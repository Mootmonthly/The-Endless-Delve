# The Endless Delve - Technical Design Document

Status: living document, Session 1 (2026-10-26). Architecture decisions recorded in
[decisions/](decisions/) are final; this document expands them. Items marked
**Proposal (needs owner sign-off):** are not yet agreed.

Related: [GDD](gdd.md), [Roadmap](roadmap.md), [Licensing](licensing.md).

## 1. Engine and language

| Choice | Value | Why |
|---|---|---|
| Engine | Godot 4.5 stable | Free, MIT licensed, strong 2D, headless mode for dedicated servers. See [ADR-0001](decisions/ADR-0001-godot-gdscript.md). |
| Language | GDScript only | One language for client, server and tests; approachable for a small team. |
| Typing | Static typing everywhere | `var hp: int`, `func roll(n: int) -> int`, `Array[Creature]`. Catches errors at parse time and is faster at runtime. |
| Renderer | `gl_compatibility` | 2D only; widest hardware support including older laptops. |
| Project features | `config/features` includes `"4.5"` | Locks the project to the 4.5 API. |

Coding conventions: `snake_case` files and functions, `PascalCase` `class_name`s, one class per file,
`@export` only on scene-facing nodes, no `preload` of other core scripts inside `src/core` (use
`class_name` references).

## 2. High-level architecture

```
  +-------------------+        ENet (UDP)        +--------------------------------+
  |  Client (Godot)   |  intents  --------->     |  Instance Server (headless     |
  |  src/client       |                          |  Godot, one process =          |
  |  rendering, input |  <---------  results     |  one 5-floor instance)         |
  |  UI, interpolation|        snapshots         |  src/server + src/core         |
  +-------------------+                          +---------------+----------------+
                                                                 |
                                         later (M5+)             |  HTTPS / internal
                                  +------------------+     +-----+---------------+
  Client --- queue/lobby -------> |   Matchmaker     |---->|   Persistence       |
                                  | assigns instance |     |   service           |
                                  +------------------+     |   (characters, DB)  |
                                                           +---------------------+

  Offline mode: Client + Instance Server code in ONE process, connected by a local transport.
```

## 3. Module layering

```
          src/core      pure rules engine, depends on nothing
             ^
             |
          src/shared    network message types, content ids, transport interface
           ^      ^
           |      |
  src/server      src/client
```

**Dependency rule:** an arrow means "may depend on". `src/core` depends on nothing (no `Node`, no
scenes, no autoloads, no engine singletons other than plain value types). `src/shared` depends only on
`src/core`. `src/server` and `src/client` depend on `src/shared` and `src/core`, and never on each other.
Offline mode wires a client and a server together in `scenes/`, which is the only place both are
referenced. A CI check (proposal) greps `src/core` for `extends Node`, `get_tree`, `randi`, `randf` and
autoload names, and fails the build on any hit.

| Directory | Contents | Base types |
|---|---|---|
| `src/core/rng` | Seeded RNG wrapper | `RefCounted` |
| `src/core/dice` | Dice expressions, advantage/disadvantage | `RefCounted` |
| `src/core/rules` | Abilities, proficiency, character sheet, leveling, rests | `RefCounted` |
| `src/core/combat` | Initiative, encounter state machine, attack/damage resolution | `RefCounted` |
| `src/core/content` | Loaders that turn `data/*.json` into typed definitions | `RefCounted` |
| `src/shared` | Intent/result message classes, serialisation, transport interface | `RefCounted` |
| `src/server` | Instance server nodes, floor simulation, RPC endpoints | `Node` |
| `src/client` | Scenes, rendering, input, UI | `Node`, `Control` |

## 4. The pure rules engine

See [ADR-0002](decisions/ADR-0002-pure-deterministic-rules-core.md).

- Every class in `src/core` extends `RefCounted` and declares a `class_name`.
- No randomness except through an injected RNG object (a wrapper around `RandomNumberGenerator`
  constructed with an explicit seed). No `randi()`, `randf()`, `randomize()` or global RNG state.
- No wall clock, no frame time, no `Time` or `OS` calls. Time is a parameter (rounds, turns, ticks).
- Rules arithmetic uses `int`. Floats are not used for rules outcomes (distances in feet and tiles are
  integers; 1 tile = 5 ft).
- Functions return result objects rather than emitting signals or mutating global state. Every roll is
  recorded in the result (die size, raw values, modifiers, total) so clients can show it and tests can
  assert on it.

**Why:** the same code then runs unchanged on the authoritative server, inside the offline client and in
headless tests. Given the same seed, content and inputs, an encounter produces the same transcript on
every machine, which makes bugs reproducible from a log (seed + intent list), enables replay tests and
lets us later verify disputed outcomes.

**Seeding proposal (needs owner sign-off):** each encounter gets its own RNG seeded from
`hash(instance_seed, floor, encounter_serial)`; the instance seed comes from a cryptographic source at
instance boot and is never sent to clients during play (otherwise clients could predict rolls).

## 5. Encounter state machine

Owned by the server; lives in `src/core/combat` as a pure state machine and is driven by the server's
encounter controller node in `src/server`. Clients only ever see the state through results.

```
 Exploring --(hostile awareness / attack intent)--> EncounterForming
 EncounterForming --(region fixed, participants collected)--> RollInitiative
 RollInitiative --(order sorted)--> TurnStart
 TurnStart --(start-of-turn effects, death saves done)--> AwaitingAction
 AwaitingAction --(valid intent | AI decision | timer expired)--> Resolving
 Resolving --(result applied; turn resources remain)--> AwaitingAction
 Resolving --(end turn | no resources left)--> TurnEnd
 TurnEnd --(end condition not met)--> TurnStart   (next creature; new round wraps)
 TurnEnd --(end condition met)--> EncounterEnd
 EncounterEnd --(survivors released to real time)--> Exploring
```

| Event | Raised by | Allowed in states | Effect |
|---|---|---|---|
| `participant_joined` | Server floor simulation | any except `EncounterEnd` | Roll initiative, insert into order. |
| `participant_left` | Server (flee, disconnect timeout, death finalised) | any | Remove from order; adjust current index. |
| `intent_received` | Network layer, validated | `AwaitingAction` (or reaction window) | Only from the creature whose turn it is (or a reacting creature). |
| `ai_decided` | Server monster AI | `AwaitingAction` | Same path as a player intent. |
| `turn_timer_expired` | Server timer | `AwaitingAction` | Default action (Dodge), then end turn. |
| `reaction_window_closed` | Server timer or response | `Resolving` | Continue resolution. |

**Who may transition:** only the server. The core state machine exposes methods such as
`begin(participants)`, `submit(intent) -> Result`, `advance() -> Result`; it rejects calls that are not
legal in the current state with an error result, never by crashing. Clients can never move the state
machine; they can only submit intents that the server may reject.

## 6. Networking

See [ADR-0003](decisions/ADR-0003-server-authoritative-instance-per-process.md).

- Godot high-level multiplayer API over `ENetMultiplayerPeer`. The server is peer 1 and the authority
  for every node in the instance.
- **Intents, not outcomes:** clients send what they want to do; the server validates, resolves (rolling
  all dice) and broadcasts results. Clients never roll dice and never decide hits, damage or loot.

### 6.1 RPC conventions

| Direction | Annotation | Use |
|---|---|---|
| Client to server | `@rpc("any_peer", "call_remote", "reliable")` | Intents: move target, attack, cast, end turn, chat. |
| Server to clients | `@rpc("authority", "call_remote", "reliable")` | Results that must arrive: encounter events, rolls, damage, inventory. |
| Server to clients | `@rpc("authority", "call_remote", "unreliable_ordered")` | Exploration position snapshots. |

Note that a bare `@rpc("authority")` defaults to `unreliable`; always spell out the transfer mode.
Every intent handler starts by reading `multiplayer.get_remote_sender_id()`, maps it to the character it
controls, and rejects anything that character may not do. RPC arguments are plain `Dictionary`/`Array`
payloads produced by message classes in `src/shared` (`to_dict()` / `from_dict()`), each with a message
`type` and protocol `version`.

**Channels proposal (needs owner sign-off):** channel 0 for encounter traffic, channel 1 for exploration
snapshots, channel 2 for chat, so chat bursts never delay combat results.

### 6.2 Tick model

**Proposal (needs owner sign-off):**
- The server simulates exploration at a fixed 20 ticks per second (`_physics_process` at 20 Hz on the
  server only).
- Movement is tile-based: clients send a target tile (or a direction held); the server pathfinds on the
  floor's navigation grid, moves the character at its exploration speed, and broadcasts positions.
- M1 has **no client-side prediction**. Clients interpolate between the last two snapshots (100 ms
  buffer). This adds visible latency to movement but removes reconciliation code. Prediction for the
  local player is reconsidered in M3 if playtests demand it.
- Encounters are event driven, not tick driven: nothing happens until an intent, AI decision or timer.

### 6.3 Voice and global chat (M5)

- **Proximity voice** rides beside the game transport, not inside it. Candidates: Steam Voice through a
  Steamworks GDExtension (cheapest, Steam-only, matches the platform choice) or a WebRTC/Opus mesh. Either way
  the instance server stays the authority on *who can hear whom*: each tick it computes, per player, the set of
  audible peers from tile distance and a wall-occlusion test on the floor's walk map, and sends that set with a
  gain factor; the voice layer only mixes what the server allows. Voice packets never pass through the core.
- **Global text chat** is a hub-server channel fanned out to every safe zone hub of the same server type via a
  small chat relay service (M5). Text passes through the profanity filter and the report pipeline; rate limited
  per account.
- Decision deferred to an ADR in M5 after a bandwidth test at 100 players.

## 7. Offline mode

The offline game runs the instance server and the client in one process. Because Godot's
`OfflineMultiplayerPeer` makes the local process peer 1 and does not deliver `call_remote` RPCs to
itself, offline mode uses a **transport interface** defined in `src/shared`:

| Transport | Used by | Behaviour |
|---|---|---|
| `NetTransport` | Online client and server | Sends message dictionaries through the RPC endpoints above. |
| `LocalTransport` | Offline mode | Delivers the same message dictionaries by direct method call (deferred one frame). |

Server logic is written against the transport, so the server code path is identical online and offline.
The offline "server" runs PVE rules with one party and no turn timer.

## 8. Instance lifecycle

1. **Boot:** `godot --headless --main-pack ted_server.pck -- --instance-id=<id> --floors=6-10
   --mode=pvp --port=<port>`. The server loads and validates all content (section 9), loads the five
   floor scenes, seeds the instance RNG and opens the port.
2. **Admission (revolving door):** a joining party is admitted only onto the first floor of the instance
   and only while population < capacity (proposal: 100 on PVP, 5 on PVE). Until the matchmaker exists
   (M5) admission is "first come" with a join token from command line or config.
3. **Running:** parties move between floors 1-5 of the instance; the final staircase hands the party to a
   safe zone (in M3, a stub: the server records the hand-off and disconnects them with a save).
4. **Shutdown:** when the instance has been empty for 5 minutes (proposal), or on operator signal, the
   server persists state and exits with code 0. A crash exits non-zero; the orchestrator restarts it.

## 9. Data pipeline

See [ADR-0004](decisions/ADR-0004-srd-only-content.md).

- Content lives as JSON under `data/`: `classes/`, `ancestries/`, `weapons/`, `items/`, `spells/`,
  `loot/` and `monsters/` (later conditions). One record per file, file name equals the record `id`.
  Floors (`floors/*.json`) reference monsters by id and loot tables by id (`chests`); monsters name a
  `loot_table`; class kits, loot entries and spell lists reference item and spell ids.
  `tests/content/` checks every reference and the SRD numbers.
- **Icons:** `tools/gen_tileset.py` also writes `assets/icons/entity_icons.png` (one row of 32x32 icons),
  `entity_icons.tres` (TileSet, atlas source 0) and `entity_icons.json`, whose `icons` map an id (class id,
  monster id, item kind, `potion`, `chest_closed`, `chest_open`) to its atlas column.
- **Schema conventions:** every record has `id` (lowercase `snake_case`, unique per kind),
  `schema_version` (integer), `name`, and `source` (for example `"SRD 5.1"`). Units are explicit in key
  names (`speed_ft`, `range_ft`). Dice are strings in standard notation (`"1d8"`, `"2d6+3"`).
- **Loading:** loaders in `src/core/content` parse JSON into typed definition objects (`ClassDef`,
  `MonsterDef`, ...). They validate required keys, types, enum values and cross-references (for example a
  monster's attack names a known damage type) and return a list of errors instead of partial data.
- **Boot validation:** server and offline client refuse to start if any content error exists. A test
  loads the whole `data/` tree on every CI run.
- **Content versioning:** at boot the loader computes a content hash over all files. The client sends its
  hash on connect; the server rejects mismatches with a "please update" message. `schema_version` bumps
  require a migration note in the loader.

## 10. Persistence

Out of scope for M0-M2 beyond local offline saves.

**Proposal (needs owner sign-off):**
- A thin persistence service in front of PostgreSQL. Instance and hub servers are its only clients
  (never game clients). Accounts, characters, deepest-floor records and cosmetics are rows; the
  character sheet itself is a versioned JSON document (`jsonb`) with `schema_version`.
- Writes happen at checkpoints: floor change, safe zone entry, trade completion, death finalised.
- Offline saves are versioned JSON files in `user://saves/`, signed with HMAC-SHA256. The key ships in
  the client, so this only deters casual editing; offline characters can never be imported online,
  which limits the value of tampering.

## 11. Floor authoring

**M1 decision (2026-10-26):** floors are authored as JSON text files (`floors/floor_NNN.json`) holding an ASCII
tile grid (`#` wall, `.` floor, `A` arrival, `S` stairs) plus marker data (encounter zones with monster ids and
spawn points). `FloorFile` in `src/shared` turns a file into `FloorData`, and `FloorView` builds the
`TileMapLayer`s from it at load. This keeps floors diffable and lets the headless validator run without the editor.

**Set 1 (2026-10-26):** floors also carry optional `floor_number`, `theme` and a content-only `budget`
(`{"level", "min", "max"}`, read by content tests, ignored by the rules); zones carry optional `kind`
(`pack` / `ambush` / `boss`), `boss` (bool) and `optional` (bool, content-only: a side area off the route).
A set manifest `floors/set_NN.json` lists a set's five floors in descent order (`FloorFile.load_set`). Each
set has a content test under `tests/content/` checking loading, budgets and stairs gating (GDD 5.4).
Hand-placed `TileMapLayer` scenes, as described below, remain the plan once the content pipeline (M6) justifies an
editor workflow; the proposal below is kept for that stage.

- Each floor is a handcrafted scene: `floors/floor_NNN.tscn` (proposal), built from `TileMapLayer`
  nodes (ground, walls, decoration) sharing a common `TileSet` with 16x16 or 32x32 px tiles.
- Gameplay markers are child nodes with editor-visible gizmos: `ArrivalLanding`, `Staircase`,
  `EncounterZone` (rect plus monster pack ids from `data/monsters`), `BossZone`, `SecretDoor` (DC values),
  `LootChest` (loot table id).
- The server builds a navigation grid (`AStarGrid2D`) from the wall layer at load, and converts markers
  into plain data passed to the core. The core never sees the scene tree.
- A floor validator (headless script, proposal for M6) checks every floor: reachable stairs, encounter
  zones inside walkable area, ids exist in `data/`.

## 12. Testing strategy

See [ADR-0005](decisions/ADR-0005-in-house-test-runner.md).

- In-house runner: `godot --headless -s tests/run_tests.gd`. It discovers `tests/**/test_*.gd`; each file
  extends `tests/test_case.gd`; every method named `test_*` runs; a summary prints; exit code is
  non-zero on any failure.
- **Naming:** `tests/core/test_dice.gd` tests `src/core/dice`; methods read as sentences:
  `test_advantage_takes_higher_roll`, `test_death_save_nat_20_restores_one_hp`.
- **Determinism tests:** fixed seeds; the same seed plus the same intents must give identical
  transcripts. Some tests pin exact roll sequences for a seed so an accidental change to RNG usage is
  caught.
- **Rules tests** quote the SRD behaviour they check in a comment.
- **CI:** GitHub Actions on every push and pull request downloads Godot 4.5 headless, imports the
  project once, then runs the runner. Server integration tests (two processes on localhost) arrive in M3.

## 13. Performance budgets

**Proposal (needs owner sign-off):**

| Budget | Target |
|---|---|
| Players per PVP instance | 100 (stretch: 150) |
| Exploration tick | 20 ticks/s, server tick work < 10 ms at 100 players |
| Encounter intent resolution | < 50 ms server time per intent, including reactions |
| Concurrent encounters per instance | 30 |
| Bandwidth per client | < 16 KB/s average during exploration |
| Server memory per instance | < 1 GB |
| Client frame rate | 60 fps on integrated graphics at 1080p |

A headless benchmark with 100 simulated clients is an exit criterion of M3.

## 14. Security and anti-cheat basics

- Never trust the client: all dice, hits, damage, loot, XP and positions are server-side.
- Validate every intent: sender owns the character, it is that character's turn (or a valid reaction),
  the action is available, target is in range and in line of sight, resources are unspent.
- Movement: server pathfinds and enforces speed; teleport or wall-clipping requests are rejected.
- Rate limit intents per peer (proposal: 30 per second exploration, 5 per second chat); disconnect on
  sustained abuse.
- Clients only receive what they may see: no monster positions or secret doors outside vision.
- The instance seed and RNG state are never sent to clients.

## 15. Build and release

- Export presets: Windows, Linux, macOS desktop clients; Linux dedicated server (Godot "Dedicated
  Server" export mode, strips visuals) for instance servers.
- Version string in `project.godot` (`application/config/version`), shown by the boot scene and sent
  on connect alongside the content hash.
- Steam integration (achievements, overlay, auth tickets) is deferred to M7 and will use a GDExtension
  wrapper of Steamworks. Storefront keyword rules are in [licensing.md](licensing.md).

## 16. Risks

| # | Risk | Mitigation |
|---|---|---|
| 1 | MMO scope is too large for a small team | Ship Offline first (M1-M2); one server type at a time; strict milestone exit criteria; Early Access with fewer than 100 floors. |
| 2 | Handcrafting 100 floors | Reusable room kit, floor validator, data-driven encounters; produce floors in batches of 5 (one instance) and playtest each batch (M6). |
| 3 | GDScript server performance at 100 players | Static typing, integer rules math, event-driven encounters, benchmark in M3; move hot paths to a GDExtension only if profiling demands it. |
| 4 | PVP fairness (level gaps, ganking) | Per-set budgets assume the level a full-clear solo reaches, keeping levels on a floor within about one of each other; arrival protection; no-PVP stairs ring; PVE servers as an alternative. |
| 5 | Licensing (non-SRD content or trademarks leak in) | SRD-only content rule, `source` field on every record, CI grep for banned terms, review before store launch. |
| 6 | Netcode complexity | Server authority, no prediction in M1, turn-based combat, one transport interface shared with offline mode. |
| 7 | Persistence and data loss | Versioned JSON character documents, checkpoint writes, migrations tested in CI, backups before EA. |
| 8 | Scope creep | Pillars in the GDD as a filter; anything not in the current milestone goes to the backlog; ADRs for any architectural change. |
| 9 | Voice chat cost and moderation | Server-decided audibility sets, push-to-talk default, per-player mute, bandwidth test before committing to a stack, legal review of any voice buffering. |

# The Endless Delve - Roadmap

Milestones are ordered, not dated. A milestone is done only when every exit criterion is met and
checked into the repo (tests green in CI). See [GDD](gdd.md) and [TDD](tdd.md) for the design behind
each item.

| Milestone | Name | One-line goal |
|---|---|---|
| M0 | Bootstrap | Repo, docs, pure rules core with tests, CI. |
| M1 | One Floor Offline | Play one handcrafted floor offline with real-time movement and a turn-based fight. |
| M2 | Five Floors + Rests + Death | A full offline instance with boss, rests, permadeath and saves. |
| M3 | Multiplayer Instance | Headless server, 5-player party, PVE rules, revolving door. |
| M4 | Spells, Classes Wave 2, Loot | Full SRD class roster, spellcasting, magic items. |
| M5 | PVP + Safe-zone Social + Matchmaker | PVP servers, social hubs, queueing. |
| M6 | Content Production Pipeline | Tools and process to build all 100 floors. |
| M7 | Steam Early Access | Shippable build on Steam. |

## M0 - Bootstrap

- **Goal:** a repository that any contributor (human or agent) can clone, understand and test.
- **In scope:** `project.godot` (Godot 4.5, `gl_compatibility`), repo hygiene files, `CLAUDE.md`, these
  docs and ADRs, `src/core` rng, dice, abilities, proficiency, character sheet basics, initiative and a
  first encounter state machine, SRD JSON for wave-1 classes and a few monsters, in-house test runner,
  GitHub Actions CI.
- **Out of scope:** any rendering, networking, floors, persistence.
- **Exit criteria:**
  - `godot --headless -s tests/run_tests.gd` exits 0 locally and in CI.
  - Determinism test: the same seed produces the same dice sequence and initiative order.
  - `src/core` contains no `Node`, scene, autoload or global RNG usage.
  - Docs index lists GDD, TDD, roadmap, licensing and five ADRs.
- **Key risks:** code written without a runnable Godot in the authoring sandbox may have syntax
  errors; first CI run is the real check.

## M1 - One Floor Offline

- **Goal:** prove the core feel: walk a floor in real time, drop into a 5e fight, win, take the stairs.
- **In scope:** minimal character creator (wave-1 class, SRD ancestry, standard array, name); one
  handcrafted floor built from `TileMapLayer`; real-time tile movement; one encounter type (a melee
  monster pack in an authored zone) with initiative, movement, Attack, Dash, Dodge, Disengage,
  opportunity attacks and melee weapon attacks; death saves; stairs; short rest with Hit Dice; offline
  `LocalTransport` running server code in-process.
- **Out of scope:** spells, ranged combat polish, bosses, saving, multiplayer, loot beyond starting gear.
- **Exit criteria:**
  - A new player can create a Fighter and reach the stairs in one sitting without a crash.
  - Encounter resolution is driven only by intents; a test replays a recorded intent log to the same result.
  - Joining an encounter in progress inserts the newcomer into initiative correctly (unit tested).
  - Short rest on stairs spends Hit Dice per SRD (unit tested).
- **Key risks:** real-time to turn-based transition feeling jarring; tile movement feel.

## M2 - Five Floors + Rests + Death

- **Goal:** a complete offline instance with the full death loop.
- **In scope:** floors 1-5; one boss encounter per floor with boss gating of the stairs; safe zone 1 with
  long rest and milestone level-up to 2; permadeath and party-wipe rules; reset to floor 1; offline save
  and load (versioned, HMAC-signed JSON); Rogue, Cleric and Wizard playable with cantrips and a minimal
  set of level-1 spells needed for Cleric and Wizard to function.
- **Out of scope:** full spell lists, multiplayer, trading.
- **Exit criteria:**
  - A party can play floors 1-5, reach safe zone 1 and level up to 2.
  - Full death and party wipe both reset the character (integration tests with fixed seeds).
  - Save, quit, load restores the exact character state; a tampered save is rejected.
- **Key risks:** difficulty tuning; save schema churn.

## M3 - Multiplayer Instance

- **Goal:** the same instance, online, with a real party.
- **In scope:** headless instance server (dedicated server export), `NetTransport`, intent validation,
  5-player party, PVE server rules (one party per instance), revolving-door admission onto floor 1,
  disconnect handling, turn timer, snapshot interpolation, 100-simulated-client benchmark.
- **Out of scope:** PVP, matchmaker (servers are joined by address and token), persistence service.
- **Exit criteria:**
  - Five clients on separate machines complete floor 1 together.
  - Every intent type has a server-side rejection test for invalid senders and illegal actions.
  - Benchmark: 100 simulated clients at 20 ticks/s with tick work under 10 ms.
  - An empty instance shuts itself down cleanly.
- **Key risks:** GDScript server performance; latency on reactions.

## M4 - Spells, Classes Wave 2, Loot

- **Goal:** the full SRD character experience.
- **In scope:** spellcasting system (slots, concentration, areas, saving throws, conditions); the
  remaining SRD classes and subclasses; levels 1-20 data; SRD magic items, attunement, loot tables,
  secret loot rooms; merchant in safe zones.
- **Out of scope:** PVP, trading between players.
- **Exit criteria:**
  - All twelve SRD classes can be created and levelled 1-20 in a headless test.
  - Every shipped spell has at least one rules test.
  - A content lint confirms every record has a `source` and no banned terms.
- **Key risks:** spell edge cases explode in number; spells that break a shared dungeon.

## M5 - PVP + Safe-zone Social + Matchmaker

- **Goal:** the MMO layer.
- **In scope:** PVP server rules (engagement, arrival protection, stairs no-PVP ring); safe zone hub
  servers with the global text chat, trade and regrouping; proximity voice chat inside instances
  (distance falloff, wall occlusion, push-to-talk, mute); matchmaker service; persistence service with
  PostgreSQL; accounts; report and block tools for text and voice.
- **Out of scope:** Steam payments and cosmetics store.
- **Exit criteria:**
  - A party queues in a safe zone, is placed in an instance, finishes it and arrives in the next safe zone.
  - Trades are atomic and logged; a killed server loses no completed trade.
  - PVP engagement and arrival protection behave as specified (integration tests).
  - Two players on the same floor hear each other only inside the hearing radius, and not through walls;
    a muted player is silent for the muter. Global text chat reaches every safe zone of the same server type.
- **Key risks:** griefing (now including voice harassment); voice bandwidth and relay cost; data loss.

## M6 - Content Production Pipeline for 100 floors

- **Goal:** make building floors 6-100 a repeatable process.
- **In scope:** room kit and tile sets per depth band, floor validator, encounter budget calculator,
  automated playthrough bot for reachability, content review checklist, batch production of instances.
- **Out of scope:** postgame floor 101.
- **Exit criteria:**
  - Floor validator runs in CI on every floor scene.
  - At least two new instances (10 floors) built using only the pipeline, each playtested.
  - A measured floors-per-week rate is recorded so the owner can plan the remaining floors.
- **Key risks:** production rate too low; visual monotony across 100 floors.

## M7 - Steam Early Access

- **Goal:** paying players.
- **In scope:** Steamworks integration, store page (keywords reviewed per licensing.md), cosmetics store,
  crash reporting, server operations runbook, launch content (proposal: floors 1-25 plus safe zones).
- **Out of scope:** floors not yet produced; floor 101.
- **Exit criteria:**
  - Licensing review checklist completed and signed off by the owner.
  - Closed beta of at least 50 players with no blocker bugs open.
  - Backups and restore of the persistence database tested.
- **Key risks:** launch load; negative reviews from content gaps; trademark misuse on the store page.

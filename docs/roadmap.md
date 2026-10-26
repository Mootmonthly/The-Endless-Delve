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
| M4 | Spells, Classes Wave 2, Loot | Full SRD class roster to level 20, full spellcasting, magic items. |
| M5 | PVP + Safe-zone Social + Matchmaker | PVP servers, social hubs, queueing. |
| M6 | Content Production Pipeline | Tools and process to build all 100 floors. |
| M7 | Steam Early Access | Shippable build on Steam. |

## M0 - Bootstrap

**Status: done (2026-10-26).**

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

**Status: playable vertical slice landed 2026-10-26** (character creator, floor_001, real-time walking,
intent-driven encounters with move/Attack/Dash/Dodge/Disengage/opportunity attacks/death saves, monster AI,
stairs, short rest, in-process server over LocalTransport, replay test). Remaining before M1 exits: human
playtest of feel and balance, monster health bars and cleared-zone display. GDD open question 19 was
resolved by the owner on 2026-10-26 (GDD 5.4, 8.3, 9.3).

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
- **In scope:** the first five-floor set, "The Barrow Warrens" (GDD 5.4: `floors/set_01.json`,
  `floor_001`-`floor_005`, SRD budgets checked by `tests/content/test_set_01.gd`), with required zones
  gating each floor's stairs and the set boss (an ogre) guarding the stairs on floor 5; XP from kills split
  across the party, leveling within the set (GDD 8.3); safe zone 1 with long rest; permadeath and
  party-wipe rules with death saves before the wipe (GDD 9.3); reset to floor 1; offline save and load
  (versioned, HMAC-signed JSON); Rogue, Cleric and Wizard playable with cantrips and a minimal set of
  level-1 spells needed for Cleric and Wizard to function.
- **Landing early (2026-10-26, during M1 close-out):** floor progression (stairs load the next floor of
  the set; the last floor's stairs give a long rest and end the set), XP awards and level-ups, death saves
  before the wipe, and the five floors' content. What remains for M2 is the rest of the list above: the
  safe zone itself, saves, the extra classes and spells, and tuning from playtests.
- **Items, spells, loot, twelve classes (playtest round 1, 2026-10-26):** the owner's first playtest asked
  for inventory, potions, throwing weapons, spells for the Wizard, visible armor, chests by the stairs,
  monster drops, icons and faster early levels. Added: SRD items (`data/items/`: 19 weapons, 10 armors,
  shield, potions, ammunition, gold, tools) and a Tab inventory with equip slots (GDD 8.5); starter kits
  per class; SRD spells (`data/spells/`: 9 cantrips, 14 level-1 and 8 level-2 spells, of which the area and
  condition spells are data only) with ranged, thrown and spell attack rules (GDD 7.6); loot tables
  (`data/loot/`) for chests and monster drops, a `starter_gear` chest by every staircase and a hidden
  chest in every side area; a floor-clear bonus of 100 XP per floor (budgets in GDD 5.4 updated: floor 2 is
  now planned at level 2); class, monster and item icons (`assets/icons/`); and data for an interactive
  level-up screen (GDD 8.6).
- **Wave 2 landed early (owner request):** all twelve SRD classes are playable at level-1 depth (GDD 8.2):
  Barbarian, Bard, Druid, Monk, Paladin, Ranger, Sorcerer and Warlock join the wave-1 four with their
  level-1 fight mechanics (Rage, Unarmored Defense, Martial Arts, Lay on Hands, Bardic Inspiration, Pact
  Magic, Sneak Attack, Second Wind) and spells; the remaining features are flavour until M4.
- **Progression to 20, round A (owner decision, 2026-10-26):** every class's full SRD progression is in
  the data now, imported by `tools/import_srd.py` (GDD 8.2, 8.7): features 1-20 for all twelve classes
  and their SRD subclass, slot tables to 20, 320 spells, invocations, metamagic, fighting styles, every
  SRD monster with an attack roll, all SRD equipment and magic items. Mechanics land in tiers; this round
  is the shared systems (conditions, concentration, multiple attacks, areas, upcasting) and every feature
  through level 5. Features above that say "not yet modelled" (`"mechanic": "unsupported"`).
- **Out of scope:** multiplayer, trading. (Full spell lists, areas, conditions and subclasses moved into
  the progression-to-20 work above.)
- **Exit criteria:**
  - A party can play floors 1-5 and reach safe zone 1, leveling from XP on the way (GDD 5.4 expects a
    full-clear solo to reach level 4 and a party of three level 3).
  - **Proposal (needs owner sign-off):** a playtest bot run on every floor of the set (solo at the assumed level, and a party of three) is
    recorded in GDD 5.4, replacing the floor-1-only measurement.
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
- **In scope:** spellcasting system (concentration, areas, conditions; slots, saving throws and the
  twelve classes at level-1 depth landed early in M2); subclasses and class features above level 1;
  Paladin and Ranger spellcasting; levels 1-20 data; SRD magic items, attunement, loot tables,
  secret loot rooms; merchant in safe zones. Already landed: the levels 1-20 data, subclass data and the
  SRD magic item records (round A of progression to 20, M2 above); features above level 5, magic item
  effects and attunement remain.
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

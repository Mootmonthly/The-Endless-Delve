# CLAUDE.md — working in The Endless Delve

The Endless Delve (TED) is a 2D top-down dungeon-crawling MMO for Steam, built
in Godot 4.5 with GDScript, whose rules come from the 5e SRD: 100 handcrafted
floors, five-floor instances of ~100 players, permadeath back to floor 1.

Read `docs/gdd.md` (design), `docs/tdd.md` (technical design),
`docs/roadmap.md` (milestones) and `docs/licensing.md` before large changes.
Decisions are recorded as ADRs in `docs/decisions/`.

## Architecture decisions (settled — change only via a new ADR)

1. **Engine:** Godot 4.5 stable, GDScript only, static typing everywhere.
   Renderer `gl_compatibility` for 2D and broad hardware support.
2. **Rules first:** `src/core/` is a pure, deterministic rules engine.
   `RefCounted` classes with `class_name` only — never `Node`, scenes,
   autoloads, or `randi()`/global RNG. All randomness comes from an injected
   seeded RNG object, so the same code runs on server, offline client and tests.
3. **Server-authoritative multiplayer:** one headless Godot process = one
   dungeon instance (5 floors, ~100 players), high-level multiplayer over ENet.
   Clients send intents; the server rolls, resolves and broadcasts.
   Offline mode runs the server code in-process (offline `MultiplayerPeer`).
4. **Exploration vs combat:** exploration is real-time; combat is turn-based
   inside an encounter (bounded tile region with its own initiative order).
   Entities entering the region join initiative. Server-owned state machine.
5. **Data-driven content:** classes, monsters, items, spells are JSON under
   `data/`, loaded into typed definition objects. Floors are handcrafted
   scenes / TileMapLayers.
6. **Licensing:** rules from SRD 5.1 / 5.2 (CC-BY-4.0) only. See below.
7. **Tests:** in-house runner, no third-party framework. CI on GitHub Actions.
8. **Godot in the agent sandbox:** cloud sessions in Auto mode cannot execute
   a Godot binary downloaded mid-session. The environment setup script runs
   `bash tools/install_godot.sh` (installs 4.5-stable to `/opt/godot/godot`).
   If `/opt/godot/godot` is missing, say so rather than working around it, and
   let CI be the first real run.

## Repository layout

```
project.godot              Godot 4.5 project (no autoloads; InputMap actions, audio buses)
scenes/                    main (boot + settings/pause overlay), ui/ (creator, settings,
                           level-up), game/ (game scene, HUD, entity layer), floor/ (FloorView)
src/core/                  pure rules engine (RefCounted only)
  rng/ dice/ grid/ rules/ combat/ spells/ items/ floors/ content/
src/server/                authoritative instance server (InstanceServer, 20 Hz)
src/client/                view-model (ClientState), drafts, settings, icons
src/shared/                Messages, Transport/LocalTransport, FloorFile
data/                      JSON content, all SRD 5.1 (+ hex from SRD 5.2):
  classes/ (12, progression to 20) ancestries/ features/ spells/ weapons/
  items/ monsters/ loot/ invocations/ metamagic/ fighting_styles/
floors/                    set manifests and JSON floors (ASCII grid + zones + chests)
assets/                    generated placeholder tiles and icons (tools/gen_tileset.py)
tools/                     install_godot.sh, gen_tileset.py, import_srd.py (SRD importer;
                           cache in tools/srd_cache/, gitignored)
tests/                     run_tests.gd, test_case.gd, core/ shared/ server/ client/
                           scenes/ content/
docs/                      gdd, tdd, roadmap, licensing, decisions/
.github/workflows/ci.yml   headless test run on push / PR
```

Regenerating data: `python3 -I tools/import_srd.py --offline --check` verifies the
converted data is deterministic and licence-clean; without `--offline` it refreshes
the cache from the SRD API. Hand-tuned records carry `"hand_edited": true` and keep
their hand-written keys.

Dependency direction: `client` -> `shared` -> `core`; `server` -> `shared` ->
`core`. `core` depends on nothing outside itself.

## Hard rules

- `src/core/` is pure `RefCounted` with injected RNG. No `Node`, no
  `get_tree()`, no signals to scene nodes, no file paths baked into rules.
  Prefer `class_name` references over `preload()` paths inside `src/core/`.
- Never use the global RNG (`randi`, `randf`, `randomize`) anywhere in rules.
- **Licensing:** use SRD content only. Never write the publisher's trademarks
  or product names, nor non-SRD monsters, spells or setting names, in code,
  data or docs. Say "5e SRD" or "SRD rules". The only exception is the
  CC-BY-4.0 attribution line in `README.md` / `docs/licensing.md`.

## Coding conventions

- Static typing on every variable, parameter and return (`-> void` too).
  Use `:=` only when the type is obvious from the right-hand side.
- Typed collections: `Array[int]`, `Array[Dictionary]`, `Dictionary[String, int]`.
- Files and folders `snake_case` (`dice_roller.gd`); `class_name` in
  `PascalCase` (`DiceRoller`); one class per file.
- Doc comments use `##` on the line above the class/member they describe.
- Constants `UPPER_SNAKE_CASE`, enums `PascalCase` with `UPPER_SNAKE` values.
- Tabs for indentation in `.gd` files (see `.editorconfig`).
- Commit the `.import` and `.uid` files Godot generates; never `.godot/`.

## Running tests

```
godot --headless --path . --import          # first time / after new assets
godot --headless --path . -s res://tests/run_tests.gd
```

The runner discovers `tests/**/test_*.gd`, runs every `test_*` method, prints
a summary and exits non-zero on any failure. CI runs the same command.

### Adding a test

1. Create `tests/<area>/test_<thing>.gd` extending the base in
   `tests/test_case.gd` (by its `class_name` if it has one, else by path).
2. Add methods named `test_<behaviour>() -> void`; use the assertion helpers
   from `tests/test_case.gd`.
3. Build any RNG from a fixed seed so results are reproducible.
4. Run the suite locally (or rely on CI) and keep it green.

## Commits

Conventional Commits: `feat:`, `fix:`, `docs:`, `test:`, `refactor:`,
`chore:`, `ci:`, optionally scoped (`feat(core): add advantage rolls`).
Small, focused commits; never commit secrets or export credentials.

## Session log

Append one entry per working session (newest last).

- **2026-10-26 — M0 bootstrap.** Created the Godot 4.5 project skeleton
  (`project.godot`, boot scene, git/editor config), CI workflow, this file
  and the README; DOCS wrote the GDD/TDD/roadmap/licensing/ADRs; RULES started
  the pure `src/core/` engine (RNG, dice, rules, combat, content loaders), the
  SRD data subset and the in-house test runner. Godot was not runnable in the
  sandbox, so CI is the first real execution.
- **2026-10-26 — M1 vertical slice.** Owner authorised running Godot in the
  sandbox (`/opt/godot/godot`). Phase A: intent-driven `Encounter` with event
  stream and replay, grid movement, `MonsterBrain`, ancestries/weapons/armor,
  `FloorData`; shared `Messages`/`Transport`/`LocalTransport`, JSON floor files,
  placeholder tileset, `FloorView`. Phase B: `InstanceServer` (20 Hz, zone
  triggers, monster turns, stairs, short rest, game over) and the client
  (`ClientState`, `CharacterDraft`, creator UI, `GameScene`, HUD). Balance pass
  found the stairs route crossed the crypt zone; walled it off and set zone 1 to
  two giant rats (see GDD open question 19). Suite: 258 tests green.
- **2026-10-26 — First five-floor set.** Owner decisions: floor 1 easy to
  floor 5 solo-lethal head-on, solos get death saves before a wipe, one theme
  per set. Core: a team stays "in the fight" while any member is conscious or
  dying; `MonsterBrain` finishes dying hostiles last. Server: XP awards on
  wins, `configure_set`, next-floor loading on the stairs, long rest +
  `SET_CLEARED` on the last floor. Content: set_01 "The Barrow Warrens"
  (floors 1-5, seven new SRD monsters, per-floor XP budgets checked by
  `tests/content`). Naive-bot curve over 20 seeds: dies on floors 1/2/3
  (9/4/7), never past floor 3 at level 1. Owner kept floor 1 at a two-rat pack:
  players are smarter than the bot. Suite: 304 tests green.
- **2026-10-26 — Items, spells, twelve classes, level-up, settings (playtest
  round 1).** Owner playtest: nothing broke, but no inventory/items, no Wizard
  spells, under-levelled, no loot. Core: items/equipment/inventory, spell
  slots and effects (spell_attack, auto_hit, save, heal, buff, multi-ray),
  ranged/thrown attacks with LOS, class features for all twelve SRD classes,
  loot tables, chests, `LevelUp.choices/apply` (gain_xp no longer
  auto-levels). Content: 42 items, 31 spells, 8 new classes, chests by every
  staircase plus hidden caches, floor-clear XP bonus (100), icon atlas; witch
  bolt dropped (not SRD), hex is SRD 5.2 (attribution added). Server: item and
  chest intents, drops, LEVEL_UP_AVAILABLE/level_up round trip. Client: Tab
  inventory, Spells/Features/attack pickers with targeting, level-up screen,
  settings menu with rebinding and volume, InputMap actions. Suite: 482 green.
- **2026-10-26 — Progression to 20, round A.** Owner: "add literally
  everything". `tools/import_srd.py` imports the whole SRD 5.1 dataset
  (12 classes to level 20 with subclasses, 192 features, 320 spells, 329
  monsters, 540 items, invocations, metamagic, fighting styles). Core adds
  conditions, concentration, multiattack/Action Surge/two-weapon fighting,
  areas of effect (sphere/cube/cone/line), slots to 9 with upcasting,
  fighting styles, every class feature through level 5 (`Features.IMPLEMENTED`
  is the source of truth; the importer syncs data/features `mechanic` from
  it), and LevelUp choice types (subclass, style, expertise, invocations,
  metamagic, feature options, skills). Also: offline-only pause, a private
  Feat Workshop artifact for original feats (SRD has only Grappler). Suite:
  576 green. Next: round B (levels 6-12), round C (13-20), UI exposure.
- **2026-10-26 — Progression round B + UI exposure.** UI: conditions,
  concentration, attack counters, resources, attack options, area footprints,
  metamagic/upcast pickers, every level-up choice type, creation choices.
  Core round B: ability checks/contests, hide/stealth/invisibility,
  shove/grapple, generalised reactions with `reaction_policy`, summons and
  companions, teleport/fly moves, tile effects (walls, zones), exhaustion,
  revive spells, all metamagic, lite wild shape/polymorph, `SpellEffects`
  overrides (157 of 320 spells castable; 163 remain unsupported, grouped
  in the round B report: utility/exploration, terrain the grid can't hold,
  compulsion, unmodelled summons, illusions, special outcomes), every class
  feature for levels 6-12 except pact_of_the_chain/tome and slow_fall.
  Suite: 673 green. Paused by owner before round C (levels 13-20).
- **2026-10-26 — Out-of-combat casting + reactions UI.** `cast` is a dual
  intent: out of combat it runs `OutOfCombat.cast` (companions such as Find
  Familiar and Animate Dead, heals, revives, buffs; long casting times and
  rituals resolve at once in M2), result `out_of_combat_events`, intent
  `dismiss_companion`; HUD Companions line; Reactions popup reachable from
  the pause menu, policies persist per player across floors. Core gaps noted
  for round C: `OutOfCombat.castable`, event emission and per-target keys in
  OutOfCombat, ritual casting, core-owned companion ids, a core table of
  reactions per trigger. Suite: 689 green.
- **2026-10-27 — Progression round C + Round D1.** Core round C: terrain
  and walls, compulsion/control/banishment, illusions, remaining summons,
  special-outcome spells, exploration hooks (`exploration_effect`,
  `no_effect`, light/darkness, locked chests), pacts of the chain/tome and
  all 32 invocations, every level 13-20 feature and capstone. Coverage:
  192/192 features, 320/320 spells castable (268 with a mechanic, 52
  declared no_effect), 32/32 invocations. Round D1: floor format v2
  (landings, doors, props, respawn, zone flags), `tools/gen_floor.py`
  concentric generator, set_01 regenerated at 112x80/128x96 with 4-6
  landings, `tools/build_tiles.py` art refresh (autotiled walls, floor
  variants, doors, props, torch lighting, vignette; CC0 Kenney pieces with
  provenance). Suite: 831 green. Next: D2 + round C UI (one agent).
- **2026-10-27 — Round D2 + round C UI.** Server: seeded landing
  assignment, doors (open/close/unlock by tools, key or Knock) and
  breakable props that block paths, sight and fight maps, pack and boss
  respawns on timers (never with a player in the zone), exploration_effect
  resolution (unlock/open/reveal/light/teleport/recall), control intent
  for dominated creatures, fight light from the floor. Client: click doors
  and props, terrain overlay (walls, darkness, difficult ground, zones),
  unseen/banished/illusion rendering, control panel, ritual toggle,
  "no effect in the delve" label, familiar/Overchannel/Quivering Palm/Hurl
  Through Hell options, new level-up sections, a Dynamic lighting setting.
  Gaps for later: no object targets in fights, logged mid-fight map edits,
  move-only blockers, floor light levels, tool proficiencies on sheets,
  key items, Messages lacks hide/search/shove/grapple/help/move_effect
  validation. Suite: 886 green.
- **2026-10-27 — Playtest round 2 fixes.** Window opens maximized with a
  Window mode setting; creator unclipped (Start under Suggested scores,
  scrolling columns); ability score methods: standard array, point buy,
  rolled. Door keys: six key items, props carry guaranteed `drops`, the
  generator pairs about half the locked doors with a crate or barrel holding
  the key (reachable without passing any locked door, unique colour per
  floor), keys are consumed and lost on descent. Chest loot: category-roll
  loot tables (gear + potions + gold + optional supplies), chest_stairs_t1/t2
  and cache_t1/t2 by floor, nine +1 items with bonuses applied on equip.
  Suite: 929 green.

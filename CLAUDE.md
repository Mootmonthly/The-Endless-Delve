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
8. **Godot may be unavailable in an agent sandbox:** cloud sessions in Auto
   mode cannot execute a Godot binary downloaded mid-session. Preinstall it via
   the environment setup script (download the 4.5-stable Linux zip, unzip,
   chmod +x) or allow it in `.claude/settings.json`; otherwise write carefully,
   re-read for GDScript 4.5 syntax, and let CI be the first real run.

## Repository layout

```
project.godot              Godot 4.5 project (no autoloads)
scenes/main.tscn, main.gd  minimal boot scene
src/core/                  pure rules engine (RefCounted only)
  rng/ dice/ rules/ combat/ content/
src/server/                authoritative instance server (stub)
src/client/                presentation only (stub)
src/shared/                network message definitions (stub)
data/                      JSON content (SRD subset): classes/, monsters/
tests/                     run_tests.gd, test_case.gd, core/test_*.gd
docs/                      gdd, tdd, roadmap, licensing, decisions/
.github/workflows/ci.yml   headless test run on push / PR
```

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
  (9/4/7), never past floor 3 at level 1; floor 1 zone 1 reduced to one giant
  rat. Suite: 304 tests green.

# src/core — pure rules engine

Deterministic 5e SRD rules shared by the authoritative server, offline mode and headless tests.

## The purity rule
- Every class is `class_name X` + `extends RefCounted`. No `Node`, scenes, autoloads or signals to the scene tree.
- No global randomness (`randi()`, `randf()`, `randomize()`). Anything random takes an injected `Rng`.
- Reference other core classes by `class_name`, not `preload` paths.
- Rules text and data come from the SRD 5.1 (CC-BY-4.0) only. Say "5e SRD" / "SRD rules".

## Module map
| Folder | Contents |
|---|---|
| `rng/` | `Rng`: seeded wrapper (`next_int` inclusive, `next_float`, `fork`, `state`/`set_state`) |
| `dice/` | `DiceExpr` ("2d6+3", "4d6kh3"), `DiceRoll`, `D20` (advantage/disadvantage), `D20Result` |
| `rules/` | `Ability`, `AbilityScores`, `Skill`, `Proficiency`, `Experience`, `ClassDefinition` (+ starting gear), `AncestryDefinition`, `WeaponDefinition`, `CharacterSheet` (armor_base / armor_max_dex / shield_bonus, weapon `attacks`), `CharacterBuilder`, `Rest`, `DamageOutcome`, `DeathSaveOutcome` |
| `grid/` | `GridMath` (Chebyshev distance, adjacency, `[x, y]` <-> `Vector2i`), `WalkMap` (walkable tiles, `can_step` without corner cutting, BFS `reachable` / `path_to`) |
| `floors/` | `FloorData` (walk map, arrival, stairs, zones, `validate()`), `EncounterZoneData` |
| `combat/` | `Combatant` (grid position + per-turn resources), `MonsterDefinition`, `InitiativeTracker`, `AttackResolver`, `AttackResult`, `Encounter` (intent-driven FORMING → ACTIVE → ENDED, events, intent log, `replay`), `MonsterBrain` (deterministic melee AI) |
| `content/` | `ContentLoader` (data/*.json → definitions: classes, monsters, ancestries, weapons), `DictUtil` (JSON-safe readers) |

## Grid conventions
Tiles are `Vector2i` (x right, y down), one tile = 5 ft, 8-directional movement where every step costs
1 tile, distance = Chebyshev. Melee reach is 1 tile (diagonals included). A diagonal step may not cut a
wall corner. On the wire positions are `[x, y]` int arrays (`GridMath.vec_to_arr` / `arr_to_vec`).

## Driving an encounter
```gdscript
var enc := Encounter.new("z1", Rng.new(seed), floor_data.walk_map, zone.rect)  # FRESH Rng
enc.add_combatant(pc)            # positions must be inside the region, walkable, unoccupied
enc.start()                      # events: combatant_joined..., encounter_started, round_started, turn_started
var res := enc.submit({"v": 1, "type": "move", "actor": pc.id, "path": [[3, 4], [4, 4]]})
# res = {"ok": bool, "error": String, "events": [...]}; rejected intents change nothing and are not logged
for intent in MonsterBrain.decide(enc, enc.current_actor().id):  # monsters' turns
    if not enc.submit(intent)["ok"]:
        break
var again := Encounter.replay(enc.rng_seed, floor_data.walk_map, zone.rect, enc.setup_snapshot(), enc.intent_log)
# again.events == enc.events
```
Turn starts (resets, death saves, skipping downed/stable combatants) happen inside the encounter.
Mid-fight `add_combatant` / `remove_combatant` are recorded in `intent_log` as replay-only entries
(`combatant_join` / `combatant_remove`); read their events with `events_since(index)`.

## Using `Rng`
```gdscript
var rng := Rng.new(instance_seed)       # same seed => same results
var floor_rng := rng.fork(floor_number) # independent child stream, stable regardless of earlier draws
var dmg := DiceExpr.parse("1d8+2").roll(floor_rng)
var saved := rng.state()                # persist / replay with rng.set_state(saved)
```
Only the server owns Rng instances in multiplayer; clients never roll.

## Adding content
1. Add `data/{classes,monsters,ancestries,weapons}/<id>.json` (copy an existing file; keep `"schema_version": 1`).
2. Abilities and skills are upper-case strings (`"DEX"`, `"SLEIGHT_OF_HAND"`); damage uses dice syntax.
3. `ContentLoader.load_classes()` / `load_monsters()` / `load_ancestries()` / `load_weapons()` validate on load
   and `push_error` on bad files. `load_classes()` also resolves each class's `starting_weapon`.
4. Add a test in `tests/core/` and run `godot --headless --path . -s res://tests/run_tests.gd`.

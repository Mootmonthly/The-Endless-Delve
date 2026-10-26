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
| `rules/` | `Ability`, `AbilityScores`, `Skill`, `Proficiency`, `Experience`, `ClassDefinition`, `CharacterSheet`, `CharacterBuilder`, `Rest`, `DamageOutcome`, `DeathSaveOutcome` |
| `combat/` | `Combatant`, `MonsterDefinition`, `InitiativeTracker`, `AttackResolver`, `AttackResult`, `Encounter` (FORMING → ACTIVE → ENDED) |
| `content/` | `ContentLoader` (data/*.json → definitions), `DictUtil` (JSON-safe readers) |

## Using `Rng`
```gdscript
var rng := Rng.new(instance_seed)       # same seed => same results
var floor_rng := rng.fork(floor_number) # independent child stream, stable regardless of earlier draws
var dmg := DiceExpr.parse("1d8+2").roll(floor_rng)
var saved := rng.state()                # persist / replay with rng.set_state(saved)
```
Only the server owns Rng instances in multiplayer; clients never roll.

## Adding content
1. Add `data/classes/<id>.json` or `data/monsters/<id>.json` (copy an existing file; keep `"schema_version": 1`).
2. Abilities and skills are upper-case strings (`"DEX"`, `"SLEIGHT_OF_HAND"`); damage uses dice syntax.
3. `ContentLoader.load_classes()` / `load_monsters()` validate on load and `push_error` on bad files.
4. Add a test in `tests/core/` and run `godot --headless --path . -s res://tests/run_tests.gd`.

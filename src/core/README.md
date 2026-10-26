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
| `rules/` | `Ability`, `AbilityScores`, `Skill`, `Proficiency`, `Experience`, `ClassDefinition` (starting gear + kit, `features`, `spellcasting` slot table, level-up tables), `AncestryDefinition`, `WeaponDefinition` (thrown / ranged, `range_ft`, `ammo_id`), `CharacterSheet` (armor, `attacks`, inventory / equipment, spell slots, class resources, buffs), `CharacterBuilder` (kits, starting gear as equipped items), `LevelUp` (interactive level-up `choices` / `apply`), `Rest` (also slots and resources), `DamageOutcome`, `DeathSaveOutcome` |
| `items/` | `ItemDefinition` (weapon / armor / shield / consumable / ammo / gold / misc), `LootTable` (weighted, deterministic `roll(rng)`) |
| `spells/` | `SpellDefinition` (spell_attack / auto_hit / save / heal / buff / mark effects, riders, cantrip scaling, upcasting) |
| `grid/` | `GridMath` (Chebyshev distance, adjacency, `[x, y]` <-> `Vector2i`), `WalkMap` (walkable tiles, `can_step` without corner cutting, BFS `reachable` / `path_to`, Bresenham `has_line_of_sight`) |
| `floors/` | `FloorData` (walk map, arrival, stairs, zones, chests, `validate(loot_tables)`), `EncounterZoneData`, `ChestData` |
| `combat/` | `Combatant` (grid position, per-turn resources, encounter effects: rage, marks, inspiration), `MonsterDefinition` (+ `loot_table`), `InitiativeTracker`, `AttackResolver` (+ extra damage dice), `AttackResult`, `Encounter` (intent-driven FORMING → ACTIVE → ENDED, events, intent log, `replay`), `MonsterBrain` (deterministic AI: melee, shoots when it cannot reach) |
| `content/` | `ContentLoader` (data/*.json → definitions: classes, monsters, ancestries, weapons, items, spells, loot tables; `cache()`, `load_all()`, `validate_references()`), `DictUtil` (JSON-safe readers) |

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
Spells and items come from `enc.content` (the `ContentLoader.cache()` dictionary when left `{}`); pass the same
content to `Encounter.replay(..., encounter_id, content)`.
Turn starts (resets, death saves, skipping downed/stable combatants) happen inside the encounter.
Mid-fight `add_combatant` / `remove_combatant` are recorded in `intent_log` as replay-only entries
(`combatant_join` / `combatant_remove`); read their events with `events_since(index)`.

## Intents (all `{"v": 1, "type", "actor"}` + fields; only the current actor may act)
| type | fields | cost / rules |
|---|---|---|
| `move` | `path: [[x, y], ...]` | 1 tile of movement per step, no corner cutting; leaving reach provokes opportunity attacks (first usable melee attack) |
| `attack` | `target`, `attack_index`, `bonus` (optional) | action. Melee: adjacent. Ranged / thrown: distance ≤ long range and line of sight; disadvantage beyond normal range or with a conscious hostile adjacent to the attacker; thrown uses up the weapon item, ranged one ammunition item (`consumes`). `bonus: true` = Martial Arts unarmed strike (bonus action, after the Attack action) |
| `cast` | `spell`, `target` (default actor), `slot_level` (0 cantrip; 0 for a leveled spell = lowest free slot) | action or bonus action per spell; prepared, slot available, range (touch = 1 tile) and line of sight; harmful spells need a hostile target, heals / buffs an ally (heals revive the dying) |
| `use_item` | `item`, `target` (optional, self only in M2) | `use.action` (action / bonus action); heal, temp_hp and cure are implemented; the item is used up |
| `use_feature` | `feature`, `target`, `amount` | `second_wind` (bonus, 1d10 + level), `rage` (bonus, until the encounter ends or 10 rounds), `lay_on_hands` (action, `amount` from the 5 × level pool, self or adjacent ally), `bardic_inspiration` (bonus, ally within 12 tiles) |
| `dash` / `dodge` / `disengage` | – | action |
| `end_turn` | – | – |

## Events (`kind` + fields; JSON-safe)
`combatant_joined {id, name, team, initiative, position, hp, max_hp, ac}`, `combatant_removed {id}`,
`encounter_started {order}`, `round_started {round}`, `turn_started {actor, round}`, `turn_ended {actor}`,
`moved {actor, from, to}`, `dash|dodge|disengage {actor}`, `opportunity_attack {attacker, target}`,
`attack {attacker, target, attack_name, attack_kind ("melee"|"ranged"|"thrown"|"spell"), natural, d20s, total,
target_ac, hit, critical, fumble, advantage ("normal"|"advantage"|"disadvantage"), bonus, consumed (item id or ""),
spell (spell attacks only)}`,
`damage {target, amount, type, hp_after, dropped, died, extra? [{source ("rage"|"hex"|"sneak_attack"), amount, type}],
spell? (spell damage), darts? (magic missile)}`,
`death_save {actor, natural, successes, failures, stable, died, regained}`,
`cast {actor, spell, target, slot_level}`, `save {actor (caster), target, ability ("DEX"), dc, natural, total, success}`
(natural 0 = automatic failure), `heal {source, target, amount (restored), rolled, hp_after, revived}`,
`temp_hp {source, target, amount, temp_hp_after}`, `item_used {actor, item, target}`,
`feature_used {actor, feature, target, remaining}`, `inspiration_used {actor, source, die, roll}`,
`effect_applied {source, target, effect ("rage"|"hex"|"guiding_bolt_mark"|"slow"|"mockery"|"no_reactions"|
"bardic_inspiration"|"mage_armor"), die? (inspiration), ac? (mage armor)}`, `effect_ended {target, effect}`
(rage after 10 rounds, mockery at the target's turn end, guiding bolt mark after the caster's next turn),
`encounter_ended {winning_team}`.

## Items, spells, features (M2 scope)
- Inventory: `sheet.inventory` `[{"item", "qty"}]` (equipped items included), `sheet.equipped` (`main_hand`,
  `off_hand`, `armor`). `equip` / `unequip` update the AC fields and `rebuild_attacks(content)`. Armor proficiency
  is not enforced in M2. Thrown items are lost when thrown (no pick-up in M2). Carried thrown / ranged weapons
  are attacks even when not held (drawing a weapon is the free object interaction).
- Spells: `casting_ability`, `spells_known`, `spells_prepared` (cantrips included), `spell_slots` /
  `spell_slots_max` (index 0 = level 1), `slot_recovery` (`short_rest` = pact magic). Spell attack bonus =
  proficiency + casting modifier; save DC = 8 + both. Unsupported spells (area effects, concentration buffs)
  load as data but cannot be cast. Hex adds its dice to the caster's attack hits until the encounter ends.
- Class resources (`class_resources`): `second_wind` (short rest), `rage`, `lay_on_hands` (5 × level pool),
  `bardic_inspiration` (CHA modifier) restore on a long rest. Unarmored Defense (CON / WIS), Martial Arts,
  Sneak Attack and Mage Armor are computed from `features` / `active_buffs`.
- Levels: `gain_xp` only banks XP (`pending_levels()`); `LevelUp.choices(sheet, content)` /
  `LevelUp.apply(sheet, choices_made, content, rng)` raise one level with HP, ASI, spells and features.

## Using `Rng`
```gdscript
var rng := Rng.new(instance_seed)       # same seed => same results
var floor_rng := rng.fork(floor_number) # independent child stream, stable regardless of earlier draws
var dmg := DiceExpr.parse("1d8+2").roll(floor_rng)
var saved := rng.state()                # persist / replay with rng.set_state(saved)
```
Only the server owns Rng instances in multiplayer; clients never roll.

## Adding content
1. Add `data/{classes,monsters,ancestries,weapons,items,spells,loot}/<id>.json` (copy an existing file; keep
   `"schema_version": 1`).
2. Abilities and skills are upper-case strings (`"DEX"`, `"SLEIGHT_OF_HAND"`); damage uses dice syntax.
3. `ContentLoader.load_classes()` / `load_monsters()` / `load_ancestries()` / `load_weapons()` / `load_items()` /
   `load_spells()` / `load_loot_tables()` validate on load and `push_error` on bad files. `load_classes()` also
   resolves each class's `starting_weapon`. `ContentLoader.validate_references(content)` lists broken cross-references
   (kit items, weapon ids, ammo, spells, loot tables).
4. Add a test in `tests/core/` and run `godot --headless --path . -s res://tests/run_tests.gd`.

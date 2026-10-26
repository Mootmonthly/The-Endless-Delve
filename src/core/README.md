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
| `dice/` | `DiceExpr` ("2d6+3", "4d6kh3"), `DiceFormula` (sums such as "2d6+1d8+MOD"; crit doubling, Great Weapon Fighting rerolls, Empowered Spell), `DiceRoll`, `D20` (advantage/disadvantage), `D20Result` |
| `rules/` | `Ability`, `AbilityScores`, `Skill`, `Proficiency`, `Experience`, `ClassDefinition` (starting gear + kit, `features`, `spellcasting` slot table, level-up tables), `AncestryDefinition`, `WeaponDefinition` (thrown / ranged, `range_ft`, `ammo_id`), `CharacterSheet` (armor, `attacks`, inventory / equipment, spell slots, class resources, buffs), `CharacterBuilder` (kits, starting gear as equipped items, level-1 subclass and `creation_choices`), `LevelUp` (interactive level-up `choices` / `apply` with subclass, fighting style, expertise, invocations, metamagic, option features, skills), `Rest` (slots, resources, Song of Rest, Arcane / Natural Recovery), `Features` (`IMPLEMENTED` feature ids, implemented invocations / metamagic / fighting styles, `FEATURE_OPTIONS`), `Progression` (SRD fallback numbers when a class has no table), `DamageOutcome`, `DeathSaveOutcome` |
| `items/` | `ItemDefinition` (weapon / armor / shield / consumable / ammo / gold / misc), `LootTable` (weighted, deterministic `roll(rng)`) |
| `spells/` | `SpellDefinition` (spell_attack / auto_hit / save / heal / buff / mark / area_save / area_attack effects, riders, conditions, concentration, areas, `damage_by_slot` / `heal_by_slot` / `damage_by_character_level`, casting times) |
| `grid/` | `GridMath` (Chebyshev distance, adjacency, `[x, y]` <-> `Vector2i`), `WalkMap` (walkable tiles, `can_step` without corner cutting, BFS `reachable` / `path_to`, Bresenham `has_line_of_sight`), `AreaOfEffect` (sphere / cylinder / cube / line / cone tiles) |
| `floors/` | `FloorData` (walk map, arrival, stairs, zones, chests, `validate(loot_tables)`), `EncounterZoneData`, `ChestData` |
| `combat/` | `Combatant` (grid position, per-turn resources incl. `attacks_per_action` / `attacks_remaining`, encounter effects: rage, marks, inspiration, `conditions`, `concentration`), `Conditions` (SRD conditions and durations), `MonsterDefinition` (+ `loot_table`, `creature_type`, `multiattack`), `InitiativeTracker`, `AttackResolver` (+ extra damage dice, crit range, `roll` / `apply_damage`), `AttackResult`, `Encounter` (intent-driven FORMING → ACTIVE → ENDED, events, intent log, `replay`), `MonsterBrain` (deterministic AI: melee, shoots when it cannot reach, Multiattack, honours conditions) |
| `content/` | `ContentLoader` (data/*.json → definitions: classes, monsters, ancestries, weapons, items, spells, loot tables; records: features, invocations, metamagic, fighting_styles; `cache()`, `load_all()`, `validate_references()`), `DictUtil` (JSON-safe readers) |

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
Every field below is copied into `intent_log`, so replays reproduce it. An incapacitated actor (stunned,
paralyzed, incapacitated) may only `move` / `stand` / `end_turn`; a turned one (Turn Undead) only `move`,
`stand`, `dash`, `dodge`, `end_turn`.

| type | fields | cost / rules |
|---|---|---|
| `move` | `path: [[x, y], ...]` | 1 tile of movement per step, no corner cutting; leaving reach provokes opportunity attacks (first usable melee attack); a prone mover stands first (half its speed); a frightened mover may not step closer to a source of its fear |
| `stand` | – | a prone creature stands up: half its speed (rounded up) |
| `attack` | `target`, `attack_index`, `bonus`, `reckless`, `smite` (slot level), `stun`, `technique` (`"prone"`/`"push"`/`"no_reactions"`), `retarget` | The first attack takes the Attack action and leaves `attacks_per_action - 1` attacks (Extra Attack, Multiattack); later attack intents use them (moving in between is allowed). Melee: adjacent. Ranged / thrown: distance ≤ long range and line of sight; disadvantage beyond normal range or with a conscious, not incapacitated hostile adjacent. `bonus: true` = bonus-action attack: Martial Arts unarmed strike or two-weapon fighting off-hand attack (`"off_hand"` attack entry, both after the Attack action), Flurry of Blows strikes (after `use_feature flurry_of_blows`), Frenzy (melee, from the turn after raging with `frenzy`). `reckless` (Reckless Attack, first attack, melee STR). `smite`: Divine Smite with a slot of that level if a melee weapon attack hits (slot spent on a hit only). `stun`: Stunning Strike (1 ki on a melee weapon hit). `technique`: Open Hand Technique on a Flurry of Blows hit. `retarget`: when the target is no longer conscious, the conscious hostile in reach with the lowest hp (ties: id) is attacked instead (MonsterBrain multiattack follow-ups). Off-hand entries attack only as `bonus` |
| `cast` | `spell`, `target` (default actor), `slot_level` (0 cantrip; 0 for a leveled spell = lowest free slot, up to 9), `point: [x, y]` (area spells), `sculpt: [ids]`, `metamagic: [ids]`, `twin_target` | action or bonus action per spell (Quickened Spell: bonus action); only `action` / `bonus_action` casting times are castable in combat; prepared, slot available, range (touch = 1 tile) and line of sight; harmful spells need a hostile target, heals / buffs an ally (heals revive the dying). Area spells: `point` within range and sight (self cones / lines aim at `point`; self spheres / cubes are centred on the caster, who is excluded). `sculpt` (Sculpt Spells, evocation areas): up to 1 + spell level allies who are left out. `metamagic`: `quickened_spell` (2 points), `twinned_spell` (spell level points, min 1; `twin_target`), `empowered_spell` (1 point; rerolls up to CHA mod low damage dice); one of quickened / twinned per cast. Armor of Shadows: `mage_armor` on itself without a slot. No casting while raging |
| `use_item` | `item`, `target` (optional, self only), `bonus` | `use.action` (action / bonus action); `bonus: true` uses an action item as a bonus action (Fast Hands); heal, temp_hp and cure (ends the conditions) are implemented; the item is used up |
| `use_feature` | `feature`, `target`, `amount`, `mode`, `slot_level`, `allocations: {id: hp}`, `frenzy` | `second_wind` (bonus, 1d10 + level), `rage` (bonus; `frenzy: true` with Frenzy; ends concentration), `lay_on_hands` (action, `amount` from the pool, self or adjacent ally), `bardic_inspiration` (bonus, ally within 12 tiles, die from the class table), `action_surge` (free, once per turn: the action is available again), `flurry_of_blows` (bonus, 1 ki, after the Attack action: two unarmed `bonus` attacks), `patient_defense` (bonus, 1 ki: Dodge), `step_of_the_wind` (bonus, 1 ki, `mode` `"dash"` / `"disengage"`), `cunning_action` (bonus, `mode` `"dash"` / `"disengage"`; `"hide"` is not modelled), `turn_undead` / `turn_the_unholy` (action, 1 Channel Divinity: WIS save for undead (+ fiends) within 6 tiles in sight; failed = turned 10 rounds, or destroyed with Destroy Undead), `preserve_life` (action, 1 CD: `allocations` total ≤ 5 × level, allies within 6 tiles, none above half max hp), `sacred_weapon` (action, 1 CD: + CHA mod to weapon attack rolls for 10 turns), `font_of_magic` (bonus, `mode` `"create_slot"` (`slot_level` 1..5, sorcery points per class `sorcery_slot_costs`) / `"convert_slot"` (`slot_level`: points += level)), `pact_weapon` (action, Pact of the Blade: appends a proficient 1d8 + STR melee attack to the combatant's attacks) |
| `dash` / `dodge` / `disengage` | – | action |
| `end_turn` | – | – |

## Events (`kind` + fields; JSON-safe)
`combatant_joined {id, name, team, initiative, position, hp, max_hp, ac}`, `combatant_removed {id}`,
`encounter_started {order}`, `round_started {round}`, `turn_started {actor, round}`, `turn_ended {actor}`,
`moved {actor, from, to}`, `dash|dodge|disengage {actor}`, `opportunity_attack {attacker, target}`,
`attack {attacker, target, attack_name, attack_kind ("melee"|"ranged"|"thrown"|"spell"), natural, d20s, total,
target_ac, hit, critical, fumble, advantage ("normal"|"advantage"|"disadvantage"), bonus, consumed (item id or ""),
spell (spell attacks only), bonus_source ("martial_arts"|"flurry_of_blows"|"two_weapon_fighting"|"frenzy", bonus
attacks only)}`,
`damage_reduced {actor (the defender), feature ("deflect_missiles"|"uncanny_dodge"), source, amount}` (before the damage),
`damage {target, amount, type, hp_after, dropped, died, extra? [{source ("rage"|"hex"|"sneak_attack"|"colossus_slayer"|
"divine_smite"), amount, type}], spell? (spell damage), darts? (magic missile)}`,
`death_save {actor, natural, successes, failures, stable, died, regained}`,
`cast {actor, spell, target ("" for areas), slot_level, point? (areas), metamagic? [ids]}`,
`area_effect {caster, spell, point, shape, size_tiles, affected [ids], sculpted [ids]}` (then per creature `save` /
`damage` or `attack` events),
`save {actor (the source), target, ability ("DEX"), dc, natural, total, success, advantage? ("advantage"|"disadvantage",
only when not normal)}` (natural 0 = automatic failure),
`heal {source, target, amount (restored), rolled, hp_after, revived}`,
`temp_hp {source, target, amount, temp_hp_after, feature? ("dark_ones_blessing")}`, `item_used {actor, item, target}`,
`feature_used {actor, feature, target, remaining, mode?, slot_level?}` (remaining = the resource left: uses, ki,
channel_divinity, sorcery points; for `divine_smite` the slots of that level),
`inspiration_used {actor, source, die, roll}`,
`effect_applied {source, target, effect ("rage"|"frenzy"|"reckless_attack"|"hex"|"guiding_bolt_mark"|"slow"|"mockery"|
"no_reactions"|"bardic_inspiration"|"mage_armor"|"sacred_weapon"|"pact_weapon"), die? (inspiration), ac? (mage armor),
bonus? (sacred weapon), attack_index? (pact weapon)}`, `effect_ended {target, effect}`
(rage after 10 rounds or at 0 hp, mockery at the target's turn end, guiding bolt mark after the caster's next turn,
sacred weapon after 10 turns, hex when concentration ends),
`condition_applied {target, condition, source, duration}` / `condition_ended {target, condition}` (see below),
`concentration_started {actor, spell}`, `concentration_check {actor, spell, dc, natural, total, success}`,
`concentration_ended {actor, spell, reason ("new_spell"|"damage"|"unconscious"|"incapacitated"|"rage")}`,
`pushed {target, source, from, to}` (Open Hand push, Repelling Blast, area `push_ft`),
`destroyed {source, target, feature ("destroy_undead")}`, `encounter_ended {winning_team}`.

## Conditions and concentration
`Combatant.conditions` holds `{"condition", "source", "duration", "turns_left", "spell"?, "flee"?, "ends_on_damage"?}`
entries (`sheet.conditions` strings, e.g. a lasting "poisoned", count too). Conditions: prone, stunned, paralyzed,
incapacitated, frightened, poisoned, restrained, grappled, blinded, charmed (+ `no_reactions`). Durations:
`{"type": "until_source_next_turn"}`, `{"type": "until_target_turn_end"}`, `{"type": "save_ends", "ability", "dc"}`
(save at the end of the target's turns), `{"type": "rounds", "rounds": n}` (target turn ends), `{"type": "encounter"}`.
Rules: see `Conditions` and `Encounter._attack_mode` / `_saving_throw`. Stunned / paralyzed turns are skipped
(turn_started then turn_ended). Monsters get `condition_immunities` from their stat block. One concentration spell
per caster; casting another, damage (CON save DC max(10, damage / 2)), 0 hp, incapacitation and rage end it, and
with it the conditions and marks that spell applied.

## Items, spells, features
- Inventory: `sheet.inventory` `[{"item", "qty"}]` (equipped items included), `sheet.equipped` (`main_hand`,
  `off_hand`, `armor`). `equip` / `unequip` update the AC fields and `rebuild_attacks(content)`. Armor proficiency
  is not enforced. Thrown items are lost when thrown (no pick-up yet). Carried thrown / ranged weapons
  are attacks even when not held (drawing a weapon is the free object interaction). Light melee weapons in both
  hands add an `"off_hand": true` attack (bonus action). Fighting styles are baked into the attacks (archery,
  dueling, great weapon fighting `"reroll_max": 2`, two-weapon fighting) and AC (defense).
- Spells: `casting_ability`, `spells_known`, `spells_prepared` (cantrips included), `always_prepared` (subclass
  spells), `spell_slots` / `spell_slots_max` (index 0 = level 1, up to 9), `slot_recovery` (`short_rest` = pact
  magic). Spell attack bonus = proficiency + casting modifier; save DC = 8 + both. Class `spell_slots` tables cover
  1..20 (half casters from level 2, pact rows). Upcasting uses `damage_by_slot` / `heal_by_slot` (MOD = casting
  modifier), else `per_slot_level_above`; cantrips scale with `damage_by_character_level` / `scaling`.
  `unsupported` spells and other casting times load as data but cannot be cast.
- Class resources (`class_resources`, sized from the class `tables` when present, else `Progression`):
  `second_wind`, `action_surge`, `ki`, `channel_divinity` (short rest); `rage`, `lay_on_hands`, `sorcery_points`,
  `arcane_recovery`, `natural_recovery` and `bardic_inspiration` (long rest; inspiration also on a short rest with
  Font of Inspiration). Unarmored Defense, Draconic Resilience, Martial Arts (die table), Sneak Attack (table),
  Fast / Unarmored Movement, Extra Attack (`extra_attacks` table) and Mage Armor are computed from `features` /
  `active_buffs`.
- Progression: `subclass_id`, `fighting_styles`, `expertise_skills`, `invocations`, `metamagic` and option
  features (`pact_of_the_blade`, `colossus_slayer`, `circle_of_the_land_<terrain>`, `dragon_ancestor_<colour>`)
  live on the sheet. `Features.IMPLEMENTED` lists every feature id the engine models (data marks the rest
  "unsupported"). Levels: `gain_xp` only banks XP (`pending_levels()`); `LevelUp.choices(sheet, content)` /
  `LevelUp.apply(sheet, choices_made, content, rng)` raise one level (shapes in `level_up.gd`).
  `CharacterBuilder.create(..., choices)` / `creation_choices(cls, skills)` handle level-1 choices.
- Rests: `Rest.short_rest(sheet, dice, rng, song_die)` (`Rest.song_of_rest_die(party)`),
  `Rest.slot_recovery_options(sheet)` / `Rest.recover_slots(sheet, levels)` (Arcane / Natural Recovery after a
  short rest, once per long rest), `Rest.long_rest(sheet)`.

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

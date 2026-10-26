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
| `rules/` | `Ability`, `AbilityScores`, `Skill`, `Proficiency`, `Experience`, `ClassDefinition` (starting gear + kit, `features`, `spellcasting` slot table, level-up tables), `AncestryDefinition`, `WeaponDefinition` (thrown / ranged, `range_ft`, `ammo_id`), `CharacterSheet` (armor, `attacks`, inventory / equipment, spell slots, class resources, buffs), `CharacterBuilder` (kits, starting gear as equipped items, level-1 subclass and `creation_choices`), `LevelUp` (interactive level-up `choices` / `apply` with subclass, fighting style, expertise, invocations, metamagic, option features, skills, magical_secrets, mystic_arcanum, damage_type), `Rest` (slots, resources, Song of Rest, Arcane / Natural Recovery, `default_slot_recovery`, exhaustion / companions / Tranquility at a long rest, Sorcerous Restoration), `Features` (`IMPLEMENTED` feature ids, implemented invocations / metamagic / fighting styles, `FEATURE_OPTIONS`), `Progression` (SRD fallback numbers when a class has no table), `DamageOutcome`, `DeathSaveOutcome` |
| `items/` | `ItemDefinition` (weapon / armor / shield / consumable / ammo / gold / misc), `LootTable` (weighted, deterministic `roll(rng)`) |
| `spells/` | `SpellDefinition` (spell_attack / auto_hit / save / heal / buff / mark / area_save / area_attack + round B temp_hp / area_heal / heal_pool / summon / teleport / zone / sleep / revive / dispel / threshold / transform / reaction effects, riders, conditions, buff modifiers, modes, damage over time, sustain, concentration, areas, `damage_by_slot` / `heal_by_slot` / `damage_by_character_level`, casting times), `SpellEffects` (`OVERRIDES`: rules effects for data spells still marked unsupported), `OutOfCombat` (`cast`: Find Familiar / Animate Dead companions, Raise Dead, heals, restorations outside fights) |
| `grid/` | `GridMath` (Chebyshev distance, adjacency, `[x, y]` <-> `Vector2i`), `WalkMap` (walkable tiles, `can_step` without corner cutting, BFS `reachable` / `path_to`, Bresenham `has_line_of_sight`), `AreaOfEffect` (sphere / cylinder / cube / line / cone tiles) |
| `floors/` | `FloorData` (walk map, arrival, stairs, zones, chests, `validate(loot_tables)`), `EncounterZoneData`, `ChestData` |
| `combat/` | `Combatant` (grid position, per-turn resources incl. `attacks_per_action` / `attacks_remaining`, encounter effects: rage, marks, inspiration, `conditions`, `concentration`, `buffs`, `hidden`, summon fields, `form`, `reaction_policy`), `Conditions` (SRD conditions and durations), `MonsterDefinition` (+ `loot_table`, `creature_type`, `multiattack`), `InitiativeTracker`, `AttackResolver` (+ extra damage dice, crit range, `roll` / `apply_damage`), `AttackResult`, `Encounter` (intent-driven FORMING → ACTIVE → ENDED, events, intent log, `replay`), `MonsterBrain` (deterministic AI: melee, shoots when it cannot reach, Multiattack, honours conditions, searches for hidden foes, familiars Help) |
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
`set_reaction_policy(id, {trigger_or_reaction: "auto" | "never"})` may be called at any time (not only on
that combatant's turn); while ACTIVE it is logged as a replay-only `reaction_policy` entry.
Summons and companions never need server intents: the encounter runs their turns itself (MonsterBrain, not
logged; replays recompute them), so `current_actor()` is never a summon.

## Intents (all `{"v": 1, "type", "actor"}` + fields; only the current actor may act)
Every field below is copied into `intent_log`, so replays reproduce it. An incapacitated actor (stunned,
paralyzed, incapacitated) may only `move` / `stand` / `end_turn`; a turned one (Turn Undead) only `move`,
`stand`, `dash`, `dodge`, `end_turn`.

| type | fields | cost / rules |
|---|---|---|
| `move` | `path: [[x, y], ...]`, `mode` (`"walk"` default, `"fly"`, `"teleport"`) | 1 tile of movement per step (2 on difficult terrain: tile effects marked difficult), no corner cutting; leaving reach provokes opportunity attacks (reaction `opportunity_attack`, trigger `creature_left_reach`); a prone mover stands first (half its speed); a frightened mover may not step closer to a source of its fear. `fly` needs a fly speed (stat block, Fly, Dragon Wings): steps may cross unwalkable tiles in the region, the last must be open ground; flyers ignore ground effects. `teleport`: one destination within the teleport movement granted this turn (Misty Step / Dimension Door cast without a point), no opportunity attacks |
| `stand` | – | a prone creature stands up: half its speed (rounded up) |
| `attack` | `target`, `attack_index`, `bonus`, `reckless`, `smite` (slot level), `stun`, `technique` (`"prone"`/`"push"`/`"no_reactions"`), `retarget` | The first attack takes the Attack action and leaves `attacks_per_action - 1` attacks (Extra Attack, Multiattack); later attack intents use them (moving in between is allowed). Melee: adjacent. Ranged / thrown: distance ≤ long range and line of sight; disadvantage beyond normal range or with a conscious, not incapacitated hostile adjacent. `bonus: true` = bonus-action attack: Martial Arts unarmed strike or two-weapon fighting off-hand attack (`"off_hand"` attack entry, both after the Attack action), Flurry of Blows strikes (after `use_feature flurry_of_blows`), Frenzy (melee, on every turn of the rage after the one it started with `frenzy`; when a frenzied rage ends the barbarian gains one level of exhaustion). `reckless` (Reckless Attack, first attack, melee STR). `smite`: Divine Smite with a slot of that level if a melee weapon attack hits (slot spent on a hit only). `stun`: Stunning Strike (1 ki on a melee weapon hit). `technique`: Open Hand Technique on a Flurry of Blows hit. `retarget`: when the target is no longer conscious, the conscious hostile in reach with the lowest hp (ties: id) is attacked instead (MonsterBrain multiattack follow-ups). Off-hand entries attack only as `bonus`. `haste: true`: the Haste action (one weapon attack). Untargetable spell objects cannot be attacked. Thirsting Blade: two attacks per action with the pact weapon. Horde Breaker follows automatically (policy key `horde_breaker`) |
| `cast` | `spell`, `target` (default actor), `slot_level` (0 cantrip; 0 for a leveled spell = lowest free slot, up to 9), `point: [x, y]` (area spells), `sculpt: [ids]`, `metamagic: [ids]`, `twin_target` | action or bonus action per spell (Quickened Spell: bonus action); only `action` / `bonus_action` casting times are castable in combat; prepared, slot available, range (touch = 1 tile) and line of sight; harmful spells need a hostile target, heals / buffs an ally (heals revive the dying). Area spells: `point` within range and sight (self cones / lines aim at `point`; self spheres / cubes are centred on the caster, who is excluded). `sculpt` (Sculpt Spells, evocation areas): up to 1 + spell level allies who are left out. `metamagic`: `quickened_spell` (2 points), `twinned_spell` (spell level points, min 1; `twin_target`), `empowered_spell` (1 point; rerolls up to CHA mod low damage dice); one of quickened / twinned per cast. Armor of Shadows / Fiendish Vigor / Ascendant Step: mage armor / false life / levitate on itself without a slot. No casting while raging, polymorphed, in wild shape (unless Beast Spells) or feebleminded. Round B fields: `targets: [ids]` (multi-target spells: Bless 3 + 1 per slot level above, Mass Healing Word 6, ...), `mode` (spell variants: Command `grovel`/`halt`, Enhance Ability `bear`/`bull`/..., Protection from Energy damage type, Fire Shield `warm`/`chill`, Enlarge/Reduce `enlarge`/`reduce`, Eyebite `asleep`/`panicked`/`sickened`, Blindness/Deafness), `form` (summon / Polymorph creature id), `wall_end: [x, y]` (wall spells; default: across the caster's line of sight through `point`), `sustain: true` (recast a concentration spell with `sustain` without a slot: Call Lightning, Vampiric Touch, Heat Metal, Eyebite), `careful: [ids]`, `heightened_target`. Metamagic adds `careful_spell` (1), `distant_spell` (1: range x2, touch 30 ft), `extended_spell` (1: round durations x2), `heightened_spell` (3: disadvantage on the target's first save), `subtle_spell` (1: cannot be countered, works in Silence); one option per cast plus Empowered Spell. Mystic Arcanum spells cast once per long rest without a slot; invocation spells (Thief of Five Fates, Mire the Mind, Sign of Ill Omen, Dreadful Word, Sculptor of Flesh) once per long rest with a slot. Teleport: `point` = destination (Misty Step needs sight). Summons: optional `point` (near) and `form`. A cast may be answered by a hostile's Counterspell |
| `use_item` | `item`, `target` (optional, self only), `bonus` | `use.action` (action / bonus action); `bonus: true` uses an action item as a bonus action (Fast Hands); heal, temp_hp and cure (ends the conditions) are implemented; the item is used up |
| `use_feature` | `feature`, `target`, `amount`, `mode`, `slot_level`, `allocations: {id: hp}`, `frenzy` | `second_wind` (bonus, 1d10 + level), `rage` (bonus; `frenzy: true` with Frenzy; ends concentration), `lay_on_hands` (action, `amount` from the pool, self or adjacent ally), `bardic_inspiration` (bonus, ally within 12 tiles, die from the class table), `action_surge` (free, once per turn: the action is available again), `flurry_of_blows` (bonus, 1 ki, after the Attack action: two unarmed `bonus` attacks), `patient_defense` (bonus, 1 ki: Dodge), `step_of_the_wind` (bonus, 1 ki, `mode` `"dash"` / `"disengage"`), `cunning_action` (bonus, `mode` `"dash"` / `"disengage"` / `"hide"`), `turn_undead` / `turn_the_unholy` (action, 1 Channel Divinity: WIS save for undead (+ fiends) within 6 tiles in sight; failed = turned 10 rounds, or destroyed with Destroy Undead), `preserve_life` (action, 1 CD: `allocations` total ≤ 5 × level, allies within 6 tiles, none above half max hp), `sacred_weapon` (action, 1 CD: + CHA mod to weapon attack rolls for 10 turns), `font_of_magic` (bonus, `mode` `"create_slot"` (`slot_level` 1..5, sorcery points per class `sorcery_slot_costs`) / `"convert_slot"` (`slot_level`: points += level)), `pact_weapon` (action, Pact of the Blade: appends a proficient 1d8 + STR melee attack to the combatant's attacks). Round B: `intimidating_presence` (action, `target` within 6 tiles that sees you: WIS save DC 8 + prof + CHA or frightened until your next turn; using it again on a frightened target extends without a save; a success makes it immune), `countercharm` (action: you and allies within 6 tiles have advantage on saves against frightened / charmed until your next turn ends), `wholeness_of_body` (action, 1/long rest: heal 3 x level), `stillness_of_mind` (action: end charmed / frightened on yourself), `divine_intervention` (action, 1/long rest: d100 <= level (always at 20) heals every ally to full: `divine_intervention {actor, roll, success}`), `cleansing_touch` (action, CHA mod / long rest: end one hostile spell on yourself or an adjacent ally; `mode` = spell id), `volley` (action, `attack_index` ranged, `point`: one attack against each hostile within 2 tiles of the point), `whirlwind_attack` (action, `attack_index` melee: one attack against each hostile in reach), `elemental_affinity` (free, 1 sorcery point: resistance to the ancestry's damage type this encounter), `dragon_wings` (bonus: fly speed = walking speed), `wild_shape` (action, 2 / short rest, `form`: a beast within the CR / fly limits), `revert_form` (bonus), `empty_body` (action, 4 ki: invisible and resistant to all but force for 10 rounds), `draconic_presence` (action, 5 sorcery points, `mode` `"awe"` / `"fear"`: hostiles within 12 tiles WIS save or charmed / frightened for 10 rounds) |
| `dash` / `dodge` / `disengage` | `haste` (dash / disengage) | action (or the Haste action) |
| `hide` | `bonus` (Cunning Action / Vanish), `haste` | action: Stealth (DEX) against the highest passive Perception of conscious hostiles in line of sight (Supreme Sneak: advantage after moving at most half speed; Hide in Plain Sight: +10 when it has not moved); not with a hostile that can see it adjacent, unless it stands in an obscured tile (Fog Cloud, Darkness; Devil's Sight sees through). Success: hidden |
| `search` | – | action: Perception check; reveals hidden hostiles in sight whose Stealth total it meets (MonsterBrain searches when only hidden foes are left) |
| `shove` / `grapple` | `target`, `mode` (shove: `"prone"` default / `"push"` 1 tile) | replaces one attack of the Attack action; target adjacent, at most one size larger; Athletics against the target's Athletics or Acrobatics (an incapacitated target loses). Grappled lasts until escape, the grappler is incapacitated or they are no longer adjacent |
| `escape_grapple` | – | action: Athletics or Acrobatics against the grappler's Athletics |
| `help` | `target` | action: the next attack roll an ally makes against the adjacent hostile `target` before your next turn has advantage |
| `move_effect` | `effect` (tile effect id), `point` | moves a movable tile effect of the actor (Moonbeam: action, 60 ft; Flaming Sphere: bonus action, 30 ft) so it is centred on `point` |
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
`condition_applied {target, condition, source, duration, turns_left}` / `condition_ended {target, condition}` (see below),
`concentration_started {actor, spell}`, `concentration_check {actor, spell, dc, natural, total, success}`,
`concentration_ended {actor, spell, reason ("new_spell"|"damage"|"unconscious"|"incapacitated"|"rage"|"form_ended")}`,
`pushed {target, source, from, to}` (Open Hand push, Repelling Blast, area `push_ft`),
`destroyed {source, target, feature ("destroy_undead"|"power_word_kill"|"divine_word")}`, `encounter_ended {winning_team}`.

Round A shapes are unchanged; round B adds fields and kinds:
- Added fields: `dash|dodge|disengage {actor, source?}` (`source` = the feature: patient_defense, step_of_the_wind,
  cunning_action); `feature_used` for divine_smite carries `slot_level`, for flurry_of_blows `strikes` (2);
  `condition_applied` carries `turns_left`; `moved {.., mode: "fly"}` for flights; `combatant_joined {.., owner}`
  for summons; `cast {.., targets? [ids], point? (also teleport / summon), sustain?}`; `save {.., careful: true}`
  (Careful Spell, automatic success); `damage {.., spell?, effect_id? (tile effect), over_time?, blocked?}`;
  `area_effect {.., pool}` (Sleep); `effect_applied {.., duration, spell?}` for buffs (bless, haste, shield, ...),
  `effect_ended {target, effect: "reckless_attack"}` when Reckless Attack lapses at the barbarian's next turn.
- `reaction_used {actor, reaction, trigger, source?, target?, spell?, slot_level?, die?, roll?}`: reactions are
  opportunity_attack, shield, cutting_words, protection, counterspell, hellish_rebuke, uncanny_dodge,
  deflect_missiles, stand_against_the_tide, giant_killer, retaliation (opportunity_attack / damage_reduced still
  follow as before).
- `check {actor, ability, skill, natural, total, reason, dc?, success?, advantage?, contest?}`,
  `contest {actor, target, reason ("shove"|"grapple"|"escape_grapple"), actor_total, target_total, success}`.
- `hidden {actor, total}`, `revealed {actor, reason ("attacked"|"cast"|"moved_adjacent"|"found"|"shove"|"grapple"|
  "help"|"dropped"), by?}`, `help {actor, target}`, `attack_lost {attacker, target, reason ("sanctuary")}`,
  `mirror_image {attacker, target, roll, hit, images_left}`.
- `summoned {caster, spell, id, monster, position}`, `summon_ended {id, reason ("concentration"|"expired"|"dropped")}`
  (followed by `combatant_removed {id}`).
- `teleported {actor, from, to, spell?}`.
- `tile_effect_created {id, effect, source, spell, tiles, rounds (-1 = until concentration / encounter end), anchor}`,
  `tile_effect_moved {id, tiles}`, `tile_effect_triggered {id, target, trigger ("create"|"enter"|"start_turn"|
  "end_turn"|"per_tile")}`, `tile_effect_ended {id, reason ("concentration"|"expired"|"exhausted")}`.
- `spell_countered {caster, spell, by}`, `dispel {source, target, spell}`, `stabilized {source, target, spell}`,
  `revived {source, target, hp_after, spell}`.
- `save_modified {target, feature ("dark_ones_own_luck"|"indomitable"|"diamond_soul"), natural, total, success,
  roll?}` after a failed save.
- `death_avoided {target, feature ("death_ward"|"relentless_rage"), hp_after}`,
  `exhaustion {target, level, source}`, `confusion_roll {actor, roll}`, `divine_intervention {actor, roll, success}`.
- `transformed {target, form, kind ("wild_shape"|"polymorph"), hp, source}`, `reverted {target, reason, hp_after}`.

## Conditions and concentration
`Combatant.conditions` holds `{"condition", "source", "duration", "turns_left", "spell"?, "flee"?, "ends_on_damage"?}`
entries (`sheet.conditions` strings, e.g. a lasting "poisoned", count too). Conditions: prone, stunned, paralyzed,
incapacitated, frightened, poisoned, restrained, grappled, blinded, charmed (+ `no_reactions`). Durations:
`{"type": "until_source_next_turn"}`, `{"type": "until_target_turn_end"}`, `{"type": "save_ends", "ability", "dc"}`
(save at the end of the target's turns), `{"type": "rounds", "rounds": n}` (target turn ends), `{"type": "encounter"}`.
Rules: see `Conditions` and `Encounter._attack_mode` / `_saving_throw`. Stunned / paralyzed turns are skipped
(turn_started then turn_ended). Monsters get `condition_immunities` from their stat block. One concentration spell
per caster; casting another, damage (CON save DC max(10, damage / 2)), 0 hp, incapacitation and rage end it, and
with it the conditions, buffs, marks, tile effects, summons and polymorph forms that spell applied.
Round B adds invisible, unconscious (Sleep), petrified and deafened, plus the tracked `turn_lost` (Command,
confusion, Haste's lethargy: the next turn is skipped) and the duration `{"type": "until_target_turn_start"}`.
Situational immunities: Mindless Rage, Aura of Devotion / Courage, Nature's Ward, buff `immune_conditions`.

## Round B systems
- **Ability checks**: `Encounter.ability_check(c, ability, skill, dc, reason, adv, dis, bonus, contest_with)`,
  `Encounter.contest(...)`; `CharacterSheet.check_modifier` (proficiency, Expertise, Jack of All Trades, Remarkable
  Athlete; stat-block `skill_bonuses`), Reliable Talent, exhaustion / poisoned / frightened disadvantage, Guidance.
- **Hidden / invisible**: `Combatant.hidden` + `stealth_total`; `Encounter.can_see(viewer, target)` (blinded viewers,
  hidden or invisible targets; Blindsense within 2 tiles, See Invisibility, Faerie Fire outlines). An unseen attacker
  has advantage, attacking an unseen target has disadvantage (Feral Senses ignores it).
- **Reactions** (`Combatant.reaction_policy`, default "auto"; keys are a trigger or a reaction id):
  `creature_left_reach` (opportunity attacks), `creature_hit_me` (Shield when it turns the hit into a miss, Deflect
  Missiles, Uncanny Dodge, Giant Killer), `ally_attacked` (Protection: disadvantage, needs a shield),
  `ally_hit` (Cutting Words when the die can make it miss), `missed` (Stand Against the Tide, Giant Killer),
  `spell_cast_in_range` (Counterspell: 12 tiles, leveled spells, not Subtle), `damage_taken` (Hellish Rebuke,
  Retaliation), `failed_save` (Dark One's Own Luck, Indomitable, Diamond Soul — not reactions, same policy dict).
- **Buffs**: `Combatant.buffs` entries with modifiers (`ac`, `ac_min`, `attack_dice`, `save_dice`, `check_dice`,
  `once`, `save_bonus[_ABL]`, `adv_saves`, `disadv_saves`, `adv_checks`, `resist`, `resist_all`, `resist_nonmagical`,
  `immune_conditions`, `immune_damage`, `speed_double`, `speed_half`, `speed_zero`, `speed_bonus_ft`, `fly_ft`,
  `haste_action`, `single_action`, `no_reactions`, `attackers_advantage`, `attackers_disadvantage`,
  `attackers_disadvantage_types`, `attack_advantage`, `attack_disadvantage`, `advantage_vs`, `weapon_bonus`,
  `weapon_magical`, `weapon_damage_dice`, `weapon_damage_penalty_dice`, `next_hit_dice`, `half_str_damage`,
  `temp_hp`, `temp_hp_each_turn`, `max_hp_bonus`, `death_ward`, `sanctuary_dc`, `images`, `retaliate_dice`,
  `share_damage_with`, `see_invisible`, `outlined`, `levitating`, `confused`, `no_spellcasting`, `dot_*`,
  `lethargy`, `ends_on_attack`) and the condition durations.
- **Summons / companions**: `_summon` adds a combatant on the owner's team that acts right after it
  (`InitiativeTracker.insert_after`), run by the encounter, never keeping its team in the fight. Spiritual Weapon /
  Arcane Sword are untargetable spell objects. `sheet.companions` (Find Familiar, Animate Dead, Find Steed, Create
  Undead via `OutOfCombat.cast`) spawn next to their owner when the encounter starts; their hp is written back and the
  dead are dropped when it ends. Familiars only Help.
- **Tile effects**: `Encounter.tile_effects` (`_create_tile_effect`): triggers create / enter (once per turn) /
  start_turn / end_turn / per_tile, saves (Evasion applies), damage, conditions, difficult terrain, ground effects,
  obscured (hiding) and silence (no verbal spells) tiles, anchored (Spirit Guardians), drifting (Cloudkill), movable
  (`move_effect`), damage pools (Guardian of Faith), durations or concentration.
- **Exhaustion** (`sheet.exhaustion` 0..6), **revive** (Revivify within 10 rounds, Spare the Dying; Raise Dead /
  Resurrection out of combat with the -4 penalty fading per long rest), **damage over time** (buff `dot_*`:
  Phantasmal Killer), **forms** (`Combatant.form`: Wild Shape, Polymorph; revert at 0 hp with excess damage or at
  the end of the encounter), **nonmagical resistance** (stat-block "... from nonmagical weapons" entries; spells,
  magic weapons and Ki-Empowered Strikes beat them).
- **Spells**: `SpellEffects.OVERRIDES` gives data spells still marked unsupported a real effect (157 of 320 SRD
  spells are castable; the 163 left are utility / exploration, illusions, terrain the grid cannot hold, control
  needing an AI ally, 1-minute conjurations and special outcomes).

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
  `active_buffs`. Round B resources: `dark_ones_own_luck`, `stroke_of_luck`, `wild_shape` (short rest);
  `indomitable` (1 / 2 / 3), `wholeness_of_body`, `divine_intervention`, `cleansing_touch` (CHA mod) (long rest);
  `arcanum:<spell>` and `invocation:<id>` once-per-long-rest spells. Sheet fields: `size`, `exhaustion`,
  `skill_bonuses` / `save_bonuses` / `proficiency_override` / `fly_speed` (monsters), `companions`, `mystic_arcanum`,
  `chosen_resistance` (Fiendish Resilience), `relentless_rage_uses`, `resurrection_penalty`.
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

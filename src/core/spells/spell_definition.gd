class_name SpellDefinition
extends RefCounted
## A spell from data/spells/*.json (5e SRD), reduced to what the rules engine
## resolves: one effect per spell plus an optional rider.
##
## {"schema_version": 1, "id", "display_name", "level": 0..9, "school",
##  "casting_time": "action"|"bonus_action", "range_ft": int (or "touch"/"self"),
##  "target": "creature"|"self"|"creature_or_self"|"ally",
##  "effect": {"type": "spell_attack"|"auto_hit"|"save"|"heal"|"buff"|"mark"|"unsupported", ...}}
## Effect fields by type:
##   spell_attack: attack ("ranged" default | "melee"), damage, damage_type,
##                 scaling {"5": "2d10", ...} (by character level),
##                 per_slot_level_above (dice added per slot level above, or a
##                 number of extra rays), rays (attack rolls, default 1),
##                 beams {"1": 1, "5": 2} (rays by character level),
##                 on_miss ("half" = half damage on a miss)
##   auto_hit:     darts, damage (per dart), damage_type, per_slot_level_above (darts)
##   save:         save ("DEX"), damage, damage_type, on_save ("none"|"half"), scaling
##   heal:         dice, add_casting_mod, per_slot_level_above (dice)
##   buff:         buff ("mage_armor"; "hex" and "guiding_bolt_mark" also accepted)
##   mark:         mark ("hex"), damage or bonus_damage ("1d6"), damage_type ("necrotic")
##   area_save:    as save, for every creature in the top-level "area" (one damage roll)
##   area_attack:  as spell_attack, one attack roll per creature in the area
##   unsupported:  loads, but cannot be cast (data only)
## Optional top-level fields: "concentration" (bool), "area" {"shape": "sphere"|
## "cube"|"cone"|"line"|"cylinder" (as sphere), "size_ft"}, "saving_throw"
## {"ability", "on_success": "half"|"none"} (defaults for save / area_save),
## "damage_by_slot" {"3": "8d6", ...} and "heal_by_slot" {"1": "1d8+MOD", ...}
## (upcasting; MOD = casting modifier), "damage_by_character_level" (cantrips),
## "casting_time" beyond action / bonus_action ("reaction", "1_minute", ...: loads
## but cannot be cast in combat). Descriptive fields (higher_level, ritual,
## components, duration, classes, range_text, ...) are kept in `raw`.
## Conditions: an effect may carry "apply_condition": {"condition": "paralyzed",
## "duration": {...} (see Conditions; default: save_ends with the spell's save,
## else rounds 10)} (or a "condition" string naming an SRD condition); applied on
## a failed save / a hit / to the target of a buff. save / area_save may omit
## damage when they apply a condition.
## Riders (any type; key "rider", "on_hit", "on_hit_buff", "on_fail", "mark" or
## "condition"; a string id, or an object whose keys name it, e.g.
## {"slow_tiles": 2} or {"disadvantage_next_attack": true}):
##   "guiding_bolt_mark" (next attack roll against the target has advantage),
##   "slow" (target loses 2 tiles of movement on its next turn),
##   "mockery" (target has disadvantage on its next attack roll), "hex".
## When no rider is given, ray_of_frost / vicious_mockery / guiding_bolt get theirs by id.
##
## Round B effect types and fields (SpellEffects.OVERRIDES supplies them for
## data spells whose effect is still "unsupported"):
##   buff:      "modifiers" {...} (Combatant buff modifiers: ac, attack_dice,
##              save_dice, resist, fly_ft, ...), "effect_id", "rounds" (0 =
##              encounter), "max_targets" (+ "targets_per_slot"), "condition"
##              (Invisibility), "modes" {mode: {modifiers}} picked by the cast's "mode"
##   save / area_save / spell_attack: also "apply_effect" {modifiers} (+
##              "effect_id", "duration"), "extra_conditions" [ids], "dot" {dice,
##              type, trigger, once?, save?}, "extra_damage" [{damage, damage_type}],
##              "heal_caster" ("half"), "sustain" ("action" | "bonus_action")
##   temp_hp:   dice (+ per_slot_level_above), targets like heal
##   heal:      also "max_targets" (Mass Healing Word); area_heal: allies in the area
##   heal_pool: "pool" hit points split among allies in range (Mass Heal)
##   summon:    "monster" (default form), "forms" (allowed ids or "beast"), "max_cr",
##              "count" {cr: n}, "rounds", "familiar", "custom": "spiritual_weapon"
##   teleport:  "range_ft" (the spell's range), "need_sight"
##   zone:      "zone" {triggers, save, damage, damage_type, on_save, condition,
##              difficult, ground, plant, affects, rounds, obscured, silence,
##              wall, anchor ("caster"), move, move_ft, drift_ft, per_tile_damage, pool}
##   sleep:     "pool" dice (+ "per_slot_level_above") of hit points put to sleep
##   revive:    "max_rounds" since death (Revivify); "hp" restored
##   dispel:    "conditions" [ids] ended, "spells": true (ends spell effects)
##   threshold: "levels" [[hp, outcome], ...] (Power Word Kill / Stun, Divine Word)
##   transform: "form" (default monster), "max_cr" (polymorph)
##   reaction:  resolved by the reaction system (Shield, Counterspell)
## A top-level "target": "any" lets a spell target allies (no save) or
## hostiles (save) alike.

const SCHEMA_VERSION := 1
const REQUIRED_FIELDS: Array[String] = ["id", "display_name", "level", "effect"]
const EFFECT_SPELL_ATTACK := "spell_attack"
const EFFECT_AUTO_HIT := "auto_hit"
const EFFECT_SAVE := "save"
const EFFECT_HEAL := "heal"
const EFFECT_BUFF := "buff"
const EFFECT_MARK := "mark"
const EFFECT_AREA_SAVE := "area_save"
const EFFECT_AREA_ATTACK := "area_attack"
const EFFECT_TEMP_HP := "temp_hp"
const EFFECT_AREA_HEAL := "area_heal"
const EFFECT_HEAL_POOL := "heal_pool"
const EFFECT_SUMMON := "summon"
const EFFECT_TELEPORT := "teleport"
const EFFECT_ZONE := "zone"
const EFFECT_SLEEP := "sleep"
const EFFECT_REVIVE := "revive"
const EFFECT_DISPEL := "dispel"
const EFFECT_THRESHOLD := "threshold"
const EFFECT_TRANSFORM := "transform"
const EFFECT_REACTION := "reaction"
const EFFECT_UNSUPPORTED := "unsupported"
const EFFECT_TYPES: Array[String] = [
	EFFECT_SPELL_ATTACK, EFFECT_AUTO_HIT, EFFECT_SAVE, EFFECT_HEAL, EFFECT_BUFF, EFFECT_MARK, EFFECT_AREA_SAVE,
	EFFECT_AREA_ATTACK, EFFECT_TEMP_HP, EFFECT_AREA_HEAL, EFFECT_HEAL_POOL, EFFECT_SUMMON, EFFECT_TELEPORT,
	EFFECT_ZONE, EFFECT_SLEEP, EFFECT_REVIVE, EFFECT_DISPEL, EFFECT_THRESHOLD, EFFECT_TRANSFORM, EFFECT_REACTION,
	EFFECT_UNSUPPORTED,
]
## Effects whose cast names a point (areas; teleports; summons may).
const POINT_EFFECTS: Array[String] = [EFFECT_AREA_SAVE, EFFECT_AREA_ATTACK, EFFECT_ZONE, EFFECT_AREA_HEAL, EFFECT_SLEEP]
const AREA_SHAPES: Array[String] = ["sphere", "cube", "cone", "line", "cylinder"]
const TARGET_CREATURE := "creature"
const TARGET_SELF := "self"
const TARGET_CREATURE_OR_SELF := "creature_or_self"
const TARGET_ALLY := "ally"
const TARGET_ANY := "any"
const TARGETS: Array[String] = [TARGET_CREATURE, TARGET_SELF, TARGET_CREATURE_OR_SELF, TARGET_ALLY, TARGET_ANY]
## Casting times usable in combat; any other non-empty value loads as data only.
const CASTING_TIMES: Array[String] = ["action", "bonus_action"]
const DEFAULT_CONDITION_ROUNDS := 10  # 1 minute
const BUFF_MAGE_ARMOR := "mage_armor"
const RIDER_GUIDING := "guiding_bolt_mark"
const RIDER_SLOW := "slow"
const RIDER_MOCKERY := "mockery"
const RIDER_HEX := "hex"
const RIDER_NO_REACTIONS := "no_reactions"
const DEFAULT_SLOW_TILES := 2
const SUPPORTED_BUFFS: Array[String] = [BUFF_MAGE_ARMOR]
const RIDER_ALIASES := {
	"guiding_bolt_mark": RIDER_GUIDING, "guiding_bolt": RIDER_GUIDING, "advantage_next_attack": RIDER_GUIDING,
	"slow": RIDER_SLOW, "slowed": RIDER_SLOW, "speed_penalty": RIDER_SLOW, "ray_of_frost": RIDER_SLOW,
	"mockery": RIDER_MOCKERY, "mocked": RIDER_MOCKERY, "vicious_mockery": RIDER_MOCKERY,
	"disadvantage_next_attack": RIDER_MOCKERY,
	"hex": RIDER_HEX, "hex_mark": RIDER_HEX, "hexed": RIDER_HEX,
	"no_reactions": RIDER_NO_REACTIONS,
}
const RIDER_KEYS: Array[String] = ["rider", "on_hit", "on_hit_buff", "on_fail", "mark", "condition"]
const DEFAULT_RIDERS := {"ray_of_frost": RIDER_SLOW, "vicious_mockery": RIDER_MOCKERY, "guiding_bolt": RIDER_GUIDING}
const TOUCH_RANGE_FT := 5

var id: String = ""
var display_name: String = ""
var level: int = 0  # 0 = cantrip
var school: String = ""
var description: String = ""
var casting_time: String = "action"
var range_ft: int = 0  # 0 = self, 5 = touch
var target: String = TARGET_CREATURE
var effect_type: String = ""
var damage: String = ""  # spell_attack / save base dice; auto_hit per-dart; mark extra dice
var damage_type: String = ""
var scaling: Dictionary[int, String] = {}  # character level -> damage dice (cantrips)
var darts: int = 0
var per_slot_dice: String = ""  # extra dice per slot level above the spell's level
var per_slot_darts: int = 0
var save_ability: int = -1  # Ability.Type
var on_save: String = "none"  # "none" | "half"
var heal_dice: String = ""
var add_casting_mod: bool = false
var buff: String = ""
var rider: String = ""  # canonical rider id, "" = none
var slow_tiles: int = DEFAULT_SLOW_TILES  # movement lost by a "slow" rider
var melee: bool = false  # melee spell attack (no ranged-attack disadvantages)
var rays: int = 1  # spell_attack rolls per casting
var beams: Dictionary[int, int] = {}  # character level -> rays (overrides rays)
var half_on_miss: bool = false
var raw_effect: Dictionary = {}
var concentration: bool = false
var area_shape: String = ""  # "" = single target
var area_size_ft: int = 0
var damage_by_slot: Dictionary[int, String] = {}
var damage_by_character_level: Dictionary[int, String] = {}
var heal_by_slot: Dictionary[int, String] = {}
var push_tiles: int = 0  # area_save: creatures failing the save are pushed away ("push_ft")
var condition: String = ""  # SRD condition applied ("" = none)
var condition_duration: Dictionary = {}  # Conditions duration ({} = default)
var raw: Dictionary = {}  # the whole JSON object (descriptive fields)
var zone: Dictionary = {}  # "zone" effects: the lingering area's rules (see Encounter._create_tile_effect)
var modifiers: Dictionary = {}  # buff modifiers (buff) or the effect a failed save applies (apply_effect)
var effect_id: String = ""  # buff / applied effect id (default: the spell id)
var rounds: int = DEFAULT_CONDITION_ROUNDS  # buff duration in rounds (0 = the encounter)
var max_targets: int = 1  # creatures one casting affects (bless: 3)
var targets_per_slot: int = 0  # extra creatures per slot level above the spell's
var extra_conditions: Array[String] = []  # further conditions applied with `condition`
var extra_damage: Array[Dictionary] = []  # [{"damage", "damage_type", "damage_by_slot"?}] a second damage type
var dot: Dictionary = {}  # damage over time applied on a hit / failed save
var sustain: String = ""  # "action" / "bonus_action": recast without a slot while concentrating
var modes: Dictionary = {}  # mode -> {modifiers...} (cast "mode")
var overridden: bool = false  # the effect came from SpellEffects.OVERRIDES


## Returns null (and push_error) when a field is missing or invalid.
static func from_dict(d: Dictionary) -> SpellDefinition:
	if not DictUtil.require_keys(d, REQUIRED_FIELDS, "SpellDefinition"):
		return null
	var s := SpellDefinition.new()
	s.id = str(d["id"])
	var ctx := "SpellDefinition '%s'" % s.id
	if s.id.is_empty():
		push_error("%s: id must not be empty" % ctx)
		return null
	if d.has("schema_version") and DictUtil.to_int(d["schema_version"], -1) != SCHEMA_VERSION:
		push_error("%s: unsupported schema_version %s" % [ctx, str(d["schema_version"])])
		return null
	var effect_check: Variant = d.get("effect", {})
	if typeof(effect_check) == TYPE_DICTIONARY and str((effect_check as Dictionary).get("type", "")).to_lower() == EFFECT_UNSUPPORTED \
			and SpellEffects.OVERRIDES.has(s.id):
		d = SpellEffects.apply_override(d)
		s.overridden = true
	s.display_name = str(d["display_name"])
	s.description = str(d.get("description", ""))
	s.school = str(d.get("school", ""))
	s.level = DictUtil.to_int(d["level"], -1)
	if s.level < 0 or s.level > 9:
		push_error("%s: level must be 0..9" % ctx)
		return null
	s.raw = d.duplicate(true)
	s.casting_time = str(d.get("casting_time", "action")).to_lower().replace(" ", "_")
	if s.casting_time.is_empty():
		push_error("%s: casting_time must not be empty" % ctx)
		return null
	s.concentration = DictUtil.to_bool(d.get("concentration", false), false)
	var area_v: Variant = d.get("area", null)
	if typeof(area_v) == TYPE_DICTIONARY:
		var area: Dictionary = area_v
		s.area_shape = str(area.get("shape", "")).to_lower()
		s.area_size_ft = DictUtil.to_int(area.get("size_ft", 0), 0)
		if not AREA_SHAPES.has(s.area_shape) or s.area_size_ft < 5:
			push_error("%s: area needs a shape (%s) and size_ft >= 5" % [ctx, ", ".join(AREA_SHAPES)])
			return null
	if not SpellDefinition._parse_formula_table(d.get("damage_by_slot", null), s.damage_by_slot, ctx + " damage_by_slot"):
		return null
	if not SpellDefinition._parse_formula_table(d.get("damage_by_character_level", null), s.damage_by_character_level, ctx + " damage_by_character_level"):
		return null
	if not SpellDefinition._parse_formula_table(d.get("heal_by_slot", null), s.heal_by_slot, ctx + " heal_by_slot"):
		return null
	s.target = str(d.get("target", TARGET_CREATURE)).to_lower()
	if not TARGETS.has(s.target):
		push_error("%s: unknown target '%s'" % [ctx, s.target])
		return null
	var range_v: Variant = d.get("range_ft", 0)
	if typeof(range_v) == TYPE_STRING and str(range_v).to_lower() == "touch":
		s.range_ft = TOUCH_RANGE_FT
	elif typeof(range_v) == TYPE_STRING and str(range_v).to_lower() == "self":
		s.range_ft = 0
	else:
		s.range_ft = DictUtil.to_int(range_v, -1)
	if s.range_ft < 0:
		push_error("%s: range_ft must be a non-negative number, \"touch\" or \"self\"" % ctx)
		return null
	if s.target == TARGET_SELF:
		s.range_ft = 0
	var effect_v: Variant = d["effect"]
	if typeof(effect_v) != TYPE_DICTIONARY:
		push_error("%s: effect must be an object" % ctx)
		return null
	var effect_d: Dictionary = effect_v
	var e: Dictionary = effect_d.duplicate(true)
	s.raw_effect = effect_d.duplicate(true)
	s.effect_type = str(e.get("type", "")).to_lower()
	if not EFFECT_TYPES.has(s.effect_type):
		push_error("%s: unknown effect type '%s'" % [ctx, s.effect_type])
		return null
	if s.effect_type in [EFFECT_AREA_SAVE, EFFECT_AREA_ATTACK] and s.area_shape.is_empty():
		push_error("%s: %s needs a top-level area" % [ctx, s.effect_type])
		return null
	if not SpellDefinition._parse_condition(s, e, ctx):
		return null
	s.push_tiles = GridMath.feet_to_tiles(DictUtil.to_int(e.get("push_ft", 0), 0))
	if not SpellDefinition._parse_round_b(s, e, d, ctx):
		return null
	var st_v: Variant = d.get("saving_throw", null)
	if typeof(st_v) == TYPE_DICTIONARY:
		var st: Dictionary = st_v
		if not e.has("save") and st.has("ability"):
			e["save"] = st["ability"]
		if not e.has("on_save") and st.has("on_success"):
			e["on_save"] = st["on_success"]
	s.damage = str(e.get("damage", ""))
	s.damage_type = str(e.get("damage_type", "")).to_lower()
	var scaling_v: Variant = e.get("scaling", {})
	if typeof(scaling_v) == TYPE_DICTIONARY:
		var scaling_d: Dictionary = scaling_v
		for key: Variant in scaling_d.keys():
			var lvl := DictUtil.to_int(key, -1)
			var dice := str(scaling_d[key])
			if lvl < 1 or not DiceExpr.parse(dice).valid:
				push_error("%s: invalid scaling entry %s: %s" % [ctx, str(key), dice])
				return null
			s.scaling[lvl] = dice
	var per_v: Variant = e.get("per_slot_level_above", null)
	if DictUtil.is_number(per_v):
		s.per_slot_darts = DictUtil.to_int(per_v, 0)
	elif per_v != null and str(per_v) != "":
		s.per_slot_dice = str(per_v)
		if not DiceExpr.parse(s.per_slot_dice).valid:
			push_error("%s: invalid per_slot_level_above '%s'" % [ctx, s.per_slot_dice])
			return null
	if s.damage.is_empty() and not s.damage_by_slot.is_empty():
		s.damage = s.damage_by_slot.get(s.level, s.damage_by_slot.values()[0])
	if s.damage.is_empty() and not s.damage_by_character_level.is_empty():
		s.damage = s.damage_by_character_level.get(1, s.damage_by_character_level.values()[0])
	match s.effect_type:
		EFFECT_SPELL_ATTACK, EFFECT_SAVE, EFFECT_AREA_ATTACK, EFFECT_AREA_SAVE:
			if s.effect_type in [EFFECT_SPELL_ATTACK, EFFECT_AREA_ATTACK]:
				s.melee = str(e.get("attack", "ranged")).to_lower() == "melee"
				s.rays = maxi(1, DictUtil.to_int(e.get("rays", 1), 1))
				s.half_on_miss = str(e.get("on_miss", "")).to_lower() == "half"
				var beams_v: Variant = e.get("beams", {})
				if typeof(beams_v) == TYPE_DICTIONARY:
					var beams_d: Dictionary = beams_v
					for key: Variant in beams_d.keys():
						s.beams[DictUtil.to_int(key, 1)] = maxi(1, DictUtil.to_int(beams_d[key], 1))
			var damage_optional := s.damage.is_empty() and (not s.condition.is_empty() or not s.modifiers.is_empty() or not s.dot.is_empty() \
					or s.push_tiles > 0 or e.has("curse_mark")) \
					and s.effect_type in [EFFECT_SAVE, EFFECT_AREA_SAVE]
			if not damage_optional and not DiceFormula.parse(s.damage).valid:
				push_error("%s: invalid damage '%s'" % [ctx, s.damage])
				return null
			if s.effect_type in [EFFECT_SAVE, EFFECT_AREA_SAVE]:
				s.save_ability = Ability.from_string(str(e.get("save", "")))
				if s.save_ability < 0:
					push_error("%s: unknown save ability '%s'" % [ctx, str(e.get("save", ""))])
					return null
				s.on_save = str(e.get("on_save", "none")).to_lower()
				if not s.on_save in ["none", "half"]:
					push_error("%s: on_save must be none or half" % ctx)
					return null
		EFFECT_AUTO_HIT:
			s.darts = DictUtil.to_int(e.get("darts", 1), 1)
			if s.darts < 1 or not DiceExpr.parse(s.damage).valid:
				push_error("%s: auto_hit needs darts >= 1 and valid damage" % ctx)
				return null
		EFFECT_HEAL, EFFECT_AREA_HEAL, EFFECT_TEMP_HP:
			s.heal_dice = str(e.get("dice", e.get("heal", "")))
			if s.heal_dice.is_empty() and not s.heal_by_slot.is_empty():
				s.heal_dice = s.heal_by_slot.get(s.level, s.heal_by_slot.values()[0])
			if not DiceFormula.parse(s.heal_dice).valid:
				push_error("%s: invalid heal dice '%s'" % [ctx, s.heal_dice])
				return null
			s.add_casting_mod = DictUtil.to_bool(e.get("add_casting_mod", false), false)
		EFFECT_BUFF:
			s.buff = str(e.get("buff", s.effect_id if not s.modifiers.is_empty() or not s.modes.is_empty() or not s.condition.is_empty() else "")).to_lower()
			if s.buff.is_empty():
				push_error("%s: buff effect needs a \"buff\" id" % ctx)
				return null
			if RIDER_ALIASES.has(s.buff):
				# A "buff" that is really a mark on a hostile (hex, guiding bolt).
				s.rider = str(RIDER_ALIASES[s.buff])
				if s.rider == RIDER_HEX:
					s.effect_type = EFFECT_MARK
		EFFECT_MARK:
			var mark := str(e.get("mark", RIDER_HEX)).to_lower()
			s.rider = str(RIDER_ALIASES.get(mark, mark))
	if s.effect_type == EFFECT_MARK:
		if s.damage.is_empty():
			s.damage = str(e.get("bonus_damage", "1d6"))
		if s.damage_type.is_empty() and s.rider == RIDER_HEX:
			s.damage_type = "necrotic"
		if not DiceExpr.parse(s.damage).valid:
			push_error("%s: invalid mark damage '%s'" % [ctx, s.damage])
			return null
	if s.rider.is_empty():
		for key in RIDER_KEYS:
			if e.has(key) and e[key] != null:
				s.rider = SpellDefinition._rider_from(e[key], s)
				if not s.rider.is_empty():
					break
	if s.rider.is_empty() and DEFAULT_RIDERS.has(s.id):
		s.rider = str(DEFAULT_RIDERS[s.id])
	return s


## "apply_condition" {"condition", "duration"?}, or a "condition" string naming
## an SRD condition.
static func _parse_condition(s: SpellDefinition, e: Dictionary, ctx: String) -> bool:
	var ac: Variant = e.get("apply_condition", null)
	if typeof(ac) == TYPE_DICTIONARY:
		var acd: Dictionary = ac
		s.condition = str(acd.get("condition", "")).to_lower()
		if acd.has("duration"):
			var dur: Variant = acd["duration"]
			var dur_type := str(dur)
			if typeof(dur) == TYPE_DICTIONARY:
				var dur_d: Dictionary = dur
				dur_type = str(dur_d.get("type", ""))
			s.condition_duration = Conditions.normalize_duration(dur)
			if s.condition_duration.is_empty() and dur_type == Conditions.DURATION_SAVE_ENDS:
				# save_ends without ability / dc: the spell's save against the caster's DC.
				s.condition_duration = {"type": Conditions.DURATION_SAVE_ENDS}
			if s.condition_duration.is_empty():
				push_error("%s: invalid apply_condition duration %s" % [ctx, str(dur)])
				return false
	elif typeof(e.get("condition", null)) == TYPE_STRING and Conditions.is_condition(str(e["condition"]).to_lower()):
		s.condition = str(e["condition"]).to_lower()
	if not s.condition.is_empty() and not Conditions.is_condition(s.condition):
		push_error("%s: unknown condition '%s'" % [ctx, s.condition])
		return false
	return true


## Round B fields (see the class doc): modifiers, effect_id, rounds, targets,
## extra conditions, extra damage, damage over time, sustain, modes, zone.
static func _parse_round_b(s: SpellDefinition, e: Dictionary, d: Dictionary, ctx: String) -> bool:
	var mods_v: Variant = e.get("modifiers", e.get("apply_effect", {}))
	if typeof(mods_v) == TYPE_DICTIONARY:
		var mods: Dictionary = mods_v
		s.modifiers = mods.duplicate(true)
	s.effect_id = str(e.get("effect_id", s.id))
	s.rounds = maxi(0, DictUtil.to_int(e.get("rounds", DEFAULT_CONDITION_ROUNDS), DEFAULT_CONDITION_ROUNDS))
	s.max_targets = maxi(1, DictUtil.to_int(e.get("max_targets", 1), 1))
	s.targets_per_slot = maxi(0, DictUtil.to_int(e.get("targets_per_slot", 0), 0))
	for c in DictUtil.to_string_array(e.get("extra_conditions", [])):
		if not Conditions.is_condition(c):
			push_error("%s: unknown condition '%s'" % [ctx, c])
			return false
		s.extra_conditions.append(c)
	var extra_src: Variant = e.get("extra_damage", d.get("extra_damage", []))
	for raw_extra in DictUtil.to_dict_array(extra_src):
		var entry := {"damage_type": str(raw_extra.get("damage_type", "")).to_lower(), "damage": str(raw_extra.get("damage", ""))}
		var by_slot: Dictionary[int, String] = {}
		if not SpellDefinition._parse_formula_table(raw_extra.get("damage_by_slot", null), by_slot, ctx + " extra_damage"):
			return false
		if str(entry["damage"]).is_empty() and not by_slot.is_empty():
			entry["damage"] = by_slot.get(s.level, by_slot.values()[0])
		if not DiceFormula.parse(str(entry["damage"])).valid:
			continue
		s.extra_damage.append(entry)
	var dot_v: Variant = e.get("dot", {})
	if typeof(dot_v) == TYPE_DICTIONARY:
		var dot_d: Dictionary = dot_v
		s.dot = dot_d.duplicate(true)
	s.sustain = str(e.get("sustain", ""))
	var modes_v: Variant = e.get("modes", {})
	if typeof(modes_v) == TYPE_DICTIONARY:
		var modes_d: Dictionary = modes_v
		s.modes = modes_d.duplicate(true)
	var zone_v: Variant = e.get("zone", {})
	if typeof(zone_v) == TYPE_DICTIONARY:
		var zone_d: Dictionary = zone_v
		s.zone = zone_d.duplicate(true)
	if s.effect_type == EFFECT_ZONE and s.area_shape.is_empty():
		push_error("%s: zone needs a top-level area" % ctx)
		return false
	return true


## The modifiers for a cast "mode" (modes), else the base modifiers.
func modifiers_for(mode: String) -> Dictionary:
	if not mode.is_empty() and modes.has(mode):
		var m: Variant = modes[mode]
		if typeof(m) == TYPE_DICTIONARY:
			var out := modifiers.duplicate(true)
			out.merge(m as Dictionary, true)
			return out
	return modifiers.duplicate(true)


## Creatures one casting at slot_level may target.
func targets_at(slot_level: int) -> int:
	return max_targets + targets_per_slot * maxi(0, slot_level - level)


## {"3": "8d6", ...} -> into[3] = "8d6" (each a valid DiceFormula).
static func _parse_formula_table(v: Variant, into: Dictionary, ctx: String) -> bool:
	if v == null:
		return true
	if typeof(v) != TYPE_DICTIONARY:
		push_error("%s: must be an object keyed by level" % ctx)
		return false
	var src: Dictionary = v
	for key: Variant in src.keys():
		var lvl := DictUtil.to_int(key, -1)
		var text := str(src[key])
		if lvl < 0 or lvl > 20 or not DiceFormula.parse(text).valid:
			push_error("%s: invalid entry %s: %s" % [ctx, str(key), text])
			return false
		into[lvl] = text
	return true


## A rider id from a string or from the keys of an object ("" if none is known).
static func _rider_from(v: Variant, s: SpellDefinition) -> String:
	if typeof(v) == TYPE_DICTIONARY:
		var d: Dictionary = v
		if d.has("slow_tiles"):
			s.slow_tiles = maxi(0, DictUtil.to_int(d["slow_tiles"], DEFAULT_SLOW_TILES))
			return RIDER_SLOW
		if d.has("speed_penalty_ft"):
			s.slow_tiles = GridMath.feet_to_tiles(DictUtil.to_int(d["speed_penalty_ft"], 10))
			return RIDER_SLOW
		for key: Variant in d.keys():
			var k := str(key).to_lower()
			var off: bool = typeof(d[key]) == TYPE_BOOL and not DictUtil.to_bool(d[key])
			if RIDER_ALIASES.has(k) and not off:
				return str(RIDER_ALIASES[k])
		return ""
	var r := str(v).to_lower()
	return str(RIDER_ALIASES.get(r, ""))


## Attack rolls for a caster of character_level casting at slot_level.
func rays_for(character_level: int, slot_level: int) -> int:
	var n := rays
	var best := 0
	for lvl: int in beams.keys():
		if lvl <= character_level and lvl > best:
			best = lvl
			n = beams[lvl]
	if per_slot_dice.is_empty() and per_slot_darts > 0 and level > 0:
		n += per_slot_darts * maxi(0, slot_level - level)
	return n


func is_cantrip() -> bool:
	return level == 0


func is_harmful() -> bool:
	if target == TARGET_ANY:
		return false
	return effect_type in [EFFECT_SPELL_ATTACK, EFFECT_AUTO_HIT, EFFECT_SAVE, EFFECT_MARK, EFFECT_AREA_SAVE, EFFECT_AREA_ATTACK, EFFECT_THRESHOLD, EFFECT_SLEEP] \
			or (effect_type == EFFECT_BUFF and rider == RIDER_GUIDING) or (effect_type == EFFECT_TRANSFORM and target != TARGET_ALLY)


## Area spells pick a point (or a direction) instead of a target.
func is_area() -> bool:
	return effect_type in POINT_EFFECTS


## Whether the rules engine can resolve this spell (unsupported buffs are data only).
func is_supported() -> bool:
	if effect_type == EFFECT_UNSUPPORTED:
		return false
	if effect_type == EFFECT_BUFF:
		return SUPPORTED_BUFFS.has(buff) or rider == RIDER_GUIDING or not condition.is_empty() or not modifiers.is_empty() or not modes.is_empty()
	return true


## Castable as an action or bonus action (not a reaction or a ritual-length cast).
func is_combat_castable() -> bool:
	return CASTING_TIMES.has(casting_time)


## Damage formula for a caster of character_level casting with slot_level:
## damage_by_slot (highest entry <= slot) for leveled spells, else
## damage_by_character_level / scaling for cantrips, else the base damage plus
## per_slot_level_above dice for each slot level above the spell's.
func damage_formula(character_level: int, slot_level: int) -> String:
	if level > 0 and not damage_by_slot.is_empty():
		return SpellDefinition._at_or_below(damage_by_slot, maxi(slot_level, level), damage)
	if level == 0 and not damage_by_character_level.is_empty():
		return SpellDefinition._at_or_below(damage_by_character_level, character_level, damage)
	var base := damage_for_level(character_level)
	if per_slot_dice.is_empty() or slot_level <= level or level == 0:
		return base
	var b := DiceExpr.parse(base)
	var p := DiceExpr.parse(per_slot_dice)
	var times := slot_level - level
	if b.valid and p.valid and not b.is_constant() and b.sides == p.sides and b.keep_highest == 0:
		return "%dd%d" % [b.count + p.count * times, b.sides] + CharacterBuilder.signed(b.modifier + p.modifier * times)
	return DiceFormula.plus(base, per_slot_dice, times)


## Heal formula at slot_level: heal_by_slot (MOD = casting modifier, so
## add_casting_mod is ignored) or the base dice plus per-slot dice.
## Returns {"formula": String, "add_mod": bool}.
func heal_formula(slot_level: int) -> Dictionary:
	if not heal_by_slot.is_empty():
		return {"formula": SpellDefinition._at_or_below(heal_by_slot, maxi(slot_level, level), heal_dice), "add_mod": false}
	var times := maxi(0, slot_level - level)
	return {"formula": DiceFormula.plus(heal_dice, per_slot_dice, times), "add_mod": add_casting_mod}


static func _at_or_below(table: Dictionary[int, String], key: int, fallback: String) -> String:
	var best := -1
	var out := fallback
	for k: int in table.keys():
		if k <= key and k > best:
			best = k
			out = table[k]
	return out


## Area size in tiles: radius for sphere / cylinder, half the side (rounded
## down) for cube, length for cone / line.
func area_size_tiles() -> int:
	var tiles := GridMath.feet_to_tiles(area_size_ft)
	if area_shape == "cube":
		return maxi(0, floori(tiles / 2.0))
	return maxi(1, tiles)


func uses_bonus_action() -> bool:
	return casting_time == "bonus_action"


## Range in tiles (touch = 1, self = 0).
func range_tiles() -> int:
	return GridMath.feet_to_tiles(range_ft)


## Damage dice for a caster of character_level: the highest scaling entry whose
## level is <= character_level, else the base damage.
func damage_for_level(character_level: int) -> String:
	var best := 0
	var dice := damage
	for lvl: int in scaling.keys():
		if lvl <= character_level and lvl > best:
			best = lvl
			dice = scaling[lvl]
	return dice

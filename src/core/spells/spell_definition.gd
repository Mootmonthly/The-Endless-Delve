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
##   unsupported:  loads, but cannot be cast (data only)
## Riders (any type; key "rider", "on_hit", "on_hit_buff", "on_fail", "mark" or
## "condition"; a string id, or an object whose keys name it, e.g.
## {"slow_tiles": 2} or {"disadvantage_next_attack": true}):
##   "guiding_bolt_mark" (next attack roll against the target has advantage),
##   "slow" (target loses 2 tiles of movement on its next turn),
##   "mockery" (target has disadvantage on its next attack roll), "hex".
## When no rider is given, ray_of_frost / vicious_mockery / guiding_bolt get theirs by id.

const SCHEMA_VERSION := 1
const REQUIRED_FIELDS: Array[String] = ["id", "display_name", "level", "effect"]
const EFFECT_SPELL_ATTACK := "spell_attack"
const EFFECT_AUTO_HIT := "auto_hit"
const EFFECT_SAVE := "save"
const EFFECT_HEAL := "heal"
const EFFECT_BUFF := "buff"
const EFFECT_MARK := "mark"
const EFFECT_UNSUPPORTED := "unsupported"
const EFFECT_TYPES: Array[String] = [EFFECT_SPELL_ATTACK, EFFECT_AUTO_HIT, EFFECT_SAVE, EFFECT_HEAL, EFFECT_BUFF, EFFECT_MARK, EFFECT_UNSUPPORTED]
const TARGET_CREATURE := "creature"
const TARGET_SELF := "self"
const TARGET_CREATURE_OR_SELF := "creature_or_self"
const TARGET_ALLY := "ally"
const TARGETS: Array[String] = [TARGET_CREATURE, TARGET_SELF, TARGET_CREATURE_OR_SELF, TARGET_ALLY]
const CASTING_TIMES: Array[String] = ["action", "bonus_action"]
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
	s.display_name = str(d["display_name"])
	s.description = str(d.get("description", ""))
	s.school = str(d.get("school", ""))
	s.level = DictUtil.to_int(d["level"], -1)
	if s.level < 0 or s.level > 9:
		push_error("%s: level must be 0..9" % ctx)
		return null
	s.casting_time = str(d.get("casting_time", "action")).to_lower()
	if not CASTING_TIMES.has(s.casting_time):
		push_error("%s: casting_time must be action or bonus_action, got '%s'" % [ctx, s.casting_time])
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
	var e: Dictionary = effect_v
	s.raw_effect = e.duplicate(true)
	s.effect_type = str(e.get("type", "")).to_lower()
	if not EFFECT_TYPES.has(s.effect_type):
		push_error("%s: unknown effect type '%s'" % [ctx, s.effect_type])
		return null
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
	match s.effect_type:
		EFFECT_SPELL_ATTACK, EFFECT_SAVE:
			if s.effect_type == EFFECT_SPELL_ATTACK:
				s.melee = str(e.get("attack", "ranged")).to_lower() == "melee"
				s.rays = maxi(1, DictUtil.to_int(e.get("rays", 1), 1))
				s.half_on_miss = str(e.get("on_miss", "")).to_lower() == "half"
				var beams_v: Variant = e.get("beams", {})
				if typeof(beams_v) == TYPE_DICTIONARY:
					var beams_d: Dictionary = beams_v
					for key: Variant in beams_d.keys():
						s.beams[DictUtil.to_int(key, 1)] = maxi(1, DictUtil.to_int(beams_d[key], 1))
			if not DiceExpr.parse(s.damage).valid:
				push_error("%s: invalid damage '%s'" % [ctx, s.damage])
				return null
			if s.effect_type == EFFECT_SAVE:
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
		EFFECT_HEAL:
			s.heal_dice = str(e.get("dice", e.get("heal", "")))
			if not DiceExpr.parse(s.heal_dice).valid:
				push_error("%s: invalid heal dice '%s'" % [ctx, s.heal_dice])
				return null
			s.add_casting_mod = DictUtil.to_bool(e.get("add_casting_mod", false), false)
		EFFECT_BUFF:
			s.buff = str(e.get("buff", "")).to_lower()
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
		if s.damage_type.is_empty():
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
	return effect_type in [EFFECT_SPELL_ATTACK, EFFECT_AUTO_HIT, EFFECT_SAVE, EFFECT_MARK] \
			or (effect_type == EFFECT_BUFF and rider == RIDER_GUIDING)


## Whether the rules engine can resolve this spell (unsupported buffs are data only).
func is_supported() -> bool:
	if effect_type == EFFECT_UNSUPPORTED:
		return false
	if effect_type == EFFECT_BUFF:
		return SUPPORTED_BUFFS.has(buff) or rider == RIDER_GUIDING
	return true


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

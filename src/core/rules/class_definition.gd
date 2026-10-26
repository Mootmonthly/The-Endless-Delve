class_name ClassDefinition
extends RefCounted
## A character class loaded from data/classes/*.json.

const SCHEMA_VERSION := 1
const VALID_HIT_DICE := [6, 8, 10, 12]
## "spellcasting_ability" is also required unless a "spellcasting" key is present.
const REQUIRED_FIELDS: Array[String] = [
	"id", "display_name", "hit_die", "primary_abilities", "saving_throws",
	"armor_proficiencies", "weapon_proficiencies", "skill_choices",
	"skill_choice_count",
]
const DEFAULT_ASI_LEVELS: Array[int] = [4, 8, 12, 16, 19]
const SLOT_RECOVERY_LONG := "long_rest"
const SLOT_RECOVERY_SHORT := "short_rest"
## Level-1 mechanics the rules engine implements (others are flavour only).
const FEATURE_UNARMORED_DEFENSE_CON := "unarmored_defense_con"
const FEATURE_UNARMORED_DEFENSE_WIS := "unarmored_defense_wis"
const FEATURE_RAGE := "rage"
const FEATURE_MARTIAL_ARTS := "martial_arts"
const FEATURE_SECOND_WIND := "second_wind"
const FEATURE_SNEAK_ATTACK := "sneak_attack"
const FEATURE_LAY_ON_HANDS := "lay_on_hands"
const FEATURE_BARDIC_INSPIRATION := "bardic_inspiration"
const FEATURE_PACT_MAGIC := "pact_magic"

var id: String = ""
var display_name: String = ""
var hit_die: int = 8
var primary_abilities: Array[int] = []  # Ability.Type values
var saving_throws: Array[int] = []  # Ability.Type values
var armor_proficiencies: Array[String] = []
var weapon_proficiencies: Array[String] = []
var tool_proficiencies: Array[String] = []
var skill_choices: Array[int] = []  # Skill.Type values
var skill_choice_count: int = 0
var spellcasting_ability: int = -1  # Ability.Type, or -1 for none
var description: String = ""
## Starting equipment (all optional in JSON).
var starting_weapon: String = ""  # weapon id, "" = none
var starting_armor_base: int = 0  # 0 = no armor
var starting_armor_max_dex: int = -1  # -1 = no DEX cap
var starting_shield: bool = false
var starting_armor_item: String = ""  # optional item id in starting_armor {"item": ...}
## Resolved by ContentLoader.load_classes() from starting_weapon (null if unknown).
var starting_weapon_def: WeaponDefinition = null
## Starter kit: [{"item": id, "qty": int}, ...] added to the inventory at creation.
var starting_kit: Array[Dictionary] = []
## Feature ids gained at level 1 (see the FEATURE_* constants).
var features: Array[String] = []
## Features gained at later levels: level -> Array of ids ("features_by_level").
var features_by_level: Dictionary = {}
var asi_levels: Array[int] = DEFAULT_ASI_LEVELS.duplicate()
## Spellcasting ("spellcasting" object; null/absent = none).
var has_spellcasting: bool = false
var spells_prepared: Array[String] = []  # level-1 picks (cantrips + spells)
var spell_slot_table: Dictionary = {}  # character level (int) -> Array[int] slots per spell level
var slot_recovery: String = SLOT_RECOVERY_LONG
var spell_list: Array[String] = []  # every spell the class can learn / prepare
var cantrips_known_table: Dictionary = {}  # character level (int) -> int
var spells_known_table: Dictionary = {}  # character level (int) -> int (known casters)
var prepares_spells: bool = false  # prepared caster (casting mod + level spells prepared)
var spellbook_learn_per_level: int = 0  # wizard: spells added to the spellbook per level


## Returns null (and push_error) when a field is missing or invalid.
static func from_dict(d: Dictionary) -> ClassDefinition:
	if not DictUtil.require_keys(d, REQUIRED_FIELDS, "ClassDefinition"):
		return null
	var def := ClassDefinition.new()
	def.id = str(d["id"])
	var ctx := "ClassDefinition '%s'" % def.id
	if def.id.is_empty():
		push_error("%s: id must not be empty" % ctx)
		return null
	if d.has("schema_version") and DictUtil.to_int(d["schema_version"], -1) != SCHEMA_VERSION:
		push_error("%s: unsupported schema_version %s" % [ctx, str(d["schema_version"])])
		return null
	def.display_name = str(d["display_name"])
	def.description = str(d.get("description", ""))
	def.hit_die = DictUtil.to_int(d["hit_die"], 0)
	if not VALID_HIT_DICE.has(def.hit_die):
		push_error("%s: invalid hit_die %d" % [ctx, def.hit_die])
		return null
	def.primary_abilities = DictUtil.to_ability_array(d["primary_abilities"])
	def.saving_throws = DictUtil.to_ability_array(d["saving_throws"])
	if def.primary_abilities.has(-1) or def.saving_throws.has(-1):
		push_error("%s: unknown ability name in primary_abilities/saving_throws" % ctx)
		return null
	def.armor_proficiencies = DictUtil.to_string_array(d["armor_proficiencies"])
	def.weapon_proficiencies = DictUtil.to_string_array(d["weapon_proficiencies"])
	def.tool_proficiencies = DictUtil.to_string_array(d.get("tool_proficiencies", []))
	def.skill_choices = DictUtil.to_skill_array(d["skill_choices"])
	if def.skill_choices.has(-1):
		push_error("%s: unknown skill name in skill_choices" % ctx)
		return null
	def.skill_choice_count = DictUtil.to_int(d["skill_choice_count"], -1)
	if def.skill_choice_count < 0 or def.skill_choice_count > def.skill_choices.size():
		push_error("%s: skill_choice_count %d is out of range" % [ctx, def.skill_choice_count])
		return null
	if not d.has("spellcasting_ability") and not d.has("spellcasting"):
		push_error("%s: missing required field(s): spellcasting_ability" % ctx)
		return null
	var spell: Variant = d.get("spellcasting_ability", null)
	if spell == null or str(spell) == "" or str(spell).to_upper() == "NONE":
		def.spellcasting_ability = -1
	else:
		def.spellcasting_ability = Ability.from_string(str(spell))
		if def.spellcasting_ability == -1:
			push_error("%s: unknown spellcasting_ability '%s'" % [ctx, str(spell)])
			return null
	var weapon: Variant = d.get("starting_weapon", null)
	def.starting_weapon = "" if weapon == null else str(weapon)
	var armor: Variant = d.get("starting_armor", null)
	if typeof(armor) == TYPE_DICTIONARY:
		var armor_dict: Dictionary = armor
		def.starting_armor_base = DictUtil.to_int(armor_dict.get("base", 0), 0)
		def.starting_armor_max_dex = DictUtil.to_int(armor_dict.get("max_dex", -1), -1)
		def.starting_armor_item = "" if armor_dict.get("item") == null else str(armor_dict.get("item", ""))
		if def.starting_armor_base < 0 or def.starting_armor_max_dex < -1:
			push_error("%s: invalid starting_armor %s" % [ctx, str(armor_dict)])
			return null
	elif armor != null:
		push_error("%s: starting_armor must be an object or null" % ctx)
		return null
	def.starting_shield = DictUtil.to_bool(d.get("starting_shield", false), false)
	for raw in DictUtil.to_dict_array(d.get("starting_kit", [])):
		var item := str(raw.get("item", ""))
		var qty := DictUtil.to_int(raw.get("qty", 1), 0)
		if item.is_empty() or qty < 1:
			push_error("%s: invalid starting_kit entry %s" % [ctx, str(raw)])
			return null
		def.starting_kit.append({"item": item, "qty": qty})
	for f in DictUtil.to_string_array(d.get("features", [])):
		def.features.append(f.to_lower())
	var fbl: Variant = d.get("features_by_level", {})
	if typeof(fbl) == TYPE_DICTIONARY:
		var fbl_d: Dictionary = fbl
		for key: Variant in fbl_d.keys():
			var ids: Array[String] = []
			for f in DictUtil.to_string_array(fbl_d[key]):
				ids.append(f.to_lower())
			def.features_by_level[DictUtil.to_int(key, 0)] = ids
	if d.has("asi_levels"):
		def.asi_levels = DictUtil.to_int_array(d["asi_levels"])
	if not ClassDefinition._parse_spellcasting(def, d, ctx):
		return null
	return def


## Reads the "spellcasting" object. Level-up tables (spell_list, cantrips_known,
## spells_known, prepares, spellbook_learn_per_level) may sit inside it or at
## the top level of the class JSON.
static func _parse_spellcasting(def: ClassDefinition, d: Dictionary, ctx: String) -> bool:
	var sc_v: Variant = d.get("spellcasting", null)
	var sc: Dictionary = {}
	if typeof(sc_v) == TYPE_DICTIONARY:
		sc = sc_v
		def.has_spellcasting = true
	elif sc_v != null:
		push_error("%s: spellcasting must be an object or null" % ctx)
		return false
	if def.has_spellcasting:
		if sc.has("ability") and sc["ability"] != null:
			var ability := Ability.from_string(str(sc["ability"]))
			if ability < 0:
				push_error("%s: unknown spellcasting ability '%s'" % [ctx, str(sc["ability"])])
				return false
			def.spellcasting_ability = ability
		if def.spellcasting_ability < 0:
			push_error("%s: spellcasting needs an ability" % ctx)
			return false
		def.spells_prepared = DictUtil.to_string_array(sc.get("prepared", []))
		var slots_v: Variant = sc.get("slots", {})
		if typeof(slots_v) == TYPE_DICTIONARY:
			var slots_d: Dictionary = slots_v
			for key: Variant in slots_d.keys():
				var lvl := DictUtil.to_int(key, 0)
				var row := DictUtil.to_int_array(slots_d[key])
				if lvl < 1 or lvl > CharacterSheet.MAX_LEVEL or row.has(-1) or row.size() > 9:
					push_error("%s: invalid spell slot row %s: %s" % [ctx, str(key), str(slots_d[key])])
					return false
				def.spell_slot_table[lvl] = row
		def.slot_recovery = str(sc.get("slot_recovery", SLOT_RECOVERY_LONG)).to_lower()
		if def.features.has(FEATURE_PACT_MAGIC):
			def.slot_recovery = SLOT_RECOVERY_SHORT
		if not def.slot_recovery in [SLOT_RECOVERY_LONG, SLOT_RECOVERY_SHORT]:
			push_error("%s: slot_recovery must be long_rest or short_rest" % ctx)
			return false
	def.spell_list = DictUtil.to_string_array(sc.get("spell_list", d.get("spell_list", [])))
	def.cantrips_known_table = ClassDefinition._level_table(sc.get("cantrips_known", d.get("cantrips_known", {})))
	def.spells_known_table = ClassDefinition._level_table(sc.get("spells_known", d.get("spells_known", {})))
	def.prepares_spells = DictUtil.to_bool(sc.get("prepares", d.get("prepares", false)), false)
	def.spellbook_learn_per_level = DictUtil.to_int(sc.get("spellbook_learn_per_level", d.get("spellbook_learn_per_level", 0)), 0)
	return true


## {"1": 3, "4": 4} -> {1: 3, 4: 4}; anything else -> {}.
static func _level_table(v: Variant) -> Dictionary:
	var out := {}
	if typeof(v) == TYPE_DICTIONARY:
		var src: Dictionary = v
		for key: Variant in src.keys():
			out[DictUtil.to_int(key, 0)] = DictUtil.to_int(src[key], 0)
	return out


## Looks up a level table (as above): the entry of the highest level <= level, else fallback.
static func table_value(table: Dictionary, level: int, fallback: int = 0) -> int:
	var best := 0
	var value := fallback
	for key: int in table.keys():
		if key <= level and key > best:
			best = key
			value = DictUtil.to_int(table[key])
	return value


## Spell slots per spell level (index 0 = 1st level) at a character level:
## the row of the highest table level <= level; [] for non-casters.
func slots_for_level(level: int) -> Array[int]:
	var best := 0
	var out: Array[int] = []
	for key: int in spell_slot_table.keys():
		if key <= level and key > best:
			best = key
			var row: Array[int] = spell_slot_table[key]
			out = row.duplicate()
	return out


## Feature ids gained on reaching `level` (level 1 = `features`).
func features_at(level: int) -> Array[String]:
	if level <= 1:
		return features.duplicate()
	var out: Array[String] = []
	if features_by_level.has(level):
		var ids: Array[String] = features_by_level[level]
		out = ids.duplicate()
	return out


func has_feature(feature: String) -> bool:
	return features.has(feature)


func is_proficient_with(weapon: WeaponDefinition) -> bool:
	return weapon != null and (weapon_proficiencies.has(weapon.category) or weapon_proficiencies.has(weapon.id))


func is_spellcaster() -> bool:
	return spellcasting_ability >= 0

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
## Per-class numeric tables ("tables"): name -> {level (int): value} (rage_uses,
## rage_damage, sneak_attack_dice, martial_arts_die, ki_points, unarmored_movement,
## bardic_inspiration_die, extra_attacks, sorcery_points, invocations_known,
## channel_divinity_uses, lay_on_hands_pool, aura_radius, ...). Read with
## table_int / table_die.
var tables: Dictionary = {}
## The SRD subclass ("subclass" object; subclass_id "" = none).
var subclass_id: String = ""
var subclass_name: String = ""
var subclass_description: String = ""
var subclass_level: int = 0  # class level at which the subclass is chosen
var subclass_features_by_level: Dictionary = {}  # level -> Array[String]
var subclass_spells_by_level: Dictionary = {}  # level -> Array[String]
## "always_prepared" (domain / oath / circle spells) or "expanded_list" (added
## to the spells the class may learn).
var subclass_spells_mode: String = "always_prepared"
## Circle of the Land: terrain -> {level: Array[String]} (the terrain is the
## circle_of_the_land_<terrain> option of circle_spells).
var subclass_spells_by_terrain: Dictionary = {}
## Fighting style options ("fighting_styles"); empty = the class has none.
var fighting_style_options: Array[String] = []
var expertise_levels: Dictionary = {}  # level -> number of skills gaining expertise
var invocations_known_table: Dictionary = {}  # level -> invocations known (warlock)
var metamagic_known_table: Dictionary = {}  # level -> metamagic options known (sorcerer)
var sorcery_slot_costs: Dictionary = {}  # slot level -> sorcery points to create it


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
	def.features_by_level = ClassDefinition._id_lists_by_level(d.get("features_by_level", {}))
	if def.features.is_empty() and def.features_by_level.has(1):
		var first: Array[String] = def.features_by_level[1]
		def.features = first.duplicate()
	if d.has("asi_levels"):
		def.asi_levels = DictUtil.to_int_array(d["asi_levels"])
	var tables_v: Variant = d.get("tables", {})
	if typeof(tables_v) == TYPE_DICTIONARY:
		var tables_d: Dictionary = tables_v
		for key: Variant in tables_d.keys():
			var rows: Variant = tables_d[key]
			if typeof(rows) != TYPE_DICTIONARY:
				push_error("%s: table '%s' must be an object keyed by level" % [ctx, str(key)])
				return null
			var rows_d: Dictionary = rows
			var table := {}
			for lvl_v: Variant in rows_d.keys():
				table[DictUtil.to_int(lvl_v, 0)] = rows_d[lvl_v]
			def.tables[str(key)] = table
	var sub_v: Variant = d.get("subclass", null)
	if typeof(sub_v) == TYPE_DICTIONARY:
		var sub: Dictionary = sub_v
		def.subclass_id = str(sub.get("id", ""))
		def.subclass_name = str(sub.get("display_name", def.subclass_id))
		def.subclass_description = str(sub.get("description", ""))
		def.subclass_level = DictUtil.to_int(sub.get("level", 3), 3)
		def.subclass_features_by_level = ClassDefinition._id_lists_by_level(sub.get("features_by_level", {}))
		def.subclass_spells_by_level = ClassDefinition._id_lists_by_level(sub.get("spells_by_level", {}))
		def.subclass_spells_mode = str(sub.get("spells_mode", "always_prepared"))
		var terrains_v: Variant = sub.get("spells_by_terrain", {})
		if typeof(terrains_v) == TYPE_DICTIONARY:
			var terrains: Dictionary = terrains_v
			for terrain: Variant in terrains.keys():
				def.subclass_spells_by_terrain[str(terrain)] = ClassDefinition._id_lists_by_level(terrains[terrain])
		if def.subclass_id.is_empty() or def.subclass_level < 1 or def.subclass_level > CharacterSheet.MAX_LEVEL:
			push_error("%s: subclass needs an id and a level 1..20" % ctx)
			return null
	def.fighting_style_options = DictUtil.to_string_array(d.get("fighting_styles", []))
	def.expertise_levels = ClassDefinition._level_table(d.get("expertise_levels", {}))
	def.invocations_known_table = ClassDefinition._level_table(d.get("invocations_known", def.tables.get("invocations_known", {})))
	def.metamagic_known_table = ClassDefinition._level_table(d.get("metamagic_known", def.tables.get("metamagic_known", {})))
	def.sorcery_slot_costs = ClassDefinition._level_table(d.get("sorcery_slot_costs", {}))
	if not ClassDefinition._parse_spellcasting(def, d, ctx):
		return null
	return def


## {"3": ["a", "b"]} -> {3: ["a", "b"]} (ids lower-cased); anything else -> {}.
static func _id_lists_by_level(v: Variant) -> Dictionary:
	var out := {}
	if typeof(v) != TYPE_DICTIONARY:
		return out
	var src: Dictionary = v
	for key: Variant in src.keys():
		var ids: Array[String] = []
		for f in DictUtil.to_string_array(src[key]):
			ids.append(f.to_lower())
		out[DictUtil.to_int(key, 0)] = ids
	return out


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
		if not ClassDefinition._parse_slot_table(def, sc.get("slots", {}), ctx):
			return false
		def.slot_recovery = str(sc.get("slot_recovery", SLOT_RECOVERY_LONG)).to_lower()
		if not def.slot_recovery in [SLOT_RECOVERY_LONG, SLOT_RECOVERY_SHORT]:
			push_error("%s: slot_recovery must be long_rest or short_rest" % ctx)
			return false
	# The top-level full table (1..20, half casters from level 2, pact rows) wins.
	if typeof(d.get("spell_slots", null)) == TYPE_DICTIONARY:
		def.spell_slot_table.clear()
		if not ClassDefinition._parse_slot_table(def, d["spell_slots"], ctx):
			return false
	if def.features.has(FEATURE_PACT_MAGIC) or def.id == "warlock":
		def.slot_recovery = SLOT_RECOVERY_SHORT
	if not def.spell_slot_table.is_empty() and def.spellcasting_ability < 0:
		# Half casters without a level-1 "spellcasting" object (paladin, ranger):
		# the last mental ability among the primary abilities (CHA, WIS).
		for ability in def.primary_abilities:
			if ability in [Ability.Type.INT, Ability.Type.WIS, Ability.Type.CHA]:
				def.spellcasting_ability = ability
	def.spell_list = DictUtil.to_string_array(sc.get("spell_list", d.get("spell_list", [])))
	def.cantrips_known_table = ClassDefinition._level_table(sc.get("cantrips_known", d.get("cantrips_known", {})))
	def.spells_known_table = ClassDefinition._level_table(sc.get("spells_known", d.get("spells_known", {})))
	def.prepares_spells = DictUtil.to_bool(sc.get("prepares", d.get("prepares", false)), false)
	def.spellbook_learn_per_level = DictUtil.to_int(sc.get("spellbook_learn_per_level", d.get("spellbook_learn_per_level", 0)), 0)
	return true


static func _parse_slot_table(def: ClassDefinition, slots_v: Variant, ctx: String) -> bool:
	if typeof(slots_v) != TYPE_DICTIONARY:
		return true
	var slots_d: Dictionary = slots_v
	for key: Variant in slots_d.keys():
		var lvl := DictUtil.to_int(key, 0)
		var row := DictUtil.to_int_array(slots_d[key])
		if lvl < 1 or lvl > CharacterSheet.MAX_LEVEL or row.has(-1) or row.size() > 9:
			push_error("%s: invalid spell slot row %s: %s" % [ctx, str(key), str(slots_d[key])])
			return false
		# Trailing zero levels carry no information.
		while not row.is_empty() and row[row.size() - 1] == 0:
			row.remove_at(row.size() - 1)
		def.spell_slot_table[lvl] = row
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


## Subclass feature ids gained on reaching `level`.
func subclass_features_at(level: int) -> Array[String]:
	var out: Array[String] = []
	if subclass_features_by_level.has(level):
		var ids: Array[String] = subclass_features_by_level[level]
		out = ids.duplicate()
	return out


## Subclass spells granted at or below `level` (terrain: a Circle of the Land
## terrain, "" = spells_by_level).
func subclass_spells_through(level: int, terrain: String = "") -> Array[String]:
	var out: Array[String] = []
	var table: Dictionary = subclass_spells_by_level
	if not terrain.is_empty():
		table = subclass_spells_by_terrain.get(terrain, {})
	var keys: Array = table.keys()
	keys.sort()
	for key: Variant in keys:
		if DictUtil.to_int(key) <= level:
			var ids: Array[String] = table[key]
			for s in ids:
				if not out.has(s):
					out.append(s)
	return out


## Every subclass spell (any level, any terrain).
func all_subclass_spells() -> Array[String]:
	var out := subclass_spells_through(CharacterSheet.MAX_LEVEL)
	for terrain: Variant in subclass_spells_by_terrain.keys():
		for s in subclass_spells_through(CharacterSheet.MAX_LEVEL, str(terrain)):
			if not out.has(s):
				out.append(s)
	return out


## Half casters (paladin, ranger) gain their first slots after level 1.
func is_half_caster() -> bool:
	if spell_slot_table.is_empty():
		return false
	for n in slots_for_level(1):
		if n > 0:
			return false
	return true


func has_subclass() -> bool:
	return not subclass_id.is_empty()


## The value of a "tables" entry at `level` (highest key <= level), or null.
func table_raw(table_name: String, level: int) -> Variant:
	if not tables.has(table_name):
		return null
	var table: Dictionary = tables[table_name]
	var best := 0
	var value: Variant = null
	for key: Variant in table.keys():
		var k := DictUtil.to_int(key)
		if k <= level and k > best:
			best = k
			value = table[key]
	return value


## A table value as an int: numbers as is, "Unlimited" = 99, otherwise the
## first integer in the text ("3d6" -> 3, "+10 ft." -> 10); fallback if none.
func table_int(table_name: String, level: int, fallback: int = 0) -> int:
	var v: Variant = table_raw(table_name, level)
	if v == null:
		return fallback
	if DictUtil.is_number(v):
		return DictUtil.to_int(v, fallback)
	var text := str(v).to_lower()
	if text.contains("unlimited"):
		return 99
	var re := RegEx.new()
	re.compile("\\d+")
	var m := re.search(text)
	return m.get_string().to_int() if m != null else fallback


## A table value as a die size: "1d6" / "d6" -> 6, numbers as is; fallback if none.
func table_die(table_name: String, level: int, fallback: int = 0) -> int:
	var v: Variant = table_raw(table_name, level)
	if v == null:
		return fallback
	if DictUtil.is_number(v):
		return DictUtil.to_int(v, fallback)
	var re := RegEx.new()
	re.compile("d(\\d+)")
	var m := re.search(str(v).to_lower())
	return m.get_string(1).to_int() if m != null else fallback


func has_feature(feature: String) -> bool:
	return features.has(feature)


func is_proficient_with(weapon: WeaponDefinition) -> bool:
	return weapon != null and (weapon_proficiencies.has(weapon.category) or weapon_proficiencies.has(weapon.id))


func is_spellcaster() -> bool:
	return spellcasting_ability >= 0

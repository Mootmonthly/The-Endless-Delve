class_name ClassDefinition
extends RefCounted
## A character class loaded from data/classes/*.json.

const SCHEMA_VERSION := 1
const VALID_HIT_DICE := [6, 8, 10, 12]
const REQUIRED_FIELDS: Array[String] = [
	"id", "display_name", "hit_die", "primary_abilities", "saving_throws",
	"armor_proficiencies", "weapon_proficiencies", "skill_choices",
	"skill_choice_count", "spellcasting_ability",
]

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
## Resolved by ContentLoader.load_classes() from starting_weapon (null if unknown).
var starting_weapon_def: WeaponDefinition = null


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
	var spell: Variant = d["spellcasting_ability"]
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
		if def.starting_armor_base < 0 or def.starting_armor_max_dex < -1:
			push_error("%s: invalid starting_armor %s" % [ctx, str(armor_dict)])
			return null
	elif armor != null:
		push_error("%s: starting_armor must be an object or null" % ctx)
		return null
	def.starting_shield = DictUtil.to_bool(d.get("starting_shield", false), false)
	return def


func is_proficient_with(weapon: WeaponDefinition) -> bool:
	return weapon != null and (weapon_proficiencies.has(weapon.category) or weapon_proficiencies.has(weapon.id))


func is_spellcaster() -> bool:
	return spellcasting_ability >= 0

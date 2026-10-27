class_name AncestryDefinition
extends RefCounted
## A playable ancestry (SRD 5.1 race/subrace) loaded from data/ancestries/*.json.
## Only the numbers the rules use so far are typed; traits are descriptive.

const SCHEMA_VERSION := 1
const REQUIRED_FIELDS: Array[String] = ["id", "display_name", "speed", "ability_bonuses", "size"]
const VALID_SIZES: Array[String] = ["small", "medium"]

var id: String = ""
var display_name: String = ""
var speed: int = 30  # walking speed in feet
var ability_bonuses: Dictionary[int, int] = {}  # Ability.Type -> bonus
var size: String = "medium"
var traits: Array[Dictionary] = []  # {"name", "description"}; descriptive only for now
var description: String = ""
## Darkvision range in feet: "darkvision_ft", else a "Darkvision" trait (its
## "within N feet", default 60); 0 = none.
var darkvision_ft: int = 0


## Returns null (and push_error) when a field is missing or invalid.
static func from_dict(d: Dictionary) -> AncestryDefinition:
	if not DictUtil.require_keys(d, REQUIRED_FIELDS, "AncestryDefinition"):
		return null
	var a := AncestryDefinition.new()
	a.id = str(d["id"])
	var ctx := "AncestryDefinition '%s'" % a.id
	if a.id.is_empty():
		push_error("%s: id must not be empty" % ctx)
		return null
	if d.has("schema_version") and DictUtil.to_int(d["schema_version"], -1) != SCHEMA_VERSION:
		push_error("%s: unsupported schema_version %s" % [ctx, str(d["schema_version"])])
		return null
	a.display_name = str(d["display_name"])
	a.description = str(d.get("description", ""))
	a.speed = DictUtil.to_int(d["speed"], -1)
	if a.speed <= 0 or a.speed % GridMath.FEET_PER_TILE != 0:
		push_error("%s: speed must be a positive multiple of 5 ft" % ctx)
		return null
	a.size = str(d["size"]).to_lower()
	if not VALID_SIZES.has(a.size):
		push_error("%s: unknown size '%s'" % [ctx, a.size])
		return null
	var bonuses: Variant = d["ability_bonuses"]
	if typeof(bonuses) != TYPE_DICTIONARY:
		push_error("%s: ability_bonuses must be an object" % ctx)
		return null
	var bonus_dict: Dictionary = bonuses
	for key: Variant in bonus_dict.keys():
		var ability := Ability.from_string(str(key))
		if ability < 0:
			push_error("%s: unknown ability '%s' in ability_bonuses" % [ctx, str(key)])
			return null
		a.ability_bonuses[ability] = DictUtil.to_int(bonus_dict[key], 0)
	a.traits = DictUtil.to_dict_array(d.get("traits", []))
	a.darkvision_ft = DictUtil.to_int(d.get("darkvision_ft", 0), 0)
	if a.darkvision_ft <= 0:
		for t in a.traits:
			if str(t.get("name", "")).to_lower() == "darkvision":
				var ft := MonsterDefinition.sense_ft(str(t.get("description", "")).to_lower(), "within")
				a.darkvision_ft = ft if ft > 0 else 60
	return a


func bonus_for(ability: int) -> int:
	var bonus: int = ability_bonuses.get(ability, 0)
	return bonus

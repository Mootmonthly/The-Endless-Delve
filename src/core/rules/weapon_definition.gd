class_name WeaponDefinition
extends RefCounted
## A weapon from the SRD equipment tables, loaded from data/weapons/*.json.

const SCHEMA_VERSION := 1
const REQUIRED_FIELDS: Array[String] = ["id", "display_name", "damage", "damage_type", "properties", "category"]
const CATEGORIES: Array[String] = ["simple", "martial"]

var id: String = ""
var display_name: String = ""
var damage: String = "1d4"  # dice only, no modifier
var damage_type: String = ""
var properties: Array[String] = []  # "finesse", "light", "thrown", "versatile", ...
var category: String = "simple"
var versatile_damage: String = ""  # two-handed damage for versatile weapons
var range_ft: Array[int] = []  # [normal, long] for thrown weapons


## Returns null (and push_error) when a field is missing or invalid.
static func from_dict(d: Dictionary) -> WeaponDefinition:
	if not DictUtil.require_keys(d, REQUIRED_FIELDS, "WeaponDefinition"):
		return null
	var w := WeaponDefinition.new()
	w.id = str(d["id"])
	var ctx := "WeaponDefinition '%s'" % w.id
	if w.id.is_empty():
		push_error("%s: id must not be empty" % ctx)
		return null
	if d.has("schema_version") and DictUtil.to_int(d["schema_version"], -1) != SCHEMA_VERSION:
		push_error("%s: unsupported schema_version %s" % [ctx, str(d["schema_version"])])
		return null
	w.display_name = str(d["display_name"])
	w.damage = str(d["damage"])
	var expr := DiceExpr.parse(w.damage)
	if not expr.valid or expr.is_constant() or expr.modifier != 0:
		push_error("%s: damage must be plain dice such as '1d8', got '%s'" % [ctx, w.damage])
		return null
	w.damage_type = str(d["damage_type"]).to_lower()
	if w.damage_type.is_empty():
		push_error("%s: damage_type must not be empty" % ctx)
		return null
	for p in DictUtil.to_string_array(d["properties"]):
		w.properties.append(p.to_lower())
	w.category = str(d["category"]).to_lower()
	if not CATEGORIES.has(w.category):
		push_error("%s: category must be simple or martial, got '%s'" % [ctx, w.category])
		return null
	w.versatile_damage = str(d.get("versatile_damage", ""))
	if not w.versatile_damage.is_empty() and not DiceExpr.parse(w.versatile_damage).valid:
		push_error("%s: invalid versatile_damage '%s'" % [ctx, w.versatile_damage])
		return null
	w.range_ft = DictUtil.to_int_array(d.get("range_ft", []))
	return w


func has_property(property: String) -> bool:
	return properties.has(property)


func is_finesse() -> bool:
	return has_property("finesse")

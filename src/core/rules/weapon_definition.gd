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
var range_ft: Array[int] = []  # [normal, long] for thrown and ranged weapons
var ammo_id: String = ""  # ammunition item id for "ammunition" weapons ("" = none needed)
var ranged: bool = false  # a ranged weapon (bow, crossbow, sling, dart): "ranged": true, "ammunition" or "type": "ranged"


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
	if not w.range_ft.is_empty() and (w.range_ft.size() != 2 or w.range_ft[0] <= 0 or w.range_ft[1] < w.range_ft[0]):
		push_error("%s: range_ft must be [normal, long] with 0 < normal <= long" % ctx)
		return null
	w.ammo_id = "" if d.get("ammo_id") == null else str(d.get("ammo_id", ""))
	var weapon_type := str(d.get("type", d.get("weapon_type", ""))).to_lower()
	w.ranged = w.has_property("ammunition") or weapon_type == "ranged" or DictUtil.to_bool(d.get("ranged", false), false)
	if (w.ranged or w.has_property("thrown")) and w.range_ft.is_empty():
		push_error("%s: thrown and ranged weapons need range_ft" % ctx)
		return null
	return w


func has_property(property: String) -> bool:
	return properties.has(property)


func is_finesse() -> bool:
	return has_property("finesse")


func is_thrown() -> bool:
	return has_property("thrown")


func is_two_handed() -> bool:
	return has_property("two-handed") or has_property("two_handed")


## [normal, long] in tiles; [1, 1] (reach) when the weapon has no range.
func range_tiles() -> Array[int]:
	if range_ft.size() != 2:
		return [1, 1]
	return [GridMath.feet_to_tiles(range_ft[0]), GridMath.feet_to_tiles(range_ft[1])]

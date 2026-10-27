class_name ItemDefinition
extends RefCounted
## An item from data/items/*.json: weapon, armor, shield, consumable, ammo,
## gold, key or misc. Weapon items point at a WeaponDefinition by `weapon_id`.
## A key opens the floor door whose `key_item` names it (and is used up).
##
## {"schema_version": 1, "id", "display_name", "kind", "description",
##  "weight": float, "value_gp": float, "stackable": bool,
##  "weapon_id": String (weapon), "ammo_id": String (weapon that needs ammunition),
##  "armor": {"base", "max_dex", "category", "stealth_disadvantage"} (armor),
##  "shield": {"bonus"} (shield),
##  "use": {"action": "action"|"bonus_action", "effect": "heal"|"temp_hp"|"cure",
##          "dice": "2d4+2", "target": "self"|"touch", "conditions": [...]} (consumable),
##  "bonus": int (magic +N weapon / armor / shield: attack and damage rolls,
##            or AC, while equipped; 0 = mundane)}

const SCHEMA_VERSION := 1
const REQUIRED_FIELDS: Array[String] = ["id", "display_name", "kind"]
const KIND_WEAPON := "weapon"
const KIND_ARMOR := "armor"
const KIND_SHIELD := "shield"
const KIND_CONSUMABLE := "consumable"
const KIND_AMMO := "ammo"
const KIND_GOLD := "gold"
const KIND_MISC := "misc"
const KIND_KEY := "key"
const KINDS: Array[String] = [KIND_WEAPON, KIND_ARMOR, KIND_SHIELD, KIND_CONSUMABLE, KIND_AMMO, KIND_GOLD, KIND_MISC, KIND_KEY]
const USE_ACTIONS: Array[String] = ["action", "bonus_action"]
const EFFECT_HEAL := "heal"
const EFFECT_TEMP_HP := "temp_hp"
const EFFECT_CURE := "cure"
const USE_EFFECTS: Array[String] = [EFFECT_HEAL, EFFECT_TEMP_HP, EFFECT_CURE]
const USE_TARGETS: Array[String] = ["self", "touch"]
const ARMOR_CATEGORIES: Array[String] = ["light", "medium", "heavy"]

var id: String = ""
var display_name: String = ""
var kind: String = KIND_MISC
var description: String = ""
var weight: float = 0.0
var value_gp: float = 0.0
var stackable: bool = false
var weapon_id: String = ""
var ammo_id: String = ""
var armor_base: int = 0
var armor_max_dex: int = -1  # -1 = no cap, 0 = heavy
var armor_category: String = ""
var stealth_disadvantage: bool = false
var shield_bonus: int = 0
## Magic enhancement (+1..+3) of a weapon, armor or shield item; 0 otherwise.
var bonus: int = 0
var use_action: String = ""  # "" = not usable
var use_effect: String = ""
var use_dice: String = ""
var use_target: String = "self"
var use_conditions: Array[String] = []


## Returns null (and push_error) when a field is missing or invalid.
static func from_dict(d: Dictionary) -> ItemDefinition:
	if not DictUtil.require_keys(d, REQUIRED_FIELDS, "ItemDefinition"):
		return null
	var it := ItemDefinition.new()
	it.id = str(d["id"])
	var ctx := "ItemDefinition '%s'" % it.id
	if it.id.is_empty():
		push_error("%s: id must not be empty" % ctx)
		return null
	if d.has("schema_version") and DictUtil.to_int(d["schema_version"], -1) != SCHEMA_VERSION:
		push_error("%s: unsupported schema_version %s" % [ctx, str(d["schema_version"])])
		return null
	it.display_name = str(d["display_name"])
	it.kind = str(d["kind"]).to_lower()
	if not KINDS.has(it.kind):
		push_error("%s: unknown kind '%s'" % [ctx, it.kind])
		return null
	it.description = str(d.get("description", ""))
	it.weight = maxf(0.0, DictUtil.to_float(d.get("weight", 0.0), 0.0))
	it.value_gp = maxf(0.0, DictUtil.to_float(d.get("value_gp", 0.0), 0.0))
	var default_stack := it.kind in [KIND_CONSUMABLE, KIND_AMMO, KIND_GOLD]
	it.stackable = DictUtil.to_bool(d.get("stackable", default_stack), default_stack)
	it.weapon_id = _opt_str(d.get("weapon_id", ""))
	it.ammo_id = _opt_str(d.get("ammo_id", ""))
	if it.kind in [KIND_WEAPON, KIND_ARMOR, KIND_SHIELD]:
		it.bonus = maxi(0, DictUtil.to_int(d.get("bonus", 0), 0))
	match it.kind:
		KIND_WEAPON:
			if it.weapon_id.is_empty():
				push_error("%s: weapon items need a weapon_id" % ctx)
				return null
		KIND_ARMOR:
			var armor_v: Variant = d.get("armor", null)
			if typeof(armor_v) != TYPE_DICTIONARY:
				push_error("%s: armor items need an \"armor\" object" % ctx)
				return null
			var armor: Dictionary = armor_v
			it.armor_base = DictUtil.to_int(armor.get("base", 0), 0)
			it.armor_max_dex = DictUtil.to_int(armor.get("max_dex", -1), -1)
			it.armor_category = str(armor.get("category", "")).to_lower()
			it.stealth_disadvantage = DictUtil.to_bool(armor.get("stealth_disadvantage", false), false)
			if it.armor_base <= 0 or it.armor_max_dex < -1:
				push_error("%s: invalid armor %s" % [ctx, str(armor)])
				return null
			if not it.armor_category.is_empty() and not ARMOR_CATEGORIES.has(it.armor_category):
				push_error("%s: unknown armor category '%s'" % [ctx, it.armor_category])
				return null
		KIND_SHIELD:
			var shield_v: Variant = d.get("shield", {"bonus": 2})
			if typeof(shield_v) != TYPE_DICTIONARY:
				push_error("%s: \"shield\" must be an object" % ctx)
				return null
			var shield: Dictionary = shield_v
			it.shield_bonus = DictUtil.to_int(shield.get("bonus", 2), 2)
			if it.shield_bonus <= 0:
				push_error("%s: shield bonus must be positive" % ctx)
				return null
	var use_v: Variant = d.get("use", null)
	if typeof(use_v) == TYPE_DICTIONARY:
		var use: Dictionary = use_v
		it.use_action = str(use.get("action", "action")).to_lower()
		it.use_effect = str(use.get("effect", "")).to_lower()
		it.use_dice = str(use.get("dice", ""))
		it.use_target = str(use.get("target", "self")).to_lower()
		it.use_conditions = DictUtil.to_string_array(use.get("conditions", []))
		if not USE_ACTIONS.has(it.use_action):
			push_error("%s: use.action must be action or bonus_action, got '%s'" % [ctx, it.use_action])
			return null
		if it.use_effect.is_empty():
			push_error("%s: use.effect is empty" % ctx)
			return null
		if not USE_TARGETS.has(it.use_target):
			push_error("%s: use.target must be self or touch, got '%s'" % [ctx, it.use_target])
			return null
		if it.use_effect in [EFFECT_HEAL, EFFECT_TEMP_HP]:
			var expr := DiceExpr.parse(it.use_dice)
			if not expr.valid:
				push_error("%s: use.dice '%s' is not a dice expression" % [ctx, it.use_dice])
				return null
	elif use_v != null:
		push_error("%s: \"use\" must be an object or null" % ctx)
		return null
	if it.kind == KIND_CONSUMABLE and it.use_action.is_empty():
		push_error("%s: consumables need a \"use\" object" % ctx)
		return null
	return it


func is_usable() -> bool:
	return not use_action.is_empty()


## Usable in combat by the rules engine (heal, temp_hp and cure are implemented).
func has_implemented_use() -> bool:
	return USE_EFFECTS.has(use_effect)


func to_dict() -> Dictionary:
	var d := {
		"schema_version": SCHEMA_VERSION,
		"id": id,
		"display_name": display_name,
		"kind": kind,
		"description": description,
		"weight": weight,
		"value_gp": value_gp,
		"stackable": stackable,
	}
	if not weapon_id.is_empty():
		d["weapon_id"] = weapon_id
	if not ammo_id.is_empty():
		d["ammo_id"] = ammo_id
	if kind == KIND_ARMOR:
		d["armor"] = {"base": armor_base, "max_dex": armor_max_dex, "category": armor_category, "stealth_disadvantage": stealth_disadvantage}
	if kind == KIND_SHIELD:
		d["shield"] = {"bonus": shield_bonus}
	if bonus > 0:
		d["bonus"] = bonus
	if is_usable():
		d["use"] = {"action": use_action, "effect": use_effect, "dice": use_dice, "target": use_target, "conditions": use_conditions.duplicate()}
	return d


static func _opt_str(v: Variant) -> String:
	return "" if v == null else str(v)

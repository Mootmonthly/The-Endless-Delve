class_name MonsterDefinition
extends RefCounted
## A monster stat block loaded from data/monsters/*.json (SRD 5.1).

const SCHEMA_VERSION := 1
const REQUIRED_FIELDS: Array[String] = [
	"id", "display_name", "armor_class", "hit_points", "hit_dice", "speed",
	"abilities", "challenge_rating", "xp", "attacks",
]
const ATTACK_FIELDS: Array[String] = ["name", "to_hit", "damage", "damage_type"]

var id: String = ""
var display_name: String = ""
var armor_class: int = 10
var hit_points_avg: int = 1
var hit_dice: String = "1d8"
var speed: int = 30
var abilities: AbilityScores = AbilityScores.new()
var challenge_rating: float = 0.0
var xp: int = 0
## Each: {"name", "kind", "to_hit": int, "damage": dice expr, "damage_type"};
## ranged attacks also get "range_tiles": [normal, long] from "range_ft".
var attacks: Array[Dictionary] = []
var damage_resistances: Array[String] = []
var damage_immunities: Array[String] = []
var damage_vulnerabilities: Array[String] = []
var condition_immunities: Array[String] = []
var traits: Array[Dictionary] = []  # {"name", "description"}; descriptive only for now
var loot_table: String = ""  # LootTable id rolled when it dies ("" = no drops)


## Returns null (and push_error) when a field is missing or invalid.
static func from_dict(d: Dictionary) -> MonsterDefinition:
	if not DictUtil.require_keys(d, REQUIRED_FIELDS, "MonsterDefinition"):
		return null
	var m := MonsterDefinition.new()
	m.id = str(d["id"])
	var ctx := "MonsterDefinition '%s'" % m.id
	if m.id.is_empty():
		push_error("%s: id must not be empty" % ctx)
		return null
	if d.has("schema_version") and DictUtil.to_int(d["schema_version"], -1) != SCHEMA_VERSION:
		push_error("%s: unsupported schema_version %s" % [ctx, str(d["schema_version"])])
		return null
	m.display_name = str(d["display_name"])
	m.armor_class = DictUtil.to_int(d["armor_class"], -1)
	m.hit_points_avg = DictUtil.to_int(d["hit_points"], -1)
	m.hit_dice = str(d["hit_dice"])
	m.speed = DictUtil.to_int(d["speed"], -1)
	m.challenge_rating = DictUtil.to_float(d["challenge_rating"], -1.0)
	m.xp = DictUtil.to_int(d["xp"], -1)
	if m.armor_class < 0 or m.hit_points_avg < 1 or m.speed < 0 or m.challenge_rating < 0.0 or m.xp < 0:
		push_error("%s: armor_class/hit_points/speed/challenge_rating/xp invalid" % ctx)
		return null
	if not DiceExpr.parse(m.hit_dice).valid:
		push_error("%s: invalid hit_dice '%s'" % [ctx, m.hit_dice])
		return null
	var ab: Variant = d["abilities"]
	if typeof(ab) != TYPE_DICTIONARY:
		push_error("%s: abilities must be an object" % ctx)
		return null
	var ab_dict: Dictionary = ab
	if not DictUtil.require_keys(ab_dict, ["STR", "DEX", "CON", "INT", "WIS", "CHA"], ctx + " abilities"):
		return null
	m.abilities = AbilityScores.from_dict(ab_dict)
	for raw in DictUtil.to_dict_array(d["attacks"]):
		if not DictUtil.require_keys(raw, ATTACK_FIELDS, ctx + " attack"):
			return null
		var attack: Dictionary = raw.duplicate(true)
		attack["name"] = str(raw["name"])
		attack["kind"] = str(raw.get("kind", "melee"))
		attack["to_hit"] = DictUtil.to_int(raw["to_hit"], 0)
		attack["damage"] = str(raw["damage"])
		attack["damage_type"] = str(raw["damage_type"]).to_lower()
		if attack.has("range_ft"):
			var ft := DictUtil.to_int_array(attack["range_ft"])
			if ft.size() == 2:
				attack["range_ft"] = ft
				attack["range_tiles"] = [GridMath.feet_to_tiles(ft[0]), GridMath.feet_to_tiles(ft[1])]
		if not DiceExpr.parse(str(attack["damage"])).valid:
			push_error("%s: attack '%s' has invalid damage '%s'" % [ctx, attack["name"], attack["damage"]])
			return null
		m.attacks.append(attack)
	if m.attacks.is_empty():
		push_error("%s: needs at least one attack" % ctx)
		return null
	m.damage_resistances = DictUtil.to_string_array(d.get("damage_resistances", []))
	m.damage_immunities = DictUtil.to_string_array(d.get("damage_immunities", []))
	m.damage_vulnerabilities = DictUtil.to_string_array(d.get("damage_vulnerabilities", []))
	m.condition_immunities = DictUtil.to_string_array(d.get("condition_immunities", []))
	m.traits = DictUtil.to_dict_array(d.get("traits", []))
	m.loot_table = "" if d.get("loot_table") == null else str(d.get("loot_table", ""))
	return m


## Builds a CharacterSheet for this monster. Uses average hp unless roll_hp is
## true and an rng is given. Monsters don't make death saves: 0 hp means dead.
func to_sheet(rng: Rng = null, roll_hp: bool = false) -> CharacterSheet:
	var sheet := CharacterSheet.new()
	sheet.name = display_name
	sheet.class_id = "monster:" + id
	sheet.abilities = abilities.copy()
	var hp := hit_points_avg
	var dice := DiceExpr.parse(hit_dice)
	if roll_hp and rng != null and dice.valid:
		hp = maxi(1, dice.roll(rng).total)
	sheet.max_hp = hp
	sheet.current_hp = hp
	# Stat-block AC already includes DEX: store it as armor whose base cancels DEX out.
	sheet.armor_base = armor_class - sheet.abilities.get_modifier(Ability.Type.DEX)
	sheet.armor_max_dex = -1
	sheet.shield_bonus = 0
	sheet.speed = speed
	sheet.uses_death_saves = false
	sheet.hit_die = dice.sides if dice.valid and dice.sides > 0 else 8
	sheet.hit_dice_total = maxi(1, dice.count)
	sheet.hit_dice_remaining = sheet.hit_dice_total
	sheet.damage_resistances = damage_resistances.duplicate()
	sheet.damage_immunities = damage_immunities.duplicate()
	sheet.damage_vulnerabilities = damage_vulnerabilities.duplicate()
	return sheet

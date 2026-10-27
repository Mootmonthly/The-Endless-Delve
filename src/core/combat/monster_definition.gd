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
var creature_type: String = ""  # "undead", "humanoid", "beast", ... (lower case; "" = unknown)
## Multiattack: attack names used by one Attack action, in order ([] = one attack).
var multiattack: Array[String] = []
var size: String = "medium"
var skills: Dictionary[int, int] = {}  # Skill.Type -> total bonus ("skills": {"STEALTH": 4})
var saving_throws: Dictionary[int, int] = {}  # Ability.Type -> total bonus ("saving_throws": {"DEX": 5})
var proficiency_bonus: int = 0  # 0 = derived from the challenge rating
var fly_speed: int = 0  # feet ("speeds": {"fly": 60})
## Senses in feet parsed from "senses" ("darkvision 60 ft., blindsight 10 ft., ...").
var darkvision_ft: int = 0
var blindsight_ft: int = 0
var truesight_ft: int = 0
var icon: String = ""  # optional icon id ("" = none)


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
	m.creature_type = "" if d.get("creature_type") == null else str(d.get("creature_type", "")).to_lower()
	# Multiattack names an attack each; unknown names count as the first attack.
	m.multiattack = DictUtil.to_string_array(d.get("multiattack", []))
	for attack_name in m.multiattack:
		if m.attack_index(attack_name) < 0:
			push_warning("%s: multiattack names unknown attack '%s'" % [ctx, attack_name])
	m.size = str(d.get("size", "medium")).to_lower()
	var skills_v: Variant = d.get("skills", {})
	if typeof(skills_v) == TYPE_DICTIONARY:
		var skills_d: Dictionary = skills_v
		for key: Variant in skills_d.keys():
			var skill := Skill.from_string(str(key))
			if skill >= 0:
				m.skills[skill] = DictUtil.to_int(skills_d[key], 0)
	var saves_v: Variant = d.get("saving_throws", {})
	if typeof(saves_v) == TYPE_DICTIONARY:
		var saves_d: Dictionary = saves_v
		for key: Variant in saves_d.keys():
			var ability := Ability.from_string(str(key))
			if ability >= 0:
				m.saving_throws[ability] = DictUtil.to_int(saves_d[key], 0)
	m.proficiency_bonus = DictUtil.to_int(d.get("proficiency_bonus", 0), 0)
	m.icon = "" if d.get("icon") == null else str(d.get("icon", ""))
	var speeds_v: Variant = d.get("speeds", {})
	if typeof(speeds_v) == TYPE_DICTIONARY:
		var speeds_d: Dictionary = speeds_v
		m.fly_speed = DictUtil.to_int(speeds_d.get("fly", 0), 0)
	var senses := "" if d.get("senses") == null else str(d.get("senses", "")).to_lower()
	m.darkvision_ft = MonsterDefinition.sense_ft(senses, "darkvision")
	m.blindsight_ft = MonsterDefinition.sense_ft(senses, "blindsight")
	m.truesight_ft = MonsterDefinition.sense_ft(senses, "truesight")
	return m


## The range in feet of a sense named in a stat block's senses text ("darkvision
## 60 ft., passive Perception 9" -> 60 for "darkvision"; 0 when absent).
static func sense_ft(senses: String, sense: String) -> int:
	var at := senses.find(sense)
	if at < 0:
		return 0
	var digits := ""
	for ch in senses.substr(at + sense.length()):
		if ch >= "0" and ch <= "9":
			digits += ch
		elif ch == " " and digits.is_empty():
			continue
		else:
			break
	return digits.to_int()


## Index of the attack with this name (case-insensitive), or -1.
func attack_index(attack_name: String) -> int:
	for i in range(attacks.size()):
		if str(attacks[i]["name"]).to_lower() == attack_name.to_lower():
			return i
	return -1


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
	sheet.condition_immunities = condition_immunities.duplicate()
	sheet.size = size
	sheet.skill_bonuses = skills.duplicate()
	sheet.save_bonuses = saving_throws.duplicate()
	sheet.proficiency_override = proficiency_bonus
	sheet.fly_speed = fly_speed
	sheet.darkvision_ft = darkvision_ft
	sheet.blindsight_ft = blindsight_ft
	sheet.truesight_ft = truesight_ft
	return sheet

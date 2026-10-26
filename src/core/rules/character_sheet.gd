class_name CharacterSheet
extends RefCounted
## A creature's rules state: abilities, hit points, proficiencies, death saves.
## Player characters and (for simplicity) monsters both use this class.

const SCHEMA_VERSION := 1
const MAX_LEVEL := 20
const DEATH_SAVES_NEEDED := 3

var name: String = ""
var class_id: String = ""
var level: int = 1
var xp: int = 0
var abilities: AbilityScores = AbilityScores.new()
var max_hp: int = 1
var current_hp: int = 1
var temp_hp: int = 0
var armor_bonus: int = 0  # added to 10 + DEX modifier (armor, shield, natural armor)
var speed: int = 30
var hit_die: int = 8
var hit_dice_total: int = 1  # equals level for characters
var hit_dice_remaining: int = 1
var proficient_saves: Array[int] = []  # Ability.Type values
var proficient_skills: Array[int] = []  # Skill.Type values
var death_save_successes: int = 0
var death_save_failures: int = 0
var stable: bool = false
var dead: bool = false
var uses_death_saves: bool = true  # false for monsters: they die at 0 hp
var conditions: Array[String] = []
var damage_resistances: Array[String] = []
var damage_immunities: Array[String] = []
var damage_vulnerabilities: Array[String] = []
var deepest_floor: int = 0


func proficiency_bonus() -> int:
	return Proficiency.bonus_for_level(level)


func armor_class() -> int:
	return 10 + abilities.get_modifier(Ability.Type.DEX) + armor_bonus


func ability_modifier(ability: int) -> int:
	return abilities.get_modifier(ability)


func save_modifier(ability: int) -> int:
	var mod := abilities.get_modifier(ability)
	if proficient_saves.has(ability):
		mod += proficiency_bonus()
	return mod


func skill_modifier(skill: int) -> int:
	var mod := abilities.get_modifier(Skill.ability_for(skill))
	if proficient_skills.has(skill):
		mod += proficiency_bonus()
	return mod


func initiative_modifier() -> int:
	return abilities.get_modifier(Ability.Type.DEX)


func is_alive() -> bool:
	return not dead


func is_dead() -> bool:
	return dead


func is_unconscious() -> bool:
	return not dead and current_hp == 0


func is_conscious() -> bool:
	return not dead and current_hp > 0


## Applies immunity (0), resistance (half, rounded down) and vulnerability (double).
func adjust_damage_for_type(amount: int, damage_type: String) -> int:
	var t := damage_type.to_lower()
	if t.is_empty():
		return amount
	if damage_immunities.has(t):
		return 0
	var result := amount
	if damage_resistances.has(t):
		result = floori(result / 2.0)
	if damage_vulnerabilities.has(t):
		result *= 2
	return result


## Temporary hit points don't stack: keep the larger value.
func grant_temp_hp(amount: int) -> void:
	temp_hp = maxi(temp_hp, amount)


## SRD damage rules: temp hp absorbs first; dropping to 0 knocks a character
## unconscious (monsters die); leftover damage >= max hp is instant death;
## damage while at 0 hp is one death-save failure (two on a critical hit).
func take_damage(amount: int, critical: bool = false) -> DamageOutcome:
	var out := DamageOutcome.new()
	out.amount = maxi(amount, 0)
	out.critical = critical
	if dead:
		out.hp_after = current_hp
		return out
	var remaining := out.amount
	var absorbed := mini(temp_hp, remaining)
	temp_hp -= absorbed
	remaining -= absorbed
	out.absorbed_by_temp = absorbed
	if remaining > 0:
		if current_hp > 0:
			if remaining < current_hp:
				current_hp -= remaining
				out.hp_lost = remaining
			else:
				var leftover := remaining - current_hp
				out.hp_lost = current_hp
				current_hp = 0
				out.dropped_to_zero = true
				if leftover >= max_hp:
					out.instant_death = true
					out.died = true
					_die()
				elif not uses_death_saves:
					out.died = true
					_die()
				else:
					reset_death_saves()
		else:
			if remaining >= max_hp:
				out.instant_death = true
				out.died = true
				_die()
			else:
				var added := 2 if critical else 1
				out.death_save_failures_added = added
				stable = false
				death_save_failures = mini(DEATH_SAVES_NEEDED, death_save_failures + added)
				if death_save_failures >= DEATH_SAVES_NEEDED:
					out.died = true
					_die()
	out.hp_after = current_hp
	return out


## Returns hit points actually restored. Healing from 0 hp resets death saves.
func heal(amount: int) -> int:
	if dead or amount <= 0:
		return 0
	var before := current_hp
	current_hp = mini(max_hp, current_hp + amount)
	if before == 0 and current_hp > 0:
		reset_death_saves()
	return current_hp - before


func reset_death_saves() -> void:
	death_save_successes = 0
	death_save_failures = 0
	stable = false


## Natural 20: regain 1 hp. Natural 1: two failures. 10+: success, else failure.
## Three successes: stable. Three failures: dead.
func roll_death_save(rng: Rng) -> DeathSaveOutcome:
	var out := DeathSaveOutcome.new()
	if dead or current_hp > 0 or stable or not uses_death_saves:
		out.successes = death_save_successes
		out.failures = death_save_failures
		return out
	out.rolled = true
	var d := D20.roll(rng)
	out.natural = d.natural
	if d.natural == 20:
		current_hp = 1
		reset_death_saves()
		out.success = true
		out.regained_consciousness = true
	elif d.natural == 1:
		death_save_failures += 2
	elif d.natural >= 10:
		death_save_successes += 1
		out.success = true
	else:
		death_save_failures += 1
	if death_save_failures >= DEATH_SAVES_NEEDED:
		death_save_failures = DEATH_SAVES_NEEDED
		out.died = true
		_die()
	elif death_save_successes >= DEATH_SAVES_NEEDED:
		death_save_successes = 0
		death_save_failures = 0
		stable = true
		out.became_stable = true
	out.successes = death_save_successes
	out.failures = death_save_failures
	return out


## Adds XP and applies any level-ups (average hit points). Returns levels gained.
func gain_xp(amount: int) -> int:
	if amount <= 0:
		return 0
	xp += amount
	var target := Experience.level_for_xp(xp)
	var gained := 0
	while level < target and level < MAX_LEVEL:
		level_up(null, true)
		gained += 1
	return gained


## Raises level by one. HP gain is the hit die average (hit_die / 2 + 1), or a
## roll when `average` is false and an rng is given, plus CON modifier, min 1.
## Returns the hit points gained.
func level_up(rng: Rng = null, average: bool = true) -> int:
	if level >= MAX_LEVEL:
		return 0
	level += 1
	var base := floori(hit_die / 2.0) + 1
	if not average and rng != null:
		base = rng.next_int(1, hit_die)
	var gain := maxi(1, base + abilities.get_modifier(Ability.Type.CON))
	max_hp += gain
	if is_conscious():
		current_hp += gain
	hit_dice_total = level
	hit_dice_remaining = mini(hit_dice_total, hit_dice_remaining + 1)
	return gain


## SRD unarmed strike: proficiency + STR to hit, 1 + STR bludgeoning damage.
func unarmed_strike() -> Dictionary:
	var str_mod := abilities.get_modifier(Ability.Type.STR)
	return {
		"name": "Unarmed Strike",
		"kind": "melee",
		"to_hit": proficiency_bonus() + str_mod,
		"damage": str(maxi(0, 1 + str_mod)),
		"damage_type": "bludgeoning",
	}


func _die() -> void:
	dead = true
	current_hp = 0
	stable = false


func to_dict() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"name": name,
		"class_id": class_id,
		"level": level,
		"xp": xp,
		"abilities": abilities.to_dict(),
		"max_hp": max_hp,
		"current_hp": current_hp,
		"temp_hp": temp_hp,
		"armor_bonus": armor_bonus,
		"speed": speed,
		"hit_die": hit_die,
		"hit_dice_total": hit_dice_total,
		"hit_dice_remaining": hit_dice_remaining,
		"proficient_saves": DictUtil.ability_keys(proficient_saves),
		"proficient_skills": DictUtil.skill_keys(proficient_skills),
		"death_save_successes": death_save_successes,
		"death_save_failures": death_save_failures,
		"stable": stable,
		"dead": dead,
		"uses_death_saves": uses_death_saves,
		"conditions": conditions.duplicate(),
		"damage_resistances": damage_resistances.duplicate(),
		"damage_immunities": damage_immunities.duplicate(),
		"damage_vulnerabilities": damage_vulnerabilities.duplicate(),
		"deepest_floor": deepest_floor,
	}


static func from_dict(d: Dictionary) -> CharacterSheet:
	var s := CharacterSheet.new()
	s.name = str(d.get("name", ""))
	s.class_id = str(d.get("class_id", ""))
	s.level = clampi(DictUtil.to_int(d.get("level", 1), 1), 1, MAX_LEVEL)
	s.xp = DictUtil.to_int(d.get("xp", 0), 0)
	var ab: Variant = d.get("abilities", {})
	if typeof(ab) == TYPE_DICTIONARY:
		var ab_dict: Dictionary = ab
		s.abilities = AbilityScores.from_dict(ab_dict)
	s.max_hp = maxi(1, DictUtil.to_int(d.get("max_hp", 1), 1))
	s.current_hp = clampi(DictUtil.to_int(d.get("current_hp", s.max_hp), s.max_hp), 0, s.max_hp)
	s.temp_hp = maxi(0, DictUtil.to_int(d.get("temp_hp", 0), 0))
	s.armor_bonus = DictUtil.to_int(d.get("armor_bonus", 0), 0)
	s.speed = DictUtil.to_int(d.get("speed", 30), 30)
	s.hit_die = DictUtil.to_int(d.get("hit_die", 8), 8)
	s.hit_dice_total = DictUtil.to_int(d.get("hit_dice_total", s.level), s.level)
	s.hit_dice_remaining = DictUtil.to_int(d.get("hit_dice_remaining", s.hit_dice_total), s.hit_dice_total)
	for save in DictUtil.to_ability_array(d.get("proficient_saves", [])):
		if save >= 0 and not s.proficient_saves.has(save):
			s.proficient_saves.append(save)
	for skill in DictUtil.to_skill_array(d.get("proficient_skills", [])):
		if skill >= 0 and not s.proficient_skills.has(skill):
			s.proficient_skills.append(skill)
	s.death_save_successes = DictUtil.to_int(d.get("death_save_successes", 0), 0)
	s.death_save_failures = DictUtil.to_int(d.get("death_save_failures", 0), 0)
	s.stable = DictUtil.to_bool(d.get("stable", false), false)
	s.dead = DictUtil.to_bool(d.get("dead", false), false)
	s.uses_death_saves = DictUtil.to_bool(d.get("uses_death_saves", true), true)
	s.conditions = DictUtil.to_string_array(d.get("conditions", []))
	s.damage_resistances = DictUtil.to_string_array(d.get("damage_resistances", []))
	s.damage_immunities = DictUtil.to_string_array(d.get("damage_immunities", []))
	s.damage_vulnerabilities = DictUtil.to_string_array(d.get("damage_vulnerabilities", []))
	s.deepest_floor = DictUtil.to_int(d.get("deepest_floor", 0), 0)
	return s

class_name CharacterBuilder
extends RefCounted
## Builds a level 1 CharacterSheet from a class, an ancestry, ability scores
## and skill picks, and equips the class's starting armor, shield and weapon.

const MAX_STARTING_SCORE := 20
const SHIELD_AC_BONUS := 2


## Level 1 HP = hit die + CON modifier (min 1), with CON after ancestry
## bonuses. Saving throw proficiencies come from the class. Skills must be in
## the class list; extras are dropped with an error. `ancestry` may be null (no
## bonuses, speed 30). `weapon` overrides the class's starting weapon (which
## ContentLoader.load_classes() resolves into cls.starting_weapon_def).
static func create(character_name: String, cls: ClassDefinition, ancestry: AncestryDefinition, scores: AbilityScores, chosen_skills: Array[int], weapon: WeaponDefinition = null) -> CharacterSheet:
	if cls == null:
		push_error("CharacterBuilder.create: class definition is null")
		return null
	var sheet := CharacterSheet.new()
	sheet.name = character_name
	sheet.class_id = cls.id
	sheet.level = 1
	sheet.xp = 0
	sheet.abilities = scores.copy() if scores != null else AbilityScores.new()
	if ancestry != null:
		sheet.ancestry_id = ancestry.id
		sheet.speed = ancestry.speed
		for ability in range(Ability.COUNT):
			var bonus := ancestry.bonus_for(ability)
			if bonus != 0:
				var raised := mini(MAX_STARTING_SCORE, sheet.abilities.get_score(ability) + bonus)
				sheet.abilities.set_score(ability, raised)
	sheet.hit_die = cls.hit_die
	sheet.hit_dice_total = 1
	sheet.hit_dice_remaining = 1
	sheet.max_hp = maxi(1, cls.hit_die + sheet.abilities.get_modifier(Ability.Type.CON))
	sheet.current_hp = sheet.max_hp
	for save in cls.saving_throws:
		sheet.proficient_saves.append(save)
	var picked: Array[int] = []
	for skill in chosen_skills:
		if not cls.skill_choices.has(skill):
			push_error("CharacterBuilder: %s is not a %s skill choice" % [Skill.name_of(skill), cls.display_name])
			continue
		if not picked.has(skill):
			picked.append(skill)
	if picked.size() > cls.skill_choice_count:
		push_error("CharacterBuilder: %s may choose %d skills, got %d; extras dropped" % [cls.display_name, cls.skill_choice_count, picked.size()])
		picked.resize(cls.skill_choice_count)
	sheet.proficient_skills = picked
	sheet.armor_base = cls.starting_armor_base
	sheet.armor_max_dex = cls.starting_armor_max_dex
	sheet.shield_bonus = SHIELD_AC_BONUS if cls.starting_shield else 0
	var wielded := weapon if weapon != null else cls.starting_weapon_def
	if wielded != null:
		sheet.attacks.append(CharacterBuilder.weapon_attack(sheet, wielded, cls.is_proficient_with(wielded)))
	elif not cls.starting_weapon.is_empty():
		push_error("CharacterBuilder: %s starting weapon '%s' is not loaded; unarmed only" % [cls.display_name, cls.starting_weapon])
	return sheet


## Melee weapon attack (one-handed damage): STR, or DEX for a finesse weapon
## when DEX is higher. to_hit = ability modifier + proficiency (if proficient);
## damage = weapon dice + ability modifier, e.g. "1d8+3".
static func weapon_attack(sheet: CharacterSheet, weapon: WeaponDefinition, proficient: bool = true) -> Dictionary:
	var mod := sheet.ability_modifier(Ability.Type.STR)
	if weapon.is_finesse():
		mod = maxi(mod, sheet.ability_modifier(Ability.Type.DEX))
	var damage := weapon.damage
	if mod > 0:
		damage += "+%d" % mod
	elif mod < 0:
		damage += "-%d" % absi(mod)
	return {
		"name": weapon.display_name,
		"kind": "melee",
		"to_hit": mod + (sheet.proficiency_bonus() if proficient else 0),
		"damage": damage,
		"damage_type": weapon.damage_type,
		"weapon_id": weapon.id,
	}

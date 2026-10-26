class_name CharacterBuilder
extends RefCounted
## Builds a level 1 CharacterSheet from a class, ability scores and skill picks.


## Level 1 HP = hit die + CON modifier (min 1). Saving throw proficiencies come
## from the class. Skills must be in the class list; extras are dropped with an error.
static func create(character_name: String, cls: ClassDefinition, scores: AbilityScores, chosen_skills: Array[int]) -> CharacterSheet:
	if cls == null:
		push_error("CharacterBuilder.create: class definition is null")
		return null
	var sheet := CharacterSheet.new()
	sheet.name = character_name
	sheet.class_id = cls.id
	sheet.level = 1
	sheet.xp = 0
	sheet.abilities = scores.copy() if scores != null else AbilityScores.new()
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
	return sheet

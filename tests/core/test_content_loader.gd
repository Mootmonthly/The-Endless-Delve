extends TestCase

var classes: Dictionary
var monsters: Dictionary


func before_each() -> void:
	classes = ContentLoader.load_classes()
	monsters = ContentLoader.load_monsters()


func _cls(class_id: String) -> ClassDefinition:
	var def: ClassDefinition = classes.get(class_id)
	return def


func _mon(monster_id: String) -> MonsterDefinition:
	var def: MonsterDefinition = monsters.get(monster_id)
	return def


func test_loads_four_classes() -> void:
	assert_eq(classes.size(), 4)
	for class_id: String in ["fighter", "rogue", "cleric", "wizard"]:
		assert_has(classes, class_id)


func test_fighter_fields() -> void:
	var f := _cls("fighter")
	assert_eq(f.display_name, "Fighter")
	assert_eq(f.hit_die, 10)
	assert_eq(f.saving_throws, [Ability.Type.STR, Ability.Type.CON])
	assert_eq(f.skill_choice_count, 2)
	assert_eq(f.skill_choices.size(), 8)
	assert_has(f.armor_proficiencies, "heavy")
	assert_eq(f.spellcasting_ability, -1)


func test_rogue_fields() -> void:
	var r := _cls("rogue")
	assert_eq(r.hit_die, 8)
	assert_eq(r.saving_throws, [Ability.Type.DEX, Ability.Type.INT])
	assert_eq(r.skill_choice_count, 4)
	assert_has(r.skill_choices, Skill.Type.STEALTH)
	assert_has(r.tool_proficiencies, "thieves_tools")


func test_spellcasters() -> void:
	assert_eq(_cls("cleric").spellcasting_ability, Ability.Type.WIS)
	assert_eq(_cls("cleric").saving_throws, [Ability.Type.WIS, Ability.Type.CHA])
	assert_eq(_cls("wizard").spellcasting_ability, Ability.Type.INT)
	assert_eq(_cls("wizard").hit_die, 6)
	assert_eq(_cls("wizard").saving_throws, [Ability.Type.INT, Ability.Type.WIS])


func test_loads_four_monsters() -> void:
	assert_eq(monsters.size(), 4)
	for monster_id: String in ["goblin", "skeleton", "giant_rat", "zombie"]:
		assert_has(monsters, monster_id)


func test_goblin_stat_block() -> void:
	var g := _mon("goblin")
	assert_eq(g.armor_class, 15)
	assert_eq(g.hit_points_avg, 7)
	assert_eq(g.hit_dice, "2d6")
	assert_eq(g.abilities.get_score(Ability.Type.DEX), 14)
	assert_eq(g.challenge_rating, 0.25)
	assert_eq(g.xp, 50)
	assert_eq(g.attacks.size(), 2)
	assert_eq(g.attacks[0]["to_hit"], 4)
	assert_eq(g.attacks[0]["damage"], "1d6+2")


func test_other_monsters() -> void:
	assert_eq(_mon("zombie").speed, 20)
	assert_eq(_mon("zombie").hit_points_avg, 22)
	assert_has(_mon("skeleton").damage_vulnerabilities, "bludgeoning")
	assert_eq(_mon("giant_rat").challenge_rating, 0.125)
	assert_eq(_mon("giant_rat").attacks[0]["damage"], "1d4+2")


func test_monster_to_sheet() -> void:
	var g := _mon("goblin")
	var sheet := g.to_sheet(null)
	assert_eq(sheet.armor_class(), 15)
	assert_eq(sheet.max_hp, 7)
	assert_false(sheet.uses_death_saves)
	var rolled := g.to_sheet(Rng.new(3), true)
	assert_in_range(rolled.max_hp, 2, 12)
	assert_eq(_mon("zombie").to_sheet(null).armor_class(), 8)


func test_unknown_strings_map_to_minus_one() -> void:
	assert_eq(Ability.from_string("FOO"), -1)
	assert_eq(Skill.from_string("JUGGLING"), -1)


func test_invalid_input_is_rejected() -> void:
	assert_eq(ContentLoader.load_json("res://data/does_not_exist.json"), {})
	assert_null(ClassDefinition.from_dict({"id": "broken"}))
	assert_null(MonsterDefinition.from_dict({"id": "broken"}))


func test_build_character_from_loaded_class() -> void:
	var skills: Array[int] = [Skill.Type.STEALTH, Skill.Type.ACROBATICS, Skill.Type.DECEPTION, Skill.Type.INSIGHT]
	var sheet := CharacterBuilder.create("Shade", _cls("rogue"), null, AbilityScores.new(), skills)
	assert_eq(sheet.max_hp, 8)
	assert_eq(sheet.proficient_skills.size(), 4)
	assert_eq(sheet.class_id, "rogue")

extends TestCase


func test_proficiency_table() -> void:
	var expected := [2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 6, 6, 6, 6]
	for level in range(1, 21):
		assert_eq(Proficiency.bonus_for_level(level), expected[level - 1], "level %d" % level)


func test_proficiency_clamps_out_of_range() -> void:
	assert_eq(Proficiency.bonus_for_level(0), 2)
	assert_eq(Proficiency.bonus_for_level(25), 6)


func test_xp_for_level() -> void:
	assert_eq(Experience.xp_for_level(1), 0)
	assert_eq(Experience.xp_for_level(2), 300)
	assert_eq(Experience.xp_for_level(5), 6500)
	assert_eq(Experience.xp_for_level(20), 355000)


func test_level_for_xp_boundaries() -> void:
	assert_eq(Experience.level_for_xp(0), 1)
	assert_eq(Experience.level_for_xp(299), 1)
	assert_eq(Experience.level_for_xp(300), 2)
	assert_eq(Experience.level_for_xp(899), 2)
	assert_eq(Experience.level_for_xp(900), 3)
	assert_eq(Experience.level_for_xp(354999), 19)
	assert_eq(Experience.level_for_xp(999999), 20)


func test_thresholds_round_trip() -> void:
	for level in range(1, 21):
		assert_eq(Experience.level_for_xp(Experience.xp_for_level(level)), level)


func test_xp_to_next_level() -> void:
	assert_eq(Experience.xp_to_next_level(100), 200)
	assert_eq(Experience.xp_to_next_level(400000), 0)


func test_skill_abilities() -> void:
	assert_eq(Skill.ability_for(Skill.Type.ATHLETICS), Ability.Type.STR)
	assert_eq(Skill.ability_for(Skill.Type.STEALTH), Ability.Type.DEX)
	assert_eq(Skill.ability_for(Skill.Type.ARCANA), Ability.Type.INT)
	assert_eq(Skill.ability_for(Skill.Type.PERCEPTION), Ability.Type.WIS)
	assert_eq(Skill.ability_for(Skill.Type.PERSUASION), Ability.Type.CHA)


func test_skill_names_and_from_string() -> void:
	assert_eq(Skill.name_of(Skill.Type.SLEIGHT_OF_HAND), "Sleight of Hand")
	assert_eq(Skill.from_string("SLEIGHT_OF_HAND"), Skill.Type.SLEIGHT_OF_HAND)
	assert_eq(Skill.from_string("Animal Handling"), Skill.Type.ANIMAL_HANDLING)
	assert_eq(Skill.KEYS.size(), Skill.COUNT)

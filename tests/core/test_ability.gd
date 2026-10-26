extends TestCase


func test_modifier_table() -> void:
	var table := {1: -5, 2: -4, 3: -4, 8: -1, 9: -1, 10: 0, 11: 0, 12: 1, 15: 2, 20: 5, 30: 10}
	for score: int in table.keys():
		assert_eq(Ability.modifier(score), table[score], "score %d" % score)


func test_names_and_abbreviations() -> void:
	assert_eq(Ability.name_of(Ability.Type.CON), "Constitution")
	assert_eq(Ability.abbreviation(Ability.Type.WIS), "WIS")
	assert_eq(Ability.name_of(99), "Unknown")


func test_from_string() -> void:
	assert_eq(Ability.from_string("DEX"), Ability.Type.DEX)
	assert_eq(Ability.from_string("cha"), Ability.Type.CHA)
	assert_eq(Ability.from_string("Intelligence"), Ability.Type.INT)
	assert_eq(Ability.from_string("LUCK"), -1)


func test_scores_default_to_ten() -> void:
	var a := AbilityScores.new()
	for i in range(Ability.COUNT):
		assert_eq(a.get_score(i), 10)
		assert_eq(a.get_modifier(i), 0)


func test_set_score_clamps() -> void:
	var a := AbilityScores.new()
	a.set_score(Ability.Type.STR, 40)
	assert_eq(a.get_score(Ability.Type.STR), 30)
	a.set_score(Ability.Type.STR, -3)
	assert_eq(a.get_score(Ability.Type.STR), 1)


func test_standard_array() -> void:
	assert_eq(AbilityScores.standard_array(), [15, 14, 13, 12, 10, 8])


func test_point_buy_costs() -> void:
	var expected := [0, 1, 2, 3, 4, 5, 7, 9]
	for i in range(expected.size()):
		assert_eq(AbilityScores.point_buy_cost(8 + i), expected[i], "score %d" % (8 + i))
	assert_eq(AbilityScores.point_buy_cost(7), -1)
	assert_eq(AbilityScores.point_buy_cost(16), -1)


func test_point_buy_total() -> void:
	var spread: Array[int] = [15, 15, 15, 8, 8, 8]
	assert_eq(AbilityScores.point_buy_total(spread), AbilityScores.POINT_BUY_BUDGET)
	var bad: Array[int] = [18, 8, 8, 8, 8, 8]
	assert_eq(AbilityScores.point_buy_total(bad), -1)


func test_roll_scores_is_six_values_in_range() -> void:
	var scores := AbilityScores.roll_scores(Rng.new(10))
	assert_eq(scores.size(), 6)
	for s in scores:
		assert_in_range(s, 3, 18)
	assert_eq(AbilityScores.roll_scores(Rng.new(10)), scores, "deterministic for a seed")


func test_dict_round_trip() -> void:
	var a := AbilityScores.new()
	a.set_all(AbilityScores.standard_array())
	var b := AbilityScores.from_dict(a.to_dict())
	assert_eq(b.scores, a.scores)
	assert_eq(a.to_dict()["STR"], 15)

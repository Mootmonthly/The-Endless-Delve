extends TestCase


func test_parse_plain_d20() -> void:
	var e := DiceExpr.parse("d20")
	assert_true(e.valid, e.error)
	assert_eq(e.count, 1)
	assert_eq(e.sides, 20)
	assert_eq(e.modifier, 0)
	assert_eq(e.keep_highest, 0)


func test_parse_with_modifiers() -> void:
	var plus := DiceExpr.parse("2d6+3")
	assert_true(plus.valid, plus.error)
	assert_eq([plus.count, plus.sides, plus.modifier], [2, 6, 3])
	var minus := DiceExpr.parse("1d8-1")
	assert_true(minus.valid, minus.error)
	assert_eq([minus.count, minus.sides, minus.modifier], [1, 8, -1])


func test_parse_keep_highest() -> void:
	var e := DiceExpr.parse("4d6kh3")
	assert_true(e.valid, e.error)
	assert_eq([e.count, e.sides, e.keep_highest], [4, 6, 3])


func test_parse_constant() -> void:
	var e := DiceExpr.parse("3")
	assert_true(e.valid, e.error)
	assert_true(e.is_constant())
	assert_eq(e.modifier, 3)
	assert_eq(DiceExpr.parse("-1").modifier, -1)


func test_parse_is_case_and_space_insensitive() -> void:
	var e := DiceExpr.parse(" 2D6 + 3 ")
	assert_true(e.valid, e.error)
	assert_eq(str(e), "2d6+3")


func test_parse_invalid_inputs() -> void:
	for bad: String in ["", "abc", "2d", "d0", "0d6", "4d6kh5", "2d6+", "1d6*2", "d", "kh3"]:
		var e := DiceExpr.parse(bad)
		assert_false(e.valid, "'%s' should be invalid" % bad)
		assert_ne(e.error, "", "'%s' should have an error message" % bad)


func test_roll_totals_in_range() -> void:
	var r := Rng.new(3)
	var e := DiceExpr.parse("3d8+2")
	for _i in range(500):
		var roll := e.roll(r)
		assert_in_range(roll.total, e.min_total(), e.max_total())
		assert_eq(roll.rolls.size(), 3)


func test_modifier_applied_to_total() -> void:
	var roll := DiceExpr.parse("2d6-4").roll(Rng.new(8))
	assert_eq(roll.total, roll.rolls[0] + roll.rolls[1] - 4)
	assert_eq(roll.modifier, -4)


func test_keep_highest_keeps_three_largest() -> void:
	var r := Rng.new(17)
	for _i in range(100):
		var roll := DiceExpr.parse("4d6kh3").roll(r)
		assert_eq(roll.rolls.size(), 4)
		assert_eq(roll.kept.size(), 3)
		var sorted: Array[int] = roll.rolls.duplicate()
		sorted.sort()
		assert_eq(roll.total, sorted[1] + sorted[2] + sorted[3])


func test_constant_roll_uses_no_dice() -> void:
	var roll := DiceExpr.parse("5").roll(Rng.new(1))
	assert_eq(roll.total, 5)
	assert_true(roll.rolls.is_empty())


func test_critical_doubles_dice_not_modifier() -> void:
	var roll := DiceExpr.parse("2d6+3").roll(Rng.new(21), true)
	assert_eq(roll.rolls.size(), 4)
	var sum := 0
	for v in roll.rolls:
		sum += v
	assert_eq(roll.total, sum + 3)


func test_breakdown_string() -> void:
	var roll := DiceExpr.parse("2d6+3").roll(Rng.new(4))
	var text := roll.to_string_breakdown()
	assert_true(text.begins_with("2d6+3 ["), text)
	assert_has(text, "+3 = %d" % roll.total)
	var kh := DiceExpr.parse("4d6kh3").roll(Rng.new(4)).to_string_breakdown()
	assert_has(kh, "keep [")

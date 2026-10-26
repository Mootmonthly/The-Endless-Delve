extends TestCase


func test_normal_rolls_one_die() -> void:
	var d := D20.roll(Rng.new(1))
	assert_eq(d.all.size(), 1)
	assert_eq(d.natural, d.all[0])
	assert_eq(d.mode, D20.RollMode.NORMAL)


func test_advantage_keeps_higher() -> void:
	var r := Rng.new(2)
	for _i in range(200):
		var d := D20.roll(r, D20.RollMode.ADVANTAGE)
		assert_eq(d.all.size(), 2)
		assert_eq(d.natural, maxi(d.all[0], d.all[1]))


func test_disadvantage_keeps_lower() -> void:
	var r := Rng.new(3)
	for _i in range(200):
		var d := D20.roll(r, D20.RollMode.DISADVANTAGE)
		assert_eq(d.all.size(), 2)
		assert_eq(d.natural, mini(d.all[0], d.all[1]))


func test_combine_cancels() -> void:
	assert_eq(D20.combine(false, false), D20.RollMode.NORMAL)
	assert_eq(D20.combine(true, false), D20.RollMode.ADVANTAGE)
	assert_eq(D20.combine(false, true), D20.RollMode.DISADVANTAGE)
	assert_eq(D20.combine(true, true), D20.RollMode.NORMAL)


func test_natural_helpers() -> void:
	var s20 := seed_where(func(r: Rng) -> bool: return D20.roll(r).natural == 20)
	assert_true(D20.roll(Rng.new(s20)).is_nat20())
	var s1 := seed_where(func(r: Rng) -> bool: return D20.roll(r).natural == 1)
	var d1 := D20.roll(Rng.new(s1))
	assert_true(d1.is_nat1())
	assert_false(d1.is_nat20())


func test_rolls_stay_in_range() -> void:
	var r := Rng.new(4)
	for _i in range(500):
		assert_in_range(D20.roll(r).natural, 1, 20)

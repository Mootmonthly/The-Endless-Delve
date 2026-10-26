extends TestCase


func _sheet(level: int) -> CharacterSheet:
	var s := CharacterSheet.new()
	s.hit_die = 8
	s.level = level
	s.hit_dice_total = level
	s.hit_dice_remaining = level
	s.max_hp = 40
	s.current_hp = 40
	s.abilities.set_score(Ability.Type.CON, 14)
	return s


func test_short_rest_heals_and_spends_dice() -> void:
	var s := _sheet(4)
	s.current_hp = 5
	var healed := Rest.short_rest(s, 2, Rng.new(1))
	assert_eq(s.hit_dice_remaining, 2)
	assert_in_range(healed, 6, 20)
	assert_eq(s.current_hp, 5 + healed)


func test_short_rest_stops_at_full_hp() -> void:
	var s := _sheet(4)
	s.current_hp = 39
	var healed := Rest.short_rest(s, 4, Rng.new(1))
	assert_eq(healed, 1)
	assert_eq(s.hit_dice_remaining, 3, "only one die needed")
	assert_eq(s.current_hp, 40)


func test_short_rest_without_dice_heals_nothing() -> void:
	var s := _sheet(2)
	s.current_hp = 10
	s.hit_dice_remaining = 0
	assert_eq(Rest.short_rest(s, 2, Rng.new(1)), 0)
	assert_eq(s.current_hp, 10)


func test_long_rest_restores_hp_and_half_dice() -> void:
	var s := _sheet(5)
	s.current_hp = 3
	s.temp_hp = 4
	s.hit_dice_remaining = 0
	Rest.long_rest(s)
	assert_eq(s.current_hp, 40)
	assert_eq(s.temp_hp, 0)
	assert_eq(s.hit_dice_remaining, 2, "half of 5 rounded down")
	var one := _sheet(1)
	one.hit_dice_remaining = 0
	Rest.long_rest(one)
	assert_eq(one.hit_dice_remaining, 1, "minimum of one die")


func test_long_rest_clears_death_saves_and_conditions() -> void:
	var s := _sheet(3)
	s.take_damage(40)
	s.take_damage(1)
	s.conditions.append("poisoned")
	Rest.long_rest(s)
	assert_eq(s.death_save_failures, 0)
	assert_true(s.conditions.is_empty())
	assert_eq(s.current_hp, s.max_hp)


func test_dead_characters_do_not_rest() -> void:
	var s := _sheet(3)
	s.take_damage(100)
	Rest.long_rest(s)
	assert_eq(s.current_hp, 0)
	assert_true(s.is_dead())

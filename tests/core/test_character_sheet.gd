extends TestCase

var fighter: ClassDefinition


func before_each() -> void:
	fighter = ClassDefinition.from_dict({
		"id": "fighter", "display_name": "Fighter", "hit_die": 10,
		"primary_abilities": ["STR"], "saving_throws": ["STR", "CON"],
		"armor_proficiencies": ["light"], "weapon_proficiencies": ["simple"],
		"skill_choices": ["ATHLETICS", "PERCEPTION", "SURVIVAL"], "skill_choice_count": 2,
		"spellcasting_ability": null,
	})


## STR 15, DEX 14, CON 13 (+1), INT 12, WIS 10, CHA 8; Athletics + Perception.
func _hero() -> CharacterSheet:
	var scores := AbilityScores.new()
	scores.set_all(AbilityScores.standard_array())
	var skills: Array[int] = [Skill.Type.ATHLETICS, Skill.Type.PERCEPTION]
	return CharacterBuilder.create("Hero", fighter, null, scores, skills)


## Next three d20s are all 10..19 (successes, no natural 20).
func _three_plain_successes(r: Rng) -> bool:
	for _i in range(3):
		var n := D20.roll(r).natural
		if n < 10 or n == 20:
			return false
	return true


## Next three d20s are all 2..9 (failures, no natural 1).
func _three_plain_failures(r: Rng) -> bool:
	for _i in range(3):
		var n := D20.roll(r).natural
		if n < 2 or n > 9:
			return false
	return true


func _downed() -> CharacterSheet:
	var s := _hero()
	s.take_damage(s.max_hp)
	return s


func test_builder_level_one_hp() -> void:
	var s := _hero()
	assert_eq(s.max_hp, 11, "d10 + CON 1")
	assert_eq(s.current_hp, 11)
	assert_eq(s.hit_dice_total, 1)
	assert_eq(s.hit_die, 10)


func test_builder_hp_minimum_one() -> void:
	var scores := AbilityScores.new()
	scores.set_score(Ability.Type.CON, 1)
	var empty: Array[int] = []
	var weak := fighter
	weak.hit_die = 6
	assert_eq(CharacterBuilder.create("Frail", weak, null, scores, empty).max_hp, 1)


func test_builder_saves_and_skills() -> void:
	var s := _hero()
	assert_eq(s.save_modifier(Ability.Type.STR), 4, "STR +2, prof +2")
	assert_eq(s.save_modifier(Ability.Type.DEX), 2, "not proficient")
	assert_eq(s.skill_modifier(Skill.Type.ATHLETICS), 4)
	assert_eq(s.skill_modifier(Skill.Type.STEALTH), 2)
	assert_eq(s.proficiency_bonus(), 2)


func test_builder_rejects_invalid_and_extra_skills() -> void:
	var skills: Array[int] = [Skill.Type.ARCANA, Skill.Type.ATHLETICS, Skill.Type.PERCEPTION, Skill.Type.SURVIVAL]
	var s := CharacterBuilder.create("Greedy", fighter, null, AbilityScores.new(), skills)
	assert_eq(s.proficient_skills, [Skill.Type.ATHLETICS, Skill.Type.PERCEPTION])


func test_armor_class_and_initiative() -> void:
	var s := _hero()
	assert_eq(s.armor_class(), 12, "10 + DEX 2")
	s.shield_bonus = 2
	assert_eq(s.armor_class(), 14, "shield")
	s.armor_base = 14
	s.armor_max_dex = 1
	assert_eq(s.armor_class(), 17, "scale mail caps DEX at +1 here, plus shield")
	s.armor_max_dex = 0
	s.shield_bonus = 0
	s.abilities.set_score(Ability.Type.DEX, 6)
	assert_eq(s.armor_class(), 14, "heavy armor ignores a DEX penalty")
	assert_eq(s.initiative_modifier(), -2)


func test_temp_hp_absorbs_first() -> void:
	var s := _hero()
	s.grant_temp_hp(5)
	var out := s.take_damage(7)
	assert_eq(out.absorbed_by_temp, 5)
	assert_eq(s.temp_hp, 0)
	assert_eq(s.current_hp, 9)


func test_dropping_to_zero_is_unconscious() -> void:
	var s := _hero()
	var out := s.take_damage(15)
	assert_true(out.dropped_to_zero)
	assert_false(out.died)
	assert_eq(s.current_hp, 0)
	assert_true(s.is_unconscious())
	assert_true(s.is_alive())


func test_massive_damage_instant_death() -> void:
	var s := _hero()
	var out := s.take_damage(22)
	assert_true(out.instant_death, "11 left over >= 11 max hp")
	assert_true(s.is_dead())
	assert_false(s.is_unconscious())


func test_damage_at_zero_adds_failures() -> void:
	var s := _downed()
	assert_eq(s.take_damage(1).death_save_failures_added, 1)
	assert_eq(s.death_save_failures, 1)
	s.take_damage(1, true)
	assert_eq(s.death_save_failures, 3)
	assert_true(s.is_dead(), "crit at 0 hp adds two failures")


func test_big_hit_at_zero_is_instant_death() -> void:
	var s := _downed()
	assert_true(s.take_damage(11).instant_death)
	assert_true(s.is_dead())


func test_death_save_nat20_regains_one_hp() -> void:
	var s := _downed()
	var found := seed_where(func(r: Rng) -> bool: return D20.roll(r).natural == 20)
	var out := s.roll_death_save(Rng.new(found))
	assert_true(out.regained_consciousness)
	assert_eq(s.current_hp, 1)
	assert_eq(s.death_save_failures, 0)


func test_death_save_nat1_is_two_failures() -> void:
	var s := _downed()
	var found := seed_where(func(r: Rng) -> bool: return D20.roll(r).natural == 1)
	s.roll_death_save(Rng.new(found))
	assert_eq(s.death_save_failures, 2)


func test_three_successes_stabilize() -> void:
	var s := _downed()
	var rng := Rng.new(seed_where(_three_plain_successes))
	s.roll_death_save(rng)
	s.roll_death_save(rng)
	var out := s.roll_death_save(rng)
	assert_true(out.became_stable)
	assert_true(s.stable)
	assert_eq(s.death_save_successes, 0)
	assert_false(s.roll_death_save(rng).rolled, "stable creatures stop rolling")


func test_three_failures_kill() -> void:
	var s := _downed()
	var rng := Rng.new(seed_where(_three_plain_failures))
	s.roll_death_save(rng)
	s.roll_death_save(rng)
	var out := s.roll_death_save(rng)
	assert_true(out.died)
	assert_true(s.is_dead())


func test_heal_resets_death_saves_and_caps() -> void:
	var s := _downed()
	s.take_damage(1)
	assert_eq(s.heal(4), 4)
	assert_eq(s.death_save_failures, 0)
	assert_eq(s.heal(100), s.max_hp - 4)
	assert_eq(s.current_hp, s.max_hp)


func test_dead_cannot_be_healed() -> void:
	var s := _hero()
	s.take_damage(100)
	assert_eq(s.heal(5), 0)
	assert_eq(s.current_hp, 0)


func test_gain_xp_levels_up() -> void:
	var s := _hero()
	assert_eq(s.gain_xp(299), 0)
	assert_eq(s.gain_xp(700), 2, "999 xp is level 3: two levels pending")
	assert_eq(s.level, 1, "gain_xp no longer applies levels (LevelUp does)")
	assert_eq(s.pending_levels(), 2)
	s.level_up()
	s.level_up()
	assert_eq(s.pending_levels(), 0)
	assert_eq(s.level, 3)
	assert_eq(s.max_hp, 11 + 2 * (6 + 1), "average d10 (6) + CON 1 per level")
	assert_eq(s.hit_dice_total, 3)
	assert_eq(s.proficiency_bonus(), 2)


func test_level_up_rolled_hp_minimum_one() -> void:
	var s := _hero()
	s.abilities.set_score(Ability.Type.CON, 1)
	var gain := s.level_up(Rng.new(1), false)
	assert_true(gain >= 1)
	assert_eq(s.level, 2)


func test_to_dict_round_trip() -> void:
	var s := _hero()
	s.xp = 450
	s.temp_hp = 3
	s.conditions.append("poisoned")
	s.deepest_floor = 7
	s.damage_resistances.append("fire")
	var copy := CharacterSheet.from_dict(s.to_dict())
	assert_eq(copy.to_dict(), s.to_dict())
	assert_eq(copy.proficient_skills, s.proficient_skills)
	assert_eq(copy.abilities.scores, s.abilities.scores)


func test_from_dict_accepts_json_floats() -> void:
	var data: Dictionary = JSON.parse_string(JSON.stringify(_hero().to_dict()))
	var copy := CharacterSheet.from_dict(data)
	assert_eq(copy.max_hp, 11)
	assert_eq(copy.proficient_saves, [Ability.Type.STR, Ability.Type.CON])


func test_damage_type_adjustments() -> void:
	var s := _hero()
	s.damage_immunities.append("poison")
	s.damage_resistances.append("fire")
	s.damage_vulnerabilities.append("cold")
	assert_eq(s.adjust_damage_for_type(9, "poison"), 0)
	assert_eq(s.adjust_damage_for_type(9, "fire"), 4)
	assert_eq(s.adjust_damage_for_type(9, "cold"), 18)
	assert_eq(s.adjust_damage_for_type(9, "slashing"), 9)

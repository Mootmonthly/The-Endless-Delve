extends TestCase
## LevelUpDraft: the level-up screen's rules against real LevelUp offers.


func _sheet(class_id: String, level: int = 1) -> CharacterSheet:
	var d := CharacterDraft.new()
	d.character_name = "Lev"
	d.set_class(ContentLoader.load_classes()[class_id])
	d.auto_assign()
	var s := d.build_sheet()
	s.xp = Experience.xp_for_level(level + 1)
	return s


func _level_to(s: CharacterSheet, level: int) -> void:
	while s.level < level:
		s.xp = maxi(s.xp, Experience.xp_for_level(s.level + 1))
		var d := LevelUpDraft.first_valid(LevelUp.choices(s), s)
		assert_eq(LevelUp.apply(s, d.to_choices(), {}, null), "", "level %d" % (s.level + 1))


func test_first_valid_is_accepted_for_every_class_up_to_level_5() -> void:
	for id: String in CharacterDraft.CLASS_ORDER:
		var s := _sheet(id)
		_level_to(s, 5)
		assert_eq(s.level, 5, id)


func test_asi_rules_and_preview() -> void:
	var s := _sheet("fighter")
	_level_to(s, 3)
	s.xp = Experience.xp_for_level(4)
	var d := LevelUpDraft.new(LevelUp.choices(s), s)
	assert_true(d.asi_offered(), "level 4 has an ASI")
	assert_false(d.is_valid(), "the ASI must be chosen")
	d.set_asi_plus_two(Ability.Type.CON)
	assert_true(d.is_valid(), str(d.problems()))
	assert_eq(d.preview_scores()[Ability.Type.CON], s.abilities.get_score(Ability.Type.CON) + 2)
	d.set_asi_split(Ability.Type.STR, Ability.Type.STR)
	assert_false(d.is_valid(), "two different abilities")
	d.set_asi_split(Ability.Type.STR, Ability.Type.DEX)
	assert_eq(d.to_choices()["asi"], {"STR": 1, "DEX": 1})
	s.abilities.set_score(Ability.Type.WIS, 20)
	assert_false(d.can_raise(Ability.Type.WIS))
	d.set_asi_plus_two(Ability.Type.WIS)
	assert_false(d.is_valid(), "a score at 20 cannot be picked")
	s.abilities.set_score(Ability.Type.INT, 19)
	d.set_asi_plus_two(Ability.Type.INT)
	assert_eq(d.preview_scores()[Ability.Type.INT], 20, "capped at 20")


func test_learning_counts_and_unsupported_spells() -> void:
	var s := _sheet("wizard")
	var d := LevelUpDraft.new(LevelUp.choices(s), s)
	assert_true(d.spells_needed() > 0, "a wizard adds spells to the spellbook")
	assert_false(d.is_valid())
	var unsupported := ""
	var supported: Array[String] = []
	for id in d.spell_options():
		if d.is_supported(id):
			supported.append(id)
		elif unsupported.is_empty():
			unsupported = id
	if not unsupported.is_empty() and supported.size() >= d.spells_needed():
		assert_false(d.toggle_learn(unsupported, true), "greyed out")
	for id in supported:
		d.toggle_learn(id, true)
	for id in d.spell_options():
		if d.may_pick(id, false):
			d.toggle_learn(id, true)  # greyed ones only when the castable ones run out
	if not unsupported.is_empty() and supported.size() >= d.spells_needed():
		assert_false(d.learn_spells.has(unsupported))
	assert_eq(d.learn_spells.size(), d.spells_needed(), "the count caps the picks")
	assert_true(d.is_valid(), str(d.problems()))
	assert_true(d.toggle_learn(d.learn_spells[0], false))
	assert_false(d.is_valid())


func test_hp_choice_and_prepared_caster() -> void:
	var s := _sheet("cleric")
	var d := LevelUpDraft.new(LevelUp.choices(s), s)
	assert_eq(d.to_choices()["hp"], "average")
	d.set_hp_mode(LevelUpDraft.HP_ROLL)
	assert_eq(d.to_choices()["hp"], "roll")
	assert_true(d.is_prepared_caster())
	assert_true(d.prepared.size() <= d.prepared_count())
	for id in d.prepare_options():
		d.toggle_prepared(id, true)
	assert_eq(d.prepared.size(), mini(d.prepare_options().size(), d.prepared_count()), "never more than the count")
	assert_true(d.is_valid(), str(d.problems()))
	var rng := Rng.new(5)
	assert_eq(LevelUp.apply(s, d.to_choices(), {}, rng), "")
	assert_eq(s.level, 2)

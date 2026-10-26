extends TestCase
## The interactive level-up flow: gain_xp banks XP, LevelUp.choices() lists
## the options, LevelUp.apply() validates and applies them.

var content: Dictionary


func _class(d: Dictionary) -> ClassDefinition:
	var base := {
		"schema_version": 1, "display_name": str(d["id"]).capitalize(), "hit_die": 10,
		"primary_abilities": ["STR"], "saving_throws": ["STR", "CON"],
		"armor_proficiencies": [], "weapon_proficiencies": ["simple", "martial"],
		"skill_choices": ["ATHLETICS", "PERCEPTION"], "skill_choice_count": 1,
		"spellcasting_ability": null,
	}
	base.merge(d, true)
	var cls := ClassDefinition.from_dict(base)
	assert_not_null(cls, str(d["id"]))
	return cls


func before_each() -> void:
	content = CoreFixtures.content()
	var classes := {}
	for cls: ClassDefinition in [
		_class({"id": "fighter", "features": ["second_wind"], "features_by_level": {"1": ["second_wind"], "2": ["action_surge"], "3": ["martial_archetype"]}}),
		_class({"id": "wizard", "hit_die": 6, "spellcasting_ability": "INT",
			"spellcasting": {"ability": "INT", "prepared": ["fire_bolt", "ray_of_frost", "magic_missile", "mage_armor"],
				"slots": {"1": [2], "2": [3], "3": [4, 2], "4": [4, 3]}},
			"spell_list": ["fire_bolt", "ray_of_frost", "shocking_grasp", "magic_missile", "mage_armor", "burning_hands", "thunder_save", "scorching_ray", "acid_arrow"],
			"cantrips_known": {"1": 2, "4": 3}, "prepares": true, "spellbook_learn_per_level": 2}),
		_class({"id": "cleric", "hit_die": 8, "spellcasting_ability": "WIS",
			"spellcasting": {"ability": "WIS", "prepared": ["sacred_flame", "cure_wounds"], "slots": {"1": [2], "2": [3], "3": [4, 2]}},
			"spell_list": ["sacred_flame", "cure_wounds", "healing_word", "guiding_bolt", "scorching_ray"],
			"cantrips_known": {"1": 1}, "prepares": true}),
		_class({"id": "sorcerer", "hit_die": 6, "spellcasting_ability": "CHA",
			"spellcasting": {"ability": "CHA", "prepared": ["fire_bolt", "magic_missile"], "slots": {"1": [2], "2": [3], "3": [4, 2]}},
			"spell_list": ["fire_bolt", "ray_of_frost", "shocking_grasp", "magic_missile", "mage_armor", "scorching_ray"],
			"cantrips_known": {"1": 1, "2": 2}, "spells_known": {"1": 1, "2": 2, "3": 3}}),
		_class({"id": "paladin", "features": ["lay_on_hands"], "features_by_level": {"2": ["second_wind"]}}),
	]:
		classes[cls.id] = cls
	content["classes"] = classes


func _build(class_id: String, scores: Array[int]) -> CharacterSheet:
	var ab := AbilityScores.new()
	ab.set_all(scores)
	var none: Array[int] = []
	var cls: ClassDefinition = content["classes"][class_id]
	return CharacterBuilder.create(class_id, cls, null, ab, none, null, content)


func test_gain_xp_only_banks_xp() -> void:
	var s := _build("fighter", [16, 12, 14, 10, 10, 10])
	assert_eq(s.gain_xp(250), 0)
	assert_eq(s.gain_xp(50), 1)
	assert_eq(s.level, 1)
	assert_eq(s.pending_levels(), 1)
	assert_eq(s.gain_xp(0), 1, "no XP: still one pending")


func test_fighter_level_two_with_average_hp() -> void:
	var s := _build("fighter", [16, 12, 14, 10, 10, 10])
	assert_eq(s.max_hp, 12)
	s.gain_xp(300)
	var ch := LevelUp.choices(s, content)
	assert_eq(ch["new_level"], 2)
	assert_eq(ch["levels_pending"], 1)
	assert_eq(ch["hp"], {"average": 8, "may_roll": true, "die": 10, "con_mod": 2, "bonus": 0})
	assert_eq(ch["asi"], false)
	assert_eq(ch["new_spell_slots"], [])
	assert_eq(ch["cantrips_to_learn"], 0)
	assert_eq(ch["spells_to_learn"], 0)
	assert_eq(ch["spell_options"], [])
	assert_eq(ch["prepared_count"], 0)
	assert_eq(ch["features_gained"], ["action_surge"])
	assert_eq(ch["skills_to_choose"], 0)
	assert_eq(LevelUp.apply(s, {"hp": "average"}, content, null), "")
	assert_eq(s.level, 2)
	assert_eq(s.max_hp, 20)
	assert_eq(s.current_hp, 20)
	assert_eq(s.hit_dice_total, 2)
	assert_has(s.features, "action_surge")
	assert_eq(s.pending_levels(), 0)
	assert_ne(LevelUp.apply(s, {"hp": "average"}, content, null), "", "no XP for level 3")


func test_rolled_hp_needs_an_rng_and_valid_mode() -> void:
	var s := _build("fighter", [16, 12, 14, 10, 10, 10])
	s.gain_xp(300)
	assert_ne(LevelUp.apply(s, {"hp": "roll"}, content, null), "")
	assert_ne(LevelUp.apply(s, {"hp": "max"}, content, Rng.new(1)), "")
	assert_eq(s.level, 1, "rejected choices change nothing")
	assert_eq(LevelUp.apply(s, {"hp": "roll"}, content, Rng.new(7)), "")
	assert_in_range(s.max_hp, 12 + 3, 12 + 12)


func test_wizard_learns_two_spells_and_gains_a_slot() -> void:
	var s := _build("wizard", [8, 14, 12, 16, 12, 10])
	assert_eq(s.spell_slots, [2])
	assert_eq(s.spells_known, ["fire_bolt", "ray_of_frost", "magic_missile", "mage_armor"])
	s.gain_xp(300)
	var ch := LevelUp.choices(s, content)
	assert_eq(ch["new_spell_slots"], [3])
	assert_eq(ch["spells_to_learn"], 2)
	assert_eq(ch["cantrips_to_learn"], 0)
	assert_eq(ch["spell_options"], ["shocking_grasp", "burning_hands", "thunder_save"], "not known yet, level <= 1, class list order")
	assert_eq(ch["prepared_count"], 5, "INT 3 + level 2")
	assert_eq(ch["prepare_options"], ["magic_missile", "mage_armor"])
	assert_ne(LevelUp.apply(s, {"learn_spells": ["thunder_save"]}, content, null), "", "too few")
	assert_ne(LevelUp.apply(s, {"learn_spells": ["thunder_save", "scorching_ray"]}, content, null), "", "level 2 not yet castable")
	assert_ne(LevelUp.apply(s, {"learn_spells": ["thunder_save", "shocking_grasp"]}, content, null), "", "a cantrip is not a spell")
	assert_ne(LevelUp.apply(s, {"learn_spells": ["thunder_save", "thunder_save"]}, content, null), "", "duplicate")
	assert_eq(s.level, 1)
	var err := LevelUp.apply(s, {"learn_spells": ["thunder_save", "burning_hands"], "prepared": ["magic_missile", "thunder_save"]}, content, null)
	assert_eq(err, "")
	assert_eq(s.level, 2)
	assert_eq(s.spell_slots_max, [3])
	assert_eq(s.spell_slots, [3])
	assert_has(s.spells_known, "thunder_save")
	assert_has(s.spells_known, "burning_hands")
	assert_eq(s.spells_prepared, ["fire_bolt", "ray_of_frost", "magic_missile", "thunder_save"], "cantrips stay, leveled as chosen")


func test_prepared_list_is_limited() -> void:
	var s := _build("wizard", [8, 14, 12, 12, 12, 10])
	s.gain_xp(300)
	assert_eq(LevelUp.choices(s, content)["prepared_count"], 3, "INT 1 + level 2")
	var err := LevelUp.apply(s, {"learn_spells": ["thunder_save", "burning_hands"], "prepared": ["magic_missile", "mage_armor", "thunder_save", "burning_hands"]}, content, null)
	assert_true(err.contains("at most 3"), err)
	err = LevelUp.apply(s, {"learn_spells": ["thunder_save", "burning_hands"], "prepared": ["guiding_bolt"]}, content, null)
	assert_true(err.contains("cannot be prepared"), err)


func test_cleric_prepared_count_is_wis_mod_plus_level() -> void:
	var s := _build("cleric", [10, 10, 14, 10, 16, 10])
	s.gain_xp(300)
	var ch := LevelUp.choices(s, content)
	assert_eq(ch["prepared_count"], 5, "WIS 3 + level 2")
	assert_eq(ch["spells_to_learn"], 0, "clerics prepare from the whole list")
	assert_eq(ch["prepare_options"], ["cure_wounds", "healing_word", "guiding_bolt"])
	assert_eq(LevelUp.apply(s, {"prepared": ["healing_word", "guiding_bolt"]}, content, null), "")
	assert_eq(s.spells_prepared, ["sacred_flame", "healing_word", "guiding_bolt"])
	assert_eq(s.spell_slots, [3])


func test_known_caster_learns_cantrips_and_spells() -> void:
	var s := _build("sorcerer", [8, 14, 12, 10, 10, 16])
	s.gain_xp(300)
	var ch := LevelUp.choices(s, content)
	assert_eq(ch["cantrips_to_learn"], 1)
	assert_eq(ch["spells_to_learn"], 1)
	assert_eq(ch["prepared_count"], 0)
	assert_ne(LevelUp.apply(s, {"learn_spells": ["mage_armor"]}, content, null), "", "cantrip missing")
	assert_eq(LevelUp.apply(s, {"learn_cantrips": ["ray_of_frost"], "learn_spells": ["mage_armor"]}, content, null), "")
	assert_has(s.spells_prepared, "ray_of_frost")
	assert_has(s.spells_prepared, "mage_armor")
	assert_ne(LevelUp.apply(s, {}, content, null), "", "no more XP")


func test_ability_score_improvement_at_level_four() -> void:
	var s := _build("fighter", [19, 12, 14, 10, 10, 10])
	s.add_item("longsword")
	s.equip("longsword", "main_hand", content)
	s.gain_xp(2700)
	assert_eq(s.pending_levels(), 3)
	assert_eq(LevelUp.apply(s, {}, content, null), "")
	assert_eq(LevelUp.apply(s, {}, content, null), "")
	assert_eq(s.level, 3)
	var ch := LevelUp.choices(s, content)
	assert_eq(ch["asi"], true)
	assert_ne(LevelUp.apply(s, {}, content, null), "", "an ASI must be chosen")
	assert_ne(LevelUp.apply(s, {"asi": {"STR": 1}}, content, null), "", "+1 alone")
	assert_ne(LevelUp.apply(s, {"asi": {"STR": 1, "DEX": 1, "CON": 1}}, content, null), "", "three abilities")
	assert_ne(LevelUp.apply(s, {"asi": {"LUCK": 2}}, content, null), "", "unknown ability")
	assert_ne(LevelUp.apply(s, {"asi": {"STR": 3}}, content, null), "", "+3")
	assert_eq(s.level, 3)
	assert_eq(LevelUp.apply(s, {"asi": {"STR": 2}}, content, null), "")
	assert_eq(s.level, 4)
	assert_eq(s.abilities.get_score(Ability.Type.STR), 20, "19 + 2 capped at 20")
	assert_eq(s.attacks[0]["damage"], "1d8+5", "attacks follow the new STR")
	var at20 := _build("fighter", [20, 12, 14, 10, 10, 10])
	at20.gain_xp(2700)
	LevelUp.apply(at20, {}, content, null)
	LevelUp.apply(at20, {}, content, null)
	assert_ne(LevelUp.apply(at20, {"asi": {"STR": 2}}, content, null), "", "already 20")
	assert_ne(LevelUp.apply(s, {"asi": {"DEX": 2}}, content, null), "", "no ASI at level 5 (and no XP)")


func test_con_increase_raises_hp_retroactively() -> void:
	var s := _build("fighter", [16, 12, 15, 10, 10, 10])
	s.gain_xp(2700)
	for _i in range(3):
		var ch := LevelUp.choices(s, content)
		var made := {"asi": {"CON": 1, "STR": 1}} if ch["asi"] else {}
		assert_eq(LevelUp.apply(s, made, content, null), "")
	assert_eq(s.level, 4)
	# L1 10 + 2, L2-3 6 + 2 each, CON 16 at L4: +1 for levels 1-3, L4 6 + 3.
	assert_eq(s.max_hp, 12 + 8 + 8 + 3 + 9)


func test_new_resource_features_start_full() -> void:
	var s := _build("paladin", [16, 10, 14, 10, 10, 14])
	assert_eq(s.class_resource("lay_on_hands"), 5)
	s.spend_class_resource("lay_on_hands", 4)
	s.gain_xp(300)
	assert_eq(LevelUp.apply(s, {}, content, null), "")
	assert_eq(s.class_resource("lay_on_hands"), 6, "pool max grows by 5")
	assert_eq(s.class_resource("second_wind"), 1, "gained at level 2, ready")


func test_real_classes_offer_choices() -> void:
	var c := ContentLoader.cache()
	var classes: Dictionary = c["classes"]
	if not classes.has("wizard"):
		return
	var wiz: ClassDefinition = classes["wizard"]
	var ab := AbilityScores.new()
	ab.set_all([8, 14, 12, 16, 12, 10])
	var none: Array[int] = []
	var s := CharacterBuilder.create("W", wiz, null, ab, none, null, c)
	s.gain_xp(300)
	var ch := LevelUp.choices(s, c)
	assert_eq(ch["new_level"], 2)
	assert_eq(ch["new_spell_slots"], [3])
	assert_eq(ch["prepared_count"], 5)
	var options: Array = ch["spell_options"]
	var learn: Array = options.filter(func(id: Variant) -> bool:
		var sp: SpellDefinition = c["spells"][id]
		return sp.level >= 1)
	learn = learn.slice(0, DictUtil.to_int(ch["spells_to_learn"]))
	assert_eq(LevelUp.apply(s, {"learn_spells": learn}, c, null), "")
	assert_eq(s.spell_slots, [3])

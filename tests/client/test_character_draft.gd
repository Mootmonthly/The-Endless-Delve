extends TestCase
## CharacterDraft: the creator's rules (score methods: standard array, point
## buy, roll; skills, preview).

var _classes: Dictionary = {}
var _ancestries: Dictionary = {}


func before_each() -> void:
	if _classes.is_empty():
		_classes = ContentLoader.load_classes()
		_ancestries = ContentLoader.load_ancestries()


func _fighter_draft() -> CharacterDraft:
	var d := CharacterDraft.new()
	d.character_name = "Brann"
	d.set_class(_classes["fighter"])
	d.set_ancestry(_ancestries["human"])
	return d


func test_all_twelve_classes_in_menu_order() -> void:
	var ids: Array[String] = []
	for def in CharacterDraft.ordered_classes(_classes):
		ids.append(def.id)
	assert_eq(ids, CharacterDraft.CLASS_ORDER, "every SRD class, fighter first")
	assert_eq(ids.size(), 12)
	assert_eq(CharacterDraft.sorted_ancestries(_ancestries).size(), _ancestries.size())


func test_every_class_builds_a_valid_preview() -> void:
	for def in CharacterDraft.ordered_classes(_classes):
		var d := CharacterDraft.new()
		d.character_name = "Tester"
		d.set_class(def)
		d.set_ancestry(_ancestries["human"])
		d.auto_assign()
		for skill in def.skill_choices:
			d.toggle_skill(skill, true)
		d.auto_choose()  # level-1 choices (fighting style, expertise, dragon ancestor)
		assert_true(d.is_valid(), "%s: %s" % [def.id, str(d.problems())])
		var p := d.preview()
		assert_true(int(p["hp"]) > 0, def.id)
		assert_true((p["attacks"] as Array).size() >= 1, "%s has an attack" % def.id)
		assert_true((p["kit"] as Array).size() >= 1, "%s carries a kit" % def.id)
		assert_eq(int(p["gold"]), 10, "%s starts with 10 gold" % def.id)


func test_preview_shows_armor_ranges_spells_and_slots() -> void:
	var d := _fighter_draft()
	d.auto_assign()
	var p := d.preview()
	assert_has(str(p["armor"]), "Chain Mail")
	var wiz := CharacterDraft.new()
	wiz.character_name = "Ilsa"
	wiz.set_class(_classes["wizard"])
	wiz.set_ancestry(_ancestries["human"])
	wiz.auto_assign()
	var wp := wiz.preview()
	assert_false((wp["spells"] as Array).is_empty(), "a wizard has prepared spells")
	assert_has(str(wp["slots"]), "level 1")
	var ranger := CharacterDraft.new()
	ranger.set_class(_classes["ranger"])
	ranger.auto_assign()
	var ranged := false
	for a: String in ranger.preview()["attacks"]:
		if a.contains("ranged") and a.contains(" ft"):
			ranged = true
	assert_true(ranged, "the ranger preview lists a ranged attack with its range")


func test_assign_swaps_to_keep_values_unique() -> void:
	var d := _fighter_draft()
	d.assign(Ability.Type.STR, 15)
	d.assign(Ability.Type.DEX, 14)
	assert_eq(d.assigned[Ability.Type.STR], 15)
	d.assign(Ability.Type.DEX, 15)
	assert_eq(d.assigned[Ability.Type.DEX], 15)
	assert_eq(d.assigned[Ability.Type.STR], 14, "STR took DEX's old value")
	d.assign(Ability.Type.CON, 14)
	assert_eq(d.assigned[Ability.Type.STR], CharacterDraft.UNASSIGNED, "STR lost 14 to CON")
	d.assign(Ability.Type.WIS, 11)
	assert_eq(d.assigned[Ability.Type.WIS], CharacterDraft.UNASSIGNED, "11 is not in the standard array")


func test_auto_assign_uses_primary_abilities_first() -> void:
	var d := _fighter_draft()
	d.auto_assign()
	assert_true(d.is_fully_assigned())
	assert_eq(d.assigned[Ability.Type.STR], 15)
	assert_eq(d.assigned[Ability.Type.DEX], 14)
	assert_eq(d.assigned[Ability.Type.CON], 13)
	var sorted := d.assigned.duplicate()
	sorted.sort()
	assert_eq(sorted, [8, 10, 12, 13, 14, 15])


func test_skills_are_limited_to_class_choices_and_count() -> void:
	var d := _fighter_draft()
	assert_eq(d.skills_needed(), 2)
	assert_false(d.toggle_skill(Skill.Type.ARCANA, true), "not a fighter skill")
	assert_true(d.toggle_skill(Skill.Type.ATHLETICS, true))
	assert_true(d.toggle_skill(Skill.Type.PERCEPTION, true))
	assert_false(d.toggle_skill(Skill.Type.SURVIVAL, true), "only two")
	assert_true(d.toggle_skill(Skill.Type.PERCEPTION, false))
	assert_eq(d.skills, [Skill.Type.ATHLETICS] as Array[int])
	d.set_class(_classes["wizard"])
	assert_eq(d.skills.size(), 0, "athletics is not a wizard skill")


func test_validity_and_build() -> void:
	var d := _fighter_draft()
	d.character_name = "  "
	assert_false(d.is_valid())
	assert_eq(d.problems().size(), 4, "name, scores, skills, fighting style")
	d.character_name = "Brann"
	d.auto_assign()
	d.toggle_skill(Skill.Type.ATHLETICS, true)
	assert_false(d.is_valid())
	d.toggle_skill(Skill.Type.INTIMIDATION, true)
	assert_false(d.is_valid(), "the fighting style is still open")
	var style: Dictionary = d.creation_choices()[0]
	assert_true(d.toggle_creation_choice(style, "defense", true))
	assert_true(d.is_valid(), str(d.problems()))
	var sheet := d.build_sheet()
	assert_not_null(sheet)
	assert_eq(sheet.name, "Brann")
	assert_eq(sheet.class_id, "fighter")
	assert_eq(sheet.ancestry_id, "human")
	assert_eq(sheet.abilities.get_score(Ability.Type.STR), 16, "15 + human bonus")
	assert_eq(sheet.proficient_skills.size(), 2)
	assert_eq(sheet.fighting_styles, ["defense"] as Array[String], "the picked style is sent explicitly")


func test_preview_matches_the_srd_fighter() -> void:
	var d := _fighter_draft()
	d.auto_assign()
	var p := d.preview()
	assert_eq(p["ac"], 16)
	assert_eq(p["to_hit"], 5)
	assert_eq(p["damage"], "1d8+3")
	assert_eq(p["attack_name"], "Longsword")
	assert_eq(p["hp"], 12, "d10 + CON 14 (+2)")
	assert_eq(p["speed"], 30)
	assert_eq(p["scores"], [16, 15, 14, 11, 13, 9])


func test_creator_score_menu_mapping() -> void:
	assert_eq(CharacterCreator.score_for_index(0), CharacterDraft.UNASSIGNED)
	assert_eq(CharacterCreator.score_for_index(1), 15)
	assert_eq(CharacterCreator.score_for_index(6), 8)
	assert_eq(CharacterCreator.index_for_score(15), 1)
	assert_eq(CharacterCreator.index_for_score(8), 6)
	assert_eq(CharacterCreator.index_for_score(CharacterDraft.UNASSIGNED), 0)


func test_creation_choices_for_level_one_subclasses_and_expertise() -> void:
	var sorc := CharacterDraft.new()
	sorc.character_name = "Vex"
	sorc.set_class(_classes["sorcerer"])
	sorc.set_ancestry(_ancestries["human"])
	sorc.auto_assign()
	for skill in _classes["sorcerer"].skill_choices:
		sorc.toggle_skill(skill, true)
	var info := sorc.subclass_info()
	assert_eq(str(info.get("id", "")), "draconic", "sorcerers start with their origin")
	assert_ne(str(info.get("description", "")), "")
	var entries := sorc.creation_choices()
	assert_eq(entries.size(), 1)
	assert_eq(str(entries[0]["feature"]), "dragon_ancestor")
	var labels := sorc.creation_draft()
	assert_eq(labels.option_label(entries[0], "dragon_ancestor_red"), "Red")
	assert_true(sorc.toggle_creation_choice(entries[0], "dragon_ancestor_red", true))
	assert_true(sorc.toggle_creation_choice(entries[0], "dragon_ancestor_blue", true), "a single pick swaps")
	assert_true(sorc.is_valid(), str(sorc.problems()))
	var sheet := sorc.build_sheet()
	assert_eq(sheet.subclass_id, "draconic")
	assert_true(sheet.has_feature("dragon_ancestor_blue"))
	assert_false(sheet.has_feature("dragon_ancestor_black"), "not the default")
	# Rogue expertise comes from the chosen skills; changing skills drops stale picks.
	var rogue := CharacterDraft.new()
	rogue.character_name = "Nim"
	rogue.set_class(_classes["rogue"])
	rogue.set_ancestry(_ancestries["human"])
	rogue.auto_assign()
	var rskills: Array[int] = []
	rskills.assign(_classes["rogue"].skill_choices)
	for i in range(_classes["rogue"].skill_choice_count):
		rogue.toggle_skill(rskills[i], true)
	var exp: Dictionary = rogue.creation_choices()[0]
	assert_eq(str(exp["type"]), "expertise")
	var opts := DictUtil.to_string_array(exp["options"])
	assert_true(rogue.toggle_creation_choice(exp, opts[0], true))
	assert_true(rogue.toggle_creation_choice(exp, opts[1], true))
	assert_false(rogue.toggle_creation_choice(exp, opts[2], true), "count reached")
	assert_true(rogue.is_valid(), str(rogue.problems()))
	rogue.toggle_skill(Skill.from_string(opts[0]), false)
	rogue.creation_choices()
	assert_eq(DictUtil.to_string_array(rogue.creation_picks["expertise"]), [opts[1]] as Array[String], "the dropped skill's expertise is gone")
	assert_eq(rogue.build_sheet().expertise_skills.size(), 2, "defaults fill an incomplete answer")


# --- Score methods ------------------------------------------------------------------

func _ready_fighter() -> CharacterDraft:
	var d := _fighter_draft()
	d.toggle_skill(Skill.Type.ATHLETICS, true)
	d.toggle_skill(Skill.Type.PERCEPTION, true)
	d.auto_choose()
	return d


func test_standard_array_is_the_default_method() -> void:
	var d := _ready_fighter()
	assert_eq(d.method, CharacterDraft.METHOD_STANDARD)
	assert_eq(d.score_choices(), [15, 14, 13, 12, 10, 8] as Array[int])
	assert_eq(d.unassigned_values(), [15, 14, 13, 12, 10, 8] as Array[int])
	assert_has(d.problems(), "Assign every standard-array score.")
	d.auto_assign()
	assert_true(d.is_valid(), str(d.problems()))
	assert_eq(d.unassigned_values(), [] as Array[int])
	d.set_method(CharacterDraft.METHOD_STANDARD)
	assert_true(d.is_valid(), "re-selecting the same method keeps the scores")


func test_point_buy_cost_arithmetic_and_remaining() -> void:
	var d := _ready_fighter()
	d.auto_assign()
	d.set_method(CharacterDraft.METHOD_POINT_BUY)
	assert_eq(d.assigned, [8, 8, 8, 8, 8, 8] as Array[int], "point buy starts at all 8s")
	assert_eq(d.point_buy_spent(), 0)
	assert_eq(d.point_buy_remaining(), 27)
	assert_true(d.is_valid(), "unspent points are allowed: %s" % str(d.problems()))
	assert_eq(d.score_choices(), [15, 14, 13, 12, 11, 10, 9, 8] as Array[int])
	d.assign(Ability.Type.STR, 15)  # 9
	assert_eq(d.point_buy_remaining(), 18)
	d.assign(Ability.Type.DEX, 14)  # 7
	assert_eq(d.point_buy_remaining(), 11)
	d.assign(Ability.Type.CON, 13)  # 5
	assert_eq(d.point_buy_remaining(), 6)
	d.assign(Ability.Type.WIS, 12)  # 4
	d.assign(Ability.Type.CHA, 10)  # 2
	assert_eq(d.point_buy_spent(), 27)
	assert_eq(d.point_buy_remaining(), 0)
	assert_eq(d.assigned, [15, 14, 13, 8, 12, 10] as Array[int], "values may repeat; no swapping")
	assert_true(d.is_valid(), str(d.problems()))
	d.assign(Ability.Type.INT, 16)
	assert_eq(d.assigned[Ability.Type.INT], 8, "above 15 is refused")
	d.assign(Ability.Type.INT, 7)
	assert_eq(d.assigned[Ability.Type.INT], 8, "below 8 is refused")
	assert_false(d.point_buy_affordable(Ability.Type.INT, 9), "no points left")
	assert_true(d.point_buy_affordable(Ability.Type.STR, 14), "lowering is always affordable")
	assert_true(d.point_buy_affordable(Ability.Type.INT, 8))
	# Suggested scores under point buy: the standard spread, exactly 27 points.
	d.auto_assign()
	assert_eq(d.point_buy_remaining(), 0)
	assert_eq(d.assigned[Ability.Type.STR], 15)
	var sheet := d.build_sheet()
	assert_eq(sheet.abilities.get_score(Ability.Type.STR), 16, "ancestry bonus on top of the bought 15")
	assert_eq(int(d.preview()["scores"][Ability.Type.STR]), 16)


func test_point_buy_overspend_is_invalid() -> void:
	var d := _ready_fighter()
	d.set_method(CharacterDraft.METHOD_POINT_BUY)
	for ability in [Ability.Type.STR, Ability.Type.DEX, Ability.Type.CON, Ability.Type.INT]:
		d.assign(ability, 15)  # 4 x 9 = 36
	assert_eq(d.point_buy_spent(), 36)
	assert_eq(d.point_buy_remaining(), -9)
	assert_false(d.is_valid())
	assert_has(d.problems(), "Point buy: 9 points over the 27-point budget.")
	d.assign(Ability.Type.INT, 8)
	assert_eq(d.point_buy_remaining(), 0)
	assert_true(d.is_valid(), str(d.problems()))
	d.assigned[Ability.Type.WIS] = 17  # not reachable through assign()
	assert_eq(d.point_buy_remaining(), -1)
	assert_has(d.problems(), "Point-buy scores must be 8-15.")
	d.assigned[Ability.Type.WIS] = CharacterDraft.UNASSIGNED
	assert_has(d.problems(), "Choose every score.")


func test_roll_assigns_like_the_standard_array() -> void:
	var d := _ready_fighter()
	assert_eq(d.rolled_values, [] as Array[int])
	d.set_method(CharacterDraft.METHOD_ROLL)
	assert_eq(d.method, CharacterDraft.METHOD_ROLL)
	assert_false(d.is_fully_assigned(), "nothing to assign before a roll")
	assert_has(d.problems(), "Roll your scores.")
	d.roll_scores(Rng.new(1234))
	var expected := AbilityScores.roll_scores(Rng.new(1234))
	assert_eq(d.rolled_values, expected, "4d6 drop lowest via AbilityScores.roll_scores")
	assert_eq(d.rolled_values.size(), 6)
	for v in d.rolled_values:
		assert_in_range(v, 3, 18)
	assert_false(d.is_fully_assigned(), "the player assigns the rolled values")
	assert_has(d.problems(), "Assign every rolled score.")
	var pool := d.score_pool()
	assert_eq(d.unassigned_values(), pool)
	for i in range(Ability.COUNT):
		d.assign(i, pool[i])
	assert_true(d.is_fully_assigned())
	assert_eq(d.unassigned_values(), [] as Array[int])
	assert_true(d.is_valid(), str(d.problems()))
	# A value not rolled is refused; assigning a taken value swaps.
	var not_rolled := 3
	while d.rolled_values.has(not_rolled):
		not_rolled += 1
	d.assign(Ability.Type.STR, not_rolled)
	assert_eq(d.assigned[Ability.Type.STR], pool[0], "not a rolled value")
	d.assign(Ability.Type.STR, pool[5])
	assert_eq(d.assigned[Ability.Type.STR], pool[5])
	if pool[5] != pool[0]:
		assert_eq(d.assigned[5], pool[0], "the holder took STR's old value")
	assert_true(d.is_valid(), str(d.problems()))
	var sheet := d.build_sheet()
	assert_eq(sheet.abilities.get_score(Ability.Type.STR), pool[5] + 1, "human +1 on the rolled value")


func test_rolled_duplicates_can_each_be_used_once() -> void:
	var d := _ready_fighter()
	d.method = CharacterDraft.METHOD_ROLL
	d.rolled_values = [12, 15, 12, 9, 10, 12] as Array[int]
	assert_eq(d.score_choices(), [15, 12, 10, 9] as Array[int], "distinct values for the menus")
	assert_eq(d.score_pool(), [15, 12, 12, 12, 10, 9] as Array[int])
	d.assign(Ability.Type.STR, 12)
	d.assign(Ability.Type.DEX, 12)
	d.assign(Ability.Type.CON, 12)
	assert_eq(d.assigned.slice(0, 3), [12, 12, 12] as Array[int], "three 12s rolled, three used")
	d.assign(Ability.Type.INT, 12)
	assert_eq(d.assigned[Ability.Type.INT], 12)
	assert_eq(d.assigned[Ability.Type.STR], CharacterDraft.UNASSIGNED, "a fourth 12 swaps with the first holder")
	d.assign(Ability.Type.STR, 15)
	d.assign(Ability.Type.WIS, 10)
	d.assign(Ability.Type.CHA, 9)
	assert_true(d.is_valid(), str(d.problems()))
	d.auto_assign()
	assert_eq(d.assigned[Ability.Type.STR], 15, "suggestion: highest roll to the primary ability")
	assert_true(d.is_valid(), str(d.problems()))


func test_reroll_replaces_values_and_clears_the_assignment() -> void:
	var d := _ready_fighter()
	var rng := Rng.new(99)
	d.roll_scores(rng)
	d.auto_assign()
	assert_true(d.is_valid(), str(d.problems()))
	var first := d.rolled_values.duplicate()
	d.roll_scores(rng)
	assert_ne(d.rolled_values, first, "the same rng gives new values")
	assert_eq(d.rolled_values.size(), 6)
	assert_false(d.is_fully_assigned(), "a reroll clears the old assignment")
	d.auto_assign()
	var sorted := d.assigned.duplicate()
	sorted.sort()
	var rolled := d.rolled_values.duplicate()
	rolled.sort()
	assert_eq(sorted, rolled, "the new values are the ones assigned")
	# Switching away and back keeps the roll (no free reroll by switching).
	var kept := d.rolled_values.duplicate()
	d.set_method(CharacterDraft.METHOD_STANDARD)
	assert_true(d.is_valid(), "back to the standard array, suggested")
	assert_eq(d.assigned[Ability.Type.STR], 15)
	d.set_method(CharacterDraft.METHOD_ROLL)
	assert_eq(d.rolled_values, kept)
	assert_true(d.is_valid(), "the kept roll is suggested again: %s" % str(d.problems()))
	d.set_method("nonsense")
	assert_eq(d.method, CharacterDraft.METHOD_ROLL, "unknown methods are ignored")


func test_every_method_builds_every_class() -> void:
	for def in CharacterDraft.ordered_classes(_classes):
		for m in CharacterDraft.METHODS:
			var d := CharacterDraft.new()
			d.character_name = "Tester"
			d.set_class(def)
			d.set_ancestry(_ancestries["human"])
			if m == CharacterDraft.METHOD_ROLL:
				d.roll_scores(Rng.new(7))
			else:
				d.set_method(m)
			d.auto_assign()
			for skill in def.skill_choices:
				d.toggle_skill(skill, true)
			d.auto_choose()
			assert_true(d.is_valid(), "%s/%s: %s" % [def.id, m, str(d.problems())])
			assert_true(int(d.preview()["hp"]) > 0, "%s/%s preview" % [def.id, m])
			assert_not_null(d.build_sheet(), "%s/%s sheet" % [def.id, m])

extends TestCase
## CharacterDraft: the creator's rules (standard array, skills, preview).

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
	assert_eq(d.problems().size(), 3, "name, scores, skills")
	d.character_name = "Brann"
	d.auto_assign()
	d.toggle_skill(Skill.Type.ATHLETICS, true)
	assert_false(d.is_valid())
	d.toggle_skill(Skill.Type.INTIMIDATION, true)
	assert_true(d.is_valid(), str(d.problems()))
	var sheet := d.build_sheet()
	assert_not_null(sheet)
	assert_eq(sheet.name, "Brann")
	assert_eq(sheet.class_id, "fighter")
	assert_eq(sheet.ancestry_id, "human")
	assert_eq(sheet.abilities.get_score(Ability.Type.STR), 16, "15 + human bonus")
	assert_eq(sheet.proficient_skills.size(), 2)


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

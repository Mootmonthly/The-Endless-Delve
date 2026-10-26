extends TestCase
## Full class progression against data/: every class levels 1 -> 20, slot
## tables, LevelUp choice types (subclass, fighting style, expertise,
## invocations, metamagic, feature options, skills) and their validation,
## creation choices, and the Features registry against data/features.

var content: Dictionary


func before_each() -> void:
	content = ContentLoader.cache()


func _cls(id: String) -> ClassDefinition:
	var classes: Dictionary = content["classes"]
	var c: ClassDefinition = classes[id]
	return c


func _new(id: String, choices: Dictionary = {}) -> CharacterSheet:
	var cls := _cls(id)
	var skills: Array[int] = []
	for i in range(cls.skill_choice_count):
		skills.append(cls.skill_choices[i])
	var scores := AbilityScores.new()
	scores.set_all([14, 14, 14, 14, 14, 14])
	return CharacterBuilder.create("T", cls, null, scores, skills, null, content, choices)


## Answers the next level with defaults: average hp, +2 to the first ability
## below 19, the first spell options.
func _auto(ch: Dictionary, s: CharacterSheet) -> Dictionary:
	var made := {"hp": "average"}
	if ch["asi"]:
		for a in range(Ability.COUNT):
			if s.abilities.get_score(a) <= 18:
				made["asi"] = {Ability.abbreviation(a): 2}
				break
	var cantrips: Array = []
	var spells: Array = []
	for id_v: Variant in ch["spell_options"]:
		var spell: SpellDefinition = content["spells"][str(id_v)]
		if spell.level == 0 and cantrips.size() < int(ch["cantrips_to_learn"]):
			cantrips.append(str(id_v))
		elif spell.level > 0 and spells.size() < int(ch["spells_to_learn"]):
			spells.append(str(id_v))
	made["learn_cantrips"] = cantrips
	made["learn_spells"] = spells
	return made


func _level_to(s: CharacterSheet, level: int, extra: Dictionary = {}) -> void:
	while s.level < level:
		s.xp = maxi(s.xp, Experience.xp_for_level(s.level + 1))
		var made := _auto(LevelUp.choices(s, content), s)
		if s.level + 1 == level:
			made.merge(extra, true)
		var err := LevelUp.apply(s, made, content, null)
		assert_eq(err, "", "%s level %d" % [s.class_id, s.level + 1])
		if not err.is_empty():
			return


func test_content_loads_completely() -> void:
	assert_eq(len(content["classes"]), 12)
	assert_eq(len(content["spells"]), ContentLoader.json_files("res://data/spells").size(), "every spell file loads")
	assert_eq(len(content["features"]), ContentLoader.json_files("res://data/features").size())
	assert_true(ContentLoader.validate_references(content).is_empty(), str(ContentLoader.validate_references(content)))
	for key: String in ["invocations", "metamagic", "fighting_styles"]:
		assert_true(len(content[key]) > 0, key)


func test_features_registry_matches_data() -> void:
	var features: Dictionary = content["features"]
	for id in Features.IMPLEMENTED:
		assert_true(features.has(id), "data/features/%s.json" % id)
	for pair: Array in [[Features.IMPLEMENTED_INVOCATIONS, "invocations"], [Features.IMPLEMENTED_METAMAGIC, "metamagic"], [Features.IMPLEMENTED_FIGHTING_STYLES, "fighting_styles"]]:
		var records: Dictionary = content[pair[1]]
		for id: String in pair[0]:
			if id == "twinned_spell" and not records.has(id):
				continue  # not in the SRD 5.1 API data; modelled for completeness
			assert_true(records.has(id), "%s/%s" % [pair[1], id])
	# Every class feature id through level 5 is either implemented or marked unsupported.
	var classes: Dictionary = content["classes"]
	for cls_v: Variant in classes.values():
		var cls: ClassDefinition = cls_v
		for lvl in range(1, 6):
			for f in cls.features_at(lvl) + cls.subclass_features_at(lvl):
				var rec: Dictionary = features.get(f, {})
				assert_eq(str(rec.get("mechanic", "")), "implemented" if Features.is_implemented(f) else "unsupported", "%s %s" % [cls.id, f])


func test_every_class_levels_to_twenty() -> void:
	var classes: Dictionary = content["classes"]
	for id: String in classes.keys():
		var s := _new(id)
		_level_to(s, 20)
		assert_eq(s.level, 20, id)
		var cls := _cls(id)
		assert_eq(s.spell_slots_max, cls.slots_for_level(20), id + " slots")
		assert_eq(s.subclass_id, cls.subclass_id, id + " subclass chosen")
		for f in cls.features_at(5):
			assert_has(s.features, f, "%s has %s" % [id, f])
		assert_eq(s.hit_dice_total, 20)


func test_full_caster_slots_reach_ninth_level() -> void:
	var wiz := _cls("wizard")
	assert_eq(wiz.slots_for_level(20).size(), 9)
	assert_eq(wiz.slots_for_level(17)[8], 1)
	var pal := _cls("paladin")
	assert_true(pal.is_half_caster())
	assert_eq(pal.spellcasting_ability, Ability.Type.CHA)
	assert_eq(_cls("ranger").spellcasting_ability, Ability.Type.WIS)
	assert_eq(_cls("warlock").slot_recovery, "short_rest")
	assert_eq(_cls("warlock").slots_for_level(5), [0, 0, 2])


func test_level_one_subclasses_and_creation_choices() -> void:
	var cleric := _new("cleric")
	assert_eq(cleric.subclass_id, "life")
	assert_has(cleric.features, "disciple_of_life")
	assert_has(cleric.always_prepared, "bless")
	assert_has(cleric.spells_prepared, "cure_wounds")
	var sorc := _new("sorcerer", {"feature_options": {"dragon_ancestor": "dragon_ancestor_red"}})
	assert_has(sorc.features, "dragon_ancestor_red")
	assert_has(sorc.features, "draconic_resilience")
	assert_eq(sorc.max_hp, 6 + 2 + 1, "d6 + CON 2 + draconic resilience")
	var fighter_choices := CharacterBuilder.creation_choices(_cls("fighter"), [] as Array[int], content)
	assert_eq(fighter_choices[0]["type"], "fighting_style")
	var fighter := _new("fighter", {"fighting_style": "dueling"})
	assert_eq(fighter.fighting_styles, ["dueling"])
	var rogue_cls := _cls("rogue")
	var rogue := _new("rogue", {"expertise": [Skill.key_of(rogue_cls.skill_choices[0]), Skill.key_of(rogue_cls.skill_choices[1])]})
	assert_eq(rogue.expertise_skills.size(), 2)
	var defaulted := _new("rogue")
	assert_eq(defaulted.expertise_skills.size(), 2, "omitted answers take the defaults")


func test_paladin_gains_spellcasting_and_a_fighting_style_at_two() -> void:
	var s := _new("paladin")
	s.xp = Experience.xp_for_level(2)
	var ch := LevelUp.choices(s, content)
	assert_eq(ch["new_spell_slots"], [2])
	assert_eq(ch["prepared_count"], 2 + 1, "CHA 2 + half of level 2")
	var styles: Dictionary = {}
	for entry: Dictionary in ch["choices"]:
		styles[entry["type"]] = entry
	assert_true(styles.has("fighting_style"))
	assert_false("archery" in styles["fighting_style"]["options"], "paladin list")
	assert_ne(LevelUp.apply(s, {"hp": "average", "fighting_style": "archery"}, content, null), "")
	assert_eq(LevelUp.apply(s, {"hp": "average", "fighting_style": "defense"}, content, null), "")
	assert_eq(s.casting_ability, Ability.Type.CHA)
	assert_eq(s.spell_slots_max, [2])
	assert_eq(s.fighting_styles, ["defense"])


func test_subclass_and_feature_option_choices() -> void:
	var r := _new("ranger")
	_level_to(r, 2)
	r.xp = Experience.xp_for_level(3)
	var ch := LevelUp.choices(r, content)
	var choice_list: Array = ch["choices"]
	var types: Array = choice_list.map(func(e: Dictionary) -> String: return str(e["type"]))
	assert_has(types, "subclass")
	assert_has(types, "feature_option")
	assert_has(ch["features_gained"], "hunters_prey")
	assert_has(ch["features_detail"], {"id": "hunters_prey", "implemented": true, "subclass": true})
	var made := _auto(ch, r)
	made["subclass"] = "wrong"
	assert_true(LevelUp.apply(r, made, content, null).contains("not a subclass option"))
	made["subclass"] = "hunter"
	made["feature_options"] = {"hunters_prey": "foe_slayer"}
	assert_true(LevelUp.apply(r, made, content, null).contains("not a hunters_prey option"))
	made["feature_options"] = {"hunters_prey": "colossus_slayer"}
	assert_eq(LevelUp.apply(r, made, content, null), "")
	assert_eq(r.subclass_id, "hunter")
	assert_has(r.features, "colossus_slayer")


func test_warlock_invocations_and_pact_boon() -> void:
	var w := _new("warlock")
	w.xp = Experience.xp_for_level(2)
	var ch := LevelUp.choices(w, content)
	var inv: Dictionary = {}
	for entry: Dictionary in ch["choices"]:
		if entry["type"] == "invocations":
			inv = entry
	assert_eq(inv["count"], 2)
	assert_false("thirsting_blade" in inv["options"], "level 5 and pact prerequisites")
	assert_eq("agonizing_blast" in inv["options"], w.spells_known.has("eldritch_blast"))
	var made := _auto(ch, w)
	made["invocations"] = ["armor_of_shadows"]
	assert_true(LevelUp.apply(w, made, content, null).contains("choose 2"))
	made["invocations"] = ["armor_of_shadows", "armor_of_shadows"]
	assert_true(LevelUp.apply(w, made, content, null).contains("twice"))
	made["invocations"] = ["armor_of_shadows", "devils_sight"]
	assert_eq(LevelUp.apply(w, made, content, null), "")
	assert_eq(w.invocations, ["armor_of_shadows", "devils_sight"])
	_level_to(w, 3, {"feature_options": {"pact_boon": "pact_of_the_blade"}})
	assert_has(w.features, "pact_of_the_blade")
	var spell_options: Array = LevelUp.choices(w, content)["spell_options"]
	assert_true(spell_options.has("burning_hands") or w.spells_known.has("burning_hands"), "fiend expanded list")


func test_sorcerer_metamagic_bard_expertise_and_lore_skills() -> void:
	var s := _new("sorcerer")
	_level_to(s, 3, {"metamagic": ["quickened_spell", "empowered_spell"]})
	assert_eq(s.metamagic, ["quickened_spell", "empowered_spell"])
	assert_eq(s.class_resource("sorcery_points"), 3)
	var b := _new("bard")
	_level_to(b, 2)
	b.xp = Experience.xp_for_level(3)
	var ch := LevelUp.choices(b, content)
	assert_eq(ch["skills_to_choose"], 3)
	var made := _auto(ch, b)
	var skill_options: Array = []
	for entry: Dictionary in ch["choices"]:
		if entry["type"] == "skills":
			skill_options = entry["options"]
	assert_false(skill_options.has(Skill.key_of(b.proficient_skills[0])), "only new skills")
	made["skills"] = ["HISTORY", "nature", "RELIGION"]
	if b.proficient_skills.has(Skill.Type.HISTORY) or b.proficient_skills.has(Skill.Type.NATURE) or b.proficient_skills.has(Skill.Type.RELIGION):
		made["skills"] = skill_options.slice(0, 3)
	var known: Array = []
	for skill in b.proficient_skills:
		known.append(Skill.key_of(skill))
	made["expertise"] = known.slice(0, 2)
	assert_eq(LevelUp.apply(b, made, content, null), "")
	assert_true(b.proficient_skills.has(Skill.Type.HISTORY))
	assert_eq(b.expertise_skills.size(), 2)
	assert_has(b.features, "bonus_proficiencies")


func test_druid_bonus_cantrip_and_circle_spells() -> void:
	var d := _new("druid")
	d.xp = Experience.xp_for_level(2)
	var before := LevelUp.choices(d, content)
	assert_has(before["features_gained"], "bonus_cantrip")
	var cls := _cls("druid")
	var plain := ClassDefinition.table_value(cls.cantrips_known_table, 2) - ClassDefinition.table_value(cls.cantrips_known_table, 1)
	assert_eq(before["cantrips_to_learn"], plain + 1)
	_level_to(d, 2)
	_level_to(d, 3, {"feature_options": {"circle_spells": "circle_of_the_land_arctic"}})
	assert_has(d.features, "circle_of_the_land_arctic")
	assert_has(d.always_prepared, "hold_person")
	assert_has(d.spells_prepared, "spike_growth")
	assert_eq(LevelUp.feature_options("circle_spells", cls).size(), 7)


func test_monk_and_barbarian_tables_from_data() -> void:
	var m := _new("monk")
	_level_to(m, 5)
	assert_eq(m.martial_arts_die(), 6)
	assert_eq(m.class_resource("ki"), 5)
	assert_eq(m.attacks_per_action(), 2)
	assert_eq(m.effective_speed(), 40)
	var f := _new("fighter")
	_level_to(f, 11)
	assert_eq(f.attacks_per_action(), 3, "fighter extra attacks table")
	var b := _new("barbarian")
	_level_to(b, 9)
	assert_eq(Encounter.rage_damage(b), 3)
	assert_eq(b.class_resource("rage"), 4)


func test_monsters_have_creature_types_and_multiattack() -> void:
	var monsters: Dictionary = content["monsters"]
	for m_v: Variant in monsters.values():
		var m: MonsterDefinition = m_v
		assert_false(m.creature_type.is_empty(), m.id)
		for attack_name in m.multiattack:
			assert_true(m.attack_index(attack_name) >= 0, "%s multiattack %s" % [m.id, attack_name])
	var troll: MonsterDefinition = monsters["troll"]
	var c := Combatant.from_monster("troll", troll, Combatant.TEAM_MONSTERS, Rng.new(1))
	assert_eq(c.attacks_per_action, 3)
	assert_eq(c.creature_type, "giant")
	var zombie: MonsterDefinition = monsters["zombie"]
	assert_eq(zombie.to_sheet().condition_immunities, ["poisoned"])
	assert_eq(Combatant.from_monster("z", zombie, 1, Rng.new(1)).creature_type, "undead")


func test_a_sheet_past_its_subclass_level_gets_the_subclass_late() -> void:
	var f := _new("fighter")
	_level_to(f, 3)
	f.subclass_id = ""
	f.features.erase("improved_critical")
	f.xp = Experience.xp_for_level(4)
	var ch := LevelUp.choices(f, content)
	assert_has(ch["features_gained"], "improved_critical", "the level-3 subclass feature comes with the late choice")
	assert_eq(LevelUp.apply(f, _auto(ch, f), content, null), "")
	assert_eq(f.subclass_id, "champion")
	assert_has(f.features, "improved_critical")

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


## Every class from level 1 to 20 through LevelUpDraft.first_valid (what the
## smoke bot sends): LevelUp.apply accepts each answer, every progression
## choice is answered explicitly, and over the loop every choice type shows up.
func test_first_valid_is_accepted_for_every_class_from_1_to_20() -> void:
	var seen := {}
	for id: String in CharacterDraft.CLASS_ORDER:
		var d := CharacterDraft.new()
		d.character_name = "Lev"
		d.set_class(ContentLoader.load_classes()[id])
		d.set_ancestry(ContentLoader.load_ancestries()["human"])
		d.auto_assign()
		for skill in d.class_def.skill_choices:
			d.toggle_skill(skill, true)
		d.auto_choose()
		assert_true(d.is_valid(), "%s: %s" % [id, str(d.problems())])
		var s := d.build_sheet()
		while s.level < 20:
			s.xp = maxi(s.xp, Experience.xp_for_level(s.level + 1))
			var offer := LevelUp.choices(s)
			var draft := LevelUpDraft.first_valid(offer, s)
			assert_true(draft.is_valid(), "%s level %d: %s" % [id, s.level + 1, str(draft.problems())])
			var made := draft.to_choices()
			for entry in draft.choice_entries():
				var kind := str(entry["type"])
				seen[kind] = true
				if kind == LevelUp.CHOICE_FEATURE_OPTION:
					assert_true((made.get("feature_options", {}) as Dictionary).has(str(entry["feature"])), "%s answered explicitly" % entry["feature"])
				else:
					assert_true(made.has(kind), "%s level %d answers %s explicitly" % [id, s.level + 1, kind])
			var err := LevelUp.apply(s, made, {}, null)
			assert_eq(err, "", "%s to level %d" % [id, s.level + 1])
			if not err.is_empty():
				break
		assert_eq(s.level, 20, id)
		assert_false(s.subclass_id.is_empty(), "%s has a subclass by 20" % id)
	for kind: String in [LevelUp.CHOICE_SUBCLASS, LevelUp.CHOICE_FIGHTING_STYLE, LevelUp.CHOICE_EXPERTISE,
			LevelUp.CHOICE_INVOCATIONS, LevelUp.CHOICE_METAMAGIC, LevelUp.CHOICE_FEATURE_OPTION, LevelUp.CHOICE_SKILLS]:
		assert_true(seen.has(kind), "the loop answered a %s choice" % kind)


func test_choice_sections_labels_and_feature_cards() -> void:
	var s := _sheet("fighter")
	_level_to(s, 2)
	s.xp = Experience.xp_for_level(3)
	var d := LevelUpDraft.new(LevelUp.choices(s), s)
	var sub: Dictionary = {}
	for entry in d.choice_entries():
		if str(entry["type"]) == LevelUp.CHOICE_SUBCLASS:
			sub = entry
	assert_false(sub.is_empty(), "level 3 asks for the archetype")
	assert_eq(d.picks_for(sub), ["champion"] as Array[String], "the single SRD subclass starts picked")
	assert_eq(d.option_label(sub, "champion"), "Champion")
	assert_ne(d.option_description(sub, "champion"), "")
	assert_eq(d.to_choices()["subclass"], "champion", "sent explicitly")
	var cards := d.feature_cards()
	var crit := {}
	for c in cards:
		if str(c["id"]) == "improved_critical":
			crit = c
	assert_false(crit.is_empty(), "subclass feature card")
	assert_true(bool(crit["subclass"]))
	assert_true(bool(crit["implemented"]))
	assert_ne(str(crit["description"]), "", "description from data/features")
	assert_true(d.is_valid(), str(d.problems()))
	assert_true(d.toggle_choice(sub, "champion", false))
	assert_false(d.is_valid(), "the subclass must be chosen")
	# Warlock invocations: counts, modelled first in first_valid, labels.
	var w := _sheet("warlock")
	_level_to(w, 1)
	w.xp = Experience.xp_for_level(2)
	var wd := LevelUpDraft.new(LevelUp.choices(w), w)
	var inv: Dictionary = {}
	for entry in wd.choice_entries():
		if str(entry["type"]) == LevelUp.CHOICE_INVOCATIONS:
			inv = entry
	assert_false(inv.is_empty(), "warlock level 2 learns invocations")
	assert_eq(wd.choice_count(inv), 2)
	assert_eq(wd.option_label(inv, "agonizing_blast"), "Agonizing Blast")
	assert_true(wd.option_implemented(inv, "agonizing_blast"))
	assert_true(wd.option_implemented(inv, "beast_speech"), "every invocation is modelled since round C")
	var auto := LevelUpDraft.first_valid(wd.offer, w)
	for p in auto.picks_for(inv):
		assert_true(Features.IMPLEMENTED_INVOCATIONS.has(p), "%s: modelled invocations first" % p)
	assert_true(wd.toggle_choice(inv, "beast_speech", true))
	assert_true(wd.toggle_choice(inv, "agonizing_blast", true))
	assert_false(wd.toggle_choice(inv, "armor_of_shadows", true), "count reached")
	assert_eq(wd.to_choices()["invocations"], ["beast_speech", "agonizing_blast"])


func test_spell_options_are_grouped_by_level() -> void:
	var s := _sheet("wizard")
	_level_to(s, 4)
	s.xp = Experience.xp_for_level(5)
	var d := LevelUpDraft.new(LevelUp.choices(s), s)
	var groups := d.spell_options_by_level()
	assert_true(groups.has(3), "3rd-level spells at level 5")
	for lvl: int in groups.keys():
		for id: String in groups[lvl]:
			assert_eq(d.spell_level(id), lvl)


func _raised(class_id: String, to_level: int) -> CharacterSheet:
	var d := CharacterDraft.new()
	d.character_name = "Lev"
	d.set_class(ContentLoader.load_classes()[class_id])
	d.set_ancestry(ContentLoader.load_ancestries()["human"])
	d.auto_assign()
	for skill in d.class_def.skill_choices:
		d.toggle_skill(skill, true)
	d.auto_choose()
	var s := d.build_sheet()
	while s.level < to_level:
		s.xp = maxi(s.xp, Experience.xp_for_level(s.level + 1))
		assert_eq(LevelUp.apply(s, LevelUpDraft.first_valid(LevelUp.choices(s), s).to_choices(), {}, null), "")
	return s


func _entry(draft: LevelUpDraft, kind: String, feature: String = "") -> Dictionary:
	for e in draft.choice_entries():
		if str(e["type"]) == kind and (feature.is_empty() or str(e.get("feature", "")) == feature):
			return e
	return {}


## Pact of the Tome's cantrips: optional until the boon is picked, then three
## cantrips with spell labels; Book of Ancient Secrets likewise.
func test_tome_cantrips_follow_the_pact_boon_pick() -> void:
	var s := _raised("warlock", 2)
	s.xp = Experience.xp_for_level(3)
	var offer := LevelUp.choices(s)
	var draft := LevelUpDraft.first_valid(offer, s)
	var boon := _entry(draft, LevelUp.CHOICE_FEATURE_OPTION, "pact_boon")
	var tome := _entry(draft, LevelUp.CHOICE_TOME_CANTRIPS)
	assert_false(boon.is_empty(), "the pact boon is chosen at 3")
	assert_false(tome.is_empty(), "the tome cantrips are offered alongside")
	assert_eq(draft.choice_title(tome), "Book of Shadows cantrips (Pact of the Tome)")
	assert_has(draft.option_label(tome, str(tome["options"][0])), "(cantrip")
	draft.toggle_choice(boon, "pact_of_the_blade", true)
	assert_false(draft.requirement_met(tome))
	assert_has(draft.choice_note(tome), "Only if you pick")
	for o in draft.picks_for(tome):
		draft.toggle_choice(tome, o, false)
	assert_true(draft.is_valid(), str(draft.problems()))
	assert_eq(draft.to_choices()[LevelUp.CHOICE_TOME_CANTRIPS], [], "unmet: answered with []")
	draft.toggle_choice(boon, "pact_of_the_tome", true)
	assert_true(draft.requirement_met(tome))
	assert_false(draft.is_valid(), "three cantrips are now needed")
	draft.fill_choice(tome)
	assert_true(draft.is_valid(), str(draft.problems()))
	assert_eq(LevelUp.apply(s, draft.to_choices(), {}, null), "")
	assert_eq(s.tome_cantrips.size(), 3)


## Spell Mastery at 18 (one 1st- and one 2nd-level spell) and Signature
## Spells at 20, through first_valid and with labels.
func test_spell_mastery_and_signature_spells_choices() -> void:
	var s := _raised("wizard", 17)
	s.xp = Experience.xp_for_level(18)
	var draft := LevelUpDraft.first_valid(LevelUp.choices(s), s)
	var mastery := _entry(draft, LevelUp.CHOICE_SPELL_MASTERY)
	assert_false(mastery.is_empty())
	assert_eq(draft.choice_title(mastery), "Spell Mastery (one 1st- and one 2nd-level spell)")
	assert_true(draft.is_valid(), str(draft.problems()))
	var firsts: Array[String] = []
	for o in DictUtil.to_string_array(mastery["options"]):
		if draft.spell_level(o) == 1:
			firsts.append(o)
	if firsts.size() >= 2:
		draft.toggle_choice(mastery, draft.picks_for(mastery)[1], false)
		draft.toggle_choice(mastery, firsts[1] if firsts[1] != draft.picks_for(mastery)[0] else firsts[0], true)
		assert_false(draft.is_valid(), "two 1st-level spells are refused")
		draft = LevelUpDraft.first_valid(LevelUp.choices(s), s)
	assert_eq(LevelUp.apply(s, draft.to_choices(), {}, null), "")
	assert_eq(s.spell_mastery.size(), 2)
	while s.level < 20:
		s.xp = Experience.xp_for_level(s.level + 1)
		var d := LevelUpDraft.first_valid(LevelUp.choices(s), s)
		var sig := _entry(d, LevelUp.CHOICE_SIGNATURE_SPELLS)
		if not sig.is_empty():
			assert_eq(d.choice_title(sig), "Signature Spells")
			assert_has(d.option_label(sig, str(sig["options"][0])), "3rd level")
		assert_eq(LevelUp.apply(s, d.to_choices(), {}, null), "")
	assert_eq(s.signature_spells.size(), 2)

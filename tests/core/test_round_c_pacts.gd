extends TestCase
## Round C item 8: Pact of the Chain (special familiars, the familiar's
## attack in place of the warlock's), Pact of the Tome (three cantrips),
## Book of Ancient Secrets (ritual book), the at-will and once-per-rest
## invocations, One with Shadows, Gaze of Two Minds. Real data.

const SURE := {"name": "Sure", "kind": "melee", "to_hit": 100, "damage": "4", "damage_type": "slashing", "ability": "STR"}

var content: Dictionary


func before_each() -> void:
	content = ContentLoader.cache()


func _evs(res: Dictionary) -> Array:
	var evs: Array = res.get("events", [])
	return evs


func _warlock(level: int = 15) -> CharacterSheet:
	var s := CoreFixtures.caster("Lock", Ability.Type.CHA, ["eldritch_blast"], 80)
	s.abilities.set_score(Ability.Type.CHA, 30)
	s.class_id = "warlock"
	s.level = level
	s.spell_slots_max = [0, 0, 0, 0, 3]
	s.spell_slots = [0, 0, 0, 0, 3]
	s.slot_recovery = "short_rest"
	return s


func _gob(hp: int = 200) -> CharacterSheet:
	return CoreFixtures.sheet("Gob", hp, [1, 1, 1, 1, 1, 1])


func _fight(hero: CharacterSheet, foes: Dictionary = {}, allies: Dictionary = {}) -> Encounter:
	var f := foes if not foes.is_empty() else {"gob": [_gob(), Vector2i(3, 2), [SURE]]}
	var e := CoreFixtures.duel(hero, [SURE], f, content, "hero", Vector2i(3, 3), allies)
	assert_not_null(e)
	return e


func _new_warlock() -> CharacterSheet:
	var classes: Dictionary = content["classes"]
	var cls: ClassDefinition = classes["warlock"]
	var skills: Array[int] = []
	for i in range(cls.skill_choice_count):
		skills.append(cls.skill_choices[i])
	var scores := AbilityScores.new()
	scores.set_all([14, 14, 14, 14, 14, 14])
	return CharacterBuilder.create("W", cls, null, scores, skills, null, content)


## Levels a sheet once with average hp and the first spell options, merging extra.
func _level(s: CharacterSheet, extra: Dictionary = {}) -> String:
	s.xp = maxi(s.xp, Experience.xp_for_level(s.level + 1))
	var ch := LevelUp.choices(s, content)
	var made := {"hp": "average"}
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
	made.merge(extra, true)
	return LevelUp.apply(s, made, content, null)


func _choice(s: CharacterSheet, kind: String) -> Dictionary:
	s.xp = maxi(s.xp, Experience.xp_for_level(s.level + 1))
	for entry: Dictionary in LevelUp.choices(s, content)["choices"]:
		if entry["type"] == kind:
			return entry
	return {}


func test_every_invocation_is_modelled() -> void:
	for key: Variant in content["invocations"].keys():
		assert_has(Features.IMPLEMENTED_INVOCATIONS, str(key))


func test_pact_of_the_tome_offers_three_cantrips() -> void:
	var w := _new_warlock()
	assert_eq(_level(w, {"invocations": ["armor_of_shadows", "devils_sight"]}), "")
	var tome := _choice(w, LevelUp.CHOICE_TOME_CANTRIPS)
	assert_eq([tome["count"], tome["requires"]], [3, "pact_of_the_tome"])
	assert_has(tome["options"], "sacred_flame", "any class's cantrips")
	assert_eq(_level(w, {"feature_options": {"pact_boon": "pact_of_the_tome"}, "tome_cantrips": ["sacred_flame", "guidance", "shillelagh"]}), "")
	assert_eq(w.tome_cantrips, ["sacred_flame", "guidance", "shillelagh"] as Array[String])
	assert_true(w.is_spell_prepared("sacred_flame") and w.spells_known.has("guidance"))
	var book := _choice(w, LevelUp.CHOICE_RITUAL_BOOK)
	assert_true(book.is_empty() or book.has("requires"), "the book needs the invocation")


func test_other_pacts_skip_the_tome_cantrips() -> void:
	var w := _new_warlock()
	_level(w, {"invocations": ["armor_of_shadows", "devils_sight"]})
	assert_eq(_level(w, {"feature_options": {"pact_boon": "pact_of_the_chain"}, "tome_cantrips": []}), "")
	assert_true(w.tome_cantrips.is_empty())
	assert_true(w.is_spell_prepared("find_familiar"), "the chain teaches Find Familiar")
	var r := OutOfCombat.cast(w, "find_familiar", content, Rng.new(1), [], {"form": "imp", "ritual": true})
	assert_true(r["ok"] == true, str(r["error"]))
	assert_eq(w.companions[0]["monster"], "imp")
	var plain := CoreFixtures.caster("Wiz", Ability.Type.INT, ["find_familiar"])
	assert_false(OutOfCombat.cast(plain, "find_familiar", content, Rng.new(1), [], {"form": "imp"})["ok"] == true, "imps need the chain")


func test_book_of_ancient_secrets_rituals() -> void:
	var w := _warlock(5)
	w.features.append("pact_of_the_tome")
	w.invocations.append("book_of_ancient_secrets")
	w.ritual_book = ["detect_magic", "unseen_servant"]
	var r := OutOfCombat.cast(w, "detect_magic", content, Rng.new(1), [], {"ritual": true})
	assert_true(r["ok"] == true, str(r["error"]))
	assert_eq(r["slot_level"], 0)
	assert_false(OutOfCombat.cast(w, "detect_magic", content, Rng.new(1))["ok"] == true, "only as a ritual")
	var w2 := _new_warlock()
	w2.features.append("pact_of_the_tome")
	w2.invocations.append("book_of_ancient_secrets")
	var book := _choice(w2, LevelUp.CHOICE_RITUAL_BOOK)
	assert_eq(book["count"], 2)
	assert_has(book["options"], "detect_magic")


func test_familiar_attacks_in_place_of_an_attack() -> void:
	var w := _warlock()
	w.features.append("pact_of_the_chain")
	w.companions = [{"id": "c1", "monster": "imp", "spell": "find_familiar", "hp": 10}]
	var e := _fight(w)
	var fam: Combatant = null
	for c in e.combatants():
		if c.is_summon():
			fam = c
	assert_not_null(fam)
	assert_true(GridMath.is_adjacent(fam.position, Vector2i(3, 2)), "the imp stands next to the goblin")
	var plain := CoreFixtures.duel(_warlock(), [SURE], {"gob": [_gob(), Vector2i(3, 2), [SURE]]}, content)
	assert_true(str(plain.submit(CoreFixtures.intent("attack", "hero", {"target": "gob", "via_familiar": true}))["error"]).contains("Chain"))
	var res := e.submit(CoreFixtures.intent("attack", "hero", {"target": "gob", "attack_index": 0, "via_familiar": true}))
	assert_true(res["ok"] == true, str(res["error"]))
	var used := CoreFixtures.first_event(_evs(res), "reaction_used")
	assert_eq([used["actor"], used["reaction"], used["owner"]], [fam.id, "familiar_attack", "hero"])
	assert_eq(CoreFixtures.first_event(_evs(res), "attack")["attacker"], fam.id)
	assert_true(e.get_combatant("hero").action_used)
	assert_true(str(e.submit(CoreFixtures.intent("attack", "hero", {"target": "gob", "attack_index": 0, "via_familiar": true}))["error"]) != "", "one reaction per round")


func test_at_will_invocations_need_no_slot() -> void:
	var w := _warlock()
	w.invocations.append_array(["eldritch_sight", "misty_visions", "chains_of_carceri"])
	var r := OutOfCombat.cast(w, "detect_magic", content, Rng.new(1))
	assert_true(r["ok"] == true, str(r["error"]))
	assert_eq([r["slot_level"], r["events"][0]["invocation"]], [0, "eldritch_sight"])
	var fiend := _gob()
	var e := _fight(w, {"gob": [_gob(), Vector2i(3, 2), [SURE]], "imp": [fiend, Vector2i(6, 3), [SURE]]})
	e.get_combatant("imp").creature_type = "fiend"
	var res := e.submit(CoreFixtures.intent("cast", "hero", {"spell": "silent_image", "point": [5, 5]}))
	assert_true(res["ok"] == true, str(res["error"]))
	assert_eq(CoreFixtures.first_event(_evs(res), "cast")["slot_level"], 0)
	e.get_combatant("hero").action_used = false
	assert_true(str(e.submit(CoreFixtures.intent("cast", "hero", {"spell": "hold_monster", "target": "gob"}))["error"]).contains("celestials"))
	res = e.submit(CoreFixtures.intent("cast", "hero", {"spell": "hold_monster", "target": "imp"}))
	assert_true(res["ok"] == true, str(res["error"]))
	assert_eq(e.get_combatant("hero").sheet.spell_slots[4], 3, "no slot spent")
	e.get_combatant("hero").action_used = false
	assert_true(str(e.submit(CoreFixtures.intent("cast", "hero", {"spell": "hold_monster", "target": "imp"}))["error"]).contains("already"))


func test_minions_of_chaos_once_per_long_rest_out_of_combat() -> void:
	var w := _warlock()
	w.invocations.append("minions_of_chaos")
	w.class_resources[CharacterSheet.INVOCATION_PREFIX + "minions_of_chaos"] = 1
	var r := OutOfCombat.cast(w, "conjure_elemental", content, Rng.new(1), [], {"form": "air_elemental"})
	assert_true(r["ok"] == true, str(r["error"]))
	assert_eq([r["slot_level"], w.spell_slots[4], r["events"][0]["invocation"]], [5, 2, "minions_of_chaos"])
	assert_false(OutOfCombat.cast(w, "conjure_elemental", content, Rng.new(1), [], {"form": "air_elemental"})["ok"] == true, "used up")


func test_one_with_shadows_needs_shade_and_ends_on_moving() -> void:
	var w := _warlock()
	w.invocations.append("one_with_shadows")
	var e := _fight(w)
	assert_true(str(e.submit(CoreFixtures.intent("use_feature", "hero", {"feature": "one_with_shadows"}))["error"]).contains("dim light"))
	e.set_light(Encounter.LIGHT_DIM)
	var res := e.submit(CoreFixtures.intent("use_feature", "hero", {"feature": "one_with_shadows"}))
	assert_true(res["ok"] == true, str(res["error"]))
	var hero := e.get_combatant("hero")
	assert_true(hero.is_invisible())
	e.submit(CoreFixtures.intent("move", "hero", {"path": [[3, 4]]}))
	assert_false(hero.is_invisible(), "moving ends it")


func test_gaze_of_two_minds_sees_through_an_ally() -> void:
	var w := _warlock()
	w.invocations.append("gaze_of_two_minds")
	var e := _fight(w, {"gob": [_gob(), Vector2i(9, 9), [SURE]]}, {"ally": [CoreFixtures.sheet("Ally"), Vector2i(3, 4), [SURE]]})
	var res := e.submit(CoreFixtures.intent("use_feature", "hero", {"feature": "gaze_of_two_minds", "target": "ally"}))
	assert_true(res["ok"] == true, str(res["error"]))
	var hero := e.get_combatant("hero")
	assert_true(hero.has_condition(Conditions.BLINDED) and hero.has_condition(Conditions.DEAFENED))
	assert_true(e.can_see(hero, e.get_combatant("gob")), "through the ally's eyes")

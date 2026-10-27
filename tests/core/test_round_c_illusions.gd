extends TestCase
## Round C item 5: illusion combatants (decoys hostiles treat as real until
## an Investigation check), Mislead, Weird, and the Stealth-advantage
## disguises in and out of combat.

const SURE := {"name": "Sure", "kind": "melee", "to_hit": 100, "damage": "4", "damage_type": "slashing", "ability": "STR"}

var content: Dictionary


func before_each() -> void:
	content = CoreFixtures.content()
	for d: Dictionary in [
		{"id": "silent_image", "level": 1, "range_ft": 60, "concentration": true, "area": {"shape": "cube", "size_ft": 15}},
		{"id": "mislead", "level": 5, "range_ft": 0, "target": "self", "concentration": true},
		{"id": "weird", "level": 9, "range_ft": 120, "concentration": true, "area": {"shape": "sphere", "size_ft": 30}},
		{"id": "disguise_self", "level": 1, "range_ft": 0, "target": "self", "duration": "1 hour"},
		{"id": "alter_self", "level": 2, "range_ft": 0, "target": "self", "concentration": true},
		{"id": "minor_illusion", "level": 0, "range_ft": 30},
		{"id": "hallucinatory_terrain", "level": 4, "casting_time": "10_minutes", "range_ft": 300},
	]:
		var base := {"display_name": str(d["id"]).capitalize(), "effect": {"type": "unsupported"}}
		base.merge(d, true)
		var sdef := CoreFixtures.spell(base)
		assert_not_null(sdef, str(d["id"]))
		content["spells"][sdef.id] = sdef
	var ogre := {"schema_version": 1, "id": "ogre", "display_name": "Ogre", "armor_class": 11, "hit_points": 59, "hit_dice": "7d10+21", "speed": 40,
		"abilities": {"STR": 19, "DEX": 8, "CON": 16, "INT": 5, "WIS": 7, "CHA": 7}, "challenge_rating": 2.0, "xp": 450,
		"attacks": [{"name": "Club", "kind": "melee", "to_hit": 6, "damage": "2d8+4", "damage_type": "bludgeoning"}], "size": "large"}
	content["monsters"]["ogre"] = MonsterDefinition.from_dict(ogre)


func _evs(res: Dictionary) -> Array:
	var evs: Array = res.get("events", [])
	return evs


func _caster(prepared: Array[String]) -> CharacterSheet:
	var s := CoreFixtures.caster("Mage", Ability.Type.INT, prepared, 80)
	s.abilities.set_score(Ability.Type.INT, 30)
	s.spell_slots_max = [4, 3, 3, 3, 3, 2, 2, 1, 1]
	s.spell_slots = [4, 3, 3, 3, 3, 2, 2, 1, 1]
	return s


func _fight(hero: CharacterSheet, gob_int: int = 1) -> Encounter:
	var gob := CoreFixtures.sheet("Gob", 200, [10, 10, 10, gob_int, 1, 1])
	var e := CoreFixtures.duel(hero, [SURE], {"gob": [gob, Vector2i(9, 3), [SURE]]}, content)
	assert_not_null(e)
	return e


func _illusion(e: Encounter) -> Combatant:
	for c in e.combatants():
		if not c.illusion.is_empty():
			return c
	return null


func test_silent_image_fools_a_dull_foe() -> void:
	var e := _fight(_caster(["silent_image"]))
	var res := e.submit(CoreFixtures.intent("cast", "hero", {"spell": "silent_image", "point": [8, 3], "form": "ogre"}))
	assert_true(res["ok"] == true, str(res["error"]))
	var image := _illusion(e)
	assert_eq(image.display_name, "Ogre", "it looks like an ogre")
	assert_true(CoreFixtures.first_event(_evs(res), "combatant_joined")["illusion"] == true)
	assert_eq(image.adjust_damage(30, "fire", true), 0)
	e.end_turn()
	var plan := MonsterBrain.decide(e, "gob")
	var attacks_image := false
	for intent in plan:
		if str(intent["type"]) == "attack" and str(intent["target"]) == image.id:
			attacks_image = true
	assert_true(attacks_image, "the goblin swings at the ogre next to it")
	res = e.submit(CoreFixtures.intent("attack", "gob", {"target": image.id, "attack_index": 0}))
	assert_true(res["ok"] == true, str(res["error"]))
	var check := CoreFixtures.first_event(_evs(res), "check")
	assert_eq(check["reason"], "illusion")
	assert_eq(CoreFixtures.first_event(_evs(res), "attack_lost")["reason"], "illusion", "INT 1 misses the trick")
	assert_true(CoreFixtures.events_of(_evs(res), "damage").is_empty())


func test_a_sharp_mind_disbelieves() -> void:
	var e := _fight(_caster(["silent_image"]), 30)
	e.submit(CoreFixtures.intent("cast", "hero", {"spell": "silent_image", "point": [8, 3]}))
	var image := _illusion(e)
	e.get_combatant("gob").sheet.skill_bonuses[Skill.Type.INVESTIGATION] = 50
	e.end_turn()
	var res := e.submit(CoreFixtures.intent("attack", "gob", {"target": image.id, "attack_index": 0}))
	assert_eq(CoreFixtures.first_event(_evs(res), "disbelieved")["illusion"], image.id)
	assert_eq(CoreFixtures.first_event(_evs(res), "summon_ended")["reason"], "disbelieved")
	assert_null(e.get_combatant(image.id))


func test_witch_sight_sees_through_and_mislead_hides_the_caster() -> void:
	var e := _fight(_caster(["mislead"]))
	var res := e.submit(CoreFixtures.intent("cast", "hero", {"spell": "mislead"}))
	assert_true(res["ok"] == true, str(res["error"]))
	var hero := e.get_combatant("hero")
	assert_true(hero.is_invisible())
	var image := _illusion(e)
	assert_eq(image.display_name, hero.display_name, "a double of the caster")
	var gob := e.get_combatant("gob")
	gob.sheet.invocations.append("witch_sight")
	gob.position = image.position + Vector2i(1, 0)
	e._illusion_interaction(gob, image)
	assert_true(CoreFixtures.kinds(e.events).has("disbelieved"))
	assert_false(CoreFixtures.kinds(e.events).has("check") and CoreFixtures.events_of(e.events, "check").back()["reason"] == "illusion", "no check needed")


func test_weird_frightens_and_harms_each_turn() -> void:
	var e := _fight(_caster(["weird"]))
	var res := e.submit(CoreFixtures.intent("cast", "hero", {"spell": "weird", "point": [9, 3]}))
	assert_true(res["ok"] == true, str(res["error"]))
	var gob := e.get_combatant("gob")
	assert_true(gob.has_condition(Conditions.FRIGHTENED))
	assert_true(gob.has_buff("weird_dot"))
	assert_false(e.get_combatant("hero").has_condition(Conditions.FRIGHTENED), "only hostiles")


func test_disguises_give_one_stealth_advantage() -> void:
	var s := _caster(["disguise_self", "hallucinatory_terrain"])
	var r := OutOfCombat.cast(s, "hallucinatory_terrain", content, Rng.new(1))
	assert_true(r["ok"] == true, str(r["error"]))
	assert_eq(s.lingering[0]["kind"], "stealth")
	var e := _fight(s)
	var hero := e.get_combatant("hero")
	assert_true(hero.buff_flag("stealth_advantage"), "the terrain hides the party's approach")
	var res := e.submit(CoreFixtures.intent("hide", "hero"))
	assert_eq(CoreFixtures.first_event(_evs(res), "check")["advantage"], "advantage")
	assert_false(hero.buff_flag("stealth_advantage"), "used up")
	e.end_turn()
	e.end_turn()
	res = e.submit(CoreFixtures.intent("cast", "hero", {"spell": "disguise_self"}))
	assert_true(res["ok"] == true, str(res["error"]))
	assert_true(hero.buff_flag("stealth_advantage"))


func test_alter_self_natural_weapons_and_minor_illusion_cover() -> void:
	var s := _caster(["alter_self", "minor_illusion"])
	var e := CoreFixtures.duel(s, [], {"gob": [CoreFixtures.sheet("Gob", 200, [1, 1, 1, 1, 1, 1]), Vector2i(4, 3), [SURE]]}, content)
	var hero := e.get_combatant("hero")
	e.submit(CoreFixtures.intent("cast", "hero", {"spell": "alter_self"}))
	hero.action_used = false
	var unarmed := hero.attacks.size() - 1
	var res := e.submit(CoreFixtures.intent("attack", "hero", {"target": "gob", "attack_index": unarmed}))
	assert_true(res["ok"] == true, str(res["error"]))
	var dmg := CoreFixtures.first_event(_evs(res), "damage")
	if not dmg.is_empty():
		assert_in_range(dmg["amount"], 1, 6, "1d6 + 0")
	e.end_turn()
	e.end_turn()
	res = e.submit(CoreFixtures.intent("cast", "hero", {"spell": "minor_illusion", "point": [2, 3]}))
	assert_true(res["ok"] == true, str(res["error"]))
	assert_true(e._tile_obscured(Vector2i(2, 3)), "a crate to hide behind")

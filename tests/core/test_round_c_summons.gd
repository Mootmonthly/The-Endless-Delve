extends TestCase
## Round C item 4: conjurations as companions lasting encounters (with
## concentration), animate objects, giant insect, faithful hound, unseen
## servant, planar ally / binding, simulacrum, awaken, reincarnate, gate.

const SURE := {"name": "Sure", "kind": "melee", "to_hit": 100, "damage": "4", "damage_type": "slashing", "ability": "STR"}

var content: Dictionary


func before_each() -> void:
	content = CoreFixtures.content()
	for d: Dictionary in [
		{"id": "conjure_elemental", "level": 5, "casting_time": "1_minute", "range_ft": 90, "concentration": true, "duration": "up to 1 hour"},
		{"id": "conjure_minor_elementals", "level": 4, "casting_time": "1_minute", "range_ft": 90, "concentration": true, "duration": "up to 1 hour"},
		{"id": "animate_objects", "level": 5, "range_ft": 120, "concentration": true},
		{"id": "giant_insect", "level": 4, "range_ft": 30, "concentration": true},
		{"id": "faithful_hound", "level": 4, "range_ft": 30},
		{"id": "unseen_servant", "level": 1, "range_ft": 60, "ritual": true, "duration": "1 hour"},
		{"id": "planar_binding", "level": 5, "casting_time": "1_hour", "range_ft": 60},
		{"id": "simulacrum", "level": 7, "casting_time": "12_hours", "range_ft": 5},
		{"id": "awaken", "level": 5, "casting_time": "8_hours", "range_ft": 5},
		{"id": "reincarnate", "level": 5, "casting_time": "1_hour", "range_ft": 5},
		{"id": "gate", "level": 9, "range_ft": 60, "concentration": true},
		{"id": "phantom_steed", "level": 3, "casting_time": "1_minute", "range_ft": 30, "ritual": true, "duration": "1 hour"},
	]:
		var base := {"display_name": str(d["id"]).capitalize(), "effect": {"type": "unsupported"}}
		base.merge(d, true)
		var sdef := CoreFixtures.spell(base)
		assert_not_null(sdef, str(d["id"]))
		content["spells"][sdef.id] = sdef
	for d: Dictionary in [
		{"id": "air_elemental", "display_name": "Air Elemental", "creature_type": "elemental", "challenge_rating": 5.0, "hit_points": 90, "hit_dice": "12d10+24"},
		{"id": "efreeti", "display_name": "Efreeti", "creature_type": "elemental", "challenge_rating": 11.0, "hit_points": 200, "hit_dice": "16d10+112"},
		{"id": "magma_mephit", "display_name": "Magma Mephit", "creature_type": "elemental", "challenge_rating": 0.5, "hit_points": 22, "hit_dice": "5d6+5"},
		{"id": "giant_spider", "display_name": "Giant Spider", "creature_type": "beast", "challenge_rating": 1.0, "hit_points": 26, "hit_dice": "4d10+4"},
		{"id": "couatl", "display_name": "Couatl", "creature_type": "celestial", "challenge_rating": 4.0, "hit_points": 97, "hit_dice": "13d8+39"},
		{"id": "awakened_tree", "display_name": "Awakened Tree", "creature_type": "plant", "challenge_rating": 2.0, "hit_points": 59, "hit_dice": "7d12+14"},
	]:
		var base := {"schema_version": 1, "armor_class": 12, "speed": 30, "abilities": {"STR": 14, "DEX": 10, "CON": 12, "INT": 6, "WIS": 10, "CHA": 6},
			"xp": 10, "attacks": [{"name": "Hit", "kind": "melee", "to_hit": 100, "damage": "5", "damage_type": "bludgeoning"}]}
		base.merge(d, true)
		content["monsters"][str(d["id"])] = MonsterDefinition.from_dict(base)
	for d: Dictionary in [
		{"id": "human", "display_name": "Human", "speed": 30, "size": "medium", "ability_bonuses": {"STR": 1}},
		{"id": "lightfoot_halfling", "display_name": "Halfling", "speed": 25, "size": "small", "ability_bonuses": {"DEX": 2}},
	]:
		content["ancestries"][str(d["id"])] = AncestryDefinition.from_dict(d)


func _evs(res: Dictionary) -> Array:
	var evs: Array = res.get("events", [])
	return evs


func _caster(prepared: Array[String]) -> CharacterSheet:
	var s := CoreFixtures.caster("Mage", Ability.Type.INT, prepared, 80)
	s.abilities.set_score(Ability.Type.INT, 30)
	s.abilities.set_score(Ability.Type.CON, 30)
	s.class_id = "wizard"
	s.level = 17
	s.spell_slots_max = [4, 3, 3, 3, 3, 2, 2, 1, 1]
	s.spell_slots = [4, 3, 3, 3, 3, 2, 2, 1, 1]
	return s


func _fight(hero: CharacterSheet, foe_hp: int = 300) -> Encounter:
	var e := CoreFixtures.duel(hero, [SURE], {"gob": [CoreFixtures.sheet("Gob", foe_hp, [1, 1, 1, 1, 1, 1]), Vector2i(9, 3), [SURE]]}, content)
	assert_not_null(e)
	return e


func _summons(e: Encounter) -> Array[Combatant]:
	var out: Array[Combatant] = []
	for c in e.combatants():
		if c.is_summon():
			out.append(c)
	return out


func test_conjure_elemental_is_a_concentration_companion_for_two_encounters() -> void:
	var s := _caster(["conjure_elemental"])
	assert_false(OutOfCombat.cast(s, "conjure_elemental", content, Rng.new(1), [], {"form": "efreeti"})["ok"] == true, "CR 11 is too much")
	var r := OutOfCombat.cast(s, "conjure_elemental", content, Rng.new(1), [], {"form": "air_elemental"})
	assert_true(r["ok"] == true, str(r["error"]))
	var entry: Dictionary = s.companions[0]
	assert_eq([entry["monster"], entry["encounters_left"], entry["concentration"]], ["air_elemental", 2, true])
	var e := _fight(s, 5)
	var hero := e.get_combatant("hero")
	assert_eq(hero.concentration["spell"], "conjure_elemental", "the caster concentrates when the fight starts")
	assert_eq(_summons(e).size(), 1)
	e.submit(CoreFixtures.intent("end_turn", "hero"))
	while e.state == Encounter.State.ACTIVE:
		e._deal_effect_damage(null, e.get_combatant("gob"), 99, "fire", {})
		e.check_end()
	var after := hero.sheet
	assert_eq(after.companions.size(), 1)
	assert_eq(after.companions[0]["encounters_left"], 1)
	var e2 := _fight(after)
	var hero2 := e2.get_combatant("hero")
	e2._end_concentration(hero2, "damage")
	assert_true(_summons(e2).is_empty(), "concentration ends it")
	e2._end_encounter(0)
	assert_true(hero2.sheet.companions.is_empty(), "and it leaves the sheet")


func test_minor_elementals_count_by_cr_and_slot() -> void:
	var s := _caster(["conjure_minor_elementals"])
	var r := OutOfCombat.cast(s, "conjure_minor_elementals", content, Rng.new(1), [], {"form": "magma_mephit", "slot_level": 6})
	assert_true(r["ok"] == true, str(r["error"]))
	assert_eq(r["result"]["companions"], 8, "four CR 1/2 elementals, doubled at 6th level")


func test_animate_objects_giant_insect_and_hound() -> void:
	var e := _fight(_caster(["animate_objects", "giant_insect", "faithful_hound"]))
	var res := e.submit(CoreFixtures.intent("cast", "hero", {"spell": "animate_objects", "point": [5, 5]}))
	assert_true(res["ok"] == true, str(res["error"]))
	assert_eq(CoreFixtures.events_of(_evs(res), "summoned").size(), 10)
	var obj := _summons(e)[0]
	assert_eq([obj.sheet.max_hp, obj.armor_class(), obj.attacks[0]["to_hit"]], [20, 18, 8])
	assert_false(obj.untargetable)
	e.end_turn()
	e.end_turn()
	res = e.submit(CoreFixtures.intent("cast", "hero", {"spell": "giant_insect", "form": "giant_spider"}))
	assert_true(res["ok"] == true, str(res["error"]))
	assert_eq(CoreFixtures.events_of(_evs(res), "summoned").size(), 3, "three spiders (and the objects are gone)")
	e.end_turn()
	e.end_turn()
	res = e.submit(CoreFixtures.intent("cast", "hero", {"spell": "faithful_hound", "point": [8, 3]}))
	var hound := e.get_combatant(str(CoreFixtures.first_event(_evs(res), "summoned")["id"]))
	assert_true(hound.untargetable)
	assert_eq([hound.speed_tiles(), hound.attacks[0]["damage"]], [0, "4d8"])


func test_unseen_servant_helps_and_lingers_as_a_companion() -> void:
	var s := _caster(["unseen_servant"])
	var r := OutOfCombat.cast(s, "unseen_servant", content, Rng.new(1), [], {"ritual": true})
	assert_true(r["ok"] == true, str(r["error"]))
	assert_eq(s.companions[0]["custom"], "unseen_servant")
	var e := _fight(s)
	var servant := _summons(e)[0]
	assert_true(servant.familiar, "it only helps")
	assert_eq(servant.display_name, "Unseen Servant")


func test_simulacrum_awaken_and_planar_binding() -> void:
	var s := _caster(["simulacrum", "awaken", "planar_binding"])
	var r := OutOfCombat.cast(s, "simulacrum", content, Rng.new(1))
	assert_true(r["ok"] == true, str(r["error"]))
	assert_eq(s.companions[0]["hp"], 40, "half the caster's hit points")
	assert_true(OutOfCombat.cast(s, "awaken", content, Rng.new(1), [], {"form": "awakened_tree"})["ok"] == true)
	assert_true(OutOfCombat.cast(s, "planar_binding", content, Rng.new(1), [], {"form": "couatl"})["ok"] == true)
	assert_true(s.companions[2]["until_long_rest"] == true)
	var e := _fight(s)
	var names: Array = []
	for c in _summons(e):
		names.append(c.display_name)
	assert_eq(names, ["Mage (simulacrum)", "Awakened Tree", "Couatl"])
	assert_eq(_summons(e)[0].sheet.max_hp, 40)


func test_reincarnate_picks_a_new_ancestry() -> void:
	var s := _caster(["reincarnate"])
	var dead := CoreFixtures.sheet("Fallen", 20)
	dead.ancestry_id = "human"
	dead.kill()
	var targets: Array[CharacterSheet] = [dead]
	var r := OutOfCombat.cast(s, "reincarnate", content, Rng.new(2), targets, {"target_ids": ["p2"]})
	assert_true(r["ok"] == true, str(r["error"]))
	assert_true(dead.is_conscious())
	assert_eq(dead.current_hp, dead.max_hp)
	var ev := CoreFixtures.first_event(r["events"], "revived")
	assert_has(["human", "lightfoot_halfling"], ev["ancestry"])
	assert_eq(dead.ancestry_id, str(ev["ancestry"]))


func test_gate_and_phantom_steed() -> void:
	var e := _fight(_caster(["gate"]))
	var res := e.submit(CoreFixtures.intent("cast", "hero", {"spell": "gate", "form": "couatl"}))
	assert_true(res["ok"] == true, str(res["error"]))
	assert_eq(CoreFixtures.first_event(_evs(res), "summoned")["monster"], "couatl")
	var s := _caster(["phantom_steed"])
	var r := OutOfCombat.cast(s, "phantom_steed", content, Rng.new(1), [], {"ritual": true})
	assert_true(r["ok"] == true, str(r["error"]))
	var e2 := _fight(s)
	assert_eq(e2.get_combatant("hero").speed_tiles(), 12, "30 ft + 30 ft")

extends TestCase
## Spell effects added in round B (SpellEffects overrides): buffs and debuffs,
## conditions, sleep, revive, dispel, thresholds, polymorph, damage over time,
## sustained spells, metamagic, Mystic Arcanum and invocation spells.

const SURE := {"name": "Sure", "kind": "melee", "to_hit": 100, "damage": "4", "damage_type": "slashing", "ability": "STR"}
const WEAK := {"name": "Weak", "kind": "melee", "to_hit": -100, "damage": "4", "damage_type": "slashing", "ability": "STR"}

var content: Dictionary


func before_each() -> void:
	content = CoreFixtures.content()
	for d: Dictionary in [
		{"id": "bless", "level": 1, "range_ft": 30, "concentration": true},
		{"id": "bane", "level": 1, "range_ft": 30, "concentration": true},
		{"id": "sleep", "level": 1, "range_ft": 90, "area": {"shape": "sphere", "size_ft": 20}},
		{"id": "haste", "level": 3, "range_ft": 30, "concentration": true},
		{"id": "slow", "level": 3, "range_ft": 120, "concentration": true, "area": {"shape": "cube", "size_ft": 40}},
		{"id": "revivify", "level": 3, "range_ft": 5},
		{"id": "dispel_magic", "level": 3, "range_ft": 120},
		{"id": "power_word_kill", "level": 9, "range_ft": 60},
		{"id": "polymorph", "level": 4, "range_ft": 60, "concentration": true},
		{"id": "call_lightning", "level": 3, "range_ft": 120, "concentration": true, "area": {"shape": "sphere", "size_ft": 5}},
		{"id": "phantasmal_killer", "level": 4, "range_ft": 120, "concentration": true},
		{"id": "circle_of_death_x", "level": 6, "range_ft": 150, "area": {"shape": "sphere", "size_ft": 10},
			"effect": {"type": "area_save", "save": "CON", "damage": "8d6", "damage_type": "necrotic", "on_save": "half"}},
		{"id": "false_life", "level": 1, "range_ft": 0, "target": "self"},
		{"id": "death_ward", "level": 4, "range_ft": 5},
		{"id": "mirror_image", "level": 2, "range_ft": 0, "target": "self"},
		{"id": "sanctuary", "level": 1, "casting_time": "bonus_action", "range_ft": 30},
		{"id": "invisibility", "level": 2, "range_ft": 5, "concentration": true},
		{"id": "faerie_fire", "level": 1, "range_ft": 60, "concentration": true, "area": {"shape": "cube", "size_ft": 20}},
		{"id": "mass_healing_word", "level": 3, "casting_time": "bonus_action", "range_ft": 60, "heal_by_slot": {"3": "1d4+MOD"}},
	]:
		var base := {"display_name": str(d["id"]).capitalize(), "effect": {"type": "unsupported"}}
		base.merge(d, true)
		var sdef := CoreFixtures.spell(base)
		assert_not_null(sdef, str(d["id"]))
		content["spells"][sdef.id] = sdef
	for d: Dictionary in [
		{"id": "rat", "display_name": "Rat", "creature_type": "beast", "challenge_rating": 0.0, "hit_points": 1, "hit_dice": "1d4-1"},
		{"id": "brown_bear", "display_name": "Brown Bear", "creature_type": "beast", "challenge_rating": 1.0, "hit_points": 34, "hit_dice": "4d10+12"},
	]:
		var base := {"schema_version": 1, "armor_class": 10, "speed": 30, "abilities": {"STR": 2, "DEX": 11, "CON": 9, "INT": 2, "WIS": 10, "CHA": 4},
			"xp": 10, "attacks": [{"name": "Bite", "kind": "melee", "to_hit": 0, "damage": "1", "damage_type": "piercing"}]}
		base.merge(d, true)
		var m := MonsterDefinition.from_dict(base)
		content["monsters"][m.id] = m


func _evs(res: Dictionary) -> Array:
	var evs: Array = res.get("events", [])
	return evs


## A caster with DC 20 (score 30), slots 4 / 3 / 3 / 3 / 2 / 1 and the spells prepared.
func _caster(prepared: Array[String], ability: int = Ability.Type.WIS) -> CharacterSheet:
	var s := CoreFixtures.caster("Caster", ability, prepared, 60)
	s.abilities.set_score(ability, 30)
	s.spell_slots_max = [4, 3, 3, 3, 2, 1]
	s.spell_slots = [4, 3, 3, 3, 2, 1]
	return s


func _weak_gob(hp: int = 200) -> CharacterSheet:
	return CoreFixtures.sheet("Gob", hp, [1, 1, 1, 1, 1, 1])


func _fight(hero: CharacterSheet, foes: Dictionary = {}, allies: Dictionary = {}) -> Encounter:
	var f := foes if not foes.is_empty() else {"gob": [_weak_gob(), Vector2i(6, 3), [SURE]]}
	var e := CoreFixtures.duel(hero, [SURE], f, content, "hero", Vector2i(3, 3), allies)
	assert_not_null(e)
	return e


func _cast(e: Encounter, fields: Dictionary) -> Dictionary:
	return e.submit(CoreFixtures.intent("cast", "hero", fields))


func test_bless_and_bane_dice() -> void:
	var allies := {"ally": [CoreFixtures.sheet("Ally", 20), Vector2i(3, 4), [SURE]]}
	var e := _fight(_caster(["bless", "bane"]), {}, allies)
	var res := _cast(e, {"spell": "bless", "targets": ["hero", "ally"]})
	assert_true(res["ok"] == true, str(res["error"]))
	assert_eq(CoreFixtures.events_of(_evs(res), "effect_applied").size(), 2)
	assert_eq(CoreFixtures.first_event(_evs(res), "cast")["targets"], ["hero", "ally"])
	assert_true(e.get_combatant("ally").has_buff("bless"))
	var hero := e.get_combatant("hero")
	for _i in range(10):
		var b := e._d20_dice_bonus(hero, "attack_dice")
		assert_in_range(b, 1, 4)
	assert_true(str(_cast(e, {"spell": "bless", "targets": ["hero", "ally", "gob", "hero"]})["error"]).length() > 0)
	var e2 := _fight(_caster(["bane"]))
	res = _cast(e2, {"spell": "bane", "target": "gob"})
	assert_true(res["ok"] == true, str(res["error"]))
	var gob := e2.get_combatant("gob")
	assert_true(gob.has_buff("bane"), "CHA 1 fails DC 20")
	assert_in_range(e2._d20_dice_bonus(gob, "save_dice"), -4, -1)
	e2._end_concentration(e2.get_combatant("hero"), "test")
	assert_false(gob.has_buff("bane"), "concentration ends it")


func test_sleep_by_hit_point_pool() -> void:
	var foes := {"a": [CoreFixtures.sheet("A", 1), Vector2i(8, 3), [SURE]], "b": [CoreFixtures.sheet("B", 2), Vector2i(8, 4), [SURE]], "c": [CoreFixtures.sheet("C", 500), Vector2i(9, 3), [SURE]]}
	var e := _fight(_caster(["sleep"]), foes)
	var res := _cast(e, {"spell": "sleep", "point": [8, 3]})
	assert_true(res["ok"] == true, str(res["error"]))
	var area := CoreFixtures.first_event(_evs(res), "area_effect")
	assert_eq(area["affected"], ["a", "b", "c"], "lowest hit points first")
	assert_true(e.get_combatant("a").has_condition(Conditions.UNCONSCIOUS))
	assert_true(e.get_combatant("b").has_condition(Conditions.UNCONSCIOUS))
	assert_false(e.get_combatant("c").has_condition(Conditions.UNCONSCIOUS))
	assert_true(e.get_combatant("a").loses_turn())
	e._deal_effect_damage(null, e.get_combatant("c"), 1, "fire", {})
	e._after_damage(null, e.get_combatant("b"), 1, false)
	assert_false(e.get_combatant("b").has_condition(Conditions.UNCONSCIOUS), "damage wakes it")


func test_haste_and_slow() -> void:
	var e := _fight(_caster(["haste", "slow"]))
	var res := _cast(e, {"spell": "haste", "target": "hero"})
	assert_true(res["ok"] == true, str(res["error"]))
	var hero := e.get_combatant("hero")
	assert_eq(hero.armor_class(), 12)
	assert_eq(hero.speed_tiles(), 12)
	res = e.submit(CoreFixtures.intent("dash", "hero", {"haste": true}))
	assert_true(res["ok"] == true, str(res["error"]))
	assert_true(str(e.submit(CoreFixtures.intent("dash", "hero", {"haste": true}))["error"]).contains("hasted"))
	e._end_concentration(hero, "test")
	assert_true(hero.has_condition(Conditions.TURN_LOST), "lethargy")
	var e2 := _fight(_caster(["slow"]))
	res = _cast(e2, {"spell": "slow", "point": [6, 3]})
	var gob := e2.get_combatant("gob")
	assert_true(gob.has_buff("slow"))
	assert_eq(gob.armor_class(), 3, "AC 5 - 2")
	assert_false(gob.can_react())
	e2.end_turn()
	assert_eq(gob.movement_remaining, 3, "half speed")
	assert_true(e2.submit(CoreFixtures.intent("dash", "gob"))["ok"] == true)
	assert_true(str(e2.submit(CoreFixtures.intent("use_feature", "gob", {"feature": "second_wind"}))["error"]).length() > 0)


func test_revivify_within_a_minute() -> void:
	var allies := {"ally": [CoreFixtures.sheet("Ally", 20), Vector2i(3, 4), [SURE]]}
	var e := _fight(_caster(["revivify"]), {}, allies)
	var ally := e.get_combatant("ally")
	e._take_damage(ally, 100)
	assert_true(ally.sheet.is_dead())
	var res := _cast(e, {"spell": "revivify", "target": "ally"})
	assert_true(res["ok"] == true, str(res["error"]))
	assert_eq(CoreFixtures.first_event(_evs(res), "revived")["hp_after"], 1)
	assert_true(ally.is_conscious())
	assert_true(str(_cast(e, {"spell": "revivify", "target": "hero"})["error"]).length() > 0, "not dead")


func test_dispel_magic_and_power_word_kill() -> void:
	var e := _fight(_caster(["dispel_magic", "bane", "power_word_kill"]))
	_cast(e, {"spell": "bane", "target": "gob"})
	e.end_turn()
	e.end_turn()
	var res := _cast(e, {"spell": "dispel_magic", "target": "gob"})
	assert_true(res["ok"] == true, str(res["error"]))
	assert_false(e.get_combatant("gob").has_buff("bane"))
	var pwk := _caster(["power_word_kill"])
	pwk.spell_slots_max = [0, 0, 0, 0, 0, 0, 0, 0, 1]
	pwk.spell_slots = [0, 0, 0, 0, 0, 0, 0, 0, 1]
	var e2 := _fight(pwk, {"gob": [_weak_gob(90), Vector2i(6, 3), [SURE]], "big": [_weak_gob(150), Vector2i(7, 3), [SURE]]})
	res = _cast(e2, {"spell": "power_word_kill", "target": "gob"})
	assert_true(res["ok"] == true, str(res["error"]))
	assert_eq(CoreFixtures.first_event(_evs(res), "destroyed")["feature"], "power_word_kill")
	assert_true(e2.get_combatant("gob").sheet.is_dead())


func test_polymorph_and_revert() -> void:
	var e := _fight(_caster(["polymorph"]), {"gob": [_weak_gob(40), Vector2i(6, 3), [SURE]]})
	var gob := e.get_combatant("gob")
	gob.challenge_rating = 2.0
	gob.monster_id = "gob"
	var res := _cast(e, {"spell": "polymorph", "target": "gob"})
	assert_true(res["ok"] == true, str(res["error"]))
	assert_eq(CoreFixtures.first_event(_evs(res), "transformed")["form"], "rat")
	assert_eq(gob.sheet.max_hp, 1)
	e._deal_effect_damage(null, gob, 5, "fire", {})
	assert_true(CoreFixtures.kinds(e.events).has("reverted"))
	assert_eq(gob.sheet.max_hp, 40)
	assert_eq(gob.sheet.current_hp, 36, "excess damage carries over")
	assert_true(e.get_combatant("hero").concentration.is_empty(), "the spell ends")


func test_phantasmal_killer_damage_over_time() -> void:
	var e := _fight(_caster(["phantasmal_killer"]))
	var res := _cast(e, {"spell": "phantasmal_killer", "target": "gob"})
	var gob := e.get_combatant("gob")
	assert_true(gob.has_condition(Conditions.FRIGHTENED))
	assert_true(gob.has_buff("phantasmal_killer_dot"))
	e.end_turn()
	res = e.submit(CoreFixtures.intent("end_turn", "gob"))
	var dmg := CoreFixtures.first_event(_evs(res), "damage")
	assert_eq(dmg["spell"], "phantasmal_killer")
	assert_true(dmg["over_time"])


func test_sustained_call_lightning() -> void:
	var e := _fight(_caster(["call_lightning"]))
	var res := _cast(e, {"spell": "call_lightning", "point": [6, 3]})
	assert_true(res["ok"] == true, str(res["error"]))
	var hero := e.get_combatant("hero")
	assert_eq(hero.sheet.slots_left(3), 2)
	e.end_turn()
	e.end_turn()
	res = _cast(e, {"spell": "call_lightning", "point": [6, 3], "sustain": true})
	assert_true(res["ok"] == true, str(res["error"]))
	assert_true(CoreFixtures.first_event(_evs(res), "cast")["sustain"])
	assert_eq(hero.sheet.slots_left(3), 2, "no new slot")
	assert_eq(str(hero.concentration["spell"]), "call_lightning")


func test_buff_spells_death_ward_mirror_image_sanctuary_invisibility() -> void:
	var e := _fight(_caster(["death_ward", "mirror_image", "sanctuary", "invisibility", "false_life"]))
	_cast(e, {"spell": "death_ward", "target": "hero"})
	var hero := e.get_combatant("hero")
	e._deal_effect_damage(null, hero, 500, "fire", {})
	assert_eq(hero.sheet.current_hp, 1, "Death Ward")
	assert_eq(CoreFixtures.first_event(e.events, "death_avoided")["feature"], "death_ward")
	e.end_turn()
	e.end_turn()
	var res := _cast(e, {"spell": "mirror_image"})
	assert_true(res["ok"] == true, str(res["error"]))
	assert_eq(DictUtil.to_int(hero.buffs[hero.buffs.size() - 1]["images"]), 3)
	var e2 := _fight(_caster(["sanctuary"]), {"gob": [CoreFixtures.sheet("Gob", 40, [10, 10, 10, 10, 1, 10]), Vector2i(4, 3), [SURE]]})
	res = _cast(e2, {"spell": "sanctuary", "target": "hero"})
	assert_true(res["ok"] == true, str(res["error"]))
	e2.end_turn()
	res = e2.submit(CoreFixtures.intent("attack", "gob", {"target": "hero", "attack_index": 0}))
	assert_eq(CoreFixtures.first_event(_evs(res), "attack_lost")["reason"], "sanctuary")
	var e3 := _fight(_caster(["invisibility", "false_life"]))
	_cast(e3, {"spell": "invisibility", "target": "hero"})
	assert_true(e3.get_combatant("hero").is_invisible())
	var s := _caster([])
	s.invocations = ["fiendish_vigor"]
	var e4 := _fight(s)
	res = _cast(e4, {"spell": "false_life"})
	assert_true(res["ok"] == true, str(res["error"]))
	assert_eq(res["events"][0]["slot_level"], 0, "Fiendish Vigor: no slot")
	assert_in_range(e4.get_combatant("hero").sheet.temp_hp, 5, 8)


func test_metamagic_careful_distant_extended_heightened() -> void:
	var s := _caster(["circle_of_death_x", "bane", "bless"], Ability.Type.CHA)
	s.features.append("font_of_magic")
	s.level = 12
	s.restore_class_resources()
	s.metamagic = ["careful_spell", "distant_spell", "extended_spell", "heightened_spell"]
	var allies := {"ally": [CoreFixtures.sheet("Ally", 200, [1, 1, 1, 1, 1, 1]), Vector2i(7, 3), [SURE]]}
	var e := _fight(s, {"gob": [_weak_gob(), Vector2i(8, 3), [SURE]]}, allies)
	var res := _cast(e, {"spell": "circle_of_death_x", "point": [8, 3], "metamagic": ["careful_spell"], "careful": ["ally"]})
	assert_true(res["ok"] == true, str(res["error"]))
	var saves := CoreFixtures.events_of(_evs(res), "save")
	var careful_save: Dictionary = saves[0] if saves[0]["target"] == "ally" else saves[1]
	assert_true(careful_save["careful"], "the ally succeeds automatically")
	assert_eq(e.get_combatant("hero").sheet.class_resource("sorcery_points"), 11)
	var e2 := _fight(s, {"gob": [_weak_gob(), Vector2i(11, 3), [SURE]]})
	assert_true(str(_cast(e2, {"spell": "bane", "target": "gob"})["error"]).contains("out of range"))
	res = _cast(e2, {"spell": "bane", "target": "gob", "metamagic": ["distant_spell"]})
	assert_true(res["ok"] == true, str(res["error"]))
	var e3 := _fight(s)
	res = _cast(e3, {"spell": "bless", "target": "hero", "metamagic": ["extended_spell"]})
	assert_eq(CoreFixtures.first_event(_evs(res), "effect_applied")["duration"], {"type": "rounds", "rounds": 20})
	var e4 := _fight(s)
	res = _cast(e4, {"spell": "bane", "target": "gob", "metamagic": ["heightened_spell"], "heightened_target": "gob"})
	assert_eq(CoreFixtures.first_event(_evs(res), "save")["advantage"], "disadvantage")
	assert_true(str(_cast(_fight(s), {"spell": "bane", "target": "gob", "metamagic": ["heightened_spell", "distant_spell"], "heightened_target": "gob"})["error"]).contains("one metamagic"))


func test_mystic_arcanum_and_invocation_spells() -> void:
	var s := CoreFixtures.caster("Lock", Ability.Type.CHA, ["fire_bolt"], 60)
	s.abilities.set_score(Ability.Type.CHA, 30)
	s.spell_slots_max = [0, 0, 0, 0, 2]
	s.spell_slots = [0, 0, 0, 0, 2]
	s.mystic_arcanum = ["circle_of_death_x"]
	s.invocations = ["thief_of_five_fates"]
	s.features.append("mystic_arcanum")
	s.restore_class_resources()
	assert_eq(s.class_resource("arcanum:circle_of_death_x"), 1)
	assert_eq(s.class_resource("invocation:thief_of_five_fates"), 1)
	var e := _fight(s, {"gob": [_weak_gob(), Vector2i(8, 3), [SURE]]})
	var res := _cast(e, {"spell": "circle_of_death_x", "point": [8, 3]})
	assert_true(res["ok"] == true, str(res["error"]))
	var hero := e.get_combatant("hero")
	assert_eq(hero.sheet.class_resource("arcanum:circle_of_death_x"), 0)
	assert_eq(hero.sheet.slots_left(5), 2, "no pact slot used")
	e.end_turn()
	e.end_turn()
	assert_true(str(_cast(e, {"spell": "circle_of_death_x", "point": [8, 3]})["error"]).length() > 0, "once per long rest")
	res = _cast(e, {"spell": "bane", "target": "gob"})
	assert_true(res["ok"] == true, str(res["error"]))
	assert_eq(hero.sheet.slots_left(5), 1, "Thief of Five Fates uses a warlock slot")
	assert_eq(hero.sheet.class_resource("invocation:thief_of_five_fates"), 0)
	Rest.long_rest(hero.sheet)
	assert_eq(hero.sheet.class_resource("arcanum:circle_of_death_x"), 1)


func test_faerie_fire_and_mass_healing_word() -> void:
	var e := _fight(_caster(["faerie_fire", "mass_healing_word"]))
	var res := _cast(e, {"spell": "faerie_fire", "point": [6, 3]})
	var gob := e.get_combatant("gob")
	assert_true(gob.has_buff("faerie_fire"))
	assert_eq(e._attack_mode(e.get_combatant("hero"), gob, SURE, true)["mode"], D20.RollMode.ADVANTAGE)
	e.end_turn()
	e.end_turn()
	var hero := e.get_combatant("hero")
	hero.sheet.current_hp = 10
	res = _cast(e, {"spell": "mass_healing_word", "targets": ["hero"]})
	assert_true(res["ok"] == true, str(res["error"]))
	assert_true(hero.sheet.current_hp > 10)


func test_overrides_cover_unsupported_data_spells() -> void:
	var spells := ContentLoader.load_spells()
	if spells.is_empty():
		return
	for id: String in ["bless", "hold_person", "web", "spiritual_weapon", "misty_step", "sleep", "revivify", "counterspell", "spirit_guardians"]:
		if spells.has(id):
			var sdef: SpellDefinition = spells[id]
			assert_true(sdef.is_supported() or sdef.effect_type == "reaction", "%s is modelled" % id)

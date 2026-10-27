extends TestCase
## Round C item 3: domination and the control intent, suggestion, compulsion,
## calm emotions, enthrall, banishment / maze / imprisonment / plane shift,
## transformations (true polymorph, shapechange, animal shapes, magic jar),
## gaseous form, blink, etherealness, lingering effects (antipathy).

const SURE := {"name": "Sure", "kind": "melee", "to_hit": 100, "damage": "4", "damage_type": "slashing", "ability": "STR"}

var content: Dictionary


func before_each() -> void:
	content = CoreFixtures.content()
	for d: Dictionary in [
		{"id": "dominate_person", "level": 5, "range_ft": 60, "concentration": true},
		{"id": "suggestion", "level": 2, "range_ft": 30, "concentration": true},
		{"id": "compulsion", "level": 4, "range_ft": 30, "concentration": true},
		{"id": "calm_emotions", "level": 2, "range_ft": 60, "concentration": true, "area": {"shape": "sphere", "size_ft": 20}},
		{"id": "enthrall", "level": 2, "range_ft": 60},
		{"id": "banishment", "level": 4, "range_ft": 60, "concentration": true},
		{"id": "maze", "level": 8, "range_ft": 60, "concentration": true},
		{"id": "imprisonment", "level": 9, "range_ft": 30, "casting_time": "1_minute"},
		{"id": "plane_shift", "level": 7, "range_ft": 5},
		{"id": "true_polymorph", "level": 9, "range_ft": 30, "concentration": true},
		{"id": "shapechange", "level": 9, "range_ft": 0, "target": "self", "concentration": true},
		{"id": "animal_shapes", "level": 8, "range_ft": 30, "concentration": true},
		{"id": "gaseous_form", "level": 3, "range_ft": 5, "concentration": true},
		{"id": "blink", "level": 3, "range_ft": 0, "target": "self"},
		{"id": "etherealness", "level": 7, "range_ft": 0, "target": "self"},
		{"id": "magic_jar", "level": 6, "range_ft": 0, "target": "self", "casting_time": "1_minute", "duration": "until dispelled"},
		{"id": "antipathy_sympathy", "level": 8, "range_ft": 60, "casting_time": "1_hour", "duration": "10 days"},
		{"id": "geas", "level": 5, "range_ft": 60, "casting_time": "1_minute"},
	]:
		var base := {"display_name": str(d["id"]).capitalize(), "effect": {"type": "unsupported"}}
		base.merge(d, true)
		var sdef := CoreFixtures.spell(base)
		assert_not_null(sdef, str(d["id"]))
		content["spells"][sdef.id] = sdef
	for d: Dictionary in [
		{"id": "rat", "display_name": "Rat", "creature_type": "beast", "challenge_rating": 0.0, "hit_points": 1, "hit_dice": "1d4-1"},
		{"id": "brown_bear", "display_name": "Brown Bear", "creature_type": "beast", "challenge_rating": 1.0, "hit_points": 34, "hit_dice": "4d10+12"},
		{"id": "ogre", "display_name": "Ogre", "creature_type": "giant", "challenge_rating": 2.0, "hit_points": 59, "hit_dice": "7d10+21"},
		{"id": "bandit", "display_name": "Bandit", "creature_type": "humanoid", "challenge_rating": 0.125, "hit_points": 11, "hit_dice": "2d8+2"},
	]:
		var base := {"schema_version": 1, "armor_class": 12, "speed": 30, "abilities": {"STR": 14, "DEX": 10, "CON": 12, "INT": 6, "WIS": 10, "CHA": 6},
			"xp": 10, "attacks": [{"name": "Hit", "kind": "melee", "to_hit": 100, "damage": "5", "damage_type": "bludgeoning"}]}
		base.merge(d, true)
		var m := MonsterDefinition.from_dict(base)
		content["monsters"][m.id] = m


func _evs(res: Dictionary) -> Array:
	var evs: Array = res.get("events", [])
	return evs


func _caster(prepared: Array[String]) -> CharacterSheet:
	var s := CoreFixtures.caster("Mage", Ability.Type.INT, prepared, 80)
	s.abilities.set_score(Ability.Type.INT, 30)
	s.level = 17
	s.spell_slots_max = [4, 3, 3, 3, 3, 2, 2, 1, 1]
	s.spell_slots = [4, 3, 3, 3, 3, 2, 2, 1, 1]
	return s


func _gob(hp: int = 200) -> CharacterSheet:
	return CoreFixtures.sheet("Gob", hp, [1, 1, 1, 1, 1, 1])


func _fight(hero: CharacterSheet, foes: Dictionary = {}, allies: Dictionary = {}) -> Encounter:
	var f := foes if not foes.is_empty() else {"gob": [_gob(), Vector2i(5, 3), [SURE]], "orc": [_gob(), Vector2i(9, 9), [SURE]]}
	var e := CoreFixtures.duel(hero, [SURE], f, content, "hero", Vector2i(3, 3), allies)
	assert_not_null(e)
	return e


func _cast(e: Encounter, fields: Dictionary, actor: String = "hero") -> Dictionary:
	var res := e.submit(CoreFixtures.intent("cast", actor, fields))
	assert_true(res["ok"] == true, "%s: %s" % [str(fields.get("spell", "")), str(res["error"])])
	return res


func _until(e: Encounter, id: String) -> void:
	for _i in range(40):
		if e.current_actor() == null or e.current_actor().id == id:
			return
		e.end_turn()


func test_dominate_person_switches_sides_and_takes_orders() -> void:
	var e := _fight(_caster(["dominate_person"]))
	var gob := e.get_combatant("gob")
	gob.creature_type = "humanoid"
	var res := _cast(e, {"spell": "dominate_person", "target": "gob"})
	var changed := CoreFixtures.first_event(_evs(res), "team_changed")
	assert_eq([changed["target"], changed["team"], changed["controlled_by"]], ["gob", Combatant.TEAM_PLAYERS, "hero"])
	assert_eq(e.state, Encounter.State.ACTIVE, "the orc still fights")
	assert_true(gob.auto_controlled)
	assert_true(str(e.submit(CoreFixtures.intent("control", "hero", {"target": "orc", "orders": []}))["error"]).contains("does not control"))
	res = e.submit(CoreFixtures.intent("control", "hero", {"target": "gob", "orders": [{"type": "dodge"}]}))
	assert_true(res["ok"] == true, str(res["error"]))
	assert_eq(CoreFixtures.first_event(_evs(res), "control")["orders"], 1)
	var start := e.events.size()
	e.end_turn()
	_until(e, "hero")
	var dodges := CoreFixtures.events_of(e.events_since(start), "dodge")
	assert_true(not dodges.is_empty() and dodges[0]["actor"] == "gob", "the order ran on the goblin's turn")
	# Damage lets it save again (WIS 1 against DC 20: it fails and stays).
	e._deal_effect_damage(null, gob, 1, "fire", {})
	assert_true(gob.has_condition(Conditions.DOMINATED))
	e._end_concentration(e.get_combatant("hero"), "damage")
	assert_eq(gob.team, Combatant.TEAM_MONSTERS, "concentration ends the domination")
	assert_eq(gob.controlled_by, "")


func test_suggestion_pacifies_toward_the_casters_side() -> void:
	var e := _fight(_caster(["suggestion"]))
	_cast(e, {"spell": "suggestion", "target": "gob"})
	_until(e, "gob")
	var gob := e.get_combatant("gob")
	assert_true(str(e.submit(CoreFixtures.intent("attack", "gob", {"target": "hero", "attack_index": 0}))["error"]).contains("suggestion"))
	for intent in MonsterBrain.decide(e, "gob"):
		assert_ne(str(intent["type"]), "attack", "it leaves the hero alone")
	e._deal_effect_damage(e.get_combatant("hero"), gob, 1, "fire", {})
	assert_false(gob.has_condition(Conditions.SUGGESTED), "damage breaks it")


func test_compulsion_moves_creatures_toward_the_point() -> void:
	var e := _fight(_caster(["compulsion"]), {"gob": [_gob(), Vector2i(5, 3), [SURE]], "orc": [_gob(), Vector2i(9, 9), [SURE]]})
	_cast(e, {"spell": "compulsion", "point": [5, 10]})
	var gob := e.get_combatant("gob")
	assert_true(gob.has_condition(Conditions.COMPELLED))
	assert_false(e.get_combatant("orc").has_condition(Conditions.COMPELLED), "out of the 30-ft radius")
	var start := e.events.size()
	_until(e, "gob")
	assert_false(CoreFixtures.events_of(e.events_since(start), "compelled").is_empty())
	assert_true(gob.position.y > 3, "it walked toward the point")
	_until(e, "hero")
	var res := _cast(e, {"spell": "compulsion", "point": [0, 0], "sustain": true})
	assert_eq(CoreFixtures.first_event(_evs(res), "redirected")["point"], [0, 0])


func test_calm_emotions_and_enthrall() -> void:
	var ally := CoreFixtures.sheet("Ally", 30)
	var e := _fight(_caster(["calm_emotions", "enthrall"]), {}, {"ally": [ally, Vector2i(4, 4)]})
	var a := e.get_combatant("ally")
	e._apply_condition(a, Conditions.FRIGHTENED, "gob", Conditions.duration(Conditions.DURATION_ENCOUNTER))
	_cast(e, {"spell": "calm_emotions", "point": [4, 3]})
	assert_false(a.has_condition(Conditions.FRIGHTENED), "allies are calmed without a save")
	assert_true(e.get_combatant("gob").has_condition(Conditions.SUGGESTED), "the goblin becomes indifferent")
	e.end_turn()
	_until(e, "hero")
	_cast(e, {"spell": "enthrall", "targets": ["gob"]})
	assert_true(e.get_combatant("gob").buff_list("disadv_checks").has("WIS"))
	var check := e.ability_check(e.get_combatant("gob"), Ability.Type.WIS, Skill.Type.PERCEPTION)
	assert_eq(CoreFixtures.events_of(e.events, "check").back()["advantage"], "disadvantage")
	assert_true(check.has("total"))


func test_banishment_returns_or_sends_home() -> void:
	var e := _fight(_caster(["banishment"]))
	var res := _cast(e, {"spell": "banishment", "target": "gob"})
	var gob := e.get_combatant("gob")
	assert_eq(CoreFixtures.first_event(_evs(res), "banished")["permanent"], false)
	assert_true(gob.untargetable and gob.loses_turn())
	assert_false(e.occupied_cells().has(Vector2i(5, 3)), "its tile is free")
	for _i in range(30):
		if not gob.banished.is_empty():
			e.end_turn()
	assert_eq(gob.position, Vector2i(5, 3), "back at its tile after 10 rounds")
	assert_false(gob.untargetable)
	assert_true(CoreFixtures.kinds(e.events).has("returned"))
	# A fiend held the full duration goes home for good.
	var e2 := _fight(_caster(["banishment"]))
	var fiend := e2.get_combatant("gob")
	fiend.creature_type = "fiend"
	fiend.monster_id = "imp"
	_cast(e2, {"spell": "banishment", "target": "gob"})
	for _i in range(30):
		if e2.state == Encounter.State.ACTIVE and fiend.banished.get("permanent", false) != true:
			e2.end_turn()
	assert_true(fiend.banished.get("permanent", false) == true)
	assert_false(fiend.is_in_fight())


func test_banishment_ends_with_concentration() -> void:
	var e := _fight(_caster(["banishment"]))
	_cast(e, {"spell": "banishment", "target": "gob"})
	e._end_concentration(e.get_combatant("hero"), "damage")
	var gob := e.get_combatant("gob")
	assert_true(gob.banished.is_empty())
	assert_eq(CoreFixtures.events_of(e.events, "returned")[0]["reason"], "concentration")


func test_maze_escape_and_imprisonment() -> void:
	var e := _fight(_caster(["maze"]))
	var gob := e.get_combatant("gob")
	gob.sheet.abilities.set_score(Ability.Type.INT, 30)
	_cast(e, {"spell": "maze", "target": "gob"})
	assert_false(gob.banished.is_empty())
	for _i in range(30):
		if not gob.banished.is_empty():
			e.end_turn()
	assert_true(gob.banished.is_empty(), "INT 30 escapes the maze")
	assert_eq(CoreFixtures.events_of(e.events, "returned")[0]["reason"], "escaped")
	var s := _caster(["imprisonment"])
	var r := OutOfCombat.cast(s, "imprisonment", content, Rng.new(1))
	assert_true(r["ok"] == true, str(r["error"]))
	assert_eq(CoreFixtures.first_event(r["events"], "no_effect")["spell"], "imprisonment", "a fight-only spell does nothing outside one")
	assert_eq(r["slot_level"], 0, "and costs no slot")
	var e2 := _fight(_caster(["imprisonment"]), {"gob": [_gob(), Vector2i(5, 3), [SURE]]})
	var gob2 := e2.get_combatant("gob")
	gob2.monster_id = "gob"
	e2._banish(gob2, "hero", "imprisonment", -1, true, {})
	assert_false(gob2.is_in_fight())
	assert_true(e2.check_end(), "a permanent banishment ends the fight")


func test_plane_shift_self_and_hostile() -> void:
	var e := _fight(_caster(["plane_shift"]), {"gob": [_gob(), Vector2i(4, 3), [SURE]], "orc": [_gob(), Vector2i(9, 9), [SURE]]})
	e.get_combatant("gob").monster_id = "gob"
	var res := _cast(e, {"spell": "plane_shift", "target": "gob"})
	assert_eq(CoreFixtures.first_event(_evs(res), "attack")["spell"], "plane_shift", "a melee spell attack first")
	var gob := e.get_combatant("gob")
	if CoreFixtures.first_event(_evs(res), "attack")["hit"] == true:
		assert_true(gob.banished.get("permanent", false) == true, "CHA 1 fails: gone for good")
	e.end_turn()
	_until(e, "hero")
	res = _cast(e, {"spell": "plane_shift", "target": "hero"})
	var hero := e.get_combatant("hero")
	assert_eq(CoreFixtures.first_event(_evs(res), "banished")["rounds"], 10)
	assert_false(hero.banished.get("permanent", true) == true)


func test_true_polymorph_shapechange_and_animal_shapes() -> void:
	var ally := CoreFixtures.sheet("Ally", 30)
	ally.level = 5
	var mage := _caster(["true_polymorph", "shapechange", "animal_shapes"])
	mage.spell_slots_max[8] = 2
	mage.spell_slots[8] = 2
	var e := _fight(mage, {}, {"ally": [ally, Vector2i(3, 4)]})
	var gob := e.get_combatant("gob")
	gob.challenge_rating = 3.0
	gob.monster_id = "gob"
	_cast(e, {"spell": "true_polymorph", "target": "gob", "form": "ogre"})
	assert_eq(gob.form["kind"], "true_polymorph", "any creature type")
	assert_eq(gob.sheet.max_hp, 59)
	e.end_turn()
	_until(e, "hero")
	var res := _cast(e, {"spell": "shapechange", "form": "ogre"})
	var hero := e.get_combatant("hero")
	assert_eq(hero.form["kind"], "shapechange")
	assert_true(CoreFixtures.first_event(_evs(res), "concentration_ended").size() > 0, "a new concentration spell ends the old one")
	assert_true(gob.form.is_empty(), "true polymorph ended with concentration")
	_until(e, "hero")
	assert_true(e.submit(CoreFixtures.intent("use_feature", "hero", {"feature": "revert_form"}))["ok"] == true, "shapechange can be dropped")
	e.end_turn()
	_until(e, "hero")
	_cast(e, {"spell": "animal_shapes", "targets": ["hero", "ally"], "form": "brown_bear"})
	assert_eq(e.get_combatant("ally").form["kind"], "animal_shapes")
	assert_eq(hero.form["monster"], "brown_bear")


func test_gaseous_form_blink_and_etherealness() -> void:
	var e := _fight(_caster(["gaseous_form", "blink", "etherealness"]))
	var hero := e.get_combatant("hero")
	_cast(e, {"spell": "gaseous_form", "target": "hero"})
	assert_eq(hero.speed_tiles(), 2, "10 ft")
	assert_eq(hero.fly_tiles(), 2)
	hero.action_used = false
	assert_true(str(e.submit(CoreFixtures.intent("attack", "hero", {"target": "gob", "attack_index": 0}))["error"]).contains("cannot attack"))
	e._end_concentration(hero, "damage")
	_cast(e, {"spell": "blink"})
	var vanished := false
	for _i in range(8):
		var start := e.events.size()
		_until(e, "orc")
		for ev in CoreFixtures.events_of(e.events_since(start), "blink"):
			if ev["vanished"] == true:
				vanished = true
				assert_true(hero.untargetable, "out of reach until its next turn")
		_until(e, "hero")
		assert_false(hero.is_ethereal(), "back at its turn start")
	assert_true(vanished, "11+ on a d20 within eight turns")
	_cast(e, {"spell": "etherealness"})
	assert_true(hero.is_ethereal() and hero.untargetable)
	hero.action_used = false
	assert_true(str(e.submit(CoreFixtures.intent("attack", "hero", {"target": "gob", "attack_index": 0}))["error"]).contains("Ethereal"))
	assert_true(e.submit(CoreFixtures.intent("use_feature", "hero", {"feature": "end_spell", "mode": "etherealness"}))["ok"] == true)
	assert_false(hero.is_ethereal())


func test_magic_jar_possesses_a_humanoid() -> void:
	var s := _caster(["magic_jar"])
	var r := OutOfCombat.cast(s, "magic_jar", content, Rng.new(1))
	assert_true(r["ok"] == true, str(r["error"]))
	assert_eq(s.lingering[0]["kind"], "feature")
	assert_eq(s.lingering[0]["encounters_left"], -1, "until dispelled: until the next long rest")
	var bandit := Combatant.from_monster("bandit", content["monsters"]["bandit"], Combatant.TEAM_MONSTERS, null)
	bandit.sheet.abilities.set_score(Ability.Type.CHA, 1)
	var e := _fight(s, {"bandit": [bandit.sheet, Vector2i(6, 3), [SURE]], "orc": [_gob(), Vector2i(9, 9), [SURE]]})
	var b := e.get_combatant("bandit")
	b.monster_id = "bandit"
	b.creature_type = "humanoid"
	var res := e.submit(CoreFixtures.intent("use_feature", "hero", {"feature": "magic_jar", "target": "bandit"}))
	assert_true(res["ok"] == true, str(res["error"]))
	var hero := e.get_combatant("hero")
	assert_eq(hero.form["kind"], "magic_jar")
	assert_eq(hero.position, Vector2i(6, 3), "the caster now wears the bandit's body")
	assert_true(b.untargetable and b.loses_turn())
	_until(e, "hero")
	assert_true(e.submit(CoreFixtures.intent("use_feature", "hero", {"feature": "revert_form"}))["ok"] == true)
	assert_true(b.banished.is_empty() and not b.untargetable, "the host's soul returns")
	Rest.long_rest(s)
	assert_true(s.lingering.is_empty())


func test_antipathy_lingers_into_the_next_fight() -> void:
	var s := _caster(["antipathy_sympathy", "geas"])
	var r := OutOfCombat.cast(s, "antipathy_sympathy", content, Rng.new(1), [], {"mode": "antipathy", "creature_type": "humanoid", "caster_id": "p1"})
	assert_true(r["ok"] == true, str(r["error"]))
	var added := CoreFixtures.first_event(r["events"], "lingering_added")
	assert_eq([added["spell"], added["lingering_kind"], added["encounters"]], ["antipathy_sympathy", "zone", -1])
	var g := OutOfCombat.cast(s, "geas", content, Rng.new(1))
	assert_eq(CoreFixtures.first_event(g["events"], "no_effect")["reason"].contains("command"), true)
	var e := _fight(s, {"gob": [_gob(), Vector2i(5, 3), [SURE]], "orc": [_gob(), Vector2i(9, 9), [SURE]]})
	e.get_combatant("gob").creature_type = "humanoid"
	assert_eq(e.tile_effects.size(), 1, "the ward is laid where the caster stands")
	assert_eq(e.tile_effects[0]["creature_types"], ["humanoid"] as Array[String])
	_until(e, "gob")
	assert_true(e.get_combatant("gob").has_condition(Conditions.FRIGHTENED), "a humanoid inside fails its WIS save")
	assert_false(e.get_combatant("orc").has_condition(Conditions.FRIGHTENED))


func test_lingering_counts_down_per_encounter() -> void:
	var s := _caster([])
	s.lingering = [{"spell": "x_buff", "kind": "buff", "effect": "x_buff", "modifiers": {"ac": 1}, "encounters_left": 1}]
	var e := _fight(s, {"gob": [_gob(5), Vector2i(4, 3), [SURE]]})
	var hero := e.get_combatant("hero")
	assert_true(hero.has_buff("x_buff"))
	assert_eq(hero.armor_class(), hero.sheet.armor_class() + 1)
	e.submit(CoreFixtures.intent("attack", "hero", {"target": "gob", "attack_index": 0}))
	e.submit(CoreFixtures.intent("attack", "hero", {"target": "gob", "attack_index": 0}))
	_until(e, "hero")
	for _i in range(5):
		if e.state == Encounter.State.ACTIVE:
			e._deal_effect_damage(null, e.get_combatant("gob"), 99, "fire", {})
			e.check_end()
	assert_true(hero.sheet.lingering.is_empty(), "used up")
	assert_true(CoreFixtures.kinds(e.events).has("lingering_ended"))


func test_prismatic_violet_banishes_on_a_failed_second_save() -> void:
	var e := _fight(_caster([]))
	var gob := e.get_combatant("gob")
	gob.monster_id = "gob"
	e._prismatic_layer("hero", gob, "violet", 30, "prismatic_wall", 0)
	assert_true(gob.has_condition(Conditions.BLINDED))
	_until(e, "gob")
	_until(e, "hero")
	assert_false(gob.has_condition(Conditions.BLINDED))
	assert_true(gob.banished.get("permanent", false) == true, "WIS 1 fails: another plane")

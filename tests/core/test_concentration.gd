extends TestCase
## Concentration: one spell at a time, CON saves on damage, ends at 0 hp and on
## incapacitation; the effects it maintains end with it.

const HIT := {"name": "Hit", "kind": "melee", "to_hit": 100, "damage": "4", "damage_type": "slashing", "ability": "STR"}
const BIG := {"name": "Big", "kind": "melee", "to_hit": 100, "damage": "30", "damage_type": "slashing", "ability": "STR"}

var content: Dictionary


func before_each() -> void:
	content = CoreFixtures.content()


func _evs(res: Dictionary) -> Array:
	var evs: Array = res.get("events", [])
	return evs


func _caster() -> CharacterSheet:
	var s := CoreFixtures.caster("Warlock", Ability.Type.CHA, ["hold_person", "hex_c", "scare", "fire_bolt"])
	s.abilities.set_score(Ability.Type.CHA, 30)
	s.spell_slots_max = [4, 4]
	s.spell_slots = [4, 4]
	return s


func _fight(gob_attacks: Array = [HIT], caster_hp: int = 30) -> Encounter:
	var s := _caster()
	s.max_hp = caster_hp
	s.current_hp = caster_hp
	var gob := CoreFixtures.sheet("Gob", 60, [10, 1, 10, 10, 1, 10])
	var ogre := CoreFixtures.sheet("Ogre", 60, [10, 1, 10, 10, 1, 10])
	var e := CoreFixtures.duel(s, [HIT], {"gob": [gob, Vector2i(4, 3), gob_attacks], "ogre": [ogre, Vector2i(7, 6), [HIT]]}, content)
	assert_not_null(e)
	return e


func _cast(e: Encounter, spell: String, target: String, slot: int) -> Dictionary:
	return e.submit(CoreFixtures.intent("cast", "hero", {"spell": spell, "target": target, "slot_level": slot}))


func test_concentration_starts_and_a_second_spell_ends_the_first() -> void:
	var e := _fight()
	var res := _cast(e, "scare", "gob", 1)
	assert_true(res["ok"] == true, str(res["error"]))
	assert_has(_evs(res), {"kind": "concentration_started", "actor": "hero", "spell": "scare"})
	var hero := e.get_combatant("hero")
	assert_eq(hero.concentration, {"spell": "scare", "slot_level": 1})
	assert_true(e.get_combatant("gob").has_condition("frightened"))
	res = _cast(e, "hex_c", "ogre", 1)
	assert_true(res["ok"] == true, str(res["error"]))
	var kinds := CoreFixtures.kinds(_evs(res))
	assert_eq(kinds.slice(0, 4), ["cast", "concentration_ended", "condition_ended", "concentration_started"])
	assert_has(_evs(res), {"kind": "concentration_ended", "actor": "hero", "spell": "scare", "reason": "new_spell"})
	assert_false(e.get_combatant("gob").has_condition("frightened"), "the fear ends with concentration")
	assert_eq(e.get_combatant("ogre").marks["hero"]["spell"], "hex_c")


func test_damage_forces_a_con_save() -> void:
	var e := _fight()
	_cast(e, "hex_c", "gob", 1)
	e.end_turn()
	if e.current_actor().id != "gob":
		e.end_turn()
	var res := e.submit(CoreFixtures.intent("attack", "gob", {"target": "hero", "attack_index": 0}))
	var check := CoreFixtures.first_event(_evs(res), "concentration_check")
	if CoreFixtures.first_event(_evs(res), "attack")["hit"]:
		assert_eq(check["dc"], 10, "max(10, damage / 2)")
		assert_eq(check["spell"], "hex_c")
		assert_eq(check["total"], check["natural"])
		var hero := e.get_combatant("hero")
		assert_eq(hero.concentration.is_empty(), not check["success"])
		if not check["success"]:
			assert_false(e.get_combatant("gob").marks.has("hero"), "the hex mark ends")
			assert_has(_evs(res), {"kind": "effect_ended", "target": "gob", "effect": "hex"})


func test_big_hit_dc_and_dropping_to_zero() -> void:
	var e := _fight([BIG], 60)
	_cast(e, "hold_person", "ogre", 2)
	assert_true(e.get_combatant("ogre").has_condition("paralyzed"))
	e.end_turn()
	if e.current_actor().id != "gob":
		e.end_turn()
	var res := e.submit(CoreFixtures.intent("attack", "gob", {"target": "hero", "attack_index": 0}))
	if CoreFixtures.first_event(_evs(res), "attack")["hit"]:
		var amount: int = CoreFixtures.first_event(_evs(res), "damage")["amount"]
		assert_eq(CoreFixtures.first_event(_evs(res), "concentration_check")["dc"], maxi(10, floori(amount / 2.0)))
	var e2 := _fight([BIG], 20)
	_cast(e2, "hold_person", "ogre", 2)
	e2.end_turn()
	if e2.current_actor().id != "gob":
		e2.end_turn()
	res = e2.submit(CoreFixtures.intent("attack", "gob", {"target": "hero", "attack_index": 0}))
	if CoreFixtures.first_event(_evs(res), "attack")["hit"]:
		assert_has(_evs(res), {"kind": "concentration_ended", "actor": "hero", "spell": "hold_person", "reason": "unconscious"})
		assert_true(CoreFixtures.first_event(_evs(res), "concentration_check").is_empty(), "no save at 0 hp")
		assert_false(e2.get_combatant("ogre").has_condition("paralyzed"))


func test_incapacitation_ends_concentration() -> void:
	var e := _fight()
	_cast(e, "hex_c", "gob", 1)
	var before := e.events.size()
	e._apply_condition(e.get_combatant("hero"), "stunned", "gob", Conditions.duration("until_source_next_turn"))
	assert_has(e.events_since(before), {"kind": "concentration_ended", "actor": "hero", "spell": "hex_c", "reason": "incapacitated"})


func test_non_concentration_spells_do_not_touch_it() -> void:
	var e := _fight()
	_cast(e, "hex_c", "gob", 1)
	e.end_turn()
	while e.current_actor().id != "hero":
		e.end_turn()
	var res := _cast(e, "fire_bolt", "gob", 0)
	assert_true(res["ok"] == true, str(res["error"]))
	assert_false(CoreFixtures.kinds(_evs(res)).has("concentration_ended"))
	assert_eq(e.get_combatant("hero").concentration["spell"], "hex_c")


func test_rage_ends_concentration_and_blocks_casting() -> void:
	var s := _caster()
	s.features.append("rage")
	s.restore_class_resources()
	var e := CoreFixtures.duel(s, [HIT], {"gob": [CoreFixtures.sheet("Gob", 60), Vector2i(4, 3), [HIT]]}, content)
	assert_true(e.submit(CoreFixtures.intent("cast", "hero", {"spell": "hold_person", "target": "gob", "slot_level": 2}))["ok"] == true)
	var res := e.submit(CoreFixtures.intent("use_feature", "hero", {"feature": "rage"}))
	assert_true(res["ok"] == true, str(res["error"]))
	assert_has(_evs(res), {"kind": "concentration_ended", "actor": "hero", "spell": "hold_person", "reason": "rage"})
	assert_true(str(e.submit(CoreFixtures.intent("cast", "hero", {"spell": "fire_bolt", "target": "gob"}))["error"]).contains("raging"))

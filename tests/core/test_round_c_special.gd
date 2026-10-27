extends TestCase
## Round C item 6: special outcomes: Contagion (save-track diseases),
## Prismatic Spray (ray table), Flame Blade / Shillelagh (temporary weapon
## attacks), Wish (duplicate, restore slots, instant health, exhaustion),
## Time Stop (extra turns), Foresight (lingering buff). Real data spells.

const SURE := {"name": "Sure", "kind": "melee", "to_hit": 100, "damage": "4", "damage_type": "slashing", "ability": "STR"}
const STAFF := {"name": "Quarterstaff", "kind": "melee", "to_hit": 2, "damage": "1d6", "damage_type": "bludgeoning", "ability": "STR", "weapon_id": "quarterstaff"}
const SPELLS: Array[String] = ["contagion", "prismatic_spray", "flame_blade", "shillelagh", "wish", "time_stop", "foresight"]

var content: Dictionary


func before_each() -> void:
	content = CoreFixtures.content()
	for id in SPELLS:
		var sdef := SpellDefinition.from_dict(ContentLoader.load_json("res://data/spells/%s.json" % id))
		assert_not_null(sdef, id)
		content["spells"][id] = sdef


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


func _gob(hp: int = 200) -> CharacterSheet:
	return CoreFixtures.sheet("Gob", hp, [1, 1, 1, 1, 1, 1])


func _fight(hero: CharacterSheet, hero_attacks: Array[Dictionary] = [SURE], foes: Dictionary = {}) -> Encounter:
	var f := foes if not foes.is_empty() else {"gob": [_gob(), Vector2i(4, 3), [SURE]]}
	var e := CoreFixtures.duel(hero, hero_attacks, f, content)
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


func test_every_special_spell_is_castable() -> void:
	for id in SPELLS:
		var s: SpellDefinition = content["spells"][id]
		assert_true(s.is_supported(), "%s has a mechanic" % id)


func test_contagion_takes_hold_after_three_failed_saves() -> void:
	var e := _fight(_caster(["contagion"]))
	var res := _cast(e, {"spell": "contagion", "target": "gob", "mode": "filth_fever"})
	assert_true(CoreFixtures.first_event(_evs(res), "attack")["hit"] == true)
	var gob := e.get_combatant("gob")
	assert_true(gob.has_condition(Conditions.POISONED), "poisoned while the disease incubates")
	assert_true(CoreFixtures.events_of(_evs(res), "damage").is_empty(), "contagion deals no damage")
	var start := e.events.size()
	for _i in range(3):
		_until(e, "gob")
		_until(e, "hero")
	var ended := CoreFixtures.events_of(e.events_since(start), "save_track_ended")
	assert_eq(ended.size(), 1)
	assert_eq([ended[0]["outcome"], ended[0]["label"]], ["took_hold", "Filth Fever"])
	assert_false(gob.has_condition(Conditions.POISONED), "the poisoning gives way to the disease")
	assert_true(gob.buff_list("attack_disadvantage_abilities").has("STR"))
	assert_true(gob.buff_list("disadv_saves").has("STR"))


func test_contagion_ends_on_three_successes() -> void:
	var tough := _gob()
	tough.save_bonuses[Ability.Type.CON] = 40
	var e := _fight(_caster(["contagion"]), [SURE], {"gob": [tough, Vector2i(4, 3), [SURE]]})
	_cast(e, {"spell": "contagion", "target": "gob"})
	var start := e.events.size()
	for _i in range(4):
		_until(e, "gob")
		_until(e, "hero")
	var ended := CoreFixtures.events_of(e.events_since(start), "save_track_ended")
	assert_eq(ended.size(), 1)
	assert_eq(ended[0]["outcome"], "recovered")
	assert_false(e.get_combatant("gob").has_condition(Conditions.POISONED))


func test_prismatic_spray_rolls_a_ray_per_creature() -> void:
	var e := _fight(_caster(["prismatic_spray"]), [SURE], {"gob": [_gob(), Vector2i(5, 3), [SURE]], "orc": [_gob(), Vector2i(6, 4), [SURE]]})
	var res := _cast(e, {"spell": "prismatic_spray", "point": [8, 3]})
	var rays := CoreFixtures.events_of(_evs(res), "prismatic_ray")
	assert_true(rays.size() >= 2, "every creature in the cone gets a ray")
	for ray in rays:
		assert_has(["red", "orange", "yellow", "green", "blue", "indigo", "violet"], str(ray["layer"]))
		assert_in_range(int(ray["roll"]), 1, 8)


func test_flame_blade_adds_a_spell_attack_until_concentration_ends() -> void:
	var e := _fight(_caster(["flame_blade"]))
	var hero := e.get_combatant("hero")
	var before := hero.attacks.size()
	var res := _cast(e, {"spell": "flame_blade", "slot_level": 4})
	var applied: Dictionary = {}
	for ev in CoreFixtures.events_of(_evs(res), "effect_applied"):
		if ev.has("attack_index"):
			applied = ev
	assert_eq(applied.get("attack_index", -1), before)
	var blade: Dictionary = hero.attacks[before]
	assert_eq([blade["damage"], blade["damage_type"], blade["to_hit"]], ["4d6", "fire", hero.sheet.spell_attack_bonus()])
	res = e.submit(CoreFixtures.intent("attack", "hero", {"target": "gob", "attack_index": before}))
	assert_true(res["ok"] == true, str(res["error"]))
	assert_eq(hero.attacks_remaining, 0, "one blade attack per action")
	e._end_concentration(hero, "damage")
	assert_true(blade.get("disabled", false) == true, "the blade is gone with concentration")
	assert_eq(hero.attacks.size(), before + 1, "attack indexes stay stable")


func test_shillelagh_needs_a_staff_and_uses_the_casting_ability() -> void:
	var s := _caster(["shillelagh"])
	var e := _fight(s)
	assert_true(str(e.submit(CoreFixtures.intent("cast", "hero", {"spell": "shillelagh"}))["error"]).contains("quarterstaff"))
	e = _fight(s, [SURE, STAFF])
	var hero := e.get_combatant("hero")
	_cast(e, {"spell": "shillelagh"})
	var staff: Dictionary = hero.attacks[hero.attacks.size() - 1]
	assert_eq([staff["damage"], staff["to_hit"], staff["magical"]], ["1d8+10", 10 + hero.sheet.proficiency_bonus(), true])


func test_wish_restores_slots_and_strains_the_caster() -> void:
	var s := _caster(["wish"])
	s.spell_slots = [0, 0, 1, 3, 3, 2, 0, 0, 1]
	var e := _fight(s)
	var hero := e.get_combatant("hero")
	assert_true(str(e.submit(CoreFixtures.intent("cast", "hero", {"spell": "wish"}))["error"]).contains("mode"))
	var res := _cast(e, {"spell": "wish", "mode": "restore_slots"})
	assert_eq(CoreFixtures.first_event(_evs(res), "slots_restored")["levels"], [1, 2, 3, 7, 8])
	assert_eq(hero.sheet.spell_slots, [4, 3, 3, 3, 3, 2, 2, 1, 0], "the 9th-level slot is spent")
	assert_eq(hero.sheet.exhaustion, 1)


func test_wish_duplicates_a_spell_at_its_own_level() -> void:
	var e := _fight(_caster(["wish"]), [SURE], {"gob": [_gob(), Vector2i(8, 3), [SURE]]})
	assert_true(str(e.submit(CoreFixtures.intent("cast", "hero", {"spell": "wish", "mode": "time_stop"}))["error"]).contains("8th level"))
	var res := _cast(e, {"spell": "wish", "mode": "fireball", "point": [8, 3]})
	var cast := CoreFixtures.first_event(_evs(res), "cast")
	assert_eq([cast["spell"], cast["duplicate"], cast["slot_level"]], ["wish", "fireball", 9])
	assert_false(CoreFixtures.events_of(_evs(res), "area_effect").is_empty())
	assert_eq(CoreFixtures.first_event(_evs(res), "damage")["target"], "gob")
	assert_eq(e.get_combatant("hero").sheet.exhaustion, 0, "a duplicated spell carries no stress")


func test_wish_instant_health_heals_allies() -> void:
	var e := _fight(_caster(["wish"]))
	var hero := e.get_combatant("hero")
	hero.sheet.current_hp = 10
	_cast(e, {"spell": "wish", "mode": "instant_health"})
	assert_eq(hero.sheet.current_hp, hero.sheet.max_hp)
	assert_true(str(e.submit(CoreFixtures.intent("cast", "hero", {"spell": "wish", "mode": "instant_health", "targets": ["gob"]}))["error"]) != "")


func test_time_stop_grants_extra_turns_until_another_is_affected() -> void:
	var e := _fight(_caster(["time_stop"]))
	var res := _cast(e, {"spell": "time_stop"})
	var ts := CoreFixtures.first_event(_evs(res), "time_stop")
	assert_in_range(int(ts["turns"]), 2, 5)
	res = e.submit(CoreFixtures.intent("end_turn", "hero"))
	assert_false(CoreFixtures.events_of(_evs(res), "extra_turn").is_empty())
	assert_eq(e.current_actor().id, "hero", "the hero acts again")
	res = e.submit(CoreFixtures.intent("attack", "hero", {"target": "gob", "attack_index": 0}))
	assert_eq(CoreFixtures.first_event(_evs(res), "time_stop_ended")["reason"], "affected_other")
	res = e.submit(CoreFixtures.intent("end_turn", "hero"))
	assert_eq(e.current_actor().id, "gob", "time runs again")


func test_foresight_lingers_into_the_next_fight() -> void:
	var s := _caster(["foresight"])
	var r := OutOfCombat.cast(s, "foresight", content, Rng.new(1))
	assert_true(r["ok"] == true, str(r["error"]))
	assert_eq(CoreFixtures.first_event(r["events"], "lingering_added")["encounters"], 4)
	var e := _fight(s)
	var hero := e.get_combatant("hero")
	assert_true(hero.buff_flag("attack_advantage") and hero.buff_flag("attackers_disadvantage"))
	assert_true(hero.buff_list("adv_saves").has("DEX"))


func test_special_outcomes_replay_through_json() -> void:
	var s := _caster(["contagion", "wish", "time_stop", "flame_blade"])
	s.spell_slots_max[8] = 2
	s.spell_slots[8] = 2
	var e := _fight(s, [SURE], {"gob": [_gob(), Vector2i(4, 3), [SURE]]})
	_cast(e, {"spell": "time_stop"})
	e.submit(CoreFixtures.intent("end_turn", "hero"))
	_cast(e, {"spell": "flame_blade"})
	_cast(e, {"spell": "contagion", "target": "gob", "mode": "mindfire"})
	for _i in range(3):
		_until(e, "gob")
		_until(e, "hero")
	_cast(e, {"spell": "wish", "mode": "restore_slots"})
	var setup: Array[Dictionary] = []
	for d in e.setup_snapshot():
		setup.append(JSON.parse_string(JSON.stringify(d)))
	var entries: Array[Dictionary] = []
	for d in e.intent_log:
		entries.append(JSON.parse_string(JSON.stringify(d)))
	var m := WalkMap.new(12, 12, true)
	m.set_walkable(Vector2i(6, 6), false)
	var again := Encounter.replay(e.rng_seed, m, e.region, setup, entries, "t", content)
	assert_eq(JSON.stringify(again.events), JSON.stringify(e.events))

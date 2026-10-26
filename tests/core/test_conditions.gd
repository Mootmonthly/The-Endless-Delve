extends TestCase
## Conditions framework: attack modes, saves, movement, turn skipping,
## durations, immunities, charm, stand, cures; spells that apply conditions.

const HIT := {"name": "Hit", "kind": "melee", "to_hit": 100, "damage": "1", "damage_type": "slashing", "ability": "STR"}
const BOW := {"name": "Bow", "kind": "ranged", "to_hit": 100, "damage": "1", "damage_type": "piercing", "range_tiles": [16, 64]}

var content: Dictionary


func before_each() -> void:
	content = CoreFixtures.content()


func _evs(res: Dictionary) -> Array:
	var evs: Array = res.get("events", [])
	return evs


## hero at (3,3) vs gob at gob_pos; hero acts first.
func _duel(gob_pos: Vector2i = Vector2i(4, 3), hero: CharacterSheet = null, hero_attacks: Array[Dictionary] = [HIT], gob: CharacterSheet = null) -> Encounter:
	var h := hero if hero != null else CoreFixtures.sheet("Hero", 40)
	var g := gob if gob != null else CoreFixtures.sheet("Gob", 40)
	var e := CoreFixtures.duel(h, hero_attacks, {"gob": [g, gob_pos, [HIT, BOW]]}, content)
	assert_not_null(e)
	return e


func _attack(e: Encounter, actor: String, target: String, index: int = 0) -> Dictionary:
	return e.submit(CoreFixtures.intent("attack", actor, {"target": target, "attack_index": index}))


func _mode(res: Dictionary) -> String:
	return str(CoreFixtures.first_event(_evs(res), "attack").get("advantage", ""))


func _apply(e: Encounter, target: String, condition: String, source: String, duration: Dictionary) -> void:
	assert_true(e._apply_condition(e.get_combatant(target), condition, source, duration), "apply %s" % condition)


func test_condition_entries_and_events() -> void:
	var e := _duel()
	var gob := e.get_combatant("gob")
	var before := e.events.size()
	_apply(e, "gob", "poisoned", "hero", Conditions.duration("rounds", {"rounds": 2}))
	var ev := e.events_since(before)
	assert_eq(ev[0], {"kind": "condition_applied", "target": "gob", "condition": "poisoned", "source": "hero", "duration": {"type": "rounds", "rounds": 2}, "turns_left": 2})
	assert_true(gob.has_condition("poisoned"))
	assert_eq(gob.conditions[0]["turns_left"], 2)
	assert_eq(gob.condition_sources("poisoned"), ["hero"])
	assert_false(e._apply_condition(gob, "poisoned", "hero", {}), "an invalid duration is refused")
	assert_eq(Conditions.normalize_duration({"type": "save_ends", "ability": "con", "dc": 12}), {"type": "save_ends", "ability": "CON", "dc": 12})
	assert_eq(Conditions.normalize_duration("forever"), {})


func test_prone_target_and_prone_attacker() -> void:
	var e := _duel(Vector2i(4, 3))
	_apply(e, "gob", "prone", "hero", Conditions.duration("encounter"))
	assert_eq(_mode(_attack(e, "hero", "gob")), "advantage", "adjacent attacker vs prone")
	e = _duel(Vector2i(8, 3), null, [HIT, BOW])
	_apply(e, "gob", "prone", "hero", Conditions.duration("encounter"))
	assert_eq(_mode(_attack(e, "hero", "gob", 1)), "disadvantage", "ranged attack vs prone from afar")
	e = _duel(Vector2i(4, 3))
	_apply(e, "hero", "prone", "gob", Conditions.duration("encounter"))
	assert_eq(_mode(_attack(e, "hero", "gob")), "disadvantage", "a prone attacker")


func test_stunned_and_paralyzed() -> void:
	var e := _duel()
	_apply(e, "gob", "stunned", "hero", Conditions.duration("until_source_next_turn"))
	var gob := e.get_combatant("gob")
	assert_true(gob.is_incapacitated())
	assert_true(gob.is_immobilized())
	assert_false(gob.can_react())
	assert_eq(_mode(_attack(e, "hero", "gob")), "advantage")
	var before := e.events.size()
	assert_false(e._saving_throw("hero", gob, Ability.Type.DEX, 5), "stunned fails DEX saves")
	assert_eq(e.events_since(before)[0]["natural"], 0)
	# Its turn is skipped; the stun ends at the end of the hero's next turn.
	e.end_turn()
	assert_eq(e.current_actor().id, "hero", "the stunned gob's turn passed")
	assert_true(gob.has_condition("stunned"))
	var kinds := CoreFixtures.kinds(e.events_since(before))
	assert_true(kinds.has("turn_started") and kinds.has("turn_ended"))
	before = e.events.size()
	e.end_turn()
	assert_false(gob.has_condition("stunned"))
	assert_has(e.events_since(before), {"kind": "condition_ended", "target": "gob", "condition": "stunned"})


func test_paralyzed_adjacent_hit_is_critical() -> void:
	var e := _duel()
	_apply(e, "gob", "paralyzed", "hero", Conditions.duration("encounter"))
	var ev := CoreFixtures.first_event(_evs(_attack(e, "hero", "gob")), "attack")
	if ev["hit"]:
		assert_true(ev["critical"], "a hit on a paralyzed creature within 5 ft is a critical hit")


func test_incapacitated_actor_cannot_act_but_may_end_turn() -> void:
	var e := _duel()
	_apply(e, "hero", "incapacitated", "gob", Conditions.duration("encounter"))
	assert_true(str(_attack(e, "hero", "gob")["error"]).contains("incapacitated"))
	assert_true(str(e.submit(CoreFixtures.intent("dash", "hero"))["error"]).contains("incapacitated"))
	assert_true(e.submit(CoreFixtures.intent("move", "hero", {"path": [[3, 4]]}))["ok"] == true, "incapacitated alone still allows moving")


func test_frightened_disadvantage_and_movement() -> void:
	var e := _duel(Vector2i(6, 3))
	_apply(e, "hero", "frightened", "gob", Conditions.duration("encounter"))
	var res := e.submit(CoreFixtures.intent("move", "hero", {"path": [[4, 3]]}))
	assert_true(str(res["error"]).contains("frightened"), "cannot move closer")
	assert_true(e.submit(CoreFixtures.intent("move", "hero", {"path": [[3, 4]]}))["ok"] == true, "may keep its distance")
	assert_true(e.submit(CoreFixtures.intent("move", "hero", {"path": [[2, 4]]}))["ok"] == true, "or move away")


func test_frightened_attack_disadvantage_needs_line_of_sight() -> void:
	var e := _duel(Vector2i(4, 3))
	_apply(e, "hero", "frightened", "gob", Conditions.duration("encounter"))
	assert_eq(_mode(_attack(e, "hero", "gob")), "disadvantage")


func test_poisoned_blinded_restrained_grappled() -> void:
	for cond: String in ["poisoned", "blinded", "restrained"]:
		var e := _duel()
		_apply(e, "hero", cond, "gob", Conditions.duration("encounter"))
		assert_eq(_mode(_attack(e, "hero", "gob")), "disadvantage", cond + " attacker")
	for cond: String in ["blinded", "restrained"]:
		var e := _duel()
		_apply(e, "gob", cond, "hero", Conditions.duration("encounter"))
		assert_eq(_mode(_attack(e, "hero", "gob")), "advantage", cond + " target")
	var g := _duel()
	_apply(g, "hero", "grappled", "gob", Conditions.duration("encounter"))
	assert_eq(g.get_combatant("hero").movement_remaining, 0, "grappled: speed 0")
	assert_eq(g.get_combatant("hero").speed_tiles(), 0)
	var r := _duel()
	_apply(r, "hero", "restrained", "gob", Conditions.duration("encounter"))
	assert_true(str(r.submit(CoreFixtures.intent("move", "hero", {"path": [[3, 4]]}))["error"]).contains("movement"), "restrained: speed 0")


func test_charmed_cannot_attack_the_charmer() -> void:
	var e := _duel()
	_apply(e, "hero", "charmed", "gob", Conditions.duration("encounter"))
	assert_true(str(_attack(e, "hero", "gob")["error"]).contains("charmed"))


func test_condition_immunity() -> void:
	var gob := CoreFixtures.sheet("Gob", 40)
	gob.condition_immunities = ["poisoned"]
	var e := _duel(Vector2i(4, 3), null, [HIT], gob)
	assert_false(e._apply_condition(e.get_combatant("gob"), "poisoned", "hero", Conditions.duration("encounter")))
	assert_false(e.get_combatant("gob").has_condition("poisoned"))
	var m := MonsterDefinition.from_dict({"id": "s", "display_name": "S", "armor_class": 12, "hit_points": 5, "hit_dice": "1d8",
		"speed": 30, "abilities": {"STR": 10, "DEX": 10, "CON": 10, "INT": 10, "WIS": 10, "CHA": 10}, "challenge_rating": 0.25,
		"xp": 50, "attacks": [HIT], "condition_immunities": ["poisoned"], "creature_type": "Undead"})
	assert_eq(m.to_sheet().condition_immunities, ["poisoned"])
	assert_eq(m.creature_type, "undead")


func test_durations_target_turn_end_rounds_and_save_ends() -> void:
	var e := _duel()
	_apply(e, "gob", "poisoned", "hero", Conditions.duration("until_target_turn_end"))
	_apply(e, "gob", "blinded", "hero", Conditions.duration("rounds", {"rounds": 2}))
	_apply(e, "gob", "restrained", "hero", Conditions.duration("save_ends", {"ability": "STR", "dc": 99}))
	var gob := e.get_combatant("gob")
	e.end_turn()  # hero -> gob
	assert_eq(e.current_actor().id, "gob")
	var before := e.events.size()
	e.end_turn()  # gob's turn ends
	var evs := e.events_since(before)
	assert_false(gob.has_condition("poisoned"), "until_target_turn_end")
	assert_true(gob.has_condition("blinded"), "one of two rounds")
	assert_true(gob.has_condition("restrained"), "DC 99 save fails")
	var save := CoreFixtures.first_event(evs, "save")
	assert_eq(save["ability"], "STR")
	assert_eq(save["dc"], 99)
	e.end_turn()  # hero
	e.end_turn()  # gob again
	assert_false(gob.has_condition("blinded"), "two rounds")


func test_stand_intent_and_prone_move() -> void:
	var e := _duel(Vector2i(8, 8))
	_apply(e, "hero", "prone", "gob", Conditions.duration("encounter"))
	var hero := e.get_combatant("hero")
	assert_eq(hero.movement_remaining, 6)
	var res := e.submit(CoreFixtures.intent("stand", "hero"))
	assert_true(res["ok"] == true, str(res["error"]))
	assert_false(hero.has_condition("prone"))
	assert_eq(hero.movement_remaining, 3, "half of 6 tiles")
	assert_true(str(e.submit(CoreFixtures.intent("stand", "hero"))["error"]).contains("not prone"))
	_apply(e, "hero", "prone", "gob", Conditions.duration("encounter"))
	assert_false(e.submit(CoreFixtures.intent("move", "hero", {"path": [[3, 4]]}))["ok"] == true, "3 tiles left: standing costs 3")
	var e2 := _duel(Vector2i(8, 8))
	_apply(e2, "hero", "prone", "gob", Conditions.duration("encounter"))
	res = e2.submit(CoreFixtures.intent("move", "hero", {"path": [[3, 4], [3, 5]]}))
	assert_true(res["ok"] == true, str(res["error"]))
	assert_eq(CoreFixtures.kinds(_evs(res))[0], "condition_ended", "stands up first")
	assert_eq(e2.get_combatant("hero").movement_remaining, 1)


func test_cure_item_ends_encounter_condition() -> void:
	var s := CoreFixtures.sheet("Hero", 40)
	s.add_item("antidote")
	var e := _duel(Vector2i(8, 8), s)
	_apply(e, "hero", "poisoned", "gob", Conditions.duration("encounter"))
	var res := e.submit(CoreFixtures.intent("use_item", "hero", {"item": "antidote"}))
	assert_true(res["ok"] == true, str(res["error"]))
	assert_has(_evs(res), {"kind": "condition_ended", "target": "hero", "condition": "poisoned"})
	assert_false(e.get_combatant("hero").has_condition("poisoned"))


func test_spell_applies_condition_with_save_ends() -> void:
	var caster := CoreFixtures.caster("Cleric", Ability.Type.WIS, ["hold_person", "trip"])
	caster.abilities.set_score(Ability.Type.WIS, 30)  # DC 8 + 2 + 10 = 20
	var gob := CoreFixtures.sheet("Gob", 40, [10, 1, 10, 10, 1, 10])
	var e := _duel(Vector2i(6, 3), caster, [HIT], gob)
	var res := e.submit(CoreFixtures.intent("cast", "hero", {"spell": "hold_person", "target": "gob", "slot_level": 2}))
	assert_true(res["ok"] == true, str(res["error"]))
	var applied := CoreFixtures.first_event(_evs(res), "condition_applied")
	assert_eq(applied["condition"], "paralyzed")
	assert_eq(applied["duration"], {"type": "save_ends", "ability": "WIS", "dc": 20})
	var g := e.get_combatant("gob")
	assert_true(g.loses_turn())
	assert_eq(g.conditions[0]["spell"], "hold_person", "tied to concentration")
	var trip := _duel(Vector2i(6, 3), caster, [HIT], gob)
	res = trip.submit(CoreFixtures.intent("cast", "hero", {"spell": "trip", "target": "gob", "slot_level": 1}))
	assert_eq(CoreFixtures.first_event(_evs(res), "condition_applied")["condition"], "prone")
	assert_eq(CoreFixtures.first_event(_evs(res), "condition_applied")["duration"], {"type": "save_ends", "ability": "DEX", "dc": 20})


func test_monster_brain_honours_conditions() -> void:
	var e := CoreFixtures.duel(CoreFixtures.sheet("Hero", 40), [HIT], {"gob": [CoreFixtures.sheet("Gob", 40), Vector2i(6, 3), [HIT]]}, content, "gob")
	assert_not_null(e)
	e._apply_condition(e.get_combatant("gob"), "frightened", "hero", Conditions.duration("encounter"))
	var plan := MonsterBrain.decide(e, "gob")
	assert_eq(plan.size(), 1, "frightened with only closer paths: holds")
	assert_eq(plan[0]["type"], "end_turn")
	var p := CoreFixtures.duel(CoreFixtures.sheet("Hero", 40), [HIT], {"gob": [CoreFixtures.sheet("Gob", 40), Vector2i(4, 3), [HIT]]}, content, "gob")
	p._apply_condition(p.get_combatant("gob"), "prone", "hero", Conditions.duration("encounter"))
	plan = MonsterBrain.decide(p, "gob")
	assert_eq(plan[0]["type"], "stand")
	assert_eq(plan[1]["type"], "attack")
	for intent in plan:
		assert_true(p.submit(intent)["ok"] == true)
	var t := CoreFixtures.duel(CoreFixtures.sheet("Hero", 40), [HIT], {"gob": [CoreFixtures.sheet("Gob", 40), Vector2i(4, 3), [HIT]]}, content, "gob")
	t._apply_condition(t.get_combatant("gob"), "frightened", "hero", Conditions.duration("rounds", {"rounds": 10}), {"flee": true})
	plan = MonsterBrain.decide(t, "gob")
	assert_eq(plan[0]["type"], "move")
	assert_has(plan.map(func(i: Dictionary) -> String: return str(i["type"])), "dash")
	for intent in plan:
		assert_true(t.submit(intent)["ok"] == true, str(intent))
	assert_true(GridMath.distance_tiles(t.get_combatant("gob").position, Vector2i(3, 3)) > 6, "fled")
	var c := CoreFixtures.duel(CoreFixtures.sheet("Hero", 40), [HIT], {"gob": [CoreFixtures.sheet("Gob", 40), Vector2i(4, 3), [HIT]]}, content, "gob")
	c._apply_condition(c.get_combatant("gob"), "charmed", "hero", Conditions.duration("encounter"))
	plan = MonsterBrain.decide(c, "gob")
	assert_eq(plan.size(), 1, "charmed by its only foe: no attack")

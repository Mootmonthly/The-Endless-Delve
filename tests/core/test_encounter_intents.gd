extends TestCase
## Intent-driven Encounter: movement, actions, opportunity attacks, turn start.

const SURE_HIT := {"name": "Sure Hit", "kind": "melee", "to_hit": 100, "damage": "1", "damage_type": "slashing"}
const SURE_KILL := {"name": "Sure Kill", "kind": "melee", "to_hit": 100, "damage": "100", "damage_type": "slashing"}
const BOW := {"name": "Bow", "kind": "ranged", "to_hit": 0, "damage": "1", "damage_type": "piercing"}

var map: WalkMap
var region: Rect2i



func _ok(res: Dictionary) -> bool:
	return res.get("ok", false) == true


func _evs(res: Dictionary) -> Array:
	var evs: Array = res.get("events", [])
	return evs


func _flag(ev: Dictionary, key: String) -> bool:
	return ev.get(key, false) == true

func before_each() -> void:
	map = WalkMap.new(12, 12, true)
	map.set_walkable(Vector2i(6, 6), false)
	region = Rect2i(0, 0, 10, 10)


func _make(combatant_id: String, team: int, pos: Vector2i, hp: int = 30, attack: Dictionary = SURE_HIT) -> Combatant:
	var s := CharacterSheet.new()
	s.name = combatant_id
	s.max_hp = hp
	s.current_hp = hp
	s.uses_death_saves = team == Combatant.TEAM_PLAYERS
	var c := Combatant.from_sheet(combatant_id, s, team)
	c.attacks = [attack.duplicate()]
	c.position = pos
	return c


## Builds and starts an encounter, trying seeds until `first_id` acts first.
## specs: [id, team, pos, hp, attack] arrays.
func _fight(specs: Array, first_id: String) -> Encounter:
	for s in range(1, 500):
		var e := Encounter.new("t", Rng.new(s), map, region)
		for spec: Array in specs:
			var team: int = spec[1]
			var pos: Vector2i = spec[2]
			var hp: int = spec[3] if spec.size() > 3 else 30
			var attack: Dictionary = spec[4] if spec.size() > 4 else SURE_HIT
			var c := _make(str(spec[0]), team, pos, hp, attack)
			assert_true(e.add_combatant(c), "add %s" % c.id)
		e.start()
		if e.current_actor() != null and e.current_actor().id == first_id:
			return e
	fail("no seed lets %s act first" % first_id)
	return null


func _move(actor_id: String, steps: Array) -> Dictionary:
	return {"v": 1, "type": "move", "actor": actor_id, "path": steps}


func _act(actor_id: String, intent_type: String) -> Dictionary:
	return {"v": 1, "type": intent_type, "actor": actor_id}


func _attack(actor_id: String, target_id: String, index: int = 0) -> Dictionary:
	return {"v": 1, "type": "attack", "actor": actor_id, "target": target_id, "attack_index": index}


func _kinds(evs: Array) -> Array[String]:
	var out: Array[String] = []
	for ev: Dictionary in evs:
		out.append(str(ev["kind"]))
	return out


func _count(evs: Array, kind: String) -> int:
	return _kinds(evs).count(kind)


func _first(evs: Array, kind: String) -> Dictionary:
	for ev: Dictionary in evs:
		if ev["kind"] == kind:
			return ev
	return {}


## Forces the encounter's next d20 roll(s) to satisfy predicate.
func _force_rng(e: Encounter, predicate: Callable) -> void:
	e.rng = Rng.new(seed_where(predicate))


func test_start_events() -> void:
	var e := _fight([["hero", 0, Vector2i(1, 1)], ["gob", 1, Vector2i(8, 8)]], "hero")
	var k := _kinds(e.events)
	assert_eq(k, ["combatant_joined", "combatant_joined", "encounter_started", "round_started", "turn_started"])
	assert_eq(e.events[2]["order"], ["hero", "gob"])
	assert_eq(e.events[4]["actor"], "hero")
	assert_eq(e.events[0]["position"], [1, 1])
	assert_eq(e.current_actor().movement_remaining, 6, "speed 30 ft = 6 tiles")
	assert_eq(e.setup_snapshot().size(), 2)


func test_add_combatant_position_rules() -> void:
	var e := Encounter.new("t", Rng.new(1), map, region)
	assert_true(e.add_combatant(_make("a", 0, Vector2i(1, 1))))
	assert_false(e.add_combatant(_make("b", 0, Vector2i(1, 1))), "occupied")
	assert_false(e.add_combatant(_make("c", 0, Vector2i(6, 6))), "wall")
	assert_false(e.add_combatant(_make("d", 0, Vector2i(11, 11))), "outside the region")


func test_move_updates_position_and_budget() -> void:
	var e := _fight([["hero", 0, Vector2i(1, 1)], ["gob", 1, Vector2i(8, 8)]], "hero")
	var res := e.submit(_move("hero", [[2, 2], [3, 3], [4, 3]]))
	assert_true(_ok(res), str(res["error"]))
	var hero := e.get_combatant("hero")
	assert_eq(hero.position, Vector2i(4, 3))
	assert_eq(hero.movement_remaining, 3)
	assert_eq(_count(_evs(res), "moved"), 3)
	assert_eq(_evs(res)[0], {"kind": "moved", "actor": "hero", "from": [1, 1], "to": [2, 2]})
	assert_eq(e.intent_log.size(), 1)
	assert_false(_ok(e.submit(_move("hero", [[5, 3], [6, 3], [7, 3], [8, 3]]))), "only 3 tiles left")
	assert_true(_ok(e.submit(_move("hero", [[5, 3], [6, 3], [7, 3]]))))
	assert_eq(hero.movement_remaining, 0)


func test_move_rejects_illegal_paths() -> void:
	var e := _fight([["hero", 0, Vector2i(5, 5)], ["ally", 0, Vector2i(4, 5)], ["gob", 1, Vector2i(9, 9)]], "hero")
	var hero := e.get_combatant("hero")
	var before := e.events.size()
	assert_false(_ok(e.submit(_move("hero", [[6, 6]]))), "wall")
	assert_false(_ok(e.submit(_move("hero", [[4, 5]]))), "occupied by an ally")
	assert_false(_ok(e.submit(_move("hero", [[7, 5]]))), "not adjacent")
	assert_false(_ok(e.submit(_move("hero", [[6, 5], [7, 6], [6, 6]]))), "later step into a wall")
	assert_false(_ok(e.submit(_move("hero", []))), "empty")
	assert_false(_ok(e.submit(_move("hero", [["x", 1]]))), "malformed")
	assert_false(_ok(e.submit({"v": 1, "type": "move", "actor": "hero"})), "missing path")
	assert_eq(hero.position, Vector2i(5, 5))
	assert_eq(hero.movement_remaining, 6)
	assert_eq(e.events.size(), before)
	assert_eq(e.intent_log.size(), 0)


func test_move_cannot_leave_region() -> void:
	var e := _fight([["hero", 0, Vector2i(9, 2)], ["gob", 1, Vector2i(1, 8)]], "hero")
	assert_false(_ok(e.submit(_move("hero", [[10, 2]]))))
	assert_true(_ok(e.submit(_move("hero", [[9, 3]]))))


func test_json_float_intents_accepted() -> void:
	var e := _fight([["hero", 0, Vector2i(1, 1)], ["gob", 1, Vector2i(8, 8)]], "hero")
	var intent: Dictionary = JSON.parse_string(JSON.stringify(_move("hero", [[2, 1]])))
	assert_true(_ok(e.submit(intent)))
	assert_eq(e.get_combatant("hero").position, Vector2i(2, 1))


func test_opportunity_attack_fires_once() -> void:
	var e := _fight([["hero", 0, Vector2i(3, 3), 50], ["gob", 1, Vector2i(4, 3)]], "hero")
	var res := e.submit(_move("hero", [[2, 3], [1, 3]]))
	assert_true(_ok(res))
	var evs: Array = _evs(res)
	assert_eq(_count(evs, "opportunity_attack"), 1)
	assert_eq(_first(evs, "opportunity_attack"), {"kind": "opportunity_attack", "attacker": "gob", "target": "hero"})
	assert_eq(_kinds(evs).slice(0, 3), ["opportunity_attack", "reaction_used", "attack"], "the attack resolves before the step")
	assert_eq(_first(evs, "reaction_used"), {"kind": "reaction_used", "actor": "gob", "reaction": "opportunity_attack", "trigger": "creature_left_reach", "target": "hero"})
	assert_true(e.get_combatant("gob").reaction_used)
	# Walk back into reach and out again: the reaction is spent.
	res = e.submit(_move("hero", [[2, 3], [3, 3], [2, 4], [1, 4]]))
	assert_true(_ok(res))
	assert_eq(_count(_evs(res), "opportunity_attack"), 0)


func test_no_opportunity_attack_when_staying_in_reach() -> void:
	var e := _fight([["hero", 0, Vector2i(3, 3)], ["gob", 1, Vector2i(4, 4)]], "hero")
	var res := e.submit(_move("hero", [[3, 4], [3, 5]]))
	assert_eq(_count(_evs(res), "opportunity_attack"), 0)
	assert_false(e.get_combatant("gob").reaction_used)


func test_no_opportunity_attack_when_disengaging() -> void:
	var e := _fight([["hero", 0, Vector2i(3, 3)], ["gob", 1, Vector2i(4, 3)]], "hero")
	var res := e.submit(_act("hero", "disengage"))
	assert_true(_ok(res))
	assert_eq(_kinds(_evs(res)), ["disengage"])
	res = e.submit(_move("hero", [[2, 3], [1, 3]]))
	assert_true(_ok(res))
	assert_eq(_count(_evs(res), "opportunity_attack"), 0)
	assert_false(_ok(e.submit(_attack("hero", "gob"))), "disengage used the action")


func test_no_opportunity_attack_when_reaction_used() -> void:
	var e := _fight([["hero", 0, Vector2i(3, 3)], ["gob", 1, Vector2i(4, 3)]], "hero")
	e.get_combatant("gob").reaction_used = true
	var res := e.submit(_move("hero", [[2, 3]]))
	assert_eq(_count(_evs(res), "opportunity_attack"), 0)


func test_opportunity_attack_dropping_mover_stops_move() -> void:
	var specs := [["hero", 0, Vector2i(3, 3), 5], ["ally", 0, Vector2i(0, 9)], ["gob", 1, Vector2i(4, 3), 30, SURE_KILL]]
	var e := _fight(specs, "hero")
	_force_rng(e, func(r: Rng) -> bool: return D20.roll(r).natural > 1)
	var res := e.submit(_move("hero", [[2, 3], [1, 3]]))
	assert_true(_ok(res))
	var hero := e.get_combatant("hero")
	assert_eq(hero.position, Vector2i(3, 3), "never left the tile")
	assert_eq(_count(_evs(res), "moved"), 0)
	assert_true(_flag(_first(_evs(res), "damage"), "dropped"))
	assert_eq(_first(_evs(res), "turn_ended")["actor"], "hero", "the downed mover's turn ends")
	assert_ne(e.current_actor().id, "hero")


func test_dash_adds_movement() -> void:
	var e := _fight([["hero", 0, Vector2i(0, 0)], ["gob", 1, Vector2i(9, 0)]], "hero")
	var res := e.submit(_act("hero", "dash"))
	assert_true(_ok(res))
	assert_eq(_kinds(_evs(res)), ["dash"])
	var hero := e.get_combatant("hero")
	assert_eq(hero.movement_remaining, 12)
	assert_true(hero.action_used)
	assert_false(_ok(e.submit(_act("hero", "dash"))), "one action per turn")
	assert_true(_ok(e.submit(_move("hero", [[1, 1], [2, 2], [3, 3], [4, 4], [5, 5], [5, 6], [5, 7], [5, 8], [5, 9], [4, 9], [3, 9], [2, 9]]))))
	assert_eq(hero.movement_remaining, 0)


func test_dodge_imposes_disadvantage_until_next_turn() -> void:
	var e := _fight([["hero", 0, Vector2i(3, 3)], ["gob", 1, Vector2i(4, 3)]], "hero")
	assert_true(_ok(e.submit(_act("hero", "dodge"))))
	assert_true(e.get_combatant("hero").dodging)
	e.submit(_act("hero", "end_turn"))
	assert_eq(e.current_actor().id, "gob")
	var res := e.submit(_attack("gob", "hero"))
	assert_true(_ok(res))
	assert_eq(_first(_evs(res), "attack")["advantage"], "disadvantage")
	var d20s: Array = _first(_evs(res), "attack")["d20s"]
	assert_eq(d20s.size(), 2)
	e.submit(_act("gob", "end_turn"))
	assert_eq(e.current_actor().id, "hero")
	assert_false(e.get_combatant("hero").dodging, "dodge ends at the start of the dodger's next turn")


func test_ranged_attack_in_melee_has_disadvantage() -> void:
	var e := _fight([["hero", 0, Vector2i(3, 3), 30, BOW], ["gob", 1, Vector2i(4, 3)]], "hero")
	var res := e.submit(_attack("hero", "gob"))
	assert_eq(_first(_evs(res), "attack")["advantage"], "disadvantage")


func test_attack_needs_adjacency() -> void:
	var e := _fight([["hero", 0, Vector2i(1, 3)], ["gob", 1, Vector2i(4, 3)]], "hero")
	var res := e.submit(_attack("hero", "gob"))
	assert_false(_ok(res))
	assert_true(str(res["error"]).contains("reach"))
	assert_true(_ok(e.submit(_move("hero", [[2, 3], [3, 3]]))))
	res = e.submit(_attack("hero", "gob"))
	assert_true(_ok(res))
	var atk := _first(_evs(res), "attack")
	assert_eq(atk["attacker"], "hero")
	assert_eq(atk["target"], "gob")
	assert_eq(atk["attack_name"], "Sure Hit")
	assert_eq(atk["target_ac"], 10)
	assert_eq(atk["advantage"], "normal")
	if atk["hit"]:
		assert_eq(_first(_evs(res), "damage")["amount"], 2 if atk["critical"] else 1)


func test_attack_validation() -> void:
	var e := _fight([["hero", 0, Vector2i(3, 3)], ["ally", 0, Vector2i(3, 4)], ["gob", 1, Vector2i(4, 3)]], "hero")
	assert_false(_ok(e.submit(_attack("hero", "ally"))), "same team")
	assert_false(_ok(e.submit(_attack("hero", "nobody"))), "unknown target")
	assert_false(_ok(e.submit(_attack("hero", "gob", 5))), "bad attack index")
	assert_false(_ok(e.submit(_attack("hero", "gob", -1))), "negative attack index")
	assert_true(_ok(e.submit(_attack("hero", "gob"))))
	assert_false(_ok(e.submit(_attack("hero", "gob"))), "action already used")
	assert_false(_ok(e.submit(_act("hero", "dodge"))), "action already used")
	assert_true(_ok(e.submit(_move("hero", [[2, 3]]))), "movement is separate from the action")


func test_unconscious_target_advantage_and_auto_crit() -> void:
	var specs := [["gob", 1, Vector2i(4, 3)], ["down", 0, Vector2i(3, 3)], ["ally", 0, Vector2i(0, 9)]]
	var e := _fight(specs, "gob")
	var down := e.get_combatant("down")
	down.sheet.take_damage(30)
	assert_true(down.sheet.is_unconscious())
	_force_rng(e, func(r: Rng) -> bool:
		var n := D20.roll(r, D20.RollMode.ADVANTAGE).natural
		return n > 1 and n < 20)
	var res := e.submit(_attack("gob", "down"))
	assert_true(_ok(res))
	var atk := _first(_evs(res), "attack")
	assert_eq(atk["advantage"], "advantage")
	assert_true(_flag(atk, "hit"))
	assert_true(_flag(atk, "critical"), "a hit within 5 ft of an unconscious creature is a critical hit")
	assert_false(_flag(atk, "fumble"))
	assert_eq(down.sheet.death_save_failures, 2, "a critical hit at 0 hp is two failures")


func test_death_save_at_turn_start() -> void:
	var specs := [["ally", 0, Vector2i(0, 0)], ["down", 0, Vector2i(5, 5)], ["gob", 1, Vector2i(9, 9)]]
	var e := _fight(specs, "ally")
	var down := e.get_combatant("down")
	down.sheet.take_damage(30)
	for _i in range(6):
		e.end_turn()
		assert_ne(e.current_actor().id, "down", "a downed combatant never waits for intents")
	var k := _kinds(e.events)
	var save_at := k.find("death_save")
	assert_true(save_at > 0, "a death save was rolled")
	assert_eq(e.events[save_at - 1], {"kind": "turn_started", "actor": "down", "round": e.events[save_at - 1]["round"]})
	assert_eq(e.events[save_at]["actor"], "down")
	assert_true(e.events[save_at].has("natural") and e.events[save_at].has("successes") and e.events[save_at].has("regained"))
	if not e.events[save_at]["regained"]:
		assert_eq(e.events[save_at + 1], {"kind": "turn_ended", "actor": "down"})


func test_turns_of_stable_and_dead_are_skipped() -> void:
	var specs := [["ally", 0, Vector2i(0, 0)], ["stable", 0, Vector2i(5, 5)], ["dead", 0, Vector2i(2, 2)], ["gob", 1, Vector2i(9, 9)]]
	var e := _fight(specs, "ally")
	var stable := e.get_combatant("stable")
	stable.sheet.take_damage(30)
	stable.sheet.stable = true
	e.get_combatant("dead").sheet.take_damage(100)
	assert_true(e.get_combatant("dead").sheet.is_dead())
	var start := e.events.size()
	for _i in range(4):
		e.end_turn()
	var evs := e.events_since(start)
	assert_eq(_count(evs, "death_save"), 0, "stable creatures do not roll")
	var stable_turns := 0
	for i in range(evs.size()):
		var ev: Dictionary = evs[i]
		if ev["kind"] == "turn_started" and ev["actor"] == "stable":
			stable_turns += 1
			assert_eq(evs[i + 1], {"kind": "turn_ended", "actor": "stable"})
		if ev["kind"] == "turn_started":
			assert_ne(ev["actor"], "dead", "the dead get no turns")
	assert_true(stable_turns >= 1)


func test_turn_start_resets_resources() -> void:
	var e := _fight([["hero", 0, Vector2i(3, 3)], ["gob", 1, Vector2i(4, 3)]], "hero")
	e.submit(_act("hero", "dash"))
	e.submit(_move("hero", [[3, 4]]))
	e.get_combatant("hero").reaction_used = true
	e.submit(_act("hero", "end_turn"))
	e.submit(_act("gob", "end_turn"))
	var hero := e.get_combatant("hero")
	assert_eq(e.current_actor(), hero)
	assert_eq(hero.movement_remaining, 6)
	assert_false(hero.action_used)
	assert_false(hero.reaction_used)
	assert_false(hero.disengaging)
	assert_eq(_kinds(e.events).count("round_started"), 2)


func test_rejected_intents_are_not_logged() -> void:
	var e := _fight([["hero", 0, Vector2i(3, 3)], ["gob", 1, Vector2i(8, 8)]], "hero")
	var events_before := e.events.size()
	var rejected: Array[Dictionary] = [
		_act("gob", "end_turn"),
		{"v": 2, "type": "end_turn", "actor": "hero"},
		{"type": "end_turn", "actor": "hero"},
		{"v": 1, "type": "end_turn"},
		{"v": 1, "type": "fly", "actor": "hero"},
		_attack("hero", "gob"),
	]
	for intent in rejected:
		var res := e.submit(intent)
		assert_false(_ok(res), str(intent))
		assert_ne(res["error"], "")
		assert_eq(_evs(res), [])
	assert_eq(e.intent_log.size(), 0)
	assert_eq(e.events.size(), events_before)
	assert_true(_ok(e.submit(_act("hero", "end_turn"))))
	assert_eq(e.intent_log, [_act("hero", "end_turn")])


func test_intents_rejected_when_not_active() -> void:
	var e := Encounter.new("t", Rng.new(1), map, region)
	e.add_combatant(_make("hero", 0, Vector2i(1, 1)))
	assert_false(_ok(e.submit(_act("hero", "end_turn"))), "forming")
	assert_eq(e.intent_log.size(), 0)


func test_encounter_ends_when_last_monster_dies() -> void:
	var specs := [["hero", 0, Vector2i(3, 3), 30, SURE_KILL], ["gob", 1, Vector2i(4, 3), 5]]
	var e := _fight(specs, "hero")
	_force_rng(e, func(r: Rng) -> bool: return D20.roll(r).natural > 1)
	var res := e.submit(_attack("hero", "gob"))
	var k := _kinds(_evs(res))
	assert_eq(k, ["attack", "damage", "encounter_ended"])
	assert_true(_flag(_first(_evs(res), "damage"), "died"), "monsters die at 0 hp")
	assert_eq(_first(_evs(res), "encounter_ended")["winning_team"], 0)
	assert_eq(e.state, Encounter.State.ENDED)
	assert_eq(e.winning_team, 0)
	assert_false(_ok(e.submit(_act("hero", "end_turn"))))
	assert_null(e.current_actor())


func test_mid_combat_join_and_remove_are_logged() -> void:
	var e := _fight([["hero", 0, Vector2i(3, 3)], ["gob", 1, Vector2i(8, 8)]], "hero")
	assert_true(e.add_combatant(_make("late", 1, Vector2i(9, 9))))
	assert_eq(e.events[e.events.size() - 1]["kind"], "combatant_joined")
	assert_eq(e.intent_log[0]["type"], Encounter.LOG_JOIN)
	assert_eq(e.intent_log[0]["entry"]["id"], "late")
	assert_true(e.remove_combatant("hero"))
	assert_eq(e.intent_log[1], {"v": 1, "type": Encounter.LOG_REMOVE, "id": "hero"})
	assert_eq(e.state, Encounter.State.ENDED, "no players left")
	assert_eq(e.winning_team, 1)
	assert_false(_ok(e.submit(e.intent_log[0])), "log-only entries are never accepted by submit")

extends TestCase

const CLAW := {"name": "Claw", "kind": "melee", "to_hit": 100, "damage": "1", "damage_type": "slashing"}

var map: WalkMap


func before_each() -> void:
	map = WalkMap.new(12, 12, true)


func _make(combatant_id: String, team: int, pos: Vector2i, hp: int = 30) -> Combatant:
	var s := CharacterSheet.new()
	s.name = combatant_id
	s.max_hp = hp
	s.current_hp = hp
	s.uses_death_saves = team == Combatant.TEAM_PLAYERS
	var c := Combatant.from_sheet(combatant_id, s, team)
	c.attacks = [CLAW.duplicate()]
	c.position = pos
	if team == Combatant.TEAM_MONSTERS:
		c.monster_id = "test_monster"
	return c


## Encounter where the monster "m" at m_pos acts first, versus the given heroes.
func _fight(m_pos: Vector2i, heroes: Array[Combatant]) -> Encounter:
	for s in range(1, 500):
		var e := Encounter.new("brain", Rng.new(s), map, Rect2i(0, 0, 12, 12))
		e.add_combatant(_make("m", 1, m_pos))
		for h in heroes:
			var copy := _make(h.id, h.team, h.position, h.sheet.current_hp)
			e.add_combatant(copy)
		e.start()
		if e.current_actor() != null and e.current_actor().id == "m":
			return e
	fail("no seed lets the monster act first")
	return null


func _types(intents: Array[Dictionary]) -> Array[String]:
	var out: Array[String] = []
	for i in intents:
		out.append(str(i["type"]))
	return out


func _heroes(list: Array) -> Array[Combatant]:
	var out: Array[Combatant] = []
	for spec: Array in list:
		var pos: Vector2i = spec[1]
		var hp: int = spec[2] if spec.size() > 2 else 30
		out.append(_make(str(spec[0]), 0, pos, hp))
	return out


func test_moves_toward_nearest_then_attacks() -> void:
	var e := _fight(Vector2i(0, 0), _heroes([["far", Vector2i(9, 0)], ["near", Vector2i(3, 4)]]))
	var plan := MonsterBrain.decide(e, "m")
	assert_eq(_types(plan), ["move", "attack", "end_turn"])
	var path: Array = plan[0]["path"]
	var last := GridMath.arr_to_vec(path[path.size() - 1])
	assert_true(GridMath.is_adjacent(last, Vector2i(3, 4)))
	assert_eq(path.size(), 3)
	assert_eq(plan[1]["target"], "near")
	assert_eq(plan[1]["attack_index"], 0)
	for intent in plan:
		var res := e.submit(intent)
		assert_eq(res["ok"], true, str(res["error"]))
	assert_ne(e.current_actor().id, "m", "turn ended")


func test_far_target_move_truncated_without_attack() -> void:
	var e := _fight(Vector2i(0, 0), _heroes([["far", Vector2i(11, 11)]]))
	var plan := MonsterBrain.decide(e, "m")
	assert_eq(_types(plan), ["move", "end_turn"])
	var path: Array = plan[0]["path"]
	assert_eq(path.size(), 6, "speed 30 ft")
	assert_eq(e.submit(plan[0])["ok"], true)


func test_attacks_lowest_hp_adjacent() -> void:
	var e := _fight(Vector2i(5, 5), _heroes([["strong", Vector2i(4, 5), 20], ["weak", Vector2i(6, 6), 5], ["away", Vector2i(9, 9), 1]]))
	var plan := MonsterBrain.decide(e, "m")
	assert_eq(_types(plan), ["attack", "end_turn"])
	assert_eq(plan[0]["target"], "weak")


func test_ties_break_by_id() -> void:
	var e := _fight(Vector2i(5, 5), _heroes([["b", Vector2i(4, 5), 10], ["a", Vector2i(6, 5), 10]]))
	assert_eq(MonsterBrain.decide(e, "m")[0]["target"], "a")
	var e2 := _fight(Vector2i(5, 5), _heroes([["zed", Vector2i(5, 1)], ["amy", Vector2i(9, 5)]]))
	var plan := MonsterBrain.decide(e2, "m")
	var path: Array = plan[0]["path"]
	assert_true(GridMath.is_adjacent(GridMath.arr_to_vec(path[path.size() - 1]), Vector2i(9, 5)), "equal distance: lowest id")


func test_ignores_unconscious_and_is_deterministic() -> void:
	var e := _fight(Vector2i(5, 5), _heroes([["down", Vector2i(4, 5)], ["up", Vector2i(9, 5)], ["other", Vector2i(0, 0)]]))
	e.get_combatant("down").sheet.take_damage(30)
	var plan := MonsterBrain.decide(e, "m")
	assert_eq(_types(plan)[0], "move", "an unconscious neighbour is not attacked")
	assert_eq(MonsterBrain.decide(e, "m"), plan, "same state, same plan")
	assert_eq(e.intent_log.size(), 0, "decide() does not change the encounter")


func test_unreachable_target_just_ends_turn() -> void:
	map = WalkMap.from_rows(["...#....", "...#....", "...#....", "...#...."])
	var e := _fight(Vector2i(0, 0), _heroes([["hero", Vector2i(6, 1)]]))
	assert_eq(_types(MonsterBrain.decide(e, "m")), ["end_turn"])
	assert_eq(MonsterBrain.decide(e, "nobody"), [])


func test_targets_a_dying_hostile_when_none_is_conscious() -> void:
	var e := _fight(Vector2i(5, 5), _heroes([["down", Vector2i(4, 5)]]))
	e.get_combatant("down").sheet.take_damage(30)
	var plan := MonsterBrain.decide(e, "m")
	assert_eq(_types(plan), ["attack", "end_turn"], "the dying are attacked once nobody else stands")
	assert_eq(plan[0]["target"], "down")


func test_walks_to_a_dying_hostile() -> void:
	var e := _fight(Vector2i(0, 0), _heroes([["down", Vector2i(4, 4)]]))
	e.get_combatant("down").sheet.take_damage(30)
	var plan := MonsterBrain.decide(e, "m")
	assert_eq(_types(plan), ["move", "attack", "end_turn"])
	assert_eq(plan[1]["target"], "down")


func test_never_targets_stable_or_dead() -> void:
	var e := _fight(Vector2i(5, 5), _heroes([["stable", Vector2i(4, 5)], ["dead", Vector2i(6, 5)], ["dying", Vector2i(9, 9)]]))
	var stable := e.get_combatant("stable")
	stable.sheet.take_damage(30)
	stable.sheet.stable = true
	e.get_combatant("dead").sheet.take_damage(100)
	assert_true(e.get_combatant("dead").sheet.is_dead())
	e.get_combatant("dying").sheet.take_damage(30)
	var plan := MonsterBrain.decide(e, "m")
	assert_eq(_types(plan), ["move", "attack", "end_turn"], "heads for the dying one, ignoring adjacent stable / dead")
	assert_eq(plan[1]["target"], "dying")
	e.get_combatant("dying").sheet.stable = true
	assert_eq(_types(MonsterBrain.decide(e, "m")), ["end_turn"], "nobody left to target")

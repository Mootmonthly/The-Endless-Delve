extends TestCase

const STRONG := {"name": "Greatsword", "to_hit": 50, "damage": "50", "damage_type": "slashing"}
const WEAK := {"name": "Poke", "to_hit": 0, "damage": "1", "damage_type": "piercing"}


## Everyone stands in one 2x2 block, so every pair is adjacent (reach 1).
const BLOCK: Array[Vector2i] = [Vector2i(2, 2), Vector2i(3, 2), Vector2i(2, 3), Vector2i(3, 3), Vector2i(4, 2)]

var _next_slot: int = 0



func _ok(res: Dictionary) -> bool:
	return res.get("ok", false) == true


func _evs(res: Dictionary) -> Array:
	var evs: Array = res.get("events", [])
	return evs


func _flag(ev: Dictionary, key: String) -> bool:
	return ev.get(key, false) == true

func before_each() -> void:
	_next_slot = 0


func _c(combatant_id: String, team: int, hp: int = 20) -> Combatant:
	var s := CharacterSheet.new()
	s.name = combatant_id
	s.max_hp = hp
	s.current_hp = hp
	var c := Combatant.from_sheet(combatant_id, s, team)
	c.attacks = [STRONG.duplicate() if team == 0 else WEAK.duplicate()]
	c.position = BLOCK[_next_slot % BLOCK.size()]
	_next_slot += 1
	return c


func _new_encounter(seed_value: int) -> Encounter:
	return Encounter.new("e1", Rng.new(seed_value), WalkMap.new(8, 8, true), Rect2i(0, 0, 8, 8))


func _duel() -> Encounter:
	var e := _new_encounter(2024)
	e.add_combatant(_c("hero", 0, 100))
	e.add_combatant(_c("ally", 0, 100))
	e.add_combatant(_c("goblin", 1, 1))
	e.add_combatant(_c("rat", 1, 1))
	e.start()
	return e


func _attack(e: Encounter, attacker_id: String, target_id: String) -> Dictionary:
	return e.submit({"v": 1, "type": "attack", "actor": attacker_id, "target": target_id, "attack_index": 0})


func _enemy_of(e: Encounter, actor: Combatant) -> Combatant:
	for c in e.combatants():
		if c.team != actor.team and c.is_alive():
			return c
	return null


func _friend_of(e: Encounter, actor: Combatant) -> Combatant:
	for c in e.combatants():
		if c.team == actor.team and c.id != actor.id:
			return c
	return null


func test_start_requires_two_teams() -> void:
	var e := _new_encounter(1)
	assert_false(e.start(), "empty encounter")
	e.add_combatant(_c("a", 0))
	e.add_combatant(_c("b", 0))
	assert_false(e.start(), "one team only")
	assert_eq(e.state, Encounter.State.FORMING)
	e.add_combatant(_c("m", 1))
	assert_true(e.start())
	assert_eq(e.state, Encounter.State.ACTIVE)
	assert_not_null(e.current_actor())


func test_rejects_attack_out_of_turn() -> void:
	var e := _duel()
	var actor := e.current_actor()
	var waiting := _enemy_of(e, actor)
	var res := _attack(e, waiting.id, actor.id)
	assert_false(_ok(res))
	assert_ne(res["error"], "")


func test_rejects_same_team_target() -> void:
	var e := _duel()
	var actor := e.current_actor()
	assert_false(_ok(_attack(e, actor.id, _friend_of(e, actor).id)))


func test_rejects_dead_target() -> void:
	var e := _duel()
	var actor := e.current_actor()
	var enemy := _enemy_of(e, actor)
	enemy.sheet.take_damage(1000)
	assert_false(_ok(_attack(e, actor.id, enemy.id)))


func test_one_attack_per_turn() -> void:
	var e := _duel()
	var actor := e.current_actor()
	var enemy := _enemy_of(e, actor)
	assert_true(_ok(_attack(e, actor.id, enemy.id)))
	if e.state == Encounter.State.ACTIVE:
		var other := _enemy_of(e, actor)
		assert_false(_ok(_attack(e, actor.id, other.id)))


func test_end_turn_advances() -> void:
	var e := _duel()
	var first := e.current_actor()
	var second := e.end_turn()
	assert_not_null(second)
	assert_ne(second.id, first.id)
	assert_eq(e.current_actor().id, second.id)


func test_fight_ends_with_winning_team() -> void:
	var e := _duel()
	for _turn in range(100):
		if e.state != Encounter.State.ACTIVE:
			break
		var actor := e.current_actor()
		var enemy := _enemy_of(e, actor)
		_attack(e, actor.id, enemy.id)
		e.end_turn()
	assert_eq(e.state, Encounter.State.ENDED)
	assert_eq(e.winning_team, 0)
	assert_null(e.end_turn(), "no turns after the end")


func test_mid_combat_join() -> void:
	var e := _duel()
	assert_true(e.add_combatant(_c("late", 1)))
	assert_eq(e.combatants().size(), 5)
	var dup := _c("late", 1)
	dup.position = Vector2i(6, 6)
	assert_false(e.add_combatant(dup), "duplicate id")


func test_no_joining_after_end() -> void:
	var e := _duel()
	for c in e.combatants():
		if c.team == 1:
			c.sheet.take_damage(1000)
	assert_true(e.check_end())
	assert_eq(e.winning_team, 0)
	assert_false(e.add_combatant(_c("late", 1)))

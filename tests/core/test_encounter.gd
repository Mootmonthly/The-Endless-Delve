extends TestCase

const STRONG := {"name": "Greatsword", "to_hit": 50, "damage": "50", "damage_type": "slashing"}
const WEAK := {"name": "Poke", "to_hit": 0, "damage": "1", "damage_type": "piercing"}


func _c(combatant_id: String, team: int, hp: int = 20) -> Combatant:
	var s := CharacterSheet.new()
	s.name = combatant_id
	s.max_hp = hp
	s.current_hp = hp
	return Combatant.from_sheet(combatant_id, s, team)


func _duel() -> Encounter:
	var e := Encounter.new("e1", Rng.new(2024))
	e.add_combatant(_c("hero", 0, 100))
	e.add_combatant(_c("ally", 0, 100))
	e.add_combatant(_c("goblin", 1, 1))
	e.add_combatant(_c("rat", 1, 1))
	e.start()
	return e


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
	var e := Encounter.new("e", Rng.new(1))
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
	assert_null(e.perform_attack(waiting.id, actor.id, STRONG))
	assert_true(e.event_log[e.event_log.size() - 1].begins_with("Rejected"))


func test_rejects_same_team_target() -> void:
	var e := _duel()
	var actor := e.current_actor()
	assert_null(e.perform_attack(actor.id, _friend_of(e, actor).id, STRONG))


func test_rejects_dead_target() -> void:
	var e := _duel()
	var actor := e.current_actor()
	var enemy := _enemy_of(e, actor)
	enemy.sheet.take_damage(1000)
	assert_null(e.perform_attack(actor.id, enemy.id, STRONG))


func test_one_attack_per_turn() -> void:
	var e := _duel()
	var actor := e.current_actor()
	var enemy := _enemy_of(e, actor)
	assert_not_null(e.perform_attack(actor.id, enemy.id, WEAK))
	if e.state == Encounter.State.ACTIVE:
		var other := _enemy_of(e, actor)
		assert_null(e.perform_attack(actor.id, other.id, WEAK))


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
		e.perform_attack(actor.id, enemy.id, STRONG if actor.team == 0 else WEAK)
		e.end_turn()
	assert_eq(e.state, Encounter.State.ENDED)
	assert_eq(e.winning_team, 0)
	assert_null(e.end_turn(), "no turns after the end")


func test_mid_combat_join() -> void:
	var e := _duel()
	assert_true(e.add_combatant(_c("late", 1)))
	assert_eq(e.combatants().size(), 5)
	assert_false(e.add_combatant(_c("late", 1)), "duplicate id")


func test_no_joining_after_end() -> void:
	var e := _duel()
	for c in e.combatants():
		if c.team == 1:
			c.sheet.take_damage(1000)
	assert_true(e.check_end())
	assert_eq(e.winning_team, 0)
	assert_false(e.add_combatant(_c("late", 1)))

extends TestCase


func _c(combatant_id: String, dex: int = 10, team: int = 0) -> Combatant:
	var s := CharacterSheet.new()
	s.name = combatant_id
	s.abilities.set_score(Ability.Type.DEX, dex)
	s.max_hp = 10
	s.current_hp = 10
	return Combatant.from_sheet(combatant_id, s, team)


func _ids(t: InitiativeTracker) -> Array[String]:
	var out: Array[String] = []
	for c in t.order():
		out.append(c.id)
	return out


## A(20) B(10) C(5), begun, A current.
func _abc() -> InitiativeTracker:
	var t := InitiativeTracker.new()
	t.insert_with_initiative(_c("B"), 10)
	t.insert_with_initiative(_c("A"), 20)
	t.insert_with_initiative(_c("C"), 5)
	t.begin()
	return t


func test_rolled_order_is_descending() -> void:
	var t := InitiativeTracker.new()
	var rng := Rng.new(77)
	for i in range(8):
		assert_true(t.add(_c("c%d" % i, 8 + i), rng))
	var order := t.order()
	assert_eq(order.size(), 8)
	for i in range(order.size() - 1):
		assert_true(order[i].initiative >= order[i + 1].initiative, "position %d" % i)


func test_rolled_initiative_uses_dex_modifier() -> void:
	var t := InitiativeTracker.new()
	var c := _c("quick", 18)
	t.add(c, Rng.new(5))
	assert_in_range(c.initiative, 1 + 4, 20 + 4)


func test_tie_broken_by_dex_then_join_order() -> void:
	var t := InitiativeTracker.new()
	t.insert_with_initiative(_c("slow", 10), 12)
	t.insert_with_initiative(_c("fast", 16), 12)
	t.insert_with_initiative(_c("first", 8), 12)
	t.insert_with_initiative(_c("second", 8), 12)
	assert_eq(_ids(t), ["fast", "slow", "first", "second"])


func test_advance_cycles_and_counts_rounds() -> void:
	var t := _abc()
	assert_eq(t.current().id, "A")
	assert_eq(t.round_number, 1)
	assert_eq(t.advance().id, "B")
	assert_eq(t.advance().id, "C")
	assert_eq(t.advance().id, "A")
	assert_eq(t.round_number, 2)


func test_advance_skips_dead() -> void:
	var t := _abc()
	t.get_combatant("B").sheet.take_damage(100)
	assert_eq(t.advance().id, "C")
	assert_eq(t.advance().id, "A")


func test_mid_combat_join_before_current_waits_a_round() -> void:
	var t := _abc()
	t.advance()  # B is current
	t.insert_with_initiative(_c("D"), 15, true)
	assert_eq(t.current().id, "B", "current actor unchanged")
	assert_eq(t.advance().id, "C")
	assert_eq(t.advance().id, "A")
	assert_eq(t.advance().id, "D")
	assert_eq(t.advance().id, "B")


func test_mid_combat_join_after_current_waits_a_round() -> void:
	var t := _abc()
	t.insert_with_initiative(_c("D"), 8, true)
	assert_eq(_ids(t), ["A", "B", "D", "C"])
	assert_eq(t.advance().id, "B")
	assert_eq(t.advance().id, "C", "D skipped in the round it joined")
	assert_eq(t.advance().id, "A")
	assert_eq(t.advance().id, "B")
	assert_eq(t.advance().id, "D")


func test_remove_current_and_earlier() -> void:
	var t := _abc()
	t.advance()  # B
	assert_true(t.remove("B"))
	assert_eq(t.current().id, "C")
	assert_true(t.remove("A"))
	assert_eq(t.current().id, "C")
	assert_false(t.remove("nobody"))
	assert_eq(t.size(), 1)


func test_duplicate_ids_rejected() -> void:
	var t := InitiativeTracker.new()
	assert_true(t.insert_with_initiative(_c("x"), 5))
	assert_false(t.insert_with_initiative(_c("x"), 9))
	assert_eq(t.size(), 1)

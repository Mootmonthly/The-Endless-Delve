extends TestCase


func _draws(r: Rng, n: int) -> Array[int]:
	var out: Array[int] = []
	for _i in range(n):
		out.append(r.next_int(1, 1000000))
	return out


func test_same_seed_same_sequence() -> void:
	assert_eq(_draws(Rng.new(42), 50), _draws(Rng.new(42), 50))


func test_different_seeds_differ() -> void:
	assert_ne(_draws(Rng.new(1), 20), _draws(Rng.new(2), 20))


func test_next_int_range_is_inclusive() -> void:
	var r := Rng.new(7)
	var seen_lo := false
	var seen_hi := false
	for _i in range(1000):
		var v := r.next_int(1, 6)
		assert_in_range(v, 1, 6)
		seen_lo = seen_lo or v == 1
		seen_hi = seen_hi or v == 6
	assert_true(seen_lo, "1 should appear in 1000 d6 rolls")
	assert_true(seen_hi, "6 should appear in 1000 d6 rolls")


func test_next_float_in_unit_interval() -> void:
	var r := Rng.new(99)
	for _i in range(1000):
		var f := r.next_float()
		assert_true(f >= 0.0 and f < 1.0, "float %f out of [0, 1)" % f)


func test_fork_is_deterministic() -> void:
	assert_eq(_draws(Rng.new(5).fork(3), 20), _draws(Rng.new(5).fork(3), 20))


func test_fork_differs_from_parent_and_siblings() -> void:
	var parent := Rng.new(5)
	assert_ne(_draws(parent.fork(1), 20), _draws(Rng.new(5), 20), "child vs parent")
	assert_ne(_draws(parent.fork(1), 20), _draws(parent.fork(2), 20), "sibling streams")


func test_fork_ignores_parent_draw_count() -> void:
	var a := Rng.new(11)
	var b := Rng.new(11)
	_draws(b, 10)
	assert_eq(a.fork(4).seed_value, b.fork(4).seed_value)


func test_state_round_trip_replays() -> void:
	var r := Rng.new(123)
	_draws(r, 5)
	var saved := r.state()
	var first := _draws(r, 10)
	r.set_state(saved)
	assert_eq(_draws(r, 10), first)
	assert_eq(r.seed_value, 123)

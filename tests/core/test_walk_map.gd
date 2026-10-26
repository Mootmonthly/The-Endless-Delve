extends TestCase

const NONE := {}


func _map(rows: Array[String]) -> WalkMap:
	return WalkMap.from_rows(rows)


func _open(w: int, h: int) -> WalkMap:
	return WalkMap.new(w, h, true)


func _assert_valid_path(m: WalkMap, start: Vector2i, path: Array[Vector2i], occupied: Dictionary) -> void:
	var cursor := start
	for step in path:
		assert_true(m.can_step(cursor, step, occupied), "illegal step %s -> %s" % [cursor, step])
		cursor = step


func test_rows_round_trip_and_padding() -> void:
	var m := _map(["#..#", "#.", "####"])
	assert_eq(m.width, 4)
	assert_eq(m.height, 3)
	assert_true(m.is_walkable(Vector2i(1, 0)))
	assert_false(m.is_walkable(Vector2i(0, 0)))
	assert_false(m.is_walkable(Vector2i(3, 1)), "short rows are padded with walls")
	assert_false(m.is_walkable(Vector2i(9, 9)), "out of bounds is not walkable")
	assert_eq(m.to_rows(), ["#..#", "#.##", "####"])
	assert_eq(_map(["#AS.#"]).to_rows(), ["#...#"], "every non-'#' char is floor")
	m.set_walkable(Vector2i(0, 0), true)
	assert_true(m.is_walkable(Vector2i(0, 0)))
	assert_eq(WalkMap.from_dict(m.to_dict()).to_rows(), m.to_rows())


func test_can_step_rules() -> void:
	var m := _open(4, 4)
	assert_true(m.can_step(Vector2i(1, 1), Vector2i(2, 2), NONE))
	assert_false(m.can_step(Vector2i(1, 1), Vector2i(3, 1), NONE), "two tiles is not a step")
	assert_false(m.can_step(Vector2i(1, 1), Vector2i(1, 1), NONE), "standing still is not a step")
	assert_false(m.can_step(Vector2i(0, 0), Vector2i(-1, 0), NONE), "out of bounds")
	assert_false(m.can_step(Vector2i(1, 1), Vector2i(2, 1), {Vector2i(2, 1): true}), "occupied")


func test_no_corner_cutting() -> void:
	# (1,0) is a wall: the diagonal (0,0)->(1,1) would cut its corner.
	var m := _map([".#.", "...", "..."])
	assert_false(m.can_step(Vector2i(0, 0), Vector2i(1, 1), NONE))
	assert_false(m.can_step(Vector2i(2, 0), Vector2i(1, 1), NONE))
	assert_true(m.can_step(Vector2i(0, 1), Vector2i(1, 2), NONE))
	assert_true(m.can_step(Vector2i(0, 0), Vector2i(0, 1), NONE))


func test_reachable_respects_budget() -> void:
	var m := _open(7, 7)
	var centre := Vector2i(3, 3)
	assert_eq(m.reachable(centre, 0, NONE).size(), 1, "only the start")
	assert_eq(m.reachable(centre, 1, NONE).size(), 9)
	var two := m.reachable(centre, 2, NONE)
	assert_eq(two.size(), 25)
	assert_eq(two[Vector2i(5, 5)], 2)
	assert_eq(two[centre], 0)
	assert_false(two.has(Vector2i(6, 6)))


func test_reachable_blocked_by_walls_and_creatures() -> void:
	var m := _map(["...", "###", "..."])
	assert_eq(m.reachable(Vector2i(0, 0), 10, NONE).size(), 3)
	var open := _open(3, 1)
	assert_eq(open.reachable(Vector2i(0, 0), 5, {Vector2i(1, 0): true}).size(), 1, "a creature blocks the corridor")


func test_path_goes_around_walls() -> void:
	var m := _map(["..#..", "..#..", "....."])
	var path := m.path_to(Vector2i(0, 0), Vector2i(4, 0), NONE)
	assert_eq(path.size(), 6, "around the wall without cutting corners")
	assert_eq(path[path.size() - 1], Vector2i(4, 0))
	_assert_valid_path(m, Vector2i(0, 0), path, NONE)
	assert_eq(m.path_to(Vector2i(0, 0), Vector2i(4, 0), NONE), path, "deterministic")


func test_path_to_occupied_goal_ends_adjacent() -> void:
	var m := _open(6, 3)
	var goal := Vector2i(5, 0)
	var occupied := {goal: true}
	var path := m.path_to(Vector2i(0, 0), goal, occupied)
	assert_eq(path.size(), 4)
	assert_true(GridMath.is_adjacent(path[path.size() - 1], goal))
	assert_false(path.has(goal))
	_assert_valid_path(m, Vector2i(0, 0), path, occupied)
	assert_eq(m.path_to(Vector2i(4, 1), goal, occupied).size(), 0, "already adjacent")


func test_path_edge_cases() -> void:
	var m := _map(["..#..", "..#..", "..#.."])
	assert_eq(m.path_to(Vector2i(0, 0), Vector2i(4, 0), NONE).size(), 0, "walled off")
	assert_eq(m.path_to(Vector2i(0, 0), Vector2i(0, 0), NONE).size(), 0, "start == goal")
	var open := _open(8, 1)
	assert_eq(open.path_to(Vector2i(0, 0), Vector2i(7, 0), NONE, 3).size(), 0, "longer than max_len")
	assert_eq(open.path_to(Vector2i(0, 0), Vector2i(3, 0), NONE, 3).size(), 3)


func test_cropped_to_blocks_outside() -> void:
	var m := _open(5, 5).cropped_to(Rect2i(1, 1, 3, 3))
	assert_eq(m.width, 5)
	assert_true(m.is_walkable(Vector2i(2, 2)))
	assert_false(m.is_walkable(Vector2i(0, 2)))
	assert_eq(m.walkable_count(), 9)

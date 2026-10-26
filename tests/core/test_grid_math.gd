extends TestCase


func test_distance_is_chebyshev() -> void:
	assert_eq(GridMath.distance_tiles(Vector2i(0, 0), Vector2i(0, 0)), 0)
	assert_eq(GridMath.distance_tiles(Vector2i(0, 0), Vector2i(3, 0)), 3)
	assert_eq(GridMath.distance_tiles(Vector2i(0, 0), Vector2i(3, 3)), 3, "diagonals cost 1")
	assert_eq(GridMath.distance_tiles(Vector2i(2, 5), Vector2i(-1, 1)), 4)


func test_adjacency_includes_diagonals_not_self() -> void:
	var p := Vector2i(4, 4)
	assert_true(GridMath.is_adjacent(p, Vector2i(5, 5)))
	assert_true(GridMath.is_adjacent(p, Vector2i(4, 3)))
	assert_false(GridMath.is_adjacent(p, p), "not adjacent to itself")
	assert_false(GridMath.is_adjacent(p, Vector2i(6, 4)))


func test_neighbors8_order_orthogonal_first() -> void:
	var n := GridMath.neighbors8(Vector2i(1, 1))
	assert_eq(n.size(), 8)
	assert_eq(n[0], Vector2i(1, 0))
	assert_eq(n[1], Vector2i(2, 1))
	assert_eq(n[2], Vector2i(1, 2))
	assert_eq(n[3], Vector2i(0, 1))
	for q in n:
		assert_true(GridMath.is_adjacent(Vector2i(1, 1), q))


func test_vec_array_round_trip() -> void:
	var v := Vector2i(7, -3)
	assert_eq(GridMath.vec_to_arr(v), [7, -3])
	assert_eq(GridMath.arr_to_vec(GridMath.vec_to_arr(v)), v)
	assert_eq(GridMath.arr_to_vec(JSON.parse_string("[4.0, 9.0]")), Vector2i(4, 9), "JSON floats")
	assert_true(GridMath.is_vec_arr([1, 2]))
	assert_false(GridMath.is_vec_arr([1]))
	assert_false(GridMath.is_vec_arr(["a", 2]))
	assert_false(GridMath.is_vec_arr("1,2"))
	assert_eq(GridMath.arr_to_vec("junk"), Vector2i.ZERO)


func test_rect_and_list_helpers() -> void:
	var r := Rect2i(1, 2, 3, 4)
	assert_eq(GridMath.rect_to_arr(r), [1, 2, 3, 4])
	assert_eq(GridMath.arr_to_rect([1, 2, 3, 4]), r)
	assert_eq(GridMath.arr_to_rect([1, 2]), Rect2i())
	var pts: Array[Vector2i] = [Vector2i(1, 1), Vector2i(2, 3)]
	assert_eq(GridMath.vec_list_to_arr(pts), [[1, 1], [2, 3]])
	assert_eq(GridMath.arr_to_vec_list([[1, 1], "bad", [2, 3]]), pts)
	assert_eq(GridMath.feet_to_tiles(30), 6)
	assert_eq(GridMath.feet_to_tiles(25), 5)

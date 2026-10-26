extends TestCase

const ROWS: Array[String] = [
	"##########",
	"#A...#...#",
	"#....#...#",
	"#........#",
	"#....#..S#",
	"##########",
]


func _floor() -> FloorData:
	var f := FloorData.new()
	f.id = "test_floor"
	f.display_name = "Test Floor"
	f.walk_map = WalkMap.from_rows(ROWS)
	f.arrival = Vector2i(1, 1)
	f.stairs = Vector2i(8, 4)
	var z := EncounterZoneData.new()
	z.id = "z1"
	z.rect = Rect2i(6, 1, 3, 3)
	z.monster_ids = ["goblin", "giant_rat"]
	z.spawn_points = [Vector2i(7, 1), Vector2i(7, 2)]
	f.encounter_zones.append(z)
	return f


func _assert_problem(f: FloorData, needle: String) -> void:
	var problems := f.validate()
	for p in problems:
		if p.contains(needle):
			return
	fail("expected a problem containing '%s', got %s" % [needle, str(problems)])


func test_valid_floor_has_no_problems() -> void:
	assert_eq(_floor().validate(), [])


func test_arrival_and_stairs_checks() -> void:
	var f := _floor()
	f.arrival = Vector2i(0, 0)
	_assert_problem(f, "arrival (0, 0) is not walkable")
	f = _floor()
	f.stairs = Vector2i(20, 1)
	_assert_problem(f, "stairs (20, 1) is out of bounds")
	f = _floor()
	f.stairs = f.arrival
	_assert_problem(f, "same tile")


func test_unreachable_stairs() -> void:
	var f := _floor()
	f.walk_map.set_walkable(Vector2i(5, 3), false)
	_assert_problem(f, "not reachable")


func test_zone_checks() -> void:
	var f := _floor()
	f.encounter_zones[0].rect = Rect2i(8, 1, 5, 2)
	_assert_problem(f, "out of bounds")
	f = _floor()
	f.encounter_zones[0].spawn_points[1] = Vector2i(2, 2)
	_assert_problem(f, "outside its rect")
	f = _floor()
	f.encounter_zones[0].rect = Rect2i(4, 1, 4, 3)
	f.encounter_zones[0].spawn_points[1] = Vector2i(5, 2)
	_assert_problem(f, "(5, 2) is not walkable")
	f = _floor()
	f.encounter_zones[0].spawn_points.resize(1)
	_assert_problem(f, "only 1 spawn points")
	f = _floor()
	f.encounter_zones[0].spawn_points[1] = Vector2i(7, 1)
	_assert_problem(f, "listed twice")
	f = _floor()
	f.encounter_zones.append(f.encounter_zones[0])
	_assert_problem(f, "duplicate zone id")
	f = _floor()
	f.encounter_zones[0].monster_ids.clear()
	_assert_problem(f, "no monsters")


func test_dict_round_trip_through_json() -> void:
	var f := _floor()
	var data: Dictionary = JSON.parse_string(JSON.stringify(f.to_dict()))
	var copy := FloorData.from_dict(data)
	assert_eq(copy.to_dict(), f.to_dict())
	assert_eq(copy.encounter_zones[0].spawn_points, f.encounter_zones[0].spawn_points)
	assert_eq(copy.encounter_zones[0].rect, Rect2i(6, 1, 3, 3))
	assert_eq(copy.validate(), [])
	assert_eq(copy.get_zone("z1").monster_ids, ["goblin", "giant_rat"])
	assert_eq(copy.zone_at(Vector2i(7, 2)).id, "z1")
	assert_null(copy.zone_at(Vector2i(1, 1)))

extends TestCase

const FLOOR_001 := "res://floors/floor_001.json"


func _tiny() -> Dictionary:
	return {
		"schema_version": 1, "id": "tiny", "display_name": "Tiny",
		"rows": ["######", "#A...#", "#..#S#", "######"],
		"arrival": [1, 1], "stairs": [4, 2],
		"encounter_zones": [{"id": "z", "rect": [2, 1, 3, 2], "monster_ids": ["goblin"], "spawn_points": [[3, 1]]}],
	}


func test_floor_001_loads_and_validates() -> void:
	var f := FloorFile.load(FLOOR_001)
	assert_not_null(f)
	if f == null:
		return
	assert_eq(f.id, "floor_001")
	assert_eq(f.display_name, "The Threshold")
	assert_eq(f.validate(), [] as Array[String])


func test_floor_001_layout() -> void:
	var f := FloorFile.load(FLOOR_001)
	if f == null:
		fail("floor_001 did not load")
		return
	assert_eq(f.walk_map.width, 48)
	assert_eq(f.walk_map.height, 32)
	assert_eq(f.arrival, Vector2i(5, 5))
	assert_eq(f.stairs, Vector2i(42, 26))
	assert_eq(f.encounter_zones.size(), 2)
	var z1: EncounterZoneData = f.encounter_zones[0]
	var z2: EncounterZoneData = f.encounter_zones[1]
	assert_eq(z1.id, "z1")
	assert_eq(z1.rect, Rect2i(17, 2, 12, 9))
	assert_eq(z1.monster_ids, ["goblin", "goblin", "giant_rat"] as Array[String])
	assert_eq(z1.spawn_points.size(), 3)
	assert_eq(z2.monster_ids, ["skeleton", "skeleton", "zombie"] as Array[String])


func test_floor_001_monsters_exist_in_data() -> void:
	var f := FloorFile.load(FLOOR_001)
	if f == null:
		fail("floor_001 did not load")
		return
	var monsters := ContentLoader.load_monsters()
	for zone in f.encounter_zones:
		assert_eq(zone.monster_ids.size(), zone.spawn_points.size(), "zone %s: one spawn point per monster" % zone.id)
		for mid in zone.monster_ids:
			assert_true(monsters.has(mid), "unknown monster id '%s'" % mid)


func test_floor_001_stairs_need_zone_1() -> void:
	var f := FloorFile.load(FLOOR_001)
	if f == null:
		fail("floor_001 did not load")
		return
	assert_false(f.walk_map.path_to(f.arrival, f.stairs, {}).is_empty(), "stairs reachable")
	# Treat every zone-1 tile as occupied: the stairs must then be unreachable.
	var blocked := {}
	var r: Rect2i = f.encounter_zones[0].rect
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			blocked[Vector2i(x, y)] = true
	assert_true(f.walk_map.path_to(f.arrival, f.stairs, blocked).is_empty(),
			"stairs must only be reachable through zone 1")


func test_tiny_floor_from_dict() -> void:
	var f := FloorFile.from_dict(_tiny())
	assert_not_null(f)
	if f == null:
		return
	assert_eq(f.walk_map.width, 6)
	assert_eq(f.walk_map.height, 4)
	assert_true(f.walk_map.is_walkable(Vector2i(1, 1)), "'A' is floor")
	assert_true(f.walk_map.is_walkable(Vector2i(4, 2)), "'S' is floor")
	assert_false(f.walk_map.is_walkable(Vector2i(3, 2)))
	assert_eq(f.encounter_zones[0].spawn_points, [Vector2i(3, 1)] as Array[Vector2i])
	assert_eq(f.validate(), [] as Array[String])


func test_tiny_floor_survives_json_round_trip() -> void:
	var parsed: Variant = JSON.parse_string(JSON.stringify(_tiny()))
	var f := FloorFile.from_dict(parsed as Dictionary)
	assert_not_null(f)
	if f != null:
		assert_eq(f.arrival, Vector2i(1, 1))
		assert_eq(f.encounter_zones[0].rect, Rect2i(2, 1, 3, 2))


func test_structural_problems() -> void:
	assert_eq(FloorFile.structural_problems(_tiny()), [] as Array[String])
	var mutations: Array[Callable] = [
		func(d: Dictionary) -> void: d["schema_version"] = 2,
		func(d: Dictionary) -> void: d.erase("id"),
		func(d: Dictionary) -> void: d["rows"] = [],
		func(d: Dictionary) -> void: (d["rows"] as Array)[1] = "#A..#",
		func(d: Dictionary) -> void: (d["rows"] as Array)[1] = "#A.x.#",
		func(d: Dictionary) -> void: d["arrival"] = [2, 1],
		func(d: Dictionary) -> void: d["stairs"] = "4,2",
		func(d: Dictionary) -> void: (d["encounter_zones"] as Array)[0]["rect"] = [1, 2, 3],
		func(d: Dictionary) -> void: (d["encounter_zones"] as Array)[0]["spawn_points"] = [[1]],
		func(d: Dictionary) -> void: (d["encounter_zones"] as Array).append({"id": "z", "rect": [1, 1, 1, 1]}),
	]
	for i in range(mutations.size()):
		var d := _tiny()
		mutations[i].call(d)
		assert_false(FloorFile.structural_problems(d).is_empty(), "mutation %d should be reported" % i)


func test_missing_file_returns_null() -> void:
	assert_null(FloorFile.load("res://floors/does_not_exist.json"))

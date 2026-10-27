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
	assert_eq(f.schema_version, 2)
	assert_eq(f.validate(ContentLoader.load_loot_tables("res://data/loot")), [] as Array[String])


func test_floor_001_layout() -> void:
	var f := FloorFile.load(FLOOR_001)
	if f == null:
		fail("floor_001 did not load")
		return
	assert_eq(f.walk_map.width, 112)
	assert_eq(f.walk_map.height, 80)
	assert_eq(f.landings.size(), 4)
	assert_eq(f.arrival, f.landings[0].position, "arrival is the first landing")
	assert_eq(f.stairs, Vector2i(56, 40), "the stairs stand in the middle")
	var z1: EncounterZoneData = f.get_zone("z1")
	assert_not_null(z1)
	if z1 != null:
		assert_eq(z1.monster_ids, ["giant_rat"] as Array[String], "the first landing's pack is a giant rat")
		assert_false(z1.optional)
	var guard := f.stairs_zone()
	assert_not_null(guard)
	if guard != null:
		assert_true(guard.guards_stairs)
	assert_true(f.doors.size() > 0, "doors")
	assert_true(f.props.size() > 0, "props")


func test_floor_001_monsters_exist_in_data() -> void:
	var f := FloorFile.load(FLOOR_001)
	if f == null:
		fail("floor_001 did not load")
		return
	var monsters := ContentLoader.load_monsters()
	for zone in f.encounter_zones:
		assert_true(zone.spawn_points.size() >= zone.monster_ids.size(), "zone %s: at least one spawn point per monster" % zone.id)
		for mid in zone.monster_ids:
			assert_true(monsters.has(mid), "unknown monster id '%s'" % mid)


func test_floor_001_stairs_need_zone_1() -> void:
	var f := FloorFile.load(FLOOR_001)
	if f == null:
		fail("floor_001 did not load")
		return
	assert_false(f.walk_map.path_to(f.arrival, f.stairs, {}).is_empty(), "stairs reachable")
	# Treat every zone-1 tile as occupied: the stairs must then be unreachable
	# from the first landing (its own pack guards the only way out).
	var blocked := {}
	var r: Rect2i = f.get_zone("z1").rect
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


func test_optional_fields_are_checked_and_parsed() -> void:
	var d := _tiny()
	d["floor_number"] = 2
	d["theme"] = "flooded halls"
	d["budget"] = {"level": 1, "min": "easy", "max": "medium"}
	(d["encounter_zones"] as Array)[0]["boss"] = true
	(d["encounter_zones"] as Array)[0]["kind"] = "boss"
	assert_eq(FloorFile.structural_problems(d), [] as Array[String])
	var f := FloorFile.from_dict(JSON.parse_string(JSON.stringify(d)))
	assert_not_null(f)
	if f != null:
		assert_eq(f.floor_number, 2)
		assert_eq(f.theme, "flooded halls")
		assert_true(f.encounter_zones[0].boss)
		assert_eq(f.encounter_zones[0].kind, "boss")
	var mutations: Array[Callable] = [
		func(m: Dictionary) -> void: m["floor_number"] = -1,
		func(m: Dictionary) -> void: m["floor_number"] = "2",
		func(m: Dictionary) -> void: m["theme"] = 5,
		func(m: Dictionary) -> void: (m["encounter_zones"] as Array)[0]["boss"] = "yes",
		func(m: Dictionary) -> void: (m["encounter_zones"] as Array)[0]["kind"] = "horde",
	]
	for i in range(mutations.size()):
		var m := _tiny()
		mutations[i].call(m)
		assert_false(FloorFile.structural_problems(m).is_empty(), "optional-field mutation %d should be reported" % i)


## A minimal valid v2 floor file (see tests/core/test_floor_v2.gd for the rules).
func _tiny_v2() -> Dictionary:
	return {
		"schema_version": 2, "id": "tiny2", "display_name": "Tiny 2",
		"rows": ["##########", "#A.......#", "#.######.#", "#.#....#.#", "#.D..S.#L#", "#.#....#.#", "##########"],
		"landings": [{"id": "nw", "position": [1, 1], "facing": "east"}, {"id": "e", "position": [8, 4]}],
		"stairs": [5, 4],
		"encounter_zones": [{"id": "z1", "rect": [3, 3, 4, 3], "monster_ids": ["goblin"], "spawn_points": [[6, 3]],
			"guards_stairs": true, "respawns": true, "optional": false, "name": "stair room"}],
		"chests": [{"id": "c1", "position": [6, 5], "table": "starter_gear"}],
		"doors": [{"id": "d1", "position": [2, 4], "state": "closed"}],
		"props": [{"id": "p1", "kind": "barrel", "position": [3, 5], "hp": 4, "blocks": true}],
		"respawn": {"pack_seconds": 600, "boss_seconds": 1800},
		"theme_style": {"darkness": "#202020"},
		"generated_by": "by hand",
	}


func test_v2_file_loads() -> void:
	assert_eq(FloorFile.structural_problems(_tiny_v2()), [] as Array[String])
	var f := FloorFile.from_dict(JSON.parse_string(JSON.stringify(_tiny_v2())))
	assert_not_null(f)
	if f == null:
		return
	assert_eq(f.schema_version, 2)
	assert_eq(f.arrival, Vector2i(1, 1))
	assert_eq(f.landings.size(), 2)
	assert_eq(f.doors.size(), 1)
	assert_eq(f.props.size(), 1)
	assert_eq(f.encounter_zones[0].name, "stair room")
	assert_true(f.walk_map.is_walkable(Vector2i(8, 4)), "'L' is floor")
	assert_true(f.walk_map.is_walkable(Vector2i(2, 4)), "'D' is floor")
	assert_eq(f.validate(), [] as Array[String])
	var with_arrival := _tiny_v2()
	with_arrival["arrival"] = [1, 1]
	assert_eq(FloorFile.structural_problems(with_arrival), [] as Array[String], "arrival may repeat landings[0]")


func test_v2_structural_problems() -> void:
	var mutations: Array[Callable] = [
		func(d: Dictionary) -> void: d.erase("landings"),
		func(d: Dictionary) -> void: d["landings"] = [],
		func(d: Dictionary) -> void: d["landings"] = [{"id": "nw", "position": [1]}],
		func(d: Dictionary) -> void: d["landings"] = [{"position": [1, 1]}],
		func(d: Dictionary) -> void: (d["landings"] as Array)[0]["facing"] = "up",
		func(d: Dictionary) -> void: d["arrival"] = [8, 4],
		func(d: Dictionary) -> void: (d["rows"] as Array)[1] = "#L.......#",
		func(d: Dictionary) -> void: (d["rows"] as Array)[1] = "#A..D....#",
		func(d: Dictionary) -> void: (d["rows"] as Array)[1] = "#A..x....#",
		func(d: Dictionary) -> void: d["doors"] = {},
		func(d: Dictionary) -> void: (d["doors"] as Array)[0]["state"] = "ajar",
		func(d: Dictionary) -> void: (d["doors"] as Array)[0]["dc"] = -2,
		func(d: Dictionary) -> void: (d["doors"] as Array)[0]["key_item"] = 7,
		func(d: Dictionary) -> void: (d["doors"] as Array)[0].erase("position"),
		func(d: Dictionary) -> void: d["props"] = "barrel",
		func(d: Dictionary) -> void: (d["props"] as Array)[0]["kind"] = "statue",
		func(d: Dictionary) -> void: (d["props"] as Array)[0]["hp"] = 0,
		func(d: Dictionary) -> void: (d["props"] as Array)[0]["blocks"] = "yes",
		func(d: Dictionary) -> void: (d["props"] as Array)[0]["loot_table"] = 3,
		func(d: Dictionary) -> void: (d["props"] as Array)[0].erase("id"),
		func(d: Dictionary) -> void: d["respawn"] = 600,
		func(d: Dictionary) -> void: d["respawn"] = {"pack_seconds": -1},
		func(d: Dictionary) -> void: d["theme_style"] = "dark",
		func(d: Dictionary) -> void: (d["encounter_zones"] as Array)[0]["guards_stairs"] = "yes",
		func(d: Dictionary) -> void: (d["encounter_zones"] as Array)[0]["respawns"] = 1,
		func(d: Dictionary) -> void: (d["encounter_zones"] as Array)[0]["optional"] = "no",
		func(d: Dictionary) -> void: (d["encounter_zones"] as Array)[0]["name"] = 5,
		func(d: Dictionary) -> void: d["schema_version"] = 3,
	]
	for i in range(mutations.size()):
		var d := _tiny_v2()
		mutations[i].call(d)
		assert_false(FloorFile.structural_problems(d).is_empty(), "v2 mutation %d should be reported" % i)


func test_v1_rows_reject_v2_markers() -> void:
	var d := _tiny()
	(d["rows"] as Array)[1] = "#AL..#"
	assert_false(FloorFile.structural_problems(d).is_empty(), "'L' is not a v1 tile")
	d = _tiny()
	(d["rows"] as Array)[1] = "#A.D.#"
	assert_false(FloorFile.structural_problems(d).is_empty(), "'D' is not a v1 tile")


func test_every_set_floor_is_version_2() -> void:
	for floor_id in FloorFile.set_floor_ids(FloorFile.load_set("res://floors/set_01.json")):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(FloorFile.floor_path(floor_id)))
		assert_eq(typeof(parsed), TYPE_DICTIONARY)
		if typeof(parsed) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = parsed
		assert_eq(FloorFile.structural_problems(d), [] as Array[String], "%s is well formed" % floor_id)
		assert_eq(DictUtil.to_int(d.get("schema_version"), 0), 2, "%s schema" % floor_id)
		assert_true(str(d.get("generated_by", "")).begins_with("tools/gen_floor.py"), "%s records its generator" % floor_id)


func test_floor_path() -> void:
	assert_eq(FloorFile.floor_path("floor_002"), "res://floors/floor_002.json")
	assert_eq(FloorFile.floor_path("floor_001"), FLOOR_001)


func _manifest() -> Dictionary:
	return {"schema_version": 1, "id": "set_x", "display_name": "Test Set", "theme": "t",
		"floors": ["floor_a", "floor_b"]}


func test_set_manifest_shape() -> void:
	assert_eq(FloorFile.set_problems(_manifest()), [] as Array[String])
	assert_eq(FloorFile.set_floor_ids(_manifest()), ["floor_a", "floor_b"] as Array[String])
	var mutations: Array[Callable] = [
		func(m: Dictionary) -> void: m["schema_version"] = 2,
		func(m: Dictionary) -> void: m.erase("id"),
		func(m: Dictionary) -> void: m["floors"] = [],
		func(m: Dictionary) -> void: m.erase("floors"),
		func(m: Dictionary) -> void: m["floors"] = ["floor_a", 3],
		func(m: Dictionary) -> void: m["floors"] = ["floor_a", "floor_a"],
		func(m: Dictionary) -> void: m["theme"] = [],
	]
	for i in range(mutations.size()):
		var m := _manifest()
		mutations[i].call(m)
		assert_false(FloorFile.set_problems(m).is_empty(), "set mutation %d should be reported" % i)


func test_load_set_reads_a_manifest_file() -> void:
	var path := "user://test_floor_file_set.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(_manifest()))
	file.close()
	var loaded := FloorFile.load_set(path)
	assert_eq(str(loaded.get("id", "")), "set_x")
	assert_eq(FloorFile.set_floor_ids(loaded), ["floor_a", "floor_b"] as Array[String])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	assert_eq(FloorFile.load_set("res://floors/does_not_exist.json"), {})

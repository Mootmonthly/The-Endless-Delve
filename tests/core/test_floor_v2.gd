extends TestCase
## Floor file v2 in FloorData: landings, doors, props, respawn, guarded stairs
## and every validation rule (each with a failing case). See docs/gdd.md 5.2.2.

## 10x7: landings A (1, 1) and L (8, 4) on the edge, a door D (2, 4) into the
## stairs room (zone z1 = x 3..6, y 3..5) with the stairs S (5, 4).
const ROWS: Array[String] = [
	"##########",
	"#A.......#",
	"#.######.#",
	"#.#....#.#",
	"#.D..S.#L#",
	"#.#....#.#",
	"##########",
]


func _dict() -> Dictionary:
	return {
		"schema_version": 2, "id": "v2", "display_name": "V2",
		"rows": ROWS.duplicate(),
		"landings": [{"id": "nw", "position": [1, 1], "facing": "east"}, {"id": "e", "position": [8, 4], "facing": "north"}],
		"stairs": [5, 4],
		"encounter_zones": [{"id": "z1", "rect": [3, 3, 4, 3], "monster_ids": ["goblin"], "spawn_points": [[6, 3]],
			"guards_stairs": true}],
		"chests": [{"id": "c1", "position": [6, 5], "table": "starter_gear"}],
		"doors": [{"id": "d1", "position": [2, 4], "state": "closed"}],
		"props": [
			{"id": "p1", "kind": "barrel", "position": [3, 5], "hp": 4, "blocks": true, "loot_table": "monster_small"},
			{"id": "p2", "kind": "bones", "position": [1, 3], "hp": 2, "blocks": false},
		],
		"respawn": {"pack_seconds": 600, "boss_seconds": 1800},
		"theme_style": {"darkness": "#202020"},
	}


func _floor() -> FloorData:
	return FloorData.from_dict(_dict())


func _assert_problem(f: FloorData, needle: String, loot: Dictionary = {}) -> void:
	var problems := f.validate(loot)
	for p in problems:
		if p.contains(needle):
			assert_true(true)
			return
	fail("expected a problem containing '%s', got %s" % [needle, str(problems)])


func test_valid_v2_floor() -> void:
	var f := _floor()
	assert_eq(f.schema_version, 2)
	assert_eq(f.validate(), [] as Array[String])
	assert_eq(f.landings.size(), 2)
	assert_eq(f.arrival, Vector2i(1, 1), "arrival is landings[0] when the file omits it")
	assert_eq(f.get_landing("e").facing, LandingData.FACING_NORTH)
	assert_eq(f.landing_positions(), [Vector2i(1, 1), Vector2i(8, 4)] as Array[Vector2i])
	assert_eq(f.door_at(Vector2i(2, 4)).id, "d1")
	assert_eq(f.get_door("d1").state, DoorData.STATE_CLOSED)
	assert_eq(f.prop_at(Vector2i(3, 5)).kind, PropData.KIND_BARREL)
	assert_eq(f.get_prop("p2").blocks, false)
	assert_eq(f.respawn_pack_seconds, 600)
	assert_eq(f.respawn_boss_seconds, 1800)
	assert_eq(str(f.theme_style.get("darkness")), "#202020")
	assert_eq(f.stairs_zone().id, "z1")
	assert_true(f.stairs_zone().guards_stairs)
	assert_true(f.stairs_zone().respawns, "zones respawn by default")


func test_v2_validates_against_loot_tables() -> void:
	var loot := ContentLoader.load_loot_tables("res://data/loot")
	assert_eq(_floor().validate(loot), [] as Array[String])
	var f := _floor()
	f.props[0].loot_table = "no_such_table"
	_assert_problem(f, "unknown loot table 'no_such_table'", loot)


func test_v1_floors_load_as_one_landing() -> void:
	var f := FloorData.from_dict({"schema_version": 1, "id": "old", "rows": ["#####", "#A.S#", "#####"],
		"arrival": [1, 1], "stairs": [3, 1]})
	assert_eq(f.schema_version, 1)
	assert_eq(f.landings.size(), 0, "a v1 floor keeps no landing list")
	assert_eq(f.get_landings().size(), 1)
	assert_eq(f.get_landings()[0].id, LandingData.ARRIVAL_ID)
	assert_eq(f.get_landings()[0].position, Vector2i(1, 1))
	assert_eq(f.validate(), [] as Array[String], "v1 rules: no guard or edge landing needed")
	assert_eq(f.static_blockers(), [] as Array[Vector2i])
	var d := f.to_dict()
	assert_eq(int(d["schema_version"]), 1, "to_dict keeps the source schema")
	assert_eq((d["landings"] as Array).size(), 1)


func test_round_trip_through_json() -> void:
	var f := _floor()
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(f.to_dict()))
	var copy := FloorData.from_dict(parsed)
	assert_eq(copy.to_dict(), f.to_dict())
	assert_eq(copy.validate(), [] as Array[String])
	assert_eq(copy.doors[0].position, Vector2i(2, 4))
	assert_eq(copy.props[0].loot_table, "monster_small")


func test_blockers_and_blocked_walk_map() -> void:
	var f := _floor()
	assert_eq(f.static_blockers(), [Vector2i(2, 4), Vector2i(3, 5)] as Array[Vector2i], "closed door + barrel")
	assert_eq(f.sight_blockers(), [Vector2i(2, 4)] as Array[Vector2i], "only the door blocks sight")
	assert_eq(f.prop_blockers(), {Vector2i(3, 5): true})
	var m := f.blocked_walk_map()
	assert_false(m.is_walkable(Vector2i(2, 4)), "a closed door is a wall in the copy")
	assert_true(f.walk_map.is_walkable(Vector2i(2, 4)), "the floor itself is untouched")
	assert_true(m.is_walkable(Vector2i(3, 5)), "props are not walled (they never block sight)")
	f.doors[0].state = DoorData.STATE_OPEN
	assert_eq(f.static_blockers(), [Vector2i(3, 5)] as Array[Vector2i])
	assert_true(f.blocked_walk_map().is_walkable(Vector2i(2, 4)))
	f.doors[0].state = DoorData.STATE_LOCKED
	assert_true(f.doors[0].is_locked() and f.doors[0].blocks())


func test_corridor_cells() -> void:
	var f := _floor()
	assert_true(f.is_corridor_cell(Vector2i(2, 4)), "walls north and south, floor east and west")
	assert_true(f.is_corridor_cell(Vector2i(1, 2)), "walls east and west, floor north and south")
	assert_false(f.is_corridor_cell(Vector2i(4, 4)), "inside a room")
	assert_false(f.is_corridor_cell(Vector2i(0, 0)), "a wall")


func test_outer_third() -> void:
	var f := _floor()
	assert_true(f.is_on_outer_third(Vector2i(1, 1)))
	assert_true(f.is_on_outer_third(Vector2i(8, 4)))
	assert_false(f.is_on_outer_third(Vector2i(4, 1)), "near the middle column, not near an edge row")


func test_landing_rules() -> void:
	var f := _floor()
	f.landings.clear()
	_assert_problem(f, "needs at least one landing")
	f = _floor()
	f.landings[1].position = Vector2i(4, 1)
	_assert_problem(f, "is not on the outer third")
	f = _floor()
	f.landings[1].position = Vector2i(4, 4)
	_assert_problem(f, "is inside zone 'z1'")
	f = _floor()
	f.landings[1].position = Vector2i(2, 2)
	_assert_problem(f, "landing 'e' position (2, 2) is not walkable")
	f = _floor()
	f.landings[1].id = "nw"
	_assert_problem(f, "duplicate landing id 'nw'")
	f = _floor()
	f.landings[1].id = ""
	_assert_problem(f, "a landing has an empty id")
	f = _floor()
	f.landings[1].facing = "up"
	_assert_problem(f, "facing 'up'")
	f = _floor()
	f.arrival = Vector2i(8, 1)
	_assert_problem(f, "is not landings[0]")


func test_stairs_guard_rules() -> void:
	var f := _floor()
	f.encounter_zones[0].guards_stairs = false
	_assert_problem(f, "is not marked guards_stairs")
	f = _floor()
	f.chests[0].position = Vector2i(8, 1)
	_assert_problem(f, "has no chest")
	f = _floor()
	f.encounter_zones[0].rect = Rect2i(3, 3, 2, 3)
	f.encounter_zones[0].spawn_points[0] = Vector2i(4, 3)
	_assert_problem(f, "are not inside an encounter zone")
	_assert_problem(f, "guards the stairs but its rect does not hold the stairs")


func test_route_rules() -> void:
	var f := _floor()
	f.doors[0].state = DoorData.STATE_LOCKED
	f.doors[0].dc = 12
	_assert_problem(f, "not reachable from landing 'nw'")
	_assert_problem(f, "not reachable from landing 'e'")
	f = _floor()
	f.props[1].blocks = true
	_assert_problem(f, "not reachable from landing 'nw'")
	f = _floor()
	f.doors[0].state = DoorData.STATE_CLOSED
	assert_eq(f.validate(), [] as Array[String], "closed doors can be opened: still a route")


func test_door_rules() -> void:
	var f := _floor()
	f.doors[0].position = Vector2i(4, 4)
	_assert_problem(f, "is not a 1-wide corridor cell")
	f = _floor()
	f.doors[0].position = Vector2i(0, 0)
	_assert_problem(f, "door 'd1' position (0, 0) is not walkable")
	f = _floor()
	f.doors[0].state = "ajar"
	_assert_problem(f, "state 'ajar'")
	f = _floor()
	f.doors[0].state = DoorData.STATE_LOCKED
	_assert_problem(f, "neither a dc nor a key_item")
	f = _floor()
	f.doors[0].dc = -1
	_assert_problem(f, "dc -1 is negative")
	f = _floor()
	f.doors.append(DoorData.from_dict({"id": "d1", "position": [1, 2], "state": "open"}))
	_assert_problem(f, "duplicate door id 'd1'")
	f = _floor()
	f.doors[0].id = ""
	_assert_problem(f, "a door has an empty id")


func test_prop_rules() -> void:
	var f := _floor()
	f.props[0].kind = "statue"
	_assert_problem(f, "kind 'statue'")
	f = _floor()
	f.props[0].hp = 0
	_assert_problem(f, "hp 0 must be at least 1")
	f = _floor()
	f.props[0].position = Vector2i(0, 0)
	_assert_problem(f, "prop 'p1' position (0, 0) is not walkable")
	f = _floor()
	f.props[1].id = "p1"
	_assert_problem(f, "duplicate prop id 'p1'")
	f = _floor()
	f.props[0].id = ""
	_assert_problem(f, "a prop has an empty id")


func test_objects_need_their_own_tile() -> void:
	var f := _floor()
	f.props[0].position = Vector2i(6, 5)
	_assert_problem(f, "chest 'c1' and prop 'p1' share tile (6, 5)")
	f = _floor()
	f.props[1].position = Vector2i(5, 4)
	_assert_problem(f, "stairs and prop 'p2' share tile (5, 4)")
	f = _floor()
	f.chests[0].position = Vector2i(1, 1)
	_assert_problem(f, "landing 'nw' and chest 'c1' share tile (1, 1)")


func test_spawn_points_avoid_doors_and_blocking_props() -> void:
	var f := _floor()
	f.encounter_zones[0].spawn_points[0] = Vector2i(3, 5)
	_assert_problem(f, "is on blocking prop 'p1'")
	f = _floor()
	f.encounter_zones[0].rect = Rect2i(2, 3, 5, 3)
	f.encounter_zones[0].spawn_points[0] = Vector2i(2, 4)
	_assert_problem(f, "is on door 'd1'")


func test_respawn_rules() -> void:
	var f := _floor()
	f.respawn_pack_seconds = -1
	_assert_problem(f, "respawn seconds must be >= 0")
	var g := FloorData.from_dict({"schema_version": 2, "id": "x", "rows": ["A.S"], "landings": [{"id": "a", "position": [0, 0]}],
		"stairs": [2, 0]})
	assert_eq(g.respawn_pack_seconds, FloorData.DEFAULT_PACK_RESPAWN_SECONDS)
	assert_eq(g.respawn_boss_seconds, FloorData.DEFAULT_BOSS_RESPAWN_SECONDS)


func test_unsupported_schema_is_a_problem() -> void:
	var f := _floor()
	f.schema_version = 3
	_assert_problem(f, "schema_version 3 is not supported")

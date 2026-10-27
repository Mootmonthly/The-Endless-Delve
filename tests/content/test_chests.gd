extends TestCase
## Treasure chests on the first set's floors: one stairs chest within
## STAIR_CHEST_RANGE tiles of each staircase (chest_stairs_t1 on floors 1-2,
## chest_stairs_t2 on 3-5) and one hidden cache (cache_t1 / cache_t2) inside
## the floor's optional side area; neither table can roll only supplies. Positions are walkable floor (not a wall or
## pillar), unique, off the spawn points, the stairs and the arrival tile, and
## every table exists in data/loot. See docs/gdd.md "Items and inventory".

const SET_PATH := "res://floors/set_01.json"
const LOOT_DIR := "res://data/loot"
const STAIR_CHEST_RANGE := 3
## Floor number -> [stairs chest table, hidden cache table].
const TABLES_BY_FLOOR: Dictionary = {
	1: ["chest_stairs_t1", "cache_t1"], 2: ["chest_stairs_t1", "cache_t1"],
	3: ["chest_stairs_t2", "cache_t2"], 4: ["chest_stairs_t2", "cache_t2"], 5: ["chest_stairs_t2", "cache_t2"],
}
## Items that count as "supplies": a chest must never give only these.
const SUPPLIES: Array[String] = ["torch", "rations", "arrows", "bolts", "sling_bullets"]

var _floor_ids: Array[String] = []
var _loot: Dictionary = {}


func before_each() -> void:
	if _floor_ids.is_empty():
		_floor_ids = DictUtil.to_string_array(FloorFile.load_set(SET_PATH).get("floors", []))
	if _loot.is_empty():
		_loot = ContentLoader.load_loot_tables(LOOT_DIR)


func _raw(floor_id: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(FloorFile.floor_path(floor_id)))
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var d: Dictionary = parsed
	return d


func _raw_chests(floor_id: String) -> Array[Dictionary]:
	return DictUtil.to_dict_array(_raw(floor_id).get("chests", []))


func _pos(chest: Dictionary) -> Vector2i:
	var arr := DictUtil.to_int_array(chest.get("position", []))
	if arr.size() != 2:
		return Vector2i(-1, -1)
	return Vector2i(arr[0], arr[1])


func _spawn_points(f: FloorData) -> Dictionary:
	var out := {}
	for zone in f.encounter_zones:
		for p in zone.spawn_points:
			out[p] = zone.id
	return out


func test_set_has_five_floors() -> void:
	assert_eq(_floor_ids.size(), 5)


func test_chest_positions_are_walkable_unique_and_clear() -> void:
	for floor_id in _floor_ids:
		var f := FloorFile.load(FloorFile.floor_path(floor_id))
		if f == null:
			fail("%s did not load" % floor_id)
			continue
		var raw := _raw_chests(floor_id)
		assert_true(raw.size() >= 2, "%s has at least two chests" % floor_id)
		var spawns := _spawn_points(f)
		var ids := {}
		var positions := {}
		for c in raw:
			var cid := str(c.get("id", ""))
			var p := _pos(c)
			var ctx := "%s chest '%s' at %s" % [floor_id, cid, str(p)]
			assert_ne(cid, "", "%s: chest id" % floor_id)
			assert_false(ids.has(cid), "%s: id is unique" % ctx)
			assert_false(positions.has(p), "%s: position is unique" % ctx)
			ids[cid] = true
			positions[p] = true
			assert_true(f.walk_map.is_walkable(p), "%s: walkable (not a wall or pillar)" % ctx)
			assert_false(spawns.has(p), "%s: not a spawn point" % ctx)
			assert_ne(p, f.stairs, "%s: not on the stairs" % ctx)
			assert_ne(p, f.arrival, "%s: not on the arrival tile" % ctx)
			assert_eq(typeof(c.get("hidden", false)), TYPE_BOOL, "%s: hidden is a bool" % ctx)


func test_chest_tables_exist() -> void:
	for floor_id in _floor_ids:
		for c in _raw_chests(floor_id):
			var table := str(c.get("table", ""))
			assert_true(FileAccess.file_exists("%s/%s.json" % [LOOT_DIR, table]),
					"%s chest %s: data/loot/%s.json exists" % [floor_id, str(c.get("id")), table])
			assert_true(_loot.has(table), "%s chest %s: loot table '%s' loads" % [floor_id, str(c.get("id")), table])


func test_a_tiered_chest_sits_by_each_staircase() -> void:
	for floor_id in _floor_ids:
		var f := FloorFile.load(FloorFile.floor_path(floor_id))
		if f == null:
			fail("%s did not load" % floor_id)
			continue
		var stair_table := str((TABLES_BY_FLOOR[f.floor_number] as Array)[0])
		var near := 0
		for c in _raw_chests(floor_id):
			if DictUtil.to_bool(c.get("hidden", false), false):
				continue
			if str(c.get("table", "")) != stair_table:
				continue
			if GridMath.distance_tiles(_pos(c), f.stairs) <= STAIR_CHEST_RANGE:
				near += 1
				# reachable from the stairs without leaving the room
				assert_false(f.walk_map.path_to(f.stairs, _pos(c), {}).is_empty(),
						"%s: the stair chest is reachable" % floor_id)
		assert_eq(near, 1, "%s: one visible %s chest within %d tiles of the stairs" % [floor_id, stair_table, STAIR_CHEST_RANGE])


func test_one_hidden_chest_in_the_optional_side_area() -> void:
	for floor_id in _floor_ids:
		var f := FloorFile.load(FloorFile.floor_path(floor_id))
		if f == null:
			fail("%s did not load" % floor_id)
			continue
		var optional_rects: Array[Rect2i] = []
		for z in DictUtil.to_dict_array(_raw(floor_id).get("encounter_zones", [])):
			if DictUtil.to_bool(z.get("optional", false), false):
				var zone := f.get_zone(str(z.get("id", "")))
				if zone != null:
					optional_rects.append(zone.rect)
		var hidden := 0
		for c in _raw_chests(floor_id):
			if not DictUtil.to_bool(c.get("hidden", false), false):
				continue
			hidden += 1
			assert_eq(str(c.get("table", "")), str((TABLES_BY_FLOOR[f.floor_number] as Array)[1]), "%s hidden cache table" % floor_id)
			var inside := false
			for r in optional_rects:
				if r.has_point(_pos(c)):
					inside = true
			assert_true(inside, "%s hidden chest %s is inside the optional side area" % [floor_id, str(c.get("id"))])
		assert_eq(hidden, 1, "%s hidden chests" % floor_id)


func test_floor_data_parses_the_chests() -> void:
	for floor_id in _floor_ids:
		var f := FloorFile.load(FloorFile.floor_path(floor_id))
		if f == null:
			fail("%s did not load" % floor_id)
			continue
		var raw := _raw_chests(floor_id)
		assert_eq(f.chests.size(), raw.size(), "%s chest count" % floor_id)
		for c in raw:
			var chest := f.get_chest(str(c.get("id", "")))
			assert_not_null(chest, "%s: chest %s parsed" % [floor_id, str(c.get("id"))])
			if chest != null:
				assert_eq(chest.position, _pos(c))
				assert_eq(chest.table_id, str(c.get("table", "")))
				assert_eq(chest.hidden, DictUtil.to_bool(c.get("hidden", false), false))
		assert_eq(f.validate(_loot), [] as Array[String], "%s validates against the loot tables" % floor_id)


func test_stairs_and_cache_tables_never_roll_only_supplies() -> void:
	for tid in ["chest_stairs_t1", "chest_stairs_t2", "cache_t1", "cache_t2"]:
		assert_true(_loot.has(tid), "loot table %s" % tid)
		if not _loot.has(tid):
			continue
		var table: LootTable = _loot[tid]
		assert_true(table.is_grouped(), "%s uses category rolls" % tid)
		var gear_rolls := 0
		for name in table.group_names():
			if name.begins_with("gear"):
				gear_rolls += 1
		assert_eq(gear_rolls, 2 if tid.begins_with("cache") else 1, "%s gear rolls" % tid)
		for s in range(1, 201):
			var drops := table.roll(Rng.new(s))
			var other := 0
			for d in drops:
				if not SUPPLIES.has(str(d["item"])):
					other += 1
			assert_true(other >= 3, "%s seed %d: gear, healing and gold, not just supplies (%s)" % [tid, s, str(drops)])

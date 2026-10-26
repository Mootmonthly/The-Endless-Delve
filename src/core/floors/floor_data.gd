class_name FloorData
extends RefCounted
## One handcrafted floor: walkable tiles, arrival and stairs tiles, encounter zones.
##
## Dictionary form (also the floor file format):
## {"schema_version": 1, "id", "display_name", "rows": ["####", "#..#", ...],
##  "arrival": [x, y], "stairs": [x, y], "encounter_zones": [EncounterZoneData...],
##  "floor_number": int (optional, default 0 = unnumbered), "theme": String (optional, default ""),
##  "chests": [ChestData...] (optional: {"id", "position": [x, y], "table", "hidden"})}
## In rows '#' is a wall and every other character ('.', 'A', 'S', ...) is walkable.
## Other keys (e.g. a content "budget") are ignored by the rules.

const SCHEMA_VERSION := 1

var id: String = ""
var display_name: String = ""
## 1-based depth in the dungeon (0 = not numbered, e.g. a test floor).
var floor_number: int = 0
## Theme shared by every floor of a five-floor set ("" = none).
var theme: String = ""
var walk_map: WalkMap = WalkMap.new()
var arrival: Vector2i = Vector2i.ZERO
var stairs: Vector2i = Vector2i.ZERO
var encounter_zones: Array[EncounterZoneData] = []
var chests: Array[ChestData] = []


func get_chest(chest_id: String) -> ChestData:
	for c in chests:
		if c.id == chest_id:
			return c
	return null


func get_zone(zone_id: String) -> EncounterZoneData:
	for z in encounter_zones:
		if z.id == zone_id:
			return z
	return null


## The zone whose rect contains p, or null.
func zone_at(p: Vector2i) -> EncounterZoneData:
	for z in encounter_zones:
		if z.rect.has_point(p):
			return z
	return null


## Lists every authoring problem; empty means the floor is playable. When
## loot_tables (id -> LootTable) is given, chest tables must exist in it.
func validate(loot_tables: Dictionary = {}) -> Array[String]:
	var problems: Array[String] = []
	if id.is_empty():
		problems.append("floor id is empty")
	if floor_number < 0:
		problems.append("floor_number %d is negative" % floor_number)
	if walk_map == null or walk_map.width == 0 or walk_map.height == 0:
		problems.append("walk map is empty")
		return problems
	_check_tile(problems, "arrival", arrival)
	_check_tile(problems, "stairs", stairs)
	if arrival == stairs:
		problems.append("arrival and stairs are the same tile %s" % str(arrival))
	var seen_ids := {}
	for z in encounter_zones:
		var ctx := "zone '%s'" % z.id
		if z.id.is_empty():
			problems.append("an encounter zone has an empty id")
		elif seen_ids.has(z.id):
			problems.append("duplicate zone id '%s'" % z.id)
		seen_ids[z.id] = true
		if z.rect.size.x <= 0 or z.rect.size.y <= 0:
			problems.append("%s has an empty rect" % ctx)
		elif not walk_map.bounds().encloses(z.rect):
			problems.append("%s rect %s is out of bounds" % [ctx, str(z.rect)])
		if z.monster_ids.is_empty():
			problems.append("%s has no monsters" % ctx)
		if z.spawn_points.size() < z.monster_ids.size():
			problems.append("%s has %d monsters but only %d spawn points" % [ctx, z.monster_ids.size(), z.spawn_points.size()])
		var seen_points := {}
		for p in z.spawn_points:
			if not z.rect.has_point(p):
				problems.append("%s spawn point %s is outside its rect" % [ctx, str(p)])
			if not walk_map.is_walkable(p):
				problems.append("%s spawn point %s is not walkable" % [ctx, str(p)])
			if seen_points.has(p):
				problems.append("%s spawn point %s is listed twice" % [ctx, str(p)])
			seen_points[p] = true
	var seen_chests := {}
	for c in chests:
		var cctx := "chest '%s'" % c.id
		if c.id.is_empty():
			problems.append("a chest has an empty id")
		elif seen_chests.has(c.id):
			problems.append("duplicate chest id '%s'" % c.id)
		seen_chests[c.id] = true
		if not walk_map.is_walkable(c.position):
			problems.append("%s position %s is not walkable" % [cctx, str(c.position)])
		if c.table_id.is_empty():
			problems.append("%s has no loot table" % cctx)
		elif not loot_tables.is_empty() and not loot_tables.has(c.table_id):
			problems.append("%s uses unknown loot table '%s'" % [cctx, c.table_id])
	if walk_map.is_walkable(arrival) and walk_map.is_walkable(stairs) and arrival != stairs:
		if walk_map.path_to(arrival, stairs, {}).is_empty():
			problems.append("stairs %s are not reachable from arrival %s" % [str(stairs), str(arrival)])
	return problems


func to_dict() -> Dictionary:
	var zones: Array = []
	for z in encounter_zones:
		zones.append(z.to_dict())
	var chest_list: Array = []
	for c in chests:
		chest_list.append(c.to_dict())
	return {
		"schema_version": SCHEMA_VERSION,
		"id": id,
		"display_name": display_name,
		"floor_number": floor_number,
		"theme": theme,
		"rows": walk_map.to_rows() if walk_map != null else [],
		"arrival": GridMath.vec_to_arr(arrival),
		"stairs": GridMath.vec_to_arr(stairs),
		"encounter_zones": zones,
		"chests": chest_list,
	}


## Never returns null; call validate() on the result. Accepts "rows" (floor
## file format) or a nested "walk_map" dictionary.
static func from_dict(d: Dictionary) -> FloorData:
	var f := FloorData.new()
	if d.has("schema_version") and DictUtil.to_int(d["schema_version"], -1) != SCHEMA_VERSION:
		push_error("FloorData: unsupported schema_version %s" % str(d["schema_version"]))
	f.id = str(d.get("id", ""))
	f.display_name = str(d.get("display_name", f.id))
	f.floor_number = DictUtil.to_int(d.get("floor_number", 0), 0)
	f.theme = str(d.get("theme", ""))
	if d.has("rows"):
		f.walk_map = WalkMap.from_rows(DictUtil.to_string_array(d["rows"]))
	elif typeof(d.get("walk_map")) == TYPE_DICTIONARY:
		var wm: Dictionary = d["walk_map"]
		f.walk_map = WalkMap.from_dict(wm)
	f.arrival = GridMath.arr_to_vec(d.get("arrival", [0, 0]))
	f.stairs = GridMath.arr_to_vec(d.get("stairs", [0, 0]))
	for zd in DictUtil.to_dict_array(d.get("encounter_zones", [])):
		f.encounter_zones.append(EncounterZoneData.from_dict(zd))
	for cd in DictUtil.to_dict_array(d.get("chests", [])):
		f.chests.append(ChestData.from_dict(cd))
	return f


func _check_tile(problems: Array[String], label: String, p: Vector2i) -> void:
	if not walk_map.in_bounds(p):
		problems.append("%s %s is out of bounds" % [label, str(p)])
	elif not walk_map.is_walkable(p):
		problems.append("%s %s is not walkable" % [label, str(p)])

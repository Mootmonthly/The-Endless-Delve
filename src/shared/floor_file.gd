class_name FloorFile
extends RefCounted
## Reads a handcrafted floor authored as JSON (floors/floor_NNN.json) into a
## core FloorData.
##
## File format (schema_version 1):
##   {"schema_version": 1, "id": "floor_001", "display_name": "The Threshold",
##    "rows": ["#####", "#A.S#", ...],      one string per tile row, all equal width
##    "arrival": [x, y], "stairs": [x, y],
##    "encounter_zones": [{"id": "z1", "rect": [x, y, w, h],
##                         "monster_ids": ["goblin", ...], "spawn_points": [[x, y], ...]}]}
## Row legend: '#' wall, '.' floor, 'A' arrival (floor), 'S' stairs (floor).
## 'A' / 'S' are optional in the rows; when present they must match
## "arrival" / "stairs". Coordinates are tiles, x right and y down.
##
## FloorFile adds the strict format checks (legend, equal row widths, A/S
## markers matching arrival/stairs, field shapes) and then delegates to
## FloorData.from_dict, which reads the same layout. Structural problems are
## reported with push_error and yield null; game rules about the floor
## (reachability, spawn points etc.) are FloorData.validate()'s job.

const SCHEMA_VERSION := 1
const WALL := "#"
const FLOOR := "."
const ARRIVAL := "A"
const STAIRS := "S"
const LEGEND := "#.AS"


## Loads and parses a floor file; null (with push_error) on any problem.
static func load(path: String) -> FloorData:
	if not FileAccess.file_exists(path):
		push_error("FloorFile: file not found: %s" % path)
		return null
	var text := FileAccess.get_file_as_string(path)
	var parser := JSON.new()
	if parser.parse(text) != OK:
		push_error("FloorFile: %s line %d: %s" % [path, parser.get_error_line(), parser.get_error_message()])
		return null
	if typeof(parser.data) != TYPE_DICTIONARY:
		push_error("FloorFile: %s: top level must be an object" % path)
		return null
	var d: Dictionary = parser.data
	var floor_data := FloorFile.from_dict(d)
	if floor_data == null:
		push_error("FloorFile: %s is not a valid floor file" % path)
	return floor_data


## Builds FloorData from a parsed floor file dictionary; null on problems.
static func from_dict(d: Dictionary) -> FloorData:
	var problems := FloorFile.structural_problems(d)
	if not problems.is_empty():
		for p in problems:
			push_error("FloorFile: %s" % p)
		return null
	return FloorData.from_dict(d)


## Format-level problems with a floor file dictionary ([] when well formed).
static func structural_problems(d: Dictionary) -> Array[String]:
	var out: Array[String] = []
	if DictUtil.to_int(d.get("schema_version"), -1) != SCHEMA_VERSION:
		out.append("schema_version must be %d" % SCHEMA_VERSION)
	if typeof(d.get("id")) != TYPE_STRING or str(d.get("id")).is_empty():
		out.append("missing or empty 'id'")
	if typeof(d.get("rows")) != TYPE_ARRAY or (d["rows"] as Array).is_empty():
		out.append("'rows' must be a non-empty array of strings")
		return out
	var raw_rows: Array = d["rows"]
	var width := -1
	var marker_a := Vector2i(-1, -1)
	var marker_s := Vector2i(-1, -1)
	for y in range(raw_rows.size()):
		if typeof(raw_rows[y]) != TYPE_STRING:
			out.append("row %d is not a string" % y)
			continue
		var row: String = raw_rows[y]
		if width == -1:
			width = row.length()
		elif row.length() != width:
			out.append("row %d has width %d, expected %d" % [y, row.length(), width])
		for x in range(row.length()):
			var c := row[x]
			if not LEGEND.contains(c):
				out.append("unknown tile '%s' at (%d, %d)" % [c, x, y])
			elif c == ARRIVAL:
				if marker_a.x >= 0:
					out.append("more than one 'A' in rows")
				marker_a = Vector2i(x, y)
			elif c == STAIRS:
				if marker_s.x >= 0:
					out.append("more than one 'S' in rows")
				marker_s = Vector2i(x, y)
	if width <= 0:
		out.append("rows must not be empty strings")
	for key: String in ["arrival", "stairs"]:
		if not FloorFile._is_pair(d.get(key)):
			out.append("'%s' must be [x, y]" % key)
	if out.is_empty():
		if marker_a.x >= 0 and marker_a != FloorFile._vec(d["arrival"]):
			out.append("'A' in rows at %s does not match arrival %s" % [marker_a, FloorFile._vec(d["arrival"])])
		if marker_s.x >= 0 and marker_s != FloorFile._vec(d["stairs"]):
			out.append("'S' in rows at %s does not match stairs %s" % [marker_s, FloorFile._vec(d["stairs"])])
	var zones_v: Variant = d.get("encounter_zones", [])
	if typeof(zones_v) != TYPE_ARRAY:
		out.append("'encounter_zones' must be an array")
		return out
	var zones: Array = zones_v
	var seen_ids: Array[String] = []
	for i in range(zones.size()):
		if typeof(zones[i]) != TYPE_DICTIONARY:
			out.append("encounter zone %d is not an object" % i)
			continue
		var z: Dictionary = zones[i]
		var zid := str(z.get("id", ""))
		if typeof(z.get("id")) != TYPE_STRING or zid.is_empty():
			out.append("encounter zone %d has no 'id'" % i)
		elif seen_ids.has(zid):
			out.append("duplicate encounter zone id '%s'" % zid)
		seen_ids.append(zid)
		var rect_v: Variant = z.get("rect")
		if typeof(rect_v) != TYPE_ARRAY or (rect_v as Array).size() != 4 \
				or not (rect_v as Array).all(func(n: Variant) -> bool: return DictUtil.is_number(n)):
			out.append("encounter zone '%s': 'rect' must be [x, y, w, h]" % zid)
		if typeof(z.get("monster_ids", [])) != TYPE_ARRAY:
			out.append("encounter zone '%s': 'monster_ids' must be an array" % zid)
		var spawns_v: Variant = z.get("spawn_points", [])
		if typeof(spawns_v) != TYPE_ARRAY:
			out.append("encounter zone '%s': 'spawn_points' must be an array" % zid)
		else:
			for sp: Variant in (spawns_v as Array):
				if not FloorFile._is_pair(sp):
					out.append("encounter zone '%s': spawn point %s is not [x, y]" % [zid, str(sp)])
	return out


static func _is_pair(v: Variant) -> bool:
	if typeof(v) != TYPE_ARRAY:
		return false
	var arr: Array = v
	return arr.size() == 2 and DictUtil.is_number(arr[0]) and DictUtil.is_number(arr[1])


static func _vec(v: Variant) -> Vector2i:
	var arr: Array = v
	return Vector2i(DictUtil.to_int(arr[0]), DictUtil.to_int(arr[1]))

class_name FloorData
extends RefCounted
## One handcrafted floor: walkable tiles, landings, stairs, encounter zones,
## chests, doors and breakable props.
##
## Dictionary form (also the floor file format, see FloorFile and docs/gdd.md
## 5.2.2):
## {"schema_version": 2, "id", "display_name", "rows": ["####", "#..#", ...],
##  "landings": [LandingData...], "arrival": [x, y] (= landings[0]),
##  "stairs": [x, y], "encounter_zones": [EncounterZoneData...],
##  "floor_number": int (optional, default 0 = unnumbered), "theme": String (optional, default ""),
##  "chests": [ChestData...] (optional: {"id", "position": [x, y], "table", "hidden"}),
##  "doors": [DoorData...], "props": [PropData...] (optional, v2),
##  "respawn": {"pack_seconds": int, "boss_seconds": int} (optional, v2),
##  "theme_style": {...} (optional, v2: presentation hints, never read by the rules)}
## Schema 1 files have "arrival" and no landings / doors / props; they load as
## one landing with id LandingData.ARRIVAL_ID. In rows '#' is a wall and every
## other character is walkable. Other keys (e.g. a content "budget") are
## ignored by the rules.
##
## Doors and blocking props are not part of the walk map: a closed door tile
## and a blocking prop tile are floor in the rows. Callers compose them in
## (static_blockers / sight_blockers / blocked_walk_map) so that opening a
## door or breaking a prop never rewrites the floor.

## The latest floor schema; from_dict reads 1 and 2 and to_dict writes the
## floor's own schema_version (with every v2 key, which v1 readers ignore).
const SCHEMA_VERSION := 2
const SUPPORTED_SCHEMAS: Array[int] = [1, 2]
const DEFAULT_PACK_RESPAWN_SECONDS := 600
const DEFAULT_BOSS_RESPAWN_SECONDS := 1800
## A v2 landing must lie in the outer third of the map: its normalised
## Chebyshev distance from the centre (0 centre, 1 edge) is at least this.
const LANDING_MIN_EDGE_RATIO := 2.0 / 3.0

var id: String = ""
var display_name: String = ""
## Schema of the source dictionary (1 or 2); version-2 rules (at least one
## landing, landings on the edge and outside zones, guarded stairs with a
## chest) apply only to schema 2 floors. A hand-built FloorData is 1 until set.
var schema_version: int = 1
## 1-based depth in the dungeon (0 = not numbered, e.g. a test floor).
var floor_number: int = 0
## Theme shared by every floor of a five-floor set ("" = none).
var theme: String = ""
var walk_map: WalkMap = WalkMap.new()
## The legacy arrival tile: always landings[0].position when landings exist.
var arrival: Vector2i = Vector2i.ZERO
var stairs: Vector2i = Vector2i.ZERO
## Arrival landings around the edge; empty on a schema 1 or hand-built
## FloorData, in which case get_landings() derives one from `arrival`.
var landings: Array[LandingData] = []
var encounter_zones: Array[EncounterZoneData] = []
var chests: Array[ChestData] = []
var doors: Array[DoorData] = []
var props: Array[PropData] = []
## Seconds before a slain pack (respawns == true) comes back.
var respawn_pack_seconds: int = DEFAULT_PACK_RESPAWN_SECONDS
## Seconds before a slain boss zone comes back.
var respawn_boss_seconds: int = DEFAULT_BOSS_RESPAWN_SECONDS
## Presentation hints for the client (darkness, torch colour, floor variant
## weights...). Carried through to_dict / from_dict untouched.
var theme_style: Dictionary = {}


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


func get_door(door_id: String) -> DoorData:
	for d in doors:
		if d.id == door_id:
			return d
	return null


func get_prop(prop_id: String) -> PropData:
	for p in props:
		if p.id == prop_id:
			return p
	return null


func get_landing(landing_id: String) -> LandingData:
	for l in get_landings():
		if l.id == landing_id:
			return l
	return null


## The landings, or one derived from `arrival` when none were given.
func get_landings() -> Array[LandingData]:
	if not landings.is_empty():
		return landings
	var out: Array[LandingData] = [LandingData.make(LandingData.ARRIVAL_ID, arrival)]
	return out


func landing_positions() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for l in get_landings():
		out.append(l.position)
	return out


## The zone whose rect contains p, or null.
func zone_at(p: Vector2i) -> EncounterZoneData:
	for z in encounter_zones:
		if z.rect.has_point(p):
			return z
	return null


## The door on tile p, or null.
func door_at(p: Vector2i) -> DoorData:
	for d in doors:
		if d.position == p:
			return d
	return null


## The prop on tile p, or null.
func prop_at(p: Vector2i) -> PropData:
	for pr in props:
		if pr.position == p:
			return pr
	return null


## The zone that holds the stairs tile (the stairs guard), or null.
func stairs_zone() -> EncounterZoneData:
	return zone_at(stairs)


## Tiles that stop movement at load time: closed or locked doors and blocking
## props. Servers add them to their occupied / blocked sets (props) or wall
## them off in a walk map copy (doors, see blocked_walk_map).
func static_blockers() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for d in doors:
		if d.blocks():
			out.append(d.position)
	for p in props:
		if p.blocks:
			out.append(p.position)
	return out


## Tiles that stop line of sight at load time: closed or locked doors.
func sight_blockers() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for d in doors:
		if d.blocks():
			out.append(d.position)
	return out


## A copy of the walk map in which closed and locked doors are walls (they
## block movement and line of sight). Blocking props are not walled (they do
## not block sight): pass prop_blockers() as `occupied` to path finding.
func blocked_walk_map() -> WalkMap:
	var m := walk_map.copy()
	for p in sight_blockers():
		if m.in_bounds(p):
			m.set_walkable(p, false)
	return m


## Blocking prop tiles as an `occupied`-style set (Vector2i -> true).
func prop_blockers() -> Dictionary:
	var out := {}
	for p in props:
		if p.blocks:
			out[p.position] = true
	return out


## True when p lies in the outer third of the map (see LANDING_MIN_EDGE_RATIO).
func is_on_outer_third(p: Vector2i) -> bool:
	if walk_map == null or walk_map.width == 0 or walk_map.height == 0:
		return false
	var half_w := walk_map.width / 2.0
	var half_h := walk_map.height / 2.0
	var nx := absf(p.x + 0.5 - half_w) / half_w
	var ny := absf(p.y + 0.5 - half_h) / half_h
	return maxf(nx, ny) >= LANDING_MIN_EDGE_RATIO - 0.0001


## Lists every authoring problem; empty means the floor is playable. When
## loot_tables (id -> LootTable) is given, chest and prop tables must exist in it.
func validate(loot_tables: Dictionary = {}) -> Array[String]:
	var problems: Array[String] = []
	if id.is_empty():
		problems.append("floor id is empty")
	if floor_number < 0:
		problems.append("floor_number %d is negative" % floor_number)
	if not SUPPORTED_SCHEMAS.has(schema_version):
		problems.append("schema_version %d is not supported" % schema_version)
	if walk_map == null or walk_map.width == 0 or walk_map.height == 0:
		problems.append("walk map is empty")
		return problems
	var v2 := schema_version >= 2
	_check_tile(problems, "arrival", arrival)
	_check_tile(problems, "stairs", stairs)
	if arrival == stairs:
		problems.append("arrival and stairs are the same tile %s" % str(arrival))
	_validate_zones(problems)
	_validate_chests(problems, loot_tables)
	_validate_landings(problems, v2)
	_validate_doors(problems)
	_validate_props(problems, loot_tables)
	_validate_objects_share_no_tile(problems)
	if respawn_pack_seconds < 0 or respawn_boss_seconds < 0:
		problems.append("respawn seconds must be >= 0 (pack %d, boss %d)" % [respawn_pack_seconds, respawn_boss_seconds])
	if v2:
		_validate_stairs_guard(problems)
	_validate_routes(problems)
	return problems


func to_dict() -> Dictionary:
	var zones: Array = []
	for z in encounter_zones:
		zones.append(z.to_dict())
	var chest_list: Array = []
	for c in chests:
		chest_list.append(c.to_dict())
	var landing_list: Array = []
	for l in get_landings():
		landing_list.append(l.to_dict())
	var door_list: Array = []
	for d in doors:
		door_list.append(d.to_dict())
	var prop_list: Array = []
	for p in props:
		prop_list.append(p.to_dict())
	return {
		"schema_version": schema_version,
		"id": id,
		"display_name": display_name,
		"floor_number": floor_number,
		"theme": theme,
		"rows": walk_map.to_rows() if walk_map != null else [],
		"arrival": GridMath.vec_to_arr(arrival),
		"stairs": GridMath.vec_to_arr(stairs),
		"landings": landing_list,
		"encounter_zones": zones,
		"chests": chest_list,
		"doors": door_list,
		"props": prop_list,
		"respawn": {"pack_seconds": respawn_pack_seconds, "boss_seconds": respawn_boss_seconds},
		"theme_style": theme_style.duplicate(true),
	}


## Never returns null; call validate() on the result. Accepts "rows" (floor
## file format) or a nested "walk_map" dictionary, schema 1 or 2.
static func from_dict(d: Dictionary) -> FloorData:
	var f := FloorData.new()
	f.schema_version = 1
	if d.has("schema_version"):
		f.schema_version = DictUtil.to_int(d["schema_version"], -1)
		if not SUPPORTED_SCHEMAS.has(f.schema_version):
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
	for ld in DictUtil.to_dict_array(d.get("landings", [])):
		f.landings.append(LandingData.from_dict(ld))
	if d.has("arrival"):
		f.arrival = GridMath.arr_to_vec(d.get("arrival", [0, 0]))
	elif not f.landings.is_empty():
		f.arrival = f.landings[0].position
	f.stairs = GridMath.arr_to_vec(d.get("stairs", [0, 0]))
	for zd in DictUtil.to_dict_array(d.get("encounter_zones", [])):
		f.encounter_zones.append(EncounterZoneData.from_dict(zd))
	for cd in DictUtil.to_dict_array(d.get("chests", [])):
		f.chests.append(ChestData.from_dict(cd))
	for dd in DictUtil.to_dict_array(d.get("doors", [])):
		f.doors.append(DoorData.from_dict(dd))
	for pd in DictUtil.to_dict_array(d.get("props", [])):
		f.props.append(PropData.from_dict(pd))
	if typeof(d.get("respawn")) == TYPE_DICTIONARY:
		var r: Dictionary = d["respawn"]
		f.respawn_pack_seconds = DictUtil.to_int(r.get("pack_seconds", DEFAULT_PACK_RESPAWN_SECONDS), DEFAULT_PACK_RESPAWN_SECONDS)
		f.respawn_boss_seconds = DictUtil.to_int(r.get("boss_seconds", DEFAULT_BOSS_RESPAWN_SECONDS), DEFAULT_BOSS_RESPAWN_SECONDS)
	if typeof(d.get("theme_style")) == TYPE_DICTIONARY:
		var ts: Dictionary = d["theme_style"]
		f.theme_style = ts.duplicate(true)
	return f


func _check_tile(problems: Array[String], label: String, p: Vector2i) -> void:
	if not walk_map.in_bounds(p):
		problems.append("%s %s is out of bounds" % [label, str(p)])
	elif not walk_map.is_walkable(p):
		problems.append("%s %s is not walkable" % [label, str(p)])


func _validate_zones(problems: Array[String]) -> void:
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
			var door := door_at(p)
			if door != null:
				problems.append("%s spawn point %s is on door '%s'" % [ctx, str(p), door.id])
			var prop := prop_at(p)
			if prop != null and prop.blocks:
				problems.append("%s spawn point %s is on blocking prop '%s'" % [ctx, str(p), prop.id])
		if z.guards_stairs and not z.rect.has_point(stairs):
			problems.append("%s guards the stairs but its rect does not hold the stairs %s" % [ctx, str(stairs)])


func _validate_chests(problems: Array[String], loot_tables: Dictionary) -> void:
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


func _validate_landings(problems: Array[String], v2: bool) -> void:
	if landings.is_empty():
		if v2:
			problems.append("a version 2 floor needs at least one landing")
		return
	if landings[0].position != arrival:
		problems.append("arrival %s is not landings[0] %s" % [str(arrival), str(landings[0].position)])
	var seen := {}
	for l in landings:
		var ctx := "landing '%s'" % l.id
		if l.id.is_empty():
			problems.append("a landing has an empty id")
		elif seen.has(l.id):
			problems.append("duplicate landing id '%s'" % l.id)
		seen[l.id] = true
		if not walk_map.in_bounds(l.position) or not walk_map.is_walkable(l.position):
			problems.append("%s position %s is not walkable" % [ctx, str(l.position)])
		if not l.facing.is_empty() and not LandingData.FACINGS.has(l.facing):
			problems.append("%s facing '%s' is not one of %s" % [ctx, l.facing, str(LandingData.FACINGS)])
		if v2:
			var zone := zone_at(l.position)
			if zone != null:
				problems.append("%s %s is inside zone '%s'" % [ctx, str(l.position), zone.id])
			if not is_on_outer_third(l.position):
				problems.append("%s %s is not on the outer third of the map" % [ctx, str(l.position)])


func _validate_doors(problems: Array[String]) -> void:
	var seen := {}
	for d in doors:
		var ctx := "door '%s'" % d.id
		if d.id.is_empty():
			problems.append("a door has an empty id")
		elif seen.has(d.id):
			problems.append("duplicate door id '%s'" % d.id)
		seen[d.id] = true
		if not DoorData.STATES.has(d.state):
			problems.append("%s state '%s' is not one of %s" % [ctx, d.state, str(DoorData.STATES)])
		if d.dc < 0:
			problems.append("%s dc %d is negative" % [ctx, d.dc])
		if d.is_locked() and d.dc <= 0 and d.key_item.is_empty():
			problems.append("%s is locked but has neither a dc nor a key_item" % ctx)
		if not walk_map.in_bounds(d.position) or not walk_map.is_walkable(d.position):
			problems.append("%s position %s is not walkable" % [ctx, str(d.position)])
		elif not is_corridor_cell(d.position):
			problems.append("%s position %s is not a 1-wide corridor cell" % [ctx, str(d.position)])


func _validate_props(problems: Array[String], loot_tables: Dictionary) -> void:
	var seen := {}
	for p in props:
		var ctx := "prop '%s'" % p.id
		if p.id.is_empty():
			problems.append("a prop has an empty id")
		elif seen.has(p.id):
			problems.append("duplicate prop id '%s'" % p.id)
		seen[p.id] = true
		if not PropData.KINDS.has(p.kind):
			problems.append("%s kind '%s' is not one of %s" % [ctx, p.kind, str(PropData.KINDS)])
		if p.hp < 1:
			problems.append("%s hp %d must be at least 1" % [ctx, p.hp])
		if not walk_map.in_bounds(p.position) or not walk_map.is_walkable(p.position):
			problems.append("%s position %s is not walkable" % [ctx, str(p.position)])
		if not p.loot_table.is_empty() and not loot_tables.is_empty() and not loot_tables.has(p.loot_table):
			problems.append("%s uses unknown loot table '%s'" % [ctx, p.loot_table])


## A walkable tile with walls on two opposite sides and open ground on the
## other two (where a door may hang).
func is_corridor_cell(p: Vector2i) -> bool:
	if not walk_map.is_walkable(p):
		return false
	var n := walk_map.is_walkable(p + Vector2i.UP)
	var s := walk_map.is_walkable(p + Vector2i.DOWN)
	var w := walk_map.is_walkable(p + Vector2i.LEFT)
	var e := walk_map.is_walkable(p + Vector2i.RIGHT)
	return (not n and not s and w and e) or (not w and not e and n and s)


## Stairs, landings, chests, doors and props each need a tile of their own.
func _validate_objects_share_no_tile(problems: Array[String]) -> void:
	var owners := {stairs: "stairs"}
	var add := func(p: Vector2i, label: String) -> void:
		if owners.has(p):
			problems.append("%s and %s share tile %s" % [owners[p], label, str(p)])
		else:
			owners[p] = label
	for l in landings:
		add.call(l.position, "landing '%s'" % l.id)
	for c in chests:
		add.call(c.position, "chest '%s'" % c.id)
	for d in doors:
		add.call(d.position, "door '%s'" % d.id)
	for p in props:
		add.call(p.position, "prop '%s'" % p.id)


## Version 2: the stairs stand inside a zone marked guards_stairs, with a chest
## in that zone.
func _validate_stairs_guard(problems: Array[String]) -> void:
	var zone := stairs_zone()
	if zone == null:
		problems.append("the stairs %s are not inside an encounter zone" % str(stairs))
		return
	if not zone.guards_stairs:
		problems.append("zone '%s' holds the stairs but is not marked guards_stairs" % zone.id)
	var has_chest := false
	for c in chests:
		if zone.rect.has_point(c.position):
			has_chest = true
	if not has_chest:
		problems.append("stairs zone '%s' has no chest" % zone.id)


## Every landing reaches the stairs without passing a locked door or a
## blocking prop (closed doors can be opened, so they do not count).
func _validate_routes(problems: Array[String]) -> void:
	if not walk_map.is_walkable(stairs):
		return
	var blocked := prop_blockers()
	for d in doors:
		if d.is_locked():
			blocked[d.position] = true
	blocked.erase(stairs)
	for l in get_landings():
		if not walk_map.is_walkable(l.position) or l.position == stairs:
			continue
		if walk_map.path_to(l.position, stairs, blocked).is_empty():
			if l.id == LandingData.ARRIVAL_ID and landings.size() <= 1:
				problems.append("stairs %s are not reachable from arrival %s" % [str(stairs), str(l.position)])
			else:
				problems.append("stairs %s are not reachable from landing '%s' %s" % [str(stairs), l.id, str(l.position)])

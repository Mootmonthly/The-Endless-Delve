extends TestCase
## Content checks for the first five-floor set (floors/set_01.json): every
## floor loads and validates, monsters exist, zones sit inside the floor's
## declared SRD encounter budget, floors grow, and the zones gate the stairs.
##
## Budget maths (SRD encounter building): adjusted XP = sum of monster XP x a
## multiplier for the number of monsters (1: x1, 2: x1.5, 3-6: x2, 7-10: x2.5,
## 11-14: x3, 15+: x4), compared with one character's thresholds, because the
## set is tuned for a solo at the floor's "budget.level". A zone marked
## "optional" (a side area) may exceed the band; the "boss" zone must be at
## least deadly. See docs/gdd.md section 5.4.

const SET_PATH := "res://floors/set_01.json"
const MONSTER_DIR := "res://data/monsters"
const BANDS: Array[String] = ["trivial", "easy", "medium", "hard", "deadly"]
## SRD XP thresholds per character level: [easy, medium, hard, deadly].
const THRESHOLDS: Dictionary[int, Array] = {
	1: [25, 50, 75, 100],
	2: [50, 100, 150, 200],
	3: [75, 150, 225, 400],
	4: [125, 250, 375, 500],
	5: [250, 500, 750, 1100],
}
## SRD challenge rating -> XP, for the stat-block sanity check.
const CR_XP: Dictionary[String, int] = {
	"0.0": 10, "0.125": 25, "0.25": 50, "0.5": 100, "1.0": 200, "2.0": 450, "3.0": 700,
}

var _manifest: Dictionary = {}
var _monsters: Dictionary = {}


func before_each() -> void:
	if _manifest.is_empty():
		_manifest = FloorFile.load_set(SET_PATH)
	if _monsters.is_empty():
		_monsters = ContentLoader.load_monsters(MONSTER_DIR)


func _floor_ids() -> Array[String]:
	return DictUtil.to_string_array(_manifest.get("floors", []))


## The floor file as parsed JSON (budget / optional are content-only keys).
func _raw(floor_id: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(FloorFile.floor_path(floor_id))
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var d: Dictionary = parsed
	return d


func _raw_zones(raw: Dictionary) -> Array[Dictionary]:
	return DictUtil.to_dict_array(raw.get("encounter_zones", []))


func _is_optional(raw_zone: Dictionary) -> bool:
	return DictUtil.to_bool(raw_zone.get("optional", false), false)


func _is_boss(raw_zone: Dictionary) -> bool:
	return DictUtil.to_bool(raw_zone.get("boss", false), false)


static func _multiplier(count: int) -> float:
	if count <= 1:
		return 1.0
	if count == 2:
		return 1.5
	if count <= 6:
		return 2.0
	if count <= 10:
		return 2.5
	if count <= 14:
		return 3.0
	return 4.0


func _raw_xp(monster_ids: Array[String]) -> int:
	var total := 0
	for mid in monster_ids:
		if _monsters.has(mid):
			var def: MonsterDefinition = _monsters[mid]
			total += def.xp
	return total


func _adjusted_xp(monster_ids: Array[String]) -> float:
	return float(_raw_xp(monster_ids)) * _multiplier(monster_ids.size())


## Index into BANDS for `adjusted` XP against `party_size` characters of `level`.
static func _band(adjusted: float, level: int, party_size: int = 1) -> int:
	var thresholds: Array = THRESHOLDS[level]
	var band := 0
	for i in range(thresholds.size()):
		var t: int = thresholds[i]
		if adjusted >= float(t * party_size):
			band = i + 1
	return band


func _rect_tiles(rect: Rect2i) -> Dictionary:
	var tiles := {}
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			tiles[Vector2i(x, y)] = true
	return tiles


## Full-clear XP of one floor (every zone, optional ones included).
func _floor_xp(f: FloorData) -> int:
	var total := 0
	for zone in f.encounter_zones:
		total += _raw_xp(zone.monster_ids)
	return total


func test_manifest_lists_five_themed_floors() -> void:
	assert_false(_manifest.is_empty(), "set_01.json loads")
	assert_eq(str(_manifest.get("id", "")), "set_01")
	var theme := str(_manifest.get("theme", ""))
	assert_ne(theme, "", "the set has a theme")
	var ids := _floor_ids()
	assert_eq(ids.size(), 5, "a set is five floors")
	for i in range(ids.size()):
		var raw := _raw(ids[i])
		assert_eq(DictUtil.to_int(raw.get("floor_number", 0), 0), i + 1, "%s floor_number" % ids[i])
		assert_eq(str(raw.get("theme", "")), theme, "%s shares the set theme" % ids[i])
		var f := FloorFile.load(FloorFile.floor_path(ids[i]))
		if f != null:
			assert_eq(f.floor_number, i + 1, "%s parsed floor_number" % ids[i])
			assert_eq(f.theme, theme, "%s parsed theme" % ids[i])


func test_every_floor_loads_and_validates() -> void:
	for floor_id in _floor_ids():
		var f := FloorFile.load(FloorFile.floor_path(floor_id))
		assert_not_null(f, "%s loads" % floor_id)
		if f == null:
			continue
		assert_eq(f.id, floor_id)
		assert_eq(f.validate(), [] as Array[String], "%s validates" % floor_id)
		for zone in f.encounter_zones:
			assert_false(zone.rect.has_point(f.arrival), "%s: arrival is outside zone %s" % [floor_id, zone.id])


func test_monsters_exist_and_have_spawn_points() -> void:
	for floor_id in _floor_ids():
		var f := FloorFile.load(FloorFile.floor_path(floor_id))
		if f == null:
			fail("%s did not load" % floor_id)
			continue
		for zone in f.encounter_zones:
			assert_true(zone.spawn_points.size() >= zone.monster_ids.size(),
					"%s %s: one spawn point per monster" % [floor_id, zone.id])
			for mid in zone.monster_ids:
				assert_true(_monsters.has(mid), "%s %s: unknown monster '%s'" % [floor_id, zone.id, mid])


func test_monster_xp_matches_challenge_rating() -> void:
	for mid: String in _monsters.keys():
		var def: MonsterDefinition = _monsters[mid]
		var key := str(def.challenge_rating)
		assert_true(CR_XP.has(key), "%s: CR %s is in the table" % [mid, key])
		if CR_XP.has(key):
			assert_eq(def.xp, CR_XP[key], "%s: SRD XP for CR %s" % [mid, key])


func test_zone_budgets_fit_the_declared_band() -> void:
	for floor_id in _floor_ids():
		var raw := _raw(floor_id)
		var budget_v: Variant = raw.get("budget")
		assert_eq(typeof(budget_v), TYPE_DICTIONARY, "%s declares a budget" % floor_id)
		if typeof(budget_v) != TYPE_DICTIONARY:
			continue
		var budget: Dictionary = budget_v
		var level := DictUtil.to_int(budget.get("level", 0), 0)
		var lo := BANDS.find(str(budget.get("min", "")))
		var hi := BANDS.find(str(budget.get("max", "")))
		assert_true(THRESHOLDS.has(level), "%s: budget level %d has thresholds" % [floor_id, level])
		assert_true(lo >= 1 and hi >= lo, "%s: budget band %s..%s" % [floor_id, budget.get("min"), budget.get("max")])
		if not THRESHOLDS.has(level) or lo < 1 or hi < lo:
			continue
		for z in _raw_zones(raw):
			var ids := DictUtil.to_string_array(z.get("monster_ids", []))
			var adjusted := _adjusted_xp(ids)
			var band := _band(adjusted, level)
			var ctx := "%s %s (%s, adjusted XP %.1f) at level %d" % [floor_id, str(z.get("id")), BANDS[band], adjusted, level]
			if _is_boss(z):
				assert_true(band >= BANDS.find("deadly"), "%s: a boss zone is at least deadly" % ctx)
			elif _is_optional(z):
				assert_true(band >= lo, "%s: optional zone is at least %s" % [ctx, BANDS[lo]])
			else:
				assert_in_range(band, lo, hi, "%s: inside %s..%s" % [ctx, BANDS[lo], BANDS[hi]])


func test_only_the_last_floor_has_a_boss() -> void:
	var ids := _floor_ids()
	for i in range(ids.size()):
		var bosses := 0
		for z in _raw_zones(_raw(ids[i])):
			if _is_boss(z):
				bosses += 1
				assert_eq(str(z.get("kind", "")), "boss", "%s: boss zone kind" % ids[i])
				assert_false(_is_optional(z), "%s: the boss is not optional" % ids[i])
		assert_eq(bosses, 1 if i == ids.size() - 1 else 0, "%s boss zones" % ids[i])


func test_each_floor_has_one_optional_side_area() -> void:
	for floor_id in _floor_ids():
		var optional := 0
		for z in _raw_zones(_raw(floor_id)):
			if _is_optional(z):
				optional += 1
		assert_eq(optional, 1, "%s optional zones" % floor_id)


func test_floors_grow_and_zone_counts_never_drop() -> void:
	var prev_area := 0
	var prev_zones := 0
	var prev_w := 0
	var prev_h := 0
	for floor_id in _floor_ids():
		var f := FloorFile.load(FloorFile.floor_path(floor_id))
		if f == null:
			fail("%s did not load" % floor_id)
			continue
		var area := f.walk_map.width * f.walk_map.height
		assert_true(area > prev_area, "%s area %d grows past %d" % [floor_id, area, prev_area])
		assert_true(f.walk_map.width > prev_w and f.walk_map.height > prev_h, "%s is wider and taller" % floor_id)
		assert_true(f.encounter_zones.size() >= prev_zones, "%s zone count %d >= %d" % [floor_id, f.encounter_zones.size(), prev_zones])
		prev_area = area
		prev_w = f.walk_map.width
		prev_h = f.walk_map.height
		prev_zones = f.encounter_zones.size()


func test_shortest_route_crosses_a_zone() -> void:
	for floor_id in _floor_ids():
		var f := FloorFile.load(FloorFile.floor_path(floor_id))
		if f == null:
			fail("%s did not load" % floor_id)
			continue
		var path := f.walk_map.path_to(f.arrival, f.stairs, {})
		assert_false(path.is_empty(), "%s: stairs reachable" % floor_id)
		var crossed := false
		for p in path:
			if f.zone_at(p) != null:
				crossed = true
				break
		assert_true(crossed, "%s: the shortest route to the stairs crosses a zone" % floor_id)
		for zone in f.encounter_zones:
			if not zone.boss:
				continue
			var through_boss := false
			for p in path:
				if zone.rect.has_point(p):
					through_boss = true
					break
			assert_true(through_boss, "%s: the shortest route crosses boss zone %s" % [floor_id, zone.id])


func test_every_route_crosses_a_required_zone() -> void:
	for floor_id in _floor_ids():
		var f := FloorFile.load(FloorFile.floor_path(floor_id))
		if f == null:
			fail("%s did not load" % floor_id)
			continue
		var raw_zones := _raw_zones(_raw(floor_id))
		var blocked := {}
		for z in raw_zones:
			if _is_optional(z):
				continue
			var zone := f.get_zone(str(z.get("id", "")))
			if zone != null:
				blocked.merge(_rect_tiles(zone.rect))
		blocked.erase(f.stairs)  # a blocked goal would change path_to's meaning
		assert_true(f.walk_map.path_to(f.arrival, f.stairs, blocked).is_empty(),
				"%s: no route to the stairs avoids every required zone" % floor_id)


func test_optional_zones_are_off_the_route() -> void:
	for floor_id in _floor_ids():
		var f := FloorFile.load(FloorFile.floor_path(floor_id))
		if f == null:
			fail("%s did not load" % floor_id)
			continue
		for z in _raw_zones(_raw(floor_id)):
			if not _is_optional(z):
				continue
			var zone := f.get_zone(str(z.get("id", "")))
			if zone == null:
				fail("%s: zone %s missing" % [floor_id, str(z.get("id"))])
				continue
			assert_false(zone.rect.has_point(f.stairs), "%s %s: stairs are not in a side area" % [floor_id, zone.id])
			assert_false(f.walk_map.path_to(f.arrival, f.stairs, _rect_tiles(zone.rect)).is_empty(),
					"%s %s: the stairs stay reachable without entering the side area" % [floor_id, zone.id])


func test_boss_guards_the_stairs_on_the_last_floor() -> void:
	var ids := _floor_ids()
	if ids.is_empty():
		fail("no floors")
		return
	var f := FloorFile.load(FloorFile.floor_path(ids[ids.size() - 1]))
	if f == null:
		fail("last floor did not load")
		return
	var boss: EncounterZoneData = null
	for zone in f.encounter_zones:
		if zone.boss:
			boss = zone
	assert_not_null(boss, "the last floor has a boss zone")
	if boss == null:
		return
	if boss.rect.has_point(f.stairs):
		return
	for n in GridMath.neighbors8(f.stairs):
		if f.walk_map.is_walkable(n):
			assert_true(boss.rect.has_point(n), "tile %s next to the stairs is inside the boss zone" % str(n))


func test_full_clear_level_matches_each_floor_budget() -> void:
	# A solo who clears every zone arrives on each floor at its budget level.
	var cumulative := 0
	for floor_id in _floor_ids():
		var f := FloorFile.load(FloorFile.floor_path(floor_id))
		if f == null:
			fail("%s did not load" % floor_id)
			continue
		var budget_v: Variant = _raw(floor_id).get("budget", {})
		var budget: Dictionary = budget_v if typeof(budget_v) == TYPE_DICTIONARY else {}
		var level := DictUtil.to_int(budget.get("level", 0), 0)
		assert_eq(Experience.level_for_xp(cumulative), level,
				"%s: a full-clear solo arrives with %d XP" % [floor_id, cumulative])
		cumulative += _floor_xp(f)


func test_a_party_of_three_can_face_the_boss() -> void:
	# XP is split across the party, so a party of three arrives on the last
	# floor at a lower level than a solo; the boss must still be at most hard
	# for them, while it is deadly for a solo (test_zone_budgets_fit_the_declared_band).
	var ids := _floor_ids()
	var cumulative := 0
	for i in range(ids.size()):
		var f := FloorFile.load(FloorFile.floor_path(ids[i]))
		if f == null:
			fail("%s did not load" % ids[i])
			return
		if i < ids.size() - 1:
			cumulative += _floor_xp(f)
			continue
		var party_level := Experience.level_for_xp(cumulative / 3)
		for zone in f.encounter_zones:
			if zone.boss:
				var band := _band(_adjusted_xp(zone.monster_ids), party_level, 3)
				assert_true(band <= BANDS.find("hard"),
						"boss is %s for three level-%d characters" % [BANDS[band], party_level])

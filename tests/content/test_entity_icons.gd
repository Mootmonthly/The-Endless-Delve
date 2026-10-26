extends TestCase
## The entity icon atlas from tools/gen_tileset.py: the TileSet loads, every id
## in entity_icons.json maps to a tile that exists, and every class, monster
## and item kind in data/ has an icon.

const TILESET_PATH := "res://assets/icons/entity_icons.tres"
const MAP_PATH := "res://assets/icons/entity_icons.json"
const ITEM_KINDS: Array[String] = ["weapon", "armor", "shield", "consumable", "ammo", "gold", "misc"]

var _map: Dictionary = {}


func before_each() -> void:
	if _map.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MAP_PATH))
		if typeof(parsed) == TYPE_DICTIONARY:
			_map = parsed


func _icons() -> Dictionary:
	var v: Variant = _map.get("icons", {})
	if typeof(v) != TYPE_DICTIONARY:
		return {}
	var d: Dictionary = v
	return d


func _atlas() -> TileSetAtlasSource:
	var res: Resource = load(TILESET_PATH)
	if not (res is TileSet):
		return null
	var ts: TileSet = res
	if ts.tile_size != Vector2i(32, 32) or not ts.has_source(0):
		return null
	var src: TileSetSource = ts.get_source(0)
	if not (src is TileSetAtlasSource):
		return null
	var atlas: TileSetAtlasSource = src
	return atlas


func test_tileset_loads_with_one_tile_per_column() -> void:
	assert_false(_map.is_empty(), "entity_icons.json parses")
	var atlas := _atlas()
	assert_not_null(atlas, "entity_icons.tres is a 32x32 TileSet with atlas source 0")
	if atlas == null:
		return
	var columns := DictUtil.to_int(_map.get("columns", 0), 0)
	assert_true(columns > 0, "columns")
	assert_eq(atlas.texture_region_size, Vector2i(32, 32))
	assert_eq(atlas.get_tiles_count(), columns)
	assert_not_null(atlas.texture)
	if atlas.texture != null:
		assert_eq(atlas.texture.get_size(), Vector2(32 * columns, 32))
	assert_eq(DictUtil.to_int(_map.get("tile_size", 0), 0), 32)
	assert_eq(str(_map.get("tileset", "")), TILESET_PATH)


func test_every_icon_id_maps_to_a_valid_column() -> void:
	var atlas := _atlas()
	var columns := DictUtil.to_int(_map.get("columns", 0), 0)
	var used := {}
	for id: String in _icons().keys():
		var col := DictUtil.to_int(_icons()[id], -1)
		assert_in_range(col, 0, columns - 1, "icon '%s' column" % id)
		if atlas != null:
			assert_true(atlas.has_tile(Vector2i(col, 0)), "icon '%s' tile exists" % id)
		used[col] = true
	assert_eq(used.size(), columns, "every column is used by some id")
	# Every glyph is its own column except declared aliases.
	var aliases: Dictionary = _map.get("aliases", {})
	var by_col := {}
	for id: String in _icons().keys():
		if aliases.has(id):
			assert_eq(_icons()[id], _icons().get(str(aliases[id])), "alias '%s' shares its target's column" % id)
			continue
		var col := DictUtil.to_int(_icons()[id], -1)
		assert_false(by_col.has(col), "'%s' and '%s' share column %d" % [id, str(by_col.get(col, "")), col])
		by_col[col] = id


func test_classes_monsters_and_item_kinds_have_icons() -> void:
	var icons := _icons()
	for path in ContentLoader.json_files("res://data/classes"):
		var cid := path.get_file().get_basename()
		assert_true(icons.has(cid), "class '%s' has an icon" % cid)
	for path in ContentLoader.json_files("res://data/monsters"):
		var mid := path.get_file().get_basename()
		assert_true(icons.has(mid), "monster '%s' has an icon" % mid)
	for kind in ITEM_KINDS:
		assert_true(icons.has(kind), "item kind '%s' has an icon" % kind)
	for extra in ["potion", "chest_closed", "chest_open"]:
		assert_true(icons.has(extra), "'%s' has an icon" % extra)
	var groups: Dictionary = _map.get("groups", {})
	for g in ["classes", "monsters", "items"]:
		for id in DictUtil.to_string_array(groups.get(g, [])):
			assert_true(icons.has(id), "group %s id '%s' has a column" % [g, id])

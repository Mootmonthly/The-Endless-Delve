extends TestCase
## assets/tiles/dungeon_tiles.tres (built by tools/build_tiles.py): legacy row 0
## kept, the 47 blob wall tiles carry terrain set 0, animated tiles, and the
## json map agrees with FloorView's constants.

const TILESET_PATH := "res://assets/tiles/dungeon_tiles.tres"
const MAP_PATH := "res://assets/tiles/dungeon_tiles.json"
const MAX_ATLAS_BYTES := 2 * 1024 * 1024


func _atlas() -> TileSetAtlasSource:
	var res: Resource = load(TILESET_PATH)
	if not (res is TileSet):
		return null
	var ts: TileSet = res
	return ts.get_source(0) as TileSetAtlasSource


func _map() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MAP_PATH))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


func _coords(name: String) -> Vector2i:
	var arr: Array = (_map().get("tiles", {}) as Dictionary).get(name, [-1, -1])
	return Vector2i(int(arr[0]), int(arr[1]))


func test_tileset_loads_with_legacy_row() -> void:
	var res: Resource = load(TILESET_PATH)
	assert_true(res is TileSet, "dungeon_tiles.tres must be a TileSet")
	if not (res is TileSet):
		return
	var ts: TileSet = res
	assert_eq(ts.tile_size, Vector2i(32, 32))
	assert_true(ts.has_source(0), "atlas source 0")
	var atlas := _atlas()
	assert_not_null(atlas)
	if atlas == null:
		return
	assert_eq(atlas.texture_region_size, Vector2i(32, 32))
	for i in range(16):
		assert_true(atlas.has_tile(Vector2i(i, 0)), "row 0 tile %d exists" % i)
	assert_not_null(atlas.texture)
	if atlas.texture != null:
		assert_eq(atlas.texture.get_size(), Vector2(512, 192))
	assert_true(FileAccess.get_file_as_bytes("res://assets/tiles/dungeon_tiles.png").size() < MAX_ATLAS_BYTES, "atlas under 2 MB")


func test_wall_terrain_set() -> void:
	var res: Resource = load(TILESET_PATH)
	var ts: TileSet = res as TileSet
	var atlas := _atlas()
	if ts == null or atlas == null:
		fail("tileset missing")
		return
	assert_eq(ts.get_terrain_sets_count(), 1)
	assert_eq(ts.get_terrain_set_mode(0), TileSet.TERRAIN_MODE_MATCH_CORNERS_AND_SIDES)
	assert_eq(ts.get_terrains_count(0), 1)
	var masks := FloorView.blob_masks()
	assert_eq(masks.size(), 47, "the 47-tile blob set")
	var bits := [[FloorView.BIT_N, TileSet.CELL_NEIGHBOR_TOP_SIDE], [FloorView.BIT_NE, TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER],
		[FloorView.BIT_E, TileSet.CELL_NEIGHBOR_RIGHT_SIDE], [FloorView.BIT_SE, TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER],
		[FloorView.BIT_S, TileSet.CELL_NEIGHBOR_BOTTOM_SIDE], [FloorView.BIT_SW, TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER],
		[FloorView.BIT_W, TileSet.CELL_NEIGHBOR_LEFT_SIDE], [FloorView.BIT_NW, TileSet.CELL_NEIGHBOR_TOP_LEFT_CORNER]]
	var json_masks: Array[int] = []
	for v: Variant in (_map().get("blob_masks", []) as Array):
		json_masks.append(int(v))
	assert_eq(json_masks, masks, "json lists the same masks")
	for m in masks:
		var c := FloorView.wall_atlas_coords(m)
		assert_true(atlas.has_tile(c), "wall tile for mask %d" % m)
		if not atlas.has_tile(c):
			continue
		var td := atlas.get_tile_data(c, 0)
		assert_eq(td.terrain_set, 0, "mask %d terrain set" % m)
		assert_eq(td.terrain, 0, "mask %d terrain" % m)
		for pair: Array in bits:
			var want := 0 if m & int(pair[0]) else -1
			assert_eq(td.get_terrain_peering_bit(pair[1]), want, "mask %d peering bit %d" % [m, int(pair[0])])


func test_animated_tiles() -> void:
	var atlas := _atlas()
	if atlas == null:
		fail("tileset missing")
		return
	for name: String in ["brazier", "landing", "torch"]:
		var c := _coords(name)
		assert_true(atlas.has_tile(c), "%s tile" % name)
		if atlas.has_tile(c):
			assert_eq(atlas.get_tile_animation_frames_count(c), 2, "%s flickers on two frames" % name)
	assert_eq(_coords("brazier"), FloorView.prop_atlas_coords("brazier"))
	assert_eq(_coords("torch"), FloorView.ATLAS_TORCH)
	assert_eq(_coords("landing"), FloorView.ATLAS_LANDING_GLOW)


func test_json_matches_floor_view_constants() -> void:
	assert_eq(_coords("floor"), Vector2i(FloorView.TILE_FLOOR, 0))
	assert_eq(_coords("wall"), Vector2i(FloorView.TILE_WALL, 0))
	assert_eq(_coords("stairs"), Vector2i(FloorView.TILE_STAIRS, 0))
	assert_eq(_coords("arrival"), Vector2i(FloorView.TILE_ARRIVAL, 0))
	assert_eq(_coords("zone_floor"), Vector2i(FloorView.TILE_ZONE_FLOOR, 0))
	assert_eq(_coords("player"), Vector2i(FloorView.TILE_PLAYER, 0))
	assert_eq(_coords("monster"), Vector2i(FloorView.TILE_MONSTER, 0))
	assert_eq(_coords("unconscious"), Vector2i(FloorView.TILE_UNCONSCIOUS, 0))
	assert_eq(_coords("selection"), Vector2i(FloorView.TILE_SELECTION, 0))
	assert_eq(_coords("zone_tint"), FloorView.ATLAS_ZONE_TINT)
	for key: String in FloorView.ATLAS_FLOOR_VARIANTS.keys():
		var name := "floor" if key == "plain" else "floor_%s" % key
		assert_eq(_coords(name), FloorView.ATLAS_FLOOR_VARIANTS[key], name)
	for key: String in FloorView.ATLAS_DOORS.keys():
		var parts := key.split("_")
		assert_eq(_coords("door_%s_%s" % [parts[0], parts[1]]), FloorView.ATLAS_DOORS[key], key)
	for kind: String in PropData.KINDS:
		assert_eq(_coords(kind), FloorView.prop_atlas_coords(kind), kind)
		assert_eq(_coords("%s_damaged" % kind), FloorView.prop_atlas_coords(kind, FloorView.PROP_DAMAGED), kind + " damaged")
	for key: String in FloorView.ATLAS_DECALS.keys():
		assert_eq(_coords("decal_%s" % key), FloorView.ATLAS_DECALS[key], key)


func test_light_texture_and_provenance() -> void:
	var tex: Resource = load(FloorView.LIGHT_TEXTURE_PATH)
	assert_true(tex is Texture2D, "light_soft.png loads")
	assert_true(FileAccess.file_exists("res://assets/third_party/kenney_tiny_dungeon/PROVENANCE.md"), "third-party art records its provenance")

extends TestCase

const TILESET_PATH := "res://assets/tiles/dungeon_tiles.tres"


func test_tileset_loads_with_nine_tiles() -> void:
	var res: Resource = load(TILESET_PATH)
	assert_true(res is TileSet, "dungeon_tiles.tres must be a TileSet")
	if not (res is TileSet):
		return
	var ts: TileSet = res
	assert_eq(ts.tile_size, Vector2i(32, 32))
	assert_true(ts.has_source(0), "atlas source 0")
	var src: TileSetSource = ts.get_source(0)
	assert_true(src is TileSetAtlasSource)
	if not (src is TileSetAtlasSource):
		return
	var atlas: TileSetAtlasSource = src
	assert_eq(atlas.texture_region_size, Vector2i(32, 32))
	assert_eq(atlas.get_tiles_count(), 9)
	for i in range(9):
		assert_true(atlas.has_tile(Vector2i(i, 0)), "tile %d exists" % i)
	assert_not_null(atlas.texture)
	if atlas.texture != null:
		assert_eq(atlas.texture.get_size(), Vector2(288, 32))

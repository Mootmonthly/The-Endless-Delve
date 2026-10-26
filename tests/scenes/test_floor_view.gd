extends TestCase

const SCENE_PATH := "res://scenes/floor/floor_view.tscn"


func _view() -> FloorView:
	var packed: PackedScene = load(SCENE_PATH)
	var node: Node = packed.instantiate()
	return node as FloorView


func _wall_count(f: FloorData) -> int:
	var n := 0
	for y in range(f.walk_map.height):
		for x in range(f.walk_map.width):
			if not f.walk_map.is_walkable(Vector2i(x, y)):
				n += 1
	return n


func test_build_floor_001_draws_every_cell() -> void:
	var f := FloorFile.load("res://floors/floor_001.json")
	var view := _view()
	assert_not_null(view, "scene root is a FloorView")
	if f == null or view == null:
		fail("floor or view missing")
		if view != null:
			view.free()
		return
	view.build(f)
	var walls: TileMapLayer = view.get_node("Walls")
	var ground: TileMapLayer = view.get_node("Ground")
	var overlay: TileMapLayer = view.get_node("Overlay")
	var wall_count := _wall_count(f)
	assert_eq(wall_count, 854)
	assert_eq(walls.get_used_cells().size(), wall_count)
	assert_eq(ground.get_used_cells().size(), f.walk_map.width * f.walk_map.height - wall_count)
	assert_eq(overlay.get_cell_atlas_coords(f.arrival), Vector2i(FloorView.TILE_ARRIVAL, 0))
	assert_eq(overlay.get_cell_atlas_coords(f.stairs), Vector2i(FloorView.TILE_STAIRS, 0))
	assert_eq(walls.get_cell_source_id(Vector2i(0, 0)), FloorView.SOURCE_ID)
	assert_eq(ground.get_cell_source_id(Vector2i(0, 0)), -1, "no ground under walls")
	view.free()


func test_rebuild_clears_previous_cells() -> void:
	var f := FloorFile.load("res://floors/floor_001.json")
	var view := _view()
	if f == null or view == null:
		fail("floor or view missing")
		if view != null:
			view.free()
		return
	view.build(f)
	view.build(f)
	var walls: TileMapLayer = view.get_node("Walls")
	assert_eq(walls.get_used_cells().size(), _wall_count(f))
	view.free()


func test_zone_highlight_toggles_walkable_cells_only() -> void:
	var f := FloorFile.load("res://floors/floor_001.json")
	var view := _view()
	if f == null or view == null:
		fail("floor or view missing")
		if view != null:
			view.free()
		return
	view.build(f)
	var ground: TileMapLayer = view.get_node("Ground")
	var rect: Rect2i = f.encounter_zones[0].rect
	var inside := Vector2i(24, 3)
	var pillar := Vector2i(20, 4)
	view.set_zone_highlight(rect, true)
	assert_eq(ground.get_cell_atlas_coords(inside), Vector2i(FloorView.TILE_ZONE_FLOOR, 0))
	assert_eq(ground.get_cell_source_id(pillar), -1, "walls inside the zone get no ground")
	assert_eq(ground.get_cell_atlas_coords(f.arrival), Vector2i(FloorView.TILE_FLOOR, 0), "outside untouched")
	view.set_zone_highlight(rect, false)
	assert_eq(ground.get_cell_atlas_coords(inside), Vector2i(FloorView.TILE_FLOOR, 0))
	view.free()


func test_tile_world_conversion() -> void:
	assert_eq(FloorView.tile_to_world(Vector2i(0, 0)), Vector2(16, 16))
	assert_eq(FloorView.tile_to_world(Vector2i(3, 2)), Vector2(112, 80))
	assert_eq(FloorView.world_to_tile(Vector2(112, 80)), Vector2i(3, 2))
	assert_eq(FloorView.world_to_tile(Vector2(31.9, 0)), Vector2i(0, 0))
	assert_eq(FloorView.world_to_tile(Vector2(-0.5, -40)), Vector2i(-1, -2))
	for p: Vector2i in [Vector2i(0, 0), Vector2i(47, 31), Vector2i(-3, 5)]:
		assert_eq(FloorView.world_to_tile(FloorView.tile_to_world(p)), p)

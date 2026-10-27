extends TestCase
## FloorView draws floor_001 (v2): every cell, blob walls, landings, stairs,
## doors, props, torches with lights, darkness and the zone tint.

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


func _built() -> Array:
	var f := FloorFile.load("res://floors/floor_001.json")
	var view := _view()
	if f == null or view == null:
		fail("floor or view missing")
		if view != null:
			view.free()
		return []
	view.build(f)
	return [f, view]


func test_build_floor_001_draws_every_cell() -> void:
	var built := _built()
	if built.is_empty():
		return
	var f: FloorData = built[0]
	var view: FloorView = built[1]
	var walls: TileMapLayer = view.get_node("Walls")
	var ground: TileMapLayer = view.get_node("Ground")
	var overlay: TileMapLayer = view.get_node("Overlay")
	var wall_count := _wall_count(f)
	assert_eq(walls.get_used_cells().size(), wall_count)
	assert_eq(ground.get_used_cells().size(), f.walk_map.width * f.walk_map.height - wall_count)
	assert_eq(overlay.get_cell_atlas_coords(f.arrival), Vector2i(FloorView.TILE_ARRIVAL, 0))
	assert_eq(overlay.get_cell_atlas_coords(f.stairs), Vector2i(FloorView.TILE_STAIRS, 0))
	for l in f.landings:
		assert_eq(overlay.get_cell_atlas_coords(l.position), Vector2i(FloorView.TILE_ARRIVAL, 0), "landing %s rune" % l.id)
	assert_eq(walls.get_cell_source_id(Vector2i(0, 0)), FloorView.SOURCE_ID)
	assert_eq(walls.get_cell_atlas_coords(Vector2i(0, 0)), FloorView.wall_atlas_coords(255), "the map edge is solid wall")
	assert_eq(ground.get_cell_source_id(Vector2i(0, 0)), -1, "no ground under walls")
	view.free()


func test_walls_use_the_blob_lookup() -> void:
	var built := _built()
	if built.is_empty():
		return
	var f: FloorData = built[0]
	var view: FloorView = built[1]
	var walls: TileMapLayer = view.get_node("Walls")
	var seen := {}
	for c in walls.get_used_cells():
		var want := FloorView.wall_atlas_coords(FloorView.wall_mask(f.walk_map, c))
		assert_eq(walls.get_cell_atlas_coords(c), want, "wall %s" % str(c))
		seen[want] = true
		if seen.size() > 12:
			break
	# a pillar (wall with floor on all four sides) is the isolated blob tile
	var pillar := Vector2i(-1, -1)
	for y in range(1, f.walk_map.height - 1):
		for x in range(1, f.walk_map.width - 1):
			var p := Vector2i(x, y)
			if not f.walk_map.is_walkable(p) and FloorView.wall_mask(f.walk_map, p) == 0:
				pillar = p
				break
		if pillar.x >= 0:
			break
	assert_true(pillar.x >= 0, "floor_001 has pillars")
	if pillar.x >= 0:
		assert_eq(walls.get_cell_atlas_coords(pillar), FloorView.wall_atlas_coords(0))
	view.free()


func test_floor_variants_are_stable() -> void:
	var built := _built()
	if built.is_empty():
		return
	var f: FloorData = built[0]
	var view: FloorView = built[1]
	var ground: TileMapLayer = view.get_node("Ground")
	var variants := {}
	var first := {}
	for c in ground.get_used_cells():
		variants[ground.get_cell_atlas_coords(c)] = true
		if first.size() < 50:
			first[c] = ground.get_cell_atlas_coords(c)
	assert_true(variants.size() >= 4, "several floor variants are used (%d)" % variants.size())
	view.build(f)
	for c: Vector2i in first.keys():
		assert_eq(ground.get_cell_atlas_coords(c), first[c], "variant at %s is stable across builds" % str(c))
	view.free()


func test_doors_props_and_lights() -> void:
	var built := _built()
	if built.is_empty():
		return
	var f: FloorData = built[0]
	var view: FloorView = built[1]
	var doors: TileMapLayer = view.get_node("Doors")
	var props: TileMapLayer = view.get_node("Props")
	var wall_decor: TileMapLayer = view.get_node("WallDecor")
	assert_eq(doors.get_used_cells().size(), f.doors.size(), "one door tile per door")
	assert_eq(props.get_used_cells().size(), f.props.size(), "one prop tile per prop")
	for d in f.doors:
		var key := "%s_%s" % [d.state, FloorView.door_orientation(f.walk_map, d.position)]
		assert_eq(doors.get_cell_atlas_coords(d.position), FloorView.ATLAS_DOORS[key], "door %s" % d.id)
	var braziers := 0
	for p in f.props:
		assert_eq(props.get_cell_atlas_coords(p.position), FloorView.prop_atlas_coords(p.kind), "prop %s" % p.id)
		if p.kind == PropData.KIND_BRAZIER:
			braziers += 1
	var torches := view.torch_cells()
	assert_true(torches.size() > 0, "torches on the walls")
	assert_eq(wall_decor.get_used_cells().size(), torches.size())
	for t in torches:
		assert_false(f.walk_map.is_walkable(t), "a torch hangs on a wall")
		assert_true(f.walk_map.is_walkable(t + Vector2i.DOWN), "facing the floor")
	assert_eq(view.light_count(), torches.size() + braziers, "one light per torch and brazier")
	var darkness: CanvasModulate = view.get_node("Darkness")
	assert_eq(darkness.color, Color(str(view.style["darkness"])), "theme darkness")
	assert_true(darkness.visible)
	assert_not_null((view.get_node("Lights/PlayerLight") as PointLight2D).texture, "the player light has a texture")
	view.set_lighting_enabled(false)
	assert_false(darkness.visible, "lighting can be switched off")
	view.free()


func test_door_and_prop_state_hooks() -> void:
	var built := _built()
	if built.is_empty():
		return
	var f: FloorData = built[0]
	var view: FloorView = built[1]
	var doors: TileMapLayer = view.get_node("Doors")
	var props: TileMapLayer = view.get_node("Props")
	var door := f.doors[0]
	view.set_door_state(door.id, DoorData.STATE_OPEN)
	var key := "open_%s" % FloorView.door_orientation(f.walk_map, door.position)
	assert_eq(doors.get_cell_atlas_coords(door.position), FloorView.ATLAS_DOORS[key])
	var brazier: PropData = null
	var barrel: PropData = null
	for p in f.props:
		if p.kind == PropData.KIND_BRAZIER and brazier == null:
			brazier = p
		if p.kind == PropData.KIND_BARREL and barrel == null:
			barrel = p
	if barrel != null:
		view.set_prop_state(barrel.id, FloorView.PROP_DAMAGED)
		assert_eq(props.get_cell_atlas_coords(barrel.position), FloorView.prop_atlas_coords("barrel", FloorView.PROP_DAMAGED))
		view.set_prop_state(barrel.id, FloorView.PROP_DESTROYED)
		assert_eq(props.get_cell_source_id(barrel.position), -1, "a destroyed prop is gone")
		assert_eq(view.prop_state(barrel.id), FloorView.PROP_DESTROYED)
	if brazier != null:
		var before := view.light_count()
		view.set_prop_state(brazier.id, FloorView.PROP_DESTROYED)
		assert_eq(view.light_count(), before - 1, "a broken brazier goes dark")
	view.free()


func test_rebuild_clears_previous_cells() -> void:
	var built := _built()
	if built.is_empty():
		return
	var f: FloorData = built[0]
	var view: FloorView = built[1]
	var lights := view.light_count()
	view.build(f)
	var walls: TileMapLayer = view.get_node("Walls")
	assert_eq(walls.get_used_cells().size(), _wall_count(f))
	assert_eq(view.light_count(), lights, "lights are rebuilt, not duplicated")
	view.free()


func test_zone_highlight_toggles_walkable_cells_only() -> void:
	var built := _built()
	if built.is_empty():
		return
	var f: FloorData = built[0]
	var view: FloorView = built[1]
	var tint: TileMapLayer = view.get_node("Tint")
	var ground: TileMapLayer = view.get_node("Ground")
	var zone := f.get_zone("z1")
	var rect: Rect2i = zone.rect
	var inside := zone.spawn_points[0]
	var before := ground.get_cell_atlas_coords(inside)
	view.set_zone_highlight(rect, true)
	assert_eq(tint.get_cell_atlas_coords(inside), FloorView.ATLAS_ZONE_TINT)
	var walls_inside := 0
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			if not f.walk_map.is_walkable(Vector2i(x, y)):
				walls_inside += 1
				assert_eq(tint.get_cell_source_id(Vector2i(x, y)), -1, "walls inside the zone get no tint")
	assert_true(walls_inside > 0, "the pack room has pillars")
	assert_eq(tint.get_cell_source_id(f.arrival), -1, "outside untouched")
	assert_eq(ground.get_cell_atlas_coords(inside), before, "the ground keeps its variant")
	view.set_zone_highlight(rect, false)
	assert_eq(tint.get_cell_source_id(inside), -1)
	view.free()


func test_theme_style_resolution() -> void:
	var f := FloorData.new()
	f.theme = "The Barrow Warrens"
	var st := FloorView.resolve_style(f)
	assert_eq(str(st["darkness"]), str(FloorView.THEME_STYLES["The Barrow Warrens"]["darkness"]), "theme default")
	f.theme_style = {"darkness": "#101010", "floor_variant_weights": {"puddle": 0.0}}
	st = FloorView.resolve_style(f)
	assert_eq(str(st["darkness"]), "#101010", "the floor overrides its theme")
	var weights: Dictionary = st["floor_variant_weights"]
	assert_eq(float(weights["puddle"]), 0.0)
	assert_eq(float(weights["plain"]), float(FloorView.DEFAULT_STYLE["floor_variant_weights"]["plain"]), "weights merge key by key")
	var plain := FloorView.resolve_style(FloorData.new())
	assert_eq(str(plain["darkness"]), str(FloorView.DEFAULT_STYLE["darkness"]), "no theme: defaults")


func test_tile_world_conversion() -> void:
	assert_eq(FloorView.tile_to_world(Vector2i(0, 0)), Vector2(16, 16))
	assert_eq(FloorView.tile_to_world(Vector2i(3, 2)), Vector2(112, 80))
	assert_eq(FloorView.world_to_tile(Vector2(112, 80)), Vector2i(3, 2))
	assert_eq(FloorView.world_to_tile(Vector2(31.9, 0)), Vector2i(0, 0))
	assert_eq(FloorView.world_to_tile(Vector2(-0.5, -40)), Vector2i(-1, -2))
	for p: Vector2i in [Vector2i(0, 0), Vector2i(47, 31), Vector2i(-3, 5)]:
		assert_eq(FloorView.world_to_tile(FloorView.tile_to_world(p)), p)


func test_v1_floor_still_draws() -> void:
	var f := FloorData.from_dict({"schema_version": 1, "id": "old", "rows": ["#####", "#A.S#", "#####"],
		"arrival": [1, 1], "stairs": [3, 1]})
	var view := _view()
	view.build(f)
	var overlay: TileMapLayer = view.get_node("Overlay")
	assert_eq(overlay.get_cell_atlas_coords(Vector2i(1, 1)), Vector2i(FloorView.TILE_ARRIVAL, 0))
	assert_eq((view.get_node("Walls") as TileMapLayer).get_used_cells().size(), 12)
	assert_eq(view.light_count(), view.torch_cells().size(), "lights only for torches (no props on a v1 floor)")
	view.free()

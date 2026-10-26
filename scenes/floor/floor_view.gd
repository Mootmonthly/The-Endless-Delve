class_name FloorView
extends Node2D
## Presentation of one floor: draws a core FloorData onto three TileMapLayers
## that share assets/tiles/dungeon_tiles.tres (atlas source 0, one row of tiles).
##
##   Ground  - floor tiles under every walkable cell (zone tint when highlighted)
##   Walls   - one wall tile per non-walkable cell
##   Overlay - arrival and stairs markers (and, later, other static markers)
##
## Pure view: it reads FloorData and never changes it. Tile (x, y) has its
## top-left corner at world (x * TILE_SIZE, y * TILE_SIZE).

const TILE_SIZE := 32
const SOURCE_ID := 0

## Atlas column of each tile in dungeon_tiles.png (see tools/gen_tileset.py).
const TILE_FLOOR := 0
const TILE_WALL := 1
const TILE_STAIRS := 2
const TILE_ARRIVAL := 3
const TILE_ZONE_FLOOR := 4
const TILE_PLAYER := 5
const TILE_MONSTER := 6
const TILE_UNCONSCIOUS := 7
const TILE_SELECTION := 8

@onready var ground: TileMapLayer = $Ground
@onready var walls: TileMapLayer = $Walls
@onready var overlay: TileMapLayer = $Overlay

var floor_data: FloorData = null


## Clears all layers and draws the floor: ground, walls, arrival and stairs.
func build(new_floor: FloorData) -> void:
	_bind_layers()
	floor_data = new_floor
	ground.clear()
	walls.clear()
	overlay.clear()
	if new_floor == null or new_floor.walk_map == null:
		push_error("FloorView.build: no floor data")
		return
	var wm: WalkMap = new_floor.walk_map
	for y in range(wm.height):
		for x in range(wm.width):
			var p := Vector2i(x, y)
			if wm.is_walkable(p):
				ground.set_cell(p, SOURCE_ID, Vector2i(TILE_FLOOR, 0))
			else:
				walls.set_cell(p, SOURCE_ID, Vector2i(TILE_WALL, 0))
	overlay.set_cell(new_floor.arrival, SOURCE_ID, Vector2i(TILE_ARRIVAL, 0))
	overlay.set_cell(new_floor.stairs, SOURCE_ID, Vector2i(TILE_STAIRS, 0))


## Tints (on) or restores (off) the walkable ground cells inside rect.
func set_zone_highlight(rect: Rect2i, on: bool) -> void:
	_bind_layers()
	if floor_data == null or floor_data.walk_map == null:
		return
	var tile := TILE_ZONE_FLOOR if on else TILE_FLOOR
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var p := Vector2i(x, y)
			if floor_data.walk_map.in_bounds(p) and floor_data.walk_map.is_walkable(p):
				ground.set_cell(p, SOURCE_ID, Vector2i(tile, 0))


## World-space centre of tile p.
static func tile_to_world(p: Vector2i) -> Vector2:
	return Vector2(p.x * TILE_SIZE + TILE_SIZE / 2.0, p.y * TILE_SIZE + TILE_SIZE / 2.0)


## Tile containing world point w.
static func world_to_tile(w: Vector2) -> Vector2i:
	return Vector2i(floori(w.x / TILE_SIZE), floori(w.y / TILE_SIZE))


## Lets build() work before the node enters the tree (e.g. in headless tests).
func _bind_layers() -> void:
	if ground == null:
		ground = get_node("Ground")
	if walls == null:
		walls = get_node("Walls")
	if overlay == null:
		overlay = get_node("Overlay")

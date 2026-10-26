class_name ReachOverlay
extends Node2D
## Tints the tiles the player can reach this turn and outlines the hovered tile.

const FILL := Color(0.35, 0.75, 1.0, 0.22)
const EDGE := Color(0.35, 0.75, 1.0, 0.55)
const HOVER := Color(1.0, 0.9, 0.3, 0.9)
const NO_HOVER := Vector2i(-1, -1)

var tiles: Array[Vector2i] = []
var hover: Vector2i = NO_HOVER


func set_tiles(new_tiles: Array[Vector2i]) -> void:
	if new_tiles == tiles:
		return
	tiles = new_tiles
	queue_redraw()


func set_hover(tile: Vector2i) -> void:
	if tile == hover:
		return
	hover = tile
	queue_redraw()


func _draw() -> void:
	var size := Vector2(FloorView.TILE_SIZE, FloorView.TILE_SIZE)
	for t in tiles:
		var r := Rect2(Vector2(t * FloorView.TILE_SIZE), size)
		draw_rect(r, FILL, true)
		draw_rect(r.grow(-1.0), EDGE, false, 1.0)
	if hover != NO_HOVER:
		draw_rect(Rect2(Vector2(hover * FloorView.TILE_SIZE), size).grow(-1.0), HOVER, false, 2.0)

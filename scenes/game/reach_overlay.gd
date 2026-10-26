class_name ReachOverlay
extends Node2D
## Tints the tiles the player can reach this turn, the tiles in range of the
## selected ranged attack / spell / feature (normal range and, fainter, long
## range with disadvantage), and outlines the hovered tile (gold, or violet
## while picking a target). While an area spell is being aimed it also shows
## the footprint under the cursor (ClientState.area_preview: sphere / cube
## around the point, cone / line from the caster) and rings the creatures it
## would catch (red) or that Sculpt Spells spares (green).

const FILL := Color(0.35, 0.75, 1.0, 0.22)
const EDGE := Color(0.35, 0.75, 1.0, 0.55)
const RANGE_NORMAL := Color(1.0, 0.55, 0.2, 0.16)
const RANGE_LONG := Color(1.0, 0.3, 0.2, 0.08)
const HOVER := Color(1.0, 0.9, 0.3, 0.9)
const HOVER_TARGETING := Color(0.85, 0.5, 1.0, 0.95)
const NO_HOVER := Vector2i(-1, -1)
const AREA_FILL := Color(1.0, 0.35, 0.1, 0.30)
const AREA_FILL_INVALID := Color(0.5, 0.5, 0.5, 0.25)
const AFFECTED := Color(1.0, 0.15, 0.1, 0.95)
const SPARED := Color(0.3, 1.0, 0.4, 0.95)

var tiles: Array[Vector2i] = []
## Vector2i -> 0 (normal range) / 1 (long range).
var range_tiles: Dictionary = {}
var hover: Vector2i = NO_HOVER
var targeting: bool = false
## Area footprint under the cursor and the tiles of the creatures it catches / spares.
var area_tiles: Array[Vector2i] = []
var affected_tiles: Array[Vector2i] = []
var spared_tiles: Array[Vector2i] = []
var area_valid: bool = true


func set_tiles(new_tiles: Array[Vector2i]) -> void:
	if new_tiles == tiles:
		return
	tiles = new_tiles
	queue_redraw()


func set_range(new_range: Dictionary, is_targeting: bool = false) -> void:
	if new_range == range_tiles and is_targeting == targeting:
		return
	range_tiles = new_range
	targeting = is_targeting
	queue_redraw()


## Shows an area preview (tiles, creature tiles caught / spared); empty clears it.
func set_area(tiles_in: Array[Vector2i], affected: Array[Vector2i] = [], spared: Array[Vector2i] = [], valid: bool = true) -> void:
	if tiles_in == area_tiles and affected == affected_tiles and spared == spared_tiles and valid == area_valid:
		return
	area_tiles = tiles_in
	affected_tiles = affected
	spared_tiles = spared
	area_valid = valid
	queue_redraw()


func set_hover(tile: Vector2i) -> void:
	if tile == hover:
		return
	hover = tile
	queue_redraw()


func _draw() -> void:
	var size := Vector2(FloorView.TILE_SIZE, FloorView.TILE_SIZE)
	for key: Variant in range_tiles.keys():
		var t: Vector2i = key
		var r := Rect2(Vector2(t * FloorView.TILE_SIZE), size)
		draw_rect(r, RANGE_NORMAL if int(range_tiles[key]) == 0 else RANGE_LONG, true)
	for t in tiles:
		var r := Rect2(Vector2(t * FloorView.TILE_SIZE), size)
		draw_rect(r, FILL, true)
		draw_rect(r.grow(-1.0), EDGE, false, 1.0)
	for t in area_tiles:
		draw_rect(Rect2(Vector2(t * FloorView.TILE_SIZE), size), AREA_FILL if area_valid else AREA_FILL_INVALID, true)
	for t in affected_tiles:
		draw_rect(Rect2(Vector2(t * FloorView.TILE_SIZE), size).grow(-2.0), AFFECTED, false, 2.0)
	for t in spared_tiles:
		draw_rect(Rect2(Vector2(t * FloorView.TILE_SIZE), size).grow(-2.0), SPARED, false, 2.0)
	if hover != NO_HOVER:
		draw_rect(Rect2(Vector2(hover * FloorView.TILE_SIZE), size).grow(-1.0), HOVER_TARGETING if targeting else HOVER, false, 2.0)

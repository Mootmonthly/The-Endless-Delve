class_name TerrainOverlay
extends Node2D
## Paints the round C terrain of the player's fight over the floor: raised
## walls (Wall of Stone, Forcecage...), magical darkness, opaque fog,
## difficult terrain, other spell zones, lit tiles and opened walls
## (ClientState.terrain_cells), each kind in its own translucent colour so the
## encounter tint and the reach overlay stay readable. Pure view: redraws
## when ClientState.terrain_serial changes.

const COLORS: Dictionary[String, Color] = {
	"wall": Color(0.55, 0.55, 0.6, 0.85),
	"darkness": Color(0.0, 0.0, 0.03, 0.72),
	"fog": Color(0.75, 0.78, 0.8, 0.45),
	"difficult": Color(0.55, 0.38, 0.15, 0.40),
	"zone": Color(0.65, 0.3, 0.95, 0.22),
	"lit": Color(1.0, 0.92, 0.5, 0.16),
	"opened": Color(0.4, 0.8, 0.5, 0.25),
}

## Vector2i -> kind (see COLORS).
var cells: Dictionary = {}
var _serial: int = -1


func refresh(state: ClientState) -> void:
	if state == null or state.terrain_serial == _serial:
		return
	_serial = state.terrain_serial
	cells = state.terrain_cells()
	queue_redraw()


## How many tiles of a kind are painted (tests).
func count(kind: String) -> int:
	var n := 0
	for k: Variant in cells.values():
		if str(k) == kind:
			n += 1
	return n


func _draw() -> void:
	var size := Vector2(FloorView.TILE_SIZE, FloorView.TILE_SIZE)
	for key: Variant in cells.keys():
		var p: Vector2i = key
		var kind := str(cells[key])
		var c: Color = COLORS.get(kind, COLORS["zone"])
		var r := Rect2(Vector2(p.x * FloorView.TILE_SIZE, p.y * FloorView.TILE_SIZE), size)
		draw_rect(r, c, true)
		if kind == "difficult":
			# Hatching: two diagonal strokes.
			draw_line(r.position, r.end, Color(c, 0.8), 1.0)
			draw_line(Vector2(r.position.x, r.end.y), Vector2(r.end.x, r.position.y), Color(c, 0.8), 1.0)
		elif kind == "wall":
			draw_rect(r.grow(-2.0), Color(0.2, 0.2, 0.25, 0.9), false, 2.0)

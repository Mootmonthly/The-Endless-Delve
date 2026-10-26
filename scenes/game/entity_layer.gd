class_name EntityLayer
extends Node2D
## Draws the entities of a ClientState as tiles from the dungeon tileset:
## players (TILE_PLAYER), monsters (TILE_MONSTER), the downed (TILE_UNCONSCIOUS),
## plus a selection ring (TILE_SELECTION) on the combatant whose turn it is.
## Slain monsters are not drawn. Pure view: reads the state, never changes it.

const TILESET_PATH := "res://assets/tiles/dungeon_tiles.tres"

var figures: TileMapLayer
var markers: TileMapLayer


func _init() -> void:
	var tile_set: TileSet = load(TILESET_PATH)
	markers = TileMapLayer.new()
	markers.name = "Markers"
	markers.tile_set = tile_set
	add_child(markers)
	figures = TileMapLayer.new()
	figures.name = "Figures"
	figures.tile_set = tile_set
	add_child(figures)


## Redraws every entity from scratch (a floor holds at most a few hundred).
func refresh(state: ClientState) -> void:
	figures.clear()
	markers.clear()
	for id: String in state.entities.keys():
		var e: Dictionary = state.entities[id]
		var p: Vector2i = e["position"]
		var tile := EntityLayer.tile_for(e)
		if tile >= 0:
			figures.set_cell(p, FloorView.SOURCE_ID, Vector2i(tile, 0))
	if state.in_encounter and state.entities.has(state.current_actor):
		var current: Dictionary = state.entities[state.current_actor]
		var cp: Vector2i = current["position"]
		markers.set_cell(cp, FloorView.SOURCE_ID, Vector2i(FloorView.TILE_SELECTION, 0))


## Atlas column for an entity, or -1 when it is not drawn (a slain monster).
static func tile_for(e: Dictionary) -> int:
	var is_player := str(e.get("kind", "")) == ClientState.KIND_PLAYER
	if bool(e.get("dead", false)):
		return FloorView.TILE_UNCONSCIOUS if is_player else -1
	if bool(e.get("down", false)):
		return FloorView.TILE_UNCONSCIOUS
	return FloorView.TILE_PLAYER if is_player else FloorView.TILE_MONSTER

class_name EntityLayer
extends Node2D
## Draws the entities and chests of a ClientState:
## - chests from the icon atlas (chest_closed / chest_open); hidden chests are
##   only in the state once the server revealed them;
## - players by class_id and monsters by monster_id from the icon atlas
##   (res://assets/icons/entity_icons.json); ids without an icon fall back to
##   the dungeon tileset's TILE_PLAYER / TILE_MONSTER;
## - the downed (and dead players) as TILE_UNCONSCIOUS;
## - a selection ring (TILE_SELECTION) on the combatant whose turn it is.
## Slain monsters are not drawn. Round C visibility (ClientState.visibility_of):
## hidden / invisible hostiles and banished creatures are not drawn; the
## player's own side while unseen, and illusions, are drawn ghosted (the
## Ghosts layers, half transparent). Pure view: reads the state, never changes it.

const TILESET_PATH := "res://assets/tiles/dungeon_tiles.tres"

var chest_layer: TileMapLayer
var markers: TileMapLayer
## Dungeon-tileset figures (fallback icons and the downed).
var fallback: TileMapLayer
## Icon-atlas figures.
var figures: TileMapLayer
## Ghosted figures (icon atlas / dungeon tileset), drawn half transparent.
var ghosts: TileMapLayer
var ghost_fallback: TileMapLayer
var icons: EntityIcons


func _init() -> void:
	var tile_set: TileSet = load(TILESET_PATH)
	icons = EntityIcons.shared()
	var icon_set := icons.tile_set()
	chest_layer = TileMapLayer.new()
	chest_layer.name = "Chests"
	chest_layer.tile_set = icon_set
	add_child(chest_layer)
	markers = TileMapLayer.new()
	markers.name = "Markers"
	markers.tile_set = tile_set
	add_child(markers)
	fallback = TileMapLayer.new()
	fallback.name = "FallbackFigures"
	fallback.tile_set = tile_set
	add_child(fallback)
	figures = TileMapLayer.new()
	figures.name = "Figures"
	figures.tile_set = icon_set
	add_child(figures)
	ghost_fallback = TileMapLayer.new()
	ghost_fallback.name = "GhostFallback"
	ghost_fallback.tile_set = tile_set
	ghost_fallback.modulate = Color(0.75, 0.85, 1.0, 0.45)
	add_child(ghost_fallback)
	ghosts = TileMapLayer.new()
	ghosts.name = "Ghosts"
	ghosts.tile_set = icon_set
	ghosts.modulate = Color(0.75, 0.85, 1.0, 0.45)
	add_child(ghosts)


## Redraws every entity and chest from scratch (a floor holds at most a few hundred).
func refresh(state: ClientState) -> void:
	figures.clear()
	fallback.clear()
	ghosts.clear()
	ghost_fallback.clear()
	markers.clear()
	chest_layer.clear()
	for c in state.visible_chests():
		var col := icons.column_for(EntityIcons.CHEST_OPEN if bool(c["opened"]) else EntityIcons.CHEST_CLOSED)
		if col >= 0:
			chest_layer.set_cell(c["position"], icons.source_id, Vector2i(col, 0))
	for id: String in state.entities.keys():
		var e: Dictionary = state.entities[id]
		var p: Vector2i = e["position"]
		var vis := state.visibility_of(id)
		if vis == ClientState.VIS_HIDDEN:
			continue
		var ghost := vis == ClientState.VIS_GHOST
		var icon := EntityLayer.icon_for(e, icons)
		if icon >= 0:
			(ghosts if ghost else figures).set_cell(p, icons.source_id, Vector2i(icon, 0))
			continue
		var tile := EntityLayer.tile_for(e)
		if tile >= 0:
			(ghost_fallback if ghost else fallback).set_cell(p, FloorView.SOURCE_ID, Vector2i(tile, 0))
	if state.in_encounter and state.entities.has(state.current_actor):
		var current: Dictionary = state.entities[state.current_actor]
		var cp: Vector2i = current["position"]
		markers.set_cell(cp, FloorView.SOURCE_ID, Vector2i(FloorView.TILE_SELECTION, 0))


## Icon-atlas column for a standing entity, or -1 (downed, dead or no icon).
static func icon_for(e: Dictionary, map: EntityIcons) -> int:
	if bool(e.get("dead", false)) or bool(e.get("down", false)):
		return -1
	return map.column_for_entity(e)


## Dungeon-tileset column for an entity, or -1 when it is not drawn (a slain monster).
static func tile_for(e: Dictionary) -> int:
	var is_player := str(e.get("kind", "")) == ClientState.KIND_PLAYER
	if bool(e.get("dead", false)):
		return FloorView.TILE_UNCONSCIOUS if is_player else -1
	if bool(e.get("down", false)):
		return FloorView.TILE_UNCONSCIOUS
	return FloorView.TILE_PLAYER if is_player else FloorView.TILE_MONSTER

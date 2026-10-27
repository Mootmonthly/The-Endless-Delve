class_name FloorView
extends Node2D
## Presentation of one floor: draws a core FloorData (schema 1 or 2) onto
## TileMapLayers that share assets/tiles/dungeon_tiles.tres (atlas source 0,
## layout in assets/tiles/dungeon_tiles.json, built by tools/build_tiles.py),
## plus 2D lights, a darkness modulate and a vignette.
##
##   Ground    floor tiles under every walkable cell; the variant (plain,
##             cracked, mossy, rubble, puddle) is a stable hash of (x, y, floor
##             id) weighted by the theme's floor_variant_weights
##   Decor     decals (cracks, moss, pebbles, cobwebs in room corners)
##   Overlay   landing runes (TILE_ARRIVAL on every landing) and the stairs
##   Tint      the encounter-region tint (set_zone_highlight)
##   Walls     one wall tile per non-walkable cell, chosen from the 47-tile blob
##             set by its 8 neighbours (out of bounds counts as wall); the tiles
##             also carry terrain set 0 so the editor can paint them
##   WallDecor torch sconces on south-facing wall faces
##   Doors     doors by state and orientation (set_door_state)
##   Props     barrels, crates, braziers, bones, rubble (set_prop_state)
##   Lights    a PointLight2D per torch and brazier, and PlayerLight, which
##             follows the current Camera2D (or set_focus)
##   Darkness  CanvasModulate in the theme's darkness colour
##   Vignette  CanvasLayer (layer VIGNETTE_LAYER, below the HUD) with a radial
##             gradient
##
## Theme style: DEFAULT_STYLE, overridden by THEME_STYLES[floor.theme], then by
## the floor file's "theme_style" (see resolve_style). Pure view: it reads
## FloorData and never changes it. Tile (x, y) has its top-left corner at world
## (x * TILE_SIZE, y * TILE_SIZE).

const TILE_SIZE := 32
const SOURCE_ID := 0

## Atlas columns of row 0 (the legacy one-row tiles; see tools/build_tiles.py).
const TILE_FLOOR := 0
const TILE_WALL := 1
const TILE_STAIRS := 2
const TILE_ARRIVAL := 3
const TILE_ZONE_FLOOR := 4
const TILE_PLAYER := 5
const TILE_MONSTER := 6
const TILE_UNCONSCIOUS := 7
const TILE_SELECTION := 8

## Atlas coordinates of the Round D tiles.
const ATLAS_FLOOR_VARIANTS: Dictionary[String, Vector2i] = {
	"plain": Vector2i(0, 0), "cracked": Vector2i(9, 0), "mossy": Vector2i(10, 0),
	"rubble": Vector2i(11, 0), "puddle": Vector2i(12, 0),
}
const ATLAS_ZONE_TINT := Vector2i(13, 0)
const ATLAS_WATER := Vector2i(14, 0)
const ATLAS_PIT := Vector2i(15, 0)
## First row of the 47 blob wall tiles (BLOB_MASKS order, 16 per row).
const WALL_ROW := 1
const ATLAS_COLUMNS := 16
const ATLAS_DOORS: Dictionary[String, Vector2i] = {
	"closed_h": Vector2i(0, 4), "open_h": Vector2i(1, 4), "locked_h": Vector2i(2, 4),
	"closed_v": Vector2i(3, 4), "open_v": Vector2i(4, 4), "locked_v": Vector2i(5, 4),
}
## Prop kind -> [intact, damaged] atlas coordinates.
const ATLAS_PROPS: Dictionary[String, Array] = {
	"barrel": [Vector2i(6, 4), Vector2i(7, 4)],
	"crate": [Vector2i(8, 4), Vector2i(9, 4)],
	"brazier": [Vector2i(10, 4), Vector2i(12, 4)],
	"bones": [Vector2i(13, 4), Vector2i(14, 4)],
	"rubble": [Vector2i(15, 4), Vector2i(0, 5)],
}
const ATLAS_LANDING_GLOW := Vector2i(1, 5)
const ATLAS_TORCH := Vector2i(3, 5)
const ATLAS_DECALS: Dictionary[String, Vector2i] = {
	"crack": Vector2i(5, 5), "moss": Vector2i(6, 5), "pebbles": Vector2i(7, 5),
	"holes": Vector2i(8, 5), "cobweb": Vector2i(9, 5),
}
const ATLAS_GRAVESTONES: Array[Vector2i] = [Vector2i(10, 5), Vector2i(11, 5)]

const PROP_INTACT := "intact"
const PROP_DAMAGED := "damaged"
const PROP_DESTROYED := "destroyed"
## Neighbour bits of the blob masks.
const BIT_N := 1
const BIT_NE := 2
const BIT_E := 4
const BIT_SE := 8
const BIT_S := 16
const BIT_SW := 32
const BIT_W := 64
const BIT_NW := 128
const LIGHT_TEXTURE_PATH := "res://assets/tiles/light_soft.png"
const VIGNETTE_LAYER := 5
## Minimum Chebyshev distance between two torches.
const TORCH_SPACING := 5

const DEFAULT_STYLE := {
	"darkness": "#5a5450",
	"torch_color": "#ffb45e",
	"torch_density": 0.05,
	"torch_energy": 0.9,
	"torch_radius_tiles": 5.0,
	"brazier_energy": 0.75,
	"brazier_radius_tiles": 6.0,
	"player_light_color": "#fff0d8",
	"player_light_energy": 0.7,
	"player_light_radius_tiles": 9.0,
	"decor_density": 0.06,
	"cobweb_chance": 0.25,
	"vignette": 0.55,
	"floor_variant_weights": {"plain": 12.0, "cracked": 3.0, "mossy": 1.5, "rubble": 1.0, "puddle": 0.3},
}
## Per-theme defaults (floor files may still override any key).
const THEME_STYLES := {
	"The Barrow Warrens": {"darkness": "#4a4038", "torch_color": "#ffb45e", "cobweb_chance": 0.35},
}

@onready var ground: TileMapLayer = $Ground
@onready var decor: TileMapLayer = $Decor
@onready var overlay: TileMapLayer = $Overlay
@onready var tint: TileMapLayer = $Tint
@onready var walls: TileMapLayer = $Walls
@onready var wall_decor: TileMapLayer = $WallDecor
@onready var doors_layer: TileMapLayer = $Doors
@onready var props_layer: TileMapLayer = $Props
@onready var lights: Node2D = $Lights
@onready var player_light: PointLight2D = $Lights/PlayerLight
@onready var darkness: CanvasModulate = $Darkness
@onready var vignette: TextureRect = $Vignette/Shade

var floor_data: FloorData = null
## The resolved theme style of the floor being shown.
var style: Dictionary = {}
## Door id -> tile; prop id -> tile; prop id -> state.
var _door_cells: Dictionary = {}
var _prop_cells: Dictionary = {}
var _prop_states: Dictionary = {}
## Prop id -> its PointLight2D (braziers).
var _prop_lights: Dictionary = {}
var _torch_cells: Array[Vector2i] = []
var _focus: Vector2 = Vector2.ZERO
var _has_focus: bool = false
var _lighting: bool = true
static var _blob_index: Dictionary = {}
static var _light_texture: Texture2D = null


## Clears every layer and draws the floor: ground, decor, walls, torches,
## landings, stairs, doors, props, lights and the theme's darkness.
func build(new_floor: FloorData) -> void:
	_bind_layers()
	floor_data = new_floor
	for layer: TileMapLayer in [ground, decor, overlay, tint, walls, wall_decor, doors_layer, props_layer]:
		layer.clear()
	_clear_lights()
	_door_cells.clear()
	_prop_cells.clear()
	_prop_states.clear()
	_torch_cells.clear()
	if new_floor == null or new_floor.walk_map == null:
		push_error("FloorView.build: no floor data")
		return
	style = FloorView.resolve_style(new_floor)
	var wm: WalkMap = new_floor.walk_map
	var salt := FloorView._salt(new_floor.id)
	var weights := FloorView._weights(style)
	var decor_density := float(style.get("decor_density", 0.0))
	var cobweb_chance := float(style.get("cobweb_chance", 0.0))
	for y in range(wm.height):
		for x in range(wm.width):
			var p := Vector2i(x, y)
			if wm.is_walkable(p):
				ground.set_cell(p, SOURCE_ID, FloorView._pick_variant(weights, FloorView.cell_hash(x, y, salt)))
				_place_decal(p, wm, salt, decor_density, cobweb_chance)
			else:
				walls.set_cell(p, SOURCE_ID, FloorView.wall_atlas_coords(FloorView.wall_mask(wm, p)))
	_place_torches(wm, salt)
	for l in new_floor.get_landings():
		overlay.set_cell(l.position, SOURCE_ID, Vector2i(TILE_ARRIVAL, 0))
	overlay.set_cell(new_floor.stairs, SOURCE_ID, Vector2i(TILE_STAIRS, 0))
	for d in new_floor.doors:
		_door_cells[d.id] = d.position
		_draw_door(d.position, d.state)
	for pr in new_floor.props:
		_prop_cells[pr.id] = pr.position
		_prop_states[pr.id] = PROP_INTACT
		props_layer.set_cell(pr.position, SOURCE_ID, FloorView.prop_atlas_coords(pr.kind, PROP_INTACT))
		if pr.kind == PropData.KIND_BRAZIER:
			_prop_lights[pr.id] = _add_light(pr.position, "brazier")
	_apply_lighting()


## Tints (on) or clears (off) the walkable cells inside rect on the Tint layer.
func set_zone_highlight(rect: Rect2i, on: bool) -> void:
	_bind_layers()
	if floor_data == null or floor_data.walk_map == null:
		return
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var p := Vector2i(x, y)
			if floor_data.walk_map.in_bounds(p) and floor_data.walk_map.is_walkable(p):
				if on:
					tint.set_cell(p, SOURCE_ID, ATLAS_ZONE_TINT)
				else:
					tint.erase_cell(p)


## Redraws a door in a new state ("open" | "closed" | "locked"). Phase D2 calls
## it on DOOR_CHANGED.
func set_door_state(door_id: String, state: String) -> void:
	_bind_layers()
	if not _door_cells.has(door_id):
		return
	_draw_door(_door_cells[door_id], state)


## Redraws a prop: PROP_INTACT, PROP_DAMAGED (the second frame) or
## PROP_DESTROYED (removed, its light too). Phase D2 calls it on PROP_DESTROYED
## (and on a damaging hit, if it reports one).
func set_prop_state(prop_id: String, state: String) -> void:
	_bind_layers()
	if not _prop_cells.has(prop_id) or floor_data == null:
		return
	var cell: Vector2i = _prop_cells[prop_id]
	var prop := floor_data.get_prop(prop_id)
	_prop_states[prop_id] = state
	if state == PROP_DESTROYED or prop == null:
		props_layer.erase_cell(cell)
	else:
		props_layer.set_cell(cell, SOURCE_ID, FloorView.prop_atlas_coords(prop.kind, state))
	if _prop_lights.has(prop_id) and state != PROP_INTACT:
		var light: PointLight2D = _prop_lights[prop_id]
		_prop_lights.erase(prop_id)
		if light.is_inside_tree():
			light.queue_free()
		else:
			light.free()


func prop_state(prop_id: String) -> String:
	return str(_prop_states.get(prop_id, ""))


## Pins the player light to a world position (otherwise it follows the camera).
func set_focus(world: Vector2) -> void:
	_focus = world
	_has_focus = true
	_bind_layers()
	player_light.position = world


## Turns the darkness, lights and vignette on or off (a settings toggle, or
## screenshots of the plain layout).
func set_lighting_enabled(on: bool) -> void:
	_lighting = on
	_bind_layers()
	_apply_lighting()


func is_lighting_enabled() -> bool:
	return _lighting


## Torch and brazier lights currently shown (not counting PlayerLight).
func light_count() -> int:
	_bind_layers()
	return lights.get_child_count() - 1


func torch_cells() -> Array[Vector2i]:
	return _torch_cells.duplicate()


func _process(_delta: float) -> void:
	if _has_focus or player_light == null:
		return
	if not is_inside_tree():
		return
	var cam: Camera2D = get_viewport().get_camera_2d()
	if cam != null:
		player_light.global_position = cam.get_screen_center_position()


## World-space centre of tile p.
static func tile_to_world(p: Vector2i) -> Vector2:
	return Vector2(p.x * TILE_SIZE + TILE_SIZE / 2.0, p.y * TILE_SIZE + TILE_SIZE / 2.0)


## Tile containing world point w.
static func world_to_tile(w: Vector2) -> Vector2i:
	return Vector2i(floori(w.x / TILE_SIZE), floori(w.y / TILE_SIZE))


## DEFAULT_STYLE, then the theme's entry in THEME_STYLES, then the floor's own
## theme_style (floor_variant_weights merge key by key).
static func resolve_style(f: FloorData) -> Dictionary:
	var out: Dictionary = DEFAULT_STYLE.duplicate(true)
	var layers: Array[Dictionary] = []
	if f != null and THEME_STYLES.has(f.theme):
		var theme_style: Dictionary = THEME_STYLES[f.theme]
		layers.append(theme_style)
	if f != null:
		layers.append(f.theme_style)
	for layer in layers:
		for key: Variant in layer.keys():
			if key == "floor_variant_weights" and typeof(layer[key]) == TYPE_DICTIONARY:
				var merged: Dictionary = (out[key] as Dictionary).duplicate()
				merged.merge(layer[key] as Dictionary, true)
				out[key] = merged
			else:
				out[key] = layer[key]
	return out


## 8-neighbour wall mask of tile p (bit set = wall; out of bounds is wall),
## with diagonals cleared unless both their sides are walls.
static func wall_mask(wm: WalkMap, p: Vector2i) -> int:
	var dirs: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0), Vector2i(1, 1),
		Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(-1, -1)]
	var mask := 0
	for i in range(8):
		if not wm.is_walkable(p + dirs[i]):
			mask |= 1 << i
	return FloorView.canonical_mask(mask)


static func canonical_mask(mask: int) -> int:
	var m := mask
	if not (m & BIT_N and m & BIT_E):
		m &= ~BIT_NE
	if not (m & BIT_S and m & BIT_E):
		m &= ~BIT_SE
	if not (m & BIT_S and m & BIT_W):
		m &= ~BIT_SW
	if not (m & BIT_N and m & BIT_W):
		m &= ~BIT_NW
	return m


## The 47 canonical masks in atlas order (ascending), as tools/build_tiles.py.
static func blob_masks() -> Array[int]:
	var seen := {}
	for m in range(256):
		seen[FloorView.canonical_mask(m)] = true
	var out: Array[int] = []
	for k: Variant in seen.keys():
		out.append(int(k))
	out.sort()
	return out


static func wall_atlas_coords(mask: int) -> Vector2i:
	if _blob_index.is_empty():
		var masks := FloorView.blob_masks()
		for i in range(masks.size()):
			_blob_index[masks[i]] = i
	var index: int = _blob_index.get(FloorView.canonical_mask(mask), _blob_index[255])
	return Vector2i(index % ATLAS_COLUMNS, WALL_ROW + index / ATLAS_COLUMNS)


static func prop_atlas_coords(kind: String, state: String = PROP_INTACT) -> Vector2i:
	var frames: Array = ATLAS_PROPS.get(kind, ATLAS_PROPS[PropData.KIND_RUBBLE])
	return frames[1] if state == PROP_DAMAGED else frames[0]


## "h" for a door in a horizontal wall (walls west and east), "v" otherwise.
static func door_orientation(wm: WalkMap, p: Vector2i) -> String:
	if not wm.is_walkable(p + Vector2i.UP) and not wm.is_walkable(p + Vector2i.DOWN):
		return "v"
	return "h"


## A stable non-negative hash of a tile and a salt (no RNG: the same floor
## always looks the same).
static func cell_hash(x: int, y: int, salt: int) -> int:
	var h := (x * 73856093) ^ (y * 19349663) ^ (salt * 83492791)
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return h & 0x7fffffff


static func _salt(floor_id: String) -> int:
	var s := 7
	for i in range(floor_id.length()):
		s = (s * 31 + floor_id.unicode_at(i)) & 0xffffff
	return s


static func _weights(st: Dictionary) -> Array:
	var out: Array = []
	var w_v: Variant = st.get("floor_variant_weights", {})
	var w: Dictionary = w_v if typeof(w_v) == TYPE_DICTIONARY else {}
	for key: String in ["plain", "cracked", "mossy", "rubble", "puddle"]:
		var weight := maxf(0.0, float(w.get(key, 0.0)))
		if weight > 0.0:
			out.append([ATLAS_FLOOR_VARIANTS[key], weight])
	if out.is_empty():
		out.append([ATLAS_FLOOR_VARIANTS["plain"], 1.0])
	return out


static func _pick_variant(weights: Array, h: int) -> Vector2i:
	var total := 0.0
	for pair: Array in weights:
		total += float(pair[1])
	var roll := float(h % 10000) / 10000.0 * total
	for pair: Array in weights:
		roll -= float(pair[1])
		if roll < 0.0:
			return pair[0]
	return weights[0][0]


func _place_decal(p: Vector2i, wm: WalkMap, salt: int, density: float, cobweb_chance: float) -> void:
	var h := FloorView.cell_hash(p.x, p.y, salt + 101)
	var wall_n := not wm.is_walkable(p + Vector2i.UP)
	var wall_w := not wm.is_walkable(p + Vector2i.LEFT)
	if wall_n and wall_w and float(h % 1000) / 1000.0 < cobweb_chance:
		decor.set_cell(p, SOURCE_ID, ATLAS_DECALS["cobweb"])
		return
	if float((h >> 10) % 1000) / 1000.0 >= density:
		return
	var kinds: Array[String] = ["crack", "moss", "pebbles", "crack", "pebbles"]
	decor.set_cell(p, SOURCE_ID, ATLAS_DECALS[kinds[(h >> 20) % kinds.size()]])


## Torches on wall cells whose face is seen (floor to the south), spaced out.
func _place_torches(wm: WalkMap, salt: int) -> void:
	var density := float(style.get("torch_density", 0.0))
	if density <= 0.0:
		return
	var blocked := {}
	for d in floor_data.doors:
		blocked[d.position] = true
	for y in range(wm.height):
		for x in range(wm.width):
			var p := Vector2i(x, y)
			var below := p + Vector2i.DOWN
			if wm.is_walkable(p) or not wm.is_walkable(below) or blocked.has(below):
				continue
			if not wm.in_bounds(p) or not wm.is_walkable(below + Vector2i.LEFT) or not wm.is_walkable(below + Vector2i.RIGHT):
				continue
			if float(FloorView.cell_hash(x, y, salt + 202) % 1000) / 1000.0 >= density:
				continue
			var near := false
			for t in _torch_cells:
				if GridMath.distance_tiles(t, p) < TORCH_SPACING:
					near = true
					break
			if near:
				continue
			_torch_cells.append(p)
			wall_decor.set_cell(p, SOURCE_ID, ATLAS_TORCH)
			_add_light(p, "torch")


func _draw_door(cell: Vector2i, state: String) -> void:
	var orient := FloorView.door_orientation(floor_data.walk_map, cell)
	var key := "%s_%s" % [state if DoorData.STATES.has(state) else DoorData.STATE_CLOSED, orient]
	doors_layer.set_cell(cell, SOURCE_ID, ATLAS_DOORS[key])


func _add_light(cell: Vector2i, kind: String) -> PointLight2D:
	var light := PointLight2D.new()
	light.name = "%s_%d_%d" % [kind, cell.x, cell.y]
	light.texture = FloorView._light_tex()
	var tex_size := 128.0
	if light.texture != null:
		tex_size = float(light.texture.get_width())
	var radius := float(style.get("%s_radius_tiles" % kind, 5.0)) * TILE_SIZE
	light.texture_scale = radius * 2.0 / tex_size
	light.energy = float(style.get("%s_energy" % kind, 1.0))
	light.color = Color(str(style.get("torch_color", "#ffb45e")))
	var pos := FloorView.tile_to_world(cell)
	if kind == "torch":
		pos.y += TILE_SIZE * 0.6  # the flame hangs on the wall face, shine onto the floor
	light.position = pos
	lights.add_child(light)
	return light


func _clear_lights() -> void:
	for child in lights.get_children():
		if child == player_light:
			continue
		lights.remove_child(child)
		child.free()
	_prop_lights.clear()


func _apply_lighting() -> void:
	var dark := Color(str(style.get("darkness", DEFAULT_STYLE["darkness"])))
	darkness.color = dark
	darkness.visible = _lighting
	lights.visible = _lighting
	for child in lights.get_children():
		var l := child as Light2D
		if l != null:
			l.enabled = _lighting
	player_light.texture = FloorView._light_tex()
	if player_light.texture != null:
		var radius := float(style.get("player_light_radius_tiles", 9.0)) * TILE_SIZE
		player_light.texture_scale = radius * 2.0 / float(player_light.texture.get_width())
	player_light.energy = float(style.get("player_light_energy", 0.7))
	player_light.color = Color(str(style.get("player_light_color", "#fff0d8")))
	if floor_data != null and not _has_focus:
		player_light.position = FloorView.tile_to_world(floor_data.arrival)
	var strength := float(style.get("vignette", 0.5))
	vignette.visible = _lighting and strength > 0.0
	vignette.texture = FloorView._vignette_texture(strength)


static func _light_tex() -> Texture2D:
	if _light_texture == null and ResourceLoader.exists(LIGHT_TEXTURE_PATH):
		_light_texture = load(LIGHT_TEXTURE_PATH)
	return _light_texture


static func _vignette_texture(strength: float) -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0))
	g.set_color(1, Color(0, 0, 0, clampf(strength, 0.0, 1.0)))
	g.add_point(0.55, Color(0, 0, 0, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 1.0)
	tex.width = 256
	tex.height = 256
	return tex


## Lets build() work before the node enters the tree (e.g. in headless tests).
func _bind_layers() -> void:
	if ground == null:
		ground = get_node("Ground")
		decor = get_node("Decor")
		overlay = get_node("Overlay")
		tint = get_node("Tint")
		walls = get_node("Walls")
		wall_decor = get_node("WallDecor")
		doors_layer = get_node("Doors")
		props_layer = get_node("Props")
		lights = get_node("Lights")
		player_light = get_node("Lights/PlayerLight")
		darkness = get_node("Darkness")
		vignette = get_node("Vignette/Shade")

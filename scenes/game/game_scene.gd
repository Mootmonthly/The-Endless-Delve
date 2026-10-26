class_name GameScene
extends Node2D
## Offline play: runs the authoritative InstanceServer in-process over a
## LocalTransport and presents what it sends.
##
## Children (built in _ready): FloorView (from FLOOR_LOADED), ReachOverlay
## (tiles reachable this turn), EntityLayer, Camera2D following the player at
## an integer zoom, Hud, and the InstanceServer node. Every result from the
## transport goes through ClientState; the views redraw from it. Input becomes
## intents (see ClientState.intent_for_click); the server validates them all.
##
## Controls: left click = walk (exploring) / move or attack (your combat turn);
## arrow keys = one step; Space = end turn; mouse wheel = zoom.

## Emitted when the player asks for a new character after the run ended.
signal exit_requested

const FLOOR_PATH := "res://floors/floor_001.json"
const FLOOR_VIEW_SCENE := "res://scenes/floor/floor_view.tscn"
const TICKS_PER_SECOND := 20
const DEFAULT_ZOOM := 2
const MIN_ZOOM := 1
const MAX_ZOOM := 4
## Ticks between a monster's turn_started and its actions, so turns are readable.
const MONSTER_TURN_DELAY_TICKS := 8

var transport: LocalTransport = null
var server: InstanceServer = null
var state: ClientState = null
var floor_view: FloorView = null
var reach: ReachOverlay = null
var entity_layer: EntityLayer = null
var camera: Camera2D = null
var hud: Hud = null

var _sheet: CharacterSheet = null
var _seed: int = 0
var _dirty: bool = true
var _built_floor_id: String = ""
var _highlighted: Rect2i = Rect2i()
var _zoom: int = DEFAULT_ZOOM


## Call before adding the scene to the tree. seed 0 = pick one from the clock.
func setup(sheet: CharacterSheet, instance_seed: int = 0) -> void:
	_sheet = sheet
	_seed = instance_seed


func _ready() -> void:
	Engine.physics_ticks_per_second = TICKS_PER_SECOND
	if _sheet == null:
		_sheet = GameScene.default_sheet()
	if _seed == 0:
		_seed = int(Time.get_unix_time_from_system()) % 1000000007 + 1
	transport = LocalTransport.new()
	state = ClientState.new(ClientState.player_id_for_peer(transport.local_peer_id()))
	transport.result_received.connect(_on_result)

	var packed: PackedScene = load(FLOOR_VIEW_SCENE)
	floor_view = packed.instantiate() as FloorView
	add_child(floor_view)
	reach = ReachOverlay.new()
	reach.name = "ReachOverlay"
	add_child(reach)
	entity_layer = EntityLayer.new()
	entity_layer.name = "EntityLayer"
	add_child(entity_layer)
	camera = Camera2D.new()
	camera.name = "Camera"
	camera.zoom = Vector2(_zoom, _zoom)
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 10.0
	add_child(camera)
	camera.make_current()
	hud = Hud.new()
	hud.name = "Hud"
	add_child(hud)
	hud.action_requested.connect(_on_hud_action)
	hud.new_character_requested.connect(_on_new_character)

	var floor_data := FloorFile.load(FLOOR_PATH)
	if floor_data == null:
		hud.show_end("Error", "Could not load %s." % FLOOR_PATH)
		return
	server = InstanceServer.new()
	server.name = "InstanceServer"
	server.monster_turn_delay_ticks = MONSTER_TURN_DELAY_TICKS
	add_child(server)
	server.configure(transport, floor_data, _seed)
	# The server keeps its own copy of the sheet, as it would over the network.
	var entity_id := server.add_player(transport.local_peer_id(), _sheet)
	if not entity_id.is_empty():
		state.player_id = entity_id
	_refresh_view()


## A ready-to-play level 1 Human Fighter (used when the scene runs on its own).
static func default_sheet() -> CharacterSheet:
	var draft := CharacterDraft.new()
	draft.character_name = "Wanderer"
	var classes := CharacterDraft.wave_1_classes(ContentLoader.load_classes())
	if not classes.is_empty():
		draft.set_class(classes[0])
	var ancestries := ContentLoader.load_ancestries()
	if ancestries.has("human"):
		var human: AncestryDefinition = ancestries["human"]
		draft.set_ancestry(human)
	draft.auto_assign()
	if draft.class_def != null:
		for skill in draft.class_def.skill_choices:
			draft.toggle_skill(skill, true)
	return draft.build_sheet()


func _on_result(result: Dictionary) -> void:
	state.apply(result)
	_dirty = true


func _process(_delta: float) -> void:
	if _dirty:
		_refresh_view()


func _refresh_view() -> void:
	_dirty = false
	if state == null:
		return
	var lines := state.drain_log()
	if not lines.is_empty():
		hud.append_log(lines)
	if state.floor_data != null and state.floor_data.id != _built_floor_id:
		floor_view.build(state.floor_data)
		_built_floor_id = state.floor_data.id
		_highlighted = Rect2i()
	var want := state.region if state.in_encounter else Rect2i()
	if want != _highlighted:
		if _highlighted.has_area():
			floor_view.set_zone_highlight(_highlighted, false)
		if want.has_area():
			floor_view.set_zone_highlight(want, true)
		_highlighted = want
	entity_layer.refresh(state)
	var tiles: Array[Vector2i] = []
	for key: Variant in state.reachable_tiles().keys():
		var t: Vector2i = key
		tiles.append(t)
	reach.set_tiles(tiles)
	if state.has_player_entity():
		camera.position = FloorView.tile_to_world(state.player_position())
	hud.refresh(state)


func _unhandled_input(event: InputEvent) -> void:
	if state == null:
		return
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if not mb.pressed:
			return
		match mb.button_index:
			MOUSE_BUTTON_LEFT:
				_send(state.intent_for_click(_mouse_tile()))
				get_viewport().set_input_as_handled()
			MOUSE_BUTTON_WHEEL_UP:
				_set_zoom(_zoom + 1)
			MOUSE_BUTTON_WHEEL_DOWN:
				_set_zoom(_zoom - 1)
	elif event is InputEventMouseMotion:
		reach.set_hover(_mouse_tile())
	elif event is InputEventKey:
		var key: InputEventKey = event
		if not key.pressed or key.echo:
			return
		if key.keycode == KEY_SPACE:
			if state.is_my_turn():
				_send(state.simple_intent(Messages.END_TURN))
			get_viewport().set_input_as_handled()
			return
		var dir := Vector2i.ZERO
		if event.is_action("ui_left"):
			dir = Vector2i.LEFT
		elif event.is_action("ui_right"):
			dir = Vector2i.RIGHT
		elif event.is_action("ui_up"):
			dir = Vector2i.UP
		elif event.is_action("ui_down"):
			dir = Vector2i.DOWN
		if dir != Vector2i.ZERO and state.has_player_entity():
			_send(state.intent_for_click(state.player_position() + dir))
			get_viewport().set_input_as_handled()


func _mouse_tile() -> Vector2i:
	return FloorView.world_to_tile(floor_view.get_local_mouse_position())


func _set_zoom(z: int) -> void:
	_zoom = clampi(z, MIN_ZOOM, MAX_ZOOM)
	camera.zoom = Vector2(_zoom, _zoom)


func _send(intent: Dictionary) -> void:
	if not intent.is_empty():
		transport.send_intent(intent)


func _on_hud_action(action: String) -> void:
	match action:
		"attack":
			_send(state.attack_intent())
		"dash", "dodge", "disengage", "end_turn", "use_stairs":
			_send(state.simple_intent(action))
		"short_rest":
			_send(state.short_rest_intent(1))


func _on_new_character() -> void:
	exit_requested.emit()

class_name GameScene
extends Node2D
## Offline play: runs the authoritative InstanceServer in-process over a
## LocalTransport and presents what it sends.
##
## Plays the first five-floor set (floors/set_01.json) when it exists, else
## the single floor floors/floor_001.json. Every FLOOR_LOADED (a new floor
## after the stairs) rebuilds the floor view, entities and camera.
##
## Children (built in _ready): FloorView (from FLOOR_LOADED), ReachOverlay
## (tiles reachable this turn), EntityLayer, Camera2D following the player at
## an integer zoom, Hud, and the InstanceServer node. Every result from the
## transport goes through ClientState; the views redraw from it. Input becomes
## intents (see ClientState.intent_for_click); the server validates them all.
##
## Controls (InputMap actions, rebindable in Settings): left click = walk /
## open a chest within reach (exploring), move or attack with the selected
## attack (your combat turn), or pick the target of a spell / feature in
## targeting mode; right click or `cancel` (Escape) = leave targeting mode,
## then close HUD panels (else Main opens the pause menu); move_* = one step;
## end_turn; action_attack / action_dash / action_dodge / action_disengage;
## open_spells; open_features; toggle_inventory; descend; rest; mouse wheel
## = zoom. The LevelUpScreen opens by itself on a new LEVEL_UP_AVAILABLE when
## out of combat; the HUD's "Level up available" button reopens it.
## While an area spell is aimed, the ReachOverlay shows its footprint under
## the cursor and rings the creatures it would catch (ClientState.area_preview).
## The short rest spends one hit die when hurt and asks for Arcane / Natural
## Recovery when it applies.

## Emitted when the player asks for a new character after the run ended.
signal exit_requested

const SET_PATH := "res://floors/set_01.json"
const FLOOR_PATH := "res://floors/floor_001.json"
const FLOOR_VIEW_SCENE := "res://scenes/floor/floor_view.tscn"
const LEVEL_UP_SCENE := "res://scenes/ui/level_up_screen.tscn"
const MOVE_ACTIONS: Dictionary[String, Vector2i] = {
	"move_up": Vector2i.UP, "move_down": Vector2i.DOWN, "move_left": Vector2i.LEFT, "move_right": Vector2i.RIGHT,
}
const HUD_ACTIONS: Dictionary[String, String] = {
	"action_attack": "attack", "action_dash": "dash", "action_dodge": "dodge",
	"action_disengage": "disengage", "end_turn": "end_turn", "descend": "use_stairs", "rest": "short_rest",
}
const TICKS_PER_SECOND := 20
const DEFAULT_ZOOM := 2
const MIN_ZOOM := 1
const MAX_ZOOM := 4
## Ticks between a monster's turn_started and its actions, so turns are readable.
const MONSTER_TURN_DELAY_TICKS := 8

## True while the simulation runs in-process (offline mode). Only an offline
## game may be paused; an MMO instance keeps moving while any menu is open.
var offline: bool = true
var transport: LocalTransport = null
var server: InstanceServer = null
var state: ClientState = null
var floor_view: FloorView = null
var reach: ReachOverlay = null
var entity_layer: EntityLayer = null
var camera: Camera2D = null
var hud: Hud = null
var level_up_screen: LevelUpScreen = null

var _sheet: CharacterSheet = null
var _seed: int = 0
var _dirty: bool = true
var _built_floor_serial: int = 0
var _highlighted: Rect2i = Rect2i()
var _zoom: int = DEFAULT_ZOOM
var _seen_level_up_serial: int = 0
var _hover_tile: Vector2i = Vector2i(-1, -1)


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
	hud.intent_requested.connect(_send)
	hud.state_changed.connect(func() -> void: _dirty = true)
	hud.new_character_requested.connect(_on_new_character)
	var level_packed: PackedScene = load(LEVEL_UP_SCENE)
	level_up_screen = level_packed.instantiate() as LevelUpScreen
	level_up_screen.name = "LevelUpScreen"
	add_child(level_up_screen)
	level_up_screen.confirmed.connect(_on_level_up_confirmed)

	server = InstanceServer.new()
	server.name = "InstanceServer"
	server.monster_turn_delay_ticks = MONSTER_TURN_DELAY_TICKS
	add_child(server)
	if not _configure_server():
		return
	# The server keeps its own copy of the sheet, as it would over the network.
	var entity_id := server.add_player(transport.local_peer_id(), _sheet)
	if not entity_id.is_empty():
		state.player_id = entity_id
	_refresh_view()


## The set if its manifest exists and loads, else the single first floor.
func _configure_server() -> bool:
	if FileAccess.file_exists(SET_PATH):
		var manifest := FloorFile.load_set(SET_PATH)
		if not manifest.is_empty() and server.configure_set(transport, manifest, _seed):
			return true
	var floor_data := FloorFile.load(FLOOR_PATH)
	if floor_data == null:
		hud.show_end("Error", "Could not load %s." % FLOOR_PATH)
		return false
	server.configure(transport, floor_data, _seed)
	return true


## A ready-to-play level 1 Human Fighter (used when the scene runs on its own).
static func default_sheet() -> CharacterSheet:
	var draft := CharacterDraft.new()
	draft.character_name = "Wanderer"
	var classes := CharacterDraft.ordered_classes(ContentLoader.load_classes())
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
	if str(result.get("kind", "")) == Messages.ERROR and level_up_screen != null and level_up_screen.is_open():
		level_up_screen.set_waiting(false, str(result.get("message", "")))
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
	var new_floor := state.floor_data != null and state.floor_serial != _built_floor_serial
	if new_floor:
		floor_view.build(state.floor_data)
		_built_floor_serial = state.floor_serial
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
	reach.set_range(state.range_tiles(), state.is_targeting())
	_refresh_area_preview()
	_refresh_level_up()
	if state.has_player_entity():
		camera.position = FloorView.tile_to_world(state.player_position())
		if new_floor:
			camera.reset_smoothing()  # jump to the new arrival, no pan across floors
	elif new_floor and state.floor_data != null:
		camera.position = FloorView.tile_to_world(state.floor_data.arrival)
		camera.reset_smoothing()
	hud.refresh(state)


## The area footprint under the cursor while an area spell is aimed.
func _refresh_area_preview() -> void:
	var preview := state.area_preview(_hover_tile) if state.is_targeting() else {}
	var tiles: Array[Vector2i] = []
	var caught: Array[Vector2i] = []
	var spared: Array[Vector2i] = []
	if not preview.is_empty():
		tiles.assign(preview["tiles"])
		for id: String in preview["affected"]:
			caught.append(state.get_entity(id)["position"])
		for id: String in preview["sculpted"]:
			spared.append(state.get_entity(id)["position"])
	reach.set_area(tiles, caught, spared, preview.is_empty() or str(preview.get("error", "")).is_empty())


## Opens the level-up screen once per new offer (when it can be answered),
## and closes it once the offer is answered (CHARACTER_STATE leveled_to).
func _refresh_level_up() -> void:
	if level_up_screen == null:
		return
	if level_up_screen.is_open() and not state.has_level_up_offer():
		level_up_screen.close()
	elif state.level_up_serial != _seen_level_up_serial and state.can_level_up():
		_seen_level_up_serial = state.level_up_serial
		open_level_up()


func open_level_up() -> void:
	if state.can_level_up() and level_up_screen != null:
		hud.close_popups()
		level_up_screen.open(state.level_up_offer, state.sheet, state.content)


func _on_level_up_confirmed(choices: Dictionary) -> void:
	_send(state.level_up_intent(choices))


func _unhandled_input(event: InputEvent) -> void:
	if state == null:
		return
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if not mb.pressed:
			return
		match mb.button_index:
			MOUSE_BUTTON_LEFT:
				var targeting := state.is_targeting()
				var intent := state.intent_for_click(_mouse_tile())
				if targeting:
					if not intent.is_empty():
						state.cancel_targeting()
					_dirty = true  # show the hint either way
				_send(intent)
				get_viewport().set_input_as_handled()
			MOUSE_BUTTON_RIGHT:
				if state.is_targeting():
					state.cancel_targeting()
					_dirty = true
					get_viewport().set_input_as_handled()
			MOUSE_BUTTON_WHEEL_UP:
				_set_zoom(_zoom + 1)
			MOUSE_BUTTON_WHEEL_DOWN:
				_set_zoom(_zoom - 1)
		return
	if event is InputEventMouseMotion:
		_hover_tile = _mouse_tile()
		reach.set_hover(_hover_tile)
		if state.is_targeting():
			_refresh_area_preview()
		return
	if not event.is_pressed() or event.is_echo():
		return
	if event.is_action_pressed("cancel"):
		# Escape closes what the game has open; with nothing open Main opens the pause menu.
		if state.is_targeting():
			state.cancel_targeting()
			_dirty = true
			get_viewport().set_input_as_handled()
		elif hud.close_top():
			get_viewport().set_input_as_handled()
		return
	for action: String in MOVE_ACTIONS.keys():
		if event.is_action_pressed(action):
			_send(state.step_intent(MOVE_ACTIONS[action]))
			get_viewport().set_input_as_handled()
			return
	for action: String in HUD_ACTIONS.keys():
		if event.is_action_pressed(action):
			_on_hud_action(HUD_ACTIONS[action])
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("toggle_inventory"):
		hud.toggle_inventory()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("open_spells"):
		hud.toggle_spells()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("open_features"):
		hud.toggle_features()
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
			# Melee: the first adjacent hostile. Ranged / thrown: the first hostile
			# in range; with none, pick a target by clicking.
			var intent := state.attack_intent()
			if intent.is_empty() and state.can_make_attack():
				state.begin_attack_targeting()
			_send(intent)
		"dash", "dodge", "disengage":
			if state.can_take_action():
				state.cancel_targeting()
				_send(state.simple_intent(action))
		"end_turn":
			if state.is_my_turn():
				state.cancel_targeting()
				_send(state.simple_intent(action))
		"use_stairs":
			if state.can_use_stairs():
				_send(state.simple_intent(action))
		"short_rest":
			if state.can_short_rest():
				var hurt := state.sheet.current_hp < state.sheet.max_hp and state.sheet.hit_dice_remaining > 0
				_send(state.short_rest_intent(1 if hurt else 0, not state.slot_recovery().is_empty()))
		"stand":
			if state.is_my_turn():
				_send(state.stand_intent())
		"level_up":
			open_level_up()
	_dirty = true


func _on_new_character() -> void:
	exit_requested.emit()


## Pauses or resumes the in-process simulation. No-op online: the server is
## authoritative and never waits for a client menu. Returns whether it paused.
func set_simulation_paused(paused: bool) -> bool:
	if not offline:
		return false
	get_tree().paused = paused
	return paused

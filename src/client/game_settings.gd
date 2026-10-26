class_name GameSettings
extends RefCounted
## Player settings: audio volumes, keyboard bindings and video options,
## stored in a ConfigFile (default user://settings.cfg) and applied to
## AudioServer, InputMap and the window. No singleton: scenes/main.gd loads one
## at boot, applies it, and hands it to the SettingsMenu.
##
## NOTE (M2): the InputMap actions below are defined in project.godot and
## rebound here, but scenes/game/game_scene.gd still reads raw keys / ui_*
## actions. The game scene adopts these actions (move_*, end_turn, action_*,
## ...) in a later pass; until then only open_settings / cancel / confirm are
## read (by Main and the SettingsMenu). Mouse input is not configurable.
##
## settings.cfg format:
##   [audio]  master=80  music=80  sfx=80          ; ints 0-100 (clamped on load)
##   [input]  move_up=["Up", "W"]  end_turn=["Space"] ...
##            ; per action, up to SLOTS key strings: physical keycode plus
##            ; modifiers as OS.get_keycode_string() writes them ("Shift+W").
##            ; Missing or unparseable actions fall back to the defaults.
##   [video]  fullscreen=false  vsync=true

const DEFAULT_PATH := "user://settings.cfg"
const SECTION_AUDIO := "audio"
const SECTION_INPUT := "input"
const SECTION_VIDEO := "video"

const BUS_MASTER := "Master"
const BUS_MUSIC := "Music"
const BUS_SFX := "SFX"
const BUSES: Array[String] = [BUS_MASTER, BUS_MUSIC, BUS_SFX]
## ConfigFile key per bus.
const BUS_KEYS: Dictionary[String, String] = {BUS_MASTER: "master", BUS_MUSIC: "music", BUS_SFX: "sfx"}
const MIN_VOLUME := 0
const MAX_VOLUME := 100
const DEFAULT_VOLUME := 80
## Bus volume at slider 0 (linear_to_db(0) would be -inf).
const SILENT_DB := -80.0

## Key slots per action shown in the Controls tab.
const SLOTS := 2
const ACTION_DEADZONE := 0.2
## InputMap "any device" (InputMap::ALL_DEVICES), as the editor writes it.
const ALL_DEVICES := -1

## Configurable actions, in menu order.
const ACTIONS: Array[String] = [
	"move_up", "move_down", "move_left", "move_right",
	"end_turn", "action_attack", "action_dash", "action_dodge", "action_disengage",
	"open_spells", "open_features", "toggle_inventory", "descend", "rest",
	"confirm", "cancel", "open_settings",
]

const ACTION_LABELS: Dictionary[String, String] = {
	"move_up": "Move up",
	"move_down": "Move down",
	"move_left": "Move left",
	"move_right": "Move right",
	"end_turn": "End turn",
	"action_attack": "Attack",
	"action_dash": "Dash",
	"action_dodge": "Dodge",
	"action_disengage": "Disengage",
	"open_spells": "Spells",
	"open_features": "Features",
	"toggle_inventory": "Inventory",
	"descend": "Take the stairs",
	"rest": "Rest",
	"confirm": "Confirm",
	"cancel": "Cancel / back (menus)",
	"open_settings": "Pause / settings",
}

## Defaults; must match the [input] section of project.godot (a test checks).
const DEFAULT_BINDINGS: Dictionary[String, Array] = {
	"move_up": ["Up", "W"],
	"move_down": ["Down", "S"],
	"move_left": ["Left", "A"],
	"move_right": ["Right", "D"],
	"end_turn": ["Space"],
	"action_attack": ["1"],
	"action_dash": ["2"],
	"action_dodge": ["3"],
	"action_disengage": ["4"],
	"open_spells": ["Q"],
	"open_features": ["E"],
	"toggle_inventory": ["Tab"],
	"descend": ["F"],
	"rest": ["R"],
	"confirm": ["Enter"],
	"cancel": ["Escape"],
	"open_settings": ["Escape"],
}

## Action pairs that may share a key without counting as a conflict
## (they are read in different contexts). Stored as "a|b" with a < b.
const SHAREABLE_PAIRS: Array[String] = ["cancel|open_settings"]

var path: String = DEFAULT_PATH
var volumes: Dictionary[String, int] = {}
var fullscreen: bool = false
var vsync: bool = true
var bindings: Dictionary[String, PackedStringArray] = {}


func _init(p_path: String = DEFAULT_PATH) -> void:
	path = p_path
	reset_all()


## A GameSettings for `p_path`, loaded if the file exists (else defaults).
static func load_from(p_path: String = DEFAULT_PATH) -> GameSettings:
	var s := GameSettings.new(p_path)
	s.load_file()
	return s


func reset_all() -> void:
	for bus in BUSES:
		volumes[bus] = DEFAULT_VOLUME
	fullscreen = false
	vsync = true
	reset_bindings()


func reset_bindings() -> void:
	bindings.clear()
	for action in ACTIONS:
		bindings[action] = GameSettings.default_keys(action)


## Default key strings for `action` (empty for an unknown action).
static func default_keys(action: String) -> PackedStringArray:
	if not DEFAULT_BINDINGS.has(action):
		return PackedStringArray()
	return PackedStringArray(DEFAULT_BINDINGS[action])


func copy_from(other: GameSettings) -> void:
	volumes = other.volumes.duplicate()
	fullscreen = other.fullscreen
	vsync = other.vsync
	bindings.clear()
	for action: String in other.bindings.keys():
		bindings[action] = other.bindings[action].duplicate()


func duplicate_settings() -> GameSettings:
	var s := GameSettings.new(path)
	s.copy_from(self)
	return s


func equals(other: GameSettings) -> bool:
	if volumes != other.volumes or fullscreen != other.fullscreen or vsync != other.vsync:
		return false
	for action in ACTIONS:
		if bindings_for(action) != other.bindings_for(action):
			return false
	return true


# --- File ---------------------------------------------------------------------

## Loads `path`. Returns OK, ERR_FILE_NOT_FOUND (defaults kept) or a parse
## error (defaults kept). Out-of-range or malformed values fall back per key.
func load_file() -> Error:
	reset_all()
	if not FileAccess.file_exists(path):
		return ERR_FILE_NOT_FOUND
	var cfg := ConfigFile.new()
	var err := cfg.load(path)
	if err != OK:
		return err
	for bus in BUSES:
		var v: Variant = cfg.get_value(SECTION_AUDIO, BUS_KEYS[bus], DEFAULT_VOLUME)
		if v is int or v is float:
			set_volume(bus, int(v))
	var fs: Variant = cfg.get_value(SECTION_VIDEO, "fullscreen", false)
	fullscreen = fs if fs is bool else false
	var vs: Variant = cfg.get_value(SECTION_VIDEO, "vsync", true)
	vsync = vs if vs is bool else true
	for action in ACTIONS:
		if not cfg.has_section_key(SECTION_INPUT, action):
			continue
		var raw: Variant = cfg.get_value(SECTION_INPUT, action)
		if not (raw is Array or raw is PackedStringArray):
			continue
		var parsed := PackedStringArray()
		for item: Variant in raw:
			var canonical := GameSettings.canonical_key(str(item))
			if canonical != "" and not parsed.has(canonical) and parsed.size() < SLOTS:
				parsed.append(canonical)
		if not parsed.is_empty():
			bindings[action] = parsed
	return OK


func save_file() -> Error:
	var cfg := ConfigFile.new()
	for bus in BUSES:
		cfg.set_value(SECTION_AUDIO, BUS_KEYS[bus], volumes[bus])
	for action in ACTIONS:
		cfg.set_value(SECTION_INPUT, action, Array(bindings_for(action)))
	cfg.set_value(SECTION_VIDEO, "fullscreen", fullscreen)
	cfg.set_value(SECTION_VIDEO, "vsync", vsync)
	var dir := path.get_base_dir()
	if dir != "" and not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	return cfg.save(path)


# --- Audio --------------------------------------------------------------------

func set_volume(bus: String, value: int) -> void:
	if BUSES.has(bus):
		volumes[bus] = clampi(value, MIN_VOLUME, MAX_VOLUME)


func volume(bus: String) -> int:
	return volumes.get(bus, DEFAULT_VOLUME)


## Slider value (0-100) -> bus volume in dB; 0 is SILENT_DB, 100 is 0 dB.
static func volume_to_db(value: int) -> float:
	var v := clampi(value, MIN_VOLUME, MAX_VOLUME)
	if v <= MIN_VOLUME:
		return SILENT_DB
	return maxf(linear_to_db(float(v) / float(MAX_VOLUME)), SILENT_DB)


# --- Bindings -----------------------------------------------------------------

func bindings_for(action: String) -> PackedStringArray:
	if bindings.has(action):
		return bindings[action]
	return PackedStringArray()


## Binds `key` (a key string) to slot `slot` of `action`. A slot past the end
## appends; binding a key the action already has in its other slot moves it.
func set_binding(action: String, slot: int, key: String) -> bool:
	var canonical := GameSettings.canonical_key(key)
	if not ACTIONS.has(action) or canonical == "" or slot < 0 or slot >= SLOTS:
		return false
	var current := bindings_for(action).duplicate()
	var existing := current.find(canonical)
	if existing >= 0:
		current.remove_at(existing)
	if slot < current.size():
		current[slot] = canonical
	else:
		current.append(canonical)
	bindings[action] = current
	return true


func reset_action(action: String) -> void:
	if DEFAULT_BINDINGS.has(action):
		bindings[action] = GameSettings.default_keys(action)


## Other actions that share a key with `action` (shareable pairs excluded).
func conflicts_for(action: String) -> PackedStringArray:
	var out := PackedStringArray()
	var mine := bindings_for(action)
	for other in ACTIONS:
		if other == action or GameSettings.is_shareable(action, other):
			continue
		for key in bindings_for(other):
			if mine.has(key):
				out.append(other)
				break
	return out


## Every action with at least one conflict.
func conflicting_actions() -> PackedStringArray:
	var out := PackedStringArray()
	for action in ACTIONS:
		if not conflicts_for(action).is_empty():
			out.append(action)
	return out


static func is_shareable(a: String, b: String) -> bool:
	var pair := "%s|%s" % [a, b] if a < b else "%s|%s" % [b, a]
	return SHAREABLE_PAIRS.has(pair)


## Normalised key string ("ctrl+shift+f" -> "Shift+Ctrl+F"); "" if unknown.
static func canonical_key(key: String) -> String:
	var code := OS.find_keycode_from_string(key.strip_edges())
	if code == KEY_NONE or (code & KEY_CODE_MASK) == KEY_NONE:
		return ""
	return OS.get_keycode_string(code)


## Key string for a key event, by physical keycode (layout independent).
static func key_string(event: InputEventKey) -> String:
	var code := event.physical_keycode
	if code == KEY_NONE:
		code = event.keycode
	if code == KEY_NONE:
		return ""
	var with_mods: int = code | (event.get_modifiers_mask() as int)
	return OS.get_keycode_string(with_mods)


## InputEventKey (physical keycode + modifiers) from a key string; null if unknown.
static func event_from_string(key: String) -> InputEventKey:
	var code := OS.find_keycode_from_string(key.strip_edges())
	if (code & KEY_CODE_MASK) == KEY_NONE:
		return null
	var e := InputEventKey.new()
	e.device = ALL_DEVICES
	e.physical_keycode = (code & KEY_CODE_MASK) as Key
	e.shift_pressed = (code & KEY_MASK_SHIFT) != 0
	e.ctrl_pressed = (code & KEY_MASK_CTRL) != 0
	e.alt_pressed = (code & KEY_MASK_ALT) != 0
	e.meta_pressed = (code & KEY_MASK_META) != 0
	return e


## Key string as the player sees it on their layout (e.g. "Z" for physical W
## on AZERTY). Falls back to the stored string.
static func display_key(key: String) -> String:
	var e := GameSettings.event_from_string(key)
	if e == null or DisplayServer.get_name() == "headless":
		return key
	var label_code := DisplayServer.keyboard_get_keycode_from_physical(e.physical_keycode)
	if label_code == KEY_NONE:
		return key
	return OS.get_keycode_string(label_code | (e.get_modifiers_mask() as int))


# --- Apply --------------------------------------------------------------------

func apply() -> void:
	apply_audio()
	apply_input()
	apply_video()


func apply_audio() -> void:
	for bus in BUSES:
		var idx := AudioServer.get_bus_index(bus)
		if idx >= 0:
			AudioServer.set_bus_volume_db(idx, GameSettings.volume_to_db(volume(bus)))


## Replaces the key events of every configurable action (other event kinds,
## e.g. mouse or joypad, are kept). Missing actions are created.
func apply_input() -> void:
	for action in ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action, ACTION_DEADZONE)
		for e: InputEvent in InputMap.action_get_events(action):
			if e is InputEventKey:
				InputMap.action_erase_event(action, e)
		for key in bindings_for(action):
			var ev := GameSettings.event_from_string(key)
			if ev != null:
				InputMap.action_add_event(action, ev)


func apply_video() -> void:
	var want_mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	var mode := DisplayServer.window_get_mode()
	var is_full := mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	if fullscreen != is_full:
		DisplayServer.window_set_mode(want_mode)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)


## Key strings currently bound to `action` in the live InputMap.
static func input_map_keys(action: String) -> PackedStringArray:
	var out := PackedStringArray()
	if not InputMap.has_action(action):
		return out
	for e: InputEvent in InputMap.action_get_events(action):
		if e is InputEventKey:
			var s := GameSettings.key_string(e as InputEventKey)
			if s != "":
				out.append(s)
	return out

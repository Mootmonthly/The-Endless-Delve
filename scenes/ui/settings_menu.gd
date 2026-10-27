class_name SettingsMenu
extends CanvasLayer
## Modal overlay with two pages:
## - Pause (Escape in the game): Resume / Reactions (in a game: closes the
##   menu and opens the HUD's Reactions panel) / Settings / Quit to character
##   creator.
##   The offline InstanceServer keeps ticking while it is open (M2: there is no
##   pause in an MMO instance; an offline game is paused by Main while open).
## - Settings (from Pause, or the creator's Settings button): tabs Audio
##   (Master / Music / SFX sliders, previewed live), Controls (two key slots per
##   action; click a slot, press a key; Escape cancels; shared keys are
##   highlighted but allowed; "Reset to defaults"), Video (fullscreen, vsync, dynamic lighting).
##   Apply saves and applies; Back discards unapplied changes.
##
## Edits go to `working`, a copy of the GameSettings handed to setup(); Apply
## copies them back, saves the file and applies them. While open, the overlay
## swallows mouse clicks (full-rect blocker) and every unhandled key, so the
## game behind it gets no input. Main keeps this node after the active scene
## so it sees unhandled input first. UI is built in code from _ready().

signal closed
signal quit_requested
## The pause page's "Reactions" entry: the menu closed, the game should show
## its reaction settings.
signal reactions_requested
signal applied(settings: GameSettings)

enum Page { NONE, PAUSE, SETTINGS }

const LAYER := 50
const WAITING_TEXT := "Press a key..."
const UNBOUND_TEXT := "--"
const CONFLICT_COLOR := Color(1.0, 0.5, 0.42)
const NORMAL_COLOR := Color(1, 1, 1)
const BUS_LABELS: Dictionary[String, String] = {"Master": "Master", "Music": "Music", "SFX": "Effects"}
const TAB_AUDIO := 0
const TAB_CONTROLS := 1
const TAB_VIDEO := 2

## The applied settings (owned by Main); `working` holds unapplied edits.
var settings: GameSettings = null
var working: GameSettings = null
var page: Page = Page.NONE

var _blocker: ColorRect
var _pause_panel: PanelContainer
var _pause_title: Label
var _pause_note: Label
var _settings_panel: PanelContainer
var _resume_button: Button
var _settings_button: Button
var _reactions_button: Button
var _quit_button: Button
var _tabs: TabContainer
var _sliders: Dictionary[String, HSlider] = {}
var _slider_values: Dictionary[String, Label] = {}
var _action_labels: Dictionary[String, Label] = {}
var _binding_buttons: Dictionary[String, Array] = {}  # action -> Array[Button], one per slot
var _fullscreen_check: CheckBox
var _vsync_check: CheckBox
var _lighting_check: CheckBox
var _status: Label
var _capture_action: String = ""
var _capture_slot: int = -1
var _from_pause: bool = false
var _syncing: bool = false
var _built: bool = false


## Call before (or after) adding to the tree; `p_settings` is kept and updated on Apply.
func setup(p_settings: GameSettings) -> void:
	settings = p_settings
	working = settings.duplicate_settings()


func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	if settings == null:
		setup(GameSettings.new())
	_build_ui()
	_show_page(Page.NONE)


func is_open() -> bool:
	return page != Page.NONE


func is_capturing() -> bool:
	return _capture_action != ""


# --- Pages ----------------------------------------------------------------------

## Pause page; `allow_quit` shows "Quit to character creator", `show_reactions`
## the "Reactions" entry.
func open_pause(allow_quit: bool = true, simulation_paused: bool = false, show_reactions: bool = false) -> void:
	_build_ui()
	_quit_button.visible = allow_quit
	_reactions_button.visible = show_reactions
	_pause_title.text = "Paused" if simulation_paused else "Menu"
	_pause_note.text = (
		"Offline game: the dungeon waits while this menu is open."
		if simulation_paused
		else "Online instance: the dungeon does not wait. The world keeps moving while this menu is open."
	)
	_show_page(Page.PAUSE)
	_focus_later(_resume_button)


## Settings page. `from_pause`: Back returns to the pause page instead of closing.
func open_settings(from_pause: bool = false) -> void:
	_build_ui()
	_from_pause = from_pause
	working = settings.duplicate_settings()
	_cancel_capture()
	_sync_from_working()
	_status.text = ""
	_show_page(Page.SETTINGS)
	_tabs.current_tab = TAB_AUDIO
	_focus_later(_sliders[GameSettings.BUS_MASTER])


## Closes everything; unapplied audio preview is reverted.
func close() -> void:
	_cancel_capture()
	if settings != null:
		settings.apply_audio()
	_show_page(Page.NONE)
	closed.emit()


## Back / Escape: cancels a capture, else leaves the settings page (discarding
## unapplied edits), else closes the pause page.
func back() -> void:
	if is_capturing():
		_cancel_capture()
		_refresh_controls()
		return
	match page:
		Page.SETTINGS:
			working = settings.duplicate_settings()
			settings.apply_audio()
			if _from_pause:
				open_pause(_quit_button.visible, _pause_title.text == "Paused", _reactions_button.visible)
			else:
				close()
		Page.PAUSE:
			close()


func apply_changes() -> void:
	_cancel_capture()
	settings.copy_from(working)
	var err := settings.save_file()
	settings.apply()
	_status.text = "Saved." if err == OK else "Applied, but could not save (error %d)." % err
	_refresh_controls()
	applied.emit(settings)


func has_unapplied_changes() -> bool:
	return working != null and settings != null and not working.equals(settings)


# --- Audio / video --------------------------------------------------------------

## Slider handler; also callable directly. Previews the volume on the bus.
func set_volume(bus: String, value: int) -> void:
	working.set_volume(bus, value)
	working.apply_audio()
	_slider_values[bus].text = "%d%%" % working.volume(bus)
	if not _syncing and _sliders[bus].value != working.volume(bus):
		_sliders[bus].value = working.volume(bus)
	_mark_dirty()


func _on_slider_changed(value: float, bus: String) -> void:
	if _syncing:
		return
	set_volume(bus, int(value))


func _on_fullscreen_toggled(on: bool) -> void:
	if not _syncing:
		working.fullscreen = on
		_mark_dirty()


func _on_vsync_toggled(on: bool) -> void:
	if not _syncing:
		working.vsync = on
		_mark_dirty()


## Also callable directly (tests): the dynamic lighting toggle.
func _on_lighting_toggled(on: bool) -> void:
	if not _syncing:
		working.lighting = on
		_mark_dirty()


# --- Rebinding ------------------------------------------------------------------

func start_capture(action: String, slot: int) -> void:
	_cancel_capture()
	_refresh_controls()
	_capture_action = action
	_capture_slot = slot
	var b: Button = _binding_buttons[action][slot]
	b.text = WAITING_TEXT
	b.modulate = NORMAL_COLOR


## Feeds a key press to an active capture. Escape cancels; modifier keys alone
## are ignored (so Shift+W can be bound). Returns true if the event was used.
func capture_key(event: InputEventKey) -> bool:
	if not is_capturing() or not event.pressed or event.echo:
		return false
	var code: Key = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
	if code in [KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META]:
		return true
	if code == KEY_ESCAPE:
		_cancel_capture()
		_refresh_controls()
		return true
	var key := GameSettings.key_string(event)
	if key != "":
		working.set_binding(_capture_action, _capture_slot, key)
		_mark_dirty()
	var focus_button: Button = _binding_buttons[_capture_action][mini(_capture_slot, GameSettings.SLOTS - 1)]
	_cancel_capture()
	_refresh_controls()
	_focus_later(focus_button)
	return true


func reset_bindings_to_defaults() -> void:
	_cancel_capture()
	working.reset_bindings()
	_refresh_controls()
	_mark_dirty()


func _cancel_capture() -> void:
	_capture_action = ""
	_capture_slot = -1


# --- Input ----------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if not is_capturing() or not (event is InputEventKey):
		return
	if capture_key(event as InputEventKey):
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if not is_open():
		return
	if event.is_action_pressed("cancel") or event.is_action_pressed("open_settings"):
		back()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey:
		# Nothing behind the overlay gets keys while it is open.
		get_viewport().set_input_as_handled()


# --- UI -------------------------------------------------------------------------

func _show_page(p: Page) -> void:
	page = p
	visible = p != Page.NONE
	if _blocker == null:
		return
	_blocker.visible = visible
	_pause_panel.visible = p == Page.PAUSE
	_settings_panel.visible = p == Page.SETTINGS


func _build_ui() -> void:
	if _built:
		return
	_built = true
	_blocker = ColorRect.new()
	_blocker.color = Color(0, 0, 0, 0.6)
	_blocker.set_anchors_preset(Control.PRESET_FULL_RECT)
	_blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_blocker)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_blocker.add_child(center)
	_pause_panel = _build_pause_panel()
	center.add_child(_pause_panel)
	_settings_panel = _build_settings_panel()
	center.add_child(_settings_panel)


func _panel_box(panel: PanelContainer) -> VBoxContainer:
	var margin := MarginContainer.new()
	for side: String in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 20)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)
	return box


func _title(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 24)
	return l


func _button(text: String, handler: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(handler)
	return b


func _build_pause_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	var box := _panel_box(panel)
	box.custom_minimum_size = Vector2(320, 0)
	_pause_title = _title("Menu")
	box.add_child(_pause_title)
	var note := Label.new()
	note.text = "Online instance: the dungeon does not wait. The world keeps moving while this menu is open."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(320, 0)
	note.modulate = Color(0.8, 0.8, 0.85)
	box.add_child(note)
	_pause_note = note
	_resume_button = _button("Resume", close)
	box.add_child(_resume_button)
	_reactions_button = _button("Reactions", _on_reactions_pressed)
	_reactions_button.tooltip_text = "Which reactions your character takes on its own"
	_reactions_button.visible = false
	box.add_child(_reactions_button)
	_settings_button = _button("Settings", open_settings.bind(true))
	box.add_child(_settings_button)
	_quit_button = _button("Quit to character creator", _on_quit_pressed)
	box.add_child(_quit_button)
	return panel


func _build_settings_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	var box := _panel_box(panel)
	box.add_child(_title("Settings"))
	_tabs = TabContainer.new()
	_tabs.custom_minimum_size = Vector2(620, 440)
	box.add_child(_tabs)
	_tabs.add_child(_build_audio_tab())
	_tabs.add_child(_build_controls_tab())
	_tabs.add_child(_build_video_tab())
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	box.add_child(footer)
	_status = Label.new()
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.modulate = Color(0.8, 0.8, 0.85)
	footer.add_child(_status)
	footer.add_child(_button("Back", back))
	footer.add_child(_button("Apply", apply_changes))
	return panel


func _build_audio_tab() -> Control:
	var grid := GridContainer.new()
	grid.name = "Audio"
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 12)
	for bus in GameSettings.BUSES:
		var l := Label.new()
		l.text = BUS_LABELS.get(bus, bus)
		grid.add_child(l)
		var slider := HSlider.new()
		slider.min_value = GameSettings.MIN_VOLUME
		slider.max_value = GameSettings.MAX_VOLUME
		slider.step = 1
		slider.custom_minimum_size = Vector2(360, 0)
		slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		slider.value_changed.connect(_on_slider_changed.bind(bus))
		grid.add_child(slider)
		_sliders[bus] = slider
		var value := Label.new()
		value.custom_minimum_size = Vector2(56, 0)
		grid.add_child(value)
		_slider_values[bus] = value
	return grid


func _build_controls_tab() -> Control:
	var outer := VBoxContainer.new()
	outer.name = "Controls"
	var hint := Label.new()
	hint.text = "Click a key, then press the new key (Escape cancels). Shared keys are shown in red."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.modulate = Color(0.8, 0.8, 0.85)
	outer.add_child(hint)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 1 + GameSettings.SLOTS
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 12)
	scroll.add_child(grid)
	for action in GameSettings.ACTIONS:
		var l := Label.new()
		l.text = GameSettings.ACTION_LABELS.get(action, action)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(l)
		_action_labels[action] = l
		var buttons: Array[Button] = []
		for slot in range(GameSettings.SLOTS):
			var b := Button.new()
			b.custom_minimum_size = Vector2(150, 0)
			b.pressed.connect(start_capture.bind(action, slot))
			grid.add_child(b)
			buttons.append(b)
		_binding_buttons[action] = buttons
	outer.add_child(_button("Reset to defaults", reset_bindings_to_defaults))
	return outer


func _build_video_tab() -> Control:
	var box := VBoxContainer.new()
	box.name = "Video"
	_fullscreen_check = CheckBox.new()
	_fullscreen_check.text = "Fullscreen"
	_fullscreen_check.toggled.connect(_on_fullscreen_toggled)
	box.add_child(_fullscreen_check)
	_vsync_check = CheckBox.new()
	_vsync_check.text = "V-Sync"
	_vsync_check.toggled.connect(_on_vsync_toggled)
	box.add_child(_vsync_check)
	_lighting_check = CheckBox.new()
	_lighting_check.name = "Lighting"
	_lighting_check.text = "Dynamic lighting (darkness, torches, vignette)"
	_lighting_check.toggled.connect(_on_lighting_toggled)
	box.add_child(_lighting_check)
	return box


func _sync_from_working() -> void:
	_syncing = true
	for bus in GameSettings.BUSES:
		_sliders[bus].value = working.volume(bus)
		_slider_values[bus].text = "%d%%" % working.volume(bus)
	_fullscreen_check.button_pressed = working.fullscreen
	_vsync_check.button_pressed = working.vsync
	_lighting_check.button_pressed = working.lighting
	_syncing = false
	_refresh_controls()


func _refresh_controls() -> void:
	for action in GameSettings.ACTIONS:
		var keys := working.bindings_for(action)
		var conflicts := working.conflicts_for(action)
		var names := PackedStringArray()
		for other in conflicts:
			names.append(GameSettings.ACTION_LABELS.get(other, other))
		var tip := "" if conflicts.is_empty() else "Also used by: %s" % ", ".join(names)
		_action_labels[action].modulate = CONFLICT_COLOR if not conflicts.is_empty() else NORMAL_COLOR
		for slot in range(GameSettings.SLOTS):
			var b: Button = _binding_buttons[action][slot]
			if action == _capture_action and slot == _capture_slot:
				b.text = WAITING_TEXT
				b.modulate = NORMAL_COLOR
				continue
			var key: String = keys[slot] if slot < keys.size() else ""
			b.text = GameSettings.display_key(key) if key != "" else UNBOUND_TEXT
			var shared := key != "" and _key_conflicts(action, key)
			b.modulate = CONFLICT_COLOR if shared else NORMAL_COLOR
			b.tooltip_text = tip if shared else ""


## True when another (non-shareable) action also uses `key`.
func _key_conflicts(action: String, key: String) -> bool:
	for other in GameSettings.ACTIONS:
		if other != action and not GameSettings.is_shareable(action, other) and working.bindings_for(other).has(key):
			return true
	return false


func _focus_later(control: Control) -> void:
	if is_inside_tree():
		control.grab_focus.call_deferred()


func _mark_dirty() -> void:
	if _status != null and not _syncing:
		_status.text = "Unapplied changes." if has_unapplied_changes() else ""


func _on_quit_pressed() -> void:
	_cancel_capture()
	if settings != null:
		settings.apply_audio()
	_show_page(Page.NONE)
	quit_requested.emit()


func _on_reactions_pressed() -> void:
	close()
	reactions_requested.emit()

extends TestCase
## GameSettings: defaults match project.godot, ConfigFile round trip (temp
## path), clamping, bus volumes, InputMap rebinding and reset, conflicts; and
## the SettingsMenu built off-tree (its _ready() called by hand; off-tree a
## Range emits no value_changed, so slider handlers are called directly).
## Every test restores the default InputMap keys and the original bus volumes.

const TMP_DIR := "user://test_tmp"
const TMP_PATH := "user://test_tmp/settings_test.cfg"

var _bus_db: Dictionary[String, float] = {}


func before_each() -> void:
	_bus_db.clear()
	for bus in GameSettings.BUSES:
		var idx := AudioServer.get_bus_index(bus)
		if idx >= 0:
			_bus_db[bus] = AudioServer.get_bus_volume_db(idx)
	_remove_tmp()


func after_each() -> void:
	for bus: String in _bus_db.keys():
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index(bus), _bus_db[bus])
	GameSettings.new(TMP_PATH).apply_input()
	_remove_tmp()


func _remove_tmp() -> void:
	if FileAccess.file_exists(TMP_PATH):
		DirAccess.remove_absolute(TMP_PATH)


func _bus_db_now(bus: String) -> float:
	return AudioServer.get_bus_volume_db(AudioServer.get_bus_index(bus))


func _write_cfg(text: String) -> void:
	DirAccess.make_dir_recursive_absolute(TMP_DIR)
	var f := FileAccess.open(TMP_PATH, FileAccess.WRITE)
	f.store_string(text)
	f.close()


# --- Defaults -------------------------------------------------------------------

func test_bus_layout_has_master_music_sfx() -> void:
	for bus in GameSettings.BUSES:
		assert_true(AudioServer.get_bus_index(bus) >= 0, "bus %s exists" % bus)
	assert_eq(AudioServer.get_bus_send(AudioServer.get_bus_index("Music")), &"Master")
	assert_eq(AudioServer.get_bus_send(AudioServer.get_bus_index("SFX")), &"Master")


func test_project_input_map_matches_defaults() -> void:
	for action in GameSettings.ACTIONS:
		assert_true(ProjectSettings.has_setting("input/" + action), "project.godot defines %s" % action)
		var keys := PackedStringArray()
		var entry: Dictionary = ProjectSettings.get_setting("input/" + action, {})
		for e: Variant in entry.get("events", []):
			if e is InputEventKey:
				keys.append(GameSettings.key_string(e as InputEventKey))
		assert_eq(keys, GameSettings.default_keys(action), action)
		assert_eq(GameSettings.input_map_keys(action), GameSettings.default_keys(action), "InputMap %s" % action)
		assert_true(GameSettings.ACTION_LABELS.has(action), "label for %s" % action)


func test_movement_defaults_are_arrows_and_wasd() -> void:
	var s := GameSettings.new(TMP_PATH)
	assert_eq(s.bindings_for("move_up"), PackedStringArray(["Up", "W"]))
	assert_eq(s.bindings_for("move_left"), PackedStringArray(["Left", "A"]))
	assert_eq(s.bindings_for("move_down"), PackedStringArray(["Down", "S"]))
	assert_eq(s.bindings_for("move_right"), PackedStringArray(["Right", "D"]))
	assert_eq(s.bindings_for("open_settings"), PackedStringArray(["Escape"]))


func test_defaults_have_no_conflicts() -> void:
	var s := GameSettings.new(TMP_PATH)
	assert_eq(s.conflicting_actions(), PackedStringArray(), "cancel and open_settings may share Escape")


# --- File -----------------------------------------------------------------------

func test_missing_file_keeps_defaults() -> void:
	var s := GameSettings.new(TMP_PATH)
	assert_eq(s.load_file(), ERR_FILE_NOT_FOUND)
	assert_true(s.equals(GameSettings.new()), "defaults")


func test_round_trip_through_config_file() -> void:
	var s := GameSettings.new(TMP_PATH)
	s.set_volume("Master", 55)
	s.set_volume("Music", 0)
	s.set_volume("SFX", 100)
	s.fullscreen = true
	s.vsync = false
	assert_true(s.set_binding("end_turn", 0, "Enter"))
	assert_true(s.set_binding("move_up", 1, "Shift+I"))
	assert_eq(s.save_file(), OK)
	assert_true(FileAccess.file_exists(TMP_PATH))
	var back := GameSettings.load_from(TMP_PATH)
	assert_true(back.equals(s), "loaded equals saved")
	assert_eq(back.volume("Master"), 55)
	assert_eq(back.volume("Music"), 0)
	assert_true(back.fullscreen)
	assert_false(back.vsync)
	assert_eq(back.bindings_for("end_turn"), PackedStringArray(["Enter"]))
	assert_eq(back.bindings_for("move_up"), PackedStringArray(["Up", "Shift+I"]))
	var cfg := ConfigFile.new()
	assert_eq(cfg.load(TMP_PATH), OK)
	assert_eq(cfg.get_value("audio", "master"), 55)
	assert_eq(cfg.get_value("input", "move_up"), ["Up", "Shift+I"])
	assert_eq(cfg.get_value("video", "fullscreen"), true)


func test_load_clamps_and_repairs_bad_values() -> void:
	_write_cfg("[audio]\nmaster=250\nmusic=-3\nsfx=\"loud\"\n" +
		"[input]\nmove_up=[\"Nonsense\"]\nend_turn=[\"ctrl+shift+f\", \"Bogus\", \"P\", \"O\"]\nrest=5\n" +
		"[video]\nfullscreen=\"yes\"\nvsync=false\n")
	var s := GameSettings.load_from(TMP_PATH)
	assert_eq(s.volume("Master"), 100, "clamped high")
	assert_eq(s.volume("Music"), 0, "clamped low")
	assert_eq(s.volume("SFX"), GameSettings.DEFAULT_VOLUME, "non-number -> default")
	assert_eq(s.bindings_for("move_up"), GameSettings.default_keys("move_up"), "all-bad list -> default")
	assert_eq(s.bindings_for("end_turn"), PackedStringArray(["Shift+Ctrl+F", "P"]), "canonical, bad dropped, max SLOTS")
	assert_eq(s.bindings_for("rest"), GameSettings.default_keys("rest"), "non-list -> default")
	assert_false(s.fullscreen, "non-bool -> default")
	assert_false(s.vsync)


func test_set_volume_clamps() -> void:
	var s := GameSettings.new(TMP_PATH)
	s.set_volume("Music", 140)
	assert_eq(s.volume("Music"), 100)
	s.set_volume("Music", -1)
	assert_eq(s.volume("Music"), 0)
	s.set_volume("NoSuchBus", 10)
	assert_false(s.volumes.has("NoSuchBus"))


# --- Audio ----------------------------------------------------------------------

func test_volume_to_db() -> void:
	assert_eq(GameSettings.volume_to_db(0), GameSettings.SILENT_DB)
	assert_eq(GameSettings.volume_to_db(100), 0.0)
	assert_in_range(GameSettings.volume_to_db(50), -6.1, -6.0)
	assert_eq(GameSettings.volume_to_db(-20), GameSettings.SILENT_DB)


func test_apply_audio_sets_bus_volumes() -> void:
	var s := GameSettings.new(TMP_PATH)
	s.set_volume("Master", 100)
	s.set_volume("Music", 0)
	s.set_volume("SFX", 50)
	s.apply_audio()
	assert_in_range(_bus_db_now("Master"), -0.01, 0.01)
	assert_eq(_bus_db_now("Music"), GameSettings.SILENT_DB)
	assert_in_range(_bus_db_now("SFX"), -6.1, -6.0)


# --- Input ----------------------------------------------------------------------

func test_key_string_round_trip() -> void:
	for key: String in ["W", "Up", "Space", "Escape", "Tab", "Enter", "1", "Shift+W", "Shift+Ctrl+F"]:
		var e := GameSettings.event_from_string(key)
		assert_not_null(e, key)
		if e != null:
			assert_eq(GameSettings.key_string(e), key)
			assert_eq(e.device, GameSettings.ALL_DEVICES)
	assert_null(GameSettings.event_from_string("Nonsense"))
	assert_eq(GameSettings.canonical_key("ctrl+shift+f"), "Shift+Ctrl+F")
	assert_eq(GameSettings.canonical_key(""), "")


func test_rebinding_changes_input_map_and_reset_restores() -> void:
	var s := GameSettings.new(TMP_PATH)
	assert_true(s.set_binding("move_up", 1, "I"))
	assert_true(s.set_binding("end_turn", 0, "Enter"))
	s.apply_input()
	assert_eq(GameSettings.input_map_keys("move_up"), PackedStringArray(["Up", "I"]))
	assert_eq(GameSettings.input_map_keys("end_turn"), PackedStringArray(["Enter"]))
	var press := InputEventKey.new()
	press.physical_keycode = KEY_I
	press.pressed = true
	assert_true(InputMap.event_is_action(press, "move_up"), "I now moves up")
	press.physical_keycode = KEY_W
	assert_false(InputMap.event_is_action(press, "move_up"), "W no longer does")
	press.physical_keycode = KEY_SPACE
	assert_false(InputMap.event_is_action(press, "end_turn"))
	s.reset_bindings()
	s.apply_input()
	for action in GameSettings.ACTIONS:
		assert_eq(GameSettings.input_map_keys(action), GameSettings.default_keys(action), action)
	press.physical_keycode = KEY_W
	assert_true(InputMap.event_is_action(press, "move_up"), "W back on move_up")


func test_apply_input_keeps_non_key_events() -> void:
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_RIGHT
	InputMap.action_add_event("rest", mouse)
	GameSettings.new(TMP_PATH).apply_input()
	assert_true(InputMap.action_has_event("rest", mouse), "mouse event kept")
	InputMap.action_erase_event("rest", mouse)


func test_set_binding_slots() -> void:
	var s := GameSettings.new(TMP_PATH)
	assert_true(s.set_binding("rest", 1, "T"), "slot past end appends")
	assert_eq(s.bindings_for("rest"), PackedStringArray(["R", "T"]))
	assert_true(s.set_binding("rest", 0, "T"), "same key moves, no duplicate")
	assert_eq(s.bindings_for("rest"), PackedStringArray(["T"]))
	assert_false(s.set_binding("rest", GameSettings.SLOTS, "Y"), "slot out of range")
	assert_false(s.set_binding("rest", 0, "Nonsense"), "unknown key")
	assert_false(s.set_binding("no_such_action", 0, "Y"))
	s.reset_action("rest")
	assert_eq(s.bindings_for("rest"), PackedStringArray(["R"]))


func test_conflicts_are_reported_both_ways() -> void:
	var s := GameSettings.new(TMP_PATH)
	s.set_binding("action_attack", 0, "Q")
	assert_eq(s.conflicts_for("action_attack"), PackedStringArray(["open_spells"]))
	assert_eq(s.conflicts_for("open_spells"), PackedStringArray(["action_attack"]))
	assert_eq(s.conflicting_actions(), PackedStringArray(["action_attack", "open_spells"]))
	s.set_binding("rest", 0, "Escape")
	assert_has(s.conflicts_for("rest"), "cancel")
	assert_has(s.conflicts_for("rest"), "open_settings")


# --- SettingsMenu -----------------------------------------------------------------

func _menu() -> SettingsMenu:
	var packed: PackedScene = load("res://scenes/ui/settings_menu.tscn")
	var menu := packed.instantiate() as SettingsMenu
	menu.setup(GameSettings.new(TMP_PATH))
	menu._ready()
	return menu


func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.pressed = true
	return e


func test_menu_slider_changes_bus_volume_and_back_reverts() -> void:
	var menu := _menu()
	assert_false(menu.is_open())
	menu.settings.apply_audio()
	menu.open_settings()
	assert_true(menu.is_open())
	# Off-tree a Range does not emit value_changed; call its handler as the slider would.
	menu._on_slider_changed(0.0, "Music")
	assert_eq(menu._sliders["Music"].value, 0.0)
	assert_eq(_bus_db_now("Music"), GameSettings.SILENT_DB, "live preview")
	assert_eq(menu._slider_values["Music"].text, "0%")
	assert_true(menu.has_unapplied_changes())
	menu.back()
	assert_false(menu.is_open())
	assert_in_range(_bus_db_now("Music"), GameSettings.volume_to_db(80) - 0.01, GameSettings.volume_to_db(80) + 0.01)
	menu.free()


func test_menu_apply_saves_and_applies() -> void:
	var menu := _menu()
	menu.open_settings()
	menu.set_volume("SFX", 50)
	assert_eq(menu._sliders["SFX"].value, 50.0, "slider follows")
	menu._on_vsync_toggled(false)
	menu.apply_changes()
	assert_false(menu.has_unapplied_changes())
	assert_eq(menu.settings.volume("SFX"), 50)
	assert_false(menu.settings.vsync)
	assert_in_range(_bus_db_now("SFX"), -6.1, -6.0)
	assert_eq(GameSettings.load_from(TMP_PATH).volume("SFX"), 50, "saved")
	menu.free()


func test_menu_rebind_capture_escape_and_reset() -> void:
	var menu := _menu()
	menu.open_settings()
	var b: Button = menu._binding_buttons["end_turn"][0]
	b.pressed.emit()
	assert_true(menu.is_capturing())
	assert_eq(b.text, SettingsMenu.WAITING_TEXT)
	assert_true(menu.capture_key(_key(KEY_ESCAPE)), "escape handled")
	assert_false(menu.is_capturing(), "escape cancels")
	assert_eq(menu.working.bindings_for("end_turn"), PackedStringArray(["Space"]))
	menu.start_capture("end_turn", 0)
	assert_true(menu.capture_key(_key(KEY_SHIFT)), "modifier alone ignored")
	assert_true(menu.is_capturing())
	menu.capture_key(_key(KEY_Q))
	assert_false(menu.is_capturing())
	assert_eq(menu.working.bindings_for("end_turn"), PackedStringArray(["Q"]))
	assert_eq(b.modulate, SettingsMenu.CONFLICT_COLOR, "Q shared with Spells")
	var spells: Button = menu._binding_buttons["open_spells"][0]
	assert_eq(spells.modulate, SettingsMenu.CONFLICT_COLOR)
	menu.apply_changes()
	assert_eq(GameSettings.input_map_keys("end_turn"), PackedStringArray(["Q"]))
	menu.reset_bindings_to_defaults()
	assert_eq(b.modulate, SettingsMenu.NORMAL_COLOR)
	menu.apply_changes()
	assert_eq(GameSettings.input_map_keys("end_turn"), PackedStringArray(["Space"]))
	menu.free()


func test_menu_pause_page() -> void:
	var menu := _menu()
	var quits: Array[int] = [0]
	menu.quit_requested.connect(func() -> void: quits[0] += 1)
	menu.open_pause(true)
	assert_eq(menu.page, SettingsMenu.Page.PAUSE)
	assert_true(menu._quit_button.visible)
	menu._settings_button.pressed.emit()
	assert_eq(menu.page, SettingsMenu.Page.SETTINGS)
	menu.back()
	assert_eq(menu.page, SettingsMenu.Page.PAUSE, "Back from settings returns to pause")
	menu._quit_button.pressed.emit()
	assert_false(menu.is_open())
	assert_eq(quits[0], 1)
	menu.open_pause(false)
	assert_false(menu._quit_button.visible)
	menu._resume_button.pressed.emit()
	assert_false(menu.is_open())
	menu.free()


func test_menu_pause_page_reactions_entry() -> void:
	var menu := _menu()
	var asked: Array[int] = [0]
	menu.reactions_requested.connect(func() -> void: asked[0] += 1)
	menu.open_pause(true)
	assert_false(menu._reactions_button.visible, "only when the game asks for it")
	menu.open_pause(true, true, true)
	assert_true(menu._reactions_button.visible)
	menu._settings_button.pressed.emit()
	menu.back()
	assert_true(menu._reactions_button.visible, "kept when coming back from settings")
	assert_eq(menu._pause_title.text, "Paused")
	menu._reactions_button.pressed.emit()
	assert_false(menu.is_open(), "the menu closes")
	assert_eq(asked[0], 1)
	menu.free()

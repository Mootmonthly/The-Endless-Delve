class_name Hud
extends CanvasLayer
## Heads-up display for the GameScene, built in code: character panel (name,
## class, level, HP bar, floor, mode, movement / action), initiative order,
## action bar, stairs buttons, combat log and the end-of-run panel.
##
## Reads a ClientState in refresh(); user choices leave as signals and the
## GameScene turns them into intents. Buttons never take keyboard focus, so
## the arrow keys and Space stay free for the map.

## "attack", "dash", "dodge", "disengage", "end_turn", "use_stairs" or "short_rest".
signal action_requested(action: String)
## The run is over (game over / floor cleared) and the player wants a new character.
signal new_character_requested

const PANEL_WIDTH := 300
const LOG_HEIGHT := 170

var _name_label: Label
var _hp_bar: ProgressBar
var _hp_label: Label
var _floor_label: Label
var _mode_label: Label
var _turn_label: Label
var _order_label: Label
var _order_panel: PanelContainer
var _log: RichTextLabel
var _buttons: Dictionary = {}  # action -> Button
var _end_panel: PanelContainer
var _end_title: Label
var _end_text: Label


func _ready() -> void:
	layer = 10
	var root := Control.new()
	root.name = "Root"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_build_status(root)
	_build_order(root)
	_build_bottom(root)
	_build_end_panel(root)


func _build_status(root: Control) -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(8, 8)
	panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	root.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	_name_label = Label.new()
	box.add_child(_name_label)
	var hp_row := HBoxContainer.new()
	box.add_child(hp_row)
	_hp_bar = ProgressBar.new()
	_hp_bar.show_percentage = false
	_hp_bar.custom_minimum_size = Vector2(180, 14)
	_hp_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_hp_bar.modulate = Color(0.9, 0.3, 0.3)
	hp_row.add_child(_hp_bar)
	_hp_label = Label.new()
	hp_row.add_child(_hp_label)
	_floor_label = Label.new()
	box.add_child(_floor_label)
	_mode_label = Label.new()
	box.add_child(_mode_label)
	_turn_label = Label.new()
	_turn_label.modulate = Color(0.75, 0.85, 1.0)
	box.add_child(_turn_label)


func _build_order(root: Control) -> void:
	_order_panel = PanelContainer.new()
	_order_panel.anchor_left = 1.0
	_order_panel.anchor_right = 1.0
	_order_panel.offset_left = -228
	_order_panel.offset_right = -8
	_order_panel.offset_top = 8
	_order_panel.offset_bottom = 8
	_order_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_order_panel.visible = false
	root.add_child(_order_panel)
	var box := VBoxContainer.new()
	_order_panel.add_child(box)
	var title := Label.new()
	title.text = "Initiative"
	box.add_child(title)
	_order_label = Label.new()
	box.add_child(_order_label)


func _build_bottom(root: Control) -> void:
	var bottom := VBoxContainer.new()
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_left = 8
	bottom.offset_right = -8
	bottom.offset_top = -(LOG_HEIGHT + 56)
	bottom.offset_bottom = -8
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bottom)
	var bar := HBoxContainer.new()
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_child(bar)
	_add_button(bar, "attack", "Attack")
	_add_button(bar, "dash", "Dash")
	_add_button(bar, "dodge", "Dodge")
	_add_button(bar, "disengage", "Disengage")
	_add_button(bar, "end_turn", "End Turn [Space]")
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(spacer)
	_add_button(bar, "short_rest", "Short rest (spend 1 Hit Die)")
	_add_button(bar, "use_stairs", "Descend")
	var log_panel := PanelContainer.new()
	log_panel.custom_minimum_size = Vector2(0, LOG_HEIGHT)
	log_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(log_panel)
	_log = RichTextLabel.new()
	_log.scroll_following = true
	_log.bbcode_enabled = false
	_log.focus_mode = Control.FOCUS_NONE
	log_panel.add_child(_log)


func _add_button(parent: Control, action: String, text: String) -> void:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.disabled = true
	b.pressed.connect(func() -> void: action_requested.emit(action))
	parent.add_child(b)
	_buttons[action] = b


func _build_end_panel(root: Control) -> void:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)
	_end_panel = PanelContainer.new()
	_end_panel.visible = false
	center.add_child(_end_panel)
	var margin := MarginContainer.new()
	for side: String in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 24)
	_end_panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	margin.add_child(box)
	_end_title = Label.new()
	_end_title.add_theme_font_size_override("font_size", 28)
	_end_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_end_title)
	_end_text = Label.new()
	_end_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_end_text)
	var again := Button.new()
	again.text = "New character"
	again.pressed.connect(func() -> void: new_character_requested.emit())
	box.add_child(again)


## Adds lines to the combat log.
func append_log(lines: Array[String]) -> void:
	for line in lines:
		_log.add_text(line + "\n")


## Shows a message in the end panel (also used for load failures).
func show_end(title: String, text: String) -> void:
	_end_title.text = title
	_end_text.text = text
	_end_panel.visible = true


func refresh(state: ClientState) -> void:
	var sheet := state.sheet
	if sheet != null:
		_name_label.text = "%s - level %d %s" % [sheet.name, sheet.level, sheet.class_id.capitalize()]
		_hp_bar.max_value = sheet.max_hp
		_hp_bar.value = sheet.current_hp
		var hp_text := "HP %d / %d" % [sheet.current_hp, sheet.max_hp]
		if sheet.dead:
			hp_text += " (dead)"
		elif sheet.current_hp == 0:
			hp_text += " (stable)" if sheet.stable else " (dying %d/%d)" % [sheet.death_save_successes, sheet.death_save_failures]
		_hp_label.text = hp_text + "   AC %d" % sheet.armor_class()
	else:
		_name_label.text = "Connecting..."
	_floor_label.text = state.floor_data.display_name if state.floor_data != null else ""
	_mode_label.text = state.mode_text()
	if state.is_my_turn():
		_turn_label.text = "Movement: %d tiles (%d ft)   Action: %s" % [
			state.movement_remaining, state.movement_remaining * GridMath.FEET_PER_TILE,
			"used" if state.action_used else "ready"]
	elif state.can_use_stairs():
		_turn_label.text = "You stand on the stairs."
	else:
		_turn_label.text = ""
	_order_panel.visible = state.in_encounter
	var lines: PackedStringArray = []
	for id in state.order:
		var e := state.get_entity(id)
		var marker := "> " if id == state.current_actor else "   "
		var status := ""
		if bool(e.get("dead", false)):
			status = " (dead)"
		elif bool(e.get("down", false)):
			status = " (down)"
		lines.append("%s%s  [%d]%s" % [marker, state.display_name(id), int(state.initiatives.get(id, 0)), status])
	_order_label.text = "\n".join(lines)
	var my_action := state.can_take_action()
	_set_enabled("attack", state.can_attack())
	_set_enabled("dash", my_action)
	_set_enabled("dodge", my_action)
	_set_enabled("disengage", my_action)
	_set_enabled("end_turn", state.is_my_turn())
	_set_enabled("use_stairs", state.can_use_stairs())
	_set_enabled("short_rest", state.can_short_rest())
	var stairs_button: Button = _buttons["use_stairs"]
	stairs_button.visible = state.on_stairs()
	var rest_button: Button = _buttons["short_rest"]
	rest_button.visible = state.on_stairs()
	match state.mode:
		ClientState.Mode.GAME_OVER:
			show_end("Game over", "Your party has fallen. Permadeath: the delve starts again from floor 1.")
		ClientState.Mode.FLOOR_CLEARED:
			show_end("Floor cleared", "You reached the stairs of %s. (Milestone 1 ends here.)" % (state.floor_data.display_name if state.floor_data != null else state.cleared_floor_id))
		_:
			_end_panel.visible = false


func _set_enabled(action: String, on: bool) -> void:
	var b: Button = _buttons[action]
	b.disabled = not on

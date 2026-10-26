class_name Hud
extends CanvasLayer
## Heads-up display for the GameScene, built in code:
## - character panel: name, class, level / XP, HP bar (+ temp HP), AC, spell
##   slots, class resources, gold, floor, mode, movement / action / bonus
##   action, the targeting hint and a "Level up available" button;
## - initiative order with status tags (dodging, raging, marked, ...);
## - action bar: Attack [1] with the attack picker (melee / thrown / ranged),
##   Spells [Q], Features [E], Dash [2], Dodge [3], Disengage [4],
##   End Turn [Space], Inventory [Tab], Short rest [R] and the stairs [F];
## - Spells popup (prepared spells, slot choice per leveled spell, greyed out
##   when not castable now or not supported by the rules engine yet) and
##   Features popup (Second Wind, Rage, Lay on Hands with an amount, Bardic
##   Inspiration, the Martial Arts strike);
## - InventoryPanel (Tab): equipment slots, items with icon / qty / weight and
##   Use / Equip / Unequip / Drop, gold, carried weight and the AC breakdown;
## - combat log and the end-of-run panel.
##
## Reads a ClientState in refresh(). Spells / features / items call the
## state's begin_* helpers (targeting mode) and send ready intents through
## intent_requested; other choices leave as action_requested. Buttons never
## take keyboard focus, so the movement keys stay free for the map.

## "attack", "dash", "dodge", "disengage", "end_turn", "use_stairs", "short_rest",
## "level_up" (open the level-up screen) or "inventory" (toggle the panel).
signal action_requested(action: String)
## A finished intent built from a HUD choice (cast, feature, item, equipment).
signal intent_requested(intent: Dictionary)
## The HUD changed the ClientState (targeting, attack choice): redraw.
signal state_changed
## The run is over (game over / floor or set cleared) and the player wants a new character.
signal new_character_requested

const PANEL_WIDTH := 320
const LOG_HEIGHT := 150
const POPUP_WIDTH := 380
const ICON_SIZE := 24
const GREY := Color(0.6, 0.6, 0.6)
const WARN := Color(1.0, 0.7, 0.45)

var _state: ClientState = null
var _icons: EntityIcons = null

var _name_label: Label
var _hp_bar: ProgressBar
var _hp_label: Label
var _xp_label: Label
var _slots_label: Label
var _resources_label: Label
var _gold_label: Label
var _floor_label: Label
var _mode_label: Label
var _turn_label: Label
var _hint_label: Label
var _level_up_button: Button
var _order_label: Label
var _order_panel: PanelContainer
var _log: RichTextLabel
var _buttons: Dictionary = {}  # action -> Button
var _attack_picker: OptionButton
var _attack_picker_key: String = ""
var _end_panel: PanelContainer
var _end_title: Label
var _end_text: Label

var _spells_panel: PanelContainer
var _spells_box: VBoxContainer
var _spells_key: String = ""
var _features_panel: PanelContainer
var _features_box: VBoxContainer
var _features_key: String = ""
var _lay_amount: SpinBox = null

var _inventory_panel: PanelContainer
var _inv_gold: Label
var _inv_ac: Label
var _inv_weight: Label
var _inv_slots_box: VBoxContainer
var _inv_items_box: VBoxContainer
var _inv_note: Label
var _inventory_key: String = ""


func _ready() -> void:
	layer = 10
	_icons = EntityIcons.shared()
	var root := Control.new()
	root.name = "Root"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_build_status(root)
	_build_order(root)
	_build_bottom(root)
	_build_spells_popup(root)
	_build_features_popup(root)
	_build_inventory(root)
	_build_end_panel(root)


# --- building ---------------------------------------------------------------------

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
	_hp_bar.custom_minimum_size = Vector2(150, 14)
	_hp_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_hp_bar.modulate = Color(0.9, 0.3, 0.3)
	hp_row.add_child(_hp_bar)
	_hp_label = Label.new()
	hp_row.add_child(_hp_label)
	_xp_label = Label.new()
	_xp_label.modulate = Color(1.0, 0.9, 0.55)
	box.add_child(_xp_label)
	_slots_label = Label.new()
	_slots_label.modulate = Color(0.7, 0.8, 1.0)
	box.add_child(_slots_label)
	_resources_label = Label.new()
	_resources_label.modulate = Color(0.8, 1.0, 0.8)
	_resources_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_resources_label)
	_gold_label = Label.new()
	box.add_child(_gold_label)
	_floor_label = Label.new()
	box.add_child(_floor_label)
	_mode_label = Label.new()
	box.add_child(_mode_label)
	_turn_label = Label.new()
	_turn_label.modulate = Color(0.75, 0.85, 1.0)
	box.add_child(_turn_label)
	_hint_label = Label.new()
	_hint_label.modulate = Color(0.9, 0.7, 1.0)
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_hint_label)
	_level_up_button = _make_button("Level up available!", func() -> void: action_requested.emit("level_up"))
	_level_up_button.disabled = false
	_level_up_button.visible = false
	_level_up_button.modulate = Color(1.0, 0.95, 0.5)
	box.add_child(_level_up_button)


func _build_order(root: Control) -> void:
	_order_panel = PanelContainer.new()
	_order_panel.anchor_left = 1.0
	_order_panel.anchor_right = 1.0
	_order_panel.offset_left = -268
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
	_add_button(bar, "attack", "Attack [1]")
	_attack_picker = OptionButton.new()
	_attack_picker.focus_mode = Control.FOCUS_NONE
	_attack_picker.custom_minimum_size = Vector2(170, 0)
	_attack_picker.fit_to_longest_item = false
	_attack_picker.clip_text = true
	_attack_picker.tooltip_text = "Attack used by Attack and by clicking a monster"
	_attack_picker.item_selected.connect(_on_attack_picked)
	bar.add_child(_attack_picker)
	_add_button(bar, "spells", "Spells [Q]")
	_add_button(bar, "features", "Features [E]")
	_add_button(bar, "dash", "Dash [2]")
	_add_button(bar, "dodge", "Dodge [3]")
	_add_button(bar, "disengage", "Disengage [4]")
	_add_button(bar, "end_turn", "End Turn [Space]")
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(spacer)
	_add_button(bar, "inventory", "Inventory [Tab]")
	_add_button(bar, "short_rest", "Short rest [R]")
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
	var b := _make_button(text, func() -> void: _on_button(action))
	parent.add_child(b)
	_buttons[action] = b


func _make_button(text: String, handler: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.disabled = true
	b.pressed.connect(handler)
	return b


func _popup_panel(root: Control, title_text: String) -> Array:
	var panel := PanelContainer.new()
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = 8
	panel.offset_right = 8 + POPUP_WIDTH
	panel.offset_bottom = -(LOG_HEIGHT + 64)
	panel.offset_top = -(LOG_HEIGHT + 64)
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.visible = false
	root.add_child(panel)
	var outer := VBoxContainer.new()
	panel.add_child(outer)
	var header := HBoxContainer.new()
	outer.add_child(header)
	var title := Label.new()
	title.text = title_text
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close := _make_button("x", func() -> void: panel.visible = false)
	close.disabled = false
	header.add_child(close)
	var box := VBoxContainer.new()
	outer.add_child(box)
	return [panel, box]


func _build_spells_popup(root: Control) -> void:
	var parts := _popup_panel(root, "Spells (prepared)")
	_spells_panel = parts[0]
	_spells_box = parts[1]


func _build_features_popup(root: Control) -> void:
	var parts := _popup_panel(root, "Class features")
	_features_panel = parts[0]
	_features_box = parts[1]


func _build_inventory(root: Control) -> void:
	_inventory_panel = PanelContainer.new()
	_inventory_panel.anchor_left = 1.0
	_inventory_panel.anchor_right = 1.0
	_inventory_panel.offset_left = -468
	_inventory_panel.offset_right = -8
	_inventory_panel.offset_top = 60
	_inventory_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_inventory_panel.visible = false
	root.add_child(_inventory_panel)
	var margin := MarginContainer.new()
	for side: String in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 8)
	_inventory_panel.add_child(margin)
	var box := VBoxContainer.new()
	margin.add_child(box)
	var header := HBoxContainer.new()
	box.add_child(header)
	var title := Label.new()
	title.text = "Inventory [Tab]"
	title.add_theme_font_size_override("font_size", 18)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close := _make_button("x", func() -> void: _inventory_panel.visible = false)
	close.disabled = false
	header.add_child(close)
	_inv_gold = Label.new()
	box.add_child(_inv_gold)
	_inv_ac = Label.new()
	_inv_ac.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_inv_ac)
	_inv_weight = Label.new()
	box.add_child(_inv_weight)
	_inv_note = Label.new()
	_inv_note.modulate = WARN
	_inv_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_inv_note)
	var eq_title := Label.new()
	eq_title.text = "Equipment"
	box.add_child(eq_title)
	_inv_slots_box = VBoxContainer.new()
	box.add_child(_inv_slots_box)
	var items_title := Label.new()
	items_title.text = "Carried"
	box.add_child(items_title)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(440, 260)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_inv_items_box = VBoxContainer.new()
	_inv_items_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_inv_items_box)


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


# --- public -----------------------------------------------------------------------

## Adds lines to the combat log.
func append_log(lines: Array[String]) -> void:
	for line in lines:
		_log.add_text(line + "\n")


## Shows a message in the end panel (also used for load failures).
func show_end(title: String, text: String) -> void:
	_end_title.text = title
	_end_text.text = text
	_end_panel.visible = true


func toggle_inventory() -> void:
	_inventory_panel.visible = not _inventory_panel.visible
	_inventory_key = ""
	if _state != null:
		refresh(_state)


func is_inventory_open() -> bool:
	return _inventory_panel.visible


func toggle_spells() -> void:
	var show := not _spells_panel.visible
	close_popups()
	_spells_panel.visible = show
	_spells_key = ""
	if _state != null:
		refresh(_state)


func toggle_features() -> void:
	var show := not _features_panel.visible
	close_popups()
	_features_panel.visible = show
	_features_key = ""
	if _state != null:
		refresh(_state)


func is_popup_open() -> bool:
	return _spells_panel.visible or _features_panel.visible


## Closes the Spells / Features popups (not the inventory).
func close_popups() -> void:
	_spells_panel.visible = false
	_features_panel.visible = false


## Escape: closes the topmost HUD panel; false when nothing was open.
func close_top() -> bool:
	if is_popup_open():
		close_popups()
		return true
	if _inventory_panel.visible:
		_inventory_panel.visible = false
		return true
	return false


func refresh(state: ClientState) -> void:
	_state = state
	var sheet := state.sheet
	if sheet != null:
		_name_label.text = "%s - level %d %s" % [sheet.name, sheet.level, sheet.class_id.capitalize()]
		_hp_bar.max_value = sheet.max_hp
		_hp_bar.value = sheet.current_hp
		var hp_text := "HP %d / %d" % [sheet.current_hp, sheet.max_hp]
		if sheet.temp_hp > 0:
			hp_text += " +%d temp" % sheet.temp_hp
		if sheet.dead:
			hp_text += " (dead)"
		elif sheet.current_hp == 0:
			hp_text += " (stable)" if sheet.stable else " (dying %d/%d)" % [sheet.death_save_successes, sheet.death_save_failures]
		_hp_label.text = hp_text + "   AC %d" % sheet.armor_class()
		_xp_label.text = state.level_text()
		_slots_label.text = state.slots_text()
		_resources_label.text = state.resources_text()
		_gold_label.text = "Gold: %d" % state.gold()
	else:
		_name_label.text = "Connecting..."
		_xp_label.text = ""
		_slots_label.text = ""
		_resources_label.text = ""
		_gold_label.text = ""
	_slots_label.visible = not _slots_label.text.is_empty()
	_resources_label.visible = not _resources_label.text.is_empty()
	_floor_label.text = state.floor_label()
	_mode_label.text = state.mode_text()
	if state.is_my_turn():
		_turn_label.text = "Movement: %d tiles (%d ft)   Action: %s   Bonus: %s" % [
			state.movement_remaining, state.movement_remaining * GridMath.FEET_PER_TILE,
			"used" if state.action_used else "ready", "used" if state.bonus_action_used else "ready"]
	elif state.can_use_stairs():
		_turn_label.text = "You stand on the stairs."
	else:
		var chest := state.nearest_closed_chest()
		_turn_label.text = "A chest is within reach: click it to open." if not chest.is_empty() and state.can_open_chest(chest) else ""
	_hint_label.text = state.hint if state.is_targeting() else ""
	if state.is_targeting():
		_hint_label.text += " (Esc / right click cancels)"
	_hint_label.visible = not _hint_label.text.is_empty()
	_level_up_button.visible = state.has_level_up_offer()
	_level_up_button.disabled = not state.can_level_up()
	_level_up_button.text = "Level up available! (level %d)" % DictUtil.to_int(state.level_up_offer.get("new_level", 0), 0) \
		if state.can_level_up() else "Level up available after the fight"
	_refresh_order(state)
	_refresh_attack_picker(state)
	var my_action := state.can_take_action()
	_set_enabled("attack", state.can_attack())
	_set_enabled("spells", sheet != null and not sheet.spells_prepared.is_empty())
	_set_enabled("features", not state.feature_entries().is_empty())
	_set_enabled("dash", my_action)
	_set_enabled("dodge", my_action)
	_set_enabled("disengage", my_action)
	_set_enabled("end_turn", state.is_my_turn())
	_set_enabled("inventory", sheet != null)
	_set_enabled("use_stairs", state.can_use_stairs())
	_set_enabled("short_rest", state.can_short_rest())
	var stairs_button: Button = _buttons["use_stairs"]
	stairs_button.visible = state.on_stairs()
	stairs_button.text = state.stairs_label()
	stairs_button.tooltip_text = "Take the stairs [F]"
	var rest_button: Button = _buttons["short_rest"]
	rest_button.visible = state.on_stairs()
	if _spells_panel.visible:
		_refresh_spells(state)
	if _features_panel.visible:
		_refresh_features(state)
	if _inventory_panel.visible:
		_refresh_inventory(state)
	match state.mode:
		ClientState.Mode.GAME_OVER:
			show_end("Game over", "Your party has fallen. Permadeath: the delve starts again from floor 1.")
		ClientState.Mode.FLOOR_CLEARED:
			show_end("Floor cleared", "You reached the stairs of %s." % (state.floor_data.display_name if state.floor_data != null else state.cleared_floor_id))
		ClientState.Mode.SET_CLEARED:
			var set_title := state.set_name if not state.set_name.is_empty() else state.cleared_set_id
			var who := state.sheet.name if state.sheet != null else "You"
			var level := state.sheet.level if state.sheet != null else 1
			show_end("Set cleared", "%s conquered all %d floors of %s and reached the safe zone at level %d." % [who, state.floor_count, set_title, level])
		_:
			_end_panel.visible = false


# --- sections ---------------------------------------------------------------------

func _refresh_order(state: ClientState) -> void:
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
		var tags := state.status_tags(id)
		if not tags.is_empty():
			status += " [%s]" % ", ".join(tags)
		var hp := ""
		if int(e.get("hp", -1)) >= 0 and int(e.get("max_hp", -1)) > 0:
			hp = " %d/%d" % [int(e["hp"]), int(e["max_hp"])]
		lines.append("%s%s  [%d]%s%s" % [marker, state.display_name(id), int(state.initiatives.get(id, 0)), hp, status])
	_order_label.text = "\n".join(lines)


func _refresh_attack_picker(state: ClientState) -> void:
	var attacks := state.available_attacks()
	var labels: PackedStringArray = []
	for a in attacks:
		labels.append(state.attack_label(a))
	var key := "|".join(labels)
	if key != _attack_picker_key:
		_attack_picker_key = key
		_attack_picker.clear()
		for i in range(attacks.size()):
			_attack_picker.add_item(labels[i], i)
			_attack_picker.set_item_disabled(i, not state.attack_supply_error(attacks[i]).is_empty())
	if state.selected_attack < _attack_picker.item_count:
		_attack_picker.select(state.selected_attack)
	_attack_picker.disabled = attacks.is_empty()
	_attack_picker.tooltip_text = labels[state.selected_attack] if state.selected_attack < labels.size() else ""


func _refresh_spells(state: ClientState) -> void:
	var entries := state.spell_entries()
	var key := "%s|%s" % [str(entries), state.slots_text()]
	if key == _spells_key:
		return
	_spells_key = key
	_clear(_spells_box)
	if entries.is_empty():
		_spells_box.add_child(_note("No prepared spells."))
		return
	if not state.slots_text().is_empty():
		_spells_box.add_child(_note(state.slots_text()))
	for entry in entries:
		var row := HBoxContainer.new()
		_spells_box.add_child(row)
		var id := str(entry["id"])
		var level := int(entry["level"])
		var label := "%s (%s%s, %s)" % [str(entry["name"]), "cantrip" if level == 0 else ClientState.ordinal(level) + " level",
			", bonus" if bool(entry["bonus"]) else "", _range_text(int(entry["range_tiles"]), str(entry["target"]))]
		var slot_picker: OptionButton = null
		var slots: Array[int] = []
		slots.assign(entry["slots"])
		if level > 0 and slots.size() > 1:
			slot_picker = OptionButton.new()
			slot_picker.focus_mode = Control.FOCUS_NONE
			for s in slots:
				slot_picker.add_item("%s slot (%d)" % [ClientState.ordinal(s), state.sheet.slots_left(s)], s)
		var b := _make_button(label, func() -> void:
			var slot := slot_picker.get_selected_id() if slot_picker != null else 0
			_begin_cast(id, slot))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var error := str(entry["error"])
		b.disabled = not error.is_empty()
		if not bool(entry["supported"]):
			b.text += " - not castable yet"
			b.modulate = GREY
		b.tooltip_text = error if not error.is_empty() else "Cast %s" % str(entry["name"])
		row.add_child(b)
		if slot_picker != null:
			slot_picker.disabled = b.disabled
			row.add_child(slot_picker)


static func _range_text(tiles: int, target: String) -> String:
	if target == SpellDefinition.TARGET_SELF:
		return "self"
	if tiles <= 1:
		return "touch"
	return "%d ft" % (tiles * GridMath.FEET_PER_TILE)


func _refresh_features(state: ClientState) -> void:
	var entries := state.feature_entries()
	var key := str(entries)
	if key == _features_key:
		return
	_features_key = key
	_clear(_features_box)
	_lay_amount = null
	if entries.is_empty():
		_features_box.add_child(_note("No class features to use."))
		return
	for entry in entries:
		var id := str(entry["id"])
		var row := HBoxContainer.new()
		_features_box.add_child(row)
		var label := str(entry["name"])
		if int(entry["max"]) >= 0:
			label += " (%d/%d)" % [int(entry["remaining"]), int(entry["max"])]
		var b := _make_button(label, func() -> void: _begin_feature(id))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var error := str(entry["error"])
		b.disabled = not error.is_empty()
		b.tooltip_text = error
		row.add_child(b)
		if id == ClassDefinition.FEATURE_LAY_ON_HANDS:
			_lay_amount = SpinBox.new()
			_lay_amount.min_value = 1
			_lay_amount.max_value = maxi(1, int(entry["remaining"]))
			_lay_amount.value = maxi(1, mini(5, int(entry["remaining"])))
			_lay_amount.suffix = "HP"
			_lay_amount.focus_mode = Control.FOCUS_NONE
			_lay_amount.get_line_edit().focus_mode = Control.FOCUS_CLICK
			_lay_amount.editable = not b.disabled
			_lay_amount.tooltip_text = "Hit points to restore from the pool"
			row.add_child(_lay_amount)


func _refresh_inventory(state: ClientState) -> void:
	var sheet := state.sheet
	if sheet == null:
		return
	var key := "%s|%s|%s|%s|%s|%s" % [str(sheet.inventory), str(sheet.equipped), state.can_manage_equipment(),
		state.is_my_turn(), state.action_used, state.bonus_action_used]
	if key == _inventory_key:
		return
	_inventory_key = key
	_inv_gold.text = "Gold: %d gp" % state.gold()
	_inv_ac.text = state.ac_breakdown()
	_inv_weight.text = "Carried weight: %.1f lb" % state.carried_weight()
	var manage := state.can_manage_equipment()
	if state.in_encounter:
		_inv_note.text = "In combat: equipment is locked; potions work on your turn."
	elif not manage:
		_inv_note.text = "You cannot change equipment now."
	else:
		_inv_note.text = ""
	_inv_note.visible = not _inv_note.text.is_empty()
	_clear(_inv_slots_box)
	for slot in CharacterSheet.SLOTS:
		var row := HBoxContainer.new()
		_inv_slots_box.add_child(row)
		var held := sheet.equipped_item(slot)
		var icon_col := _icons.column_for_item(state.item_def(held)) if not held.is_empty() else -1
		row.add_child(_icon(icon_col))
		var l := Label.new()
		l.text = "%s: %s" % [ClientState.SLOT_NAMES.get(slot, slot), state.item_name(held) if not held.is_empty() else "(empty)"]
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		if not held.is_empty():
			var b := _make_button("Unequip", func() -> void: intent_requested.emit(state.unequip_intent(slot)))
			b.disabled = not manage
			row.add_child(b)
	_clear(_inv_items_box)
	var rows := state.inventory_rows()
	if rows.is_empty():
		_inv_items_box.add_child(_note("Nothing carried."))
	for r in rows:
		_inv_items_box.add_child(_item_row(state, r, manage))


func _item_row(state: ClientState, r: Dictionary, manage: bool) -> HBoxContainer:
	var row := HBoxContainer.new()
	var item := str(r["item"])
	row.add_child(_icon(_icons.column_for_item(state.item_def(item))))
	var name_label := Label.new()
	var held: Array[String] = []
	held.assign(r["equipped"])
	var text := ClientState.quantity_text(str(r["name"]), int(r["qty"]))
	if not held.is_empty():
		var names: PackedStringArray = []
		for s in held:
			names.append(str(ClientState.SLOT_NAMES.get(s, s)).to_lower())
		text += " (%s)" % ", ".join(names)
	name_label.text = text
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.clip_text = true
	row.add_child(name_label)
	var w := Label.new()
	w.text = "%.1f lb" % float(r["weight"])
	w.modulate = GREY
	row.add_child(w)
	if bool(r["usable"]):
		var use_error := state.use_item_error(item)
		var use := _make_button("Use", func() -> void: intent_requested.emit(state.use_item_intent(item)))
		use.disabled = not use_error.is_empty()
		use.tooltip_text = use_error
		row.add_child(use)
	var slots: Array[String] = []
	slots.assign(r["equip_slots"])
	for slot in slots:
		if held.has(slot):
			continue
		var label := "Wear" if slot == CharacterSheet.SLOT_ARMOR else ("Equip" if slot == CharacterSheet.SLOT_MAIN_HAND else "Off hand")
		var eq := _make_button(label, func() -> void: intent_requested.emit(state.equip_intent(item, slot)))
		eq.disabled = not manage
		eq.tooltip_text = "Equip in %s" % str(ClientState.SLOT_NAMES.get(slot, slot)).to_lower()
		row.add_child(eq)
	var drop := _make_button("Drop", func() -> void: intent_requested.emit(state.drop_item_intent(item, 1)))
	drop.disabled = not manage
	drop.tooltip_text = "Drop one (it is gone for good)"
	row.add_child(drop)
	return row


func _icon(column: int) -> TextureRect:
	var t := TextureRect.new()
	t.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.texture = _icons.atlas_texture(column) if _icons != null else null
	return t


func _note(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.modulate = GREY
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _clear(box: Container) -> void:
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()


# --- choices ----------------------------------------------------------------------

func _on_button(action: String) -> void:
	match action:
		"spells":
			toggle_spells()
		"features":
			toggle_features()
		"inventory":
			toggle_inventory()
		_:
			action_requested.emit(action)


func _on_attack_picked(index: int) -> void:
	if _state == null:
		return
	_state.cancel_targeting()
	_state.select_attack(index)
	state_changed.emit()


func _begin_cast(spell_id: String, slot_level: int) -> void:
	if _state == null:
		return
	close_popups()
	var intent := _state.begin_cast(spell_id, slot_level)
	if not intent.is_empty():
		intent_requested.emit(intent)
	state_changed.emit()


func _begin_feature(feature: String) -> void:
	if _state == null:
		return
	var amount := int(_lay_amount.value) if _lay_amount != null and feature == ClassDefinition.FEATURE_LAY_ON_HANDS else 0
	close_popups()
	var intent := _state.begin_feature(feature, amount)
	if not intent.is_empty():
		intent_requested.emit(intent)
	state_changed.emit()


func _set_enabled(action: String, on: bool) -> void:
	var b: Button = _buttons[action]
	b.disabled = not on

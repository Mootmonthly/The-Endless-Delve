class_name Hud
extends CanvasLayer
## Heads-up display for the GameScene, built in code:
## - character panel: name, class, level / XP, HP bar (+ temp HP), AC, spell
##   slots (pact slots marked), class resources (ki, sorcery points, channel
##   divinity, lay on hands pool, bardic inspiration with its die, rage,
##   action surge, ...), gold, floor, mode, movement / action (with the
##   "Attack 2/2" counter of Extra Attack) / bonus action / reaction, the
##   targeting hint, a "Level up available" button and the Companions line
##   (name, hp per companion on the sheet, with a Dismiss button while
##   exploring);
## - initiative order with status tags (dodging, raging, marked, ...),
##   conditions with their remaining duration and the concentration spell;
## - attack options row (only the character's): Reckless, Divine Smite slot,
##   Stunning Strike, Open Hand Technique;
## - action bar: Attack [1] with the attack picker (melee / thrown / ranged),
##   Spells [Q], Features [E], Dash [2], Dodge [3], Disengage [4],
##   End Turn [Space], Inventory [Tab], Short rest [R] and the stairs [F];
## - Spells popup (prepared spells, upcast slot choice per leveled spell, a
##   metamagic picker for sorcerers, a concentration warning, greyed out when
##   not castable now or not supported by the rules engine yet). While
##   exploring it lists the spells that work outside a fight (companions,
##   heals, temporary HP, restorations, Mage Armor) with their casting time
##   and a form picker for Find Familiar / Animate Dead; they cast at once on
##   yourself (no real-time wait for long casting times in M2). Features
##   popup (every usable feature with its cost and resource: Second Wind,
##   Action Surge, Rage / Frenzy, Lay on Hands with an amount, Bardic
##   Inspiration, ki features with their modes, Channel Divinity, Font of
##   Magic, Pact Weapon, and the bonus-action attacks);
## - Reactions popup (in and out of combat; also reachable from the pause
##   menu): one check box per trigger with the reactions of this character it
##   governs (opportunity attack, Shield, Uncanny Dodge, Counterspell, ...),
##   and one check box per reaction when a trigger governs several, sent as
##   the reaction_policy intent;
## - InventoryPanel (Tab): equipment slots, items with icon / qty / weight,
##   weapon properties (two-handed, light, versatile...) and Use / Equip /
##   Unequip / Drop, gold, carried weight and the AC breakdown;
## - combat log and the end-of-run panel.
##
## Reads a ClientState in refresh(). Spells / features / items call the
## state's begin_* helpers (targeting mode) and send ready intents through
## intent_requested; other choices leave as action_requested. Buttons never
## take keyboard focus, so the movement keys stay free for the map.

## "attack", "dash", "dodge", "disengage", "end_turn", "use_stairs", "short_rest", "stand",
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
const ALLY_TINT := Color(0.7, 1.0, 0.75)

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
var _companions_box: VBoxContainer
var _companions_key: String = ""
var _order_label: Label
var _order_panel: PanelContainer
var _log: RichTextLabel
var _buttons: Dictionary = {}  # action -> Button
var _attack_picker: OptionButton
var _attack_picker_key: String = ""
var _options_row: HBoxContainer
var _reckless_check: CheckBox
var _smite_picker: OptionButton
var _smite_key: String = ""
var _stun_check: CheckBox
var _technique_picker: OptionButton
var _end_panel: PanelContainer
var _end_title: Label
var _end_text: Label

var _spells_panel: PanelContainer
var _spells_box: VBoxContainer
var _spells_key: String = ""
var _reactions_panel: PanelContainer
var _reactions_box: VBoxContainer
var _reactions_key: String = ""
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
	_build_reactions_popup(root)
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
	_companions_box = VBoxContainer.new()
	_companions_box.modulate = ALLY_TINT
	_companions_box.visible = false
	box.add_child(_companions_box)


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
	_build_attack_options(bottom)
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
	_add_button(bar, "stand", "Stand up")
	_add_button(bar, "end_turn", "End Turn [Space]")
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(spacer)
	_add_button(bar, "reactions", "Reactions")
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


## Reckless / Smite / Stun / Technique: shown for the characters that have them.
func _build_attack_options(parent: Control) -> void:
	_options_row = HBoxContainer.new()
	_options_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_options_row.visible = false
	parent.add_child(_options_row)
	_reckless_check = CheckBox.new()
	_reckless_check.text = "Reckless"
	_reckless_check.focus_mode = Control.FOCUS_NONE
	_reckless_check.tooltip_text = "Reckless Attack: advantage on your first melee STR attack; attacks against you have advantage until your next turn"
	_reckless_check.toggled.connect(func(on: bool) -> void: _set_option("reckless", on))
	_options_row.add_child(_reckless_check)
	_smite_picker = OptionButton.new()
	_smite_picker.focus_mode = Control.FOCUS_NONE
	_smite_picker.tooltip_text = "Divine Smite on the next melee hit (the slot is spent only on a hit)"
	_smite_picker.item_selected.connect(func(i: int) -> void: _set_option("smite", _smite_picker.get_item_id(i)))
	_options_row.add_child(_smite_picker)
	_stun_check = CheckBox.new()
	_stun_check.text = "Stunning Strike"
	_stun_check.focus_mode = Control.FOCUS_NONE
	_stun_check.tooltip_text = "Spend 1 ki on the next melee hit: CON save or stunned"
	_stun_check.toggled.connect(func(on: bool) -> void: _set_option("stun", on))
	_options_row.add_child(_stun_check)
	_technique_picker = OptionButton.new()
	_technique_picker.focus_mode = Control.FOCUS_NONE
	_technique_picker.tooltip_text = "Open Hand Technique on Flurry of Blows hits"
	for t: String in ["", "prone", "push", "no_reactions"]:
		_technique_picker.add_item("Technique: none" if t.is_empty() else "Technique: %s" % t.replace("_", " "))
		_technique_picker.set_item_metadata(_technique_picker.item_count - 1, t)
	_technique_picker.item_selected.connect(func(i: int) -> void: _set_option("technique", str(_technique_picker.get_item_metadata(i))))
	_options_row.add_child(_technique_picker)


func _set_option(key: String, value: Variant) -> void:
	if _state == null:
		return
	_state.set_attack_option(key, value)
	state_changed.emit()


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
	var parts := _popup_panel(root, "Spells (prepared) [Q]")
	_spells_panel = parts[0]
	_spells_box = parts[1]


func _build_features_popup(root: Control) -> void:
	var parts := _popup_panel(root, "Class features")
	_features_panel = parts[0]
	_features_box = parts[1]


func _build_reactions_popup(root: Control) -> void:
	var parts := _popup_panel(root, "Reactions (automatic when checked)")
	_reactions_panel = parts[0]
	_reactions_box = parts[1]


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


func toggle_reactions() -> void:
	var show := not _reactions_panel.visible
	close_popups()
	_reactions_panel.visible = show
	_reactions_key = ""
	if _state != null:
		refresh(_state)


## Opens the Reactions popup (the pause menu's "Reactions" entry).
func open_reactions() -> void:
	if not _reactions_panel.visible:
		toggle_reactions()


func is_reactions_open() -> bool:
	return _reactions_panel.visible


func is_spells_open() -> bool:
	return _spells_panel.visible


func toggle_features() -> void:
	var show := not _features_panel.visible
	close_popups()
	_features_panel.visible = show
	_features_key = ""
	if _state != null:
		refresh(_state)


func is_popup_open() -> bool:
	return _spells_panel.visible or _features_panel.visible or _reactions_panel.visible


## Closes the Spells / Features popups (not the inventory).
func close_popups() -> void:
	_spells_panel.visible = false
	_features_panel.visible = false
	_reactions_panel.visible = false


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
		var counter := state.attack_counter_text()
		var action_text := "ready" if not state.action_used else ("%s left" % counter if not counter.is_empty() else "used")
		if not state.action_used and not counter.is_empty():
			action_text = "ready (%s)" % counter
		var bonus_text := "used" if state.bonus_action_used else "ready"
		if state.bonus_attacks_remaining > 0:
			bonus_text = "%d strike%s left" % [state.bonus_attacks_remaining, "" if state.bonus_attacks_remaining == 1 else "s"]
		_turn_label.text = "Movement: %d tiles (%d ft)   Action: %s   Bonus: %s   Reaction: %s" % [
			state.movement_remaining, state.movement_remaining * GridMath.FEET_PER_TILE,
			action_text, bonus_text, "used" if state.reaction_used else "ready"]
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
	_refresh_companions(state)
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
	var prone := state.is_my_turn() and state.has_condition(state.player_id, "prone")
	var stand_button: Button = _buttons["stand"]
	stand_button.visible = prone
	_set_enabled("stand", prone)
	_refresh_attack_options(state)
	_set_enabled("inventory", sheet != null)
	var reactions_button: Button = _buttons["reactions"]
	reactions_button.visible = ClientState.reaction_policy_supported()
	_set_enabled("reactions", sheet != null)
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
	if _reactions_panel.visible:
		_refresh_reactions(state)
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

## The Companions line and, while exploring, a Dismiss button per companion.
func _refresh_companions(state: ClientState) -> void:
	var entries := state.companion_entries()
	var can_dismiss := state.can_dismiss_companion()
	var key := "%s|%s" % [str(entries), can_dismiss]
	if key == _companions_key:
		return
	_companions_key = key
	_clear(_companions_box)
	_companions_box.visible = not entries.is_empty()
	if entries.is_empty():
		return
	var title := Label.new()
	title.text = state.companions_text()
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_companions_box.add_child(title)
	for c in entries:
		var cid := str(c["id"])
		if cid.is_empty():
			continue
		var row := HBoxContainer.new()
		_companions_box.add_child(row)
		var l := Label.new()
		l.text = "%s (%s)" % [str(c["name"]), state.spell_name(str(c["spell"]))]
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		var b := _make_button("Dismiss companion", func() -> void: intent_requested.emit(state.dismiss_companion_intent(cid)))
		b.disabled = not can_dismiss
		b.tooltip_text = "Send %s away for good" % str(c["name"]) if can_dismiss else "Only while exploring"
		row.add_child(b)

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


func _refresh_attack_options(state: ClientState) -> void:
	var kinds := state.attack_option_kinds()
	_options_row.visible = not kinds.is_empty() and state.in_encounter
	var attack_button: Button = _buttons["attack"]
	var counter := state.attack_counter_text()
	attack_button.text = "Attack [1]" if counter.is_empty() else "%s [1]" % counter
	if not _options_row.visible:
		return
	_reckless_check.visible = kinds.has("reckless")
	_reckless_check.set_pressed_no_signal(bool(state.attack_options.get("reckless", false)))
	_stun_check.visible = kinds.has("stun")
	_stun_check.set_pressed_no_signal(bool(state.attack_options.get("stun", false)))
	_stun_check.disabled = state.sheet == null or state.sheet.class_resource("ki") < 1
	_technique_picker.visible = kinds.has("technique")
	var technique := str(state.attack_options.get("technique", ""))
	for i in range(_technique_picker.item_count):
		if str(_technique_picker.get_item_metadata(i)) == technique:
			_technique_picker.select(i)
	_smite_picker.visible = kinds.has("smite")
	if kinds.has("smite"):
		var levels := state.smite_levels()
		var key := "%s|%d" % [str(levels), int(state.attack_options.get("smite", 0))]
		if key != _smite_key:
			_smite_key = key
			_smite_picker.clear()
			_smite_picker.add_item("No smite", 0)
			for lvl in levels:
				_smite_picker.add_item("Smite: %s slot (%d left)" % [ClientState.ordinal(lvl), state.sheet.slots_left(lvl)], lvl)
			var idx := _smite_picker.get_item_index(int(state.attack_options.get("smite", 0)))
			_smite_picker.select(maxi(0, idx))


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
	var all_entries := state.spell_entries()
	var exploring := not state.in_encounter
	var entries: Array[Dictionary] = []
	for entry in all_entries:
		if not exploring or bool(entry["out_of_combat"]):
			entries.append(entry)
	var key := "%s|%s|%s|%s|%s" % [str(entries), state.slots_text(), str(state.concentration), state.resources_text(), exploring]
	if key == _spells_key:
		return
	_spells_key = key
	_clear(_spells_box)
	if all_entries.is_empty():
		_spells_box.add_child(_note("No prepared spells."))
		return
	if not state.slots_text().is_empty():
		_spells_box.add_child(_note(state.slots_text()))
	if exploring:
		var hidden := all_entries.size() - entries.size()
		_spells_box.add_child(_note("Out of combat: spells cast on yourself at once, long casting times included.%s" % (
			" %d combat spell%s hidden." % [hidden, "" if hidden == 1 else "s"] if hidden > 0 else "")))
		if entries.is_empty():
			_spells_box.add_child(_note("None of your prepared spells works outside a fight."))
	for entry in entries:
		var row := HBoxContainer.new()
		_spells_box.add_child(row)
		var id := str(entry["id"])
		var level := int(entry["level"])
		var meta_picker: OptionButton = null
		var meta_opts := state.metamagic_options(id)
		if not meta_opts.is_empty():
			meta_picker = OptionButton.new()
			meta_picker.focus_mode = Control.FOCUS_NONE
			meta_picker.add_item("No metamagic")
			meta_picker.set_item_metadata(0, "")
			for m in meta_opts:
				meta_picker.add_item("%s (%d SP)" % [str(m["name"]), int(m["cost"])])
				var mi := meta_picker.item_count - 1
				meta_picker.set_item_metadata(mi, str(m["id"]))
				meta_picker.set_item_disabled(mi, not str(m["error"]).is_empty())
				meta_picker.set_item_tooltip(mi, str(m["error"]))
		var label := "%s (%s%s, %s)" % [str(entry["name"]), "cantrip" if level == 0 else ClientState.ordinal(level) + " level",
			", bonus" if bool(entry["bonus"]) else "", _range_text(int(entry["range_tiles"]), str(entry["target"]))]
		if exploring or not ClientState.is_quick_casting_time(str(entry["casting_time"])) or bool(entry["ritual"]):
			label += " - %s" % str(entry["casting_time_text"])
		var slot_picker: OptionButton = null
		var slots: Array[int] = []
		slots.assign(entry["slots"])
		if level > 0 and slots.size() > 1:
			slot_picker = OptionButton.new()
			slot_picker.focus_mode = Control.FOCUS_NONE
			for s in slots:
				slot_picker.add_item("%s slot (%d)" % [ClientState.ordinal(s), state.sheet.slots_left(s)], s)
		var spell := state.spell_def(id)
		var form_picker: OptionButton = null
		var forms := DictUtil.to_string_array(spell.raw_effect.get("forms", [])) if spell != null and exploring else ([] as Array[String])
		if forms.size() > 1:
			form_picker = OptionButton.new()
			form_picker.focus_mode = Control.FOCUS_NONE
			form_picker.tooltip_text = "Form of the companion"
			var default_form := str(spell.raw_effect.get("monster", ""))
			for f in forms:
				form_picker.add_item(state.monster_name(f))
				form_picker.set_item_metadata(form_picker.item_count - 1, f)
				if f == default_form:
					form_picker.select(form_picker.item_count - 1)
		if spell != null and spell.is_area():
			label += ", %d ft %s" % [spell.area_size_ft, spell.area_shape]
		if spell != null and spell.concentration:
			label += ", concentration"
		var warning := state.concentration_warning(id)
		if not warning.is_empty():
			label += " (!)"
		var b := _make_button(label, func() -> void:
			var slot := slot_picker.get_selected_id() if slot_picker != null else 0
			var meta: Array[String] = []
			if meta_picker != null and not str(meta_picker.get_selected_metadata()).is_empty():
				meta.append(str(meta_picker.get_selected_metadata()))
			var form := str(form_picker.get_selected_metadata()) if form_picker != null and form_picker.selected >= 0 else ""
			_begin_cast(id, slot, meta, form))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var error := str(entry["error"])
		b.disabled = not error.is_empty()
		if not bool(entry["supported"]):
			b.text += " - not castable yet"
			b.modulate = GREY
		b.tooltip_text = error if not error.is_empty() else "Cast %s" % str(entry["name"])
		if not warning.is_empty():
			b.tooltip_text += "\n" + warning
		row.add_child(b)
		if slot_picker != null:
			slot_picker.disabled = b.disabled
			slot_picker.tooltip_text = "Upcast with a higher slot"
			row.add_child(slot_picker)
		if meta_picker != null:
			meta_picker.disabled = b.disabled
			row.add_child(meta_picker)
		if form_picker != null:
			form_picker.disabled = b.disabled
			row.add_child(form_picker)


static func _range_text(tiles: int, target: String) -> String:
	if target == SpellDefinition.TARGET_SELF:
		return "self"
	if tiles <= 1:
		return "touch"
	return "%d ft" % (tiles * GridMath.FEET_PER_TILE)


func _refresh_features(state: ClientState) -> void:
	var entries := state.feature_entries()
	var key := "%s|%s" % [str(entries), state.slots_text()]
	if key == _features_key:
		return
	_features_key = key
	_clear(_features_box)
	_lay_amount = null
	if entries.is_empty():
		_features_box.add_child(_note("No class features to use."))
		return
	var resources := state.resources_text()
	if not resources.is_empty():
		_features_box.add_child(_note(resources))
	for entry in entries:
		var id := str(entry["id"])
		var row := HBoxContainer.new()
		_features_box.add_child(row)
		var label := str(entry["name"])
		if int(entry["max"]) >= 0:
			label += " (%s %d/%d)" % [ClientState.feature_name(str(entry["resource"])) if str(entry["resource"]) != id else "uses",
				int(entry["remaining"]), int(entry["max"])]
		label += " - %s" % {"action": "action", "bonus": "bonus action", "free": "free"}.get(str(entry["cost"]), "")
		var error := str(entry["error"])
		var modes: Array[String] = []
		modes.assign(entry["modes"])
		if id == "font_of_magic":
			_font_of_magic_row(state, row, label, error)
			continue
		if modes.is_empty():
			var b := _make_button(label, func() -> void: _begin_feature(id))
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.disabled = not error.is_empty()
			b.tooltip_text = error
			row.add_child(b)
		else:
			var title := Label.new()
			title.text = label
			title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(title)
			for m in modes:
				var mode := m
				var mb := _make_button(mode.capitalize(), func() -> void: _begin_feature(id, mode))
				var merr := state.feature_error(id, mode)
				mb.disabled = not merr.is_empty()
				mb.tooltip_text = merr
				row.add_child(mb)
		if id == ClassDefinition.FEATURE_LAY_ON_HANDS:
			_lay_amount = SpinBox.new()
			_lay_amount.min_value = 1
			_lay_amount.max_value = maxi(1, int(entry["remaining"]))
			_lay_amount.value = maxi(1, mini(5, int(entry["remaining"])))
			_lay_amount.suffix = "HP"
			_lay_amount.focus_mode = Control.FOCUS_NONE
			_lay_amount.get_line_edit().focus_mode = Control.FOCUS_CLICK
			_lay_amount.editable = error.is_empty()
			_lay_amount.tooltip_text = "Hit points to restore from the pool"
			row.add_child(_lay_amount)


## One check box per trigger (checked = react automatically, "auto") naming
## the character's reactions it governs; a trigger with several of them gets
## one indented check box per reaction too.
func _refresh_reactions(state: ClientState) -> void:
	var entries := state.reaction_entries()
	var key := str(entries)
	if key == _reactions_key:
		return
	_reactions_key = key
	_clear(_reactions_box)
	_reactions_box.add_child(_note("Reactions resolve on their own when checked; settings are kept between fights and floors."))
	for entry in entries:
		var trigger := str(entry["trigger"])
		var mine: Array[Dictionary] = []
		mine.assign(entry["reactions"])
		var names: PackedStringArray = []
		for r in mine:
			names.append(str(r["name"]))
		var c := CheckBox.new()
		c.text = "%s: %s" % [str(entry["label"]), ", ".join(names) if not names.is_empty() else "none of yours yet"]
		c.focus_mode = Control.FOCUS_NONE
		c.button_pressed = bool(entry["on"])
		c.tooltip_text = "Trigger: %s" % trigger
		if names.is_empty():
			c.modulate = GREY
		c.toggled.connect(func(on: bool) -> void: intent_requested.emit(state.reaction_toggle_intent(trigger, "", on)))
		_reactions_box.add_child(c)
		if mine.size() < 2:
			continue
		for r in mine:
			var rid := str(r["id"])
			var sub := CheckBox.new()
			sub.text = "    %s" % str(r["name"])
			sub.focus_mode = Control.FOCUS_NONE
			sub.button_pressed = bool(r["on"])
			sub.toggled.connect(func(on: bool) -> void: intent_requested.emit(state.reaction_toggle_intent(trigger, rid, on)))
			_reactions_box.add_child(sub)


## Font of Magic: a picker of create / convert choices and a Use button.
func _font_of_magic_row(state: ClientState, row: HBoxContainer, label: String, error: String) -> void:
	var title := Label.new()
	title.text = label
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	var picker := OptionButton.new()
	picker.focus_mode = Control.FOCUS_NONE
	for o in state.font_of_magic_options():
		picker.add_item(str(o["label"]))
		var i := picker.item_count - 1
		picker.set_item_metadata(i, o)
		picker.set_item_disabled(i, not str(o["error"]).is_empty())
		picker.set_item_tooltip(i, str(o["error"]))
	row.add_child(picker)
	var use := _make_button("Use", func() -> void:
		var o: Dictionary = picker.get_selected_metadata() if picker.selected >= 0 else {}
		if not o.is_empty():
			_begin_feature("font_of_magic", str(o["mode"]), int(o["slot_level"])))
	use.disabled = not error.is_empty() or picker.item_count == 0
	use.tooltip_text = error
	picker.disabled = use.disabled
	row.add_child(use)


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
	var props: Array[String] = []
	props.assign(r.get("properties", []))
	if not props.is_empty():
		text += " [%s]" % ", ".join(props)
	name_label.text = text
	name_label.tooltip_text = text
	name_label.mouse_filter = Control.MOUSE_FILTER_PASS
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
		"reactions":
			toggle_reactions()
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


func _begin_cast(spell_id: String, slot_level: int, metamagic: Array[String] = [], form: String = "") -> void:
	if _state == null:
		return
	close_popups()
	var intent := _state.begin_cast(spell_id, slot_level, metamagic, {"form": form} if not form.is_empty() else {})
	if not intent.is_empty():
		intent_requested.emit(intent)
	state_changed.emit()


func _begin_feature(feature: String, mode: String = "", slot_level: int = 0) -> void:
	if _state == null:
		return
	var amount := int(_lay_amount.value) if _lay_amount != null and feature == ClassDefinition.FEATURE_LAY_ON_HANDS else 0
	close_popups()
	var intent := _state.begin_feature(feature, amount, mode, slot_level)
	if not intent.is_empty():
		intent_requested.emit(intent)
	state_changed.emit()


func _set_enabled(action: String, on: bool) -> void:
	var b: Button = _buttons[action]
	b.disabled = not on

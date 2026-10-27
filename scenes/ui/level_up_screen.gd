class_name LevelUpScreen
extends CanvasLayer
## Modal level-up screen for one LEVEL_UP_AVAILABLE offer, edited through a
## LevelUpDraft: header "Level N!", hit points (Average +X vs Roll d(die) +
## CON), the ability score improvement when offered (+2 to one or +1 to two,
## live preview of scores and modifiers, capped at 20), cantrips and spells
## to learn with a search box, leveled spells grouped by spell level (spells
## the rules engine cannot cast yet are greyed out), the prepared-spell picker
## for prepared casters (count shown), one section per progression choice
## (subclass with its description, fighting style, expertise from proficient
## skills, invocations, metamagic, option features such as Dragon Ancestor,
## extra skills, round C's spell choices: Magical Secrets, Mystic Arcanum,
## Pact of the Tome cantrips, Book of Ancient Secrets rituals, Spell Mastery
## and Signature Spells, each option named with its spell level, plus a note
## when a choice only applies with another pick; counts shown, every option
## with its rules text and a "not yet modelled" badge when the engine does
## not model it), and the
## features gained as cards (data/features descriptions, "implemented" /
## "not yet modelled", subclass features marked). Confirm stays disabled until
## the draft is valid; it emits `confirmed(choices)` and waits (set_waiting)
## until the GameScene closes it on the CHARACTER_STATE with leveled_to, or
## shows the server's error. "Later" (or Escape) emits `dismissed`; the HUD's
## "Level up available" button reopens it. Built in code from _ready().

signal confirmed(choices: Dictionary)
signal dismissed

const LAYER := 30
const PANEL_SIZE := Vector2(720, 560)
const GREY := Color(0.6, 0.6, 0.6)
const WARN := Color(1.0, 0.65, 0.45)
const NOTE := Color(0.78, 0.78, 0.82)
const BADGE_OK := Color(0.55, 0.9, 0.55)
const BADGE_TODO := Color(1.0, 0.75, 0.4)
## One-line notes for class features the rules engine implements (else the id is shown).
const FEATURE_NOTES: Dictionary[String, String] = {
	"second_wind": "Bonus action: regain 1d10 + your level in hit points; back after a short rest.",
	"rage": "Bonus action: extra melee damage and resistance to bludgeoning, piercing and slashing.",
	"lay_on_hands": "Action: restore hit points from a pool of 5 x your level by touch.",
	"bardic_inspiration": "Bonus action: give an ally a die to add to an attack roll.",
	"sneak_attack": "Extra damage once per turn with a finesse or ranged weapon when you have advantage or an ally is next to the target.",
	"martial_arts": "Unarmed strikes use 1d4 + the better of STR and DEX; a bonus unarmed strike after the Attack action.",
	"unarmored_defense_con": "Without armor your AC is 10 + DEX + CON (a shield still counts).",
	"unarmored_defense_wis": "Without armor or shield your AC is 10 + DEX + WIS.",
	"spellcasting": "You can cast spells from your class list.",
	"pact_magic": "Your spell slots come back after a short rest.",
}

var draft: LevelUpDraft = null
var class_name_text: String = ""

var _blocker: ColorRect
var _panel: PanelContainer
var _title: Label
var _hp_average: CheckBox
var _hp_roll: CheckBox
var _asi_box: VBoxContainer
var _asi_two: CheckBox
var _asi_split: CheckBox
var _asi_first: OptionButton
var _asi_second: OptionButton
var _asi_preview: Label
var _search: LineEdit
var _cantrip_header: Label
var _cantrip_box: VBoxContainer
var _spell_header: Label
var _spell_box: VBoxContainer
var _prepared_header: Label
var _prepared_box: VBoxContainer
var _features_box: VBoxContainer
var _choices_section: VBoxContainer
var _problems: Label
var _confirm: Button
var _later: Button
var _learn_section: VBoxContainer
var _prepared_section: VBoxContainer
var _features_section: VBoxContainer
var _waiting: bool = false
var _syncing: bool = false
var _built: bool = false


func _ready() -> void:
	layer = LAYER
	_build_ui()
	visible = false


func is_open() -> bool:
	return visible


## Opens the screen for an offer (LevelUp.choices) and the character's current sheet.
func open(offer: Dictionary, sheet: CharacterSheet, content: Dictionary = {}) -> void:
	_build_ui()
	draft = LevelUpDraft.new(offer, sheet, content)
	class_name_text = sheet.class_id.capitalize() if sheet != null else ""
	_waiting = false
	_search.text = ""
	_title.text = "Level %d!%s" % [draft.new_level(), ("  " + class_name_text) if not class_name_text.is_empty() else ""]
	var bonus := DictUtil.to_int((offer.get("hp", {}) as Dictionary).get("bonus", 0), 0) if typeof(offer.get("hp")) == TYPE_DICTIONARY else 0
	_hp_average.text = "Average: +%d HP%s" % [draft.average_hp() + bonus, (" (incl. +%d from features)" % bonus) if bonus > 0 else ""]
	_hp_roll.text = "Roll: d%d %s CON" % [draft.hit_die(), "%+d" % draft.con_mod()]
	_hp_roll.disabled = not draft.may_roll()
	_asi_box.visible = draft.asi_offered()
	if draft.asi_offered():
		_set_asi_default()
	_rebuild_lists()
	_fill_choices()
	_fill_feature_cards()
	_features_section.visible = not draft.feature_cards().is_empty()
	visible = true
	_refresh()


func close() -> void:
	visible = false
	_waiting = false


## While waiting for the server's answer to Confirm, everything is locked.
func set_waiting(on: bool, error: String = "") -> void:
	_waiting = on
	_refresh()
	if not error.is_empty():
		_problems.text = "The server refused: %s" % error


## Release the search box's focus before it eats Escape, so Escape closes the screen.
func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("cancel") and _search != null and _search.has_focus():
		_search.release_focus()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("cancel"):
		_on_later()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("confirm") and not _confirm.disabled:
		_on_confirm()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey:
		get_viewport().set_input_as_handled()  # the map behind gets no keys


# --- UI -------------------------------------------------------------------------

func _build_ui() -> void:
	if _built:
		return
	_built = true
	_blocker = ColorRect.new()
	_blocker.color = Color(0, 0, 0, 0.55)
	_blocker.set_anchors_preset(Control.PRESET_FULL_RECT)
	_blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_blocker)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_panel = PanelContainer.new()
	_panel.custom_minimum_size = PANEL_SIZE
	center.add_child(_panel)
	var margin := MarginContainer.new()
	for side: String in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 16)
	_panel.add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	margin.add_child(root)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 28)
	root.add_child(_title)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, PANEL_SIZE.y - 150)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 10)
	scroll.add_child(body)

	# Hit points.
	body.add_child(_heading("Hit points"))
	var hp_group := ButtonGroup.new()
	var hp_row := HBoxContainer.new()
	body.add_child(hp_row)
	_hp_average = CheckBox.new()
	_hp_average.button_group = hp_group
	_hp_average.button_pressed = true
	_hp_average.toggled.connect(func(on: bool) -> void: _on_hp(LevelUpDraft.HP_AVERAGE, on))
	hp_row.add_child(_hp_average)
	_hp_roll = CheckBox.new()
	_hp_roll.button_group = hp_group
	_hp_roll.toggled.connect(func(on: bool) -> void: _on_hp(LevelUpDraft.HP_ROLL, on))
	hp_row.add_child(_hp_roll)

	# Ability score improvement.
	_asi_box = VBoxContainer.new()
	body.add_child(_asi_box)
	_asi_box.add_child(_heading("Ability score improvement"))
	var mode_row := HBoxContainer.new()
	_asi_box.add_child(mode_row)
	var asi_group := ButtonGroup.new()
	_asi_two = CheckBox.new()
	_asi_two.text = "+2 to one ability"
	_asi_two.button_group = asi_group
	_asi_two.toggled.connect(_on_asi_mode_toggled)
	mode_row.add_child(_asi_two)
	_asi_split = CheckBox.new()
	_asi_split.text = "+1 to two abilities"
	_asi_split.button_group = asi_group
	_asi_split.toggled.connect(_on_asi_mode_toggled)
	mode_row.add_child(_asi_split)
	var pick_row := HBoxContainer.new()
	_asi_box.add_child(pick_row)
	_asi_first = _ability_picker()
	pick_row.add_child(_asi_first)
	_asi_second = _ability_picker()
	pick_row.add_child(_asi_second)
	_asi_preview = Label.new()
	_asi_box.add_child(_asi_preview)

	# Progression choices (subclass, fighting style, expertise, ...).
	_choices_section = VBoxContainer.new()
	_choices_section.add_theme_constant_override("separation", 6)
	body.add_child(_choices_section)

	# Spells to learn.
	_learn_section = VBoxContainer.new()
	body.add_child(_learn_section)
	var search_row := HBoxContainer.new()
	_learn_section.add_child(search_row)
	search_row.add_child(_label("Search spells"))
	_search = LineEdit.new()
	_search.placeholder_text = "name..."
	_search.custom_minimum_size = Vector2(220, 0)
	_search.text_changed.connect(func(_t: String) -> void: _rebuild_lists())
	search_row.add_child(_search)
	_cantrip_header = _heading("Cantrips")
	_learn_section.add_child(_cantrip_header)
	_cantrip_box = VBoxContainer.new()
	_learn_section.add_child(_cantrip_box)
	_spell_header = _heading("Spells")
	_learn_section.add_child(_spell_header)
	_spell_box = VBoxContainer.new()
	_learn_section.add_child(_spell_box)

	# Prepared spells.
	_prepared_section = VBoxContainer.new()
	body.add_child(_prepared_section)
	_prepared_header = _heading("Prepared spells")
	_prepared_section.add_child(_prepared_header)
	_prepared_box = VBoxContainer.new()
	_prepared_section.add_child(_prepared_box)

	# Features.
	_features_section = VBoxContainer.new()
	body.add_child(_features_section)
	_features_section.add_child(_heading("Features gained"))
	_features_box = VBoxContainer.new()
	_features_box.add_theme_constant_override("separation", 6)
	_features_section.add_child(_features_box)

	_problems = Label.new()
	_problems.modulate = WARN
	_problems.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_problems.custom_minimum_size = Vector2(PANEL_SIZE.x - 40, 0)
	root.add_child(_problems)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	root.add_child(buttons)
	_later = Button.new()
	_later.text = "Later"
	_later.tooltip_text = "Close; the HUD's Level up button reopens this screen"
	_later.pressed.connect(_on_later)
	buttons.add_child(_later)
	_confirm = Button.new()
	_confirm.text = "Confirm"
	_confirm.pressed.connect(_on_confirm)
	buttons.add_child(_confirm)


func _ability_picker() -> OptionButton:
	var opt := OptionButton.new()
	for a in range(Ability.COUNT):
		opt.add_item(Ability.abbreviation(a), a)
	opt.item_selected.connect(func(_i: int) -> void: _on_asi_changed())
	return opt


func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	return l


func _heading(text: String) -> Label:
	var l := _label(text)
	l.add_theme_font_size_override("font_size", 18)
	return l


func _set_asi_default() -> void:
	var auto := LevelUpDraft.first_valid(draft.offer, draft.sheet, draft.content)
	_syncing = true
	if auto.asi_mode == LevelUpDraft.ASI_SPLIT:
		_asi_split.button_pressed = true
	else:
		_asi_two.button_pressed = true
	if auto.asi_abilities.size() > 0:
		_asi_first.select(auto.asi_abilities[0])
	if auto.asi_abilities.size() > 1:
		_asi_second.select(auto.asi_abilities[1])
	else:
		_asi_second.select((_asi_first.selected + 1) % Ability.COUNT)
	_syncing = false
	_on_asi_changed()


func _rebuild_lists() -> void:
	if draft == null:
		return
	var filter := _search.text.strip_edges().to_lower()
	_fill_learn(_cantrip_box, draft.cantrip_options(), true, filter)
	_fill_learn(_spell_box, draft.spell_options(), false, filter)
	_learn_section.visible = draft.cantrips_needed() > 0 or draft.spells_needed() > 0
	_cantrip_header.visible = draft.cantrips_needed() > 0
	_cantrip_box.visible = draft.cantrips_needed() > 0
	_spell_header.visible = draft.spells_needed() > 0
	_spell_box.visible = draft.spells_needed() > 0
	_fill_prepared()
	_refresh()


func _fill_learn(box: VBoxContainer, options: Array[String], cantrips: bool, filter: String) -> void:
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()
	var chosen := draft.learn_cantrips if cantrips else draft.learn_spells
	var sorted := options.duplicate()
	if not cantrips:
		sorted.sort_custom(func(a: String, b: String) -> bool:
			return draft.spell_level(a) < draft.spell_level(b) or (draft.spell_level(a) == draft.spell_level(b) and options.find(a) < options.find(b)))
	var last_level := -1
	for id in sorted:
		var spell_label := draft.spell_name(id)
		if not filter.is_empty() and not spell_label.to_lower().contains(filter) and not chosen.has(id):
			continue
		if not cantrips and draft.spell_level(id) != last_level:
			last_level = draft.spell_level(id)
			var group := _label("%s-level spells" % ClientState.ordinal(last_level))
			group.modulate = NOTE
			box.add_child(group)
		var c := CheckBox.new()
		c.text = spell_label if cantrips else "%s (%s level)" % [spell_label, ClientState.ordinal(draft.spell_level(id))]
		if not draft.is_supported(id):
			c.text += " - not castable yet"
			c.modulate = GREY
		c.button_pressed = chosen.has(id)
		c.set_meta("spell", id)
		c.set_meta("cantrip", cantrips)
		c.toggled.connect(func(on: bool) -> void: _on_learn_toggled(id, on))
		box.add_child(c)


func _fill_prepared() -> void:
	for child in _prepared_box.get_children():
		_prepared_box.remove_child(child)
		child.queue_free()
	_prepared_section.visible = draft.is_prepared_caster()
	if not draft.is_prepared_caster():
		return
	for id in draft.prepare_options():
		var c := CheckBox.new()
		c.text = "%s (%s level)" % [draft.spell_name(id), ClientState.ordinal(draft.spell_level(id))]
		if not draft.is_supported(id):
			c.text += " - not castable yet"
			c.modulate = GREY
		c.button_pressed = draft.prepared.has(id)
		c.set_meta("spell", id)
		c.toggled.connect(func(on: bool) -> void: _on_prepared_toggled(id, on))
		_prepared_box.add_child(c)


## One card per feature gained: name, badges, rules text (data/features).
func _fill_feature_cards() -> void:
	_clear(_features_box)
	for card in draft.feature_cards():
		var box := VBoxContainer.new()
		_features_box.add_child(box)
		var head := HBoxContainer.new()
		box.add_child(head)
		var name_label := _label(str(card["name"]))
		name_label.add_theme_font_size_override("font_size", 16)
		head.add_child(name_label)
		if bool(card["subclass"]):
			var sub := _label("subclass")
			sub.modulate = NOTE
			head.add_child(sub)
		var badge := _label("implemented" if bool(card["implemented"]) else "not yet modelled")
		badge.modulate = BADGE_OK if bool(card["implemented"]) else BADGE_TODO
		head.add_child(badge)
		var text := str(card["description"])
		if text.is_empty():
			text = FEATURE_NOTES.get(str(card["id"]), "")
		if not text.is_empty():
			box.add_child(_description(text))


## One section per progression choice: heading with the count, then each
## option (radio for a single pick, check boxes otherwise) with its rules text.
func _fill_choices() -> void:
	_clear(_choices_section)
	for entry in draft.choice_entries():
		var count := draft.choice_count(entry)
		var section := VBoxContainer.new()
		section.set_meta("choice", entry)
		_choices_section.add_child(section)
		var heading := _heading("%s (choose %d)" % [draft.choice_title(entry), count])
		heading.set_meta("heading", true)
		section.add_child(heading)
		var note := draft.choice_note(entry)
		if not note.is_empty():
			section.add_child(_description(note))
		var group: ButtonGroup = ButtonGroup.new() if count == 1 else null
		if group != null:
			group.allow_unpress = true
		for option in DictUtil.to_string_array(entry.get("options", [])):
			var c := CheckBox.new()
			c.text = draft.option_label(entry, option)
			if not draft.option_implemented(entry, option):
				c.text += " - not yet modelled"
				c.modulate = GREY
			c.button_group = group
			c.button_pressed = draft.picks_for(entry).has(option)
			c.set_meta("option", option)
			var e := entry
			var o := option
			c.toggled.connect(func(on: bool) -> void: _on_choice_toggled(e, o, on))
			section.add_child(c)
			var text := draft.option_description(entry, option)
			if not text.is_empty():
				section.add_child(_description(text))


func _description(text: String) -> Label:
	var l := _label(text)
	l.modulate = NOTE
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(PANEL_SIZE.x - 80, 0)
	return l


func _clear(box: Container) -> void:
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()


func _refresh() -> void:
	if draft == null or _confirm == null:
		return
	_syncing = true
	_cantrip_header.text = "Cantrips to learn: %d (%d chosen)" % [draft.cantrips_needed(), draft.learn_cantrips.size()]
	_spell_header.text = "Spells to learn: %d (%d chosen)" % [draft.spells_needed(), draft.learn_spells.size()]
	_prepared_header.text = "Prepared spells: %d / %d (cantrips are always prepared)" % [draft.prepared.size(), draft.prepared_count()]
	for box: VBoxContainer in [_cantrip_box, _spell_box]:
		for child in box.get_children():
			var c := child as CheckBox
			if c == null:
				continue  # a spell-level heading
			var id := str(c.get_meta("spell"))
			var cantrip := bool(c.get_meta("cantrip"))
			var chosen := draft.learn_cantrips if cantrip else draft.learn_spells
			var full := chosen.size() >= (draft.cantrips_needed() if cantrip else draft.spells_needed())
			c.set_pressed_no_signal(chosen.has(id))
			c.disabled = _waiting or (not chosen.has(id) and (full or not draft.may_pick(id, cantrip)))
	for child in _prepared_box.get_children():
		var c := child as CheckBox
		var id := str(c.get_meta("spell"))
		c.set_pressed_no_signal(draft.prepared.has(id))
		c.disabled = _waiting or (not draft.prepared.has(id) and draft.prepared.size() >= draft.prepared_count())
	for section in _choices_section.get_children():
		var entry: Dictionary = section.get_meta("choice", {})
		var picked := draft.picks_for(entry)
		var full := picked.size() >= draft.choice_count(entry)
		for child in section.get_children():
			var c := child as CheckBox
			if c == null:
				continue
			var o := str(c.get_meta("option"))
			c.set_pressed_no_signal(picked.has(o))
			c.disabled = _waiting or (not picked.has(o) and full and draft.choice_count(entry) > 1)
	_asi_second.visible = _asi_split.button_pressed
	_asi_preview.text = _asi_preview_text()
	var problems := draft.problems()
	_problems.text = "Waiting for the server..." if _waiting else "\n".join(problems)
	_confirm.disabled = _waiting or not problems.is_empty()
	_later.disabled = _waiting
	_syncing = false


func _asi_preview_text() -> String:
	var after := draft.preview_scores()
	var parts: PackedStringArray = []
	for a in range(Ability.COUNT):
		var before := draft.current_score(a)
		if after[a] != before:
			parts.append("%s %d (%+d) -> %d (%+d)" % [Ability.abbreviation(a), before, Ability.modifier(before), after[a], Ability.modifier(after[a])])
		else:
			parts.append("%s %d (%+d)" % [Ability.abbreviation(a), before, Ability.modifier(before)])
	return "   ".join(parts)


# --- handlers ---------------------------------------------------------------------

func _on_hp(mode: String, on: bool) -> void:
	if on and draft != null:
		draft.set_hp_mode(mode)
		_refresh()


func _on_asi_mode_toggled(on: bool) -> void:
	if on:
		_on_asi_changed()


func _on_asi_changed() -> void:
	if _syncing or draft == null:
		return
	if _asi_split.button_pressed:
		draft.set_asi_split(_asi_first.get_selected_id(), _asi_second.get_selected_id())
	else:
		draft.set_asi_plus_two(_asi_first.get_selected_id())
	_refresh()


func _on_learn_toggled(id: String, on: bool) -> void:
	if _syncing or draft == null:
		return
	draft.toggle_learn(id, on)
	_fill_prepared()
	_refresh()


func _on_choice_toggled(entry: Dictionary, option: String, on: bool) -> void:
	if _syncing or draft == null:
		return
	draft.toggle_choice(entry, option, on)
	_refresh()


func _on_prepared_toggled(id: String, on: bool) -> void:
	if _syncing or draft == null:
		return
	draft.toggle_prepared(id, on)
	_refresh()


func _on_confirm() -> void:
	if draft == null or not draft.is_valid() or _waiting:
		return
	_waiting = true
	_refresh()
	confirmed.emit(draft.to_choices())


func _on_later() -> void:
	if _waiting:
		return
	close()
	dismissed.emit()

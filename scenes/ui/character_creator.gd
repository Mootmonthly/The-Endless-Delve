class_name CharacterCreator
extends Control
## Character creation screen: name, any of the twelve SRD classes, SRD
## ancestry, ability scores by a method (standard array or rolled values,
## each used once, or 27-point buy with a live points-remaining label; see
## CharacterDraft), class skill picks
## and a live preview (scores, HP, AC with the starting armor, every attack
## with ranges, prepared spells and slots, features and the starting kit).
## Level-1 progression: the subclass a cleric / sorcerer / warlock starts with
## (name and description) and the creation choices (fighting style,
## expertise from the chosen skills, Dragon Ancestor, ...) as pickers with
## the rules text of each option; they are sent explicitly to the builder.
## Start stays disabled until the CharacterDraft is valid; pressing it emits
## character_created with the finished level 1 sheet.
##
## Layout (fits 1280x720 and up; the panel fills the height and is centred):
## title over two columns. The left column (name / class / ancestry, class
## and subclass text, score method and scores, Reroll) scrolls. The right
## column keeps "Suggested scores for this class", then "Start the delve" and
## "Settings", then the problems list at its top, always visible; below them
## skills, creation choices and the preview scroll.
##
## The whole UI is built in code from _ready(); every control is reachable
## with the keyboard (Tab / arrows / Enter), no mouse needed. Escape
## (open_settings) opens the settings on the first press even while the name
## field has focus: _input() releases the field's focus first, so the key
## reaches Main's _unhandled_input instead of being eaten by the LineEdit.

signal character_created(sheet: CharacterSheet)
## The Settings button was pressed (Main opens the SettingsMenu).
signal settings_requested

const UNASSIGNED_LABEL := "--"

var draft: CharacterDraft = CharacterDraft.new()

var _classes: Array[ClassDefinition] = []
var _ancestries: Array[AncestryDefinition] = []
var _name_edit: LineEdit
var _class_option: OptionButton
var _ancestry_option: OptionButton
var _score_options: Array[OptionButton] = []
var _method_option: OptionButton
var _method_info: Label
var _points_label: Label
var _reroll_button: Button
var _suggest_button: Button
var _settings_button: Button
var _left_scroll: ScrollContainer
var _right_scroll: ScrollContainer
## Score menu item index -> value (UNASSIGNED first for pool methods).
var _menu_values: Array[int] = []
var _menu_key: String = ""
## Clock-seeded dice for Roll (client-side; online servers will roll themselves).
var _rng: Rng = null
var _skill_box: VBoxContainer
var _skill_checks: Dictionary = {}  # Skill.Type -> CheckBox
var _skill_header: Label
var _class_info: Label
var _subclass_info: Label
var _choices_box: VBoxContainer
var _choices_key: String = ""
var _preview: Label
var _problems: Label
var _start_button: Button
var _syncing: bool = false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_classes = CharacterDraft.ordered_classes(ContentLoader.load_classes())
	_ancestries = CharacterDraft.sorted_ancestries(ContentLoader.load_ancestries())
	if _rng == null:
		_rng = Rng.new(CharacterCreator.clock_seed())
	_build_ui()
	if not _classes.is_empty():
		draft.set_class(_classes[0])
	if not _ancestries.is_empty():
		draft.set_ancestry(_ancestries[0])
	draft.auto_assign()
	_rebuild_skills()
	_refresh()
	if is_inside_tree():
		_name_edit.grab_focus()


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.06, 0.09)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Full-height panel, centred horizontally at its minimum width.
	var outer := MarginContainer.new()
	outer.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side: String in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		outer.add_theme_constant_override(side, 16)
	add_child(outer)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	outer.add_child(row)
	var panel := PanelContainer.new()
	panel.size_flags_vertical = Control.SIZE_FILL
	row.add_child(panel)
	var margin := MarginContainer.new()
	for side: String in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 16)
	panel.add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)

	var title := Label.new()
	title.text = "The Endless Delve - New Character"
	title.add_theme_font_size_override("font_size", 26)
	root.add_child(title)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 28)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(columns)
	_left_scroll = _scroll()
	_left_scroll.name = "LeftScroll"
	columns.add_child(_left_scroll)
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(380, 0)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_left_scroll.add_child(left)
	var right := VBoxContainer.new()
	right.name = "RightColumn"
	right.custom_minimum_size = Vector2(440, 0)
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_child(right)

	# Name, class, ancestry.
	var form := GridContainer.new()
	form.columns = 2
	left.add_child(form)
	form.add_child(_label("Name"))
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Your adventurer's name"
	_name_edit.max_length = CharacterDraft.MAX_NAME_LENGTH
	_name_edit.custom_minimum_size = Vector2(240, 0)
	_name_edit.text_changed.connect(_on_name_changed)
	_name_edit.text_submitted.connect(_on_name_submitted)
	form.add_child(_name_edit)
	form.add_child(_label("Class"))
	_class_option = OptionButton.new()
	for def in _classes:
		_class_option.add_item(def.display_name)
	_class_option.item_selected.connect(_on_class_selected)
	form.add_child(_class_option)
	form.add_child(_label("Ancestry"))
	_ancestry_option = OptionButton.new()
	for def in _ancestries:
		_ancestry_option.add_item(def.display_name)
	_ancestry_option.item_selected.connect(_on_ancestry_selected)
	form.add_child(_ancestry_option)

	_class_info = _wrapped(Color(0.8, 0.8, 0.85))
	left.add_child(_class_info)
	_subclass_info = _wrapped(Color(0.85, 0.8, 1.0))
	left.add_child(_subclass_info)

	# Ability scores: method, explanation, one menu per ability, Reroll.
	left.add_child(_heading("Ability scores"))
	var method_row := GridContainer.new()
	method_row.columns = 2
	left.add_child(method_row)
	method_row.add_child(_label("Method"))
	_method_option = OptionButton.new()
	_method_option.name = "ScoreMethod"
	for m in CharacterDraft.METHODS:
		_method_option.add_item(CharacterDraft.METHOD_LABELS[m])
	_method_option.item_selected.connect(_on_method_selected)
	method_row.add_child(_method_option)
	_method_info = _wrapped(Color(0.8, 0.8, 0.85))
	left.add_child(_method_info)
	_points_label = _label("")
	_points_label.name = "PointsRemaining"
	left.add_child(_points_label)
	var scores := GridContainer.new()
	scores.columns = 2
	left.add_child(scores)
	for ability in range(Ability.COUNT):
		scores.add_child(_label(Ability.name_of(ability)))
		var opt := OptionButton.new()
		opt.custom_minimum_size = Vector2(120, 0)
		opt.item_selected.connect(_on_score_selected.bind(ability))
		scores.add_child(opt)
		_score_options.append(opt)
	_reroll_button = Button.new()
	_reroll_button.name = "Reroll"
	_reroll_button.text = "Reroll (4d6, drop lowest)"
	_reroll_button.pressed.connect(reroll)
	left.add_child(_reroll_button)

	# Right column, fixed part: suggestion, start, settings, problems.
	_suggest_button = Button.new()
	_suggest_button.name = "Suggest"
	_suggest_button.text = "Suggested scores for this class"
	_suggest_button.pressed.connect(_on_suggest_pressed)
	right.add_child(_suggest_button)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	right.add_child(actions)
	_start_button = Button.new()
	_start_button.name = "Start"
	_start_button.text = "Start the delve"
	_start_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_start_button.pressed.connect(_on_start_pressed)
	actions.add_child(_start_button)
	_settings_button = Button.new()
	_settings_button.text = "Settings"
	_settings_button.pressed.connect(settings_requested.emit)
	actions.add_child(_settings_button)
	_problems = _wrapped(Color(1.0, 0.65, 0.45))
	right.add_child(_problems)

	# Right column, scrolling part: skills, creation choices, preview.
	_right_scroll = _scroll()
	_right_scroll.name = "RightScroll"
	right.add_child(_right_scroll)
	var details := VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_right_scroll.add_child(details)
	_skill_header = _heading("Skills")
	details.add_child(_skill_header)
	_skill_box = VBoxContainer.new()
	details.add_child(_skill_box)
	_choices_box = VBoxContainer.new()
	details.add_child(_choices_box)
	details.add_child(_heading("Preview"))
	_preview = Label.new()
	_preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_preview.custom_minimum_size = Vector2(400, 0)
	_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_child(_preview)


## A vertical-only ScrollContainer that fills its column and scrolls to the
## focused control (keyboard navigation).
func _scroll() -> ScrollContainer:
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	sc.follow_focus = true
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return sc


func _wrapped(color: Color) -> Label:
	var l := Label.new()
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(360, 0)
	l.modulate = color
	return l


## A seed from the wall clock and the tick counter (for Roll).
static func clock_seed() -> int:
	return int(Time.get_unix_time_from_system() * 1000.0) ^ Time.get_ticks_usec()


## Uses `rng` for Roll instead of the clock-seeded one (tests); call before _ready().
func use_rng(rng: Rng) -> void:
	_rng = rng


## Score menu item index -> standard-array value (index 0 is unassigned).
static func score_for_index(index: int) -> int:
	var values := AbilityScores.standard_array()
	if index <= 0 or index > values.size():
		return CharacterDraft.UNASSIGNED
	return values[index - 1]


static func index_for_score(score: int) -> int:
	return AbilityScores.standard_array().find(score) + 1


func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	return l


func _heading(text: String) -> Label:
	var l := _label(text)
	l.add_theme_font_size_override("font_size", 18)
	return l


func _rebuild_skills() -> void:
	for child in _skill_box.get_children():
		_skill_box.remove_child(child)
		child.queue_free()
	_skill_checks.clear()
	if draft.class_def == null:
		return
	for skill in draft.class_def.skill_choices:
		var box := CheckBox.new()
		box.text = "%s (%s)" % [Skill.name_of(skill), Ability.abbreviation(Skill.ability_for(skill))]
		box.button_pressed = draft.skills.has(skill)
		box.toggled.connect(_on_skill_toggled.bind(skill))
		_skill_box.add_child(box)
		_skill_checks[skill] = box


## Creation choices: one picker per entry (an OptionButton for a single pick,
## check boxes otherwise), rebuilt when the entries change.
func _rebuild_choices() -> void:
	var d := draft.creation_draft()
	var entries := d.choice_entries()
	var key := "%s|%s" % [str(entries), str(draft.creation_picks)]
	if key == _choices_key:
		return
	_choices_key = key
	for child in _choices_box.get_children():
		_choices_box.remove_child(child)
		child.queue_free()
	for entry in entries:
		var count := d.choice_count(entry)
		_choices_box.add_child(_heading("%s (choose %d)" % [d.choice_title(entry), count]))
		var picked := d.picks_for(entry)
		var opts := DictUtil.to_string_array(entry.get("options", []))
		if count == 1:
			var opt := OptionButton.new()
			opt.add_item("-- choose --")
			opt.set_item_metadata(0, "")
			for o in opts:
				var label := d.option_label(entry, o)
				if not d.option_implemented(entry, o):
					label += " (not yet modelled)"
				opt.add_item(label)
				opt.set_item_metadata(opt.item_count - 1, o)
				opt.set_item_tooltip(opt.item_count - 1, d.option_description(entry, o))
				if picked.has(o):
					opt.select(opt.item_count - 1)
			var e := entry
			opt.item_selected.connect(func(i: int) -> void: _on_creation_choice(e, str(opt.get_item_metadata(i))))
			_choices_box.add_child(opt)
			if not picked.is_empty():
				var desc := Label.new()
				desc.text = d.option_description(entry, picked[0])
				desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				desc.custom_minimum_size = Vector2(360, 0)
				desc.modulate = Color(0.8, 0.8, 0.85)
				_choices_box.add_child(desc)
		else:
			for o in opts:
				var c := CheckBox.new()
				c.text = d.option_label(entry, o)
				c.tooltip_text = d.option_description(entry, o)
				c.button_pressed = picked.has(o)
				c.disabled = not picked.has(o) and picked.size() >= count
				var e := entry
				var option := o
				c.toggled.connect(func(on: bool) -> void:
					if not _syncing:
						draft.toggle_creation_choice(e, option, on)
						_refresh())
				_choices_box.add_child(c)


func _on_creation_choice(entry: Dictionary, option: String) -> void:
	if _syncing:
		return
	if option.is_empty():
		for o in DictUtil.to_string_array(draft.creation_picks.get(LevelUpDraft.choice_key(entry), [])):
			draft.toggle_creation_choice(entry, o, false)
	else:
		draft.toggle_creation_choice(entry, option, true)
	_refresh()


func _refresh() -> void:
	_syncing = true
	var cls := draft.class_def
	if cls != null:
		_class_option.select(_classes.find(cls))
		_class_info.text = cls.description
	if draft.ancestry != null:
		_ancestry_option.select(_ancestries.find(draft.ancestry))
	_refresh_scores()
	var sub := draft.subclass_info()
	_subclass_info.text = "%s: %s" % [str(sub["name"]), str(sub["description"])] if not sub.is_empty() else ""
	_subclass_info.visible = not sub.is_empty()
	_rebuild_choices()
	var needed := draft.skills_needed()
	_skill_header.text = "Skills (choose %d, %d chosen)" % [needed, draft.skills.size()]
	for skill: int in _skill_checks.keys():
		var box: CheckBox = _skill_checks[skill]
		box.set_pressed_no_signal(draft.skills.has(skill))
		box.disabled = not draft.skills.has(skill) and draft.skills.size() >= needed
	_preview.text = _preview_text()
	var problems := draft.problems()
	_problems.text = "\n".join(problems)
	_problems.visible = not problems.is_empty()
	_start_button.disabled = not problems.is_empty()
	_syncing = false


## Method menu, explanation, points label, Reroll and the six score menus.
func _refresh_scores() -> void:
	_method_option.select(maxi(CharacterDraft.METHODS.find(draft.method), 0))
	var point_buy := draft.method == CharacterDraft.METHOD_POINT_BUY
	var values: Array[int] = []
	if not point_buy:
		values.append(CharacterDraft.UNASSIGNED)
	values.append_array(draft.score_choices())
	var key := "%s|%s" % [draft.method, str(values)]
	if key != _menu_key:
		_menu_key = key
		_menu_values = values
		for opt in _score_options:
			opt.clear()
			for v in values:
				if v == CharacterDraft.UNASSIGNED:
					opt.add_item(UNASSIGNED_LABEL)
				elif point_buy:
					opt.add_item("%d (%d pt)" % [v, AbilityScores.point_buy_cost(v)])
				else:
					opt.add_item(str(v))
	for ability in range(Ability.COUNT):
		var opt := _score_options[ability]
		opt.select(_menu_values.find(draft.assigned[ability]))
		for i in range(_menu_values.size()):
			opt.set_item_disabled(i, point_buy and not draft.point_buy_affordable(ability, _menu_values[i]))
	_method_info.text = _method_text()
	_points_label.visible = point_buy
	if point_buy:
		var remaining := draft.point_buy_remaining()
		_points_label.text = "Points remaining: %d of %d" % [remaining, AbilityScores.POINT_BUY_BUDGET]
		_points_label.modulate = Color(1.0, 0.65, 0.45) if remaining < 0 else Color(0.75, 1.0, 0.75)
	_reroll_button.visible = draft.method == CharacterDraft.METHOD_ROLL


func _method_text() -> String:
	match draft.method:
		CharacterDraft.METHOD_POINT_BUY:
			return ("Spend up to %d points; every score is %d-%d before ancestry bonuses. "
				+ "8 costs 0, each point to 13 costs 1, 14 costs 7, 15 costs 9.") % [
				AbilityScores.POINT_BUY_BUDGET, CharacterDraft.POINT_BUY_MIN, CharacterDraft.POINT_BUY_MAX]
		CharacterDraft.METHOD_ROLL:
			var rolled := "Rolled (4d6, drop the lowest): %s." % CharacterCreator._join(draft.score_pool())
			var to_place := draft.unassigned_values()
			if not to_place.is_empty():
				rolled += " Still to place: %s." % CharacterCreator._join(to_place)
			return rolled + ("\nOffline you may reroll as often as you like; online servers will restrict "
				+ "rolled scores (see the design document).")
	var text := "Assign %s, each once." % CharacterCreator._join(AbilityScores.standard_array())
	var left := draft.unassigned_values()
	if not left.is_empty():
		text += " Still to place: %s." % CharacterCreator._join(left)
	return text


static func _join(values: Array[int]) -> String:
	var parts: PackedStringArray = []
	for v in values:
		parts.append(str(v))
	return ", ".join(parts)


func _preview_text() -> String:
	var p := draft.preview()
	if p.is_empty():
		return "Choose a class."
	var parts: PackedStringArray = []
	var final_scores: Array[int] = []
	final_scores.assign(p["scores"])
	for ability in range(Ability.COUNT):
		var score := final_scores[ability]
		parts.append("%s %d (%+d)" % [Ability.abbreviation(ability), score, Ability.modifier(score)])
	var lines: PackedStringArray = []
	lines.append("  ".join(parts))
	lines.append("HP %d    AC %d (%s)    Speed %d ft" % [int(p["hp"]), int(p["ac"]), str(p["armor"]), int(p["speed"])])
	if draft.ancestry != null:
		lines.append("%s, speed %d ft." % [draft.ancestry.display_name, draft.ancestry.speed])
	lines.append("")
	lines.append("Attacks:")
	for a: String in p["attacks"]:
		lines.append("  " + a)
	var spells: Array = p["spells"]
	if not spells.is_empty():
		lines.append("Spells prepared%s:" % ((" (slots: %s)" % str(p["slots"])) if not str(p["slots"]).is_empty() else ""))
		for sp: String in spells:
			lines.append("  " + sp)
	elif not str(p["slots"]).is_empty():
		lines.append("Spell slots: %s" % str(p["slots"]))
	var features: Array = p["features"]
	if not features.is_empty():
		var names: PackedStringArray = []
		for f: String in features:
			names.append(f)
		lines.append("Features: %s" % ", ".join(names))
	var kit: Array = p["kit"]
	var kit_names: PackedStringArray = []
	for k: String in kit:
		kit_names.append(k)
	lines.append("Kit: %s; %d gold" % [", ".join(kit_names), int(p["gold"])])
	return "\n".join(lines)


## The name field would swallow the first Escape (LineEdit ends editing on
## ui_cancel); drop its focus so Escape reaches Main and opens the settings.
func _input(event: InputEvent) -> void:
	if _name_edit != null and _name_edit.has_focus() and event.is_action_pressed("open_settings"):
		_name_edit.release_focus()


func _on_name_changed(text: String) -> void:
	draft.character_name = text
	_refresh()


func _on_name_submitted(_text: String) -> void:
	if draft.is_valid():
		_on_start_pressed()


func _on_class_selected(index: int) -> void:
	if _syncing or index < 0 or index >= _classes.size():
		return
	draft.set_class(_classes[index])
	draft.auto_assign()
	_rebuild_skills()
	_refresh()


func _on_ancestry_selected(index: int) -> void:
	if _syncing or index < 0 or index >= _ancestries.size():
		return
	draft.set_ancestry(_ancestries[index])
	_refresh()


func _on_score_selected(index: int, ability: int) -> void:
	if _syncing or index < 0 or index >= _menu_values.size():
		return
	draft.assign(ability, _menu_values[index])
	_refresh()


## Score method menu (also callable directly): Roll rolls first if nothing
## was rolled yet.
func _on_method_selected(index: int) -> void:
	if _syncing or index < 0 or index >= CharacterDraft.METHODS.size():
		return
	var m := CharacterDraft.METHODS[index]
	if m == CharacterDraft.METHOD_ROLL and draft.rolled_values.size() != Ability.COUNT:
		reroll()
		return
	draft.set_method(m)
	_refresh()


## Rolls six new values, suggests an assignment and refreshes (the Reroll
## button). Offline rerolls are unlimited.
func reroll() -> void:
	if _rng == null:
		_rng = Rng.new(CharacterCreator.clock_seed())
	draft.roll_scores(_rng)
	draft.auto_assign()
	_refresh()


func _on_suggest_pressed() -> void:
	draft.auto_assign()
	_refresh()


func _on_skill_toggled(on: bool, skill: int) -> void:
	if _syncing:
		return
	draft.toggle_skill(skill, on)
	_refresh()


func _on_start_pressed() -> void:
	if not draft.is_valid():
		_refresh()
		return
	var sheet := draft.build_sheet()
	if sheet != null:
		character_created.emit(sheet)

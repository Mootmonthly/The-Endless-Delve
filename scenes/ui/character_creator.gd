class_name CharacterCreator
extends Control
## Character creation screen: name, wave-1 class, SRD ancestry, standard-array
## scores (each value used once), class skill picks and a live preview.
## Start stays disabled until the CharacterDraft is valid; pressing it emits
## character_created with the finished level 1 sheet.
##
## The whole UI is built in code from _ready(); every control is reachable
## with the keyboard (Tab / arrows / Enter), no mouse needed.

signal character_created(sheet: CharacterSheet)

const UNASSIGNED_LABEL := "--"

var draft: CharacterDraft = CharacterDraft.new()

var _classes: Array[ClassDefinition] = []
var _ancestries: Array[AncestryDefinition] = []
var _name_edit: LineEdit
var _class_option: OptionButton
var _ancestry_option: OptionButton
var _score_options: Array[OptionButton] = []
var _skill_box: VBoxContainer
var _skill_checks: Dictionary = {}  # Skill.Type -> CheckBox
var _skill_header: Label
var _class_info: Label
var _preview: Label
var _problems: Label
var _start_button: Button
var _syncing: bool = false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_classes = CharacterDraft.wave_1_classes(ContentLoader.load_classes())
	_ancestries = CharacterDraft.sorted_ancestries(ContentLoader.load_ancestries())
	_build_ui()
	if not _classes.is_empty():
		draft.set_class(_classes[0])
	if not _ancestries.is_empty():
		draft.set_ancestry(_ancestries[0])
	draft.auto_assign()
	_rebuild_skills()
	_refresh()
	_name_edit.grab_focus()


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.06, 0.09)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side: String in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 20)
	panel.add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	var title := Label.new()
	title.text = "The Endless Delve - New Character"
	title.add_theme_font_size_override("font_size", 26)
	root.add_child(title)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 32)
	root.add_child(columns)
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(360, 0)
	columns.add_child(left)
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(360, 0)
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

	_class_info = Label.new()
	_class_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_class_info.custom_minimum_size = Vector2(360, 0)
	_class_info.modulate = Color(0.8, 0.8, 0.85)
	left.add_child(_class_info)

	# Standard array.
	left.add_child(_heading("Ability scores (standard array: 15, 14, 13, 12, 10, 8)"))
	var scores := GridContainer.new()
	scores.columns = 2
	left.add_child(scores)
	for ability in range(Ability.COUNT):
		scores.add_child(_label(Ability.name_of(ability)))
		var opt := OptionButton.new()
		opt.add_item(UNASSIGNED_LABEL)
		for value in AbilityScores.standard_array():
			opt.add_item(str(value))
		opt.item_selected.connect(_on_score_selected.bind(ability))
		scores.add_child(opt)
		_score_options.append(opt)
	var suggest := Button.new()
	suggest.text = "Suggested scores for this class"
	suggest.pressed.connect(_on_suggest_pressed)
	left.add_child(suggest)

	# Skills, preview, start.
	_skill_header = _heading("Skills")
	right.add_child(_skill_header)
	_skill_box = VBoxContainer.new()
	right.add_child(_skill_box)
	right.add_child(_heading("Preview"))
	_preview = Label.new()
	_preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_preview.custom_minimum_size = Vector2(360, 0)
	right.add_child(_preview)
	_problems = Label.new()
	_problems.modulate = Color(1.0, 0.65, 0.45)
	_problems.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_problems.custom_minimum_size = Vector2(360, 0)
	right.add_child(_problems)
	_start_button = Button.new()
	_start_button.text = "Start the delve"
	_start_button.pressed.connect(_on_start_pressed)
	right.add_child(_start_button)


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


func _refresh() -> void:
	_syncing = true
	var cls := draft.class_def
	if cls != null:
		_class_option.select(_classes.find(cls))
		_class_info.text = cls.description
	if draft.ancestry != null:
		_ancestry_option.select(_ancestries.find(draft.ancestry))
	for ability in range(Ability.COUNT):
		var opt := _score_options[ability]
		opt.select(CharacterCreator.index_for_score(draft.assigned[ability]))
	var needed := draft.skills_needed()
	_skill_header.text = "Skills (choose %d, %d chosen)" % [needed, draft.skills.size()]
	for skill: int in _skill_checks.keys():
		var box: CheckBox = _skill_checks[skill]
		box.set_pressed_no_signal(draft.skills.has(skill))
		box.disabled = not draft.skills.has(skill) and draft.skills.size() >= needed
	_preview.text = _preview_text()
	var problems := draft.problems()
	_problems.text = "\n".join(problems)
	_start_button.disabled = not problems.is_empty()
	_syncing = false


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
	lines.append("HP %d    AC %d    Speed %d ft" % [int(p["hp"]), int(p["ac"]), int(p["speed"])])
	lines.append("%s: %+d to hit, %s %s" % [str(p["attack_name"]), int(p["to_hit"]), str(p["damage"]), str(p["damage_type"])])
	if draft.ancestry != null:
		lines.append("%s, speed %d ft." % [draft.ancestry.display_name, draft.ancestry.speed])
	return "\n".join(lines)


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
	if _syncing:
		return
	draft.assign(ability, CharacterCreator.score_for_index(index))
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

extends TestCase
## CharacterCreator built off-tree (_ready() called by hand): the layout keeps
## Start at the top of the right column directly under "Suggested scores for
## this class", outside any ScrollContainer, with both columns' long content
## in ScrollContainers; the score method menu (standard array, point buy with
## its points-remaining label, roll with Reroll) drives the CharacterDraft.
## The on-screen check (Start inside a 1280x720 viewport for every class, and
## Tab reaching Start) needs a running SceneTree; see the session report.


func _creator(seed_value: int = 4242) -> CharacterCreator:
	var packed: PackedScene = load("res://scenes/ui/character_creator.tscn")
	var c := packed.instantiate() as CharacterCreator
	c.use_rng(Rng.new(seed_value))
	c._ready()
	return c


func _has_scroll_ancestor(node: Node, stop: Node) -> bool:
	var p := node.get_parent()
	while p != null and p != stop:
		if p is ScrollContainer:
			return true
		p = p.get_parent()
	return false


func _fill_and_choose(c: CharacterCreator) -> void:
	c._name_edit.text = "Brann"
	c._on_name_changed("Brann")
	for skill: int in c._skill_checks.keys():
		c._on_skill_toggled(true, skill)
	c.draft.auto_choose()
	c._refresh()


func test_start_sits_under_suggest_at_the_top_of_the_right_column() -> void:
	var c := _creator()
	var right := c._start_button.get_parent().get_parent()
	assert_eq(str(right.name), "RightColumn")
	assert_eq(right.get_child(0), c._suggest_button, "Suggested scores first")
	assert_eq(c._start_button.get_parent(), right.get_child(1), "Start directly under it")
	assert_eq(c._start_button.get_parent().get_child(0), c._start_button, "Start before Settings")
	assert_eq(c._start_button.get_parent().get_child(1), c._settings_button)
	assert_eq(right.get_child(2), c._problems, "then the problems list")
	assert_eq(right.get_child(3), c._right_scroll, "then the scrolling details")
	assert_false(_has_scroll_ancestor(c._start_button, c), "Start never scrolls away")
	assert_false(_has_scroll_ancestor(c._suggest_button, c))
	for node: Control in [c._skill_box, c._choices_box, c._preview]:
		assert_true(_has_scroll_ancestor(node, c), "%s scrolls" % node.get_class())
	for node: Control in [c._name_edit, c._method_option, c._score_options[5], c._reroll_button]:
		assert_true(_has_scroll_ancestor(node, c), "left column content scrolls")
	assert_true(c._left_scroll.follow_focus and c._right_scroll.follow_focus, "keyboard focus scrolls into view")
	assert_eq(c._left_scroll.horizontal_scroll_mode, ScrollContainer.SCROLL_MODE_DISABLED)
	assert_eq(c._start_button.focus_mode, Control.FOCUS_ALL, "Start takes keyboard focus")
	# Tree order is the default Tab order: Start comes right after the scores.
	var order: Array[Control] = []
	_collect_focusable(c, order)
	var start_at := order.find(c._start_button)
	assert_eq(order[start_at - 1], c._suggest_button, "Tab from Suggested reaches Start")
	assert_true(order.find(c._score_options[5]) < start_at, "after the score menus")
	c.free()


func _collect_focusable(node: Node, out: Array[Control]) -> void:
	for child in node.get_children():
		if child is Control and (child as Control).focus_mode == Control.FOCUS_ALL:
			out.append(child as Control)
		_collect_focusable(child, out)


func test_standard_array_menus_by_default() -> void:
	var c := _creator()
	assert_eq(c.draft.method, CharacterDraft.METHOD_STANDARD)
	assert_eq(c._method_option.selected, 0)
	assert_eq(c._method_option.item_count, 3)
	assert_eq(c._score_options[0].item_count, 7, "-- plus six values")
	assert_eq(c._score_options[0].get_item_text(1), "15")
	assert_false(c._points_label.visible)
	assert_false(c._reroll_button.visible)
	assert_has(c._method_info.text, "15, 14, 13, 12, 10, 8")
	_fill_and_choose(c)
	assert_false(c._start_button.disabled, c._problems.text)
	c.free()


func test_point_buy_menus_and_live_points_label() -> void:
	var c := _creator()
	_fill_and_choose(c)
	c._on_method_selected(CharacterDraft.METHODS.find(CharacterDraft.METHOD_POINT_BUY))
	assert_eq(c.draft.method, CharacterDraft.METHOD_POINT_BUY)
	assert_true(c._points_label.visible)
	assert_eq(c._points_label.text, "Points remaining: 27 of 27")
	var opt := c._score_options[Ability.Type.STR]
	assert_eq(opt.item_count, 8, "15 down to 8, no unassigned entry")
	assert_eq(opt.get_item_text(0), "15 (9 pt)")
	assert_eq(opt.get_item_text(7), "8 (0 pt)")
	assert_eq(opt.selected, 7, "starts at 8")
	c._on_score_selected(0, Ability.Type.STR)
	assert_eq(c.draft.assigned[Ability.Type.STR], 15)
	assert_eq(c._points_label.text, "Points remaining: 18 of 27", "live")
	c._on_score_selected(0, Ability.Type.DEX)
	c._on_score_selected(1, Ability.Type.CON)  # 14: 7
	assert_eq(c._points_label.text, "Points remaining: 2 of 27")
	var intel := c._score_options[Ability.Type.INT]
	assert_true(intel.is_item_disabled(0), "15 would overspend")
	assert_false(intel.is_item_disabled(5), "10 costs 2: affordable")
	assert_true(intel.is_item_disabled(4), "11 costs 3: not")
	assert_false(c._start_button.disabled, c._problems.text)
	c.free()


func test_roll_reroll_and_offline_note() -> void:
	var c := _creator(77)
	_fill_and_choose(c)
	c._on_method_selected(CharacterDraft.METHODS.find(CharacterDraft.METHOD_ROLL))
	assert_eq(c.draft.method, CharacterDraft.METHOD_ROLL)
	assert_eq(c.draft.rolled_values, AbilityScores.roll_scores(Rng.new(77)), "rolled with the creator's rng")
	assert_true(c._reroll_button.visible)
	assert_false(c._points_label.visible)
	assert_true(c.draft.is_fully_assigned(), "the roll is suggested at once")
	assert_has(c._method_info.text, "online servers will restrict")
	assert_has(c._method_info.text, "Rolled (4d6, drop the lowest)")
	var opt := c._score_options[0]
	assert_eq(opt.get_item_text(0), "--")
	assert_eq(opt.item_count, 1 + c.draft.score_choices().size())
	assert_false(c._start_button.disabled, c._problems.text)
	var first := c.draft.rolled_values.duplicate()
	c._reroll_button.pressed.emit()
	assert_ne(c.draft.rolled_values, first, "Reroll replaces the values")
	assert_true(c.draft.is_fully_assigned())
	c._on_score_selected(0, Ability.Type.STR)
	assert_eq(c.draft.assigned[Ability.Type.STR], CharacterDraft.UNASSIGNED)
	assert_true(c._start_button.disabled, "every rolled value must be placed")
	assert_has(c._method_info.text, "Still to place")
	c._on_suggest_pressed()
	assert_false(c._start_button.disabled, c._problems.text)
	c._on_method_selected(0)
	assert_eq(c.draft.method, CharacterDraft.METHOD_STANDARD)
	assert_false(c._reroll_button.visible)
	assert_eq(c._score_options[0].get_item_text(1), "15")
	c.free()


func test_start_emits_a_sheet_for_each_method() -> void:
	for m in CharacterDraft.METHODS:
		var c := _creator()
		_fill_and_choose(c)
		c._on_method_selected(CharacterDraft.METHODS.find(m))
		c._on_suggest_pressed()
		var got: Array[CharacterSheet] = []
		c.character_created.connect(func(sheet: CharacterSheet) -> void: got.append(sheet))
		c._start_button.pressed.emit()
		assert_eq(got.size(), 1, "%s: %s" % [m, c._problems.text])
		c.free()

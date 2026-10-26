extends TestCase
## Hud built off-tree (its _ready() called by hand) and refreshed from a
## ClientState: level / XP line, floor label, stairs button, end panels.


func _state_on_last_floor() -> ClientState:
	var st := ClientState.new("p1")
	st.apply(Messages.make_result(Messages.FLOOR_LOADED, {"floor": {
		"schema_version": 1, "id": "floor_b", "display_name": "Lower Hall", "floor_number": 2,
		"rows": ["#######", "#A...S#", "#######"], "arrival": [1, 1], "stairs": [5, 1], "encounter_zones": [],
	}, "entity_id": "p1", "set_id": "set_t", "set_name": "Test Set", "floor_index": 1, "floor_count": 2}))
	var s := CharacterSheet.new()
	s.name = "Tess"
	s.class_id = "fighter"
	s.level = 2
	s.xp = 315
	s.max_hp = 20
	s.current_hp = 20
	st.apply(Messages.make_result(Messages.CHARACTER_STATE, {"sheet": s.to_dict()}))
	st.apply(Messages.make_result(Messages.EXPLORE_STATE, {"entities": [{"id": "p1", "kind": "player", "position": [5, 1]}], "tick": 1}))
	return st


func test_hud_shows_level_floor_and_stairs_label() -> void:
	var hud := Hud.new()
	hud._ready()
	var st := _state_on_last_floor()
	hud.refresh(st)
	assert_eq(hud._xp_label.text, "Lv 2  XP 315/900")
	assert_eq(hud._floor_label.text, "Floor 2 — Lower Hall")
	var stairs: Button = hud._buttons["use_stairs"]
	assert_true(stairs.visible)
	assert_false(stairs.disabled)
	assert_eq(stairs.text, "Enter the safe zone")
	assert_false(hud._end_panel.visible)
	st.apply(Messages.make_result(Messages.SET_CLEARED, {"set_id": "set_t"}))
	hud.refresh(st)
	assert_true(hud._end_panel.visible, "set cleared panel")
	assert_eq(hud._end_title.text, "Set cleared")
	assert_has(hud._end_text.text, "Test Set")
	hud.free()


func _wizard_state() -> ClientState:
	var st := ClientState.new("p1")
	st.apply(Messages.make_result(Messages.FLOOR_LOADED, {"floor": {
		"schema_version": 1, "id": "f", "display_name": "Hall", "floor_number": 1,
		"rows": ["##########", "#A.......#", "#.......S#", "##########"], "arrival": [1, 1], "stairs": [8, 2],
		"encounter_zones": [{"id": "z1", "rect": [1, 1, 8, 2], "monster_ids": ["goblin"], "spawn_points": [[6, 1]]}],
	}, "entity_id": "p1", "chests": [{"id": "c1", "position": [2, 2], "hidden": false, "opened": false}]}))
	var d := CharacterDraft.new()
	d.character_name = "Ilsa"
	d.set_class(ContentLoader.load_classes()["wizard"])
	d.auto_assign()
	st.apply(Messages.make_result(Messages.CHARACTER_STATE, {"sheet": d.build_sheet().to_dict()}))
	st.apply(Messages.make_result(Messages.EXPLORE_STATE, {"entities": [
		{"id": "p1", "kind": "player", "position": [1, 1]},
		{"id": "z1_goblin_0", "kind": "monster", "position": [6, 1], "name": "Goblin", "monster_id": "goblin"},
	], "tick": 1}))
	return st


func test_hud_shows_slots_inventory_spells_and_tags() -> void:
	var hud := Hud.new()
	hud._ready()
	var st := _wizard_state()
	hud.refresh(st)
	assert_eq(hud._slots_label.text, "Slots: 1st 2/2")
	assert_eq(hud._gold_label.text, "Gold: 10")
	assert_has(hud._turn_label.text, "chest", "a chest within reach")
	assert_false(hud.is_inventory_open())
	hud.toggle_inventory()
	assert_true(hud.is_inventory_open())
	assert_has(hud._inv_ac.text, "AC ")
	assert_true(hud._inv_items_box.get_child_count() > 0, "item rows")
	assert_true(hud.close_top())
	assert_false(hud.is_inventory_open())
	st.apply(Messages.make_result(Messages.ENCOUNTER_EVENTS, {"encounter_id": "z1", "zone_id": "z1", "events": [
		{"kind": "combatant_joined", "id": "p1", "initiative": 15, "position": [1, 1]},
		{"kind": "combatant_joined", "id": "z1_goblin_0", "initiative": 5, "position": [6, 1]},
		{"kind": "encounter_started", "order": ["p1", "z1_goblin_0"]},
		{"kind": "turn_started", "actor": "p1", "round": 1},
		{"kind": "effect_applied", "source": "p1", "target": "z1_goblin_0", "effect": "hex"},
	]}))
	hud.toggle_spells()
	assert_true(hud.is_popup_open())
	assert_true(hud._spells_box.get_child_count() > 0, "spell rows")
	assert_has(hud._order_label.text, "[hexed]")
	assert_true(hud.close_top())
	assert_false(hud.is_popup_open())
	var signals: Array[Dictionary] = []
	hud.intent_requested.connect(func(i: Dictionary) -> void: signals.append(i))
	hud._begin_cast("fire_bolt", 0)
	assert_true(st.is_targeting() or not signals.is_empty(), "casting started")
	hud.free()


func test_level_up_button_and_screen() -> void:
	var hud := Hud.new()
	hud._ready()
	var st := _wizard_state()
	var s := st.sheet
	s.xp = 300
	st.apply(Messages.make_result(Messages.CHARACTER_STATE, {"sheet": s.to_dict()}))
	st.apply(Messages.make_result(Messages.LEVEL_UP_AVAILABLE, {"entity_id": "p1", "choices": LevelUp.choices(st.sheet)}))
	hud.refresh(st)
	assert_true(hud._level_up_button.visible)
	assert_false(hud._level_up_button.disabled)
	var packed: PackedScene = load("res://scenes/ui/level_up_screen.tscn")
	var screen := packed.instantiate() as LevelUpScreen
	screen._ready()
	screen.open(st.level_up_offer, st.sheet)
	assert_true(screen.is_open())
	assert_eq(screen._title.text, "Level 2!  Wizard")
	assert_true(screen._confirm.disabled, "spells to learn first")
	var sent: Array[Dictionary] = []
	screen.confirmed.connect(func(c: Dictionary) -> void: sent.append(c))
	var auto := LevelUpDraft.first_valid(st.level_up_offer, st.sheet)
	for id in auto.learn_spells:
		screen._on_learn_toggled(id, true)
	for id in auto.learn_cantrips:
		screen._on_learn_toggled(id, true)
	assert_false(screen._confirm.disabled, str(screen.draft.problems()))
	screen._on_confirm()
	assert_eq(sent.size(), 1)
	assert_eq(sent[0]["hp"], "average")
	assert_true(screen._confirm.disabled, "waiting for the server")
	screen.set_waiting(false, "nope")
	assert_has(screen._problems.text, "nope")
	screen.free()
	hud.free()


func _class_state(class_id: String, level: int) -> ClientState:
	var d := CharacterDraft.new()
	d.character_name = "Kit"
	d.set_class(ContentLoader.load_classes()[class_id])
	d.set_ancestry(ContentLoader.load_ancestries()["human"])
	d.auto_assign()
	for skill in d.class_def.skill_choices:
		d.toggle_skill(skill, true)
	d.auto_choose()
	var s := d.build_sheet()
	while s.level < level:
		s.xp = maxi(s.xp, Experience.xp_for_level(s.level + 1))
		assert_eq(LevelUp.apply(s, LevelUpDraft.first_valid(LevelUp.choices(s), s).to_choices(), {}, null), "")
	var st := ClientState.new("p1")
	st.apply(Messages.make_result(Messages.FLOOR_LOADED, {"floor": {
		"schema_version": 1, "id": "f", "display_name": "Hall", "floor_number": 1,
		"rows": ["##########", "#A.......#", "#.......S#", "##########"], "arrival": [1, 1], "stairs": [8, 2],
		"encounter_zones": [{"id": "z1", "rect": [1, 1, 8, 2], "monster_ids": ["goblin"], "spawn_points": [[2, 1]]}],
	}, "entity_id": "p1"}))
	st.apply(Messages.make_result(Messages.CHARACTER_STATE, {"sheet": s.to_dict()}))
	st.apply(Messages.make_result(Messages.EXPLORE_STATE, {"entities": [
		{"id": "p1", "kind": "player", "position": [1, 1]},
		{"id": "z1_goblin_0", "kind": "monster", "position": [2, 1], "name": "Goblin", "monster_id": "goblin"},
	], "tick": 1}))
	st.apply(Messages.make_result(Messages.ENCOUNTER_EVENTS, {"encounter_id": "z1", "zone_id": "z1", "events": [
		{"kind": "combatant_joined", "id": "p1", "initiative": 15, "position": [1, 1]},
		{"kind": "combatant_joined", "id": "z1_goblin_0", "initiative": 5, "position": [2, 1]},
		{"kind": "encounter_started", "order": ["p1", "z1_goblin_0"]},
		{"kind": "turn_started", "actor": "p1", "round": 1},
	]}))
	return st


func test_hud_attack_counter_conditions_and_concentration() -> void:
	var hud := Hud.new()
	hud._ready()
	var st := _class_state("fighter", 5)
	hud.refresh(st)
	var attack: Button = hud._buttons["attack"]
	assert_eq(attack.text, "Attack 1/2 [1]")
	assert_has(hud._turn_label.text, "Reaction: ready")
	st.apply(Messages.make_result(Messages.ENCOUNTER_EVENTS, {"encounter_id": "z1", "zone_id": "z1", "events": [
		{"kind": "attack", "attacker": "p1", "target": "z1_goblin_0", "attack_name": "Longsword", "attack_kind": "melee",
			"natural": 3, "d20s": [3], "total": 8, "target_ac": 15, "hit": false, "critical": false, "fumble": false,
			"advantage": "normal", "bonus": false, "consumed": ""},
		{"kind": "condition_applied", "target": "z1_goblin_0", "condition": "prone", "source": "p1", "duration": {"type": "encounter"}},
		{"kind": "concentration_started", "actor": "z1_goblin_0", "spell": "hex"},
	]}))
	hud.refresh(st)
	assert_eq(attack.text, "Attack 2/2 [1]")
	assert_false(attack.disabled, "the second attack is still available")
	assert_has(hud._turn_label.text, "Action: Attack 2/2 left")
	assert_has(hud._order_label.text, "prone")
	assert_has(hud._order_label.text, "concentrating: Hex")
	assert_false(hud._options_row.visible, "a fighter has no attack options")
	hud.free()


func test_hud_attack_options_features_and_metamagic() -> void:
	var hud := Hud.new()
	hud._ready()
	var pal := _class_state("paladin", 2)
	hud.refresh(pal)
	assert_true(hud._options_row.visible)
	assert_true(hud._smite_picker.visible)
	assert_false(hud._reckless_check.visible)
	assert_eq(hud._smite_picker.item_count, 2, "no smite + 1st-level slots")
	hud._smite_picker.select(1)
	hud._smite_picker.item_selected.emit(1)
	assert_eq(int(pal.attack_options["smite"]), 1)
	hud.free()
	var hud2 := Hud.new()
	hud2._ready()
	var monk := _class_state("monk", 5)
	hud2.refresh(monk)
	assert_true(hud2._stun_check.visible)
	assert_true(hud2._technique_picker.visible)
	hud2.toggle_features()
	var mode_buttons := 0
	for row in hud2._features_box.get_children():
		for child in row.get_children():
			if child is Button and (child as Button).text in ["Dash", "Disengage"]:
				mode_buttons += 1
	assert_eq(mode_buttons, 2, "Step of the Wind: dash / disengage")
	hud2.free()
	var hud3 := Hud.new()
	hud3._ready()
	var sorc := _class_state("sorcerer", 3)
	sorc.sheet.metamagic = ["quickened_spell", "twinned_spell"] as Array[String]
	hud3.refresh(sorc)
	hud3.toggle_spells()
	var pickers := 0
	for row in hud3._spells_box.get_children():
		for child in row.get_children():
			if child is OptionButton and (child as OptionButton).get_item_text(0) == "No metamagic":
				pickers += 1
	assert_true(pickers > 0, "metamagic pickers on the spell rows")
	assert_has(hud3._resources_label.text, "Sorcery points")
	hud3.free()


func test_level_up_screen_choice_sections_and_cards() -> void:
	var st := _class_state("warlock", 1)
	var s := st.sheet
	s.xp = Experience.xp_for_level(2)
	var packed: PackedScene = load("res://scenes/ui/level_up_screen.tscn")
	var screen := packed.instantiate() as LevelUpScreen
	screen._ready()
	screen.open(LevelUp.choices(s), s)
	var sections := screen._choices_section.get_children()
	assert_eq(sections.size(), 1, "invocations")
	var boxes := 0
	var greyed := 0
	for child in sections[0].get_children():
		if child is CheckBox:
			boxes += 1
			if (child as CheckBox).text.ends_with("not yet modelled"):
				greyed += 1
	assert_true(boxes >= 3, "invocation options")
	assert_true(greyed > 0, "unmodelled invocations are marked")
	assert_true(screen._confirm.disabled, "two invocations to choose")
	var auto := LevelUpDraft.first_valid(screen.draft.offer, s)
	for entry in auto.choice_entries():
		for o in auto.picks_for(entry):
			screen._on_choice_toggled(entry, o, true)
	for id in auto.learn_spells:
		screen._on_learn_toggled(id, true)
	for id in auto.learn_cantrips:
		screen._on_learn_toggled(id, true)
	assert_false(screen._confirm.disabled, str(screen.draft.problems()))
	var sent: Array[Dictionary] = []
	screen.confirmed.connect(func(c: Dictionary) -> void: sent.append(c))
	screen._on_confirm()
	assert_eq((sent[0]["invocations"] as Array).size(), 2)
	assert_eq(LevelUp.apply(s, sent[0], {}, null), "", "the screen's answer is valid")
	assert_true(screen._features_box.get_child_count() > 0, "feature cards")
	screen.free()


## A wizard exploring the _wizard_state() floor with Find Familiar and Shield prepared.
func _ooc_wizard_state() -> ClientState:
	var st := _wizard_state()
	for id: String in ["find_familiar", "shield"]:
		st.sheet.spells_known.append(id)
		st.sheet.spells_prepared.append(id)
	return st


func _buttons_in(box: Container) -> Array[Button]:
	var out: Array[Button] = []
	for child in box.get_children():
		if child is Button:
			out.append(child as Button)
		elif child is Container:
			out.append_array(_buttons_in(child as Container))
	return out


func test_spells_popup_out_of_combat_casts_at_once() -> void:
	var hud := Hud.new()
	hud._ready()
	var st := _ooc_wizard_state()
	var sent: Array[Dictionary] = []
	hud.intent_requested.connect(func(i: Dictionary) -> void: sent.append(i))
	hud.refresh(st)
	assert_false(hud._buttons["spells"].disabled, "Q works while exploring")
	hud.toggle_spells()
	assert_true(hud.is_spells_open())
	var familiar: Button = null
	var texts: PackedStringArray = []
	for b in _buttons_in(hud._spells_box):
		texts.append(b.text)
		if b.text.begins_with("Find Familiar"):
			familiar = b
	assert_not_null(familiar, str(texts))
	assert_has(familiar.text, "1 hour (ritual)")
	assert_false(familiar.disabled)
	for t in texts:
		assert_false(t.begins_with("Fire Bolt"), "combat spells are hidden while exploring")
	var forms: OptionButton = null
	for row in hud._spells_box.get_children():
		for child in row.get_children():
			if child is OptionButton and (child as OptionButton).tooltip_text == "Form of the companion":
				forms = child
	assert_not_null(forms, "a form picker")
	assert_eq(str(forms.get_selected_metadata()), "owl", "the default form")
	for i in range(forms.item_count):
		if str(forms.get_item_metadata(i)) == "cat":
			forms.select(i)
	familiar.pressed.emit()
	assert_eq(sent.size(), 1)
	assert_eq(sent[0].get("type"), Messages.CAST)
	assert_eq(sent[0].get("spell"), "find_familiar")
	assert_eq(sent[0].get("form"), "cat")
	assert_false(hud.is_spells_open(), "the popup closes")
	hud.free()


func test_companions_line_and_dismiss_button() -> void:
	var hud := Hud.new()
	hud._ready()
	var st := _ooc_wizard_state()
	var sent: Array[Dictionary] = []
	hud.intent_requested.connect(func(i: Dictionary) -> void: sent.append(i))
	hud.refresh(st)
	assert_false(hud._companions_box.visible, "no companions yet")
	var sheet := st.sheet
	sheet.companions = [{"id": "c1", "monster": "owl", "spell": "find_familiar", "hp": 1}] as Array[Dictionary]
	st.apply(Messages.make_result(Messages.CHARACTER_STATE, {"sheet": sheet.to_dict()}))
	hud.refresh(st)
	assert_true(hud._companions_box.visible)
	var title: Label = hud._companions_box.get_child(0)
	assert_has(title.text, "Companions: Owl 1/")
	var dismiss: Button = null
	for b in _buttons_in(hud._companions_box):
		if b.text == "Dismiss companion":
			dismiss = b
	assert_not_null(dismiss)
	assert_false(dismiss.disabled)
	dismiss.pressed.emit()
	assert_eq(sent.size(), 1)
	assert_eq(sent[0].get("type"), Messages.DISMISS_COMPANION)
	assert_eq(sent[0].get("companion_id"), "c1")
	hud.free()


func test_reactions_popup_names_the_reactions_and_sends_the_policy() -> void:
	var hud := Hud.new()
	hud._ready()
	var st := _ooc_wizard_state()
	var sent: Array[Dictionary] = []
	hud.intent_requested.connect(func(i: Dictionary) -> void: sent.append(i))
	hud.refresh(st)
	assert_true(hud._buttons["reactions"].visible, "the rules engine has reaction policies")
	assert_false(hud._buttons["reactions"].disabled, "available out of combat")
	hud.open_reactions()
	assert_true(hud.is_reactions_open())
	var reach: CheckBox = null
	var hit: CheckBox = null
	for child in hud._reactions_box.get_children():
		if child is CheckBox:
			var c := child as CheckBox
			if c.text.begins_with("A creature leaves my reach"):
				reach = c
			elif c.text.begins_with("A creature hits me"):
				hit = c
	assert_not_null(reach)
	assert_eq(reach.text, "A creature leaves my reach: Opportunity attack")
	assert_not_null(hit)
	assert_eq(hit.text, "A creature hits me: Shield")
	assert_true(reach.button_pressed)
	reach.button_pressed = false
	assert_eq(sent.size(), 1)
	assert_eq(sent[0].get("type"), Messages.REACTION_POLICY)
	assert_eq(sent[0].get("policy"), {"creature_left_reach": "never"})
	hud.open_reactions()
	assert_true(hud.is_reactions_open(), "open_reactions never toggles it shut")
	hud.free()

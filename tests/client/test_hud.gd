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

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

extends TestCase
## Round D / round C presentation off-tree: the Hud (floor line with the
## landing, door hints, the Control panel, new attack options, ritual /
## no-effect / landmark / Overchannel in the Spells popup), EntityLayer
## visibility and the TerrainOverlay.

const PID := "p1"
const ROWS: Array[String] = [
	"##############",
	"#.....#......#",
	"#............#",
	"#.....#......#",
	"##############",
]


func _state(sheet: CharacterSheet, pos: Array = [5, 2]) -> ClientState:
	var st := ClientState.new(PID)
	var fd := {
		"schema_version": 2, "id": "f", "display_name": "Door Hall", "floor_number": 1, "rows": ROWS,
		"landings": [{"id": "ne", "position": [12, 1]}], "arrival": [12, 1], "stairs": [1, 1],
		"encounter_zones": [{"id": "z1", "rect": [7, 1, 6, 3], "monster_ids": ["goblin"], "spawn_points": [[11, 3]]}],
		"doors": [{"id": "d1", "position": [6, 2], "state": "closed"}],
		"props": [{"id": "p1", "kind": "crate", "position": [2, 3], "hp": 3, "blocks": true}],
	}
	st.apply(Messages.make_result(Messages.FLOOR_LOADED, {"floor": fd, "entity_id": PID, "landing_id": "ne", "doors": fd["doors"]}))
	st.apply(Messages.make_result(Messages.CHARACTER_STATE, {"sheet": sheet.to_dict()}))
	st.apply(Messages.make_result(Messages.EXPLORE_STATE, {"entities": [{"id": PID, "kind": "player", "position": pos}], "tick": 1}))
	return st


func _sheet(class_id: String) -> CharacterSheet:
	var d := CharacterDraft.new()
	d.character_name = "Ilsa"
	d.set_class(ContentLoader.load_classes()[class_id])
	d.set_ancestry(ContentLoader.load_ancestries()["human"])
	d.auto_assign()
	return d.build_sheet()


func _fight(st: ClientState) -> void:
	st.apply(Messages.make_result(Messages.EXPLORE_STATE, {"entities": [
		{"id": PID, "kind": "player", "position": [8, 2]},
		{"id": "g1", "kind": "monster", "position": [10, 2], "name": "Goblin", "monster_id": "goblin"},
		{"id": "g2", "kind": "monster", "position": [12, 3], "name": "Goblin", "monster_id": "goblin"},
	], "tick": 2}))
	st.apply(Messages.make_result(Messages.ENCOUNTER_EVENTS, {"encounter_id": "z1", "zone_id": "z1", "events": [
		{"kind": "combatant_joined", "id": PID, "initiative": 15, "position": [8, 2]},
		{"kind": "combatant_joined", "id": "g1", "initiative": 10, "position": [10, 2]},
		{"kind": "combatant_joined", "id": "g2", "initiative": 5, "position": [12, 3]},
		{"kind": "encounter_started", "order": [PID, "g1", "g2"]},
		{"kind": "round_started", "round": 1},
		{"kind": "turn_started", "actor": PID, "round": 1},
	]}))


func _buttons_in(box: Node) -> Array[Button]:
	var out: Array[Button] = []
	for child in box.get_children():
		if child is Button:
			out.append(child as Button)
		if child.get_child_count() > 0:
			out.append_array(_buttons_in(child))
	return out


func test_floor_line_names_the_landing_and_door_hints_show() -> void:
	var hud := Hud.new()
	hud._ready()
	var st := _state(_sheet("fighter"))
	hud.refresh(st)
	assert_eq(hud._floor_label.text, "Floor 1 — Door Hall, arrived at the north-east landing")
	assert_eq(hud._turn_label.text, "A closed door: click it to open it.")
	hud.free()


func test_control_panel_orders_a_dominated_creature() -> void:
	var hud := Hud.new()
	hud._ready()
	var st := _state(_sheet("fighter"))
	_fight(st)
	hud.refresh(st)
	assert_false(hud._control_panel.visible, "nobody to control yet")
	st.apply(Messages.make_result(Messages.ENCOUNTER_EVENTS, {"encounter_id": "z1", "zone_id": "z1", "events": [
		{"kind": "team_changed", "target": "g1", "team": 0, "controlled_by": PID}]}))
	var sent: Array[Dictionary] = []
	hud.intent_requested.connect(func(i: Dictionary) -> void: sent.append(i))
	hud.refresh(st)
	assert_true(hud._control_panel.visible)
	var by_text := {}
	for b in _buttons_in(hud._control_box):
		by_text[b.text] = b
	for t: String in ["Move", "Attack", "Hold"]:
		assert_true(by_text.has(t), t)
		assert_false((by_text[t] as Button).disabled, "%s on my turn" % t)
	(by_text["Hold"] as Button).pressed.emit()
	assert_eq(sent.size(), 1)
	assert_eq(str(sent[0]["type"]), Messages.CONTROL)
	(by_text["Attack"] as Button).pressed.emit()
	assert_true(st.is_targeting(), "Attack picks a target on the map")
	assert_has(hud._order_label.text, "dominated")
	hud.free()


func test_round_c_attack_option_checks() -> void:
	var hud := Hud.new()
	hud._ready()
	var s := _sheet("monk")
	s.features.append("quivering_palm")
	s.class_resources["ki"] = 6
	var st := _state(s)
	_fight(st)
	hud.refresh(st)
	assert_true(hud._options_row.visible)
	assert_true(hud._palm_check.visible)
	assert_false(hud._palm_check.disabled)
	assert_false(hud._hurl_check.visible)
	assert_false(hud._familiar_check.visible)
	hud._palm_check.toggled.emit(true)
	assert_true(bool(st.attack_options["quivering_palm"]))
	hud.free()


func test_spells_popup_ritual_no_effect_landmark_and_overchannel() -> void:
	var hud := Hud.new()
	hud._ready()
	var w := _sheet("wizard")
	for id: String in ["comprehend_languages", "teleportation_circle"]:
		w.spells_known.append(id)
		w.spells_prepared.append(id)
	w.spells_known.append("detect_magic")
	w.spell_slots_max = [4, 3, 3, 3, 2] as Array[int]
	w.spell_slots = [4, 3, 3, 3, 2] as Array[int]
	var st := _state(w)
	var sent: Array[Dictionary] = []
	hud.intent_requested.connect(func(i: Dictionary) -> void: sent.append(i))
	hud.refresh(st)
	hud.toggle_spells()
	var texts := {}
	for b in _buttons_in(hud._spells_box):
		texts[b.text.get_slice(" (", 0)] = b
	assert_true(texts.has("Comprehend Languages"), str(texts.keys()))
	assert_has((texts["Comprehend Languages"] as Button).text, "no effect in the delve")
	assert_true(texts.has("Detect Magic"), "a spellbook ritual is listed")
	assert_has((texts["Detect Magic"] as Button).text, "ritual only")
	var ritual: CheckBox = null
	var landmark: OptionButton = null
	for row in hud._spells_box.get_children():
		for child in row.get_children():
			if child is CheckBox and (child as CheckBox).text == "Ritual":
				ritual = child
			if child is OptionButton and (child as OptionButton).tooltip_text == "Where to go":
				landmark = child
	assert_not_null(ritual, "a Ritual check box")
	assert_not_null(landmark, "a landmark picker")
	assert_true(ritual.button_pressed, "an unprepared spellbook ritual can only be a ritual")
	(texts["Detect Magic"] as Button).pressed.emit()
	assert_eq(sent.size(), 1)
	assert_true(sent[0].get("ritual", false) == true)
	assert_eq(int(sent[0]["slot_level"]), 0)
	hud.toggle_spells()
	for b in _buttons_in(hud._spells_box):
		if b.text.begins_with("Teleportation Circle"):
			b.pressed.emit()
	assert_eq(str(sent.back()["target_kind"]), "landmark")
	assert_eq(str(sent.back()["target_id"]), "arrival")
	# Overchannel shows in a fight for a wizard with the feature.
	w.features.append("overchannel")
	var st2 := _state(w)
	_fight(st2)
	var hud2 := Hud.new()
	hud2._ready()
	hud2.refresh(st2)
	hud2.toggle_spells()
	var oc: CheckBox = null
	for child in hud2._spells_box.get_children():
		if child is CheckBox and (child as CheckBox).text.begins_with("Overchannel"):
			oc = child
	assert_not_null(oc)
	oc.toggled.emit(true)
	assert_true(bool(st2.cast_options["overchannel"]))
	hud.free()
	hud2.free()


func test_entity_layer_hides_unseen_hostiles_and_ghosts_illusions() -> void:
	var st := _state(_sheet("fighter"))
	_fight(st)
	var layer := EntityLayer.new()
	layer.refresh(st)
	assert_eq(layer.figures.get_used_cells().size() + layer.fallback.get_used_cells().size(), 3)
	st.apply(Messages.make_result(Messages.ENCOUNTER_EVENTS, {"encounter_id": "z1", "zone_id": "z1", "events": [
		{"kind": "hidden", "actor": "g2", "total": 18},
		{"kind": "combatant_joined", "id": "img", "name": "Image", "team": 0, "initiative": 1, "position": [9, 3], "owner": PID, "illusion": true},
	]}))
	layer.refresh(st)
	assert_eq(layer.figures.get_used_cells().size() + layer.fallback.get_used_cells().size(), 2, "the hidden goblin is not drawn")
	assert_eq(layer.ghosts.get_used_cells().size() + layer.ghost_fallback.get_used_cells().size(), 1, "the illusion is ghosted")
	assert_true(layer.ghosts.modulate.a < 1.0)
	layer.free()


func test_terrain_overlay_paints_walls_darkness_and_difficult_ground() -> void:
	var st := _state(_sheet("fighter"))
	_fight(st)
	st.apply(Messages.make_result(Messages.ENCOUNTER_EVENTS, {"encounter_id": "z1", "zone_id": "z1", "events": [
		{"kind": "tile_effect_created", "id": "a", "spell": "wall_of_stone", "tiles": [[9, 1], [9, 3]], "terrain": "solid"},
		{"kind": "tile_effect_created", "id": "b", "spell": "darkness", "tiles": [[11, 1]], "darkness": true},
		{"kind": "tile_effect_created", "id": "c", "spell": "spike_growth", "tiles": [[10, 3], [11, 3], [12, 2]]},
	]}))
	var overlay := TerrainOverlay.new()
	overlay.refresh(st)
	assert_eq(overlay.count("wall"), 2)
	assert_eq(overlay.count("darkness"), 1)
	assert_eq(overlay.count("difficult"), 3)
	overlay.free()

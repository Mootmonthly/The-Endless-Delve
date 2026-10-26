extends TestCase
## Offline smoke runs of the real client logic against the real server for
## the class progression systems: ClientState + LocalTransport +
## InstanceServer ticked by hand, driven only by the intents the GameScene
## would send (begin_cast / intent_for_click / begin_feature / attack_intent).
## - a level 1 wizard opens with Burning Hands (a cone aimed by clicking the
##   nearest goblin) and finishes the fight with Fire Bolt;
## - a fighter plays a long in-test set (six floors of ogres), levels up
##   interactively with LevelUpDraft.first_valid on every offer up to level 5
##   and then uses Extra Attack and Action Surge.

const MAX_TICKS := 30000

var _errors: Array[String] = []
var _answered_serial: int = 0
var _level_ups_sent: int = 0
var _burned: bool = false
var _bolts: int = 0
var _second_attacks: int = 0
var _surges: int = 0


func _on_result(result: Dictionary, st: ClientState) -> void:
	if str(result.get("kind", "")) == Messages.ERROR:
		_errors.append(str(result.get("message", "")))
	st.apply(result)


func _sheet(class_id: String, hp: int) -> CharacterSheet:
	var d := CharacterDraft.new()
	d.character_name = "Smoke"
	d.set_class(ContentLoader.load_classes()[class_id])
	d.set_ancestry(ContentLoader.load_ancestries()["human"])
	d.auto_assign()
	for skill in d.class_def.skill_choices:
		d.toggle_skill(skill, true)
	d.auto_choose()
	assert_true(d.is_valid(), str(d.problems()))
	var s := d.build_sheet()
	s.max_hp = hp
	s.current_hp = hp
	return s


func _nearest_hostile(st: ClientState) -> String:
	var best := ""
	var best_d := 1 << 30
	for id in st.order:
		var e := st.get_entity(id)
		if e.is_empty() or str(e["kind"]) != ClientState.KIND_MONSTER or bool(e["dead"]):
			continue
		var d := GridMath.distance_tiles(st.player_position(), e["position"])
		if d < best_d:
			best_d = d
			best = id
	return best


## Walks toward the nearest hostile (a click on a reachable tile next to the path's end).
func _approach(st: ClientState) -> Dictionary:
	var target := _nearest_hostile(st)
	if target.is_empty() or st.movement_remaining <= 0:
		return {}
	var path := st.movement_map().path_to(st.player_position(), st.get_entity(target)["position"], st.occupied_cells(st.player_id))
	if path.size() <= 1:
		return {}
	var steps: Array[Vector2i] = path.slice(0, mini(path.size() - 1, st.movement_remaining))
	return st.intent_for_click(steps[steps.size() - 1])


func _wizard_turn(st: ClientState) -> Dictionary:
	if st.can_take_action():
		var target := _nearest_hostile(st)
		if target.is_empty():
			return st.simple_intent(Messages.END_TURN)
		var where: Vector2i = st.get_entity(target)["position"]
		if not _burned and GridMath.distance_tiles(st.player_position(), where) <= 3 and st.cast_error("burning_hands").is_empty():
			st.begin_cast("burning_hands")
			var preview := st.area_preview(where)
			assert_has(preview.get("affected", []), target, "the cone preview catches the target")
			var cone := st.intent_for_click(where)
			if not cone.is_empty():
				_burned = true
				return cone
			st.cancel_targeting()
		st.begin_cast("fire_bolt")
		var bolt := st.intent_for_click(where)
		if not bolt.is_empty():
			_bolts += 1
			return bolt
		st.cancel_targeting()
		var walk := _approach(st)
		if not walk.is_empty():
			return walk
	return st.simple_intent(Messages.END_TURN)


func _fighter_turn(st: ClientState) -> Dictionary:
	if st.can_attack():
		if st.action_used:
			_second_attacks += 1  # an Extra Attack roll
		return st.attack_intent()
	if not st.adjacent_hostiles().is_empty() and st.feature_error("action_surge").is_empty():
		_surges += 1
		return st.begin_feature("action_surge")
	if not st.action_used:
		var walk := _approach(st)
		if not walk.is_empty():
			return walk
	return st.simple_intent(Messages.END_TURN)


func _answer_level_up(st: ClientState, transport: LocalTransport) -> bool:
	if not st.can_level_up() or st.level_up_serial == _answered_serial:
		return false
	_answered_serial = st.level_up_serial
	var draft := LevelUpDraft.first_valid(st.level_up_offer, st.sheet)
	assert_true(draft.is_valid(), "first valid choices: %s" % str(draft.problems()))
	transport.send_intent(st.level_up_intent(draft.to_choices()))
	_level_ups_sent += 1
	return true


func test_wizard_casts_burning_hands_and_fire_bolt() -> void:
	_errors.clear()
	var floor_data := FloorData.from_dict({
		"schema_version": 1, "id": "smoke_wizard", "display_name": "Smoke Study", "floor_number": 1,
		"rows": ["############", "#A.........#", "#..........#", "#.........S#", "############"],
		"arrival": [1, 1], "stairs": [10, 3],
		"encounter_zones": [{"id": "z1", "rect": [1, 1, 10, 3], "monster_ids": ["goblin", "goblin", "giant_rat"],
			"spawn_points": [[4, 1], [4, 2], [9, 3]]}],
	})
	var sheet := _sheet("wizard", 400)  # hardy: fire bolts at disadvantage when surrounded
	if not sheet.spells_prepared.has("burning_hands"):
		sheet.spells_prepared.append("burning_hands")
	var transport := LocalTransport.new()
	var st := ClientState.new(ClientState.player_id_for_peer(transport.local_peer_id()))
	transport.result_received.connect(_on_result.bind(st))
	var server := InstanceServer.new()
	server.configure(transport, floor_data, 4242)
	server.add_player(transport.local_peer_id(), sheet)
	server.run_tick()
	assert_true(st.in_encounter, "the arrival is inside the zone")
	for _t in range(MAX_TICKS):
		if not st.in_encounter or st.mode == ClientState.Mode.GAME_OVER:
			break
		if st.is_my_turn():
			var intent := _wizard_turn(st)
			if not intent.is_empty():
				transport.send_intent(intent)
		server.run_tick()
	transport.pump()
	assert_eq(_errors, [] as Array[String], "the server rejected no client intent")
	assert_true(_burned, "Burning Hands was cast")
	assert_true(_bolts >= 1, "Fire Bolt was cast")
	var cone := false
	var bolt := false
	for line in st.log_lines:
		if line.contains("Burning Hands (cone) catches"):
			cone = true
		if line.contains("casts Fire Bolt"):
			bolt = true
	assert_true(cone, "the area_effect was logged")
	assert_true(bolt, "the fire bolt was logged")
	assert_true(server.is_zone_cleared("z1"), "the wizard won")
	assert_eq(st.sheet.slots_left(1), server.get_entity("p1").sheet.slots_left(1), "client slots match the server")
	assert_eq(st.sheet.current_hp, server.get_entity("p1").sheet.current_hp)
	server.free()


func _ogre_floor(index: int) -> FloorData:
	return FloorData.from_dict({
		"schema_version": 1, "id": "smoke_ogres_%d" % index, "display_name": "Ogre Hall %d" % index, "floor_number": index,
		"rows": ["##############", "#A...........#", "#............#", "#...........S#", "##############"],
		"arrival": [1, 1], "stairs": [12, 3],
		"encounter_zones": [{"id": "z1", "rect": [5, 1, 4, 3], "monster_ids": ["ogre", "ogre", "ogre", "ogre"],
			"spawn_points": [[7, 1], [8, 1], [7, 3], [8, 3]]}],
	})


## Six floors of four ogres (450 XP each) + the floor-clear bonus: level 5 by
## the fifth floor's fight. The test softens each floor's ogres to 18 hp so the
## run stays short; the fighter has 3000 hp.
func test_fighter_levels_to_5_on_a_long_set_and_uses_extra_attack() -> void:
	_errors.clear()
	var floors := {}
	var ids: Array = []
	for i in range(1, 7):
		var f := _ogre_floor(i)
		floors[f.id] = f
		ids.append(f.id)
	var manifest := {"schema_version": 1, "id": "smoke_long", "display_name": "Smoke Long Set", "floors": ids}
	var transport := LocalTransport.new()
	var st := ClientState.new(ClientState.player_id_for_peer(transport.local_peer_id()))
	transport.result_received.connect(_on_result.bind(st))
	var server := InstanceServer.new()
	assert_true(server.configure_set(transport, manifest, 99, floors))
	server.add_player(transport.local_peer_id(), _sheet("fighter", 3000))
	var softened := -1
	var stairs_sent_on := -1
	var walk_sent_tick := -100
	for t in range(MAX_TICKS):
		if softened != server.get_floor_index():
			softened = server.get_floor_index()
			for id in server.entity_ids():
				var e := server.get_entity(id)
				if e.is_monster():
					e.sheet.max_hp = 18
					e.sheet.current_hp = 18
		if st.mode == ClientState.Mode.GAME_OVER or st.mode == ClientState.Mode.SET_CLEARED:
			if not _answer_level_up(st, transport) and st.level_up_serial == _answered_serial and not st.has_level_up_offer():
				break
		elif st.in_encounter:
			if st.is_my_turn():
				var intent := _fighter_turn(st)
				if not intent.is_empty():
					transport.send_intent(intent)
		elif _answer_level_up(st, transport):
			pass
		elif st.has_level_up_offer():
			pass  # waiting for the answer
		elif st.can_use_stairs() and stairs_sent_on != st.floor_serial:
			transport.send_intent(st.simple_intent(Messages.USE_STAIRS))
			stairs_sent_on = st.floor_serial
		elif st.mode == ClientState.Mode.EXPLORING and t - walk_sent_tick > 40:
			transport.send_intent(st.intent_for_click(st.floor_data.stairs))
			walk_sent_tick = t
		server.run_tick()
	transport.pump()
	assert_eq(_errors, [] as Array[String], "the server rejected no client intent")
	assert_eq(st.mode, ClientState.Mode.SET_CLEARED, st.mode_text())
	assert_true(st.sheet.level >= 5, "level %d after the set" % st.sheet.level)
	assert_eq(st.sheet.level, server.get_entity("p1").sheet.level)
	assert_eq(st.sheet.subclass_id, "champion", "the archetype was chosen at level 3")
	assert_true(_level_ups_sent >= 4, "every level from 2 to 5 answered on its own offer")
	assert_true(_second_attacks >= 1, "Extra Attack rolls were made")
	assert_true(_surges >= 1, "Action Surge was used")
	server.free()

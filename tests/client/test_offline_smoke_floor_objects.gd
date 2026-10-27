extends TestCase
## Offline smoke on the Round D floor_001 (v2: landings, doors, props): a
## hardy fighter driven only through ClientState intents (as GameScene's
## clicks) opens the nearest closed door, breaks the nearest barrel, then
## walks to the stairs (route_intent opens any closed door in the way),
## fighting what it meets, answering level-ups, and descends.

const FLOOR_PATH := "res://floors/floor_001.json"
const MAX_TICKS := 9000

var _errors: Array[String] = []
var _results: Array[Dictionary] = []
var _answered_serial: int = 0


func _on_result(result: Dictionary, st: ClientState) -> void:
	_results.append(result)
	if str(result.get("kind", "")) == Messages.ERROR:
		_errors.append(str(result.get("message", "")))
	st.apply(result)


func _sheet() -> CharacterSheet:
	var d := CharacterDraft.new()
	d.character_name = "Delver"
	d.set_class(ContentLoader.load_classes()["fighter"])
	d.set_ancestry(ContentLoader.load_ancestries()["human"])
	d.auto_assign()
	d.toggle_skill(Skill.Type.ATHLETICS, true)
	d.toggle_skill(Skill.Type.PERCEPTION, true)
	var s := d.build_sheet()
	s.max_hp = 400
	s.current_hp = 400
	return s


## Walk distance from `from` to stand next to `tile` (closed doors passable,
## locked ones and blocking props not); -1 when unreachable.
func _route_len(st: ClientState, from: Vector2i, tile: Vector2i) -> int:
	var m := st.floor_data.walk_map.copy()
	for d in st.floor_data.doors:
		if st.door_state(d.id) == DoorData.STATE_LOCKED:
			m.set_walkable(d.position, false)
	var blocked := st.prop_blockers()
	blocked[tile] = true
	var path := m.path_to(from, tile, blocked)
	return path.size() if not path.is_empty() or GridMath.is_adjacent(from, tile) else -1


func _nearest_door(st: ClientState) -> String:
	var best := ""
	var best_len := 1 << 30
	for d in st.floor_data.doors:
		if st.door_state(d.id) != DoorData.STATE_CLOSED:
			continue
		var n := _route_len(st, st.player_position(), d.position)
		if n >= 0 and n < best_len:
			best_len = n
			best = d.id
	return best


func _nearest_barrel(st: ClientState) -> String:
	var best := ""
	var best_len := 1 << 30
	for p in st.floor_data.props:
		if p.kind != PropData.KIND_BARREL or st.destroyed_props.has(p.id):
			continue
		var n := _route_len(st, st.player_position(), p.position)
		if n >= 0 and n < best_len:
			best_len = n
			best = p.id
	return best


func _combat_intent(st: ClientState) -> Dictionary:
	if st.can_attack():
		return st.attack_intent()
	if st.movement_remaining > 0:
		var wm := st.movement_map()
		var best: Array[Vector2i] = []
		for id in st.order:
			var e := st.get_entity(id)
			if e.is_empty() or str(e["kind"]) != ClientState.KIND_MONSTER or bool(e["dead"]):
				continue
			var path := wm.path_to(st.player_position(), e["position"], st.occupied_cells(st.player_id))
			if not path.is_empty() and (best.is_empty() or path.size() < best.size()):
				best = path
		if not best.is_empty():
			var steps: Array[Vector2i] = best.slice(0, mini(best.size(), st.movement_remaining))
			var intent := st.intent_for_click(steps[steps.size() - 1])
			if not intent.is_empty():
				return intent
	return st.simple_intent(Messages.END_TURN)


func test_fighter_opens_a_door_and_breaks_a_barrel_on_the_way_to_the_stairs() -> void:
	var floor_data := FloorFile.load(FLOOR_PATH)
	assert_not_null(floor_data)
	assert_eq(floor_data.schema_version, 2)
	var transport := LocalTransport.new()
	var st := ClientState.new(ClientState.player_id_for_peer(transport.local_peer_id()))
	transport.result_received.connect(_on_result.bind(st))
	var server := InstanceServer.new()
	server.configure(transport, floor_data, 20261027)
	server.add_player(transport.local_peer_id(), _sheet())
	server.run_tick()
	assert_eq(st.mode, ClientState.Mode.EXPLORING)
	assert_false(st.landing_id.is_empty())
	assert_true(st.floor_hud_text().contains("arrived at the"), st.floor_hud_text())
	assert_eq(st.door_states.size(), floor_data.doors.size(), "every door's state arrived")
	var door_goal := _nearest_door(st)
	assert_false(door_goal.is_empty(), "a closed door can be reached")
	var barrel_goal := ""
	var stairs_sent := false
	var walk_sent := -100
	for t in range(MAX_TICKS):
		if st.mode != ClientState.Mode.EXPLORING and st.mode != ClientState.Mode.COMBAT:
			break
		if st.in_encounter:
			if st.is_my_turn():
				transport.send_intent(_combat_intent(st))
		elif st.can_level_up() and st.level_up_serial != _answered_serial:
			_answered_serial = st.level_up_serial
			transport.send_intent(st.level_up_intent(LevelUpDraft.first_valid(st.level_up_offer, st.sheet).to_choices()))
		elif t - walk_sent > 30:
			walk_sent = t
			var intent := {}
			if st.door_state(door_goal) == DoorData.STATE_CLOSED:
				intent = st.intent_for_click(floor_data.get_door(door_goal).position)
			else:
				if barrel_goal.is_empty():
					barrel_goal = _nearest_barrel(st)
				if not barrel_goal.is_empty() and not st.destroyed_props.has(barrel_goal):
					intent = st.intent_for_click(floor_data.get_prop(barrel_goal).position)
				elif st.can_use_stairs() and not stairs_sent:
					intent = st.simple_intent(Messages.USE_STAIRS)
					stairs_sent = true
				elif not st.on_stairs():
					intent = st.intent_for_click(floor_data.stairs)
			if not intent.is_empty():
				transport.send_intent(intent)
		server.run_tick()
	transport.pump()
	assert_eq(_errors, [] as Array[String], "the server rejected no client intent")
	assert_eq(st.mode, ClientState.Mode.FLOOR_CLEARED, st.mode_text())
	var opened := false
	var broke := false
	for r in _results:
		match str(r.get("kind", "")):
			Messages.DOOR_CHANGED:
				if str(r["by"]) == st.player_id and str(r["state"]) == "open":
					opened = true
			Messages.PROP_DESTROYED:
				if str(r["by"]) == st.player_id and str(r["prop_id"]) == barrel_goal:
					broke = true
	assert_true(opened, "the fighter opened a door")
	assert_true(broke, "the fighter broke barrel %s" % barrel_goal)
	assert_eq(st.door_state(door_goal), "open")
	assert_eq(server.door_state(door_goal), "open", "client and server agree on the door")
	assert_true(server.is_prop_destroyed(barrel_goal))
	assert_true(st.destroyed_props.has(barrel_goal))
	var logged_door := false
	var logged_barrel := false
	for line in st.log_lines:
		if line == "You open the door.":
			logged_door = true
		if line == "You smash the barrel.":
			logged_barrel = true
	assert_true(logged_door, "the log says the door opened")
	assert_true(logged_barrel, "the log says the barrel broke")
	assert_eq(st.sheet.inventory, server.get_entity(st.player_id).sheet.inventory, "loot reached the client's inventory")
	server.free()

extends TestCase
## Offline smoke test of the real client logic against the real server:
## LocalTransport + InstanceServer (never added to a tree; ticks are run by
## hand with run_tick()) + ClientState, driven only through the intents the
## GameScene would send. Walks into the first zone, fights to the end of the
## encounter, then heads for the stairs and descends (or dies trying).

const FLOOR_PATH := "res://floors/floor_001.json"
const MAX_TICKS := 6000

var _errors: Array[String] = []


func _bot_sheet() -> CharacterSheet:
	var classes := ContentLoader.load_classes()
	var ancestries := ContentLoader.load_ancestries()
	var d := CharacterDraft.new()
	d.character_name = "Smoke"
	d.set_class(classes["fighter"])
	d.set_ancestry(ancestries["human"])
	d.auto_assign()
	d.toggle_skill(Skill.Type.ATHLETICS, true)
	d.toggle_skill(Skill.Type.PERCEPTION, true)
	return d.build_sheet()


## What a player would do on their combat turn: attack if possible, else walk
## toward the nearest monster, else end the turn.
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
			var target: Vector2i = steps[steps.size() - 1]
			var intent := st.intent_for_click(target)
			if not intent.is_empty():
				return intent
	return st.simple_intent(Messages.END_TURN)


func _on_result(result: Dictionary, st: ClientState) -> void:
	if str(result.get("kind", "")) == Messages.ERROR:
		_errors.append(str(result.get("message", "")))
	st.apply(result)


## Runs a whole offline session with a scripted player; returns the client
## state (the server is freed). fought / errors are reported via fields.
var _fought: bool = false
var _server_hp: int = -1
var _zone_cleared: bool = false


func _play(sheet: CharacterSheet, instance_seed: int) -> ClientState:
	_errors.clear()
	_fought = false
	var floor_data := FloorFile.load(FLOOR_PATH)
	assert_not_null(floor_data)
	var transport := LocalTransport.new()
	var st := ClientState.new(ClientState.player_id_for_peer(transport.local_peer_id()))
	transport.result_received.connect(_on_result.bind(st))
	var server := InstanceServer.new()
	server.configure(transport, floor_data, instance_seed)
	var pid := server.add_player(transport.local_peer_id(), sheet)
	assert_eq(pid, "p1")
	server.run_tick()
	assert_eq(st.mode, ClientState.Mode.EXPLORING)
	assert_eq(st.player_position(), floor_data.arrival)
	assert_eq(st.entities.size(), 6, "the player and five monsters")
	assert_eq(st.display_name("z1_giant_rat_0"), "Giant Rat", "names come from EXPLORE_STATE")
	var stairs_sent := false
	var walk_sent_tick := -100
	for t in range(MAX_TICKS):
		if st.mode == ClientState.Mode.GAME_OVER or st.mode == ClientState.Mode.FLOOR_CLEARED:
			break
		if st.in_encounter:
			_fought = true
			if st.is_my_turn():
				transport.send_intent(_combat_intent(st))
		elif st.can_use_stairs() and not stairs_sent:
			transport.send_intent(st.simple_intent(Messages.USE_STAIRS))
			stairs_sent = true
		elif st.mode == ClientState.Mode.EXPLORING and t - walk_sent_tick > 40:
			# (Re)issue the walk to the stairs now and then, e.g. after a fight.
			transport.send_intent(st.intent_for_click(floor_data.stairs))
			walk_sent_tick = t
		server.run_tick()
	_server_hp = server.get_entity(pid).sheet.current_hp
	_zone_cleared = server.is_zone_cleared("z1")
	server.free()
	return st


func test_level_1_fighter_run_ends_cleanly() -> void:
	var st := _play(_bot_sheet(), 20261026)
	assert_true(_fought, "an encounter was triggered on the way")
	assert_true(st.mode == ClientState.Mode.FLOOR_CLEARED or st.mode == ClientState.Mode.GAME_OVER,
		"the run ended (%s)" % st.mode_text())
	assert_eq(_errors, [] as Array[String], "the server rejected no client intent")
	assert_eq(st.sheet.current_hp, _server_hp, "client HP matches the server")
	assert_false(st.in_encounter)


## A test-only hardy character (100 HP) so the run always reaches the stairs:
## exercises encounter end, walking on, use_stairs and FLOOR_CLEARED.
func test_hardy_character_clears_the_floor() -> void:
	var sheet := _bot_sheet()
	sheet.max_hp = 100
	sheet.current_hp = 100
	var st := _play(sheet, 7)
	assert_true(_fought)
	assert_true(_zone_cleared, "z1 cleared")
	assert_eq(st.mode, ClientState.Mode.FLOOR_CLEARED, st.mode_text())
	assert_eq(st.cleared_floor_id, "floor_001")
	assert_eq(st.player_position(), FloorFile.load(FLOOR_PATH).stairs)
	assert_eq(_errors, [] as Array[String], "the server rejected no client intent")
	assert_eq(st.sheet.current_hp, _server_hp, "client HP matches the server")
	assert_has(st.log_lines, "Victory! The fight is over.")



## A two-floor set (floor_001, then a small in-test floor) played by the same
## scripted client: the second FLOOR_LOADED must be handled cleanly and the
## run ends with SET_CLEARED.
func test_hardy_character_clears_a_two_floor_set() -> void:
	_errors.clear()
	var floor_b := FloorData.from_dict({
		"schema_version": 1, "id": "smoke_floor_b", "display_name": "Smoke Hall", "floor_number": 2,
		"rows": ["##########", "#A......S#", "#.########", "#...######", "##########"],
		"arrival": [1, 1], "stairs": [8, 1],
		"encounter_zones": [{"id": "z1", "rect": [2, 3, 2, 1], "monster_ids": ["goblin"], "spawn_points": [[3, 3]]}],
	})
	var manifest := {"schema_version": 1, "id": "smoke_set", "display_name": "Smoke Set", "floors": ["floor_001", "smoke_floor_b"]}
	var sheet := _bot_sheet()
	sheet.max_hp = 100
	sheet.current_hp = 100
	var transport := LocalTransport.new()
	var st := ClientState.new(ClientState.player_id_for_peer(transport.local_peer_id()))
	transport.result_received.connect(_on_result.bind(st))
	var server := InstanceServer.new()
	assert_true(server.configure_set(transport, manifest, 7, {"smoke_floor_b": floor_b}))
	server.add_player(transport.local_peer_id(), sheet)
	server.run_tick()
	assert_eq(st.floor_label(), "Floor 1 — %s" % st.floor_data.display_name)
	assert_eq(st.stairs_label(), "Descend to floor 2")
	var stairs_sent_on := -1
	var walk_sent_tick := -100
	for t in range(MAX_TICKS * 2):
		if st.mode == ClientState.Mode.GAME_OVER or st.mode == ClientState.Mode.SET_CLEARED:
			break
		if st.in_encounter:
			if st.is_my_turn():
				transport.send_intent(_combat_intent(st))
		elif st.can_use_stairs() and stairs_sent_on != st.floor_serial:
			transport.send_intent(st.simple_intent(Messages.USE_STAIRS))
			stairs_sent_on = st.floor_serial
		elif st.mode == ClientState.Mode.EXPLORING and t - walk_sent_tick > 40:
			transport.send_intent(st.intent_for_click(st.floor_data.stairs))
			walk_sent_tick = t
		server.run_tick()
	transport.pump()
	assert_eq(st.mode, ClientState.Mode.SET_CLEARED, st.mode_text())
	assert_eq(st.floor_data.id, "smoke_floor_b")
	assert_eq(st.floor_serial, 2, "two FLOOR_LOADED results")
	assert_eq(st.floor_label(), "Floor 2 — Smoke Hall")
	assert_eq(st.cleared_set_id, "smoke_set")
	assert_eq(st.sheet.current_hp, st.sheet.max_hp, "long rest at the end")
	assert_eq(st.sheet.current_hp, server.get_entity("p1").sheet.current_hp, "client HP matches the server")
	assert_true(st.sheet.xp > 0, "XP from floor 1's fight")
	assert_eq(st.entities.size(), 2, "the player and floor B's goblin")
	assert_eq(_errors, [] as Array[String], "the server rejected no client intent")
	server.free()

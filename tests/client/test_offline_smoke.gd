extends TestCase
## Offline smoke test of the real client logic against the real server:
## LocalTransport + InstanceServer (never added to a tree; ticks are run by
## hand with run_tick()) + ClientState, driven only through the intents the
## GameScene would send. Walks into the first zone, fights to the end of the
## encounter, then heads for the stairs and descends (or dies trying).
## On its combat turns it drinks a potion of healing when below half HP; it
## opens the chest by the stairs before descending and answers every
## LEVEL_UP_AVAILABLE with average HP and the first valid options
## (LevelUpDraft.first_valid), as a player clicking Confirm would.

const FLOOR_PATH := "res://floors/floor_001.json"
const MAX_TICKS := 6000
const POTION := "potion_of_healing"
const STAIRS_CHEST := "f1_stairs"
## Ticks the loop keeps running after the floor ends, for the last offers.
const AFTER_END_TICKS := 10

var _errors: Array[String] = []
var _potions_drunk: int = 0
var _level_ups_sent: int = 0
var _offers_seen: int = 0
var _answered_serial: int = 0


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
	if st.sheet.current_hp * 2 < st.sheet.max_hp and st.use_item_error(POTION).is_empty():
		_potions_drunk += 1
		return st.use_item_intent(POTION)
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
	if str(result.get("kind", "")) == Messages.LEVEL_UP_AVAILABLE:
		_offers_seen += 1
	st.apply(result)


## Answers a pending level-up offer (once per offer) the way the level-up
## screen's defaults would. true when an intent was sent.
func _answer_level_up(st: ClientState, transport: LocalTransport) -> bool:
	if not st.can_level_up() or st.level_up_serial == _answered_serial:
		return false
	_answered_serial = st.level_up_serial
	var draft := LevelUpDraft.first_valid(st.level_up_offer, st.sheet)
	assert_true(draft.is_valid(), "first valid choices: %s" % str(draft.problems()))
	transport.send_intent(st.level_up_intent(draft.to_choices()))
	_level_ups_sent += 1
	return true


## Exploring: open the stairs chest first (click it: walk there, then open),
## then the stairs.
func _explore_target(st: ClientState, floor_data: FloorData) -> Vector2i:
	if st.chests.has(STAIRS_CHEST) and not bool(st.chests[STAIRS_CHEST]["opened"]):
		return st.chests[STAIRS_CHEST]["position"]
	return floor_data.stairs


## Runs a whole offline session with a scripted player; returns the client
## state (the server is freed). fought / errors are reported via fields.
var _fought: bool = false
var _server_hp: int = -1
var _zone_cleared: bool = false
var _server_sheet: Dictionary = {}


func _play(sheet: CharacterSheet, instance_seed: int) -> ClientState:
	_errors.clear()
	_fought = false
	_potions_drunk = 0
	_level_ups_sent = 0
	_offers_seen = 0
	_answered_serial = 0
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
	var expected_entities := 1
	for z in floor_data.encounter_zones:
		expected_entities += z.monster_ids.size()
	assert_eq(st.entities.size(), expected_entities, "the player and every monster on the floor")
	assert_eq(st.display_name("z1_giant_rat_0"), "Giant Rat", "names come from EXPLORE_STATE")
	assert_true(st.chests.has(STAIRS_CHEST), "the stairs chest is known from FLOOR_LOADED")
	assert_false(st.chests.has("f1_hidden"), "the hidden chest is not sent before it is found")
	var stairs_sent := false
	var walk_sent_tick := -100
	var ended_at := -1
	for t in range(MAX_TICKS):
		if st.mode == ClientState.Mode.GAME_OVER or st.mode == ClientState.Mode.FLOOR_CLEARED:
			if ended_at < 0:
				ended_at = t
			_answer_level_up(st, transport)
			if t - ended_at > AFTER_END_TICKS:
				break
		elif st.in_encounter:
			_fought = true
			if st.is_my_turn():
				transport.send_intent(_combat_intent(st))
		elif _answer_level_up(st, transport):
			pass
		elif st.can_use_stairs() and not stairs_sent and _explore_target(st, floor_data) == floor_data.stairs:
			transport.send_intent(st.simple_intent(Messages.USE_STAIRS))
			stairs_sent = true
		elif st.mode == ClientState.Mode.EXPLORING and (t - walk_sent_tick > 40 or st.can_open_chest(STAIRS_CHEST)):
			# (Re)issue the click now and then, e.g. after a fight; at the chest it opens it.
			var intent := st.intent_for_click(_explore_target(st, floor_data))
			if not intent.is_empty():
				transport.send_intent(intent)
			walk_sent_tick = t
		server.run_tick()
	_server_hp = server.get_entity(pid).sheet.current_hp
	_server_sheet = server.get_entity(pid).sheet.to_dict()
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
	assert_true(bool(st.chests[STAIRS_CHEST]["opened"]), "the stairs chest was opened before descending")
	var looted := false
	for line in st.log_lines:
		if line.begins_with("Loot from the chest") or line.begins_with("Nothing of value from the chest"):
			looted = true
	assert_true(looted, "chest loot was reported")
	assert_eq(st.sheet.inventory, CharacterSheet.from_dict(_server_sheet).inventory, "client inventory matches the server")


## Starts hurt (40 / 100 HP) one fight short of level 2: drinks a potion on its
## first combat turn, then answers the LEVEL_UP_AVAILABLE offer interactively.
func test_bot_drinks_a_potion_and_levels_up_interactively() -> void:
	var sheet := _bot_sheet()
	sheet.max_hp = 100
	sheet.current_hp = 40
	sheet.xp = 290
	var potions_before := sheet.count_item(POTION)
	assert_eq(potions_before, 2, "the fighter kit has two potions")
	var st := _play(sheet, 7)
	assert_true(_fought)
	assert_eq(_errors, [] as Array[String], "the server rejected no client intent")
	assert_true(_potions_drunk >= 1, "drank a potion below half HP")
	assert_true(st.sheet.count_item(POTION) <= potions_before - _potions_drunk + 2, "potions were used up (chest may add some)")
	var used := false
	for line in st.log_lines:
		if line.contains("uses Potion of Healing"):
			used = true
	assert_true(used, "the item_used event was logged")
	assert_true(_offers_seen >= 1, "LEVEL_UP_AVAILABLE arrived (never auto-applied)")
	assert_eq(_level_ups_sent, _offers_seen, "every offer was answered")
	assert_eq(st.last_leveled_to, 2, "CHARACTER_STATE leveled_to")
	assert_eq(st.sheet.level, 2)
	assert_eq(int(_server_sheet["level"]), 2, "the server applied the level")
	assert_false(st.has_level_up_offer(), "no offer left pending")
	assert_has(st.log_lines, "Level up! Smoke is now level 2.")



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

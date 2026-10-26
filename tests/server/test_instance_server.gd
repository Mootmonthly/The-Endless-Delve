extends TestCase
## InstanceServer driven headless: never added to a tree, ticked by calling
## _physics_process(1.0 / 20) directly, talking through a LocalTransport.

const DT := 1.0 / 20.0
const SEED := 1234
const RAT := "z1_giant_rat_0"

## 12x6 room. Arrival (1,1), stairs (10,4).
const ROWS: Array[String] = [
	"############",
	"#A.........#",
	"#..........#",
	"#..........#",
	"#.........S#",
	"############",
]

## Records results per peer (0 = broadcast) and lets tests send intents as
## any peer, like a network transport would.
class MultiPeerTransport extends LocalTransport:
	var sent: Array[Dictionary] = []

	func send_result(peer_id: int, result: Dictionary) -> void:
		sent.append({"peer": peer_id, "result": result.duplicate(true)})

	func broadcast_result(result: Dictionary) -> void:
		sent.append({"peer": 0, "result": result.duplicate(true)})

	func deliver(peer_id: int, intent: Dictionary) -> void:
		intent_received.emit(peer_id, intent.duplicate(true))


var server: InstanceServer
var transport: LocalTransport
var results: Array[Dictionary] = []


func before_each() -> void:
	server = InstanceServer.new()
	transport = LocalTransport.new()
	transport.result_received.connect(_on_result)
	results.clear()


func after_each() -> void:
	if server != null:
		server.free()
		server = null


func _on_result(result: Dictionary) -> void:
	results.append(result)


# --- helpers --------------------------------------------------------------------

## Zone z1 covers the full height of columns 6..8 (unavoidable when walking
## east), rat at (8,2). With zone_in_corner the zone sits at x 1..2, y 3..4
## (rat at (1,4)), off every shortest path from arrival to the stairs.
func _floor(zone_in_corner: bool = false) -> FloorData:
	var zone := {"id": "z1", "rect": [6, 1, 3, 4], "monster_ids": ["giant_rat"], "spawn_points": [[8, 2]]}
	if zone_in_corner:
		zone = {"id": "z1", "rect": [1, 3, 2, 2], "monster_ids": ["giant_rat"], "spawn_points": [[1, 4]]}
	var f := FloorData.from_dict({
		"schema_version": 1,
		"id": "test_floor",
		"display_name": "Test Floor",
		"rows": ROWS,
		"arrival": [1, 1],
		"stairs": [10, 4],
		"encounter_zones": [zone],
	})
	assert_eq(f.validate(), [] as Array[String], "test floor is valid")
	return f


func _fighter(char_name: String = "Hero") -> CharacterSheet:
	var classes := ContentLoader.load_classes()
	var ancestries := ContentLoader.load_ancestries()
	var scores := AbilityScores.new()
	scores.set_all([15, 14, 13, 12, 10, 8] as Array[int])
	var skills: Array[int] = []
	return CharacterBuilder.create(char_name, classes["fighter"], ancestries["human"], scores, skills)


func _setup(zone_in_corner: bool = false, sheet: CharacterSheet = null) -> String:
	server.configure(transport, _floor(zone_in_corner), SEED)
	return server.add_player(LocalTransport.PEER_ID, sheet if sheet != null else _fighter())


func _tick(n: int = 1) -> void:
	for _i in range(n):
		server._physics_process(DT)


## Delivers results still queued after the last tick.
func _flush() -> void:
	transport.pump()


func _send(type: String, fields: Dictionary = {}) -> void:
	var f := fields.duplicate()
	f["actor"] = "p1"
	transport.send_intent(Messages.make_intent(type, f))


func _of_kind(kind: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for r in results:
		if str(r.get("kind", "")) == kind:
			out.append(r)
	return out


func _all_events() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for r in _of_kind(Messages.ENCOUNTER_EVENTS):
		for e: Variant in (r["events"] as Array):
			out.append(e)
	return out


func _has_event(kind: String, field: String = "", value: Variant = null) -> bool:
	for e in _all_events():
		if str(e.get("kind", "")) == kind and (field.is_empty() or e.get(field) == value):
			return true
	return false


func _pos(entity_id: String) -> Vector2i:
	return server.get_entity(entity_id).position


## Walks p1 until it reaches target or enters combat (bounded).
func _walk_to(target: Vector2i, max_ticks: int = 200) -> void:
	_send(Messages.EXPLORE_MOVE, {"target": GridMath.vec_to_arr(target)})
	for _i in range(max_ticks):
		_tick()
		var e := server.get_entity("p1")
		if e.position == target or e.in_combat():
			break
	_flush()


## Plays p1's turns: attack an adjacent living hostile, else walk toward the
## nearest one, else end the turn. One intent per tick.
func _play_fight(max_ticks: int = 2000) -> void:
	for _i in range(max_ticks):
		var enc := server.get_encounter_for("p1")
		if enc == null:
			break
		var actor := enc.current_actor()
		if actor != null and actor.id == "p1":
			_send_player_choice(enc, actor)
		_tick()
	_flush()


func _send_player_choice(enc: Encounter, me: Combatant) -> void:
	var target: Combatant = null
	for h in enc.hostiles_of(me):
		if h.is_alive() and (target == null or GridMath.distance_tiles(me.position, h.position) < GridMath.distance_tiles(me.position, target.position)):
			target = h
	if target != null and GridMath.is_adjacent(me.position, target.position) and not me.action_used:
		_send(Messages.ATTACK, {"target": target.id, "attack_index": 0})
		return
	if target != null and not GridMath.is_adjacent(me.position, target.position) and me.movement_remaining > 0:
		var path := enc.walk_map.path_to(me.position, target.position, enc.occupied_cells(me.id))
		if not path.is_empty():
			if path.size() > me.movement_remaining:
				path.resize(me.movement_remaining)
			_send(Messages.MOVE, {"path": GridMath.vec_list_to_arr(path)})
			return
	_send(Messages.END_TURN)


# --- tests --------------------------------------------------------------------------

func test_add_player_sends_floor_character_and_explore_state() -> void:
	var id := _setup()
	assert_eq(id, "p1")
	assert_eq(_pos("p1"), Vector2i(1, 1), "placed on arrival")
	_flush()
	var kinds: Array[String] = []
	for r in results:
		kinds.append(str(r["kind"]))
		assert_eq(Messages.validate_result(r), "", "well-formed %s" % str(r["kind"]))
	assert_eq(kinds, [Messages.FLOOR_LOADED, Messages.CHARACTER_STATE, Messages.EXPLORE_STATE] as Array[String])
	assert_eq(str(results[0]["floor"]["id"]), "test_floor")
	assert_eq(str(results[1]["sheet"]["name"]), "Hero")
	var ids: Array[String] = []
	for ent: Variant in (results[2]["entities"] as Array):
		ids.append(str((ent as Dictionary)["id"]))
	assert_eq(ids, [RAT, "p1"] as Array[String], "monster spawned at load, then the player")
	assert_eq(_pos(RAT), Vector2i(8, 2))
	assert_false(server.get_entity(RAT).in_combat(), "monsters idle until the zone triggers")


func test_player_walks_to_tile_one_step_every_three_ticks() -> void:
	_setup(true)
	_send(Messages.EXPLORE_MOVE, {"target": [5, 1]})
	_tick()
	assert_eq(_pos("p1"), Vector2i(2, 1), "first step on the tick the intent arrives")
	_tick(2)
	assert_eq(_pos("p1"), Vector2i(2, 1), "no step in between")
	_tick()
	assert_eq(_pos("p1"), Vector2i(3, 1), "second step 3 ticks later")
	_tick(6)
	assert_eq(_pos("p1"), Vector2i(5, 1), "arrived")
	_tick(6)
	assert_eq(_pos("p1"), Vector2i(5, 1), "stays put")
	_flush()
	var states := _of_kind(Messages.EXPLORE_STATE)
	assert_eq(states.size(), 1 + 4, "one EXPLORE_STATE on join and one per step")
	var last: Dictionary = states[states.size() - 1]
	for ent: Variant in (last["entities"] as Array):
		var d: Dictionary = ent
		if str(d["id"]) == "p1":
			assert_eq(d["position"], [5, 1])
	assert_true(_of_kind(Messages.ERROR).is_empty(), "no errors")


func test_explore_move_to_a_wall_is_rejected() -> void:
	_setup(true)
	_send(Messages.EXPLORE_MOVE, {"target": [0, 0]})
	_tick()
	_flush()
	assert_eq(_of_kind(Messages.ERROR).size(), 1)
	assert_eq(_pos("p1"), Vector2i(1, 1))


func test_entering_a_zone_starts_an_encounter() -> void:
	_setup()
	_walk_to(Vector2i(10, 1))
	var e := server.get_entity("p1")
	assert_true(e.in_combat(), "stepping into the zone switches to combat")
	assert_eq(e.position.x, 6, "stopped on the zone's first column")
	assert_eq(e.zone_id, "z1")
	assert_true(server.get_entity(RAT).in_combat())
	var enc := server.get_encounter_for("p1")
	assert_not_null(enc)
	assert_eq(enc.state, Encounter.State.ACTIVE)
	assert_eq(enc.combatants().size(), 2)
	assert_true(_has_event("encounter_started"), "encounter_started broadcast")
	assert_true(_has_event("combatant_joined", "id", "p1"))
	assert_true(_has_event("combatant_joined", "id", RAT))
	var batches := _of_kind(Messages.ENCOUNTER_EVENTS)
	assert_eq(str(batches[0]["zone_id"]), "z1")
	# Exploration intents are refused in combat.
	var errors_before := _of_kind(Messages.ERROR).size()
	_send(Messages.EXPLORE_MOVE, {"target": [1, 1]})
	_tick()
	_flush()
	assert_eq(_of_kind(Messages.ERROR).size(), errors_before + 1, "explore_move in combat is an error")


func test_combat_intent_while_exploring_is_rejected() -> void:
	_setup()
	_send(Messages.END_TURN)
	_tick()
	_flush()
	var errors := _of_kind(Messages.ERROR)
	assert_eq(errors.size(), 1)
	assert_has(str(errors[0]["message"]), "not in combat")


func test_monster_turn_resolves_automatically_on_the_next_tick() -> void:
	_setup()
	_walk_to(Vector2i(10, 1))
	for _i in range(40):
		var enc := server.get_encounter_for("p1")
		if enc == null:
			break
		if enc.current_actor() != null and enc.current_actor().id == "p1":
			_send(Messages.END_TURN)
		_tick()
		_flush()
		if _has_event("turn_ended", "actor", RAT):
			break
	assert_true(_has_event("turn_started", "actor", RAT), "the rat's turn started")
	assert_true(_has_event("turn_ended", "actor", RAT), "the rat's turn ended without any client input")
	# The rat acts on a later tick than the one that broadcast its turn_started.
	for r in _of_kind(Messages.ENCOUNTER_EVENTS):
		var started := false
		var ended := false
		for ev: Variant in (r["events"] as Array):
			var d: Dictionary = ev
			if str(d["kind"]) == "turn_started" and str(d.get("actor")) == RAT:
				started = true
			if str(d["kind"]) == "turn_ended" and str(d.get("actor")) == RAT:
				ended = true
		assert_false(started and ended, "turn_started and the monster's actions arrive in separate results")
	var enc := server.get_encounter_for("p1")
	if enc != null:
		assert_eq(enc.current_actor().id, "p1", "back to the player")


func test_intent_for_another_entity_is_rejected() -> void:
	_setup()
	server.monster_turn_delay_ticks = 1000  # keep the rat from acting meanwhile
	_walk_to(Vector2i(10, 1))
	var enc := server.get_encounter_for("p1")
	var logged := enc.intent_log.size()
	transport.send_intent(Messages.make_intent(Messages.END_TURN, {"actor": RAT}))
	_tick()
	_flush()
	var errors := _of_kind(Messages.ERROR)
	assert_eq(errors.size(), 1)
	assert_has(str(errors[0]["message"]), "only act as p1")
	assert_eq(enc.intent_log.size(), logged, "nothing reached the encounter")


func test_intent_from_the_wrong_peer_goes_back_only_to_that_peer() -> void:
	var multi := MultiPeerTransport.new()
	server.configure(multi, _floor(), SEED)
	server.add_player(1, _fighter("One"))
	server.add_player(2, _fighter("Two"))
	assert_eq(server.entity_id_for_peer(2), "p2")
	assert_ne(server.get_entity("p2").position, server.get_entity("p1").position, "second player placed on a free tile")
	multi.sent.clear()
	multi.deliver(2, Messages.make_intent(Messages.EXPLORE_MOVE, {"actor": "p1", "target": [3, 3]}))
	multi.deliver(3, Messages.make_intent(Messages.EXPLORE_MOVE, {"actor": "p1", "target": [3, 3]}))
	assert_eq(multi.sent.size(), 2)
	assert_eq(int(multi.sent[0]["peer"]), 2, "error to the sender only")
	assert_eq(str(multi.sent[0]["result"]["kind"]), Messages.ERROR)
	assert_eq(int(multi.sent[1]["peer"]), 3, "unknown peer is told so")
	assert_eq(str(multi.sent[1]["result"]["kind"]), Messages.ERROR)
	server._physics_process(DT)
	assert_eq(_pos("p1"), Vector2i(1, 1), "p1 did not move")


func test_second_player_joins_an_active_encounter() -> void:
	var multi := MultiPeerTransport.new()
	server.configure(multi, _floor(), SEED)
	server.add_player(1, _fighter("One"))
	multi.deliver(1, Messages.make_intent(Messages.EXPLORE_MOVE, {"actor": "p1", "target": [10, 1]}))
	for _i in range(60):
		server._physics_process(DT)
		if server.get_entity("p1").in_combat():
			break
	var enc := server.get_encounter_for("p1")
	assert_not_null(enc, "p1 triggered the zone")
	server.add_player(2, _fighter("Two"))
	multi.deliver(2, Messages.make_intent(Messages.EXPLORE_MOVE, {"actor": "p2", "target": [7, 4]}))
	for _i in range(60):
		server._physics_process(DT)
		if server.get_entity("p2").in_combat() or server.get_encounter_for("p1") == null:
			break
	if server.get_encounter_for("p1") == null:
		fail("the encounter ended before p2 arrived")
		return
	assert_true(server.get_entity("p2").in_combat(), "p2 joined on entering the region")
	assert_true(server.get_encounter_for("p2") == enc, "same encounter")
	assert_not_null(enc.get_combatant("p2"))
	var joined := false
	for entry in multi.sent:
		var r: Dictionary = entry["result"]
		if str(r["kind"]) != Messages.ENCOUNTER_EVENTS:
			continue
		for ev: Variant in (r["events"] as Array):
			var d: Dictionary = ev
			if str(d["kind"]) == "combatant_joined" and str(d["id"]) == "p2":
				joined = true
	assert_true(joined, "combatant_joined for p2 broadcast")


func test_use_stairs_off_the_stairs_is_rejected() -> void:
	_setup(true)
	_send(Messages.USE_STAIRS)
	_tick()
	_flush()
	assert_eq(_of_kind(Messages.ERROR).size(), 1)
	assert_true(_of_kind(Messages.FLOOR_CLEARED).is_empty())
	assert_false(server.is_floor_cleared())


func test_use_stairs_on_the_stairs_clears_the_floor() -> void:
	_setup(true)
	_walk_to(Vector2i(10, 4))
	assert_eq(_pos("p1"), Vector2i(10, 4), "reached the stairs")
	assert_false(server.get_entity("p1").in_combat(), "path avoided the corner zone")
	_send(Messages.USE_STAIRS)
	_tick()
	_flush()
	var cleared := _of_kind(Messages.FLOOR_CLEARED)
	assert_eq(cleared.size(), 1)
	assert_eq(str(cleared[0]["floor_id"]), "test_floor")
	assert_true(server.is_floor_cleared())


func test_full_fight_against_a_giant_rat_clears_the_zone() -> void:
	var sheet := _fighter()
	sheet.max_hp = 200  # cannot lose: the test is about the flow, not the dice
	sheet.current_hp = 200
	_setup(false, sheet)
	_walk_to(Vector2i(10, 1))
	assert_true(server.get_entity("p1").in_combat())
	_play_fight()
	assert_eq(server.active_encounter_count(), 0, "encounter over")
	assert_true(server.is_zone_cleared("z1"), "players won: zone cleared")
	assert_null(server.get_entity(RAT), "dead monster removed")
	var p1 := server.get_entity("p1")
	assert_false(p1.in_combat(), "back to exploring")
	assert_true(p1.sheet.is_conscious())
	assert_true(_has_event("encounter_ended", "winning_team", Combatant.TEAM_PLAYERS))
	assert_true(_has_event("damage", "target", RAT))
	assert_false(server.is_game_over())
	assert_true(_of_kind(Messages.CHARACTER_STATE).size() >= 2, "character state after the fight")
	# A cleared zone does not trigger again, and the stairs now work.
	_walk_to(Vector2i(10, 4))
	assert_eq(_pos("p1"), Vector2i(10, 4))
	assert_false(server.get_entity("p1").in_combat())
	_send(Messages.USE_STAIRS)
	_tick()
	_flush()
	assert_eq(_of_kind(Messages.FLOOR_CLEARED).size(), 1)


func test_party_wipe_is_game_over() -> void:
	var sheet := _fighter()
	sheet.max_hp = 1
	sheet.current_hp = 1
	sheet.armor_base = 1  # AC 1: the rat hits on anything but a natural 1
	sheet.armor_max_dex = 0
	_setup(false, sheet)
	_walk_to(Vector2i(10, 1))
	for _i in range(2000):
		if server.is_game_over():
			break
		var enc := server.get_encounter_for("p1")
		if enc != null and enc.current_actor() != null and enc.current_actor().id == "p1":
			_send(Messages.END_TURN)
		_tick()
	_flush()
	assert_true(server.is_game_over(), "game over")
	assert_eq(_of_kind(Messages.GAME_OVER).size(), 1, "GAME_OVER broadcast once")
	assert_true(_has_event("encounter_ended", "winning_team", Combatant.TEAM_MONSTERS))
	assert_true(server.get_entity("p1").sheet.is_dead(), "the fallen are finished off")
	assert_false(server.is_zone_cleared("z1"))
	assert_not_null(server.get_entity(RAT), "the rat survives")
	var errors_before := _of_kind(Messages.ERROR).size()
	_send(Messages.EXPLORE_MOVE, {"target": [1, 1]})
	_tick()
	_flush()
	assert_eq(_of_kind(Messages.ERROR).size(), errors_before + 1, "intents after game over are refused")


func test_short_rest_on_the_stairs_heals() -> void:
	_setup(true)
	var sheet := server.get_entity("p1").sheet
	sheet.current_hp = 3
	_send(Messages.SHORT_REST, {"hit_dice": 1})
	_tick()
	_flush()
	assert_eq(_of_kind(Messages.ERROR).size(), 1, "no short rest off the stairs")
	assert_eq(sheet.current_hp, 3)
	_walk_to(Vector2i(10, 4))
	results.clear()
	_send(Messages.SHORT_REST, {"hit_dice": 1})
	_tick()
	_flush()
	var states := _of_kind(Messages.CHARACTER_STATE)
	assert_eq(states.size(), 1, "CHARACTER_STATE reply")
	var hp := int(states[0]["sheet"]["current_hp"])
	assert_true(hp > 3, "healed (d10 + CON 2 >= 3)")
	assert_eq(hp, sheet.current_hp)
	assert_eq(int(states[0]["sheet"]["hit_dice_remaining"]), 0, "hit die spent")
	assert_eq(int(states[0]["healed"]), hp - 3)


func test_server_copies_the_sheet() -> void:
	var sheet := _fighter()
	_setup(true, sheet)
	server.get_entity("p1").sheet.current_hp = 1
	assert_eq(sheet.current_hp, sheet.max_hp, "the caller's sheet is not server state")


func test_physics_rate_is_independent_of_frame_delta() -> void:
	_setup(true)
	for _i in range(3):
		server._physics_process(1.0 / 60.0)
	assert_eq(server.tick, 1, "three 60 Hz frames make one 20 Hz tick")
	server._physics_process(0.1)
	assert_eq(server.tick, 3, "a long frame catches up")


func test_floor_001_playthrough_to_the_stairs() -> void:
	var floor_data := FloorFile.load("res://floors/floor_001.json")
	assert_not_null(floor_data)
	var sheet := _fighter()
	sheet.max_hp = 500
	sheet.current_hp = 500
	server.configure(transport, floor_data, SEED)
	assert_eq(server.add_player(LocalTransport.PEER_ID, sheet), "p1")
	assert_eq(server.entity_ids().size(), 7, "6 monsters + the player")
	for _attempt in range(6):
		_walk_to(floor_data.stairs, 1000)
		if server.get_entity("p1").in_combat():
			_play_fight(4000)
		elif _pos("p1") == floor_data.stairs:
			break
	assert_eq(_pos("p1"), floor_data.stairs, "reached the stairs")
	assert_true(server.is_zone_cleared("z1"), "the route crosses z1")
	_send(Messages.USE_STAIRS)
	_tick()
	_flush()
	assert_eq(_of_kind(Messages.FLOOR_CLEARED).size(), 1)
	assert_false(server.is_game_over())
	for r in results:
		assert_eq(Messages.validate_result(r), "", "every result is well formed")

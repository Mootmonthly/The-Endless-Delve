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
	assert_eq(server.entity_ids().size(), 6, "5 monsters + the player")
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


# --- death saves before wipe, XP, five-floor sets -----------------------------------

func _events_of(kind: String, field: String = "", value: Variant = null) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in _all_events():
		if str(e.get("kind", "")) == kind and (field.is_empty() or e.get(field) == value):
			out.append(e)
	return out


func test_downed_solo_player_rolls_death_saves_before_game_over() -> void:
	var sheet := _fighter()
	sheet.max_hp = 20  # a rat bite (3..6) on 1 hp drops, never kills outright
	sheet.current_hp = 1
	sheet.armor_base = 1
	sheet.armor_max_dex = 0
	_setup(false, sheet)
	_walk_to(Vector2i(10, 1))
	for _i in range(4000):
		if server.is_game_over():
			break
		var enc := server.get_encounter_for("p1")
		if enc != null and enc.current_actor() != null and enc.current_actor().id == "p1":
			_send(Messages.END_TURN)
		_tick()
	_flush()
	assert_true(server.is_game_over(), "game over in the end")
	assert_eq(_of_kind(Messages.GAME_OVER).size(), 1)
	var drops := _events_of("damage", "dropped", true)
	assert_true(drops.size() >= 1, "the hero was dropped, not killed outright")
	assert_true(_events_of("death_save", "actor", "p1").size() >= 1, "and rolled death saves before the wipe")
	# The encounter ended only after the hero died or became stable.
	var last_save_index := -1
	var end_index := -1
	var all := _all_events()
	for i in range(all.size()):
		var kind := str(all[i]["kind"])
		if kind == "death_save" or (kind == "damage" and str(all[i].get("target", "")) == "p1"):
			last_save_index = i
		if kind == "encounter_ended":
			end_index = i
	assert_true(end_index > last_save_index, "encounter_ended follows the last death save / hit")
	var final_save: Dictionary = {}
	for e in _events_of("death_save", "actor", "p1"):
		final_save = e
	var final_damage: Dictionary = {}
	for e in _events_of("damage", "target", "p1"):
		final_damage = e
	assert_true(final_save.get("died") == true or final_save.get("stable") == true or final_damage.get("died") == true,
			"dead or stable when the fight ended")
	assert_true(server.get_entity("p1").sheet.is_dead())


func test_winning_awards_xp_and_levels_up() -> void:
	var sheet := _fighter()
	sheet.max_hp = 200
	sheet.current_hp = 200
	sheet.xp = 290  # a giant rat is worth 25 XP: 315 >= 300 reaches level 2
	_setup(false, sheet)
	_walk_to(Vector2i(10, 1))
	_play_fight()
	assert_true(server.is_zone_cleared("z1"))
	var p1 := server.get_entity("p1")
	assert_eq(p1.sheet.xp, 315)
	assert_eq(p1.sheet.level, 2)
	assert_eq(p1.sheet.max_hp, 200 + 8, "average fighter level-up: d10 avg 6 + CON 2")
	var states := _of_kind(Messages.CHARACTER_STATE)
	var award: Dictionary = states[states.size() - 1]
	assert_eq(int(award["xp_gained"]), 25)
	assert_eq(int(award["levels_gained"]), 1)
	assert_eq(int(award["sheet"]["level"]), 2)
	assert_eq(int(award["sheet"]["xp"]), 315)
	assert_eq(Messages.validate_result(award), "")


func test_no_xp_when_the_monsters_win() -> void:
	var sheet := _fighter()
	sheet.max_hp = 1
	sheet.current_hp = 1
	sheet.armor_base = 1
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
	for st in _of_kind(Messages.CHARACTER_STATE):
		assert_false(st.has("xp_gained"), "no XP award on a loss")
	assert_eq(server.get_entity("p1").sheet.xp, 0)


func test_xp_is_split_evenly_among_surviving_players() -> void:
	var multi := MultiPeerTransport.new()
	server.configure(multi, _floor(), SEED)
	server.add_player(1, _fighter("One"))
	server.add_player(2, _fighter("Two"))
	var zone := server.get_floor().get_zone("z1")
	var enc := Encounter.new("z1", Rng.new(1), server.get_floor().walk_map, zone.rect)
	var session := EncounterSession.new("z1", zone, enc)
	session.entity_ids.assign([RAT, "p1", "p2"])
	assert_eq(server._xp_share(session), 0, "nothing died yet")
	server.get_entity(RAT).sheet.kill()
	assert_eq(server._xp_share(session), 12, "25 XP / 2 players, remainder dropped")
	server.get_entity("p2").sheet.kill()
	assert_eq(server._xp_share(session), 25, "the dead get no share")


## Floor A: _floor() (zone z1 with a giant rat across the route). Floor B: a
## corridor to the stairs with a side room holding zone "z1" (a goblin) off
## the route, so walking to the stairs never triggers it.
const ROWS_B: Array[String] = [
	"##########",
	"#A......S#",
	"#.########",
	"#...######",
	"##########",
]


func _floor_b() -> FloorData:
	var f := FloorData.from_dict({
		"schema_version": 1, "id": "test_floor_b", "display_name": "Lower Hall",
		"floor_number": 2, "theme": "test",
		"rows": ROWS_B, "arrival": [1, 1], "stairs": [8, 1],
		"encounter_zones": [{"id": "z1", "rect": [2, 3, 2, 1], "monster_ids": ["goblin"], "spawn_points": [[3, 3]]}],
	})
	assert_eq(f.validate(), [] as Array[String], "floor B is valid")
	return f


func _two_floor_set() -> Dictionary:
	return {"schema_version": 1, "id": "set_test", "display_name": "Test Set", "theme": "test",
		"floors": ["test_floor", "test_floor_b"]}


func _setup_set(sheet: CharacterSheet) -> void:
	var floors := {"test_floor": _floor(), "test_floor_b": _floor_b()}
	assert_true(server.configure_set(transport, _two_floor_set(), SEED, floors))
	assert_eq(server.add_player(LocalTransport.PEER_ID, sheet), "p1")


func test_configure_set_rejects_a_bad_manifest() -> void:
	assert_false(server.configure_set(transport, {"schema_version": 1, "id": "x", "floors": []}, SEED))
	assert_false(server.configure_set(transport, {"schema_version": 1, "id": "x", "floors": ["no_such_floor"]}, SEED))


func test_two_floor_set_descends_and_clears_the_set() -> void:
	var sheet := _fighter()
	sheet.max_hp = 200
	sheet.current_hp = 200
	_setup_set(sheet)
	_flush()
	var loaded := _of_kind(Messages.FLOOR_LOADED)
	assert_eq(loaded.size(), 1)
	assert_eq(str(loaded[0]["set_id"]), "set_test")
	assert_eq(int(loaded[0]["floor_index"]), 0)
	assert_eq(int(loaded[0]["floor_count"]), 2)
	assert_eq(server.get_floor_count(), 2)
	# Floor A: clear z1 (the rat), take some damage, reach the stairs.
	_walk_to(Vector2i(10, 1))
	_play_fight()
	assert_true(server.is_zone_cleared("z1"))
	_walk_to(Vector2i(10, 4))
	assert_eq(_pos("p1"), Vector2i(10, 4))
	var p1 := server.get_entity("p1")
	p1.sheet.current_hp = 150
	var hit_dice_before := p1.sheet.hit_dice_remaining
	results.clear()
	_send(Messages.USE_STAIRS)
	_tick()
	_flush()
	var kinds: Array[String] = []
	for r in results:
		kinds.append(str(r["kind"]))
		assert_eq(Messages.validate_result(r), "", "well-formed %s" % str(r["kind"]))
	assert_eq(kinds, [Messages.FLOOR_CLEARED, Messages.FLOOR_LOADED, Messages.CHARACTER_STATE, Messages.EXPLORE_STATE] as Array[String])
	assert_eq(str(results[0]["floor_id"]), "test_floor")
	assert_eq(str(results[1]["floor"]["id"]), "test_floor_b")
	assert_eq(int(results[1]["floor"]["floor_number"]), 2)
	assert_eq(int(results[1]["floor_index"]), 1)
	assert_eq(str(results[1]["entity_id"]), "p1")
	assert_eq(results[1]["cleared_zones"], [], "cleared zones reset")
	# Floor B state: the player kept its sheet and stands on the new arrival.
	assert_eq(server.get_floor().id, "test_floor_b")
	assert_eq(server.get_floor_index(), 1)
	assert_true(server.get_entity("p1") == p1, "same player entity")
	assert_eq(p1.sheet.current_hp, 150, "HP damage carries over")
	assert_eq(p1.sheet.hit_dice_remaining, hit_dice_before)
	assert_eq(p1.sheet.xp, 25, "XP carries over")
	assert_eq(int(results[2]["sheet"]["current_hp"]), 150)
	assert_eq(_pos("p1"), Vector2i(1, 1))
	assert_false(server.is_zone_cleared("z1"), "floor B's z1 is a fresh zone")
	assert_false(server.is_floor_cleared())
	assert_eq(server.entity_ids(), ["z1_goblin_0", "p1"] as Array[String], "new monsters spawned, old ones gone")
	assert_eq(_pos("z1_goblin_0"), Vector2i(3, 3))
	var ents: Array = results[3]["entities"]
	assert_eq(ents.size(), 2)
	# Floor B is the last: the stairs give a long rest and clear the set.
	_walk_to(Vector2i(8, 1))
	assert_eq(_pos("p1"), Vector2i(8, 1))
	assert_false(p1.in_combat())
	results.clear()
	_send(Messages.USE_STAIRS)
	_tick()
	_flush()
	kinds.clear()
	for r in results:
		kinds.append(str(r["kind"]))
		assert_eq(Messages.validate_result(r), "", "well-formed %s" % str(r["kind"]))
	assert_eq(kinds, [Messages.FLOOR_CLEARED, Messages.CHARACTER_STATE, Messages.SET_CLEARED] as Array[String])
	assert_true(results[1]["long_rest"] == true)
	assert_eq(int(results[1]["sheet"]["current_hp"]), p1.sheet.max_hp, "long rest: full HP")
	assert_eq(p1.sheet.current_hp, p1.sheet.max_hp)
	assert_eq(str(results[2]["set_id"]), "set_test")
	assert_true(server.is_set_cleared())
	# Terminal: everything afterwards is refused, and SET_CLEARED is sent once.
	results.clear()
	_send(Messages.USE_STAIRS)
	_send(Messages.EXPLORE_MOVE, {"target": [1, 1]})
	_send(Messages.SHORT_REST, {"hit_dice": 0})
	_tick(5)
	_flush()
	var errors := _of_kind(Messages.ERROR)
	assert_eq(errors.size(), 3, "intents after SET_CLEARED are rejected")
	assert_has(str(errors[0]["message"]), "set is cleared")
	assert_eq(_of_kind(Messages.SET_CLEARED).size(), 0, "SET_CLEARED only once")
	assert_eq(_pos("p1"), Vector2i(8, 1))


func test_set_floors_use_their_own_dice() -> void:
	var floors := {"test_floor": _floor(), "test_floor_b": _floor_b()}
	server.configure_set(transport, _two_floor_set(), SEED, floors)
	var first := server._floor_rng.state()
	server._enter_floor(1, _floor_b())
	assert_ne(server._floor_rng.state(), first, "a deeper floor forks its own stream")
	assert_eq(server._floor_rng.seed_value, Rng.new(SEED).fork(InstanceServer.FLOOR_STREAM + 1).seed_value)


func test_set_01_walkthrough_with_a_strong_character() -> void:
	var path := FloorFile.floor_path("set_01")
	if not FileAccess.file_exists(path):
		assert_true(true, "floors/set_01.json not written yet: skipped")
		return
	var manifest := FloorFile.load_set(path)
	assert_false(manifest.is_empty(), "set_01 manifest is valid")
	if manifest.is_empty():
		return
	var ids := FloorFile.set_floor_ids(manifest)
	var sheet := _fighter()
	sheet.max_hp = 2000
	sheet.current_hp = 2000
	assert_true(server.configure_set(transport, manifest, SEED), "set_01 loads")
	assert_eq(server.add_player(LocalTransport.PEER_ID, sheet), "p1")
	for index in range(ids.size()):
		assert_eq(server.get_floor_index(), index)
		var floor_data := server.get_floor()
		assert_eq(floor_data.id, ids[index])
		for _attempt in range(12):
			_walk_to(floor_data.stairs, 2000)
			if server.get_entity("p1").in_combat():
				_play_fight(8000)
			elif _pos("p1") == floor_data.stairs:
				break
		assert_eq(_pos("p1"), floor_data.stairs, "reached the stairs of %s" % floor_data.id)
		_send(Messages.USE_STAIRS)
		_tick()
		_flush()
		if server.get_floor_index() == index and not server.is_set_cleared():
			fail("could not leave %s" % floor_data.id)
			return
	assert_true(server.is_set_cleared(), "set_01 cleared")
	assert_eq(_of_kind(Messages.SET_CLEARED).size(), 1)
	assert_eq(_of_kind(Messages.FLOOR_LOADED).size(), ids.size())
	assert_false(server.is_game_over())
	assert_true(server.get_entity("p1").sheet.level > 1, "levelled up along the way")
	for r in results:
		assert_eq(Messages.validate_result(r), "", "every result is well formed")

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


## Answers LEVEL_UP_AVAILABLE offers like a simple bot: average HP, the first
## valid cantrips / spells from the offer, +2 to the first ability below 19 when
## an ASI is offered, preparation unchanged. Keeps answering while the server
## re-offers (bounded).
func _answer_level_up_offers(max_levels: int = 20) -> void:
	var answered := 0
	var seen := _of_kind(Messages.LEVEL_UP_AVAILABLE).size()
	while answered < max_levels:
		var offers := _of_kind(Messages.LEVEL_UP_AVAILABLE)
		var me := server.get_entity("p1")
		if offers.is_empty() or me.in_combat() or me.sheet.pending_levels() <= 0:
			return
		var offer: Dictionary = offers.back()
		if answered > 0 and offers.size() == seen:
			return  # no new offer after the last answer
		seen = offers.size()
		_send(Messages.LEVEL_UP, {"choices": _bot_level_choices(offer["choices"])})
		_tick()
		_flush()
		answered += 1


func _bot_level_choices(offer: Dictionary) -> Dictionary:
	var spells: Dictionary = ContentLoader.cache()["spells"]
	var cantrips: Array = []
	var leveled: Array = []
	for id_v: Variant in (offer.get("spell_options", []) as Array):
		var spell: SpellDefinition = spells.get(str(id_v))
		if spell == null:
			continue
		if spell.level == 0:
			cantrips.append(str(id_v))
		else:
			leveled.append(str(id_v))
	var made := {
		"hp": "average",
		"learn_cantrips": cantrips.slice(0, int(offer.get("cantrips_to_learn", 0))),
		"learn_spells": leveled.slice(0, int(offer.get("spells_to_learn", 0))),
	}
	if bool(offer.get("asi", false)):
		var sheet := server.get_entity("p1").sheet
		for ability: String in ["STR", "DEX", "CON", "INT", "WIS", "CHA"]:
			if sheet.abilities.get_score(Ability.from_string(ability)) <= 18:
				made["asi"] = {ability: 2}
				break
	return made


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
	var expected_entities := 1
	for z in server.get_floor().encounter_zones:
		expected_entities += z.monster_ids.size()
	assert_eq(server.entity_ids().size(), expected_entities, "every monster + the player")
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


func test_winning_awards_xp_and_offers_a_level_up() -> void:
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
	assert_eq(p1.sheet.level, 1, "levels are never applied automatically")
	var states := _of_kind(Messages.CHARACTER_STATE)
	var award: Dictionary = states[states.size() - 1]
	assert_eq(int(award["xp_gained"]), 25)
	assert_eq(int(award["levels_pending"]), 1)
	assert_false(award.has("levels_gained"))
	assert_eq(int(award["sheet"]["level"]), 1)
	assert_eq(int(award["sheet"]["xp"]), 315)
	assert_eq(Messages.validate_result(award), "")
	var offers := _of_kind(Messages.LEVEL_UP_AVAILABLE)
	assert_eq(offers.size(), 1, "one offer once the fight is over")
	assert_eq(Messages.validate_result(offers[0]), "")
	assert_eq(str(offers[0]["entity_id"]), "p1")
	assert_eq(int(offers[0]["choices"]["new_level"]), 2)
	assert_eq(int(offers[0]["choices"]["hp"]["average"]), 8)
	assert_eq(str(results[results.size() - 1]["kind"]), Messages.LEVEL_UP_AVAILABLE, "the offer comes last")
	# The bot answers with average HP and the first valid options.
	_answer_level_up_offers()
	assert_eq(p1.sheet.level, 2)
	assert_eq(p1.sheet.max_hp, 200 + 8, "average fighter level-up: d10 avg 6 + CON 2")
	var last: Dictionary = _of_kind(Messages.CHARACTER_STATE).back()
	assert_eq(int(last["leveled_to"]), 2)
	assert_eq(int(last["levels_pending"]), 0)
	assert_eq(int(last["sheet"]["level"]), 2)
	assert_eq(_of_kind(Messages.LEVEL_UP_AVAILABLE).size(), 1, "no further offer")


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
	assert_eq(p1.sheet.xp, 25 + InstanceServer.FLOOR_CLEAR_XP, "XP carries over, plus the floor-clear bonus")
	assert_eq(int(results[2]["sheet"]["current_hp"]), 150)
	assert_eq(int(results[2]["xp_gained"]), 100, "floor-clear XP rides on the floor's CHARACTER_STATE")
	assert_eq(int(results[2]["floor_clear_xp"]), 100)
	assert_eq(int(results[2]["sheet"]["xp"]), 125)
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
	assert_eq(int(results[1]["floor_clear_xp"]), 100, "the last floor pays its bonus too")
	assert_eq(p1.sheet.xp, 225)
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
	_send(Messages.LEVEL_UP, {"choices": {"hp": "average"}})
	_tick()
	_flush()
	assert_has(str(_last(Messages.ERROR)["message"]), "no level-up pending", "level_up still reaches the server")
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
				_answer_level_up_offers()
			elif _pos("p1") == floor_data.stairs:
				break
		assert_eq(_pos("p1"), floor_data.stairs, "reached the stairs of %s" % floor_data.id)
		_send(Messages.USE_STAIRS)
		_tick()
		_flush()
		if server.get_floor_index() == index and not server.is_set_cleared():
			fail("could not leave %s" % floor_data.id)
			return
		if server.get_entity("p1").in_combat():
			_play_fight(8000)
		_answer_level_up_offers()
	assert_true(server.is_set_cleared(), "set_01 cleared")
	assert_eq(server.get_entity("p1").sheet.pending_levels(), 0, "every offer was answered")
	for err in _of_kind(Messages.ERROR):
		assert_false(str(err["message"]).begins_with("level_up"), "level-up choices accepted: %s" % str(err["message"]))
	assert_eq(_of_kind(Messages.SET_CLEARED).size(), 1)
	assert_eq(_of_kind(Messages.FLOOR_LOADED).size(), ids.size())
	assert_false(server.is_game_over())
	assert_true(server.get_entity("p1").sheet.level > 1, "levelled up along the way")
	for r in results:
		assert_eq(Messages.validate_result(r), "", "every result is well formed")


# --- items, chests, loot, level-up (M2) -------------------------------------------

## _floor() plus a visible chest c1 at (3,1) and a hidden chest h1 at (3,4).
func _chest_floor() -> FloorData:
	var f := FloorData.from_dict({
		"schema_version": 1, "id": "chest_floor", "display_name": "Chest Floor",
		"rows": ROWS, "arrival": [1, 1], "stairs": [10, 4],
		"encounter_zones": [{"id": "z1", "rect": [6, 1, 3, 4], "monster_ids": ["giant_rat"], "spawn_points": [[8, 2]]}],
		"chests": [
			{"id": "c1", "position": [3, 1], "table": "starter_gear"},
			{"id": "h1", "position": [3, 4], "table": "hidden_cache", "hidden": true},
		],
	})
	assert_eq(f.validate(ContentLoader.cache()["loot_tables"]), [] as Array[String], "chest floor is valid")
	return f


func _class_sheet(class_id: String, char_name: String = "Hero") -> CharacterSheet:
	var scores := AbilityScores.new()
	scores.set_all([10, 14, 13, 15, 12, 8] as Array[int])
	var skills: Array[int] = []
	var sheet := CharacterBuilder.create(char_name, ContentLoader.load_classes()[class_id],
			ContentLoader.load_ancestries()["human"], scores, skills)
	sheet.max_hp = 200
	sheet.current_hp = 200
	return sheet


## Ticks (ending the player's turns only when end_turns) until it is p1's turn.
func _wait_for_my_turn(max_ticks: int = 200) -> Encounter:
	for _i in range(max_ticks):
		var enc := server.get_encounter_for("p1")
		if enc == null:
			return null
		if enc.current_actor() != null and enc.current_actor().id == "p1":
			_flush()
			return enc
		_tick()
	return null


func _last(kind: String) -> Dictionary:
	var list := _of_kind(kind)
	return list.back() if not list.is_empty() else {}


func test_equip_unequip_drop_and_use_item_out_of_combat() -> void:
	_setup()
	var sheet := server.get_entity("p1").sheet
	assert_eq(sheet.equipped_item("armor"), "chain_mail")
	var ac_before := sheet.armor_class()
	_send(Messages.UNEQUIP, {"slot": "armor"})
	_tick()
	_flush()
	var st := _last(Messages.CHARACTER_STATE)
	assert_eq(st["unequipped"], {"item": "chain_mail", "slot": "armor"})
	assert_eq(str(st["sheet"]["equipped"]["armor"]), "")
	assert_true(sheet.armor_class() < ac_before, "unarmored AC is lower")
	assert_true(sheet.has_item("chain_mail"), "the armor stays in the inventory")
	_send(Messages.EQUIP, {"item": "chain_mail", "slot": "armor"})
	_tick()
	_flush()
	st = _last(Messages.CHARACTER_STATE)
	assert_eq(st["equipped"], {"item": "chain_mail", "slot": "armor"})
	assert_eq(sheet.armor_class(), ac_before)
	# Invalid equips are errors and change nothing.
	_send(Messages.EQUIP, {"item": "rations", "slot": "main_hand"})
	_send(Messages.EQUIP, {"item": "greataxe", "slot": "main_hand"})
	_tick()
	_flush()
	assert_eq(_of_kind(Messages.ERROR).size(), 2, "not a weapon / not carried")
	# Potion out of combat: heals, is used up, rolled by the server.
	sheet.current_hp = 3
	var potions := sheet.count_item("potion_of_healing")
	_send(Messages.USE_ITEM, {"item": "potion_of_healing"})
	_tick()
	_flush()
	st = _last(Messages.CHARACTER_STATE)
	assert_eq(str(st["item_used"]), "potion_of_healing")
	assert_in_range(int(st["healed"]), 4, 10, "2d4+2")
	assert_eq(sheet.current_hp, 3 + int(st["healed"]))
	assert_eq(sheet.count_item("potion_of_healing"), potions - 1)
	_send(Messages.USE_ITEM, {"item": "rations"})
	_tick()
	_flush()
	assert_eq(_of_kind(Messages.ERROR).size(), 3, "rations have no use")
	# Drop: removed from the inventory, nothing on the floor.
	_send(Messages.DROP_ITEM, {"item": "rations", "qty": 2})
	_tick()
	_flush()
	st = _last(Messages.CHARACTER_STATE)
	assert_eq(st["dropped"], {"item": "rations", "qty": 2})
	assert_eq(sheet.count_item("rations"), 3)
	_send(Messages.DROP_ITEM, {"item": "rations", "qty": 9})
	_tick()
	_flush()
	assert_eq(_of_kind(Messages.ERROR).size(), 4, "cannot drop more than carried")
	assert_eq(sheet.count_item("rations"), 3)
	for r in results:
		assert_eq(Messages.validate_result(r), "")


func test_inventory_intents_in_combat() -> void:
	_setup()
	_walk_to(Vector2i(10, 1))
	assert_true(server.get_entity("p1").in_combat())
	_send(Messages.UNEQUIP, {"slot": "armor"})
	_tick()
	_flush()
	assert_has(str(_last(Messages.ERROR)["message"]), "in combat", "equipment changes are exploration-only")


func test_open_chest_needs_adjacency_and_opens_once() -> void:
	server.configure(transport, _chest_floor(), SEED)
	server.add_player(LocalTransport.PEER_ID, _fighter())
	_flush()
	var loaded := _of_kind(Messages.FLOOR_LOADED)[0]
	assert_eq(loaded["chests"], [{"id": "c1", "position": [3, 1], "hidden": false, "opened": false}],
			"only the visible chest is listed")
	assert_eq(loaded["floor"]["chests"], loaded["chests"], "the floor dict hides it too")
	# (1,1) is two tiles from (3,1): too far.
	_send(Messages.OPEN_CHEST, {"chest_id": "c1"})
	_tick()
	_flush()
	assert_has(str(_last(Messages.ERROR)["message"]), "not next to")
	assert_false(server.is_chest_opened("c1"))
	_walk_to(Vector2i(2, 2))
	var sheet := server.get_entity("p1").sheet
	var before := sheet.inventory.duplicate(true)
	results.clear()
	_send(Messages.OPEN_CHEST, {"chest_id": "c1"})
	_tick()
	_flush()
	var kinds: Array[String] = []
	for r in results:
		kinds.append(str(r["kind"]))
		assert_eq(Messages.validate_result(r), "")
	assert_eq(kinds, [Messages.CHEST_OPENED, Messages.LOOT_GAINED, Messages.CHARACTER_STATE] as Array[String])
	assert_eq(str(results[0]["chest_id"]), "c1")
	assert_eq(str(results[0]["entity_id"]), "p1")
	assert_eq(str(results[1]["source"]), "chest")
	assert_eq(str(results[1]["chest_id"]), "c1")
	var table: LootTable = ContentLoader.cache()["loot_tables"]["starter_gear"]
	var rolled: Array[Dictionary] = table.roll(Rng.new(SEED).fork(InstanceServer.LOOT_STREAM))
	assert_eq(results[1]["items"], rolled, "rolled with the floor's loot stream")
	for entry: Variant in (results[1]["items"] as Array):
		var item := str((entry as Dictionary)["item"])
		var had := 0
		for b: Variant in before:
			if str((b as Dictionary)["item"]) == item:
				had = int((b as Dictionary)["qty"])
		assert_eq(sheet.count_item(item), had + int((entry as Dictionary)["qty"]), "%s added" % item)
	assert_true(server.is_chest_opened("c1"))
	# A second open is rejected; unknown ids too.
	_send(Messages.OPEN_CHEST, {"chest_id": "c1"})
	_send(Messages.OPEN_CHEST, {"chest_id": "nope"})
	_tick()
	_flush()
	var errors := _of_kind(Messages.ERROR)
	assert_has(str(errors[errors.size() - 2]["message"]), "already open")
	assert_has(str(errors[errors.size() - 1]["message"]), "no chest")


func test_hidden_chest_is_revealed_within_one_tile() -> void:
	server.configure(transport, _chest_floor(), SEED)
	server.add_player(LocalTransport.PEER_ID, _fighter())
	_flush()
	assert_false(server.is_chest_revealed("h1"))
	# Not revealed yet: answers like an unknown chest.
	_send(Messages.OPEN_CHEST, {"chest_id": "h1"})
	_tick()
	_flush()
	assert_has(str(_last(Messages.ERROR)["message"]), "no chest")
	_walk_to(Vector2i(1, 3))
	assert_eq(_of_kind(Messages.CHEST_REVEALED).size(), 0, "two tiles away: still hidden")
	_walk_to(Vector2i(2, 3))
	var revealed := _of_kind(Messages.CHEST_REVEALED)
	assert_eq(revealed.size(), 1, "revealed once within 1 tile")
	assert_eq(revealed[0]["chest"], {"id": "h1", "position": [3, 4], "hidden": true, "opened": false})
	assert_eq(Messages.validate_result(revealed[0]), "")
	assert_true(server.is_chest_revealed("h1"))
	_walk_to(Vector2i(3, 3))
	assert_eq(_of_kind(Messages.CHEST_REVEALED).size(), 1, "sent only once")
	_send(Messages.OPEN_CHEST, {"chest_id": "h1"})
	_tick()
	_flush()
	assert_true(server.is_chest_opened("h1"))
	assert_eq(str(_last(Messages.LOOT_GAINED)["chest_id"]), "h1")


func test_monster_drops_arrive_after_a_win() -> void:
	server.configure(transport, _floor(), SEED)
	var rat_def: MonsterDefinition = server._monster_defs["giant_rat"]
	rat_def.loot_table = "boss"  # three rolls, never empty
	var sheet := _fighter()
	sheet.max_hp = 200
	sheet.current_hp = 200
	server.add_player(LocalTransport.PEER_ID, sheet)
	_walk_to(Vector2i(10, 1))
	_play_fight()
	assert_true(server.is_zone_cleared("z1"))
	var loot := _of_kind(Messages.LOOT_GAINED)
	assert_eq(loot.size(), 1)
	assert_eq(Messages.validate_result(loot[0]), "")
	assert_eq(str(loot[0]["source"]), "monster")
	assert_eq(str(loot[0]["entity_id"]), "p1")
	var items: Array = loot[0]["items"]
	assert_false(items.is_empty())
	var boss: LootTable = ContentLoader.cache()["loot_tables"]["boss"]
	assert_eq(items, boss.roll(Rng.new(SEED).fork(InstanceServer.LOOT_STREAM)), "deterministic drop")
	# LOOT_GAINED comes right before the CHARACTER_STATE that carries it.
	var i := results.find(loot[0])
	assert_eq(str(results[i + 1]["kind"]), Messages.CHARACTER_STATE)
	assert_true(results[i + 1].has("xp_gained"))
	var p1 := server.get_entity("p1")
	for entry: Variant in items:
		assert_true(p1.sheet.has_item(str((entry as Dictionary)["item"])))


func test_no_drops_when_the_monsters_win() -> void:
	server.configure(transport, _floor(), SEED)
	var rat_def: MonsterDefinition = server._monster_defs["giant_rat"]
	rat_def.loot_table = "boss"
	var sheet := _fighter()
	sheet.max_hp = 1
	sheet.current_hp = 1
	sheet.armor_base = 1
	sheet.armor_max_dex = 0
	server.add_player(LocalTransport.PEER_ID, sheet)
	_walk_to(Vector2i(10, 1))
	for _i in range(2000):
		if server.is_game_over():
			break
		var enc := server.get_encounter_for("p1")
		if enc != null and enc.current_actor() != null and enc.current_actor().id == "p1":
			_send(Messages.END_TURN)
		_tick()
	_flush()
	assert_true(server.is_game_over())
	assert_eq(_of_kind(Messages.LOOT_GAINED).size(), 0)


func test_use_stairs_awards_floor_clear_xp() -> void:
	_setup(true)
	_walk_to(Vector2i(10, 4))
	assert_eq(_pos("p1"), Vector2i(10, 4))
	results.clear()
	_send(Messages.USE_STAIRS)
	_tick()
	_flush()
	var kinds: Array[String] = []
	for r in results:
		kinds.append(str(r["kind"]))
	assert_eq(kinds, [Messages.FLOOR_CLEARED, Messages.CHARACTER_STATE] as Array[String])
	assert_eq(int(results[1]["xp_gained"]), InstanceServer.FLOOR_CLEAR_XP)
	assert_eq(int(results[1]["floor_clear_xp"]), 100)
	assert_eq(int(results[1]["levels_pending"]), 0)
	assert_eq(server.get_entity("p1").sheet.xp, 100)


func test_floor_clear_xp_can_offer_a_level_up() -> void:
	var sheet := _fighter()
	sheet.xp = 250
	_setup(true, sheet)
	_walk_to(Vector2i(10, 4))
	results.clear()
	_send(Messages.USE_STAIRS)
	_tick()
	_flush()
	var kinds: Array[String] = []
	for r in results:
		kinds.append(str(r["kind"]))
	assert_eq(kinds, [Messages.FLOOR_CLEARED, Messages.CHARACTER_STATE, Messages.LEVEL_UP_AVAILABLE] as Array[String])
	assert_eq(int(results[1]["levels_pending"]), 1)
	assert_eq(server.get_entity("p1").sheet.level, 1)


func test_level_up_round_trip_with_errors_and_re_offer() -> void:
	var sheet := _fighter()
	sheet.xp = 900  # levels 2 and 3 banked
	_setup(true, sheet)
	_flush()
	var offers := _of_kind(Messages.LEVEL_UP_AVAILABLE)
	assert_eq(offers.size(), 1, "a sheet joining with banked XP gets an offer")
	assert_eq(int(offers[0]["choices"]["new_level"]), 2)
	assert_eq(int(offers[0]["choices"]["levels_pending"]), 2)
	var p1 := server.get_entity("p1")
	# Invalid choices: ERROR, nothing changes.
	_send(Messages.LEVEL_UP, {"choices": {"hp": "max"}})
	_send(Messages.LEVEL_UP, {"choices": {"hp": "average", "asi": {"STR": 2}}})
	_tick()
	_flush()
	var errors := _of_kind(Messages.ERROR)
	assert_eq(errors.size(), 2)
	assert_has(str(errors[0]["message"]), "hp must be")
	assert_has(str(errors[1]["message"]), "no ability score improvement")
	assert_eq(p1.sheet.level, 1)
	# A valid answer: CHARACTER_STATE with leveled_to, then the next offer.
	results.clear()
	var hp_before := p1.sheet.max_hp
	_send(Messages.LEVEL_UP, {"choices": {"hp": "average"}})
	_tick()
	_flush()
	var kinds: Array[String] = []
	for r in results:
		kinds.append(str(r["kind"]))
		assert_eq(Messages.validate_result(r), "")
	assert_eq(kinds, [Messages.CHARACTER_STATE, Messages.LEVEL_UP_AVAILABLE] as Array[String])
	assert_eq(int(results[0]["leveled_to"]), 2)
	assert_eq(int(results[0]["levels_pending"]), 1)
	assert_eq(p1.sheet.max_hp, hp_before + 8)
	assert_eq(int(results[1]["choices"]["new_level"]), 3)
	# Rolled HP: d10 + CON 2, from the server's level stream.
	results.clear()
	hp_before = p1.sheet.max_hp
	_send(Messages.LEVEL_UP, {"choices": {"hp": "roll"}})
	_tick()
	_flush()
	assert_eq(int(results[0]["leveled_to"]), 3)
	assert_in_range(p1.sheet.max_hp - hp_before, 3, 12)
	assert_eq(_of_kind(Messages.LEVEL_UP_AVAILABLE).size(), 0, "nothing pending: no offer")
	_send(Messages.LEVEL_UP, {"choices": {"hp": "average"}})
	_tick()
	_flush()
	assert_has(str(_last(Messages.ERROR)["message"]), "no level-up pending")
	assert_eq(p1.sheet.level, 3)


func test_level_up_offer_waits_for_the_encounter_to_end() -> void:
	# The arrival tile is inside z1: the player starts in combat.
	var f := FloorData.from_dict({
		"schema_version": 1, "id": "ambush", "display_name": "Ambush",
		"rows": ROWS, "arrival": [1, 1], "stairs": [10, 4],
		"encounter_zones": [{"id": "z1", "rect": [1, 1, 3, 3], "monster_ids": ["giant_rat"], "spawn_points": [[3, 3]]}],
	})
	server.configure(transport, f, SEED)
	var sheet := _fighter()
	sheet.max_hp = 200
	sheet.current_hp = 200
	sheet.xp = 300
	server.add_player(LocalTransport.PEER_ID, sheet)
	_flush()
	assert_true(server.get_entity("p1").in_combat())
	assert_eq(_of_kind(Messages.LEVEL_UP_AVAILABLE).size(), 0, "no offer in combat")
	_wait_for_my_turn()
	_send(Messages.LEVEL_UP, {"choices": {"hp": "average"}})
	_tick()
	_flush()
	assert_has(str(_last(Messages.ERROR)["message"]), "in combat")
	assert_eq(server.get_entity("p1").sheet.level, 1)
	_play_fight()
	assert_false(server.get_entity("p1").in_combat())
	var offers := _of_kind(Messages.LEVEL_UP_AVAILABLE)
	assert_eq(offers.size(), 1, "offered once the encounter ended")
	assert_eq(int(offers[0]["choices"]["new_level"]), 2)


func test_cast_intent_reaches_the_encounter() -> void:
	_setup(false, _class_sheet("wizard", "Mage"))
	_walk_to(Vector2i(10, 1))
	var enc := _wait_for_my_turn()
	assert_not_null(enc)
	results.clear()
	_send(Messages.CAST, {"spell": "fire_bolt", "target": RAT})
	_tick()
	_flush()
	assert_eq(_of_kind(Messages.ERROR).size(), 0)
	assert_true(_has_event("cast", "spell", "fire_bolt"), "cast event broadcast")
	assert_true(_has_event("attack", "attack_kind", "spell"), "fire bolt is a spell attack")
	# Unprepared or unknown spells are rejected by the encounter.
	_send(Messages.CAST, {"spell": "cure_wounds", "target": "p1"})
	_tick()
	_flush()
	assert_eq(_of_kind(Messages.ERROR).size(), 1)


func test_ranged_attack_and_combat_item_and_feature() -> void:
	_setup()
	var rat := server.get_entity(RAT).sheet
	rat.max_hp = 500
	rat.current_hp = 500  # survives the whole test
	_walk_to(Vector2i(10, 1))
	var enc := _wait_for_my_turn()
	assert_not_null(enc)
	var sheet := server.get_entity("p1").sheet
	var thrown := -1
	for i in range(sheet.attacks.size()):
		if str(sheet.attacks[i].get("kind", "")) == "thrown":
			thrown = i
	assert_true(thrown >= 0, "the fighter's handaxes are thrown attacks")
	var axes := sheet.count_item("handaxe")
	results.clear()
	_send(Messages.ATTACK, {"target": RAT, "attack_index": thrown})
	_tick()
	_flush()
	assert_eq(_of_kind(Messages.ERROR).size(), 0)
	assert_true(_has_event("attack", "attack_kind", "thrown"))
	assert_true(_has_event("attack", "consumed", "handaxe"))
	assert_eq(sheet.count_item("handaxe"), axes - 1, "the thrown axe is gone")
	# Bonus action: second wind; then a potion is refused (action already used).
	var potions := sheet.count_item("potion_of_healing")
	_send(Messages.USE_FEATURE, {"feature": "second_wind"})
	_send(Messages.USE_ITEM, {"item": "potion_of_healing"})
	_tick()
	_flush()
	assert_true(_has_event("feature_used", "feature", "second_wind"))
	assert_eq(_of_kind(Messages.ERROR).size(), 1, "the potion needs the action already spent")
	assert_eq(sheet.count_item("potion_of_healing"), potions, "rejected use keeps the potion")
	_send(Messages.END_TURN)
	_tick()
	assert_not_null(_wait_for_my_turn(), "still fighting")
	_send(Messages.USE_ITEM, {"item": "potion_of_healing"})
	_tick()
	_flush()
	assert_true(_has_event("item_used", "item", "potion_of_healing"), "in combat use_item goes to the encounter")
	assert_eq(sheet.count_item("potion_of_healing"), potions - 1)
	# Bonus attack flag passes through: no Martial Arts for a fighter.
	_send(Messages.ATTACK, {"target": RAT, "attack_index": 0, "bonus": true})
	_tick()
	_flush()
	assert_eq(_of_kind(Messages.ERROR).size(), 2, "the encounter judged the bonus attack")


# --- class progression round A: new intents through the server ------------------------

## Raises a sheet to `level` with LevelUp.apply: average HP, +2 to the first
## ability at 18 or less, the first cantrips / spells offered, every progression
## choice answered with its default (the first options).
func _level_to(sheet: CharacterSheet, level: int) -> void:
	var spells: Dictionary = ContentLoader.cache()["spells"]
	while sheet.level < level:
		sheet.xp = maxi(sheet.xp, Experience.xp_for_level(sheet.level + 1))
		var ch := LevelUp.choices(sheet)
		var cantrips: Array[String] = []
		var leveled: Array[String] = []
		for id in DictUtil.to_string_array(ch["spell_options"]):
			var sp: SpellDefinition = spells.get(id)
			if sp == null:
				continue
			if sp.level == 0 and cantrips.size() < int(ch["cantrips_to_learn"]):
				cantrips.append(id)
			elif sp.level > 0 and leveled.size() < int(ch["spells_to_learn"]):
				leveled.append(id)
		var made := {"hp": "average", "learn_cantrips": cantrips, "learn_spells": leveled}
		for entry: Dictionary in ch["choices"]:
			var opts := DictUtil.to_string_array(entry["options"]).slice(0, int(entry["count"]))
			match str(entry["type"]):
				"subclass", "fighting_style":
					made[str(entry["type"])] = opts[0]
				"feature_option":
					var fo: Dictionary = made.get("feature_options", {})
					fo[str(entry["feature"])] = opts[0]
					made["feature_options"] = fo
				_:
					made[str(entry["type"])] = opts
		if bool(ch["asi"]):
			for ability: String in ["STR", "DEX", "CON", "INT", "WIS", "CHA"]:
				if sheet.abilities.get_score(Ability.from_string(ability)) <= 18:
					made["asi"] = {ability: 2}
					break
		assert_eq(LevelUp.apply(sheet, made, {}, null), "", "%s to level %d" % [sheet.class_id, sheet.level + 1])


## A sheet of class_id at `level` with 200 hp (see _class_sheet).
func _leveled_sheet(class_id: String, level: int) -> CharacterSheet:
	var sheet := _class_sheet(class_id)
	_level_to(sheet, level)
	sheet.xp = Experience.xp_for_level(level)
	sheet.max_hp = 200
	sheet.current_hp = 200
	return sheet


## Walks into z1 (rat at (8,2) with `rat_hp` hp) and waits for p1's turn.
func _fight_rat(sheet: CharacterSheet, rat_hp: int = 500) -> Encounter:
	_setup(false, sheet)
	var rat := server.get_entity(RAT).sheet
	rat.max_hp = rat_hp
	rat.current_hp = rat_hp
	_walk_to(Vector2i(10, 1))
	var enc := _wait_for_my_turn()
	assert_not_null(enc, "p1's turn comes")
	results.clear()
	return enc


func _melee_index(sheet: CharacterSheet) -> int:
	for i in range(sheet.attacks.size()):
		if str(sheet.attacks[i].get("kind", "")) == "melee" and sheet.attacks[i].get("off_hand", false) != true:
			return i
	return sheet.attacks.size()  # the unarmed strike


## Steps p1 next to the rat (on its turn) when it is not adjacent yet.
func _close_in(enc: Encounter) -> void:
	var me := enc.get_combatant("p1")
	var rat := enc.get_combatant(RAT)
	if GridMath.is_adjacent(me.position, rat.position):
		return
	var path := enc.walk_map.path_to(me.position, rat.position, enc.occupied_cells("p1"))
	path.resize(mini(path.size() - 1, me.movement_remaining))
	_send(Messages.MOVE, {"path": GridMath.vec_list_to_arr(path)})
	_tick()
	_flush()


func test_wizard_fireball_area_through_the_server() -> void:
	var sheet := _class_sheet("wizard", "Mage")
	sheet.spells_known.append("fireball")
	sheet.spells_prepared.append("fireball")
	sheet.spell_slots_max = [4, 3, 2] as Array[int]
	sheet.spell_slots = [4, 3, 2] as Array[int]
	var enc := _fight_rat(sheet, 7)
	_send(Messages.CAST, {"spell": "fireball", "slot_level": 3, "point": [8, 2]})
	_tick()
	_flush()
	assert_eq(_of_kind(Messages.ERROR).size(), 0, str(_of_kind(Messages.ERROR)))
	var cast := _events_of("cast", "spell", "fireball")
	assert_eq(cast.size(), 1)
	assert_eq(cast[0]["point"], [8, 2])
	assert_eq(int(cast[0]["slot_level"]), 3)
	var area := _events_of("area_effect", "spell", "fireball")
	assert_eq(area.size(), 1, "area_effect broadcast")
	assert_eq(str(area[0]["shape"]), "sphere")
	assert_has(area[0]["affected"], RAT)
	assert_true(_has_event("save", "target", RAT), "the rat saves")
	assert_true(_has_event("damage", "spell", "fireball"), "fire damage")
	assert_eq(server.get_entity("p1").sheet.slots_left(3), 1, "a 3rd-level slot was spent")
	assert_true(enc != null)


func test_fighter_extra_attack_sequence() -> void:
	var sheet := _leveled_sheet("fighter", 5)
	assert_eq(sheet.attacks_per_action(), 2, "Extra Attack at level 5")
	var enc := _fight_rat(sheet)
	_close_in(enc)
	results.clear()
	var index := _melee_index(sheet)
	_send(Messages.ATTACK, {"target": RAT, "attack_index": index})
	_tick()
	_send(Messages.ATTACK, {"target": RAT, "attack_index": index})
	_tick()
	_flush()
	assert_eq(_of_kind(Messages.ERROR).size(), 0, "two attacks per Attack action: %s" % str(_of_kind(Messages.ERROR)))
	assert_eq(_events_of("attack", "attacker", "p1").size(), 2)
	_send(Messages.ATTACK, {"target": RAT, "attack_index": index})
	_tick()
	_flush()
	assert_eq(_of_kind(Messages.ERROR).size(), 1, "a third attack needs Action Surge")
	_send(Messages.USE_FEATURE, {"feature": "action_surge"})
	_send(Messages.ATTACK, {"target": RAT, "attack_index": index})
	_tick()
	_flush()
	assert_eq(_of_kind(Messages.ERROR).size(), 1, "Action Surge gives the action back")
	assert_true(_has_event("feature_used", "feature", "action_surge"))
	assert_eq(_events_of("attack", "attacker", "p1").size(), 3)


func test_stunned_monster_skips_its_turn() -> void:
	var sheet := _leveled_sheet("monk", 5)
	assert_true(sheet.has_feature("stunning_strike"))
	var enc := _fight_rat(sheet)
	sheet = server.get_entity("p1").sheet  # the server's copy
	var stunned := false
	for _round in range(12):
		_close_in(enc)
		var me := enc.get_combatant("p1")
		if not me.action_used and sheet.class_resource("ki") > 0:
			_send(Messages.ATTACK, {"target": RAT, "attack_index": _melee_index(sheet), "stun": true})
			_tick()
			_flush()
		if _has_event("condition_applied", "condition", "stunned"):
			stunned = true
			break
		_send(Messages.END_TURN)
		_tick()
		if _wait_for_my_turn() == null:
			break
	assert_true(stunned, "Stunning Strike landed within a few rounds (seed %d)" % SEED)
	assert_eq(_of_kind(Messages.ERROR).size(), 0, str(_of_kind(Messages.ERROR)))
	assert_true(_has_event("feature_used", "feature", "stunning_strike"))
	results.clear()
	_send(Messages.END_TURN)
	_tick()
	assert_not_null(_wait_for_my_turn(), "back to p1 after the rat's skipped turn")
	var rat_turn := false
	var rat_acted := false
	for e in _all_events():
		if str(e["kind"]) == "turn_started" and str(e["actor"]) == RAT:
			rat_turn = true
		if str(e["kind"]) in ["attack", "moved"] and str(e.get("attacker", e.get("actor", ""))) == RAT:
			rat_acted = true
	assert_true(rat_turn, "the rat's turn started")
	assert_false(rat_acted, "a stunned rat neither moves nor attacks")


func test_paladin_divine_smite_spends_a_slot_on_a_hit() -> void:
	var sheet := _leveled_sheet("paladin", 2)
	assert_true(sheet.has_feature("divine_smite"))
	var enc := _fight_rat(sheet)
	sheet = server.get_entity("p1").sheet  # the server's copy
	var slots := sheet.slots_left(1)
	assert_true(slots > 0)
	var hit := false
	for _round in range(10):
		_close_in(enc)
		results.clear()
		_send(Messages.ATTACK, {"target": RAT, "attack_index": _melee_index(sheet), "smite": 1})
		_tick()
		_flush()
		assert_eq(_of_kind(Messages.ERROR).size(), 0, str(_of_kind(Messages.ERROR)))
		var attack := _events_of("attack", "attacker", "p1")
		if not attack.is_empty() and bool(attack[0]["hit"]):
			hit = true
			break
		assert_eq(sheet.slots_left(1), slots, "a miss keeps the slot")
		_send(Messages.END_TURN)
		_tick()
		if _wait_for_my_turn() == null:
			break
	assert_true(hit, "the paladin hit within a few rounds")
	assert_true(_has_event("feature_used", "feature", "divine_smite"), "smite reported")
	var smitten := false
	for e in _events_of("damage", "target", RAT):
		for x: Variant in (e.get("extra", []) as Array):
			if str((x as Dictionary).get("source", "")) == "divine_smite":
				smitten = true
	assert_true(smitten, "radiant smite dice in the damage extras")
	assert_eq(sheet.slots_left(1), slots - 1, "the slot is spent on the hit")


func test_level_3_subclass_choice_round_trip() -> void:
	var sheet := _class_sheet("fighter")
	_level_to(sheet, 2)
	sheet.xp = Experience.xp_for_level(3)
	_setup(true, sheet)
	_flush()
	var offer: Dictionary = _last(Messages.LEVEL_UP_AVAILABLE)["choices"]
	assert_eq(int(offer["new_level"]), 3)
	var sub: Dictionary = {}
	for entry: Dictionary in offer["choices"]:
		if str(entry["type"]) == "subclass":
			sub = entry
	assert_false(sub.is_empty(), "the level 3 offer asks for the subclass")
	assert_eq(DictUtil.to_string_array(sub["options"]), ["champion"] as Array[String])
	var detail_ids: Array[String] = []
	for d: Dictionary in offer["features_detail"]:
		detail_ids.append(str(d["id"]))
	assert_has(detail_ids, "improved_critical", "subclass features are listed")
	_send(Messages.LEVEL_UP, {"choices": {"hp": "average", "subclass": "berserker"}})
	_tick()
	_flush()
	assert_has(str(_last(Messages.ERROR)["message"]), "not a subclass option")
	results.clear()
	_send(Messages.LEVEL_UP, {"choices": {"hp": "average", "subclass": "champion"}})
	_tick()
	_flush()
	var state := _last(Messages.CHARACTER_STATE)
	assert_eq(int(state.get("leveled_to", 0)), 3)
	assert_eq(str(state["sheet"]["subclass_id"]), "champion")
	var p1 := server.get_entity("p1").sheet
	assert_eq(p1.subclass_id, "champion")
	assert_true(p1.has_feature("improved_critical"))


func test_concentration_broken_by_damage() -> void:
	var sheet := _class_sheet("warlock", "Hexer")
	sheet.abilities.set_score(Ability.Type.CON, 1)  # CON save -5: the check fails
	sheet.unequip(CharacterSheet.SLOT_ARMOR, {})
	sheet.abilities.set_score(Ability.Type.DEX, 1)  # AC 5: the rat hits
	var enc := _fight_rat(sheet)
	_send(Messages.CAST, {"spell": "hex", "target": RAT})
	_tick()
	_flush()
	assert_eq(_of_kind(Messages.ERROR).size(), 0, str(_of_kind(Messages.ERROR)))
	assert_true(_has_event("concentration_started", "spell", "hex"), "hex needs concentration")
	var broken := false
	for _round in range(10):
		_send(Messages.END_TURN)
		_tick()
		if _wait_for_my_turn() == null:
			break
		if _has_event("concentration_ended", "reason", "damage"):
			broken = true
			break
	assert_true(broken, "the rat's hit broke concentration")
	assert_true(_has_event("concentration_check", "success", false))
	assert_true(_has_event("effect_ended", "effect", "hex"), "the hex mark ends with it")
	assert_true(enc.get_combatant("p1").concentration.is_empty())


func test_short_rest_recovers_slots_on_request() -> void:
	var sheet := _class_sheet("wizard", "Mage")
	_level_to(sheet, 3)
	sheet.spell_slots[0] = 0
	sheet.spell_slots[1] = 0
	_setup(true, sheet)
	_walk_to(Vector2i(10, 4))
	results.clear()
	_send(Messages.SHORT_REST, {"hit_dice": 0, "recover_slots": true})
	_tick()
	_flush()
	var state := _last(Messages.CHARACTER_STATE)
	assert_eq(state.get("slots_recovered", []), [2], "budget 2 (half of level 3, rounded up): one 2nd-level slot")
	var p1 := server.get_entity("p1").sheet
	assert_eq(p1.slots_left(2), 1)
	assert_eq(p1.slots_left(1), 0)
	results.clear()
	_send(Messages.SHORT_REST, {"hit_dice": 0, "recover_slots": [1]})
	_tick()
	_flush()
	state = _last(Messages.CHARACTER_STATE)
	assert_false(state.has("slots_recovered"), "once per long rest")
	assert_has(str(state.get("recovery_error", "")), "no slot recovery")
	assert_eq(p1.slots_left(1), 0)


func test_stand_intent_reaches_the_encounter() -> void:
	var enc := _fight_rat(_fighter())
	_send(Messages.STAND)
	_tick()
	_flush()
	assert_has(str(_last(Messages.ERROR).get("message", "")), "not prone", "the encounter judged stand")
	enc.get_combatant("p1").conditions.append({"condition": "prone", "source": RAT,
		"duration": {"type": "encounter"}, "turns_left": 0})
	_send(Messages.STAND)
	_tick()
	_flush()
	assert_eq(_of_kind(Messages.ERROR).size(), 1, "a prone fighter stands up")
	assert_false(enc.get_combatant("p1").has_condition("prone"))


func test_reaction_policy_is_stored_and_handed_to_encounters() -> void:
	_setup()
	_send(Messages.REACTION_POLICY, {"policy": {"creature_left_reach": "never"}})
	_tick()
	_flush()
	assert_eq(_of_kind(Messages.ERROR).size(), 0)
	var state := _last(Messages.CHARACTER_STATE)
	assert_eq(state.get("reaction_policy", {}), {"creature_left_reach": "never"})
	assert_eq(server.get_entity("p1").reaction_policy, {"creature_left_reach": "never"})
	_walk_to(Vector2i(10, 1))
	var enc := server.get_encounter_for("p1")
	assert_not_null(enc)
	var me := enc.get_combatant("p1")
	assert_eq(me.reaction_policy, {"creature_left_reach": "never"}, "the combatant joins with the policy")
	# Off-turn changes reach the active encounter too.
	_send(Messages.REACTION_POLICY, {"policy": {"creature_left_reach": "auto", "creature_hit_me": "never"}})
	_tick()
	_flush()
	assert_eq(_of_kind(Messages.ERROR).size(), 0, "allowed any time")
	assert_eq(me.reaction_policy, {"creature_left_reach": "auto", "creature_hit_me": "never"})


## Sets p1's policy while exploring (when given), walks into z1 next to the
## rat, ends the turn and makes the rat walk out of p1's reach. True when p1
## made an opportunity attack.
func _rat_walks_away(policy: Dictionary) -> bool:
	var sheet := _fighter()
	sheet.max_hp = 200
	sheet.current_hp = 200
	_setup(false, sheet)
	var rat := server.get_entity(RAT).sheet
	rat.max_hp = 500
	rat.current_hp = 500
	if not policy.is_empty():
		_send(Messages.REACTION_POLICY, {"policy": policy})
		_tick()
		_flush()
		assert_false(server.get_entity("p1").in_combat(), "the policy was set out of combat")
	_walk_to(Vector2i(10, 1))
	var enc := _wait_for_my_turn()
	assert_not_null(enc, "p1's turn comes")
	assert_eq(enc.get_combatant("p1").reaction_policy, policy, "the encounter got the stored policy")
	_close_in(enc)
	_send(Messages.END_TURN)
	_tick()
	_flush()
	var rat_c := enc.get_combatant(RAT)
	assert_eq(enc.current_actor(), rat_c, "the rat's turn, not resolved yet")
	var me := enc.get_combatant("p1")
	assert_true(GridMath.is_adjacent(me.position, rat_c.position), "the rat starts next to p1")
	var path: Array[Vector2i] = []
	for y in range(enc.region.position.y, enc.region.end.y):
		for x in range(enc.region.position.x, enc.region.end.x):
			var t := Vector2i(x, y)
			if GridMath.distance_tiles(t, me.position) < 2 or not path.is_empty():
				continue
			var p := enc.walk_map.path_to(rat_c.position, t, enc.occupied_cells(RAT))
			if not p.is_empty() and p.size() <= rat_c.movement_remaining:
				path = p
	assert_false(path.is_empty(), "a tile out of reach")
	var res := enc.submit(Messages.make_intent(Messages.MOVE, {"actor": RAT, "path": GridMath.vec_list_to_arr(path)}))
	assert_true(res.get("ok", false), str(res.get("error", "")))
	for ev: Dictionary in res.get("events", []):
		if str(ev.get("kind", "")) == "opportunity_attack" and str(ev.get("attacker", "")) == "p1":
			return true
	return false


func test_reaction_policy_set_out_of_combat_applies_in_the_next_encounter() -> void:
	assert_true(_rat_walks_away({}), "by default p1 makes the opportunity attack")
	server.free()
	before_each()
	assert_false(_rat_walks_away({"creature_left_reach": "never"}), "never: no opportunity attack")


func test_reaction_policy_persists_to_the_next_floor() -> void:
	_setup_set(_fighter())
	_send(Messages.REACTION_POLICY, {"policy": {"creature_hit_me": "never", "uncanny_dodge": "auto"}})
	_tick()
	_flush()
	server._enter_floor(1, _floor_b())
	_walk_to(Vector2i(2, 3))
	var enc := server.get_encounter_for("p1")
	assert_not_null(enc, "floor B's zone starts a fight")
	assert_eq(enc.get_combatant("p1").reaction_policy, {"creature_hit_me": "never", "uncanny_dodge": "auto"})
	assert_eq(enc.setup_snapshot().filter(func(d: Dictionary) -> bool: return str(d.get("id", "")) == "p1")[0].get("reaction_policy"),
		{"creature_hit_me": "never", "uncanny_dodge": "auto"}, "part of the replay setup")


# --- out-of-combat casting -------------------------------------------------------------

func _wizard_with_familiar() -> CharacterSheet:
	var sheet := _class_sheet("wizard", "Mage")
	for list: Array[String] in [sheet.spells_known, sheet.spells_prepared]:
		if not list.has("find_familiar"):
			list.append("find_familiar")
	return sheet


func test_find_familiar_out_of_combat_adds_a_companion_that_joins_the_next_fight() -> void:
	_setup(false, _wizard_with_familiar())
	_flush()
	results.clear()
	_send(Messages.CAST, {"spell": "find_familiar", "slot_level": 1, "form": "cat"})
	_tick()
	_flush()
	assert_eq(_of_kind(Messages.ERROR).size(), 0, str(_of_kind(Messages.ERROR)))
	var kinds: Array[String] = []
	for r in results:
		kinds.append(str(r["kind"]))
		assert_eq(Messages.validate_result(r), "", "well-formed %s" % str(r["kind"]))
	assert_eq(kinds, [Messages.OUT_OF_COMBAT_EVENTS, Messages.CHARACTER_STATE] as Array[String])
	var ooc := results[0]
	assert_eq(str(ooc["entity_id"]), "p1")
	assert_eq(str(ooc["spell"]), "find_familiar")
	assert_eq(int(ooc["slot_level"]), 1)
	var events: Array = ooc["events"]
	assert_eq(str(events[0]["kind"]), "cast")
	assert_eq(str(events[0]["casting_time"]), "1_hour", "a long casting time resolves at once in M2")
	assert_true(events[0]["ritual"] == true)
	assert_eq(str(events[1]["kind"]), "companion_summoned")
	assert_eq(str(events[1]["monster"]), "cat")
	assert_eq(events[1]["companion_ids"], ["c1"])
	var me := server.get_entity("p1")
	assert_eq(me.sheet.companions.size(), 1)
	assert_eq(str(me.sheet.companions[0]["monster"]), "cat")
	assert_eq(str(me.sheet.companions[0]["id"]), "c1")
	assert_eq(me.sheet.slots_left(1), 1, "a 1st-level slot was spent")
	var state := results[1]
	assert_eq(str(state["spell_cast"]), "find_familiar")
	assert_eq(str((state["sheet"]["companions"] as Array)[0]["id"]), "c1", "the client sees the id")
	# The next encounter spawns it next to its owner.
	_walk_to(Vector2i(10, 1))
	var enc := server.get_encounter_for("p1")
	assert_not_null(enc)
	var familiar: Dictionary = {}
	for e in _all_events():
		if str(e.get("kind", "")) == "combatant_joined" and str(e.get("owner", "")) == "p1":
			familiar = e
	assert_false(familiar.is_empty(), "combatant_joined with owner p1")
	var fam := enc.get_combatant(str(familiar["id"]))
	assert_not_null(fam)
	assert_eq(fam.monster_id, "cat")
	assert_true(GridMath.distance_tiles(fam.position, enc.get_combatant("p1").position) <= 1, "beside the owner")


func test_cure_wounds_out_of_combat_heals_and_spends_a_slot() -> void:
	var sheet := _class_sheet("cleric", "Priest")
	sheet.current_hp = 100
	_setup(true, sheet)
	_flush()
	results.clear()
	_send(Messages.CAST, {"spell": "cure_wounds", "target": "p1"})
	_tick()
	_flush()
	assert_eq(_of_kind(Messages.ERROR).size(), 0, str(_of_kind(Messages.ERROR)))
	var me := server.get_entity("p1")
	assert_true(me.sheet.current_hp > 100, "healed")
	assert_eq(me.sheet.slots_left(1), 1, "a slot spent")
	var ooc := _last(Messages.OUT_OF_COMBAT_EVENTS)
	var heal: Dictionary = (ooc["events"] as Array)[1]
	assert_eq(str(heal["kind"]), "heal")
	assert_eq(int(heal["amount"]), me.sheet.current_hp - 100)
	assert_eq(int(heal["hp_after"]), me.sheet.current_hp)
	assert_eq(int(_last(Messages.CHARACTER_STATE)["sheet"]["current_hp"]), me.sheet.current_hp)
	# Same seed, same heal: the cast stream is deterministic.
	var healed := me.sheet.current_hp
	server.free()
	before_each()
	var again := _class_sheet("cleric", "Priest")
	again.current_hp = 100
	_setup(true, again)
	_send(Messages.CAST, {"spell": "cure_wounds"})
	_tick()
	_flush()
	assert_eq(server.get_entity("p1").sheet.current_hp, healed)


func test_out_of_combat_cast_rejections() -> void:
	var sheet := _wizard_with_familiar()
	_setup(true, sheet)
	_flush()
	var me := server.get_entity("p1")
	var cases: Array[Array] = [
		[{"spell": "fire_bolt", "target": RAT}, "yourself"],
		[{"spell": "fire_bolt"}, "outside a fight"],
		[{"spell": "magic_missile"}, "outside a fight"],
		[{"spell": "cure_wounds"}, "has not prepared"],
		[{"spell": "no_such_spell"}, "unknown spell"],
		[{"spell": "find_familiar", "form": "ogre"}, "cannot bring"],
	]
	for c in cases:
		results.clear()
		_send(Messages.CAST, c[0])
		_tick()
		_flush()
		var errors := _of_kind(Messages.ERROR)
		assert_eq(errors.size(), 1, "rejected: %s" % str(c[0]))
		if errors.size() == 1:
			assert_has(str(errors[0]["message"]), str(c[1]))
		assert_eq(_of_kind(Messages.OUT_OF_COMBAT_EVENTS).size(), 0)
	assert_eq(me.sheet.slots_left(1), 2, "no slot spent by a rejected cast")
	assert_true(me.sheet.companions.is_empty())
	# No slot left.
	me.sheet.use_spell_slot(1)
	me.sheet.use_spell_slot(1)
	results.clear()
	_send(Messages.CAST, {"spell": "find_familiar"})
	_tick()
	_flush()
	assert_has(str(_last(Messages.ERROR).get("message", "")), "no level 1+ spell slot")
	# Unconscious, then dead.
	me.sheet.spell_slots[0] = 2
	me.sheet.current_hp = 0
	_send(Messages.CAST, {"spell": "find_familiar"})
	_tick()
	_flush()
	assert_has(str(_last(Messages.ERROR).get("message", "")), "cannot cast")
	me.sheet.kill()
	_send(Messages.CAST, {"spell": "find_familiar"})
	_tick()
	_flush()
	assert_has(str(_last(Messages.ERROR).get("message", "")), "is dead")
	assert_true(me.sheet.companions.is_empty())


func test_dismiss_companion() -> void:
	_setup(false, _wizard_with_familiar())
	_send(Messages.CAST, {"spell": "find_familiar"})
	_tick()
	_flush()
	var me := server.get_entity("p1")
	assert_eq(me.sheet.companions.size(), 1)
	results.clear()
	_send(Messages.DISMISS_COMPANION, {"companion_id": "c9"})
	_tick()
	_flush()
	assert_has(str(_last(Messages.ERROR).get("message", "")), "no companion 'c9'")
	_send(Messages.DISMISS_COMPANION, {"companion_id": "c1"})
	_tick()
	_flush()
	assert_true(me.sheet.companions.is_empty(), "dismissed")
	var state := _last(Messages.CHARACTER_STATE)
	assert_eq(state.get("companion_dismissed"), {"id": "c1", "monster": "owl"})
	assert_eq((state["sheet"]["companions"] as Array).size(), 0)
	# A new familiar gets a fresh id; dismissing is refused in a fight.
	_send(Messages.CAST, {"spell": "find_familiar"})
	_tick()
	_flush()
	assert_eq(str(me.sheet.companions[0]["id"]), "c2")
	_walk_to(Vector2i(10, 1))
	assert_true(me.in_combat())
	results.clear()
	_send(Messages.DISMISS_COMPANION, {"companion_id": "c2"})
	_tick()
	_flush()
	assert_has(str(_last(Messages.ERROR).get("message", "")), "in combat")
	assert_eq(me.sheet.companions.size(), 1)

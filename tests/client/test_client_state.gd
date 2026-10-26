extends TestCase
## ClientState: server results in, view-model out. No Nodes involved.

const PID := "p1"
const GOBLIN := "z1_goblin_0"
const RAT := "z1_giant_rat_1"


func _floor_dict() -> Dictionary:
	return {
		"schema_version": 1,
		"id": "test_floor",
		"display_name": "Test Floor",
		"rows": [
			"############",
			"#..........#",
			"#..........#",
			"#..........#",
			"#..........#",
			"#..........#",
			"############",
		],
		"arrival": [1, 1],
		"stairs": [10, 5],
		"encounter_zones": [
			{"id": "z1", "rect": [4, 1, 5, 5], "monster_ids": ["goblin", "giant_rat"], "spawn_points": [[7, 3], [8, 5]]},
		],
	}


func _sheet_dict(hp: int = 12) -> Dictionary:
	var s := CharacterSheet.new()
	s.name = "Tess"
	s.class_id = "fighter"
	s.max_hp = hp
	s.current_hp = hp
	s.speed = 30
	s.hit_dice_remaining = 1
	return s.to_dict()


func _ent(id: String, kind: String, pos: Array) -> Dictionary:
	return {"id": id, "kind": kind, "position": pos, "name": id.capitalize()}


func _explore(entities: Array, tick: int = 1) -> Dictionary:
	return Messages.make_result(Messages.EXPLORE_STATE, {"entities": entities, "tick": tick})


func _events(events: Array, enc_id: String = "z1") -> Dictionary:
	return Messages.make_result(Messages.ENCOUNTER_EVENTS, {"events": events, "encounter_id": enc_id, "zone_id": "z1"})


## A loaded client: floor, sheet, the player at (4, 3), goblin at (7, 3), rat at (8, 5).
func _loaded() -> ClientState:
	var st := ClientState.new(PID)
	st.apply(Messages.make_result(Messages.FLOOR_LOADED, {"floor": _floor_dict()}))
	st.apply(Messages.make_result(Messages.CHARACTER_STATE, {"sheet": _sheet_dict()}))
	st.apply(_explore([
		_ent(PID, "player", [4, 3]),
		_ent(GOBLIN, "monster", [7, 3]),
		_ent(RAT, "monster", [8, 5]),
	]))
	return st


## _loaded() plus an encounter in which the goblin acts first, then the player.
func _in_combat() -> ClientState:
	var st := _loaded()
	st.apply(_events([
		{"kind": "combatant_joined", "id": PID, "initiative": 12, "position": [4, 3]},
		{"kind": "combatant_joined", "id": GOBLIN, "initiative": 15, "position": [7, 3]},
		{"kind": "combatant_joined", "id": RAT, "initiative": 5, "position": [8, 5]},
		{"kind": "encounter_started", "order": [GOBLIN, PID, RAT]},
		{"kind": "round_started", "round": 1},
		{"kind": "turn_started", "actor": GOBLIN, "round": 1},
	]))
	return st


func _my_turn() -> ClientState:
	var st := _in_combat()
	st.apply(_events([
		{"kind": "turn_ended", "actor": GOBLIN},
		{"kind": "turn_started", "actor": PID, "round": 1},
	]))
	return st


func test_starts_loading_and_floor_loaded_switches_to_exploring() -> void:
	var st := ClientState.new(PID)
	assert_eq(st.mode, ClientState.Mode.LOADING)
	st.apply(Messages.make_result(Messages.FLOOR_LOADED, {"floor": _floor_dict(), "entity_id": "p7"}))
	assert_eq(st.mode, ClientState.Mode.EXPLORING)
	assert_not_null(st.floor_data)
	assert_eq(st.floor_data.id, "test_floor")
	assert_eq(st.floor_data.stairs, Vector2i(10, 5))
	assert_eq(st.player_id, "p7", "adopts the server's entity_id")
	assert_eq(st.mode_text(), "Exploring")


func test_player_id_for_peer() -> void:
	assert_eq(ClientState.player_id_for_peer(1), "p1")
	assert_eq(ClientState.player_id_for_peer(42), "p42")


func test_character_state_sets_sheet() -> void:
	var st := _loaded()
	assert_not_null(st.sheet)
	assert_eq(st.sheet.name, "Tess")
	assert_eq(st.sheet.current_hp, 12)
	assert_eq(st.speed_tiles(), 6)
	assert_eq(st.display_name(PID), "Tess")
	assert_eq(int(st.get_entity(PID)["hp"]), 12)


func test_explore_state_replaces_entities() -> void:
	var st := _loaded()
	assert_eq(st.entities.size(), 3)
	assert_eq(st.player_position(), Vector2i(4, 3))
	assert_eq(str(st.get_entity(GOBLIN)["kind"]), "monster")
	st.apply(_explore([_ent(PID, "player", [5, 3]), _ent(GOBLIN, "monster", [7, 3])], 2))
	assert_eq(st.entities.size(), 2, "the rat is gone")
	assert_eq(st.player_position(), Vector2i(5, 3))
	assert_eq(st.tick, 2)
	assert_eq(st.display_name(GOBLIN), GOBLIN.capitalize())


func test_explore_state_reads_hp_and_dead() -> void:
	var st := _loaded()
	var e := _ent(GOBLIN, "monster", [7, 3])
	e["hp"] = 4
	e["max_hp"] = 7
	st.apply(_explore([_ent(PID, "player", [4, 3]), e]))
	assert_eq(int(st.get_entity(GOBLIN)["hp"]), 4)
	assert_eq(int(st.get_entity(GOBLIN)["max_hp"]), 7)
	e["hp"] = 0
	e["dead"] = true
	st.apply(_explore([_ent(PID, "player", [4, 3]), e]))
	assert_true(bool(st.get_entity(GOBLIN)["dead"]))
	assert_false(bool(st.get_entity(GOBLIN)["down"]))


func test_encounter_start_enters_combat_with_order() -> void:
	var st := _in_combat()
	assert_eq(st.mode, ClientState.Mode.COMBAT)
	assert_true(st.in_encounter)
	assert_eq(st.encounter_id, "z1")
	assert_eq(st.order, [GOBLIN, PID, RAT] as Array[String])
	assert_eq(st.region, Rect2i(4, 1, 5, 5))
	assert_eq(st.round_number, 1)
	assert_eq(st.current_actor, GOBLIN)
	assert_false(st.is_my_turn())
	assert_eq(int(st.initiatives[GOBLIN]), 15)
	assert_has(st.mode_text(), "turn")


func test_turn_started_resets_movement_and_action() -> void:
	var st := _my_turn()
	assert_true(st.is_my_turn())
	assert_eq(st.current_actor, PID)
	assert_eq(st.movement_remaining, 6)
	assert_false(st.action_used)
	assert_eq(st.mode_text(), "Combat: your turn (round 1)")


func test_moved_and_dash_track_movement() -> void:
	var st := _my_turn()
	st.apply(_events([
		{"kind": "moved", "actor": PID, "from": [4, 3], "to": [5, 3]},
		{"kind": "moved", "actor": PID, "from": [5, 3], "to": [6, 3]},
	]))
	assert_eq(st.movement_remaining, 4)
	assert_eq(st.player_position(), Vector2i(6, 3))
	st.apply(_events([{"kind": "dash", "actor": PID}]))
	assert_eq(st.movement_remaining, 10)
	assert_true(st.action_used)
	assert_false(st.can_take_action())
	# Somebody else's movement does not touch ours.
	st.apply(_events([{"kind": "moved", "actor": RAT, "from": [8, 5], "to": [8, 4]}]))
	assert_eq(st.movement_remaining, 10)
	assert_eq(Vector2i(st.get_entity(RAT)["position"]), Vector2i(8, 4))


func test_own_attack_uses_action_but_opportunity_attack_does_not() -> void:
	var st := _in_combat()
	st.apply(_events([
		{"kind": "opportunity_attack", "attacker": PID, "target": GOBLIN},
		{"kind": "attack", "attacker": PID, "target": GOBLIN, "attack_name": "Longsword", "natural": 3,
			"d20s": [3], "total": 8, "target_ac": 15, "hit": false, "critical": false, "fumble": false, "advantage": "normal"},
		{"kind": "turn_ended", "actor": GOBLIN},
		{"kind": "turn_started", "actor": PID, "round": 1},
	]))
	assert_false(st.action_used, "a reaction on the goblin's turn")
	st.apply(_events([
		{"kind": "attack", "attacker": PID, "target": GOBLIN, "attack_name": "Longsword", "natural": 17,
			"d20s": [17], "total": 22, "target_ac": 15, "hit": true, "critical": false, "fumble": false, "advantage": "normal"},
		{"kind": "damage", "target": GOBLIN, "amount": 9, "type": "slashing", "hp_after": 0, "dropped": true, "died": true},
	]))
	assert_true(st.action_used)
	assert_true(bool(st.get_entity(GOBLIN)["dead"]))
	assert_eq(st.hostile_at(Vector2i(7, 3)), "", "the dead are not hostiles")


func test_damage_and_death_saves_update_player_sheet() -> void:
	var st := _in_combat()
	st.apply(_events([
		{"kind": "attack", "attacker": GOBLIN, "target": PID, "attack_name": "Scimitar", "natural": 20,
			"d20s": [20], "total": 24, "target_ac": 16, "hit": true, "critical": true, "fumble": false, "advantage": "normal"},
		{"kind": "damage", "target": PID, "amount": 5, "type": "slashing", "hp_after": 7, "dropped": false, "died": false},
	]))
	assert_eq(st.sheet.current_hp, 7)
	assert_eq(int(st.get_entity(PID)["hp"]), 7)
	st.apply(_events([{"kind": "damage", "target": PID, "amount": 9, "type": "slashing", "hp_after": 0, "dropped": true, "died": false}]))
	assert_eq(st.sheet.current_hp, 0)
	assert_true(bool(st.get_entity(PID)["down"]))
	assert_false(st.is_player_conscious())
	st.apply(_events([
		{"kind": "turn_ended", "actor": GOBLIN},
		{"kind": "turn_started", "actor": PID, "round": 1},
		{"kind": "death_save", "actor": PID, "natural": 4, "successes": 0, "failures": 1, "stable": false, "died": false, "regained": false},
		{"kind": "turn_ended", "actor": PID},
	]))
	assert_eq(st.sheet.death_save_failures, 1)
	assert_false(st.is_my_turn(), "a downed player never has an actionable turn")
	st.apply(_events([{"kind": "death_save", "actor": PID, "natural": 20, "successes": 0, "failures": 0, "stable": false, "died": false, "regained": true}]))
	assert_eq(st.sheet.current_hp, 1)
	assert_false(bool(st.get_entity(PID)["down"]))
	st.apply(_events([{"kind": "damage", "target": PID, "amount": 30, "type": "slashing", "hp_after": 0, "dropped": true, "died": true}]))
	assert_true(st.sheet.dead)


func test_encounter_ended_returns_to_exploring_and_drops_the_slain() -> void:
	var st := _my_turn()
	st.apply(_events([
		{"kind": "damage", "target": GOBLIN, "amount": 9, "type": "slashing", "hp_after": 0, "dropped": true, "died": true},
		{"kind": "damage", "target": RAT, "amount": 9, "type": "slashing", "hp_after": 0, "dropped": true, "died": true},
		{"kind": "encounter_ended", "winning_team": 0},
	]))
	assert_eq(st.mode, ClientState.Mode.EXPLORING)
	assert_false(st.in_encounter)
	assert_eq(st.order.size(), 0)
	assert_eq(st.current_actor, "")
	assert_eq(st.last_winning_team, 0)
	assert_false(st.entities.has(GOBLIN))
	assert_true(st.entities.has(PID))
	assert_has(st.log_lines, "Victory! The fight is over.")


func test_round_and_turn_order_progress() -> void:
	var st := _my_turn()
	st.apply(_events([
		{"kind": "turn_ended", "actor": PID},
		{"kind": "turn_started", "actor": RAT, "round": 1},
	]))
	assert_eq(st.current_actor, RAT)
	assert_false(st.is_my_turn())
	st.apply(_events([
		{"kind": "turn_ended", "actor": RAT},
		{"kind": "round_started", "round": 2},
		{"kind": "turn_started", "actor": GOBLIN, "round": 2},
	]))
	assert_eq(st.round_number, 2)
	assert_eq(st.current_actor, GOBLIN)


func test_mid_fight_join_is_ordered_by_initiative() -> void:
	var st := _in_combat()
	st.apply(_events([{"kind": "combatant_joined", "id": "z1_goblin_9", "initiative": 13, "position": [6, 1]}]))
	assert_eq(st.order, [GOBLIN, "z1_goblin_9", PID, RAT] as Array[String])
	assert_eq(str(st.get_entity("z1_goblin_9")["kind"]), "monster")
	st.apply(_events([{"kind": "combatant_removed", "id": "z1_goblin_9"}]))
	assert_eq(st.order, [GOBLIN, PID, RAT] as Array[String])


func test_other_encounters_do_not_hijack_ours() -> void:
	var st := _my_turn()
	st.apply(_events([
		{"kind": "turn_started", "actor": "z2_skeleton_0", "round": 4},
		{"kind": "moved", "actor": "z2_skeleton_0", "from": [3, 3], "to": [3, 4]},
		{"kind": "encounter_ended", "winning_team": 1},
	], "z2"))
	assert_true(st.in_encounter)
	assert_eq(st.current_actor, PID)
	assert_eq(st.round_number, 1)
	assert_eq(Vector2i(st.get_entity("z2_skeleton_0")["position"]), Vector2i(3, 4), "positions still tracked")


func test_encounter_without_player_is_ignored() -> void:
	var st := _loaded()
	st.apply(_events([
		{"kind": "combatant_joined", "id": "p2", "initiative": 10, "position": [7, 1]},
		{"kind": "combatant_joined", "id": GOBLIN, "initiative": 15, "position": [7, 3]},
		{"kind": "encounter_started", "order": [GOBLIN, "p2"]},
		{"kind": "turn_started", "actor": GOBLIN, "round": 1},
	]))
	assert_eq(st.mode, ClientState.Mode.EXPLORING)
	assert_false(st.in_encounter)
	assert_eq(st.current_actor, "")
	assert_eq(str(st.get_entity("p2")["kind"]), "player")
	# Then this player walks in mid-fight.
	st.apply(_events([{"kind": "combatant_joined", "id": PID, "initiative": 20, "position": [6, 2]}]))
	assert_true(st.in_encounter)
	assert_eq(st.mode, ClientState.Mode.COMBAT)
	assert_eq(st.order, [PID, GOBLIN, "p2"] as Array[String])


func test_error_game_over_and_floor_cleared() -> void:
	var st := _loaded()
	st.apply(Messages.make_error("no path to (0, 0)"))
	assert_eq(st.last_error, "no path to (0, 0)")
	assert_has(st.drain_log(), "[!] no path to (0, 0)")
	assert_eq(st.drain_log().size(), 0, "drained")
	st.apply(Messages.make_result(Messages.FLOOR_CLEARED, {"floor_id": "test_floor"}))
	assert_eq(st.mode, ClientState.Mode.FLOOR_CLEARED)
	assert_eq(st.cleared_floor_id, "test_floor")
	var st2 := _in_combat()
	st2.apply(Messages.make_result(Messages.GAME_OVER, {}))
	assert_eq(st2.mode, ClientState.Mode.GAME_OVER)
	assert_false(st2.in_encounter)
	assert_eq(st2.intent_for_click(Vector2i(2, 2)), {})


func test_malformed_result_is_ignored() -> void:
	var st := _loaded()
	var before := st.revision
	st.apply({"v": 1, "kind": "explore_state", "entities": "nope", "tick": 3})
	assert_eq(st.entities.size(), 3)
	assert_eq(st.revision, before + 1)
	assert_true(st.log_lines[st.log_lines.size() - 1].begins_with("[bad message]"))


func test_click_while_exploring_walks() -> void:
	var st := _loaded()
	var intent := st.intent_for_click(Vector2i(2, 2))
	assert_eq(intent.get("type"), Messages.EXPLORE_MOVE)
	assert_eq(intent.get("actor"), PID)
	assert_eq(intent.get("target"), [2, 2])
	assert_eq(Messages.validate_intent(intent), "")
	assert_eq(st.intent_for_click(Vector2i(0, 0)), {}, "walls")
	assert_eq(st.intent_for_click(Vector2i(4, 3)), {}, "own tile")


func test_click_in_combat_moves_attacks_or_nothing() -> void:
	var st := _in_combat()
	assert_eq(st.intent_for_click(Vector2i(5, 3)), {}, "not my turn")
	st.apply(_events([{"kind": "turn_ended", "actor": GOBLIN}, {"kind": "turn_started", "actor": PID, "round": 1}]))
	var move := st.intent_for_click(Vector2i(6, 3))
	assert_eq(move.get("type"), Messages.MOVE)
	assert_eq(move.get("path"), [[5, 3], [6, 3]])
	assert_eq(Messages.validate_intent(move), "")
	assert_eq(st.intent_for_click(Vector2i(2, 3)), {}, "outside the encounter region")
	assert_eq(st.intent_for_click(Vector2i(7, 3)), {}, "goblin is not adjacent yet")
	st.apply(_events([
		{"kind": "moved", "actor": PID, "from": [4, 3], "to": [5, 3]},
		{"kind": "moved", "actor": PID, "from": [5, 3], "to": [6, 3]},
	]))
	var attack := st.intent_for_click(Vector2i(7, 3))
	assert_eq(attack.get("type"), Messages.ATTACK)
	assert_eq(attack.get("target"), GOBLIN)
	assert_eq(attack.get("attack_index"), 0)
	assert_eq(Messages.validate_intent(attack), "")
	assert_true(st.can_attack())
	assert_eq(st.attack_intent().get("target"), GOBLIN)
	st.apply(_events([{"kind": "dodge", "actor": PID}]))
	assert_eq(st.intent_for_click(Vector2i(7, 3)), {}, "action already used")
	assert_false(st.can_attack())


func test_reachable_tiles_respect_budget_region_and_occupants() -> void:
	var st := _my_turn()
	var reach := st.reachable_tiles()
	assert_false(reach.has(Vector2i(4, 3)), "start excluded")
	assert_false(reach.has(Vector2i(7, 3)), "occupied by the goblin")
	assert_false(reach.has(Vector2i(3, 3)), "outside the region")
	assert_true(reach.has(Vector2i(8, 1)))
	# Region is 5x5 = 25 tiles, minus the player, goblin and rat.
	assert_eq(reach.size(), 22)
	for key: Variant in reach.keys():
		assert_true(st.region.has_point(key))
	st.apply(_events([{"kind": "moved", "actor": PID, "from": [4, 3], "to": [4, 4]}]))
	st.movement_remaining = 1
	reach = st.reachable_tiles()
	assert_true(reach.has(Vector2i(5, 5)))
	assert_false(reach.has(Vector2i(6, 4)), "two steps away")
	st.apply(_events([{"kind": "turn_ended", "actor": PID}, {"kind": "turn_started", "actor": RAT, "round": 1}]))
	assert_eq(st.reachable_tiles().size(), 0, "nothing on someone else's turn")


func test_stairs_and_rest_availability() -> void:
	var st := _loaded()
	assert_false(st.on_stairs())
	st.apply(_explore([_ent(PID, "player", [10, 5])]))
	assert_true(st.on_stairs())
	assert_true(st.can_use_stairs())
	assert_false(st.can_short_rest(), "already at full HP")
	var hurt := _sheet_dict()
	hurt["current_hp"] = 5
	st.apply(Messages.make_result(Messages.CHARACTER_STATE, {"sheet": hurt}))
	assert_true(st.can_short_rest())
	var rest := st.short_rest_intent(1)
	assert_eq(rest.get("type"), Messages.SHORT_REST)
	assert_eq(rest.get("hit_dice"), 1)
	assert_eq(Messages.validate_intent(rest), "")
	assert_eq(Messages.validate_intent(st.simple_intent(Messages.USE_STAIRS)), "")
	var healed := _sheet_dict()
	healed["current_hp"] = 11
	st.apply(Messages.make_result(Messages.CHARACTER_STATE, {"sheet": healed, "healed": 6}))
	assert_has(st.log_lines, "Tess regains 6 HP.")


func test_log_describes_attacks() -> void:
	var st := _in_combat()
	st.drain_log()
	st.apply(_events([
		{"kind": "attack", "attacker": GOBLIN, "target": PID, "attack_name": "Scimitar", "natural": 12,
			"d20s": [12, 4], "total": 16, "target_ac": 16, "hit": true, "critical": false, "fumble": false, "advantage": "advantage"},
		{"kind": "damage", "target": PID, "amount": 5, "type": "slashing", "hp_after": 7, "dropped": false, "died": false},
	]))
	var lines := st.drain_log()
	assert_eq(lines.size(), 2)
	assert_eq(lines[0], "%s attacks Tess with Scimitar: 16 vs AC 16 [12/4, advantage], hits." % GOBLIN.capitalize())
	assert_eq(lines[1], "Tess takes 5 slashing damage (7 HP left).")

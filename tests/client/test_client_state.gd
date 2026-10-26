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


# --- five-floor sets, XP ------------------------------------------------------------

func _set_floor_loaded(floor_dict: Dictionary, index: int, count: int = 2) -> Dictionary:
	return Messages.make_result(Messages.FLOOR_LOADED, {"floor": floor_dict, "entity_id": PID,
		"cleared_zones": [], "set_id": "set_t", "set_name": "Test Set", "floor_index": index, "floor_count": count})


func _floor_b_dict() -> Dictionary:
	return {
		"schema_version": 1, "id": "floor_b", "display_name": "Lower Hall", "floor_number": 2,
		"rows": ["#######", "#A...S#", "#######"], "arrival": [1, 1], "stairs": [5, 1],
		"encounter_zones": [{"id": "z1", "rect": [3, 1, 1, 1], "monster_ids": ["goblin"], "spawn_points": [[3, 1]]}],
	}


func test_single_floor_labels() -> void:
	var st := _loaded()
	assert_eq(st.floor_label(), "Floor 1 — Test Floor", "unnumbered floor: place in the set")
	assert_eq(st.stairs_label(), "Descend", "no set")
	assert_false(st.has_next_floor())
	assert_eq(st.level_text(), "Lv 1  XP 0/300")


func test_set_floor_labels_and_stairs_button() -> void:
	var st := ClientState.new(PID)
	st.apply(_set_floor_loaded(_floor_dict(), 0))
	assert_eq(st.set_id, "set_t")
	assert_eq(st.floor_count, 2)
	assert_eq(st.floor_label(), "Floor 1 — Test Floor")
	assert_true(st.has_next_floor())
	assert_eq(st.stairs_label(), "Descend to floor 2")
	st.apply(_set_floor_loaded(_floor_b_dict(), 1))
	assert_eq(st.floor_label(), "Floor 2 — Lower Hall")
	assert_false(st.has_next_floor())
	assert_eq(st.stairs_label(), "Enter the safe zone", "last floor of the set")


func test_repeated_floor_loaded_replaces_the_floor() -> void:
	var st := ClientState.new(PID)
	st.apply(_set_floor_loaded(_floor_dict(), 0))
	st.apply(Messages.make_result(Messages.CHARACTER_STATE, {"sheet": _sheet_dict()}))
	st.apply(_explore([_ent(PID, "player", [10, 5]), _ent(GOBLIN, "monster", [7, 3])]))
	var serial := st.floor_serial
	st.apply(Messages.make_result(Messages.FLOOR_CLEARED, {"floor_id": "test_floor"}))
	assert_eq(st.mode, ClientState.Mode.LOADING, "descending, not the end")
	assert_has(st.log_lines, "Floor cleared! You descend the stairs to floor 2.")
	st.apply(_set_floor_loaded(_floor_b_dict(), 1))
	assert_eq(st.floor_serial, serial + 1, "views rebuild")
	assert_eq(st.mode, ClientState.Mode.EXPLORING)
	assert_eq(st.floor_data.id, "floor_b")
	assert_true(st.entities.is_empty(), "the old floor's entities are gone")
	assert_eq(st.player_position(), Vector2i(1, 1), "arrival until EXPLORE_STATE")
	assert_has(st.log_lines, "You arrive on Floor 2 — Lower Hall.")
	st.apply(_explore([_ent(PID, "player", [1, 1]), _ent("z1_goblin_0", "monster", [3, 1])], 50))
	assert_eq(st.entities.size(), 2)
	assert_eq(st.player_position(), Vector2i(1, 1))
	assert_true(st.sheet != null and st.sheet.name == "Tess", "the sheet survives the descent")


func test_floor_loaded_mid_encounter_resets_combat_state() -> void:
	var st := _in_combat()
	st.apply(_set_floor_loaded(_floor_b_dict(), 1))
	assert_false(st.in_encounter)
	assert_eq(st.order, [] as Array[String])
	assert_eq(st.mode, ClientState.Mode.EXPLORING)


func test_xp_and_level_up_are_logged() -> void:
	var st := _loaded()
	var s := CharacterSheet.from_dict(_sheet_dict())
	s.xp = 315
	s.level = 2
	st.apply(Messages.make_result(Messages.CHARACTER_STATE, {"sheet": s.to_dict(), "xp_gained": 25, "levels_gained": 1}))
	assert_eq(st.last_xp_gained, 25)
	assert_eq(st.last_levels_gained, 1)
	var log := st.drain_log()
	assert_has(log, "Gained 25 XP.")
	assert_has(log, "Level up! Now level 2.")
	assert_eq(st.level_text(), "Lv 2  XP 315/900")
	st.apply(Messages.make_result(Messages.CHARACTER_STATE, {"sheet": s.to_dict(), "xp_gained": 0, "levels_gained": 0}))
	assert_eq(st.drain_log().size(), 0, "nothing to report")


func test_set_cleared_ends_the_run() -> void:
	var st := ClientState.new(PID)
	st.apply(_set_floor_loaded(_floor_b_dict(), 1))
	st.apply(Messages.make_result(Messages.CHARACTER_STATE, {"sheet": _sheet_dict()}))
	st.apply(_explore([_ent(PID, "player", [5, 1])]))
	assert_true(st.can_use_stairs())
	st.apply(Messages.make_result(Messages.FLOOR_CLEARED, {"floor_id": "floor_b"}))
	assert_eq(st.mode, ClientState.Mode.FLOOR_CLEARED, "last floor: no descent")
	st.apply(Messages.make_result(Messages.CHARACTER_STATE, {"sheet": _sheet_dict(), "long_rest": true}))
	assert_has(st.drain_log(), "You take a long rest in the safe zone: HP and Hit Dice restored.")
	st.apply(Messages.make_result(Messages.SET_CLEARED, {"set_id": "set_t"}))
	assert_eq(st.mode, ClientState.Mode.SET_CLEARED)
	assert_eq(st.cleared_set_id, "set_t")
	assert_eq(st.mode_text(), "Set cleared")
	assert_false(st.can_use_stairs())
	assert_eq(st.intent_for_click(Vector2i(2, 1)), {}, "no more walking")


# --- items, chests, spells, features, level-ups (M2) --------------------------------

## A level 1 fighter built from the real content (longsword, chain mail, shield, kit).
func _fighter_sheet_dict(hp: int = 12) -> Dictionary:
	var d := CharacterDraft.new()
	d.character_name = "Tess"
	var classes := ContentLoader.load_classes()
	d.set_class(classes["fighter"])
	d.auto_assign()
	var s := d.build_sheet()
	s.max_hp = hp
	s.current_hp = hp
	return s.to_dict()


func _caster_sheet_dict(class_id: String) -> Dictionary:
	var d := CharacterDraft.new()
	d.character_name = "Ilsa"
	var classes := ContentLoader.load_classes()
	d.set_class(classes[class_id])
	d.auto_assign()
	return d.build_sheet().to_dict()


func _loaded_with(sheet_dict: Dictionary, extra_floor: Dictionary = {}) -> ClientState:
	var st := ClientState.new(PID)
	var fields := {"floor": _floor_dict()}
	fields.merge(extra_floor, true)
	st.apply(Messages.make_result(Messages.FLOOR_LOADED, fields))
	st.apply(Messages.make_result(Messages.CHARACTER_STATE, {"sheet": sheet_dict}))
	st.apply(_explore([
		_ent(PID, "player", [4, 3]),
		{"id": GOBLIN, "kind": "monster", "position": [7, 3], "name": "Goblin", "monster_id": "goblin"},
		{"id": RAT, "kind": "monster", "position": [8, 5], "name": "Giant Rat", "monster_id": "giant_rat"},
	]))
	return st


func _combat_turn(st: ClientState) -> void:
	st.apply(_events([
		{"kind": "combatant_joined", "id": PID, "initiative": 18, "position": [4, 3]},
		{"kind": "combatant_joined", "id": GOBLIN, "initiative": 15, "position": [7, 3]},
		{"kind": "combatant_joined", "id": RAT, "initiative": 5, "position": [8, 5]},
		{"kind": "encounter_started", "order": [PID, GOBLIN, RAT]},
		{"kind": "round_started", "round": 1},
		{"kind": "turn_started", "actor": PID, "round": 1},
	]))


func test_entities_carry_icon_ids() -> void:
	var st := _loaded_with(_fighter_sheet_dict())
	assert_eq(str(st.get_entity(GOBLIN).get("monster_id", "")), "goblin")
	assert_eq(str(st.get_entity(PID).get("class_id", "")), "fighter")
	var icons := EntityIcons.shared()
	assert_eq(icons.column_for_entity(st.get_entity(PID)), 0, "fighter column")
	assert_eq(icons.column_for_entity(st.get_entity(GOBLIN)), 13, "goblin column")
	assert_eq(icons.column_for("consumable"), icons.column_for("potion"), "alias")
	assert_eq(icons.column_for("nope"), -1)
	assert_eq(EntityLayer.icon_for(st.get_entity(PID), icons), 0)
	var down := st.get_entity(PID).duplicate()
	down["down"] = true
	assert_eq(EntityLayer.icon_for(down, icons), -1, "the downed use the unconscious tile")
	assert_eq(EntityLayer.tile_for(down), FloorView.TILE_UNCONSCIOUS)


func test_floor_loaded_chests_and_reveal() -> void:
	var st := _loaded_with(_fighter_sheet_dict(), {"chests": [{"id": "c1", "position": [2, 2], "hidden": false, "opened": false}]})
	assert_eq(st.chests.size(), 1)
	assert_eq(st.chest_at(Vector2i(2, 2)), "c1")
	assert_false(st.can_open_chest("c1"), "too far away")
	st.apply(Messages.make_result(Messages.CHEST_REVEALED, {"chest": {"id": "c2", "position": [5, 3], "hidden": true, "opened": false}}))
	assert_eq(st.visible_chests().size(), 2)
	assert_has(st.log_lines, "You discover a hidden chest!")
	assert_true(st.can_open_chest("c2"), "adjacent")
	var open := st.intent_for_click(Vector2i(5, 3))
	assert_eq(open.get("type"), Messages.OPEN_CHEST)
	assert_eq(open.get("chest_id"), "c2")
	assert_eq(Messages.validate_intent(open), "")
	var walk := st.intent_for_click(Vector2i(2, 2))
	assert_eq(walk.get("type"), Messages.EXPLORE_MOVE, "a far chest: walk onto it first")
	st.apply(Messages.make_result(Messages.CHEST_OPENED, {"chest_id": "c2", "entity_id": PID}))
	assert_true(bool(st.chests["c2"]["opened"]))
	assert_false(st.can_open_chest("c2"), "already open")
	assert_eq(st.intent_for_click(Vector2i(5, 3)).get("type"), Messages.EXPLORE_MOVE)
	assert_eq(st.nearest_closed_chest(), "c1")


func test_floor_without_chest_list_uses_visible_floor_chests() -> void:
	var floor := _floor_dict()
	floor["chests"] = [{"id": "a", "position": [2, 2], "table": "starter_gear"},
		{"id": "b", "position": [3, 3], "table": "hidden_cache", "hidden": true}]
	var st := ClientState.new(PID)
	st.apply(Messages.make_result(Messages.FLOOR_LOADED, {"floor": floor}))
	assert_true(st.chests.has("a"))
	assert_false(st.chests.has("b"), "hidden chests wait for CHEST_REVEALED")


func test_loot_gained_is_logged_for_this_player_only() -> void:
	var st := _loaded_with(_fighter_sheet_dict())
	st.drain_log()
	st.apply(Messages.make_result(Messages.LOOT_GAINED, {"entity_id": PID, "source": "chest", "chest_id": "c1",
		"items": [{"item": "potion_of_healing", "qty": 2}, {"item": "gold", "qty": 12}, {"item": "dagger", "qty": 1}]}))
	assert_eq(st.drain_log(), ["Loot from the chest: Potion of Healing x2, 12 gold, Dagger."] as Array[String])
	assert_eq(st.last_loot.size(), 3)
	st.apply(Messages.make_result(Messages.LOOT_GAINED, {"entity_id": PID, "source": "chest", "items": []}))
	assert_eq(st.drain_log(), ["Nothing of value from the chest."] as Array[String])
	st.apply(Messages.make_result(Messages.LOOT_GAINED, {"entity_id": "p9", "source": "monster", "items": [{"item": "gold", "qty": 3}]}))
	assert_eq(st.drain_log().size(), 0, "someone else's loot")
	assert_eq(st.last_loot.size(), 0, "the empty chest's loot is still the latest")


func test_character_state_extras_are_logged() -> void:
	var st := _loaded_with(_fighter_sheet_dict())
	st.drain_log()
	var sheet := _fighter_sheet_dict()
	st.apply(Messages.make_result(Messages.CHARACTER_STATE, {"sheet": sheet, "item_used": "potion_of_healing", "healed": 7}))
	st.apply(Messages.make_result(Messages.CHARACTER_STATE, {"sheet": sheet, "equipped": {"item": "dagger", "slot": "main_hand"}}))
	st.apply(Messages.make_result(Messages.CHARACTER_STATE, {"sheet": sheet, "unequipped": {"item": "shield", "slot": "off_hand"}}))
	st.apply(Messages.make_result(Messages.CHARACTER_STATE, {"sheet": sheet, "dropped": {"item": "rations", "qty": 2}}))
	st.apply(Messages.make_result(Messages.CHARACTER_STATE, {"sheet": sheet, "xp_gained": 100, "floor_clear_xp": 100, "levels_pending": 0}))
	assert_eq(st.drain_log(), [
		"Tess uses Potion of Healing.", "Tess regains 7 HP.", "Tess equips Dagger.", "Tess puts away Shield.",
		"Tess drops Rations x2.", "Floor-clear bonus: gained 100 XP.",
	] as Array[String])


func test_inventory_rows_slots_and_ac_breakdown() -> void:
	var st := _loaded_with(_fighter_sheet_dict())
	assert_eq(st.ac_breakdown(), "AC 16: chain mail 16, DEX 0, shield +0")
	assert_eq(st.gold(), 10)
	var by_id := {}
	for r in st.inventory_rows():
		by_id[r["item"]] = r
	assert_false(by_id.has("gold"), "gold has its own line")
	var potion: Dictionary = by_id["potion_of_healing"]
	assert_eq(int(potion["qty"]), 2)
	assert_true(bool(potion["usable"]))
	var sword: Dictionary = by_id["longsword"]
	assert_eq(sword["equipped"], ["main_hand"] as Array[String])
	assert_has(sword["equip_slots"], "main_hand")
	assert_eq(st.equip_slots_for("shield"), ["off_hand"] as Array[String])
	assert_eq(st.equip_slots_for("chain_mail"), ["armor"] as Array[String])
	assert_has(st.equip_slots_for("dagger"), "off_hand", "a light weapon fits the off hand")
	assert_true(st.carried_weight() > 0.0)
	assert_true(st.can_manage_equipment())
	assert_eq(st.use_item_error("potion_of_healing"), "", "potions work out of combat")
	assert_eq(st.use_item_error("rations"), "cannot be used")
	for intent: Dictionary in [st.equip_intent("dagger", "off_hand"), st.unequip_intent("armor"),
			st.use_item_intent("potion_of_healing"), st.drop_item_intent("rations", 2)]:
		assert_eq(Messages.validate_intent(intent), "", str(intent))
	_combat_turn(st)
	assert_false(st.can_manage_equipment(), "equipment is locked in combat")
	assert_eq(st.use_item_error("potion_of_healing"), "", "on my turn with the action free")


func test_combat_item_use_spends_the_action_and_the_potion() -> void:
	var st := _loaded_with(_fighter_sheet_dict())
	_combat_turn(st)
	st.apply(_events([
		{"kind": "item_used", "actor": PID, "item": "potion_of_healing", "target": PID},
		{"kind": "heal", "source": PID, "target": PID, "amount": 3, "rolled": 7, "hp_after": 12, "revived": false},
	]))
	assert_true(st.action_used)
	assert_eq(st.sheet.count_item("potion_of_healing"), 1)
	assert_ne(st.use_item_error("potion_of_healing"), "", "action spent")
	assert_has(st.log_lines, "Tess uses Potion of Healing.")
	assert_has(st.log_lines, "Tess regains 3 HP (12 HP).")


func test_attacks_selection_ranges_and_consumption() -> void:
	var sheet := CharacterSheet.from_dict(_fighter_sheet_dict())
	sheet.add_item("javelin", 2)
	sheet.rebuild_attacks(ContentLoader.cache())
	var st := _loaded_with(sheet.to_dict())
	var attacks := st.available_attacks()
	assert_eq(str(attacks[attacks.size() - 1]["name"]), "Unarmed Strike", "the unarmed strike is last, as on the server")
	var javelin := -1
	for i in range(attacks.size()):
		if str(attacks[i].get("kind", "")) == "thrown" and str(attacks[i].get("item", "")) == "javelin":
			javelin = i
	assert_true(javelin >= 0, "carried javelins are a thrown attack")
	_combat_turn(st)
	assert_false(st.can_attack(), "melee: nothing adjacent")
	st.select_attack(javelin)
	assert_true(st.can_attack(), "the goblin is within javelin range")
	var tiles := st.range_tiles()
	assert_eq(int(tiles.get(Vector2i(7, 3), -1)), 0, "goblin in normal range")
	var click := st.intent_for_click(Vector2i(7, 3))
	assert_eq(click.get("type"), Messages.ATTACK)
	assert_eq(int(click.get("attack_index")), javelin)
	st.apply(_events([{"kind": "attack", "attacker": PID, "target": GOBLIN, "attack_name": "Javelin", "attack_kind": "thrown",
		"natural": 15, "d20s": [15], "total": 20, "target_ac": 15, "hit": true, "critical": false, "fumble": false,
		"advantage": "normal", "bonus": false, "consumed": "javelin"}]))
	assert_true(st.action_used)
	assert_true(st.attack_action_taken)
	assert_eq(st.sheet.count_item("javelin"), 1, "one javelin thrown")
	assert_eq(st.available_attacks().size(), attacks.size(), "combat indices stay those of the encounter start")


func test_spells_targeting_slots_and_unsupported() -> void:
	var st := _loaded_with(_caster_sheet_dict("wizard"))
	var entries := st.spell_entries()
	assert_false(entries.is_empty())
	assert_eq(int(entries[0]["level"]), 0, "cantrips first")
	assert_ne(st.cast_error("fire_bolt"), "", "not in combat")
	assert_eq(st.slots_text(), "Slots: 1st 2/2")
	_combat_turn(st)
	var cantrip := ""
	var leveled := ""
	for e in entries:
		var def := st.spell_def(str(e["id"]))
		if def.is_harmful() and def.is_supported() and def.range_tiles() >= 3:
			if def.level == 0 and cantrip.is_empty():
				cantrip = def.id
			elif def.level == 1 and leveled.is_empty():
				leveled = def.id
	assert_ne(cantrip, "", "a ranged attack cantrip is prepared")
	assert_eq(st.begin_cast(cantrip), {}, "enters targeting mode")
	assert_true(st.is_targeting())
	assert_false(st.range_tiles().is_empty(), "spell range is tinted")
	assert_eq(st.intent_for_click(Vector2i(4, 3)), {}, "a harmful spell cannot target yourself")
	assert_has(st.hint, "hostile")
	var cast := st.intent_for_click(Vector2i(7, 3))
	assert_eq(cast.get("type"), Messages.CAST)
	assert_eq(cast.get("spell"), cantrip)
	assert_eq(cast.get("target"), GOBLIN)
	assert_eq(int(cast.get("slot_level")), 0, "cantrips need no slot")
	assert_eq(Messages.validate_intent(cast), "")
	st.cancel_targeting()
	assert_false(st.is_targeting())
	if not leveled.is_empty():
		st.begin_cast(leveled)
		assert_eq(int(st.targeting["slot_level"]), 1, "lowest available slot by default")
		st.cancel_targeting()
	st.apply(_events([{"kind": "cast", "actor": PID, "spell": leveled if not leveled.is_empty() else cantrip,
		"target": GOBLIN, "slot_level": 1 if not leveled.is_empty() else 0}]))
	assert_true(st.action_used)
	if not leveled.is_empty():
		assert_eq(st.sheet.slots_left(1), 1, "a level 1 slot was spent")
	assert_ne(st.cast_error(cantrip), "", "action used")
	# An unsupported spell is listed but never castable.
	st.sheet.spells_prepared.append("alarm")
	var found := false
	for e in st.spell_entries():
		if str(e["id"]) == "alarm":
			found = true
			assert_false(bool(e["supported"]))
			assert_eq(str(e["error"]), "not supported yet")
	assert_true(found)


func test_self_and_ally_spells() -> void:
	var st := _loaded_with(_caster_sheet_dict("cleric"))
	_combat_turn(st)
	var heal := ""
	for id in st.sheet.spells_prepared:
		var def := st.spell_def(id)
		if def != null and def.effect_type == SpellDefinition.EFFECT_HEAL:
			heal = id
	if heal.is_empty():
		st.sheet.spells_prepared.append("cure_wounds")
		heal = "cure_wounds"
	st.begin_cast(heal)
	assert_eq(st.intent_for_click(Vector2i(7, 3)), {}, "a heal needs an ally")
	var intent := st.intent_for_click(Vector2i(4, 3))
	assert_eq(intent.get("target"), PID, "heal yourself")


func test_features_and_resources() -> void:
	var st := _loaded_with(_fighter_sheet_dict())
	assert_eq(st.resources_text(), "Second Wind 1/1")
	var entries := st.feature_entries()
	assert_eq(entries.size(), 1)
	assert_ne(str(entries[0]["error"]), "", "combat only")
	_combat_turn(st)
	var intent := st.begin_feature("second_wind")
	assert_eq(intent.get("type"), Messages.USE_FEATURE)
	assert_eq(intent.get("feature"), "second_wind")
	assert_eq(Messages.validate_intent(intent), "")
	st.apply(_events([
		{"kind": "feature_used", "actor": PID, "feature": "second_wind", "target": PID, "remaining": 0},
		{"kind": "heal", "source": PID, "target": PID, "amount": 0, "rolled": 6, "hp_after": 12, "revived": false},
	]))
	assert_true(st.bonus_action_used)
	assert_false(st.action_used, "a bonus action")
	assert_eq(st.sheet.class_resource("second_wind"), 0)
	assert_eq(st.resources_text(), "Second Wind 0/1")
	assert_has(st.log_lines, "Tess uses Second Wind.")


func test_lay_on_hands_and_bardic_inspiration_target() -> void:
	var st := _loaded_with(_caster_sheet_dict("paladin"))
	_combat_turn(st)
	assert_eq(st.begin_feature("lay_on_hands", 3), {})
	assert_eq(int(st.targeting["amount"]), 3)
	var lay := st.intent_for_click(Vector2i(4, 3))
	assert_eq(lay.get("feature"), "lay_on_hands")
	assert_eq(int(lay.get("amount")), 3)
	assert_eq(lay.get("target"), PID)
	var bard := _loaded_with(_caster_sheet_dict("bard"))
	_combat_turn(bard)
	bard.begin_feature("bardic_inspiration")
	assert_eq(bard.intent_for_click(Vector2i(4, 3)), {}, "not yourself")
	assert_eq(bard.intent_for_click(Vector2i(7, 3)), {}, "not a monster")


func test_status_tags_follow_effects() -> void:
	var st := _loaded_with(_fighter_sheet_dict())
	_combat_turn(st)
	st.apply(_events([
		{"kind": "dodge", "actor": PID},
		{"kind": "effect_applied", "source": PID, "target": GOBLIN, "effect": "guiding_bolt_mark"},
		{"kind": "effect_applied", "source": PID, "target": PID, "effect": "rage"},
	]))
	assert_has(st.status_tags(PID), "dodging")
	assert_has(st.status_tags(PID), "raging")
	assert_has(st.status_tags(GOBLIN), "marked")
	assert_has(st.log_lines, "Goblin is now marked.")
	st.apply(_events([
		{"kind": "turn_ended", "actor": PID},
		{"kind": "turn_started", "actor": GOBLIN, "round": 1},
		{"kind": "attack", "attacker": RAT, "target": GOBLIN, "attack_name": "Bite", "attack_kind": "melee", "natural": 5,
			"d20s": [5, 12], "total": 9, "target_ac": 15, "hit": false, "critical": false, "fumble": false, "advantage": "advantage"},
		{"kind": "effect_ended", "target": PID, "effect": "rage"},
	]))
	assert_eq(st.status_tags(GOBLIN).size(), 0, "the mark is used up by the attack")
	assert_has(st.status_tags(PID), "dodging", "dodge lasts until my next turn")
	assert_false(st.status_tags(PID).has("raging"))
	st.apply(_events([{"kind": "turn_ended", "actor": GOBLIN}, {"kind": "turn_started", "actor": PID, "round": 2}]))
	assert_eq(st.status_tags(PID).size(), 0)


func test_cast_save_and_temp_hp_log_lines() -> void:
	var st := _loaded_with(_fighter_sheet_dict())
	_combat_turn(st)
	st.drain_log()
	st.apply(_events([
		{"kind": "cast", "actor": GOBLIN, "spell": "sacred_flame", "target": PID, "slot_level": 0},
		{"kind": "save", "actor": GOBLIN, "target": PID, "ability": "DEX", "dc": 13, "natural": 9, "total": 9, "success": false},
		{"kind": "temp_hp", "source": PID, "target": PID, "amount": 5, "temp_hp_after": 5},
		{"kind": "inspiration_used", "actor": PID, "source": "p2", "die": 6, "roll": 4},
	]))
	assert_eq(st.drain_log(), [
		"Goblin casts Sacred Flame at Tess.",
		"Tess makes a DEX saving throw: 9 vs DC 13, fails.",
		"Tess gains 5 temporary HP.",
		"Tess adds a Bardic Inspiration die: d6 rolled 4.",
	] as Array[String])
	assert_eq(st.sheet.temp_hp, 5)


func test_level_up_offer_is_tracked_until_answered() -> void:
	var st := _loaded_with(_fighter_sheet_dict())
	var s := CharacterSheet.from_dict(_fighter_sheet_dict())
	s.xp = 300
	st.apply(Messages.make_result(Messages.CHARACTER_STATE, {"sheet": s.to_dict(), "xp_gained": 50, "levels_pending": 1}))
	var choices := LevelUp.choices(s)
	st.apply(Messages.make_result(Messages.LEVEL_UP_AVAILABLE, {"entity_id": PID, "choices": choices}))
	assert_true(st.has_level_up_offer())
	assert_true(st.can_level_up())
	assert_eq(st.level_up_serial, 1)
	assert_has(st.log_lines, "Level 2 is available! Open the level-up screen to choose.")
	st.apply(Messages.make_result(Messages.LEVEL_UP_AVAILABLE, {"entity_id": "p9", "choices": choices}))
	assert_eq(st.level_up_serial, 1, "another player's offer")
	var draft := LevelUpDraft.first_valid(st.level_up_offer, st.sheet)
	assert_true(draft.is_valid(), str(draft.problems()))
	var intent := st.level_up_intent(draft.to_choices())
	assert_eq(intent.get("type"), Messages.LEVEL_UP)
	assert_eq(intent["choices"]["hp"], "average")
	assert_eq(Messages.validate_intent(intent), "")
	_combat_turn(st)
	assert_false(st.can_level_up(), "never in combat")
	st.apply(_events([{"kind": "encounter_ended", "winning_team": 0}]))
	assert_true(st.can_level_up())
	assert_true(LevelUp.apply(s, draft.to_choices(), {}, null).is_empty())
	st.apply(Messages.make_result(Messages.CHARACTER_STATE, {"sheet": s.to_dict(), "leveled_to": 2, "levels_pending": 0}))
	assert_false(st.has_level_up_offer())
	assert_eq(st.last_leveled_to, 2)
	assert_has(st.log_lines, "Level up! Tess is now level 2.")


func test_step_intent_ignores_targeting() -> void:
	var st := _loaded_with(_fighter_sheet_dict())
	var walk := st.step_intent(Vector2i.RIGHT)
	assert_eq(walk.get("type"), Messages.EXPLORE_MOVE)
	assert_eq(walk.get("target"), [5, 3])
	_combat_turn(st)
	st.begin_attack_targeting(0)
	var step := st.step_intent(Vector2i.RIGHT)
	assert_eq(step.get("type"), Messages.MOVE)
	assert_eq(step.get("path"), [[5, 3]])


func test_imported_monsters_fall_back_to_their_glyph() -> void:
	var icons := EntityIcons.shared()
	assert_eq(icons.monster_icon_id("goblin"), "goblin", "an atlas column of its own")
	assert_eq(icons.monster_icon_id("awakened_shrub"), "giant_centipede", "the data file's icon")
	assert_eq(icons.column_for_entity({"kind": "monster", "monster_id": "aboleth"}), icons.column_for("ghoul"),
		"an aberration without a column")
	assert_eq(icons.monster_icon_id("no_such_monster"), "")
	var custom := EntityIcons.from_dict({"icons": {"skeleton": 3}})
	assert_eq(custom.monster_icon_id("lich"), "skeleton", "undead by creature type when the named icon is missing")

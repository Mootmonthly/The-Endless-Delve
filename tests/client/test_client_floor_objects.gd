extends TestCase
## ClientState for Round D floor objects (doors, props, landings, respawns,
## reveals) and the round C fight state (terrain, light, control, visibility,
## ritual / no-effect / exploration casts, new attack options). No Nodes.

const PID := "p1"
const RAT := "z2_giant_rat_0"

## 14x7, door d1 (6, 2) between two rooms, barrel p1 (2, 4), crate p2
## (5, 1), locked chest c_locked (1, 3); zones z1 (right room, stairs) and z2.
const ROWS: Array[String] = [
	"##############",
	"#.....#......#",
	"#............#",
	"#.....#......#",
	"#.....#......#",
	"#.....#......#",
	"##############",
]


func _floor_dict(door_state: String = "closed") -> Dictionary:
	return {
		"schema_version": 2, "id": "d2_floor", "display_name": "Door Hall", "floor_number": 1, "rows": ROWS,
		"landings": [{"id": "nw", "position": [1, 1]}, {"id": "sw", "position": [1, 5]}],
		"arrival": [1, 1], "stairs": [11, 2],
		"encounter_zones": [
			{"id": "z1", "name": "Stair Hall", "rect": [7, 1, 6, 5], "monster_ids": ["giant_rat"], "spawn_points": [[12, 5]], "guards_stairs": true},
			{"id": "z2", "name": "Rat Nook", "rect": [3, 4, 2, 2], "monster_ids": ["giant_rat"], "spawn_points": [[4, 5]]},
		],
		"chests": [{"id": "c_stairs", "position": [9, 5], "hidden": false, "opened": false}],
		"doors": [{"id": "d1", "position": [6, 2], "state": door_state, "dc": 12}],
		"props": [
			{"id": "p1", "kind": "barrel", "position": [2, 4], "hp": 4, "blocks": true, "destroyed": false},
			{"id": "p2", "kind": "crate", "position": [5, 1], "hp": 6, "blocks": true, "destroyed": false},
		],
	}


func _loaded(door_state: String = "closed", sheet: CharacterSheet = null, pos: Array = [5, 2], extra: Dictionary = {}) -> ClientState:
	var st := ClientState.new(PID)
	var fd := _floor_dict(door_state)
	var fields := {"floor": fd, "entity_id": PID, "doors": fd["doors"], "props": fd["props"], "landing_id": "nw", "light": "dim",
		"landings": fd["landings"], "chests": [{"id": "c_stairs", "position": [9, 5], "hidden": false, "opened": false},
			{"id": "c_locked", "position": [1, 3], "hidden": false, "opened": false, "locked": true}]}
	fields.merge(extra, true)
	st.apply(Messages.make_result(Messages.FLOOR_LOADED, fields))
	var s := sheet if sheet != null else _fighter()
	st.apply(Messages.make_result(Messages.CHARACTER_STATE, {"sheet": s.to_dict(), "entity_id": PID}))
	st.apply(Messages.make_result(Messages.EXPLORE_STATE, {"entities": [
		{"id": PID, "kind": "player", "position": pos},
		{"id": RAT, "kind": "monster", "position": [4, 5], "name": "Giant Rat", "monster_id": "giant_rat"},
	], "tick": 1}))
	return st


func _fighter() -> CharacterSheet:
	var d := CharacterDraft.new()
	d.character_name = "Tess"
	d.set_class(ContentLoader.load_classes()["fighter"])
	d.set_ancestry(ContentLoader.load_ancestries()["human"])
	d.auto_assign()
	return d.build_sheet()


func _wizard(extra_spells: Array[String] = [], known_only: Array[String] = []) -> CharacterSheet:
	var d := CharacterDraft.new()
	d.character_name = "Ilsa"
	d.set_class(ContentLoader.load_classes()["wizard"])
	d.set_ancestry(ContentLoader.load_ancestries()["human"])
	d.auto_assign()
	var s := d.build_sheet()
	for id in extra_spells:
		for list: Array[String] in [s.spells_known, s.spells_prepared]:
			if not list.has(id):
				list.append(id)
	for id in known_only:
		if not s.spells_known.has(id):
			s.spells_known.append(id)
	s.spell_slots_max = [4, 3, 3, 3, 2] as Array[int]
	s.spell_slots = [4, 3, 3, 3, 2] as Array[int]
	return s


func _events(events: Array, enc_id: String = "z1") -> Dictionary:
	return Messages.make_result(Messages.ENCOUNTER_EVENTS, {"events": events, "encounter_id": enc_id, "zone_id": "z1"})


## In a fight in z1 (whole right room): the player at (8, 2), a goblin at (10, 2), the player's turn.
func _fight(st: ClientState) -> void:
	st.apply(Messages.make_result(Messages.EXPLORE_STATE, {"entities": [
		{"id": PID, "kind": "player", "position": [8, 2]},
		{"id": "g1", "kind": "monster", "position": [10, 2], "name": "Goblin", "monster_id": "goblin"},
		{"id": "g2", "kind": "monster", "position": [12, 4], "name": "Goblin", "monster_id": "goblin"},
	], "tick": 2}))
	st.apply(_events([
		{"kind": "combatant_joined", "id": PID, "initiative": 15, "position": [8, 2]},
		{"kind": "combatant_joined", "id": "g1", "initiative": 10, "position": [10, 2]},
		{"kind": "combatant_joined", "id": "g2", "initiative": 5, "position": [12, 4]},
		{"kind": "encounter_started", "order": [PID, "g1", "g2"], "light": "dim"},
		{"kind": "round_started", "round": 1},
		{"kind": "turn_started", "actor": PID, "round": 1},
	]))


# --- floor loaded ---------------------------------------------------------------------

func test_floor_loaded_reads_doors_props_landing_and_light() -> void:
	var st := _loaded()
	assert_eq(st.door_state("d1"), "closed")
	assert_eq(int(st.door_info["d1"]["dc"]), 12)
	assert_eq(st.landing_id, "nw")
	assert_eq(st.landing_text(), "the north-west landing")
	assert_eq(st.floor_hud_text(), "Floor 1 — Door Hall, arrived at the north-west landing")
	assert_has(st.log_lines, "You arrive on Floor 1 — Door Hall at the north-west landing.")
	assert_eq(st.floor_light, "dim")
	assert_true(st.destroyed_props.is_empty())
	assert_eq(st.prop_blockers().size(), 2)
	assert_false(st.explore_map().is_walkable(Vector2i(6, 2)), "a closed door is a wall")
	assert_true(st.floor_data.walk_map.is_walkable(Vector2i(6, 2)))
	var destroyed := _loaded("closed", null, [5, 2], {"props": [{"id": "p1", "destroyed": true}]})
	assert_true(destroyed.destroyed_props.has("p1"), "a prop broken before arrival stays broken")
	assert_true(bool(destroyed.chests["c_locked"]["locked"]))


func test_door_changed_updates_the_map_and_logs() -> void:
	var st := _loaded()
	var serial := st.objects_serial
	st.apply(Messages.make_result(Messages.DOOR_CHANGED, {"door_id": "d1", "state": "open", "by": PID, "method": "hand"}))
	assert_eq(st.door_state("d1"), "open")
	assert_true(st.objects_serial > serial)
	assert_true(st.explore_map().is_walkable(Vector2i(6, 2)))
	assert_has(st.log_lines, "You open the door.")
	st.apply(Messages.make_result(Messages.DOOR_CHANGED, {"door_id": "d1", "state": "closed", "by": "p2"}))
	assert_has(st.log_lines, "P 2 closes the door.")
	st.apply(Messages.make_result(Messages.DOOR_CHANGED, {"door_id": "d1", "state": "locked", "by": PID, "method": "spell", "spell": "arcane_lock"}))
	assert_has(st.log_lines, "You lock the door with Arcane Lock.")
	st.apply(Messages.make_result(Messages.DOOR_CHANGED, {"door_id": "d1", "state": "closed", "by": PID, "method": "spell", "spell": "knock"}))
	assert_has(st.log_lines, "You unlock the door with Knock.")


# --- clicks ----------------------------------------------------------------------------

func test_clicking_doors_opens_closes_and_unlocks() -> void:
	var st := _loaded()
	var open := st.intent_for_click(Vector2i(6, 2))
	assert_eq(str(open["type"]), Messages.OPEN_DOOR)
	assert_eq(str(open["door_id"]), "d1")
	assert_eq(Messages.validate_intent(open), "")
	st.apply(Messages.make_result(Messages.DOOR_CHANGED, {"door_id": "d1", "state": "open", "by": PID}))
	assert_eq(str(st.intent_for_click(Vector2i(6, 2))["type"]), Messages.CLOSE_DOOR)
	assert_eq(st.nearby_object_hint(), "An open door: click it to close it.")
	# Locked: a fighter without tools, key or Knock gets a hint.
	var locked := _loaded("locked")
	assert_eq(locked.intent_for_click(Vector2i(6, 2)), {})
	assert_true(locked.hint.contains("DC 12"), locked.hint)
	locked.sheet.add_item("thieves_tools", 1)
	var pick := locked.intent_for_click(Vector2i(6, 2))
	assert_eq(str(pick["type"]), Messages.UNLOCK_DOOR)
	assert_eq(str(pick["method"]), "tools")
	assert_eq(locked.nearby_object_hint(), "A locked door: click it to pick the lock.")
	var keyed := _loaded("locked", null, [5, 2], {"doors": [{"id": "d1", "position": [6, 2], "state": "locked", "keyed": true}]})
	assert_eq(str(keyed.intent_for_click(Vector2i(6, 2))["method"]), "key", "a keyed door whose key is not named")
	var mage := _loaded("locked", _wizard(["knock"]))
	assert_eq(str(mage.intent_for_click(Vector2i(6, 2))["method"]), "spell")
	# Too far: walk next to the door first.
	var far := _loaded("closed", null, [2, 2])
	var walk := far.intent_for_click(Vector2i(6, 2))
	assert_eq(str(walk["type"]), Messages.EXPLORE_MOVE)
	assert_eq(GridMath.distance_tiles(Messages.to_position(walk["target"]), Vector2i(6, 2)), 1)


func test_a_tile_behind_a_closed_door_routes_through_it() -> void:
	var st := _loaded("closed", null, [2, 2])
	var first := st.intent_for_click(Vector2i(10, 3))
	assert_eq(str(first["type"]), Messages.EXPLORE_MOVE)
	assert_eq(Messages.to_position(first["target"]), Vector2i(5, 2), "walk up to the door")
	assert_eq(st.hint, "A closed door is in the way.")
	st.apply(Messages.make_result(Messages.EXPLORE_STATE, {"entities": [{"id": PID, "kind": "player", "position": [5, 2]}], "tick": 3}))
	var second := st.intent_for_click(Vector2i(10, 3))
	assert_eq(str(second["type"]), Messages.OPEN_DOOR, "then open it")
	st.apply(Messages.make_result(Messages.DOOR_CHANGED, {"door_id": "d1", "state": "open", "by": PID}))
	var third := st.intent_for_click(Vector2i(10, 3))
	assert_eq(str(third["type"]), Messages.EXPLORE_MOVE)
	assert_eq(Messages.to_position(third["target"]), Vector2i(10, 3))
	var walled := _loaded("locked", null, [2, 2])
	assert_eq(walled.intent_for_click(Vector2i(10, 3)), {}, "a locked door has no way round")
	assert_eq(walled.hint, "No way there.")


func test_clicking_a_prop_breaks_it_and_loot_is_logged() -> void:
	var st := _loaded("closed", null, [2, 3])
	var smash := st.intent_for_click(Vector2i(2, 4))
	assert_eq(str(smash["type"]), Messages.INTERACT)
	assert_eq(str(smash["prop_id"]), "p1")
	assert_eq(Messages.validate_intent(smash), "")
	assert_eq(st.nearby_object_hint(), "A barrel: click it to break it open.")
	st.apply(Messages.make_result(Messages.PROP_DESTROYED, {"prop_id": "p1", "by": PID, "kind": "barrel"}))
	assert_true(st.destroyed_props.has("p1"))
	assert_has(st.log_lines, "You smash the barrel.")
	assert_false(st.prop_blockers().has(Vector2i(2, 4)))
	st.apply(Messages.make_result(Messages.LOOT_GAINED, {"entity_id": PID, "items": [{"item": "gold", "qty": 5}], "source": "prop", "prop_id": "p1"}))
	assert_has(st.log_lines, "Loot from the wreckage: 5 gold.")
	assert_eq(st.intent_for_click(Vector2i(2, 4))["type"], Messages.EXPLORE_MOVE, "a broken prop's tile is floor again")
	var far := _loaded("closed", null, [5, 3])
	var walk := far.intent_for_click(Vector2i(2, 4))
	assert_eq(str(walk["type"]), Messages.EXPLORE_MOVE)
	assert_eq(GridMath.distance_tiles(Messages.to_position(walk["target"]), Vector2i(2, 4)), 1)


func test_locked_chest_click_says_why() -> void:
	var st := _loaded("closed", null, [1, 2])
	assert_eq(st.intent_for_click(Vector2i(1, 3)), {})
	assert_true(st.hint.contains("locked"))
	st.apply(Messages.make_result(Messages.CHEST_REVEALED, {"chest": {"id": "c_locked", "position": [1, 3], "hidden": false, "opened": false}}))
	assert_has(st.log_lines, "The chest's lock clicks open.")
	assert_eq(str(st.intent_for_click(Vector2i(1, 3))["type"]), Messages.OPEN_CHEST)


# --- results: respawn, reveal, character state extras ----------------------------------

func test_zone_respawned_and_reveal_results_are_logged() -> void:
	var st := _loaded()
	st.apply(Messages.make_result(Messages.ZONE_RESPAWNED, {"zone_id": "z2"}))
	assert_has(st.log_lines, "Monsters stir again in Rat Nook.")
	st.apply(Messages.make_result(Messages.REVEAL, {"entity_id": PID, "reveal": "monsters", "spell": "clairvoyance",
		"zones": [{"zone_id": "z1", "name": "Stair Hall", "monsters": [{"id": "a", "monster_id": "giant_rat", "position": [12, 5]},
			{"id": "b", "monster_id": "giant_rat", "position": [12, 4]}]}]}))
	assert_has(st.log_lines, "Clairvoyance reveals Stair Hall: Giant Rat x2.")
	assert_eq((st.revealed_zones["z1"] as Array).size(), 2)
	st.apply(Messages.make_result(Messages.REVEAL, {"entity_id": PID, "reveal": "hidden_chests", "spell": "locate_object", "chests": ["c9"]}))
	assert_has(st.log_lines, "Locate Object: 1 hidden chest found.")
	st.apply(Messages.make_result(Messages.REVEAL, {"entity_id": PID, "reveal": "stairs", "spell": "find_the_path", "stairs": [11, 2], "distance": 9}))
	assert_has(st.log_lines, "Find the Path: the stairs lie 9 steps away.")
	st.apply(Messages.make_result(Messages.REVEAL, {"entity_id": PID, "reveal": "threat", "spell": "augury", "threat": "woe"}))
	assert_has(st.log_lines, "Augury: woe. Danger waits ahead.")
	st.apply(Messages.make_result(Messages.REVEAL, {"entity_id": PID, "reveal": "teleport", "spell": "teleportation_circle", "landmark": "arrival"}))
	assert_has(st.log_lines, "You vanish and reappear at the north-west landing.")
	st.apply(Messages.make_result(Messages.REVEAL, {"entity_id": "p9", "reveal": "map", "spell": "commune_with_nature"}))
	assert_eq(str(st.last_reveal["reveal"]), "teleport", "other players' reveals are not ours")


func test_character_state_light_and_lock_extras() -> void:
	var st := _loaded()
	var s := st.sheet.to_dict()
	st.apply(Messages.make_result(Messages.CHARACTER_STATE, {"sheet": s, "light_level": "bright"}))
	assert_eq(st.light_level, "bright")
	assert_has(st.log_lines, "Light surrounds you (bright).")
	st.apply(Messages.make_result(Messages.CHARACTER_STATE, {"sheet": s, "unlock_failed": {"door_id": "d1", "total": 9, "dc": 12}}))
	assert_has(st.log_lines, "Tess fails to pick the lock (9 vs DC 12).")
	st.apply(Messages.make_result(Messages.CHARACTER_STATE, {"sheet": s, "door_unlocked": {"door_id": "d1", "method": "tools", "total": 14, "dc": 12}}))
	assert_has(st.log_lines, "Tess picks the lock (14 vs DC 12).")


# --- round C fight state -----------------------------------------------------------------

func test_terrain_tile_effects_and_light_in_a_fight() -> void:
	var st := _loaded("open")
	_fight(st)
	assert_eq(st.encounter_light, "dim")
	assert_has(st.log_lines, "The fight begins in dim light.")
	assert_true(st.fight_map().is_walkable(Vector2i(9, 2)))
	st.apply(_events([
		{"kind": "tile_effect_created", "id": "fx1", "effect": "wall_of_stone", "spell": "wall_of_stone", "tiles": [[9, 1], [9, 2]], "terrain": "solid"},
		{"kind": "tile_effect_created", "id": "fx2", "effect": "darkness", "spell": "darkness", "tiles": [[11, 3]], "darkness": true},
		{"kind": "tile_effect_created", "id": "fx3", "effect": "spike_growth", "spell": "spike_growth", "tiles": [[10, 4]]},
		{"kind": "terrain_changed", "walls": [[9, 2]], "floors": [[13, 3]]},
		{"kind": "light_changed", "light": "dark"},
	]))
	var cells := st.terrain_cells()
	assert_eq(str(cells[Vector2i(9, 1)]), "wall")
	assert_eq(str(cells[Vector2i(11, 3)]), "darkness")
	assert_eq(str(cells[Vector2i(10, 4)]), "difficult", "spike growth's zone is difficult terrain")
	assert_eq(str(cells[Vector2i(13, 3)]), "opened")
	assert_false(st.fight_map().is_walkable(Vector2i(9, 2)), "a raised wall blocks the fight map")
	assert_eq(st.encounter_light, "dark")
	assert_has(st.log_lines, "The light turns dark.")
	var serial := st.terrain_serial
	st.apply(_events([{"kind": "tile_effect_moved", "id": "fx2", "tiles": [[12, 3]]}, {"kind": "tile_effect_ended", "id": "fx3", "reason": "expired"}]))
	assert_true(st.terrain_serial > serial)
	assert_eq(str(st.terrain_cells()[Vector2i(12, 3)]), "darkness")
	assert_false(st.terrain_cells().has(Vector2i(10, 4)))
	st.apply(_events([{"kind": "encounter_ended", "winning_team": 0}]))
	assert_true(st.terrain_cells().is_empty(), "terrain goes with the fight")


func test_dominated_creatures_take_control_orders() -> void:
	var st := _loaded("open")
	_fight(st)
	st.apply(_events([{"kind": "team_changed", "target": "g1", "team": 0, "controlled_by": PID}]))
	assert_eq(st.controlled_creatures(), ["g1"] as Array[String])
	assert_eq(str(st.get_entity("g1")["kind"]), ClientState.KIND_ALLY)
	assert_has(st.log_lines, "Goblin is now under Tess's control.")
	var hold := st.control_hold_intent("g1")
	assert_eq(str(hold["type"]), Messages.CONTROL)
	assert_eq(Messages.validate_intent(hold), "")
	assert_eq(hold["orders"], [{"type": "end_turn"}])
	st.begin_control("g1", "attack")
	assert_true(st.is_targeting())
	var attack := st.intent_for_click(Vector2i(12, 4))
	assert_eq(str(attack["type"]), Messages.CONTROL)
	assert_eq(str(attack["target"]), "g1")
	var orders: Array = attack["orders"]
	assert_eq(str(orders[0]["type"]), Messages.MOVE, "walks next to g2 first")
	assert_eq(str(orders[1]["type"]), Messages.ATTACK)
	assert_eq(str(orders[1]["target"]), "g2")
	assert_eq(Messages.validate_intent(attack), "")
	st.begin_control("g1", "move")
	var move := st.intent_for_click(Vector2i(11, 1))
	assert_eq(str(move["orders"][0]["type"]), Messages.MOVE)
	st.apply(_events([{"kind": "control", "actor": PID, "target": "g1", "orders": 2}]))
	assert_has(st.log_lines, "Tess commands Goblin.")
	st.apply(_events([{"kind": "team_changed", "target": "g1", "team": 1, "controlled_by": ""}]))
	assert_true(st.controlled_creatures().is_empty())
	assert_eq(str(st.get_entity("g1")["kind"]), ClientState.KIND_MONSTER)


func test_visibility_of_hidden_banished_and_illusory_creatures() -> void:
	var st := _loaded("open")
	_fight(st)
	assert_eq(st.visibility_of("g1"), ClientState.VIS_SHOWN)
	st.apply(_events([{"kind": "hidden", "actor": "g1", "total": 17}]))
	assert_eq(st.visibility_of("g1"), ClientState.VIS_HIDDEN, "an unseen hostile is not drawn")
	st.apply(_events([{"kind": "revealed", "actor": "g1", "reason": "found"}]))
	assert_eq(st.visibility_of("g1"), ClientState.VIS_SHOWN)
	st.apply(_events([{"kind": "condition_applied", "target": PID, "condition": "invisible", "source": PID, "duration": {"type": "rounds", "rounds": 10}, "turns_left": 10}]))
	assert_eq(st.visibility_of(PID), ClientState.VIS_GHOST, "the player sees itself ghosted")
	st.apply(_events([{"kind": "banished", "target": "g2", "source": PID, "spell": "banishment", "rounds": 10, "permanent": false}]))
	assert_eq(st.visibility_of("g2"), ClientState.VIS_HIDDEN)
	assert_has(st.log_lines, "Goblin is banished (10 rounds).")
	st.apply(_events([{"kind": "returned", "target": "g2", "position": [12, 5], "reason": "concentration"}]))
	assert_eq(st.visibility_of("g2"), ClientState.VIS_SHOWN)
	assert_eq(st.get_entity("g2")["position"], Vector2i(12, 5))
	st.apply(_events([{"kind": "combatant_joined", "id": "img1", "name": "Image", "team": 0, "initiative": 1, "position": [8, 3], "owner": PID, "illusion": true}]))
	assert_eq(st.visibility_of("img1"), ClientState.VIS_GHOST)
	st.apply(_events([{"kind": "teleported", "actor": PID, "from": [8, 2], "to": [8, 4], "spell": "misty_step"}]))
	assert_eq(st.player_position(), Vector2i(8, 4))


func test_no_effect_time_stop_and_lingering_are_logged() -> void:
	var st := _loaded("open")
	_fight(st)
	st.apply(_events([
		{"kind": "no_effect", "actor": PID, "spell": "comprehend_languages", "reason": "nobody here speaks a language you lack"},
		{"kind": "time_stop", "actor": PID, "turns": 3},
		{"kind": "extra_turn", "actor": PID, "source": "time_stop", "turns_left": 2},
		{"kind": "lingering_added", "source": PID, "target": PID, "spell": "gentle_repose", "lingering_kind": "feature", "encounters": 1},
	]))
	assert_has(st.log_lines, "Comprehend Languages has no effect in the delve: nobody here speaks a language you lack.")
	assert_has(st.log_lines, "Tess stops time (3 turns).")
	assert_has(st.log_lines, "Tess takes another turn.")
	assert_true(st.can_take_action(), "an extra turn gives the action back")
	var ooc := _loaded()
	ooc.apply(Messages.make_result(Messages.OUT_OF_COMBAT_EVENTS, {"entity_id": PID, "spell": "comprehend_languages", "events": [
		{"kind": "cast", "actor": PID, "spell": "comprehend_languages", "target": PID, "slot_level": 0, "casting_time": "action", "ritual": true},
		{"kind": "no_effect", "actor": PID, "spell": "comprehend_languages", "reason": "no tongue to read"},
		{"kind": "lingering_added", "source": PID, "target": PID, "spell": "foresight", "lingering_kind": "buff", "encounters": 2},
	]}))
	assert_has(ooc.log_lines, "Comprehend Languages has no effect in the delve: no tongue to read.")
	assert_has(ooc.log_lines, "Foresight holds on Tess for the next 2 fights.")


# --- spells ---------------------------------------------------------------------------

func test_ritual_and_no_effect_spells_in_the_spells_list() -> void:
	var st := _loaded("closed", _wizard(["comprehend_languages"], ["detect_magic"]))
	var by_id := {}
	for e in st.spell_entries():
		by_id[str(e["id"])] = e
	assert_true(by_id.has("detect_magic"), "a spellbook ritual is listed while exploring")
	var dm: Dictionary = by_id["detect_magic"]
	assert_false(bool(dm["prepared"]))
	assert_true(bool(dm["ritual_castable"]))
	assert_eq(str(dm["ritual_error"]), "")
	assert_ne(str(dm["error"]), "", "not prepared: only as a ritual")
	var cl: Dictionary = by_id["comprehend_languages"]
	assert_false(str(cl["no_effect"]).is_empty(), "declared no-effect spells say why")
	assert_eq(str(cl["error"]), "", "and are castable")
	st.sheet.spell_slots = [0, 0, 0, 0, 0] as Array[int]
	var intent := st.begin_cast("detect_magic", 0, [] as Array[String], {"ritual": true})
	assert_eq(str(intent["type"]), Messages.CAST)
	assert_true(intent["ritual"] == true)
	assert_eq(int(intent["slot_level"]), 0, "a ritual spends no slot")
	assert_eq(Messages.validate_intent(intent), "")
	var free := st.begin_cast("comprehend_languages")
	assert_eq(int(free["slot_level"]), 0, "no-effect spells are free")


func test_exploration_spells_aim_at_doors_chests_and_landmarks() -> void:
	var st := _loaded("locked", _wizard(["knock", "teleportation_circle", "clairvoyance"]), [2, 2])
	assert_eq(st.begin_cast("knock"), {}, "Knock waits for a click")
	assert_true(st.is_targeting())
	assert_true(st.hint.contains("door"))
	assert_eq(st.intent_for_click(Vector2i(3, 3)), {}, "nothing to unlock there")
	var knock := st.intent_for_click(Vector2i(6, 2))
	assert_eq(str(knock["type"]), Messages.CAST)
	assert_eq(str(knock["target_kind"]), "door")
	assert_eq(str(knock["target_id"]), "d1")
	assert_eq(Messages.validate_intent(knock), "")
	st.cancel_targeting()
	st.begin_cast("knock")
	var chest := st.intent_for_click(Vector2i(1, 3))
	assert_eq(str(chest["target_kind"]), "chest")
	assert_eq(str(chest["target_id"]), "c_locked")
	st.cancel_targeting()
	var circle := st.begin_cast("teleportation_circle")
	assert_eq(str(circle["target_kind"]), "landmark")
	assert_eq(str(circle["target_id"]), "arrival")
	var stairs := st.begin_cast("teleportation_circle", 0, [] as Array[String], {"target_kind": "landmark", "target_id": "arrival"})
	assert_eq(str(stairs["target_id"]), "arrival")
	st.begin_cast("clairvoyance")
	assert_true(st.is_targeting(), "Clairvoyance aims at a zone")
	var zone := st.intent_for_click(Vector2i(10, 3))
	assert_eq(str(zone["target_kind"]), "zone")
	assert_eq(str(zone["target_id"]), "z1")


func test_overchannel_rides_on_damaging_spells_when_toggled() -> void:
	var w := _wizard(["magic_missile", "shield"])
	w.features.append("overchannel")
	var st := _loaded("open", w)
	_fight(st)
	var plain := st.cast_intent("magic_missile", "g1", 1)
	assert_false(plain.has("overchannel"))
	st.set_cast_option("overchannel", true)
	var max_out := st.cast_intent("magic_missile", "g1", 1)
	assert_true(max_out["overchannel"] == true)
	assert_eq(Messages.validate_intent(max_out), "")
	assert_false(st.cast_intent("shield", PID, 1).has("overchannel"), "only damaging spells")


func test_round_c_attack_options() -> void:
	var monk := _fighter()
	monk.features.append("quivering_palm")
	monk.features.append("hurl_through_hell")
	monk.class_resources["ki"] = 5
	monk.class_resources["hurl_through_hell"] = 1
	var st := _loaded("open", monk)
	_fight(st)
	var kinds := st.attack_option_kinds()
	assert_has(kinds, "quivering_palm")
	assert_has(kinds, "hurl_through_hell")
	assert_false(kinds.has("via_familiar"), "no pact, no familiar")
	st.set_attack_option("quivering_palm", true)
	st.set_attack_option("hurl_through_hell", true)
	var unarmed := st.available_attacks().size() - 1
	var fields := st.attack_option_fields(unarmed, false)
	assert_true(fields.get("quivering_palm", false) == true, "unarmed: Quivering Palm")
	assert_true(fields.get("hurl_through_hell", false) == true)
	assert_false(st.attack_option_fields(0, false).has("quivering_palm"), "a weapon attack is not unarmed")
	st.apply(Messages.make_result(Messages.EXPLORE_STATE, {"entities": [{"id": PID, "kind": "player", "position": [9, 2]}], "tick": 3}))
	st.apply(_events([{"kind": "attack", "attacker": PID, "target": "g1", "attack_kind": "melee", "hit": true}]))
	assert_false(bool(st.attack_options["quivering_palm"]), "one-shot")


func test_pact_of_the_chain_familiar_attacks() -> void:
	var w := _fighter()
	w.features.append("pact_of_the_chain")
	w.companions = [{"id": "c1", "monster": "imp", "spell": "find_familiar", "hp": 10}] as Array[Dictionary]
	var st := _loaded("open", w)
	_fight(st)
	st.apply(_events([{"kind": "combatant_joined", "id": "fam", "name": "Imp", "team": 0, "initiative": 14, "position": [11, 2], "owner": PID, "monster": "imp"}]))
	st.apply(_events([{"kind": "summoned", "caster": PID, "spell": "find_familiar", "id": "fam", "monster": "imp", "position": [11, 2]}]))
	assert_eq(st.familiar_id(), "fam")
	assert_has(st.attack_option_kinds(), "via_familiar")
	assert_eq(st.familiar_targets(), ["g1"] as Array[String], "g1 is next to the imp")
	st.set_attack_option("via_familiar", true)
	assert_true(st.can_attack())
	var intent := st.attack_intent()
	assert_eq(str(intent["target"]), "g1")
	assert_true(intent["via_familiar"] == true)
	assert_eq(int(intent["attack_index"]), 0)
	assert_eq(Messages.validate_intent(intent), "")
	assert_eq(st.attack_error("g2"), "not in your familiar's reach")



# --- door keys ----------------------------------------------------------------------------

func _key_door(st_sheet: CharacterSheet = null) -> ClientState:
	return _loaded("locked", st_sheet, [5, 2], {"doors": [{"id": "d1", "position": [6, 2], "state": "locked", "dc": 12,
		"keyed": true, "key_item": "key_bronze"}]})


func test_floor_loaded_reads_the_key_a_door_wants() -> void:
	var st := _key_door()
	assert_eq(st.door_key_item("d1"), "key_bronze")
	assert_eq(st.door_for_key("key_bronze"), "d1")
	assert_eq(st.door_for_key("key_iron"), "")
	assert_true(st.is_key_item("key_bronze"))
	assert_false(st.is_key_item("longsword"))


func test_the_door_hint_names_the_key() -> void:
	var st := _key_door()
	assert_eq(st.nearby_object_hint(), "Locked: needs the Bronze Key. Barrels and crates hide such things.")
	assert_eq(st.intent_for_click(Vector2i(6, 2)), {}, "no key, tools or Knock: nothing to send")
	assert_true(st.hint.begins_with("Locked: needs the Bronze Key"), st.hint)
	assert_true(st.hint.contains("DC 12"), st.hint)
	st.sheet.add_item("key_bronze", 1)
	assert_eq(st.nearby_object_hint(), "Locked: needs the Bronze Key. You have the Bronze Key: click the door to unlock it.")
	var wrong := _key_door()
	wrong.sheet.add_item("key_iron", 1)
	assert_true(wrong.nearby_object_hint().begins_with("Locked: needs the Bronze Key. Barrels"), "the wrong key does not count")


func test_click_order_is_key_then_tools_then_knock() -> void:
	var st := _key_door()
	st.sheet.add_item("thieves_tools", 1)
	assert_eq(str(st.intent_for_click(Vector2i(6, 2))["method"]), "tools", "no key yet: pick the lock")
	assert_eq(st.nearby_object_hint(), "Locked: needs the Bronze Key. Click it to pick the lock instead.")
	st.sheet.add_item("key_bronze", 1)
	var click := st.intent_for_click(Vector2i(6, 2))
	assert_eq(str(click["method"]), "key", "the key first when carried")
	assert_eq(Messages.validate_intent(click), "")
	var mage := _key_door(_wizard(["knock"]))
	assert_eq(str(mage.intent_for_click(Vector2i(6, 2))["method"]), "spell")
	assert_eq(mage.nearby_object_hint(), "Locked: needs the Bronze Key. Click it to cast Knock instead.")
	mage.sheet.add_item("thieves_tools", 1)
	assert_eq(str(mage.intent_for_click(Vector2i(6, 2))["method"]), "tools", "tools before Knock")
	mage.sheet.add_item("key_bronze", 1)
	assert_eq(str(mage.intent_for_click(Vector2i(6, 2))["method"]), "key", "and the key before both")


func test_finding_and_using_a_key_is_logged() -> void:
	var st := _key_door(null)
	st.apply(Messages.make_result(Messages.PROP_DESTROYED, {"prop_id": "p2", "by": PID, "kind": "crate"}))
	st.apply(Messages.make_result(Messages.LOOT_GAINED, {"entity_id": PID, "source": "prop", "prop_id": "p2",
		"items": [{"item": "key_bronze", "qty": 1}, {"item": "gold", "qty": 4}]}))
	assert_has(st.log_lines, "You find the Bronze Key in the crate! It fits a locked door on this floor.")
	assert_has(st.log_lines, "Loot from the wreckage: Bronze Key, 4 gold.")
	st.apply(Messages.make_result(Messages.DOOR_CHANGED, {"door_id": "d1", "state": "closed", "by": PID, "method": "key", "consumed": "key_bronze"}))
	assert_has(st.log_lines, "You unlock the door with the Bronze Key.")
	var s := st.sheet.to_dict()
	st.apply(Messages.make_result(Messages.CHARACTER_STATE, {"sheet": s, "door_unlocked": {"door_id": "d1", "method": "key", "consumed": "key_bronze"}}))
	assert_has(st.log_lines, "The Bronze Key turns in the lock and stays there: it is used up.")
	st.apply(Messages.make_result(Messages.CHARACTER_STATE, {"sheet": s, "keys_lost": ["key_iron"]}))
	assert_has(st.log_lines, "The Iron Key crumbles to dust: its lock was on the floor above.")


func test_inventory_lists_keys_under_their_own_heading() -> void:
	var st := _key_door()
	var plain := st.inventory_sections()
	assert_eq(plain.size(), 1, "no keys: one section")
	assert_eq(str(plain[0]["heading"]), ClientState.INVENTORY_ITEMS_HEADING)
	st.sheet.add_item("key_bronze", 1)
	st.sheet.add_item("key_iron", 1)
	var sections := st.inventory_sections()
	assert_eq(sections.size(), 2)
	assert_eq(str(sections[1]["heading"]), "Keys")
	var keys: Array = sections[1]["rows"]
	assert_eq(keys.size(), 2)
	assert_eq(str(keys[0]["name"]), "Bronze Key")
	assert_eq(str(keys[0]["kind"]), "key")
	assert_true(keys[0]["key"] == true)
	assert_eq(str(keys[0]["door"]), "d1", "the bronze key fits d1")
	assert_eq(str(keys[1]["door"]), "", "no lock here takes the iron key")
	for r: Variant in (sections[0]["rows"] as Array):
		assert_false((r as Dictionary)["key"] == true, "keys are not listed with the items")
	var icons := EntityIcons.shared()
	assert_eq(icons.column_for_item(st.item_def("key_bronze")), icons.column_for("misc"), "keys reuse the misc glyph")

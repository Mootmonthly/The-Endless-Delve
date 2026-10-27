extends TestCase


func test_make_intent_sets_version_and_type() -> void:
	var d := Messages.make_intent(Messages.ATTACK, {"actor": "p1", "target": "g1", "attack_index": 0})
	assert_eq(d["v"], Messages.PROTOCOL_VERSION)
	assert_eq(d["type"], "attack")
	assert_eq(d["target"], "g1")
	assert_eq(Messages.validate_intent(d), "")


func test_make_intent_copies_fields() -> void:
	var path: Array = [[1, 2]]
	var fields := {"actor": "p1", "path": path}
	var d := Messages.make_intent(Messages.MOVE, fields)
	path.append([1, 3])
	assert_eq((d["path"] as Array).size(), 1, "intent must not alias the caller's arrays")
	assert_false(fields.has("v"), "fields must not be modified")


func test_every_intent_type_validates_with_required_fields() -> void:
	var cases: Array[Dictionary] = [
		Messages.make_intent(Messages.MOVE, {"actor": "p1", "path": [[1, 1], [2, 2]]}),
		Messages.make_intent(Messages.ATTACK, {"actor": "p1", "target": "g1", "attack_index": 0}),
		Messages.make_intent(Messages.DASH, {"actor": "p1"}),
		Messages.make_intent(Messages.DODGE, {"actor": "p1"}),
		Messages.make_intent(Messages.DISENGAGE, {"actor": "p1"}),
		Messages.make_intent(Messages.END_TURN, {"actor": "p1"}),
		Messages.make_intent(Messages.EXPLORE_MOVE, {"actor": "p1", "target": [10, 4]}),
		Messages.make_intent(Messages.USE_STAIRS, {"actor": "p1"}),
		Messages.make_intent(Messages.SHORT_REST, {"actor": "p1", "hit_dice": 1}),
		Messages.make_intent(Messages.ATTACK, {"actor": "p1", "target": "g1", "attack_index": 2, "bonus": true}),
		Messages.make_intent(Messages.CAST, {"actor": "p1", "spell": "fire_bolt"}),
		Messages.make_intent(Messages.CAST, {"actor": "p1", "spell": "cure_wounds", "target": "p2", "slot_level": 1}),
		Messages.make_intent(Messages.USE_ITEM, {"actor": "p1", "item": "potion_of_healing"}),
		Messages.make_intent(Messages.USE_ITEM, {"actor": "p1", "item": "potion_of_healing", "target": "p1"}),
		Messages.make_intent(Messages.USE_FEATURE, {"actor": "p1", "feature": "second_wind"}),
		Messages.make_intent(Messages.USE_FEATURE, {"actor": "p1", "feature": "lay_on_hands", "target": "p2", "amount": 5}),
		Messages.make_intent(Messages.EQUIP, {"actor": "p1", "item": "shield", "slot": "off_hand"}),
		Messages.make_intent(Messages.UNEQUIP, {"actor": "p1", "slot": "armor"}),
		Messages.make_intent(Messages.OPEN_CHEST, {"actor": "p1", "chest_id": "f1_stairs"}),
		Messages.make_intent(Messages.DROP_ITEM, {"actor": "p1", "item": "rations", "qty": 2}),
		Messages.make_intent(Messages.LEVEL_UP, {"actor": "p1", "choices": {"hp": "average"}}),
	]
	for d in cases:
		assert_eq(Messages.validate_intent(d), "", "type %s" % d["type"])


func test_item_spell_and_level_up_intents_reject_bad_fields() -> void:
	var bad: Array[Dictionary] = [
		Messages.make_intent(Messages.ATTACK, {"actor": "p1", "target": "g1", "attack_index": 0, "bonus": 1}),
		Messages.make_intent(Messages.CAST, {"actor": "p1"}),
		Messages.make_intent(Messages.CAST, {"actor": "p1", "spell": "fire_bolt", "slot_level": -1}),
		Messages.make_intent(Messages.CAST, {"actor": "p1", "spell": "fire_bolt", "target": ""}),
		Messages.make_intent(Messages.USE_ITEM, {"actor": "p1"}),
		Messages.make_intent(Messages.USE_FEATURE, {"actor": "p1", "feature": "lay_on_hands", "amount": "5"}),
		Messages.make_intent(Messages.EQUIP, {"actor": "p1", "item": "shield"}),
		Messages.make_intent(Messages.EQUIP, {"actor": "p1", "item": "shield", "slot": "head"}),
		Messages.make_intent(Messages.UNEQUIP, {"actor": "p1"}),
		Messages.make_intent(Messages.OPEN_CHEST, {"actor": "p1", "chest_id": ""}),
		Messages.make_intent(Messages.DROP_ITEM, {"actor": "p1", "item": "rations"}),
		Messages.make_intent(Messages.DROP_ITEM, {"actor": "p1", "item": "rations", "qty": 0}),
		Messages.make_intent(Messages.LEVEL_UP, {"actor": "p1"}),
		Messages.make_intent(Messages.LEVEL_UP, {"actor": "p1", "choices": "average"}),
	]
	for d in bad:
		assert_ne(Messages.validate_intent(d), "", "should reject %s" % str(d))


func test_intent_rejects_wrong_version() -> void:
	var d := Messages.make_intent(Messages.DASH, {"actor": "p1"})
	d["v"] = 2
	assert_ne(Messages.validate_intent(d), "")
	d.erase("v")
	assert_ne(Messages.validate_intent(d), "")


func test_intent_rejects_unknown_type_and_missing_actor() -> void:
	assert_ne(Messages.validate_intent(Messages.make_intent("fly", {"actor": "p1"})), "")
	assert_ne(Messages.validate_intent(Messages.make_intent(Messages.DASH)), "")
	assert_ne(Messages.validate_intent(Messages.make_intent(Messages.DASH, {"actor": ""})), "")
	assert_ne(Messages.validate_intent({"v": 1}), "")


func test_move_requires_non_empty_path_of_pairs() -> void:
	var bad: Array = [null, [], [[1]], [[1, "2"]], [1, 2], "1,2"]
	for path: Variant in bad:
		var d := Messages.make_intent(Messages.MOVE, {"actor": "p1", "path": path})
		assert_ne(Messages.validate_intent(d), "", "path %s should be rejected" % str(path))


func test_attack_requires_target_and_index() -> void:
	assert_ne(Messages.validate_intent(Messages.make_intent(Messages.ATTACK, {"actor": "p1", "attack_index": 0})), "")
	assert_ne(Messages.validate_intent(Messages.make_intent(Messages.ATTACK, {"actor": "p1", "target": "g1"})), "")
	assert_ne(Messages.validate_intent(
			Messages.make_intent(Messages.ATTACK, {"actor": "p1", "target": "g1", "attack_index": -1})), "")
	assert_ne(Messages.validate_intent(
			Messages.make_intent(Messages.ATTACK, {"actor": "p1", "target": "g1", "attack_index": 0.5})), "")


func test_explore_and_rest_fields() -> void:
	assert_ne(Messages.validate_intent(Messages.make_intent(Messages.EXPLORE_MOVE, {"actor": "p1"})), "")
	assert_ne(Messages.validate_intent(Messages.make_intent(Messages.EXPLORE_MOVE, {"actor": "p1", "target": [1]})), "")
	assert_ne(Messages.validate_intent(Messages.make_intent(Messages.SHORT_REST, {"actor": "p1"})), "")
	assert_ne(Messages.validate_intent(Messages.make_intent(Messages.SHORT_REST, {"actor": "p1", "hit_dice": -1})), "")
	assert_eq(Messages.validate_intent(Messages.make_intent(Messages.SHORT_REST, {"actor": "p1", "hit_dice": 0})), "")


func test_intent_survives_json_round_trip() -> void:
	var d := Messages.make_intent(Messages.MOVE, {"actor": "p1", "path": [[3, 4], [4, 5]]})
	var parsed: Variant = JSON.parse_string(JSON.stringify(d))
	assert_eq(typeof(parsed), TYPE_DICTIONARY)
	var back: Dictionary = parsed
	assert_eq(Messages.validate_intent(back), "", "integral floats from JSON count as ints")
	assert_eq(Messages.path_of(back), [Vector2i(3, 4), Vector2i(4, 5)] as Array[Vector2i])


func test_encounter_intent_classification() -> void:
	assert_true(Messages.is_encounter_intent(Messages.make_intent(Messages.DODGE, {"actor": "p1"})))
	assert_false(Messages.is_encounter_intent(Messages.make_intent(Messages.USE_STAIRS, {"actor": "p1"})))
	var cast := Messages.make_intent(Messages.CAST, {"actor": "p1"})
	assert_false(Messages.is_encounter_intent(cast), "cast also works out of combat")
	assert_true(Messages.is_dual_intent(cast))
	assert_false(Messages.is_dual_intent(Messages.make_intent(Messages.DISMISS_COMPANION, {"actor": "p1"})), "exploration only")
	assert_true(Messages.is_encounter_intent(Messages.make_intent(Messages.USE_FEATURE, {"actor": "p1"})))
	assert_false(Messages.is_encounter_intent(Messages.make_intent(Messages.EQUIP, {"actor": "p1"})))
	var use := Messages.make_intent(Messages.USE_ITEM, {"actor": "p1"})
	assert_false(Messages.is_encounter_intent(use), "use_item is routed by the server")
	assert_true(Messages.is_dual_intent(use))
	assert_false(Messages.is_dual_intent(Messages.make_intent(Messages.ATTACK, {"actor": "p1"})))


func test_every_result_kind_validates_with_required_fields() -> void:
	var cases: Array[Dictionary] = [
		Messages.make_result(Messages.ENCOUNTER_EVENTS, {"events": [{"kind": "dash", "actor": "p1"}]}),
		Messages.make_result(Messages.EXPLORE_STATE,
				{"entities": [{"id": "p1", "position": [5, 5], "kind": "player"}], "tick": 12}),
		Messages.make_error("not your turn"),
		Messages.make_result(Messages.FLOOR_LOADED, {"floor": {"id": "floor_001"}}),
		Messages.make_result(Messages.CHARACTER_STATE, {"sheet": {"name": "Ada"}}),
		Messages.make_result(Messages.GAME_OVER),
		Messages.make_result(Messages.FLOOR_CLEARED, {"floor_id": "floor_001"}),
		Messages.make_result(Messages.SET_CLEARED, {"set_id": "set_01"}),
		Messages.make_result(Messages.LOOT_GAINED,
				{"entity_id": "p1", "items": [{"item": "gold", "qty": 12}], "source": "chest"}),
		Messages.make_result(Messages.LOOT_GAINED, {"entity_id": "p1", "items": [], "source": "monster"}),
		Messages.make_result(Messages.CHEST_OPENED, {"chest_id": "f1_stairs"}),
		Messages.make_result(Messages.CHEST_REVEALED,
				{"chest": {"id": "f1_hidden", "position": [28, 29], "hidden": true, "opened": false}}),
		Messages.make_result(Messages.LEVEL_UP_AVAILABLE, {"entity_id": "p1", "choices": {"new_level": 2}}),
	]
	for d in cases:
		assert_eq(Messages.validate_result(d), "", "kind %s" % d["kind"])


func test_result_rejects_malformed_payloads() -> void:
	var bad: Array[Dictionary] = [
		{"kind": Messages.ERROR, "message": "x"},
		Messages.make_result("weather", {}),
		Messages.make_result(Messages.ENCOUNTER_EVENTS, {}),
		Messages.make_result(Messages.ENCOUNTER_EVENTS, {"events": [{"actor": "p1"}]}),
		Messages.make_result(Messages.ENCOUNTER_EVENTS, {"events": ["dash"]}),
		Messages.make_result(Messages.EXPLORE_STATE, {"entities": []}),
		Messages.make_result(Messages.EXPLORE_STATE, {"entities": [{"id": "p1", "kind": "player"}], "tick": 1}),
		Messages.make_result(Messages.ERROR, {}),
		Messages.make_result(Messages.FLOOR_LOADED, {"floor": "floor_001"}),
		Messages.make_result(Messages.CHARACTER_STATE, {}),
		Messages.make_result(Messages.FLOOR_CLEARED, {}),
		Messages.make_result(Messages.FLOOR_CLEARED, {"floor_id": ""}),
		Messages.make_result(Messages.SET_CLEARED, {}),
		Messages.make_result(Messages.SET_CLEARED, {"set_id": 1}),
		Messages.make_result(Messages.LOOT_GAINED, {"entity_id": "p1", "items": [], "source": "shop"}),
		Messages.make_result(Messages.LOOT_GAINED, {"entity_id": "p1", "items": [{"qty": 1}], "source": "chest"}),
		Messages.make_result(Messages.LOOT_GAINED, {"items": [], "source": "chest"}),
		Messages.make_result(Messages.CHEST_OPENED, {}),
		Messages.make_result(Messages.CHEST_REVEALED, {"chest": {"id": "c"}}),
		Messages.make_result(Messages.LEVEL_UP_AVAILABLE, {"entity_id": "p1"}),
	]
	for d in bad:
		assert_ne(Messages.validate_result(d), "", "should reject %s" % str(d))


func test_position_helpers() -> void:
	assert_true(Messages.is_position([1, 2]))
	assert_true(Messages.is_position([1.0, 2.0]))
	assert_false(Messages.is_position([1.5, 2]))
	assert_false(Messages.is_position(Vector2i(1, 2)))
	assert_eq(Messages.to_position([7.0, -3]), Vector2i(7, -3))


func test_progression_intent_fields_validate() -> void:
	var good: Array[Dictionary] = [
		Messages.make_intent(Messages.STAND, {"actor": "p1"}),
		Messages.make_intent(Messages.ATTACK, {"actor": "p1", "target": "g1", "attack_index": 0,
			"reckless": true, "smite": 2, "stun": false, "retarget": true}),
		Messages.make_intent(Messages.ATTACK, {"actor": "p1", "target": "g1", "attack_index": 2, "bonus": true, "technique": "push"}),
		Messages.make_intent(Messages.CAST, {"actor": "p1", "spell": "fireball", "slot_level": 3, "point": [4, 5],
			"sculpt": ["p2"], "metamagic": ["empowered_spell"]}),
		Messages.make_intent(Messages.CAST, {"actor": "p1", "spell": "chill_touch", "target": "g1", "metamagic": ["twinned_spell"], "twin_target": "g2"}),
		Messages.make_intent(Messages.USE_FEATURE, {"actor": "p1", "feature": "step_of_the_wind", "mode": "dash"}),
		Messages.make_intent(Messages.USE_FEATURE, {"actor": "p1", "feature": "font_of_magic", "mode": "create_slot", "slot_level": 2}),
		Messages.make_intent(Messages.USE_FEATURE, {"actor": "p1", "feature": "preserve_life", "allocations": {"p1": 3, "p2": 7.0}}),
		Messages.make_intent(Messages.USE_FEATURE, {"actor": "p1", "feature": "rage", "frenzy": true}),
		Messages.make_intent(Messages.USE_ITEM, {"actor": "p1", "item": "potion_of_healing", "bonus": true}),
		Messages.make_intent(Messages.SHORT_REST, {"actor": "p1", "hit_dice": 0, "recover_slots": true}),
		Messages.make_intent(Messages.SHORT_REST, {"actor": "p1", "hit_dice": 1, "recover_slots": [1, 2.0]}),
		Messages.make_intent(Messages.LEVEL_UP, {"actor": "p1", "choices": {"hp": "average", "subclass": "champion",
			"fighting_style": "defense", "feature_options": {"hunters_prey": "colossus_slayer"}}}),
	]
	for d in good:
		assert_eq(Messages.validate_intent(d), "", str(d))
	assert_true(Messages.is_encounter_intent(Messages.make_intent(Messages.STAND, {"actor": "p1"})), "stand is a combat intent")


func test_progression_intent_fields_reject_bad_values() -> void:
	var bad: Array[Dictionary] = [
		Messages.make_intent(Messages.ATTACK, {"actor": "p1", "target": "g1", "attack_index": 0, "reckless": "yes"}),
		Messages.make_intent(Messages.ATTACK, {"actor": "p1", "target": "g1", "attack_index": 0, "smite": 10}),
		Messages.make_intent(Messages.ATTACK, {"actor": "p1", "target": "g1", "attack_index": 0, "smite": -1}),
		Messages.make_intent(Messages.ATTACK, {"actor": "p1", "target": "g1", "attack_index": 0, "stun": 1}),
		Messages.make_intent(Messages.ATTACK, {"actor": "p1", "target": "g1", "attack_index": 0, "technique": "trip"}),
		Messages.make_intent(Messages.ATTACK, {"actor": "p1", "target": "g1", "attack_index": 0, "retarget": "true"}),
		Messages.make_intent(Messages.CAST, {"actor": "p1", "spell": "fireball", "point": [1]}),
		Messages.make_intent(Messages.CAST, {"actor": "p1", "spell": "fireball", "slot_level": 12}),
		Messages.make_intent(Messages.CAST, {"actor": "p1", "spell": "fireball", "sculpt": "p2"}),
		Messages.make_intent(Messages.CAST, {"actor": "p1", "spell": "fireball", "metamagic": [""]}),
		Messages.make_intent(Messages.CAST, {"actor": "p1", "spell": "fire_bolt", "twin_target": ""}),
		Messages.make_intent(Messages.USE_FEATURE, {"actor": "p1", "feature": "cunning_action", "mode": ""}),
		Messages.make_intent(Messages.USE_FEATURE, {"actor": "p1", "feature": "font_of_magic", "slot_level": "2"}),
		Messages.make_intent(Messages.USE_FEATURE, {"actor": "p1", "feature": "preserve_life", "allocations": [3]}),
		Messages.make_intent(Messages.USE_FEATURE, {"actor": "p1", "feature": "preserve_life", "allocations": {"p1": 0}}),
		Messages.make_intent(Messages.USE_FEATURE, {"actor": "p1", "feature": "rage", "frenzy": "on"}),
		Messages.make_intent(Messages.USE_ITEM, {"actor": "p1", "item": "potion_of_healing", "bonus": 1}),
		Messages.make_intent(Messages.SHORT_REST, {"actor": "p1", "hit_dice": 0, "recover_slots": "all"}),
		Messages.make_intent(Messages.SHORT_REST, {"actor": "p1", "hit_dice": 0, "recover_slots": [0]}),
	]
	for d in bad:
		assert_ne(Messages.validate_intent(d), "", "should reject %s" % str(d))


func test_reaction_policy_intent() -> void:
	var good := Messages.make_intent(Messages.REACTION_POLICY, {"actor": "p1", "policy": {"creature_left_reach": "never", "shield": "auto"}})
	assert_eq(Messages.validate_intent(good), "")
	assert_true(Messages.is_dual_intent(good), "settable in and out of combat")
	assert_eq(Messages.validate_intent(Messages.make_intent(Messages.REACTION_POLICY, {"actor": "p1", "policy": {}})), "", "all auto")
	for bad: Dictionary in [{"actor": "p1"}, {"actor": "p1", "policy": "never"}, {"actor": "p1", "policy": {"missed": "sometimes"}},
			{"actor": "p1", "policy": {"missed": true}}]:
		assert_ne(Messages.validate_intent(Messages.make_intent(Messages.REACTION_POLICY, bad)), "", str(bad))


func test_out_of_combat_cast_and_companion_messages() -> void:
	var cast := Messages.make_intent(Messages.CAST, {"actor": "p1", "spell": "find_familiar", "targets": ["p1"], "form": "cat", "slot_level": 1})
	assert_eq(Messages.validate_intent(cast), "")
	for bad: Dictionary in [{"targets": "p1"}, {"targets": [""]}, {"form": ""}, {"form": 3}]:
		var d := {"actor": "p1", "spell": "find_familiar"}
		d.merge(bad)
		assert_ne(Messages.validate_intent(Messages.make_intent(Messages.CAST, d)), "", str(bad))
	assert_eq(Messages.validate_intent(Messages.make_intent(Messages.DISMISS_COMPANION, {"actor": "p1", "companion_id": "c1"})), "")
	assert_ne(Messages.validate_intent(Messages.make_intent(Messages.DISMISS_COMPANION, {"actor": "p1"})), "")
	assert_ne(Messages.validate_intent(Messages.make_intent(Messages.DISMISS_COMPANION, {"actor": "p1", "companion_id": 1})), "")
	var ok := Messages.make_result(Messages.OUT_OF_COMBAT_EVENTS, {"entity_id": "p1", "spell": "cure_wounds",
		"events": [{"kind": "cast", "actor": "p1", "spell": "cure_wounds"}, {"kind": "heal", "target": "p1", "amount": 5}]})
	assert_eq(Messages.validate_result(ok), "")
	for bad: Dictionary in [{"spell": "x", "events": []}, {"entity_id": "p1", "events": []}, {"entity_id": "p1", "spell": "x"},
			{"entity_id": "p1", "spell": "x", "events": [{"amount": 1}]}, {"entity_id": "p1", "spell": "x", "events": ["heal"]}]:
		assert_ne(Messages.validate_result(Messages.make_result(Messages.OUT_OF_COMBAT_EVENTS, bad)), "", str(bad))


# --- Round D (doors, props) and round C fields ---------------------------------------

func _intent(type: String, fields: Dictionary = {}) -> Dictionary:
	var f := fields.duplicate()
	f["actor"] = "p1"
	return Messages.make_intent(type, f)


func test_door_prop_and_control_intents_validate() -> void:
	var good: Array[Dictionary] = [
		_intent(Messages.OPEN_DOOR, {"door_id": "d1"}),
		_intent(Messages.CLOSE_DOOR, {"door_id": "d1"}),
		_intent(Messages.UNLOCK_DOOR, {"door_id": "d1", "method": "key"}),
		_intent(Messages.UNLOCK_DOOR, {"door_id": "d1", "method": "tools"}),
		_intent(Messages.UNLOCK_DOOR, {"door_id": "d1", "method": "spell", "spell": "knock"}),
		_intent(Messages.INTERACT, {"prop_id": "p1"}),
		_intent(Messages.CONTROL, {"target": "goblin_0", "orders": [{"type": "attack", "target": "x", "attack_index": 0}, {"type": "end_turn"}]}),
		_intent(Messages.CONTROL, {"target": "goblin_0", "orders": []}),
	]
	for d in good:
		assert_eq(Messages.validate_intent(d), "", str(d))
	var bad: Array[Dictionary] = [
		_intent(Messages.OPEN_DOOR),
		_intent(Messages.CLOSE_DOOR, {"door_id": ""}),
		_intent(Messages.UNLOCK_DOOR, {"door_id": "d1"}),
		_intent(Messages.UNLOCK_DOOR, {"door_id": "d1", "method": "crowbar"}),
		_intent(Messages.UNLOCK_DOOR, {"door_id": "d1", "method": "spell", "spell": ""}),
		_intent(Messages.INTERACT, {}),
		_intent(Messages.CONTROL, {"orders": []}),
		_intent(Messages.CONTROL, {"target": "g", "orders": {}}),
		_intent(Messages.CONTROL, {"target": "g", "orders": [{"target": "x"}]}),
		_intent(Messages.CONTROL, {"target": "g", "orders": [{"type": "control"}]}),
		_intent(Messages.CONTROL, {"target": "g", "orders": [{"type": "end_turn"}, {"type": "end_turn"}, {"type": "end_turn"},
			{"type": "end_turn"}, {"type": "end_turn"}, {"type": "end_turn"}, {"type": "end_turn"}, {"type": "end_turn"},
			{"type": "end_turn"}, {"type": "end_turn"}, {"type": "end_turn"}, {"type": "end_turn"}, {"type": "end_turn"}]}),
	]
	for d in bad:
		assert_ne(Messages.validate_intent(d), "", str(d))
	assert_true(Messages.is_encounter_intent(_intent(Messages.CONTROL, {"target": "g", "orders": []})), "control goes to the encounter")
	for type: String in [Messages.OPEN_DOOR, Messages.CLOSE_DOOR, Messages.UNLOCK_DOOR, Messages.INTERACT]:
		assert_false(Messages.is_encounter_intent({"type": type}), "%s is exploration" % type)
		assert_false(Messages.is_dual_intent({"type": type}))


func test_round_c_cast_attack_and_move_fields() -> void:
	var good: Array[Dictionary] = [
		_intent(Messages.CAST, {"spell": "knock", "target_kind": "door", "target_id": "d1"}),
		_intent(Messages.CAST, {"spell": "wish", "mode": "fireball", "duplicate_mode": "x"}),
		_intent(Messages.CAST, {"spell": "eldritch_blast", "invocation": "agonizing_blast"}),
		_intent(Messages.CAST, {"spell": "fireball", "overchannel": true}),
		_intent(Messages.CAST, {"spell": "detect_magic", "ritual": true, "spend_slot": false}),
		_intent(Messages.ATTACK, {"target": "g", "attack_index": 0, "via_familiar": true}),
		_intent(Messages.ATTACK, {"target": "g", "attack_index": 0, "quivering_palm": true, "hurl_through_hell": false}),
		_intent(Messages.MOVE, {"path": [[1, 1]], "mode": "fly"}),
	]
	for d in good:
		assert_eq(Messages.validate_intent(d), "", str(d))
	var bad: Array[Dictionary] = [
		_intent(Messages.CAST, {"spell": "knock", "target_kind": "window", "target_id": "d1"}),
		_intent(Messages.CAST, {"spell": "knock", "target_id": "d1"}),
		_intent(Messages.CAST, {"spell": "wish", "mode": ""}),
		_intent(Messages.CAST, {"spell": "fireball", "overchannel": 1}),
		_intent(Messages.CAST, {"spell": "detect_magic", "ritual": "yes"}),
		_intent(Messages.ATTACK, {"target": "g", "attack_index": 0, "via_familiar": "yes"}),
		_intent(Messages.MOVE, {"path": [[1, 1]], "mode": "swim"}),
	]
	for d in bad:
		assert_ne(Messages.validate_intent(d), "", str(d))


func test_door_prop_respawn_and_reveal_results() -> void:
	var good: Array[Dictionary] = [
		Messages.make_result(Messages.DOOR_CHANGED, {"door_id": "d1", "state": "open", "by": "p1"}),
		Messages.make_result(Messages.PROP_DESTROYED, {"prop_id": "p1", "by": "p1"}),
		Messages.make_result(Messages.ZONE_RESPAWNED, {"zone_id": "z1"}),
		Messages.make_result(Messages.REVEAL, {"entity_id": "p1", "reveal": "monsters", "zones": []}),
		Messages.make_result(Messages.LOOT_GAINED, {"entity_id": "p1", "items": [], "source": "prop", "prop_id": "p1"}),
	]
	for d in good:
		assert_eq(Messages.validate_result(d), "", str(d))
	var bad: Array[Dictionary] = [
		Messages.make_result(Messages.DOOR_CHANGED, {"door_id": "d1", "state": "ajar"}),
		Messages.make_result(Messages.DOOR_CHANGED, {"state": "open"}),
		Messages.make_result(Messages.PROP_DESTROYED, {}),
		Messages.make_result(Messages.ZONE_RESPAWNED, {"zone_id": ""}),
		Messages.make_result(Messages.REVEAL, {"entity_id": "p1"}),
		Messages.make_result(Messages.LOOT_GAINED, {"entity_id": "p1", "items": [], "source": "sky"}),
	]
	for d in bad:
		assert_ne(Messages.validate_result(d), "", str(d))

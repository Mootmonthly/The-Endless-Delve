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
	]
	for d in cases:
		assert_eq(Messages.validate_intent(d), "", "type %s" % d["type"])


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
	]
	for d in bad:
		assert_ne(Messages.validate_result(d), "", "should reject %s" % str(d))


func test_position_helpers() -> void:
	assert_true(Messages.is_position([1, 2]))
	assert_true(Messages.is_position([1.0, 2.0]))
	assert_false(Messages.is_position([1.5, 2]))
	assert_false(Messages.is_position(Vector2i(1, 2)))
	assert_eq(Messages.to_position([7.0, -3]), Vector2i(7, -3))

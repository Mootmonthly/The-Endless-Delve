extends TestCase

var _log: Array[String] = []
var _intents: Array[Dictionary] = []
var _results: Array[Dictionary] = []
var _nested: Array[int] = []
# Handlers below are methods, not lambdas: a lambda capturing the transport
# would form a reference cycle (transport -> connection -> lambda -> transport).
var _t: LocalTransport = null


func before_each() -> void:
	_log.clear()
	_intents.clear()
	_results.clear()
	_nested.clear()
	_t = null


func after_each() -> void:
	_t = null


## A tiny "server": answers each intent with an echo result.
func _echo_server(peer_id: int, intent: Dictionary) -> void:
	_t.send_result(peer_id, Messages.make_result(Messages.ERROR, {"message": "echo " + str(intent["type"])}))


func _pump_again(_result: Dictionary) -> void:
	_nested.append(_t.pump())


func _on_intent(peer_id: int, intent: Dictionary) -> void:
	_log.append("intent:%d:%s" % [peer_id, str(intent.get("type", ""))])
	_intents.append(intent)


func _on_result(result: Dictionary) -> void:
	_log.append("result:%s" % str(result.get("kind", "")))
	_results.append(result)


func _make() -> LocalTransport:
	var t := LocalTransport.new()
	t.intent_received.connect(_on_intent)
	t.result_received.connect(_on_result)
	return t


func test_local_peer_id_is_one() -> void:
	assert_eq(LocalTransport.new().local_peer_id(), 1)


func test_nothing_is_delivered_before_pump() -> void:
	var t := _make()
	t.send_intent(Messages.make_intent(Messages.DASH, {"actor": "p1"}))
	t.broadcast_result(Messages.make_error("x"))
	assert_eq(_log.size(), 0)
	assert_eq(t.pending_count(), 2)
	assert_eq(t.pump(), 2)
	assert_eq(t.pending_count(), 0)
	assert_eq(t.pump(), 0, "an empty queue delivers nothing")


func test_pump_delivers_in_send_order_across_directions() -> void:
	var t := _make()
	t.send_intent(Messages.make_intent(Messages.DASH, {"actor": "p1"}))
	t.send_result(1, Messages.make_result(Messages.GAME_OVER))
	t.send_intent(Messages.make_intent(Messages.DODGE, {"actor": "p1"}))
	t.broadcast_result(Messages.make_error("late"))
	t.pump()
	assert_eq(_log, ["intent:1:dash", "result:game_over", "intent:1:dodge", "result:error"] as Array[String])


func test_messages_are_copied_not_shared() -> void:
	var t := _make()
	var intent := Messages.make_intent(Messages.MOVE, {"actor": "p1", "path": [[1, 1]]})
	t.send_intent(intent)
	(intent["path"] as Array).append([2, 2])
	intent["actor"] = "someone_else"
	t.pump()
	assert_eq(_intents.size(), 1)
	assert_eq(_intents[0]["actor"], "p1")
	assert_eq((_intents[0]["path"] as Array).size(), 1)


func test_results_sent_by_handlers_arrive_in_same_pump_after_queued_messages() -> void:
	var t := _make()
	_t = t
	t.intent_received.connect(_echo_server)
	t.send_intent(Messages.make_intent(Messages.DASH, {"actor": "p1"}))
	t.send_intent(Messages.make_intent(Messages.DODGE, {"actor": "p1"}))
	assert_eq(t.pump(), 4)
	assert_eq(_log, ["intent:1:dash", "intent:1:dodge", "result:error", "result:error"] as Array[String])
	assert_eq(_results[0]["message"], "echo dash")
	assert_eq(_results[1]["message"], "echo dodge")


func test_pump_respects_max_messages() -> void:
	var t := _make()
	for i in range(5):
		t.broadcast_result(Messages.make_result(Messages.FLOOR_CLEARED, {"floor_id": "f%d" % i}))
	assert_eq(t.pump(2), 2)
	assert_eq(t.pending_count(), 3)
	assert_eq(_results[1]["floor_id"], "f1")
	assert_eq(t.pump(), 3)
	assert_eq(_results[4]["floor_id"], "f4")


func test_nested_pump_is_ignored() -> void:
	var t := _make()
	_t = t
	t.result_received.connect(_pump_again)
	t.broadcast_result(Messages.make_error("a"))
	t.broadcast_result(Messages.make_error("b"))
	assert_eq(t.pump(), 2)
	assert_eq(_nested, [0, 0] as Array[int])


func test_clear_drops_pending_messages() -> void:
	var t := _make()
	t.send_intent(Messages.make_intent(Messages.DASH, {"actor": "p1"}))
	t.clear()
	assert_eq(t.pump(), 0)
	assert_eq(_log.size(), 0)

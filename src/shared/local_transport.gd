class_name LocalTransport
extends Transport
## In-process transport for offline play: one client (peer id 1) and the
## server live in the same process.
##
## Nothing is delivered synchronously. send_intent / send_result /
## broadcast_result append a deep copy of the message to ONE FIFO queue
## (so no Dictionary is shared between sender and receiver, as on a real
## network), and pump() delivers the queue in send order by emitting
## intent_received(1, intent) or result_received(result).
##
## The offline server calls pump() once per tick (tests call it directly, so
## they are deterministic without a frame loop). Messages sent by a handler
## *during* pump() are delivered in the same pump(), after everything queued
## before them, so an intent and the results it causes arrive within one tick.
## max_messages bounds a pump in case handlers keep producing messages.

const PEER_ID := 1
const DEFAULT_MAX_MESSAGES := 10000

const _TO_SERVER := 0
const _TO_CLIENT := 1

var _queue: Array[Dictionary] = []  # {"dir": _TO_SERVER|_TO_CLIENT, "msg": Dictionary}
var _pumping: bool = false


func send_intent(intent: Dictionary) -> void:
	_queue.append({"dir": _TO_SERVER, "msg": intent.duplicate(true)})


func send_result(peer_id: int, result: Dictionary) -> void:
	if peer_id != PEER_ID:
		push_error("LocalTransport.send_result: unknown peer %d (only %d exists offline)" % [peer_id, PEER_ID])
		return
	_queue.append({"dir": _TO_CLIENT, "msg": result.duplicate(true)})


func broadcast_result(result: Dictionary) -> void:
	_queue.append({"dir": _TO_CLIENT, "msg": result.duplicate(true)})


func local_peer_id() -> int:
	return PEER_ID


## Number of messages waiting for the next pump().
func pending_count() -> int:
	return _queue.size()


## Drops every queued message without delivering it.
func clear() -> void:
	_queue.clear()


## Delivers queued messages in FIFO order, including ones queued by handlers
## while pumping, until the queue is empty or max_messages were delivered.
## Returns how many were delivered. A nested pump() from a handler is ignored
## (returns 0) so delivery order stays strictly FIFO.
func pump(max_messages: int = DEFAULT_MAX_MESSAGES) -> int:
	if _pumping:
		return 0
	_pumping = true
	var delivered := 0
	while not _queue.is_empty() and delivered < max_messages:
		var entry: Dictionary = _queue.pop_front()
		var msg: Dictionary = entry["msg"]
		delivered += 1
		if int(entry["dir"]) == _TO_SERVER:
			intent_received.emit(PEER_ID, msg)
		else:
			result_received.emit(msg)
	_pumping = false
	return delivered

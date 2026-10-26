class_name Transport
extends RefCounted
## Moves message Dictionaries (see Messages) between client and server.
##
## Server code listens to intent_received and answers with send_result /
## broadcast_result; client code calls send_intent and listens to
## result_received. The server logic is written against this interface only,
## so the same code path runs online (a network transport over ENet RPCs)
## and offline (LocalTransport, in-process). Transports move messages; they
## never validate or interpret them.

## Server side: a client peer sent an intent.
signal intent_received(peer_id: int, intent: Dictionary)
## Client side: the server sent a result to this peer.
signal result_received(result: Dictionary)


## Client side: send an intent to the server.
func send_intent(_intent: Dictionary) -> void:
	push_error("Transport.send_intent: not implemented")


## Server side: send a result to one peer.
func send_result(_peer_id: int, _result: Dictionary) -> void:
	push_error("Transport.send_result: not implemented")


## Server side: send a result to every connected peer.
func broadcast_result(_result: Dictionary) -> void:
	push_error("Transport.broadcast_result: not implemented")


## The peer id this process's client uses (1 offline).
func local_peer_id() -> int:
	push_error("Transport.local_peer_id: not implemented")
	return 0

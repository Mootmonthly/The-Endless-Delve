class_name Messages
extends RefCounted
## Wire format for everything exchanged between client and server.
##
## Every message is a plain, JSON-safe Dictionary carrying the protocol
## version under "v". Client -> server messages are *intents* and carry a
## "type"; server -> client messages are *results* and carry a "kind".
## Positions are always two-int arrays [x, y] (see GridMath.vec_to_arr).
##
## Intents (all carry "actor": the combatant / character id the sender
## wants to act as; the server checks it belongs to the sending peer):
##   move        {"path": [[x, y], ...]}              encounter movement
##   attack      {"target": id, "attack_index": int}
##   dash, dodge, disengage, end_turn                 no extra fields
##   explore_move {"target": [x, y]}                  real-time walking
##   use_stairs                                       no extra fields
##   short_rest  {"hit_dice": int >= 0}
## Results:
##   encounter_events {"events": [event dicts, each with "kind"]}
##   explore_state    {"entities": [{"id", "position": [x, y], "kind"}], "tick": int}
##   error            {"message": String}
##   floor_loaded     {"floor": FloorData.to_dict()}
##   character_state  {"sheet": CharacterSheet.to_dict()}
##   game_over        {}                                the party is wiped out
##   floor_cleared    {"floor_id": String}              stairs taken / floor done
## Unknown extra fields are allowed (forward compatible); missing or
## mistyped required fields are not. Numbers may arrive as integral floats
## after a JSON round trip and are accepted as ints.

const PROTOCOL_VERSION := 1

# --- Intent types (client -> server) ---
const MOVE := "move"
const ATTACK := "attack"
const DASH := "dash"
const DODGE := "dodge"
const DISENGAGE := "disengage"
const END_TURN := "end_turn"
const EXPLORE_MOVE := "explore_move"
const USE_STAIRS := "use_stairs"
const SHORT_REST := "short_rest"

## Intents resolved by an Encounter (Encounter.submit).
const ENCOUNTER_INTENTS: Array[String] = [MOVE, ATTACK, DASH, DODGE, DISENGAGE, END_TURN]
## Intents resolved by the real-time floor simulation.
const EXPLORE_INTENTS: Array[String] = [EXPLORE_MOVE, USE_STAIRS, SHORT_REST]

# --- Result kinds (server -> client) ---
const ENCOUNTER_EVENTS := "encounter_events"
const EXPLORE_STATE := "explore_state"
const ERROR := "error"
const FLOOR_LOADED := "floor_loaded"
const CHARACTER_STATE := "character_state"
const GAME_OVER := "game_over"
const FLOOR_CLEARED := "floor_cleared"

const RESULT_KINDS: Array[String] = [
	ENCOUNTER_EVENTS, EXPLORE_STATE, ERROR, FLOOR_LOADED, CHARACTER_STATE, GAME_OVER, FLOOR_CLEARED,
]


## {"v": PROTOCOL_VERSION, "type": type} merged with a deep copy of fields.
## "v" and "type" in fields are ignored.
static func make_intent(type: String, fields: Dictionary = {}) -> Dictionary:
	var d: Dictionary = fields.duplicate(true)
	d["v"] = PROTOCOL_VERSION
	d["type"] = type
	return d


## {"v": PROTOCOL_VERSION, "kind": kind} merged with a deep copy of fields.
static func make_result(kind: String, fields: Dictionary = {}) -> Dictionary:
	var d: Dictionary = fields.duplicate(true)
	d["v"] = PROTOCOL_VERSION
	d["kind"] = kind
	return d


## Convenience: an error result carrying a human-readable message.
static func make_error(message: String) -> Dictionary:
	return Messages.make_result(ERROR, {"message": message})


static func is_intent_type(type: String) -> bool:
	return ENCOUNTER_INTENTS.has(type) or EXPLORE_INTENTS.has(type)


static func is_encounter_intent(d: Dictionary) -> bool:
	return ENCOUNTER_INTENTS.has(str(d.get("type", "")))


## "" when d is a well-formed intent, else a short description of the first problem.
## Structural only: whether the actor may act, the path is legal etc. is the
## server's / Encounter's job.
static func validate_intent(d: Dictionary) -> String:
	var version_problem := Messages._check_version(d)
	if version_problem != "":
		return version_problem
	if typeof(d.get("type")) != TYPE_STRING:
		return "intent: missing or non-string 'type'"
	var type: String = d["type"]
	if not Messages.is_intent_type(type):
		return "intent: unknown type '%s'" % type
	if not Messages._is_non_empty_string(d.get("actor")):
		return "%s: missing or empty 'actor'" % type
	match type:
		MOVE:
			if typeof(d.get("path")) != TYPE_ARRAY:
				return "move: 'path' must be an array of [x, y]"
			var path: Array = d["path"]
			if path.is_empty():
				return "move: 'path' is empty"
			for step: Variant in path:
				if not Messages.is_position(step):
					return "move: path step %s is not [x, y]" % str(step)
		ATTACK:
			if not Messages._is_non_empty_string(d.get("target")):
				return "attack: missing or empty 'target'"
			if not Messages._is_int_like(d.get("attack_index")):
				return "attack: 'attack_index' must be an int"
			if Messages._as_int(d["attack_index"]) < 0:
				return "attack: 'attack_index' must be >= 0"
		EXPLORE_MOVE:
			if not Messages.is_position(d.get("target")):
				return "explore_move: 'target' must be [x, y]"
		SHORT_REST:
			if not Messages._is_int_like(d.get("hit_dice")):
				return "short_rest: 'hit_dice' must be an int"
			if Messages._as_int(d["hit_dice"]) < 0:
				return "short_rest: 'hit_dice' must be >= 0"
	return ""


## "" when d is a well-formed result, else a short description of the first problem.
static func validate_result(d: Dictionary) -> String:
	var version_problem := Messages._check_version(d)
	if version_problem != "":
		return version_problem
	if typeof(d.get("kind")) != TYPE_STRING:
		return "result: missing or non-string 'kind'"
	var kind: String = d["kind"]
	if not RESULT_KINDS.has(kind):
		return "result: unknown kind '%s'" % kind
	match kind:
		ENCOUNTER_EVENTS:
			if typeof(d.get("events")) != TYPE_ARRAY:
				return "encounter_events: 'events' must be an array"
			var events: Array = d["events"]
			for e: Variant in events:
				if typeof(e) != TYPE_DICTIONARY:
					return "encounter_events: every event must be a dictionary"
				var ev: Dictionary = e
				if not Messages._is_non_empty_string(ev.get("kind")):
					return "encounter_events: event without a 'kind'"
		EXPLORE_STATE:
			if typeof(d.get("entities")) != TYPE_ARRAY:
				return "explore_state: 'entities' must be an array"
			if not Messages._is_int_like(d.get("tick")):
				return "explore_state: 'tick' must be an int"
			var entities: Array = d["entities"]
			for e: Variant in entities:
				if typeof(e) != TYPE_DICTIONARY:
					return "explore_state: every entity must be a dictionary"
				var ent: Dictionary = e
				if not Messages._is_non_empty_string(ent.get("id")):
					return "explore_state: entity without an 'id'"
				if not Messages.is_position(ent.get("position")):
					return "explore_state: entity '%s' has no [x, y] position" % str(ent.get("id"))
				if not Messages._is_non_empty_string(ent.get("kind")):
					return "explore_state: entity '%s' has no 'kind'" % str(ent.get("id"))
		ERROR:
			if typeof(d.get("message")) != TYPE_STRING:
				return "error: 'message' must be a string"
		FLOOR_LOADED:
			if typeof(d.get("floor")) != TYPE_DICTIONARY:
				return "floor_loaded: 'floor' must be a dictionary"
		CHARACTER_STATE:
			if typeof(d.get("sheet")) != TYPE_DICTIONARY:
				return "character_state: 'sheet' must be a dictionary"
		FLOOR_CLEARED:
			if not Messages._is_non_empty_string(d.get("floor_id")):
				return "floor_cleared: missing or empty 'floor_id'"
	return ""


## True for a two-element array of ints (or integral floats): [x, y].
static func is_position(v: Variant) -> bool:
	if typeof(v) != TYPE_ARRAY:
		return false
	var arr: Array = v
	return arr.size() == 2 and Messages._is_int_like(arr[0]) and Messages._is_int_like(arr[1])


## [x, y] -> Vector2i. Call only after is_position() (or validate_*) passed.
static func to_position(v: Variant) -> Vector2i:
	var arr: Array = v
	return Vector2i(Messages._as_int(arr[0]), Messages._as_int(arr[1]))


## A move intent's path as Vector2i steps. Call only after validate_intent() passed.
static func path_of(intent: Dictionary) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var path: Array = intent.get("path", [])
	for step: Variant in path:
		out.append(Messages.to_position(step))
	return out


static func _check_version(d: Dictionary) -> String:
	if not Messages._is_int_like(d.get("v")):
		return "message: missing protocol version 'v'"
	var v := Messages._as_int(d["v"])
	if v != PROTOCOL_VERSION:
		return "message: unsupported protocol version %d (expected %d)" % [v, PROTOCOL_VERSION]
	return ""


static func _is_non_empty_string(v: Variant) -> bool:
	if typeof(v) != TYPE_STRING:
		return false
	var s: String = v
	return not s.is_empty()


static func _is_int_like(v: Variant) -> bool:
	if typeof(v) == TYPE_INT:
		return true
	if typeof(v) == TYPE_FLOAT:
		var f: float = v
		return is_finite(f) and f == floorf(f)
	return false


static func _as_int(v: Variant) -> int:
	if typeof(v) == TYPE_FLOAT:
		var f: float = v
		return int(f)
	var i: int = v
	return i

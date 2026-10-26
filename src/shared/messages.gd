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
##   attack      {"target": id, "attack_index": int, "bonus"?: bool}
##   cast        {"spell": id, "target"?: id, "slot_level"?: int >= 0}
##   use_feature {"feature": id, "target"?: id, "amount"?: int >= 0}
##   dash, dodge, disengage, end_turn                 no extra fields
##   use_item    {"item": id, "target"?: id}          BOTH: resolved by the encounter
##                                                    when the actor is in one, else
##                                                    out of combat by the server
##   explore_move {"target": [x, y]}                  real-time walking
##   use_stairs                                       no extra fields
##   short_rest  {"hit_dice": int >= 0}
##   equip       {"item": id, "slot": "main_hand"|"off_hand"|"armor"}
##   unequip     {"slot": "main_hand"|"off_hand"|"armor"}
##   open_chest  {"chest_id": id}                     on or adjacent to the chest
##   drop_item   {"item": id, "qty": int >= 1}        discarded (nothing on the floor in M2)
##   level_up    {"choices": {"hp": "average"|"roll", "asi"?: {ABILITY: int},
##                "learn_cantrips"?: [id], "learn_spells"?: [id], "prepared"?: [id]}}
## Results:
##   encounter_events {"events": [event dicts, each with "kind"]}
##   explore_state    {"entities": [{"id", "position": [x, y], "kind"}], "tick": int}
##   error            {"message": String}
##   floor_loaded     {"floor": FloorData.to_dict()}    sent again for every new floor
##                    extras: "entity_id", "cleared_zones", "set_id", "set_name",
##                    "floor_index" (0-based in the set), "floor_count",
##                    "chests": [{"id", "position": [x, y], "hidden": bool, "opened": bool}]
##                    (hidden chests are listed only once revealed or opened)
##   character_state  {"sheet": CharacterSheet.to_dict()}
##                    extras: "entity_id", "healed", "xp_gained", "floor_clear_xp",
##                    "leveled_to" (after a level_up intent), "long_rest", "item_used",
##                    "equipped", "unequipped", "dropped"
##   loot_gained      {"entity_id", "items": [{"item", "qty"}], "source": "chest"|"monster"|"floor"}
##                    extras: "chest_id" (chest loot)
##   chest_opened     {"chest_id": id}                  extras: "entity_id" (the opener)
##   chest_revealed   {"chest": {"id", "position", "hidden", "opened"}}
##   level_up_available {"entity_id", "choices": LevelUp.choices(...)}  one level at a
##                    time, only out of combat; answer with the level_up intent
##   game_over        {}                                the party is wiped out
##   floor_cleared    {"floor_id": String}              stairs taken / floor done
##   set_cleared      {"set_id": String}                last floor's stairs taken: the
##                                                      five-floor set is done (terminal)
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
const CAST := "cast"
const USE_ITEM := "use_item"
const USE_FEATURE := "use_feature"
const EQUIP := "equip"
const UNEQUIP := "unequip"
const OPEN_CHEST := "open_chest"
const DROP_ITEM := "drop_item"
const LEVEL_UP := "level_up"

## Equipment slot names accepted by equip / unequip (CharacterSheet.SLOTS).
const EQUIP_SLOTS: Array[String] = ["main_hand", "off_hand", "armor"]

## Intents resolved by an Encounter (Encounter.submit).
const ENCOUNTER_INTENTS: Array[String] = [
	MOVE, ATTACK, DASH, DODGE, DISENGAGE, END_TURN, CAST, USE_ITEM, USE_FEATURE,
]
## Intents resolved by the real-time floor simulation. USE_ITEM is in both
## lists: the server routes it to the encounter when the actor is in one.
const EXPLORE_INTENTS: Array[String] = [
	EXPLORE_MOVE, USE_STAIRS, SHORT_REST, EQUIP, UNEQUIP, USE_ITEM, OPEN_CHEST, DROP_ITEM, LEVEL_UP,
]

# --- Result kinds (server -> client) ---
const ENCOUNTER_EVENTS := "encounter_events"
const EXPLORE_STATE := "explore_state"
const ERROR := "error"
const FLOOR_LOADED := "floor_loaded"
const CHARACTER_STATE := "character_state"
const GAME_OVER := "game_over"
const FLOOR_CLEARED := "floor_cleared"
const SET_CLEARED := "set_cleared"
const LOOT_GAINED := "loot_gained"
const CHEST_OPENED := "chest_opened"
const CHEST_REVEALED := "chest_revealed"
const LEVEL_UP_AVAILABLE := "level_up_available"

## LOOT_GAINED "source" values.
const LOOT_SOURCE_CHEST := "chest"
const LOOT_SOURCE_MONSTER := "monster"
const LOOT_SOURCE_FLOOR := "floor"

const RESULT_KINDS: Array[String] = [
	ENCOUNTER_EVENTS, EXPLORE_STATE, ERROR, FLOOR_LOADED, CHARACTER_STATE, GAME_OVER, FLOOR_CLEARED,
	SET_CLEARED, LOOT_GAINED, CHEST_OPENED, CHEST_REVEALED, LEVEL_UP_AVAILABLE,
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


## True for intents only an Encounter resolves. USE_ITEM is NOT included (it is
## valid both in and out of combat; see is_dual_intent).
static func is_encounter_intent(d: Dictionary) -> bool:
	var type := str(d.get("type", ""))
	return ENCOUNTER_INTENTS.has(type) and not EXPLORE_INTENTS.has(type)


## True for intents valid both in an encounter and out of combat (use_item).
static func is_dual_intent(d: Dictionary) -> bool:
	var type := str(d.get("type", ""))
	return ENCOUNTER_INTENTS.has(type) and EXPLORE_INTENTS.has(type)


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
			if d.has("bonus") and typeof(d["bonus"]) != TYPE_BOOL:
				return "attack: 'bonus' must be a bool"
		CAST:
			if not Messages._is_non_empty_string(d.get("spell")):
				return "cast: missing or empty 'spell'"
			if d.has("target") and not Messages._is_non_empty_string(d["target"]):
				return "cast: 'target' must be a non-empty string"
			if d.has("slot_level"):
				if not Messages._is_int_like(d["slot_level"]) or Messages._as_int(d["slot_level"]) < 0:
					return "cast: 'slot_level' must be an int >= 0"
		USE_ITEM:
			if not Messages._is_non_empty_string(d.get("item")):
				return "use_item: missing or empty 'item'"
			if d.has("target") and not Messages._is_non_empty_string(d["target"]):
				return "use_item: 'target' must be a non-empty string"
		USE_FEATURE:
			if not Messages._is_non_empty_string(d.get("feature")):
				return "use_feature: missing or empty 'feature'"
			if d.has("target") and not Messages._is_non_empty_string(d["target"]):
				return "use_feature: 'target' must be a non-empty string"
			if d.has("amount"):
				if not Messages._is_int_like(d["amount"]) or Messages._as_int(d["amount"]) < 0:
					return "use_feature: 'amount' must be an int >= 0"
		EQUIP:
			if not Messages._is_non_empty_string(d.get("item")):
				return "equip: missing or empty 'item'"
			if not EQUIP_SLOTS.has(str(d.get("slot", ""))) or typeof(d.get("slot")) != TYPE_STRING:
				return "equip: 'slot' must be one of %s" % str(EQUIP_SLOTS)
		UNEQUIP:
			if not EQUIP_SLOTS.has(str(d.get("slot", ""))) or typeof(d.get("slot")) != TYPE_STRING:
				return "unequip: 'slot' must be one of %s" % str(EQUIP_SLOTS)
		OPEN_CHEST:
			if not Messages._is_non_empty_string(d.get("chest_id")):
				return "open_chest: missing or empty 'chest_id'"
		DROP_ITEM:
			if not Messages._is_non_empty_string(d.get("item")):
				return "drop_item: missing or empty 'item'"
			if not Messages._is_int_like(d.get("qty")) or Messages._as_int(d["qty"]) < 1:
				return "drop_item: 'qty' must be an int >= 1"
		LEVEL_UP:
			if typeof(d.get("choices")) != TYPE_DICTIONARY:
				return "level_up: 'choices' must be a dictionary"
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
		LOOT_GAINED:
			if not Messages._is_non_empty_string(d.get("entity_id")):
				return "loot_gained: missing or empty 'entity_id'"
			if typeof(d.get("items")) != TYPE_ARRAY:
				return "loot_gained: 'items' must be an array"
			var loot: Array = d["items"]
			for it: Variant in loot:
				if typeof(it) != TYPE_DICTIONARY:
					return "loot_gained: every item must be a dictionary"
				var entry: Dictionary = it
				if not Messages._is_non_empty_string(entry.get("item")):
					return "loot_gained: item without an 'item' id"
				if not Messages._is_int_like(entry.get("qty")):
					return "loot_gained: item '%s' has no int 'qty'" % str(entry.get("item"))
			if not [LOOT_SOURCE_CHEST, LOOT_SOURCE_MONSTER, LOOT_SOURCE_FLOOR].has(str(d.get("source", ""))):
				return "loot_gained: 'source' must be chest, monster or floor"
		CHEST_OPENED:
			if not Messages._is_non_empty_string(d.get("chest_id")):
				return "chest_opened: missing or empty 'chest_id'"
		CHEST_REVEALED:
			if typeof(d.get("chest")) != TYPE_DICTIONARY:
				return "chest_revealed: 'chest' must be a dictionary"
			var chest: Dictionary = d["chest"]
			if not Messages._is_non_empty_string(chest.get("id")):
				return "chest_revealed: chest without an 'id'"
			if not Messages.is_position(chest.get("position")):
				return "chest_revealed: chest '%s' has no [x, y] position" % str(chest.get("id"))
		LEVEL_UP_AVAILABLE:
			if not Messages._is_non_empty_string(d.get("entity_id")):
				return "level_up_available: missing or empty 'entity_id'"
			if typeof(d.get("choices")) != TYPE_DICTIONARY:
				return "level_up_available: 'choices' must be a dictionary"
		FLOOR_CLEARED:
			if not Messages._is_non_empty_string(d.get("floor_id")):
				return "floor_cleared: missing or empty 'floor_id'"
		SET_CLEARED:
			if not Messages._is_non_empty_string(d.get("set_id")):
				return "set_cleared: missing or empty 'set_id'"
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

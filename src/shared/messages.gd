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
##   stand                                            a prone combatant stands up
##   attack      {"target": id, "attack_index": int, "bonus"?: bool,
##                "reckless"?: bool, "smite"?: int 0..9 (slot level, 0 = none),
##                "stun"?: bool, "technique"?: "prone"|"push"|"no_reactions",
##                "retarget"?: bool}
##   cast        {"spell": id, "target"?: id, "slot_level"?: int 0..9,
##                "point"?: [x, y] (area spells), "sculpt"?: [id],
##                "metamagic"?: [id], "twin_target"?: id, "targets"?: [id],
##                "form"?: monster id (Find Familiar / Animate Dead form),
##                round C: "mode"?: String (spell variant / Wish choice), "duplicate_mode"?:
##                String, "target_kind"?: "chest"|"door"|"zone"|"landmark", "target_id"?: id,
##                "invocation"?: id, "overchannel"?: bool, "ritual"?: bool (out of combat:
##                cast as a ritual, no slot), "spend_slot"?: bool (a no-effect spell spends
##                its slot anyway)}
##                                                    BOTH: resolved by the encounter
##                                                    when the actor is in one, else
##                                                    out of combat by the server
##                                                    (OutOfCombat.cast: companions,
##                                                    heals, temp HP, restorations,
##                                                    revives, Mage Armor; long casting
##                                                    times and rituals take no real
##                                                    time in M2); answered with
##                                                    OUT_OF_COMBAT_EVENTS + CHARACTER_STATE
##   use_feature {"feature": id, "target"?: id, "amount"?: int >= 0,
##                "mode"?: String, "slot_level"?: int 0..9,
##                "allocations"?: {id: int >= 1}, "frenzy"?: bool}
##                round C: "via_familiar"?, "quivering_palm"?, "hurl_through_hell"?: bool
##   control     {"target": id, "orders": [intent dicts with a "type", not control, <= 12]}
##                                                    round C (encounter, free): orders for a
##                                                    creature the actor dominates
##   dash, dodge, disengage, end_turn                 no extra fields
##   use_item    {"item": id, "target"?: id, "bonus"?: bool}
##                                                    BOTH: resolved by the encounter
##                                                    when the actor is in one, else
##                                                    out of combat by the server
##   explore_move {"target": [x, y]}                  real-time walking
##   use_stairs                                       no extra fields
##   short_rest  {"hit_dice": int >= 0, "recover_slots"?: true | [int 1..9]}
##                                                    recover_slots: Arcane / Natural
##                                                    Recovery as the rest ends (true =
##                                                    the server picks the slots)
##   equip       {"item": id, "slot": "main_hand"|"off_hand"|"armor"}
##   unequip     {"slot": "main_hand"|"off_hand"|"armor"}
##   open_chest  {"chest_id": id}                     on or adjacent to the chest
##   open_door   {"door_id": id}                      adjacent, out of combat: closed -> open
##   close_door  {"door_id": id}                      adjacent, out of combat: open -> closed
##                                                    (nobody may stand in the doorway)
##   unlock_door {"door_id": id, "method": "key"|"tools"|"spell", "spell"?: id}
##                                                    adjacent (spell: in the spell's range);
##                                                    key: carry the door's key item (kept);
##                                                    tools: thieves' tools, DEX check (+
##                                                    proficiency) vs the door's dc; spell:
##                                                    casts "spell" (default knock) at the door
##   interact    {"prop_id": id}                      adjacent, out of combat: breaks a
##                                                    prop and rolls its loot
##   drop_item   {"item": id, "qty": int >= 1}        discarded (nothing on the floor in M2)
##   dismiss_companion {"companion_id": id}           out of combat: removes a companion
##                                                    (sheet.companions entry "id") from
##                                                    the sheet; CHARACTER_STATE extra
##                                                    "companion_dismissed"
##   reaction_policy {"policy": {trigger or reaction id: "auto"|"never"}}
##                                                    BOTH (any time, also off-turn):
##                                                    the server stores it and hands it
##                                                    to the character's encounters
##                                                    (Encounter.set_reaction_policy; kept
##                                                    across encounters and floors);
##                                                    answered with CHARACTER_STATE
##                                                    "reaction_policy"
##   level_up    {"choices": {"hp": "average"|"roll", "asi"?: {ABILITY: int},
##                "learn_cantrips"?: [id], "learn_spells"?: [id], "prepared"?: [id],
##                "subclass"?: id, "fighting_style"?: id, "expertise"?: [SKILL],
##                "skills"?: [SKILL], "invocations"?: [id], "metamagic"?: [id],
##                "feature_options"?: {feature: option}}}  (LevelUp.apply checks them)
## Results:
##   encounter_events {"events": [event dicts, each with "kind"]}
##   explore_state    {"entities": [{"id", "position": [x, y], "kind"}], "tick": int}
##   error            {"message": String}
##   floor_loaded     {"floor": FloorData.to_dict()}    sent again for every new floor
##                    (doors carry their current state and never key_item; props never
##                    loot_table; hidden chests and their tables never)
##                    extras: "entity_id", "cleared_zones", "set_id", "set_name",
##                    "floor_index" (0-based in the set), "floor_count",
##                    "chests": [{"id", "position": [x, y], "hidden": bool, "opened": bool}]
##                    (hidden chests are listed only once revealed or opened),
##                    "landings": [{"id", "position", "facing"?}], "landing_id" (where this
##                    player arrived), "doors": [{"id", "position", "state", "dc"?, "keyed"?,
##                    "key_item"?}], "props": [{"id", "kind", "position", "hp", "blocks",
##                    "destroyed"}] (never a prop's loot_table or drops),
##                    "light" (the floor's light level: "bright"|"dim"|"dark")
##   character_state  {"sheet": CharacterSheet.to_dict()}
##                    extras: "entity_id", "healed", "xp_gained", "floor_clear_xp",
##                    "leveled_to" (after a level_up intent), "long_rest", "item_used",
##                    "equipped", "unequipped", "dropped", "slots_recovered" ([levels],
##                    after a short_rest with recover_slots), "recovery_error",
##                    "reaction_policy", "spell_cast" (out-of-combat cast),
##                    "companion_dismissed" {"id", "monster"}, "light_level" (the
##                    player's own light after a light spell), "door_unlocked" {door_id,
##                    method, consumed? (the key used up)}, "unlock_failed" {door_id,
##                    total, dc}, "keys_lost" ([key item ids] gone on leaving their floor)
##                    sheet "companions" entries carry a server-given "id"
##   out_of_combat_events {"entity_id": id, "spell": id, "events": [event dicts, each
##                    with "kind"]}  an out-of-combat cast; extras "slot_level" and
##                    "result" (OutOfCombat.cast's result dict). Event kinds:
##                    the core's (OutOfCombat.cast): cast {actor, spell, target,
##                    slot_level, casting_time, ritual (the spell's tag), as_ritual,
##                    invocation?}, companion_summoned {caster, spell, monster, count,
##                    companion_ids}, heal {target, amount, hp_after}, temp_hp {target,
##                    amount, temp_hp_after}, revived {target, hp}, restored {target,
##                    conditions_removed, exhaustion}, buff {target, buff, ac}; round C
##                    exploration_effect {actor, spell, effect, reveal?, target_kind?,
##                    target_id?, ...} (the server then resolves it: door_changed,
##                    chest_revealed, chest_opened, reveal), no_effect {actor, spell,
##                    reason}, lingering_added {target, spell, lingering_kind, encounters}
##   loot_gained      {"entity_id", "items": [{"item", "qty"}], "source": "chest"|"monster"|
##                    "floor"|"prop"}  extras: "chest_id" (chest loot), "prop_id" (a broken prop)
##   chest_opened     {"chest_id": id}                  extras: "entity_id" (the opener)
##   chest_revealed   {"chest": {"id", "position", "hidden", "opened", "locked"?}}
##   door_changed     {"door_id", "state": "open"|"closed"|"locked", "by": entity id}
##                    extras: "method" ("hand"|"key"|"tools"|"spell"), "spell",
##                    "consumed" (the key item used up by a "key" unlock)
##   prop_destroyed   {"prop_id", "by": entity id}
##   zone_respawned   {"zone_id"}                       a cleared pack came back (its timer
##                                                      ran out with no player in its rect)
##   reveal           {"entity_id", "reveal": "monsters"|"creatures"|"hidden_chests"|"stairs"|
##                    "map"|"threat"|"traps"|"magic_items"|"teleport"|"recall"|"light"|"nothing",
##                    "spell"} + per kind: "zones" [{"zone_id", "name", "rect", "monsters"
##                    [{"id", "monster_id", "position"}]}], "chests" [ids], "stairs" [x, y],
##                    "position" [x, y], "threat" ("weal"|"woe"|"cleared"), "zone_id",
##                    "light" ("bright"|"dim"|"dark"), "reason"; only to the caster
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
const STAND := "stand"
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
const REACTION_POLICY := "reaction_policy"
const DISMISS_COMPANION := "dismiss_companion"
const OPEN_DOOR := "open_door"
const CLOSE_DOOR := "close_door"
const UNLOCK_DOOR := "unlock_door"
const INTERACT := "interact"
## Round C (encounter, free): orders for a dominated creature.
const CONTROL := "control"
## unlock_door "method" values.
const UNLOCK_KEY := "key"
const UNLOCK_TOOLS := "tools"
const UNLOCK_SPELL := "spell"
const UNLOCK_METHODS: Array[String] = [UNLOCK_KEY, UNLOCK_TOOLS, UNLOCK_SPELL]
## cast "target_kind" values (exploration spells).
const TARGET_KINDS: Array[String] = ["chest", "door", "zone", "landmark"]
## Most orders one control intent may carry (Encounter._check_control).
const MAX_CONTROL_ORDERS := 12
## Reaction triggers of a reaction policy (Combatant.reaction_policy); a key
## may also be a reaction id. Values: "auto" (react when able) or "never".
const REACTION_TRIGGERS: Array[String] = [
	"creature_left_reach", "creature_hit_me", "damage_taken", "missed", "failed_save",
	"ally_attacked", "ally_hit", "spell_cast_in_range",
]
const REACTION_POLICY_VALUES: Array[String] = ["auto", "never"]

## Equipment slot names accepted by equip / unequip (CharacterSheet.SLOTS).
const EQUIP_SLOTS: Array[String] = ["main_hand", "off_hand", "armor"]
## Open Hand Technique options of an attack's "technique" (Encounter.TECHNIQUES).
const TECHNIQUES: Array[String] = ["prone", "push", "no_reactions"]
## Highest spell slot level ("slot_level", "smite", recovered slots).
const MAX_SLOT_LEVEL := 9

## Intents resolved by an Encounter (Encounter.submit).
const ENCOUNTER_INTENTS: Array[String] = [
	MOVE, STAND, ATTACK, DASH, DODGE, DISENGAGE, END_TURN, CAST, USE_ITEM, USE_FEATURE, REACTION_POLICY, CONTROL,
]
## Intents resolved by the real-time floor simulation. USE_ITEM and CAST are
## in both lists: the server routes them to the encounter when the actor is in one.
const EXPLORE_INTENTS: Array[String] = [
	EXPLORE_MOVE, USE_STAIRS, SHORT_REST, EQUIP, UNEQUIP, USE_ITEM, CAST, OPEN_CHEST, DROP_ITEM, LEVEL_UP,
	REACTION_POLICY, DISMISS_COMPANION, OPEN_DOOR, CLOSE_DOOR, UNLOCK_DOOR, INTERACT,
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
const OUT_OF_COMBAT_EVENTS := "out_of_combat_events"
const DOOR_CHANGED := "door_changed"
const PROP_DESTROYED := "prop_destroyed"
const ZONE_RESPAWNED := "zone_respawned"
const REVEAL := "reveal"

## LOOT_GAINED "source" values.
const LOOT_SOURCE_CHEST := "chest"
const LOOT_SOURCE_MONSTER := "monster"
const LOOT_SOURCE_FLOOR := "floor"
const LOOT_SOURCE_PROP := "prop"
const LOOT_SOURCES: Array[String] = [LOOT_SOURCE_CHEST, LOOT_SOURCE_MONSTER, LOOT_SOURCE_FLOOR, LOOT_SOURCE_PROP]

const RESULT_KINDS: Array[String] = [
	ENCOUNTER_EVENTS, EXPLORE_STATE, ERROR, FLOOR_LOADED, CHARACTER_STATE, GAME_OVER, FLOOR_CLEARED,
	SET_CLEARED, LOOT_GAINED, CHEST_OPENED, CHEST_REVEALED, LEVEL_UP_AVAILABLE, OUT_OF_COMBAT_EVENTS,
	DOOR_CHANGED, PROP_DESTROYED, ZONE_RESPAWNED, REVEAL,
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


## True for intents only an Encounter resolves. USE_ITEM and CAST are NOT
## included (they are valid both in and out of combat; see is_dual_intent).
static func is_encounter_intent(d: Dictionary) -> bool:
	var type := str(d.get("type", ""))
	return ENCOUNTER_INTENTS.has(type) and not EXPLORE_INTENTS.has(type)


## True for intents valid both in an encounter and out of combat (use_item,
## cast, reaction_policy).
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
			if d.has("mode") and (typeof(d["mode"]) != TYPE_STRING or not ["walk", "fly", "teleport"].has(str(d["mode"]))):
				return "move: 'mode' must be walk, fly or teleport"
		ATTACK:
			if not Messages._is_non_empty_string(d.get("target")):
				return "attack: missing or empty 'target'"
			if not Messages._is_int_like(d.get("attack_index")):
				return "attack: 'attack_index' must be an int"
			if Messages._as_int(d["attack_index"]) < 0:
				return "attack: 'attack_index' must be >= 0"
			for key: String in ["bonus", "reckless", "stun", "retarget", "haste", "via_familiar", "quivering_palm", "hurl_through_hell"]:
				if d.has(key) and typeof(d[key]) != TYPE_BOOL:
					return "attack: '%s' must be a bool" % key
			if d.has("smite") and not Messages._is_slot_level(d["smite"]):
				return "attack: 'smite' must be a slot level 0..%d" % MAX_SLOT_LEVEL
			if d.has("technique") and (typeof(d["technique"]) != TYPE_STRING or not TECHNIQUES.has(str(d["technique"]))):
				return "attack: 'technique' must be one of %s" % ", ".join(TECHNIQUES)
		CAST:
			if not Messages._is_non_empty_string(d.get("spell")):
				return "cast: missing or empty 'spell'"
			if d.has("target") and not Messages._is_non_empty_string(d["target"]):
				return "cast: 'target' must be a non-empty string"
			if d.has("slot_level") and not Messages._is_slot_level(d["slot_level"]):
				return "cast: 'slot_level' must be an int 0..%d" % MAX_SLOT_LEVEL
			if d.has("point") and not Messages.is_position(d["point"]):
				return "cast: 'point' must be [x, y]"
			for key: String in ["sculpt", "metamagic"]:
				if d.has(key) and not Messages._is_id_list(d[key]):
					return "cast: '%s' must be an array of non-empty strings" % key
			if d.has("twin_target") and not Messages._is_non_empty_string(d["twin_target"]):
				return "cast: 'twin_target' must be a non-empty string"
			if d.has("targets") and not Messages._is_id_list(d["targets"]):
				return "cast: 'targets' must be an array of non-empty strings"
			if d.has("form") and not Messages._is_non_empty_string(d["form"]):
				return "cast: 'form' must be a non-empty string"
			for key: String in ["mode", "duplicate_mode", "target_id", "invocation"]:
				if d.has(key) and not Messages._is_non_empty_string(d[key]):
					return "cast: '%s' must be a non-empty string" % key
			if d.has("target_kind") and (typeof(d["target_kind"]) != TYPE_STRING or not TARGET_KINDS.has(str(d["target_kind"]))):
				return "cast: 'target_kind' must be one of %s" % ", ".join(TARGET_KINDS)
			if d.has("target_id") and not d.has("target_kind"):
				return "cast: 'target_id' needs a 'target_kind'"
			for key: String in ["overchannel", "ritual", "spend_slot", "sustain"]:
				if d.has(key) and typeof(d[key]) != TYPE_BOOL:
					return "cast: '%s' must be a bool" % key
		USE_ITEM:
			if not Messages._is_non_empty_string(d.get("item")):
				return "use_item: missing or empty 'item'"
			if d.has("target") and not Messages._is_non_empty_string(d["target"]):
				return "use_item: 'target' must be a non-empty string"
			if d.has("bonus") and typeof(d["bonus"]) != TYPE_BOOL:
				return "use_item: 'bonus' must be a bool"
		USE_FEATURE:
			if not Messages._is_non_empty_string(d.get("feature")):
				return "use_feature: missing or empty 'feature'"
			if d.has("target") and not Messages._is_non_empty_string(d["target"]):
				return "use_feature: 'target' must be a non-empty string"
			if d.has("amount"):
				if not Messages._is_int_like(d["amount"]) or Messages._as_int(d["amount"]) < 0:
					return "use_feature: 'amount' must be an int >= 0"
			if d.has("mode") and not Messages._is_non_empty_string(d["mode"]):
				return "use_feature: 'mode' must be a non-empty string"
			if d.has("slot_level") and not Messages._is_slot_level(d["slot_level"]):
				return "use_feature: 'slot_level' must be an int 0..%d" % MAX_SLOT_LEVEL
			if d.has("frenzy") and typeof(d["frenzy"]) != TYPE_BOOL:
				return "use_feature: 'frenzy' must be a bool"
			if d.has("allocations"):
				if typeof(d["allocations"]) != TYPE_DICTIONARY:
					return "use_feature: 'allocations' must be a dictionary {id: hit points}"
				var alloc: Dictionary = d["allocations"]
				for key: Variant in alloc.keys():
					if not Messages._is_non_empty_string(key):
						return "use_feature: 'allocations' keys must be combatant ids"
					if not Messages._is_int_like(alloc[key]) or Messages._as_int(alloc[key]) < 1:
						return "use_feature: allocation for '%s' must be an int >= 1" % str(key)
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
		DISMISS_COMPANION:
			if not Messages._is_non_empty_string(d.get("companion_id")):
				return "dismiss_companion: missing or empty 'companion_id'"
		OPEN_DOOR, CLOSE_DOOR:
			if not Messages._is_non_empty_string(d.get("door_id")):
				return "%s: missing or empty 'door_id'" % type
		UNLOCK_DOOR:
			if not Messages._is_non_empty_string(d.get("door_id")):
				return "unlock_door: missing or empty 'door_id'"
			if typeof(d.get("method")) != TYPE_STRING or not UNLOCK_METHODS.has(str(d.get("method"))):
				return "unlock_door: 'method' must be one of %s" % ", ".join(UNLOCK_METHODS)
			if d.has("spell") and not Messages._is_non_empty_string(d["spell"]):
				return "unlock_door: 'spell' must be a non-empty string"
		INTERACT:
			if not Messages._is_non_empty_string(d.get("prop_id")):
				return "interact: missing or empty 'prop_id'"
		CONTROL:
			if not Messages._is_non_empty_string(d.get("target")):
				return "control: missing or empty 'target'"
			if typeof(d.get("orders")) != TYPE_ARRAY:
				return "control: 'orders' must be an array of intents"
			var orders: Array = d["orders"]
			if orders.size() > MAX_CONTROL_ORDERS:
				return "control: at most %d orders" % MAX_CONTROL_ORDERS
			for o: Variant in orders:
				if typeof(o) != TYPE_DICTIONARY or not Messages._is_non_empty_string((o as Dictionary).get("type")):
					return "control: every order must be an intent with a 'type'"
				if str((o as Dictionary)["type"]) == CONTROL:
					return "control: an order may not be another control"
		REACTION_POLICY:
			if typeof(d.get("policy")) != TYPE_DICTIONARY:
				return "reaction_policy: 'policy' must be a dictionary {trigger: \"auto\"|\"never\"}"
			var policy: Dictionary = d["policy"]
			for key: Variant in policy.keys():
				if not Messages._is_non_empty_string(key):
					return "reaction_policy: keys must be trigger or reaction ids"
				if typeof(policy[key]) != TYPE_STRING or not REACTION_POLICY_VALUES.has(str(policy[key])):
					return "reaction_policy: '%s' must be \"auto\" or \"never\"" % str(key)
		EXPLORE_MOVE:
			if not Messages.is_position(d.get("target")):
				return "explore_move: 'target' must be [x, y]"
		SHORT_REST:
			if not Messages._is_int_like(d.get("hit_dice")):
				return "short_rest: 'hit_dice' must be an int"
			if Messages._as_int(d["hit_dice"]) < 0:
				return "short_rest: 'hit_dice' must be >= 0"
			if d.has("recover_slots"):
				var rs: Variant = d["recover_slots"]
				if typeof(rs) == TYPE_ARRAY:
					for lvl: Variant in (rs as Array):
						if not Messages._is_slot_level(lvl) or Messages._as_int(lvl) < 1:
							return "short_rest: 'recover_slots' levels must be ints 1..%d" % MAX_SLOT_LEVEL
				elif typeof(rs) != TYPE_BOOL:
					return "short_rest: 'recover_slots' must be a bool or an array of slot levels"
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
			if not LOOT_SOURCES.has(str(d.get("source", ""))):
				return "loot_gained: 'source' must be one of %s" % ", ".join(LOOT_SOURCES)
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
		OUT_OF_COMBAT_EVENTS:
			if not Messages._is_non_empty_string(d.get("entity_id")):
				return "out_of_combat_events: missing or empty 'entity_id'"
			if not Messages._is_non_empty_string(d.get("spell")):
				return "out_of_combat_events: missing or empty 'spell'"
			if typeof(d.get("events")) != TYPE_ARRAY:
				return "out_of_combat_events: 'events' must be an array"
			for e: Variant in (d["events"] as Array):
				if typeof(e) != TYPE_DICTIONARY or not Messages._is_non_empty_string((e as Dictionary).get("kind")):
					return "out_of_combat_events: every event must be a dictionary with a 'kind'"
		LEVEL_UP_AVAILABLE:
			if not Messages._is_non_empty_string(d.get("entity_id")):
				return "level_up_available: missing or empty 'entity_id'"
			if typeof(d.get("choices")) != TYPE_DICTIONARY:
				return "level_up_available: 'choices' must be a dictionary"
		DOOR_CHANGED:
			if not Messages._is_non_empty_string(d.get("door_id")):
				return "door_changed: missing or empty 'door_id'"
			if typeof(d.get("state")) != TYPE_STRING or not ["open", "closed", "locked"].has(str(d.get("state"))):
				return "door_changed: 'state' must be open, closed or locked"
			if d.has("consumed") and not Messages._is_non_empty_string(d.get("consumed")):
				return "door_changed: 'consumed' must be an item id"
		PROP_DESTROYED:
			if not Messages._is_non_empty_string(d.get("prop_id")):
				return "prop_destroyed: missing or empty 'prop_id'"
		ZONE_RESPAWNED:
			if not Messages._is_non_empty_string(d.get("zone_id")):
				return "zone_respawned: missing or empty 'zone_id'"
		REVEAL:
			if not Messages._is_non_empty_string(d.get("entity_id")):
				return "reveal: missing or empty 'entity_id'"
			if not Messages._is_non_empty_string(d.get("reveal")):
				return "reveal: missing or empty 'reveal'"
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


## An int (or integral float) slot level 0..MAX_SLOT_LEVEL.
static func _is_slot_level(v: Variant) -> bool:
	return Messages._is_int_like(v) and Messages._as_int(v) >= 0 and Messages._as_int(v) <= MAX_SLOT_LEVEL


## An array of non-empty strings (may be empty).
static func _is_id_list(v: Variant) -> bool:
	if typeof(v) != TYPE_ARRAY:
		return false
	for item: Variant in (v as Array):
		if not Messages._is_non_empty_string(item):
			return false
	return true


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

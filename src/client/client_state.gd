class_name ClientState
extends RefCounted
## Everything the client knows about the game, derived purely from server
## results (see Messages): FLOOR_LOADED, CHARACTER_STATE, EXPLORE_STATE,
## ENCOUNTER_EVENTS, ERROR, GAME_OVER, FLOOR_CLEARED and SET_CLEARED.
##
## Five-floor sets: FLOOR_LOADED arrives again for every new floor (extras
## set_id / set_name / floor_index / floor_count); each one replaces the floor,
## forgets the old floor's entities and encounter and bumps floor_serial so
## scenes rebuild their views. FLOOR_CLEARED on a floor with a next floor only
## means "descending" (mode LOADING until the next FLOOR_LOADED); on a single
## floor or the set's last floor it is the end (mode FLOOR_CLEARED), and
## SET_CLEARED then ends the run (mode SET_CLEARED).
##
## Pure view-model: no Nodes, no rules resolution, no dice. The client only
## predicts what it needs to drive the UI (movement left this turn, whether
## the action is spent, which tiles look reachable) and the server re-checks
## every intent. Scenes call apply() for each result and then read the state.
##
## Entities are Dictionaries:
##   {"id": String, "kind": "player"|"monster", "name": String,
##    "position": Vector2i, "hp": int (-1 = unknown), "max_hp": int (-1 = unknown),
##    "down": bool, "dead": bool}
## Optional extra fields the server sends are used when present (FLOOR_LOADED /
## CHARACTER_STATE "entity_id", EXPLORE_STATE "name"/"hp"/"max_hp"/"dead",
## ENCOUNTER_EVENTS "encounter_id"/"zone_id", CHARACTER_STATE "healed",
## "xp_gained", "floor_clear_xp", "leveled_to", "levels_pending", "long_rest",
## "item_used", "temp_hp", "equipped" / "unequipped" {item, slot}, "dropped"
## {item, qty}; legacy "levels_gained"; EXPLORE_STATE "monster_id").
## Entities also carry "monster_id" (monsters, from EXPLORE_STATE) and
## "class_id" (this client's character, from its sheet) for the icon atlas.
##
## Items, spells and level-ups (M2):
## - LOOT_GAINED / CHEST_OPENED / CHEST_REVEALED keep `chests` (only chests the
##   server has shown: FLOOR_LOADED "chests", else the floor's non-hidden ones)
##   and log the loot. The inventory itself only changes through CHARACTER_STATE
##   (the server sends one after every loot) or combat events (item_used,
##   attack "consumed", cast "slot_level", feature_used "remaining"), which
##   predict the sheet until the next CHARACTER_STATE.
## - LEVEL_UP_AVAILABLE stores `level_up_offer` (LevelUp.choices) and bumps
##   level_up_serial; a CHARACTER_STATE with "leveled_to" (or no pending
##   level left) clears it. Offers are answered only out of combat.
## - Targeting: begin_cast / begin_feature / begin_attack_targeting put the
##   next map click into `targeting` mode; intent_for_click then picks the
##   target on the clicked tile. Ranged attacks need no mode: clicking a
##   monster uses `selected_attack`.
## - Combat attacks are indexed like the server's Combatant: the sheet's
##   attacks at the start of the encounter plus the unarmed strike.

enum Mode { LOADING, EXPLORING, COMBAT, GAME_OVER, FLOOR_CLEARED, SET_CLEARED }

const KIND_PLAYER := "player"
const KIND_MONSTER := "monster"
const PLAYER_ID_PREFIX := "p"
const MAX_LOG_LINES := 200
const TEAM_PLAYERS := 0
const TARGET_CAST := "cast"
const TARGET_FEATURE := "feature"
const TARGET_ATTACK := "attack"
const FEATURE_MARTIAL_ARTS_STRIKE := "martial_arts"
## Bardic Inspiration reach (Encounter.BARDIC_INSPIRATION_RANGE_TILES).
const BARDIC_INSPIRATION_RANGE := 12
## Effect id -> the tag shown next to a combatant ("dodge" comes from the dodge event).
const STATUS_TAGS: Dictionary[String, String] = {
	"dodge": "dodging", "rage": "raging", "hex": "hexed", "guiding_bolt_mark": "marked",
	"slow": "slowed", "mockery": "mocked", "bardic_inspiration": "inspired",
	"mage_armor": "mage armor", "no_reactions": "no reactions",
}
const FEATURE_NAMES: Dictionary[String, String] = {
	"second_wind": "Second Wind", "rage": "Rage", "lay_on_hands": "Lay on Hands",
	"bardic_inspiration": "Bardic Inspiration", "martial_arts": "Martial Arts strike",
}
const SLOT_NAMES: Dictionary[String, String] = {"main_hand": "Main hand", "off_hand": "Off hand", "armor": "Armor"}
const LOOT_SOURCES: Dictionary[String, String] = {"chest": "from the chest", "monster": "from the fallen", "floor": "found on the floor"}

var player_id: String = ""
var mode: Mode = Mode.LOADING
var floor_data: FloorData = null
var sheet: CharacterSheet = null
var entities: Dictionary = {}  # id -> entity Dictionary (see above)
var tick: int = 0

# --- the player's encounter (empty / false outside combat) ---
var in_encounter: bool = false
var encounter_id: String = ""  # only known if the server tags results with "encounter_id"
var region: Rect2i = Rect2i()  # the encounter's zone rect, from the floor
var order: Array[String] = []  # initiative order of the player's encounter
var initiatives: Dictionary = {}  # combatant id -> initiative (from combatant_joined)
var round_number: int = 0
var current_actor: String = ""
var movement_remaining: int = 0  # the player's, tracked from events
var action_used: bool = false  # the player's, tracked from events
var last_winning_team: int = -1
var bonus_action_used: bool = false  # the player's, tracked from events
var attack_action_taken: bool = false  # the player took the Attack action this turn (Martial Arts)
## Combat effects per combatant id: Array[String] of effect ids (see STATUS_TAGS).
var statuses: Dictionary = {}

# --- items, chests, spells, level-ups ---
## Content definitions ({} = ContentLoader.cache()).
var content: Dictionary = {}
## Chests the client knows about: id -> {"id", "position": Vector2i, "hidden": bool, "opened": bool}.
var chests: Dictionary = {}
## Latest LEVEL_UP_AVAILABLE choices for this character ({} = none pending).
var level_up_offer: Dictionary = {}
## Bumped by every LEVEL_UP_AVAILABLE for this character.
var level_up_serial: int = 0
## Level reached by the latest answered level-up (CHARACTER_STATE "leveled_to").
var last_leveled_to: int = 0
## Items of the latest LOOT_GAINED for this character.
var last_loot: Array[Dictionary] = []
## Index into available_attacks() used by clicks on monsters and the Attack button.
var selected_attack: int = 0
## {} or {"mode": TARGET_CAST, "spell", "slot_level"} / {"mode": TARGET_FEATURE,
## "feature", "amount"} / {"mode": TARGET_ATTACK, "attack_index", "bonus"}.
var targeting: Dictionary = {}
## Why the last begin_* / targeted click did nothing ("" = fine).
var hint: String = ""

var last_error: String = ""
var cleared_floor_id: String = ""

# --- where in the set (FLOOR_LOADED extras; a single floor is a set of one) ---
var set_id: String = ""
var set_name: String = ""
var floor_index: int = 0  # 0-based position of the current floor in the set
var floor_count: int = 1
## Bumped by every FLOOR_LOADED; scenes rebuild the floor view when it changes.
var floor_serial: int = 0
var cleared_set_id: String = ""
## From the latest CHARACTER_STATE that carried them.
var last_xp_gained: int = 0
var last_levels_gained: int = 0
var log_lines: Array[String] = []
## Bumped by every apply(); scenes redraw when it changes.
var revision: int = 0

var _unread_log: Array[String] = []
var _last_seen_order: Array[String] = []  # latest encounter_started order (any encounter)
var _event_zone_id: String = ""  # "zone_id" of the ENCOUNTER_EVENTS being applied
var _combat_attacks: Array[Dictionary] = []  # snapshot at the start of the encounter


## player_id is the entity id the server gives this client ("p<peer_id>").
func _init(own_player_id: String = "p1") -> void:
	player_id = own_player_id


## Entity id the server uses for a peer's character.
static func player_id_for_peer(peer_id: int) -> String:
	return "%s%d" % [PLAYER_ID_PREFIX, peer_id]


# --- applying results ------------------------------------------------------

## Folds one server result into the state. Malformed results are logged and ignored.
func apply(result: Dictionary) -> void:
	var problem := Messages.validate_result(result)
	if problem != "":
		_log("[bad message] %s" % problem)
		revision += 1
		return
	var kind: String = result["kind"]
	match kind:
		Messages.FLOOR_LOADED:
			_apply_floor_loaded(result)
		Messages.CHARACTER_STATE:
			_apply_character_state(result)
		Messages.EXPLORE_STATE:
			_apply_explore_state(result)
		Messages.ENCOUNTER_EVENTS:
			var enc_id := str(result.get("encounter_id", ""))
			_event_zone_id = str(result.get("zone_id", ""))
			var events: Array = result["events"]
			for ev_v: Variant in events:
				var ev: Dictionary = ev_v
				_apply_event(ev, enc_id)
		Messages.ERROR:
			last_error = str(result["message"])
			_log("[!] %s" % last_error)
		Messages.GAME_OVER:
			mode = Mode.GAME_OVER
			_leave_encounter()
			_log("Your party has fallen. The delve begins anew on floor 1.")
		Messages.FLOOR_CLEARED:
			cleared_floor_id = str(result["floor_id"])
			_leave_encounter()
			if has_next_floor():
				mode = Mode.LOADING
				_log("Floor cleared! You descend the stairs to floor %d." % (floor_number() + 1))
			else:
				mode = Mode.FLOOR_CLEARED
				_log("You descend the stairs. Floor cleared!")
		Messages.SET_CLEARED:
			cleared_set_id = str(result["set_id"])
			mode = Mode.SET_CLEARED
			_leave_encounter()
			_log("%s cleared! You reach the safe zone." % (set_name if not set_name.is_empty() else "The set"))
		Messages.LOOT_GAINED:
			_apply_loot(result)
		Messages.CHEST_OPENED:
			var chest_id := str(result["chest_id"])
			if chests.has(chest_id):
				var c: Dictionary = chests[chest_id]
				c["opened"] = true
			var opener := str(result.get("entity_id", player_id))
			if opener == player_id:
				_log("You open the chest.")
		Messages.CHEST_REVEALED:
			var raw: Dictionary = result["chest"]
			var known := chests.has(str(raw["id"]))
			_put_chest(raw)
			if not known:
				_log("You discover a hidden chest!")
		Messages.LEVEL_UP_AVAILABLE:
			if str(result["entity_id"]) == player_id:
				var offered: Dictionary = result["choices"]
				level_up_offer = offered.duplicate(true)
				level_up_serial += 1
				var lvl := DictUtil.to_int(level_up_offer.get("new_level", 0), 0)
				_log("Level %d is available! Open the level-up screen to choose." % lvl)
	revision += 1


func _apply_character_state(result: Dictionary) -> void:
	var sheet_dict: Dictionary = result["sheet"]
	sheet = CharacterSheet.from_dict(sheet_dict)
	_adopt_entity_id(result)
	var who := sheet.name if not sheet.name.is_empty() else "You"
	var used := _item_extra(result.get("item_used", null))
	if not used.is_empty():
		_log("%s uses %s." % [who, item_name(used)])
	var healed := DictUtil.to_int(result.get("healed", 0), 0)
	if healed > 0:
		_log("%s regains %d HP." % [sheet.name, healed])
	var temp := DictUtil.to_int(result.get("temp_hp", 0), 0)
	if temp > 0:
		_log("%s gains %d temporary HP." % [who, temp])
	var equipped_id := _item_extra(result.get("equipped", null))
	if not equipped_id.is_empty():
		_log("%s equips %s." % [who, item_name(equipped_id)])
	var unequipped_id := _item_extra(result.get("unequipped", null))
	if not unequipped_id.is_empty():
		_log("%s puts away %s." % [who, item_name(unequipped_id)])
	var dropped_id := _item_extra(result.get("dropped", null))
	if not dropped_id.is_empty():
		var dropped_v: Variant = result["dropped"]
		var dropped_qty := 1
		if typeof(dropped_v) == TYPE_DICTIONARY:
			var dd: Dictionary = dropped_v
			dropped_qty = DictUtil.to_int(dd.get("qty", 1), 1)
		_log("%s drops %s." % [who, ClientState.quantity_text(item_name(dropped_id), dropped_qty, dropped_id == CharacterSheet.GOLD_ITEM)])
	var floor_xp := DictUtil.to_int(result.get("floor_clear_xp", 0), 0)
	if result.has("xp_gained") or result.has("levels_gained") or floor_xp > 0:
		last_xp_gained = DictUtil.to_int(result.get("xp_gained", floor_xp), floor_xp)
		last_levels_gained = DictUtil.to_int(result.get("levels_gained", 0), 0)
		if floor_xp > 0:
			_log("Floor-clear bonus: gained %d XP." % maxi(floor_xp, last_xp_gained))
		elif last_xp_gained > 0:
			_log("Gained %d XP." % last_xp_gained)
		if last_levels_gained > 0:
			_log("Level up! Now level %d." % sheet.level)
	if result.has("leveled_to"):
		last_leveled_to = DictUtil.to_int(result["leveled_to"], sheet.level)
		level_up_offer = {}
		_log("Level up! %s is now level %d." % [who, last_leveled_to])
	if not level_up_offer.is_empty() and sheet.pending_levels() <= 0:
		level_up_offer = {}  # stale: nothing left to choose
	if DictUtil.to_bool(result.get("long_rest", false), false):
		_log("You take a long rest in the safe zone: HP and Hit Dice restored.")
	if entities.has(player_id):
		var e: Dictionary = entities[player_id]
		e["hp"] = sheet.current_hp
		e["down"] = sheet.is_unconscious()
		e["dead"] = sheet.dead
		e["name"] = sheet.name
		e["max_hp"] = sheet.max_hp
		e["class_id"] = sheet.class_id
	if selected_attack >= available_attacks().size():
		selected_attack = 0


## An item id from a CHARACTER_STATE extra: "id", {"item": id} or true/other ("").
func _item_extra(v: Variant) -> String:
	if typeof(v) == TYPE_STRING:
		return str(v)
	if typeof(v) == TYPE_DICTIONARY:
		var d: Dictionary = v
		return str(d.get("item", ""))
	return ""


func _apply_loot(result: Dictionary) -> void:
	if str(result["entity_id"]) != player_id:
		return
	var items: Array = result["items"]
	last_loot.clear()
	var parts: PackedStringArray = []
	for it_v: Variant in items:
		var it: Dictionary = it_v
		var id := str(it.get("item", ""))
		var qty := DictUtil.to_int(it.get("qty", 1), 1)
		last_loot.append({"item": id, "qty": qty})
		parts.append(ClientState.quantity_text(item_name(id), qty, id == CharacterSheet.GOLD_ITEM))
	var source := str(result.get("source", ""))
	var where: String = LOOT_SOURCES.get(source, "")
	if parts.is_empty():
		_log("Nothing of value %s." % (where if not where.is_empty() else "here"))
	else:
		_log("Loot%s: %s." % [(" " + where) if not where.is_empty() else "", ", ".join(parts)])


## "Potion of Healing x2", "12 gold", "Longsword".
static func quantity_text(item_display: String, qty: int, is_gold: bool = false) -> String:
	if is_gold:
		return "%d gold" % qty
	return item_display if qty == 1 else "%s x%d" % [item_display, qty]


func _put_chest(raw: Dictionary) -> void:
	var id := str(raw.get("id", ""))
	if id.is_empty() or not Messages.is_position(raw.get("position")):
		return
	chests[id] = {
		"id": id,
		"position": Messages.to_position(raw["position"]),
		"hidden": DictUtil.to_bool(raw.get("hidden", false), false),
		"opened": DictUtil.to_bool(raw.get("opened", false), false),
	}


## A (new) floor: replaces the old one and everything that lived on it.
func _apply_floor_loaded(result: Dictionary) -> void:
	var floor_dict: Dictionary = result["floor"]
	var first := floor_data == null
	floor_data = FloorData.from_dict(floor_dict)
	floor_serial += 1
	_adopt_entity_id(result)
	set_id = str(result.get("set_id", set_id))
	set_name = str(result.get("set_name", set_name))
	floor_index = maxi(0, DictUtil.to_int(result.get("floor_index", floor_index), floor_index))
	floor_count = maxi(1, DictUtil.to_int(result.get("floor_count", floor_count), floor_count))
	if not first:
		_leave_encounter()
		_last_seen_order.clear()
		initiatives.clear()
		last_winning_team = -1
		entities.clear()
	if mode == Mode.LOADING or mode == Mode.FLOOR_CLEARED or mode == Mode.COMBAT:
		mode = Mode.EXPLORING
	chests.clear()
	targeting = {}
	if typeof(result.get("chests")) == TYPE_ARRAY:
		var listed: Array = result["chests"]
		for c_v: Variant in listed:
			if typeof(c_v) == TYPE_DICTIONARY:
				_put_chest(c_v)
	else:
		for c in floor_data.chests:
			if not c.hidden:
				chests[c.id] = {"id": c.id, "position": c.position, "hidden": false, "opened": false}
	_log("You arrive on %s." % floor_label())


## Log lines added since the last call (oldest first).
func drain_log() -> Array[String]:
	var out: Array[String] = _unread_log.duplicate()
	_unread_log.clear()
	return out


func _apply_explore_state(result: Dictionary) -> void:
	tick = DictUtil.to_int(result["tick"], tick)
	var next := {}
	var raw_entities: Array = result["entities"]
	for raw_v: Variant in raw_entities:
		var raw: Dictionary = raw_v
		var id := str(raw["id"])
		var e: Dictionary = entities[id] if entities.has(id) else _new_entity(id, str(raw["kind"]))
		e["kind"] = str(raw["kind"])
		var name_v: Variant = raw.get("name", raw.get("display_name", null))
		if typeof(name_v) == TYPE_STRING and not str(name_v).is_empty():
			e["name"] = str(name_v)
		# During the player's fight, combat events own the combatants' positions.
		if not (in_encounter and order.has(id)):
			e["position"] = Messages.to_position(raw["position"])
		if DictUtil.is_number(raw.get("hp")):
			e["hp"] = DictUtil.to_int(raw["hp"], -1)
			e["down"] = int(e["hp"]) == 0
		if DictUtil.is_number(raw.get("max_hp")):
			e["max_hp"] = DictUtil.to_int(raw["max_hp"], -1)
		if typeof(raw.get("dead")) == TYPE_BOOL:
			e["dead"] = bool(raw["dead"])
		var monster_id := str(raw.get("monster_id", ""))
		if not monster_id.is_empty():
			e["monster_id"] = monster_id
		if typeof(raw.get("class_id")) == TYPE_STRING and not str(raw["class_id"]).is_empty():
			e["class_id"] = str(raw["class_id"])
		if id == player_id and sheet != null:
			e["class_id"] = sheet.class_id
		if id == player_id and sheet != null and not DictUtil.is_number(raw.get("hp")):
			e["hp"] = sheet.current_hp
			e["max_hp"] = sheet.max_hp
			e["down"] = sheet.is_unconscious()
			e["dead"] = sheet.dead
		if bool(e["dead"]):
			e["down"] = false
		next[id] = e
	# Combatants the server leaves out while they fight stay on screen.
	if in_encounter:
		for id: String in order:
			if not next.has(id) and entities.has(id):
				next[id] = entities[id]
	entities = next


func _apply_event(ev: Dictionary, enc_id: String) -> void:
	var kind := str(ev.get("kind", ""))
	if in_encounter and not encounter_id.is_empty() and not enc_id.is_empty() and enc_id != encounter_id:
		# Another encounter's events: keep positions and health current, nothing else.
		if kind == "moved" or kind == "damage" or kind == "combatant_joined" or kind == "heal":
			_apply_world_effect(ev)
		return
	match kind:
		"combatant_joined":
			var id := str(ev.get("id", ""))
			_apply_world_effect(ev)
			initiatives[id] = DictUtil.to_int(ev.get("initiative", 0), 0)
			if in_encounter:
				if not order.has(id):
					_insert_by_initiative(id)
					_log("%s joins the fight." % display_name(id))
			elif id == player_id and not _last_seen_order.is_empty():
				# Walked into a fight that is already running.
				_enter_encounter(_last_seen_order, enc_id)
				_insert_by_initiative(id)
				_log("You join the fight!")
			elif not _last_seen_order.is_empty() and not _last_seen_order.has(id):
				_last_seen_order.append(id)
		"encounter_started":
			var started: Array[String] = []
			var raw_order: Array = ev.get("order", [])
			for id_v: Variant in raw_order:
				started.append(str(id_v))
			_last_seen_order.assign(started)
			if started.has(player_id):
				_enter_encounter(started, enc_id)
				_log("Combat! Initiative: %s" % ", ".join(_names(order)))
		"round_started":
			if in_encounter:
				round_number = DictUtil.to_int(ev.get("round", round_number), round_number)
				_log("-- Round %d --" % round_number)
		"turn_started":
			var actor := str(ev.get("actor", ""))
			_remove_status(actor, "dodge")  # Dodge lasts until the dodger's next turn
			if in_encounter and order.has(actor):
				current_actor = actor
				round_number = DictUtil.to_int(ev.get("round", round_number), round_number)
				if actor == player_id:
					movement_remaining = speed_tiles()
					action_used = false
					bonus_action_used = false
					attack_action_taken = false
					_log("Your turn.")
		"turn_ended":
			if in_encounter and str(ev.get("actor", "")) == current_actor:
				current_actor = ""
		"moved":
			_apply_world_effect(ev)
			if in_encounter and str(ev.get("actor", "")) == player_id:
				movement_remaining = maxi(0, movement_remaining - 1)
		"dash":
			var actor := str(ev.get("actor", ""))
			if actor == player_id:
				movement_remaining += speed_tiles()
				action_used = true
			_log("%s dashes." % display_name(actor))
		"dodge":
			var actor := str(ev.get("actor", ""))
			if actor == player_id:
				action_used = true
			_add_status(actor, "dodge")
			_log("%s takes the Dodge action." % display_name(actor))
		"disengage":
			var actor := str(ev.get("actor", ""))
			if actor == player_id:
				action_used = true
			_log("%s disengages." % display_name(actor))
		"opportunity_attack":
			_log("%s makes an opportunity attack on %s!" % [display_name(str(ev.get("attacker", ""))), display_name(str(ev.get("target", "")))])
		"attack":
			var attacker := str(ev.get("attacker", ""))
			var attack_kind := str(ev.get("attack_kind", "melee"))
			if attacker == player_id and current_actor == player_id:
				if DictUtil.to_bool(ev.get("bonus", false), false):
					bonus_action_used = true
				elif attack_kind != "spell":
					action_used = true
					attack_action_taken = true
			var consumed := str(ev.get("consumed", ""))
			if attacker == player_id and sheet != null and not consumed.is_empty():
				sheet.remove_item(consumed, 1, _content())
			# The attack used up the guiding bolt mark on the target and the attacker's mockery.
			_remove_status(str(ev.get("target", "")), "guiding_bolt_mark")
			_remove_status(attacker, "mockery")
			_log(_attack_line(ev))
		"damage":
			_apply_world_effect(ev)
			_log(_damage_line(ev))
		"death_save":
			_apply_death_save(ev)
		"cast":
			_apply_cast(ev)
		"save":
			_log(_save_line(ev))
		"heal":
			_apply_world_effect(ev)
			_log(_heal_line(ev))
		"temp_hp":
			var target := str(ev.get("target", ""))
			var after := DictUtil.to_int(ev.get("temp_hp_after", 0), 0)
			if target == player_id and sheet != null:
				sheet.temp_hp = after
			_log("%s gains %d temporary HP." % [display_name(target), DictUtil.to_int(ev.get("amount", 0), 0)])
		"item_used":
			var actor := str(ev.get("actor", ""))
			var item := str(ev.get("item", ""))
			if actor == player_id:
				var def := item_def(item)
				if current_actor == player_id:
					if def != null and def.use_action == "bonus_action":
						bonus_action_used = true
					else:
						action_used = true
				if sheet != null:
					sheet.remove_item(item, 1, _content())
			_log("%s uses %s." % [display_name(actor), item_name(item)])
		"feature_used":
			var actor := str(ev.get("actor", ""))
			var feature := str(ev.get("feature", ""))
			if actor == player_id:
				if current_actor == player_id:
					if feature == ClassDefinition.FEATURE_LAY_ON_HANDS:
						action_used = true
					else:
						bonus_action_used = true
				if sheet != null and ev.has("remaining"):
					sheet.class_resources[feature] = DictUtil.to_int(ev["remaining"], 0)
			var target := str(ev.get("target", actor))
			var line := "%s uses %s" % [display_name(actor), ClientState.feature_name(feature)]
			if not target.is_empty() and target != actor:
				line += " on %s" % display_name(target)
			_log(line + ".")
		"inspiration_used":
			var actor := str(ev.get("actor", ""))
			_remove_status(actor, "bardic_inspiration")
			_log("%s adds a Bardic Inspiration die: d%d rolled %d." % [display_name(actor),
				DictUtil.to_int(ev.get("die", 0), 0), DictUtil.to_int(ev.get("roll", 0), 0)])
		"effect_applied":
			var target := str(ev.get("target", ""))
			var effect := str(ev.get("effect", ""))
			_add_status(target, effect)
			_log(_effect_line(target, effect, true))
		"effect_ended":
			var target := str(ev.get("target", ""))
			var effect := str(ev.get("effect", ""))
			_remove_status(target, effect)
			_log(_effect_line(target, effect, false))
		"combatant_removed":
			var id := str(ev.get("id", ""))
			order.erase(id)
			_last_seen_order.erase(id)
			if id == player_id:
				_leave_encounter()
		"encounter_ended":
			var winner := DictUtil.to_int(ev.get("winning_team", -1), -1)
			_last_seen_order.clear()
			if in_encounter:
				last_winning_team = winner
				_leave_encounter()
				if winner == TEAM_PLAYERS:
					_log("Victory! The fight is over.")
				else:
					_log("The fight is over.")
		_:
			pass


## Position / health changes that hold no matter whose encounter they belong to.
func _apply_world_effect(ev: Dictionary) -> void:
	var kind := str(ev.get("kind", ""))
	match kind:
		"combatant_joined":
			var e := _entity_or_new(str(ev.get("id", "")))
			if Messages.is_position(ev.get("position")):
				e["position"] = Messages.to_position(ev["position"])
		"moved":
			var e := _entity_or_new(str(ev.get("actor", "")))
			if Messages.is_position(ev.get("to")):
				e["position"] = Messages.to_position(ev["to"])
		"damage":
			var target := str(ev.get("target", ""))
			var e := _entity_or_new(target)
			var hp := DictUtil.to_int(ev.get("hp_after", 0), 0)
			var died := DictUtil.to_bool(ev.get("died", false), false)
			e["hp"] = hp
			e["dead"] = died
			e["down"] = hp == 0 and not died
			if target == player_id and sheet != null:
				sheet.current_hp = hp
				if typeof(ev.get("temp_hp_after")) != TYPE_NIL:
					sheet.temp_hp = DictUtil.to_int(ev["temp_hp_after"], sheet.temp_hp)
				if died:
					sheet.dead = true
				elif hp == 0 and DictUtil.to_bool(ev.get("dropped", false), false):
					sheet.reset_death_saves()
		"heal":
			var target := str(ev.get("target", ""))
			var e := _entity_or_new(target)
			var hp := DictUtil.to_int(ev.get("hp_after", 0), 0)
			e["hp"] = hp
			if hp > 0:
				e["down"] = false
			if target == player_id and sheet != null:
				sheet.current_hp = hp
				if DictUtil.to_bool(ev.get("revived", false), false) or hp > 0:
					sheet.reset_death_saves()


func _apply_death_save(ev: Dictionary) -> void:
	var actor := str(ev.get("actor", ""))
	var e := _entity_or_new(actor)
	var died := DictUtil.to_bool(ev.get("died", false), false)
	var regained := DictUtil.to_bool(ev.get("regained", false), false)
	var stable := DictUtil.to_bool(ev.get("stable", false), false)
	var successes := DictUtil.to_int(ev.get("successes", 0), 0)
	var failures := DictUtil.to_int(ev.get("failures", 0), 0)
	if died:
		e["dead"] = true
		e["down"] = false
		e["hp"] = 0
	elif regained:
		e["down"] = false
		e["hp"] = 1
	if actor == player_id and sheet != null:
		sheet.death_save_successes = successes
		sheet.death_save_failures = failures
		sheet.stable = stable
		if died:
			sheet.dead = true
			sheet.current_hp = 0
		elif regained:
			sheet.current_hp = 1
	var who := display_name(actor)
	var natural := DictUtil.to_int(ev.get("natural", 0), 0)
	if died:
		_log("%s fails a death saving throw (rolled %d) and dies." % [who, natural])
	elif regained:
		_log("%s rolls a natural 20 on a death saving throw and regains 1 HP!" % who)
	elif stable:
		_log("%s is stable (rolled %d)." % [who, natural])
	else:
		_log("%s death saving throw: rolled %d (%d successes, %d failures)." % [who, natural, successes, failures])


func _enter_encounter(new_order: Array[String], enc_id: String) -> void:
	in_encounter = true
	encounter_id = enc_id
	order.assign(new_order)
	mode = Mode.COMBAT if mode == Mode.EXPLORING or mode == Mode.LOADING else mode
	current_actor = ""
	round_number = 0
	movement_remaining = 0
	action_used = false
	bonus_action_used = false
	attack_action_taken = false
	statuses.clear()
	targeting = {}
	_combat_attacks = _attacks_from_sheet()
	region = Rect2i()
	if floor_data != null:
		var zone := floor_data.get_zone(_event_zone_id) if not _event_zone_id.is_empty() else null
		if zone == null:
			zone = floor_data.zone_at(player_position())
		if zone != null:
			region = zone.rect


func _leave_encounter() -> void:
	in_encounter = false
	encounter_id = ""
	order.clear()
	current_actor = ""
	round_number = 0
	movement_remaining = 0
	action_used = false
	bonus_action_used = false
	attack_action_taken = false
	statuses.clear()
	targeting = {}
	_combat_attacks.clear()
	region = Rect2i()
	if mode == Mode.COMBAT:
		mode = Mode.EXPLORING
	# The server removes the slain; drop them now rather than at the next explore tick.
	for id: String in entities.keys():
		var e: Dictionary = entities[id]
		if bool(e["dead"]) and str(e["kind"]) == KIND_MONSTER:
			entities.erase(id)


## Mid-fight joiners: placed by initiative among the known combatants (the
## server's tracker is authoritative; this only orders the HUD list).
func _insert_by_initiative(id: String) -> void:
	var mine: int = initiatives.get(id, 0)
	for i in range(order.size()):
		var other: int = initiatives.get(order[i], 0)
		if mine > other:
			order.insert(i, id)
			return
	order.append(id)


func _new_entity(id: String, kind: String) -> Dictionary:
	return {"id": id, "kind": kind, "name": "", "position": Vector2i.ZERO, "hp": -1, "max_hp": -1, "down": false, "dead": false}


## The server may name this client's entity explicitly ("entity_id").
func _adopt_entity_id(result: Dictionary) -> void:
	var id_v: Variant = result.get("entity_id", null)
	if typeof(id_v) == TYPE_STRING and not str(id_v).is_empty():
		player_id = str(id_v)


func _entity_or_new(id: String) -> Dictionary:
	if not entities.has(id):
		entities[id] = _new_entity(id, guess_kind(id))
	var e: Dictionary = entities[id]
	return e


## Kind of an id never seen in EXPLORE_STATE: "p<digits>" is a player.
func guess_kind(id: String) -> String:
	if id == player_id:
		return KIND_PLAYER
	if id.begins_with(PLAYER_ID_PREFIX) and id.substr(PLAYER_ID_PREFIX.length()).is_valid_int():
		return KIND_PLAYER
	return KIND_MONSTER


func _log(line: String) -> void:
	log_lines.append(line)
	_unread_log.append(line)
	if log_lines.size() > MAX_LOG_LINES:
		log_lines.remove_at(0)


func _attack_line(ev: Dictionary) -> String:
	var attacker := display_name(str(ev.get("attacker", "")))
	var target := display_name(str(ev.get("target", "")))
	var weapon := str(ev.get("attack_name", "an attack"))
	var total := DictUtil.to_int(ev.get("total", 0), 0)
	var ac := DictUtil.to_int(ev.get("target_ac", 0), 0)
	var mode_name := str(ev.get("advantage", "normal"))
	var rolls := ""
	if typeof(ev.get("d20s")) == TYPE_ARRAY:
		var d20s: Array = ev["d20s"]
		if d20s.size() > 1:
			var parts: PackedStringArray = []
			for r: Variant in d20s:
				parts.append(str(DictUtil.to_int(r, 0)))
			rolls = " [%s, %s]" % ["/".join(parts), mode_name]
	var outcome := "misses"
	if DictUtil.to_bool(ev.get("critical", false), false):
		outcome = "CRITS"
	elif DictUtil.to_bool(ev.get("hit", false), false):
		outcome = "hits"
	return "%s attacks %s with %s: %d vs AC %d%s, %s." % [attacker, target, weapon, total, ac, rolls, outcome]


func _damage_line(ev: Dictionary) -> String:
	var target := display_name(str(ev.get("target", "")))
	var amount := DictUtil.to_int(ev.get("amount", 0), 0)
	var dtype := str(ev.get("type", ""))
	var line := "%s takes %d %s damage (%d HP left)." % [target, amount, dtype, DictUtil.to_int(ev.get("hp_after", 0), 0)]
	if DictUtil.to_bool(ev.get("died", false), false):
		line += " %s dies!" % target
	elif DictUtil.to_bool(ev.get("dropped", false), false):
		line += " %s falls unconscious!" % target
	return line.replace("  ", " ")


func _apply_cast(ev: Dictionary) -> void:
	var actor := str(ev.get("actor", ""))
	var spell_id := str(ev.get("spell", ""))
	var spell := spell_def(spell_id)
	var slot := DictUtil.to_int(ev.get("slot_level", 0), 0)
	if actor == player_id:
		if current_actor == player_id:
			if spell != null and spell.uses_bonus_action():
				bonus_action_used = true
			else:
				action_used = true
		if sheet != null and slot >= 1 and slot <= sheet.spell_slots.size():
			sheet.spell_slots[slot - 1] = maxi(0, sheet.spell_slots[slot - 1] - 1)
	var target := str(ev.get("target", actor))
	var line := "%s casts %s" % [display_name(actor), spell.display_name if spell != null else spell_id.capitalize()]
	if not target.is_empty() and target != actor:
		line += " at %s" % display_name(target)
	if slot > 0:
		line += " (level %d slot)" % slot
	_log(line + ".")


func _save_line(ev: Dictionary) -> String:
	var target := display_name(str(ev.get("target", "")))
	var natural := DictUtil.to_int(ev.get("natural", 0), 0)
	var total := DictUtil.to_int(ev.get("total", 0), 0)
	var dc := DictUtil.to_int(ev.get("dc", 0), 0)
	var ability := str(ev.get("ability", ""))
	var outcome := "succeeds" if DictUtil.to_bool(ev.get("success", false), false) else "fails"
	if natural == 0:
		return "%s automatically fails the %s saving throw (DC %d)." % [target, ability, dc]
	return "%s makes a %s saving throw: %d vs DC %d, %s." % [target, ability, total, dc, outcome]


func _heal_line(ev: Dictionary) -> String:
	var target := display_name(str(ev.get("target", "")))
	var amount := DictUtil.to_int(ev.get("amount", 0), 0)
	var line := "%s regains %d HP (%d HP)." % [target, amount, DictUtil.to_int(ev.get("hp_after", 0), 0)]
	if DictUtil.to_bool(ev.get("revived", false), false):
		line += " %s is back on their feet!" % target
	return line


func _effect_line(target: String, effect: String, applied: bool) -> String:
	var who := display_name(target)
	var tag: String = STATUS_TAGS.get(effect, effect.replace("_", " "))
	if applied:
		return "%s is now %s." % [who, tag]
	return "%s is no longer %s." % [who, tag]


func _add_status(id: String, effect: String) -> void:
	if id.is_empty() or effect.is_empty():
		return
	if not statuses.has(id):
		statuses[id] = [] as Array[String]
	var list: Array[String] = statuses[id]
	if not list.has(effect):
		list.append(effect)


func _remove_status(id: String, effect: String) -> void:
	if statuses.has(id):
		var list: Array[String] = statuses[id]
		list.erase(effect)


func _names(ids: Array[String]) -> PackedStringArray:
	var out: PackedStringArray = []
	for id in ids:
		out.append(display_name(id))
	return out


# --- queries for the scenes ---------------------------------------------------

## The character's name for the player, else a server-provided name, else
## the id made readable ("goblin_2" -> "Goblin 2").
func display_name(id: String) -> String:
	if id == player_id and sheet != null and not sheet.name.is_empty():
		return sheet.name
	if entities.has(id):
		var e: Dictionary = entities[id]
		var n := str(e.get("name", ""))
		if not n.is_empty():
			return n
	return id.replace("_", " ").capitalize()


func get_entity(id: String) -> Dictionary:
	if not entities.has(id):
		return {}
	var e: Dictionary = entities[id]
	return e


func has_player_entity() -> bool:
	return entities.has(player_id)


func player_position() -> Vector2i:
	if entities.has(player_id):
		var e: Dictionary = entities[player_id]
		var p: Vector2i = e["position"]
		return p
	return floor_data.arrival if floor_data != null else Vector2i.ZERO


func speed_tiles() -> int:
	return GridMath.feet_to_tiles(sheet.speed) if sheet != null else 0


func is_player_conscious() -> bool:
	return sheet != null and sheet.is_conscious()


func is_my_turn() -> bool:
	return mode == Mode.COMBAT and in_encounter and current_actor == player_id and is_player_conscious()


## Tiles holding a living entity (Vector2i -> id), WalkMap's `occupied` format.
func occupied_cells(except_id: String = "") -> Dictionary:
	var out := {}
	for id: String in entities.keys():
		var e: Dictionary = entities[id]
		if id != except_id and not bool(e["dead"]):
			var p: Vector2i = e["position"]
			out[p] = id
	return out


## The walk map the player moves on right now (cropped to the region in combat).
func movement_map() -> WalkMap:
	if floor_data == null:
		return null
	if in_encounter and region.has_area():
		return floor_data.walk_map.cropped_to(region)
	return floor_data.walk_map


## Tiles the player can still move to this turn (start excluded): Vector2i -> steps.
## Empty unless it is the player's turn.
func reachable_tiles() -> Dictionary:
	if not is_my_turn() or movement_remaining <= 0:
		return {}
	var wm := movement_map()
	if wm == null:
		return {}
	var start := player_position()
	var out := wm.reachable(start, movement_remaining, occupied_cells(player_id))
	out.erase(start)
	return out


## Combat path from the player to tile within movement_remaining; empty if none.
func move_path_to(tile: Vector2i) -> Array[Vector2i]:
	var empty: Array[Vector2i] = []
	var wm := movement_map()
	if wm == null or not is_my_turn():
		return empty
	var path := wm.path_to(player_position(), tile, occupied_cells(player_id), movement_remaining)
	if path.is_empty() or path[path.size() - 1] != tile or path.size() > movement_remaining:
		return empty
	return path


## Id of a living monster standing on tile, or "".
func hostile_at(tile: Vector2i) -> String:
	for id: String in entities.keys():
		var e: Dictionary = entities[id]
		var p: Vector2i = e["position"]
		if p == tile and str(e["kind"]) == KIND_MONSTER and not bool(e["dead"]):
			return id
	return ""


## Living monsters of the player's encounter within reach, in initiative order.
func adjacent_hostiles() -> Array[String]:
	var out: Array[String] = []
	if not in_encounter:
		return out
	var me := player_position()
	for id in order:
		if not entities.has(id):
			continue
		var e: Dictionary = entities[id]
		var p: Vector2i = e["position"]
		if str(e["kind"]) == KIND_MONSTER and not bool(e["dead"]) and GridMath.is_adjacent(me, p):
			out.append(id)
	return out


func can_take_action() -> bool:
	return is_my_turn() and not action_used


func can_take_bonus_action() -> bool:
	return is_my_turn() and not bonus_action_used


## True when the selected attack can hit some hostile right now.
func can_attack() -> bool:
	return can_take_action() and not attack_targets().is_empty()


func on_stairs() -> bool:
	return floor_data != null and has_player_entity() and player_position() == floor_data.stairs


## Stairs and resting are only allowed out of combat, on the stairs tile.
func can_use_stairs() -> bool:
	return mode == Mode.EXPLORING and not in_encounter and on_stairs() and is_player_conscious()


func can_short_rest() -> bool:
	return can_use_stairs() and sheet != null and sheet.hit_dice_remaining > 0 and sheet.current_hp < sheet.max_hp


## 1-based floor number: the floor's own floor_number, else its place in the set.
func floor_number() -> int:
	if floor_data != null and floor_data.floor_number > 0:
		return floor_data.floor_number
	return floor_index + 1


## "Floor 2 — <display_name>" ("" before the first FLOOR_LOADED).
func floor_label() -> String:
	if floor_data == null:
		return ""
	return "Floor %d — %s" % [floor_number(), floor_data.display_name]


## True while playing a set whose current floor is not its last.
func has_next_floor() -> bool:
	return not set_id.is_empty() and floor_index + 1 < floor_count


func is_last_floor_of_set() -> bool:
	return not set_id.is_empty() and floor_index + 1 >= floor_count


## Text for the stairs button.
func stairs_label() -> String:
	if has_next_floor():
		return "Descend to floor %d" % (floor_number() + 1)
	if is_last_floor_of_set():
		return "Enter the safe zone"
	return "Descend"


## XP needed in total for the next level (the current level's cap at 20).
func xp_for_next_level() -> int:
	if sheet == null:
		return 0
	return Experience.xp_for_level(sheet.level + 1)


## "Lv N  XP x/y" ("" before the first CHARACTER_STATE).
func level_text() -> String:
	if sheet == null:
		return ""
	return "Lv %d  XP %d/%d" % [sheet.level, sheet.xp, xp_for_next_level()]


## Human-readable mode line for the HUD.
func mode_text() -> String:
	match mode:
		Mode.LOADING:
			return "Loading..."
		Mode.EXPLORING:
			return "Exploring"
		Mode.GAME_OVER:
			return "Game over"
		Mode.FLOOR_CLEARED:
			return "Floor cleared"
		Mode.SET_CLEARED:
			return "Set cleared"
	if current_actor.is_empty():
		return "Combat: round %d" % round_number
	if current_actor == player_id:
		return "Combat: your turn (round %d)" % round_number
	return "Combat: %s's turn (round %d)" % [display_name(current_actor), round_number]


# --- intents ------------------------------------------------------------------

## The intent a left click on tile means right now, or {} for none.
## Exploring: open a chest within reach on the tile, else walk there.
## Targeting mode: the cast / feature / attack on the creature on the tile.
## Player's combat turn: attack a hostile on the tile with the selected attack
## (adjacent for melee, in range for ranged / thrown) if the action is free,
## else move there if reachable.
func intent_for_click(tile: Vector2i) -> Dictionary:
	if floor_data == null or not has_player_entity():
		return {}
	if mode == Mode.EXPLORING and not in_encounter:
		if not is_player_conscious():
			return {}
		var chest_id := chest_at(tile)
		if not chest_id.is_empty() and can_open_chest(chest_id):
			return open_chest_intent(chest_id)
		if not floor_data.walk_map.is_walkable(tile) or tile == player_position():
			return {}
		return Messages.make_intent(Messages.EXPLORE_MOVE, {"actor": player_id, "target": GridMath.vec_to_arr(tile)})
	if not is_my_turn():
		return {}
	if is_targeting():
		return _targeted_intent(tile)
	var target := hostile_at(tile)
	if not target.is_empty():
		if order.has(target) and attack_error(target, selected_attack).is_empty():
			return attack_intent(target)
		return {}
	var path := move_path_to(tile)
	if path.is_empty():
		return {}
	return Messages.make_intent(Messages.MOVE, {"actor": player_id, "path": GridMath.vec_list_to_arr(path)})


## One step in a direction (arrow keys / WASD): walk or move, never a target pick.
func step_intent(dir: Vector2i) -> Dictionary:
	if floor_data == null or not has_player_entity() or dir == Vector2i.ZERO:
		return {}
	var tile := player_position() + dir
	if mode == Mode.EXPLORING and not in_encounter:
		if not is_player_conscious() or not floor_data.walk_map.is_walkable(tile):
			return {}
		return Messages.make_intent(Messages.EXPLORE_MOVE, {"actor": player_id, "target": GridMath.vec_to_arr(tile)})
	var path := move_path_to(tile)
	if path.is_empty():
		return {}
	return Messages.make_intent(Messages.MOVE, {"actor": player_id, "path": GridMath.vec_list_to_arr(path)})


## Attack with attack_index (-1 = selected_attack). target "" = the first
## hostile the attack can reach (adjacent for melee), in initiative order.
func attack_intent(target: String = "", attack_index: int = -1, bonus: bool = false) -> Dictionary:
	var index := selected_attack if attack_index < 0 else attack_index
	var t := target
	if t.is_empty():
		var near := attack_targets(index)
		if near.is_empty():
			return {}
		t = near[0]
	var fields := {"actor": player_id, "target": t, "attack_index": index}
	if bonus:
		fields["bonus"] = true
	return Messages.make_intent(Messages.ATTACK, fields)


## dash / dodge / disengage / end_turn / use_stairs: intents with no extra fields.
func simple_intent(type: String) -> Dictionary:
	return Messages.make_intent(type, {"actor": player_id})


func short_rest_intent(hit_dice: int = 1) -> Dictionary:
	return Messages.make_intent(Messages.SHORT_REST, {"actor": player_id, "hit_dice": hit_dice})


func cast_intent(spell_id: String, target: String = "", slot_level: int = 0) -> Dictionary:
	return Messages.make_intent(Messages.CAST, {"actor": player_id, "spell": spell_id,
		"target": target if not target.is_empty() else player_id, "slot_level": slot_level})


## use_feature; target "" = self, amount only for lay_on_hands.
func feature_intent(feature: String, target: String = "", amount: int = 0) -> Dictionary:
	var fields := {"actor": player_id, "feature": feature, "target": target if not target.is_empty() else player_id}
	if amount > 0:
		fields["amount"] = amount
	return Messages.make_intent(Messages.USE_FEATURE, fields)


## use_item on yourself: the combat intent on your turn, the exploration one otherwise (same shape).
func use_item_intent(item: String) -> Dictionary:
	return Messages.make_intent(Messages.USE_ITEM, {"actor": player_id, "item": item})


func equip_intent(item: String, slot: String) -> Dictionary:
	return Messages.make_intent(Messages.EQUIP, {"actor": player_id, "item": item, "slot": slot})


func unequip_intent(slot: String) -> Dictionary:
	return Messages.make_intent(Messages.UNEQUIP, {"actor": player_id, "slot": slot})


func drop_item_intent(item: String, qty: int = 1) -> Dictionary:
	return Messages.make_intent(Messages.DROP_ITEM, {"actor": player_id, "item": item, "qty": maxi(1, qty)})


func open_chest_intent(chest_id: String) -> Dictionary:
	return Messages.make_intent(Messages.OPEN_CHEST, {"actor": player_id, "chest_id": chest_id})


## Answers the pending level-up offer (see LevelUpDraft.to_choices()).
func level_up_intent(choices: Dictionary) -> Dictionary:
	return Messages.make_intent(Messages.LEVEL_UP, {"actor": player_id, "choices": choices.duplicate(true)})


# --- content lookups ------------------------------------------------------------

func _content() -> Dictionary:
	return ContentLoader.resolve(content)


func item_def(item_id: String) -> ItemDefinition:
	return CharacterSheet.item_def(item_id, _content())


func spell_def(spell_id: String) -> SpellDefinition:
	var spells: Dictionary = _content()["spells"]
	if not spells.has(spell_id):
		return null
	var s: SpellDefinition = spells[spell_id]
	return s


func item_name(item_id: String) -> String:
	var def := item_def(item_id)
	return def.display_name if def != null else item_id.replace("_", " ").capitalize()


func spell_name(spell_id: String) -> String:
	var def := spell_def(spell_id)
	return def.display_name if def != null else spell_id.replace("_", " ").capitalize()


static func feature_name(feature: String) -> String:
	return FEATURE_NAMES.get(feature, feature.replace("_", " ").capitalize())


## "1st", "2nd", "3rd", "4th"...
static func ordinal(n: int) -> String:
	match n:
		1:
			return "1st"
		2:
			return "2nd"
		3:
			return "3rd"
	return "%dth" % n


# --- attacks ------------------------------------------------------------------------

func _attacks_from_sheet() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if sheet == null:
		return out
	for a in sheet.attacks:
		out.append(a.duplicate(true))
	out.append(sheet.unarmed_strike())
	return out


## The attacks an attack_index refers to: in combat the server's list (the
## sheet's attacks when the encounter started + the unarmed strike), else the
## sheet's current ones + the unarmed strike.
func available_attacks() -> Array[Dictionary]:
	if in_encounter and not _combat_attacks.is_empty():
		return _combat_attacks
	return _attacks_from_sheet()


func get_attack(index: int) -> Dictionary:
	var list := available_attacks()
	if index < 0 or index >= list.size():
		return {}
	return list[index]


func select_attack(index: int) -> void:
	if index >= 0 and index < available_attacks().size():
		selected_attack = index
		revision += 1


static func is_ranged_attack(attack: Dictionary) -> bool:
	return Encounter.is_ranged_attack(attack)


## "" when the attack's item and ammunition are still carried, else why not.
func attack_supply_error(attack: Dictionary) -> String:
	if sheet == null:
		return "no character"
	var item := str(attack.get("item", ""))
	if not item.is_empty() and not sheet.has_item(item):
		return "no %s left" % item_name(item)
	var consumes := str(attack.get("consumes", ""))
	if not consumes.is_empty() and not sheet.has_item(consumes):
		return "out of %s" % item_name(consumes)
	return ""


## "Longsword (melee) +5, 1d8+3 slashing"; ranged ones add "range 16/64" and the count left.
func attack_label(attack: Dictionary) -> String:
	var kind := str(attack.get("kind", "melee"))
	var text := "%s (%s) %+d, %s %s" % [str(attack.get("name", "?")), kind,
		DictUtil.to_int(attack.get("to_hit", 0), 0), str(attack.get("damage", "")), str(attack.get("damage_type", ""))]
	if ClientState.is_ranged_attack(attack):
		var r := Encounter.attack_range_tiles(attack)
		text += ", range %d/%d" % [r[0], r[1]]
		var consumes := str(attack.get("consumes", ""))
		if not consumes.is_empty() and sheet != null:
			text += ", %d left" % sheet.count_item(consumes)
	return text.strip_edges()


## "" when the player may attack target with attacks[attack_index] now, else why not.
func attack_error(target: String, attack_index: int = -1, bonus: bool = false) -> String:
	var index := selected_attack if attack_index < 0 else attack_index
	if not is_my_turn():
		return "not your turn"
	if bonus:
		if not can_take_bonus_action():
			return "bonus action already used"
	elif action_used:
		return "action already used"
	var attack := get_attack(index)
	if attack.is_empty():
		return "no such attack"
	var supply := attack_supply_error(attack)
	if not supply.is_empty():
		return supply
	var e := get_entity(target)
	if e.is_empty() or str(e["kind"]) != KIND_MONSTER or bool(e["dead"]) or not order.has(target):
		return "not a hostile in this fight"
	var to: Vector2i = e["position"]
	var dist := GridMath.distance_tiles(player_position(), to)
	var r := Encounter.attack_range_tiles(attack)
	if not ClientState.is_ranged_attack(attack):
		return "" if dist >= 1 and dist <= maxi(1, r[1]) else "out of reach"
	if dist > r[1]:
		return "out of range (%d tiles, long range %d)" % [dist, r[1]]
	if floor_data != null and not floor_data.walk_map.has_line_of_sight(player_position(), to):
		return "no line of sight"
	return ""


## Hostiles of the player's encounter the attack can hit now, in initiative order.
func attack_targets(attack_index: int = -1, bonus: bool = false) -> Array[String]:
	var out: Array[String] = []
	if not in_encounter:
		return out
	for id in order:
		if attack_error(id, attack_index, bonus).is_empty():
			out.append(id)
	return out


## Tiles to tint for the current choice: Vector2i -> 0 (normal range) or 1
## (long range, disadvantage). A selected ranged attack (action free) or a
## targeting mode, inside the encounter region, with line of sight. {} otherwise.
func range_tiles() -> Dictionary:
	var out := {}
	if not is_my_turn() or floor_data == null:
		return out
	var normal := 0
	var long := 0
	if targeting.get("mode", "") == TARGET_CAST:
		var spell := spell_def(str(targeting["spell"]))
		if spell == null:
			return out
		normal = maxi(1, spell.range_tiles()) if spell.range_ft > 0 else 0
		long = normal
	elif targeting.get("mode", "") == TARGET_FEATURE:
		normal = BARDIC_INSPIRATION_RANGE if str(targeting["feature"]) == ClassDefinition.FEATURE_BARDIC_INSPIRATION else 1
		long = normal
	else:
		var attack := get_attack(int(targeting.get("attack_index", selected_attack)))
		if attack.is_empty() or (targeting.is_empty() and (action_used or not ClientState.is_ranged_attack(attack))):
			return out
		var r := Encounter.attack_range_tiles(attack)
		normal = r[0]
		long = r[1]
	if long <= 0:
		return out
	var me := player_position()
	var area := region if region.has_area() else Rect2i(me - Vector2i(long, long), Vector2i(long * 2 + 1, long * 2 + 1))
	var wm := floor_data.walk_map
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var t := Vector2i(x, y)
			var dist := GridMath.distance_tiles(me, t)
			if dist == 0 or dist > long or not wm.is_walkable(t):
				continue
			if not wm.has_line_of_sight(me, t):
				continue
			out[t] = 0 if dist <= normal else 1
	return out


# --- spells -------------------------------------------------------------------------

## The prepared spells for the Spells list, cantrips first, each
## {"id", "name", "level", "supported", "bonus", "target", "range_tiles",
##  "slots": Array[int] (slot levels with a slot left, >= the spell's level),
##  "error": "" when castable right now}.
func spell_entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if sheet == null:
		return out
	for id in sheet.spells_prepared:
		var def := spell_def(id)
		if def == null:
			continue
		out.append({
			"id": id, "name": def.display_name, "level": def.level, "supported": def.is_supported(),
			"bonus": def.uses_bonus_action(), "target": def.target, "range_tiles": def.range_tiles(),
			"slots": cast_slot_options(id), "error": cast_error(id),
		})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["level"]) != int(b["level"]):
			return int(a["level"]) < int(b["level"])
		return str(a["name"]) < str(b["name"]))
	return out


## Slot levels a leveled spell may use now (lowest first); [] for cantrips.
func cast_slot_options(spell_id: String) -> Array[int]:
	var out: Array[int] = []
	var def := spell_def(spell_id)
	if def == null or def.level == 0 or sheet == null:
		return out
	for lvl in range(def.level, sheet.spell_slots_max.size() + 1):
		if sheet.slots_left(lvl) > 0:
			out.append(lvl)
	return out


## "" when spell_id can be cast now (slot_level 0 = cantrip / lowest free slot).
func cast_error(spell_id: String, slot_level: int = 0) -> String:
	var def := spell_def(spell_id)
	if def == null or sheet == null:
		return "unknown spell"
	if not def.is_supported():
		return "not supported yet"
	if not sheet.is_spell_prepared(spell_id):
		return "not prepared"
	if not is_my_turn():
		return "only on your turn in combat"
	if def.uses_bonus_action():
		if bonus_action_used:
			return "bonus action already used"
	elif action_used:
		return "action already used"
	if def.level > 0:
		var slot := slot_level if slot_level > 0 else sheet.lowest_available_slot(def.level)
		if slot == 0 or slot < def.level or sheet.slots_left(slot) <= 0:
			return "no spell slot left"
	return ""


## "" when target is a valid target for spell_id from where the player stands.
func cast_target_error(spell_id: String, target: String) -> String:
	var def := spell_def(spell_id)
	if def == null:
		return "unknown spell"
	var e := get_entity(target)
	if e.is_empty() or bool(e["dead"]):
		return "no creature there"
	if def.target == SpellDefinition.TARGET_SELF and target != player_id:
		return "%s targets only yourself" % def.display_name
	var hostile := str(e["kind"]) == KIND_MONSTER
	if def.is_harmful():
		if not hostile or not order.has(target):
			return "%s needs a hostile target" % def.display_name
	elif hostile:
		return "%s needs an ally" % def.display_name
	if target != player_id:
		var reach := maxi(1, def.range_tiles()) if def.range_ft > 0 else 0
		var to: Vector2i = e["position"]
		if GridMath.distance_tiles(player_position(), to) > reach:
			return "out of range"
		if floor_data != null and not floor_data.walk_map.has_line_of_sight(player_position(), to):
			return "no line of sight"
	return ""


## Starts casting: a self-only spell returns its intent at once; others enter
## targeting mode and return {}. {} with `hint` set when it cannot be cast.
func begin_cast(spell_id: String, slot_level: int = 0) -> Dictionary:
	hint = cast_error(spell_id, slot_level)
	if not hint.is_empty():
		return {}
	var def := spell_def(spell_id)
	var slot := 0 if def.level == 0 else (slot_level if slot_level > 0 else sheet.lowest_available_slot(def.level))
	if def.target == SpellDefinition.TARGET_SELF:
		targeting = {}
		return cast_intent(spell_id, player_id, slot)
	targeting = {"mode": TARGET_CAST, "spell": spell_id, "slot_level": slot}
	hint = "%s: click a target%s." % [def.display_name, "" if def.is_harmful() else " (yourself or an ally)"]
	revision += 1
	return {}


# --- features -----------------------------------------------------------------------

## Class features usable in combat: {"id", "name", "remaining", "max", "error"}.
func feature_entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if sheet == null:
		return out
	for f in CharacterSheet.RESOURCE_FEATURES:
		if sheet.has_feature(f):
			out.append({"id": f, "name": ClientState.feature_name(f), "remaining": sheet.class_resource(f),
				"max": sheet.resource_max(f), "error": feature_error(f)})
	if sheet.has_feature(ClassDefinition.FEATURE_MARTIAL_ARTS):
		out.append({"id": FEATURE_MARTIAL_ARTS_STRIKE, "name": ClientState.feature_name(FEATURE_MARTIAL_ARTS_STRIKE),
			"remaining": -1, "max": -1, "error": feature_error(FEATURE_MARTIAL_ARTS_STRIKE)})
	return out


func feature_error(feature: String) -> String:
	if sheet == null:
		return "no character"
	if not is_my_turn():
		return "only on your turn in combat"
	if feature == FEATURE_MARTIAL_ARTS_STRIKE:
		if not attack_action_taken:
			return "take the Attack action first"
		if bonus_action_used:
			return "bonus action already used"
		return ""
	if not sheet.has_feature(feature):
		return "you lack %s" % ClientState.feature_name(feature)
	if sheet.class_resource(feature) <= 0:
		return "no uses left"
	if feature == ClassDefinition.FEATURE_LAY_ON_HANDS:
		return "action already used" if action_used else ""
	if bonus_action_used:
		return "bonus action already used"
	if feature == ClassDefinition.FEATURE_RAGE and status_tags(player_id).has("raging"):
		return "already raging"
	return ""


## Starts a feature: second_wind / rage return their intent; lay_on_hands
## (amount from the pool) and bardic_inspiration enter targeting mode; the
## Martial Arts strike targets like an attack with the unarmed strike.
func begin_feature(feature: String, amount: int = 0) -> Dictionary:
	hint = feature_error(feature)
	if not hint.is_empty():
		return {}
	match feature:
		ClassDefinition.FEATURE_LAY_ON_HANDS:
			var pool := sheet.class_resource(feature)
			targeting = {"mode": TARGET_FEATURE, "feature": feature, "amount": clampi(amount if amount > 0 else pool, 1, pool)}
			hint = "Lay on Hands (%d HP): click yourself or an adjacent ally." % int(targeting["amount"])
		ClassDefinition.FEATURE_BARDIC_INSPIRATION:
			targeting = {"mode": TARGET_FEATURE, "feature": feature, "amount": 0}
			hint = "Bardic Inspiration: click an ally within %d tiles." % BARDIC_INSPIRATION_RANGE
		FEATURE_MARTIAL_ARTS_STRIKE:
			targeting = {"mode": TARGET_ATTACK, "attack_index": available_attacks().size() - 1, "bonus": true}
			hint = "Martial Arts: click an adjacent hostile."
		_:
			targeting = {}
			return feature_intent(feature)
	revision += 1
	return {}


## Ranged / thrown attack (or any attack) via an explicit target pick.
func begin_attack_targeting(attack_index: int = -1) -> void:
	var index := selected_attack if attack_index < 0 else attack_index
	targeting = {"mode": TARGET_ATTACK, "attack_index": index, "bonus": false}
	hint = "Click a hostile to attack with %s." % str(get_attack(index).get("name", "the attack"))
	revision += 1


func is_targeting() -> bool:
	return not targeting.is_empty()


func cancel_targeting() -> void:
	if not targeting.is_empty():
		targeting = {}
		hint = ""
		revision += 1


## Id of a living creature (any kind) on tile, or "".
func creature_at(tile: Vector2i) -> String:
	if has_player_entity() and player_position() == tile and not bool(get_entity(player_id)["dead"]):
		return player_id
	for id: String in entities.keys():
		var e: Dictionary = entities[id]
		var p: Vector2i = e["position"]
		if p == tile and not bool(e["dead"]):
			return id
	return ""


func _targeted_intent(tile: Vector2i) -> Dictionary:
	var target := creature_at(tile)
	if target.is_empty():
		hint = "No creature there."
		return {}
	match str(targeting.get("mode", "")):
		TARGET_CAST:
			var spell_id := str(targeting["spell"])
			hint = cast_target_error(spell_id, target)
			if hint.is_empty():
				return cast_intent(spell_id, target, int(targeting.get("slot_level", 0)))
		TARGET_FEATURE:
			var feature := str(targeting["feature"])
			hint = feature_target_error(feature, target)
			if hint.is_empty():
				return feature_intent(feature, target, int(targeting.get("amount", 0)))
		TARGET_ATTACK:
			var index := int(targeting.get("attack_index", selected_attack))
			var bonus := bool(targeting.get("bonus", false))
			hint = attack_error(target, index, bonus)
			if hint.is_empty():
				return attack_intent(target, index, bonus)
	return {}


func feature_target_error(feature: String, target: String) -> String:
	var e := get_entity(target)
	if e.is_empty() or bool(e["dead"]):
		return "no creature there"
	if str(e["kind"]) == KIND_MONSTER:
		return "%s needs an ally" % ClientState.feature_name(feature)
	var to: Vector2i = e["position"]
	var dist := GridMath.distance_tiles(player_position(), to)
	if feature == ClassDefinition.FEATURE_BARDIC_INSPIRATION:
		if target == player_id:
			return "inspire someone else"
		if dist > BARDIC_INSPIRATION_RANGE:
			return "out of range"
		if bool(e.get("down", false)):
			return "%s cannot hear you" % display_name(target)
	elif feature == ClassDefinition.FEATURE_LAY_ON_HANDS and target != player_id and dist > 1:
		return "touch range: stand next to them"
	return ""


# --- inventory ----------------------------------------------------------------------

## Inventory rows (gold excluded, see gold()): {"item", "name", "kind", "qty",
## "weight" (total), "equipped": Array[String] slots holding it,
## "equip_slots": Array[String] slots it fits, "usable": bool}.
func inventory_rows() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if sheet == null:
		return out
	for entry in sheet.inventory:
		var id := str(entry.get("item", ""))
		if id == CharacterSheet.GOLD_ITEM:
			continue
		var qty := DictUtil.to_int(entry.get("qty", 1), 1)
		var def := item_def(id)
		var slots_held: Array[String] = []
		for slot in CharacterSheet.SLOTS:
			if sheet.equipped_item(slot) == id:
				slots_held.append(slot)
		out.append({
			"item": id, "name": def.display_name if def != null else item_name(id),
			"kind": def.kind if def != null else ItemDefinition.KIND_MISC, "qty": qty,
			"weight": (def.weight * qty) if def != null else 0.0, "equipped": slots_held,
			"equip_slots": equip_slots_for(id), "usable": def != null and def.has_implemented_use(),
		})
	return out


## Equipment slots an item can go into (main hand for weapons, off hand for
## shields and light weapons, armor for armor).
func equip_slots_for(item_id: String) -> Array[String]:
	var out: Array[String] = []
	var def := item_def(item_id)
	if def == null:
		return out
	match def.kind:
		ItemDefinition.KIND_WEAPON:
			out.append(CharacterSheet.SLOT_MAIN_HAND)
			var w := CharacterSheet.weapon_for_item(item_id, _content())
			if w != null and w.has_property("light"):
				out.append(CharacterSheet.SLOT_OFF_HAND)
		ItemDefinition.KIND_SHIELD:
			out.append(CharacterSheet.SLOT_OFF_HAND)
		ItemDefinition.KIND_ARMOR:
			out.append(CharacterSheet.SLOT_ARMOR)
	return out


func gold() -> int:
	return sheet.gold() if sheet != null else 0


func carried_weight() -> float:
	var total := 0.0
	if sheet == null:
		return total
	for entry in sheet.inventory:
		var def := item_def(str(entry.get("item", "")))
		if def != null:
			total += def.weight * DictUtil.to_int(entry.get("qty", 1), 1)
	return total


## Equipment changes (equip / unequip / drop) happen out of combat only.
func can_manage_equipment() -> bool:
	return mode == Mode.EXPLORING and not in_encounter and is_player_conscious()


## "" when the item can be used now (out of combat, or on your combat turn
## with the action / bonus action it needs).
func use_item_error(item_id: String) -> String:
	var def := item_def(item_id)
	if def == null or sheet == null or not sheet.has_item(item_id):
		return "not carried"
	if not def.has_implemented_use():
		return "cannot be used"
	if mode == Mode.EXPLORING and not in_encounter:
		return "" if is_player_conscious() else "you are down"
	if not is_my_turn():
		return "wait for your turn"
	if def.use_action == "bonus_action":
		return "bonus action already used" if bonus_action_used else ""
	return "action already used" if action_used else ""


## "AC 16: chain mail 16, DEX 0, shield +2" (how armor_class() adds up).
func ac_breakdown() -> String:
	if sheet == null:
		return ""
	var ac := sheet.armor_class()
	var raw_dex := sheet.ability_modifier(Ability.Type.DEX)
	var parts: PackedStringArray = []
	var armor_id := sheet.equipped_item(CharacterSheet.SLOT_ARMOR)
	if sheet.armor_base > 0:
		var dex := raw_dex
		if sheet.armor_max_dex == 0:
			dex = 0
		elif sheet.armor_max_dex > 0:
			dex = mini(dex, sheet.armor_max_dex)
		var armor_label := item_name(armor_id).to_lower() if not armor_id.is_empty() else "armor"
		parts.append("%s %d" % [armor_label, sheet.armor_base])
		parts.append("DEX %s" % ClientState._signed_or_zero(dex))
	else:
		var base := 10
		var label := "unarmored"
		var extra := ""
		if sheet.active_buffs.has(CharacterSheet.BUFF_MAGE_ARMOR) and CharacterSheet.MAGE_ARMOR_BASE + raw_dex + sheet.shield_bonus >= ac:
			base = CharacterSheet.MAGE_ARMOR_BASE
			label = "mage armor"
		elif sheet.has_feature("unarmored_defense_con") and 10 + raw_dex + sheet.ability_modifier(Ability.Type.CON) + sheet.shield_bonus == ac:
			label = "unarmored defense"
			extra = "CON %s" % ClientState._signed_or_zero(sheet.ability_modifier(Ability.Type.CON))
		elif sheet.has_feature("unarmored_defense_wis") and sheet.shield_bonus == 0 and 10 + raw_dex + sheet.ability_modifier(Ability.Type.WIS) == ac:
			label = "unarmored defense"
			extra = "WIS %s" % ClientState._signed_or_zero(sheet.ability_modifier(Ability.Type.WIS))
		parts.append("%s %d" % [label, base])
		parts.append("DEX %s" % ClientState._signed_or_zero(raw_dex))
		if not extra.is_empty():
			parts.append(extra)
	parts.append("shield %+d" % sheet.shield_bonus)
	return "AC %d: %s" % [ac, ", ".join(parts)]


static func _signed_or_zero(v: int) -> String:
	return "0" if v == 0 else "%+d" % v


## "Slots: 1st 2/2  2nd 0/1" ("" for non-casters). Pact magic adds "(short rest)".
func slots_text() -> String:
	if sheet == null or sheet.spell_slots_max.is_empty():
		return ""
	var parts: PackedStringArray = []
	for i in range(sheet.spell_slots_max.size()):
		if sheet.spell_slots_max[i] > 0:
			var left := sheet.spell_slots[i] if i < sheet.spell_slots.size() else 0
			parts.append("%s %d/%d" % [ClientState.ordinal(i + 1), left, sheet.spell_slots_max[i]])
	if parts.is_empty():
		return ""
	var text := "Slots: " + "  ".join(parts)
	if sheet.slot_recovery == ClassDefinition.SLOT_RECOVERY_SHORT:
		text += " (short rest)"
	return text


## "Second Wind 1/1  Rage 2/2" ("" without resource features).
func resources_text() -> String:
	if sheet == null:
		return ""
	var parts: PackedStringArray = []
	for f in CharacterSheet.RESOURCE_FEATURES:
		if sheet.has_feature(f):
			parts.append("%s %d/%d" % [ClientState.feature_name(f), sheet.class_resource(f), sheet.resource_max(f)])
	return "  ".join(parts)


## Status tags of a combatant ("dodging", "raging", "marked", ...).
func status_tags(id: String) -> PackedStringArray:
	var out: PackedStringArray = []
	if not statuses.has(id):
		return out
	var list: Array[String] = statuses[id]
	for effect in list:
		out.append(STATUS_TAGS.get(effect, effect.replace("_", " ")))
	return out


# --- chests -------------------------------------------------------------------------

## Chests to draw: every known chest (hidden ones only once revealed).
func visible_chests() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: String in chests.keys():
		var c: Dictionary = chests[id]
		out.append(c)
	return out


## Id of a known chest on tile, or "".
func chest_at(tile: Vector2i) -> String:
	for id: String in chests.keys():
		var c: Dictionary = chests[id]
		var p: Vector2i = c["position"]
		if p == tile:
			return id
	return ""


## Unopened, known, and the player stands on it or next to it, out of combat.
func can_open_chest(chest_id: String) -> bool:
	if not chests.has(chest_id) or not has_player_entity() or in_encounter or mode != Mode.EXPLORING:
		return false
	var c: Dictionary = chests[chest_id]
	var p: Vector2i = c["position"]
	return not bool(c["opened"]) and GridMath.distance_tiles(player_position(), p) <= 1


## The nearest known unopened chest ("" if none).
func nearest_closed_chest() -> String:
	var best := ""
	var best_d := 1 << 30
	for id: String in chests.keys():
		var c: Dictionary = chests[id]
		if bool(c["opened"]):
			continue
		var p: Vector2i = c["position"]
		var d := GridMath.distance_tiles(player_position(), p)
		if d < best_d:
			best_d = d
			best = id
	return best


# --- level-ups ----------------------------------------------------------------------

func has_level_up_offer() -> bool:
	return not level_up_offer.is_empty()


## A pending offer can be answered now: out of combat and alive (the server
## also accepts it after the floor / set is cleared).
func can_level_up() -> bool:
	return has_level_up_offer() and not in_encounter and sheet != null and not sheet.dead \
		and mode in [Mode.EXPLORING, Mode.FLOOR_CLEARED, Mode.SET_CLEARED]

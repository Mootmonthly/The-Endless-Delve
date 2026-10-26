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
## "xp_gained", "levels_gained", "long_rest").

enum Mode { LOADING, EXPLORING, COMBAT, GAME_OVER, FLOOR_CLEARED, SET_CLEARED }

const KIND_PLAYER := "player"
const KIND_MONSTER := "monster"
const PLAYER_ID_PREFIX := "p"
const MAX_LOG_LINES := 200
const TEAM_PLAYERS := 0

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
			var sheet_dict: Dictionary = result["sheet"]
			sheet = CharacterSheet.from_dict(sheet_dict)
			_adopt_entity_id(result)
			var healed := DictUtil.to_int(result.get("healed", 0), 0)
			if healed > 0:
				_log("%s regains %d HP." % [sheet.name, healed])
			if result.has("xp_gained") or result.has("levels_gained"):
				last_xp_gained = DictUtil.to_int(result.get("xp_gained", 0), 0)
				last_levels_gained = DictUtil.to_int(result.get("levels_gained", 0), 0)
				if last_xp_gained > 0:
					_log("Gained %d XP." % last_xp_gained)
				if last_levels_gained > 0:
					_log("Level up! Now level %d." % sheet.level)
			if DictUtil.to_bool(result.get("long_rest", false), false):
				_log("You take a long rest in the safe zone: HP and Hit Dice restored.")
			if entities.has(player_id):
				var e: Dictionary = entities[player_id]
				e["hp"] = sheet.current_hp
				e["down"] = sheet.is_unconscious()
				e["dead"] = sheet.dead
				e["name"] = sheet.name
				e["max_hp"] = sheet.max_hp
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
	revision += 1


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
		if kind == "moved" or kind == "damage" or kind == "combatant_joined":
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
			if in_encounter and order.has(actor):
				current_actor = actor
				round_number = DictUtil.to_int(ev.get("round", round_number), round_number)
				if actor == player_id:
					movement_remaining = speed_tiles()
					action_used = false
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
			if attacker == player_id and current_actor == player_id:
				action_used = true
			_log(_attack_line(ev))
		"damage":
			_apply_world_effect(ev)
			_log(_damage_line(ev))
		"death_save":
			_apply_death_save(ev)
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
				if died:
					sheet.dead = true
				elif hp == 0 and DictUtil.to_bool(ev.get("dropped", false), false):
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


func can_attack() -> bool:
	return can_take_action() and not adjacent_hostiles().is_empty()


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
## Exploring: walk there. Player's combat turn: attack an adjacent hostile on
## the tile (if the action is free), else move there if reachable.
func intent_for_click(tile: Vector2i) -> Dictionary:
	if floor_data == null or not has_player_entity():
		return {}
	if mode == Mode.EXPLORING and not in_encounter:
		if not floor_data.walk_map.is_walkable(tile) or tile == player_position() or not is_player_conscious():
			return {}
		return Messages.make_intent(Messages.EXPLORE_MOVE, {"actor": player_id, "target": GridMath.vec_to_arr(tile)})
	if not is_my_turn():
		return {}
	var target := hostile_at(tile)
	if not target.is_empty():
		if GridMath.is_adjacent(player_position(), tile) and not action_used and order.has(target):
			return attack_intent(target)
		return {}
	var path := move_path_to(tile)
	if path.is_empty():
		return {}
	return Messages.make_intent(Messages.MOVE, {"actor": player_id, "path": GridMath.vec_list_to_arr(path)})


## Attack with the first (weapon) attack; target "" = first adjacent hostile.
func attack_intent(target: String = "") -> Dictionary:
	var t := target
	if t.is_empty():
		var near := adjacent_hostiles()
		if near.is_empty():
			return {}
		t = near[0]
	return Messages.make_intent(Messages.ATTACK, {"actor": player_id, "target": t, "attack_index": 0})


## dash / dodge / disengage / end_turn / use_stairs: intents with no extra fields.
func simple_intent(type: String) -> Dictionary:
	return Messages.make_intent(type, {"actor": player_id})


func short_rest_intent(hit_dice: int = 1) -> Dictionary:
	return Messages.make_intent(Messages.SHORT_REST, {"actor": player_id, "hit_dice": hit_dice})

class_name Encounter
extends RefCounted
## Turn-based combat inside one bounded tile region (server-owned state machine).
##
## FORMING: combatants gather (add_combatant); start() needs conscious
##          combatants on >= 2 teams.
## ACTIVE:  turns follow the InitiativeTracker. Everything that changes state
##          goes through submit(intent); newcomers may still join.
## ENDED:   at most one team is still "in the fight" (winning_team), or none
##          is (winning_team = -1). A team is in the fight while at least one
##          member is conscious OR still dying (0 hp, not dead, not stable,
##          rolling death saves). So a downed solo player keeps rolling death
##          saves at its turn start while the monsters keep acting; the fight
##          only ends once the fallen die or all become stable (or one rolls a
##          natural 20 and fights on). Monsters never use death saves, so for
##          them in the fight means alive and conscious.
##
## Determinism: given the same seed, setup and accepted intents, an encounter
## produces exactly the same `events`. `intent_log` holds every accepted intent
## (plus replay-only join/remove entries), so replay() can rebuild a fight.
## Construct with a FRESH Rng (Rng.new(seed)) or replay cannot reproduce it.
##
## Intents (Dictionary, "v": 1, "actor": id of the current actor):
##   {"type": "move", "path": [[x, y], ...]}   steps via WalkMap.can_step, <= movement_remaining
##   {"type": "attack", "target": id, "attack_index": int}   action; target adjacent
##   {"type": "dash"} / {"type": "dodge"} / {"type": "disengage"}   action
##   {"type": "end_turn"}
## Results: {"ok": bool, "error": String, "events": Array[Dictionary]}.
## Events: Dictionaries with "kind" and JSON-safe values (see the M1 contract).

enum State { FORMING, ACTIVE, ENDED }

const INTENT_VERSION := 1
const MOVE := "move"
const ATTACK := "attack"
const DASH := "dash"
const DODGE := "dodge"
const DISENGAGE := "disengage"
const END_TURN := "end_turn"
## Replay-only intent_log entries recorded when the roster changes mid-fight.
## submit() never accepts these; replay() applies them.
const LOG_JOIN := "combatant_join"  # {"v", "type", "entry": setup dict}
const LOG_REMOVE := "combatant_remove"  # {"v", "type", "id"}
const MAX_AUTO_TURNS := 10000  # safety net for skipping turns at turn start

var id: String = ""
var state: State = State.FORMING
var tracker: InitiativeTracker = InitiativeTracker.new()
var rng: Rng = null
var rng_seed: int = 0  # seed_value of the Rng given to the constructor
var replay_safe: bool = false  # the Rng was fresh (unused) at construction
var walk_map: WalkMap = null  # copy of the floor map; tiles outside `region` are walls
var region: Rect2i = Rect2i()
var winning_team: int = -1
var intent_log: Array[Dictionary] = []
var events: Array[Dictionary] = []
var _combatants: Dictionary = {}  # id -> Combatant, in join order
var _setup: Array[Dictionary] = []
var _pending: Array[Dictionary] = []  # events of the operation in progress


func _init(encounter_id: String, encounter_rng: Rng, source_map: WalkMap, battle_region: Rect2i) -> void:
	id = encounter_id
	rng = encounter_rng
	if encounter_rng != null:
		rng_seed = encounter_rng.seed_value
		replay_safe = Rng.new(rng_seed).state() == encounter_rng.state()
	region = battle_region
	walk_map = source_map.cropped_to(battle_region) if source_map != null else WalkMap.new()


## Adds a combatant (rolling initiative). Its position must be inside the
## region, walkable and not occupied by a living combatant. While ACTIVE the
## newcomer first acts next round. Emits combatant_joined.
func add_combatant(c: Combatant) -> bool:
	if c == null or c.sheet == null or c.id.is_empty():
		push_error("Encounter.add_combatant: invalid combatant")
		return false
	if state == State.ENDED or _combatants.has(c.id):
		return false
	if not region.has_point(c.position) or not walk_map.is_walkable(c.position):
		return false
	if occupied_cells().has(c.position):
		return false
	_pending.clear()
	var entry := c.to_setup_dict()
	var ok := tracker.add(c, rng) if state == State.FORMING else tracker.add_mid_combat(c, rng)
	if not ok:
		return false
	_combatants[c.id] = c
	if state == State.ACTIVE:
		intent_log.append({"v": INTENT_VERSION, "type": LOG_JOIN, "entry": entry})
	_emit("combatant_joined", {
		"id": c.id,
		"name": c.display_name,
		"team": c.team,
		"initiative": c.initiative,
		"position": GridMath.vec_to_arr(c.position),
		"hp": c.sheet.current_hp,
		"max_hp": c.sheet.max_hp,
		"ac": c.sheet.armor_class(),
	})
	_pending.clear()
	return true


## Removes a combatant (fled, disconnected). If it was the current actor the
## next turn begins. Removing during FORMING breaks replay (its initiative
## roll was already drawn from the Rng).
func remove_combatant(combatant_id: String) -> bool:
	if not _combatants.has(combatant_id):
		return false
	_pending.clear()
	var current := current_actor()
	var was_current := current != null and current.id == combatant_id
	var previous_round := tracker.round_number
	if state == State.ACTIVE:
		intent_log.append({"v": INTENT_VERSION, "type": LOG_REMOVE, "id": combatant_id})
	_combatants.erase(combatant_id)
	tracker.remove(combatant_id)
	_emit("combatant_removed", {"id": combatant_id})
	if state == State.ACTIVE and not check_end() and was_current:
		if tracker.round_number != previous_round and tracker.current() != null:
			_emit("round_started", {"round": tracker.round_number})
		_begin_turns()
	_pending.clear()
	return true


## FORMING -> ACTIVE. Captures setup_snapshot() and runs the first turn start.
func start() -> bool:
	if state != State.FORMING:
		return false
	if _conscious_teams().size() < 2:
		return false
	_pending.clear()
	_setup.clear()
	for value: Variant in _combatants.values():
		var c: Combatant = value
		_setup.append(c.to_setup_dict())
	state = State.ACTIVE
	tracker.begin()
	var order: Array = []
	for c in tracker.order():
		order.append(c.id)
	_emit("encounter_started", {"order": order})
	_emit("round_started", {"round": tracker.round_number})
	_begin_turns()
	_pending.clear()
	return true


## Validates and resolves one intent from the current actor. Rejected intents
## change nothing and are not logged.
func submit(intent: Dictionary) -> Dictionary:
	_pending.clear()
	if state != State.ACTIVE:
		return _rejected("encounter is not active")
	if DictUtil.to_int(intent.get("v", -1), -1) != INTENT_VERSION:
		return _rejected("unsupported intent version")
	var actor := current_actor()
	if actor == null or str(intent.get("actor", "")) != actor.id:
		return _rejected("it is not that combatant's turn")
	if not actor.is_conscious():
		return _rejected("%s cannot act" % actor.display_name)
	var intent_type := str(intent.get("type", ""))
	var error := ""
	match intent_type:
		MOVE:
			error = _check_move(actor, intent)
		ATTACK:
			error = _check_attack(actor, intent)
		DASH, DODGE, DISENGAGE:
			if actor.action_used:
				error = "%s has already used its action" % actor.display_name
		END_TURN:
			pass
		_:
			error = "unknown intent type '%s'" % intent_type
	if not error.is_empty():
		return _rejected(error)

	intent_log.append(intent.duplicate(true))
	match intent_type:
		MOVE:
			_do_move(actor, GridMath.arr_to_vec_list(intent["path"]))
		ATTACK:
			var target := get_combatant(str(intent["target"]))
			actor.action_used = true
			_resolve_attack(actor, target, DictUtil.to_int(intent.get("attack_index", 0), 0))
			check_end()
		DASH:
			actor.action_used = true
			actor.movement_remaining += actor.speed_tiles()
			_emit("dash", {"actor": actor.id})
		DODGE:
			actor.action_used = true
			actor.dodging = true
			_emit("dodge", {"actor": actor.id})
		DISENGAGE:
			actor.action_used = true
			actor.disengaging = true
			_emit("disengage", {"actor": actor.id})
		END_TURN:
			_end_current_turn()
	# An actor knocked out during its own turn (opportunity attack) is done.
	if intent_type != END_TURN and state == State.ACTIVE and current_actor() == actor and not actor.is_conscious():
		_end_current_turn()
	var result := {"ok": true, "error": "", "events": _pending.duplicate()}
	_pending.clear()
	return result


## Convenience wrapper: ends the current actor's turn via submit(). Returns
## the next actor, or null if the encounter is not (or no longer) active.
func end_turn() -> Combatant:
	var actor := current_actor()
	if actor == null:
		return null
	submit({"v": INTENT_VERSION, "type": END_TURN, "actor": actor.id})
	return current_actor()


## Ends the encounter when at most one team is still in the fight (has a
## member who is conscious or dying; see Combatant.is_in_fight). The winner is
## that team, else -1. Emits encounter_ended once.
func check_end() -> bool:
	if state == State.ENDED:
		return true
	if state != State.ACTIVE:
		return false
	var teams := _teams_in_fight()
	if teams.size() > 1:
		return false
	var winner := -1
	for team_id: int in teams.keys():
		winner = team_id
	_end_encounter(winner)
	return true


func get_combatant(combatant_id: String) -> Combatant:
	if not _combatants.has(combatant_id):
		return null
	var c: Combatant = _combatants[combatant_id]
	return c


func current_actor() -> Combatant:
	return tracker.current() if state == State.ACTIVE else null


## All combatants in initiative order.
func combatants() -> Array[Combatant]:
	return tracker.order()


## Living (conscious or not) combatants of other teams, in initiative order.
func hostiles_of(c: Combatant) -> Array[Combatant]:
	var out: Array[Combatant] = []
	for other in tracker.order():
		if other.team != c.team and other.is_alive():
			out.append(other)
	return out


## Tiles holding a living combatant (Vector2i -> combatant id). The dead do
## not block movement.
func occupied_cells(except_id: String = "") -> Dictionary:
	var out := {}
	for value: Variant in _combatants.values():
		var c: Combatant = value
		if c.id != except_id and c.is_alive():
			out[c.position] = c.id
	return out


## Setup entries captured at start(), in join order (deep copy).
func setup_snapshot() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry in _setup:
		out.append(entry.duplicate(true))
	return out


## Events appended since index (e.g. a server remembers events.size()).
func events_since(index: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in range(maxi(0, index), events.size()):
		out.append(events[i])
	return out


## Rebuilds an encounter from its seed, setup_snapshot() and intent_log. The
## result's `events` equal the original's. Accepts JSON round-tripped data.
static func replay(seed_value: int, source_map: WalkMap, battle_region: Rect2i, setup: Array[Dictionary], intents: Array[Dictionary], encounter_id: String = "replay") -> Encounter:
	var enc := Encounter.new(encounter_id, Rng.new(seed_value), source_map, battle_region)
	for entry in setup:
		enc.add_combatant(Combatant.from_setup_dict(entry))
	enc.start()
	for intent in intents:
		var intent_type := str(intent.get("type", ""))
		if intent_type == LOG_JOIN:
			var entry_v: Variant = intent.get("entry", {})
			if typeof(entry_v) == TYPE_DICTIONARY:
				var entry: Dictionary = entry_v
				enc.add_combatant(Combatant.from_setup_dict(entry))
		elif intent_type == LOG_REMOVE:
			enc.remove_combatant(str(intent.get("id", "")))
		else:
			enc.submit(intent)
	return enc


# --- validation -------------------------------------------------------------

func _check_move(actor: Combatant, intent: Dictionary) -> String:
	var raw: Variant = intent.get("path", null)
	if typeof(raw) != TYPE_ARRAY:
		return "path must be an array of [x, y] steps"
	var steps: Array = raw
	if steps.is_empty():
		return "path is empty"
	if steps.size() > actor.movement_remaining:
		return "path has %d steps but only %d tiles of movement remain" % [steps.size(), actor.movement_remaining]
	var occupied := occupied_cells(actor.id)
	var cursor := actor.position
	for step_v: Variant in steps:
		if not GridMath.is_vec_arr(step_v):
			return "malformed path step %s" % str(step_v)
		var step := GridMath.arr_to_vec(step_v)
		if not walk_map.can_step(cursor, step, occupied):
			return "cannot step from %s to %s" % [str(cursor), str(step)]
		cursor = step
	return ""


func _check_attack(actor: Combatant, intent: Dictionary) -> String:
	if actor.action_used:
		return "%s has already used its action" % actor.display_name
	var target := get_combatant(str(intent.get("target", "")))
	if target == null:
		return "unknown target"
	if target.team == actor.team:
		return "%s is on the same team" % target.display_name
	if not target.is_alive():
		return "%s is already dead" % target.display_name
	if not GridMath.is_adjacent(actor.position, target.position):
		return "%s is out of reach" % target.display_name
	var index := DictUtil.to_int(intent.get("attack_index", 0), -1)
	if index < 0 or index >= actor.attacks.size():
		return "invalid attack_index"
	return ""


# --- resolution ------------------------------------------------------------

func _do_move(actor: Combatant, path: Array[Vector2i]) -> void:
	for step in path:
		var from := actor.position
		if not actor.disengaging:
			for hostile in _opportunity_attackers(actor, from, step):
				if not actor.is_conscious():
					break
				if not hostile.is_conscious():
					continue
				hostile.reaction_used = true
				_emit("opportunity_attack", {"attacker": hostile.id, "target": actor.id})
				_resolve_attack(hostile, actor, 0)
		if not actor.is_conscious():
			break
		actor.position = step
		actor.movement_remaining -= 1
		_emit("moved", {"actor": actor.id, "from": GridMath.vec_to_arr(from), "to": GridMath.vec_to_arr(step)})
	check_end()


## Conscious hostiles with a reaction left that `from` is in reach of and
## `to` is not (initiative order).
func _opportunity_attackers(mover: Combatant, from: Vector2i, to: Vector2i) -> Array[Combatant]:
	var out: Array[Combatant] = []
	for h in tracker.order():
		if h.team == mover.team or not h.is_conscious() or h.reaction_used or h.attacks.is_empty():
			continue
		if GridMath.is_adjacent(h.position, from) and not GridMath.is_adjacent(h.position, to):
			out.append(h)
	return out


## Rolls one attack and emits attack (+ damage on a hit). Advantage against an
## unconscious target, and any hit on it from within 5 ft is a critical hit.
## Disadvantage against a dodging target, and for a ranged attack (the target
## is always within 5 ft here).
func _resolve_attack(attacker: Combatant, target: Combatant, attack_index: int) -> AttackResult:
	var attack: Dictionary = attacker.attacks[attack_index]
	var target_down := target.sheet.is_unconscious()
	var disadvantage := (target.dodging and target.is_conscious()) or str(attack.get("kind", "melee")) == "ranged"
	var mode := D20.combine(target_down, disadvantage)
	var auto_crit := target_down and GridMath.is_adjacent(attacker.position, target.position)
	var r := AttackResolver.resolve_attack(attacker, target, attack, rng, mode, auto_crit)
	_emit("attack", {
		"attacker": attacker.id,
		"target": target.id,
		"attack_name": r.attack_name,
		"natural": r.d20.natural,
		"d20s": r.d20.all.duplicate(),
		"total": r.attack_total,
		"target_ac": r.target_ac,
		"hit": r.hit,
		"critical": r.critical,
		"fumble": r.fumble,
		"advantage": Encounter._mode_name(mode),
	})
	if r.hit:
		_emit("damage", {
			"target": target.id,
			"amount": r.damage_total,
			"type": r.damage_type,
			"hp_after": r.target_hp_after,
			"dropped": r.target_dropped,
			"died": r.target_died,
		})
	if not target.is_conscious():
		target.dodging = false
	return r


func _end_current_turn() -> void:
	var c := tracker.current()
	if c != null:
		_emit("turn_ended", {"actor": c.id})
	if check_end():
		return
	_advance()
	_begin_turns()


func _advance() -> void:
	var previous_round := tracker.round_number
	tracker.advance()
	if tracker.round_number != previous_round and tracker.current() != null:
		_emit("round_started", {"round": tracker.round_number})


## Turn-start rules for the current actor: reset its turn resources; a downed
## player who is not stable rolls a death save; anyone still not conscious
## (unconscious, stable at 0) ends the turn at once. Loops until a conscious
## actor is waiting for intents or the encounter ends. (The dead are skipped
## by the InitiativeTracker without a turn.)
func _begin_turns() -> void:
	for _i in range(MAX_AUTO_TURNS):
		if state != State.ACTIVE:
			return
		var c := tracker.current()
		if c == null:
			if not check_end():
				_end_encounter(-1)
			return
		_emit("turn_started", {"actor": c.id, "round": tracker.round_number})
		c.reset_turn()
		if c.sheet.uses_death_saves and c.sheet.is_unconscious() and not c.sheet.stable:
			var save := c.sheet.roll_death_save(rng)
			_emit("death_save", {
				"actor": c.id,
				"natural": save.natural,
				"successes": save.successes,
				"failures": save.failures,
				"stable": c.sheet.stable,
				"died": save.died,
				"regained": save.regained_consciousness,
			})
		if c.is_conscious():
			return
		_emit("turn_ended", {"actor": c.id})
		if check_end():
			return
		_advance()
	push_error("Encounter %s: turn-start loop did not settle" % id)


func _end_encounter(winner: int) -> void:
	state = State.ENDED
	winning_team = winner
	_emit("encounter_ended", {"winning_team": winner})


func _conscious_teams() -> Dictionary:
	var teams := {}
	for value: Variant in _combatants.values():
		var c: Combatant = value
		if c.is_conscious():
			teams[c.team] = true
	return teams


## Teams with at least one member who is conscious or dying.
func _teams_in_fight() -> Dictionary:
	var teams := {}
	for value: Variant in _combatants.values():
		var c: Combatant = value
		if c.is_in_fight():
			teams[c.team] = true
	return teams


func _emit(kind: String, fields: Dictionary) -> void:
	var ev := {"kind": kind}
	ev.merge(fields)
	events.append(ev)
	_pending.append(ev)


func _rejected(reason: String) -> Dictionary:
	var empty: Array[Dictionary] = []
	return {"ok": false, "error": reason, "events": empty}


static func _mode_name(mode: D20.RollMode) -> String:
	match mode:
		D20.RollMode.ADVANTAGE:
			return "advantage"
		D20.RollMode.DISADVANTAGE:
			return "disadvantage"
	return "normal"

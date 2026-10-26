class_name InstanceServer
extends Node
## Authoritative simulation of one floor of a dungeon instance (M1: one floor,
## offline). Owns every piece of game state; clients only send intents
## through a Transport and render the results it broadcasts.
##
## Tick: a fixed 20 Hz step driven from _physics_process (delta is
## accumulated, so the rate holds whatever Engine.physics_ticks_per_second
## is; the offline main scene sets it to 20). Each tick:
##   1. transport.pump() - delivers queued intents (handled immediately).
##   2. due monster turns run (MonsterBrain -> Encounter.submit).
##   3. exploration: walking entities advance one tile every
##      EXPLORE_STEP_TICKS ticks; EXPLORE_STATE is broadcast if anything moved;
##      a player stepping into an uncleared zone starts an encounter, any
##      entity stepping into an active encounter's region joins it.
## Results sent outside a pump (steps 2-3, add_player) reach a LocalTransport
## client on the next pump, i.e. the next tick.
##
## Encounters: one core Encounter per triggered zone, region = zone rect,
## each built with a fresh Rng forked from the instance seed by zone index
## (and attempt), so a zone's dice do not depend on other zones. A monster's
## turn resolves on the tick after its turn_started was broadcast
## (monster_turn_delay_ticks). When an encounter ends:
##   - players won: the zone is cleared; every surviving player at 0 hp
##     (stable or still dying) is set to 1 hp (M1 simplification);
##   - otherwise (monsters won / nobody left standing): the zone stays
##     uncleared and the monsters finish off the downed players, who die
##     (M1 simplification: no rescue outside an encounter);
##   - dead monsters are removed, survivors return to exploration, every
##     participating player gets a CHARACTER_STATE and EXPLORE_STATE is
##     broadcast; if no living player remains, GAME_OVER is broadcast once and
##     every further intent is rejected.
##
## Exploration intents (explore_move, use_stairs, short_rest) are refused
## while the sender's character is in combat; combat intents are refused
## while it explores. use_stairs needs the stairs tile and no active encounter
## on the floor; short_rest needs the stairs tile. Errors go only to the
## sending peer as ERROR results.

const TICKS_PER_SECOND := 20
const TICK_SECONDS := 1.0 / TICKS_PER_SECOND
## Exploration speed: one tile every 3 ticks (~6.7 tiles/s).
const EXPLORE_STEP_TICKS := 3
## At most this many ticks are run per _physics_process call (backlog is dropped).
const MAX_CATCH_UP_TICKS := 5
## Rng.fork stream ids: zone index + attempt * ZONE_ATTEMPT_STRIDE for
## encounters; REST_STREAM for short-rest hit dice.
const ZONE_ATTEMPT_STRIDE := 1024
const REST_STREAM := 1 << 20
const _TICK_EPSILON := 0.0001

## Ticks between a monster's turn_started and its actions (>= 1). The client
## may raise it to slow monster turns down for readability.
var monster_turn_delay_ticks: int = 1
## Ticks run since configure().
var tick: int = 0

var _transport: Transport = null
var _floor: FloorData = null
var _seed: int = 0
var _root_rng: Rng = null
var _rest_rng: Rng = null
var _monster_defs: Dictionary = {}  # id -> MonsterDefinition
var _entities: Dictionary = {}  # id -> ServerEntity, insertion order
var _peer_entities: Dictionary = {}  # peer id -> entity id
var _sessions: Dictionary = {}  # session id -> EncounterSession (active only)
var _cleared_zones: Dictionary = {}  # zone id -> true
var _zone_attempts: Dictionary = {}  # zone id -> encounters created
var _game_over: bool = false
var _floor_cleared: bool = false
var _accumulator: float = 0.0


# --- setup --------------------------------------------------------------------

## Binds the server to a transport and a floor, seeds all randomness and
## spawns every zone's monsters at their spawn points (idle until the zone
## triggers). Calling it again resets the whole simulation.
func configure(transport: Transport, floor_data: FloorData, instance_seed: int) -> void:
	if _transport != null and _transport.intent_received.is_connected(_on_intent_received):
		_transport.intent_received.disconnect(_on_intent_received)
	tick = 0
	_entities.clear()
	_peer_entities.clear()
	_sessions.clear()
	_cleared_zones.clear()
	_zone_attempts.clear()
	_game_over = false
	_floor_cleared = false
	_accumulator = 0.0
	_transport = transport
	_floor = floor_data
	_seed = instance_seed
	_root_rng = Rng.new(instance_seed)
	_rest_rng = _root_rng.fork(REST_STREAM)
	if _monster_defs.is_empty():
		_monster_defs = ContentLoader.load_monsters()
	if transport != null:
		transport.intent_received.connect(_on_intent_received)
	if floor_data == null:
		push_error("InstanceServer.configure: floor is null")
		return
	_spawn_monsters()


## Adds a player character (the server keeps its own copy of the sheet) as
## entity "p<peer_id>" at the floor's arrival tile (or the nearest free tile),
## sends FLOOR_LOADED and CHARACTER_STATE to that peer, then broadcasts
## EXPLORE_STATE. Returns the entity id, or "" on failure.
func add_player(peer_id: int, sheet: CharacterSheet) -> String:
	if _floor == null or _transport == null:
		push_error("InstanceServer.add_player: call configure() first")
		return ""
	if sheet == null:
		push_error("InstanceServer.add_player: sheet is null")
		return ""
	if _peer_entities.has(peer_id):
		push_error("InstanceServer.add_player: peer %d already has a character" % peer_id)
		return ""
	var e := ServerEntity.new()
	e.id = "p%d" % peer_id
	e.kind = ServerEntity.KIND_PLAYER
	e.peer_id = peer_id
	e.sheet = CharacterSheet.from_dict(sheet.to_dict())
	e.display_name = e.sheet.name
	e.position = _free_tile_near(_floor.arrival)
	_entities[e.id] = e
	_peer_entities[peer_id] = e.id
	var cleared: Array = _cleared_zones.keys()
	_transport.send_result(peer_id, Messages.make_result(Messages.FLOOR_LOADED, {
		"floor": _floor.to_dict(),
		"entity_id": e.id,
		"cleared_zones": cleared,
	}))
	_send_character_state(e)
	_broadcast_explore_state()
	_check_zone_entry(e)
	return e.id


# --- read-only accessors (tests, tools; clients use the Transport) ------------

func get_floor() -> FloorData:
	return _floor


func get_entity(entity_id: String) -> ServerEntity:
	var e: ServerEntity = _entities.get(entity_id, null)
	return e


## Entity ids in insertion order (monsters first, then players as added).
func entity_ids() -> Array[String]:
	var out: Array[String] = []
	for key: Variant in _entities.keys():
		out.append(str(key))
	return out


func entity_id_for_peer(peer_id: int) -> String:
	return str(_peer_entities.get(peer_id, ""))


## The active Encounter the entity fights in, or null while it explores.
func get_encounter_for(entity_id: String) -> Encounter:
	var e := get_entity(entity_id)
	if e == null or not _sessions.has(e.encounter_id):
		return null
	var session: EncounterSession = _sessions[e.encounter_id]
	return session.encounter


func active_encounter_count() -> int:
	return _sessions.size()


func is_zone_cleared(zone_id: String) -> bool:
	return _cleared_zones.has(zone_id)


func is_game_over() -> bool:
	return _game_over


func is_floor_cleared() -> bool:
	return _floor_cleared


# --- tick -----------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_accumulator += delta
	var ran := 0
	while _accumulator + _TICK_EPSILON >= TICK_SECONDS and ran < MAX_CATCH_UP_TICKS:
		_accumulator = maxf(0.0, _accumulator - TICK_SECONDS)
		run_tick()
		ran += 1
	if ran >= MAX_CATCH_UP_TICKS:
		_accumulator = 0.0


## Runs exactly one server tick (see the class comment for the phases).
func run_tick() -> void:
	if _transport == null or _floor == null:
		return
	tick += 1
	_pump_transport()
	_run_due_monster_turns()
	_advance_exploration()


func _pump_transport() -> void:
	_transport.pump()


# --- intents --------------------------------------------------------------------

func _on_intent_received(peer_id: int, intent: Dictionary) -> void:
	var problem := Messages.validate_intent(intent)
	if not problem.is_empty():
		_send_error(peer_id, problem)
		return
	if _floor == null:
		_send_error(peer_id, "the server has no floor loaded")
		return
	if not _peer_entities.has(peer_id):
		_send_error(peer_id, "peer %d has no character on this floor" % peer_id)
		return
	var entity := get_entity(str(_peer_entities[peer_id]))
	var actor := str(intent["actor"])
	if actor != entity.id:
		_send_error(peer_id, "you may only act as %s, not %s" % [entity.id, actor])
		return
	if _game_over:
		_send_error(peer_id, "the game is over")
		return
	if not entity.is_alive():
		_send_error(peer_id, "%s is dead" % entity.display_name)
		return
	if Messages.is_encounter_intent(intent):
		_handle_combat_intent(peer_id, entity, intent)
		return
	if entity.in_combat():
		_send_error(peer_id, "%s is in combat" % entity.display_name)
		return
	match str(intent["type"]):
		Messages.EXPLORE_MOVE:
			_handle_explore_move(peer_id, entity, Messages.to_position(intent["target"]))
		Messages.USE_STAIRS:
			_handle_use_stairs(peer_id, entity)
		Messages.SHORT_REST:
			_handle_short_rest(peer_id, entity, DictUtil.to_int(intent["hit_dice"], 0))


func _handle_combat_intent(peer_id: int, entity: ServerEntity, intent: Dictionary) -> void:
	if not entity.in_combat() or not _sessions.has(entity.encounter_id):
		_send_error(peer_id, "%s is not in combat" % entity.display_name)
		return
	var session: EncounterSession = _sessions[entity.encounter_id]
	var res := session.encounter.submit(intent)
	var ok: bool = res.get("ok", false)
	if not ok:
		_send_error(peer_id, str(res.get("error", "intent rejected")))
		return
	var events: Array = res.get("events", [])
	_broadcast_events(session, events)
	_after_encounter_change(session)


func _handle_explore_move(peer_id: int, entity: ServerEntity, target: Vector2i) -> void:
	if not entity.sheet.is_conscious():
		_send_error(peer_id, "%s cannot move" % entity.display_name)
		return
	var walk_map := _floor.walk_map
	if not walk_map.is_walkable(target):
		_send_error(peer_id, "tile %s is not walkable" % str(target))
		return
	if target == entity.position:
		entity.path.clear()
		return
	var occupied := _occupied(entity.id)
	var path := walk_map.path_to(entity.position, target, occupied)
	if path.is_empty():
		if occupied.has(target) and GridMath.is_adjacent(entity.position, target):
			entity.path.clear()  # already next to the creature standing there
			return
		_send_error(peer_id, "no path to %s" % str(target))
		return
	if entity.path.is_empty():
		entity.step_timer = EXPLORE_STEP_TICKS - 1  # first step this tick
	entity.path = path
	entity.target = target


func _handle_use_stairs(peer_id: int, entity: ServerEntity) -> void:
	if not _sessions.is_empty():
		_send_error(peer_id, "the stairs cannot be used while an encounter is in progress")
		return
	if entity.position != _floor.stairs:
		_send_error(peer_id, "%s is not standing on the stairs" % entity.display_name)
		return
	entity.path.clear()
	_floor_cleared = true
	_transport.broadcast_result(Messages.make_result(Messages.FLOOR_CLEARED, {"floor_id": _floor.id}))


func _handle_short_rest(peer_id: int, entity: ServerEntity, hit_dice: int) -> void:
	if entity.position != _floor.stairs:
		_send_error(peer_id, "a short rest is only possible on the stairs")
		return
	var healed := Rest.short_rest(entity.sheet, hit_dice, _rest_rng)
	_send_character_state(entity, {"healed": healed})


# --- exploration ------------------------------------------------------------------

func _advance_exploration() -> void:
	var stepped: Array[ServerEntity] = []
	for value: Variant in _entities.values():
		var e: ServerEntity = value
		if e.path.is_empty() or e.in_combat() or not e.is_alive():
			continue
		e.step_timer += 1
		if e.step_timer < EXPLORE_STEP_TICKS:
			continue
		e.step_timer = 0
		if _step_entity(e):
			stepped.append(e)
	if stepped.is_empty():
		return
	_broadcast_explore_state()
	for e in stepped:
		_check_zone_entry(e)


## Moves e one tile along its path, re-pathing if a creature blocks the next
## tile. Returns false (and stops) if no way forward exists.
func _step_entity(e: ServerEntity) -> bool:
	var walk_map := _floor.walk_map
	var occupied := _occupied(e.id)
	var next := e.path[0]
	if not walk_map.can_step(e.position, next, occupied):
		var repath := walk_map.path_to(e.position, e.target, occupied)
		if repath.is_empty():
			e.path.clear()
			return false
		e.path = repath
		next = e.path[0]
	e.path.remove_at(0)
	e.position = next
	return true


## Tiles holding a living entity (Vector2i -> entity id), excluding except_id.
func _occupied(except_id: String = "") -> Dictionary:
	var out := {}
	for value: Variant in _entities.values():
		var e: ServerEntity = value
		if e.id != except_id and e.is_alive():
			out[e.position] = e.id
	return out


## p if it is free and walkable, else the nearest free walkable tile (BFS).
func _free_tile_near(p: Vector2i) -> Vector2i:
	var occupied := _occupied()
	if _floor.walk_map.is_walkable(p) and not occupied.has(p):
		return p
	var costs := _floor.walk_map.reachable(p, _floor.walk_map.width + _floor.walk_map.height, {})
	for key: Variant in costs.keys():
		var cell: Vector2i = key
		if not occupied.has(cell) and _floor.walk_map.is_walkable(cell):
			return cell
	push_error("InstanceServer: no free tile near %s" % str(p))
	return p


# --- encounters -------------------------------------------------------------------

## Called after e entered a tile while exploring: joins an active encounter
## whose region holds the tile, or (players only) triggers an uncleared zone.
func _check_zone_entry(e: ServerEntity) -> void:
	if _game_over or e.in_combat() or not e.is_alive():
		return
	for value: Variant in _sessions.values():
		var session: EncounterSession = value
		if session.region().has_point(e.position):
			_join_session(session, e)
			return
	if not e.is_player():
		return
	var zone := _floor.zone_at(e.position)
	if zone == null or _cleared_zones.has(zone.id):
		return
	_start_session(zone)


func _start_session(zone: EncounterZoneData) -> void:
	var zone_index := _floor.encounter_zones.find(zone)
	var attempt: int = _zone_attempts.get(zone.id, 0)
	_zone_attempts[zone.id] = attempt + 1
	var rng := _root_rng.fork(zone_index + attempt * ZONE_ATTEMPT_STRIDE)
	var session_id := zone.id if attempt == 0 else "%s#%d" % [zone.id, attempt + 1]
	var enc := Encounter.new(session_id, rng, _floor.walk_map, zone.rect)
	var session := EncounterSession.new(session_id, zone, enc)
	var joined: Array[ServerEntity] = []
	for value: Variant in _entities.values():
		var e: ServerEntity = value
		if e.in_combat() or not e.is_alive() or not zone.rect.has_point(e.position):
			continue
		var c := e.make_combatant()
		if enc.add_combatant(c):
			e.combatant = c
			joined.append(e)
		else:
			push_error("InstanceServer: %s could not join encounter %s" % [e.id, session_id])
	if not enc.start():
		# Nobody to fight (e.g. the zone's monsters are gone): nothing happens.
		for e in joined:
			e.combatant = null
		var monsters_left := false
		for e in joined:
			if e.is_monster():
				monsters_left = true
		if not monsters_left:
			_cleared_zones[zone.id] = true
		return
	for e in joined:
		_enter_combat(session, e)
	_sessions[session_id] = session
	_broadcast_events(session, enc.events_since(0))
	_after_encounter_change(session)


## Mid-fight join: the core inserts the newcomer into the initiative order.
func _join_session(session: EncounterSession, e: ServerEntity) -> void:
	var enc := session.encounter
	var first := enc.events.size()
	var c := e.make_combatant()
	if not enc.add_combatant(c):
		return
	e.combatant = c
	_enter_combat(session, e)
	_broadcast_events(session, enc.events_since(first))
	_after_encounter_change(session)


func _enter_combat(session: EncounterSession, e: ServerEntity) -> void:
	e.encounter_id = session.id
	e.path.clear()
	e.step_timer = 0
	if e.is_player():
		e.zone_id = session.zone.id
	if not session.entity_ids.has(e.id):
		session.entity_ids.append(e.id)


## Syncs entity positions from the encounter, finishes it if it ended, and
## schedules the next monster turn when a monster is the current actor.
func _after_encounter_change(session: EncounterSession) -> void:
	for entity_id in session.entity_ids:
		var e := get_entity(entity_id)
		if e != null and e.combatant != null:
			e.position = e.combatant.position
	var enc := session.encounter
	if enc.state == Encounter.State.ENDED:
		_finish_session(session)
		return
	var actor := enc.current_actor()
	if actor != null and actor.is_monster():
		if session.monster_due_tick < 0:
			session.monster_due_tick = tick + maxi(1, monster_turn_delay_ticks)
	else:
		session.monster_due_tick = -1


func _run_due_monster_turns() -> void:
	for value: Variant in _sessions.values():
		var session: EncounterSession = value
		if not _sessions.has(session.id):
			continue  # finished earlier this tick
		if session.monster_due_tick < 0 or tick < session.monster_due_tick:
			continue
		session.monster_due_tick = -1
		_run_monster_turn(session)


## Resolves the current monster's whole turn (MonsterBrain plan, stopping at
## the first rejected intent) and broadcasts its events as one result.
func _run_monster_turn(session: EncounterSession) -> void:
	var enc := session.encounter
	var actor := enc.current_actor()
	if actor == null or not actor.is_monster():
		_after_encounter_change(session)
		return
	var events: Array = []
	for intent in MonsterBrain.decide(enc, actor.id):
		var res := enc.submit(intent)
		var ok: bool = res.get("ok", false)
		if not ok:
			break
		var produced: Array = res.get("events", [])
		events.append_array(produced)
	if enc.state == Encounter.State.ACTIVE and enc.current_actor() == actor:
		# Safety net: the plan always ends with end_turn, but never stall.
		var res := enc.submit(Messages.make_intent(Messages.END_TURN, {"actor": actor.id}))
		var produced: Array = res.get("events", [])
		events.append_array(produced)
	_broadcast_events(session, events)
	_after_encounter_change(session)


func _finish_session(session: EncounterSession) -> void:
	_sessions.erase(session.id)
	var players_won := session.encounter.winning_team == Combatant.TEAM_PLAYERS
	if players_won:
		_cleared_zones[session.zone.id] = true
	for entity_id in session.entity_ids:
		var e := get_entity(entity_id)
		if e == null:
			continue
		e.encounter_id = ""
		e.combatant = null
		e.path.clear()
		e.step_timer = 0
		if e.is_monster():
			if not e.is_alive():
				_entities.erase(entity_id)
			continue
		e.zone_id = ""
		if e.is_alive() and e.sheet.current_hp == 0:
			if players_won:
				e.sheet.heal(1)  # M1: the downed are patched up to 1 hp
			else:
				_kill(e.sheet)  # M1: the monsters finish off the fallen
		_send_character_state(e)
	_broadcast_explore_state()
	_check_game_over()


func _kill(sheet: CharacterSheet) -> void:
	sheet.kill()


func _check_game_over() -> void:
	if _game_over:
		return
	var any_player := false
	for value: Variant in _entities.values():
		var e: ServerEntity = value
		if not e.is_player():
			continue
		any_player = true
		if e.is_alive():
			return
	if not any_player:
		return
	_game_over = true
	for value: Variant in _entities.values():
		var e: ServerEntity = value
		e.path.clear()
	_transport.broadcast_result(Messages.make_result(Messages.GAME_OVER, {}))


func _spawn_monsters() -> void:
	for zone in _floor.encounter_zones:
		for i in range(mini(zone.monster_ids.size(), zone.spawn_points.size())):
			var monster_id := zone.monster_ids[i]
			if not _monster_defs.has(monster_id):
				push_error("InstanceServer: unknown monster '%s' in zone %s" % [monster_id, zone.id])
				continue
			var def: MonsterDefinition = _monster_defs[monster_id]
			var proto := Combatant.from_monster("", def, Combatant.TEAM_MONSTERS, null, false)
			var e := ServerEntity.new()
			e.id = "%s_%s_%d" % [zone.id, monster_id, i]
			e.kind = ServerEntity.KIND_MONSTER
			e.sheet = proto.sheet
			e.attacks = proto.attacks
			e.display_name = def.display_name
			e.monster_id = def.id
			e.zone_id = zone.id
			e.position = zone.spawn_points[i]
			_entities[e.id] = e


# --- results ------------------------------------------------------------------------

func _broadcast_events(session: EncounterSession, events: Array) -> void:
	if events.is_empty():
		return
	_transport.broadcast_result(Messages.make_result(Messages.ENCOUNTER_EVENTS, {
		"events": events,
		"encounter_id": session.id,
		"zone_id": session.zone.id,
	}))


func _broadcast_explore_state() -> void:
	var list: Array = []
	for value: Variant in _entities.values():
		var e: ServerEntity = value
		list.append(e.to_state())
	_transport.broadcast_result(Messages.make_result(Messages.EXPLORE_STATE, {"entities": list, "tick": tick}))


func _send_character_state(e: ServerEntity, extra: Dictionary = {}) -> void:
	var fields := {"sheet": e.sheet.to_dict(), "entity_id": e.id}
	fields.merge(extra)
	_transport.send_result(e.peer_id, Messages.make_result(Messages.CHARACTER_STATE, fields))


func _send_error(peer_id: int, message: String) -> void:
	_transport.send_result(peer_id, Messages.make_error(message))

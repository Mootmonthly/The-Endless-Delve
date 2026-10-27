class_name InstanceServer
extends Node
## Authoritative simulation of a dungeon instance: one floor at a time, either
## a single floor (configure) or a five-floor set walked in order
## (configure_set). Owns every piece of game state; clients only send intents
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
##     (stable or still dying) is set to 1 hp (M1 simplification). XP = sum of
##     the stat-block XP of the monsters that died in the encounter, split
##     evenly (integer division, remainder to nobody) among the encounter's
##     players alive at its end; each gets CHARACTER_STATE with extras
##     xp_gained / levels_pending (CharacterSheet.gain_xp only banks XP). The
##     dead monsters' loot tables are rolled and the drops go to the first
##     living player (LOOT_GAINED source "monster", before its CHARACTER_STATE);
##   - otherwise (monsters won / nobody left standing): the zone stays
##     uncleared and the monsters finish off the downed players, who die
##     (M1 simplification: no rescue outside an encounter). The core only ends
##     a fight once no player is conscious or still dying (death saves before
##     wipe), so the fallen here are all stable or dead;
##   - dead monsters are removed, survivors return to exploration, every
##     participating player gets a CHARACTER_STATE and EXPLORE_STATE is
##     broadcast; if no living player remains, GAME_OVER is broadcast once and
##     every further intent is rejected.
##
## Exploration intents (explore_move, use_stairs, short_rest, equip, unequip,
## open_chest, drop_item, level_up, dismiss_companion) are refused
## while the sender's character is in combat; combat intents are refused
## while it explores. use_item and cast are dual (Messages.is_dual_intent):
## the Encounter resolves them in a fight, the server out of combat;
## reaction_policy is accepted any time. use_stairs needs the stairs tile and no active encounter
## on the floor; short_rest needs the stairs tile (recover_slots: Arcane /
## Natural Recovery as it ends; Song of Rest from the living party's bards).
## Errors go only to the sending peer as ERROR results.
##
## Stairs: FLOOR_CLEARED {floor_id} is broadcast. In a set with a next floor,
## the whole instance descends: monsters of the old floor are dropped, the
## next floor's monsters spawn, cleared zones reset, every player keeps its
## sheet (HP, XP, hit dice) and is placed at the new arrival, and each player
## gets FLOOR_LOADED (+ extras), CHARACTER_STATE, then EXPLORE_STATE is
## broadcast. On the set's LAST floor every living player takes a long rest
## (safe zone placeholder; CHARACTER_STATE extra long_rest: true) and
## SET_CLEARED {set_id} is broadcast once; the instance is then terminal and
## every further intent except level_up is rejected. A single floor
## (configure) only broadcasts FLOOR_CLEARED. Every living player gets
## FLOOR_CLEAR_XP on the stairs (CHARACTER_STATE extras xp_gained,
## floor_clear_xp, levels_pending, on the state the floor change sends).
##
## Level-up: never automatic. A player out of combat with pending levels gets
## LEVEL_UP_AVAILABLE {entity_id, choices: LevelUp.choices} (one level at a
## time; a fighting player gets it when its encounter ends); the level_up
## intent applies LevelUp.apply and answers CHARACTER_STATE {leveled_to,
## levels_pending} (+ the next offer) or ERROR.
##
## Out-of-combat casting: a cast intent while exploring runs OutOfCombat.cast
## on the player's sheet (content cache, CAST_STREAM rng, the player as the
## only target in M2, options slot_level / form): Find Familiar / Animate Dead
## companions, heals, temporary HP, restorations, revives and Mage Armor.
## Spells with casting times longer than an action (1 minute, 10 minutes,
## 1 hour) and rituals take no real time in M2: the cast resolves at once (a
## ritual still spends a slot, as OutOfCombat.cast does). Success:
## OUT_OF_COMBAT_EVENTS {entity_id, spell, slot_level, result, events}, then
## CHARACTER_STATE (extra spell_cast); a spell that only works in a fight, an
## unprepared spell, no slot, an unconscious or dead caster or another target
## -> ERROR. Companions on the sheet get a server id ("c<n>") on every
## CHARACTER_STATE; dismiss_companion {companion_id} removes one (out of
## combat). The next encounter spawns the sheet's companions beside their
## owner (Encounter._spawn_companions).
##
## Reaction policy: stored per player, handed to its encounter at once
## (Encounter.set_reaction_policy) and to every later combatant it becomes
## (ServerEntity.make_combatant), on this floor and the next ones.
##
## Items and chests: use_item is resolved by the Encounter while the actor
## fights, else here (no action cost). Chest state lasts one floor visit;
## hidden chests are withheld from FLOOR_LOADED until a player comes within
## CHEST_REVEAL_RANGE (CHEST_REVEALED) or opens them. A locked chest
## (ChestData.locked, or Arcane Lock) opens only after Knock.
##
## Floor objects (Round D, floor file v2; state lasts one floor visit):
##   - landings: each player arrives on one (add_player: the floor's seeded
##     base landing, then round robin; a party descending together lands on
##     the new floor's base landing); v1 floors have one, the arrival tile.
##   - doors: a closed or locked door is a wall of the exploration map
##     (explore_map(): movement and line of sight) and of every new
##     encounter's map copy; open_door / close_door (adjacent, out of combat),
##     unlock_door {method: key | tools | spell}; DOOR_CHANGED is broadcast
##     (a key is used up: "consumed": key item id). Keys belong to one floor:
##     any key-kind item a player still carries is gone when the instance
##     descends (CHARACTER_STATE extra "keys_lost": [item ids]).
##   - props: intact blocking props are obstacles (exploration: occupied
##     tiles; encounters: walls of the map copy). interact {prop_id}
##     (adjacent, out of combat) breaks one: PROP_DESTROYED, its guaranteed
##     drops (a door's key) then its loot table roll to the breaker
##     (LOOT_GAINED source "prop", drops listed first). FLOOR_LOADED shows each
##     door's key_item (the colour it wants) but never a prop's drops or table. Props cannot be attacked in a
##     fight (the core has no object targets; see the D2 report).
##   - respawns (schema 2 floors): a cleared zone with `respawns` comes back
##     after the floor's pack_seconds (boss zones: boss_seconds), never while
##     a living player stands in its rect or a fight runs there; its new
##     monsters (ids suffixed "_r<n>") re-arm the zone: ZONE_RESPAWNED, then
##     EXPLORE_STATE.
##   - exploration effects (round C): out-of-combat casts forward the core's
##     events (exploration_effect, no_effect, lingering_added, ...) in
##     OUT_OF_COMBAT_EVENTS; this server resolves exploration_effect: unlock /
##     lock / open doors and chests (target_kind / target_id, checked before
##     the cast so a bad aim spends nothing), reveal (REVEAL to the caster;
##     hidden chests also CHEST_REVEALED), light (the caster's light level ->
##     bright, CHARACTER_STATE extra light_level), teleport (landmark arrival
##     = the player's landing, or the stairs) and recall (the landing). The
##     same hooks cast inside a fight resolve after its events. A fight starts
##     at the floor's light level (floor_light(); Encounter.set_light).

const TICKS_PER_SECOND := 20
const TICK_SECONDS := 1.0 / TICKS_PER_SECOND
## Exploration speed: one tile every 3 ticks (~6.7 tiles/s).
const EXPLORE_STEP_TICKS := 3
## At most this many ticks are run per _physics_process call (backlog is dropped).
const MAX_CATCH_UP_TICKS := 5
## Rng.fork stream ids: zone index + attempt * ZONE_ATTEMPT_STRIDE for
## encounters (forked from the floor's stream); REST_STREAM for short-rest
## hit dice; FLOOR_STREAM + floor index for floors after the first (the first
## floor uses the root stream, as a single floor does).
const ZONE_ATTEMPT_STRIDE := 1024
const REST_STREAM := 1 << 20
const FLOOR_STREAM := 1 << 21
## Rng.fork stream ids for out-of-combat item use (root), level-up hit point
## rolls (root) and loot (chests and monster drops; forked from the floor's
## stream, so each floor's loot is independent of earlier floors).
const ITEM_STREAM := 1 << 22
const LEVEL_STREAM := 1 << 23
const LOOT_STREAM := 1 << 24
## Rng.fork stream id (root) for out-of-combat spells (heal and temp HP dice).
const CAST_STREAM := 1 << 25
## Rng.fork stream ids: the landing pick (forked from the floor's stream) and
## thieves' tools checks (root).
const LANDING_STREAM := 1 << 26
const TOOLS_STREAM := 1 << 27
const THIEVES_TOOLS := "thieves_tools"
## XP every living player gets when the stairs are taken (not split).
const FLOOR_CLEAR_XP := 100
## A hidden chest is revealed once a player stands within this many tiles.
const CHEST_REVEAL_RANGE := 1
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
var _floor_rng: Rng = null  # encounters on the current floor fork from this
var _rest_rng: Rng = null
var _item_rng: Rng = null
var _level_rng: Rng = null
var _loot_rng: Rng = null  # per floor: forked from _floor_rng
var _cast_rng: Rng = null
var _tools_rng: Rng = null
var _monster_defs: Dictionary = {}  # id -> MonsterDefinition
var _entities: Dictionary = {}  # id -> ServerEntity, insertion order
var _peer_entities: Dictionary = {}  # peer id -> entity id
var _sessions: Dictionary = {}  # session id -> EncounterSession (active only)
var _cleared_zones: Dictionary = {}  # zone id -> true
var _zone_attempts: Dictionary = {}  # zone id -> encounters created
# Chest state of the current floor visit (reset on every floor load).
var _opened_chests: Dictionary = {}  # chest id -> true
var _revealed_chests: Dictionary = {}  # chest id -> true (hidden chests only)
# Floor objects of the current floor visit (reset on every floor load).
var _door_states: Dictionary = {}  # door id -> state
var _door_dcs: Dictionary = {}  # door id -> dc (Arcane Lock raises it)
var _destroyed_props: Dictionary = {}  # prop id -> true
var _unlocked_chests: Dictionary = {}  # locked chest id -> true (Knock)
var _arcane_locked_chests: Dictionary = {}  # chest id -> true
var _cleared_at: Dictionary = {}  # zone id -> tick it was cleared (respawn timer)
var _zone_respawns: Dictionary = {}  # zone id -> respawns so far
var _landing_base: int = 0
var _landing_counter: int = 0
var _explore_map: WalkMap = null
var _prop_block: Dictionary = {}  # Vector2i -> prop id (intact blocking props)
var _teleported: Array[ServerEntity] = []  # moved by exploration effects this intent
var _game_over: bool = false
var _floor_cleared: bool = false
var _accumulator: float = 0.0
# Five-floor set (configure_set); empty / 0 for a single floor.
var _set_id: String = ""
var _set_name: String = ""
var _set_floor_ids: Array[String] = []
var _set_floor_overrides: Dictionary = {}  # floor id -> FloorData (tests, tools)
var _floor_index: int = 0
var _set_cleared: bool = false


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
	_opened_chests.clear()
	_revealed_chests.clear()
	_game_over = false
	_floor_cleared = false
	_accumulator = 0.0
	_set_id = ""
	_set_name = ""
	_set_floor_ids.clear()
	_set_floor_overrides = {}
	_floor_index = 0
	_set_cleared = false
	_transport = transport
	_floor = floor_data
	_seed = instance_seed
	_root_rng = Rng.new(instance_seed)
	_floor_rng = _root_rng
	_rest_rng = _root_rng.fork(REST_STREAM)
	_item_rng = _root_rng.fork(ITEM_STREAM)
	_level_rng = _root_rng.fork(LEVEL_STREAM)
	_cast_rng = _root_rng.fork(CAST_STREAM)
	_tools_rng = _root_rng.fork(TOOLS_STREAM)
	_loot_rng = _floor_rng.fork(LOOT_STREAM)
	if _monster_defs.is_empty():
		_monster_defs = ContentLoader.load_monsters()
	if transport != null:
		transport.intent_received.connect(_on_intent_received)
	if floor_data == null:
		push_error("InstanceServer.configure: floor is null")
		return
	_reset_floor_runtime()
	_spawn_monsters()


## Like configure(), for a five-floor set manifest (see FloorFile.load_set):
## loads the set's first floor and remembers the rest for the stairs. Floors
## are read from FloorFile.floor_path(id) unless `floors` (floor id ->
## FloorData) supplies them. Returns false (push_error) if the manifest or the
## first floor is unusable.
func configure_set(transport: Transport, set_manifest: Dictionary, instance_seed: int, floors: Dictionary = {}) -> bool:
	var problems := FloorFile.set_problems(set_manifest)
	if not problems.is_empty():
		for p in problems:
			push_error("InstanceServer.configure_set: %s" % p)
		return false
	var ids := FloorFile.set_floor_ids(set_manifest)
	var first := _load_set_floor(ids[0], floors)
	if first == null:
		return false
	configure(transport, first, instance_seed)
	_set_id = str(set_manifest["id"])
	_set_name = str(set_manifest.get("display_name", _set_id))
	_set_floor_ids = ids
	_set_floor_overrides = floors
	return true


## Adds a player character (the server keeps its own copy of the sheet) as
## entity "p<peer_id>" on a landing (_next_landing; v1 floors: the arrival
## tile) or the nearest free tile,
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
	var landing := _next_landing()
	e.landing_id = landing.id
	e.light_level = floor_light()
	e.position = _free_tile_near(landing.position)
	_entities[e.id] = e
	_peer_entities[peer_id] = e.id
	_send_floor_loaded(e)
	_send_character_state(e)
	_broadcast_explore_state()
	_reveal_chests_near(e)
	_check_zone_entry(e)
	_offer_level_up(e)
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


## Id of the set being played ("" for a single floor).
func get_set_id() -> String:
	return _set_id


## 0-based index of the current floor in the set (0 for a single floor).
func get_floor_index() -> int:
	return _floor_index


## Floors in the set (1 for a single floor).
func get_floor_count() -> int:
	return maxi(1, _set_floor_ids.size())


func is_set_cleared() -> bool:
	return _set_cleared


func is_chest_opened(chest_id: String) -> bool:
	return _opened_chests.has(chest_id)


## True once a chest may be shown to clients: visible from the start, or a
## hidden chest a player came within CHEST_REVEAL_RANGE of, or any opened chest.
func is_chest_revealed(chest_id: String) -> bool:
	var chest := _floor.get_chest(chest_id) if _floor != null else null
	if chest == null:
		return false
	return not chest.hidden or _revealed_chests.has(chest_id) or _opened_chests.has(chest_id)


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
	_check_respawns()


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
	var type := str(intent["type"])
	# A cleared set is terminal, except that banked levels may still be taken.
	if _set_cleared and type != Messages.LEVEL_UP:
		_send_error(peer_id, "the set is cleared")
		return
	if not entity.is_alive():
		_send_error(peer_id, "%s is dead" % entity.display_name)
		return
	if type == Messages.REACTION_POLICY:
		_handle_reaction_policy(entity, intent["policy"])
		return
	if Messages.is_encounter_intent(intent) or (Messages.is_dual_intent(intent) and entity.in_combat()):
		_handle_combat_intent(peer_id, entity, intent)
		return
	if entity.in_combat():
		_send_error(peer_id, "%s is in combat" % entity.display_name)
		return
	match type:
		Messages.EXPLORE_MOVE:
			_handle_explore_move(peer_id, entity, Messages.to_position(intent["target"]))
		Messages.USE_STAIRS:
			_handle_use_stairs(peer_id, entity)
		Messages.SHORT_REST:
			_handle_short_rest(peer_id, entity, DictUtil.to_int(intent["hit_dice"], 0), intent.get("recover_slots", false))
		Messages.EQUIP:
			_handle_equip(peer_id, entity, str(intent["item"]), str(intent["slot"]))
		Messages.UNEQUIP:
			_handle_unequip(peer_id, entity, str(intent["slot"]))
		Messages.USE_ITEM:
			_handle_use_item(peer_id, entity, intent)
		Messages.CAST:
			_handle_cast_out_of_combat(peer_id, entity, intent)
		Messages.DISMISS_COMPANION:
			_handle_dismiss_companion(peer_id, entity, str(intent["companion_id"]))
		Messages.DROP_ITEM:
			_handle_drop_item(peer_id, entity, str(intent["item"]), DictUtil.to_int(intent["qty"], 0))
		Messages.OPEN_CHEST:
			_handle_open_chest(peer_id, entity, str(intent["chest_id"]))
		Messages.OPEN_DOOR:
			_handle_open_door(peer_id, entity, str(intent["door_id"]))
		Messages.CLOSE_DOOR:
			_handle_close_door(peer_id, entity, str(intent["door_id"]))
		Messages.UNLOCK_DOOR:
			_handle_unlock_door(peer_id, entity, intent)
		Messages.INTERACT:
			_handle_interact(peer_id, entity, str(intent["prop_id"]))
		Messages.LEVEL_UP:
			_handle_level_up(peer_id, entity, intent["choices"])


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
	_teleported.clear()
	_resolve_fight_exploration(events)
	_after_encounter_change(session)


func _handle_explore_move(peer_id: int, entity: ServerEntity, target: Vector2i) -> void:
	if not entity.sheet.is_conscious():
		_send_error(peer_id, "%s cannot move" % entity.display_name)
		return
	var walk_map := explore_map()
	if not walk_map.is_walkable(target):
		var door := _floor.door_at(target)
		_send_error(peer_id, "door '%s' is %s" % [door.id, door_state(door.id)] if door != null else "tile %s is not walkable" % str(target))
		return
	if target == entity.position:
		entity.path.clear()
		return
	var occupied := _blocked(entity.id)
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
	var next_floor: FloorData = null
	if _has_next_floor():
		next_floor = _load_set_floor(_set_floor_ids[_floor_index + 1], _set_floor_overrides)
		if next_floor == null:
			_send_error(peer_id, "the next floor could not be loaded")
			return
	_floor_cleared = true
	_transport.broadcast_result(Messages.make_result(Messages.FLOOR_CLEARED, {"floor_id": _floor.id}))
	# Floor-clear bonus: every living player, not split. It rides on the
	# CHARACTER_STATE the floor change sends anyway (one per player).
	var players := _players()
	var extras := {}  # entity id -> CHARACTER_STATE extras
	for e in players:
		if e.is_alive():
			e.sheet.gain_xp(FLOOR_CLEAR_XP)
			extras[e.id] = {
				"xp_gained": FLOOR_CLEAR_XP,
				"floor_clear_xp": FLOOR_CLEAR_XP,
				"levels_pending": e.sheet.pending_levels(),
			}
	if next_floor != null:
		_enter_floor(_floor_index + 1, next_floor, extras)
	elif not _set_id.is_empty():
		_clear_set(extras)
	else:
		for e in players:
			if extras.has(e.id):
				_send_character_state(e, extras[e.id])
	for e in players:
		_offer_level_up(e)


func _players() -> Array[ServerEntity]:
	var out: Array[ServerEntity] = []
	for value: Variant in _entities.values():
		var e: ServerEntity = value
		if e.is_player():
			out.append(e)
	return out


func _has_next_floor() -> bool:
	return not _set_id.is_empty() and _floor_index + 1 < _set_floor_ids.size()


func _load_set_floor(floor_id: String, overrides: Dictionary) -> FloorData:
	if overrides.has(floor_id):
		var given: FloorData = overrides[floor_id]
		return given
	var path := FloorFile.floor_path(floor_id)
	var loaded := FloorFile.load(path)
	if loaded == null:
		push_error("InstanceServer: could not load floor '%s' (%s)" % [floor_id, path])
	return loaded


## Moves the whole instance to the set's floor `index`: old monsters go, the
## new floor's monsters spawn, players keep their sheets and stand on the
## new floor's base landing.
## `extras` (entity id -> Dictionary) are merged into each player's CHARACTER_STATE.
func _enter_floor(index: int, floor_data: FloorData, extras: Dictionary = {}) -> void:
	var players := _players()
	_entities.clear()
	_sessions.clear()
	_cleared_zones.clear()
	_zone_attempts.clear()
	_opened_chests.clear()
	_revealed_chests.clear()
	_floor_cleared = false
	_floor_index = index
	_floor = floor_data
	_floor_rng = _root_rng.fork(FLOOR_STREAM + index)
	_loot_rng = _floor_rng.fork(LOOT_STREAM)
	_reset_floor_runtime()
	_spawn_monsters()
	# The party descended together: everyone lands on the floor's base landing.
	var landing := _next_landing()
	for e in players:
		e.path.clear()
		e.step_timer = 0
		e.encounter_id = ""
		e.combatant = null
		e.zone_id = ""
		e.landing_id = landing.id
		e.light_level = floor_light()
		e.position = _free_tile_near(landing.position) if e.is_alive() else landing.position
		_entities[e.id] = e
	for e in players:
		var lost := _drop_floor_keys(e)
		if not lost.is_empty():
			var fields: Dictionary = (extras.get(e.id, {}) as Dictionary).duplicate()
			fields["keys_lost"] = lost
			extras[e.id] = fields
	for e in players:
		_send_floor_loaded(e)
		_send_character_state(e, extras.get(e.id, {}))
	_broadcast_explore_state()
	for e in players:
		_reveal_chests_near(e)
	for e in players:
		_check_zone_entry(e)


## Removes every key-kind item from e (keys open locks on their own floor
## only); returns the removed item ids.
func _drop_floor_keys(e: ServerEntity) -> Array[String]:
	var lost: Array[String] = []
	var items: Dictionary = ContentLoader.cache().get("items", {})
	for entry in e.sheet.inventory.duplicate():
		var item_id := str(entry["item"])
		var def: ItemDefinition = items.get(item_id, null)
		if def != null and def.kind == ItemDefinition.KIND_KEY:
			lost.append(item_id)
	for item_id in lost:
		e.sheet.remove_item(item_id, e.sheet.count_item(item_id), ContentLoader.cache())
	return lost


## Last floor's stairs: long rest for every living player, then SET_CLEARED.
func _clear_set(extras: Dictionary = {}) -> void:
	for value: Variant in _entities.values():
		var e: ServerEntity = value
		e.path.clear()
		if e.is_player() and e.is_alive():
			Rest.long_rest(e.sheet)
			var fields: Dictionary = {"long_rest": true}
			fields.merge(extras.get(e.id, {}))
			_send_character_state(e, fields)
	_set_cleared = true
	_transport.broadcast_result(Messages.make_result(Messages.SET_CLEARED, {"set_id": _set_id}))


## Stores the player's reaction policy (any time, also off-turn) and hands it
## to its active encounter through Encounter.set_reaction_policy (logged there
## for replays); later encounters, on this floor or the next, get it as the
## combatant joins (ServerEntity.make_combatant). Answers CHARACTER_STATE with
## "reaction_policy".
func _handle_reaction_policy(entity: ServerEntity, policy: Dictionary) -> void:
	entity.reaction_policy = {}
	for key: Variant in policy.keys():
		entity.reaction_policy[str(key)] = str(policy[key])
	var enc := get_encounter_for(entity.id)
	if enc != null:
		enc.set_reaction_policy(entity.id, entity.reaction_policy.duplicate())
	_send_character_state(entity, {"reaction_policy": entity.reaction_policy.duplicate()})


## Short rest on the stairs: hit dice (with the party's Song of Rest die),
## short-rest resources and pact slots (Rest.short_rest), then, when asked,
## Arcane / Natural Recovery (Rest.recover_slots): `recover_slots` true lets
## the server pick (recovery_picks), an array names the slot levels. A refused
## recovery still rests: CHARACTER_STATE carries "recovery_error" instead of
## "slots_recovered".
func _handle_short_rest(peer_id: int, entity: ServerEntity, hit_dice: int, recover: Variant = false) -> void:
	if entity.position != _floor.stairs:
		_send_error(peer_id, "a short rest is only possible on the stairs")
		return
	var party: Array[CharacterSheet] = []
	for e in _players():
		if e.is_alive():
			party.append(e.sheet)
	var healed := Rest.short_rest(entity.sheet, hit_dice, _rest_rng, Rest.song_of_rest_die(party))
	var extra := {"healed": healed}
	var levels: Array[int] = []
	if typeof(recover) == TYPE_ARRAY:
		for v: Variant in (recover as Array):
			levels.append(DictUtil.to_int(v, 0))
	elif recover == true:
		levels = InstanceServer.recovery_picks(entity.sheet)
	if typeof(recover) == TYPE_ARRAY or recover == true:
		var err := Rest.recover_slots(entity.sheet, levels) if not levels.is_empty() else "no expended slots to recover"
		if err.is_empty():
			extra["slots_recovered"] = levels
		else:
			extra["recovery_error"] = err
	_send_character_state(entity, extra)


## Arcane / Natural Recovery picks: expended slots, highest level first, while
## the budget (Rest.slot_recovery_options) allows. [] when nothing applies.
static func recovery_picks(sheet: CharacterSheet) -> Array[int]:
	var out: Array[int] = []
	var opts := Rest.slot_recovery_options(sheet)
	if opts.is_empty():
		return out
	var budget := DictUtil.to_int(opts.get("budget", 0), 0)
	var top := mini(DictUtil.to_int(opts.get("max_slot_level", 5), 5), sheet.spell_slots_max.size())
	for lvl in range(top, 0, -1):
		var missing := sheet.spell_slots_max[lvl - 1] - sheet.slots_left(lvl)
		while missing > 0 and budget >= lvl:
			out.append(lvl)
			budget -= lvl
			missing -= 1
	return out


# --- items, chests, level-up (out of combat) ----------------------------------------

func _handle_equip(peer_id: int, entity: ServerEntity, item_id: String, slot: String) -> void:
	var err := entity.sheet.equip(item_id, slot, {})
	if not err.is_empty():
		_send_error(peer_id, err)
		return
	_send_character_state(entity, {"equipped": {"item": item_id, "slot": slot}})


func _handle_unequip(peer_id: int, entity: ServerEntity, slot: String) -> void:
	var held := entity.sheet.equipped_item(slot)
	var err := entity.sheet.unequip(slot, {})
	if not err.is_empty():
		_send_error(peer_id, err)
		return
	_send_character_state(entity, {"unequipped": {"item": held, "slot": slot}})


## Out-of-combat item use (the in-combat use_item goes to the Encounter):
## the same checks as the core (carried, usable, implemented, self only),
## no action economy. Rolls with the instance's item stream.
func _handle_use_item(peer_id: int, entity: ServerEntity, intent: Dictionary) -> void:
	var sheet := entity.sheet
	var item_id := str(intent["item"])
	var item := CharacterSheet.item_def(item_id, ContentLoader.cache())
	if item == null:
		_send_error(peer_id, "unknown item '%s'" % item_id)
		return
	if not sheet.has_item(item_id):
		_send_error(peer_id, "%s does not carry %s" % [entity.display_name, item.display_name])
		return
	if not item.is_usable():
		_send_error(peer_id, "%s cannot be used" % item.display_name)
		return
	if not item.has_implemented_use():
		_send_error(peer_id, "%s has no effect yet" % item.display_name)
		return
	var target := str(intent.get("target", entity.id))
	if target != entity.id:
		_send_error(peer_id, "items can only be used on yourself for now")
		return
	if not sheet.is_conscious():
		_send_error(peer_id, "%s is unconscious" % entity.display_name)
		return
	sheet.remove_item(item_id, 1, {})
	var extra := {"item_used": item_id}
	match item.use_effect:
		ItemDefinition.EFFECT_HEAL:
			var rolled := maxi(0, DiceExpr.parse(item.use_dice).roll(_item_rng).total)
			extra["healed"] = sheet.heal(rolled)
		ItemDefinition.EFFECT_TEMP_HP:
			var amount := maxi(0, DiceExpr.parse(item.use_dice).roll(_item_rng).total)
			sheet.grant_temp_hp(amount)
			extra["temp_hp"] = amount
		ItemDefinition.EFFECT_CURE:
			for condition in item.use_conditions:
				sheet.conditions.erase(condition)
	_send_character_state(entity, extra)


## Out-of-combat cast (see the class comment): OutOfCombat.cast with the
## player's own sheet as the target (options: slot_level, form, mode,
## target_kind / target_id, invocation, ritual, spend_slot), then
## OUT_OF_COMBAT_EVENTS (the core's events: cast, companion_summoned, heal,
## temp_hp, revived, restored, buff, exploration_effect, no_effect,
## lingering_added), the exploration hooks' own results, and CHARACTER_STATE
## to the caster; or ERROR (nothing changed). An exploration spell aimed at
## an object that is missing, out of range or in the wrong state is refused
## before the cast.
func _handle_cast_out_of_combat(peer_id: int, entity: ServerEntity, intent: Dictionary) -> void:
	var spell_id := str(intent["spell"])
	var content := ContentLoader.cache()
	var spells: Dictionary = content.get("spells", {})
	var spell: SpellDefinition = spells.get(spell_id, null)
	if spell == null:
		_send_error(peer_id, "unknown spell '%s'" % spell_id)
		return
	var ids: Array[String] = []
	if intent.has("targets"):
		ids = DictUtil.to_string_array(intent["targets"])
	elif intent.has("target"):
		ids.append(str(intent["target"]))
	for id in ids:
		if id != entity.id:
			_send_error(peer_id, "out of combat, %s can only target yourself for now" % spell.display_name)
			return
	if spell.effect_type == SpellDefinition.EFFECT_EXPLORATION:
		var problem := _exploration_problem(entity, spell, intent)
		if not problem.is_empty():
			_send_error(peer_id, problem)
			return
	var options := {"caster_id": entity.id, "target_ids": [entity.id]}
	if intent.has("slot_level"):
		options["slot_level"] = DictUtil.to_int(intent["slot_level"], 0)
	for key: String in ["form", "mode", "target_kind", "target_id", "invocation"]:
		if intent.has(key):
			options[key] = str(intent[key])
	for key: String in ["ritual", "spend_slot"]:
		if intent.has(key):
			options[key] = intent[key] == true
	var sheet := entity.sheet
	var targets: Array[CharacterSheet] = [sheet]
	var res := OutOfCombat.cast(sheet, spell_id, content, _cast_rng, targets, options)
	if res.get("ok", false) != true:
		_send_error(peer_id, str(res.get("error", "the spell fails")))
		return
	_stamp_companion_ids(entity)
	var slot := DictUtil.to_int(res.get("slot_level", 0), 0)
	var result: Dictionary = res.get("result", {})
	var events: Array = []
	for ev_v: Variant in (res.get("events", []) as Array):
		var ev: Dictionary = (ev_v as Dictionary).duplicate(true)
		if str(ev.get("kind", "")) == "cast":
			# "ritual" = the spell has the ritual tag (as before); "as_ritual" = cast as one (no slot).
			ev["as_ritual"] = ev.get("ritual", false) == true
			ev["ritual"] = spell.ritual
		events.append(ev)
	_transport.send_result(peer_id, Messages.make_result(Messages.OUT_OF_COMBAT_EVENTS, {
		"entity_id": entity.id, "spell": spell_id, "slot_level": slot, "result": result, "events": events,
	}))
	_teleported.clear()
	var light_before := entity.light_level
	for ev_v: Variant in events:
		var ev: Dictionary = ev_v
		if str(ev.get("kind", "")) == "exploration_effect":
			_resolve_exploration(entity, ev)
	var extra := {"spell_cast": spell_id}
	if entity.light_level != light_before:
		extra["light_level"] = entity.light_level
	_send_character_state(entity, extra)
	_after_teleports()


## Players moved by teleport / recall hooks: EXPLORE_STATE, then hidden
## chests near them and the zones they landed in.
func _after_teleports() -> void:
	if _teleported.is_empty():
		return
	var moved := _teleported.duplicate()
	_teleported.clear()
	_broadcast_explore_state()
	for e: ServerEntity in moved:
		_reveal_chests_near(e)
		_check_zone_entry(e)


## Removes a companion (by its server id) from the player's sheet.
func _handle_dismiss_companion(peer_id: int, entity: ServerEntity, companion_id: String) -> void:
	_stamp_companion_ids(entity)
	var list := entity.sheet.companions
	for i in range(list.size()):
		if str(list[i].get("id", "")) == companion_id:
			var gone: Dictionary = list[i]
			list.remove_at(i)
			_send_character_state(entity, {"companion_dismissed": {"id": companion_id, "monster": str(gone.get("monster", ""))}})
			return
	_send_error(peer_id, "%s has no companion '%s'" % [entity.display_name, companion_id])


## Gives every companion on a player's sheet without an "id" the next free
## "c<n>" (ids already on the sheet are kept and never reused).
func _stamp_companion_ids(e: ServerEntity) -> void:
	if e == null or e.sheet == null:
		return
	for entry in e.sheet.companions:
		var id := str(entry.get("id", ""))
		if id.begins_with("c") and id.substr(1).is_valid_int():
			e.companion_serial = maxi(e.companion_serial, id.substr(1).to_int())
	for entry in e.sheet.companions:
		if str(entry.get("id", "")).is_empty():
			e.companion_serial += 1
			entry["id"] = "c%d" % e.companion_serial


func _handle_drop_item(peer_id: int, entity: ServerEntity, item_id: String, qty: int) -> void:
	var carried := entity.sheet.count_item(item_id)
	if carried <= 0:
		_send_error(peer_id, "%s does not carry %s" % [entity.display_name, item_id])
		return
	if not entity.sheet.remove_item(item_id, qty, {}):
		_send_error(peer_id, "%s carries only %d %s" % [entity.display_name, carried, item_id])
		return
	_send_character_state(entity, {"dropped": {"item": item_id, "qty": qty}})


## Opens a chest the player stands on or next to: CHEST_OPENED is broadcast,
## the opener gets LOOT_GAINED (source "chest") and CHARACTER_STATE. A hidden
## chest nobody has revealed answers like an unknown id.
func _handle_open_chest(peer_id: int, entity: ServerEntity, chest_id: String) -> void:
	var chest := _floor.get_chest(chest_id)
	var near := chest != null and GridMath.distance_tiles(entity.position, chest.position) <= 1
	if chest == null or (not is_chest_revealed(chest_id) and not near):
		_send_error(peer_id, "there is no chest '%s' on this floor" % chest_id)
		return
	if _opened_chests.has(chest_id):
		_send_error(peer_id, "chest '%s' is already open" % chest_id)
		return
	if not near:
		_send_error(peer_id, "%s is not next to chest '%s'" % [entity.display_name, chest_id])
		return
	if not entity.sheet.is_conscious():
		_send_error(peer_id, "%s cannot open a chest now" % entity.display_name)
		return
	if is_chest_locked(chest_id):
		_send_error(peer_id, "chest '%s' is locked" % chest_id)
		return
	entity.path.clear()
	_open_chest_for(entity, chest)


## Opens a chest for e: CHEST_OPENED (broadcast), LOOT_GAINED, CHARACTER_STATE.
func _open_chest_for(entity: ServerEntity, chest: ChestData) -> void:
	_opened_chests[chest.id] = true
	_revealed_chests[chest.id] = true
	var items := _roll_loot(chest.table_id)
	_transport.broadcast_result(Messages.make_result(Messages.CHEST_OPENED, {
		"chest_id": chest.id, "entity_id": entity.id,
	}))
	_give_loot(entity, items, Messages.LOOT_SOURCE_CHEST, {"chest_id": chest.id})
	_send_character_state(entity)


## Applies one level (LevelUp.apply) with the player's choices. Success:
## CHARACTER_STATE with leveled_to (+ levels_pending) and, while levels remain,
## the next LEVEL_UP_AVAILABLE. Failure: ERROR, the sheet is unchanged.
func _handle_level_up(peer_id: int, entity: ServerEntity, choices: Dictionary) -> void:
	if entity.sheet.pending_levels() <= 0:
		_send_error(peer_id, "%s has no level-up pending" % entity.display_name)
		return
	var err := LevelUp.apply(entity.sheet, choices, {}, _level_rng)
	if not err.is_empty():
		_send_error(peer_id, "level_up: %s" % err)
		return
	_send_character_state(entity, {
		"leveled_to": entity.sheet.level,
		"levels_pending": entity.sheet.pending_levels(),
	})
	_offer_level_up(entity)


## Sends LEVEL_UP_AVAILABLE for the next level when e has banked enough XP and
## is out of combat (a fighting player gets it when its encounter ends). Each
## call re-sends the current offer; the client keeps only the latest.
func _offer_level_up(e: ServerEntity) -> void:
	if e == null or not e.is_player() or not e.is_alive() or e.in_combat() or _game_over:
		return
	if e.sheet.pending_levels() <= 0:
		return
	_transport.send_result(e.peer_id, Messages.make_result(Messages.LEVEL_UP_AVAILABLE, {
		"entity_id": e.id,
		"choices": LevelUp.choices(e.sheet, {}),
	}))


## Rolls a loot table with the floor's loot stream; [] for "" or an unknown id.
func _roll_loot(table_id: String) -> Array[Dictionary]:
	if table_id.is_empty():
		return []
	var tables: Dictionary = ContentLoader.cache().get("loot_tables", {})
	if not tables.has(table_id):
		push_warning("InstanceServer: unknown loot table '%s'" % table_id)
		return []
	var table: LootTable = tables[table_id]
	return table.roll(_loot_rng)


## Adds items to e's inventory and sends LOOT_GAINED to its peer (also when
## items is empty: an empty chest). The caller sends CHARACTER_STATE.
func _give_loot(e: ServerEntity, items: Array[Dictionary], source: String, extra: Dictionary = {}) -> void:
	for entry in items:
		e.sheet.add_item(str(entry["item"]), DictUtil.to_int(entry["qty"]))
	var fields := {"entity_id": e.id, "items": items, "source": source}
	fields.merge(extra)
	_transport.send_result(e.peer_id, Messages.make_result(Messages.LOOT_GAINED, fields))


## Reveals every hidden chest within CHEST_REVEAL_RANGE of a player
## (CHEST_REVEALED is broadcast once per chest).
func _reveal_chests_near(e: ServerEntity) -> void:
	if e == null or not e.is_player() or not e.is_alive() or _floor == null:
		return
	for chest in _floor.chests:
		if not chest.hidden or is_chest_revealed(chest.id):
			continue
		if GridMath.distance_tiles(e.position, chest.position) > CHEST_REVEAL_RANGE:
			continue
		_revealed_chests[chest.id] = true
		_transport.broadcast_result(Messages.make_result(Messages.CHEST_REVEALED, {
			"chest": _chest_state(chest),
		}))


## The wire form of a chest: {id, position, hidden, opened, locked?} (no loot table).
func _chest_state(chest: ChestData) -> Dictionary:
	var out := {
		"id": chest.id,
		"position": GridMath.vec_to_arr(chest.position),
		"hidden": chest.hidden,
		"opened": _opened_chests.has(chest.id),
	}
	if is_chest_locked(chest.id):
		out["locked"] = true
	return out


## Chests clients may know about (see is_chest_revealed), in floor order.
func _visible_chests() -> Array:
	var out: Array = []
	for chest in _floor.chests:
		if is_chest_revealed(chest.id):
			out.append(_chest_state(chest))
	return out


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
		_reveal_chests_near(e)
	for e in stepped:
		_check_zone_entry(e)


## Moves e one tile along its path, re-pathing if a creature blocks the next
## tile. Returns false (and stops) if no way forward exists.
func _step_entity(e: ServerEntity) -> bool:
	var walk_map := explore_map()
	var occupied := _blocked(e.id)
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


## p if it is free and walkable (doors and props composed in), else the
## nearest free walkable tile (BFS). except_id's own tile counts as free.
func _free_tile_near(p: Vector2i, except_id: String = "") -> Vector2i:
	var occupied := _blocked(except_id)
	var wm := explore_map()
	if wm.is_walkable(p) and not occupied.has(p):
		return p
	var costs := wm.reachable(p, wm.width + wm.height, {})
	for key: Variant in costs.keys():
		var cell: Vector2i = key
		if not occupied.has(cell) and wm.is_walkable(cell):
			return cell
	push_error("InstanceServer: no free tile near %s" % str(p))
	return p


# --- encounters -------------------------------------------------------------------

## Called after e entered a tile while exploring: joins an active encounter
## whose region holds the tile, or (players only) triggers an uncleared zone.
func _check_zone_entry(e: ServerEntity) -> void:
	if _game_over or _set_cleared or e.in_combat() or not e.is_alive():
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
	var rng := _floor_rng.fork(zone_index + attempt * ZONE_ATTEMPT_STRIDE)
	var session_id := zone.id if attempt == 0 else "%s#%d" % [zone.id, attempt + 1]
	var enc := Encounter.new(session_id, rng, _encounter_map(), zone.rect)
	if floor_light() != Encounter.LIGHT_BRIGHT:
		enc.set_light(floor_light())
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
			_mark_cleared(zone.id)
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
			_reveal_chests_near(e)
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
	var xp_share := 0
	var drops: Array[Dictionary] = []
	var looter: ServerEntity = null
	if players_won:
		_mark_cleared(session.zone.id)
		xp_share = _xp_share(session)
		drops = _roll_monster_drops(session)
		looter = _first_living_player(session)
	var players: Array[ServerEntity] = []
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
		players.append(e)
		if players_won and e.is_alive():
			e.sheet.gain_xp(xp_share)
			if e == looter and not drops.is_empty():
				_give_loot(e, drops, Messages.LOOT_SOURCE_MONSTER)
			_send_character_state(e, {"xp_gained": xp_share, "levels_pending": e.sheet.pending_levels()})
		else:
			_send_character_state(e)
	_broadcast_explore_state()
	_check_game_over()
	for e in players:
		_offer_level_up(e)


## Each surviving player's XP for a won encounter: the stat-block XP of the
## monsters that died in it, split evenly among the encounter's players alive
## at its end (integer division; the remainder goes to nobody).
func _xp_share(session: EncounterSession) -> int:
	var total := 0
	var survivors := 0
	for entity_id in session.entity_ids:
		var e := get_entity(entity_id)
		if e == null:
			continue
		if e.is_monster() and not e.is_alive() and _monster_defs.has(e.monster_id):
			var def: MonsterDefinition = _monster_defs[e.monster_id]
			total += def.xp
		elif e.is_player() and e.is_alive():
			survivors += 1
	if survivors == 0:
		return 0
	@warning_ignore("integer_division")
	return total / survivors


func _kill(sheet: CharacterSheet) -> void:
	sheet.kill()


## Rolls the loot table of every monster that died in the session (session
## order) with the floor's loot stream; the merged [{"item", "qty"}] list.
func _roll_monster_drops(session: EncounterSession) -> Array[Dictionary]:
	var merged: Array[Dictionary] = []
	for entity_id in session.entity_ids:
		var e := get_entity(entity_id)
		if e == null or not e.is_monster() or e.is_alive() or not _monster_defs.has(e.monster_id):
			continue
		var def: MonsterDefinition = _monster_defs[e.monster_id]
		for entry in _roll_loot(def.loot_table):
			LootTable.merge_into(merged, str(entry["item"]), DictUtil.to_int(entry["qty"]))
	return merged


## M2: all monster drops go to the first player of the session still alive.
func _first_living_player(session: EncounterSession) -> ServerEntity:
	for entity_id in session.entity_ids:
		var e := get_entity(entity_id)
		if e != null and e.is_player() and e.is_alive():
			return e
	return null


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
		_spawn_zone(zone, "")


## Spawns a zone's monsters at their spawn points; id "<zone>_<monster>_<i>"
## + suffix (respawns add "_r<n>").
func _spawn_zone(zone: EncounterZoneData, suffix: String) -> void:
	for i in range(mini(zone.monster_ids.size(), zone.spawn_points.size())):
		var monster_id := zone.monster_ids[i]
		if not _monster_defs.has(monster_id):
			push_error("InstanceServer: unknown monster '%s' in zone %s" % [monster_id, zone.id])
			continue
		var def: MonsterDefinition = _monster_defs[monster_id]
		var proto := Combatant.from_monster("", def, Combatant.TEAM_MONSTERS, null, false)
		var e := ServerEntity.new()
		e.id = "%s_%s_%d%s" % [zone.id, monster_id, i, suffix]
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


## FLOOR_LOADED for one player: the floor plus entity_id, cleared_zones and
## the set position (set_id / set_name "" and floor_count 1 for a single floor).
func _send_floor_loaded(e: ServerEntity) -> void:
	var cleared: Array = _cleared_zones.keys()
	var chests := _visible_chests()
	var floor_dict := _floor.to_dict()
	floor_dict["chests"] = chests  # never leak hidden chests or loot tables
	var doors: Array = []
	for d in _floor.doors:
		doors.append(_door_wire(d))
	var props: Array = []
	for p in _floor.props:
		props.append(_prop_wire(p))
	floor_dict["doors"] = doors  # current states, never key items
	floor_dict["props"] = props  # never loot tables or drops
	var landings: Array = []
	for l in _floor.get_landings():
		landings.append(l.to_dict())
	_transport.send_result(e.peer_id, Messages.make_result(Messages.FLOOR_LOADED, {
		"floor": floor_dict,
		"chests": chests,
		"doors": doors,
		"props": props,
		"landings": landings,
		"landing_id": e.landing_id,
		"light": floor_light(),
		"entity_id": e.id,
		"cleared_zones": cleared,
		"set_id": _set_id,
		"set_name": _set_name,
		"floor_index": _floor_index,
		"floor_count": get_floor_count(),
	}))


func _send_character_state(e: ServerEntity, extra: Dictionary = {}) -> void:
	_stamp_companion_ids(e)
	var fields := {"sheet": e.sheet.to_dict(), "entity_id": e.id}
	fields.merge(extra)
	_transport.send_result(e.peer_id, Messages.make_result(Messages.CHARACTER_STATE, fields))


func _send_error(peer_id: int, message: String) -> void:
	_transport.send_result(peer_id, Messages.make_error(message))


# --- floor objects: landings, doors, props, light (Round D) ---------------------------

## Forgets the floor visit's door / prop / chest-lock / respawn state and
## rebuilds the exploration map from the floor's authored states.
func _reset_floor_runtime() -> void:
	_door_states.clear()
	_door_dcs.clear()
	_destroyed_props.clear()
	_unlocked_chests.clear()
	_arcane_locked_chests.clear()
	_cleared_at.clear()
	_zone_respawns.clear()
	_landing_counter = 0
	_landing_base = 0
	_explore_map = null
	_prop_block = {}
	if _floor == null:
		return
	for d in _floor.doors:
		_door_states[d.id] = d.state
	var landings := _floor.get_landings()
	if landings.size() > 1:
		var rng := _floor_rng.fork(LANDING_STREAM)
		_landing_base = rng.next_int(0, landings.size() - 1)
	_rebuild_floor_maps()


## _explore_map = the floor's walk map with closed / locked doors as walls;
## _prop_block = intact blocking props (tile -> prop id).
func _rebuild_floor_maps() -> void:
	_explore_map = _floor.walk_map.copy()
	for d in _floor.doors:
		if door_state(d.id) != DoorData.STATE_OPEN and _explore_map.in_bounds(d.position):
			_explore_map.set_walkable(d.position, false)
	_prop_block = {}
	for p in _floor.props:
		if p.blocks and not _destroyed_props.has(p.id):
			_prop_block[p.position] = p.id


## The walk map exploration uses right now (doors composed in).
func explore_map() -> WalkMap:
	if _explore_map == null and _floor != null:
		_rebuild_floor_maps()
	return _explore_map


## The map copy a new encounter gets: closed doors and intact blocking props
## are walls (the core has no "solid but see-through" tile, so a blocking prop
## also blocks line of sight inside a fight).
func _encounter_map() -> WalkMap:
	var m := explore_map().copy()
	for key: Variant in _prop_block.keys():
		var p: Vector2i = key
		m.set_walkable(p, false)
	return m


## Living entities (except except_id) and intact blocking props, as an
## `occupied` set for exploration path finding.
func _blocked(except_id: String = "") -> Dictionary:
	var out := _occupied(except_id)
	for key: Variant in _prop_block.keys():
		out[key] = _prop_block[key]
	return out


## Current state of a door ("" for an unknown id).
func door_state(door_id: String) -> String:
	if _door_states.has(door_id):
		return str(_door_states[door_id])
	var d := _floor.get_door(door_id) if _floor != null else null
	return d.state if d != null else ""


func is_prop_destroyed(prop_id: String) -> bool:
	return _destroyed_props.has(prop_id)


## The landing a player arrived at on this floor ("" before add_player).
func landing_of(entity_id: String) -> String:
	var e := get_entity(entity_id)
	return e.landing_id if e != null else ""


## The floor's ambient light: theme_style "light" ("bright" | "dim" | "dark"),
## default bright. FloorData has no light field yet (see the D2 report).
func floor_light() -> String:
	if _floor == null:
		return Encounter.LIGHT_BRIGHT
	var l := str(_floor.theme_style.get("light", Encounter.LIGHT_BRIGHT))
	return l if Encounter.LIGHT_LEVELS.has(l) else Encounter.LIGHT_BRIGHT


## Landing for the next player added to this floor: the seeded base landing,
## then round robin (offline the instance seed picks it; online this becomes
## least-recently-used).
func _next_landing() -> LandingData:
	var landings := _floor.get_landings()
	var l := landings[(_landing_base + _landing_counter) % landings.size()]
	_landing_counter += 1
	return l


func _landing_position(e: ServerEntity) -> Vector2i:
	var l := _floor.get_landing(e.landing_id)
	return l.position if l != null else _floor.arrival


## The wire form of a door: {id, position, state, dc?, keyed?, key_item?}
## (players see which key a door wants; the prop that drops it stays hidden).
func _door_wire(d: DoorData) -> Dictionary:
	var out := {"id": d.id, "position": GridMath.vec_to_arr(d.position), "state": door_state(d.id)}
	var dc := _door_dc(d)
	if dc > 0:
		out["dc"] = dc
	if not d.key_item.is_empty():
		out["keyed"] = true
		out["key_item"] = d.key_item
	return out


## The wire form of a prop: {id, kind, position, hp, blocks, destroyed} (never
## loot_table or drops: a key's hiding place is found by breaking things).
func _prop_wire(p: PropData) -> Dictionary:
	return {"id": p.id, "kind": p.kind, "position": GridMath.vec_to_arr(p.position), "hp": p.hp, "blocks": p.blocks,
		"destroyed": _destroyed_props.has(p.id)}


func _door_dc(d: DoorData) -> int:
	return DictUtil.to_int(_door_dcs.get(d.id, d.dc), d.dc)


func _set_door_state(d: DoorData, state: String, by: String, method: String, spell: String = "", extra: Dictionary = {}) -> void:
	_door_states[d.id] = state
	_rebuild_floor_maps()
	var fields := {"door_id": d.id, "state": state, "by": by, "method": method}
	if not spell.is_empty():
		fields["spell"] = spell
	fields.merge(extra)
	_transport.broadcast_result(Messages.make_result(Messages.DOOR_CHANGED, fields))


## Common checks for door / prop intents: the object exists, the player is
## conscious and within `reach` tiles. "" when fine.
func _object_problem(entity: ServerEntity, pos: Vector2i, what: String, reach: int = 1) -> String:
	if not entity.sheet.is_conscious():
		return "%s cannot do that now" % entity.display_name
	if GridMath.distance_tiles(entity.position, pos) > reach:
		return "%s is not next to the %s" % [entity.display_name, what]
	return ""


func _handle_open_door(peer_id: int, entity: ServerEntity, door_id: String) -> void:
	var d := _floor.get_door(door_id)
	if d == null:
		_send_error(peer_id, "there is no door '%s' on this floor" % door_id)
		return
	var problem := _object_problem(entity, d.position, "door")
	if not problem.is_empty():
		_send_error(peer_id, problem)
		return
	match door_state(door_id):
		DoorData.STATE_OPEN:
			_send_error(peer_id, "door '%s' is already open" % door_id)
		DoorData.STATE_LOCKED:
			_send_error(peer_id, "door '%s' is locked" % door_id)
		_:
			entity.path.clear()
			_set_door_state(d, DoorData.STATE_OPEN, entity.id, "hand")


func _handle_close_door(peer_id: int, entity: ServerEntity, door_id: String) -> void:
	var d := _floor.get_door(door_id)
	if d == null:
		_send_error(peer_id, "there is no door '%s' on this floor" % door_id)
		return
	var problem := _object_problem(entity, d.position, "door")
	if not problem.is_empty():
		_send_error(peer_id, problem)
		return
	if door_state(door_id) != DoorData.STATE_OPEN:
		_send_error(peer_id, "door '%s' is not open" % door_id)
		return
	if _occupied().has(d.position):
		_send_error(peer_id, "something stands in the doorway")
		return
	_set_door_state(d, DoorData.STATE_CLOSED, entity.id, "hand")


## unlock_door: key (the door's key_item, carried; used up: DOOR_CHANGED
## "consumed"), tools (thieves' tools: d20 + DEX +
## proficiency when the class has the tool proficiency, against the door's
## dc; a failure may be retried) or spell (casts the spell, Knock by default,
## at the door through the out-of-combat cast; the exploration_effect opens
## the lock). A key or a successful check leaves the door closed (unlocked).
func _handle_unlock_door(peer_id: int, entity: ServerEntity, intent: Dictionary) -> void:
	var door_id := str(intent["door_id"])
	var d := _floor.get_door(door_id)
	if d == null:
		_send_error(peer_id, "there is no door '%s' on this floor" % door_id)
		return
	var method := str(intent["method"])
	if method == Messages.UNLOCK_SPELL:
		var spell_id := str(intent.get("spell", "knock"))
		_handle_cast_out_of_combat(peer_id, entity, Messages.make_intent(Messages.CAST, {
			"actor": entity.id, "spell": spell_id, "target_kind": "door", "target_id": door_id,
		}))
		return
	var problem := _object_problem(entity, d.position, "door")
	if not problem.is_empty():
		_send_error(peer_id, problem)
		return
	if door_state(door_id) != DoorData.STATE_LOCKED:
		_send_error(peer_id, "door '%s' is not locked" % door_id)
		return
	entity.path.clear()
	if method == Messages.UNLOCK_KEY:
		if d.key_item.is_empty() or not entity.sheet.has_item(d.key_item):
			_send_error(peer_id, "%s has no key for this door" % entity.display_name)
			return
		entity.sheet.remove_item(d.key_item, 1, ContentLoader.cache())
		_set_door_state(d, DoorData.STATE_CLOSED, entity.id, Messages.UNLOCK_KEY, "", {"consumed": d.key_item})
		_send_character_state(entity, {"door_unlocked": {"door_id": door_id, "method": Messages.UNLOCK_KEY, "consumed": d.key_item}})
		return
	var dc := _door_dc(d)
	if dc <= 0:
		_send_error(peer_id, "this lock cannot be picked")
		return
	if not entity.sheet.has_item(THIEVES_TOOLS):
		_send_error(peer_id, "%s carries no thieves' tools" % entity.display_name)
		return
	var check := InstanceServer.tools_check_bonus(entity.sheet)
	var roll := D20.roll(_tools_rng)
	var total := roll.natural + check
	if total >= dc:
		_set_door_state(d, DoorData.STATE_CLOSED, entity.id, Messages.UNLOCK_TOOLS)
		_send_character_state(entity, {"door_unlocked": {"door_id": door_id, "method": Messages.UNLOCK_TOOLS, "natural": roll.natural, "total": total, "dc": dc}})
	else:
		_send_character_state(entity, {"unlock_failed": {"door_id": door_id, "natural": roll.natural, "total": total, "dc": dc}})


## Thieves' tools check modifier: DEX, + proficiency when the class has the
## thieves' tools proficiency (the sheet has no tool proficiencies yet).
static func tools_check_bonus(sheet: CharacterSheet) -> int:
	var bonus := sheet.ability_modifier(Ability.Type.DEX)
	var cls := sheet.class_definition({})
	if cls != null and cls.tool_proficiencies.has(THIEVES_TOOLS):
		bonus += sheet.proficiency_bonus()
	return bonus


## interact {prop_id}: breaks an adjacent intact prop (no roll): PROP_DESTROYED
## is broadcast, the breaker gets LOOT_GAINED (source "prop": the prop's drops
## first, then its loot table roll; only when it has either) and CHARACTER_STATE.
func _handle_interact(peer_id: int, entity: ServerEntity, prop_id: String) -> void:
	var p := _floor.get_prop(prop_id)
	if p == null:
		_send_error(peer_id, "there is no prop '%s' on this floor" % prop_id)
		return
	if _destroyed_props.has(prop_id):
		_send_error(peer_id, "the %s is already broken" % p.kind)
		return
	var problem := _object_problem(entity, p.position, p.kind)
	if not problem.is_empty():
		_send_error(peer_id, problem)
		return
	entity.path.clear()
	_destroy_prop(p, entity)


func _destroy_prop(p: PropData, by: ServerEntity) -> void:
	_destroyed_props[p.id] = true
	_rebuild_floor_maps()
	_transport.broadcast_result(Messages.make_result(Messages.PROP_DESTROYED, {"prop_id": p.id, "by": by.id, "kind": p.kind}))
	if (not p.loot_table.is_empty() or not p.drops.is_empty()) and by.is_player():
		var items: Array[Dictionary] = []
		for drop in p.drops:
			LootTable.merge_into(items, str(drop["item"]), DictUtil.to_int(drop["qty"], 1))
		for rolled in _roll_loot(p.loot_table):
			LootTable.merge_into(items, str(rolled["item"]), DictUtil.to_int(rolled["qty"]))
		_give_loot(by, items, Messages.LOOT_SOURCE_PROP, {"prop_id": p.id})
		_send_character_state(by)


# --- respawns ------------------------------------------------------------------------

## Seconds before a cleared zone comes back: boss zones (boss or kind "boss")
## use the floor's boss timer, packs the pack timer; 0 = never.
func _respawn_seconds(zone: EncounterZoneData) -> int:
	if zone.boss or zone.kind == EncounterZoneData.KIND_BOSS:
		return _floor.respawn_boss_seconds
	return _floor.respawn_pack_seconds


## Respawns every cleared zone (schema 2 floors, zones with respawns) whose
## timer ran out, unless a living player stands inside its rect or a fight
## runs there. The respawned pack re-arms the zone (ZONE_RESPAWNED, then
## EXPLORE_STATE).
func _check_respawns() -> void:
	if _floor.schema_version < 2 or _game_over or _set_cleared or _cleared_at.is_empty():
		return
	var spawned := false
	for zone in _floor.encounter_zones:
		if not zone.respawns or not _cleared_zones.has(zone.id) or not _cleared_at.has(zone.id):
			continue
		var secs := _respawn_seconds(zone)
		if secs <= 0 or tick - DictUtil.to_int(_cleared_at[zone.id], tick) < secs * TICKS_PER_SECOND:
			continue
		if _player_in_rect(zone.rect) or _zone_in_fight(zone.id):
			continue
		_respawn_zone(zone)
		spawned = true
	if spawned:
		_broadcast_explore_state()


func _player_in_rect(rect: Rect2i) -> bool:
	for e in _players():
		if e.is_alive() and rect.has_point(e.position):
			return true
	return false


func _zone_in_fight(zone_id: String) -> bool:
	for value: Variant in _sessions.values():
		var session: EncounterSession = value
		if session.zone.id == zone_id:
			return true
	return false


func _respawn_zone(zone: EncounterZoneData) -> void:
	var count: int = DictUtil.to_int(_zone_respawns.get(zone.id, 0), 0) + 1
	_zone_respawns[zone.id] = count
	_cleared_zones.erase(zone.id)
	_cleared_at.erase(zone.id)
	_spawn_zone(zone, "_r%d" % count)
	_transport.broadcast_result(Messages.make_result(Messages.ZONE_RESPAWNED, {"zone_id": zone.id}))


## Marks a zone cleared now (its respawn timer starts).
func _mark_cleared(zone_id: String) -> void:
	_cleared_zones[zone_id] = true
	_cleared_at[zone_id] = tick


# --- exploration effects (round C hooks resolved here) ------------------------------

## Range in tiles of an exploration spell aimed at an object (its effect's
## range_ft; touch / 0 = adjacent).
static func _exploration_reach(spell: SpellDefinition) -> int:
	var ft := DictUtil.to_int(spell.raw_effect.get("range_ft", spell.range_ft), spell.range_ft)
	return maxi(1, GridMath.feet_to_tiles(ft))


## Why an out-of-combat exploration cast cannot work here ("" when it can):
## the object it names exists, is known, in range and in a state the effect
## changes. Checked before the cast so a failed aim spends nothing.
func _exploration_problem(entity: ServerEntity, spell: SpellDefinition, intent: Dictionary) -> String:
	var effect := str(spell.raw_effect.get("exploration", "reveal"))
	var kind := str(intent.get("target_kind", ""))
	var target_id := str(intent.get("target_id", ""))
	match effect:
		"unlock", "lock", "open":
			if kind != "door" and kind != "chest":
				return "%s needs a door or a chest (target_kind / target_id)" % spell.display_name
			var pos := Vector2i.ZERO
			if kind == "door":
				var d := _floor.get_door(target_id)
				if d == null:
					return "there is no door '%s' on this floor" % target_id
				pos = d.position
				var st := door_state(target_id)
				if effect == "unlock" and st != DoorData.STATE_LOCKED:
					return "door '%s' is not locked" % target_id
				if effect == "lock" and st == DoorData.STATE_OPEN:
					return "door '%s' must be closed first" % target_id
				if effect == "lock" and st == DoorData.STATE_LOCKED and _door_dcs.has(target_id):
					return "door '%s' is already magically locked" % target_id
				if effect == "open" and st != DoorData.STATE_CLOSED:
					return "door '%s' is %s" % [target_id, st]
			else:
				var c := _floor.get_chest(target_id)
				if c == null or not is_chest_revealed(target_id):
					return "there is no chest '%s' on this floor" % target_id
				pos = c.position
				if _opened_chests.has(target_id):
					return "chest '%s' is already open" % target_id
				if effect == "unlock" and not is_chest_locked(target_id):
					return "chest '%s' is not locked" % target_id
				if effect == "open" and is_chest_locked(target_id):
					return "chest '%s' is locked" % target_id
			if GridMath.distance_tiles(entity.position, pos) > InstanceServer._exploration_reach(spell):
				return "the %s is out of range of %s" % [kind, spell.display_name]
		"reveal":
			if kind == "zone" and _floor.get_zone(target_id) == null:
				return "there is no zone '%s' on this floor" % target_id
		"teleport":
			if kind != "landmark" or target_id.is_empty():
				return "%s needs a landmark (target_kind \"landmark\", target_id)" % spell.display_name
	return ""


## Applies one exploration_effect event of `caster` (out of combat or in a
## fight): sends DOOR_CHANGED, CHEST_REVEALED, CHEST_OPENED / LOOT_GAINED and
## REVEAL as it goes; teleports are collected in _teleported (the caller
## broadcasts EXPLORE_STATE and checks zone entry).
func _resolve_exploration(caster: ServerEntity, ev: Dictionary) -> void:
	var spell_id := str(ev.get("spell", ""))
	var effect := str(ev.get("effect", ""))
	var kind := str(ev.get("target_kind", ""))
	var target_id := str(ev.get("target_id", ""))
	match effect:
		"unlock", "lock", "open":
			if kind == "door":
				var d := _floor.get_door(target_id)
				if d == null:
					return
				var st := door_state(target_id)
				if effect == "unlock" and st == DoorData.STATE_LOCKED:
					_door_dcs.erase(target_id)
					_set_door_state(d, DoorData.STATE_CLOSED, caster.id, Messages.UNLOCK_SPELL, spell_id)
				elif effect == "lock" and st != DoorData.STATE_OPEN:
					_door_dcs[target_id] = maxi(10, d.dc) + 10  # Arcane Lock: the DC rises by 10
					_set_door_state(d, DoorData.STATE_LOCKED, caster.id, Messages.UNLOCK_SPELL, spell_id)
				elif effect == "open" and st == DoorData.STATE_CLOSED:
					_set_door_state(d, DoorData.STATE_OPEN, caster.id, Messages.UNLOCK_SPELL, spell_id)
					_open_door_in_fights(d)
			elif kind == "chest":
				var c := _floor.get_chest(target_id)
				if c == null or _opened_chests.has(target_id):
					return
				if effect == "unlock":
					_unlocked_chests[target_id] = true
					_arcane_locked_chests.erase(target_id)
					_transport.broadcast_result(Messages.make_result(Messages.CHEST_REVEALED, {"chest": _chest_state(c)}))
				elif effect == "lock":
					_arcane_locked_chests[target_id] = true
					_unlocked_chests.erase(target_id)
					_transport.broadcast_result(Messages.make_result(Messages.CHEST_REVEALED, {"chest": _chest_state(c)}))
				elif effect == "open" and not is_chest_locked(target_id):
					_open_chest_for(caster, c)
		"reveal":
			_send_reveal(caster, ev)
		"light":
			caster.light_level = Encounter.LIGHT_BRIGHT
			_transport.send_result(caster.peer_id, Messages.make_result(Messages.REVEAL, {
				"entity_id": caster.id, "reveal": "light", "spell": spell_id, "light": caster.light_level, "floor_light": floor_light(),
			}))
		"teleport", "recall":
			if caster.in_combat():
				_transport.send_result(caster.peer_id, Messages.make_result(Messages.REVEAL, {
					"entity_id": caster.id, "reveal": "nothing", "spell": spell_id, "reason": "the fight holds you here"}))
				return
			var dest := _landing_position(caster)
			var landmark := "arrival"
			if effect == "teleport" and target_id == "stairs":
				dest = _floor.stairs
				landmark = "stairs"
			var from := caster.position
			caster.path.clear()
			caster.position = _free_tile_near(dest, caster.id)
			_transport.send_result(caster.peer_id, Messages.make_result(Messages.REVEAL, {
				"entity_id": caster.id, "reveal": effect, "spell": spell_id, "from": GridMath.vec_to_arr(from),
				"position": GridMath.vec_to_arr(caster.position), "landmark": landmark}))
			_teleported.append(caster)


## A door opened by magic while a fight runs over it: the fight's map opens too
## (Encounter has no logged API for this; see the D2 report).
func _open_door_in_fights(d: DoorData) -> void:
	for value: Variant in _sessions.values():
		var session: EncounterSession = value
		var enc := session.encounter
		if enc.region.has_point(d.position) and enc.walk_map.in_bounds(d.position):
			enc.walk_map.set_walkable(d.position, true)


## REVEAL for a reveal hook: monsters / creatures (zones within radius or the
## targeted zone, with their living monsters), hidden_chests (CHEST_REVEALED
## too), stairs, map (every zone, door and the stairs), threat (a zone's
## danger: weal when no monster is left or the pack is weak, else woe),
## traps / magic_items (none modelled: an empty answer).
func _send_reveal(caster: ServerEntity, ev: Dictionary) -> void:
	var reveal := str(ev.get("reveal", "monsters"))
	var spell_id := str(ev.get("spell", ""))
	var radius := -1
	if ev.has("radius_ft"):
		radius = GridMath.feet_to_tiles(DictUtil.to_int(ev["radius_ft"], 0))
	elif ev.has("range_ft"):
		radius = GridMath.feet_to_tiles(DictUtil.to_int(ev["range_ft"], 0))
	var target_zone := str(ev.get("target_id", "")) if str(ev.get("target_kind", "")) == "zone" else ""
	var fields := {"entity_id": caster.id, "reveal": reveal, "spell": spell_id}
	match reveal:
		"monsters", "creatures":
			var types := DictUtil.to_string_array(ev.get("creature_types", []))
			var zones: Array = []
			for zone in _floor.encounter_zones:
				if not target_zone.is_empty() and zone.id != target_zone:
					continue
				if target_zone.is_empty() and radius >= 0 and InstanceServer._rect_distance(zone.rect, caster.position) > radius:
					continue
				var monsters := _zone_monsters(zone.id, types)
				if monsters.is_empty():
					continue
				zones.append({"zone_id": zone.id, "name": zone.name, "rect": GridMath.rect_to_arr(zone.rect), "monsters": monsters})
			fields["zones"] = zones
		"hidden_chests":
			var ids: Array = []
			for chest in _floor.chests:
				if not chest.hidden or is_chest_revealed(chest.id):
					continue
				if radius >= 0 and GridMath.distance_tiles(caster.position, chest.position) > radius:
					continue
				_revealed_chests[chest.id] = true
				ids.append(chest.id)
				_transport.broadcast_result(Messages.make_result(Messages.CHEST_REVEALED, {"chest": _chest_state(chest)}))
			fields["chests"] = ids
		"stairs":
			fields["stairs"] = GridMath.vec_to_arr(_floor.stairs)
			var path := explore_map().path_to(caster.position, _floor.stairs, _prop_block)
			fields["distance"] = path.size()
		"map":
			var zones: Array = []
			for zone in _floor.encounter_zones:
				zones.append({"zone_id": zone.id, "name": zone.name, "rect": GridMath.rect_to_arr(zone.rect),
					"cleared": _cleared_zones.has(zone.id), "guards_stairs": zone.guards_stairs})
			fields["zones"] = zones
			fields["stairs"] = GridMath.vec_to_arr(_floor.stairs)
		"threat":
			var zone := _floor.get_zone(target_zone) if not target_zone.is_empty() else _nearest_uncleared_zone(caster.position)
			if zone == null:
				fields["threat"] = "cleared"
			else:
				fields["zone_id"] = zone.id
				var xp := 0
				for m in _zone_monsters(zone.id, []):
					var def: MonsterDefinition = _monster_defs.get(str(m["monster_id"]), null)
					xp += def.xp if def != null else 0
				fields["xp"] = xp
				fields["threat"] = "cleared" if xp == 0 else ("woe" if xp > 50 * maxi(1, caster.sheet.level) else "weal")
		_:
			fields["count"] = 0
	_transport.send_result(caster.peer_id, Messages.make_result(Messages.REVEAL, fields))


## Living monsters of a zone (creature_types filters by type when given).
func _zone_monsters(zone_id: String, types: Array[String]) -> Array:
	var out: Array = []
	for value: Variant in _entities.values():
		var e: ServerEntity = value
		if not e.is_monster() or e.zone_id != zone_id or not e.is_alive():
			continue
		if not types.is_empty():
			var def: MonsterDefinition = _monster_defs.get(e.monster_id, null)
			if def == null or not types.has(def.creature_type):
				continue
		out.append({"id": e.id, "monster_id": e.monster_id, "position": GridMath.vec_to_arr(e.position)})
	return out


func _nearest_uncleared_zone(p: Vector2i) -> EncounterZoneData:
	var best: EncounterZoneData = null
	var best_d := 1 << 30
	for zone in _floor.encounter_zones:
		if _cleared_zones.has(zone.id):
			continue
		var d := InstanceServer._rect_distance(zone.rect, p)
		if d < best_d:
			best_d = d
			best = zone
	return best


## Chebyshev distance from p to the nearest tile of rect (0 inside).
static func _rect_distance(rect: Rect2i, p: Vector2i) -> int:
	var cx := clampi(p.x, rect.position.x, rect.end.x - 1)
	var cy := clampi(p.y, rect.position.y, rect.end.y - 1)
	return GridMath.distance_tiles(p, Vector2i(cx, cy))


## True while a chest cannot be opened by hand: authored locked (and not
## unlocked by Knock) or Arcane Locked.
func is_chest_locked(chest_id: String) -> bool:
	if _arcane_locked_chests.has(chest_id):
		return true
	var c := _floor.get_chest(chest_id) if _floor != null else null
	return c != null and c.locked and not _unlocked_chests.has(chest_id)


## Exploration events of a fight (Knock, Mage Hand, Locate Object, ... cast
## as an action): resolved like out-of-combat ones for the player who cast
## them; their extra events go to the caster's log as OUT_OF_COMBAT_EVENTS.
func _resolve_fight_exploration(events: Array) -> void:
	for ev_v: Variant in events:
		if typeof(ev_v) != TYPE_DICTIONARY:
			continue
		var ev: Dictionary = ev_v
		if str(ev.get("kind", "")) != "exploration_effect":
			continue
		var caster := get_entity(str(ev.get("actor", "")))
		if caster == null or not caster.is_player():
			continue
		_resolve_exploration(caster, ev)

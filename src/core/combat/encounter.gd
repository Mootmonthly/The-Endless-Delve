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
##   {"type": "attack", "target": id, "attack_index": int, "bonus": bool (optional)}
##       action (bonus: true = Martial Arts unarmed strike as a bonus action after
##       the Attack action). Melee: target within reach (adjacent). Ranged /
##       thrown: distance <= long range and line of sight; disadvantage beyond
##       normal range or while a conscious hostile is adjacent to the attacker.
##       Thrown attacks use up the weapon item, ranged ones one ammunition item.
##   {"type": "cast", "spell": id, "target": id (default: actor), "slot_level": int}
##       action or bonus action per the spell; slot_level 0 for cantrips, and for
##       a leveled spell 0/absent = lowest available slot.
##   {"type": "use_item", "item": id, "target": id (optional, self only in M2)}
##   {"type": "use_feature", "feature": "second_wind"|"rage"|"lay_on_hands"|
##       "bardic_inspiration", "target": id (lay_on_hands, bardic_inspiration),
##       "amount": int (lay_on_hands)}
##   {"type": "dash"} / {"type": "dodge"} / {"type": "disengage"}   action
##   {"type": "end_turn"}
## Results: {"ok": bool, "error": String, "events": Array[Dictionary]}.
## Events: Dictionaries with "kind" and JSON-safe values (see src/core/README.md).
## Spells and items come from `content` (ContentLoader.cache() shape; {} = the
## cache); replay() must be given the same content.

enum State { FORMING, ACTIVE, ENDED }

const INTENT_VERSION := 1
const MOVE := "move"
const ATTACK := "attack"
const DASH := "dash"
const DODGE := "dodge"
const DISENGAGE := "disengage"
const END_TURN := "end_turn"
const CAST := "cast"
const USE_ITEM := "use_item"
const USE_FEATURE := "use_feature"
const RAGE_ROUNDS := 10
const DEFAULT_RANGED_TILES: Array[int] = [16, 64]  # 80/320 ft when an attack names no range
const BARDIC_INSPIRATION_RANGE_TILES := 12  # 60 ft
const RAGE_DAMAGE := 2
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
## Definitions for spells and items ({} = ContentLoader.cache()).
var content: Dictionary = {}
var turn_counter: int = 0  # turns started so far (Sneak Attack is once per turn)
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
		CAST:
			error = _check_cast(actor, intent)
		USE_ITEM:
			error = _check_use_item(actor, intent)
		USE_FEATURE:
			error = _check_feature(actor, intent)
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
			var bonus := DictUtil.to_bool(intent.get("bonus", false), false)
			if bonus:
				actor.bonus_action_used = true
			else:
				actor.action_used = true
				actor.attack_action_taken = true
			_resolve_attack(actor, target, DictUtil.to_int(intent.get("attack_index", 0), 0), bonus)
			check_end()
		CAST:
			_do_cast(actor, intent)
			check_end()
		USE_ITEM:
			_do_use_item(actor, intent)
			check_end()
		USE_FEATURE:
			_do_feature(actor, intent)
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
static func replay(seed_value: int, source_map: WalkMap, battle_region: Rect2i, setup: Array[Dictionary], intents: Array[Dictionary], encounter_id: String = "replay", content_set: Dictionary = {}) -> Encounter:
	var enc := Encounter.new(encounter_id, Rng.new(seed_value), source_map, battle_region)
	enc.content = content_set
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
	var bonus := DictUtil.to_bool(intent.get("bonus", false), false)
	if bonus:
		if not actor.sheet.has_feature(ClassDefinition.FEATURE_MARTIAL_ARTS):
			return "%s has no bonus-action attack" % actor.display_name
		if actor.bonus_action_used:
			return "%s has already used its bonus action" % actor.display_name
		if not actor.attack_action_taken:
			return "the Martial Arts strike follows the Attack action"
	elif actor.action_used:
		return "%s has already used its action" % actor.display_name
	var target := get_combatant(str(intent.get("target", "")))
	if target == null:
		return "unknown target"
	if target.team == actor.team:
		return "%s is on the same team" % target.display_name
	if not target.is_alive():
		return "%s is already dead" % target.display_name
	var index := DictUtil.to_int(intent.get("attack_index", 0), -1)
	if index < 0 or index >= actor.attacks.size():
		return "invalid attack_index"
	var attack: Dictionary = actor.attacks[index]
	if bonus and attack.get("unarmed", false) != true:
		return "the bonus-action attack must be an unarmed strike"
	var item := str(attack.get("item", ""))
	if not item.is_empty() and not actor.sheet.has_item(item):
		return "%s no longer carries %s" % [actor.display_name, item]
	var consumes := str(attack.get("consumes", ""))
	if not consumes.is_empty() and not actor.sheet.has_item(consumes):
		return "%s is out of %s" % [actor.display_name, consumes]
	return attack_reach_error(actor.position, target.position, attack)


## "" when an attack from `from` can reach `to`: melee within reach (1 tile
## unless range_tiles says otherwise); ranged / thrown within long range with
## line of sight. Otherwise the reason.
func attack_reach_error(from: Vector2i, to: Vector2i, attack: Dictionary) -> String:
	var dist := GridMath.distance_tiles(from, to)
	var tiles := Encounter.attack_range_tiles(attack)
	if not Encounter.is_ranged_attack(attack):
		return "" if dist >= 1 and dist <= maxi(1, tiles[1]) else "target is out of reach"
	if dist > tiles[1]:
		return "target is out of range (%d tiles, long range %d)" % [dist, tiles[1]]
	if not walk_map.has_line_of_sight(from, to):
		return "no line of sight to the target"
	return ""


## [normal, long] range in tiles: "range_tiles", else "range_ft" / 5, else
## [1, 1] for melee and DEFAULT_RANGED_TILES for ranged / thrown attacks.
static func attack_range_tiles(attack: Dictionary) -> Array[int]:
	var tiles := DictUtil.to_int_array(attack.get("range_tiles", []))
	if tiles.size() == 2:
		return tiles
	var ft := DictUtil.to_int_array(attack.get("range_ft", []))
	if ft.size() == 2:
		return [GridMath.feet_to_tiles(ft[0]), GridMath.feet_to_tiles(ft[1])]
	if Encounter.is_ranged_attack(attack):
		return DEFAULT_RANGED_TILES.duplicate()
	return [1, 1]


## Ranged, thrown and ranged-spell attacks (not melee).
static func is_ranged_attack(attack: Dictionary) -> bool:
	var kind := str(attack.get("kind", "melee"))
	if kind == "spell":
		return attack.get("melee", false) != true
	return kind == "ranged" or kind == "thrown"


## Conscious combatants of other teams adjacent to c.
func _hostile_adjacent(c: Combatant) -> bool:
	for other in tracker.order():
		if other.team != c.team and other.is_conscious() and GridMath.is_adjacent(other.position, c.position):
			return true
	return false


## A conscious ally of attacker (not the attacker) adjacent to target.
func _ally_adjacent_to(target: Combatant, attacker: Combatant) -> bool:
	for other in tracker.order():
		if other != attacker and other.team == attacker.team and other.is_conscious() \
				and GridMath.is_adjacent(other.position, target.position):
			return true
	return false


func _content() -> Dictionary:
	return ContentLoader.resolve(content)


func _spell_def(spell_id: String) -> SpellDefinition:
	var spells: Dictionary = _content()["spells"]
	if not spells.has(spell_id):
		return null
	var s: SpellDefinition = spells[spell_id]
	return s


func _item_def(item_id: String) -> ItemDefinition:
	var items: Dictionary = _content()["items"]
	if not items.has(item_id):
		return null
	var it: ItemDefinition = items[item_id]
	return it


## The slot a cast intent uses: 0 for a cantrip; slot_level, or the lowest
## available slot >= the spell's level when 0 / absent.
func _cast_slot(actor: Combatant, spell: SpellDefinition, intent: Dictionary) -> int:
	if spell.level == 0:
		return 0
	var asked := DictUtil.to_int(intent.get("slot_level", 0), 0)
	return asked if asked > 0 else actor.sheet.lowest_available_slot(spell.level)


func _cast_target(actor: Combatant, intent: Dictionary) -> Combatant:
	var tid := str(intent.get("target", ""))
	if tid.is_empty():
		return actor
	return get_combatant(tid)


func _check_cast(actor: Combatant, intent: Dictionary) -> String:
	var spell_id := str(intent.get("spell", ""))
	var spell := _spell_def(spell_id)
	if spell == null:
		return "unknown spell '%s'" % spell_id
	if not spell.is_supported():
		return "%s cannot be cast yet" % spell.display_name
	if not actor.sheet.is_spell_prepared(spell_id):
		return "%s has not prepared %s" % [actor.display_name, spell.display_name]
	if spell.uses_bonus_action():
		if actor.bonus_action_used:
			return "%s has already used its bonus action" % actor.display_name
	elif actor.action_used:
		return "%s has already used its action" % actor.display_name
	if spell.level == 0:
		if DictUtil.to_int(intent.get("slot_level", 0), 0) != 0:
			return "cantrips do not use spell slots"
	else:
		var slot := _cast_slot(actor, spell, intent)
		if slot == 0:
			return "%s has no spell slots of level %d or higher left" % [actor.display_name, spell.level]
		if slot < spell.level or slot > 9:
			return "%s needs a slot of level %d or higher" % [spell.display_name, spell.level]
		if actor.sheet.slots_left(slot) <= 0:
			return "%s has no level %d spell slots left" % [actor.display_name, slot]
	var target := _cast_target(actor, intent)
	if target == null:
		return "unknown target"
	if spell.target == SpellDefinition.TARGET_SELF and target != actor:
		return "%s can only target its caster" % spell.display_name
	if not target.is_alive():
		return "%s is dead" % target.display_name
	if spell.is_harmful():
		if target.team == actor.team:
			return "%s is on the same team" % target.display_name
	else:
		if target.team != actor.team:
			return "%s is not an ally" % target.display_name
		if spell.effect_type == SpellDefinition.EFFECT_BUFF and spell.buff == SpellDefinition.BUFF_MAGE_ARMOR and target.sheet.armor_base > 0:
			return "%s is wearing armor" % target.display_name
	if target != actor:
		var dist := GridMath.distance_tiles(actor.position, target.position)
		var reach := maxi(1, spell.range_tiles()) if spell.range_ft > 0 else 0
		if dist > reach:
			return "%s is out of range (%d tiles, range %d)" % [target.display_name, dist, reach]
		if not walk_map.has_line_of_sight(actor.position, target.position):
			return "no line of sight to %s" % target.display_name
	return ""


func _check_use_item(actor: Combatant, intent: Dictionary) -> String:
	var item_id := str(intent.get("item", ""))
	var item := _item_def(item_id)
	if item == null:
		return "unknown item '%s'" % item_id
	if not actor.sheet.has_item(item_id):
		return "%s does not carry %s" % [actor.display_name, item.display_name]
	if not item.is_usable():
		return "%s cannot be used" % item.display_name
	if not item.has_implemented_use():
		return "%s has no effect yet" % item.display_name
	var tid := str(intent.get("target", actor.id))
	if not tid.is_empty() and tid != actor.id:
		return "items can only be used on yourself for now"
	if item.use_action == "bonus_action":
		if actor.bonus_action_used:
			return "%s has already used its bonus action" % actor.display_name
	elif actor.action_used:
		return "%s has already used its action" % actor.display_name
	return ""


func _check_feature(actor: Combatant, intent: Dictionary) -> String:
	var feature := str(intent.get("feature", ""))
	if not feature in [ClassDefinition.FEATURE_SECOND_WIND, ClassDefinition.FEATURE_RAGE, ClassDefinition.FEATURE_LAY_ON_HANDS, ClassDefinition.FEATURE_BARDIC_INSPIRATION]:
		return "unknown feature '%s'" % feature
	if not actor.sheet.has_feature(feature):
		return "%s does not have %s" % [actor.display_name, feature]
	if actor.sheet.class_resource(feature) <= 0:
		return "%s has no uses of %s left" % [actor.display_name, feature]
	var uses_action := feature == ClassDefinition.FEATURE_LAY_ON_HANDS
	if uses_action and actor.action_used:
		return "%s has already used its action" % actor.display_name
	if not uses_action and actor.bonus_action_used:
		return "%s has already used its bonus action" % actor.display_name
	match feature:
		ClassDefinition.FEATURE_RAGE:
			if actor.raging:
				return "%s is already raging" % actor.display_name
		ClassDefinition.FEATURE_LAY_ON_HANDS:
			var target := _cast_target(actor, intent)
			if target == null:
				return "unknown target"
			if target.team != actor.team:
				return "%s is not an ally" % target.display_name
			if not target.is_alive():
				return "%s is dead" % target.display_name
			if target != actor and not GridMath.is_adjacent(actor.position, target.position):
				return "%s is out of reach" % target.display_name
			var amount := DictUtil.to_int(intent.get("amount", 0), 0)
			if amount < 1:
				return "lay_on_hands needs an amount of at least 1"
			if amount > actor.sheet.class_resource(feature):
				return "only %d hit points left in the pool" % actor.sheet.class_resource(feature)
		ClassDefinition.FEATURE_BARDIC_INSPIRATION:
			var target := _cast_target(actor, intent)
			if target == null or target == actor:
				return "bardic inspiration needs another creature as target"
			if target.team != actor.team:
				return "%s is not an ally" % target.display_name
			if not target.is_conscious():
				return "%s cannot hear you" % target.display_name
			if GridMath.distance_tiles(actor.position, target.position) > BARDIC_INSPIRATION_RANGE_TILES:
				return "%s is out of range" % target.display_name
			if target.inspiration_die > 0:
				return "%s is already inspired" % target.display_name
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
				_resolve_attack(hostile, actor, _usable_melee_index(hostile))
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
		if h.team == mover.team or not h.is_conscious() or h.reaction_used or _usable_melee_index(h) < 0:
			continue
		if GridMath.is_adjacent(h.position, from) and not GridMath.is_adjacent(h.position, to):
			out.append(h)
	return out


## First melee attack whose weapon item is still carried, or -1.
func _usable_melee_index(c: Combatant) -> int:
	for i in range(c.attacks.size()):
		var attack: Dictionary = c.attacks[i]
		if Encounter.is_ranged_attack(attack):
			continue
		var item := str(attack.get("item", ""))
		if item.is_empty() or c.sheet.has_item(item):
			return i
	return -1


## Rolls one weapon attack and emits attack (+ damage on a hit), then uses up
## a thrown weapon / ammunition.
func _resolve_attack(attacker: Combatant, target: Combatant, attack_index: int, bonus: bool = false) -> AttackResult:
	var attack: Dictionary = attacker.attacks[attack_index]
	var r := _roll_attack(attacker, target, attack, bonus, null)
	return r


## The shared attack roll for weapons and spell attacks. Advantage: target
## unconscious, or marked by Guiding Bolt. Disadvantage: target dodging,
## attacker under Vicious Mockery, and for ranged / thrown / ranged-spell
## attacks beyond normal range or with a conscious hostile adjacent to the
## attacker. A hit from within 5 ft on an unconscious target is critical.
## Bardic Inspiration adds its die to the roll; Rage, Hex and Sneak Attack add
## damage (see AttackResolver extras).
func _roll_attack(attacker: Combatant, target: Combatant, attack: Dictionary, bonus: bool, spell: SpellDefinition) -> AttackResult:
	var kind := str(attack.get("kind", "melee"))
	var ranged := Encounter.is_ranged_attack(attack)
	var dist := GridMath.distance_tiles(attacker.position, target.position)
	var target_down := target.sheet.is_unconscious()
	var advantage := target_down or not target.guided_by.is_empty()
	var disadvantage := (target.dodging and target.is_conscious()) or attacker.mocked
	if ranged and (dist > Encounter.attack_range_tiles(attack)[0] or _hostile_adjacent(attacker)):
		disadvantage = true
	var mode := D20.combine(advantage, disadvantage)
	var auto_crit := target_down and GridMath.is_adjacent(attacker.position, target.position)
	var extra_to_hit := 0
	if attacker.inspiration_die > 0:
		extra_to_hit = rng.next_int(1, attacker.inspiration_die)
		_emit("inspiration_used", {"actor": attacker.id, "source": attacker.inspiration_source, "die": attacker.inspiration_die, "roll": extra_to_hit})
		attacker.inspiration_die = 0
		attacker.inspiration_source = ""
	var damage_type := str(attack.get("damage_type", ""))
	var extras: Array[Dictionary] = []
	if spell == null and attacker.raging and kind == "melee" and str(attack.get("ability", "STR")) == "STR":
		extras.append({"source": "rage", "dice": str(RAGE_DAMAGE), "type": damage_type})
	if target.marks.has(attacker.id):
		var mark: Dictionary = target.marks[attacker.id]
		extras.append({"source": str(mark.get("effect", "")), "dice": str(mark.get("dice", "1d6")), "type": str(mark.get("type", ""))})
	var sneak := false
	if spell == null and attacker.sheet.has_feature(ClassDefinition.FEATURE_SNEAK_ATTACK) and attacker.sneak_attack_turn != turn_counter:
		var props: Array = attack.get("properties", [])
		if props.has("finesse") or kind == "ranged":
			if mode == D20.RollMode.ADVANTAGE or (mode != D20.RollMode.DISADVANTAGE and _ally_adjacent_to(target, attacker)):
				sneak = true
				extras.append({"source": "sneak_attack", "dice": attacker.sheet.sneak_attack_dice(), "type": damage_type})
	var half_on_miss := spell != null and spell.half_on_miss
	var r := AttackResolver.resolve_attack(attacker, target, attack, rng, mode, auto_crit, extra_to_hit, extras, half_on_miss)
	if sneak and r.hit:
		attacker.sneak_attack_turn = turn_counter
	target.guided_by = ""
	target.guided_turns_left = 0
	attacker.mocked = false
	var consumed := ""
	if spell == null:
		consumed = str(attack.get("consumes", ""))
		if not consumed.is_empty():
			attacker.sheet.remove_item(consumed, 1, _content())
	var ev := {
		"attacker": attacker.id,
		"target": target.id,
		"attack_name": r.attack_name,
		"attack_kind": "spell" if spell != null else kind,
		"natural": r.d20.natural,
		"d20s": r.d20.all.duplicate(),
		"total": r.attack_total,
		"target_ac": r.target_ac,
		"hit": r.hit,
		"critical": r.critical,
		"fumble": r.fumble,
		"advantage": Encounter._mode_name(mode),
		"bonus": bonus,
		"consumed": consumed,
	}
	if spell != null:
		ev["spell"] = spell.id
	_emit("attack", ev)
	if r.hit or r.damage_total > 0:
		var dmg := {
			"target": target.id,
			"amount": r.damage_total,
			"type": r.damage_type,
			"hp_after": r.target_hp_after,
			"dropped": r.target_dropped,
			"died": r.target_died,
		}
		if not r.extras.is_empty():
			dmg["extra"] = r.extras.duplicate(true)
		if spell != null:
			dmg["spell"] = spell.id
		_emit("damage", dmg)
	if not target.is_conscious():
		target.dodging = false
	return r


# --- spells, items and features ---------------------------------------------

func _do_cast(actor: Combatant, intent: Dictionary) -> void:
	var spell := _spell_def(str(intent.get("spell", "")))
	var slot := _cast_slot(actor, spell, intent)
	var target := _cast_target(actor, intent)
	if slot > 0:
		actor.sheet.use_spell_slot(slot)
	if spell.uses_bonus_action():
		actor.bonus_action_used = true
	else:
		actor.action_used = true
	_emit("cast", {"actor": actor.id, "spell": spell.id, "target": target.id, "slot_level": slot})
	var above := maxi(0, slot - spell.level)
	match spell.effect_type:
		SpellDefinition.EFFECT_SPELL_ATTACK:
			var tiles := maxi(1, spell.range_tiles())
			var attack := {
				"name": spell.display_name,
				"kind": "spell",
				"melee": spell.melee,
				"to_hit": actor.sheet.spell_attack_bonus(),
				"damage": Encounter._dice_plus(spell.damage_for_level(actor.sheet.level), spell.per_slot_dice, above),
				"damage_type": spell.damage_type,
				"range_tiles": [tiles, tiles],
			}
			for _i in range(spell.rays_for(actor.sheet.level, slot)):
				if not target.is_alive():
					break
				var r := _roll_attack(actor, target, attack, false, spell)
				if r.hit and target.is_alive():
					_apply_rider(actor, target, spell)
		SpellDefinition.EFFECT_AUTO_HIT:
			var darts := spell.darts + spell.per_slot_darts * above
			var expr := DiceExpr.parse(spell.damage)
			var total := 0
			for _i in range(darts):
				total += target.adjust_damage(maxi(0, expr.roll(rng).total), spell.damage_type)
			_deal_spell_damage(target, total, spell, {"darts": darts})
		SpellDefinition.EFFECT_SAVE:
			var success := _saving_throw(actor, target, spell.save_ability, actor.sheet.spell_save_dc())
			if not success or spell.on_save == "half":
				var dice := Encounter._dice_plus(spell.damage_for_level(actor.sheet.level), spell.per_slot_dice, above)
				var rolled := maxi(0, DiceExpr.parse(dice).roll(rng).total)
				if success:
					rolled = floori(rolled / 2.0)
				_deal_spell_damage(target, target.adjust_damage(rolled, spell.damage_type), spell, {})
			if not success and target.is_alive():
				_apply_rider(actor, target, spell)
		SpellDefinition.EFFECT_HEAL:
			var amount := maxi(0, DiceExpr.parse(spell.heal_dice).roll(rng).total)
			if not spell.per_slot_dice.is_empty():
				var per := DiceExpr.parse(spell.per_slot_dice)
				for _i in range(above):
					amount += maxi(0, per.roll(rng).total)
			if spell.add_casting_mod:
				amount += actor.sheet.casting_modifier()
			_heal(actor.id, target, maxi(0, amount))
		SpellDefinition.EFFECT_BUFF:
			if spell.buff == SpellDefinition.BUFF_MAGE_ARMOR:
				if not target.sheet.active_buffs.has(SpellDefinition.BUFF_MAGE_ARMOR):
					target.sheet.active_buffs.append(SpellDefinition.BUFF_MAGE_ARMOR)
				_emit("effect_applied", {"source": actor.id, "target": target.id, "effect": SpellDefinition.BUFF_MAGE_ARMOR, "ac": target.sheet.armor_class()})
			else:
				_apply_rider(actor, target, spell)
		SpellDefinition.EFFECT_MARK:
			target.marks[actor.id] = {"effect": spell.rider, "dice": spell.damage, "type": spell.damage_type}
			_emit("effect_applied", {"source": actor.id, "target": target.id, "effect": spell.rider})


## Applies a spell's rider to target and emits effect_applied.
func _apply_rider(caster: Combatant, target: Combatant, spell: SpellDefinition) -> void:
	match spell.rider:
		SpellDefinition.RIDER_GUIDING:
			target.guided_by = caster.id
			target.guided_turns_left = 2  # this turn's end and the caster's next
		SpellDefinition.RIDER_SLOW:
			target.slowed_tiles = maxi(target.slowed_tiles, spell.slow_tiles)
		SpellDefinition.RIDER_MOCKERY:
			target.mocked = true
			target.mocked_by = caster.id
		SpellDefinition.RIDER_NO_REACTIONS:
			target.reaction_used = true
		SpellDefinition.RIDER_HEX:
			target.marks[caster.id] = {"effect": SpellDefinition.RIDER_HEX, "dice": "1d6", "type": "necrotic"}
		_:
			return
	_emit("effect_applied", {"source": caster.id, "target": target.id, "effect": spell.rider})


## Rolls target's saving throw against dc and emits save. Dodging gives
## advantage on DEX saves; an unconscious creature fails STR and DEX saves
## automatically (natural 0, total 0).
func _saving_throw(caster: Combatant, target: Combatant, ability: int, dc: int) -> bool:
	var natural := 0
	var total := 0
	var success := false
	if target.sheet.is_unconscious() and (ability == Ability.Type.STR or ability == Ability.Type.DEX):
		success = false
	else:
		var mode := D20.combine(target.dodging and ability == Ability.Type.DEX, false)
		var d := D20.roll(rng, mode)
		natural = d.natural
		total = d.natural + target.sheet.save_modifier(ability)
		success = total >= dc
	_emit("save", {
		"actor": caster.id,
		"target": target.id,
		"ability": Ability.abbreviation(ability),
		"dc": dc,
		"natural": natural,
		"total": total,
		"success": success,
	})
	return success


## Applies already-adjusted spell damage and emits damage (+ "spell" and extras).
func _deal_spell_damage(target: Combatant, amount: int, spell: SpellDefinition, fields: Dictionary) -> void:
	var outcome := target.sheet.take_damage(amount)
	var ev := {
		"target": target.id,
		"amount": outcome.amount,
		"type": spell.damage_type,
		"hp_after": target.sheet.current_hp,
		"dropped": outcome.dropped_to_zero,
		"died": outcome.died,
		"spell": spell.id,
	}
	ev.merge(fields)
	_emit("damage", ev)
	if not target.is_conscious():
		target.dodging = false


## Heals target and emits heal {source, target, amount (restored), rolled,
## hp_after, revived}. Healing a creature at 0 hp brings it back up.
func _heal(source_id: String, target: Combatant, rolled: int) -> void:
	var before := target.sheet.current_hp
	var restored := target.sheet.heal(rolled)
	_emit("heal", {
		"source": source_id,
		"target": target.id,
		"amount": restored,
		"rolled": rolled,
		"hp_after": target.sheet.current_hp,
		"revived": before == 0 and target.sheet.current_hp > 0,
	})


func _do_use_item(actor: Combatant, intent: Dictionary) -> void:
	var item := _item_def(str(intent.get("item", "")))
	if item.use_action == "bonus_action":
		actor.bonus_action_used = true
	else:
		actor.action_used = true
	actor.sheet.remove_item(item.id, 1, _content())
	_emit("item_used", {"actor": actor.id, "item": item.id, "target": actor.id})
	match item.use_effect:
		ItemDefinition.EFFECT_HEAL:
			_heal(actor.id, actor, maxi(0, DiceExpr.parse(item.use_dice).roll(rng).total))
		ItemDefinition.EFFECT_TEMP_HP:
			var amount := maxi(0, DiceExpr.parse(item.use_dice).roll(rng).total)
			actor.sheet.grant_temp_hp(amount)
			_emit("temp_hp", {"source": actor.id, "target": actor.id, "amount": amount, "temp_hp_after": actor.sheet.temp_hp})
		ItemDefinition.EFFECT_CURE:
			for condition in item.use_conditions:
				actor.sheet.conditions.erase(condition)


func _do_feature(actor: Combatant, intent: Dictionary) -> void:
	var feature := str(intent.get("feature", ""))
	var target := actor
	var spend := 1
	if feature == ClassDefinition.FEATURE_LAY_ON_HANDS:
		target = _cast_target(actor, intent)
		spend = DictUtil.to_int(intent.get("amount", 0), 0)
		actor.action_used = true
	else:
		if feature == ClassDefinition.FEATURE_BARDIC_INSPIRATION:
			target = _cast_target(actor, intent)
		actor.bonus_action_used = true
	actor.sheet.spend_class_resource(feature, spend)
	_emit("feature_used", {"actor": actor.id, "feature": feature, "target": target.id, "remaining": actor.sheet.class_resource(feature)})
	match feature:
		ClassDefinition.FEATURE_SECOND_WIND:
			var amount := maxi(0, DiceExpr.parse("1d10").roll(rng).total) + actor.sheet.level
			_heal(actor.id, actor, amount)
		ClassDefinition.FEATURE_RAGE:
			actor.raging = true
			actor.rage_started_round = tracker.round_number
			_emit("effect_applied", {"source": actor.id, "target": actor.id, "effect": "rage"})
		ClassDefinition.FEATURE_LAY_ON_HANDS:
			_heal(actor.id, target, spend)
		ClassDefinition.FEATURE_BARDIC_INSPIRATION:
			target.inspiration_die = Encounter.bardic_die(actor.sheet.level)
			target.inspiration_source = actor.id
			_emit("effect_applied", {"source": actor.id, "target": target.id, "effect": "bardic_inspiration", "die": target.inspiration_die})


## SRD Bardic Inspiration die by bard level: d6, d8 at 5, d10 at 10, d12 at 15.
static func bardic_die(bard_level: int) -> int:
	if bard_level >= 15:
		return 12
	if bard_level >= 10:
		return 10
	if bard_level >= 5:
		return 8
	return 6


## Upcasting: base dice plus `times` copies of per, e.g. ("4d6", "1d6", 2) ->
## "6d6". DiceExpr has one dice group, so extra dice of another size count as
## the base die (no supported SRD spell mixes sizes). Empty per or times 0 = base.
static func _dice_plus(base: String, per: String, times: int) -> String:
	if per.is_empty() or times <= 0:
		return base
	var b := DiceExpr.parse(base)
	var p := DiceExpr.parse(per)
	if not b.valid or not p.valid or b.is_constant():
		return base
	var text := "%dd%d" % [b.count + p.count * times, b.sides]
	var mod := b.modifier + p.modifier * times
	return text + CharacterBuilder.signed(mod)


## End-of-turn bookkeeping for c: Vicious Mockery wears off, Guiding Bolt
## marks made by c count down.
func _on_turn_end(c: Combatant) -> void:
	if c.mocked:
		c.mocked = false
		_emit("effect_ended", {"target": c.id, "effect": SpellDefinition.RIDER_MOCKERY})
	for other in tracker.order():
		if other.guided_by == c.id:
			other.guided_turns_left -= 1
			if other.guided_turns_left <= 0:
				other.guided_by = ""
				_emit("effect_ended", {"target": other.id, "effect": SpellDefinition.RIDER_GUIDING})


func _end_current_turn() -> void:
	var c := tracker.current()
	if c != null:
		_emit("turn_ended", {"actor": c.id})
		_on_turn_end(c)
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
		turn_counter += 1
		c.reset_turn()
		if c.raging and tracker.round_number - c.rage_started_round >= RAGE_ROUNDS:
			c.raging = false
			_emit("effect_ended", {"target": c.id, "effect": "rage"})
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
		_on_turn_end(c)
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

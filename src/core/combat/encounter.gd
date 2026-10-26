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
## Intents (Dictionary, "v": 1, "actor": id of the current actor); every field
## below is part of the logged intent. See src/core/README.md for the full table.
##   {"type": "move", "path": [[x, y], ...]}   steps via WalkMap.can_step, <= movement_remaining
##       (a prone mover stands up first: half its speed)
##   {"type": "stand"}   a prone creature stands up (half its speed)
##   {"type": "attack", "target": id, "attack_index": int, "bonus": bool,
##    "reckless": bool, "smite": slot level, "stun": bool, "technique":
##    "prone"|"push"|"no_reactions", "retarget": bool}
##       The first attack takes the Attack action (attacks_per_action rolls:
##       Extra Attack / Multiattack); later attacks use the remaining rolls.
##       bonus: a bonus-action attack (Martial Arts, Flurry of Blows strikes,
##       two-weapon fighting off-hand attack, Frenzy).
##   {"type": "cast", "spell": id, "target": id (default: actor), "slot_level": int,
##    "point": [x, y] (area spells), "sculpt": [ids], "metamagic": [ids],
##    "twin_target": id}
##   {"type": "use_item", "item": id, "target": id (optional, self only), "bonus": bool (Fast Hands)}
##   {"type": "use_feature", "feature": id, "target": id, "amount": int, "mode": String,
##    "slot_level": int, "allocations": {id: hp}, "frenzy": bool}
##   {"type": "dash"} / {"type": "dodge"} / {"type": "disengage"}   action
##   {"type": "end_turn"}
## Results: {"ok": bool, "error": String, "events": Array[Dictionary]}.
## Events: Dictionaries with "kind" and JSON-safe values (see src/core/README.md).
## Spells and items come from `content` (ContentLoader.cache() shape; {} = the
## cache); replay() must be given the same content.

enum State { FORMING, ACTIVE, ENDED }

const INTENT_VERSION := 1
const MOVE := "move"
const STAND := "stand"
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
const CHANNEL_DIVINITY_RANGE_TILES := 6  # 30 ft (Turn Undead, Preserve Life)
const TURNED_ROUNDS := 10  # 1 minute
const SACRED_WEAPON_ROUNDS := 10
const OPEN_HAND_PUSH_TILES := 3  # 15 ft
const REPELLING_BLAST_TILES := 2  # 10 ft
const SMITE_MAX_DICE := 5
const TECHNIQUES: Array[String] = ["prone", "push", "no_reactions"]
const METAMAGIC_SUPPORTED: Array[String] = ["quickened_spell", "twinned_spell", "empowered_spell"]
const KI_FEATURES: Array[String] = ["flurry_of_blows", "patient_defense", "step_of_the_wind"]
const CHANNEL_DIVINITY_FEATURES: Array[String] = ["turn_undead", "turn_the_unholy", "preserve_life", "sacred_weapon"]
## use_feature ids the encounter resolves.
const USABLE_FEATURES: Array[String] = [
	"second_wind", "rage", "lay_on_hands", "bardic_inspiration", "action_surge",
	"flurry_of_blows", "patient_defense", "step_of_the_wind", "cunning_action",
	"turn_undead", "turn_the_unholy", "preserve_life", "sacred_weapon", "font_of_magic",
	"pact_weapon",
]
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
	if actor.is_incapacitated() and not intent_type in [MOVE, STAND, END_TURN]:
		error = "%s is incapacitated" % actor.display_name
	elif actor.is_fleeing() and not intent_type in [MOVE, STAND, DASH, DODGE, END_TURN]:
		error = "%s is turned: it can only move away, Dash or Dodge" % actor.display_name
	if error.is_empty():
		match intent_type:
			MOVE:
				error = _check_move(actor, intent)
			STAND:
				error = stand_error(actor)
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
		STAND:
			_stand(actor)
		ATTACK:
			_do_attack(actor, intent)
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
			_dash(actor)
		DODGE:
			actor.action_used = true
			_dodge(actor)
		DISENGAGE:
			actor.action_used = true
			_disengage(actor)
		END_TURN:
			_end_current_turn()
	# An actor knocked out during its own turn (opportunity attack) is done.
	if intent_type != END_TURN and state == State.ACTIVE and current_actor() == actor and not actor.is_conscious():
		_end_current_turn()
	var result := {"ok": true, "error": "", "events": _pending.duplicate()}
	_pending.clear()
	return result


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
	var budget := actor.movement_remaining
	if actor.has_condition(Conditions.PRONE):
		var stand_problem := stand_error(actor)
		if not stand_problem.is_empty():
			return stand_problem
		budget -= stand_cost(actor)
	if steps.size() > budget:
		return "path has %d steps but only %d tiles of movement remain" % [steps.size(), budget]
	var occupied := occupied_cells(actor.id)
	var fears := fear_sources(actor)
	var cursor := actor.position
	for step_v: Variant in steps:
		if not GridMath.is_vec_arr(step_v):
			return "malformed path step %s" % str(step_v)
		var step := GridMath.arr_to_vec(step_v)
		if not walk_map.can_step(cursor, step, occupied):
			return "cannot step from %s to %s" % [str(cursor), str(step)]
		for source in fears:
			if GridMath.distance_tiles(step, source.position) < GridMath.distance_tiles(cursor, source.position):
				return "%s is frightened and cannot move closer to %s" % [actor.display_name, source.display_name]
		cursor = step
	return ""


## Living creatures actor is frightened of (it may not move closer to them).
func fear_sources(actor: Combatant) -> Array[Combatant]:
	var out: Array[Combatant] = []
	for src_id in actor.condition_sources(Conditions.FRIGHTENED):
		var src := get_combatant(src_id)
		if src != null and src.is_alive():
			out.append(src)
	return out


## Standing up costs half the creature's speed (rounded up).
func stand_cost(actor: Combatant) -> int:
	return ceili(actor.speed_tiles() / 2.0)


func stand_error(actor: Combatant) -> String:
	if not actor.has_condition(Conditions.PRONE):
		return "%s is not prone" % actor.display_name
	if actor.speed_tiles() <= 0:
		return "%s cannot stand up (speed 0)" % actor.display_name
	if actor.movement_remaining < stand_cost(actor):
		return "standing up needs %d tiles of movement" % stand_cost(actor)
	return ""


## The combatant an attack intent hits: its target, or with "retarget" (monster
## multiattack follow-ups) when that target is no longer conscious, the
## conscious hostile in reach of the attack with the lowest hp (ties: id).
func _attack_target(actor: Combatant, intent: Dictionary) -> Combatant:
	var target := get_combatant(str(intent.get("target", "")))
	if not DictUtil.to_bool(intent.get("retarget", false), false):
		return target
	if target != null and target.is_conscious():
		return target
	var index := DictUtil.to_int(intent.get("attack_index", 0), -1)
	if index < 0 or index >= actor.attacks.size():
		return target
	var attack: Dictionary = actor.attacks[index]
	var best: Combatant = null
	for h in hostiles_of(actor):
		if not h.is_conscious() or not attack_reach_error(actor.position, h.position, attack).is_empty():
			continue
		if best == null or h.sheet.current_hp < best.sheet.current_hp or (h.sheet.current_hp == best.sheet.current_hp and h.id < best.id):
			best = h
	return best if best != null else target


func _check_attack(actor: Combatant, intent: Dictionary) -> String:
	var bonus := DictUtil.to_bool(intent.get("bonus", false), false)
	var index := DictUtil.to_int(intent.get("attack_index", 0), -1)
	var attack: Dictionary = actor.attacks[index] if index >= 0 and index < actor.attacks.size() else {}
	if bonus:
		var src := _bonus_attack_source(actor, attack)
		if src.begins_with("!"):
			return src.substr(1)
	elif actor.action_used and not (actor.attack_action_taken and actor.attacks_remaining > 0):
		return "%s has already used its action" % actor.display_name
	var target := _attack_target(actor, intent)
	if target == null:
		return "unknown target"
	if target.team == actor.team:
		return "%s is on the same team" % target.display_name
	if not target.is_alive():
		return "%s is already dead" % target.display_name
	if attack.is_empty():
		return "invalid attack_index"
	if not bonus and attack.get("off_hand", false) == true:
		return "the off-hand weapon attacks as a bonus action (two-weapon fighting)"
	if actor.condition_sources(Conditions.CHARMED).has(target.id):
		return "%s is charmed by %s" % [actor.display_name, target.display_name]
	var item := str(attack.get("item", ""))
	if not item.is_empty() and not actor.sheet.has_item(item):
		return "%s no longer carries %s" % [actor.display_name, item]
	var consumes := str(attack.get("consumes", ""))
	if not consumes.is_empty() and not actor.sheet.has_item(consumes):
		return "%s is out of %s" % [actor.display_name, consumes]
	var melee_weapon := not Encounter.is_ranged_attack(attack)
	if DictUtil.to_bool(intent.get("reckless", false), false):
		if not actor.sheet.has_feature("reckless_attack"):
			return "%s cannot attack recklessly" % actor.display_name
		if actor.attack_action_taken or bonus:
			return "Reckless Attack is decided on the first attack of the turn"
		if not melee_weapon or str(attack.get("ability", "STR")) != "STR":
			return "Reckless Attack needs a melee attack using Strength"
	var smite := DictUtil.to_int(intent.get("smite", 0), 0)
	if smite != 0:
		if not actor.sheet.has_feature("divine_smite"):
			return "%s cannot smite" % actor.display_name
		if not melee_weapon:
			return "Divine Smite needs a melee weapon attack"
		if smite < 1 or smite > 9 or actor.sheet.slots_left(smite) <= 0:
			return "no level %d spell slot left for Divine Smite" % smite
	if DictUtil.to_bool(intent.get("stun", false), false):
		if not actor.sheet.has_feature("stunning_strike"):
			return "%s does not know Stunning Strike" % actor.display_name
		if not melee_weapon:
			return "Stunning Strike needs a melee weapon attack"
		if actor.sheet.class_resource("ki") < 1:
			return "no ki points left"
	var technique := str(intent.get("technique", ""))
	if not technique.is_empty():
		if not actor.sheet.has_feature("open_hand_technique"):
			return "%s does not know the Open Hand Technique" % actor.display_name
		if not TECHNIQUES.has(technique):
			return "technique must be one of %s" % ", ".join(TECHNIQUES)
		if not bonus or actor.bonus_attacks_remaining <= 0 or actor.bonus_attack_source != "flurry_of_blows":
			return "the Open Hand Technique applies to Flurry of Blows strikes"
	return attack_reach_error(actor.position, target.position, attack)


## Which feature allows a bonus-action attack with `attack`: "flurry_of_blows",
## "two_weapon_fighting", "martial_arts" or "frenzy"; "!reason" when none does.
func _bonus_attack_source(actor: Combatant, attack: Dictionary) -> String:
	var unarmed: bool = attack.get("unarmed", false) == true
	if actor.bonus_attacks_remaining > 0:
		if unarmed:
			return actor.bonus_attack_source
		return "!Flurry of Blows strikes are unarmed strikes"
	if actor.bonus_action_used:
		return "!%s has already used its bonus action" % actor.display_name
	if attack.get("off_hand", false) == true:
		if not actor.attack_action_taken:
			return "!the off-hand attack follows the Attack action"
		return "two_weapon_fighting"
	var martial := actor.sheet.has_feature(ClassDefinition.FEATURE_MARTIAL_ARTS)
	if unarmed and martial:
		if not actor.attack_action_taken:
			return "!the Martial Arts strike follows the Attack action"
		return "martial_arts"
	if actor.frenzied and actor.raging and not attack.is_empty() and not Encounter.is_ranged_attack(attack):
		if actor.rage_started_turn == turn_counter:
			return "!the Frenzy attack starts on the turn after you rage"
		return "frenzy"
	if martial:
		return "!the bonus-action attack must be an unarmed strike"
	return "!%s has no bonus-action attack" % actor.display_name


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


## Conscious, not incapacitated combatants of other teams adjacent to c.
func _hostile_adjacent(c: Combatant) -> bool:
	for other in tracker.order():
		if other.team != c.team and other.is_conscious() and not other.is_incapacitated() \
				and GridMath.is_adjacent(other.position, c.position):
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


## Armor of Shadows: Mage Armor on itself at will, without a slot.
func _free_mage_armor(actor: Combatant, spell: SpellDefinition, intent: Dictionary) -> bool:
	if spell.buff != SpellDefinition.BUFF_MAGE_ARMOR or not actor.sheet.invocations.has("armor_of_shadows"):
		return false
	var tid := str(intent.get("target", actor.id))
	return tid.is_empty() or tid == actor.id


## The slot a cast intent uses: 0 for a cantrip (and Armor of Shadows);
## slot_level, or the lowest available slot >= the spell's level when 0 / absent.
func _cast_slot(actor: Combatant, spell: SpellDefinition, intent: Dictionary) -> int:
	if spell.level == 0 or _free_mage_armor(actor, spell, intent):
		return 0
	var asked := DictUtil.to_int(intent.get("slot_level", 0), 0)
	return asked if asked > 0 else actor.sheet.lowest_available_slot(spell.level)


func _cast_target(actor: Combatant, intent: Dictionary) -> Combatant:
	var tid := str(intent.get("target", ""))
	if tid.is_empty():
		return actor
	return get_combatant(tid)


## Metamagic ids of a cast intent (validated by _check_cast).
static func _metamagic_of(intent: Dictionary) -> Array[String]:
	return DictUtil.to_string_array(intent.get("metamagic", []))


## Sorcery points a cast's metamagic costs (quickened 2, empowered 1, twinned
## the spell's level, min 1).
static func _metamagic_cost(options: Array[String], spell: SpellDefinition) -> int:
	var cost := 0
	for m in options:
		match m:
			"quickened_spell":
				cost += 2
			"empowered_spell":
				cost += 1
			"twinned_spell":
				cost += maxi(1, spell.level)
	return cost


func _check_cast(actor: Combatant, intent: Dictionary) -> String:
	var spell_id := str(intent.get("spell", ""))
	var spell := _spell_def(spell_id)
	if spell == null:
		return "unknown spell '%s'" % spell_id
	if not spell.is_supported():
		return "%s cannot be cast yet" % spell.display_name
	if not spell.is_combat_castable():
		return "%s takes %s to cast and cannot be cast in combat" % [spell.display_name, spell.casting_time.replace("_", " ")]
	if not actor.sheet.is_spell_prepared(spell_id) and not _free_mage_armor(actor, spell, intent):
		return "%s has not prepared %s" % [actor.display_name, spell.display_name]
	if actor.raging:
		return "%s cannot cast spells while raging" % actor.display_name
	var meta := Encounter._metamagic_of(intent)
	for m in meta:
		if not actor.sheet.metamagic.has(m):
			return "%s does not know %s" % [actor.display_name, m]
		if not Features.IMPLEMENTED_METAMAGIC.has(m):
			return "%s is not modelled yet" % m
		if meta.count(m) > 1:
			return "%s is listed twice" % m
	if meta.has("quickened_spell") and meta.has("twinned_spell"):
		return "only one of Quickened and Twinned Spell per casting"
	if not meta.is_empty() and actor.sheet.class_resource("sorcery_points") < Encounter._metamagic_cost(meta, spell):
		return "not enough sorcery points (%d needed)" % Encounter._metamagic_cost(meta, spell)
	var quickened := meta.has("quickened_spell")
	if quickened and spell.uses_bonus_action():
		return "Quickened Spell needs a spell cast with an action"
	if spell.uses_bonus_action() or quickened:
		if actor.bonus_action_used:
			return "%s has already used its bonus action" % actor.display_name
	elif actor.action_used:
		return "%s has already used its action" % actor.display_name
	if spell.level == 0 or _free_mage_armor(actor, spell, intent):
		if DictUtil.to_int(intent.get("slot_level", 0), 0) != 0:
			return "cantrips do not use spell slots" if spell.level == 0 else "Armor of Shadows needs no spell slot"
	else:
		var slot := _cast_slot(actor, spell, intent)
		if slot == 0:
			return "%s has no spell slots of level %d or higher left" % [actor.display_name, spell.level]
		if slot < spell.level or slot > 9:
			return "%s needs a slot of level %d or higher" % [spell.display_name, spell.level]
		if actor.sheet.slots_left(slot) <= 0:
			return "%s has no level %d spell slots left" % [actor.display_name, slot]
	var sculpt := DictUtil.to_string_array(intent.get("sculpt", []))
	if not sculpt.is_empty():
		if not actor.sheet.has_feature("sculpt_spells") or spell.school.to_lower() != "evocation" or not spell.is_area():
			return "only an evocation area spell of a Sculpt Spells caster can be sculpted"
		if sculpt.size() > 1 + spell.level:
			return "at most %d creatures can be sculpted" % (1 + spell.level)
		for sid in sculpt:
			var s := get_combatant(sid)
			if s == null or s.team != actor.team:
				return "%s is not an ally" % sid
	if spell.is_area():
		return _check_area(actor, spell, intent)
	var target := _cast_target(actor, intent)
	var err := _check_spell_target(actor, spell, target)
	if not err.is_empty():
		return err
	if meta.has("twinned_spell"):
		if spell.range_ft == 0 or spell.target == SpellDefinition.TARGET_SELF:
			return "Twinned Spell needs a spell that targets one creature other than the caster"
		var twin := get_combatant(str(intent.get("twin_target", "")))
		if twin == null or twin == target:
			return "Twinned Spell needs a second, different twin_target"
		err = _check_spell_target(actor, spell, twin)
		if not err.is_empty():
			return err
	elif intent.has("twin_target"):
		return "twin_target needs Twinned Spell"
	return ""


## Target rules of a single-target spell.
func _check_spell_target(actor: Combatant, spell: SpellDefinition, target: Combatant) -> String:
	if target == null:
		return "unknown target"
	if spell.target == SpellDefinition.TARGET_SELF and target != actor:
		return "%s can only target its caster" % spell.display_name
	if not target.is_alive():
		return "%s is dead" % target.display_name
	if spell.is_harmful():
		if target.team == actor.team:
			return "%s is on the same team" % target.display_name
		if actor.condition_sources(Conditions.CHARMED).has(target.id):
			return "%s is charmed by %s" % [actor.display_name, target.display_name]
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


## Self-centred area spells (range self, sphere / cube / cylinder) need no point.
static func _self_centred(spell: SpellDefinition) -> bool:
	return spell.range_ft == 0 and spell.area_shape in ["sphere", "cube", "cylinder"]


## Where an area spell is centred / aimed: "point", or the caster for a
## self-centred area.
func _area_point(actor: Combatant, spell: SpellDefinition, intent: Dictionary) -> Vector2i:
	if Encounter._self_centred(spell) or not GridMath.is_vec_arr(intent.get("point", null)):
		return actor.position
	return GridMath.arr_to_vec(intent["point"])


func _check_area(actor: Combatant, spell: SpellDefinition, intent: Dictionary) -> String:
	if Encounter._self_centred(spell):
		return ""
	if not GridMath.is_vec_arr(intent.get("point", null)):
		return "%s needs a point [x, y]" % spell.display_name
	var point := GridMath.arr_to_vec(intent["point"])
	if not region.has_point(point):
		return "the point is outside the battle area"
	if spell.range_ft == 0:
		if point == actor.position:
			return "aim %s away from the caster" % spell.display_name
		return ""
	var dist := GridMath.distance_tiles(actor.position, point)
	if dist > spell.range_tiles():
		return "the point is out of range (%d tiles, range %d)" % [dist, spell.range_tiles()]
	if not walk_map.has_line_of_sight(actor.position, point):
		return "no line of sight to the point"
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
	if _item_uses_bonus(actor, item, intent):
		if DictUtil.to_bool(intent.get("bonus", false), false) and not actor.sheet.has_feature("fast_hands"):
			return "%s cannot use items as a bonus action" % actor.display_name
		if actor.bonus_action_used:
			return "%s has already used its bonus action" % actor.display_name
	elif actor.action_used:
		return "%s has already used its action" % actor.display_name
	return ""


## A bonus-action item, or "bonus": true (Fast Hands).
static func _item_uses_bonus(_actor: Combatant, item: ItemDefinition, intent: Dictionary) -> bool:
	return item.use_action == "bonus_action" or DictUtil.to_bool(intent.get("bonus", false), false)


## Whether actor may use `feature` (ki options also come with "ki").
func _has_usable_feature(actor: Combatant, feature: String) -> bool:
	if actor.sheet.has_feature(feature):
		return true
	if KI_FEATURES.has(feature):
		return actor.sheet.has_feature("ki")
	if feature == "pact_weapon":
		return actor.sheet.has_feature("pact_of_the_blade")
	if feature == "font_of_magic":
		return actor.sheet.has_feature("font_of_magic")
	return false


## Resource id spent by a feature use ("" = none).
static func _feature_resource(feature: String) -> String:
	if KI_FEATURES.has(feature):
		return "ki"
	if CHANNEL_DIVINITY_FEATURES.has(feature):
		return "channel_divinity"
	if feature == "font_of_magic":
		return "sorcery_points"
	if CharacterSheet.RESOURCE_FEATURES.has(feature):
		return feature
	return ""


## "action", "bonus" or "free".
static func _feature_cost(feature: String) -> String:
	match feature:
		"lay_on_hands", "turn_undead", "turn_the_unholy", "preserve_life", "sacred_weapon", "pact_weapon":
			return "action"
		"action_surge":
			return "free"
	return "bonus"


func _check_feature(actor: Combatant, intent: Dictionary) -> String:
	var feature := str(intent.get("feature", ""))
	if not USABLE_FEATURES.has(feature):
		return "unknown feature '%s'" % feature
	if not _has_usable_feature(actor, feature):
		return "%s does not have %s" % [actor.display_name, feature]
	var resource := Encounter._feature_resource(feature)
	if not resource.is_empty() and feature != "font_of_magic" and actor.sheet.class_resource(resource) <= 0:
		return "%s has no uses of %s left" % [actor.display_name, resource]
	match Encounter._feature_cost(feature):
		"action":
			if actor.action_used:
				return "%s has already used its action" % actor.display_name
		"bonus":
			if actor.bonus_action_used:
				return "%s has already used its bonus action" % actor.display_name
	var mode := str(intent.get("mode", ""))
	match feature:
		ClassDefinition.FEATURE_RAGE:
			if actor.raging:
				return "%s is already raging" % actor.display_name
			if DictUtil.to_bool(intent.get("frenzy", false), false) and not actor.sheet.has_feature("frenzy"):
				return "%s cannot frenzy" % actor.display_name
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
		"action_surge":
			if actor.action_surged:
				return "Action Surge can be used once per turn"
		"flurry_of_blows":
			if not actor.attack_action_taken:
				return "Flurry of Blows follows the Attack action"
		"step_of_the_wind":
			if not mode in ["dash", "disengage"]:
				return "step_of_the_wind needs mode \"dash\" or \"disengage\""
		"cunning_action":
			if mode == "hide":
				return "hiding is not modelled yet"
			if not mode in ["dash", "disengage"]:
				return "cunning_action needs mode \"dash\" or \"disengage\""
		"preserve_life":
			return _check_preserve_life(actor, intent)
		"font_of_magic":
			return _check_font_of_magic(actor, intent)
		"pact_weapon":
			if actor.pact_weapon:
				return "the pact weapon is already in hand"
	return ""


func _check_preserve_life(actor: Combatant, intent: Dictionary) -> String:
	var alloc_v: Variant = intent.get("allocations", null)
	if typeof(alloc_v) != TYPE_DICTIONARY:
		return "preserve_life needs allocations {id: hit points}"
	var alloc: Dictionary = alloc_v
	if alloc.is_empty():
		return "preserve_life needs allocations {id: hit points}"
	var total := 0
	for key: Variant in alloc.keys():
		var t := get_combatant(str(key))
		var amount := DictUtil.to_int(alloc[key], 0)
		if t == null or t.team != actor.team or not t.is_alive():
			return "%s is not a living ally" % str(key)
		if t.creature_type in ["undead", "construct"]:
			return "%s cannot be healed by Preserve Life" % t.display_name
		if GridMath.distance_tiles(actor.position, t.position) > CHANNEL_DIVINITY_RANGE_TILES:
			return "%s is out of range" % t.display_name
		if amount < 1:
			return "each allocation must be at least 1"
		if t.sheet.current_hp + amount > floori(t.sheet.max_hp / 2.0):
			return "Preserve Life cannot raise %s above half its hit point maximum" % t.display_name
		total += amount
	if total > 5 * actor.sheet.level:
		return "Preserve Life restores at most %d hit points" % (5 * actor.sheet.level)
	return ""


func _check_font_of_magic(actor: Combatant, intent: Dictionary) -> String:
	var slot := DictUtil.to_int(intent.get("slot_level", 0), 0)
	match str(intent.get("mode", "")):
		"create_slot":
			if slot < 1 or slot > Progression.MAX_CREATED_SLOT:
				return "slots of level 1..%d can be created" % Progression.MAX_CREATED_SLOT
			var cost := _slot_creation_cost(actor, slot)
			if actor.sheet.class_resource("sorcery_points") < cost:
				return "a level %d slot costs %d sorcery points" % [slot, cost]
		"convert_slot":
			if actor.sheet.slots_left(slot) <= 0:
				return "no level %d spell slot to convert" % slot
		_:
			return "font_of_magic needs mode \"create_slot\" or \"convert_slot\""
	return ""


## Sorcery points to create a slot (class "sorcery_slot_costs", else SRD).
func _slot_creation_cost(actor: Combatant, slot: int) -> int:
	var cls := actor.sheet.class_definition(_content())
	if cls != null and cls.sorcery_slot_costs.has(slot):
		return DictUtil.to_int(cls.sorcery_slot_costs[slot])
	return Progression.SLOT_CREATION_COST.get(slot, 99)


# --- movement and simple actions -----------------------------------------------

func _do_move(actor: Combatant, path: Array[Vector2i]) -> void:
	if actor.has_condition(Conditions.PRONE):
		_stand(actor)
	for step in path:
		var from := actor.position
		if not actor.disengaging:
			for hostile in _opportunity_attackers(actor, from, step):
				if not actor.is_conscious():
					break
				if not hostile.can_react():
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


## Stands up: spends half the speed and ends prone.
func _stand(actor: Combatant) -> void:
	actor.movement_remaining = maxi(0, actor.movement_remaining - stand_cost(actor))
	_end_conditions_named(actor, Conditions.PRONE)


func _dash(actor: Combatant) -> void:
	actor.movement_remaining += actor.speed_tiles()
	_emit("dash", {"actor": actor.id})


func _dodge(actor: Combatant) -> void:
	actor.dodging = true
	_emit("dodge", {"actor": actor.id})


func _disengage(actor: Combatant) -> void:
	actor.disengaging = true
	_emit("disengage", {"actor": actor.id})


## Conscious hostiles able to react that `from` is in reach of and `to` is not
## (initiative order).
func _opportunity_attackers(mover: Combatant, from: Vector2i, to: Vector2i) -> Array[Combatant]:
	var out: Array[Combatant] = []
	for h in tracker.order():
		if h.team == mover.team or not h.can_react() or _usable_melee_index(h) < 0:
			continue
		if GridMath.is_adjacent(h.position, from) and not GridMath.is_adjacent(h.position, to):
			out.append(h)
	return out


## First melee attack whose weapon item is still carried, or -1.
func _usable_melee_index(c: Combatant) -> int:
	for i in range(c.attacks.size()):
		var attack: Dictionary = c.attacks[i]
		if Encounter.is_ranged_attack(attack) or attack.get("off_hand", false) == true:
			continue
		var item := str(attack.get("item", ""))
		if item.is_empty() or c.sheet.has_item(item):
			return i
	return -1


# --- attacks ---------------------------------------------------------------------

func _do_attack(actor: Combatant, intent: Dictionary) -> void:
	var target := _attack_target(actor, intent)
	var index := DictUtil.to_int(intent.get("attack_index", 0), 0)
	var bonus := DictUtil.to_bool(intent.get("bonus", false), false)
	var opts := {}
	if bonus:
		var source := _bonus_attack_source(actor, actor.attacks[index])
		opts["bonus_source"] = source
		if actor.bonus_attacks_remaining > 0:
			actor.bonus_attacks_remaining -= 1
		else:
			actor.bonus_action_used = true
	elif actor.action_used:
		actor.attacks_remaining -= 1
	else:
		actor.action_used = true
		actor.attack_action_taken = true
		actor.attacks_remaining = actor.attacks_per_action - 1
	if DictUtil.to_bool(intent.get("reckless", false), false):
		actor.reckless = true
		_emit("effect_applied", {"source": actor.id, "target": actor.id, "effect": "reckless_attack"})
	for key: String in ["smite", "stun", "technique"]:
		if intent.has(key):
			opts[key] = intent[key]
	_resolve_attack(actor, target, index, bonus, opts)


## Rolls one weapon attack and emits attack (+ damage on a hit), then uses up
## a thrown weapon / ammunition.
func _resolve_attack(attacker: Combatant, target: Combatant, attack_index: int, bonus: bool = false, opts: Dictionary = {}) -> AttackResult:
	var attack: Dictionary = attacker.attacks[attack_index]
	return _roll_attack(attacker, target, attack, bonus, null, opts)


## Advantage / disadvantage and auto-critical of an attack (SRD conditions).
## Advantage: target unconscious, marked by Guiding Bolt, stunned, paralyzed,
## restrained or blinded, prone with an adjacent attacker, or attacking
## recklessly (either side); the attacker's own Reckless Attack (melee STR).
## Disadvantage: target dodging, prone and the attacker not adjacent; attacker
## under Vicious Mockery, prone, poisoned, restrained, blinded, or frightened
## with a source in sight; ranged attacks beyond normal range or with a hostile
## adjacent. A hit from an adjacent attacker on an unconscious or paralyzed
## target is critical.
func _attack_mode(attacker: Combatant, target: Combatant, attack: Dictionary, weapon: bool) -> Dictionary:
	var ranged := Encounter.is_ranged_attack(attack)
	var adjacent := GridMath.is_adjacent(attacker.position, target.position)
	var target_down := target.sheet.is_unconscious()
	var advantage := target_down or not target.guided_by.is_empty() or target.reckless
	var disadvantage := (target.dodging and target.is_conscious() and not target.is_incapacitated()) or attacker.mocked
	for c in Conditions.TARGET_ADVANTAGE:
		if target.has_condition(c):
			advantage = true
	if target.has_condition(Conditions.PRONE):
		if adjacent:
			advantage = true
		else:
			disadvantage = true
	for c in Conditions.ATTACKER_DISADVANTAGE:
		if attacker.has_condition(c):
			disadvantage = true
	if _frightened_in_sight(attacker):
		disadvantage = true
	if attacker.reckless and weapon and not ranged and str(attack.get("ability", "STR")) == "STR":
		advantage = true
	if ranged and (GridMath.distance_tiles(attacker.position, target.position) > Encounter.attack_range_tiles(attack)[0] or _hostile_adjacent(attacker)):
		disadvantage = true
	var auto_crit := adjacent and (target_down or target.has_condition(Conditions.PARALYZED))
	return {"mode": D20.combine(advantage, disadvantage), "auto_crit": auto_crit}


## Frightened with a source in line of sight (or of an unknown source).
func _frightened_in_sight(c: Combatant) -> bool:
	if not c.has_condition(Conditions.FRIGHTENED):
		return false
	var sources := c.condition_sources(Conditions.FRIGHTENED)
	if sources.is_empty():
		return true
	for src_id in sources:
		var src := get_combatant(src_id)
		if src != null and src.is_alive() and walk_map.has_line_of_sight(c.position, src.position):
			return true
	return false


## The shared attack roll for weapons and spell attacks (see _attack_mode).
## Bardic Inspiration adds its die to the roll, Sacred Weapon its bonus; Rage,
## Hex, Sneak Attack, Colossus Slayer and Divine Smite add damage (AttackResolver
## extras). Improved Critical crits on 19-20. A hit may be reduced by the
## target's reaction (Deflect Missiles, Uncanny Dodge: damage_reduced). opts:
## {"bonus_source", "smite", "stun", "technique"}.
func _roll_attack(attacker: Combatant, target: Combatant, attack: Dictionary, bonus: bool, spell: SpellDefinition, opts: Dictionary = {}) -> AttackResult:
	var kind := str(attack.get("kind", "melee"))
	var weapon := spell == null
	var ranged := Encounter.is_ranged_attack(attack)
	var m := _attack_mode(attacker, target, attack, weapon)
	var mode: D20.RollMode = m["mode"]
	var extra_to_hit := 0
	if attacker.inspiration_die > 0:
		extra_to_hit = rng.next_int(1, attacker.inspiration_die)
		_emit("inspiration_used", {"actor": attacker.id, "source": attacker.inspiration_source, "die": attacker.inspiration_die, "roll": extra_to_hit})
		attacker.inspiration_die = 0
		attacker.inspiration_source = ""
	if weapon:
		extra_to_hit += attacker.sacred_weapon_bonus
	var damage_type := str(attack.get("damage_type", ""))
	var extras: Array[Dictionary] = []
	if weapon and attacker.raging and not ranged and str(attack.get("ability", "STR")) == "STR":
		extras.append({"source": "rage", "dice": str(Encounter.rage_damage(attacker.sheet)), "type": damage_type})
	if target.marks.has(attacker.id):
		var mark: Dictionary = target.marks[attacker.id]
		extras.append({"source": str(mark.get("effect", "")), "dice": str(mark.get("dice", "1d6")), "type": str(mark.get("type", ""))})
	var sneak := false
	if weapon and attacker.sheet.has_feature(ClassDefinition.FEATURE_SNEAK_ATTACK) and attacker.sneak_attack_turn != turn_counter:
		var props: Array = attack.get("properties", [])
		if props.has("finesse") or kind == "ranged":
			if mode == D20.RollMode.ADVANTAGE or (mode != D20.RollMode.DISADVANTAGE and _ally_adjacent_to(target, attacker)):
				sneak = true
				extras.append({"source": "sneak_attack", "dice": attacker.sheet.sneak_attack_dice(), "type": damage_type})
	var colossus := false
	if weapon and attacker.sheet.has_feature("colossus_slayer") and attacker.colossus_turn != turn_counter \
			and target.sheet.current_hp < target.sheet.max_hp:
		colossus = true
		extras.append({"source": "colossus_slayer", "dice": "1d8", "type": damage_type})
	var smite := DictUtil.to_int(opts.get("smite", 0), 0)
	if weapon and smite > 0:
		var dice := mini(SMITE_MAX_DICE, 1 + smite)
		if target.creature_type in ["undead", "fiend"]:
			dice += 1
		extras.append({"source": "divine_smite", "dice": "%dd8" % dice, "type": "radiant"})
	var half_on_miss := spell != null and spell.half_on_miss
	var crit_min := 19 if weapon and attacker.sheet.has_feature("improved_critical") else 20
	var auto_crit: bool = m["auto_crit"]
	var r := AttackResolver.roll(attacker, target, attack, rng, mode, auto_crit, extra_to_hit, extras, half_on_miss, crit_min)
	if sneak and r.hit:
		attacker.sneak_attack_turn = turn_counter
	if colossus and r.hit:
		attacker.colossus_turn = turn_counter
	target.guided_by = ""
	target.guided_turns_left = 0
	attacker.mocked = false
	var consumed := ""
	if weapon:
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
	if bonus and opts.has("bonus_source"):
		ev["bonus_source"] = str(opts["bonus_source"])
	_emit("attack", ev)
	if r.hit or r.damage_total > 0:
		var amount := r.damage_total
		if r.hit and amount > 0:
			amount = _reaction_reduction(attacker, target, weapon, ranged, amount)
		AttackResolver.apply_damage(r, target, amount)
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
		_after_damage(attacker, target, r.damage_total, r.target_dropped)
	if not target.is_conscious():
		target.dodging = false
	if weapon and smite > 0 and r.hit:
		attacker.sheet.use_spell_slot(smite)
		_emit("feature_used", {"actor": attacker.id, "feature": "divine_smite", "target": target.id, "remaining": attacker.sheet.slots_left(smite)})
	if weapon and r.hit and target.is_alive():
		if DictUtil.to_bool(opts.get("stun", false), false):
			_stunning_strike(attacker, target)
		var technique := str(opts.get("technique", ""))
		if not technique.is_empty() and target.is_alive():
			_open_hand_technique(attacker, target, technique)
	return r


## SRD rage damage bonus (+2, +3 at 9, +4 at 16; class table "rage_damage").
static func rage_damage(sheet: CharacterSheet) -> int:
	var fallback := 4 if sheet.level >= 16 else (3 if sheet.level >= 9 else RAGE_DAMAGE)
	return sheet.table_int("rage_damage", fallback)


## Reactions that reduce a hit's damage, used automatically when the target
## can react: Deflect Missiles (ranged weapon attacks: 1d10 + DEX + monk level)
## and Uncanny Dodge (an attacker it can see: half the damage). Emits
## damage_reduced {actor, feature, source, amount}. Returns the new damage.
func _reaction_reduction(attacker: Combatant, target: Combatant, weapon: bool, ranged: bool, amount: int) -> int:
	if not target.can_react():
		return amount
	var feature := ""
	var reduced := 0
	if weapon and ranged and target.sheet.has_feature("deflect_missiles"):
		feature = "deflect_missiles"
		reduced = rng.next_int(1, 10) + target.sheet.ability_modifier(Ability.Type.DEX) + target.sheet.level
	elif target.sheet.has_feature("uncanny_dodge") and not target.has_condition(Conditions.BLINDED):
		feature = "uncanny_dodge"
		reduced = amount - floori(amount / 2.0)
	if feature.is_empty():
		return amount
	reduced = clampi(reduced, 0, amount)
	target.reaction_used = true
	_emit("damage_reduced", {"actor": target.id, "feature": feature, "source": attacker.id, "amount": reduced})
	return amount - reduced


## Stunning Strike: 1 ki; the target makes a CON save or is stunned until the
## end of the monk's next turn.
func _stunning_strike(monk: Combatant, target: Combatant) -> void:
	monk.sheet.spend_class_resource("ki", 1)
	_emit("feature_used", {"actor": monk.id, "feature": "stunning_strike", "target": target.id, "remaining": monk.sheet.class_resource("ki")})
	if not _saving_throw(monk.id, target, Ability.Type.CON, Encounter.ki_save_dc(monk.sheet)):
		_apply_condition(target, Conditions.STUNNED, monk.id, Conditions.duration(Conditions.DURATION_SOURCE_NEXT_TURN))


## Ki save DC: 8 + proficiency + WIS.
static func ki_save_dc(sheet: CharacterSheet) -> int:
	return 8 + sheet.proficiency_bonus() + sheet.ability_modifier(Ability.Type.WIS)


## Open Hand Technique after a Flurry of Blows hit: "prone" (DEX save or
## prone), "push" (STR save or pushed up to 3 tiles away), "no_reactions" (no
## reactions until the end of the monk's next turn).
func _open_hand_technique(monk: Combatant, target: Combatant, technique: String) -> void:
	_emit("feature_used", {"actor": monk.id, "feature": "open_hand_technique", "target": target.id, "remaining": 0, "mode": technique})
	var dc := Encounter.ki_save_dc(monk.sheet)
	match technique:
		"prone":
			if not _saving_throw(monk.id, target, Ability.Type.DEX, dc):
				_apply_condition(target, Conditions.PRONE, monk.id, Conditions.duration(Conditions.DURATION_ENCOUNTER))
		"push":
			if not _saving_throw(monk.id, target, Ability.Type.STR, dc):
				_push(monk, target, OPEN_HAND_PUSH_TILES)
		"no_reactions":
			_apply_condition(target, Conditions.NO_REACTIONS, monk.id, Conditions.duration(Conditions.DURATION_SOURCE_NEXT_TURN))


## Pushes target up to `tiles` tiles straight away from source, stopping at a
## wall, an occupied tile or a corner. Emits pushed {target, source, from, to}
## when it moved.
func _push(source: Combatant, target: Combatant, tiles: int) -> void:
	var delta := target.position - source.position
	var dir := Vector2i(signi(delta.x), signi(delta.y))
	if dir == Vector2i.ZERO:
		return
	var from := target.position
	var occupied := occupied_cells(target.id)
	for _i in range(tiles):
		var next := target.position + dir
		if not region.has_point(next) or not walk_map.can_step(target.position, next, occupied):
			break
		target.position = next
	if target.position != from:
		_emit("pushed", {"target": target.id, "source": source.id, "from": GridMath.vec_to_arr(from), "to": GridMath.vec_to_arr(target.position)})


# --- damage pipeline, conditions and concentration -------------------------------

## After damage to target (amount already applied): Turn Undead's turning ends,
## concentration is checked (CON save DC max(10, damage / 2)) or ends at 0 hp,
## and Dark One's Blessing gives the source temporary hit points when it
## dropped a hostile to 0.
func _after_damage(source: Combatant, target: Combatant, amount: int, dropped: bool) -> void:
	if amount <= 0 and not dropped:
		return
	for entry: Dictionary in target.conditions.duplicate():
		if entry.get("ends_on_damage", false) == true:
			_remove_condition(target, entry)
	if not target.concentration.is_empty():
		if not target.is_conscious():
			_end_concentration(target, "unconscious")
		elif amount > 0:
			_concentration_check(target, amount)
	if dropped and source != null and source.team != target.team and source.is_conscious() \
			and source.sheet.has_feature("dark_ones_blessing"):
		var temp := maxi(1, source.sheet.ability_modifier(Ability.Type.CHA) + source.sheet.level)
		source.sheet.grant_temp_hp(temp)
		_emit("temp_hp", {"source": source.id, "target": source.id, "amount": temp, "temp_hp_after": source.sheet.temp_hp, "feature": "dark_ones_blessing"})


func _concentration_check(c: Combatant, damage: int) -> void:
	var dc := maxi(10, floori(damage / 2.0))
	var d := D20.roll(rng)
	var total := d.natural + c.sheet.save_modifier(Ability.Type.CON)
	var success := total >= dc
	_emit("concentration_check", {"actor": c.id, "spell": str(c.concentration.get("spell", "")), "dc": dc, "natural": d.natural, "total": total, "success": success})
	if not success:
		_end_concentration(c, "damage")


## Starts concentrating on spell (ending any earlier concentration first).
func _start_concentration(c: Combatant, spell: SpellDefinition, slot: int) -> void:
	_end_concentration(c, "new_spell")
	c.concentration = {"spell": spell.id, "slot_level": slot}
	_emit("concentration_started", {"actor": c.id, "spell": spell.id})


## Ends c's concentration ("new_spell", "damage", "unconscious",
## "incapacitated"): emits concentration_ended {actor, spell, reason} and ends
## the conditions and marks that spell put on anyone.
func _end_concentration(c: Combatant, reason: String) -> void:
	if c.concentration.is_empty():
		return
	var spell_id := str(c.concentration.get("spell", ""))
	c.concentration = {}
	_emit("concentration_ended", {"actor": c.id, "spell": spell_id, "reason": reason})
	for other in tracker.order():
		for entry: Dictionary in other.conditions.duplicate():
			if str(entry.get("source", "")) == c.id and str(entry.get("spell", "")) == spell_id:
				_remove_condition(other, entry)
		if other.marks.has(c.id):
			var mark: Dictionary = other.marks[c.id]
			if str(mark.get("spell", "")) == spell_id:
				other.marks.erase(c.id)
				_emit("effect_ended", {"target": other.id, "effect": str(mark.get("effect", ""))})


## Applies a condition (Conditions) with a duration; extra fields (spell, flee,
## ends_on_damage) are stored on the entry. A creature immune to it, or dead,
## is unaffected (false). The same condition from the same source is replaced.
## Emits condition_applied {target, condition, source, duration}.
func _apply_condition(target: Combatant, condition: String, source_id: String, duration: Dictionary, extra: Dictionary = {}) -> bool:
	if not target.is_alive() or target.is_immune_to_condition(condition) or duration.is_empty():
		return false
	for entry: Dictionary in target.conditions.duplicate():
		if str(entry.get("condition", "")) == condition and str(entry.get("source", "")) == source_id:
			_remove_entry(target, entry)
	var turns := 0
	match str(duration.get("type", "")):
		Conditions.DURATION_SOURCE_NEXT_TURN:
			var current := current_actor()
			turns = 2 if current != null and current.id == source_id else 1
		Conditions.DURATION_TARGET_TURN_END:
			turns = 1
		Conditions.DURATION_ROUNDS:
			turns = DictUtil.to_int(duration.get("rounds", 1), 1)
	var entry := {"condition": condition, "source": source_id, "duration": duration.duplicate(), "turns_left": turns}
	entry.merge(extra)
	target.conditions.append(entry)
	_emit("condition_applied", {"target": target.id, "condition": condition, "source": source_id, "duration": duration.duplicate()})
	if Conditions.INCAPACITATING.has(condition):
		target.dodging = false
		_end_concentration(target, "incapacitated")
	if Conditions.IMMOBILIZING.has(condition):
		target.movement_remaining = 0
	return true


## Removes one entry and emits condition_ended {target, condition}.
func _remove_condition(target: Combatant, entry: Dictionary) -> void:
	if _remove_entry(target, entry):
		_emit("condition_ended", {"target": target.id, "condition": str(entry.get("condition", ""))})


func _remove_entry(target: Combatant, entry: Dictionary) -> bool:
	for i in range(target.conditions.size()):
		if is_same(target.conditions[i], entry):
			target.conditions.remove_at(i)
			return true
	return false


## Ends every entry of a condition on c (and the sheet's lasting one).
func _end_conditions_named(c: Combatant, condition: String) -> void:
	for entry: Dictionary in c.conditions.duplicate():
		if str(entry.get("condition", "")) == condition:
			_remove_condition(c, entry)
	if c.sheet.conditions.has(condition):
		c.sheet.conditions.erase(condition)
		_emit("condition_ended", {"target": c.id, "condition": condition})


# --- spells ---------------------------------------------------------------------

func _do_cast(actor: Combatant, intent: Dictionary) -> void:
	var spell := _spell_def(str(intent.get("spell", "")))
	var slot := _cast_slot(actor, spell, intent)
	var meta := Encounter._metamagic_of(intent)
	if slot > 0:
		actor.sheet.use_spell_slot(slot)
	if not meta.is_empty():
		actor.sheet.spend_class_resource("sorcery_points", Encounter._metamagic_cost(meta, spell))
	if spell.uses_bonus_action() or meta.has("quickened_spell"):
		actor.bonus_action_used = true
	else:
		actor.action_used = true
	var cast_ev := {"actor": actor.id, "spell": spell.id, "target": "" if spell.is_area() else _cast_target(actor, intent).id, "slot_level": slot}
	if spell.is_area():
		cast_ev["point"] = GridMath.vec_to_arr(_area_point(actor, spell, intent))
	if not meta.is_empty():
		cast_ev["metamagic"] = meta.duplicate()
	_emit("cast", cast_ev)
	if spell.concentration:
		_start_concentration(actor, spell, slot)
	var empower := maxi(1, actor.sheet.ability_modifier(Ability.Type.CHA)) if meta.has("empowered_spell") else 0
	if spell.is_area():
		_cast_area(actor, spell, slot, intent, empower)
		return
	_cast_single(actor, _cast_target(actor, intent), spell, slot, empower)
	if meta.has("twinned_spell"):
		var twin := get_combatant(str(intent.get("twin_target", "")))
		if twin != null and twin.is_alive():
			_cast_single(actor, twin, spell, slot, empower)


## Resolves a single-target spell on target.
func _cast_single(actor: Combatant, target: Combatant, spell: SpellDefinition, slot: int, empower: int) -> void:
	var above := maxi(0, slot - spell.level)
	match spell.effect_type:
		SpellDefinition.EFFECT_SPELL_ATTACK:
			var attack := _spell_attack(actor, spell, slot, empower)
			for _i in range(spell.rays_for(actor.sheet.level, slot)):
				if not target.is_alive():
					break
				var r := _roll_attack(actor, target, attack, false, spell)
				if r.hit and target.is_alive():
					_apply_rider(actor, target, spell)
					_spell_condition(actor, target, spell, false)
					if spell.id == "eldritch_blast" and actor.sheet.invocations.has("repelling_blast"):
						_push(actor, target, REPELLING_BLAST_TILES)
		SpellDefinition.EFFECT_AUTO_HIT:
			var darts := spell.darts + spell.per_slot_darts * above
			var formula := DiceFormula.parse(spell.damage)
			var total := 0
			for _i in range(darts):
				total += target.adjust_damage(maxi(0, DictUtil.to_int(formula.roll(rng, actor.sheet.casting_modifier())["total"])), spell.damage_type)
			_deal_spell_damage(actor, target, total, spell, {"darts": darts})
		SpellDefinition.EFFECT_SAVE:
			var success := _saving_throw(actor.id, target, spell.save_ability, actor.sheet.spell_save_dc())
			if not spell.damage.is_empty() and (not success or spell.on_save == "half"):
				var rolled := _roll_spell_damage(actor, spell, slot, empower)
				if success:
					rolled = floori(rolled / 2.0)
				_deal_spell_damage(actor, target, target.adjust_damage(rolled, spell.damage_type), spell, {})
			if not success and target.is_alive():
				_apply_rider(actor, target, spell)
				_spell_condition(actor, target, spell, true)
		SpellDefinition.EFFECT_HEAL:
			var hf := spell.heal_formula(slot)
			var amount := maxi(0, DictUtil.to_int(DiceFormula.parse(str(hf["formula"])).roll(rng, actor.sheet.casting_modifier())["total"]))
			if hf["add_mod"] == true:
				amount += actor.sheet.casting_modifier()
			if spell.level >= 1 and actor.sheet.has_feature("disciple_of_life"):
				amount += 2 + slot
			_heal(actor.id, target, maxi(0, amount))
		SpellDefinition.EFFECT_BUFF:
			if spell.buff == SpellDefinition.BUFF_MAGE_ARMOR:
				if not target.sheet.active_buffs.has(SpellDefinition.BUFF_MAGE_ARMOR):
					target.sheet.active_buffs.append(SpellDefinition.BUFF_MAGE_ARMOR)
				_emit("effect_applied", {"source": actor.id, "target": target.id, "effect": SpellDefinition.BUFF_MAGE_ARMOR, "ac": target.sheet.armor_class()})
			elif not spell.condition.is_empty():
				_spell_condition(actor, target, spell, false)
			else:
				_apply_rider(actor, target, spell)
		SpellDefinition.EFFECT_MARK:
			var mark := {"effect": spell.rider, "dice": spell.damage, "type": spell.damage_type}
			if spell.concentration:
				mark["spell"] = spell.id
			target.marks[actor.id] = mark
			_emit("effect_applied", {"source": actor.id, "target": target.id, "effect": spell.rider})


## The attack dictionary of a spell attack (Agonizing Blast adds CHA to
## eldritch blast's damage; Empowered Spell rerolls low dice).
func _spell_attack(actor: Combatant, spell: SpellDefinition, slot: int, empower: int) -> Dictionary:
	var tiles := maxi(1, spell.range_tiles())
	var damage := spell.damage_formula(actor.sheet.level, slot)
	if spell.id == "eldritch_blast" and actor.sheet.invocations.has("agonizing_blast"):
		var cha := actor.sheet.ability_modifier(Ability.Type.CHA)
		if cha != 0:
			damage += CharacterBuilder.signed(cha)
	var attack := {
		"name": spell.display_name,
		"kind": "spell",
		"melee": spell.melee,
		"to_hit": actor.sheet.spell_attack_bonus(),
		"damage": damage,
		"damage_type": spell.damage_type,
		"range_tiles": [tiles, tiles],
	}
	if empower > 0:
		attack["empower"] = empower
	return attack


## Rolls a spell's damage formula at slot (MOD = casting modifier).
func _roll_spell_damage(actor: Combatant, spell: SpellDefinition, slot: int, empower: int) -> int:
	var formula := DiceFormula.parse(spell.damage_formula(actor.sheet.level, slot))
	return maxi(0, DictUtil.to_int(formula.roll(rng, actor.sheet.casting_modifier(), false, 0, empower)["total"]))


## Applies the spell's condition (if any). Default duration: save_ends with the
## spell's save and the caster's DC for save spells, else 10 rounds. Tied to
## the caster's concentration when the spell needs it.
func _spell_condition(actor: Combatant, target: Combatant, spell: SpellDefinition, from_save: bool) -> void:
	if spell.condition.is_empty() or not target.is_alive():
		return
	var duration := spell.condition_duration.duplicate()
	if duration.is_empty():
		duration = {"type": Conditions.DURATION_SAVE_ENDS} if from_save and spell.save_ability >= 0 else Conditions.duration(Conditions.DURATION_ROUNDS, {"rounds": SpellDefinition.DEFAULT_CONDITION_ROUNDS})
	if str(duration.get("type", "")) == Conditions.DURATION_SAVE_ENDS and not duration.has("ability"):
		if spell.save_ability < 0:
			duration = Conditions.duration(Conditions.DURATION_ROUNDS, {"rounds": SpellDefinition.DEFAULT_CONDITION_ROUNDS})
		else:
			duration = Conditions.duration(Conditions.DURATION_SAVE_ENDS, {"ability": Ability.abbreviation(spell.save_ability), "dc": actor.sheet.spell_save_dc()})
	var extra := {"spell": spell.id} if spell.concentration else {}
	_apply_condition(target, spell.condition, actor.id, duration, extra)


## Area spells: every living creature (any team) on a covered tile, the caster
## excluded from its own self-centred areas. Emits area_effect {caster, spell,
## point, shape, size_tiles, affected, sculpted}; then per creature a save (+
## damage) or an attack. Sculpted allies (Sculpt Spells) are left out entirely.
## Damage of an area save is rolled once for all targets.
func _cast_area(actor: Combatant, spell: SpellDefinition, slot: int, intent: Dictionary, empower: int) -> void:
	var point := _area_point(actor, spell, intent)
	var size := spell.area_size_tiles()
	var covered := AreaOfEffect.tiles(spell.area_shape, size, actor.position, point, walk_map)
	var sculpt := DictUtil.to_string_array(intent.get("sculpt", []))
	var affected: Array[Combatant] = []
	var affected_ids: Array = []
	var sculpted: Array = []
	for c in tracker.order():
		if not c.is_alive() or not covered.has(c.position):
			continue
		if c == actor and Encounter._self_centred(spell):
			continue
		if sculpt.has(c.id):
			sculpted.append(c.id)
			continue
		affected.append(c)
		affected_ids.append(c.id)
	_emit("area_effect", {
		"caster": actor.id, "spell": spell.id, "point": GridMath.vec_to_arr(point), "shape": spell.area_shape,
		"size_tiles": size, "affected": affected_ids, "sculpted": sculpted,
	})
	if spell.effect_type == SpellDefinition.EFFECT_AREA_ATTACK:
		var attack := _spell_attack(actor, spell, slot, empower)
		attack["range_tiles"] = [999, 999]
		for t in affected:
			if t.is_alive():
				var r := _roll_attack(actor, t, attack, false, spell)
				if r.hit and t.is_alive():
					_spell_condition(actor, t, spell, false)
		return
	var rolled := 0
	if not spell.damage.is_empty():
		rolled = _roll_spell_damage(actor, spell, slot, empower)
	for t in affected:
		if not t.is_alive():
			continue
		var success := _saving_throw(actor.id, t, spell.save_ability, actor.sheet.spell_save_dc())
		if not spell.damage.is_empty() and (not success or spell.on_save == "half"):
			var amount := floori(rolled / 2.0) if success else rolled
			_deal_spell_damage(actor, t, t.adjust_damage(amount, spell.damage_type), spell, {})
		if not success and t.is_alive():
			_spell_condition(actor, t, spell, true)
			if spell.push_tiles > 0:
				_push(actor, t, spell.push_tiles)


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
			var mark := {"effect": SpellDefinition.RIDER_HEX, "dice": "1d6", "type": "necrotic"}
			if spell.concentration:
				mark["spell"] = spell.id
			target.marks[caster.id] = mark
		_:
			return
	_emit("effect_applied", {"source": caster.id, "target": target.id, "effect": spell.rider})


## Rolls target's saving throw against dc and emits save {actor (the source),
## target, ability, dc, natural, total, success}. Automatic failure (natural 0,
## total 0) on STR / DEX saves while unconscious, stunned or paralyzed.
## Advantage on DEX saves: dodging, or Danger Sense (not blinded or
## incapacitated). Disadvantage on DEX saves while restrained. The event gets
## "advantage" ("advantage" / "disadvantage") only when the roll was not normal.
func _saving_throw(source_id: String, target: Combatant, ability: int, dc: int) -> bool:
	var natural := 0
	var total := 0
	var success := false
	var mode := D20.RollMode.NORMAL
	var physical := ability == Ability.Type.STR or ability == Ability.Type.DEX
	if physical and (target.sheet.is_unconscious() or target.loses_turn()):
		success = false
	else:
		var dex := ability == Ability.Type.DEX
		var advantage := dex and (target.dodging or (target.sheet.has_feature("danger_sense") \
				and not target.has_condition(Conditions.BLINDED) and not target.is_incapacitated()))
		var disadvantage := dex and target.has_condition(Conditions.RESTRAINED)
		mode = D20.combine(advantage, disadvantage)
		var d := D20.roll(rng, mode)
		natural = d.natural
		total = d.natural + target.sheet.save_modifier(ability)
		success = total >= dc
	var ev := {
		"actor": source_id,
		"target": target.id,
		"ability": Ability.abbreviation(ability),
		"dc": dc,
		"natural": natural,
		"total": total,
		"success": success,
	}
	if mode != D20.RollMode.NORMAL:
		ev["advantage"] = Encounter._mode_name(mode)
	_emit("save", ev)
	return success


## Applies already-adjusted spell damage and emits damage (+ "spell" and extras).
func _deal_spell_damage(source: Combatant, target: Combatant, amount: int, spell: SpellDefinition, fields: Dictionary) -> void:
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
	_after_damage(source, target, outcome.amount, outcome.dropped_to_zero)
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
	if Encounter._item_uses_bonus(actor, item, intent):
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
				_end_conditions_named(actor, condition)


# --- class features ---------------------------------------------------------------

func _do_feature(actor: Combatant, intent: Dictionary) -> void:
	var feature := str(intent.get("feature", ""))
	var target := actor
	var resource := Encounter._feature_resource(feature)
	var spend := 1
	match Encounter._feature_cost(feature):
		"action":
			actor.action_used = true
		"bonus":
			actor.bonus_action_used = true
	match feature:
		ClassDefinition.FEATURE_LAY_ON_HANDS:
			target = _cast_target(actor, intent)
			spend = DictUtil.to_int(intent.get("amount", 0), 0)
		ClassDefinition.FEATURE_BARDIC_INSPIRATION:
			target = _cast_target(actor, intent)
		"font_of_magic", "cunning_action", "pact_weapon":
			spend = 0
	if spend > 0 and not resource.is_empty():
		actor.sheet.spend_class_resource(resource, spend)
	var used := {"actor": actor.id, "feature": feature, "target": target.id, "remaining": actor.sheet.class_resource(resource) if not resource.is_empty() else 0}
	if intent.has("mode"):
		used["mode"] = str(intent["mode"])
	if feature != "font_of_magic":
		_emit("feature_used", used)
	match feature:
		ClassDefinition.FEATURE_SECOND_WIND:
			var amount := maxi(0, DiceExpr.parse("1d10").roll(rng).total) + actor.sheet.level
			_heal(actor.id, actor, amount)
		ClassDefinition.FEATURE_RAGE:
			actor.raging = true
			actor.rage_started_round = tracker.round_number
			actor.rage_started_turn = turn_counter
			_end_concentration(actor, "rage")
			_emit("effect_applied", {"source": actor.id, "target": actor.id, "effect": "rage"})
			if DictUtil.to_bool(intent.get("frenzy", false), false):
				actor.frenzied = true
				_emit("effect_applied", {"source": actor.id, "target": actor.id, "effect": "frenzy"})
		ClassDefinition.FEATURE_LAY_ON_HANDS:
			_heal(actor.id, target, spend)
		ClassDefinition.FEATURE_BARDIC_INSPIRATION:
			target.inspiration_die = actor.sheet.bardic_inspiration_die()
			target.inspiration_source = actor.id
			_emit("effect_applied", {"source": actor.id, "target": target.id, "effect": "bardic_inspiration", "die": target.inspiration_die})
		"action_surge":
			actor.action_surged = true
			actor.action_used = false
			actor.attacks_remaining = 0
		"flurry_of_blows":
			actor.bonus_attacks_remaining = 2
			actor.bonus_attack_source = "flurry_of_blows"
		"patient_defense":
			_dodge(actor)
		"step_of_the_wind", "cunning_action":
			if str(intent.get("mode", "")) == "dash":
				_dash(actor)
			else:
				_disengage(actor)
		"turn_undead":
			_turn(actor, ["undead"], feature)
		"turn_the_unholy":
			_turn(actor, ["undead", "fiend"], feature)
		"preserve_life":
			var alloc: Dictionary = intent["allocations"]
			var ids: Array = alloc.keys()
			ids.sort()
			for key: Variant in ids:
				_heal(actor.id, get_combatant(str(key)), DictUtil.to_int(alloc[key], 0))
		"sacred_weapon":
			actor.sacred_weapon_bonus = maxi(1, actor.sheet.ability_modifier(Ability.Type.CHA))
			actor.sacred_weapon_turns = SACRED_WEAPON_ROUNDS
			_emit("effect_applied", {"source": actor.id, "target": actor.id, "effect": "sacred_weapon", "bonus": actor.sacred_weapon_bonus})
		"font_of_magic":
			_font_of_magic(actor, intent, used)
		"pact_weapon":
			actor.pact_weapon = true
			actor.attacks.append(Encounter.pact_weapon_attack(actor.sheet))
			_emit("effect_applied", {"source": actor.id, "target": actor.id, "effect": "pact_weapon", "attack_index": actor.attacks.size() - 1})


## Turn Undead / Turn the Unholy: each creature of the types within 6 tiles in
## line of sight makes a WIS save against the turner's spell save DC; on a
## failure it is turned for 10 rounds (frightened of the turner, must move
## away, may only Dash or Dodge; ends when it takes damage). Destroy Undead:
## an undead of challenge rating up to the table's value is destroyed instead
## (emits destroyed {source, target, feature}).
func _turn(actor: Combatant, types: Array[String], feature: String) -> void:
	var dc := actor.sheet.spell_save_dc()
	var max_cr := -1.0
	if actor.sheet.has_feature("destroy_undead"):
		max_cr = Encounter.destroy_undead_cr(actor.sheet)
	for h in hostiles_of(actor):
		if not h.is_conscious() or not types.has(h.creature_type):
			continue
		if GridMath.distance_tiles(actor.position, h.position) > CHANNEL_DIVINITY_RANGE_TILES:
			continue
		if not walk_map.has_line_of_sight(actor.position, h.position):
			continue
		if _saving_throw(actor.id, h, Ability.Type.WIS, dc):
			continue
		if h.creature_type == "undead" and max_cr >= 0.0 and h.challenge_rating <= max_cr:
			h.sheet.kill()
			_emit("destroyed", {"source": actor.id, "target": h.id, "feature": "destroy_undead"})
			continue
		_apply_condition(h, Conditions.FRIGHTENED, actor.id, Conditions.duration(Conditions.DURATION_ROUNDS, {"rounds": TURNED_ROUNDS}),
				{"flee": true, "ends_on_damage": true, "feature": feature})


## Destroy Undead's challenge rating limit (class table "destroy_undead_cr").
static func destroy_undead_cr(sheet: CharacterSheet) -> float:
	var cls := sheet.class_definition()
	if cls != null and cls.tables.has("destroy_undead_cr"):
		var v: Variant = cls.table_raw("destroy_undead_cr", sheet.level)
		if DictUtil.is_number(v):
			var cr := DictUtil.to_float(v, -1.0)
			return cr if cr > 0.0 else -1.0
	return Progression.destroy_undead_cr(sheet.level)


## Font of Magic: "create_slot" (spend sorcery points for a slot of level 1..5)
## or "convert_slot" (spend a slot, gain points equal to its level, up to the
## maximum). Emits feature_used with mode, slot_level and remaining points.
func _font_of_magic(actor: Combatant, intent: Dictionary, used: Dictionary) -> void:
	var slot := DictUtil.to_int(intent.get("slot_level", 0), 0)
	var s := actor.sheet
	if str(intent.get("mode", "")) == "create_slot":
		s.spend_class_resource("sorcery_points", _slot_creation_cost(actor, slot))
		while s.spell_slots.size() < slot:
			s.spell_slots.append(0)
		while s.spell_slots_max.size() < slot:
			s.spell_slots_max.append(0)
		s.spell_slots[slot - 1] += 1
	else:
		s.use_spell_slot(slot)
		s.class_resources["sorcery_points"] = mini(s.resource_max("sorcery_points"), s.class_resource("sorcery_points") + slot)
	used["remaining"] = s.class_resource("sorcery_points")
	used["slot_level"] = slot
	_emit("feature_used", used)


## Pact of the Blade weapon: a proficient longsword-like melee attack (1d8
## slashing + STR).
static func pact_weapon_attack(sheet: CharacterSheet) -> Dictionary:
	var str_mod := sheet.ability_modifier(Ability.Type.STR)
	return {
		"name": "Pact Weapon",
		"kind": "melee",
		"to_hit": sheet.proficiency_bonus() + str_mod,
		"damage": "1d8" + CharacterBuilder.signed(str_mod),
		"damage_type": "slashing",
		"ability": "STR",
		"properties": ["versatile"],
		"range_tiles": [1, 1],
		"proficient": true,
		"pact_weapon": true,
	}


## SRD Bardic Inspiration die by bard level: d6, d8 at 5, d10 at 10, d12 at 15.
static func bardic_die(bard_level: int) -> int:
	return Progression.bardic_die(bard_level)


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


# --- turns --------------------------------------------------------------------

## End-of-turn bookkeeping for c: Vicious Mockery wears off, Guiding Bolt
## marks made by c count down, c's conditions run their durations (saves at
## the end of its turn, rounds, until its turn end), conditions c imposed
## "until its next turn" end, Sacred Weapon counts down.
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
	for entry: Dictionary in c.conditions.duplicate():
		var duration: Dictionary = entry.get("duration", {})
		match str(duration.get("type", "")):
			Conditions.DURATION_TARGET_TURN_END, Conditions.DURATION_ROUNDS:
				entry["turns_left"] = DictUtil.to_int(entry.get("turns_left", 1), 1) - 1
				if DictUtil.to_int(entry["turns_left"]) <= 0:
					_remove_condition(c, entry)
			Conditions.DURATION_SAVE_ENDS:
				if c.is_alive() and _saving_throw(str(entry.get("source", "")), c, Ability.from_string(str(duration.get("ability", "WIS"))), DictUtil.to_int(duration.get("dc", 10), 10)):
					_remove_condition(c, entry)
	for other in tracker.order():
		for entry: Dictionary in other.conditions.duplicate():
			var duration: Dictionary = entry.get("duration", {})
			if str(entry.get("source", "")) == c.id and str(duration.get("type", "")) == Conditions.DURATION_SOURCE_NEXT_TURN:
				entry["turns_left"] = DictUtil.to_int(entry.get("turns_left", 1), 1) - 1
				if DictUtil.to_int(entry["turns_left"]) <= 0:
					_remove_condition(other, entry)
	if c.sacred_weapon_turns > 0:
		c.sacred_weapon_turns -= 1
		if c.sacred_weapon_turns <= 0:
			c.sacred_weapon_bonus = 0
			_emit("effect_ended", {"target": c.id, "effect": "sacred_weapon"})


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
## (unconscious, stable at 0), stunned or paralyzed ends the turn at once.
## Loops until a conscious actor is waiting for intents or the encounter ends.
## (The dead are skipped by the InitiativeTracker without a turn.)
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
		if c.raging and (tracker.round_number - c.rage_started_round >= RAGE_ROUNDS or not c.is_conscious()):
			c.raging = false
			c.frenzied = false
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
		if c.is_conscious() and not c.loses_turn():
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

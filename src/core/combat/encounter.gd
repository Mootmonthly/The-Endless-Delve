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
##   {"type": "hide", "bonus": bool} / {"type": "search"}   Stealth / Perception
##   {"type": "shove", "target": id, "mode": "prone"|"push"} / {"type": "grapple", "target": id}
##   {"type": "escape_grapple"} / {"type": "help", "target": id}
##   {"type": "move_effect", "effect": tile effect id, "point": [x, y]}
##   {"type": "end_turn"}
## Round B: move "mode" ("walk"|"fly"|"teleport"); cast "targets", "mode",
## "form", "wall_end", "sustain", "careful", "heightened_target"; "haste": true
## on attack / dash / disengage / hide / use_item uses the Haste action.
## Reactions resolve automatically by Combatant.reaction_policy; summons'
## turns run inside the encounter (not logged).
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
const HIDE := "hide"
const SEARCH := "search"
const SHOVE := "shove"
const GRAPPLE := "grapple"
const ESCAPE_GRAPPLE := "escape_grapple"
const HELP := "help"
const MOVE_EFFECT := "move_effect"
## Round C: {"type": "control", "target": dominated id, "orders": [intents]}
## (free): orders for the dominated creature's next turn.
const CONTROL := "control"
## Creature types native to other planes (Banishment sends them home for good).
const OTHERWORLDLY_TYPES: Array[String] = ["aberration", "celestial", "elemental", "fey", "fiend"]
const MOVE_MODES: Array[String] = ["walk", "fly", "teleport"]
const CUTTING_WORDS_RANGE_TILES := 12  # 60 ft
const COUNTERSPELL_RANGE_TILES := 12  # 60 ft
const HELLISH_REBUKE_RANGE_TILES := 12  # 60 ft
const COUNTERCHARM_RANGE_TILES := 6  # 30 ft
const INTIMIDATING_PRESENCE_RANGE_TILES := 6  # 30 ft
const BLINDSENSE_TILES := 2  # 10 ft
const VOLLEY_RADIUS_TILES := 2  # 10 ft
const REVIVIFY_ROUNDS := 10  # 1 minute
const SHIELD_AC := 5
const MULTIATTACK_DEFENSE_AC := 4
const DRACONIC_PRESENCE_RANGE_TILES := 12  # 60 ft
## Dragon ancestor option feature -> damage type (Elemental Affinity).
const DRAGON_DAMAGE: Dictionary[String, String] = {
	"dragon_ancestor_black": "acid", "dragon_ancestor_blue": "lightning", "dragon_ancestor_brass": "fire",
	"dragon_ancestor_bronze": "lightning", "dragon_ancestor_copper": "acid", "dragon_ancestor_gold": "fire",
	"dragon_ancestor_green": "poison", "dragon_ancestor_red": "fire", "dragon_ancestor_silver": "cold",
	"dragon_ancestor_white": "cold",
}
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
const METAMAGIC_SUPPORTED: Array[String] = [
	"quickened_spell", "twinned_spell", "empowered_spell", "careful_spell", "distant_spell",
	"extended_spell", "heightened_spell", "subtle_spell",
]
const KI_FEATURES: Array[String] = ["flurry_of_blows", "patient_defense", "step_of_the_wind", "empty_body"]
const CHANNEL_DIVINITY_FEATURES: Array[String] = ["turn_undead", "turn_the_unholy", "preserve_life", "sacred_weapon"]
## use_feature ids the encounter resolves.
const USABLE_FEATURES: Array[String] = [
	"second_wind", "rage", "lay_on_hands", "bardic_inspiration", "action_surge",
	"flurry_of_blows", "patient_defense", "step_of_the_wind", "cunning_action",
	"turn_undead", "turn_the_unholy", "preserve_life", "sacred_weapon", "font_of_magic",
	"pact_weapon", "intimidating_presence", "countercharm", "wholeness_of_body", "stillness_of_mind",
	"divine_intervention", "cleansing_touch", "volley", "whirlwind_attack", "elemental_affinity",
	"dragon_wings", "wild_shape", "revert_form", "empty_body", "draconic_presence",
	"magic_jar", "end_spell",
	# round C: invocations used as features, then class features 13-20
	"one_with_shadows", "gaze_of_two_minds", "quivering_palm", "holy_nimbus",
]
## Invocations used with use_feature (the sheet's invocations, not features).
const INVOCATION_FEATURES: Array[String] = ["one_with_shadows", "gaze_of_two_minds"]
## Resource cost of a feature use when it is not 1.
const FEATURE_SPEND: Dictionary[String, int] = {"empty_body": 4, "draconic_presence": 5}
## Replay-only intent_log entries recorded when the roster changes mid-fight.
## submit() never accepts these; replay() applies them.
const LOG_JOIN := "combatant_join"  # {"v", "type", "entry": setup dict}
const LOG_REMOVE := "combatant_remove"  # {"v", "type", "id"}
const LOG_POLICY := "reaction_policy"  # {"v", "type", "id", "policy"}
const LOG_LIGHT := "light"  # {"v", "type", "light", "setup"?: true (logged by start())}
## Round C: the fight's ambient light (set_light). In "dark" fights a creature
## sees another only within its darkvision or when that creature stands in a
## lit tile (Light, Daylight, ...); magical darkness (the Darkness spell)
## stops darkvision too (Devil's Sight, blindsight and truesight see through).
const LIGHT_BRIGHT := "bright"
const LIGHT_DIM := "dim"
const LIGHT_DARK := "dark"
const LIGHT_LEVELS: Array[String] = [LIGHT_BRIGHT, LIGHT_DIM, LIGHT_DARK]
const DEVILS_SIGHT_TILES := 24  # 120 ft
const HOLY_NIMBUS_TILES := 6  # 30 ft
const HOLY_NIMBUS_ROUNDS := 10
const QUIVERING_PALM_KI := 3
const HURL_SOURCE_TURNS := 2  # until the end of the warlock's next turn
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
## Lingering spell areas (grease, web, moonbeam, wall of fire, ...): see _create_tile_effect.
var tile_effects: Array[Dictionary] = []
## Ambient light (LIGHT_LEVELS); the server sets it before start() (set_light).
var light: String = LIGHT_BRIGHT
var _effect_counter: int = 0
var _summon_counter: int = 0
## "feature:target id" pairs that are immune for the rest of the encounter
## (a creature that saved against Intimidating Presence).
var _feature_immunity: Dictionary = {}
var _dismissed: Array[String] = []  # summon ids still waiting to leave the tracker
var _cast_meta: Array[String] = []  # metamagic of the cast being checked / resolved
var _one_roll_bonus: int = 0  # Elemental Affinity / Empowered Evocation: added to one damage roll of the cast
var _one_roll_source: String = ""
var _cast_intent: Dictionary = {}  # the cast intent being resolved (mode, heightened_target, form)
var _blessed_healer_done: bool = false
var _dup_slot: int = 0  # Wish: the slot level a duplicated spell is checked / cast at (0 = none)
var _maximize: bool = false  # Overchannel: the cast's damage dice deal their maximum
var _time_stop_reactions: Dictionary = {}  # Time Stop: reaction_used of the others before time stopped
var _base_map: WalkMap = null  # walk_map before terrain effects (walls, passwall, ...)
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
	_base_map = walk_map.copy()


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
	if state == State.ACTIVE:
		_spawn_companions(c)
		_apply_lingering(c)
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
	if light != LIGHT_BRIGHT:
		intent_log.append({"v": INTENT_VERSION, "type": LOG_LIGHT, "light": light, "setup": true})
	for value: Variant in _combatants.values():
		var owner: Combatant = value
		if not owner.is_summon():
			_spawn_companions(owner)
			_apply_lingering(owner)
	for value: Variant in _combatants.values():
		_on_initiative(value as Combatant)
		var thief := value as Combatant
		if thief.sheet.has_feature("thiefs_reflexes") and not thief.is_summon():
			thief.extra_turns = 1  # lite: the second turn follows the first
			thief.extra_turn_source = "thiefs_reflexes"
	tracker.begin()
	var order: Array = []
	for c in tracker.order():
		order.append(c.id)
	var started := {"order": order}
	if light != LIGHT_BRIGHT:
		started["light"] = light
	_emit("encounter_started", started)
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
	var intent_type := str(intent.get("type", ""))
	var error := _validate(actor, intent)
	if not error.is_empty():
		return _rejected(error)

	intent_log.append(intent.duplicate(true))
	var breaks_time_stop := actor.time_stopped and _affects_others(actor, intent)
	var shadows := intent_type == USE_FEATURE and str(intent.get("feature", "")) == "one_with_shadows"
	_resolve(actor, intent)
	if intent_type != END_TURN and not shadows:
		_end_on_act(actor)
	if breaks_time_stop:
		_end_time_stop(actor, "affected_other")
	# An actor knocked out during its own turn (opportunity attack) is done.
	if intent_type != END_TURN and state == State.ACTIVE and current_actor() == actor and not actor.is_conscious():
		_end_current_turn()
	var result := {"ok": true, "error": "", "events": _pending.duplicate()}
	_pending.clear()
	return result


## "" when actor may perform intent now, else the reason.
func _validate(actor: Combatant, intent: Dictionary) -> String:
	if not actor.is_conscious():
		return "%s cannot act" % actor.display_name
	var intent_type := str(intent.get("type", ""))
	if actor.is_incapacitated() and not intent_type in [MOVE, STAND, END_TURN]:
		return "%s is incapacitated" % actor.display_name
	if actor.is_fleeing() and not intent_type in [MOVE, STAND, DASH, DODGE, END_TURN]:
		return "%s is turned: it can only move away, Dash or Dodge" % actor.display_name
	if actor.familiar and intent_type in [ATTACK, CAST, SHOVE, GRAPPLE]:
		return "a familiar cannot attack"
	var haste := DictUtil.to_bool(intent.get("haste", false), false)
	if haste and not intent_type in [ATTACK, DASH, DISENGAGE, HIDE, USE_ITEM]:
		return "the hasted action can only Attack (one weapon attack), Dash, Disengage, Hide or Use an Object"
	if haste and not _haste_available(actor):
		return "%s has no hasted action left" % actor.display_name
	match intent_type:
		MOVE:
			return _check_move(actor, intent)
		STAND:
			return stand_error(actor)
		ATTACK:
			return _check_attack(actor, intent)
		CAST:
			return _check_cast(actor, intent)
		USE_ITEM:
			return _check_use_item(actor, intent)
		USE_FEATURE:
			return _check_feature(actor, intent)
		DASH, DODGE, DISENGAGE, SEARCH, ESCAPE_GRAPPLE:
			if not haste:
				var err := _action_error(actor)
				if not err.is_empty():
					return err
			if intent_type == ESCAPE_GRAPPLE and actor.condition_sources(Conditions.GRAPPLED).is_empty():
				return "%s is not grappled" % actor.display_name
			return ""
		HIDE:
			return _check_hide(actor, intent)
		SHOVE, GRAPPLE:
			return _check_shove(actor, intent)
		HELP:
			return _check_help(actor, intent)
		MOVE_EFFECT:
			return _check_move_effect(actor, intent)
		CONTROL:
			return _check_control(actor, intent)
		END_TURN:
			return ""
	return "unknown intent type '%s'" % intent_type


## Resolves a validated intent (no logging).
func _resolve(actor: Combatant, intent: Dictionary) -> void:
	var intent_type := str(intent.get("type", ""))
	var haste := DictUtil.to_bool(intent.get("haste", false), false)
	if haste:
		_use_haste_action(actor)
	match intent_type:
		MOVE:
			_do_move(actor, GridMath.arr_to_vec_list(intent["path"]), str(intent.get("mode", "walk")))
		STAND:
			_stand(actor)
		ATTACK:
			_do_attack(actor, intent)
			check_end()
		CAST:
			_do_cast(actor, intent)
			_after_overchannel(actor, intent)
			check_end()
		USE_ITEM:
			_do_use_item(actor, intent)
			check_end()
		USE_FEATURE:
			_do_feature(actor, intent)
			check_end()
		DASH:
			if not haste:
				actor.action_used = true
			_dash(actor)
		DODGE:
			actor.action_used = true
			_dodge(actor)
		DISENGAGE:
			if not haste:
				actor.action_used = true
			_disengage(actor)
		HIDE:
			_do_hide(actor, intent)
		SEARCH:
			actor.action_used = true
			_do_search(actor)
		SHOVE, GRAPPLE:
			_do_shove(actor, intent)
			check_end()
		ESCAPE_GRAPPLE:
			actor.action_used = true
			_do_escape_grapple(actor)
		HELP:
			actor.action_used = true
			_do_help(actor, intent)
		MOVE_EFFECT:
			_do_move_effect(actor, intent)
			check_end()
		CONTROL:
			_do_control(actor, intent)
		END_TURN:
			_end_current_turn()


## "" when actor still has its action (Slow: not after its bonus action).
func _action_error(actor: Combatant) -> String:
	if actor.action_used:
		return "%s has already used its action" % actor.display_name
	if actor.buff_flag("single_action") and actor.bonus_action_used:
		return "%s is slowed: it used its bonus action this turn" % actor.display_name
	return ""


## "" when actor still has its bonus action (Slow: not after its action).
func _bonus_error(actor: Combatant) -> String:
	if actor.bonus_action_used:
		return "%s has already used its bonus action" % actor.display_name
	if actor.buff_flag("single_action") and actor.action_used:
		return "%s is slowed: it used its action this turn" % actor.display_name
	return ""


## Haste: one limited extra action per turn.
func _haste_available(actor: Combatant) -> bool:
	return actor.buff_flag("haste_action") and actor.haste_action_turn != turn_counter


func _use_haste_action(actor: Combatant) -> void:
	actor.haste_action_turn = turn_counter


## Sets a combatant's reaction policy ({trigger or reaction id: "auto" |
## "never"}). Allowed at any time (not only on its turn); recorded in
## intent_log as a replay-only entry while ACTIVE. Returns false for an
## unknown combatant.
func set_reaction_policy(combatant_id: String, policy: Dictionary) -> bool:
	var c := get_combatant(combatant_id)
	if c == null:
		return false
	var clean := {}
	for key: Variant in policy.keys():
		clean[str(key)] = "never" if str(policy[key]) == "never" else "auto"
	c.reaction_policy = clean
	if state == State.ACTIVE:
		intent_log.append({"v": INTENT_VERSION, "type": LOG_POLICY, "id": combatant_id, "policy": clean.duplicate()})
	return true


## Sets the ambient light ("bright" | "dim" | "dark"; see LIGHT_LEVELS). Before
## start() it is part of the setup (start() logs it first); while ACTIVE it
## is a replay-only `light` log entry and emits light_changed {light}.
## Returns false for an unknown level.
func set_light(level: String) -> bool:
	if not LIGHT_LEVELS.has(level) or state == State.ENDED:
		return false
	light = level
	if state == State.ACTIVE:
		intent_log.append({"v": INTENT_VERSION, "type": LOG_LIGHT, "light": level})
		_pending.clear()
		_emit("light_changed", {"light": level})
		_pending.clear()
	return true


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
		if c.id != except_id and c.is_alive() and not c.untargetable:
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
	var skip := 0
	if not intents.is_empty() and str(intents[0].get("type", "")) == LOG_LIGHT and intents[0].get("setup", false) == true:
		enc.light = str(intents[0].get("light", LIGHT_BRIGHT))
		skip = 1
	enc.start()
	for i in range(skip, intents.size()):
		var intent := intents[i]
		var intent_type := str(intent.get("type", ""))
		if intent_type == LOG_LIGHT:
			enc.set_light(str(intent.get("light", LIGHT_BRIGHT)))
		elif intent_type == LOG_JOIN:
			var entry_v: Variant = intent.get("entry", {})
			if typeof(entry_v) == TYPE_DICTIONARY:
				var entry: Dictionary = entry_v
				enc.add_combatant(Combatant.from_setup_dict(entry))
		elif intent_type == LOG_REMOVE:
			enc.remove_combatant(str(intent.get("id", "")))
		elif intent_type == LOG_POLICY:
			var policy_v: Variant = intent.get("policy", {})
			enc.set_reaction_policy(str(intent.get("id", "")), policy_v if typeof(policy_v) == TYPE_DICTIONARY else {})
		else:
			enc.submit(intent)
	return enc



# --- validation -------------------------------------------------------------

## Move validation. "mode": "walk" (default; WalkMap steps), "fly" (needs a
## fly speed: steps may cross unwalkable tiles inside the region and ignore
## corners, the last tile must be walkable) or "teleport" (one destination
## within the teleport movement granted this turn, e.g. Misty Step cast
## without a point). Difficult terrain (grease, web, spike growth, spirit
## guardians for hostiles, ...) costs 2 tiles per step unless flying over a
## ground effect.
func _check_move(actor: Combatant, intent: Dictionary) -> String:
	var raw: Variant = intent.get("path", null)
	if typeof(raw) != TYPE_ARRAY:
		return "path must be an array of [x, y] steps"
	var steps: Array = raw
	if steps.is_empty():
		return "path is empty"
	var mode := str(intent.get("mode", "walk"))
	if not MOVE_MODES.has(mode):
		return "mode must be one of %s" % ", ".join(MOVE_MODES)
	var occupied := occupied_cells(actor.id)
	if mode == "teleport":
		if actor.teleport_tiles <= 0:
			return "%s has no teleport movement this turn" % actor.display_name
		if steps.size() != 1 or not GridMath.is_vec_arr(steps[0]):
			return "a teleport names exactly one destination"
		var dest := GridMath.arr_to_vec(steps[0])
		return _teleport_error(actor, dest, actor.teleport_tiles, false)
	if mode == "fly" and actor.fly_tiles() <= 0:
		return "%s cannot fly" % actor.display_name
	var budget := actor.movement_remaining
	if actor.has_condition(Conditions.PRONE):
		var stand_problem := stand_error(actor)
		if not stand_problem.is_empty():
			return stand_problem
		budget -= stand_cost(actor)
	var fears := fear_sources(actor)
	var cursor := actor.position
	var cost := 0
	for i in range(steps.size()):
		var step_v: Variant = steps[i]
		if not GridMath.is_vec_arr(step_v):
			return "malformed path step %s" % str(step_v)
		var step := GridMath.arr_to_vec(step_v)
		if mode == "fly":
			if not region.has_point(step) or not GridMath.is_adjacent(cursor, step) or occupied.has(step):
				return "cannot fly from %s to %s" % [str(cursor), str(step)]
			if i == steps.size() - 1 and not walk_map.is_walkable(step):
				return "a flight must end on open ground"
		elif not walk_map.can_step(cursor, step, occupied):
			return "cannot step from %s to %s" % [str(cursor), str(step)]
		var barrier := _barrier_at(actor, step)
		if not barrier.is_empty() and not _effect_covers(barrier, cursor):
			return "the %s holds %s back" % [str(barrier["spell"]).replace("_", " "), actor.display_name]
		for source in fears:
			if GridMath.distance_tiles(step, source.position) < GridMath.distance_tiles(cursor, source.position):
				return "%s is frightened and cannot move closer to %s" % [actor.display_name, source.display_name]
		cost += _step_cost(actor, step, mode)
		cursor = step
	if cost > budget:
		return "the path costs %d tiles of movement but only %d remain" % [cost, budget]
	return ""


## "" when actor can teleport to dest: inside the region, walkable,
## unoccupied, within `tiles`; need_sight: in line of sight (Misty Step).
func _teleport_error(actor: Combatant, dest: Vector2i, tiles: int, need_sight: bool) -> String:
	if not region.has_point(dest) or not walk_map.is_walkable(dest):
		return "cannot teleport to %s" % str(dest)
	if occupied_cells(actor.id).has(dest):
		return "%s is occupied" % str(dest)
	if GridMath.distance_tiles(actor.position, dest) > tiles:
		return "the destination is out of range (%d tiles, range %d)" % [GridMath.distance_tiles(actor.position, dest), tiles]
	if need_sight and not walk_map.has_line_of_sight(actor.position, dest):
		return "no line of sight to the destination"
	return ""


## Movement cost of entering `step`: 2 on difficult terrain (a tile effect
## marked difficult that affects actor), else 1.
func _step_cost(actor: Combatant, step: Vector2i, mode: String) -> int:
	if actor.buff_flag("ignore_difficult"):
		return 1
	var cost := 1
	for fx in tile_effects:
		if fx.get("difficult", false) != true or not _effect_covers(fx, step):
			continue
		if fx.get("ground", false) == true and (mode == "fly" or actor.ignores_ground()):
			continue
		if not _effect_affects(fx, actor):
			continue
		cost = maxi(cost, maxi(2, DictUtil.to_int(fx.get("difficult_cost", 2), 2)))
	return cost


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
	if DictUtil.to_bool(intent.get("via_familiar", false), false):
		return _check_familiar_attack(actor, intent)
	var bonus := DictUtil.to_bool(intent.get("bonus", false), false)
	var index := DictUtil.to_int(intent.get("attack_index", 0), -1)
	var attack: Dictionary = actor.attacks[index] if index >= 0 and index < actor.attacks.size() else {}
	var haste := DictUtil.to_bool(intent.get("haste", false), false)
	if bonus:
		if haste:
			return "the hasted action is not a bonus action"
		var src := _bonus_attack_source(actor, attack)
		if src.begins_with("!"):
			return src.substr(1)
	elif haste:
		pass
	elif not (actor.attack_action_taken and actor.attacks_remaining > 0):
		var act_err := _action_error(actor)
		if not act_err.is_empty():
			return act_err
	var target := _attack_target(actor, intent)
	if target == null:
		return "unknown target"
	if target.team == actor.team:
		return "%s is on the same team" % target.display_name
	if not target.is_alive():
		return "%s is already dead" % target.display_name
	if target.untargetable:
		return "%s cannot be attacked" % target.display_name
	if attack.is_empty():
		return "invalid attack_index"
	if attack.get("disabled", false) == true:
		return "%s is gone" % str(attack.get("name", "that attack"))
	var sealed := _sealed_error(actor, target)
	if not sealed.is_empty():
		return sealed
	if actor.buff_flag("no_attacks"):
		return "%s cannot attack in this form" % actor.display_name
	if actor.is_ethereal() and not target.is_ethereal():
		return "%s is on the Ethereal Plane" % actor.display_name
	if not Encounter.is_ranged_attack(attack):
		var barrier := _barrier_at(actor, target.position)
		if not barrier.is_empty() and not _effect_covers(barrier, actor.position):
			return "%s cannot reach through the %s" % [actor.display_name, str(barrier["spell"]).replace("_", " ")]
	if not bonus and attack.get("off_hand", false) == true:
		return "the off-hand weapon attacks as a bonus action (two-weapon fighting)"
	if actor.condition_sources(Conditions.CHARMED).has(target.id):
		return "%s is charmed by %s" % [actor.display_name, target.display_name]
	var pacified := _pacified_error(actor, target)
	if not pacified.is_empty():
		return pacified
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
	if DictUtil.to_bool(intent.get("quivering_palm", false), false):
		if not actor.sheet.has_feature("quivering_palm"):
			return "%s does not know Quivering Palm" % actor.display_name
		if attack.get("unarmed", false) != true:
			return "Quivering Palm needs an unarmed strike"
		if actor.sheet.class_resource("ki") < QUIVERING_PALM_KI:
			return "Quivering Palm needs %d ki points" % QUIVERING_PALM_KI
	if DictUtil.to_bool(intent.get("hurl_through_hell", false), false):
		if not actor.sheet.has_feature("hurl_through_hell") or actor.sheet.class_resource("hurl_through_hell") <= 0:
			return "%s cannot Hurl Through Hell now" % actor.display_name
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
	var bonus_err := _bonus_error(actor)
	if not bonus_err.is_empty():
		return "!" + bonus_err
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


## At-will invocations on the warlock itself without a slot (Armor of
## Shadows: mage armor, Fiendish Vigor: false life, Ascendant Step: levitate,
## Otherworldly Leap: jump), and round C at-will invocations on any target
## (CharacterSheet.AT_WILL_INVOCATIONS) when the spell is not prepared or the
## cast names the invocation ("invocation": id).
func _free_mage_armor(actor: Combatant, spell: SpellDefinition, intent: Dictionary) -> bool:
	if not _at_will_invocation(actor, spell, intent).is_empty():
		return true
	var granted := false
	for inv: String in CharacterSheet.AT_WILL_SELF_INVOCATIONS.keys():
		if CharacterSheet.AT_WILL_SELF_INVOCATIONS[inv] == spell.id and actor.sheet.invocations.has(inv):
			granted = true
	if not granted:
		return false
	var tid := str(intent.get("target", actor.id))
	return tid.is_empty() or tid == actor.id


## Spell Mastery / Signature Spells: a cast at the spell's own level (slot_level
## 0 or that level) without a slot: "spell_mastery" (prepared 1st / 2nd-level
## mastery spells), "signature_spell" (a 3rd-level signature spell with its
## use left this short rest); "" = a normal cast.
func _mastery_free(actor: Combatant, spell: SpellDefinition, intent: Dictionary) -> String:
	var wanted := DictUtil.to_int(intent.get("slot_level", 0), 0)
	if wanted != 0 and wanted != spell.level:
		return ""
	if spell.level in [1, 2] and actor.sheet.spell_mastery.has(spell.id) and actor.sheet.is_spell_prepared(spell.id):
		return "spell_mastery"
	if spell.level == 3 and actor.sheet.signature_spells.has(spell.id) and actor.sheet.class_resource(CharacterSheet.SIGNATURE_PREFIX + spell.id) > 0:
		return "signature_spell"
	return ""


## Overchannel (evocation 14), after the cast resolved: the first use per
## long rest is free; each later one deals the caster (n + 1)d12 necrotic
## per spell level, n = earlier uses (ignores resistance and immunity):
## feature_used {actor, feature: "overchannel", target, remaining: uses} and
## damage {.., feature: "overchannel"}.
func _after_overchannel(actor: Combatant, intent: Dictionary) -> void:
	if not _maximize:
		return
	_maximize = false
	var spell := _spell_def(str(intent.get("spell", "")))
	var uses := actor.sheet.overchannel_uses
	actor.sheet.overchannel_uses += 1
	_emit("feature_used", {"actor": actor.id, "feature": "overchannel", "target": actor.id, "remaining": actor.sheet.overchannel_uses})
	if uses >= 1 and spell != null and actor.is_alive():
		var amount := DiceExpr.parse("%dd12" % ((uses + 1) * spell.level)).roll(rng).total
		_deal_effect_damage(actor, actor, amount, "necrotic", {"feature": "overchannel"})


## The round C at-will invocation a cast uses ("" = none): see _free_mage_armor.
func _at_will_invocation(actor: Combatant, spell: SpellDefinition, intent: Dictionary) -> String:
	var inv := actor.sheet.at_will_invocation(spell.id)
	if inv.is_empty():
		return ""
	if actor.sheet.is_spell_prepared(spell.id) and str(intent.get("invocation", "")) != inv:
		return ""
	return inv


## Invocation that casts this spell once per long rest with a warlock slot
## (Thief of Five Fates: bane, Mire the Mind: slow, ...); "" = none usable.
func _invocation_cast(actor: Combatant, spell: SpellDefinition) -> String:
	for inv: String in CharacterSheet.INVOCATION_SPELLS.keys():
		if CharacterSheet.INVOCATION_SPELLS[inv] == spell.id and actor.sheet.invocations.has(inv) \
				and actor.sheet.class_resource(CharacterSheet.INVOCATION_PREFIX + inv) > 0:
			return inv
	return ""


## Mystic Arcanum: the spell is one of the sheet's arcana with its use left.
func _arcanum_cast(actor: Combatant, spell: SpellDefinition) -> bool:
	return actor.sheet.mystic_arcanum.has(spell.id) and actor.sheet.class_resource(CharacterSheet.ARCANUM_PREFIX + spell.id) > 0


## Sustaining a spell (Call Lightning, Vampiric Touch, Heat Metal, Eyebite):
## recast without a slot while concentrating on it.
func _sustaining(actor: Combatant, spell: SpellDefinition, intent: Dictionary) -> bool:
	return DictUtil.to_bool(intent.get("sustain", false), false) and not spell.sustain.is_empty() \
			and str(actor.concentration.get("spell", "")) == spell.id


## The slot a cast intent uses: 0 for a cantrip (and at-will invocations);
## the concentration slot when sustaining; the spell's level for a Mystic
## Arcanum; slot_level, or the lowest available slot >= the spell's level
## when 0 / absent.
func _cast_slot(actor: Combatant, spell: SpellDefinition, intent: Dictionary) -> int:
	if _dup_slot > 0:
		return _dup_slot
	if not _mastery_free(actor, spell, intent).is_empty():
		return 0
	if spell.level == 0 or _free_mage_armor(actor, spell, intent) or spell.effect_type == SpellDefinition.EFFECT_NO_EFFECT:
		return 0
	if _sustaining(actor, spell, intent):
		return DictUtil.to_int(actor.concentration.get("slot_level", spell.level), spell.level)
	if _arcanum_cast(actor, spell) and actor.sheet.slots_left(spell.level) <= 0:
		return spell.level
	var asked := DictUtil.to_int(intent.get("slot_level", 0), 0)
	return asked if asked > 0 else actor.sheet.lowest_available_slot(spell.level)


func _cast_target(actor: Combatant, intent: Dictionary) -> Combatant:
	var tid := str(intent.get("target", ""))
	if tid.is_empty():
		return actor
	return get_combatant(tid)


## The creatures a single-target spell affects: "targets" [ids] when given,
## else "target" (default the caster). Unknown ids become null.
func _cast_targets(actor: Combatant, intent: Dictionary) -> Array[Combatant]:
	var out: Array[Combatant] = []
	var ids := DictUtil.to_string_array(intent.get("targets", []))
	if ids.is_empty():
		out.append(_cast_target(actor, intent))
		return out
	for tid in ids:
		out.append(get_combatant(tid))
	return out


## Metamagic ids of a cast intent (validated by _check_cast).
static func _metamagic_of(intent: Dictionary) -> Array[String]:
	return DictUtil.to_string_array(intent.get("metamagic", []))


## Sorcery points a cast's metamagic costs (quickened 2, empowered / careful /
## distant / extended / subtle 1, heightened 3, twinned the spell's level, min 1).
static func _metamagic_cost(options: Array[String], spell: SpellDefinition) -> int:
	var cost := 0
	for m in options:
		match m:
			"quickened_spell":
				cost += 2
			"empowered_spell", "careful_spell", "distant_spell", "extended_spell", "subtle_spell":
				cost += 1
			"heightened_spell":
				cost += 3
			"twinned_spell":
				cost += maxi(1, spell.level)
	return cost


## Spell range in tiles; Distant Spell doubles it (touch becomes 30 ft).
func _spell_range(spell: SpellDefinition) -> int:
	var tiles := spell.range_tiles()
	if _cast_meta.has("distant_spell"):
		if spell.range_ft == SpellDefinition.TOUCH_RANGE_FT:
			return 6
		return tiles * 2
	return tiles


func _check_cast(actor: Combatant, intent: Dictionary) -> String:
	var spell_id := str(intent.get("spell", ""))
	var spell := _spell_def(spell_id)
	if spell == null:
		return "unknown spell '%s'" % spell_id
	if not spell.is_castable():
		return "%s cannot be cast yet" % spell.display_name
	if not spell.is_combat_castable():
		return "%s takes %s to cast and cannot be cast in combat" % [spell.display_name, spell.casting_time.replace("_", " ")]
	if spell.effect_type == SpellDefinition.EFFECT_REACTION:
		return "%s is cast as a reaction" % spell.display_name
	var sustain := DictUtil.to_bool(intent.get("sustain", false), false)
	if sustain and not _sustaining(actor, spell, intent):
		return "%s is not sustaining %s" % [actor.display_name, spell.display_name]
	var via_invocation := _invocation_cast(actor, spell)
	if not actor.sheet.is_spell_prepared(spell_id) and not _free_mage_armor(actor, spell, intent) \
			and via_invocation.is_empty() and not _arcanum_cast(actor, spell) and not sustain:
		return "%s has not prepared %s" % [actor.display_name, spell.display_name]
	if actor.raging:
		return "%s cannot cast spells while raging" % actor.display_name
	var form_kind := str(actor.form.get("kind", ""))
	if actor.buff_flag("no_spellcasting") or form_kind in ["polymorph", "true_polymorph", "animal_shapes", "shapechange"] \
			or (form_kind == "wild_shape" and not actor.sheet.has_feature("beast_spells")):
		return "%s cannot cast spells now" % actor.display_name
	if actor.antimagic:
		return "%s stands in an antimagic field" % actor.display_name
	var meta := Encounter._metamagic_of(intent)
	_cast_meta = meta
	for m in meta:
		if not actor.sheet.metamagic.has(m):
			return "%s does not know %s" % [actor.display_name, m]
		if not Features.IMPLEMENTED_METAMAGIC.has(m):
			return "%s is not modelled yet" % m
		if meta.count(m) > 1:
			return "%s is listed twice" % m
	var non_empowered := 0
	for m in meta:
		if m != "empowered_spell":
			non_empowered += 1
	if non_empowered > 1:
		return "only one metamagic option per casting (Empowered Spell may join it)"
	if not meta.is_empty() and actor.sheet.class_resource("sorcery_points") < Encounter._metamagic_cost(meta, spell):
		return "not enough sorcery points (%d needed)" % Encounter._metamagic_cost(meta, spell)
	if _tile_silenced(actor.position) and not meta.has("subtle_spell") and spell.raw.get("components", ["V"]).has("V"):
		return "%s cannot speak the spell inside the silence" % actor.display_name
	var quickened := meta.has("quickened_spell")
	if quickened and spell.uses_bonus_action():
		return "Quickened Spell needs a spell cast with an action"
	var cost := spell.casting_time
	if sustain:
		cost = spell.sustain
	if cost == "bonus_action" or quickened:
		var err := _bonus_error(actor)
		if not err.is_empty():
			return err
	else:
		var err := _action_error(actor)
		if not err.is_empty():
			return err
	var mastery := _mastery_free(actor, spell, intent)
	if DictUtil.to_bool(intent.get("overchannel", false), false):
		if not actor.sheet.has_feature("overchannel"):
			return "%s cannot Overchannel" % actor.display_name
		if spell.level < 1 or spell.level > 5 or not DictUtil.to_string_array(spell.raw.get("classes", [])).has("wizard") \
				or (spell.damage.is_empty() and spell.damage_by_slot.is_empty()):
			return "Overchannel needs a damaging wizard spell of 1st to 5th level"
	if spell.level == 0 or _free_mage_armor(actor, spell, intent) or spell.effect_type == SpellDefinition.EFFECT_NO_EFFECT or not mastery.is_empty():
		if DictUtil.to_int(intent.get("slot_level", 0), 0) != 0 and spell.effect_type != SpellDefinition.EFFECT_NO_EFFECT and mastery.is_empty():
			return "cantrips do not use spell slots" if spell.level == 0 else "an at-will invocation needs no spell slot"
	elif not sustain:
		var slot := _cast_slot(actor, spell, intent)
		var arcanum := _arcanum_cast(actor, spell) and slot == spell.level and actor.sheet.slots_left(slot) <= 0
		if slot == 0:
			return "%s has no spell slots of level %d or higher left" % [actor.display_name, spell.level]
		if slot < spell.level or slot > 9:
			return "%s needs a slot of level %d or higher" % [spell.display_name, spell.level]
		if actor.sheet.slots_left(slot) <= 0 and not arcanum:
			return "%s has no level %d spell slots left" % [actor.display_name, slot]
	match spell.effect_type:
		SpellDefinition.EFFECT_WISH:
			return _check_wish(actor, spell, intent)
		SpellDefinition.EFFECT_NO_EFFECT, SpellDefinition.EFFECT_TIME_STOP:
			return ""
		SpellDefinition.EFFECT_WEAPON_ATTACK:
			return _check_weapon_attack(actor, spell)
	return _check_cast_effect(actor, spell, intent)


## Target, area and metamagic-target rules of a cast (after the slot and
## action checks): Sculpt / Careful / Heightened / Twinned Spell, teleport and
## summon points, areas, targets per slot level, transformations and forced
## moves. Also checks the spell a Wish duplicates.
func _check_cast_effect(actor: Combatant, spell: SpellDefinition, intent: Dictionary) -> String:
	var meta := _cast_meta
	var sculpt := DictUtil.to_string_array(intent.get("sculpt", []))
	if not sculpt.is_empty():
		if not actor.sheet.has_feature("sculpt_spells") or spell.school.to_lower() != "evocation" or not spell.is_area():
			return "only an evocation area spell of a Sculpt Spells caster can be sculpted"
		if sculpt.size() > 1 + spell.level:
			return "at most %d creatures can be sculpted" % (1 + spell.level)
		for sid in sculpt:
			var s := get_combatant(sid)
			if s == null or s.team != actor.team or s == actor:
				return "%s is not an ally (other than the caster)" % sid
	var careful := DictUtil.to_string_array(intent.get("careful", []))
	if not careful.is_empty():
		if not meta.has("careful_spell") or not spell.is_area():
			return "careful needs Careful Spell on an area spell"
		if careful.size() > maxi(1, actor.sheet.ability_modifier(Ability.Type.CHA)):
			return "Careful Spell protects at most %d creatures" % maxi(1, actor.sheet.ability_modifier(Ability.Type.CHA))
	if meta.has("heightened_spell") and get_combatant(str(intent.get("heightened_target", ""))) == null:
		return "Heightened Spell needs a heightened_target"
	match spell.effect_type:
		SpellDefinition.EFFECT_TELEPORT:
			if GridMath.is_vec_arr(intent.get("point", null)):
				return _teleport_error(actor, GridMath.arr_to_vec(intent["point"]), _teleport_tiles(spell), DictUtil.to_bool(spell.raw_effect.get("need_sight", true), true))
			return ""
		SpellDefinition.EFFECT_SUMMON:
			return _check_summon(actor, spell, intent)
		SpellDefinition.EFFECT_HEAL_POOL:
			return ""
	if spell.is_area():
		return _check_area(actor, spell, intent)
	var targets := _cast_targets(actor, intent)
	var slot_for_count := maxi(spell.level, _cast_slot(actor, spell, intent))
	if targets.size() > spell.targets_at(slot_for_count):
		return "%s affects at most %d creatures" % [spell.display_name, spell.targets_at(slot_for_count)]
	var seen: Array[Combatant] = []
	for t in targets:
		if seen.has(t):
			return "a target is listed twice"
		seen.append(t)
		var err := _check_spell_target(actor, spell, t)
		if not err.is_empty():
			return err
	if meta.has("twinned_spell"):
		if spell.range_ft == 0 or spell.target == SpellDefinition.TARGET_SELF or spell.targets_at(slot_for_count) > 1:
			return "Twinned Spell needs a spell that targets one creature other than the caster"
		var twin := get_combatant(str(intent.get("twin_target", "")))
		if twin == null or targets.has(twin):
			return "Twinned Spell needs a second, different twin_target"
		var err := _check_spell_target(actor, spell, twin)
		if not err.is_empty():
			return err
	elif intent.has("twin_target"):
		return "twin_target needs Twinned Spell"
	if spell.effect_type == SpellDefinition.EFFECT_TRANSFORM:
		return _check_transform(actor, spell, targets[0], intent)
	if spell.effect_type == SpellDefinition.EFFECT_FORCED_MOVE:
		return _check_forced_move(actor, spell, targets[0], intent)
	if _at_will_invocation(actor, spell, intent) == "chains_of_carceri":
		for t in targets:
			if not t.creature_type in ["celestial", "fiend", "elemental"]:
				return "Chains of Carceri holds only celestials, fiends and elementals"
			if _feature_immunity.has("chains_of_carceri:" + t.id):
				return "Chains of Carceri was already used on %s" % t.display_name
	if spell.effect_type == SpellDefinition.EFFECT_EXPLORATION:
		return OutOfCombat.exploration_error(spell, intent)
	if spell.raw_effect.get("requires_wall", false) == true and not _next_to_wall(actor.position):
		return "%s needs a stone wall next to %s" % [spell.display_name, actor.display_name]
	return ""


## Whether a wall (an unwalkable tile of the map) is adjacent to tile.
func _next_to_wall(tile: Vector2i) -> bool:
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var n := tile + Vector2i(dx, dy)
			if n != tile and not walk_map.is_walkable(n):
				return true
	return false


## Target rules of a single-target spell: range (Distant Spell), sight, team
## (harmful spells need a hostile, others an ally; "any" both), creature
## types (Hold Person: humanoids), Revivify / Spare the Dying targets.
func _check_spell_target(actor: Combatant, spell: SpellDefinition, target: Combatant) -> String:
	if target == null:
		return "unknown target"
	if spell.target == SpellDefinition.TARGET_SELF and target != actor:
		return "%s can only target its caster" % spell.display_name
	if actor.is_sealed() and target != actor:
		return "%s is sealed inside a sphere of force" % actor.display_name
	if actor.is_ethereal() and target != actor:
		return "%s is on the Ethereal Plane" % actor.display_name
	if target.untargetable:
		return "%s cannot be targeted" % target.display_name
	if spell.effect_type == SpellDefinition.EFFECT_REVIVE:
		if target.team != actor.team:
			return "%s is not an ally" % target.display_name
		if spell.raw_effect.get("stabilize", false) == true:
			if not target.is_dying():
				return "%s is not dying" % target.display_name
		else:
			if target.is_alive():
				return "%s is not dead" % target.display_name
			var max_rounds := DictUtil.to_int(spell.raw_effect.get("max_rounds", REVIVIFY_ROUNDS), REVIVIFY_ROUNDS)
			if max_rounds >= 0 and (target.died_round < 0 or tracker.round_number - target.died_round > max_rounds) \
					and not OutOfCombat.has_lingering_feature(target.sheet, "gentle_repose"):
				return "%s has been dead too long" % target.display_name
			if target.is_summon() or not target.sheet.uses_death_saves and target.is_monster():
				return "%s cannot be revived" % target.display_name
	elif not target.is_alive() and spell.raw_effect.get("dead_ok", false) != true:
		return "%s is dead" % target.display_name
	if spell.is_harmful():
		if target.team == actor.team:
			return "%s is on the same team" % target.display_name
		if actor.condition_sources(Conditions.CHARMED).has(target.id):
			return "%s is charmed by %s" % [actor.display_name, target.display_name]
		var pacified := _pacified_error(actor, target)
		if not pacified.is_empty():
			return pacified
	elif spell.target != SpellDefinition.TARGET_ANY:
		if target.team != actor.team:
			return "%s is not an ally" % target.display_name
		if spell.effect_type == SpellDefinition.EFFECT_BUFF and spell.buff == SpellDefinition.BUFF_MAGE_ARMOR and target.sheet.armor_base > 0:
			return "%s is wearing armor" % target.display_name
	var types := DictUtil.to_string_array(spell.raw_effect.get("creature_types", []))
	if not types.is_empty() and target.team != actor.team and not types.has(target.creature_type) and target.is_monster():
		return "%s only affects %s" % [spell.display_name, ", ".join(types)]
	if DictUtil.to_string_array(spell.raw_effect.get("excluded_types", [])).has(target.creature_type):
		return "%s has no effect on %s" % [spell.display_name, target.creature_type]
	if target != actor:
		var dist := GridMath.distance_tiles(actor.position, target.position)
		var reach := maxi(1, _spell_range(spell)) if spell.range_ft > 0 else 0
		if dist > reach:
			return "%s is out of range (%d tiles, range %d)" % [target.display_name, dist, reach]
		if not walk_map.has_line_of_sight(actor.position, target.position):
			return "no line of sight to %s" % target.display_name
	var warded := _spell_warded(actor, target, spell)
	if not warded.is_empty():
		return "%s is protected: %s" % [target.display_name, warded.replace("_", " ")]
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
	if dist > _spell_range(spell):
		return "the point is out of range (%d tiles, range %d)" % [dist, _spell_range(spell)]
	if not walk_map.has_line_of_sight(actor.position, point):
		return "no line of sight to the point"
	if GridMath.is_vec_arr(intent.get("wall_end", null)):
		var end := GridMath.arr_to_vec(intent["wall_end"])
		if GridMath.distance_tiles(point, end) > spell.area_size_tiles():
			return "the wall is at most %d tiles long" % spell.area_size_tiles()
	var on := str(spell.zone.get("point_on", ""))
	var on_modes_v: Variant = spell.zone.get("point_on_modes", null)
	if typeof(on_modes_v) == TYPE_DICTIONARY:
		var on_modes: Dictionary = on_modes_v
		var mode := str(intent.get("mode", ""))
		if not mode.is_empty() and not on_modes.has(mode):
			return "%s mode must be one of %s" % [spell.display_name, ", ".join(DictUtil.to_string_array(on_modes.keys()))]
		on = str(on_modes.get(mode, on))
	if on == "wall" and walk_map.is_walkable(point):
		return "%s needs a wall tile" % spell.display_name
	if on == "floor" and (not walk_map.is_walkable(point) or occupied_cells().has(point)):
		return "%s needs a free floor tile" % spell.display_name
	return ""


## Teleport distance in tiles (the effect's range_ft, else the spell's range).
func _teleport_tiles(spell: SpellDefinition) -> int:
	var ft := DictUtil.to_int(spell.raw_effect.get("range_ft", spell.range_ft), spell.range_ft)
	var tiles := GridMath.feet_to_tiles(ft)
	return tiles * 2 if _cast_meta.has("distant_spell") else tiles


## Summons: an optional "point" (within range, open) and "form" (a monster
## id allowed by the spell: its "forms" list, or creature type with max CR).
func _check_summon(actor: Combatant, spell: SpellDefinition, intent: Dictionary) -> String:
	if GridMath.is_vec_arr(intent.get("point", null)):
		var p := GridMath.arr_to_vec(intent["point"])
		if not region.has_point(p) or GridMath.distance_tiles(actor.position, p) > maxi(1, _spell_range(spell)):
			return "the point is out of range"
	if not str(spell.raw_effect.get("custom", "")).is_empty():
		return ""
	var form := str(intent.get("form", spell.raw_effect.get("monster", "")))
	if _summon_def(spell, form, _cast_slot(actor, spell, intent)) == null:
		return "%s cannot summon '%s'" % [spell.display_name, form]
	return ""


## The monster a summon spell may bring for `form` (null when not allowed).
func _summon_def(spell: SpellDefinition, form: String, slot: int = 0) -> MonsterDefinition:
	return Encounter.summon_def_for(spell, form, slot, _content().get("monsters", {}))


## The monster a summon spell cast at `slot` may bring as `form`: a listed id
## ("forms" array, or "also_forms"), else a creature of the "forms" type (or
## one of "form_types") whose challenge rating is at most "max_cr" (+
## "cr_per_slot" per slot level above the spell's, or "cr_by_slot" {slot:
## cr}). null when not allowed.
static func summon_def_for(spell: SpellDefinition, form: String, slot: int, monsters: Dictionary) -> MonsterDefinition:
	if not monsters.has(form):
		return null
	var e := spell.raw_effect
	var def: MonsterDefinition = monsters[form]
	if DictUtil.to_string_array(e.get("also_forms", [])).has(form):
		return def
	var forms_v: Variant = e.get("forms", null)
	if typeof(forms_v) == TYPE_ARRAY:
		return def if DictUtil.to_string_array(forms_v).has(form) else null
	var types := DictUtil.to_string_array(e.get("form_types", []))
	if typeof(forms_v) == TYPE_STRING:
		types.append(str(forms_v))
	if not types.is_empty() and not types.has(def.creature_type):
		return null
	var max_cr := DictUtil.to_float(e.get("max_cr", 99.0), 99.0)
	var above := maxi(0, slot - spell.level)
	max_cr += DictUtil.to_float(e.get("cr_per_slot", 0.0), 0.0) * above
	var by_slot_v: Variant = e.get("cr_by_slot", {})
	if typeof(by_slot_v) == TYPE_DICTIONARY:
		var by_slot: Dictionary = by_slot_v
		for key: Variant in by_slot.keys():
			if DictUtil.to_int(key, 99) <= slot:
				max_cr = maxf(max_cr, DictUtil.to_float(by_slot[key], 0.0))
	if def.challenge_rating > max_cr:
		return null
	return def


## Polymorph: "form" (default: the spell's "form" for a hostile, "ally_form"
## for an ally) must be a beast of CR <= the target's CR (or level).
func _check_transform(actor: Combatant, spell: SpellDefinition, target: Combatant, intent: Dictionary) -> String:
	var def := _transform_def(spell, target, intent)
	var e := spell.raw_effect
	if def == null:
		return "no such form"
	if e.get("any_type", false) != true and def.creature_type != "beast":
		return "%s turns creatures into beasts" % spell.display_name
	if DictUtil.to_string_array(e.get("excluded_form_types", [])).has(def.creature_type):
		return "%s cannot take the form of a %s" % [spell.display_name, def.creature_type]
	var limit := target.challenge_rating if target.is_monster() else float(target.sheet.level)
	match str(e.get("cr_limit", "target")):
		"caster":
			limit = float(actor.sheet.level)
		"none":
			limit = 99.0
	if e.has("max_cr"):
		limit = minf(limit, DictUtil.to_float(e["max_cr"], 99.0))
	if def.challenge_rating > limit:
		return "%s is too powerful a form for %s" % [def.display_name, target.display_name]
	return ""


func _transform_def(spell: SpellDefinition, target: Combatant, intent: Dictionary) -> MonsterDefinition:
	var caster := current_actor()
	var default := str(spell.raw_effect.get("form", "rat"))
	if caster != null and target.team == caster.team:
		default = str(spell.raw_effect.get("ally_form", default))
	var form := str(intent.get("form", default))
	var monsters: Dictionary = _content().get("monsters", {})
	if not monsters.has(form):
		return null
	var def: MonsterDefinition = monsters[form]
	return def

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
	elif not DictUtil.to_bool(intent.get("haste", false), false):
		return _action_error(actor)
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
	if feature == "revert_form":
		return str(actor.form.get("kind", "")) in ["wild_shape", "shapechange", "magic_jar"]
	if feature in ["elemental_affinity", "draconic_presence"]:
		return actor.sheet.has_feature(feature)
	if feature == "magic_jar":
		return _lingering_feature(actor, "magic_jar")
	if feature == "end_spell":
		return true
	if INVOCATION_FEATURES.has(feature):
		return actor.sheet.invocations.has(feature)
	return false


## Resource id spent by a feature use ("" = none).
static func _feature_resource(feature: String) -> String:
	if KI_FEATURES.has(feature):
		return "ki"
	if CHANNEL_DIVINITY_FEATURES.has(feature):
		return "channel_divinity"
	if feature in ["font_of_magic", "elemental_affinity", "draconic_presence"]:
		return "sorcery_points"
	if CharacterSheet.RESOURCE_FEATURES.has(feature):
		return feature
	return ""


## "action", "bonus" or "free".
static func _feature_cost(feature: String) -> String:
	match feature:
		"lay_on_hands", "turn_undead", "turn_the_unholy", "preserve_life", "sacred_weapon", "pact_weapon", \
				"intimidating_presence", "countercharm", "wholeness_of_body", "stillness_of_mind", "divine_intervention", \
				"cleansing_touch", "volley", "whirlwind_attack", "wild_shape", "empty_body", "draconic_presence", "magic_jar", \
				"one_with_shadows", "gaze_of_two_minds", "quivering_palm", "holy_nimbus":
			return "action"
		"action_surge", "elemental_affinity", "end_spell":
			return "free"
	return "bonus"


func _check_feature(actor: Combatant, intent: Dictionary) -> String:
	var feature := str(intent.get("feature", ""))
	if not USABLE_FEATURES.has(feature):
		return "unknown feature '%s'" % feature
	if not _has_usable_feature(actor, feature):
		return "%s does not have %s" % [actor.display_name, feature]
	var resource := Encounter._feature_resource(feature)
	if not resource.is_empty() and feature != "font_of_magic" and actor.sheet.class_resource(resource) < FEATURE_SPEND.get(feature, 1):
		return "%s has no uses of %s left" % [actor.display_name, resource]
	match Encounter._feature_cost(feature):
		"action":
			var err := _action_error(actor)
			if not err.is_empty():
				return err
		"bonus":
			var err := _bonus_error(actor)
			if not err.is_empty():
				return err
	var mode := str(intent.get("mode", ""))
	var round_b := _check_feature_b(actor, feature, intent)
	if round_b != "-":
		return round_b
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
				return _hide_error(actor)
			if not mode in ["dash", "disengage"]:
				return "cunning_action needs mode \"dash\", \"disengage\" or \"hide\""
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

## Moves along path. Leaving a hostile's reach provokes opportunity attacks
## (reactions: trigger creature_left_reach); entering tile effects triggers
## them (enter / per tile); a hidden mover ending next to a conscious hostile
## is revealed; grapples whose creatures are no longer adjacent end.
## "fly" moves emit moved with "mode": "fly"; "teleport" emits teleported.
func _do_move(actor: Combatant, path: Array[Vector2i], mode: String = "walk") -> void:
	if mode == "teleport":
		var dest := path[0]
		actor.teleport_tiles = 0
		_teleport(actor, dest, "")
		check_end()
		return
	if actor.has_condition(Conditions.PRONE):
		_stand(actor)
	for step in path:
		var from := actor.position
		if not actor.disengaging:
			for hostile in _opportunity_attackers(actor, from, step):
				if not actor.is_conscious():
					break
				if not hostile.can_react() or not hostile.reaction_allowed("creature_left_reach", "opportunity_attack"):
					continue
				_emit("opportunity_attack", {"attacker": hostile.id, "target": actor.id})
				_use_reaction(hostile, "opportunity_attack", "creature_left_reach", {"target": actor.id})
				_resolve_attack(hostile, actor, _usable_melee_index(hostile), false, {"opportunity": true})
		if not actor.is_conscious() or state != State.ACTIVE:
			break
		actor.position = step
		actor.movement_remaining -= _step_cost(actor, step, mode)
		actor.tiles_moved += 1
		var moved := {"actor": actor.id, "from": GridMath.vec_to_arr(from), "to": GridMath.vec_to_arr(step)}
		if mode == "fly":
			moved["mode"] = "fly"
		_emit("moved", moved)
		_after_position_change(actor, from, mode != "fly")
		if not actor.is_conscious() or state != State.ACTIVE:
			break
	if actor.hidden and _hostile_adjacent(actor):
		_reveal(actor, "moved_adjacent")
	check_end()


## Teleports actor to dest (no opportunity attacks). Emits teleported {actor,
## from, to, spell?}, then tile effects at the destination trigger.
func _teleport(actor: Combatant, dest: Vector2i, spell_id: String) -> void:
	var from := actor.position
	actor.position = dest
	var ev := {"actor": actor.id, "from": GridMath.vec_to_arr(from), "to": GridMath.vec_to_arr(dest)}
	if not spell_id.is_empty():
		ev["spell"] = spell_id
	_emit("teleported", ev)
	_after_position_change(actor, from, false)


## Bookkeeping after a creature's tile changed (moved, pushed, teleported):
## grapples end when grappler and grappled are no longer adjacent; tile
## effects trigger on entry (walking: also per tile moved, e.g. spike growth).
func _after_position_change(c: Combatant, from: Vector2i, walked: bool) -> void:
	_check_grapples(c)
	_refresh_anchored(c)
	_refresh_antimagic()
	if c.is_alive():
		_tile_effects_on_enter(c, from, walked)


## Stands up: spends half the speed and ends prone.
func _stand(actor: Combatant) -> void:
	actor.movement_remaining = maxi(0, actor.movement_remaining - stand_cost(actor))
	_end_conditions_named(actor, Conditions.PRONE)


## Dash / Dodge / Disengage; `source` names the feature that granted it
## (patient_defense, step_of_the_wind, cunning_action) on the event.
func _dash(actor: Combatant, source: String = "") -> void:
	actor.movement_remaining += actor.speed_tiles()
	_emit("dash", Encounter._with_source({"actor": actor.id}, source))


func _dodge(actor: Combatant, source: String = "") -> void:
	actor.dodging = true
	_emit("dodge", Encounter._with_source({"actor": actor.id}, source))


func _disengage(actor: Combatant, source: String = "") -> void:
	actor.disengaging = true
	_emit("disengage", Encounter._with_source({"actor": actor.id}, source))


static func _with_source(ev: Dictionary, source: String) -> Dictionary:
	if not source.is_empty():
		ev["source"] = source
	return ev


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
		if Encounter.is_ranged_attack(attack) or attack.get("off_hand", false) == true or attack.get("disabled", false) == true:
			continue
		var item := str(attack.get("item", ""))
		if item.is_empty() or c.sheet.has_item(item):
			return i
	return -1


# --- attacks ---------------------------------------------------------------------

func _do_attack(actor: Combatant, intent: Dictionary) -> void:
	if DictUtil.to_bool(intent.get("via_familiar", false), false):
		_do_familiar_attack(actor, intent)
		return
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
	elif DictUtil.to_bool(intent.get("haste", false), false):
		pass  # the hasted action: one weapon attack
	else:
		_take_attack_action(actor, actor.attacks[index])
	if DictUtil.to_bool(intent.get("reckless", false), false):
		actor.reckless = true
		_emit("effect_applied", {"source": actor.id, "target": actor.id, "effect": "reckless_attack"})
	for key: String in ["smite", "stun", "technique", "quivering_palm", "hurl_through_hell"]:
		if intent.has(key):
			opts[key] = intent[key]
	_resolve_attack(actor, target, index, bonus, opts)
	_horde_breaker(actor, target, index)
	_after_own_attack(actor)


## Pact of the Chain: the warlock forgoes one attack of its Attack action
## and its familiar attacks with its reaction ("via_familiar": true;
## "attack_index" is the familiar's attack; the target must be in the
## familiar's reach / range).
func _check_familiar_attack(actor: Combatant, intent: Dictionary) -> String:
	if not actor.sheet.has_feature("pact_of_the_chain"):
		return "%s has no Pact of the Chain" % actor.display_name
	if DictUtil.to_bool(intent.get("bonus", false), false) or DictUtil.to_bool(intent.get("haste", false), false):
		return "the familiar attacks in place of one attack of the Attack action"
	if not (actor.attack_action_taken and actor.attacks_remaining > 0):
		var err := _action_error(actor)
		if not err.is_empty():
			return err
	var fam := _chain_familiar(actor)
	if fam == null:
		return "%s has no familiar ready to attack" % actor.display_name
	var target := get_combatant(str(intent.get("target", "")))
	if target == null or target.team == fam.team or not target.is_alive() or target.untargetable:
		return "the familiar needs a hostile target"
	var index := DictUtil.to_int(intent.get("attack_index", 0), -1)
	if index < 0 or index >= fam.attacks.size():
		return "invalid attack_index for the familiar"
	var reach := attack_reach_error(fam.position, target.position, fam.attacks[index])
	if not reach.is_empty():
		return reach
	return ""


## actor's familiar that can attack now (alive, conscious, reaction free).
func _chain_familiar(actor: Combatant) -> Combatant:
	for c in _summons_of(actor.id):
		if c.familiar and c.is_conscious() and c.can_react() and not c.is_incapacitated():
			return c
	return null


func _do_familiar_attack(actor: Combatant, intent: Dictionary) -> void:
	var fam := _chain_familiar(actor)
	var target := get_combatant(str(intent.get("target", "")))
	_take_attack_action(actor, {})
	_use_reaction(fam, "familiar_attack", "owner_attack", {"owner": actor.id, "target": target.id})
	_resolve_attack(fam, target, DictUtil.to_int(intent.get("attack_index", 0), 0))
	_after_own_attack(fam)


## Horde Breaker (hunter 3): once per turn, after a weapon attack, another
## attack against a different hostile within 5 ft of the target and in reach
## (the lowest hit points, ties by id).
func _horde_breaker(actor: Combatant, target: Combatant, index: int) -> void:
	if not actor.sheet.has_feature("horde_breaker") or actor.horde_breaker_turn == turn_counter or index < 0 or index >= actor.attacks.size():
		return
	var attack: Dictionary = actor.attacks[index]
	var best: Combatant = null
	for h in hostiles_of(actor):
		if h == target or not h.is_conscious() or h.untargetable or not GridMath.is_adjacent(h.position, target.position):
			continue
		if not attack_reach_error(actor.position, h.position, attack).is_empty():
			continue
		if best == null or h.sheet.current_hp < best.sheet.current_hp or (h.sheet.current_hp == best.sheet.current_hp and h.id < best.id):
			best = h
	if best == null or not actor.reaction_allowed("horde_breaker", "horde_breaker"):
		return
	var consumes := str(attack.get("consumes", ""))
	if not consumes.is_empty() and not actor.sheet.has_item(consumes):
		return
	actor.horde_breaker_turn = turn_counter
	_emit("feature_used", {"actor": actor.id, "feature": "horde_breaker", "target": best.id, "remaining": 0})
	_resolve_attack(actor, best, index)


## Initiative-time features: Superior Inspiration (a bard with no Bardic
## Inspiration regains one), Perfect Self (a monk with no ki regains 4).
func _on_initiative(c: Combatant) -> void:
	if c.sheet.has_feature("superior_inspiration") and c.sheet.class_resource("bardic_inspiration") <= 0:
		c.sheet.class_resources["bardic_inspiration"] = 1
		_emit("feature_used", {"actor": c.id, "feature": "superior_inspiration", "target": c.id, "remaining": 1})
	if c.sheet.has_feature("perfect_self") and c.sheet.class_resource("ki") <= 0:
		c.sheet.class_resources["ki"] = 4
		_emit("feature_used", {"actor": c.id, "feature": "perfect_self", "target": c.id, "remaining": 4})


## Spends one attack of the Attack action (taking the action on the first):
## attacks_per_action rolls (Thirsting Blade: two with the pact weapon).
func _take_attack_action(actor: Combatant, attack: Dictionary) -> void:
	if actor.attack_action_taken and actor.attacks_remaining > 0:
		actor.attacks_remaining -= 1
		return
	actor.action_used = true
	actor.attack_action_taken = true
	var per_action := actor.attacks_per_action
	if attack.get("pact_weapon", false) == true and actor.sheet.invocations.has("thirsting_blade"):
		per_action = maxi(per_action, 2)
	if attack.get("single_attack", false) == true:
		per_action = 1  # Flame Blade: one melee spell attack per action
	actor.attacks_remaining = per_action - 1


## After actor attacks: it is no longer hidden, Invisibility (the spell) and
## Sanctuary / Tranquility on it end.
func _after_own_attack(actor: Combatant) -> void:
	if actor.hidden:
		_reveal(actor, "attacked")
	for entry: Dictionary in actor.conditions.duplicate():
		if entry.get("ends_on_attack", false) == true:
			_remove_condition(actor, entry)
	for b: Dictionary in actor.buffs.duplicate():
		if b.get("ends_on_attack", false) == true:
			_remove_buff(actor, b)
	if actor.sheet.active_buffs.has("tranquility"):
		actor.sheet.active_buffs.erase("tranquility")
		_emit("effect_ended", {"target": actor.id, "effect": "tranquility"})


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
## Also (round B): an attacker the target cannot see (hidden, invisible) has
## advantage, an attack against a creature the attacker cannot see has
## disadvantage (Feral Senses / Blindsense ignore that); Help, Faerie Fire
## (attackers_advantage), True Strike; Blur (attackers_disadvantage), exhaustion
## 3+, Escape the Horde (opportunity attacks); Elusive removes advantage
## against the rogue.
func _attack_mode(attacker: Combatant, target: Combatant, attack: Dictionary, weapon: bool, opts: Dictionary = {}) -> Dictionary:
	var ranged := Encounter.is_ranged_attack(attack)
	var adjacent := GridMath.is_adjacent(attacker.position, target.position)
	var target_down := target.sheet.is_unconscious()
	var advantage := target_down or not target.guided_by.is_empty() or target.reckless
	var disadvantage := (target.dodging and target.is_conscious() and not target.is_incapacitated()) or attacker.mocked
	if not can_see(target, attacker):
		advantage = true
	if not can_see(attacker, target) and not _senses_unseen(attacker, target):
		disadvantage = true
	if not target.helped_by.is_empty() and target.help_team == attacker.team:
		advantage = true
	if target.buff_flag("attackers_advantage") or attacker.buff_flag("attack_advantage"):
		advantage = true
	for b in attacker.buffs:
		if str(b.get("advantage_vs", "")) == target.id:
			advantage = true
	if target.buff_flag("attackers_disadvantage") or attacker.buff_flag("attack_disadvantage"):
		disadvantage = true
	if attacker.buff_list("attack_disadvantage_abilities").has(str(attack.get("ability", "STR" if not ranged else "DEX"))):
		disadvantage = true
	if not attacker.creature_type.is_empty() and (target.buff_list("attackers_disadvantage_types").has(attacker.creature_type) \
			or (target.sheet.has_feature("purity_of_spirit") and attacker.creature_type in ["aberration", "celestial", "elemental", "fey", "fiend", "undead"])):
		disadvantage = true
	if attacker.sheet.exhaustion >= 3:
		disadvantage = true
	if opts.get("opportunity", false) == true and target.sheet.has_feature("escape_the_horde"):
		disadvantage = true
	if opts.get("protected", false) == true:
		disadvantage = true
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
	if target.sheet.has_feature("elusive") and not target.is_incapacitated():
		advantage = false
	var auto_crit := adjacent and (target_down or target.has_condition(Conditions.PARALYZED) or target.has_condition(Conditions.UNCONSCIOUS))
	return {"mode": D20.combine(advantage, disadvantage), "auto_crit": auto_crit}


## Whether viewer can see target: not when viewer is blinded, target is
## hidden from viewer's team or invisible (unless within Blindsense range),
## or no line of sight. Allies always see each other.
func can_see(viewer: Combatant, target: Combatant) -> bool:
	if viewer == target:
		return true
	if viewer.team == target.team:
		return true
	var gaze := _gaze_partner(viewer)
	if gaze != null:
		return can_see(gaze, target)
	if viewer.has_condition(Conditions.BLINDED):
		return _blindsense(viewer, target)
	if not eyes_reach(viewer, target.position):
		return _blindsense(viewer, target)
	if (target.hidden or target.is_invisible()) and not target.buff_flag("outlined"):
		if target.is_invisible() and not target.hidden and viewer.buff_flag("see_invisible"):
			return walk_map.has_line_of_sight(viewer.position, target.position)
		return _blindsense(viewer, target)
	return walk_map.has_line_of_sight(viewer.position, target.position)


## Gaze of Two Minds: the ally whose senses c uses (null = its own).
func _gaze_partner(c: Combatant) -> Combatant:
	for entry in c.conditions:
		if entry.has("gaze"):
			var ally := get_combatant(str(entry["gaze"]))
			if ally != null and ally != c and ally.is_conscious():
				return ally
	return null


## Ends c's conditions flagged "ends_on_act" (One with Shadows) after it
## moved, acted or reacted.
func _end_on_act(c: Combatant) -> void:
	for entry: Dictionary in c.conditions.duplicate():
		if entry.get("ends_on_act", false) == true:
			_remove_condition(c, entry)


## Round C light: whether viewer's sight reaches `tile` through the dark.
## Blindsight / truesight within range always do. Magical darkness (a tile
## effect with "darkness", on the tile or around the viewer) blocks every
## other sight but Devil's Sight (120 ft). In a "dark" fight a tile is seen
## when lit (a "lit" tile effect: Light, Daylight, Dancing Lights) or within
## the viewer's darkvision (ancestry, stat block, Darkvision spell, Devil's
## Sight). Bright and dim fights: always.
func eyes_reach(viewer: Combatant, tile: Vector2i) -> bool:
	var dist := GridMath.distance_tiles(viewer.position, tile)
	var keen := maxi(viewer.sheet.truesight_ft, viewer.sheet.blindsight_ft)
	if keen > 0 and dist <= GridMath.feet_to_tiles(keen):
		return true
	var devils := viewer.sheet.invocations.has("devils_sight") and dist <= DEVILS_SIGHT_TILES
	if _tile_dark_magic(tile) or _tile_dark_magic(viewer.position):
		return devils
	if light != LIGHT_DARK or _tile_lit(tile):
		return true
	var dv := viewer.darkvision_tiles()
	return dv > 0 and dist <= dv


## A tile inside magical darkness (the Darkness spell).
func _tile_dark_magic(tile: Vector2i) -> bool:
	for fx in tile_effects:
		if fx.get("darkness", false) == true and _effect_covers(fx, tile):
			return true
	return false


## A tile lit by a light effect (Light, Daylight, Continual Flame, Dancing Lights).
func _tile_lit(tile: Vector2i) -> bool:
	for fx in tile_effects:
		if fx.get("lit", false) == true and _effect_covers(fx, tile):
			return true
	return false


## Blindsense (rogue 14): aware of hidden / invisible creatures within 2 tiles.
func _blindsense(viewer: Combatant, target: Combatant) -> bool:
	return viewer.sheet.has_feature("blindsense") and not viewer.has_condition(Conditions.DEAFENED) \
			and GridMath.distance_tiles(viewer.position, target.position) <= BLINDSENSE_TILES


## Feral Senses (ranger 18): no disadvantage attacking a creature it cannot see.
func _senses_unseen(attacker: Combatant, _target: Combatant) -> bool:
	return attacker.sheet.has_feature("feral_senses") and not attacker.has_condition(Conditions.BLINDED)


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
## Bardic Inspiration adds its die to the roll, Sacred Weapon its bonus, Bless /
## Bane their dice; Rage, Hex / Hunter's Mark, Sneak Attack, Colossus Slayer,
## Divine Smite, Improved Divine Smite, Divine Strike, Lifedrinker, Divine Favor,
## Branding Smite and Brutal Critical add damage (AttackResolver extras).
## Improved / Superior Critical crit on 19-20 / 18-20. Before the roll a
## Sanctuary ward may stop the attack (attack_lost) and Protection may impose
## disadvantage; after a hit the target's reactions (Shield, Cutting Words,
## Deflect Missiles, Uncanny Dodge) may turn it into a miss or reduce it; after
## damage Hellish Rebuke and Fire Shield answer. opts: {"bonus_source",
## "smite", "stun", "technique", "opportunity", "spell_bonus" (flat damage added
## once: Elemental Affinity / Empowered Evocation), "no_reactions"}.
func _roll_attack(attacker: Combatant, target: Combatant, attack: Dictionary, bonus: bool, spell: SpellDefinition, opts: Dictionary = {}) -> AttackResult:
	var kind := str(attack.get("kind", "melee"))
	var weapon := spell == null
	var ranged := Encounter.is_ranged_attack(attack)
	if not target.illusion.is_empty() and attacker.team != target.team:
		_illusion_interaction(attacker, target)
		var wasted := AttackResult.new()
		wasted.attacker_name = attacker.display_name
		wasted.target_name = target.display_name
		return wasted
	if _sanctuary_blocks(attacker, target) or (weapon and ranged and _wind_blocks(attacker, target)):
		var lost := AttackResult.new()
		lost.attacker_name = attacker.display_name
		lost.target_name = target.display_name
		lost.target_hp_after = target.sheet.current_hp
		return lost
	var protected := _protection_reaction(attacker, target)
	if protected:
		opts = opts.duplicate()
		opts["protected"] = true
	var m := _attack_mode(attacker, target, attack, weapon, opts)
	var mode: D20.RollMode = m["mode"]
	var extra_to_hit := 0
	if attacker.inspiration_die > 0:
		extra_to_hit = rng.next_int(1, attacker.inspiration_die)
		_emit("inspiration_used", {"actor": attacker.id, "source": attacker.inspiration_source, "die": attacker.inspiration_die, "roll": extra_to_hit})
		attacker.inspiration_die = 0
		attacker.inspiration_source = ""
	if weapon:
		extra_to_hit += attacker.sacred_weapon_bonus + attacker.buff_int("weapon_bonus")
	for b: Dictionary in attacker.buffs.duplicate():
		if str(b.get("advantage_vs", "")) == target.id:
			_remove_buff(attacker, b)
	extra_to_hit += _d20_dice_bonus(attacker, "attack_dice") - attacker.sheet.resurrection_penalty
	if not target.helped_by.is_empty() and target.help_team == attacker.team:
		target.helped_by = ""
		target.help_team = -1
	var damage_type := str(attack.get("damage_type", ""))
	var extras: Array[Dictionary] = []
	var melee_weapon := weapon and not ranged
	if weapon and attacker.raging and not ranged and str(attack.get("ability", "STR")) == "STR":
		extras.append({"source": "rage", "dice": str(Encounter.rage_damage(attacker.sheet)), "type": damage_type})
	if target.marks.has(attacker.id):
		var mark: Dictionary = target.marks[attacker.id]
		if weapon or mark.get("any_attack", true) == true:
			extras.append({"source": str(mark.get("effect", "")), "dice": str(mark.get("dice", "1d6")), "type": str(mark.get("type", damage_type))})
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
	if melee_weapon and attacker.sheet.has_feature("improved_divine_smite"):
		extras.append({"source": "improved_divine_smite", "dice": "1d8", "type": "radiant"})
	var divine_strike := false
	if weapon and attacker.sheet.has_feature("divine_strike") and attacker.divine_strike_turn != turn_counter:
		divine_strike = true
		extras.append({"source": "divine_strike", "dice": "2d8" if attacker.sheet.level >= 14 else "1d8", "type": "radiant"})
	if weapon and attack.get("pact_weapon", false) == true and attacker.sheet.invocations.has("lifedrinker"):
		extras.append({"source": "lifedrinker", "dice": str(maxi(1, attacker.sheet.ability_modifier(Ability.Type.CHA))), "type": "necrotic", "no_crit_double": true})
	if weapon:
		for b in attacker.buffs:
			var wd := str(b.get("weapon_damage_dice", ""))
			if not wd.is_empty():
				extras.append({"source": str(b.get("effect", "")), "dice": wd, "type": str(b.get("weapon_damage_type", damage_type))})
	var next_hit: Dictionary = {}
	if weapon:
		for b in attacker.buffs:
			if not str(b.get("next_hit_dice", "")).is_empty():
				next_hit = b
				extras.append({"source": str(b.get("effect", "")), "dice": str(b["next_hit_dice"]), "type": str(b.get("next_hit_type", damage_type))})
				break
	if melee_weapon and attacker.sheet.has_feature("brutal_critical"):
		var die := Encounter._first_die(str(attack.get("damage", "")))
		if die > 0:
			var n := attacker.sheet.table_int("brutal_critical_dice", 3 if attacker.sheet.level >= 17 else (2 if attacker.sheet.level >= 13 else 1))
			extras.append({"source": "brutal_critical", "dice": "%dd%d" % [n, die], "type": damage_type, "crit_only": true, "no_crit_double": true})
	var spell_bonus := DictUtil.to_int(opts.get("spell_bonus", 0), 0)
	if spell_bonus != 0:
		extras.append({"source": str(opts.get("spell_bonus_source", "")), "dice": str(spell_bonus), "type": damage_type, "no_crit_double": true})
	var half_on_miss := spell != null and spell.half_on_miss
	var crit_min := 20
	if weapon and attacker.sheet.has_feature("superior_critical"):
		crit_min = 18
	elif weapon and attacker.sheet.has_feature("improved_critical"):
		crit_min = 19
	var auto_crit: bool = m["auto_crit"]
	var rolled_attack := attack.duplicate()
	if target.sheet.has_feature("multiattack_defense") and DictUtil.to_int(target.defended_against.get(attacker.id, -1), -1) == turn_counter:
		rolled_attack["target_ac_bonus"] = MULTIATTACK_DEFENSE_AC
	if weapon and (attacker.buff_flag("weapon_magical") or attacker.sheet.has_feature("ki_empowered_strikes") and attack.get("unarmed", false) == true):
		rolled_attack["magical"] = true
	if weapon and attack.get("unarmed", false) == true and attacker.buff_int("unarmed_die") > Encounter._first_die(str(attack.get("damage", ""))):
		var ability := Ability.from_string(str(attack.get("ability", "STR")))
		rolled_attack["damage"] = "1d%d" % attacker.buff_int("unarmed_die") + CharacterBuilder.signed(attacker.sheet.ability_modifier(maxi(0, ability)))
		rolled_attack["magical"] = true
	if attacker.antimagic:
		rolled_attack["magical"] = false
	if _mirror_image_absorbs(attacker, target, mode):
		var fooled := AttackResult.new()
		fooled.attacker_name = attacker.display_name
		fooled.target_name = target.display_name
		fooled.target_hp_after = target.sheet.current_hp
		return fooled
	var r := AttackResolver.roll(attacker, target, rolled_attack, rng, mode, auto_crit, extra_to_hit, extras, half_on_miss, crit_min)
	if attacker.raging and target.team != attacker.team:
		attacker.rage_kept = true
	_luck_and_foe_slayer(attacker, target, rolled_attack, r, extras)
	if r.hit and weapon and attacker.buff_flag("half_str_damage") and str(attack.get("ability", "STR")) == "STR":
		r.damage_total = floori(r.damage_total / 2.0)
	if r.hit and weapon:
		for pd in attacker.buff_dice("weapon_damage_penalty_dice"):
			r.damage_total = maxi(0, r.damage_total - DiceExpr.parse(pd).roll(rng).total)
	if r.hit and not DictUtil.to_bool(opts.get("no_reactions", false), false):
		_on_hit_reactions(attacker, target, r, spell)
	if sneak and r.hit:
		attacker.sneak_attack_turn = turn_counter
	if colossus and r.hit:
		attacker.colossus_turn = turn_counter
	if divine_strike and r.hit:
		attacker.divine_strike_turn = turn_counter
	if r.hit and not next_hit.is_empty():
		_remove_buff(attacker, next_hit)
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
	if (r.hit or r.damage_total > 0) and attack.get("no_damage", false) != true:
		var amount := r.damage_total
		if r.hit and amount > 0:
			amount = _reaction_reduction(attacker, target, weapon, ranged, amount)
		var outcome := _take_damage(target, amount, r.critical)
		r.damage_total = outcome.amount
		r.target_hp_after = target.sheet.current_hp
		r.target_dropped = outcome.dropped_to_zero
		r.target_died = outcome.died
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
		if r.hit:
			_after_hit_by(attacker, target, melee_weapon or (spell != null and spell.melee), r.damage_total)
	elif not r.hit and not ranged:
		_stand_against_the_tide(attacker, target, attack, spell)
		if not attacker.is_summon() and spell == null:
			_melee_answer(attacker, target, false)
	if not target.is_conscious():
		target.dodging = false
	if weapon and smite > 0 and r.hit:
		attacker.sheet.use_spell_slot(smite)
		_emit("feature_used", {"actor": attacker.id, "feature": "divine_smite", "target": target.id, "remaining": attacker.sheet.slots_left(smite), "slot_level": smite})
	if r.hit and target.is_alive() and DictUtil.to_bool(opts.get("hurl_through_hell", false), false) \
			and attacker.sheet.spend_class_resource("hurl_through_hell", 1):
		_emit("feature_used", {"actor": attacker.id, "feature": "hurl_through_hell", "target": target.id, "remaining": 0})
		_banish(target, attacker.id, "hurl_through_hell", -1, false,
				{"source_turns": HURL_SOURCE_TURNS, "return_damage": {"dice": "10d10", "type": "psychic", "immune_types": ["fiend"], "feature": "hurl_through_hell"}})
	if weapon and r.hit and target.is_alive() and DictUtil.to_bool(opts.get("quivering_palm", false), false) \
			and attacker.sheet.spend_class_resource("ki", QUIVERING_PALM_KI):
		attacker.quivering_target = target.id
		_emit("feature_used", {"actor": attacker.id, "feature": "quivering_palm", "target": target.id, "remaining": attacker.sheet.class_resource("ki")})
		_emit("effect_applied", {"source": attacker.id, "target": target.id, "effect": "quivering_palm"})
	if weapon and r.hit and target.is_alive():
		if DictUtil.to_bool(opts.get("stun", false), false):
			_stunning_strike(attacker, target)
		var technique := str(opts.get("technique", ""))
		if not technique.is_empty() and target.is_alive():
			_open_hand_technique(attacker, target, technique)
	return r


## Foe Slayer (ranger 20, once per turn; policy key foe_slayer): a miss that
## the ranger's WIS modifier would turn into a hit hits, else a hit deals
## WIS more damage (lite: against any creature, favored enemies are not
## tracked). Stroke of Luck (rogue 20, once per short rest; policy key
## stroke_of_luck, trigger own_attack_missed): a miss becomes a hit.
## feature_used {actor, feature, target, remaining, mode ("attack" |
## "damage")}.
func _luck_and_foe_slayer(attacker: Combatant, target: Combatant, attack: Dictionary, r: AttackResult, extras: Array[Dictionary]) -> void:
	var wis := attacker.sheet.ability_modifier(Ability.Type.WIS)
	if attacker.sheet.has_feature("foe_slayer") and attacker.foe_slayer_turn != turn_counter and wis > 0 \
			and attacker.reaction_allowed("own_attack", "foe_slayer") and not attacker.is_summon():
		if not r.hit and not r.fumble and r.attack_total + wis >= r.target_ac:
			attacker.foe_slayer_turn = turn_counter
			r.attack_total += wis
			AttackResolver.force_hit(r, target, attack, rng, extras)
			_emit("feature_used", {"actor": attacker.id, "feature": "foe_slayer", "target": target.id, "remaining": 0, "mode": "attack"})
		elif r.hit:
			attacker.foe_slayer_turn = turn_counter
			var bonus := target.adjust_damage(wis, r.damage_type, true)
			r.damage_total += bonus
			r.extras.append({"source": "foe_slayer", "amount": bonus, "type": r.damage_type})
			_emit("feature_used", {"actor": attacker.id, "feature": "foe_slayer", "target": target.id, "remaining": 0, "mode": "damage"})
	if not r.hit and attacker.sheet.has_feature("stroke_of_luck") and attacker.sheet.class_resource("stroke_of_luck") > 0 \
			and attacker.reaction_allowed("own_attack_missed", "stroke_of_luck") and not attacker.is_summon():
		attacker.sheet.spend_class_resource("stroke_of_luck", 1)
		AttackResolver.force_hit(r, target, attack, rng, extras)
		_emit("feature_used", {"actor": attacker.id, "feature": "stroke_of_luck", "target": target.id, "remaining": 0, "mode": "attack"})


## Size of the first die in a damage formula ("1d8+3" -> 8; 0 = none).
static func _first_die(formula: String) -> int:
	var f := DiceFormula.parse(formula)
	if not f.valid or f.dice.is_empty():
		return 0
	return f.dice[0].sides

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
	var uncanny := target.sheet.has_feature("uncanny_dodge") or target.sheet.has_feature("superior_hunters_defense_uncanny_dodge")
	if weapon and ranged and target.sheet.has_feature("deflect_missiles") and target.reaction_allowed("creature_hit_me", "deflect_missiles"):
		feature = "deflect_missiles"
		reduced = rng.next_int(1, 10) + target.sheet.ability_modifier(Ability.Type.DEX) + target.sheet.level
	elif uncanny and can_see(target, attacker) and target.reaction_allowed("creature_hit_me", "uncanny_dodge"):
		feature = "uncanny_dodge"
		reduced = amount - floori(amount / 2.0)
	if feature.is_empty():
		return amount
	reduced = clampi(reduced, 0, amount)
	_use_reaction(target, feature, "creature_hit_me", {"source": attacker.id})
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
		_after_position_change(target, from, false)


# --- damage pipeline, conditions and concentration -------------------------------

## After damage to target (amount already applied): Turn Undead's turning ends,
## concentration is checked (CON save DC max(10, damage / 2)) or ends at 0 hp,
## and Dark One's Blessing gives the source temporary hit points when it
## dropped a hostile to 0.
func _after_damage(source: Combatant, target: Combatant, amount: int, dropped: bool) -> void:
	if amount <= 0 and not dropped:
		return
	if amount > 0 and target.is_conscious() and target.buff_flag("stunned_on_damage"):
		var stun_source := source.id if source != null else ""
		_apply_condition(target, Conditions.STUNNED, stun_source, Conditions.duration(Conditions.DURATION_TARGET_TURN_END), {"disease": "slimy_doom"})
	for entry: Dictionary in target.conditions.duplicate():
		if entry.get("ends_on_damage", false) == true:
			_remove_condition(target, entry)
		elif typeof(entry.get("save_on_damage", null)) == TYPE_DICTIONARY and target.is_conscious() and target.conditions.has(entry):
			var sod: Dictionary = entry["save_on_damage"]
			if _saving_throw(str(entry.get("source", "")), target, Ability.from_string(str(sod.get("ability", "WIS"))), DictUtil.to_int(sod.get("dc", 10), 10), {"vs_condition": str(entry.get("condition", ""))}):
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
	if amount > 0:
		for b: Dictionary in target.buffs.duplicate():
			var share := str(b.get("share_damage_with", ""))
			var partner := get_combatant(share)
			if partner != null and partner != target and partner.is_alive():
				var shared := _take_damage(partner, amount)
				_emit("damage", {"target": partner.id, "amount": shared.amount, "type": "", "hp_after": partner.sheet.current_hp,
						"dropped": shared.dropped_to_zero, "died": shared.died, "spell": str(b.get("spell", "warding_bond"))})
				_after_damage(null, partner, shared.amount, shared.dropped_to_zero)
				if not partner.is_alive() or not partner.is_conscious():
					_remove_buff(target, b)
		_damage_taken_reactions(source, target)
	if not target.is_conscious():
		_on_dropped(target)


## A creature at 0 hp: its hidden state and buffs end; a summon is dismissed
## (a companion leaves its owner's list when it dies).
func _on_dropped(target: Combatant) -> void:
	_reveal(target, "dropped")
	if target.is_summon():
		_dismiss(target, "dropped")


func _concentration_check(c: Combatant, damage: int) -> void:
	var dc := maxi(10, floori(damage / 2.0))
	var d := D20.roll(rng, D20.combine(false, c.sheet.exhaustion >= 3))
	var total := d.natural + c.sheet.save_modifier(Ability.Type.CON) + _save_flat_bonus(c, Ability.Type.CON) + _d20_dice_bonus(c, "save_dice")
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
		for b: Dictionary in other.buffs.duplicate():
			if str(b.get("source", "")) == c.id and str(b.get("spell", "")) == spell_id:
				_remove_buff(other, b)
		if other.marks.has(c.id):
			var mark: Dictionary = other.marks[c.id]
			if str(mark.get("spell", "")) == spell_id:
				other.marks.erase(c.id)
				_emit("effect_ended", {"target": other.id, "effect": str(mark.get("effect", ""))})
		if not other.form.is_empty() and str(other.form.get("source", "")) == c.id and str(other.form.get("spell", "")) == spell_id:
			_revert_form(other, "concentration")
	for fx: Dictionary in tile_effects.duplicate():
		if str(fx["source"]) == c.id and str(fx["spell"]) == spell_id and fx.get("concentration", false) == true:
			_end_tile_effect(fx, "concentration")
	for s in _summons_of(c.id):
		if s.summon_concentration and s.summon_spell == spell_id:
			_dismiss(s, "concentration")
	for other in tracker.order():
		if str(other.banished.get("source", "")) == c.id and str(other.banished.get("spell", "")) == spell_id \
				and other.banished.get("permanent", false) != true:
			_return(other, "concentration")


## Applies a condition (Conditions) with a duration; extra fields (spell, flee,
## ends_on_damage) are stored on the entry. A creature immune to it, or dead,
## is unaffected (false). The same condition from the same source is replaced.
## Emits condition_applied {target, condition, source, duration}.
func _apply_condition(target: Combatant, condition: String, source_id: String, duration: Dictionary, extra: Dictionary = {}) -> bool:
	if not target.is_alive() or target.is_immune_to_condition(condition) or duration.is_empty():
		return false
	if _condition_blocked(target, condition, source_id):
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
	_emit("condition_applied", {"target": target.id, "condition": condition, "source": source_id, "duration": duration.duplicate(), "turns_left": turns})
	_on_condition_added(target, entry)
	if Conditions.INCAPACITATING.has(condition):
		target.dodging = false
		_end_concentration(target, "incapacitated")
	if Conditions.IMMOBILIZING.has(condition):
		target.movement_remaining = 0
	return true


## Situational immunities: Aura of Devotion (charmed) / Aura of Courage
## (frightened) of a conscious paladin ally in range; Nature's Ward (charmed /
## frightened by elementals and fey).
func _condition_blocked(target: Combatant, condition: String, source_id: String) -> bool:
	if not condition in [Conditions.CHARMED, Conditions.FRIGHTENED]:
		return false
	var aura_feature := "aura_of_devotion" if condition == Conditions.CHARMED else "aura_of_courage"
	for p in tracker.order():
		if p.team == target.team and p.is_conscious() and p.sheet.has_feature(aura_feature) \
				and GridMath.distance_tiles(p.position, target.position) <= Encounter.aura_tiles(p.sheet):
			return true
	var src := get_combatant(source_id)
	if src != null and target.sheet.has_feature("natures_ward") and src.creature_type in ["elemental", "fey"]:
		return true
	return false


## Removes one entry and emits condition_ended {target, condition}.
func _remove_condition(target: Combatant, entry: Dictionary) -> void:
	if _remove_entry(target, entry):
		_emit("condition_ended", {"target": target.id, "condition": str(entry.get("condition", ""))})


func _remove_entry(target: Combatant, entry: Dictionary) -> bool:
	for i in range(target.conditions.size()):
		if is_same(target.conditions[i], entry):
			target.conditions.remove_at(i)
			_on_condition_removed(target, entry)
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

## Resolves a validated cast: spends the slot (or Mystic Arcanum / invocation
## use), sorcery points and the action; emits cast {actor, spell, target,
## slot_level, point?, targets?, metamagic?, sustain?}; a hostile within 12
## tiles may Counterspell it (spell_countered); then concentration starts and
## the effect resolves by type.
func _do_cast(actor: Combatant, intent: Dictionary) -> void:
	var spell := _spell_def(str(intent.get("spell", "")))
	_cast_meta = Encounter._metamagic_of(intent)
	_cast_intent = intent
	var meta := _cast_meta
	var sustain := _sustaining(actor, spell, intent)
	_maximize = DictUtil.to_bool(intent.get("overchannel", false), false)
	var free_cast := _mastery_free(actor, spell, intent) if not sustain else ""
	var slot := _cast_slot(actor, spell, intent)
	if free_cast == "signature_spell":
		actor.sheet.spend_class_resource(CharacterSheet.SIGNATURE_PREFIX + spell.id, 1)
	if slot > 0 and not sustain:
		if _arcanum_cast(actor, spell) and actor.sheet.slots_left(slot) <= 0:
			actor.sheet.spend_class_resource(CharacterSheet.ARCANUM_PREFIX + spell.id, 1)
		else:
			actor.sheet.use_spell_slot(slot)
	if not actor.sheet.is_spell_prepared(spell.id) and not sustain:
		var inv := _invocation_cast(actor, spell)
		if not inv.is_empty():
			actor.sheet.spend_class_resource(CharacterSheet.INVOCATION_PREFIX + inv, 1)
	if not meta.is_empty():
		actor.sheet.spend_class_resource("sorcery_points", Encounter._metamagic_cost(meta, spell))
	var cost := spell.sustain if sustain else spell.casting_time
	if cost == "bonus_action" or meta.has("quickened_spell"):
		actor.bonus_action_used = true
	else:
		actor.action_used = true
	var targets := _cast_targets(actor, intent)
	if _at_will_invocation(actor, spell, intent) == "chains_of_carceri":
		for t in targets:
			_feature_immunity["chains_of_carceri:" + t.id] = true
	var fx_spell := spell
	var fx_slot := slot
	var dup := _wish_duplicate(spell, intent)
	if dup != null:
		fx_spell = dup
		fx_slot = dup.level
	var single := not fx_spell.is_area() and not fx_spell.effect_type in [SpellDefinition.EFFECT_TELEPORT, SpellDefinition.EFFECT_SUMMON, SpellDefinition.EFFECT_HEAL_POOL]
	var cast_ev := {"actor": actor.id, "spell": spell.id, "target": targets[0].id if single else "", "slot_level": slot}
	if dup != null:
		cast_ev["duplicate"] = dup.id
	if not free_cast.is_empty():
		cast_ev["free_cast"] = free_cast
	if _maximize:
		cast_ev["overchannel"] = true
	if fx_spell.is_area() or GridMath.is_vec_arr(intent.get("point", null)):
		cast_ev["point"] = GridMath.vec_to_arr(_area_point(actor, fx_spell, intent))
	if single and targets.size() > 1:
		var ids: Array = []
		for t in targets:
			ids.append(t.id)
		cast_ev["targets"] = ids
	if not meta.is_empty():
		cast_ev["metamagic"] = meta.duplicate()
	if sustain:
		cast_ev["sustain"] = true
	_emit("cast", cast_ev)
	_after_own_cast(actor, fx_spell.is_harmful() or fx_spell.is_area())
	if sustain and str(spell.raw_effect.get("sustain_mode", "")) == "redirect":
		_redirect(actor, spell, intent)
		return
	if not sustain and not meta.has("subtle_spell") and spell.level > 0 and _counterspelled(actor, spell, slot):
		return
	if dup != null:
		var dup_intent := intent.duplicate(true)
		dup_intent["mode"] = str(intent.get("duplicate_mode", ""))
		_cast_intent = dup_intent
		_resolve_cast(actor, dup, fx_slot, dup_intent, targets, meta, false)
		return
	_resolve_cast(actor, spell, slot, intent, targets, meta, sustain)


## The effect half of a cast (after the slot, the cast event and Counterspell):
## concentration starts and the spell's effect resolves by type. Also used for
## the spell a Wish duplicates (at its own level).
func _resolve_cast(actor: Combatant, spell: SpellDefinition, slot: int, intent: Dictionary, targets: Array[Combatant], meta: Array[String], sustain: bool) -> void:
	if spell.concentration and not sustain:
		_start_concentration(actor, spell, slot)
	_set_one_roll_bonus(actor, spell)
	var empower := maxi(1, actor.sheet.ability_modifier(Ability.Type.CHA)) if meta.has("empowered_spell") else 0
	match spell.effect_type:
		SpellDefinition.EFFECT_NO_EFFECT:
			_emit("no_effect", {"actor": actor.id, "spell": spell.id, "reason": spell.no_effect_reason()})
			return
		SpellDefinition.EFFECT_WEAPON_ATTACK:
			_cast_weapon_attack(actor, spell, slot)
			return
		SpellDefinition.EFFECT_WISH:
			_cast_wish(actor, spell, intent, targets)
			return
		SpellDefinition.EFFECT_TIME_STOP:
			_cast_time_stop(actor, spell)
			return
		SpellDefinition.EFFECT_EXPLORATION:
			_cast_exploration(actor, spell, slot, intent, targets)
			return
		SpellDefinition.EFFECT_LINGERING:
			_cast_lingering(actor, spell, slot, intent, targets)
			return
		SpellDefinition.EFFECT_TELEPORT:
			_cast_teleport(actor, spell, intent)
			return
		SpellDefinition.EFFECT_SUMMON:
			_cast_summon(actor, spell, slot, intent)
			return
		SpellDefinition.EFFECT_HEAL_POOL:
			_cast_heal_pool(actor, spell)
			return
		SpellDefinition.EFFECT_ZONE:
			_cast_zone(actor, spell, slot, intent)
			return
		SpellDefinition.EFFECT_AREA_HEAL:
			_cast_area_heal(actor, spell, slot, intent)
			return
		SpellDefinition.EFFECT_SLEEP:
			_cast_sleep(actor, spell, slot, intent)
			return
	if spell.is_area():
		_cast_area(actor, spell, slot, intent, empower)
		return
	_blessed_healer_done = false
	for t in targets:
		if t != null and (t.is_alive() or spell.effect_type == SpellDefinition.EFFECT_REVIVE):
			_cast_single(actor, t, spell, slot, empower)
	if meta.has("twinned_spell"):
		var twin := get_combatant(str(intent.get("twin_target", "")))
		if twin != null and twin.is_alive():
			_cast_single(actor, twin, spell, slot, empower)


## After casting: a hidden caster is revealed and Invisibility (the spell)
## ends; a harmful spell also ends Sanctuary / Tranquility on the caster.
func _after_own_cast(actor: Combatant, harmful: bool) -> void:
	if actor.hidden:
		_reveal(actor, "cast")
	for entry: Dictionary in actor.conditions.duplicate():
		if entry.get("ends_on_attack", false) == true:
			_remove_condition(actor, entry)
	if harmful:
		_after_own_attack(actor)


## Counterspell (trigger spell_cast_in_range): the first hostile in
## initiative order within 12 tiles that can see the caster, has Counterspell
## prepared and a 3rd-level or higher slot, and whose policy allows it.
## It uses the spell's level slot when it has one (automatic success), else
## its lowest 3rd+ slot and a casting ability check DC 10 + spell level.
## Emits reaction_used and spell_countered {caster, spell, by} on success.
func _counterspelled(caster: Combatant, spell: SpellDefinition, _slot: int) -> bool:
	for h in tracker.order():
		if h.team == caster.team or not h.sheet.has_feature("spellcasting") and not h.sheet.is_spell_prepared("counterspell"):
			continue
		if not h.sheet.is_spell_prepared("counterspell") or GridMath.distance_tiles(h.position, caster.position) > COUNTERSPELL_RANGE_TILES:
			continue
		if not can_see(h, caster) or not _may_react(h, "spell_cast_in_range", "counterspell"):
			continue
		var use := h.sheet.lowest_available_slot(maxi(3, spell.level))
		if use == 0:
			use = h.sheet.lowest_available_slot(3)
		if use == 0:
			continue
		h.sheet.use_spell_slot(use)
		_use_reaction(h, "counterspell", "spell_cast_in_range", {"source": caster.id, "spell": spell.id, "slot_level": use})
		var countered := use >= spell.level
		if not countered:
			var res := ability_check(h, h.sheet.casting_ability, -1, 10 + spell.level, "counterspell")
			countered = res["success"] == true
		if countered:
			_emit("spell_countered", {"caster": caster.id, "spell": spell.id, "by": h.id})
			return true
		return false
	return false


## Elemental Affinity (CHA to one damage roll of the dragon ancestor's type)
## and Empowered Evocation (INT to one damage roll of a wizard evocation spell).
func _set_one_roll_bonus(actor: Combatant, spell: SpellDefinition) -> void:
	_one_roll_bonus = 0
	_one_roll_source = ""
	if actor.sheet.has_feature("elemental_affinity") and not spell.damage_type.is_empty() and spell.damage_type == Encounter.dragon_damage_type(actor.sheet):
		_one_roll_bonus += actor.sheet.ability_modifier(Ability.Type.CHA)
		_one_roll_source = "elemental_affinity"
	if actor.sheet.has_feature("empowered_evocation") and spell.school.to_lower() == "evocation" and actor.sheet.class_id == "wizard":
		_one_roll_bonus += actor.sheet.ability_modifier(Ability.Type.INT)
		_one_roll_source = "empowered_evocation" if _one_roll_source.is_empty() else _one_roll_source
	if spell.damage.is_empty():
		_one_roll_bonus = 0


## Takes the one-roll damage bonus (0 once used).
func _take_one_roll_bonus() -> int:
	var b := _one_roll_bonus
	_one_roll_bonus = 0
	return b


## The damage type of a sorcerer's dragon ancestor ("" = none).
static func dragon_damage_type(sheet: CharacterSheet) -> String:
	for f: String in DRAGON_DAMAGE.keys():
		if sheet.has_feature(f):
			return DRAGON_DAMAGE[f]
	return ""


## Resolves a single-target spell on target.
func _cast_single(actor: Combatant, target: Combatant, spell: SpellDefinition, slot: int, empower: int) -> void:
	if not target.illusion.is_empty() and target.team != actor.team:
		_illusion_interaction(actor, target)
		return
	var above := maxi(0, slot - spell.level)
	var mode := str(_cast_intent.get("mode", ""))
	match spell.effect_type:
		SpellDefinition.EFFECT_SPELL_ATTACK:
			var attack := _spell_attack(actor, spell, slot, empower)
			for _i in range(spell.rays_for(actor.sheet.level, slot)):
				if not target.is_alive():
					break
				var opts := {}
				if _one_roll_bonus != 0:
					opts = {"spell_bonus": _one_roll_bonus, "spell_bonus_source": _one_roll_source}
				var r := _roll_attack(actor, target, attack, false, spell, opts)
				if r.hit:
					_one_roll_bonus = 0
				if r.hit and spell.raw_effect.get("heal_caster", "") == "half" and r.damage_total > 0:
					_heal(actor.id, actor, floori(r.damage_total / 2.0))
				if r.hit and target.is_alive():
					_apply_rider(actor, target, spell)
					_spell_condition(actor, target, spell, false)
					_spell_effect_on(actor, target, spell, slot, mode)
					if spell.id == "eldritch_blast" and actor.sheet.invocations.has("repelling_blast"):
						_push(actor, target, REPELLING_BLAST_TILES)
		SpellDefinition.EFFECT_AUTO_HIT:
			var darts := spell.darts + spell.per_slot_darts * above
			if target.team != actor.team and _may_react(target, "creature_hit_me", "shield") and _reaction_slot(target, "shield", 1) > 0:
				_cast_shield(target, actor, _reaction_slot(target, "shield", 1))
			if target.has_buff("shield") and spell.id == "magic_missile":
				_deal_spell_damage(actor, target, 0, spell, {"darts": darts, "blocked": "shield"})
				return
			var formula := DiceFormula.parse(DiceFormula.maximized(spell.damage) if _maximize else spell.damage)
			var total := _take_one_roll_bonus()
			for _i in range(darts):
				total += target.adjust_damage(maxi(0, DictUtil.to_int(formula.roll(rng, actor.sheet.casting_modifier())["total"])), spell.damage_type, true)
			_deal_spell_damage(actor, target, total, spell, {"darts": darts})
		SpellDefinition.EFFECT_SAVE:
			if _sanctuary_blocks(actor, target):
				return
			var success := false
			if spell.raw_effect.get("auto_fail", false) != true:
				success = _saving_throw(actor.id, target, spell.save_ability, actor.sheet.spell_save_dc(), _save_opts(spell, target, mode))
			if not spell.damage.is_empty() and target.is_alive():
				var half := spell.on_save == "half" or (spell.level == 0 and actor.sheet.has_feature("potent_cantrip"))
				if not success or half:
					var rolled := _roll_spell_damage(actor, spell, slot, empower) + _take_one_roll_bonus()
					_deal_spell_damage(actor, target, target.adjust_damage(_save_damage(target, spell.save_ability, rolled, success, half), spell.damage_type, true), spell, {})
					_extra_spell_damage(actor, target, spell, slot, success, half)
			if not success and target.is_alive():
				_apply_rider(actor, target, spell)
				_spell_condition(actor, target, spell, true)
				_spell_effect_on(actor, target, spell, slot, mode)
		SpellDefinition.EFFECT_HEAL:
			var amount := _roll_heal(actor, target, spell, slot)
			_heal(actor.id, target, maxi(0, amount))
			_blessed_healer(actor, target, slot)
		SpellDefinition.EFFECT_TEMP_HP:
			var hf := spell.heal_formula(slot)
			var amount := maxi(0, DictUtil.to_int(DiceFormula.parse(str(hf["formula"])).roll(rng, actor.sheet.casting_modifier())["total"]))
			target.sheet.grant_temp_hp(amount)
			_emit("temp_hp", {"source": actor.id, "target": target.id, "amount": amount, "temp_hp_after": target.sheet.temp_hp, "spell": spell.id})
		SpellDefinition.EFFECT_BUFF:
			if spell.buff == SpellDefinition.BUFF_MAGE_ARMOR:
				if not target.sheet.active_buffs.has(SpellDefinition.BUFF_MAGE_ARMOR):
					target.sheet.active_buffs.append(SpellDefinition.BUFF_MAGE_ARMOR)
				_emit("effect_applied", {"source": actor.id, "target": target.id, "effect": SpellDefinition.BUFF_MAGE_ARMOR, "ac": target.sheet.armor_class()})
				return
			if spell.raw_effect.get("buff_on_caster", false) == true:
				_apply_spell_buff(actor, actor, spell, slot, mode, target)
				return
			if target.team != actor.team and spell.raw_effect.has("save"):
				if _saving_throw(actor.id, target, Ability.from_string(str(spell.raw_effect["save"])), actor.sheet.spell_save_dc(), _save_opts(spell, target, mode)):
					return
			if not spell.condition.is_empty():
				_spell_condition(actor, target, spell, false)
			if not spell.modifiers.is_empty() or not spell.modes.is_empty():
				var m := mode
				if m.is_empty() and spell.modes.has("reduce") and target.team != actor.team:
					m = "reduce"
				_apply_spell_buff(actor, target, spell, slot, m, target)
			elif spell.condition.is_empty():
				_apply_rider(actor, target, spell)
		SpellDefinition.EFFECT_MARK:
			var mark := {"effect": spell.rider, "dice": spell.damage, "type": spell.damage_type}
			if spell.raw_effect.get("weapon_only", false) == true:
				mark["any_attack"] = false
			if spell.concentration:
				mark["spell"] = spell.id
			target.marks[actor.id] = mark
			_emit("effect_applied", {"source": actor.id, "target": target.id, "effect": spell.rider})
		SpellDefinition.EFFECT_REVIVE:
			_revive(actor, target, spell)
		SpellDefinition.EFFECT_DISPEL:
			_dispel(actor, target, spell, slot)
		SpellDefinition.EFFECT_THRESHOLD:
			_threshold(actor, target, spell)
		SpellDefinition.EFFECT_FORCED_MOVE:
			_forced_move(actor, target, spell, _cast_intent)
		SpellDefinition.EFFECT_BANISH:
			_banish_spell(actor, target, spell, slot)
		SpellDefinition.EFFECT_TRANSFORM:
			var def := _transform_def(spell, target, _cast_intent)
			if def == null:
				return
			if target.team != actor.team and _saving_throw(actor.id, target, Ability.Type.WIS, actor.sheet.spell_save_dc(), _save_opts(spell, target, mode)):
				return
			_transform(target, def, str(spell.raw_effect.get("kind", "polymorph")), actor.id, spell.id if spell.concentration else "")


## Saving throw options for a spell's save: the condition it imposes (for
## Countercharm / Steel Will), plant spells (Land's Stride) and Heightened Spell.
func _save_opts(spell: SpellDefinition, target: Combatant, mode: String = "") -> Dictionary:
	var opts := {"vs_condition": _mode_condition(spell, mode)}
	if _cast_meta.has("heightened_spell") and str(_cast_intent.get("heightened_target", "")) == target.id:
		opts["heightened"] = true
	if spell.zone.get("plant", false) == true:
		opts["plant"] = true
	return opts


## A Dictionary field of a spell's effect, replaced by the cast mode's own
## (Contagion's diseases); {} when neither has it.
static func _mode_value(spell: SpellDefinition, mode: String, key: String) -> Dictionary:
	if not mode.is_empty() and spell.modes.has(mode):
		var m: Dictionary = spell.modes[mode]
		if typeof(m.get(key, null)) == TYPE_DICTIONARY:
			return (m[key] as Dictionary).duplicate(true)
	var v: Variant = spell.raw_effect.get(key, null)
	return (v as Dictionary).duplicate(true) if typeof(v) == TYPE_DICTIONARY else {}


## A save_track condition at the end of the target's turn (Contagion, Prismatic
## indigo): one save against the entry's DC; three successes end it
## (save_track_ended outcome "recovered"); three failures end the tracked
## condition and its "track_effect" takes hold for the encounter: modifiers as
## a buff and conditions ("ends_condition": the tracked condition ends too, else
## it stays): save_track_ended {target, condition, outcome: "took_hold", effect,
## label?}.
func _save_track(c: Combatant, entry: Dictionary) -> void:
	var duration: Dictionary = entry["duration"]
	var source_id := str(entry.get("source", ""))
	var condition := str(entry.get("condition", ""))
	var ok := _saving_throw(source_id, c, Ability.from_string(str(duration.get("ability", "CON"))), DictUtil.to_int(duration.get("dc", 10), 10), {"vs_condition": condition})
	if not c.conditions.has(entry):
		return
	if ok:
		duration["successes"] = DictUtil.to_int(duration.get("successes", 0), 0) + 1
	else:
		duration["failures"] = DictUtil.to_int(duration.get("failures", 0), 0) + 1
	if DictUtil.to_int(duration["successes"]) >= 3:
		_remove_condition(c, entry)
		_emit("save_track_ended", {"target": c.id, "condition": condition, "outcome": "recovered"})
		return
	if DictUtil.to_int(duration["failures"]) < 3:
		return
	var track_v: Variant = entry.get("track_effect", {})
	var track: Dictionary = track_v if typeof(track_v) == TYPE_DICTIONARY else {}
	var spell_id := str(entry.get("cast_spell", entry.get("spell", "")))
	var effect := str(track.get("effect", spell_id))
	var ev := {"target": c.id, "condition": condition, "outcome": "took_hold", "effect": effect}
	if track.has("label"):
		ev["label"] = str(track["label"])
	if track.get("ends_condition", false) == true:
		_remove_condition(c, entry)
	else:
		entry["duration"] = Conditions.duration(Conditions.DURATION_ENCOUNTER)
	_emit("save_track_ended", ev)
	var mods_v: Variant = track.get("modifiers", {})
	var mods: Dictionary = mods_v if typeof(mods_v) == TYPE_DICTIONARY else {}
	if not mods.is_empty():
		_apply_buff(c, effect, source_id, Conditions.duration(Conditions.DURATION_ENCOUNTER), mods, spell_id)
	for cond in DictUtil.to_string_array(track.get("conditions", [])):
		if c.is_alive():
			_apply_condition(c, cond, source_id, Conditions.duration(Conditions.DURATION_ENCOUNTER), {"cast_spell": spell_id})


## The condition a spell applies in a mode (modes may replace it).
func _mode_condition(spell: SpellDefinition, mode: String) -> String:
	if not mode.is_empty() and spell.modes.has(mode):
		var m: Dictionary = spell.modes[mode]
		if m.has("condition"):
			return str(m["condition"])
	return spell.condition


## A second damage type (Flame Strike's radiant, Ice Storm's cold): rolled and
## applied separately with the same save outcome.
func _extra_spell_damage(actor: Combatant, target: Combatant, spell: SpellDefinition, _slot: int, success: bool, half: bool) -> void:
	for extra in spell.extra_damage:
		if not target.is_alive():
			return
		var rolled := maxi(0, DictUtil.to_int(DiceFormula.parse(str(extra["damage"])).roll(rng, actor.sheet.casting_modifier())["total"]))
		var dtype := str(extra["damage_type"])
		var amount := target.adjust_damage(_save_damage(target, spell.save_ability, rolled, success, half), dtype, true)
		_deal_effect_damage(actor, target, amount, dtype, {"spell": spell.id})


## Heal amount: the spell's dice at slot (+ casting modifier), Disciple of
## Life (+2 + slot level), Beacon of Hope (maximum dice).
func _roll_heal(actor: Combatant, target: Combatant, spell: SpellDefinition, slot: int) -> int:
	var hf := spell.heal_formula(slot)
	var formula := DiceFormula.parse(str(hf["formula"]))
	var amount := 0
	if target.buff_flag("max_healing") or actor.sheet.has_feature("supreme_healing"):
		for d in formula.dice:
			amount += d.count * d.sides
		amount += formula.constant + actor.sheet.casting_modifier() * formula.mod_count
	else:
		amount = maxi(0, DictUtil.to_int(formula.roll(rng, actor.sheet.casting_modifier())["total"]))
	if hf["add_mod"] == true:
		amount += actor.sheet.casting_modifier()
	if spell.level >= 1 and actor.sheet.has_feature("disciple_of_life"):
		amount += 2 + slot
	return amount


## Blessed Healer: healing another creature with a 1st-level or higher spell
## also heals the cleric 2 + the spell's level (once per casting).
func _blessed_healer(actor: Combatant, target: Combatant, slot: int) -> void:
	if target == actor or slot < 1 or _blessed_healer_done or not actor.sheet.has_feature("blessed_healer"):
		return
	_blessed_healer_done = true
	_heal(actor.id, actor, 2 + slot)


## Effects a spell puts on a creature it hit / that failed its save: the
## "apply_effect" buff, damage over time ("dot") and Bestow Curse's mark.
func _spell_effect_on(actor: Combatant, target: Combatant, spell: SpellDefinition, slot: int, mode: String) -> void:
	if not target.is_alive():
		return
	if not spell.modifiers.is_empty() and spell.effect_type != SpellDefinition.EFFECT_BUFF:
		_apply_spell_buff(actor, target, spell, slot, mode, target)
	if not spell.dot.is_empty():
		var dot := spell.dot
		var dice := str(dot.get("dice", "1d6"))
		var per := str(dot.get("per_slot_level_above", ""))
		if not per.is_empty() and slot > spell.level:
			dice = DiceFormula.plus(dice, per, slot - spell.level)
		var mods := {"dot_dice": dice, "dot_type": str(dot.get("type", spell.damage_type)), "dot_trigger": str(dot.get("trigger", "end_turn")), "dot_once": dot.get("once", false) == true}
		if dot.has("save"):
			mods["dot_save"] = {"ability": str(dot["save"]), "dc": actor.sheet.spell_save_dc(), "ends": true}
		var duration := Conditions.duration(Conditions.DURATION_ENCOUNTER)
		if dot.get("once", false) == true:
			duration = Conditions.duration(Conditions.DURATION_ROUNDS, {"rounds": 1})
		_apply_buff(target, spell.id + "_dot", actor.id, duration, mods, spell.id)
	var curse_v: Variant = spell.raw_effect.get("curse_mark", null)
	if typeof(curse_v) == TYPE_DICTIONARY:
		var curse: Dictionary = curse_v
		var mark := {"effect": spell.id, "dice": str(curse.get("dice", "1d8")), "type": str(curse.get("type", "necrotic"))}
		if spell.concentration:
			mark["spell"] = spell.id
		target.marks[actor.id] = mark
		_emit("effect_applied", {"source": actor.id, "target": target.id, "effect": spell.id})


## Applies a spell's buff modifiers (mode-specific) to target. Placeholders:
## "MOD" (casting modifier), "DC" (spell save DC), "CASTER" (caster id),
## "TARGET" (the cast's target id). Aid adds max_hp_bonus_per_slot per slot
## above; temp_hp_dice is rolled; cure_conditions end. Duration: the effect's
## "duration" (save_ends uses its "save" and the caster's DC), else "rounds"
## (0 = the encounter; Extended Spell doubles).
func _apply_spell_buff(actor: Combatant, target: Combatant, spell: SpellDefinition, slot: int, mode: String, cast_target: Combatant) -> void:
	var mods := spell.modifiers_for(mode)
	for key: Variant in mods.keys():
		var v: Variant = mods[key]
		if typeof(v) == TYPE_STRING:
			match str(v):
				"MOD":
					mods[key] = actor.sheet.casting_modifier()
				"DC":
					mods[key] = actor.sheet.spell_save_dc()
				"CASTER":
					mods[key] = actor.id
				"TARGET":
					mods[key] = cast_target.id
	if mods.has("max_hp_bonus_per_slot"):
		mods["max_hp_bonus"] = DictUtil.to_int(mods.get("max_hp_bonus", 0), 0) + DictUtil.to_int(mods["max_hp_bonus_per_slot"], 0) * maxi(0, slot - spell.level)
		mods.erase("max_hp_bonus_per_slot")
	if not str(mods.get("temp_hp_dice", "")).is_empty():
		mods["temp_hp"] = maxi(0, DiceExpr.parse(str(mods["temp_hp_dice"])).roll(rng).total)
	mods.erase("temp_hp_dice")
	if mods.get("weapon_magical", false) == true:
		mods.erase("weapon_magical")
		mods["weapon_magical"] = true
	for c in DictUtil.to_string_array(mods.get("cure_conditions", [])):
		_end_conditions_named(target, c)
	mods.erase("cure_conditions")
	if str(mods.get("share_damage_with", "")) == target.id:
		mods.erase("share_damage_with")
	var duration := _spell_duration(actor, spell, str(spell.raw_effect.get("duration", "")), str(spell.raw_effect.get("save", "")))
	var applied := _apply_buff(target, spell.effect_id, actor.id, duration, mods, spell.id)
	if applied.get("images", 0) != 0:
		applied["images"] = DictUtil.to_int(applied["images"], 3)


## A duration for a spell effect: "save_ends" (save ability, caster's DC),
## another named duration, or the spell's rounds (0 = encounter), doubled by
## Extended Spell.
func _spell_duration(actor: Combatant, spell: SpellDefinition, named: String, save: String) -> Dictionary:
	if named == Conditions.DURATION_SAVE_ENDS:
		var ability := Ability.from_string(save)
		if ability < 0:
			ability = spell.save_ability
		if ability >= 0:
			return Conditions.duration(Conditions.DURATION_SAVE_ENDS, {"ability": Ability.abbreviation(ability), "dc": actor.sheet.spell_save_dc()})
	if not named.is_empty():
		var d := Conditions.normalize_duration(named)
		if not d.is_empty():
			return d
	if spell.rounds <= 0:
		return Conditions.duration(Conditions.DURATION_ENCOUNTER)
	return Conditions.duration(Conditions.DURATION_ROUNDS, {"rounds": spell.rounds * (2 if _cast_meta.has("extended_spell") else 1)})


## The attack dictionary of a spell attack (Agonizing Blast adds CHA to
## eldritch blast's damage, Eldritch Spear makes its range 300 ft; Empowered
## Spell rerolls low dice; Distant Spell doubles the range).
func _spell_attack(actor: Combatant, spell: SpellDefinition, slot: int, empower: int) -> Dictionary:
	var tiles := maxi(1, _spell_range(spell))
	var damage := spell.damage_formula(actor.sheet.level, slot)
	if _maximize and not damage.is_empty():
		damage = DiceFormula.maximized(damage)
	if spell.id == "eldritch_blast" and actor.sheet.invocations.has("agonizing_blast"):
		var cha := actor.sheet.ability_modifier(Ability.Type.CHA)
		if cha != 0:
			damage += CharacterBuilder.signed(cha)
	if spell.id == "eldritch_blast" and actor.sheet.invocations.has("eldritch_spear"):
		tiles = maxi(tiles, GridMath.feet_to_tiles(300))
	var attack := {
		"name": spell.display_name,
		"kind": "spell",
		"melee": spell.melee,
		"to_hit": actor.sheet.spell_attack_bonus(),
		"damage": damage if not damage.is_empty() else "0",
		"damage_type": spell.damage_type,
		"range_tiles": [tiles, tiles],
	}
	if damage.is_empty():
		attack["no_damage"] = true  # Contagion: the hit only applies the condition
	if empower > 0:
		attack["empower"] = empower
	return attack


## Rolls a spell's damage formula at slot (MOD = casting modifier).
func _roll_spell_damage(actor: Combatant, spell: SpellDefinition, slot: int, empower: int) -> int:
	var text := spell.damage_formula(actor.sheet.level, slot)
	var formula := DiceFormula.parse(DiceFormula.maximized(text) if _maximize else text)
	return maxi(0, DictUtil.to_int(formula.roll(rng, actor.sheet.casting_modifier(), false, 0, empower)["total"]))


## Applies the spell's condition(s) (if any). Default duration: save_ends with
## the spell's save and the caster's DC for save spells, else 10 rounds
## (Extended Spell doubles rounds). Tied to the caster's concentration when
## the spell needs it. Effect flags: condition_ends_on_damage,
## condition_ends_on_attack, condition_flee; "extra_conditions" (prone lasts
## until the creature stands, others share the duration).
func _spell_condition(actor: Combatant, target: Combatant, spell: SpellDefinition, from_save: bool) -> void:
	var mode := str(_cast_intent.get("mode", ""))
	var condition := _mode_condition(spell, mode)
	if condition.is_empty() or not target.is_alive():
		return
	var duration := spell.condition_duration.duplicate()
	if duration.is_empty():
		duration = {"type": Conditions.DURATION_SAVE_ENDS} if from_save and spell.save_ability >= 0 else Conditions.duration(Conditions.DURATION_ROUNDS, {"rounds": SpellDefinition.DEFAULT_CONDITION_ROUNDS})
	if str(duration.get("type", "")) == Conditions.DURATION_SAVE_ENDS and not duration.has("ability"):
		if spell.save_ability < 0:
			duration = Conditions.duration(Conditions.DURATION_ROUNDS, {"rounds": SpellDefinition.DEFAULT_CONDITION_ROUNDS})
		else:
			duration = Conditions.duration(Conditions.DURATION_SAVE_ENDS, {"ability": Ability.abbreviation(spell.save_ability), "dc": actor.sheet.spell_save_dc()})
	if str(duration.get("type", "")) == Conditions.DURATION_ROUNDS and _cast_meta.has("extended_spell"):
		duration["rounds"] = DictUtil.to_int(duration.get("rounds", 1), 1) * 2
	var extra := {"spell": spell.id} if spell.concentration else {}
	extra["cast_spell"] = spell.id
	if str(duration.get("type", "")) == Conditions.DURATION_SAVE_TRACK:
		if not duration.has("dc"):
			duration["dc"] = actor.sheet.spell_save_dc()
		var track := Encounter._mode_value(spell, mode, "track_effect")
		if not track.is_empty():
			extra["track_effect"] = track
	for flag: String in ["ends_on_damage", "ends_on_attack", "flee"]:
		if spell.raw_effect.get("condition_" + flag, false) == true:
			extra[flag] = true
	if spell.raw_effect.get("condition_save_on_damage", false) == true and spell.save_ability >= 0:
		extra["save_on_damage"] = {"ability": Ability.abbreviation(spell.save_ability), "dc": actor.sheet.spell_save_dc()}
	if condition == Conditions.COMPELLED:
		extra["toward"] = _cast_intent["point"] if GridMath.is_vec_arr(_cast_intent.get("point", null)) else GridMath.vec_to_arr(actor.position)
	_apply_condition(target, condition, actor.id, duration, extra)
	var extras := spell.extra_conditions
	if not mode.is_empty() and spell.modes.has(mode) and (spell.modes[mode] as Dictionary).has("extra_conditions"):
		extras = DictUtil.to_string_array((spell.modes[mode] as Dictionary)["extra_conditions"])
	for c in extras:
		if not target.is_alive():
			return
		var d := Conditions.duration(Conditions.DURATION_ENCOUNTER) if c == Conditions.PRONE else duration
		_apply_condition(target, c, actor.id, d, extra)


## Area spells: every living, targetable creature (any team) on a covered
## tile, the caster excluded from its own self-centred areas. Emits
## area_effect {caster, spell, point, shape, size_tiles, affected, sculpted};
## then per creature a save (+ damage) or an attack. Sculpted allies (Sculpt
## Spells) are left out entirely; Careful Spell allies succeed automatically
## (save event with "careful": true). Damage of an area save is rolled once for
## all targets (+ Elemental Affinity / Empowered Evocation); Evasion applies.
func _cast_area(actor: Combatant, spell: SpellDefinition, slot: int, intent: Dictionary, empower: int) -> void:
	var point := _area_point(actor, spell, intent)
	var size := spell.area_size_tiles()
	var covered := AreaOfEffect.tiles(spell.area_shape, size, actor.position, point, walk_map)
	var sculpt := DictUtil.to_string_array(intent.get("sculpt", []))
	var careful := DictUtil.to_string_array(intent.get("careful", []))
	var affected: Array[Combatant] = []
	var affected_ids: Array = []
	var sculpted: Array = []
	var warded: Array = []
	for c in tracker.order():
		if not c.is_alive() or c.untargetable or not covered.has(c.position):
			continue
		if not c.illusion.is_empty():
			continue
		if c == actor and Encounter._self_centred(spell):
			continue
		if sculpt.has(c.id):
			sculpted.append(c.id)
			continue
		if not _spell_warded(actor, c, spell).is_empty():
			warded.append(c.id)
			continue
		if c.team == actor.team and str(spell.raw_effect.get("affects", "all")) == "hostiles":
			for cond in DictUtil.to_string_array(spell.raw_effect.get("allies_cure", [])):
				_end_conditions_named(c, cond)
			continue
		affected.append(c)
		affected_ids.append(c.id)
	var area_ev := {
		"caster": actor.id, "spell": spell.id, "point": GridMath.vec_to_arr(point), "shape": spell.area_shape,
		"size_tiles": size, "affected": affected_ids, "sculpted": sculpted,
	}
	if not warded.is_empty():
		area_ev["warded"] = warded
	_emit("area_effect", area_ev)
	var mode := str(intent.get("mode", ""))
	if spell.raw_effect.get("prismatic", false) == true:
		_prismatic_spray(actor, spell, affected, careful)
		return
	if spell.effect_type == SpellDefinition.EFFECT_AREA_ATTACK:
		var attack := _spell_attack(actor, spell, slot, empower)
		attack["range_tiles"] = [999, 999]
		for t in affected:
			if t.is_alive():
				var r := _roll_attack(actor, t, attack, false, spell)
				if r.hit and t.is_alive():
					_spell_condition(actor, t, spell, false)
					_spell_effect_on(actor, t, spell, slot, mode)
		return
	var rolled := 0
	if not spell.damage.is_empty():
		rolled = _roll_spell_damage(actor, spell, slot, empower) + _take_one_roll_bonus()
	var half := spell.on_save == "half"
	for t in affected:
		if not t.is_alive():
			continue
		var success := false
		if careful.has(t.id):
			success = true
			_emit("save", {"actor": actor.id, "target": t.id, "ability": Ability.abbreviation(spell.save_ability), "dc": actor.sheet.spell_save_dc(),
					"natural": 0, "total": 0, "success": true, "careful": true})
		else:
			success = _saving_throw(actor.id, t, spell.save_ability, actor.sheet.spell_save_dc(), _save_opts(spell, t, mode))
		if not spell.damage.is_empty():
			var amount := _save_damage(t, spell.save_ability, rolled, success, half)
			if amount > 0 or not success:
				_deal_spell_damage(actor, t, t.adjust_damage(amount, spell.damage_type, true), spell, {})
			_extra_spell_damage(actor, t, spell, slot, success, half)
		if not success and t.is_alive():
			_spell_condition(actor, t, spell, true)
			_spell_effect_on(actor, t, spell, slot, mode)
			if spell.push_tiles > 0:
				_push(actor, t, spell.push_tiles)


## Lingering area: tiles from the spell's area at the point (a wall: a line
## through the point across the caster's line of sight, or to "wall_end";
## anchored to the caster: around it). See _create_tile_effect.
func _cast_zone(actor: Combatant, spell: SpellDefinition, slot: int, intent: Dictionary) -> void:
	var point := _area_point(actor, spell, intent)
	var size := spell.area_size_tiles()
	var anchor := ""
	if str(spell.zone.get("anchor", "")) == "caster":
		anchor = actor.id
		point = actor.position
	var cells := _zone_cells(actor, spell, point, size, intent)
	var fx := _create_tile_effect(actor, spell, slot, cells, anchor, point)
	if _cast_meta.has("extended_spell") and DictUtil.to_int(fx.get("turns_left", -1), -1) > 0:
		fx["turns_left"] = DictUtil.to_int(fx["turns_left"]) * 2


## The tiles a zone spell covers: a wall line, a sphere around an anchored
## caster, a ring (Forcecage: the tiles exactly `size` away), raw tiles
## ("cells": "raw", walls included: Passwall's passage, Move Earth's square),
## else the spell's area.
func _zone_cells(actor: Combatant, spell: SpellDefinition, point: Vector2i, size: int, intent: Dictionary) -> Array[Vector2i]:
	var z := spell.zone
	var out: Array[Vector2i] = []
	if z.get("wall", false) == true:
		var end := GridMath.arr_to_vec(intent["wall_end"]) if GridMath.is_vec_arr(intent.get("wall_end", null)) else Vector2i(-1, -1)
		return _wall_tiles(actor.position, point, size, end)
	if str(z.get("anchor", "")) == "caster":
		return AreaOfEffect.tiles("sphere", size, point, point, walk_map)
	match str(z.get("cells", "")):
		"ring":
			var r := maxi(1, size)
			for y in range(point.y - r, point.y + r + 1):
				for x in range(point.x - r, point.x + r + 1):
					var p := Vector2i(x, y)
					if GridMath.distance_tiles(p, point) == r and region.has_point(p):
						out.append(p)
			return out
		"raw":
			if spell.area_shape == "line":
				var d := point - actor.position
				var step := Vector2i(signi(d.x), signi(d.y))
				if step == Vector2i.ZERO:
					step = Vector2i(1, 0)
				for k in range(maxi(1, size)):
					var p := point + step * k
					if region.has_point(p):
						out.append(p)
				return out
			for y in range(point.y - size, point.y + size + 1):
				for x in range(point.x - size, point.x + size + 1):
					var p := Vector2i(x, y)
					if region.has_point(p):
						out.append(p)
			return out
	return AreaOfEffect.tiles(spell.area_shape, size, actor.position, point, walk_map)


## Tiles of a wall `length` tiles long through `point`: to `end` when given,
## else across the caster -> point direction, centred on point.
func _wall_tiles(origin: Vector2i, point: Vector2i, length: int, end: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if end.x >= 0:
		for p in WalkMap.line_cells(point, end):
			if out.size() > length:
				break
			if region.has_point(p) and walk_map.is_walkable(p):
				out.append(p)
		return out
	var dir := point - origin
	var perp := Vector2i(-signi(dir.y), signi(dir.x))
	if perp == Vector2i.ZERO:
		perp = Vector2i(1, 0)
	var half := floori(length / 2.0)
	for k in range(-half, length - half):
		var p := point + perp * k
		if region.has_point(p) and walk_map.is_walkable(p):
			out.append(p)
	return out


## Misty Step / Dimension Door: teleports to "point"; without one the caster
## gets teleport movement for this turn (move {"mode": "teleport"}).
func _cast_teleport(actor: Combatant, spell: SpellDefinition, intent: Dictionary) -> void:
	if GridMath.is_vec_arr(intent.get("point", null)):
		_teleport(actor, GridMath.arr_to_vec(intent["point"]), spell.id)
		check_end()
		return
	actor.teleport_tiles = _teleport_tiles(spell)
	_emit("effect_applied", {"source": actor.id, "target": actor.id, "effect": "teleport", "spell": spell.id, "tiles": actor.teleport_tiles})


## Summons near "point" (default: the caster): "form" picks the creature;
## the number comes from the spell's "count" table by challenge rating times
## its "slot_multiplier", or count_base + count_per_slot per slot above.
func _cast_summon(actor: Combatant, spell: SpellDefinition, slot: int, intent: Dictionary) -> void:
	var near := GridMath.arr_to_vec(intent["point"]) if GridMath.is_vec_arr(intent.get("point", null)) else actor.position
	var rounds := DictUtil.to_int(spell.raw_effect.get("rounds", 0), 0)
	if rounds > 0 and _cast_meta.has("extended_spell"):
		rounds *= 2
	var limit := rounds if rounds > 0 else -1
	var extra := {"concentration": spell.concentration, "familiar": spell.raw_effect.get("familiar", false) == true}
	var custom := str(spell.raw_effect.get("custom", ""))
	if custom == "illusion":
		_cast_illusion(actor, spell, near, limit, extra, intent)
		return
	if not custom.is_empty():
		extra["untargetable"] = spell.raw_effect.get("targetable", false) != true
		for _i in range(Encounter.summon_count(spell, null, slot)):
			_summon(actor, spell.id, null, near, limit, extra, _spiritual_weapon_custom(actor, slot, custom))
		return
	var def := _summon_def(spell, str(intent.get("form", spell.raw_effect.get("monster", ""))), slot)
	if def == null:
		return
	for _i in range(Encounter.summon_count(spell, def, slot)):
		_summon(actor, spell.id, def, near, limit, extra)


## Creatures one summon casting brings (see _cast_summon).
static func summon_count(spell: SpellDefinition, def: MonsterDefinition, slot: int) -> int:
	var e := spell.raw_effect
	if e.has("count_base"):
		return DictUtil.to_int(e["count_base"], 1) + DictUtil.to_int(e.get("count_per_slot", 0), 0) * maxi(0, slot - spell.level)
	if def == null:
		return 1
	var by_form_v: Variant = e.get("count_by_form", {})
	if typeof(by_form_v) == TYPE_DICTIONARY and (by_form_v as Dictionary).has(def.id):
		return DictUtil.to_int((by_form_v as Dictionary)[def.id], 1)
	var n := 1
	var table_v: Variant = e.get("count", {})
	if typeof(table_v) == TYPE_DICTIONARY:
		var table: Dictionary = table_v
		for key: Variant in table.keys():
			if is_equal_approx(DictUtil.to_float(key, -1.0), def.challenge_rating):
				n = DictUtil.to_int(table[key], 1)
	var mult := 1
	var mult_v: Variant = e.get("slot_multiplier", {})
	if typeof(mult_v) == TYPE_DICTIONARY:
		var mt: Dictionary = mult_v
		var best := 0
		for key: Variant in mt.keys():
			var lvl := DictUtil.to_int(key, 99)
			if lvl <= slot and lvl > best:
				best = lvl
				mult = DictUtil.to_int(mt[key], 1)
	return n * mult


## Mass Heal: the pool is split among living allies in range, the most hurt first.
func _cast_heal_pool(actor: Combatant, spell: SpellDefinition) -> void:
	var pool := DictUtil.to_int(spell.raw_effect.get("pool", 0), 0)
	var allies: Array[Combatant] = []
	for c in tracker.order():
		if c.team == actor.team and c.is_alive() and not c.untargetable and GridMath.distance_tiles(actor.position, c.position) <= maxi(1, _spell_range(spell)):
			allies.append(c)
	allies.sort_custom(func(a: Combatant, b: Combatant) -> bool:
		var ma := a.sheet.max_hp - a.sheet.current_hp
		var mb := b.sheet.max_hp - b.sheet.current_hp
		if ma != mb:
			return ma > mb
		return a.id < b.id)
	for c in allies:
		var need := c.sheet.hit_point_maximum() - c.sheet.current_hp
		if pool <= 0 or need <= 0:
			continue
		var give := mini(pool, need)
		pool -= give
		_heal(actor.id, c, give)


## Mass Cure Wounds: allies in the area (up to max_targets, the lowest hit
## points first, ties by id) each regain the rolled amount.
func _cast_area_heal(actor: Combatant, spell: SpellDefinition, slot: int, intent: Dictionary) -> void:
	var point := _area_point(actor, spell, intent)
	var covered := AreaOfEffect.tiles(spell.area_shape, spell.area_size_tiles(), actor.position, point, walk_map)
	var allies: Array[Combatant] = []
	for c in tracker.order():
		if c.team == actor.team and c.is_alive() and not c.untargetable and covered.has(c.position) and c.creature_type != "undead" and c.creature_type != "construct":
			allies.append(c)
	allies.sort_custom(func(a: Combatant, b: Combatant) -> bool:
		if a.sheet.current_hp != b.sheet.current_hp:
			return a.sheet.current_hp < b.sheet.current_hp
		return a.id < b.id)
	var ids: Array = []
	for c in allies.slice(0, spell.targets_at(slot)):
		ids.append(c.id)
	_emit("area_effect", {"caster": actor.id, "spell": spell.id, "point": GridMath.vec_to_arr(point), "shape": spell.area_shape,
			"size_tiles": spell.area_size_tiles(), "affected": ids, "sculpted": []})
	_blessed_healer_done = false
	for id_v: Variant in ids:
		var c := get_combatant(str(id_v))
		_heal(actor.id, c, _roll_heal(actor, c, spell, slot))
		_blessed_healer(actor, c, slot)


## Sleep / Color Spray: roll the hit point pool; creatures in the area, the
## lowest current hit points first (ties by id), fall unconscious (Sleep;
## wakes on damage) or are blinded until the caster's next turn (Color Spray)
## while the pool covers them. Sleep spares undead and charm-immune creatures.
func _cast_sleep(actor: Combatant, spell: SpellDefinition, slot: int, intent: Dictionary) -> void:
	var point := _area_point(actor, spell, intent)
	var covered := AreaOfEffect.tiles(spell.area_shape, spell.area_size_tiles(), actor.position, point, walk_map)
	var dice := str(spell.raw_effect.get("pool", "5d8"))
	var per := str(spell.raw_effect.get("per_slot_level_above", ""))
	if not per.is_empty() and slot > spell.level:
		dice = DiceFormula.plus(dice, per, slot - spell.level)
	var pool := maxi(0, DictUtil.to_int(DiceFormula.parse(dice).roll(rng)["total"]))
	var condition := str(spell.raw_effect.get("condition", Conditions.UNCONSCIOUS))
	var candidates: Array[Combatant] = []
	for c in tracker.order():
		if not c.is_conscious() or c.untargetable or c == actor or not covered.has(c.position):
			continue
		if c.has_condition(condition):
			continue
		if condition == Conditions.UNCONSCIOUS and (c.creature_type == "undead" or c.is_immune_to_condition(Conditions.CHARMED)):
			continue
		candidates.append(c)
	candidates.sort_custom(func(a: Combatant, b: Combatant) -> bool:
		if a.sheet.current_hp != b.sheet.current_hp:
			return a.sheet.current_hp < b.sheet.current_hp
		return a.id < b.id)
	var ids: Array = []
	for c in candidates:
		ids.append(c.id)
	_emit("area_effect", {"caster": actor.id, "spell": spell.id, "point": GridMath.vec_to_arr(point), "shape": spell.area_shape,
			"size_tiles": spell.area_size_tiles(), "affected": ids, "sculpted": [], "pool": pool})
	for c in candidates:
		if c.sheet.current_hp > pool:
			break
		pool -= c.sheet.current_hp
		if condition == Conditions.UNCONSCIOUS:
			_apply_condition(c, condition, actor.id, Conditions.duration(Conditions.DURATION_ROUNDS, {"rounds": SpellDefinition.DEFAULT_CONDITION_ROUNDS}), {"ends_on_damage": true})
		else:
			_apply_condition(c, condition, actor.id, Conditions.duration(Conditions.DURATION_SOURCE_NEXT_TURN))


## Revivify: a creature dead for at most max_rounds returns with "hp" hit
## points (revived {source, target, hp_after, spell}); Spare the Dying
## stabilizes a dying creature (death_save-like stable).
func _revive(actor: Combatant, target: Combatant, spell: SpellDefinition) -> void:
	if spell.raw_effect.get("stabilize", false) == true:
		target.sheet.stable = true
		target.sheet.death_save_failures = 0
		target.sheet.death_save_successes = 0
		_emit("stabilized", {"source": actor.id, "target": target.id, "spell": spell.id})
		return
	var hp := DictUtil.to_int(spell.raw_effect.get("hp", 1), 1)
	target.sheet.dead = false
	target.sheet.current_hp = target.sheet.max_hp if hp < 0 else clampi(hp, 1, target.sheet.max_hp)
	target.sheet.reset_death_saves()
	target.died_round = -1
	target.sheet.resurrection_penalty = maxi(target.sheet.resurrection_penalty, DictUtil.to_int(spell.raw_effect.get("penalty", 0), 0))
	_emit("revived", {"source": actor.id, "target": target.id, "hp_after": target.sheet.current_hp, "spell": spell.id})


## Dispel effects: "conditions" listed end on the target; "exhaustion" levels
## are removed; "spell_ids" end those spells' effects; "spells": every spell
## effect on the target ends (level <= the slot automatically, higher with a
## casting ability check DC 10 + its level).
func _dispel(actor: Combatant, target: Combatant, spell: SpellDefinition, slot: int) -> void:
	_emit("dispel", {"source": actor.id, "target": target.id, "spell": spell.id})
	for c in DictUtil.to_string_array(spell.raw_effect.get("conditions", [])):
		_end_conditions_named(target, c)
	var exhaustion := DictUtil.to_int(spell.raw_effect.get("exhaustion", 0), 0)
	if exhaustion > 0 and target.sheet.exhaustion > 0:
		_add_exhaustion(target, -exhaustion, spell.id)
	var only := DictUtil.to_string_array(spell.raw_effect.get("spell_ids", []))
	var all: bool = spell.raw_effect.get("spells", false) == true
	if only.is_empty() and not all:
		return
	var spell_ids: Array[String] = []
	for entry in target.conditions:
		var sid := str(entry.get("spell", ""))
		if not sid.is_empty() and not spell_ids.has(sid):
			spell_ids.append(sid)
	for b in target.buffs:
		var sid := str(b.get("spell", ""))
		if not sid.is_empty() and not spell_ids.has(sid):
			spell_ids.append(sid)
	for caster_id: Variant in target.marks.keys():
		var sid := str((target.marks[caster_id] as Dictionary).get("effect", ""))
		if not sid.is_empty() and not spell_ids.has(sid):
			spell_ids.append(sid)
	for sid in spell_ids:
		if not only.is_empty() and not only.has(sid):
			continue
		var def := _spell_def(sid)
		var lvl := def.level if def != null else 0
		if all and lvl > slot:
			if ability_check(actor, actor.sheet.casting_ability, -1, 10 + lvl, "dispel")["success"] != true:
				continue
		for entry: Dictionary in target.conditions.duplicate():
			if str(entry.get("spell", "")) == sid:
				_remove_condition(target, entry)
		for b: Dictionary in target.buffs.duplicate():
			if str(b.get("spell", "")) == sid:
				_remove_buff(target, b)
		for caster_id: Variant in target.marks.keys():
			var mark: Dictionary = target.marks[caster_id]
			if str(mark.get("effect", "")) == sid or str(mark.get("spell", "")) == sid:
				target.marks.erase(caster_id)
				_emit("effect_ended", {"target": target.id, "effect": str(mark.get("effect", ""))})
		if target.sheet.active_buffs.has(sid):
			target.sheet.active_buffs.erase(sid)
			_emit("effect_ended", {"target": target.id, "effect": sid})


## Power Word Kill / Stun, Divine Word: by the target's current hit points,
## the first "levels" entry [hp, outcome] with hp <= its value applies:
## "kill" (destroyed {source, target, feature: spell}) or conditions (save_ends
## with the spell's "save", else the encounter). "save_first": a successful
## save first prevents everything.
func _threshold(actor: Combatant, target: Combatant, spell: SpellDefinition) -> void:
	var save := Ability.from_string(str(spell.raw_effect.get("save", "")))
	if spell.raw_effect.get("save_first", false) == true and save >= 0:
		if _saving_throw(actor.id, target, save, actor.sheet.spell_save_dc()):
			return
	var levels: Array = spell.raw_effect.get("levels", [])
	for level_v: Variant in levels:
		var level: Array = level_v
		if target.sheet.current_hp > DictUtil.to_int(level[0], 0):
			continue
		var outcome: Variant = level[1]
		if str(outcome) == "kill":
			target.sheet.kill()
			if target.died_round < 0:
				target.died_round = tracker.round_number
			_emit("destroyed", {"source": actor.id, "target": target.id, "feature": spell.id})
			_on_dropped(target)
			return
		var conditions: Array[String] = DictUtil.to_string_array(outcome) if typeof(outcome) == TYPE_ARRAY else [str(outcome)]
		var duration := Conditions.duration(Conditions.DURATION_ENCOUNTER)
		if save >= 0 and spell.raw_effect.get("save_first", false) != true:
			duration = Conditions.duration(Conditions.DURATION_SAVE_ENDS, {"ability": Ability.abbreviation(save), "dc": actor.sheet.spell_save_dc()})
		for c in conditions:
			_apply_condition(target, c, actor.id, duration)
		return

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
## total 0) on STR / DEX saves while unconscious, stunned, paralyzed or
## petrified. Advantage: DEX saves while dodging or with Danger Sense (not
## blinded or incapacitated), buffs ("adv_saves": Haste DEX, ...), Countercharm
## and Steel Will against fear / charm (opts "vs_condition"), Land's Stride
## against plant spells (opts "plant"). Disadvantage: DEX saves while
## restrained, exhaustion 3+, Heightened Spell (opts "heightened"). Bonuses:
## Aura of Protection (+CHA of a conscious paladin ally in its aura), Bless /
## Bane dice, flat buff bonuses ("save_bonus", "save_bonus_<ABL>"), minus the
## Raise Dead penalty. A failed save may be saved by Dark One's Own Luck
## (+1d10 when that can succeed), Indomitable or Diamond Soul (reroll; 1 ki),
## each emitting save_modified {target, feature, natural, total, success, roll?}.
## The event gets "advantage" only when the roll was not normal.
func _saving_throw(source_id: String, target: Combatant, ability: int, dc: int, opts: Dictionary = {}) -> bool:
	var natural := 0
	var total := 0
	var success := false
	var mode := D20.RollMode.NORMAL
	var physical := ability == Ability.Type.STR or ability == Ability.Type.DEX
	var abbr := Ability.abbreviation(ability)
	var flat := 0
	if physical and (target.sheet.is_unconscious() or target.auto_fails_physical_saves()):
		success = false
	else:
		var dex := ability == Ability.Type.DEX
		var advantage := dex and (target.dodging or (target.sheet.has_feature("danger_sense") \
				and not target.has_condition(Conditions.BLINDED) and not target.is_incapacitated()))
		var adv_saves := target.buff_list("adv_saves")
		if adv_saves.has(abbr) or adv_saves.has("ALL"):
			advantage = true
		var vs := str(opts.get("vs_condition", ""))
		if vs in [Conditions.FRIGHTENED, Conditions.CHARMED] and _countercharmed(target):
			advantage = true
		if vs == Conditions.FRIGHTENED and target.sheet.has_feature("steel_will"):
			advantage = true
		if opts.get("plant", false) == true and target.sheet.has_feature("lands_stride"):
			advantage = true
		var vs_types := target.buff_list("adv_saves_vs_types")
		if not vs_types.is_empty():
			var src := get_combatant(source_id)
			if src != null and vs_types.has(src.creature_type):
				advantage = true
		var disadvantage: bool = (dex and target.has_condition(Conditions.RESTRAINED)) or target.sheet.exhaustion >= 3 \
				or opts.get("heightened", false) == true
		var dis_saves := target.buff_list("disadv_saves")
		if dis_saves.has(abbr) or dis_saves.has("ALL"):
			disadvantage = true
		mode = D20.combine(advantage, disadvantage)
		var d := D20.roll(rng, mode)
		natural = d.natural
		flat = _save_flat_bonus(target, ability) + _d20_dice_bonus(target, "save_dice")
		total = d.natural + target.sheet.save_modifier(ability) + flat
		success = total >= dc
	var ev := {
		"actor": source_id,
		"target": target.id,
		"ability": abbr,
		"dc": dc,
		"natural": natural,
		"total": total,
		"success": success,
	}
	if mode != D20.RollMode.NORMAL:
		ev["advantage"] = Encounter._mode_name(mode)
	_emit("save", ev)
	if not success and natural > 0:
		success = _rescue_failed_save(target, ability, dc, total, flat)
	return success


## Flat saving throw bonuses: Aura of Protection, buff bonuses, minus the
## Raise Dead penalty.
func _save_flat_bonus(target: Combatant, ability: int) -> int:
	var bonus := target.buff_int("save_bonus") + target.buff_int("save_bonus_" + Ability.abbreviation(ability)) - target.sheet.resurrection_penalty
	var aura := 0
	for p in tracker.order():
		if p.team != target.team or not p.is_conscious() or not p.sheet.has_feature("aura_of_protection"):
			continue
		if GridMath.distance_tiles(p.position, target.position) <= Encounter.aura_tiles(p.sheet):
			aura = maxi(aura, maxi(1, p.sheet.ability_modifier(Ability.Type.CHA)))
	return bonus + aura


## Paladin aura radius in tiles (class table "aura_radius" in feet; 2, 6 from 18th level).
static func aura_tiles(sheet: CharacterSheet) -> int:
	return GridMath.feet_to_tiles(sheet.table_int("aura_radius", 30 if sheet.level >= 18 else 10))


## A Countercharm ally (or itself) within 6 tiles is performing.
func _countercharmed(target: Combatant) -> bool:
	for b in tracker.order():
		if b.team != target.team or not b.is_conscious() or not b.has_buff("countercharm"):
			continue
		if GridMath.distance_tiles(b.position, target.position) <= COUNTERCHARM_RANGE_TILES:
			return true
	return false


## Features that rescue a failed save (policy key "failed_save" or the feature
## id): Dark One's Own Luck (+1d10, when 10 more would succeed), Indomitable
## (reroll), Diamond Soul (1 ki, reroll). Returns the new success.
func _rescue_failed_save(target: Combatant, ability: int, dc: int, total: int, flat: int) -> bool:
	if not target.is_conscious():
		return false
	if target.sheet.has_feature("dark_ones_own_luck") and target.sheet.class_resource("dark_ones_own_luck") > 0 \
			and total + 10 >= dc and target.reaction_allowed("failed_save", "dark_ones_own_luck"):
		target.sheet.spend_class_resource("dark_ones_own_luck", 1)
		var roll := rng.next_int(1, 10)
		var new_total := total + roll
		_emit("save_modified", {"target": target.id, "feature": "dark_ones_own_luck", "natural": 0, "roll": roll, "total": new_total, "success": new_total >= dc})
		if new_total >= dc:
			return true
	for feature: String in ["indomitable", "diamond_soul"]:
		if not target.sheet.has_feature(feature) or not target.reaction_allowed("failed_save", feature):
			continue
		var resource := "indomitable" if feature == "indomitable" else "ki"
		if target.sheet.class_resource(resource) <= 0:
			continue
		target.sheet.spend_class_resource(resource, 1)
		var d := D20.roll(rng)
		var new_total := d.natural + target.sheet.save_modifier(ability) + flat
		var ok := new_total >= dc
		_emit("save_modified", {"target": target.id, "feature": feature, "natural": d.natural, "total": new_total, "success": ok})
		return ok
	return false

## Applies already-adjusted spell damage and emits damage (+ "spell" and extras).
func _deal_spell_damage(source: Combatant, target: Combatant, amount: int, spell: SpellDefinition, fields: Dictionary) -> void:
	var outcome := _take_damage(target, amount)
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
	elif not DictUtil.to_bool(intent.get("haste", false), false):
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
		"font_of_magic", "cunning_action", "pact_weapon", "revert_form", "volley", "whirlwind_attack", "intimidating_presence", \
				"countercharm", "stillness_of_mind", "dragon_wings", "magic_jar", "end_spell":
			spend = 0
	if FEATURE_SPEND.has(feature):
		spend = FEATURE_SPEND[feature]
	if spend > 0 and not resource.is_empty():
		actor.sheet.spend_class_resource(resource, spend)
	if feature in ["intimidating_presence", "cleansing_touch", "magic_jar", "gaze_of_two_minds"]:
		target = _cast_target(actor, intent)
	if feature == "quivering_palm" and get_combatant(actor.quivering_target) != null:
		target = get_combatant(actor.quivering_target)
	var used := {"actor": actor.id, "feature": feature, "target": target.id, "remaining": actor.sheet.class_resource(resource) if not resource.is_empty() else 0}
	if intent.has("mode"):
		used["mode"] = str(intent["mode"])
	if feature == "flurry_of_blows":
		used["strikes"] = 2
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
			if actor.sheet.has_feature("mindless_rage"):
				_end_conditions_named(actor, Conditions.CHARMED)
				_end_conditions_named(actor, Conditions.FRIGHTENED)
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
			_dodge(actor, feature)
		"step_of_the_wind", "cunning_action":
			if str(intent.get("mode", "")) == "dash":
				_dash(actor, feature)
			elif str(intent.get("mode", "")) == "hide":
				_hide(actor)
			else:
				_disengage(actor, feature)
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
		"intimidating_presence", "countercharm", "wholeness_of_body", "stillness_of_mind", "divine_intervention", \
				"cleansing_touch", "volley", "whirlwind_attack", "elemental_affinity", "dragon_wings", "wild_shape", \
				"revert_form", "empty_body", "draconic_presence":
			_do_feature_b(actor, feature, intent)
		"magic_jar", "end_spell", "one_with_shadows", "gaze_of_two_minds", "quivering_palm", "holy_nimbus":
			_do_feature_c(actor, feature, intent)
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
				if c.is_alive() and _saving_throw(str(entry.get("source", "")), c, Ability.from_string(str(duration.get("ability", "WIS"))), DictUtil.to_int(duration.get("dc", 10), 10), {"vs_condition": str(entry.get("condition", ""))}):
					_remove_condition(c, entry)
			Conditions.DURATION_SAVE_TRACK:
				if c.is_alive():
					_save_track(c, entry)
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
	_buffs_turn_end(c)
	_tile_effects_turn_end(c)
	_banish_turn_end(c)
	_blink(c)
	for s in _summons_of(c.id):
		if s.summon_turns_left > 0:
			s.summon_turns_left -= 1
			if s.summon_turns_left <= 0:
				_dismiss(s, "expired")


## Buff durations at the end of c's turn (as for conditions), damage over
## time with "dot_trigger": "end_turn" (Phantasmal Killer, Acid Arrow), and
## end-of-turn saves of save_ends buffs (Slow, Hideous Laughter).
func _buffs_turn_end(c: Combatant) -> void:
	for b: Dictionary in c.buffs.duplicate():
		if not c.buffs.has(b):
			continue
		if str(b.get("dot_trigger", "")) == "end_turn":
			_buff_dot(c, b)
			if not c.buffs.has(b) or not c.is_alive():
				continue
		var duration: Dictionary = b.get("duration", {})
		match str(duration.get("type", "")):
			Conditions.DURATION_TARGET_TURN_END, Conditions.DURATION_ROUNDS:
				b["turns_left"] = DictUtil.to_int(b.get("turns_left", 1), 1) - 1
				if DictUtil.to_int(b["turns_left"]) <= 0:
					_remove_buff(c, b)
			Conditions.DURATION_SAVE_ENDS:
				if c.is_alive() and _saving_throw(str(b.get("source", "")), c, Ability.from_string(str(duration.get("ability", "WIS"))), DictUtil.to_int(duration.get("dc", 10), 10)):
					_remove_buff(c, b)
	for other in tracker.order():
		for b: Dictionary in other.buffs.duplicate():
			var duration: Dictionary = b.get("duration", {})
			if str(b.get("source", "")) == c.id and str(duration.get("type", "")) == Conditions.DURATION_SOURCE_NEXT_TURN:
				b["turns_left"] = DictUtil.to_int(b.get("turns_left", 1), 1) - 1
				if DictUtil.to_int(b["turns_left"]) <= 0:
					_remove_buff(other, b)


## Damage over time from a buff entry: "dot_dice" of "dot_type"; with
## "dot_save" {ability, dc} a successful save prevents it and ends the buff
## (and the condition the spell applied); "dot_once" ends it after the damage.
func _buff_dot(c: Combatant, b: Dictionary) -> void:
	var source := get_combatant(str(b.get("source", "")))
	var save_v: Variant = b.get("dot_save", {})
	if typeof(save_v) == TYPE_DICTIONARY and not (save_v as Dictionary).is_empty():
		var save: Dictionary = save_v
		if _saving_throw(str(b.get("source", "")), c, Ability.from_string(str(save.get("ability", "WIS"))), DictUtil.to_int(save.get("dc", 10), 10)):
			if save.get("ends", true) == true:
				_remove_buff(c, b)
				var spell_id := str(b.get("spell", ""))
				for entry: Dictionary in c.conditions.duplicate():
					if not spell_id.is_empty() and str(entry.get("spell", "")) == spell_id and str(entry.get("source", "")) == str(b.get("source", "")):
						_remove_condition(c, entry)
			return
	var dtype := str(b.get("dot_type", ""))
	var rolled := maxi(0, DictUtil.to_int(DiceFormula.parse(str(b.get("dot_dice", "0"))).roll(rng)["total"]))
	_deal_effect_damage(source, c, c.adjust_damage(rolled, dtype, true), dtype, {"spell": str(b.get("spell", b.get("effect", ""))), "over_time": true})
	if b.get("dot_once", false) == true and c.buffs.has(b):
		_remove_buff(c, b)


## Start of c's turn: Shield-like buffs ("until_target_turn_start") end, its
## Help marks fade, Survivor and Heroism heal / grant temporary hit points,
## start-of-turn damage over time and tile effects trigger, a confused
## creature rolls its d10 (1-6: the turn is lost).
func _start_of_turn(c: Combatant) -> void:
	for b: Dictionary in c.buffs.duplicate():
		var duration: Dictionary = b.get("duration", {})
		if str(duration.get("type", "")) == Conditions.DURATION_TARGET_TURN_START:
			_remove_buff(c, b)
	for entry: Dictionary in c.conditions.duplicate():
		var duration: Dictionary = entry.get("duration", {})
		if str(duration.get("type", "")) == Conditions.DURATION_TARGET_TURN_START:
			_remove_condition(c, entry)
	_violet_saves(c)
	for other in tracker.order():
		if other.helped_by == c.id:
			other.helped_by = ""
			other.help_team = -1
	if not c.is_conscious():
		return
	if c.sheet.has_feature("survivor") and c.sheet.current_hp <= floori(c.sheet.max_hp / 2.0):
		_heal(c.id, c, 5 + c.sheet.ability_modifier(Ability.Type.CON))
	for b: Dictionary in c.buffs.duplicate():
		if b.has("temp_hp_each_turn"):
			var temp := DictUtil.to_int(b["temp_hp_each_turn"], 0)
			if temp > c.sheet.temp_hp:
				c.sheet.grant_temp_hp(temp)
				_emit("temp_hp", {"source": str(b.get("source", "")), "target": c.id, "amount": temp, "temp_hp_after": c.sheet.temp_hp})
		if str(b.get("dot_trigger", "")) == "start_turn" and c.buffs.has(b):
			_buff_dot(c, b)
		if not c.is_alive():
			return
	_tile_effects_turn_start(c)
	_compelled_move(c)
	if c.is_conscious() and c.has_buff("confused"):
		var roll := rng.next_int(1, 10)
		_emit("confusion_roll", {"actor": c.id, "roll": roll})
		if roll <= 6:
			_apply_condition(c, Conditions.TURN_LOST, c.id, Conditions.duration(Conditions.DURATION_TARGET_TURN_END))


## Runs an auto-controlled combatant's turn (summons): MonsterBrain's plan up
## to its end_turn, intents validated and resolved without being logged
## (replays recompute them).
func _auto_turn(c: Combatant) -> void:
	if not c.orders.is_empty():
		var orders: Array[Dictionary] = c.orders.duplicate(true)
		c.orders.clear()
		for order: Dictionary in orders:
			var intent: Dictionary = order.duplicate(true)
			intent["v"] = INTENT_VERSION
			intent["actor"] = c.id
			if str(intent.get("type", "")) == END_TURN or not _validate(c, intent).is_empty():
				return
			_resolve(c, intent)
			if state != State.ACTIVE or tracker.current() != c or not c.is_conscious() or not _combatants.has(c.id):
				return
		return
	for intent in MonsterBrain.decide(self, c.id):
		if str(intent.get("type", "")) == END_TURN:
			return
		if not _validate(c, intent).is_empty():
			return
		_resolve(c, intent)
		if state != State.ACTIVE or tracker.current() != c or not c.is_conscious() or not _combatants.has(c.id):
			return


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
	var cur := tracker.current()
	if cur != null and cur.extra_turns > 0 and cur.is_conscious() and _combatants.has(cur.id) and not cur.loses_turn():
		cur.extra_turns -= 1
		_emit("extra_turn", {"actor": cur.id, "source": cur.extra_turn_source, "turns_left": cur.extra_turns})
		return
	if cur != null:
		cur.extra_turns = 0
		_end_time_stop(cur, "expired")
	var previous_round := tracker.round_number
	tracker.advance()
	_purge_dismissed()
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
		if c.reckless:
			_emit("effect_ended", {"target": c.id, "effect": "reckless_attack"})
		c.reset_turn()
		if c.raging and (tracker.round_number - c.rage_started_round >= RAGE_ROUNDS or not c.is_conscious()):
			_end_rage(c)
		elif c.raging and not c.rage_kept and not c.sheet.has_feature("persistent_rage"):
			_end_rage(c, "inactive")
		c.rage_kept = false
		_start_of_turn(c)
		if state != State.ACTIVE:
			return
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
			if not c.auto_controlled:
				return
			_auto_turn(c)
			if state != State.ACTIVE:
				return
			if tracker.current() != c:
				continue
		_emit("turn_ended", {"actor": c.id})
		_on_turn_end(c)
		if check_end():
			return
		_advance()
	push_error("Encounter %s: turn-start loop did not settle" % id)


## Rage ends: effect_ended rage (reason "inactive" when the barbarian neither
## attacked a hostile nor took damage since its last turn; Persistent Rage
## keeps it); a Frenzy costs one level of exhaustion (exhaustion {target,
## level, source}).
func _end_rage(c: Combatant, reason: String = "") -> void:
	var frenzy := c.frenzied
	c.raging = false
	c.frenzied = false
	var ev := {"target": c.id, "effect": "rage"}
	if not reason.is_empty():
		ev["reason"] = reason
	_emit("effect_ended", ev)
	if frenzy:
		_add_exhaustion(c, 1, "frenzy")


## Adds exhaustion levels and emits exhaustion {target, level, source}.
func _add_exhaustion(c: Combatant, n: int, source: String) -> void:
	var before := c.sheet.exhaustion
	c.sheet.add_exhaustion(n)
	if c.sheet.exhaustion != before:
		_emit("exhaustion", {"target": c.id, "level": c.sheet.exhaustion, "source": source})


func _end_encounter(winner: int) -> void:
	state = State.ENDED
	winning_team = winner
	_settle_companions()
	_settle_lingering()
	_emit("encounter_ended", {"winning_team": winner})


func _conscious_teams() -> Dictionary:
	var teams := {}
	for value: Variant in _combatants.values():
		var c: Combatant = value
		if c.is_conscious() and not c.is_summon() and c.controlled_by.is_empty():
			teams[c.team] = true
	return teams


## Teams with at least one member who is conscious or dying.
func _teams_in_fight() -> Dictionary:
	var teams := {}
	for value: Variant in _combatants.values():
		var c: Combatant = value
		if c.is_in_fight() and not c.is_summon() and c.controlled_by.is_empty():
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


# --- reactions -------------------------------------------------------------------

## Marks c's reaction as spent and emits reaction_used {actor, reaction,
## trigger, ...fields}.
func _use_reaction(c: Combatant, reaction: String, trigger: String, fields: Dictionary = {}) -> void:
	c.reaction_used = true
	_end_on_act(c)
	var ev := {"actor": c.id, "reaction": reaction, "trigger": trigger}
	ev.merge(fields)
	_emit("reaction_used", ev)


## c can react now and its policy allows `reaction` for `trigger`.
func _may_react(c: Combatant, trigger: String, reaction: String) -> bool:
	return c.can_react() and c.reaction_allowed(trigger, reaction)


## The lowest slot (>= min_level) c can cast a prepared reaction spell with, or 0.
func _reaction_slot(c: Combatant, spell_id: String, min_level: int) -> int:
	if c.raging or not c.sheet.is_spell_prepared(spell_id):
		return 0
	return c.sheet.lowest_available_slot(maxi(1, min_level))


## Protection fighting style (trigger ally_attacked): a creature with the
## style and a shield, adjacent to the target (not the target itself), that
## can see the attacker imposes disadvantage on the attack roll.
func _protection_reaction(attacker: Combatant, target: Combatant) -> bool:
	for c in tracker.order():
		if c == target or c.team != target.team or c.team == attacker.team:
			continue
		if not c.sheet.fighting_styles.has("protection") or c.sheet.shield_bonus <= 0:
			continue
		if not GridMath.is_adjacent(c.position, target.position) or not can_see(c, attacker):
			continue
		if not _may_react(c, "ally_attacked", "protection"):
			continue
		_use_reaction(c, "protection", "ally_attacked", {"source": attacker.id, "target": target.id})
		return true
	return false


## Reactions to a hit (not a critical) that can turn it into a miss: the
## Shield spell (trigger creature_hit_me: +5 AC until the target's next turn,
## when that makes the attack miss) and Cutting Words (trigger ally_hit: a
## Lore bard within 12 tiles of the attacker subtracts its inspiration die,
## used when the die can make the attack miss).
func _on_hit_reactions(attacker: Combatant, target: Combatant, r: AttackResult, _spell: SpellDefinition) -> void:
	if r.critical or not r.hit:
		return
	if r.attack_total < r.target_ac + SHIELD_AC and _may_react(target, "creature_hit_me", "shield"):
		var slot := _reaction_slot(target, "shield", 1)
		if slot > 0:
			_cast_shield(target, attacker, slot)
			r.target_ac += SHIELD_AC
			_convert_to_miss(r)
			return
	for bard in tracker.order():
		if bard.team != target.team or not bard.sheet.has_feature("cutting_words") or bard.sheet.class_resource("bardic_inspiration") <= 0:
			continue
		if GridMath.distance_tiles(bard.position, attacker.position) > CUTTING_WORDS_RANGE_TILES or not can_see(bard, attacker):
			continue
		var die := bard.sheet.bardic_inspiration_die()
		if r.attack_total - die >= r.target_ac or not _may_react(bard, "ally_hit", "cutting_words"):
			continue
		var roll := rng.next_int(1, die)
		bard.sheet.spend_class_resource("bardic_inspiration", 1)
		_use_reaction(bard, "cutting_words", "ally_hit", {"source": attacker.id, "target": target.id, "die": die, "roll": roll})
		r.attack_total -= roll
		if r.attack_total < r.target_ac:
			_convert_to_miss(r)
		return


## Casts Shield as a reaction: spends the slot, emits reaction_used and the
## +5 AC effect until the start of its next turn.
func _cast_shield(c: Combatant, source: Combatant, slot: int) -> void:
	c.sheet.use_spell_slot(slot)
	_use_reaction(c, "shield", "creature_hit_me", {"source": source.id, "slot_level": slot})
	_apply_buff(c, "shield", c.id, Conditions.duration(Conditions.DURATION_TARGET_TURN_START), {"ac": SHIELD_AC, "immune_damage_spell": "magic_missile"}, "shield")


## Mirror Image: an attacker that can see the target rolls a d20; 6+ (3
## images), 8+ (2) or 11+ (1) aims at a duplicate instead (AC 10 + DEX; a hit
## destroys it). Emits mirror_image {attacker, target, roll, hit, images_left}.
func _mirror_image_absorbs(attacker: Combatant, target: Combatant, _mode: D20.RollMode) -> bool:
	var entry := {}
	for b in target.buffs:
		if DictUtil.to_int(b.get("images", 0), 0) > 0:
			entry = b
	if entry.is_empty() or not can_see(attacker, target):
		return false
	var images := DictUtil.to_int(entry["images"])
	var need := 6 if images >= 3 else (8 if images == 2 else 11)
	var roll := rng.next_int(1, 20)
	if roll < need:
		return false
	var d := D20.roll(rng)
	var dup_ac := 10 + target.sheet.ability_modifier(Ability.Type.DEX)
	var hit := d.natural == 20 or (d.natural != 1 and d.natural + DictUtil.to_int(attacker.attacks[0].get("to_hit", 0) if not attacker.attacks.is_empty() else 0, 0) >= dup_ac)
	if hit:
		entry["images"] = images - 1
	_emit("mirror_image", {"attacker": attacker.id, "target": target.id, "roll": roll, "hit": hit, "images_left": DictUtil.to_int(entry["images"])})
	if DictUtil.to_int(entry["images"]) <= 0:
		_remove_buff(target, entry)
	return true


static func _convert_to_miss(r: AttackResult) -> void:
	r.hit = false
	r.critical = false
	r.extras.clear()
	r.damage_total = 0


## After a hit landed: Multiattack Defense remembers the attacker; Fire Shield
## burns a melee attacker within 5 ft.
func _after_hit_by(attacker: Combatant, target: Combatant, melee: bool, _damage: int) -> void:
	if target.sheet.has_feature("multiattack_defense"):
		target.defended_against[attacker.id] = turn_counter
	if melee:
		_melee_answer(attacker, target, true)
	if not melee or not attacker.is_alive() or not GridMath.is_adjacent(attacker.position, target.position):
		return
	for b in target.buffs:
		var dice := str(b.get("retaliate_dice", ""))
		if dice.is_empty() or not target.is_alive():
			continue
		var dtype := str(b.get("retaliate_type", "fire"))
		var amount := attacker.adjust_damage(maxi(0, DiceExpr.parse(dice).roll(rng).total), dtype, true)
		_deal_effect_damage(target, attacker, amount, dtype, {"spell": str(b.get("spell", b.get("effect", "")))})


## Melee reactions of the target against an adjacent attacker: Retaliation
## (berserker 14, after taking damage: trigger damage_taken) and Giant Killer
## (hunter 3, a Large or larger attacker hits or misses: trigger
## creature_hit_me / missed). The target makes its first usable melee attack.
func _melee_answer(attacker: Combatant, target: Combatant, hit: bool) -> void:
	if not attacker.is_alive() or not target.is_conscious() or not GridMath.is_adjacent(attacker.position, target.position):
		return
	var reaction := ""
	var trigger := ""
	if hit and target.sheet.has_feature("retaliation"):
		reaction = "retaliation"
		trigger = "damage_taken"
	elif target.sheet.has_feature("giant_killer") and attacker.sheet.size_index() >= 3:
		reaction = "giant_killer"
		trigger = "creature_hit_me" if hit else "missed"
	if reaction.is_empty() or not _may_react(target, trigger, reaction):
		return
	var index := _usable_melee_index(target)
	if index < 0:
		return
	_use_reaction(target, reaction, trigger, {"target": attacker.id})
	_resolve_attack(target, attacker, index, false, {"no_reactions": true})


## Stand Against the Tide (hunter 15, trigger missed): a melee attack that
## missed the ranger is repeated against another creature in the attacker's
## reach (the attacker's own ally with the lowest hp, ties by id).
func _stand_against_the_tide(attacker: Combatant, target: Combatant, attack: Dictionary, spell: SpellDefinition) -> void:
	if not target.sheet.has_feature("stand_against_the_tide") or spell != null or attacker.is_summon():
		return
	var best: Combatant = null
	for c in tracker.order():
		if c == attacker or c == target or c.team != attacker.team or not c.is_conscious() or c.untargetable:
			continue
		if not attack_reach_error(attacker.position, c.position, attack).is_empty():
			continue
		if best == null or c.sheet.current_hp < best.sheet.current_hp or (c.sheet.current_hp == best.sheet.current_hp and c.id < best.id):
			best = c
	if best == null or not _may_react(target, "missed", "stand_against_the_tide"):
		return
	_use_reaction(target, "stand_against_the_tide", "missed", {"source": attacker.id, "target": best.id})
	_roll_attack(attacker, best, attack, false, null, {"no_reactions": true})


## Hellish Rebuke (trigger damage_taken): a creature damaged by a hostile it
## can see within 12 tiles answers with the reaction spell (DEX save, fire).
func _damage_taken_reactions(source: Combatant, target: Combatant) -> void:
	if source == null or source.team == target.team or not source.is_alive() or not target.is_conscious():
		return
	if GridMath.distance_tiles(source.position, target.position) > HELLISH_REBUKE_RANGE_TILES or not can_see(target, source):
		return
	if not _may_react(target, "damage_taken", "hellish_rebuke"):
		return
	var spell := _spell_def("hellish_rebuke")
	var slot := _reaction_slot(target, "hellish_rebuke", 1)
	if spell == null or slot <= 0:
		return
	target.sheet.use_spell_slot(slot)
	_use_reaction(target, "hellish_rebuke", "damage_taken", {"source": source.id, "slot_level": slot})
	var success := _saving_throw(target.id, source, Ability.Type.DEX, target.sheet.spell_save_dc())
	var rolled := _roll_spell_damage(target, spell, slot, 0)
	if success:
		rolled = floori(rolled / 2.0)
	_deal_spell_damage(target, source, source.adjust_damage(rolled, spell.damage_type, true), spell, {})


## Sanctuary / Tranquility: a hostile attacking (or targeting with a harmful
## spell) the warded creature makes a WIS save; on a failure the attack or
## spell is lost (attack_lost {attacker, target, reason}).
func _sanctuary_blocks(attacker: Combatant, target: Combatant) -> bool:
	if attacker.team == target.team:
		return false
	var dc := -1
	for b in target.buffs:
		if b.has("sanctuary_dc"):
			dc = maxi(dc, DictUtil.to_int(b["sanctuary_dc"], 10))
	if dc < 0 and target.sheet.active_buffs.has("tranquility"):
		dc = Encounter.ki_save_dc(target.sheet)
	if dc < 0 and target.sheet.has_feature("natures_sanctuary") and attacker.creature_type in ["beast", "plant"]:
		dc = target.sheet.spell_save_dc()
	if dc < 0:
		return false
	if _saving_throw(target.id, attacker, Ability.Type.WIS, dc):
		return false
	_emit("attack_lost", {"attacker": attacker.id, "target": target.id, "reason": "sanctuary"})
	return true


# --- d20 tests: checks, contests, visibility -----------------------------------------

## Sum of a d20-test dice modifier from c's buffs (Bless "attack_dice" /
## "save_dice" +1d4, Bane -1d4, Guidance / Resistance "check_dice" /
## "save_dice" used once). Rolls each die.
func _d20_dice_bonus(c: Combatant, key: String) -> int:
	var total := 0
	for b: Dictionary in c.buffs.duplicate():
		var dice := str(b.get(key, ""))
		if dice.is_empty():
			continue
		var negative := dice.begins_with("-")
		var expr := DiceExpr.parse(dice.trim_prefix("-"))
		if not expr.valid:
			continue
		var v := expr.roll(rng).total
		total += -v if negative else v
		if b.get("once", false) == true:
			_remove_buff(c, b)
	return total


## Rolls an ability check (SRD): d20 + check modifier (proficiency /
## Expertise / Jack of All Trades / Remarkable Athlete, see
## CharacterSheet.check_modifier) + Guidance - the Raise Dead penalty.
## Disadvantage while poisoned, frightened of a source in sight or exhausted;
## `advantage` / `disadvantage` add more. Reliable Talent treats a d20 below
## 10 as 10 on proficient checks. Emits check {actor, ability, skill (key or
## ""), natural, total, reason, dc? and success? (dc >= 0), advantage? (when
## not normal), contest? (opponent id)}. Returns {"total", "natural", "success"}.
func ability_check(c: Combatant, ability: int, skill: int = -1, dc: int = -1, reason: String = "", advantage: bool = false, disadvantage: bool = false, bonus: int = 0, contest_with: String = "") -> Dictionary:
	var dis := disadvantage or c.has_condition(Conditions.POISONED) or _frightened_in_sight(c) or c.sheet.exhaustion >= 1
	var adv := advantage
	if skill == Skill.Type.STEALTH and c.sheet.armor_base > 0 and c.sheet.wears_heavy_armor():
		dis = true
	var adv_checks := c.buff_list("adv_checks")
	if adv_checks.has(Ability.abbreviation(ability)) or adv_checks.has("ALL"):
		adv = true
	var dis_checks := c.buff_list("disadv_checks")
	if dis_checks.has(Ability.abbreviation(ability)) or dis_checks.has("ALL"):
		dis = true
	var mode := D20.combine(adv, dis)
	var d := D20.roll(rng, mode)
	var natural := d.natural
	var die := natural
	if c.sheet.has_feature("reliable_talent") and c.sheet.is_skill_proficient(skill) and die < 10:
		die = 10
	var extra := c.buff_int("stealth_bonus") if skill == Skill.Type.STEALTH else 0  # Pass without Trace
	var modifier := c.sheet.check_modifier(ability, skill) + bonus + extra + _d20_dice_bonus(c, "check_dice") - c.sheet.resurrection_penalty
	var total := die + modifier
	if ability == Ability.Type.STR and c.sheet.has_feature("indomitable_might"):
		total = maxi(total, c.sheet.abilities.get_score(Ability.Type.STR))
	var ev := {"actor": c.id, "ability": Ability.abbreviation(ability), "skill": Skill.key_of(skill) if skill >= 0 else "", "natural": natural, "total": total, "reason": reason}
	var success := true
	if dc >= 0:
		success = total >= dc
		ev["dc"] = dc
		ev["success"] = success
	if mode != D20.RollMode.NORMAL:
		ev["advantage"] = Encounter._mode_name(mode)
	if not contest_with.is_empty():
		ev["contest"] = contest_with
	_emit("check", ev)
	if dc >= 0 and not success:
		total = _improve_failed_check(c, total, modifier, dc)
		success = total >= dc
	return {"total": total, "natural": natural, "success": success}


## A failed ability check of c with `total` against dc (a contest: the total
## to beat + 1): Peerless Skill (lore 14) adds a Bardic Inspiration die (one
## use), then Stroke of Luck (rogue 20, once per short rest) treats the d20 as
## a 20 (d20 = 20 + modifier). Each emits check_modified {actor, feature,
## roll?, total, success}. Returns the new total.
func _improve_failed_check(c: Combatant, total: int, modifier: int, dc: int) -> int:
	if c.sheet.has_feature("peerless_skill") and c.sheet.class_resource("bardic_inspiration") > 0 and c.reaction_allowed("failed_check", "peerless_skill"):
		c.sheet.spend_class_resource("bardic_inspiration", 1)
		var roll := rng.next_int(1, c.sheet.bardic_inspiration_die())
		total += roll
		_emit("check_modified", {"actor": c.id, "feature": "peerless_skill", "roll": roll, "total": total, "success": total >= dc})
	if total < dc and c.sheet.has_feature("stroke_of_luck") and c.sheet.class_resource("stroke_of_luck") > 0 and c.reaction_allowed("failed_check", "stroke_of_luck") \
			and 20 + modifier >= dc:
		c.sheet.spend_class_resource("stroke_of_luck", 1)
		total = 20 + modifier
		_emit("check_modified", {"actor": c.id, "feature": "stroke_of_luck", "total": total, "success": total >= dc})
	return total


## Contest (SRD): actor's check against the best of target's options
## ([[ability, skill], ...], the higher modifier). The actor wins on a higher
## total (a tie leaves things as they were: the actor fails). An incapacitated
## target loses automatically. Emits two check events and contest {actor,
## target, reason, actor_total, target_total, success}.
func contest(actor: Combatant, a_ability: int, a_skill: int, target: Combatant, options: Array, reason: String) -> bool:
	var a := ability_check(actor, a_ability, a_skill, -1, reason, false, false, 0, target.id)
	var target_total := -1
	if not target.is_incapacitated():
		var best: Array = options[0]
		for o: Array in options:
			if target.sheet.check_modifier(o[0], o[1]) > target.sheet.check_modifier(best[0], best[1]):
				best = o
		var t := ability_check(target, best[0], best[1], -1, reason, false, false, 0, actor.id)
		target_total = DictUtil.to_int(t["total"])
	var actor_total := DictUtil.to_int(a["total"])
	if actor_total <= target_total:
		actor_total = _improve_failed_check(actor, actor_total, actor_total - DictUtil.to_int(a["natural"]), target_total + 1)
		a["total"] = actor_total
	var success := actor_total > target_total
	_emit("contest", {"actor": actor.id, "target": target.id, "reason": reason, "actor_total": a["total"], "target_total": target_total, "success": success})
	return success


## Ends c's hidden state: revealed {actor, reason, by?}.
func _reveal(c: Combatant, reason: String, by: String = "") -> void:
	if not c.hidden:
		return
	c.hidden = false
	c.stealth_total = 0
	var ev := {"actor": c.id, "reason": reason}
	if not by.is_empty():
		ev["by"] = by
	_emit("revealed", ev)


## Hide: an action (or a bonus action with "bonus": true and Cunning Action,
## or Vanish). Not possible while a conscious hostile that can see it is
## adjacent, unless it stands in an obscured tile (fog, darkness).
func _check_hide(actor: Combatant, intent: Dictionary) -> String:
	if DictUtil.to_bool(intent.get("bonus", false), false):
		if not actor.sheet.has_feature("cunning_action") and not actor.sheet.has_feature("vanish"):
			return "%s cannot hide as a bonus action" % actor.display_name
		var err := _bonus_error(actor)
		if not err.is_empty():
			return err
	elif not DictUtil.to_bool(intent.get("haste", false), false):
		var err := _action_error(actor)
		if not err.is_empty():
			return err
	return _hide_error(actor)


func _hide_error(actor: Combatant) -> String:
	if _tile_obscured(actor.position):
		return ""
	for h in tracker.order():
		if h.team != actor.team and h.is_conscious() and not h.is_incapacitated() and not h.untargetable \
				and GridMath.is_adjacent(h.position, actor.position) and not h.has_condition(Conditions.BLINDED) and eyes_reach(h, actor.position):
			return "%s cannot hide next to %s" % [actor.display_name, h.display_name]
	return ""


## Stealth (DEX) check against the highest passive Perception among conscious
## hostiles with line of sight (none: it hides automatically, the total still
## counts against searches). Supreme Sneak: advantage after moving at most
## half its speed; Hide in Plain Sight: +10 when it has not moved this turn.
## Success: hidden {actor, total}.
func _do_hide(actor: Combatant, intent: Dictionary) -> void:
	var haste := DictUtil.to_bool(intent.get("haste", false), false)
	if DictUtil.to_bool(intent.get("bonus", false), false):
		actor.bonus_action_used = true
	elif not haste:
		actor.action_used = true
	_hide(actor)


func _hide(actor: Combatant) -> void:
	var dc := 0
	for h in tracker.order():
		if h.team == actor.team or not h.is_conscious() or h.untargetable or h.has_condition(Conditions.BLINDED):
			continue
		var obscured := (_tile_obscured(actor.position) and not h.sheet.invocations.has("devils_sight")) or not eyes_reach(h, actor.position)
		if not obscured and walk_map.has_line_of_sight(h.position, actor.position):
			dc = maxi(dc, h.sheet.passive_perception())
	var adv := actor.sheet.has_feature("supreme_sneak") and actor.tiles_moved <= floori(actor.speed_tiles() / 2.0)
	if actor.buff_flag("stealth_advantage"):
		adv = true
		for b: Dictionary in actor.buffs.duplicate():
			if b.get("stealth_advantage", false) == true:
				_remove_buff(actor, b)
	var bonus := 10 if actor.sheet.has_feature("hide_in_plain_sight") and actor.tiles_moved == 0 else 0
	var res := ability_check(actor, Ability.Type.DEX, Skill.Type.STEALTH, dc, "hide", adv, false, bonus)
	if res["success"] == true:
		actor.hidden = true
		actor.stealth_total = DictUtil.to_int(res["total"])
		_emit("hidden", {"actor": actor.id, "total": actor.stealth_total})


## Search (action): a Wisdom (Perception) check; every hidden hostile in line
## of sight whose Stealth total it meets is revealed.
func _do_search(actor: Combatant) -> void:
	var res := ability_check(actor, Ability.Type.WIS, Skill.Type.PERCEPTION, -1, "search")
	for h in tracker.order():
		if h.team == actor.team or not h.hidden:
			continue
		if walk_map.has_line_of_sight(actor.position, h.position) and DictUtil.to_int(res["total"]) >= h.stealth_total:
			_reveal(h, "found", actor.id)


## Shove / grapple: replaces one attack of the Attack action (like an attack
## intent: the first takes the action). The target is an adjacent creature at
## most one size larger. shove "mode": "prone" (default) or "push" (1 tile).
func _check_shove(actor: Combatant, intent: Dictionary) -> String:
	if not (actor.attack_action_taken and actor.attacks_remaining > 0) and not DictUtil.to_bool(intent.get("haste", false), false):
		var err := _action_error(actor)
		if not err.is_empty():
			return err
	var target := get_combatant(str(intent.get("target", "")))
	if target == null or target == actor:
		return "unknown target"
	if not target.is_alive() or target.untargetable:
		return "%s cannot be grabbed" % target.display_name
	if not GridMath.is_adjacent(actor.position, target.position):
		return "%s is out of reach" % target.display_name
	if target.sheet.size_index() > actor.sheet.size_index() + 1:
		return "%s is too large" % target.display_name
	if str(intent.get("type", "")) == SHOVE and not str(intent.get("mode", "prone")) in ["prone", "push"]:
		return "shove mode must be \"prone\" or \"push\""
	if actor.condition_sources(Conditions.CHARMED).has(target.id):
		return "%s is charmed by %s" % [actor.display_name, target.display_name]
	return _pacified_error(actor, target)


## Athletics contest against the target's Athletics or Acrobatics. Shove: prone
## (until it stands) or pushed 1 tile away. Grapple: grappled (speed 0) until
## it escapes, the grappler is incapacitated or they are no longer adjacent.
func _do_shove(actor: Combatant, intent: Dictionary) -> void:
	var target := get_combatant(str(intent.get("target", "")))
	if not DictUtil.to_bool(intent.get("haste", false), false):
		_take_attack_action(actor, {})
	var kind := str(intent.get("type", ""))
	var options := [[Ability.Type.STR, Skill.Type.ATHLETICS], [Ability.Type.DEX, Skill.Type.ACROBATICS]]
	var won := contest(actor, Ability.Type.STR, Skill.Type.ATHLETICS, target, options, kind)
	if actor.hidden:
		_reveal(actor, kind)
	if not won:
		return
	if kind == GRAPPLE:
		_apply_condition(target, Conditions.GRAPPLED, actor.id, Conditions.duration(Conditions.DURATION_ENCOUNTER), {"grapple": true})
	elif str(intent.get("mode", "prone")) == "push":
		_push(actor, target, 1)
	else:
		_apply_condition(target, Conditions.PRONE, actor.id, Conditions.duration(Conditions.DURATION_ENCOUNTER))


## Escape a grapple (action): Athletics or Acrobatics against the grappler's
## Athletics; success ends every grapple on the actor.
func _do_escape_grapple(actor: Combatant) -> void:
	for entry: Dictionary in actor.conditions.duplicate():
		if str(entry.get("condition", "")) != Conditions.GRAPPLED:
			continue
		var grappler := get_combatant(str(entry.get("source", "")))
		if grappler == null or not grappler.is_conscious():
			_remove_condition(actor, entry)
			continue
		var ability := Ability.Type.DEX if actor.sheet.check_modifier(Ability.Type.DEX, Skill.Type.ACROBATICS) > actor.sheet.check_modifier(Ability.Type.STR, Skill.Type.ATHLETICS) else Ability.Type.STR
		var skill := Skill.Type.ACROBATICS if ability == Ability.Type.DEX else Skill.Type.ATHLETICS
		if contest(actor, ability, skill, grappler, [[Ability.Type.STR, Skill.Type.ATHLETICS]], "escape_grapple"):
			_remove_condition(actor, entry)


## Grapples (conditions with "grapple": true) end when grappler and grappled
## are no longer adjacent or the grappler is incapacitated.
func _check_grapples(moved: Combatant) -> void:
	for c in tracker.order():
		for entry: Dictionary in c.conditions.duplicate():
			if entry.get("grapple", false) != true:
				continue
			var src := get_combatant(str(entry.get("source", "")))
			if c != moved and (src == null or src != moved):
				continue
			if src == null or not src.is_conscious() or src.is_incapacitated() or not GridMath.is_adjacent(src.position, c.position):
				_remove_condition(c, entry)


## Help (action): the next attack roll an ally makes against the target (a
## hostile adjacent to the helper) before the helper's next turn has advantage.
func _check_help(actor: Combatant, intent: Dictionary) -> String:
	var err := _action_error(actor)
	if not err.is_empty():
		return err
	var target := get_combatant(str(intent.get("target", "")))
	if target == null or target.team == actor.team or not target.is_alive():
		return "help needs a hostile target"
	if not GridMath.is_adjacent(actor.position, target.position):
		return "%s is not next to %s" % [target.display_name, actor.display_name]
	return ""


func _do_help(actor: Combatant, intent: Dictionary) -> void:
	var target := get_combatant(str(intent.get("target", "")))
	target.helped_by = actor.id
	target.help_team = actor.team
	if actor.hidden:
		_reveal(actor, "help")
	_emit("help", {"actor": actor.id, "target": target.id})


# --- buffs (encounter effects with modifiers) ---------------------------------------

## Applies an encounter effect with modifiers to target (see Combatant.buffs):
## the same effect from the same source is replaced. duration as for
## conditions (plus until_target_turn_start). Emits effect_applied {source,
## target, effect, duration, spell?}.
func _apply_buff(target: Combatant, effect: String, source_id: String, duration: Dictionary, mods: Dictionary, spell_id: String = "") -> Dictionary:
	if not target.is_alive():
		return {}
	for b: Dictionary in target.buffs.duplicate():
		if str(b.get("effect", "")) == effect and str(b.get("source", "")) == source_id:
			_remove_buff(target, b, false)
	var turns := 0
	match str(duration.get("type", "")):
		Conditions.DURATION_SOURCE_NEXT_TURN:
			var current := current_actor()
			turns = 2 if current != null and current.id == source_id else 1
		Conditions.DURATION_TARGET_TURN_END:
			turns = 1
		Conditions.DURATION_ROUNDS:
			turns = DictUtil.to_int(duration.get("rounds", 1), 1)
	var entry := mods.duplicate(true)
	entry["effect"] = effect
	entry["source"] = source_id
	entry["duration"] = duration.duplicate()
	entry["turns_left"] = turns
	if not spell_id.is_empty():
		entry["spell"] = spell_id
	target.buffs.append(entry)
	var ev := {"source": source_id, "target": target.id, "effect": effect, "duration": duration.duplicate()}
	if not spell_id.is_empty():
		ev["spell"] = spell_id
	_emit("effect_applied", ev)
	if entry.has("temp_hp"):
		var temp := DictUtil.to_int(entry["temp_hp"], 0)
		target.sheet.grant_temp_hp(temp)
		_emit("temp_hp", {"source": source_id, "target": target.id, "amount": temp, "temp_hp_after": target.sheet.temp_hp})
	if entry.has("max_hp_bonus"):
		var extra := DictUtil.to_int(entry["max_hp_bonus"], 0)
		target.sheet.max_hp += extra
		target.sheet.current_hp += extra
	if entry.get("speed_zero", false) == true:
		target.movement_remaining = 0
	for c in DictUtil.to_string_array(entry.get("immune_conditions", [])):
		_end_conditions_named(target, c)
	return entry


## Removes a buff entry; emits effect_ended {target, effect} (unless quiet).
## Haste's end costs the target its next turn; Aid's hit points go away.
func _remove_buff(target: Combatant, entry: Dictionary, announce: bool = true) -> void:
	for i in range(target.buffs.size()):
		if is_same(target.buffs[i], entry):
			target.buffs.remove_at(i)
			if entry.has("weapon_attack_index"):
				var wi := DictUtil.to_int(entry["weapon_attack_index"], -1)
				if wi >= 0 and wi < target.attacks.size():
					target.attacks[wi]["disabled"] = true
			if entry.has("max_hp_bonus"):
				var extra := DictUtil.to_int(entry["max_hp_bonus"], 0)
				target.sheet.max_hp = maxi(1, target.sheet.max_hp - extra)
				target.sheet.current_hp = mini(target.sheet.current_hp, target.sheet.max_hp)
			if announce:
				_emit("effect_ended", {"target": target.id, "effect": str(entry.get("effect", ""))})
				if entry.get("lethargy", false) == true and target.is_alive():
					_apply_condition(target, Conditions.TURN_LOST, str(entry.get("source", "")), Conditions.duration(Conditions.DURATION_TARGET_TURN_END))
			return


## Ends every buff named `effect` on c.
func _end_buffs_named(c: Combatant, effect: String) -> void:
	for b: Dictionary in c.buffs.duplicate():
		if str(b.get("effect", "")) == effect:
			_remove_buff(c, b)


# --- damage ------------------------------------------------------------------------

## Applies damage through the sheet, then the "drop to 0" interventions: Death
## Ward (drops to 1 instead, once) and Relentless Rage (raging, not killed
## outright: CON save DC 10 (+5 per use since the last rest) to drop to 1).
## Wild Shape / Polymorph forms revert at 0 hp, the excess carrying over.
## Emits death_avoided {target, feature, hp_after}. Records died_round.
func _take_damage(target: Combatant, amount: int, critical: bool = false) -> DamageOutcome:
	var hp_before := target.sheet.current_hp
	if target.raging and amount > 0:
		target.rage_kept = true
	var outcome := target.sheet.take_damage(amount, critical)
	if outcome.dropped_to_zero and not target.form.is_empty():
		var excess := maxi(0, amount - outcome.absorbed_by_temp - hp_before)
		_revert_form(target, "dropped")
		if excess > 0 and target.is_alive():
			var carry := target.sheet.take_damage(excess, critical)
			outcome.dropped_to_zero = carry.dropped_to_zero
			outcome.died = carry.died
		else:
			outcome.dropped_to_zero = false
			outcome.died = false
		outcome.hp_after = target.sheet.current_hp
	if outcome.dropped_to_zero:
		var ward := {}
		for b in target.buffs:
			if b.get("death_ward", false) == true:
				ward = b
		if not ward.is_empty() or target.sheet.active_buffs.has("death_ward"):
			if ward.is_empty():
				target.sheet.active_buffs.erase("death_ward")
			else:
				_remove_buff(target, ward)
			_restore_to_one(target, outcome)
			_emit("death_avoided", {"target": target.id, "feature": "death_ward", "hp_after": 1})
		elif target.raging and target.sheet.has_feature("relentless_rage") and not outcome.instant_death:
			var dc := 10 + 5 * target.sheet.relentless_rage_uses
			target.sheet.relentless_rage_uses += 1
			target.sheet.dead = false
			if _saving_throw(target.id, target, Ability.Type.CON, dc):
				_restore_to_one(target, outcome)
				_emit("death_avoided", {"target": target.id, "feature": "relentless_rage", "hp_after": 1})
			elif not target.sheet.uses_death_saves:
				target.sheet.kill()
	if target.sheet.is_dead() and target.died_round < 0:
		target.died_round = tracker.round_number
	return outcome


func _restore_to_one(target: Combatant, outcome: DamageOutcome) -> void:
	target.sheet.dead = false
	target.sheet.current_hp = 1
	target.sheet.reset_death_saves()
	outcome.dropped_to_zero = false
	outcome.died = false
	outcome.instant_death = false
	outcome.hp_after = 1


## Damage from an effect (tile effects, Fire Shield, damage over time):
## applies it and emits damage {target, amount, type, hp_after, dropped, died,
## ...fields} (fields carry "spell" / "effect" / "over_time").
func _deal_effect_damage(source: Combatant, target: Combatant, amount: int, damage_type: String, fields: Dictionary) -> void:
	var outcome := _take_damage(target, amount)
	var ev := {
		"target": target.id, "amount": outcome.amount, "type": damage_type, "hp_after": target.sheet.current_hp,
		"dropped": outcome.dropped_to_zero, "died": outcome.died,
	}
	ev.merge(fields)
	_emit("damage", ev)
	_after_damage(source, target, outcome.amount, outcome.dropped_to_zero)
	if not target.is_conscious():
		target.dodging = false


# --- tile effects (lingering spell areas) ---------------------------------------------

## Creates a tile effect from a spell's "zone" data (see SpellDefinition.zone)
## covering `cells` (anchored effects follow their anchor). Emits
## tile_effect_created {id, effect, source, spell, tiles, rounds}; "create"
## triggers resolve at once for every creature inside. Returns the entry.
func _create_tile_effect(caster: Combatant, spell: SpellDefinition, slot: int, cells: Array[Vector2i], anchor_id: String = "", centre: Vector2i = Vector2i(-1, -1)) -> Dictionary:
	var z := spell.zone.duplicate(true)
	var terrain_modes: Variant = z.get("terrain_modes", null)
	if typeof(terrain_modes) == TYPE_DICTIONARY:
		var tm: Dictionary = terrain_modes
		z["terrain"] = str(tm.get(str(_cast_intent.get("mode", "")), z.get("terrain", "")))
	if z.has("globe"):
		z["globe"] = DictUtil.to_int(z["globe"], 5) + maxi(0, slot - spell.level)
	return _create_zone(caster, spell.id, z, slot, cells, anchor_id, spell.area_size_tiles(), spell.concentration,
			Encounter._zone_damage(spell, z, slot), str(z.get("damage_type", spell.damage_type)), spell.level, centre)


## Creates a tile effect from zone data `z` (a spell's "zone", or a feature's:
## Holy Nimbus). Round C fields: "terrain" ("solid": the tiles become walls
## that block movement and sight; "open": walls become floor), "opaque"
## (blocks sight only), "wind" (ranged weapon attacks through it are lost),
## "barrier" ("living": hostile creatures other than undead / constructs
## cannot enter or reach in, and are pushed out), "globe" (spells of that
## level or lower cast from outside cannot affect creatures inside),
## "antimagic", "layers" (Prismatic Wall), "phases" (Storm of Vengeance: one
## effect per caster turn), "difficult_cost", "fall" (falling damage dice),
## "breaks_concentration" (Earthquake).
func _create_zone(caster: Combatant, spell_id: String, z: Dictionary, slot: int, cells: Array[Vector2i], anchor_id: String, radius: int,
		concentration: bool, damage: String, damage_type: String, spell_level: int, centre: Vector2i = Vector2i(-1, -1)) -> Dictionary:
	_effect_counter += 1
	var rounds := DictUtil.to_int(z.get("rounds", -1), -1)
	var fx := {
		"id": "fx%d" % _effect_counter,
		"effect": spell_id,
		"spell": spell_id,
		"source": caster.id,
		"team": caster.team,
		"cells": cells,
		"anchor": anchor_id,
		"radius": radius,
		"turns_left": rounds,
		"concentration": concentration,
		"difficult": z.get("difficult", false) == true,
		"ground": z.get("ground", false) == true,
		"obscured": z.get("obscured", false) == true,
		"silence": z.get("silence", false) == true,
		"plant": z.get("plant", false) == true,
		"affects": str(z.get("affects", "all")),
		"triggers": DictUtil.to_string_array(z.get("triggers", [])),
		"save": str(z.get("save", "")),
		"dc": DictUtil.to_int(z.get("dc", caster.sheet.spell_save_dc()), 10),
		"damage": damage,
		"damage_type": damage_type,
		"on_save": str(z.get("on_save", "none")),
		"per_tile_damage": str(z.get("per_tile_damage", "")),
		"condition": str(z.get("condition", "")),
		"condition_duration": Conditions.normalize_duration(z.get("condition_duration", {})),
		"pool": DictUtil.to_int(z.get("pool", 0), 0),
		"drift_tiles": GridMath.feet_to_tiles(DictUtil.to_int(z.get("drift_ft", 0), 0)),
		"move_tiles": GridMath.feet_to_tiles(DictUtil.to_int(z.get("move_ft", 0), 0)),
		"move_cost": str(z.get("move", "")),
		"slot_level": slot,
		"spell_level": spell_level,
		"hit": {},
		"terrain": str(z.get("terrain", "")),
		"opaque": z.get("opaque", false) == true,
		"wind": z.get("wind", false) == true,
		"barrier": str(z.get("barrier", "")),
		"globe": DictUtil.to_int(z.get("globe", -1), -1),
		"antimagic": z.get("antimagic", false) == true,
		"layers": DictUtil.to_string_array(z.get("layers", [])),
		"phases": DictUtil.to_dict_array(z.get("phases", [])),
		"age": 0,
		"difficult_cost": DictUtil.to_int(z.get("difficult_cost", 2), 2),
		"fall": str(z.get("fall", "")),
		"breaks_concentration": z.get("breaks_concentration", false) == true,
		"creature_types": DictUtil.to_string_array(z.get("creature_types", [])),
		"darkness": z.get("darkness", false) == true,
		"lit": z.get("lit", false) == true,
	}
	if centre.x >= 0:
		fx["centre"] = GridMath.vec_to_arr(centre)
	tile_effects.append(fx)
	var created := {"id": fx["id"], "effect": spell_id, "source": caster.id, "spell": spell_id,
			"tiles": GridMath.vec_list_to_arr(cells), "rounds": rounds, "anchor": anchor_id}
	for flag: String in ["terrain", "barrier"]:
		if not str(fx[flag]).is_empty():
			created[flag] = fx[flag]
	for flag: String in ["opaque", "wind", "antimagic", "darkness", "lit"]:
		if fx[flag] == true:
			created[flag] = true
	if DictUtil.to_int(fx["globe"]) >= 0:
		created["globe"] = fx["globe"]
	_emit("tile_effect_created", created)
	if fx["triggers"].has("create"):
		for c in tracker.order():
			if c.is_alive() and _effect_covers(fx, c.position) and tile_effects.has(fx):
				_trigger_tile_effect(fx, c, "create")
	var phases: Array[Dictionary] = fx["phases"]
	if not phases.is_empty() and tile_effects.has(fx):
		_run_phase(fx, 0)
	_after_zone_change(fx, cells)
	return fx


## Damage formula of a zone at slot: "damage_by_slot" in the zone, the spell's
## damage_by_slot, or zone "damage" plus "per_slot_level_above".
static func _zone_damage(spell: SpellDefinition, z: Dictionary, slot: int) -> String:
	var base := str(z.get("damage", ""))
	if base.is_empty() and not spell.damage.is_empty():
		return spell.damage_formula(0, slot)
	var per := str(z.get("per_slot_level_above", ""))
	if not per.is_empty() and slot > spell.level:
		return DiceFormula.plus(base, per, slot - spell.level)
	return base


func _effect_cells(fx: Dictionary) -> Array[Vector2i]:
	var cells: Array[Vector2i] = fx["cells"]
	return cells


func _effect_covers(fx: Dictionary, tile: Vector2i) -> bool:
	return _effect_cells(fx).has(tile)


## Whether a tile effect acts on c: living, targetable; "hostiles" effects
## spare the caster's team; ground effects spare flyers and levitating creatures.
func _effect_affects(fx: Dictionary, c: Combatant) -> bool:
	if not c.is_alive() or c.untargetable:
		return false
	if str(fx.get("affects", "all")) == "hostiles" and c.team == DictUtil.to_int(fx.get("team", -1), -1):
		return false
	if fx.get("ground", false) == true and c.ignores_ground():
		return false
	if not c.illusion.is_empty():
		return false
	if c.is_sealed() or (c.antimagic and fx.get("antimagic", false) != true):
		return false
	var types := DictUtil.to_string_array(fx.get("creature_types", []))
	if not types.is_empty() and not types.has(c.creature_type):
		return false
	var source := get_combatant(str(fx.get("source", "")))
	if source != null and source != c and _warded_by_globe(source, c, DictUtil.to_int(fx.get("spell_level", 0), 0)):
		return false
	return true


## A tile covered by an obscuring effect (Fog Cloud, Darkness): hiding is possible there.
func _tile_obscured(tile: Vector2i) -> bool:
	for fx in tile_effects:
		if fx.get("obscured", false) == true and _effect_covers(fx, tile):
			return true
	return false


## A tile inside Silence (no spells with verbal components).
func _tile_silenced(tile: Vector2i) -> bool:
	for fx in tile_effects:
		if fx.get("silence", false) == true and _effect_covers(fx, tile):
			return true
	return false


## Entering tiles: "enter" effects trigger once per turn when c moves into
## one of their tiles from outside; "per_tile" damage (Spike Growth) applies
## for every tile walked inside.
func _tile_effects_on_enter(c: Combatant, from: Vector2i, walked: bool) -> void:
	for fx: Dictionary in tile_effects.duplicate():
		if not tile_effects.has(fx) or not _effect_covers(fx, c.position):
			continue
		var triggers: Array[String] = fx["triggers"]
		if walked and not str(fx.get("per_tile_damage", "")).is_empty():
			_per_tile_damage(fx, c)
		if triggers.has("enter") and not _effect_covers(fx, from):
			_trigger_tile_effect(fx, c, "enter")
		if not c.is_alive() or state != State.ACTIVE:
			return


func _per_tile_damage(fx: Dictionary, c: Combatant) -> void:
	if not _effect_affects(fx, c):
		return
	var dtype := str(fx.get("damage_type", ""))
	var amount := c.adjust_damage(maxi(0, DiceFormula.parse(str(fx["per_tile_damage"])).roll(rng)["total"]), dtype, true)
	_emit("tile_effect_triggered", {"id": fx["id"], "target": c.id, "trigger": "per_tile"})
	_deal_effect_damage(get_combatant(str(fx["source"])), c, amount, dtype, {"spell": str(fx["spell"]), "effect_id": str(fx["id"])})


## Resolves one trigger of a tile effect on c (once per turn for enter /
## start_turn / end_turn): tile_effect_triggered {id, target, trigger}, then
## the save (Evasion applies to DEX "half" saves), damage and condition.
func _trigger_tile_effect(fx: Dictionary, c: Combatant, trigger: String) -> void:
	if not _effect_affects(fx, c):
		return
	var hit: Dictionary = fx["hit"]
	if trigger != "create":
		var key := "%s:%s" % [c.id, "turn" if trigger in ["enter", "start_turn"] else trigger]
		if DictUtil.to_int(hit.get(key, -1), -1) == turn_counter:
			return
		hit[key] = turn_counter
	_emit("tile_effect_triggered", {"id": fx["id"], "target": c.id, "trigger": trigger})
	_zone_hit(fx, fx, c)


## One creature hit by a tile effect, with the rules in `spec` (the effect
## itself, or one of its phases): the save (Evasion applies to DEX "half"
## saves), damage, falling damage, condition, prismatic layers, and
## Earthquake's concentration save.
func _zone_hit(fx: Dictionary, spec: Dictionary, c: Combatant) -> void:
	var source := get_combatant(str(fx["source"]))
	var source_id := str(fx["source"])
	var dc := DictUtil.to_int(fx["dc"], 10)
	var save := str(spec.get("save", ""))
	var success := false
	var ability := Ability.from_string(save) if not save.is_empty() else -1
	if ability >= 0:
		success = _saving_throw(source_id, c, ability, dc, {"plant": fx.get("plant", false) == true, "vs_condition": str(spec.get("condition", ""))})
	var formula := str(spec.get("damage", ""))
	var dtype := str(spec.get("damage_type", fx.get("damage_type", "")))
	if not formula.is_empty() and c.is_alive():
		var rolled := maxi(0, DictUtil.to_int(DiceFormula.parse(formula).roll(rng)["total"]))
		var amount := _save_damage(c, ability, rolled, success, str(spec.get("on_save", "none")) == "half")
		if amount > 0 or not success:
			amount = c.adjust_damage(amount, dtype, true)
			_deal_effect_damage(source, c, amount, dtype, {"spell": str(fx["spell"]), "effect_id": str(fx["id"])})
			if DictUtil.to_int(fx.get("pool", 0), 0) > 0:
				fx["pool"] = DictUtil.to_int(fx["pool"]) - amount
				if DictUtil.to_int(fx["pool"]) <= 0:
					_end_tile_effect(fx, "exhausted")
					return
	if not success and c.is_alive() and not str(spec.get("fall", "")).is_empty():
		_fall(c, str(spec["fall"]), source_id, str(fx["spell"]))
	var condition := str(spec.get("condition", ""))
	if not condition.is_empty() and not success and c.is_alive():
		var duration: Dictionary = Conditions.normalize_duration(spec.get("condition_duration", {}))
		if duration.is_empty():
			duration = Conditions.duration(Conditions.DURATION_ROUNDS, {"rounds": 1})
		var extra := {"spell": str(fx["spell"])} if fx.get("concentration", false) == true else {}
		_apply_condition(c, condition, source_id, duration, extra)
	for layer in DictUtil.to_string_array(spec.get("layers", [])):
		if not c.is_alive():
			break
		_prismatic_layer(source_id, c, layer, dc, str(fx["spell"]))
	if spec.get("breaks_concentration", false) == true and c.is_alive() and c.id != source_id and not c.concentration.is_empty():
		if not _saving_throw(source_id, c, Ability.Type.CON, dc):
			_end_concentration(c, "earthquake")


## Damage after a save: full on a failure; half or none on a success. Evasion
## (DEX saves for half): none on a success, half on a failure. Potent Cantrip
## is handled by the caller.
func _save_damage(target: Combatant, ability: int, rolled: int, success: bool, half_on_save: bool) -> int:
	var evasion := ability == Ability.Type.DEX and half_on_save and not target.is_incapacitated() \
			and (target.sheet.has_feature("evasion") or target.sheet.has_feature("superior_hunters_defense_evasion"))
	if evasion:
		return 0 if success else floori(rolled / 2.0)
	if success:
		return floori(rolled / 2.0) if half_on_save else 0
	return rolled


## Ends a tile effect: tile_effect_ended {id, reason}.
func _end_tile_effect(fx: Dictionary, reason: String) -> void:
	var i := tile_effects.find(fx)
	if i < 0:
		return
	tile_effects.remove_at(i)
	_emit("tile_effect_ended", {"id": fx["id"], "reason": reason})
	_after_zone_change(fx, _effect_cells(fx))


## Recomputes the tiles of effects anchored to c (Spirit Guardians) after it moved.
func _refresh_anchored(c: Combatant) -> void:
	for fx in tile_effects:
		if str(fx.get("anchor", "")) != c.id:
			continue
		fx["cells"] = AreaOfEffect.tiles("sphere", DictUtil.to_int(fx.get("radius", 1), 1), c.position, c.position, walk_map)
		_emit("tile_effect_moved", {"id": fx["id"], "tiles": GridMath.vec_list_to_arr(_effect_cells(fx))})
		_after_zone_change(fx, [])


## move_effect {effect, point}: moves a movable tile effect of the actor
## (Moonbeam: action, Flaming Sphere: bonus action) so it is centred on point
## (within the effect's move distance of its current centre).
func _check_move_effect(actor: Combatant, intent: Dictionary) -> String:
	var fx := _tile_effect_by_id(str(intent.get("effect", "")))
	if fx.is_empty() or str(fx["source"]) != actor.id or str(fx.get("move_cost", "")).is_empty():
		return "no movable effect '%s' of %s" % [str(intent.get("effect", "")), actor.display_name]
	var err := _action_error(actor) if str(fx["move_cost"]) == "action" else _bonus_error(actor)
	if not err.is_empty():
		return err
	if not GridMath.is_vec_arr(intent.get("point", null)):
		return "move_effect needs a point [x, y]"
	var point := GridMath.arr_to_vec(intent["point"])
	if not region.has_point(point) or not walk_map.is_walkable(point):
		return "the point is not open ground"
	if GridMath.distance_tiles(Encounter._effect_centre(fx), point) > DictUtil.to_int(fx.get("move_tiles", 0), 0):
		return "the effect moves at most %d tiles" % DictUtil.to_int(fx.get("move_tiles", 0), 0)
	return ""


func _do_move_effect(actor: Combatant, intent: Dictionary) -> void:
	var fx := _tile_effect_by_id(str(intent.get("effect", "")))
	if str(fx["move_cost"]) == "action":
		actor.action_used = true
	else:
		actor.bonus_action_used = true
	_relocate_effect(fx, GridMath.arr_to_vec(intent["point"]))


## Moves an effect so it is centred on point; creatures newly covered trigger "enter".
func _relocate_effect(fx: Dictionary, point: Vector2i) -> void:
	var before := _effect_cells(fx).duplicate()
	var spell := _spell_def(str(fx["spell"]))
	var shape := spell.area_shape if spell != null and not spell.area_shape.is_empty() else "sphere"
	fx["cells"] = AreaOfEffect.tiles(shape, DictUtil.to_int(fx.get("radius", 1), 1), point, point, walk_map)
	fx["centre"] = GridMath.vec_to_arr(point)
	_emit("tile_effect_moved", {"id": fx["id"], "tiles": GridMath.vec_list_to_arr(_effect_cells(fx))})
	var triggers: Array[String] = fx["triggers"]
	if triggers.has("enter"):
		for c in tracker.order():
			if c.is_alive() and _effect_covers(fx, c.position) and not before.has(c.position):
				_trigger_tile_effect(fx, c, "enter")


## The centre of an effect: its stored "centre", else the middle of its tiles.
static func _effect_centre(fx: Dictionary) -> Vector2i:
	if GridMath.is_vec_arr(fx.get("centre", null)):
		return GridMath.arr_to_vec(fx["centre"])
	var cells: Array[Vector2i] = fx["cells"]
	if cells.is_empty():
		return Vector2i.ZERO
	var sum := Vector2i.ZERO
	for p in cells:
		sum += p
	return Vector2i(roundi(float(sum.x) / cells.size()), roundi(float(sum.y) / cells.size()))


func _tile_effect_by_id(effect_id: String) -> Dictionary:
	for fx in tile_effects:
		if str(fx["id"]) == effect_id:
			return fx
	return {}


## Start of c's turn: tile effects with "start_turn" covering c trigger; the
## caster's drifting effects (Cloudkill) move away from it first.
func _tile_effects_turn_start(c: Combatant) -> void:
	for fx: Dictionary in tile_effects.duplicate():
		var phases: Array[Dictionary] = fx["phases"]
		if str(fx["source"]) == c.id and not phases.is_empty() and tile_effects.has(fx):
			fx["age"] = DictUtil.to_int(fx["age"]) + 1
			_run_phase(fx, mini(DictUtil.to_int(fx["age"]), phases.size() - 1))
	for fx: Dictionary in tile_effects.duplicate():
		if str(fx["source"]) == c.id and DictUtil.to_int(fx.get("drift_tiles", 0), 0) > 0:
			var centre := Encounter._effect_centre(fx)
			var dir := centre - c.position
			var step := Vector2i(signi(dir.x), signi(dir.y))
			if step == Vector2i.ZERO:
				step = Vector2i(1, 0)
			_relocate_effect(fx, centre + step * DictUtil.to_int(fx["drift_tiles"]))
	for fx: Dictionary in tile_effects.duplicate():
		if not tile_effects.has(fx) or not c.is_alive():
			continue
		var triggers: Array[String] = fx["triggers"]
		if triggers.has("start_turn") and _effect_covers(fx, c.position):
			_trigger_tile_effect(fx, c, "start_turn")


## End of c's turn: "end_turn" effects covering c trigger; effects c created
## count down (rounds) and end.
func _tile_effects_turn_end(c: Combatant) -> void:
	for fx: Dictionary in tile_effects.duplicate():
		if not tile_effects.has(fx) or not c.is_alive():
			continue
		var triggers: Array[String] = fx["triggers"]
		if triggers.has("end_turn") and _effect_covers(fx, c.position):
			_trigger_tile_effect(fx, c, "end_turn")
	for fx: Dictionary in tile_effects.duplicate():
		if str(fx["source"]) != c.id or DictUtil.to_int(fx.get("turns_left", -1), -1) < 0:
			continue
		fx["turns_left"] = DictUtil.to_int(fx["turns_left"]) - 1
		if DictUtil.to_int(fx["turns_left"]) <= 0:
			_end_tile_effect(fx, "expired")


# --- summons, companions and forms ------------------------------------------------------

## Adds a creature summoned by owner: it joins owner's team, acts right after
## owner every round (the encounter runs its turns with MonsterBrain) and
## never keeps its team in the fight. `def` is a MonsterDefinition, or null
## with `custom` = {"sheet": CharacterSheet, "attacks": [...], "monster_id"}
## (Spiritual Weapon). Placed on the free walkable tile nearest `near`.
## rounds: owner turn ends before it vanishes (-1 = no limit). extra may set
## "familiar", "untargetable", "companion_index", "concentration". Emits
## combatant_joined (+ "owner") and summoned {caster, spell, id, monster,
## position}. Returns null when no tile is free.
func _summon(owner: Combatant, spell_id: String, def: MonsterDefinition, near: Vector2i, rounds: int, extra: Dictionary = {}, custom: Dictionary = {}) -> Combatant:
	var tile := _free_tile_near(near, DictUtil.to_bool(extra.get("untargetable", false), false))
	if tile.x < 0:
		return null
	_summon_counter += 1
	var c: Combatant = null
	var monster := ""
	if def != null:
		monster = def.id
		c = Combatant.from_monster("%s_%s_%d" % [owner.id, def.id, _summon_counter], def, owner.team, null, false)
	else:
		monster = str(custom.get("monster_id", spell_id))
		c = Combatant.new()
		c.id = "%s_%s_%d" % [owner.id, monster, _summon_counter]
		c.sheet = custom["sheet"]
		c.display_name = c.sheet.name
		c.team = owner.team
		c.monster_id = monster
		for a: Dictionary in custom.get("attacks", []):
			c.attacks.append(a.duplicate(true))
	c.position = tile
	c.owner_id = owner.id
	c.summon_spell = spell_id
	c.summon_turns_left = rounds
	c.auto_controlled = true
	c.familiar = DictUtil.to_bool(extra.get("familiar", false), false)
	c.untargetable = DictUtil.to_bool(extra.get("untargetable", false), false)
	c.companion_index = DictUtil.to_int(extra.get("companion_index", -1), -1)
	c.summon_concentration = DictUtil.to_bool(extra.get("concentration", false), false)
	if typeof(extra.get("illusion", null)) == TYPE_DICTIONARY:
		c.illusion = (extra["illusion"] as Dictionary).duplicate()
	if not tracker.insert_after(c, owner):
		return null
	_combatants[c.id] = c
	var joined := {
		"id": c.id, "name": c.display_name, "team": c.team, "initiative": c.initiative,
		"position": GridMath.vec_to_arr(c.position), "hp": c.sheet.current_hp, "max_hp": c.sheet.max_hp,
		"ac": c.sheet.armor_class(), "owner": owner.id, "monster": monster,
	}
	if not c.illusion.is_empty():
		joined["illusion"] = true
	_emit("combatant_joined", joined)
	_emit("summoned", {"caster": owner.id, "spell": spell_id, "id": c.id, "monster": monster, "position": GridMath.vec_to_arr(c.position)})
	return c


## Nearest free walkable tile to p inside the region (Chebyshev rings, then
## row-major), or (-1, -1). Untargetable spell objects may share no tile either.
func _free_tile_near(p: Vector2i, _object: bool = false) -> Vector2i:
	var occupied := occupied_cells()
	for r in range(0, 12):
		for y in range(p.y - r, p.y + r + 1):
			for x in range(p.x - r, p.x + r + 1):
				var t := Vector2i(x, y)
				if GridMath.distance_tiles(t, p) != r:
					continue
				if region.has_point(t) and walk_map.is_walkable(t) and not occupied.has(t):
					return t
	return Vector2i(-1, -1)


## Removes a summon: summon_ended {id, reason} and combatant_removed {id}. A
## companion that dropped is marked dead on its owner's sheet. (The tracker
## entry goes once it is not the current actor.)
func _dismiss(c: Combatant, reason: String) -> void:
	if not _combatants.has(c.id):
		return
	if c.companion_index >= 0 and reason in ["dropped", "concentration"]:
		var owner := get_combatant(c.owner_id)
		if owner != null and c.companion_index < owner.sheet.companions.size():
			owner.sheet.companions[c.companion_index]["dead"] = true
	if c.is_alive():
		c.sheet.kill()
	_combatants.erase(c.id)
	_emit("summon_ended", {"id": c.id, "reason": reason})
	_emit("combatant_removed", {"id": c.id})
	if tracker.current() != c:
		tracker.remove(c.id)
	else:
		_dismissed.append(c.id)


## Drops tracker entries of dismissed summons that were current when dismissed.
func _purge_dismissed() -> void:
	for cid: String in _dismissed.duplicate():
		var cur := tracker.current()
		if cur == null or cur.id != cid:
			tracker.remove(cid)
			_dismissed.erase(cid)


## Summons of `owner` tied to a spell (concentration or the owner's turn count).
func _summons_of(owner_id: String) -> Array[Combatant]:
	var out: Array[Combatant] = []
	for value: Variant in _combatants.values():
		var c: Combatant = value
		if c.owner_id == owner_id:
			out.append(c)
	return out


## Companions on a newly joined combatant's sheet (Find Familiar, Animate
## Dead) appear next to it. Called when the encounter starts and when a
## combatant joins mid-fight.
func _spawn_companions(owner: Combatant) -> void:
	var monsters: Dictionary = _content().get("monsters", {})
	for i in range(owner.sheet.companions.size()):
		var entry: Dictionary = owner.sheet.companions[i]
		if entry.get("dead", false) == true or not owner.is_conscious():
			continue
		var spell_id := str(entry.get("spell", ""))
		var extra := {"companion_index": i, "familiar": spell_id == "find_familiar" or entry.get("familiar", false) == true}
		var concentration: bool = entry.get("concentration", false) == true
		if concentration:
			var spell := _spell_def(spell_id)
			if spell != null and str(owner.concentration.get("spell", "")) != spell_id:
				_start_concentration(owner, spell, DictUtil.to_int(entry.get("slot_level", spell.level), spell.level))
			extra["concentration"] = true
		var c: Combatant = null
		var custom := str(entry.get("custom", ""))
		if not custom.is_empty():
			extra["untargetable"] = entry.get("untargetable", false) == true
			c = _summon(owner, spell_id, null, owner.position, -1, extra, _custom_companion(owner, entry))
		else:
			var mid := str(entry.get("monster", ""))
			if not monsters.has(mid):
				continue
			var def: MonsterDefinition = monsters[mid]
			c = _summon(owner, spell_id, def, owner.position, -1, extra)
		if c != null and entry.has("hp"):
			c.sheet.current_hp = clampi(DictUtil.to_int(entry["hp"], c.sheet.max_hp), 1, c.sheet.max_hp)


## Encounter end: companions write their hit points back to the owner's
## sheet (dead ones are dropped from it); forms revert.
func _settle_companions() -> void:
	for c in tracker.order():
		if not c.form.is_empty():
			_revert_form(c, "encounter_end")
	for value: Variant in _combatants.values():
		var c: Combatant = value
		if c.companion_index < 0:
			continue
		var owner := get_combatant(c.owner_id)
		if owner != null and c.companion_index < owner.sheet.companions.size():
			owner.sheet.companions[c.companion_index]["hp"] = c.sheet.current_hp
	for value: Variant in _combatants.values():
		var c: Combatant = value
		if c.is_summon():
			continue
		var kept: Array[Dictionary] = []
		for entry in c.sheet.companions:
			if entry.get("dead", false) == true:
				continue
			if entry.has("encounters_left") and DictUtil.to_int(entry["encounters_left"], -1) > 0:
				entry["encounters_left"] = DictUtil.to_int(entry["encounters_left"]) - 1
				if DictUtil.to_int(entry["encounters_left"]) <= 0:
					continue
			kept.append(entry)
		c.sheet.companions = kept


## Spiritual Weapon: an untargetable spectral weapon making melee spell
## attacks (1d8 + casting modifier force, +1d8 per two slot levels above 2nd).
## Arcane Sword ("arcane_sword"): 3d10 force.
func _spiritual_weapon_custom(caster: Combatant, slot: int, kind: String = "spiritual_weapon") -> Dictionary:
	var s := CharacterSheet.new()
	s.name = "Arcane Sword" if kind == "arcane_sword" else "Spiritual Weapon"
	s.class_id = "monster:" + kind
	s.max_hp = 1
	s.current_hp = 1
	s.speed = 20
	s.uses_death_saves = false
	s.armor_base = 99
	s.damage_immunities = CharacterSheet.DAMAGE_TYPES.duplicate()
	s.condition_immunities = Conditions.ALL.duplicate()
	var dice := 1 + floori(maxi(0, slot - 2) / 2.0)
	var damage := "%dd8" % dice + CharacterBuilder.signed(caster.sheet.casting_modifier())
	if kind == "arcane_sword":
		damage = "3d10"
		s.speed = 20
	if kind == "arcane_hand":
		# Arcane Hand (SRD): AC 20, hit points = the caster's maximum, Clenched Fist 4d8 force (+2d8 per slot above 5th).
		s.name = "Arcane Hand"
		s.max_hp = caster.sheet.max_hp
		s.current_hp = caster.sheet.max_hp
		s.armor_base = 20
		s.speed = 60
		s.abilities.set_score(Ability.Type.STR, 26)
		s.abilities.set_score(Ability.Type.DEX, 10)
		s.damage_immunities = []
		s.condition_immunities = []
		damage = "%dd8" % (4 + 2 * maxi(0, slot - 5))
	var damage_type := "force"
	var to_hit := caster.sheet.spell_attack_bonus()
	match kind:
		"animated_object":
			# Animate Objects (SRD): a Tiny object: AC 18, 20 hp, +8 to hit, 1d4 + 4.
			s.name = "Animated Object"
			s.max_hp = 20
			s.current_hp = 20
			s.armor_base = 18
			s.speed = 30
			s.abilities.set_score(Ability.Type.DEX, 10)
			s.damage_immunities = ["poison", "psychic"]
			s.condition_immunities = []
			damage = "1d4+4"
			damage_type = "bludgeoning"
			to_hit = 8
		"faithful_hound":
			# Faithful Hound (SRD): invisible, unharmable, bites a hostile within 5 ft for 4d8 piercing.
			s.name = "Faithful Hound"
			s.speed = 0
			damage = "4d8"
			damage_type = "piercing"
		"unseen_servant":
			# Unseen Servant (SRD): AC 10, 1 hp, STR 2: it cannot attack; it helps.
			s.name = "Unseen Servant"
			s.armor_base = 10
			s.speed = 15
			s.damage_immunities = []
			s.condition_immunities = []
			return {"sheet": s, "attacks": [{"name": "Help", "kind": "melee", "to_hit": -10, "damage": "0", "damage_type": "bludgeoning", "range_tiles": [1, 1]}], "monster_id": kind}
	var attack := {
		"name": s.name, "kind": "melee", "to_hit": to_hit,
		"damage": damage, "damage_type": damage_type, "magical": true, "range_tiles": [1, 1],
	}
	return {"sheet": s, "attacks": [attack], "monster_id": kind}


## A companion entry with "custom": a simulacrum (a copy of its "sheet"), or
## a spell object of that kind (Unseen Servant, ...).
func _custom_companion(owner: Combatant, entry: Dictionary) -> Dictionary:
	var kind := str(entry.get("custom", ""))
	if kind == "simulacrum" and typeof(entry.get("sheet", null)) == TYPE_DICTIONARY:
		var s := CharacterSheet.from_dict(entry["sheet"])
		s.uses_death_saves = false
		var attacks: Array[Dictionary] = []
		for a in s.attacks:
			attacks.append(a.duplicate(true))
		attacks.append(s.unarmed_strike())
		return {"sheet": s, "attacks": attacks, "monster_id": "simulacrum"}
	return _spiritual_weapon_custom(owner, DictUtil.to_int(entry.get("slot_level", 1), 1), kind)


## Wild Shape / Polymorph: c takes a beast's STR, DEX, CON, hit points, AC,
## speed, size and attacks (its own INT, WIS, CHA and features stay). At 0 hp
## it reverts and excess damage carries over. Emits transformed {target,
## form, kind, hp, source}.
func _transform(c: Combatant, def: MonsterDefinition, kind: String, source_id: String, spell_id: String = "") -> void:
	if not c.form.is_empty():
		_revert_form(c, "new_form")
	var s := c.sheet
	var saved := {
		"STR": s.abilities.get_score(Ability.Type.STR), "DEX": s.abilities.get_score(Ability.Type.DEX),
		"CON": s.abilities.get_score(Ability.Type.CON), "max_hp": s.max_hp, "current_hp": s.current_hp,
		"armor_base": s.armor_base, "armor_max_dex": s.armor_max_dex, "shield_bonus": s.shield_bonus,
		"speed": s.speed, "fly_speed": s.fly_speed, "size": s.size, "attacks": c.attacks.duplicate(true),
		"attacks_per_action": c.attacks_per_action, "multiattack": c.multiattack.duplicate(),
		"creature_type": c.creature_type, "skill_bonuses": s.skill_bonuses.duplicate(),
		"save_bonuses": s.save_bonuses.duplicate(), "uses_death_saves": s.uses_death_saves,
	}
	s.abilities.set_score(Ability.Type.STR, def.abilities.get_score(Ability.Type.STR))
	s.abilities.set_score(Ability.Type.DEX, def.abilities.get_score(Ability.Type.DEX))
	s.abilities.set_score(Ability.Type.CON, def.abilities.get_score(Ability.Type.CON))
	s.max_hp = def.hit_points_avg
	s.current_hp = def.hit_points_avg
	s.armor_base = def.armor_class - s.abilities.get_modifier(Ability.Type.DEX)
	s.armor_max_dex = -1
	s.shield_bonus = 0
	s.speed = def.speed
	s.fly_speed = def.fly_speed
	s.size = def.size
	s.skill_bonuses = def.skills.duplicate()
	if kind in ["polymorph", "true_polymorph", "animal_shapes", "magic_jar"]:
		s.save_bonuses = def.saving_throws.duplicate()
	s.uses_death_saves = false
	c.attacks.clear()
	for a in def.attacks:
		c.attacks.append(a.duplicate(true))
	c.multiattack = def.multiattack.duplicate()
	c.attacks_per_action = maxi(1, def.multiattack.size())
	c.creature_type = def.creature_type
	c.form = {"monster": def.id, "kind": kind, "source": source_id, "spell": spell_id, "saved": saved}
	_emit("transformed", {"target": c.id, "form": def.id, "kind": kind, "hp": s.current_hp, "source": source_id})


## Back to its own form: reverted {target, reason, hp_after}.
func _revert_form(c: Combatant, reason: String) -> void:
	if c.form.is_empty():
		return
	var saved: Dictionary = c.form["saved"]
	var s := c.sheet
	saved["kind"] = str(c.form.get("kind", ""))
	saved["host"] = str(c.form.get("host", ""))
	saved["form_hp"] = s.current_hp
	s.abilities.set_score(Ability.Type.STR, DictUtil.to_int(saved["STR"]))
	s.abilities.set_score(Ability.Type.DEX, DictUtil.to_int(saved["DEX"]))
	s.abilities.set_score(Ability.Type.CON, DictUtil.to_int(saved["CON"]))
	s.max_hp = DictUtil.to_int(saved["max_hp"])
	s.current_hp = clampi(DictUtil.to_int(saved["current_hp"]), 0, s.max_hp)
	s.dead = false
	s.armor_base = DictUtil.to_int(saved["armor_base"])
	s.armor_max_dex = DictUtil.to_int(saved["armor_max_dex"])
	s.shield_bonus = DictUtil.to_int(saved["shield_bonus"])
	s.speed = DictUtil.to_int(saved["speed"])
	s.fly_speed = DictUtil.to_int(saved["fly_speed"])
	s.size = str(saved["size"])
	s.skill_bonuses = saved["skill_bonuses"]
	s.save_bonuses = saved["save_bonuses"]
	s.uses_death_saves = saved["uses_death_saves"] == true
	c.attacks.clear()
	for a: Dictionary in saved["attacks"]:
		c.attacks.append(a)
	c.attacks_per_action = DictUtil.to_int(saved["attacks_per_action"], 1)
	c.multiattack = DictUtil.to_string_array(saved["multiattack"])
	c.creature_type = str(saved["creature_type"])
	var spell_id := str(c.form.get("spell", ""))
	var source_id := str(c.form.get("source", ""))
	c.form = {}
	_emit("reverted", {"target": c.id, "reason": reason, "hp_after": s.current_hp})
	if str(saved.get("kind", "")) == "magic_jar":
		_release_host(c, str(saved.get("host", "")), reason, DictUtil.to_int(saved.get("form_hp", 0), 0))
	if not spell_id.is_empty() and reason != "concentration":
		var src := get_combatant(source_id)
		if src != null and str(src.concentration.get("spell", "")) == spell_id:
			_end_concentration(src, "form_ended")


# --- round B class features (use_feature) ------------------------------------------------

## Validation of the round B use_feature ids; "-" when `feature` is not one.
func _check_feature_b(actor: Combatant, feature: String, intent: Dictionary) -> String:
	match feature:
		"intimidating_presence":
			var target := _cast_target(actor, intent)
			if target == null or target.team == actor.team or not target.is_conscious():
				return "Intimidating Presence needs a conscious hostile target"
			if GridMath.distance_tiles(actor.position, target.position) > INTIMIDATING_PRESENCE_RANGE_TILES or not can_see(target, actor):
				return "%s must see %s within 30 feet" % [target.display_name, actor.display_name]
			if _feature_immunity.has("intimidating_presence:" + target.id):
				return "%s is immune to the Intimidating Presence" % target.display_name
			return ""
		"countercharm", "wholeness_of_body", "divine_intervention", "dragon_wings":
			return ""
		"stillness_of_mind":
			if not actor.has_condition(Conditions.CHARMED) and not actor.has_condition(Conditions.FRIGHTENED):
				return "%s is neither charmed nor frightened" % actor.display_name
			return ""
		"cleansing_touch":
			var target := _cast_target(actor, intent)
			if target == null or target.team != actor.team or not target.is_alive():
				return "Cleansing Touch needs yourself or an ally"
			if target != actor and not GridMath.is_adjacent(actor.position, target.position):
				return "%s is out of reach" % target.display_name
			if _hostile_spells_on(actor, target).is_empty():
				return "no spell to end on %s" % target.display_name
			return ""
		"volley":
			var index := DictUtil.to_int(intent.get("attack_index", -1), -1)
			if index < 0 or index >= actor.attacks.size() or not Encounter.is_ranged_attack(actor.attacks[index]):
				return "Volley needs a ranged weapon attack_index"
			if not GridMath.is_vec_arr(intent.get("point", null)):
				return "Volley needs a point [x, y]"
			var point := GridMath.arr_to_vec(intent["point"])
			var tiles := Encounter.attack_range_tiles(actor.attacks[index])
			if GridMath.distance_tiles(actor.position, point) > tiles[1] or not walk_map.has_line_of_sight(actor.position, point):
				return "the point is out of range or sight"
			return ""
		"whirlwind_attack":
			var index := DictUtil.to_int(intent.get("attack_index", -1), -1)
			if index < 0 or index >= actor.attacks.size() or Encounter.is_ranged_attack(actor.attacks[index]):
				return "Whirlwind Attack needs a melee attack_index"
			return ""
		"elemental_affinity":
			if Encounter.dragon_damage_type(actor.sheet).is_empty():
				return "%s has no dragon ancestor" % actor.display_name
			return ""
		"wild_shape":
			var def := _wild_shape_def(actor, str(intent.get("form", "")))
			if def == null:
				return "%s cannot take that form (beast, CR %s at most)" % [actor.display_name, str(Encounter.wild_shape_max_cr(actor.sheet))]
			return ""
		"revert_form":
			return ""
		"empty_body":
			return ""
		"draconic_presence":
			if not str(intent.get("mode", "fear")) in ["awe", "fear"]:
				return "draconic_presence mode must be \"awe\" or \"fear\""
			return ""
	return _check_feature_c(actor, feature, intent)


## Hostile spell effects on target, grouped by spell id (Cleansing Touch).
func _hostile_spells_on(actor: Combatant, target: Combatant) -> Array[String]:
	var out: Array[String] = []
	for entry in target.conditions:
		var src := get_combatant(str(entry.get("source", "")))
		var sid := str(entry.get("spell", ""))
		if not sid.is_empty() and src != null and src.team != actor.team and not out.has(sid):
			out.append(sid)
	for b in target.buffs:
		var src := get_combatant(str(b.get("source", "")))
		var sid := str(b.get("spell", ""))
		if not sid.is_empty() and src != null and src.team != actor.team and not out.has(sid):
			out.append(sid)
	return out


## Wild Shape forms: beasts of CR <= the druid's limit (class table
## wild_shape_max_cr: 1/4, 1/2 at 4, 1 at 8), no fly speed before 8th level.
func _wild_shape_def(actor: Combatant, form: String) -> MonsterDefinition:
	var monsters: Dictionary = _content().get("monsters", {})
	if not monsters.has(form):
		return null
	var def: MonsterDefinition = monsters[form]
	if def.creature_type != "beast" or def.challenge_rating > Encounter.wild_shape_max_cr(actor.sheet):
		return null
	if def.fly_speed > 0 and actor.sheet.table_int("wild_shape_fly", 1 if actor.sheet.level >= 8 else 0) <= 0:
		return null
	return def


static func wild_shape_max_cr(sheet: CharacterSheet) -> float:
	var cls := sheet.class_definition()
	if cls != null and cls.tables.has("wild_shape_max_cr"):
		var v: Variant = cls.table_raw("wild_shape_max_cr", sheet.level)
		if DictUtil.is_number(v):
			return DictUtil.to_float(v, 0.25)
	return 1.0 if sheet.level >= 8 else (0.5 if sheet.level >= 4 else 0.25)


## Resolution of the round B use_feature ids (feature_used already emitted).
func _do_feature_b(actor: Combatant, feature: String, intent: Dictionary) -> void:
	match feature:
		"intimidating_presence":
			var target := _cast_target(actor, intent)
			var extending := false
			for entry in target.conditions:
				if str(entry.get("feature", "")) == "intimidating_presence" and str(entry.get("source", "")) == actor.id:
					extending = true
			if not extending:
				var dc := 8 + actor.sheet.proficiency_bonus() + actor.sheet.ability_modifier(Ability.Type.CHA)
				if _saving_throw(actor.id, target, Ability.Type.WIS, dc, {"vs_condition": Conditions.FRIGHTENED}):
					_feature_immunity["intimidating_presence:" + target.id] = true
					return
			_apply_condition(target, Conditions.FRIGHTENED, actor.id, Conditions.duration(Conditions.DURATION_SOURCE_NEXT_TURN), {"feature": "intimidating_presence"})
		"countercharm":
			_apply_buff(actor, "countercharm", actor.id, Conditions.duration(Conditions.DURATION_SOURCE_NEXT_TURN), {})
		"wholeness_of_body":
			_heal(actor.id, actor, 3 * actor.sheet.level)
		"stillness_of_mind":
			_end_conditions_named(actor, Conditions.CHARMED)
			_end_conditions_named(actor, Conditions.FRIGHTENED)
		"divine_intervention":
			var roll := rng.next_int(1, 100)
			var success := actor.sheet.level >= 20 or roll <= actor.sheet.level
			_emit("divine_intervention", {"actor": actor.id, "roll": roll, "success": success})
			if success:
				for c in tracker.order():
					if c.team == actor.team and c.is_alive() and not c.is_summon():
						_heal(actor.id, c, c.sheet.max_hp)
		"cleansing_touch":
			var target := _cast_target(actor, intent)
			var spells := _hostile_spells_on(actor, target)
			var sid := str(intent.get("mode", spells[0] if not spells.is_empty() else ""))
			for entry: Dictionary in target.conditions.duplicate():
				if str(entry.get("spell", "")) == sid:
					_remove_condition(target, entry)
			for b: Dictionary in target.buffs.duplicate():
				if str(b.get("spell", "")) == sid:
					_remove_buff(target, b)
		"volley":
			var index := DictUtil.to_int(intent.get("attack_index", 0), 0)
			var point := GridMath.arr_to_vec(intent["point"])
			for h in hostiles_of(actor):
				if not h.is_alive() or h.untargetable or GridMath.distance_tiles(h.position, point) > VOLLEY_RADIUS_TILES:
					continue
				if not attack_reach_error(actor.position, h.position, actor.attacks[index]).is_empty():
					continue
				var consumes := str(actor.attacks[index].get("consumes", ""))
				if not consumes.is_empty() and not actor.sheet.has_item(consumes):
					break
				_resolve_attack(actor, h, index)
			_after_own_attack(actor)
		"whirlwind_attack":
			var index := DictUtil.to_int(intent.get("attack_index", 0), 0)
			for h in hostiles_of(actor):
				if h.is_alive() and not h.untargetable and attack_reach_error(actor.position, h.position, actor.attacks[index]).is_empty():
					_resolve_attack(actor, h, index)
			_after_own_attack(actor)
		"elemental_affinity":
			actor.elemental_resistance = Encounter.dragon_damage_type(actor.sheet)
			_emit("effect_applied", {"source": actor.id, "target": actor.id, "effect": "elemental_affinity", "resist": actor.elemental_resistance})
		"dragon_wings":
			_apply_buff(actor, "dragon_wings", actor.id, Conditions.duration(Conditions.DURATION_ENCOUNTER), {"fly_ft": -1})
		"wild_shape":
			_transform(actor, _wild_shape_def(actor, str(intent.get("form", ""))), "wild_shape", actor.id)
		"revert_form":
			_revert_form(actor, "dismissed")
		"empty_body":
			_apply_condition(actor, Conditions.INVISIBLE, actor.id, Conditions.duration(Conditions.DURATION_ROUNDS, {"rounds": 10}))
			var resist: Array[String] = CharacterSheet.DAMAGE_TYPES.duplicate()
			resist.erase("force")
			_apply_buff(actor, "empty_body", actor.id, Conditions.duration(Conditions.DURATION_ROUNDS, {"rounds": 10}), {"resist": resist})
		"draconic_presence":
			var condition := Conditions.CHARMED if str(intent.get("mode", "fear")) == "awe" else Conditions.FRIGHTENED
			for h in hostiles_of(actor):
				if not h.is_conscious() or h.untargetable or GridMath.distance_tiles(actor.position, h.position) > DRACONIC_PRESENCE_RANGE_TILES:
					continue
				if not _saving_throw(actor.id, h, Ability.Type.WIS, actor.sheet.spell_save_dc(), {"vs_condition": condition}):
					_apply_condition(h, condition, actor.id, Conditions.duration(Conditions.DURATION_ROUNDS, {"rounds": 10}))


# --- round C: terrain, walls and wards ------------------------------------------------

## After a tile effect was created, moved or ended: terrain (walls, passages,
## opaque tiles) is recomputed when it changes the map, Antimagic Fields are
## re-applied and barriers (Antilife Shell) push out the creatures they bar.
func _after_zone_change(fx: Dictionary, cells: Array[Vector2i]) -> void:
	if not str(fx.get("terrain", "")).is_empty() or fx.get("opaque", false) == true:
		_refresh_terrain(cells)
	_refresh_antimagic()
	_repel_barriers()


## Recomputes walk_map on the tiles of terrain effects (and `extra`): the base
## map, then each effect in creation order ("solid" walls, "open" passages
## inside the region, "opaque" tiles). Emits terrain_changed {walls, floors}
## (tiles that became walls / floor); creatures left on a wall tile are pushed
## to the nearest free tile (pushed).
func _refresh_terrain(extra: Array[Vector2i]) -> void:
	var touched := {}
	for p in extra:
		touched[p] = true
	for fx in tile_effects:
		if not str(fx.get("terrain", "")).is_empty() or fx.get("opaque", false) == true:
			for p in _effect_cells(fx):
				touched[p] = true
	var before := {}
	for key: Variant in touched.keys():
		var p: Vector2i = key
		if not walk_map.in_bounds(p):
			continue
		before[p] = walk_map.is_walkable(p)
		walk_map.set_walkable(p, _base_map.is_walkable(p))
		walk_map.set_opaque(p, _base_map.is_opaque(p))
	for fx in tile_effects:
		var terrain := str(fx.get("terrain", ""))
		for p in _effect_cells(fx):
			if not walk_map.in_bounds(p):
				continue
			if terrain == "solid":
				walk_map.set_walkable(p, false)
			elif terrain == "open" and region.has_point(p):
				walk_map.set_walkable(p, true)
			if fx.get("opaque", false) == true:
				walk_map.set_opaque(p, true)
	var walls: Array = []
	var floors: Array = []
	for key: Variant in before.keys():
		var p: Vector2i = key
		if before[p] != walk_map.is_walkable(p):
			(floors if walk_map.is_walkable(p) else walls).append(GridMath.vec_to_arr(p))
	if not walls.is_empty() or not floors.is_empty():
		_emit("terrain_changed", {"walls": walls, "floors": floors})
	for c in tracker.order():
		if c.is_alive() and not c.untargetable and not walk_map.is_walkable(c.position):
			_expel(c, {}, "")


## Moves c to the nearest free walkable tile (not in `avoid`): pushed {target,
## source, from, to}.
func _expel(c: Combatant, avoid: Dictionary, source_id: String) -> void:
	var occupied := occupied_cells(c.id)
	for r in range(1, 16):
		for y in range(c.position.y - r, c.position.y + r + 1):
			for x in range(c.position.x - r, c.position.x + r + 1):
				var t := Vector2i(x, y)
				if GridMath.distance_tiles(t, c.position) != r or avoid.has(t) or occupied.has(t):
					continue
				if region.has_point(t) and walk_map.is_walkable(t):
					var from := c.position
					c.position = t
					_emit("pushed", {"target": c.id, "source": source_id, "from": GridMath.vec_to_arr(from), "to": GridMath.vec_to_arr(t)})
					_after_position_change(c, from, false)
					return


## A barrier (Antilife Shell) keeps out c: c is alive, targetable, hostile to
## the caster and neither undead nor a construct.
func _barrier_affects(fx: Dictionary, c: Combatant) -> bool:
	if str(fx.get("barrier", "")).is_empty() or not c.is_alive() or c.untargetable:
		return false
	return c.team != DictUtil.to_int(fx.get("team", -1), -1) and not c.creature_type in ["undead", "construct"]


## The barrier covering `tile` that keeps `actor` out ({} = none).
func _barrier_at(actor: Combatant, tile: Vector2i) -> Dictionary:
	for fx in tile_effects:
		if _effect_covers(fx, tile) and _barrier_affects(fx, actor):
			return fx
	return {}


## Pushes creatures a barrier keeps out to the nearest tile outside it.
func _repel_barriers() -> void:
	for fx: Dictionary in tile_effects.duplicate():
		if str(fx.get("barrier", "")).is_empty() or not tile_effects.has(fx):
			continue
		var avoid := {}
		for p in _effect_cells(fx):
			avoid[p] = true
		for c in tracker.order():
			if _barrier_affects(fx, c) and _effect_covers(fx, c.position):
				_expel(c, avoid, str(fx["source"]))


## Wind Wall: a ranged weapon attack whose line crosses a wind tile is lost
## (attack_lost {attacker, target, reason: "wind_wall"}).
func _wind_blocks(attacker: Combatant, target: Combatant) -> bool:
	for fx in tile_effects:
		if fx.get("wind", false) != true:
			continue
		for cell in WalkMap.line_cells(attacker.position, target.position):
			if cell != attacker.position and _effect_covers(fx, cell):
				_emit("attack_lost", {"attacker": attacker.id, "target": target.id, "reason": "wind_wall"})
				return true
	return false


## Marks every combatant standing in an Antimagic Field.
func _refresh_antimagic() -> void:
	for value: Variant in _combatants.values():
		var c: Combatant = value
		var inside := false
		for fx in tile_effects:
			if fx.get("antimagic", false) == true and _effect_covers(fx, c.position):
				inside = true
				break
		c.antimagic = inside


## Globe of Invulnerability: target stands in a globe that `source` is
## outside of, and a spell of `level` is within the globe's limit.
func _warded_by_globe(source: Combatant, target: Combatant, level: int) -> bool:
	for fx in tile_effects:
		var limit := DictUtil.to_int(fx.get("globe", -1), -1)
		if limit < 0 or level > limit:
			continue
		if _effect_covers(fx, target.position) and not _effect_covers(fx, source.position):
			return true
	return false


## Why a spell of `caster` cannot affect target ("" = it can): a Resilient
## Sphere around it, an Antimagic Field, a Globe of Invulnerability.
func _spell_warded(caster: Combatant, target: Combatant, spell: SpellDefinition) -> String:
	if target != caster and target.is_sealed():
		return "resilient_sphere"
	if target.antimagic:
		return "antimagic_field"
	if target != caster and _warded_by_globe(caster, target, spell.level):
		return "globe_of_invulnerability"
	return ""


## Attacks into or out of a Resilient Sphere ("" = allowed).
func _sealed_error(actor: Combatant, target: Combatant) -> String:
	if actor.is_sealed() and actor != target:
		return "%s is sealed inside a sphere of force" % actor.display_name
	if target.is_sealed() and actor != target:
		return "%s is sealed inside a sphere of force" % target.display_name
	return ""


## One phase of a phased effect (Storm of Vengeance): "set" changes the
## effect's own fields (difficult, wind, obscured), then every creature it
## affects (or, with "max_targets", that many hostiles of the caster nearest
## its centre, ties by id) is hit by the phase (tile_effect_triggered
## trigger "phase").
func _run_phase(fx: Dictionary, index: int) -> void:
	var phases: Array[Dictionary] = fx["phases"]
	if index < 0 or index >= phases.size():
		return
	var phase := phases[index]
	var set_v: Variant = phase.get("set", {})
	if typeof(set_v) == TYPE_DICTIONARY:
		var set_d: Dictionary = set_v
		for key: Variant in set_d.keys():
			fx[str(key)] = set_d[key]
	var victims: Array[Combatant] = []
	for c in tracker.order():
		if _effect_covers(fx, c.position) and _effect_affects(fx, c):
			victims.append(c)
	var limit := DictUtil.to_int(phase.get("max_targets", 0), 0)
	if limit > 0:
		var centre := Encounter._effect_centre(fx)
		var team := DictUtil.to_int(fx.get("team", -1), -1)
		var hostile: Array[Combatant] = []
		for c in victims:
			if c.team != team:
				hostile.append(c)
		hostile.sort_custom(func(a: Combatant, b: Combatant) -> bool:
			var da := GridMath.distance_tiles(a.position, centre)
			var db := GridMath.distance_tiles(b.position, centre)
			if da != db:
				return da < db
			return a.id < b.id)
		victims = hostile.slice(0, limit)
	for c in victims:
		if not tile_effects.has(fx) or state != State.ACTIVE:
			return
		if not c.is_alive():
			continue
		_emit("tile_effect_triggered", {"id": fx["id"], "target": c.id, "trigger": "phase"})
		_zone_hit(fx, phase, c)


## Falling damage (Reverse Gravity): a falling creature may be saved by an
## ally's (or its own) Feather Fall (reaction, trigger falling: no damage) or
## reduce it with Slow Fall (monk: 5 x level). Emits damage {.., fall: true}.
func _fall(c: Combatant, dice: String, source_id: String, spell_id: String) -> void:
	var rolled := maxi(0, DictUtil.to_int(DiceFormula.parse(dice).roll(rng)["total"]))
	var saver: Combatant = null
	for ally in tracker.order():
		if ally.team != c.team or GridMath.distance_tiles(ally.position, c.position) > 12:
			continue
		if _may_react(ally, "falling", "feather_fall") and _reaction_slot(ally, "feather_fall", 1) > 0:
			saver = ally
			break
	if saver != null:
		var slot := _reaction_slot(saver, "feather_fall", 1)
		saver.sheet.use_spell_slot(slot)
		_use_reaction(saver, "feather_fall", "falling", {"target": c.id, "spell": "feather_fall", "slot_level": slot})
		rolled = 0
	elif c.sheet.has_feature("slow_fall") and _may_react(c, "falling", "slow_fall"):
		var reduced := mini(rolled, 5 * c.sheet.level)
		_use_reaction(c, "slow_fall", "falling", {"amount": reduced})
		rolled -= reduced
	var amount := c.adjust_damage(rolled, "bludgeoning", false)
	_deal_effect_damage(get_combatant(source_id), c, amount, "bludgeoning", {"spell": spell_id, "fall": true})


## Prismatic Wall layers / Prismatic Spray rays (1 red fire, 2 orange acid,
## 3 yellow lightning, 4 green poison, 5 blue cold: 10d6, half on a DEX save;
## 6 indigo: restrained; 7 violet: blinded). `saved` -1 rolls the layer's own
## DEX save, 0 / 1 uses a save already made (Prismatic Spray).
func _prismatic_layer(source_id: String, c: Combatant, layer: String, dc: int, spell_id: String, saved: int = -1) -> void:
	var damage_types := {"red": "fire", "orange": "acid", "yellow": "lightning", "green": "poison", "blue": "cold"}
	var success := saved == 1
	if saved < 0:
		success = _saving_throw(source_id, c, Ability.Type.DEX, dc)
	if damage_types.has(layer):
		var dtype := str(damage_types[layer])
		var rolled := maxi(0, DiceExpr.parse("10d6").roll(rng).total)
		var amount := c.adjust_damage(_save_damage(c, Ability.Type.DEX, rolled, success, true), dtype, true)
		_deal_effect_damage(get_combatant(source_id), c, amount, dtype, {"spell": spell_id, "layer": layer})
		return
	if success or not c.is_alive():
		return
	match layer:
		"indigo":
			_apply_condition(c, Conditions.RESTRAINED, source_id, Conditions.duration(Conditions.DURATION_SAVE_TRACK, {"ability": "CON", "dc": dc}),
					{"layer": layer, "cast_spell": spell_id, "track_effect": {"effect": "prismatic_indigo", "ends_condition": true, "conditions": [Conditions.PETRIFIED]}})
		"violet":
			_apply_condition(c, Conditions.BLINDED, source_id, Conditions.duration(Conditions.DURATION_SAVE_ENDS, {"ability": "WIS", "dc": dc}), {"layer": layer})


## Telekinesis: "point" (required) is free open ground within the effect's
## move_ft of the target and within the spell's range of the caster; the
## target is Huge or smaller.
func _check_forced_move(actor: Combatant, spell: SpellDefinition, target: Combatant, intent: Dictionary) -> String:
	if target == actor:
		return "%s cannot move its caster" % spell.display_name
	if not GridMath.is_vec_arr(intent.get("point", null)):
		return "%s needs a point [x, y]" % spell.display_name
	var p := GridMath.arr_to_vec(intent["point"])
	var tiles := GridMath.feet_to_tiles(DictUtil.to_int(spell.raw_effect.get("move_ft", 30), 30))
	if not region.has_point(p) or not walk_map.is_walkable(p) or occupied_cells(target.id).has(p):
		return "the point is not free open ground"
	if GridMath.distance_tiles(target.position, p) > tiles:
		return "%s moves a creature at most %d tiles" % [spell.display_name, tiles]
	if GridMath.distance_tiles(actor.position, p) > maxi(1, _spell_range(spell)):
		return "the point is out of range"
	if target.sheet.size_index() > 4:
		return "%s is too large" % target.display_name
	return ""


## Telekinesis: a hostile contests the caster's spellcasting ability check
## with Strength (contest reason "telekinesis"); on a win (or for an ally) it
## is moved to the point (pushed {.., spell}) and a hostile is restrained
## until the end of the caster's next turn.
func _forced_move(actor: Combatant, target: Combatant, spell: SpellDefinition, intent: Dictionary) -> void:
	var hostile := target.team != actor.team
	if hostile and not contest(actor, maxi(0, actor.sheet.casting_ability), -1, target, [[Ability.Type.STR, -1]], "telekinesis"):
		return
	var from := target.position
	var dest := GridMath.arr_to_vec(intent["point"])
	target.position = dest
	_emit("pushed", {"target": target.id, "source": actor.id, "from": GridMath.vec_to_arr(from), "to": GridMath.vec_to_arr(dest), "spell": spell.id})
	_after_position_change(target, from, false)
	if hostile and target.is_alive() and not spell.condition.is_empty():
		var extra := {"spell": spell.id} if spell.concentration else {}
		_apply_condition(target, spell.condition, actor.id, Conditions.duration(Conditions.DURATION_SOURCE_NEXT_TURN), extra)


# --- round C: control, charm effects, absence and banishment ----------------------------

## control {target, orders}: the actor dominates target; orders (intent
## dictionaries without "v" / "actor", at most 12) run on its next turn
## instead of MonsterBrain. Free; replaces earlier orders.
func _check_control(actor: Combatant, intent: Dictionary) -> String:
	var target := get_combatant(str(intent.get("target", "")))
	if target == null or target.controlled_by != actor.id:
		return "%s does not control that creature" % actor.display_name
	var orders_v: Variant = intent.get("orders", null)
	if typeof(orders_v) != TYPE_ARRAY:
		return "control needs orders: an array of intents"
	var orders: Array = orders_v
	if orders.size() > 12:
		return "at most 12 orders"
	for o: Variant in orders:
		if typeof(o) != TYPE_DICTIONARY or str((o as Dictionary).get("type", "")) in ["", CONTROL]:
			return "every order is an intent with a type (not control)"
	return ""


func _do_control(actor: Combatant, intent: Dictionary) -> void:
	var target := get_combatant(str(intent["target"]))
	target.orders = DictUtil.to_dict_array(intent["orders"])
	_emit("control", {"actor": actor.id, "target": target.id, "orders": target.orders.size()})


## Hooks when a condition entry is added: dominated switches the creature to
## the source's team (team_changed {target, team, controlled_by}); suggested
## remembers the source's team; ethereal takes it out of reach.
func _on_condition_added(target: Combatant, entry: Dictionary) -> void:
	match str(entry.get("condition", "")):
		Conditions.DOMINATED:
			var src := get_combatant(str(entry.get("source", "")))
			if src == null:
				return
			if target.controlled_by.is_empty():
				target.original_team = target.team
				target.was_auto_controlled = target.auto_controlled
			target.controlled_by = src.id
			target.team = src.team
			target.auto_controlled = true
			target.orders.clear()
			_emit("team_changed", {"target": target.id, "team": target.team, "controlled_by": src.id})
		Conditions.SUGGESTED:
			var src := get_combatant(str(entry.get("source", "")))
			if src != null:
				entry["source_team"] = src.team
		Conditions.ETHEREAL:
			_set_absent(target, "ethereal", true)


## Hooks when a condition entry goes: the last dominated entry gives the
## creature back to its team; the last ethereal entry brings it back.
func _on_condition_removed(target: Combatant, entry: Dictionary) -> void:
	var condition := str(entry.get("condition", ""))
	if condition == Conditions.DOMINATED and not target._has_own_condition(Conditions.DOMINATED) and not target.controlled_by.is_empty():
		target.team = target.original_team
		target.controlled_by = ""
		target.auto_controlled = target.was_auto_controlled
		target.orders.clear()
		_emit("team_changed", {"target": target.id, "team": target.team, "controlled_by": ""})
	elif condition == Conditions.ETHEREAL and not target._has_own_condition(Conditions.ETHEREAL):
		_set_absent(target, "ethereal", false)


## Marks c absent for `reason` (or back): absent creatures are untargetable
## and occupy no tile; one coming back onto an occupied tile is pushed aside.
func _set_absent(c: Combatant, reason: String, on: bool) -> void:
	if on:
		if c.absent.is_empty():
			c.absent_saved_untargetable = c.untargetable
		if not c.absent.has(reason):
			c.absent.append(reason)
		c.untargetable = true
		return
	if not c.absent.has(reason):
		return
	c.absent.erase(reason)
	if not c.absent.is_empty():
		return
	c.untargetable = c.absent_saved_untargetable
	if occupied_cells(c.id).has(c.position) or not walk_map.is_walkable(c.position):
		_expel(c, {}, "")


## Suggestion / Calm Emotions: no hostile action against the source's side.
func _pacified_error(actor: Combatant, target: Combatant) -> String:
	if actor.suggested_teams().has(target.team):
		return "%s will not act against %s (suggestion)" % [actor.display_name, target.display_name]
	return ""


## Compulsion: a compelled creature first moves as far as it can toward the
## entry's "toward" point (compelled {actor, toward}, then moved events).
func _compelled_move(c: Combatant) -> void:
	if not c.is_conscious() or c.movement_remaining <= 0:
		return
	for entry: Dictionary in c.conditions.duplicate():
		if str(entry.get("condition", "")) != Conditions.COMPELLED or not GridMath.is_vec_arr(entry.get("toward", null)):
			continue
		var toward := GridMath.arr_to_vec(entry["toward"])
		var path := walk_map.path_to(c.position, toward, occupied_cells(c.id))
		var steps: Array[Vector2i] = []
		var budget := c.movement_remaining
		for p in path:
			var cost := _step_cost(c, p, "walk")
			if cost > budget:
				break
			budget -= cost
			steps.append(p)
		_emit("compelled", {"actor": c.id, "toward": GridMath.vec_to_arr(toward)})
		if not steps.is_empty():
			_do_move(c, steps)
		return


## Compulsion's bonus action: compelled creatures of the actor's casting now
## head for the new point (redirected {actor, spell, point}).
func _redirect(actor: Combatant, spell: SpellDefinition, intent: Dictionary) -> void:
	var point: Array = intent["point"] if GridMath.is_vec_arr(intent.get("point", null)) else GridMath.vec_to_arr(actor.position)
	for c in tracker.order():
		for entry in c.conditions:
			if str(entry.get("condition", "")) == Conditions.COMPELLED and str(entry.get("source", "")) == actor.id:
				entry["toward"] = point.duplicate()
	_emit("redirected", {"actor": actor.id, "spell": spell.id, "point": point.duplicate()})


## Prismatic violet: a creature blinded by it saves (WIS) at the start of the
## source's next turn; success ends the blindness, failure sends it to
## another plane (banished: for good, or 10 rounds for player characters).
func _violet_saves(source: Combatant) -> void:
	for other in tracker.order():
		for entry: Dictionary in other.conditions.duplicate():
			if str(entry.get("layer", "")) != "violet" or str(entry.get("source", "")) != source.id or not other.conditions.has(entry):
				continue
			var dc := DictUtil.to_int((entry.get("duration", {}) as Dictionary).get("dc", 10), 10)
			_remove_condition(other, entry)
			if not _saving_throw(source.id, other, Ability.Type.WIS, dc) and other.is_alive():
				_banish(other, source.id, "prismatic", 10, true, {})


## Banishment-type spells (see SpellDefinition.EFFECT_BANISH): the caster
## itself or an ally leaves for "self_rounds"; a hostile is first hit by a
## melee spell attack ("attack": "melee", Plane Shift), then saves ("save").
func _banish_spell(actor: Combatant, target: Combatant, spell: SpellDefinition, _slot: int) -> void:
	var e := spell.raw_effect
	var rounds := DictUtil.to_int(e.get("rounds", 10), 10)
	if rounds > 0 and _cast_meta.has("extended_spell"):
		rounds *= 2
	if target.team == actor.team:
		_banish(target, actor.id, spell.id, DictUtil.to_int(e.get("self_rounds", rounds), rounds), false, {})
		return
	if str(e.get("attack", "")) == "melee":
		var attack := {"name": spell.display_name, "kind": "spell", "melee": true, "to_hit": actor.sheet.spell_attack_bonus(),
				"damage": "0", "damage_type": "force", "range_tiles": [1, 1]}
		var r := _roll_attack(actor, target, attack, false, spell)
		if not r.hit or not target.is_alive():
			return
	var save := Ability.from_string(str(e.get("save", "")))
	if save >= 0 and _saving_throw(actor.id, target, save, actor.sheet.spell_save_dc(), _save_opts(spell, target)):
		return
	var extra := {}
	if e.get("native_permanent", false) == true:
		extra["native_permanent"] = true
	if typeof(e.get("escape", null)) == TYPE_DICTIONARY:
		extra["escape"] = e["escape"]
	_banish(target, actor.id, spell.id, rounds, e.get("permanent", false) == true, extra)


## Sends c away: banished {target, source, spell, rounds, permanent}. It is
## out of reach, its turns pass, its concentration ends; a permanent
## banishment takes it out of the fight (player characters: 10 rounds
## instead). rounds -1 = until the source's concentration ends.
func _banish(c: Combatant, source_id: String, spell_id: String, rounds: int, permanent: bool, extra: Dictionary) -> void:
	if not c.is_alive():
		return
	if permanent and not c.is_monster():
		permanent = false
		rounds = maxi(rounds, 10)
	c.banished = {"source": source_id, "spell": spell_id, "turns_left": rounds, "permanent": permanent, "position": GridMath.vec_to_arr(c.position)}
	c.banished.merge(extra, true)
	_set_absent(c, "banished", true)
	_reveal(c, "dropped")
	_end_concentration(c, "incapacitated")
	_emit("banished", {"target": c.id, "source": source_id, "spell": spell_id, "rounds": rounds, "permanent": permanent})


## Brings a banished creature back to its tile (or the nearest free one):
## returned {target, position, reason}; Hurl Through Hell's damage follows.
func _return(c: Combatant, reason: String) -> void:
	if c.banished.is_empty():
		return
	var damage_v: Variant = c.banished.get("return_damage", null)
	var source := get_combatant(str(c.banished.get("source", "")))
	c.position = GridMath.arr_to_vec(c.banished.get("position", GridMath.vec_to_arr(c.position)))
	c.banished = {}
	for why: String in ["banished", "possessed"]:
		_set_absent(c, why, false)
	_emit("returned", {"target": c.id, "position": GridMath.vec_to_arr(c.position), "reason": reason})
	_after_position_change(c, c.position, false)
	if typeof(damage_v) == TYPE_DICTIONARY and c.is_alive():
		var dmg: Dictionary = damage_v
		if not DictUtil.to_string_array(dmg.get("immune_types", [])).has(c.creature_type):
			var dtype := str(dmg.get("type", "psychic"))
			var amount := c.adjust_damage(maxi(0, DiceExpr.parse(str(dmg.get("dice", "10d10"))).roll(rng).total), dtype, true)
			_deal_effect_damage(source, c, amount, dtype, {"feature": str(dmg.get("feature", ""))})


## End of c's turn: its own banishment counts down (Maze: an INT check DC 20
## escapes; Banishment holding an otherworldly creature the full duration
## sends it home for good), and banishments that last until c's turn ends
## (Hurl Through Hell) end.
func _banish_turn_end(c: Combatant) -> void:
	for other in tracker.order():
		if other.banished.is_empty() or str(other.banished.get("source", "")) != c.id or not other.banished.has("source_turns"):
			continue
		other.banished["source_turns"] = DictUtil.to_int(other.banished["source_turns"]) - 1
		if DictUtil.to_int(other.banished["source_turns"]) <= 0:
			_return(other, "expired")
	if c.banished.is_empty() or c.banished.get("permanent", false) == true or c.banished.has("source_turns"):
		return
	var escape_v: Variant = c.banished.get("escape", null)
	if typeof(escape_v) == TYPE_DICTIONARY:
		var esc: Dictionary = escape_v
		var res := ability_check(c, Ability.from_string(str(esc.get("ability", "INT"))), -1, DictUtil.to_int(esc.get("dc", 20), 20), "maze")
		if res["success"] == true:
			_return(c, "escaped")
			return
	var left := DictUtil.to_int(c.banished.get("turns_left", -1), -1)
	if left < 0:
		return
	left -= 1
	c.banished["turns_left"] = left
	if left > 0:
		return
	if c.banished.get("native_permanent", false) == true and OTHERWORLDLY_TYPES.has(c.creature_type):
		c.banished["permanent"] = true
		_emit("banished", {"target": c.id, "source": str(c.banished.get("source", "")), "spell": str(c.banished.get("spell", "")), "rounds": -1, "permanent": true})
		check_end()
		return
	_return(c, "expired")


## Blink: at the end of its turns the creature rolls a d20; on 11+ it
## vanishes to the Ethereal Plane until its next turn starts (blink {actor,
## roll, vanished}).
func _blink(c: Combatant) -> void:
	if not c.is_conscious() or not c.buff_flag("blink"):
		return
	var roll := rng.next_int(1, 20)
	var vanished := roll >= 11
	_emit("blink", {"actor": c.id, "roll": roll, "vanished": vanished})
	if vanished:
		_apply_condition(c, Conditions.ETHEREAL, c.id, Conditions.duration(Conditions.DURATION_TARGET_TURN_START))


# --- round C: lingering out-of-combat effects --------------------------------------------

## Effects cast before the fight (CharacterSheet.lingering) take hold when it
## starts: buffs on their owner ("buff", "stealth"), light around it
## ("light": a lit tile effect of radius_ft anchored to it), zones centred on it
## ("zone": the spell's zone, mode / creature_type from the entry). Features
## ("feature": Magic Jar) are checked when used.
func _apply_lingering(c: Combatant) -> void:
	for entry in c.sheet.lingering:
		var spell_id := str(entry.get("spell", ""))
		match str(entry.get("kind", "")):
			"buff", "stealth":
				var mods_v: Variant = entry.get("modifiers", {})
				var mods: Dictionary = mods_v if typeof(mods_v) == TYPE_DICTIONARY else {}
				_apply_buff(c, str(entry.get("effect", spell_id)), c.id, Conditions.duration(Conditions.DURATION_ENCOUNTER), mods, spell_id)
				var cond := str(entry.get("condition", ""))
				if not cond.is_empty():
					_apply_condition(c, cond, c.id, Conditions.duration(Conditions.DURATION_ENCOUNTER), {})
			"light":
				var radius := GridMath.feet_to_tiles(DictUtil.to_int(entry.get("radius_ft", 20), 20))
				_create_zone(c, spell_id, {"lit": true, "rounds": -1}, DictUtil.to_int(entry.get("slot_level", 0), 0),
						AreaOfEffect.tiles("sphere", radius, c.position, c.position, walk_map), c.id, radius, false, "", "", 0, c.position)
			"zone":
				var spell := _spell_def(spell_id)
				if spell == null:
					continue
				var z := spell.zone.duplicate(true)
				var modes_v: Variant = z.get("modes", {})
				var mode := str(entry.get("mode", ""))
				if typeof(modes_v) == TYPE_DICTIONARY and (modes_v as Dictionary).has(mode):
					z.merge((modes_v as Dictionary)[mode], true)
				if entry.has("creature_type"):
					z["creature_types"] = [str(entry["creature_type"])]
				var slot := DictUtil.to_int(entry.get("slot_level", spell.level), spell.level)
				var cells := AreaOfEffect.tiles("sphere", spell.area_size_tiles(), c.position, c.position, walk_map)
				_create_zone(c, spell_id, z, slot, cells, "", spell.area_size_tiles(), false, Encounter._zone_damage(spell, z, slot),
						str(z.get("damage_type", spell.damage_type)), spell.level, c.position)


## Whether c carries a lingering feature (Magic Jar's container).
func _lingering_feature(c: Combatant, feature: String) -> bool:
	for entry in c.sheet.lingering:
		if str(entry.get("kind", "")) == "feature" and str(entry.get("feature", "")) == feature:
			return true
	return false


## Encounter end: lingering effects with a count lose one encounter; those
## used up leave the sheet (lingering_ended {target, spell}).
func _settle_lingering() -> void:
	for value: Variant in _combatants.values():
		var c: Combatant = value
		if c.is_summon() or c.sheet.lingering.is_empty():
			continue
		var kept: Array[Dictionary] = []
		for entry in c.sheet.lingering:
			var left := DictUtil.to_int(entry.get("encounters_left", -1), -1)
			if left > 0:
				left -= 1
				entry["encounters_left"] = left
				if left == 0:
					_emit("lingering_ended", {"target": c.id, "spell": str(entry.get("spell", ""))})
					continue
			kept.append(entry)
		c.sheet.lingering = kept


# --- round C class features and spell actions (use_feature) ------------------------------

## Validation of the round C use_feature ids; "-" when `feature` is not one.
func _check_feature_c(actor: Combatant, feature: String, intent: Dictionary) -> String:
	match feature:
		"magic_jar":
			var target := _cast_target(actor, intent)
			if target == null or target == actor or target.team == actor.team or not target.is_conscious() or target.untargetable:
				return "Magic Jar needs a hostile creature"
			if not target.is_monster() or target.creature_type != "humanoid":
				return "Magic Jar can only possess a humanoid"
			if GridMath.distance_tiles(actor.position, target.position) > 20:
				return "%s is more than 100 feet away" % target.display_name
			if not actor.form.is_empty():
				return "%s is not in its own body" % actor.display_name
			return ""
		"end_spell":
			var sid := str(intent.get("mode", ""))
			if _own_spell_effects(actor, sid).is_empty() and str(actor.concentration.get("spell", "")) != sid:
				return "%s has no %s to end" % [actor.display_name, sid]
			return ""
		"one_with_shadows":
			if light == LIGHT_BRIGHT and not _tile_dark_magic(actor.position) and not _tile_obscured(actor.position):
				return "One with Shadows needs dim light or darkness"
			return ""
		"quivering_palm":
			var target := get_combatant(actor.quivering_target)
			if target == null or not target.is_alive() or not target.absent.is_empty():
				return "%s has set no Quivering Palm vibrations in a creature here" % actor.display_name
			return ""
		"holy_nimbus":
			return ""
		"gaze_of_two_minds":
			var target := _cast_target(actor, intent)
			if target == null or target == actor or target.team != actor.team or not target.is_conscious():
				return "Gaze of Two Minds needs a willing ally"
			if target.creature_type != "humanoid" and target.is_monster():
				return "Gaze of Two Minds needs a humanoid"
			if not GridMath.is_adjacent(actor.position, target.position):
				return "%s is out of reach" % target.display_name
			return ""
	return "-"


## The actor's own buffs / conditions of spell_id on itself.
func _own_spell_effects(actor: Combatant, spell_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if spell_id.is_empty():
		return out
	for b in actor.buffs:
		if str(b.get("spell", "")) == spell_id and str(b.get("source", "")) == actor.id:
			out.append(b)
	for entry in actor.conditions:
		if str(entry.get("spell", entry.get("cast_spell", ""))) == spell_id and str(entry.get("source", "")) == actor.id:
			out.append(entry)
	return out


## One with Shadows: invisible until it moves, acts or reacts (condition flag
## "ends_on_act"). Gaze of Two Minds: blinded and deafened until the end of
## its next turn, seeing through the touched ally's senses (can_see uses the
## ally's; condition field "gaze").
## Quivering Palm (open hand 17): the vibrating creature makes a CON save
## (ki DC): it drops to 0 hit points on a failure (damage {.., type:
## "necrotic", feature: "quivering_palm"}), else takes 10d10 necrotic. Holy
## Nimbus (devotion 20): for 10 rounds a 30-ft sunlit aura (a "lit" tile
## effect anchored to the paladin) deals 10 radiant to each hostile starting
## its turn in it, and the paladin has advantage on saves against fiends and
## undead (buff holy_nimbus).
func _do_feature_c(actor: Combatant, feature: String, intent: Dictionary) -> void:
	match feature:
		"quivering_palm":
			var target := get_combatant(actor.quivering_target)
			actor.quivering_target = ""
			if _saving_throw(actor.id, target, Ability.Type.CON, Encounter.ki_save_dc(actor.sheet)):
				var amount := target.adjust_damage(DiceExpr.parse("10d10").roll(rng).total, "necrotic", true)
				_deal_effect_damage(actor, target, amount, "necrotic", {"feature": "quivering_palm"})
			else:
				_deal_effect_damage(actor, target, target.sheet.current_hp + target.sheet.temp_hp, "necrotic", {"feature": "quivering_palm"})
		"holy_nimbus":
			var radius := HOLY_NIMBUS_TILES
			var cells := AreaOfEffect.tiles("sphere", radius, actor.position, actor.position, walk_map)
			_create_zone(actor, "holy_nimbus", {"lit": true, "rounds": HOLY_NIMBUS_ROUNDS, "triggers": ["start_turn"], "affects": "hostiles", "damage": "10", "damage_type": "radiant"},
					0, cells, actor.id, radius, false, "10", "radiant", 0, actor.position)
			_apply_buff(actor, "holy_nimbus", actor.id, Conditions.duration(Conditions.DURATION_ROUNDS, {"rounds": HOLY_NIMBUS_ROUNDS}), {"adv_saves_vs_types": ["fiend", "undead"]})
		"one_with_shadows":
			_apply_condition(actor, Conditions.INVISIBLE, actor.id, Conditions.duration(Conditions.DURATION_ENCOUNTER), {"ends_on_act": true, "feature": feature})
		"gaze_of_two_minds":
			var ally := _cast_target(actor, intent)
			for cond: String in [Conditions.BLINDED, Conditions.DEAFENED]:
				_apply_condition(actor, cond, actor.id, Conditions.duration(Conditions.DURATION_ROUNDS, {"rounds": 2}), {"gaze": ally.id, "feature": feature})
		"magic_jar":
			var target := _cast_target(actor, intent)
			if _saving_throw(actor.id, target, Ability.Type.CHA, actor.sheet.spell_save_dc()):
				return
			var monsters: Dictionary = _content().get("monsters", {})
			if not monsters.has(target.monster_id):
				return
			var def: MonsterDefinition = monsters[target.monster_id]
			var host_hp := target.sheet.current_hp
			var host_pos := target.position
			target.banished = {"source": actor.id, "spell": "magic_jar", "turns_left": -1, "permanent": false, "position": GridMath.vec_to_arr(host_pos), "possessed": true}
			_set_absent(target, "possessed", true)
			_emit("possessed", {"actor": actor.id, "target": target.id})
			var from := actor.position
			actor.position = host_pos
			_emit("teleported", {"actor": actor.id, "from": GridMath.vec_to_arr(from), "to": GridMath.vec_to_arr(host_pos), "spell": "magic_jar"})
			_transform(actor, def, "magic_jar", actor.id)
			actor.sheet.current_hp = clampi(host_hp, 1, actor.sheet.max_hp)
			actor.form["host"] = target.id
			_after_position_change(actor, from, false)
		"end_spell":
			var sid := str(intent.get("mode", ""))
			for entry in _own_spell_effects(actor, sid):
				if actor.buffs.has(entry):
					_remove_buff(actor, entry)
				else:
					_remove_condition(actor, entry)
			if str(actor.concentration.get("spell", "")) == sid:
				_end_concentration(actor, "dismissed")


## Magic Jar ends: a host body that dropped to 0 dies; otherwise the host's
## soul returns (with the body's hit points) next to the caster.
func _release_host(c: Combatant, host_id: String, reason: String, form_hp: int) -> void:
	var host := get_combatant(host_id)
	if host == null or str(host.banished.get("spell", "")) != "magic_jar":
		return
	if reason == "dropped":
		host.banished = {}
		host.absent.erase("possessed")
		host.sheet.kill()
		_emit("destroyed", {"source": c.id, "target": host.id, "feature": "magic_jar"})
		return
	host.sheet.current_hp = clampi(form_hp, 1, host.sheet.max_hp)
	_return(host, "released")


# --- round C: illusions -------------------------------------------------------------------

## An illusion spell's image: a creature-like decoy on the caster's team that
## looks like "form" (a monster id; Project Image / Mislead: the caster),
## takes no damage and does nothing. Mislead ("self_invisible") also makes the
## caster invisible until it attacks or casts.
func _cast_illusion(actor: Combatant, spell: SpellDefinition, near: Vector2i, limit: int, extra: Dictionary, intent: Dictionary) -> void:
	var s := CharacterSheet.new()
	var e := spell.raw_effect
	var monsters: Dictionary = _content().get("monsters", {})
	var form := str(intent.get("form", e.get("monster", "")))
	s.name = "Illusory Figure"
	s.max_hp = 1
	if e.get("copy_caster", false) == true:
		s.name = actor.display_name
		s.max_hp = actor.sheet.max_hp
		s.size = actor.sheet.size
	elif monsters.has(form):
		var def: MonsterDefinition = monsters[form]
		s.name = def.display_name
		s.max_hp = def.hit_points_avg
		s.size = def.size
	s.class_id = "monster:illusion"
	s.current_hp = s.max_hp
	s.speed = 30
	s.uses_death_saves = false
	s.armor_base = 10
	s.damage_immunities = CharacterSheet.DAMAGE_TYPES.duplicate()
	s.condition_immunities = Conditions.ALL.duplicate()
	extra["illusion"] = {"spell": spell.id, "dc": actor.sheet.spell_save_dc(), "source": actor.id}
	var at := near
	if e.get("copy_caster", false) == true and near == actor.position:
		at = actor.position + Vector2i(1, 0)
	_summon(actor, spell.id, null, at, limit, extra, {"sheet": s, "attacks": [], "monster_id": "illusion"})
	if e.get("self_invisible", false) == true:
		var cond_extra := {"ends_on_attack": true, "cast_spell": spell.id}
		if spell.concentration:
			cond_extra["spell"] = spell.id
		_apply_condition(actor, Conditions.INVISIBLE, actor.id, Conditions.duration(Conditions.DURATION_ENCOUNTER), cond_extra)


## A hostile interacts with an illusion (attacks it, targets it): Witch Sight
## within 30 ft sees through it; otherwise an Intelligence (Investigation)
## check against the caster's DC (check reason "illusion"). Disbelieved:
## disbelieved {actor, illusion} and the image ends (summon_ended reason
## "disbelieved"); else the effort is wasted (attack_lost reason "illusion").
func _illusion_interaction(viewer: Combatant, image: Combatant) -> void:
	var seen := viewer.sheet.invocations.has("witch_sight") and GridMath.distance_tiles(viewer.position, image.position) <= 6
	if not seen:
		var res := ability_check(viewer, Ability.Type.INT, Skill.Type.INVESTIGATION, DictUtil.to_int(image.illusion.get("dc", 10), 10), "illusion")
		seen = res["success"] == true
	if seen:
		_emit("disbelieved", {"actor": viewer.id, "illusion": image.id})
		_dismiss(image, "disbelieved")
		return
	_emit("attack_lost", {"attacker": viewer.id, "target": image.id, "reason": "illusion"})


# --- round C: special outcomes (Wish, Time Stop, temporary weapons, Prismatic Spray) ------------

## The spell a Wish cast duplicates (its "mode" names a spell id), else null.
func _wish_duplicate(spell: SpellDefinition, intent: Dictionary) -> SpellDefinition:
	if spell == null or spell.effect_type != SpellDefinition.EFFECT_WISH:
		return null
	var mode := str(intent.get("mode", ""))
	if mode in ["", "restore_slots", "instant_health"]:
		return null
	return _spell_def(mode)


## Wish: "mode" is "restore_slots", "instant_health" (up to ten allies in
## `targets`, default the caster, within 12 tiles) or the id of a spell of 8th
## level or lower that the engine resolves in a fight; the duplicated spell
## needs no preparation and ignores its casting time, and its targets / point
## are checked as for that spell (at its own level).
func _check_wish(actor: Combatant, spell: SpellDefinition, intent: Dictionary) -> String:
	var mode := str(intent.get("mode", ""))
	match mode:
		"restore_slots":
			return ""
		"instant_health":
			var targets := _cast_targets(actor, intent)
			if targets.size() > DictUtil.to_int(spell.raw_effect.get("instant_health_targets", 10), 10):
				return "Wish heals at most ten creatures"
			for t in targets:
				if t == null or t.team != actor.team or not t.is_alive():
					return "Wish heals living allies"
				if GridMath.distance_tiles(actor.position, t.position) > 12:
					return "%s is too far away" % t.display_name
			return ""
		"":
			return "Wish needs a mode: a spell id, \"restore_slots\" or \"instant_health\""
	var dup := _spell_def(mode)
	if dup == null:
		return "unknown spell '%s'" % mode
	if dup.level > DictUtil.to_int(spell.raw_effect.get("max_duplicate_level", 8), 8) or dup.effect_type == SpellDefinition.EFFECT_WISH:
		return "Wish duplicates spells of 8th level or lower"
	if not dup.is_supported() or dup.effect_type in [SpellDefinition.EFFECT_REACTION, SpellDefinition.EFFECT_LINGERING] \
			or (dup.effect_type == SpellDefinition.EFFECT_SUMMON and dup.raw_effect.get("companion", false) == true and not dup.is_combat_castable()):
		return "%s has no effect Wish can produce in a fight" % dup.display_name
	match dup.effect_type:
		SpellDefinition.EFFECT_NO_EFFECT, SpellDefinition.EFFECT_TIME_STOP:
			return ""
		SpellDefinition.EFFECT_WEAPON_ATTACK:
			return _check_weapon_attack(actor, dup)
	_dup_slot = maxi(1, dup.level)
	var err := _check_cast_effect(actor, dup, intent)
	_dup_slot = 0
	return err


## Flame Blade / Shillelagh: Shillelagh needs a carried club or quarterstaff attack.
func _check_weapon_attack(actor: Combatant, spell: SpellDefinition) -> String:
	var items := DictUtil.to_string_array(spell.raw_effect.get("requires_items", []))
	if not items.is_empty() and _weapon_attack_base(actor, items) < 0:
		return "%s needs a %s" % [spell.display_name, " or ".join(items)]
	return ""


## Index of actor's first usable attack with one of the weapon ids, or -1.
func _weapon_attack_base(actor: Combatant, weapon_ids: Array[String]) -> int:
	for i in range(actor.attacks.size()):
		var a: Dictionary = actor.attacks[i]
		if a.get("disabled", false) == true or str(a.get("kind", "melee")) != "melee":
			continue
		if weapon_ids.has(str(a.get("weapon_id", ""))) or weapon_ids.has(str(a.get("item", ""))):
			var item := str(a.get("item", ""))
			if item.is_empty() or actor.sheet.has_item(item):
				return i
	return -1


## Temporary weapon attacks (SpellDefinition.EFFECT_WEAPON_ATTACK): an attack
## entry appended to the caster's attacks for the spell's duration (a buff
## "<spell>" carries it: concentration, rounds or the encounter); when the
## buff ends the entry is disabled (attack indexes stay stable). Flame Blade:
## a melee spell attack (spell attack bonus, 3d6 fire + 1d6 per two slot
## levels above 2nd), one attack per action. Shillelagh: the club /
## quarterstaff attack with the casting ability, a d8 damage die, magical.
## Emits effect_applied {.., effect, attack_index}.
func _cast_weapon_attack(actor: Combatant, spell: SpellDefinition, slot: int) -> void:
	var spec_v: Variant = spell.raw_effect.get("attack", {})
	var spec: Dictionary = spec_v if typeof(spec_v) == TYPE_DICTIONARY else {}
	var entry := {}
	var items := DictUtil.to_string_array(spell.raw_effect.get("requires_items", []))
	if not items.is_empty():
		var base := _weapon_attack_base(actor, items)
		if base < 0:
			return
		entry = (actor.attacks[base] as Dictionary).duplicate(true)
		var mod := actor.sheet.casting_modifier()
		entry["name"] = "%s (%s)" % [str(entry.get("name", "Weapon")), spell.display_name]
		entry["to_hit"] = mod + actor.sheet.proficiency_bonus()
		entry["damage"] = "1d%d" % DictUtil.to_int(spec.get("damage_die", 8), 8) + CharacterBuilder.signed(mod)
		entry["ability"] = Ability.abbreviation(actor.sheet.casting_ability) if actor.sheet.casting_ability >= 0 else "WIS"
		entry["magical"] = true
	else:
		var dice := str(spec.get("damage", "1d6"))
		var per := str(spec.get("per_two_slots", ""))
		var steps := floori((slot - spell.level) / 2.0)
		if not per.is_empty() and steps > 0:
			var base_dice := DiceExpr.parse(dice)
			var per_dice := DiceExpr.parse(per)
			if base_dice.valid and per_dice.valid and base_dice.sides == per_dice.sides and base_dice.modifier == 0 and per_dice.modifier == 0 and base_dice.keep_highest == 0:
				dice = "%dd%d" % [base_dice.count + per_dice.count * steps, base_dice.sides]
			else:
				dice = DiceFormula.plus(dice, per, steps)
		entry = {"name": str(spec.get("name", spell.display_name)), "kind": str(spec.get("kind", "melee")), "to_hit": actor.sheet.spell_attack_bonus(),
				"damage": dice, "damage_type": str(spec.get("damage_type", "fire")), "range_tiles": [1, 1], "magical": true, "single_attack": true,
				"ability": Ability.abbreviation(actor.sheet.casting_ability) if actor.sheet.casting_ability >= 0 else "CHA"}
	entry["temp_spell"] = spell.id
	entry.erase("off_hand")
	for i in range(actor.attacks.size()):
		var old: Dictionary = actor.attacks[i]
		if str(old.get("temp_spell", "")) == spell.id and old.get("disabled", false) != true:
			old["disabled"] = true
	actor.attacks.append(entry)
	var index := actor.attacks.size() - 1
	var duration := Conditions.duration(Conditions.DURATION_ENCOUNTER)
	if spell.rounds > 0 and not spell.concentration:
		duration = Conditions.duration(Conditions.DURATION_ROUNDS, {"rounds": spell.rounds})
	var b := _apply_buff(actor, spell.id, actor.id, duration, {"weapon_attack_index": index}, spell.id)
	_emit("effect_applied", {"source": actor.id, "target": actor.id, "effect": spell.id, "attack_index": index})
	if b.is_empty():
		entry["disabled"] = true


## Wish (see _check_wish): "restore_slots" regains every expended slot of
## 8th level or lower; "instant_health" restores the targets to full hit
## points and ends their conditions. Either strains the caster: one level of
## exhaustion (exhaustion {.., source: "wish"}). A duplicated spell is
## resolved by _do_cast.
func _cast_wish(actor: Combatant, spell: SpellDefinition, intent: Dictionary, targets: Array[Combatant]) -> void:
	match str(intent.get("mode", "")):
		"restore_slots":
			var restored: Array = []
			for i in range(mini(8, actor.sheet.spell_slots_max.size())):
				var missing := actor.sheet.spell_slots_max[i] - actor.sheet.spell_slots[i]
				if missing > 0:
					actor.sheet.spell_slots[i] = actor.sheet.spell_slots_max[i]
					restored.append(i + 1)
			_emit("slots_restored", {"actor": actor.id, "source": spell.id, "levels": restored})
		"instant_health":
			for t in targets:
				if t == null or not t.is_alive():
					continue
				_heal(actor.id, t, t.sheet.max_hp)
				for entry: Dictionary in t.conditions.duplicate():
					var src := get_combatant(str(entry.get("source", "")))
					if src == null or src.team != t.team:
						_remove_condition(t, entry)
	_add_exhaustion(actor, 1, "wish")


## Time Stop: the caster takes 1d4 + 1 turns in a row after this one
## (time_stop {actor, turns}; each extra turn: extra_turn {actor, source,
## turns_left}); meanwhile no one else can react. It ends early when the
## caster's action affects another creature (time_stop_ended {actor, reason:
## "affected_other"}), else after the last turn (reason "expired").
func _cast_time_stop(actor: Combatant, spell: SpellDefinition) -> void:
	var turns := maxi(1, DictUtil.to_int(DiceFormula.parse(str(spell.raw_effect.get("dice", "1d4+1"))).roll(rng)["total"], 2))
	actor.extra_turns = turns
	actor.extra_turn_source = "time_stop"
	actor.time_stopped = true
	_time_stop_reactions.clear()
	for c in tracker.order():
		if c != actor:
			_time_stop_reactions[c.id] = c.reaction_used
			c.reaction_used = true
	_emit("time_stop", {"actor": actor.id, "turns": turns})


func _end_time_stop(c: Combatant, reason: String) -> void:
	if not c.time_stopped:
		return
	c.time_stopped = false
	if c.extra_turn_source == "time_stop":
		c.extra_turns = 0
		c.extra_turn_source = ""
	for other in tracker.order():
		if _time_stop_reactions.has(other.id):
			other.reaction_used = _time_stop_reactions[other.id] == true
	_time_stop_reactions.clear()
	_emit("time_stop_ended", {"actor": c.id, "reason": reason})


## Whether an intent of a time-stopped actor affects another creature.
func _affects_others(actor: Combatant, intent: Dictionary) -> bool:
	match str(intent.get("type", "")):
		ATTACK, SHOVE, GRAPPLE, HELP, CONTROL:
			return true
		CAST:
			var spell := _spell_def(str(intent.get("spell", "")))
			if spell == null:
				return false
			var fx_spell := _wish_duplicate(spell, intent)
			if fx_spell == null:
				fx_spell = spell
			if fx_spell.is_area() or fx_spell.effect_type == SpellDefinition.EFFECT_ZONE:
				return true
			for t in _cast_targets(actor, intent):
				if t != null and t != actor:
					return true
		USE_FEATURE:
			var tid := str(intent.get("target", actor.id))
			return not tid.is_empty() and tid != actor.id
	return false


## Prismatic Spray: each creature in the cone saves (DEX) once, then a d8
## picks its ray (prismatic_ray {caster, target, roll, layer}): 1-5 damage
## (10d6, half on a save), 6 indigo, 7 violet (see _prismatic_layer), 8 two
## rays (rolled again, ignoring 8).
func _prismatic_spray(actor: Combatant, spell: SpellDefinition, affected: Array[Combatant], careful: Array[String]) -> void:
	var layers: Array[String] = ["red", "orange", "yellow", "green", "blue", "indigo", "violet"]
	var dc := actor.sheet.spell_save_dc()
	for t in affected:
		if not t.is_alive():
			continue
		var success := careful.has(t.id)
		if success:
			_emit("save", {"actor": actor.id, "target": t.id, "ability": "DEX", "dc": dc, "natural": 0, "total": 0, "success": true, "careful": true})
		else:
			success = _saving_throw(actor.id, t, Ability.Type.DEX, dc, _save_opts(spell, t))
		var rolls: Array[int] = []
		var roll := rng.next_int(1, 8)
		if roll == 8:
			rolls.append(rng.next_int(1, 7))
			rolls.append(rng.next_int(1, 7))
		else:
			rolls.append(roll)
		for r in rolls:
			if not t.is_alive():
				break
			_emit("prismatic_ray", {"caster": actor.id, "target": t.id, "roll": roll, "layer": layers[r - 1]})
			_prismatic_layer(actor.id, t, layers[r - 1], dc, spell.id, 1 if success else 0)


# --- round C: exploration utilities in a fight ------------------------------------------------------

## A lingering spell cast in a fight (Gentle Repose): each target's sheet
## gets the lingering entry (see OutOfCombat.lingering_entry) and buff kinds
## take hold at once: lingering_added {source, target, spell, lingering_kind,
## encounters}.
func _cast_lingering(actor: Combatant, spell: SpellDefinition, slot: int, intent: Dictionary, targets: Array[Combatant]) -> void:
	for t in targets:
		if t == null:
			continue
		var entry := OutOfCombat.lingering_entry(spell, slot, intent)
		OutOfCombat.add_lingering(t.sheet, entry)
		_emit("lingering_added", {"source": actor.id, "target": t.id, "spell": spell.id, "lingering_kind": entry["kind"], "encounters": entry["encounters_left"]})
		if str(entry["kind"]) in ["buff", "stealth"] and t.is_alive():
			var mods_v: Variant = entry.get("modifiers", {})
			_apply_buff(t, str(entry.get("effect", spell.id)), actor.id, Conditions.duration(Conditions.DURATION_ENCOUNTER), mods_v if typeof(mods_v) == TYPE_DICTIONARY else {}, spell.id)

## Exploration spells cast in a fight (SpellDefinition.EFFECT_EXPLORATION):
## exploration_effect {actor, spell, effect, ...} for the server, plus the
## fight hooks some of them have.
## Fight hooks: "light" lights the tiles around the target (a "lit" tile
## effect anchored to it, radius_ft; a hostile target makes the spell's save
## to avoid it; concentration spells end with concentration) and Daylight
## ends magical darkness of a spell of "dispel_darkness" level or lower that
## overlaps it (tile_effect_ended reason "dispelled"); "fight_reveal"
## (Detect Thoughts, Detect Evil and Good) reveals hidden hostiles within
## its radius (creature_types / min_int): revealed {.., reason: "detected", by}.
func _cast_exploration(actor: Combatant, spell: SpellDefinition, slot: int, intent: Dictionary, targets: Array[Combatant]) -> void:
	var ev := OutOfCombat.exploration_fields(spell, intent)
	ev["actor"] = actor.id
	var e := spell.raw_effect
	var t: Combatant = targets[0] if not targets.is_empty() and targets[0] != null else actor
	if str(ev["effect"]) in ["light", "recall"]:
		var ids: Array = []
		for c in targets:
			if c != null:
				ids.append(c.id)
		ev["targets"] = ids
	_emit("exploration_effect", ev)
	match str(ev["effect"]):
		"light":
			var save := Ability.from_string(str(e.get("save", "")))
			if t.team != actor.team and save >= 0 and _saving_throw(actor.id, t, save, actor.sheet.spell_save_dc(), _save_opts(spell, t)):
				return
			var radius := GridMath.feet_to_tiles(DictUtil.to_int(e.get("radius_ft", 20), 20))
			var cells := AreaOfEffect.tiles("sphere", radius, t.position, t.position, walk_map)
			var fx := _create_zone(actor, spell.id, {"lit": true, "rounds": -1}, slot, cells, t.id, radius, spell.concentration, "", "", spell.level, t.position)
			var max_level := DictUtil.to_int(e.get("dispel_darkness", -1), -1)
			if max_level >= 0:
				for other in tile_effects.duplicate():
					if other.get("darkness", false) != true or DictUtil.to_int(other.get("spell_level", 0), 0) > max_level:
						continue
					for cell in _effect_cells(other):
						if _effect_covers(fx, cell):
							_end_tile_effect(other, "dispelled")
							break
	var reveal_v: Variant = e.get("fight_reveal", null)
	if typeof(reveal_v) == TYPE_DICTIONARY:
		var fr: Dictionary = reveal_v
		var radius := GridMath.feet_to_tiles(DictUtil.to_int(fr.get("radius_ft", 30), 30))
		var types := DictUtil.to_string_array(fr.get("creature_types", []))
		var min_int := DictUtil.to_int(fr.get("min_int", 0), 0)
		for h in tracker.order():
			if h.team == actor.team or not h.hidden or not h.is_alive() or GridMath.distance_tiles(actor.position, h.position) > radius:
				continue
			if not types.is_empty() and not types.has(h.creature_type):
				continue
			if h.sheet.abilities.get_score(Ability.Type.INT) < min_int:
				continue
			_reveal(h, "detected", actor.id)

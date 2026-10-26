class_name Encounter
extends RefCounted
## Turn-based combat inside one bounded battle area (server-owned state machine).
##
## FORMING: combatants gather; start() needs living combatants on >= 2 teams.
## ACTIVE: turns follow the InitiativeTracker; newcomers join via add_mid_combat.
## ENDED: every conscious combatant left shares one team (winning_team), or
##        nobody is left standing (winning_team = -1).
## One attack (action) per turn for now; no movement or grid yet (M1).

enum State { FORMING, ACTIVE, ENDED }

var id: String = ""
var state: State = State.FORMING
var tracker: InitiativeTracker = InitiativeTracker.new()
var rng: Rng = null
var event_log: Array[String] = []
var winning_team: int = -1
var _combatants: Dictionary = {}  # id -> Combatant
var _action_used: bool = false


func _init(encounter_id: String, encounter_rng: Rng) -> void:
	id = encounter_id
	rng = encounter_rng


func add_combatant(c: Combatant) -> bool:
	if c == null or c.sheet == null or c.id.is_empty():
		_note("Rejected: invalid combatant.")
		return false
	if state == State.ENDED:
		_note("Rejected: %s cannot join, the encounter has ended." % c.display_name)
		return false
	if _combatants.has(c.id):
		_note("Rejected: duplicate combatant id '%s'." % c.id)
		return false
	var ok := false
	if state == State.FORMING:
		ok = tracker.add(c, rng)
	else:
		ok = tracker.add_mid_combat(c, rng)
	if not ok:
		return false
	_combatants[c.id] = c
	_note("%s joins team %d (initiative %d)." % [c.display_name, c.team, c.initiative])
	return true


func remove_combatant(combatant_id: String) -> bool:
	if not _combatants.has(combatant_id):
		return false
	var was_current := current_actor() != null and current_actor().id == combatant_id
	_combatants.erase(combatant_id)
	tracker.remove(combatant_id)
	if was_current:
		_action_used = false
	check_end()
	return true


func start() -> bool:
	if state != State.FORMING:
		return false
	if _conscious_teams().size() < 2:
		_note("Cannot start: need combatants from at least two teams.")
		return false
	state = State.ACTIVE
	var first := tracker.begin()
	_note("Encounter %s begins. Round 1: %s acts first." % [id, first.display_name if first != null else "nobody"])
	return true


func get_combatant(combatant_id: String) -> Combatant:
	if not _combatants.has(combatant_id):
		return null
	var c: Combatant = _combatants[combatant_id]
	return c


func current_actor() -> Combatant:
	return tracker.current() if state == State.ACTIVE else null


## Validates and resolves an attack by the current actor. Returns null (and
## logs why) when the attack is not allowed.
func perform_attack(attacker_id: String, target_id: String, attack: Dictionary, mode: D20.RollMode = D20.RollMode.NORMAL) -> AttackResult:
	if state != State.ACTIVE:
		return _reject("encounter is not active")
	var attacker := get_combatant(attacker_id)
	var target := get_combatant(target_id)
	var actor := current_actor()
	if attacker == null or target == null:
		return _reject("unknown attacker or target")
	if actor == null or actor.id != attacker_id:
		return _reject("it is not %s's turn" % attacker.display_name)
	if not attacker.is_conscious():
		return _reject("%s cannot act" % attacker.display_name)
	if _action_used:
		return _reject("%s has already attacked this turn" % attacker.display_name)
	if target.team == attacker.team:
		return _reject("%s and %s are on the same team" % [attacker.display_name, target.display_name])
	if not target.is_alive():
		return _reject("%s is already dead" % target.display_name)
	var result := AttackResolver.resolve_attack(attacker, target, attack, rng, mode)
	_action_used = true
	_note(result.summary())
	check_end()
	return result


## Ends the current turn. Returns the next actor, or null if the encounter ended.
func end_turn() -> Combatant:
	if state != State.ACTIVE:
		return null
	_action_used = false
	var previous_round := tracker.round_number
	var next := tracker.advance()
	if check_end():
		return null
	if tracker.round_number != previous_round:
		_note("Round %d begins." % tracker.round_number)
	if next != null:
		_note("%s's turn." % next.display_name)
	return next


## Ends the encounter when at most one team still has conscious combatants.
func check_end() -> bool:
	if state == State.ENDED:
		return true
	if state != State.ACTIVE:
		return false
	var teams := _conscious_teams()
	if teams.size() > 1:
		return false
	state = State.ENDED
	winning_team = -1
	for team_id: int in teams.keys():
		winning_team = team_id
	_note("Encounter %s ends. Winning team: %d." % [id, winning_team])
	return true


func combatants() -> Array[Combatant]:
	return tracker.order()


func _conscious_teams() -> Dictionary:
	var teams := {}
	for value: Variant in _combatants.values():
		var c: Combatant = value
		if c.is_conscious():
			teams[c.team] = true
	return teams


func _reject(reason: String) -> AttackResult:
	_note("Rejected: %s." % reason)
	return null


func _note(line: String) -> void:
	event_log.append(line)

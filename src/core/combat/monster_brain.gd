class_name MonsterBrain
extends RefCounted
## Simple, deterministic melee monster AI. decide() only reads the encounter;
## the server feeds each returned intent through Encounter.submit() in order
## (after a rejection, e.g. the monster was dropped by an opportunity attack
## and its turn already ended, the remaining intents can be discarded).
##
## Targets: conscious hostiles; only when none is left, dying hostiles
## (unconscious, not dead, not stable: still rolling death saves). Stable and
## dead combatants are never targeted.
## Plan: if adjacent to a target, attack the adjacent one with the lowest hp
## (ties: id) using its first melee attack. Otherwise walk toward the nearest
## target (Chebyshev distance, ties: id) along WalkMap.path_to, truncated to
## the remaining movement, and attack if that ends adjacent. If it still is
## not adjacent and has a ranged attack (goblin / skeleton shortbow), shoot
## the nearest target (ties: id) within long range and line of sight from
## where it stopped. (Attacks on a dying target have advantage and crit
## within 5 ft: Encounter rules.) Always finish with end_turn.
## Conditions: stunned / paralyzed / incapacitated monsters only end their
## turn; a prone one stands up first (half its speed); a turned one (Turn
## Undead) moves as far from the turner as it can, Dashes and moves again; a
## frightened one never steps closer to the source of its fear (it stops, then
## attacks if something is in reach); a charmed one ignores its charmer.
## Attacks: one Attack action = its Multiattack names in order (else
## attacks_per_action attacks); follow-up attacks carry "retarget": true so
## the encounter switches to another conscious hostile in reach if the first
## target dropped.


static func decide(enc: Encounter, actor_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var me := enc.get_combatant(actor_id)
	if me == null or not me.is_conscious():
		return out
	if me.loses_turn() or me.is_incapacitated():
		out.append(MonsterBrain._intent(Encounter.END_TURN, actor_id))
		return out
	var movement := me.movement_remaining
	var pos := me.position
	if me.has_condition(Conditions.PRONE) and enc.stand_error(me).is_empty():
		out.append(MonsterBrain._intent(Encounter.STAND, actor_id))
		movement -= enc.stand_cost(me)
	if me.is_fleeing():
		MonsterBrain._flee(enc, me, movement, out)
		out.append(MonsterBrain._intent(Encounter.END_TURN, actor_id))
		return out
	var hostiles := MonsterBrain._targets(enc, me)
	if not hostiles.is_empty() and not me.attacks.is_empty() and not me.action_used:
		var melee := me.first_melee_attack()
		var ranged := me.first_ranged_attack()
		var target := MonsterBrain._weakest_adjacent(pos, hostiles)
		if target == null and movement > 0:
			var path := MonsterBrain._path_toward_nearest(enc, me, hostiles, movement)
			if not path.is_empty():
				out.append({"v": Encounter.INTENT_VERSION, "type": Encounter.MOVE, "actor": actor_id, "path": GridMath.vec_list_to_arr(path)})
				pos = path[path.size() - 1]
				target = MonsterBrain._weakest_adjacent(pos, hostiles)
		var index := melee if melee >= 0 else ranged
		if target == null and ranged >= 0:
			target = MonsterBrain._nearest_in_range(enc, pos, me.attacks[ranged], hostiles)
			index = ranged
		if target != null and index >= 0:
			var sequence := MonsterBrain._attack_sequence(me, index)
			for i in range(sequence.size()):
				var attack := {"v": Encounter.INTENT_VERSION, "type": Encounter.ATTACK, "actor": actor_id, "target": target.id, "attack_index": sequence[i]}
				if i > 0:
					attack["retarget"] = true
				out.append(attack)
	out.append(MonsterBrain._intent(Encounter.END_TURN, actor_id))
	return out


static func _intent(intent_type: String, actor_id: String) -> Dictionary:
	return {"v": Encounter.INTENT_VERSION, "type": intent_type, "actor": actor_id}


## Attack indices for one Attack action: the Multiattack names in order (a
## name of the wrong kind for this plan, or unknown, uses `index`), else
## `index` attacks_per_action times.
static func _attack_sequence(me: Combatant, index: int) -> Array[int]:
	var out: Array[int] = []
	var plan_ranged := Encounter.is_ranged_attack(me.attacks[index])
	if me.multiattack.is_empty():
		for _i in range(maxi(1, me.attacks_per_action)):
			out.append(index)
		return out
	for attack_name in me.multiattack:
		var chosen := index
		for i in range(me.attacks.size()):
			if str(me.attacks[i].get("name", "")).to_lower() == attack_name.to_lower():
				if Encounter.is_ranged_attack(me.attacks[i]) == plan_ranged:
					chosen = i
				break
		out.append(chosen)
	return out


## Turned: move as far from the turner as possible, Dash, and keep going.
static func _flee(enc: Encounter, me: Combatant, movement: int, out: Array[Dictionary]) -> void:
	var fears := enc.fear_sources(me)
	if fears.is_empty():
		return
	var occupied := enc.occupied_cells(me.id)
	var pos := me.position
	for leg in range(2):
		var budget := movement if leg == 0 else me.speed_tiles()
		var path: Array[Vector2i] = []
		for _i in range(budget):
			var best := pos
			var best_d := MonsterBrain._fear_distance(pos, fears)
			for n in GridMath.neighbors8(pos):
				if not enc.walk_map.can_step(pos, n, occupied):
					continue
				var d := MonsterBrain._fear_distance(n, fears)
				if d > best_d and MonsterBrain._not_closer(pos, n, fears):
					best = n
					best_d = d
			if best == pos:
				break
			path.append(best)
			pos = best
		if leg == 1:
			if path.is_empty():
				return
			out.append(MonsterBrain._intent(Encounter.DASH, me.id))
		if not path.is_empty():
			out.append({"v": Encounter.INTENT_VERSION, "type": Encounter.MOVE, "actor": me.id, "path": GridMath.vec_list_to_arr(path)})


static func _fear_distance(p: Vector2i, fears: Array[Combatant]) -> int:
	var d := 1 << 30
	for f in fears:
		d = mini(d, GridMath.distance_tiles(p, f.position))
	return d


static func _not_closer(from: Vector2i, to: Vector2i, fears: Array[Combatant]) -> bool:
	for f in fears:
		if GridMath.distance_tiles(to, f.position) < GridMath.distance_tiles(from, f.position):
			return false
	return true


## Conscious hostiles of me; when there are none, the dying ones.
static func _targets(enc: Encounter, me: Combatant) -> Array[Combatant]:
	var conscious: Array[Combatant] = []
	var dying: Array[Combatant] = []
	var charmed_by := me.condition_sources(Conditions.CHARMED)
	for h in enc.hostiles_of(me):
		if charmed_by.has(h.id):
			continue
		if h.is_conscious():
			conscious.append(h)
		elif h.is_dying():
			dying.append(h)
	return conscious if not conscious.is_empty() else dying


## Lowest current hp among hostiles adjacent to pos; ties broken by id.
static func _weakest_adjacent(pos: Vector2i, hostiles: Array[Combatant]) -> Combatant:
	var best: Combatant = null
	for h in hostiles:
		if not GridMath.is_adjacent(pos, h.position):
			continue
		if best == null or h.sheet.current_hp < best.sheet.current_hp \
				or (h.sheet.current_hp == best.sheet.current_hp and h.id < best.id):
			best = h
	return best


## Nearest hostile (ties: id) the attack reaches from pos (range and line of sight).
static func _nearest_in_range(enc: Encounter, pos: Vector2i, attack: Dictionary, hostiles: Array[Combatant]) -> Combatant:
	var best: Combatant = null
	var best_dist := 0
	for h in hostiles:
		if not enc.attack_reach_error(pos, h.position, attack).is_empty():
			continue
		var d := GridMath.distance_tiles(pos, h.position)
		if best == null or d < best_dist or (d == best_dist and h.id < best.id):
			best = h
			best_dist = d
	return best


## Path (truncated to movement_remaining) toward the nearest hostile that can
## be reached at all; empty if none can.
## A frightened monster's path stops before the first step that would bring
## it closer to a source of its fear.
static func _path_toward_nearest(enc: Encounter, me: Combatant, hostiles: Array[Combatant], movement: int) -> Array[Vector2i]:
	var sorted := hostiles.duplicate()
	sorted.sort_custom(func(a: Combatant, b: Combatant) -> bool:
		var da := GridMath.distance_tiles(me.position, a.position)
		var db := GridMath.distance_tiles(me.position, b.position)
		if da != db:
			return da < db
		return a.id < b.id)
	var occupied := enc.occupied_cells(me.id)
	for h: Combatant in sorted:
		var path := enc.walk_map.path_to(me.position, h.position, occupied)
		if path.is_empty():
			continue
		if path.size() > movement:
			path.resize(movement)
		var fears := enc.fear_sources(me)
		if not fears.is_empty():
			var cursor := me.position
			for i in range(path.size()):
				if not MonsterBrain._not_closer(cursor, path[i], fears):
					path.resize(i)
					break
				cursor = path[i]
			if path.is_empty():
				continue
		return path
	var none: Array[Vector2i] = []
	return none

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


static func decide(enc: Encounter, actor_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var me := enc.get_combatant(actor_id)
	if me == null or not me.is_conscious():
		return out
	var hostiles := MonsterBrain._targets(enc, me)
	if not hostiles.is_empty() and not me.attacks.is_empty() and not me.action_used:
		var melee := me.first_melee_attack()
		var ranged := me.first_ranged_attack()
		var pos := me.position
		var target := MonsterBrain._weakest_adjacent(pos, hostiles)
		if target == null and me.movement_remaining > 0:
			var path := MonsterBrain._path_toward_nearest(enc, me, hostiles)
			if not path.is_empty():
				out.append({"v": Encounter.INTENT_VERSION, "type": Encounter.MOVE, "actor": actor_id, "path": GridMath.vec_list_to_arr(path)})
				pos = path[path.size() - 1]
				target = MonsterBrain._weakest_adjacent(pos, hostiles)
		var index := melee if melee >= 0 else ranged
		if target == null and ranged >= 0:
			target = MonsterBrain._nearest_in_range(enc, pos, me.attacks[ranged], hostiles)
			index = ranged
		if target != null and index >= 0:
			out.append({"v": Encounter.INTENT_VERSION, "type": Encounter.ATTACK, "actor": actor_id, "target": target.id, "attack_index": index})
	out.append({"v": Encounter.INTENT_VERSION, "type": Encounter.END_TURN, "actor": actor_id})
	return out


## Conscious hostiles of me; when there are none, the dying ones.
static func _targets(enc: Encounter, me: Combatant) -> Array[Combatant]:
	var conscious: Array[Combatant] = []
	var dying: Array[Combatant] = []
	for h in enc.hostiles_of(me):
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
static func _path_toward_nearest(enc: Encounter, me: Combatant, hostiles: Array[Combatant]) -> Array[Vector2i]:
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
		if path.size() > me.movement_remaining:
			path.resize(me.movement_remaining)
		return path
	var none: Array[Vector2i] = []
	return none

class_name InitiativeTracker
extends RefCounted
## Turn order for one encounter.
##
## Order: initiative descending, then DEX score descending, then join order
## (whoever joined first). Fully deterministic for a given Rng.
##
## Mid-combat joining rule: a combatant added with add_mid_combat() rolls
## initiative and is slotted into the order, but it never acts in the round it
## joins. Its first turn is at its initiative slot in the NEXT round. The
## current actor stays current.

var round_number: int = 0  # 0 until begin(), then 1, 2, ...
var _entries: Array[Combatant] = []
var _index: int = -1
var _begun: bool = false
var _join_counter: int = 0


## Rolls d20 + initiative modifier and inserts before combat starts
## (advantage with Feral Instinct, disadvantage with exhaustion).
func add(c: Combatant, rng: Rng) -> bool:
	return insert_with_initiative(c, D20.roll(rng, c.initiative_mode()).natural + c.initiative_modifier(), false)


## Rolls initiative for a combatant joining an ongoing fight (see class doc).
func add_mid_combat(c: Combatant, rng: Rng) -> bool:
	return insert_with_initiative(c, D20.roll(rng, c.initiative_mode()).natural + c.initiative_modifier(), true)


## Inserts c (a summon) directly after `owner` with the owner's initiative:
## it acts right after its owner, starting this round if the owner is the
## current actor or has not acted yet.
func insert_after(c: Combatant, owner: Combatant) -> bool:
	if c == null or owner == null or has(c.id):
		return false
	var owner_idx := _find(owner.id)
	if owner_idx < 0:
		return false
	c.initiative = owner.initiative
	c.join_order = _join_counter
	_join_counter += 1
	var idx := owner_idx + 1
	while idx < _entries.size() and _entries[idx].owner_id == owner.id:
		idx += 1
	c.has_acted_this_round = _begun and idx <= _index
	_entries.insert(idx, c)
	if _begun and idx <= _index:
		_index += 1
	return true


## Inserts with a known initiative value (tests, restoring saved state).
func insert_with_initiative(c: Combatant, initiative_value: int, mid_combat: bool = false) -> bool:
	if c == null or has(c.id):
		push_error("InitiativeTracker: null or duplicate combatant")
		return false
	c.initiative = initiative_value
	c.join_order = _join_counter
	_join_counter += 1
	c.has_acted_this_round = mid_combat and _begun
	var idx := 0
	while idx < _entries.size() and _comes_before(_entries[idx], c):
		idx += 1
	_entries.insert(idx, c)
	if _begun and idx <= _index:
		_index += 1
	return true


## Starts round 1 and returns the first living combatant.
func begin() -> Combatant:
	_begun = true
	round_number = 1
	_index = -1
	for e in _entries:
		e.has_acted_this_round = false
	return _step_to_next()


func has(combatant_id: String) -> bool:
	return _find(combatant_id) >= 0


func get_combatant(combatant_id: String) -> Combatant:
	var idx := _find(combatant_id)
	return _entries[idx] if idx >= 0 else null


func remove(combatant_id: String) -> bool:
	var idx := _find(combatant_id)
	if idx < 0:
		return false
	_entries.remove_at(idx)
	if not _begun:
		return true
	if idx < _index:
		_index -= 1
	elif idx == _index:
		_index -= 1
		_step_to_next()
	return true


func current() -> Combatant:
	if not _begun or _index < 0 or _index >= _entries.size():
		return null
	return _entries[_index]


## Ends the current turn and returns the next living combatant (skipping the
## dead). Increments round_number when wrapping. Returns null if none alive.
func advance() -> Combatant:
	if not _begun:
		return null
	var cur := current()
	if cur != null:
		cur.has_acted_this_round = true
	return _step_to_next()


func order() -> Array[Combatant]:
	var out: Array[Combatant] = []
	for e in _entries:
		out.append(e)
	return out


func size() -> int:
	return _entries.size()


func _step_to_next() -> Combatant:
	var any_alive := false
	for e in _entries:
		if e.is_alive():
			any_alive = true
			break
	if not any_alive:
		_index = -1 if _entries.is_empty() else 0
		return null
	var n := _entries.size()
	for _i in range(n * 2 + 1):
		_index += 1
		if _index >= n:
			_index = 0
			round_number += 1
			for e in _entries:
				e.has_acted_this_round = false
		var c := _entries[_index]
		if c.is_alive() and not c.has_acted_this_round:
			return c
	return null


func _find(combatant_id: String) -> int:
	for i in range(_entries.size()):
		if _entries[i].id == combatant_id:
			return i
	return -1


func _comes_before(a: Combatant, b: Combatant) -> bool:
	if b.is_summon() and a.id == b.owner_id:
		return true
	if a.is_summon() and b.id == a.owner_id:
		return false
	if a.initiative != b.initiative:
		return a.initiative > b.initiative
	if a.dex_score() != b.dex_score():
		return a.dex_score() > b.dex_score()
	return a.join_order < b.join_order

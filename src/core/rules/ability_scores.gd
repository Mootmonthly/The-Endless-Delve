class_name AbilityScores
extends RefCounted
## A creature's six ability scores (each 1..30, default 10).

const MIN_SCORE := 1
const MAX_SCORE := 30
const POINT_BUY_BUDGET := 27

var scores: Array[int] = [10, 10, 10, 10, 10, 10]


func get_score(t: int) -> int:
	if not Ability.is_valid(t):
		push_error("AbilityScores.get_score: invalid ability %d" % t)
		return 10
	return scores[t]


func set_score(t: int, value: int) -> void:
	if not Ability.is_valid(t):
		push_error("AbilityScores.set_score: invalid ability %d" % t)
		return
	scores[t] = clampi(value, MIN_SCORE, MAX_SCORE)


func get_modifier(t: int) -> int:
	return Ability.modifier(get_score(t))


## Sets all six scores in STR, DEX, CON, INT, WIS, CHA order.
func set_all(values: Array[int]) -> void:
	for i in range(mini(values.size(), Ability.COUNT)):
		set_score(i, values[i])


func copy() -> AbilityScores:
	var other := AbilityScores.new()
	for i in range(Ability.COUNT):
		other.scores[i] = scores[i]
	return other


static func standard_array() -> Array[int]:
	var values: Array[int] = [15, 14, 13, 12, 10, 8]
	return values


## Six scores, each rolled as 4d6 keeping the highest three.
static func roll_scores(rng: Rng) -> Array[int]:
	var expr := DiceExpr.parse("4d6kh3")
	var values: Array[int] = []
	for _i in range(Ability.COUNT):
		values.append(expr.roll(rng).total)
	return values


## Point-buy cost of a single score: 8->0, 9->1, ... 13->5, 14->7, 15->9.
## Returns -1 for scores outside 8..15.
static func point_buy_cost(score: int) -> int:
	if score < 8 or score > 15:
		return -1
	if score <= 13:
		return score - 8
	return 7 if score == 14 else 9


## Total point-buy cost of a set of scores, or -1 if any score is invalid.
static func point_buy_total(values: Array[int]) -> int:
	var total := 0
	for v in values:
		var cost := AbilityScores.point_buy_cost(v)
		if cost < 0:
			return -1
		total += cost
	return total


func to_dict() -> Dictionary:
	var d := {}
	for i in range(Ability.COUNT):
		d[Ability.abbreviation(i)] = scores[i]
	return d


## Reads {"STR": 15, ...}; missing keys default to 10.
static func from_dict(d: Dictionary) -> AbilityScores:
	var result := AbilityScores.new()
	for i in range(Ability.COUNT):
		var key := Ability.abbreviation(i)
		if d.has(key):
			result.set_score(i, DictUtil.to_int(d[key], 10))
	return result

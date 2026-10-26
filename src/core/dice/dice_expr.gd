class_name DiceExpr
extends RefCounted
## A parsed dice expression: "d20", "2d6+3", "1d8-1", "4d6kh3", "3", "-1".
##
## parse() never returns null. Check `valid` (and `error`) before rolling.
## A constant expression has count == 0 and sides == 0; its value is `modifier`.

const MAX_COUNT := 100
const MAX_SIDES := 1000
const MAX_MODIFIER := 1000

var source: String = ""
var count: int = 0
var sides: int = 0
var modifier: int = 0
var keep_highest: int = 0  # 0 = keep all dice
var valid: bool = false
var error: String = ""


static func parse(text: String) -> DiceExpr:
	var expr := DiceExpr.new()
	var cleaned := text.strip_edges().to_lower().replace(" ", "")
	expr.source = cleaned
	if cleaned.is_empty():
		expr.error = "empty dice expression"
		return expr

	var constant_re := RegEx.new()
	constant_re.compile("^([+-]?)(\\d{1,6})$")
	var cm := constant_re.search(cleaned)
	if cm != null:
		expr.modifier = cm.get_string(2).to_int()
		if cm.get_string(1) == "-":
			expr.modifier = -expr.modifier
		expr.valid = true
		return expr

	var dice_re := RegEx.new()
	dice_re.compile("^(\\d{0,4})d(\\d{1,5})(kh(\\d{1,4}))?(([+-])(\\d{1,6}))?$")
	var m := dice_re.search(cleaned)
	if m == null:
		expr.error = "cannot parse dice expression '%s'" % text
		return expr

	var count_text := m.get_string(1)
	expr.count = 1 if count_text.is_empty() else count_text.to_int()
	expr.sides = m.get_string(2).to_int()
	var keep_text := m.get_string(4)
	if not keep_text.is_empty():
		expr.keep_highest = keep_text.to_int()
	var mod_text := m.get_string(7)
	if not mod_text.is_empty():
		expr.modifier = mod_text.to_int()
		if m.get_string(6) == "-":
			expr.modifier = -expr.modifier

	if expr.count < 1 or expr.count > MAX_COUNT:
		expr.error = "dice count must be 1..%d in '%s'" % [MAX_COUNT, text]
	elif expr.sides < 1 or expr.sides > MAX_SIDES:
		expr.error = "dice sides must be 1..%d in '%s'" % [MAX_SIDES, text]
	elif not keep_text.is_empty() and (expr.keep_highest < 1 or expr.keep_highest > expr.count):
		expr.error = "keep-highest must be 1..%d in '%s'" % [expr.count, text]
	elif absi(expr.modifier) > MAX_MODIFIER:
		expr.error = "modifier out of range in '%s'" % text
	else:
		expr.valid = true
	return expr


func is_constant() -> bool:
	return count == 0


## Number of dice that contribute to the total (non-critical).
func kept_count() -> int:
	return keep_highest if keep_highest > 0 else count


func min_total() -> int:
	return kept_count() + modifier


func max_total() -> int:
	return kept_count() * sides + modifier


## Rolls the expression. With critical == true the number of dice is doubled
## (and so is keep_highest); the flat modifier is NOT doubled (SRD crit rule).
func roll(rng: Rng, critical: bool = false) -> DiceRoll:
	var result := DiceRoll.new()
	result.expression = _to_string()
	result.modifier = modifier
	result.critical = critical and count > 0
	if not valid:
		push_error("DiceExpr.roll on invalid expression: %s" % error)
		return result
	var n := count * 2 if result.critical else count
	for _i in range(n):
		result.rolls.append(rng.next_int(1, sides))
	if keep_highest > 0:
		var keep := keep_highest * 2 if result.critical else keep_highest
		var sorted: Array[int] = []
		for r in result.rolls:
			sorted.append(r)
		sorted.sort()
		sorted.reverse()
		for i in range(mini(keep, sorted.size())):
			result.kept.append(sorted[i])
	else:
		for r in result.rolls:
			result.kept.append(r)
	var sum := 0
	for k in result.kept:
		sum += k
	result.total = sum + modifier
	return result


func _to_string() -> String:
	if not valid:
		return source
	if count == 0:
		return str(modifier)
	var text := "%dd%d" % [count, sides]
	if keep_highest > 0:
		text += "kh%d" % keep_highest
	if modifier > 0:
		text += "+%d" % modifier
	elif modifier < 0:
		text += "-%d" % absi(modifier)
	return text

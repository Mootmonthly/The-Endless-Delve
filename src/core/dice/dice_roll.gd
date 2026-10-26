class_name DiceRoll
extends RefCounted
## The result of rolling a DiceExpr: every die rolled, the dice kept, and the total.

var expression: String = ""
var rolls: Array[int] = []
var kept: Array[int] = []
var modifier: int = 0
var total: int = 0
var critical: bool = false


## Human-readable breakdown, e.g. "2d6+3 [4, 2] +3 = 9" or
## "4d6kh3 [6, 1, 5, 3] keep [6, 5, 3] = 14".
func to_string_breakdown() -> String:
	if rolls.is_empty():
		return "%s = %d" % [expression, total]
	var text := "%s %s" % [expression, DiceRoll._list(rolls)]
	if kept.size() != rolls.size():
		text += " keep " + DiceRoll._list(kept)
	if modifier > 0:
		text += " +%d" % modifier
	elif modifier < 0:
		text += " -%d" % absi(modifier)
	text += " = %d" % total
	if critical:
		text += " (critical)"
	return text


static func _list(values: Array[int]) -> String:
	var parts := PackedStringArray()
	for v in values:
		parts.append(str(v))
	return "[" + ", ".join(parts) + "]"

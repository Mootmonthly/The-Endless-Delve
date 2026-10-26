class_name D20Result
extends RefCounted
## Outcome of a d20 roll, possibly with advantage or disadvantage.

var natural: int = 0  # the kept die
var all: Array[int] = []  # every die rolled, in roll order
var mode: int = 0  # a D20.RollMode value


func is_nat20() -> bool:
	return natural == 20


func is_nat1() -> bool:
	return natural == 1


func _to_string() -> String:
	if all.size() <= 1:
		return "d20(%d)" % natural
	return "d20%s->%d" % [str(all), natural]

class_name D20
extends RefCounted
## d20 rolls with advantage / disadvantage.

enum RollMode { NORMAL, ADVANTAGE, DISADVANTAGE }


## Normal: one die. Advantage: two dice, keep the higher.
## Disadvantage: two dice, keep the lower.
static func roll(rng: Rng, mode: RollMode = RollMode.NORMAL) -> D20Result:
	var result := D20Result.new()
	result.mode = mode
	var first := rng.next_int(1, 20)
	result.all.append(first)
	result.natural = first
	if mode != RollMode.NORMAL:
		var second := rng.next_int(1, 20)
		result.all.append(second)
		if mode == RollMode.ADVANTAGE:
			result.natural = maxi(first, second)
		else:
			result.natural = mini(first, second)
	return result


## Any number of advantage sources and disadvantage sources cancel out:
## if both are present the roll is NORMAL.
static func combine(advantage: bool, disadvantage: bool) -> RollMode:
	if advantage == disadvantage:
		return RollMode.NORMAL
	return RollMode.ADVANTAGE if advantage else RollMode.DISADVANTAGE

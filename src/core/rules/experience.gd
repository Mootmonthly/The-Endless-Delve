class_name Experience
extends RefCounted
## SRD experience point thresholds for character levels 1..20.

const MAX_LEVEL := 20
const THRESHOLDS: Array[int] = [
	0, 300, 900, 2700, 6500, 14000, 23000, 34000, 48000, 64000,
	85000, 100000, 120000, 140000, 165000, 195000, 225000, 265000, 305000, 355000,
]


## Total XP needed to reach `level` (clamped to 1..20).
static func xp_for_level(level: int) -> int:
	var clamped := clampi(level, 1, MAX_LEVEL)
	return THRESHOLDS[clamped - 1]


static func level_for_xp(xp: int) -> int:
	for level in range(MAX_LEVEL, 0, -1):
		if xp >= THRESHOLDS[level - 1]:
			return level
	return 1


## XP still needed for the next level (0 at level 20).
static func xp_to_next_level(xp: int) -> int:
	var level := Experience.level_for_xp(xp)
	if level >= MAX_LEVEL:
		return 0
	return Experience.xp_for_level(level + 1) - xp

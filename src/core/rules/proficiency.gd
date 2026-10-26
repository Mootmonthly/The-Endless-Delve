class_name Proficiency
extends RefCounted
## Proficiency bonus by character level (SRD): +2 at 1-4 ... +6 at 17-20.


static func bonus_for_level(level: int) -> int:
	var clamped := clampi(level, 1, 20)
	return 2 + floori((clamped - 1) / 4.0)

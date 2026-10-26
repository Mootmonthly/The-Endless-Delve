class_name Ability
extends RefCounted
## The six ability scores and their modifiers (SRD rules).

enum Type { STR, DEX, CON, INT, WIS, CHA }

const COUNT := 6
const ABBREVIATIONS := ["STR", "DEX", "CON", "INT", "WIS", "CHA"]
const NAMES := ["Strength", "Dexterity", "Constitution", "Intelligence", "Wisdom", "Charisma"]


## floor((score - 10) / 2), correct for scores below 10 (e.g. 9 -> -1, 1 -> -5).
static func modifier(score: int) -> int:
	return floori((score - 10) / 2.0)


static func is_valid(t: int) -> bool:
	return t >= 0 and t < COUNT


static func name_of(t: int) -> String:
	if not is_valid(t):
		return "Unknown"
	return str(NAMES[t])


static func abbreviation(t: int) -> String:
	if not is_valid(t):
		return "???"
	return str(ABBREVIATIONS[t])


## "STR" / "str" / "Strength" -> Type.STR. Returns -1 when unknown.
static func from_string(s: String) -> int:
	var key := s.strip_edges().to_upper()
	var idx := ABBREVIATIONS.find(key)
	if idx >= 0:
		return idx
	for i in range(COUNT):
		if str(NAMES[i]).to_upper() == key:
			return i
	return -1

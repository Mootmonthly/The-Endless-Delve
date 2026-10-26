class_name Skill
extends RefCounted
## The eighteen SRD skills and the ability each one uses.

enum Type {
	ACROBATICS,
	ANIMAL_HANDLING,
	ARCANA,
	ATHLETICS,
	DECEPTION,
	HISTORY,
	INSIGHT,
	INTIMIDATION,
	INVESTIGATION,
	MEDICINE,
	NATURE,
	PERCEPTION,
	PERFORMANCE,
	PERSUASION,
	RELIGION,
	SLEIGHT_OF_HAND,
	STEALTH,
	SURVIVAL,
}

const COUNT := 18
const KEYS := [
	"ACROBATICS", "ANIMAL_HANDLING", "ARCANA", "ATHLETICS", "DECEPTION", "HISTORY",
	"INSIGHT", "INTIMIDATION", "INVESTIGATION", "MEDICINE", "NATURE", "PERCEPTION",
	"PERFORMANCE", "PERSUASION", "RELIGION", "SLEIGHT_OF_HAND", "STEALTH", "SURVIVAL",
]
const NAMES := [
	"Acrobatics", "Animal Handling", "Arcana", "Athletics", "Deception", "History",
	"Insight", "Intimidation", "Investigation", "Medicine", "Nature", "Perception",
	"Performance", "Persuasion", "Religion", "Sleight of Hand", "Stealth", "Survival",
]


static func is_valid(skill: int) -> bool:
	return skill >= 0 and skill < COUNT


static func ability_for(skill: int) -> Ability.Type:
	match skill:
		Type.ATHLETICS:
			return Ability.Type.STR
		Type.ACROBATICS, Type.SLEIGHT_OF_HAND, Type.STEALTH:
			return Ability.Type.DEX
		Type.ARCANA, Type.HISTORY, Type.INVESTIGATION, Type.NATURE, Type.RELIGION:
			return Ability.Type.INT
		Type.ANIMAL_HANDLING, Type.INSIGHT, Type.MEDICINE, Type.PERCEPTION, Type.SURVIVAL:
			return Ability.Type.WIS
		Type.DECEPTION, Type.INTIMIDATION, Type.PERFORMANCE, Type.PERSUASION:
			return Ability.Type.CHA
	push_error("Skill.ability_for: invalid skill %d" % skill)
	return Ability.Type.STR


static func name_of(skill: int) -> String:
	if not is_valid(skill):
		return "Unknown"
	return str(NAMES[skill])


static func key_of(skill: int) -> String:
	if not is_valid(skill):
		return ""
	return str(KEYS[skill])


## "STEALTH" / "stealth" / "Sleight of Hand" -> enum value. Returns -1 when unknown.
static func from_string(s: String) -> int:
	var key := s.strip_edges().to_upper().replace(" ", "_")
	return KEYS.find(key)

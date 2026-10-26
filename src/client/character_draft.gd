class_name CharacterDraft
extends RefCounted
## The character creator's choices and their validation, without any UI:
## name, class, ancestry, a standard-array assignment and skill picks.
## The CharacterCreator scene edits a draft and asks it for the preview and,
## once is_valid(), the finished CharacterSheet (built by CharacterBuilder).

## Classes offered in M1 (GDD wave 1), in menu order.
const WAVE_1_CLASSES: Array[String] = ["fighter", "rogue", "cleric", "wizard"]
const UNASSIGNED := -1
const MAX_NAME_LENGTH := 24
## Abilities filled after a class's primary abilities by auto_assign().
const FALLBACK_PRIORITY: Array[int] = [
	Ability.Type.CON, Ability.Type.DEX, Ability.Type.WIS, Ability.Type.STR, Ability.Type.INT, Ability.Type.CHA,
]

var character_name: String = ""
var class_def: ClassDefinition = null
var ancestry: AncestryDefinition = null
## Base score per Ability.Type (before ancestry bonuses); UNASSIGNED = not chosen.
var assigned: Array[int] = [UNASSIGNED, UNASSIGNED, UNASSIGNED, UNASSIGNED, UNASSIGNED, UNASSIGNED]
var skills: Array[int] = []


## Wave-1 classes from an id -> ClassDefinition map, in WAVE_1_CLASSES order.
static func wave_1_classes(all_classes: Dictionary) -> Array[ClassDefinition]:
	var out: Array[ClassDefinition] = []
	for id in WAVE_1_CLASSES:
		if all_classes.has(id):
			var def: ClassDefinition = all_classes[id]
			out.append(def)
	return out


## Ancestries sorted by display name.
static func sorted_ancestries(all_ancestries: Dictionary) -> Array[AncestryDefinition]:
	var out: Array[AncestryDefinition] = []
	for value: Variant in all_ancestries.values():
		var def: AncestryDefinition = value
		out.append(def)
	out.sort_custom(func(a: AncestryDefinition, b: AncestryDefinition) -> bool: return a.display_name < b.display_name)
	return out


## Changes class and drops skill picks the new class does not offer.
func set_class(def: ClassDefinition) -> void:
	class_def = def
	var kept: Array[int] = []
	if def != null:
		for s in skills:
			if def.skill_choices.has(s) and kept.size() < def.skill_choice_count:
				kept.append(s)
	skills = kept


func set_ancestry(def: AncestryDefinition) -> void:
	ancestry = def


## Gives ability `ability` the standard-array value `value` (or UNASSIGNED).
## Each value is used once: an ability already holding `value` takes this
## ability's previous value (a swap).
func assign(ability: int, value: int) -> void:
	if not Ability.is_valid(ability):
		return
	if value != UNASSIGNED and not AbilityScores.standard_array().has(value):
		return
	var previous := assigned[ability]
	if value != UNASSIGNED:
		for other in range(Ability.COUNT):
			if other != ability and assigned[other] == value:
				assigned[other] = previous
	assigned[ability] = value


## Standard array by the class's primary abilities, then CON, DEX, WIS, STR, INT, CHA.
func auto_assign() -> void:
	var priority: Array[int] = []
	if class_def != null:
		for a in class_def.primary_abilities:
			if not priority.has(a):
				priority.append(a)
	for a in FALLBACK_PRIORITY:
		if not priority.has(a):
			priority.append(a)
	var values := AbilityScores.standard_array()
	for i in range(Ability.COUNT):
		assigned[priority[i]] = values[i]


func is_fully_assigned() -> bool:
	return not assigned.has(UNASSIGNED)


## Adds or removes a skill pick. Returns false if the change is not allowed
## (not a class skill, or the class's skill count is already reached).
func toggle_skill(skill: int, on: bool) -> bool:
	if class_def == null or not class_def.skill_choices.has(skill):
		return false
	if not on:
		skills.erase(skill)
		return true
	if skills.has(skill):
		return true
	if skills.size() >= class_def.skill_choice_count:
		return false
	skills.append(skill)
	return true


func skills_needed() -> int:
	return class_def.skill_choice_count if class_def != null else 0


## Every reason the draft cannot be confirmed yet ([] when valid).
func problems() -> Array[String]:
	var out: Array[String] = []
	var trimmed := character_name.strip_edges()
	if trimmed.is_empty():
		out.append("Enter a name.")
	elif trimmed.length() > MAX_NAME_LENGTH:
		out.append("Name is too long (max %d characters)." % MAX_NAME_LENGTH)
	if class_def == null:
		out.append("Choose a class.")
	if ancestry == null:
		out.append("Choose an ancestry.")
	if not is_fully_assigned():
		out.append("Assign every standard-array score.")
	if class_def != null and skills.size() != class_def.skill_choice_count:
		out.append("Choose %d skills (%d chosen)." % [class_def.skill_choice_count, skills.size()])
	return out


func is_valid() -> bool:
	return problems().is_empty()


## Base scores with unassigned abilities shown as 10 (for previews).
func base_scores() -> AbilityScores:
	var scores := AbilityScores.new()
	for i in range(Ability.COUNT):
		scores.set_score(i, assigned[i] if assigned[i] != UNASSIGNED else 10)
	return scores


## The sheet CharacterBuilder makes from the current choices (unassigned
## scores count as 10). Null without a class.
func build_sheet() -> CharacterSheet:
	if class_def == null:
		return null
	var picked: Array[int] = []
	for s in skills:
		if class_def.skill_choices.has(s) and picked.size() < class_def.skill_choice_count:
			picked.append(s)
	return CharacterBuilder.create(character_name.strip_edges(), class_def, ancestry, base_scores(), picked)


## Numbers for the live preview: {"hp", "ac", "speed", "attack_name", "to_hit",
## "damage", "damage_type", "scores": Array[int] after ancestry bonuses}.
## {} without a class.
func preview() -> Dictionary:
	var sheet := build_sheet()
	if sheet == null:
		return {}
	var attack: Dictionary = sheet.attacks[0] if not sheet.attacks.is_empty() else sheet.unarmed_strike()
	var final_scores: Array[int] = []
	for i in range(Ability.COUNT):
		final_scores.append(sheet.abilities.get_score(i))
	return {
		"hp": sheet.max_hp,
		"ac": sheet.armor_class(),
		"speed": sheet.speed,
		"attack_name": str(attack.get("name", "")),
		"to_hit": DictUtil.to_int(attack.get("to_hit", 0), 0),
		"damage": str(attack.get("damage", "")),
		"damage_type": str(attack.get("damage_type", "")),
		"scores": final_scores,
	}

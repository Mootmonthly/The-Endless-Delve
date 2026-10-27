class_name CharacterDraft
extends RefCounted
## The character creator's choices and their validation, without any UI:
## name, class, ancestry, ability scores and skill picks.
##
## Ability scores come from one of three `method`s (SRD rules), all before
## ancestry bonuses:
## - METHOD_STANDARD: 15, 14, 13, 12, 10, 8, each used once.
## - METHOD_POINT_BUY: every score 8-15, AbilityScores.point_buy_cost per
##   score, at most POINT_BUY_BUDGET (27) points in total.
## - METHOD_ROLL: six 4d6-drop-lowest values (`rolled_values`, from
##   roll_scores(rng)), each used once, like the standard array. Offline
##   rerolls are unlimited; online servers will restrict rolled scores (GDD).
## The CharacterCreator scene edits a draft and asks it for the preview and,
## once is_valid(), the finished CharacterSheet (built by CharacterBuilder).
##
## Level-1 progression: classes whose subclass starts at level 1 (cleric,
## sorcerer, warlock) get their SRD subclass (subclass_info()), and
## creation_choices() (CharacterBuilder.creation_choices: fighting style,
## expertise from the chosen skills, Dragon Ancestor, ...) are answered in
## `creation_picks` (LevelUpDraft.choice_key -> [options]) and passed to
## CharacterBuilder.create. Picks that stop being options (another class,
## other skills) are dropped.

## Menu order of the SRD classes (all twelve are offered); classes missing
## here follow in display-name order.
const CLASS_ORDER: Array[String] = [
	"fighter", "rogue", "cleric", "wizard", "barbarian", "bard", "druid", "monk",
	"paladin", "ranger", "sorcerer", "warlock",
]
const UNASSIGNED := -1
const METHOD_STANDARD := "standard_array"
const METHOD_POINT_BUY := "point_buy"
const METHOD_ROLL := "roll"
## Score methods in menu order.
const METHODS: Array[String] = [METHOD_STANDARD, METHOD_POINT_BUY, METHOD_ROLL]
const METHOD_LABELS: Dictionary[String, String] = {
	METHOD_STANDARD: "Standard array",
	METHOD_POINT_BUY: "Point buy",
	METHOD_ROLL: "Roll (4d6, drop lowest)",
}
const POINT_BUY_MIN := 8
const POINT_BUY_MAX := 15
const MAX_NAME_LENGTH := 24
## Abilities filled after a class's primary abilities by auto_assign().
const FALLBACK_PRIORITY: Array[int] = [
	Ability.Type.CON, Ability.Type.DEX, Ability.Type.WIS, Ability.Type.STR, Ability.Type.INT, Ability.Type.CHA,
]

var character_name: String = ""
var class_def: ClassDefinition = null
var ancestry: AncestryDefinition = null
## How the scores are generated: one of METHODS.
var method: String = METHOD_STANDARD
## The six 4d6-drop-lowest values of the last roll ([] until rolled); kept
## when switching method so returning to Roll does not reroll.
var rolled_values: Array[int] = []
## Base score per Ability.Type (before ancestry bonuses); UNASSIGNED = not chosen.
var assigned: Array[int] = [UNASSIGNED, UNASSIGNED, UNASSIGNED, UNASSIGNED, UNASSIGNED, UNASSIGNED]
var skills: Array[int] = []
## Answers to creation_choices(): LevelUpDraft.choice_key(entry) -> Array[String].
var creation_picks: Dictionary = {}


## Every class of an id -> ClassDefinition map: CLASS_ORDER first, then
## any others by display name.
static func ordered_classes(all_classes: Dictionary) -> Array[ClassDefinition]:
	var out: Array[ClassDefinition] = []
	for id in CLASS_ORDER:
		if all_classes.has(id):
			var def: ClassDefinition = all_classes[id]
			out.append(def)
	var rest: Array[ClassDefinition] = []
	for id: Variant in all_classes.keys():
		if not CLASS_ORDER.has(str(id)):
			var def: ClassDefinition = all_classes[id]
			rest.append(def)
	rest.sort_custom(func(a: ClassDefinition, b: ClassDefinition) -> bool: return a.display_name < b.display_name)
	out.append_array(rest)
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
	if def != class_def:
		creation_picks.clear()
	class_def = def
	var kept: Array[int] = []
	if def != null:
		for s in skills:
			if def.skill_choices.has(s) and kept.size() < def.skill_choice_count:
				kept.append(s)
	skills = kept


func set_ancestry(def: AncestryDefinition) -> void:
	ancestry = def


## Switches the score method. Standard array: the class's suggested
## assignment; point buy: every score 8 (all 27 points to spend); roll: the
## suggested assignment of rolled_values, or nothing assigned until rolled.
func set_method(m: String) -> void:
	if not METHODS.has(m) or m == method:
		return
	method = m
	clear_scores()
	match method:
		METHOD_STANDARD:
			auto_assign()
		METHOD_POINT_BUY:
			for i in range(Ability.COUNT):
				assigned[i] = POINT_BUY_MIN
		METHOD_ROLL:
			if rolled_values.size() == Ability.COUNT:
				auto_assign()


## Rolls six new values (4d6 drop lowest, AbilityScores.roll_scores) with
## `rng`, switches to METHOD_ROLL and clears the assignment (a reroll
## replaces the previous values).
func roll_scores(rng: Rng) -> void:
	rolled_values = AbilityScores.roll_scores(rng)
	method = METHOD_ROLL
	clear_scores()


func clear_scores() -> void:
	for i in range(Ability.COUNT):
		assigned[i] = UNASSIGNED


## The values to choose among, highest first: the standard array, the
## distinct rolled values, or 15..8 for point buy.
func score_choices() -> Array[int]:
	var out: Array[int] = []
	match method:
		METHOD_POINT_BUY:
			for v in range(POINT_BUY_MAX, POINT_BUY_MIN - 1, -1):
				out.append(v)
		METHOD_ROLL:
			for v in rolled_values:
				if not out.has(v):
					out.append(v)
			out.sort()
			out.reverse()
		_:
			out = AbilityScores.standard_array()
	return out


## The values each used once (standard array or rolled values, highest
## first); [] for point buy.
func score_pool() -> Array[int]:
	var out: Array[int] = []
	match method:
		METHOD_ROLL:
			out.assign(rolled_values)
			out.sort()
			out.reverse()
		METHOD_STANDARD:
			out = AbilityScores.standard_array()
	return out


## Pool values not assigned to any ability yet, highest first ([] for point buy).
func unassigned_values() -> Array[int]:
	var left := score_pool()
	for v in assigned:
		if v != UNASSIGNED:
			left.erase(v)
	return left


## Gives ability `ability` the value `value` (or UNASSIGNED). Standard array
## and rolled values: each pool value is used once, so if every copy of
## `value` is taken, the first ability holding it takes this ability's
## previous value (a swap). Point buy: any score 8-15 (the budget is checked
## by problems()). Values outside score_choices() are ignored.
func assign(ability: int, value: int) -> void:
	if not Ability.is_valid(ability):
		return
	if value != UNASSIGNED and not score_choices().has(value):
		return
	if method == METHOD_POINT_BUY:
		if value != UNASSIGNED:
			assigned[ability] = value
		return
	var previous := assigned[ability]
	if value != UNASSIGNED and value != previous:
		var copies := score_pool().count(value)
		var used := 0
		var holder := -1
		for other in range(Ability.COUNT):
			if other != ability and assigned[other] == value:
				used += 1
				if holder < 0:
					holder = other
		if used >= copies and holder >= 0:
			assigned[holder] = previous
	assigned[ability] = value


## Point-buy points spent on the current scores (unassigned counts as 8), or
## -1 if a score is outside 8..15.
func point_buy_spent() -> int:
	var values: Array[int] = []
	for v in assigned:
		values.append(POINT_BUY_MIN if v == UNASSIGNED else v)
	return AbilityScores.point_buy_total(values)


## Points left of the 27-point budget (negative when overspent); -1 if a
## score is outside 8..15.
func point_buy_remaining() -> int:
	var spent := point_buy_spent()
	if spent < 0:
		return -1
	return AbilityScores.POINT_BUY_BUDGET - spent


## Whether setting `ability` to `value` keeps point buy within the budget.
func point_buy_affordable(ability: int, value: int) -> bool:
	if not Ability.is_valid(ability) or AbilityScores.point_buy_cost(value) < 0:
		return false
	var values: Array[int] = []
	for i in range(Ability.COUNT):
		var v := value if i == ability else assigned[i]
		values.append(POINT_BUY_MIN if v == UNASSIGNED else v)
	var total := AbilityScores.point_buy_total(values)
	return total >= 0 and total <= AbilityScores.POINT_BUY_BUDGET


## The suggested scores, by the class's primary abilities, then CON, DEX,
## WIS, STR, INT, CHA: the standard array (also for point buy, where it costs
## exactly 27 points) or the rolled values highest first. Nothing happens for
## Roll before a roll.
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
	if method == METHOD_ROLL:
		values = score_pool()
		if values.size() != Ability.COUNT:
			return
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


## The level-1 progression choices of the class with the chosen skills
## (LevelUp choice entries; [] without a class). Stale picks are dropped.
func creation_choices(content: Dictionary = {}) -> Array[Dictionary]:
	if class_def == null:
		return [] as Array[Dictionary]
	var entries := CharacterBuilder.creation_choices(class_def, _picked_skills(), content)
	var keys: Array[String] = []
	for entry in entries:
		var key := LevelUpDraft.choice_key(entry)
		keys.append(key)
		var opts := DictUtil.to_string_array(entry.get("options", []))
		var kept: Array[String] = []
		for p in DictUtil.to_string_array(creation_picks.get(key, [])):
			if opts.has(p) and kept.size() < DictUtil.to_int(entry.get("count", 1), 1):
				kept.append(p)
		if kept.is_empty() and opts.size() == DictUtil.to_int(entry.get("count", 1), 1):
			kept = opts.duplicate()
		creation_picks[key] = kept
	for key: Variant in creation_picks.keys():
		if not keys.has(str(key)):
			creation_picks.erase(key)
	return entries


## A LevelUpDraft over the creation choices (labels, descriptions, toggling).
func creation_draft(content: Dictionary = {}) -> LevelUpDraft:
	var d := LevelUpDraft.new({"choices": creation_choices(content)}, build_sheet_without_choices(), content)
	d.choice_picks = creation_picks
	return d


## Picks / unpicks an option of a creation choice (see LevelUpDraft.toggle_choice).
func toggle_creation_choice(entry: Dictionary, option: String, on: bool) -> bool:
	var d := LevelUpDraft.new({"choices": [entry]}, null)
	d.choice_picks = creation_picks
	return d.toggle_choice(entry, option, on)


## {"id", "name", "description"} of the subclass a new character starts with
## (cleric, sorcerer, warlock), else {}.
func subclass_info() -> Dictionary:
	if class_def == null or not class_def.has_subclass() or class_def.subclass_level > 1:
		return {}
	return {"id": class_def.subclass_id, "name": class_def.subclass_name, "description": class_def.subclass_description}


## The `choices` CharacterBuilder.create takes, from creation_picks.
func creation_answers() -> Dictionary:
	var out := {}
	var feature_options := {}
	for entry in creation_choices():
		var picked := DictUtil.to_string_array(creation_picks.get(LevelUpDraft.choice_key(entry), []))
		match str(entry.get("type", "")):
			LevelUp.CHOICE_SUBCLASS, LevelUp.CHOICE_FIGHTING_STYLE:
				if not picked.is_empty():
					out[str(entry["type"])] = picked[0]
			LevelUp.CHOICE_FEATURE_OPTION:
				if not picked.is_empty():
					feature_options[str(entry.get("feature", ""))] = picked[0]
			_:
				if picked.size() == DictUtil.to_int(entry.get("count", 1), 1):
					out[str(entry["type"])] = picked  # incomplete answers are left to the defaults
	if not feature_options.is_empty():
		out["feature_options"] = feature_options
	return out


## Picks every creation choice that is still open: modelled options first.
func auto_choose() -> void:
	var d := creation_draft()
	for entry in d.choice_entries():
		d.fill_choice(entry)
	creation_picks = d.choice_picks


func _picked_skills() -> Array[int]:
	var picked: Array[int] = []
	if class_def == null:
		return picked
	for s in skills:
		if class_def.skill_choices.has(s) and picked.size() < class_def.skill_choice_count:
			picked.append(s)
	return picked


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
	out.append_array(score_problems())
	if class_def != null and skills.size() != class_def.skill_choice_count:
		out.append("Choose %d skills (%d chosen)." % [class_def.skill_choice_count, skills.size()])
	if class_def != null:
		var d := creation_draft()
		for entry in d.choice_entries():
			var count := d.choice_count(entry)
			if d.picks_for(entry).size() != count:
				out.append("Choose %d: %s (%d chosen)." % [count, d.choice_title(entry), d.picks_for(entry).size()])
	return out


## The ability-score part of problems() for the current method.
func score_problems() -> Array[String]:
	var out: Array[String] = []
	match method:
		METHOD_POINT_BUY:
			if not is_fully_assigned():
				out.append("Choose every score.")
			var remaining := point_buy_remaining()
			if point_buy_spent() < 0:
				out.append("Point-buy scores must be %d-%d." % [POINT_BUY_MIN, POINT_BUY_MAX])
			elif remaining < 0:
				out.append("Point buy: %d points over the %d-point budget." % [-remaining, AbilityScores.POINT_BUY_BUDGET])
		METHOD_ROLL:
			if rolled_values.size() != Ability.COUNT:
				out.append("Roll your scores.")
			elif not is_fully_assigned():
				out.append("Assign every rolled score.")
			elif not _assignment_matches_pool():
				out.append("Use each rolled value once.")
		_:
			if not is_fully_assigned():
				out.append("Assign every standard-array score.")
			elif not _assignment_matches_pool():
				out.append("Use each standard-array value once.")
	return out


func _assignment_matches_pool() -> bool:
	var mine: Array[int] = []
	mine.assign(assigned)
	mine.sort()
	var pool := score_pool()
	pool.sort()
	return mine == pool


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
	return CharacterBuilder.create(character_name.strip_edges(), class_def, ancestry, base_scores(), _picked_skills(),
		null, {}, creation_answers())


## The sheet without the creation answers (defaults), for labels and previews
## that must not recurse into creation_choices.
func build_sheet_without_choices() -> CharacterSheet:
	if class_def == null:
		return null
	return CharacterBuilder.create(character_name.strip_edges(), class_def, ancestry, base_scores(), _picked_skills())


## Numbers for the live preview: {"hp", "ac", "speed", "attack_name", "to_hit",
## "damage", "damage_type" (first attack), "scores": Array[int] after ancestry
## bonuses, "armor": equipped armor + shield text, "attacks": Array[String]
## (every attack: melee, thrown and ranged with ranges), "spells":
## Array[String] (prepared, cantrips first; unsupported ones marked),
## "slots": String, "features": Array[String], "kit": Array[String] (carried
## items with quantities), "gold": int}. {} without a class.
func preview(content: Dictionary = {}) -> Dictionary:
	var sheet := build_sheet()
	if sheet == null:
		return {}
	var c := ContentLoader.resolve(content)
	var attack: Dictionary = sheet.attacks[0] if not sheet.attacks.is_empty() else sheet.unarmed_strike()
	var final_scores: Array[int] = []
	for i in range(Ability.COUNT):
		final_scores.append(sheet.abilities.get_score(i))
	var attacks: Array[String] = []
	for a in sheet.attacks:
		attacks.append(CharacterDraft.attack_text(a))
	if sheet.attacks.is_empty():
		attacks.append(CharacterDraft.attack_text(sheet.unarmed_strike()))
	var spells: Array[String] = []
	var spell_defs: Dictionary = c["spells"]
	var prepared: Array[SpellDefinition] = []
	for id in sheet.spells_prepared:
		if spell_defs.has(id):
			var sd: SpellDefinition = spell_defs[id]
			prepared.append(sd)
	prepared.sort_custom(func(a: SpellDefinition, b: SpellDefinition) -> bool:
		return a.level < b.level or (a.level == b.level and a.display_name < b.display_name))
	for sd in prepared:
		var text := "%s (%s)" % [sd.display_name, "cantrip" if sd.level == 0 else "level %d" % sd.level]
		if not sd.is_supported():
			text += " [not castable yet]"
		spells.append(text)
	var slot_parts: PackedStringArray = []
	for i in range(sheet.spell_slots_max.size()):
		if sheet.spell_slots_max[i] > 0:
			slot_parts.append("%d x level %d" % [sheet.spell_slots_max[i], i + 1])
	var features: Array[String] = []
	for f in sheet.features:
		features.append(ClientState.feature_name(f))
	var kit: Array[String] = []
	for entry in sheet.inventory:
		var id := str(entry["item"])
		if id == CharacterSheet.GOLD_ITEM:
			continue
		var item := CharacterSheet.item_def(id, c)
		var label := item.display_name if item != null else id.replace("_", " ").capitalize()
		var qty := DictUtil.to_int(entry["qty"], 1)
		if sheet.equipped_count(id) > 0:
			label += " (equipped)"
		kit.append(ClientState.quantity_text(label, qty))
	var armor_parts: PackedStringArray = []
	var armor_id := sheet.equipped_item(CharacterSheet.SLOT_ARMOR)
	if not armor_id.is_empty():
		var armor_def := CharacterSheet.item_def(armor_id, c)
		armor_parts.append(armor_def.display_name if armor_def != null else armor_id)
	elif sheet.armor_base > 0:
		armor_parts.append("armor %d" % sheet.armor_base)
	else:
		armor_parts.append("no armor")
	if sheet.shield_bonus > 0:
		armor_parts.append("shield +%d" % sheet.shield_bonus)
	return {
		"hp": sheet.max_hp,
		"ac": sheet.armor_class(),
		"speed": sheet.speed,
		"attack_name": str(attack.get("name", "")),
		"to_hit": DictUtil.to_int(attack.get("to_hit", 0), 0),
		"damage": str(attack.get("damage", "")),
		"damage_type": str(attack.get("damage_type", "")),
		"scores": final_scores,
		"armor": ", ".join(armor_parts),
		"attacks": attacks,
		"spells": spells,
		"slots": ", ".join(slot_parts),
		"features": features,
		"kit": kit,
		"gold": sheet.gold(),
	}


## "Longbow (ranged 30/120 ft): +4, 1d8+2 piercing".
static func attack_text(a: Dictionary) -> String:
	var kind := str(a.get("kind", "melee"))
	var where := kind
	if Encounter.is_ranged_attack(a):
		var r := Encounter.attack_range_tiles(a)
		where = "%s %d/%d ft" % [kind, r[0] * GridMath.FEET_PER_TILE, r[1] * GridMath.FEET_PER_TILE]
	return "%s (%s): %+d, %s %s" % [str(a.get("name", "")), where, DictUtil.to_int(a.get("to_hit", 0), 0),
		str(a.get("damage", "")), str(a.get("damage_type", ""))]

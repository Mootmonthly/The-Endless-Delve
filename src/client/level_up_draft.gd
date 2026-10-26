class_name LevelUpDraft
extends RefCounted
## The level-up screen's choices and their validation, without any UI: one
## LEVEL_UP_AVAILABLE offer (LevelUp.choices: new_level, hp, asi,
## cantrips_to_learn, spells_to_learn, spell_options, prepared_count,
## prepare_options, features_gained) answered with to_choices(), the `choices`
## of the level_up intent: {"hp": "average"|"roll", "asi"?: {"STR": 2},
## "learn_cantrips": [...], "learn_spells": [...], "prepared"?: [...]}.
##
## Mirrors LevelUp.apply's rules so Confirm can stay disabled until the server
## would accept: exact learn counts, ASI +2 to one ability or +1 to two (a
## score at 20 cannot be picked; the rise is capped at 20), at most
## prepared_count prepared leveled spells. Spells the rules engine cannot cast
## yet (effect "unsupported") are offered greyed out: they can only be picked
## when there are not enough castable options to fill the count.

const HP_AVERAGE := "average"
const HP_ROLL := "roll"
const MAX_SCORE := 20
const ASI_NONE := 0
const ASI_PLUS_TWO := 1  # +2 to one ability
const ASI_SPLIT := 2  # +1 to two abilities

var offer: Dictionary = {}
var sheet: CharacterSheet = null
var content: Dictionary = {}  # {} = ContentLoader.cache()

var hp_mode: String = HP_AVERAGE
var asi_mode: int = ASI_NONE
## Ability.Type values picked for the ASI (one for +2, two for +1 each).
var asi_abilities: Array[int] = []
var learn_cantrips: Array[String] = []
var learn_spells: Array[String] = []
var prepared: Array[String] = []


func _init(p_offer: Dictionary = {}, p_sheet: CharacterSheet = null, p_content: Dictionary = {}) -> void:
	offer = p_offer
	sheet = p_sheet
	content = p_content
	if is_prepared_caster() and sheet != null:
		for id in sheet.spells_prepared:
			var s := _spell(id)
			if s != null and s.level >= 1 and prepare_options().has(id) and prepared.size() < prepared_count():
				prepared.append(id)


# --- offer ------------------------------------------------------------------------

func new_level() -> int:
	return DictUtil.to_int(offer.get("new_level", 0), 0)


func hit_die() -> int:
	var hp: Dictionary = offer.get("hp", {})
	return DictUtil.to_int(hp.get("die", sheet.hit_die if sheet != null else 8), 8)


func con_mod() -> int:
	var hp: Dictionary = offer.get("hp", {})
	return DictUtil.to_int(hp.get("con_mod", 0), 0)


## HP gained with the average option (already includes CON).
func average_hp() -> int:
	var hp: Dictionary = offer.get("hp", {})
	return DictUtil.to_int(hp.get("average", 1), 1)


func may_roll() -> bool:
	var hp: Dictionary = offer.get("hp", {})
	return DictUtil.to_bool(hp.get("may_roll", true), true)


func asi_offered() -> bool:
	return DictUtil.to_bool(offer.get("asi", false), false)


func cantrips_needed() -> int:
	return DictUtil.to_int(offer.get("cantrips_to_learn", 0), 0)


func spells_needed() -> int:
	return DictUtil.to_int(offer.get("spells_to_learn", 0), 0)


func prepared_count() -> int:
	return DictUtil.to_int(offer.get("prepared_count", 0), 0)


func is_prepared_caster() -> bool:
	return prepared_count() > 0


func features_gained() -> Array[String]:
	return DictUtil.to_string_array(offer.get("features_gained", []))


## Cantrip options (spell_options with level 0), in offer order.
func cantrip_options() -> Array[String]:
	return _options(true)


## Leveled spell options, in offer order.
func spell_options() -> Array[String]:
	return _options(false)


## Leveled spells that may be prepared: the offer's prepare_options plus the
## spells being learned now.
func prepare_options() -> Array[String]:
	var out := DictUtil.to_string_array(offer.get("prepare_options", []))
	for id in learn_spells:
		if not out.has(id):
			out.append(id)
	return out


func _options(cantrips: bool) -> Array[String]:
	var out: Array[String] = []
	for id in DictUtil.to_string_array(offer.get("spell_options", [])):
		var s := _spell(id)
		if s != null and (s.level == 0) == cantrips:
			out.append(id)
	return out


func _spell(id: String) -> SpellDefinition:
	var spells: Dictionary = ContentLoader.resolve(content)["spells"]
	if not spells.has(id):
		return null
	var s: SpellDefinition = spells[id]
	return s


func spell_name(id: String) -> String:
	var s := _spell(id)
	return s.display_name if s != null else id.replace("_", " ").capitalize()


func spell_level(id: String) -> int:
	var s := _spell(id)
	return s.level if s != null else 0


func is_supported(id: String) -> bool:
	var s := _spell(id)
	return s != null and s.is_supported()


## Whether an unsupported option may be picked: only when the castable
## options cannot fill the count.
func may_pick(id: String, cantrips: bool) -> bool:
	if is_supported(id):
		return true
	var options := cantrip_options() if cantrips else spell_options()
	var supported := 0
	for o in options:
		if is_supported(o):
			supported += 1
	return supported < (cantrips_needed() if cantrips else spells_needed())


# --- edits ------------------------------------------------------------------------

func set_hp_mode(m: String) -> void:
	if m == HP_ROLL and may_roll():
		hp_mode = HP_ROLL
	else:
		hp_mode = HP_AVERAGE


## +2 to one ability.
func set_asi_plus_two(ability: int) -> void:
	asi_mode = ASI_PLUS_TWO
	asi_abilities.clear()
	if Ability.is_valid(ability):
		asi_abilities.append(ability)


## +1 to two different abilities (pass -1 for a not-yet-chosen one).
func set_asi_split(first: int, second: int) -> void:
	asi_mode = ASI_SPLIT
	asi_abilities.clear()
	for a in [first, second]:
		if Ability.is_valid(a):
			asi_abilities.append(a)


## Score of an ability now (before the ASI).
func current_score(ability: int) -> int:
	return sheet.abilities.get_score(ability) if sheet != null else 10


## Whether an ability can take part in the ASI (below 20).
func can_raise(ability: int) -> bool:
	return Ability.is_valid(ability) and current_score(ability) < MAX_SCORE


## Scores after the chosen ASI (capped at 20), by Ability.Type.
func preview_scores() -> Array[int]:
	var out: Array[int] = []
	for i in range(Ability.COUNT):
		out.append(current_score(i))
	var raises := _raises()
	for a: int in raises.keys():
		out[a] = mini(MAX_SCORE, out[a] + raises[a])
	return out


func _raises() -> Dictionary:
	var out := {}
	if not asi_offered():
		return out
	if asi_mode == ASI_PLUS_TWO and asi_abilities.size() == 1:
		out[asi_abilities[0]] = 2
	elif asi_mode == ASI_SPLIT and asi_abilities.size() == 2 and asi_abilities[0] != asi_abilities[1]:
		out[asi_abilities[0]] = 1
		out[asi_abilities[1]] = 1
	return out


## Adds / removes a spell to learn (cantrip or leveled by the spell's level).
## false when not allowed (not an option, greyed out, or the count is full).
func toggle_learn(id: String, on: bool) -> bool:
	var s := _spell(id)
	if s == null:
		return false
	var cantrip := s.level == 0
	var list := learn_cantrips if cantrip else learn_spells
	var options := cantrip_options() if cantrip else spell_options()
	if not on:
		list.erase(id)
		if not cantrip:
			prepared.erase(id)
		return true
	if list.has(id):
		return true
	if not options.has(id) or not may_pick(id, cantrip):
		return false
	if list.size() >= (cantrips_needed() if cantrip else spells_needed()):
		return false
	list.append(id)
	return true


func toggle_prepared(id: String, on: bool) -> bool:
	if not on:
		prepared.erase(id)
		return true
	if prepared.has(id):
		return true
	if not prepare_options().has(id) or prepared.size() >= prepared_count():
		return false
	prepared.append(id)
	return true


# --- validation ------------------------------------------------------------------

## Every reason the choices would be rejected ([] when valid).
func problems() -> Array[String]:
	var out: Array[String] = []
	if offer.is_empty():
		out.append("No level-up is pending.")
		return out
	if asi_offered():
		var raises := _raises()
		if raises.is_empty():
			out.append("Choose an ability score improvement: +2 to one ability or +1 to two.")
		for a: int in raises.keys():
			if not can_raise(a):
				out.append("%s is already %d." % [Ability.abbreviation(a), MAX_SCORE])
	if learn_cantrips.size() != cantrips_needed():
		out.append("Learn %d cantrip(s) (%d chosen)." % [cantrips_needed(), learn_cantrips.size()])
	if learn_spells.size() != spells_needed():
		out.append("Learn %d spell(s) (%d chosen)." % [spells_needed(), learn_spells.size()])
	if is_prepared_caster() and prepared.size() > prepared_count():
		out.append("Prepare at most %d spells." % prepared_count())
	return out


func is_valid() -> bool:
	return problems().is_empty()


## The level_up intent's "choices".
func to_choices() -> Dictionary:
	var d := {"hp": hp_mode, "learn_cantrips": learn_cantrips.duplicate(), "learn_spells": learn_spells.duplicate()}
	var raises := _raises()
	if not raises.is_empty():
		var asi := {}
		for a: int in raises.keys():
			asi[Ability.abbreviation(a)] = raises[a]
		d["asi"] = asi
	if is_prepared_caster():
		d["prepared"] = prepared.duplicate()
	return d


## Average HP and the first valid options: +2 to the class's first primary
## ability below 20 (else the highest score below 20, else +1 to two), the
## first castable cantrips / spells, current preparation kept (plus learned
## spells while there is room). What the smoke bot answers with.
static func first_valid(p_offer: Dictionary, p_sheet: CharacterSheet, p_content: Dictionary = {}) -> LevelUpDraft:
	var d := LevelUpDraft.new(p_offer, p_sheet, p_content)
	if d.asi_offered():
		var pick := -1
		var cls := p_sheet.class_definition(p_content) if p_sheet != null else null
		if cls != null:
			for a in cls.primary_abilities:
				if d.current_score(a) <= MAX_SCORE - 2:
					pick = a
					break
		if pick < 0:
			var best := -1
			for a in range(Ability.COUNT):
				if d.current_score(a) <= MAX_SCORE - 2 and d.current_score(a) > best:
					best = d.current_score(a)
					pick = a
		if pick >= 0:
			d.set_asi_plus_two(pick)
		else:
			var below: Array[int] = []
			for a in range(Ability.COUNT):
				if d.can_raise(a):
					below.append(a)
			d.set_asi_split(below[0] if below.size() > 0 else -1, below[1] if below.size() > 1 else -1)
	for pass_supported: bool in [true, false]:
		for id in d.cantrip_options():
			if d.learn_cantrips.size() < d.cantrips_needed() and (d.is_supported(id) or not pass_supported):
				d.toggle_learn(id, true)
		for id in d.spell_options():
			if d.learn_spells.size() < d.spells_needed() and (d.is_supported(id) or not pass_supported):
				d.toggle_learn(id, true)
	for id in d.learn_spells:
		d.toggle_prepared(id, true)
	return d

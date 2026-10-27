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
##
## Progression choices (offer "choices": subclass, fighting_style, expertise,
## invocations, metamagic, feature_option, skills) are answered in
## `choice_picks` (choice_key(entry) -> Array[String]) and always sent
## explicitly by to_choices(); a choice with a single option (the SRD
## subclass) starts picked. option_label / option_description /
## option_implemented read data/features, fighting_styles, invocations and
## metamagic records (and the class's subclass text) for the screen;
## feature_cards() describes the features gained ("implemented" or "not yet
## modelled").
##
## Spell choices (magical_secrets, mystic_arcanum, tome_cantrips,
## ritual_book, spell_mastery, signature_spells) label their options with the
## spell's name and level; damage_type options are damage types. A choice
## with "requires" (tome_cantrips needs Pact of the Tome, ritual_book needs
## Book of Ancient Secrets) may stay empty while that boon / invocation is
## neither on the sheet nor picked in this draft (requirement_met), and is
## then sent as []; Spell Mastery needs one spell of each level of its
## "per_level" ({"1": 1, "2": 1}).

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
## Progression answers: choice_key(entry) -> Array[String] of option ids.
var choice_picks: Dictionary = {}


func _init(p_offer: Dictionary = {}, p_sheet: CharacterSheet = null, p_content: Dictionary = {}) -> void:
	offer = p_offer
	sheet = p_sheet
	content = p_content
	for entry in choice_entries():
		var opts := DictUtil.to_string_array(entry.get("options", []))
		var count := DictUtil.to_int(entry.get("count", 1), 1)
		if opts.size() == count:
			choice_picks[LevelUpDraft.choice_key(entry)] = opts.duplicate()
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


## The offer's progression choices (LevelUp.choices "choices"), in order.
func choice_entries() -> Array[Dictionary]:
	return DictUtil.to_dict_array(offer.get("choices", []))


## The key of a choice in choice_picks: its type, or "feature_option:<feature>".
static func choice_key(entry: Dictionary) -> String:
	var kind := str(entry.get("type", ""))
	if kind == LevelUp.CHOICE_FEATURE_OPTION:
		return "%s:%s" % [kind, str(entry.get("feature", ""))]
	return kind


func choice_count(entry: Dictionary) -> int:
	return DictUtil.to_int(entry.get("count", 1), 1)


## The options picked for a choice (copy).
func picks_for(entry: Dictionary) -> Array[String]:
	var out: Array[String] = []
	out.assign(choice_picks.get(LevelUpDraft.choice_key(entry), []))
	return out


## Picks / unpicks an option of a choice. A one-option-count choice swaps its
## pick; others fill up to their count (false when full or not an option).
func toggle_choice(entry: Dictionary, option: String, on: bool) -> bool:
	var key := LevelUpDraft.choice_key(entry)
	var opts := DictUtil.to_string_array(entry.get("options", []))
	var picked := picks_for(entry)
	if not on:
		picked.erase(option)
		choice_picks[key] = picked
		return true
	if not opts.has(option):
		return false
	if picked.has(option):
		return true
	if choice_count(entry) == 1:
		picked = [option] as Array[String]
	elif picked.size() >= choice_count(entry):
		return false
	else:
		picked.append(option)
	choice_picks[key] = picked
	return true


## "Fighting style", "Expertise", "Dragon Ancestor", ... (a choice's heading).
func choice_title(entry: Dictionary) -> String:
	match str(entry.get("type", "")):
		LevelUp.CHOICE_SUBCLASS:
			var cls := _class()
			return cls.subclass_name if cls != null and not cls.subclass_name.is_empty() else "Subclass"
		LevelUp.CHOICE_FIGHTING_STYLE:
			return "Fighting style"
		LevelUp.CHOICE_EXPERTISE:
			return "Expertise"
		LevelUp.CHOICE_INVOCATIONS:
			return "Eldritch invocations"
		LevelUp.CHOICE_METAMAGIC:
			return "Metamagic"
		LevelUp.CHOICE_SKILLS:
			return "Skill proficiencies"
		LevelUp.CHOICE_FEATURE_OPTION:
			return _record_name("features", str(entry.get("feature", "")))
		LevelUp.CHOICE_MAGICAL_SECRETS:
			return "Magical Secrets"
		LevelUp.CHOICE_MYSTIC_ARCANUM:
			return "Mystic Arcanum (%s level)" % ClientState.ordinal(DictUtil.to_int(entry.get("spell_level", 6), 6))
		LevelUp.CHOICE_DAMAGE_TYPE:
			return "Fiendish Resilience: damage type"
		LevelUp.CHOICE_TOME_CANTRIPS:
			return "Book of Shadows cantrips (Pact of the Tome)"
		LevelUp.CHOICE_RITUAL_BOOK:
			return "Book of Ancient Secrets rituals"
		LevelUp.CHOICE_SPELL_MASTERY:
			return "Spell Mastery (one 1st- and one 2nd-level spell)"
		LevelUp.CHOICE_SIGNATURE_SPELLS:
			return "Signature Spells"
	return str(entry.get("type", "")).capitalize()


## The choice types whose options are spell ids.
const SPELL_CHOICES: Array[String] = [LevelUp.CHOICE_MAGICAL_SECRETS, LevelUp.CHOICE_MYSTIC_ARCANUM, LevelUp.CHOICE_TOME_CANTRIPS,
	LevelUp.CHOICE_RITUAL_BOOK, LevelUp.CHOICE_SPELL_MASTERY, LevelUp.CHOICE_SIGNATURE_SPELLS]


## Whether a "requires" choice applies: its boon / invocation is on the sheet
## or picked in this draft (true for choices without "requires").
func requirement_met(entry: Dictionary) -> bool:
	var req := str(entry.get("requires", ""))
	if req.is_empty():
		return true
	if sheet != null and (sheet.has_feature(req) or sheet.invocations.has(req)):
		return true
	for other in choice_entries():
		if other == entry:
			continue
		if picks_for(other).has(req):
			return true
	return false


## A line under a choice's heading ("" when none): why it may stay empty, or
## the per-level rule of Spell Mastery.
func choice_note(entry: Dictionary) -> String:
	if entry.has("requires") and not requirement_met(entry):
		return "Only if you pick %s." % _record_name("features" if str(entry["requires"]).begins_with("pact_") else "invocations", str(entry["requires"]))
	if str(entry.get("type", "")) == LevelUp.CHOICE_SPELL_MASTERY:
		return "Cast them at their lowest level without a slot."
	if str(entry.get("type", "")) == LevelUp.CHOICE_SIGNATURE_SPELLS:
		return "Each casts once per short rest at 3rd level without a slot."
	return ""


## Display name of an option.
func option_label(entry: Dictionary, option: String) -> String:
	match str(entry.get("type", "")):
		LevelUp.CHOICE_SUBCLASS:
			var cls := _class()
			if cls != null and cls.subclass_id == option and not cls.subclass_name.is_empty():
				return cls.subclass_name
		LevelUp.CHOICE_FIGHTING_STYLE:
			return _record_name("fighting_styles", option)
		LevelUp.CHOICE_INVOCATIONS:
			return _record_name("invocations", option)
		LevelUp.CHOICE_METAMAGIC:
			return _record_name("metamagic", option)
		LevelUp.CHOICE_EXPERTISE, LevelUp.CHOICE_SKILLS:
			var skill := Skill.from_string(option)
			return Skill.name_of(skill) if skill >= 0 else option.capitalize()
		LevelUp.CHOICE_FEATURE_OPTION:
			var full := _record_name("features", option)
			var prefix := _record_name("features", str(entry.get("feature", ""))) + ": "
			return full.trim_prefix(prefix) if full.begins_with(prefix) else full
	if SPELL_CHOICES.has(str(entry.get("type", ""))):
		var spell := _spell(option)
		if spell != null:
			var lvl := "cantrip" if spell.level == 0 else ClientState.ordinal(spell.level) + " level"
			return "%s (%s%s)" % [spell.display_name, lvl, ", ritual" if spell.ritual else ""]
	return option.replace("_", " ").capitalize()


## Rules text of an option ("" when the data has none).
func option_description(entry: Dictionary, option: String) -> String:
	match str(entry.get("type", "")):
		LevelUp.CHOICE_SUBCLASS:
			var cls := _class()
			return cls.subclass_description if cls != null and cls.subclass_id == option else ""
		LevelUp.CHOICE_FIGHTING_STYLE:
			return _record_text("fighting_styles", option)
		LevelUp.CHOICE_INVOCATIONS:
			return _record_text("invocations", option)
		LevelUp.CHOICE_METAMAGIC:
			var text := _record_text("metamagic", option)
			var cost := DictUtil.to_int(_record("metamagic", option).get("cost", 0), 0)
			return ("(%d sorcery point%s) " % [cost, "" if cost == 1 else "s"] + text) if cost > 0 else text
		LevelUp.CHOICE_FEATURE_OPTION:
			return _record_text("features", option)
		LevelUp.CHOICE_EXPERTISE:
			return "Double your proficiency bonus for checks with this skill."
		LevelUp.CHOICE_SKILLS:
			return "Gain proficiency in this skill."
		LevelUp.CHOICE_DAMAGE_TYPE:
			return "Resistance to %s damage (not from magical or silvered weapons)." % option
	return ""


## Whether the rules engine models an option (skills and expertise always).
func option_implemented(entry: Dictionary, option: String) -> bool:
	match str(entry.get("type", "")):
		LevelUp.CHOICE_FIGHTING_STYLE:
			return Features.IMPLEMENTED_FIGHTING_STYLES.has(option)
		LevelUp.CHOICE_INVOCATIONS:
			return Features.IMPLEMENTED_INVOCATIONS.has(option)
		LevelUp.CHOICE_METAMAGIC:
			return Features.IMPLEMENTED_METAMAGIC.has(option)
		LevelUp.CHOICE_FEATURE_OPTION:
			return Features.is_implemented(option)
	if SPELL_CHOICES.has(str(entry.get("type", ""))):
		return is_supported(option)
	return true


## Features gained at the new level for the screen's cards: [{"id", "name",
## "description", "implemented": bool, "subclass": bool}] (offer
## "features_detail", else "features_gained").
func feature_cards() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var detail := DictUtil.to_dict_array(offer.get("features_detail", []))
	if detail.is_empty():
		for f in features_gained():
			detail.append({"id": f, "implemented": Features.is_implemented(f), "subclass": false})
	for d in detail:
		var id := str(d.get("id", ""))
		out.append({"id": id, "name": _record_name("features", id), "description": _record_text("features", id),
			"implemented": DictUtil.to_bool(d.get("implemented", Features.is_implemented(id)), false),
			"subclass": DictUtil.to_bool(d.get("subclass", false), false)})
	return out


## Learnable leveled spells grouped by spell level: level -> Array[String].
func spell_options_by_level() -> Dictionary:
	var out := {}
	for id in spell_options():
		var lvl := spell_level(id)
		if not out.has(lvl):
			out[lvl] = [] as Array[String]
		var list: Array[String] = out[lvl]
		list.append(id)
	return out


func _class() -> ClassDefinition:
	return sheet.class_definition(ContentLoader.resolve(content)) if sheet != null else null


func _record(kind: String, id: String) -> Dictionary:
	var records: Variant = ContentLoader.resolve(content).get(kind, {})
	if typeof(records) != TYPE_DICTIONARY or not (records as Dictionary).has(id):
		return {}
	var rec: Variant = (records as Dictionary)[id]
	return rec if typeof(rec) == TYPE_DICTIONARY else {}


func _record_name(kind: String, id: String) -> String:
	var rec := _record(kind, id)
	var n := str(rec.get("display_name", ""))
	return n if not n.is_empty() else ClientState.feature_name(id)


func _record_text(kind: String, id: String) -> String:
	return str(_record(kind, id).get("description", ""))


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
	for entry in choice_entries():
		var picked := picks_for(entry)
		var opts := DictUtil.to_string_array(entry.get("options", []))
		var count := choice_count(entry)
		var optional := entry.has("requires") and not requirement_met(entry)
		if picked.size() != count and not (optional and picked.is_empty()):
			out.append("Choose %d: %s (%d chosen)." % [count, choice_title(entry), picked.size()])
		for p in picked:
			if not opts.has(p):
				out.append("%s is not an option for %s." % [p, choice_title(entry)])
		var per_level_v: Variant = entry.get("per_level", {})
		if typeof(per_level_v) == TYPE_DICTIONARY and picked.size() == count:
			var want: Dictionary = per_level_v
			var have := {}
			for p in picked:
				var key := str(spell_level(p))
				have[key] = DictUtil.to_int(have.get(key, 0), 0) + 1
			for key: Variant in want.keys():
				if DictUtil.to_int(have.get(str(key), 0), 0) != DictUtil.to_int(want[key], 0):
					out.append("%s: pick %d spell(s) of level %s." % [choice_title(entry), DictUtil.to_int(want[key], 0), str(key)])
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
	var feature_options := {}
	for entry in choice_entries():
		var picked := picks_for(entry)
		if entry.has("requires") and not requirement_met(entry):
			picked = [] as Array[String]
		match str(entry.get("type", "")):
			LevelUp.CHOICE_SUBCLASS, LevelUp.CHOICE_FIGHTING_STYLE:
				d[str(entry["type"])] = picked[0] if not picked.is_empty() else ""
			LevelUp.CHOICE_FEATURE_OPTION:
				feature_options[str(entry.get("feature", ""))] = picked[0] if not picked.is_empty() else ""
			LevelUp.CHOICE_DAMAGE_TYPE:
				d[str(entry["type"])] = picked[0] if not picked.is_empty() else ""
			_:
				d[str(entry["type"])] = picked
	if not feature_options.is_empty():
		d["feature_options"] = feature_options
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
	for entry in d.choice_entries():
		if not entry.has("requires"):
			d.fill_choice(entry)
	for entry in d.choice_entries():
		if entry.has("requires") and d.requirement_met(entry):
			d.fill_choice(entry)
	return d


## Fills a choice up to its count: modelled options first, in offer order
## (Spell Mastery: the offer's first two options, a valid pair).
func fill_choice(entry: Dictionary) -> void:
	var opts := DictUtil.to_string_array(entry.get("options", []))
	if typeof(entry.get("per_level")) == TYPE_DICTIONARY:
		for o in opts.slice(0, choice_count(entry)):
			toggle_choice(entry, o, true)
		return
	for pass_implemented: bool in [true, false]:
		for o in opts:
			if picks_for(entry).size() >= choice_count(entry):
				return
			if option_implemented(entry, o) == pass_implemented or not pass_implemented:
				toggle_choice(entry, o, true)

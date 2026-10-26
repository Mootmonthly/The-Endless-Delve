class_name LevelUp
extends RefCounted
## The interactive level-up flow. CharacterSheet.gain_xp only banks XP; when
## sheet.pending_levels() > 0 the player picks from choices() and the server
## calls apply() once per level.
##
## choices(sheet, content) ->
## {"new_level": int, "levels_pending": int,
##  "hp": {"average": int, "may_roll": true, "die": int, "con_mod": int,
##         "bonus": int (per-level hp from features, e.g. Draconic Resilience)},
##  "asi": bool, "new_spell_slots": Array[int] (max slots per spell level at the new level),
##  "cantrips_to_learn": int, "spells_to_learn": int,
##  "spell_options": Array[String] (class spells not known yet, level <= highest
##                   castable slot at the new level; cantrips included; plus a
##                   subclass's expanded spell list),
##  "prepared_count": int (prepared casters: casting mod + new level, half casters
##                    + half the level, min 1; else 0; always-prepared subclass
##                    spells do not count),
##  "prepare_options": Array[String] (leveled spells that may be prepared, before
##                     this level's learning; a wizard's spellbook, a cleric's list),
##  "features_gained": Array[String] (class + subclass feature ids),
##  "features_detail": [{"id", "implemented": bool, "subclass": bool}],
##  "skills_to_choose": int,
##  "choices": [{"type": "subclass"|"fighting_style"|"expertise"|"invocations"|
##               "metamagic"|"feature_option"|"skills", "count": int,
##               "options": Array[String], "default": Array[String] (the first
##               count options), "feature": id (feature_option only)}]}
## Every entry of "choices" is answered in apply(); an answer that is omitted
## entirely (key absent) takes the entry's "default" (its first `count`
## options) so clients that predate a choice type keep working; a given answer
## must be valid. Option values: subclass,
## style, invocation, metamagic and option-feature ids; skills as upper-case
## keys ("STEALTH"). feature_option covers hunters_prey, dragon_ancestor,
## circle_spells (circle_of_the_land_<terrain>) and pact_boon.
##
## apply(sheet, made, content, rng) with made =
## {"hp": "average"|"roll", "asi": {"STR": 2} or {"STR": 1, "DEX": 1},
##  "learn_cantrips": [ids], "learn_spells": [ids], "prepared": [ids],
##  "subclass": id, "fighting_style": id, "expertise": [skills], "skills": [skills],
##  "invocations": [ids], "metamagic": [ids], "feature_options": {feature: option}}
## returns "" on success, else an error and the sheet is unchanged. Learning
## must pick exactly cantrips_to_learn / spells_to_learn options; "prepared"
## (prepared casters only, optional: omitted keeps the current preparation)
## lists at most prepared_count leveled spells. An ASI is required exactly when
## offered: +2 to one ability or +1 to two; a score cannot exceed 20 (the
## excess is lost) and an ability already at 20 cannot be picked. A CON
## increase raises max hp retroactively (SRD). Each "choices" entry needs
## exactly `count` distinct options. Subclass spells marked always_prepared
## (domain, oath, circle spells of the chosen land) are added to the known,
## prepared and always_prepared lists automatically.

const MAX_SCORE := 20
const CHOICE_SUBCLASS := "subclass"
const CHOICE_FIGHTING_STYLE := "fighting_style"
const CHOICE_EXPERTISE := "expertise"
const CHOICE_INVOCATIONS := "invocations"
const CHOICE_METAMAGIC := "metamagic"
const CHOICE_FEATURE_OPTION := "feature_option"
const CHOICE_SKILLS := "skills"
const BONUS_PROFICIENCY_SKILLS := 3  # College of Lore


static func choices(sheet: CharacterSheet, content: Dictionary = {}) -> Dictionary:
	var c := ContentLoader.resolve(content)
	var cls := sheet.class_definition(c)
	var new_level := mini(CharacterSheet.MAX_LEVEL, sheet.level + 1)
	var con_mod := sheet.ability_modifier(Ability.Type.CON)
	var asi_levels: Array[int] = cls.asi_levels if cls != null else ClassDefinition.DEFAULT_ASI_LEVELS
	var new_slots: Array[int] = cls.slots_for_level(new_level) if cls != null else sheet.spell_slots_max.duplicate()
	var max_slot := 0
	for i in range(new_slots.size()):
		if new_slots[i] > 0:
			max_slot = i + 1
	var cantrip_options: Array[String] = []
	var spell_options: Array[String] = []
	var options: Array[String] = []
	var prepare_options: Array[String] = []
	var cantrips_to_learn := 0
	var spells_to_learn := 0
	var prepared_count := 0
	var gained := LevelUp.gained_features(sheet, cls, new_level)
	var features_gained: Array[String] = []
	var detail: Array = []
	for entry in gained:
		features_gained.append(str(entry["id"]))
		detail.append({"id": entry["id"], "implemented": Features.is_implemented(str(entry["id"])), "subclass": entry["subclass"]})
	if cls != null:
		var learnable: Array[String] = cls.spell_list.duplicate()
		if cls.has_subclass() and cls.subclass_spells_mode == "expanded_list" and (sheet.subclass_id == cls.subclass_id or new_level >= cls.subclass_level):
			for s in cls.all_subclass_spells():
				if not learnable.has(s):
					learnable.append(s)
		for spell_id in learnable:
			var spell := LevelUp._spell(spell_id, c)
			if spell == null:
				continue
			if spell.level == 0 or spell.level <= max_slot:
				if not sheet.spells_known.has(spell_id):
					options.append(spell_id)
					if spell.level == 0:
						cantrip_options.append(spell_id)
					else:
						spell_options.append(spell_id)
		cantrips_to_learn = maxi(0, ClassDefinition.table_value(cls.cantrips_known_table, new_level) - ClassDefinition.table_value(cls.cantrips_known_table, sheet.level))
		if features_gained.has("bonus_cantrip"):
			cantrips_to_learn += 1
		if not cls.spells_known_table.is_empty():
			spells_to_learn = maxi(0, ClassDefinition.table_value(cls.spells_known_table, new_level) - ClassDefinition.table_value(cls.spells_known_table, sheet.level))
		elif cls.spellbook_learn_per_level > 0:
			spells_to_learn = cls.spellbook_learn_per_level
		cantrips_to_learn = mini(cantrips_to_learn, cantrip_options.size())
		spells_to_learn = mini(spells_to_learn, spell_options.size())
		if cls.prepares_spells and cls.spellcasting_ability >= 0:
			var casting_mod := sheet.ability_modifier(cls.spellcasting_ability)
			var levels := floori(new_level / 2.0) if cls.is_half_caster() else new_level
			prepared_count = maxi(1, casting_mod + levels) if max_slot > 0 else 0
			prepare_options = LevelUp._prepare_options(sheet, cls, c, max_slot)
	var choice_list := LevelUp._choice_entries(sheet, cls, new_level, features_gained, c)
	var skills_to_choose := 0
	for entry: Dictionary in choice_list:
		if entry["type"] == CHOICE_SKILLS:
			skills_to_choose = DictUtil.to_int(entry["count"])
	return {
		"new_level": new_level,
		"levels_pending": sheet.pending_levels(),
		"hp": {"average": maxi(1, floori(sheet.hit_die / 2.0) + 1 + con_mod), "may_roll": true, "die": sheet.hit_die, "con_mod": con_mod, "bonus": sheet.hp_bonus_per_level()},
		"asi": asi_levels.has(new_level),
		"new_spell_slots": new_slots,
		"cantrips_to_learn": cantrips_to_learn,
		"spells_to_learn": spells_to_learn,
		"spell_options": options,
		"prepared_count": prepared_count,
		"prepare_options": prepare_options,
		"features_gained": features_gained,
		"features_detail": detail,
		"skills_to_choose": skills_to_choose,
		"choices": choice_list,
	}


## Features gained on reaching `level`: the class's, then the subclass's (when
## the subclass is already chosen or chosen at this level; a subclass chosen
## late, e.g. by a sheet from before subclasses existed, brings the features of
## every level up to `level`), skipping ids the sheet has. [{"id", "subclass": bool}].
static func gained_features(sheet: CharacterSheet, cls: ClassDefinition, level: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if cls == null:
		return out
	var seen: Array[String] = []
	for f in cls.features_at(level):
		if not sheet.features.has(f) and not seen.has(f):
			seen.append(f)
			out.append({"id": f, "subclass": false})
	if not cls.has_subclass():
		return out
	var first := level
	if sheet.subclass_id.is_empty() and level >= cls.subclass_level:
		first = cls.subclass_level
	elif sheet.subclass_id != cls.subclass_id:
		return out
	for lvl in range(first, level + 1):
		for f in cls.subclass_features_at(lvl):
			if not sheet.features.has(f) and not seen.has(f):
				seen.append(f)
				out.append({"id": f, "subclass": true})
	return out


## The "choices" entries for reaching `level` (see choices()).
static func _choice_entries(sheet: CharacterSheet, cls: ClassDefinition, level: int, gained: Array[String], content: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if cls == null:
		return out
	if cls.has_subclass() and sheet.subclass_id.is_empty() and level >= cls.subclass_level:
		out.append({"type": CHOICE_SUBCLASS, "count": 1, "options": [cls.subclass_id]})
	if gained.has("fighting_style") or gained.has("additional_fighting_style"):
		var styles: Array[String] = []
		for s in cls.fighting_style_options:
			if not sheet.fighting_styles.has(s):
				styles.append(s)
		if not styles.is_empty():
			out.append({"type": CHOICE_FIGHTING_STYLE, "count": 1, "options": styles})
	var expertise := DictUtil.to_int(cls.expertise_levels.get(level, 0), 0)
	if expertise > 0:
		var skills: Array[String] = []
		for skill in sheet.proficient_skills:
			if not sheet.expertise_skills.has(skill):
				skills.append(Skill.key_of(skill))
		skills.sort()
		if not skills.is_empty():
			out.append({"type": CHOICE_EXPERTISE, "count": mini(expertise, skills.size()), "options": skills})
	var invocations := ClassDefinition.table_value(cls.invocations_known_table, level) - ClassDefinition.table_value(cls.invocations_known_table, sheet.level)
	if invocations > 0:
		var opts := LevelUp._invocation_options(sheet, level, gained, content)
		if not opts.is_empty():
			out.append({"type": CHOICE_INVOCATIONS, "count": mini(invocations, opts.size()), "options": opts})
	var metamagic := ClassDefinition.table_value(cls.metamagic_known_table, level) - ClassDefinition.table_value(cls.metamagic_known_table, sheet.level)
	if metamagic > 0:
		var opts: Array[String] = []
		for key: Variant in LevelUp._records(content, "metamagic"):
			if not sheet.metamagic.has(str(key)):
				opts.append(str(key))
		opts.sort()
		if not opts.is_empty():
			out.append({"type": CHOICE_METAMAGIC, "count": mini(metamagic, opts.size()), "options": opts})
	for f in gained:
		var opts := LevelUp.feature_options(f, cls)
		if not opts.is_empty():
			out.append({"type": CHOICE_FEATURE_OPTION, "feature": f, "count": 1, "options": opts})
	if gained.has("bonus_proficiencies"):
		var skills: Array[String] = []
		for skill in range(Skill.COUNT):
			if not sheet.proficient_skills.has(skill):
				skills.append(Skill.key_of(skill))
		skills.sort()
		out.append({"type": CHOICE_SKILLS, "count": mini(BONUS_PROFICIENCY_SKILLS, skills.size()), "options": skills})
	for entry in out:
		var opts: Array = entry["options"]
		entry["default"] = opts.slice(0, DictUtil.to_int(entry["count"]))
	return out


## Option feature ids of a choice feature (Features.FEATURE_OPTIONS; land
## terrains limited to the class's spells_by_terrain when it has them).
static func feature_options(feature: String, cls: ClassDefinition) -> Array[String]:
	var out: Array[String] = []
	if not Features.FEATURE_OPTIONS.has(feature):
		return out
	for o: Variant in Features.FEATURE_OPTIONS[feature]:
		var id := str(o)
		if feature == "circle_spells" and cls != null and not cls.subclass_spells_by_terrain.is_empty():
			if not cls.subclass_spells_by_terrain.has(id.trim_prefix(Features.LAND_OPTION_PREFIX)):
				continue
		out.append(id)
	return out


## Invocations not known yet whose prerequisites hold at `level` (level, pact
## boon, known spell).
static func _invocation_options(sheet: CharacterSheet, level: int, gained: Array[String], content: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var records := LevelUp._records(content, "invocations")
	for key: Variant in records.keys():
		var id := str(key)
		if sheet.invocations.has(id):
			continue
		var rec: Dictionary = records[key]
		var pre_v: Variant = rec.get("prerequisites", null)
		if typeof(pre_v) == TYPE_DICTIONARY:
			var pre: Dictionary = pre_v
			if DictUtil.to_int(pre.get("level", 0), 0) > level:
				continue
			var pact := str(pre.get("pact", ""))
			if not pact.is_empty() and not sheet.features.has(pact) and not gained.has(pact):
				continue
			var spell := str(pre.get("spell", ""))
			if not spell.is_empty() and not sheet.spells_known.has(spell):
				continue
		out.append(id)
	out.sort()
	return out


static func _records(content: Dictionary, key: String) -> Dictionary:
	var v: Variant = content.get(key, {})
	return v if typeof(v) == TYPE_DICTIONARY else {}


static func apply(sheet: CharacterSheet, made: Dictionary, content: Dictionary = {}, rng: Rng = null) -> String:
	if sheet == null:
		return "no character"
	if sheet.level >= CharacterSheet.MAX_LEVEL:
		return "already at the maximum level"
	if sheet.pending_levels() <= 0:
		return "not enough XP for level %d (%d / %d)" % [sheet.level + 1, sheet.xp, Experience.xp_for_level(sheet.level + 1)]
	var c := ContentLoader.resolve(content)
	var cls := sheet.class_definition(c)
	var ch := LevelUp.choices(sheet, c)
	var new_level: int = ch["new_level"]
	# --- hit points
	var hp_mode := str(made.get("hp", "average"))
	if not hp_mode in ["average", "roll"]:
		return "hp must be \"average\" or \"roll\""
	if hp_mode == "roll" and rng == null:
		return "rolling hit points needs an rng"
	# --- ability score improvement
	var asi_v: Variant = made.get("asi", {})
	var asi: Dictionary = asi_v if typeof(asi_v) == TYPE_DICTIONARY else {}
	if asi_v != null and typeof(asi_v) != TYPE_DICTIONARY:
		return "asi must be an object such as {\"STR\": 2}"
	var raises: Dictionary[int, int] = {}
	if DictUtil.to_bool(ch["asi"]):
		var err := LevelUp._check_asi(sheet, asi, raises)
		if not err.is_empty():
			return err
	elif not asi.is_empty():
		return "level %d has no ability score improvement" % new_level
	# --- progression choices
	var picks := {}
	var choice_list: Array = ch["choices"]
	var err_p := LevelUp.check_choices(choice_list, made, picks)
	if not err_p.is_empty():
		return err_p
	# --- spells
	var options: Array[String] = []
	for id_v: Variant in ch["spell_options"]:
		options.append(str(id_v))
	var learn_cantrips := DictUtil.to_string_array(made.get("learn_cantrips", []))
	var learn_spells := DictUtil.to_string_array(made.get("learn_spells", []))
	var err_c := LevelUp._check_learn(learn_cantrips, DictUtil.to_int(ch["cantrips_to_learn"]), options, c, true)
	if not err_c.is_empty():
		return err_c
	var err_s := LevelUp._check_learn(learn_spells, DictUtil.to_int(ch["spells_to_learn"]), options, c, false)
	if not err_s.is_empty():
		return err_s
	var prepared_given := made.has("prepared") and made["prepared"] != null
	var prepared := DictUtil.to_string_array(made.get("prepared", []))
	var leveled_prepared: Array[String] = []
	if prepared_given:
		if cls == null or not cls.prepares_spells:
			if not prepared.is_empty():
				return "this class does not prepare spells"
		else:
			var allowed: Array[String] = []
			for id_v: Variant in ch["prepare_options"]:
				allowed.append(str(id_v))
			allowed.append_array(learn_spells)
			for spell_id in prepared:
				var spell := LevelUp._spell(spell_id, c)
				if spell != null and spell.level == 0 and (sheet.spells_known.has(spell_id) or learn_cantrips.has(spell_id)):
					continue  # cantrips are always prepared
				if sheet.always_prepared.has(spell_id):
					continue  # subclass spells are always prepared
				if not allowed.has(spell_id):
					return "%s cannot be prepared" % spell_id
				if leveled_prepared.has(spell_id):
					return "%s is listed twice" % spell_id
				leveled_prepared.append(spell_id)
			if leveled_prepared.size() > DictUtil.to_int(ch["prepared_count"]):
				return "at most %d spells can be prepared, got %d" % [DictUtil.to_int(ch["prepared_count"]), leveled_prepared.size()]
	# --- apply
	var old_con := sheet.ability_modifier(Ability.Type.CON)
	for ability: int in raises.keys():
		sheet.abilities.set_score(ability, mini(MAX_SCORE, sheet.abilities.get_score(ability) + raises[ability]))
	var con_delta := sheet.ability_modifier(Ability.Type.CON) - old_con
	if con_delta != 0:
		sheet.max_hp = maxi(1, sheet.max_hp + con_delta * sheet.level)
		if sheet.is_conscious():
			sheet.current_hp = clampi(sheet.current_hp + con_delta * sheet.level, 1, sheet.max_hp)
	var base := floori(sheet.hit_die / 2.0) + 1
	if hp_mode == "roll":
		base = rng.next_int(1, sheet.hit_die)
	var gain := maxi(1, base + sheet.ability_modifier(Ability.Type.CON))
	sheet.advance_level(gain, cls)
	if picks.has(CHOICE_SUBCLASS):
		sheet.subclass_id = str(picks[CHOICE_SUBCLASS][0])
	for f_v: Variant in ch["features_gained"]:
		sheet.gain_feature(str(f_v))
	LevelUp.apply_picks(sheet, picks)
	for spell_id in learn_cantrips + learn_spells:
		if not sheet.spells_known.has(spell_id):
			sheet.spells_known.append(spell_id)
	if cls != null and cls.prepares_spells:
		var keep: Array[String] = []
		for spell_id in sheet.spells_prepared:
			var spell := LevelUp._spell(spell_id, c)
			if spell != null and spell.level == 0:
				keep.append(spell_id)
			elif sheet.always_prepared.has(spell_id) or not prepared_given:
				keep.append(spell_id)
		for spell_id in learn_cantrips:
			if not keep.has(spell_id):
				keep.append(spell_id)
		for spell_id in leveled_prepared:
			if not keep.has(spell_id):
				keep.append(spell_id)
		sheet.spells_prepared = keep
	else:
		for spell_id in learn_cantrips + learn_spells:
			if not sheet.spells_prepared.has(spell_id):
				sheet.spells_prepared.append(spell_id)
	LevelUp.sync_subclass_spells(sheet, cls)
	if not sheet.inventory.is_empty():
		sheet.rebuild_attacks(c)
	return ""


## Validates the answers to `choice_list` (choices()["choices"]) in `made` and
## fills picks[type or "feature_option:<feature>"] = Array[String]. "" or an error.
static func check_choices(choice_list: Array, made: Dictionary, picks: Dictionary) -> String:
	var feature_answers: Dictionary = made.get("feature_options", {}) if typeof(made.get("feature_options", {})) == TYPE_DICTIONARY else {}
	for entry_v: Variant in choice_list:
		var entry: Dictionary = entry_v
		var kind := str(entry["type"])
		var count := DictUtil.to_int(entry["count"])
		var allowed := DictUtil.to_string_array(entry["options"])
		var given: Array[String] = []
		var key := kind
		match kind:
			CHOICE_SUBCLASS, CHOICE_FIGHTING_STYLE:
				var v: Variant = made.get(kind, null)
				if v != null and str(v) != "":
					given.append(str(v))
			CHOICE_FEATURE_OPTION:
				key = "%s:%s" % [kind, str(entry["feature"])]
				var v: Variant = feature_answers.get(str(entry["feature"]), null)
				if v != null and str(v) != "":
					given.append(str(v))
			_:
				given = DictUtil.to_string_array(made.get(kind, []))
				if kind in [CHOICE_EXPERTISE, CHOICE_SKILLS]:
					var upper: Array[String] = []
					for g in given:
						upper.append(g.to_upper())
					given = upper
		var label := kind if kind != CHOICE_FEATURE_OPTION else str(entry["feature"])
		var answered := made.has(kind) if kind != CHOICE_FEATURE_OPTION else feature_answers.has(str(entry["feature"]))
		if not answered:
			given = DictUtil.to_string_array(entry.get("default", []))
		if given.size() != count:
			return "choose %d %s option%s, got %d" % [count, label, "" if count == 1 else "s", given.size()]
		var seen: Array[String] = []
		for g in given:
			if not allowed.has(g):
				return "%s is not a %s option" % [g, label]
			if seen.has(g):
				return "%s is listed twice" % g
			seen.append(g)
		picks[key] = seen
	return ""


## Applies validated picks (see check_choices) to the sheet: fighting styles,
## expertise, extra skill proficiencies, invocations, metamagic and option
## features (added to `features`).
static func apply_picks(sheet: CharacterSheet, picks: Dictionary) -> void:
	for key: Variant in picks.keys():
		var values: Array = picks[key]
		var kind := str(key)
		for v: Variant in values:
			var id := str(v)
			match kind:
				CHOICE_FIGHTING_STYLE:
					if not sheet.fighting_styles.has(id):
						sheet.fighting_styles.append(id)
				CHOICE_EXPERTISE:
					var skill := Skill.from_string(id)
					if skill >= 0 and not sheet.expertise_skills.has(skill):
						sheet.expertise_skills.append(skill)
				CHOICE_SKILLS:
					var skill := Skill.from_string(id)
					if skill >= 0 and not sheet.proficient_skills.has(skill):
						sheet.proficient_skills.append(skill)
				CHOICE_INVOCATIONS:
					if not sheet.invocations.has(id):
						sheet.invocations.append(id)
				CHOICE_METAMAGIC:
					if not sheet.metamagic.has(id):
						sheet.metamagic.append(id)
				_:
					if kind.begins_with(CHOICE_FEATURE_OPTION + ":"):
						sheet.gain_feature(id)


## Adds the subclass's always-prepared spells up to the sheet's level (domain,
## oath spells; circle spells of the chosen land) to always_prepared,
## spells_known and spells_prepared.
static func sync_subclass_spells(sheet: CharacterSheet, cls: ClassDefinition) -> void:
	if cls == null or not cls.has_subclass() or sheet.subclass_id != cls.subclass_id:
		return
	if cls.subclass_spells_mode != "always_prepared":
		return
	var spells := cls.subclass_spells_through(sheet.level)
	for terrain: Variant in cls.subclass_spells_by_terrain.keys():
		if sheet.features.has(Features.LAND_OPTION_PREFIX + str(terrain)) and sheet.features.has("circle_spells"):
			spells.append_array(cls.subclass_spells_through(sheet.level, str(terrain)))
	for s in spells:
		if not sheet.always_prepared.has(s):
			sheet.always_prepared.append(s)
		if not sheet.spells_known.has(s):
			sheet.spells_known.append(s)
		if not sheet.spells_prepared.has(s):
			sheet.spells_prepared.append(s)


static func _check_asi(sheet: CharacterSheet, asi: Dictionary, raises: Dictionary[int, int]) -> String:
	if asi.is_empty():
		return "choose an ability score improvement: +2 to one ability or +1 to two"
	var total := 0
	for key: Variant in asi.keys():
		var ability := Ability.from_string(str(key))
		if ability < 0:
			return "unknown ability '%s'" % str(key)
		var amount := DictUtil.to_int(asi[key], 0)
		if amount < 1 or amount > 2:
			return "each ability rises by 1 or 2"
		if sheet.abilities.get_score(ability) >= MAX_SCORE:
			return "%s is already %d" % [Ability.abbreviation(ability), MAX_SCORE]
		raises[ability] = amount
		total += amount
	if total != 2 or raises.size() > 2:
		return "an ability score improvement is +2 to one ability or +1 to two"
	return ""


static func _check_learn(picks: Array[String], count: int, options: Array[String], content: Dictionary, cantrips: bool) -> String:
	var what := "cantrips" if cantrips else "spells"
	if picks.size() != count:
		return "learn exactly %d %s, got %d" % [count, what, picks.size()]
	var seen: Array[String] = []
	for spell_id in picks:
		if not options.has(spell_id):
			return "%s is not a %s option" % [spell_id, what]
		var spell := LevelUp._spell(spell_id, content)
		if spell == null or (spell.level == 0) != cantrips:
			return "%s is not a %s" % [spell_id, "cantrip" if cantrips else "leveled spell"]
		if seen.has(spell_id):
			return "%s is listed twice" % spell_id
		seen.append(spell_id)
	return ""


## Leveled spells a prepared caster may prepare: a spellbook caster (wizard)
## from its known spells, others from the class list up to max_slot.
static func _prepare_options(sheet: CharacterSheet, cls: ClassDefinition, content: Dictionary, max_slot: int) -> Array[String]:
	var out: Array[String] = []
	var source: Array[String] = sheet.spells_known if cls.spellbook_learn_per_level > 0 else cls.spell_list
	for spell_id in source:
		if sheet.always_prepared.has(spell_id):
			continue
		var spell := LevelUp._spell(spell_id, content)
		if spell != null and spell.level >= 1 and spell.level <= max_slot and not out.has(spell_id):
			out.append(spell_id)
	return out


static func _spell(spell_id: String, content: Dictionary) -> SpellDefinition:
	var spells: Dictionary = content.get("spells", {})
	if not spells.has(spell_id):
		return null
	var s: SpellDefinition = spells[spell_id]
	return s

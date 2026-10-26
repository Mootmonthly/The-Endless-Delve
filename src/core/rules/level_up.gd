class_name LevelUp
extends RefCounted
## The interactive level-up flow. CharacterSheet.gain_xp only banks XP; when
## sheet.pending_levels() > 0 the player picks from choices() and the server
## calls apply() once per level.
##
## choices(sheet, content) ->
## {"new_level": int, "levels_pending": int,
##  "hp": {"average": int, "may_roll": true, "die": int, "con_mod": int},
##  "asi": bool, "new_spell_slots": Array[int] (max slots per spell level at the new level),
##  "cantrips_to_learn": int, "spells_to_learn": int,
##  "spell_options": Array[String] (class spells not known yet, level <= highest
##                   castable slot at the new level; cantrips included),
##  "prepared_count": int (prepared casters: casting mod + new level, min 1; else 0),
##  "prepare_options": Array[String] (leveled spells that may be prepared, before
##                     this level's learning; a wizard's spellbook, a cleric's list),
##  "features_gained": Array[String], "skills_to_choose": 0}
##
## apply(sheet, made, content, rng) with made =
## {"hp": "average"|"roll", "asi": {"STR": 2} or {"STR": 1, "DEX": 1},
##  "learn_cantrips": [ids], "learn_spells": [ids], "prepared": [ids]}
## returns "" on success, else an error and the sheet is unchanged. Learning
## must pick exactly cantrips_to_learn / spells_to_learn options; "prepared"
## (prepared casters only, optional: omitted keeps the current preparation)
## lists at most prepared_count leveled spells. An ASI is required exactly when
## offered: +2 to one ability or +1 to two; a score cannot exceed 20 (the
## excess is lost) and an ability already at 20 cannot be picked. A CON
## increase raises max hp retroactively (SRD).

const MAX_SCORE := 20


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
	var features_gained: Array[String] = []
	if cls != null:
		for spell_id in cls.spell_list:
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
		if not cls.spells_known_table.is_empty():
			spells_to_learn = maxi(0, ClassDefinition.table_value(cls.spells_known_table, new_level) - ClassDefinition.table_value(cls.spells_known_table, sheet.level))
		elif cls.spellbook_learn_per_level > 0:
			spells_to_learn = cls.spellbook_learn_per_level
		cantrips_to_learn = mini(cantrips_to_learn, cantrip_options.size())
		spells_to_learn = mini(spells_to_learn, spell_options.size())
		if cls.prepares_spells:
			prepared_count = maxi(1, sheet.casting_modifier() + new_level) if cls.spellcasting_ability >= 0 else 0
			prepare_options = LevelUp._prepare_options(sheet, cls, c, max_slot)
		for f in cls.features_at(new_level):
			if not sheet.features.has(f):
				features_gained.append(f)
	return {
		"new_level": new_level,
		"levels_pending": sheet.pending_levels(),
		"hp": {"average": maxi(1, floori(sheet.hit_die / 2.0) + 1 + con_mod), "may_roll": true, "die": sheet.hit_die, "con_mod": con_mod},
		"asi": asi_levels.has(new_level),
		"new_spell_slots": new_slots,
		"cantrips_to_learn": cantrips_to_learn,
		"spells_to_learn": spells_to_learn,
		"spell_options": options,
		"prepared_count": prepared_count,
		"prepare_options": prepare_options,
		"features_gained": features_gained,
		"skills_to_choose": 0,
	}


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
	for f_v: Variant in ch["features_gained"]:
		var f := str(f_v)
		if not sheet.features.has(f):
			sheet.features.append(f)
			if CharacterSheet.RESOURCE_FEATURES.has(f):
				sheet.class_resources[f] = sheet.resource_max(f)
	for spell_id in learn_cantrips + learn_spells:
		if not sheet.spells_known.has(spell_id):
			sheet.spells_known.append(spell_id)
	if cls != null and cls.prepares_spells:
		var keep: Array[String] = []
		for spell_id in sheet.spells_prepared:
			var spell := LevelUp._spell(spell_id, c)
			if spell != null and spell.level == 0:
				keep.append(spell_id)
			elif not prepared_given:
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
	if not raises.is_empty() and not sheet.inventory.is_empty():
		sheet.rebuild_attacks(c)
	return ""


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

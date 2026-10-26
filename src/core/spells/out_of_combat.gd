class_name OutOfCombat
extends RefCounted
## Spells cast outside an encounter (exploration, rests) on character sheets:
## the long-casting-time spells the encounter cannot cast (Find Familiar, Animate
## Dead, Find Steed, Create Undead, Raise Dead, Resurrection, Prayer of
## Healing) plus heals, temporary hit points, restorations and Mage Armor.
##
## cast(caster, spell_id, content, rng, targets, options) ->
##   {"ok": bool, "error": String, "slot_level": int, "result": {...}}
## targets: Array[CharacterSheet] (default: the caster). options:
##   "slot_level" (default: the lowest free slot >= the spell's level),
##   "form" (a companion's monster id), "dead_minutes" (Revivify: <= 1).
## Companions are appended to the caster's sheet.companions as {"monster",
## "spell", "hp", "until_long_rest"?}; the Encounter spawns them next to their
## owner when a fight starts. One familiar at a time (a new one replaces it).
## Nothing changes on an error.


static func cast(caster: CharacterSheet, spell_id: String, content: Dictionary = {}, rng: Rng = null, targets: Array[CharacterSheet] = [], options: Dictionary = {}) -> Dictionary:
	var c := ContentLoader.resolve(content)
	var spells: Dictionary = c.get("spells", {})
	if not spells.has(spell_id):
		return OutOfCombat._fail("unknown spell '%s'" % spell_id)
	var spell: SpellDefinition = spells[spell_id]
	if caster == null or not caster.is_conscious():
		return OutOfCombat._fail("the caster cannot cast")
	if not caster.is_spell_prepared(spell_id):
		return OutOfCombat._fail("%s has not prepared %s" % [caster.name, spell.display_name])
	if not spell.is_supported():
		return OutOfCombat._fail("%s cannot be cast yet" % spell.display_name)
	var slot := 0
	if spell.level > 0:
		slot = DictUtil.to_int(options.get("slot_level", 0), 0)
		if slot <= 0:
			slot = caster.lowest_available_slot(spell.level)
		if slot < spell.level or caster.slots_left(slot) <= 0:
			return OutOfCombat._fail("no level %d+ spell slot left" % spell.level)
	var list: Array[CharacterSheet] = targets.duplicate()
	if list.is_empty():
		list.append(caster)
	var e := spell.raw_effect
	var result := {}
	match spell.effect_type:
		SpellDefinition.EFFECT_SUMMON:
			if e.get("companion", false) != true:
				return OutOfCombat._fail("%s only works in a fight" % spell.display_name)
			var form := str(options.get("form", e.get("monster", "")))
			var forms := DictUtil.to_string_array(e.get("forms", []))
			var monsters: Dictionary = c.get("monsters", {})
			if not forms.is_empty() and not forms.has(form) or not monsters.has(form):
				return OutOfCombat._fail("%s cannot bring '%s'" % [spell.display_name, form])
			var def: MonsterDefinition = monsters[form]
			var count := DictUtil.to_int(e.get("count_base", 1), 1) + DictUtil.to_int(e.get("count_per_slot", 0), 0) * maxi(0, slot - spell.level)
			if e.get("familiar", false) == true:
				var kept: Array[Dictionary] = []
				for entry in caster.companions:
					if str(entry.get("spell", "")) != spell_id:
						kept.append(entry)
				caster.companions = kept
				count = 1
			for _i in range(count):
				var entry := {"monster": def.id, "spell": spell_id, "hp": def.hit_points_avg}
				if e.get("until_long_rest", false) == true:
					entry["until_long_rest"] = true
				caster.companions.append(entry)
			result = {"companions": count, "monster": def.id}
		SpellDefinition.EFFECT_REVIVE:
			var t := list[0]
			if e.get("stabilize", false) == true:
				return OutOfCombat._fail("Spare the Dying only matters in a fight")
			if not t.is_dead():
				return OutOfCombat._fail("%s is not dead" % t.name)
			var max_rounds := DictUtil.to_int(e.get("max_rounds", -1), -1)
			if max_rounds >= 0 and DictUtil.to_float(options.get("dead_minutes", 99.0), 99.0) > 1.0:
				return OutOfCombat._fail("%s has been dead too long" % t.name)
			var hp := DictUtil.to_int(e.get("hp", 1), 1)
			t.dead = false
			t.current_hp = t.max_hp if hp < 0 else clampi(hp, 1, t.max_hp)
			t.reset_death_saves()
			t.resurrection_penalty = maxi(t.resurrection_penalty, DictUtil.to_int(e.get("penalty", 0), 0))
			result = {"revived": t.name, "hp": t.current_hp}
		SpellDefinition.EFFECT_HEAL, SpellDefinition.EFFECT_AREA_HEAL, SpellDefinition.EFFECT_HEAL_POOL:
			if list.size() > spell.targets_at(slot) and spell.effect_type != SpellDefinition.EFFECT_HEAL_POOL:
				return OutOfCombat._fail("%s affects at most %d creatures" % [spell.display_name, spell.targets_at(slot)])
			if rng == null:
				return OutOfCombat._fail("healing needs an rng")
			var healed := {}
			var pool := DictUtil.to_int(e.get("pool", 0), 0)
			for t in list:
				var amount := 0
				if spell.effect_type == SpellDefinition.EFFECT_HEAL_POOL:
					amount = mini(pool, t.max_hp - t.current_hp)
					pool -= amount
				else:
					var hf := spell.heal_formula(slot)
					amount = maxi(0, DictUtil.to_int(DiceFormula.parse(str(hf["formula"])).roll(rng, caster.casting_modifier())["total"]))
					if hf["add_mod"] == true:
						amount += caster.casting_modifier()
					if spell.level >= 1 and caster.has_feature("disciple_of_life"):
						amount += 2 + slot
				healed[t.name] = t.heal(amount)
			result = {"healed": healed}
		SpellDefinition.EFFECT_TEMP_HP:
			if rng == null:
				return OutOfCombat._fail("temporary hit points need an rng")
			var hf := spell.heal_formula(slot)
			var amount := maxi(0, DictUtil.to_int(DiceFormula.parse(str(hf["formula"])).roll(rng, caster.casting_modifier())["total"]))
			list[0].grant_temp_hp(amount)
			result = {"temp_hp": amount}
		SpellDefinition.EFFECT_DISPEL:
			var t := list[0]
			for cond in DictUtil.to_string_array(e.get("conditions", [])):
				t.conditions.erase(cond)
			if DictUtil.to_int(e.get("exhaustion", 0), 0) > 0:
				t.add_exhaustion(-DictUtil.to_int(e["exhaustion"], 0))
			result = {"target": t.name, "exhaustion": t.exhaustion}
		SpellDefinition.EFFECT_BUFF:
			if spell.buff != SpellDefinition.BUFF_MAGE_ARMOR:
				return OutOfCombat._fail("%s only lasts within a fight" % spell.display_name)
			var t := list[0]
			if t.armor_base > 0:
				return OutOfCombat._fail("%s is wearing armor" % t.name)
			if not t.active_buffs.has(SpellDefinition.BUFF_MAGE_ARMOR):
				t.active_buffs.append(SpellDefinition.BUFF_MAGE_ARMOR)
			result = {"ac": t.armor_class()}
		_:
			return OutOfCombat._fail("%s has no effect outside a fight" % spell.display_name)
	if slot > 0:
		caster.use_spell_slot(slot)
	return {"ok": true, "error": "", "slot_level": slot, "result": result}


static func _fail(reason: String) -> Dictionary:
	return {"ok": false, "error": reason, "slot_level": 0, "result": {}}

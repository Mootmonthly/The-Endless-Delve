class_name OutOfCombat
extends RefCounted
## Spells cast outside an encounter (exploration, rests) on character sheets:
## the long-casting-time spells the encounter cannot cast (Find Familiar, Animate
## Dead, Find Steed, Create Undead, Raise Dead, Resurrection, Prayer of
## Healing) plus heals, temporary hit points, restorations and Mage Armor.
##
## cast(caster, spell_id, content, rng, targets, options) ->
##   {"ok": bool, "error": String, "slot_level": int, "result": {...},
##    "events": [event dicts]}
## targets: Array[CharacterSheet] (default: the caster). options:
##   "slot_level" (default: the lowest free slot >= the spell's level),
##   "form" (a companion's monster id), "dead_minutes" (Revivify: <= 1),
##   "ritual": true (a ritual spell cast as a ritual: no slot; see
##   can_ritual_cast), "caster_id" (the caster's id in events, default ""),
##   "target_ids" (ids of `targets` in order; events name a target by its id,
##   else by its index as a string), "mode" (spell variants),
##   "spend_slot": true (a no_effect spell spends its slot anyway).
## Events (same kinds the server sends in out_of_combat_events):
##   cast {actor, spell, target, slot_level, casting_time, ritual}
##   companion_summoned {caster, spell, monster, count, companion_ids}
##   heal {source, target, target_index, amount, hp_after}
##   temp_hp {source, target, target_index, amount, temp_hp_after}
##   revived {source, target, target_index, hp, hp_after, spell}
##   restored {source, target, target_index, conditions_removed, exhaustion}
##   buff {source, target, target_index, buff, ac?}
## Round C kinds: lingering_added {source, target, target_index, spell,
## lingering_kind, encounters} (spells whose effect holds for the next encounters, see
## CharacterSheet.lingering), no_effect {actor, spell, reason} (declared
## no-effect spells, free unless "spend_slot"; and spells whose rules only
## work inside a fight but take too long to cast there).
## Companions are appended to the caster's sheet.companions as {"id" ("c<n>",
## minted by the sheet), "monster", "spell", "hp", "until_long_rest"?}; the
## Encounter spawns them next to their owner when a fight starts. One familiar
## at a time (a new one replaces it). Nothing changes on an error.

## Classes whose Spellcasting includes Ritual Casting (SRD): a prepared ritual
## can be cast as a ritual; a wizard may ritual-cast any ritual in its
## spellbook (spells_known), prepared or not.
const RITUAL_CASTERS: Array[String] = ["bard", "cleric", "druid", "wizard"]
const SPELLBOOK_RITUALS: Array[String] = ["wizard"]


## Whether cast() can resolve this spell outside a fight (for any caster):
## companion summons, revives (not Spare the Dying), heals, temporary hit
## points, restorations, Mage Armor, exploration hooks and declared no_effect
## spells.
static func castable(spell: SpellDefinition) -> bool:
	if spell == null or not spell.is_castable():
		return false
	var e := spell.raw_effect
	if e.has("lingering") or not OutOfCombat.fight_only_reason(spell).is_empty():
		return true
	match spell.effect_type:
		SpellDefinition.EFFECT_SUMMON:
			return e.get("companion", false) == true
		SpellDefinition.EFFECT_REVIVE:
			return e.get("stabilize", false) != true
		SpellDefinition.EFFECT_HEAL, SpellDefinition.EFFECT_AREA_HEAL, SpellDefinition.EFFECT_HEAL_POOL, \
				SpellDefinition.EFFECT_TEMP_HP, SpellDefinition.EFFECT_DISPEL, SpellDefinition.EFFECT_NO_EFFECT, \
				SpellDefinition.EFFECT_EXPLORATION:
			return true
		SpellDefinition.EFFECT_BUFF:
			return spell.buff == SpellDefinition.BUFF_MAGE_ARMOR
	return false


## A spell whose rules only resolve inside a fight but whose casting time
## (1 minute or more, or a reaction) keeps it out of one: cast outside a fight
## it does nothing, and says why ("" for other spells).
static func fight_only_reason(spell: SpellDefinition) -> String:
	if spell == null or spell.is_combat_castable() or spell.raw_effect.has("lingering"):
		return ""
	match spell.effect_type:
		SpellDefinition.EFFECT_SUMMON:
			if spell.raw_effect.get("companion", false) == true:
				return ""
		SpellDefinition.EFFECT_REVIVE, SpellDefinition.EFFECT_HEAL, SpellDefinition.EFFECT_AREA_HEAL, SpellDefinition.EFFECT_HEAL_POOL, \
				SpellDefinition.EFFECT_TEMP_HP, SpellDefinition.EFFECT_DISPEL, SpellDefinition.EFFECT_NO_EFFECT, SpellDefinition.EFFECT_EXPLORATION:
			return ""
		SpellDefinition.EFFECT_BUFF:
			if spell.buff == SpellDefinition.BUFF_MAGE_ARMOR:
				return ""
	if spell.casting_time == "reaction":
		return "it is cast as a reaction during a fight"
	return "its target must be at hand, and outside a fight the delve has none; a %s casting cannot happen in a fight" % spell.casting_time.replace("_", " ")


## Whether `caster` may cast spell_id as a ritual: the spell has the ritual
## tag and the caster's class has Ritual Casting (prepared; a wizard's
## spellbook is enough).
static func can_ritual_cast(caster: CharacterSheet, spell: SpellDefinition) -> bool:
	if caster == null or spell == null or not spell.ritual:
		return false
	if SPELLBOOK_RITUALS.has(caster.class_id) and caster.spells_known.has(spell.id):
		return true
	return RITUAL_CASTERS.has(caster.class_id) and caster.is_spell_prepared(spell.id)


static func cast(caster: CharacterSheet, spell_id: String, content: Dictionary = {}, rng: Rng = null, targets: Array[CharacterSheet] = [], options: Dictionary = {}) -> Dictionary:
	var c := ContentLoader.resolve(content)
	var spells: Dictionary = c.get("spells", {})
	if not spells.has(spell_id):
		return OutOfCombat._fail("unknown spell '%s'" % spell_id)
	var spell: SpellDefinition = spells[spell_id]
	if caster == null or not caster.is_conscious():
		return OutOfCombat._fail("the caster cannot cast")
	var ritual := DictUtil.to_bool(options.get("ritual", false), false)
	if ritual and not OutOfCombat.can_ritual_cast(caster, spell):
		return OutOfCombat._fail("%s cannot cast %s as a ritual" % [caster.name, spell.display_name])
	if not ritual and not caster.is_spell_prepared(spell_id):
		return OutOfCombat._fail("%s has not prepared %s" % [caster.name, spell.display_name])
	if not spell.is_castable():
		return OutOfCombat._fail("%s cannot be cast yet" % spell.display_name)
	var fight_only := OutOfCombat.fight_only_reason(spell)
	var no_effect := spell.effect_type == SpellDefinition.EFFECT_NO_EFFECT or not fight_only.is_empty()
	var free := ritual or (no_effect and not DictUtil.to_bool(options.get("spend_slot", false), false))
	var slot := 0
	if spell.level > 0 and not free:
		slot = DictUtil.to_int(options.get("slot_level", 0), 0)
		if slot <= 0:
			slot = caster.lowest_available_slot(spell.level)
		if slot < spell.level or caster.slots_left(slot) <= 0:
			return OutOfCombat._fail("no level %d+ spell slot left" % spell.level)
	var effect_slot := slot if slot > 0 else spell.level
	var list: Array[CharacterSheet] = targets.duplicate()
	if list.is_empty():
		list.append(caster)
	var ids := DictUtil.to_string_array(options.get("target_ids", []))
	var caster_id := str(options.get("caster_id", ids[0] if not ids.is_empty() and list[0] == caster else ""))
	var e := spell.raw_effect
	var result := {}
	var events: Array[Dictionary] = []
	events.append({"kind": "cast", "actor": caster_id, "spell": spell_id, "target": OutOfCombat._target_key(list, 0, ids),
			"slot_level": slot, "casting_time": spell.casting_time, "ritual": ritual})
	if no_effect:
		var reason := spell.no_effect_reason() if fight_only.is_empty() else fight_only
		events.append({"kind": "no_effect", "actor": caster_id, "spell": spell_id, "reason": reason})
		if slot > 0:
			caster.use_spell_slot(slot)
		return {"ok": true, "error": "", "slot_level": slot, "result": {"no_effect": reason}, "events": events}
	if e.has("lingering"):
		var lg_v: Variant = e["lingering"]
		var lg: Dictionary = lg_v if typeof(lg_v) == TYPE_DICTIONARY else {}
		if list.size() > spell.targets_at(effect_slot):
			return OutOfCombat._fail("%s affects at most %d creatures" % [spell.display_name, spell.targets_at(effect_slot)])
		var encounters := DictUtil.to_int(lg.get("encounters", SpellDefinition.encounters_for_duration(spell.duration_text)), 1)
		if encounters == 0:
			encounters = 1
		for i in range(list.size()):
			var t := list[i]
			var entry := {"spell": spell_id, "slot_level": effect_slot, "kind": str(lg.get("kind", "buff")), "encounters_left": encounters}
			for key: String in ["effect", "modifiers", "feature", "condition"]:
				if lg.has(key):
					entry[key] = lg[key].duplicate(true) if typeof(lg[key]) == TYPE_DICTIONARY else lg[key]
			if options.has("mode"):
				entry["mode"] = str(options["mode"])
			if options.has("creature_type"):
				entry["creature_type"] = str(options["creature_type"])
			var kept: Array[Dictionary] = []
			for old in t.lingering:
				if str(old.get("spell", "")) != spell_id:
					kept.append(old)
			kept.append(entry)
			t.lingering = kept
			events.append(OutOfCombat._target_event("lingering_added", caster_id, list, i, ids, {"spell": spell_id, "lingering_kind": entry["kind"], "encounters": encounters}))
		if slot > 0:
			caster.use_spell_slot(slot)
		return {"ok": true, "error": "", "slot_level": slot, "result": {"lingering": list.size(), "encounters": encounters}, "events": events}
	match spell.effect_type:
		SpellDefinition.EFFECT_SUMMON:
			if e.get("companion", false) != true:
				return OutOfCombat._fail("%s only works in a fight" % spell.display_name)
			var custom := str(e.get("custom", ""))
			var monster_id := custom
			var hp := 1
			var count := 1
			if custom.is_empty():
				var form := str(options.get("form", e.get("monster", "")))
				var forms := DictUtil.to_string_array(e.get("forms", []))
				var monsters: Dictionary = c.get("monsters", {})
				var def: MonsterDefinition = null
				if forms.is_empty() and typeof(e.get("forms", null)) != TYPE_ARRAY:
					def = Encounter.summon_def_for(spell, form, effect_slot, monsters)
				elif forms.has(form) and monsters.has(form):
					def = monsters[form]
				if def == null:
					return OutOfCombat._fail("%s cannot bring '%s'" % [spell.display_name, form])
				monster_id = def.id
				hp = def.hit_points_avg
				count = Encounter.summon_count(spell, def, effect_slot)
			if e.get("familiar", false) == true or e.get("single", false) == true:
				var kept: Array[Dictionary] = []
				for entry in caster.companions:
					if str(entry.get("spell", "")) != spell_id:
						kept.append(entry)
				caster.companions = kept
				count = 1
			caster.stamp_companion_ids()
			var new_ids: Array = []
			var encounters := 0
			if e.has("encounters"):
				encounters = DictUtil.to_int(e["encounters"], 0)
				if encounters <= 0:
					encounters = SpellDefinition.encounters_for_duration(spell.duration_text)
			for _i in range(count):
				var entry := {"id": caster.mint_companion_id(), "spell": spell_id, "hp": hp}
				if custom.is_empty():
					entry["monster"] = monster_id
				else:
					entry["custom"] = custom
					entry["slot_level"] = effect_slot
					if e.get("familiar", false) == true:
						entry["familiar"] = true
					if custom == "simulacrum":
						var copy := caster.to_dict()
						copy["name"] = "%s (simulacrum)" % caster.name
						copy["max_hp"] = maxi(1, floori(caster.max_hp / 2.0))
						copy["current_hp"] = copy["max_hp"]
						copy["companions"] = []
						copy["lingering"] = []
						entry["sheet"] = copy
						entry["hp"] = copy["max_hp"]
				if e.get("until_long_rest", false) == true:
					entry["until_long_rest"] = true
				if encounters > 0:
					entry["encounters_left"] = encounters
				elif encounters < 0:
					entry["until_long_rest"] = true
				if spell.concentration:
					entry["concentration"] = true
					entry["slot_level"] = effect_slot
				caster.companions.append(entry)
				new_ids.append(entry["id"])
			result = {"companions": count, "monster": monster_id}
			events.append({"kind": "companion_summoned", "caster": caster_id, "spell": spell_id, "monster": monster_id, "count": count, "companion_ids": new_ids})
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
			var revived := {"hp": t.current_hp, "hp_after": t.current_hp, "spell": spell_id}
			if e.get("reincarnate", false) == true:
				var ancestries: Dictionary = c.get("ancestries", {})
				var keys: Array = ancestries.keys()
				keys.sort()
				if not keys.is_empty():
					var pick := str(keys[rng.next_int(0, keys.size() - 1)]) if rng != null else str(keys[0])
					var anc: AncestryDefinition = ancestries[pick]
					t.ancestry_id = anc.id
					t.speed = anc.speed
					t.size = anc.size
					result["ancestry"] = anc.id
					revived["ancestry"] = anc.id
			events.append(OutOfCombat._target_event("revived", caster_id, list, 0, ids, revived))
		SpellDefinition.EFFECT_HEAL, SpellDefinition.EFFECT_AREA_HEAL, SpellDefinition.EFFECT_HEAL_POOL:
			if list.size() > spell.targets_at(effect_slot) and spell.effect_type != SpellDefinition.EFFECT_HEAL_POOL:
				return OutOfCombat._fail("%s affects at most %d creatures" % [spell.display_name, spell.targets_at(effect_slot)])
			if rng == null:
				return OutOfCombat._fail("healing needs an rng")
			var healed := {}
			var by_target := {}
			var pool := DictUtil.to_int(e.get("pool", 0), 0)
			for i in range(list.size()):
				var t := list[i]
				var amount := 0
				if spell.effect_type == SpellDefinition.EFFECT_HEAL_POOL:
					amount = mini(pool, t.max_hp - t.current_hp)
					pool -= amount
				else:
					var hf := spell.heal_formula(effect_slot)
					amount = maxi(0, DictUtil.to_int(DiceFormula.parse(str(hf["formula"])).roll(rng, caster.casting_modifier())["total"]))
					if hf["add_mod"] == true:
						amount += caster.casting_modifier()
					if spell.level >= 1 and caster.has_feature("disciple_of_life"):
						amount += 2 + effect_slot
				var restored := t.heal(amount)
				healed[t.name] = restored
				by_target[OutOfCombat._target_key(list, i, ids)] = restored
				events.append(OutOfCombat._target_event("heal", caster_id, list, i, ids, {"amount": restored, "hp_after": t.current_hp}))
			result = {"healed": healed, "healed_by_target": by_target}
		SpellDefinition.EFFECT_TEMP_HP:
			if rng == null:
				return OutOfCombat._fail("temporary hit points need an rng")
			var hf := spell.heal_formula(effect_slot)
			var amount := maxi(0, DictUtil.to_int(DiceFormula.parse(str(hf["formula"])).roll(rng, caster.casting_modifier())["total"]))
			list[0].grant_temp_hp(amount)
			result = {"temp_hp": amount}
			events.append(OutOfCombat._target_event("temp_hp", caster_id, list, 0, ids, {"amount": amount, "temp_hp_after": list[0].temp_hp}))
		SpellDefinition.EFFECT_DISPEL:
			var t := list[0]
			var removed: Array = []
			for cond in DictUtil.to_string_array(e.get("conditions", [])):
				if t.conditions.has(cond):
					t.conditions.erase(cond)
					removed.append(cond)
			if DictUtil.to_int(e.get("exhaustion", 0), 0) > 0:
				t.add_exhaustion(-DictUtil.to_int(e["exhaustion"], 0))
			result = {"target": t.name, "exhaustion": t.exhaustion}
			events.append(OutOfCombat._target_event("restored", caster_id, list, 0, ids, {"conditions_removed": removed, "exhaustion": t.exhaustion}))
		SpellDefinition.EFFECT_BUFF:
			if spell.buff != SpellDefinition.BUFF_MAGE_ARMOR:
				return OutOfCombat._fail("%s only lasts within a fight" % spell.display_name)
			var t := list[0]
			if t.armor_base > 0:
				return OutOfCombat._fail("%s is wearing armor" % t.name)
			if not t.active_buffs.has(SpellDefinition.BUFF_MAGE_ARMOR):
				t.active_buffs.append(SpellDefinition.BUFF_MAGE_ARMOR)
			result = {"ac": t.armor_class()}
			events.append(OutOfCombat._target_event("buff", caster_id, list, 0, ids, {"buff": spell.buff, "ac": t.armor_class()}))
		_:
			return OutOfCombat._fail("%s has no effect outside a fight" % spell.display_name)
	if slot > 0:
		caster.use_spell_slot(slot)
	return {"ok": true, "error": "", "slot_level": slot, "result": result, "events": events}


## A target's key in events: its id from target_ids, else its index.
static func _target_key(list: Array[CharacterSheet], i: int, ids: Array[String]) -> String:
	if i < ids.size():
		return ids[i]
	return str(i) if i < list.size() else ""


static func _target_event(kind: String, caster_id: String, list: Array[CharacterSheet], i: int, ids: Array[String], fields: Dictionary) -> Dictionary:
	var ev := {"kind": kind, "source": caster_id, "target": OutOfCombat._target_key(list, i, ids), "target_index": i}
	ev.merge(fields)
	return ev


static func _fail(reason: String) -> Dictionary:
	var none: Array[Dictionary] = []
	return {"ok": false, "error": reason, "slot_level": 0, "result": {}, "events": none}

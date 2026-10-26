extends TestCase
## Levels 1-5 features of the casters: bard, cleric, druid, sorcerer,
## warlock, wizard (and the rest rules they bring).

const HIT := {"name": "Hit", "kind": "melee", "to_hit": 100, "damage": "4", "damage_type": "slashing", "ability": "STR"}

var content: Dictionary


func before_each() -> void:
	content = CoreFixtures.content()


func _evs(res: Dictionary) -> Array:
	var evs: Array = res.get("events", [])
	return evs


func _feature(e: Encounter, feature: String, fields: Dictionary = {}) -> Dictionary:
	var f := {"feature": feature}
	f.merge(fields)
	return e.submit(CoreFixtures.intent("use_feature", "hero", f))


func _cast(e: Encounter, spell: String, fields: Dictionary) -> Dictionary:
	var f := {"spell": spell}
	f.merge(fields)
	return e.submit(CoreFixtures.intent("cast", "hero", f))


# --- bard -----------------------------------------------------------------------

func test_bardic_inspiration_die_and_font_of_inspiration() -> void:
	var s := CoreFixtures.sheet("Bard", 30, [10, 10, 10, 10, 10, 16], ["bardic_inspiration"])
	s.level = 5
	assert_eq(s.bardic_inspiration_die(), 8)
	s.class_resources["bardic_inspiration"] = 0
	Rest.short_rest(s, 0, Rng.new(1))
	assert_eq(s.class_resource("bardic_inspiration"), 0, "long rest only")
	s.features.append("font_of_inspiration")
	Rest.short_rest(s, 0, Rng.new(1))
	assert_eq(s.class_resource("bardic_inspiration"), 3, "font of inspiration: short rest")


func test_song_of_rest() -> void:
	var bard := CoreFixtures.sheet("Bard", 30, [], ["song_of_rest"])
	bard.level = 9
	var down := CoreFixtures.sheet("Bard", 30, [], ["song_of_rest"])
	down.current_hp = 0
	var party: Array[CharacterSheet] = [bard, down, CoreFixtures.sheet("Other", 30)]
	assert_eq(Rest.song_of_rest_die(party), 8)
	var empty: Array[CharacterSheet] = [CoreFixtures.sheet("Other", 30)]
	assert_eq(Rest.song_of_rest_die(empty), 0)
	var a := CoreFixtures.sheet("A", 100)
	a.current_hp = 1
	a.hit_dice_remaining = 1
	var b := CoreFixtures.sheet("A", 100)
	b.current_hp = 1
	b.hit_dice_remaining = 1
	var plain := Rest.short_rest(a, 1, Rng.new(4))
	var sung := Rest.short_rest(b, 1, Rng.new(4), 8)
	assert_true(sung > plain, "an extra 1d8")
	assert_true(sung - plain <= 8)
	var c := CoreFixtures.sheet("C", 100)
	c.current_hp = 50
	assert_eq(Rest.short_rest(c, 0, Rng.new(4), 8), 0, "no hit die spent, no song")


# --- cleric ---------------------------------------------------------------------

func _cleric(level: int = 5) -> CharacterSheet:
	var s := CoreFixtures.caster("Cleric", Ability.Type.WIS, ["cure_wounds", "healing_word"], 40)
	s.abilities.set_score(Ability.Type.WIS, 30)
	s.features = ["channel_divinity", "turn_undead", "destroy_undead", "disciple_of_life", "preserve_life"]
	s.class_id = "cleric"
	s.level = level
	s.restore_class_resources()
	return s


func _undead_fight(cleric: CharacterSheet) -> Encounter:
	var make := func() -> Array:
		var c := CoreFixtures.combatant("hero", CharacterSheet.from_dict(cleric.to_dict()), Combatant.TEAM_PLAYERS, Vector2i(3, 3), [HIT])
		var zombie := CoreFixtures.combatant("zombie", CoreFixtures.sheet("Zombie", 30, [10, 10, 10, 10, 1, 10]), Combatant.TEAM_MONSTERS, Vector2i(5, 3), [HIT])
		zombie.creature_type = "undead"
		zombie.challenge_rating = 0.25
		var ghoul := CoreFixtures.combatant("ghoul", CoreFixtures.sheet("Ghoul", 30, [10, 10, 10, 10, 1, 10]), Combatant.TEAM_MONSTERS, Vector2i(5, 4), [HIT])
		ghoul.creature_type = "undead"
		ghoul.challenge_rating = 1.0
		var orc := CoreFixtures.combatant("orc", CoreFixtures.sheet("Orc", 30, [10, 10, 10, 10, 1, 10]), Combatant.TEAM_MONSTERS, Vector2i(4, 5), [HIT])
		orc.creature_type = "humanoid"
		var far := CoreFixtures.combatant("far", CoreFixtures.sheet("Far", 30, [10, 10, 10, 10, 1, 10]), Combatant.TEAM_MONSTERS, Vector2i(11, 11), [HIT])
		far.creature_type = "undead"
		var ally := CoreFixtures.combatant("ally", CoreFixtures.sheet("Ally", 30), Combatant.TEAM_PLAYERS, Vector2i(2, 3), [HIT])
		return [c, zombie, ghoul, orc, far, ally]
	var e := CoreFixtures.fight(make, "hero", content)
	assert_not_null(e)
	return e


func test_turn_undead_and_destroy_undead() -> void:
	var e := _undead_fight(_cleric(5))
	var res := _feature(e, "turn_undead")
	assert_true(res["ok"] == true, str(res["error"]))
	var saves := CoreFixtures.events_of(_evs(res), "save")
	assert_eq(saves.size(), 2, "the two undead within 6 tiles")
	assert_has(_evs(res), {"kind": "destroyed", "source": "hero", "target": "zombie", "feature": "destroy_undead"})
	assert_true(e.get_combatant("zombie").sheet.is_dead(), "CR 1/4 <= 1/2")
	var ghoul := e.get_combatant("ghoul")
	assert_true(ghoul.is_fleeing(), "CR 1 is turned instead")
	assert_eq(ghoul.conditions[0]["duration"], {"type": "rounds", "rounds": 10})
	assert_false(e.get_combatant("orc").has_condition("frightened"))
	assert_true(str(_feature(e, "turn_undead")["error"]).length() > 0, "action used and no uses left")
	# Damage ends the turning.
	e._deal_spell_damage(e.get_combatant("hero"), ghoul, 1, content["spells"]["fire_bolt"], {})
	assert_false(ghoul.has_condition("frightened"))
	var low := _undead_fight(_cleric(2))
	low.submit(CoreFixtures.intent("use_feature", "hero", {"feature": "turn_undead"}))
	assert_false(low.get_combatant("zombie").sheet.is_dead(), "no Destroy Undead before 5th level")
	assert_eq(Progression.destroy_undead_cr(8), 1.0)


func test_disciple_of_life_and_preserve_life() -> void:
	var s := _cleric(5)
	s.current_hp = 1
	var e := _undead_fight(s)
	var res := _cast(e, "cure_wounds", {"target": "hero", "slot_level": 2})
	var heal := CoreFixtures.first_event(_evs(res), "heal")
	assert_in_range(heal["rolled"], 2 + 10 + 4, 16 + 10 + 4, "2d8 + WIS 10 + 2 + slot 2")
	var e2 := _undead_fight(_cleric(5))
	var ally := e2.get_combatant("ally")
	ally.sheet.current_hp = 5
	assert_true(str(_feature(e2, "preserve_life", {"allocations": {"ally": 20}})["error"]).contains("half"))
	assert_true(str(_feature(e2, "preserve_life", {"allocations": {"zombie": 1}})["error"]).contains("ally"))
	res = _feature(e2, "preserve_life", {"allocations": {"ally": 10}})
	assert_true(res["ok"] == true, str(res["error"]))
	assert_eq(ally.sheet.current_hp, 15)
	assert_eq(e2.get_combatant("hero").sheet.class_resource("channel_divinity"), 0)


# --- druid / wizard ------------------------------------------------------------------

func test_arcane_and_natural_recovery() -> void:
	var s := CoreFixtures.caster("Wiz", Ability.Type.INT, [], 20)
	s.features.append("arcane_recovery")
	s.level = 5
	s.spell_slots_max = [4, 3, 2]
	s.spell_slots = [0, 0, 0]
	s.restore_class_resources()
	assert_eq(Rest.slot_recovery_options(s), {"feature": "arcane_recovery", "budget": 3, "max_slot_level": 5})
	var few: Array[int] = [2, 2]
	assert_true(Rest.recover_slots(s, few).contains("total"))
	var ok: Array[int] = [2, 1]
	assert_eq(Rest.recover_slots(s, ok), "")
	assert_eq(s.spell_slots, [1, 1, 0])
	assert_eq(Rest.recover_slots(s, [1] as Array[int]), "no slot recovery available", "once per long rest")
	Rest.long_rest(s)
	assert_eq(s.class_resource("arcane_recovery"), 1)
	var d := CoreFixtures.caster("Druid", Ability.Type.WIS, [], 20)
	d.features.append("natural_recovery")
	d.level = 2
	d.spell_slots_max = [3]
	d.spell_slots = [3]
	d.restore_class_resources()
	assert_eq(Rest.slot_recovery_options(d)["feature"], "natural_recovery")
	assert_true(Rest.recover_slots(d, [1] as Array[int]).contains("expended"))


# --- sorcerer -----------------------------------------------------------------------

func test_draconic_resilience() -> void:
	var s := CoreFixtures.sheet("Sorc", 8, [10, 14, 10, 10, 10, 10])
	s.gain_feature("draconic_resilience")
	assert_eq(s.max_hp, 9, "+1 hp per level")
	assert_eq(s.armor_class(), 15, "13 + DEX")
	assert_eq(s.level_up(), 6, "5 average + 1")
	assert_eq(s.max_hp, 15)


func test_font_of_magic_create_and_convert() -> void:
	var s := CoreFixtures.caster("Sorc", Ability.Type.CHA, [], 30)
	s.features.append("font_of_magic")
	s.level = 3
	s.spell_slots_max = [4, 2]
	s.spell_slots = [4, 2]
	s.restore_class_resources()
	var e := CoreFixtures.duel(s, [HIT], {"gob": [CoreFixtures.sheet("Gob", 30), Vector2i(8, 8), [HIT]]}, content)
	var res := _feature(e, "font_of_magic", {"mode": "create_slot", "slot_level": 2})
	assert_true(res["ok"] == true, str(res["error"]))
	assert_eq(CoreFixtures.first_event(_evs(res), "feature_used"), {"kind": "feature_used", "actor": "hero", "feature": "font_of_magic", "target": "hero", "remaining": 0, "mode": "create_slot", "slot_level": 2})
	var hero := e.get_combatant("hero")
	assert_eq(hero.sheet.slots_left(2), 3)
	assert_true(hero.bonus_action_used)
	var e2 := CoreFixtures.duel(s, [HIT], {"gob": [CoreFixtures.sheet("Gob", 30), Vector2i(8, 8), [HIT]]}, content)
	assert_true(str(_feature(e2, "font_of_magic", {"mode": "create_slot", "slot_level": 6})["error"]).contains("1..5"))
	e2.get_combatant("hero").sheet.class_resources["sorcery_points"] = 1
	res = _feature(e2, "font_of_magic", {"mode": "convert_slot", "slot_level": 1})
	assert_true(res["ok"] == true, str(res["error"]))
	assert_eq(e2.get_combatant("hero").sheet.class_resource("sorcery_points"), 2)
	assert_eq(e2.get_combatant("hero").sheet.slots_left(1), 3)


# --- warlock ------------------------------------------------------------------------

func _warlock() -> CharacterSheet:
	var s := CoreFixtures.caster("Lock", Ability.Type.CHA, ["eldritch_blast"], 30)
	s.abilities.set_score(Ability.Type.CHA, 18)
	s.features = ["pact_magic", "dark_ones_blessing", "eldritch_invocations", "pact_boon", "pact_of_the_blade"]
	s.invocations = ["agonizing_blast", "repelling_blast", "armor_of_shadows"]
	s.level = 3
	return s


func test_agonizing_and_repelling_blast() -> void:
	var e := CoreFixtures.duel(_warlock(), [HIT], {"gob": [CoreFixtures.sheet("Gob", 200), Vector2i(5, 3), [HIT]]}, content)
	var attack := e._spell_attack(e.get_combatant("hero"), content["spells"]["eldritch_blast"], 0, 0)
	assert_eq(attack["damage"], "1d10+4", "agonizing blast adds CHA")
	var res := _cast(e, "eldritch_blast", {"target": "gob"})
	assert_true(res["ok"] == true, str(res["error"]))
	if CoreFixtures.first_event(_evs(res), "attack")["hit"]:
		assert_eq(CoreFixtures.first_event(_evs(res), "pushed"), {"kind": "pushed", "target": "gob", "source": "hero", "from": [5, 3], "to": [7, 3]})


func test_armor_of_shadows_and_pact_weapon() -> void:
	var e := CoreFixtures.duel(_warlock(), [HIT], {"gob": [CoreFixtures.sheet("Gob", 200), Vector2i(4, 3), [HIT]]}, content)
	var res := _cast(e, "mage_armor", {"target": "hero"})
	assert_true(res["ok"] == true, str(res["error"]))
	assert_eq(CoreFixtures.first_event(_evs(res), "cast")["slot_level"], 0, "no slot")
	assert_eq(e.get_combatant("hero").sheet.slots_left(1), 2)
	assert_has(e.get_combatant("hero").sheet.active_buffs, "mage_armor")
	var e2 := CoreFixtures.duel(_warlock(), [HIT], {"gob": [CoreFixtures.sheet("Gob", 200), Vector2i(4, 3), [HIT]]}, content)
	res = _feature(e2, "pact_weapon")
	assert_true(res["ok"] == true, str(res["error"]))
	var hero := e2.get_combatant("hero")
	var index: int = CoreFixtures.first_event(_evs(res), "effect_applied")["attack_index"]
	assert_eq(hero.attacks[index]["name"], "Pact Weapon")
	assert_eq(hero.attacks[index]["damage"], "1d8")
	assert_true(str(_feature(e2, "pact_weapon")["error"]).length() > 0)
	var no_blade := _warlock()
	no_blade.features.erase("pact_of_the_blade")
	var e3 := CoreFixtures.duel(no_blade, [HIT], {"gob": [CoreFixtures.sheet("Gob", 200), Vector2i(4, 3), [HIT]]}, content)
	assert_true(str(_feature(e3, "pact_weapon")["error"]).contains("does not have"))


func test_dark_ones_blessing() -> void:
	var e := CoreFixtures.duel(_warlock(), [{"name": "Kill", "kind": "melee", "to_hit": 100, "damage": "50", "damage_type": "slashing"}],
		{"gob": [CoreFixtures.sheet("Gob", 5), Vector2i(4, 3), [HIT]], "orc": [CoreFixtures.sheet("Orc", 50), Vector2i(9, 9), [HIT]]}, content)
	var res := e.submit(CoreFixtures.intent("attack", "hero", {"target": "gob", "attack_index": 0}))
	if CoreFixtures.first_event(_evs(res), "attack")["hit"]:
		assert_has(_evs(res), {"kind": "temp_hp", "source": "hero", "target": "hero", "amount": 7, "temp_hp_after": 7, "feature": "dark_ones_blessing"})

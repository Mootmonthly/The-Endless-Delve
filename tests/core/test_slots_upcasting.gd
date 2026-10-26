extends TestCase
## Spell slots to 9th level, half-caster and pact tables, upcasting from
## damage_by_slot / heal_by_slot, cantrip scaling, DiceFormula, metamagic.

const HIT := {"name": "Hit", "kind": "melee", "to_hit": 100, "damage": "1", "damage_type": "slashing", "ability": "STR"}

var content: Dictionary


func before_each() -> void:
	content = CoreFixtures.content()


func _evs(res: Dictionary) -> Array:
	var evs: Array = res.get("events", [])
	return evs


func _class(extra: Dictionary) -> ClassDefinition:
	var d := {"id": "x", "display_name": "X", "hit_die": 8, "primary_abilities": ["STR", "CHA"], "saving_throws": ["WIS"],
		"armor_proficiencies": [], "weapon_proficiencies": [], "skill_choices": [], "skill_choice_count": 0, "spellcasting_ability": null}
	d.merge(extra, true)
	return ClassDefinition.from_dict(d)


func test_dice_formula() -> void:
	var f := DiceFormula.parse("2d6 + 1d8 + MOD + 3")
	assert_true(f.valid)
	assert_eq(f.dice_count(), 3)
	assert_eq(f.constant, 3)
	assert_eq(f.mod_count, 1)
	var r := f.roll(Rng.new(5), 4)
	assert_in_range(r["total"], 3 + 4 + 3, 12 + 8 + 4 + 3)
	assert_eq(len(r["rolls"]), 3)
	assert_eq(len(f.roll(Rng.new(5), 0, true)["rolls"]), 6, "critical doubles dice")
	assert_false(DiceFormula.parse("lots").valid)
	assert_false(DiceFormula.parse("").valid)
	assert_eq(DiceFormula.parse("1d8-1").constant, -1)
	# Same draws as DiceExpr for a simple expression (replays stay stable).
	assert_eq(DiceFormula.parse("3d6+2").roll(Rng.new(9))["total"], DiceExpr.parse("3d6+2").roll(Rng.new(9)).total)


func test_great_weapon_fighting_and_empowered_rerolls() -> void:
	var f := DiceFormula.parse("10d6")
	var seed_value := seed_where(func(rng: Rng) -> bool:
		var plain: Array = DiceFormula.parse("10d6").roll(rng)["rolls"]
		return plain.has(1))
	var plain: Array = f.roll(Rng.new(seed_value))["rolls"]
	var gwf: Array = f.roll(Rng.new(seed_value), 0, false, 2)["rolls"]
	assert_eq(gwf.size(), 10)
	assert_ne(plain, gwf, "low dice were rolled again")
	var emp: Array = f.roll(Rng.new(seed_value), 0, false, 0, 2)["rolls"]
	var changed := 0
	for i in range(10):
		if emp[i] != plain[i]:
			changed += 1
	assert_true(changed <= 2, "at most CHA mod dice")


func test_slot_tables_to_level_nine_half_and_pact() -> void:
	var full := _class({"spellcasting": {"ability": "INT"}, "spell_slots": {"1": [2, 0, 0], "17": [4, 3, 3, 3, 2, 1, 1, 1, 1], "20": [4, 3, 3, 3, 3, 2, 2, 1, 1]}})
	assert_eq(full.slots_for_level(1), [2], "trailing zeros dropped")
	assert_eq(full.slots_for_level(18).size(), 9)
	assert_false(full.is_half_caster())
	var half := _class({"spell_slots": {"1": [], "2": [2], "5": [4, 2]}, "prepares": true})
	assert_eq(half.spellcasting_ability, Ability.Type.CHA, "half caster ability from the primary abilities")
	assert_true(half.is_half_caster())
	assert_eq(half.slots_for_level(1), [])
	var pact := _class({"id": "warlock", "spellcasting": {"ability": "CHA"}, "spell_slots": {"1": [1], "5": [0, 0, 2]}})
	assert_eq(pact.slot_recovery, "short_rest")
	assert_eq(pact.slots_for_level(5), [0, 0, 2])
	var s := CoreFixtures.sheet("W", 20)
	s.class_id = "x"
	s.level = 4
	s.apply_class_level(half)
	assert_eq(s.spell_slots_max, [2])
	assert_eq(s.casting_ability, Ability.Type.CHA, "gains casting with its first slots")


func test_heal_by_slot_and_cantrip_by_character_level() -> void:
	var cure: SpellDefinition = content["spells"]["cure_by_slot"]
	assert_eq(cure.heal_formula(1), {"formula": "1d8+MOD", "add_mod": false})
	assert_eq(cure.heal_formula(3), {"formula": "2d8+MOD", "add_mod": false})
	var classic: SpellDefinition = content["spells"]["cure_wounds"]
	assert_eq(classic.heal_formula(3), {"formula": "1d8+1d8+1d8", "add_mod": true})
	var spark: SpellDefinition = content["spells"]["spark"]
	assert_eq(spark.damage_formula(1, 0), "1d6")
	assert_eq(spark.damage_formula(5, 0), "2d6")
	assert_eq(spark.damage_formula(20, 0), "3d6")
	var bolt: SpellDefinition = content["spells"]["guiding_bolt"]
	assert_eq(bolt.damage_formula(1, 3), "6d6", "per_slot_level_above merges dice")
	var s := CoreFixtures.caster("Cleric", Ability.Type.WIS, ["cure_by_slot"], 40)
	s.current_hp = 1
	var e := CoreFixtures.duel(s, [HIT], {"gob": [CoreFixtures.sheet("Gob", 20), Vector2i(8, 8), [HIT]]}, content)
	var res := e.submit(CoreFixtures.intent("cast", "hero", {"spell": "cure_by_slot", "target": "hero", "slot_level": 2}))
	assert_true(res["ok"] == true, str(res["error"]))
	assert_in_range(CoreFixtures.first_event(_evs(res), "heal")["rolled"], 2 + 3, 16 + 3)


func test_casting_time_and_slot_nine() -> void:
	var s := CoreFixtures.caster("W", Ability.Type.INT, ["shield_reaction", "fireball"], 40)
	s.spell_slots_max = [1, 1, 1, 1, 1, 1, 1, 1, 1]
	s.spell_slots = [1, 1, 1, 1, 1, 1, 1, 1, 1]
	var e := CoreFixtures.duel(s, [HIT], {"gob": [CoreFixtures.sheet("Gob", 200), Vector2i(8, 8), [HIT]]}, content)
	assert_true(str(e.submit(CoreFixtures.intent("cast", "hero", {"spell": "shield_reaction"}))["error"]).contains("cannot be cast"))
	var res := e.submit(CoreFixtures.intent("cast", "hero", {"spell": "fireball", "point": [8, 3], "slot_level": 9}))
	assert_true(res["ok"] == true, str(res["error"]))
	assert_eq(e.get_combatant("hero").sheet.slots_left(9), 0)


func test_metamagic_quickened_twinned_empowered() -> void:
	var s := CoreFixtures.caster("Sorc", Ability.Type.CHA, ["fire_bolt", "thunder_save"], 40)
	s.features.append("font_of_magic")
	s.level = 3
	s.restore_class_resources()
	assert_eq(s.class_resource("sorcery_points"), 3)
	s.metamagic = ["quickened_spell", "twinned_spell", "empowered_spell", "subtle_spell"]
	var foes := {"a": [CoreFixtures.sheet("A", 200), Vector2i(6, 3), [HIT]], "b": [CoreFixtures.sheet("B", 200), Vector2i(6, 5), [HIT]]}
	var e := CoreFixtures.duel(s, [HIT], foes, content)
	assert_true(str(e.submit(CoreFixtures.intent("cast", "hero", {"spell": "fire_bolt", "target": "a", "metamagic": ["subtle_spell"]}))["error"]).contains("not modelled"))
	var res := e.submit(CoreFixtures.intent("cast", "hero", {"spell": "fire_bolt", "target": "a", "metamagic": ["quickened_spell"]}))
	assert_true(res["ok"] == true, str(res["error"]))
	var hero := e.get_combatant("hero")
	assert_true(hero.bonus_action_used)
	assert_false(hero.action_used)
	assert_eq(hero.sheet.class_resource("sorcery_points"), 1)
	assert_eq(CoreFixtures.first_event(_evs(res), "cast")["metamagic"], ["quickened_spell"])
	res = e.submit(CoreFixtures.intent("cast", "hero", {"spell": "thunder_save", "target": "a", "twin_target": "b", "slot_level": 1, "metamagic": ["twinned_spell"]}))
	assert_true(res["ok"] == true, str(res["error"]))
	assert_eq(CoreFixtures.events_of(_evs(res), "save").size(), 2, "both targets save")
	assert_eq(hero.sheet.class_resource("sorcery_points"), 0)
	var e2 := CoreFixtures.duel(s, [HIT], foes, content)
	assert_true(str(e2.submit(CoreFixtures.intent("cast", "hero", {"spell": "fire_bolt", "target": "a", "twin_target": "a", "metamagic": ["twinned_spell"]}))["error"]).contains("different"))
	res = e2.submit(CoreFixtures.intent("cast", "hero", {"spell": "fire_bolt", "target": "a", "metamagic": ["empowered_spell"]}))
	assert_true(res["ok"] == true, str(res["error"]))
	assert_eq(e2.get_combatant("hero").sheet.class_resource("sorcery_points"), 2)

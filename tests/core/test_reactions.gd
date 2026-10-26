extends TestCase
## Generalised reactions: policy, reaction_used, opportunity attacks, Shield,
## Cutting Words, Protection, Counterspell, Hellish Rebuke, Uncanny Dodge,
## Stand Against the Tide, Giant Killer, Retaliation; replay of policies.

const HIT := {"name": "Hit", "kind": "melee", "to_hit": 5, "damage": "4", "damage_type": "slashing", "ability": "STR"}
const SURE := {"name": "Sure", "kind": "melee", "to_hit": 100, "damage": "4", "damage_type": "slashing", "ability": "STR"}

var content: Dictionary


func before_each() -> void:
	content = CoreFixtures.content()
	for sdef: SpellDefinition in [
		CoreFixtures.spell({"id": "shield", "display_name": "Shield", "level": 1, "casting_time": "reaction", "target": "self", "effect": {"type": "unsupported"}}),
		CoreFixtures.spell({"id": "counterspell", "display_name": "Counterspell", "level": 3, "casting_time": "reaction", "range_ft": 60, "effect": {"type": "unsupported"}}),
		CoreFixtures.spell({"id": "hellish_rebuke", "display_name": "Hellish Rebuke", "level": 1, "casting_time": "reaction", "range_ft": 60,
			"effect": {"type": "save", "save": "DEX", "damage": "2d10", "damage_type": "fire", "on_save": "half", "per_slot_level_above": "1d10"}}),
	]:
		content["spells"][sdef.id] = sdef


func _evs(res: Dictionary) -> Array:
	var evs: Array = res.get("events", [])
	return evs


func test_override_supplies_reaction_effects() -> void:
	assert_eq(content["spells"]["shield"].effect_type, "reaction")
	assert_true(content["spells"]["shield"].overridden)


func test_opportunity_attack_policy_never() -> void:
	var e := CoreFixtures.duel(CoreFixtures.sheet("Hero", 50), [SURE], {"gob": [CoreFixtures.sheet("Gob", 40), Vector2i(4, 3), [SURE]]}, content)
	assert_true(e.set_reaction_policy("gob", {"creature_left_reach": "never"}))
	var res := e.submit(CoreFixtures.intent("move", "hero", {"path": [[2, 3], [1, 3]]}))
	assert_eq(CoreFixtures.events_of(_evs(res), "opportunity_attack").size(), 0)
	assert_eq(e.intent_log[0]["type"], "reaction_policy", "logged for replay")
	var again := Encounter.replay(e.rng_seed, WalkMap.new(12, 12, true), Rect2i(0, 0, 12, 12), e.setup_snapshot(), e.intent_log, "r", content)
	assert_eq(again.get_combatant("gob").reaction_policy, {"creature_left_reach": "never"})


func test_shield_turns_a_hit_into_a_miss() -> void:
	var wiz := CoreFixtures.caster("Wiz", Ability.Type.INT, ["shield"], 30)
	var gob := CoreFixtures.sheet("Gob", 40)
	var e := CoreFixtures.duel(wiz, [SURE], {"gob": [gob, Vector2i(4, 3), [HIT]]}, content, "gob")
	assert_not_null(e)
	var hero := e.get_combatant("hero")
	# AC 10: a +5 attack hits on 5-14 and Shield (+5) makes it miss.
	for _i in range(30):
		if hero.sheet.slots_left(1) < 2:
			break
		var res := e.submit(CoreFixtures.intent("attack", "gob", {"target": "hero", "attack_index": 0}))
		var used := CoreFixtures.first_event(_evs(res), "reaction_used")
		if not used.is_empty():
			assert_eq(used["reaction"], "shield")
			assert_false(CoreFixtures.first_event(_evs(res), "attack")["hit"])
			assert_true(hero.has_buff("shield"))
			assert_eq(hero.armor_class(), 15)
			assert_eq(hero.sheet.slots_left(1), 1)
		e.end_turn()
		e.end_turn()
	assert_eq(hero.sheet.slots_left(1), 1, "Shield was cast once")
	assert_false(hero.has_buff("shield"), "it lasts until the wizard's turn starts")


func test_cutting_words_and_protection() -> void:
	var bard := CoreFixtures.sheet("Bard", 30, [10, 10, 10, 10, 10, 18], ["cutting_words", "bardic_inspiration"])
	bard.restore_class_resources()
	bard.shield_bonus = 2
	bard.fighting_styles = ["protection"]
	var e := CoreFixtures.duel(CoreFixtures.sheet("Hero", 60), [SURE], {"gob": [CoreFixtures.sheet("Gob", 40), Vector2i(4, 3), [HIT]]}, content, "gob", Vector2i(3, 3),
			{"bard": [bard, Vector2i(3, 4), [SURE]]})
	assert_not_null(e)
	var res := e.submit(CoreFixtures.intent("attack", "gob", {"target": "hero", "attack_index": 0}))
	var used := CoreFixtures.events_of(_evs(res), "reaction_used")
	assert_eq(used[0]["reaction"], "protection", "the shield bearer next to the hero protects first")
	assert_eq(CoreFixtures.first_event(_evs(res), "attack")["advantage"], "disadvantage")
	assert_eq(used.size(), 1, "one reaction per round")


func test_cutting_words_subtracts_the_die() -> void:
	var bard := CoreFixtures.sheet("Bard", 30, [10, 10, 10, 10, 10, 18], ["cutting_words", "bardic_inspiration"])
	bard.restore_class_resources()
	var foes := {"gob": [CoreFixtures.sheet("Gob", 40), Vector2i(4, 3), [HIT]]}
	var saw := false
	for s in range(1, 60):
		var e := CoreFixtures.duel(CoreFixtures.sheet("Hero", 60), [SURE], foes, content, "gob", Vector2i(3, 3), {"bard": [bard, Vector2i(2, 5), [SURE]]})
		if e == null:
			continue
		e.rng = Rng.new(s)
		var res := e.submit(CoreFixtures.intent("attack", "gob", {"target": "hero", "attack_index": 0}))
		var used := CoreFixtures.first_event(_evs(res), "reaction_used")
		if used.is_empty():
			continue
		saw = true
		assert_eq(used["reaction"], "cutting_words")
		assert_eq(used["die"], 6)
		var atk := CoreFixtures.first_event(_evs(res), "attack")
		assert_eq(atk["hit"], DictUtil.to_int(atk["total"]) >= DictUtil.to_int(atk["target_ac"]))
		assert_eq(e.get_combatant("bard").sheet.class_resource("bardic_inspiration"), 3)
		break
	assert_true(saw, "Cutting Words fired on some seed")


func test_counterspell_stops_a_hostile_spell() -> void:
	var foe_caster := CoreFixtures.caster("Mage", Ability.Type.INT, ["counterspell"], 30)
	foe_caster.spell_slots_max = [2, 2, 1]
	foe_caster.spell_slots = [2, 2, 1]
	var hero := CoreFixtures.caster("Hero", Ability.Type.INT, ["thunder_save", "fire_bolt"], 30)
	var e := CoreFixtures.duel(hero, [SURE], {"gob": [foe_caster, Vector2i(6, 3), [SURE]]}, content)
	var res := e.submit(CoreFixtures.intent("cast", "hero", {"spell": "thunder_save", "target": "gob"}))
	assert_true(res["ok"] == true, str(res["error"]))
	assert_eq(CoreFixtures.first_event(_evs(res), "reaction_used")["reaction"], "counterspell")
	assert_eq(CoreFixtures.first_event(_evs(res), "spell_countered"), {"kind": "spell_countered", "caster": "hero", "spell": "thunder_save", "by": "gob"})
	assert_eq(CoreFixtures.events_of(_evs(res), "save").size(), 0)
	assert_eq(e.get_combatant("hero").sheet.slots_left(1), 1, "the slot is spent")
	assert_eq(e.get_combatant("gob").sheet.slots_left(3), 0)
	# A cantrip is not countered; neither is a Subtle Spell.
	var e2 := CoreFixtures.duel(hero, [SURE], {"gob": [foe_caster, Vector2i(6, 3), [SURE]]}, content)
	res = e2.submit(CoreFixtures.intent("cast", "hero", {"spell": "fire_bolt", "target": "gob"}))
	assert_true(res["ok"] == true, str(res["error"]))
	assert_eq(CoreFixtures.events_of(_evs(res), "spell_countered").size(), 0)
	hero.features.append("font_of_magic")
	hero.metamagic = ["subtle_spell"]
	hero.class_resources["sorcery_points"] = 2
	var e3 := CoreFixtures.duel(hero, [SURE], {"gob": [foe_caster, Vector2i(6, 3), [SURE]]}, content)
	res = e3.submit(CoreFixtures.intent("cast", "hero", {"spell": "thunder_save", "target": "gob", "metamagic": ["subtle_spell"]}))
	assert_true(res["ok"] == true, str(res["error"]))
	assert_eq(CoreFixtures.events_of(_evs(res), "reaction_used").size(), 0)
	assert_eq(CoreFixtures.events_of(_evs(res), "save").size(), 1)


func test_hellish_rebuke_answers_damage() -> void:
	var warlock := CoreFixtures.caster("Lock", Ability.Type.CHA, ["hellish_rebuke"], 60)
	var gob := CoreFixtures.sheet("Gob", 80, [10, 1, 10, 10, 10, 10])
	var e := CoreFixtures.duel(warlock, [SURE], {"gob": [gob, Vector2i(4, 3), [SURE]]}, content, "gob")
	var res := e.submit(CoreFixtures.intent("attack", "gob", {"target": "hero", "attack_index": 0}))
	var used := CoreFixtures.first_event(_evs(res), "reaction_used")
	assert_eq(used["reaction"], "hellish_rebuke")
	assert_eq(used["trigger"], "damage_taken")
	var dmg := CoreFixtures.events_of(_evs(res), "damage")
	assert_eq(dmg[dmg.size() - 1]["target"], "gob")
	assert_eq(dmg[dmg.size() - 1]["spell"], "hellish_rebuke")
	e.set_reaction_policy("hero", {"hellish_rebuke": "never"})
	e.end_turn()
	e.end_turn()
	res = e.submit(CoreFixtures.intent("attack", "gob", {"target": "hero", "attack_index": 0}))
	assert_eq(CoreFixtures.events_of(_evs(res), "reaction_used").size(), 0, "policy by reaction id")


func test_uncanny_dodge_emits_reaction_used() -> void:
	var rogue := CoreFixtures.sheet("Rogue", 60, [], ["uncanny_dodge"])
	var e := CoreFixtures.duel(rogue, [SURE], {"gob": [CoreFixtures.sheet("Gob", 40), Vector2i(4, 3), [SURE]]}, content, "gob")
	var res := e.submit(CoreFixtures.intent("attack", "gob", {"target": "hero", "attack_index": 0}))
	assert_eq(CoreFixtures.first_event(_evs(res), "reaction_used")["reaction"], "uncanny_dodge")
	assert_eq(CoreFixtures.first_event(_evs(res), "damage_reduced")["amount"], 2)


func test_stand_against_the_tide_redirects_a_miss() -> void:
	var ranger := CoreFixtures.sheet("Ranger", 60, [], ["stand_against_the_tide"])
	ranger.armor_base = 99
	var foes := {"gob": [CoreFixtures.sheet("Gob", 40), Vector2i(4, 3), [HIT]], "orc": [CoreFixtures.sheet("Orc", 40), Vector2i(4, 4), [HIT]]}
	var e := CoreFixtures.duel(ranger, [SURE], foes, content, "gob")
	assert_not_null(e)
	var res := e.submit(CoreFixtures.intent("attack", "gob", {"target": "hero", "attack_index": 0}))
	var used := CoreFixtures.first_event(_evs(res), "reaction_used")
	assert_eq(used["reaction"], "stand_against_the_tide")
	assert_eq(used["target"], "orc")
	var attacks := CoreFixtures.events_of(_evs(res), "attack")
	assert_eq(attacks[1]["target"], "orc")


func test_giant_killer_and_retaliation() -> void:
	var ranger := CoreFixtures.sheet("Ranger", 60, [], ["giant_killer"])
	var ogre := CoreFixtures.sheet("Ogre", 60)
	ogre.size = "large"
	var e := CoreFixtures.duel(ranger, [SURE], {"gob": [ogre, Vector2i(4, 3), [SURE]]}, content, "gob")
	var res := e.submit(CoreFixtures.intent("attack", "gob", {"target": "hero", "attack_index": 0}))
	assert_eq(CoreFixtures.first_event(_evs(res), "reaction_used")["reaction"], "giant_killer")
	assert_eq(CoreFixtures.events_of(_evs(res), "attack")[1]["attacker"], "hero")
	var berserker := CoreFixtures.sheet("Berserker", 60, [], ["retaliation"])
	var e2 := CoreFixtures.duel(berserker, [SURE], {"gob": [CoreFixtures.sheet("Gob", 40), Vector2i(4, 3), [SURE]]}, content, "gob")
	res = e2.submit(CoreFixtures.intent("attack", "gob", {"target": "hero", "attack_index": 0}))
	assert_eq(CoreFixtures.first_event(_evs(res), "reaction_used")["reaction"], "retaliation")

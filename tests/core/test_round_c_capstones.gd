extends TestCase
## Round C item 9: class features for levels 13-20 and the capstones:
## Persistent Rage (and the rage's inactivity rule), Indomitable Might,
## Primal Champion, Peerless Skill, Stroke of Luck, Foe Slayer, Quivering
## Palm, Hurl Through Hell, Holy Nimbus, Overchannel, Spell Mastery,
## Signature Spells, Thief's Reflexes, Eldritch Master.

const SURE := {"name": "Sure", "kind": "melee", "to_hit": 100, "damage": "4", "damage_type": "slashing", "ability": "STR"}
const NEVER := {"name": "Never", "kind": "melee", "to_hit": -100, "damage": "4", "damage_type": "slashing", "ability": "STR"}
const PUNCH := {"name": "Unarmed Strike", "kind": "melee", "to_hit": 100, "damage": "1d4", "damage_type": "bludgeoning", "ability": "STR", "unarmed": true}

var content: Dictionary


func before_each() -> void:
	content = CoreFixtures.content()
	for d: Dictionary in [
		{"id": "arc_bolt", "display_name": "Arc Bolt", "level": 2, "classes": ["wizard"], "effect": {"type": "save", "save": "DEX", "damage": "4d6", "damage_type": "lightning", "on_save": "half"}},
		{"id": "storm_ball", "display_name": "Storm Ball", "level": 3, "classes": ["wizard"], "effect": {"type": "spell_attack", "damage": "3d6", "damage_type": "lightning"}},
	]:
		var sdef := CoreFixtures.spell(d)
		content["spells"][sdef.id] = sdef


func _evs(res: Dictionary) -> Array:
	var evs: Array = res.get("events", [])
	return evs


func _gob(hp: int = 200) -> CharacterSheet:
	return CoreFixtures.sheet("Gob", hp, [1, 1, 1, 1, 1, 1])


func _fight(hero: CharacterSheet, attacks: Array[Dictionary] = [SURE], foes: Dictionary = {}, first: String = "hero") -> Encounter:
	var f := foes if not foes.is_empty() else {"gob": [_gob(), Vector2i(4, 3), [SURE]]}
	var e := CoreFixtures.duel(hero, attacks, f, content, first)
	assert_not_null(e)
	return e


func _until(e: Encounter, id: String) -> void:
	for _i in range(40):
		if e.current_actor() == null or e.current_actor().id == id:
			return
		e.end_turn()


func test_rage_ends_when_idle_unless_persistent() -> void:
	var barb := CoreFixtures.sheet("Barb", 60, [], ["rage"])
	barb.level = 15
	var e := _fight(barb, [SURE], {"gob": [_gob(), Vector2i(9, 9), [NEVER]]})
	e.submit(CoreFixtures.intent("use_feature", "hero", {"feature": "rage"}))
	_until(e, "gob")
	_until(e, "hero")
	var hero := e.get_combatant("hero")
	assert_false(hero.raging, "no attack, no damage: the rage ends")
	var ended := CoreFixtures.events_of(e.events, "effect_ended")
	assert_eq(ended.back()["reason"], "inactive")
	barb.features.append("persistent_rage")
	e = _fight(barb, [SURE], {"gob": [_gob(), Vector2i(9, 9), [NEVER]]})
	e.submit(CoreFixtures.intent("use_feature", "hero", {"feature": "rage"}))
	_until(e, "gob")
	_until(e, "hero")
	assert_true(e.get_combatant("hero").raging, "Persistent Rage")


func test_indomitable_might_and_primal_champion() -> void:
	var barb := CoreFixtures.sheet("Barb", 60, [18, 10, 16, 10, 10, 10], ["indomitable_might"])
	barb.level = 20
	var e := _fight(barb)
	var res := e.ability_check(e.get_combatant("hero"), Ability.Type.STR, Skill.Type.ATHLETICS, -1, "test")
	assert_true(int(res["total"]) >= 18, "at least the Strength score")
	var hp := barb.max_hp
	barb.gain_feature("primal_champion")
	assert_eq([barb.abilities.get_score(Ability.Type.STR), barb.abilities.get_score(Ability.Type.CON)], [22, 20])
	assert_eq(barb.max_hp, hp + 2 * 20, "CON +2 modifier for 20 levels")
	var strong := CoreFixtures.sheet("Strong", 60, [22, 10, 10, 10, 10, 10])
	strong.gain_feature("primal_champion")
	assert_eq(strong.abilities.get_score(Ability.Type.STR), 24, "capped at 24")


func test_peerless_skill_and_stroke_of_luck_on_checks() -> void:
	var bard := CoreFixtures.sheet("Bard", 40, [1, 1, 1, 1, 1, 10], ["bardic_inspiration", "peerless_skill"])
	bard.level = 14
	bard.restore_class_resources()
	var e := _fight(bard)
	var res := e.ability_check(e.get_combatant("hero"), Ability.Type.STR, -1, 40, "test")
	var mod := CoreFixtures.first_event(e.events_since(0), "check_modified")
	assert_eq(mod["feature"], "peerless_skill")
	assert_false(res["success"])
	var rogue := CoreFixtures.sheet("Rogue", 40, [10, 10, 10, 10, 10, 10], ["stroke_of_luck"])
	rogue.level = 20
	rogue.restore_class_resources()
	e = _fight(rogue)
	var hero := e.get_combatant("hero")
	res = e.ability_check(hero, Ability.Type.STR, -1, 20, "test")
	assert_true(res["success"] == true, "the d20 counts as a 20")
	assert_eq(hero.sheet.class_resource("stroke_of_luck"), 0)


func test_stroke_of_luck_turns_a_miss_into_a_hit() -> void:
	var rogue := CoreFixtures.sheet("Rogue", 40, [], ["stroke_of_luck"])
	rogue.level = 20
	rogue.restore_class_resources()
	var e := _fight(rogue, [NEVER])
	var res := e.submit(CoreFixtures.intent("attack", "hero", {"target": "gob", "attack_index": 0}))
	assert_eq(CoreFixtures.first_event(_evs(res), "feature_used")["feature"], "stroke_of_luck")
	assert_eq(CoreFixtures.first_event(_evs(res), "damage")["amount"], 4)
	assert_eq(e.get_combatant("hero").sheet.class_resource("stroke_of_luck"), 0)


func test_foe_slayer_adds_wisdom_once_per_turn() -> void:
	var ranger := CoreFixtures.sheet("Ranger", 40, [10, 10, 10, 10, 18, 10], ["foe_slayer", "extra_attack"])
	ranger.level = 20
	var e := _fight(ranger)
	var res := e.submit(CoreFixtures.intent("attack", "hero", {"target": "gob", "attack_index": 0}))
	var used := CoreFixtures.first_event(_evs(res), "feature_used")
	assert_eq([used["feature"], used["mode"]], ["foe_slayer", "damage"])
	assert_eq(CoreFixtures.first_event(_evs(res), "damage")["amount"], 8, "4 + WIS 4")
	res = e.submit(CoreFixtures.intent("attack", "hero", {"target": "gob", "attack_index": 0}))
	assert_eq(CoreFixtures.first_event(_evs(res), "damage")["amount"], 4, "once per turn")


func test_quivering_palm_sets_and_triggers() -> void:
	var monk := CoreFixtures.sheet("Monk", 60, [10, 10, 10, 10, 20, 10], ["ki", "quivering_palm"])
	monk.level = 17
	monk.restore_class_resources()
	var e := _fight(monk, [PUNCH])
	var hero := e.get_combatant("hero")
	var ki := hero.sheet.class_resource("ki")
	assert_true(str(e.submit(CoreFixtures.intent("use_feature", "hero", {"feature": "quivering_palm"}))["error"]).contains("vibrations"))
	var res := e.submit(CoreFixtures.intent("attack", "hero", {"target": "gob", "attack_index": 0, "quivering_palm": true}))
	assert_true(res["ok"] == true, str(res["error"]))
	assert_eq(hero.sheet.class_resource("ki"), ki - 3)
	assert_eq(hero.quivering_target, "gob")
	_until(e, "gob")
	_until(e, "hero")
	res = e.submit(CoreFixtures.intent("use_feature", "hero", {"feature": "quivering_palm"}))
	assert_true(res["ok"] == true, str(res["error"]))
	assert_false(e.get_combatant("gob").is_alive(), "CON 1 fails: reduced to 0 hit points")


func test_hurl_through_hell_banishes_and_returns_with_damage() -> void:
	var lock := CoreFixtures.sheet("Lock", 60, [], ["hurl_through_hell"])
	lock.level = 14
	lock.restore_class_resources()
	var e := _fight(lock)
	var res := e.submit(CoreFixtures.intent("attack", "hero", {"target": "gob", "attack_index": 0, "hurl_through_hell": true}))
	assert_true(res["ok"] == true, str(res["error"]))
	assert_eq(CoreFixtures.first_event(_evs(res), "banished")["target"], "gob")
	var start := e.events.size()
	e.end_turn()
	_until(e, "hero")
	assert_true(CoreFixtures.events_of(e.events_since(start), "returned").is_empty(), "gone until the end of the warlock's next turn")
	e.end_turn()
	var back := e.events_since(start)
	assert_false(CoreFixtures.events_of(back, "returned").is_empty())
	var hurt: Array[Dictionary] = []
	for d in CoreFixtures.events_of(back, "damage"):
		if str(d.get("feature", "")) == "hurl_through_hell":
			hurt.append(d)
	assert_eq(hurt.size(), 1)
	assert_true(str(e.submit(CoreFixtures.intent("attack", "hero", {"target": "gob", "attack_index": 0, "hurl_through_hell": true}))["error"]) != "", "once per long rest")


func test_holy_nimbus_burns_hostiles_starting_nearby() -> void:
	var pal := CoreFixtures.sheet("Pal", 60, [], ["holy_nimbus"])
	pal.level = 20
	pal.restore_class_resources()
	var e := _fight(pal)
	var res := e.submit(CoreFixtures.intent("use_feature", "hero", {"feature": "holy_nimbus"}))
	assert_true(res["ok"] == true, str(res["error"]))
	assert_true(CoreFixtures.first_event(_evs(res), "tile_effect_created")["lit"] == true)
	var start := e.events.size()
	e.end_turn()
	var burns := CoreFixtures.events_of(e.events_since(start), "damage")
	assert_false(burns.is_empty())
	assert_eq([burns[0]["target"], burns[0]["amount"], burns[0]["type"]], ["gob", 10, "radiant"])
	assert_true(e.get_combatant("hero").buff_list("adv_saves_vs_types").has("undead"))


func test_overchannel_maximizes_then_hurts() -> void:
	var wiz := CoreFixtures.caster("Wiz", Ability.Type.INT, ["arc_bolt"], 80)
	wiz.features.append("overchannel")
	wiz.level = 14
	var e := _fight(wiz)
	var res := e.submit(CoreFixtures.intent("cast", "hero", {"spell": "arc_bolt", "target": "gob", "overchannel": true}))
	assert_true(res["ok"] == true, str(res["error"]))
	var dmg := CoreFixtures.first_event(_evs(res), "damage")
	assert_true(int(dmg["amount"]) in [24, 12], "4d6 at its maximum (half on a save)")
	assert_true(CoreFixtures.first_event(_evs(res), "cast")["overchannel"] == true)
	_until(e, "gob")
	_until(e, "hero")
	res = e.submit(CoreFixtures.intent("cast", "hero", {"spell": "arc_bolt", "target": "gob", "overchannel": true}))
	var self_hit: Array[Dictionary] = []
	for d in CoreFixtures.events_of(_evs(res), "damage"):
		if d["target"] == "hero":
			self_hit.append(d)
	assert_eq(self_hit.size(), 1, "the second use costs 2d12 per spell level")
	assert_in_range(int(self_hit[0]["amount"]), 4, 48)
	assert_true(str(e.submit(CoreFixtures.intent("cast", "hero", {"spell": "fire_bolt", "target": "gob", "overchannel": true}))["error"]) != "")


func test_spell_mastery_and_signature_spells_cast_free() -> void:
	var wiz := CoreFixtures.caster("Wiz", Ability.Type.INT, ["arc_bolt", "storm_ball"], 80)
	wiz.level = 20
	wiz.spell_slots_max = [4, 3, 3]
	wiz.spell_slots = [4, 3, 3]
	wiz.spell_mastery = ["arc_bolt"]
	wiz.signature_spells = ["storm_ball"]
	wiz.restore_class_resources()
	var e := _fight(wiz)
	var hero := e.get_combatant("hero")
	var res := e.submit(CoreFixtures.intent("cast", "hero", {"spell": "arc_bolt", "target": "gob"}))
	assert_eq([CoreFixtures.first_event(_evs(res), "cast")["free_cast"], hero.sheet.spell_slots[1]], ["spell_mastery", 3])
	_until(e, "gob")
	_until(e, "hero")
	res = e.submit(CoreFixtures.intent("cast", "hero", {"spell": "arc_bolt", "target": "gob", "slot_level": 3}))
	assert_eq(hero.sheet.spell_slots[2], 2, "upcasting spends a slot")
	_until(e, "gob")
	_until(e, "hero")
	res = e.submit(CoreFixtures.intent("cast", "hero", {"spell": "storm_ball", "target": "gob"}))
	assert_eq(CoreFixtures.first_event(_evs(res), "cast")["free_cast"], "signature_spell")
	assert_eq(hero.sheet.spell_slots[2], 2)
	_until(e, "gob")
	_until(e, "hero")
	res = e.submit(CoreFixtures.intent("cast", "hero", {"spell": "storm_ball", "target": "gob"}))
	assert_false(CoreFixtures.first_event(_evs(res), "cast").has("free_cast"), "once per short rest")
	assert_eq(hero.sheet.spell_slots[2], 1)
	Rest.short_rest(hero.sheet, 0, Rng.new(1))
	assert_eq(hero.sheet.class_resource(CharacterSheet.SIGNATURE_PREFIX + "storm_ball"), 1)


func test_wizard_level_up_offers_mastery_and_signature() -> void:
	var c := ContentLoader.cache()
	var classes: Dictionary = c["classes"]
	var cls: ClassDefinition = classes["wizard"]
	var skills: Array[int] = []
	for i in range(cls.skill_choice_count):
		skills.append(cls.skill_choices[i])
	var scores := AbilityScores.new()
	scores.set_all([10, 14, 14, 18, 12, 10])
	var w := CharacterBuilder.create("W", cls, null, scores, skills, null, c)
	w.level = 17
	w.subclass_id = cls.subclass_id
	w.spells_known.append_array(["magic_missile", "shield", "misty_step", "web", "fireball", "fly", "counterspell"])
	w.xp = Experience.xp_for_level(18)
	var mastery: Dictionary = {}
	for entry: Dictionary in LevelUp.choices(w, c)["choices"]:
		if entry["type"] == LevelUp.CHOICE_SPELL_MASTERY:
			mastery = entry
	assert_false(mastery.is_empty())
	var pair: Array = (mastery["options"] as Array).slice(0, 2)
	var levels: Array[int] = []
	for id: Variant in pair:
		levels.append((c["spells"][str(id)] as SpellDefinition).level)
	levels.sort()
	assert_eq(levels, [1, 2] as Array[int], "the first two options are a valid pair")
	var bad: Dictionary = {"hp": "average", "spell_mastery": ["magic_missile", "shield"]}
	var ch := LevelUp.choices(w, c)
	var learn: Array = []
	for id_v: Variant in ch["spell_options"]:
		if (c["spells"][str(id_v)] as SpellDefinition).level > 0 and learn.size() < int(ch["spells_to_learn"]):
			learn.append(str(id_v))
	bad["learn_spells"] = learn
	assert_true(LevelUp.apply(w, bad, c, null).contains("Spell Mastery"))
	bad["spell_mastery"] = ["shield", "web"]
	assert_eq(LevelUp.apply(w, bad, c, null), "")
	assert_eq(w.spell_mastery, ["shield", "web"] as Array[String])


func test_thiefs_reflexes_takes_two_turns_in_the_first_round() -> void:
	var thief := CoreFixtures.sheet("Thief", 40, [], ["thiefs_reflexes"])
	thief.level = 17
	var e := _fight(thief)
	var res := e.submit(CoreFixtures.intent("end_turn", "hero"))
	var extra := CoreFixtures.first_event(_evs(res), "extra_turn")
	assert_eq(extra["source"], "thiefs_reflexes")
	assert_eq(e.current_actor().id, "hero")
	e.end_turn()
	assert_eq(e.current_actor().id, "gob")
	_until(e, "hero")
	res = e.submit(CoreFixtures.intent("end_turn", "hero"))
	assert_true(CoreFixtures.events_of(_evs(res), "extra_turn").is_empty(), "only in the first round")


func test_eldritch_master_restores_pact_slots_once() -> void:
	var lock := CoreFixtures.sheet("Lock", 40, [], ["eldritch_master"])
	lock.level = 20
	lock.restore_class_resources()
	lock.spell_slots_max = [0, 0, 0, 0, 4]
	lock.spell_slots = [0, 0, 0, 0, 0]
	assert_eq(Rest.eldritch_master(lock), "")
	assert_eq(lock.spell_slots[4], 4)
	assert_ne(Rest.eldritch_master(lock), "", "once per long rest")
	Rest.long_rest(lock)
	assert_eq(lock.class_resource("eldritch_master"), 1)


func test_round_c_features_replay_through_json() -> void:
	var hero := CoreFixtures.sheet("Hero", 80, [16, 10, 14, 10, 18, 10], ["rage", "stroke_of_luck", "foe_slayer", "thiefs_reflexes", "holy_nimbus", "hurl_through_hell", "ki", "quivering_palm"])
	hero.level = 20
	hero.restore_class_resources()
	var make := func() -> Array:
		return [CoreFixtures.combatant("hero", CharacterSheet.from_dict(hero.to_dict()), Combatant.TEAM_PLAYERS, Vector2i(3, 3), [SURE, NEVER, PUNCH]),
			CoreFixtures.combatant("gob", CharacterSheet.from_dict(_gob().to_dict()), Combatant.TEAM_MONSTERS, Vector2i(4, 3), [SURE]),
			CoreFixtures.combatant("orc", CharacterSheet.from_dict(_gob().to_dict()), Combatant.TEAM_MONSTERS, Vector2i(4, 4), [SURE])]
	var e := CoreFixtures.fight(make, "hero", content)
	assert_not_null(e)
	e.set_light(Encounter.LIGHT_DIM)
	e.submit(CoreFixtures.intent("use_feature", "hero", {"feature": "rage"}))
	e.submit(CoreFixtures.intent("attack", "hero", {"target": "gob", "attack_index": 1}))
	e.submit(CoreFixtures.intent("end_turn", "hero"))
	e.submit(CoreFixtures.intent("use_feature", "hero", {"feature": "holy_nimbus"}))
	e.submit(CoreFixtures.intent("end_turn", "hero"))
	_until(e, "hero")
	e.submit(CoreFixtures.intent("attack", "hero", {"target": "orc", "attack_index": 2, "quivering_palm": true}))
	e.submit(CoreFixtures.intent("end_turn", "hero"))
	_until(e, "hero")
	e.submit(CoreFixtures.intent("attack", "hero", {"target": "gob", "attack_index": 0, "hurl_through_hell": true}))
	e.submit(CoreFixtures.intent("end_turn", "hero"))
	_until(e, "hero")
	e.submit(CoreFixtures.intent("use_feature", "hero", {"feature": "quivering_palm"}))
	var setup: Array[Dictionary] = []
	for d in e.setup_snapshot():
		setup.append(JSON.parse_string(JSON.stringify(d)))
	var entries: Array[Dictionary] = []
	for d in e.intent_log:
		entries.append(JSON.parse_string(JSON.stringify(d)))
	var m := WalkMap.new(12, 12, true)
	m.set_walkable(Vector2i(6, 6), false)
	var again := Encounter.replay(e.rng_seed, m, e.region, setup, entries, "t", content)
	assert_eq(JSON.stringify(again.events), JSON.stringify(e.events))
	var kinds := CoreFixtures.kinds(e.events)
	for k: String in ["extra_turn", "banished", "tile_effect_created", "light_changed"]:
		assert_has(kinds, k)

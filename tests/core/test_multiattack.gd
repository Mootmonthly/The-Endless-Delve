extends TestCase
## Several attacks per Attack action (Extra Attack, Multiattack), Action
## Surge, two-weapon fighting, Frenzy, and MonsterBrain's multiattack plans.

const HIT := {"name": "Hit", "kind": "melee", "to_hit": 100, "damage": "1", "damage_type": "slashing", "ability": "STR"}

var content: Dictionary


func before_each() -> void:
	content = CoreFixtures.content()


func _evs(res: Dictionary) -> Array:
	var evs: Array = res.get("events", [])
	return evs


func _atk(e: Encounter, actor: String, target: String, index: int = 0, fields: Dictionary = {}) -> Dictionary:
	var f := {"target": target, "attack_index": index}
	f.merge(fields)
	return e.submit(CoreFixtures.intent("attack", actor, f))


func _duel(hero: CharacterSheet, attacks: Array[Dictionary] = [HIT]) -> Encounter:
	var e := CoreFixtures.duel(hero, attacks, {"gob": [CoreFixtures.sheet("Gob", 200), Vector2i(4, 3), [HIT]]}, content)
	assert_not_null(e)
	return e


func test_extra_attack_gives_two_attacks_per_action() -> void:
	var s := CoreFixtures.sheet("Fighter", 40, [], ["extra_attack"])
	assert_eq(s.attacks_per_action(), 2)
	var e := _duel(s)
	var hero := e.get_combatant("hero")
	assert_eq(hero.attacks_per_action, 2)
	assert_true(_atk(e, "hero", "gob")["ok"] == true)
	assert_eq(hero.attacks_remaining, 1)
	assert_true(e.submit(CoreFixtures.intent("move", "hero", {"path": [[3, 4]]}))["ok"] == true, "moving between attacks")
	assert_true(_atk(e, "hero", "gob")["ok"] == true, "second attack")
	assert_true(str(_atk(e, "hero", "gob")["error"]).contains("already used its action"))
	var plain := _duel(CoreFixtures.sheet("Plain", 40))
	assert_true(_atk(plain, "hero", "gob")["ok"] == true)
	assert_false(_atk(plain, "hero", "gob")["ok"] == true)


func test_extra_attack_from_class_table() -> void:
	var cls := ClassDefinition.from_dict({"id": "fighter", "display_name": "F", "hit_die": 10, "primary_abilities": ["STR"],
		"saving_throws": ["STR"], "armor_proficiencies": [], "weapon_proficiencies": [], "skill_choices": [], "skill_choice_count": 0,
		"spellcasting_ability": null, "tables": {"extra_attacks": {"1": 0, "5": 1, "11": 2, "20": 3}}})
	assert_eq(cls.table_int("extra_attacks", 11), 2)
	assert_eq(cls.table_int("extra_attacks", 19), 2)
	assert_eq(cls.table_int("extra_attacks", 20), 3)
	assert_eq(cls.table_int("missing", 3, 7), 7)


func test_action_surge_grants_another_action() -> void:
	var s := CoreFixtures.sheet("Fighter", 40, [], ["action_surge"])
	assert_eq(s.class_resource("action_surge"), 1)
	var e := _duel(s)
	assert_true(_atk(e, "hero", "gob")["ok"] == true)
	var res := e.submit(CoreFixtures.intent("use_feature", "hero", {"feature": "action_surge"}))
	assert_true(res["ok"] == true, str(res["error"]))
	assert_eq(CoreFixtures.first_event(_evs(res), "feature_used"), {"kind": "feature_used", "actor": "hero", "feature": "action_surge", "target": "hero", "remaining": 0})
	var hero := e.get_combatant("hero")
	assert_false(hero.action_used)
	assert_false(hero.bonus_action_used, "action surge is free")
	assert_true(_atk(e, "hero", "gob")["ok"] == true, "the surged action")
	assert_true(str(e.submit(CoreFixtures.intent("use_feature", "hero", {"feature": "action_surge"}))["error"]).contains("no uses"))
	Rest.short_rest(e.get_combatant("hero").sheet, 0, Rng.new(1))
	assert_eq(hero.sheet.class_resource("action_surge"), 1, "short rest")


func test_two_weapon_fighting_off_hand_attack() -> void:
	var s := CoreFixtures.sheet("Rogue", 40, [10, 16, 10, 10, 10, 10])
	s.add_item("shortsword")
	s.add_item("dagger")
	assert_eq(s.equip("shortsword", "main_hand", content), "")
	assert_eq(s.equip("dagger", "off_hand", content), "")
	var off: Dictionary = s.attacks[s.attacks.size() - 1]
	assert_eq(off["off_hand"], true)
	assert_eq(off["name"], "Dagger (off hand)")
	assert_eq(off["damage"], "1d4", "no ability modifier to off-hand damage")
	s.fighting_styles.append("two_weapon_fighting")
	s.rebuild_attacks(content)
	assert_eq(s.attacks[s.attacks.size() - 1]["damage"], "1d4+3", "Two-Weapon Fighting style")
	var off_index := s.attacks.size() - 1
	var e := _duel(s, [])
	assert_true(str(_atk(e, "hero", "gob", off_index)["error"]).contains("bonus action"))
	assert_true(str(_atk(e, "hero", "gob", off_index, {"bonus": true})["error"]).contains("follows the Attack action"))
	assert_true(_atk(e, "hero", "gob", 0)["ok"] == true)
	var res := _atk(e, "hero", "gob", off_index, {"bonus": true})
	assert_true(res["ok"] == true, str(res["error"]))
	assert_eq(CoreFixtures.first_event(_evs(res), "attack")["bonus_source"], "two_weapon_fighting")
	assert_true(e.get_combatant("hero").bonus_action_used)
	var heavy := CoreFixtures.sheet("H", 40)
	heavy.add_item("longsword")
	heavy.add_item("dagger")
	heavy.equip("longsword", "main_hand", content)
	heavy.equip("dagger", "off_hand", content)
	for a in heavy.attacks:
		assert_false(a.get("off_hand", false) == true, "the main-hand weapon must be light too")


func test_frenzy_bonus_attack_from_the_next_turn() -> void:
	var s := CoreFixtures.sheet("Berserker", 60, [], ["rage", "frenzy"])
	var e := _duel(s)
	var res := e.submit(CoreFixtures.intent("use_feature", "hero", {"feature": "rage", "frenzy": true}))
	assert_true(res["ok"] == true, str(res["error"]))
	assert_has(_evs(res), {"kind": "effect_applied", "source": "hero", "target": "hero", "effect": "frenzy"})
	assert_true(_atk(e, "hero", "gob")["ok"] == true)
	e.end_turn()
	while e.current_actor().id != "hero":
		e.end_turn()
	assert_true(_atk(e, "hero", "gob")["ok"] == true)
	res = _atk(e, "hero", "gob", 0, {"bonus": true})
	assert_true(res["ok"] == true, str(res["error"]))
	assert_eq(CoreFixtures.first_event(_evs(res), "attack")["bonus_source"], "frenzy")
	var no := _duel(CoreFixtures.sheet("B", 60, [], ["rage"]))
	assert_true(str(no.submit(CoreFixtures.intent("use_feature", "hero", {"feature": "rage", "frenzy": true}))["error"]).contains("frenzy"))


func _ogre_def(multi: Array) -> MonsterDefinition:
	return MonsterDefinition.from_dict({"id": "brute", "display_name": "Brute", "armor_class": 10, "hit_points": 50, "hit_dice": "6d10",
		"speed": 30, "abilities": {"STR": 18, "DEX": 10, "CON": 14, "INT": 6, "WIS": 10, "CHA": 6}, "challenge_rating": 2, "xp": 450,
		"creature_type": "giant", "multiattack": multi,
		"attacks": [{"name": "Bite", "to_hit": 100, "damage": "3", "damage_type": "piercing"}, {"name": "Claw", "to_hit": 100, "damage": "2", "damage_type": "slashing"},
			{"name": "Rock", "kind": "ranged", "to_hit": 100, "damage": "3", "damage_type": "bludgeoning", "range_ft": [30, 120]}]})


func _monster_fight(def: MonsterDefinition, hero_pos: Vector2i = Vector2i(4, 3), second_hero: bool = false) -> Encounter:
	var make := func() -> Array:
		var all: Array = []
		all.append(CoreFixtures.combatant("hero", CoreFixtures.sheet("Hero", 3), Combatant.TEAM_PLAYERS, hero_pos, [HIT]))
		if second_hero:
			all.append(CoreFixtures.combatant("ally", CoreFixtures.sheet("Ally", 30), Combatant.TEAM_PLAYERS, Vector2i(3, 4), [HIT]))
		var m := Combatant.from_monster("brute", def, Combatant.TEAM_MONSTERS, Rng.new(1))
		m.position = Vector2i(3, 3)
		all.append(m)
		return all
	var e := CoreFixtures.fight(make, "brute", content)
	assert_not_null(e)
	return e


func test_monster_multiattack_definition_and_combatant() -> void:
	var def := _ogre_def(["Bite", "Claw"])
	assert_eq(def.multiattack, ["Bite", "Claw"])
	var e := _monster_fight(def)
	var brute := e.get_combatant("brute")
	assert_eq(brute.attacks_per_action, 2)
	assert_eq(brute.creature_type, "giant")
	assert_eq(brute.challenge_rating, 2.0)
	var again := Combatant.from_setup_dict(brute.to_setup_dict())
	assert_eq(again.multiattack, ["Bite", "Claw"])
	assert_eq(again.attacks_per_action, 2)
	assert_eq(again.creature_type, "giant")


func test_brain_uses_every_multiattack_attack_and_retargets() -> void:
	var e := _monster_fight(_ogre_def(["Bite", "Claw"]), Vector2i(4, 3), true)
	var plan := MonsterBrain.decide(e, "brute")
	var types: Array = plan.map(func(i: Dictionary) -> String: return str(i["type"]))
	assert_eq(types, ["attack", "attack", "end_turn"])
	assert_eq(plan[0]["attack_index"], 0, "Bite")
	assert_eq(plan[1]["attack_index"], 1, "Claw")
	assert_eq(plan[1]["retarget"], true)
	var first: String = plan[0]["target"]
	var all_events: Array = []
	for intent in plan:
		var res := e.submit(intent)
		assert_true(res["ok"] == true, str(res["error"]))
		all_events.append_array(_evs(res))
	var attacks := CoreFixtures.events_of(all_events, "attack")
	assert_eq(attacks.size(), 2)
	assert_eq(first, "hero", "the weakest adjacent hostile")
	if attacks[0]["hit"]:
		assert_eq(attacks[1]["target"], "ally", "the follow-up switched to a conscious hostile")
	# Replays identically (retarget is decided from the logged intent).
	var again := Encounter.replay(e.rng_seed, e.walk_map, e.region, e.setup_snapshot(), e.intent_log, "r", content)
	assert_eq(again.events, e.events)


func test_brain_ranged_multiattack_and_plain_extra_attacks() -> void:
	var e := _monster_fight(_ogre_def(["Rock", "Rock"]), Vector2i(9, 3))
	var brute := e.get_combatant("brute")
	brute.movement_remaining = 0
	var plan := MonsterBrain.decide(e, "brute")
	assert_eq(plan[0]["attack_index"], 2)
	assert_eq(plan[1]["attack_index"], 2)
	var def := _ogre_def([])
	var e2 := _monster_fight(def)
	e2.get_combatant("brute").attacks_per_action = 3
	plan = MonsterBrain.decide(e2, "brute")
	assert_eq(plan.size(), 4, "three attacks and end_turn")

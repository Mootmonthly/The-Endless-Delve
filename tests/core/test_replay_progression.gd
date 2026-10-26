extends TestCase
## Replays stay identical with the progression intents and events: extra
## attacks, smite / stun / technique fields, area spells with points and
## sculpting, metamagic, concentration, conditions, features with modes.

const HIT := {"name": "Hit", "kind": "melee", "to_hit": 5, "damage": "1d6+2", "damage_type": "slashing", "ability": "STR"}


func _round_trip(v: Variant) -> Variant:
	return JSON.parse_string(JSON.stringify(v))


func test_progression_fight_replays_identically_through_json() -> void:
	var content := CoreFixtures.content()
	var make := func() -> Array:
		var monk := CoreFixtures.sheet("Monk", 40, [10, 16, 10, 10, 16, 10], ["martial_arts", "ki", "stunning_strike", "open_hand_technique", "extra_attack"])
		monk.level = 5
		monk.restore_class_resources()
		var wiz := CoreFixtures.caster("Wiz", Ability.Type.INT, ["fireball", "hold_person", "fire_bolt"], 30)
		wiz.features.append_array(["sculpt_spells", "font_of_magic"])
		wiz.metamagic = ["quickened_spell"]
		wiz.level = 5
		wiz.spell_slots_max = [4, 3, 2]
		wiz.spell_slots = [4, 3, 2]
		wiz.restore_class_resources()
		var a := CoreFixtures.combatant("monk", monk, Combatant.TEAM_PLAYERS, Vector2i(3, 3), [HIT])
		var b := CoreFixtures.combatant("wiz", wiz, Combatant.TEAM_PLAYERS, Vector2i(1, 1), [HIT])
		var m1 := CoreFixtures.combatant("orc", CoreFixtures.sheet("Orc", 60), Combatant.TEAM_MONSTERS, Vector2i(4, 3), [HIT, HIT])
		m1.attacks_per_action = 2
		var m2 := CoreFixtures.combatant("gob", CoreFixtures.sheet("Gob", 40), Combatant.TEAM_MONSTERS, Vector2i(5, 4), [HIT])
		return [a, b, m1, m2]
	var e := CoreFixtures.fight(make, "monk", content)
	assert_not_null(e)
	var accepted := 0
	for round_index in range(6):
		if e.state != Encounter.State.ACTIVE:
			break
		for _turn in range(4):
			if e.state != Encounter.State.ACTIVE:
				break
			var actor := e.current_actor()
			var plan: Array[Dictionary] = []
			match actor.id:
				"monk":
					var unarmed := actor.attacks.size() - 1
					plan = [
						CoreFixtures.intent("attack", "monk", {"target": "orc", "attack_index": 0, "stun": true, "retarget": true}),
						CoreFixtures.intent("attack", "monk", {"target": "orc", "attack_index": 0, "retarget": true}),
						CoreFixtures.intent("use_feature", "monk", {"feature": "flurry_of_blows"}),
						CoreFixtures.intent("attack", "monk", {"target": "orc", "attack_index": unarmed, "bonus": true, "technique": "push", "retarget": true}),
					]
				"wiz":
					var target := "orc" if e.get_combatant("orc").is_alive() else "gob"
					var fireball := CoreFixtures.intent("cast", "wiz", {"spell": "fireball", "point": [5, 4], "slot_level": 3, "sculpt": ["monk"]})
					var hold := CoreFixtures.intent("cast", "wiz", {"spell": "hold_person", "target": target, "slot_level": 2})
					plan = [
						hold if round_index == 0 else fireball,
						CoreFixtures.intent("cast", "wiz", {"spell": "fire_bolt", "target": "gob", "metamagic": ["quickened_spell"]}),
					]
				_:
					plan = MonsterBrain.decide(e, actor.id)
			for intent in plan:
				if e.state != Encounter.State.ACTIVE or e.current_actor() != actor:
					break
				if e.submit(intent)["ok"]:
					accepted += 1
			if e.state == Encounter.State.ACTIVE and e.current_actor() == actor:
				e.end_turn()
	assert_true(accepted > 5, "the scenario exercised the new intents")
	var kinds := CoreFixtures.kinds(e.events)
	for kind: String in ["area_effect", "concentration_started", "feature_used"]:
		assert_has(kinds, kind)
	var setup: Array[Dictionary] = []
	for entry: Variant in _round_trip(e.setup_snapshot()):
		setup.append(entry)
	var intents: Array[Dictionary] = []
	for entry: Variant in _round_trip(e.intent_log):
		intents.append(entry)
	var again := Encounter.replay(e.rng_seed, e.walk_map, e.region, setup, intents, "r", content)
	assert_eq(again.events.size(), e.events.size())
	assert_eq(_round_trip(again.events), _round_trip(e.events))

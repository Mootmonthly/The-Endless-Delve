extends TestCase
## Replays stay identical with the round B systems: summons and companions
## (turns run by the encounter), tile effects, reactions and policies, hide /
## search, shove / grapple, buffs, metamagic and class features.

const HIT := {"name": "Hit", "kind": "melee", "to_hit": 5, "damage": "1d6+2", "damage_type": "slashing", "ability": "STR"}


func _round_trip(v: Variant) -> Variant:
	return JSON.parse_string(JSON.stringify(v))


func test_round_b_fight_replays_identically_through_json() -> void:
	var content := CoreFixtures.content()
	var wolf := MonsterDefinition.from_dict({"schema_version": 1, "id": "wolf", "display_name": "Wolf", "creature_type": "beast", "armor_class": 13,
		"hit_points": 11, "hit_dice": "2d8+2", "speed": 40, "challenge_rating": 0.25, "xp": 50,
		"abilities": {"STR": 12, "DEX": 15, "CON": 12, "INT": 3, "WIS": 12, "CHA": 6},
		"attacks": [{"name": "Bite", "kind": "melee", "to_hit": 4, "damage": "2d4+2", "damage_type": "piercing"}]})
	content["monsters"]["wolf"] = wolf
	for d: Dictionary in [
		{"id": "spiritual_weapon", "level": 2, "casting_time": "bonus_action", "range_ft": 60},
		{"id": "bless", "level": 1, "range_ft": 30, "concentration": true},
		{"id": "web", "level": 2, "range_ft": 60, "concentration": true, "area": {"shape": "cube", "size_ft": 10}},
		{"id": "shield", "level": 1, "casting_time": "reaction", "target": "self"},
	]:
		var base := {"display_name": str(d["id"]), "effect": {"type": "unsupported"}}
		base.merge(d, true)
		content["spells"][d["id"]] = CoreFixtures.spell(base)
	var make := func() -> Array:
		var cleric := CoreFixtures.caster("Cleric", Ability.Type.WIS, ["spiritual_weapon", "bless", "web", "shield"], 40)
		cleric.spell_slots_max = [4, 3]
		cleric.spell_slots = [4, 3]
		cleric.companions = [{"monster": "wolf", "spell": "animate_dead", "hp": 11}]
		var rogue := CoreFixtures.sheet("Rogue", 40, [10, 18, 10, 10, 10, 10], ["cunning_action", "uncanny_dodge", "evasion"])
		rogue.proficient_skills = [Skill.Type.STEALTH, Skill.Type.ATHLETICS]
		var a := CoreFixtures.combatant("cleric", cleric, Combatant.TEAM_PLAYERS, Vector2i(1, 1), [HIT])
		var b := CoreFixtures.combatant("rogue", rogue, Combatant.TEAM_PLAYERS, Vector2i(3, 3), [HIT])
		b.reaction_policy = {"uncanny_dodge": "auto"}
		var m1 := CoreFixtures.combatant("orc", CoreFixtures.sheet("Orc", 50), Combatant.TEAM_MONSTERS, Vector2i(5, 3), [HIT])
		var m2 := CoreFixtures.combatant("gob", CoreFixtures.sheet("Gob", 30), Combatant.TEAM_MONSTERS, Vector2i(7, 4), [HIT])
		return [a, b, m1, m2]
	var e := CoreFixtures.fight(make, "cleric", content)
	assert_not_null(e)
	e.set_reaction_policy("orc", {"creature_left_reach": "never"})
	for round_index in range(6):
		for _turn in range(8):
			if e.state != Encounter.State.ACTIVE:
				break
			var actor := e.current_actor()
			var plan: Array[Dictionary] = []
			match actor.id:
				"cleric":
					if round_index == 0:
						plan = [CoreFixtures.intent("cast", "cleric", {"spell": "bless", "targets": ["cleric", "rogue"]}),
							CoreFixtures.intent("cast", "cleric", {"spell": "spiritual_weapon", "point": [4, 3]})]
					elif round_index == 1:
						plan = [CoreFixtures.intent("cast", "cleric", {"spell": "web", "point": [7, 4]})]
				"rogue":
					var orc := e.get_combatant("orc")
					var step := orc.position + Vector2i(-1, 0)
					plan = [CoreFixtures.intent("move", "rogue", {"path": [[step.x, step.y]]}),
						CoreFixtures.intent("shove", "rogue", {"target": "orc", "mode": "prone"}),
						CoreFixtures.intent("use_feature", "rogue", {"feature": "cunning_action", "mode": "hide"})]
					if round_index > 0:
						plan.push_front(CoreFixtures.intent("attack", "rogue", {"target": "orc", "attack_index": 0, "retarget": true}))
				_:
					plan = MonsterBrain.decide(e, actor.id)
			for intent in plan:
				if e.state != Encounter.State.ACTIVE or e.current_actor() != actor:
					break
				e.submit(intent)
			if e.state == Encounter.State.ACTIVE and e.current_actor() == actor:
				e.end_turn()
	var kinds := CoreFixtures.kinds(e.events)
	for kind: String in ["summoned", "tile_effect_created", "contest", "effect_applied", "check"]:
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

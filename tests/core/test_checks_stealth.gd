extends TestCase
## Round B shared systems: ability checks and contests, Hide / Search and the
## hidden state, invisibility, shove / grapple / escape, Help, exhaustion.

const HIT := {"name": "Hit", "kind": "melee", "to_hit": 100, "damage": "1", "damage_type": "slashing", "ability": "STR"}
const BOW := {"name": "Bow", "kind": "ranged", "to_hit": 100, "damage": "1", "damage_type": "piercing", "range_tiles": [16, 64]}

var content: Dictionary


func before_each() -> void:
	content = CoreFixtures.content()


func _evs(res: Dictionary) -> Array:
	var evs: Array = res.get("events", [])
	return evs


func _duel(hero: CharacterSheet, gob_pos: Vector2i = Vector2i(4, 3), gob: CharacterSheet = null, attacks: Array[Dictionary] = [HIT, BOW]) -> Encounter:
	var g := gob if gob != null else CoreFixtures.sheet("Gob", 40)
	var e := CoreFixtures.duel(hero, attacks, {"gob": [g, gob_pos, [HIT, BOW]]}, content)
	assert_not_null(e)
	return e


func test_check_modifiers_proficiency_expertise_jack_remarkable() -> void:
	var s := CoreFixtures.sheet("S", 10, [14, 14, 14, 10, 10, 10])
	s.level = 5  # proficiency +3
	assert_eq(s.check_modifier(Ability.Type.STR, Skill.Type.ATHLETICS), 2)
	s.proficient_skills = [Skill.Type.ATHLETICS]
	assert_eq(s.check_modifier(Ability.Type.STR, Skill.Type.ATHLETICS), 5)
	s.expertise_skills = [Skill.Type.ATHLETICS]
	assert_eq(s.check_modifier(Ability.Type.STR, Skill.Type.ATHLETICS), 8)
	s.features.append("jack_of_all_trades")
	assert_eq(s.check_modifier(Ability.Type.WIS, Skill.Type.PERCEPTION), 1, "half proficiency rounded down")
	assert_eq(s.initiative_modifier(), 3, "initiative is a DEX check")
	s.features = ["remarkable_athlete"]
	assert_eq(s.check_modifier(Ability.Type.DEX, Skill.Type.ACROBATICS), 4, "half proficiency rounded up")
	assert_eq(s.check_modifier(Ability.Type.WIS, Skill.Type.PERCEPTION), 0, "not WIS")
	assert_eq(s.passive_perception(), 10)
	var m := CharacterSheet.new()
	m.skill_bonuses = {Skill.Type.STEALTH: 6}
	assert_eq(m.check_modifier(Ability.Type.DEX, Skill.Type.STEALTH), 6, "stat-block skills")
	assert_true(m.is_skill_proficient(Skill.Type.STEALTH))


func test_reliable_talent_floors_the_die() -> void:
	var s := CoreFixtures.sheet("Rogue", 20, [10, 10, 10, 10, 10, 10], ["reliable_talent"])
	s.proficient_skills = [Skill.Type.STEALTH]
	var e := _duel(s, Vector2i(9, 9))
	var hero := e.get_combatant("hero")
	for _i in range(20):
		var res := e.ability_check(hero, Ability.Type.DEX, Skill.Type.STEALTH)
		assert_true(DictUtil.to_int(res["total"]) >= 12, "d20 below 10 counts as 10 (+2)")
	var plain := e.ability_check(hero, Ability.Type.STR, Skill.Type.ATHLETICS, 50, "test")
	assert_false(plain["success"] == true)
	var ev := CoreFixtures.events_of(e.events, "check")
	assert_eq(ev[ev.size() - 1]["dc"], 50)
	assert_eq(ev[ev.size() - 1]["skill"], "ATHLETICS")


func test_hide_search_and_attacks_from_hiding() -> void:
	var s := CoreFixtures.sheet("Rogue", 20, [10, 30, 10, 10, 10, 10])
	s.proficient_skills = [Skill.Type.STEALTH]
	var gob := CoreFixtures.sheet("Gob", 40, [10, 10, 10, 10, 1, 10])
	var e := _duel(s, Vector2i(4, 3), gob)
	var res := e.submit(CoreFixtures.intent("hide", "hero"))
	assert_true(str(res["error"]).contains("cannot hide next to"))
	res = e.submit(CoreFixtures.intent("move", "hero", {"path": [[2, 3], [1, 3]]}))
	assert_true(res["ok"] == true, str(res["error"]))
	res = e.submit(CoreFixtures.intent("hide", "hero", {"bonus": true}))
	assert_true(str(res["error"]).contains("bonus action"), "needs Cunning Action")
	res = e.submit(CoreFixtures.intent("hide", "hero"))
	assert_true(res["ok"] == true, str(res["error"]))
	var hero := e.get_combatant("hero")
	assert_true(hero.hidden, "Stealth +12 beats passive Perception 5")
	assert_eq(CoreFixtures.first_event(_evs(res), "hidden")["actor"], "hero")
	assert_false(e.can_see(e.get_combatant("gob"), hero))
	assert_true(MonsterBrain._targets(e, e.get_combatant("gob")).is_empty(), "a hidden hero is no target")
	e.end_turn()
	var plan := MonsterBrain.decide(e, "gob")
	assert_eq(plan[0]["type"], "search", "the goblin searches")
	# The next attack from hiding has advantage and reveals.
	e.submit(CoreFixtures.intent("end_turn", "gob"))
	res = e.submit(CoreFixtures.intent("attack", "hero", {"target": "gob", "attack_index": 1}))
	assert_eq(CoreFixtures.first_event(_evs(res), "attack")["advantage"], "advantage")
	assert_eq(CoreFixtures.first_event(_evs(res), "revealed")["reason"], "attacked")
	assert_false(hero.hidden)


func test_search_reveals_a_hidden_creature() -> void:
	var e := _duel(CoreFixtures.sheet("Hero", 20, [10, 10, 10, 10, 30, 10]), Vector2i(8, 3))
	var gob := e.get_combatant("gob")
	gob.hidden = true
	gob.stealth_total = 5
	var res := e.submit(CoreFixtures.intent("search", "hero"))
	assert_true(res["ok"] == true, str(res["error"]))
	assert_eq(CoreFixtures.first_event(_evs(res), "revealed"), {"kind": "revealed", "actor": "gob", "reason": "found", "by": "hero"})
	assert_true(e.get_combatant("hero").action_used)


func test_invisible_condition_and_see_invisibility() -> void:
	var e := _duel(CoreFixtures.sheet("Hero", 20), Vector2i(4, 3))
	var hero := e.get_combatant("hero")
	var gob := e.get_combatant("gob")
	e._apply_condition(hero, Conditions.INVISIBLE, "hero", Conditions.duration(Conditions.DURATION_ENCOUNTER), {"ends_on_attack": true})
	assert_eq(e._attack_mode(hero, gob, HIT, true)["mode"], D20.RollMode.ADVANTAGE)
	assert_eq(e._attack_mode(gob, hero, HIT, true)["mode"], D20.RollMode.DISADVANTAGE)
	gob.buffs.append({"effect": "see_invisibility", "see_invisible": true})
	assert_eq(e._attack_mode(gob, hero, HIT, true)["mode"], D20.RollMode.NORMAL, "See Invisibility")
	var res := e.submit(CoreFixtures.intent("attack", "hero", {"target": "gob", "attack_index": 0}))
	assert_has(_evs(res), {"kind": "condition_ended", "target": "hero", "condition": "invisible"}, "Invisibility ends on attacking")


func test_shove_prone_push_and_grapple_escape() -> void:
	var strong := CoreFixtures.sheet("Hero", 20, [30, 10, 10, 10, 10, 10])
	var weak := CoreFixtures.sheet("Gob", 40, [1, 1, 10, 10, 10, 10])
	var e := _duel(strong, Vector2i(4, 3), weak)
	var res := e.submit(CoreFixtures.intent("shove", "hero", {"target": "gob"}))
	assert_true(res["ok"] == true, str(res["error"]))
	assert_true(CoreFixtures.first_event(_evs(res), "contest")["success"])
	assert_true(e.get_combatant("gob").has_condition(Conditions.PRONE))
	assert_true(e.get_combatant("hero").action_used, "a shove replaces an attack")
	var e2 := _duel(strong, Vector2i(4, 3), weak)
	res = e2.submit(CoreFixtures.intent("shove", "hero", {"target": "gob", "mode": "push"}))
	assert_eq(CoreFixtures.first_event(_evs(res), "pushed")["to"], [5, 3])
	var e3 := _duel(strong, Vector2i(4, 3), weak)
	res = e3.submit(CoreFixtures.intent("grapple", "hero", {"target": "gob"}))
	var gob := e3.get_combatant("gob")
	assert_true(gob.has_condition(Conditions.GRAPPLED))
	assert_eq(gob.speed_tiles(), 0)
	e3.end_turn()
	res = e3.submit(CoreFixtures.intent("escape_grapple", "gob"))
	assert_true(res["ok"] == true, str(res["error"]))
	assert_true(gob.has_condition(Conditions.GRAPPLED), "a weak goblin cannot escape")
	# Moving away ends the grapple.
	e3.end_turn()
	e3.submit(CoreFixtures.intent("move", "hero", {"path": [[2, 3]]}))
	assert_false(gob.has_condition(Conditions.GRAPPLED))
	var huge := CoreFixtures.sheet("Ogre", 40)
	huge.size = "huge"
	var e4 := _duel(strong, Vector2i(4, 3), huge)
	assert_true(str(e4.submit(CoreFixtures.intent("grapple", "hero", {"target": "gob"}))["error"]).contains("too large"))


func test_help_gives_an_ally_advantage() -> void:
	var foes := {"gob": [CoreFixtures.sheet("Gob", 40), Vector2i(4, 3), [HIT]]}
	var allies := {"ally": [CoreFixtures.sheet("Ally", 20), Vector2i(5, 3), [HIT]]}
	var e := CoreFixtures.duel(CoreFixtures.sheet("Hero", 20), [HIT], foes, content, "hero", Vector2i(3, 3), allies)
	var res := e.submit(CoreFixtures.intent("help", "hero", {"target": "gob"}))
	assert_true(res["ok"] == true, str(res["error"]))
	assert_eq(CoreFixtures.first_event(_evs(res), "help"), {"kind": "help", "actor": "hero", "target": "gob"})
	var gob := e.get_combatant("gob")
	var ally := e.get_combatant("ally")
	assert_eq(e._attack_mode(ally, gob, HIT, true)["mode"], D20.RollMode.ADVANTAGE)
	e._roll_attack(ally, gob, HIT, false, null)
	assert_eq(gob.helped_by, "", "used up")


func test_exhaustion_levels() -> void:
	var s := CoreFixtures.sheet("Tired", 40)
	s.add_exhaustion(2)
	assert_eq(s.effective_speed(), 15, "speed halved")
	s.add_exhaustion(2)
	assert_eq(s.hit_point_maximum(), 20)
	assert_eq(s.current_hp, 20, "hp capped")
	assert_eq(s.heal(50), 0)
	s.add_exhaustion(1)
	assert_eq(s.effective_speed(), 0)
	Rest.long_rest(s)
	assert_eq(s.exhaustion, 4, "a long rest removes one level")
	s.add_exhaustion(2)
	assert_true(s.is_dead(), "level 6 is death")
	var t := CoreFixtures.sheet("T", 20)
	t.exhaustion = 3
	var e := _duel(t)
	assert_eq(e._attack_mode(e.get_combatant("hero"), e.get_combatant("gob"), HIT, true)["mode"], D20.RollMode.DISADVANTAGE)
	assert_eq(CharacterSheet.from_dict(t.to_dict()).exhaustion, 3)

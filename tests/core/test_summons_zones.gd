extends TestCase
## Summons and companions, tile effects (zones, walls, anchored areas),
## difficult terrain, teleport and fly movement.

const SURE := {"name": "Sure", "kind": "melee", "to_hit": 100, "damage": "4", "damage_type": "slashing", "ability": "STR"}

var content: Dictionary


func before_each() -> void:
	content = CoreFixtures.content()
	for d: Dictionary in [
		{"id": "wolf", "display_name": "Wolf", "creature_type": "beast", "challenge_rating": 0.25, "hit_points": 11, "hit_dice": "2d8+2"},
		{"id": "owl", "display_name": "Owl", "creature_type": "beast", "challenge_rating": 0.0, "hit_points": 1, "hit_dice": "1d4-1", "speeds": {"walk": 5, "fly": 60}},
		{"id": "skeleton", "display_name": "Skeleton", "creature_type": "undead", "challenge_rating": 0.25, "hit_points": 13, "hit_dice": "2d8+4"},
		{"id": "brown_bear", "display_name": "Brown Bear", "creature_type": "beast", "challenge_rating": 1.0, "hit_points": 34, "hit_dice": "4d10+12", "size": "large"},
	]:
		var base := {"schema_version": 1, "armor_class": 12, "speed": 30, "abilities": {"STR": 12, "DEX": 14, "CON": 12, "INT": 3, "WIS": 12, "CHA": 6},
			"xp": 50, "attacks": [{"name": "Bite", "kind": "melee", "to_hit": 100, "damage": "3", "damage_type": "piercing"}]}
		base.merge(d, true)
		var m := MonsterDefinition.from_dict(base)
		content["monsters"][m.id] = m
	for d: Dictionary in [
		{"id": "spiritual_weapon", "display_name": "Spiritual Weapon", "level": 2, "casting_time": "bonus_action", "range_ft": 60, "effect": {"type": "unsupported"}},
		{"id": "conjure_animals", "display_name": "Conjure Animals", "level": 3, "range_ft": 60, "concentration": true, "effect": {"type": "unsupported"}},
		{"id": "find_familiar", "display_name": "Find Familiar", "level": 1, "casting_time": "1_hour", "range_ft": 10, "effect": {"type": "unsupported"}},
		{"id": "grease", "display_name": "Grease", "level": 1, "range_ft": 60, "area": {"shape": "cube", "size_ft": 10}, "saving_throw": {"ability": "DEX", "on_success": "none"}, "effect": {"type": "unsupported"}},
		{"id": "spike_growth", "display_name": "Spike Growth", "level": 2, "range_ft": 150, "concentration": true, "area": {"shape": "cylinder", "size_ft": 10}, "effect": {"type": "unsupported"}},
		{"id": "moonbeam", "display_name": "Moonbeam", "level": 2, "range_ft": 120, "concentration": true, "area": {"shape": "cylinder", "size_ft": 5}, "effect": {"type": "unsupported"}},
		{"id": "wall_of_fire", "display_name": "Wall of Fire", "level": 4, "range_ft": 120, "concentration": true, "area": {"shape": "line", "size_ft": 30}, "effect": {"type": "unsupported"}},
		{"id": "spirit_guardians", "display_name": "Spirit Guardians", "level": 3, "range_ft": 0, "target": "self", "concentration": true, "effect": {"type": "unsupported"}},
		{"id": "misty_step", "display_name": "Misty Step", "level": 2, "casting_time": "bonus_action", "range_ft": 0, "target": "self", "effect": {"type": "unsupported"}},
		{"id": "fly", "display_name": "Fly", "level": 3, "range_ft": 5, "concentration": true, "effect": {"type": "unsupported"}},
	]:
		var sdef := CoreFixtures.spell(d)
		assert_not_null(sdef, d["id"])
		content["spells"][sdef.id] = sdef


func _evs(res: Dictionary) -> Array:
	var evs: Array = res.get("events", [])
	return evs


func _caster(prepared: Array[String]) -> CharacterSheet:
	var s := CoreFixtures.caster("Cleric", Ability.Type.WIS, prepared, 60)
	s.abilities.set_score(Ability.Type.WIS, 30)
	s.spell_slots_max = [4, 3, 3, 3]
	s.spell_slots = [4, 3, 3, 3]
	return s


func _fight(hero: CharacterSheet, gob_pos: Vector2i = Vector2i(9, 3), gob: CharacterSheet = null) -> Encounter:
	var g := gob if gob != null else CoreFixtures.sheet("Gob", 200, [10, 1, 10, 10, 10, 10])
	var e := CoreFixtures.duel(hero, [SURE], {"gob": [g, gob_pos, [SURE]]}, content)
	assert_not_null(e)
	return e


func test_spiritual_weapon_acts_after_its_caster() -> void:
	var e := _fight(_caster(["spiritual_weapon"]), Vector2i(8, 3))
	var res := e.submit(CoreFixtures.intent("cast", "hero", {"spell": "spiritual_weapon", "point": [7, 3]}))
	assert_true(res["ok"] == true, str(res["error"]))
	var summoned := CoreFixtures.first_event(_evs(res), "summoned")
	assert_eq(summoned["monster"], "spiritual_weapon")
	var weapon := e.get_combatant(str(summoned["id"]))
	assert_true(weapon.untargetable and weapon.auto_controlled)
	assert_eq(weapon.team, Combatant.TEAM_PLAYERS)
	assert_eq(CoreFixtures.first_event(_evs(res), "combatant_joined")["owner"], "hero")
	assert_eq(e.tracker.order()[1].id, weapon.id, "acts right after the caster")
	res = e.submit(CoreFixtures.intent("end_turn", "hero"))
	var attacks := CoreFixtures.events_of(_evs(res), "attack")
	assert_eq(attacks[0]["attacker"], weapon.id, "the encounter runs its turn")
	assert_eq(e.current_actor().id, "gob")
	assert_true(str(e.submit(CoreFixtures.intent("attack", "gob", {"target": weapon.id, "attack_index": 0}))["error"]).contains("cannot be attacked"))
	assert_false(e.occupied_cells().has(weapon.position), "spell objects do not block")
	# It lasts 10 of the caster's turns.
	for _i in range(25):
		if e.state != Encounter.State.ACTIVE:
			break
		e.end_turn()
	assert_null(e.get_combatant(weapon.id), "dismissed after 1 minute")
	assert_true(CoreFixtures.kinds(e.events).has("summon_ended"))


func test_conjure_animals_count_and_concentration() -> void:
	var e := _fight(_caster(["conjure_animals", "spike_growth"]))
	var res := e.submit(CoreFixtures.intent("cast", "hero", {"spell": "conjure_animals", "form": "wolf"}))
	assert_true(res["ok"] == true, str(res["error"]))
	assert_eq(CoreFixtures.events_of(_evs(res), "summoned").size(), 8, "eight CR 1/4 beasts")
	assert_true(str(e.submit(CoreFixtures.intent("cast", "hero", {"spell": "conjure_animals", "form": "brown_bear", "slot_level": 4}))["error"]).length() > 0)
	e.end_turn()
	e.end_turn()
	res = e.submit(CoreFixtures.intent("cast", "hero", {"spell": "spike_growth", "point": [9, 6]}))
	assert_eq(CoreFixtures.events_of(_evs(res), "summon_ended").size(), 8, "concentration ends the summons")
	assert_eq(Encounter.summon_count(content["spells"]["conjure_animals"], content["monsters"]["wolf"], 5), 16)


func test_companions_join_at_start_and_persist() -> void:
	var s := _caster(["find_familiar"])
	var r := OutOfCombat.cast(s, "find_familiar", content, Rng.new(1), [], {"form": "owl"})
	assert_true(r["ok"] == true, str(r["error"]))
	assert_eq(s.companions, [{"monster": "owl", "spell": "find_familiar", "hp": 1}])
	assert_eq(s.slots_left(1), 3)
	assert_false(OutOfCombat.cast(s, "find_familiar", content, Rng.new(1), [], {"form": "wolf"})["ok"] == true, "not a familiar form")
	var e := _fight(s, Vector2i(8, 3))
	var owl: Combatant = null
	for c in e.combatants():
		if c.is_summon():
			owl = c
	assert_not_null(owl)
	assert_true(owl.familiar)
	owl.movement_remaining = owl.speed_tiles()
	var plan := MonsterBrain.decide(e, owl.id)
	assert_eq(plan[plan.size() - 2]["type"], "help", "a familiar helps instead of attacking")
	e._dismiss(owl, "dropped")
	e._end_encounter(0)
	assert_eq(e.get_combatant("hero").sheet.companions, [] as Array[Dictionary], "a familiar that died leaves the sheet")


func test_grease_and_difficult_terrain() -> void:
	var gob := CoreFixtures.sheet("Gob", 40, [10, 1, 10, 10, 10, 10])
	var e := _fight(_caster(["grease"]), Vector2i(6, 3), gob)
	var res := e.submit(CoreFixtures.intent("cast", "hero", {"spell": "grease", "point": [6, 3]}))
	assert_true(res["ok"] == true, str(res["error"]))
	var created := CoreFixtures.first_event(_evs(res), "tile_effect_created")
	assert_eq(created["effect"], "grease")
	assert_eq(created["rounds"], 10)
	assert_true(e.get_combatant("gob").has_condition(Conditions.PRONE), "fails DEX on creation")
	assert_eq(e.tile_effects.size(), 1)
	var hero := e.get_combatant("hero")
	assert_eq(e._step_cost(hero, Vector2i(5, 3), "walk"), 2)
	assert_eq(e._step_cost(hero, Vector2i(5, 3), "fly"), 1, "flyers skip ground effects")
	assert_eq(e._step_cost(hero, Vector2i(3, 4), "walk"), 1)


func test_spike_growth_hurts_per_tile() -> void:
	var gob := CoreFixtures.sheet("Gob", 200)
	var e := _fight(_caster(["spike_growth"]), Vector2i(10, 3), gob)
	e.submit(CoreFixtures.intent("cast", "hero", {"spell": "spike_growth", "point": [8, 3]}))
	e.end_turn()
	var res := e.submit(CoreFixtures.intent("move", "gob", {"path": [[9, 3], [8, 3]]}))
	assert_true(res["ok"] == true, str(res["error"]))
	assert_eq(CoreFixtures.events_of(_evs(res), "tile_effect_triggered").size(), 2)
	assert_eq(CoreFixtures.events_of(_evs(res), "damage").size(), 2)
	assert_eq(e.get_combatant("gob").movement_remaining, 6 - 4, "two difficult steps")


func test_moonbeam_start_of_turn_and_move_effect() -> void:
	var gob := CoreFixtures.sheet("Gob", 200, [10, 10, 1, 10, 10, 10])
	var e := _fight(_caster(["moonbeam"]), Vector2i(9, 3), gob)
	var res := e.submit(CoreFixtures.intent("cast", "hero", {"spell": "moonbeam", "point": [9, 3]}))
	assert_true(res["ok"] == true, str(res["error"]))
	var fx_id := str(CoreFixtures.first_event(_evs(res), "tile_effect_created")["id"])
	res = e.submit(CoreFixtures.intent("end_turn", "hero"))
	assert_eq(CoreFixtures.first_event(_evs(res), "tile_effect_triggered")["trigger"], "start_turn")
	assert_eq(CoreFixtures.first_event(_evs(res), "damage")["spell"], "moonbeam")
	e.submit(CoreFixtures.intent("move", "gob", {"path": [[9, 4], [9, 5]]}))
	e.end_turn()
	res = e.submit(CoreFixtures.intent("move_effect", "hero", {"effect": fx_id, "point": [9, 5]}))
	assert_true(res["ok"] == true, str(res["error"]))
	assert_eq(CoreFixtures.first_event(_evs(res), "tile_effect_triggered")["trigger"], "enter")
	assert_true(e.get_combatant("hero").action_used, "Moonbeam moves with an action")
	e._end_concentration(e.get_combatant("hero"), "test")
	assert_eq(e.tile_effects.size(), 0)


func test_wall_and_anchored_spirit_guardians() -> void:
	var e := _fight(_caster(["wall_of_fire", "spirit_guardians"]), Vector2i(9, 3))
	var res := e.submit(CoreFixtures.intent("cast", "hero", {"spell": "wall_of_fire", "point": [6, 3]}))
	assert_true(res["ok"] == true, str(res["error"]))
	var tiles: Array = CoreFixtures.first_event(_evs(res), "tile_effect_created")["tiles"]
	assert_eq(tiles.size(), 6, "a 30 ft wall across the line of sight")
	for t: Array in tiles:
		assert_eq(t[0], 6)
	e.end_turn()
	e.end_turn()
	res = e.submit(CoreFixtures.intent("cast", "hero", {"spell": "spirit_guardians"}))
	assert_true(res["ok"] == true, str(res["error"]))
	var fx: Dictionary = e.tile_effects[0]
	assert_eq(fx["anchor"], "hero")
	assert_eq(fx["affects"], "hostiles")
	res = e.submit(CoreFixtures.intent("move", "hero", {"path": [[4, 3]]}))
	assert_eq(CoreFixtures.events_of(_evs(res), "tile_effect_moved").size(), 1, "follows its caster")
	assert_true(fx["cells"].has(Vector2i(7, 3)))


func test_teleport_and_fly_moves() -> void:
	var s := _caster(["misty_step", "fly"])
	var e := _fight(s, Vector2i(10, 10))
	var res := e.submit(CoreFixtures.intent("cast", "hero", {"spell": "misty_step", "point": [8, 3]}))
	assert_true(res["ok"] == true, str(res["error"]))
	assert_eq(CoreFixtures.first_event(_evs(res), "teleported"), {"kind": "teleported", "actor": "hero", "from": [3, 3], "to": [8, 3], "spell": "misty_step"})
	var e2 := _fight(s, Vector2i(10, 10))
	res = e2.submit(CoreFixtures.intent("cast", "hero", {"spell": "misty_step"}))
	assert_eq(e2.get_combatant("hero").teleport_tiles, 6)
	assert_true(str(e2.submit(CoreFixtures.intent("move", "hero", {"mode": "teleport", "path": [[10, 3]]}))["error"]).contains("out of range"))
	res = e2.submit(CoreFixtures.intent("move", "hero", {"mode": "teleport", "path": [[9, 3]]}))
	assert_true(res["ok"] == true, str(res["error"]))
	assert_eq(e2.get_combatant("hero").position, Vector2i(9, 3))
	# Fly: over a wall tile, ending on open ground.
	var e3 := _fight(s, Vector2i(10, 10))
	assert_true(str(e3.submit(CoreFixtures.intent("move", "hero", {"mode": "fly", "path": [[4, 4]]}))["error"]).contains("cannot fly"))
	res = e3.submit(CoreFixtures.intent("cast", "hero", {"spell": "fly", "target": "hero"}))
	assert_true(res["ok"] == true, str(res["error"]))
	var hero := e3.get_combatant("hero")
	assert_eq(hero.fly_tiles(), 12)
	hero.position = Vector2i(5, 5)
	res = e3.submit(CoreFixtures.intent("move", "hero", {"mode": "fly", "path": [[6, 6], [7, 7]]}))
	assert_true(res["ok"] == true, str(res["error"]))
	assert_eq(CoreFixtures.first_event(_evs(res), "moved")["mode"], "fly")
	assert_true(str(e3.submit(CoreFixtures.intent("move", "hero", {"mode": "fly", "path": [[6, 6]]}))["error"]).contains("open ground"))

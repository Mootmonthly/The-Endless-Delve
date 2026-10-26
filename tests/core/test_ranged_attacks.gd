extends TestCase
## Ranged and thrown attacks: range bands, line of sight, adjacency
## disadvantage, ammunition and thrown-weapon use; monsters shooting.

const SURE_HIT := {"name": "Sure Hit", "kind": "melee", "to_hit": 100, "damage": "1", "damage_type": "slashing"}
const SLING := {"name": "Sling", "kind": "ranged", "to_hit": 100, "damage": "1", "damage_type": "bludgeoning", "range_tiles": [3, 6]}

var content: Dictionary


func before_each() -> void:
	content = CoreFixtures.content()


func _ok(res: Dictionary) -> bool:
	return res.get("ok", false) == true


func _evs(res: Dictionary) -> Array:
	var evs: Array = res.get("events", [])
	return evs


func _attack(actor: String, target: String, index: int = 0) -> Dictionary:
	return {"v": 1, "type": "attack", "actor": actor, "target": target, "attack_index": index}


func _fight(archer: CharacterSheet, attacks: Array[Dictionary], gob_pos: Vector2i, archer_pos: Vector2i = Vector2i(1, 1)) -> Encounter:
	var make := func() -> Array:
		var a := CoreFixtures.combatant("archer", CharacterSheet.from_dict(archer.to_dict()), Combatant.TEAM_PLAYERS, archer_pos, attacks)
		var g := CoreFixtures.combatant("gob", CoreFixtures.sheet("Gob", 100), Combatant.TEAM_MONSTERS, gob_pos, [SURE_HIT])
		return [a, g]
	var e := CoreFixtures.fight(make, "archer", content)
	assert_not_null(e)
	return e


func test_line_of_sight() -> void:
	var m := WalkMap.from_rows([
		"#######",
		"#.....#",
		"#..#..#",
		"#.....#",
		"#######",
	])
	assert_true(m.has_line_of_sight(Vector2i(1, 1), Vector2i(5, 1)))
	assert_false(m.has_line_of_sight(Vector2i(1, 2), Vector2i(5, 2)), "pillar in the way")
	assert_false(m.has_line_of_sight(Vector2i(5, 2), Vector2i(1, 2)), "symmetric")
	assert_true(m.has_line_of_sight(Vector2i(2, 2), Vector2i(2, 3)), "adjacent")
	assert_true(m.has_line_of_sight(Vector2i(1, 1), Vector2i(1, 1)))
	assert_false(m.has_line_of_sight(Vector2i(1, 1), Vector2i(9, 9)), "out of bounds")
	for a: Vector2i in [Vector2i(1, 1), Vector2i(1, 3), Vector2i(5, 3)]:
		for b: Vector2i in [Vector2i(5, 1), Vector2i(2, 3), Vector2i(4, 1)]:
			assert_eq(m.has_line_of_sight(a, b), m.has_line_of_sight(b, a), "symmetric %s %s" % [a, b])
	assert_eq(WalkMap.line_cells(Vector2i(0, 0), Vector2i(3, 1)).size(), 4)


func test_range_bands() -> void:
	var e := _fight(CoreFixtures.sheet("Archer"), [SLING], Vector2i(4, 1))
	var res := e.submit(_attack("archer", "gob"))
	assert_true(_ok(res), str(res["error"]))
	assert_eq(CoreFixtures.first_event(_evs(res), "attack")["advantage"], "normal", "3 tiles: normal range")
	assert_eq(CoreFixtures.first_event(_evs(res), "attack")["attack_kind"], "ranged")
	e = _fight(CoreFixtures.sheet("Archer"), [SLING], Vector2i(6, 1))
	res = e.submit(_attack("archer", "gob"))
	assert_eq(CoreFixtures.first_event(_evs(res), "attack")["advantage"], "disadvantage", "5 tiles: long range")
	e = _fight(CoreFixtures.sheet("Archer"), [SLING], Vector2i(8, 1))
	res = e.submit(_attack("archer", "gob"))
	assert_false(_ok(res))
	assert_true(str(res["error"]).contains("out of range"))


func test_line_of_sight_is_required() -> void:
	var e := _fight(CoreFixtures.sheet("Archer"), [SLING], Vector2i(8, 6), Vector2i(4, 6))
	var res := e.submit(_attack("archer", "gob"))
	assert_false(_ok(res))
	assert_true(str(res["error"]).contains("line of sight"), "wall at (6, 6)")


func test_adjacent_hostile_gives_disadvantage_unless_down() -> void:
	var make := func() -> Array:
		var a := CoreFixtures.combatant("archer", CoreFixtures.sheet("Archer"), Combatant.TEAM_PLAYERS, Vector2i(1, 1), [SLING])
		var far := CoreFixtures.combatant("far", CoreFixtures.sheet("Far", 100), Combatant.TEAM_MONSTERS, Vector2i(3, 1), [SURE_HIT])
		var near := CoreFixtures.combatant("near", CoreFixtures.sheet("Near", 100), Combatant.TEAM_MONSTERS, Vector2i(1, 2), [SURE_HIT])
		return [a, far, near]
	var e := CoreFixtures.fight(make, "archer", content)
	var res := e.submit(_attack("archer", "far"))
	assert_eq(CoreFixtures.first_event(_evs(res), "attack")["advantage"], "disadvantage")
	e = CoreFixtures.fight(make, "archer", content)
	e.get_combatant("near").sheet.kill()
	res = e.submit(_attack("archer", "far"))
	assert_eq(CoreFixtures.first_event(_evs(res), "attack")["advantage"], "normal", "a dead hostile does not count")


func test_melee_still_needs_adjacency() -> void:
	var e := _fight(CoreFixtures.sheet("Archer"), [SURE_HIT], Vector2i(3, 1))
	assert_true(str(e.submit(_attack("archer", "gob"))["error"]).contains("reach"))


func test_ammunition_is_used_up() -> void:
	var s := CoreFixtures.sheet("Archer", 20, [10, 16, 10, 10, 10, 10])
	s.add_item("shortbow")
	s.add_item("arrows", 2)
	s.equip("shortbow", "main_hand", content)
	assert_eq(s.attacks[0]["consumes"], "arrows")
	var make := func() -> Array:
		var a := Combatant.from_sheet("archer", CharacterSheet.from_dict(s.to_dict()), Combatant.TEAM_PLAYERS)
		a.position = Vector2i(1, 1)
		var g := CoreFixtures.combatant("gob", CoreFixtures.sheet("Gob", 100), Combatant.TEAM_MONSTERS, Vector2i(9, 1), [SURE_HIT])
		return [a, g]
	var e := CoreFixtures.fight(make, "archer", content)
	var archer := e.get_combatant("archer")
	var res := e.submit(_attack("archer", "gob"))
	assert_true(_ok(res), str(res["error"]))
	var atk := CoreFixtures.first_event(_evs(res), "attack")
	assert_eq(atk["consumed"], "arrows")
	assert_eq(atk["advantage"], "normal", "8 tiles is within 16")
	assert_eq(archer.sheet.count_item("arrows"), 1)
	e.end_turn()
	while e.current_actor().id != "archer":
		e.end_turn()
	assert_true(_ok(e.submit(_attack("archer", "gob"))))
	assert_eq(archer.sheet.count_item("arrows"), 0)
	e.end_turn()
	while e.current_actor().id != "archer":
		e.end_turn()
	res = e.submit(_attack("archer", "gob"))
	assert_false(_ok(res))
	assert_true(str(res["error"]).contains("out of arrows"))


func test_thrown_weapons_are_used_up() -> void:
	var s := CoreFixtures.sheet("Rogue", 20, [10, 16, 10, 10, 10, 10])
	s.add_item("shortsword")
	s.add_item("dagger", 1)
	s.equip("shortsword", "main_hand", content)
	var make := func() -> Array:
		var a := Combatant.from_sheet("rogue", CharacterSheet.from_dict(s.to_dict()), Combatant.TEAM_PLAYERS)
		a.position = Vector2i(1, 1)
		var g := CoreFixtures.combatant("gob", CoreFixtures.sheet("Gob", 100), Combatant.TEAM_MONSTERS, Vector2i(4, 1), [SURE_HIT])
		return [a, g]
	var e := CoreFixtures.fight(make, "rogue", content)
	var rogue := e.get_combatant("rogue")
	assert_eq(rogue.attacks[1]["name"], "Dagger (thrown)")
	assert_true(str(e.submit(_attack("rogue", "gob", 0))["error"]).contains("reach"), "the sword is melee")
	var res := e.submit(_attack("rogue", "gob", 1))
	assert_true(_ok(res), str(res["error"]))
	assert_eq(CoreFixtures.first_event(_evs(res), "attack")["consumed"], "dagger")
	assert_eq(CoreFixtures.first_event(_evs(res), "attack")["attack_kind"], "thrown")
	assert_false(rogue.sheet.has_item("dagger"), "thrown items are lost (M2)")
	e.end_turn()
	while e.current_actor().id != "rogue":
		e.end_turn()
	assert_true(str(e.submit(_attack("rogue", "gob", 1))["error"]).contains("no longer carries"))


func test_attack_range_helpers() -> void:
	assert_eq(Encounter.attack_range_tiles({"kind": "melee"}), [1, 1])
	assert_eq(Encounter.attack_range_tiles({"kind": "ranged", "range_ft": [80, 320]}), [16, 64])
	assert_eq(Encounter.attack_range_tiles({"kind": "ranged"}), [16, 64], "default")
	assert_eq(Encounter.attack_range_tiles({"kind": "thrown", "range_tiles": [4, 12]}), [4, 12])
	assert_true(Encounter.is_ranged_attack({"kind": "thrown"}))
	assert_false(Encounter.is_ranged_attack({"kind": "spell", "melee": true}))
	assert_true(Encounter.is_ranged_attack({"kind": "spell"}))


func test_monster_definition_ranged_attack_ranges() -> void:
	var goblin: MonsterDefinition = ContentLoader.load_monsters()["goblin"]
	assert_eq(goblin.attacks[1]["kind"], "ranged")
	assert_eq(goblin.attacks[1]["range_tiles"], [16, 64])


func _goblin_vs_hero(gob_pos: Vector2i, hero_pos: Vector2i, map: WalkMap = null) -> Encounter:
	var goblin: MonsterDefinition = ContentLoader.load_monsters()["goblin"]
	var make := func() -> Array:
		var g := Combatant.from_monster("gob", goblin, Combatant.TEAM_MONSTERS, null)
		g.position = gob_pos
		var h := CoreFixtures.combatant("hero", CoreFixtures.sheet("Hero", 30), Combatant.TEAM_PLAYERS, hero_pos, [SURE_HIT])
		return [g, h]
	var e := CoreFixtures.fight(make, "gob", content, map)
	assert_not_null(e)
	return e


func test_monster_shoots_when_it_cannot_reach() -> void:
	var map := WalkMap.from_rows([
		"############",
		"#....#.....#",
		"#....#.....#",
		"#..........#",
		"############",
	])
	map.set_walkable(Vector2i(5, 3), false)  # wall the two halves apart; sight over row 1 is blocked too
	var e := _goblin_vs_hero(Vector2i(1, 1), Vector2i(10, 1), null)
	var plan := MonsterBrain.decide(e, "gob")
	assert_eq(plan[0]["type"], "move")
	assert_eq(plan[1]["type"], "attack")
	assert_eq(plan[1]["attack_index"], 1, "shortbow after closing in")
	for intent in plan:
		assert_true(_ok(e.submit(intent)), str(intent))
	var adjacent := _goblin_vs_hero(Vector2i(3, 3), Vector2i(4, 3))
	var melee_plan := MonsterBrain.decide(adjacent, "gob")
	assert_eq(melee_plan[0]["type"], "attack")
	assert_eq(melee_plan[0]["attack_index"], 0, "scimitar when adjacent")
	var region := Rect2i(0, 0, 12, 5)
	var walled := _goblin_vs_hero_on(map, region, Vector2i(1, 1), Vector2i(8, 2))
	var blocked := MonsterBrain.decide(walled, "gob")
	assert_eq(blocked.size(), 1, "no path and no line of sight: just end the turn")


func _goblin_vs_hero_on(map: WalkMap, region: Rect2i, gob_pos: Vector2i, hero_pos: Vector2i) -> Encounter:
	var goblin: MonsterDefinition = ContentLoader.load_monsters()["goblin"]
	var make := func() -> Array:
		var g := Combatant.from_monster("gob", goblin, Combatant.TEAM_MONSTERS, null)
		g.position = gob_pos
		var h := CoreFixtures.combatant("hero", CoreFixtures.sheet("Hero", 30), Combatant.TEAM_PLAYERS, hero_pos, [SURE_HIT])
		return [g, h]
	var e := CoreFixtures.fight(make, "gob", content, map, region)
	assert_not_null(e)
	return e

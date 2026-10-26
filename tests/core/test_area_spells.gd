extends TestCase
## Areas of effect: geometry (sphere / cube / line / cone), area_save and
## area_attack resolution, Sculpt Spells, push, range checks.

const HIT := {"name": "Hit", "kind": "melee", "to_hit": 100, "damage": "1", "damage_type": "slashing", "ability": "STR"}

var content: Dictionary


func before_each() -> void:
	content = CoreFixtures.content()


func _evs(res: Dictionary) -> Array:
	var evs: Array = res.get("events", [])
	return evs


func test_sphere_and_cube_tiles() -> void:
	var m := WalkMap.new(12, 12, true)
	var sphere := AreaOfEffect.tiles("sphere", 1, Vector2i(0, 0), Vector2i(5, 5), m)
	assert_eq(sphere.size(), 9)
	assert_has(sphere, Vector2i(4, 4))
	assert_has(sphere, Vector2i(6, 6))
	m.set_walkable(Vector2i(5, 4), false)
	m.set_walkable(Vector2i(5, 3), false)
	var walled := AreaOfEffect.tiles("sphere", 2, Vector2i(0, 0), Vector2i(5, 5), m)
	assert_false(walled.has(Vector2i(5, 4)), "walls are not covered")
	assert_false(walled.has(Vector2i(5, 3)), "behind a wall")
	assert_eq(AreaOfEffect.tiles("cylinder", 1, Vector2i.ZERO, Vector2i(2, 2), WalkMap.new(12, 12, true)).size(), 9, "cylinder = sphere")


func test_line_tiles() -> void:
	var m := WalkMap.new(12, 12, true)
	var line := AreaOfEffect.tiles("line", 4, Vector2i(1, 1), Vector2i(3, 1), m)
	assert_eq(line, [Vector2i(2, 1), Vector2i(3, 1), Vector2i(4, 1), Vector2i(5, 1)], "full length past the aim point")
	var diag := AreaOfEffect.tiles("line", 3, Vector2i(1, 1), Vector2i(9, 9), m)
	assert_eq(diag, [Vector2i(2, 2), Vector2i(3, 3), Vector2i(4, 4)])
	m.set_walkable(Vector2i(4, 1), false)
	assert_eq(AreaOfEffect.tiles("line", 4, Vector2i(1, 1), Vector2i(3, 1), m).size(), 2, "stops at a wall")
	assert_true(AreaOfEffect.tiles("line", 4, Vector2i(1, 1), Vector2i(1, 1), m).is_empty())


func test_cone_tiles() -> void:
	var m := WalkMap.new(12, 12, true)
	var cone := AreaOfEffect.tiles("cone", 3, Vector2i(5, 5), Vector2i(8, 5), m)
	assert_has(cone, Vector2i(6, 5))
	assert_has(cone, Vector2i(8, 8), "exactly 45 degrees is in")
	assert_has(cone, Vector2i(7, 4))
	assert_false(cone.has(Vector2i(5, 6)), "90 degrees is out")
	assert_false(cone.has(Vector2i(4, 5)), "behind")
	assert_false(cone.has(Vector2i(5, 5)), "the origin")
	assert_false(cone.has(Vector2i(9, 5)), "beyond the length")


## caster at (3,3); foes a (6,3), b (6,4), c (10,10); ally at (7,3).
func _fight(caster: CharacterSheet) -> Encounter:
	var weak := CoreFixtures.sheet("Weak", 200, [10, 1, 1, 10, 10, 10])
	var e := CoreFixtures.duel(caster, [HIT], {
		"a": [weak, Vector2i(6, 3), [HIT]], "b": [weak, Vector2i(6, 4), [HIT]], "c": [weak, Vector2i(10, 10), [HIT]],
	}, content, "hero", Vector2i(3, 3), {"ally": [CoreFixtures.sheet("Ally", 200, [10, 1, 1, 10, 10, 10]), Vector2i(7, 3), [HIT]]})
	assert_not_null(e)
	return e


func _wizard() -> CharacterSheet:
	var s := CoreFixtures.caster("Wizard", Ability.Type.INT, ["fireball", "cone_spray", "bolt_line", "thunder_cube", "frost_shards"], 40)
	s.abilities.set_score(Ability.Type.INT, 30)
	s.spell_slots_max = [4, 3, 3, 1]
	s.spell_slots = [4, 3, 3, 1]
	return s


func _cast(e: Encounter, spell: String, fields: Dictionary) -> Dictionary:
	var f := {"spell": spell}
	f.merge(fields)
	return e.submit(CoreFixtures.intent("cast", "hero", f))


func test_fireball_hits_everyone_in_the_sphere() -> void:
	var e := _fight(_wizard())
	var res := _cast(e, "fireball", {"point": [6, 4], "slot_level": 3})
	assert_true(res["ok"] == true, str(res["error"]))
	var evs := _evs(res)
	assert_eq(CoreFixtures.first_event(evs, "cast"), {"kind": "cast", "actor": "hero", "spell": "fireball", "target": "", "slot_level": 3, "point": [6, 4]})
	var area := CoreFixtures.first_event(evs, "area_effect")
	assert_eq(area["shape"], "sphere")
	assert_eq(area["size_tiles"], 2)
	var affected: Array = area["affected"]
	affected.sort()
	assert_eq(affected, ["a", "ally", "b"], "friendly fire; c is far away")
	assert_eq(CoreFixtures.events_of(evs, "save").size(), 3)
	var dmg := CoreFixtures.events_of(evs, "damage")
	assert_eq(dmg.size(), 3)
	assert_eq(dmg[0]["amount"], dmg[1]["amount"], "one damage roll for every target (all failed)")
	assert_in_range(dmg[0]["amount"], 8, 48)


func test_upcast_fireball_uses_damage_by_slot() -> void:
	var spell: SpellDefinition = content["spells"]["fireball"]
	assert_eq(spell.damage_formula(5, 3), "8d6")
	assert_eq(spell.damage_formula(5, 4), "9d6")
	assert_eq(spell.damage_formula(9, 9), "10d6", "the highest entry at or below the slot")
	assert_eq(spell.save_ability, Ability.Type.DEX, "from saving_throw")
	assert_eq(spell.on_save, "half")


func test_sculpt_spells_protects_allies() -> void:
	var s := _wizard()
	assert_true(str(_cast(_fight(s), "fireball", {"point": [6, 4], "sculpt": ["ally"]})["error"]).contains("Sculpt"))
	s.features.append("sculpt_spells")
	var e := _fight(s)
	assert_true(str(_cast(e, "fireball", {"point": [6, 4], "sculpt": ["a"]})["error"]).contains("not an ally"))
	var res := _cast(e, "fireball", {"point": [6, 4], "sculpt": ["ally"]})
	assert_true(res["ok"] == true, str(res["error"]))
	var area := CoreFixtures.first_event(_evs(res), "area_effect")
	assert_eq(area["sculpted"], ["ally"])
	assert_false("ally" in area["affected"])
	for ev in CoreFixtures.events_of(_evs(res), "damage"):
		assert_ne(ev["target"], "ally")
	assert_eq(e.get_combatant("ally").sheet.current_hp, 200)


func test_self_cone_line_and_cube() -> void:
	var e := _fight(_wizard())
	assert_true(str(_cast(e, "cone_spray", {})["error"]).contains("point"))
	assert_true(str(_cast(e, "cone_spray", {"point": [3, 3]})["error"]).contains("away"))
	var res := _cast(e, "cone_spray", {"point": [6, 3], "slot_level": 2})
	assert_true(res["ok"] == true, str(res["error"]))
	var area := CoreFixtures.first_event(_evs(res), "area_effect")
	assert_has(area["affected"], "a")
	assert_false("hero" in area["affected"])
	assert_in_range(CoreFixtures.first_event(_evs(res), "damage")["amount"], 4, 24)
	var e2 := _fight(_wizard())
	res = _cast(e2, "bolt_line", {"point": [4, 3]})
	assert_true(res["ok"] == true, str(res["error"]))
	var line: Array = CoreFixtures.first_event(_evs(res), "area_effect")["affected"]
	line.sort()
	assert_eq(line, ["a", "ally"], "6 tiles along the row")


func test_thunder_cube_pushes_on_a_failed_save() -> void:
	var e := CoreFixtures.duel(_wizard(), [HIT], {"a": [CoreFixtures.sheet("A", 200, [10, 10, 1, 10, 10, 10]), Vector2i(4, 3), [HIT]]}, content)
	var res := _cast(e, "thunder_cube", {})
	assert_true(res["ok"] == true, str(res["error"]))
	assert_eq(CoreFixtures.first_event(_evs(res), "area_effect")["affected"], ["a"], "self-centred, caster excluded")
	var pushed := CoreFixtures.first_event(_evs(res), "pushed")
	assert_eq(pushed, {"kind": "pushed", "target": "a", "source": "hero", "from": [4, 3], "to": [6, 3]})


func test_area_attack_and_range_checks() -> void:
	var e := _fight(_wizard())
	assert_true(str(_cast(e, "frost_shards", {"point": [7, 7]})["error"]).contains("line of sight"), "the wall at (6, 6)")
	assert_true(str(_cast(e, "cone_spray", {"point": [11, 3], "slot_level": 1, "sculpt": ["hero"]})["error"]).contains("Sculpt"))
	assert_true(str(_cast(e, "frost_shards", {"point": [40, 40]})["error"]).contains("outside"))
	var res := _cast(e, "frost_shards", {"point": [6, 3], "slot_level": 2})
	assert_true(res["ok"] == true, str(res["error"]))
	var attacks := CoreFixtures.events_of(_evs(res), "attack")
	assert_eq(attacks.size(), 3, "a, b and the ally")
	for a in attacks:
		assert_eq(a["spell"], "frost_shards")

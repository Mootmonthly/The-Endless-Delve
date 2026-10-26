extends TestCase
## Round B spells and summons with the real data under data/ (overrides
## applied to the imported spells; real monsters for summons).

const SURE := {"name": "Sure", "kind": "melee", "to_hit": 100, "damage": "4", "damage_type": "slashing", "ability": "STR"}


func test_real_spells_cast_in_an_encounter() -> void:
	var content := ContentLoader.cache()
	var spells: Dictionary = content.get("spells", {})
	var monsters: Dictionary = content.get("monsters", {})
	if not spells.has("web") or not monsters.has("wolf"):
		return
	var cases := [
		[{"spell": "bless", "targets": ["hero"]}, "effect_applied"],
		[{"spell": "web", "point": [8, 3]}, "tile_effect_created"],
		[{"spell": "spiritual_weapon", "point": [7, 3]}, "summoned"],
		[{"spell": "misty_step", "point": [5, 5]}, "teleported"],
		[{"spell": "conjure_animals", "form": "wolf"}, "summoned"],
		[{"spell": "hold_person", "target": "gob"}, "save"],
		[{"spell": "spirit_guardians"}, "tile_effect_created"],
		[{"spell": "sleep", "point": [8, 3]}, "area_effect"],
		[{"spell": "haste", "target": "hero"}, "effect_applied"],
		[{"spell": "flame_strike", "point": [8, 3]}, "save"],
	]
	for case: Array in cases:
		var fields: Dictionary = case[0]
		var id := str(fields["spell"])
		var s := CoreFixtures.caster("Caster", Ability.Type.WIS, [id], 60)
		s.level = 9
		s.spell_slots_max = [4, 3, 3, 3, 1]
		s.spell_slots = [4, 3, 3, 3, 1]
		var gob := CoreFixtures.sheet("Gob", 100)
		gob.class_id = "monster:goblin"
		var e := CoreFixtures.duel(s, [SURE], {"gob": [gob, Vector2i(8, 3), [SURE]]}, content)
		assert_not_null(e)
		var c := e.get_combatant("gob")
		c.monster_id = "goblin"
		c.creature_type = "humanoid"
		var res := e.submit(CoreFixtures.intent("cast", "hero", fields))
		assert_true(res["ok"] == true, "%s: %s" % [id, str(res["error"])])
		assert_has(CoreFixtures.kinds(res.get("events", [])), str(case[1]), id)

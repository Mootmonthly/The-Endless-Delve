extends TestCase
## Round C item 2: walls and terrain (solid / open / opaque tiles), cages,
## wind, barriers, globes, antimagic, falling, phased storms, telekinesis,
## difficult-terrain costs and movement modes.

const SURE := {"name": "Sure", "kind": "melee", "to_hit": 100, "damage": "4", "damage_type": "slashing", "ability": "STR"}
const BOW := {"name": "Bow", "kind": "ranged", "to_hit": 100, "damage": "4", "damage_type": "piercing", "range_tiles": [16, 64]}

var content: Dictionary


func before_each() -> void:
	content = CoreFixtures.content()
	for d: Dictionary in [
		{"id": "wall_of_stone", "level": 5, "range_ft": 120, "concentration": true},
		{"id": "wall_of_ice", "level": 6, "range_ft": 120, "concentration": true},
		{"id": "forcecage", "level": 7, "range_ft": 100, "area": {"shape": "cube", "size_ft": 20}},
		{"id": "resilient_sphere", "level": 4, "range_ft": 30, "concentration": true},
		{"id": "prismatic_wall", "level": 9, "range_ft": 60, "area": {"shape": "line", "size_ft": 90}},
		{"id": "wind_wall", "level": 3, "range_ft": 120, "concentration": true, "area": {"shape": "line", "size_ft": 50}},
		{"id": "antilife_shell", "level": 5, "range_ft": 0, "target": "self", "concentration": true, "area": {"shape": "sphere", "size_ft": 10}},
		{"id": "globe_of_invulnerability", "level": 6, "range_ft": 0, "target": "self", "concentration": true, "area": {"shape": "sphere", "size_ft": 10}},
		{"id": "antimagic_field", "level": 8, "range_ft": 0, "target": "self", "concentration": true, "area": {"shape": "sphere", "size_ft": 10}},
		{"id": "reverse_gravity", "level": 7, "range_ft": 100, "concentration": true, "area": {"shape": "cylinder", "size_ft": 10}},
		{"id": "earthquake", "level": 8, "range_ft": 500, "concentration": true, "area": {"shape": "sphere", "size_ft": 20}},
		{"id": "storm_of_vengeance", "level": 9, "range_ft": 0, "concentration": true, "area": {"shape": "sphere", "size_ft": 360}},
		{"id": "telekinesis", "level": 5, "range_ft": 60, "concentration": true},
		{"id": "passwall", "level": 5, "range_ft": 30},
		{"id": "stone_shape", "level": 4, "range_ft": 5},
		{"id": "plant_growth", "level": 3, "range_ft": 150},
		{"id": "spider_climb", "level": 2, "range_ft": 5, "concentration": true},
		{"id": "feather_fall", "level": 1, "casting_time": "reaction", "range_ft": 60},
		{"id": "arcane_hand", "level": 5, "range_ft": 120, "concentration": true},
		{"id": "bless", "level": 1, "range_ft": 30, "concentration": true},
		{"id": "move_earth", "level": 6, "range_ft": 120, "concentration": true},
	]:
		var base := {"display_name": str(d["id"]).capitalize(), "effect": {"type": "unsupported"}}
		base.merge(d, true)
		var sdef := CoreFixtures.spell(base)
		assert_not_null(sdef, str(d["id"]))
		content["spells"][sdef.id] = sdef


func _evs(res: Dictionary) -> Array:
	var evs: Array = res.get("events", [])
	return evs


## DC 20+ caster with plenty of slots.
func _caster(prepared: Array[String]) -> CharacterSheet:
	var s := CoreFixtures.caster("Mage", Ability.Type.INT, prepared, 80)
	s.abilities.set_score(Ability.Type.INT, 30)
	s.spell_slots_max = [4, 3, 3, 3, 3, 2, 2, 1, 1]
	s.spell_slots = [4, 3, 3, 3, 3, 2, 2, 1, 1]
	return s


func _gob(hp: int = 200) -> CharacterSheet:
	return CoreFixtures.sheet("Gob", hp, [1, 1, 1, 1, 1, 1])


func _fight(hero: CharacterSheet, foes: Dictionary = {}, allies: Dictionary = {}, hero_pos: Vector2i = Vector2i(3, 3)) -> Encounter:
	var f := foes if not foes.is_empty() else {"gob": [_gob(), Vector2i(9, 3), [SURE]]}
	var e := CoreFixtures.duel(hero, [SURE], f, content, "hero", hero_pos, allies)
	assert_not_null(e)
	return e


## Ends turns until `id` acts.
func _until(e: Encounter, id: String) -> void:
	for _i in range(20):
		if e.current_actor() == null or e.current_actor().id == id:
			return
		e.end_turn()


func _cast(e: Encounter, fields: Dictionary, actor: String = "hero") -> Dictionary:
	var res := e.submit(CoreFixtures.intent("cast", actor, fields))
	assert_true(res["ok"] == true, "%s: %s" % [str(fields.get("spell", "")), str(res["error"])])
	return res


func test_wall_of_stone_blocks_movement_and_sight_and_pushes() -> void:
	var e := _fight(_caster(["wall_of_stone", "bless"]), {}, {"ally": [CoreFixtures.sheet("Ally", 30), Vector2i(6, 4)]})
	assert_true(e.walk_map.has_line_of_sight(Vector2i(3, 3), Vector2i(9, 3)))
	var res := _cast(e, {"spell": "wall_of_stone", "point": [6, 3]})
	assert_false(e.walk_map.is_walkable(Vector2i(6, 3)), "the wall is solid")
	assert_false(e.walk_map.has_line_of_sight(Vector2i(3, 3), Vector2i(9, 3)), "and blocks sight")
	var changed := CoreFixtures.first_event(_evs(res), "terrain_changed")
	assert_has(changed["walls"], [6, 3])
	assert_eq(CoreFixtures.first_event(_evs(res), "tile_effect_created")["terrain"], "solid")
	var pushed := CoreFixtures.first_event(_evs(res), "pushed")
	assert_eq(pushed["target"], "ally", "a creature in the wall's path is pushed aside")
	assert_true(e.walk_map.is_walkable(e.get_combatant("ally").position))
	_until(e, "gob")
	var gob := e.get_combatant("gob")
	assert_true(str(e.submit(CoreFixtures.intent("move", "gob", {"path": [[8, 3], [7, 3], [6, 3]]}))["error"]).contains("cannot step"))
	_until(e, "hero")
	res = _cast(e, {"spell": "bless", "targets": ["hero"]})
	assert_true(e.walk_map.is_walkable(Vector2i(6, 3)), "concentration ends the wall")
	assert_has(CoreFixtures.first_event(_evs(res), "terrain_changed")["floors"], [6, 3])
	assert_false(e.walk_map.is_walkable(Vector2i(6, 6)), "the floor's own wall stays")
	assert_not_null(gob)


func test_wall_of_ice_damages_on_creation() -> void:
	var e := _fight(_caster(["wall_of_ice"]), {"gob": [_gob(), Vector2i(6, 3), [SURE]]})
	var res := _cast(e, {"spell": "wall_of_ice", "point": [6, 3]})
	var dmg := CoreFixtures.first_event(_evs(res), "damage")
	assert_eq([dmg["target"], dmg["type"]], ["gob", "cold"])
	assert_ne(e.get_combatant("gob").position, Vector2i(6, 3), "then pushed out of the ice")


func test_forcecage_traps_its_prisoner() -> void:
	var e := _fight(_caster(["forcecage"]))
	_cast(e, {"spell": "forcecage", "point": [9, 3]})
	var gob := e.get_combatant("gob")
	for p: Vector2i in [Vector2i(11, 3), Vector2i(7, 3), Vector2i(9, 1), Vector2i(9, 5)]:
		assert_false(e.walk_map.is_walkable(p), "bar at %s" % str(p))
	assert_true(e.walk_map.is_walkable(Vector2i(8, 3)), "inside stays open")
	assert_eq(e.walk_map.path_to(gob.position, Vector2i(3, 3), e.occupied_cells(gob.id)), [] as Array[Vector2i], "no way out")


func test_resilient_sphere_seals_both_ways() -> void:
	var e := _fight(_caster(["resilient_sphere"]), {"gob": [_gob(), Vector2i(4, 3), [SURE]]})
	_cast(e, {"spell": "resilient_sphere", "target": "gob"})
	var gob := e.get_combatant("gob")
	assert_true(gob.is_sealed())
	e.get_combatant("hero").action_used = false
	assert_true(str(e.submit(CoreFixtures.intent("attack", "hero", {"target": "gob", "attack_index": 0}))["error"]).contains("sealed"))
	assert_eq(gob.adjust_damage(40, "fire", true), 0, "nothing passes the sphere")
	e.end_turn()
	assert_true(str(e.submit(CoreFixtures.intent("attack", "gob", {"target": "hero", "attack_index": 0}))["error"]).contains("sealed"))
	assert_eq(gob.speed_tiles(), 0)


func test_prismatic_wall_layers_on_entry_and_opaque() -> void:
	var e := _fight(_caster(["prismatic_wall"]), {"gob": [_gob(500), Vector2i(8, 3), [SURE]]})
	_cast(e, {"spell": "prismatic_wall", "point": [6, 3]})
	assert_true(e.walk_map.is_walkable(Vector2i(6, 3)), "the wall can be crossed")
	assert_true(e.walk_map.is_opaque(Vector2i(6, 3)))
	assert_false(e.walk_map.has_line_of_sight(Vector2i(3, 3), Vector2i(9, 3)), "but not seen through")
	e.end_turn()
	var res := e.submit(CoreFixtures.intent("move", "gob", {"path": [[7, 3], [6, 3]]}))
	assert_true(res["ok"] == true, str(res["error"]))
	var layers: Array = []
	for d in CoreFixtures.events_of(_evs(res), "damage"):
		layers.append(d["layer"])
	assert_eq(layers, ["red", "orange", "yellow", "green", "blue"], "five damage layers in order")
	var gob := e.get_combatant("gob")
	assert_true(gob.has_condition(Conditions.RESTRAINED) or gob.has_condition(Conditions.BLINDED), "indigo / violet on failed saves")


func test_wind_wall_stops_arrows() -> void:
	var e := _fight(_caster(["wind_wall"]), {"gob": [_gob(), Vector2i(9, 3), [BOW]]})
	_cast(e, {"spell": "wind_wall", "point": [6, 3]})
	e.end_turn()
	var res := e.submit(CoreFixtures.intent("attack", "gob", {"target": "hero", "attack_index": 0}))
	assert_true(res["ok"] == true, str(res["error"]))
	assert_eq(CoreFixtures.first_event(_evs(res), "attack_lost")["reason"], "wind_wall")
	assert_true(CoreFixtures.events_of(_evs(res), "attack").is_empty())


func test_antilife_shell_keeps_the_living_out() -> void:
	var zombie := _gob()
	var e := _fight(_caster(["antilife_shell"]), {"gob": [_gob(), Vector2i(4, 3), [SURE]], "zed": [zombie, Vector2i(3, 5), [SURE]]})
	e.get_combatant("zed").creature_type = "undead"
	var res := _cast(e, {"spell": "antilife_shell"})
	var gob := e.get_combatant("gob")
	assert_eq(CoreFixtures.first_event(_evs(res), "pushed")["target"], "gob", "pushed out of the shell")
	assert_true(GridMath.distance_tiles(gob.position, Vector2i(3, 3)) > 2)
	assert_eq(e.get_combatant("zed").position, Vector2i(3, 5), "undead are not barred")
	while e.current_actor().id != "gob":
		e.end_turn()
	var step := gob.position + Vector2i(-1, 0)
	assert_true(str(e.submit(CoreFixtures.intent("move", "gob", {"path": [GridMath.vec_to_arr(step)]}))["error"]).contains("holds"))


func test_globe_of_invulnerability_blocks_lower_spells() -> void:
	var foe := _caster(["fire_bolt"])
	var e := _fight(_caster(["globe_of_invulnerability"]), {"mage": [foe, Vector2i(9, 3), [SURE]]})
	_cast(e, {"spell": "globe_of_invulnerability"})
	e.end_turn()
	var err := str(e.submit(CoreFixtures.intent("cast", "mage", {"spell": "fire_bolt", "target": "hero"}))["error"])
	assert_true(err.contains("globe of invulnerability"), err)


func test_antimagic_field_suppresses_magic() -> void:
	var e := _fight(_caster(["antimagic_field", "bless"]), {"gob": [_gob(), Vector2i(4, 3), [SURE]]})
	_cast(e, {"spell": "bless", "targets": ["hero"]})
	var hero := e.get_combatant("hero")
	assert_eq(hero.buff_dice("attack_dice"), ["1d4"] as Array[String])
	e.end_turn()
	e.end_turn()
	_cast(e, {"spell": "antimagic_field"})
	assert_true(hero.antimagic and e.get_combatant("gob").antimagic)
	assert_true(hero.buff_dice("attack_dice").is_empty(), "spell buffs are suppressed")
	e.end_turn()
	e.end_turn()
	assert_true(str(e.submit(CoreFixtures.intent("cast", "hero", {"spell": "bless", "targets": ["hero"]}))["error"]).contains("antimagic"))


func test_reverse_gravity_fall_and_feather_fall() -> void:
	var hero := _caster(["reverse_gravity", "feather_fall"])
	var e := _fight(hero, {"gob": [_gob(), Vector2i(8, 3), [SURE]]}, {"ally": [CoreFixtures.sheet("Ally", 30, [10, 1, 10, 10, 10, 10]), Vector2i(8, 5)]})
	var res := _cast(e, {"spell": "reverse_gravity", "point": [8, 4]})
	var falls: Array = []
	for d in CoreFixtures.events_of(_evs(res), "damage"):
		if d.get("fall", false) == true:
			falls.append([d["target"], d["amount"]])
	assert_true(e.get_combatant("gob").has_condition(Conditions.PRONE), "the goblin falls")
	var used := CoreFixtures.first_event(_evs(res), "reaction_used")
	assert_eq([used["reaction"], used["trigger"], used["target"]], ["feather_fall", "falling", "ally"], "the hero saves its ally")
	assert_has(falls, ["ally", 0])
	assert_eq(e.get_combatant("hero").sheet.slots_left(1), 3)


func test_slow_fall_reduces_falling_damage() -> void:
	var monk := CoreFixtures.sheet("Monk", 60, [10, 1, 10, 10, 10, 10], ["slow_fall"])
	monk.level = 10
	var e := _fight(_caster(["reverse_gravity"]), {"gob": [_gob(), Vector2i(9, 9), [SURE]]}, {"monk": [monk, Vector2i(8, 3)]})
	var res := _cast(e, {"spell": "reverse_gravity", "point": [8, 3]})
	var used := CoreFixtures.first_event(_evs(res), "reaction_used")
	assert_eq(used["reaction"], "slow_fall")
	assert_eq(e.get_combatant("monk").sheet.current_hp, 60, "50 points of slow fall soak 4d6")


func test_earthquake_knocks_prone_and_breaks_concentration() -> void:
	var e := _fight(_caster(["earthquake"]), {"gob": [_gob(), Vector2i(9, 3), [SURE]]})
	var gob := e.get_combatant("gob")
	gob.concentration = {"spell": "bless", "slot_level": 1}
	var res := _cast(e, {"spell": "earthquake", "point": [9, 3]})
	assert_true(gob.has_condition(Conditions.PRONE))
	assert_eq(CoreFixtures.first_event(_evs(res), "concentration_ended")["reason"], "earthquake")
	e.end_turn()
	e.submit(CoreFixtures.intent("stand", "gob"))
	e.end_turn()
	assert_true(gob.has_condition(Conditions.PRONE), "again at the caster's next turn")


func test_storm_of_vengeance_phases() -> void:
	var hero := _caster(["storm_of_vengeance"])
	hero.abilities.set_score(Ability.Type.CON, 30)
	hero.max_hp = 300
	hero.current_hp = 300
	var e := _fight(hero, {"gob": [_gob(500), Vector2i(9, 3), [SURE]]})
	var res := _cast(e, {"spell": "storm_of_vengeance"})
	var types: Array = []
	for d in CoreFixtures.events_of(_evs(res), "damage"):
		if d["target"] == "gob":
			types.append(d["type"])
	assert_eq(types, ["thunder"])
	assert_true(e.get_combatant("gob").has_condition(Conditions.DEAFENED))
	var seen: Array = []
	for _round in range(4):
		var start := e.events.size()
		e.end_turn()
		e.end_turn()
		for d in CoreFixtures.events_of(e.events_since(start), "damage"):
			if d["target"] == "gob":
				seen.append(d["type"])
	assert_eq(seen, ["acid", "lightning", "bludgeoning", "cold"])
	var fx: Dictionary = e.tile_effects[0]
	assert_true(fx["difficult"] == true and fx["wind"] == true, "gusts and freezing rain")


func test_telekinesis_moves_and_restrains() -> void:
	var e := _fight(_caster(["telekinesis"]), {"gob": [_gob(), Vector2i(9, 3), [SURE]]})
	assert_true(str(e.submit(CoreFixtures.intent("cast", "hero", {"spell": "telekinesis", "target": "gob", "point": [2, 9]}))["error"]).length() > 0, "too far for 30 ft")
	var res := _cast(e, {"spell": "telekinesis", "target": "gob", "point": [9, 0]})
	assert_eq(CoreFixtures.first_event(_evs(res), "contest")["reason"], "telekinesis")
	var gob := e.get_combatant("gob")
	assert_eq(gob.position, Vector2i(9, 0))
	assert_true(gob.has_condition(Conditions.RESTRAINED))
	e.end_turn()
	e.end_turn()
	res = _cast(e, {"spell": "telekinesis", "target": "gob", "point": [9, 4], "sustain": true})
	assert_eq(gob.position, Vector2i(9, 4), "sustained with an action")
	assert_eq(res["events"][0]["slot_level"], 5)


func test_passwall_and_stone_shape_change_the_map() -> void:
	var m := WalkMap.new(12, 12, true)
	for y in range(12):
		m.set_walkable(Vector2i(5, y), false)
	var make := func() -> Array:
		var hero := CoreFixtures.combatant("hero", _caster(["passwall", "stone_shape"]), Combatant.TEAM_PLAYERS, Vector2i(4, 3), [SURE])
		var gob := CoreFixtures.combatant("gob", _gob(), Combatant.TEAM_MONSTERS, Vector2i(9, 3), [SURE])
		return [hero, gob]
	var e := CoreFixtures.fight(make, "hero", content, m)
	assert_true(str(e.submit(CoreFixtures.intent("cast", "hero", {"spell": "passwall", "point": [4, 4]}))["error"]).contains("wall"))
	var res := _cast(e, {"spell": "passwall", "point": [5, 3]})
	assert_true(e.walk_map.is_walkable(Vector2i(5, 3)), "a passage through the wall")
	assert_has(CoreFixtures.first_event(_evs(res), "terrain_changed")["floors"], [5, 3])
	e.end_turn()
	e.end_turn()
	res = _cast(e, {"spell": "stone_shape", "point": [4, 4], "mode": "wall"})
	assert_false(e.walk_map.is_walkable(Vector2i(4, 4)), "a new pillar")


func test_plant_growth_costs_four_per_step() -> void:
	var e := _fight(_caster(["plant_growth"]), {"gob": [_gob(), Vector2i(9, 3), [SURE]]})
	_cast(e, {"spell": "plant_growth", "point": [9, 3]})
	e.end_turn()
	var gob := e.get_combatant("gob")
	assert_eq(e._step_cost(gob, Vector2i(8, 3), "walk"), 4)
	assert_eq(e._step_cost(e.get_combatant("hero"), Vector2i(8, 3), "walk"), 1, "the caster's side is spared")


func test_spider_climb_and_arcane_hand() -> void:
	var e := _fight(_caster(["spider_climb", "arcane_hand"]))
	_cast(e, {"spell": "spider_climb", "target": "hero"})
	assert_true(e.get_combatant("hero").ignores_ground())
	e.end_turn()
	e.end_turn()
	var res := _cast(e, {"spell": "arcane_hand", "point": [8, 3]})
	var hand := e.get_combatant(str(CoreFixtures.first_event(_evs(res), "summoned")["id"]))
	assert_false(hand.untargetable, "the hand can be attacked")
	assert_eq([hand.sheet.max_hp, hand.armor_class()], [80, 20])
	assert_eq(hand.attacks[0]["damage"], "4d8")


func test_move_earth_raises_ground() -> void:
	var e := _fight(_caster(["move_earth"]), {"gob": [_gob(), Vector2i(9, 9), [SURE]]})
	var res := _cast(e, {"spell": "move_earth", "point": [8, 3], "mode": "raise"})
	assert_false(e.walk_map.is_walkable(Vector2i(8, 3)))
	assert_eq((CoreFixtures.first_event(_evs(res), "terrain_changed")["walls"] as Array).size(), 25)

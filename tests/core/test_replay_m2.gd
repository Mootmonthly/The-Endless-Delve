extends TestCase
## Replay determinism with the M2 intents: cast, use_item, use_feature,
## ranged and thrown attacks (with ammunition and thrown weapons used up).

const SEED := 777
const CLAW := {"name": "Claw", "kind": "melee", "to_hit": 4, "damage": "1d6+2", "damage_type": "slashing"}
const BOW := {"name": "Shortbow", "kind": "ranged", "to_hit": 4, "damage": "1d6+2", "damage_type": "piercing", "range_tiles": [16, 64]}

var content: Dictionary
var map: WalkMap
var region: Rect2i


func before_each() -> void:
	content = CoreFixtures.content()
	map = WalkMap.from_rows([
		"##############",
		"#............#",
		"#....#.......#",
		"#....#.......#",
		"#............#",
		"#.......##...#",
		"#............#",
		"##############",
	])
	region = Rect2i(1, 1, 12, 6)


func _party() -> Array[Combatant]:
	var wiz := CoreFixtures.caster("Wiz", Ability.Type.INT, ["fire_bolt", "magic_missile", "mage_armor"], 14)
	wiz.add_item("potion_of_healing", 1)
	var fighter := CoreFixtures.sheet("Fighter", 24, [16, 12, 14, 10, 10, 10], ["second_wind"])
	fighter.add_item("longsword")
	fighter.add_item("handaxe", 2)
	fighter.add_item("potion_of_healing", 2)
	fighter.equip("longsword", "main_hand", content)
	var archer := CoreFixtures.sheet("Archer", 18, [10, 16, 12, 10, 10, 10], ["sneak_attack"])
	archer.add_item("shortbow")
	archer.add_item("arrows", 6)
	archer.equip("shortbow", "main_hand", content)
	var out: Array[Combatant] = []
	var spots: Array[Vector2i] = [Vector2i(1, 1), Vector2i(2, 3), Vector2i(1, 5)]
	var sheets: Array[CharacterSheet] = [wiz, fighter, archer]
	var ids: Array[String] = ["wiz", "fighter", "archer"]
	for i in range(3):
		var c := Combatant.from_sheet(ids[i], sheets[i], Combatant.TEAM_PLAYERS)
		c.position = spots[i]
		out.append(c)
	return out


func _monsters() -> Array[Combatant]:
	var out: Array[Combatant] = []
	var spots: Array[Vector2i] = [Vector2i(11, 1), Vector2i(12, 4), Vector2i(11, 6)]
	for i in range(3):
		var s := CoreFixtures.sheet("Gob %d" % i, 12, [10, 14, 10, 10, 10, 10])
		s.uses_death_saves = false
		var c := Combatant.from_sheet("gob_%d" % i, s, Combatant.TEAM_MONSTERS)
		c.attacks = [CLAW.duplicate(), BOW.duplicate()]
		c.position = spots[i]
		out.append(c)
	return out


func _nearest_hostile(e: Encounter, me: Combatant) -> Combatant:
	var best: Combatant = null
	for h in e.hostiles_of(me):
		if not h.is_conscious():
			continue
		if best == null or GridMath.distance_tiles(me.position, h.position) < GridMath.distance_tiles(me.position, best.position):
			best = h
	return best


## A simple player policy that exercises every M2 intent.
func _player_turn(e: Encounter, me: Combatant) -> void:
	var target := _nearest_hostile(e, me)
	var v := Encounter.INTENT_VERSION
	match me.id:
		"wiz":
			if e.tracker.round_number == 1:
				e.submit({"v": v, "type": "cast", "actor": "wiz", "spell": "mage_armor", "target": "wiz", "slot_level": 1})
			elif me.sheet.current_hp * 2 < me.sheet.max_hp and me.sheet.has_item("potion_of_healing"):
				e.submit({"v": v, "type": "use_item", "actor": "wiz", "item": "potion_of_healing"})
			elif target != null and me.sheet.slots_left(1) > 0:
				e.submit({"v": v, "type": "cast", "actor": "wiz", "spell": "magic_missile", "target": target.id, "slot_level": 1})
			elif target != null:
				e.submit({"v": v, "type": "cast", "actor": "wiz", "spell": "fire_bolt", "target": target.id, "slot_level": 0})
		"fighter":
			if me.sheet.current_hp * 2 < me.sheet.max_hp and me.sheet.class_resource("second_wind") > 0:
				e.submit({"v": v, "type": "use_feature", "actor": "fighter", "feature": "second_wind"})
			if me.sheet.current_hp * 2 < me.sheet.max_hp and me.sheet.has_item("potion_of_healing"):
				e.submit({"v": v, "type": "use_item", "actor": "fighter", "item": "potion_of_healing"})
			elif target != null and GridMath.is_adjacent(me.position, target.position):
				e.submit({"v": v, "type": "attack", "actor": "fighter", "target": target.id, "attack_index": 0})
			elif target != null:
				var res := e.submit({"v": v, "type": "attack", "actor": "fighter", "target": target.id, "attack_index": 1})
				if not res["ok"]:
					var path := e.walk_map.path_to(me.position, target.position, e.occupied_cells(me.id))
					if not path.is_empty():
						path.resize(mini(path.size(), me.movement_remaining))
						e.submit({"v": v, "type": "move", "actor": "fighter", "path": GridMath.vec_list_to_arr(path)})
		"archer":
			if target != null:
				e.submit({"v": v, "type": "attack", "actor": "archer", "target": target.id, "attack_index": 0})
	if e.state == Encounter.State.ACTIVE and e.current_actor() == me:
		e.submit({"v": v, "type": "end_turn", "actor": me.id})


func _scripted_fight() -> Encounter:
	var e := Encounter.new("m2", Rng.new(SEED), map, region)
	e.content = content
	for c in _party() + _monsters():
		assert_true(e.add_combatant(c), c.id)
	assert_true(e.start())
	for _turn in range(300):
		if e.state != Encounter.State.ACTIVE:
			break
		var actor := e.current_actor()
		if actor.team == Combatant.TEAM_PLAYERS:
			_player_turn(e, actor)
		else:
			for intent in MonsterBrain.decide(e, actor.id):
				if not e.submit(intent)["ok"]:
					break
	return e


func _intent_types(e: Encounter) -> Array[String]:
	var out: Array[String] = []
	for intent in e.intent_log:
		out.append(str(intent["type"]))
	return out


func test_fight_uses_the_new_intents() -> void:
	var e := _scripted_fight()
	assert_eq(e.state, Encounter.State.ENDED)
	var types := _intent_types(e)
	assert_has(types, "cast")
	assert_has(types, "attack")
	var kinds := CoreFixtures.kinds(e.events)
	assert_has(kinds, "cast")
	assert_has(kinds, "effect_applied")
	var ranged := false
	for ev in CoreFixtures.events_of(e.events, "attack"):
		if ev["attack_kind"] in ["ranged", "thrown"]:
			ranged = true
	assert_true(ranged, "someone shot or threw")
	assert_true(e.get_combatant("archer").sheet.count_item("arrows") < 6, "arrows were used")


func test_replay_reproduces_m2_events_after_json_round_trip() -> void:
	var e := _scripted_fight()
	var setup := DictUtil.to_dict_array(JSON.parse_string(JSON.stringify(e.setup_snapshot())))
	var intents := DictUtil.to_dict_array(JSON.parse_string(JSON.stringify(e.intent_log)))
	var copy := Encounter.replay(e.rng_seed, map, region, setup, intents, "replay", content)
	assert_eq(JSON.stringify(copy.events), JSON.stringify(e.events))
	for c in e.combatants():
		var other := copy.get_combatant(c.id)
		assert_eq(other.sheet.current_hp, c.sheet.current_hp, c.id)
		assert_eq(other.sheet.inventory, c.sheet.inventory, "%s inventory" % c.id)
		assert_eq(other.sheet.spell_slots, c.sheet.spell_slots, "%s slots" % c.id)


func test_replay_with_use_item_and_feature_in_the_log() -> void:
	# A short fight driven by hand so the log certainly holds use_item,
	# use_feature, a ranged attack, a thrown attack and a cast.
	var make := func() -> Array:
		var all: Array = []
		var party := _party()
		party[1].sheet.current_hp = 5  # the fighter starts hurt (before the setup snapshot)
		all.append_array(party)
		var gob := _monsters()[0]
		gob.position = Vector2i(8, 1)
		all.append(gob)
		return all
	var e := CoreFixtures.fight(make, "wiz", content, map, region)
	assert_not_null(e)
	var v := Encounter.INTENT_VERSION
	var done := {}
	for _turn in range(40):
		if e.state != Encounter.State.ACTIVE:
			break
		var me := e.current_actor()
		match me.id:
			"wiz":
				if e.submit({"v": v, "type": "cast", "actor": "wiz", "spell": "fire_bolt", "target": "gob_0", "slot_level": 0})["ok"]:
					done["cast"] = true
			"fighter":
				if e.submit({"v": v, "type": "use_feature", "actor": "fighter", "feature": "second_wind"})["ok"]:
					done["use_feature"] = true
				if e.submit({"v": v, "type": "use_item", "actor": "fighter", "item": "potion_of_healing"})["ok"]:
					done["use_item"] = true
				elif e.submit({"v": v, "type": "attack", "actor": "fighter", "target": "gob_0", "attack_index": 1})["ok"]:
					done["thrown"] = true
			"archer":
				if e.submit({"v": v, "type": "attack", "actor": "archer", "target": "gob_0", "attack_index": 0})["ok"]:
					done["ranged"] = true
			_:
				for intent in MonsterBrain.decide(e, me.id):
					if not e.submit(intent)["ok"]:
						break
		if e.state == Encounter.State.ACTIVE and e.current_actor() == me:
			e.end_turn()
	for key: String in ["cast", "use_feature", "use_item", "ranged"]:
		assert_true(done.has(key), key)
	var copy := Encounter.replay(e.rng_seed, map, region, e.setup_snapshot(), e.intent_log, "replay", content)
	assert_eq(copy.events, e.events)
	assert_eq(copy.intent_log, e.intent_log)

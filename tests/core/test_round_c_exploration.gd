extends TestCase
## Round C item 7: exploration utilities (exploration_effect events, knock /
## locks, reveals, teleport landmarks), light and darkness (set_light,
## darkvision, lit tiles, magical darkness, Daylight), Pass without Trace,
## Gentle Repose, Heroes' Feast, Meld into Stone, Goodberry, declared
## no_effect spells, senses parsing and locked chests. Real data spells.

const SURE := {"name": "Sure", "kind": "melee", "to_hit": 100, "damage": "4", "damage_type": "slashing", "ability": "STR"}
const SPELLS: Array[String] = ["knock", "teleport", "detect_magic", "light", "daylight", "darkness", "darkvision", "pass_without_trace",
	"gentle_repose", "revivify", "heroes_feast", "meld_into_stone", "goodberry", "detect_thoughts", "tongues", "word_of_recall", "dancing_lights"]

var content: Dictionary


func before_each() -> void:
	content = CoreFixtures.content()
	for id in SPELLS:
		var sdef := SpellDefinition.from_dict(ContentLoader.load_json("res://data/spells/%s.json" % id))
		assert_not_null(sdef, id)
		content["spells"][id] = sdef


func _evs(res: Dictionary) -> Array:
	var evs: Array = res.get("events", [])
	return evs


func _caster(prepared: Array[String]) -> CharacterSheet:
	var s := CoreFixtures.caster("Mage", Ability.Type.WIS, prepared, 80)
	s.abilities.set_score(Ability.Type.WIS, 30)
	s.class_id = "cleric"
	s.level = 17
	s.spell_slots_max = [4, 3, 3, 3, 3, 2, 2, 1, 1]
	s.spell_slots = [4, 3, 3, 3, 3, 2, 2, 1, 1]
	return s


func _gob(hp: int = 200) -> CharacterSheet:
	return CoreFixtures.sheet("Gob", hp, [1, 1, 1, 1, 1, 1])


func _fight(hero: CharacterSheet, foes: Dictionary = {}, light: String = Encounter.LIGHT_BRIGHT, map: WalkMap = null) -> Encounter:
	var f := foes if not foes.is_empty() else {"gob": [_gob(), Vector2i(9, 3), [SURE]]}
	var make := func() -> Array:
		var all: Array = [CoreFixtures.combatant("hero", CharacterSheet.from_dict(hero.to_dict()), Combatant.TEAM_PLAYERS, Vector2i(3, 3), [SURE])]
		var keys: Array = f.keys()
		keys.sort()
		for key: Variant in keys:
			var spec: Array = f[key]
			var s: CharacterSheet = spec[0]
			all.append(CoreFixtures.combatant(str(key), CharacterSheet.from_dict(s.to_dict()), Combatant.TEAM_MONSTERS, spec[1], [SURE]))
		return all
	var m := map
	if m == null:
		m = WalkMap.new(12, 12, true)
		m.set_walkable(Vector2i(6, 6), false)
	for seed_value in range(1, 500):
		var e := Encounter.new("t", Rng.new(seed_value), m, Rect2i(0, 0, 12, 12))
		e.content = content
		for c_v: Variant in make.call():
			e.add_combatant(c_v as Combatant)
		e.set_light(light)
		e.start()
		if e.current_actor() != null and e.current_actor().id == "hero":
			return e
	fail("no seed")
	return null


func _cast(e: Encounter, fields: Dictionary, actor: String = "hero") -> Dictionary:
	var res := e.submit(CoreFixtures.intent("cast", actor, fields))
	assert_true(res["ok"] == true, "%s: %s" % [str(fields.get("spell", "")), str(res["error"])])
	return res


func test_every_srd_spell_is_castable() -> void:
	var spells: Dictionary = ContentLoader.load_spells()
	var stuck: Array[String] = []
	for id: Variant in spells.keys():
		if not (spells[id] as SpellDefinition).is_castable():
			stuck.append(str(id))
	assert_eq(stuck, [] as Array[String], "every SRD spell has a mechanic or a declared no_effect")


func test_knock_unlocks_a_chest_out_of_combat() -> void:
	var s := _caster(["knock"])
	var r := OutOfCombat.cast(s, "knock", content, Rng.new(1), [], {"target_kind": "chest", "target_id": "c3", "caster_id": "p1"})
	assert_true(r["ok"] == true, str(r["error"]))
	var ev := CoreFixtures.first_event(r["events"], "exploration_effect")
	assert_eq([ev["actor"], ev["spell"], ev["effect"], ev["target_kind"], ev["target_id"], ev["range_ft"]], ["p1", "knock", "unlock", "chest", "c3", 60])
	assert_eq(s.spell_slots[1], 2, "knock spends a 2nd-level slot")
	assert_false(OutOfCombat.cast(s, "knock", content, Rng.new(1), [], {"target_kind": "zone"})["ok"] == true)


func test_knock_in_a_fight_emits_the_event() -> void:
	var e := _fight(_caster(["knock"]))
	var res := _cast(e, {"spell": "knock", "target_kind": "door", "target_id": "d1"})
	var ev := CoreFixtures.first_event(_evs(res), "exploration_effect")
	assert_eq([ev["effect"], ev["target_id"]], ["unlock", "d1"])


func test_teleport_and_reveals_name_their_hooks() -> void:
	var s := _caster(["teleport", "detect_magic", "word_of_recall"])
	assert_false(OutOfCombat.cast(s, "teleport", content, Rng.new(1), [], {"target_kind": "landmark", "target_id": "moon"})["ok"] == true)
	var r := OutOfCombat.cast(s, "teleport", content, Rng.new(1), [], {"target_kind": "landmark", "target_id": "stairs"})
	assert_eq(CoreFixtures.first_event(r["events"], "exploration_effect")["effect"], "teleport")
	r = OutOfCombat.cast(s, "detect_magic", content, Rng.new(1), [], {"ritual": true})
	var ev := CoreFixtures.first_event(r["events"], "exploration_effect")
	assert_eq([ev["reveal"], ev["radius_ft"]], ["magic_items", 30])
	assert_eq(r["slot_level"], 0, "a ritual spends no slot")
	var ally := CoreFixtures.sheet("Ally")
	r = OutOfCombat.cast(s, "word_of_recall", content, Rng.new(1), [s, ally], {"target_ids": ["p1", "p2"]})
	assert_eq(CoreFixtures.first_event(r["events"], "exploration_effect")["targets"], ["p1", "p2"])


func test_darkness_hides_creatures_without_darkvision() -> void:
	var e := _fight(_caster([]), {}, Encounter.LIGHT_DARK)
	var hero := e.get_combatant("hero")
	var gob := e.get_combatant("gob")
	assert_eq(CoreFixtures.first_event(e.events, "encounter_started")["light"], "dark")
	assert_false(e.can_see(hero, gob), "no darkvision in the dark")
	gob.sheet.darkvision_ft = 60
	assert_true(e.can_see(gob, hero), "darkvision 60 ft reaches 6 tiles")
	gob.position = Vector2i(11, 3)
	gob.sheet.darkvision_ft = 30
	assert_false(e.can_see(gob, hero), "beyond darkvision range")
	assert_true(e.set_light(Encounter.LIGHT_DIM))
	assert_true(e.can_see(hero, gob), "dim light is enough to fight")


func test_light_lingers_and_lights_its_bearer() -> void:
	var s := _caster(["light"])
	var r := OutOfCombat.cast(s, "light", content, Rng.new(1))
	assert_true(r["ok"] == true, str(r["error"]))
	assert_eq(s.lingering[0]["kind"], "light")
	var e := _fight(s, {}, Encounter.LIGHT_DARK)
	var hero := e.get_combatant("hero")
	var gob := e.get_combatant("gob")
	assert_true(e.can_see(gob, hero), "the hero stands in its own light")
	assert_false(e.can_see(hero, gob), "the goblin is outside the 20-ft light")
	gob.position = Vector2i(6, 3)
	assert_true(e.can_see(hero, gob))


func test_darkvision_spell_and_magical_darkness() -> void:
	var e := _fight(_caster(["darkvision", "darkness"]), {}, Encounter.LIGHT_DARK)
	var hero := e.get_combatant("hero")
	var gob := e.get_combatant("gob")
	_cast(e, {"spell": "darkvision"})
	assert_true(e.can_see(hero, gob), "darkvision 60 ft")
	e.get_combatant("hero").action_used = false
	_cast(e, {"spell": "darkness", "point": [9, 3]})
	assert_false(e.can_see(hero, gob), "magical darkness defeats darkvision")
	hero.sheet.invocations.append("devils_sight")
	assert_true(e.can_see(hero, gob), "Devil's Sight sees through it")


func test_daylight_dispels_darkness() -> void:
	var e := _fight(_caster(["daylight", "darkness"]), {}, Encounter.LIGHT_DARK)
	_cast(e, {"spell": "darkness", "point": [9, 3]})
	e.get_combatant("hero").action_used = false
	var res := _cast(e, {"spell": "daylight", "target": "hero"})
	var ended := CoreFixtures.events_of(_evs(res), "tile_effect_ended")
	assert_eq(ended.size(), 1)
	assert_eq(ended[0]["reason"], "dispelled")
	assert_true(e.can_see(e.get_combatant("hero"), e.get_combatant("gob")), "60 ft of daylight")


func test_light_cast_on_a_hostile_allows_a_save() -> void:
	var e := _fight(_caster(["light"]), {"gob": [_gob(), Vector2i(4, 3), [SURE]]}, Encounter.LIGHT_DARK)
	assert_false(e.can_see(e.get_combatant("hero"), e.get_combatant("gob")))
	var res := _cast(e, {"spell": "light", "target": "gob"})
	assert_false(CoreFixtures.events_of(_evs(res), "save").is_empty())
	assert_true(e.can_see(e.get_combatant("hero"), e.get_combatant("gob")), "DEX 1 fails: the goblin glows")


func test_set_light_replays_through_json() -> void:
	var e := _fight(_caster(["dancing_lights"]), {}, Encounter.LIGHT_DARK)
	_cast(e, {"spell": "dancing_lights", "target": "hero"})
	e.set_light(Encounter.LIGHT_BRIGHT)
	assert_eq(CoreFixtures.first_event(e.events_since(e.events.size() - 1), "light_changed")["light"], "bright")
	e.end_turn()
	var setup: Array[Dictionary] = []
	for d in e.setup_snapshot():
		setup.append(JSON.parse_string(JSON.stringify(d)))
	var entries: Array[Dictionary] = []
	for d in e.intent_log:
		entries.append(JSON.parse_string(JSON.stringify(d)))
	assert_eq(entries[0]["type"], "light")
	var m := WalkMap.new(12, 12, true)
	m.set_walkable(Vector2i(6, 6), false)
	var again := Encounter.replay(e.rng_seed, m, e.region, setup, entries, "t", content)
	assert_eq(JSON.stringify(again.events), JSON.stringify(e.events))
	assert_eq(again.intent_log.size(), e.intent_log.size())


func test_pass_without_trace_adds_ten_to_stealth() -> void:
	var e := _fight(_caster(["pass_without_trace"]))
	_cast(e, {"spell": "pass_without_trace"})
	var hero := e.get_combatant("hero")
	var check := e.ability_check(hero, Ability.Type.DEX, Skill.Type.STEALTH, -1, "test")
	var ev: Dictionary = CoreFixtures.events_of(e.events, "check").back()
	assert_eq(int(ev["total"]), int(ev["natural"]) + hero.sheet.check_modifier(Ability.Type.DEX, Skill.Type.STEALTH) + 10)
	assert_eq(check["total"], ev["total"])
	var s := _caster(["pass_without_trace"])
	var r := OutOfCombat.cast(s, "pass_without_trace", content, Rng.new(1))
	assert_true(r["ok"] == true, str(r["error"]))
	assert_eq(s.lingering[0]["modifiers"]["stealth_bonus"], 10)


func test_gentle_repose_keeps_the_dead_revivable() -> void:
	var s := _caster(["gentle_repose", "revivify"])
	var corpse := CoreFixtures.sheet("Corpse")
	corpse.current_hp = 0
	corpse.dead = true
	assert_false(OutOfCombat.cast(s, "revivify", content, Rng.new(1), [corpse], {"dead_minutes": 30.0})["ok"] == true)
	assert_true(OutOfCombat.cast(s, "gentle_repose", content, Rng.new(1), [corpse], {"ritual": true})["ok"] == true)
	var r := OutOfCombat.cast(s, "revivify", content, Rng.new(1), [corpse], {"dead_minutes": 30.0})
	assert_true(r["ok"] == true, str(r["error"]))
	assert_false(corpse.is_dead())


func test_heroes_feast_lingers_until_a_long_rest() -> void:
	var s := _caster(["heroes_feast"])
	var r := OutOfCombat.cast(s, "heroes_feast", content, Rng.new(1))
	assert_true(r["ok"] == true, str(r["error"]))
	assert_eq(s.lingering[0]["encounters_left"], -1)
	var e := _fight(s)
	var hero := e.get_combatant("hero")
	assert_true(hero.buff_list("immune_conditions").has("poisoned"))
	assert_eq(hero.sheet.max_hp, 91)
	Rest.long_rest(s)
	assert_true(s.lingering.is_empty())


func test_meld_into_stone_needs_a_wall() -> void:
	var e := _fight(_caster(["meld_into_stone"]))
	assert_true(str(e.submit(CoreFixtures.intent("cast", "hero", {"spell": "meld_into_stone"}))["error"]).contains("wall"))
	var m := WalkMap.new(12, 12, true)
	m.set_walkable(Vector2i(2, 3), false)
	e = _fight(_caster(["meld_into_stone"]), {}, Encounter.LIGHT_BRIGHT, m)
	var res := _cast(e, {"spell": "meld_into_stone"})
	assert_eq(CoreFixtures.first_event(_evs(res), "banished")["target"], "hero")


func test_goodberry_heals_from_a_pool_of_ten() -> void:
	var e := _fight(_caster(["goodberry"]))
	var hero := e.get_combatant("hero")
	hero.sheet.current_hp = 50
	_cast(e, {"spell": "goodberry"})
	assert_eq(hero.sheet.current_hp, 60)


func test_detect_thoughts_reveals_hidden_thinkers() -> void:
	var smart := _gob()
	smart.abilities.set_score(Ability.Type.INT, 10)
	var e := _fight(_caster(["detect_thoughts"]), {"gob": [smart, Vector2i(6, 3), [SURE]], "rat": [_gob(), Vector2i(5, 4), [SURE]]})
	e.get_combatant("gob").hidden = true
	e.get_combatant("rat").hidden = true
	var res := _cast(e, {"spell": "detect_thoughts"})
	var revealed := CoreFixtures.events_of(_evs(res), "revealed")
	assert_eq(revealed.size(), 1, "INT 1 is not a thinking mind")
	assert_eq([revealed[0]["actor"], revealed[0]["reason"]], ["gob", "detected"])


func test_no_effect_spells_say_why_and_cost_nothing() -> void:
	var s := _caster(["tongues"])
	var r := OutOfCombat.cast(s, "tongues", content, Rng.new(1))
	assert_true(r["ok"] == true)
	assert_eq(CoreFixtures.first_event(r["events"], "no_effect")["reason"], "no one in the delve to talk to yet")
	assert_eq(s.spell_slots[2], 3, "free unless the caster spends the slot")
	OutOfCombat.cast(s, "tongues", content, Rng.new(1), [], {"spend_slot": true})
	assert_eq(s.spell_slots[2], 2)
	var e := _fight(_caster(["tongues"]))
	var res := _cast(e, {"spell": "tongues"})
	assert_false(CoreFixtures.events_of(_evs(res), "no_effect").is_empty())


func test_senses_and_locked_chests_load() -> void:
	assert_eq(MonsterDefinition.sense_ft("blindsight 10 ft., darkvision 60 ft., passive perception 9", "darkvision"), 60)
	assert_eq(MonsterDefinition.sense_ft("blindsight 10 ft., darkvision 60 ft.", "blindsight"), 10)
	assert_eq(MonsterDefinition.sense_ft("passive perception 9", "truesight"), 0)
	var monsters: Dictionary = ContentLoader.load_monsters()
	assert_eq((monsters["goblin"] as MonsterDefinition).to_sheet().darkvision_ft, 60)
	var ancestries: Dictionary = ContentLoader.load_ancestries()
	assert_eq((ancestries["hill_dwarf"] as AncestryDefinition).darkvision_ft, 60)
	assert_eq((ancestries["human"] as AncestryDefinition).darkvision_ft, 0)
	var chest := ChestData.from_dict({"id": "c1", "position": [1, 2], "table": "t", "locked": true})
	assert_true(chest.locked)
	assert_eq(ChestData.from_dict(chest.to_dict()).locked, true)
	assert_false(ChestData.from_dict({"id": "c2"}).to_dict().has("locked"))

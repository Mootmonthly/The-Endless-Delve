extends TestCase
## Determinism: seed + setup_snapshot + intent_log rebuild identical events.

const SEED := 4242

var map: WalkMap
var region: Rect2i


func before_each() -> void:
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


func _fighter(char_name: String) -> CharacterSheet:
	var classes := ContentLoader.load_classes()
	var ancestries := ContentLoader.load_ancestries()
	var scores := AbilityScores.new()
	var values: Array[int] = [15, 13, 14, 8, 12, 10]
	scores.set_all(values)
	var skills: Array[int] = [Skill.Type.ATHLETICS, Skill.Type.PERCEPTION]
	var cls: ClassDefinition = classes["fighter"]
	var human: AncestryDefinition = ancestries["human"]
	return CharacterBuilder.create(char_name, cls, human, scores, skills)


## A full scripted fight: both sides are driven by MonsterBrain; a goblin
## joins mid-fight. Returns the finished encounter.
func _scripted_fight() -> Encounter:
	var monsters := ContentLoader.load_monsters()
	var goblin: MonsterDefinition = monsters["goblin"]
	var rat: MonsterDefinition = monsters["giant_rat"]
	var e := Encounter.new("fight", Rng.new(SEED), map, region)
	var a := Combatant.from_sheet("pc_a", _fighter("Ana"), 0)
	a.position = Vector2i(1, 1)
	var b := Combatant.from_sheet("pc_b", _fighter("Bo"), 0)
	b.position = Vector2i(1, 3)
	var setup_rng := Rng.new(7)
	var g1 := Combatant.from_monster("goblin_1", goblin, 1, setup_rng, true)
	g1.position = Vector2i(10, 2)
	var r1 := Combatant.from_monster("rat_1", rat, 1, setup_rng, true)
	r1.position = Vector2i(10, 6)
	for c: Combatant in [a, b, g1, r1]:
		assert_true(e.add_combatant(c))
	assert_true(e.start())
	var joined := false
	for _turn in range(200):
		if e.state != Encounter.State.ACTIVE:
			break
		if not joined and e.tracker.round_number >= 2:
			var g2 := Combatant.from_monster("goblin_2", goblin, 1, setup_rng, true)
			g2.position = Vector2i(12, 6)
			assert_true(e.add_combatant(g2))
			joined = true
		var actor := e.current_actor()
		for intent in MonsterBrain.decide(e, actor.id):
			if not e.submit(intent)["ok"]:
				break
	return e


func _to_json_dicts(data: Array) -> Array[Dictionary]:
	return DictUtil.to_dict_array(JSON.parse_string(JSON.stringify(data)))


func test_scripted_fight_finishes() -> void:
	var e := _scripted_fight()
	assert_eq(e.state, Encounter.State.ENDED)
	assert_true(e.replay_safe)
	assert_eq(e.rng_seed, SEED)
	assert_true(e.intent_log.size() > 5)
	var kinds: Array[String] = []
	for ev in e.events:
		kinds.append(str(ev["kind"]))
	assert_has(kinds, "attack")
	assert_has(kinds, "moved")
	assert_eq(kinds[kinds.size() - 1], "encounter_ended")


func test_replay_produces_identical_events() -> void:
	var e := _scripted_fight()
	var copy := Encounter.replay(e.rng_seed, map, region, e.setup_snapshot(), e.intent_log)
	assert_eq(copy.events.size(), e.events.size())
	assert_eq(copy.events, e.events)
	assert_eq(copy.state, e.state)
	assert_eq(copy.winning_team, e.winning_team)
	assert_eq(copy.intent_log, e.intent_log)


func test_replay_from_json_round_trip() -> void:
	var e := _scripted_fight()
	var setup := _to_json_dicts(e.setup_snapshot())
	var intents := _to_json_dicts(e.intent_log)
	var copy := Encounter.replay(e.rng_seed, map, region, setup, intents)
	var original_json := JSON.stringify(e.events)
	assert_eq(JSON.stringify(copy.events), original_json, "same events after a JSON round trip")
	for c in e.combatants():
		var other := copy.get_combatant(c.id)
		assert_eq(other.sheet.current_hp, c.sheet.current_hp, c.id)
		assert_eq(other.position, c.position, c.id)


func test_events_are_json_safe() -> void:
	var e := _scripted_fight()
	var back: Variant = JSON.parse_string(JSON.stringify(e.events))
	assert_eq(typeof(back), TYPE_ARRAY)
	for ev in e.events:
		for key: Variant in ev.keys():
			var t := typeof(ev[key])
			assert_true(t in [TYPE_STRING, TYPE_INT, TYPE_BOOL, TYPE_ARRAY], "%s.%s has type %d" % [ev["kind"], key, t])


func test_different_seed_differs() -> void:
	var e := _scripted_fight()
	var other := Encounter.replay(e.rng_seed + 1, map, region, e.setup_snapshot(), e.intent_log)
	assert_ne(JSON.stringify(other.events), JSON.stringify(e.events))

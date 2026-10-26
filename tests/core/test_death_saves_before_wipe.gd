extends TestCase
## "Death saves before wipe": a team stays in the fight while any member is
## conscious OR still dying, so a downed solo player keeps rolling death saves
## while the monsters act; the fight ends once the fallen die or are stable.

const CLAW := {"name": "Claw", "kind": "melee", "to_hit": 100, "damage": "1", "damage_type": "slashing"}

var map: WalkMap


func before_each() -> void:
	map = WalkMap.new(12, 12, true)


func _make(combatant_id: String, team: int, pos: Vector2i, hp: int = 10) -> Combatant:
	var s := CharacterSheet.new()
	s.name = combatant_id
	s.max_hp = hp
	s.current_hp = hp
	s.uses_death_saves = team == Combatant.TEAM_PLAYERS
	var c := Combatant.from_sheet(combatant_id, s, team)
	c.attacks = [CLAW.duplicate()]
	c.position = pos
	if team == Combatant.TEAM_MONSTERS:
		c.monster_id = "test_monster"
	return c


## Encounter in which `first_id` acts first. specs: [id, team, pos].
func _fight(specs: Array, first_id: String) -> Encounter:
	for s in range(1, 500):
		var e := Encounter.new("t", Rng.new(s), map, Rect2i(0, 0, 12, 12))
		for spec: Array in specs:
			var pos: Vector2i = spec[2]
			assert_true(e.add_combatant(_make(str(spec[0]), int(spec[1]), pos)))
		e.start()
		if e.current_actor() != null and e.current_actor().id == first_id:
			return e
	fail("no seed lets %s act first" % first_id)
	return null


func _end_turn(actor_id: String) -> Dictionary:
	return {"v": 1, "type": "end_turn", "actor": actor_id}


## Drops c to 0 hp without killing it (dying, death saves pending).
func _down(c: Combatant) -> void:
	c.sheet.take_damage(c.sheet.current_hp)
	assert_true(c.is_dying(), "%s is dying" % c.id)


func _events_of(e: Encounter, kind: String, actor_key: String = "", actor: String = "") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for ev in e.events:
		if str(ev["kind"]) == kind and (actor_key.is_empty() or str(ev.get(actor_key, "")) == actor):
			out.append(ev)
	return out


## Runs MonsterBrain turns for monster actors until the fight ends (bounded).
func _run_monsters(e: Encounter, max_turns: int = 200) -> void:
	for _i in range(max_turns):
		if e.state != Encounter.State.ACTIVE:
			return
		var actor := e.current_actor()
		if not actor.is_monster():
			e.submit(_end_turn(actor.id))
			continue
		for intent in MonsterBrain.decide(e, actor.id):
			if not e.submit(intent)["ok"]:
				break


func test_combatant_in_fight_predicates() -> void:
	var hero := _make("hero", 0, Vector2i(0, 0))
	assert_true(hero.is_in_fight())
	assert_false(hero.is_dying())
	_down(hero)
	assert_true(hero.is_in_fight(), "dying keeps the team in the fight")
	hero.sheet.stable = true
	assert_false(hero.is_dying())
	assert_false(hero.is_in_fight(), "stable does not")
	var m := _make("m", 1, Vector2i(1, 1))
	m.sheet.take_damage(10)
	assert_true(m.sheet.is_dead(), "monsters die at 0 hp")
	assert_false(m.is_in_fight())


func test_downed_solo_player_does_not_end_the_fight() -> void:
	var e := _fight([["m", 1, Vector2i(0, 0)], ["hero", 0, Vector2i(8, 8)]], "m")
	_down(e.get_combatant("hero"))
	assert_false(e.check_end(), "a dying player keeps the players in the fight")
	assert_eq(e.state, Encounter.State.ACTIVE)
	assert_eq(_events_of(e, "encounter_ended").size(), 0)


func test_downed_solo_player_rolls_death_saves_while_the_monster_closes_in() -> void:
	var e := _fight([["m", 1, Vector2i(0, 0)], ["hero", 0, Vector2i(8, 8)]], "m")
	var hero := e.get_combatant("hero")
	_down(hero)
	var plan := MonsterBrain.decide(e, "m")
	assert_eq(plan[0]["type"], "move", "the monster heads for the dying player")
	assert_eq((plan[0]["path"] as Array).size(), 6)
	for intent in plan.slice(0, plan.size() - 1):
		assert_true(e.submit(intent)["ok"])
	# The hero's first death save will be a plain success (no natural 20).
	e.rng = Rng.new(seed_where(func(r: Rng) -> bool:
		var n := D20.roll(r).natural
		return n >= 10 and n < 20))
	assert_true(e.submit(plan[plan.size() - 1])["ok"])
	var saves := _events_of(e, "death_save", "actor", "hero")
	assert_eq(saves.size(), 1, "the dying hero rolled at its turn start")
	assert_eq(int(saves[0]["successes"]), 1)
	assert_eq(e.state, Encounter.State.ACTIVE, "the fight goes on")
	assert_eq(e.current_actor().id, "m", "back to the monster")
	_run_monsters(e)
	assert_eq(e.state, Encounter.State.ENDED)
	var attacks := _events_of(e, "attack", "attacker", "m")
	assert_true(attacks.size() >= 1, "the monster reached and attacked the dying hero")
	assert_eq(str(attacks[0]["target"]), "hero")
	assert_eq(str(attacks[0]["advantage"]), "advantage", "advantage against an unconscious target")
	if attacks[0]["hit"] == true:
		assert_true(attacks[0]["critical"] == true, "a hit within 5 ft is a critical hit")
	assert_eq(e.winning_team, Combatant.TEAM_MONSTERS)
	assert_true(hero.sheet.is_dead() or hero.sheet.stable, "the fight ends only once the hero died or is stable")
	assert_eq(_events_of(e, "encounter_ended").size(), 1)


func test_natural_20_brings_the_solo_player_back_and_the_fight_continues() -> void:
	var e := _fight([["m", 1, Vector2i(0, 0)], ["hero", 0, Vector2i(1, 0)]], "m")
	var hero := e.get_combatant("hero")
	_down(hero)
	e.rng = Rng.new(seed_where(func(r: Rng) -> bool: return D20.roll(r).natural == 20))
	assert_true(e.submit(_end_turn("m"))["ok"], "the monster passes")
	var saves := _events_of(e, "death_save", "actor", "hero")
	assert_eq(saves.size(), 1)
	assert_eq(int(saves[0]["natural"]), 20)
	assert_true(saves[0]["regained"] == true)
	assert_eq(hero.sheet.current_hp, 1, "a natural 20 restores 1 hp")
	assert_eq(e.state, Encounter.State.ACTIVE)
	assert_eq(e.current_actor(), hero, "the hero acts this very turn")
	var res := e.submit({"v": 1, "type": "attack", "actor": "hero", "target": "m", "attack_index": 0})
	assert_true(res["ok"], "and may fight on")


func test_all_stable_means_the_monsters_win() -> void:
	# A wall keeps the monster away, so only the death saves matter.
	map = WalkMap.from_rows(["....#.......", "....#.......", "....#.......", "....#......."])
	var e := _fight([["m", 1, Vector2i(0, 0)], ["hero", 0, Vector2i(8, 1)]], "m")
	var hero := e.get_combatant("hero")
	_down(hero)
	hero.sheet.death_save_successes = 2
	e.rng = Rng.new(seed_where(func(r: Rng) -> bool:
		var n := D20.roll(r).natural
		return n >= 10 and n < 20))
	assert_eq(MonsterBrain.decide(e, "m").size(), 1, "unreachable: the monster just ends its turn")
	e.submit(_end_turn("m"))
	assert_true(hero.sheet.stable, "third success: stable")
	assert_eq(e.state, Encounter.State.ENDED, "nobody on the players' side is conscious or dying")
	assert_eq(e.winning_team, Combatant.TEAM_MONSTERS)
	var ended := _events_of(e, "encounter_ended")
	assert_eq(ended.size(), 1)
	assert_eq(int(ended[0]["winning_team"]), Combatant.TEAM_MONSTERS)


func test_party_of_two_stays_in_the_fight_while_one_is_dying() -> void:
	var e := _fight([["m", 1, Vector2i(5, 5)], ["a", 0, Vector2i(5, 4)], ["b", 0, Vector2i(0, 0)]], "m")
	var a := e.get_combatant("a")
	var b := e.get_combatant("b")
	_down(a)
	b.sheet.take_damage(100)
	assert_true(b.sheet.is_dead())
	assert_false(e.check_end(), "a is still dying")
	a.sheet.stable = true
	assert_true(e.check_end(), "one stable and one dead: wiped")
	assert_eq(e.winning_team, Combatant.TEAM_MONSTERS)


func test_party_wipe_when_everyone_dies() -> void:
	var e := _fight([["m", 1, Vector2i(5, 5)], ["a", 0, Vector2i(5, 4)], ["b", 0, Vector2i(5, 6)]], "m")
	for id: String in ["a", "b"]:
		e.get_combatant(id).sheet.take_damage(100)
	assert_true(e.check_end())
	assert_eq(e.winning_team, Combatant.TEAM_MONSTERS)

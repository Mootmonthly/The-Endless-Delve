extends TestCase
## Levels 1-5 features of the martial classes and the fighting styles:
## barbarian, fighter, monk, paladin, ranger, rogue.

const HIT := {"name": "Hit", "kind": "melee", "to_hit": 100, "damage": "4", "damage_type": "slashing", "ability": "STR"}
const RAPIER := {"name": "Rapier", "kind": "melee", "to_hit": 100, "damage": "1", "damage_type": "piercing", "properties": ["finesse"], "ability": "DEX"}
const ARROW := {"name": "Arrow", "kind": "ranged", "to_hit": 100, "damage": "10", "damage_type": "piercing", "range_tiles": [16, 64]}

var content: Dictionary


func before_each() -> void:
	content = CoreFixtures.content()


func _evs(res: Dictionary) -> Array:
	var evs: Array = res.get("events", [])
	return evs


func _feature(e: Encounter, feature: String, fields: Dictionary = {}) -> Dictionary:
	var f := {"feature": feature}
	f.merge(fields)
	return e.submit(CoreFixtures.intent("use_feature", "hero", f))


func _atk(e: Encounter, actor: String, target: String, index: int = 0, fields: Dictionary = {}) -> Dictionary:
	var f := {"target": target, "attack_index": index}
	f.merge(fields)
	return e.submit(CoreFixtures.intent("attack", actor, f))


func _duel(hero: CharacterSheet, attacks: Array[Dictionary] = [HIT], gob: CharacterSheet = null, gob_pos: Vector2i = Vector2i(4, 3), first: String = "hero", gob_attacks: Array = [HIT]) -> Encounter:
	var g := gob if gob != null else CoreFixtures.sheet("Gob", 200)
	var e := CoreFixtures.duel(hero, attacks, {"gob": [g, gob_pos, gob_attacks]}, content, first)
	assert_not_null(e)
	return e


func _to_turn(e: Encounter, id: String) -> void:
	for _i in range(10):
		if e.current_actor().id == id:
			return
		e.end_turn()


# --- fighting styles ---------------------------------------------------------------

func test_fighting_styles() -> void:
	var s := CoreFixtures.sheet("F", 20, [16, 14, 10, 10, 10, 10])
	s.add_item("shortbow")
	s.add_item("arrows", 10)
	s.add_item("longsword")
	s.add_item("greataxe")
	s.add_item("chain_mail")
	s.equip("shortbow", "main_hand", content)
	var plain_bow: int = s.attacks[0]["to_hit"]
	s.fighting_styles = ["archery"]
	s.rebuild_attacks(content)
	assert_eq(s.attacks[0]["to_hit"], plain_bow + 2, "archery")
	s.fighting_styles = ["dueling"]
	s.equip("longsword", "main_hand", content)
	assert_eq(s.attacks[0]["damage"], "1d8+5", "dueling: STR 3 + 2")
	s.add_item("shield")
	s.equip("shield", "off_hand", content)
	assert_eq(s.attacks[0]["damage"], "1d8+5", "a shield is not a weapon")
	s.unequip("off_hand", content)
	s.fighting_styles = ["great_weapon_fighting"]
	s.equip("greataxe", "main_hand", content)
	assert_eq(s.attacks[0]["reroll_max"], 2)
	assert_eq(s.attacks[0]["damage"], "1d12+3")
	assert_eq(s.armor_class(), 12)
	s.equip("chain_mail", "armor", content)
	assert_eq(s.armor_class(), 16)
	s.fighting_styles = ["defense"]
	assert_eq(s.armor_class(), 17, "defense: +1 in armor")


# --- barbarian -----------------------------------------------------------------

func test_rage_damage_table_reckless_attack_and_danger_sense() -> void:
	var s := CoreFixtures.sheet("Barb", 60, [], ["rage", "reckless_attack", "danger_sense", "fast_movement"])
	assert_eq(Encounter.rage_damage(s), 2)
	s.level = 9
	assert_eq(Encounter.rage_damage(s), 3)
	s.level = 16
	assert_eq(Encounter.rage_damage(s), 4)
	s.level = 5
	assert_eq(s.effective_speed(), 40, "fast movement")
	s.armor_base = 16
	s.armor_max_dex = 0
	assert_eq(s.effective_speed(), 30, "not in heavy armor")
	s.armor_base = 0
	s.armor_max_dex = -1
	var e := _duel(s)
	assert_true(str(_atk(e, "hero", "gob", 0, {"reckless": true, "bonus": true})["error"]).length() > 0)
	var res := _atk(e, "hero", "gob", 0, {"reckless": true})
	assert_true(res["ok"] == true, str(res["error"]))
	assert_eq(CoreFixtures.first_event(_evs(res), "attack")["advantage"], "advantage")
	_to_turn(e, "gob")
	res = _atk(e, "gob", "hero")
	assert_eq(CoreFixtures.first_event(_evs(res), "attack")["advantage"], "advantage", "attacks against a reckless barbarian")
	var hero := e.get_combatant("hero")
	var before := e.events.size()
	e._saving_throw("gob", hero, Ability.Type.DEX, 10)
	assert_eq(e.events_since(before)[0]["advantage"], "advantage", "danger sense")
	e._apply_condition(hero, "blinded", "gob", Conditions.duration("encounter"))
	before = e.events.size()
	e._saving_throw("gob", hero, Ability.Type.DEX, 10)
	assert_false(e.events_since(before)[0].has("advantage"), "not while blinded")


# --- fighter -------------------------------------------------------------------

func test_improved_critical() -> void:
	var gob := Combatant.from_sheet("gob", CoreFixtures.sheet("Gob", 50))
	var hero := Combatant.from_sheet("hero", CoreFixtures.sheet("Hero", 50))
	var seed_value := seed_where(func(rng: Rng) -> bool: return D20.roll(rng).natural == 19)
	var plain := AttackResolver.roll(hero, gob, {"to_hit": 0, "damage": "1d6"}, Rng.new(seed_value))
	assert_false(plain.critical)
	var champion := AttackResolver.roll(hero, gob, {"to_hit": 0, "damage": "1d6"}, Rng.new(seed_value), D20.RollMode.NORMAL, false, 0, [], false, 19)
	assert_true(champion.critical, "19 crits with Improved Critical")
	assert_true(champion.hit)


# --- monk ------------------------------------------------------------------------

func _monk(level: int = 5) -> CharacterSheet:
	var s := CoreFixtures.sheet("Monk", 40, [10, 16, 10, 10, 30, 10], ["martial_arts", "unarmored_defense_wis", "ki", "unarmored_movement",
		"deflect_missiles", "stunning_strike", "open_hand_technique", "extra_attack"])
	s.level = level
	s.restore_class_resources()
	return s


func test_monk_numbers() -> void:
	var s := _monk(5)
	assert_eq(s.class_resource("ki"), 5)
	assert_eq(s.martial_arts_die(), 6)
	assert_eq(s.unarmed_strike()["damage"], "1d6+3")
	assert_eq(s.effective_speed(), 40, "unarmored movement +10 ft")
	s.level = 11
	s.add_item("shortsword")
	s.equip("shortsword", "main_hand", content)
	assert_eq(s.attacks[0]["damage"], "1d8+3", "monk weapon uses the bigger martial arts die")
	s.level = 6
	assert_eq(s.effective_speed(), 45)


func test_flurry_of_blows_and_open_hand() -> void:
	var s := _monk()
	var gob := CoreFixtures.sheet("Gob", 200, [1, 1, 1, 10, 10, 10])
	var e := _duel(s, [], gob)
	var hero := e.get_combatant("hero")
	var unarmed := hero.attacks.size() - 1
	assert_true(str(_feature(e, "flurry_of_blows")["error"]).contains("Attack action"))
	assert_true(_atk(e, "hero", "gob", unarmed)["ok"] == true)
	var res := _feature(e, "flurry_of_blows")
	assert_true(res["ok"] == true, str(res["error"]))
	assert_eq(CoreFixtures.first_event(_evs(res), "feature_used")["remaining"], 4)
	assert_eq(hero.bonus_attacks_remaining, 2)
	res = _atk(e, "hero", "gob", unarmed, {"bonus": true, "technique": "prone"})
	assert_true(res["ok"] == true, str(res["error"]))
	assert_eq(CoreFixtures.first_event(_evs(res), "attack")["bonus_source"], "flurry_of_blows")
	if CoreFixtures.first_event(_evs(res), "attack")["hit"]:
		assert_true(e.get_combatant("gob").has_condition("prone"), "DEX 1 vs DC 8 + 3 + 10")
	res = _atk(e, "hero", "gob", unarmed, {"bonus": true, "technique": "push"})
	assert_true(res["ok"] == true, str(res["error"]))
	if CoreFixtures.first_event(_evs(res), "attack")["hit"]:
		assert_eq(CoreFixtures.first_event(_evs(res), "pushed")["to"], [7, 3])
	assert_eq(hero.bonus_attacks_remaining, 0)
	assert_false(_atk(e, "hero", "gob", unarmed, {"bonus": true})["ok"] == true, "two strikes only")
	assert_true(str(_atk(e, "hero", "gob", unarmed, {"technique": "prone"})["error"]).contains("Flurry"))


func test_patient_defense_step_of_the_wind() -> void:
	var e := _duel(_monk(), [], null, Vector2i(9, 9))
	var res := _feature(e, "patient_defense")
	assert_true(res["ok"] == true, str(res["error"]))
	assert_eq(CoreFixtures.kinds(_evs(res)), ["feature_used", "dodge"])
	assert_true(e.get_combatant("hero").dodging)
	var e2 := _duel(_monk(), [], null, Vector2i(9, 9))
	assert_true(str(_feature(e2, "step_of_the_wind")["error"]).contains("mode"))
	res = _feature(e2, "step_of_the_wind", {"mode": "dash"})
	assert_true(res["ok"] == true, str(res["error"]))
	assert_eq(e2.get_combatant("hero").movement_remaining, 16, "8 + 8 tiles")
	assert_false(e2.get_combatant("hero").action_used)


func test_stunning_strike() -> void:
	var gob := CoreFixtures.sheet("Gob", 200, [10, 10, 1, 10, 10, 10])
	var e := _duel(_monk(), [HIT], gob)
	var res := _atk(e, "hero", "gob", 0, {"stun": true})
	assert_true(res["ok"] == true, str(res["error"]))
	if CoreFixtures.first_event(_evs(res), "attack")["hit"]:
		assert_has(_evs(res), {"kind": "feature_used", "actor": "hero", "feature": "stunning_strike", "target": "gob", "remaining": 4})
		var applied := CoreFixtures.first_event(_evs(res), "condition_applied")
		assert_eq(applied["condition"], "stunned")
		assert_eq(applied["duration"], {"type": "until_source_next_turn"})
	var no_ki := _monk()
	no_ki.class_resources["ki"] = 0
	assert_true(str(_atk(_duel(no_ki), "hero", "gob", 0, {"stun": true})["error"]).contains("ki"))


func test_deflect_missiles() -> void:
	var e := _duel(_monk(), [HIT], null, Vector2i(9, 3), "gob", [ARROW])
	var res := _atk(e, "gob", "hero")
	if CoreFixtures.first_event(_evs(res), "attack")["hit"]:
		var reduced := CoreFixtures.first_event(_evs(res), "damage_reduced")
		assert_eq(reduced["feature"], "deflect_missiles")
		assert_eq(reduced["actor"], "hero")
		assert_true(int(reduced["amount"]) >= 1)
		assert_eq(CoreFixtures.first_event(_evs(res), "damage")["amount"], 10 - int(reduced["amount"]), "flat 10 damage, crit or not")
		assert_true(e.get_combatant("hero").reaction_used)


# --- paladin -----------------------------------------------------------------------

func _paladin() -> CharacterSheet:
	var s := CoreFixtures.sheet("Pal", 60, [16, 10, 10, 10, 10, 16], ["divine_smite", "channel_divinity", "sacred_weapon", "turn_the_unholy"])
	s.class_id = "paladin"
	s.level = 3
	s.casting_ability = Ability.Type.CHA
	s.spell_slots_max = [3]
	s.spell_slots = [3]
	s.restore_class_resources()
	return s


func test_divine_smite() -> void:
	var gob := CoreFixtures.sheet("Gob", 200)
	var e := _duel(_paladin(), [HIT], gob)
	assert_true(str(_atk(e, "hero", "gob", 0, {"smite": 3})["error"]).contains("slot"))
	var res := _atk(e, "hero", "gob", 0, {"smite": 1})
	assert_true(res["ok"] == true, str(res["error"]))
	var hero := e.get_combatant("hero")
	if CoreFixtures.first_event(_evs(res), "attack")["hit"]:
		var extra: Array = CoreFixtures.first_event(_evs(res), "damage")["extra"]
		assert_eq(extra[0]["source"], "divine_smite")
		assert_eq(extra[0]["type"], "radiant")
		assert_eq(hero.sheet.slots_left(1), 2)
		assert_has(_evs(res), {"kind": "feature_used", "actor": "hero", "feature": "divine_smite", "target": "gob", "remaining": 2})
	else:
		assert_eq(hero.sheet.slots_left(1), 3, "no slot spent on a miss")


func test_sacred_weapon_and_turn_the_unholy() -> void:
	var e := _duel(_paladin())
	var res := _feature(e, "sacred_weapon")
	assert_true(res["ok"] == true, str(res["error"]))
	assert_has(_evs(res), {"kind": "effect_applied", "source": "hero", "target": "hero", "effect": "sacred_weapon", "bonus": 3})
	var hero := e.get_combatant("hero")
	assert_eq(hero.sacred_weapon_bonus, 3)
	assert_eq(hero.sheet.class_resource("channel_divinity"), 0)
	assert_true(str(_feature(e, "turn_the_unholy")["error"]).contains("no uses"))
	for _i in range(10):
		_to_turn(e, "gob")
		_to_turn(e, "hero")
	assert_eq(hero.sacred_weapon_bonus, 0, "ten rounds")
	var make := func() -> Array:
		var p := CoreFixtures.combatant("hero", _paladin(), Combatant.TEAM_PLAYERS, Vector2i(3, 3), [HIT])
		var fiend := CoreFixtures.combatant("imp", CoreFixtures.sheet("Imp", 30, [10, 10, 10, 10, 1, 10]), Combatant.TEAM_MONSTERS, Vector2i(5, 3), [HIT])
		fiend.creature_type = "fiend"
		var beast := CoreFixtures.combatant("wolf", CoreFixtures.sheet("Wolf", 30, [10, 10, 10, 10, 1, 10]), Combatant.TEAM_MONSTERS, Vector2i(5, 4), [HIT])
		beast.creature_type = "beast"
		return [p, fiend, beast]
	var t := CoreFixtures.fight(make, "hero", content)
	res = t.submit(CoreFixtures.intent("use_feature", "hero", {"feature": "turn_the_unholy"}))
	assert_true(res["ok"] == true, str(res["error"]))
	assert_eq(CoreFixtures.events_of(_evs(res), "save").size(), 1, "only the fiend")
	var imp := t.get_combatant("imp")
	assert_true(imp.has_condition("frightened"))
	assert_true(imp.is_fleeing())
	Rest.short_rest(t.get_combatant("hero").sheet, 0, Rng.new(1))
	assert_eq(t.get_combatant("hero").sheet.class_resource("channel_divinity"), 1, "short rest")


# --- ranger / rogue ------------------------------------------------------------------

func test_colossus_slayer_once_per_turn_on_a_wounded_target() -> void:
	var s := CoreFixtures.sheet("Ranger", 40, [], ["hunters_prey", "colossus_slayer", "extra_attack"])
	var e := _duel(s)
	var res := _atk(e, "hero", "gob")
	var extra: Array = CoreFixtures.first_event(_evs(res), "damage").get("extra", [])
	assert_true(extra.is_empty(), "the target was unhurt")
	res = _atk(e, "hero", "gob")
	if CoreFixtures.first_event(_evs(res), "attack")["hit"]:
		extra = CoreFixtures.first_event(_evs(res), "damage")["extra"]
		assert_eq(extra[0]["source"], "colossus_slayer")
		assert_eq(e.get_combatant("hero").colossus_turn, e.turn_counter)


func test_cunning_action_fast_hands_uncanny_dodge_expertise() -> void:
	var s := CoreFixtures.sheet("Rogue", 40, [10, 16, 10, 10, 10, 10], ["cunning_action", "fast_hands", "uncanny_dodge", "sneak_attack"])
	s.add_item("potion_of_healing")
	s.proficient_skills = [Skill.Type.STEALTH]
	s.expertise_skills = [Skill.Type.STEALTH]
	assert_eq(s.skill_modifier(Skill.Type.STEALTH), 3 + 4, "expertise doubles proficiency")
	var e := _duel(s, [RAPIER], null, Vector2i(4, 3), "hero", [{"name": "Big", "kind": "melee", "to_hit": 100, "damage": "10", "damage_type": "slashing"}])
	assert_true(str(_feature(e, "cunning_action", {"mode": "hide"})["error"]).contains("not modelled"))
	var res := _feature(e, "cunning_action", {"mode": "disengage"})
	assert_true(res["ok"] == true, str(res["error"]))
	assert_eq(CoreFixtures.kinds(_evs(res)), ["feature_used", "disengage"])
	assert_true(str(e.submit(CoreFixtures.intent("use_item", "hero", {"item": "potion_of_healing", "bonus": true}))["error"]).contains("bonus action"))
	res = e.submit(CoreFixtures.intent("use_item", "hero", {"item": "potion_of_healing"}))
	assert_true(res["ok"] == true, str(res["error"]))
	var plain := CoreFixtures.sheet("P", 40)
	plain.add_item("potion_of_healing")
	assert_true(str(_duel(plain).submit(CoreFixtures.intent("use_item", "hero", {"item": "potion_of_healing", "bonus": true}))["error"]).contains("cannot use items"))
	var f := CoreFixtures.sheet("Thief", 40, [], ["fast_hands"])
	f.add_item("potion_of_healing")
	var e2 := _duel(f)
	res = e2.submit(CoreFixtures.intent("use_item", "hero", {"item": "potion_of_healing", "bonus": true}))
	assert_true(res["ok"] == true, str(res["error"]))
	assert_true(e2.get_combatant("hero").bonus_action_used)
	assert_false(e2.get_combatant("hero").action_used)
	_to_turn(e, "gob")
	res = _atk(e, "gob", "hero")
	if CoreFixtures.first_event(_evs(res), "attack")["hit"] and not CoreFixtures.first_event(_evs(res), "attack")["critical"]:
		assert_eq(CoreFixtures.first_event(_evs(res), "damage_reduced")["feature"], "uncanny_dodge")
		assert_eq(CoreFixtures.first_event(_evs(res), "damage")["amount"], 5)

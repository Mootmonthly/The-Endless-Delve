extends TestCase
## Level-1 class features and spell marks: unarmored defense, rage, martial
## arts, second wind, sneak attack, lay on hands, bardic inspiration, hex,
## guiding bolt, mage armor, ray of frost, vicious mockery; plus use_item.

const SURE_HIT := {"name": "Sure Hit", "kind": "melee", "to_hit": 100, "damage": "1", "damage_type": "slashing", "ability": "STR"}
const BIG_HIT := {"name": "Big Hit", "kind": "melee", "to_hit": 100, "damage": "10", "damage_type": "slashing"}
const FINESSE_HIT := {"name": "Rapier", "kind": "melee", "to_hit": 100, "damage": "1", "damage_type": "piercing", "properties": ["finesse"], "ability": "DEX"}
const PLAIN_HIT := {"name": "Club", "kind": "melee", "to_hit": 100, "damage": "1", "damage_type": "bludgeoning", "properties": [], "ability": "STR"}

var content: Dictionary


func before_each() -> void:
	content = CoreFixtures.content()


func _ok(res: Dictionary) -> bool:
	return res.get("ok", false) == true


func _evs(res: Dictionary) -> Array:
	var evs: Array = res.get("events", [])
	return evs


func _feature(actor: String, feature: String, extra: Dictionary = {}) -> Dictionary:
	var intent := {"v": 1, "type": "use_feature", "actor": actor, "feature": feature}
	intent.merge(extra)
	return intent


func _attack(actor: String, target: String, index: int = 0, bonus: bool = false) -> Dictionary:
	var intent := {"v": 1, "type": "attack", "actor": actor, "target": target, "attack_index": index}
	if bonus:
		intent["bonus"] = true
	return intent


func _cast(actor: String, spell: String, target: String, slot: int = 0) -> Dictionary:
	return {"v": 1, "type": "cast", "actor": actor, "spell": spell, "target": target, "slot_level": slot}


func _end(e: Encounter) -> void:
	e.end_turn()


## hero (with sheet) at (3, 3), an ally at (9, 1), a goblin at gob_pos.
func _fight(hero_sheet: CharacterSheet, hero_attacks: Array[Dictionary], gob_pos: Vector2i = Vector2i(4, 3), first: String = "hero", gob_attacks: Array[Dictionary] = [SURE_HIT]) -> Encounter:
	var make := func() -> Array:
		var copy := CharacterSheet.from_dict(hero_sheet.to_dict())
		var hero := CoreFixtures.combatant("hero", copy, Combatant.TEAM_PLAYERS, Vector2i(3, 3), hero_attacks)
		var ally := CoreFixtures.combatant("ally", CoreFixtures.sheet("Ally", 20), Combatant.TEAM_PLAYERS, Vector2i(9, 1), [SURE_HIT])
		var gob := CoreFixtures.combatant("gob", CoreFixtures.sheet("Gob", 100), Combatant.TEAM_MONSTERS, gob_pos, gob_attacks)
		return [hero, ally, gob]
	var e := CoreFixtures.fight(make, first, content)
	assert_not_null(e, "%s acts first" % first)
	return e


# --- armor class ----------------------------------------------------------------

func test_unarmored_defense_variants_and_mage_armor() -> void:
	var barb := CoreFixtures.sheet("B", 10, [10, 14, 16, 10, 10, 10], ["unarmored_defense_con"])
	assert_eq(barb.armor_class(), 15, "10 + DEX 2 + CON 3")
	barb.shield_bonus = 2
	assert_eq(barb.armor_class(), 17, "shield allowed")
	barb.armor_base = 14
	barb.armor_max_dex = 2
	assert_eq(barb.armor_class(), 18, "armor replaces unarmored defense")
	var monk := CoreFixtures.sheet("M", 10, [10, 16, 10, 10, 14, 10], ["unarmored_defense_wis"])
	assert_eq(monk.armor_class(), 15, "10 + DEX 3 + WIS 2")
	monk.shield_bonus = 2
	assert_eq(monk.armor_class(), 15, "no unarmored defense with a shield: 10 + 3 + 2")
	var wiz := CoreFixtures.sheet("W", 10, [10, 14, 10, 10, 10, 10])
	assert_eq(wiz.armor_class(), 12)
	wiz.active_buffs.append("mage_armor")
	assert_eq(wiz.armor_class(), 15, "13 + DEX 2")
	Rest.long_rest(wiz)
	assert_eq(wiz.armor_class(), 12, "mage armor ends on a long rest")


# --- rage -----------------------------------------------------------------------

func test_rage_adds_damage_and_resists_physical_damage() -> void:
	var s := CoreFixtures.sheet("Barb", 40, [], ["rage"])
	assert_eq(s.class_resource("rage"), 2)
	var e := _fight(s, [SURE_HIT], Vector2i(4, 3), "hero", [BIG_HIT])
	var res := e.submit(_feature("hero", "rage"))
	assert_true(_ok(res), str(res["error"]))
	assert_eq(CoreFixtures.kinds(_evs(res)), ["feature_used", "effect_applied"])
	assert_eq(CoreFixtures.first_event(_evs(res), "feature_used"), {"kind": "feature_used", "actor": "hero", "feature": "rage", "target": "hero", "remaining": 1})
	var hero := e.get_combatant("hero")
	assert_true(hero.raging)
	assert_true(hero.bonus_action_used)
	assert_true(str(e.submit(_feature("hero", "rage"))["error"]).contains("bonus action"))
	res = e.submit(_attack("hero", "gob"))
	var dmg := CoreFixtures.first_event(_evs(res), "damage")
	assert_eq(dmg["extra"], [{"source": "rage", "amount": 2, "type": "slashing"}])
	assert_eq(dmg["amount"], 3 if not CoreFixtures.first_event(_evs(res), "attack")["critical"] else 4)
	while e.current_actor().id != "gob":
		_end(e)
	res = e.submit(_attack("gob", "hero"))
	var taken := CoreFixtures.first_event(_evs(res), "damage")
	assert_eq(taken["amount"], 5, "10 slashing halved")


func test_rage_needs_uses_and_ends_with_the_encounter() -> void:
	var s := CoreFixtures.sheet("Barb", 40, [], ["rage"])
	s.class_resources["rage"] = 0
	var e := _fight(s, [SURE_HIT])
	assert_true(str(e.submit(_feature("hero", "rage"))["error"]).contains("no uses"))
	var plain := _fight(CoreFixtures.sheet("Plain"), [SURE_HIT])
	assert_true(str(plain.submit(_feature("hero", "rage"))["error"]).contains("does not have"))
	assert_true(str(plain.submit(_feature("hero", "fireball"))["error"]).contains("unknown feature"))
	var fresh := Combatant.from_sheet("again", s)
	assert_false(fresh.raging, "rage lives on the encounter's combatant only")


# --- martial arts -----------------------------------------------------------------

func test_martial_arts_unarmed_strike_and_bonus_attack() -> void:
	var s := CoreFixtures.sheet("Monk", 20, [10, 16, 10, 10, 14, 10], ["martial_arts"])
	var strike := s.unarmed_strike()
	assert_eq(strike["damage"], "1d4+3", "1d4 + DEX")
	assert_eq(strike["to_hit"], 5)
	assert_eq(strike["unarmed"], true)
	s.add_item("shortsword")
	s.equip("shortsword", "main_hand", content)
	assert_eq(s.attacks[0]["ability"], "DEX", "monk weapon uses DEX")
	assert_eq(s.attacks[0]["damage"], "1d6+3")
	var e := _fight(s, [])
	var hero := e.get_combatant("hero")
	var unarmed := hero.attacks.size() - 1
	assert_eq(hero.attacks[unarmed]["name"], "Unarmed Strike")
	assert_true(str(e.submit(_attack("hero", "gob", unarmed, true))["error"]).contains("Attack action"))
	assert_true(_ok(e.submit(_attack("hero", "gob", 0))))
	assert_true(str(e.submit(_attack("hero", "gob", 0, true))["error"]).contains("unarmed"))
	var res := e.submit(_attack("hero", "gob", unarmed, true))
	assert_true(_ok(res), str(res["error"]))
	assert_eq(CoreFixtures.first_event(_evs(res), "attack")["bonus"], true)
	assert_true(hero.bonus_action_used)
	assert_false(_ok(e.submit(_attack("hero", "gob", unarmed, true))), "one bonus attack")


func test_bonus_attack_needs_martial_arts() -> void:
	var e := _fight(CoreFixtures.sheet("Plain"), [SURE_HIT])
	assert_true(_ok(e.submit(_attack("hero", "gob", 0))))
	assert_true(str(e.submit(_attack("hero", "gob", 0, true))["error"]).contains("no bonus-action attack"))


# --- second wind -----------------------------------------------------------------

func test_second_wind_heals_once_per_short_rest() -> void:
	var s := CoreFixtures.sheet("Fighter", 30, [], ["second_wind"])
	s.current_hp = 5
	var e := _fight(s, [SURE_HIT])
	var res := e.submit(_feature("hero", "second_wind"))
	assert_true(_ok(res), str(res["error"]))
	assert_eq(CoreFixtures.kinds(_evs(res)), ["feature_used", "heal"])
	var heal := CoreFixtures.first_event(_evs(res), "heal")
	assert_in_range(heal["amount"], 2, 11, "1d10 + level 1")
	var hero := e.get_combatant("hero")
	assert_eq(hero.sheet.current_hp, 5 + DictUtil.to_int(heal["amount"]))
	assert_eq(hero.sheet.class_resource("second_wind"), 0)
	assert_true(hero.bonus_action_used)
	assert_false(hero.action_used)
	Rest.short_rest(hero.sheet, 0, Rng.new(1))
	assert_eq(hero.sheet.class_resource("second_wind"), 1)


# --- sneak attack ------------------------------------------------------------------

func test_sneak_attack_with_an_ally_next_to_the_target() -> void:
	var s := CoreFixtures.sheet("Rogue", 20, [], ["sneak_attack"])
	s.level = 3
	assert_eq(s.sneak_attack_dice(), "2d6")
	var e := _fight(s, [FINESSE_HIT])
	e.get_combatant("ally").position = Vector2i(5, 3)
	var res := e.submit(_attack("hero", "gob"))
	var dmg := CoreFixtures.first_event(_evs(res), "damage")
	var extra: Array = dmg["extra"]
	assert_eq(extra.size(), 1)
	assert_eq(extra[0]["source"], "sneak_attack")
	assert_in_range(extra[0]["amount"], 2, 24)
	assert_eq(e.get_combatant("hero").sneak_attack_turn, e.turn_counter)


func test_no_sneak_attack_without_advantage_ally_or_finesse() -> void:
	var s := CoreFixtures.sheet("Rogue", 20, [], ["sneak_attack"])
	var e := _fight(s, [FINESSE_HIT, PLAIN_HIT])
	var res := e.submit(_attack("hero", "gob"))
	assert_false(CoreFixtures.first_event(_evs(res), "damage").has("extra"), "no ally adjacent, no advantage")
	e = _fight(s, [FINESSE_HIT, PLAIN_HIT])
	e.get_combatant("ally").position = Vector2i(5, 3)
	res = e.submit(_attack("hero", "gob", 1))
	assert_false(CoreFixtures.first_event(_evs(res), "damage").has("extra"), "not a finesse weapon")
	e = _fight(s, [FINESSE_HIT])
	e.get_combatant("ally").position = Vector2i(5, 3)
	e.get_combatant("gob").dodging = true
	res = e.submit(_attack("hero", "gob"))
	if CoreFixtures.first_event(_evs(res), "attack")["hit"]:
		assert_false(CoreFixtures.first_event(_evs(res), "damage").has("extra"), "disadvantage cancels the ally rule")
	e = _fight(s, [FINESSE_HIT])
	e.get_combatant("ally").position = Vector2i(5, 3)
	e.get_combatant("hero").sneak_attack_turn = e.turn_counter
	res = e.submit(_attack("hero", "gob"))
	assert_false(CoreFixtures.first_event(_evs(res), "damage").has("extra"), "once per turn")


func test_sneak_attack_with_advantage_against_a_downed_target() -> void:
	var s := CoreFixtures.sheet("Rogue", 20, [], ["sneak_attack"])
	var make := func() -> Array:
		var rogue := CoreFixtures.combatant("rogue", CharacterSheet.from_dict(s.to_dict()), Combatant.TEAM_MONSTERS, Vector2i(3, 3), [FINESSE_HIT])
		var hero := CoreFixtures.combatant("hero", CoreFixtures.sheet("Hero", 20), Combatant.TEAM_PLAYERS, Vector2i(4, 3))
		var other := CoreFixtures.combatant("other", CoreFixtures.sheet("Other", 20), Combatant.TEAM_PLAYERS, Vector2i(9, 9))
		return [rogue, hero, other]
	var e := CoreFixtures.fight(make, "rogue", content)
	e.get_combatant("hero").sheet.take_damage(20)
	var res := e.submit(_attack("rogue", "hero"))
	var atk := CoreFixtures.first_event(_evs(res), "attack")
	assert_eq(atk["advantage"], "advantage")
	if atk["hit"]:
		assert_eq(CoreFixtures.first_event(_evs(res), "damage")["extra"][0]["source"], "sneak_attack")


# --- lay on hands -------------------------------------------------------------------

func test_lay_on_hands_heals_from_a_pool_and_revives() -> void:
	var s := CoreFixtures.sheet("Paladin", 20, [], ["lay_on_hands"])
	assert_eq(s.class_resource("lay_on_hands"), 5)
	var e := _fight(s, [SURE_HIT])
	var ally := e.get_combatant("ally")
	assert_true(str(e.submit(_feature("hero", "lay_on_hands", {"target": "ally", "amount": 3}))["error"]).contains("reach"))
	ally.position = Vector2i(2, 3)
	ally.sheet.take_damage(20)
	assert_true(str(e.submit(_feature("hero", "lay_on_hands", {"target": "ally", "amount": 6}))["error"]).contains("pool"))
	assert_true(str(e.submit(_feature("hero", "lay_on_hands", {"target": "ally"}))["error"]).contains("amount"))
	assert_true(str(e.submit(_feature("hero", "lay_on_hands", {"target": "gob", "amount": 1}))["error"]).contains("not an ally"))
	var res := e.submit(_feature("hero", "lay_on_hands", {"target": "ally", "amount": 3}))
	assert_true(_ok(res), str(res["error"]))
	assert_eq(CoreFixtures.first_event(_evs(res), "feature_used")["remaining"], 2)
	var heal := CoreFixtures.first_event(_evs(res), "heal")
	assert_eq(heal["amount"], 3)
	assert_eq(heal["revived"], true)
	assert_true(ally.is_conscious())
	assert_true(e.get_combatant("hero").action_used, "lay on hands is an action")
	s.level = 3
	assert_eq(s.resource_max("lay_on_hands"), 15)


# --- bardic inspiration ----------------------------------------------------------------

func test_bardic_inspiration_adds_a_die_to_the_next_attack() -> void:
	var s := CoreFixtures.sheet("Bard", 20, [10, 10, 10, 10, 10, 16], ["bardic_inspiration"])
	assert_eq(s.class_resource("bardic_inspiration"), 3, "CHA modifier uses")
	var e := _fight(s, [SURE_HIT])
	assert_true(str(e.submit(_feature("hero", "bardic_inspiration", {"target": "hero"}))["error"]).contains("another creature"))
	assert_true(str(e.submit(_feature("hero", "bardic_inspiration", {"target": "gob"}))["error"]).contains("not an ally"))
	var res := e.submit(_feature("hero", "bardic_inspiration", {"target": "ally"}))
	assert_true(_ok(res), str(res["error"]))
	var applied := CoreFixtures.first_event(_evs(res), "effect_applied")
	assert_eq(applied["effect"], "bardic_inspiration")
	assert_eq(applied["die"], 6)
	var ally := e.get_combatant("ally")
	assert_eq(ally.inspiration_die, 6)
	assert_eq(e.get_combatant("hero").sheet.class_resource("bardic_inspiration"), 2)
	while e.current_actor().id != "ally":
		_end(e)
	ally.position = Vector2i(5, 3)
	res = e.submit(_attack("ally", "gob"))
	assert_eq(CoreFixtures.kinds(_evs(res)).slice(0, 2), ["inspiration_used", "attack"])
	var used := CoreFixtures.first_event(_evs(res), "inspiration_used")
	assert_eq(used["actor"], "ally")
	assert_eq(used["source"], "hero")
	assert_in_range(used["roll"], 1, 6)
	var atk := CoreFixtures.first_event(_evs(res), "attack")
	assert_eq(DictUtil.to_int(atk["total"]), DictUtil.to_int(atk["natural"]) + 100 + DictUtil.to_int(used["roll"]))
	assert_eq(ally.inspiration_die, 0, "used up")


# --- spells with marks ----------------------------------------------------------------

func test_hex_adds_necrotic_damage_to_the_casters_hits() -> void:
	var s := CoreFixtures.caster("Lock", Ability.Type.CHA, ["hex"])
	var e := _fight(s, [SURE_HIT])
	var res := e.submit(_cast("hero", "hex", "gob", 1))
	assert_true(_ok(res), str(res["error"]))
	assert_eq(CoreFixtures.first_event(_evs(res), "effect_applied"), {"kind": "effect_applied", "source": "hero", "target": "gob", "effect": "hex"})
	assert_true(e.get_combatant("hero").bonus_action_used)
	res = e.submit(_attack("hero", "gob"))
	var dmg := CoreFixtures.first_event(_evs(res), "damage")
	assert_eq(dmg["extra"][0]["source"], "hex")
	assert_eq(dmg["extra"][0]["type"], "necrotic")
	assert_in_range(dmg["extra"][0]["amount"], 1, 12)
	while e.current_actor().id != "ally":
		_end(e)
	e.get_combatant("ally").position = Vector2i(5, 3)
	res = e.submit(_attack("ally", "gob"))
	assert_false(CoreFixtures.first_event(_evs(res), "damage").has("extra"), "only the caster's hits")


func test_guiding_bolt_gives_the_next_attack_advantage() -> void:
	var s := CoreFixtures.caster("Cleric", Ability.Type.WIS, ["guiding_bolt"])
	var e: Encounter = null
	for _try in range(40):
		e = _fight(s, [SURE_HIT], Vector2i(8, 3))
		e.rng = Rng.new(1000 + _try)
		var res := e.submit(_cast("hero", "guiding_bolt", "gob", 1))
		if CoreFixtures.first_event(_evs(res), "attack")["hit"]:
			assert_eq(CoreFixtures.first_event(_evs(res), "effect_applied")["effect"], "guiding_bolt_mark")
			assert_in_range(CoreFixtures.first_event(_evs(res), "damage")["amount"], 4, 48)
			break
		e = null
	assert_not_null(e, "some seed hits")
	var gob := e.get_combatant("gob")
	assert_eq(gob.guided_by, "hero")
	while e.current_actor().id != "ally":
		_end(e)
	e.get_combatant("ally").position = Vector2i(7, 3)
	var res2 := e.submit(_attack("ally", "gob"))
	assert_eq(CoreFixtures.first_event(_evs(res2), "attack")["advantage"], "advantage")
	assert_eq(gob.guided_by, "", "the mark is spent")


func test_guiding_bolt_mark_fades_after_the_casters_next_turn() -> void:
	var s := CoreFixtures.caster("Cleric", Ability.Type.WIS, ["guiding_bolt"])
	var e := _fight(s, [SURE_HIT], Vector2i(8, 3))
	var gob := e.get_combatant("gob")
	gob.guided_by = "hero"
	gob.guided_turns_left = 2
	_end(e)
	assert_eq(gob.guided_by, "hero", "still marked after the casting turn")
	while e.current_actor().id != "hero":
		_end(e)
	var res := e.submit({"v": 1, "type": "end_turn", "actor": "hero"})
	assert_eq(gob.guided_by, "")
	assert_has(CoreFixtures.kinds(_evs(res)), "effect_ended")


func test_mage_armor_cast_sets_ac() -> void:
	var s := CoreFixtures.caster("Wiz", Ability.Type.INT, ["mage_armor"])
	s.abilities.set_score(Ability.Type.DEX, 14)
	var e := _fight(s, [SURE_HIT])
	var res := e.submit(_cast("hero", "mage_armor", "hero", 1))
	assert_true(_ok(res), str(res["error"]))
	var applied := CoreFixtures.first_event(_evs(res), "effect_applied")
	assert_eq(applied["effect"], "mage_armor")
	assert_eq(applied["ac"], 15)
	assert_eq(e.get_combatant("hero").sheet.armor_class(), 15)


func test_ray_of_frost_slows_the_target_next_turn() -> void:
	var s := CoreFixtures.caster("Wiz", Ability.Type.INT, ["ray_of_frost"])
	var e: Encounter = null
	for _try in range(40):
		e = _fight(s, [SURE_HIT], Vector2i(8, 3))
		e.rng = Rng.new(2000 + _try)
		var res := e.submit(_cast("hero", "ray_of_frost", "gob"))
		if CoreFixtures.first_event(_evs(res), "attack")["hit"]:
			assert_eq(CoreFixtures.first_event(_evs(res), "effect_applied")["effect"], "slow")
			break
		e = null
	assert_not_null(e)
	var gob := e.get_combatant("gob")
	assert_eq(gob.slowed_tiles, 2)
	while e.current_actor().id != "gob":
		_end(e)
	assert_eq(gob.movement_remaining, gob.speed_tiles() - 2)
	assert_eq(gob.slowed_tiles, 0)


func test_vicious_mockery_gives_disadvantage_on_the_next_attack() -> void:
	var s := CoreFixtures.caster("Bard", Ability.Type.CHA, ["vicious_mockery"])
	var e: Encounter = null
	for _try in range(60):
		e = _fight(s, [SURE_HIT], Vector2i(4, 3))
		e.rng = Rng.new(3000 + _try)
		var res := e.submit(_cast("hero", "vicious_mockery", "gob"))
		if not CoreFixtures.first_event(_evs(res), "save")["success"]:
			assert_eq(CoreFixtures.first_event(_evs(res), "effect_applied")["effect"], "mockery")
			assert_in_range(CoreFixtures.first_event(_evs(res), "damage")["amount"], 1, 4)
			break
		e = null
	assert_not_null(e, "some seed fails the save")
	var gob := e.get_combatant("gob")
	assert_true(gob.mocked)
	while e.current_actor().id != "gob":
		_end(e)
	var res2 := e.submit(_attack("gob", "hero"))
	assert_eq(CoreFixtures.first_event(_evs(res2), "attack")["advantage"], "disadvantage")
	assert_false(gob.mocked)


func test_mockery_wears_off_at_the_end_of_the_targets_turn() -> void:
	var e := _fight(CoreFixtures.sheet("Hero"), [SURE_HIT])
	var gob := e.get_combatant("gob")
	gob.mocked = true
	while e.current_actor().id != "gob":
		_end(e)
	var res := e.submit({"v": 1, "type": "end_turn", "actor": "gob"})
	assert_false(gob.mocked)
	assert_eq(CoreFixtures.first_event(_evs(res), "effect_ended"), {"kind": "effect_ended", "target": "gob", "effect": "mockery"})


func test_shocking_grasp_is_a_melee_spell_that_stops_reactions() -> void:
	var s := CoreFixtures.caster("Wiz", Ability.Type.INT, ["shocking_grasp"])
	var e: Encounter = null
	for _try in range(40):
		e = _fight(s, [SURE_HIT])
		e.rng = Rng.new(4000 + _try)
		var res := e.submit(_cast("hero", "shocking_grasp", "gob"))
		assert_eq(CoreFixtures.first_event(_evs(res), "attack")["advantage"], "normal", "melee spell: no adjacency disadvantage")
		if CoreFixtures.first_event(_evs(res), "attack")["hit"]:
			break
		e = null
	assert_not_null(e)
	assert_true(e.get_combatant("gob").reaction_used)


# --- items ---------------------------------------------------------------------------------

func test_potion_heals_and_is_used_up() -> void:
	var s := CoreFixtures.sheet("Hero", 30)
	s.current_hp = 4
	s.add_item("potion_of_healing", 2)
	var e := _fight(s, [SURE_HIT])
	var res := e.submit({"v": 1, "type": "use_item", "actor": "hero", "item": "potion_of_healing"})
	assert_true(_ok(res), str(res["error"]))
	assert_eq(CoreFixtures.kinds(_evs(res)), ["item_used", "heal"])
	assert_eq(CoreFixtures.first_event(_evs(res), "item_used"), {"kind": "item_used", "actor": "hero", "item": "potion_of_healing", "target": "hero"})
	var heal := CoreFixtures.first_event(_evs(res), "heal")
	assert_in_range(heal["amount"], 4, 10)
	assert_eq(heal["source"], "hero")
	var hero := e.get_combatant("hero")
	assert_eq(hero.sheet.count_item("potion_of_healing"), 1)
	assert_true(hero.action_used)
	assert_true(str(e.submit({"v": 1, "type": "use_item", "actor": "hero", "item": "potion_of_healing"})["error"]).contains("action"))


func test_temp_hp_item_and_item_validation() -> void:
	var s := CoreFixtures.sheet("Hero", 30)
	s.add_item("elixir")
	s.add_item("salve")
	s.add_item("rations")
	s.add_item("potion_of_healing")
	var e := _fight(s, [SURE_HIT])
	var use := func(item: String, extra: Dictionary = {}) -> Dictionary:
		var intent := {"v": 1, "type": "use_item", "actor": "hero", "item": item}
		intent.merge(extra)
		return e.submit(intent)
	assert_true(str(use.call("potion_of_healing", {"target": "ally"})["error"]).contains("yourself"))
	assert_true(str(use.call("antidote")["error"]).contains("does not carry"))
	assert_true(str(use.call("rations")["error"]).contains("cannot be used"))
	assert_true(str(use.call("salve")["error"]).contains("no effect"))
	assert_true(str(use.call("phoenix_down")["error"]).contains("unknown item"))
	var res: Dictionary = use.call("elixir")
	assert_true(_ok(res), str(res["error"]))
	assert_eq(CoreFixtures.first_event(_evs(res), "temp_hp"), {"kind": "temp_hp", "source": "hero", "target": "hero", "amount": 5, "temp_hp_after": 5})
	var hero := e.get_combatant("hero")
	assert_true(hero.bonus_action_used, "the elixir is a bonus action")
	assert_false(hero.action_used)
	var last: Dictionary = use.call("potion_of_healing")
	assert_true(_ok(last), "action still free")

extends TestCase
## SpellDefinition parsing, spell slots, DC / attack bonus, and the cast intent
## for each effect type (spell attack, auto hit, save, heal, buff), including
## reviving a dying ally.

const SURE_HIT := {"name": "Sure Hit", "kind": "melee", "to_hit": 100, "damage": "1", "damage_type": "slashing"}

var content: Dictionary


func before_each() -> void:
	content = CoreFixtures.content()


func _spell(spell_id: String) -> SpellDefinition:
	var s: SpellDefinition = content["spells"][spell_id]
	return s


func _cast(actor: String, spell: String, target: String, slot: int = 0) -> Dictionary:
	return {"v": 1, "type": "cast", "actor": actor, "spell": spell, "target": target, "slot_level": slot}


func _ok(res: Dictionary) -> bool:
	return res.get("ok", false) == true


func _evs(res: Dictionary) -> Array:
	var evs: Array = res.get("events", [])
	return evs


## Wizard (INT 16) at (2, 2) against a goblin with hp at `gob_pos`.
func _wizard_fight(gob_pos: Vector2i = Vector2i(7, 2), gob_hp: int = 100, prepared: Array[String] = ["fire_bolt", "ray_of_frost", "magic_missile", "mage_armor", "burning_hands", "thunder_save", "scorching_ray", "acid_arrow", "shocking_grasp"]) -> Encounter:
	var make := func() -> Array:
		var wiz := CoreFixtures.combatant("wiz", CoreFixtures.caster("Wiz", Ability.Type.INT, prepared), Combatant.TEAM_PLAYERS, Vector2i(2, 2))
		var gob := CoreFixtures.combatant("gob", CoreFixtures.sheet("Gob", gob_hp), Combatant.TEAM_MONSTERS, gob_pos, [SURE_HIT])
		return [wiz, gob]
	var e := CoreFixtures.fight(make, "wiz", content)
	assert_not_null(e, "wizard acts first")
	return e


func test_spell_definitions_parse_effects_and_riders() -> void:
	var fb := _spell("fire_bolt")
	assert_eq(fb.effect_type, "spell_attack")
	assert_true(fb.is_cantrip())
	assert_eq(fb.range_tiles(), 24)
	assert_eq(fb.damage_for_level(1), "1d10")
	assert_eq(fb.damage_for_level(5), "2d10")
	assert_eq(fb.damage_for_level(12), "3d10")
	assert_eq(_spell("ray_of_frost").rider, "slow")
	assert_eq(_spell("ray_of_frost").slow_tiles, 2)
	assert_eq(_spell("vicious_mockery").rider, "mockery")
	assert_eq(_spell("guiding_bolt").rider, "guiding_bolt_mark")
	assert_eq(_spell("guiding_bolt").per_slot_dice, "1d6")
	assert_eq(_spell("shocking_grasp").rider, "no_reactions")
	assert_true(_spell("shocking_grasp").melee)
	var hex := _spell("hex")
	assert_eq(hex.effect_type, "mark", "a hex buff is a mark on a hostile")
	assert_eq(hex.damage, "1d6")
	assert_eq(hex.damage_type, "necrotic")
	assert_true(hex.is_harmful())
	assert_true(hex.uses_bonus_action())
	assert_eq(_spell("magic_missile").per_slot_darts, 1)
	assert_eq(_spell("sacred_flame").save_ability, Ability.Type.DEX)
	assert_eq(_spell("cure_wounds").range_tiles(), 1, "touch")
	assert_true(_spell("cure_wounds").add_casting_mod)
	assert_false(_spell("cure_wounds").is_harmful())
	assert_false(_spell("burning_hands").is_supported())
	assert_eq(_spell("scorching_ray").rays_for(3, 2), 3)
	assert_eq(_spell("scorching_ray").rays_for(3, 3), 4)
	assert_true(_spell("acid_arrow").half_on_miss)
	var blast := CoreFixtures.spell({"id": "eb", "display_name": "EB", "level": 0, "effect": {"type": "spell_attack", "damage": "1d10", "damage_type": "force", "beams": {"1": 1, "5": 2}}})
	assert_eq(blast.rays_for(1, 0), 1)
	assert_eq(blast.rays_for(5, 0), 2)


func test_invalid_spells_are_rejected() -> void:
	assert_null(CoreFixtures.spell({"id": "x", "display_name": "X", "level": 10, "effect": {"type": "heal", "dice": "1d4"}}), "level 10")
	assert_null(CoreFixtures.spell({"id": "x", "display_name": "X", "level": 1, "effect": {"type": "teleport"}}), "unknown type")
	assert_null(CoreFixtures.spell({"id": "x", "display_name": "X", "level": 1, "effect": {"type": "save", "save": "LUCK", "damage": "1d6"}}), "bad save")
	assert_null(CoreFixtures.spell({"id": "x", "display_name": "X", "level": 1, "effect": {"type": "spell_attack", "damage": "lots"}}), "bad damage")
	var reaction := CoreFixtures.spell({"id": "x", "display_name": "X", "level": 1, "casting_time": "reaction", "effect": {"type": "heal", "dice": "1d4"}})
	assert_not_null(reaction, "reaction spells load as data")
	assert_false(reaction.is_combat_castable(), "but cannot be cast in combat")
	assert_null(CoreFixtures.spell({"id": "x", "display_name": "X", "level": 1, "casting_time": "", "effect": {"type": "heal", "dice": "1d4"}}), "empty casting time")
	assert_null(SpellDefinition.from_dict({"id": "x", "display_name": "X", "level": 1}), "no effect")


func test_spell_attack_bonus_and_save_dc() -> void:
	var s := CoreFixtures.caster("W", Ability.Type.INT, [])
	assert_eq(s.casting_modifier(), 3)
	assert_eq(s.spell_attack_bonus(), 5, "proficiency 2 + INT 3")
	assert_eq(s.spell_save_dc(), 13, "8 + 2 + 3")
	s.level = 5
	assert_eq(s.spell_attack_bonus(), 6)
	assert_eq(s.spell_save_dc(), 14)
	var none := CharacterSheet.new()
	assert_false(none.is_spellcaster())
	assert_eq(none.spell_save_dc(), 10, "no casting ability: 8 + proficiency")


func test_slot_helpers() -> void:
	var s := CoreFixtures.caster("W", Ability.Type.INT, [])
	s.spell_slots_max = [2, 0, 1]
	s.spell_slots = [0, 0, 1]
	assert_eq(s.highest_slot_level(), 3)
	assert_eq(s.lowest_available_slot(1), 3)
	assert_eq(s.slots_left(3), 1)
	assert_eq(s.slots_left(4), 0)
	assert_true(s.use_spell_slot(3))
	assert_false(s.use_spell_slot(3))
	assert_eq(s.lowest_available_slot(1), 0)
	s.restore_spell_slots()
	assert_eq(s.spell_slots, [2, 0, 1])


func test_cantrip_spell_attack_emits_cast_attack_and_damage() -> void:
	var e := _wizard_fight()
	var res := e.submit(_cast("wiz", "fire_bolt", "gob"))
	assert_true(_ok(res), str(res["error"]))
	var kinds := CoreFixtures.kinds(_evs(res))
	assert_eq(kinds[0], "cast")
	assert_eq(CoreFixtures.first_event(_evs(res), "cast"), {"kind": "cast", "actor": "wiz", "spell": "fire_bolt", "target": "gob", "slot_level": 0})
	var atk := CoreFixtures.first_event(_evs(res), "attack")
	assert_eq(atk["attack_kind"], "spell")
	assert_eq(atk["spell"], "fire_bolt")
	assert_eq(atk["attack_name"], "Fire Bolt")
	assert_eq(DictUtil.to_int(atk["total"]) - DictUtil.to_int(atk["natural"]), 5, "spell attack bonus")
	assert_eq(atk["advantage"], "normal")
	var dmg := CoreFixtures.first_event(_evs(res), "damage")
	if atk["hit"]:
		assert_eq(dmg["type"], "fire")
		assert_eq(dmg["spell"], "fire_bolt")
		assert_in_range(dmg["amount"], 1, 20)
	else:
		assert_eq(dmg, {})
	assert_eq(e.get_combatant("wiz").sheet.spell_slots, [2, 2], "cantrips use no slot")
	assert_true(e.get_combatant("wiz").action_used)
	assert_false(_ok(e.submit(_cast("wiz", "fire_bolt", "gob"))), "action already used")


func test_cast_validation() -> void:
	var e := _wizard_fight(Vector2i(8, 6), 100, ["fire_bolt", "magic_missile", "burning_hands", "shocking_grasp", "mage_armor"])
	var wiz := e.get_combatant("wiz")
	assert_true(str(e.submit(_cast("wiz", "cure_wounds", "gob"))["error"]).contains("not prepared"))
	assert_true(str(e.submit(_cast("wiz", "wish", "gob"))["error"]).contains("unknown spell"))
	assert_true(str(e.submit(_cast("wiz", "burning_hands", "wiz", 1))["error"]).contains("cannot be cast"))
	assert_true(str(e.submit(_cast("wiz", "shocking_grasp", "gob"))["error"]).contains("out of range"))
	assert_true(str(e.submit(_cast("wiz", "fire_bolt", "gob", 1))["error"]).contains("cantrips"))
	assert_true(str(e.submit(_cast("wiz", "fire_bolt", "wiz"))["error"]).contains("same team"))
	assert_true(str(e.submit(_cast("wiz", "mage_armor", "gob", 1))["error"]).contains("not an ally"))
	assert_true(str(e.submit(_cast("wiz", "fire_bolt", "nobody"))["error"]).contains("unknown target"))
	wiz.position = Vector2i(4, 6)
	assert_true(str(e.submit(_cast("wiz", "fire_bolt", "gob"))["error"]).contains("line of sight"), "wall at (6, 6)")
	wiz.position = Vector2i(2, 2)
	wiz.sheet.spell_slots = [0, 0]
	assert_true(str(e.submit(_cast("wiz", "magic_missile", "gob"))["error"]).contains("no spell slots"))
	wiz.sheet.spell_slots = [0, 1]
	assert_true(str(e.submit(_cast("wiz", "magic_missile", "gob", 1))["error"]).contains("no level 1"))
	assert_eq(e.intent_log.size(), 0, "rejected casts are not logged")
	var res := e.submit(_cast("wiz", "magic_missile", "gob"))
	assert_true(_ok(res), "slot 0 = lowest available (level 2)")
	assert_eq(CoreFixtures.first_event(_evs(res), "cast")["slot_level"], 2)
	assert_eq(wiz.sheet.spell_slots, [0, 0])


func test_mage_armor_rejects_an_armored_target() -> void:
	var e := _wizard_fight()
	var wiz := e.get_combatant("wiz")
	wiz.sheet.armor_base = 11
	assert_true(str(e.submit(_cast("wiz", "mage_armor", "wiz", 1))["error"]).contains("wearing armor"))


func test_magic_missile_hits_automatically_and_upcasts() -> void:
	var e := _wizard_fight()
	var res := e.submit(_cast("wiz", "magic_missile", "gob", 1))
	assert_true(_ok(res), str(res["error"]))
	assert_eq(CoreFixtures.kinds(_evs(res)), ["cast", "damage"], "no attack roll")
	var dmg := CoreFixtures.first_event(_evs(res), "damage")
	assert_eq(dmg["darts"], 3)
	assert_in_range(dmg["amount"], 6, 15)
	assert_eq(dmg["type"], "force")
	assert_eq(e.get_combatant("gob").sheet.current_hp, 100 - DictUtil.to_int(dmg["amount"]))
	assert_eq(e.get_combatant("wiz").sheet.spell_slots, [1, 2])
	e.end_turn()
	e.submit({"v": 1, "type": "end_turn", "actor": "gob"})
	res = e.submit(_cast("wiz", "magic_missile", "gob", 2))
	assert_eq(CoreFixtures.first_event(_evs(res), "damage")["darts"], 4, "one more dart per slot level")
	assert_eq(e.get_combatant("wiz").sheet.spell_slots, [1, 1])


func test_scorching_ray_rolls_one_attack_per_ray() -> void:
	var e := _wizard_fight()
	var res := e.submit(_cast("wiz", "scorching_ray", "gob", 2))
	assert_true(_ok(res), str(res["error"]))
	assert_eq(CoreFixtures.events_of(_evs(res), "attack").size(), 3)


func test_acid_arrow_deals_half_on_a_miss() -> void:
	var e := _wizard_fight()
	e.get_combatant("gob").sheet.armor_base = 60  # only a natural 20 hits
	var res := e.submit(_cast("wiz", "acid_arrow", "gob", 2))
	var atk := CoreFixtures.first_event(_evs(res), "attack")
	var dmg := CoreFixtures.first_event(_evs(res), "damage")
	if atk["hit"]:
		assert_in_range(dmg["amount"], 8, 32)
	else:
		assert_in_range(dmg["amount"], 2, 8, "half of 4d4")


func test_save_spell_emits_save_and_damage_on_failure() -> void:
	var e := _wizard_fight(Vector2i(7, 2), 100, ["sacred_flame", "thunder_save"])
	var gob := e.get_combatant("gob")
	gob.sheet.abilities.set_score(Ability.Type.DEX, 14)
	var wiz := e.get_combatant("wiz")
	wiz.sheet.spells_prepared.append("sacred_flame")
	var res := e.submit(_cast("wiz", "sacred_flame", "gob"))
	assert_true(_ok(res), str(res["error"]))
	var save := CoreFixtures.first_event(_evs(res), "save")
	assert_eq(save["actor"], "wiz")
	assert_eq(save["target"], "gob")
	assert_eq(save["ability"], "DEX")
	assert_eq(save["dc"], 13)
	assert_eq(DictUtil.to_int(save["total"]), DictUtil.to_int(save["natural"]) + 2)
	assert_eq(save["success"], DictUtil.to_int(save["total"]) >= 13)
	var dmg := CoreFixtures.first_event(_evs(res), "damage")
	if save["success"]:
		assert_eq(dmg, {}, "on_save none")
	else:
		assert_in_range(dmg["amount"], 1, 8)
		assert_eq(dmg["type"], "radiant")


func test_half_damage_save_still_hurts_on_success() -> void:
	var e := _wizard_fight(Vector2i(7, 2), 100, ["thunder_save"])
	e.get_combatant("gob").sheet.abilities.set_score(Ability.Type.CON, 30)  # +10: always saves vs DC 13 unless a 1/2
	var res := e.submit(_cast("wiz", "thunder_save", "gob", 1))
	var save := CoreFixtures.first_event(_evs(res), "save")
	var dmg := CoreFixtures.first_event(_evs(res), "damage")
	assert_false(dmg.is_empty(), "half damage on a success")
	if save["success"]:
		assert_in_range(dmg["amount"], 1, 8)


func test_unconscious_target_fails_dex_saves() -> void:
	var make := func() -> Array:
		var cleric := CoreFixtures.combatant("evil", CoreFixtures.caster("Evil", Ability.Type.WIS, ["sacred_flame"]), Combatant.TEAM_MONSTERS, Vector2i(2, 2))
		var victim := CoreFixtures.combatant("hero", CoreFixtures.sheet("Hero", 20), Combatant.TEAM_PLAYERS, Vector2i(5, 2))
		var friend := CoreFixtures.combatant("friend", CoreFixtures.sheet("Friend", 20), Combatant.TEAM_PLAYERS, Vector2i(9, 9))
		return [cleric, victim, friend]
	var e := CoreFixtures.fight(make, "evil", content)
	var hero := e.get_combatant("hero")
	hero.sheet.take_damage(20)
	assert_true(hero.is_dying())
	var res := e.submit(_cast("evil", "sacred_flame", "hero"))
	assert_true(_ok(res), str(res["error"]))
	var save := CoreFixtures.first_event(_evs(res), "save")
	assert_eq(save["success"], false)
	assert_eq(save["natural"], 0, "no roll: automatic failure")
	var dmg := CoreFixtures.first_event(_evs(res), "damage")
	assert_eq(dmg["hp_after"], 0)
	assert_true(hero.sheet.death_save_failures >= 1, "damage at 0 hp is a death-save failure")


func _cleric_fight() -> Encounter:
	var make := func() -> Array:
		var cleric := CoreFixtures.combatant("cleric", CoreFixtures.caster("Cleric", Ability.Type.WIS, ["cure_wounds", "healing_word", "sacred_flame"]), Combatant.TEAM_PLAYERS, Vector2i(2, 2))
		var ally := CoreFixtures.combatant("ally", CoreFixtures.sheet("Ally", 20), Combatant.TEAM_PLAYERS, Vector2i(3, 2))
		var gob := CoreFixtures.combatant("gob", CoreFixtures.sheet("Gob", 50), Combatant.TEAM_MONSTERS, Vector2i(9, 9), [SURE_HIT])
		return [cleric, ally, gob]
	var e := CoreFixtures.fight(make, "cleric", content)
	assert_not_null(e)
	return e


func test_cure_wounds_revives_a_dying_ally() -> void:
	var e := _cleric_fight()
	var ally := e.get_combatant("ally")
	ally.sheet.take_damage(20)
	ally.sheet.death_save_failures = 2
	assert_true(ally.is_dying())
	var res := e.submit(_cast("cleric", "cure_wounds", "ally", 1))
	assert_true(_ok(res), str(res["error"]))
	var heal := CoreFixtures.first_event(_evs(res), "heal")
	assert_eq(heal["source"], "cleric")
	assert_eq(heal["target"], "ally")
	assert_eq(heal["revived"], true)
	assert_in_range(heal["amount"], 4, 11, "1d8 + WIS 3")
	assert_eq(heal["hp_after"], heal["amount"])
	assert_true(ally.is_conscious())
	assert_eq(ally.sheet.death_save_failures, 0, "death saves reset")
	assert_eq(e.get_combatant("cleric").sheet.spell_slots, [1, 2])


func test_cure_wounds_is_touch_and_upcasts() -> void:
	var e := _cleric_fight()
	var ally := e.get_combatant("ally")
	ally.position = Vector2i(5, 2)
	ally.sheet.take_damage(19)
	assert_true(str(e.submit(_cast("cleric", "cure_wounds", "ally", 1))["error"]).contains("out of range"))
	ally.position = Vector2i(3, 3)
	var res := e.submit(_cast("cleric", "cure_wounds", "ally", 2))
	var heal := CoreFixtures.first_event(_evs(res), "heal")
	assert_in_range(heal["rolled"], 5, 19, "2d8 + 3 at slot 2")
	assert_eq(heal["revived"], false)


func test_healing_word_is_a_ranged_bonus_action() -> void:
	var e := _cleric_fight()
	var ally := e.get_combatant("ally")
	ally.position = Vector2i(10, 2)
	ally.sheet.take_damage(20)
	var res := e.submit(_cast("cleric", "healing_word", "ally", 1))
	assert_true(_ok(res), str(res["error"]))
	assert_eq(CoreFixtures.first_event(_evs(res), "heal")["revived"], true)
	var cleric := e.get_combatant("cleric")
	assert_true(cleric.bonus_action_used)
	assert_false(cleric.action_used)
	assert_false(_ok(e.submit(_cast("cleric", "healing_word", "cleric", 1))), "bonus action spent")
	e.get_combatant("gob").position = Vector2i(2, 9)
	var flame := e.submit(_cast("cleric", "sacred_flame", "gob"))
	assert_true(_ok(flame), "the action is still free: %s" % flame["error"])


func test_heal_cannot_target_the_dead_or_enemies() -> void:
	var e := _cleric_fight()
	assert_true(str(e.submit(_cast("cleric", "healing_word", "gob", 1))["error"]).contains("not an ally"))
	e.get_combatant("ally").sheet.kill()
	assert_true(str(e.submit(_cast("cleric", "healing_word", "ally", 1))["error"]).contains("dead"))


func test_level_up_raises_slots_from_the_class_table() -> void:
	var cls := ClassDefinition.from_dict({
		"id": "mage", "display_name": "Mage", "hit_die": 6, "primary_abilities": ["INT"], "saving_throws": ["INT", "WIS"],
		"armor_proficiencies": [], "weapon_proficiencies": ["dagger"], "skill_choices": ["ARCANA"], "skill_choice_count": 1,
		"spellcasting": {"ability": "INT", "prepared": ["fire_bolt", "magic_missile"], "slots": {"1": [2], "2": [3], "3": [4, 2]}},
	})
	assert_not_null(cls)
	assert_eq(cls.slots_for_level(1), [2])
	assert_eq(cls.slots_for_level(3), [4, 2])
	assert_eq(cls.slots_for_level(7), [4, 2], "highest known row")
	var none: Array[int] = []
	var s := CharacterBuilder.create("M", cls, null, AbilityScores.new(), none, null, content)
	assert_eq(s.casting_ability, Ability.Type.INT)
	assert_eq(s.spells_prepared, ["fire_bolt", "magic_missile"])
	assert_eq(s.spell_slots, [2])
	s.use_spell_slot(1)
	s.level_up(null, true, cls)
	assert_eq(s.spell_slots_max, [3])
	assert_eq(s.spell_slots, [2], "the new slot is available, the spent one is not")
	s.level_up(null, true, cls)
	assert_eq(s.spell_slots_max, [4, 2])
	assert_eq(s.spell_slots, [3, 2])
	Rest.long_rest(s)
	assert_eq(s.spell_slots, [4, 2])


func test_pact_magic_recovers_slots_on_a_short_rest() -> void:
	var pact := CoreFixtures.caster("Lock", Ability.Type.CHA, ["hex"])
	pact.slot_recovery = "short_rest"
	pact.spell_slots = [0, 0]
	Rest.short_rest(pact, 0, Rng.new(1))
	assert_eq(pact.spell_slots, [2, 2])
	var wiz := CoreFixtures.caster("Wiz", Ability.Type.INT, ["fire_bolt"])
	wiz.spell_slots = [0, 0]
	Rest.short_rest(wiz, 0, Rng.new(1))
	assert_eq(wiz.spell_slots, [0, 0], "long-rest casters wait for a long rest")
	Rest.long_rest(wiz)
	assert_eq(wiz.spell_slots, [2, 2])


func test_real_spells_load() -> void:
	var spells := ContentLoader.load_spells()
	if spells.is_empty():
		return  # CONTENT has not landed data/spells yet
	for spell_id: String in ["fire_bolt", "ray_of_frost", "magic_missile", "mage_armor", "sacred_flame", "cure_wounds", "healing_word", "guiding_bolt", "vicious_mockery", "produce_flame", "eldritch_blast", "hex"]:
		assert_true(spells.has(spell_id), spell_id)
		if spells.has(spell_id):
			var sp: SpellDefinition = spells[spell_id]
			assert_true(sp.is_supported(), "%s is castable" % spell_id)
	var hex: SpellDefinition = spells["hex"]
	assert_eq(hex.effect_type, "mark")
	var frost: SpellDefinition = spells["ray_of_frost"]
	assert_eq(frost.rider, "slow")
	var mockery: SpellDefinition = spells["vicious_mockery"]
	assert_eq(mockery.rider, "mockery")
	var bolt: SpellDefinition = spells["guiding_bolt"]
	assert_eq(bolt.rider, "guiding_bolt_mark")
	var warlock_slots: ClassDefinition = ContentLoader.cache()["classes"]["warlock"]
	assert_eq(warlock_slots.slot_recovery, "short_rest")

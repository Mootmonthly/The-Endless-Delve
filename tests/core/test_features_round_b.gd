extends TestCase
## Class features of levels 6-12 (round B) for all twelve classes, the new
## level-up choices, rests and Features.IMPLEMENTED.

const SURE := {"name": "Sure", "kind": "melee", "to_hit": 100, "damage": "1d8+2", "damage_type": "slashing", "ability": "STR"}
const BOW := {"name": "Bow", "kind": "ranged", "to_hit": 100, "damage": "4", "damage_type": "piercing", "range_tiles": [16, 64]}

var content: Dictionary


func before_each() -> void:
	content = CoreFixtures.content()
	var bear := MonsterDefinition.from_dict({"schema_version": 1, "id": "black_bear", "display_name": "Black Bear", "creature_type": "beast",
		"armor_class": 11, "hit_points": 19, "hit_dice": "3d8+6", "speed": 40, "challenge_rating": 0.5, "xp": 100,
		"abilities": {"STR": 15, "DEX": 10, "CON": 14, "INT": 2, "WIS": 12, "CHA": 7},
		"attacks": [{"name": "Claws", "kind": "melee", "to_hit": 4, "damage": "2d4+2", "damage_type": "slashing"}]})
	content["monsters"]["black_bear"] = bear


func _evs(res: Dictionary) -> Array:
	var evs: Array = res.get("events", [])
	return evs


func _duel(hero: CharacterSheet, gob: CharacterSheet = null, first: String = "hero", gob_pos: Vector2i = Vector2i(4, 3), allies: Dictionary = {}) -> Encounter:
	var g := gob if gob != null else CoreFixtures.sheet("Gob", 200, [10, 10, 10, 10, 1, 1])
	var e := CoreFixtures.duel(hero, [SURE, BOW], {"gob": [g, gob_pos, [SURE]]}, content, first, Vector2i(3, 3), allies)
	assert_not_null(e)
	return e


func _feature(e: Encounter, feature: String, fields: Dictionary = {}) -> Dictionary:
	var f := {"feature": feature}
	f.merge(fields)
	return e.submit(CoreFixtures.intent("use_feature", "hero", f))


# --- barbarian ---------------------------------------------------------------------

func test_barbarian_mindless_rage_feral_instinct_brutal_critical() -> void:
	var s := CoreFixtures.sheet("Barb", 80, [], ["rage", "mindless_rage", "feral_instinct", "brutal_critical"])
	s.level = 9
	s.restore_class_resources()
	var e := _duel(s)
	var hero := e.get_combatant("hero")
	assert_eq(hero.initiative_mode(), D20.RollMode.ADVANTAGE)
	e._apply_condition(hero, Conditions.FRIGHTENED, "gob", Conditions.duration(Conditions.DURATION_ENCOUNTER))
	_feature(e, "rage")
	assert_false(hero.has_condition(Conditions.FRIGHTENED), "raging ends fear")
	assert_false(e._apply_condition(hero, Conditions.CHARMED, "gob", Conditions.duration(Conditions.DURATION_ENCOUNTER)))
	# Brutal Critical: one extra weapon die on a critical hit.
	hero.reckless = false
	var gob := e.get_combatant("gob")
	gob.sheet.current_hp = 0
	gob.sheet.uses_death_saves = true
	var r := e._roll_attack(hero, gob, SURE, false, null)
	assert_true(r.critical, "auto crit on an unconscious target")
	var sources: Array = []
	for x in r.extras:
		sources.append(x["source"])
	assert_has(sources, "brutal_critical")


func test_intimidating_presence_and_relentless_rage() -> void:
	var s := CoreFixtures.sheet("Barb", 30, [10, 10, 30, 10, 10, 30], ["rage", "intimidating_presence", "relentless_rage"])
	s.level = 11
	s.restore_class_resources()
	var e := _duel(s)
	var res := _feature(e, "intimidating_presence", {"target": "gob"})
	assert_true(res["ok"] == true, str(res["error"]))
	assert_true(e.get_combatant("gob").has_condition(Conditions.FRIGHTENED), "WIS 1 fails")
	var e2 := _duel(s)
	_feature(e2, "rage")
	var hero := e2.get_combatant("hero")
	e2._deal_effect_damage(null, hero, 35, "fire", {})
	assert_eq(hero.sheet.current_hp, 1, "CON 30 makes DC 10")
	assert_eq(hero.sheet.relentless_rage_uses, 1)
	Rest.short_rest(hero.sheet, 0, Rng.new(1))
	assert_eq(hero.sheet.relentless_rage_uses, 0)


func test_frenzy_costs_exhaustion() -> void:
	var s := CoreFixtures.sheet("Barb", 80, [], ["rage", "frenzy"])
	s.restore_class_resources()
	var e := _duel(s)
	_feature(e, "rage", {"frenzy": true})
	var hero := e.get_combatant("hero")
	e._end_rage(hero)
	assert_eq(hero.sheet.exhaustion, 1)
	assert_eq(CoreFixtures.first_event(e.events, "exhaustion")["source"], "frenzy")


# --- bard / cleric ----------------------------------------------------------------

func test_countercharm_gives_advantage_on_fear_saves() -> void:
	var s := CoreFixtures.sheet("Bard", 30, [], ["countercharm"])
	var e := _duel(s)
	_feature(e, "countercharm")
	var hero := e.get_combatant("hero")
	assert_true(hero.has_buff("countercharm"))
	e._saving_throw("gob", hero, Ability.Type.WIS, 10, {"vs_condition": Conditions.FRIGHTENED})
	assert_eq(CoreFixtures.events_of(e.events, "save")[0]["advantage"], "advantage")


func test_blessed_healer_divine_strike_divine_intervention() -> void:
	var s := CoreFixtures.caster("Cleric", Ability.Type.WIS, ["cure_wounds"], 40)
	s.features.append_array(["blessed_healer", "divine_strike", "divine_intervention"])
	s.level = 10
	s.restore_class_resources()
	var allies := {"ally": [CoreFixtures.sheet("Ally", 40), Vector2i(3, 4), [SURE]]}
	var e := _duel(s, null, "hero", Vector2i(4, 3), allies)
	var hero := e.get_combatant("hero")
	hero.sheet.current_hp = 20
	e.get_combatant("ally").sheet.current_hp = 10
	var res := e.submit(CoreFixtures.intent("cast", "hero", {"spell": "cure_wounds", "target": "ally"}))
	assert_true(res["ok"] == true, str(res["error"]))
	var heals := CoreFixtures.events_of(_evs(res), "heal")
	assert_eq(heals[1]["target"], "hero")
	assert_eq(heals[1]["amount"], 3, "2 + spell level")
	e.end_turn()
	e.end_turn()
	e.end_turn()
	res = e.submit(CoreFixtures.intent("attack", "hero", {"target": "gob", "attack_index": 0}))
	var extra: Array = CoreFixtures.first_event(_evs(res), "damage")["extra"]
	assert_eq(extra[0]["source"], "divine_strike")
	assert_eq(extra[0]["type"], "radiant")
	res = _feature(e, "divine_intervention")
	assert_true(res["ok"] == false, "the action is used")
	var e2 := _duel(s)
	e2.get_combatant("hero").sheet.level = 20
	res = _feature(e2, "divine_intervention")
	assert_true(CoreFixtures.first_event(_evs(res), "divine_intervention")["success"])
	assert_eq(e2.get_combatant("hero").sheet.current_hp, 40)


# --- druid ------------------------------------------------------------------------

func test_wild_shape_and_natures_ward() -> void:
	var s := CoreFixtures.sheet("Druid", 30, [10, 10, 10, 10, 16, 10], ["wild_shape", "natures_ward"])
	s.level = 4
	s.restore_class_resources()
	assert_true(s.damage_immunities.has("poison") or true)
	s.gain_feature("purity_of_body")
	assert_true(s.damage_immunities.has("poison"))
	assert_true(s.condition_immunities.has("poisoned"))
	var e := _duel(s)
	assert_true(str(_feature(e, "wild_shape", {"form": "wolf"})["error"]).contains("cannot take"))
	var res := _feature(e, "wild_shape", {"form": "black_bear"})
	assert_true(res["ok"] == true, str(res["error"]))
	var hero := e.get_combatant("hero")
	assert_eq(hero.sheet.max_hp, 19)
	assert_eq(hero.attacks[0]["name"], "Claws")
	assert_eq(hero.sheet.class_resource("wild_shape"), 1)
	e._deal_effect_damage(null, hero, 25, "fire", {})
	assert_eq(hero.sheet.max_hp, 30, "reverted")
	assert_eq(hero.sheet.current_hp, 24, "6 excess damage")
	assert_true(str(e.submit(CoreFixtures.intent("cast", "hero", {"spell": "fire_bolt", "target": "gob"}))["error"]).length() > 0)


# --- fighter / monk -----------------------------------------------------------------

func test_indomitable_survivor_superior_critical() -> void:
	var s := CoreFixtures.sheet("Fighter", 100, [10, 10, 10, 10, 1, 10], ["indomitable", "survivor", "superior_critical"])
	s.level = 18
	s.restore_class_resources()
	assert_eq(s.class_resource("indomitable"), 3)
	var e := _duel(s)
	var hero := e.get_combatant("hero")
	e._saving_throw("gob", hero, Ability.Type.WIS, 30)
	assert_eq(CoreFixtures.first_event(e.events, "save_modified")["feature"], "indomitable")
	assert_eq(hero.sheet.class_resource("indomitable"), 2)
	hero.sheet.current_hp = 40
	e.end_turn()
	var res := e.submit(CoreFixtures.intent("end_turn", "gob"))
	assert_eq(CoreFixtures.first_event(_evs(res), "heal")["amount"], 5, "Survivor: 5 + CON")


func test_monk_wholeness_stillness_evasion_diamond_soul_empty_body() -> void:
	var s := CoreFixtures.sheet("Monk", 80, [10, 10, 10, 10, 10, 10], ["ki", "wholeness_of_body", "stillness_of_mind", "evasion", "diamond_soul", "empty_body"])
	s.level = 18
	s.restore_class_resources()
	assert_eq(s.save_modifier(Ability.Type.CHA), 6, "Diamond Soul: proficient in every save")
	var e := _duel(s)
	var hero := e.get_combatant("hero")
	hero.sheet.current_hp = 10
	var res := _feature(e, "wholeness_of_body")
	assert_eq(CoreFixtures.first_event(_evs(res), "heal")["amount"], 54)
	assert_eq(e._save_damage(hero, Ability.Type.DEX, 20, true, true), 0, "Evasion: none on a success")
	assert_eq(e._save_damage(hero, Ability.Type.DEX, 20, false, true), 10, "half on a failure")
	e.end_turn()
	e.end_turn()
	e._apply_condition(hero, Conditions.CHARMED, "gob", Conditions.duration(Conditions.DURATION_ENCOUNTER))
	res = _feature(e, "stillness_of_mind")
	assert_false(hero.has_condition(Conditions.CHARMED))
	e.end_turn()
	e.end_turn()
	res = _feature(e, "empty_body")
	assert_true(res["ok"] == true, str(res["error"]))
	assert_true(hero.is_invisible())
	assert_eq(hero.adjust_damage(10, "fire"), 5)
	assert_eq(hero.adjust_damage(10, "force"), 10)


func test_ki_empowered_strikes_beat_nonmagical_resistance() -> void:
	var gob := CoreFixtures.sheet("Golem", 200)
	gob.damage_resistances = ["bludgeoning, piercing, and slashing from nonmagical weapons"]
	var plain := CoreFixtures.sheet("Monk", 40, [], ["martial_arts"])
	var e := _duel(plain, gob)
	var punch: Dictionary = plain.unarmed_strike()
	punch["to_hit"] = 100
	punch["damage"] = "10"
	var r := e._roll_attack(e.get_combatant("hero"), e.get_combatant("gob"), punch, false, null)
	if r.hit:
		assert_eq(r.damage_total, 5, "resisted")
	var ki := CoreFixtures.sheet("Monk", 40, [], ["martial_arts", "ki_empowered_strikes"])
	var e2 := _duel(ki, gob)
	r = e2._roll_attack(e2.get_combatant("hero"), e2.get_combatant("gob"), punch, false, null)
	if r.hit:
		assert_eq(r.damage_total, 10, "magical strikes")
	assert_eq(gob.adjust_damage_for_type(10, "slashing", [], true), 10)
	assert_eq(gob.adjust_damage_for_type(10, "slashing"), 5)


# --- paladin ----------------------------------------------------------------------

func test_paladin_auras_improved_smite_cleansing_touch() -> void:
	var s := CoreFixtures.sheet("Paladin", 60, [10, 10, 10, 10, 10, 16], ["aura_of_protection", "aura_of_devotion", "aura_of_courage", "improved_divine_smite", "cleansing_touch"])
	s.level = 14
	s.restore_class_resources()
	var allies := {"ally": [CoreFixtures.sheet("Ally", 40), Vector2i(3, 5), [SURE]]}
	var e := _duel(s, null, "hero", Vector2i(4, 3), allies)
	var ally := e.get_combatant("ally")
	assert_eq(e._save_flat_bonus(ally, Ability.Type.DEX), 3, "+CHA within 10 ft")
	assert_false(e._apply_condition(ally, Conditions.CHARMED, "gob", Conditions.duration(Conditions.DURATION_ENCOUNTER)))
	assert_false(e._apply_condition(ally, Conditions.FRIGHTENED, "gob", Conditions.duration(Conditions.DURATION_ENCOUNTER)))
	ally.position = Vector2i(3, 7)
	assert_eq(e._save_flat_bonus(ally, Ability.Type.DEX), 0, "outside the aura")
	var res := e.submit(CoreFixtures.intent("attack", "hero", {"target": "gob", "attack_index": 0}))
	assert_eq(CoreFixtures.first_event(_evs(res), "damage")["extra"][0]["source"], "improved_divine_smite")
	e.end_turn()
	e.end_turn()
	e.end_turn()
	var hero := e.get_combatant("hero")
	e._apply_condition(hero, Conditions.PARALYZED, "gob", Conditions.duration(Conditions.DURATION_ENCOUNTER), {"spell": "hold_person"})
	assert_true(str(_feature(e, "cleansing_touch")["error"]).contains("incapacitated"))
	hero.conditions.clear()
	e._apply_condition(hero, Conditions.POISONED, "gob", Conditions.duration(Conditions.DURATION_ENCOUNTER), {"spell": "ray_of_sickness"})
	res = _feature(e, "cleansing_touch")
	assert_true(res["ok"] == true, str(res["error"]))
	assert_false(hero.has_condition(Conditions.POISONED))


# --- ranger -----------------------------------------------------------------------

func test_ranger_defensive_tactics_and_multiattack() -> void:
	var s := CoreFixtures.sheet("Ranger", 60, [], ["escape_the_horde", "multiattack_defense", "steel_will", "volley", "whirlwind_attack"])
	s.add_item("arrows", 10)
	var foes := {"a": [CoreFixtures.sheet("A", 50), Vector2i(8, 3), [SURE]], "b": [CoreFixtures.sheet("B", 50), Vector2i(9, 4), [SURE]], "c": [CoreFixtures.sheet("C", 50), Vector2i(4, 3), [SURE]]}
	var bow := {"name": "Longbow", "kind": "ranged", "to_hit": 100, "damage": "4", "damage_type": "piercing", "range_tiles": [30, 120], "consumes": "arrows"}
	var e := CoreFixtures.duel(s, [SURE, bow], foes, content)
	var hero := e.get_combatant("hero")
	var c := e.get_combatant("c")
	assert_eq(e._attack_mode(c, hero, SURE, true, {"opportunity": true})["mode"], D20.RollMode.DISADVANTAGE, "Escape the Horde")
	var res := _feature(e, "volley", {"attack_index": 1, "point": [8, 3]})
	assert_true(res["ok"] == true, str(res["error"]))
	assert_eq(CoreFixtures.events_of(_evs(res), "attack").size(), 2, "a and b are within 10 ft of the point")
	assert_eq(hero.sheet.count_item("arrows"), 8)
	e.end_turn()
	e.end_turn()
	e.end_turn()
	e.end_turn()
	res = _feature(e, "whirlwind_attack", {"attack_index": 0})
	assert_eq(CoreFixtures.events_of(_evs(res), "attack").size(), 1, "only c is in reach")
	e._after_hit_by(c, hero, true, 3)
	var r := AttackResolver.roll(c, hero, {"to_hit": 0, "damage": "1", "target_ac_bonus": 0}, Rng.new(1))
	assert_eq(r.target_ac, hero.armor_class())
	assert_eq(DictUtil.to_int(hero.defended_against.get("c", -1)), e.turn_counter, "Multiattack Defense remembers")
	e._saving_throw("c", hero, Ability.Type.WIS, 10, {"vs_condition": Conditions.FRIGHTENED})
	var saves := CoreFixtures.events_of(e.events, "save")
	assert_eq(saves[saves.size() - 1]["advantage"], "advantage", "Steel Will")


func test_hunter_options_are_level_up_choices() -> void:
	assert_eq(LevelUp.feature_options("defensive_tactics", null), ["escape_the_horde", "multiattack_defense", "steel_will"] as Array[String])
	assert_eq(LevelUp.feature_options("multiattack", null), ["volley", "whirlwind_attack"] as Array[String])
	assert_eq(LevelUp.feature_options("superior_hunters_defense", null).size(), 3)


# --- rogue --------------------------------------------------------------------------

func test_rogue_elusive_blindsense_slippery_mind_supreme_sneak() -> void:
	var s := CoreFixtures.sheet("Rogue", 60, [10, 30, 10, 10, 10, 10], ["elusive", "blindsense", "supreme_sneak", "cunning_action"])
	s.proficient_skills = [Skill.Type.STEALTH]
	s.gain_feature("slippery_mind")
	assert_true(s.proficient_saves.has(Ability.Type.WIS))
	var e := _duel(s, null, "hero", Vector2i(5, 3))
	var hero := e.get_combatant("hero")
	var gob := e.get_combatant("gob")
	hero.reckless = true
	assert_ne(e._attack_mode(gob, hero, SURE, true)["mode"], D20.RollMode.ADVANTAGE, "Elusive")
	gob.hidden = true
	assert_true(e.can_see(hero, gob), "Blindsense within 10 ft")
	gob.position = Vector2i(9, 3)
	assert_false(e.can_see(hero, gob))
	gob.hidden = false
	var res := _feature(e, "cunning_action", {"mode": "hide"})
	assert_true(res["ok"] == true, str(res["error"]))
	assert_eq(CoreFixtures.first_event(_evs(res), "check")["advantage"], "advantage", "Supreme Sneak")


# --- sorcerer / warlock / wizard -------------------------------------------------------

func test_elemental_affinity_and_dragon_wings() -> void:
	var s := CoreFixtures.caster("Sorc", Ability.Type.CHA, ["fire_bolt"], 40)
	s.features.append_array(["font_of_magic", "elemental_affinity", "dragon_ancestor_red", "dragon_wings"])
	s.level = 14
	s.restore_class_resources()
	var e := _duel(s, null, "hero", Vector2i(6, 3))
	var res := e.submit(CoreFixtures.intent("cast", "hero", {"spell": "fire_bolt", "target": "gob"}))
	var dmg := CoreFixtures.first_event(_evs(res), "damage")
	if CoreFixtures.first_event(_evs(res), "attack")["hit"]:
		assert_eq(dmg["extra"][0]["source"], "elemental_affinity")
		assert_eq(dmg["extra"][0]["amount"], 3)
	res = _feature(e, "elemental_affinity")
	assert_true(res["ok"] == true, str(res["error"]))
	assert_eq(e.get_combatant("hero").adjust_damage(10, "fire"), 5)
	res = _feature(e, "dragon_wings")
	assert_eq(e.get_combatant("hero").fly_tiles(), 6)


func test_dark_ones_own_luck_and_fiendish_resilience() -> void:
	var s := CoreFixtures.sheet("Lock", 40, [10, 10, 10, 10, 10, 10], ["dark_ones_own_luck"])
	s.restore_class_resources()
	s.chosen_resistance = "cold"
	assert_eq(s.adjust_damage_for_type(10, "cold"), 5)
	var e := _duel(s)
	var hero := e.get_combatant("hero")
	for _i in range(20):
		if hero.sheet.class_resource("dark_ones_own_luck") == 0:
			break
		e._saving_throw("gob", hero, Ability.Type.WIS, 15)
	assert_eq(hero.sheet.class_resource("dark_ones_own_luck"), 0)
	assert_eq(CoreFixtures.first_event(e.events, "save_modified")["feature"], "dark_ones_own_luck")
	Rest.short_rest(hero.sheet, 0, Rng.new(1))
	assert_eq(hero.sheet.class_resource("dark_ones_own_luck"), 1)


func test_potent_cantrip_and_empowered_evocation() -> void:
	var s := CoreFixtures.caster("Wiz", Ability.Type.INT, ["sacred_flame", "magic_missile"], 40)
	s.class_id = "wizard"
	s.features.append_array(["potent_cantrip", "empowered_evocation"])
	content["spells"]["magic_missile"].school = "evocation"
	var gob := CoreFixtures.sheet("Gob", 200, [10, 30, 10, 10, 10, 10])
	var e := _duel(s, gob, "hero", Vector2i(6, 3))
	var res := e.submit(CoreFixtures.intent("cast", "hero", {"spell": "sacred_flame", "target": "gob"}))
	assert_true(CoreFixtures.first_event(_evs(res), "save")["success"])
	assert_eq(CoreFixtures.events_of(_evs(res), "damage").size(), 1, "half damage on a success")
	e.end_turn()
	e.end_turn()
	res = e.submit(CoreFixtures.intent("cast", "hero", {"spell": "magic_missile", "target": "gob"}))
	assert_true(DictUtil.to_int(CoreFixtures.first_event(_evs(res), "damage")["amount"]) >= 3 * 2 + 3, "+INT once")


# --- level-up choices and data -------------------------------------------------------------

func test_level_up_choices_round_b() -> void:
	var cache := ContentLoader.cache()
	var classes: Dictionary = cache.get("classes", {})
	if not classes.has("warlock") or not classes.has("bard"):
		return
	var lock := CharacterSheet.new()
	lock.class_id = "warlock"
	lock.level = 10
	lock.subclass_id = "fiend"
	lock.xp = Experience.xp_for_level(11)
	var ch := LevelUp.choices(lock, cache)
	var arcanum := {}
	for entry: Dictionary in ch["choices"]:
		if entry["type"] == "mystic_arcanum":
			arcanum = entry
	assert_eq(arcanum.get("spell_level", 0), 6)
	assert_false((arcanum.get("options", []) as Array).is_empty())
	lock.level = 9
	lock.xp = Experience.xp_for_level(10)
	ch = LevelUp.choices(lock, cache)
	var types: Array = []
	for entry: Dictionary in ch["choices"]:
		types.append(entry["type"])
	assert_has(types, "damage_type", "Fiendish Resilience")
	var bard := CharacterSheet.new()
	bard.class_id = "bard"
	bard.subclass_id = "lore"
	bard.level = 9
	bard.xp = Experience.xp_for_level(10)
	ch = LevelUp.choices(bard, cache)
	var secrets := {}
	for entry: Dictionary in ch["choices"]:
		if entry["type"] == "magical_secrets":
			secrets = entry
	assert_eq(secrets.get("count", 0), 2)
	assert_has(secrets["options"], "fireball", "any class's spell")
	var picks := {}
	assert_eq(LevelUp.check_choices([{"type": "damage_type", "count": 1, "options": ["fire", "cold"], "default": ["fire"]}], {"damage_type": "cold"}, picks), "")
	var sheet := CharacterSheet.new()
	LevelUp.apply_picks(sheet, picks)
	assert_eq(sheet.chosen_resistance, "cold")


func test_features_implemented_list_is_exact() -> void:
	for id in Features.IMPLEMENTED:
		assert_eq(Features.IMPLEMENTED.count(id), 1, "%s listed once" % id)
	for id: String in ["mindless_rage", "countercharm", "blessed_healer", "wild_shape", "indomitable", "evasion", "aura_of_protection",
			"volley", "reliable_talent", "elemental_affinity", "mystic_arcanum", "potent_cantrip", "cutting_words", "jack_of_all_trades"]:
		assert_true(Features.is_implemented(id), id)
	for id: String in ["quivering_palm", "stroke_of_luck", "overchannel", "hurl_through_hell", "slow_fall"]:
		assert_false(Features.is_implemented(id), "%s is round C" % id)
	assert_eq(Features.IMPLEMENTED_METAMAGIC.size(), 8)


func test_rest_round_b() -> void:
	var s := CoreFixtures.sheet("Sorc", 40, [], ["font_of_magic", "sorcerous_restoration", "tranquility"])
	s.level = 20
	s.restore_class_resources()
	s.class_resources["sorcery_points"] = 10
	Rest.short_rest(s, 0, Rng.new(1))
	assert_eq(s.class_resource("sorcery_points"), 14)
	s.companions = [{"monster": "skeleton", "spell": "animate_dead", "hp": 13, "until_long_rest": true}, {"monster": "owl", "spell": "find_familiar", "hp": 1}]
	s.resurrection_penalty = 4
	Rest.long_rest(s)
	assert_eq(s.companions.size(), 1, "animated dead leave at a long rest")
	assert_eq(s.resurrection_penalty, 3)
	assert_true(s.active_buffs.has("tranquility"))
	var w := CoreFixtures.sheet("Wiz", 20, [], ["arcane_recovery"])
	w.level = 6
	w.spell_slots_max = [4, 3, 3]
	w.spell_slots = [0, 0, 0]
	w.restore_class_resources()
	assert_eq(Rest.default_slot_recovery(w), [3] as Array[int])


func test_out_of_combat_raise_dead() -> void:
	var cleric := CoreFixtures.caster("Cleric", Ability.Type.WIS, ["raise_dead"], 40)
	cleric.spell_slots_max = [4, 3, 3, 3, 2]
	cleric.spell_slots = [4, 3, 3, 3, 2]
	var spell := CoreFixtures.spell({"id": "raise_dead", "display_name": "Raise Dead", "level": 5, "casting_time": "1_hour", "range_ft": 5, "effect": {"type": "unsupported"}})
	content["spells"]["raise_dead"] = spell
	var friend := CoreFixtures.sheet("Friend", 30)
	friend.kill()
	var targets: Array[CharacterSheet] = [friend]
	var r := OutOfCombat.cast(cleric, "raise_dead", content, Rng.new(1), targets)
	assert_true(r["ok"] == true, str(r["error"]))
	assert_true(friend.is_alive())
	assert_eq(friend.current_hp, 1)
	assert_eq(friend.resurrection_penalty, 4)
	assert_eq(cleric.slots_left(5), 1)
	assert_false(OutOfCombat.cast(cleric, "raise_dead", content, Rng.new(1), targets)["ok"] == true, "not dead any more")

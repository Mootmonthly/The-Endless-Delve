extends TestCase
## ClientState and the class progression systems (round A): conditions with
## durations, concentration, Extra Attack and Action Surge, resources spent
## through features, metamagic, Divine Smite, area spells, pushes and
## reactions, all folded from events the server would send.

const PID := "p1"
const ALLY := "p2"
const GOBLIN := "z1_goblin_0"
const RAT := "z1_giant_rat_1"
const UNDEAD := "z1_skeleton_2"


func _floor_dict() -> Dictionary:
	return {
		"schema_version": 1, "id": "prog_floor", "display_name": "Progression Hall",
		"rows": [
			"############",
			"#..........#",
			"#..........#",
			"#..........#",
			"#..........#",
			"#..........#",
			"############",
		],
		"arrival": [1, 1], "stairs": [10, 5],
		"encounter_zones": [{"id": "z1", "rect": [1, 1, 10, 5], "monster_ids": ["goblin"], "spawn_points": [[7, 3]]}],
	}


## A sheet of class_id raised to `level` with LevelUpDraft.first_valid.
func _sheet(class_id: String, level: int = 1) -> CharacterSheet:
	var d := CharacterDraft.new()
	d.character_name = "Tess"
	d.set_class(ContentLoader.load_classes()[class_id])
	d.set_ancestry(ContentLoader.load_ancestries()["human"])
	d.auto_assign()
	for skill in d.class_def.skill_choices:
		d.toggle_skill(skill, true)
	d.auto_choose()
	var s := d.build_sheet()
	while s.level < level:
		s.xp = maxi(s.xp, Experience.xp_for_level(s.level + 1))
		var draft := LevelUpDraft.first_valid(LevelUp.choices(s), s)
		assert_eq(LevelUp.apply(s, draft.to_choices(), {}, null), "", "%s level %d" % [class_id, s.level + 1])
	s.max_hp = 40
	s.current_hp = 40
	return s


func _events(events: Array) -> Dictionary:
	return Messages.make_result(Messages.ENCOUNTER_EVENTS, {"events": events, "encounter_id": "z1", "zone_id": "z1"})


## The player at (4, 3), an ally at (3, 3), goblin (7, 3), rat (8, 5),
## skeleton (5, 1); the player's combat turn in round 1.
func _fight(sheet: CharacterSheet) -> ClientState:
	var st := ClientState.new(PID)
	st.apply(Messages.make_result(Messages.FLOOR_LOADED, {"floor": _floor_dict()}))
	st.apply(Messages.make_result(Messages.CHARACTER_STATE, {"sheet": sheet.to_dict()}))
	st.apply(Messages.make_result(Messages.EXPLORE_STATE, {"tick": 1, "entities": [
		{"id": PID, "kind": "player", "position": [4, 3]},
		{"id": ALLY, "kind": "player", "position": [3, 3], "name": "Ally", "hp": 4, "max_hp": 30},
		{"id": GOBLIN, "kind": "monster", "position": [7, 3], "name": "Goblin", "monster_id": "goblin", "hp": 7, "max_hp": 7},
		{"id": RAT, "kind": "monster", "position": [8, 5], "name": "Giant Rat", "monster_id": "giant_rat", "hp": 7, "max_hp": 7},
		{"id": UNDEAD, "kind": "monster", "position": [5, 1], "name": "Skeleton", "monster_id": "skeleton", "hp": 13, "max_hp": 13},
	]}))
	st.apply(_events([
		{"kind": "combatant_joined", "id": PID, "initiative": 20, "position": [4, 3]},
		{"kind": "combatant_joined", "id": ALLY, "initiative": 18, "position": [3, 3]},
		{"kind": "combatant_joined", "id": GOBLIN, "initiative": 15, "position": [7, 3]},
		{"kind": "combatant_joined", "id": RAT, "initiative": 5, "position": [8, 5]},
		{"kind": "combatant_joined", "id": UNDEAD, "initiative": 3, "position": [5, 1]},
		{"kind": "encounter_started", "order": [PID, ALLY, GOBLIN, RAT, UNDEAD]},
		{"kind": "round_started", "round": 1},
		{"kind": "turn_started", "actor": PID, "round": 1},
	]))
	return st


func _attack_ev(attacker: String, target: String, extra: Dictionary = {}) -> Dictionary:
	var ev := {"kind": "attack", "attacker": attacker, "target": target, "attack_name": "Longsword", "attack_kind": "melee",
		"natural": 15, "d20s": [15], "total": 20, "target_ac": 15, "hit": true, "critical": false, "fumble": false,
		"advantage": "normal", "bonus": false, "consumed": ""}
	ev.merge(extra, true)
	return ev


func _end_turn(actor: String, next: String) -> Dictionary:
	return _events([{"kind": "turn_ended", "actor": actor}, {"kind": "turn_started", "actor": next, "round": 1}])


func test_condition_tags_count_down_like_the_core() -> void:
	var st := _fight(_sheet("monk", 5))
	st.apply(_events([
		{"kind": "condition_applied", "target": GOBLIN, "condition": "stunned", "source": PID,
			"duration": {"type": "until_source_next_turn"}},
		{"kind": "condition_applied", "target": RAT, "condition": "frightened", "source": PID,
			"duration": {"type": "rounds", "rounds": 10}},
		{"kind": "condition_applied", "target": UNDEAD, "condition": "restrained", "source": PID,
			"duration": {"type": "save_ends", "ability": "STR", "dc": 13}},
	]))
	assert_has(st.status_tags(GOBLIN), "stunned (2 turns)", "applied on the source's own turn: its next turn end counts too")
	assert_has(st.status_tags(RAT), "frightened (10 rounds)")
	assert_has(st.status_tags(UNDEAD), "restrained (save DC 13 STR)")
	assert_has(st.log_lines, "Goblin is stunned (2 turns) by Tess.")
	assert_true(st.has_condition(GOBLIN, "incapacitated"), "stunned includes incapacitated")
	assert_true(st.is_immobilized(GOBLIN))
	st.apply(_end_turn(PID, ALLY))
	assert_has(st.status_tags(GOBLIN), "stunned (1 turn)")
	st.apply(_events([{"kind": "turn_ended", "actor": ALLY}, {"kind": "turn_started", "actor": GOBLIN, "round": 1},
		{"kind": "turn_ended", "actor": GOBLIN}, {"kind": "turn_started", "actor": RAT, "round": 1},
		{"kind": "turn_ended", "actor": RAT}]))
	assert_has(st.status_tags(RAT), "frightened (9 rounds)", "rounds count the target's turn ends")
	st.apply(_events([{"kind": "condition_ended", "target": GOBLIN, "condition": "stunned"}]))
	assert_eq(st.conditions_of(GOBLIN).size(), 0)
	assert_has(st.log_lines, "Goblin is no longer stunned.")
	# The player's own speed drops to 0 when restrained.
	st.apply(_events([{"kind": "turn_started", "actor": UNDEAD, "round": 1}, {"kind": "turn_ended", "actor": UNDEAD},
		{"kind": "round_started", "round": 2}, {"kind": "turn_started", "actor": PID, "round": 2}]))
	assert_true(st.movement_remaining > 0)
	st.apply(_events([{"kind": "condition_applied", "target": PID, "condition": "grappled", "source": GOBLIN,
		"duration": {"type": "encounter"}}]))
	assert_eq(st.movement_remaining, 0)
	assert_has(st.status_tags(PID), "grappled")
	st.apply(_events([{"kind": "encounter_ended", "winning_team": 0}]))
	assert_eq(st.conditions_of(PID).size(), 0, "encounter conditions end with it")


func test_concentration_marker_warning_and_end() -> void:
	var st := _fight(_sheet("warlock"))
	assert_eq(st.concentration_warning("hex"), "", "not concentrating yet")
	st.apply(_events([
		{"kind": "cast", "actor": PID, "spell": "hex", "target": GOBLIN, "slot_level": 1},
		{"kind": "concentration_started", "actor": PID, "spell": "hex"},
		{"kind": "effect_applied", "source": PID, "target": GOBLIN, "effect": "hex"},
	]))
	assert_true(st.bonus_action_used, "hex is a bonus action")
	assert_has(st.status_tags(PID), "concentrating: Hex")
	assert_has(st.concentration_warning("hex"), "ends your concentration on Hex")
	assert_eq(st.concentration_warning("eldritch_blast"), "", "no warning for a spell without concentration")
	st.apply(_events([
		{"kind": "concentration_check", "actor": PID, "spell": "hex", "dc": 10, "natural": 3, "total": 4, "success": false},
		{"kind": "concentration_ended", "actor": PID, "spell": "hex", "reason": "damage"},
		{"kind": "effect_ended", "target": GOBLIN, "effect": "hex"},
	]))
	assert_false(st.concentration.has(PID))
	assert_has(st.log_lines, "Tess makes a concentration check: 4 vs DC 10, fails.")
	assert_has(st.log_lines, "Tess loses concentration on Hex (taking damage).")
	assert_eq(st.status_tags(GOBLIN).size(), 0)


func test_extra_attack_counter_and_action_surge() -> void:
	var st := _fight(_sheet("fighter", 5))
	st.apply(Messages.make_result(Messages.EXPLORE_STATE, {"tick": 2, "entities": []}))  # no-op for combatants
	assert_eq(st.attacks_per_action(), 2)
	assert_eq(st.attack_counter_text(), "Attack 1/2")
	st.apply(_events([{"kind": "moved", "actor": GOBLIN, "from": [7, 3], "to": [5, 3]}]))
	assert_true(st.can_attack(), "the goblin is adjacent")
	st.apply(_events([_attack_ev(PID, GOBLIN)]))
	assert_true(st.action_used)
	assert_eq(st.attacks_remaining, 1)
	assert_eq(st.attack_counter_text(), "Attack 2/2")
	assert_true(st.can_attack(), "Extra Attack: a second roll")
	assert_eq(st.attack_error(GOBLIN), "")
	st.apply(_events([_attack_ev(PID, GOBLIN)]))
	assert_eq(st.attacks_remaining, 0)
	assert_false(st.can_attack())
	assert_eq(st.attack_counter_text(), "")
	var surge := {}
	for e in st.feature_entries():
		if str(e["id"]) == "action_surge":
			surge = e
	assert_eq(str(surge.get("cost", "")), "free")
	assert_eq(str(surge.get("error", "?")), "")
	var intent := st.begin_feature("action_surge")
	assert_eq(intent.get("feature"), "action_surge")
	st.apply(_events([{"kind": "feature_used", "actor": PID, "feature": "action_surge", "target": PID, "remaining": 0}]))
	assert_false(st.action_used, "Action Surge gives the action back")
	assert_false(st.bonus_action_used, "and costs nothing")
	assert_eq(st.sheet.class_resource("action_surge"), 0)
	assert_eq(st.attack_counter_text(), "Attack 1/2")
	assert_has(st.feature_error("action_surge"), "no uses left")


func test_monk_ki_features_flurry_and_stunning_strike() -> void:
	var st := _fight(_sheet("monk", 5))
	var ki := st.sheet.class_resource("ki")
	assert_eq(ki, 5)
	assert_has(st.resources_text(), "Ki 5/5")
	st.apply(_events([{"kind": "moved", "actor": GOBLIN, "from": [7, 3], "to": [5, 3]}]))
	assert_has(st.feature_error("flurry_of_blows"), "Attack action first")
	st.set_attack_option("stun", true)
	var melee := st.attack_intent(GOBLIN, 0)
	assert_eq(melee.get("stun"), true, "Stunning Strike rides on the melee attack")
	assert_eq(Messages.validate_intent(melee), "")
	st.apply(_events([_attack_ev(PID, GOBLIN),
		{"kind": "feature_used", "actor": PID, "feature": "stunning_strike", "target": GOBLIN, "remaining": 4}]))
	assert_eq(st.sheet.class_resource("ki"), 4, "stunning_strike remaining is ki")
	assert_false(bool(st.attack_options["stun"]), "stun is one-shot")
	st.apply(_events([{"kind": "feature_used", "actor": PID, "feature": "flurry_of_blows", "target": PID, "remaining": 3}]))
	assert_eq(st.sheet.class_resource("ki"), 3)
	assert_true(st.bonus_action_used)
	assert_eq(st.bonus_attacks_remaining, 2)
	assert_eq(st.feature_error(ClientState.FEATURE_FLURRY_STRIKE), "")
	st.set_attack_option("technique", "push")
	assert_eq(st.begin_feature(ClientState.FEATURE_FLURRY_STRIKE), {}, "targets like an attack")
	var strike := st.intent_for_click(Vector2i(5, 3))
	assert_eq(strike.get("bonus"), true)
	assert_eq(strike.get("technique"), "push", "Open Hand Technique on a Flurry strike")
	assert_eq(int(strike.get("attack_index")), st.available_attacks().size() - 1, "unarmed strike")
	st.apply(_events([_attack_ev(PID, GOBLIN, {"bonus": true, "bonus_source": "flurry_of_blows", "attack_name": "Unarmed Strike"}),
		{"kind": "feature_used", "actor": PID, "feature": "open_hand_technique", "target": GOBLIN, "remaining": 0, "mode": "push"},
		{"kind": "pushed", "target": GOBLIN, "source": PID, "from": [5, 3], "to": [7, 3]}]))
	assert_eq(st.bonus_attacks_remaining, 1)
	assert_eq(st.sheet.class_resource("ki"), 3, "the technique spends nothing")
	assert_eq(st.get_entity(GOBLIN)["position"], Vector2i(7, 3), "pushed")
	assert_has(st.log_lines, "Goblin is pushed back.")
	# Patient Defense: a bonus-action Dodge never spends the action.
	st.apply(_events([{"kind": "turn_ended", "actor": PID}, {"kind": "turn_started", "actor": PID, "round": 2}]))
	var pd := st.begin_feature("patient_defense")
	assert_eq(pd.get("feature"), "patient_defense")
	st.apply(_events([{"kind": "feature_used", "actor": PID, "feature": "patient_defense", "target": PID, "remaining": 2},
		{"kind": "dodge", "actor": PID}]))
	assert_false(st.action_used, "Patient Defense is a bonus action")
	assert_true(st.bonus_action_used)
	assert_has(st.status_tags(PID), "dodging")
	st.apply(_events([{"kind": "turn_ended", "actor": PID}, {"kind": "turn_started", "actor": PID, "round": 3}]))
	var step := st.begin_feature("step_of_the_wind", 0, "dash")
	assert_eq(step.get("mode"), "dash")
	var before := st.movement_remaining
	st.apply(_events([{"kind": "feature_used", "actor": PID, "feature": "step_of_the_wind", "target": PID, "remaining": 1, "mode": "dash"},
		{"kind": "dash", "actor": PID}]))
	assert_eq(st.movement_remaining, before + st.speed_tiles())
	assert_false(st.action_used, "Step of the Wind dashes as a bonus action")


func test_paladin_smite_option_and_slot_update() -> void:
	var st := _fight(_sheet("paladin", 2))
	assert_has(st.attack_option_kinds(), "smite")
	st.apply(_events([{"kind": "moved", "actor": GOBLIN, "from": [7, 3], "to": [5, 3]}]))
	assert_eq(st.smite_levels(), [1] as Array[int])
	st.set_attack_option("smite", 1)
	var intent := st.attack_intent(GOBLIN, 0)
	assert_eq(int(intent.get("smite", 0)), 1)
	assert_eq(Messages.validate_intent(intent), "")
	var slots := st.sheet.slots_left(1)
	st.apply(_events([_attack_ev(PID, GOBLIN),
		{"kind": "damage", "target": GOBLIN, "amount": 14, "type": "slashing", "hp_after": 0, "dropped": true, "died": true,
			"extra": [{"source": "divine_smite", "amount": 9, "type": "radiant"}]},
		{"kind": "feature_used", "actor": PID, "feature": "divine_smite", "target": GOBLIN, "remaining": slots - 1}]))
	assert_eq(st.sheet.slots_left(1), slots - 1, "the smite slot level comes from the intent")
	assert_eq(int(st.attack_options["smite"]), 0, "smite is one-shot")
	assert_has(st.log_lines, "Tess uses Divine Smite on Goblin.")
	# A ranged attack never smites.
	st.set_attack_option("smite", 1)
	var thrown := -1
	for i in range(st.available_attacks().size()):
		if ClientState.is_ranged_attack(st.get_attack(i)):
			thrown = i
	if thrown >= 0:
		assert_false(st.attack_option_fields(thrown, false).has("smite"))


func test_barbarian_reckless_rage_and_frenzy() -> void:
	var st := _fight(_sheet("barbarian", 3))
	assert_true(st.sheet.has_feature("frenzy"), "the Berserker path at level 3")
	st.apply(_events([{"kind": "moved", "actor": GOBLIN, "from": [7, 3], "to": [5, 3]}]))
	var modes: Array = []
	for e in st.feature_entries():
		if str(e["id"]) == "rage":
			modes = e["modes"]
	assert_eq(modes, ["rage", "frenzy"])
	var rage := st.begin_feature("rage", 0, "frenzy")
	assert_eq(rage.get("frenzy"), true)
	st.apply(_events([{"kind": "feature_used", "actor": PID, "feature": "rage", "target": PID, "remaining": 2},
		{"kind": "effect_applied", "source": PID, "target": PID, "effect": "rage"},
		{"kind": "effect_applied", "source": PID, "target": PID, "effect": "frenzy"}]))
	assert_eq(st.sheet.class_resource("rage"), 2)
	assert_has(st.status_tags(PID), "frenzied")
	st.set_attack_option("reckless", true)
	var first := st.attack_intent(GOBLIN, 0)
	assert_eq(first.get("reckless"), true, "Reckless Attack on the first melee attack")
	st.apply(_events([{"kind": "effect_applied", "source": PID, "target": PID, "effect": "reckless_attack"}, _attack_ev(PID, GOBLIN)]))
	assert_false(st.attack_option_fields(0, false).has("reckless"), "only the first attack of the turn")
	assert_has(st.feature_error(ClientState.FEATURE_FRENZY_ATTACK), "bonus action already used", "raging took the bonus action")
	st.apply(_events([{"kind": "turn_ended", "actor": PID}, {"kind": "turn_started", "actor": PID, "round": 2}]))
	assert_false(st.status_tags(PID).has("reckless"), "Reckless Attack ends at the next turn")
	assert_eq(st.feature_error(ClientState.FEATURE_FRENZY_ATTACK), "", "Frenzy from the next turn")
	st.apply(_events([{"kind": "effect_ended", "target": PID, "effect": "rage"}]))
	assert_false(st.status_tags(PID).has("frenzied"), "frenzy ends with the rage")


func test_sorcerer_metamagic_font_of_magic_and_twinned() -> void:
	var st := _fight(_sheet("sorcerer", 3))
	assert_false(st.sheet.metamagic.is_empty(), "metamagic at level 3")
	st.sheet.metamagic = ["quickened_spell", "twinned_spell"] as Array[String]
	st.sheet.class_resources["sorcery_points"] = 3
	var opts := st.metamagic_options("fire_bolt")
	assert_eq(opts.size(), 2)
	var quick: Array[String] = ["quickened_spell"]
	assert_eq(st.metamagic_error("fire_bolt", quick), "")
	assert_eq(st.begin_cast("fire_bolt", 0, quick), {}, "targeting")
	var cast := st.intent_for_click(Vector2i(7, 3))
	assert_eq(cast.get("metamagic"), ["quickened_spell"])
	assert_eq(Messages.validate_intent(cast), "")
	st.apply(_events([{"kind": "cast", "actor": PID, "spell": "fire_bolt", "target": GOBLIN, "slot_level": 0, "metamagic": ["quickened_spell"]}]))
	assert_true(st.bonus_action_used, "Quickened: a bonus action")
	assert_false(st.action_used)
	assert_eq(st.sheet.class_resource("sorcery_points"), 1)
	assert_has(st.metamagic_error("fire_bolt", quick), "sorcery points")
	# Twinned: two clicks.
	var twin: Array[String] = ["twinned_spell"]
	st.begin_cast("fire_bolt", 0, twin)
	assert_eq(st.intent_for_click(Vector2i(7, 3)), {}, "first target stored")
	assert_has(st.hint, "second")
	var twinned := st.intent_for_click(Vector2i(8, 5))
	assert_eq(twinned.get("target"), GOBLIN)
	assert_eq(twinned.get("twin_target"), RAT)
	assert_eq(Messages.validate_intent(twinned), "")
	var area_twin: Array[String] = ["twinned_spell"]
	assert_has(st.metamagic_error("burning_hands", area_twin), "single-target")
	# Font of Magic (next turn: the bonus action is free again): create a slot
	# from points, convert a slot back.
	st.apply(_events([{"kind": "turn_ended", "actor": PID}, {"kind": "turn_started", "actor": PID, "round": 2}]))
	var options := st.font_of_magic_options()
	assert_false(options.is_empty())
	assert_has(str(options[0]["error"]), "needs 2 sorcery points", "1 point left")
	st.sheet.class_resources["sorcery_points"] = 2
	var create := st.begin_feature("font_of_magic", 0, "create_slot", 1)
	assert_eq(create.get("mode"), "create_slot")
	assert_eq(int(create.get("slot_level")), 1)
	var slots := st.sheet.slots_left(1)
	st.apply(_events([{"kind": "feature_used", "actor": PID, "feature": "font_of_magic", "target": PID, "remaining": 0,
		"mode": "create_slot", "slot_level": 1}]))
	assert_eq(st.sheet.slots_left(1), slots + 1)
	assert_eq(st.sheet.class_resource("sorcery_points"), 0)
	st.apply(_events([{"kind": "feature_used", "actor": PID, "feature": "font_of_magic", "target": PID, "remaining": 2,
		"mode": "convert_slot", "slot_level": 2}]))
	assert_eq(st.sheet.class_resource("sorcery_points"), 2)
	assert_has(st.resources_text(), "Sorcery points 2/3")


func test_area_spells_preview_point_and_event() -> void:
	var sheet := _sheet("wizard", 3)
	assert_true(sheet.spells_known.has("burning_hands"))
	if not sheet.spells_prepared.has("burning_hands"):
		sheet.spells_prepared.append("burning_hands")
	if not sheet.spells_prepared.has("thunderwave"):
		sheet.spells_known.append("thunderwave")
		sheet.spells_prepared.append("thunderwave")
	sheet.spells_known.append("shatter")
	sheet.spells_prepared.append("shatter")
	var st := _fight(sheet)
	assert_eq(st.begin_cast("burning_hands", 1), {}, "a cone needs an aim")
	assert_true(bool(st.targeting.get("area", false)))
	assert_has(st.hint, "cone")
	assert_false(st.range_tiles().is_empty(), "the cone's reach is tinted")
	var preview := st.area_preview(Vector2i(7, 3))
	assert_eq(str(preview["error"]), "")
	assert_true((preview["tiles"] as Array).has(Vector2i(5, 3)), "the cone starts next to the caster")
	assert_false((preview["tiles"] as Array).has(Vector2i(4, 3)), "not on the caster")
	assert_has(preview["affected"], GOBLIN, "3 tiles east")
	assert_false((preview["affected"] as Array).has(ALLY), "the ally stands behind")
	assert_ne(str(st.area_preview(Vector2i(4, 3))["error"]), "", "aim away from yourself")
	var intent := st.intent_for_click(Vector2i(7, 3))
	assert_eq(intent.get("type"), Messages.CAST)
	assert_eq(intent.get("point"), [7, 3])
	assert_eq(int(intent.get("slot_level")), 1)
	assert_eq(Messages.validate_intent(intent), "")
	st.cancel_targeting()
	# A ranged sphere: point in range and sight; the caster is caught too, the
	# evoker's ally is sculpted out (Sculpt Spells chooses other creatures).
	st.begin_cast("shatter", 2)
	var sphere := st.area_preview(Vector2i(3, 2))
	assert_has(sphere["affected"], PID, "the caster is not spared from a ranged sphere")
	assert_has(sphere["affected"], UNDEAD)
	assert_eq(sphere["sculpted"], [ALLY] as Array[String])
	st.cancel_targeting()
	# Self-centred cube: cast at once, no point.
	var wave := st.begin_cast("thunderwave", 1)
	assert_eq(wave.get("spell"), "thunderwave")
	assert_false(wave.has("point"))
	st.apply(_events([
		{"kind": "cast", "actor": PID, "spell": "burning_hands", "target": "", "slot_level": 1, "point": [7, 3]},
		{"kind": "area_effect", "caster": PID, "spell": "burning_hands", "point": [7, 3], "shape": "cone", "size_tiles": 3,
			"affected": [GOBLIN], "sculpted": []},
		{"kind": "save", "actor": PID, "target": GOBLIN, "ability": "DEX", "dc": 13, "natural": 4, "total": 6, "success": false},
		{"kind": "damage", "target": GOBLIN, "amount": 9, "type": "fire", "hp_after": 0, "dropped": true, "died": true, "spell": "burning_hands"},
	]))
	assert_true(st.action_used)
	assert_eq(st.area_serial, 1)
	assert_eq(st.last_area["point"], Vector2i(7, 3))
	assert_has(st.log_lines, "Tess casts Burning Hands (level 1 slot).")
	assert_has(st.log_lines, "Tess's Burning Hands (cone) catches Goblin.")


func test_evoker_sculpts_allies_out_of_its_areas() -> void:
	var sheet := _sheet("wizard", 2)
	assert_true(sheet.has_feature("sculpt_spells"), "School of Evocation at level 2")
	sheet.spells_known.append("shatter")
	sheet.spells_prepared.append("shatter")
	sheet.spell_slots_max = [3, 2] as Array[int]
	sheet.spell_slots = [3, 2] as Array[int]
	var st := _fight(sheet)
	st.begin_cast("shatter", 2)
	var preview := st.area_preview(Vector2i(3, 2))
	assert_has(preview["sculpted"], ALLY)
	assert_false((preview["affected"] as Array).has(ALLY), "sculpted allies are left out")
	var intent := st.intent_for_click(Vector2i(3, 2))
	assert_has(intent.get("sculpt", []), ALLY)
	assert_eq(Messages.validate_intent(intent), "")


func test_reactions_destroyed_and_pact_weapon() -> void:
	var st := _fight(_sheet("warlock", 3))
	st.apply(_events([
		{"kind": "damage_reduced", "actor": PID, "feature": "uncanny_dodge", "source": GOBLIN, "amount": 3},
		{"kind": "destroyed", "source": ALLY, "target": UNDEAD, "feature": "destroy_undead"},
	]))
	assert_true(st.reaction_used)
	assert_has(st.log_lines, "Tess uses Uncanny Dodge: 3 damage avoided.")
	assert_true(bool(st.get_entity(UNDEAD)["dead"]))
	assert_has(st.log_lines, "Skeleton is destroyed by Ally's Destroy Undead!")
	var before := st.available_attacks().size()
	if st.has_usable_feature("pact_weapon"):
		st.apply(_events([{"kind": "feature_used", "actor": PID, "feature": "pact_weapon", "target": PID, "remaining": 0},
			{"kind": "effect_applied", "source": PID, "target": PID, "effect": "pact_weapon", "attack_index": before}]))
		assert_eq(st.available_attacks().size(), before + 1, "the pact weapon is a new attack index")
		assert_true(st.action_used, "summoning takes the action")
		assert_has(st.feature_error("pact_weapon"), "action already used")


func test_resources_pact_slots_and_short_rest_recovery() -> void:
	var warlock := _fight(_sheet("warlock", 2))
	assert_has(warlock.slots_text(), "Pact slots: 1st")
	assert_has(warlock.slots_text(), "(short rest)")
	var bard := ClientState.new(PID)
	bard.apply(Messages.make_result(Messages.CHARACTER_STATE, {"sheet": _sheet("bard").to_dict()}))
	assert_has(bard.resources_text(), "Bardic Inspiration")
	assert_has(bard.resources_text(), "(d6)")
	var cleric := ClientState.new(PID)
	cleric.apply(Messages.make_result(Messages.CHARACTER_STATE, {"sheet": _sheet("cleric", 2).to_dict()}))
	assert_has(cleric.resources_text(), "Channel Divinity 1/1")
	var paladin := ClientState.new(PID)
	paladin.apply(Messages.make_result(Messages.CHARACTER_STATE, {"sheet": _sheet("paladin").to_dict()}))
	assert_has(paladin.resources_text(), "Lay on Hands 5/5")
	# Arcane Recovery on the stairs.
	var wiz_sheet := _sheet("wizard", 3)
	wiz_sheet.spell_slots[1] = 0
	var wiz := ClientState.new(PID)
	wiz.apply(Messages.make_result(Messages.FLOOR_LOADED, {"floor": _floor_dict()}))
	wiz.apply(Messages.make_result(Messages.CHARACTER_STATE, {"sheet": wiz_sheet.to_dict()}))
	wiz.apply(Messages.make_result(Messages.EXPLORE_STATE, {"tick": 1, "entities": [{"id": PID, "kind": "player", "position": [10, 5]}]}))
	var rec := wiz.slot_recovery()
	assert_eq(str(rec.get("feature", "")), "arcane_recovery")
	assert_eq(rec.get("levels", []), [2] as Array[int])
	assert_true(wiz.can_short_rest(), "full HP, but a slot to recover")
	var rest := wiz.short_rest_intent(0, true)
	assert_eq(rest.get("recover_slots"), true)
	assert_eq(Messages.validate_intent(rest), "")


func test_cleric_channel_divinity_and_preserve_life() -> void:
	var st := _fight(_sheet("cleric", 2))
	assert_true(st.has_usable_feature("turn_undead"))
	assert_true(st.has_usable_feature("preserve_life"))
	var alloc := st.preserve_life_allocations()
	assert_eq(alloc, {ALLY: 10}, "up to half of 30 hp, within 5 x level 2")
	var intent := st.begin_feature("preserve_life")
	assert_eq(intent.get("allocations"), {ALLY: 10})
	assert_eq(Messages.validate_intent(intent), "")
	st.apply(_events([{"kind": "feature_used", "actor": PID, "feature": "preserve_life", "target": PID, "remaining": 0}]))
	assert_true(st.action_used, "Channel Divinity takes the action")
	assert_eq(st.sheet.class_resource("channel_divinity"), 0)
	assert_has(st.feature_error("turn_undead"), "channel divinity")


func test_stand_intent_and_inventory_weapon_properties() -> void:
	var st := _fight(_sheet("fighter"))
	var stand := st.stand_intent()
	assert_eq(stand.get("type"), Messages.STAND)
	assert_eq(Messages.validate_intent(stand), "")
	var props := st.weapon_properties("longsword")
	assert_has(props, "versatile (1d10)")
	assert_eq(st.weapon_properties("potion_of_healing"), [] as Array[String])
	var rows := st.inventory_rows()
	var found := false
	for r in rows:
		if str(r["item"]) == "longsword":
			found = true
			assert_has(r["properties"], "versatile (1d10)")
	assert_true(found)


func test_reaction_policy_toggles() -> void:
	var st := _fight(_sheet("rogue", 5))
	assert_true(st.reacts_to("creature_hit_me"), "auto by default")
	var intent := st.reaction_policy_intent("creature_hit_me", false)
	assert_eq(intent.get("policy"), {"creature_hit_me": "never"})
	assert_eq(Messages.validate_intent(intent), "")
	st.apply(Messages.make_result(Messages.CHARACTER_STATE, {"sheet": st.sheet.to_dict(), "reaction_policy": {"creature_hit_me": "never"}}))
	assert_false(st.reacts_to("creature_hit_me"))
	st.apply(_events([{"kind": "reaction_used", "actor": PID, "reaction": "uncanny_dodge", "trigger": "creature_hit_me"}]))
	assert_true(st.reaction_used)
	assert_has(st.log_lines, "Tess reacts: Uncanny Dodge.")
	assert_eq(st.reaction_policy_intent("creature_left_reach", false).get("policy"), {"creature_hit_me": "never", "creature_left_reach": "never"},
		"the other entries are kept")

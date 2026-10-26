extends TestCase
## ClientState out of combat: spell entries and casts while exploring,
## OUT_OF_COMBAT_EVENTS, the companions line and dismissal, summons as allies
## in a fight, and the reaction entries of the Reactions panel.

const PID := "p1"
const GOBLIN := "z1_goblin_0"


func _floor_dict() -> Dictionary:
	return {
		"schema_version": 1, "id": "ooc_floor", "display_name": "Study",
		"rows": ["##########", "#........#", "#........#", "#........#", "##########"],
		"arrival": [1, 1], "stairs": [8, 3],
		"encounter_zones": [{"id": "z1", "rect": [5, 1, 4, 3], "monster_ids": ["goblin"], "spawn_points": [[7, 2]]}],
	}


func _sheet(class_id: String) -> CharacterSheet:
	var d := CharacterDraft.new()
	d.character_name = "Ilsa"
	d.set_class(ContentLoader.load_classes()[class_id])
	d.auto_assign()
	return d.build_sheet()


func _state(sheet: CharacterSheet) -> ClientState:
	var st := ClientState.new(PID)
	st.apply(Messages.make_result(Messages.FLOOR_LOADED, {"floor": _floor_dict(), "entity_id": PID}))
	st.apply(Messages.make_result(Messages.CHARACTER_STATE, {"sheet": sheet.to_dict()}))
	st.apply(Messages.make_result(Messages.EXPLORE_STATE, {"entities": [
		{"id": PID, "kind": "player", "position": [1, 1]},
		{"id": GOBLIN, "kind": "monster", "position": [7, 2], "name": "Goblin", "monster_id": "goblin"},
	], "tick": 1}))
	return st


func _wizard() -> CharacterSheet:
	var s := _sheet("wizard")
	s.spells_known.append("find_familiar")
	s.spells_prepared.append("find_familiar")
	return s


func _entry(st: ClientState, spell_id: String) -> Dictionary:
	for e in st.spell_entries():
		if str(e["id"]) == spell_id:
			return e
	return {}


func _fight(st: ClientState) -> void:
	st.apply(Messages.make_result(Messages.ENCOUNTER_EVENTS, {"encounter_id": "z1", "zone_id": "z1", "events": [
		{"kind": "combatant_joined", "id": PID, "initiative": 15, "position": [5, 1]},
		{"kind": "combatant_joined", "id": GOBLIN, "initiative": 5, "position": [7, 2]},
		{"kind": "combatant_joined", "id": "p1_cat_1", "name": "Cat", "team": 0, "initiative": 15, "position": [5, 2],
			"hp": 2, "max_hp": 2, "owner": PID},
		{"kind": "summoned", "caster": PID, "spell": "find_familiar", "id": "p1_cat_1", "monster": "cat", "position": [5, 2]},
		{"kind": "encounter_started", "order": [PID, "p1_cat_1", GOBLIN]},
		{"kind": "round_started", "round": 1},
		{"kind": "turn_started", "actor": PID, "round": 1},
	]}))


func test_spell_entries_and_casts_while_exploring() -> void:
	var st := _state(_wizard())
	assert_eq(st.mode, ClientState.Mode.EXPLORING)
	var familiar := _entry(st, "find_familiar")
	assert_true(bool(familiar["out_of_combat"]))
	assert_eq(str(familiar["casting_time"]), "1_hour")
	assert_eq(str(familiar["casting_time_text"]), "1 hour (ritual)")
	assert_true(bool(familiar["ritual"]))
	assert_eq(str(familiar["error"]), "", "castable while exploring")
	var bolt := _entry(st, "fire_bolt")
	assert_false(bool(bolt["out_of_combat"]))
	assert_eq(str(bolt["casting_time_text"]), "1 action")
	assert_eq(str(bolt["error"]), "only in a fight")
	assert_eq(st.cast_error("mage_armor"), "", "unarmored wizard")
	var intent := st.begin_cast("find_familiar", 0, [], {"form": "cat"})
	assert_false(st.is_targeting(), "no targeting out of combat")
	assert_eq(intent.get("type"), Messages.CAST)
	assert_eq(intent.get("target"), PID)
	assert_eq(int(intent.get("slot_level")), 1)
	assert_eq(intent.get("form"), "cat")
	assert_eq(Messages.validate_intent(intent), "")
	assert_eq(st.begin_cast("fire_bolt"), {})
	assert_eq(st.hint, "only in a fight")
	st.sheet.spells_prepared.append("cure_wounds")
	assert_eq(st.cast_error("cure_wounds"), "you are at full health")
	st.sheet.current_hp -= 1
	assert_eq(st.cast_error("cure_wounds"), "")
	st.sheet.use_spell_slot(1)
	st.sheet.use_spell_slot(1)
	assert_eq(st.cast_error("find_familiar"), "no spell slot left")
	st.sheet.spells_prepared.append("raise_dead")
	assert_has(st.cast_error("raise_dead"), "fallen ally")
	# In a fight the old rules apply again.
	_fight(st)
	st.sheet.spell_slots[0] = 2
	assert_eq(st.cast_error("find_familiar"), "takes too long to cast in combat")


func test_out_of_combat_events_and_the_companions_line() -> void:
	var st := _state(_wizard())
	st.drain_log()
	st.apply(Messages.make_result(Messages.OUT_OF_COMBAT_EVENTS, {"entity_id": "p2", "spell": "find_familiar",
		"events": [{"kind": "cast", "actor": "p2", "spell": "find_familiar"}]}))
	assert_eq(st.drain_log(), [] as Array[String], "another player's casts are not ours")
	st.apply(Messages.make_result(Messages.OUT_OF_COMBAT_EVENTS, {"entity_id": PID, "spell": "find_familiar", "slot_level": 1,
		"events": [
			{"kind": "cast", "actor": PID, "spell": "find_familiar", "target": PID, "slot_level": 1, "casting_time": "1_hour", "ritual": true},
			{"kind": "companion_summoned", "caster": PID, "spell": "find_familiar", "monster": "cat", "count": 1, "companion_ids": ["c1"]},
			{"kind": "heal", "target": PID, "amount": 5, "hp_after": 9},
			{"kind": "temp_hp", "target": PID, "amount": 6, "temp_hp_after": 6},
			{"kind": "revived", "target": PID, "hp": 1},
			{"kind": "restored", "target": PID, "conditions_removed": ["poisoned"], "exhaustion": 0},
			{"kind": "buff", "target": PID, "buff": "mage_armor", "ac": 15},
		]}))
	var lines := st.drain_log()
	assert_eq(lines.size(), 7, str(lines))
	assert_eq(lines[0], "Ilsa casts Find Familiar (level 1 slot, 1 hour (ritual), done at once).")
	assert_eq(lines[1], "Cat stands at your side: it will join your next fight.")
	assert_eq(lines[2], "Ilsa regains 5 HP (9 HP).")
	assert_eq(lines[3], "Ilsa gains 6 temporary HP.")
	assert_eq(lines[4], "Ilsa returns to life with 1 HP!")
	assert_eq(lines[5], "Ilsa is restored: no longer poisoned (exhaustion 0).")
	assert_eq(lines[6], "Ilsa is protected by Mage Armor (AC 15).")
	assert_eq(st.companions_text(), "", "the sheet changes with CHARACTER_STATE")
	var sheet := st.sheet
	sheet.companions = [{"id": "c1", "monster": "cat", "spell": "find_familiar", "hp": 1}] as Array[Dictionary]
	st.apply(Messages.make_result(Messages.CHARACTER_STATE, {"sheet": sheet.to_dict(), "spell_cast": "find_familiar"}))
	var cat: MonsterDefinition = ContentLoader.cache()["monsters"]["cat"]
	assert_eq(st.companions_text(), "Companions: Cat 1/%d HP" % cat.hit_points_avg)
	var entries := st.companion_entries()
	assert_eq(entries.size(), 1)
	assert_eq(str(entries[0]["id"]), "c1")
	assert_eq(str(entries[0]["spell"]), "find_familiar")
	assert_true(st.can_dismiss_companion())
	var dismiss := st.dismiss_companion_intent("c1")
	assert_eq(dismiss.get("type"), Messages.DISMISS_COMPANION)
	assert_eq(dismiss.get("companion_id"), "c1")
	assert_eq(Messages.validate_intent(dismiss), "")
	_fight(st)
	assert_false(st.can_dismiss_companion(), "not in a fight")
	st.drain_log()
	sheet.companions = [] as Array[Dictionary]
	st.apply(Messages.make_result(Messages.CHARACTER_STATE, {"sheet": sheet.to_dict(), "companion_dismissed": {"id": "c1", "monster": "cat"}}))
	assert_has(st.drain_log(), "Ilsa dismisses the Cat.")
	assert_eq(st.companions_text(), "")


func test_summons_in_a_fight_are_allies() -> void:
	var st := _state(_wizard())
	_fight(st)
	var cat := st.get_entity("p1_cat_1")
	assert_eq(str(cat["kind"]), ClientState.KIND_ALLY)
	assert_eq(str(cat["owner"]), PID)
	assert_eq(str(cat["monster_id"]), "cat")
	assert_eq(st.display_name("p1_cat_1"), "Cat")
	assert_true(st.order.has("p1_cat_1"))
	assert_eq(st.hostile_at(Vector2i(5, 2)), "", "never a hostile")
	assert_false(st.adjacent_hostiles().has("p1_cat_1"))
	assert_has(st.log_lines, "Ilsa's Cat appears.")


func test_reaction_entries_name_the_characters_reactions() -> void:
	assert_true(ClientState.reaction_policy_supported())
	var s := _wizard()
	s.spells_known.append("shield")
	s.spells_prepared.append("shield")
	var st := _state(s)
	var entries := st.reaction_entries()
	assert_eq(entries.size(), Messages.REACTION_TRIGGERS.size())
	var by_trigger := {}
	for e in entries:
		by_trigger[str(e["trigger"])] = e
	var reach: Dictionary = by_trigger["creature_left_reach"]
	assert_eq(str(reach["label"]), "A creature leaves my reach")
	assert_eq(str((reach["reactions"] as Array)[0]["name"]), "Opportunity attack")
	var hit: Dictionary = by_trigger["creature_hit_me"]
	assert_eq((hit["reactions"] as Array).size(), 1)
	assert_eq(str((hit["reactions"] as Array)[0]["id"]), "shield")
	assert_eq((by_trigger["spell_cast_in_range"]["reactions"] as Array).size(), 0, "no Counterspell at level 1")
	assert_true(bool(hit["on"]))
	# A reaction key wins over its trigger; toggling the trigger drops it.
	var only_shield := st.reaction_toggle_intent("creature_hit_me", "shield", false)
	assert_eq(only_shield["policy"], {"shield": "never"})
	st.apply(Messages.make_result(Messages.CHARACTER_STATE, {"sheet": st.sheet.to_dict(), "reaction_policy": {"shield": "never"}}))
	assert_true(st.reacts_to("creature_hit_me"))
	assert_false(st.reacts_with("creature_hit_me", "shield"))
	assert_eq(st.reaction_toggle_intent("creature_hit_me", "", true)["policy"], {"creature_hit_me": "auto"})
	# Features and fighting styles count too.
	var rogue := _sheet("rogue")
	rogue.features.append("uncanny_dodge")
	var rs := _state(rogue)
	assert_true(rs.has_reaction("uncanny_dodge"))
	assert_false(rs.has_reaction("shield"))

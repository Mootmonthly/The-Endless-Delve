extends TestCase
## Round C item 1: OutOfCombat.castable / events / companion ids / rituals,
## Reactions.BY_TRIGGER and summons' combatant_joined "monster".

const SURE := {"name": "Sure", "kind": "melee", "to_hit": 100, "damage": "4", "damage_type": "slashing", "ability": "STR"}

var content: Dictionary


func before_each() -> void:
	content = CoreFixtures.content()
	for d: Dictionary in [
		{"id": "owl", "display_name": "Owl", "creature_type": "beast", "challenge_rating": 0.0, "hit_points": 1, "hit_dice": "1d4-1"},
		{"id": "skeleton", "display_name": "Skeleton", "creature_type": "undead", "challenge_rating": 0.25, "hit_points": 13, "hit_dice": "2d8+4"},
		{"id": "wolf", "display_name": "Wolf", "creature_type": "beast", "challenge_rating": 0.25, "hit_points": 11, "hit_dice": "2d8+2"},
	]:
		var base := {"schema_version": 1, "armor_class": 12, "speed": 30, "abilities": {"STR": 12, "DEX": 14, "CON": 12, "INT": 3, "WIS": 12, "CHA": 6},
			"xp": 50, "attacks": [{"name": "Bite", "kind": "melee", "to_hit": 100, "damage": "3", "damage_type": "piercing"}]}
		base.merge(d, true)
		var m := MonsterDefinition.from_dict(base)
		content["monsters"][m.id] = m
	for d: Dictionary in [
		{"id": "find_familiar", "display_name": "Find Familiar", "level": 1, "casting_time": "1_hour", "range_ft": 10, "ritual": true, "effect": {"type": "unsupported"}},
		{"id": "animate_dead", "display_name": "Animate Dead", "level": 3, "casting_time": "1_minute", "range_ft": 10, "effect": {"type": "unsupported"}},
		{"id": "prayer_of_healing", "display_name": "Prayer of Healing", "level": 2, "casting_time": "10_minutes", "range_ft": 30, "effect": {"type": "unsupported"}},
		{"id": "conjure_animals", "display_name": "Conjure Animals", "level": 3, "range_ft": 60, "concentration": true, "effect": {"type": "unsupported"}},
	]:
		var sdef := CoreFixtures.spell(d)
		assert_not_null(sdef, d["id"])
		content["spells"][sdef.id] = sdef


func _spell(id: String) -> SpellDefinition:
	return content["spells"][id]


func test_castable_out_of_combat() -> void:
	assert_true(OutOfCombat.castable(_spell("find_familiar")), "companion summon")
	assert_true(OutOfCombat.castable(_spell("prayer_of_healing")), "heal")
	assert_true(OutOfCombat.castable(_spell("mage_armor")), "mage armor")
	assert_true(OutOfCombat.castable(_spell("cure_wounds")))
	assert_false(OutOfCombat.castable(_spell("fire_bolt")), "attack spells need a fight")
	assert_false(OutOfCombat.castable(_spell("conjure_animals")), "a fight-only summon")
	assert_false(OutOfCombat.castable(null))


func test_cast_returns_events_keyed_per_target() -> void:
	var s := CoreFixtures.caster("Cleric", Ability.Type.WIS, ["prayer_of_healing"], 40)
	s.current_hp = 10
	var ally := CoreFixtures.sheet("Ally", 40)
	ally.current_hp = 5
	var targets: Array[CharacterSheet] = [s, ally]
	var r := OutOfCombat.cast(s, "prayer_of_healing", content, Rng.new(3), targets, {"target_ids": ["p1", "p2"]})
	assert_true(r["ok"] == true, str(r["error"]))
	var evs: Array = r["events"]
	assert_eq(str(evs[0]["kind"]), "cast")
	assert_eq([evs[0]["actor"], evs[0]["target"], evs[0]["slot_level"], evs[0]["ritual"]], ["p1", "p1", 2, false])
	var heals := CoreFixtures.events_of(evs, "heal")
	assert_eq(heals.size(), 2)
	assert_eq([heals[0]["target"], heals[0]["target_index"], heals[1]["target"]], ["p1", 0, "p2"])
	assert_eq(heals[1]["hp_after"], ally.current_hp)
	assert_true((r["result"] as Dictionary).has("healed"), "the result shape is kept")
	assert_eq((r["result"]["healed_by_target"] as Dictionary).keys().size(), 2)
	# Without ids, targets are keyed by index.
	s.current_hp = 10
	r = OutOfCombat.cast(s, "prayer_of_healing", content, Rng.new(3), targets)
	assert_eq(CoreFixtures.events_of(r["events"], "heal")[1]["target"], "1")


func test_companion_ids_are_minted_by_the_sheet() -> void:
	var s := CoreFixtures.caster("Necro", Ability.Type.INT, ["animate_dead", "find_familiar"], 40)
	s.spell_slots_max = [2, 2, 2, 2]
	s.spell_slots = [2, 2, 2, 2]
	s.companions = [{"monster": "wolf", "spell": "x", "hp": 3}]
	var r := OutOfCombat.cast(s, "animate_dead", content, Rng.new(1), [], {"form": "skeleton", "slot_level": 4, "caster_id": "p1"})
	assert_true(r["ok"] == true, str(r["error"]))
	var ids: Array = []
	for entry in s.companions:
		ids.append(entry["id"])
	assert_eq(ids, ["c1", "c2", "c3", "c4"], "the old entry is stamped first, three skeletons follow")
	var summoned := CoreFixtures.first_event(r["events"], "companion_summoned")
	assert_eq(summoned["companion_ids"], ["c2", "c3", "c4"])
	assert_eq([summoned["caster"], summoned["count"], summoned["monster"]], ["p1", 3, "skeleton"])
	assert_eq(s.companion_serial, 4)
	var copy := CharacterSheet.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	assert_eq(copy.mint_companion_id(), "c5", "ids are never reused")
	assert_eq(s.companion_by_id("c3")["monster"], "skeleton")


func test_ritual_casting() -> void:
	var wiz := CoreFixtures.caster("Wiz", Ability.Type.INT, [], 30)
	wiz.class_id = "wizard"
	wiz.spells_known = ["find_familiar"]
	var r := OutOfCombat.cast(wiz, "find_familiar", content, Rng.new(1), [], {"form": "owl"})
	assert_false(r["ok"] == true, "not prepared")
	r = OutOfCombat.cast(wiz, "find_familiar", content, Rng.new(1), [], {"form": "owl", "ritual": true})
	assert_true(r["ok"] == true, str(r["error"]))
	assert_eq(r["slot_level"], 0, "a ritual spends no slot")
	assert_eq(wiz.slots_left(1), 2)
	assert_true(r["events"][0]["ritual"] == true)
	var sorc := CoreFixtures.caster("Sorc", Ability.Type.CHA, ["find_familiar"], 30)
	sorc.class_id = "sorcerer"
	assert_false(OutOfCombat.cast(sorc, "find_familiar", content, Rng.new(1), [], {"form": "owl", "ritual": true})["ok"] == true, "no Ritual Casting")
	var cleric := CoreFixtures.caster("Cleric", Ability.Type.WIS, ["prayer_of_healing"], 30)
	cleric.class_id = "cleric"
	assert_false(OutOfCombat.cast(cleric, "prayer_of_healing", content, Rng.new(1), [], {"ritual": true})["ok"] == true, "not a ritual")
	assert_true(OutOfCombat.can_ritual_cast(wiz, _spell("find_familiar")))
	assert_false(OutOfCombat.can_ritual_cast(cleric, _spell("find_familiar")), "a cleric needs it prepared")


func test_reactions_by_trigger_table() -> void:
	assert_has(Reactions.BY_TRIGGER["creature_hit_me"], "shield")
	assert_has(Reactions.BY_TRIGGER["spell_cast_in_range"], "counterspell")
	assert_has(Reactions.BY_TRIGGER["creature_left_reach"], "opportunity_attack")
	assert_eq(Reactions.triggers_of("giant_killer"), ["creature_hit_me", "missed"] as Array[String])
	var s := CoreFixtures.caster("Wiz", Ability.Type.INT, ["shield"], 30)
	s.features = ["uncanny_dodge"]
	var mine := Reactions.for_sheet(s)
	assert_eq(mine["creature_hit_me"], ["shield", "uncanny_dodge"] as Array[String])
	assert_eq(mine["creature_left_reach"], ["opportunity_attack"] as Array[String])
	assert_false(mine.has("ally_hit"))
	for trigger: String in Reactions.BY_TRIGGER.keys():
		for r: Variant in Reactions.BY_TRIGGER[trigger]:
			assert_true(Reactions.SOURCES.has(str(r)), "%s has a source" % str(r))


func test_summon_join_event_names_the_monster() -> void:
	var s := CoreFixtures.caster("Druid", Ability.Type.WIS, ["conjure_animals"], 40)
	s.spell_slots_max = [2, 2, 2]
	s.spell_slots = [2, 2, 2]
	var e := CoreFixtures.duel(s, [SURE], {"gob": [CoreFixtures.sheet("Gob", 50), Vector2i(9, 3), [SURE]]}, content)
	var res := e.submit(CoreFixtures.intent("cast", "hero", {"spell": "conjure_animals", "form": "wolf"}))
	assert_true(res["ok"] == true, str(res["error"]))
	var joined := CoreFixtures.first_event(res["events"], "combatant_joined")
	assert_eq([joined["owner"], joined["monster"]], ["hero", "wolf"])

extends TestCase
## ItemDefinition parsing, inventory helpers, equipment effects on AC and
## attacks, serialization, starter kits.

var content: Dictionary


func before_each() -> void:
	content = CoreFixtures.content()


func test_item_definition_parses_each_kind() -> void:
	var potion := CoreFixtures.item({"id": "p", "display_name": "P", "kind": "consumable", "weight": 0.5, "value_gp": 0.05,
		"use": {"action": "action", "effect": "heal", "dice": "2d4+2", "target": "self"}})
	assert_not_null(potion)
	assert_true(potion.is_usable())
	assert_true(potion.has_implemented_use())
	assert_eq(potion.use_dice, "2d4+2")
	assert_true(potion.stackable, "consumables stack by default")
	assert_eq(potion.value_gp, 0.05)
	var armor: ItemDefinition = content["items"]["chain_mail"]
	assert_eq(armor.armor_base, 16)
	assert_eq(armor.armor_max_dex, 0)
	assert_eq(armor.armor_category, "heavy")
	var shield: ItemDefinition = content["items"]["shield"]
	assert_eq(shield.shield_bonus, 2)
	var bow := CoreFixtures.item({"id": "b", "display_name": "B", "kind": "weapon", "weapon_id": "shortbow", "ammo_id": "arrows"})
	assert_eq(bow.ammo_id, "arrows")
	var salve: ItemDefinition = content["items"]["salve"]
	assert_false(salve.has_implemented_use(), "unknown effects load as data only")


func test_invalid_items_are_rejected() -> void:
	assert_null(ItemDefinition.from_dict({"id": "x", "display_name": "X"}), "kind missing")
	assert_null(CoreFixtures.item({"id": "x", "display_name": "X", "kind": "potion"}), "unknown kind")
	assert_null(CoreFixtures.item({"id": "x", "display_name": "X", "kind": "weapon"}), "weapon without weapon_id")
	assert_null(CoreFixtures.item({"id": "x", "display_name": "X", "kind": "armor"}), "armor without armor block")
	assert_null(CoreFixtures.item({"id": "x", "display_name": "X", "kind": "consumable"}), "consumable without use")
	assert_null(CoreFixtures.item({"id": "x", "display_name": "X", "kind": "consumable", "use": {"action": "free", "effect": "heal", "dice": "1d4"}}), "bad action")
	assert_null(CoreFixtures.item({"id": "x", "display_name": "X", "kind": "consumable", "use": {"action": "action", "effect": "heal", "dice": "lots"}}), "bad dice")


func test_inventory_add_remove_count_and_gold() -> void:
	var s := CharacterSheet.new()
	s.add_item("potion_of_healing", 2)
	s.add_item("potion_of_healing")
	s.add_item("gold", 15)
	s.add_item("nothing", 0)
	assert_eq(s.inventory.size(), 2, "same ids stack into one entry")
	assert_eq(s.count_item("potion_of_healing"), 3)
	assert_true(s.has_item("potion_of_healing", 3))
	assert_false(s.has_item("potion_of_healing", 4))
	assert_eq(s.gold(), 15)
	assert_false(s.remove_item("potion_of_healing", 4, content), "not enough: nothing removed")
	assert_eq(s.count_item("potion_of_healing"), 3)
	assert_true(s.remove_item("potion_of_healing", 3, content))
	assert_eq(s.count_item("potion_of_healing"), 0)
	assert_eq(s.inventory.size(), 1, "empty stacks are dropped")


func test_equip_armor_and_shield_change_ac() -> void:
	var s := CoreFixtures.sheet("A", 10, [10, 14, 10, 10, 10, 10])
	assert_eq(s.armor_class(), 12)
	s.add_item("chain_mail")
	s.add_item("shield")
	s.add_item("scale_mail")
	assert_eq(s.equip("chain_mail", "armor", content), "")
	assert_eq(s.armor_class(), 16, "heavy armor ignores DEX")
	assert_eq(s.equip("shield", "off_hand", content), "")
	assert_eq(s.armor_class(), 18)
	assert_eq(s.equip("scale_mail", "armor", content), "", "swapping armor")
	assert_eq(s.equipped_item("armor"), "scale_mail")
	assert_eq(s.armor_class(), 14 + 2 + 2, "medium armor DEX cap 2, shield")
	assert_eq(s.unequip("off_hand", content), "")
	assert_eq(s.unequip("armor", content), "")
	assert_eq(s.armor_class(), 12)
	assert_eq(s.count_item("chain_mail"), 1, "unequipped items stay carried")


func test_equip_validation() -> void:
	var s := CoreFixtures.sheet("A")
	s.add_item("longsword")
	s.add_item("greataxe")
	s.add_item("shield")
	s.add_item("potion_of_healing")
	assert_ne(s.equip("dagger", "main_hand", content), "", "not carried")
	assert_ne(s.equip("longsword", "belt", content), "", "unknown slot")
	assert_ne(s.equip("potion_of_healing", "main_hand", content), "", "not a weapon")
	assert_ne(s.equip("longsword", "armor", content), "", "not armor")
	assert_ne(s.equip("longsword", "off_hand", content), "", "not light")
	assert_eq(s.equip("shield", "off_hand", content), "")
	assert_ne(s.equip("greataxe", "main_hand", content), "", "two-handed needs the off hand free")
	assert_eq(s.equip("longsword", "main_hand", content), "")
	assert_eq(s.armor_class(), 12, "10 + shield")
	assert_eq(s.unequip("off_hand", content), "")
	assert_eq(s.equip("greataxe", "main_hand", content), "")
	assert_ne(s.equip("shield", "off_hand", content), "", "shield needs a free hand")
	assert_eq(s.equipped_item("main_hand"), "greataxe")


func test_rebuild_attacks_melee_thrown_and_ranged() -> void:
	var s := CoreFixtures.sheet("R", 10, [12, 16, 10, 10, 10, 10])
	s.add_item("shortsword")
	s.add_item("dagger", 3)
	s.add_item("shortbow")
	s.add_item("arrows", 20)
	s.add_item("handaxe", 1)
	assert_eq(s.equip("shortsword", "main_hand", content), "")
	var names: Array[String] = []
	for a in s.attacks:
		names.append(str(a["name"]))
	assert_eq(names, ["Shortsword", "Dagger (thrown)", "Shortbow", "Handaxe (thrown)"])
	var sword := s.attacks[0]
	assert_eq(sword["kind"], "melee")
	assert_eq(sword["to_hit"], 5, "finesse DEX +3, proficiency +2")
	assert_eq(sword["damage"], "1d6+3")
	assert_eq(sword["range_tiles"], [1, 1])
	assert_eq(sword["consumes"], "")
	assert_eq(sword["item"], "shortsword")
	var dagger := s.attacks[1]
	assert_eq(dagger["kind"], "thrown")
	assert_eq(dagger["range_tiles"], [4, 12])
	assert_eq(dagger["consumes"], "dagger")
	var bow := s.attacks[2]
	assert_eq(bow["kind"], "ranged")
	assert_eq(bow["range_tiles"], [16, 64])
	assert_eq(bow["consumes"], "arrows", "ammunition from the weapon's ammo_id")
	assert_eq(bow["ability"], "DEX")
	var axe := s.attacks[3]
	assert_eq(axe["to_hit"], 3, "handaxe is not finesse: STR +1, proficiency +2")
	assert_eq(axe["damage"], "1d6+1")


func test_main_hand_thrown_weapon_and_ranged_main_hand() -> void:
	var s := CoreFixtures.sheet("F", 10, [16, 10, 10, 10, 10, 10])
	s.add_item("handaxe", 2)
	assert_eq(s.equip("handaxe", "main_hand", content), "")
	assert_eq(s.attacks.size(), 2)
	assert_eq(s.attacks[0]["kind"], "melee")
	assert_eq(s.attacks[1]["kind"], "thrown")
	assert_eq(s.attacks[1]["consumes"], "handaxe")
	assert_true(s.remove_item("handaxe", 1, content))
	assert_eq(s.equipped_item("main_hand"), "handaxe", "one handaxe left: still wielded")
	assert_true(s.remove_item("handaxe", 1, content))
	assert_eq(s.equipped_item("main_hand"), "", "the last one thrown: main hand empty")
	assert_eq(s.attacks.size(), 0)
	s.add_item("shortbow")
	assert_eq(s.equip("shortbow", "main_hand", content), "")
	assert_eq(s.attacks[0]["kind"], "ranged", "a bow in the main hand shoots")


func test_unknown_weapon_items_are_skipped() -> void:
	var s := CoreFixtures.sheet("U")
	s.add_item("mystery_blade")
	s.add_item("rations", 3)
	s.rebuild_attacks(content)
	assert_eq(s.attacks.size(), 0)


func test_sheet_round_trip_keeps_inventory_spells_and_resources() -> void:
	var s := CoreFixtures.caster("W", Ability.Type.INT, ["fire_bolt", "magic_missile"])
	s.features = ["second_wind", "rage"]
	s.restore_class_resources()
	s.add_item("dagger", 2)
	s.add_item("leather_armor")
	s.add_item("gold", 7)
	s.equip("dagger", "main_hand", content)
	s.equip("leather_armor", "armor", content)
	s.use_spell_slot(1)
	s.spend_class_resource("rage")
	s.active_buffs.append("mage_armor")
	var data: Dictionary = JSON.parse_string(JSON.stringify(s.to_dict()))
	var copy := CharacterSheet.from_dict(data)
	assert_eq(copy.to_dict(), s.to_dict())
	assert_eq(copy.inventory, [{"item": "dagger", "qty": 2}, {"item": "leather_armor", "qty": 1}, {"item": "gold", "qty": 7}])
	assert_eq(copy.equipped_item("main_hand"), "dagger")
	assert_eq(copy.equipped_item("armor"), "leather_armor")
	assert_eq(copy.casting_ability, Ability.Type.INT)
	assert_eq(copy.spell_slots, [1, 2])
	assert_eq(copy.spell_slots_max, [2, 2])
	assert_eq(copy.spells_prepared, ["fire_bolt", "magic_missile"])
	assert_eq(copy.class_resource("rage"), 1)
	assert_eq(copy.class_resource("second_wind"), 1)
	assert_eq(copy.active_buffs, ["mage_armor"])
	assert_eq(copy.armor_class(), s.armor_class())
	assert_eq(typeof(copy.attacks[0]["range_tiles"][0]), TYPE_INT)


func test_equipped_item_not_carried_is_dropped_on_load() -> void:
	var copy := CharacterSheet.from_dict({"inventory": [{"item": "dagger", "qty": 1}], "equipped": {"main_hand": "longsword", "off_hand": "dagger"}})
	assert_eq(copy.equipped_item("main_hand"), "")
	assert_eq(copy.equipped_item("off_hand"), "dagger")


func test_builder_applies_kit_and_equips_starting_gear() -> void:
	var cls := ClassDefinition.from_dict({
		"id": "tester", "display_name": "Tester", "hit_die": 10,
		"primary_abilities": ["STR"], "saving_throws": ["STR", "CON"],
		"armor_proficiencies": ["heavy"], "weapon_proficiencies": ["simple", "martial"],
		"skill_choices": ["ATHLETICS"], "skill_choice_count": 1,
		"starting_weapon": "longsword", "starting_armor": {"base": 16, "max_dex": 0}, "starting_shield": true,
		"starting_kit": [{"item": "handaxe", "qty": 2}, {"item": "potion_of_healing", "qty": 2}, {"item": "gold", "qty": 10}],
		"features": ["second_wind"],
		"spellcasting": null,
	})
	assert_not_null(cls)
	assert_eq(cls.starting_kit.size(), 3)
	var scores := AbilityScores.new()
	scores.set_all([16, 12, 14, 10, 10, 10])
	var none: Array[int] = []
	var sword: WeaponDefinition = content["weapons"]["longsword"]
	var s := CharacterBuilder.create("Kit", cls, null, scores, none, sword, content)
	assert_eq(s.equipped_item("main_hand"), "longsword")
	assert_eq(s.equipped_item("armor"), "chain_mail", "matched by base 16 / max_dex 0")
	assert_eq(s.equipped_item("off_hand"), "shield")
	assert_eq(s.armor_class(), 18)
	assert_eq(s.count_item("handaxe"), 2)
	assert_eq(s.count_item("potion_of_healing"), 2)
	assert_eq(s.gold(), 10)
	assert_eq(s.attacks.size(), 2)
	assert_eq(s.attacks[0]["name"], "Longsword")
	assert_eq(s.attacks[1]["name"], "Handaxe (thrown)")
	assert_eq(s.class_resource("second_wind"), 1)
	assert_eq(s.features, ["second_wind"])


func test_real_items_load_and_reference_known_content() -> void:
	var items := ContentLoader.load_items()
	if items.is_empty():
		return  # CONTENT has not landed data/items yet
	assert_true(items.has("potion_of_healing"))
	var potion: ItemDefinition = items["potion_of_healing"]
	assert_eq(potion.use_effect, "heal")
	var problems := ContentLoader.validate_references(ContentLoader.load_all())
	assert_eq(problems, [], "content cross-references")


func test_every_real_class_builds_with_its_kit() -> void:
	var c := ContentLoader.cache()
	var classes: Dictionary = c["classes"]
	var scores := AbilityScores.new()
	scores.set_all([14, 14, 14, 12, 12, 12])
	var none: Array[int] = []
	for class_id: String in classes.keys():
		var cls: ClassDefinition = classes[class_id]
		var s := CharacterBuilder.create(class_id, cls, null, scores, none, null, c)
		assert_not_null(s, class_id)
		assert_false(s.attacks.is_empty(), "%s has a weapon attack" % class_id)
		for entry in cls.starting_kit:
			assert_true(s.has_item(str(entry["item"]), DictUtil.to_int(entry["qty"])), "%s carries %s" % [class_id, entry["item"]])
		if cls.starting_armor_base > 0:
			assert_ne(s.equipped_item("armor"), "", "%s wears its armor as an item" % class_id)
		if cls.starting_shield:
			assert_eq(s.equipped_item("off_hand"), "shield", "%s holds a shield" % class_id)
		var spells: Dictionary = c["spells"]
		for spell_id in s.spells_prepared:
			assert_true(spells.has(spell_id), "%s: %s exists" % [class_id, spell_id])


func test_ranged_thrown_weapon_in_hand_is_only_thrown() -> void:
	var s := CoreFixtures.sheet("Monk", 10, [10, 16, 10, 10, 10, 10])
	s.add_item("dart", 10)
	assert_eq(s.equip("dart", "main_hand", content), "")
	assert_eq(s.attacks.size(), 1, "a dart is a ranged weapon: no melee attack")
	assert_eq(s.attacks[0]["name"], "Dart")
	assert_eq(s.attacks[0]["kind"], "thrown")
	assert_eq(s.attacks[0]["ability"], "DEX", "finesse")
	assert_eq(s.attacks[0]["consumes"], "dart")

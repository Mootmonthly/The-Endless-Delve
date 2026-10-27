extends TestCase
## +N weapons, armor and shields (ItemDefinition.bonus applied by
## CharacterSheet when equipped), the "key" item kind, and LootTable category
## rolls (guaranteed gear / consumables / gold, optional supplies).

var content: Dictionary


func before_each() -> void:
	content = CoreFixtures.content()
	var items: Dictionary = content["items"]
	for idef: ItemDefinition in [
		CoreFixtures.item({"id": "longsword_plus_1", "display_name": "Longsword, +1", "kind": "weapon", "weapon_id": "longsword", "bonus": 1}),
		CoreFixtures.item({"id": "shortsword_plus_2", "display_name": "Shortsword, +2", "kind": "weapon", "weapon_id": "shortsword", "bonus": 2}),
		CoreFixtures.item({"id": "shortbow_plus_1", "display_name": "Shortbow, +1", "kind": "weapon", "weapon_id": "shortbow", "ammo_id": "arrows", "bonus": 1}),
		CoreFixtures.item({"id": "scale_mail_plus_1", "display_name": "Scale Mail, +1", "kind": "armor",
			"armor": {"base": 14, "max_dex": 2, "category": "medium"}, "bonus": 1}),
		CoreFixtures.item({"id": "shield_plus_1", "display_name": "Shield, +1", "kind": "shield", "shield": {"bonus": 2}, "bonus": 1}),
	]:
		items[idef.id] = idef


func _table(d: Dictionary) -> LootTable:
	var base := {"schema_version": 1, "id": "t"}
	base.merge(d, true)
	return LootTable.from_dict(base)


func _chest() -> LootTable:
	return _table({"rolls": [
		{"name": "gear", "entries": [{"item": "longsword", "weight": 3}, {"item": "shield", "weight": 1}]},
		{"name": "consumables", "entries": [{"item": "potion_of_healing", "weight": 1, "qty": [1, 2]}]},
		{"name": "gold", "entries": [{"item": "gold", "weight": 1, "qty": [25, 60]}]},
		{"name": "supplies", "chance": 50, "count": [1, 2], "entries": [{"item": "rations", "weight": 1, "qty": [1, 3]}]},
	]})


# --- items ------------------------------------------------------------------------------

func test_bonus_and_key_kind_parse() -> void:
	var sword: ItemDefinition = content["items"]["longsword_plus_1"]
	assert_eq(sword.bonus, 1)
	assert_eq(int(sword.to_dict()["bonus"]), 1)
	var plain: ItemDefinition = content["items"]["longsword"]
	assert_eq(plain.bonus, 0)
	assert_false(plain.to_dict().has("bonus"))
	var trinket := CoreFixtures.item({"id": "x", "display_name": "X", "kind": "misc", "bonus": 1})
	assert_eq(trinket.bonus, 0, "only weapons, armor and shields take a bonus")
	var key := CoreFixtures.item({"id": "key_bronze", "display_name": "Bronze Key", "kind": "key", "weight": 0.1})
	assert_not_null(key)
	assert_eq(key.kind, ItemDefinition.KIND_KEY)
	assert_has(ItemDefinition.KINDS, "key")
	assert_false(key.stackable, "keys do not stack by default")


func test_plus_one_weapon_adds_to_hit_and_damage() -> void:
	var s := CoreFixtures.sheet("F", 10, [16, 10, 10, 10, 10, 10])
	s.add_item("longsword")
	s.add_item("longsword_plus_1")
	assert_eq(s.equip("longsword", "main_hand", content), "")
	var plain := s.attacks[0]
	assert_eq([plain["to_hit"], plain["damage"]], [5, "1d8+3"], "STR +3, proficiency +2")
	assert_false(plain.get("magical", false) == true)
	assert_eq(s.equip("longsword_plus_1", "main_hand", content), "")
	var magic := s.attacks[0]
	assert_eq([magic["to_hit"], magic["damage"]], [6, "1d8+4"], "+1 to hit and damage")
	assert_eq(magic["name"], "Longsword +1")
	assert_eq(magic["item"], "longsword_plus_1")
	assert_true(magic["magical"] == true, "a +1 weapon's attack is magical")
	assert_eq(int(magic["magic_bonus"]), 1)
	s.add_item("shortsword_plus_2")
	s.add_item("shortbow_plus_1")
	s.add_item("arrows", 10)
	assert_eq(s.equip("shortsword_plus_2", "main_hand", content), "")
	assert_eq([s.attacks[0]["to_hit"], s.attacks[0]["damage"]], [7, "1d6+5"], "+2 shortsword")
	var bow: Dictionary = {}
	for a in s.attacks:
		if str(a["item"]) == "shortbow_plus_1":
			bow = a
	assert_eq([bow["kind"], bow["to_hit"], bow["damage"], bow["consumes"]], ["ranged", 3, "1d6+1", "arrows"], "DEX +0, prof +2, +1")


func test_plus_one_armor_and_shield_add_to_ac() -> void:
	var s := CoreFixtures.sheet("A", 10, [10, 14, 10, 10, 10, 10])
	s.add_item("scale_mail_plus_1")
	s.add_item("shield_plus_1")
	s.add_item("shield")
	assert_eq(s.equip("scale_mail_plus_1", "armor", content), "")
	assert_eq(s.armor_class(), 14 + 2 + 1, "medium armor, DEX cap 2, +1")
	assert_eq(s.equip("shield_plus_1", "off_hand", content), "")
	assert_eq(s.armor_class(), 17 + 2 + 1, "a +1 shield gives 3")
	assert_eq(s.equip("shield", "off_hand", content), "")
	assert_eq(s.armor_class(), 19, "a plain shield gives 2")
	assert_eq(s.unequip("armor", content), "")
	assert_eq(s.armor_class(), 12 + 2, "unarmored again")
	var again := CharacterSheet.from_dict(s.to_dict())
	assert_eq(again.armor_class(), s.armor_class(), "survives a round trip")


# --- loot category rolls ------------------------------------------------------------------

func test_category_rolls_parse() -> void:
	var t := _chest()
	assert_not_null(t)
	assert_true(t.is_grouped())
	assert_eq(t.group_names(), ["gear", "consumables", "gold", "supplies"] as Array[String])
	assert_eq(t.item_ids(), ["longsword", "shield", "potion_of_healing", "gold", "rations"] as Array[String])
	assert_eq(int(t.groups[3]["chance"]), 50)
	assert_eq([t.groups[3]["count_min"], t.groups[3]["count_max"]], [1, 2])
	assert_eq(int(t.groups[0]["chance"]), 100, "guaranteed by default")
	var old := _table({"rolls": 2, "entries": [{"item": "gold", "weight": 1}]})
	assert_false(old.is_grouped(), "the single-bag shape still loads")
	assert_eq(old.roll(Rng.new(1)), [{"item": "gold", "qty": 2}] as Array[Dictionary])


func test_invalid_category_rolls_are_rejected() -> void:
	assert_null(_table({"rolls": [{"name": "gear", "entries": []}]}), "empty group")
	assert_null(_table({"rolls": [{"name": "gear", "chance": 0, "entries": [{"item": "gold"}]}]}), "chance 0")
	assert_null(_table({"rolls": [{"name": "gear", "chance": 101, "entries": [{"item": "gold"}]}]}), "chance over 100")
	assert_null(_table({"rolls": [{"name": "gear", "count": [3, 1], "entries": [{"item": "gold"}]}]}), "inverted count")
	assert_null(_table({"rolls": [{"name": "gear", "entries": [{"item": "gold"}]}], "entries": [{"item": "gold"}]}), "both shapes")
	assert_null(_table({"rolls": [{"name": "gear", "entries": [{"weight": 1}]}]}), "an entry with no item")


func test_every_guaranteed_category_drops_every_time() -> void:
	var t := _chest()
	var supplies := 0
	for s in range(1, 201):
		var by := t.roll_by_group(Rng.new(s))
		for g in ["gear", "consumables", "gold"]:
			assert_true(by.has(g) and not (by[g] as Array).is_empty(), "seed %d drops %s" % [s, g])
		var gold: Array = by["gold"]
		assert_in_range(int(gold[0]["qty"]), 25, 60, "gold range")
		if by.has("supplies"):
			supplies += 1
		assert_eq(t.roll(Rng.new(s)).size(), 3 + (1 if by.has("supplies") else 0), "seed %d: merged roll" % s)
		assert_eq(t.roll(Rng.new(s)), t.roll(Rng.new(s)), "deterministic")
	assert_in_range(supplies, 70, 130, "supplies about half the time (%d / 200)" % supplies)

extends TestCase
## LootTable parsing and rolling; chests on floors.


func _table(d: Dictionary) -> LootTable:
	var base := {"schema_version": 1, "id": "t", "rolls": 1}
	base.merge(d, true)
	return LootTable.from_dict(base)


func test_parse_entries_and_ranges() -> void:
	var t := _table({"rolls": [1, 3], "entries": [
		{"item": "gold", "weight": 4, "qty": [5, 20]}, {"item": "potion_of_healing", "weight": 2}, {"nothing": true, "weight": 1}]})
	assert_not_null(t)
	assert_eq(t.rolls_min, 1)
	assert_eq(t.rolls_max, 3)
	assert_eq(t.total_weight(), 7)
	assert_eq(t.item_ids(), ["gold", "potion_of_healing"])
	assert_eq(t.entries[0], {"item": "gold", "weight": 4, "qty_min": 5, "qty_max": 20})
	assert_eq(t.entries[2]["item"], "", "a nothing entry")


func test_invalid_tables_are_rejected() -> void:
	assert_null(LootTable.from_dict({"id": "t"}), "no entries")
	assert_null(_table({"entries": []}), "empty entries")
	assert_null(_table({"entries": [{"weight": 1}]}), "neither item nor nothing")
	assert_null(_table({"entries": [{"item": "gold", "weight": 0}]}), "zero weight")
	assert_null(_table({"entries": [{"item": "gold", "weight": 1, "qty": [5, 2]}]}), "inverted qty")
	assert_null(_table({"rolls": -1, "entries": [{"item": "gold", "weight": 1}]}), "negative rolls")
	assert_null(_table({"schema_version": 9, "entries": [{"item": "gold", "weight": 1}]}), "schema")


func test_rolls_are_deterministic() -> void:
	var t := _table({"rolls": [1, 4], "entries": [
		{"item": "gold", "weight": 4, "qty": [5, 20]}, {"item": "potion_of_healing", "weight": 2, "qty": [1, 2]}, {"nothing": true, "weight": 1}]})
	for s in range(1, 30):
		assert_eq(t.roll(Rng.new(s)), t.roll(Rng.new(s)), "seed %d" % s)
	var differs := false
	for s in range(1, 30):
		if t.roll(Rng.new(s)) != t.roll(Rng.new(s + 100)):
			differs = true
	assert_true(differs, "different seeds give different loot")


func test_weights_shape_the_distribution() -> void:
	var t := _table({"entries": [{"item": "a", "weight": 3}, {"item": "b", "weight": 1}, {"nothing": true, "weight": 1}]})
	var counts := {"a": 0, "b": 0, "": 0}
	var rng := Rng.new(99)
	for _i in range(5000):
		var out := t.roll(rng)
		var key := "" if out.is_empty() else str(out[0]["item"])
		counts[key] = DictUtil.to_int(counts[key]) + 1
	assert_in_range(counts["a"], 2700, 3300, "3/5")
	assert_in_range(counts["b"], 850, 1150, "1/5")
	assert_in_range(counts[""], 850, 1150, "nothing 1/5")


func test_nothing_only_table_gives_nothing() -> void:
	var t := _table({"rolls": 5, "entries": [{"nothing": true, "weight": 3}]})
	assert_eq(t.roll(Rng.new(1)), [])


func test_quantities_and_merging() -> void:
	var t := _table({"rolls": 6, "entries": [{"item": "gold", "weight": 1, "qty": [2, 4]}]})
	var out := t.roll(Rng.new(5))
	assert_eq(out.size(), 1, "same item stacks")
	assert_in_range(out[0]["qty"], 12, 24)
	var fixed := _table({"rolls": 3, "entries": [{"item": "arrows", "weight": 1, "qty": 10}]})
	assert_eq(fixed.roll(Rng.new(1)), [{"item": "arrows", "qty": 30}])


func test_loot_goes_into_an_inventory() -> void:
	var t := _table({"rolls": 2, "entries": [{"item": "gold", "weight": 1, "qty": [5, 5]}]})
	var s := CharacterSheet.new()
	for entry in t.roll(Rng.new(3)):
		s.add_item(str(entry["item"]), DictUtil.to_int(entry["qty"]))
	assert_eq(s.gold(), 10)


func test_real_loot_tables_load() -> void:
	var tables := ContentLoader.load_loot_tables() if DirAccess.dir_exists_absolute("res://data/loot") else {}
	if tables.is_empty():
		return  # CONTENT has not landed data/loot yet
	var items := ContentLoader.load_items()
	for t_v: Variant in tables.values():
		var t: LootTable = t_v
		for item_id in t.item_ids():
			assert_true(items.has(item_id), "%s: %s" % [t.id, item_id])
		assert_eq(t.roll(Rng.new(1)), t.roll(Rng.new(1)))


func test_monster_loot_table_field() -> void:
	var m := MonsterDefinition.from_dict({
		"id": "m", "display_name": "M", "armor_class": 10, "hit_points": 5, "hit_dice": "1d8", "speed": 30,
		"abilities": {"STR": 10, "DEX": 10, "CON": 10, "INT": 10, "WIS": 10, "CHA": 10},
		"challenge_rating": 0, "xp": 10, "loot_table": "goblin_pouch",
		"attacks": [{"name": "Bite", "to_hit": 2, "damage": "1d4", "damage_type": "piercing"}]})
	assert_eq(m.loot_table, "goblin_pouch")
	var plain := MonsterDefinition.from_dict({
		"id": "p", "display_name": "P", "armor_class": 10, "hit_points": 5, "hit_dice": "1d8", "speed": 30,
		"abilities": {"STR": 10, "DEX": 10, "CON": 10, "INT": 10, "WIS": 10, "CHA": 10},
		"challenge_rating": 0, "xp": 10, "attacks": [{"name": "Bite", "to_hit": 2, "damage": "1d4", "damage_type": "piercing"}]})
	assert_eq(plain.loot_table, "", "optional")


# --- chests -------------------------------------------------------------------------

func _floor(chests: Array) -> FloorData:
	return FloorData.from_dict({
		"id": "f", "rows": ["#######", "#.....#", "#..#..#", "#.....#", "#######"],
		"arrival": [1, 1], "stairs": [5, 3], "encounter_zones": [], "chests": chests})


func test_chest_data_round_trip() -> void:
	var c := ChestData.from_dict({"id": "c1", "position": [4, 1], "table": "starter_gear", "hidden": true})
	assert_eq(c.id, "c1")
	assert_eq(c.position, Vector2i(4, 1))
	assert_eq(c.table_id, "starter_gear")
	assert_true(c.hidden)
	assert_eq(c.to_dict(), {"id": "c1", "position": [4, 1], "table": "starter_gear", "hidden": true})
	assert_false(ChestData.from_dict({"id": "c2", "position": [1, 1], "table": "x"}).hidden, "hidden defaults to false")


func test_floor_parses_and_validates_chests() -> void:
	var f := _floor([{"id": "c1", "position": [4, 3], "table": "starter_gear"}])
	assert_eq(f.chests.size(), 1)
	assert_eq(f.get_chest("c1").position, Vector2i(4, 3))
	assert_null(f.get_chest("nope"))
	assert_eq(f.validate(), [])
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(f.to_dict()))
	var copy := FloorData.from_dict(parsed)
	assert_eq(copy.to_dict(), f.to_dict())
	var tables := {"starter_gear": LootTable.from_dict({"id": "starter_gear", "entries": [{"item": "gold", "weight": 1}]})}
	assert_eq(f.validate(tables), [])
	var bad := _floor([
		{"id": "c1", "position": [3, 2], "table": "starter_gear"},
		{"id": "c1", "position": [1, 3], "table": "missing_table"},
		{"id": "", "position": [2, 3], "table": ""},
	])
	var problems := bad.validate(tables)
	assert_has(problems, "chest 'c1' position (3, 2) is not walkable")
	assert_has(problems, "duplicate chest id 'c1'")
	assert_has(problems, "chest 'c1' uses unknown loot table 'missing_table'")
	assert_has(problems, "a chest has an empty id")
	assert_has(problems, "chest '' has no loot table")
	assert_eq(FloorData.from_dict({"id": "x"}).chests.size(), 0, "chests are optional")


func test_real_floor_chests_validate() -> void:
	var tables := ContentLoader.load_loot_tables() if DirAccess.dir_exists_absolute("res://data/loot") else {}
	for n in range(1, 6):
		var path := "res://floors/floor_%03d.json" % n
		if not FileAccess.file_exists(path):
			continue
		var f := FloorData.from_dict(ContentLoader.load_json(path))
		assert_eq(f.validate(tables), [], path)

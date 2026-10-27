extends TestCase
## Content checks for data/weapons, data/items, data/loot and the monsters'
## loot tables: every file parses, references resolve, SRD numbers are in
## place for the armor table and potions, and loot rolls only produce items
## that exist.

const WEAPONS_DIR := "res://data/weapons"
const ITEMS_DIR := "res://data/items"
const LOOT_DIR := "res://data/loot"
const MONSTERS_DIR := "res://data/monsters"
## SRD 5.1 armor table: id -> [base AC, max DEX (-1 = none), category, stealth disadvantage].
const SRD_ARMOR: Dictionary = {
	"padded_armor": [11, -1, "light", true],
	"leather_armor": [11, -1, "light", false],
	"studded_leather_armor": [12, -1, "light", false],
	"hide_armor": [12, 2, "medium", false],
	"chain_shirt": [13, 2, "medium", false],
	"scale_mail": [14, 2, "medium", true],
	"breastplate": [14, 2, "medium", false],
	"chain_mail": [16, 0, "heavy", true],
	"splint_armor": [17, 0, "heavy", true],
	"plate_armor": [18, 0, "heavy", true],
}
## Monster -> loot table (rats and other weak foes: small; tougher: medium; ogre: boss).
const MONSTER_TABLES: Dictionary = {
	"giant_rat": "monster_small", "goblin": "monster_small", "kobold": "monster_small",
	"skeleton": "monster_small", "zombie": "monster_small", "giant_centipede": "monster_small",
	"hobgoblin": "monster_medium", "ghoul": "monster_medium", "bugbear": "monster_medium",
	"giant_spider": "monster_medium", "ogre": "boss",
}

var _weapons: Dictionary = {}
var _items: Dictionary = {}
var _loot: Dictionary = {}
var _monsters: Dictionary = {}


func before_each() -> void:
	if _weapons.is_empty():
		_weapons = ContentLoader.load_weapons(WEAPONS_DIR)
		_items = ContentLoader.load_items(ITEMS_DIR)
		_loot = ContentLoader.load_loot_tables(LOOT_DIR)
		_monsters = ContentLoader.load_monsters(MONSTERS_DIR)


func _raw(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var d: Dictionary = parsed
	return d


func _item(id: String) -> ItemDefinition:
	if not _items.has(id):
		return null
	var it: ItemDefinition = _items[id]
	return it


func test_every_content_file_parses() -> void:
	assert_eq(_weapons.size(), ContentLoader.json_files(WEAPONS_DIR).size(), "every weapon file parses")
	assert_eq(_items.size(), ContentLoader.json_files(ITEMS_DIR).size(), "every item file parses")
	assert_eq(_loot.size(), ContentLoader.json_files(LOOT_DIR).size(), "every loot table parses")
	for path in ContentLoader.json_files(ITEMS_DIR) + ContentLoader.json_files(LOOT_DIR) + ContentLoader.json_files(WEAPONS_DIR):
		assert_eq(str(_raw(path).get("id", "")), path.get_file().get_basename(), "%s: id matches the file name" % path)


func test_every_weapon_has_an_item_and_every_weapon_item_a_weapon() -> void:
	for wid: String in _weapons.keys():
		var it := _item(wid)
		assert_not_null(it, "weapon '%s' has an item" % wid)
		if it != null:
			assert_eq(it.kind, "weapon")
			assert_eq(it.weapon_id, wid)
	for iid: String in _items.keys():
		var it := _item(iid)
		if it.kind == "weapon":
			assert_true(_weapons.has(it.weapon_id), "item '%s': weapon '%s' exists" % [iid, it.weapon_id])


func test_ranged_and_thrown_weapons_have_ranges_and_ammo() -> void:
	for wid: String in _weapons.keys():
		var w: WeaponDefinition = _weapons[wid]
		var raw := _raw("%s/%s.json" % [WEAPONS_DIR, wid])
		var ranged := w.has_property("ammunition") or w.has_property("thrown")
		if ranged:
			assert_eq(w.range_ft.size(), 2, "%s: range_ft is [normal, long]" % wid)
			if w.range_ft.size() == 2:
				assert_true(w.range_ft[0] > 0 and w.range_ft[1] >= w.range_ft[0], "%s: range %s" % [wid, str(w.range_ft)])
		if w.has_property("ammunition"):
			var ammo := str(raw.get("ammo_id", ""))
			var it := _item(ammo)
			assert_not_null(it, "%s: ammo item '%s' exists" % [wid, ammo])
			if it != null:
				assert_eq(it.kind, "ammo", "%s: ammo item kind" % wid)
				assert_true(it.stackable, "%s: ammo stacks" % wid)
			var weapon_item := _item(wid)
			if weapon_item != null:
				assert_eq(weapon_item.ammo_id, ammo, "%s: the item names the same ammo" % wid)


func test_srd_weapon_numbers() -> void:
	var expect := {
		"javelin": ["1d6", "piercing", [30, 120]], "light_crossbow": ["1d8", "piercing", [80, 320]],
		"shortbow": ["1d6", "piercing", [80, 320]], "longbow": ["1d8", "piercing", [150, 600]],
		"dart": ["1d4", "piercing", [20, 60]], "sling": ["1d4", "bludgeoning", [30, 120]],
		"spear": ["1d6", "piercing", [20, 60]], "greataxe": ["1d12", "slashing", []],
		"rapier": ["1d8", "piercing", []], "scimitar": ["1d6", "slashing", []],
		"warhammer": ["1d8", "bludgeoning", []], "battleaxe": ["1d8", "slashing", []],
		"club": ["1d4", "bludgeoning", []], "handaxe": ["1d6", "slashing", [20, 60]],
	}
	for wid: String in expect.keys():
		assert_true(_weapons.has(wid), "weapon '%s' exists" % wid)
		if not _weapons.has(wid):
			continue
		var w: WeaponDefinition = _weapons[wid]
		var e: Array = expect[wid]
		assert_eq(w.damage, str(e[0]), "%s damage" % wid)
		assert_eq(w.damage_type, str(e[1]), "%s damage type" % wid)
		var rng: Array = e[2]
		if not rng.is_empty():
			assert_eq(w.range_ft, [int(rng[0]), int(rng[1])] as Array[int], "%s range" % wid)
	var rapier: WeaponDefinition = _weapons.get("rapier")
	if rapier != null:
		assert_true(rapier.is_finesse(), "rapier is finesse")


func test_srd_armor_table() -> void:
	for aid: String in SRD_ARMOR.keys():
		var it := _item(aid)
		assert_not_null(it, "armor '%s' exists" % aid)
		if it == null:
			continue
		var e: Array = SRD_ARMOR[aid]
		assert_eq(it.kind, "armor")
		assert_eq(it.armor_base, int(e[0]), "%s base AC" % aid)
		assert_eq(it.armor_max_dex, int(e[1]), "%s max DEX" % aid)
		assert_eq(it.armor_category, str(e[2]), "%s category" % aid)
		assert_eq(it.stealth_disadvantage, bool(e[3]), "%s stealth" % aid)
	var shield := _item("shield")
	assert_not_null(shield, "shield exists")
	if shield != null:
		assert_eq(shield.kind, "shield")
		assert_eq(shield.shield_bonus, 2)


func test_consumables_and_basics() -> void:
	var potion := _item("potion_of_healing")
	var greater := _item("potion_of_greater_healing")
	assert_not_null(potion)
	assert_not_null(greater)
	if potion != null:
		assert_eq([potion.kind, potion.use_effect, potion.use_dice, potion.use_action, potion.use_target],
				["consumable", "heal", "2d4+2", "action", "self"])
		assert_true(potion.stackable)
	if greater != null:
		assert_eq([greater.use_effect, greater.use_dice], ["heal", "4d4+4"])
	var gold := _item("gold")
	assert_not_null(gold)
	if gold != null:
		assert_eq(gold.kind, "gold")
		assert_true(gold.stackable)
	for mid in ["rations", "thieves_tools", "spellbook", "component_pouch", "holy_symbol", "torch"]:
		var it := _item(mid)
		assert_not_null(it, "misc item '%s'" % mid)
		if it != null:
			assert_eq(it.kind, "misc", "%s kind" % mid)
	for aid in ["arrows", "bolts", "sling_bullets"]:
		var it := _item(aid)
		assert_not_null(it, "ammo item '%s'" % aid)
		if it != null:
			assert_eq(it.kind, "ammo", "%s kind" % aid)
	# Hand-made items all have a price; imported SRD gear without a price
	# (pack contents) and artifacts are worth 0.
	for iid: String in _items.keys():
		var it := _item(iid)
		var raw := _raw("%s/%s.json" % [ITEMS_DIR, iid])
		assert_ne(it.description, "", "%s has a description" % iid)
		assert_true(it.weight >= 0.0 and it.value_gp >= 0.0, "%s weight/value" % iid)
		if DictUtil.to_bool(raw.get("hand_edited", false), false):
			assert_true(it.value_gp > 0.0, "%s has a price" % iid)


func test_loot_tables_are_well_formed() -> void:
	for path in ContentLoader.json_files(LOOT_DIR):
		var raw := _raw(path)
		var tid := str(raw.get("id", ""))
		var bags: Array[Dictionary] = []
		if typeof(raw.get("rolls")) == TYPE_ARRAY and not (raw["rolls"] as Array).is_empty() \
				and typeof((raw["rolls"] as Array)[0]) == TYPE_DICTIONARY:
			# Category rolls: each group is its own weighted bag.
			for g in DictUtil.to_dict_array(raw["rolls"]):
				assert_ne(str(g.get("name", "")), "", "%s: every category roll has a name" % tid)
				bags.append({"ctx": "%s/%s" % [tid, str(g.get("name", ""))], "entries": DictUtil.to_dict_array(g.get("entries", []))})
			assert_false(raw.has("entries"), "%s: category rolls or entries, not both" % tid)
		else:
			assert_true(DictUtil.to_int(raw.get("rolls", 0), 0) >= 1, "%s rolls >= 1" % tid)
			bags.append({"ctx": tid, "entries": DictUtil.to_dict_array(raw.get("entries", []))})
		for bag in bags:
			_check_entries(str(bag["ctx"]), bag["entries"])
		assert_true(_loot.has(tid), "%s loads" % tid)


func _check_entries(tid: String, entries: Array[Dictionary]) -> void:
	assert_false(entries.is_empty(), "%s has entries" % tid)
	for e in entries:
		assert_true(DictUtil.to_int(e.get("weight", 0), 0) >= 1, "%s: weight >= 1 in %s" % [tid, str(e)])
		if DictUtil.to_bool(e.get("nothing", false), false):
			assert_false(e.has("item"), "%s: a nothing entry names no item" % tid)
			continue
		var iid := str(e.get("item", ""))
		assert_true(_items.has(iid), "%s: item '%s' exists" % [tid, iid])
		if e.has("qty"):
			var q := DictUtil.to_int_array(e["qty"])
			assert_eq(q.size(), 2, "%s %s: qty is [min, max]" % [tid, iid])
			if q.size() == 2:
				assert_true(q[0] >= 1 and q[1] >= q[0], "%s %s: qty %s" % [tid, iid, str(q)])
			var it := _item(iid)
			if it != null and q.size() == 2 and q[1] > 1:
				assert_true(it.stackable, "%s %s: multi-quantity drops are stackable" % [tid, iid])


func test_required_tables_and_their_shape() -> void:
	for tid in ["starter_gear", "monster_small", "monster_medium", "boss", "hidden_cache"]:
		assert_true(_loot.has(tid), "loot table '%s'" % tid)
	var starter := _raw(LOOT_DIR + "/starter_gear.json")
	var has_nothing := false
	var kinds := {}
	for e in DictUtil.to_dict_array(starter.get("entries", [])):
		if DictUtil.to_bool(e.get("nothing", false), false):
			has_nothing = true
		else:
			var it := _item(str(e.get("item", "")))
			if it != null:
				kinds[it.kind] = true
				if it.kind == "armor":
					assert_true(it.armor_category != "heavy", "starter gear has no heavy armor (%s)" % it.id)
	assert_true(has_nothing, "starter_gear has a 'nothing' entry")
	for k in ["weapon", "armor", "consumable", "gold"]:
		assert_true(kinds.has(k), "starter_gear offers a %s" % k)
	# Weak monsters mostly drop nothing.
	var small := _raw(LOOT_DIR + "/monster_small.json")
	var nothing_w := 0
	var total_w := 0
	for e in DictUtil.to_dict_array(small.get("entries", [])):
		var w := DictUtil.to_int(e.get("weight", 0), 0)
		total_w += w
		if DictUtil.to_bool(e.get("nothing", false), false):
			nothing_w += w
	assert_true(nothing_w * 2 >= total_w, "monster_small drops nothing at least half the time (%d/%d)" % [nothing_w, total_w])
	# The boss table never comes up empty.
	for e in DictUtil.to_dict_array(_raw(LOOT_DIR + "/boss.json").get("entries", [])):
		assert_false(DictUtil.to_bool(e.get("nothing", false), false), "boss table has no nothing entry")


func test_every_monster_has_an_existing_loot_table() -> void:
	for path in ContentLoader.json_files(MONSTERS_DIR):
		var raw := _raw(path)
		var mid := str(raw.get("id", ""))
		var table := str(raw.get("loot_table", ""))
		assert_ne(table, "", "%s has a loot_table" % mid)
		assert_true(_loot.has(table), "%s: loot table '%s' exists" % [mid, table])
		if MONSTER_TABLES.has(mid):
			assert_eq(table, str(MONSTER_TABLES[mid]), "%s loot table" % mid)
		if _monsters.has(mid):
			var m: MonsterDefinition = _monsters[mid]
			assert_eq(m.loot_table, table, "%s: parsed loot_table" % mid)


func test_rolls_only_produce_existing_items() -> void:
	for tid: String in _loot.keys():
		var table: LootTable = _loot[tid]
		var rng := Rng.new(4242)
		for i in range(200):
			for drop in table.roll(rng):
				var iid := str(drop.get("item", ""))
				assert_true(_items.has(iid), "%s rolled unknown item '%s'" % [tid, iid])
				assert_true(DictUtil.to_int(drop.get("qty", 0), 0) >= 1, "%s rolled qty >= 1" % tid)


func test_tiered_chest_tables_hold_wanted_gear() -> void:
	for tid in ["chest_stairs_t1", "chest_stairs_t2", "cache_t1", "cache_t2"]:
		var table: LootTable = _loot.get(tid)
		assert_not_null(table, tid)
		if table == null:
			continue
		var gear := table.groups[0]
		assert_eq(str(gear["name"]), "gear", "%s rolls gear first" % tid)
		var plus_weight := 0
		var total := 0
		for e: Dictionary in (gear["entries"] as Array):
			var it := _item(str(e["item"]))
			assert_not_null(it, "%s gear item %s" % [tid, str(e["item"])])
			if it == null:
				continue
			assert_has(["weapon", "armor", "shield"], it.kind, "%s gear is a weapon, armor or shield (%s)" % [tid, it.id])
			assert_true(it.kind != "armor" or it.armor_category != "heavy", "%s: no heavy armor (%s)" % [tid, it.id])
			total += DictUtil.to_int(e["weight"])
			if it.bonus > 0:
				plus_weight += DictUtil.to_int(e["weight"])
		if tid == "chest_stairs_t1":
			assert_eq(plus_weight, 0, "tier 1 stairs gear is mundane")
		elif tid == "cache_t2":
			assert_in_range(float(plus_weight) / total, 0.4, 0.6, "cache_t2: +1 gear about half the time")
		else:
			assert_in_range(float(plus_weight) / total, 0.2, 0.3, "%s: +1 gear about a quarter of the time" % tid)
		for wanted in ["longsword", "shortsword", "battleaxe", "rapier", "longbow", "scale_mail", "chain_shirt", "shield"]:
			assert_has(table.item_ids(), wanted, "%s offers %s" % [tid, wanted])


func test_plus_one_gear_is_equippable() -> void:
	for iid in ["longsword_plus_1", "shortsword_plus_1", "longbow_plus_1", "shield_plus_1", "chain_shirt_plus_1", "leather_armor_plus_1"]:
		var it := _item(iid)
		assert_not_null(it, iid)
		if it == null:
			continue
		assert_eq(it.bonus, 1, "%s bonus" % iid)
		assert_has(["weapon", "armor", "shield"], it.kind, "%s kind" % iid)
		var raw := _raw("%s/%s.json" % [ITEMS_DIR, iid])
		assert_eq([raw.get("magic"), raw.get("mechanic")], [true, "bonus"], "%s magic item schema" % iid)


func test_door_keys() -> void:
	for colour in ["bronze", "iron", "silver", "brass", "copper", "bone"]:
		var it := _item("key_" + colour)
		assert_not_null(it, "key_" + colour)
		if it == null:
			continue
		assert_eq([it.kind, it.display_name, it.weight, it.value_gp, it.stackable],
			["key", "%s Key" % colour.capitalize(), 0.1, 1.0, false], "key_" + colour)
		assert_eq(it.description, "Opens a matching lock on this floor.")

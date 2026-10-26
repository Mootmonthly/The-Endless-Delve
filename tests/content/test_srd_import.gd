extends TestCase
## The bulk SRD 5.1 import (tools/import_srd.py): every imported monster,
## weapon and item loads through ContentLoader, monster fields have the shapes
## the rules engine reads (creature_type, multiattack names, loot table by CR
## band), magic items carry rarity / attunement / mechanic, and re-running the
## importer against its cache reproduces data/ exactly (skipped when the
## gitignored cache or python3 is not available, e.g. on CI).

const MONSTERS_DIR := "res://data/monsters"
const ITEMS_DIR := "res://data/items"
const WEAPONS_DIR := "res://data/weapons"
const SPELLS_DIR := "res://data/spells"
const SIZES: Array[String] = ["tiny", "small", "medium", "large", "huge", "gargantuan"]
const CREATURE_TYPES: Array[String] = [
	"aberration", "beast", "celestial", "construct", "dragon", "elemental", "fey", "fiend", "giant",
	"humanoid", "monstrosity", "ooze", "plant", "undead",
]
const TRAIT_KINDS: Array[String] = ["trait", "action", "reaction", "legendary_action"]
const RARITIES: Array[String] = ["common", "uncommon", "rare", "very rare", "legendary", "artifact"]
const ITEM_MECHANICS: Array[String] = ["implemented", "unsupported", "bonus"]

var _monsters: Dictionary = {}
var _items: Dictionary = {}
var _weapons: Dictionary = {}


func before_each() -> void:
	if _monsters.is_empty():
		_monsters = ContentLoader.load_monsters(MONSTERS_DIR)
		_weapons = ContentLoader.load_weapons(WEAPONS_DIR)
		_items = ContentLoader.load_items(ITEMS_DIR)


func _raw(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var d: Dictionary = parsed
	return d


func _band(cr: float) -> String:
	if cr <= 0.25:
		return "monster_small"
	if cr <= 2.0:
		return "monster_medium"
	return "boss"


func test_every_record_loads() -> void:
	var monster_files := ContentLoader.json_files(MONSTERS_DIR)
	assert_true(monster_files.size() >= 300, "the SRD bestiary is imported (%d)" % monster_files.size())
	assert_eq(_monsters.size(), monster_files.size(), "every monster loads")
	assert_eq(_weapons.size(), ContentLoader.json_files(WEAPONS_DIR).size(), "every weapon loads")
	assert_true(_weapons.size() >= 36, "every SRD weapon with damage is imported (%d)" % _weapons.size())
	assert_eq(_items.size(), ContentLoader.json_files(ITEMS_DIR).size(), "every item loads")
	assert_true(_items.size() >= 500, "SRD equipment and magic items are imported (%d)" % _items.size())
	var spells := ContentLoader.load_spells(SPELLS_DIR)
	assert_eq(spells.size(), ContentLoader.json_files(SPELLS_DIR).size(), "every spell loads")
	assert_true(spells.size() >= 319, "every SRD class spell is imported (%d)" % spells.size())


func test_monster_fields() -> void:
	for path in ContentLoader.json_files(MONSTERS_DIR):
		var raw := _raw(path)
		var mid := path.get_file().get_basename()
		var ctx := "monster %s" % mid
		assert_eq(str(raw.get("id", "")), mid, "%s: id matches the file" % ctx)
		assert_has(CREATURE_TYPES, str(raw.get("creature_type", "")), "%s creature_type" % ctx)
		assert_has(SIZES, str(raw.get("size", "")), "%s size" % ctx)
		var attack_names: Array[String] = []
		for a in DictUtil.to_dict_array(raw.get("attacks", [])):
			attack_names.append(str(a.get("name", "")))
			assert_has(["melee", "ranged"], str(a.get("kind", "")), "%s attack kind" % ctx)
			if str(a.get("kind", "")) == "melee" and a.has("range_ft"):
				var r := DictUtil.to_int_array(a["range_ft"])
				assert_eq(r, [DictUtil.to_int(a.get("reach_ft", 5)), DictUtil.to_int(a.get("reach_ft", 5))] as Array[int],
						"%s: melee range_ft is its reach" % ctx)
		for name in DictUtil.to_string_array(raw.get("multiattack", [])):
			assert_has(attack_names, name, "%s: multiattack names an attack" % ctx)
		if raw.has("multiattack"):
			assert_true(DictUtil.to_string_array(raw["multiattack"]).size() >= 1 or raw.has("multiattack_text"), "%s multiattack" % ctx)
		for t in DictUtil.to_dict_array(raw.get("traits", [])):
			assert_ne(str(t.get("name", "")), "", "%s trait name" % ctx)
		if DictUtil.to_bool(raw.get("hand_edited", false), false):
			continue
		assert_eq(str(raw.get("loot_table", "")), _band(DictUtil.to_float(raw.get("challenge_rating", 0.0))), "%s loot table by CR" % ctx)
		assert_eq(str(raw.get("source", "")), "SRD 5.1", "%s source" % ctx)
		assert_true(typeof(raw.get("speeds")) == TYPE_DICTIONARY, "%s speeds" % ctx)
		for t in DictUtil.to_dict_array(raw.get("traits", [])):
			assert_has(TRAIT_KINDS, str(t.get("kind", "")), "%s trait kind" % ctx)
			assert_eq(str(t.get("mechanic", "")), "unsupported", "%s trait mechanic" % ctx)
	# The SRD stat blocks the floors use keep their hand-tuned numbers and gain the type.
	for mid in ["giant_rat", "goblin", "kobold", "skeleton", "zombie", "ghoul", "ogre"]:
		var raw := _raw("%s/%s.json" % [MONSTERS_DIR, mid])
		assert_true(DictUtil.to_bool(raw.get("hand_edited", false), false), "%s is hand-edited" % mid)
	var want_types := {"skeleton": "undead", "zombie": "undead", "ghoul": "undead", "ogre": "giant", "goblin": "humanoid", "giant_rat": "beast"}
	for mid: String in want_types.keys():
		var m: MonsterDefinition = _monsters.get(mid)
		assert_not_null(m, mid)
		if m != null:
			assert_eq(str(_raw("%s/%s.json" % [MONSTERS_DIR, mid]).get("creature_type", "")), str(want_types[mid]), "%s type" % mid)
	var dragon := _raw(MONSTERS_DIR + "/adult_red_dragon.json")
	assert_eq(DictUtil.to_string_array(dragon.get("multiattack", [])), ["Bite", "Claw", "Claw"] as Array[String], "dragon multiattack")
	assert_eq(DictUtil.to_int(dragon.get("speed", 0), 0), 40, "speed is the walking speed")
	assert_eq(DictUtil.to_int(dragon.get("speeds", {}).get("fly", 0), 0), 80, "speeds keeps flying")


func test_weapons_and_gear() -> void:
	var expect := {
		"greatsword": ["2d6", "slashing", "martial"], "heavy_crossbow": ["1d10", "piercing", "martial"],
		"hand_crossbow": ["1d6", "piercing", "martial"], "halberd": ["1d10", "slashing", "martial"],
		"whip": ["1d4", "slashing", "martial"], "sickle": ["1d4", "slashing", "simple"],
	}
	for wid: String in expect.keys():
		var w: WeaponDefinition = _weapons.get(wid)
		assert_not_null(w, "weapon %s" % wid)
		if w != null:
			var e: Array = expect[wid]
			assert_eq([w.damage, w.damage_type, w.category], [str(e[0]), str(e[1]), str(e[2])], wid)
	var heavy: WeaponDefinition = _weapons.get("heavy_crossbow")
	if heavy != null:
		assert_eq(heavy.range_ft, [100, 400] as Array[int], "heavy crossbow range")
		assert_eq(heavy.ammo_id, "bolts", "heavy crossbow fires bolts")
	for iid in ["blowgun_needles", "half_plate_armor", "ring_mail", "backpack", "explorers_pack", "net"]:
		assert_true(_items.has(iid), "item %s" % iid)
	var half_plate: ItemDefinition = _items.get("half_plate_armor")
	if half_plate != null:
		assert_eq([half_plate.armor_base, half_plate.armor_max_dex, half_plate.armor_category], [15, 2, "medium"], "half plate")


func test_magic_items() -> void:
	var magic := 0
	for path in ContentLoader.json_files(ITEMS_DIR):
		var raw := _raw(path)
		if not DictUtil.to_bool(raw.get("magic", false), false):
			continue
		magic += 1
		var ctx := "magic item %s" % raw.get("id", "")
		assert_has(RARITIES, str(raw.get("rarity", "")), "%s rarity" % ctx)
		assert_eq(typeof(raw.get("requires_attunement")), TYPE_BOOL, "%s requires_attunement" % ctx)
		assert_has(ITEM_MECHANICS, str(raw.get("mechanic", "")), "%s mechanic" % ctx)
		assert_ne(str(raw.get("description", "")), "", "%s description" % ctx)
		if str(raw.get("mechanic", "")) == "bonus":
			assert_in_range(DictUtil.to_int(raw.get("bonus", 0), 0), 1, 3, "%s bonus" % ctx)
	assert_true(magic >= 300, "SRD magic items are imported (%d)" % magic)
	for n in [1, 2, 3]:
		for kind in ["weapon", "armor", "ammunition"]:
			var raw := _raw("%s/%s_plus_%d.json" % [ITEMS_DIR, kind, n])
			assert_eq([raw.get("bonus"), raw.get("bonus_applies_to")], [n, kind], "%s +%d" % [kind, n])
	var potions := {"potion_of_healing": "2d4+2", "potion_of_greater_healing": "4d4+4",
			"potion_of_superior_healing": "8d4+8", "potion_of_supreme_healing": "10d4+20"}
	for pid: String in potions.keys():
		var it: ItemDefinition = _items.get(pid)
		assert_not_null(it, pid)
		if it != null:
			assert_eq([it.kind, it.use_effect, it.use_dice], ["consumable", "heal", str(potions[pid])], pid)
	var bag := _raw(ITEMS_DIR + "/bag_of_holding.json")
	assert_eq([bag.get("rarity"), bag.get("requires_attunement"), bag.get("mechanic")], ["uncommon", false, "unsupported"], "bag of holding")


func test_importer_is_deterministic() -> void:
	var cache := ProjectSettings.globalize_path("res://tools/srd_cache")
	var script := ProjectSettings.globalize_path("res://tools/import_srd.py")
	if not DirAccess.dir_exists_absolute(cache):
		print("    (skipped: tools/srd_cache is not present; run python3 -I tools/import_srd.py once)")
		return
	var output: Array = []
	var code := OS.execute("python3", ["-I", script, "--check"], output, true)
	if code == -1:
		print("    (skipped: python3 is not available)")
		return
	assert_eq(code, 0, "import_srd --check: two runs match each other and data/\n%s" % "\n".join(output))

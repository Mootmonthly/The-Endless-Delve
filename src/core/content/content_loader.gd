class_name ContentLoader
extends RefCounted
## Loads data/*.json into typed definition objects. Invalid files are skipped
## with push_error so one bad file never takes down the whole content set.
##
## cache() loads everything under res://data once and returns the shared
## content dictionary {"classes", "ancestries", "weapons", "items", "spells",
## "loot_tables", "monsters"} (each id -> definition), plus the record folders
## {"features", "invocations", "metamagic", "fighting_styles"} (each id -> the
## JSON object, with at least "id" and "mechanic"). Rules code that needs
## definitions takes such a dictionary (tests pass hand-built ones).

const DATA_ROOT := "res://data"
const CONTENT_KEYS: Array[String] = ["classes", "ancestries", "weapons", "items", "spells", "loot_tables", "monsters", "features", "invocations", "metamagic", "fighting_styles"]
## Folders loaded as plain records (id -> Dictionary) by load_records().
const RECORD_KEYS: Array[String] = ["features", "invocations", "metamagic", "fighting_styles"]

static var _cache: Dictionary = {}


## Returns the parsed top-level object, or {} (with push_error) on failure.
static func load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("ContentLoader: file not found: %s" % path)
		return {}
	var text := FileAccess.get_file_as_string(path)
	var parser := JSON.new()
	var err := parser.parse(text)
	if err != OK:
		push_error("ContentLoader: %s line %d: %s" % [path, parser.get_error_line(), parser.get_error_message()])
		return {}
	if typeof(parser.data) != TYPE_DICTIONARY:
		push_error("ContentLoader: %s: top level must be an object" % path)
		return {}
	var result: Dictionary = parser.data
	return result


## id -> ClassDefinition for every *.json file in dir_path. Each class's
## starting_weapon id is resolved against the weapons in weapons_dir.
static func load_classes(dir_path: String = "res://data/classes", weapons_dir: String = "res://data/weapons") -> Dictionary:
	var weapons := ContentLoader.load_weapons(weapons_dir)
	var result := {}
	for path in ContentLoader.json_files(dir_path):
		var data := ContentLoader.load_json(path)
		if data.is_empty():
			continue
		var def := ClassDefinition.from_dict(data)
		if def == null:
			push_error("ContentLoader: skipping invalid class file %s" % path)
			continue
		if result.has(def.id):
			push_error("ContentLoader: duplicate class id '%s' in %s" % [def.id, path])
			continue
		if not def.starting_weapon.is_empty():
			if weapons.has(def.starting_weapon):
				var weapon: WeaponDefinition = weapons[def.starting_weapon]
				def.starting_weapon_def = weapon
			else:
				push_error("ContentLoader: class '%s' starting weapon '%s' not found" % [def.id, def.starting_weapon])
		result[def.id] = def
	return result


## id -> AncestryDefinition for every *.json file in dir_path.
static func load_ancestries(dir_path: String = "res://data/ancestries") -> Dictionary:
	var result := {}
	for path in ContentLoader.json_files(dir_path):
		var data := ContentLoader.load_json(path)
		if data.is_empty():
			continue
		var def := AncestryDefinition.from_dict(data)
		if def == null:
			push_error("ContentLoader: skipping invalid ancestry file %s" % path)
			continue
		if result.has(def.id):
			push_error("ContentLoader: duplicate ancestry id '%s' in %s" % [def.id, path])
			continue
		result[def.id] = def
	return result


## id -> WeaponDefinition for every *.json file in dir_path.
static func load_weapons(dir_path: String = "res://data/weapons") -> Dictionary:
	var result := {}
	for path in ContentLoader.json_files(dir_path):
		var data := ContentLoader.load_json(path)
		if data.is_empty():
			continue
		var def := WeaponDefinition.from_dict(data)
		if def == null:
			push_error("ContentLoader: skipping invalid weapon file %s" % path)
			continue
		if result.has(def.id):
			push_error("ContentLoader: duplicate weapon id '%s' in %s" % [def.id, path])
			continue
		result[def.id] = def
	return result


## id -> MonsterDefinition for every *.json file in dir_path.
static func load_monsters(dir_path: String = "res://data/monsters") -> Dictionary:
	var result := {}
	for path in ContentLoader.json_files(dir_path):
		var data := ContentLoader.load_json(path)
		if data.is_empty():
			continue
		var def := MonsterDefinition.from_dict(data)
		if def == null:
			push_error("ContentLoader: skipping invalid monster file %s" % path)
			continue
		if result.has(def.id):
			push_error("ContentLoader: duplicate monster id '%s' in %s" % [def.id, path])
			continue
		result[def.id] = def
	return result


## id -> ItemDefinition for every *.json file in dir_path.
static func load_items(dir_path: String = "res://data/items") -> Dictionary:
	var result := {}
	for path in ContentLoader.json_files(dir_path):
		var data := ContentLoader.load_json(path)
		if data.is_empty():
			continue
		var def := ItemDefinition.from_dict(data)
		if def == null:
			push_error("ContentLoader: skipping invalid item file %s" % path)
			continue
		if result.has(def.id):
			push_error("ContentLoader: duplicate item id '%s' in %s" % [def.id, path])
			continue
		result[def.id] = def
	return result


## id -> SpellDefinition for every *.json file in dir_path.
static func load_spells(dir_path: String = "res://data/spells") -> Dictionary:
	var result := {}
	for path in ContentLoader.json_files(dir_path):
		var data := ContentLoader.load_json(path)
		if data.is_empty():
			continue
		var def := SpellDefinition.from_dict(data)
		if def == null:
			push_error("ContentLoader: skipping invalid spell file %s" % path)
			continue
		if result.has(def.id):
			push_error("ContentLoader: duplicate spell id '%s' in %s" % [def.id, path])
			continue
		result[def.id] = def
	return result


## id -> LootTable for every *.json file in dir_path.
static func load_loot_tables(dir_path: String = "res://data/loot") -> Dictionary:
	var result := {}
	for path in ContentLoader.json_files(dir_path):
		var data := ContentLoader.load_json(path)
		if data.is_empty():
			continue
		var def := LootTable.from_dict(data)
		if def == null:
			push_error("ContentLoader: skipping invalid loot table file %s" % path)
			continue
		if result.has(def.id):
			push_error("ContentLoader: duplicate loot table id '%s' in %s" % [def.id, path])
			continue
		result[def.id] = def
	return result


## id -> JSON object for every *.json file in dir_path (needs a non-empty "id").
static func load_records(dir_path: String) -> Dictionary:
	var result := {}
	for path in ContentLoader.json_files(dir_path):
		var data := ContentLoader.load_json(path)
		if data.is_empty():
			continue
		var record_id := str(data.get("id", ""))
		if record_id.is_empty():
			push_error("ContentLoader: %s has no id" % path)
			continue
		if result.has(record_id):
			push_error("ContentLoader: duplicate id '%s' in %s" % [record_id, path])
			continue
		result[record_id] = data
	return result


## Loads every content folder under root (a missing folder gives an empty
## dictionary without an error). Shape: see cache().
static func load_all(root: String = DATA_ROOT) -> Dictionary:
	var out := {}
	for key in CONTENT_KEYS:
		out[key] = {}
	var weapons_dir := root.path_join("weapons")
	if DirAccess.dir_exists_absolute(weapons_dir):
		out["weapons"] = ContentLoader.load_weapons(weapons_dir)
	if DirAccess.dir_exists_absolute(root.path_join("classes")):
		out["classes"] = ContentLoader.load_classes(root.path_join("classes"), weapons_dir)
	if DirAccess.dir_exists_absolute(root.path_join("ancestries")):
		out["ancestries"] = ContentLoader.load_ancestries(root.path_join("ancestries"))
	if DirAccess.dir_exists_absolute(root.path_join("items")):
		out["items"] = ContentLoader.load_items(root.path_join("items"))
	if DirAccess.dir_exists_absolute(root.path_join("spells")):
		out["spells"] = ContentLoader.load_spells(root.path_join("spells"))
	if DirAccess.dir_exists_absolute(root.path_join("loot")):
		out["loot_tables"] = ContentLoader.load_loot_tables(root.path_join("loot"))
	if DirAccess.dir_exists_absolute(root.path_join("monsters")):
		out["monsters"] = ContentLoader.load_monsters(root.path_join("monsters"))
	for key in RECORD_KEYS:
		if DirAccess.dir_exists_absolute(root.path_join(key)):
			out[key] = ContentLoader.load_records(root.path_join(key))
	return out


## The shared content set from res://data, loaded on first use.
static func cache() -> Dictionary:
	if _cache.is_empty():
		_cache = ContentLoader.load_all(DATA_ROOT)
	return _cache


## Forgets the cached content (the next cache() reloads res://data).
static func clear_cache() -> void:
	_cache = {}


## A content dictionary with every CONTENT_KEYS entry present: missing keys
## are filled with {}. Pass {} to get cache().
static func resolve(content: Dictionary) -> Dictionary:
	if content.is_empty():
		return ContentLoader.cache()
	for key in CONTENT_KEYS:
		if not content.has(key):
			content[key] = {}
	return content


## Cross-references between content files: weapon items -> weapons, ammo ids,
## class kits / prepared spells / spell lists, monster loot tables, loot
## table items. Returns one line per problem (empty = consistent).
static func validate_references(content: Dictionary) -> Array[String]:
	var c := ContentLoader.resolve(content)
	var problems: Array[String] = []
	var weapons: Dictionary = c["weapons"]
	var items: Dictionary = c["items"]
	var spells: Dictionary = c["spells"]
	var loot: Dictionary = c["loot_tables"]
	var classes: Dictionary = c["classes"]
	var monsters: Dictionary = c["monsters"]
	for item_v: Variant in items.values():
		var it: ItemDefinition = item_v
		if it.kind == ItemDefinition.KIND_WEAPON and not weapons.has(it.weapon_id):
			problems.append("item '%s': unknown weapon_id '%s'" % [it.id, it.weapon_id])
		if not it.ammo_id.is_empty() and not items.has(it.ammo_id):
			problems.append("item '%s': unknown ammo_id '%s'" % [it.id, it.ammo_id])
	for weapon_v: Variant in weapons.values():
		var w: WeaponDefinition = weapon_v
		if not w.ammo_id.is_empty() and not items.is_empty() and not items.has(w.ammo_id):
			problems.append("weapon '%s': unknown ammo_id '%s'" % [w.id, w.ammo_id])
	for cls_v: Variant in classes.values():
		var cls: ClassDefinition = cls_v
		for entry in cls.starting_kit:
			if not items.has(str(entry["item"])):
				problems.append("class '%s': unknown kit item '%s'" % [cls.id, str(entry["item"])])
		var class_spells: Array[String] = cls.spells_prepared.duplicate()
		class_spells.append_array(cls.spell_list)
		for spell_id in class_spells:
			if not spells.has(spell_id):
				problems.append("class '%s': unknown spell '%s'" % [cls.id, spell_id])
		if not cls.starting_armor_item.is_empty() and not items.has(cls.starting_armor_item):
			problems.append("class '%s': unknown starting armor item '%s'" % [cls.id, cls.starting_armor_item])
	for mon_v: Variant in monsters.values():
		var m: MonsterDefinition = mon_v
		if not m.loot_table.is_empty() and not loot.has(m.loot_table):
			problems.append("monster '%s': unknown loot_table '%s'" % [m.id, m.loot_table])
	for table_v: Variant in loot.values():
		var t: LootTable = table_v
		for item_id in t.item_ids():
			if not items.has(item_id):
				problems.append("loot table '%s': unknown item '%s'" % [t.id, item_id])
	problems.sort()
	return problems


## Sorted list of *.json paths directly inside dir_path.
static func json_files(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_error("ContentLoader: cannot open directory %s (error %d)" % [dir_path, DirAccess.get_open_error()])
		return out
	for file_name: String in dir.get_files():
		if file_name.get_extension().to_lower() == "json":
			out.append(dir_path.path_join(file_name))
	out.sort()
	return out

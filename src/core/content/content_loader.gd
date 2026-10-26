class_name ContentLoader
extends RefCounted
## Loads data/*.json into typed definition objects. Invalid files are skipped
## with push_error so one bad file never takes down the whole content set.


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

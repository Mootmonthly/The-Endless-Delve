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


## id -> ClassDefinition for every *.json file in dir_path.
static func load_classes(dir_path: String = "res://data/classes") -> Dictionary:
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

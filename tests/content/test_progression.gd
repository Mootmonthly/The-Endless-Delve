extends TestCase
## Class progression to level 20 (imported by tools/import_srd.py from the
## SRD 5.1 dataset): every feature id in a class or subclass progression has a
## data/features file, feature "mechanic" follows Features.IMPLEMENTED, slot
## and class tables cover levels 1-20 with the SRD numbers, and invocations,
## metamagic, fighting styles and subclass spells reference content that exists.

const CLASSES_DIR := "res://data/classes"
const FEATURES_DIR := "res://data/features"
const SPELLS_DIR := "res://data/spells"
const FEATURES_GD := "res://src/core/rules/features.gd"
const CLASS_IDS: Array[String] = [
	"barbarian", "bard", "cleric", "druid", "fighter", "monk",
	"paladin", "ranger", "rogue", "sorcerer", "warlock", "wizard",
]
## The one SRD 5.1 subclass per class: id and the class level it is chosen at.
const SUBCLASSES: Dictionary = {
	"barbarian": ["berserker", 3], "bard": ["lore", 3], "cleric": ["life", 1], "druid": ["land", 2],
	"fighter": ["champion", 3], "monk": ["open_hand", 3], "paladin": ["devotion", 3], "ranger": ["hunter", 3],
	"rogue": ["thief", 3], "sorcerer": ["draconic", 1], "warlock": ["fiend", 1], "wizard": ["evocation", 2],
}
const FULL_CASTERS: Array[String] = ["bard", "cleric", "druid", "sorcerer", "wizard"]
const HALF_CASTERS: Array[String] = ["paladin", "ranger"]
const MECHANICS: Array[String] = ["implemented", "unsupported"]
## Tables the brief names, per class (each keyed "1".."20").
const REQUIRED_TABLES: Dictionary = {
	"barbarian": ["rage_uses", "rage_damage", "extra_attacks"], "bard": ["bardic_inspiration_die"],
	"cleric": ["channel_divinity_uses"], "fighter": ["extra_attacks"],
	"monk": ["martial_arts_die", "ki_points", "unarmored_movement", "extra_attacks"],
	"paladin": ["lay_on_hands_pool", "aura_radius", "channel_divinity_uses", "extra_attacks"],
	"ranger": ["extra_attacks"], "rogue": ["sneak_attack_dice"], "sorcerer": ["sorcery_points"],
	"warlock": ["invocations_known"],
}

var _classes: Dictionary = {}
var _features: Dictionary = {}
var _spells: Dictionary = {}
var _implemented: Dictionary = {}


func before_each() -> void:
	if not _classes.is_empty():
		return
	for cid in CLASS_IDS:
		_classes[cid] = _raw("%s/%s.json" % [CLASSES_DIR, cid])
	_features = _load_dir(FEATURES_DIR)
	_spells = _load_dir(SPELLS_DIR)
	# Every IMPLEMENTED* constant of Features (the importer reads them all).
	var script: Script = load(FEATURES_GD)
	var consts: Dictionary = script.get_script_constant_map()
	for key: String in consts.keys():
		if key.begins_with("IMPLEMENTED") and typeof(consts[key]) == TYPE_ARRAY:
			for fid: Variant in consts[key]:
				_implemented[str(fid)] = true


func _raw(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var d: Dictionary = parsed
	return d


func _load_dir(dir: String) -> Dictionary:
	var out := {}
	for path in ContentLoader.json_files(dir):
		out[path.get_file().get_basename()] = _raw(path)
	return out


func _row(table: Variant, level: int) -> Variant:
	if typeof(table) != TYPE_DICTIONARY:
		return null
	var d: Dictionary = table
	return d.get(str(level))


func _levels_of(feature: Dictionary, cid: String) -> Array[int]:
	var by_class: Dictionary = feature.get("levels_by_class", {})
	if by_class.has(cid):
		return DictUtil.to_int_array(by_class[cid])
	if feature.has("levels"):
		return DictUtil.to_int_array(feature["levels"])
	return [DictUtil.to_int(feature.get("level", 0), 0)] as Array[int]


func _classes_of(feature: Dictionary) -> Array[String]:
	if feature.has("classes"):
		return DictUtil.to_string_array(feature["classes"])
	return [str(feature.get("class", ""))] as Array[String]


func test_every_progression_feature_has_a_file() -> void:
	for cid in CLASS_IDS:
		var fbl: Dictionary = _classes[cid].get("features_by_level", {})
		for lvl in range(1, 21):
			for fid in DictUtil.to_string_array(fbl.get(str(lvl), [])):
				assert_true(_features.has(fid), "%s L%d: feature '%s' has a file" % [cid, lvl, fid])
				if not _features.has(fid):
					continue
				var f: Dictionary = _features[fid]
				assert_has(_classes_of(f), cid, "%s: feature %s names the class" % [cid, fid])
				assert_has(_levels_of(f, cid), lvl, "%s: feature %s lists level %d" % [cid, fid, lvl])
		var sub: Dictionary = _classes[cid].get("subclass", {})
		var sfbl: Dictionary = sub.get("features_by_level", {})
		for lvl: String in sfbl.keys():
			for fid in DictUtil.to_string_array(sfbl[lvl]):
				assert_true(_features.has(fid), "%s subclass L%s: feature '%s' has a file" % [cid, lvl, fid])
				if _features.has(fid):
					var f: Dictionary = _features[fid]
					var sub_id := str(f.get("subclass", f.get("subclass_by_class", {}).get(cid, "")))
					assert_eq(sub_id, str(sub.get("id", "")), "%s: feature %s belongs to the subclass" % [cid, fid])


func test_feature_files_are_well_formed() -> void:
	assert_true(_features.size() >= 150, "every class and subclass feature is imported (%d)" % _features.size())
	var referenced := {}
	for cid in CLASS_IDS:
		var fbl: Dictionary = _classes[cid].get("features_by_level", {})
		for lvl: String in fbl.keys():
			for fid in DictUtil.to_string_array(fbl[lvl]):
				referenced[fid] = true
		var sfbl: Dictionary = _classes[cid].get("subclass", {}).get("features_by_level", {})
		for lvl: String in sfbl.keys():
			for fid in DictUtil.to_string_array(sfbl[lvl]):
				referenced[fid] = true
	for fid: String in _features.keys():
		var f: Dictionary = _features[fid]
		var ctx := "feature %s" % fid
		for key in ["schema_version", "id", "display_name", "class", "level", "description", "mechanic", "source"]:
			assert_true(f.has(key), "%s has '%s'" % [ctx, key])
		assert_eq(str(f.get("id", "")), fid, "%s: id matches the file name" % ctx)
		assert_eq(str(f.get("source", "")), "SRD 5.1", "%s source" % ctx)
		assert_ne(str(f.get("description", "")), "", "%s has SRD text" % ctx)
		assert_in_range(DictUtil.to_int(f.get("level", 0), 0), 1, 20, "%s level" % ctx)
		for cid in _classes_of(f):
			assert_has(CLASS_IDS, cid, "%s: class '%s'" % [ctx, cid])
		if f.has("option_of"):
			var parent := str(f["option_of"])
			assert_true(_features.has(parent), "%s: parent '%s' exists" % [ctx, parent])
			if _features.has(parent):
				assert_has(DictUtil.to_string_array(_features[parent].get("options", [])), fid, "%s is listed by its parent" % ctx)
		else:
			assert_true(referenced.has(fid), "%s is in some class or subclass progression" % ctx)
		for opt in DictUtil.to_string_array(f.get("options", [])):
			assert_true(_features.has(opt), "%s: option '%s' exists" % [ctx, opt])


func test_mechanic_follows_features_implemented() -> void:
	assert_false(_implemented.is_empty(), "Features.IMPLEMENTED is readable")
	for fid: String in _features.keys():
		var m := str(_features[fid].get("mechanic", ""))
		assert_has(MECHANICS, m, "feature %s mechanic" % fid)
		assert_eq(m == "implemented", _implemented.has(fid), "feature %s: implemented iff in Features.IMPLEMENTED" % fid)
	for dir in ["res://data/invocations", "res://data/metamagic", "res://data/fighting_styles"]:
		for path in ContentLoader.json_files(dir):
			assert_has(MECHANICS, str(_raw(path).get("mechanic", "")), "%s mechanic" % path)


func test_subclasses_match_the_srd() -> void:
	for cid in CLASS_IDS:
		var sub: Dictionary = _classes[cid].get("subclass", {})
		var want: Array = SUBCLASSES[cid]
		assert_eq(str(sub.get("id", "")), str(want[0]), "%s subclass" % cid)
		assert_eq(DictUtil.to_int(sub.get("level", 0), 0), int(want[1]), "%s subclass level" % cid)
		assert_ne(str(sub.get("display_name", "")), "", "%s subclass name" % cid)
		assert_ne(str(sub.get("description", "")), "", "%s subclass description" % cid)
		var sfbl: Dictionary = sub.get("features_by_level", {})
		assert_true(sfbl.has(str(want[1])), "%s subclass grants features at level %d" % [cid, int(want[1])])
		var spell_tables: Array = []
		if sub.has("spells_by_level"):
			spell_tables.append(sub["spells_by_level"])
		var terrains: Dictionary = sub.get("spells_by_terrain", {})
		for t: String in terrains.keys():
			spell_tables.append(terrains[t])
		for table: Dictionary in spell_tables:
			for lvl: String in table.keys():
				for sid in DictUtil.to_string_array(table[lvl]):
					assert_true(_spells.has(sid), "%s subclass spell '%s' exists" % [cid, sid])
	assert_eq(DictUtil.to_string_array(_classes["cleric"]["subclass"].get("spells_by_level", {}).get("1", [])),
			["bless", "cure_wounds"] as Array[String], "life domain spells at cleric 1")
	assert_eq(_classes["druid"]["subclass"].get("spells_by_terrain", {}).size(), 7, "seven circle-of-the-land terrains")


func test_asi_levels() -> void:
	for cid in CLASS_IDS:
		var want: Array[int] = [4, 8, 12, 16, 19]
		if cid == "fighter":
			want = [4, 6, 8, 12, 14, 16, 19]
		elif cid == "rogue":
			want = [4, 8, 10, 12, 16, 19]
		assert_eq(DictUtil.to_int_array(_classes[cid].get("asi_levels", [])), want, "%s asi_levels" % cid)


func test_slot_tables_cover_twenty_levels() -> void:
	for cid in CLASS_IDS:
		var raw: Dictionary = _classes[cid]
		var caster := FULL_CASTERS.has(cid) or HALF_CASTERS.has(cid) or cid == "warlock"
		assert_eq(raw.has("spell_slots"), caster, "%s has spell_slots iff it casts" % cid)
		if not caster:
			continue
		var slots: Dictionary = raw["spell_slots"]
		assert_eq(slots.size(), 20, "%s spell_slots has 20 rows" % cid)
		for lvl in range(1, 21):
			assert_true(slots.has(str(lvl)), "%s spell_slots level %d" % [cid, lvl])
			assert_true(DictUtil.to_int_array(slots.get(str(lvl), [])).size() <= 9, "%s level %d: at most 9 slot levels" % [cid, lvl])
	for cid in FULL_CASTERS:
		assert_eq(DictUtil.to_int_array(_row(_classes[cid]["spell_slots"], 20)), [4, 3, 3, 3, 3, 2, 2, 1, 1] as Array[int],
				"%s: full caster slots at 20" % cid)
		assert_eq(DictUtil.to_int_array(_row(_classes[cid]["spell_slots"], 1)), [2] as Array[int], "%s: slots at 1" % cid)
	for cid in HALF_CASTERS:
		assert_eq(DictUtil.to_int_array(_row(_classes[cid]["spell_slots"], 1)), [] as Array[int], "%s: no slots at 1" % cid)
		assert_eq(DictUtil.to_int_array(_row(_classes[cid]["spell_slots"], 2)), [2] as Array[int], "%s: slots at 2" % cid)
		assert_eq(DictUtil.to_int_array(_row(_classes[cid]["spell_slots"], 20)), [4, 3, 3, 3, 2] as Array[int],
				"%s: half caster slots at 20" % cid)
	var pact: Dictionary = _classes["warlock"]["spell_slots"]
	assert_eq(DictUtil.to_int_array(_row(pact, 20)), [0, 0, 0, 0, 4] as Array[int], "warlock: four 5th-level pact slots at 20")
	assert_eq(DictUtil.to_int_array(_row(pact, 11)), [0, 0, 0, 0, 3] as Array[int], "warlock: three pact slots at 11")


func test_class_tables_cover_levels_one_to_twenty() -> void:
	for cid in CLASS_IDS:
		var tables: Dictionary = _classes[cid].get("tables", {})
		for name in REQUIRED_TABLES.get(cid, []):
			assert_true(tables.has(name), "%s has table %s" % [cid, name])
		for name: String in tables.keys():
			var t: Dictionary = tables[name]
			assert_eq(t.size(), 20, "%s.%s has 20 rows" % [cid, name])
			for lvl in range(1, 21):
				assert_true(DictUtil.is_number(t.get(str(lvl))), "%s.%s level %d is a number" % [cid, name, lvl])
	var t: Dictionary = _classes["fighter"]["tables"]["extra_attacks"]
	assert_eq([t["4"], t["5"], t["11"], t["20"]], [0, 1, 2, 3], "fighter extra attacks 5/11/20")
	for cid in ["barbarian", "monk", "paladin", "ranger"]:
		var e: Dictionary = _classes[cid]["tables"]["extra_attacks"]
		assert_eq([e["4"], e["5"], e["20"]], [0, 1, 1], "%s extra attack at 5" % cid)
	var bar: Dictionary = _classes["barbarian"]["tables"]
	assert_eq([bar["rage_uses"]["1"], bar["rage_uses"]["3"], bar["rage_uses"]["6"], bar["rage_uses"]["17"]], [2, 3, 4, 6], "rage uses")
	assert_eq([bar["rage_damage"]["1"], bar["rage_damage"]["9"], bar["rage_damage"]["16"]], [2, 3, 4], "rage damage")
	var sneak: Dictionary = _classes["rogue"]["tables"]["sneak_attack_dice"]
	assert_eq([sneak["1"], sneak["2"], sneak["3"], sneak["5"], sneak["20"]], [1, 1, 2, 3, 10], "sneak attack dice")
	var monk: Dictionary = _classes["monk"]["tables"]
	assert_eq([monk["martial_arts_die"]["1"], monk["martial_arts_die"]["5"], monk["martial_arts_die"]["11"], monk["martial_arts_die"]["17"]], [4, 6, 8, 10], "martial arts die")
	assert_eq([monk["ki_points"]["1"], monk["ki_points"]["2"], monk["ki_points"]["20"]], [0, 2, 20], "ki points")
	assert_eq([monk["unarmored_movement"]["1"], monk["unarmored_movement"]["2"], monk["unarmored_movement"]["18"]], [0, 10, 30], "unarmored movement")
	var bard: Dictionary = _classes["bard"]["tables"]["bardic_inspiration_die"]
	assert_eq([bard["1"], bard["5"], bard["10"], bard["15"]], [6, 8, 10, 12], "bardic inspiration die")
	var cd: Dictionary = _classes["cleric"]["tables"]["channel_divinity_uses"]
	assert_eq([cd["1"], cd["2"], cd["6"], cd["18"]], [0, 1, 2, 3], "cleric channel divinity")
	var pal: Dictionary = _classes["paladin"]["tables"]
	assert_eq([pal["lay_on_hands_pool"]["1"], pal["lay_on_hands_pool"]["20"]], [5, 100], "lay on hands pool = 5 x level")
	assert_eq([pal["aura_radius"]["5"], pal["aura_radius"]["6"], pal["aura_radius"]["18"]], [0, 10, 30], "aura radius")
	var sorc: Dictionary = _classes["sorcerer"]["tables"]["sorcery_points"]
	assert_eq([sorc["1"], sorc["2"], sorc["20"]], [0, 2, 20], "sorcery points")
	var inv: Dictionary = _classes["warlock"]["invocations_known"]
	assert_eq([inv["1"], inv["2"], inv["5"], inv["7"], inv["9"], inv["12"], inv["15"], inv["18"]], [0, 2, 3, 4, 5, 6, 7, 8], "invocations known")
	var meta: Dictionary = _classes["sorcerer"]["metamagic_known"]
	assert_eq([meta["2"], meta["3"], meta["10"], meta["17"]], [0, 2, 3, 4], "metamagic known")


func test_known_casters_and_spell_lists() -> void:
	for cid in ["bard", "ranger", "sorcerer", "warlock"]:
		var known: Dictionary = _classes[cid].get("spells_known", {})
		assert_eq(known.size(), 20, "%s spells_known to 20" % cid)
	assert_eq([_classes["bard"]["spells_known"]["20"], _classes["sorcerer"]["spells_known"]["20"],
			_classes["warlock"]["spells_known"]["20"], _classes["ranger"]["spells_known"]["20"]], [22, 15, 15, 11], "spells known at 20")
	for cid in ["cleric", "druid", "paladin", "wizard"]:
		assert_true(DictUtil.to_bool(_classes[cid].get("prepares", false), false), "%s prepares" % cid)
	var total := {}
	for cid in CLASS_IDS:
		for sid in DictUtil.to_string_array(_classes[cid].get("spell_list", [])):
			assert_true(_spells.has(sid), "%s spell_list: '%s' exists" % [cid, sid])
			total[sid] = true
	assert_true(total.size() >= 300, "class lists cover the SRD spells (%d)" % total.size())
	var levels := {}
	for sid in DictUtil.to_string_array(_classes["wizard"].get("spell_list", [])):
		levels[DictUtil.to_int(_spells.get(sid, {}).get("level", -1), -1)] = true
	for lvl in range(0, 10):
		assert_true(levels.has(lvl), "the wizard list has level-%d spells" % lvl)


func test_fighting_styles_expertise_invocations_metamagic() -> void:
	var styles := ContentLoader.json_files("res://data/fighting_styles")
	assert_eq(styles.size(), 6, "six SRD fighting styles")
	var want_styles := {
		"fighter": ["archery", "defense", "dueling", "great_weapon_fighting", "protection", "two_weapon_fighting"],
		"paladin": ["defense", "dueling", "great_weapon_fighting", "protection"],
		"ranger": ["archery", "defense", "dueling", "two_weapon_fighting"],
	}
	for cid: String in want_styles.keys():
		var have := DictUtil.to_string_array(_classes[cid].get("fighting_styles", []))
		assert_eq(have, DictUtil.to_string_array(want_styles[cid]), "%s fighting styles" % cid)
		for sid in have:
			assert_true(FileAccess.file_exists("res://data/fighting_styles/%s.json" % sid), "fighting style %s file" % sid)
	assert_eq(_classes["rogue"].get("expertise_levels"), {"1": 2, "6": 2}, "rogue expertise")
	assert_eq(_classes["bard"].get("expertise_levels"), {"3": 2, "10": 2}, "bard expertise")
	var invocations := ContentLoader.json_files("res://data/invocations")
	assert_true(invocations.size() >= 30, "SRD invocations (%d)" % invocations.size())
	for path in invocations:
		var inv := _raw(path)
		var pre: Dictionary = inv.get("prerequisites", {})
		if pre.has("spell"):
			assert_true(_spells.has(str(pre["spell"])), "%s: prerequisite spell exists" % path)
		if pre.has("pact"):
			assert_true(_features.has(str(pre["pact"])), "%s: prerequisite pact exists" % path)
		assert_ne(str(inv.get("description", "")), "", "%s description" % path)
	for iid in ["agonizing_blast", "armor_of_shadows", "repelling_blast"]:
		assert_true(FileAccess.file_exists("res://data/invocations/%s.json" % iid), "invocation %s" % iid)
	var meta := ContentLoader.json_files("res://data/metamagic")
	assert_eq(meta.size(), 8, "eight SRD metamagic options")
	for mid in ["quickened_spell", "twinned_spell", "empowered_spell"]:
		assert_true(FileAccess.file_exists("res://data/metamagic/%s.json" % mid), "metamagic %s" % mid)

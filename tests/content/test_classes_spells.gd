extends TestCase
## Content checks for the twelve SRD classes and data/spells: every class
## parses with the required fields, kits and spell lists reference content
## that exists, spell slot and known/prepared tables are well-formed (levels
## 1-20, from tools/import_srd.py), and the level-1 feature ids CORE
## implements are where the addendum puts them. Progression details: see
## test_progression.gd.

const CLASSES_DIR := "res://data/classes"
const SPELLS_DIR := "res://data/spells"
const CLASS_IDS: Array[String] = [
	"barbarian", "bard", "cleric", "druid", "fighter", "monk",
	"paladin", "ranger", "rogue", "sorcerer", "warlock", "wizard",
]
const REQUIRED: Array[String] = [
	"schema_version", "id", "display_name", "description", "hit_die", "primary_abilities", "saving_throws",
	"armor_proficiencies", "weapon_proficiencies", "skill_choices", "skill_choice_count",
	"spellcasting_ability", "starting_weapon", "starting_armor", "starting_shield", "starting_kit",
	"features", "features_by_level", "spellcasting", "asi_levels", "subclass", "tables",
]
## SRD 5.1 hit die and saving throws per class.
const SRD: Dictionary = {
	"barbarian": [12, ["STR", "CON"]], "bard": [8, ["DEX", "CHA"]], "cleric": [8, ["WIS", "CHA"]],
	"druid": [8, ["INT", "WIS"]], "fighter": [10, ["STR", "CON"]], "monk": [8, ["STR", "DEX"]],
	"paladin": [10, ["WIS", "CHA"]], "ranger": [10, ["STR", "DEX"]], "rogue": [8, ["DEX", "INT"]],
	"sorcerer": [6, ["CON", "CHA"]], "warlock": [8, ["WIS", "CHA"]], "wizard": [6, ["INT", "WIS"]],
}
## Level-1 feature ids with M2 mechanics (or named flavour) per the addendum.
const LEVEL_1_FEATURES: Dictionary = {
	"barbarian": ["rage", "unarmored_defense_con"], "bard": ["bardic_inspiration"],
	"fighter": ["second_wind"], "monk": ["unarmored_defense_wis", "martial_arts"],
	"paladin": ["lay_on_hands", "divine_sense"], "ranger": ["favored_enemy", "natural_explorer"],
	"rogue": ["sneak_attack"], "warlock": ["pact_magic"],
}
## Casters at level 1: ability and slot recovery.
const CASTERS: Dictionary = {
	"bard": ["CHA", "long_rest"], "cleric": ["WIS", "long_rest"], "druid": ["WIS", "long_rest"],
	"sorcerer": ["CHA", "long_rest"], "warlock": ["CHA", "short_rest"], "wizard": ["INT", "long_rest"],
}
const KNOWN_CASTERS: Array[String] = ["bard", "sorcerer", "warlock"]
const PREPARED_CASTERS: Array[String] = ["cleric", "druid", "wizard"]
const EFFECT_TYPES: Array[String] = [
	"spell_attack", "auto_hit", "save", "heal", "buff", "mark", "area_save", "area_attack", "unsupported",
]
const CASTING_TIMES: Array[String] = [
	"action", "bonus_action", "reaction", "1_minute", "10_minutes", "1_hour", "8_hours", "12_hours", "24_hours",
]
const AREA_SHAPES: Array[String] = ["sphere", "cube", "cone", "line", "cylinder"]
const LEVELS := 20

var _classes: Dictionary = {}
var _spells: Dictionary = {}
var _raw_spells: Dictionary = {}


func before_each() -> void:
	if _classes.is_empty():
		_classes = ContentLoader.load_classes(CLASSES_DIR)
		_spells = ContentLoader.load_spells(SPELLS_DIR)
		for path in ContentLoader.json_files(SPELLS_DIR):
			var d := _raw(path)
			_raw_spells[str(d.get("id", ""))] = d


func _raw(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var d: Dictionary = parsed
	return d


func _raw_class(cid: String) -> Dictionary:
	return _raw("%s/%s.json" % [CLASSES_DIR, cid])


func _level(spell_id: String) -> int:
	return DictUtil.to_int(_raw_spells.get(spell_id, {}).get("level", -1), -1)


## {"1": n, ...} with int-able keys -> sorted [[level, value], ...]; [] if malformed.
func _level_rows(v: Variant) -> Array:
	if typeof(v) != TYPE_DICTIONARY:
		return []
	var d: Dictionary = v
	var rows: Array = []
	for key: Variant in d.keys():
		rows.append([DictUtil.to_int(key, 0), d[key]])
	rows.sort_custom(func(a: Array, b: Array) -> bool: return int(a[0]) < int(b[0]))
	return rows


func test_all_twelve_classes_parse_with_required_fields() -> void:
	assert_eq(ContentLoader.json_files(CLASSES_DIR).size(), CLASS_IDS.size(), "twelve class files")
	assert_eq(_classes.size(), CLASS_IDS.size(), "every class file parses")
	for cid in CLASS_IDS:
		var raw := _raw_class(cid)
		for key in REQUIRED:
			assert_true(raw.has(key), "%s.json has '%s'" % [cid, key])
		assert_eq(str(raw.get("id", "")), cid)
		assert_true(_classes.has(cid), "%s loads" % cid)
		if not _classes.has(cid):
			continue
		var def: ClassDefinition = _classes[cid]
		var srd: Array = SRD[cid]
		assert_eq(def.hit_die, int(srd[0]), "%s hit die" % cid)
		assert_eq(DictUtil.ability_keys(def.saving_throws), srd[1], "%s saves" % cid)
		assert_true(def.skill_choice_count >= 2, "%s skill count" % cid)
		assert_not_null(def.starting_weapon_def, "%s starting weapon '%s' exists" % [cid, def.starting_weapon])


func test_kits_reference_existing_items_and_weapons() -> void:
	var items := ContentLoader.load_items()
	var weapons := ContentLoader.load_weapons()
	for cid in CLASS_IDS:
		var raw := _raw_class(cid)
		var kit := DictUtil.to_dict_array(raw.get("starting_kit", []))
		assert_false(kit.is_empty(), "%s has a starting kit" % cid)
		var potions := 0
		for entry in kit:
			var iid := str(entry.get("item", ""))
			assert_true(DictUtil.to_int(entry.get("qty", 0), 0) >= 1, "%s kit %s qty" % [cid, iid])
			assert_true(items.has(iid), "%s kit item '%s' exists" % [cid, iid])
			if not items.has(iid):
				continue
			var it: ItemDefinition = items[iid]
			if it.kind == "weapon":
				assert_true(weapons.has(it.weapon_id), "%s kit weapon '%s' exists" % [cid, it.weapon_id])
				var w: WeaponDefinition = weapons.get(it.weapon_id)
				if w != null and w.has_property("ammunition"):
					var has_ammo := false
					for other in kit:
						has_ammo = has_ammo or str(other.get("item", "")) == it.ammo_id
					assert_true(has_ammo, "%s kit carries %s for its %s" % [cid, it.ammo_id, iid])
			if iid == "potion_of_healing":
				potions += DictUtil.to_int(entry.get("qty", 0), 0)
		assert_eq(potions, 2, "%s starts with two potions of healing" % cid)
		var armor_v: Variant = raw.get("starting_armor")
		if typeof(armor_v) == TYPE_DICTIONARY:
			var armor: Dictionary = armor_v
			var aid := str(armor.get("item", ""))
			assert_true(items.has(aid), "%s starting armor item '%s' exists" % [cid, aid])
			if items.has(aid):
				var it: ItemDefinition = items[aid]
				assert_eq(it.armor_base, DictUtil.to_int(armor.get("base", 0), 0), "%s armor base matches %s" % [cid, aid])
				assert_eq(it.armor_max_dex, DictUtil.to_int(armor.get("max_dex", -1), -1), "%s armor max_dex matches %s" % [cid, aid])


func test_features_by_level_are_well_formed() -> void:
	for cid in CLASS_IDS:
		var raw := _raw_class(cid)
		var fbl_v: Variant = raw.get("features_by_level")
		assert_eq(typeof(fbl_v), TYPE_DICTIONARY, "%s features_by_level" % cid)
		if typeof(fbl_v) != TYPE_DICTIONARY:
			continue
		var fbl: Dictionary = fbl_v
		for lvl in range(1, LEVELS + 1):
			assert_true(fbl.has(str(lvl)), "%s features_by_level has level %d" % [cid, lvl])
		assert_eq(fbl.size(), LEVELS, "%s features_by_level has exactly levels 1-20" % cid)
		assert_eq(DictUtil.to_string_array(raw.get("features", [])), DictUtil.to_string_array(fbl.get("1", [])),
				"%s: features == features_by_level['1']" % cid)
		for lvl: Variant in fbl.keys():
			var at_level := DictUtil.to_string_array(fbl[lvl])
			var seen := {}
			for f in at_level:
				assert_eq(f, f.to_lower().replace(" ", "_"), "%s feature id '%s' is snake_case" % [cid, f])
				assert_false(seen.has(f), "%s: '%s' listed once at level %s" % [cid, f, str(lvl)])
				seen[f] = true
		if LEVEL_1_FEATURES.has(cid):
			for f: String in LEVEL_1_FEATURES[cid]:
				assert_has(DictUtil.to_string_array(raw.get("features", [])), f, "%s level-1 feature" % cid)
		if _classes.has(cid):
			var def: ClassDefinition = _classes[cid]
			assert_eq(def.features_at(2), DictUtil.to_string_array(fbl.get("2", [])), "%s parsed level-2 features" % cid)


func test_spellcasting_blocks_and_slot_tables() -> void:
	for cid in CLASS_IDS:
		var raw := _raw_class(cid)
		var sc_v: Variant = raw.get("spellcasting")
		if not CASTERS.has(cid):
			assert_eq(sc_v, null, "%s has no level-1 spellcasting" % cid)
			continue
		assert_eq(typeof(sc_v), TYPE_DICTIONARY, "%s spellcasting" % cid)
		if typeof(sc_v) != TYPE_DICTIONARY:
			continue
		var sc: Dictionary = sc_v
		var spec: Array = CASTERS[cid]
		assert_eq(str(sc.get("ability", "")), str(spec[0]), "%s casting ability" % cid)
		assert_eq(str(raw.get("spellcasting_ability", "")), str(spec[0]), "%s spellcasting_ability" % cid)
		assert_eq(str(sc.get("slot_recovery", "")), str(spec[1]), "%s slot recovery" % cid)
		var rows := _level_rows(sc.get("slots"))
		assert_eq(rows.size(), LEVELS, "%s slot table covers levels 1-20" % cid)
		assert_eq(sc.get("slots"), raw.get("spell_slots"), "%s: spellcasting.slots == spell_slots" % cid)
		var prev_total := 0
		var prev_max := 0
		for i in range(rows.size()):
			var lvl: int = rows[i][0]
			assert_eq(lvl, i + 1, "%s slot table level %d" % [cid, i + 1])
			var row := DictUtil.to_int_array(rows[i][1])
			assert_false(row.is_empty(), "%s level %d has slots" % [cid, lvl])
			var total := 0
			for n in row:
				assert_true(n >= 0, "%s level %d slot counts are non-negative" % [cid, lvl])
				total += n
			assert_true(total >= 1, "%s level %d has at least one slot" % [cid, lvl])
			assert_true(row.size() >= prev_max, "%s: max slot level never drops at level %d" % [cid, lvl])
			if cid != "warlock":
				assert_true(total >= prev_total, "%s: slot total never drops at level %d" % [cid, lvl])
				assert_true(row[row.size() - 1] > 0, "%s level %d: the highest slot level has slots" % [cid, lvl])
			prev_total = total
			prev_max = row.size()
		if _classes.has(cid):
			var def: ClassDefinition = _classes[cid]
			assert_true(def.has_spellcasting, "%s parses as a caster" % cid)
			assert_eq(def.slots_for_level(1), DictUtil.to_int_array(rows[0][1]) if not rows.is_empty() else [] as Array[int])
	var warlock := _raw_class("warlock")
	var wsc: Dictionary = warlock.get("spellcasting", {})
	var pact: Dictionary = wsc.get("slots", {})
	var first_five := {}
	for lvl in ["1", "2", "3", "4", "5"]:
		first_five[lvl] = pact.get(lvl)
	assert_eq(first_five, {"1": [1], "2": [2], "3": [0, 2], "4": [0, 2], "5": [0, 0, 2]}, "warlock pact slots")


func test_prepared_spells_exist_fit_the_tables_and_can_be_cast() -> void:
	for cid: String in CASTERS.keys():
		var raw := _raw_class(cid)
		var sc: Dictionary = raw.get("spellcasting", {})
		var prepared := DictUtil.to_string_array(sc.get("prepared", []))
		var spell_list := DictUtil.to_string_array(raw.get("spell_list", []))
		assert_false(prepared.is_empty(), "%s prepares spells" % cid)
		var cantrips := 0
		var leveled := 0
		var level_one_slots := DictUtil.to_int_array(_level_rows(sc.get("slots"))[0][1]).size()
		for sid in prepared:
			assert_true(_spells.has(sid), "%s prepared spell '%s' loads" % [cid, sid])
			assert_has(spell_list, sid, "%s: prepared %s is on the class list" % [cid, sid])
			var lvl := _level(sid)
			if lvl == 0:
				cantrips += 1
			else:
				leveled += 1
				assert_true(lvl <= level_one_slots, "%s: %s fits a level-1 slot" % [cid, sid])
			var effect: Dictionary = _raw_spells.get(sid, {}).get("effect", {})
			assert_ne(str(effect.get("type", "")), "unsupported", "%s: prepared %s is castable" % [cid, sid])
		var cantrips_known := ClassDefinition.table_value(_classes[cid].cantrips_known_table, 1) if _classes.has(cid) else 0
		assert_true(cantrips >= 1 and cantrips <= cantrips_known, "%s: %d cantrips <= %d known" % [cid, cantrips, cantrips_known])
		if KNOWN_CASTERS.has(cid) and _classes.has(cid):
			var known := ClassDefinition.table_value(_classes[cid].spells_known_table, 1)
			assert_true(leveled <= known, "%s: %d level-1 spells <= %d known" % [cid, leveled, known])


func test_known_and_prepared_fields_are_well_formed() -> void:
	for cid in CLASS_IDS:
		var raw := _raw_class(cid)
		var has_list := raw.has("spell_list")
		var is_known := KNOWN_CASTERS.has(cid) or cid == "ranger"
		var is_prepared := PREPARED_CASTERS.has(cid) or cid == "paladin"
		assert_eq(has_list, is_known or is_prepared, "%s has a spell_list iff it casts" % cid)
		assert_eq(raw.has("spells_known"), is_known, "%s spells_known" % cid)
		assert_eq(DictUtil.to_bool(raw.get("prepares", false), false), is_prepared, "%s prepares" % cid)
		if is_known:
			var rows := _level_rows(raw.get("spells_known"))
			assert_eq(rows.size(), LEVELS, "%s spells_known covers levels 1-20" % cid)
			var prev := -1
			for i in range(rows.size()):
				assert_eq(int(rows[i][0]), i + 1, "%s spells_known level" % cid)
				var n := DictUtil.to_int(rows[i][1], -1)
				assert_true(n >= 0 and n >= prev, "%s spells_known never drops (level %d: %d)" % [cid, i + 1, n])
				prev = n
		if CASTERS.has(cid):
			var crows := _level_rows(raw.get("cantrips_known"))
			assert_eq(crows.size(), LEVELS, "%s cantrips_known covers levels 1-20" % cid)
			var steps: Array = []
			var prev := 0
			for r: Array in crows:
				var n := DictUtil.to_int(r[1], -1)
				assert_true(n >= prev and n > 0, "%s cantrips_known never drops" % cid)
				if n > prev:
					steps.append(int(r[0]))
				prev = n
			assert_eq(steps, [1, 4, 10], "%s cantrips grow at levels 1/4/10" % cid)
		else:
			assert_false(raw.has("cantrips_known"), "%s learns no cantrips" % cid)
	var wiz := _raw_class("wizard")
	var book := DictUtil.to_string_array(wiz.get("spellbook", []))
	assert_eq(book.size(), 6, "the wizard's spellbook starts with six spells")
	assert_eq(DictUtil.to_int(wiz.get("spellbook_learn_per_level", 0), 0), 2)
	for sid in book:
		assert_eq(_level(sid), 1, "spellbook %s is a level-1 spell" % sid)
		assert_has(DictUtil.to_string_array(wiz.get("spell_list", [])), sid, "spellbook %s is a wizard spell" % sid)
	var wsc: Dictionary = wiz.get("spellcasting", {})
	for sid in DictUtil.to_string_array(wsc.get("prepared", [])):
		if _level(sid) > 0:
			assert_has(book, sid, "the wizard's prepared %s is in the spellbook" % sid)


func test_spell_lists_reference_existing_spells_both_ways() -> void:
	for cid in CLASS_IDS:
		var raw := _raw_class(cid)
		var list := DictUtil.to_string_array(raw.get("spell_list", []))
		var seen := {}
		for sid in list:
			assert_true(_spells.has(sid), "%s spell_list: '%s' exists" % [cid, sid])
			assert_false(seen.has(sid), "%s spell_list: '%s' listed once" % [cid, sid])
			seen[sid] = true
			assert_has(DictUtil.to_string_array(_raw_spells.get(sid, {}).get("classes", [])), cid,
					"%s lists %s; the spell names the class" % [cid, sid])
	for sid: String in _raw_spells.keys():
		for cid in DictUtil.to_string_array(_raw_spells[sid].get("classes", [])):
			assert_has(CLASS_IDS, cid, "%s: class '%s' exists" % [sid, cid])
			assert_has(DictUtil.to_string_array(_raw_class(cid).get("spell_list", [])), sid, "%s is on the %s list" % [sid, cid])
	# Real choices at levels 2-3: every full caster has a level-2 spell to learn.
	for cid in ["bard", "cleric", "druid", "sorcerer", "warlock", "wizard"]:
		var level_two := 0
		for sid in DictUtil.to_string_array(_raw_class(cid).get("spell_list", [])):
			if _level(sid) == 2:
				level_two += 1
		assert_true(level_two >= 1, "%s has level-2 spells" % cid)


func test_every_spell_parses_and_is_well_formed() -> void:
	assert_eq(_spells.size(), _raw_spells.size(), "every spell file parses")
	for sid: String in _raw_spells.keys():
		var d: Dictionary = _raw_spells[sid]
		var ctx := "spell %s" % sid
		for key in ["schema_version", "id", "display_name", "level", "school", "casting_time", "range_ft",
				"target", "effect", "classes", "source", "description"]:
			assert_true(d.has(key), "%s has '%s'" % [ctx, key])
		assert_has(["SRD 5.1", "SRD 5.2"], str(d.get("source", "")), "%s source" % ctx)
		assert_has(CASTING_TIMES, str(d.get("casting_time", "")), "%s casting time" % ctx)
		assert_in_range(DictUtil.to_int(d.get("level", -1), -1), 0, 9, "%s level" % ctx)
		assert_true(typeof(d.get("range_ft")) == TYPE_FLOAT or typeof(d.get("range_ft")) == TYPE_INT, "%s range_ft is a number" % ctx)
		var e: Dictionary = d.get("effect", {})
		var t := str(e.get("type", ""))
		assert_has(EFFECT_TYPES, t, "%s effect type" % ctx)
		var lvl := DictUtil.to_int(d.get("level", 0), 0)
		if d.has("area"):
			var area: Dictionary = d.get("area", {})
			assert_has(AREA_SHAPES, str(area.get("shape", "")), "%s area shape" % ctx)
			assert_true(DictUtil.to_int(area.get("size_ft", 0), 0) >= 5, "%s area size" % ctx)
		if t == "area_save" or t == "area_attack":
			assert_true(d.has("area"), "%s: %s needs an area" % [ctx, t])
		match t:
			"spell_attack", "save", "area_save", "area_attack":
				assert_true(DiceExpr.parse(str(e.get("damage", ""))).valid, "%s damage dice" % ctx)
				assert_ne(str(e.get("damage_type", "")), "", "%s damage type" % ctx)
				if lvl == 0 and not e.has("beams"):
					assert_eq(_level_rows(e.get("scaling")).size(), 3, "%s cantrip scaling at 5/11/17" % ctx)
				if t == "save" or t == "area_save":
					assert_has(["STR", "DEX", "CON", "INT", "WIS", "CHA"], str(e.get("save", "")), "%s save ability" % ctx)
					assert_has(["none", "half"], str(e.get("on_save", "")), "%s on_save" % ctx)
			"auto_hit":
				assert_true(DictUtil.to_int(e.get("darts", 0), 0) >= 1, "%s darts" % ctx)
			"heal":
				assert_true(DiceExpr.parse(str(e.get("dice", ""))).valid, "%s heal dice" % ctx)
		if lvl > 0 and t != "unsupported" and t != "buff" and t != "mark":
			var table: Dictionary = d.get("heal_by_slot", {}) if t == "heal" else d.get("damage_by_slot", {})
			assert_true(e.has("per_slot_level_above") or table.size() >= 1 or d.get("hand_edited", false),
					"%s scales with slot level (per_slot_level_above or a by-slot table)" % ctx)


func test_srd_spell_numbers() -> void:
	var expect := {
		"fire_bolt": ["spell_attack", "1d10", "fire", 120], "ray_of_frost": ["spell_attack", "1d8", "cold", 60],
		"sacred_flame": ["save", "1d8", "radiant", 60], "vicious_mockery": ["save", "1d4", "psychic", 60],
		"produce_flame": ["spell_attack", "1d8", "fire", 30], "eldritch_blast": ["spell_attack", "1d10", "force", 120],
		"magic_missile": ["auto_hit", "1d4+1", "force", 120], "guiding_bolt": ["spell_attack", "4d6", "radiant", 120],
		"chill_touch": ["spell_attack", "1d8", "necrotic", 120], "scorching_ray": ["spell_attack", "2d6", "fire", 120],
		"inflict_wounds": ["spell_attack", "3d10", "necrotic", 5],
	}
	for sid: String in expect.keys():
		var d: Dictionary = _raw_spells.get(sid, {})
		var e: Array = expect[sid]
		var effect: Dictionary = d.get("effect", {})
		assert_eq([str(effect.get("type", "")), str(effect.get("damage", "")), str(effect.get("damage_type", "")),
				DictUtil.to_int(d.get("range_ft", 0), 0)], [str(e[0]), str(e[1]), str(e[2]), int(e[3])], sid)
	var cure: Dictionary = _raw_spells.get("cure_wounds", {}).get("effect", {})
	assert_eq([cure.get("dice"), cure.get("add_casting_mod"), cure.get("per_slot_level_above")], ["1d8", true, "1d8"])
	var word: Dictionary = _raw_spells.get("healing_word", {})
	assert_eq([word.get("casting_time"), DictUtil.to_int(word.get("range_ft"), 0), word.get("effect", {}).get("dice")],
			["bonus_action", 60, "1d4"])
	var ray: Dictionary = _raw_spells.get("scorching_ray", {}).get("effect", {})
	assert_eq(DictUtil.to_int(ray.get("rays", 0), 0), 3, "scorching ray fires three rays")
	var hex: Dictionary = _raw_spells.get("hex", {})
	assert_eq([hex.get("casting_time"), hex.get("source")], ["bonus_action", "SRD 5.2"], "hex is the SRD 5.2 bonus-action curse")


func test_cross_references_resolve() -> void:
	var problems := ContentLoader.validate_references(ContentLoader.load_all())
	assert_eq(problems, [] as Array[String], "ContentLoader.validate_references")

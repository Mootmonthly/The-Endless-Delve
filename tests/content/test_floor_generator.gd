extends TestCase
## tools/gen_floor.py: deterministic output, its --check passes for every set
## floor, and the committed floors are the generator's output unless marked
## "hand_edited": true. Needs python3 on PATH (CI runners and the sandbox have
## it); without it the checks are skipped with a passing note.

const GENERATOR := "tools/gen_floor.py"
const SET_PATH := "res://floors/set_01.json"

var _python := ""


func before_each() -> void:
	if _python.is_empty():
		for candidate: String in ["python3", "python"]:
			var out: Array = []
			if OS.execute(candidate, ["--version"], out, true) == 0:
				_python = candidate
				break


func _run(args: PackedStringArray) -> Dictionary:
	var out: Array = []
	var full := PackedStringArray(["-I", ProjectSettings.globalize_path("res://" + GENERATOR)])
	full.append_array(args)
	var code := OS.execute(_python, full, out, true)
	return {"code": code, "text": "".join(PackedStringArray(out))}


func _floor_ids() -> Array[String]:
	return FloorFile.set_floor_ids(FloorFile.load_set(SET_PATH))


func test_generator_is_deterministic() -> void:
	if _python.is_empty():
		assert_true(true, "python3 not available: skipped")
		return
	var a := _run(PackedStringArray(["--preset", "floor_001", "--stdout"]))
	var b := _run(PackedStringArray(["--preset", "floor_001", "--stdout"]))
	assert_eq(int(a["code"]), 0, "the generator runs")
	assert_true(str(a["text"]).length() > 1000, "it prints a floor")
	assert_eq(a["text"], b["text"], "same preset and seed, same JSON")
	var c := _run(PackedStringArray(["--preset", "floor_001", "--stdout", "--seed", "7"]))
	assert_ne(a["text"], c["text"], "another seed moves the contents")


func test_committed_floors_match_the_generator() -> void:
	if _python.is_empty():
		assert_true(true, "python3 not available: skipped")
		return
	for floor_id in _floor_ids():
		var path := FloorFile.floor_path(floor_id)
		var text := FileAccess.get_file_as_string(path)
		var parsed: Variant = JSON.parse_string(text)
		if typeof(parsed) == TYPE_DICTIONARY and DictUtil.to_bool((parsed as Dictionary).get("hand_edited", false), false):
			continue
		var res := _run(PackedStringArray(["--preset", floor_id, "--stdout"]))
		assert_eq(int(res["code"]), 0, "%s generates" % floor_id)
		assert_eq(res["text"], text, "%s is the generator's output (mark hand edits with \"hand_edited\": true)" % floor_id)


func test_generator_check_passes_for_every_floor() -> void:
	if _python.is_empty():
		assert_true(true, "python3 not available: skipped")
		return
	var args := PackedStringArray(["--check"])
	for floor_id in _floor_ids():
		args.append(ProjectSettings.globalize_path(FloorFile.floor_path(floor_id)))
	var res := _run(args)
	assert_eq(int(res["code"]), 0, "gen_floor.py --check: %s" % str(res["text"]))


# --- door keys -------------------------------------------------------------------------

const KEY_ITEMS: Array[String] = ["key_bronze", "key_iron", "key_silver", "key_brass", "key_copper", "key_bone"]


func test_every_floor_has_key_doors_with_reachable_key_props() -> void:
	var items := ContentLoader.load_items()
	for floor_id in _floor_ids():
		var f := FloorFile.load(FloorFile.floor_path(floor_id))
		if f == null:
			fail("%s did not load" % floor_id)
			continue
		var blocked := f.prop_blockers()
		var locked := 0
		for d in f.doors:
			if d.is_locked():
				blocked[d.position] = true
				locked += 1
		var colours := {}
		for d in f.doors:
			if d.key_item.is_empty():
				continue
			var ctx := "%s door %s (%s)" % [floor_id, d.id, d.key_item]
			assert_true(d.is_locked(), "%s is locked" % ctx)
			assert_true(d.dc > 0, "%s keeps its DC: thieves' tools still work" % ctx)
			assert_has(KEY_ITEMS, d.key_item, "%s is a key colour" % ctx)
			assert_true(items.has(d.key_item) and (items[d.key_item] as ItemDefinition).kind == ItemDefinition.KIND_KEY, "%s is a key item" % ctx)
			assert_false(colours.has(d.key_item), "%s: one door per colour" % ctx)
			colours[d.key_item] = true
			var holders: Array[PropData] = []
			for p in f.props:
				if p.drops_item(d.key_item):
					holders.append(p)
			assert_eq(holders.size(), 1, "%s: exactly one prop drops the key" % ctx)
			if holders.size() != 1:
				continue
			var holder := holders[0]
			assert_has(["crate", "barrel"], holder.kind, "%s: a crate or barrel holds the key" % ctx)
			for l in f.get_landings():
				var reach := f.walk_map.reachable(l.position, f.walk_map.width * f.walk_map.height, blocked)
				var ok := false
				for n in GridMath.neighbors8(holder.position):
					ok = ok or reach.has(n)
				assert_true(ok, "%s: key prop %s reachable from landing %s past no locked door" % [ctx, holder.id, l.id])
			# The key sits on the landings' side, a short walk from its door.
			var from_door := f.walk_map.reachable(d.position, 40, f.prop_blockers())
			var near := 999
			for n in GridMath.neighbors8(holder.position):
				if from_door.has(n):
					near = mini(near, int(from_door[n]) + 1)
			assert_in_range(near, 2, 30, "%s: key prop %s is near its door (%d)" % [ctx, holder.id, near])
		var keyed := colours.size()
		assert_true(keyed >= 1, "%s has at least one key door" % floor_id)
		assert_true(keyed <= mini(KEY_ITEMS.size(), locked), "%s: at most one key door per colour and locked door" % floor_id)
		assert_true(locked > keyed or locked == 1, "%s keeps DC-only locked doors too" % floor_id)


func test_key_doors_follow_the_share_and_move_nothing_else() -> void:
	if _python.is_empty():
		assert_true(true, "python3 not available: skipped")
		return
	var none := _run(PackedStringArray(["--preset", "floor_003", "--stdout", "--key-doors", "0"]))
	var half := _run(PackedStringArray(["--preset", "floor_003", "--stdout"]))
	assert_eq(int(none["code"]), 0)
	var a: Dictionary = JSON.parse_string(str(none["text"]))
	var b: Dictionary = JSON.parse_string(str(half["text"]))
	assert_false(str(none["text"]).contains("key_item"), "--key-doors 0: no keys")
	assert_eq(a["rows"], b["rows"], "keys never move the layout")
	assert_eq(a["chests"], b["chests"])
	assert_eq((a["props"] as Array).size(), (b["props"] as Array).size(), "no prop added or removed")
	var keyed := 0
	for d: Variant in (b["doors"] as Array):
		if (d as Dictionary).has("key_item"):
			keyed += 1
	assert_true(keyed >= 1, "the default share keys some doors")
	assert_true(str(b["generated_by"]).contains("--key-doors 0.5"), str(b["generated_by"]))

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

extends SceneTree
## Headless test runner. Usage:
##   godot --headless -s tests/run_tests.gd                 # run everything
##   godot --headless -s tests/run_tests.gd -- test_dice    # files whose name contains "test_dice"
##   godot --headless -s tests/run_tests.gd -- test_dice::parse   # ...and methods containing "parse"
## Discovers res://tests/**/test_*.gd (except test_case.gd), runs every
## `test_*` method, prints PASS/FAIL lines and a summary, exits 1 on failure.
## A runtime script error inside a test (e.g. null access) also fails that test.

const TEST_ROOT := "res://tests"

var _finished := false


## Counts GDScript runtime errors so a test that crashes half-way cannot PASS.
## (push_error() from code under test is ERROR_TYPE_ERROR and is not counted.)
class ScriptErrorCounter extends Logger:
	var errors: Array[String] = []
	var _mutex := Mutex.new()

	func _log_error(_function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type != ERROR_TYPE_SCRIPT:
			return
		_mutex.lock()
		errors.append("script error at %s:%d: %s" % [file, line, rationale if rationale != "" else code])
		_mutex.unlock()

	func take() -> Array[String]:
		_mutex.lock()
		var out := errors.duplicate()
		errors.clear()
		_mutex.unlock()
		return out


func _init() -> void:
	var filters: PackedStringArray = OS.get_cmdline_user_args()
	var files: Array[String] = []
	_collect(TEST_ROOT, files)
	files.sort()
	var counter := ScriptErrorCounter.new()
	OS.add_logger(counter)
	var ran := 0
	var failed := 0
	for path in files:
		var file_name := path.get_file().get_basename()
		if not _file_matches(file_name, filters):
			continue
		var script: Variant = load(path)
		if script == null or not (script is GDScript):
			print("FAIL %s (could not load script; see errors above)" % path)
			failed += 1
			ran += 1
			continue
		var gd_script: GDScript = script
		if not gd_script.can_instantiate():
			print("FAIL %s (script does not compile; see errors above)" % path)
			failed += 1
			ran += 1
			continue
		var instance: Variant = gd_script.new()
		if not (instance is TestCase):
			print("SKIP %s (does not extend TestCase)" % path)
			continue
		var tc: TestCase = instance
		for method_name in _test_methods(tc):
			if not _method_matches(file_name, method_name, filters):
				continue
			tc._current = method_name
			tc._failures.clear()
			counter.take()
			tc.before_each()
			tc.call(method_name)
			tc.after_each()
			for script_error in counter.take():
				tc._failures.append("%s: %s" % [method_name, script_error])
			ran += 1
			if tc._failures.is_empty():
				print("PASS %s::%s" % [file_name, method_name])
			else:
				failed += 1
				print("FAIL %s::%s" % [file_name, method_name])
				for failure in tc._failures:
					print("    " + failure)
	OS.remove_logger(counter)
	print("Ran %d tests, %d failures" % [ran, failed])
	_finished = true
	quit(1 if failed > 0 else 0)


## Safety net: if _init() was aborted by a script error, quit() was never
## called. The first frame then exits with a failure instead of hanging CI.
func _process(_delta: float) -> bool:
	if not _finished:
		print("FAIL test runner aborted before finishing; see SCRIPT ERROR above")
		_finished = true
		quit(1)
	return false


func _collect(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_error("run_tests: cannot open %s" % dir_path)
		return
	for file_name: String in dir.get_files():
		if file_name.begins_with("test_") and file_name.ends_with(".gd") and file_name != "test_case.gd":
			out.append(dir_path.path_join(file_name))
	for sub: String in dir.get_directories():
		if not sub.begins_with("."):
			_collect(dir_path.path_join(sub), out)


func _test_methods(tc: TestCase) -> Array[String]:
	var names: Array[String] = []
	for info: Dictionary in tc.get_method_list():
		var method_name: String = str(info.get("name", ""))
		if method_name.begins_with("test_") and not names.has(method_name):
			names.append(method_name)
	return names


func _file_matches(file_name: String, filters: PackedStringArray) -> bool:
	if filters.is_empty():
		return true
	for f: String in filters:
		var file_part := f.get_slice("::", 0)
		if file_name.contains(file_part):
			return true
	return false


func _method_matches(file_name: String, method_name: String, filters: PackedStringArray) -> bool:
	if filters.is_empty():
		return true
	for f: String in filters:
		var file_part := f.get_slice("::", 0)
		if not file_name.contains(file_part):
			continue
		if not f.contains("::"):
			return true
		if method_name.contains(f.get_slice("::", 1)):
			return true
	return false

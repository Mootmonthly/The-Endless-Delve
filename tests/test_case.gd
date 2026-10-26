class_name TestCase
extends RefCounted
## Base class for every test file under res://tests/.
##
## Test files `extends TestCase` (no class_name of their own) and declare
## methods named `test_*`. The runner (tests/run_tests.gd) calls
## before_each(), the test method, then after_each(). A failing assertion
## records a message in _failures and the test keeps running.

var _failures: Array[String] = []
var _current: String = ""
var _assertions: int = 0


func before_each() -> void:
	pass


func after_each() -> void:
	pass


func fail(msg: String) -> void:
	_failures.append("%s: %s" % [_current, msg])


func assert_true(c: bool, msg: String = "") -> void:
	_assertions += 1
	if not c:
		_record(msg, true, false)


func assert_false(c: bool, msg: String = "") -> void:
	_assertions += 1
	if c:
		_record(msg, false, true)


func assert_eq(a: Variant, b: Variant, msg: String = "") -> void:
	_assertions += 1
	if not _deep_equal(a, b):
		_record(msg, b, a)


func assert_ne(a: Variant, b: Variant, msg: String = "") -> void:
	_assertions += 1
	if _deep_equal(a, b):
		_record(msg, "anything but %s" % str(b), a)


func assert_null(v: Variant, msg: String = "") -> void:
	_assertions += 1
	if v != null:
		_record(msg, null, v)


func assert_not_null(v: Variant, msg: String = "") -> void:
	_assertions += 1
	if v == null:
		_record(msg, "non-null", null)


func assert_in_range(v: Variant, lo: Variant, hi: Variant, msg: String = "") -> void:
	_assertions += 1
	if not _is_number(v) or _num(v) < _num(lo) or _num(v) > _num(hi):
		_record(msg, "%s..%s" % [str(lo), str(hi)], v)


func assert_has(container: Variant, item: Variant, msg: String = "") -> void:
	_assertions += 1
	var found := false
	match typeof(container):
		TYPE_ARRAY:
			var arr: Array = container
			for element: Variant in arr:
				if _deep_equal(element, item):
					found = true
					break
		TYPE_DICTIONARY:
			var dict: Dictionary = container
			found = dict.has(item)
		TYPE_STRING:
			var text: String = container
			found = text.find(str(item)) != -1
		TYPE_PACKED_STRING_ARRAY:
			var packed: PackedStringArray = container
			found = packed.has(str(item))
		_:
			found = false
	if not found:
		_record(msg, "container holding %s" % str(item), container)


## Returns the first seed in 1..max_tries for which predicate(Rng.new(seed))
## is true. Used to force specific dice outcomes deterministically.
func seed_where(predicate: Callable, max_tries: int = 100000) -> int:
	for s in range(1, max_tries + 1):
		if predicate.call(Rng.new(s)):
			return s
	fail("seed_where: no seed satisfied the predicate in %d tries" % max_tries)
	return 1


func _record(msg: String, expected: Variant, actual: Variant) -> void:
	var text := msg if msg != "" else "assertion failed"
	_failures.append("%s: %s (expected %s, got %s)" % [_current, text, str(expected), str(actual)])


func _is_number(v: Variant) -> bool:
	return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT


func _num(v: Variant) -> float:
	if typeof(v) == TYPE_INT:
		var i: int = v
		return float(i)
	if typeof(v) == TYPE_FLOAT:
		var f: float = v
		return f
	return NAN


func _deep_equal(a: Variant, b: Variant) -> bool:
	if _is_number(a) and _is_number(b):
		if typeof(a) == TYPE_FLOAT or typeof(b) == TYPE_FLOAT:
			return is_equal_approx(_num(a), _num(b))
		var ia: int = a
		var ib: int = b
		return ia == ib
	if typeof(a) != typeof(b):
		return false
	if typeof(a) == TYPE_ARRAY:
		var aa: Array = a
		var ba: Array = b
		if aa.size() != ba.size():
			return false
		for i in range(aa.size()):
			if not _deep_equal(aa[i], ba[i]):
				return false
		return true
	if typeof(a) == TYPE_DICTIONARY:
		var ad: Dictionary = a
		var bd: Dictionary = b
		if ad.size() != bd.size():
			return false
		for key: Variant in ad.keys():
			if not bd.has(key):
				return false
			if not _deep_equal(ad[key], bd[key]):
				return false
		return true
	return a == b

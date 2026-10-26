class_name DictUtil
extends RefCounted
## Small helpers for reading JSON-shaped data (JSON numbers arrive as floats).


## Pushes one error naming every missing key; returns true when all are present.
static func require_keys(d: Dictionary, keys: Array[String], context: String) -> bool:
	var missing := PackedStringArray()
	for k in keys:
		if not d.has(k):
			missing.append(k)
	if missing.is_empty():
		return true
	push_error("%s: missing required field(s): %s" % [context, ", ".join(missing)])
	return false


static func is_number(v: Variant) -> bool:
	return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT


## int, float (rounded) or numeric string -> int; anything else -> fallback.
static func to_int(v: Variant, fallback: int = 0) -> int:
	match typeof(v):
		TYPE_INT:
			var i: int = v
			return i
		TYPE_FLOAT:
			var f: float = v
			return roundi(f)
		TYPE_STRING:
			var s: String = v
			if s.strip_edges().is_valid_int():
				return s.strip_edges().to_int()
	return fallback


## bool, or a number (non-zero = true); anything else -> fallback.
static func to_bool(v: Variant, fallback: bool = false) -> bool:
	match typeof(v):
		TYPE_BOOL:
			var b: bool = v
			return b
		TYPE_INT, TYPE_FLOAT:
			return DictUtil.to_float(v, 0.0) != 0.0
	return fallback


## Accepts numbers, numeric strings and fractions such as "1/4".
static func to_float(v: Variant, fallback: float = 0.0) -> float:
	match typeof(v):
		TYPE_INT, TYPE_FLOAT:
			var f: float = v
			return f
		TYPE_STRING:
			var s: String = v
			s = s.strip_edges()
			if s.is_valid_float():
				return s.to_float()
			var parts := s.split("/")
			if parts.size() == 2 and parts[0].is_valid_int() and parts[1].is_valid_int():
				var den := parts[1].to_int()
				if den != 0:
					return float(parts[0].to_int()) / float(den)
	return fallback


static func to_string_array(v: Variant) -> Array[String]:
	var out: Array[String] = []
	if typeof(v) == TYPE_ARRAY:
		var arr: Array = v
		for item: Variant in arr:
			out.append(str(item))
	return out


static func to_int_array(v: Variant) -> Array[int]:
	var out: Array[int] = []
	if typeof(v) == TYPE_ARRAY:
		var arr: Array = v
		for item: Variant in arr:
			out.append(DictUtil.to_int(item, 0))
	return out


static func to_dict_array(v: Variant) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if typeof(v) == TYPE_ARRAY:
		var arr: Array = v
		for item: Variant in arr:
			if typeof(item) == TYPE_DICTIONARY:
				var d: Dictionary = item
				out.append(d)
	return out


## ["STR", "dex"] -> [Ability.Type.STR, Ability.Type.DEX]. Unknown names become -1
## so callers can detect them with `.has(-1)`.
static func to_ability_array(v: Variant) -> Array[int]:
	var out: Array[int] = []
	for s in DictUtil.to_string_array(v):
		out.append(Ability.from_string(s))
	return out


## ["STEALTH", "Sleight of Hand"] -> Skill enum values; unknown names become -1.
static func to_skill_array(v: Variant) -> Array[int]:
	var out: Array[int] = []
	for s in DictUtil.to_string_array(v):
		out.append(Skill.from_string(s))
	return out


static func ability_keys(values: Array[int]) -> Array:
	var out: Array = []
	for v in values:
		out.append(Ability.abbreviation(v))
	return out


static func skill_keys(values: Array[int]) -> Array:
	var out: Array = []
	for v in values:
		out.append(Skill.key_of(v))
	return out

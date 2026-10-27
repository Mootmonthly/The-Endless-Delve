class_name LootTable
extends RefCounted
## A weighted random loot table from data/loot/<id>.json, in one of two shapes.
##
## One weighted bag:
## {"schema_version": 1, "id", "rolls": int or [min, max],
##  "entries": [{"item": id, "weight": int, "qty": int or [min, max]},
##              {"nothing": true, "weight": int}, ...]}
## roll(rng) draws `rolls` times (weighted, with replacement).
##
## Category rolls (a chest that always gives gear, healing and gold):
## {"schema_version": 1, "id",
##  "rolls": [{"name": "gear", "entries": [...]},
##            {"name": "supplies", "chance": 50, "count": int or [min, max], "entries": [...]}, ...]}
## Each group is rolled in order: `chance` (percent, default 100) decides
## whether it drops at all, then `count` (default 1) weighted draws from its
## own entries (same entry shape as above).
##
## Either way the results are merged by item id in first-drawn order:
## [{"item", "qty"}, ...].

const SCHEMA_VERSION := 1
const REQUIRED_FIELDS: Array[String] = ["id"]

var id: String = ""
var rolls_min: int = 1
var rolls_max: int = 1
## Each: {"item": String ("" = nothing), "weight": int, "qty_min": int, "qty_max": int}.
## The single bag; empty for a table of category rolls.
var entries: Array[Dictionary] = []
## Category rolls, each {"name": String, "chance": int (1..100), "count_min",
## "count_max": int, "entries": Array[Dictionary] (shape of `entries`)}.
var groups: Array[Dictionary] = []


## Returns null (and push_error) when a field is missing or invalid.
static func from_dict(d: Dictionary) -> LootTable:
	if not DictUtil.require_keys(d, REQUIRED_FIELDS, "LootTable"):
		return null
	var t := LootTable.new()
	t.id = str(d["id"])
	var ctx := "LootTable '%s'" % t.id
	if t.id.is_empty():
		push_error("%s: id must not be empty" % ctx)
		return null
	if d.has("schema_version") and DictUtil.to_int(d["schema_version"], -1) != SCHEMA_VERSION:
		push_error("%s: unsupported schema_version %s" % [ctx, str(d["schema_version"])])
		return null
	var rolls_v: Variant = d.get("rolls", 1)
	if typeof(rolls_v) == TYPE_ARRAY and not (rolls_v as Array).is_empty() and typeof((rolls_v as Array)[0]) == TYPE_DICTIONARY:
		for g_v: Variant in (rolls_v as Array):
			if typeof(g_v) != TYPE_DICTIONARY:
				push_error("%s: every category roll must be an object" % ctx)
				return null
			var g: Dictionary = g_v
			var gname := str(g.get("name", "roll %d" % (t.groups.size() + 1)))
			var chance := DictUtil.to_int(g.get("chance", 100), -1)
			if chance < 1 or chance > 100:
				push_error("%s: roll '%s' chance must be 1..100" % [ctx, gname])
				return null
			var count := LootTable._range(g.get("count", 1), 1)
			if count.x < 1 or count.y < count.x:
				push_error("%s: roll '%s' has an invalid count" % [ctx, gname])
				return null
			var g_entries := LootTable._parse_entries(g.get("entries", []), "%s roll '%s'" % [ctx, gname])
			if g_entries.is_empty():
				return null
			t.groups.append({"name": gname, "chance": chance, "count_min": count.x, "count_max": count.y, "entries": g_entries})
		if d.has("entries"):
			push_error("%s: use either category rolls or \"entries\", not both" % ctx)
			return null
		return t
	if not d.has("entries"):
		push_error("%s: needs \"entries\" or category \"rolls\"" % ctx)
		return null
	var rolls := LootTable._range(rolls_v, 1)
	t.rolls_min = rolls.x
	t.rolls_max = rolls.y
	if t.rolls_min < 0 or t.rolls_max < t.rolls_min:
		push_error("%s: invalid rolls %s" % [ctx, str(d.get("rolls"))])
		return null
	t.entries = LootTable._parse_entries(d["entries"], ctx)
	if t.entries.is_empty():
		return null
	return t


## Parsed entries, or [] (after push_error) when one is invalid or there are none.
static func _parse_entries(raw_entries: Variant, ctx: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for raw in DictUtil.to_dict_array(raw_entries):
		var nothing := DictUtil.to_bool(raw.get("nothing", false), false)
		var item := "" if nothing else str(raw.get("item", ""))
		if not nothing and item.is_empty():
			push_error("%s: an entry has neither \"item\" nor \"nothing\"" % ctx)
			return [] as Array[Dictionary]
		var weight := DictUtil.to_int(raw.get("weight", 1), -1)
		if weight < 1:
			push_error("%s: entry '%s' needs a weight >= 1" % [ctx, item])
			return [] as Array[Dictionary]
		var qty := LootTable._range(raw.get("qty", 1), 1)
		if qty.x < 1 or qty.y < qty.x:
			push_error("%s: entry '%s' has an invalid qty" % [ctx, item])
			return [] as Array[Dictionary]
		out.append({"item": item, "weight": weight, "qty_min": qty.x, "qty_max": qty.y})
	if out.is_empty():
		push_error("%s: needs at least one entry" % ctx)
	return out


func total_weight() -> int:
	return LootTable._weight_of(entries)


func is_grouped() -> bool:
	return not groups.is_empty()


## Category roll names in order ([] for a single-bag table).
func group_names() -> Array[String]:
	var out: Array[String] = []
	for g in groups:
		out.append(str(g["name"]))
	return out


## Item ids this table can produce (no duplicates, entry order).
func item_ids() -> Array[String]:
	var out: Array[String] = []
	var all: Array[Dictionary] = entries.duplicate()
	for g in groups:
		var ge: Array[Dictionary] = g["entries"]
		all.append_array(ge)
	for e in all:
		var item := str(e["item"])
		if not item.is_empty() and not out.has(item):
			out.append(item)
	return out


## Deterministic for a given rng state. Single bag: the roll count (only when
## rolls is a range), then per roll the entry (1..total weight) and, for a
## quantity range, the quantity. Category rolls, per group in order: the
## chance (1..100, only when below 100), the count (only for a range), then
## per draw the entry and quantity as above.
func roll(rng: Rng) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if is_grouped():
		for g in groups:
			LootTable._roll_group(g, rng, out)
		return out
	if total_weight() <= 0:
		return out
	var count := rolls_min if rolls_min == rolls_max else rng.next_int(rolls_min, rolls_max)
	for _i in range(count):
		LootTable._draw(entries, rng, out)
	return out


## Rolls a categorised table and returns {group name: [{"item", "qty"}]} for
## the groups that dropped (tests and tools; a single bag reports "all").
func roll_by_group(rng: Rng) -> Dictionary:
	var out := {}
	if not is_grouped():
		out["all"] = roll(rng)
		return out
	for g in groups:
		var got: Array[Dictionary] = []
		if LootTable._roll_group(g, rng, got):
			out[str(g["name"])] = got
	return out


## Rolls one category group into out; false when its chance failed.
static func _roll_group(g: Dictionary, rng: Rng, out: Array[Dictionary]) -> bool:
	var chance: int = g["chance"]
	if chance < 100 and rng.next_int(1, 100) > chance:
		return false
	var lo: int = g["count_min"]
	var hi: int = g["count_max"]
	var n := lo if lo == hi else rng.next_int(lo, hi)
	var ge: Array[Dictionary] = g["entries"]
	for _i in range(n):
		LootTable._draw(ge, rng, out)
	return true


static func _weight_of(list: Array[Dictionary]) -> int:
	var total := 0
	for e in list:
		total += DictUtil.to_int(e["weight"])
	return total


## One weighted draw from list (and its quantity), merged into out.
static func _draw(list: Array[Dictionary], rng: Rng, out: Array[Dictionary]) -> void:
	var total := LootTable._weight_of(list)
	if total <= 0:
		return
	var pick := rng.next_int(1, total)
	for e in list:
		pick -= DictUtil.to_int(e["weight"])
		if pick > 0:
			continue
		var item := str(e["item"])
		if not item.is_empty():
			var lo: int = e["qty_min"]
			var hi: int = e["qty_max"]
			var qty := lo if lo == hi else rng.next_int(lo, hi)
			LootTable.merge_into(out, item, qty)
		return


## Adds qty of item to a [{"item", "qty"}] list, stacking on an existing entry.
static func merge_into(list: Array[Dictionary], item: String, qty: int) -> void:
	for entry in list:
		if str(entry["item"]) == item:
			entry["qty"] = DictUtil.to_int(entry["qty"]) + qty
			return
	list.append({"item": item, "qty": qty})


## int -> (n, n); [a, b] -> (a, b); anything else -> (fallback, fallback).
static func _range(v: Variant, fallback: int) -> Vector2i:
	if typeof(v) == TYPE_ARRAY:
		var arr: Array = v
		if arr.size() == 2:
			return Vector2i(DictUtil.to_int(arr[0], -1), DictUtil.to_int(arr[1], -1))
		return Vector2i(-1, -1)
	if DictUtil.is_number(v):
		var n := DictUtil.to_int(v, fallback)
		return Vector2i(n, n)
	return Vector2i(fallback, fallback)

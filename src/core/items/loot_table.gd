class_name LootTable
extends RefCounted
## A weighted random loot table from data/loot/<id>.json.
##
## {"schema_version": 1, "id", "rolls": int or [min, max],
##  "entries": [{"item": id, "weight": int, "qty": int or [min, max]},
##              {"nothing": true, "weight": int}, ...]}
## roll(rng) draws `rolls` times (weighted, with replacement) and returns the
## results merged by item id in first-drawn order: [{"item", "qty"}, ...].

const SCHEMA_VERSION := 1
const REQUIRED_FIELDS: Array[String] = ["id", "entries"]

var id: String = ""
var rolls_min: int = 1
var rolls_max: int = 1
## Each: {"item": String ("" = nothing), "weight": int, "qty_min": int, "qty_max": int}.
var entries: Array[Dictionary] = []


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
	var rolls := LootTable._range(d.get("rolls", 1), 1)
	t.rolls_min = rolls.x
	t.rolls_max = rolls.y
	if t.rolls_min < 0 or t.rolls_max < t.rolls_min:
		push_error("%s: invalid rolls %s" % [ctx, str(d.get("rolls"))])
		return null
	for raw in DictUtil.to_dict_array(d["entries"]):
		var nothing := DictUtil.to_bool(raw.get("nothing", false), false)
		var item := "" if nothing else str(raw.get("item", ""))
		if not nothing and item.is_empty():
			push_error("%s: an entry has neither \"item\" nor \"nothing\"" % ctx)
			return null
		var weight := DictUtil.to_int(raw.get("weight", 1), -1)
		if weight < 1:
			push_error("%s: entry '%s' needs a weight >= 1" % [ctx, item])
			return null
		var qty := LootTable._range(raw.get("qty", 1), 1)
		if qty.x < 1 or qty.y < qty.x:
			push_error("%s: entry '%s' has an invalid qty" % [ctx, item])
			return null
		t.entries.append({"item": item, "weight": weight, "qty_min": qty.x, "qty_max": qty.y})
	if t.entries.is_empty():
		push_error("%s: needs at least one entry" % ctx)
		return null
	return t


func total_weight() -> int:
	var total := 0
	for e in entries:
		total += DictUtil.to_int(e["weight"])
	return total


## Item ids this table can produce (no duplicates, entry order).
func item_ids() -> Array[String]:
	var out: Array[String] = []
	for e in entries:
		var item := str(e["item"])
		if not item.is_empty() and not out.has(item):
			out.append(item)
	return out


## Deterministic for a given rng state. Draw order: the roll count (only when
## rolls is a range), then per roll the entry (1..total weight) and, for a
## quantity range, the quantity.
func roll(rng: Rng) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var total := total_weight()
	if total <= 0:
		return out
	var n := rolls_min if rolls_min == rolls_max else rng.next_int(rolls_min, rolls_max)
	for _i in range(n):
		var pick := rng.next_int(1, total)
		for e in entries:
			pick -= DictUtil.to_int(e["weight"])
			if pick > 0:
				continue
			var item := str(e["item"])
			if not item.is_empty():
				var lo: int = e["qty_min"]
				var hi: int = e["qty_max"]
				var qty := lo if lo == hi else rng.next_int(lo, hi)
				LootTable.merge_into(out, item, qty)
			break
	return out


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

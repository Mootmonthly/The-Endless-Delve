class_name PropData
extends RefCounted
## A breakable environmental object on a floor (floor file v2): {"id", "kind":
## "barrel" | "crate" | "brazier" | "bones" | "rubble", "position": [x, y],
## "hp": int, "blocks": bool, "loot_table": id (optional), "drops": [{"item":
## id, "qty": int}] (optional)}. Attacking it to 0 hp, or an `interact` out of
## combat, destroys it: the breaker gets its guaranteed `drops` (e.g. the key
## to a locked door on the floor) and a roll of its loot table (server side).
## A blocking prop is an obstacle (like a creature that never moves: it does
## not block line of sight) until destroyed.

const KIND_BARREL := "barrel"
const KIND_CRATE := "crate"
const KIND_BRAZIER := "brazier"
const KIND_BONES := "bones"
const KIND_RUBBLE := "rubble"
const KINDS: Array[String] = [KIND_BARREL, KIND_CRATE, KIND_BRAZIER, KIND_BONES, KIND_RUBBLE]

var id: String = ""
var kind: String = KIND_BARREL
var position: Vector2i = Vector2i.ZERO
var hp: int = 1
var blocks: bool = true
## Loot table rolled when the prop is destroyed ("" = nothing).
var loot_table: String = ""
## Guaranteed items, [{"item": id, "qty": int >= 1}], given before the loot table.
var drops: Array[Dictionary] = []


## True when the prop's drops include item_id.
func drops_item(item_id: String) -> bool:
	for d in drops:
		if str(d.get("item", "")) == item_id:
			return true
	return false


func to_dict() -> Dictionary:
	var d := {"id": id, "kind": kind, "position": GridMath.vec_to_arr(position), "hp": hp, "blocks": blocks}
	if not loot_table.is_empty():
		d["loot_table"] = loot_table
	if not drops.is_empty():
		var list: Array = []
		for entry in drops:
			list.append({"item": str(entry.get("item", "")), "qty": DictUtil.to_int(entry.get("qty", 1), 1)})
		d["drops"] = list
	return d


static func from_dict(d: Dictionary) -> PropData:
	var p := PropData.new()
	p.id = str(d.get("id", ""))
	p.kind = str(d.get("kind", KIND_BARREL))
	p.position = GridMath.arr_to_vec(d.get("position", [0, 0]))
	p.hp = DictUtil.to_int(d.get("hp", 1), 1)
	p.blocks = DictUtil.to_bool(d.get("blocks", true), true)
	p.loot_table = str(d.get("loot_table", ""))
	for raw in DictUtil.to_dict_array(d.get("drops", [])):
		p.drops.append({"item": str(raw.get("item", "")), "qty": DictUtil.to_int(raw.get("qty", 1), 0)})
	return p

class_name PropData
extends RefCounted
## A breakable environmental object on a floor (floor file v2): {"id", "kind":
## "barrel" | "crate" | "brazier" | "bones" | "rubble", "position": [x, y],
## "hp": int, "blocks": bool, "loot_table": id (optional)}. Attacking it to 0
## hp, or an `interact` out of combat, destroys it and rolls its loot table
## (server side). A blocking prop is an obstacle (like a creature that never
## moves: it does not block line of sight) until destroyed.

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


func to_dict() -> Dictionary:
	var d := {"id": id, "kind": kind, "position": GridMath.vec_to_arr(position), "hp": hp, "blocks": blocks}
	if not loot_table.is_empty():
		d["loot_table"] = loot_table
	return d


static func from_dict(d: Dictionary) -> PropData:
	var p := PropData.new()
	p.id = str(d.get("id", ""))
	p.kind = str(d.get("kind", KIND_BARREL))
	p.position = GridMath.arr_to_vec(d.get("position", [0, 0]))
	p.hp = DictUtil.to_int(d.get("hp", 1), 1)
	p.blocks = DictUtil.to_bool(d.get("blocks", true), true)
	p.loot_table = str(d.get("loot_table", ""))
	return p

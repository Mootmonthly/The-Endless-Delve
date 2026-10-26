class_name ChestData
extends RefCounted
## A treasure chest placed on a floor: {"id", "position": [x, y], "table": loot
## table id, "hidden": bool}. Opening it rolls the loot table (server side).
## A hidden chest is only data for now (clients draw it once revealed).

var id: String = ""
var position: Vector2i = Vector2i.ZERO
var table_id: String = ""
var hidden: bool = false


func to_dict() -> Dictionary:
	return {"id": id, "position": GridMath.vec_to_arr(position), "table": table_id, "hidden": hidden}


## Accepts "table" (floor file format) or "table_id".
static func from_dict(d: Dictionary) -> ChestData:
	var c := ChestData.new()
	c.id = str(d.get("id", ""))
	c.position = GridMath.arr_to_vec(d.get("position", [0, 0]))
	c.table_id = str(d.get("table", d.get("table_id", "")))
	c.hidden = DictUtil.to_bool(d.get("hidden", false), false)
	return c

class_name EncounterZoneData
extends RefCounted
## An authored encounter zone on a floor: a tile rectangle (the combat region),
## the monsters it holds and where they spawn (one spawn point per monster).

var id: String = ""
var rect: Rect2i = Rect2i()  # in tiles
var monster_ids: Array[String] = []
var spawn_points: Array[Vector2i] = []


func to_dict() -> Dictionary:
	return {
		"id": id,
		"rect": GridMath.rect_to_arr(rect),
		"monster_ids": monster_ids.duplicate(),
		"spawn_points": GridMath.vec_list_to_arr(spawn_points),
	}


## Reads {"id", "rect": [x, y, w, h], "monster_ids": [...], "spawn_points": [[x, y], ...]}.
static func from_dict(d: Dictionary) -> EncounterZoneData:
	var z := EncounterZoneData.new()
	z.id = str(d.get("id", ""))
	z.rect = GridMath.arr_to_rect(d.get("rect", []))
	z.monster_ids = DictUtil.to_string_array(d.get("monster_ids", []))
	z.spawn_points = GridMath.arr_to_vec_list(d.get("spawn_points", []))
	return z

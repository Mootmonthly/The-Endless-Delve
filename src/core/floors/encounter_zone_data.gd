class_name EncounterZoneData
extends RefCounted
## An authored encounter zone on a floor: a tile rectangle (the combat region),
## the monsters it holds and where they spawn (one spawn point per monster).
## Optional authoring fields: "boss" (bool, default false) marks the set's boss
## zone; "kind" ("pack" | "boss" | "ambush", default "pack") is informational
## for now; "name" (String) is a display name. Floor file v2 adds
## "guards_stairs" (bool, default false: the zone holds the stairs tile),
## "respawns" (bool, default true: the pack comes back on the floor's respawn
## timer) and "optional" (bool, default false: a side area off every route).

const KIND_PACK := "pack"
const KIND_BOSS := "boss"
const KIND_AMBUSH := "ambush"
const KINDS: Array[String] = [KIND_PACK, KIND_BOSS, KIND_AMBUSH]

var id: String = ""
var name: String = ""
var rect: Rect2i = Rect2i()  # in tiles
var monster_ids: Array[String] = []
var spawn_points: Array[Vector2i] = []
var boss: bool = false
var kind: String = KIND_PACK
var guards_stairs: bool = false
var respawns: bool = true
var optional: bool = false


func to_dict() -> Dictionary:
	var d := {
		"id": id,
		"rect": GridMath.rect_to_arr(rect),
		"monster_ids": monster_ids.duplicate(),
		"spawn_points": GridMath.vec_list_to_arr(spawn_points),
		"boss": boss,
		"kind": kind,
		"guards_stairs": guards_stairs,
		"respawns": respawns,
		"optional": optional,
	}
	if not name.is_empty():
		d["name"] = name
	return d


## Reads {"id", "rect": [x, y, w, h], "monster_ids": [...], "spawn_points": [[x, y], ...],
## "boss": bool, "kind": String, "name": String, "guards_stairs": bool,
## "respawns": bool, "optional": bool} (all after spawn_points optional).
static func from_dict(d: Dictionary) -> EncounterZoneData:
	var z := EncounterZoneData.new()
	z.id = str(d.get("id", ""))
	z.name = str(d.get("name", ""))
	z.rect = GridMath.arr_to_rect(d.get("rect", []))
	z.monster_ids = DictUtil.to_string_array(d.get("monster_ids", []))
	z.spawn_points = GridMath.arr_to_vec_list(d.get("spawn_points", []))
	z.boss = DictUtil.to_bool(d.get("boss", false), false)
	z.kind = str(d.get("kind", KIND_PACK))
	z.guards_stairs = DictUtil.to_bool(d.get("guards_stairs", false), false)
	z.respawns = DictUtil.to_bool(d.get("respawns", true), true)
	z.optional = DictUtil.to_bool(d.get("optional", false), false)
	return z

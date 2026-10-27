class_name LandingData
extends RefCounted
## An arrival landing on a floor (floor file v2): {"id", "position": [x, y],
## "facing": "north" | "east" | "south" | "west" (optional)}. Players arriving
## from the stairs above appear on a landing; landings[0] is the floor's
## legacy "arrival" tile. Facing is where an arriving player looks (towards
## the centre of the floor), "" when unset.

const FACING_NORTH := "north"
const FACING_EAST := "east"
const FACING_SOUTH := "south"
const FACING_WEST := "west"
const FACINGS: Array[String] = [FACING_NORTH, FACING_EAST, FACING_SOUTH, FACING_WEST]
## Id given to the single landing a v1 floor's "arrival" becomes.
const ARRIVAL_ID := "arrival"

var id: String = ""
var position: Vector2i = Vector2i.ZERO
var facing: String = ""


func to_dict() -> Dictionary:
	var d := {"id": id, "position": GridMath.vec_to_arr(position)}
	if not facing.is_empty():
		d["facing"] = facing
	return d


static func from_dict(d: Dictionary) -> LandingData:
	var l := LandingData.new()
	l.id = str(d.get("id", ""))
	l.position = GridMath.arr_to_vec(d.get("position", [0, 0]))
	l.facing = str(d.get("facing", ""))
	return l


static func make(landing_id: String, p: Vector2i, facing_dir: String = "") -> LandingData:
	var l := LandingData.new()
	l.id = landing_id
	l.position = p
	l.facing = facing_dir
	return l

class_name DoorData
extends RefCounted
## A door on a floor (floor file v2): {"id", "position": [x, y], "state":
## "open" | "closed" | "locked", "dc": int (optional), "key_item": item id
## (optional)}. The door tile is floor in the rows; it is walkable only while
## the door is open, and a closed or locked door blocks line of sight. A
## locked door opens with key_item, a thieves' tools check against dc, or the
## Knock spell (resolved by the server). Doors sit in 1-wide corridor cells.

const STATE_OPEN := "open"
const STATE_CLOSED := "closed"
const STATE_LOCKED := "locked"
const STATES: Array[String] = [STATE_OPEN, STATE_CLOSED, STATE_LOCKED]

var id: String = ""
var position: Vector2i = Vector2i.ZERO
var state: String = STATE_CLOSED
## Thieves' tools DC to pick the lock (0 = no DC given; only key or Knock).
var dc: int = 0
## Item id that unlocks the door ("" = none).
var key_item: String = ""


func is_open() -> bool:
	return state == STATE_OPEN


func is_locked() -> bool:
	return state == STATE_LOCKED


## True while the door stops movement and line of sight (closed or locked).
func blocks() -> bool:
	return state != STATE_OPEN


func to_dict() -> Dictionary:
	var d := {"id": id, "position": GridMath.vec_to_arr(position), "state": state}
	if dc > 0:
		d["dc"] = dc
	if not key_item.is_empty():
		d["key_item"] = key_item
	return d


static func from_dict(d: Dictionary) -> DoorData:
	var door := DoorData.new()
	door.id = str(d.get("id", ""))
	door.position = GridMath.arr_to_vec(d.get("position", [0, 0]))
	door.state = str(d.get("state", STATE_CLOSED))
	door.dc = DictUtil.to_int(d.get("dc", 0), 0)
	door.key_item = str(d.get("key_item", ""))
	return door

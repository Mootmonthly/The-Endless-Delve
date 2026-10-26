class_name EncounterSession
extends RefCounted
## Server bookkeeping for one active core Encounter: which zone it belongs
## to, which ServerEntities fight in it, and when the next monster turn is due.

var id: String = ""
var zone: EncounterZoneData = null
var encounter: Encounter = null
var entity_ids: Array[String] = []
## Server tick on which the current monster actor resolves its turn; -1 when
## no monster turn is scheduled (a player is acting).
var monster_due_tick: int = -1


func _init(session_id: String, encounter_zone: EncounterZoneData, enc: Encounter) -> void:
	id = session_id
	zone = encounter_zone
	encounter = enc


func region() -> Rect2i:
	return encounter.region if encounter != null else Rect2i()


func is_active() -> bool:
	return encounter != null and encounter.state == Encounter.State.ACTIVE

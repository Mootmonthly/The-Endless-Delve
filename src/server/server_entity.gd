class_name ServerEntity
extends RefCounted
## One creature standing on a floor in the InstanceServer's world model: a
## player character or a monster. Exploration state (position, walking path)
## lives here; while the entity fights, `combatant` is its Combatant in the
## active Encounter and the encounter owns its position.

const KIND_PLAYER := "player"
const KIND_MONSTER := "monster"

var id: String = ""
var kind: String = KIND_PLAYER
var position: Vector2i = Vector2i.ZERO
## Remaining exploration steps (excluding the current tile); empty when idle.
var path: Array[Vector2i] = []
## Where the current path leads (used to re-path around a blocker).
var target: Vector2i = Vector2i.ZERO
var peer_id: int = 0  # owning peer for players; 0 for monsters
var sheet: CharacterSheet = null  # server-owned copy; persists across encounters
## Monsters: the zone they spawned in. Players: the zone of the encounter
## they are fighting in ("" while exploring).
var zone_id: String = ""
var display_name: String = ""
var monster_id: String = ""  # empty for players
var attacks: Array[Dictionary] = []  # monsters: stat-block attacks
var encounter_id: String = ""  # "" while exploring
var combatant: Combatant = null  # set while in an encounter
var step_timer: int = 0  # ticks since the last exploration step


func is_player() -> bool:
	return kind == KIND_PLAYER


func is_monster() -> bool:
	return kind == KIND_MONSTER


func in_combat() -> bool:
	return not encounter_id.is_empty()


func is_alive() -> bool:
	return sheet != null and sheet.is_alive()


## A fresh Combatant sharing this entity's sheet (so damage persists), placed
## at the entity's position.
func make_combatant() -> Combatant:
	var c: Combatant = null
	if is_player():
		c = Combatant.from_sheet(id, sheet, Combatant.TEAM_PLAYERS)
	else:
		c = Combatant.new()
		c.id = id
		c.display_name = display_name
		c.team = Combatant.TEAM_MONSTERS
		c.sheet = sheet
		c.monster_id = monster_id
		for attack in attacks:
			c.attacks.append(attack.duplicate(true))
	c.position = position
	return c


## JSON-safe entry for an EXPLORE_STATE result. Beyond the required
## id / position / kind it carries name, monster_id, hp, max_hp, dead and
## in_combat so a client can label and colour entities.
func to_state() -> Dictionary:
	return {
		"id": id,
		"kind": kind,
		"position": GridMath.vec_to_arr(position),
		"name": display_name,
		"monster_id": monster_id,
		"hp": sheet.current_hp if sheet != null else 0,
		"max_hp": sheet.max_hp if sheet != null else 0,
		"dead": not is_alive(),
		"in_combat": in_combat(),
	}

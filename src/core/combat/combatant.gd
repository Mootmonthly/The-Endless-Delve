class_name Combatant
extends RefCounted
## One participant in an Encounter: a player character or a monster.

const TEAM_PLAYERS := 0
const TEAM_MONSTERS := 1

var id: String = ""
var display_name: String = ""
var team: int = TEAM_PLAYERS  # 0 players, 1 monsters; PVP gives each party its own team
var sheet: CharacterSheet = null
var attacks: Array[Dictionary] = []
var monster_id: String = ""  # empty for player characters
var initiative: int = 0
var join_order: int = -1  # set by InitiativeTracker; final tie-breaker
var has_acted_this_round: bool = false

## Grid and per-turn resources (reset by reset_turn() at this combatant's turn start).
var position: Vector2i = Vector2i.ZERO
var movement_remaining: int = 0  # tiles
var action_used: bool = false
var bonus_action_used: bool = false
var reaction_used: bool = false
var dodging: bool = false
var disengaging: bool = false


## Player character: the sheet's weapon attacks, then an unarmed strike fallback.
static func from_sheet(combatant_id: String, character: CharacterSheet, team_id: int = TEAM_PLAYERS) -> Combatant:
	var c := Combatant.new()
	c.id = combatant_id
	c.display_name = character.name
	c.team = team_id
	c.sheet = character
	for attack in character.attacks:
		c.attacks.append(attack.duplicate(true))
	c.attacks.append(character.unarmed_strike())
	return c


static func from_monster(combatant_id: String, def: MonsterDefinition, team_id: int, rng: Rng, roll_hp: bool = false) -> Combatant:
	var c := Combatant.new()
	c.id = combatant_id
	c.display_name = def.display_name
	c.team = team_id
	c.monster_id = def.id
	c.sheet = def.to_sheet(rng, roll_hp)
	for attack in def.attacks:
		c.attacks.append(attack.duplicate(true))
	return c


## Rebuilds a combatant from a setup entry (see to_setup_dict()). The attacks
## list is taken verbatim, so the result matches the original exactly.
static func from_setup_dict(d: Dictionary) -> Combatant:
	var c := Combatant.new()
	c.id = str(d.get("id", ""))
	c.team = DictUtil.to_int(d.get("team", TEAM_PLAYERS), TEAM_PLAYERS)
	c.position = GridMath.arr_to_vec(d.get("position", [0, 0]))
	var sheet_v: Variant = d.get("sheet", {})
	var sheet_dict: Dictionary = sheet_v if typeof(sheet_v) == TYPE_DICTIONARY else {}
	c.sheet = CharacterSheet.from_dict(sheet_dict)
	c.display_name = str(d.get("display_name", c.sheet.name))
	c.monster_id = str(d.get("monster_id", ""))
	for raw in DictUtil.to_dict_array(d.get("attacks", [])):
		c.attacks.append(CharacterSheet.normalize_attack(raw))
	return c


## JSON-safe snapshot: {"id", "team", "position": [x, y], "sheet", "attacks",
## "monster_id", "display_name"}.
func to_setup_dict() -> Dictionary:
	return {
		"id": id,
		"display_name": display_name,
		"team": team,
		"position": GridMath.vec_to_arr(position),
		"sheet": sheet.to_dict() if sheet != null else {},
		"attacks": attacks.duplicate(true),
		"monster_id": monster_id,
	}


func is_alive() -> bool:
	return sheet != null and sheet.is_alive()


## Alive and above 0 hp: able to act.
func is_conscious() -> bool:
	return sheet != null and sheet.is_conscious()


## At 0 hp, not dead and not stable, and rolling death saves (players).
## Monsters never use death saves: they die at 0 hp, so they are never dying.
func is_dying() -> bool:
	return sheet != null and sheet.uses_death_saves and sheet.is_unconscious() and not sheet.stable


## Keeps its team "in the fight": conscious, or still dying (death saves
## pending). Stable and dead combatants do not.
func is_in_fight() -> bool:
	return is_conscious() or is_dying()


func is_monster() -> bool:
	return not monster_id.is_empty()


func dex_score() -> int:
	return sheet.abilities.get_score(Ability.Type.DEX) if sheet != null else 10


func initiative_modifier() -> int:
	return sheet.initiative_modifier() if sheet != null else 0


## Walking speed in tiles (speed in feet / 5).
func speed_tiles() -> int:
	return GridMath.feet_to_tiles(sheet.speed) if sheet != null else 0


## Start-of-turn reset: full movement, fresh action/bonus action/reaction,
## Dodge and Disengage end.
func reset_turn() -> void:
	movement_remaining = speed_tiles()
	action_used = false
	bonus_action_used = false
	reaction_used = false
	dodging = false
	disengaging = false

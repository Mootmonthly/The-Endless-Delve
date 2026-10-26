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


static func from_sheet(combatant_id: String, character: CharacterSheet, team_id: int = TEAM_PLAYERS) -> Combatant:
	var c := Combatant.new()
	c.id = combatant_id
	c.display_name = character.name
	c.team = team_id
	c.sheet = character
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


func is_alive() -> bool:
	return sheet != null and sheet.is_alive()


## Alive and above 0 hp: able to act and to keep its team in the fight.
func is_conscious() -> bool:
	return sheet != null and sheet.is_conscious()


func dex_score() -> int:
	return sheet.abilities.get_score(Ability.Type.DEX) if sheet != null else 10


func initiative_modifier() -> int:
	return sheet.initiative_modifier() if sheet != null else 0

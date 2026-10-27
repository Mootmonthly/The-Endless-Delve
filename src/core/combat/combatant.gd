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
var creature_type: String = ""  # monsters: "undead", "humanoid", ... ("" for player characters)
var challenge_rating: float = 0.0  # monsters (Destroy Undead)
## Attack rolls per Attack action (Extra Attack; a monster's Multiattack size).
var attacks_per_action: int = 1
## Monster Multiattack: attack names in stat-block order ([] = none).
var multiattack: Array[String] = []
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
var attack_action_taken: bool = false  # took the Attack action this turn (Martial Arts bonus strike)
var attacks_remaining: int = 0  # further attacks of this turn's Attack action
var bonus_attacks_remaining: int = 0  # bonus-action attacks granted (Flurry of Blows)
var bonus_attack_source: String = ""  # feature that granted bonus_attacks_remaining
var action_surged: bool = false  # Action Surge used this turn

## Encounter-scoped effects (not part of the setup snapshot; a new encounter
## starts without them).
var raging: bool = false
var rage_started_round: int = 0
var inspiration_die: int = 0  # Bardic Inspiration die added to the next attack roll (0 = none)
var inspiration_source: String = ""
var mocked: bool = false  # Vicious Mockery: disadvantage on the next attack roll, until its turn ends
var mocked_by: String = ""
var slowed_tiles: int = 0  # Ray of Frost: movement lost at the start of its next turn
var guided_by: String = ""  # Guiding Bolt: next attack roll against it has advantage
var guided_turns_left: int = 0  # turn ends of guided_by before the mark fades
## Hex and similar marks: caster id -> {"effect", "dice", "type"}; the caster's
## attack hits on this combatant add the dice.
var marks: Dictionary = {}
var sneak_attack_turn: int = -1  # encounter turn counter when Sneak Attack was last used
var colossus_turn: int = -1  # encounter turn counter when Colossus Slayer was last used
var divine_strike_turn: int = -1  # encounter turn counter when Divine Strike was last used
var horde_breaker_turn: int = -1  # encounter turn counter when Horde Breaker was last used
## Conditions with durations (see Conditions): [{"condition", "source", "duration", "turns_left", ...}].
var conditions: Array[Dictionary] = []
## The concentration spell being maintained: {"spell": id, "slot_level": int} ({} = none).
var concentration: Dictionary = {}
var reckless: bool = false  # Reckless Attack: attacks against it have advantage until its next turn
var frenzied: bool = false  # Berserker Frenzy while raging
var rage_started_turn: int = -1  # encounter turn counter when it started raging
var sacred_weapon_bonus: int = 0  # Sacred Weapon: added to its weapon attack rolls (0 = none)
var sacred_weapon_turns: int = 0  # its turn ends before Sacred Weapon fades
var pact_weapon: bool = false  # Pact of the Blade weapon summoned (an extra attack entry)
## Hidden (Hide action): stealth_total is the Stealth check it beat perception
## with. Attacks from hiding have advantage and reveal it.
var hidden: bool = false
var stealth_total: int = 0
## Encounter effects with modifiers (bless, haste, shield, sanctuary, ...):
## [{"effect", "source", "spell"?, "duration", "turns_left", <modifiers>}] (see Encounter._apply_buff).
var buffs: Array[Dictionary] = []
## Summoned / companion creatures: the summoner's id ("" = not summoned). Such
## combatants act right after their owner and the encounter runs their turns
## (MonsterBrain); they never keep a team in the fight.
var owner_id: String = ""
var summon_spell: String = ""
var summon_turns_left: int = -1  # owner's turn ends before it vanishes (-1 = no limit)
var companion_index: int = -1  # index in the owner's sheet.companions (-1 = summoned this fight)
var auto_controlled: bool = false
var summon_concentration: bool = false  # vanishes when the owner's concentration ends
var familiar: bool = false  # Find Familiar: cannot attack, uses the Help action
var untargetable: bool = false  # Spiritual Weapon and other spell objects
## Reaction policy: trigger or reaction id -> "auto" | "never" (missing = "auto").
## Triggers: creature_hit_me, creature_left_reach, ally_attacked, ally_hit,
## spell_cast_in_range, damage_taken, failed_save, missed.
var reaction_policy: Dictionary = {}
var teleport_tiles: int = 0  # teleport movement left this turn (Misty Step without a point)
var died_round: int = -1  # encounter round when it died (Revivify: within 10 rounds)
var tiles_moved: int = 0  # tiles moved this turn (Supreme Sneak, Hide in Plain Sight)
## Help action: the next attack roll against it by a member of help_team has
## advantage (until helped_by's next turn).
var helped_by: String = ""
var help_team: int = -1
## Multiattack Defense: attacker id -> turn counter of its hit (+4 AC vs it that turn).
var defended_against: Dictionary = {}
## Wild Shape / Polymorph: {"monster", "kind", "saved": {...}} ({} = own form).
var form: Dictionary = {}
var elemental_resistance: String = ""  # Elemental Affinity: resisted type this encounter
var haste_action_turn: int = -1  # encounter turn counter when the hasted action was used
## Round C: inside an Antimagic Field (set by the encounter): spell buffs and
## spell conditions on it are suppressed, its spell summons lose their turns.
var antimagic: bool = false
## Round C control: the controller's id while dominated ("" = itself), its own
## team meanwhile, and orders queued by `control` intents for its next turn.
var controlled_by: String = ""
var original_team: int = -1
var orders: Array[Dictionary] = []
var was_auto_controlled: bool = false
## Round C absence: reasons it is out of reach ("banished", "ethereal",
## "possessed"); while any is set it is untargetable and occupies no tile.
var absent: Array[String] = []
var absent_saved_untargetable: bool = false
## Banishment / Maze / Imprisonment / Plane Shift: {"source", "spell",
## "turns_left" (-1 = until the source's concentration ends), "permanent",
## "position": [x, y], "native_permanent"?, "escape"? {ability, dc},
## "return_damage"? {dice, type, immune_types}} ({} = here).
var banished: Dictionary = {}
## Round C illusions (Silent / Major Image, Project Image, Mislead, ...): {"spell",
## "dc", "source"} ({} = a real creature). Hostiles treat it as real until an
## Investigation check against dc succeeds when they interact with it.
var illusion: Dictionary = {}
## Round C extra turns in a row (Time Stop, Thief's Reflexes): taken right
## after its turn ends; time_stopped forbids affecting other creatures.
var extra_turns: int = 0
var extra_turn_source: String = ""
var time_stopped: bool = false
## Round C class features: whether a raging barbarian attacked a hostile or
## took damage since its last turn started (else the rage ends, unless
## Persistent Rage); the creature its Quivering Palm vibrations are in ("" =
## none); the turn counter of its last Foe Slayer.
var rage_kept: bool = false
var quivering_target: String = ""
var foe_slayer_turn: int = -1


## Player character: the sheet's weapon attacks, then an unarmed strike fallback.
static func from_sheet(combatant_id: String, character: CharacterSheet, team_id: int = TEAM_PLAYERS) -> Combatant:
	var c := Combatant.new()
	c.id = combatant_id
	c.display_name = character.name
	c.team = team_id
	c.sheet = character
	c.attacks_per_action = character.attacks_per_action()
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
	c.creature_type = def.creature_type
	c.challenge_rating = def.challenge_rating
	c.multiattack = def.multiattack.duplicate()
	c.attacks_per_action = maxi(1, def.multiattack.size())
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
	c.creature_type = str(d.get("creature_type", ""))
	c.challenge_rating = DictUtil.to_float(d.get("challenge_rating", 0.0), 0.0)
	c.attacks_per_action = maxi(1, DictUtil.to_int(d.get("attacks_per_action", 1), 1))
	c.multiattack = DictUtil.to_string_array(d.get("multiattack", []))
	for raw in DictUtil.to_dict_array(d.get("attacks", [])):
		c.attacks.append(CharacterSheet.normalize_attack(raw))
	var policy_v: Variant = d.get("reaction_policy", {})
	if typeof(policy_v) == TYPE_DICTIONARY:
		var policy: Dictionary = policy_v
		c.reaction_policy = policy.duplicate()
	return c


## JSON-safe snapshot: {"id", "team", "position": [x, y], "sheet", "attacks",
## "monster_id", "display_name", "creature_type", "challenge_rating",
## "attacks_per_action", "multiattack"}.
func to_setup_dict() -> Dictionary:
	return {
		"id": id,
		"display_name": display_name,
		"team": team,
		"position": GridMath.vec_to_arr(position),
		"sheet": sheet.to_dict() if sheet != null else {},
		"attacks": attacks.duplicate(true),
		"monster_id": monster_id,
		"creature_type": creature_type,
		"challenge_rating": challenge_rating,
		"attacks_per_action": attacks_per_action,
		"multiattack": multiattack.duplicate(),
		"reaction_policy": reaction_policy.duplicate(),
	}


## Whether its reaction policy allows `reaction` (a reaction id) for trigger.
## A key for the reaction id wins over the trigger key; default "auto".
func reaction_allowed(trigger: String, reaction: String) -> bool:
	if reaction_policy.has(reaction):
		return str(reaction_policy[reaction]) != "never"
	return str(reaction_policy.get(trigger, "auto")) != "never"


## Summoned or companion creature.
func is_summon() -> bool:
	return not owner_id.is_empty()


## Its buffs that currently work: all of them, or inside an Antimagic Field
## only those not from a spell.
func live_buffs() -> Array[Dictionary]:
	if not antimagic:
		return buffs
	var out: Array[Dictionary] = []
	for b in buffs:
		if str(b.get("spell", "")).is_empty():
			out.append(b)
	return out


## Sum of an integer buff modifier across its active buffs ("ac", ...).
func buff_int(key: String) -> int:
	var total := 0
	for b in live_buffs():
		total += DictUtil.to_int(b.get(key, 0), 0)
	return total


## True when any active buff sets the flag.
func buff_flag(key: String) -> bool:
	for b in live_buffs():
		if b.get(key, false) == true:
			return true
	return false


## Dice strings of a buff modifier ("attack_dice", "save_dice", ...).
func buff_dice(key: String) -> Array[String]:
	var out: Array[String] = []
	for b in live_buffs():
		var v := str(b.get(key, ""))
		if not v.is_empty():
			out.append(v)
	return out


## String-array buff modifier values merged ("resist", "immune_conditions", ...).
func buff_list(key: String) -> Array[String]:
	var out: Array[String] = []
	for b in live_buffs():
		for v in DictUtil.to_string_array(b.get(key, [])):
			if not out.has(v):
				out.append(v)
	return out


func has_buff(effect: String) -> bool:
	for b in live_buffs():
		if str(b.get("effect", "")) == effect:
			return true
	return false


## Armor class with buffs (Shield, Shield of Faith, Haste, Slow, Barkskin).
func armor_class() -> int:
	var ac := sheet.armor_class() + buff_int("ac")
	for b in live_buffs():
		var floor_ac := DictUtil.to_int(b.get("ac_min", 0), 0)
		if floor_ac > ac:
			ac = floor_ac
	return ac


## Darkvision in tiles: the sheet's (ancestry, stat block), a buff's
## "darkvision_ft" (Darkvision spell) or Devil's Sight (120 ft); 0 = none.
func darkvision_tiles() -> int:
	var feet := sheet.darkvision_ft if sheet != null else 0
	if sheet != null and sheet.invocations.has("devils_sight"):
		feet = maxi(feet, 120)
	for b in live_buffs():
		feet = maxi(feet, DictUtil.to_int(b.get("darkvision_ft", 0), 0))
	return GridMath.feet_to_tiles(feet)


## Fly speed in tiles (stat block, Fly, Dragon Wings; 0 = none).
func fly_tiles() -> int:
	var feet := sheet.fly_speed if sheet != null else 0
	for b in live_buffs():
		var ft := DictUtil.to_int(b.get("fly_ft", 0), 0)
		if ft < 0:
			ft = sheet.effective_speed()
		feet = maxi(feet, ft)
	return GridMath.feet_to_tiles(feet)


## Flying, levitating or climbing (Spider Climb) creatures, and leapers (Jump),
## ignore ground effects (grease, spike growth).
func ignores_ground() -> bool:
	return fly_tiles() > 0 or buff_flag("levitating") or buff_flag("climbing") or buff_flag("ignores_ground")


## Resilient Sphere: sealed in a globe of force (nothing passes either way).
func is_sealed() -> bool:
	return buff_flag("sealed")


## Invisible (the condition, or Empty Body / Greater Invisibility buffs).
func is_invisible() -> bool:
	return has_condition(Conditions.INVISIBLE)


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
## pending). Stable and dead combatants do not, nor creatures banished for
## good (Imprisonment, Plane Shift).
func is_in_fight() -> bool:
	if banished.get("permanent", false) == true:
		return false
	return is_conscious() or is_dying()


func is_monster() -> bool:
	return not monster_id.is_empty()


func dex_score() -> int:
	return sheet.abilities.get_score(Ability.Type.DEX) if sheet != null else 10


func initiative_modifier() -> int:
	return sheet.initiative_modifier() if sheet != null else 0


## Initiative roll mode: advantage with Feral Instinct, disadvantage with
## exhaustion (ability checks).
func initiative_mode() -> D20.RollMode:
	if sheet == null:
		return D20.RollMode.NORMAL
	return D20.combine(sheet.has_feature("feral_instinct"), sheet.exhaustion >= 1)


## Walking speed in tiles (speed in feet / 5, with Fast Movement / Unarmored
## Movement); 0 while grappled, restrained, stunned or paralyzed.
func speed_tiles() -> int:
	if sheet == null or is_immobilized() or buff_flag("speed_zero"):
		return 0
	var feet := sheet.effective_speed() + buff_int("speed_bonus_ft")
	var tiles := GridMath.feet_to_tiles(maxi(0, feet))
	if buff_flag("speed_double"):
		tiles *= 2
	if buff_flag("speed_half"):
		tiles = floori(tiles / 2.0)
	tiles = maxi(tiles, fly_tiles() if not buff_flag("speed_half") else floori(fly_tiles() / 2.0))
	for b in live_buffs():
		var cap := DictUtil.to_int(b.get("speed_cap_ft", -1), -1)
		if cap >= 0:
			tiles = mini(tiles, GridMath.feet_to_tiles(cap))
	return tiles


## Teams whose creatures it may not act against (Suggestion, Calm Emotions).
func suggested_teams() -> Array[int]:
	var out: Array[int] = []
	for entry in conditions:
		if str(entry.get("condition", "")) == Conditions.SUGGESTED:
			var t := DictUtil.to_int(entry.get("source_team", -1), -1)
			if t >= 0 and not out.has(t):
				out.append(t)
	return out


func is_ethereal() -> bool:
	return absent.has("ethereal")


## Start-of-turn reset: full movement (minus any slow), fresh action/bonus
## action/reaction, Dodge, Disengage and Reckless Attack end.
func reset_turn() -> void:
	movement_remaining = maxi(0, speed_tiles() - slowed_tiles)
	slowed_tiles = 0
	action_used = false
	bonus_action_used = false
	reaction_used = false
	dodging = false
	disengaging = false
	attack_action_taken = false
	attacks_remaining = 0
	bonus_attacks_remaining = 0
	bonus_attack_source = ""
	action_surged = false
	reckless = false
	teleport_tiles = 0
	tiles_moved = 0
	defended_against.clear()


# --- conditions ----------------------------------------------------------------

## True when it has the condition (an encounter condition entry, the sheet's
## lasting conditions, or a condition that includes it: stunned and paralyzed
## include incapacitated).
func has_condition(condition: String) -> bool:
	if condition == Conditions.INCAPACITATED:
		for c in Conditions.INCAPACITATING:
			if _has_own_condition(c):
				return true
		return false
	return _has_own_condition(condition)


func _has_own_condition(condition: String) -> bool:
	if sheet != null and sheet.conditions.has(condition):
		return true
	for entry in conditions:
		if str(entry.get("condition", "")) == condition:
			if antimagic and not str(entry.get("spell", "")).is_empty():
				continue
			return true
	return false


## Ids of the creatures it is frightened of (entries with a source).
func condition_sources(condition: String) -> Array[String]:
	var out: Array[String] = []
	for entry in conditions:
		if str(entry.get("condition", "")) == condition:
			var src := str(entry.get("source", ""))
			if not src.is_empty() and not out.has(src):
				out.append(src)
	return out


## Incapacitated (stunned, paralyzed, unconscious): no actions, bonus actions
## or reactions.
func is_incapacitated() -> bool:
	return has_condition(Conditions.INCAPACITATED)


## Speed 0: grappled, restrained, stunned or paralyzed.
func is_immobilized() -> bool:
	for c in Conditions.IMMOBILIZING:
		if has_condition(c):
			return true
	return false


## Stunned, paralyzed, unconscious (Sleep) or its turn is lost (Command,
## confusion): the turn passes without it acting or moving.
func loses_turn() -> bool:
	if antimagic and is_summon() and not summon_spell.is_empty():
		return true
	if absent.has("banished") or absent.has("possessed"):
		return true
	for c in Conditions.TURN_SKIPPING:
		if has_condition(c):
			return true
	return false


## STR / DEX saves fail automatically (stunned, paralyzed, unconscious, petrified).
func auto_fails_physical_saves() -> bool:
	for c in Conditions.PHYSICAL_SAVE_FAIL:
		if has_condition(c):
			return true
	return false


## Turned (Turn Undead): it may only move away and Dash.
func is_fleeing() -> bool:
	for entry in conditions:
		if entry.get("flee", false) == true:
			return true
	return false


## Conscious and not incapacitated: can take reactions (opportunity attacks).
func can_react() -> bool:
	return is_conscious() and not reaction_used and not is_incapacitated() and not is_fleeing() \
			and not has_condition(Conditions.NO_REACTIONS) and not untargetable and not buff_flag("no_reactions")


## Immune to a condition: its sheet, active buffs (Heroism, Freedom of
## Movement, ...) and Mindless Rage (charmed / frightened while raging).
func is_immune_to_condition(condition: String) -> bool:
	if sheet == null:
		return false
	if sheet.condition_immunities.has(condition) or buff_list("immune_conditions").has(condition):
		return true
	if Conditions.CHARM_EFFECTS.has(condition) and condition != Conditions.CHARMED and is_immune_to_condition(Conditions.CHARMED):
		return true
	if raging and sheet.has_feature("mindless_rage") and condition in [Conditions.CHARMED, Conditions.FRIGHTENED]:
		return true
	return false


## Damage after the sheet's immunities / resistances / vulnerabilities, with
## Rage's resistance to bludgeoning, piercing and slashing while raging, and
## buff resistances (Stoneskin, Protection from Energy, Warding Bond, ...).
## magical: from a spell or a magical weapon (beats "nonmagical" resistances).
func adjust_damage(amount: int, damage_type: String, magical: bool = false) -> int:
	if sheet == null:
		return amount
	if is_sealed():
		return 0
	var extra: Array[String] = buff_list("resist")
	if raging:
		for t: String in ["bludgeoning", "piercing", "slashing"]:
			if not extra.has(t):
				extra.append(t)
	if not elemental_resistance.is_empty() and not extra.has(elemental_resistance):
		extra.append(elemental_resistance)
	if buff_flag("resist_nonmagical") and not magical:
		for t: String in ["bludgeoning", "piercing", "slashing"]:
			if not extra.has(t):
				extra.append(t)
	if (buff_flag("resist_all") or has_condition(Conditions.PETRIFIED)) and not extra.has(damage_type.to_lower()):
		extra.append(damage_type.to_lower())
	var out := sheet.adjust_damage_for_type(amount, damage_type, extra, magical, buff_list("immune_damage"))
	if buff_flag("vulnerable_all"):
		out *= 2
	return out


## Index of the first melee attack (opportunity attacks), or -1.
func first_melee_attack() -> int:
	for i in range(attacks.size()):
		if str(attacks[i].get("kind", "melee")) == "melee":
			return i
	return -1


## Index of the first ranged or thrown attack, or -1.
func first_ranged_attack() -> int:
	for i in range(attacks.size()):
		if str(attacks[i].get("kind", "melee")) in ["ranged", "thrown"]:
			return i
	return -1

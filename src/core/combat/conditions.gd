class_name Conditions
extends RefCounted
## SRD conditions tracked on a Combatant during an encounter, and their durations.
##
## A condition entry (Combatant.conditions) is a JSON-safe Dictionary:
## {"condition": id, "source": combatant id ("" = none), "duration": {"type", ...},
##  "turns_left": int (turn ends still to count, see below), "spell": id (optional,
##  set when a concentration spell applied it), "flee": bool (optional, Turn Undead:
##  must move away and may only Dash), "ends_on_damage": bool (optional)}.
## Durations ("duration" objects, also carried by condition_applied events):
##   {"type": "until_source_next_turn"}  ends at the end of the source's next turn
##   {"type": "until_target_turn_end"}   ends at the end of the target's next (or current) turn
##   {"type": "save_ends", "ability": "CON", "dc": 13}  the target saves at the end of each of its turns
##   {"type": "rounds", "rounds": n}     ends after n of the target's turn ends
##   {"type": "encounter"}               lasts until the encounter ends
## Rules (applied by Encounter):
##   prone: its attacks have disadvantage; attacks against it have advantage from an
##          adjacent attacker, else disadvantage; standing up costs half its speed.
##   stunned / paralyzed: incapacitated, cannot move, fail STR and DEX saves, attacks
##          against it have advantage; a hit on a paralyzed creature from an adjacent
##          attacker is a critical hit. Its turns are skipped.
##   incapacitated: no actions, bonus actions or reactions (may still move).
##   frightened: disadvantage on attack rolls while a source is in line of sight;
##          cannot move closer to a source.
##   poisoned: disadvantage on attack rolls (SRD: and ability checks, not modelled).
##   restrained: speed 0, its attacks have disadvantage, attacks against it advantage,
##          disadvantage on DEX saves.
##   grappled: speed 0.
##   blinded: its attacks have disadvantage, attacks against it have advantage.
##   charmed: cannot attack or target the source with harmful effects.
##   invisible: its attacks have advantage, attacks against it disadvantage.
##   unconscious (Sleep): incapacitated, prone-like: attacks against it have
##          advantage and crit from an adjacent attacker, fails STR / DEX saves,
##          turns skipped; it wakes when it takes damage.
##   petrified: incapacitated, speed 0, attacks against it advantage, fails STR /
##          DEX saves, resistance to all damage, turns skipped.
##   deafened: no rules beyond the label (cannot hear).
##   turn_lost (not SRD; Command "grovel", confusion): its next turn is skipped.
## Durations also include {"type": "until_target_turn_start"} (ends when the
## target's next turn starts; buffs such as Shield).
## Round C tracked conditions (not SRD conditions; charm effects, so a
## creature immune to charmed is immune to them):
##   dominated (Dominate Person / Beast / Monster, Magic Jar): the source's team
##          controls it: its team switches until it ends, the encounter runs
##          its turns (MonsterBrain, or the controller's `control` orders);
##          each time it takes damage it repeats the save ("save_on_damage").
##   suggested (Suggestion, Mass Suggestion, Calm Emotions): it takes no hostile
##          action against the source's side; ends when that side damages it.
##   compelled (Compulsion): at the start of its turns it moves as far as it can
##          toward the entry's "toward" point.
## ethereal (Blink, Etherealness) is tracked too: the creature is out of reach
## (untargetable, not occupying its tile) and cannot affect creatures that are
## not ethereal.

const PRONE := "prone"
const STUNNED := "stunned"
const PARALYZED := "paralyzed"
const INCAPACITATED := "incapacitated"
const FRIGHTENED := "frightened"
const POISONED := "poisoned"
const RESTRAINED := "restrained"
const GRAPPLED := "grappled"
const BLINDED := "blinded"
const CHARMED := "charmed"
const INVISIBLE := "invisible"
const UNCONSCIOUS := "unconscious"
const PETRIFIED := "petrified"
const DEAFENED := "deafened"
const ALL: Array[String] = [PRONE, STUNNED, PARALYZED, INCAPACITATED, FRIGHTENED, POISONED, RESTRAINED, GRAPPLED, BLINDED, CHARMED, INVISIBLE, UNCONSCIOUS, PETRIFIED, DEAFENED]
## Not an SRD condition: the creature's next turn is skipped (Command, confusion).
const TURN_LOST := "turn_lost"
## Not an SRD condition but tracked the same way: cannot take reactions
## (Open Hand Technique).
const NO_REACTIONS := "no_reactions"
const DOMINATED := "dominated"
const SUGGESTED := "suggested"
const COMPELLED := "compelled"
const ETHEREAL := "ethereal"
## Round C tracked conditions (see the class doc).
const TRACKED: Array[String] = [TURN_LOST, DOMINATED, SUGGESTED, COMPELLED, ETHEREAL]
## Charm effects: immunity to charmed covers them.
const CHARM_EFFECTS: Array[String] = [CHARMED, DOMINATED, SUGGESTED, COMPELLED]
## Conditions that include "incapacitated".
const INCAPACITATING: Array[String] = [INCAPACITATED, STUNNED, PARALYZED, UNCONSCIOUS, PETRIFIED]
## Conditions whose creature cannot move (speed 0).
const IMMOBILIZING: Array[String] = [STUNNED, PARALYZED, RESTRAINED, GRAPPLED, UNCONSCIOUS, PETRIFIED]
## Conditions that give the creature's own attack rolls disadvantage (frightened is
## conditional on line of sight and handled separately).
const ATTACKER_DISADVANTAGE: Array[String] = [PRONE, POISONED, RESTRAINED, BLINDED]
## Conditions that give attack rolls against the creature advantage (prone is by distance).
const TARGET_ADVANTAGE: Array[String] = [STUNNED, PARALYZED, RESTRAINED, BLINDED, UNCONSCIOUS, PETRIFIED]
## Conditions under which STR and DEX saves fail automatically.
const PHYSICAL_SAVE_FAIL: Array[String] = [STUNNED, PARALYZED, UNCONSCIOUS, PETRIFIED]
## Conditions whose creature's turns are skipped.
const TURN_SKIPPING: Array[String] = [STUNNED, PARALYZED, UNCONSCIOUS, PETRIFIED, TURN_LOST]

const DURATION_SOURCE_NEXT_TURN := "until_source_next_turn"
const DURATION_TARGET_TURN_END := "until_target_turn_end"
const DURATION_SAVE_ENDS := "save_ends"
const DURATION_ROUNDS := "rounds"
const DURATION_ENCOUNTER := "encounter"
const DURATION_TARGET_TURN_START := "until_target_turn_start"
## Round C: {"type": "save_track", "ability", "dc", "successes", "failures"}:
## a save at the end of each of the target's turns; three successes end it,
## three failures make it last (and the entry's "track_effect" takes hold:
## Contagion's disease, Prismatic indigo's petrification).
const DURATION_SAVE_TRACK := "save_track"
const DURATION_TYPES: Array[String] = [DURATION_SOURCE_NEXT_TURN, DURATION_TARGET_TURN_END, DURATION_SAVE_ENDS, DURATION_ROUNDS, DURATION_ENCOUNTER, DURATION_TARGET_TURN_START, DURATION_SAVE_TRACK]


static func is_condition(condition: String) -> bool:
	return ALL.has(condition) or TRACKED.has(condition)


## A normalised, JSON-safe duration object, or {} when `d` is invalid.
## Accepts a Dictionary {"type", ...} or a bare type string.
static func normalize_duration(d: Variant) -> Dictionary:
	var src: Dictionary = {}
	if typeof(d) == TYPE_STRING:
		src = {"type": str(d)}
	elif typeof(d) == TYPE_DICTIONARY:
		src = d
	else:
		return {}
	var t := str(src.get("type", ""))
	match t:
		DURATION_SOURCE_NEXT_TURN, DURATION_TARGET_TURN_END, DURATION_ENCOUNTER, DURATION_TARGET_TURN_START:
			return {"type": t}
		DURATION_SAVE_ENDS:
			var ability := Ability.from_string(str(src.get("ability", "")))
			if ability < 0:
				return {}
			return {"type": t, "ability": Ability.abbreviation(ability), "dc": DictUtil.to_int(src.get("dc", 10), 10)}
		DURATION_ROUNDS:
			return {"type": t, "rounds": maxi(1, DictUtil.to_int(src.get("rounds", 1), 1))}
		DURATION_SAVE_TRACK:
			var ability := Ability.from_string(str(src.get("ability", "CON")))
			if ability < 0:
				return {}
			var out := {"type": t, "ability": Ability.abbreviation(ability), "successes": DictUtil.to_int(src.get("successes", 0), 0), "failures": DictUtil.to_int(src.get("failures", 0), 0)}
			if src.has("dc"):
				out["dc"] = DictUtil.to_int(src["dc"], 10)
			return out
	return {}


static func duration(type_name: String, fields: Dictionary = {}) -> Dictionary:
	var d := {"type": type_name}
	d.merge(fields)
	return Conditions.normalize_duration(d)

class_name AttackResult
extends RefCounted
## Everything that happened during one attack roll.

var attacker_name: String = ""
var target_name: String = ""
var attack_name: String = ""
var damage_type: String = ""
var hit: bool = false
var critical: bool = false  # natural 20
var fumble: bool = false  # natural 1
var d20: D20Result = null
var attack_total: int = 0  # natural + to_hit
var target_ac: int = 0
var damage: DiceRoll = null  # null on a miss
var damage_rolls: Array[int] = []  # base damage dice rolled (after rerolls)
var damage_total: int = 0  # after resistances / immunities / vulnerabilities, extras included
var extras: Array[Dictionary] = []  # [{"source", "amount", "type"}] extra damage on a hit
var target_hp_after: int = 0
var target_dropped: bool = false  # target's hp reached 0 during this attack
var target_died: bool = false


func summary() -> String:
	var text := "%s attacks %s with %s: %s +%d = %d vs AC %d" % [
		attacker_name, target_name, attack_name, str(d20), attack_total - (d20.natural if d20 != null else 0),
		attack_total, target_ac,
	]
	if not hit:
		return text + (" - natural 1, MISS." if fumble else " - MISS.")
	text += " - %sHIT for %d %s" % ["CRITICAL " if critical else "", damage_total, damage_type]
	if damage != null:
		text += " (%s)" % damage.to_string_breakdown()
	text += ". %s has %d HP" % [target_name, target_hp_after]
	if target_died:
		text += " and dies"
	elif target_dropped:
		text += " and falls unconscious"
	return text + "."

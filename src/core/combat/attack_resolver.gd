class_name AttackResolver
extends RefCounted
## Resolves a single attack roll and its damage (SRD rules).


## attack: {"name", "to_hit": int, "damage": dice formula, "damage_type",
## "reroll_max"?: int (Great Weapon Fighting: damage dice showing <= it are
## rolled again once)}.
## Natural 1 always misses. A natural roll >= crit_min (20; 19 with Improved
## Critical) always hits and is a critical hit (damage dice are rolled twice,
## flat modifiers added once). Otherwise the attack hits when d20 + to_hit +
## extra_to_hit >= target AC. Damage is applied to target.sheet (through
## Combatant.adjust_damage, so Rage resistance counts).
## auto_crit: any hit is a critical hit (SRD: melee hit within 5 ft of an
## unconscious or paralyzed creature).
## extra_damage: [{"source", "dice", "type"}] rolled on a hit (doubled on a
## critical), each adjusted for its own damage type, and reported in
## result.extras as [{"source", "amount", "type"}].
## half_on_miss: a miss still deals half the base damage (no extras).
static func resolve_attack(attacker: Combatant, target: Combatant, attack: Dictionary, rng: Rng, mode: D20.RollMode = D20.RollMode.NORMAL, auto_crit: bool = false, extra_to_hit: int = 0, extra_damage: Array[Dictionary] = [], half_on_miss: bool = false) -> AttackResult:
	var result := AttackResolver.roll(attacker, target, attack, rng, mode, auto_crit, extra_to_hit, extra_damage, half_on_miss)
	if result.hit or half_on_miss:
		AttackResolver.apply_damage(result, target, result.damage_total)
	return result


## As resolve_attack, but the damage is only computed (damage_total), not
## applied: call apply_damage() (after any reduction such as Uncanny Dodge).
static func roll(attacker: Combatant, target: Combatant, attack: Dictionary, rng: Rng, mode: D20.RollMode = D20.RollMode.NORMAL, auto_crit: bool = false, extra_to_hit: int = 0, extra_damage: Array[Dictionary] = [], half_on_miss: bool = false, crit_min: int = 20) -> AttackResult:
	var result := AttackResult.new()
	result.attacker_name = attacker.display_name
	result.target_name = target.display_name
	result.attack_name = str(attack.get("name", "Attack"))
	result.damage_type = str(attack.get("damage_type", "")).to_lower()
	var to_hit := DictUtil.to_int(attack.get("to_hit", 0), 0) + extra_to_hit
	result.d20 = D20.roll(rng, mode)
	result.attack_total = result.d20.natural + to_hit
	result.target_ac = target.sheet.armor_class()
	if result.d20.is_nat1():
		result.fumble = true
		result.hit = false
	elif result.d20.natural >= clampi(crit_min, 2, 20):
		result.hit = true
		result.critical = true
	else:
		result.hit = result.attack_total >= result.target_ac
		result.critical = result.hit and auto_crit
	result.target_hp_after = target.sheet.current_hp
	if not result.hit and not half_on_miss:
		return result
	var formula := DiceFormula.parse(str(attack.get("damage", "0")))
	if not formula.valid:
		push_error("AttackResolver: invalid damage expression: %s" % formula.error)
		formula = DiceFormula.parse("0")
	var rolled := formula.roll(rng, 0, result.critical, DictUtil.to_int(attack.get("reroll_max", 0), 0))
	var amount := maxi(0, DictUtil.to_int(rolled["total"]))
	result.damage_rolls = rolled["rolls"]
	result.damage = DiceRoll.new()
	result.damage.expression = formula.source
	result.damage.rolls = result.damage_rolls.duplicate()
	result.damage.kept = result.damage_rolls.duplicate()
	result.damage.modifier = formula.constant
	result.damage.total = DictUtil.to_int(rolled["total"])
	result.damage.critical = result.critical
	if not result.hit:
		amount = floori(amount / 2.0)
	var total := target.adjust_damage(amount, result.damage_type)
	if result.hit:
		for extra in extra_damage:
			var extra_formula := DiceFormula.parse(str(extra.get("dice", "0")))
			if not extra_formula.valid:
				continue
			var extra_type := str(extra.get("type", result.damage_type)).to_lower()
			var extra_roll := maxi(0, DictUtil.to_int(extra_formula.roll(rng, 0, result.critical)["total"]))
			var adjusted := target.adjust_damage(extra_roll, extra_type)
			result.extras.append({"source": str(extra.get("source", "")), "amount": adjusted, "type": extra_type})
			total += adjusted
	result.damage_total = total
	return result


## Applies `amount` to the target and records the outcome on the result.
static func apply_damage(result: AttackResult, target: Combatant, amount: int) -> void:
	result.damage_total = maxi(0, amount)
	var outcome := target.sheet.take_damage(result.damage_total, result.critical)
	result.target_hp_after = target.sheet.current_hp
	result.target_dropped = outcome.dropped_to_zero
	result.target_died = outcome.died

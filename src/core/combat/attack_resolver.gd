class_name AttackResolver
extends RefCounted
## Resolves a single attack roll and its damage (SRD rules).


## attack: {"name", "to_hit": int, "damage": dice expr, "damage_type"}.
## Natural 1 always misses. Natural 20 always hits and is a critical hit (damage
## dice are rolled twice, the flat modifier is added once). Otherwise the attack
## hits when d20 + to_hit + extra_to_hit >= target AC. Damage is applied to
## target.sheet (through Combatant.adjust_damage, so Rage resistance counts).
## auto_crit: any hit is a critical hit (SRD: melee hit within 5 ft of an
## unconscious creature).
## extra_damage: [{"source", "dice", "type"}] rolled on a hit (doubled on a
## critical), each adjusted for its own damage type, and reported in
## result.extras as [{"source", "amount", "type"}].
## half_on_miss: a miss still deals half the base damage (no extras).
static func resolve_attack(attacker: Combatant, target: Combatant, attack: Dictionary, rng: Rng, mode: D20.RollMode = D20.RollMode.NORMAL, auto_crit: bool = false, extra_to_hit: int = 0, extra_damage: Array[Dictionary] = [], half_on_miss: bool = false) -> AttackResult:
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
	elif result.d20.is_nat20():
		result.hit = true
		result.critical = true
	else:
		result.hit = result.attack_total >= result.target_ac
		result.critical = result.hit and auto_crit
	if not result.hit and not half_on_miss:
		result.target_hp_after = target.sheet.current_hp
		return result
	var expr := DiceExpr.parse(str(attack.get("damage", "0")))
	if not expr.valid:
		push_error("AttackResolver: invalid damage expression: %s" % expr.error)
		expr = DiceExpr.parse("0")
	result.damage = expr.roll(rng, result.critical)
	var amount := maxi(0, result.damage.total)
	if not result.hit:
		amount = floori(amount / 2.0)
	var total := target.adjust_damage(amount, result.damage_type)
	if result.hit:
		for extra in extra_damage:
			var extra_expr := DiceExpr.parse(str(extra.get("dice", "0")))
			if not extra_expr.valid:
				continue
			var extra_type := str(extra.get("type", result.damage_type)).to_lower()
			var rolled := maxi(0, extra_expr.roll(rng, result.critical).total)
			var adjusted := target.adjust_damage(rolled, extra_type)
			result.extras.append({"source": str(extra.get("source", "")), "amount": adjusted, "type": extra_type})
			total += adjusted
	result.damage_total = total
	var outcome := target.sheet.take_damage(result.damage_total, result.critical)
	result.target_hp_after = target.sheet.current_hp
	result.target_dropped = outcome.dropped_to_zero
	result.target_died = outcome.died
	return result

class_name AttackResolver
extends RefCounted
## Resolves a single attack roll and its damage (SRD rules).


## attack: {"name", "to_hit": int, "damage": dice expr, "damage_type"}.
## Natural 1 always misses. Natural 20 always hits and is a critical hit (damage
## dice are rolled twice, the flat modifier is added once). Otherwise the attack
## hits when d20 + to_hit >= target AC. Damage is applied to target.sheet.
## auto_crit: any hit is a critical hit (SRD: melee hit within 5 ft of an
## unconscious creature).
static func resolve_attack(attacker: Combatant, target: Combatant, attack: Dictionary, rng: Rng, mode: D20.RollMode = D20.RollMode.NORMAL, auto_crit: bool = false) -> AttackResult:
	var result := AttackResult.new()
	result.attacker_name = attacker.display_name
	result.target_name = target.display_name
	result.attack_name = str(attack.get("name", "Attack"))
	result.damage_type = str(attack.get("damage_type", "")).to_lower()
	var to_hit := DictUtil.to_int(attack.get("to_hit", 0), 0)
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
	if not result.hit:
		result.target_hp_after = target.sheet.current_hp
		return result
	var expr := DiceExpr.parse(str(attack.get("damage", "0")))
	if not expr.valid:
		push_error("AttackResolver: invalid damage expression: %s" % expr.error)
		expr = DiceExpr.parse("0")
	result.damage = expr.roll(rng, result.critical)
	var amount := maxi(0, result.damage.total)
	result.damage_total = target.sheet.adjust_damage_for_type(amount, result.damage_type)
	var outcome := target.sheet.take_damage(result.damage_total, result.critical)
	result.target_hp_after = target.sheet.current_hp
	result.target_dropped = outcome.dropped_to_zero
	result.target_died = outcome.died
	return result

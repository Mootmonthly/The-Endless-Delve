class_name Rest
extends RefCounted
## Short and long rests (SRD). In the game, each floor descent is a short rest
## and entering a safe zone is a long rest.


## Spends up to `hit_dice_to_spend` hit dice. Each die heals hit_die roll + CON
## modifier (min 0), capped at max hp. Stops early once at full hp so dice are
## not wasted. Returns hit points healed.
static func short_rest(sheet: CharacterSheet, hit_dice_to_spend: int, rng: Rng) -> int:
	if sheet == null or sheet.is_dead():
		return 0
	var con_mod := sheet.abilities.get_modifier(Ability.Type.CON)
	var healed := 0
	var to_spend := mini(hit_dice_to_spend, sheet.hit_dice_remaining)
	for _i in range(to_spend):
		if sheet.current_hp >= sheet.max_hp:
			break
		sheet.hit_dice_remaining -= 1
		var amount := maxi(0, rng.next_int(1, sheet.hit_die) + con_mod)
		healed += sheet.heal(amount)
	return healed


## Full hp, temp hp cleared, regain half of total hit dice (round down, min 1),
## death saves and stability reset, all conditions cleared.
## TODO: exhaustion should only drop by one level once it is implemented.
static func long_rest(sheet: CharacterSheet) -> void:
	if sheet == null or sheet.is_dead():
		return
	sheet.current_hp = sheet.max_hp
	sheet.temp_hp = 0
	var regain := maxi(1, floori(sheet.hit_dice_total / 2.0))
	sheet.hit_dice_remaining = mini(sheet.hit_dice_total, sheet.hit_dice_remaining + regain)
	sheet.reset_death_saves()
	sheet.conditions.clear()

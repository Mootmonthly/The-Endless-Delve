class_name Rest
extends RefCounted
## Short and long rests (SRD). In the game, each floor descent is a short rest
## and entering a safe zone is a long rest.


## Spends up to `hit_dice_to_spend` hit dice. Each die heals hit_die roll + CON
## modifier (min 0), capped at max hp. Stops early once at full hp so dice are
## not wasted. Returns hit points healed. Also refills short-rest class
## resources (Second Wind, Action Surge, ki, Channel Divinity, Bardic
## Inspiration with Font of Inspiration) and, for pact magic (slot_recovery
## "short_rest"), every spell slot. Song of Rest: with song_die > 0 (see
## song_of_rest_die) a creature that spent at least one hit die regains an
## extra 1d<song_die> (SRD: once per rest, not per die).
static func short_rest(sheet: CharacterSheet, hit_dice_to_spend: int, rng: Rng, song_die: int = 0) -> int:
	if sheet == null or sheet.is_dead():
		return 0
	sheet.restore_class_resources(true)
	sheet.relentless_rage_uses = 0
	if sheet.has_feature("sorcerous_restoration"):
		sheet.class_resources["sorcery_points"] = mini(sheet.resource_max("sorcery_points"), sheet.class_resource("sorcery_points") + 4)
	if sheet.slot_recovery == ClassDefinition.SLOT_RECOVERY_SHORT:
		sheet.restore_spell_slots()
	var con_mod := sheet.abilities.get_modifier(Ability.Type.CON)
	var healed := 0
	var spent := 0
	var to_spend := mini(hit_dice_to_spend, sheet.hit_dice_remaining)
	for _i in range(to_spend):
		if sheet.current_hp >= sheet.max_hp:
			break
		sheet.hit_dice_remaining -= 1
		spent += 1
		var amount := maxi(0, rng.next_int(1, sheet.hit_die) + con_mod)
		healed += sheet.heal(amount)
	if spent > 0 and song_die > 0:
		healed += sheet.heal(rng.next_int(1, song_die))
	return healed


## The Song of Rest die a resting party gets: the largest among its living,
## conscious bards with the feature (class table "song_of_rest_die", else d6 /
## d8 at 9 / d10 at 13 / d12 at 17); 0 = none.
static func song_of_rest_die(party: Array[CharacterSheet]) -> int:
	var best := 0
	for s in party:
		if s != null and s.is_conscious() and s.has_feature("song_of_rest"):
			best = maxi(best, s.table_die("song_of_rest_die", Progression.song_of_rest_die(s.level)))
	return best


## Arcane Recovery (wizard) / Natural Recovery (land druid), usable once per
## long rest when finishing a short rest: {"feature", "budget" (combined slot
## levels: half the level, rounded up), "max_slot_level" (5)}; {} when the
## sheet has neither or it is used up.
static func slot_recovery_options(sheet: CharacterSheet) -> Dictionary:
	if sheet == null:
		return {}
	for feature: String in ["arcane_recovery", "natural_recovery"]:
		if sheet.has_feature(feature) and sheet.class_resource(feature) > 0:
			return {"feature": feature, "budget": Progression.recovery_budget(sheet.level), "max_slot_level": Progression.MAX_RECOVERED_SLOT}
	return {}


## The default Arcane / Natural Recovery picks: expended slots, highest level
## first, while the budget allows ([] when nothing applies). Server and client
## share this choice.
static func default_slot_recovery(sheet: CharacterSheet) -> Array[int]:
	var out: Array[int] = []
	var opts := Rest.slot_recovery_options(sheet)
	if opts.is_empty():
		return out
	var budget := DictUtil.to_int(opts.get("budget", 0), 0)
	var top := mini(DictUtil.to_int(opts.get("max_slot_level", 5), 5), sheet.spell_slots_max.size())
	for lvl in range(top, 0, -1):
		var missing := sheet.spell_slots_max[lvl - 1] - sheet.slots_left(lvl)
		while missing > 0 and budget >= lvl:
			out.append(lvl)
			budget -= lvl
			missing -= 1
	return out


## Regains one expended slot per entry of slot_levels (the server calls this as
## a short rest finishes). The levels must total <= the budget, none above 5th,
## each an expended slot. Spends the feature's use. "" or an error (no change).
static func recover_slots(sheet: CharacterSheet, slot_levels: Array[int]) -> String:
	var opts := Rest.slot_recovery_options(sheet)
	if opts.is_empty():
		return "no slot recovery available"
	if slot_levels.is_empty():
		return "choose at least one slot"
	var total := 0
	var missing: Dictionary[int, int] = {}
	for lvl in slot_levels:
		if lvl < 1 or lvl > DictUtil.to_int(opts["max_slot_level"]):
			return "slots above level %d cannot be recovered" % DictUtil.to_int(opts["max_slot_level"])
		total += lvl
		missing[lvl] = missing.get(lvl, 0) + 1
	if total > DictUtil.to_int(opts["budget"]):
		return "slot levels total %d, the limit is %d" % [total, DictUtil.to_int(opts["budget"])]
	for lvl: int in missing.keys():
		var max_n := sheet.spell_slots_max[lvl - 1] if lvl <= sheet.spell_slots_max.size() else 0
		if max_n - sheet.slots_left(lvl) < missing[lvl]:
			return "not enough expended level %d slots" % lvl
	for lvl in slot_levels:
		sheet.spell_slots[lvl - 1] += 1
	sheet.spend_class_resource(str(opts["feature"]), 1)
	return ""


## Full hp, temp hp cleared, regain half of total hit dice (round down, min 1),
## death saves and stability reset, all conditions cleared, every spell slot
## and class resource restored (Mystic Arcanum, invocation spells too),
## lasting buffs (Mage Armor) end. Exhaustion and the Raise Dead penalty drop
## by one; Relentless Rage resets; Animate Dead / Create Undead companions
## (until_long_rest) leave; Tranquility (monk 11) starts its sanctuary.
static func long_rest(sheet: CharacterSheet) -> void:
	if sheet == null or sheet.is_dead():
		return
	sheet.exhaustion = maxi(0, sheet.exhaustion - 1)
	sheet.resurrection_penalty = maxi(0, sheet.resurrection_penalty - 1)
	sheet.relentless_rage_uses = 0
	sheet.overchannel_uses = 0
	var kept: Array[Dictionary] = []
	for entry in sheet.companions:
		if entry.get("until_long_rest", false) != true and entry.get("dead", false) != true:
			kept.append(entry)
	sheet.companions = kept
	sheet.current_hp = sheet.hit_point_maximum()
	sheet.temp_hp = 0
	var regain := maxi(1, floori(sheet.hit_dice_total / 2.0))
	sheet.hit_dice_remaining = mini(sheet.hit_dice_total, sheet.hit_dice_remaining + regain)
	sheet.reset_death_saves()
	sheet.conditions.clear()
	sheet.restore_spell_slots()
	sheet.restore_class_resources()
	sheet.active_buffs.clear()
	sheet.lingering.clear()
	if sheet.has_feature("tranquility"):
		sheet.active_buffs.append("tranquility")


## Eldritch Master (warlock 20): after a minute entreating the patron, every
## expended Pact Magic slot comes back, once per long rest. "" or an error
## (nothing changes).
static func eldritch_master(sheet: CharacterSheet) -> String:
	if sheet == null or not sheet.has_feature("eldritch_master"):
		return "no Eldritch Master"
	if sheet.class_resource("eldritch_master") <= 0:
		return "Eldritch Master needs a long rest first"
	sheet.restore_spell_slots()
	sheet.spend_class_resource("eldritch_master", 1)
	return ""

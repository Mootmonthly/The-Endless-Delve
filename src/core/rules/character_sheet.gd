class_name CharacterSheet
extends RefCounted
## A creature's rules state: abilities, hit points, proficiencies, death saves,
## inventory and equipment, spellcasting and class resources.
## Player characters and (for simplicity) monsters both use this class.
##
## Inventory: `inventory` holds every carried item, equipped ones included,
## as [{"item": id, "qty": int}] (one entry per id). `equipped` maps
## "main_hand" / "off_hand" / "armor" to an item id ("" = empty); an equipped
## id must be carried. Methods that need item / weapon definitions take a
## content dictionary (ContentLoader.cache() shape); {} means the cache.

const SCHEMA_VERSION := 1
const MAX_LEVEL := 20
const DEATH_SAVES_NEEDED := 3
const SLOT_MAIN_HAND := "main_hand"
const SLOT_OFF_HAND := "off_hand"
const SLOT_ARMOR := "armor"
const SLOTS: Array[String] = [SLOT_MAIN_HAND, SLOT_OFF_HAND, SLOT_ARMOR]
const GOLD_ITEM := "gold"
const BUFF_MAGE_ARMOR := "mage_armor"
const MAGE_ARMOR_BASE := 13
## Class features with a per-rest resource counter in class_resources.
const RESOURCE_FEATURES: Array[String] = ["second_wind", "rage", "lay_on_hands", "bardic_inspiration"]
## Resources that also come back on a short rest (the rest need a long rest).
const SHORT_REST_RESOURCES: Array[String] = ["second_wind"]
## SRD rage uses by barbarian level (index = level); 20th level is unlimited (99).
const RAGE_USES: Array[int] = [0, 2, 2, 3, 3, 3, 4, 4, 4, 4, 4, 4, 5, 5, 5, 5, 5, 6, 6, 6, 99]

var name: String = ""
var class_id: String = ""
var ancestry_id: String = ""  # empty for monsters / legacy sheets
var level: int = 1
var xp: int = 0
var abilities: AbilityScores = AbilityScores.new()
var max_hp: int = 1
var current_hp: int = 1
var temp_hp: int = 0
var armor_base: int = 0  # worn armor's base AC; 0 = unarmored (10)
var armor_max_dex: int = -1  # cap on the DEX bonus from armor; -1 = no cap, 0 = heavy (DEX ignored)
var shield_bonus: int = 0  # shield (+2) or any other flat AC bonus
var speed: int = 30
var hit_die: int = 8
var hit_dice_total: int = 1  # equals level for characters
var hit_dice_remaining: int = 1
var proficient_saves: Array[int] = []  # Ability.Type values
var proficient_skills: Array[int] = []  # Skill.Type values
var death_save_successes: int = 0
var death_save_failures: int = 0
var stable: bool = false
var dead: bool = false
var uses_death_saves: bool = true  # false for monsters: they die at 0 hp
var conditions: Array[String] = []
var damage_resistances: Array[String] = []
var damage_immunities: Array[String] = []
var damage_vulnerabilities: Array[String] = []
var deepest_floor: int = 0
## Weapon attacks, each {"name", "kind": "melee"|"ranged"|"thrown", "to_hit": int,
## "damage": dice expr, "damage_type", "weapon_id", "item": weapon item id,
## "consumes": item id used up per attack ("" = none), "range_tiles": [normal,
## long], "ability": "STR"|"DEX", "properties": [...], "proficient": bool}.
## Built by rebuild_attacks(); empty = unarmed only.
var attacks: Array[Dictionary] = []
## Class feature ids (ClassDefinition.FEATURE_*; others are flavour).
var features: Array[String] = []
var weapon_proficiencies: Array[String] = []  # copied from the class ("simple", "dagger", ...)
var inventory: Array[Dictionary] = []  # [{"item": id, "qty": int}]
var equipped: Dictionary[String, String] = {SLOT_MAIN_HAND: "", SLOT_OFF_HAND: "", SLOT_ARMOR: ""}
## Spellcasting: casting_ability is an Ability.Type or -1. spells_known holds
## cantrips and spells the character knows (spellbook for a wizard);
## spells_prepared are castable (cantrips included). spell_slots[i] is the
## number of remaining slots of level i + 1; spell_slots_max the maximum.
var casting_ability: int = -1
var spells_known: Array[String] = []
var spells_prepared: Array[String] = []
var spell_slots: Array[int] = []
var spell_slots_max: Array[int] = []
var slot_recovery: String = "long_rest"  # "short_rest" for pact magic
## Remaining uses of per-rest class features (see RESOURCE_FEATURES).
var class_resources: Dictionary[String, int] = {}
## Lasting spell effects on this character ("mage_armor"); cleared by a long rest.
var active_buffs: Array[String] = []


func proficiency_bonus() -> int:
	return Proficiency.bonus_for_level(level)


## (armor_base, or 10 unarmored) + DEX modifier (capped by armor_max_dex) + shield_bonus.
## SRD heavy armor (armor_max_dex 0) ignores DEX entirely, even a penalty.
## Unarmored (armor_base 0) the best of: 10 + DEX, Mage Armor 13 + DEX,
## Unarmored Defense 10 + DEX + CON (shield allowed) or 10 + DEX + WIS (no shield).
func armor_class() -> int:
	var base := armor_base if armor_base > 0 else 10
	var raw_dex := abilities.get_modifier(Ability.Type.DEX)
	var dex := raw_dex
	if armor_max_dex == 0:
		dex = 0
	elif armor_max_dex > 0:
		dex = mini(dex, armor_max_dex)
	var ac := base + dex
	if armor_base <= 0:
		if active_buffs.has(BUFF_MAGE_ARMOR):
			ac = maxi(ac, MAGE_ARMOR_BASE + raw_dex)
		if features.has("unarmored_defense_con"):
			ac = maxi(ac, 10 + raw_dex + abilities.get_modifier(Ability.Type.CON))
		if features.has("unarmored_defense_wis") and shield_bonus == 0:
			ac = maxi(ac, 10 + raw_dex + abilities.get_modifier(Ability.Type.WIS))
	return ac + shield_bonus


func has_feature(feature: String) -> bool:
	return features.has(feature)


func ability_modifier(ability: int) -> int:
	return abilities.get_modifier(ability)


func save_modifier(ability: int) -> int:
	var mod := abilities.get_modifier(ability)
	if proficient_saves.has(ability):
		mod += proficiency_bonus()
	return mod


func skill_modifier(skill: int) -> int:
	var mod := abilities.get_modifier(Skill.ability_for(skill))
	if proficient_skills.has(skill):
		mod += proficiency_bonus()
	return mod


func initiative_modifier() -> int:
	return abilities.get_modifier(Ability.Type.DEX)


func is_alive() -> bool:
	return not dead


func is_dead() -> bool:
	return dead


func is_unconscious() -> bool:
	return not dead and current_hp == 0


func is_conscious() -> bool:
	return not dead and current_hp > 0


## Applies immunity (0), resistance (half, rounded down) and vulnerability
## (double). extra_resistances (e.g. Rage) do not stack with the sheet's own.
func adjust_damage_for_type(amount: int, damage_type: String, extra_resistances: Array[String] = []) -> int:
	var t := damage_type.to_lower()
	if t.is_empty():
		return amount
	if damage_immunities.has(t):
		return 0
	var result := amount
	if damage_resistances.has(t) or extra_resistances.has(t):
		result = floori(result / 2.0)
	if damage_vulnerabilities.has(t):
		result *= 2
	return result


## Temporary hit points don't stack: keep the larger value.
func grant_temp_hp(amount: int) -> void:
	temp_hp = maxi(temp_hp, amount)


## SRD damage rules: temp hp absorbs first; dropping to 0 knocks a character
## unconscious (monsters die); leftover damage >= max hp is instant death;
## damage while at 0 hp is one death-save failure (two on a critical hit).
func take_damage(amount: int, critical: bool = false) -> DamageOutcome:
	var out := DamageOutcome.new()
	out.amount = maxi(amount, 0)
	out.critical = critical
	if dead:
		out.hp_after = current_hp
		return out
	var remaining := out.amount
	var absorbed := mini(temp_hp, remaining)
	temp_hp -= absorbed
	remaining -= absorbed
	out.absorbed_by_temp = absorbed
	if remaining > 0:
		if current_hp > 0:
			if remaining < current_hp:
				current_hp -= remaining
				out.hp_lost = remaining
			else:
				var leftover := remaining - current_hp
				out.hp_lost = current_hp
				current_hp = 0
				out.dropped_to_zero = true
				if leftover >= max_hp:
					out.instant_death = true
					out.died = true
					_die()
				elif not uses_death_saves:
					out.died = true
					_die()
				else:
					reset_death_saves()
		else:
			if remaining >= max_hp:
				out.instant_death = true
				out.died = true
				_die()
			else:
				var added := 2 if critical else 1
				out.death_save_failures_added = added
				stable = false
				death_save_failures = mini(DEATH_SAVES_NEEDED, death_save_failures + added)
				if death_save_failures >= DEATH_SAVES_NEEDED:
					out.died = true
					_die()
	out.hp_after = current_hp
	return out


## Returns hit points actually restored. Healing from 0 hp resets death saves.
func heal(amount: int) -> int:
	if dead or amount <= 0:
		return 0
	var before := current_hp
	current_hp = mini(max_hp, current_hp + amount)
	if before == 0 and current_hp > 0:
		reset_death_saves()
	return current_hp - before


func reset_death_saves() -> void:
	death_save_successes = 0
	death_save_failures = 0
	stable = false


## Natural 20: regain 1 hp. Natural 1: two failures. 10+: success, else failure.
## Three successes: stable. Three failures: dead.
func roll_death_save(rng: Rng) -> DeathSaveOutcome:
	var out := DeathSaveOutcome.new()
	if dead or current_hp > 0 or stable or not uses_death_saves:
		out.successes = death_save_successes
		out.failures = death_save_failures
		return out
	out.rolled = true
	var d := D20.roll(rng)
	out.natural = d.natural
	if d.natural == 20:
		current_hp = 1
		reset_death_saves()
		out.success = true
		out.regained_consciousness = true
	elif d.natural == 1:
		death_save_failures += 2
	elif d.natural >= 10:
		death_save_successes += 1
		out.success = true
	else:
		death_save_failures += 1
	if death_save_failures >= DEATH_SAVES_NEEDED:
		death_save_failures = DEATH_SAVES_NEEDED
		out.died = true
		_die()
	elif death_save_successes >= DEATH_SAVES_NEEDED:
		death_save_successes = 0
		death_save_failures = 0
		stable = true
		out.became_stable = true
	out.successes = death_save_successes
	out.failures = death_save_failures
	return out


## Adds XP. Levels are NOT applied here: the player chooses them through
## LevelUp.choices() / LevelUp.apply(). Returns pending_levels().
func gain_xp(amount: int) -> int:
	if amount > 0:
		xp += amount
	return pending_levels()


## Levels the current XP allows beyond the current level (0 if none).
func pending_levels() -> int:
	return maxi(0, mini(MAX_LEVEL, Experience.level_for_xp(xp)) - level)


## Raises level by one without choices (tests, monsters; players use LevelUp).
## HP gain is the hit die average (hit_die / 2 + 1), or a roll when `average`
## is false and an rng is given, plus CON modifier, min 1. Also updates spell
## slots and class resources from the class (cls, or the cached class of
## class_id when null) and the to_hit of proficient attacks. Returns the hit
## points gained.
func level_up(rng: Rng = null, average: bool = true, cls: ClassDefinition = null) -> int:
	if level >= MAX_LEVEL:
		return 0
	var base := floori(hit_die / 2.0) + 1
	if not average and rng != null:
		base = rng.next_int(1, hit_die)
	var gain := maxi(1, base + abilities.get_modifier(Ability.Type.CON))
	advance_level(gain, cls)
	return gain


## The bookkeeping of one level: level + 1, hp + gain, one more hit die,
## proficient attacks' to_hit follow the proficiency bonus, then spell slots
## and class resources follow the class table (see apply_class_level).
func advance_level(hp_gain: int, cls: ClassDefinition = null) -> void:
	var old_prof := proficiency_bonus()
	var resource_before := _resource_maxima()
	level += 1
	max_hp += hp_gain
	if is_conscious():
		current_hp += hp_gain
	hit_dice_total = level
	hit_dice_remaining = mini(hit_dice_total, hit_dice_remaining + 1)
	var delta := proficiency_bonus() - old_prof
	if delta != 0:
		for attack in attacks:
			if attack.get("proficient", false) == true:
				attack["to_hit"] = DictUtil.to_int(attack["to_hit"]) + delta
	apply_class_level(cls)
	for feature: String in resource_before.keys():
		var gained := resource_max(feature) - DictUtil.to_int(resource_before[feature])
		if gained > 0:
			class_resources[feature] = class_resource(feature) + gained


## Sets spell_slots_max from the class slot table for the current level; new
## slots are available at once (remaining slots grow by the increase). cls null
## = the class of class_id in ContentLoader.cache() (monster sheets: nothing).
func apply_class_level(cls: ClassDefinition = null) -> void:
	var def := cls
	if def == null:
		def = class_definition()
	if def == null or def.spell_slot_table.is_empty():
		return
	var new_max := def.slots_for_level(level)
	var new_slots: Array[int] = []
	for i in range(new_max.size()):
		var old_max := spell_slots_max[i] if i < spell_slots_max.size() else 0
		var old_left := spell_slots[i] if i < spell_slots.size() else 0
		new_slots.append(clampi(old_left + maxi(0, new_max[i] - old_max), 0, new_max[i]))
	spell_slots_max = new_max
	spell_slots = new_slots


## This character's ClassDefinition from ContentLoader.cache() (null for
## monsters and unknown classes).
func class_definition(content: Dictionary = {}) -> ClassDefinition:
	if class_id.is_empty() or class_id.begins_with("monster:"):
		return null
	var classes: Dictionary = ContentLoader.resolve(content)["classes"]
	if not classes.has(class_id):
		return null
	var def: ClassDefinition = classes[class_id]
	return def


# --- class resources ---------------------------------------------------------

## Maximum uses of a resource feature at the current level, or 0 when the
## character lacks the feature.
func resource_max(feature: String) -> int:
	if not features.has(feature):
		return 0
	match feature:
		"second_wind":
			return 1
		"rage":
			return RAGE_USES[clampi(level, 1, MAX_LEVEL)]
		"lay_on_hands":
			return 5 * level
		"bardic_inspiration":
			return maxi(1, abilities.get_modifier(Ability.Type.CHA))
	return 0


func class_resource(feature: String) -> int:
	return DictUtil.to_int(class_resources.get(feature, 0))


## Refills every resource feature (long rest), or only the short-rest ones.
func restore_class_resources(short_rest_only: bool = false) -> void:
	for feature in RESOURCE_FEATURES:
		if not features.has(feature):
			continue
		if short_rest_only and not SHORT_REST_RESOURCES.has(feature):
			continue
		class_resources[feature] = resource_max(feature)


## Spends n uses; false (nothing spent) when fewer remain.
func spend_class_resource(feature: String, n: int = 1) -> bool:
	if n <= 0 or class_resource(feature) < n:
		return false
	class_resources[feature] = class_resource(feature) - n
	return true


func _resource_maxima() -> Dictionary:
	var out := {}
	for feature in RESOURCE_FEATURES:
		if features.has(feature):
			out[feature] = resource_max(feature)
	return out


## Sneak Attack dice at this level: 1d6 per two rogue levels, rounded up.
func sneak_attack_dice() -> String:
	return "%dd6" % ceili(level / 2.0)


# --- spellcasting ------------------------------------------------------------

func is_spellcaster() -> bool:
	return casting_ability >= 0


func casting_modifier() -> int:
	return abilities.get_modifier(casting_ability) if casting_ability >= 0 else 0


## Proficiency bonus + spellcasting ability modifier.
func spell_attack_bonus() -> int:
	return proficiency_bonus() + casting_modifier()


## 8 + proficiency bonus + spellcasting ability modifier.
func spell_save_dc() -> int:
	return 8 + proficiency_bonus() + casting_modifier()


func is_spell_prepared(spell_id: String) -> bool:
	return spells_prepared.has(spell_id)


## Remaining slots of a spell level (1..9); 0 when none.
func slots_left(slot_level: int) -> int:
	if slot_level < 1 or slot_level > spell_slots.size():
		return 0
	return spell_slots[slot_level - 1]


## Highest spell level with a maximum slot count above 0 (0 = none).
func highest_slot_level() -> int:
	for i in range(spell_slots_max.size() - 1, -1, -1):
		if spell_slots_max[i] > 0:
			return i + 1
	return 0


## Lowest slot level >= min_level with a slot left, or 0.
func lowest_available_slot(min_level: int) -> int:
	for lvl in range(maxi(1, min_level), spell_slots.size() + 1):
		if spell_slots[lvl - 1] > 0:
			return lvl
	return 0


## Spends one slot of slot_level; false (nothing spent) when none is left.
func use_spell_slot(slot_level: int) -> bool:
	if slots_left(slot_level) <= 0:
		return false
	spell_slots[slot_level - 1] -= 1
	return true


func restore_spell_slots() -> void:
	spell_slots = spell_slots_max.duplicate()


# --- inventory and equipment -------------------------------------------------

func count_item(item_id: String) -> int:
	for entry in inventory:
		if str(entry["item"]) == item_id:
			return DictUtil.to_int(entry["qty"])
	return 0


func has_item(item_id: String, qty: int = 1) -> bool:
	return count_item(item_id) >= qty


func gold() -> int:
	return count_item(GOLD_ITEM)


## Adds qty (>= 1) of an item, stacking onto its existing entry.
func add_item(item_id: String, qty: int = 1) -> void:
	if item_id.is_empty() or qty <= 0:
		return
	for entry in inventory:
		if str(entry["item"]) == item_id:
			entry["qty"] = DictUtil.to_int(entry["qty"]) + qty
			return
	inventory.append({"item": item_id, "qty": qty})


## Removes qty of an item; false (and no change) when fewer are carried. If
## fewer copies remain than slots holding the item, those slots are emptied
## (off hand first) and armor / attacks are updated with `content`.
func remove_item(item_id: String, qty: int = 1, content: Dictionary = {}) -> bool:
	if qty <= 0 or count_item(item_id) < qty:
		return false
	for i in range(inventory.size()):
		if str(inventory[i]["item"]) == item_id:
			var left := DictUtil.to_int(inventory[i]["qty"]) - qty
			if left <= 0:
				inventory.remove_at(i)
			else:
				inventory[i]["qty"] = left
			break
	var changed := false
	for slot: String in [SLOT_OFF_HAND, SLOT_MAIN_HAND, SLOT_ARMOR]:
		if equipped_count(item_id) > count_item(item_id) and equipped_item(slot) == item_id:
			_clear_slot(slot)
			changed = true
	if changed or _has_attack_using(item_id):
		rebuild_attacks(content)
	return true


## Number of equipment slots holding item_id.
func equipped_count(item_id: String) -> int:
	var n := 0
	for slot in SLOTS:
		if equipped_item(slot) == item_id:
			n += 1
	return n


func equipped_item(slot: String) -> String:
	var held: String = equipped.get(slot, "")
	return held


## Equips a carried item. main_hand: a weapon; off_hand: a shield or a light
## weapon; armor: armor. An occupied slot is swapped (the old item stays in
## the inventory). A shield or off-hand weapon needs a free hand (no
## two-handed main-hand weapon) and vice versa. Updates armor_base /
## armor_max_dex / shield_bonus and rebuilds attacks. Returns "" or an error.
## Armor proficiency is not enforced (M2).
func equip(item_id: String, slot: String, content: Dictionary = {}) -> String:
	var c := ContentLoader.resolve(content)
	if not SLOTS.has(slot):
		return "unknown slot '%s'" % slot
	if not has_item(item_id):
		return "%s is not carried" % item_id
	if equipped_item(slot) == item_id:
		return ""
	var copies_needed := equipped_count(item_id) + 1
	if count_item(item_id) < copies_needed:
		return "only %d %s carried" % [count_item(item_id), item_id]
	var item := CharacterSheet.item_def(item_id, c)
	var weapon := CharacterSheet.weapon_for_item(item_id, c)
	var kind := item.kind if item != null else (ItemDefinition.KIND_WEAPON if weapon != null else "")
	match slot:
		SLOT_MAIN_HAND:
			if kind != ItemDefinition.KIND_WEAPON or weapon == null:
				return "%s is not a weapon" % item_id
			if weapon.is_two_handed() and not equipped_item(SLOT_OFF_HAND).is_empty():
				return "%s needs both hands: empty the off hand first" % item_id
		SLOT_OFF_HAND:
			if kind == ItemDefinition.KIND_SHIELD:
				pass
			elif kind == ItemDefinition.KIND_WEAPON and weapon != null and weapon.has_property("light"):
				pass
			else:
				return "%s cannot be held in the off hand" % item_id
			var main := CharacterSheet.weapon_for_item(equipped_item(SLOT_MAIN_HAND), c)
			if main != null and main.is_two_handed():
				return "the main-hand weapon needs both hands"
		SLOT_ARMOR:
			if kind != ItemDefinition.KIND_ARMOR or item == null:
				return "%s is not armor" % item_id
	_clear_slot(slot)
	equipped[slot] = item_id
	if slot == SLOT_ARMOR:
		armor_base = item.armor_base
		armor_max_dex = item.armor_max_dex
	elif slot == SLOT_OFF_HAND and kind == ItemDefinition.KIND_SHIELD:
		shield_bonus = item.shield_bonus
	rebuild_attacks(c)
	return ""


## Empties a slot (the item stays in the inventory). Returns "" or an error.
func unequip(slot: String, content: Dictionary = {}) -> String:
	if not SLOTS.has(slot):
		return "unknown slot '%s'" % slot
	if equipped_item(slot).is_empty():
		return ""
	_clear_slot(slot)
	rebuild_attacks(content)
	return ""


func _clear_slot(slot: String) -> void:
	var held := equipped_item(slot)
	equipped[slot] = ""
	if held.is_empty():
		return
	if slot == SLOT_ARMOR:
		armor_base = 0
		armor_max_dex = -1
	elif slot == SLOT_OFF_HAND:
		shield_bonus = 0


func _has_attack_using(item_id: String) -> bool:
	for attack in attacks:
		if attack.get("item", "") == item_id or attack.get("consumes", "") == item_id:
			return true
	return false


## Rebuilds `attacks` from the equipment and inventory, in this order:
## the main-hand weapon (melee, or ranged with its ammunition), its thrown
## attack if it has the thrown property, then each other carried weapon that
## can be thrown or shot (drawing a weapon is the free object interaction),
## in inventory order. Thrown attacks use up the weapon item; ranged attacks
## use up the ammunition item (item or weapon "ammo_id"). Items whose weapon
## is unknown are skipped.
func rebuild_attacks(content: Dictionary = {}) -> void:
	var c := ContentLoader.resolve(content)
	attacks.clear()
	var main := equipped_item(SLOT_MAIN_HAND)
	if not main.is_empty():
		var w := CharacterSheet.weapon_for_item(main, c)
		if w != null:
			if w.ranged and not w.is_thrown():
				attacks.append(CharacterBuilder.weapon_attack(self, w, _proficient(w, c), "ranged", main, CharacterSheet.ammo_for_item(main, c)))
			elif w.ranged:
				attacks.append(CharacterBuilder.weapon_attack(self, w, _proficient(w, c), "thrown", main, main))
			else:
				attacks.append(CharacterBuilder.weapon_attack(self, w, _proficient(w, c), "melee", main, ""))
				if w.is_thrown():
					attacks.append(CharacterBuilder.weapon_attack(self, w, _proficient(w, c), "thrown", main, main))
	for entry in inventory:
		var item_id := str(entry["item"])
		if item_id == main or DictUtil.to_int(entry["qty"]) <= 0:
			continue
		var w := CharacterSheet.weapon_for_item(item_id, c)
		if w == null:
			continue
		if w.is_thrown():
			attacks.append(CharacterBuilder.weapon_attack(self, w, _proficient(w, c), "thrown", item_id, item_id))
		elif w.ranged:
			attacks.append(CharacterBuilder.weapon_attack(self, w, _proficient(w, c), "ranged", item_id, CharacterSheet.ammo_for_item(item_id, c)))


func _proficient(weapon: WeaponDefinition, content: Dictionary) -> bool:
	var profs := weapon_proficiencies
	if profs.is_empty():
		var cls := class_definition(content)
		if cls != null:
			profs = cls.weapon_proficiencies
	return profs.has(weapon.category) or profs.has(weapon.id)


static func item_def(item_id: String, content: Dictionary) -> ItemDefinition:
	var items: Dictionary = content.get("items", {})
	if items.has(item_id):
		var it: ItemDefinition = items[item_id]
		return it
	return null


## The weapon an item wields: its weapon_id, or a weapon with the item's own id.
static func weapon_for_item(item_id: String, content: Dictionary) -> WeaponDefinition:
	if item_id.is_empty():
		return null
	var weapons: Dictionary = content.get("weapons", {})
	var item := CharacterSheet.item_def(item_id, content)
	var weapon_id := item_id
	if item != null:
		if item.kind != ItemDefinition.KIND_WEAPON:
			return null
		weapon_id = item.weapon_id
	if weapons.has(weapon_id):
		var w: WeaponDefinition = weapons[weapon_id]
		return w
	return null


## Ammunition item id for a weapon item: the item's ammo_id, else the weapon's ("" = none).
static func ammo_for_item(item_id: String, content: Dictionary) -> String:
	var item := CharacterSheet.item_def(item_id, content)
	if item != null and not item.ammo_id.is_empty():
		return item.ammo_id
	var w := CharacterSheet.weapon_for_item(item_id, content)
	return w.ammo_id if w != null else ""


## SRD unarmed strike: proficiency + STR to hit, 1 + STR bludgeoning damage.
## Martial Arts (monk): 1d4 + the better of STR and DEX.
func unarmed_strike() -> Dictionary:
	var str_mod := abilities.get_modifier(Ability.Type.STR)
	var attack := {
		"name": "Unarmed Strike",
		"kind": "melee",
		"to_hit": proficiency_bonus() + str_mod,
		"damage": str(maxi(0, 1 + str_mod)),
		"damage_type": "bludgeoning",
		"unarmed": true,
		"ability": "STR",
		"range_tiles": [1, 1],
		"proficient": true,
	}
	if features.has("martial_arts"):
		var dex_mod := abilities.get_modifier(Ability.Type.DEX)
		var mod := maxi(str_mod, dex_mod)
		attack["to_hit"] = proficiency_bonus() + mod
		attack["damage"] = "1d4" + CharacterBuilder.signed(mod)
		attack["ability"] = "DEX" if dex_mod > str_mod else "STR"
	return attack


## Kills the character outright (e.g. the server finishing off a downed
## player after a party wipe). Clears stability and sets hit points to 0.
func kill() -> void:
	_die()


func _die() -> void:
	dead = true
	current_hp = 0
	stable = false


func to_dict() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"name": name,
		"class_id": class_id,
		"ancestry_id": ancestry_id,
		"level": level,
		"xp": xp,
		"abilities": abilities.to_dict(),
		"max_hp": max_hp,
		"current_hp": current_hp,
		"temp_hp": temp_hp,
		"armor_base": armor_base,
		"armor_max_dex": armor_max_dex,
		"shield_bonus": shield_bonus,
		"speed": speed,
		"hit_die": hit_die,
		"hit_dice_total": hit_dice_total,
		"hit_dice_remaining": hit_dice_remaining,
		"proficient_saves": DictUtil.ability_keys(proficient_saves),
		"proficient_skills": DictUtil.skill_keys(proficient_skills),
		"death_save_successes": death_save_successes,
		"death_save_failures": death_save_failures,
		"stable": stable,
		"dead": dead,
		"uses_death_saves": uses_death_saves,
		"conditions": conditions.duplicate(),
		"damage_resistances": damage_resistances.duplicate(),
		"damage_immunities": damage_immunities.duplicate(),
		"damage_vulnerabilities": damage_vulnerabilities.duplicate(),
		"deepest_floor": deepest_floor,
		"attacks": attacks.duplicate(true),
		"features": features.duplicate(),
		"weapon_proficiencies": weapon_proficiencies.duplicate(),
		"inventory": inventory.duplicate(true),
		"equipped": {SLOT_MAIN_HAND: equipped_item(SLOT_MAIN_HAND), SLOT_OFF_HAND: equipped_item(SLOT_OFF_HAND), SLOT_ARMOR: equipped_item(SLOT_ARMOR)},
		"casting_ability": Ability.abbreviation(casting_ability) if casting_ability >= 0 else "",
		"spells_known": spells_known.duplicate(),
		"spells_prepared": spells_prepared.duplicate(),
		"spell_slots": spell_slots.duplicate(),
		"spell_slots_max": spell_slots_max.duplicate(),
		"slot_recovery": slot_recovery,
		"class_resources": _resources_dict(),
		"active_buffs": active_buffs.duplicate(),
	}


func _resources_dict() -> Dictionary:
	var out := {}
	for key: String in class_resources.keys():
		out[key] = class_resources[key]
	return out


static func from_dict(d: Dictionary) -> CharacterSheet:
	var s := CharacterSheet.new()
	s.name = str(d.get("name", ""))
	s.class_id = str(d.get("class_id", ""))
	s.ancestry_id = str(d.get("ancestry_id", ""))
	s.level = clampi(DictUtil.to_int(d.get("level", 1), 1), 1, MAX_LEVEL)
	s.xp = DictUtil.to_int(d.get("xp", 0), 0)
	var ab: Variant = d.get("abilities", {})
	if typeof(ab) == TYPE_DICTIONARY:
		var ab_dict: Dictionary = ab
		s.abilities = AbilityScores.from_dict(ab_dict)
	s.max_hp = maxi(1, DictUtil.to_int(d.get("max_hp", 1), 1))
	s.current_hp = clampi(DictUtil.to_int(d.get("current_hp", s.max_hp), s.max_hp), 0, s.max_hp)
	s.temp_hp = maxi(0, DictUtil.to_int(d.get("temp_hp", 0), 0))
	if d.has("armor_base") or not d.has("armor_bonus"):
		s.armor_base = maxi(0, DictUtil.to_int(d.get("armor_base", 0), 0))
		s.armor_max_dex = DictUtil.to_int(d.get("armor_max_dex", -1), -1)
		s.shield_bonus = DictUtil.to_int(d.get("shield_bonus", 0), 0)
	else:
		# Legacy (M0) sheets: AC = 10 + DEX + armor_bonus.
		s.shield_bonus = DictUtil.to_int(d.get("armor_bonus", 0), 0)
	s.speed = DictUtil.to_int(d.get("speed", 30), 30)
	s.hit_die = DictUtil.to_int(d.get("hit_die", 8), 8)
	s.hit_dice_total = DictUtil.to_int(d.get("hit_dice_total", s.level), s.level)
	s.hit_dice_remaining = DictUtil.to_int(d.get("hit_dice_remaining", s.hit_dice_total), s.hit_dice_total)
	for save in DictUtil.to_ability_array(d.get("proficient_saves", [])):
		if save >= 0 and not s.proficient_saves.has(save):
			s.proficient_saves.append(save)
	for skill in DictUtil.to_skill_array(d.get("proficient_skills", [])):
		if skill >= 0 and not s.proficient_skills.has(skill):
			s.proficient_skills.append(skill)
	s.death_save_successes = DictUtil.to_int(d.get("death_save_successes", 0), 0)
	s.death_save_failures = DictUtil.to_int(d.get("death_save_failures", 0), 0)
	s.stable = DictUtil.to_bool(d.get("stable", false), false)
	s.dead = DictUtil.to_bool(d.get("dead", false), false)
	s.uses_death_saves = DictUtil.to_bool(d.get("uses_death_saves", true), true)
	s.conditions = DictUtil.to_string_array(d.get("conditions", []))
	s.damage_resistances = DictUtil.to_string_array(d.get("damage_resistances", []))
	s.damage_immunities = DictUtil.to_string_array(d.get("damage_immunities", []))
	s.damage_vulnerabilities = DictUtil.to_string_array(d.get("damage_vulnerabilities", []))
	s.deepest_floor = DictUtil.to_int(d.get("deepest_floor", 0), 0)
	for raw in DictUtil.to_dict_array(d.get("attacks", [])):
		s.attacks.append(CharacterSheet.normalize_attack(raw))
	s.features = DictUtil.to_string_array(d.get("features", []))
	s.weapon_proficiencies = DictUtil.to_string_array(d.get("weapon_proficiencies", []))
	for raw in DictUtil.to_dict_array(d.get("inventory", [])):
		s.add_item(str(raw.get("item", "")), DictUtil.to_int(raw.get("qty", 1), 0))
	var eq: Variant = d.get("equipped", {})
	if typeof(eq) == TYPE_DICTIONARY:
		var eq_d: Dictionary = eq
		for slot in SLOTS:
			var held := "" if eq_d.get(slot) == null else str(eq_d.get(slot, ""))
			s.equipped[slot] = held if s.has_item(held) else ""
	var ability_v: Variant = d.get("casting_ability", "")
	s.casting_ability = -1 if ability_v == null or str(ability_v).is_empty() else Ability.from_string(str(ability_v))
	s.spells_known = DictUtil.to_string_array(d.get("spells_known", []))
	s.spells_prepared = DictUtil.to_string_array(d.get("spells_prepared", []))
	s.spell_slots_max = DictUtil.to_int_array(d.get("spell_slots_max", []))
	s.spell_slots = DictUtil.to_int_array(d.get("spell_slots", s.spell_slots_max))
	s.spell_slots.resize(s.spell_slots_max.size())
	s.slot_recovery = str(d.get("slot_recovery", "long_rest"))
	var res: Variant = d.get("class_resources", {})
	if typeof(res) == TYPE_DICTIONARY:
		var res_d: Dictionary = res
		for key: Variant in res_d.keys():
			s.class_resources[str(key)] = DictUtil.to_int(res_d[key], 0)
	s.active_buffs = DictUtil.to_string_array(d.get("active_buffs", []))
	return s


## Copies an attack dictionary with JSON-safe, typed values (to_hit as int).
static func normalize_attack(raw: Dictionary) -> Dictionary:
	var attack: Dictionary = raw.duplicate(true)
	attack["name"] = str(raw.get("name", "Attack"))
	attack["kind"] = str(raw.get("kind", "melee"))
	attack["to_hit"] = DictUtil.to_int(raw.get("to_hit", 0), 0)
	attack["damage"] = str(raw.get("damage", "0"))
	attack["damage_type"] = str(raw.get("damage_type", "")).to_lower()
	if raw.has("range_tiles"):
		var tiles := DictUtil.to_int_array(raw["range_tiles"])
		if tiles.size() == 2:
			attack["range_tiles"] = [tiles[0], tiles[1]]
	return attack

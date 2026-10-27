class_name CharacterBuilder
extends RefCounted
## Builds a level 1 CharacterSheet from a class, an ancestry, ability scores
## and skill picks, and equips the class's starting armor, shield and weapon.

const MAX_STARTING_SCORE := 20
const SHIELD_AC_BONUS := 2


## Level 1 HP = hit die + CON modifier (min 1), with CON after ancestry
## bonuses. Saving throw proficiencies come from the class. Skills must be in
## the class list; extras are dropped with an error. `ancestry` may be null (no
## bonuses, speed 30). `weapon` overrides the class's starting weapon (which
## ContentLoader.load_classes() resolves into cls.starting_weapon_def).
## Also: class features, weapon proficiencies, spellcasting (ability, known =
## prepared = the class's level-1 picks, level-1 slots), full class resources,
## and gear: the starting weapon, armor and shield become carried, equipped
## items (armor by starting_armor.item, else the armor item with the same
## base / max_dex; the shield by the "shield" item) and the starting_kit is
## added. Without matching item definitions the armor / shield numbers are
## set directly as before. `content` is a ContentLoader.cache()-shaped
## dictionary ({} = the cache).
## Level-1 progression: a class whose subclass starts at level 1 (cleric,
## sorcerer, warlock) gets its SRD subclass and that subclass's level-1
## features; `choices` answers creation_choices() like LevelUp.apply's made
## ({"fighting_style": id, "expertise": [skills], "feature_options":
## {feature: option}}); omitted answers take each entry's default, invalid
## ones push_error and take the default. Always-prepared subclass spells are
## added (LevelUp.sync_subclass_spells).
static func create(character_name: String, cls: ClassDefinition, ancestry: AncestryDefinition, scores: AbilityScores, chosen_skills: Array[int], weapon: WeaponDefinition = null, content: Dictionary = {}, choices: Dictionary = {}) -> CharacterSheet:
	if cls == null:
		push_error("CharacterBuilder.create: class definition is null")
		return null
	var sheet := CharacterSheet.new()
	sheet.name = character_name
	sheet.class_id = cls.id
	sheet.level = 1
	sheet.xp = 0
	sheet.abilities = scores.copy() if scores != null else AbilityScores.new()
	if ancestry != null:
		sheet.ancestry_id = ancestry.id
		sheet.speed = ancestry.speed
		sheet.darkvision_ft = ancestry.darkvision_ft
		for ability in range(Ability.COUNT):
			var bonus := ancestry.bonus_for(ability)
			if bonus != 0:
				var raised := mini(MAX_STARTING_SCORE, sheet.abilities.get_score(ability) + bonus)
				sheet.abilities.set_score(ability, raised)
	sheet.hit_die = cls.hit_die
	sheet.hit_dice_total = 1
	sheet.hit_dice_remaining = 1
	sheet.max_hp = maxi(1, cls.hit_die + sheet.abilities.get_modifier(Ability.Type.CON))
	sheet.current_hp = sheet.max_hp
	for save in cls.saving_throws:
		sheet.proficient_saves.append(save)
	var picked: Array[int] = []
	for skill in chosen_skills:
		if not cls.skill_choices.has(skill):
			push_error("CharacterBuilder: %s is not a %s skill choice" % [Skill.name_of(skill), cls.display_name])
			continue
		if not picked.has(skill):
			picked.append(skill)
	if picked.size() > cls.skill_choice_count:
		push_error("CharacterBuilder: %s may choose %d skills, got %d; extras dropped" % [cls.display_name, cls.skill_choice_count, picked.size()])
		picked.resize(cls.skill_choice_count)
	sheet.proficient_skills = picked
	sheet.features = cls.features.duplicate()
	sheet.weapon_proficiencies = cls.weapon_proficiencies.duplicate()
	sheet.casting_ability = cls.spellcasting_ability
	sheet.spells_known = cls.spells_prepared.duplicate()
	sheet.spells_prepared = cls.spells_prepared.duplicate()
	sheet.spell_slots_max = cls.slots_for_level(1)
	sheet.spell_slots = sheet.spell_slots_max.duplicate()
	sheet.slot_recovery = cls.slot_recovery
	sheet.restore_class_resources()
	CharacterBuilder._apply_level_one_progression(sheet, cls, content, choices)
	CharacterBuilder._equip_starting_gear(sheet, cls, weapon, content)
	return sheet


## The progression choices a new character of cls with chosen_skills makes
## (LevelUp choice entries: fighting_style, expertise, feature_option).
static func creation_choices(cls: ClassDefinition, chosen_skills: Array[int], content: Dictionary = {}) -> Array[Dictionary]:
	var s := CharacterSheet.new()
	s.class_id = cls.id
	s.proficient_skills = chosen_skills.duplicate()
	s.features = cls.features.duplicate()
	var gained := cls.features.duplicate()
	if cls.has_subclass() and cls.subclass_level <= 1:
		s.subclass_id = cls.subclass_id
		for f in cls.subclass_features_at(1):
			if not gained.has(f):
				gained.append(f)
	return LevelUp._choice_entries(s, cls, 1, gained, ContentLoader.resolve(content))


static func _apply_level_one_progression(sheet: CharacterSheet, cls: ClassDefinition, content: Dictionary, choices: Dictionary) -> void:
	var entries := CharacterBuilder.creation_choices(cls, sheet.proficient_skills, content)
	if cls.has_subclass() and cls.subclass_level <= 1:
		sheet.subclass_id = cls.subclass_id
		for f in cls.subclass_features_at(1):
			sheet.gain_feature(f)
	var picks := {}
	var err := LevelUp.check_choices(entries, choices, picks)
	if not err.is_empty():
		push_error("CharacterBuilder: %s; using the defaults" % err)
		picks = {}
		LevelUp.check_choices(entries, {}, picks)
	LevelUp.apply_picks(sheet, picks)
	LevelUp.sync_subclass_spells(sheet, cls)


static func _equip_starting_gear(sheet: CharacterSheet, cls: ClassDefinition, weapon: WeaponDefinition, content: Dictionary) -> void:
	var c := ContentLoader.resolve(content).duplicate()
	var wielded := weapon if weapon != null else cls.starting_weapon_def
	if wielded != null:
		# Make sure the wielded weapon resolves even if it is not in the content set.
		var weapons: Dictionary = c["weapons"]
		weapons = weapons.duplicate()
		weapons[wielded.id] = wielded
		c["weapons"] = weapons
	var items: Dictionary = c["items"]
	sheet.armor_base = cls.starting_armor_base
	sheet.armor_max_dex = cls.starting_armor_max_dex
	sheet.shield_bonus = SHIELD_AC_BONUS if cls.starting_shield else 0
	if cls.starting_armor_base > 0:
		var armor_id := cls.starting_armor_item
		if armor_id.is_empty() or not items.has(armor_id):
			armor_id = CharacterBuilder._find_armor(items, cls.starting_armor_base, cls.starting_armor_max_dex)
		if not armor_id.is_empty():
			sheet.add_item(armor_id)
			if not sheet.equip(armor_id, CharacterSheet.SLOT_ARMOR, c).is_empty():
				sheet.armor_base = cls.starting_armor_base
				sheet.armor_max_dex = cls.starting_armor_max_dex
	if wielded != null:
		var weapon_item := CharacterBuilder._find_weapon_item(items, wielded.id)
		sheet.add_item(weapon_item)
		var err := sheet.equip(weapon_item, CharacterSheet.SLOT_MAIN_HAND, c)
		if not err.is_empty():
			push_error("CharacterBuilder: cannot equip %s: %s" % [weapon_item, err])
	elif not cls.starting_weapon.is_empty():
		push_error("CharacterBuilder: %s starting weapon '%s' is not loaded; unarmed only" % [cls.display_name, cls.starting_weapon])
	if cls.starting_shield:
		var shield_id := CharacterBuilder._find_shield(items)
		if not shield_id.is_empty():
			sheet.add_item(shield_id)
			if not sheet.equip(shield_id, CharacterSheet.SLOT_OFF_HAND, c).is_empty():
				sheet.shield_bonus = SHIELD_AC_BONUS
	for entry in cls.starting_kit:
		sheet.add_item(str(entry["item"]), DictUtil.to_int(entry["qty"]))
	sheet.rebuild_attacks(c)


## The item that wields weapon_id: an item with that id, else the first (by
## id) weapon item pointing at it, else weapon_id itself (resolved as a weapon).
static func _find_weapon_item(items: Dictionary, weapon_id: String) -> String:
	if items.has(weapon_id):
		return weapon_id
	var ids: Array = items.keys()
	ids.sort()
	for id_v: Variant in ids:
		var it: ItemDefinition = items[id_v]
		if it.kind == ItemDefinition.KIND_WEAPON and it.weapon_id == weapon_id:
			return it.id
	return weapon_id


static func _find_armor(items: Dictionary, base: int, max_dex: int) -> String:
	var ids: Array = items.keys()
	ids.sort()
	for id_v: Variant in ids:
		var it: ItemDefinition = items[id_v]
		if it.kind == ItemDefinition.KIND_ARMOR and it.armor_base == base and it.armor_max_dex == max_dex:
			return it.id
	return ""


static func _find_shield(items: Dictionary) -> String:
	if items.has("shield"):
		var it: ItemDefinition = items["shield"]
		if it.kind == ItemDefinition.KIND_SHIELD:
			return "shield"
	var ids: Array = items.keys()
	ids.sort()
	for id_v: Variant in ids:
		var it: ItemDefinition = items[id_v]
		if it.kind == ItemDefinition.KIND_SHIELD:
			return it.id
	return ""


## A weapon attack. kind "melee": STR, or DEX for a finesse weapon (or a monk
## weapon with Martial Arts) when DEX is higher, reach 1 tile. "thrown": the
## same ability, the weapon's range. "ranged": DEX, the weapon's range.
## to_hit = ability modifier + proficiency (if proficient); damage = weapon
## dice (one-handed) + ability modifier, e.g. "1d8+3". item_id is the weapon
## item; consumes is the item used up per attack ("" = none).
## Fighting styles: Archery +2 to hit with ranged weapons. Martial Arts: a monk
## weapon uses the Martial Arts die when it is larger. damage_bonus adds to the
## damage modifier (Dueling); add_mod false leaves a positive ability modifier
## out of the damage (off-hand attack without the Two-Weapon Fighting style).
static func weapon_attack(sheet: CharacterSheet, weapon: WeaponDefinition, proficient: bool = true, kind: String = "melee", item_id: String = "", consumes: String = "", damage_bonus: int = 0, add_mod: bool = true) -> Dictionary:
	var str_mod := sheet.ability_modifier(Ability.Type.STR)
	var dex_mod := sheet.ability_modifier(Ability.Type.DEX)
	var use_dex := false
	if kind == "ranged":
		use_dex = true
	elif weapon.is_finesse() or (sheet.has_feature("martial_arts") and CharacterBuilder.is_monk_weapon(weapon)):
		use_dex = dex_mod > str_mod
	var mod := dex_mod if use_dex else str_mod
	var attack_name := weapon.display_name
	if kind == "thrown" and not weapon.ranged:
		attack_name += " (thrown)"
	var properties: Array = []
	for p in weapon.properties:
		properties.append(p)
	var tiles := weapon.range_tiles()
	var dice := weapon.damage
	if sheet.has_feature("martial_arts") and kind != "ranged" and CharacterBuilder.is_monk_weapon(weapon):
		var parsed := DiceExpr.parse(weapon.damage)
		if parsed.valid and parsed.count == 1 and sheet.martial_arts_die() > parsed.sides:
			dice = "1d%d" % sheet.martial_arts_die()
	var to_hit := mod + (sheet.proficiency_bonus() if proficient else 0)
	if kind == "ranged" and sheet.has_fighting_style("archery"):
		to_hit += 2
	var damage_mod := (mod if add_mod or mod < 0 else 0) + damage_bonus
	return {
		"name": attack_name,
		"kind": kind,
		"to_hit": to_hit,
		"damage": dice + CharacterBuilder.signed(damage_mod),
		"damage_type": weapon.damage_type,
		"weapon_id": weapon.id,
		"item": item_id if not item_id.is_empty() else weapon.id,
		"consumes": consumes,
		"range_tiles": [1, 1] if kind == "melee" else [tiles[0], tiles[1]],
		"ability": "DEX" if use_dex else "STR",
		"properties": properties,
		"proficient": proficient,
	}


## SRD 5.1 monk weapons: shortswords and simple melee weapons that are not
## two-handed or heavy.
static func is_monk_weapon(weapon: WeaponDefinition) -> bool:
	if weapon.id == "shortsword":
		return true
	return weapon.category == "simple" and not weapon.ranged and not weapon.is_two_handed() and not weapon.has_property("heavy")


## 3 -> "+3", -1 -> "-1", 0 -> "".
static func signed(mod: int) -> String:
	if mod > 0:
		return "+%d" % mod
	if mod < 0:
		return "-%d" % absi(mod)
	return ""

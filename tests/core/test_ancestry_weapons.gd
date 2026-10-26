extends TestCase

var classes: Dictionary
var ancestries: Dictionary
var weapons: Dictionary


func before_each() -> void:
	classes = ContentLoader.load_classes()
	ancestries = ContentLoader.load_ancestries()
	weapons = ContentLoader.load_weapons()


func _cls(class_id: String) -> ClassDefinition:
	var def: ClassDefinition = classes.get(class_id)
	return def


func _anc(ancestry_id: String) -> AncestryDefinition:
	var def: AncestryDefinition = ancestries.get(ancestry_id)
	return def


func _wpn(weapon_id: String) -> WeaponDefinition:
	var def: WeaponDefinition = weapons.get(weapon_id)
	return def


## STR, DEX, CON, INT, WIS, CHA
func _scores(values: Array[int]) -> AbilityScores:
	var s := AbilityScores.new()
	s.set_all(values)
	return s


func _build(class_id: String, ancestry_id: String, values: Array[int]) -> CharacterSheet:
	var none: Array[int] = []
	return CharacterBuilder.create("Test", _cls(class_id), _anc(ancestry_id), _scores(values), none)


func test_loads_four_ancestries() -> void:
	assert_eq(ancestries.size(), 4)
	var human := _anc("human")
	for a in range(Ability.COUNT):
		assert_eq(human.bonus_for(a), 1)
	var dwarf := _anc("hill_dwarf")
	assert_eq(dwarf.speed, 25)
	assert_eq(dwarf.bonus_for(Ability.Type.CON), 2)
	assert_eq(dwarf.bonus_for(Ability.Type.WIS), 1)
	assert_eq(dwarf.bonus_for(Ability.Type.STR), 0)
	assert_eq(_anc("high_elf").bonus_for(Ability.Type.DEX), 2)
	assert_eq(_anc("high_elf").bonus_for(Ability.Type.INT), 1)
	var halfling := _anc("lightfoot_halfling")
	assert_eq(halfling.size, "small")
	assert_eq(halfling.speed, 25)
	assert_eq(halfling.bonus_for(Ability.Type.CHA), 1)


func test_loads_six_weapons() -> void:
	assert_eq(weapons.size(), 6)
	var ls := _wpn("longsword")
	assert_eq(ls.damage, "1d8")
	assert_eq(ls.damage_type, "slashing")
	assert_eq(ls.category, "martial")
	assert_eq(ls.versatile_damage, "1d10")
	assert_true(ls.has_property("versatile"))
	var dagger := _wpn("dagger")
	assert_true(dagger.is_finesse())
	assert_eq(dagger.properties, ["finesse", "light", "thrown"])
	assert_eq(dagger.range_ft, [20, 60])
	assert_eq(_wpn("mace").category, "simple")
	assert_false(_wpn("handaxe").is_finesse())


func test_class_starting_equipment() -> void:
	var f := _cls("fighter")
	assert_eq(f.starting_weapon, "longsword")
	assert_eq(f.starting_weapon_def.id, "longsword")
	assert_eq(f.starting_armor_base, 16)
	assert_eq(f.starting_armor_max_dex, 0)
	assert_false(f.starting_shield)
	assert_true(_cls("cleric").starting_shield)
	assert_eq(_cls("wizard").starting_armor_base, 0)
	assert_eq(_cls("rogue").starting_weapon_def.id, "shortsword")
	assert_true(_cls("rogue").is_proficient_with(_wpn("shortsword")))
	assert_true(_cls("wizard").is_proficient_with(_wpn("quarterstaff")))
	assert_false(_cls("wizard").is_proficient_with(_wpn("longsword")))


func test_human_fighter_longsword() -> void:
	var s := _build("fighter", "human", [15, 13, 14, 8, 12, 10])
	assert_eq(s.abilities.get_score(Ability.Type.STR), 16)
	assert_eq(s.abilities.get_score(Ability.Type.CHA), 11)
	assert_eq(s.ancestry_id, "human")
	assert_eq(s.speed, 30)
	assert_eq(s.max_hp, 12, "d10 + CON 15 (+2)")
	assert_eq(s.armor_class(), 16, "chain mail ignores DEX")
	assert_eq(s.attacks.size(), 1)
	var atk := s.attacks[0]
	assert_eq(atk["name"], "Longsword")
	assert_eq(atk["to_hit"], 5, "STR +3, proficiency +2")
	assert_eq(atk["damage"], "1d8+3")
	assert_eq(atk["damage_type"], "slashing")
	assert_eq(atk["weapon_id"], "longsword")
	var c := Combatant.from_sheet("pc", s)
	assert_eq(c.attacks.size(), 2, "weapon then unarmed strike")
	assert_eq(c.attacks[0]["damage"], "1d8+3")
	assert_eq(c.attacks[1]["name"], "Unarmed Strike")
	assert_eq(c.speed_tiles(), 6)


func test_halfling_rogue_uses_dex_for_finesse() -> void:
	var s := _build("rogue", "lightfoot_halfling", [10, 15, 14, 12, 13, 8])
	assert_eq(s.abilities.get_score(Ability.Type.DEX), 17)
	assert_eq(s.speed, 25)
	assert_eq(Combatant.from_sheet("r", s).speed_tiles(), 5)
	assert_eq(s.armor_class(), 14, "leather 11 + DEX 3")
	assert_eq(s.attacks[0]["to_hit"], 5)
	assert_eq(s.attacks[0]["damage"], "1d6+3")


func test_hill_dwarf_cleric_shield() -> void:
	var s := _build("cleric", "hill_dwarf", [13, 14, 14, 8, 15, 10])
	assert_eq(s.abilities.get_score(Ability.Type.WIS), 16)
	assert_eq(s.abilities.get_score(Ability.Type.CON), 16)
	assert_eq(s.speed, 25)
	assert_eq(s.armor_class(), 18, "scale mail 14 + DEX 2 (max 2) + shield 2")
	assert_eq(s.attacks[0]["name"], "Mace")
	assert_eq(s.attacks[0]["damage"], "1d6+1")
	assert_eq(s.attacks[0]["to_hit"], 3)
	var dexy := _build("cleric", "high_elf", [10, 16, 12, 8, 15, 10])
	assert_eq(dexy.armor_class(), 18, "DEX 18 (+4) is capped at +2")


func test_high_elf_wizard_unarmored() -> void:
	var s := _build("wizard", "high_elf", [8, 14, 13, 15, 12, 10])
	assert_eq(s.armor_class(), 13, "10 + DEX 16 (+3)")
	assert_eq(s.attacks[0]["damage"], "1d6-1", "STR 8")
	assert_eq(s.attacks[0]["to_hit"], 1)


func test_null_ancestry_and_weapon_override() -> void:
	var none: Array[int] = []
	var s := CharacterBuilder.create("Plain", _cls("fighter"), null, _scores([15, 13, 14, 8, 12, 10]), none, _wpn("handaxe"))
	assert_eq(s.speed, 30)
	assert_eq(s.abilities.get_score(Ability.Type.STR), 15)
	assert_eq(s.attacks[0]["name"], "Handaxe")
	assert_eq(s.attacks[0]["damage"], "1d6+2")


func test_ancestry_bonus_capped_at_20() -> void:
	var s := _build("fighter", "human", [20, 10, 10, 10, 10, 10])
	assert_eq(s.abilities.get_score(Ability.Type.STR), 20)


func test_sheet_round_trip_keeps_attacks_and_armor() -> void:
	var s := _build("cleric", "hill_dwarf", [13, 14, 14, 8, 15, 10])
	var data: Dictionary = JSON.parse_string(JSON.stringify(s.to_dict()))
	var copy := CharacterSheet.from_dict(data)
	assert_eq(copy.to_dict(), s.to_dict())
	assert_eq(copy.armor_class(), 18)
	assert_eq(copy.attacks[0]["to_hit"], 3)
	assert_eq(typeof(copy.attacks[0]["to_hit"]), TYPE_INT)
	assert_eq(copy.ancestry_id, "hill_dwarf")


func test_legacy_armor_bonus_is_accepted() -> void:
	var legacy := CharacterSheet.from_dict({"abilities": {"DEX": 14}, "armor_bonus": 4})
	assert_eq(legacy.armor_class(), 16, "10 + DEX 2 + old armor_bonus 4")


func test_invalid_definitions_are_rejected() -> void:
	assert_null(AncestryDefinition.from_dict({"id": "broken"}))
	assert_null(AncestryDefinition.from_dict({"id": "x", "display_name": "X", "speed": 30, "size": "medium", "ability_bonuses": {"LUCK": 2}}))
	assert_null(AncestryDefinition.from_dict({"id": "x", "display_name": "X", "speed": 30, "size": "gigantic", "ability_bonuses": {}}))
	assert_null(WeaponDefinition.from_dict({"id": "broken"}))
	assert_null(WeaponDefinition.from_dict({"id": "x", "display_name": "X", "damage": "1d8+2", "damage_type": "slashing", "properties": [], "category": "simple"}))
	assert_null(WeaponDefinition.from_dict({"id": "x", "display_name": "X", "damage": "1d8", "damage_type": "slashing", "properties": [], "category": "exotic"}))

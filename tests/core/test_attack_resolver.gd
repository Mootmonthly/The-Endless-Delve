extends TestCase


func _c(combatant_id: String, armor_bonus: int = 0, hp: int = 30, team: int = 0) -> Combatant:
	var s := CharacterSheet.new()
	s.name = combatant_id
	s.shield_bonus = armor_bonus  # AC = 10 + DEX 0 + bonus
	s.max_hp = hp
	s.current_hp = hp
	return Combatant.from_sheet(combatant_id, s, team)


func _attack(to_hit: int, damage: String, damage_type: String = "slashing") -> Dictionary:
	return {"name": "Blade", "to_hit": to_hit, "damage": damage, "damage_type": damage_type}


func _ordinary_roll(r: Rng) -> bool:
	var n := D20.roll(r).natural
	return n > 1 and n < 20


func _seed_for_natural(n: int) -> int:
	return seed_where(func(r: Rng) -> bool: return D20.roll(r).natural == n)


func test_nat20_always_hits_and_crits() -> void:
	var target := _c("wall", 100)
	var res := AttackResolver.resolve_attack(_c("hero"), target, _attack(0, "1d6+2"), Rng.new(_seed_for_natural(20)))
	assert_true(res.hit)
	assert_true(res.critical)
	assert_eq(res.damage.rolls.size(), 2, "crit doubles the dice")
	assert_eq(res.damage_total, res.damage.rolls[0] + res.damage.rolls[1] + 2, "modifier added once")
	assert_eq(target.sheet.current_hp, 30 - res.damage_total)


func test_nat1_always_misses() -> void:
	var target := _c("paper", -20)
	var res := AttackResolver.resolve_attack(_c("hero"), target, _attack(100, "1d6"), Rng.new(_seed_for_natural(1)))
	assert_false(res.hit)
	assert_true(res.fumble)
	assert_null(res.damage)
	assert_eq(target.sheet.current_hp, 30)


func test_miss_leaves_hp() -> void:
	var s := seed_where(_ordinary_roll)
	var target := _c("tank", 20)
	var res := AttackResolver.resolve_attack(_c("hero"), target, _attack(0, "2d6"), Rng.new(s))
	assert_false(res.hit)
	assert_eq(res.damage_total, 0)
	assert_eq(res.target_hp_after, 30)


func test_hit_when_total_meets_ac() -> void:
	var s := _seed_for_natural(12)
	var hit := AttackResolver.resolve_attack(_c("hero"), _c("t", 4), _attack(2, "1"), Rng.new(s))
	assert_true(hit.hit, "12 + 2 = 14 vs AC 14")
	assert_eq(hit.attack_total, 14)
	var miss := AttackResolver.resolve_attack(_c("hero"), _c("t", 5), _attack(2, "1"), Rng.new(s))
	assert_false(miss.hit, "14 vs AC 15")


func test_drop_and_death_flags() -> void:
	var s := _seed_for_natural(15)
	var pc := _c("pc", 0, 3)
	var res := AttackResolver.resolve_attack(_c("orc"), pc, _attack(5, "5"), Rng.new(s))
	assert_true(res.target_dropped)
	assert_false(res.target_died, "characters fall unconscious")
	var rat := Combatant.from_monster("rat", _rat(), Combatant.TEAM_MONSTERS, null)
	var res2 := AttackResolver.resolve_attack(_c("pc"), rat, _attack(5, "20"), Rng.new(s))
	assert_true(res2.target_died, "monsters die at 0 hp")


func test_advantage_rolls_two_dice() -> void:
	var res := AttackResolver.resolve_attack(_c("a"), _c("b"), _attack(3, "1d4"), Rng.new(9), D20.RollMode.ADVANTAGE)
	assert_eq(res.d20.all.size(), 2)
	assert_eq(res.d20.mode, D20.RollMode.ADVANTAGE)


func test_vulnerability_doubles_damage() -> void:
	var target := _c("bones")
	target.sheet.damage_vulnerabilities.append("bludgeoning")
	var res := AttackResolver.resolve_attack(_c("a"), target, _attack(5, "4", "bludgeoning"), Rng.new(_seed_for_natural(15)))
	assert_eq(res.damage_total, 8)


func test_summary_mentions_outcome() -> void:
	var res := AttackResolver.resolve_attack(_c("Hero"), _c("Goblin"), _attack(5, "1d6"), Rng.new(_seed_for_natural(20)))
	var text := res.summary()
	assert_has(text, "Hero attacks Goblin")
	assert_has(text, "CRITICAL HIT")


func _rat() -> MonsterDefinition:
	return MonsterDefinition.from_dict({
		"id": "rat", "display_name": "Rat", "armor_class": 10, "hit_points": 2, "hit_dice": "1d4",
		"speed": 20, "abilities": {"STR": 2, "DEX": 11, "CON": 9, "INT": 2, "WIS": 10, "CHA": 4},
		"challenge_rating": 0, "xp": 10,
		"attacks": [{"name": "Bite", "to_hit": 0, "damage": "1", "damage_type": "piercing"}],
	})

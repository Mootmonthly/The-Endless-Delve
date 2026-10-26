class_name CoreFixtures
extends RefCounted
## Hand-built content and combat helpers shared by the M2 core tests
## (independent of the JSON under data/).


static func weapon(d: Dictionary) -> WeaponDefinition:
	var base := {"schema_version": 1, "category": "simple", "damage_type": "piercing", "properties": []}
	base.merge(d, true)
	return WeaponDefinition.from_dict(base)


static func item(d: Dictionary) -> ItemDefinition:
	var base := {"schema_version": 1}
	base.merge(d, true)
	return ItemDefinition.from_dict(base)


static func spell(d: Dictionary) -> SpellDefinition:
	var base := {"schema_version": 1, "casting_time": "action", "target": "creature", "range_ft": 120}
	base.merge(d, true)
	return SpellDefinition.from_dict(base)


## {"classes", "ancestries", "weapons", "items", "spells", "loot_tables", "monsters"}.
static func content() -> Dictionary:
	var weapons := {}
	for wd: WeaponDefinition in [
		weapon({"id": "dagger", "display_name": "Dagger", "damage": "1d4", "properties": ["finesse", "light", "thrown"], "range_ft": [20, 60]}),
		weapon({"id": "handaxe", "display_name": "Handaxe", "damage": "1d6", "damage_type": "slashing", "properties": ["light", "thrown"], "range_ft": [20, 60]}),
		weapon({"id": "longsword", "display_name": "Longsword", "category": "martial", "damage": "1d8", "damage_type": "slashing", "properties": ["versatile"], "versatile_damage": "1d10"}),
		weapon({"id": "shortsword", "display_name": "Shortsword", "category": "martial", "damage": "1d6", "properties": ["finesse", "light"]}),
		weapon({"id": "greataxe", "display_name": "Greataxe", "category": "martial", "damage": "1d12", "damage_type": "slashing", "properties": ["heavy", "two_handed"]}),
		weapon({"id": "shortbow", "display_name": "Shortbow", "damage": "1d6", "properties": ["ammunition", "two_handed"], "range_ft": [80, 320], "ranged": true, "ammo_id": "arrows"}),
		weapon({"id": "dart", "display_name": "Dart", "damage": "1d4", "properties": ["finesse", "thrown"], "range_ft": [20, 60], "ranged": true}),
	]:
		weapons[wd.id] = wd
	var items := {}
	for idef: ItemDefinition in [
		item({"id": "dagger", "display_name": "Dagger", "kind": "weapon", "weapon_id": "dagger", "stackable": true}),
		item({"id": "handaxe", "display_name": "Handaxe", "kind": "weapon", "weapon_id": "handaxe", "stackable": true}),
		item({"id": "longsword", "display_name": "Longsword", "kind": "weapon", "weapon_id": "longsword"}),
		item({"id": "shortsword", "display_name": "Shortsword", "kind": "weapon", "weapon_id": "shortsword"}),
		item({"id": "greataxe", "display_name": "Greataxe", "kind": "weapon", "weapon_id": "greataxe"}),
		item({"id": "shortbow", "display_name": "Shortbow", "kind": "weapon", "weapon_id": "shortbow"}),
		item({"id": "dart", "display_name": "Dart", "kind": "weapon", "weapon_id": "dart", "stackable": true}),
		item({"id": "arrows", "display_name": "Arrows", "kind": "ammo"}),
		item({"id": "chain_mail", "display_name": "Chain Mail", "kind": "armor", "armor": {"base": 16, "max_dex": 0, "category": "heavy"}}),
		item({"id": "leather_armor", "display_name": "Leather Armor", "kind": "armor", "armor": {"base": 11, "max_dex": -1, "category": "light"}}),
		item({"id": "scale_mail", "display_name": "Scale Mail", "kind": "armor", "armor": {"base": 14, "max_dex": 2, "category": "medium"}}),
		item({"id": "shield", "display_name": "Shield", "kind": "shield", "shield": {"bonus": 2}}),
		item({"id": "potion_of_healing", "display_name": "Potion of Healing", "kind": "consumable", "use": {"action": "action", "effect": "heal", "dice": "2d4+2", "target": "self"}}),
		item({"id": "elixir", "display_name": "Elixir", "kind": "consumable", "use": {"action": "bonus_action", "effect": "temp_hp", "dice": "5", "target": "self"}}),
		item({"id": "antidote", "display_name": "Antidote", "kind": "consumable", "use": {"action": "action", "effect": "cure", "conditions": ["poisoned"]}}),
		item({"id": "salve", "display_name": "Salve", "kind": "consumable", "use": {"action": "action", "effect": "regrow", "target": "self"}}),
		item({"id": "gold", "display_name": "Gold", "kind": "gold"}),
		item({"id": "rations", "display_name": "Rations", "kind": "misc", "stackable": true}),
	]:
		items[idef.id] = idef
	var spells := {}
	for sdef: SpellDefinition in [
		spell({"id": "fire_bolt", "display_name": "Fire Bolt", "level": 0, "effect": {"type": "spell_attack", "damage": "1d10", "damage_type": "fire", "scaling": {"5": "2d10", "11": "3d10"}}}),
		spell({"id": "ray_of_frost", "display_name": "Ray of Frost", "level": 0, "range_ft": 60, "effect": {"type": "spell_attack", "damage": "1d8", "damage_type": "cold", "on_hit": {"slow_tiles": 2}}}),
		spell({"id": "shocking_grasp", "display_name": "Shocking Grasp", "level": 0, "range_ft": 5, "effect": {"type": "spell_attack", "attack": "melee", "damage": "1d8", "damage_type": "lightning", "on_hit": {"no_reactions": true}}}),
		spell({"id": "magic_missile", "display_name": "Magic Missile", "level": 1, "effect": {"type": "auto_hit", "darts": 3, "damage": "1d4+1", "damage_type": "force", "per_slot_level_above": 1}}),
		spell({"id": "sacred_flame", "display_name": "Sacred Flame", "level": 0, "range_ft": 60, "effect": {"type": "save", "save": "DEX", "damage": "1d8", "damage_type": "radiant", "on_save": "none"}}),
		spell({"id": "vicious_mockery", "display_name": "Vicious Mockery", "level": 0, "range_ft": 60, "effect": {"type": "save", "save": "WIS", "damage": "1d4", "damage_type": "psychic", "on_save": "none", "on_fail": {"disadvantage_next_attack": true}}}),
		spell({"id": "burning_hands", "display_name": "Burning Hands", "level": 1, "target": "self", "range_ft": 0, "effect": {"type": "unsupported"}}),
		spell({"id": "thunder_save", "display_name": "Thunder Save", "level": 1, "effect": {"type": "save", "save": "CON", "damage": "2d8", "damage_type": "thunder", "on_save": "half"}}),
		spell({"id": "cure_wounds", "display_name": "Cure Wounds", "level": 1, "range_ft": 5, "target": "creature_or_self", "effect": {"type": "heal", "dice": "1d8", "add_casting_mod": true, "per_slot_level_above": "1d8"}}),
		spell({"id": "healing_word", "display_name": "Healing Word", "level": 1, "casting_time": "bonus_action", "range_ft": 60, "target": "creature_or_self", "effect": {"type": "heal", "dice": "1d4", "add_casting_mod": true, "per_slot_level_above": "1d4"}}),
		spell({"id": "mage_armor", "display_name": "Mage Armor", "level": 1, "range_ft": 5, "target": "creature_or_self", "effect": {"type": "buff", "buff": "mage_armor"}}),
		spell({"id": "hex", "display_name": "Hex", "level": 1, "casting_time": "bonus_action", "range_ft": 90, "effect": {"type": "buff", "buff": "hex", "bonus_damage": "1d6", "damage_type": "necrotic"}}),
		spell({"id": "guiding_bolt", "display_name": "Guiding Bolt", "level": 1, "effect": {"type": "spell_attack", "damage": "4d6", "damage_type": "radiant", "per_slot_level_above": "1d6", "on_hit_buff": "guiding_bolt_mark"}}),
		spell({"id": "scorching_ray", "display_name": "Scorching Ray", "level": 2, "effect": {"type": "spell_attack", "rays": 3, "damage": "2d6", "damage_type": "fire", "per_slot_level_above": 1}}),
		spell({"id": "acid_arrow", "display_name": "Acid Arrow", "level": 2, "range_ft": 90, "effect": {"type": "spell_attack", "damage": "4d4", "damage_type": "acid", "on_miss": "half"}}),
	]:
		spells[sdef.id] = sdef
	var loot := {}
	var table := LootTable.from_dict({"id": "starter_gear", "rolls": 1, "entries": [
		{"item": "leather_armor", "weight": 3}, {"item": "potion_of_healing", "weight": 2, "qty": [1, 2]},
		{"item": "gold", "weight": 4, "qty": [5, 20]}, {"nothing": true, "weight": 1}]})
	loot[table.id] = table
	return {"classes": {}, "ancestries": {}, "weapons": weapons, "items": items, "spells": spells, "loot_tables": loot, "monsters": {}}


## A bare level-1 sheet with 10s everywhere unless scores are given.
static func sheet(sheet_name: String, hp: int = 30, scores: Array[int] = [], features: Array[String] = []) -> CharacterSheet:
	var s := CharacterSheet.new()
	s.name = sheet_name
	s.class_id = "test_class"
	s.max_hp = hp
	s.current_hp = hp
	if scores.size() == 6:
		s.abilities.set_all(scores)
	s.features = features.duplicate()
	s.weapon_proficiencies = ["simple", "martial"]
	s.restore_class_resources()
	return s


## A caster sheet: casting ability score 16 (+3), level-1 spells prepared,
## two level-1 and two level-2 slots.
static func caster(sheet_name: String, ability: int, prepared: Array[String], hp: int = 30) -> CharacterSheet:
	var s := CoreFixtures.sheet(sheet_name, hp)
	s.abilities.set_score(ability, 16)
	s.casting_ability = ability
	s.spells_known = prepared.duplicate()
	s.spells_prepared = prepared.duplicate()
	s.spell_slots_max = [2, 2]
	s.spell_slots = [2, 2]
	return s


static func combatant(c_id: String, s: CharacterSheet, team: int, pos: Vector2i, attacks: Array[Dictionary] = []) -> Combatant:
	s.uses_death_saves = team == Combatant.TEAM_PLAYERS
	var c := Combatant.from_sheet(c_id, s, team)
	if not attacks.is_empty():
		c.attacks = attacks.duplicate(true)
	c.position = pos
	return c


## Builds and starts an encounter on an open 12x12 map (wall at 6,6), trying
## seeds until first_id acts first. Combatants are rebuilt per seed by
## make_all.call() -> Array[Combatant]. Returns null when no seed works.
static func fight(make_all: Callable, first_id: String, content_set: Dictionary, map: WalkMap = null, region: Rect2i = Rect2i(0, 0, 12, 12)) -> Encounter:
	var m := map
	if m == null:
		m = WalkMap.new(12, 12, true)
		m.set_walkable(Vector2i(6, 6), false)
	for s in range(1, 500):
		var e := Encounter.new("t", Rng.new(s), m, region)
		e.content = content_set
		var all: Array = make_all.call()
		for c_v: Variant in all:
			var c: Combatant = c_v
			e.add_combatant(c)
		e.start()
		if e.current_actor() != null and e.current_actor().id == first_id:
			return e
	return null


static func first_event(evs: Array, kind: String) -> Dictionary:
	for ev_v: Variant in evs:
		var ev: Dictionary = ev_v
		if str(ev["kind"]) == kind:
			return ev
	return {}


static func events_of(evs: Array, kind: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for ev_v: Variant in evs:
		var ev: Dictionary = ev_v
		if str(ev["kind"]) == kind:
			out.append(ev)
	return out


static func kinds(evs: Array) -> Array[String]:
	var out: Array[String] = []
	for ev_v: Variant in evs:
		var ev: Dictionary = ev_v
		out.append(str(ev["kind"]))
	return out

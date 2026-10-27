extends TestCase
## Round D Phase D2 on the InstanceServer: landings, doors, props, respawns,
## exploration effects (round C hooks), the control intent and the floor's
## light. Headless, ticked by hand over a LocalTransport.

const DT := 1.0 / 20.0
const SEED := 4321

## 14x7, two rooms joined by door d1 at (6, 2) (a 1-wide corridor cell).
## Landings a (1, 1) and b (1, 5); stairs (11, 2) in z1 (guards the stairs,
## chest c_stairs); pack z2 (x 3..4, y 4..5); barrel p1 (2, 4) with loot,
## blocking crate p2 (5, 1); locked chest c_locked (1, 3); hidden chest
## c_hidden (5, 5).
const ROWS: Array[String] = [
	"##############",
	"#.....#......#",
	"#............#",
	"#.....#......#",
	"#.....#......#",
	"#.....#......#",
	"##############",
]

var server: InstanceServer
var transport: LocalTransport
var results: Array[Dictionary] = []


func before_each() -> void:
	server = InstanceServer.new()
	transport = LocalTransport.new()
	transport.result_received.connect(_on_result)
	results.clear()


func _on_result(r: Dictionary) -> void:
	results.append(r)


func after_each() -> void:
	if server != null:
		server.free()
		server = null


# --- helpers --------------------------------------------------------------------

## props_extra: prop id -> fields merged into that prop (e.g. "drops").
func _floor_dict(door: Dictionary = {}, two_rats: bool = false, light: String = "", props_extra: Dictionary = {}) -> Dictionary:
	var d1 := {"id": "d1", "position": [6, 2], "state": "closed"}
	d1.merge(door, true)
	var z1_monsters: Array = ["giant_rat", "giant_rat"] if two_rats else ["giant_rat"]
	var style := {}
	if not light.is_empty():
		style["light"] = light
	return {
		"schema_version": 2, "id": "d2_floor", "display_name": "Door Hall", "floor_number": 1,
		"rows": ROWS,
		"landings": [{"id": "a", "position": [1, 1], "facing": "east"}, {"id": "b", "position": [1, 5], "facing": "east"}],
		"stairs": [11, 2],
		"encounter_zones": [
			{"id": "z1", "rect": [7, 1, 6, 5], "monster_ids": z1_monsters, "spawn_points": [[12, 5], [12, 4]],
				"guards_stairs": true, "kind": "boss", "boss": true},
			{"id": "z2", "rect": [3, 4, 2, 2], "monster_ids": ["giant_rat"], "spawn_points": [[4, 5]]},
		],
		"chests": [
			{"id": "c_stairs", "position": [9, 5], "table": "starter_gear", "hidden": false},
			{"id": "c_locked", "position": [1, 3], "table": "starter_gear", "hidden": false, "locked": true},
			{"id": "c_hidden", "position": [5, 5], "table": "hidden_cache", "hidden": true},
		],
		"doors": [d1],
		"props": _props(props_extra),
		"respawn": {"pack_seconds": 1, "boss_seconds": 3},
		"theme_style": style,
	}


func _props(extra: Dictionary) -> Array:
	var props: Array = [
		{"id": "p1", "kind": "barrel", "position": [2, 4], "hp": 4, "blocks": true, "loot_table": "starter_gear"},
		{"id": "p2", "kind": "crate", "position": [5, 1], "hp": 6, "blocks": true},
	]
	for p: Variant in props:
		var pd: Dictionary = p
		if extra.has(pd["id"]):
			pd.merge(extra[pd["id"]], true)
	return props


func _floor(door: Dictionary = {}, two_rats: bool = false, light: String = "", props_extra: Dictionary = {}) -> FloorData:
	return FloorData.from_dict(_floor_dict(door, two_rats, light, props_extra))


## The fixture with d1 locked (DC 12) behind the Bronze Key, which crate p2 drops.
func _key_floor() -> FloorData:
	return _floor({"state": "locked", "dc": 12, "key_item": "key_bronze"}, false, "",
		{"p2": {"drops": [{"item": "key_bronze", "qty": 1}]}})


func _sheet(class_id: String = "fighter") -> CharacterSheet:
	var scores := AbilityScores.new()
	scores.set_all([15, 14, 13, 15, 12, 8] as Array[int])
	var skills: Array[int] = []
	var sheet := CharacterBuilder.create("Hero", ContentLoader.load_classes()[class_id],
			ContentLoader.load_ancestries()["human"], scores, skills)
	sheet.max_hp = 300
	sheet.current_hp = 300
	return sheet


## A wizard with the given spells prepared and 4 / 3 / 3 slots of levels 1-3.
func _wizard(spells: Array[String]) -> CharacterSheet:
	var s := _sheet("wizard")
	for id in spells:
		for list: Array[String] in [s.spells_known, s.spells_prepared]:
			if not list.has(id):
				list.append(id)
	s.spell_slots_max = [4, 3, 3] as Array[int]
	s.spell_slots = [4, 3, 3] as Array[int]
	return s


func _setup(f: FloorData, sheet: CharacterSheet = null, instance_seed: int = SEED) -> ServerEntity:
	server.configure(transport, f, instance_seed)
	server.add_player(LocalTransport.PEER_ID, sheet if sheet != null else _sheet())
	transport.pump()
	return server.get_entity("p1")


func _tick(n: int = 1) -> void:
	for _i in range(n):
		server._physics_process(DT)


func _send(type: String, fields: Dictionary = {}) -> void:
	var f := fields.duplicate()
	f["actor"] = "p1"
	transport.send_intent(Messages.make_intent(type, f))
	_tick()
	transport.pump()


func _of_kind(kind: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for r in results:
		if str(r.get("kind", "")) == kind:
			out.append(r)
	return out


func _errors() -> Array[String]:
	var out: Array[String] = []
	for r in _of_kind(Messages.ERROR):
		out.append(str(r["message"]))
	return out


func _place(e: ServerEntity, p: Vector2i) -> void:
	e.position = p
	e.path.clear()


func _walk_to(target: Vector2i, max_ticks: int = 300) -> void:
	_send(Messages.EXPLORE_MOVE, {"target": GridMath.vec_to_arr(target)})
	for _i in range(max_ticks):
		var e := server.get_entity("p1")
		if e.position == target or e.in_combat() or e.path.is_empty():
			break
		_tick()
	transport.pump()


## Plays p1's fight to its end: attack the nearest hostile in reach, else walk to it.
func _play_fight(max_ticks: int = 3000) -> void:
	for _i in range(max_ticks):
		var enc := server.get_encounter_for("p1")
		if enc == null:
			break
		var me := enc.current_actor()
		if me != null and me.id == "p1":
			var target: Combatant = null
			for h in enc.hostiles_of(me):
				if h.is_alive() and (target == null or GridMath.distance_tiles(me.position, h.position) < GridMath.distance_tiles(me.position, target.position)):
					target = h
			if target != null and GridMath.is_adjacent(me.position, target.position) and not me.action_used:
				_send(Messages.ATTACK, {"target": target.id, "attack_index": 0})
				continue
			var path: Array[Vector2i] = []
			if target != null and me.movement_remaining > 0:
				path = enc.walk_map.path_to(me.position, target.position, enc.occupied_cells(me.id))
			if not path.is_empty() and not GridMath.is_adjacent(me.position, target.position):
				path.resize(mini(path.size(), me.movement_remaining))
				_send(Messages.MOVE, {"path": GridMath.vec_list_to_arr(path)})
			else:
				_send(Messages.END_TURN)
			continue
		_tick()
	transport.pump()


# --- the fixture ------------------------------------------------------------------

func test_fixture_floor_is_a_valid_v2_floor() -> void:
	var f := _floor()
	var tables: Dictionary = ContentLoader.cache().get("loot_tables", {})
	assert_eq(f.validate(tables), [] as Array[String])
	assert_eq(f.static_blockers().size(), 3, "the closed door and two blocking props")


# --- landings ----------------------------------------------------------------------

func test_landing_assignment_is_deterministic_by_seed() -> void:
	var picks := {}
	for instance_seed in [1, 2, 3, 4, 5, 6, 7, 8]:
		var me := _setup(_floor(), null, instance_seed)
		var again := InstanceServer.new()
		var t2 := LocalTransport.new()
		again.configure(t2, _floor(), instance_seed)
		again.add_player(LocalTransport.PEER_ID, _sheet())
		assert_eq(again.landing_of("p1"), me.landing_id, "seed %d picks the same landing" % instance_seed)
		again.free()
		var landing := server.get_floor().get_landing(me.landing_id)
		assert_not_null(landing)
		assert_eq(me.position, landing.position, "the player stands on its landing")
		picks[me.landing_id] = true
	assert_eq(picks.size(), 2, "different seeds use both landings")


func test_floor_loaded_carries_landings_doors_props_and_light_without_secrets() -> void:
	var door := {"state": "locked", "dc": 12, "key_item": "key_bronze"}
	var me := _setup(_floor(door, false, "dim", {"p2": {"drops": [{"item": "key_bronze", "qty": 1}]}}))
	var loaded := _of_kind(Messages.FLOOR_LOADED)
	assert_eq(loaded.size(), 1)
	var r := loaded[0]
	assert_eq(Messages.validate_result(r), "")
	assert_eq(str(r["landing_id"]), me.landing_id)
	assert_eq((r["landings"] as Array).size(), 2)
	assert_eq(str(r["light"]), "dim")
	var doors: Array = r["doors"]
	assert_eq(doors.size(), 1)
	assert_eq(str(doors[0]["state"]), "locked")
	assert_eq(int(doors[0]["dc"]), 12)
	assert_true(doors[0].get("keyed", false) == true, "a keyed door says so")
	assert_eq(str(doors[0].get("key_item", "")), "key_bronze", "players see which key a door wants")
	assert_false(JSON.stringify(r).contains("drops"), "where the key hides never leaks")
	for p: Variant in (r["props"] as Array):
		assert_false((p as Dictionary).has("drops"), "props carry no drops")
	for p: Variant in ((r["floor"] as Dictionary)["props"] as Array):
		assert_false((p as Dictionary).has("drops"), "the floor copy's props carry no drops")
	assert_false(JSON.stringify(r).contains("loot_table"), "prop loot tables never leak")
	assert_false(JSON.stringify(r).contains("c_hidden"), "hidden chests never leak")
	var props: Array = r["props"]
	assert_eq(props.size(), 2)
	assert_false(props[0]["destroyed"] == true)
	var floor_dict: Dictionary = r["floor"]
	var client_floor := FloorData.from_dict(floor_dict)
	assert_eq(client_floor.get_door("d1").state, "locked", "the floor copy carries the current door state")


func test_descending_lands_the_party_on_the_next_floor_landing() -> void:
	var manifest := {"schema_version": 1, "id": "s", "display_name": "S", "floors": ["d2_floor", "d2_floor_b"]}
	var b := _floor_dict()
	b["id"] = "d2_floor_b"
	assert_true(server.configure_set(transport, manifest, SEED, {"d2_floor": _floor(), "d2_floor_b": FloorData.from_dict(b)}))
	server.add_player(LocalTransport.PEER_ID, _sheet())
	var me := server.get_entity("p1")
	server._mark_cleared("z1")
	_place(me, Vector2i(11, 2))
	_send(Messages.USE_STAIRS)
	assert_eq(server.get_floor().id, "d2_floor_b")
	var landing := server.get_floor().get_landing(me.landing_id)
	assert_not_null(landing)
	assert_eq(me.position, landing.position)
	assert_eq(str(_of_kind(Messages.FLOOR_LOADED).back()["landing_id"]), me.landing_id)


# --- doors -------------------------------------------------------------------------

func test_closed_door_blocks_pathing_and_opening_it_opens_the_path() -> void:
	var me := _setup(_floor())
	_place(me, Vector2i(5, 3))
	assert_false(server.explore_map().is_walkable(Vector2i(6, 2)), "a closed door is a wall")
	assert_false(server.explore_map().has_line_of_sight(Vector2i(5, 2), Vector2i(7, 2)), "and blocks sight")
	results.clear()
	_send(Messages.EXPLORE_MOVE, {"target": [8, 2]})
	assert_eq(_errors().size(), 1, "no path past a closed door")
	_send(Messages.EXPLORE_MOVE, {"target": [6, 2]})
	assert_true(_errors()[1].contains("closed"), _errors()[1])
	# Too far to open: not adjacent.
	_place(me, Vector2i(3, 2))
	_send(Messages.OPEN_DOOR, {"door_id": "d1"})
	assert_true(_errors()[2].contains("not next to"), _errors()[2])
	_place(me, Vector2i(5, 3))
	results.clear()
	_send(Messages.OPEN_DOOR, {"door_id": "d1"})
	assert_eq(_errors(), [] as Array[String])
	var changed := _of_kind(Messages.DOOR_CHANGED)
	assert_eq(changed.size(), 1)
	assert_eq(str(changed[0]["door_id"]), "d1")
	assert_eq(str(changed[0]["state"]), "open")
	assert_eq(str(changed[0]["by"]), "p1")
	assert_eq(Messages.validate_result(changed[0]), "")
	assert_eq(server.door_state("d1"), "open")
	assert_true(server.explore_map().is_walkable(Vector2i(6, 2)))
	_send(Messages.OPEN_DOOR, {"door_id": "d1"})
	assert_eq(_errors().size(), 1, "an open door cannot be opened again")
	_walk_to(Vector2i(8, 2))
	assert_true(me.position.x >= 7 or me.in_combat(), "walked through the doorway (%s)" % str(me.position))


func test_closing_a_door_needs_an_empty_doorway() -> void:
	var me := _setup(_floor({"state": "open"}))
	_place(me, Vector2i(6, 2))
	_send(Messages.CLOSE_DOOR, {"door_id": "d1"})
	assert_true(_errors()[0].contains("doorway"), str(_errors()))
	_place(me, Vector2i(5, 2))
	results.clear()
	_send(Messages.CLOSE_DOOR, {"door_id": "d1"})
	assert_eq(_errors(), [] as Array[String])
	assert_eq(server.door_state("d1"), "closed")
	assert_false(server.explore_map().is_walkable(Vector2i(6, 2)))


func test_an_encounter_map_copy_walls_closed_doors_and_blocking_props() -> void:
	_setup(_floor())
	var m := server._encounter_map()
	assert_false(m.is_walkable(Vector2i(6, 2)), "closed door")
	assert_false(m.is_walkable(Vector2i(5, 1)), "blocking crate")
	assert_true(m.is_walkable(Vector2i(5, 2)))
	assert_true(server.get_floor().walk_map.is_walkable(Vector2i(6, 2)), "the floor itself is never rewritten")


func test_unlock_door_with_its_key_uses_the_key_up() -> void:
	var sheet := _sheet()
	sheet.add_item("key_bronze", 1)
	var me := _setup(_key_floor(), sheet)
	_place(me, Vector2i(5, 2))
	_send(Messages.OPEN_DOOR, {"door_id": "d1"})
	assert_true(_errors()[0].contains("locked"))
	results.clear()
	_send(Messages.UNLOCK_DOOR, {"door_id": "d1", "method": "key"})
	assert_eq(_errors(), [] as Array[String])
	assert_eq(server.door_state("d1"), "closed", "unlocked, still closed")
	var changed := _of_kind(Messages.DOOR_CHANGED)[0]
	assert_eq(str(changed["method"]), "key")
	assert_eq(str(changed["consumed"]), "key_bronze", "DOOR_CHANGED names the key used up")
	assert_eq(Messages.validate_result(changed), "")
	assert_false(me.sheet.has_item("key_bronze"), "the key is used up")
	var state := _of_kind(Messages.CHARACTER_STATE).back() as Dictionary
	assert_eq(str((state["door_unlocked"] as Dictionary)["consumed"]), "key_bronze")
	assert_false(CharacterSheet.from_dict(state["sheet"]).has_item("key_bronze"), "the sheet sent lacks the key")
	_send(Messages.OPEN_DOOR, {"door_id": "d1"})
	assert_eq(server.door_state("d1"), "open")


func test_the_wrong_key_does_nothing() -> void:
	var sheet := _sheet()
	sheet.add_item("key_iron", 1)
	var me := _setup(_key_floor(), sheet)
	_place(me, Vector2i(5, 2))
	results.clear()
	_send(Messages.UNLOCK_DOOR, {"door_id": "d1", "method": "key"})
	assert_eq(_errors().size(), 1)
	assert_true(_errors()[0].contains("no key"), str(_errors()))
	assert_eq(server.door_state("d1"), "locked")
	assert_eq(_of_kind(Messages.DOOR_CHANGED).size(), 0)
	assert_true(me.sheet.has_item("key_iron"), "the wrong key is kept")
	# A keyless door ignores keys altogether.
	var plain := _sheet()
	plain.add_item("key_bronze", 1)
	server.free()
	server = InstanceServer.new()
	var me2 := _setup(_floor({"state": "locked", "dc": 12}), plain)
	_place(me2, Vector2i(5, 2))
	results.clear()
	_send(Messages.UNLOCK_DOOR, {"door_id": "d1", "method": "key"})
	assert_true(_errors()[0].contains("no key"), str(_errors()))
	assert_true(me2.sheet.has_item("key_bronze"))


func test_breaking_the_key_prop_gives_the_key_then_its_loot() -> void:
	var f := _floor({"state": "locked", "dc": 12, "key_item": "key_bronze"}, false, "",
		{"p1": {"drops": [{"item": "key_bronze", "qty": 1}]}})
	var me := _setup(f)
	_place(me, Vector2i(1, 4))
	results.clear()
	_send(Messages.INTERACT, {"prop_id": "p1"})
	assert_eq(_errors(), [] as Array[String])
	var loot := _of_kind(Messages.LOOT_GAINED)
	assert_eq(loot.size(), 1)
	assert_eq(Messages.validate_result(loot[0]), "")
	assert_eq(str(loot[0]["source"]), Messages.LOOT_SOURCE_PROP)
	var items: Array = loot[0]["items"]
	assert_eq(items[0], {"item": "key_bronze", "qty": 1}, "the drop comes first")
	var table: LootTable = ContentLoader.cache()["loot_tables"]["starter_gear"]
	var rolled: Array[Dictionary] = table.roll(Rng.new(SEED).fork(InstanceServer.LOOT_STREAM))
	var expected: Array[Dictionary] = [{"item": "key_bronze", "qty": 1}]
	for entry in rolled:
		LootTable.merge_into(expected, str(entry["item"]), DictUtil.to_int(entry["qty"]))
	assert_eq(items, expected, "then the loot table still rolls")
	assert_true(me.sheet.has_item("key_bronze"))
	# A prop with drops and no loot table still pays out.
	server.free()
	server = InstanceServer.new()
	var me2 := _setup(_key_floor())
	_place(me2, Vector2i(4, 2))
	results.clear()
	_send(Messages.INTERACT, {"prop_id": "p2"})
	var loot2 := _of_kind(Messages.LOOT_GAINED)
	assert_eq(loot2.size(), 1)
	assert_eq(loot2[0]["items"], [{"item": "key_bronze", "qty": 1}])
	assert_true(me2.sheet.has_item("key_bronze"))
	_place(me2, Vector2i(5, 2))
	_send(Messages.UNLOCK_DOOR, {"door_id": "d1", "method": "key"})
	assert_eq(server.door_state("d1"), "closed")
	assert_false(me2.sheet.has_item("key_bronze"))


func test_keys_are_lost_when_the_party_descends() -> void:
	var manifest := {"schema_version": 1, "id": "s", "display_name": "S", "floors": ["d2_floor", "d2_floor_b"]}
	var b := _floor_dict()
	b["id"] = "d2_floor_b"
	assert_true(server.configure_set(transport, manifest, SEED, {"d2_floor": _floor(), "d2_floor_b": FloorData.from_dict(b)}))
	var sheet := _sheet()
	sheet.add_item("key_silver", 1)
	server.add_player(LocalTransport.PEER_ID, sheet)
	var me := server.get_entity("p1")
	server._mark_cleared("z1")
	_place(me, Vector2i(11, 2))
	results.clear()
	_send(Messages.USE_STAIRS)
	assert_eq(server.get_floor().id, "d2_floor_b")
	assert_false(me.sheet.has_item("key_silver"), "a key belongs to its floor")
	var state := _of_kind(Messages.CHARACTER_STATE).back() as Dictionary
	assert_eq(DictUtil.to_string_array(state.get("keys_lost")), ["key_silver"] as Array[String])


func test_unlock_door_with_thieves_tools_rolls_against_the_dc() -> void:
	var sheet := _sheet("rogue")
	assert_true(sheet.has_item("thieves_tools"), "the rogue kit has thieves' tools")
	assert_eq(InstanceServer.tools_check_bonus(sheet), sheet.ability_modifier(Ability.Type.DEX) + sheet.proficiency_bonus(), "proficient")
	var me := _setup(_floor({"state": "locked", "dc": 15}), sheet)
	_place(me, Vector2i(7, 2) - Vector2i(2, 0))
	var tries := 0
	while server.door_state("d1") == "locked" and tries < 40:
		_send(Messages.UNLOCK_DOOR, {"door_id": "d1", "method": "tools"})
		tries += 1
	assert_eq(server.door_state("d1"), "closed", "picked within 40 tries")
	assert_eq(_errors(), [] as Array[String])
	var unlocked: Dictionary = {}
	var failed := 0
	for r in _of_kind(Messages.CHARACTER_STATE):
		if r.has("door_unlocked"):
			unlocked = r["door_unlocked"]
		if r.has("unlock_failed"):
			failed += 1
			assert_true(int(r["unlock_failed"]["total"]) < 15)
	assert_eq(failed, tries - 1)
	assert_true(int(unlocked["total"]) >= 15)
	assert_eq(str(_of_kind(Messages.DOOR_CHANGED)[0]["method"]), "tools")
	# A fighter has no tools.
	var fighter := _setup(_floor({"state": "locked", "dc": 15}), _sheet())
	_place(fighter, Vector2i(5, 2))
	results.clear()
	_send(Messages.UNLOCK_DOOR, {"door_id": "d1", "method": "tools"})
	assert_true(_errors()[0].contains("thieves' tools"), str(_errors()))


func test_unlock_door_by_spell_casts_knock_through_the_exploration_effect() -> void:
	var me := _setup(_floor({"state": "locked", "dc": 20}), _wizard(["knock"]))
	_place(me, Vector2i(3, 2))
	results.clear()
	_send(Messages.UNLOCK_DOOR, {"door_id": "d1", "method": "spell"})
	assert_eq(_errors(), [] as Array[String])
	var ooc := _of_kind(Messages.OUT_OF_COMBAT_EVENTS)
	assert_eq(ooc.size(), 1)
	var kinds: Array[String] = []
	for ev: Dictionary in (ooc[0]["events"] as Array):
		kinds.append(str(ev["kind"]))
	assert_has(kinds, "exploration_effect")
	assert_eq(server.door_state("d1"), "closed")
	var changed := _of_kind(Messages.DOOR_CHANGED)
	assert_eq(str(changed[0]["method"]), "spell")
	assert_eq(str(changed[0]["spell"]), "knock")
	assert_eq(me.sheet.slots_left(2), 2, "a 2nd-level slot was spent")
	# Knock on a door that is no longer locked: refused before the cast, no slot spent.
	results.clear()
	_send(Messages.CAST, {"spell": "knock", "target_kind": "door", "target_id": "d1"})
	assert_true(_errors()[0].contains("not locked"), str(_errors()))
	assert_eq(me.sheet.slots_left(2), 2)


func test_arcane_lock_locks_a_closed_door_and_raises_its_dc() -> void:
	var me := _setup(_floor({"dc": 10}), _wizard(["arcane_lock"]))
	_place(me, Vector2i(5, 2))
	_send(Messages.CAST, {"spell": "arcane_lock", "target_kind": "door", "target_id": "d1"})
	assert_eq(_errors(), [] as Array[String])
	assert_eq(server.door_state("d1"), "locked")
	assert_eq(server._door_dc(server.get_floor().get_door("d1")), 20)


func test_mage_hand_opens_a_closed_door_from_range() -> void:
	var me := _setup(_floor(), _wizard(["mage_hand"]))
	_place(me, Vector2i(2, 2))
	_send(Messages.CAST, {"spell": "mage_hand", "target_kind": "door", "target_id": "d1"})
	assert_eq(_errors(), [] as Array[String])
	assert_eq(server.door_state("d1"), "open")


# --- chests and reveals ------------------------------------------------------------

func test_knock_unlocks_a_locked_chest() -> void:
	var me := _setup(_floor(), _wizard(["knock"]))
	_place(me, Vector2i(1, 2))
	results.clear()
	_send(Messages.OPEN_CHEST, {"chest_id": "c_locked"})
	assert_true(_errors()[0].contains("locked"), str(_errors()))
	assert_true(server.is_chest_locked("c_locked"))
	results.clear()
	_send(Messages.CAST, {"spell": "knock", "target_kind": "chest", "target_id": "c_locked"})
	assert_eq(_errors(), [] as Array[String])
	assert_false(server.is_chest_locked("c_locked"))
	var revealed := _of_kind(Messages.CHEST_REVEALED)
	assert_eq(revealed.size(), 1, "the chest's new state is broadcast")
	assert_false(revealed[0]["chest"].has("locked"))
	_send(Messages.OPEN_CHEST, {"chest_id": "c_locked"})
	assert_eq(_errors(), [] as Array[String])
	assert_true(server.is_chest_opened("c_locked"))


func test_locate_object_reveals_hidden_chests() -> void:
	var me := _setup(_floor(), _wizard(["locate_object"]))
	_place(me, Vector2i(1, 1))
	assert_false(server.is_chest_revealed("c_hidden"))
	results.clear()
	_send(Messages.CAST, {"spell": "locate_object"})
	assert_eq(_errors(), [] as Array[String])
	assert_true(server.is_chest_revealed("c_hidden"))
	assert_eq(str(_of_kind(Messages.CHEST_REVEALED)[0]["chest"]["id"]), "c_hidden")
	var reveal := _of_kind(Messages.REVEAL)
	assert_eq(reveal.size(), 1)
	assert_eq(str(reveal[0]["reveal"]), "hidden_chests")
	assert_eq(reveal[0]["chests"], ["c_hidden"])
	assert_eq(Messages.validate_result(reveal[0]), "")


func test_teleportation_circle_returns_to_the_landing() -> void:
	var me := _setup(_floor({"state": "open"}), _wizard(["teleportation_circle"]))
	var home := me.position
	_place(me, Vector2i(5, 3))
	me.sheet.spell_slots_max = [4, 3, 3, 3, 2] as Array[int]
	me.sheet.spell_slots = [4, 3, 3, 3, 2] as Array[int]
	results.clear()
	_send(Messages.CAST, {"spell": "teleportation_circle", "target_kind": "landmark", "target_id": "arrival"})
	assert_eq(_errors(), [] as Array[String])
	assert_eq(me.position, home)
	var reveal := _of_kind(Messages.REVEAL)
	assert_eq(str(reveal[0]["reveal"]), "teleport")
	assert_eq(_of_kind(Messages.EXPLORE_STATE).size() >= 1, true)


func test_a_no_effect_spell_is_forwarded() -> void:
	var me := _setup(_floor(), _wizard(["comprehend_languages"]))
	results.clear()
	_send(Messages.CAST, {"spell": "comprehend_languages"})
	assert_eq(_errors(), [] as Array[String])
	var events: Array = _of_kind(Messages.OUT_OF_COMBAT_EVENTS)[0]["events"]
	var reason := ""
	for ev: Dictionary in events:
		if str(ev["kind"]) == "no_effect":
			reason = str(ev["reason"])
	assert_false(reason.is_empty(), "no_effect carries its reason")
	assert_eq(me.sheet.slots_left(1), 4, "free unless spend_slot")


# --- props -------------------------------------------------------------------------

func test_breaking_a_barrel_drops_its_loot() -> void:
	var me := _setup(_floor())
	_place(me, Vector2i(1, 1))
	_send(Messages.INTERACT, {"prop_id": "p1"})
	assert_true(_errors()[0].contains("not next to"), str(_errors()))
	_place(me, Vector2i(1, 4))
	var before := me.sheet.inventory.duplicate(true)
	results.clear()
	_send(Messages.INTERACT, {"prop_id": "p1"})
	assert_eq(_errors(), [] as Array[String])
	var destroyed := _of_kind(Messages.PROP_DESTROYED)
	assert_eq(destroyed.size(), 1)
	assert_eq(str(destroyed[0]["prop_id"]), "p1")
	assert_eq(str(destroyed[0]["by"]), "p1")
	var loot := _of_kind(Messages.LOOT_GAINED)
	assert_eq(loot.size(), 1)
	assert_eq(str(loot[0]["source"]), Messages.LOOT_SOURCE_PROP)
	assert_eq(str(loot[0]["prop_id"]), "p1")
	assert_eq(Messages.validate_result(loot[0]), "")
	assert_false((loot[0]["items"] as Array).is_empty(), "starter_gear always drops something")
	assert_ne(me.sheet.inventory, before, "the loot is in the inventory")
	assert_true(server.is_prop_destroyed("p1"))
	_send(Messages.INTERACT, {"prop_id": "p1"})
	assert_true(_errors()[0].contains("already broken"), str(_errors()))


func test_a_blocking_prop_is_an_obstacle_until_broken() -> void:
	var me := _setup(_floor())
	_place(me, Vector2i(4, 1))
	assert_true(server._blocked("p1").has(Vector2i(5, 1)))
	_send(Messages.EXPLORE_MOVE, {"target": [5, 1]})
	_tick(6)
	assert_eq(me.position, Vector2i(4, 1), "the crate stays in the way")
	_send(Messages.INTERACT, {"prop_id": "p2"})
	assert_eq(_errors(), [] as Array[String])
	assert_eq(_of_kind(Messages.LOOT_GAINED).size(), 0, "a prop without a table drops nothing")
	assert_false(server._blocked("p1").has(Vector2i(5, 1)))
	assert_true(server._encounter_map().is_walkable(Vector2i(5, 1)), "destroyed props stop blocking fights too")


func test_props_and_doors_are_exploration_only() -> void:
	var me := _setup(_floor())
	_place(me, Vector2i(8, 2))
	server._check_zone_entry(me)
	assert_true(me.in_combat())
	results.clear()
	_send(Messages.INTERACT, {"prop_id": "p1"})
	assert_true(_errors()[0].contains("in combat"), str(_errors()))


# --- respawns ----------------------------------------------------------------------

func test_a_pack_respawns_after_its_timer_but_never_while_a_player_is_inside() -> void:
	var me := _setup(_floor())
	_place(me, Vector2i(2, 5))
	_walk_to(Vector2i(3, 5))
	assert_true(me.in_combat(), "z2 triggered")
	_play_fight()
	assert_false(me.in_combat())
	assert_true(server.is_zone_cleared("z2"))
	_place(me, Vector2i(3, 4))
	_tick(60)  # 3 s > pack_seconds 1, but the player stands in the zone
	assert_true(server.is_zone_cleared("z2"), "no respawn under a player's feet")
	assert_eq(_of_kind(Messages.ZONE_RESPAWNED).size(), 0)
	_place(me, Vector2i(1, 1))
	_tick(2)
	transport.pump()
	var respawned := _of_kind(Messages.ZONE_RESPAWNED)
	assert_eq(respawned.size(), 1)
	assert_eq(str(respawned[0]["zone_id"]), "z2")
	assert_eq(Messages.validate_result(respawned[0]), "")
	assert_false(server.is_zone_cleared("z2"), "the zone is re-armed")
	assert_not_null(server.get_entity("z2_giant_rat_0_r1"))
	_walk_to(Vector2i(3, 5))
	assert_true(me.in_combat(), "the respawned pack fights again")


func test_boss_zones_use_the_boss_timer() -> void:
	_setup(_floor())
	var f := server.get_floor()
	assert_eq(server._respawn_seconds(f.get_zone("z1")), 3)
	assert_eq(server._respawn_seconds(f.get_zone("z2")), 1)
	server._mark_cleared("z1")
	_tick(40)
	assert_true(server.is_zone_cleared("z1"), "2 s < boss_seconds 3")
	_tick(30)
	assert_false(server.is_zone_cleared("z1"), "back after 3 s")


func test_v1_floors_never_respawn() -> void:
	var d := _floor_dict()
	d["schema_version"] = 1
	_setup(FloorData.from_dict(d))
	server._mark_cleared("z2")
	_tick(100)
	assert_true(server.is_zone_cleared("z2"))


# --- light and control ---------------------------------------------------------------

func test_a_fight_starts_at_the_floor_light_level() -> void:
	var me := _setup(_floor({}, false, "dim"))
	assert_eq(server.floor_light(), "dim")
	assert_eq(me.light_level, "dim")
	_place(me, Vector2i(8, 2))
	server._check_zone_entry(me)
	var enc := server.get_encounter_for("p1")
	assert_not_null(enc)
	assert_eq(enc.light, "dim")


func test_light_spell_out_of_combat_lights_the_player() -> void:
	var me := _setup(_floor({}, false, "dark"), _wizard(["light"]))
	results.clear()
	_send(Messages.CAST, {"spell": "light"})
	assert_eq(_errors(), [] as Array[String])
	assert_eq(me.light_level, "bright")
	var states := _of_kind(Messages.CHARACTER_STATE)
	assert_eq(str(states.back()["light_level"]), "bright")


func test_control_intent_reaches_the_encounter() -> void:
	var me := _setup(_floor({"state": "open"}, true))
	_place(me, Vector2i(8, 2))
	server._check_zone_entry(me)
	var enc := server.get_encounter_for("p1")
	assert_not_null(enc)
	for _i in range(400):
		var cur := enc.current_actor()
		if cur != null and cur.id == "p1":
			break
		_tick()
	assert_eq(enc.current_actor().id, "p1")
	var rat := enc.get_combatant("z1_giant_rat_0")
	results.clear()
	_send(Messages.CONTROL, {"target": rat.id, "orders": [{"type": "end_turn"}]})
	assert_eq(_errors().size(), 1, "not dominated yet")
	enc._apply_condition(rat, Conditions.DOMINATED, "p1", {"type": Conditions.DURATION_ENCOUNTER})
	assert_eq(rat.controlled_by, "p1")
	results.clear()
	_send(Messages.CONTROL, {"target": rat.id, "orders": [{"type": "attack", "target": "z1_giant_rat_1", "attack_index": 0}]})
	assert_eq(_errors(), [] as Array[String])
	var control: Dictionary = {}
	for r in _of_kind(Messages.ENCOUNTER_EVENTS):
		for ev: Dictionary in (r["events"] as Array):
			if str(ev["kind"]) == "control":
				control = ev
	assert_eq(str(control.get("target", "")), rat.id)
	assert_eq(int(control.get("orders", 0)), 1)

extends TestCase
## Smoke test on the real floor_001: a fighter routes (on the floor data,
## past no locked door or blocking prop) to the crate or barrel that hides a
## door's key, breaks it, carries the key to its door, unlocks it (the key is
## used up) and opens it.

const DT := 1.0 / 20.0
const SEED := 777

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


func _send(type: String, fields: Dictionary = {}) -> void:
	var f := fields.duplicate()
	f["actor"] = "p1"
	transport.send_intent(Messages.make_intent(type, f))
	server._physics_process(DT)
	transport.pump()


func _of_kind(kind: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for r in results:
		if str(r.get("kind", "")) == kind:
			out.append(r)
	return out


func _fighter() -> CharacterSheet:
	var scores := AbilityScores.new()
	scores.set_all([16, 12, 14, 10, 12, 8] as Array[int])
	var skills: Array[int] = []
	return CharacterBuilder.create("Tess", ContentLoader.load_classes()["fighter"],
			ContentLoader.load_ancestries()["human"], scores, skills)


## Floor-data route blockers: blocking props and locked doors.
func _blocked(f: FloorData) -> Dictionary:
	var blocked := f.prop_blockers()
	for d in f.doors:
		if d.is_locked():
			blocked[d.position] = true
	return blocked


func test_the_fighter_finds_a_key_and_opens_its_door() -> void:
	var f := FloorFile.load(FloorFile.floor_path("floor_001"))
	assert_not_null(f)
	if f == null:
		return
	var door: DoorData = null
	for d in f.doors:
		if not d.key_item.is_empty():
			door = d
			break
	assert_not_null(door, "floor_001 has a key door")
	if door == null:
		return
	var holder: PropData = null
	for p in f.props:
		if p.drops_item(door.key_item):
			holder = p
	assert_not_null(holder, "a prop holds %s" % door.key_item)
	server.configure(transport, f, SEED)
	server.add_player(LocalTransport.PEER_ID, _fighter())
	transport.pump()
	var me := server.get_entity("p1")
	var loaded := _of_kind(Messages.FLOOR_LOADED)[0]
	var wire_door: Dictionary = {}
	for d: Variant in (loaded["doors"] as Array):
		if str((d as Dictionary)["id"]) == door.id:
			wire_door = d
	assert_eq(str(wire_door.get("key_item", "")), door.key_item, "the client learns which key the door wants")
	assert_false(JSON.stringify(loaded).contains("\"drops\""), "but not where it hides")
	# Route on the floor data from the landing to the key prop (it blocks, so
	# the path ends next to it).
	var blocked := _blocked(f)
	var to_prop := f.walk_map.path_to(me.position, holder.position, blocked)
	assert_false(to_prop.is_empty(), "a route reaches the key prop from landing %s" % me.landing_id)
	if to_prop.is_empty():
		return
	me.position = to_prop[to_prop.size() - 1]
	me.path.clear()
	results.clear()
	_send(Messages.INTERACT, {"prop_id": holder.id})
	assert_eq(_of_kind(Messages.ERROR).size(), 0, str(_of_kind(Messages.ERROR)))
	var loot := _of_kind(Messages.LOOT_GAINED)
	assert_eq(loot.size(), 1)
	assert_eq((loot[0]["items"] as Array)[0], {"item": door.key_item, "qty": 1}, "the key comes first")
	assert_true(me.sheet.has_item(door.key_item))
	# On to the door: its landings' side is reachable with the door still locked.
	var to_door := f.walk_map.path_to(me.position, door.position, _blocked(f))
	assert_false(to_door.is_empty(), "a route leads from the key prop to its door")
	if to_door.is_empty():
		return
	me.position = to_door[to_door.size() - 1]
	me.path.clear()
	results.clear()
	_send(Messages.UNLOCK_DOOR, {"door_id": door.id, "method": "key"})
	assert_eq(_of_kind(Messages.ERROR).size(), 0, str(_of_kind(Messages.ERROR)))
	assert_eq(server.door_state(door.id), DoorData.STATE_CLOSED)
	assert_eq(str(_of_kind(Messages.DOOR_CHANGED)[0]["consumed"]), door.key_item)
	assert_false(me.sheet.has_item(door.key_item), "the key is used up")
	_send(Messages.OPEN_DOOR, {"door_id": door.id})
	assert_eq(server.door_state(door.id), DoorData.STATE_OPEN)
	assert_true(server.explore_map().is_walkable(door.position), "the way into the vault is open")

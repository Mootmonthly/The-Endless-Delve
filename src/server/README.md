# src/server — authoritative instance server

One headless Godot process = one dungeon instance (5 floors, ~100 players).
The server owns every piece of game state; clients send intents through a
`Transport` (src/shared) and render the results it sends back. All dice are
rolled here, by the pure rules engine in `src/core/`, from Rngs forked off the
instance seed. Offline mode runs the same code in-process over a
`LocalTransport`.

## Files
| File | Class | Role |
|---|---|---|
| `instance_server.gd` | `InstanceServer` (Node) | the instance's simulation, one floor at a time (single floor or a five-floor set): 20 Hz tick, exploration, encounter triggers, intent handling, XP, level-up offers, items, chests, loot, stairs |
| `server_entity.gd` | `ServerEntity` | a player or monster on the floor (position, walking path, sheet, combat link) |
| `encounter_session.gd` | `EncounterSession` | an active core `Encounter` plus its zone, members and monster-turn schedule |

## Using it (offline)
```gdscript
var transport := LocalTransport.new()
transport.result_received.connect(_on_result)      # before the first tick
var server := InstanceServer.new()
add_child(server)                                  # _physics_process drives the ticks
server.configure_set(transport, FloorFile.load_set("res://floors/set_01.json"), seed)
# or a single floor: server.configure(transport, FloorFile.load("res://floors/floor_001.json"), seed)
var my_id := server.add_player(transport.local_peer_id(), sheet)   # "p1"
transport.send_intent(Messages.make_intent(Messages.EXPLORE_MOVE, {"actor": my_id, "target": [x, y]}))
```
The server calls `transport.pump()` at the start of every tick; results sent
outside a pump (exploration, monster turns, `add_player`) arrive on the next one.

## Tick (20 Hz, `_physics_process` accumulates delta; `run_tick()` runs one)
1. Pump the transport: intents are validated and handled immediately.
2. Due monster turns: `MonsterBrain.decide` + `Encounter.submit`, one
   ENCOUNTER_EVENTS result per monster turn, on the tick after its
   `turn_started` (`monster_turn_delay_ticks`, default 1).
3. Exploration: each walking entity steps one tile every `EXPLORE_STEP_TICKS`
   (3) ticks along a server-computed path (re-pathing around blockers);
   EXPLORE_STATE is broadcast when anything moved; then a player inside an
   uncleared zone starts an encounter (everyone inside the rect joins) and
   anyone entering an active encounter's region joins it mid-fight.

## Rules the server applies
- Combat intents must name the sender's own entity and go to its encounter;
  exploration intents are refused in combat and combat intents outside it.
  Rejections go back as ERROR to the sender only.
- `use_stairs`: on the stairs tile, no encounter active on the floor ->
  FLOOR_CLEARED broadcast. In a set with a next floor the whole instance then
  descends: old monsters dropped, next floor's monsters spawned, cleared zones
  reset, players keep their sheets and get FLOOR_LOADED (extras `set_id`,
  `set_name`, `floor_index`, `floor_count`), CHARACTER_STATE, EXPLORE_STATE.
  On the set's last floor: `Rest.long_rest` for every living player
  (CHARACTER_STATE with `long_rest: true`), then SET_CLEARED once; every
  later intent is refused. `short_rest`: on the stairs tile, out of combat ->
  `Rest.short_rest`, CHARACTER_STATE (with `healed`) to the sender.
- Death saves before wipe (core rule): a fight lasts while each of two teams
  has a member who is conscious or still dying, so downed players roll their
  death saves while the monsters keep attacking them.
- Encounter end: players won -> zone cleared, surviving players at 0 hp
  (stable or dying) go to 1 hp, and the XP of the monsters that died is split
  evenly (integer division) among the encounter's living players
  (CHARACTER_STATE with `xp_gained`, `levels_pending`). Each dead monster's
  `loot_table` is rolled; the merged drops go to the first living player of
  the encounter (M2: one player) as LOOT_GAINED `{entity_id, items, source:
  "monster"}` right before that player's CHARACTER_STATE. Otherwise the fallen
  (all stable or dead by then) die and the zone stays live. Dead monsters are
  removed, survivors explore again, players get CHARACTER_STATE, and
  GAME_OVER is broadcast once no living player remains.
- Floor-clear bonus: `use_stairs` gives `FLOOR_CLEAR_XP` (100, not split) to
  every living player, carried as `xp_gained` / `floor_clear_xp` /
  `levels_pending` on the CHARACTER_STATE the floor change sends anyway (next
  floor, long rest on the set's last floor, or a lone one on a single floor).
- Level-up (never automatic): whenever a player out of combat has
  `sheet.pending_levels() > 0` after an XP award (also on `add_player` and
  when its encounter ends), it gets LEVEL_UP_AVAILABLE `{entity_id, choices:
  LevelUp.choices(sheet)}` for the next level only. The `level_up {choices}`
  intent (out of combat; also accepted after SET_CLEARED) runs
  `LevelUp.apply` (HP rolls from the LEVEL_STREAM Rng): success ->
  CHARACTER_STATE with `leveled_to` and `levels_pending`, then the next offer
  if levels remain; invalid choices or nothing pending -> ERROR, sheet unchanged.
- Items (out of combat): `equip {item, slot}` / `unequip {slot}`
  (`CharacterSheet.equip` / `unequip`; CHARACTER_STATE extras `equipped` /
  `unequipped` `{item, slot}`), `use_item {item}` (same checks as the core,
  self only, no action cost; extras `item_used`, `healed` or `temp_hp`),
  `drop_item {item, qty}` (gone for good in M2; extra `dropped {item, qty}`).
  In combat `use_item` goes to the Encounter like `cast`, `use_feature` and
  `attack` (with `bonus`); equip / unequip / drop are refused there.
- Chests (state per floor visit): FLOOR_LOADED carries `chests: [{id,
  position, hidden, opened}]` with only the chests a client may know about
  (its `floor.chests` is replaced by the same list: no hidden chests, no loot
  tables). A hidden chest is revealed when a player stands within 1 tile
  (CHEST_REVEALED `{chest}` broadcast once). `open_chest {chest_id}` needs
  the player on or next to the chest, the chest unopened (an unrevealed
  hidden chest answers like an unknown id): CHEST_OPENED `{chest_id,
  entity_id}` broadcast, LOOT_GAINED `{entity_id, items, source: "chest",
  chest_id}` and CHARACTER_STATE to the opener.
- Encounter Rng: `floor_rng.fork(zone_index + attempt * 1024)`, a fresh Rng
  (floor_rng is the root on the first floor, `root.fork(FLOOR_STREAM + i)`
  below), so every fight is replayable from `enc.rng_seed`,
  `setup_snapshot()` and `intent_log`. Loot (chests and drops) rolls from
  `floor_rng.fork(LOOT_STREAM)`, out-of-combat item use from
  `root.fork(ITEM_STREAM)`, level-up HP rolls from `root.fork(LEVEL_STREAM)`.

## Result order a client sees
- Chest open: CHEST_OPENED (broadcast), LOOT_GAINED, CHARACTER_STATE.
- Encounter won: ENCOUNTER_EVENTS (ending with `encounter_ended`), then per
  player [LOOT_GAINED (looter only)], CHARACTER_STATE (`xp_gained`), then
  EXPLORE_STATE, then LEVEL_UP_AVAILABLE for players with pending levels.
- `use_stairs`: FLOOR_CLEARED, then next floor: FLOOR_LOADED, CHARACTER_STATE
  (with the bonus), EXPLORE_STATE, [CHEST_REVEALED], [ENCOUNTER_EVENTS if the
  arrival is in a zone]; last floor: CHARACTER_STATE (`long_rest` + bonus),
  SET_CLEARED; single floor: CHARACTER_STATE (bonus). Then LEVEL_UP_AVAILABLE.
- Level-up: LEVEL_UP_AVAILABLE -> `level_up` intent -> CHARACTER_STATE
  (`leveled_to`, `levels_pending`) [-> LEVEL_UP_AVAILABLE for the next level],
  or ERROR.

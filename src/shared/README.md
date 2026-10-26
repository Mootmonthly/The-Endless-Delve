# src/shared — messages and transports

Code shared by `src/server/` and `src/client/`; depends only on `src/core/`.

- `messages.gd` (`Messages`): protocol version, intent types and result
  kinds, `make_intent` / `make_result` builders and structural validators.
  Messages are plain JSON-safe Dictionaries; positions are `[x, y]` arrays.
  The full field list is the comment at the top of `messages.gd`. Combat
  intents (`ENCOUNTER_INTENTS`): move, attack (`bonus`?), cast, use_feature,
  use_item, dash, dodge, disengage, end_turn. Exploration intents
  (`EXPLORE_INTENTS`): explore_move, use_stairs, short_rest, equip, unequip,
  use_item, open_chest, drop_item, level_up. `use_item` is in both lists
  (`is_dual_intent`): the server routes it by whether the actor is in combat.
  Results: encounter_events, explore_state, error, floor_loaded (+ `chests`),
  character_state, game_over, floor_cleared, set_cleared, loot_gained,
  chest_opened, chest_revealed, level_up_available.
- `transport.gd` (`Transport`): the interface server and client code talk
  through (`send_intent`, `send_result`, `broadcast_result`, signals
  `intent_received` / `result_received`).
- `local_transport.gd` (`LocalTransport`): offline, in-process transport.
  Messages are deep-copied into one FIFO queue and delivered by `pump()`,
  which the offline server calls once per tick.
- `floor_file.gd` (`FloorFile`): loads `floors/floor_NNN.json` into a core
  `FloorData`; `load_set` / `set_problems` / `set_floor_ids` read a five-floor
  set manifest (`floors/set_NN.json`); `floor_path(id)` = `res://floors/<id>.json`.

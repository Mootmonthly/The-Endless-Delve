# src/shared — messages and transports

Code shared by `src/server/` and `src/client/`; depends only on `src/core/`.

- `messages.gd` (`Messages`): protocol version, intent types and result
  kinds, `make_intent` / `make_result` builders and structural validators.
  Messages are plain JSON-safe Dictionaries; positions are `[x, y]` arrays.
  The full field list is the comment at the top of `messages.gd`. Combat
  intents (`ENCOUNTER_INTENTS`): move, stand, attack (`bonus`, `reckless`,
  `smite` slot level, `stun`, `technique`, `retarget`), cast (`slot_level`
  0..9, `point`, `sculpt`, `metamagic`, `twin_target`), use_feature (`mode`,
  `slot_level`, `allocations` {id: hp}, `frenzy`, `amount`), use_item
  (`bonus`), dash, dodge, disengage, end_turn. Validation is structural
  (types, ranges, the technique names); the Encounter judges the rules.
  `short_rest` takes `recover_slots` (true = the server picks, or an array of
  slot levels) for Arcane / Natural Recovery; `level_up` choices carry the
  progression answers (subclass, fighting_style, expertise, skills,
  invocations, metamagic, feature_options) that `LevelUp.apply` checks. Exploration intents
  (`EXPLORE_INTENTS`): explore_move, use_stairs, short_rest, equip, unequip,
  use_item, cast, open_chest, drop_item, level_up, reaction_policy,
  dismiss_companion (`companion_id`). `use_item`, `cast` and `reaction_policy`
  are in both lists (`is_dual_intent`): the server routes them by whether the
  actor is in combat (`cast` also takes `targets` [id] and `form`).
  Results: encounter_events, explore_state, error, floor_loaded (+ `chests`),
  character_state, game_over, floor_cleared, set_cleared, loot_gained,
  chest_opened, chest_revealed, level_up_available, out_of_combat_events
  (`{entity_id, spell, events: [{kind, ...}], slot_level, result}`).
- `transport.gd` (`Transport`): the interface server and client code talk
  through (`send_intent`, `send_result`, `broadcast_result`, signals
  `intent_received` / `result_received`).
- `local_transport.gd` (`LocalTransport`): offline, in-process transport.
  Messages are deep-copied into one FIFO queue and delivered by `pump()`,
  which the offline server calls once per tick.
- `floor_file.gd` (`FloorFile`): loads `floors/floor_NNN.json` into a core
  `FloorData`; `load_set` / `set_problems` / `set_floor_ids` read a five-floor
  set manifest (`floors/set_NN.json`); `floor_path(id)` = `res://floors/<id>.json`.

# src/client — presentation layer (stub)

Rendering, input, UI, camera, audio and animation for the 2D top-down view.
The client is presentation only: it turns player input into intents for the
server and displays the results the server broadcasts.
It must never roll dice or resolve rules on its own authority; anything it
predicts locally is cosmetic and is overwritten by server state.
Character creator, HUD, combat log and safe-zone UI will live here.

## M1 contents
| Where | Class | Role |
|---|---|---|
| `src/client/client_state.gd` | `ClientState` | pure view-model: folds server results into mode, entities, initiative, the player's movement/action; builds intents from clicks |
| `src/client/character_draft.gd` | `CharacterDraft` | creator rules: wave-1 class, ancestry, standard array (unique values), skill picks, preview |
| `scenes/ui/character_creator.*` | `CharacterCreator` | creation screen (UI built in code), emits `character_created(sheet)` |
| `scenes/game/game_scene.*` | `GameScene` | offline play: LocalTransport + InstanceServer child, FloorView, ReachOverlay, EntityLayer, Camera2D, Hud, input |
| `scenes/main.*` | `Main` | boot: creator -> game -> (run over) creator |

Tests: `tests/client/` (ClientState, CharacterDraft, scene loading, and an offline
smoke run of ClientState against a real InstanceServer ticked by hand).

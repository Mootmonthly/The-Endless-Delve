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
| `src/client/client_state.gd` | `ClientState` | pure view-model: folds server results into mode, entities, initiative, the player's movement/action, set position (floor number/name, stairs label), level/XP; builds intents from clicks |
| `src/client/character_draft.gd` | `CharacterDraft` | creator rules: all twelve SRD classes, ancestry, standard array (unique values), skill picks, preview (AC with armor, attacks with ranges, spells, slots, features, kit) |
| `scenes/ui/character_creator.*` | `CharacterCreator` | creation screen (UI built in code), emits `character_created(sheet)` |
| `scenes/game/game_scene.*` | `GameScene` | offline play of `floors/set_01.json` (else `floor_001` alone): LocalTransport + InstanceServer child, FloorView (rebuilt on every FLOOR_LOADED), ReachOverlay, EntityLayer, Camera2D, Hud, input |
| `scenes/main.*` | `Main` | boot: settings, creator -> game -> (run over) creator; Escape opens the SettingsMenu |

## M2 additions (items, spells, level-ups)
| Where | Class | Role |
|---|---|---|
| `src/client/client_state.gd` | `ClientState` | also: chests (FLOOR_LOADED `chests`, CHEST_OPENED / CHEST_REVEALED), loot log, level-up offers, combat effects as status tags, bonus action, spell / feature / item intents, targeting mode, selected attack and range tiles, inventory rows, AC breakdown, slots and resources text |
| `src/client/level_up_draft.gd` | `LevelUpDraft` | level-up rules for the screen: HP choice, ASI, spells to learn (unsupported greyed), prepared picks; `first_valid()` for bots |
| `src/client/entity_icons.gd` | `EntityIcons` | icon atlas map (`assets/icons/entity_icons.json`): class / monster / item-kind / chest columns |
| `scenes/ui/level_up_screen.*` | `LevelUpScreen` | modal level-up screen (opened on LEVEL_UP_AVAILABLE out of combat; HUD button reopens it) |
| `scenes/game/hud.gd` | `Hud` | action bar with attack picker, Spells / Features popups, inventory panel (Tab), slots / resources, status tags, level-up button |

Input goes through the InputMap actions of `project.godot` (rebindable in Settings).

Tests: `tests/client/` (ClientState, CharacterDraft, LevelUpDraft, HUD and level-up
screen off-tree, scene loading, GameSettings, and an offline smoke run of
ClientState against a real InstanceServer ticked by hand: potion, chest, level-up).

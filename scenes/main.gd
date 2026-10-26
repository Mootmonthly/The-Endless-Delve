class_name Main
extends Node
## Boot scene for The Endless Delve: prints the version, loads and applies the
## player's GameSettings (user://settings.cfg), shows the CharacterCreator, and
## on confirm starts the GameScene in offline mode (InstanceServer in-process
## over a LocalTransport). When a run ends and the player asks for a new
## character, the creator comes back.
##
## The SettingsMenu overlay is a child kept after the active scene, so it sees
## unhandled input first. The open_settings action (Escape) opens it as a
## pause menu over the game (Resume / Settings / Quit to character creator;
## the offline server keeps ticking; "Reactions" closes the menu and opens the
## game HUD's Reactions panel) or straight to Settings over the creator, which
## also has a Settings button.

const CREATOR_SCENE := "res://scenes/ui/character_creator.tscn"
const GAME_SCENE := "res://scenes/game/game_scene.tscn"
const SETTINGS_MENU_SCENE := "res://scenes/ui/settings_menu.tscn"

## Where settings are read and saved; set before _ready() to use another file.
var settings_path: String = GameSettings.DEFAULT_PATH
var settings: GameSettings = null

var _current: Node = null
var _menu: SettingsMenu = null


func _ready() -> void:
	var project_name: String = str(ProjectSettings.get_setting("application/config/name", "The Endless Delve"))
	var godot_version: String = str(Engine.get_version_info().get("string", "unknown"))
	print("%s booted on Godot %s" % [project_name, godot_version])
	load_settings()
	show_creator()


## Loads settings_path (defaults if missing) and applies audio, input and video.
func load_settings() -> void:
	settings = GameSettings.load_from(settings_path)
	settings.apply()
	if _menu != null:
		_menu.setup(settings)


func _on_menu_closed() -> void:
	if _current is GameScene:
		(_current as GameScene).set_simulation_paused(false)


func show_creator() -> void:
	get_tree().paused = false
	var packed: PackedScene = load(CREATOR_SCENE)
	var creator := packed.instantiate() as CharacterCreator
	creator.character_created.connect(_on_character_created)
	creator.settings_requested.connect(open_settings_menu)
	_swap(creator)


func start_game(sheet: CharacterSheet) -> void:
	var packed: PackedScene = load(GAME_SCENE)
	var game := packed.instantiate() as GameScene
	game.setup(sheet)
	game.exit_requested.connect(show_creator)
	_swap(game)


## Escape over the game: the pause page. Over anything else: Settings directly.
func open_pause_menu() -> void:
	var menu := _ensure_menu()
	if _current is GameScene:
		var game := _current as GameScene
		var paused := game.set_simulation_paused(true)
		menu.open_pause(true, paused, ClientState.reaction_policy_supported())
	else:
		menu.open_settings(false)


func open_settings_menu() -> void:
	_ensure_menu().open_settings(false)


func is_menu_open() -> bool:
	return _menu != null and _menu.is_open()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("open_settings") and not is_menu_open():
		open_pause_menu()
		get_viewport().set_input_as_handled()


func _ensure_menu() -> SettingsMenu:
	if _menu == null:
		var packed: PackedScene = load(SETTINGS_MENU_SCENE)
		_menu = packed.instantiate() as SettingsMenu
		_menu.setup(settings if settings != null else GameSettings.new(settings_path))
		_menu.quit_requested.connect(show_creator)
		_menu.closed.connect(_on_menu_closed)
		_menu.reactions_requested.connect(_on_reactions_requested)
		add_child(_menu)
	return _menu


func _on_reactions_requested() -> void:
	if _current is GameScene:
		var game := _current as GameScene
		if game.hud != null:
			game.hud.open_reactions()


func _on_character_created(sheet: CharacterSheet) -> void:
	start_game(sheet)


func _swap(next: Node) -> void:
	if _current != null:
		remove_child(_current)
		_current.queue_free()
	_current = next
	add_child(next)
	# The active scene stays first so the overlay gets unhandled input before it.
	move_child(next, 0)

class_name Main
extends Node
## Boot scene for The Endless Delve: prints the version, shows the
## CharacterCreator, and on confirm starts the GameScene in offline mode
## (InstanceServer in-process over a LocalTransport). When a run ends and the
## player asks for a new character, the creator comes back.

const CREATOR_SCENE := "res://scenes/ui/character_creator.tscn"
const GAME_SCENE := "res://scenes/game/game_scene.tscn"

var _current: Node = null


func _ready() -> void:
	var project_name: String = str(ProjectSettings.get_setting("application/config/name", "The Endless Delve"))
	var godot_version: String = str(Engine.get_version_info().get("string", "unknown"))
	print("%s booted on Godot %s" % [project_name, godot_version])
	show_creator()


func show_creator() -> void:
	var packed: PackedScene = load(CREATOR_SCENE)
	var creator := packed.instantiate() as CharacterCreator
	creator.character_created.connect(_on_character_created)
	_swap(creator)


func start_game(sheet: CharacterSheet) -> void:
	var packed: PackedScene = load(GAME_SCENE)
	var game := packed.instantiate() as GameScene
	game.setup(sheet)
	game.exit_requested.connect(show_creator)
	_swap(game)


func _on_character_created(sheet: CharacterSheet) -> void:
	start_game(sheet)


func _swap(next: Node) -> void:
	if _current != null:
		remove_child(_current)
		_current.queue_free()
	_current = next
	add_child(next)

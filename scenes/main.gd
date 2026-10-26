extends Node2D
## Minimal boot scene for The Endless Delve.
##
## Prints the project name and the running Godot version, nothing else.
## Real client/server bootstrapping will replace this in a later milestone.


func _ready() -> void:
	var project_name: String = str(ProjectSettings.get_setting("application/config/name", "The Endless Delve"))
	var godot_version: String = str(Engine.get_version_info().get("string", "unknown"))
	print("%s booted on Godot %s" % [project_name, godot_version])

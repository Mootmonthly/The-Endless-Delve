extends TestCase
## Every client scene loads as a PackedScene that can be instantiated
## (nothing is instantiated here: the runner has no scene tree for tests).

const SCENES: Array[String] = [
	"res://scenes/main.tscn",
	"res://scenes/ui/character_creator.tscn",
	"res://scenes/game/game_scene.tscn",
]


func test_client_scenes_load() -> void:
	for path in SCENES:
		assert_true(ResourceLoader.exists(path), "%s exists" % path)
		var res: Resource = load(path)
		assert_true(res is PackedScene, "%s is a PackedScene" % path)
		var packed := res as PackedScene
		if packed != null:
			assert_true(packed.can_instantiate(), "%s can_instantiate" % path)


func test_client_scripts_compile() -> void:
	for path: String in [
		"res://scenes/main.gd",
		"res://scenes/ui/character_creator.gd",
		"res://scenes/game/game_scene.gd",
		"res://scenes/game/hud.gd",
		"res://scenes/game/entity_layer.gd",
		"res://scenes/game/reach_overlay.gd",
		"res://src/client/client_state.gd",
		"res://src/client/character_draft.gd",
	]:
		var script := load(path) as GDScript
		assert_not_null(script, path)
		if script != null:
			assert_true(script.can_instantiate(), "%s compiles" % path)

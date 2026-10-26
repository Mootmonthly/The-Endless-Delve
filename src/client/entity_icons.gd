class_name EntityIcons
extends RefCounted
## The entity icon atlas (res://assets/icons/entity_icons.json): one row of
## 32 px icons, id -> column. Classes (by class_id), monsters (by
## monster_id), item kinds (by ItemDefinition.kind, with aliases such as
## "consumable" -> "potion") and the chest_closed / chest_open tiles.
## Loaded once and shared; column_for() is -1 for an unknown id.

const MAP_PATH := "res://assets/icons/entity_icons.json"
const CHEST_CLOSED := "chest_closed"
const CHEST_OPEN := "chest_open"

static var _shared: EntityIcons = null

var tileset_path: String = "res://assets/icons/entity_icons.tres"
var texture_path: String = "res://assets/icons/entity_icons.png"
var source_id: int = 0
var tile_size: int = 32
var icons: Dictionary[String, int] = {}
var aliases: Dictionary[String, String] = {}

var _texture: Texture2D = null
var _atlas_cache: Dictionary[int, AtlasTexture] = {}


## The icon map from MAP_PATH (cached).
static func shared() -> EntityIcons:
	if _shared == null:
		_shared = EntityIcons.from_dict(ContentLoader.load_json(MAP_PATH))
	return _shared


static func from_dict(d: Dictionary) -> EntityIcons:
	var m := EntityIcons.new()
	m.tileset_path = str(d.get("tileset", m.tileset_path))
	m.texture_path = str(d.get("texture", m.texture_path))
	m.source_id = DictUtil.to_int(d.get("atlas_source_id", 0), 0)
	m.tile_size = DictUtil.to_int(d.get("tile_size", 32), 32)
	var raw_icons: Variant = d.get("icons", {})
	if typeof(raw_icons) == TYPE_DICTIONARY:
		var icons_d: Dictionary = raw_icons
		for key: Variant in icons_d.keys():
			m.icons[str(key)] = DictUtil.to_int(icons_d[key], -1)
	var raw_aliases: Variant = d.get("aliases", {})
	if typeof(raw_aliases) == TYPE_DICTIONARY:
		var aliases_d: Dictionary = raw_aliases
		for key: Variant in aliases_d.keys():
			m.aliases[str(key)] = str(aliases_d[key])
	return m


## Atlas column for an id (aliases followed), or -1.
func column_for(id: String) -> int:
	if icons.has(id):
		return icons[id]
	if aliases.has(id) and icons.has(aliases[id]):
		return icons[aliases[id]]
	return -1


## Column for an entity: players by "class_id", monsters by "monster_id"; -1 when unknown.
func column_for_entity(e: Dictionary) -> int:
	if str(e.get("kind", "")) == ClientState.KIND_PLAYER:
		return column_for(str(e.get("class_id", "")))
	return column_for(str(e.get("monster_id", "")))


## Column for an item: by its definition's kind (e.g. "weapon", "consumable").
func column_for_item(def: ItemDefinition) -> int:
	if def == null:
		return column_for("misc")
	var col := column_for(def.kind)
	return col if col >= 0 else column_for("misc")


func tile_set() -> TileSet:
	return load(tileset_path) as TileSet


func texture() -> Texture2D:
	if _texture == null:
		_texture = load(texture_path) as Texture2D
	return _texture


## A 32 px AtlasTexture of one column, for UI icons (null if the column is unknown).
func atlas_texture(column: int) -> AtlasTexture:
	if column < 0:
		return null
	if _atlas_cache.has(column):
		return _atlas_cache[column]
	var tex := texture()
	if tex == null:
		return null
	var at := AtlasTexture.new()
	at.atlas = tex
	at.region = Rect2(column * tile_size, 0, tile_size, tile_size)
	_atlas_cache[column] = at
	return at

class_name GridMath
extends RefCounted
## Tile-grid helpers. Tiles are Vector2i (x right, y down); one tile = 5 ft.
## Movement is 8-directional and every step costs one tile (SRD simple
## diagonal rule), so distance is the Chebyshev distance.

const FEET_PER_TILE := 5

## Neighbour offsets: orthogonal first (N, E, S, W), then diagonals (NE, SE, SW, NW).
## The order is fixed so path finding is deterministic.
const OFFSETS_8: Array[Vector2i] = [
	Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0),
	Vector2i(1, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(-1, -1),
]


## Chebyshev distance in tiles.
static func distance_tiles(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


## True when b is one of the 8 tiles around a (melee reach 1, 5 ft). A tile is
## not adjacent to itself.
static func is_adjacent(a: Vector2i, b: Vector2i) -> bool:
	return a != b and GridMath.distance_tiles(a, b) == 1


static func is_diagonal_step(a: Vector2i, b: Vector2i) -> bool:
	return absi(a.x - b.x) == 1 and absi(a.y - b.y) == 1


## The 8 surrounding tiles in OFFSETS_8 order (may be out of bounds).
static func neighbors8(p: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for o in OFFSETS_8:
		out.append(p + o)
	return out


static func feet_to_tiles(feet: int) -> int:
	return floori(feet / float(FEET_PER_TILE))


## Vector2i -> [x, y] (JSON-safe).
static func vec_to_arr(v: Vector2i) -> Array:
	return [v.x, v.y]


## [x, y] (ints, floats from JSON or numeric strings) -> Vector2i. Anything
## malformed becomes Vector2i(0, 0); check with is_vec_arr() first when the
## input is untrusted.
static func arr_to_vec(a: Variant) -> Vector2i:
	if not GridMath.is_vec_arr(a):
		return Vector2i.ZERO
	var arr: Array = a
	return Vector2i(DictUtil.to_int(arr[0], 0), DictUtil.to_int(arr[1], 0))


## True for a two-element array of numbers.
static func is_vec_arr(a: Variant) -> bool:
	if typeof(a) != TYPE_ARRAY:
		return false
	var arr: Array = a
	return arr.size() == 2 and DictUtil.is_number(arr[0]) and DictUtil.is_number(arr[1])


## Rect2i -> [x, y, w, h] (JSON-safe).
static func rect_to_arr(r: Rect2i) -> Array:
	return [r.position.x, r.position.y, r.size.x, r.size.y]


## [x, y, w, h] -> Rect2i; malformed input becomes an empty Rect2i.
static func arr_to_rect(a: Variant) -> Rect2i:
	if typeof(a) != TYPE_ARRAY:
		return Rect2i()
	var arr: Array = a
	if arr.size() != 4:
		return Rect2i()
	for item: Variant in arr:
		if not DictUtil.is_number(item):
			return Rect2i()
	return Rect2i(DictUtil.to_int(arr[0], 0), DictUtil.to_int(arr[1], 0), DictUtil.to_int(arr[2], 0), DictUtil.to_int(arr[3], 0))


## [[x, y], ...] -> Array[Vector2i]; malformed entries are skipped.
static func arr_to_vec_list(a: Variant) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if typeof(a) != TYPE_ARRAY:
		return out
	var arr: Array = a
	for item: Variant in arr:
		if GridMath.is_vec_arr(item):
			out.append(GridMath.arr_to_vec(item))
	return out


static func vec_list_to_arr(list: Array[Vector2i]) -> Array:
	var out: Array = []
	for v in list:
		out.append(GridMath.vec_to_arr(v))
	return out

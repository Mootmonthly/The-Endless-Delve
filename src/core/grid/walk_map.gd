class_name WalkMap
extends RefCounted
## Which tiles of a floor can be walked on, plus grid path finding.
##
## `occupied` arguments are Dictionaries whose keys are Vector2i tiles holding a
## creature (values are ignored). Callers exclude the mover itself.

const WALL_CHAR := "#"
const FLOOR_CHAR := "."

var width: int = 0
var height: int = 0
var _cells: PackedByteArray = PackedByteArray()  # 1 = walkable, row-major


func _init(map_width: int = 0, map_height: int = 0, walkable: bool = false) -> void:
	width = maxi(0, map_width)
	height = maxi(0, map_height)
	_cells.resize(width * height)
	_cells.fill(1 if walkable else 0)


func in_bounds(p: Vector2i) -> bool:
	return p.x >= 0 and p.y >= 0 and p.x < width and p.y < height


func is_walkable(p: Vector2i) -> bool:
	return in_bounds(p) and _cells[p.y * width + p.x] == 1


func set_walkable(p: Vector2i, walkable: bool) -> void:
	if not in_bounds(p):
		push_error("WalkMap.set_walkable: %s is out of bounds" % str(p))
		return
	_cells[p.y * width + p.x] = 1 if walkable else 0


func bounds() -> Rect2i:
	return Rect2i(0, 0, width, height)


func walkable_count() -> int:
	var n := 0
	for b in _cells:
		n += b
	return n


## '#' is a wall, every other character is walkable. Short rows are padded
## with walls up to the longest row.
static func from_rows(rows: Array[String]) -> WalkMap:
	var w := 0
	for row in rows:
		w = maxi(w, row.length())
	var m := WalkMap.new(w, rows.size(), false)
	for y in range(rows.size()):
		var row := rows[y]
		for x in range(row.length()):
			if row[x] != WALL_CHAR:
				m._cells[y * w + x] = 1
	return m


## One string per row: '#' wall, '.' walkable.
func to_rows() -> Array[String]:
	var rows: Array[String] = []
	for y in range(height):
		var parts := PackedStringArray()
		for x in range(width):
			parts.append(FLOOR_CHAR if _cells[y * width + x] == 1 else WALL_CHAR)
		rows.append("".join(parts))
	return rows


func copy() -> WalkMap:
	var m := WalkMap.new(0, 0, false)
	m.width = width
	m.height = height
	m._cells = _cells.duplicate()
	return m


## A copy in which every tile outside `rect` is a wall (same coordinates).
func cropped_to(rect: Rect2i) -> WalkMap:
	var m := copy()
	for y in range(height):
		for x in range(width):
			if not rect.has_point(Vector2i(x, y)):
				m._cells[y * width + x] = 0
	return m


## One legal step: `to` is adjacent, in bounds, walkable and unoccupied, and a
## diagonal step does not cut a wall corner (both orthogonal tiles walkable).
func can_step(from: Vector2i, to: Vector2i, occupied: Dictionary) -> bool:
	if not GridMath.is_adjacent(from, to):
		return false
	if not is_walkable(to) or occupied.has(to):
		return false
	if GridMath.is_diagonal_step(from, to):
		if not is_walkable(Vector2i(to.x, from.y)) or not is_walkable(Vector2i(from.x, to.y)):
			return false
	return true


## Every tile reachable from start within `budget` steps (BFS): Vector2i -> cost.
## Includes start itself at cost 0.
func reachable(start: Vector2i, budget: int, occupied: Dictionary) -> Dictionary:
	var costs := {start: 0}
	var queue: Array[Vector2i] = [start]
	var head := 0
	while head < queue.size():
		var cell := queue[head]
		head += 1
		var cost: int = costs[cell]
		if cost >= budget:
			continue
		for n in GridMath.neighbors8(cell):
			if costs.has(n) or not can_step(cell, n, occupied):
				continue
			costs[n] = cost + 1
			queue.append(n)
	return costs


## Shortest path (BFS, deterministic neighbour order) from start to goal,
## excluding start. Empty when there is no path or start == goal.
## If goal is occupied, the path ends on the first reachable tile adjacent to
## goal (empty if start is already adjacent). max_len >= 0 limits the search
## depth: paths longer than max_len are not found.
func path_to(start: Vector2i, goal: Vector2i, occupied: Dictionary, max_len: int = -1) -> Array[Vector2i]:
	var empty: Array[Vector2i] = []
	if start == goal:
		return empty
	var goal_occupied := occupied.has(goal)
	if goal_occupied and GridMath.is_adjacent(start, goal):
		return empty
	var parent := {start: start}
	var depth := {start: 0}
	var queue: Array[Vector2i] = [start]
	var head := 0
	while head < queue.size():
		var cell := queue[head]
		head += 1
		var d: int = depth[cell]
		if max_len >= 0 and d >= max_len:
			continue
		for n in GridMath.neighbors8(cell):
			if parent.has(n) or not can_step(cell, n, occupied):
				continue
			parent[n] = cell
			depth[n] = d + 1
			if n == goal or (goal_occupied and GridMath.is_adjacent(n, goal)):
				return _unwind(parent, start, n)
			queue.append(n)
	return empty


func to_dict() -> Dictionary:
	return {"width": width, "height": height, "rows": to_rows()}


## Reads {"rows": [...]} (width/height are derived from the rows).
static func from_dict(d: Dictionary) -> WalkMap:
	return WalkMap.from_rows(DictUtil.to_string_array(d.get("rows", [])))


static func _unwind(parent: Dictionary, start: Vector2i, end: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	var cell := end
	while cell != start:
		path.append(cell)
		var prev: Vector2i = parent[cell]
		cell = prev
	path.reverse()
	return path


## True when the straight line between the centres of a and b crosses only
## walkable tiles (Bresenham; the end tiles themselves are not checked, and
## creatures never block sight). Symmetric: the line is always drawn from the
## smaller tile (by x, then y), so has_line_of_sight(a, b) == (b, a).
func has_line_of_sight(a: Vector2i, b: Vector2i) -> bool:
	if not in_bounds(a) or not in_bounds(b):
		return false
	var from := a
	var to := b
	if b.x < a.x or (b.x == a.x and b.y < a.y):
		from = b
		to = a
	for cell in WalkMap.line_cells(from, to):
		if cell != from and cell != to and not is_walkable(cell):
			return false
	return true


## Bresenham line from a to b, both ends included.
static func line_cells(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var dx := absi(b.x - a.x)
	var dy := -absi(b.y - a.y)
	var sx := 1 if a.x < b.x else -1
	var sy := 1 if a.y < b.y else -1
	var err := dx + dy
	var p := a
	while true:
		out.append(p)
		if p == b:
			break
		var e2 := 2 * err
		if e2 >= dy:
			err += dy
			p.x += sx
		if e2 <= dx:
			err += dx
			p.y += sy
	return out

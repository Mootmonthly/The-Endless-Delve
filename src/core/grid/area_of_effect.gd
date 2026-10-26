class_name AreaOfEffect
extends RefCounted
## Tiles covered by a spell area on the grid (one tile = 5 ft, Chebyshev distance).
##
## sphere / cylinder: tiles within `size` (radius in tiles) of the centre.
## cube:   tiles within `size` (half the side, rounded down) of the centre.
## line:   `size` tiles along the Bresenham line from the origin toward the aim
##         point (the origin tile excluded); it stops at the first wall.
## cone:   tiles within `size` of the origin (origin excluded) whose direction
##         from the origin is within 45 degrees of the origin -> aim direction.
## Walls block: a tile is covered only if it is walkable and in line of sight of
## the centre (sphere / cube) or origin (cone).

const CONE_HALF_ANGLE_DEG := 45.0


## Covered tiles in a stable order (row-major for sphere / cube / cone, along the
## line for line). `origin` is the caster's tile, `point` the chosen point (the
## centre of a sphere / cube, the aim of a cone / line).
static func tiles(shape: String, size: int, origin: Vector2i, point: Vector2i, map: WalkMap) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	match shape:
		"sphere", "cylinder", "cube":
			for y in range(point.y - size, point.y + size + 1):
				for x in range(point.x - size, point.x + size + 1):
					var p := Vector2i(x, y)
					if map.is_walkable(p) and map.has_line_of_sight(point, p):
						out.append(p)
		"line":
			var dir := point - origin
			if dir == Vector2i.ZERO:
				return out
			var steps := maxi(absi(dir.x), absi(dir.y))
			var scale := float(size) / float(steps)
			var end := origin + Vector2i(roundi(dir.x * scale), roundi(dir.y * scale))
			for p in WalkMap.line_cells(origin, end):
				if p == origin:
					continue
				if not map.is_walkable(p) or out.size() >= size:
					break
				out.append(p)
		"cone":
			var aim := Vector2(point - origin)
			if aim == Vector2.ZERO:
				return out
			var limit := deg_to_rad(CONE_HALF_ANGLE_DEG) + 0.0001
			for y in range(origin.y - size, origin.y + size + 1):
				for x in range(origin.x - size, origin.x + size + 1):
					var p := Vector2i(x, y)
					if p == origin or not map.is_walkable(p):
						continue
					if absf(aim.angle_to(Vector2(p - origin))) > limit:
						continue
					if map.has_line_of_sight(origin, p):
						out.append(p)
	return out

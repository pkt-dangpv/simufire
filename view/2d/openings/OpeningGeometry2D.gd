extends RefCounted


static func shared_edge_segment_m(a: Rect2, b: Rect2) -> PackedVector2Array:
	var eps: float = 0.0001

	if absf((a.position.x + a.size.x) - b.position.x) < eps:
		var x: float = a.position.x + a.size.x
		var y1: float = maxf(a.position.y, b.position.y)
		var y2: float = minf(a.position.y + a.size.y, b.position.y + b.size.y)
		if y2 > y1:
			return PackedVector2Array([Vector2(x, y1), Vector2(x, y2)])

	if absf(a.position.x - (b.position.x + b.size.x)) < eps:
		var x2: float = a.position.x
		var yy1: float = maxf(a.position.y, b.position.y)
		var yy2: float = minf(a.position.y + a.size.y, b.position.y + b.size.y)
		if yy2 > yy1:
			return PackedVector2Array([Vector2(x2, yy1), Vector2(x2, yy2)])

	if absf((a.position.y + a.size.y) - b.position.y) < eps:
		var y: float = a.position.y + a.size.y
		var xx1: float = maxf(a.position.x, b.position.x)
		var xx2: float = minf(a.position.x + a.size.x, b.position.x + b.size.x)
		if xx2 > xx1:
			return PackedVector2Array([Vector2(xx1, y), Vector2(xx2, y)])

	if absf(a.position.y - (b.position.y + b.size.y)) < eps:
		var y2: float = a.position.y
		var xxx1: float = maxf(a.position.x, b.position.x)
		var xxx2: float = minf(a.position.x + a.size.x, b.position.x + b.size.x)
		if xxx2 > xxx1:
			return PackedVector2Array([Vector2(xxx1, y2), Vector2(xxx2, y2)])

	return PackedVector2Array()


static func default_exterior_segment_m(r: Rect2, width_m: float, wall_side: String = "") -> PackedVector2Array:
	var side: String = wall_side.to_lower()

	if side == "left" or side == "right":
		var safe_height: float = clampf(width_m, 0.20, maxf(0.20, r.size.y))
		var y1: float = r.position.y + (r.size.y - safe_height) * 0.5
		var y2: float = y1 + safe_height
		var x_vertical: float = r.position.x if side == "left" else (r.position.x + r.size.x)
		return PackedVector2Array([Vector2(x_vertical, y1), Vector2(x_vertical, y2)])

	var safe_width: float = clampf(width_m, 0.20, maxf(0.20, r.size.x))
	var x1: float = r.position.x + (r.size.x - safe_width) * 0.5
	var x2: float = x1 + safe_width
	var y: float = r.position.y if side != "bottom" else (r.position.y + r.size.y)
	return PackedVector2Array([Vector2(x1, y), Vector2(x2, y)])


static func distance_point_to_segment(point: Vector2, a: Vector2, b: Vector2) -> float:
	var ab: Vector2 = b - a
	var len_sq: float = ab.length_squared()
	if len_sq <= 0.0001:
		return point.distance_to(a)
	var t: float = clampf((point - a).dot(ab) / len_sq, 0.0, 1.0)
	return point.distance_to(a + ab * t)

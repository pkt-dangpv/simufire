extends RefCounted


static func compute(op: OpeningModel, room_rects_m: Dictionary, outside_id: int, marker_depth_m: float) -> Dictionary:
	if op == null:
		return {}
	var room_id: int = op.a if op.a != outside_id else op.b
	if not room_rects_m.has(room_id):
		return {}

	var rect := Rect2(room_rects_m[room_id])
	var center_y: float = op.sill_m + op.height_m * 0.5
	var side: String = op.wall_side.strip_edges().to_lower()

	if op.is_exterior_opening() and side != "":
		return _pose_on_wall(rect, side, op.width_m, op.height_m, center_y, marker_depth_m)

	var other_id: int = op.b if op.a == room_id else op.a
	if room_rects_m.has(other_id):
		var other := Rect2(room_rects_m[other_id])
		var shared := _shared_wall_pose(rect, other, op.width_m, op.height_m, center_y, marker_depth_m)
		if not shared.is_empty():
			return shared

	var c1: Vector2 = rect.position + rect.size * 0.5
	return {
		"position": Vector3(c1.x, center_y, c1.y),
		"size": Vector3(op.width_m, op.height_m, marker_depth_m),
	}


static func _pose_on_wall(
	rect: Rect2,
	side: String,
	width_m: float,
	height_m: float,
	center_y: float,
	marker_depth_m: float
) -> Dictionary:
	var x_mid: float = rect.position.x + rect.size.x * 0.5
	var z_mid: float = rect.position.y + rect.size.y * 0.5
	match side:
		"top", "north":
			return {"position": Vector3(x_mid, center_y, rect.position.y), "size": Vector3(width_m, height_m, marker_depth_m)}
		"bottom", "south":
			return {"position": Vector3(x_mid, center_y, rect.position.y + rect.size.y), "size": Vector3(width_m, height_m, marker_depth_m)}
		"left", "west":
			return {"position": Vector3(rect.position.x, center_y, z_mid), "size": Vector3(marker_depth_m, height_m, width_m)}
		"right", "east":
			return {"position": Vector3(rect.position.x + rect.size.x, center_y, z_mid), "size": Vector3(marker_depth_m, height_m, width_m)}
		_:
			return {"position": Vector3(x_mid, center_y, z_mid), "size": Vector3(width_m, height_m, marker_depth_m)}


static func _shared_wall_pose(
	a: Rect2,
	b: Rect2,
	width_m: float,
	height_m: float,
	center_y: float,
	marker_depth_m: float
) -> Dictionary:
	var eps: float = 0.01
	var a_right: float = a.position.x + a.size.x
	var b_right: float = b.position.x + b.size.x
	var a_bottom: float = a.position.y + a.size.y
	var b_bottom: float = b.position.y + b.size.y

	if absf(a_right - b.position.x) < eps or absf(b_right - a.position.x) < eps:
		var x: float = a_right if absf(a_right - b.position.x) < eps else a.position.x
		var z1: float = maxf(a.position.y, b.position.y)
		var z2: float = minf(a_bottom, b_bottom)
		if z2 > z1:
			return {"position": Vector3(x, center_y, (z1 + z2) * 0.5), "size": Vector3(marker_depth_m, height_m, minf(width_m, z2 - z1))}

	if absf(a_bottom - b.position.y) < eps or absf(b_bottom - a.position.y) < eps:
		var z: float = a_bottom if absf(a_bottom - b.position.y) < eps else a.position.y
		var x1: float = maxf(a.position.x, b.position.x)
		var x2: float = minf(a_right, b_right)
		if x2 > x1:
			return {"position": Vector3((x1 + x2) * 0.5, center_y, z), "size": Vector3(minf(width_m, x2 - x1), height_m, marker_depth_m)}

	return {}

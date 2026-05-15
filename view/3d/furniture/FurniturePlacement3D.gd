extends RefCounted


static func fire_base_height_for(obj: Dictionary, kind_name: String) -> float:
	var elevation_m: float = maxf(0.0, float(obj.get("elevation_m", 0.0)))
	match kind_name:
		"sofa":
			return maxf(elevation_m, 0.62)
		"bed":
			return maxf(elevation_m, 0.60)
		"table":
			return maxf(elevation_m, 0.78)
		"wardrobe":
			return maxf(elevation_m, 1.45)
		"storage", "kitchen_unit":
			return maxf(elevation_m, 0.86)
		"curtain":
			return maxf(elevation_m, 1.15)
		"rug", "pool":
			return maxf(elevation_m, 0.06)
		"textile_pile", "containers", "clutter":
			return maxf(elevation_m, 0.24)
		_:
			return maxf(elevation_m, 0.30)


static func clamp_visual_pose(rect: Rect2, pos_m: Vector2, size_m: Vector2, rotation_deg: float) -> Dictionary:
	var margin_m: float = 0.10
	var room_w: float = maxf(0.05, rect.size.x)
	var room_d: float = maxf(0.05, rect.size.y)
	var available_w: float = maxf(0.05, room_w - margin_m * 2.0)
	var available_d: float = maxf(0.05, room_d - margin_m * 2.0)

	var visual_size := Vector2(maxf(0.05, size_m.x), maxf(0.05, size_m.y))
	var base_scale: float = minf(
		1.0,
		minf(
			available_w / maxf(0.05, visual_size.x),
			available_d / maxf(0.05, visual_size.y)
		)
	)
	visual_size *= maxf(0.05, base_scale)

	var angle: float = deg_to_rad(rotation_deg)
	var c: float = absf(cos(angle))
	var s: float = absf(sin(angle))
	var extent_x: float = (c * visual_size.x + s * visual_size.y) * 0.5
	var extent_z: float = (s * visual_size.x + c * visual_size.y) * 0.5
	var extent_scale: float = minf(
		1.0,
		minf(
			available_w / maxf(0.05, extent_x * 2.0),
			available_d / maxf(0.05, extent_z * 2.0)
		)
	)
	if extent_scale < 1.0:
		visual_size *= maxf(0.05, extent_scale)
		extent_x = (c * visual_size.x + s * visual_size.y) * 0.5
		extent_z = (s * visual_size.x + c * visual_size.y) * 0.5

	var center_m: Vector2 = pos_m + size_m * 0.5
	center_m.x = _clamp_or_center(center_m.x, margin_m + extent_x, room_w - margin_m - extent_x, room_w * 0.5)
	center_m.y = _clamp_or_center(center_m.y, margin_m + extent_z, room_d - margin_m - extent_z, room_d * 0.5)
	return {
		"center_m": center_m,
		"size_m": visual_size
	}


static func _clamp_or_center(value: float, min_value: float, max_value: float, center_value: float) -> float:
	if min_value > max_value:
		return center_value
	return clampf(value, min_value, max_value)

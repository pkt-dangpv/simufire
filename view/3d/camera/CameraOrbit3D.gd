extends RefCounted


static func fit_distance(bounds_m: Rect2, meters_to_units: float, min_distance_m: float, max_distance_m: float) -> float:
	if bounds_m.size == Vector2.ZERO:
		return min_distance_m
	var largest: float = maxf(bounds_m.size.x, bounds_m.size.y)
	return clampf(largest * meters_to_units * 1.35, min_distance_m, max_distance_m)


static func drag_orbit(orbit: Vector2, relative: Vector2, sensitivity: float) -> Vector2:
	return Vector2(
		clampf(orbit.x - relative.y * sensitivity, deg_to_rad(-82.0), deg_to_rad(-18.0)),
		orbit.y - relative.x * sensitivity
	)


static func zoom_distance(current_distance_m: float, step_m: float, zoom_in: bool, min_distance_m: float, max_distance_m: float) -> float:
	if zoom_in:
		return maxf(min_distance_m, current_distance_m - step_m)
	return minf(max_distance_m, current_distance_m + step_m)


static func apply_transform(camera_rig: Node3D, camera: Camera3D, orbit_x: float, orbit_y: float, distance_m: float) -> void:
	if camera_rig == null or camera == null:
		return
	camera_rig.position = Vector3.ZERO
	camera_rig.rotation = Vector3(orbit_x, orbit_y, 0.0)
	camera.position = Vector3(0.0, 0.0, distance_m)
	camera.rotation = Vector3.ZERO

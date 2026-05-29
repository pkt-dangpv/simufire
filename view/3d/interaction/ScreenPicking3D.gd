extends RefCounted


static func room_id_at_screen_pos(
	camera: Camera3D,
	building: BuildingModel,
	screen_pos: Vector2,
	meters_to_units: float,
	origin_offset_m: Vector2
) -> int:
	if camera == null or building == null:
		return -1
	var hit_m: Variant = _floor_hit_m(camera, screen_pos, meters_to_units, origin_offset_m)
	if typeof(hit_m) != TYPE_VECTOR2:
		return -1
	var rects: Dictionary = building.get_room_rects_m()
	var sorted_ids: Array = []
	for k in rects.keys():
		sorted_ids.append(int(k))
	sorted_ids.sort()
	for room_id in sorted_ids:
		if Rect2(rects[room_id]).has_point(hit_m):
			return room_id
	return -1


static func opening_index_at_screen_pos(camera: Camera3D, opening_items: Dictionary, screen_pos: Vector2) -> int:
	if camera == null:
		return -1
	var best_index: int = -1
	var best_distance: float = 999999.0
	for index in opening_items.keys():
		var item: Dictionary = Dictionary(opening_items[index])
		var marker := item.get("marker") as MeshInstance3D
		if marker == null or not marker.is_visible_in_tree():
			continue
		if camera.is_position_behind(marker.global_position):
			continue
		var marker_pos: Vector2 = camera.unproject_position(marker.global_position)
		var distance: float = marker_pos.distance_to(screen_pos)
		if distance < best_distance:
			best_distance = distance
			best_index = int(index)
	return best_index if best_distance <= 26.0 else -1


static func is_screen_point_over_model(
	camera: Camera3D,
	bounds_m: Rect2,
	screen_pos: Vector2,
	meters_to_units: float,
	origin_offset_m: Vector2
) -> bool:
	if camera == null:
		return true
	if bounds_m.size == Vector2.ZERO:
		return true
	var hit_m: Variant = _floor_hit_m(camera, screen_pos, meters_to_units, origin_offset_m)
	if typeof(hit_m) != TYPE_VECTOR2:
		return false
	var expanded_bounds: Rect2 = bounds_m.grow(0.75)
	return expanded_bounds.has_point(hit_m)


static func floor_hit_m(
	camera: Camera3D,
	screen_pos: Vector2,
	meters_to_units: float,
	origin_offset_m: Vector2
) -> Variant:
	return _floor_hit_m(camera, screen_pos, meters_to_units, origin_offset_m)


static func _floor_hit_m(
	camera: Camera3D,
	screen_pos: Vector2,
	meters_to_units: float,
	origin_offset_m: Vector2
) -> Variant:
	var origin: Vector3 = camera.project_ray_origin(screen_pos)
	var direction: Vector3 = camera.project_ray_normal(screen_pos)
	if absf(direction.y) < 0.0001:
		return null
	var t: float = -origin.y / direction.y
	if t < 0.0:
		return null
	var hit: Vector3 = origin + direction * t
	return Vector2(
		hit.x / maxf(0.0001, meters_to_units) - origin_offset_m.x,
		hit.z / maxf(0.0001, meters_to_units) - origin_offset_m.y
	)

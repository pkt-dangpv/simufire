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
	var rects: Dictionary = building.get_room_rects_m()
	var levels: Array[float] = _collect_floor_levels(building)
	levels.reverse()
	for level_m in levels:
		var hit_m: Variant = _floor_hit_at_level(camera, screen_pos, meters_to_units, origin_offset_m, level_m)
		if typeof(hit_m) != TYPE_VECTOR2:
			continue
		for room_id in rects.keys():
			var room: RoomModel = building.get_room(int(room_id))
			if room == null:
				continue
			if absf(room.floor_level_z_m - level_m) > 0.05:
				continue
			if Rect2(rects[room_id]).has_point(hit_m):
				return int(room_id)
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


## El gesto de orbita/zoom "sobre el modelo" se decidia proyectando contra el
## plano y = 0 aunque la vivienda estuviese en una planta alta, con lo que en
## multiplanta se resolvia con la proyeccion equivocada (V3-3). Si se le pasan
## las cotas de las plantas, se prueba contra cada una, de la mas alta a la mas
## baja, igual que hace room_id_at_screen_pos.
static func is_screen_point_over_model(
	camera: Camera3D,
	bounds_m: Rect2,
	screen_pos: Vector2,
	meters_to_units: float,
	origin_offset_m: Vector2,
	floor_levels_m: Array[float] = []
) -> bool:
	if camera == null:
		return true
	if bounds_m.size == Vector2.ZERO:
		return true
	var expanded_bounds: Rect2 = bounds_m.grow(0.75)
	var levels: Array[float] = floor_levels_m.duplicate()
	if levels.is_empty():
		levels.append(0.0)
	else:
		levels.sort()
		levels.reverse()
	for level_m in levels:
		var hit_m: Variant = _floor_hit_at_level(camera, screen_pos, meters_to_units, origin_offset_m, level_m)
		if typeof(hit_m) != TYPE_VECTOR2:
			continue
		if expanded_bounds.has_point(hit_m):
			return true
	return false


static func floor_hit_m(
	camera: Camera3D,
	screen_pos: Vector2,
	meters_to_units: float,
	origin_offset_m: Vector2
) -> Variant:
	return _floor_hit_m(camera, screen_pos, meters_to_units, origin_offset_m)


static func floor_hit_at_level(
	camera: Camera3D,
	screen_pos: Vector2,
	meters_to_units: float,
	origin_offset_m: Vector2,
	floor_level_m: float
) -> Variant:
	return _floor_hit_at_level(camera, screen_pos, meters_to_units, origin_offset_m, floor_level_m)


static func _floor_hit_m(
	camera: Camera3D,
	screen_pos: Vector2,
	meters_to_units: float,
	origin_offset_m: Vector2
) -> Variant:
	return _floor_hit_at_level(camera, screen_pos, meters_to_units, origin_offset_m, 0.0)


static func _floor_hit_at_level(
	camera: Camera3D,
	screen_pos: Vector2,
	meters_to_units: float,
	origin_offset_m: Vector2,
	floor_level_m: float
) -> Variant:
	var origin: Vector3 = camera.project_ray_origin(screen_pos)
	var direction: Vector3 = camera.project_ray_normal(screen_pos)
	if absf(direction.y) < 0.0001:
		return null
	var plane_y: float = floor_level_m * maxf(0.0001, meters_to_units)
	var t: float = (plane_y - origin.y) / direction.y
	if t < 0.0:
		return null
	var hit: Vector3 = origin + direction * t
	return Vector2(
		hit.x / maxf(0.0001, meters_to_units) - origin_offset_m.x,
		hit.z / maxf(0.0001, meters_to_units) - origin_offset_m.y
	)


static func _collect_floor_levels(building: BuildingModel) -> Array[float]:
	var levels: Array[float] = []
	var seen: Dictionary = {}
	var rooms: Dictionary = building.get_rooms()
	for room_id in rooms.keys():
		var room: RoomModel = rooms[room_id]
		if room == null:
			continue
		var lvl: float = room.floor_level_z_m
		var key: int = int(round(lvl * 100.0))
		if not seen.has(key):
			seen[key] = true
			levels.append(lvl)
	levels.sort()
	return levels

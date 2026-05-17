extends RefCounted


static func create_room_shell(
	rooms_root: Node3D,
	labels_root: Node3D,
	room_id: int,
	room_name: String,
	room_label: String,
	rect_m: Rect2,
	height_m: float,
	settings: Dictionary
) -> Dictionary:
	var meters_to_units: float = float(settings.get("meters_to_units", 1.0))
	var origin_offset_m: Vector2 = settings.get("origin_offset_m", Vector2.ZERO)
	var floor_thickness_m: float = float(settings.get("floor_thickness_m", 0.04))
	var wall_thickness_m: float = float(settings.get("wall_thickness_m", 0.07))
	var floor_level_m: float = float(settings.get("floor_level_m", 0.0))
	var show_walls: bool = bool(settings.get("show_walls", true))
	var show_room_labels: bool = bool(settings.get("show_room_labels", true))
	var floor_color: Color = settings.get("floor_color", Color(0.18, 0.18, 0.17, 1.0))
	var wall_color: Color = settings.get("wall_color", Color(0.84, 0.86, 0.82, 0.42))
	var label_color: Color = settings.get("label_color", Color(1.0, 0.96, 0.84, 1.0))

	var room_node := Node3D.new()
	room_node.name = "Room_%02d_%s" % [room_id, _safe_name(room_name)]
	if rooms_root != null:
		rooms_root.add_child(room_node)

	var floor := _create_box(
		"Floor",
		Vector3(rect_m.size.x, floor_thickness_m, rect_m.size.y) * meters_to_units,
		_make_material(floor_color, false)
	)
	floor.position = _room_center(rect_m, -floor_thickness_m * 0.5, origin_offset_m, meters_to_units)
	floor.position.y += floor_level_m * meters_to_units
	room_node.add_child(floor)

	var walls: Array[MeshInstance3D] = []
	if show_walls:
		var w := wall_thickness_m
		walls.append(_add_wall(room_node, "WallTop", rect_m, Vector3(rect_m.size.x + w, height_m, w), Vector2(rect_m.position.x + rect_m.size.x * 0.5, rect_m.position.y), wall_color, origin_offset_m, meters_to_units, floor_level_m))
		walls.append(_add_wall(room_node, "WallBottom", rect_m, Vector3(rect_m.size.x + w, height_m, w), Vector2(rect_m.position.x + rect_m.size.x * 0.5, rect_m.position.y + rect_m.size.y), wall_color, origin_offset_m, meters_to_units, floor_level_m))
		walls.append(_add_wall(room_node, "WallLeft", rect_m, Vector3(w, height_m, rect_m.size.y + w), Vector2(rect_m.position.x, rect_m.position.y + rect_m.size.y * 0.5), wall_color, origin_offset_m, meters_to_units, floor_level_m))
		walls.append(_add_wall(room_node, "WallRight", rect_m, Vector3(w, height_m, rect_m.size.y + w), Vector2(rect_m.position.x + rect_m.size.x, rect_m.position.y + rect_m.size.y * 0.5), wall_color, origin_offset_m, meters_to_units, floor_level_m))

	var label := Label3D.new()
	label.name = "Label_%02d" % room_id
	label.text = room_label
	label.modulate = label_color
	label.font_size = 54
	label.pixel_size = 0.014
	label.outline_size = 6
	label.no_depth_test = false
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = 3
	label.width = (minf(rect_m.size.x, rect_m.size.y) * 0.82) / 0.014
	label.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	label.position = _room_center(rect_m, floor_thickness_m + 0.012, origin_offset_m, meters_to_units)
	label.position.y += floor_level_m * meters_to_units
	label.visible = show_room_labels
	if labels_root != null:
		labels_root.add_child(label)

	return {
		"room_node": room_node,
		"floor": floor,
		"walls": walls,
		"label": label,
	}


static func _add_wall(
	parent: Node3D,
	wall_name: String,
	_rect_m: Rect2,
	size_m: Vector3,
	pos_m: Vector2,
	wall_color: Color,
	origin_offset_m: Vector2,
	meters_to_units: float,
	floor_level_m: float
) -> MeshInstance3D:
	var room_height_m: float = size_m.y
	var wall := _create_box(wall_name, size_m * meters_to_units, _make_material(wall_color, true))
	wall.position = _to_world(Vector3(pos_m.x, floor_level_m + room_height_m * 0.5, pos_m.y), origin_offset_m, meters_to_units)
	parent.add_child(wall)
	return wall


static func _create_box(node_name: String, size: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = mesh
	node.material_override = material
	return node


static func _make_material(color: Color, transparent: bool) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.94
	material.metallic = 0.0
	if transparent or color.a < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material


static func _room_center(rect_m: Rect2, y_m: float, origin_offset_m: Vector2, meters_to_units: float) -> Vector3:
	var center: Vector2 = rect_m.position + rect_m.size * 0.5
	return _to_world(Vector3(center.x, y_m, center.y), origin_offset_m, meters_to_units)


static func _to_world(pos_m: Vector3, origin_offset_m: Vector2, meters_to_units: float) -> Vector3:
	return Vector3(
		(pos_m.x + origin_offset_m.x) * meters_to_units,
		pos_m.y * meters_to_units,
		(pos_m.z + origin_offset_m.y) * meters_to_units
	)


static func _safe_name(value: String) -> String:
	var result: String = value.strip_edges()
	if result == "":
		return "room"
	result = result.replace(" ", "_")
	result = result.replace("/", "_")
	result = result.replace("\\", "_")
	return result

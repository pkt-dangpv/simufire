extends RefCounted

const SmokeVolumeMaterialFactory := preload("res://view/3d/smoke/SmokeVolumeMaterialFactory.gd")


static func create_ceiling_mask(node_name: String) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE
	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = mesh
	node.material_override = SmokeVolumeMaterialFactory.create_ceiling_mask()
	_disable_shadow_casting(node)
	return node


static func update_ceiling_mask(
	node: MeshInstance3D,
	rect: Rect2,
	height_m: float,
	should_show: bool,
	room_inset_m: float,
	meters_to_units: float
) -> void:
	if node == null:
		return
	node.visible = should_show
	if not node.visible:
		return
	var mesh := node.mesh as BoxMesh
	if mesh != null:
		mesh.size = Vector3(
			maxf(0.05, rect.size.x - room_inset_m * 2.0),
			0.018,
			maxf(0.05, rect.size.y - room_inset_m * 2.0)
		) * meters_to_units
	node.position = _room_center(rect, height_m + 0.004, meters_to_units)


static func update_layer_box(
	node: MeshInstance3D,
	rect: Rect2,
	height_m: float,
	layer_m: float,
	color: Color,
	should_show: bool,
	room_inset_m: float,
	meters_to_units: float
) -> void:
	if node == null:
		return
	node.visible = should_show and layer_m > 0.02 and layer_m < height_m - 0.02
	if not node.visible:
		return

	var mesh := node.mesh as BoxMesh
	if mesh != null:
		mesh.size = Vector3(
			maxf(0.05, rect.size.x - room_inset_m * 2.0),
			0.025,
			maxf(0.05, rect.size.y - room_inset_m * 2.0)
		) * meters_to_units
	var mat := node.material_override as StandardMaterial3D
	if mat != null:
		mat.albedo_color = color
	node.position = _room_center(rect, layer_m, meters_to_units)


static func _room_center(rect_m: Rect2, y_m: float, meters_to_units: float) -> Vector3:
	var center: Vector2 = rect_m.position + rect_m.size * 0.5
	return Vector3(center.x, y_m, center.y) * meters_to_units


static func _disable_shadow_casting(root: Node) -> void:
	if root is GeometryInstance3D:
		(root as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in root.get_children():
		_disable_shadow_casting(child)

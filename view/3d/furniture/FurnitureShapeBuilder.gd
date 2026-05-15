extends RefCounted

const FurnitureAssetLoader := preload("res://view/3d/furniture/FurnitureAssetLoader.gd")


static func rebuild(
	parent: Node3D,
	kind_name: String,
	size_m: Vector2,
	meters_to_units: float,
	generic_height_m: float
) -> void:
	if parent == null:
		return
	if FurnitureAssetLoader.try_build(parent, kind_name, size_m, meters_to_units):
		_add_heat_glow(parent, size_m, meters_to_units)
		return

	match kind_name:
		"sofa":
			_build_sofa_shape(parent, size_m, meters_to_units)
		"bed":
			_build_bed_shape(parent, size_m, meters_to_units)
		"table":
			_build_table_shape(parent, size_m, meters_to_units)
		"curtain":
			_build_curtain_shape(parent, size_m, meters_to_units)
		"wardrobe":
			_build_wardrobe_shape(parent, size_m, meters_to_units)
		"storage":
			_build_storage_shape(parent, size_m, meters_to_units)
		"kitchen_unit":
			_build_kitchen_unit_shape(parent, size_m, meters_to_units)
		"rug":
			_build_rug_shape(parent, size_m, meters_to_units)
		"textile_pile":
			_build_textile_pile_shape(parent, size_m, meters_to_units)
		"pool":
			_build_pool_shape(parent, size_m, meters_to_units)
		"containers":
			_build_container_shape(parent, size_m, meters_to_units)
		"clutter":
			_build_clutter_shape(parent, size_m, meters_to_units)
		_:
			_build_generic_fuel_shape(parent, size_m, generic_height_m, meters_to_units)
	_add_heat_glow(parent, size_m, meters_to_units)


static func _build_sofa_shape(parent: Node3D, size_m: Vector2, meters_to_units: float) -> void:
	var x: float = maxf(0.2, size_m.x)
	var z: float = maxf(0.2, size_m.y)
	var arm_w: float = minf(0.22, x * 0.13)
	var back_d: float = minf(0.20, z * 0.24)
	_add_box(parent, "ShadowBase", Vector3(0.0, 0.08, z * 0.05), Vector3(x * 0.94, 0.10, z * 0.72), Color(0.20, 0.16, 0.14, 1.0), meters_to_units)
	_add_ellipsoid(parent, "SeatRounded", Vector3(0.0, 0.27, z * 0.08), Vector3(x * 0.88, 0.30, z * 0.68), Color(0.50, 0.38, 0.31, 1.0), meters_to_units)
	_add_ellipsoid(parent, "BackRounded", Vector3(0.0, 0.58, -z * 0.5 + back_d * 0.62), Vector3(x * 0.92, 0.70, back_d * 1.35), Color(0.37, 0.28, 0.24, 1.0), meters_to_units)
	_add_ellipsoid(parent, "ArmLeft", Vector3(-x * 0.5 + arm_w * 0.65, 0.39, z * 0.05), Vector3(arm_w * 1.25, 0.48, z * 0.68), Color(0.39, 0.29, 0.24, 1.0), meters_to_units)
	_add_ellipsoid(parent, "ArmRight", Vector3(x * 0.5 - arm_w * 0.65, 0.39, z * 0.05), Vector3(arm_w * 1.25, 0.48, z * 0.68), Color(0.39, 0.29, 0.24, 1.0), meters_to_units)
	for i in range(3):
		var cx: float = lerpf(-x * 0.26, x * 0.26, float(i) / 2.0)
		_add_ellipsoid(parent, "Cushion_%d" % i, Vector3(cx, 0.45, z * 0.12), Vector3(x * 0.26, 0.10, z * 0.52), Color(0.58, 0.44, 0.36, 1.0), meters_to_units)


static func _build_bed_shape(parent: Node3D, size_m: Vector2, meters_to_units: float) -> void:
	var x: float = maxf(0.2, size_m.x)
	var z: float = maxf(0.2, size_m.y)
	_add_box(parent, "BedFrame", Vector3(0.0, 0.16, 0.0), Vector3(x, 0.18, z), Color(0.32, 0.22, 0.17, 1.0), meters_to_units)
	_add_ellipsoid(parent, "MattressRounded", Vector3(0.0, 0.36, 0.0), Vector3(x * 0.95, 0.28, z * 0.92), Color(0.72, 0.68, 0.59, 1.0), meters_to_units)
	_add_ellipsoid(parent, "BlanketSoft", Vector3(0.0, 0.53, z * 0.10), Vector3(x * 0.90, 0.09, z * 0.58), Color(0.56, 0.44, 0.34, 1.0), meters_to_units)
	_add_ellipsoid(parent, "PillowA", Vector3(-x * 0.24, 0.61, -z * 0.34), Vector3(x * 0.36, 0.13, z * 0.18), Color(0.84, 0.80, 0.70, 1.0), meters_to_units)
	_add_ellipsoid(parent, "PillowB", Vector3(x * 0.24, 0.61, -z * 0.34), Vector3(x * 0.36, 0.13, z * 0.18), Color(0.84, 0.80, 0.70, 1.0), meters_to_units)
	_add_box(parent, "Headboard", Vector3(0.0, 0.55, -z * 0.52), Vector3(x, 0.72, 0.08), Color(0.36, 0.25, 0.18, 1.0), meters_to_units)


static func _build_table_shape(parent: Node3D, size_m: Vector2, meters_to_units: float) -> void:
	var x: float = maxf(0.2, size_m.x)
	var z: float = maxf(0.2, size_m.y)
	var leg_w: float = minf(0.10, minf(x, z) * 0.14)
	_add_ellipsoid(parent, "SoftTableTop", Vector3(0.0, 0.74, 0.0), Vector3(x, 0.10, z), Color(0.48, 0.34, 0.22, 1.0), meters_to_units)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_add_cylinder(parent, "Leg", Vector3(sx * (x * 0.5 - leg_w), 0.36, sz * (z * 0.5 - leg_w)), Vector3(leg_w, 0.70, leg_w), Color(0.34, 0.22, 0.14, 1.0), meters_to_units)


static func _build_curtain_shape(parent: Node3D, size_m: Vector2, meters_to_units: float) -> void:
	var x: float = maxf(0.2, size_m.x)
	var z: float = maxf(0.05, size_m.y)
	var panels: int = 6
	var panel_w: float = x / float(panels)
	for i in range(panels):
		var offset_x: float = -x * 0.5 + panel_w * (float(i) + 0.5)
		var fold_z: float = (-0.5 if i % 2 == 0 else 0.5) * minf(0.08, z)
		_add_box(parent, "Panel_%d" % i, Vector3(offset_x, 0.90, fold_z), Vector3(panel_w * 0.72, 1.80, maxf(0.035, z * 0.55)), Color(0.53, 0.37, 0.30, 1.0), meters_to_units)
	_add_box(parent, "Rail", Vector3(0.0, 1.83, 0.0), Vector3(x, 0.04, maxf(0.04, z)), Color(0.30, 0.24, 0.20, 1.0), meters_to_units)


static func _build_wardrobe_shape(parent: Node3D, size_m: Vector2, meters_to_units: float) -> void:
	var x: float = maxf(0.2, size_m.x)
	var z: float = maxf(0.2, size_m.y)
	_add_box(parent, "Body", Vector3(0.0, 0.88, 0.0), Vector3(x, 1.76, z), Color(0.45, 0.31, 0.19, 1.0), meters_to_units)
	_add_box(parent, "DoorLeft", Vector3(-x * 0.25, 0.90, z * 0.5 + 0.012), Vector3(x * 0.46, 1.58, 0.035), Color(0.54, 0.38, 0.23, 1.0), meters_to_units)
	_add_box(parent, "DoorRight", Vector3(x * 0.25, 0.90, z * 0.5 + 0.012), Vector3(x * 0.46, 1.58, 0.035), Color(0.54, 0.38, 0.23, 1.0), meters_to_units)
	_add_box(parent, "HandleLeft", Vector3(-x * 0.06, 0.90, z * 0.5 + 0.04), Vector3(0.025, 0.42, 0.025), Color(0.76, 0.62, 0.36, 1.0), meters_to_units)
	_add_box(parent, "HandleRight", Vector3(x * 0.06, 0.90, z * 0.5 + 0.04), Vector3(0.025, 0.42, 0.025), Color(0.76, 0.62, 0.36, 1.0), meters_to_units)


static func _build_storage_shape(parent: Node3D, size_m: Vector2, meters_to_units: float) -> void:
	var x: float = maxf(0.2, size_m.x)
	var z: float = maxf(0.2, size_m.y)
	var long_axis: float = maxf(x, z)
	var shallow_axis: float = minf(x, z)
	var shelf_height: float = clampf(long_axis * 0.55, 0.70, 1.70)
	var is_x_long: bool = x >= z
	var width: float = long_axis
	var depth: float = clampf(shallow_axis, 0.24, 0.62)
	var body_size := Vector3(width, shelf_height, depth)
	var body_center := Vector3(0.0, shelf_height * 0.5, 0.0)
	if not is_x_long:
		body_size = Vector3(depth, shelf_height, width)
	_add_box(parent, "ShelfBack", body_center, body_size, Color(0.38, 0.26, 0.17, 1.0), meters_to_units)
	for level in range(3):
		var y: float = shelf_height * (0.24 + float(level) * 0.25)
		var shelf_size := Vector3(width * 0.92, 0.045, depth * 1.08)
		if not is_x_long:
			shelf_size = Vector3(depth * 1.08, 0.045, width * 0.92)
		_add_box(parent, "Shelf_%d" % level, Vector3(0.0, y, 0.0), shelf_size, Color(0.55, 0.39, 0.24, 1.0), meters_to_units)
	var item_count: int = clampi(int(round(long_axis * 2.0)), 2, 5)
	for i in range(item_count):
		var t: float = (float(i) + 0.5) / float(item_count) - 0.5
		var y_item: float = shelf_height * (0.34 + 0.18 * float(i % 3))
		var offset := Vector3(t * width * 0.70, y_item, depth * 0.05)
		var item_size := Vector3(width / float(item_count) * 0.45, 0.20 + 0.05 * float(i % 2), depth * 0.40)
		if not is_x_long:
			offset = Vector3(depth * 0.05, y_item, t * width * 0.70)
			item_size = Vector3(depth * 0.40, 0.20 + 0.05 * float(i % 2), width / float(item_count) * 0.45)
		_add_box(parent, "ShelfLoad_%d" % i, offset, item_size, Color(0.44, 0.32, 0.23, 1.0), meters_to_units)


static func _build_kitchen_unit_shape(parent: Node3D, size_m: Vector2, meters_to_units: float) -> void:
	var x: float = maxf(0.2, size_m.x)
	var z: float = maxf(0.2, size_m.y)
	_add_box(parent, "Cabinet", Vector3(0.0, 0.42, 0.0), Vector3(x, 0.84, z), Color(0.50, 0.36, 0.24, 1.0), meters_to_units)
	_add_box(parent, "Counter", Vector3(0.0, 0.88, 0.0), Vector3(x * 1.04, 0.08, z * 1.06), Color(0.20, 0.20, 0.18, 1.0), meters_to_units)
	for i in range(3):
		var cx: float = lerpf(-x * 0.32, x * 0.32, float(i) / 2.0)
		_add_box(parent, "Door_%d" % i, Vector3(cx, 0.44, z * 0.5 + 0.012), Vector3(x * 0.25, 0.58, 0.035), Color(0.58, 0.42, 0.28, 1.0), meters_to_units)
		_add_box(parent, "Handle_%d" % i, Vector3(cx, 0.58, z * 0.5 + 0.04), Vector3(x * 0.12, 0.025, 0.025), Color(0.76, 0.62, 0.36, 1.0), meters_to_units)


static func _build_textile_pile_shape(parent: Node3D, size_m: Vector2, meters_to_units: float) -> void:
	var x: float = maxf(0.2, size_m.x)
	var z: float = maxf(0.2, size_m.y)
	for i in range(6):
		var seed: float = float(i) * 1.73
		var offset := Vector3(
			sin(seed) * x * 0.22,
			0.10 + float(i % 3) * 0.055,
			cos(seed * 0.8) * z * 0.20
		)
		var item_size := Vector3(
			x * (0.34 + 0.08 * float(i % 2)),
			0.12,
			z * (0.28 + 0.07 * float((i + 1) % 2))
		)
		_add_ellipsoid(parent, "Fold_%d" % i, offset, item_size, Color(0.55, 0.42, 0.35, 1.0), meters_to_units)


static func _build_rug_shape(parent: Node3D, size_m: Vector2, meters_to_units: float) -> void:
	var x: float = maxf(0.2, size_m.x)
	var z: float = maxf(0.2, size_m.y)
	_add_ellipsoid(parent, "RugBody", Vector3(0.0, 0.035, 0.0), Vector3(x, 0.055, z), Color(0.52, 0.32, 0.24, 1.0), meters_to_units)
	_add_ellipsoid(parent, "RugInner", Vector3(0.0, 0.052, 0.0), Vector3(x * 0.78, 0.035, z * 0.70), Color(0.70, 0.50, 0.36, 1.0), meters_to_units)
	var fringe_z: float = z * 0.5 + 0.025
	_add_box(parent, "FringeA", Vector3(0.0, 0.045, -fringe_z), Vector3(x * 0.86, 0.018, 0.035), Color(0.80, 0.68, 0.52, 1.0), meters_to_units)
	_add_box(parent, "FringeB", Vector3(0.0, 0.045, fringe_z), Vector3(x * 0.86, 0.018, 0.035), Color(0.80, 0.68, 0.52, 1.0), meters_to_units)


static func _build_pool_shape(parent: Node3D, size_m: Vector2, meters_to_units: float) -> void:
	var x: float = maxf(0.2, size_m.x)
	var z: float = maxf(0.2, size_m.y)
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.5
	mesh.bottom_radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 36
	var mat := _make_material(Color(0.18, 0.12, 0.08, 0.78), true)
	mat.roughness = 0.42
	var puddle := MeshInstance3D.new()
	puddle.name = "FuelPuddle"
	puddle.mesh = mesh
	puddle.material_override = mat
	puddle.position = Vector3(0.0, 0.018, 0.0) * meters_to_units
	puddle.scale = Vector3(x, 0.025, z) * meters_to_units
	puddle.set_meta("base_color", Color(0.18, 0.12, 0.08, 0.78))
	parent.add_child(puddle)
	_add_box(parent, "PanLip", Vector3(0.0, 0.045, 0.0), Vector3(x * 1.04, 0.035, 0.035), Color(0.24, 0.22, 0.20, 1.0), meters_to_units)


static func _build_container_shape(parent: Node3D, size_m: Vector2, meters_to_units: float) -> void:
	var x: float = maxf(0.2, size_m.x)
	var z: float = maxf(0.2, size_m.y)
	var count: int = 3
	for i in range(count):
		var offset_x: float = lerpf(-x * 0.25, x * 0.25, float(i) / float(count - 1))
		_add_cylinder(parent, "PlasticContainer_%d" % i, Vector3(offset_x, 0.24, sin(float(i)) * z * 0.12), Vector3(x * 0.20, 0.48, z * 0.20), Color(0.36, 0.38, 0.36, 1.0), meters_to_units)
		_add_box(parent, "Lid_%d" % i, Vector3(offset_x, 0.50, sin(float(i)) * z * 0.12), Vector3(x * 0.24, 0.045, z * 0.24), Color(0.24, 0.27, 0.25, 1.0), meters_to_units)


static func _build_clutter_shape(parent: Node3D, size_m: Vector2, meters_to_units: float) -> void:
	var x: float = maxf(0.2, size_m.x)
	var z: float = maxf(0.2, size_m.y)
	for i in range(7):
		var seed: float = float(i) * 2.11
		var offset := Vector3(
			sin(seed) * x * 0.28,
			0.09 + float(i % 3) * 0.09,
			cos(seed * 0.7) * z * 0.28
		)
		var color := Color(0.43 + 0.05 * float(i % 2), 0.32, 0.23, 1.0)
		if i % 3 == 0:
			_add_ellipsoid(parent, "SoftLoad_%d" % i, offset, Vector3(x * 0.24, 0.18, z * 0.22), color, meters_to_units)
		else:
			_add_box(parent, "BoxLoad_%d" % i, offset, Vector3(x * 0.22, 0.18, z * 0.20), color, meters_to_units)


static func _build_generic_fuel_shape(parent: Node3D, size_m: Vector2, generic_height_m: float, meters_to_units: float) -> void:
	var x: float = maxf(0.2, size_m.x)
	var z: float = maxf(0.2, size_m.y)
	var h: float = maxf(0.22, generic_height_m)
	_add_ellipsoid(parent, "GenericPile", Vector3(0.0, h * 0.5, 0.0), Vector3(x, h, z), Color(0.48, 0.42, 0.34, 1.0), meters_to_units)


static func _add_box(
	parent: Node3D,
	node_name: String,
	center_m: Vector3,
	size_m: Vector3,
	color: Color,
	meters_to_units: float
) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size_m * meters_to_units
	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = mesh
	node.material_override = _make_material(color, false)
	node.position = center_m * meters_to_units
	node.set_meta("base_color", color)
	parent.add_child(node)
	return node


static func _add_ellipsoid(
	parent: Node3D,
	node_name: String,
	center_m: Vector3,
	size_m: Vector3,
	color: Color,
	meters_to_units: float
) -> MeshInstance3D:
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 24
	sphere.rings = 12
	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = sphere
	node.material_override = _make_material(color, false)
	node.position = center_m * meters_to_units
	node.scale = size_m * meters_to_units
	node.set_meta("base_color", color)
	parent.add_child(node)
	return node


static func _add_cylinder(
	parent: Node3D,
	node_name: String,
	center_m: Vector3,
	size_m: Vector3,
	color: Color,
	meters_to_units: float
) -> MeshInstance3D:
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.5
	cylinder.bottom_radius = 0.5
	cylinder.height = 1.0
	cylinder.radial_segments = 14
	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = cylinder
	node.material_override = _make_material(color, false)
	node.position = center_m * meters_to_units
	node.scale = size_m * meters_to_units
	node.set_meta("base_color", color)
	parent.add_child(node)
	return node


static func _add_heat_glow(parent: Node3D, size_m: Vector2, meters_to_units: float) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.5
	mesh.bottom_radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 32
	var mat := _make_material(Color(1.0, 0.32, 0.08, 0.0), true)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.26, 0.06, 1.0)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var glow := MeshInstance3D.new()
	glow.name = "HeatGlow"
	glow.mesh = mesh
	glow.material_override = mat
	glow.visible = false
	glow.position = Vector3(0.0, 0.025, 0.0) * meters_to_units
	glow.scale = Vector3(maxf(0.1, size_m.x), 0.018, maxf(0.1, size_m.y)) * meters_to_units
	parent.add_child(glow)


static func _make_material(color: Color, transparent: bool) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.94
	material.metallic = 0.0
	if transparent or color.a < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material

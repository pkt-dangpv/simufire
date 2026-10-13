extends "res://view/fp/FirstPersonController.gd"

## Diagnostic counterfactual only; exact parent method with two size guards.
## Original method identity is checked by tests, never used by product scenes.

func _update_opening_panel(index: int) -> void:
	if not _opening_nodes.has(index) or building == null:
		return
	var op: OpeningModel = building.get_opening_at(index)
	if op == null:
		return
	var data: Dictionary = _opening_nodes[index]
	var body := data.get("body") as StaticBody3D
	var mesh := data.get("mesh") as MeshInstance3D
	var shape := data.get("shape") as CollisionShape3D
	var asset := data.get("asset") as Node3D
	var window_leaf_left := data.get("window_leaf_left") as Node3D
	var window_leaf_right := data.get("window_leaf_right") as Node3D
	var light := data.get("light") as OmniLight3D
	var info: Dictionary = data.get("info", {})
	if body == null or mesh == null or shape == null or info.is_empty():
		return

	var is_door: bool = op.type == OpeningModel.Type.DOOR
	var is_window: bool = op.type == OpeningModel.Type.WINDOW
	var is_broken_window: bool = is_window and op.glass_broken
	var open_amount: float = clampf(op.open_fraction, 0.0, 1.0)
	var width_m: float = float(info.get("width_m", 0.8))
	var height_m: float = float(info.get("height_m", 2.0))
	var sill_m: float = float(info.get("sill_m", 0.0))
	var floor_level_m: float = float(info.get("floor_level_m", 0.0))
	var panel_thickness: float = 0.045 if (not is_door or _is_balcony_opening(op)) else closed_door_thickness_m
	var size := Vector3(width_m, height_m, panel_thickness)

	var center: Vector3 = Vector3(info.get("center", Vector3.ZERO))
	center.y = floor_level_m + sill_m + height_m * 0.5
	var visual_center: Vector3 = center
	var tangent: Vector3 = Vector3(info.get("tangent", Vector3.RIGHT)).normalized()
	var normal: Vector3 = Vector3(info.get("normal", Vector3.FORWARD)).normalized()
	var smoke_transmission: float = _light_smoke_transmission_for_opening(op)
	var base_yaw: float = atan2(-tangent.z, tangent.x)
	var visual_yaw: float = base_yaw
	if is_door:
		var closed_side: Vector3 = normal if _door_swing_direction(op) == "in" else -normal
		visual_center += closed_side * opening_panel_clearance_m
	elif is_window:
		visual_center -= normal * opening_panel_clearance_m

	if is_door and open_amount > 0.01:
		var base_swing_sign: float = -1.0 if tangent.cross(normal).y < 0.0 else 1.0
		var hinge_sign: float = -1.0 if _door_hinge_side(op) == "left" else 1.0
		var direction_sign: float = 1.0 if _door_swing_direction(op) == "in" else -1.0
		var swing_sign: float = base_swing_sign * -hinge_sign * direction_sign
		visual_yaw = base_yaw + deg_to_rad(82.0) * open_amount * swing_sign
		var hinge: Vector3 = center + tangent * hinge_sign * width_m * 0.5
		var rotated_tangent: Vector3 = Basis(Vector3.UP, visual_yaw).x.normalized()
		var clearance_side: Vector3 = normal if _door_swing_direction(op) == "in" else -normal
		visual_center = hinge - rotated_tangent * hinge_sign * width_m * 0.5 + clearance_side * opening_panel_clearance_m
	elif is_window and window_leaf_left != null and window_leaf_right != null:
		_update_window_leaf_pair(
			window_leaf_left,
			window_leaf_right,
			center,
			tangent,
			normal,
			base_yaw,
			width_m,
			height_m,
			open_amount,
			is_broken_window
		)
		body.position = center - normal * opening_panel_clearance_m
		body.rotation = Vector3(0.0, base_yaw, 0.0)
		var window_box_mesh := mesh.mesh as BoxMesh
		if window_box_mesh != null:
			window_box_mesh.size = size
		mesh.visible = false
		var window_box_shape := shape.shape as BoxShape3D
		if window_box_shape != null and window_box_shape.size != size:
			window_box_shape.size = size
		shape.position = Vector3.ZERO
		shape.disabled = is_broken_window or (not window_collision_when_closed) or open_amount > 0.05
		if light != null:
			var window_area_factor: float = clampf(width_m * height_m / 2.2, 0.35, 1.55)
			light.light_color = _effective_window_light_color()
			light.light_energy = _effective_window_light_energy() * window_area_factor * lerpf(0.45, 1.0, open_amount) * smoke_transmission
			light.omni_range = window_light_range_m * lerpf(0.72, 1.08, open_amount) * lerpf(0.72, 1.0, smoke_transmission)
		return

	body.position = visual_center
	body.rotation = Vector3(0.0, visual_yaw, 0.0)
	if asset != null:
		asset.position = Vector3.ZERO
		asset.rotation = Vector3.ZERO
		asset.scale = size
	var box_mesh := mesh.mesh as BoxMesh
	if box_mesh != null:
		box_mesh.size = size
	mesh.position = Vector3.ZERO
	if asset == null:
		mesh.material_override = _opening_material(op)
	var box_shape := shape.shape as BoxShape3D
	if box_shape != null and box_shape.size != size:
		box_shape.size = size
	shape.position = Vector3.ZERO
	shape.disabled = (not is_door and not (is_window and window_collision_when_closed)) or open_amount > 0.05
	if light != null:
		var area_factor: float = clampf(width_m * height_m / 2.2, 0.35, 1.55)
		# Por una balconera entra la luz de la CALLE, no la del rellano: es una
		# puerta, pero da a fachada.
		if op.type == OpeningModel.Type.WINDOW or _is_balcony_opening(op):
			light.light_color = _effective_window_light_color()
			light.light_energy = _effective_window_light_energy() * area_factor * lerpf(0.45, 1.0, open_amount) * smoke_transmission
			light.omni_range = window_light_range_m * lerpf(0.72, 1.08, open_amount) * lerpf(0.72, 1.0, smoke_transmission)
		else:
			light.light_color = _effective_landing_light_color()
			light.light_energy = _effective_landing_light_energy() * area_factor * lerpf(landing_light_closed_ratio, 1.0, open_amount) * smoke_transmission
			light.omni_range = landing_light_range_m * lerpf(0.78, 1.12, open_amount) * lerpf(0.70, 1.0, smoke_transmission)

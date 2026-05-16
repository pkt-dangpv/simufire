extends RefCounted

const SmokeBridgeMesh := preload("res://view/3d/smoke/SmokeBridgeMesh.gd")


static func update(item_dict: Dictionary, op: OpeningModel, room_items: Dictionary, settings: Dictionary) -> void:
	var curtain := item_dict.get("smoke_curtain") as MeshInstance3D
	if curtain == null:
		return
	var pose: Dictionary = Dictionary(item_dict.get("curtain_pose", {}))
	if pose.is_empty() or op == null:
		curtain.visible = false
		return

	var show_smoke_volume: bool = bool(settings.get("show_smoke_volume", true))
	var first_person_overlay: bool = bool(settings.get("first_person_overlay", false))
	var show_smoke_geometry_in_first_person: bool = bool(settings.get("show_smoke_geometry_in_first_person", false))
	var open_frac: float = op.effective_open_fraction()
	if open_frac <= 0.0 or not show_smoke_volume or (first_person_overlay and not show_smoke_geometry_in_first_person):
		curtain.visible = false
		return

	var item_a: Dictionary = room_items.get(op.a, {})
	var item_b: Dictionary = room_items.get(op.b, {})
	if item_a.is_empty() and item_b.is_empty():
		curtain.visible = false
		return

	var smoke_opening_blend_depth_m: float = float(settings.get("smoke_opening_blend_depth_m", 1.55))
	var smoke_min_visible_depth_m: float = float(settings.get("smoke_min_visible_depth_m", 0.05))
	var meters_to_units: float = float(settings.get("meters_to_units", 1.0))
	var smoke_color: Color = settings.get("smoke_color", Color(0.38, 0.40, 0.42, 0.20))
	var origin_offset_m: Vector2 = settings.get("origin_offset_m", Vector2.ZERO)

	var height_a: float = float(item_a.get("height_m", 2.4)) if not item_a.is_empty() else 2.4
	var height_b: float = float(item_b.get("height_m", 2.4)) if not item_b.is_empty() else height_a
	var bottom_a: float = float(item_a.get("smoke_bottom_m", height_a)) if not item_a.is_empty() else height_b
	var bottom_b: float = float(item_b.get("smoke_bottom_m", height_b)) if not item_b.is_empty() else height_a
	var alpha_a: float = float(item_a.get("smoke_alpha", 0.0)) if not item_a.is_empty() else 0.0
	var alpha_b: float = float(item_b.get("smoke_alpha", 0.0)) if not item_b.is_empty() else 0.0

	var source_bottom_m: float = minf(bottom_a, bottom_b)
	var source_alpha: float = maxf(alpha_a, alpha_b) * 0.72 + minf(alpha_a, alpha_b) * 0.28
	if item_a.is_empty() or item_b.is_empty():
		source_bottom_m = bottom_a if not item_a.is_empty() else bottom_b
		source_alpha = maxf(alpha_a, alpha_b) * 0.88
	var curtain_alpha: float = source_alpha * open_frac

	var pose_size: Vector3 = Vector3(pose["size"])
	var thin_axis_is_x: bool = pose_size.x <= pose_size.z
	var opening_width_m: float = maxf(pose_size.x, pose_size.z)
	var door_height_m: float = pose_size.y
	var blend_depth_m: float = maxf(minf(pose_size.x, pose_size.z), smoke_opening_blend_depth_m * lerpf(0.58, 1.0, open_frac))
	if op.is_exterior_opening():
		blend_depth_m = maxf(blend_depth_m, 0.54)
	var pos3: Vector3 = Vector3(pose["position"])
	var opening_bottom_m: float = pos3.y - door_height_m * 0.5
	var opening_top_m: float = pos3.y + door_height_m * 0.5
	var bottom_neg_m: float = clampf(source_bottom_m, opening_bottom_m, opening_top_m)
	var bottom_pos_m: float = bottom_neg_m
	if not item_a.is_empty() and not item_b.is_empty():
		var rect_a := Rect2(item_a.get("rect", Rect2()))
		var rect_b := Rect2(item_b.get("rect", Rect2()))
		var axis_a: float = rect_a.position.x + rect_a.size.x * 0.5 if thin_axis_is_x else rect_a.position.y + rect_a.size.y * 0.5
		var axis_b: float = rect_b.position.x + rect_b.size.x * 0.5 if thin_axis_is_x else rect_b.position.y + rect_b.size.y * 0.5
		var bottom_a_clamped: float = clampf(bottom_a, opening_bottom_m, opening_top_m)
		var bottom_b_clamped: float = clampf(bottom_b, opening_bottom_m, opening_top_m)
		if axis_a <= axis_b:
			bottom_neg_m = bottom_a_clamped
			bottom_pos_m = bottom_b_clamped
		else:
			bottom_neg_m = bottom_b_clamped
			bottom_pos_m = bottom_a_clamped
	var curtain_bottom_m: float = minf(bottom_neg_m, bottom_pos_m)
	var curtain_depth_m: float = maxf(0.0, opening_top_m - curtain_bottom_m)
	curtain.visible = curtain_depth_m > smoke_min_visible_depth_m and curtain_alpha > 0.012
	if not curtain.visible:
		return

	var curtain_center_y: float = curtain_bottom_m + curtain_depth_m * 0.5
	curtain.mesh = SmokeBridgeMesh.create(
		thin_axis_is_x,
		opening_width_m,
		blend_depth_m,
		bottom_neg_m - curtain_center_y,
		bottom_pos_m - curtain_center_y,
		opening_top_m - curtain_center_y,
		meters_to_units
	)
	var curtain_shader := curtain.material_override as ShaderMaterial
	if curtain_shader != null:
		var curtain_color := Color(
			smoke_color.r,
			smoke_color.g,
			smoke_color.b,
			clampf(curtain_alpha * (0.72 if first_person_overlay else 0.52), 0.035, 0.38)
		)
		curtain_shader.set_shader_parameter("smoke_color", curtain_color)
		curtain_shader.set_shader_parameter("density", clampf(0.44 + curtain_alpha * 1.15, 0.34, 1.10))
		curtain_shader.set_shader_parameter("turbulence", 0.88)
		curtain_shader.set_shader_parameter("drift_speed", 0.14)
		curtain_shader.set_shader_parameter("volume_depth_m", maxf(curtain_depth_m, 0.05))
		curtain_shader.set_shader_parameter("edge_softness", 0.30)
		curtain_shader.set_shader_parameter("bottom_waviness", 0.48)
		curtain_shader.set_shader_parameter("edge_band_strength", 0.95)
		curtain_shader.set_shader_parameter("side_visibility", 0.0 if first_person_overlay else 0.18)
		curtain_shader.set_shader_parameter("bottom_surface_strength", 1.08 if first_person_overlay else 0.82)
		curtain_shader.set_shader_parameter("top_visibility", 0.0)
	else:
		var curtain_mat := curtain.material_override as StandardMaterial3D
		if curtain_mat != null:
			curtain_mat.albedo_color = Color(
				smoke_color.r,
				smoke_color.g,
				smoke_color.b,
				clampf(curtain_alpha * 0.52, 0.035, 0.38)
			)
	curtain.position = _to_world(Vector3(pos3.x, curtain_center_y, pos3.z), meters_to_units, origin_offset_m)


static func _to_world(meters: Vector3, meters_to_units: float, origin_offset_m: Vector2) -> Vector3:
	return Vector3(
		(meters.x + origin_offset_m.x) * meters_to_units,
		meters.y * meters_to_units,
		(meters.z + origin_offset_m.y) * meters_to_units
	)

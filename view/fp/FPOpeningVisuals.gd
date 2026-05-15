extends RefCounted


static func compute_window_leaf_pair(
	center: Vector3,
	tangent: Vector3,
	normal: Vector3,
	base_yaw: float,
	width_m: float,
	open_amount: float,
	open_angle_rad: float,
	panel_clearance_m: float
) -> Dictionary:
	var clean_tangent: Vector3 = tangent.normalized()
	if clean_tangent.length_squared() <= 0.0001:
		clean_tangent = Vector3.RIGHT
	var clean_normal: Vector3 = normal.normalized()
	if clean_normal.length_squared() <= 0.0001:
		clean_normal = Vector3.BACK

	var amount: float = clampf(open_amount, 0.0, 1.0)
	var leaf_width_m: float = maxf(0.08, width_m * 0.5)
	var outward: Vector3 = -clean_normal
	var clearance: Vector3 = outward * panel_clearance_m
	var left_closed_center: Vector3 = center - clean_tangent * (leaf_width_m * 0.5) + clearance
	var right_closed_center: Vector3 = center + clean_tangent * (leaf_width_m * 0.5) + clearance
	var left_yaw: float = base_yaw
	var right_yaw: float = base_yaw
	var left_center: Vector3 = left_closed_center
	var right_center: Vector3 = right_closed_center

	if amount > 0.01:
		var angle: float = open_angle_rad * amount
		var left_hinge: Vector3 = center - clean_tangent * (width_m * 0.5)
		var right_hinge: Vector3 = center + clean_tangent * (width_m * 0.5)
		left_yaw = _pick_window_leaf_yaw(base_yaw, angle, left_hinge, leaf_width_m, left_closed_center, outward, true)
		right_yaw = _pick_window_leaf_yaw(base_yaw, angle, right_hinge, leaf_width_m, right_closed_center, outward, false)
		var left_axis: Vector3 = Basis(Vector3.UP, left_yaw).x.normalized()
		var right_axis: Vector3 = Basis(Vector3.UP, right_yaw).x.normalized()
		left_center = left_hinge + left_axis * (leaf_width_m * 0.5) + clearance
		right_center = right_hinge - right_axis * (leaf_width_m * 0.5) + clearance

	return {
		"left_center": left_center,
		"right_center": right_center,
		"left_yaw": left_yaw,
		"right_yaw": right_yaw,
	}


static func _pick_window_leaf_yaw(
	base_yaw: float,
	angle: float,
	hinge: Vector3,
	leaf_width_m: float,
	closed_center: Vector3,
	outward: Vector3,
	extends_positive_axis: bool
) -> float:
	var yaw_a: float = base_yaw + angle
	var yaw_b: float = base_yaw - angle
	var score_a: float = _window_leaf_outward_score(yaw_a, hinge, leaf_width_m, closed_center, outward, extends_positive_axis)
	var score_b: float = _window_leaf_outward_score(yaw_b, hinge, leaf_width_m, closed_center, outward, extends_positive_axis)
	return yaw_a if score_a >= score_b else yaw_b


static func _window_leaf_outward_score(
	yaw: float,
	hinge: Vector3,
	leaf_width_m: float,
	closed_center: Vector3,
	outward: Vector3,
	extends_positive_axis: bool
) -> float:
	var axis: Vector3 = Basis(Vector3.UP, yaw).x.normalized()
	var signed_half_width: float = leaf_width_m * 0.5 if extends_positive_axis else -leaf_width_m * 0.5
	var candidate_center: Vector3 = hinge + axis * signed_half_width
	return (candidate_center - closed_center).dot(outward)

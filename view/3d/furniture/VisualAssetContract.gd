extends RefCounted

## Contrato opt-in de arte; no es un interruptor de fisica.
## Legacy conserva su ajuste hasta migrar cada wrapper de forma declarada.
const KEY: String = "simufire_transform_mode"
const LEGACY: String = "legacy_fit"
const AUTHORED: String = "authored_meters_v1"
const INVALID: String = "invalid_metadata_type"
const PIVOT_EPS_M: float = 0.001


static func mode_of(instance: Node3D) -> String:
	var value: Variant = instance.get_meta(KEY, LEGACY)
	return value if typeof(value) == TYPE_STRING else INVALID


static func validate_authored(instance: Node3D, bounds: AABB) -> Array[String]:
	var errors: Array[String] = []
	if not instance.transform.is_equal_approx(Transform3D.IDENTITY):
		errors.append("authored_root_must_be_identity")
	if not bounds.size.is_finite() or bounds.size.x <= 0.0 \
			or bounds.size.y <= 0.0 or bounds.size.z <= 0.0:
		errors.append("authored_bounds_must_be_finite_and_positive")
	if not bounds.position.is_finite():
		errors.append("authored_bounds_position_must_be_finite")
	var center: Vector3 = bounds.get_center()
	if absf(center.x) > PIVOT_EPS_M or absf(center.z) > PIVOT_EPS_M \
			or absf(bounds.position.y) > PIVOT_EPS_M:
		errors.append("authored_pivot_must_be_floor_center")
	var front: Variant = instance.get_meta("simufire_front_axis", "")
	if typeof(front) != TYPE_STRING or front != "-z":
		errors.append("authored_front_axis_must_be_declared_minus_z")
	return errors


static func publish_placement_issues(node: Node3D, spec: Dictionary) -> void:
	var issues: Array = Array(spec.get("visual_placement_issues", []))
	var previous: Array = Array(node.get_meta("visual_placement_issues", []))
	node.set_meta("visual_placement_issues", issues.duplicate())
	if not issues.is_empty() and issues != previous:
		push_warning("Asset %s: colocacion de autor no corregida: %s" % [node.name, str(issues)])

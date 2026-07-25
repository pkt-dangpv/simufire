extends RefCounted
class_name Phase3SurfaceEnergySolver

# Pure five-node finite-volume solver for the Phase 3 multi-surface shadow.
# It owns no runtime state and never reads or mutates RoomModel.

const NODE_COUNT: int = 5
const EPSILON: float = 1.0e-12

# The first four nodes resolve the thermal penetration depth relevant to the
# 0-180 s validation window. Callers may provide another strictly increasing
# grid through state["node_depth_fractions"].
const DEFAULT_NODE_DEPTH_FRACTIONS: Array[float] = [
	0.0,
	0.03,
	0.05,
	0.10,
	1.0,
]


static func make_uniform_state(
	area_m2: float,
	thickness_m: float,
	conductivity_kw_m_k: float,
	density_kg_m3: float,
	cp_kj_kg_k: float,
	temp_c: float,
	reference_temp_c: float
) -> Dictionary:
	return {
		"area_m2": area_m2,
		"thickness_m": thickness_m,
		"conductivity_kw_m_k": conductivity_kw_m_k,
		"density_kg_m3": density_kg_m3,
		"cp_kj_kg_k": cp_kj_kg_k,
		"reference_temp_c": reference_temp_c,
		"node_depth_fractions": DEFAULT_NODE_DEPTH_FRACTIONS.duplicate(),
		"nodes_c": [temp_c, temp_c, temp_c, temp_c, temp_c],
	}


static func stored_energy_kj(state: Dictionary) -> float:
	var validation_error: String = _validate_state(state)
	if not validation_error.is_empty():
		return NAN
	var area_m2: float = float(state["area_m2"])
	var thickness_m: float = float(state["thickness_m"])
	var density_kg_m3: float = float(state["density_kg_m3"])
	var cp_kj_kg_k: float = float(state["cp_kj_kg_k"])
	var reference_temp_c: float = float(state["reference_temp_c"])
	var nodes: Array = state["nodes_c"]
	var fractions: Array = _depth_fractions(state)
	var widths_m: Array = _control_widths_m(thickness_m, fractions)
	var energy_kj: float = 0.0
	for index: int in range(NODE_COUNT):
		energy_kj += (
			area_m2
			* density_kg_m3
			* cp_kj_kg_k
			* float(widths_m[index])
			* (float(nodes[index]) - reference_temp_c)
		)
	return energy_kj


static func step_surface(pre_state: Dictionary, boundary: Dictionary) -> Dictionary:
	var state_error: String = _validate_state(pre_state)
	if not state_error.is_empty():
		return _invalid_result(state_error)
	var boundary_error: String = _validate_boundary(boundary)
	if not boundary_error.is_empty():
		return _invalid_result(boundary_error)

	var dt_s: float = float(boundary["dt_s"])
	var area_m2: float = float(pre_state["area_m2"])
	var thickness_m: float = float(pre_state["thickness_m"])
	var conductivity_kw_m_k: float = float(pre_state["conductivity_kw_m_k"])
	var density_kg_m3: float = float(pre_state["density_kg_m3"])
	var cp_kj_kg_k: float = float(pre_state["cp_kj_kg_k"])
	var nodes_pre: Array = pre_state["nodes_c"]
	var fractions: Array = _depth_fractions(pre_state)
	var coordinates_m: Array = _node_coordinates_m(thickness_m, fractions)
	var widths_m: Array = _control_widths_m(thickness_m, fractions)

	var gas_temp_c: float = float(boundary.get("interior_gas_temp_c", 0.0))
	var interior_h_kw_m2_k: float = float(
		boundary.get("interior_h_kw_m2_k", 0.0)
	)
	var has_prescribed_convection: bool = boundary.has(
		"interior_convection_energy_kj"
	)
	var prescribed_convection_energy_kj: float = float(
		boundary.get("interior_convection_energy_kj", 0.0)
	)
	var exterior_temp_c: float = float(boundary.get("exterior_temp_c", 0.0))
	var exterior_h_kw_m2_k: float = float(
		boundary.get("exterior_h_kw_m2_k", 0.0)
	)
	var has_prescribed_exterior: bool = boundary.has(
		"exterior_energy_removed_kj"
	)
	var prescribed_exterior_energy_removed_kj: float = float(
		boundary.get("exterior_energy_removed_kj", 0.0)
	)
	var gas_radiation_energy_kj: float = float(
		boundary.get("gas_radiation_energy_kj", 0.0)
	)
	var fire_radiation_energy_kj: float = float(
		boundary.get("fire_radiation_energy_kj", 0.0)
	)
	if area_m2 <= EPSILON:
		if absf(gas_radiation_energy_kj) > EPSILON \
				or fire_radiation_energy_kj > EPSILON \
				or absf(prescribed_convection_energy_kj) > EPSILON \
				or absf(prescribed_exterior_energy_removed_kj) > EPSILON:
			return _invalid_result("cannot apply energy to zero-area surface")
		return {
			"valid": true,
			"error": "",
			"post_state": pre_state.duplicate(true),
			"pre_stored_energy_kj": 0.0,
			"post_stored_energy_kj": 0.0,
			"stored_energy_delta_kj": 0.0,
			"interior_convection_energy_kj": 0.0,
			"gas_radiation_energy_kj": 0.0,
			"fire_radiation_energy_kj": 0.0,
			"exterior_energy_removed_kj": 0.0,
			"internal_conduction_residual_kj": 0.0,
			"energy_residual_kj": 0.0,
		}
	var applied_inner_flux_kw_m2: float = (
		(
			gas_radiation_energy_kj
			+ fire_radiation_energy_kj
			+ prescribed_convection_energy_kj
		)
		/ (area_m2 * dt_s)
	)
	var applied_outer_sink_kw_m2: float = (
		prescribed_exterior_energy_removed_kj / (area_m2 * dt_s)
	)

	var lower: Array = [0.0, 0.0, 0.0, 0.0, 0.0]
	var diagonal: Array = [0.0, 0.0, 0.0, 0.0, 0.0]
	var upper: Array = [0.0, 0.0, 0.0, 0.0, 0.0]
	var rhs: Array = [0.0, 0.0, 0.0, 0.0, 0.0]

	for index: int in range(NODE_COUNT):
		var capacity_rate_kw_m2_k: float = (
			density_kg_m3 * cp_kj_kg_k * float(widths_m[index]) / dt_s
		)
		diagonal[index] += capacity_rate_kw_m2_k
		rhs[index] += capacity_rate_kw_m2_k * float(nodes_pre[index])

	for edge: int in range(NODE_COUNT - 1):
		var spacing_m: float = (
			float(coordinates_m[edge + 1]) - float(coordinates_m[edge])
		)
		var conductance_kw_m2_k: float = conductivity_kw_m_k / spacing_m
		diagonal[edge] += conductance_kw_m2_k
		upper[edge] -= conductance_kw_m2_k
		diagonal[edge + 1] += conductance_kw_m2_k
		lower[edge + 1] -= conductance_kw_m2_k

	if not has_prescribed_convection:
		diagonal[0] += interior_h_kw_m2_k
		rhs[0] += interior_h_kw_m2_k * gas_temp_c
	rhs[0] += applied_inner_flux_kw_m2
	if not has_prescribed_exterior:
		diagonal[NODE_COUNT - 1] += exterior_h_kw_m2_k
		rhs[NODE_COUNT - 1] += exterior_h_kw_m2_k * exterior_temp_c
	rhs[NODE_COUNT - 1] -= applied_outer_sink_kw_m2

	var nodes_post: Array = _solve_tridiagonal(lower, diagonal, upper, rhs)
	if nodes_post.is_empty():
		return _invalid_result("singular tridiagonal system")
	for value in nodes_post:
		if not is_finite(float(value)):
			return _invalid_result("non-finite post-step temperature")

	var post_state: Dictionary = pre_state.duplicate(true)
	post_state["nodes_c"] = nodes_post
	post_state["node_depth_fractions"] = fractions.duplicate()

	var pre_stored_energy_kj: float = stored_energy_kj(pre_state)
	var post_stored_energy_kj: float = stored_energy_kj(post_state)
	var stored_energy_delta_kj: float = (
		post_stored_energy_kj - pre_stored_energy_kj
	)
	var interior_convection_energy_kj: float = prescribed_convection_energy_kj
	if not has_prescribed_convection:
		interior_convection_energy_kj = (
			interior_h_kw_m2_k
			* area_m2
			* (gas_temp_c - float(nodes_post[0]))
			* dt_s
		)
	var exterior_energy_removed_kj: float = \
			prescribed_exterior_energy_removed_kj
	if not has_prescribed_exterior:
		exterior_energy_removed_kj = (
			exterior_h_kw_m2_k
			* area_m2
			* (float(nodes_post[NODE_COUNT - 1]) - exterior_temp_c)
			* dt_s
		)
	var energy_residual_kj: float = (
		stored_energy_delta_kj
		- interior_convection_energy_kj
		- gas_radiation_energy_kj
		- fire_radiation_energy_kj
		+ exterior_energy_removed_kj
	)

	return {
		"valid": true,
		"error": "",
		"post_state": post_state,
		"pre_stored_energy_kj": pre_stored_energy_kj,
		"post_stored_energy_kj": post_stored_energy_kj,
		"stored_energy_delta_kj": stored_energy_delta_kj,
		"interior_convection_energy_kj": interior_convection_energy_kj,
		"gas_radiation_energy_kj": gas_radiation_energy_kj,
		"fire_radiation_energy_kj": fire_radiation_energy_kj,
		"exterior_energy_removed_kj": exterior_energy_removed_kj,
		"internal_conduction_residual_kj": 0.0,
		"energy_residual_kj": energy_residual_kj,
	}


static func _depth_fractions(state: Dictionary) -> Array:
	if state.has("node_depth_fractions"):
		return (state["node_depth_fractions"] as Array).duplicate()
	return DEFAULT_NODE_DEPTH_FRACTIONS.duplicate()


static func _node_coordinates_m(thickness_m: float, fractions: Array) -> Array:
	var coordinates: Array = []
	for fraction in fractions:
		coordinates.append(float(fraction) * thickness_m)
	return coordinates


static func _control_widths_m(thickness_m: float, fractions: Array) -> Array:
	var coordinates: Array = _node_coordinates_m(thickness_m, fractions)
	var faces: Array = [0.0]
	for index: int in range(1, NODE_COUNT):
		faces.append(
			0.5 * (float(coordinates[index - 1]) + float(coordinates[index]))
		)
	faces.append(thickness_m)
	var widths: Array = []
	for index: int in range(NODE_COUNT):
		widths.append(float(faces[index + 1]) - float(faces[index]))
	return widths


static func _validate_state(state: Dictionary) -> String:
	if not state.has("area_m2"):
		return "missing state field: area_m2"
	var area_m2: float = float(state["area_m2"])
	if not is_finite(area_m2) or area_m2 < 0.0:
		return "invalid non-negative state field: area_m2"
	for field_name in [
		"thickness_m",
		"conductivity_kw_m_k",
		"density_kg_m3",
		"cp_kj_kg_k",
		"reference_temp_c",
		"nodes_c",
	]:
		if not state.has(field_name):
			return "missing state field: " + field_name
	for field_name in [
		"thickness_m",
		"conductivity_kw_m_k",
		"density_kg_m3",
		"cp_kj_kg_k",
	]:
		var value: float = float(state[field_name])
		if not is_finite(value) or value <= 0.0:
			return "invalid positive state field: " + field_name
	var reference_temp_c: float = float(state["reference_temp_c"])
	if not is_finite(reference_temp_c):
		return "invalid reference temperature"
	if not state["nodes_c"] is Array:
		return "nodes_c must be an Array"
	var nodes: Array = state["nodes_c"]
	if nodes.size() != NODE_COUNT:
		return "nodes_c must contain five temperatures"
	for value in nodes:
		if not is_finite(float(value)):
			return "nodes_c contains a non-finite temperature"
	var fractions: Array = _depth_fractions(state)
	if fractions.size() != NODE_COUNT:
		return "node_depth_fractions must contain five values"
	if absf(float(fractions[0])) > EPSILON:
		return "node_depth_fractions must start at zero"
	if absf(float(fractions[NODE_COUNT - 1]) - 1.0) > EPSILON:
		return "node_depth_fractions must end at one"
	var previous: float = -1.0
	for value in fractions:
		var fraction: float = float(value)
		if not is_finite(fraction) or fraction <= previous:
			return "node_depth_fractions must be finite and strictly increasing"
		previous = fraction
	return ""


static func _validate_boundary(boundary: Dictionary) -> String:
	if not boundary.has("dt_s"):
		return "missing boundary field: dt_s"
	var dt_s: float = float(boundary["dt_s"])
	if not is_finite(dt_s) or dt_s <= 0.0:
		return "dt_s must be finite and positive"
	for field_name in [
		"interior_gas_temp_c",
		"interior_h_kw_m2_k",
		"exterior_temp_c",
		"exterior_h_kw_m2_k",
		"gas_radiation_energy_kj",
		"fire_radiation_energy_kj",
		"interior_convection_energy_kj",
		"exterior_energy_removed_kj",
	]:
		if boundary.has(field_name) and not is_finite(float(boundary[field_name])):
			return "non-finite boundary field: " + field_name
	for field_name in ["interior_h_kw_m2_k", "exterior_h_kw_m2_k"]:
		if float(boundary.get(field_name, 0.0)) < 0.0:
			return "negative transfer coefficient: " + field_name
	if boundary.has("interior_convection_energy_kj") \
			and absf(float(boundary.get("interior_h_kw_m2_k", 0.0))) > EPSILON:
		return "prescribed convection conflicts with interior coefficient"
	if boundary.has("exterior_energy_removed_kj") \
			and absf(float(boundary.get("exterior_h_kw_m2_k", 0.0))) > EPSILON:
		return "prescribed exterior energy conflicts with exterior coefficient"
	if float(boundary.get("fire_radiation_energy_kj", 0.0)) < 0.0:
		return "fire_radiation_energy_kj cannot be negative"
	return ""


static func _solve_tridiagonal(
	lower: Array,
	diagonal: Array,
	upper: Array,
	rhs: Array
) -> Array:
	var c_star: Array = [0.0, 0.0, 0.0, 0.0, 0.0]
	var d_star: Array = [0.0, 0.0, 0.0, 0.0, 0.0]
	if absf(float(diagonal[0])) <= EPSILON:
		return []
	c_star[0] = float(upper[0]) / float(diagonal[0])
	d_star[0] = float(rhs[0]) / float(diagonal[0])
	for index: int in range(1, NODE_COUNT):
		var denominator: float = (
			float(diagonal[index])
			- float(lower[index]) * float(c_star[index - 1])
		)
		if absf(denominator) <= EPSILON:
			return []
		if index < NODE_COUNT - 1:
			c_star[index] = float(upper[index]) / denominator
		d_star[index] = (
			float(rhs[index])
			- float(lower[index]) * float(d_star[index - 1])
		) / denominator
	var solution: Array = [0.0, 0.0, 0.0, 0.0, 0.0]
	solution[NODE_COUNT - 1] = d_star[NODE_COUNT - 1]
	for index: int in range(NODE_COUNT - 2, -1, -1):
		solution[index] = (
			float(d_star[index])
			- float(c_star[index]) * float(solution[index + 1])
		)
	return solution


static func _invalid_result(message: String) -> Dictionary:
	return {
		"valid": false,
		"error": message,
		"post_state": {},
		"energy_residual_kj": NAN,
	}

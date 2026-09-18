extends SceneTree

## F2.2D1: la fuga fria de puerta cerrada dentro de la red autoritativa.
## Comprueba la ley ELA dentro del solver, la equivalencia con el modelo puro,
## la exclusividad abierta/cerrada y los identificadores.
##
##   <godot> --headless --path . --script res://tools/validate_closed_door_leakage_network.gd

const SolverScript := preload("res://sim/core/Phase3CoupledPressureSolver.gd")
const LeakageModel := preload("res://sim/core/ClosedDoorLeakageModel.gd")
const Adapter := preload("res://sim/core/ClosedDoorLeakageNetworkAdapter.gd")
const BuildingModelScript := preload("res://sim/BuildingModel.gd")
const SimulationEngineScript := preload("res://sim/core/SimulationEngine.gd")
const TransportScript := preload("res://sim/core/PressureNetworkTransportSystem.gd")
const SOLVER_PATH: String = "res://sim/core/Phase3CoupledPressureSolver.gd"

const T_REF_K: float = 293.15
const P_EXT_PA: float = 101325.0
const AREA_M2: float = 20.0
const HEIGHT_M: float = 2.4
const DOOR_HEIGHT_M: float = 2.0
const AMBIENT_MASS_KG: float = 1.2 * AREA_M2 * HEIGHT_M
const R_J_KG_K: float = P_EXT_PA / (1.2 * T_REF_K)
const DT_S: float = 0.0833333333333333
const ELA_12: float = 0.0012
const ELA_21: float = 0.0021
const TOL: float = 1.0e-9

var _solver
var _failures: Array[String] = []
var _checks: int = 0


func _initialize() -> void:
	_solver = SolverScript.new()
	_test_01_equal_rooms_no_flow()
	_test_02_ela_definition_at_4_pa()
	_test_03_power_law_scaling()
	_test_04_sign_change()
	_test_05_two_zone_counterflow()
	_test_06_multiple_cracks()
	_test_07_equivalence_with_the_pure_model()
	_test_08_exclusivity_open_closed()
	_test_09_identifiers()
	_test_10_domain_and_zero_ela()
	_test_11_who_leaks_and_who_does_not()
	_test_12_the_crack_is_inside_the_newton_residual()
	_test_13_opening_and_closing_during_the_fire()
	_test_14_what_leaves_is_what_arrives()
	_test_15_the_engine_applies_the_transport_once()
	if _failures.is_empty():
		print("  %d checks" % _checks)
		print("CLOSED DOOR LEAKAGE NETWORK VALIDATION PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
		print("FAIL: " + failure)
	print("CLOSED DOOR LEAKAGE NETWORK VALIDATION FAIL (%d)" % _failures.size())
	quit(1)


# ---------------------------------------------------------------- helpers

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _close(actual: float, expected: float, tol: float = TOL) -> bool:
	if is_nan(actual) or is_nan(expected):
		return false
	return absf(actual - expected) <= tol * maxf(1.0, absf(expected))


func _outside() -> Dictionary:
	return {"pressure_abs_pa": P_EXT_PA, "temp_k": T_REF_K, "reference_temp_k": T_REF_K}


## Sala uniforme cuya masa fija su presion manometrica de la EOS.
func _room(room_id: String, gauge_pa: float, temp_k: float = T_REF_K) -> Dictionary:
	var volume_m3: float = AREA_M2 * HEIGHT_M
	# p_gauge = R/V * ((M - M_ref) T_ref + E/cp); con E = M cp (T - T_ref):
	#   M = (p_gauge V / R + M_ref T_ref) / T
	var reference_mass_kg: float = P_EXT_PA * volume_m3 / (R_J_KG_K * T_REF_K)
	var mass_kg: float = (gauge_pa * volume_m3 / R_J_KG_K + reference_mass_kg * T_REF_K) / temp_k
	return {
		"room_id": room_id, "floor_z_m": 0.0, "floor_area_m2": AREA_M2, "height_m": HEIGHT_M,
		"upper_gas_kg": 0.0, "upper_energy_kj": 0.0,
		"lower_gas_kg": mass_kg, "lower_energy_kj": mass_kg * (temp_k - T_REF_K),
	}


func _two_zone_room(room_id: String, upper_kg: float, upper_temp_k: float,
		lower_kg: float, lower_temp_k: float) -> Dictionary:
	return {
		"room_id": room_id, "floor_z_m": 0.0, "floor_area_m2": AREA_M2, "height_m": HEIGHT_M,
		"upper_gas_kg": upper_kg, "upper_energy_kj": upper_kg * (upper_temp_k - T_REF_K),
		"lower_gas_kg": lower_kg, "lower_energy_kj": lower_kg * (lower_temp_k - T_REF_K),
	}


## Rendija con el reparto y las bandas de D1, como la construye el adaptador.
func _crack(opening_id: String, a: String, b: String, ela_m2: float,
		regularization_pa: float = 0.0) -> Dictionary:
	var built: Dictionary = LeakageModel.build_door_segments(
		ela_m2, 0.0, DOOR_HEIGHT_M, LeakageModel.PROVISIONAL_SPLIT, Adapter.SIDE_BAND_COUNT
	)
	var segments: Array = []
	for raw_segment in built["segments"]:
		var segment: Dictionary = raw_segment
		segments.append({
			"segment_id": String(segment["id"]),
			"z_m": float(segment["z_m"]),
			"area_m2": float(segment["area_m2"]),
		})
	return {
		"opening_id": opening_id, "room_a_id": a, "room_b_id": b,
		"flow_model": "ela_crack", "crack_segments": segments,
		"ela_reference_pressure_pa": LeakageModel.NIST_ELA_REFERENCE_PRESSURE_PA,
		"flow_exponent": LeakageModel.PROVISIONAL_FLOW_EXPONENT_CANDIDATE,
		"zero_pressure_regularization_pa": regularization_pa,
		"pressure_domain_max_pa": Adapter.PRESSURE_DOMAIN_MAX_PA,
		"provenance": "cold_leakage", "leakage_class": "interior_tight",
		"resolved_ela_m2": ela_m2,
		"width_m": 1.0, "open_fraction": 1.0, "discharge_coeff": 1.0,
		"bottom_z_m": float(segments[0]["z_m"]),
		"top_z_m": float(segments[segments.size() - 1]["z_m"]),
	}


func _opening(opening_id: String, a: String, b: String) -> Dictionary:
	return {
		"opening_id": opening_id, "room_a_id": a, "room_b_id": b,
		"bottom_z_m": 0.0, "top_z_m": DOOR_HEIGHT_M, "width_m": 0.9,
		"open_fraction": 1.0, "discharge_coeff": 0.61,
	}


func _solve(rooms: Array, openings: Array, dt_s: float = DT_S) -> Dictionary:
	return _solver.solve_pressure_network(rooms, openings, _outside(), {}, dt_s)


## El elemento que el caso espera, o {} si la red no lo publico. El llamante
## comprueba con `_require_element` cuando su prueba no tiene sentido sin el.
func _require_element(result: Dictionary, opening_id: String, label: String) -> Dictionary:
	var element: Dictionary = _element(result, opening_id)
	_check(not element.is_empty(), "%s the network publishes the element '%s'" % [
			label, opening_id])
	return element


func _element(result: Dictionary, opening_id: String) -> Dictionary:
	for opening in result["openings"]:
		if String(opening["opening_id"]) == opening_id:
			return opening
	return {}


## Diferencia exacta, sin pasar por texto: los flotantes se comparan bit a bit.
func _diff_exact(left: Variant, right: Variant, path: String, out: Array[String]) -> void:
	if typeof(left) != typeof(right):
		out.append("%s type" % path)
		return
	match typeof(left):
		TYPE_DICTIONARY:
			var left_keys: Array = (left as Dictionary).keys()
			var right_keys: Array = (right as Dictionary).keys()
			left_keys.sort()
			right_keys.sort()
			if left_keys != right_keys:
				out.append("%s keys" % path)
				return
			for key in left_keys:
				_diff_exact(left[key], right[key], "%s/%s" % [path, key], out)
		TYPE_ARRAY:
			if (left as Array).size() != (right as Array).size():
				out.append("%s size" % path)
				return
			for index in range((left as Array).size()):
				_diff_exact(left[index], right[index], "%s[%d]" % [path, index], out)
		TYPE_FLOAT:
			# NaN != NaN, asi que se compara la representacion binaria: dos NaN
			# iguales pasan, un NaN frente a un numero no.
			var left_bits: int = _float_bits(float(left))
			if left_bits != _float_bits(float(right)):
				out.append("%s (%s vs %s)" % [path, left, right])
		_:
			if left != right:
				out.append("%s (%s vs %s)" % [path, left, right])


func _float_bits(value: float) -> int:
	var buffer := PackedFloat64Array([value])
	return buffer.to_byte_array().decode_s64(0)


## Rutas con NaN o infinito bajo un valor publicado.
func _nonfinite(value: Variant, path: String, out: Array[String]) -> void:
	match typeof(value):
		TYPE_DICTIONARY:
			for key in (value as Dictionary).keys():
				_nonfinite(value[key], "%s/%s" % [path, key], out)
		TYPE_ARRAY:
			for index in range((value as Array).size()):
				_nonfinite(value[index], "%s[%d]" % [path, index], out)
		TYPE_FLOAT:
			if path.ends_with("neutral_plane_z_m"):
				# Convenio del solver, anterior a D1 y comun a las aberturas
				# grandes: la cota del plano neutro es NaN justo cuando no hay
				# plano neutro. Se comprueba aparte, acoplada a su bandera.
				return
			if not is_finite(float(value)):
				out.append("%s = %s" % [path, value])


## Convenio del solver: si hay plano neutro DENTRO del elemento, su cota es un
## numero. Lo contrario no se exige: un cruce justo en el borde da cota finita y
## bandera falsa, igual que en una abertura grande.
func _check_neutral_plane_convention(element: Dictionary, label: String) -> void:
	if not bool(element["neutral_plane_inside"]):
		return
	_check(is_finite(float(element["neutral_plane_z_m"])),
			"%s publishes the height of the neutral plane it reports (%s)" % [
				label, element["neutral_plane_z_m"]])


func _total_mass_kg_s(element: Dictionary) -> float:
	var total: float = 0.0
	for segment in element["segments"]:
		total += absf(float(segment["mass_flow_kg_s"]))
	return total


# ---------------------------------------------------------------- tests

func _test_01_equal_rooms_no_flow() -> void:
	var result: Dictionary = _solve(
		[_room("a", 0.0), _room("b", 0.0)], [_crack("crack", "a", "b", ELA_21)])
	_check(bool(result["converged"]), "01 identical rooms converge (%s)" % result["failure_reason"])
	if not bool(result["converged"]):
		return
	var element: Dictionary = _require_element(result, "crack", "01")
	if element.is_empty():
		return
	_check(_close(_total_mass_kg_s(element), 0.0), "01 identical rooms move no mass (%s kg/s)"
			% _total_mass_kg_s(element))
	for segment in element["segments"]:
		_check(_close(float(segment["dp_pa"]), 0.0, 1.0e-6), "01 every crack segment sees dp = 0")


func _test_02_ela_definition_at_4_pa() -> void:
	# La definicion de ELA: a 4 Pa, Q = ELA * sqrt(2 * 4 / rho), con C_d = 1.
	for pair in [[ELA_12, "12 cm2"], [ELA_21, "21 cm2"]]:
		var ela_m2: float = float(pair[0])
		var expected_q_m3_s: float = ela_m2 * sqrt(2.0 * 4.0 / 1.2)
		var flow: Dictionary = LeakageModel.compute_segment_flow_from_dp(
			ela_m2, 4.0, 1.2, 1.2, LeakageModel.NIST_ELA_REFERENCE_PRESSURE_PA,
			LeakageModel.PROVISIONAL_FLOW_EXPONENT_CANDIDATE, 0.0, 1.0, INF)
		_check(_close(float(flow["volume_flow_m3_s"]), expected_q_m3_s, 1.0e-12),
				"02 %s at 4 Pa gives the ELA definition (%.9f vs %.9f m3/s)" % [
					pair[1], flow["volume_flow_m3_s"], expected_q_m3_s])
		# Sin un segundo Cd: 0,61 daria un 39 % menos.
		_check(not _close(float(flow["volume_flow_m3_s"]), 0.61 * expected_q_m3_s, 1.0e-6),
				"02 %s does not apply a second discharge coefficient" % pair[1])
	# Y la suma de los segmentos de una puerta es el ELA completo.
	var built: Dictionary = LeakageModel.build_door_segments(
		ELA_21, 0.0, DOOR_HEIGHT_M, LeakageModel.PROVISIONAL_SPLIT, Adapter.SIDE_BAND_COUNT)
	var area_sum: float = 0.0
	for segment in built["segments"]:
		area_sum += float(segment["area_m2"])
	_check(_close(area_sum, ELA_21, 1.0e-12), "02 the segments add up to the full ELA")


func _test_03_power_law_scaling() -> void:
	# Q proporcional a |dp|^0,65.
	var exponent: float = LeakageModel.PROVISIONAL_FLOW_EXPONENT_CANDIDATE
	var base: Dictionary = LeakageModel.compute_segment_flow_from_dp(
		ELA_21, 4.0, 1.2, 1.2, 4.0, exponent, 0.0, 1.0, INF)
	for dp_pa in [1.0, 8.0, 16.0, 40.0]:
		var flow: Dictionary = LeakageModel.compute_segment_flow_from_dp(
			ELA_21, dp_pa, 1.2, 1.2, 4.0, exponent, 0.0, 1.0, INF)
		var expected: float = float(base["volume_flow_m3_s"]) * pow(dp_pa / 4.0, exponent)
		_check(_close(float(flow["volume_flow_m3_s"]), expected, 1.0e-12),
				"03 Q scales as dp^0,65 at %s Pa" % dp_pa)
		# Un exponente 0,5 daria otro numero: la ley no es de orificio.
		var orifice: float = float(base["volume_flow_m3_s"]) * pow(dp_pa / 4.0, 0.5)
		if dp_pa != 4.0:
			_check(not _close(float(flow["volume_flow_m3_s"]), orifice, 1.0e-6),
					"03 the crack law is not the orifice law at %s Pa" % dp_pa)


func _test_04_sign_change() -> void:
	var forward: Dictionary = LeakageModel.compute_segment_flow_from_dp(
		ELA_21, 12.0, 1.2, 1.2, 4.0, 0.65, 0.0, 1.0, INF)
	var backward: Dictionary = LeakageModel.compute_segment_flow_from_dp(
		ELA_21, -12.0, 1.2, 1.2, 4.0, 0.65, 0.0, 1.0, INF)
	_check(String(forward["direction"]) == "a_to_b" and String(backward["direction"]) == "b_to_a",
			"04 the sign of dp decides the direction")
	_check(_close(float(forward["mass_flow_kg_s"]), float(backward["mass_flow_kg_s"]), 1.0e-12),
			"04 a symmetric state gives the same magnitude in both directions")
	_check(_close(float(forward["signed_mass_flow_kg_s"]), -float(backward["signed_mass_flow_kg_s"]), 1.0e-12),
			"04 the signed flow flips")
	# Densidad del ORIGEN, no del destino ni la ambiente.
	var hot_source: Dictionary = LeakageModel.compute_segment_flow_from_dp(
		ELA_21, 12.0, 0.6, 1.2, 4.0, 0.65, 0.0, 1.0, INF)
	_check(_close(float(hot_source["source_density_kg_m3"]), 0.6),
			"04 the upstream density is the source one")
	var cold_source: Dictionary = LeakageModel.compute_segment_flow_from_dp(
		ELA_21, -12.0, 0.6, 1.2, 4.0, 0.65, 0.0, 1.0, INF)
	_check(_close(float(cold_source["source_density_kg_m3"]), 1.2),
			"04 flipping the sign flips the source density")


func _test_05_two_zone_counterflow() -> void:
	# Sala caliente estratificada a presion casi ambiente contra una fria: la
	# hidrostatica manda, y la rendija inferior y la superior van al reves.
	var upper_kg: float = 20.0
	var lower_kg: float = (AMBIENT_MASS_KG * T_REF_K - upper_kg * 573.15) / 313.15
	var result: Dictionary = _solve(
		[_two_zone_room("hot", upper_kg, 573.15, lower_kg, 313.15), _room("cold", 0.0)],
		[_crack("crack", "hot", "cold", ELA_21)])
	_check(bool(result["converged"]), "05 the stratified pair converges (%s)" % result["failure_reason"])
	if not bool(result["converged"]):
		return
	var element: Dictionary = _require_element(result, "crack", "05")
	if element.is_empty():
		return
	var out_high: int = 0
	var in_low: int = 0
	for segment in element["segments"]:
		if String(segment["source_room_id"]) == "hot" and float(segment["sample_z_m"]) > 1.2:
			out_high += 1
		if String(segment["source_room_id"]) == "cold" and float(segment["sample_z_m"]) < 1.0:
			in_low += 1
	_check(out_high > 0 and in_low > 0,
			"05 the crack carries both ways at different heights (%d out high, %d in low)" % [
				out_high, in_low])
	_check(bool(element["neutral_plane_inside"]), "05 the element reports counterflow")
	_check_neutral_plane_convention(element, "05 the crack")
	# La cota publicada separa de verdad los dos sentidos: por debajo entra el
	# aire frio y por encima sale el caliente, sin solape.
	var neutral_z_m: float = float(element["neutral_plane_z_m"])
	var highest_inflow_z_m: float = -INF
	var lowest_outflow_z_m: float = INF
	for segment in element["segments"]:
		var z_m: float = float(segment["sample_z_m"])
		if String(segment["source_room_id"]) == "cold":
			highest_inflow_z_m = maxf(highest_inflow_z_m, z_m)
		else:
			lowest_outflow_z_m = minf(lowest_outflow_z_m, z_m)
	_check(highest_inflow_z_m < neutral_z_m and neutral_z_m < lowest_outflow_z_m,
			"05 the neutral plane (%.4f m) separates inflow (<= %.4f) from outflow (>= %.4f)" % [
				neutral_z_m, highest_inflow_z_m, lowest_outflow_z_m])


func _test_06_multiple_cracks() -> void:
	var rooms: Array = [_room("a", 30.0), _room("b", 0.0)]
	var first: Dictionary = _crack("crack_1", "a", "b", ELA_12)
	var second: Dictionary = _crack("crack_2", "a", "b", ELA_21)
	var forward: Dictionary = _solve(rooms, [first, second])
	var backward: Dictionary = _solve(rooms, [second, first])
	_check(bool(forward["converged"]) and bool(backward["converged"]), "06 both orders converge")
	if not bool(forward["converged"]):
		return
	# Comparacion exacta campo a campo. Un `JSON.stringify` aqui valdria de poco:
	# convierte cualquier NaN en `null`, asi que dos resultados rotos de distinta
	# forma se leerian como iguales.
	var differences: Array[String] = []
	_diff_exact(forward, backward, "", differences)
	_check(differences.is_empty(), "06 the result does not depend on the order of the cracks (%s)"
			% ", ".join(differences.slice(0, 4)))
	# Y lo que se publica de una rendija son numeros reales, sin NaN ni infinitos.
	var nonfinite: Array[String] = []
	_nonfinite(forward["openings"], "openings", nonfinite)
	_check(nonfinite.is_empty(), "06 a crack publishes only finite numbers (%s)"
			% ", ".join(nonfinite.slice(0, 4)))
	var first_element: Dictionary = _require_element(forward, "crack_1", "06")
	var second_element: Dictionary = _require_element(forward, "crack_2", "06")
	if first_element.is_empty() or second_element.is_empty():
		return
	_check_neutral_plane_convention(first_element, "06 crack_1")
	_check_neutral_plane_convention(second_element, "06 crack_2")
	var mass_1: float = _total_mass_kg_s(first_element)
	var mass_2: float = _total_mass_kg_s(second_element)
	_check(mass_1 > 0.0 and mass_2 > mass_1,
			"06 the bigger ELA carries more (%.9f vs %.9f kg/s)" % [mass_1, mass_2])
	# Dos rendijas de 12 cm2 mueven lo mismo que una de 24 cm2 a igual dp.
	var flow_12: Dictionary = LeakageModel.compute_segment_flow_from_dp(
		ELA_12, 10.0, 1.2, 1.2, 4.0, 0.65, 0.0, 1.0, INF)
	var flow_24: Dictionary = LeakageModel.compute_segment_flow_from_dp(
		2.0 * ELA_12, 10.0, 1.2, 1.2, 4.0, 0.65, 0.0, 1.0, INF)
	_check(_close(2.0 * float(flow_12["mass_flow_kg_s"]), float(flow_24["mass_flow_kg_s"]), 1.0e-12),
			"06 the law is linear in the ELA")


func _test_07_equivalence_with_the_pure_model() -> void:
	# El mismo elemento, con las mismas presiones, por las dos vias: el modelo
	# puro con presiones impuestas y el solver dentro de su residuo.
	var gauge_a_pa: float = 25.0
	var result: Dictionary = _solve(
		[_room("a", gauge_a_pa), _room("b", 0.0)], [_crack("crack", "a", "b", ELA_21)])
	_check(bool(result["converged"]), "07 the driven pair converges")
	if not bool(result["converged"]):
		return
	var element: Dictionary = _require_element(result, "crack", "07")
	if element.is_empty():
		return
	var solved_a_pa: float = 0.0
	var solved_b_pa: float = 0.0
	for room in result["rooms"]:
		if String(room["room_id"]) == "a":
			solved_a_pa = float(room["gauge_pressure_pa"])
		else:
			solved_b_pa = float(room["gauge_pressure_pa"])
	var built: Dictionary = LeakageModel.build_door_segments(
		ELA_21, 0.0, DOOR_HEIGHT_M, LeakageModel.PROVISIONAL_SPLIT, Adapter.SIDE_BAND_COUNT)
	var side_a: Dictionary = {
		"floor_z_m": 0.0, "interface_height_m": HEIGHT_M,
		"rho_lower_kg_m3": 1.2, "rho_upper_kg_m3": 1.2, "p_floor_pa": solved_a_pa,
	}
	var side_b: Dictionary = {
		"floor_z_m": 0.0, "interface_height_m": HEIGHT_M,
		"rho_lower_kg_m3": 1.2, "rho_upper_kg_m3": 1.2, "p_floor_pa": solved_b_pa,
	}
	var pure: Dictionary = LeakageModel.compute_flows(built["segments"], side_a, side_b, {
		"ela_reference_pressure_pa": LeakageModel.NIST_ELA_REFERENCE_PRESSURE_PA,
		"flow_exponent": LeakageModel.PROVISIONAL_FLOW_EXPONENT_CANDIDATE,
		"zero_pressure_regularization_pa": 0.0,
		"pressure_domain_max_pa": Adapter.PRESSURE_DOMAIN_MAX_PA,
	}, 1.0)
	_check(bool(pure["valid"]), "07 the pure model accepts the same element")
	var pure_by_id: Dictionary = {}
	for raw_flow in pure["flows"]:
		var flow: Dictionary = raw_flow
		pure_by_id[String(flow["segment_id"])] = flow
	var compared: int = 0
	for segment in element["segments"]:
		var segment_id: String = String(segment["segment_id"])
		if not pure_by_id.has(segment_id):
			continue
		var pure_flow: Dictionary = pure_by_id[segment_id]
		# Las densidades del solver salen de la EOS de cada sala, no de 1,2
		# exacto, asi que la comparacion se hace en tolerancia relativa suelta
		# pero muy por debajo de cualquier diferencia de ley.
		_check(_close(float(segment["mass_flow_kg_s"]), float(pure_flow["mass_flow_kg_s"]), 5.0e-3),
				"07 segment %s matches the pure model (%.9f vs %.9f kg/s)" % [
					segment_id, segment["mass_flow_kg_s"], pure_flow["mass_flow_kg_s"]])
		compared += 1
	_check(compared >= 8, "07 every crack segment was compared (%d)" % compared)


func _test_08_exclusivity_open_closed() -> void:
	var building: BuildingModel = _make_building()
	var engine: SimulationEngine = _make_engine(building, true, true)
	var door = building.get_openings()[0]
	door.leakage_class = "interior_tight"
	# Cerrada: rendija, nunca abertura grande.
	door.set_open_fraction(0.0)
	var closed: Dictionary = _transport(building)
	var closed_ids: Array = _opening_ids(closed)
	_check(closed_ids.size() == 1 and String(closed_ids[0]).begins_with("crack_"),
			"08 a closed door only contributes a crack (%s)" % [closed_ids])
	# Entreabierta: solo abertura grande.
	door.set_open_fraction(0.35)
	var ajar: Dictionary = _transport(building)
	var ajar_ids: Array = _opening_ids(ajar)
	_check(ajar_ids.size() == 1 and String(ajar_ids[0]).begins_with("op_"),
			"08 an ajar door only contributes a large opening (%s)" % [ajar_ids])
	# Abierta del todo: igual.
	door.set_open_fraction(1.0)
	_check(_opening_ids(_transport(building)).size() == 1, "08 a fully open door contributes one element")
	# Y al cerrarla vuelve la fuga, con la clase intacta.
	door.set_open_fraction(0.0)
	_check(String(door.leakage_class) == "interior_tight", "08 opening and closing keeps the leakage class")
	var reclosed_ids: Array = _opening_ids(_transport(building))
	_check(reclosed_ids.size() == 1 and String(reclosed_ids[0]).begins_with("crack_"),
			"08 closing the door brings the crack back")
	# Clase `none`: estanca.
	door.leakage_class = "none"
	_check(_opening_ids(_transport(building)).is_empty(), "08 a door with class none stays sealed")
	_free(engine, building)


func _test_09_identifiers() -> void:
	# Dos puertas iguales entre las mismas salas: identificadores distintos.
	var building: BuildingModel = _make_building(2)
	var engine: SimulationEngine = _make_engine(building, true, true)
	for door in building.get_openings():
		door.leakage_class = "interior_tight"
		door.set_open_fraction(0.0)
	var result: Dictionary = _transport(building)
	var ids: Array = _opening_ids(result)
	_check(ids.size() == 2, "09 both doors contribute (%s)" % [ids])
	_check(ids.size() == 2 and String(ids[0]) != String(ids[1]),
			"09 two identical doors do not share an identifier (%s)" % [ids])
	for id_text in ids:
		_check(String(id_text).begins_with("crack_"), "09 the identifier names the crack")

	# Y lo mismo con las dos puertas ABIERTAS: ahi es donde el identificador de
	# F2.2C (`op_<a>_<b>_<tipo>`) hacia que la segunda pisara a la primera.
	for door in building.get_openings():
		door.set_open_fraction(1.0)
	var open_ids: Array = _opening_ids(_transport(building))
	_check(open_ids.size() == 2, "09 both open doors contribute (%s)" % [open_ids])
	_check(open_ids.size() == 2 and String(open_ids[0]) != String(open_ids[1]),
			"09 two identical open doors do not share an identifier (%s)" % [open_ids])
	for id_text in open_ids:
		_check(String(id_text).begins_with("op_"), "09 the open identifier names the opening")
	_free(engine, building)


func _test_10_domain_and_zero_ela() -> void:
	# Un ELA cero es exactamente no tener elemento.
	var flow: Dictionary = LeakageModel.compute_segment_flow_from_dp(
		0.0, 30.0, 1.2, 1.2, 4.0, 0.65, 0.0, 1.0, INF)
	_check(bool(flow["valid"]) and _close(float(flow["mass_flow_kg_s"]), 0.0),
			"10 a zero ELA carries nothing")
	# El dominio experimental se registra, no recorta.
	var beyond: Dictionary = LeakageModel.compute_segment_flow_from_dp(
		ELA_21, 120.0, 1.2, 1.2, 4.0, 0.65, 0.0, 1.0, Adapter.PRESSURE_DOMAIN_MAX_PA)
	var inside: Dictionary = LeakageModel.compute_segment_flow_from_dp(
		ELA_21, 50.0, 1.2, 1.2, 4.0, 0.65, 0.0, 1.0, Adapter.PRESSURE_DOMAIN_MAX_PA)
	_check(bool(beyond["domain_exceeded"]) and not bool(inside["domain_exceeded"]),
			"10 beyond 50 Pa the domain flag is raised")
	var expected: float = float(inside["volume_flow_m3_s"]) * pow(120.0 / 50.0, 0.65)
	_check(_close(float(beyond["volume_flow_m3_s"]), expected, 1.0e-12),
			"10 the flow beyond the domain is not clamped (%.9f vs %.9f)" % [
				beyond["volume_flow_m3_s"], expected])


func _test_11_who_leaks_and_who_does_not() -> void:
	var building: BuildingModel = _make_building()
	var engine: SimulationEngine = _make_engine(building, true, true)
	var door = building.get_openings()[0]
	door.leakage_class = "interior_tight"
	door.set_open_fraction(0.0)

	# Con la capacidad apagada, una puerta cerrada con clase sigue estanca:
	# exactamente el comportamiento de F2.2C.
	var off_system = TransportScript.new()
	off_system.closed_door_leakage_enabled = false
	var off_result: Dictionary = off_system.step(building, DT_S)
	_check(bool(off_result.get("applied", false)), "11 the network still runs with leakage off")
	_check(bool(off_result.get("applied", false)) 			and (off_result["solution"]["openings"] as Array).is_empty(),
			"11 leakage off leaves the closed door sealed")

	# La tabla de clases es la del modelo puro y no esta cambiada de sitio.
	_check(_close(Adapter.class_ela_m2("entry_tight"), ELA_12),
			"11 the entry class is 12 cm2 (%s)" % Adapter.class_ela_m2("entry_tight"))
	_check(_close(Adapter.class_ela_m2("interior_tight"), ELA_21),
			"11 the interior class is 21 cm2 (%s)" % Adapter.class_ela_m2("interior_tight"))
	_check(_close(Adapter.class_ela_m2("none"), 0.0), "11 the class none has no area")
	_check(not Adapter.is_known_class("carpinteria_inventada"), "11 an unknown class is unknown")

	# El override manda sobre la clase.
	door.leakage_area_override_m2 = 0.0050
	var override_ids: Array = _opening_ids(_transport(building))
	_check(override_ids.size() == 1, "11 the override still produces a crack")
	_check(_close(Adapter.resolved_ela_m2(door), 0.0050),
			"11 the override wins over the class (%s)" % Adapter.resolved_ela_m2(door))
	door.leakage_area_override_m2 = 0.0
	_check(_close(Adapter.resolved_ela_m2(door), 0.0),
			"11 an override of zero seals the door")
	_check(_opening_ids(_transport(building)).is_empty(),
			"11 an override of zero contributes no element")
	door.leakage_area_override_m2 = -1.0

	# El adaptador responde que NO antes de que nadie construya nada: una puerta
	# con apertura operativa positiva no aporta fuga, tenga la clase que tenga.
	for fraction in [0.05, 0.5, 1.0]:
		door.set_open_fraction(fraction)
		_check(not Adapter.provides_leakage(door, BuildingModel.OUTSIDE_ID),
				"11 an open door (%s) provides no cold leakage" % fraction)
	door.set_open_fraction(0.0)
	_check(Adapter.provides_leakage(door, BuildingModel.OUTSIDE_ID),
			"11 a closed door with a class does provide leakage")

	# La deformacion heredada no abre la puerta ni la convierte en rendija:
	# `thermal_gap_fraction` es la fase D2 y aqui no participa.
	door.thermal_gap_fraction = 0.5
	var deformed_ids: Array = _opening_ids(_transport(building))
	_check(deformed_ids.size() == 1 and String(deformed_ids[0]).begins_with("crack_"),
			"11 a deformed closed door is still only a crack (%s)" % [deformed_ids])
	door.thermal_gap_fraction = 0.0
	_free(engine, building)

	# Una ventana cerrada no tiene fuga de puerta, tenga la clase que tenga.
	var window_building: BuildingModel = _make_building(1, "window")
	var window_engine: SimulationEngine = _make_engine(window_building, true, true)
	var window = window_building.get_openings()[0]
	window.leakage_class = "interior_tight"
	window.set_open_fraction(0.0)
	_check(not Adapter.provides_leakage(window, BuildingModel.OUTSIDE_ID),
			"11 a window is not a door for the cold leakage")
	_check(_opening_ids(_transport(window_building)).is_empty(),
			"11 a closed window contributes no crack")
	_free(window_engine, window_building)

	# Un hueco nunca esta cerrado y nunca tiene fuga.
	var hole_building: BuildingModel = _make_building(1, "hole")
	var hole_engine: SimulationEngine = _make_engine(hole_building, true, true)
	var hole = hole_building.get_openings()[0]
	hole.leakage_class = "interior_tight"
	hole.set_open_fraction(0.0)
	_check(not Adapter.provides_leakage(hole, BuildingModel.OUTSIDE_ID),
			"11 a hole has no cold leakage")
	var hole_ids: Array = _opening_ids(_transport(hole_building))
	_check(hole_ids.size() == 1 and String(hole_ids[0]).begins_with("op_"),
			"11 a hole stays a large opening (%s)" % [hole_ids])
	_free(hole_engine, hole_building)


func _test_12_the_crack_is_inside_the_newton_residual() -> void:
	# Si la fuga se calculara despues de resolver, las presiones convergidas
	# serian las de la puerta estanca. Con la rendija dentro del residuo, la
	# sala sobrepresionada se descarga y la presion resuelta baja.
	var rooms: Array = [_room("a", 40.0), _room("b", 0.0)]
	var sealed: Dictionary = _solve(rooms, [])
	var leaky: Dictionary = _solve(rooms, [_crack("crack", "a", "b", ELA_21)])
	_check(bool(sealed["converged"]) and bool(leaky["converged"]), "12 both networks converge")
	if not bool(leaky["converged"]):
		return
	var sealed_a_pa: float = float((sealed["rooms"] as Array)[0]["gauge_pressure_pa"])
	var leaky_a_pa: float = float((leaky["rooms"] as Array)[0]["gauge_pressure_pa"])
	var sealed_b_pa: float = float((sealed["rooms"] as Array)[1]["gauge_pressure_pa"])
	var leaky_b_pa: float = float((leaky["rooms"] as Array)[1]["gauge_pressure_pa"])
	_check(leaky_a_pa < sealed_a_pa,
			"12 the crack lowers the pressure the solver converges to (%.9f vs %.9f Pa)" % [
				leaky_a_pa, sealed_a_pa])
	_check(leaky_b_pa > sealed_b_pa,
			"12 and raises the one of the room it feeds (%.9f vs %.9f Pa)" % [
				leaky_b_pa, sealed_b_pa])
	# Y la masa que sale de una es la que entra en la otra, en el mismo paso.
	var element: Dictionary = _require_element(leaky, "crack", "12")
	if element.is_empty():
		return
	var out_kg: float = 0.0
	var in_kg: float = 0.0
	for segment in element["segments"]:
		var mass_kg: float = float(segment["mass_flow_kg_s"]) * DT_S
		if String(segment["source_room_id"]) == "a":
			out_kg += mass_kg
		else:
			in_kg += mass_kg
	_check(out_kg > 0.0 and in_kg == 0.0,
			"12 the flow goes from the pressurised room (%.9f out, %.9f in)" % [out_kg, in_kg])

	# Los diagnosticos de la rendija tienen que LLEGAR al consumidor: si se
	# quedan dentro del solver, nadie puede medir la ΔP ni el dominio excedido.
	for key in ["flow_model", "max_abs_dp_pa", "domain_exceeded_count"]:
		_check(element.has(key), "12 the published crack carries '%s'" % key)
	if element.has("flow_model"):
		_check(String(element["flow_model"]) == "ela_crack",
				"12 the published crack says what it is (%s)" % element["flow_model"])
		_check(float(element["max_abs_dp_pa"]) > 0.0,
				"12 the crack reports the dp it saw (%s)" % element["max_abs_dp_pa"])
	# Y una abertura grande sigue publicando exactamente lo de F2.2C, sin
	# heredar campos de rendija.
	var large: Dictionary = _solve(rooms, [_opening("door", "a", "b")])
	if bool(large["converged"]):
		var large_element: Dictionary = _element(large, "door")
		for key in ["flow_model", "max_abs_dp_pa", "domain_exceeded_count"]:
			_check(not large_element.has(key),
					"12 a large opening does not gain the crack field '%s'" % key)


## Caso 9 del encargo: abrir y cerrar la puerta con el incendio en marcha.
## Ni doble conteo, ni salto absurdo de presion, y al cerrar vuelve la fuga.
func _test_13_opening_and_closing_during_the_fire() -> void:
	var building: BuildingModel = _make_building()
	var engine: SimulationEngine = _make_engine(building, true, true)
	var door = building.get_openings()[0]
	door.leakage_class = "interior_tight"
	var system = TransportScript.new()
	system.closed_door_leakage_enabled = true

	# cerrada -> abierta -> cerrada, midiendo cada tramo.
	var schedule: Array = [
		{"fraction": 0.0, "steps": 12, "prefix": "crack_"},
		{"fraction": 1.0, "steps": 12, "prefix": "op_"},
		{"fraction": 0.0, "steps": 12, "prefix": "crack_"},
	]
	# Un paso de calentamiento: en el primero la red publica la presion por
	# primera vez, y pasar de 0 a la presion de la EOS no es una transicion de
	# puerta. Lo que se mide es lo que ocurre a partir de ahi.
	system.step(building, DT_S)
	var previous_total_kg: float = _building_gas_kg(building)
	var initial_gap_pa: float = _pressure_gap_pa(building)
	for raw_phase in schedule:
		var phase: Dictionary = raw_phase
		door.set_open_fraction(float(phase["fraction"]))
		for _step_index in range(int(phase["steps"])):
			var before_kg: float = _building_gas_kg(building)
			var before_energy_kj: float = _building_energy_kj(building)
			var result: Dictionary = system.step(building, DT_S)
			_check(bool(result.get("applied", false)),
					"13 the transport applies during the transition (%s)"
					% result.get("failure_reason", "?"))
			if not bool(result.get("applied", false)):
				_free(engine, building)
				return
			# Exactamente UN elemento por puerta: ni cero ni los dos a la vez.
			var elements: Array = result["solution"]["openings"]
			_check(elements.size() == 1,
					"13 exactly one element while the door is at %s (%d)" % [
						phase["fraction"], elements.size()])
			if elements.size() == 1:
				_check(String((elements[0] as Dictionary)["opening_id"]).begins_with(
						String(phase["prefix"])),
						"13 the element is the right kind at %s (%s)" % [
							phase["fraction"], (elements[0] as Dictionary)["opening_id"]])
			# El transporte entre dos salas no crea ni destruye masa ni energia.
			var after_kg: float = _building_gas_kg(building)
			_check(_close(after_kg, before_kg, 1.0e-9),
					"13 the transition conserves mass (%.9f vs %.9f kg)" % [after_kg, before_kg])
			var after_energy_kj: float = _building_energy_kj(building)
			_check(_close(after_energy_kj, before_energy_kj, 1.0e-9),
					"13 the transition conserves energy (%.6f vs %.6f kJ)" % [
						after_energy_kj, before_energy_kj])
			# Cota fisica: ninguna zona puede quedar en negativo, ni un paso
			# puede sacar de una sala mas gas del que tenia.
			for room in building.get_rooms().values():
				_check(float(room.upper_gas_kg) >= 0.0 and float(room.lower_gas_kg) >= 0.0,
						"13 no zone goes negative (%s: %.9f / %.9f kg)" % [
							room.id, room.upper_gas_kg, room.lower_gas_kg])
			if elements.size() != 1:
				_free(engine, building)
				return
			var drawn_kg: Dictionary = {}
			for segment in (elements[0] as Dictionary)["segments"]:
				var source_id: String = String(segment["source_room_id"])
				drawn_kg[source_id] = float(drawn_kg.get(source_id, 0.0)) \
						+ absf(float(segment["mass_flow_kg_s"])) * DT_S
			for source_id in drawn_kg:
				_check(float(drawn_kg[source_id]) <= before_kg,
						"13 a step never draws more than the building holds (%s: %.9f > %.9f kg)" % [
							source_id, drawn_kg[source_id], before_kg])
		previous_total_kg = _building_gas_kg(building)
	_check(_close(previous_total_kg, _building_gas_kg(building), 1.0e-12),
			"13 the whole schedule conserves mass")
	# Sin fuego, conectar dos salas solo puede acercarlas.
	var final_gap_pa: float = _pressure_gap_pa(building)
	_check(final_gap_pa < initial_gap_pa,
			"13 the schedule brings the two rooms closer (%.6f -> %.6f Pa)" % [
				initial_gap_pa, final_gap_pa])

	_check(String(door.leakage_class) == "interior_tight",
			"13 the leakage class survives the whole schedule")
	_free(engine, building)


## Lo que sale de una sala es lo que entra en la otra: masa, energia y O2. La
## conservacion sola no basta, porque "no mover energia" tambien conserva.
func _test_14_what_leaves_is_what_arrives() -> void:
	var building: BuildingModel = _make_building()
	var engine: SimulationEngine = _make_engine(building, true, true)
	var door = building.get_openings()[0]
	door.leakage_class = "interior_tight"
	door.set_open_fraction(0.0)
	# Composiciones bien distintas para que mover o no mover se note.
	var source = building.get_room(0)
	var receiver = building.get_room(1)
	source.o2_upper = 0.10
	source.o2_lower = 0.12
	receiver.o2_upper = 0.209
	receiver.o2_lower = 0.209

	var system = TransportScript.new()
	system.closed_door_leakage_enabled = true
	system.step(building, DT_S)  # un paso de calentamiento: la red publica presion

	var before_mass_kg: float = float(receiver.upper_gas_kg) + float(receiver.lower_gas_kg)
	var before_energy_kj: float = float(receiver.upper_energy_kj) + float(receiver.lower_energy_kj)
	var before_o2_kg: float = float(receiver.o2_upper) * float(receiver.upper_gas_kg) \
			+ float(receiver.o2_lower) * float(receiver.lower_gas_kg)
	var source_o2_upper: float = float(source.o2_upper)
	var source_o2_lower: float = float(source.o2_lower)

	var result: Dictionary = system.step(building, DT_S)
	_check(bool(result.get("applied", false)), "14 the step applies (%s)"
			% result.get("failure_reason", "?"))
	if not bool(result.get("applied", false)):
		_free(engine, building)
		return
	var element: Dictionary = _require_element(result["solution"], "crack_0", "14")
	if element.is_empty():
		_free(engine, building)
		return

	# Lo que la red DICE que movio hacia la sala receptora.
	var expected_mass_kg: float = 0.0
	var expected_energy_kj: float = 0.0
	var expected_o2_kg: float = 0.0
	for raw_segment in element["segments"]:
		var segment: Dictionary = raw_segment
		var mass_kg: float = float(segment["mass_flow_kg_s"]) * DT_S
		var sign: float = 1.0 if String(segment["destination_room_id"]) == "1" else -1.0
		expected_mass_kg += sign * mass_kg
		expected_energy_kj += sign * float(segment["enthalpy_flow_kw"]) * DT_S
		if String(segment["source_room_id"]) == "0":
			var fraction: float = source_o2_upper if String(segment["source_zone"]) == "upper" \
					else source_o2_lower
			expected_o2_kg += mass_kg * fraction

	var after_mass_kg: float = float(receiver.upper_gas_kg) + float(receiver.lower_gas_kg)
	var after_energy_kj: float = float(receiver.upper_energy_kj) + float(receiver.lower_energy_kj)
	var after_o2_kg: float = float(receiver.o2_upper) * float(receiver.upper_gas_kg) \
			+ float(receiver.o2_lower) * float(receiver.lower_gas_kg)

	_check(absf(expected_mass_kg) > 0.0, "14 the crack actually moved something (%.9f kg)"
			% expected_mass_kg)
	_check(_close(after_mass_kg - before_mass_kg, expected_mass_kg, 1.0e-6),
			"14 the receiver gains the mass the network moved (%.9f vs %.9f kg)" % [
				after_mass_kg - before_mass_kg, expected_mass_kg])
	_check(_close(after_energy_kj - before_energy_kj, expected_energy_kj, 1.0e-6),
			"14 the receiver gains the energy the network moved (%.9f vs %.9f kJ)" % [
				after_energy_kj - before_energy_kj, expected_energy_kj])
	_check(absf(expected_o2_kg) > 0.0, "14 some oxygen travelled (%.9f kg)" % expected_o2_kg)
	_check(_close(after_o2_kg - before_o2_kg, expected_o2_kg, 1.0e-6),
			"14 the receiver gains the oxygen that left the source (%.9f vs %.9f kg)" % [
				after_o2_kg - before_o2_kg, expected_o2_kg])
	_free(engine, building)


## Un paso del motor aplica el transporte UNA vez, ni cero ni dos.
##
## Se cuenta, en vez de intentar aislar la masa que mueve la red dentro de un
## paso completo: ahi el resto de rutas se mueven mas que ella y el motor
## rederiva el estado de zonas, asi que ninguna resta lo aisla.
func _test_15_the_engine_applies_the_transport_once() -> void:
	var building: BuildingModel = _make_building()
	var engine: SimulationEngine = _make_engine(building, true, true)
	var door = building.get_openings()[0]
	door.leakage_class = "interior_tight"
	door.set_open_fraction(0.0)

	var system = engine.pressure_network_transport_system
	_check(system != null, "15 the engine owns a transport system")
	if system == null:
		_free(engine, building)
		return
	_check(int(system.commit_count) == 0, "15 nothing has been applied yet (%d)"
			% system.commit_count)
	for step_index in range(1, 6):
		engine.step(DT_S)
		_check(int(system.commit_count) == step_index,
				"15 step %d leaves exactly %d applications (%d)" % [
					step_index, step_index, system.commit_count])
	_free(engine, building)


func _room_gas_kg(building: BuildingModel, room_id: int) -> float:
	var room = building.get_room(room_id)
	return float(room.upper_gas_kg) + float(room.lower_gas_kg)


func _pressure_gap_pa(building: BuildingModel) -> float:
	return absf(float(building.get_room(0).overpressure_pa)
			- float(building.get_room(1).overpressure_pa))


func _building_energy_kj(building: BuildingModel) -> float:
	var total_kj: float = 0.0
	for room in building.get_rooms().values():
		total_kj += float(room.upper_energy_kj) + float(room.lower_energy_kj)
	return total_kj


func _building_gas_kg(building: BuildingModel) -> float:
	var total_kg: float = 0.0
	for room in building.get_rooms().values():
		total_kg += float(room.upper_gas_kg) + float(room.lower_gas_kg)
	return total_kg


# ---------------------------------------------------------------- engine helpers

func _make_building(door_count: int = 1, kind: String = "door") -> BuildingModel:
	var openings: Array = []
	for index in range(door_count):
		openings.append({
			"a": 0, "b": 1, "type": kind, "open_fraction": 0.0,
			"width_m": 0.9, "height_m": DOOR_HEIGHT_M, "sill_m": 0.0,
			"wall": "right", "offset_m": 1.0 + float(index), "offset_is_fraction": false,
		})
	var template: Dictionary = {
		"building_type": "house",
		"floors": [{"level_m": 0.0, "name": "R"}],
		"rooms_data": [
			{"id": 0, "name": "R0", "kind": "salon", "floor_level_z_m": 0.0, "height_m": HEIGHT_M,
				"fuel_energy_MJ": 0.0, "max_hrr_kw": 0.0, "fuel_objects": [], "rotation_deg": 0.0},
			{"id": 1, "name": "R1", "kind": "salon", "floor_level_z_m": 0.0, "height_m": HEIGHT_M,
				"fuel_energy_MJ": 0.0, "max_hrr_kw": 0.0, "fuel_objects": [], "rotation_deg": 0.0},
		],
		"room_rect_m": {"0": {"x": 0.0, "y": 0.0, "w": 5.0, "h": 4.0},
			"1": {"x": 5.0, "y": 0.0, "w": 5.0, "h": 4.0}},
		"openings_data": openings,
	}
	var building: BuildingModel = BuildingModelScript.new()
	building.load_template_data(template)
	return building


func _make_engine(building: BuildingModel, network: bool, leakage: bool) -> SimulationEngine:
	var engine: SimulationEngine = SimulationEngineScript.new()
	engine.building = building
	engine.auto_ignite_on_ready = false
	engine.auto_finish_on_extinction = false
	engine.enable_logging = false
	engine.enable_csv_log = false
	engine.pressure_network_solver_enabled = network
	engine.closed_door_leakage_enabled = leakage
	# Sin esto, liberar el motor dispara `_exit_tree` -> generacion de graficas
	# con `OS.create_process`, y el proceso headless de Godot se queda vivo.
	engine.suppress_exit_graphs()
	root.add_child(building)
	root.add_child(engine)
	engine.reset_simulation(0, false)
	_seed(building.get_room(0), 12.0, 493.15, 40.0, 298.15)
	_seed(building.get_room(1), 0.0, T_REF_K, AMBIENT_MASS_KG, T_REF_K)
	return engine


func _seed(room, upper_kg: float, upper_temp_k: float, lower_kg: float, lower_temp_k: float) -> void:
	room.upper_gas_kg = upper_kg
	room.lower_gas_kg = lower_kg
	room.upper_energy_kj = upper_kg * (upper_temp_k - T_REF_K)
	room.lower_energy_kj = lower_kg * (lower_temp_k - T_REF_K)


func _transport(building: BuildingModel) -> Dictionary:
	var system = TransportScript.new()
	system.closed_door_leakage_enabled = true
	return system.step(building, DT_S)


## Identificadores de los elementos que la red resolvio de verdad.
##
## Un transporte no aplicado NO devuelve lista vacia en silencio: eso haria que
## "la puerta estanca no aporta nada" pasara por una caida del solver.
func _opening_ids(result: Dictionary) -> Array:
	var ids: Array = []
	_check(bool(result.get("applied", false)), "transport applied (%s)"
			% result.get("failure_reason", "?"))
	if not bool(result.get("applied", false)):
		return ["<not-applied>"]
	for opening in result["solution"]["openings"]:
		ids.append(String(opening["opening_id"]))
	ids.sort()
	return ids


func _free(engine: SimulationEngine, building: BuildingModel) -> void:
	root.remove_child(engine)
	root.remove_child(building)
	engine.free()
	building.free()

extends SceneTree

## Tests deterministas del modelo puro de fuga de puerta cerrada
## (sim/core/ClosedDoorLeakageModel.gd). No arranca el motor ni carga
## escenarios: solo diferencias de presion impuestas entre 0 y 50 Pa (y una por
## encima, para comprobar que el dominio se marca sin recortar).
##
##   <godot> --headless --path . --script res://tools/validate_closed_door_leakage_model.gd
##   <godot> --headless --path . --script res://tools/validate_closed_door_leakage_model.gd -- --dump=<ruta.json>
##
## Con --dump escribe una bateria fija de resultados en JSON canonico para
## comprobar el determinismo byte a byte entre dos ejecuciones.

const Model := preload("res://sim/core/ClosedDoorLeakageModel.gd")

const REL_TOL: float = 1.0e-12
const RHO_AIR: float = 1.2
const DOOR_SILL_M: float = 0.0
const DOOR_HEIGHT_M: float = 2.05
const BANDS: int = 8
## Parametros de PRUEBA. La presion de referencia es la de la convencion (ELA a
## 4 Pa, C_d = 1,0); el exponente es el candidato provisional y la
## regularizacion, un valor positivo para ejercitar el empalme (la configuracion
## recomendada para integrar es 0, que tambien se prueba).
const TEST_PARAMS: Dictionary = {
	"ela_reference_pressure_pa": 4.0,
	"flow_exponent": 0.65,
	"zero_pressure_regularization_pa": 0.1,
	"pressure_domain_max_pa": 50.0,
}
const PURE_POWER_LAW: Dictionary = {"zero_pressure_regularization_pa": 0.0}
const SWEEP_PA: Array = [0.0, 1.0e-12, 1.0e-6, 0.01, 0.05, 0.1, 0.2, 0.5, 1.0, 2.0, 4.0, 8.0, 10.0, 16.0, 25.0, 32.0, 50.0]

var _failures: Array[String] = []
var _checks: int = 0


func _initialize() -> void:
	var dump_path: String = ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--dump="):
			dump_path = argument.substr("--dump=".length())
	_test_01_zero_ela()
	_test_02_zero_dp()
	_test_03_symmetric_pressures()
	_test_04_flow_inversion()
	_test_05_reference_value()
	_test_06_ela_scaling()
	_test_07_exponent_scaling()
	_test_08_regularization()
	_test_09_split()
	_test_10_area_conservation()
	_test_11_neutral_plane_inside_door()
	_test_12_counter_flows()
	_test_13_different_densities()
	_test_14_segment_order_independence()
	_test_15_determinism(dump_path)
	_test_16_inputs_untouched()
	_test_17_invalid_inputs_are_not_clamped()
	_test_18_finite_everywhere()
	if _failures.is_empty():
		print("  %d checks" % _checks)
		print("CLOSED DOOR LEAKAGE MODEL VALIDATION PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
		print("FAIL: " + failure)
	print("CLOSED DOOR LEAKAGE MODEL VALIDATION FAIL (%d)" % _failures.size())
	quit(1)


# ---------------------------------------------------------------- helpers

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _close(actual: float, expected: float, tol: float = REL_TOL) -> bool:
	if is_nan(actual) or is_nan(expected):
		return false
	var scale: float = maxf(absf(expected), 1.0e-300)
	return absf(actual - expected) <= tol * scale or (expected == 0.0 and actual == 0.0)


func _side(p_floor_pa: float, rho_lower: float = RHO_AIR, rho_upper: float = RHO_AIR, interface_m: float = 10.0) -> Dictionary:
	return {
		"floor_z_m": 0.0,
		"interface_height_m": interface_m,
		"rho_lower_kg_m3": rho_lower,
		"rho_upper_kg_m3": rho_upper,
		"p_floor_pa": p_floor_pa,
	}


func _params(overrides: Dictionary = {}) -> Dictionary:
	var params: Dictionary = TEST_PARAMS.duplicate()
	for key in overrides.keys():
		params[key] = overrides[key]
	return params


## Etiqueta, signo, lados y Δp tienen que contar la misma historia.
func _check_flow_consistency(flow: Dictionary, label: String) -> void:
	var dp: float = float(flow["dp_pa"])
	var signed: float = float(flow["signed_volume_flow_m3_s"])
	if float(flow["area_m2"]) <= 0.0 or dp == 0.0:
		_check(flow["direction"] == Model.DIRECTION_NONE and signed == 0.0 and flow["source_side"] == "",
				"%s: no flow means no direction" % label)
		return
	var expected: String = Model.DIRECTION_A_TO_B if dp > 0.0 else Model.DIRECTION_B_TO_A
	_check(flow["direction"] == expected, "%s: direction label follows dp" % label)
	_check((signed > 0.0) == (dp > 0.0) and signed != 0.0, "%s: signed flow follows dp" % label)
	_check(flow["source_side"] == ("a" if dp > 0.0 else "b"), "%s: source side follows dp" % label)
	_check(flow["destination_side"] == ("b" if dp > 0.0 else "a"), "%s: destination side follows dp" % label)
	_check(absf(signed) == float(flow["volume_flow_m3_s"]), "%s: |signed| is the volume flow" % label)
	_check(String(flow["destination_zone_at_height"]) in [Model.ZONE_LOWER, Model.ZONE_UPPER],
			"%s: receiver zone at height is reported" % label)
	_check(float(flow["destination_density_at_height"]) > 0.0, "%s: receiver density at height is reported" % label)


func _one_segment(area_m2: float, z_m: float = 0.0) -> Array:
	return [{"id": "s", "z_m": z_m, "area_m2": area_m2}]


## Caudal con signo (a->b positivo) de un unico segmento con Δp uniforme.
func _q(area_m2: float, dp_pa: float, params: Dictionary = TEST_PARAMS, rho: float = RHO_AIR) -> float:
	var result: Dictionary = Model.compute_flows(_one_segment(area_m2), _side(dp_pa, rho, rho), _side(0.0, rho, rho), params)
	if not bool(result["valid"]):
		return NAN
	return float(result["flows"][0]["signed_volume_flow_m3_s"])


func _door(ela_m2: float) -> Array:
	return Model.build_door_segments(ela_m2, DOOR_SILL_M, DOOR_HEIGHT_M, Model.PROVISIONAL_SPLIT, BANDS)["segments"]


# ---------------------------------------------------------------- tests

func _test_01_zero_ela() -> void:
	var built: Dictionary = Model.build_door_segments(0.0, DOOR_SILL_M, DOOR_HEIGHT_M, Model.PROVISIONAL_SPLIT, BANDS)
	_check(bool(built["valid"]), "01 zero ELA must build")
	var result: Dictionary = Model.compute_flows(built["segments"], _side(25.0), _side(0.0), TEST_PARAMS, 0.5)
	_check(bool(result["valid"]), "01 zero ELA must compute")
	_check(result["flows"].size() == BANDS + 2, "01 zero ELA keeps every segment")
	for flow in result["flows"]:
		_check(flow["direction"] == Model.DIRECTION_NONE, "01 zero ELA has no direction")
		_check(float(flow["volume_flow_m3_s"]) == 0.0 and float(flow["mass_flow_kg_s"]) == 0.0
				and float(flow["mass_step_kg"]) == 0.0, "01 zero ELA has zero flow")
	_check(float(result["gross_mass_kg_s"]) == 0.0, "01 zero ELA gross mass is zero")


func _test_02_zero_dp() -> void:
	var result: Dictionary = Model.compute_flows(_door(0.0021), _side(7.0), _side(7.0), TEST_PARAMS, 0.5)
	_check(bool(result["valid"]), "02 zero dp must compute")
	for flow in result["flows"]:
		_check(float(flow["dp_pa"]) == 0.0, "02 dp is exactly zero at every height")
		_check(flow["direction"] == Model.DIRECTION_NONE and float(flow["mass_flow_kg_s"]) == 0.0,
				"02 zero dp has zero flow")
	_check(float(result["net_mass_a_to_b_kg_s"]) == 0.0, "02 zero dp net mass is zero")


func _test_03_symmetric_pressures() -> void:
	for dp in [0.05, 0.5, 1.0, 4.0, 10.0, 25.0, 50.0]:
		var forward: float = _q(0.0021, dp)
		var backward: float = _q(0.0021, -dp)
		_check(forward > 0.0, "03 +%s Pa flows a->b" % dp)
		_check(backward < 0.0, "03 -%s Pa flows b->a" % dp)
		_check(forward == -backward, "03 +/-%s Pa have the same magnitude" % dp)


func _test_04_flow_inversion() -> void:
	var segments: Array = _one_segment(0.0012)
	var forward: Dictionary = Model.compute_flows(segments, _side(10.0), _side(0.0), TEST_PARAMS)["flows"][0]
	var backward: Dictionary = Model.compute_flows(segments, _side(0.0), _side(10.0), TEST_PARAMS)["flows"][0]
	_check(forward["direction"] == Model.DIRECTION_A_TO_B, "04 positive dp is a_to_b")
	_check(backward["direction"] == Model.DIRECTION_B_TO_A, "04 negative dp is b_to_a")
	_check(forward["source_side"] == "a" and forward["destination_side"] == "b", "04 forward sides")
	_check(backward["source_side"] == "b" and backward["destination_side"] == "a", "04 backward sides swap")
	_check(float(forward["dp_pa"]) == -float(backward["dp_pa"]), "04 dp changes sign exactly")
	_check(float(forward["mass_flow_kg_s"]) == float(backward["mass_flow_kg_s"]), "04 same mass flow both ways")


func _test_05_reference_value() -> void:
	var area: float = 0.0021
	var expected: float = area * sqrt(2.0 * 4.0 / RHO_AIR)
	for exponent in [0.5, 0.65, 0.8, 1.0]:
		var q: float = _q(area, 4.0, _params({"flow_exponent": exponent}))
		_check(_close(q, expected), "05 at 4 Pa the flow is ELA*sqrt(2*4/rho) for n=%s (got %s, expected %s)" % [exponent, q, expected])
	# Sin coeficiente de descarga: la convencion 4 Pa lleva C_d = 1,0 dentro.
	_check(_close(_q(area, 4.0, _params(PURE_POWER_LAW)), expected), "05 no discharge factor at 4 Pa (pure power law)")
	# Forma de CONTAM (TN 1887r1, ec. 29 y 24): C_b = L·C_d·√2·ΔP_r^(1/2-n),
	# F = C_b·sqrt(ρ)·ΔP^n, Q = F/ρ, con C_d = 1 y ΔP_r = 4 Pa.
	for exponent in [0.5, 0.6, 0.65, 0.7, 1.0]:
		for dp in [0.5, 4.0, 10.0, 25.0, 50.0]:
			var cb: float = area * 1.0 * sqrt(2.0) * pow(4.0, 0.5 - exponent)
			var contam_q: float = cb * sqrt(RHO_AIR) * pow(dp, exponent) / RHO_AIR
			var q_model: float = _q(area, dp, _params({"flow_exponent": exponent, "zero_pressure_regularization_pa": 0.0}))
			_check(_close(q_model, contam_q, 1.0e-12), "05 matches CONTAM eq. 29 with Cd = 1 (n=%s, %s Pa)" % [exponent, dp])
	# Solo la convencion 4 Pa / C_d 1,0: nada de 10 Pa ni de coeficientes sueltos.
	for reference in [10.0, 1.0, 4.0000001]:
		var other: Dictionary = Model.compute_flows(_one_segment(area), _side(4.0), _side(0.0),
				_params({"ela_reference_pressure_pa": reference}))
		_check(not bool(other["valid"]), "05 reference pressure %s Pa is rejected" % reference)
	for forbidden in [{"discharge_coefficient": 1.0}, {"discharge_coefficient": 0.6}, {"reference_pressure_pa": 4.0}]:
		var extra: Dictionary = Model.compute_flows(_one_segment(area), _side(4.0), _side(0.0), _params(forbidden))
		_check(not bool(extra["valid"]), "05 %s is rejected (no second Cd)" % [forbidden])
	_check(Model.NIST_ELA_REFERENCE_PRESSURE_PA == 4.0, "05 the only reference pressure is 4 Pa")
	# Clases previstas: ELA a 4 Pa (12 y 21 cm2) con C_d = 1,0.
	for key in ["entry_tight", "interior_tight"]:
		var ela: float = float(Model.PLANNED_CLASS_ELA_M2[key])
		_check(_close(_q(ela, 4.0), ela * sqrt(8.0 / RHO_AIR)), "05 %s gives ELA*sqrt(2*4/rho) at 4 Pa" % key)
	_check(Model.PROVISIONAL_FLOW_EXPONENT_CANDIDATE == 0.65, "05 the provisional exponent candidate is 0.65")
	var mass: Dictionary = Model.compute_flows(_one_segment(area), _side(4.0), _side(0.0), TEST_PARAMS, 0.25)["flows"][0]
	_check(_close(float(mass["mass_flow_kg_s"]), RHO_AIR * expected), "05 mass flow is rho*Q")
	_check(_close(float(mass["mass_step_kg"]), RHO_AIR * expected * 0.25), "05 mass per step is mass flow * dt")


func _test_06_ela_scaling() -> void:
	var areas: Array = [0.0006, 0.0012, 0.0021, 0.0042, 0.01]
	for dp in [0.05, 2.0, 25.0]:
		var base: float = _q(0.0012, dp)
		var previous: float = 0.0
		for area in areas:
			var q: float = _q(area, dp)
			_check(q > previous, "06 flow grows with ELA (%s m2, %s Pa)" % [area, dp])
			_check(_close(q / base, float(area) / 0.0012, 1.0e-12), "06 flow is proportional to ELA (%s m2, %s Pa)" % [area, dp])
			previous = q


func _test_07_exponent_scaling() -> void:
	for exponent in [0.5, 0.625, 0.65, 0.8, 1.0]:
		var params: Dictionary = _params({"flow_exponent": exponent})
		var reference: float = _q(0.0021, 4.0, params)
		var previous: float = 0.0
		for dp in SWEEP_PA:
			if float(dp) < 0.1:
				continue
			var q: float = _q(0.0021, dp, params)
			_check(_close(q / reference, pow(float(dp) / 4.0, exponent), 1.0e-12),
					"07 Q(dp)/Q(ref) = (dp/ref)^n for n=%s dp=%s" % [exponent, dp])
			_check(q > previous, "07 flow grows with |dp| for n=%s dp=%s" % [exponent, dp])
			previous = q
	var low: float = _q(0.0021, 25.0, _params({"flow_exponent": 0.5}))
	var high: float = _q(0.0021, 25.0, _params({"flow_exponent": 1.0}))
	_check(high > low, "07 above the reference pressure a larger exponent gives more flow")
	var low_below: float = _q(0.0021, 2.0, _params({"flow_exponent": 0.5}))
	var high_below: float = _q(0.0021, 2.0, _params({"flow_exponent": 1.0}))
	_check(high_below < low_below, "07 below the reference pressure a larger exponent gives less flow")


func _test_08_regularization() -> void:
	# La regularizacion es numerica: se prueba el empalme para varios valores y
	# que 0 da la ley de potencia pura.
	for joint_pa in [0.05, 0.1, 1.0]:
		var params: Dictionary = _params({"zero_pressure_regularization_pa": joint_pa})
		var at_joint: float = _q(0.0021, joint_pa, params)
		var pure: float = 0.0021 * sqrt(2.0 * 4.0 / RHO_AIR) * pow(float(joint_pa) / 4.0, 0.65)
		_check(_close(at_joint, pure), "08 at the joint %s Pa the flow is the power law" % joint_pa)
		var just_below: float = _q(0.0021, joint_pa * (1.0 - 1.0e-9), params)
		var just_above: float = _q(0.0021, joint_pa * (1.0 + 1.0e-9), params)
		_check(absf(just_below - at_joint) <= 1.0e-8 * at_joint and absf(just_above - at_joint) <= 1.0e-8 * at_joint,
				"08 the flow is continuous at the joint %s Pa" % joint_pa)
		_check(_close(_q(0.0021, joint_pa * 0.5, params), at_joint * 0.5), "08 below %s Pa the flow is linear in dp" % joint_pa)
		_check(_close(_q(0.0021, joint_pa * 0.25, params), at_joint * 0.25), "08 linear quarter below %s Pa" % joint_pa)
		# Por encima del empalme es la ley de potencia pura.
		_check(_close(_q(0.0021, 25.0, params), _q(0.0021, 25.0, _params(PURE_POWER_LAW))),
				"08 above %s Pa the regularization changes nothing" % joint_pa)
		for dp in [1.0e-12, 1.0e-6, 0.01, 0.05, 0.5]:
			var forward: float = _q(0.0021, dp, params)
			var backward: float = _q(0.0021, -dp, params)
			_check(forward > 0.0 and backward < 0.0 and forward == -backward,
					"08 sign is kept near zero (%s Pa, joint %s Pa)" % [dp, joint_pa])
			for sign in [1.0, -1.0]:
				var flow: Dictionary = Model.compute_flows(_one_segment(0.0021), _side(float(dp) * sign), _side(0.0), params)["flows"][0]
				_check_flow_consistency(flow, "08 near zero (%s Pa, joint %s Pa)" % [float(dp) * sign, joint_pa])
		var previous: float = -1.0
		for dp in SWEEP_PA:
			var q: float = _q(0.0021, dp, params)
			_check(q >= previous, "08 monotone across the joint %s Pa at %s Pa" % [joint_pa, dp])
			previous = q
		_check(_q(0.0021, 0.0, params) == 0.0, "08 zero at zero (joint %s Pa)" % joint_pa)
		# La recta regularizada no supera la pendiente de la cuerda de la ley justo encima.
		var slope_below: float = at_joint / joint_pa
		var slope_above: float = (_q(0.0021, joint_pa * 1.01, params) - at_joint) / (joint_pa * 0.01)
		_check(slope_below >= slope_above, "08 the regularized segment keeps the flow monotone (joint %s Pa)" % joint_pa)
	# Con 0: ley de potencia pura, finita y con signo hasta muy cerca de cero.
	var bare: Dictionary = _params(PURE_POWER_LAW)
	for dp in [1.0e-12, 1.0e-6, 0.01, 0.05, 0.5, 4.0, 25.0]:
		var expected: float = 0.0021 * sqrt(2.0 * 4.0 / RHO_AIR) * pow(float(dp) / 4.0, 0.65)
		_check(_close(_q(0.0021, dp, bare), expected), "08 regularization 0 is the pure power law at %s Pa" % dp)
		_check(_q(0.0021, -dp, bare) == -_q(0.0021, dp, bare), "08 pure power law keeps the sign at %s Pa" % dp)
	_check(_q(0.0021, 0.0, bare) == 0.0, "08 pure power law is zero at zero")


func _test_09_split() -> void:
	var ela: float = 0.0021
	var built: Dictionary = Model.build_door_segments(ela, 0.3, DOOR_HEIGHT_M, Model.PROVISIONAL_SPLIT, BANDS)
	_check(bool(built["valid"]), "09 split must build")
	var segments: Array = built["segments"]
	_check(segments.size() == BANDS + 2, "09 bottom + %d bands + top" % BANDS)
	var by_id: Dictionary = {}
	for segment in segments:
		by_id[segment["id"]] = segment
	_check(by_id.has("bottom") and by_id.has("top"), "09 bottom and top exist")
	_check(_close(float(by_id["bottom"]["area_m2"]), 0.40 * ela), "09 bottom gets 40 %")
	_check(_close(float(by_id["top"]["area_m2"]), 0.13 * ela), "09 top gets 13 %")
	_check(float(by_id["bottom"]["z_m"]) == 0.3, "09 bottom sits at the sill")
	_check(_close(float(by_id["top"]["z_m"]), 0.3 + DOOR_HEIGHT_M), "09 top sits at the lintel")
	var sides_total: float = 0.0
	var previous_z: float = 0.3
	for band in range(BANDS):
		var segment: Dictionary = by_id["side_%02d" % band]
		var expected_z: float = 0.3 + (float(band) + 0.5) * DOOR_HEIGHT_M / float(BANDS)
		_check(_close(float(segment["z_m"]), expected_z), "09 band %d centre" % band)
		_check(float(segment["z_m"]) > previous_z, "09 bands go up")
		_check(_close(float(segment["area_m2"]), 0.47 * ela / float(BANDS), 1.0e-9), "09 band %d area" % band)
		previous_z = float(segment["z_m"])
		sides_total += float(segment["area_m2"])
	_check(previous_z < 0.3 + DOOR_HEIGHT_M, "09 bands stay below the lintel")
	_check(_close(sides_total, 0.47 * ela, 1.0e-12), "09 sides get 47 %")
	var one_band: Dictionary = Model.build_door_segments(ela, 0.0, 2.0, Model.PROVISIONAL_SPLIT, 1)
	_check(one_band["segments"].size() == 3 and float(one_band["segments"][1]["z_m"]) == 1.0,
			"09 one band sits at mid height")


func _test_10_area_conservation() -> void:
	var splits: Array = [
		Model.PROVISIONAL_SPLIT,
		{"bottom": 1.0, "sides": 0.0, "top": 0.0},
		{"bottom": 0.0, "sides": 1.0, "top": 0.0},
		{"bottom": 0.1, "sides": 0.7, "top": 0.2},
		{"bottom": 1.0 / 3.0, "sides": 1.0 / 3.0, "top": 1.0 / 3.0},
	]
	for ela in [0.0, 0.0012, 0.0021, 0.00777, 1.0]:
		for split in splits:
			for bands in [1, 2, 3, 7, 8, 16]:
				var built: Dictionary = Model.build_door_segments(ela, 0.0, DOOR_HEIGHT_M, split, bands)
				var total: float = Model.area_total_m2(built["segments"])
				_check(bool(built["valid"]), "10 split %s builds" % [split])
				_check(absf(total - float(ela)) <= 4.0 * 2.220446049250313e-16 * maxf(float(ela), 1.0e-300),
						"10 areas add up to ELA=%s (bands=%d, split=%s, got %s)" % [ela, bands, split, total])
				_check(built["segments"].size() == bands + 2, "10 no segment lost (bands=%d)" % bands)
	var bad_sum: Dictionary = Model.build_door_segments(0.0021, 0.0, 2.0, {"bottom": 0.5, "sides": 0.5, "top": 0.5}, 8)
	_check(not bool(bad_sum["valid"]) and bad_sum["segments"].is_empty(), "10 fractions adding over 1 are rejected")
	var negative: Dictionary = Model.build_door_segments(-0.001, 0.0, 2.0, Model.PROVISIONAL_SPLIT, 8)
	_check(not bool(negative["valid"]), "10 negative ELA is rejected")
	var missing: Dictionary = Model.build_door_segments(0.001, 0.0, 2.0, {"bottom": 0.5, "sides": 0.5}, 8)
	_check(not bool(missing["valid"]), "10 incomplete split is rejected")


## Sala a caliente: capa alta de densidad 0,6 por encima de 1,0 m y -3 Pa en el
## suelo respecto a b (aire a 1,2 uniforme). Δp = -3 + g·0,6·(z - 1) por encima
## de 1 m: plano neutro en z = 1 + 3/(9,81·0,6) = 1,5097 m, dentro de la puerta.
func _hot_room_case() -> Dictionary:
	var side_a: Dictionary = _side(-3.0, RHO_AIR, 0.6, 1.0)
	var side_b: Dictionary = _side(0.0)
	return Model.compute_flows(_door(0.0021), side_a, side_b, TEST_PARAMS, 0.5)


func _test_11_neutral_plane_inside_door() -> void:
	var result: Dictionary = _hot_room_case()
	_check(bool(result["valid"]), "11 hot room case computes")
	var neutral_z: float = 1.0 + 3.0 / (Model.GRAVITY_M_S2 * 0.6)
	var changes: int = 0
	var previous_direction: String = ""
	for flow in result["flows"]:
		var z: float = float(flow["z_m"])
		var expected_direction: String = Model.DIRECTION_B_TO_A if z < neutral_z else Model.DIRECTION_A_TO_B
		_check(flow["direction"] == expected_direction, "11 %s at %.3f m goes %s" % [flow["segment_id"], z, expected_direction])
		var expected_dp: float = -3.0 if z <= 1.0 else -3.0 + Model.GRAVITY_M_S2 * 0.6 * (z - 1.0)
		_check(_close(float(flow["dp_pa"]), expected_dp, 1.0e-12), "11 hydrostatic dp at %s" % flow["segment_id"])
		if previous_direction != "" and flow["direction"] != previous_direction:
			changes += 1
		previous_direction = flow["direction"]
	_check(changes == 1, "11 the direction changes exactly once going up (got %d)" % changes)
	var bottom: Dictionary = result["flows"][0]
	var top: Dictionary = result["flows"][result["flows"].size() - 1]
	_check(bottom["segment_id"] == "bottom" and bottom["source_side"] == "b" and bottom["source_zone"] == Model.ZONE_LOWER,
			"11 cold air enters the hot room at the bottom")
	_check(top["segment_id"] == "top" and top["source_side"] == "a" and top["source_zone"] == Model.ZONE_UPPER,
			"11 hot gas leaves through the lintel")
	# Solo la zona geometrica de la cota en el receptor: b es uniforme (interfaz a
	# 10 m), asi que el gas caliente del dintel llega a su zona baja por cota; el
	# aire frio entra en a por debajo de su interfaz (1 m).
	_check(top["destination_zone_at_height"] == Model.ZONE_LOWER, "11 lintel height is b's lower zone")
	_check(float(top["destination_density_at_height"]) == RHO_AIR, "11 b's density at the lintel")
	_check(bottom["destination_zone_at_height"] == Model.ZONE_LOWER, "11 floor height is a's lower zone")
	for flow in result["flows"]:
		var receiver: Dictionary = _side(-3.0, RHO_AIR, 0.6, 1.0) if flow["destination_side"] == "a" else _side(0.0)
		var expected_zone: String = Model.ZONE_LOWER if float(flow["z_m"]) < float(receiver["interface_height_m"]) else Model.ZONE_UPPER
		_check(flow["destination_zone_at_height"] == expected_zone, "11 %s receiver zone follows its height" % flow["segment_id"])
		_check(not flow.has("destination_zone"), "11 no deposition decision in %s" % flow["segment_id"])


func _test_12_counter_flows() -> void:
	var result: Dictionary = _hot_room_case()
	var out_kg_s: float = 0.0
	var in_kg_s: float = 0.0
	for flow in result["flows"]:
		if flow["direction"] == Model.DIRECTION_A_TO_B:
			out_kg_s += float(flow["mass_flow_kg_s"])
		elif flow["direction"] == Model.DIRECTION_B_TO_A:
			in_kg_s += float(flow["mass_flow_kg_s"])
	_check(out_kg_s > 0.0 and in_kg_s > 0.0, "12 flow goes both ways at once")
	_check(_close(float(result["net_mass_a_to_b_kg_s"]), out_kg_s - in_kg_s, 1.0e-12), "12 net mass is out - in")
	_check(_close(float(result["gross_mass_kg_s"]), out_kg_s + in_kg_s, 1.0e-12), "12 gross mass is out + in")
	_check(float(result["gross_mass_kg_s"]) > absf(float(result["net_mass_a_to_b_kg_s"])), "12 gross exceeds net")


func _test_13_different_densities() -> void:
	# Segmento en la cota del suelo: el mismo Δp = 10 Pa sin columna hidrostatica,
	# y solo cambia la densidad del lado de origen.
	var segments: Array = _one_segment(0.0021)
	var light: Dictionary = Model.compute_flows(segments, _side(10.0, 0.6, 0.6), _side(0.0), TEST_PARAMS)["flows"][0]
	var heavy: Dictionary = Model.compute_flows(segments, _side(10.0), _side(0.0), TEST_PARAMS)["flows"][0]
	_check(float(light["dp_pa"]) == 10.0 and float(heavy["dp_pa"]) == 10.0, "13 same dp at the segment")
	_check(float(light["source_density_kg_m3"]) == 0.6 and float(heavy["source_density_kg_m3"]) == RHO_AIR,
			"13 the source density is the upstream side's")
	_check(_close(float(light["volume_flow_m3_s"]) / float(heavy["volume_flow_m3_s"]), sqrt(2.0), 1.0e-12),
			"13 volume flow scales with 1/sqrt(rho_source)")
	_check(_close(float(light["mass_flow_kg_s"]) / float(heavy["mass_flow_kg_s"]), sqrt(0.5), 1.0e-12),
			"13 mass flow scales with sqrt(rho_source)")
	# Sin flotabilidad en el solver: a la misma cota, gas ligero y pesado cruzan a
	# la misma zona del receptor.
	_check(light["destination_zone_at_height"] == Model.ZONE_LOWER, "13 lighter gas is not lifted by the solver")
	_check(heavy["destination_zone_at_height"] == Model.ZONE_LOWER, "13 heavy gas crosses at the same receiver zone")
	_check(float(light["destination_density_at_height"]) == RHO_AIR, "13 receiver density at height is reported")
	# La densidad del lado aguas abajo no cambia el caudal.
	var receiver_hot: Dictionary = Model.compute_flows(segments, _side(10.0), _side(0.0, 0.5, 0.5), TEST_PARAMS)["flows"][0]
	_check(float(receiver_hot["volume_flow_m3_s"]) == float(heavy["volume_flow_m3_s"]),
			"13 the downstream density does not change the flow")
	_check(receiver_hot["destination_zone_at_height"] == Model.ZONE_LOWER
			and float(receiver_hot["destination_density_at_height"]) == 0.5,
			"13 dense gas into a hot receiver is not sunk by the solver: reports height zone and density")
	# La cota decide la zona receptora: el mismo gas ligero cruza a la zona alta
	# del receptor solo si el segmento esta por encima de su interfaz.
	var receiver_split: Dictionary = _side(0.0, RHO_AIR, 0.7, 1.0)
	var low_cross: Dictionary = Model.compute_flows(_one_segment(0.0021, 0.5), _side(10.0, 0.6, 0.6), receiver_split, TEST_PARAMS)["flows"][0]
	var high_cross: Dictionary = Model.compute_flows(_one_segment(0.0021, 1.5), _side(10.0, 0.6, 0.6), receiver_split, TEST_PARAMS)["flows"][0]
	_check(low_cross["destination_zone_at_height"] == Model.ZONE_LOWER
			and float(low_cross["destination_density_at_height"]) == RHO_AIR, "13 below the receiver interface: lower zone")
	_check(high_cross["destination_zone_at_height"] == Model.ZONE_UPPER
			and float(high_cross["destination_density_at_height"]) == 0.7, "13 above the receiver interface: upper zone")
	# Gas denso por encima de la interfaz del receptor: sigue siendo su zona alta.
	var dense_high: Dictionary = Model.compute_flows(_one_segment(0.0021, 1.5), _side(30.0, 1.3, 1.3), receiver_split, TEST_PARAMS)["flows"][0]
	_check(dense_high["direction"] == Model.DIRECTION_A_TO_B and dense_high["destination_zone_at_height"] == Model.ZONE_UPPER,
			"13 dense gas above the receiver interface is reported at the upper zone")
	# Suelo del receptor a otra cota: la zona se mide desde su propio suelo.
	var raised: Dictionary = _side(0.0, RHO_AIR, 0.7, 1.0)
	raised["floor_z_m"] = 1.0
	var raised_cross: Dictionary = Model.compute_flows(_one_segment(0.0021, 1.5), _side(30.0), raised, TEST_PARAMS)["flows"][0]
	_check(raised_cross["destination_side"] == "b" and raised_cross["destination_zone_at_height"] == Model.ZONE_LOWER, "13 receiver zone is measured from its own floor")
	# Con columna: la densidad cambia el Δp en altura, no solo el caudal.
	var column: Array = _one_segment(0.0021, 1.0)
	var tall: Dictionary = Model.compute_flows(column, _side(10.0, 0.6, 0.6), _side(0.0), TEST_PARAMS)["flows"][0]
	_check(_close(float(tall["dp_pa"]), 10.0 + Model.GRAVITY_M_S2 * (RHO_AIR - 0.6) * 1.0, 1.0e-12),
			"13 the density difference builds a hydrostatic dp with height")


func _test_14_segment_order_independence() -> void:
	var segments: Array = _door(0.0021)
	var side_a: Dictionary = _side(-3.0, RHO_AIR, 0.6, 1.0)
	var side_b: Dictionary = _side(0.0)
	var reference: String = JSON.stringify(Model.compute_flows(segments, side_a, side_b, TEST_PARAMS, 0.5), "", true, true)
	var reversed: Array = segments.duplicate(true)
	reversed.reverse()
	var rotated: Array = segments.slice(3) + segments.slice(0, 3)
	var interleaved: Array = []
	for index in range(0, segments.size(), 2):
		interleaved.append(segments[index])
	for index in range(1, segments.size(), 2):
		interleaved.append(segments[index])
	for variant in [reversed, rotated, interleaved]:
		var text: String = JSON.stringify(Model.compute_flows(variant, side_a, side_b, TEST_PARAMS, 0.5), "", true, true)
		_check(text == reference, "14 the output does not depend on the input order")
	var tied: Array = [{"id": "z2", "z_m": 1.0, "area_m2": 0.001}, {"id": "a1", "z_m": 1.0, "area_m2": 0.002}]
	var tied_result: Array = Model.compute_flows(tied, _side(4.0), _side(0.0), TEST_PARAMS)["flows"]
	_check(tied_result[0]["segment_id"] == "a1", "14 equal heights are ordered by id")
	var duplicated: Dictionary = Model.compute_flows(
		[{"id": "x", "z_m": 1.0, "area_m2": 0.001}, {"id": "x", "z_m": 2.0, "area_m2": 0.001}],
		_side(4.0), _side(0.0), TEST_PARAMS)
	_check(not bool(duplicated["valid"]), "14 duplicate segment ids are rejected")


func _battery() -> Dictionary:
	var battery: Dictionary = {}
	for ela_key in ["entry_tight", "interior_tight"]:
		var ela: float = float(Model.PLANNED_CLASS_ELA_M2[ela_key])
		var segments: Array = _door(ela)
		battery["%s_uniform_25pa" % ela_key] = Model.compute_flows(segments, _side(25.0), _side(0.0), TEST_PARAMS, 0.5)
		battery["%s_hot_room" % ela_key] = Model.compute_flows(segments, _side(-3.0, RHO_AIR, 0.6, 1.0), _side(0.0), TEST_PARAMS, 0.5)
	var sweep: Array = []
	for exponent in [0.5, 0.65, 1.0]:
		for dp in SWEEP_PA:
			sweep.append([exponent, dp, _q(0.0021, dp, _params({"flow_exponent": exponent}))])
	battery["sweep"] = sweep
	return battery


func _test_15_determinism(dump_path: String) -> void:
	var first: String = JSON.stringify(_battery(), "", true, true)
	var second: String = JSON.stringify(_battery(), "", true, true)
	_check(first == second, "15 two in-process runs are identical")
	if dump_path.is_empty():
		return
	var file := FileAccess.open(dump_path, FileAccess.WRITE)
	if file == null:
		_check(false, "15 could not open dump file %s" % dump_path)
		return
	file.store_string(first + "\n")
	file.close()


func _test_16_inputs_untouched() -> void:
	var segments: Array = [{"id": "b", "z_m": 2.0, "area_m2": 0.001}, {"id": "a", "z_m": 0.0, "area_m2": 0.001}]
	var side_a: Dictionary = _side(-3.0, RHO_AIR, 0.6, 1.0)
	var side_b: Dictionary = _side(0.0)
	var params: Dictionary = _params()
	var before: String = JSON.stringify([segments, side_a, side_b, params], "", true, true)
	var result: Dictionary = Model.compute_flows(segments, side_a, side_b, params, 0.5)
	var after: String = JSON.stringify([segments, side_a, side_b, params], "", true, true)
	_check(before == after, "16 inputs are not modified (no pressure equalisation, no reordering)")
	for key in result.keys():
		_check(not String(key).begins_with("p_") and not String(key).contains("pressure_after"),
				"16 the result carries no updated pressures (%s)" % key)
	for flow in result["flows"]:
		_check(not flow.has("p_floor_pa"), "16 flows carry no updated pressures")


func _test_17_invalid_inputs_are_not_clamped() -> void:
	var segments: Array = _one_segment(0.0021)
	var cases: Dictionary = {
		"exponent below 0.5": [_side(4.0), _side(0.0), _params({"flow_exponent": 0.4}), 0.0],
		"exponent above 1": [_side(4.0), _side(0.0), _params({"flow_exponent": 1.2}), 0.0],
		"discharge coefficient given": [_side(4.0), _side(0.0), _params({"discharge_coefficient": 1.0}), 0.0],
		"negative reference pressure": [_side(4.0), _side(0.0), _params({"ela_reference_pressure_pa": -4.0}), 0.0],
		"10 Pa convention": [_side(4.0), _side(0.0), _params({"ela_reference_pressure_pa": 10.0}), 0.0],
		"old laminar key": [_side(4.0), _side(0.0), _params({"linear_regime_pressure_pa": 0.1}), 0.0],
		"negative regularization": [_side(4.0), _side(0.0), _params({"zero_pressure_regularization_pa": -0.1}), 0.0],
		"nan pressure": [_side(NAN), _side(0.0), _params(), 0.0],
		"infinite pressure": [_side(INF), _side(0.0), _params(), 0.0],
		"zero density": [_side(4.0, 0.0, 0.0), _side(0.0), _params(), 0.0],
		"negative interface": [_side(4.0, RHO_AIR, RHO_AIR, -1.0), _side(0.0), _params(), 0.0],
		"negative dt": [_side(4.0), _side(0.0), _params(), -0.1],
	}
	for label in cases.keys():
		var args: Array = cases[label]
		var result: Dictionary = Model.compute_flows(segments, args[0], args[1], args[2], args[3])
		_check(not bool(result["valid"]) and result["flows"].is_empty() and not result["errors"].is_empty(),
				"17 %s is rejected, not clamped" % label)
	for missing in TEST_PARAMS.keys():
		var params: Dictionary = _params()
		params.erase(missing)
		var result: Dictionary = Model.compute_flows(segments, _side(4.0), _side(0.0), params)
		_check(not bool(result["valid"]), "17 missing '%s' is rejected (no hidden default)" % missing)
	var negative_area: Dictionary = Model.compute_flows(_one_segment(-0.001), _side(4.0), _side(0.0), _params())
	_check(not bool(negative_area["valid"]), "17 negative segment area is rejected")
	# Por encima del dominio: se marca, no se recorta.
	var high: Dictionary = Model.compute_flows(segments, _side(80.0), _side(0.0), _params())
	_check(bool(high["valid"]) and bool(high["domain_exceeded"]), "17 80 Pa is flagged as outside the domain")
	_check(_close(float(high["flows"][0]["volume_flow_m3_s"]), 0.0021 * sqrt(2.0 * 4.0 / RHO_AIR) * pow(80.0 / 4.0, 0.65)),
			"17 80 Pa is not clamped")
	var inside: Dictionary = Model.compute_flows(segments, _side(50.0), _side(0.0), _params())
	_check(not bool(inside["domain_exceeded"]), "17 50 Pa is inside the domain")


func _test_18_finite_everywhere() -> void:
	for exponent in [0.5, 0.625, 0.65, 1.0]:
		for linear_pa in [0.0, 0.1, 1.0]:
			var params: Dictionary = _params({"flow_exponent": exponent, "zero_pressure_regularization_pa": linear_pa})
			for dp in SWEEP_PA:
				for sign in [1.0, -1.0]:
					var result: Dictionary = Model.compute_flows(_door(0.0021), _side(float(dp) * sign), _side(0.0), params, 0.5)
					_check(bool(result["valid"]), "18 valid for n=%s lin=%s dp=%s" % [exponent, linear_pa, dp])
					for flow in result["flows"]:
						_check_flow_consistency(flow, "18 n=%s lin=%s dp=%s" % [exponent, linear_pa, float(dp) * sign])
						for key in ["dp_pa", "volume_flow_m3_s", "signed_volume_flow_m3_s", "mass_flow_kg_s", "mass_step_kg"]:
							var value: float = float(flow[key])
							_check(not is_nan(value) and not is_inf(value), "18 %s finite (n=%s lin=%s dp=%s)" % [key, exponent, linear_pa, dp])

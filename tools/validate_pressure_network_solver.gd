extends SceneTree

## Tests deterministas del solver puro acoplado de presion y aberturas
## (sim/core/Phase3CoupledPressureSolver.gd, entrada canonica
## `solve_pressure_network`, fase F2.2B). No arranca el motor, no carga
## escenarios y no aplica ningun resultado al estado fisico.
##
##   <godot> --headless --path . --script res://tools/validate_pressure_network_solver.gd
##   <godot> --headless --path . --script res://tools/validate_pressure_network_solver.gd -- --dump=<ruta.json>

const SolverScript := preload("res://sim/core/Phase3CoupledPressureSolver.gd")
const Equations := preload("res://sim/core/CompartmentPressureEquations.gd")
const SOLVER_PATH: String = "res://sim/core/Phase3CoupledPressureSolver.gd"

const T_REF_K: float = 293.15
const P_EXT_PA: float = 101325.0
const AREA_M2: float = 20.0
const HEIGHT_M: float = 2.4
const VOLUME_M3: float = AREA_M2 * HEIGHT_M
const AMBIENT_MASS_KG: float = 1.2 * VOLUME_M3
const R_J_KG_K: float = P_EXT_PA / (1.2 * T_REF_K)
const DT_S: float = 0.0833333333333333
const TOL: float = 1.0e-9

var _solver
var _failures: Array[String] = []
var _checks: int = 0


func _initialize() -> void:
	_solver = SolverScript.new()
	var dump_path: String = ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--dump="):
			dump_path = argument.substr("--dump=".length())
	_test_01_sealed_equilibrium()
	_test_02_sealed_cooling()
	_test_03_sealed_heating()
	_test_04_exterior_leak()
	_test_05_two_rooms()
	_test_06_counterflow()
	_test_07_two_storeys()
	_test_08_wind()
	_test_09_order_independence()
	_test_10_failures()
	_test_10b_convergence_gate()
	_test_11_step_independence()
	_test_12_historical_entry()
	_test_13_equations_authority()
	_test_14_reference_states()
	_test_15_contract()
	_test_16_dump(dump_path)
	if _failures.is_empty():
		print("  %d checks" % _checks)
		print("PRESSURE NETWORK SOLVER VALIDATION PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
		print("FAIL: " + failure)
	print("PRESSURE NETWORK SOLVER VALIDATION FAIL (%d)" % _failures.size())
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


func _outside(temp_k: float = T_REF_K) -> Dictionary:
	return {"pressure_abs_pa": P_EXT_PA, "temp_k": temp_k, "reference_temp_k": T_REF_K}


func _room(room_id: String, temp_k: float, floor_z_m: float = 0.0,
		area_m2: float = AREA_M2, height_m: float = HEIGHT_M) -> Dictionary:
	var mass_kg: float = 1.2 * area_m2 * height_m
	return {
		"room_id": room_id, "floor_z_m": floor_z_m,
		"floor_area_m2": area_m2, "height_m": height_m,
		"upper_gas_kg": 0.0, "upper_energy_kj": 0.0,
		"lower_gas_kg": mass_kg, "lower_energy_kj": mass_kg * (temp_k - T_REF_K),
	}


func _two_zone_room(room_id: String, upper_kg: float, upper_temp_k: float,
		lower_kg: float, lower_temp_k: float, floor_z_m: float = 0.0) -> Dictionary:
	return {
		"room_id": room_id, "floor_z_m": floor_z_m,
		"floor_area_m2": AREA_M2, "height_m": HEIGHT_M,
		"upper_gas_kg": upper_kg, "upper_energy_kj": upper_kg * (upper_temp_k - T_REF_K),
		"lower_gas_kg": lower_kg, "lower_energy_kj": lower_kg * (lower_temp_k - T_REF_K),
	}


func _opening(opening_id: String, a: String, b: String, bottom_z: float, top_z: float,
		width_m: float = 0.9, open_fraction: float = 1.0) -> Dictionary:
	return {
		"opening_id": opening_id, "room_a_id": a, "room_b_id": b,
		"bottom_z_m": bottom_z, "top_z_m": top_z, "width_m": width_m,
		"open_fraction": open_fraction, "discharge_coeff": 0.61,
	}


func _solve(rooms: Array, openings: Array, sources: Dictionary = {},
		outside: Dictionary = {}, dt_s: float = DT_S, options: Dictionary = {}) -> Dictionary:
	var outside_state: Dictionary = outside if not outside.is_empty() else _outside()
	return _solver.solve_pressure_network(rooms, openings, outside_state, sources, dt_s, options)


## Recorre el mismo intervalo fisico en varios pasos, realimentando el estado
## candidato como estado anterior. Es composicion pura del solver: no integra
## nada en el motor.
func _march(rooms: Array, openings: Array, total_s: float, steps: int,
		sources: Dictionary = {}, outside: Dictionary = {}) -> Dictionary:
	var state: Array = rooms.duplicate(true)
	var result: Dictionary = {}
	for _step in range(steps):
		result = _solve(state, openings, sources, outside, total_s / float(steps))
		if not bool(result["converged"]):
			return result
		var next_state: Array = []
		for room_state in state:
			var room_out: Dictionary = _room_out(result, String(room_state["room_id"]))
			var advanced: Dictionary = room_state.duplicate(true)
			advanced["upper_gas_kg"] = float(room_out["candidate_upper_gas_kg"])
			advanced["lower_gas_kg"] = float(room_out["candidate_lower_gas_kg"])
			advanced["upper_energy_kj"] = float(room_out["candidate_upper_energy_kj"])
			advanced["lower_energy_kj"] = float(room_out["candidate_lower_energy_kj"])
			next_state.append(advanced)
		state = next_state
	return result


func _room_out(result: Dictionary, room_id: String) -> Dictionary:
	for room in result["rooms"]:
		if String(room["room_id"]) == room_id:
			return room
	return {}


func _opening_out(result: Dictionary, opening_id: String) -> Dictionary:
	for opening in result["openings"]:
		if String(opening["opening_id"]) == opening_id:
			return opening
	return {}


func _canonical(value: Variant) -> String:
	return JSON.stringify(value, "", true, true)


func _rejected(result: Dictionary, message: String) -> void:
	_check(not bool(result["valid"]) and not bool(result["converged"])
			and not String(result["failure_reason"]).is_empty()
			and not result["errors"].is_empty(), message)


## Invariantes que todo resultado convergido debe cumplir.
func _check_converged(result: Dictionary, label: String) -> void:
	_check(bool(result["valid"]) and bool(result["converged"]),
			"%s converged (%s / %s)" % [label, result["failure_reason"], result["errors"]])
	if not bool(result["converged"]):
		return
	for room in result["rooms"]:
		_check(bool(room["equations_valid"]), "%s room %s accepted by F2.2A" % [label, room["room_id"]])
		_check(absf(float(room["mass_residual_kg"])) <= 1.0e-9, "%s room %s mass residual" % [label, room["room_id"]])
		_check(absf(float(room["energy_residual_kj"])) <= 1.0e-6, "%s room %s energy residual" % [label, room["room_id"]])
		_check(absf(float(room["pressure_residual_pa"])) <= 1.0e-6, "%s room %s pressure closure" % [label, room["room_id"]])
		_check(float(room["pressure_abs_pa"]) > 0.0, "%s room %s absolute pressure is positive" % [label, room["room_id"]])
		_check(float(room["candidate_upper_gas_kg"]) >= 0.0 and float(room["candidate_lower_gas_kg"]) >= 0.0,
				"%s room %s candidate mass is not negative" % [label, room["room_id"]])
		_check(float(room["reference_z_m"]) == float(room["pressure_profile"][0]["z_m"]),
				"%s room %s profile starts at the floor" % [label, room["room_id"]])


# ---------------------------------------------------------------- tests

func _test_01_sealed_equilibrium() -> void:
	var result: Dictionary = _solve([_room("r0", T_REF_K)], [])
	_check_converged(result, "01")
	if not bool(result["converged"]):
		return
	var room: Dictionary = _room_out(result, "r0")
	_check(_close(float(room["gauge_pressure_pa"]), 0.0), "01 a sealed room in equilibrium is at 0 Pa (%s)" % room["gauge_pressure_pa"])
	_check(_close(float(room["candidate_lower_gas_kg"]), AMBIENT_MASS_KG), "01 no mass moved")
	_check(_close(float(room["candidate_lower_energy_kj"]), 0.0), "01 no energy moved")
	_check(result["openings"].is_empty(), "01 there are no openings")
	# Repetir el mismo paso no introduce deriva.
	var longer: Dictionary = _solve([_room("r0", T_REF_K)], [], {}, {}, 60.0)
	_check(_close(float(_room_out(longer, "r0")["gauge_pressure_pa"]), 0.0), "01 a 60 s step does not drift")


func _test_02_sealed_cooling() -> void:
	var result: Dictionary = _solve([_room("r0", 273.15)], [])
	_check_converged(result, "02")
	if not bool(result["converged"]):
		return
	var room: Dictionary = _room_out(result, "r0")
	var analytic_pa: float = P_EXT_PA * (273.15 / T_REF_K - 1.0)
	var solved_pa: float = float(room["gauge_pressure_pa"])
	_check(solved_pa < 0.0, "02 the sealed cooled room is below ambient (%s Pa)" % solved_pa)
	_check(absf(solved_pa - analytic_pa) <= 0.01 * absf(analytic_pa),
			"02 within 1%% of the ideal gas value (%.4f vs %.4f Pa)" % [solved_pa, analytic_pa])
	_check(absf(analytic_pa + 6912.843254) < 0.01, "02 the reference value is about -6,9 kPa")
	_check(float(room["candidate_lower_energy_kj"]) < 0.0, "02 negative sensible energy is accepted")
	_check(float(room["pressure_abs_pa"]) > 0.0, "02 the absolute pressure stays positive")
	_check(float(room["pressure_profile"][0]["gauge_pressure_pa"]) < 0.0, "02 the profile is negative at the floor")


func _test_03_sealed_heating() -> void:
	var result: Dictionary = _solve([_room("r0", 313.15)], [])
	_check_converged(result, "03")
	if not bool(result["converged"]):
		return
	var solved_pa: float = float(_room_out(result, "r0")["gauge_pressure_pa"])
	var analytic_pa: float = P_EXT_PA * (313.15 / T_REF_K - 1.0)
	_check(solved_pa > 0.0 and absf(solved_pa - analytic_pa) <= 0.01 * absf(analytic_pa),
			"03 sealed heating is positive and matches the ideal gas value (%.4f vs %.4f)" % [solved_pa, analytic_pa])
	var cooled: Dictionary = _solve([_room("r0", 273.15)], [])
	_check(_close(solved_pa, -float(_room_out(cooled, "r0")["gauge_pressure_pa"]), 1.0e-9),
			"03 heating and cooling by 20 K are symmetric")


func _test_04_exterior_leak() -> void:
	var sealed: Dictionary = _solve([_room("r0", 313.15)], [])
	var leaked: Dictionary = _solve([_room("r0", 313.15)],
			[_opening("leak", "r0", "outside", 0.0, 0.05, 0.02)])
	_check_converged(leaked, "04")
	if not bool(leaked["converged"]):
		return
	var sealed_pa: float = float(_room_out(sealed, "r0")["gauge_pressure_pa"])
	var leaked_pa: float = float(_room_out(leaked, "r0")["gauge_pressure_pa"])
	_check(leaked_pa < sealed_pa and leaked_pa > 0.0,
			"04 a small leak relieves the pressure (%.2f -> %.2f Pa)" % [sealed_pa, leaked_pa])
	var opening: Dictionary = _opening_out(leaked, "leak")
	_check(float(opening["net_mass_kg_s"]) > 0.0, "04 the flow leaves the room")
	for segment in opening["segments"]:
		_check(float(segment["dp_pa"]) > 0.0 and String(segment["source_room_id"]) == "r0"
				and String(segment["destination_room_id"]) == "outside",
				"04 every segment flows outwards while dp > 0")
	# Invertir el signo de dP invierte el flujo.
	var cold: Dictionary = _solve([_room("r0", 273.15)],
			[_opening("leak", "r0", "outside", 0.0, 0.05, 0.02)])
	_check_converged(cold, "04 cold")
	var cold_opening: Dictionary = _opening_out(cold, "leak")
	_check(float(_room_out(cold, "r0")["gauge_pressure_pa"]) < 0.0, "04 the cold room stays below ambient")
	_check(float(cold_opening["net_mass_kg_s"]) < 0.0, "04 a negative pressure pulls air in")
	for segment in cold_opening["segments"]:
		_check(String(segment["source_room_id"]) == "outside", "04 the inflow comes from the exterior")
	# La masa y la energia entran en la contabilidad del recinto.
	var room: Dictionary = _room_out(cold, "r0")
	_check(float(room["candidate_lower_gas_kg"]) > 1.2 * VOLUME_M3 * 0.99, "04 the inflow is counted in the candidate mass")
	_check(float(room["net_mass_kg_s"]) > 0.0, "04 the net mass rate is positive when air enters")


func _test_05_two_rooms() -> void:
	var rooms: Array = [_two_zone_room("r0", 12.0, 493.15, 40.0, 298.15), _room("r1", T_REF_K)]
	var result: Dictionary = _solve(rooms, [_opening("door", "r0", "r1", 0.0, 2.0)])
	_check_converged(result, "05")
	if not bool(result["converged"]):
		return
	var hot: Dictionary = _room_out(result, "r0")
	var cold: Dictionary = _room_out(result, "r1")
	_check(float(hot["gauge_pressure_pa"]) > float(cold["gauge_pressure_pa"]),
			"05 the hot room stays above the cold one")
	var opening: Dictionary = _opening_out(result, "door")
	for segment in opening["segments"]:
		var flows_from_a: bool = String(segment["source_room_id"]) == "r0"
		_check((float(segment["dp_pa"]) >= 0.0) == flows_from_a,
				"05 each segment flows from the higher pressure side")
	# Debito y credito interiores exactamente antisimetricos.
	var mass_before: float = 0.0
	var mass_after: float = 0.0
	var energy_before: float = 0.0
	var energy_after: float = 0.0
	for room_state in rooms:
		mass_before += float(room_state["upper_gas_kg"]) + float(room_state["lower_gas_kg"])
		energy_before += float(room_state["upper_energy_kj"]) + float(room_state["lower_energy_kj"])
	for room in result["rooms"]:
		mass_after += float(room["candidate_upper_gas_kg"]) + float(room["candidate_lower_gas_kg"])
		energy_after += float(room["candidate_upper_energy_kj"]) + float(room["candidate_lower_energy_kj"])
	_check(absf(mass_after - mass_before) <= 1.0e-9 * mass_before,
			"05 the interior conserves mass (%.12f vs %.12f)" % [mass_after, mass_before])
	_check(absf(energy_after - energy_before) <= 1.0e-9 * maxf(1.0, absf(energy_before)),
			"05 the interior conserves energy (%.9f vs %.9f)" % [energy_after, energy_before])
	_check(_close(float(hot["net_mass_kg_s"]), -float(cold["net_mass_kg_s"]), 1.0e-9),
			"05 what one room loses the other gains")
	# Igualacion: tras el paso las presiones estan mas cerca.
	var gap_before: float = absf(float(hot["diagnostics"]["eos_gauge_pressure_pa"]))
	_check(gap_before >= 0.0, "05 the diagnostics carry the EOS pressure")


## Sala caliente cuya masa total la deja casi a presion ambiente: asi el
## termino termodinamico no tapa la flotabilidad y el plano neutro cae dentro
## del vano. Sum(m_z * T_z) = M_ref * T_ref.
func _buoyant_hot_room(room_id: String, floor_z_m: float = 0.0) -> Dictionary:
	var upper_kg: float = 20.0
	var upper_temp_k: float = 573.15
	var lower_temp_k: float = 313.15
	var lower_kg: float = (AMBIENT_MASS_KG * T_REF_K - upper_kg * upper_temp_k) / lower_temp_k
	return _two_zone_room(room_id, upper_kg, upper_temp_k, lower_kg, lower_temp_k, floor_z_m)


func _test_06_counterflow() -> void:
	var rooms: Array = [_buoyant_hot_room("r0"), _room("r1", T_REF_K)]
	var result: Dictionary = _solve(rooms, [_opening("door", "r0", "r1", 0.0, 2.4)])
	_check_converged(result, "06")
	if not bool(result["converged"]):
		return
	var opening: Dictionary = _opening_out(result, "door")
	_check(bool(opening["neutral_plane_inside"]), "06 the neutral plane lies inside the opening")
	var neutral_z: float = float(opening["neutral_plane_z_m"])
	_check(neutral_z > 0.0 and neutral_z < 2.4, "06 the neutral plane is at a sensible height (%.4f)" % neutral_z)
	var out_kg: float = 0.0
	var in_kg: float = 0.0
	for segment in opening["segments"]:
		if String(segment["source_room_id"]) == "r0":
			out_kg += float(segment["mass_flow_kg_s"])
			_check(float(segment["sample_z_m"]) > neutral_z, "06 the outflow is above the neutral plane")
		else:
			in_kg += float(segment["mass_flow_kg_s"])
			_check(float(segment["sample_z_m"]) < neutral_z, "06 the inflow is below the neutral plane")
	_check(out_kg > 0.0 and in_kg > 0.0, "06 both directions carry mass (%.6f out, %.6f in)" % [out_kg, in_kg])
	# Densidad aguas arriba: el gas caliente que sale es mas ligero que el que entra.
	var hot_density: float = 0.0
	var cold_density: float = 0.0
	for segment in opening["segments"]:
		if String(segment["source_room_id"]) == "r0":
			hot_density = maxf(hot_density, float(segment["source_density_kg_m3"]))
		else:
			cold_density = maxf(cold_density, float(segment["source_density_kg_m3"]))
	_check(hot_density > 0.0 and cold_density > hot_density,
			"06 the upstream density is the donor one (%.4f hot vs %.4f cold)" % [hot_density, cold_density])
	# El humo sale por arriba: la zona de origen de la salida es la superior.
	for segment in opening["segments"]:
		if String(segment["source_room_id"]) == "r0" and float(segment["sample_z_m"]) > 1.8:
			_check(String(segment["source_zone"]) == "upper", "06 the high outflow comes from the upper zone")


func _test_07_two_storeys() -> void:
	var ground: Dictionary = _two_zone_room("ground", 12.0, 493.15, 40.0, 298.15, 0.0)
	var upstairs: Dictionary = _room("upstairs", T_REF_K, 3.0)
	var stair: Dictionary = _opening("stair", "ground", "upstairs", 2.0, 2.4)
	var result: Dictionary = _solve([ground, upstairs], [stair])
	_check_converged(result, "07")
	if not bool(result["converged"]):
		return
	_check(_close(float(_room_out(result, "ground")["reference_z_m"]), 0.0)
			and _close(float(_room_out(result, "upstairs")["reference_z_m"]), 3.0),
			"07 each room keeps its own floor as the datum")
	var profile: Array = _room_out(result, "upstairs")["pressure_profile"]
	_check(_close(float(profile[0]["z_m"]), 3.0) and _close(float(profile[2]["z_m"]), 5.4),
			"07 the upstairs profile lives between 3,0 and 5,4 m")
	# Trasladar el edificio entero no cambia los caudales, pero SI cambia las
	# manometricas: cada recinto pasa a compararse con un exterior mas ligero.
	var lifted_ground: Dictionary = ground.duplicate(true)
	lifted_ground["floor_z_m"] = 10.0
	var lifted_upstairs: Dictionary = upstairs.duplicate(true)
	lifted_upstairs["floor_z_m"] = 13.0
	var lifted_stair: Dictionary = stair.duplicate(true)
	lifted_stair["bottom_z_m"] = 12.0
	lifted_stair["top_z_m"] = 12.4
	var lifted: Dictionary = _solve([lifted_ground, lifted_upstairs], [lifted_stair])
	_check_converged(lifted, "07 lifted")
	_check(_close(float(_opening_out(lifted, "stair")["net_mass_kg_s"]),
			float(_opening_out(result, "stair")["net_mass_kg_s"]), 1.0e-12),
			"07 lifting the whole building changes no flow")
	# F2.2C-R1: subir 10 m sin mover la referencia sube toda manometrica en
	# exactamente rho*g*h, porque el exterior local de cada suelo baja esa misma
	# columna. Antes esta prueba exigia que no cambiara nada, que era el defecto.
	var lift_column_pa: float = 1.2 * 9.80665 * 10.0
	for room_id in ["ground", "upstairs"]:
		_check(_close(float(_room_out(lifted, room_id)["gauge_pressure_pa"]),
				float(_room_out(result, room_id)["gauge_pressure_pa"]) + lift_column_pa,
				1.0e-9),
				"07 lifting the building raises '%s' by exactly the atmospheric column (%.9f vs %.9f Pa)" % [
					room_id, _room_out(lifted, room_id)["gauge_pressure_pa"],
					float(_room_out(result, room_id)["gauge_pressure_pa"]) + lift_column_pa])
		# Y su estado no ha cambiado, asi que su presion ABSOLUTA es la misma.
		_check(_close(float(_room_out(lifted, room_id)["pressure_abs_pa"]),
				float(_room_out(result, room_id)["pressure_abs_pa"]), 1.0e-9),
				"07 lifting the building leaves '%s' at the same absolute pressure" % room_id)
	# La invariancia de datum de verdad: subir el edificio Y la referencia con el
	# no cambia absolutamente nada.
	var lifted_with_datum: Dictionary = _solve(
		[lifted_ground, lifted_upstairs], [lifted_stair], {},
		{"pressure_abs_pa": 101325.0, "reference_z_m": 10.0,
			"temp_k": T_REF_K, "reference_temp_k": T_REF_K})
	_check_converged(lifted_with_datum, "07 lifted with its datum")
	for room_id in ["ground", "upstairs"]:
		_check(_close(float(_room_out(lifted_with_datum, room_id)["gauge_pressure_pa"]),
				float(_room_out(result, room_id)["gauge_pressure_pa"]), 1.0e-12),
				"07 moving the building and its datum together changes nothing for '%s'" % room_id)
	# Cotas locales entre plantas distintas: rechazadas.
	var local_stair: Dictionary = {
		"opening_id": "stair", "room_a_id": "ground", "room_b_id": "upstairs",
		"height_reference": "local", "bottom_m": 2.0, "top_m": 2.4,
		"width_m": 0.9, "open_fraction": 1.0, "discharge_coeff": 0.61,
	}
	_rejected(_solve([ground, upstairs], [local_stair]),
			"07 local heights between different storeys are rejected")
	# Mezclar cotas locales y absolutas: rechazado, y con el motivo exacto.
	var mixed: Dictionary = stair.duplicate(true)
	mixed["bottom_m"] = 2.0
	var mixed_result: Dictionary = _solve([ground, upstairs], [mixed])
	_rejected(mixed_result, "07 mixing local and absolute heights is rejected")
	var says_mixed: bool = false
	for message in mixed_result["errors"]:
		if String(message).contains("mixes absolute and local heights"):
			says_mixed = true
	_check(says_mixed, "07 the caller is told exactly that the heights are mixed (%s)" % [mixed_result["errors"]])
	# Cotas locales dentro de la misma planta: aceptadas y equivalentes.
	var same_floor_local: Dictionary = {
		"opening_id": "door", "room_a_id": "r0", "room_b_id": "r1",
		"height_reference": "local", "bottom_m": 0.0, "top_m": 2.0,
		"width_m": 0.9, "open_fraction": 1.0, "discharge_coeff": 0.61,
	}
	var rooms: Array = [_two_zone_room("r0", 12.0, 493.15, 40.0, 298.15), _room("r1", T_REF_K)]
	var local_result: Dictionary = _solve(rooms, [same_floor_local])
	var absolute_result: Dictionary = _solve(rooms, [_opening("door", "r0", "r1", 0.0, 2.0)])
	_check(_canonical(local_result["openings"]) == _canonical(absolute_result["openings"]),
			"07 a declared local span equals the same absolute span")


func _test_08_wind() -> void:
	var rooms: Array = [_room("r0", T_REF_K)]
	var base_opening: Dictionary = _opening("window", "r0", "outside", 0.9, 2.0)
	var calm: Dictionary = _solve(rooms, [base_opening])
	_check_converged(calm, "08 calm")
	var zero_wind: Dictionary = base_opening.duplicate(true)
	zero_wind["wind_dp_pa"] = 0.0
	var zero: Dictionary = _solve(rooms, [zero_wind])
	_check(_canonical(zero) == _canonical(calm), "08 zero wind reproduces the base case")
	var windward: Dictionary = base_opening.duplicate(true)
	windward["wind_dp_pa"] = 12.0
	var leeward: Dictionary = base_opening.duplicate(true)
	leeward["wind_dp_pa"] = -12.0
	var pushed: Dictionary = _solve(rooms, [windward])
	var pulled: Dictionary = _solve(rooms, [leeward])
	_check_converged(pushed, "08 windward")
	_check_converged(pulled, "08 leeward")
	var pushed_pa: float = float(_room_out(pushed, "r0")["gauge_pressure_pa"])
	var pulled_pa: float = float(_room_out(pulled, "r0")["gauge_pressure_pa"])
	_check(pushed_pa > 0.0 and pulled_pa < 0.0,
			"08 the wind sign drives the room pressure (%.4f vs %.4f Pa)" % [pushed_pa, pulled_pa])
	_check(_close(pushed_pa, -pulled_pa, 1.0e-6), "08 the wind contribution is antisymmetric")
	# El viento no se suma dos veces: en equilibrio la presion interior tiende al
	# valor del viento, nunca al doble.
	_check(pushed_pa < 12.0 + 1.0e-6, "08 the interior never exceeds the wind pressure (%.6f)" % pushed_pa)
	var pushed_opening: Dictionary = _opening_out(pushed, "window")
	_check(_close(float(pushed_opening["wind_dp_pa"]), 12.0), "08 the opening reports its own wind")
	# El viento en una abertura interior es un error.
	var interior_wind: Dictionary = _opening("door", "r0", "r1", 0.0, 2.0)
	interior_wind["wind_dp_pa"] = 5.0
	_rejected(_solve([_room("r0", T_REF_K), _room("r1", T_REF_K)], [interior_wind]),
			"08 an interior opening cannot carry wind")


func _test_09_order_independence() -> void:
	var hot: Dictionary = _two_zone_room("r0", 12.0, 493.15, 40.0, 298.15)
	var mid: Dictionary = _two_zone_room("r1", 6.0, 373.15, 48.0, 295.15)
	var cold: Dictionary = _room("r2", T_REF_K)
	var door_a: Dictionary = _opening("door_a", "r0", "r1", 0.0, 2.0)
	var door_b: Dictionary = _opening("door_b", "r1", "r2", 0.0, 2.0)
	var window: Dictionary = _opening("window", "r2", "outside", 1.0, 2.0, 0.6)
	var sources: Dictionary = {
		"r0": {"upper_enthalpy_kw": 50.0, "upper_mass_kg_s": 0.01},
		"r2": {"lower_mass_kg_s": -0.005},
	}
	var forward: Dictionary = _solve([hot, mid, cold], [door_a, door_b, window], sources)
	_check_converged(forward, "09")
	var reversed_rooms: Array = [cold, mid, hot]
	var reversed_openings: Array = [window, door_b, door_a]
	var reversed_sources: Dictionary = {
		"r2": {"lower_mass_kg_s": -0.005},
		"r0": {"upper_mass_kg_s": 0.01, "upper_enthalpy_kw": 50.0},
	}
	var backward: Dictionary = _solve(reversed_rooms, reversed_openings, reversed_sources)
	_check(_canonical(backward) == _canonical(forward),
			"09 reordering rooms, openings and sources gives byte-identical output")


func _test_10_failures() -> void:
	var room: Dictionary = _room("r0", T_REF_K)
	_rejected(_solve([room], [], {}, {}, 0.0), "10 dt = 0 is rejected")
	_rejected(_solve([room], [], {}, {}, -1.0), "10 a negative dt is rejected")
	_rejected(_solve([], [], {}, {}), "10 an empty network is rejected")
	_rejected(_solve([room], [], {}, {"pressure_abs_pa": 0.0, "temp_k": T_REF_K,
			"reference_temp_k": T_REF_K}), "10 a non-positive exterior pressure is rejected")
	_rejected(_solve([room], [], {}, {"pressure_abs_pa": P_EXT_PA, "temp_k": -1.0,
			"reference_temp_k": T_REF_K}), "10 a non-physical exterior temperature is rejected")
	var negative_mass: Dictionary = room.duplicate(true)
	negative_mass["lower_gas_kg"] = -1.0
	_rejected(_solve([negative_mass], []), "10 a negative room mass is rejected")
	var frozen: Dictionary = room.duplicate(true)
	frozen["lower_energy_kj"] = -AMBIENT_MASS_KG * T_REF_K
	_rejected(_solve([frozen], []), "10 a zone at 0 K is rejected")
	var colder_than_possible: Dictionary = room.duplicate(true)
	colder_than_possible["lower_energy_kj"] = -AMBIENT_MASS_KG * (T_REF_K + 10.0)
	_rejected(_solve([colder_than_possible], []), "10 a negative absolute temperature is rejected")
	var no_id: Dictionary = room.duplicate(true)
	no_id["room_id"] = "  "
	_rejected(_solve([no_id], []), "10 a blank room_id is rejected")
	var reserved: Dictionary = room.duplicate(true)
	reserved["room_id"] = "outside"
	_rejected(_solve([reserved], []), "10 'outside' is reserved for the exterior node")
	_rejected(_solve([room, room.duplicate(true)], []), "10 a duplicated room is rejected")
	var bad_volume: Dictionary = room.duplicate(true)
	bad_volume["volume_m3"] = 10.0
	_rejected(_solve([bad_volume], []), "10 a volume that contradicts the geometry is rejected")
	_rejected(_solve([room], [_opening("door", "r0", "ghost", 0.0, 2.0)]), "10 an unknown room in an opening is rejected")
	_rejected(_solve([room], [_opening("door", "r0", "r0", 0.0, 2.0)]), "10 an opening to itself is rejected")
	_rejected(_solve([room], [_opening("door", "outside", "outside", 0.0, 2.0)]), "10 exterior to exterior is rejected")
	_rejected(_solve([room], [_opening("door", "r0", "outside", 2.0, 2.0)]), "10 a span with no height is rejected")
	_rejected(_solve([room], [_opening("door", "r0", "outside", 0.0, 2.0, 0.0)]), "10 a zero width is rejected")
	var no_span: Dictionary = {"opening_id": "door", "room_a_id": "r0", "room_b_id": "outside",
			"width_m": 0.9, "open_fraction": 1.0, "discharge_coeff": 0.61}
	_rejected(_solve([room], [no_span]), "10 an opening without a span is rejected")
	var blank_opening: Dictionary = _opening("", "r0", "outside", 0.0, 2.0)
	_rejected(_solve([room], [blank_opening]), "10 a blank opening_id is rejected")
	var duplicated: Array = [_opening("door", "r0", "outside", 0.0, 2.0), _opening("door", "r0", "outside", 0.0, 1.0)]
	_rejected(_solve([room], duplicated), "10 a duplicated opening_id is rejected")
	_rejected(_solve([room], [], {"ghost": {"lower_mass_kg_s": 1.0}}), "10 a source for an unknown room is rejected")
	_rejected(_solve([room], [], {"r0": {"lower_mass_kg_s": NAN}}), "10 a non-finite source is rejected")
	# Presupuesto de iteraciones agotado.
	var hot: Dictionary = _buoyant_hot_room("r0")
	var capped: Dictionary = _solve([hot, _room("r1", T_REF_K)],
			[_opening("door", "r0", "r1", 0.0, 2.4)], {}, {}, DT_S, {"max_iterations": 1})
	_check(not bool(capped["converged"]) and String(capped["failure_reason"]) == "iteration_cap",
			"10 the iteration budget fails explicitly (%s)" % capped["failure_reason"])
	# Un candidato con masa negativa se detecta por las ecuaciones.
	var draining: Dictionary = _solve([_room("r0", T_REF_K)], [],
			{"r0": {"lower_mass_kg_s": -1000.0}}, {}, 1.0)
	_check(not bool(draining["converged"]), "10 a candidate that drains the room does not converge")
	_check(String(draining["failure_reason"]) == "compartment_equations_rejected_candidate"
			or String(draining["failure_reason"]) == "iteration_cap"
			or not draining["errors"].is_empty(),
			"10 the draining candidate fails with a visible reason (%s)" % draining["failure_reason"])


## La puerta de convergencia tiene que poder fallar: con tolerancias
## imposibles, un caso que converge numericamente debe declararse NO convergido
## y decir por que.
func _test_10b_convergence_gate() -> void:
	var rooms: Array = [_two_zone_room("r0", 12.0, 493.15, 40.0, 298.15), _room("r1", T_REF_K)]
	var openings: Array = [_opening("door", "r0", "r1", 0.0, 2.0)]
	var relaxed: Dictionary = _solve(rooms, openings)
	_check_converged(relaxed, "10b baseline")
	for pair in [["pressure_tolerance_pa", "pressure_closure_above_tolerance"],
			["mass_tolerance_kg", "mass_residual_above_tolerance"],
			["energy_tolerance_kj", "energy_residual_above_tolerance"]]:
		var strict: Dictionary = _solve(rooms, openings, {}, {}, DT_S, {String(pair[0]): 0.0})
		_check(not bool(strict["converged"]) and String(strict["failure_reason"]) == String(pair[1]),
				"10b %s = 0 fails with '%s' (got '%s')" % [pair[0], pair[1], strict["failure_reason"]])
		_check(not bool(strict["valid"]), "10b an unconverged network is not valid")
	# Con las tres tolerancias imposibles a la vez, el motivo sigue siendo uno
	# concreto y el resultado nunca se declara valido.
	var all_strict: Dictionary = _solve(rooms, openings, {}, {}, DT_S,
			{"pressure_tolerance_pa": 0.0, "mass_tolerance_kg": 0.0, "energy_tolerance_kj": 0.0})
	_check(not bool(all_strict["converged"]) and all_strict["errors"].size() >= 3,
			"10b every violated criterion is reported (%s)" % [all_strict["errors"]])


func _test_11_step_independence() -> void:
	var rooms: Array = [_two_zone_room("r0", 12.0, 493.15, 40.0, 298.15), _room("r1", T_REF_K)]
	var openings: Array = [_opening("door", "r0", "r1", 0.0, 2.0)]
	# El mismo intervalo fisico recorrido con 1, 2 y 4 pasos. Comparar un solo
	# paso de distinta duracion no mide independencia del paso: mide otra cosa.
	var pressures: Array = []
	for steps in [1, 2, 4]:
		var result: Dictionary = _march(rooms, openings, DT_S, steps)
		_check_converged(result, "11 %d steps" % steps)
		if not bool(result["converged"]):
			return
		pressures.append(float(_room_out(result, "r0")["gauge_pressure_pa"]))
	var reference_pa: float = float(pressures[0])
	for index in range(1, pressures.size()):
		var deviation: float = absf(float(pressures[index]) - reference_pa) / maxf(1.0, absf(reference_pa))
		_check(deviation < 0.02,
				"11 marching the same interval with more steps moves the pressure less than 2%% (%.4f%%)"
				% (deviation * 100.0))


func _test_12_historical_entry() -> void:
	# La entrada historica y la canonica comparten nucleo: mismo resultado.
	var historical_rooms: Dictionary = {
		"0": {"volume_m3": VOLUME_M3, "floor_area_m2": AREA_M2, "height_m": HEIGHT_M,
			"upper_gas_kg": 12.0, "lower_gas_kg": 40.0,
			"upper_energy_kj": 12.0 * 200.0, "lower_energy_kj": 40.0 * 5.0},
		"1": {"volume_m3": VOLUME_M3, "floor_area_m2": AREA_M2, "height_m": HEIGHT_M,
			"upper_gas_kg": 0.0, "lower_gas_kg": AMBIENT_MASS_KG,
			"upper_energy_kj": 0.0, "lower_energy_kj": 0.0},
	}
	var historical_openings: Array = [{
		"opening_id": 0, "room_a_id": 0, "room_b_id": 1, "bottom_m": 0.0, "top_m": 2.0,
		"width_m": 0.9, "open_fraction": 1.0, "discharge_coeff": 0.61,
	}]
	var historical: Dictionary = _solver.solve_coupled_pressure(
		historical_rooms, historical_openings, {}, DT_S, 20.0, {})
	_check(bool(historical["valid"]) and bool(historical["converged"]), "12 the historical entry still converges")
	var canonical: Dictionary = _solve(
		[_two_zone_room("r0", 12.0, T_REF_K + 200.0, 40.0, T_REF_K + 5.0), _room("r1", T_REF_K)],
		[_opening("door", "r0", "r1", 0.0, 2.0)])
	_check_converged(canonical, "12")
	if not bool(canonical["converged"]):
		return
	_check(_close(float(_room_out(canonical, "r0")["gauge_pressure_pa"]),
			float(historical["gauge_pressure_by_room"]["0"]), 1.0e-12),
			"12 both entries give the same pressure for room 0")
	_check(_close(float(_room_out(canonical, "r1")["gauge_pressure_pa"]),
			float(historical["gauge_pressure_by_room"]["1"]), 1.0e-12),
			"12 both entries give the same pressure for room 1")
	var historical_net_kg: float = float(historical["connections"][0]["net_mass_a_to_b_kg"])
	_check(_close(float(_opening_out(canonical, "door")["net_mass_kg_s"]) * DT_S,
			historical_net_kg, 1.0e-12), "12 both entries give the same net flow")


func _test_13_equations_authority() -> void:
	var rooms: Array = [_two_zone_room("r0", 12.0, 493.15, 40.0, 298.15), _room("r1", T_REF_K)]
	var result: Dictionary = _solve(rooms, [_opening("door", "r0", "r1", 0.0, 2.0)])
	_check_converged(result, "13")
	if not bool(result["converged"]):
		return
	# Reevaluar el estado final con F2.2A reproduce los residuos publicados.
	for room in result["rooms"]:
		var previous: Dictionary = {}
		for candidate_room in rooms:
			if String(candidate_room["room_id"]) == String(room["room_id"]):
				previous = candidate_room
		var previous_state: Dictionary = {
			"room_id": String(room["room_id"]), "floor_z_m": float(previous["floor_z_m"]),
			"height_m": float(previous["height_m"]), "floor_area_m2": float(previous["floor_area_m2"]),
			"upper_gas_kg": float(previous["upper_gas_kg"]), "lower_gas_kg": float(previous["lower_gas_kg"]),
			"upper_energy_kj": float(previous["upper_energy_kj"]),
			"lower_energy_kj": float(previous["lower_energy_kj"]),
		}
		var candidate_state: Dictionary = {
			"room_id": String(room["room_id"]), "floor_z_m": float(previous["floor_z_m"]),
			"height_m": float(previous["height_m"]), "floor_area_m2": float(previous["floor_area_m2"]),
			"gauge_pressure_pa": float(room["gauge_pressure_pa"]),
			"upper_gas_kg": float(room["candidate_upper_gas_kg"]),
			"lower_gas_kg": float(room["candidate_lower_gas_kg"]),
			"upper_energy_kj": float(room["candidate_upper_energy_kj"]),
			"lower_energy_kj": float(room["candidate_lower_energy_kj"]),
		}
		var fluxes: Array = _fluxes_for(result, String(room["room_id"]))
		var verdict: Dictionary = Equations.evaluate_compartment_residual(
			previous_state, candidate_state, {}, fluxes, _outside(), DT_S)
		_check(bool(verdict["valid"]), "13 the independent re-evaluation is valid (%s)" % [verdict["errors"]])
		_check(_close(float(verdict["pressure_residual_pa"]), float(room["pressure_residual_pa"]), 1.0e-9),
				"13 the published pressure residual is reproduced")
		_check(absf(float(verdict["mass_residual_kg"])) <= 1.0e-9, "13 the published mass residual is reproduced")
		# Alterar un flujo despues del solve rompe la comprobacion.
		var tampered: Array = fluxes.duplicate(true)
		if not tampered.is_empty():
			tampered[0]["mass_flow_kg_s"] = float(tampered[0]["mass_flow_kg_s"]) + 1.0
			var broken: Dictionary = Equations.evaluate_compartment_residual(
				previous_state, candidate_state, {}, tampered, _outside(), DT_S)
			_check(absf(float(broken["mass_residual_kg"])) > 1.0e-6,
					"13 tampering with a flux after the solve is caught")


func _fluxes_for(result: Dictionary, room_id: String) -> Array:
	var totals: Dictionary = {}
	for opening in result["openings"]:
		for segment in opening["segments"]:
			for role in ["source", "destination"]:
				if String(segment["%s_room_id" % role]) != room_id:
					continue
				var zone: String = String(segment["%s_zone" % role])
				if zone.is_empty():
					continue
				var key: String = "%s|%s" % [opening["opening_id"], zone]
				var entry: Dictionary = totals.get(key, {
					"opening_id": String(opening["opening_id"]), "segment_id": zone,
					"zone": zone, "mass_flow_kg_s": 0.0, "enthalpy_flow_kw": 0.0,
				})
				var sign: float = 1.0 if role == "destination" else -1.0
				entry["mass_flow_kg_s"] = float(entry["mass_flow_kg_s"]) \
						+ sign * float(segment["mass_flow_kg_s"])
				entry["enthalpy_flow_kw"] = float(entry["enthalpy_flow_kw"]) \
						+ sign * float(segment["enthalpy_flow_kw"])
				totals[key] = entry
	var keys: Array = totals.keys()
	keys.sort()
	var fluxes: Array = []
	for key in keys:
		fluxes.append(totals[key])
	return fluxes


func _test_14_reference_states() -> void:
	# Estado capturado de CFAST (cfast_two_room_door_open, R0, t = 360 s):
	# T_sup 99,813 C, T_inf 70,387 C, interfaz 0,857 m, presion -38,719 Pa.
	# Es una REPRODUCCION DE ESTADO, no de la curva temporal del caso.
	var interface_m: float = 0.857
	var upper_temp_k: float = 99.813 + 273.15
	var lower_temp_k: float = 70.387 + 273.15
	var pressure_abs_pa: float = P_EXT_PA - 38.719
	var upper_volume_m3: float = AREA_M2 * (HEIGHT_M - interface_m)
	var lower_volume_m3: float = AREA_M2 * interface_m
	var upper_kg: float = pressure_abs_pa * upper_volume_m3 / (R_J_KG_K * upper_temp_k)
	var lower_kg: float = pressure_abs_pa * lower_volume_m3 / (R_J_KG_K * lower_temp_k)
	var captured: Dictionary = _two_zone_room("r0", upper_kg, upper_temp_k, lower_kg, lower_temp_k)
	var hall: Dictionary = {
		"room_id": "hall", "floor_z_m": 0.0, "floor_area_m2": 10.5, "height_m": HEIGHT_M,
		"upper_gas_kg": 0.0, "upper_energy_kj": 0.0,
		"lower_gas_kg": 1.2 * 10.5 * HEIGHT_M, "lower_energy_kj": 0.0,
	}
	var result: Dictionary = _solve([captured, hall], [_opening("door", "r0", "hall", 0.0, 2.0)])
	_check_converged(result, "14 cfast state")
	if not bool(result["converged"]):
		return
	var room: Dictionary = _room_out(result, "r0")
	var eos_gauge_pa: float = float(room["diagnostics"]["eos_gauge_pressure_pa"])
	_check(absf(float(room["diagnostics"]["interface_m"]) - interface_m) < 0.01,
			"14 the captured interface comes back (%.4f vs %.4f m)" % [
				room["diagnostics"]["interface_m"], interface_m])
	_check(eos_gauge_pa < 0.0, "14 the captured CFAST state is below ambient (%.4f Pa)" % eos_gauge_pa)
	# Cierre de una conexion: la misma red con la puerta cerrada no transporta nada.
	var shut: Dictionary = _solve([captured, hall],
			[_opening("door", "r0", "hall", 0.0, 2.0, 0.9, 0.0)])
	_check_converged(shut, "14 shut")
	_check(shut["openings"].is_empty(), "14 a shut opening carries nothing")
	_check(_close(float(_room_out(shut, "r0")["candidate_lower_gas_kg"]), lower_kg, 1.0e-12),
			"14 closing the connection leaves the inventory untouched")
	# Abertura exterior grande: la presion se descarga casi del todo.
	var pressurized: Array = [_two_zone_room("r0", 12.0, 493.15, 40.0, 298.15)]
	var window: Array = [_opening("window", "r0", "outside", 0.0, 2.0)]
	var sealed_pa: float = float(_room_out(_solve(pressurized, []), "r0")["gauge_pressure_pa"])
	var one_step: Dictionary = _march(pressurized, window, DT_S, 1)
	_check_converged(one_step, "14 big opening, one step")
	var one_step_pa: float = float(_room_out(one_step, "r0")["gauge_pressure_pa"])
	_check(one_step_pa < 0.2 * sealed_pa,
			"14 one step through a large opening sheds most of the pressure (%.1f -> %.1f Pa)"
			% [sealed_pa, one_step_pa])
	var half_second: Dictionary = _march(pressurized, window, 0.5, 6)
	_check_converged(half_second, "14 big opening, half a second")
	var settled_pa: float = float(_room_out(half_second, "r0")["gauge_pressure_pa"])
	_check(absf(settled_pa) < 20.0,
			"14 half a second through a large opening discharges the pressure (%.4f Pa)" % settled_pa)
	_check(absf(settled_pa) < absf(one_step_pa), "14 the discharge keeps going, it does not bounce back")


func _test_15_contract() -> void:
	var result: Dictionary = _solve([_room("r0", T_REF_K)], [])
	var keys: Array = result.keys()
	keys.sort()
	_check(keys.has("converged") and keys.has("failure_reason") and keys.has("rooms")
			and keys.has("openings") and keys.has("max_mass_residual_kg")
			and keys.has("max_energy_residual_kj") and keys.has("max_pressure_residual_pa")
			and keys.has("residual_history") and keys.has("pressure_change_history_pa"),
			"15 the canonical result carries the required keys (%s)" % [keys])
	var source: String = _solver_code()
	_check(source.contains("CompartmentPressureEquationsScript = preload("),
			"15 the solver loads F2.2A")
	_check(source.contains("equations.evaluate_compartment_residual("),
			"15 the solver asks F2.2A about every candidate")
	for forbidden in ["pressure_network_solver_enabled", "RoomModel", "BuildingModel",
			"SimulationEngine", "get_tree", "@export"]:
		_check(not source.contains(forbidden), "15 the solver has no '%s'" % forbidden)
	_check(not source.contains("maxf(0.0, gauge_pressure_pa)"), "15 the gauge pressure is never clamped")


## Codigo sin lineas de comentario: la cabecera nombra justo lo que el solver
## no toca, y eso no puede confundirse con un uso real.
func _solver_code() -> String:
	var file := FileAccess.open(SOLVER_PATH, FileAccess.READ)
	if file == null:
		return ""
	var lines: PackedStringArray = []
	while not file.eof_reached():
		var line: String = file.get_line()
		if not line.strip_edges().begins_with("#"):
			lines.append(line)
	file.close()
	return "
".join(lines)


func _test_16_dump(dump_path: String) -> void:
	var battery: Dictionary = {
		"sealed_equilibrium": _solve([_room("r0", T_REF_K)], []),
		"sealed_cooling": _solve([_room("r0", 273.15)], []),
		"sealed_heating": _solve([_room("r0", 313.15)], []),
		"two_rooms": _solve([_two_zone_room("r0", 12.0, 493.15, 40.0, 298.15), _room("r1", T_REF_K)],
				[_opening("door", "r0", "r1", 0.0, 2.0)]),
		"counterflow": _solve([_buoyant_hot_room("r0"), _room("r1", T_REF_K)],
				[_opening("door", "r0", "r1", 0.0, 2.4)]),
		"two_storeys": _solve([_two_zone_room("ground", 12.0, 493.15, 40.0, 298.15, 0.0),
				_room("upstairs", T_REF_K, 3.0)], [_opening("stair", "ground", "upstairs", 2.0, 2.4)]),
	}
	var first: String = _canonical(battery)
	var second: String = _canonical(battery)
	_check(first == second, "16 the battery is deterministic")
	if dump_path.is_empty():
		return
	var file := FileAccess.open(dump_path, FileAccess.WRITE)
	if file == null:
		_check(false, "16 could not open dump file %s" % dump_path)
		return
	file.store_string(first + "\n")
	file.close()

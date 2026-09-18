extends SceneTree

## Tests deterministas del evaluador puro de ecuaciones locales de presion,
## masa y energia (sim/core/CompartmentPressureEquations.gd, fase F2.2A).
## No arranca el motor, no carga escenarios y no resuelve ninguna red.
##
##   <godot> --headless --path . --script res://tools/validate_compartment_pressure_equations.gd
##   <godot> --headless --path . --script res://tools/validate_compartment_pressure_equations.gd -- --dump=<ruta.json>

const Equations := preload("res://sim/core/CompartmentPressureEquations.gd")
const MODEL_PATH: String = "res://sim/core/CompartmentPressureEquations.gd"

const T_REF_K: float = 293.15
const P_EXT_PA: float = 101325.0
const AREA_M2: float = 20.0
const HEIGHT_M: float = 2.4
const FLOOR_Z_M: float = 3.0
const VOLUME_M3: float = AREA_M2 * HEIGHT_M
const AMBIENT_MASS_KG: float = 1.2 * VOLUME_M3
const R_J_KG_K: float = P_EXT_PA / (1.2 * T_REF_K)
const TOL: float = 1.0e-9

var _failures: Array[String] = []
var _checks: int = 0


func _initialize() -> void:
	var dump_path: String = ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--dump="):
			dump_path = argument.substr("--dump=".length())
	_test_01_ambient_equilibrium()
	_test_02_sealed_cooling_is_negative()
	_test_03_sealed_heating_is_positive()
	_test_04_sources()
	_test_05_opening_fluxes()
	_test_06_two_zone_profile()
	_test_07_degenerate_zone()
	_test_08_invalid_inputs()
	_test_09_purity_and_determinism()
	_test_10_absolute_pressure()
	_test_11_contract_limits()
	_test_12_dump(dump_path)
	if _failures.is_empty():
		print("  %d checks" % _checks)
		print("COMPARTMENT PRESSURE EQUATIONS VALIDATION PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
		print("FAIL: " + failure)
	print("COMPARTMENT PRESSURE EQUATIONS VALIDATION FAIL (%d)" % _failures.size())
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
	return {"pressure_abs_pa": P_EXT_PA, "temp_k": T_REF_K, "reference_temp_k": T_REF_K,
			"density_kg_m3": 1.2}


## Estado con toda la masa en la zona inferior, a una temperatura uniforme.
func _uniform_state(temp_k: float, mass_kg: float = AMBIENT_MASS_KG) -> Dictionary:
	return {
		"room_id": "r0",
		"floor_z_m": FLOOR_Z_M,
		"height_m": HEIGHT_M,
		"floor_area_m2": AREA_M2,
		"upper_gas_kg": 0.0,
		"upper_energy_kj": 0.0,
		"lower_gas_kg": mass_kg,
		"lower_energy_kj": mass_kg * (temp_k - T_REF_K),
	}


func _with_pressure(state: Dictionary, gauge_pa: float) -> Dictionary:
	var candidate: Dictionary = state.duplicate(true)
	candidate["gauge_pressure_pa"] = gauge_pa
	return candidate


func _eos_gauge_pa(state: Dictionary) -> float:
	var mass_kg: float = float(state["upper_gas_kg"]) + float(state["lower_gas_kg"])
	var energy_kj: float = float(state["upper_energy_kj"]) + float(state["lower_energy_kj"])
	var reference_mass_kg: float = P_EXT_PA * VOLUME_M3 / (R_J_KG_K * T_REF_K)
	return R_J_KG_K * ((mass_kg - reference_mass_kg) * T_REF_K + energy_kj) / VOLUME_M3


func _evaluate(previous: Dictionary, candidate: Dictionary, sources: Dictionary = {},
		fluxes: Array = [], dt_s: float = 1.0) -> Dictionary:
	return Equations.evaluate_compartment_residual(previous, candidate, sources, fluxes, _outside(), dt_s)


func _rejected(result: Dictionary, message: String) -> void:
	_check(not bool(result["valid"]) and not result["errors"].is_empty()
			and is_nan(float(result["pressure_residual_pa"]))
			and result["pressure_profile"].is_empty(), message)


func _canonical(value: Variant) -> String:
	return JSON.stringify(value, "", true, true)


# ---------------------------------------------------------------- tests

func _test_01_ambient_equilibrium() -> void:
	var state: Dictionary = _uniform_state(T_REF_K)
	var result: Dictionary = _evaluate(state, _with_pressure(state, 0.0))
	_check(bool(result["valid"]), "01 ambient equilibrium is valid (%s)" % [result["errors"]])
	if not bool(result["valid"]):
		return
	_check(_close(float(result["pressure_residual_pa"]), 0.0), "01 pressure residual is zero (%s)" % result["pressure_residual_pa"])
	_check(_close(float(result["mass_residual_kg"]), 0.0), "01 mass residual is zero")
	_check(_close(float(result["energy_residual_kj"]), 0.0), "01 energy residual is zero")
	_check(_close(float(result["diagnostics"]["eos_gauge_pressure_pa"]), 0.0), "01 the ambient inventory gives 0 Pa gauge")
	_check(_close(float(result["diagnostics"]["eos_absolute_pressure_pa"]), P_EXT_PA), "01 absolute pressure is the exterior one")
	_check(_close(float(result["diagnostics"]["lower_temp_k"]), T_REF_K), "01 temperature is the reference one")
	_check(_close(float(result["diagnostics"]["mass_kg"]), AMBIENT_MASS_KG), "01 mass is the ambient inventory")
	# Repetir el mismo paso no introduce deriva.
	var second: Dictionary = _evaluate(state, _with_pressure(state, 0.0), {}, [], 60.0)
	_check(_close(float(second["mass_residual_kg"]), 0.0) and _close(float(second["energy_residual_kj"]), 0.0),
			"01 a 60 s step without sources still has no residual")


func _test_02_sealed_cooling_is_negative() -> void:
	var previous: Dictionary = _uniform_state(T_REF_K)
	var cooled: Dictionary = _uniform_state(273.15)
	var analytic_pa: float = P_EXT_PA * (273.15 / T_REF_K - 1.0)
	var eos_pa: float = _eos_gauge_pa(cooled)
	_check(analytic_pa < 0.0, "02 the analytic sealed cooling pressure is negative")
	_check(absf(eos_pa - analytic_pa) <= 0.01 * absf(analytic_pa),
			"02 the EOS reproduces the ideal gas value within 1%% (%.3f vs %.3f Pa)" % [eos_pa, analytic_pa])
	_check(absf(analytic_pa + 6912.843254) < 0.01, "02 the analytic value is about -6,9 kPa (%.3f)" % analytic_pa)
	var result: Dictionary = _evaluate(previous, _with_pressure(cooled, eos_pa), {},
			[{"opening_id": "sealed", "zone": "lower", "mass_flow_kg_s": 0.0, "enthalpy_flow_kw": 0.0}], 1.0)
	_check(bool(result["valid"]), "02 the cooled sealed state is valid (%s)" % [result["errors"]])
	if not bool(result["valid"]):
		return
	_check(float(result["diagnostics"]["eos_gauge_pressure_pa"]) < 0.0, "02 the model keeps the negative sign")
	_check(_close(float(result["pressure_residual_pa"]), 0.0), "02 the candidate pressure closes the EOS")
	_check(_close(float(result["mass_residual_kg"]), 0.0), "02 no mass moved")
	# La energia si cambio: sin fuente, el residuo tiene que denunciarlo.
	_check(_close(float(result["energy_residual_kj"]), -AMBIENT_MASS_KG * 20.0),
			"02 the energy residual reports the missing sink (%s)" % result["energy_residual_kj"])
	var profile: Array = result["pressure_profile"]
	_check(float(profile[0]["gauge_pressure_pa"]) < 0.0, "02 the floor node is negative")
	_check(float(result["diagnostics"]["candidate_absolute_pressure_pa"]) > 0.0, "02 absolute pressure stays positive")


func _test_03_sealed_heating_is_positive() -> void:
	var heated: Dictionary = _uniform_state(313.15)
	var analytic_pa: float = P_EXT_PA * (313.15 / T_REF_K - 1.0)
	var eos_pa: float = _eos_gauge_pa(heated)
	_check(eos_pa > 0.0 and absf(eos_pa - analytic_pa) <= 0.01 * absf(analytic_pa),
			"03 sealed heating is positive and matches the ideal gas value (%.3f vs %.3f)" % [eos_pa, analytic_pa])
	var cooled_pa: float = _eos_gauge_pa(_uniform_state(273.15))
	_check(_close(eos_pa, -cooled_pa, 1.0e-9), "03 heating and cooling by 20 K are symmetric (%.6f vs %.6f)" % [eos_pa, cooled_pa])
	var result: Dictionary = _evaluate(_uniform_state(T_REF_K), _with_pressure(heated, eos_pa))
	_check(bool(result["valid"]) and _close(float(result["pressure_residual_pa"]), 0.0), "03 the heated candidate closes the EOS")


func _test_04_sources() -> void:
	var previous: Dictionary = _uniform_state(T_REF_K)
	var dt_s: float = 4.0
	# Fuente de masa positiva en la zona inferior.
	var gained: Dictionary = previous.duplicate(true)
	gained["lower_gas_kg"] = float(previous["lower_gas_kg"]) + 2.0
	var sources: Dictionary = {"lower_mass_kg_s": 0.5}
	var result: Dictionary = _evaluate(previous, _with_pressure(gained, _eos_gauge_pa(gained)), sources, [], dt_s)
	_check(bool(result["valid"]) and _close(float(result["mass_residual_kg"]), 0.0),
			"04 a mass source of 0,5 kg/s during 4 s adds 2 kg (%s)" % result["mass_residual_kg"])
	_check(_close(float(result["diagnostics"]["eos_gauge_pressure_pa"]), R_J_KG_K * 2.0 * T_REF_K / VOLUME_M3),
			"04 the added mass raises the pressure by the EOS amount")
	# Sin dt, el residuo sale exactamente de la masa que falta.
	var wrong: Dictionary = _evaluate(previous, _with_pressure(gained, _eos_gauge_pa(gained)), sources, [], 1.0)
	_check(_close(float(wrong["mass_residual_kg"]), 1.5), "04 with dt = 1 s the residual is 1,5 kg (%s)" % wrong["mass_residual_kg"])
	# Fuente de masa negativa.
	var lost: Dictionary = previous.duplicate(true)
	lost["lower_gas_kg"] = float(previous["lower_gas_kg"]) - 2.0
	var negative: Dictionary = _evaluate(previous, _with_pressure(lost, _eos_gauge_pa(lost)),
			{"lower_mass_kg_s": -0.5}, [], dt_s)
	_check(bool(negative["valid"]) and _close(float(negative["mass_residual_kg"]), 0.0),
			"04 a negative mass source removes mass")
	# Fuente de entalpia positiva y negativa: kW por dt da kJ.
	for sign_value in [1.0, -1.0]:
		var energy_kj: float = sign_value * 12.0 * dt_s
		var heated: Dictionary = previous.duplicate(true)
		heated["lower_energy_kj"] = float(previous["lower_energy_kj"]) + energy_kj
		var energy_result: Dictionary = _evaluate(previous, _with_pressure(heated, _eos_gauge_pa(heated)),
				{"lower_enthalpy_kw": sign_value * 12.0}, [], dt_s)
		_check(bool(energy_result["valid"]) and _close(float(energy_result["energy_residual_kj"]), 0.0),
				"04 an enthalpy source of %s kW during %s s gives %s kJ" % [sign_value * 12.0, dt_s, energy_kj])
	# kW y kJ no son intercambiables: usar el valor en kJ como si fuese kW falla.
	var confused: Dictionary = previous.duplicate(true)
	confused["lower_energy_kj"] = float(previous["lower_energy_kj"]) + 48.0
	var confused_result: Dictionary = _evaluate(previous, _with_pressure(confused, _eos_gauge_pa(confused)),
			{"lower_enthalpy_kw": 48.0}, [], dt_s)
	_check(_close(float(confused_result["energy_residual_kj"]), 48.0 - 48.0 * dt_s),
			"04 confusing kJ with kW leaves a residual of %s kJ" % (48.0 - 48.0 * dt_s))
	# Las fuentes de cada zona no se mezclan.
	var upper_source: Dictionary = _evaluate(previous, _with_pressure(gained, _eos_gauge_pa(gained)),
			{"upper_mass_kg_s": 0.5}, [], dt_s)
	_check(_close(float(upper_source["mass_residual_by_zone_kg"]["lower"]), 2.0)
			and _close(float(upper_source["mass_residual_by_zone_kg"]["upper"]), -2.0),
			"04 a source in the wrong zone is reported zone by zone")


func _test_05_opening_fluxes() -> void:
	var previous: Dictionary = _uniform_state(T_REF_K)
	var dt_s: float = 2.0
	var inflow: Array = [
		{"opening_id": "door", "segment_id": "s0", "zone": "lower", "mass_flow_kg_s": 1.5, "enthalpy_flow_kw": 30.0},
		{"opening_id": "door", "segment_id": "s1", "zone": "upper", "mass_flow_kg_s": -0.5, "enthalpy_flow_kw": -20.0},
	]
	var candidate: Dictionary = previous.duplicate(true)
	candidate["lower_gas_kg"] = float(previous["lower_gas_kg"]) + 1.5 * dt_s
	candidate["lower_energy_kj"] = float(previous["lower_energy_kj"]) + 30.0 * dt_s
	candidate["upper_gas_kg"] = 1.0  # -0.5 kg/s durante 2 s desde 2 kg
	candidate["upper_energy_kj"] = -40.0
	var previous_upper: Dictionary = previous.duplicate(true)
	previous_upper["upper_gas_kg"] = 2.0
	previous_upper["upper_energy_kj"] = 0.0
	var result: Dictionary = _evaluate(previous_upper, _with_pressure(candidate, _eos_gauge_pa(candidate)), {}, inflow, dt_s)
	_check(bool(result["valid"]), "05 candidate with fluxes is valid (%s)" % [result["errors"]])
	if not bool(result["valid"]):
		return
	_check(_close(float(result["mass_residual_kg"]), 0.0), "05 in and out flows balance the mass (%s)" % result["mass_residual_kg"])
	_check(_close(float(result["energy_residual_kj"]), 0.0), "05 in and out flows balance the energy (%s)" % result["energy_residual_kj"])
	_check(_close(float(result["diagnostics"]["flux_mass_kg_s"]["lower"]), 1.5)
			and _close(float(result["diagnostics"]["flux_mass_kg_s"]["upper"]), -0.5),
			"05 the sign convention keeps inflow positive and outflow negative")
	# El orden de los segmentos no cambia nada.
	var reversed_fluxes: Array = inflow.duplicate(true)
	reversed_fluxes.reverse()
	var reordered: Dictionary = _evaluate(previous_upper, _with_pressure(candidate, _eos_gauge_pa(candidate)), {}, reversed_fluxes, dt_s)
	_check(_canonical(reordered) == _canonical(result), "05 reversing the flux list gives byte-identical output")
	# Flujos que se cancelan dan balance neto cero.
	var cancelling: Array = [
		{"opening_id": "window", "segment_id": "a", "zone": "lower", "mass_flow_kg_s": 3.0, "enthalpy_flow_kw": 60.0},
		{"opening_id": "window", "segment_id": "b", "zone": "lower", "mass_flow_kg_s": -3.0, "enthalpy_flow_kw": -60.0},
	]
	var cancelled: Dictionary = _evaluate(previous, _with_pressure(previous, 0.0), {}, cancelling, dt_s)
	_check(bool(cancelled["valid"]) and _close(float(cancelled["mass_residual_kg"]), 0.0)
			and _close(float(cancelled["energy_residual_kj"]), 0.0), "05 cancelling flows leave no residual")
	_check(_close(float(cancelled["diagnostics"]["flux_mass_kg_s"]["lower"]), 0.0), "05 the net flux is zero")
	# Suma sensible al orden: sin un orden fijo, el resultado cambiaria.
	var catastrophic: Array = [
		{"opening_id": "a", "zone": "lower", "mass_flow_kg_s": 1.0e16, "enthalpy_flow_kw": 0.0},
		{"opening_id": "b", "zone": "lower", "mass_flow_kg_s": -1.0e16, "enthalpy_flow_kw": 0.0},
		{"opening_id": "c", "zone": "lower", "mass_flow_kg_s": 1.0, "enthalpy_flow_kw": 0.0},
	]
	var forward: Dictionary = _evaluate(previous, _with_pressure(previous, 0.0), {}, catastrophic, 1.0)
	var backward_fluxes: Array = catastrophic.duplicate(true)
	backward_fluxes.reverse()
	var backward: Dictionary = _evaluate(previous, _with_pressure(previous, 0.0), {}, backward_fluxes, 1.0)
	_check(_close(float(forward["diagnostics"]["flux_mass_kg_s"]["lower"]), 1.0),
			"05 the fixed sum order keeps the small term (%s)" % forward["diagnostics"]["flux_mass_kg_s"]["lower"])
	_check(_canonical(forward) == _canonical(backward),
			"05 an order-sensitive sum still gives byte-identical output")
	# Invertir el signo de un flujo rompe el balance.
	var flipped: Array = inflow.duplicate(true)
	flipped[0]["mass_flow_kg_s"] = -1.5
	var flipped_result: Dictionary = _evaluate(previous_upper, _with_pressure(candidate, _eos_gauge_pa(candidate)), {}, flipped, dt_s)
	_check(_close(float(flipped_result["mass_residual_kg"]), 2.0 * 1.5 * dt_s),
			"05 flipping a flux sign doubles the residual (%s)" % flipped_result["mass_residual_kg"])


func _test_06_two_zone_profile() -> void:
	var state: Dictionary = {
		"room_id": "r0", "floor_z_m": FLOOR_Z_M, "height_m": HEIGHT_M, "floor_area_m2": AREA_M2,
		"upper_gas_kg": 12.0, "upper_energy_kj": 12.0 * 200.0,
		"lower_gas_kg": 40.0, "lower_energy_kj": 40.0 * 5.0,
	}
	var result: Dictionary = _evaluate(state, _with_pressure(state, _eos_gauge_pa(state)))
	_check(bool(result["valid"]), "06 the two-zone state is valid (%s)" % [result["errors"]])
	if not bool(result["valid"]):
		return
	var diagnostics: Dictionary = result["diagnostics"]
	var upper_temp_k: float = float(diagnostics["upper_temp_k"])
	var lower_temp_k: float = float(diagnostics["lower_temp_k"])
	_check(_close(upper_temp_k, T_REF_K + 200.0) and _close(lower_temp_k, T_REF_K + 5.0),
			"06 zone temperatures come from energy over mass")
	_check(upper_temp_k > lower_temp_k, "06 the upper zone is the hot one")
	var upper_density: float = float(diagnostics["upper_density_kg_m3"])
	var lower_density: float = float(diagnostics["lower_density_kg_m3"])
	_check(upper_density < lower_density, "06 the hot zone is lighter (%.4f vs %.4f)" % [upper_density, lower_density])
	_check(_close(float(diagnostics["volume_closure_error_m3"]), 0.0, 1.0e-12), "06 the zone volumes close the room volume")
	var interface_m: float = float(diagnostics["interface_m"])
	_check(interface_m > 0.0 and interface_m < HEIGHT_M, "06 the interface lies inside the room (%.4f)" % interface_m)
	var profile: Array = result["pressure_profile"]
	_check(profile.size() == 3, "06 the profile has floor, interface and ceiling")
	_check(_close(float(profile[0]["z_m"]), FLOOR_Z_M), "06 the reference node is the floor")
	_check(_close(float(profile[1]["z_m"]), FLOOR_Z_M + interface_m), "06 the second node is the interface")
	_check(_close(float(profile[2]["z_m"]), FLOOR_Z_M + HEIGHT_M), "06 the last node is the ceiling")
	_check(_close(float(profile[0]["gauge_pressure_pa"]), float(_with_pressure(state, _eos_gauge_pa(state))["gauge_pressure_pa"])),
			"06 the floor node carries the candidate pressure")
	var lower_slope: float = (float(profile[0]["gauge_pressure_pa"]) - float(profile[1]["gauge_pressure_pa"])) / interface_m
	_check(_close(lower_slope, lower_density * 9.81, 1.0e-9), "06 the lower slope is rho_lower * g (%.6f)" % lower_slope)
	var upper_slope: float = (float(profile[1]["gauge_pressure_pa"]) - float(profile[2]["gauge_pressure_pa"])) \
			/ (HEIGHT_M - interface_m)
	_check(_close(upper_slope, upper_density * 9.81, 1.0e-9), "06 the upper slope is rho_upper * g (%.6f)" % upper_slope)
	_check(upper_slope < lower_slope, "06 the profile bends at the interface")
	# Continuidad: el nodo de interfaz es unico, y llegar por abajo o por arriba da lo mismo.
	var from_below: float = float(profile[0]["gauge_pressure_pa"]) - lower_density * 9.81 * interface_m
	var from_above: float = float(profile[2]["gauge_pressure_pa"]) + upper_density * 9.81 * (HEIGHT_M - interface_m)
	_check(_close(from_below, float(profile[1]["gauge_pressure_pa"]), 1.0e-9)
			and _close(from_above, float(profile[1]["gauge_pressure_pa"]), 1.0e-9),
			"06 the profile is continuous at the interface")
	_check(_close(float(diagnostics["reference_z_m"]), FLOOR_Z_M), "06 the reference height is the floor")
	# La cota del suelo desplaza el perfil pero no las diferencias.
	var raised: Dictionary = state.duplicate(true)
	raised["floor_z_m"] = FLOOR_Z_M + 10.0
	var raised_result: Dictionary = _evaluate(raised, _with_pressure(raised, _eos_gauge_pa(raised)))
	_check(_close(float(raised_result["pressure_profile"][0]["z_m"]), FLOOR_Z_M + 10.0)
			and _close(float(raised_result["pressure_profile"][0]["gauge_pressure_pa"]),
					float(profile[0]["gauge_pressure_pa"])),
			"06 moving the floor moves the profile, not the reference pressure")


func _test_07_degenerate_zone() -> void:
	# Solo zona inferior: la densidad superior se extiende sin inventar masa.
	var lower_only: Dictionary = _uniform_state(T_REF_K)
	var result: Dictionary = _evaluate(lower_only, _with_pressure(lower_only, 0.0))
	_check(bool(result["valid"]), "07 a single-zone compartment is valid (%s)" % [result["errors"]])
	if not bool(result["valid"]):
		return
	var diagnostics: Dictionary = result["diagnostics"]
	_check(bool(diagnostics["upper_degenerate"]) and not bool(diagnostics["lower_degenerate"]),
			"07 the empty zone is flagged as degenerate")
	_check(_close(float(diagnostics["upper_density_kg_m3"]), float(diagnostics["lower_density_kg_m3"])),
			"07 the degenerate zone borrows the density of the occupied one")
	_check(_close(float(diagnostics["mass_kg"]), AMBIENT_MASS_KG), "07 no mass was invented")
	_check(_close(float(diagnostics["interface_m"]), HEIGHT_M), "07 the interface sits at the ceiling")
	var profile: Array = result["pressure_profile"]
	_check(_close(float(profile[1]["z_m"]), float(profile[2]["z_m"])), "07 the upper segment has zero thickness")
	_check(_close(float(profile[2]["gauge_pressure_pa"]),
			-float(diagnostics["lower_density_kg_m3"]) * 9.81 * HEIGHT_M),
			"07 the ceiling pressure is the full hydrostatic column")
	# Solo zona superior.
	var upper_only: Dictionary = _uniform_state(T_REF_K)
	upper_only["upper_gas_kg"] = float(upper_only["lower_gas_kg"])
	upper_only["upper_energy_kj"] = float(upper_only["lower_energy_kj"])
	upper_only["lower_gas_kg"] = 0.0
	upper_only["lower_energy_kj"] = 0.0
	var upper_result: Dictionary = _evaluate(upper_only, _with_pressure(upper_only, 0.0))
	_check(bool(upper_result["valid"]), "07 an upper-only compartment is valid too (%s)" % [upper_result["errors"]])
	if not bool(upper_result["valid"]):
		return
	var upper_diagnostics: Dictionary = upper_result["diagnostics"]
	_check(bool(upper_diagnostics["lower_degenerate"]), "07 the empty lower zone is flagged")
	_check(_close(float(upper_diagnostics["interface_m"]), 0.0), "07 the interface sits at the floor")
	_check(_close(float(upper_diagnostics["mass_kg"]), AMBIENT_MASS_KG), "07 no mass was invented in the upper case")


func _test_08_invalid_inputs() -> void:
	var state: Dictionary = _uniform_state(T_REF_K)
	var candidate: Dictionary = _with_pressure(state, 0.0)
	_rejected(_evaluate(state, candidate, {}, [], 0.0), "08 dt = 0 is rejected")
	_rejected(_evaluate(state, candidate, {}, [], -1.0), "08 a negative dt is rejected")
	_rejected(_evaluate(state, candidate, {}, [], NAN), "08 a NaN dt is rejected")
	_rejected(Equations.evaluate_compartment_residual(state, candidate, {}, [], _outside(), "1"), "08 a non-numeric dt is rejected")
	for bad_value in [NAN, INF, -INF]:
		var bad_pressure: Dictionary = _with_pressure(state, bad_value)
		_rejected(_evaluate(state, bad_pressure), "08 a non-finite candidate pressure is rejected")
		var bad_mass: Dictionary = candidate.duplicate(true)
		bad_mass["lower_gas_kg"] = bad_value
		_rejected(_evaluate(state, bad_mass), "08 a non-finite mass is rejected")
		var bad_energy: Dictionary = candidate.duplicate(true)
		bad_energy["lower_energy_kj"] = bad_value
		_rejected(_evaluate(state, bad_energy), "08 a non-finite energy is rejected")
		_rejected(_evaluate(state, candidate, {"lower_mass_kg_s": bad_value}), "08 a non-finite source is rejected")
		_rejected(_evaluate(state, candidate, {}, [{"opening_id": "d", "zone": "lower",
				"mass_flow_kg_s": bad_value, "enthalpy_flow_kw": 0.0}]), "08 a non-finite flux is rejected")
	var negative_mass: Dictionary = candidate.duplicate(true)
	negative_mass["lower_gas_kg"] = -1.0
	_rejected(_evaluate(state, negative_mass), "08 a negative mass is rejected")
	# Una masa negativa en una zona no puede esconderse tras el total positivo.
	var negative_zone: Dictionary = candidate.duplicate(true)
	negative_zone["upper_gas_kg"] = -1.0
	_rejected(_evaluate(state, negative_zone), "08 a negative zone mass is rejected even with a positive total")
	var no_mass: Dictionary = candidate.duplicate(true)
	no_mass["lower_gas_kg"] = 0.0
	no_mass["lower_energy_kj"] = 0.0
	_rejected(_evaluate(state, no_mass), "08 an empty compartment is rejected")
	var energy_without_mass: Dictionary = candidate.duplicate(true)
	energy_without_mass["upper_energy_kj"] = 10.0
	_rejected(_evaluate(state, energy_without_mass), "08 upper energy without mass is rejected")
	var lower_energy_without_mass: Dictionary = candidate.duplicate(true)
	lower_energy_without_mass["upper_gas_kg"] = AMBIENT_MASS_KG
	lower_energy_without_mass["lower_gas_kg"] = 0.0
	lower_energy_without_mass["lower_energy_kj"] = -10.0
	_rejected(_evaluate(state, lower_energy_without_mass), "08 lower energy without mass is rejected")
	var frozen: Dictionary = candidate.duplicate(true)
	frozen["lower_energy_kj"] = -AMBIENT_MASS_KG * T_REF_K
	_rejected(_evaluate(state, frozen), "08 a zone temperature of 0 K is rejected")
	for key in ["height_m", "floor_area_m2"]:
		for bad_geometry in [0.0, -1.0]:
			var geometry: Dictionary = candidate.duplicate(true)
			geometry[key] = bad_geometry
			var previous_geometry: Dictionary = state.duplicate(true)
			previous_geometry[key] = bad_geometry
			_rejected(_evaluate(previous_geometry, geometry), "08 %s = %s is rejected" % [key, bad_geometry])
	var moved: Dictionary = candidate.duplicate(true)
	moved["height_m"] = HEIGHT_M + 0.5
	_rejected(_evaluate(state, moved), "08 geometry cannot change within a step")
	var other_room: Dictionary = candidate.duplicate(true)
	other_room["room_id"] = "r1"
	_rejected(_evaluate(state, other_room), "08 previous and candidate must be the same room")
	var no_id: Dictionary = candidate.duplicate(true)
	no_id["room_id"] = "   "
	_rejected(_evaluate(state, no_id), "08 a blank room_id is rejected")
	for key in ["room_id", "height_m", "floor_area_m2", "floor_z_m", "upper_gas_kg", "lower_gas_kg",
			"upper_energy_kj", "lower_energy_kj", "gauge_pressure_pa"]:
		var missing: Dictionary = candidate.duplicate(true)
		missing.erase(key)
		_rejected(_evaluate(state, missing), "08 a candidate without '%s' is rejected" % key)
	var no_pressure: Dictionary = candidate.duplicate(true)
	no_pressure.erase("gauge_pressure_pa")
	_rejected(_evaluate(state, no_pressure), "08 the candidate needs a pressure")
	var declared: Dictionary = candidate.duplicate(true)
	declared["declared_interface_height_m"] = HEIGHT_M + 1.0
	_rejected(_evaluate(state, declared), "08 a declared interface outside the room is rejected")
	declared["declared_interface_height_m"] = 1.0
	var declared_result: Dictionary = _evaluate(state, declared)
	_check(bool(declared_result["valid"])
			and declared_result["diagnostics"].has("declared_interface_divergence_m"),
			"08 a declared interface is only reported, never used")
	for bad_outside in [{"temp_k": T_REF_K, "reference_temp_k": T_REF_K},
			{"pressure_abs_pa": 0.0, "temp_k": T_REF_K, "reference_temp_k": T_REF_K},
			{"pressure_abs_pa": P_EXT_PA, "temp_k": -5.0, "reference_temp_k": T_REF_K},
			{"pressure_abs_pa": P_EXT_PA, "temp_k": T_REF_K, "reference_temp_k": NAN}]:
		_rejected(Equations.evaluate_compartment_residual(state, candidate, {}, [], bad_outside, 1.0),
				"08 an invalid outside state is rejected")
	_rejected(Equations.evaluate_compartment_residual(state, candidate, {}, [], "outside", 1.0), "08 a non-dictionary outside is rejected")
	_rejected(Equations.evaluate_compartment_residual("previous", candidate, {}, [], _outside(), 1.0), "08 a non-dictionary previous state is rejected")
	_rejected(Equations.evaluate_compartment_residual(state, "candidate", {}, [], _outside(), 1.0), "08 a non-dictionary candidate is rejected")
	_rejected(Equations.evaluate_compartment_residual(state, candidate, "sources", [], _outside(), 1.0), "08 non-dictionary sources are rejected")
	_rejected(Equations.evaluate_compartment_residual(state, candidate, {}, "fluxes", _outside(), 1.0), "08 non-array fluxes are rejected")
	_rejected(_evaluate(state, candidate, {}, [{"opening_id": "d", "zone": "middle",
			"mass_flow_kg_s": 0.0, "enthalpy_flow_kw": 0.0}]), "08 an unknown zone is rejected")
	_rejected(_evaluate(state, candidate, {}, [{"opening_id": "", "zone": "lower",
			"mass_flow_kg_s": 0.0, "enthalpy_flow_kw": 0.0}]), "08 a blank opening_id is rejected")
	_rejected(_evaluate(state, candidate, {}, [{"zone": "lower", "mass_flow_kg_s": 0.0, "enthalpy_flow_kw": 0.0}]),
			"08 a flux without opening_id is rejected")
	_rejected(_evaluate(state, candidate, {}, [
			{"opening_id": "d", "segment_id": "s", "zone": "lower", "mass_flow_kg_s": 1.0, "enthalpy_flow_kw": 0.0},
			{"opening_id": "d", "segment_id": "s", "zone": "lower", "mass_flow_kg_s": 2.0, "enthalpy_flow_kw": 0.0}]),
			"08 a duplicated flux key is rejected")


func _test_09_purity_and_determinism() -> void:
	var previous: Dictionary = _uniform_state(T_REF_K)
	var candidate: Dictionary = _with_pressure(_uniform_state(350.0), 1234.5)
	var sources: Dictionary = {"upper_enthalpy_kw": 3.0, "lower_mass_kg_s": -0.25}
	var fluxes: Array = [
		{"opening_id": "door", "segment_id": "s1", "zone": "lower", "mass_flow_kg_s": 0.75, "enthalpy_flow_kw": 9.0},
		{"opening_id": "door", "segment_id": "s0", "zone": "upper", "mass_flow_kg_s": -0.25, "enthalpy_flow_kw": -4.0},
	]
	var inputs: Array = [previous, candidate, sources, fluxes]
	var before: String = _canonical(inputs)
	var first: Dictionary = Equations.evaluate_compartment_residual(previous, candidate, sources, fluxes, _outside(), 3.0)
	_check(_canonical(inputs) == before, "09 the inputs are not modified")
	var second: Dictionary = Equations.evaluate_compartment_residual(previous, candidate, sources, fluxes, _outside(), 3.0)
	_check(_canonical(first) == _canonical(second), "09 two identical calls give identical output")
	first["pressure_profile"][0]["gauge_pressure_pa"] = 0.0
	first["diagnostics"]["mass_kg"] = -1.0
	_check(_canonical(inputs) == before, "09 the output does not alias the inputs")
	var third: Dictionary = Equations.evaluate_compartment_residual(previous, candidate, sources, fluxes, _outside(), 3.0)
	_check(_canonical(third) == _canonical(second), "09 mutating the output does not affect later calls")


func _test_10_absolute_pressure() -> void:
	var state: Dictionary = _uniform_state(T_REF_K)
	_rejected(_evaluate(state, _with_pressure(state, -P_EXT_PA)), "10 a candidate at absolute zero is rejected")
	_rejected(_evaluate(state, _with_pressure(state, -2.0 * P_EXT_PA)), "10 a negative absolute pressure is rejected")
	var barely: Dictionary = _evaluate(state, _with_pressure(state, -P_EXT_PA + 1.0))
	_check(bool(barely["valid"]) and float(barely["diagnostics"]["candidate_absolute_pressure_pa"]) > 0.0,
			"10 a very low but positive absolute pressure is accepted")
	_check(float(barely["pressure_residual_pa"]) < 0.0, "10 an impossible candidate leaves a large negative residual")
	var deep: Dictionary = _uniform_state(1.0)
	_check(_eos_gauge_pa(deep) < 0.0, "10 a nearly frozen compartment is deeply negative")


func _test_11_contract_limits() -> void:
	var state: Dictionary = _uniform_state(T_REF_K)
	var result: Dictionary = _evaluate(state, _with_pressure(state, 0.0))
	var keys: Array = result.keys()
	keys.sort()
	_check(keys == ["diagnostics", "energy_residual_by_zone_kj", "energy_residual_kj", "errors",
			"mass_residual_by_zone_kg", "mass_residual_kg", "pressure_profile",
			"pressure_residual_normalized", "pressure_residual_pa", "room_id", "valid"],
			"11 the result keys are fixed (%s)" % [keys])
	var text: String = _canonical(result).to_lower()
	for word in ["converged", "iteration", "flow_coefficient", "discharge", "bernoulli", "neutral_plane",
			"open_fraction", "thermal_gap", "smoke", "species"]:
		_check(not text.contains(word), "11 the output says nothing about '%s'" % word)
	var code: String = _code_lines()
	for word in ["sqrt(", "while ", "converged", "iterate", "neutral", "discharge", "preload(", "load(",
			"class_name", "RoomModel", "SimulationEngine", "Phase3", "get_tree", "FileAccess", "randf"]:
		_check(not code.contains(word), "11 the model code has no '%s'" % word)
	_check(not code.to_lower().contains("maxf(0.0, gauge") and not code.to_lower().contains("clampf(gauge"),
			"11 the model never clamps the gauge pressure")
	_check(code.begins_with("extends RefCounted"), "11 the model is a RefCounted")


func _code_lines() -> String:
	var file := FileAccess.open(MODEL_PATH, FileAccess.READ)
	if file == null:
		return ""
	var lines: PackedStringArray = []
	while not file.eof_reached():
		var line: String = file.get_line()
		if not line.strip_edges().begins_with("#"):
			lines.append(line)
	file.close()
	return "\n".join(lines)


func _test_12_dump(dump_path: String) -> void:
	var battery: Dictionary = {}
	var previous: Dictionary = _uniform_state(T_REF_K)
	battery["equilibrium"] = _evaluate(previous, _with_pressure(previous, 0.0))
	var cooled: Dictionary = _uniform_state(273.15)
	battery["sealed_cooling"] = _evaluate(previous, _with_pressure(cooled, _eos_gauge_pa(cooled)))
	var heated: Dictionary = _uniform_state(313.15)
	battery["sealed_heating"] = _evaluate(previous, _with_pressure(heated, _eos_gauge_pa(heated)))
	var two_zone: Dictionary = {
		"room_id": "r0", "floor_z_m": FLOOR_Z_M, "height_m": HEIGHT_M, "floor_area_m2": AREA_M2,
		"upper_gas_kg": 12.0, "upper_energy_kj": 2400.0, "lower_gas_kg": 40.0, "lower_energy_kj": 200.0,
	}
	battery["two_zone"] = _evaluate(two_zone, _with_pressure(two_zone, _eos_gauge_pa(two_zone)), {},
			[{"opening_id": "door", "segment_id": "s0", "zone": "lower", "mass_flow_kg_s": 0.5, "enthalpy_flow_kw": 10.0}], 2.0)
	var first: String = _canonical(battery)
	var second: String = _canonical(battery)
	_check(first == second, "12 the battery is deterministic")
	if dump_path.is_empty():
		return
	var file := FileAccess.open(dump_path, FileAccess.WRITE)
	if file == null:
		_check(false, "12 could not open dump file %s" % dump_path)
		return
	file.store_string(first + "\n")
	file.close()

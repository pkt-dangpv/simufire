extends SceneTree

const Phase3ZoneMassSystemScript = preload("res://sim/core/Phase3ZoneMassSystem.gd")


var _failed: bool = false


func _init() -> void:
	var system = Phase3ZoneMassSystemScript.new()

	var ambient: Dictionary = system.derive_canonical_thermodynamic_state(
		0.0, 48.0, 0.0, 0.0, 40.0, 16.0, 2.5, 20.0
	)
	_assert_true(bool(ambient.get("valid", false)), "ambient state valid")
	_assert_close(float(ambient.get("pressure_abs_pa", 0.0)), 101325.0, 1.0e-6, "ambient pressure")
	_assert_close(float(ambient.get("lower_volume_m3", 0.0)), 40.0, 1.0e-9, "ambient lower volume")
	_assert_close(float(ambient.get("interface_m", 0.0)), 2.5, 1.0e-9, "ambient interface")
	_assert_closure(ambient, "ambient")

	var upper_mass_kg: float = 8.0
	var lower_mass_kg: float = 40.0
	var upper_energy_kj: float = 8.0 * 180.0
	var lower_energy_kj: float = 40.0 * 20.0
	var stratified: Dictionary = system.derive_canonical_thermodynamic_state(
		upper_mass_kg, lower_mass_kg, upper_energy_kj, lower_energy_kj,
		40.0, 16.0, 2.5, 20.0
	)
	_assert_true(bool(stratified.get("valid", false)), "stratified state valid")
	_assert_close(float(stratified.get("temp_upper_c", 0.0)), 200.0, 1.0e-9, "upper temperature")
	_assert_close(float(stratified.get("temp_lower_c", 0.0)), 40.0, 1.0e-9, "lower temperature")
	_assert_true(float(stratified.get("pressure_abs_pa", 0.0)) > 101325.0, "heated pressure rises")
	_assert_true(float(stratified.get("interface_m", -1.0)) >= 0.0, "interface lower bound")
	_assert_true(float(stratified.get("interface_m", 3.0)) <= 2.5, "interface upper bound")
	_assert_closure(stratified, "stratified")
	_assert_close(upper_mass_kg, 8.0, 0.0, "upper input invariant")
	_assert_close(lower_mass_kg, 40.0, 0.0, "lower input invariant")
	_assert_close(upper_energy_kj, 1440.0, 0.0, "upper energy input invariant")
	_assert_close(lower_energy_kj, 800.0, 0.0, "lower energy input invariant")

	var near_empty: Dictionary = system.derive_canonical_thermodynamic_state(
		1.0e-9, 48.0, 1.0e-7, 0.0, 40.0, 16.0, 2.5, 20.0
	)
	_assert_true(bool(near_empty.get("valid", false)), "near-empty upper zone stable")
	_assert_closure(near_empty, "near-empty")

	var energy_without_mass: Dictionary = system.derive_canonical_thermodynamic_state(
		0.0, 48.0, 1.0, 0.0, 40.0, 16.0, 2.5, 20.0
	)
	_assert_true(not bool(energy_without_mass.get("valid", true)), "energy without mass rejected")
	_assert_close(float(energy_without_mass.get("failure_code", 0.0)), 4.0, 0.0, "energy failure code")

	var negative: Dictionary = system.derive_canonical_thermodynamic_state(
		-1.0, 48.0, 0.0, 0.0, 40.0, 16.0, 2.5, 20.0
	)
	_assert_true(not bool(negative.get("valid", true)), "negative inventory rejected")
	_assert_close(float(negative.get("failure_code", 0.0)), 2.0, 0.0, "negative failure code")

	var repeated: Dictionary = system.derive_canonical_thermodynamic_state(
		8.0, 40.0, 1440.0, 800.0, 40.0, 16.0, 2.5, 20.0
	)
	for key in stratified.keys():
		if typeof(stratified[key]) == TYPE_FLOAT:
			_assert_close(float(repeated.get(key, 0.0)), float(stratified[key]), 0.0, "deterministic %s" % key)

	# `quit()` only requests a shutdown, so execution continues. Return
	# explicitly or the PASS marker below would still be printed.
	if _failed:
		quit(1)
		return
	print("PHASE3_F31E_THERMODYNAMIC_CLOSURE_PASS")
	quit(0)


func _assert_closure(state: Dictionary, label: String) -> void:
	_assert_close(float(state.get("volume_closure_error_m3", 1.0)), 0.0, 1.0e-9, label + " volume closure")
	_assert_close(float(state.get("mass_invariance_residual_kg", 1.0)), 0.0, 0.0, label + " mass invariant")
	_assert_close(float(state.get("energy_invariance_residual_kj", 1.0)), 0.0, 0.0, label + " energy invariant")
	_assert_close(float(state.get("canonical_transaction_closure_flag", 0.0)), 1.0, 0.0, label + " closure flag")


func _assert_true(value: bool, label: String) -> void:
	if not value:
		_fail(label)


func _assert_close(actual: float, expected: float, tolerance: float, label: String) -> void:
	if absf(actual - expected) > tolerance:
		_fail("%s expected %.12g got %.12g" % [label, expected, actual])


func _fail(message: String) -> void:
	push_error(message)
	_failed = true

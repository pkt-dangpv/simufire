extends SceneTree

const Solver = preload("res://sim/core/Phase3SurfaceEnergySolver.gd")

var _failed: bool = false
var _early_surface_c: float = NAN
var _early_relative_error: float = NAN
var _long_run_residual_kj: float = NAN


func _init() -> void:
	_test_constant_ambient_is_noop()
	_test_radiation_only_closes_energy()
	_test_prescribed_boundary_energies_close_exactly()
	_test_prescribed_boundary_conflicts_fail_closed()
	_test_zero_area_surface_is_inert()
	_test_early_convection_matches_semi_infinite_reference()
	_test_long_run_conserves_energy()
	_test_input_state_is_immutable()
	_test_invalid_state_fails_closed()
	if _failed:
		quit(1)
	else:
		var metrics: String = (
			"F33R2A_METRICS early_surface_c=%.9f early_relative_error=%.9f "
			+ "long_run_residual_kj=%.12f"
		) % [_early_surface_c, _early_relative_error, _long_run_residual_kj]
		print(metrics)
		print("PHASE3_F33R2A_SURFACE_ENERGY_SOLVER_PASS")
		quit(0)


func _concrete_state(area_m2: float = 1.0) -> Dictionary:
	return Solver.make_uniform_state(
		area_m2,
		0.15,
		0.00175,
		2200.0,
		1.0,
		20.0,
		20.0
	)


func _test_constant_ambient_is_noop() -> void:
	var state: Dictionary = _concrete_state()
	var result: Dictionary = Solver.step_surface(state, {
		"dt_s": 1.0,
		"interior_gas_temp_c": 20.0,
		"interior_h_kw_m2_k": 0.025,
		"exterior_temp_c": 20.0,
		"exterior_h_kw_m2_k": 0.025,
	})
	_assert_true(bool(result["valid"]), "ambient step valid")
	for value in result["post_state"]["nodes_c"]:
		_assert_close(float(value), 20.0, "ambient node", 1.0e-10)
	_assert_close(
		float(result["stored_energy_delta_kj"]), 0.0, "ambient delta", 1.0e-9
	)
	_assert_close(
		float(result["energy_residual_kj"]), 0.0, "ambient residual", 1.0e-9
	)


func _test_radiation_only_closes_energy() -> void:
	var state: Dictionary = _concrete_state(10.0)
	var result: Dictionary = Solver.step_surface(state, {
		"dt_s": 2.0,
		"interior_h_kw_m2_k": 0.0,
		"exterior_h_kw_m2_k": 0.0,
		"fire_radiation_energy_kj": 100.0,
	})
	_assert_true(bool(result["valid"]), "radiation step valid")
	_assert_close(
		float(result["stored_energy_delta_kj"]), 100.0,
		"radiation storage", 1.0e-8
	)
	_assert_close(
		float(result["fire_radiation_energy_kj"]), 100.0,
		"radiation route", 1.0e-12
	)
	_assert_close(
		float(result["energy_residual_kj"]), 0.0,
		"radiation residual", 1.0e-8
	)


func _test_prescribed_boundary_energies_close_exactly() -> void:
	var state: Dictionary = _concrete_state(10.0)
	var heated: Dictionary = Solver.step_surface(state, {
		"dt_s": 2.0,
		"interior_convection_energy_kj": 100.0,
		"exterior_energy_removed_kj": 0.0,
	})
	_assert_true(bool(heated["valid"]), "prescribed heating valid")
	_assert_close(
		float(heated["stored_energy_delta_kj"]), 100.0,
		"prescribed heating storage", 1.0e-8
	)
	_assert_close(
		float(heated["energy_residual_kj"]), 0.0,
		"prescribed heating residual", 1.0e-8
	)
	var cooled: Dictionary = Solver.step_surface(heated["post_state"], {
		"dt_s": 2.0,
		"interior_convection_energy_kj": 0.0,
		"exterior_energy_removed_kj": 40.0,
	})
	_assert_true(bool(cooled["valid"]), "prescribed cooling valid")
	_assert_close(
		float(cooled["stored_energy_delta_kj"]), -40.0,
		"prescribed cooling storage", 1.0e-8
	)
	_assert_close(
		float(cooled["energy_residual_kj"]), 0.0,
		"prescribed cooling residual", 1.0e-8
	)


func _test_prescribed_boundary_conflicts_fail_closed() -> void:
	var state: Dictionary = _concrete_state()
	var convection_conflict: Dictionary = Solver.step_surface(state, {
		"dt_s": 1.0,
		"interior_h_kw_m2_k": 0.025,
		"interior_convection_energy_kj": 10.0,
	})
	_assert_true(
		not bool(convection_conflict["valid"]),
		"prescribed convection conflict rejected"
	)
	var exterior_conflict: Dictionary = Solver.step_surface(state, {
		"dt_s": 1.0,
		"exterior_h_kw_m2_k": 0.025,
		"exterior_energy_removed_kj": 10.0,
	})
	_assert_true(
		not bool(exterior_conflict["valid"]),
		"prescribed exterior conflict rejected"
	)


func _test_zero_area_surface_is_inert() -> void:
	var state: Dictionary = _concrete_state(0.0)
	var inert: Dictionary = Solver.step_surface(state, {
		"dt_s": 1.0,
		"interior_convection_energy_kj": 0.0,
	})
	_assert_true(bool(inert["valid"]), "zero-area no-op valid")
	var rejected: Dictionary = Solver.step_surface(state, {
		"dt_s": 1.0,
		"interior_convection_energy_kj": 1.0,
	})
	_assert_true(not bool(rejected["valid"]), "zero-area energy rejected")


func _test_early_convection_matches_semi_infinite_reference() -> void:
	var state: Dictionary = _concrete_state()
	var result: Dictionary = {}
	for _step: int in range(600):
		result = Solver.step_surface(state, {
			"dt_s": 0.1,
			"interior_gas_temp_c": 100.0,
			"interior_h_kw_m2_k": 0.025,
			"exterior_temp_c": 20.0,
			"exterior_h_kw_m2_k": 0.0,
		})
		_assert_true(bool(result["valid"]), "semi-infinite step valid")
		state = result["post_state"]
	var expected_surface_c: float = 28.184076641274316
	var actual_surface_c: float = float(state["nodes_c"][0])
	var relative_rise_error: float = (
		absf(actual_surface_c - expected_surface_c)
		/ (expected_surface_c - 20.0)
	)
	_early_surface_c = actual_surface_c
	_early_relative_error = relative_rise_error
	_assert_true(
		relative_rise_error <= 0.05,
		"semi-infinite surface error <= 5%% (actual %.6f, expected %.6f)"
		% [actual_surface_c, expected_surface_c]
	)


func _test_long_run_conserves_energy() -> void:
	var state: Dictionary = _concrete_state(12.0)
	var cumulative_residual_kj: float = 0.0
	for step_index: int in range(10000):
		var gas_temp_c: float = 75.0 + 15.0 * sin(float(step_index) * 0.002)
		var result: Dictionary = Solver.step_surface(state, {
			"dt_s": 0.05,
			"interior_gas_temp_c": gas_temp_c,
			"interior_h_kw_m2_k": 0.018,
			"exterior_temp_c": 15.0,
			"exterior_h_kw_m2_k": 0.012,
			"gas_radiation_energy_kj": 0.002,
			"fire_radiation_energy_kj": 0.003,
		})
		_assert_true(bool(result["valid"]), "long-run step valid")
		cumulative_residual_kj += float(result["energy_residual_kj"])
		state = result["post_state"]
	_long_run_residual_kj = cumulative_residual_kj
	_assert_true(
		absf(cumulative_residual_kj) <= 1.0e-5,
		"10k-step cumulative residual %.12f kJ" % cumulative_residual_kj
	)


func _test_input_state_is_immutable() -> void:
	var state: Dictionary = _concrete_state()
	var before: Dictionary = state.duplicate(true)
	var result: Dictionary = Solver.step_surface(state, {
		"dt_s": 1.0,
		"interior_gas_temp_c": 100.0,
		"interior_h_kw_m2_k": 0.025,
		"exterior_temp_c": 20.0,
		"exterior_h_kw_m2_k": 0.025,
	})
	_assert_true(bool(result["valid"]), "immutable step valid")
	for index: int in range(5):
		_assert_close(
			float(state["nodes_c"][index]),
			float(before["nodes_c"][index]),
			"input node immutable",
			0.0
		)


func _test_invalid_state_fails_closed() -> void:
	var state: Dictionary = _concrete_state()
	state["thickness_m"] = 0.0
	var result: Dictionary = Solver.step_surface(state, {"dt_s": 1.0})
	_assert_true(not bool(result["valid"]), "invalid state rejected")
	_assert_true(
		String(result["error"]).contains("thickness_m"),
		"invalid state error names field"
	)


func _assert_close(
	actual: float,
	expected: float,
	label: String,
	tolerance: float = 1.0e-9
) -> void:
	if absf(actual - expected) > tolerance:
		_failed = true
		push_error(
			"%s: expected %.12f, got %.12f (tol %.3e)"
			% [label, expected, actual, tolerance]
		)


func _assert_true(condition: bool, label: String) -> void:
	if not condition:
		_failed = true
		push_error(label)

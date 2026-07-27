extends SceneTree

const SolverScript = preload("res://sim/core/Phase3CoupledPressureSolver.gd")

const AIR_CP_KJ_KG_K: float = 1.0
const AMBIENT_C: float = 20.0

var _failed: bool = false


func _init() -> void:
	var solver = SolverScript.new()
	_test_sealed_pair_is_already_converged(solver)
	_test_single_opening_equalizes_pressure(solver)
	_test_conservation_mass_and_energy(solver)
	_test_three_room_chain_converges(solver)
	_test_room_order_invariance(solver)
	_test_opening_order_invariance(solver)
	_test_antisymmetry_of_every_connection(solver)
	_test_counterflow_preserved_when_neutral_plane_is_inside(solver)
	_test_neutral_plane_matches_analytic_height(solver)
	_test_one_way_flow_when_neutral_plane_is_outside(solver)
	_test_regularization_bounds_the_near_zero_derivative(solver)
	_test_every_owner_is_inside_the_residual(solver)
	_test_source_only_room_reaches_eos_consistency(solver)
	_test_exterior_opening_relieves_pressure(solver)
	_test_malformed_input_fails_closed(solver)
	_test_negative_inventory_fails_closed(solver)
	_test_degenerate_geometry_fails_closed(solver)
	_test_iteration_cap_fails_closed(solver)
	# `quit()` only requests a shutdown, so a bare `quit(1)` would be overwritten
	# by the `quit(0)` below. Return explicitly.
	if _failed:
		quit(1)
		return
	print("PHASE3_F33V3H1_COUPLED_PRESSURE_SOLVER_PASS")
	quit(0)


# ---------------------------------------------------------------------------
# convergence
# ---------------------------------------------------------------------------

func _test_sealed_pair_is_already_converged(solver) -> void:
	# Identical rooms, no sources, one opening: the pre-step field is already
	# the solution, so Newton must accept it without taking a step.
	var result: Dictionary = solver.solve_coupled_pressure(
		{"0": _room(60.0, 20.0, 3.0, 72.0, 0.0, 0.0, 0.0),
		 "1": _room(60.0, 20.0, 3.0, 72.0, 0.0, 0.0, 0.0)},
		[_opening(0, 0, 1)],
		{},
		0.1,
		AMBIENT_C
	)
	_assert_true(bool(result["valid"]), "sealed valid")
	_assert_true(bool(result["converged"]), "sealed converged")
	_close(float(result["iterations"]), 0.0, "sealed needs no iteration")
	_assert_true(
		float(result["max_abs_residual_kg"]) <= 1.0e-9, "sealed residual"
	)


func _test_single_opening_equalizes_pressure(solver) -> void:
	var rooms: Dictionary = {
		"0": _room(60.0, 20.0, 3.0, 72.0, 60.0, 0.0, 0.0),
		"1": _room(60.0, 20.0, 3.0, 72.0, 0.0, 0.0, 0.0),
	}
	var result: Dictionary = solver.solve_coupled_pressure(
		rooms, [_opening(0, 0, 1)], {}, 0.05, AMBIENT_C
	)
	_assert_true(bool(result["valid"]), "single valid")
	_assert_true(bool(result["converged"]), "single converged")
	_assert_true(
		float(result["iterations"]) <= 16.0, "single iteration budget"
	)
	# The over-pressured room must lose mass to the other one.
	_assert_true(
		float(result["net_mass_by_room"]["0"]) < 0.0
				and float(result["net_mass_by_room"]["1"]) > 0.0,
		"single transports toward the low side"
	)
	# Residual monotonically decreases along the accepted iterates.
	var history: Array = result["residual_history"]
	for index in range(1, history.size()):
		_assert_true(
			float(history[index]) < float(history[index - 1]),
			"single residual decreases at iterate %d" % index
		)


func _test_three_room_chain_converges(solver) -> void:
	var result: Dictionary = solver.solve_coupled_pressure(
		{
			"0": _room(60.0, 20.0, 3.0, 72.0, 90.0, 0.0, 0.0),
			"1": _room(60.0, 20.0, 3.0, 72.0, 0.0, 0.0, 0.0),
			"2": _room(60.0, 20.0, 3.0, 72.0, 45.0, 0.0, 0.0),
		},
		[_opening(0, 0, 1), _opening(1, 1, 2)],
		{},
		0.05,
		AMBIENT_C
	)
	_assert_true(bool(result["valid"]), "chain valid")
	_assert_true(bool(result["converged"]), "chain converged")
	_assert_true(float(result["iterations"]) <= 16.0, "chain iteration budget")
	_assert_true(
		float(result["max_abs_residual_kg"]) <= 1.0e-9, "chain residual"
	)


# ---------------------------------------------------------------------------
# conservation and symmetry
# ---------------------------------------------------------------------------

func _test_conservation_mass_and_energy(solver) -> void:
	var rooms: Dictionary = {
		"0": _room(60.0, 20.0, 3.0, 72.0, 200.0, 0.0, 0.0),
		"1": _room(60.0, 20.0, 3.0, 72.0, 0.0, 0.0, 0.0),
	}
	var sources: Dictionary = {
		"0": {"mass_kg": 0.012, "energy_kj": 220.0},
		"1": {"mass_kg": 0.0, "energy_kj": -35.0},
	}
	var result: Dictionary = solver.solve_coupled_pressure(
		rooms, [_opening(0, 0, 1)], sources, 0.05, AMBIENT_C
	)
	_assert_true(bool(result["valid"]), "conservation valid")
	# Building mass closes: end total equals pre total plus the injected source.
	var pre_mass_kg: float = 0.0
	var post_mass_kg: float = 0.0
	var source_mass_kg: float = 0.0
	var pre_energy_kj: float = 0.0
	var post_energy_kj: float = 0.0
	var source_energy_kj: float = 0.0
	for room_key in rooms.keys():
		var room: Dictionary = rooms[room_key]
		pre_mass_kg += float(room["upper_gas_kg"]) + float(room["lower_gas_kg"])
		pre_energy_kj += float(room["upper_energy_kj"]) \
				+ float(room["lower_energy_kj"])
		post_mass_kg += float(result["mass_by_room"][room_key])
		post_energy_kj += float(result["energy_by_room"][room_key])
		source_mass_kg += float(sources[room_key]["mass_kg"])
		source_energy_kj += float(sources[room_key]["energy_kj"])
	_close(post_mass_kg, pre_mass_kg + source_mass_kg, "building mass closes")
	_close(
		post_energy_kj, pre_energy_kj + source_energy_kj,
		"building energy closes"
	)
	# Interior transport alone moves no net building mass.
	_assert_true(
		absf(float(result["interior_transport_residual_kg"])) <= 1.0e-12,
		"interior transport is internally closed"
	)


func _test_antisymmetry_of_every_connection(solver) -> void:
	var result: Dictionary = solver.solve_coupled_pressure(
		{
			"0": _room(60.0, 20.0, 3.0, 72.0, 60.0, 0.0, 0.0),
			"1": _room(60.0, 20.0, 3.0, 72.0, 0.0, 0.0, 0.0),
			"2": _room(60.0, 20.0, 3.0, 72.0, 30.0, 0.0, 0.0),
		},
		[_opening(0, 0, 1), _opening(1, 1, 2)],
		{},
		0.05,
		AMBIENT_C
	)
	_assert_true(bool(result["valid"]), "antisymmetry valid")
	# Every connection reports one integration, so what a leaves is exactly
	# what b receives. Summing the signed nets over rooms must vanish.
	var signed_total_kg: float = 0.0
	for raw_connection in result["connections"]:
		var connection: Dictionary = raw_connection
		_assert_true(
			float(connection["a_to_b_kg"]) >= 0.0
					and float(connection["b_to_a_kg"]) >= 0.0,
			"gross flow is non-negative"
		)
		_close(
			float(connection["gross_mass_kg"]),
			float(connection["a_to_b_kg"]) + float(connection["b_to_a_kg"]),
			"gross equals the sum of directions"
		)
	for room_key in result["net_mass_by_room"].keys():
		signed_total_kg += float(result["net_mass_by_room"][room_key])
	_close(signed_total_kg, 0.0, "signed nets cancel across the network")


func _test_room_order_invariance(solver) -> void:
	var forward: Dictionary = solver.solve_coupled_pressure(
		{
			"0": _room(60.0, 20.0, 3.0, 72.0, 90.0, 0.0, 0.0),
			"1": _room(60.0, 20.0, 3.0, 72.0, 0.0, 0.0, 0.0),
			"2": _room(60.0, 20.0, 3.0, 72.0, 45.0, 0.0, 0.0),
		},
		[_opening(0, 0, 1), _opening(1, 1, 2)], {}, 0.05, AMBIENT_C
	)
	var reverse_rooms: Dictionary = {}
	reverse_rooms["2"] = _room(60.0, 20.0, 3.0, 72.0, 45.0, 0.0, 0.0)
	reverse_rooms["1"] = _room(60.0, 20.0, 3.0, 72.0, 0.0, 0.0, 0.0)
	reverse_rooms["0"] = _room(60.0, 20.0, 3.0, 72.0, 90.0, 0.0, 0.0)
	var reverse: Dictionary = solver.solve_coupled_pressure(
		reverse_rooms, [_opening(1, 1, 2), _opening(0, 0, 1)], {}, 0.05, AMBIENT_C
	)
	_assert_true(bool(reverse["valid"]), "reverse room order valid")
	for room_key in ["0", "1", "2"]:
		_close(
			float(forward["pressure_by_room"][room_key]),
			float(reverse["pressure_by_room"][room_key]),
			"room order invariant pressure %s" % room_key
		)


func _test_opening_order_invariance(solver) -> void:
	var rooms: Dictionary = {
		"0": _room(60.0, 20.0, 3.0, 72.0, 90.0, 0.0, 0.0),
		"1": _room(60.0, 20.0, 3.0, 72.0, 0.0, 0.0, 0.0),
		"2": _room(60.0, 20.0, 3.0, 72.0, 45.0, 0.0, 0.0),
	}
	var forward: Dictionary = solver.solve_coupled_pressure(
		rooms, [_opening(0, 0, 1), _opening(1, 1, 2)], {}, 0.05, AMBIENT_C
	)
	var reverse: Dictionary = solver.solve_coupled_pressure(
		rooms, [_opening(1, 1, 2), _opening(0, 0, 1)], {}, 0.05, AMBIENT_C
	)
	for index in range(forward["connections"].size()):
		_close(
			float(forward["connections"][index]["a_to_b_kg"]),
			float(reverse["connections"][index]["a_to_b_kg"]),
			"opening order invariant a_to_b %d" % index
		)
		_close(
			float(forward["connections"][index]["b_to_a_kg"]),
			float(reverse["connections"][index]["b_to_a_kg"]),
			"opening order invariant b_to_a %d" % index
		)


# ---------------------------------------------------------------------------
# neutral plane and counterflow
# ---------------------------------------------------------------------------

func _test_counterflow_preserved_when_neutral_plane_is_inside(solver) -> void:
	# The physical counterflow case: both rooms hold nearly the same pressure,
	# but one carries a hot buoyant upper layer. Buoyancy then dominates the
	# small pressure difference and dp(z) changes sign inside the doorway, so
	# hot gas must leave high while cool gas enters low.
	#   room 0: M = 60 kg, E = 1500 kJ split as 20 kg upper / 40 kg lower
	#   room 1: M = 65 kg, E = 34 kJ, single ambient layer
	# Both give M * T_ref + E / cp within ~35 of each other, i.e. dp ~ 0.
	var result: Dictionary = solver.solve_coupled_pressure(
		{
			"0": _two_layer_room(60.0, 20.0, 3.0, 20.0, 1500.0, 40.0, 0.0),
			"1": _room(60.0, 20.0, 3.0, 65.0, 34.0, 0.0, 0.0),
		},
		[_opening(0, 0, 1, 0.0, 2.4)],
		{},
		0.05,
		AMBIENT_C
	)
	_assert_true(bool(result["valid"]), "counterflow valid")
	var connection: Dictionary = result["connections"][0]
	_assert_true(
		bool(connection["neutral_plane_inside"]),
		"neutral plane lies inside the doorway"
	)
	_assert_true(
		float(connection["a_to_b_kg"]) > 0.0
				and float(connection["b_to_a_kg"]) > 0.0,
		"both directions carry strictly positive mass"
	)
	_close(
		float(result["counterflow_connection_count"]), 1.0,
		"counterflow connection counted"
	)
	_close(
		float(result["counterflow_violation_count"]), 0.0,
		"no counterflow violation"
	)


func _test_neutral_plane_matches_analytic_height(solver) -> void:
	# Both rooms uniform, so each column has a constant density and dp(z) is
	# exactly linear:  dp(z) = dp0 - g * (rho_a - rho_b) * z.
	# The neutral plane therefore has the closed form  z* = dp0 / (g*(rho_a-rho_b))
	# and the integrator must reproduce it to round-off.
	#   room 0: 60 kg -> rho = 1.0    room 1: 72 kg -> rho = 1.2
	# The energy is chosen so the pressure difference lands the crossing at
	# roughly mid-doorway rather than outside the span.
	var result: Dictionary = solver.solve_coupled_pressure(
		{
			"0": _room(60.0, 20.0, 3.0, 60.0, 3517.31, 0.0, 0.0),
			"1": _room(60.0, 20.0, 3.0, 72.0, 0.0, 0.0, 0.0),
		},
		[_opening(0, 0, 1, 0.0, 2.4)],
		{},
		0.05,
		AMBIENT_C
	)
	_assert_true(bool(result["valid"]), "analytic neutral plane valid")
	var connection: Dictionary = result["connections"][0]
	_assert_true(
		bool(connection["neutral_plane_inside"]),
		"analytic crossing lands inside the doorway"
	)
	var rho_a: float = 60.0 / 60.0
	var rho_b: float = 72.0 / 60.0
	var expected_m: float = float(connection["delta_p_pa"]) \
			/ (9.81 * (rho_a - rho_b))
	_close_rel(
		float(connection["neutral_plane_m"]), expected_m, 1.0e-9,
		"neutral plane matches the analytic height"
	)


func _test_one_way_flow_when_neutral_plane_is_outside(solver) -> void:
	# A small high vent with a large pressure difference has no sign change
	# inside its span, so one-way flow is the physical answer and must be
	# allowed. The counterflow contract only binds when the plane is inside.
	var result: Dictionary = solver.solve_coupled_pressure(
		{
			"0": _room(60.0, 20.0, 3.0, 72.0, 900.0, 0.0, 0.0),
			"1": _room(60.0, 20.0, 3.0, 72.0, 0.0, 0.0, 0.0),
		},
		[_opening(0, 0, 1, 2.2, 2.4)],
		{},
		0.05,
		AMBIENT_C
	)
	_assert_true(bool(result["valid"]), "one-way valid")
	var connection: Dictionary = result["connections"][0]
	_assert_true(
		not bool(connection["neutral_plane_inside"]),
		"neutral plane is outside the vent span"
	)
	_assert_true(
		float(connection["b_to_a_kg"]) == 0.0
				and float(connection["a_to_b_kg"]) > 0.0,
		"one-way flow accepted when it is physical"
	)


func _test_regularization_bounds_the_near_zero_derivative(solver) -> void:
	# Two identical rooms driven by a source small enough that the whole opening
	# sits below the regularisation threshold. Without the blend the orifice
	# derivative is unbounded there and Newton cannot form a Jacobian; with it,
	# the solve stays finite and converges.
	var result: Dictionary = solver.solve_coupled_pressure(
		{
			"0": _room(60.0, 20.0, 3.0, 72.0, 0.0, 0.0, 0.0),
			"1": _room(60.0, 20.0, 3.0, 72.0, 0.0, 0.0, 0.0),
		},
		[_opening(0, 0, 1)],
		{"0": {"mass_kg": 5.0e-6, "energy_kj": 0.0}},
		0.1,
		AMBIENT_C
	)
	_assert_true(bool(result["valid"]), "regularized valid")
	_assert_true(bool(result["converged"]), "regularized converged")
	_assert_true(
		float(result["regularization_active_count"]) > 0.0,
		"regularization engaged near zero"
	)
	for raw_connection in result["connections"]:
		var connection: Dictionary = raw_connection
		_assert_true(
			is_finite(float(connection["a_to_b_kg"]))
					and is_finite(float(connection["b_to_a_kg"])),
			"regularized flux stays finite"
		)


# ---------------------------------------------------------------------------
# every owner inside the residual
# ---------------------------------------------------------------------------

func _test_every_owner_is_inside_the_residual(solver) -> void:
	# This is the F3.3v3g3 counter-test. A large opposing source pair is what
	# g3 neglected; here the converged pressure must satisfy the EOS of the
	# COMPLETE balance including those sources.
	var rooms: Dictionary = {
		"0": _room(60.0, 20.0, 3.0, 72.0, 900.0, 0.0, 0.0),
		"1": _room(60.0, 20.0, 3.0, 72.0, 100.0, 0.0, 0.0),
	}
	var sources: Dictionary = {
		"0": {"mass_kg": 0.05, "energy_kj": 1400.0},
		"1": {"mass_kg": 0.0, "energy_kj": -900.0},
	}
	var result: Dictionary = solver.solve_coupled_pressure(
		rooms, [_opening(0, 0, 1)], sources, 0.05, AMBIENT_C
	)
	_assert_true(bool(result["valid"]), "owner residual valid")
	_assert_true(bool(result["converged"]), "owner residual converged")
	# Independently recompute the EOS from the reported end-of-step totals and
	# require it to reproduce the solved pressure.
	for room_key in ["0", "1"]:
		var reference_temp_k: float = AMBIENT_C + 273.15
		var gas_constant: float = 101325.0 / (1.2 * reference_temp_k)
		var expected_pa: float = gas_constant * (
			float(result["mass_by_room"][room_key]) * reference_temp_k
			+ float(result["energy_by_room"][room_key]) / AIR_CP_KJ_KG_K
		) / 60.0
		_close_rel(
			float(result["pressure_by_room"][room_key]), expected_pa, 1.0e-9,
			"solved pressure satisfies the full-balance EOS in %s" % room_key
		)


func _test_source_only_room_reaches_eos_consistency(solver) -> void:
	# No openings at all: the room must still land on the EOS pressure of its
	# own source, which proves sources are inside the residual rather than
	# applied afterwards.
	var result: Dictionary = solver.solve_coupled_pressure(
		{"0": _room(60.0, 20.0, 3.0, 72.0, 0.0, 0.0, 0.0)},
		[],
		{"0": {"mass_kg": 0.4, "energy_kj": 500.0}},
		0.1,
		AMBIENT_C
	)
	_assert_true(bool(result["valid"]), "source-only valid")
	var reference_temp_k: float = AMBIENT_C + 273.15
	var gas_constant: float = 101325.0 / (1.2 * reference_temp_k)
	var expected_pa: float = gas_constant * (
		72.4 * reference_temp_k + 500.0 / AIR_CP_KJ_KG_K
	) / 60.0
	_close_rel(
		float(result["pressure_by_room"]["0"]), expected_pa, 1.0e-9,
		"source-only room reaches its EOS pressure"
	)


func _test_exterior_opening_relieves_pressure(solver) -> void:
	# The exterior is a fixed-pressure boundary inside the same residual.
	var result: Dictionary = solver.solve_coupled_pressure(
		{"0": _room(60.0, 20.0, 3.0, 72.0, 0.0, 0.0, 0.0)},
		[_opening(0, 0, -1, 0.0, 2.0)],
		{"0": {"mass_kg": 0.30, "energy_kj": 0.0}},
		0.5,
		AMBIENT_C
	)
	_assert_true(bool(result["valid"]), "exterior valid")
	_assert_true(bool(result["converged"]), "exterior converged")
	# Over-pressure must vent outward, so the room keeps less than it was given.
	_assert_true(
		float(result["net_mass_by_room"]["0"]) < 0.0,
		"exterior opening vents the injected mass"
	)
	var connection: Dictionary = result["connections"][0]
	_assert_true(
		float(connection["a_to_b_kg"]) > 0.0, "outflow to exterior is positive"
	)


# ---------------------------------------------------------------------------
# fail closed
# ---------------------------------------------------------------------------

func _test_malformed_input_fails_closed(solver) -> void:
	var cases: Array = [
		{"label": "empty rooms", "rooms": {}, "dt": 0.1, "temp": AMBIENT_C},
		{
			"label": "zero dt",
			"rooms": {"0": _room(60.0, 20.0, 3.0, 72.0, 0.0, 0.0, 0.0)},
			"dt": 0.0, "temp": AMBIENT_C,
		},
		{
			"label": "negative dt",
			"rooms": {"0": _room(60.0, 20.0, 3.0, 72.0, 0.0, 0.0, 0.0)},
			"dt": -1.0, "temp": AMBIENT_C,
		},
		{
			"label": "nan temperature",
			"rooms": {"0": _room(60.0, 20.0, 3.0, 72.0, 0.0, 0.0, 0.0)},
			"dt": 0.1, "temp": NAN,
		},
	]
	for raw_case in cases:
		var test_case: Dictionary = raw_case
		var result: Dictionary = solver.solve_coupled_pressure(
			test_case["rooms"], [], {}, float(test_case["dt"]),
			float(test_case["temp"])
		)
		_assert_true(
			not bool(result["valid"]),
			"%s fails closed" % String(test_case["label"])
		)
		_assert_true(
			float(result["failure_code"]) > 0.0,
			"%s reports a failure code" % String(test_case["label"])
		)
		_assert_true(
			result["connections"].is_empty(),
			"%s emits no connection" % String(test_case["label"])
		)
	# A malformed source is rejected rather than silently coerced.
	var nan_source: Dictionary = solver.solve_coupled_pressure(
		{"0": _room(60.0, 20.0, 3.0, 72.0, 0.0, 0.0, 0.0)},
		[],
		{"0": {"mass_kg": NAN, "energy_kj": 0.0}},
		0.1,
		AMBIENT_C
	)
	_assert_true(not bool(nan_source["valid"]), "nan source fails closed")
	# A malformed opening is rejected rather than skipped.
	var bad_opening: Dictionary = solver.solve_coupled_pressure(
		{"0": _room(60.0, 20.0, 3.0, 72.0, 0.0, 0.0, 0.0),
		 "1": _room(60.0, 20.0, 3.0, 72.0, 0.0, 0.0, 0.0)},
		[_opening(0, 0, 1, 2.0, 1.0)],
		{},
		0.1,
		AMBIENT_C
	)
	_assert_true(not bool(bad_opening["valid"]), "inverted opening fails closed")
	# An opening naming a room that was not supplied is rejected.
	var unknown_room: Dictionary = solver.solve_coupled_pressure(
		{"0": _room(60.0, 20.0, 3.0, 72.0, 0.0, 0.0, 0.0)},
		[_opening(0, 0, 7)],
		{},
		0.1,
		AMBIENT_C
	)
	_assert_true(not bool(unknown_room["valid"]), "unknown room fails closed")


func _test_negative_inventory_fails_closed(solver) -> void:
	for state in [
		_room(60.0, 20.0, 3.0, -1.0, 0.0, 0.0, 0.0),
		_room(60.0, 20.0, 3.0, 72.0, -5.0, 0.0, 0.0),
		# a zone holding energy but no mass has no defined temperature
		_two_layer_room(60.0, 20.0, 3.0, 0.0, 100.0, 72.0, 0.0),
		# an empty room has no EOS at all
		_room(60.0, 20.0, 3.0, 0.0, 0.0, 0.0, 0.0),
	]:
		var result: Dictionary = solver.solve_coupled_pressure(
			{"0": state}, [], {}, 0.1, AMBIENT_C
		)
		_assert_true(not bool(result["valid"]), "invalid inventory fails closed")
		_close(
			float(result["failure_code"]), 2.0,
			"invalid inventory reports the room-state code"
		)


func _test_degenerate_geometry_fails_closed(solver) -> void:
	for state in [
		_room(0.0, 20.0, 3.0, 72.0, 0.0, 0.0, 0.0),
		_room(60.0, 0.0, 3.0, 72.0, 0.0, 0.0, 0.0),
		_room(60.0, 20.0, 0.0, 72.0, 0.0, 0.0, 0.0),
	]:
		var result: Dictionary = solver.solve_coupled_pressure(
			{"0": state}, [], {}, 0.1, AMBIENT_C
		)
		_assert_true(not bool(result["valid"]), "degenerate geometry fails closed")


func _test_iteration_cap_fails_closed(solver) -> void:
	# One iteration is not enough for a strongly driven pair, and the solver
	# must say so instead of returning the unconverged iterate as valid.
	var result: Dictionary = solver.solve_coupled_pressure(
		{
			"0": _room(60.0, 20.0, 3.0, 72.0, 900.0, 0.0, 0.0),
			"1": _room(60.0, 20.0, 3.0, 72.0, 0.0, 0.0, 0.0),
		},
		[_opening(0, 0, 1)],
		{},
		0.5,
		AMBIENT_C,
		{"max_iterations": 1, "residual_tolerance": 1.0e-18}
	)
	_assert_true(not bool(result["valid"]), "iteration cap fails closed")
	_assert_true(not bool(result["converged"]), "iteration cap not converged")
	_close(float(result["failure_code"]), 6.0, "iteration cap failure code")
	_assert_true(
		result["connections"].is_empty(),
		"unconverged solve emits no connection"
	)


# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

func _room(
		volume_m3: float,
		floor_area_m2: float,
		height_m: float,
		lower_gas_kg: float,
		lower_energy_kj: float,
		upper_gas_kg: float,
		upper_energy_kj: float
	) -> Dictionary:
	return {
		"volume_m3": volume_m3,
		"floor_area_m2": floor_area_m2,
		"height_m": height_m,
		"upper_gas_kg": upper_gas_kg,
		"lower_gas_kg": lower_gas_kg,
		"upper_energy_kj": upper_energy_kj,
		"lower_energy_kj": lower_energy_kj,
	}


func _two_layer_room(
		volume_m3: float,
		floor_area_m2: float,
		height_m: float,
		upper_gas_kg: float,
		upper_energy_kj: float,
		lower_gas_kg: float,
		lower_energy_kj: float
	) -> Dictionary:
	return {
		"volume_m3": volume_m3,
		"floor_area_m2": floor_area_m2,
		"height_m": height_m,
		"upper_gas_kg": upper_gas_kg,
		"lower_gas_kg": lower_gas_kg,
		"upper_energy_kj": upper_energy_kj,
		"lower_energy_kj": lower_energy_kj,
	}


func _opening(
		opening_id: int,
		room_a_id: int,
		room_b_id: int,
		bottom_m: float = 0.0,
		top_m: float = 2.0
	) -> Dictionary:
	return {
		"opening_id": opening_id,
		"room_a_id": room_a_id,
		"room_b_id": room_b_id,
		"bottom_m": bottom_m,
		"top_m": top_m,
		"width_m": 0.9,
		"open_fraction": 1.0,
		"discharge_coeff": 0.61,
	}


func _close(actual: float, expected: float, label: String) -> void:
	if absf(actual - expected) > 1.0e-9 * maxf(1.0, absf(expected)):
		push_error("%s: got %.15f expected %.15f" % [label, actual, expected])
		_failed = true


func _close_rel(
		actual: float, expected: float, tolerance: float, label: String
	) -> void:
	if absf(actual - expected) > tolerance * maxf(1.0e-12, absf(expected)):
		push_error("%s: got %.15f expected %.15f" % [label, actual, expected])
		_failed = true


func _assert_true(condition: bool, label: String) -> void:
	if not condition:
		push_error(label)
		_failed = true

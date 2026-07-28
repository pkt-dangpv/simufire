extends SceneTree

## F3.3v3h2.5e: the coupled pressure solve runs in GAUGE coordinates.
##
## H2.5c captured a real solve that reached a normalized residual of 1.147e-12
## against a 1e-12 tolerance and then could not finish: the correction it still
## owed was 0.38 ulp of an absolute-pressure iterate near 101325 Pa, so every
## damped trial evaluated the same double. Moving the unknown to a gauge
## pressure removes that floor.
##
## This fixture pins the properties the change must have, independently of any
## captured state:
##
##   * shifting every room pressure AND the exterior reference by the same
##     constant leaves the gauge solution and every flux unchanged - the solve
##     depends on pressure differences, never on the absolute level;
##   * an exterior reference away from 101325 Pa works and is self-consistent;
##   * `pressure_by_room` is still absolute and equals gauge + exterior;
##   * mass and energy are conserved across interior openings;
##   * counterflow survives;
##   * the solve is deterministic bit for bit.

const SolverScript = preload("res://sim/core/Phase3CoupledPressureSolver.gd")
const P_REF := 101325.0

var _failed: bool = false


func _init() -> void:
	_test_shift_invariance()
	_test_non_default_exterior_reference()
	_test_absolute_output_is_gauge_plus_reference()
	_test_conservation_and_counterflow()
	_test_exterior_opening_is_referenced_to_the_gauge_origin()
	_test_determinism()
	_test_gauge_iterate_is_small()
	if _failed:
		quit(1)
		return
	print("PHASE3_F33V3H25E_GAUGE_PRESSURE_PASS")
	quit(0)


# ---------------------------------------------------------------------------
# a two-room case with a doorway, warm upper layer on one side
# ---------------------------------------------------------------------------

## Realistic inventories - a compartment sits within a few pascals of ambient,
## so the masses are near the reference mass rather than arbitrary round
## numbers. These are the room-0/room-1 magnitudes from the corridor capture.
func _rooms() -> Dictionary:
	return {
		"0": {
			"volume_m3": 48.0, "floor_area_m2": 20.0, "height_m": 2.4,
			"upper_gas_kg": 13.341180715258982, "lower_gas_kg": 43.89700581336613,
			"upper_energy_kj": 105.7778942601438, "lower_energy_kj": 2.2979616486586663,
		},
		"1": {
			"volume_m3": 25.2, "floor_area_m2": 10.5, "height_m": 2.4,
			"upper_gas_kg": 0.28611634716922923, "lower_gas_kg": 29.95468972035928,
			"upper_energy_kj": 0.13579428978793925,
			"lower_energy_kj": 0.0037982474251549094,
		},
	}


func _openings() -> Array:
	return [{
		"opening_id": 0, "room_a_id": 0, "room_b_id": 1,
		"bottom_m": 0.0, "top_m": 2.0, "width_m": 0.9,
		"open_fraction": 1.0, "discharge_coeff": 0.61,
	}]


func _sources() -> Dictionary:
	return {
		"0": {"mass_kg": -0.0015, "energy_kj": 1.10},
		"1": {"mass_kg": -0.0011, "energy_kj": -0.0107},
	}


func _solve(rooms: Dictionary, options: Dictionary = {}) -> Dictionary:
	return SolverScript.new().solve_coupled_pressure(
		rooms, _openings(), _sources(), 0.08333333333333333, 20.0, options
	)


# ---------------------------------------------------------------------------
# tests
# ---------------------------------------------------------------------------

## Moving the reference is a change of coordinates, nothing more.
##
## The rooms are untouched, so the physical answer must not move at all: the
## absolute pressure field and every flux stay put, and the gauge field slides
## by exactly minus the shift. An absolute formulation cannot state this
## cleanly - it resolves the same differences through a subtraction near
## ambient, so the answer drifts at the ulp level with the reference.
func _test_shift_invariance() -> void:
	var delta: float = 500.0
	var base: Dictionary = _solve(_rooms())
	var shifted: Dictionary = _solve(
		_rooms(), {"exterior_pressure_abs_pa": P_REF + delta}
	)
	_assert_true(bool(base["converged"]), "baseline converges")
	_assert_true(bool(shifted["converged"]), "shifted reference converges")
	if not (bool(base["converged"]) and bool(shifted["converged"])):
		return
	for key in base["gauge_pressure_by_room"].keys():
		_close(
			float(shifted["gauge_pressure_by_room"][key])
					- float(base["gauge_pressure_by_room"][key]),
			-delta,
			"room %s gauge slides by exactly minus the shift" % key
		)
		_close(
			float(shifted["pressure_by_room"][key]),
			float(base["pressure_by_room"][key]),
			"room %s absolute pressure is unchanged by the reference" % key
		)
	var base_connections: Array = base["connections"]
	var shifted_connections: Array = shifted["connections"]
	_assert_true(
		base_connections.size() == shifted_connections.size(),
		"same connection count under a shift"
	)
	for index in range(mini(base_connections.size(), shifted_connections.size())):
		var a: Dictionary = base_connections[index]
		var b: Dictionary = shifted_connections[index]
		for field in ["a_to_b_kg", "b_to_a_kg", "delta_p_pa"]:
			_close_rel(
				float(b[field]), float(a[field]), 1.0e-9,
				"connection %d %s is invariant under the shift" % [index, field]
			)


## An exterior reference nowhere near 101325 Pa - altitude, or simply a caller
## that hands over a different boundary - must work and stay self-consistent.
func _test_non_default_exterior_reference() -> void:
	var exterior: float = 90000.0
	var result: Dictionary = _solve(
		_rooms(), {"exterior_pressure_abs_pa": exterior}
	)
	_assert_true(
		bool(result["converged"]),
		"solve converges with a 90000 Pa exterior reference"
	)
	if not bool(result["converged"]):
		return
	for key in result["pressure_by_room"].keys():
		_close(
			float(result["pressure_by_room"][key])
					- float(result["gauge_pressure_by_room"][key]),
			exterior,
			"room %s absolute minus gauge is the supplied reference" % key
		)
	_assert_true(
		float(result["normalized_residual"]) <= 1.0e-12,
		"the residual still closes against a non-default reference"
	)
	_assert_true(
		float(result["counterflow_violation_count"]) == 0.0,
		"no counterflow violation against a non-default reference"
	)


func _test_absolute_output_is_gauge_plus_reference() -> void:
	var result: Dictionary = _solve(_rooms())
	_assert_true(bool(result["converged"]), "solve converges")
	if not bool(result["converged"]):
		return
	for key in result["pressure_by_room"].keys():
		_close(
			float(result["pressure_by_room"][key])
					- float(result["gauge_pressure_by_room"][key]),
			P_REF,
			"room %s absolute output is rebuilt from the default reference" % key
		)


func _test_conservation_and_counterflow() -> void:
	var result: Dictionary = _solve(_rooms())
	_assert_true(bool(result["converged"]), "solve converges")
	if not bool(result["converged"]):
		return
	# Every interior route debits one room and credits another, so the net over
	# a fully interior component is zero to round-off.
	var net_mass: float = 0.0
	var net_energy: float = 0.0
	for key in result["net_mass_by_room"].keys():
		net_mass += float(result["net_mass_by_room"][key])
		net_energy += float(result["net_energy_by_room"][key])
	_assert_true(
		absf(net_mass) < 1.0e-12,
		"interior mass is conserved (net %s kg)" % String.num_scientific(net_mass)
	)
	_assert_true(
		absf(net_energy) < 1.0e-9,
		"interior energy is conserved (net %s kJ)" % String.num_scientific(net_energy)
	)
	_assert_true(
		float(result["counterflow_violation_count"]) == 0.0,
		"no counterflow violation"
	)
	for raw_connection in result["connections"]:
		var connection: Dictionary = raw_connection
		if not bool(connection.get("neutral_plane_inside", false)):
			continue
		_assert_true(
			float(connection["a_to_b_kg"]) > 0.0
					and float(connection["b_to_a_kg"]) > 0.0,
			"a neutral plane inside the span carries both directions"
		)


## The exterior side of an opening is the gauge ORIGIN - exactly zero - not the
## ambient constant. Without an exterior opening in the suite this branch is
## never executed, and a regression to `p_a - AIR_PRESSURE_REF_PA` would sail
## past every behavioural check.
func _test_exterior_opening_is_referenced_to_the_gauge_origin() -> void:
	# One vent with the exterior on side B and one with it on side A, because
	# `_evaluate` resolves the two sides through separate expressions and a
	# regression in either must be visible.
	var openings: Array = _openings()
	openings.append({
		"opening_id": 1, "room_a_id": 1, "room_b_id": -1,
		"bottom_m": 0.8, "top_m": 1.8, "width_m": 0.6,
		"open_fraction": 1.0, "discharge_coeff": 0.61,
	})
	openings.append({
		"opening_id": 2, "room_a_id": -1, "room_b_id": 0,
		"bottom_m": 0.5, "top_m": 1.2, "width_m": 0.5,
		"open_fraction": 1.0, "discharge_coeff": 0.61,
	})
	var solver = SolverScript.new()
	var result: Dictionary = solver.solve_coupled_pressure(
		_rooms(), openings, _sources(), 0.08333333333333333, 20.0, {}
	)
	_assert_true(
		bool(result["converged"]),
		"a component vented to the exterior converges"
	)
	if not bool(result["converged"]):
		return
	var seen_b_side: bool = false
	var seen_a_side: bool = false
	for raw_connection in result["connections"]:
		var connection: Dictionary = raw_connection
		var room_a: int = int(connection["room_a_id"])
		var room_b: int = int(connection["room_b_id"])
		if room_a != -1 and room_b != -1:
			continue
		# dp is the interior room's gauge measured against zero, so it stays a
		# small number. Referencing the exterior to ambient instead would make
		# this order 1e5, with the sign following whichever side is outside.
		var interior_key: String = str(room_b) if room_a == -1 else str(room_a)
		var expected: float = float(
			result["gauge_pressure_by_room"][interior_key]
		)
		if room_a == -1:
			seen_a_side = true
			expected = -expected
		else:
			seen_b_side = true
		_close_rel(
			float(connection["delta_p_pa"]), expected, 1.0e-9,
			"exterior opening %d dp is the room's own gauge pressure"
					% int(connection["opening_id"])
		)
		_assert_true(
			absf(float(connection["delta_p_pa"])) < 1.0e3,
			"exterior opening %d dp is a gauge difference, not an absolute one"
					% int(connection["opening_id"])
		)
	_assert_true(seen_b_side, "an opening with the exterior on side B is covered")
	_assert_true(seen_a_side, "an opening with the exterior on side A is covered")
	_assert_true(
		float(result["counterflow_violation_count"]) == 0.0,
		"no counterflow violation with an exterior opening"
	)


func _test_determinism() -> void:
	var first: Dictionary = _solve(_rooms())
	var second: Dictionary = _solve(_rooms())
	for field in ["converged", "iterations", "limiting_reason"]:
		_assert_true(
			str(first[field]) == str(second[field]),
			"deterministic for " + field
		)
	for key in first["gauge_pressure_by_room"].keys():
		_assert_true(
			float(first["gauge_pressure_by_room"][key])
					== float(second["gauge_pressure_by_room"][key]),
			"bit-identical gauge pressure for room %s" % key
		)


func _test_gauge_iterate_is_small() -> void:
	# The whole point: the solved quantity is order pascals, not order 1e5, so a
	# correction of 1e-12 Pa is thousands of ulps rather than a fraction of one.
	var result: Dictionary = _solve(_rooms())
	if not bool(result["converged"]):
		return
	var largest: float = 0.0
	for key in result["gauge_pressure_by_room"].keys():
		largest = maxf(largest, absf(float(result["gauge_pressure_by_room"][key])))
	_assert_true(
		largest < 1.0e3,
		"gauge iterate stays small (max %s Pa)" % String.num_scientific(largest)
	)
	_assert_true(
		float(result["normalized_residual"]) <= 1.0e-12,
		"residual closes inside the unchanged tolerance"
	)


# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

func _close(actual: float, expected: float, label: String) -> void:
	if absf(actual - expected) > 1.0e-6 * maxf(1.0, absf(expected)):
		push_error("%s: got %.9f expected %.9f" % [label, actual, expected])
		_failed = true


func _close_rel(
		actual: float, expected: float, tolerance: float, label: String
	) -> void:
	if absf(actual - expected) > tolerance * maxf(1.0e-30, absf(expected)):
		push_error("%s: got %s expected %s" % [
			label, String.num_scientific(actual), String.num_scientific(expected)
		])
		_failed = true


func _assert_true(condition: bool, label: String) -> void:
	if not condition:
		push_error(label)
		_failed = true

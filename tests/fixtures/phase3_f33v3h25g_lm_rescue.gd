extends SceneTree

## F3.3v3h2.5g: bounded Levenberg-Marquardt recovery, reachable only from the
## dead end where the solver used to return `damping_exhausted`.
##
## WHAT IT IS FOR
## --------------
## The ordinary line search accepts any strict decrease of the L-infinity
## residual. On the captured `corridor_chain` step it rejects a Newton direction
## that fixes two rooms out of three, because the third - the one currently
## holding the maximum - gets 2.4% worse. No damping helps.
##
## The recovery damps the SAME Jacobian toward steepest descent on a
## sum-of-squares merit and demands a SUFFICIENT decrease of it. The telling
## detail is that the accepted step raises the L-infinity norm on purpose
## (2.169e-04 -> 2.348e-04) while lowering the sum of squares: that is exactly
## the trade the L-infinity test was refusing, and why one step unblocks a solve
## that then converges to 6.5e-17.
##
## WHAT IS BOUNDED
## ---------------
##   - one accepted recovery step per solve;
##   - at most five regularization strengths to find it;
##   - control returns to the ordinary Newton/L-infinity loop immediately;
##   - a second dead end fails as `damping_exhausted`, as before.
##
## A recovery is never convergence by itself; the final criterion is still
## L-infinity against the unchanged 1e-12 tolerance.

const SolverScript = preload("res://sim/core/Phase3CoupledPressureSolver.gd")
const CORRIDOR := "res://tests/fixtures/data/coupled_solver_failure_corridor_chain.json"
const R0 := "res://tests/fixtures/data/coupled_solver_failure_r0_window_360.json"

## The `r0_window_360` result recorded when F3.3v3h2.5e shipped, before any
## recovery existed. The recovery must not perturb it by one bit.
const R0_ITERATIONS := 3
const R0_NORM := 9.522672403222153e-17

var _failed: bool = false


func _init() -> void:
	_test_corridor_converges_with_exactly_one_rescue()
	_test_r0_converges_without_rescue_and_is_unchanged()
	_test_successful_solves_never_reach_the_recovery()
	_test_budget_is_one_accepted_step_per_solve()
	_test_conservation_and_counterflow()
	_test_determinism()
	_test_recovery_is_not_convergence()
	if _failed:
		quit(1)
		return
	print("PHASE3_F33V3H25G_LM_RESCUE_PASS")
	quit(0)


# ---------------------------------------------------------------------------
# 1 - the corridor capture
# ---------------------------------------------------------------------------

func _test_corridor_converges_with_exactly_one_rescue() -> void:
	var result: Dictionary = _solve_capture(CORRIDOR)
	_assert_true(bool(result["converged"]), "corridor capture converges")
	_assert_true(
		float(result["rescue_attempted"]) == 1.0,
		"exactly one recovery attempt (%s)" % str(result["rescue_attempted"])
	)
	_assert_true(
		float(result["rescue_accepted"]) == 1.0,
		"exactly one accepted recovery step (%s)" % str(result["rescue_accepted"])
	)
	_assert_true(
		float(result["normalized_residual"]) <= 1.0e-12,
		"corridor closes inside the unchanged tolerance"
	)
	_assert_true(
		float(result["rescue_trials"]) >= 1.0,
		"the recovery reports how many trials it took"
	)
	_assert_true(
		float(result["rescue_lambda"]) > 0.0,
		"the recovery reports which regularization worked"
	)
	# The point of the whole mechanism: L-infinity goes UP across the rescue
	# step, which is precisely what the ordinary line search would not allow.
	_assert_true(
		float(result["rescue_final_norm"]) > float(result["rescue_initial_norm"]),
		"the accepted recovery step raises L-infinity while lowering the merit"
	)


# ---------------------------------------------------------------------------
# 2 - the r0 capture is untouched
# ---------------------------------------------------------------------------

func _test_r0_converges_without_rescue_and_is_unchanged() -> void:
	var result: Dictionary = _solve_capture(R0)
	_assert_true(bool(result["converged"]), "r0 capture still converges")
	_assert_true(
		float(result["rescue_attempted"]) == 0.0,
		"the recovery is never reached on r0"
	)
	_assert_true(
		int(result["iterations"]) == R0_ITERATIONS,
		"r0 takes the same %d iterations as before the recovery existed"
				% R0_ITERATIONS
	)
	_close_rel(
		float(result["normalized_residual"]), R0_NORM, 1.0e-15,
		"r0 reaches the identical residual it did before the recovery existed"
	)


# ---------------------------------------------------------------------------
# 3 - successful solves never reach the recovery
# ---------------------------------------------------------------------------

func _test_successful_solves_never_reach_the_recovery() -> void:
	# A spread of ordinary two-room states. None of them is a dead end, so the
	# recovery counters must stay at zero throughout - that is the guarantee
	# that a working solve executes the same code it always did.
	var checked: int = 0
	for factor in [0.996, 0.998, 1.0, 1.002, 1.004]:
		for energy in [0.5, 1.0, 2.0]:
			var rooms: Dictionary = _two_rooms(factor, energy)
			var result: Dictionary = SolverScript.new().solve_coupled_pressure(
				rooms, _two_room_openings(), _two_room_sources(),
				0.08333333333333333, 20.0, {}
			)
			if not bool(result["converged"]):
				continue
			checked += 1
			_assert_true(
				float(result["rescue_attempted"]) == 0.0
						and float(result["rescue_accepted"]) == 0.0
						and float(result["rescue_trials"]) == 0.0,
				"a converged solve leaves every recovery counter at zero"
			)
	_assert_true(checked >= 8, "enough successful solves were exercised (%d)" % checked)


# ---------------------------------------------------------------------------
# 5 - the budget really is one accepted step
# ---------------------------------------------------------------------------

func _test_budget_is_one_accepted_step_per_solve() -> void:
	# A real corridor perturbation that hits the dead end twice. The first is
	# rescued, the second is not, and the solve fails exactly as it used to.
	# Without the budget this case would keep being rescued.
	var rooms: Dictionary = _corridor_rooms_scaled(1.0 - 8.319328e-5)
	var result: Dictionary = SolverScript.new().solve_coupled_pressure(
		rooms, _corridor_openings(), _corridor_sources(),
		0.08333333333333333, 20.0, {"dp_regularization_pa": 2.5e-3}
	)
	_assert_true(
		float(result["rescue_accepted"]) == 1.0,
		"one recovery step was accepted (%s)" % str(result["rescue_accepted"])
	)
	_assert_true(
		not bool(result["converged"]),
		"the solve still fails once the budget is spent"
	)
	_assert_true(
		String(result["limiting_reason"]) == "damping_exhausted",
		"a second dead end fails as damping_exhausted, got '%s'"
				% String(result["limiting_reason"])
	)
	_assert_true(
		float(result["rescue_accepted"]) <= 1.0,
		"never more than one accepted recovery step per solve"
	)


# ---------------------------------------------------------------------------
# 6 - invariants
# ---------------------------------------------------------------------------

func _test_conservation_and_counterflow() -> void:
	var result: Dictionary = _solve_capture(CORRIDOR)
	if not bool(result["converged"]):
		return
	var net_mass: float = 0.0
	var net_energy: float = 0.0
	for key in result["net_mass_by_room"].keys():
		net_mass += float(result["net_mass_by_room"][key])
		net_energy += float(result["net_energy_by_room"][key])
	_assert_true(
		absf(net_mass) < 1.0e-12,
		"interior mass conserved across a rescued solve (%s kg)"
				% String.num_scientific(net_mass)
	)
	_assert_true(
		absf(net_energy) < 1.0e-9,
		"interior energy conserved across a rescued solve (%s kJ)"
				% String.num_scientific(net_energy)
	)
	_assert_true(
		float(result["counterflow_violation_count"]) == 0.0,
		"no counterflow violation on a rescued solve"
	)
	for raw_connection in result["connections"]:
		var connection: Dictionary = raw_connection
		if not bool(connection.get("neutral_plane_inside", false)):
			continue
		_assert_true(
			float(connection["a_to_b_kg"]) > 0.0
					and float(connection["b_to_a_kg"]) > 0.0,
			"a neutral plane inside the span still carries both directions"
		)


func _test_determinism() -> void:
	var first: Dictionary = _solve_capture(CORRIDOR)
	var second: Dictionary = _solve_capture(CORRIDOR)
	for field in ["converged", "iterations", "limiting_reason",
			"rescue_attempted", "rescue_accepted", "rescue_trials",
			"rescue_lambda"]:
		_assert_true(
			str(first[field]) == str(second[field]),
			"rescued solve is deterministic for " + field
		)
	for key in first["gauge_pressure_by_room"].keys():
		_assert_true(
			float(first["gauge_pressure_by_room"][key])
					== float(second["gauge_pressure_by_room"][key]),
			"bit-identical gauge pressure for room %s across runs" % key
		)


func _test_recovery_is_not_convergence() -> void:
	# The rescued step is appended to the residual history and then the ordinary
	# loop continues; the solve must take further iterations rather than
	# declaring victory on the rescue itself.
	var result: Dictionary = _solve_capture(CORRIDOR)
	if not bool(result["converged"]):
		return
	_assert_true(
		int(result["iterations"]) > 3,
		"the solve kept iterating after the rescue (%d iterations)"
				% int(result["iterations"])
	)
	_assert_true(
		float(result["rescue_final_norm"]) > 1.0e-12,
		"the rescue step itself was nowhere near the tolerance"
	)


# ---------------------------------------------------------------------------
# inputs
# ---------------------------------------------------------------------------

func _two_rooms(mass_factor: float, energy_scale: float) -> Dictionary:
	return {
		"0": {
			"volume_m3": 48.0, "floor_area_m2": 20.0, "height_m": 2.4,
			"upper_gas_kg": 13.341180715258982,
			"lower_gas_kg": 43.89700581336613 * mass_factor,
			"upper_energy_kj": 105.7778942601438 * energy_scale,
			"lower_energy_kj": 2.2979616486586663,
		},
		"1": {
			"volume_m3": 25.2, "floor_area_m2": 10.5, "height_m": 2.4,
			"upper_gas_kg": 0.28611634716922923,
			"lower_gas_kg": 29.95468972035928,
			"upper_energy_kj": 0.13579428978793925,
			"lower_energy_kj": 0.0037982474251549094,
		},
	}


func _two_room_openings() -> Array:
	return [{
		"opening_id": 0, "room_a_id": 0, "room_b_id": 1,
		"bottom_m": 0.0, "top_m": 2.0, "width_m": 0.9,
		"open_fraction": 1.0, "discharge_coeff": 0.61,
	}]


func _two_room_sources() -> Dictionary:
	return {
		"0": {"mass_kg": -0.0015158343655711755, "energy_kj": 1.1004597534676916},
		"1": {"mass_kg": -0.0011235286430259133, "energy_kj": -0.01068444773584418},
	}


## The corridor capture's rooms with both lower layers scaled - the real family
## the H2.5f sweep explored.
func _corridor_rooms_scaled(factor: float) -> Dictionary:
	var capture: Dictionary = _load(CORRIDOR)
	var rooms: Dictionary = {}
	var keys: Array = capture["input"]["rooms"].keys()
	keys.sort()
	for index in range(keys.size()):
		var key: String = String(keys[index])
		var room: Dictionary = _numbers(capture["input"]["rooms"][keys[index]])
		if index < 2:
			room["lower_gas_kg"] = float(room["lower_gas_kg"]) * factor
		rooms[key] = room
	return rooms


func _corridor_openings() -> Array:
	var capture: Dictionary = _load(CORRIDOR)
	var openings: Array = []
	for raw_opening in capture["input"]["openings"]:
		var opening: Dictionary = raw_opening
		openings.append({
			"opening_id": int(opening["opening_id"]),
			"room_a_id": int(opening["room_a_id"]),
			"room_b_id": int(opening["room_b_id"]),
			"bottom_m": _decode(opening["bottom_m"]),
			"top_m": _decode(opening["top_m"]),
			"width_m": _decode(opening["width_m"]),
			"open_fraction": _decode(opening["open_fraction"]),
			"discharge_coeff": _decode(opening["discharge_coeff"]),
		})
	return openings


func _corridor_sources() -> Dictionary:
	var capture: Dictionary = _load(CORRIDOR)
	var sources: Dictionary = {}
	for key in capture["input"]["sources"].keys():
		sources[String(key)] = _numbers(capture["input"]["sources"][key])
	return sources


func _solve_capture(path: String) -> Dictionary:
	var capture: Dictionary = _load(path)
	var input: Dictionary = capture["input"]
	var rooms: Dictionary = {}
	for key in input["rooms"].keys():
		rooms[String(key)] = _numbers(input["rooms"][key])
	var sources: Dictionary = {}
	for key in input["sources"].keys():
		sources[String(key)] = _numbers(input["sources"][key])
	var openings: Array = []
	for raw_opening in input["openings"]:
		var opening: Dictionary = raw_opening
		openings.append({
			"opening_id": int(opening["opening_id"]),
			"room_a_id": int(opening["room_a_id"]),
			"room_b_id": int(opening["room_b_id"]),
			"bottom_m": _decode(opening["bottom_m"]),
			"top_m": _decode(opening["top_m"]),
			"width_m": _decode(opening["width_m"]),
			"open_fraction": _decode(opening["open_fraction"]),
			"discharge_coeff": _decode(opening["discharge_coeff"]),
		})
	return SolverScript.new().solve_coupled_pressure(
		rooms, openings, sources,
		_decode(input["dt"]), _decode(input["reference_temp_c"]), {}
	)


# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

func _load(path: String) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("cannot open " + path)
		_failed = true
		return {"input": {"rooms": {}, "openings": [], "sources": {}}}
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("capture is not a JSON object: " + path)
		_failed = true
		return {"input": {"rooms": {}, "openings": [], "sources": {}}}
	return parsed


func _decode(leaf) -> float:
	if typeof(leaf) == TYPE_DICTIONARY and leaf.has("x"):
		var hex: String = String(leaf["x"])
		var bytes: PackedByteArray = PackedByteArray()
		for index in range(0, hex.length(), 2):
			bytes.append(hex.substr(index, 2).hex_to_int())
		if bytes.size() == 8:
			return bytes.decode_double(0)
		return float(String(leaf["d"]))
	return float(String(leaf))


func _numbers(source: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key in source.keys():
		out[String(key)] = _decode(source[key])
	return out


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

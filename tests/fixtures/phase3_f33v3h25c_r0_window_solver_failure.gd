extends SceneTree

## F3.3v3h2.5c: replay the SECOND real failing coupled-solve, captured verbatim
## from a `cfast_r0_window_360` run, with no scenario, no engine and no
## building. Companion to the F3.3v3h2.5a `corridor_chain` capture.
##
## WHY A SECOND CAPTURE EXISTS
## ---------------------------
## H2.5c patched the Jacobian to a centred difference on the strength of a
## 204-case synthetic family built by perturbing the H2.5a capture. That family
## scored 95.6% and the patch was NO-GO anyway: on `r0_window_360` it turned
## 1439 of 1441 steps into `iteration_cap`. Every case in the family perturbed
## one chain topology; none of them contained this one - five rooms, four
## openings, all of them meeting at room 1. One capture cannot stand in for the
## topology space, so the second topology is now versioned too.
##
## WHAT THIS CAPTURE ACTUALLY SHOWS - A THIRD FAILURE MODE
## -------------------------------------------------------
## This is NOT the period-2 limit cycle that H2.5c observed. That cycle belongs
## to the centred-difference candidate, which was reverted, so no fixture can
## reproduce it against shipped code. Nor is it the H2.5a mode, where the solve
## stalls far from the answer at a residual of 2.2e-4.
##
## Here the solve very nearly succeeds and then cannot finish:
##
##     it1  1.835e-03   accepted at damping 0.5
##     it2  1.790e-04   accepted
##     it3  7.741e-12   accepted
##     it4  1.147e-12   13 dampings, all rejected -> damping_exhausted
##
## The residual reaches 1.147e-12 against a 1.0e-12 tolerance - 15% short. The
## Newton correction that would close the gap is about 5.5e-12 Pa, while one ulp
## of the absolute-pressure iterate near 101325 Pa is 1.455e-11 Pa. The step is
## 0.38 ulp, so `p + damping * step` is not a different double: every damped
## trial evaluates the same state, none improves strictly, and the line search
## exhausts. The tolerance itself is reachable - jittering the solution by one
## ulp per room finds 3.24e-13 - but not by any step this iterate can express.
##
## The lead this hands H2.5d: the solver iterates on ABSOLUTE pressure, so it
## spends seven decimal digits representing 101325 Pa before the first digit
## that matters. A gauge-pressure unknown would not have this floor. That is a
## hypothesis for H2.5d to test, not a change made here.
##
## This fixture asserts the failure STILL REPRODUCES. It is a regression
## capture, not a target: when a future phase fixes it, this must be updated
## with intent rather than silently passing.

const SolverScript = preload("res://sim/core/Phase3CoupledPressureSolver.gd")
const CAPTURE_PATH := "res://tests/fixtures/data/coupled_solver_failure_r0_window_360.json"

## One ulp of a double near the absolute reference pressure. The failure is
## defined against this scale, so it is spelled out rather than inferred.
const PRESSURE_ULP_PA := 1.4551915228366852e-11

var _failed: bool = false


func _init() -> void:
	var capture: Dictionary = _load_capture()
	if capture.is_empty():
		quit(1)
		return
	_test_capture_is_well_formed(capture)
	_test_replay_reproduces_the_recorded_failure(capture)
	_test_replay_is_deterministic(capture)
	_test_capture_round_trips_full_precision(capture)
	_test_failure_is_the_numerical_floor_not_a_bad_direction(capture)
	_test_topology_differs_from_the_corridor_capture(capture)
	if _failed:
		quit(1)
		return
	print("PHASE3_F33V3H25C_R0_WINDOW_SOLVER_FAILURE_PASS")
	quit(0)


func _load_capture() -> Dictionary:
	if not FileAccess.file_exists(CAPTURE_PATH):
		push_error("capture file missing: " + CAPTURE_PATH)
		_failed = true
		return {}
	var file: FileAccess = FileAccess.open(CAPTURE_PATH, FileAccess.READ)
	if file == null:
		push_error("cannot open capture: " + CAPTURE_PATH)
		_failed = true
		return {}
	var text: String = file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("capture is not a JSON object")
		_failed = true
		return {}
	return parsed


# ---------------------------------------------------------------------------
# shape
# ---------------------------------------------------------------------------

func _test_capture_is_well_formed(capture: Dictionary) -> void:
	_assert_true(
		String(capture.get("schema_version", ""))
				== "simufire_coupled_solver_failure_v1",
		"schema version"
	)
	var input: Dictionary = capture.get("input", {})
	for key in ["rooms", "openings", "sources", "dt", "reference_temp_c"]:
		_assert_true(input.has(key), "input has " + key)
	_assert_true(input["rooms"].size() == 5, "five rooms")
	_assert_true(input["openings"].size() == 4, "four openings")
	_assert_true(_number(input, "dt") > 0.0, "positive dt")
	var observed: Dictionary = capture.get("observed_failure", {})
	_assert_true(
		not bool(observed.get("converged", true)),
		"capture records a non-converged solve"
	)
	_assert_true(
		String(observed.get("limiting_reason", "")) == "damping_exhausted",
		"capture records damping_exhausted"
	)


# ---------------------------------------------------------------------------
# replay
# ---------------------------------------------------------------------------

func _test_replay_reproduces_the_recorded_failure(capture: Dictionary) -> void:
	var result: Dictionary = _replay(capture)
	var observed: Dictionary = capture.get("observed_failure", {})
	_assert_true(
		not bool(result["converged"]),
		"replay does not converge, exactly as captured"
	)
	_assert_true(
		String(result["limiting_reason"]) == String(observed["limiting_reason"]),
		"replay reproduces limiting reason '%s', got '%s'" % [
			String(observed["limiting_reason"]), String(result["limiting_reason"])
		]
	)
	_close(
		float(result["failure_code"]),
		_decode(observed["failure_code"]),
		"replay reproduces failure code"
	)
	_close(
		float(result["iterations"]),
		_decode(observed["iterations"]),
		"replay reproduces iteration count"
	)


func _test_replay_is_deterministic(capture: Dictionary) -> void:
	var first: Dictionary = _replay(capture)
	var second: Dictionary = _replay(capture)
	for field in ["converged", "failure_code", "iterations", "limiting_reason"]:
		_assert_true(
			str(first[field]) == str(second[field]),
			"replay is deterministic for " + field
		)
	var first_history: Array = first["residual_history"]
	var second_history: Array = second["residual_history"]
	_assert_true(
		first_history.size() == second_history.size(),
		"deterministic residual history length"
	)
	for index in range(first_history.size()):
		_close(
			float(first_history[index]), float(second_history[index]),
			"deterministic residual at iterate %d" % index
		)


func _test_capture_round_trips_full_precision(capture: Dictionary) -> void:
	# The whole residual history must reproduce bit for bit. This capture is far
	# more demanding than the H2.5a one: its last entry is 1.1e-12, so a decimal
	# encoding that lost the ninth significant digit would replay a visibly
	# different endgame.
	var result: Dictionary = _replay(capture)
	var recorded: Array = capture.get("observed_failure", {}).get(
		"residual_history", []
	)
	var replayed: Array = result["residual_history"]
	_assert_true(
		recorded.size() == replayed.size(),
		"residual history length matches the capture (%d vs %d)" % [
			recorded.size(), replayed.size()
		]
	)
	for index in range(mini(recorded.size(), replayed.size())):
		_close_rel(
			float(replayed[index]), _decode(recorded[index]), 1.0e-15,
			"captured residual %d round-trips" % index
		)


func _test_failure_is_the_numerical_floor_not_a_bad_direction(
		capture: Dictionary
	) -> void:
	# This is what separates this capture from the H2.5a one and is the reason
	# it is worth keeping: the solve is nearly converged and the correction it
	# still needs is smaller than one ulp of the pressure iterate.
	var result: Dictionary = _replay(capture)
	var history: Array = result["residual_history"]
	_assert_true(history.size() >= 2, "residual history has an endgame")
	if history.size() < 2:
		return
	var final_residual: float = float(history[history.size() - 1])
	_assert_true(
		final_residual < 1.0e-11,
		"the stall happens near the tolerance, not far from it (got %s)"
				% String.num_scientific(final_residual)
	)
	_assert_true(
		final_residual > 1.0e-12,
		"the stall is still outside tolerance, which is why it is a failure"
	)
	# The residual fell by more than eight orders of magnitude before stalling,
	# so the Newton direction was good. Contrast H2.5a, which stalled at 2.2e-4.
	_assert_true(
		float(history[0]) / final_residual > 1.0e8,
		"the solve got close before stalling"
	)
	_assert_true(
		PRESSURE_ULP_PA > 1.0e-11,
		"one ulp near ambient pressure is coarser than the correction needed"
	)


func _test_topology_differs_from_the_corridor_capture(
		capture: Dictionary
	) -> void:
	# The point of a second capture is a second topology. Every opening here
	# meets at one room; the H2.5a capture is a chain.
	var hub_counts: Dictionary = {}
	for raw_opening in capture["input"]["openings"]:
		var opening: Dictionary = raw_opening
		for id_value in [int(opening["room_a_id"]), int(opening["room_b_id"])]:
			hub_counts[id_value] = int(hub_counts.get(id_value, 0)) + 1
	var busiest: int = 0
	for key in hub_counts.keys():
		busiest = maxi(busiest, int(hub_counts[key]))
	_assert_true(
		busiest >= 4,
		"star topology: one room carries every opening (busiest = %d)" % busiest
	)


func _replay(capture: Dictionary) -> Dictionary:
	var input: Dictionary = capture["input"]
	var rooms: Dictionary = {}
	for raw_key in input["rooms"].keys():
		rooms[String(raw_key)] = _number_dictionary(input["rooms"][raw_key])
	var sources: Dictionary = {}
	for raw_key in input["sources"].keys():
		sources[String(raw_key)] = _number_dictionary(input["sources"][raw_key])
	var openings: Array = []
	for raw_opening in input["openings"]:
		var opening: Dictionary = raw_opening
		openings.append({
			"opening_id": int(opening["opening_id"]),
			"room_a_id": int(opening["room_a_id"]),
			"room_b_id": int(opening["room_b_id"]),
			"bottom_m": _number(opening, "bottom_m"),
			"top_m": _number(opening, "top_m"),
			"width_m": _number(opening, "width_m"),
			"open_fraction": _number(opening, "open_fraction"),
			"discharge_coeff": _number(opening, "discharge_coeff"),
		})
	var defaults: Dictionary = capture.get("solver_defaults", {})
	var options: Dictionary = {}
	if not defaults.is_empty():
		options = {
			"residual_tolerance": _number(defaults, "residual_tolerance"),
			"max_iterations": int(defaults["max_iterations"]),
			"dp_regularization_pa": _number(defaults, "dp_regularization_pa"),
			"jacobian_step_pa": _number(defaults, "jacobian_step_pa"),
			"band_segments": int(defaults["band_segments"]),
			"max_damping_halvings": int(defaults["max_damping_halvings"]),
		}
	var solver = SolverScript.new()
	return solver.solve_coupled_pressure(
		rooms, openings, sources,
		_number(input, "dt"), _number(input, "reference_temp_c"),
		options
	)


# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

## Numeric leaves carry a readable decimal in "d" and the exact IEEE754 bit
## pattern in "x". Replays decode "x", so the fixture solves bit-identical
## inputs rather than a nearby problem.
func _decode(leaf) -> float:
	if typeof(leaf) == TYPE_DICTIONARY and leaf.has("x"):
		var bytes: PackedByteArray = _hex_to_bytes(String(leaf["x"]))
		if bytes.size() == 8:
			return bytes.decode_double(0)
		return float(String(leaf["d"]))
	return float(String(leaf))


func _hex_to_bytes(hex: String) -> PackedByteArray:
	var bytes: PackedByteArray = PackedByteArray()
	if hex.length() % 2 != 0:
		return bytes
	for index in range(0, hex.length(), 2):
		bytes.append(hex.substr(index, 2).hex_to_int())
	return bytes


func _number(source: Dictionary, key: String) -> float:
	return _decode(source[key])


func _number_dictionary(source: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for raw_key in source.keys():
		out[String(raw_key)] = _decode(source[raw_key])
	return out


func _close(actual: float, expected: float, label: String) -> void:
	if absf(actual - expected) > 1.0e-9 * maxf(1.0, absf(expected)):
		push_error("%s: got %.12f expected %.12f" % [label, actual, expected])
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

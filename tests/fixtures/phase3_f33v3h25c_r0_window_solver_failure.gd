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
## F3.3v3h2.5e FIXED THIS AND THIS FIXTURE WAS FLIPPED ON PURPOSE.
##
## As written it asserted the failure still reproduced, so a fix would break it
## loudly instead of passing in silence. That is what happened. H2.5e moved the
## solve into gauge coordinates: the unknown is now order 1e-5 Pa rather than
## 101325 Pa, so the correction that was 0.38 ulp is now representable many
## times over. This input converges in 3 iterations to a normalized residual of
## about 9.5e-17, five orders of magnitude inside the unchanged 1e-12 tolerance.
##
## The captured JSON is NOT re-recorded. It stays a verbatim record of what the
## absolute-pressure formulation did on 2026-07-28, and the fixture still
## asserts that the record says `damping_exhausted`, so a regression back to
## absolute coordinates is visible rather than implicit.
##
## The companion `corridor_chain` capture is still an open failure. H2.5e fixed
## the numerical-floor mode only; it did not fix that one, and H3 stays blocked.

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
	_test_solve_now_clears_the_old_numerical_floor(capture)
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
		bool(result["converged"]),
		"the captured input converges in gauge coordinates"
	)
	_assert_true(
		String(result["limiting_reason"]) == "converged",
		"limiting reason is 'converged', got '%s'" % String(result["limiting_reason"])
	)
	_assert_true(
		float(result["failure_code"]) == 0.0,
		"a converged solve records no failure code"
	)
	_assert_true(
		float(result["normalized_residual"]) <= 1.0e-12,
		"the solve closes its residual inside the unchanged tolerance"
	)
	_assert_true(
		float(result["counterflow_violation_count"]) == 0.0,
		"no counterflow violation on the converged solve"
	)
	# The record keeps saying what absolute coordinates did, so a regression is
	# detectable instead of being quietly re-baselined.
	_assert_true(
		not bool(observed.get("converged", true))
				and String(observed.get("limiting_reason", "")) == "damping_exhausted",
		"the capture still records the original absolute-coordinate failure"
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


## Pure encoding test - no solver involved, so it cannot drift when the solver
## changes. Each leaf must re-encode to its own bit pattern, and at least one
## must carry information its readable decimal does not.
func _test_capture_round_trips_full_precision(capture: Dictionary) -> void:
	var checked: int = 0
	var beyond_decimal: int = 0
	for leaf in _collect_leaves(capture):
		var value: float = _decode(leaf)
		var bytes: PackedByteArray = PackedByteArray()
		bytes.resize(8)
		bytes.encode_double(0, value)
		_assert_true(
			bytes.hex_encode() == String(leaf["x"]).to_lower(),
			"leaf re-encodes to its own bit pattern"
		)
		checked += 1
		if float(String(leaf["d"])) != value:
			beyond_decimal += 1
	_assert_true(checked > 0, "capture exposes encoded leaves")
	_assert_true(
		beyond_decimal > 0,
		"at least one leaf is not recoverable from its readable decimal alone"
	)


func _collect_leaves(node) -> Array:
	var found: Array = []
	if typeof(node) == TYPE_DICTIONARY:
		var as_dict: Dictionary = node
		if as_dict.has("x") and as_dict.has("d"):
			found.append(as_dict)
			return found
		for key in as_dict.keys():
			found.append_array(_collect_leaves(as_dict[key]))
	elif typeof(node) == TYPE_ARRAY:
		for entry in node:
			found.append_array(_collect_leaves(entry))
	return found


## The point of the H2.5e change: the solve must now finish BELOW the floor that
## used to stop it. The recorded stall was 1.147e-12, just outside tolerance and
## unreachable because the remaining correction was 0.38 ulp of an absolute
## pressure. In gauge coordinates the same input lands orders of magnitude
## further down, which is only possible if that floor is genuinely gone.
func _test_solve_now_clears_the_old_numerical_floor(capture: Dictionary) -> void:
	var result: Dictionary = _replay(capture)
	var history: Array = result["residual_history"]
	_assert_true(history.size() >= 2, "residual history has an endgame")
	if history.size() < 2:
		return
	var final_residual: float = float(history[history.size() - 1])
	var recorded_stall: float = _decode(
		capture["observed_failure"]["residual_history"][-1]
	)
	_assert_true(
		final_residual < recorded_stall * 1.0e-3,
		"the solve finishes far below the recorded stall (%s vs %s)" % [
			String.num_scientific(final_residual),
			String.num_scientific(recorded_stall)
		]
	)
	_assert_true(
		final_residual <= 1.0e-12,
		"the final residual is inside the unchanged tolerance"
	)
	# The gauge iterate is orders of magnitude smaller than ambient, which is
	# the whole reason the last correction is now representable.
	var gauge_map: Dictionary = result["gauge_pressure_by_room"]
	var largest_gauge: float = 0.0
	for key in gauge_map.keys():
		largest_gauge = maxf(largest_gauge, absf(float(gauge_map[key])))
	_assert_true(
		largest_gauge < 1.0e3,
		"the iterate is a gauge pressure, not an absolute one (max %s Pa)"
				% String.num_scientific(largest_gauge)
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

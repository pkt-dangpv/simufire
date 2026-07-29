extends SceneTree

## F3.3v3h2.5h: replay a REAL `iteration_cap`, captured verbatim from a
## `cfast_corridor_chain` run with the complete H2 stack, with no scenario, no
## engine and no building.
##
## WHY IT EXISTS
## ------------
## After H2.5g, `iteration_cap` is the dominant remaining failure mode - 217 of
## it at 120 s against 11 `damping_exhausted`. It had never been captured,
## because the instrumentation records only the first failure per run. H2.5h
## added an opt-in mode selector so a specific mode can be waited for.
##
## WHAT THE FAILURE LOOKS LIKE - AND WHY THE CAP IS THE BINDING CONSTRAINT
## ----------------------------------------------------------------
## The residual falls MONOTONICALLY on all 24 iterations. Nothing stalls,
## nothing oscillates, no damping is exhausted - the solve is simply cut off:
##
##     it0   2.159613e-02
##     it24  4.338547e-04     (97.99% removed, still far from 1e-12)
##
## Given more room the SAME input converges in 26 iterations to 6.5e-17. The cap
## is two iterations short here. The late-run failures are worse: a step
## captured at the end of a 120 s run needs 108.
##
## So the cap IS binding, and this fixture measures by how much rather than
## asserting a rhetorical claim about it. That is deliberately not an argument
## for raising it: 26 and 108 iterations are both far past the handful a healthy
## Newton needs, so the real defect is the rate, not the budget. Raising the cap
## would convert a visible failure into a slow success and hide the symptom.
## H2.5i has to explain why quadratic convergence is lost.
##
## This fixture asserts the failure STILL REPRODUCES. It is a regression
## capture, not a target: when a future phase fixes it, this must be updated
## with intent rather than silently passing.

const SolverScript = preload("res://sim/core/Phase3CoupledPressureSolver.gd")
const CAPTURE_PATH := "res://tests/fixtures/data/coupled_solver_iteration_cap_corridor_chain.json"

## The documented cap. The capture must sit exactly on it, or it is not an
## `iteration_cap`.
const EXPECTED_ITERATIONS := 24

var _failed: bool = false


func _init() -> void:
	var capture: Dictionary = _load_capture()
	if capture.is_empty():
		quit(1)
		return
	_test_capture_is_well_formed(capture)
	_test_capture_records_the_requested_mode(capture)
	_test_replay_reproduces_the_iteration_cap(capture)
	_test_replay_is_deterministic(capture)
	_test_capture_round_trips_full_precision(capture)
	_test_residual_falls_monotonically_but_far_too_slowly(capture)
	_test_a_larger_budget_converges_the_same_input(capture)
	if _failed:
		quit(1)
		return
	print("PHASE3_F33V3H25H_ITERATION_CAP_PASS")
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
		"shares the v1 schema with the earlier captures"
	)
	var input: Dictionary = capture.get("input", {})
	for key in ["rooms", "openings", "sources", "dt", "reference_temp_c"]:
		_assert_true(input.has(key), "input has " + key)
	_assert_true(input["rooms"].size() >= 2, "at least two rooms")
	_assert_true(input["openings"].size() >= 1, "at least one opening")
	_assert_true(_number(input, "dt") > 0.0, "positive dt")
	var defaults: Dictionary = capture.get("solver_defaults", {})
	_assert_true(
		int(defaults.get("max_iterations", 0)) == EXPECTED_ITERATIONS,
		"the capture records the iteration cap it hit"
	)


func _test_capture_records_the_requested_mode(capture: Dictionary) -> void:
	# The mode selector is what made this capture reachable at all, so the
	# artifact states which mode it was asked for.
	_assert_true(
		String(capture.get("requested_failure_mode", "")) == "iteration_cap",
		"capture records that iteration_cap was explicitly requested"
	)
	var observed: Dictionary = capture.get("observed_failure", {})
	_assert_true(
		not bool(observed.get("converged", true)),
		"capture records a non-converged solve"
	)
	_assert_true(
		String(observed.get("limiting_reason", "")) == "iteration_cap",
		"capture records iteration_cap, got '%s'"
				% String(observed.get("limiting_reason", ""))
	)


# ---------------------------------------------------------------------------
# replay
# ---------------------------------------------------------------------------

func _test_replay_reproduces_the_iteration_cap(capture: Dictionary) -> void:
	var result: Dictionary = _replay(capture)
	var observed: Dictionary = capture.get("observed_failure", {})
	_assert_true(
		not bool(result["converged"]),
		"replay does not converge, exactly as captured"
	)
	_assert_true(
		String(result["limiting_reason"]) == "iteration_cap",
		"replay reproduces iteration_cap, got '%s'"
				% String(result["limiting_reason"])
	)
	_close(
		float(result["failure_code"]), _decode(observed["failure_code"]),
		"replay reproduces the failure code"
	)
	_assert_true(
		int(result["iterations"]) == EXPECTED_ITERATIONS,
		"replay uses the full iteration budget (%d)" % int(result["iterations"])
	)
	# The bounded LM recovery must NOT have been involved: it only exists for
	# the damping dead end, and this failure is a different animal.
	_assert_true(
		float(result.get("rescue_attempted", 0.0)) == 0.0
				and float(result.get("rescue_accepted", 0.0)) == 0.0,
		"the LM recovery is not reached by an iteration_cap"
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
		_assert_true(
			float(first_history[index]) == float(second_history[index]),
			"bit-identical residual at iterate %d" % index
		)


func _test_capture_round_trips_full_precision(capture: Dictionary) -> void:
	# Pure encoding check - no solver involved, so it cannot drift when the
	# solver changes. Each leaf must re-encode to its own bit pattern, and at
	# least one must carry more than its readable decimal.
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
	# and the replayed trajectory must match the recording bit for bit
	var result: Dictionary = _replay(capture)
	var recorded: Array = capture["observed_failure"]["residual_history"]
	var replayed: Array = result["residual_history"]
	_assert_true(
		recorded.size() == replayed.size(),
		"residual history length matches (%d vs %d)"
				% [recorded.size(), replayed.size()]
	)
	for index in range(mini(recorded.size(), replayed.size())):
		_close_rel(
			float(replayed[index]), _decode(recorded[index]), 1.0e-15,
			"captured residual %d round-trips exactly" % index
		)


func _test_residual_falls_monotonically_but_far_too_slowly(
		capture: Dictionary
	) -> void:
	# The anatomy, asserted rather than described.
	var result: Dictionary = _replay(capture)
	var history: Array = result["residual_history"]
	_assert_true(history.size() >= 3, "history long enough to characterise")
	if history.size() < 3:
		return
	for index in range(history.size() - 1):
		_assert_true(
			float(history[index + 1]) < float(history[index]),
			"residual falls at iterate %d - nothing stalls" % index
		)
	var last: float = float(history[history.size() - 1])
	_assert_true(
		last > 1.0e-12,
		"it is cut off outside the tolerance (%s)" % String.num_scientific(last)
	)


## The load-bearing measurement: give the SAME input a larger budget and it
## converges. That proves the cap is what stopped it, and says by how much,
## without touching any default - `max_iterations` is a per-call option.
func _test_a_larger_budget_converges_the_same_input(
		capture: Dictionary
	) -> void:
	var relaxed: Dictionary = _replay_with_iteration_cap(capture, 100)
	_assert_true(
		bool(relaxed["converged"]),
		"the same input converges when the budget is not the constraint"
	)
	_assert_true(
		int(relaxed["iterations"]) > EXPECTED_ITERATIONS,
		"it needed more than the shipped cap (%d)" % int(relaxed["iterations"])
	)
	# ...but nowhere near what a healthy Newton would need, which is the point.
	_assert_true(
		int(relaxed["iterations"]) > 10,
		"convergence is slow, not merely one iteration short (%d)"
				% int(relaxed["iterations"])
	)
	_assert_true(
		float(relaxed["normalized_residual"]) <= 1.0e-12,
		"and it closes properly once allowed to finish"
	)

func _replay_with_iteration_cap(
		capture: Dictionary, iteration_cap: int
	) -> Dictionary:
	var overridden: Dictionary = capture.duplicate(true)
	overridden["solver_defaults"]["max_iterations"] = iteration_cap
	return _replay(overridden)


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
		_number(input, "dt"), _number(input, "reference_temp_c"), options
	)


# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

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

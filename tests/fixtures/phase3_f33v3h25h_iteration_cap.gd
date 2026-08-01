extends SceneTree

## F3.3v3h2.5h/j: replay a REAL `iteration_cap`, captured verbatim from a
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
## The L-infinity residual falls MONOTONICALLY on all 24 iterations, which
## originally hid the defect:
##
##     it0   2.159613e-02
##     it24  4.338547e-04     (97.99% removed, still far from 1e-12)
##
## H2.5i showed that the pressure step itself oscillates. Successive Newton
## directions have cosine approximately -1, the opening donors reverse at all
## 16 quadrature points, and the linear model promises closure while the real
## sum-of-squares merit improves by only 0-3%. The bare strict-decrease test
## accepts that period-2 zigzag until the cap interrupts it.
##
## H2.5j is that intentional fix. The original artifact remains byte-for-byte
## unchanged, while this fixture now requires the accepted-cycle safeguard to
## recognize the period-2 zigzag and converge through one bounded LM step.

const SolverScript = preload("res://sim/core/Phase3CoupledPressureSolver.gd")
const CAPTURE_PATH := "res://tests/fixtures/data/coupled_solver_iteration_cap_corridor_chain.json"

## The documented cap. The capture must sit exactly on it, or it is not an
## `iteration_cap`.
const CAPTURED_MAX_ITERATIONS := 24
## H2.5m: the analytic half step now annihilates this orbit before the cycle
## guard is reached, closing the same capture one iteration earlier and without
## spending the LM budget. Was 8 under the H2.5j cycle guard.
const EXPECTED_FIXED_ITERATIONS := 7

var _failed: bool = false


func _init() -> void:
	var capture: Dictionary = _load_capture()
	if capture.is_empty():
		quit(1)
		return
	_test_capture_is_well_formed(capture)
	_test_capture_records_the_requested_mode(capture)
	_test_cycle_guard_closes_the_iteration_cap(capture)
	_test_replay_is_deterministic(capture)
	_test_capture_round_trips_full_precision(capture)
	_test_recorded_residual_exposes_the_original_slow_cycle(capture)
	_test_default_budget_is_now_sufficient(capture)
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
		int(defaults.get("max_iterations", 0)) == CAPTURED_MAX_ITERATIONS,
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

func _test_cycle_guard_closes_the_iteration_cap(capture: Dictionary) -> void:
	var result: Dictionary = _replay(capture)
	_assert_true(
		bool(result["converged"]),
		"the captured iteration_cap now converges"
	)
	_assert_true(
		String(result["limiting_reason"]) == "converged",
		"replay closes as converged, got '%s'"
				% String(result["limiting_reason"])
	)
	_assert_true(
		int(result["iterations"]) == EXPECTED_FIXED_ITERATIONS,
		"the capture closes in %d iterations, got %d"
				% [EXPECTED_FIXED_ITERATIONS, int(result["iterations"])]
	)
	# H2.5m changed which mechanism closes this capture. The half step is tried
	# first and succeeds, so the cycle guard is never reached and the bounded LM
	# budget is left untouched - which is the point: it stays available for the
	# `damping_exhausted` dead end it was built for.
	_assert_true(
		float(result.get("analytic_half_step_attempt_total", 0.0)) == 1.0
				and float(result.get("analytic_half_step_accept_total", 0.0))
						== 1.0,
		"one analytic half step is attempted and accepted"
	)
	_assert_true(
		float(result.get("cycle_guard_attempt_total", 0.0)) == 0.0
				and float(result.get("cycle_guard_accept_total", 0.0)) == 0.0,
		"the cycle guard is no longer reached on this capture"
	)
	_assert_true(
		float(result.get("rescue_attempted", 0.0)) == 0.0
				and float(result.get("rescue_accepted", 0.0)) == 0.0,
		"the LM rescue budget is left unspent"
	)
	_assert_true(
		float(result["normalized_residual"]) <= 1.0e-12,
		"the fixed replay closes below the unchanged tolerance"
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
func _test_recorded_residual_exposes_the_original_slow_cycle(
		capture: Dictionary
	) -> void:
	# Preserve the original failure anatomy without requiring the corrected
	# solver to reproduce it.
	var history: Array = capture["observed_failure"]["residual_history"]
	_assert_true(history.size() >= 3, "history long enough to characterise")
	if history.size() < 3:
		return
	for index in range(history.size() - 1):
		_assert_true(
			_decode(history[index + 1]) < _decode(history[index]),
			"residual falls at iterate %d - nothing stalls" % index
		)
	var last: float = _decode(history[history.size() - 1])
	_assert_true(
		last > 1.0e-12,
		"it is cut off outside the tolerance (%s)" % String.num_scientific(last)
	)


func _test_default_budget_is_now_sufficient(
		capture: Dictionary
	) -> void:
	var fixed: Dictionary = _replay(capture)
	_assert_true(
		bool(fixed["converged"]),
		"the same input converges under the shipped budget"
	)
	_assert_true(
		int(fixed["iterations"]) < CAPTURED_MAX_ITERATIONS,
		"the guard closes before the cap (%d)" % int(fixed["iterations"])
	)
	_assert_true(
		float(fixed["normalized_residual"]) <= 1.0e-12,
		"and closes against the unchanged tolerance"
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

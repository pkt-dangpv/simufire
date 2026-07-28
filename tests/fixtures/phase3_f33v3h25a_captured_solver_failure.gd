extends SceneTree

## F3.3v3h2.5a: replay a REAL failing coupled-solve, captured verbatim from a
## corridor_chain run, with no scenario, no engine and no building.
##
## The point is determinism. F3.3v3h2.5 tried to diagnose the 13.6%
## non-convergence from synthetic states and failed: 528 reconstructed cases
## converged 100% of the time. Only the actual inputs reproduce the actual
## failure, so they are versioned as data and replayed here.
##
## This fixture deliberately asserts that the solve STILL FAILS. It is a
## regression capture, not a target: when a future phase fixes convergence,
## this fixture must be updated with intent rather than silently passing.

const SolverScript = preload("res://sim/core/Phase3CoupledPressureSolver.gd")
const CAPTURE_PATH := "res://tests/fixtures/data/coupled_solver_failure_corridor_chain.json"

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
	if _failed:
		quit(1)
		return
	print("PHASE3_F33V3H25A_CAPTURED_SOLVER_FAILURE_PASS")
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
	_assert_true(input["rooms"].size() >= 2, "at least two rooms")
	_assert_true(input["openings"].size() >= 1, "at least one opening")
	_assert_true(_number(input, "dt") > 0.0, "positive dt")
	var observed: Dictionary = capture.get("observed_failure", {})
	_assert_true(
		not bool(observed.get("converged", true)),
		"capture records a non-converged solve"
	)
	_assert_true(
		String(observed.get("limiting_reason", "")) != "",
		"capture records a limiting reason"
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
	# A capture whose numbers were truncated on the way to disk would replay a
	# different problem, so the recorded residual history must be reproduced
	# exactly rather than approximately.
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
		push_error("%s: got %.17f expected %.17f" % [label, actual, expected])
		_failed = true


func _assert_true(condition: bool, label: String) -> void:
	if not condition:
		push_error(label)
		_failed = true

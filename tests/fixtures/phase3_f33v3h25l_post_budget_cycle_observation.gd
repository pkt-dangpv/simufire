extends SceneTree

## H2.5l-A: replay the first real corridor solve captured after an accepted
## cycle-guard rescue still ended at `iteration_cap`. The solver must preserve
## that outcome while passively observing the recurrent period-2 sequence.

const SolverScript = preload("res://sim/core/Phase3CoupledPressureSolver.gd")
const CAPTURE_PATH := "res://tests/fixtures/data/coupled_solver_iteration_cap_after_rescue_corridor_chain.json"

var _failed: bool = false


func _init() -> void:
	var capture: Dictionary = _load_capture()
	if capture.is_empty():
		quit(1)
		return
	var first: Dictionary = _replay(capture)
	var second: Dictionary = _replay(capture)
	_assert_true(
		String(capture.get("requested_failure_mode", ""))
				== "iteration_cap_after_rescue",
		"capture records the composite selector"
	)
	_assert_true(
		not bool(first.get("converged", true))
				and String(first.get("limiting_reason", "")) == "iteration_cap",
		"replay preserves the real iteration_cap"
	)
	_assert_true(
		int(first.get("iterations", 0.0)) == 24,
		"replay preserves the unchanged iteration budget"
	)
	_assert_true(
		float(first.get("cycle_guard_attempt_total", 0.0)) == 1.0
				and float(first.get("cycle_guard_accept_total", 0.0)) == 1.0,
		"the one authorised cycle rescue is still accepted"
	)
	_assert_true(
		float(first.get("cycle_detect_after_budget_total", 0.0)) > 0.0,
		"the recurrent cycle is observed after budget exhaustion"
	)
	_assert_true(
		float(first.get("cycle_detect_total", 0.0))
				> float(first.get("cycle_guard_attempt_total", 0.0)),
		"observation continues after intervention authority ends"
	)
	_assert_true(
		float(first.get("cycle_contraction_min", 0.0)) > 0.0
				and float(first.get("cycle_contraction_max", 0.0))
						>= float(first.get("cycle_contraction_min", 0.0)),
		"two-step contraction range is populated and ordered"
	)
	for field in [
		"converged", "limiting_reason", "iterations", "residual_history",
		"cycle_detect_total", "cycle_detect_after_budget_total",
		"cycle_contraction_min", "cycle_contraction_max",
	]:
		_assert_true(first[field] == second[field], "deterministic " + field)
	print(
		"H25L counts detect=%d after_budget=%d min=%.12f max=%.12f"
		% [
			int(first["cycle_detect_total"]),
			int(first["cycle_detect_after_budget_total"]),
			float(first["cycle_contraction_min"]),
			float(first["cycle_contraction_max"]),
		]
	)
	if _failed:
		quit(1)
		return
	print("PHASE3_F33V3H25L_POST_BUDGET_CYCLE_OBSERVATION_PASS")
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
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("capture is not a JSON object")
		_failed = true
		return {}
	return parsed


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
	var defaults: Dictionary = capture["solver_defaults"]
	var options: Dictionary = {
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


func _assert_true(condition: bool, label: String) -> void:
	if not condition:
		push_error(label)
		_failed = true

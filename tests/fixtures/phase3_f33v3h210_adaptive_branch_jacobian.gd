extends SceneTree

## H2.10 runtime contracts for the fail-only adaptive branch-preserving
## unilateral Jacobian. Uses the nine exact committed captures, their 189-state
## deterministic neighbourhood, and a C8 network with parallel openings.

const SolverScript = preload("res://sim/core/Phase3CoupledPressureSolver.gd")
const DATA := "res://tests/fixtures/data"
const CAPTURES := [
	"coupled_solver_damping_exhausted_uk_bungalow",
	"coupled_solver_failure_corridor_chain",
	"coupled_solver_failure_r0_window_360",
	"coupled_solver_iteration_cap_after_rescue_corridor_chain",
	"coupled_solver_iteration_cap_corridor_chain",
	"coupled_solver_iteration_cap_flashover_simple_house",
	"coupled_solver_iteration_cap_three_bed_apartment",
	"coupled_solver_iteration_cap_two_floor_stairwell",
	"coupled_solver_iteration_cap_two_storey_smoke",
]

var _failed: bool = false


func _init() -> void:
	_test_exact_captures()
	_test_neighbourhood()
	_test_parallel_openings_c8()
	if _failed:
		quit(1)
		return
	print("PHASE3_F33V3H210_ADAPTIVE_BRANCH_JACOBIAN_PASS")
	quit(0)


func _test_exact_captures() -> void:
	for name in CAPTURES:
		var capture: Dictionary = _load("%s/%s.json" % [DATA, name])
		var first: Dictionary = _solve_capture(capture, -1)
		var second: Dictionary = _solve_capture(capture, -1)
		_assert(bool(first.get("converged", false)), name + ": converges")
		_assert(
			float(first.get("normalized_residual", 1.0)) <= 1.0e-12,
			name + ": unchanged tolerance"
		)
		for field in [
			"converged", "limiting_reason", "iterations", "residual_history",
			"gauge_pressure_by_room", "adaptive_jacobian_attempt_total",
			"adaptive_jacobian_accept_total", "rescue_accepted",
		]:
			_assert(first.get(field) == second.get(field), name + ": deterministic " + field)
		if name == "coupled_solver_damping_exhausted_uk_bungalow":
			_assert(
				float(first["adaptive_jacobian_accept_total"]) >= 1.0,
				"UK exact capture uses adaptive recovery"
			)
			_assert(
				float(first["rescue_accepted"]) == 0.0,
				"UK exact capture no longer consumes LM"
			)


func _test_neighbourhood() -> void:
	var successes: int = 0
	var adaptive_accepts: int = 0
	var counterflow_violations: float = 0.0
	for name in CAPTURES:
		var capture: Dictionary = _load("%s/%s.json" % [DATA, name])
		for variant in range(21):
			var solved: Dictionary = _solve_capture(capture, variant)
			if bool(solved.get("converged", false)):
				successes += 1
				_assert(
					float(solved.get("normalized_residual", 1.0)) <= 1.0e-12,
					"neighbourhood converged inside unchanged tolerance"
				)
			adaptive_accepts += int(
				float(solved.get("adaptive_jacobian_accept_total", 0.0))
			)
			counterflow_violations += float(
				solved.get("counterflow_violation_count", 0.0)
			)
	# H2.9's branch-preserving fixed-width candidate reached 187/189. The
	# adaptive policy must not underperform the evidence that justified it.
	_assert(successes >= 187, "neighbourhood closes at least 187/189, got %d" % successes)
	_assert(adaptive_accepts > 0, "neighbourhood exercises adaptive authority")
	_assert(counterflow_violations == 0.0, "neighbourhood preserves counterflow")
	print("H210_NEIGHBOURHOOD %d/189 adaptive=%d" % [successes, adaptive_accepts])


func _test_parallel_openings_c8() -> void:
	var openings: Array = [
		{
			"opening_id": 100, "room_a_id": 0, "room_b_id": 1,
			"bottom_m": 0.0, "top_m": 1.0, "width_m": 0.8,
			"open_fraction": 1.0, "discharge_coeff": 0.61,
		},
		{
			"opening_id": 101, "room_a_id": 0, "room_b_id": 1,
			"bottom_m": 1.0, "top_m": 2.0, "width_m": 0.8,
			"open_fraction": 1.0, "discharge_coeff": 0.61,
		},
	]
	var first: Dictionary = SolverScript.new().solve_coupled_pressure(
		_c8_rooms(), openings, _c8_sources(), 1.0 / 120.0, 20.0, {}
	)
	openings.reverse()
	var reordered: Dictionary = SolverScript.new().solve_coupled_pressure(
		_c8_rooms(), openings, _c8_sources(), 1.0 / 120.0, 20.0, {}
	)
	_assert(bool(first.get("converged", false)), "C8 parallel openings converge")
	_assert(first.get("connections", []).size() == 2, "C8 preserves both openings")
	_assert(
		absf(float(first.get("interior_transport_residual_kg", 1.0))) <= 1.0e-12,
		"C8 conserves interior mass"
	)
	_assert(
		float(first.get("counterflow_violation_count", 1.0)) == 0.0,
		"C8 preserves structural counterflow"
	)
	_assert(
		first.get("gauge_pressure_by_room", {})
				== reordered.get("gauge_pressure_by_room", {}),
		"C8 is invariant to parallel-opening input order"
	)


func _c8_rooms() -> Dictionary:
	return {
		"0": {
			"volume_m3": 48.0, "floor_area_m2": 20.0, "height_m": 2.4,
			"upper_gas_kg": 13.341180715258982,
			"lower_gas_kg": 43.89700581336613,
			"upper_energy_kj": 105.7778942601438,
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


func _c8_sources() -> Dictionary:
	return {
		"0": {"mass_kg": -0.0015, "energy_kj": 1.10},
		"1": {"mass_kg": -0.0011, "energy_kj": -0.01},
	}


func _solve_capture(capture: Dictionary, variant: int) -> Dictionary:
	var input: Dictionary = capture["input"]
	var rooms: Dictionary = {}
	for raw_key in input["rooms"].keys():
		rooms[String(raw_key)] = _numbers(input["rooms"][raw_key])
	var sources: Dictionary = {}
	for raw_key in input["sources"].keys():
		sources[String(raw_key)] = _numbers(input["sources"][raw_key])
	if variant >= 0:
		_perturb_inputs(rooms, sources, variant)
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
	var defaults: Dictionary = capture["solver_defaults"]
	var options: Dictionary = {
		"residual_tolerance": _decode(defaults["residual_tolerance"]),
		"max_iterations": int(defaults["max_iterations"]),
		"dp_regularization_pa": _decode(defaults["dp_regularization_pa"]),
		"jacobian_step_pa": _decode(defaults["jacobian_step_pa"]),
		"band_segments": int(defaults["band_segments"]),
		"max_damping_halvings": int(defaults["max_damping_halvings"]),
	}
	return SolverScript.new().solve_coupled_pressure(
		rooms, openings, sources, _decode(input["dt"]),
		_decode(input["reference_temp_c"]), options
	)


func _perturb_inputs(rooms: Dictionary, sources: Dictionary, variant: int) -> void:
	var room_keys: Array = rooms.keys()
	room_keys.sort()
	for index in range(room_keys.size()):
		var key: String = String(room_keys[index])
		var room: Dictionary = rooms[key]
		var phase: float = float((variant + 1) * (index + 3))
		var mass_factor: float = 1.0 + 1.0e-4 * sin(phase)
		var energy_factor: float = 1.0 + 1.0e-4 * cos(phase * 1.7)
		room["upper_gas_kg"] = maxf(
			1.0e-12, float(room["upper_gas_kg"]) * mass_factor
		)
		room["lower_gas_kg"] = maxf(
			1.0e-12, float(room["lower_gas_kg"]) / mass_factor
		)
		room["upper_energy_kj"] = float(room["upper_energy_kj"]) * energy_factor
		room["lower_energy_kj"] = float(room["lower_energy_kj"]) / energy_factor
		rooms[key] = room
		if sources.has(key):
			var source: Dictionary = sources[key]
			source["mass_kg"] = float(source["mass_kg"]) \
					+ 1.0e-6 * sin(phase * 0.7)
			source["energy_kj"] = float(source["energy_kj"]) \
					+ 1.0e-3 * cos(phase * 0.9)
			sources[key] = source


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
	for raw_key in source.keys():
		out[String(raw_key)] = _decode(source[raw_key])
	return out


func _assert(condition: bool, label: String) -> void:
	if not condition:
		push_error("FAIL: " + label)
		_failed = true

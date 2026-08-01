extends SceneTree

## H2.5m: what each committed capture now reports, so fixture assertions are
## written from measurement rather than assumption. Read-only.

const SolverScript = preload("res://sim/core/Phase3CoupledPressureSolver.gd")
const CAPTURES := [
	"res://tests/fixtures/data/coupled_solver_iteration_cap_after_rescue_corridor_chain.json",
	"res://tests/fixtures/data/coupled_solver_iteration_cap_corridor_chain.json",
	"res://tests/fixtures/data/coupled_solver_failure_corridor_chain.json",
	"res://tests/fixtures/data/coupled_solver_failure_r0_window_360.json",
]

const FIELDS := [
	"iterations", "normalized_residual",
	"cycle_detect_total", "cycle_detect_after_budget_total",
	"cycle_guard_attempt_total", "cycle_guard_accept_total",
	"post_budget_cycle_streak_max",
	"analytic_half_step_attempt_total", "analytic_half_step_accept_total",
	"analytic_half_step_last_initial_norm", "analytic_half_step_last_final_norm",
	"rescue_attempted", "rescue_accepted",
	"cycle_contraction_min", "cycle_contraction_max",
]


func _init() -> void:
	for raw_path in CAPTURES:
		var path: String = String(raw_path)
		var solved: Dictionary = _solve(path)
		print("--- %s" % path.get_file())
		print("    converged=%s limiting=%s" % [
			str(bool(solved.get("converged", false))),
			String(solved.get("limiting_reason", "?")),
		])
		for raw_field in FIELDS:
			var field: String = String(raw_field)
			print("    %-42s %s" % [field, str(solved.get(field, 0.0))])
	print("H25M_CAPTURE_DELTA_PASS")
	quit(0)


func _solve(path: String) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var capture: Dictionary = JSON.parse_string(file.get_as_text())
	file.close()
	var input: Dictionary = capture["input"]
	var rooms: Dictionary = {}
	for raw_key in input["rooms"].keys():
		rooms[String(raw_key)] = _number_dictionary(input["rooms"][raw_key])
	var sources: Dictionary = {}
	for raw_key in input["sources"].keys():
		sources[String(raw_key)] = _number_dictionary(input["sources"][raw_key])
	var openings: Array = []
	for raw_opening in input["openings"]:
		var o: Dictionary = raw_opening
		openings.append({
			"opening_id": int(o["opening_id"]),
			"room_a_id": int(o["room_a_id"]),
			"room_b_id": int(o["room_b_id"]),
			"bottom_m": _number(o, "bottom_m"),
			"top_m": _number(o, "top_m"),
			"width_m": _number(o, "width_m"),
			"open_fraction": _number(o, "open_fraction"),
			"discharge_coeff": _number(o, "discharge_coeff"),
		})
	var d: Dictionary = capture["solver_defaults"]
	var options: Dictionary = {
		"residual_tolerance": _number(d, "residual_tolerance"),
		"max_iterations": int(d["max_iterations"]),
		"dp_regularization_pa": _number(d, "dp_regularization_pa"),
		"jacobian_step_pa": _number(d, "jacobian_step_pa"),
		"band_segments": int(d["band_segments"]),
		"max_damping_halvings": int(d["max_damping_halvings"]),
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

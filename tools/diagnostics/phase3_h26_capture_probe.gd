extends SceneTree

## H2.6: replay an arbitrary capture at the shipped cap and at a raised cap,
## to separate "slow but converging" from "stalled". Read-only diagnostic;
## nothing here changes the shipped iteration cap.
##
## Usage: --headless --script this.gd -- <capture.json> [raised_cap]

const SolverScript = preload("res://sim/core/Phase3CoupledPressureSolver.gd")


func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("capture path required")
		quit(1)
		return
	var path: String = args[0]
	var raised: int = int(args[1]) if args.size() > 1 else 2000
	var capture: Dictionary = _load(path)
	if capture.is_empty():
		quit(1)
		return

	for cap in [24, raised]:
		var solved: Dictionary = _solve(capture, cap)
		var history: Array = solved.get("residual_history", [])
		var first: float = float(history[0]) if not history.is_empty() else NAN
		var last: float = float(history[history.size() - 1]) \
				if not history.is_empty() else NAN
		# Geometric rate over the whole run, as a per-iteration factor.
		var iterations: float = maxf(1.0, float(solved.get("iterations", 1.0)))
		var rate: float = pow(last / maxf(first, 1.0e-300), 1.0 / iterations) \
				if first > 0.0 and last > 0.0 else NAN
		var template: String = (
			"cap=%d converged=%s reason=%s iters=%d final=%s rate=%s "
			+ "half_att=%s half_acc=%s cycles=%s lm_acc=%s"
		)
		print(
			template % [
				cap, str(bool(solved.get("converged", false))),
				String(solved.get("limiting_reason", "?")),
				int(solved.get("iterations", 0.0)), str(last), str(rate),
				str(solved.get("analytic_half_step_attempt_total", 0.0)),
				str(solved.get("analytic_half_step_accept_total", 0.0)),
				str(solved.get("cycle_detect_total", 0.0)),
				str(solved.get("rescue_accepted", 0.0)),
			]
		)
	print("H26_CAPTURE_PROBE_PASS")
	quit(0)


func _solve(capture: Dictionary, cap: int) -> Dictionary:
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
		"max_iterations": cap,
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


func _load(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("capture missing: " + path)
		return {}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
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


func _number(source: Dictionary, key: String) -> float:
	return _decode(source[key])


func _number_dictionary(source: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for raw_key in source.keys():
		out[String(raw_key)] = _decode(source[raw_key])
	return out

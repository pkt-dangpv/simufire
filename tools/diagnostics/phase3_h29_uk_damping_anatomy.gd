extends SceneTree

## H2.9 offline anatomy for the exact uk_bungalow damping-exhausted capture.
## Read-only with respect to simulation state and sim/core. It reproduces the
## shipped Newton/line-search/LM loop while recording every trial that decides
## whether a step is accepted.

const SolverScript = preload("res://sim/core/Phase3CoupledPressureSolver.gd")
const CAPTURE_PATH := "res://tests/fixtures/data/coupled_solver_damping_exhausted_uk_bungalow.json"
const OUT_PATH := "res://runs/h29/uk_damping_anatomy.json"
const REPLAY_CAP := 64
const CAPTURE_PATHS := [
	"res://tests/fixtures/data/coupled_solver_damping_exhausted_uk_bungalow.json",
	"res://tests/fixtures/data/coupled_solver_failure_corridor_chain.json",
	"res://tests/fixtures/data/coupled_solver_failure_r0_window_360.json",
	"res://tests/fixtures/data/coupled_solver_iteration_cap_after_rescue_corridor_chain.json",
	"res://tests/fixtures/data/coupled_solver_iteration_cap_corridor_chain.json",
	"res://tests/fixtures/data/coupled_solver_iteration_cap_flashover_simple_house.json",
	"res://tests/fixtures/data/coupled_solver_iteration_cap_three_bed_apartment.json",
	"res://tests/fixtures/data/coupled_solver_iteration_cap_two_floor_stairwell.json",
	"res://tests/fixtures/data/coupled_solver_iteration_cap_two_storey_smoke.json",
]

var _solver = null
var _context: Dictionary = {}
var _room_count: int = 0


func _init() -> void:
	_solver = SolverScript.new()
	var capture: Dictionary = _load(CAPTURE_PATH)
	if capture.is_empty() or not _build(capture):
		quit(1)
		return
	var report: Dictionary = {
		"baseline": _trace_policy(1, 1.0),
		"lm_budget_2": _trace_policy(2, 1.0),
		"lm_budget_4": _trace_policy(4, 1.0),
		"forward_h_1e4": _trace_policy(1, 0.1),
		"forward_h_1e5": _trace_policy(1, 0.01),
		"forward_h_1e6": _trace_policy(1, 0.001),
		"branch_preserving_h_1e3": _trace_policy(1, 1.0, true),
		"capture_path": CAPTURE_PATH,
		"exact_capture_matrix": _exact_capture_matrix(),
		"neighbourhood_sweep": _neighbourhood_sweep(),
		"branch_preserving_capture_matrix": _branch_preserving_capture_matrix(),
		"branch_preserving_neighbourhood": _branch_preserving_neighbourhood(),
	}
	if Dictionary(report["exact_capture_matrix"]).size() != CAPTURE_PATHS.size():
		push_error("H2.9 capture matrix is incomplete")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://runs/h29"))
	var file: FileAccess = FileAccess.open(OUT_PATH, FileAccess.WRITE)
	if file == null:
		push_error("cannot write " + OUT_PATH)
		quit(1)
		return
	file.store_string(JSON.stringify(_json_safe(report), "  "))
	file.close()
	print("H29_UK_DAMPING_ANATOMY_WRITTEN " + OUT_PATH)
	print("H29_UK_DAMPING_ANATOMY_PASS")
	quit(0)


func _json_safe(value):
	match typeof(value):
		TYPE_FLOAT:
			return value if is_finite(float(value)) else null
		TYPE_ARRAY:
			var array_out: Array = []
			for item in value:
				array_out.append(_json_safe(item))
			return array_out
		TYPE_DICTIONARY:
			var dictionary_out: Dictionary = {}
			for raw_key in value.keys():
				dictionary_out[raw_key] = _json_safe(value[raw_key])
			return dictionary_out
		_:
			return value


func _exact_capture_matrix() -> Dictionary:
	var out: Dictionary = {}
	for raw_path in CAPTURE_PATHS:
		var path: String = String(raw_path)
		var capture: Dictionary = _load(path)
		var rows: Dictionary = {}
		var roots: Dictionary = {}
		for spec in [
			["baseline", 1.0], ["forward_h_1e4", 0.1],
			["forward_h_1e5", 0.01], ["forward_h_1e6", 0.001],
		]:
			var label: String = String(spec[0])
			var solved: Dictionary = _solve_capture(capture, float(spec[1]))
			rows[label] = {
				"converged": bool(solved.get("converged", false)),
				"iterations": int(solved.get("iterations", 0.0)),
				"limiting_reason": String(solved.get("limiting_reason", "")),
				"normalized_residual": float(solved["normalized_residual"]) \
						if solved.has("normalized_residual") else null,
				"lm_accepted": float(solved.get("rescue_accepted", 0.0)),
				"half_step_accepted": float(
					solved.get("analytic_half_step_accept_total", 0.0)
				),
			}
			if bool(solved.get("converged", false)):
				roots[label] = solved.get("gauge_pressure_by_room", {})
		rows["root_delta_vs_baseline_pa"] = _root_deltas(roots)
		out[path.get_file()] = rows
	return out


func _branch_preserving_capture_matrix() -> Dictionary:
	var out: Dictionary = {}
	for raw_path in CAPTURE_PATHS:
		var path: String = String(raw_path)
		var capture: Dictionary = _load(path)
		if not _build(capture):
			continue
		var baseline: Dictionary = _trace_policy(1, 1.0, false, 24)
		var candidate: Dictionary = _trace_policy(1, 1.0, true, 24)
		out[path.get_file()] = {
			"baseline": _policy_summary(baseline),
			"candidate": _policy_summary(candidate),
			"root_delta_pa": _array_delta(
				baseline.get("pressure", []), candidate.get("pressure", [])
			) if bool(baseline["converged"]) and bool(candidate["converged"]) \
			else null,
		}
	return out


func _branch_preserving_neighbourhood() -> Dictionary:
	var aggregate: Dictionary = _new_comparison_bucket()
	var per_capture: Dictionary = {}
	for raw_path in CAPTURE_PATHS:
		var path: String = String(raw_path)
		var capture: Dictionary = _load(path)
		var bucket: Dictionary = _new_comparison_bucket()
		for variant in range(21):
			if not _build_variant(capture, variant):
				continue
			var baseline: Dictionary = _trace_policy(1, 1.0, false, 24)
			var candidate: Dictionary = _trace_policy(1, 1.0, true, 24)
			_accumulate_policy_comparison(bucket, baseline, candidate)
			_accumulate_policy_comparison(aggregate, baseline, candidate)
			if not bool(candidate["converged"]):
				bucket["candidate_failures"].append({
					"variant": variant,
					"reason": String(candidate["limiting_reason"]),
					"iterations": int(candidate["iterations"]),
					"final_linf": float(candidate["final_linf"]),
				})
		per_capture[path.get_file()] = bucket
	return {
		"variants_per_capture": 21,
		"aggregate": aggregate,
		"per_capture": per_capture,
	}


func _new_comparison_bucket() -> Dictionary:
	return {
		"baseline_successes": 0,
		"candidate_successes": 0,
		"regressions": 0,
		"gains": 0,
		"shared_roots": 0,
		"max_shared_root_delta_pa": 0.0,
		"candidate_failures": [],
	}


func _accumulate_policy_comparison(
		bucket: Dictionary, baseline: Dictionary, candidate: Dictionary
	) -> void:
	var baseline_ok: bool = bool(baseline["converged"])
	var candidate_ok: bool = bool(candidate["converged"])
	if baseline_ok:
		bucket["baseline_successes"] += 1
	if candidate_ok:
		bucket["candidate_successes"] += 1
	if baseline_ok and not candidate_ok:
		bucket["regressions"] += 1
	if not baseline_ok and candidate_ok:
		bucket["gains"] += 1
	if baseline_ok and candidate_ok:
		bucket["shared_roots"] += 1
		bucket["max_shared_root_delta_pa"] = maxf(
			float(bucket["max_shared_root_delta_pa"]),
			_array_delta(baseline["pressure"], candidate["pressure"])
		)


func _policy_summary(result: Dictionary) -> Dictionary:
	return {
		"converged": bool(result["converged"]),
		"iterations": int(result["iterations"]),
		"limiting_reason": String(result["limiting_reason"]),
		"final_linf": float(result["final_linf"]),
		"rescue_budget_left": int(result["rescue_budget_left"]),
	}


func _array_delta(a: Array, b: Array) -> float:
	if a.size() != b.size():
		return INF
	var worst: float = 0.0
	for index in range(a.size()):
		worst = maxf(worst, absf(float(a[index]) - float(b[index])))
	return worst


func _neighbourhood_sweep() -> Dictionary:
	var policies: Array = [
		["forward_h_1e4", 0.1], ["forward_h_1e5", 0.01],
	]
	var aggregate: Dictionary = {}
	for raw_policy in policies:
		aggregate[String(raw_policy[0])] = {
			"baseline_successes": 0,
			"candidate_successes": 0,
			"regressions": 0,
			"gains": 0,
			"shared_roots": 0,
			"max_shared_root_delta_pa": 0.0,
		}
	var per_capture: Dictionary = {}
	for raw_path in CAPTURE_PATHS:
		var path: String = String(raw_path)
		var capture: Dictionary = _load(path)
		var per: Dictionary = {}
		for raw_policy in policies:
			var label: String = String(raw_policy[0])
			per[label] = {
				"baseline_successes": 0,
				"candidate_successes": 0,
				"regressions": 0,
				"gains": 0,
				"shared_roots": 0,
				"max_shared_root_delta_pa": 0.0,
			}
		for variant in range(21):
			var baseline: Dictionary = _solve_capture(capture, 1.0, variant)
			for raw_policy in policies:
				var label: String = String(raw_policy[0])
				var candidate: Dictionary = _solve_capture(
					capture, float(raw_policy[1]), variant
				)
				_accumulate_comparison(per[label], baseline, candidate)
				_accumulate_comparison(aggregate[label], baseline, candidate)
		per_capture[path.get_file()] = per
	return {
		"variants_per_capture": 21,
		"perturbation": "deterministic 1e-4 relative room state and small owner deltas",
		"aggregate": aggregate,
		"per_capture": per_capture,
	}


func _accumulate_comparison(
		bucket: Dictionary, baseline: Dictionary, candidate: Dictionary
	) -> void:
	var baseline_ok: bool = bool(baseline.get("converged", false))
	var candidate_ok: bool = bool(candidate.get("converged", false))
	if baseline_ok:
		bucket["baseline_successes"] += 1
	if candidate_ok:
		bucket["candidate_successes"] += 1
	if baseline_ok and not candidate_ok:
		bucket["regressions"] += 1
	if not baseline_ok and candidate_ok:
		bucket["gains"] += 1
	if baseline_ok and candidate_ok:
		bucket["shared_roots"] += 1
		var delta: float = _pressure_delta(
			baseline.get("gauge_pressure_by_room", {}),
			candidate.get("gauge_pressure_by_room", {})
		)
		bucket["max_shared_root_delta_pa"] = maxf(
			float(bucket["max_shared_root_delta_pa"]), delta
		)


func _pressure_delta(a: Dictionary, b: Dictionary) -> float:
	var worst: float = 0.0
	for raw_key in a.keys():
		var key: String = String(raw_key)
		worst = maxf(worst, absf(float(a[key]) - float(b[key])))
	return worst


func _solve_capture(
		capture: Dictionary, h_scale: float, variant: int = -1
	) -> Dictionary:
	var input: Dictionary = capture["input"]
	var rooms: Dictionary = {}
	for raw_key in input["rooms"].keys():
		rooms[String(raw_key)] = _number_dictionary(input["rooms"][raw_key])
	var sources: Dictionary = {}
	for raw_key in input["sources"].keys():
		sources[String(raw_key)] = _number_dictionary(input["sources"][raw_key])
	if variant >= 0:
		_perturb_inputs(rooms, sources, variant)
	var options: Dictionary = _options(capture)
	options["max_iterations"] = int(_number(
		capture["solver_defaults"], "max_iterations"
	))
	options["jacobian_step_pa"] = float(options["jacobian_step_pa"]) * h_scale
	return _solver.solve_coupled_pressure(
		rooms, _openings(input), sources, _number(input, "dt"),
		_number(input, "reference_temp_c"), options
	)


func _perturb_inputs(
		rooms: Dictionary, sources: Dictionary, variant: int
	) -> void:
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
		room["upper_energy_kj"] = float(room["upper_energy_kj"]) \
				* energy_factor
		room["lower_energy_kj"] = float(room["lower_energy_kj"]) \
				/ energy_factor
		rooms[key] = room
		if sources.has(key):
			var source: Dictionary = sources[key]
			source["mass_kg"] = float(source["mass_kg"]) \
					+ 1.0e-6 * sin(phase * 0.7)
			source["energy_kj"] = float(source["energy_kj"]) \
					+ 1.0e-3 * cos(phase * 0.9)
			sources[key] = source


func _root_deltas(roots: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	if not roots.has("baseline"):
		return out
	var baseline: Dictionary = roots["baseline"]
	for raw_label in roots.keys():
		var label: String = String(raw_label)
		if label == "baseline":
			continue
		var candidate: Dictionary = roots[label]
		var worst: float = 0.0
		for raw_key in baseline.keys():
			var key: String = String(raw_key)
			worst = maxf(
				worst, absf(float(baseline[key]) - float(candidate[key]))
			)
		out[label] = worst
	return out


func _trace_policy(
		initial_rescue_budget: int, jacobian_h_scale: float,
		branch_preserving: bool = false, iteration_cap: int = REPLAY_CAP
	) -> Dictionary:
	var pressure: Array[float] = _seed()
	var evaluation: Dictionary = _solver._evaluate(_context, pressure)
	var norm: float = float(evaluation["normalized_residual"])
	var tolerance: float = float(_context["residual_tolerance"])
	var max_halvings: int = int(_context["max_damping_halvings"])
	var h: float = float(_context["jacobian_step_pa"]) * jacobian_h_scale
	var rescue_budget: int = initial_rescue_budget
	var trace: Array = []
	var iterations: int = 0
	var reason: String = "converged"
	var previous_full_step: Array = []
	var previous_gain: float = INF

	while norm > tolerance and iterations < iteration_cap:
		iterations += 1
		var jacobian: Array = _jacobian_branch_preserving(
			pressure, evaluation, h
		) if branch_preserving else _jacobian(pressure, evaluation, h)
		if jacobian.is_empty():
			reason = "singular_jacobian"
			break
		var step: Array = _newton_step(jacobian, evaluation)
		if step.is_empty():
			reason = "singular_jacobian"
			break
		var row: Dictionary = {
			"iteration": iterations,
			"norm_before": norm,
			"l2_before": _solver._rescue_merit(evaluation),
			"dominant_before": _dominant(evaluation),
			"residual_before": evaluation["residual"],
			"per_room_normalized_before": evaluation["per_room_normalized"],
			"step": step,
			"step_norm": _vector_norm(step),
			"jacobian_condition_inf": _condition_inf(jacobian),
			"newton_l2_directional_derivative": _l2_directional_derivative(
				evaluation, jacobian, step
			),
			"branch_before": _branch_signature(evaluation),
			"line_trials": [],
			"lm_trials": [],
			"rescue_budget_before": rescue_budget,
		}
		var damping: float = 1.0
		var accepted: bool = false
		var candidate_pressure: Array[float] = pressure.duplicate()
		var candidate_evaluation: Dictionary = evaluation
		for halving in range(max_halvings + 1):
			var trial_pressure: Array[float] = _shift(pressure, step, damping)
			var trial_evaluation: Dictionary = _solver._evaluate(
				_context, trial_pressure
			)
			var valid: bool = bool(trial_evaluation.get("valid", false))
			var trial_norm: float = float(
				trial_evaluation.get("normalized_residual", INF)
			)
			row["line_trials"].append({
				"halving": halving,
				"damping": damping,
				"valid": valid,
				"linf": trial_norm,
				"l2": _solver._rescue_merit(trial_evaluation) if valid else INF,
				"dominant": _dominant(trial_evaluation) if valid else {},
				"branch": _branch_signature(trial_evaluation) if valid else [],
			})
			if valid and trial_norm < norm:
				accepted = true
				candidate_pressure = trial_pressure
				candidate_evaluation = trial_evaluation
				break
			damping *= 0.5

		if not accepted:
			if rescue_budget <= 0:
				row["failure_probe"] = _failure_probe(
						pressure, evaluation, h
				)
			var lm: Dictionary = _trace_lm(
				pressure, evaluation, jacobian, rescue_budget
			)
			row["path"] = "lm_rescue"
			row["lm_trials"] = lm["trials"]
			row["lm_accepted"] = lm["accepted"]
			trace.append(row)
			if not bool(lm["accepted"]):
				reason = "damping_exhausted"
				break
			rescue_budget -= 1
			pressure = lm["pressure"]
			evaluation = lm["evaluation"]
			norm = float(evaluation["normalized_residual"])
			previous_full_step = []
			previous_gain = INF
			continue

		var gain: float = _solver._model_gain_ratio(
			_context, evaluation, candidate_evaluation, jacobian, step, damping
		)
		var cycle_detected: bool = false
		if damping == 1.0 and not previous_full_step.is_empty():
			cycle_detected = minf(previous_gain, gain) < 0.05 \
					and _solver._step_cosine(previous_full_step, step) < -0.99
		if cycle_detected:
			var half_pressure: Array[float] = _shift(pressure, step, 0.5)
			var half_evaluation: Dictionary = _solver._evaluate(
				_context, half_pressure
			)
			if bool(half_evaluation.get("valid", false)) \
					and float(half_evaluation["normalized_residual"]) < norm:
				row["path"] = "analytic_half_step"
				trace.append(row)
				pressure = half_pressure
				evaluation = half_evaluation
				norm = float(evaluation["normalized_residual"])
				previous_full_step = []
				previous_gain = INF
				continue
		if cycle_detected and rescue_budget > 0:
			var cycle_lm: Dictionary = _trace_lm(
				pressure, evaluation, jacobian, rescue_budget
			)
			if bool(cycle_lm["accepted"]):
				row["path"] = "cycle_lm"
				trace.append(row)
				rescue_budget -= 1
				pressure = cycle_lm["pressure"]
				evaluation = cycle_lm["evaluation"]
				norm = float(evaluation["normalized_residual"])
				previous_full_step = []
				previous_gain = INF
				continue

		row["path"] = "newton"
		row["accepted_damping"] = damping
		row["norm_after"] = float(candidate_evaluation["normalized_residual"])
		row["l2_after"] = _solver._rescue_merit(candidate_evaluation)
		row["dominant_after"] = _dominant(candidate_evaluation)
		trace.append(row)
		if damping == 1.0:
			previous_full_step = step.duplicate()
			previous_gain = gain
		else:
			previous_full_step = []
			previous_gain = INF
		pressure = candidate_pressure
		evaluation = candidate_evaluation
		norm = float(evaluation["normalized_residual"])

	if norm > tolerance and reason == "converged":
		reason = "iteration_cap"
	return {
		"converged": norm <= tolerance,
		"limiting_reason": reason,
		"iterations": iterations,
		"final_linf": norm,
		"final_l2": _solver._rescue_merit(evaluation),
		"rescue_budget_left": rescue_budget,
		"pressure": pressure,
		"trace": trace,
	}


func _failure_probe(
		pressure: Array[float], evaluation: Dictionary, default_h: float
	) -> Dictionary:
	var out: Dictionary = {
		"forced_lm": {},
		"jacobian_variants": [],
		"column_branch_distances_pa": _column_branch_distances(pressure),
	}
	var baseline_jacobian: Array = _jacobian_mode(
		pressure, evaluation, default_h, "forward"
	)
	out["forced_lm"] = _trace_lm(
		pressure, evaluation, baseline_jacobian, 1
	)
	for spec in [
		["forward", 1.0e-2], ["forward", 1.0e-3],
		["forward", 1.0e-4], ["forward", 1.0e-5],
		["forward", 1.0e-6], ["backward", 1.0e-3],
		["central", 1.0e-3], ["central", 1.0e-4],
		["central", 1.0e-5],
	]:
		var mode: String = String(spec[0])
		var h: float = float(spec[1])
		var jacobian: Array = _jacobian_mode(pressure, evaluation, h, mode)
		var item: Dictionary = {
			"mode": mode,
			"h": h,
			"valid": not jacobian.is_empty(),
		}
		if not jacobian.is_empty():
			var step: Array = _newton_step(jacobian, evaluation)
			item["condition_inf"] = _condition_inf(jacobian)
			item["step_norm"] = _vector_norm(step)
			item["best_trial"] = _best_line_trial(
				pressure, evaluation, step
			)
			item["fd_branch_crossings"] = _fd_branch_crossings(
				pressure, h, mode
			)
		out["jacobian_variants"].append(item)
	return out


func _column_branch_distances(pressure: Array[float]) -> Array:
	var out: Array = []
	for column in range(_room_count):
		var closest: float = INF
		var closest_opening: int = -1
		for raw_opening in _context["openings"]:
			var opening: Dictionary = raw_opening
			if int(opening["index_a"]) != column \
					and int(opening["index_b"]) != column:
				continue
			var a: int = int(opening["index_a"])
			var b: int = int(opening["index_b"])
			var delta: float = (float(pressure[a]) if a >= 0 else 0.0) \
					- (float(pressure[b]) if b >= 0 else 0.0)
			for raw_band in opening["bands"]:
				var band: Dictionary = raw_band
				for dp in [
					delta + float(band["hydrostatic_z0_pa"]),
					delta + float(band["hydrostatic_z1_pa"]),
				]:
					if absf(float(dp)) < closest:
						closest = absf(float(dp))
						closest_opening = int(opening["opening_id"])
		out.append({
			"column": column,
			"distance_pa": closest,
			"opening_id": closest_opening,
		})
	return out


func _best_line_trial(
		pressure: Array[float], evaluation: Dictionary, step: Array
	) -> Dictionary:
	var base_linf: float = float(evaluation["normalized_residual"])
	var base_l2: float = _solver._rescue_merit(evaluation)
	var best: Dictionary = {
		"linf_ratio": INF,
		"l2_ratio": INF,
		"damping": 0.0,
		"strict_linf_decrease": false,
		"strict_l2_decrease": false,
	}
	var damping: float = 1.0
	for _halving in range(int(_context["max_damping_halvings"]) + 1):
		var trial: Dictionary = _solver._evaluate(
			_context, _shift(pressure, step, damping)
		)
		if bool(trial.get("valid", false)):
			var linf_ratio: float = float(trial["normalized_residual"]) / base_linf
			var l2_ratio: float = _solver._rescue_merit(trial) / base_l2
			if linf_ratio < float(best["linf_ratio"]):
				best["linf_ratio"] = linf_ratio
				best["damping"] = damping
			best["l2_ratio"] = minf(float(best["l2_ratio"]), l2_ratio)
		damping *= 0.5
	best["strict_linf_decrease"] = float(best["linf_ratio"]) < 1.0
	best["strict_l2_decrease"] = float(best["l2_ratio"]) < 1.0
	return best


func _fd_branch_crossings(
		pressure: Array[float], h: float, mode: String
	) -> Array:
	var base: Dictionary = _solver._evaluate(_context, pressure)
	var base_connections: Array = base["connections"]
	var out: Array = []
	for column in range(_room_count):
		for direction in ([1.0, -1.0] if mode == "central" else [-1.0] if mode == "backward" else [1.0]):
			var shifted: Array[float] = pressure.duplicate()
			shifted[column] += direction * h
			var probe: Dictionary = _solver._evaluate(_context, shifted)
			if not bool(probe.get("valid", false)):
				continue
			for index in range(base_connections.size()):
				var before_dp: float = float(base_connections[index]["delta_p_pa"])
				var after_dp: float = float(probe["connections"][index]["delta_p_pa"])
				if signf(before_dp) != signf(after_dp):
					out.append({
						"column": column,
						"direction": direction,
						"opening_id": int(base_connections[index]["opening_id"]),
						"dp_before": before_dp,
						"dp_after": after_dp,
					})
	return out


func _trace_lm(
		pressure: Array, evaluation: Dictionary, jacobian: Array, budget: int
	) -> Dictionary:
	var out: Dictionary = {"accepted": false, "trials": []}
	if budget <= 0:
		out["budget_exhausted"] = true
		return out
	var merit_before: float = _solver._rescue_merit(evaluation)
	var jacobian_scale: float = 0.0
	for row in range(_room_count):
		for column in range(_room_count):
			jacobian_scale = maxf(jacobian_scale, absf(float(jacobian[row][column])))
	if jacobian_scale <= 0.0:
		jacobian_scale = 1.0
	var rhs: Array[float] = []
	for value in evaluation["residual"]:
		rhs.append(-float(value))
	for lambda_value in [1.0e-3, 1.0e-2, 1.0e-1, 1.0, 1.0e1]:
		var damped: Array = _copy_matrix(jacobian)
		for index in range(_room_count):
			damped[index][index] = float(damped[index][index]) \
					+ float(lambda_value) * jacobian_scale
		var direction: Array = _solver._solve_linear_system(damped, rhs)
		if direction.is_empty():
			continue
		var scale: float = 1.0
		for halving in range(int(_context["max_damping_halvings"]) + 1):
			var trial_pressure: Array[float] = _shift(pressure, direction, scale)
			var trial_evaluation: Dictionary = _solver._evaluate(
				_context, trial_pressure
			)
			var valid: bool = bool(trial_evaluation.get("valid", false))
			var merit_after: float = _solver._rescue_merit(trial_evaluation) \
					if valid else INF
			var armijo_limit: float = (1.0 - 1.0e-4 * scale) * merit_before
			out["trials"].append({
				"lambda": lambda_value,
				"halving": halving,
				"scale": scale,
				"valid": valid,
				"linf": float(trial_evaluation.get("normalized_residual", INF)),
				"l2": merit_after,
				"armijo_limit": armijo_limit,
				"l2_accept": valid and merit_after <= armijo_limit,
				"dominant": _dominant(trial_evaluation) if valid else {},
				"branch": _branch_signature(trial_evaluation) if valid else [],
			})
			if valid and merit_after <= armijo_limit:
				out["accepted"] = true
				out["pressure"] = trial_pressure
				out["evaluation"] = trial_evaluation
				out["lambda"] = lambda_value
				out["scale"] = scale
				return out
			scale *= 0.5
	return out


func _dominant(evaluation: Dictionary) -> Dictionary:
	if not bool(evaluation.get("valid", false)):
		return {}
	var best_key: String = ""
	var best_value: float = -INF
	for raw_key in evaluation["per_room_normalized"].keys():
		var key: String = String(raw_key)
		var value: float = float(evaluation["per_room_normalized"][key])
		if value > best_value:
			best_key = key
			best_value = value
	return {"room": best_key, "value": best_value}


func _branch_signature(evaluation: Dictionary) -> Array:
	if not bool(evaluation.get("valid", false)):
		return []
	var out: Array = []
	for raw_connection in evaluation["connections"]:
		var connection: Dictionary = raw_connection
		var neutral_m: float = float(connection["neutral_plane_m"])
		out.append({
			"opening_id": int(connection["opening_id"]),
			"dp": float(connection["delta_p_pa"]),
			"neutral_inside": bool(connection["neutral_plane_inside"]),
			"neutral_m": neutral_m if is_finite(neutral_m) else null,
			"regularization": float(connection["regularization_active_count"]),
		})
	return out


func _l2_directional_derivative(
		evaluation: Dictionary, jacobian: Array, step: Array
	) -> float:
	var room_keys: Array = _context["room_keys"]
	var rooms: Dictionary = _context["rooms"]
	var gas_constant: float = float(_context["gas_constant"])
	var reference_temp_k: float = float(_context["reference_temp_k"])
	var gradient_dot_step: float = 0.0
	for row in range(_room_count):
		var key: String = String(room_keys[row])
		var room: Dictionary = rooms[key]
		var pressure_per_kg: float = gas_constant * reference_temp_k \
				/ float(room["volume_m3"])
		var scale: float = pressure_per_kg \
				* maxf(1.0e-12, float(room["mass_kg"]))
		var normalized_signed: float = float(evaluation["residual"][row]) / scale
		var directional: float = 0.0
		for column in range(_room_count):
			directional += float(jacobian[row][column]) * float(step[column]) / scale
		gradient_dot_step += normalized_signed * directional
	return gradient_dot_step


func _jacobian(pressure: Array[float], evaluation: Dictionary, h: float) -> Array:
	return _jacobian_mode(pressure, evaluation, h, "forward")


func _jacobian_branch_preserving(
		pressure: Array[float], evaluation: Dictionary, h: float
	) -> Array:
	var jacobian: Array = []
	for row in range(_room_count):
		var values: Array[float] = []
		values.resize(_room_count)
		jacobian.append(values)
	for column in range(_room_count):
		var forward_pressure: Array[float] = pressure.duplicate()
		var backward_pressure: Array[float] = pressure.duplicate()
		forward_pressure[column] += h
		backward_pressure[column] -= h
		var forward: Dictionary = _solver._evaluate(_context, forward_pressure)
		var backward: Dictionary = _solver._evaluate(_context, backward_pressure)
		if not bool(forward.get("valid", false)) \
				or not bool(backward.get("valid", false)):
			return []
		var use_backward: bool = _branch_change_score(evaluation, backward) \
				< _branch_change_score(evaluation, forward)
		for row in range(_room_count):
			jacobian[row][column] = (
				(float(evaluation["residual"][row])
				- float(backward["residual"][row])) / h
			) if use_backward else (
				(float(forward["residual"][row])
				- float(evaluation["residual"][row])) / h
			)
	return jacobian


func _branch_change_score(base: Dictionary, probe: Dictionary) -> int:
	var score: int = 0
	var base_connections: Array = base["connections"]
	var probe_connections: Array = probe["connections"]
	for index in range(base_connections.size()):
		var a: Dictionary = base_connections[index]
		var b: Dictionary = probe_connections[index]
		if signf(float(a["delta_p_pa"])) != signf(float(b["delta_p_pa"])):
			score += 8
		if bool(a["neutral_plane_inside"]) != bool(b["neutral_plane_inside"]):
			score += 4
		if (float(a["a_to_b_kg"]) > 0.0) != (float(b["a_to_b_kg"]) > 0.0):
			score += 2
		if (float(a["b_to_a_kg"]) > 0.0) != (float(b["b_to_a_kg"]) > 0.0):
			score += 2
		if float(a["regularization_active_count"]) \
				!= float(b["regularization_active_count"]):
			score += 1
	return score


func _jacobian_mode(
		pressure: Array[float], evaluation: Dictionary, h: float, mode: String
	) -> Array:
	var jacobian: Array = []
	for row in range(_room_count):
		var values: Array[float] = []
		values.resize(_room_count)
		jacobian.append(values)
	for column in range(_room_count):
		var forward_pressure: Array[float] = pressure.duplicate()
		forward_pressure[column] += h
		var forward: Dictionary = _solver._evaluate(_context, forward_pressure)
		var backward: Dictionary = {}
		if mode == "backward" or mode == "central":
			var backward_pressure: Array[float] = pressure.duplicate()
			backward_pressure[column] -= h
			backward = _solver._evaluate(_context, backward_pressure)
		if not bool(forward.get("valid", false)) \
				or ((mode == "backward" or mode == "central") \
				and not bool(backward.get("valid", false))):
			return []
		for row in range(_room_count):
			if mode == "central":
				jacobian[row][column] = (
					float(forward["residual"][row])
					- float(backward["residual"][row])
				) / (2.0 * h)
			elif mode == "backward":
				jacobian[row][column] = (
					float(evaluation["residual"][row])
					- float(backward["residual"][row])
				) / h
			else:
				jacobian[row][column] = (
					float(forward["residual"][row])
					- float(evaluation["residual"][row])
				) / h
	return jacobian


func _newton_step(jacobian: Array, evaluation: Dictionary) -> Array:
	var rhs: Array[float] = []
	for value in evaluation["residual"]:
		rhs.append(-float(value))
	return _solver._solve_linear_system(jacobian, rhs)


func _condition_inf(matrix: Array) -> float:
	var matrix_norm: float = _matrix_norm_inf(matrix)
	var inverse: Array = []
	for row in range(_room_count):
		var values: Array[float] = []
		values.resize(_room_count)
		inverse.append(values)
	for column in range(_room_count):
		var rhs: Array[float] = []
		for row in range(_room_count):
			rhs.append(1.0 if row == column else 0.0)
		var solution: Array = _solver._solve_linear_system(matrix, rhs)
		if solution.is_empty():
			return INF
		for row in range(_room_count):
			inverse[row][column] = float(solution[row])
	return matrix_norm * _matrix_norm_inf(inverse)


func _matrix_norm_inf(matrix: Array) -> float:
	var worst: float = 0.0
	for raw_row in matrix:
		var total: float = 0.0
		for value in raw_row:
			total += absf(float(value))
		worst = maxf(worst, total)
	return worst


func _vector_norm(vector: Array) -> float:
	var total: float = 0.0
	for value in vector:
		total += float(value) * float(value)
	return sqrt(total)


func _copy_matrix(matrix: Array) -> Array:
	var out: Array = []
	for raw_row in matrix:
		out.append(Array(raw_row).duplicate())
	return out


func _shift(base: Array, direction: Array, scale: float) -> Array[float]:
	var out: Array[float] = []
	for index in range(base.size()):
		out.append(float(base[index]) + scale * float(direction[index]))
	return out


func _seed() -> Array[float]:
	var out: Array[float] = []
	for room_key in _context["room_keys"]:
		out.append(float(_context["rooms"][room_key]["gauge_pressure_pa"]))
	return out


func _build(capture: Dictionary) -> bool:
	var input: Dictionary = capture["input"]
	var rooms: Dictionary = {}
	for raw_key in input["rooms"].keys():
		rooms[String(raw_key)] = _number_dictionary(input["rooms"][raw_key])
	var sources: Dictionary = {}
	for raw_key in input["sources"].keys():
		sources[String(raw_key)] = _number_dictionary(input["sources"][raw_key])
	var options: Dictionary = _options(capture)
	_context = _solver._build_context(
		rooms, _openings(input), sources, _number(input, "dt"),
		_number(input, "reference_temp_c"), options
	)
	_room_count = int(_context.get("room_keys", []).size())
	return bool(_context.get("valid", false))


func _build_variant(capture: Dictionary, variant: int) -> bool:
	var input: Dictionary = capture["input"]
	var rooms: Dictionary = {}
	for raw_key in input["rooms"].keys():
		rooms[String(raw_key)] = _number_dictionary(input["rooms"][raw_key])
	var sources: Dictionary = {}
	for raw_key in input["sources"].keys():
		sources[String(raw_key)] = _number_dictionary(input["sources"][raw_key])
	_perturb_inputs(rooms, sources, variant)
	var options: Dictionary = _options(capture)
	options["max_iterations"] = 24
	_context = _solver._build_context(
		rooms, _openings(input), sources, _number(input, "dt"),
		_number(input, "reference_temp_c"), options
	)
	_room_count = int(_context.get("room_keys", []).size())
	return bool(_context.get("valid", false))


func _openings(input: Dictionary) -> Array:
	var out: Array = []
	for raw_opening in input["openings"]:
		var opening: Dictionary = raw_opening
		out.append({
			"opening_id": int(opening["opening_id"]),
			"room_a_id": int(opening["room_a_id"]),
			"room_b_id": int(opening["room_b_id"]),
			"bottom_m": _number(opening, "bottom_m"),
			"top_m": _number(opening, "top_m"),
			"width_m": _number(opening, "width_m"),
			"open_fraction": _number(opening, "open_fraction"),
			"discharge_coeff": _number(opening, "discharge_coeff"),
		})
	return out


func _options(capture: Dictionary) -> Dictionary:
	var defaults: Dictionary = capture["solver_defaults"]
	return {
		"residual_tolerance": _number(defaults, "residual_tolerance"),
		"max_iterations": REPLAY_CAP,
		"dp_regularization_pa": _number(defaults, "dp_regularization_pa"),
		"jacobian_step_pa": _number(defaults, "jacobian_step_pa"),
		"band_segments": int(defaults["band_segments"]),
		"max_damping_halvings": int(defaults["max_damping_halvings"]),
	}


func _load(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("missing capture: " + path)
		return {}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


func _decode(leaf) -> float:
	if typeof(leaf) == TYPE_DICTIONARY and leaf.has("x"):
		var hex: String = String(leaf["x"])
		var bytes: PackedByteArray = PackedByteArray()
		for index in range(0, hex.length(), 2):
			bytes.append(hex.substr(index, 2).hex_to_int())
		if bytes.size() == 8:
			return bytes.decode_double(0)
		return float(String(leaf["d"]))
	return float(leaf)


func _number(source: Dictionary, key: String) -> float:
	return _decode(source[key])


func _number_dictionary(source: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for raw_key in source.keys():
		out[String(raw_key)] = _decode(source[raw_key])
	return out

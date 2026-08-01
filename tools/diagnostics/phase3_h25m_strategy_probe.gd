extends SceneTree

## H2.5m STRATEGY PROBE - offline, read-only, no runtime authority.
##
## The H2.5m trace established that the post-budget period-2 cycle is the exact
## fixed-point structure of Newton applied to a residual that is homogeneous of
## degree 1/2 along the step direction (`|F| ~ |u|^0.5007`, R^2 = 0.9999) - the
## orifice law `sqrt(2 rho dp)`. For `F(u) = C sign(u) |u|^(1/2)` the Newton map
## is exactly `u -> -u`, and damped Newton with factor `theta` gives
## `u -> (1 - 2 theta) u`. So `theta = 1/2` annihilates the cycle analytically
## and `theta = 1` reproduces it exactly. Nothing here is fitted to a scenario.
##
## This probe replays every committed capture under candidate strategies and
## reports iterations-to-convergence and final residual. It selects nothing and
## changes nothing; `sim/core` is imported, never modified.

const SolverScript = preload("res://sim/core/Phase3CoupledPressureSolver.gd")
const OUT_PATH := "res://runs/h25m_strategy_probe.json"

const CAPTURES := [
	"res://tests/fixtures/data/coupled_solver_iteration_cap_after_rescue_corridor_chain.json",
	"res://tests/fixtures/data/coupled_solver_iteration_cap_corridor_chain.json",
	"res://tests/fixtures/data/coupled_solver_failure_corridor_chain.json",
	"res://tests/fixtures/data/coupled_solver_failure_r0_window_360.json",
]

## S0 baseline; S1 analytic half step on cycle; S2 half step with no LM at all.
const STRATEGIES := ["s0_baseline", "s1_cycle_half_step", "s2_half_step_only"]

const CYCLE_MIN_GAIN := 0.05
const CYCLE_MAX_COSINE := -0.99
const PROBE_CAP := 400

var _solver = null
var _context: Dictionary = {}
var _room_count: int = 0


func _init() -> void:
	_solver = SolverScript.new()
	var report: Dictionary = {}
	for raw_path in CAPTURES:
		var path: String = String(raw_path)
		var capture: Dictionary = _load(path)
		if capture.is_empty():
			continue
		if not bool(_build(capture).get("ok", false)):
			continue
		var per_capture: Dictionary = {}
		for raw_strategy in STRATEGIES:
			var strategy: String = String(raw_strategy)
			per_capture[strategy] = _run(strategy, PROBE_CAP)
			# Shipped cap, which is what actually matters for a decision.
			var capped: Dictionary = _run(strategy, 24)
			per_capture[strategy]["at_shipped_cap_24"] = {
				"converged": bool(capped["converged"]),
				"iterations": int(capped["iterations"]),
				"final_norm": float(capped["final_norm"]),
				"limiting_reason": String(capped["limiting_reason"]),
			}
		report[path.get_file()] = per_capture
	var file: FileAccess = FileAccess.open(OUT_PATH, FileAccess.WRITE)
	if file == null:
		push_error("cannot write " + OUT_PATH)
		quit(1)
		return
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	print("H25M_STRATEGY_PROBE_WRITTEN %s" % OUT_PATH)
	print("H25M_STRATEGY_PROBE_PASS")
	quit(0)


## One full solve under the named strategy. The Newton/L-infinity core, the
## tolerance, the Jacobian and the cap are the shipped ones in every case; only
## the response to a detected period-2 cycle differs.
func _run(strategy: String, cap: int) -> Dictionary:
	var pressure: Array[float] = _seed()
	var evaluation: Dictionary = _solver._evaluate(_context, pressure)
	var norm: float = float(evaluation["normalized_residual"])
	var tolerance: float = float(_context["residual_tolerance"])
	var max_halvings: int = int(_context["max_damping_halvings"])
	var h: float = float(_context["jacobian_step_pa"])
	var use_lm: bool = strategy != "s2_half_step_only"
	var use_half: bool = strategy != "s0_baseline"
	var rescue_budget: int = 1
	var prev_step: Array = []
	var prev_gain: float = INF
	var iterations: int = 0
	var converged: bool = norm <= tolerance
	var half_steps: int = 0
	var lm_accepted: int = 0
	var evaluations: int = 1
	var reason: String = "converged"

	while not converged and iterations < cap:
		iterations += 1
		var jacobian: Array = _jacobian(pressure, evaluation, h)
		evaluations += _room_count
		if jacobian.is_empty():
			reason = "non_finite_state"
			break
		var step: Array = _newton_step(jacobian, evaluation)
		if step.is_empty():
			reason = "singular_jacobian"
			break

		var damping: float = 1.0
		var halvings: int = 0
		var accepted: bool = false
		var cand_p: Array[float] = pressure.duplicate()
		var cand_e: Dictionary = evaluation
		while halvings <= max_halvings:
			var trial: Array[float] = _shift(pressure, step, damping)
			var trial_e: Dictionary = _solver._evaluate(_context, trial)
			evaluations += 1
			if bool(trial_e.get("valid", false)) \
					and float(trial_e["normalized_residual"]) < norm:
				cand_p = trial
				cand_e = trial_e
				accepted = true
				break
			damping *= 0.5
			halvings += 1

		if not accepted:
			if not use_lm:
				reason = "damping_exhausted"
				break
			var rescue: Dictionary = _solver._try_lm_rescue(
				_context, pressure, evaluation, jacobian,
				_room_count, max_halvings, rescue_budget
			)
			evaluations += int(rescue.get("trials", 0.0))
			if not bool(rescue.get("accepted", false)):
				reason = "damping_exhausted"
				break
			rescue_budget -= 1
			lm_accepted += 1
			pressure = rescue["pressure"]
			evaluation = rescue["evaluation"]
			norm = float(evaluation["normalized_residual"])
			prev_step = []
			prev_gain = INF
			converged = norm <= tolerance
			continue

		var gain: float = float(_solver._model_gain_ratio(
			_context, evaluation, cand_e, jacobian, step, damping
		))
		var cycle: bool = false
		if damping == 1.0 and not prev_step.is_empty():
			cycle = (
				prev_gain < CYCLE_MIN_GAIN
				and gain < CYCLE_MIN_GAIN
				and float(_solver._step_cosine(prev_step, step)) < CYCLE_MAX_COSINE
			)

		if cycle and use_half:
			# Analytic annihilator for a degree-1/2 residual: theta = 1/2 maps
			# the period-2 multiplier from -1 to 0. No budget, no threshold.
			var half_p: Array[float] = _shift(pressure, step, 0.5)
			var half_e: Dictionary = _solver._evaluate(_context, half_p)
			evaluations += 1
			if bool(half_e.get("valid", false)) \
					and float(half_e["normalized_residual"]) < norm:
				half_steps += 1
				pressure = half_p
				evaluation = half_e
				norm = float(evaluation["normalized_residual"])
				prev_step = []
				prev_gain = INF
				converged = norm <= tolerance
				continue

		if cycle and use_lm and rescue_budget > 0:
			var cyc: Dictionary = _solver._try_lm_rescue(
				_context, pressure, evaluation, jacobian,
				_room_count, max_halvings, rescue_budget
			)
			evaluations += int(cyc.get("trials", 0.0))
			if bool(cyc.get("accepted", false)):
				rescue_budget -= 1
				lm_accepted += 1
				pressure = cyc["pressure"]
				evaluation = cyc["evaluation"]
				norm = float(evaluation["normalized_residual"])
				prev_step = []
				prev_gain = INF
				converged = norm <= tolerance
				continue

		if damping == 1.0:
			prev_step = step.duplicate()
			prev_gain = gain
		else:
			prev_step = []
			prev_gain = INF
		pressure = cand_p
		evaluation = cand_e
		norm = float(evaluation["normalized_residual"])
		converged = norm <= tolerance

	if not converged and reason == "converged":
		reason = "iteration_cap"
	return {
		"strategy": strategy,
		"cap": cap,
		"converged": converged,
		"iterations": iterations,
		"final_norm": norm,
		"limiting_reason": reason,
		"half_steps_taken": half_steps,
		"lm_rescues_accepted": lm_accepted,
		"residual_evaluations": evaluations,
	}


func _jacobian(pressure: Array[float], evaluation: Dictionary, h: float) -> Array:
	var j: Array = []
	for row in range(_room_count):
		var r: Array[float] = []
		r.resize(_room_count)
		j.append(r)
	for column in range(_room_count):
		var perturbed: Array[float] = pressure.duplicate()
		perturbed[column] = perturbed[column] + h
		var forward: Dictionary = _solver._evaluate(_context, perturbed)
		if not bool(forward.get("valid", false)):
			return []
		for row in range(_room_count):
			j[row][column] = (
				float(forward["residual"][row]) - float(evaluation["residual"][row])
			) / h
	return j


func _newton_step(jacobian: Array, evaluation: Dictionary) -> Array:
	var rhs: Array[float] = []
	for row in range(_room_count):
		rhs.append(-float(evaluation["residual"][row]))
	return _solver._solve_linear_system(jacobian, rhs)


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


func _build(capture: Dictionary) -> Dictionary:
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
	_context = _solver._build_context(
		rooms, openings, sources,
		_number(input, "dt"), _number(input, "reference_temp_c"), options
	)
	if not bool(_context.get("valid", false)):
		return {"ok": false}
	_room_count = int(_context["room_keys"].size())
	return {"ok": true}


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

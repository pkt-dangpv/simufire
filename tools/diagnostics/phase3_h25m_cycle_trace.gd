extends SceneTree

## H2.5m DIAGNOSTIC HARNESS - offline, read-only, no runtime authority.
##
## Replays the captured late corridor solve using the committed solver's OWN
## primitives (`_build_context`, `_evaluate`, `_solve_linear_system`,
## `_rescue_merit`, `_linear_model_merit`) and instruments every iteration.
## `sim/core` is imported, never modified.
##
## It answers four questions that the passive CSV telemetry cannot:
##
##   E1  what does the merit look like ALONG the cycle direction?
##       (does the period-2 pair bracket a root -> extrapolation viable)
##   E2  is the one-sided Jacobian the culprit?
##       (central difference at the same point -> does the gain ratio recover)
##   E3  is the residual smooth at the differencing scale?
##       (sweep h over decades -> does the Newton direction stay put)
##   E4  what is actually chattering?
##       (per-connection dp sign + regularization census per iteration)
##
## Plus E5: replay with a raised cap OFFLINE ONLY, to measure whether this
## cycle ever breaks and at what cost. Nothing here changes the shipped cap.

const SolverScript = preload("res://sim/core/Phase3CoupledPressureSolver.gd")
const CAPTURE_PATH := "res://tests/fixtures/data/coupled_solver_iteration_cap_after_rescue_corridor_chain.json"
const OUT_PATH := "res://runs/h25m_cycle_trace.json"

const CYCLE_MIN_GAIN := 0.05
const CYCLE_MAX_COSINE := -0.99
const OFFLINE_CAP := 400

var _solver = null
var _context: Dictionary = {}
var _room_count: int = 0


func _init() -> void:
	var capture: Dictionary = _load_capture()
	if capture.is_empty():
		quit(1)
		return
	_solver = SolverScript.new()
	var built: Dictionary = _build(capture)
	if not bool(built.get("ok", false)):
		push_error("context build failed")
		quit(1)
		return

	var report: Dictionary = {}
	report["trace"] = _trace(24)
	report["offline_cap_replay"] = _replay_cap(OFFLINE_CAP)
	report["experiments"] = _experiments(report["trace"])
	report["meta"] = {
		"room_count": _room_count,
		"opening_count": int(_context["openings"].size()),
		"band_segments": int(_context["band_segments"]),
		"dp_regularization_pa": float(_context["dp_regularization_pa"]),
		"jacobian_step_pa": float(_context["jacobian_step_pa"]),
		"tolerance": float(_context["residual_tolerance"]),
	}

	var file: FileAccess = FileAccess.open(OUT_PATH, FileAccess.WRITE)
	if file == null:
		push_error("cannot write " + OUT_PATH)
		quit(1)
		return
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	print("H25M_TRACE_WRITTEN %s" % OUT_PATH)
	print("H25M_CYCLE_TRACE_PASS")
	quit(0)


# ------------------------------------------------------------
# replay of the shipped loop, instrumented
# ------------------------------------------------------------

## Reproduces the committed Newton/L-infinity loop exactly, including the
## one-step LM rescue and the cycle guard, while recording per-iteration state.
func _trace(cap: int) -> Array:
	var out: Array = []
	var pressure: Array[float] = _seed()
	var evaluation: Dictionary = _solver._evaluate(_context, pressure)
	var norm: float = float(evaluation["normalized_residual"])
	var tolerance: float = float(_context["residual_tolerance"])
	var max_halvings: int = int(_context["max_damping_halvings"])
	var rescue_budget: int = 1
	var prev_step: Array = []
	var prev_gain: float = INF
	var prev_conn: Array = _connection_census(evaluation)
	var iterations: int = 0
	var converged: bool = norm <= tolerance

	while not converged and iterations < cap:
		iterations += 1
		var jacobian: Array = _jacobian(
			pressure, evaluation, float(_context["jacobian_step_pa"]), false
		)
		if jacobian.is_empty():
			break
		var step: Array = _newton_step(jacobian, evaluation)
		if step.is_empty():
			break

		var damping: float = 1.0
		var halvings: int = 0
		var accepted: bool = false
		var cand_p: Array[float] = pressure.duplicate()
		var cand_e: Dictionary = evaluation
		while halvings <= max_halvings:
			var trial: Array[float] = _shift(pressure, step, damping)
			var trial_e: Dictionary = _solver._evaluate(_context, trial)
			if bool(trial_e.get("valid", false)) \
					and float(trial_e["normalized_residual"]) < norm:
				cand_p = trial
				cand_e = trial_e
				accepted = true
				break
			damping *= 0.5
			halvings += 1

		var row: Dictionary = {
			"iteration": iterations,
			"norm_before": norm,
			"step_norm": _norm(step),
			"damping": damping,
			"accepted": accepted,
			"merit_before": float(_solver._rescue_merit(evaluation)),
			"pressure_before": _floats(pressure),
			"step": _floats(step),
		}

		if not accepted:
			# The shipped fail-only LM path.
			var rescue: Dictionary = _solver._try_lm_rescue(
				_context, pressure, evaluation, jacobian,
				_room_count, max_halvings, rescue_budget
			)
			row["path"] = "lm_fail_only"
			row["rescue_accepted"] = bool(rescue.get("accepted", false))
			out.append(row)
			if not bool(rescue.get("accepted", false)):
				break
			rescue_budget -= 1
			pressure = rescue["pressure"]
			evaluation = rescue["evaluation"]
			norm = float(evaluation["normalized_residual"])
			prev_step = []
			prev_gain = INF
			prev_conn = _connection_census(evaluation)
			converged = norm <= tolerance
			continue

		var gain: float = float(_solver._model_gain_ratio(
			_context, evaluation, cand_e, jacobian, step, damping
		))
		var cosine: float = 1.0
		var cycle: bool = false
		if damping == 1.0 and not prev_step.is_empty():
			cosine = float(_solver._step_cosine(prev_step, step))
			cycle = (
				prev_gain < CYCLE_MIN_GAIN
				and gain < CYCLE_MIN_GAIN
				and cosine < CYCLE_MAX_COSINE
			)
		row["model_gain_ratio"] = gain if is_finite(gain) else 1.0e308
		row["step_cosine"] = cosine
		row["cycle_detected"] = cycle
		row["rescue_budget_left"] = rescue_budget
		row["post_budget_cycle"] = cycle and rescue_budget <= 0

		var conn: Array = _connection_census(cand_e)
		row["connections"] = conn
		row["sign_flips"] = _count_flips(prev_conn, conn)
		row["regularization_active"] = float(
			cand_e.get("regularization_active_count", 0.0)
		)
		prev_conn = conn

		if cycle and rescue_budget > 0:
			var cyc: Dictionary = _solver._try_lm_rescue(
				_context, pressure, evaluation, jacobian,
				_room_count, max_halvings, rescue_budget
			)
			row["path"] = "lm_cycle_guard"
			row["rescue_accepted"] = bool(cyc.get("accepted", false))
			out.append(row)
			if bool(cyc.get("accepted", false)):
				rescue_budget -= 1
				pressure = cyc["pressure"]
				evaluation = cyc["evaluation"]
				norm = float(evaluation["normalized_residual"])
				prev_step = []
				prev_gain = INF
				prev_conn = _connection_census(evaluation)
				converged = norm <= tolerance
				continue
		else:
			row["path"] = "newton"
			out.append(row)

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

	return out


## E5: does this cycle ever break if the cap is lifted? Offline only.
func _replay_cap(cap: int) -> Dictionary:
	var rows: Array = _trace(cap)
	var last: Dictionary = rows[rows.size() - 1] if not rows.is_empty() else {}
	var best: float = INF
	var best_at: int = -1
	for raw in rows:
		var r: Dictionary = raw
		var n: float = float(r.get("norm_before", INF))
		if n < best:
			best = n
			best_at = int(r.get("iteration", -1))
	return {
		"cap": cap,
		"iterations_used": rows.size(),
		"converged_within_cap": rows.size() < cap,
		"final_norm": float(last.get("norm_before", INF)),
		"best_norm": best,
		"best_norm_iteration": best_at,
	}


# ------------------------------------------------------------
# experiments at the post-budget cycle points
# ------------------------------------------------------------

func _experiments(trace: Array) -> Dictionary:
	var targets: Array = []
	for raw in trace:
		var r: Dictionary = raw
		if bool(r.get("post_budget_cycle", false)):
			targets.append(r)
	if targets.is_empty():
		return {"post_budget_cycle_points": 0}

	# First and middle post-budget cycle point: early and settled behaviour.
	var picks: Array = [targets[0]]
	if targets.size() > 2:
		picks.append(targets[int(targets.size() / 2)])

	var results: Array = []
	for raw_pick in picks:
		var pick: Dictionary = raw_pick
		var p: Array[float] = _to_floats(pick["pressure_before"])
		var s: Array = pick["step"]
		results.append({
			"at_iteration": int(pick["iteration"]),
			"e1_merit_along_cycle_direction": _e1_line_scan(p, s),
			"e2_central_difference": _e2_central(p, s),
			"e3_jacobian_step_sweep": _e3_h_sweep(p),
		})
	return {
		"post_budget_cycle_points": targets.size(),
		"probes": results,
	}


## E1: merit phi(alpha) = 0.5*sum(normalized residual^2) along p + alpha*s.
## A smooth bowl with a minimum near alpha=1 means the step is fine and the
## acceptance test is at fault. A kink, or a minimum far from 1, means the
## direction itself is being computed across a non-smooth region.
func _e1_line_scan(p: Array[float], s: Array) -> Array:
	var out: Array = []
	var alpha: float = -1.5
	while alpha <= 2.5001:
		var q: Array[float] = _shift(p, s, alpha)
		var e: Dictionary = _solver._evaluate(_context, q)
		if bool(e.get("valid", false)):
			out.append({
				"alpha": alpha,
				"merit": float(_solver._rescue_merit(e)),
				"linf": float(e["normalized_residual"]),
			})
		alpha += 0.05
	return out


## E2: same point, central-difference Jacobian. If the gain ratio recovers to
## order one, the one-sided quotient is the defect.
func _e2_central(p: Array[float], s: Array) -> Dictionary:
	var e: Dictionary = _solver._evaluate(_context, p)
	var h: float = float(_context["jacobian_step_pa"])
	var jc: Array = _jacobian(p, e, h, true)
	if jc.is_empty():
		return {"valid": false}
	var sc: Array = _newton_step(jc, e)
	if sc.is_empty():
		return {"valid": false}
	var ec: Dictionary = _solver._evaluate(_context, _shift(p, sc, 1.0))
	if not bool(ec.get("valid", false)):
		return {"valid": false}
	var gain: float = float(_solver._model_gain_ratio(
		_context, e, ec, jc, sc, 1.0
	))
	return {
		"valid": true,
		"central_step_norm": _norm(sc),
		"onesided_step_norm": _norm(s),
		"cosine_central_vs_onesided": float(_solver._step_cosine(s, sc)),
		"central_model_gain_ratio": gain if is_finite(gain) else 1.0e308,
		"merit_before": float(_solver._rescue_merit(e)),
		"merit_after_central_full_step": float(_solver._rescue_merit(ec)),
		"linf_before": float(e["normalized_residual"]),
		"linf_after_central_full_step": float(ec["normalized_residual"]),
	}


## E3: sweep the differencing width. A smooth residual gives a direction that
## is stable across decades. Chattering across a switching manifold does not.
func _e3_h_sweep(p: Array[float]) -> Array:
	var e: Dictionary = _solver._evaluate(_context, p)
	var widths: Array = [1.0e-6, 1.0e-5, 1.0e-4, 1.0e-3, 1.0e-2, 1.0e-1, 1.0]
	var reference: Array = []
	var out: Array = []
	for raw_h in widths:
		var h: float = float(raw_h)
		var j: Array = _jacobian(p, e, h, false)
		if j.is_empty():
			continue
		var st: Array = _newton_step(j, e)
		if st.is_empty():
			continue
		if reference.is_empty():
			reference = st
		var trial_e: Dictionary = _solver._evaluate(_context, _shift(p, st, 1.0))
		out.append({
			"h": h,
			"step_norm": _norm(st),
			"cosine_vs_smallest_h": float(_solver._step_cosine(reference, st)),
			"linf_after_full_step": float(trial_e["normalized_residual"])
					if bool(trial_e.get("valid", false)) else -1.0,
		})
	return out


# ------------------------------------------------------------
# primitives
# ------------------------------------------------------------

func _jacobian(
		pressure: Array[float], evaluation: Dictionary, h: float, central: bool
	) -> Array:
	var j: Array = []
	for row in range(_room_count):
		var r: Array[float] = []
		r.resize(_room_count)
		j.append(r)
	for column in range(_room_count):
		var fwd_p: Array[float] = pressure.duplicate()
		fwd_p[column] = fwd_p[column] + h
		var fwd: Dictionary = _solver._evaluate(_context, fwd_p)
		if not bool(fwd.get("valid", false)):
			return []
		if central:
			var bwd_p: Array[float] = pressure.duplicate()
			bwd_p[column] = bwd_p[column] - h
			var bwd: Dictionary = _solver._evaluate(_context, bwd_p)
			if not bool(bwd.get("valid", false)):
				return []
			for row in range(_room_count):
				j[row][column] = (
					float(fwd["residual"][row]) - float(bwd["residual"][row])
				) / (2.0 * h)
		else:
			for row in range(_room_count):
				j[row][column] = (
					float(fwd["residual"][row])
					- float(evaluation["residual"][row])
				) / h
	return j


func _newton_step(jacobian: Array, evaluation: Dictionary) -> Array:
	var rhs: Array[float] = []
	for row in range(_room_count):
		rhs.append(-float(evaluation["residual"][row]))
	return _solver._solve_linear_system(jacobian, rhs)


func _connection_census(evaluation: Dictionary) -> Array:
	var out: Array = []
	for raw in evaluation.get("connections", []):
		var c: Dictionary = raw
		out.append({
			"opening_id": int(c["opening_id"]),
			"delta_p_pa": float(c["delta_p_pa"]),
			"sign": signf(float(c["delta_p_pa"])),
			"neutral_plane_inside": bool(c["neutral_plane_inside"]),
			"regularization_active_count": float(
				c.get("regularization_active_count", 0.0)
			),
		})
	return out


func _count_flips(before: Array, after: Array) -> int:
	if before.size() != after.size():
		return -1
	var flips: int = 0
	for index in range(before.size()):
		var b: Dictionary = before[index]
		var a: Dictionary = after[index]
		if float(b["sign"]) != float(a["sign"]):
			flips += 1
	return flips


func _shift(base: Array, direction: Array, scale: float) -> Array[float]:
	var out: Array[float] = []
	for index in range(base.size()):
		out.append(float(base[index]) + scale * float(direction[index]))
	return out


func _norm(v: Array) -> float:
	var total: float = 0.0
	for raw in v:
		var value: float = float(raw)
		total += value * value
	return sqrt(total)


func _floats(v: Array) -> Array:
	var out: Array = []
	for raw in v:
		out.append(float(raw))
	return out


func _to_floats(v: Array) -> Array[float]:
	var out: Array[float] = []
	for raw in v:
		out.append(float(raw))
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


func _load_capture() -> Dictionary:
	if not FileAccess.file_exists(CAPTURE_PATH):
		push_error("capture missing: " + CAPTURE_PATH)
		return {}
	var file: FileAccess = FileAccess.open(CAPTURE_PATH, FileAccess.READ)
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

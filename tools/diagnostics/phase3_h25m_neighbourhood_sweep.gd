extends SceneTree

## H2.5m NON-INTERFERENCE SWEEP - offline, read-only, no runtime authority.
##
## The strategy probe showed the analytic half step fixes the post-budget cycle
## on the captures. The remaining question is the one H2.5g answered for the LM
## rescue: over a large neighbourhood of real solves, does the candidate leave
## every already-successful solve BIT-IDENTICAL?
##
## This sweep perturbs each committed capture across owner sources, room energy
## and timestep, then runs the baseline and the candidate on every case and
## compares the converged pressure field exactly. `sim/core` is imported, never
## modified, and nothing here is committed as runtime behaviour.

const SolverScript = preload("res://sim/core/Phase3CoupledPressureSolver.gd")
const OUT_PATH := "res://runs/h25m_neighbourhood_sweep.json"

const CAPTURES := [
	"res://tests/fixtures/data/coupled_solver_iteration_cap_after_rescue_corridor_chain.json",
	"res://tests/fixtures/data/coupled_solver_iteration_cap_corridor_chain.json",
	"res://tests/fixtures/data/coupled_solver_failure_corridor_chain.json",
	"res://tests/fixtures/data/coupled_solver_failure_r0_window_360.json",
]

const SOURCE_SCALES := [0.25, 0.5, 0.75, 0.9, 1.0, 1.1, 1.25, 1.5, 2.0, 3.0]
const ENERGY_SCALES := [0.98, 0.99, 1.0, 1.01, 1.02]
const DT_SCALES := [0.5, 1.0, 2.0]

const CYCLE_MIN_GAIN := 0.05
const CYCLE_MAX_COSINE := -0.99
const SHIPPED_CAP := 24

var _solver = null
var _context: Dictionary = {}
var _room_count: int = 0


func _init() -> void:
	_solver = SolverScript.new()
	var totals: Dictionary = {
		"cases": 0,
		"baseline_converged": 0,
		"candidate_converged": 0,
		"both_converged_bit_identical": 0,
		"both_converged_differing": 0,
		"fixed_by_candidate": 0,
		"broken_by_candidate": 0,
		"candidate_half_steps": 0,
	}
	# Population maximum, not a sample: the divergence bound is the whole
	# safety claim, so it is measured over every case rather than the first few.
	var worst_delta_pa: float = 0.0
	var worst_delta_case: Dictionary = {}
	var per_capture: Dictionary = {}
	var divergences: Array = []

	for raw_path in CAPTURES:
		var path: String = String(raw_path)
		var capture: Dictionary = _load(path)
		if capture.is_empty():
			continue
		var local: Dictionary = {
			"cases": 0, "baseline_converged": 0, "candidate_converged": 0,
			"both_converged_bit_identical": 0, "both_converged_differing": 0,
			"fixed_by_candidate": 0, "broken_by_candidate": 0,
		}
		for raw_source in SOURCE_SCALES:
			for raw_energy in ENERGY_SCALES:
				for raw_dt in DT_SCALES:
					var scales: Dictionary = {
						"source": float(raw_source),
						"energy": float(raw_energy),
						"dt": float(raw_dt),
					}
					if not bool(_build(capture, scales).get("ok", false)):
						continue
					var base: Dictionary = _run(false)
					var cand: Dictionary = _run(true)
					local["cases"] += 1
					totals["cases"] += 1
					totals["candidate_half_steps"] += int(cand["half_steps"])
					if bool(base["converged"]):
						local["baseline_converged"] += 1
						totals["baseline_converged"] += 1
					if bool(cand["converged"]):
						local["candidate_converged"] += 1
						totals["candidate_converged"] += 1
					if bool(base["converged"]) and bool(cand["converged"]):
						if _identical(base["pressure"], cand["pressure"]):
							local["both_converged_bit_identical"] += 1
							totals["both_converged_bit_identical"] += 1
						else:
							local["both_converged_differing"] += 1
							totals["both_converged_differing"] += 1
							var delta_pa: float = _max_delta(
								base["pressure"], cand["pressure"]
							)
							if delta_pa > worst_delta_pa:
								worst_delta_pa = delta_pa
								worst_delta_case = {
									"capture": path.get_file(),
									"scales": scales,
									"max_abs_pressure_delta_pa": delta_pa,
									"baseline_norm": float(base["final_norm"]),
									"candidate_norm": float(cand["final_norm"]),
								}
							if divergences.size() < 12:
								divergences.append({
									"capture": path.get_file(),
									"scales": scales,
									"baseline_iterations": int(base["iterations"]),
									"candidate_iterations": int(cand["iterations"]),
									"baseline_norm": float(base["final_norm"]),
									"candidate_norm": float(cand["final_norm"]),
									"max_abs_pressure_delta_pa": _max_delta(
										base["pressure"], cand["pressure"]
									),
									"candidate_half_steps": int(cand["half_steps"]),
								})
					elif bool(cand["converged"]) and not bool(base["converged"]):
						local["fixed_by_candidate"] += 1
						totals["fixed_by_candidate"] += 1
					elif bool(base["converged"]) and not bool(cand["converged"]):
						local["broken_by_candidate"] += 1
						totals["broken_by_candidate"] += 1
		per_capture[path.get_file()] = local

	var report: Dictionary = {
		"totals": totals,
		"per_capture": per_capture,
		"worst_divergence_pa": worst_delta_pa,
		"worst_divergence_case": worst_delta_case,
		"divergence_samples": divergences,
		"grid": {
			"source_scales": SOURCE_SCALES,
			"energy_scales": ENERGY_SCALES,
			"dt_scales": DT_SCALES,
			"cap": SHIPPED_CAP,
		},
	}
	var file: FileAccess = FileAccess.open(OUT_PATH, FileAccess.WRITE)
	if file == null:
		push_error("cannot write " + OUT_PATH)
		quit(1)
		return
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	print("H25M_SWEEP_WRITTEN %s" % OUT_PATH)
	print(
		"H25M cases=%d base_conv=%d cand_conv=%d identical=%d differ=%d fixed=%d broken=%d"
		% [
			int(totals["cases"]), int(totals["baseline_converged"]),
			int(totals["candidate_converged"]),
			int(totals["both_converged_bit_identical"]),
			int(totals["both_converged_differing"]),
			int(totals["fixed_by_candidate"]), int(totals["broken_by_candidate"]),
		]
	)
	print("H25M worst_divergence_pa=%s" % str(worst_delta_pa))
	print("H25M_NEIGHBOURHOOD_SWEEP_PASS")
	quit(0)


func _run(use_half: bool) -> Dictionary:
	var pressure: Array[float] = _seed()
	var evaluation: Dictionary = _solver._evaluate(_context, pressure)
	if not bool(evaluation.get("valid", false)):
		return {"converged": false, "iterations": 0, "final_norm": INF,
				"pressure": [], "half_steps": 0}
	var norm: float = float(evaluation["normalized_residual"])
	var tolerance: float = float(_context["residual_tolerance"])
	var max_halvings: int = int(_context["max_damping_halvings"])
	var h: float = float(_context["jacobian_step_pa"])
	var rescue_budget: int = 1
	var prev_step: Array = []
	var prev_gain: float = INF
	var iterations: int = 0
	var converged: bool = norm <= tolerance
	var half_steps: int = 0

	while not converged and iterations < SHIPPED_CAP:
		iterations += 1
		var jacobian: Array = _jacobian(pressure, evaluation, h)
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

		if not accepted:
			var rescue: Dictionary = _solver._try_lm_rescue(
				_context, pressure, evaluation, jacobian,
				_room_count, max_halvings, rescue_budget
			)
			if not bool(rescue.get("accepted", false)):
				break
			rescue_budget -= 1
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
			var half_p: Array[float] = _shift(pressure, step, 0.5)
			var half_e: Dictionary = _solver._evaluate(_context, half_p)
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

		if cycle and rescue_budget > 0:
			var cyc: Dictionary = _solver._try_lm_rescue(
				_context, pressure, evaluation, jacobian,
				_room_count, max_halvings, rescue_budget
			)
			if bool(cyc.get("accepted", false)):
				rescue_budget -= 1
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

	return {
		"converged": converged,
		"iterations": iterations,
		"final_norm": norm,
		"pressure": pressure,
		"half_steps": half_steps,
	}


func _identical(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for index in range(a.size()):
		if float(a[index]) != float(b[index]):
			return false
	return true


func _max_delta(a: Array, b: Array) -> float:
	if a.size() != b.size():
		return INF
	var worst: float = 0.0
	for index in range(a.size()):
		worst = maxf(worst, absf(float(a[index]) - float(b[index])))
	return worst


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


func _build(capture: Dictionary, scales: Dictionary) -> Dictionary:
	var input: Dictionary = capture["input"]
	var energy_scale: float = float(scales["energy"])
	var source_scale: float = float(scales["source"])
	var rooms: Dictionary = {}
	for raw_key in input["rooms"].keys():
		var room: Dictionary = _number_dictionary(input["rooms"][raw_key])
		room["upper_energy_kj"] = float(room["upper_energy_kj"]) * energy_scale
		room["lower_energy_kj"] = float(room["lower_energy_kj"]) * energy_scale
		rooms[String(raw_key)] = room
	var sources: Dictionary = {}
	for raw_key in input["sources"].keys():
		var source: Dictionary = _number_dictionary(input["sources"][raw_key])
		source["mass_kg"] = float(source["mass_kg"]) * source_scale
		source["energy_kj"] = float(source["energy_kj"]) * source_scale
		sources[String(raw_key)] = source
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
		_number(input, "dt") * float(scales["dt"]),
		_number(input, "reference_temp_c"), options
	)
	if not bool(_context.get("valid", false)):
		return {"ok": false}
	_room_count = int(_context["room_keys"].size())
	return {"ok": true}


func _load(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
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

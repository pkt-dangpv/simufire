extends SceneTree

## H2.7 policy probe. Offline, read-only, no runtime authority.
##
## The stall anatomy showed the cap is not the defect. Through every stall the
## step cosine sits at -0.9999: the period-2 orbit is unmistakable. What blocks
## the H2.5j detector is that the model gain ratio ALSO has period two - one
## phase near 0.08, the other near -0.01 - while the detector demands that BOTH
## consecutive gains be below 0.05. That conjunction can never hold on an
## alternating sequence whose high phase exceeds the threshold, so the orbit
## runs until the ordinary line search happens to damp and break it.
##
## This probe compares budget policies against detector policies on the same
## captures, at the SHIPPED cap unless a policy says otherwise:
##
##   P0  baseline, exactly as shipped
##   P1  cap raised to 48, a negative control for "just make it bigger"
##   P2  detector uses min(previous_gain, gain) < 0.05 - the orbit is declared
##       when EITHER phase is a poor model match, which is what an alternating
##       gain actually looks like
##   P3  detector drops the gain test entirely and relies on the cosine
##
## P2 and P3 are evaluated here only. `sim/core` is imported, never modified,
## and nothing in this phase changes the shipped solver.

const SolverScript = preload("res://sim/core/Phase3CoupledPressureSolver.gd")
const OUT_PATH := "res://runs/h27/policy_probe.json"
const SHIPPED_CAP := 24

const CAPTURES := [
	"res://runs/h27/captures/cfast_two_floor_stairwell__iteration_cap.json",
	"res://runs/h27/captures/flashover_simple_house__iteration_cap.json",
	"res://runs/h27/captures/three_bed_apartment_smoke__iteration_cap.json",
	"res://runs/h27/captures/two_storey_smoke__iteration_cap.json",
	"res://runs/h27/captures/uk_bungalow_smoke__damping_exhausted.json",
	"res://tests/fixtures/data/coupled_solver_iteration_cap_after_rescue_corridor_chain.json",
	"res://tests/fixtures/data/coupled_solver_iteration_cap_corridor_chain.json",
	"res://tests/fixtures/data/coupled_solver_failure_corridor_chain.json",
	"res://tests/fixtures/data/coupled_solver_failure_r0_window_360.json",
]

const POLICIES := ["p0_baseline", "p1_cap48", "p2_min_gain", "p3_cosine_only"]

var _solver = null
var _context: Dictionary = {}
var _rooms: int = 0


func _init() -> void:
	_solver = SolverScript.new()
	var report: Dictionary = {}
	for raw_path in CAPTURES:
		var path: String = String(raw_path)
		var capture: Dictionary = _load(path)
		if capture.is_empty():
			continue
		if not _build(capture):
			continue
		var per: Dictionary = {}
		var roots: Array = []
		for raw_policy in POLICIES:
			var policy: String = String(raw_policy)
			var result: Dictionary = _run(policy)
			per[policy] = result
			if bool(result["converged"]):
				roots.append(result["pressure"])
				result.erase("pressure")
			else:
				result.erase("pressure")
		per["root_agreement"] = _root_agreement(roots)
		report[path.get_file()] = per
		print("probed %s" % path.get_file())
	var file: FileAccess = FileAccess.open(OUT_PATH, FileAccess.WRITE)
	if file == null:
		push_error("cannot write " + OUT_PATH)
		quit(1)
		return
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	print("H27_POLICY_PROBE_WRITTEN %s" % OUT_PATH)
	print("H27_POLICY_PROBE_PASS")
	quit(0)


func _run(policy: String) -> Dictionary:
	var cap: int = 48 if policy == "p1_cap48" else SHIPPED_CAP
	var pressure: Array[float] = _seed()
	var evaluation: Dictionary = _solver._evaluate(_context, pressure)
	var norm: float = float(evaluation["normalized_residual"])
	var tolerance: float = float(_context["residual_tolerance"])
	var max_halvings: int = int(_context["max_damping_halvings"])
	var h: float = float(_context["jacobian_step_pa"])
	var budget: int = 1
	var previous_step: Array = []
	var previous_gain: float = INF
	var iterations: int = 0
	var converged: bool = norm <= tolerance
	var half_accepts: int = 0
	var lm_accepts: int = 0
	var evaluations: int = 1
	var reason: String = "converged"

	while not converged and iterations < cap:
		iterations += 1
		var jacobian: Array = _jacobian(pressure, evaluation, h)
		evaluations += _rooms
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
		var candidate_p: Array[float] = pressure.duplicate()
		var candidate_e: Dictionary = evaluation
		while halvings <= max_halvings:
			var trial: Array[float] = _shift(pressure, step, damping)
			var trial_e: Dictionary = _solver._evaluate(_context, trial)
			evaluations += 1
			if bool(trial_e.get("valid", false)) \
					and float(trial_e["normalized_residual"]) < norm:
				candidate_p = trial
				candidate_e = trial_e
				accepted = true
				break
			damping *= 0.5
			halvings += 1

		if not accepted:
			var rescue: Dictionary = _solver._try_lm_rescue(
				_context, pressure, evaluation, jacobian, _rooms,
				max_halvings, budget
			)
			evaluations += int(rescue.get("trials", 0.0))
			if not bool(rescue.get("accepted", false)):
				reason = "damping_exhausted"
				break
			budget -= 1
			lm_accepts += 1
			pressure = rescue["pressure"]
			evaluation = rescue["evaluation"]
			norm = float(evaluation["normalized_residual"])
			previous_step = []
			previous_gain = INF
			converged = norm <= tolerance
			continue

		var gain: float = float(_solver._model_gain_ratio(
			_context, evaluation, candidate_e, jacobian, step, damping
		))
		var cosine: float = 1.0
		var detected: bool = false
		if damping == 1.0 and not previous_step.is_empty():
			cosine = float(_solver._step_cosine(previous_step, step))
			detected = _detect(policy, previous_gain, gain, cosine)

		if detected:
			var half: Array[float] = _shift(pressure, step, 0.5)
			var half_e: Dictionary = _solver._evaluate(_context, half)
			evaluations += 1
			if bool(half_e.get("valid", false)) \
					and float(half_e["normalized_residual"]) < norm:
				half_accepts += 1
				pressure = half
				evaluation = half_e
				norm = float(evaluation["normalized_residual"])
				previous_step = []
				previous_gain = INF
				converged = norm <= tolerance
				continue
		if detected and budget > 0:
			var cycle_rescue: Dictionary = _solver._try_lm_rescue(
				_context, pressure, evaluation, jacobian, _rooms,
				max_halvings, budget
			)
			evaluations += int(cycle_rescue.get("trials", 0.0))
			if bool(cycle_rescue.get("accepted", false)):
				budget -= 1
				lm_accepts += 1
				pressure = cycle_rescue["pressure"]
				evaluation = cycle_rescue["evaluation"]
				norm = float(evaluation["normalized_residual"])
				previous_step = []
				previous_gain = INF
				converged = norm <= tolerance
				continue

		if damping == 1.0:
			previous_step = step.duplicate()
			previous_gain = gain
		else:
			previous_step = []
			previous_gain = INF
		pressure = candidate_p
		evaluation = candidate_e
		norm = float(evaluation["normalized_residual"])
		converged = norm <= tolerance

	if not converged and reason == "converged":
		reason = "iteration_cap"
	return {
		"policy": policy,
		"cap": cap,
		"converged": converged,
		"iterations": iterations,
		"final_residual": norm,
		"limiting_reason": reason,
		"half_step_accepts": half_accepts,
		"lm_accepts": lm_accepts,
		"residual_evaluations": evaluations,
		"pressure": pressure,
	}


## The only thing that varies between policies is this predicate.
func _detect(
		policy: String, previous_gain: float, gain: float, cosine: float
	) -> bool:
	if cosine >= -0.99:
		return false
	match policy:
		"p2_min_gain":
			# An alternating gain never puts BOTH phases below the threshold;
			# requiring either one is what the sequence actually looks like.
			return minf(previous_gain, gain) < 0.05
		"p3_cosine_only":
			return true
		_:
			return previous_gain < 0.05 and gain < 0.05


func _root_agreement(roots: Array) -> Dictionary:
	if roots.size() < 2:
		return {"compared": roots.size(), "max_abs_delta_pa": 0.0}
	var worst: float = 0.0
	for index in range(1, roots.size()):
		for position in range(roots[0].size()):
			worst = maxf(
				worst,
				absf(float(roots[0][position]) - float(roots[index][position]))
			)
	return {"compared": roots.size(), "max_abs_delta_pa": worst}


func _jacobian(pressure: Array[float], evaluation: Dictionary, h: float) -> Array:
	var jacobian: Array = []
	for row in range(_rooms):
		var values: Array[float] = []
		values.resize(_rooms)
		jacobian.append(values)
	for column in range(_rooms):
		var perturbed: Array[float] = pressure.duplicate()
		perturbed[column] = perturbed[column] + h
		var forward: Dictionary = _solver._evaluate(_context, perturbed)
		if not bool(forward.get("valid", false)):
			return []
		for row in range(_rooms):
			jacobian[row][column] = (
				float(forward["residual"][row])
				- float(evaluation["residual"][row])
			) / h
	return jacobian


func _newton_step(jacobian: Array, evaluation: Dictionary) -> Array:
	var rhs: Array[float] = []
	for row in range(_rooms):
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


func _build(capture: Dictionary) -> bool:
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
	_context = _solver._build_context(
		rooms, openings, sources,
		_number(input, "dt"), _number(input, "reference_temp_c"),
		{
			"residual_tolerance": _number(defaults, "residual_tolerance"),
			"max_iterations": SHIPPED_CAP,
			"dp_regularization_pa": _number(defaults, "dp_regularization_pa"),
			"jacobian_step_pa": _number(defaults, "jacobian_step_pa"),
			"band_segments": int(defaults["band_segments"]),
			"max_damping_halvings": int(defaults["max_damping_halvings"]),
		}
	)
	if not bool(_context.get("valid", false)):
		return false
	_rooms = int(_context["room_keys"].size())
	return true


func _load(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("missing capture: " + path)
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

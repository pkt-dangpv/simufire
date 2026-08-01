extends SceneTree

## H2.7 stall anatomy. Offline, read-only, no runtime authority.
##
## The budget sweep showed every large-network `iteration_cap` has the same
## shape: a long stall where the residual ratio ALTERNATES near one, then a
## sudden break into quadratic convergence. Alternation is the signature of the
## period-2 square-root orbit H2.5m diagnosed - yet `cycle_detect_total` is 0
## on three of the four captures, so the detector is not seeing it.
##
## This harness replays each capture through the solver's own primitives and
## records, per iteration, the three quantities the detector actually tests:
## damping, the model gain ratio, and the cosine between successive full steps.
## It also projects the step onto the alternating subspace, because in an
## n-room network an orbit can live in a few components while the remaining
## ones dilute the global cosine - which would explain why a threshold chosen
## on a three-room corridor fails to fire on an eleven-room tree.
##
## `sim/core` is imported and never modified.

const SolverScript = preload("res://sim/core/Phase3CoupledPressureSolver.gd")
const CAPTURE_DIR := "res://runs/h27/captures"
const OUT_PATH := "res://runs/h27/stall_anatomy.json"
const REPLAY_CAP := 64

var _solver = null
var _context: Dictionary = {}
var _rooms: int = 0


func _init() -> void:
	_solver = SolverScript.new()
	var report: Dictionary = {}
	for name in _capture_names():
		var capture: Dictionary = _load("%s/%s" % [CAPTURE_DIR, name])
		if capture.is_empty():
			continue
		if not _build(capture):
			continue
		report[name] = _trace()
		print("traced %s" % name)
	var file: FileAccess = FileAccess.open(OUT_PATH, FileAccess.WRITE)
	if file == null:
		push_error("cannot write " + OUT_PATH)
		quit(1)
		return
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	print("H27_STALL_ANATOMY_WRITTEN %s" % OUT_PATH)
	print("H27_STALL_ANATOMY_PASS")
	quit(0)


## Reproduces the shipped loop, including the half step and the LM paths, while
## recording what the cycle detector sees at every iteration.
func _trace() -> Array:
	var out: Array = []
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

	while not converged and iterations < REPLAY_CAP:
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
		var candidate_p: Array[float] = pressure.duplicate()
		var candidate_e: Dictionary = evaluation
		while halvings <= max_halvings:
			var trial: Array[float] = _shift(pressure, step, damping)
			var trial_e: Dictionary = _solver._evaluate(_context, trial)
			if bool(trial_e.get("valid", false)) \
					and float(trial_e["normalized_residual"]) < norm:
				candidate_p = trial
				candidate_e = trial_e
				accepted = true
				break
			damping *= 0.5
			halvings += 1
		if not accepted:
			out.append({"iteration": iterations, "path": "damping_exhausted"})
			break

		var gain: float = float(_solver._model_gain_ratio(
			_context, evaluation, candidate_e, jacobian, step, damping
		))
		var cosine: float = 1.0
		if not previous_step.is_empty():
			cosine = float(_solver._step_cosine(previous_step, step))
		var detected: bool = (
			damping == 1.0 and not previous_step.is_empty()
			and previous_gain < 0.05 and gain < 0.05 and cosine < -0.99
		)

		var row: Dictionary = {
			"iteration": iterations,
			"norm_before": norm,
			"damping": damping,
			"model_gain_ratio": gain if is_finite(gain) else 1.0e308,
			"step_cosine": cosine,
			"cycle_detected": detected,
		}
		# Which of the three conditions blocks detection, and by how much.
		row["blocked_by"] = _blocked_by(damping, previous_gain, gain, cosine,
				previous_step.is_empty())
		# How much of the step actually alternates: the anti-parallel component
		# of s_k relative to s_{k-1}. A dominant orbit inside a wide network
		# gives a large ratio while the global cosine stays mild.
		row["antiparallel_fraction"] = _antiparallel_fraction(
			previous_step, step
		)
		out.append(row)

		if detected:
			var half: Array[float] = _shift(pressure, step, 0.5)
			var half_e: Dictionary = _solver._evaluate(_context, half)
			if bool(half_e.get("valid", false)) \
					and float(half_e["normalized_residual"]) < norm:
				pressure = half
				evaluation = half_e
				norm = float(evaluation["normalized_residual"])
				previous_step = []
				previous_gain = INF
				converged = norm <= tolerance
				continue
		if detected and budget > 0:
			var rescue: Dictionary = _solver._try_lm_rescue(
				_context, pressure, evaluation, jacobian, _rooms,
				max_halvings, budget
			)
			if bool(rescue.get("accepted", false)):
				budget -= 1
				pressure = rescue["pressure"]
				evaluation = rescue["evaluation"]
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
	return out


func _blocked_by(
		damping: float, previous_gain: float, gain: float,
		cosine: float, no_history: bool
	) -> Array:
	var reasons: Array = []
	if no_history:
		reasons.append("no_previous_full_step")
		return reasons
	if damping != 1.0:
		reasons.append("damped_step")
	if not (previous_gain < 0.05):
		reasons.append("previous_gain_ge_0.05")
	if not (gain < 0.05):
		reasons.append("gain_ge_0.05")
	if not (cosine < -0.99):
		reasons.append("cosine_ge_-0.99")
	return reasons


## |component of s_k anti-parallel to s_{k-1}| / |s_k|. Equals -cosine when the
## steps are the same length, but stays informative when they are not.
func _antiparallel_fraction(previous: Array, current: Array) -> float:
	if previous.is_empty() or previous.size() != current.size():
		return NAN
	var dot: float = 0.0
	var previous_norm_sq: float = 0.0
	var current_norm_sq: float = 0.0
	for index in range(current.size()):
		var a: float = float(previous[index])
		var b: float = float(current[index])
		dot += a * b
		previous_norm_sq += a * a
		current_norm_sq += b * b
	if previous_norm_sq <= 0.0 or current_norm_sq <= 0.0:
		return NAN
	# Projection of s_k onto the -s_{k-1} direction, as a fraction of |s_k|.
	return -dot / sqrt(previous_norm_sq) / sqrt(current_norm_sq)


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
			"max_iterations": REPLAY_CAP,
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


func _capture_names() -> Array:
	var out: Array = []
	var dir: DirAccess = DirAccess.open(CAPTURE_DIR)
	if dir == null:
		return out
	dir.list_dir_begin()
	var name: String = dir.get_next()
	while name != "":
		if not dir.current_is_dir() and name.ends_with(".json"):
			out.append(name)
		name = dir.get_next()
	dir.list_dir_end()
	out.sort()
	return out


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

extends SceneTree

## H2.7 iteration-budget anatomy. Offline, read-only, no runtime authority.
##
## H2.6 left one blocker: `two_storey_smoke` keeps 20 `iteration_cap` and its
## capture converges at 39 iterations when the budget is raised. "It passes at
## N" is not a diagnosis, so this harness replays every captured failure across
## a ladder of budgets and records the anatomy of the convergence rather than
## the verdict:
##
##   - the residual and its per-iteration reduction ratio;
##   - where the ratio changes regime (long linear tail vs terminal quadratic);
##   - how many cycles are detected, and at which iteration;
##   - half steps accepted, LM rescues accepted, damping used;
##   - the infinity-norm condition number of the Jacobian at the seed;
##   - the graph diameter and cycle count of the effective network;
##   - whether every budget that converges lands on the SAME root.
##
## `sim/core` is imported and never modified. `max_iterations` is an existing
## per-call option; the shipped DEFAULT_MAX_ITERATIONS is not touched here and
## must not be touched by this phase.

const SolverScript = preload("res://sim/core/Phase3CoupledPressureSolver.gd")
const CAPTURE_DIR := "res://runs/h27/captures"
const OUT_PATH := "res://runs/h27/budget_anatomy.json"
const BUDGETS := [24, 32, 40, 48, 64, 96, 128, 256]

var _solver = null


func _init() -> void:
	_solver = SolverScript.new()
	var report: Dictionary = {"budgets": BUDGETS, "captures": {}}
	for name in _capture_names():
		var capture: Dictionary = _load("%s/%s" % [CAPTURE_DIR, name])
		if capture.is_empty():
			continue
		report["captures"][name] = _analyse(capture)
		print("analysed %s" % name)
	var file: FileAccess = FileAccess.open(OUT_PATH, FileAccess.WRITE)
	if file == null:
		push_error("cannot write " + OUT_PATH)
		quit(1)
		return
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	print("H27_BUDGET_ANATOMY_WRITTEN %s" % OUT_PATH)
	print("H27_BUDGET_ANATOMY_PASS")
	quit(0)


func _analyse(capture: Dictionary) -> Dictionary:
	var out: Dictionary = {"static": _static_shape(capture), "runs": []}
	var roots: Array = []
	for raw_budget in BUDGETS:
		var budget: int = int(raw_budget)
		var solved: Dictionary = _solve(capture, budget)
		var history: Array = solved.get("residual_history", [])
		var ratios: Array = []
		for index in range(1, history.size()):
			var previous: float = float(history[index - 1])
			ratios.append(
				float(history[index]) / previous if previous > 0.0 else NAN
			)
		var converged: bool = bool(solved.get("converged", false))
		var row: Dictionary = {
			"budget": budget,
			"converged": converged,
			"limiting_reason": String(solved.get("limiting_reason", "?")),
			"iterations": int(solved.get("iterations", 0.0)),
			"final_residual": float(solved.get("normalized_residual", NAN))
					if converged else float(history[history.size() - 1]),
			"residual_history": history,
			"reduction_ratios": ratios,
			"cycle_detect_total": float(solved.get("cycle_detect_total", 0.0)),
			"half_step_attempts": float(
				solved.get("analytic_half_step_attempt_total", 0.0)
			),
			"half_step_accepts": float(
				solved.get("analytic_half_step_accept_total", 0.0)
			),
			"lm_accepted": float(solved.get("rescue_accepted", 0.0)),
			"damping_history": solved.get("damping_history", []),
		}
		if converged:
			roots.append(solved.get("gauge_pressure_by_room", {}))
		out["runs"].append(row)
	# Do every converging budget agree on the answer, to the last bit?
	out["root_agreement"] = _root_agreement(roots)
	return out


func _root_agreement(roots: Array) -> Dictionary:
	if roots.size() < 2:
		return {"compared": roots.size(), "identical": roots.size() == 1,
				"max_abs_delta_pa": 0.0}
	var first: Dictionary = roots[0]
	var worst: float = 0.0
	for index in range(1, roots.size()):
		var other: Dictionary = roots[index]
		for key in first.keys():
			worst = maxf(
				worst, absf(float(first[key]) - float(other.get(key, NAN)))
			)
	return {
		"compared": roots.size(),
		"identical": worst == 0.0,
		"max_abs_delta_pa": worst,
	}


## Network shape and conditioning, which is what any topology-based budget
## policy would have to be a function of.
func _static_shape(capture: Dictionary) -> Dictionary:
	var context: Dictionary = _context(capture, 24)
	var room_keys: Array = context["room_keys"]
	var count: int = room_keys.size()

	# Adjacency over interior openings only.
	var adjacency: Dictionary = {}
	for index in range(count):
		adjacency[index] = []
	var interior_links: int = 0
	var exterior_links: int = 0
	for raw_opening in context["openings"]:
		var opening: Dictionary = raw_opening
		var a: int = int(opening["index_a"])
		var b: int = int(opening["index_b"])
		if a >= 0 and b >= 0:
			adjacency[a].append(b)
			adjacency[b].append(a)
			interior_links += 1
		else:
			exterior_links += 1

	var diameter: int = 0
	for start in range(count):
		var far: int = _eccentricity(adjacency, start, count)
		diameter = maxi(diameter, far)

	var seed_pressure: Array[float] = []
	for room_key in room_keys:
		seed_pressure.append(float(context["rooms"][room_key]["gauge_pressure_pa"]))
	var evaluation: Dictionary = _solver._evaluate(context, seed_pressure)
	var condition: float = NAN
	if bool(evaluation.get("valid", false)):
		condition = _condition_inf(context, seed_pressure, evaluation, count)

	return {
		"rooms": count,
		"interior_links": interior_links,
		"exterior_links": exterior_links,
		"diameter": diameter,
		"independent_cycles": maxi(interior_links - count + 1, 0),
		"seed_residual": float(evaluation.get("normalized_residual", NAN)),
		"jacobian_condition_inf": condition,
	}


func _eccentricity(adjacency: Dictionary, start: int, count: int) -> int:
	var distance: Array[int] = []
	distance.resize(count)
	for index in range(count):
		distance[index] = -1
	distance[start] = 0
	var queue: Array[int] = [start]
	var head: int = 0
	var far: int = 0
	while head < queue.size():
		var current: int = queue[head]
		head += 1
		for raw_next in adjacency[current]:
			var next: int = int(raw_next)
			if distance[next] < 0:
				distance[next] = distance[current] + 1
				far = maxi(far, distance[next])
				queue.append(next)
	return far


## kappa_inf(J) = ||J||_inf * ||J^-1||_inf. The inverse is built column by
## column with the solver's own linear solve, so the number describes the exact
## system the solver works with.
func _condition_inf(
		context: Dictionary, pressure: Array[float],
		evaluation: Dictionary, count: int
	) -> float:
	var h: float = float(context["jacobian_step_pa"])
	var jacobian: Array = []
	for row in range(count):
		var values: Array[float] = []
		values.resize(count)
		jacobian.append(values)
	for column in range(count):
		var perturbed: Array[float] = pressure.duplicate()
		perturbed[column] = perturbed[column] + h
		var forward: Dictionary = _solver._evaluate(context, perturbed)
		if not bool(forward.get("valid", false)):
			return NAN
		for row in range(count):
			jacobian[row][column] = (
				float(forward["residual"][row])
				- float(evaluation["residual"][row])
			) / h

	var inverse: Array = []
	for row in range(count):
		var values: Array[float] = []
		values.resize(count)
		inverse.append(values)
	for column in range(count):
		var basis: Array[float] = []
		for row in range(count):
			basis.append(1.0 if row == column else 0.0)
		var solution: Array = _solver._solve_linear_system(jacobian, basis)
		if solution.is_empty():
			return INF
		for row in range(count):
			inverse[row][column] = float(solution[row])

	return _norm_inf(jacobian, count) * _norm_inf(inverse, count)


func _norm_inf(matrix: Array, count: int) -> float:
	var worst: float = 0.0
	for row in range(count):
		var total: float = 0.0
		for column in range(count):
			total += absf(float(matrix[row][column]))
		worst = maxf(worst, total)
	return worst


func _solve(capture: Dictionary, budget: int) -> Dictionary:
	var input: Dictionary = capture["input"]
	var rooms: Dictionary = {}
	for raw_key in input["rooms"].keys():
		rooms[String(raw_key)] = _number_dictionary(input["rooms"][raw_key])
	var sources: Dictionary = {}
	for raw_key in input["sources"].keys():
		sources[String(raw_key)] = _number_dictionary(input["sources"][raw_key])
	var solver = SolverScript.new()
	return solver.solve_coupled_pressure(
		rooms, _openings(input), sources,
		_number(input, "dt"), _number(input, "reference_temp_c"),
		_options(capture, budget)
	)


func _context(capture: Dictionary, budget: int) -> Dictionary:
	var input: Dictionary = capture["input"]
	var rooms: Dictionary = {}
	for raw_key in input["rooms"].keys():
		rooms[String(raw_key)] = _number_dictionary(input["rooms"][raw_key])
	var sources: Dictionary = {}
	for raw_key in input["sources"].keys():
		sources[String(raw_key)] = _number_dictionary(input["sources"][raw_key])
	return _solver._build_context(
		rooms, _openings(input), sources,
		_number(input, "dt"), _number(input, "reference_temp_c"),
		_options(capture, budget)
	)


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


func _options(capture: Dictionary, budget: int) -> Dictionary:
	var defaults: Dictionary = capture["solver_defaults"]
	return {
		"residual_tolerance": _number(defaults, "residual_tolerance"),
		"max_iterations": budget,
		"dp_regularization_pa": _number(defaults, "dp_regularization_pa"),
		"jacobian_step_pa": _number(defaults, "jacobian_step_pa"),
		"band_segments": int(defaults["band_segments"]),
		"max_damping_halvings": int(defaults["max_damping_halvings"]),
	}


func _capture_names() -> Array:
	var out: Array = []
	var dir: DirAccess = DirAccess.open(CAPTURE_DIR)
	if dir == null:
		push_error("capture dir missing: " + CAPTURE_DIR)
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

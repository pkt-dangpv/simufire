extends SceneTree

## H2.7: the five large-network captures, replayed against the shipped solver.
##
## Four are the undetected period-2 orbit that H2.7 diagnosed: the step cosine
## sits at -0.9999 through a long stall, but the H2.5j detector demands BOTH
## consecutive model gain ratios below 0.05 and the gain itself alternates, so
## the conjunction never fires and the solve runs out of iterations. They must
## all still end at `iteration_cap` on exactly 24 iterations until H2.8 changes
## the detector.
##
## The fifth is deliberately NOT one of those. `uk_bungalow_smoke` damps on
## every iteration, so `previous_full_step` is cleared each time and the
## detector is structurally unreachable; it exhausts its single LM rescue and
## dies as `damping_exhausted` at 12 iterations, and stays that way even at 256.
## Keeping it in the same fixture is the point: it pins the distinction.
##
## No solver change is asserted here and none is authorised. `max_iterations`
## is overridden only for the two offline probes at the end, through the
## existing per-call option; the shipped default is untouched.

const SolverScript = preload("res://sim/core/Phase3CoupledPressureSolver.gd")
const DATA := "res://tests/fixtures/data"

# name, expected limiting reason, expected iterations at the shipped cap
const CASES := [
	["coupled_solver_iteration_cap_two_floor_stairwell", "iteration_cap", 24],
	["coupled_solver_iteration_cap_two_storey_smoke", "iteration_cap", 24],
	["coupled_solver_iteration_cap_three_bed_apartment", "iteration_cap", 24],
	["coupled_solver_iteration_cap_flashover_simple_house", "iteration_cap", 24],
	["coupled_solver_damping_exhausted_uk_bungalow", "damping_exhausted", 12],
]

## Budget at which each orbit does close, measured in H2.7. The
## `damping_exhausted` case is absent on purpose: no budget closes it.
const CLOSES_AT := {
	"coupled_solver_iteration_cap_two_floor_stairwell": 25,
	"coupled_solver_iteration_cap_two_storey_smoke": 39,
	"coupled_solver_iteration_cap_three_bed_apartment": 25,
	"coupled_solver_iteration_cap_flashover_simple_house": 28,
}

var _failed: bool = false


func _init() -> void:
	for raw_case in CASES:
		var entry: Array = raw_case
		_check(String(entry[0]), String(entry[1]), int(entry[2]))
	_check_orbit_cases_close_with_more_budget()
	_check_damping_case_is_not_a_budget_problem()
	_check_negative_controls()
	if _failed:
		quit(1)
		return
	print("PHASE3_F33V3H27_LARGE_NETWORK_CAPTURES_PASS")
	quit(0)


func _check(name: String, reason: String, iterations: int) -> void:
	var capture: Dictionary = _load("%s/%s.json" % [DATA, name])
	if capture.is_empty():
		_failed = true
		return
	_assert(
		String(capture.get("schema_version", ""))
				== "simufire_coupled_solver_failure_v1",
		name + ": schema version"
	)
	_assert(
		String(capture.get("requested_failure_mode", "")) == reason,
		name + ": capture records the selector it was taken with"
	)

	var first: Dictionary = _solve(capture, 0)
	var second: Dictionary = _solve(capture, 0)
	_assert(
		not bool(first.get("converged", true)),
		name + ": still fails at the shipped cap"
	)
	_assert(
		String(first.get("limiting_reason", "")) == reason,
		"%s: limiting reason is %s, got '%s'"
				% [name, reason, String(first.get("limiting_reason", ""))]
	)
	_assert(
		int(first.get("iterations", 0.0)) == iterations,
		"%s: %d iterations, got %d"
				% [name, iterations, int(first.get("iterations", 0.0))]
	)

	# The recorded history must be reproduced, not merely the verdict.
	var observed: Array = capture["observed_failure"]["residual_history"]
	var replayed: Array = first["residual_history"]
	_assert(
		replayed.size() == observed.size(),
		"%s: residual history length %d vs recorded %d"
				% [name, replayed.size(), observed.size()]
	)
	var worst: float = 0.0
	for index in range(mini(replayed.size(), observed.size())):
		worst = maxf(
			worst, absf(float(replayed[index]) - _decode(observed[index]))
		)
	_assert(worst == 0.0, name + ": residual history reproduced exactly")

	for field in [
		"converged", "limiting_reason", "iterations", "residual_history",
		"cycle_detect_total", "analytic_half_step_accept_total",
		"rescue_accepted",
	]:
		_assert(first[field] == second[field], "%s: deterministic %s" % [name, field])


## The four orbits are budget-closable; that is what makes them orbits rather
## than genuine non-convergence. Recording the exact figure keeps H2.8 honest
## about how much the detector fix is worth.
func _check_orbit_cases_close_with_more_budget() -> void:
	for raw_name in CLOSES_AT.keys():
		var name: String = String(raw_name)
		var capture: Dictionary = _load("%s/%s.json" % [DATA, name])
		if capture.is_empty():
			_failed = true
			continue
		var solved: Dictionary = _solve(capture, 256)
		_assert(
			bool(solved.get("converged", false)),
			name + ": converges once the budget is raised"
		)
		_assert(
			int(solved.get("iterations", 0.0)) == int(CLOSES_AT[name]),
			"%s: closes at %d iterations, got %d"
					% [name, int(CLOSES_AT[name]), int(solved.get("iterations", 0.0))]
		)
		_assert(
			float(solved.get("normalized_residual", 1.0)) <= 1.0e-12,
			name + ": meets the unchanged tolerance"
		)


## The distinction the fixture exists to pin: this one is not a budget problem.
func _check_damping_case_is_not_a_budget_problem() -> void:
	var name := "coupled_solver_damping_exhausted_uk_bungalow"
	var capture: Dictionary = _load("%s/%s.json" % [DATA, name])
	if capture.is_empty():
		_failed = true
		return
	for budget in [24, 64, 256]:
		var solved: Dictionary = _solve(capture, budget)
		_assert(
			not bool(solved.get("converged", true)),
			"%s: still fails at budget %d" % [name, budget]
		)
		_assert(
			String(solved.get("limiting_reason", "")) == "damping_exhausted",
			"%s: stays damping_exhausted at budget %d" % [name, budget]
		)
		_assert(
			int(solved.get("iterations", 0.0)) == 12,
			"%s: raising the budget does not change it at %d" % [name, budget]
		)
	# It never enters the orbit at all, which is why the detector cannot help.
	var solved_default: Dictionary = _solve(capture, 0)
	_assert(
		float(solved_default.get("cycle_detect_total", -1.0)) == 0.0,
		name + ": no cycle is ever detected"
	)


## A capture that survives rounding or edits is not pinning anything.
##
## The discriminator is the RESIDUAL HISTORY, not the iteration count. These
## solves spend most of their iterations inside a period-2 orbit whose length is
## robust to small perturbations, so a one percent edit can still land on 39
## iterations while following a visibly different trajectory. An earlier version
## of this control compared iteration counts and was therefore vacuous.
func _check_negative_controls() -> void:
	var name := "coupled_solver_iteration_cap_two_storey_smoke"
	var capture: Dictionary = _load("%s/%s.json" % [DATA, name])
	if capture.is_empty():
		_failed = true
		return
	var reference: Array = _solve(capture, 0)["residual_history"]

	for mutation in ["round", "opening", "source"]:
		var mutated: Array = _solve(capture, 0, String(mutation))["residual_history"]
		_assert(
			not _same_history(reference, mutated),
			"negative control: '%s' must not reproduce the residual history"
					% String(mutation)
		)

	# The expected limiting reason must itself be discriminating: the same
	# input under a raised budget stops being an iteration_cap.
	var raised: Dictionary = _solve(capture, 256)
	_assert(
		String(raised.get("limiting_reason", "")) != "iteration_cap",
		"negative control: at budget 256 the reason is no longer iteration_cap"
	)


func _same_history(first: Array, second: Array) -> bool:
	if first.size() != second.size():
		return false
	for index in range(first.size()):
		if float(first[index]) != float(second[index]):
			return false
	return true


func _solve(capture: Dictionary, budget: int, mutate: String = "") -> Dictionary:
	var input: Dictionary = capture["input"]
	var rooms: Dictionary = {}
	for raw_key in input["rooms"].keys():
		rooms[String(raw_key)] = _numbers(input["rooms"][raw_key], mutate == "round")
	var sources: Dictionary = {}
	var source_keys: Array = input["sources"].keys()
	for raw_key in source_keys:
		var source: Dictionary = _numbers(
			input["sources"][raw_key], mutate == "round"
		)
		if mutate == "source" and String(raw_key) == String(source_keys[0]):
			source["mass_kg"] = float(source["mass_kg"]) * 1.01
		sources[String(raw_key)] = source
	var openings: Array = []
	for index in range(input["openings"].size()):
		var opening: Dictionary = input["openings"][index]
		var width: float = _number(opening, "width_m", mutate == "round")
		if mutate == "opening" and index == 0:
			width = width * 1.01
		openings.append({
			"opening_id": int(opening["opening_id"]),
			"room_a_id": int(opening["room_a_id"]),
			"room_b_id": int(opening["room_b_id"]),
			"bottom_m": _number(opening, "bottom_m", mutate == "round"),
			"top_m": _number(opening, "top_m", mutate == "round"),
			"width_m": width,
			"open_fraction": _number(opening, "open_fraction", mutate == "round"),
			"discharge_coeff": _number(
				opening, "discharge_coeff", mutate == "round"
			),
		})
	var defaults: Dictionary = capture["solver_defaults"]
	var options: Dictionary = {
		"residual_tolerance": _number(defaults, "residual_tolerance"),
		"max_iterations": budget if budget > 0 else int(defaults["max_iterations"]),
		"dp_regularization_pa": _number(defaults, "dp_regularization_pa"),
		"jacobian_step_pa": _number(defaults, "jacobian_step_pa"),
		"band_segments": int(defaults["band_segments"]),
		"max_damping_halvings": int(defaults["max_damping_halvings"]),
	}
	var solver = SolverScript.new()
	return solver.solve_coupled_pressure(
		rooms, openings, sources,
		_number(input, "dt", mutate == "round"),
		_number(input, "reference_temp_c", mutate == "round"),
		options
	)


func _load(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("capture missing: " + path)
		return {}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("cannot open: " + path)
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("capture is not a JSON object: " + path)
		return {}
	return parsed


## The `d` field is a readable decimal and `x` is the exact IEEE754 pattern.
##
## `d` carries seventeen significant digits, so it round-trips a double exactly
## and reading it is NOT a rounding control - it reproduces the capture bit for
## bit. The genuine control has to discard precision, so `round` truncates to
## six significant figures, which is roughly what a hand-transcribed artifact
## would preserve.
func _decode(leaf, round_it: bool = false) -> float:
	var value: float = 0.0
	if typeof(leaf) == TYPE_DICTIONARY and leaf.has("x"):
		var hex: String = String(leaf["x"])
		var bytes: PackedByteArray = PackedByteArray()
		for index in range(0, hex.length(), 2):
			bytes.append(hex.substr(index, 2).hex_to_int())
		value = bytes.decode_double(0) if bytes.size() == 8 \
				else float(String(leaf["d"]))
	else:
		value = float(String(leaf))
	return _to_significant(value, 6) if round_it else value


func _to_significant(value: float, digits: int) -> float:
	if value == 0.0 or not is_finite(value):
		return value
	var magnitude: float = floor(log(absf(value)) / log(10.0))
	var scale: float = pow(10.0, float(digits - 1) - magnitude)
	return round(value * scale) / scale


func _number(source: Dictionary, key: String, round_it: bool = false) -> float:
	return _decode(source[key], round_it)


func _numbers(source: Dictionary, round_it: bool = false) -> Dictionary:
	var out: Dictionary = {}
	for raw_key in source.keys():
		out[String(raw_key)] = _decode(source[raw_key], round_it)
	return out


func _assert(condition: bool, label: String) -> void:
	if not condition:
		push_error("FAIL: " + label)
		_failed = true

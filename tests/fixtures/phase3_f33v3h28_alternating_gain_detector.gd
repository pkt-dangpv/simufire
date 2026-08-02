extends SceneTree

## H2.8: the alternating-gain cycle detector.
##
## H2.5j asked for BOTH consecutive model gain ratios to be below the
## threshold. H2.7 measured four large-network captures and found the pair
## straddles it - roughly 0.08 on one phase of the orbit and -0.01 on the other
## - while the step cosine sits at -0.9999 the whole time. The conjunction
## therefore never fired and the orbit ran to the iteration cap.
##
## H2.8 takes the minimum of the pair against the SAME threshold. Every
## geometric condition is unchanged: two accepted full steps, a previous step
## to compare against, and a period-2 cosine.
##
## This fixture pins both regimes, the case the change must NOT touch, and the
## boundary conditions where the detector must stay silent.

const SolverScript = preload("res://sim/core/Phase3CoupledPressureSolver.gd")
const DATA := "res://tests/fixtures/data"

## The four H2.7 orbits: each must now close inside the unchanged cap of 24,
## through the alternating-gain branch, at the iteration count H2.7 predicted.
const ALTERNATING := {
	"coupled_solver_iteration_cap_two_floor_stairwell": 11,
	"coupled_solver_iteration_cap_two_storey_smoke": 10,
	"coupled_solver_iteration_cap_three_bed_apartment": 14,
	"coupled_solver_iteration_cap_flashover_simple_house": 12,
}

## Captures whose orbit already had both phases low. They must behave exactly
## as before, through the original branch, at the same iteration count.
const BOTH_PHASES_LOW := {
	"coupled_solver_iteration_cap_corridor_chain": 7,
	"coupled_solver_iteration_cap_after_rescue_corridor_chain": 4,
}

## Captures that never enter an orbit at all.
const NO_CYCLE := {
	# H2.10 later supersedes LM on this dead end and closes one iteration sooner.
	"coupled_solver_failure_corridor_chain": 5,
	"coupled_solver_failure_r0_window_360": 3,
}

var _failed: bool = false


func _init() -> void:
	_check_alternating_orbits_now_close()
	_check_both_phases_low_regime_is_untouched()
	_check_no_cycle_captures_are_untouched()
	_check_uk_bungalow_is_not_reclassified()
	_check_analytic_alternating_case()
	_check_detector_needs_both_conditions()
	_check_half_step_rejection_leaves_state_intact()
	_check_thresholds_are_unchanged()
	if _failed:
		quit(1)
		return
	print("PHASE3_F33V3H28_ALTERNATING_GAIN_DETECTOR_PASS")
	quit(0)


func _check_alternating_orbits_now_close() -> void:
	for raw_name in ALTERNATING.keys():
		var name: String = String(raw_name)
		var solved: Dictionary = _solve(name)
		_assert(
			bool(solved.get("converged", false)),
			name + ": converges inside the unchanged cap"
		)
		_assert(
			int(solved.get("iterations", 0.0)) <= 24,
			name + ": stays inside the cap of 24"
		)
		_assert(
			int(solved.get("iterations", 0.0)) == int(ALTERNATING[name]),
			"%s: closes in %d iterations, got %d"
					% [name, int(ALTERNATING[name]), int(solved.get("iterations", 0.0))]
		)
		_assert(
			float(solved.get("normalized_residual", 1.0)) <= 1.0e-12,
			name + ": meets the unchanged tolerance"
		)
		# It must be the NEW branch that fired, not the old one.
		_assert(
			float(solved.get("cycle_detect_alternating_gain_total", 0.0)) >= 1.0,
			name + ": detected through the alternating-gain branch"
		)
		_assert(
			float(solved.get("cycle_detect_both_phases_low_total", 0.0)) == 0.0,
			name + ": did not reach the original both-phases-low branch"
		)
		_assert(
			float(solved.get("analytic_half_step_accept_total", 0.0)) >= 1.0,
			name + ": the half step closed it"
		)
		# The LM budget must not have paid for this.
		_assert(
			float(solved.get("rescue_accepted", 0.0)) == 0.0,
			name + ": LM budget left unspent"
		)


func _check_both_phases_low_regime_is_untouched() -> void:
	for raw_name in BOTH_PHASES_LOW.keys():
		var name: String = String(raw_name)
		var solved: Dictionary = _solve(name)
		_assert(
			bool(solved.get("converged", false)),
			name + ": still converges"
		)
		_assert(
			int(solved.get("iterations", 0.0)) == int(BOTH_PHASES_LOW[name]),
			"%s: unchanged at %d iterations, got %d"
					% [name, int(BOTH_PHASES_LOW[name]),
						int(solved.get("iterations", 0.0))]
		)
		# Taking a minimum cannot change a pair that was already both-low.
		_assert(
			float(solved.get("cycle_detect_both_phases_low_total", 0.0)) >= 1.0,
			name + ": still classified as both phases low"
		)
		_assert(
			float(solved.get("cycle_detect_alternating_gain_total", 0.0)) == 0.0,
			name + ": not reclassified as alternating"
		)


func _check_no_cycle_captures_are_untouched() -> void:
	for raw_name in NO_CYCLE.keys():
		var name: String = String(raw_name)
		var solved: Dictionary = _solve(name)
		_assert(bool(solved.get("converged", false)), name + ": still converges")
		_assert(
			int(solved.get("iterations", 0.0)) == int(NO_CYCLE[name]),
			"%s: unchanged at %d iterations, got %d"
					% [name, int(NO_CYCLE[name]), int(solved.get("iterations", 0.0))]
		)
		_assert(
			float(solved.get("cycle_detect_total", 0.0)) == 0.0,
			name + ": a widened detector must not invent a cycle here"
		)


## H2.8 must still not claim this mode. It damps on every iteration, so its
## cycle detector remains structurally unreachable. H2.10 closes the separate
## donor-branch Jacobian defect through fail-only adaptive authority.
func _check_uk_bungalow_is_not_reclassified() -> void:
	var name := "coupled_solver_damping_exhausted_uk_bungalow"
	var solved: Dictionary = _solve(name)
	_assert(
		bool(solved.get("converged", false)),
		name + ": H2.10 closes the separate branch defect"
	)
	_assert(
		float(solved.get("adaptive_jacobian_accept_total", 0.0)) >= 1.0,
		name + ": adaptive Jacobian recovery is the authority"
	)
	_assert(
		float(solved.get("rescue_accepted", 1.0)) == 0.0,
		name + ": LM remains unused"
	)
	_assert(
		float(solved.get("cycle_detect_total", 0.0)) == 0.0,
		name + ": no cycle is detected even with the widened predicate"
	)


## Closed-form control, independent of any capture.
##
## min(a, b) < t must accept an alternating pair that straddles t, accept a pair
## already below it, and reject a pair entirely above it. The old conjunction
## accepts only the middle case; that difference IS the change.
func _check_analytic_alternating_case() -> void:
	var threshold := 0.05
	var alternating := [0.08, -0.01]
	var both_low := [0.0009, 0.0084]
	var both_high := [0.30, 0.42]

	_assert(
		minf(alternating[0], alternating[1]) < threshold,
		"analytic: alternating pair passes min-gain"
	)
	_assert(
		not (alternating[0] < threshold and alternating[1] < threshold),
		"analytic: alternating pair is exactly what the old conjunction missed"
	)
	_assert(
		minf(both_low[0], both_low[1]) < threshold
				and both_low[0] < threshold and both_low[1] < threshold,
		"analytic: a both-low pair is accepted by either formulation"
	)
	_assert(
		not (minf(both_high[0], both_high[1]) < threshold),
		"analytic: a both-high pair is still rejected"
	)
	# maxf decides the reported regime, and the two are mutually exclusive.
	_assert(
		maxf(alternating[0], alternating[1]) >= threshold,
		"analytic: the alternating pair is reported as alternating"
	)
	_assert(
		maxf(both_low[0], both_low[1]) < threshold,
		"analytic: the both-low pair is reported as both-low"
	)


## Both conditions are still required. A low gain without a period-2 cosine, or
## an opposing cosine without any low gain, must NOT fire.
func _check_detector_needs_both_conditions() -> void:
	var source: String = _read_solver()
	var body: String = source.split("func solve_coupled_pressure(", 1)[1]
	body = body.split("\nfunc ", 1)[0]
	var block: String = body.split("cycle_detected = (", 1)[1]
	block = block.split(")", 1)[0]
	_assert(
		block.contains("cycle_min_gain_ratio < CYCLE_GUARD_MIN_MODEL_GAIN_RATIO"),
		"the gain condition is present and uses the unchanged threshold"
	)
	_assert(
		block.contains("step_cosine < CYCLE_GUARD_MAX_STEP_COSINE"),
		"the cosine condition is still required"
	)
	_assert(block.contains("and"), "both conditions are conjoined")
	# The geometric preconditions are untouched.
	_assert(
		body.contains("if damping == 1.0 and not previous_full_step.is_empty():"),
		"two accepted full steps are still required"
	)


## A declined half step must leave everything alone and fall through.
func _check_half_step_rejection_leaves_state_intact() -> void:
	var source: String = _read_solver()
	var body: String = source.split("func solve_coupled_pressure(", 1)[1]
	body = body.split("\nfunc ", 1)[0]
	var start: int = body.find('result["analytic_half_step_attempt_total"] += 1.0')
	var accept: int = body.find(
		'result["analytic_half_step_accept_total"] += 1.0', start
	)
	_assert(start >= 0 and accept > start, "half step block is present")
	var before: String = body.substr(start, accept - start)
	for forbidden in [
		"pressure = half_pressure", "evaluation = half_evaluation",
		"norm = half_norm", "continue",
	]:
		_assert(
			not before.contains(forbidden),
			"no state write before acceptance: " + forbidden
		)
	_assert(
		body.contains("if is_finite(half_norm) and half_norm < norm:"),
		"acceptance still demands validity and strict descent"
	)


func _check_thresholds_are_unchanged() -> void:
	var source: String = _read_solver()
	for pair in [
		["const DEFAULT_MAX_ITERATIONS: int = 24", "iteration cap"],
		["const DEFAULT_RESIDUAL_TOLERANCE: float = 1.0e-12", "tolerance"],
		["const CYCLE_GUARD_MIN_MODEL_GAIN_RATIO: float = 0.05", "gain threshold"],
		["const CYCLE_GUARD_MAX_STEP_COSINE: float = -0.99", "cosine threshold"],
		["const CYCLE_ANALYTIC_HALF_STEP: float = 0.5", "half step factor"],
		["const LM_RESCUE_MAX_ACCEPTED_STEPS: int = 1", "LM budget"],
	]:
		_assert(source.contains(String(pair[0])), "unchanged: " + String(pair[1]))


func _read_solver() -> String:
	var file: FileAccess = FileAccess.open(
		"res://sim/core/Phase3CoupledPressureSolver.gd", FileAccess.READ
	)
	if file == null:
		_failed = true
		return ""
	var text: String = file.get_as_text()
	file.close()
	return text


func _solve(name: String) -> Dictionary:
	var path := "%s/%s.json" % [DATA, name]
	if not FileAccess.file_exists(path):
		push_error("capture missing: " + path)
		_failed = true
		return {}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	var capture: Dictionary = JSON.parse_string(file.get_as_text())
	file.close()
	var input: Dictionary = capture["input"]
	var rooms: Dictionary = {}
	for raw_key in input["rooms"].keys():
		rooms[String(raw_key)] = _numbers(input["rooms"][raw_key])
	var sources: Dictionary = {}
	for raw_key in input["sources"].keys():
		sources[String(raw_key)] = _numbers(input["sources"][raw_key])
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
	var solver = SolverScript.new()
	return solver.solve_coupled_pressure(
		rooms, openings, sources,
		_number(input, "dt"), _number(input, "reference_temp_c"),
		{
			"residual_tolerance": _number(defaults, "residual_tolerance"),
			"max_iterations": int(defaults["max_iterations"]),
			"dp_regularization_pa": _number(defaults, "dp_regularization_pa"),
			"jacobian_step_pa": _number(defaults, "jacobian_step_pa"),
			"band_segments": int(defaults["band_segments"]),
			"max_damping_halvings": int(defaults["max_damping_halvings"]),
		}
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


func _numbers(source: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for raw_key in source.keys():
		out[String(raw_key)] = _decode(source[raw_key])
	return out


func _assert(condition: bool, label: String) -> void:
	if not condition:
		push_error("FAIL: " + label)
		_failed = true

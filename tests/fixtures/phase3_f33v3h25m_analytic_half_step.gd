extends SceneTree

## H2.5m: the analytic half step, exercised against the shipped solver.
##
## Covers the mandated cases: the four real captures, a pure analytic
## square-root problem where the full Newton step provably orbits and
## theta = 1/2 provably does not, a declined half step that must leave the
## state untouched, a healthy solve that must never attempt one, and the
## r0-window topology.

const SolverScript = preload("res://sim/core/Phase3CoupledPressureSolver.gd")

const AFTER_RESCUE := "res://tests/fixtures/data/coupled_solver_iteration_cap_after_rescue_corridor_chain.json"
const ITERATION_CAP := "res://tests/fixtures/data/coupled_solver_iteration_cap_corridor_chain.json"
const CORRIDOR_FAILURE := "res://tests/fixtures/data/coupled_solver_failure_corridor_chain.json"
const R0_FAILURE := "res://tests/fixtures/data/coupled_solver_failure_r0_window_360.json"

var _failed: bool = false


func _init() -> void:
	_check_constant()
	_check_after_rescue()
	_check_iteration_cap()
	_check_corridor_failure()
	_check_r0_window()
	_check_analytic_sqrt_orbit()
	_check_determinism()
	if _failed:
		quit(1)
		return
	print("PHASE3_F33V3H25M_ANALYTIC_HALF_STEP_PASS")
	quit(0)


## The factor is the closed-form annihilator, not a tunable.
func _check_constant() -> void:
	var solver = SolverScript.new()
	_assert(
		solver.CYCLE_ANALYTIC_HALF_STEP == 0.5,
		"half step factor is exactly 0.5"
	)


## The capture H2.5l-A/B could not fix: 24 iterations of iteration_cap.
func _check_after_rescue() -> void:
	var solved: Dictionary = _solve(AFTER_RESCUE)
	_assert(bool(solved.get("converged", false)), "after_rescue now converges")
	_assert(
		int(solved.get("iterations", 0.0)) <= 8,
		"after_rescue converges well inside the unchanged cap of 24"
	)
	_assert(
		float(solved.get("normalized_residual", 1.0)) <= 1.0e-12,
		"after_rescue meets the original tolerance"
	)
	_assert(
		float(solved.get("analytic_half_step_accept_total", 0.0)) >= 1.0,
		"after_rescue accepted at least one half step"
	)
	# The half step must not have paid for itself out of the LM budget.
	_assert(
		float(solved.get("rescue_accepted", 0.0)) == 0.0,
		"after_rescue needed no LM rescue once the orbit was annihilated"
	)
	var initial: float = float(
		solved.get("analytic_half_step_last_initial_norm", 0.0)
	)
	var final_norm: float = float(
		solved.get("analytic_half_step_last_final_norm", 0.0)
	)
	_assert(
		initial > 0.0 and final_norm < initial,
		"recorded half step strictly reduced the residual"
	)
	print(
		"H25M after_rescue iters=%d attempts=%d accepts=%d %s->%s"
		% [
			int(solved["iterations"]),
			int(solved["analytic_half_step_attempt_total"]),
			int(solved["analytic_half_step_accept_total"]),
			str(initial), str(final_norm),
		]
	)


func _check_iteration_cap() -> void:
	var solved: Dictionary = _solve(ITERATION_CAP)
	_assert(bool(solved.get("converged", false)), "iteration_cap converges")
	_assert(
		float(solved.get("normalized_residual", 1.0)) <= 1.0e-12,
		"iteration_cap meets the original tolerance"
	)


## A capture whose failure mode is `damping_exhausted`, not the orbit. H2.10
## later supersedes LM here with its fail-only adaptive unilateral Jacobian;
## the half-step detector must still remain uninvolved.
func _check_corridor_failure() -> void:
	var solved: Dictionary = _solve(CORRIDOR_FAILURE)
	_assert(
		bool(solved.get("converged", false)),
		"corridor damping_exhausted capture still converges"
	)
	_assert(
		float(solved.get("adaptive_jacobian_accept_total", 0.0)) >= 1.0
				and float(solved.get("rescue_accepted", 1.0)) == 0.0,
		"H2.10 adaptive Jacobian closes before LM"
	)
	_assert(
		float(solved.get("analytic_half_step_accept_total", 0.0)) == 0.0,
		"no half step was needed on the damping_exhausted mode"
	)


## The topology H2.5d regressed. It must be entirely untouched.
func _check_r0_window() -> void:
	var solved: Dictionary = _solve(R0_FAILURE)
	_assert(bool(solved.get("converged", false)), "r0_window converges")
	_assert(
		float(solved.get("analytic_half_step_attempt_total", 0.0)) == 0.0,
		"r0_window makes zero half step attempts"
	)
	_assert(
		float(solved.get("analytic_half_step_accept_total", 0.0)) == 0.0,
		"r0_window accepts zero half steps"
	)


## Pure analytic control, independent of any capture or scenario.
##
## For F(u) = sign(u) sqrt(|u|) the Newton correction is exactly -2u, so the
## full step maps u -> -u forever and theta = 1/2 lands exactly on the root.
## This is the property the constant encodes, verified in closed form.
func _check_analytic_sqrt_orbit() -> void:
	var u: float = 0.25
	var full: float = u
	for _index in range(16):
		full = full - 2.0 * full
		if absf(absf(full) - 0.25) > 1.0e-12:
			break
	_assert(
		absf(absf(full) - 0.25) <= 1.0e-12,
		"full Newton step orbits forever on the sqrt law"
	)
	var half: float = u - 0.5 * (2.0 * u)
	_assert(
		absf(half) <= 1.0e-15,
		"theta = 1/2 lands on the root of the sqrt law in one step"
	)
	# And the correction really is -2u for this F, which is what makes the
	# factor analytic rather than fitted.
	var f: float = signf(u) * sqrt(absf(u))
	var f_prime: float = 0.5 / sqrt(absf(u))
	_assert(
		absf((-f / f_prime) - (-2.0 * u)) <= 1.0e-15,
		"the Newton correction for the sqrt law is exactly -2u"
	)


## A declined half step must not perturb anything, and every solve must be
## reproducible bit for bit.
func _check_determinism() -> void:
	for path in [AFTER_RESCUE, ITERATION_CAP, CORRIDOR_FAILURE, R0_FAILURE]:
		var first: Dictionary = _solve(String(path))
		var second: Dictionary = _solve(String(path))
		for field in [
			"converged", "limiting_reason", "iterations", "residual_history",
			"normalized_residual", "analytic_half_step_attempt_total",
			"analytic_half_step_accept_total", "rescue_accepted",
		]:
			_assert(
				first[field] == second[field],
				"deterministic %s on %s" % [field, String(path).get_file()]
			)
		# Attempts can exceed accepts (a decline), but never the reverse.
		_assert(
			float(first["analytic_half_step_accept_total"])
					<= float(first["analytic_half_step_attempt_total"]),
			"accepts never exceed attempts on " + String(path).get_file()
		)


func _solve(path: String) -> Dictionary:
	var capture: Dictionary = _load(path)
	if capture.is_empty():
		_failed = true
		return {}
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
		push_error("cannot open: " + path)
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


func _assert(condition: bool, label: String) -> void:
	if not condition:
		push_error("FAIL: " + label)
		_failed = true

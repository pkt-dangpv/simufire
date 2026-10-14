extends SceneTree

## Exercises the real Main dispatcher. The probe reproduces only the documented
## engine clock contract; no assertion here is evidence about fire physics.
class MainHarness extends "res://Main.gd":
	var sampled_real_s: float = 0.0
	func _ready() -> void:
		pass

	func _update_views() -> void:
		pass

	func _update_views_for_frame() -> void:
		pass

	func _sample_live_charts(delta: float) -> void:
		sampled_real_s += delta

class EngineProbe extends "res://sim/core/SimulationEngine.gd":
	var steps: int = 0

	func _ready() -> void:
		pass

	func _exit_tree() -> void:
		pass

	func step(delta: float) -> void:
		steps += 1
		sim_time_s += sim_fixed_dt if sim_fixed_dt > 0.0 else maxf(0.0, delta * time_scale)

var checks: int = 0
var failures: Array[String] = []
var examples: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok and failures.size() < 60:
		failures.append(label)


func _case(label: String, phases: Array, fixed_dt: float = 0.0) -> void:
	var main := MainHarness.new()
	main.engine = EngineProbe.new()
	main.add_child(main.engine)
	main.engine.sim_fixed_dt = fixed_dt
	main.playback_paused = false
	var expected: float = 0.0
	var elapsed_real: float = 0.0
	for phase: Array in phases:
		main.engine.time_scale = float(phase[0])
		for tick: int in range(int(phase[1])):
			var delta: float = float(phase[2])
			elapsed_real += delta
			expected += fixed_dt if fixed_dt > 0.0 else delta * main.engine.time_scale
			main._physics_process(delta)
			var observed: float = main.engine.sim_time_s
			check(observed <= expected + 1.0e-8, label + ": no simulated time invented")
			check(expected - observed < main.SIM_STEP_S + 1.0e-8,
				label + ": no accumulated time lost")
			check(main.sampled_real_s <= elapsed_real + 1.0e-8,
				label + ": chart wall time not invented")
			if fixed_dt > 0.0:
				check(absf(expected - observed) < 1.0e-8, label + ": fixed-step contract")
	var before: float = main.engine.sim_time_s
	main.playback_paused = true
	main._physics_process(20.0)
	check(main.engine.sim_time_s == before, label + ": pause does not advance")
	if label == "one_to_twenty_pending":
		examples[label] = {"expected_s": expected, "observed_s": before}
		check(absf(expected - before) < 1.0e-8, "one_to_twenty_pending: exact 0.40 s")
		check(absf(main.sampled_real_s - elapsed_real) < 1.0e-8,
			"one_to_twenty_pending: chart cadence preserves wall time")
	main.free()


func _run() -> void:
	_case("one_to_twenty_pending", [[1.0, 4, 1.0 / 60.0], [20.0, 1, 1.0 / 60.0]])
	for speed: float in MainHarness.TIME_SPEEDS:
		_case("constant_" + str(speed), [[speed, 240, 1.0 / 60.0]])
		_case("fixed_" + str(speed), [[speed, 20, 1.0 / 60.0]], 1.0 / 12.0)
		for next_speed: float in MainHarness.TIME_SPEEDS:
			for pending_ticks: int in range(5):
				_case("transition_" + str(speed) + "_" + str(next_speed)
					+ "_" + str(pending_ticks), [
					[speed, pending_ticks, 1.0 / 60.0],
					[next_speed, 90, 1.0 / 60.0]])
	_case("variable_callbacks", [[1.0, 30, 1.0 / 120.0], [2.0, 30, 1.0 / 30.0],
		[0.25, 30, 1.0 / 45.0], [20.0, 30, 1.0 / 60.0], [0.5, 30, 1.0 / 60.0]])
	print("PRODUCT_DISPATCH_CONTRACT " + JSON.stringify({"checks": checks,
		"failures": failures, "failure_count": failures.size(), "examples": examples,
		"scope": "native Main dispatch, not physical convergence or rendered FPS"}))
	quit(0 if failures.is_empty() else 1)

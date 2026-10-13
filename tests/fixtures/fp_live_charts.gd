extends SceneTree

## UI control only: inherited Main dispatch and real chart; not a physics test.
class MainHarness extends "res://Main.gd":
	func _ready() -> void:
		pass

	func _update_views() -> void:
		pass

	func _update_views_for_frame() -> void:
		pass

class EngineProbe extends "res://sim/core/SimulationEngine.gd":
	var exports: int = 0
	var steps: int = 0

	func _ready() -> void:
		pass

	func _exit_tree() -> void:
		pass

	func step(delta: float) -> void:
		steps += 1
		sim_time_s += delta

	func get_state() -> Dictionary:
		exports += 1
		return {"1": {"name": "Test room", "temp_upper_c": 25.0}}

var checks: int = 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)


func _run() -> void:
	var main := MainHarness.new()
	main.set_physics_process(false)
	# Keep the harness outside the tree: inherited @onready paths belong to
	# SimulationScene, not this isolated control. Only the real UI enters it.
	main.engine = EngineProbe.new()
	main.add_child(main.engine)
	main._live_overlay = main.LiveChartsOverlayScene.instantiate()
	root.add_child(main._live_overlay)
	main._live_charts_button = Button.new()
	main._live_charts_button.toggle_mode = true
	root.add_child(main._live_charts_button)
	main._live_overlay.reset()
	main._sync_view_mode()
	check(main._live_overlay.visible, "default visible outside FP")
	check(main._live_charts_button.visible, "button outside FP")
	main.playback_paused = false
	main._physics_process(0.3)
	check(main.engine.exports == 1, "normal sampling outside FP")
	var history: PackedByteArray = var_to_bytes(main._live_overlay._rooms)
	main._set_first_person_enabled(true)
	check(not main._live_overlay.visible, "hidden in FP")
	check(not main._live_charts_button.visible, "button hidden in FP")
	check(not main._live_overlay.can_process(), "chart processing suspended in FP")
	check(not main._live_overlay._chart.can_process(), "child processing suspended in FP")
	check(main._live_sample_accum_s == 0.0, "accumulator cleared on entry")
	var before: float = main.engine.sim_time_s
	var steps: int = main.engine.steps
	for index: int in range(60):
		main._physics_process(1.0 / 60.0)
	check(main.engine.steps == steps + 12, "one engine dispatch per reference step in FP")
	check(is_equal_approx(main.engine.sim_time_s - before, 1.0), "FP dispatch clock unchanged")
	check(main.engine.exports == 1, "no chart state exports in FP")
	check(var_to_bytes(main._live_overlay._rooms) == history, "no hidden history growth in FP")
	check(main._live_sample_accum_s == 0.0, "no FP accumulator growth")
	main._on_live_charts_toggled(true)
	check(not main._live_overlay.visible, "toggle cannot reveal chart in FP")
	main._set_3d_view_enabled(true)
	check(not main.first_person_enabled, "3D exits FP through shared sync")
	check(main._live_overlay.visible, "restore requested chart in 3D")
	check(main._live_charts_button.visible, "restore button in 3D")
	check(main._live_overlay.can_process(), "restore chart processing")
	check(var_to_bytes(main._live_overlay._rooms) == history, "existing history preserved")
	main._physics_process(0.1)
	check(main.engine.exports == 1, "no catch-up sample on return")
	main._physics_process(0.3)
	check(main.engine.exports == 2, "sampling resumes outside FP")
	main._on_live_charts_toggled(false)
	main._set_first_person_enabled(true)
	main._set_first_person_enabled(false)
	check(not main._live_overlay.visible, "restore user hidden preference")
	check(not main._live_charts_button.button_pressed, "button reflects hidden preference")
	main._physics_process(0.3)
	check(main.engine.exports == 3, "historical hidden sampling outside FP retained")
	main._on_live_charts_toggled(true)
	check(main._live_overlay.visible, "manual enable still works outside FP")
	main.playback_paused = true
	before = main.engine.sim_time_s
	main._physics_process(1.0)
	check(main.engine.sim_time_s == before, "pause dispatch unchanged")
	main._live_overlay.free()
	main._live_charts_button.free()
	main.free()
	print("FP_LIVE_CHARTS " + JSON.stringify({"checks": checks,
		"failures": failures, "failure_count": failures.size()}))
	quit(0 if failures.is_empty() else 1)

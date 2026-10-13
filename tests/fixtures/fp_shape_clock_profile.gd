extends SceneTree

## ABBA counterfactual; natural physics clock and real Main/engine, no real FPS.
const Scene := preload("res://scenes/SimulationScene.tscn")
const Guard := preload("res://tests/fixtures/fp_shape_guard_probe.gd")
const TICKS: int = 180

class Probe extends Node:
	var main: Node
	var active: bool = false
	var count: int = 0
	var samples: Dictionary = {"main_us": [], "engine_us": [], "physics_monitor_cached_us": []}

	func _physics_process(delta: float) -> void:
		if not active or count >= TICKS:
			return
		var start: int = Time.get_ticks_usec()
		main._physics_process(delta)
		samples["main_us"].append(Time.get_ticks_usec() - start)
		samples["engine_us"].append(main.engine._step_time_us)
		# Godot refreshes this monitor coarsely. It is not this tick's duration;
		# initial samples can still contain scene startup and are not a budget.
		samples["physics_monitor_cached_us"].append(
			Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000000.0)
		count += 1

var changes: int = 0
var errors: Array[String] = []
var trials: Dictionary = {}
var samples: Dictionary = {}
var states: Array[PackedByteArray] = []


func _initialize() -> void:
	call_deferred("_run")


func _shape_changed() -> void:
	changes += 1


func _run() -> void:
	for label: String in ["control0", "guarded0", "guarded1", "control1"]:
		var guarded: bool = label.begins_with("guarded")
		var main = Scene.instantiate()
		var fp = main.get_node("World3D/FirstPersonController")
		var properties: Dictionary = {}
		if guarded:
			# Change script before @onready/setup, retaining all serialized exports.
			for property: Dictionary in fp.get_script().get_script_property_list():
				if int(property["usage"]) & PROPERTY_USAGE_STORAGE:
					properties[property["name"]] = fp.get(property["name"])
			fp.set_script(Guard)
			for name: Variant in properties:
				fp.set(name, properties[name])
				if var_to_bytes(fp.get(name)) != var_to_bytes(properties[name]):
					errors.append("export changed: " + str(name))
		root.add_child(main)
		main.set_physics_process(false)
		main.engine.suppress_exit_graphs()
		main._set_first_person_enabled(true)
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		await process_frame
		var shapes: Array = []
		for index: Variant in fp._opening_nodes:
			var shape := fp._opening_nodes[index].get("shape") as CollisionShape3D
			if shape != null and shape.shape is BoxShape3D:
				shapes.append(shape.shape)
				shape.shape.changed.connect(_shape_changed)
		var probe := Probe.new()
		probe.main = main
		root.add_child(probe)
		main._on_play_requested()
		changes = 0
		probe.active = true
		var started: int = Time.get_ticks_usec()
		while probe.count < TICKS:
			await process_frame
		probe.active = false
		var wall_s: float = float(Time.get_ticks_usec() - started) / 1000000.0
		for key: String in probe.samples:
			samples[label + "_" + key] = probe.samples[key]
		states.append(var_to_bytes(main.engine.get_state()))
		if absf(main.engine.sim_time_s - 3.0) > 1.0e-8:
			errors.append("wrong simulation clock: " + label)
		trials[label] = {"wall_s": wall_s, "ticks": probe.count,
			"sim_time_s": main.engine.sim_time_s, "shape_changes": changes,
			"serialized_exports_preserved": properties.size() if guarded else null}
		for shape: BoxShape3D in shapes:
			shape.changed.disconnect(_shape_changed)
		shapes.clear()
		probe.free()
		main.free()
		await process_frame
		await process_frame
	var identical: bool = true
	for state: PackedByteArray in states:
		identical = identical and state == states[0]
	if not identical:
		errors.append("counterfactual changed final engine state")
	print("PRODUCT_CPU_PROFILE " + JSON.stringify({"view": "fp",
		"display_server": DisplayServer.get_name(), "rendered_fps_measured": false,
		"gpu_measured": false, "trials": trials, "engine_states_identical": identical,
		"measurements_us": samples, "errors": errors}))
	quit(0 if errors.is_empty() else 1)

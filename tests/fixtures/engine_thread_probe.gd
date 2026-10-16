extends SceneTree

## Fixture de tests/test_engine_thread.py: la escena del producto con el motor
## en un hilo trabajador (Main.gd, `--engine-thread=on`), conducida por su
## propio bucle de física, frente al motor avanzado directamente.
##
## Escribe en --out un JSON con:
## - `default`: sin el argumento, headless sigue en el hilo principal.
## - `threaded`: vistas atadas a la copia; copia igual al real y sin
##   contenedores compartidos; mismo estado que el motor directo con una puerta
##   cambiada por una vista y la velocidad cambiada con un paso en marcha.
## - `exit`: salir de la escena con un paso en marcha lo espera y libera la copia.
const Scene := preload("res://scenes/SimulationScene.tscn")
const DT: float = 1.0 / 12.0

var steps: int = 240
var out_path: String = ""
var default_mode: bool = false


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--steps="):
			steps = int(arg.trim_prefix("--steps="))
		elif arg.begins_with("--out="):
			out_path = arg.trim_prefix("--out=")
		elif arg == "--default":
			default_mode = true
	call_deferred("_run")


func _new_main() -> Node:
	var main: Node = Scene.instantiate()
	root.add_child(main)
	main.engine.suppress_exit_graphs()
	main.engine.sim_fixed_dt = DT
	return main


func _free_main(main: Node) -> void:
	main.queue_free()
	await process_frame
	await process_frame


func _run() -> void:
	var out: Dictionary = {}
	if default_mode:
		var main: Node = _new_main()
		await process_frame
		out["default"] = {"engine_threaded": main._engine_threaded,
			"views_read_engine_building": main.view_building == main.building}
		await _free_main(main)
	else:
		out["threaded"] = await _threaded_run()
		out["exit"] = await _exit_with_step_running()
	var file := FileAccess.open(out_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(out, "\t"))
	file.close()
	quit(0)


func _door_index(building: Object) -> int:
	for index: int in range(building.get_opening_count()):
		var op: Object = building.get_opening_at(index)
		if op != null and int(op.type) == 0 and op.open_fraction > 0.5:
			return index
	return -1


func _threaded_run() -> Dictionary:
	var result: Dictionary = {}
	var main: Node = _new_main()
	await process_frame
	result["engine_threaded"] = main._engine_threaded
	result["mirror_is_separate"] = main.view_building != main.building
	result["views_bound"] = {
		"Visualizer": main.visualizer.building == main.view_building,
		"Visualizer3D": main.visualizer_3d.building == main.view_building,
		"HUD": main.hud.building == main.view_building,
		"Minimap2D": main.minimap_2d.building == main.view_building,
		"FirstPersonController": main.first_person_controller.building == main.view_building,
	}
	var door: int = _door_index(main.building)
	result["door"] = door
	var door_after_step: int = -1
	var speed_after_step: int = -1
	var speed_requested: float = -1.0
	var speed_kept_during_step: bool = false
	var speed_shown_during_step: bool = false
	main._on_play_requested()
	var frames: int = 0
	while frames < steps * 20:
		await physics_frame
		frames += 1
		var done: int = roundi(main._published_sim_time_s / DT)
		var running: bool = main._engine_task_id != -1
		if door >= 0 and door_after_step < 0 and done >= steps / 3 and running:
			# Como el HUD: la vista cambia su edificio con un paso en marcha.
			main._on_opening_fraction_requested(door, 0.0)
			door_after_step = done + 1
		if speed_after_step < 0 and done >= (2 * steps) / 3 and running:
			var before: float = main.engine.time_scale
			main._on_faster_requested()
			speed_requested = main._requested_time_scale()
			speed_kept_during_step = main.engine.time_scale == before and speed_requested > before
			speed_shown_during_step = float(main._build_view_state()["time_scale"]) == speed_requested
			speed_after_step = done + 1
		if done >= steps:
			break
	main._on_pause_requested()
	main._wait_engine_idle()
	var threaded_steps: int = roundi(main.engine.sim_time_s / DT)
	result["frames"] = frames
	result["threaded_steps"] = threaded_steps
	result["door_after_step"] = door_after_step
	result["speed_after_step"] = speed_after_step
	result["speed_kept_during_step"] = speed_kept_during_step
	result["speed_shown_during_step"] = speed_shown_during_step
	result["speed_applied"] = main.engine.time_scale == speed_requested
	result["mirror_mismatches"] = _mismatches(main.building, main.view_building)
	var threaded_state: String = JSON.stringify(main.engine.get_state(), "", true, true)
	var final_time_scale: float = main.engine.time_scale
	await _free_main(main)

	var reference: Node = _new_main()
	reference.set_physics_process(false)
	await process_frame
	for i: int in range(threaded_steps):
		reference.engine.step(DT)
		if i + 1 == door_after_step:
			reference.building.set_opening_fraction(door, 0.0)
		if i + 1 == speed_after_step:
			reference.engine.time_scale = final_time_scale
	var reference_state: String = JSON.stringify(reference.engine.get_state(), "", true, true)
	result["identical_to_direct_engine"] = reference_state == threaded_state
	result["state_sha256"] = threaded_state.sha256_text()
	await _free_main(reference)
	return result


func _exit_with_step_running() -> Dictionary:
	var result: Dictionary = {}
	var main: Node = _new_main()
	await process_frame
	main._on_play_requested()
	var frames: int = 0
	while main._engine_task_id == -1 and frames < 600:
		await physics_frame
		frames += 1
	result["step_was_running"] = main._engine_task_id != -1
	var mirror: Object = main.view_building
	root.remove_child(main)
	result["task_finished_on_exit"] = main._engine_task_id == -1
	result["mirror_freed"] = not is_instance_valid(mirror)
	main.free()
	return result


func _mismatches(real: Object, mirror: Object) -> Array:
	var found: Array = []
	_compare(real, mirror, "building", found, {})
	return found


func _compare(a: Variant, b: Variant, path: String, found: Array, seen: Dictionary) -> void:
	if found.size() >= 10:
		return
	match typeof(a):
		TYPE_OBJECT:
			if a == null:
				if b != null:
					found.append(path)
				return
			if seen.has(a.get_instance_id()):
				return
			seen[a.get_instance_id()] = true
			if b == null or b == a:
				found.append(path + " (shared or missing)")
				return
			for property: Dictionary in a.get_property_list():
				if int(property["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE:
					var name: String = property["name"]
					_compare(a.get(name), b.get(name), path + "." + name, found, seen)
		TYPE_ARRAY, TYPE_DICTIONARY:
			if typeof(b) != typeof(a) or a.size() != b.size():
				found.append(path)
				return
			if is_same(a, b) and a.size() > 0:
				found.append(path + " (shared container)")
				return
			var keys: Array = range(a.size()) if typeof(a) == TYPE_ARRAY else a.keys()
			for key: Variant in keys:
				_compare(a[key], b[key], path + "[" + str(key) + "]", found, seen)
		_:
			var both_nan: bool = typeof(a) == TYPE_FLOAT and typeof(b) == TYPE_FLOAT and is_nan(a) and is_nan(b)
			if typeof(a) != typeof(b) or (a != b and not both_nan):
				found.append(path)

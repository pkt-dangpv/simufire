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
## - `views`: en FP, los refrescos usan el estado exportado en el hilo del
##   motor; FP y HUD+minimapa se refrescan en ticks distintos; el minimapa
##   sigue al jugador sin estado nuevo y solo repinta muebles si cambian.
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
		out["views"] = await _views_run()
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


func _views_run() -> Dictionary:
	var result: Dictionary = {}
	var main: Node = _new_main()
	# Cadencia del producto a x1: un paso cada 1/12 s, ticks libres entre pasos.
	main.engine.sim_fixed_dt = 0.0
	await process_frame
	main._set_first_person_enabled(true)
	var fpc: Node = main.first_person_controller
	var mini: Control = main.minimap_2d
	var structure_keys: Dictionary = {}
	var published_checks: int = 0
	var published_matches: bool = true
	var fp_refreshes: int = 0
	var hud_refreshes: int = 0
	var same_tick: int = 0
	var hud_follows_fp: bool = true
	main._on_play_requested()
	var fp_state: Variant = fpc._state
	var mini_state: Variant = mini.state
	var hud_text: String = main.hud.time_label.text
	var frames: int = 0
	while frames < 60 * 20:
		await physics_frame
		frames += 1
		var fp_changed: bool = not is_same(fpc._state, fp_state)
		var mini_changed: bool = not is_same(mini.state, mini_state)
		var hud_changed: bool = main.hud.time_label.text != hud_text
		if fp_changed:
			fp_refreshes += 1
		if mini_changed:
			hud_refreshes += 1
			# HUD y minimapa reciben el mismo estado que acaba de pintar FP.
			hud_follows_fp = hud_follows_fp and is_same(mini.state, fpc._state)
		if fp_changed and (mini_changed or hud_changed):
			same_tick += 1
		fp_state = fpc._state
		mini_state = mini.state
		hud_text = main.hud.time_label.text
		structure_keys[mini._structure_key] = true
		if main._engine_task_id == -1 and not main._published_state.is_empty():
			published_checks += 1
			var view_state: Dictionary = main._build_view_state(true)
			for key: Variant in main._published_state:
				if JSON.stringify(view_state.get(key)) != JSON.stringify(main._published_state[key]):
					published_matches = false
			published_matches = published_matches and JSON.stringify(main._published_state) 				== JSON.stringify(main.engine.get_state())
		if roundi(main._published_sim_time_s / DT) >= 60:
			break
	# Un paso en cada tick (como a x5 o mas): las vistas no pueden esperar a un
	# tick libre que no llega.
	main.engine.sim_fixed_dt = DT
	var fast_fp_refreshes: int = 0
	var fast_hud_refreshes: int = 0
	for i: int in range(120):
		await physics_frame
		if not is_same(fpc._state, fp_state):
			fast_fp_refreshes += 1
		if not is_same(mini.state, mini_state):
			fast_hud_refreshes += 1
		fp_state = fpc._state
		mini_state = mini.state
	main._on_pause_requested()
	main._wait_engine_idle()
	result["fast_fp_refreshes"] = fast_fp_refreshes
	result["fast_hud_refreshes"] = fast_hud_refreshes
	result["published_checks"] = published_checks
	result["published_state_matches_engine"] = published_matches
	result["fp_refreshes"] = fp_refreshes
	result["hud_refreshes"] = hud_refreshes
	result["fp_and_hud_same_tick"] = same_tick
	result["hud_gets_the_fp_state"] = hud_follows_fp
	result["structure_keys_during_play"] = structure_keys.size()
	# En pausa, sin estado nuevo: el jugador se mueve y el minimapa lo sigue.
	var marker_before: Dictionary = mini._live_marker.duplicate()
	fpc.global_position += Vector3(0.4, 0.0, 0.0)
	await process_frame
	await process_frame
	var marker_now: Dictionary = fpc.get_player_marker_state()
	result["marker_follows_player"] = mini._live_marker == marker_now and mini._live_marker != marker_before
	# Un cristal roto sí repinta la capa de muebles y aperturas.
	var key_before: int = mini._structure_key
	var window: Object = null
	for index: int in range(main.view_building.get_opening_count()):
		var op: Object = main.view_building.get_opening_at(index)
		if op != null and int(op.type) == int(OpeningModel.Type.WINDOW) and not op.glass_broken:
			window = op
			break
	result["window_found"] = window != null
	if window != null:
		window.glass_broken = true
		mini.set_state(mini.state)
		result["broken_glass_redraws_structure"] = mini._structure_key != key_before
		window.glass_broken = false
	await _free_main(main)
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

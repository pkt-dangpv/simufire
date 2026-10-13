extends SceneTree

## Diagnostic only: real product scene and callbacks, no physics replacements.
## Headless callback timings are NOT rendered FPS or GPU timings.
const Scene := preload("res://scenes/SimulationScene.tscn")
const Layout := preload("res://view/furniture/FurnitureVisualLayout.gd")
const DT: float = 1.0 / 60.0
const TICKS: int = 180
const REPEATS: int = 30

var samples: Dictionary = {}
var errors: Array[String] = []
var mode: String = "fp"


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--profile-view="):
			mode = arg.trim_prefix("--profile-view=")
	call_deferred("_run")


func _time(label: String, action: Callable) -> void:
	var start: int = Time.get_ticks_usec()
	action.call()
	if not samples.has(label):
		samples[label] = []
	samples[label].append(Time.get_ticks_usec() - start)


func _same(a: Variant, b: Variant) -> bool:
	if typeof(a) != typeof(b):
		return false
	if typeof(a) == TYPE_FLOAT and is_nan(a) and is_nan(b):
		return true
	if a is Dictionary:
		if a.size() != b.size():
			return false
		for key: Variant in a:
			if not b.has(key) or not _same(a[key], b[key]):
				return false
		return true
	if a is Array:
		if a.size() != b.size():
			return false
		for index: int in range(a.size()):
			if not _same(a[index], b[index]):
				return false
		return true
	return a == b


func _overview_rooms_without_furniture(overview: Variant) -> void:
	for room_id: Variant in overview._room_items.keys():
		overview._update_room(int(room_id), false)


func _layouts_only(overview: Variant) -> void:
	for room_id: Variant in overview._room_items.keys():
		var item: Dictionary = overview._room_items[room_id]
		var rs: Dictionary = overview._room_state_for_visuals(int(room_id))
		Layout.normalize_room(overview.building, int(room_id), Rect2(item["rect"]),
			Array(rs.get("fuel_objects", [])).duplicate(), overview.furnish_empty_rooms)


func _run() -> void:
	if mode not in ["2d", "3d", "fp"]:
		push_error("Unknown profiling view")
		quit(1)
		return
	var main = Scene.instantiate()
	root.add_child(main)
	main.set_physics_process(false)
	main.playback_paused = true
	await process_frame
	main.engine.suppress_exit_graphs()
	if mode == "fp":
		main._set_first_person_enabled(true)
	elif mode == "3d":
		main._set_3d_view_enabled(true)
	await process_frame
	var info: Dictionary = {
		"view": mode, "display_server": DisplayServer.get_name(),
		"rendered_fps_measured": false, "gpu_measured": false,
		"physics_dt_s": DT, "manual_ticks": TICKS,
		"template": main.building.template_name,
		"rooms": main.building.get_rooms().size(),
		"openings": main.building.get_opening_count(),
		"node_count": get_node_count(),
		"building_type": main.building.building_type,
		"apartment_floor_number": main.building.apartment_floor_number,
		"building_total_floors": main.building.building_total_floors,
	}
	# Reuse the actual running callback. Main's automatic callback is disabled;
	# no second engine tick is introduced by the diagnostic scene tree.
	main.playback_paused = false
	var time_before: float = main.engine.sim_time_s
	for tick: int in range(TICKS):
		_time("main_running_callback_us", func(): main._physics_process(DT))
		if not samples.has("engine_recorded_step_us"):
			samples["engine_recorded_step_us"] = []
		samples["engine_recorded_step_us"].append(main.engine.get("_step_time_us"))
		await process_frame
	main.playback_paused = true
	info["sim_time_before_s"] = time_before
	info["sim_time_after_s"] = main.engine.sim_time_s
	if absf(main.engine.sim_time_s - time_before - DT * TICKS) > 1.0e-8:
		errors.append("manual tick count/time mismatch")
	# Same-state repeated calls isolate CPU callback cost, not GPU frame cost.
	var before: Dictionary = main.engine.get_state().duplicate(true)
	var state: Dictionary = main._build_view_state()
	for iteration: int in range(REPEATS + 3):
		if iteration == 3:
			# Three warm-up calls are separate from the reported frozen probes.
			for label: String in samples.keys():
				if label not in ["main_running_callback_us", "engine_recorded_step_us"]:
					samples.erase(label)
		_time("build_view_state_us", func(): main._build_view_state())
		_time("hud_update_us", func(): main.hud.update_state(state))
		if mode != "2d":
			_time("overview_set_state_us", func(): main.visualizer_3d.set_state(state))
			_time("minimap_set_state_us", func(): main.minimap_2d.set_state(state))
			_time("overview_rooms_without_furniture_us", func(): _overview_rooms_without_furniture(main.visualizer_3d))
			_time("furniture_layout_only_us", func(): _layouts_only(main.visualizer_3d))
		else:
			_time("2d_set_state_us", func(): main.visualizer.set_state(state))
		if mode == "fp":
			var fp = main.first_person_controller
			_time("fp_set_state_us", func(): fp.set_state(state))
			_time("fp_opening_panels_us", func(): fp._sync_opening_panels())
			_time("fp_furniture_us", func(): fp._update_fp_furniture_visuals())
			_time("fp_fire_us", func(): fp._update_fp_fire_visuals())
			_time("fp_patio_smoke_us", func(): fp._update_patio_smoke())
			_time("fp_light_attenuation_us", func(): fp._update_smoke_light_attenuation())
			_time("fp_visibility_us", func(): fp._update_visibility_overlay())
			_time("fp_hud_us", func(): fp._update_status_hud(true))
	if not _same(before, main.engine.get_state()):
		errors.append("frozen visual probes changed engine state")
	var opening_index: int = -1
	for index: int in range(main.building.get_opening_count()):
		if main.building.get_opening_at(index).type == OpeningModel.Type.WINDOW:
			opening_index = index
			break
	info["opening_index"] = opening_index
	if opening_index < 0:
		errors.append("no window in product preset")
	else:
		var original: float = main.building.get_opening_at(opening_index).open_fraction
		var paused_time: float = main.engine.sim_time_s
		for iteration: int in range(REPEATS):
			var fraction: float = 1.0 if iteration % 2 == 0 else 0.0
			if mode == "fp":
				_time("paused_window_action_us", func(): main.first_person_controller._apply_opening_fraction(opening_index, fraction))
			else:
				_time("paused_window_action_us", func(): main._on_opening_fraction_requested(opening_index, fraction))
		main.building.set_opening_fraction(opening_index, original)
		if main.engine.sim_time_s != paused_time:
			errors.append("paused window action advanced physics")
	# This proves read-only frozen probes, not identity against an engine-only
	# trajectory or a rendered frame capture; those require separate controls.
	info["frozen_visual_state_unchanged"] = not errors.has("frozen visual probes changed engine state")
	info["measurements_us"] = samples
	info["errors"] = errors
	print("PRODUCT_CPU_PROFILE " + JSON.stringify(info))
	main.queue_free()
	await process_frame
	quit(0 if errors.is_empty() else 1)

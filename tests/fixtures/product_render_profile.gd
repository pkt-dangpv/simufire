extends SceneTree

## Diagnostic only: real window/rendering, natural fixed-rate physics callbacks.
## Baseline calls production unchanged. Optional named counterfactual uses a
## diagnostic subclass; no manual render clock or production quality changes.
const Scene := preload("res://scenes/SimulationScene.tscn")
const Layout := preload("res://view/furniture/FurnitureVisualLayout.gd")
const Overlap := preload("res://tests/fixtures/product_furniture_overlap.gd")
const SECONDS: float = 8.0

class PhysicsProbe extends Node:
	var main: Node
	var active: bool = false
	var samples: Array = []
	var frame_main_us: int = 0
	var frame_steps: int = 0

	func _physics_process(delta: float) -> void:
		if not active:
			return
		var started: int = Time.get_ticks_usec()
		var before_sim_s: float = main.engine.sim_time_s
		# Call the actual Main callback once, never a second engine step.
		main._physics_process(delta)
		var elapsed: int = Time.get_ticks_usec() - started
		var advanced: bool = main.engine.sim_time_s > before_sim_s
		var step_us: int = int(main.engine.get("_step_time_us")) if advanced else 0
		# The engine retains its last cost between dispatches. Do not count that
		# stale value as another engine execution on a view-only callback.
		samples.append([elapsed, step_us, delta, advanced])
		frame_main_us += elapsed
		frame_steps += 1

var mode: String = "3d"
var hide_minimap: bool = false
var freeze_fp_furniture: bool = false
var hide_overview_furniture: bool = false
var main: Node
var probe: PhysicsProbe
var phase: String = ""
var frames: Array = []
var last_draw_us: int = 0
var viewport_rid: RID
var phases: Dictionary = {}
var previous_keys: Dictionary = {}
var key_changes: Array = []
var asset_signals: Dictionary = {}


func _asset_changed(path: String) -> void:
	asset_signals[path] = int(asset_signals.get(path, 0)) + 1


func _cache_changes() -> void:
	for slot: Variant in Layout._room_cache:
		var key: PackedByteArray = Layout._room_cache[slot]["key"]
		if previous_keys.has(slot) and previous_keys[slot] != key and key_changes.size() < 32:
			var old: Array = bytes_to_var(previous_keys[slot])
			var current: Array = bytes_to_var(key)
			var changed: Array = []
			for i: int in range(4):
				if var_to_bytes(old[i]) != var_to_bytes(current[i]):
					changed.append(i)
			var fields: Array = []
			if old[2].size() == current[2].size():
				for i: int in range(current[2].size()):
					var names: Dictionary = {}
					for name: Variant in old[2][i]:
						names[name] = true
					for name: Variant in current[2][i]:
						names[name] = true
					for name: Variant in names:
						if var_to_bytes(old[2][i].get(name)) != var_to_bytes(current[2][i].get(name)):
							fields.append({"object": i, "field": name,
								"old": str(old[2][i].get(name)), "new": str(current[2][i].get(name))})
			key_changes.append({"slot": slot, "components": changed, "fields": fields})
		previous_keys[slot] = key


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--profile-view="):
			mode = arg.trim_prefix("--profile-view=")
		elif arg == "--hide-minimap":
			hide_minimap = true
		elif arg == "--freeze-fp-furniture":
			freeze_fp_furniture = true
		elif arg == "--hide-overview-furniture":
			hide_overview_furniture = true
	call_deferred("_run")


func _drawn() -> void:
	var now: int = Time.get_ticks_usec()
	if phase != "":
		_cache_changes()
	var probe_us: int = Time.get_ticks_usec() - now
	if phase != "" and last_draw_us > 0:
		frames.append({
			"interval_us": now - last_draw_us,
			"main_us": probe.frame_main_us,
			"physics_steps": probe.frame_steps,
			"probe_us": probe_us,
			"render_cpu_ms": RenderingServer.viewport_get_measured_render_time_cpu(viewport_rid),
			"render_gpu_ms": RenderingServer.viewport_get_measured_render_time_gpu(viewport_rid),
			"render_setup_ms": RenderingServer.get_frame_setup_time_cpu(),
			"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			"primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		})
	last_draw_us = now
	probe.frame_main_us = 0
	probe.frame_steps = 0


func _measure(label: String) -> void:
	frames = []
	probe.samples = []
	probe.frame_main_us = 0
	probe.frame_steps = 0
	last_draw_us = 0
	var start_us: int = Time.get_ticks_usec()
	var before: float = main.engine.sim_time_s
	var before_cache: Dictionary = Layout.cache_stats()
	key_changes = []
	asset_signals = {}
	phase = label
	# SceneTreeTimer counts the current frame's delta too. Use real elapsed
	# time so a slow transition cannot shorten the following paused sample.
	while float(Time.get_ticks_usec() - start_us) / 1000000.0 < SECONDS:
		await process_frame
	phase = ""
	phases[label] = {
		"wall_s": float(Time.get_ticks_usec() - start_us) / 1000000.0,
		"sim_start_s": before, "sim_end_s": main.engine.sim_time_s,
		"frames": frames.duplicate(true), "physics_callbacks": probe.samples.duplicate(true),
		"cache_before": before_cache, "cache_after": Layout.cache_stats(),
		"cache_key_changes": key_changes.duplicate(true),
		"asset_changed_signals": asset_signals.duplicate(true),
		"window_visible": root.visible,
		"window_minimized": root.mode == Window.MODE_MINIMIZED,
	}


func _furniture_overlap() -> Dictionary:
	return Overlap.read(main)


func _run() -> void:
	if mode not in ["3d", "fp"] or DisplayServer.get_name() == "headless":
		push_error("Requires a real display and 3d/fp")
		quit(1)
		return
	main = Scene.instantiate()
	if freeze_fp_furniture:
		var fp = main.get_node("World3D/FirstPersonController")
		var properties: Dictionary = {}
		for property: Dictionary in fp.get_script().get_script_property_list():
			if int(property["usage"]) & PROPERTY_USAGE_STORAGE:
				properties[property["name"]] = fp.get(property["name"])
		fp.set_script(load("res://tests/fixtures/fp_furniture_freeze_probe.gd"))
		for name: Variant in properties:
			fp.set(name, properties[name])
			if var_to_bytes(fp.get(name)) != var_to_bytes(properties[name]):
				push_error("Counterfactual lost serialized property: " + str(name))
				quit(1)
				return
	root.add_child(main)
	main.set_physics_process(false)
	main.playback_paused = true
	main.engine.suppress_exit_graphs()
	await process_frame
	if mode == "fp":
		main._set_first_person_enabled(true)
	else:
		main._set_3d_view_enabled(true)
	if hide_minimap:
		main.minimap_2d.visible = false
	var overlap_before: Dictionary = _furniture_overlap() if mode == "fp" else {}
	if hide_overview_furniture:
		main.visualizer_3d.show_fuel_objects_in_first_person = false
		main.visualizer_3d._apply_overlay_visibility()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	root.title = "SimuFire - perfil renderizado " + mode + " (cierre automatico)"
	probe = PhysicsProbe.new()
	probe.main = main
	root.add_child(probe)
	viewport_rid = root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(viewport_rid, true)
	RenderingServer.frame_post_draw.connect(_drawn)
	await create_timer(3.0).timeout
	for path: Variant in Layout._asset_resources:
		Layout._asset_resources[path].changed.connect(_asset_changed.bind(String(path)))
	await _measure("paused_before")
	if freeze_fp_furniture:
		main.first_person_controller.diagnostic_freeze_furniture = true
	main._on_play_requested()
	probe.active = true
	await _measure("playing")
	probe.active = false
	main._on_pause_requested()
	await _measure("paused_after")
	RenderingServer.frame_post_draw.disconnect(_drawn)
	var payload: Dictionary = {
		"view": mode, "display_server": DisplayServer.get_name(),
		"rendering_method": ProjectSettings.get_setting("rendering/renderer/rendering_method"),
		"adapter": RenderingServer.get_video_adapter_name(),
		"window_size": [root.size.x, root.size.y],
		"physics_ticks_per_second": Engine.physics_ticks_per_second,
		"max_physics_steps_per_frame": Engine.max_physics_steps_per_frame,
		"max_fps": Engine.max_fps, "vsync_mode": DisplayServer.window_get_vsync_mode(),
		"node_count": get_node_count(), "rooms": main.building.get_rooms().size(),
		"openings": main.building.get_opening_count(), "phases": phases,
		"rendered_frames_measured": true,
		"quality_changed": hide_minimap or freeze_fp_furniture or hide_overview_furniture,
		"hide_minimap": hide_minimap,
		"freeze_fp_furniture": freeze_fp_furniture,
		"hide_overview_furniture": hide_overview_furniture,
		"furniture_overlap_before": overlap_before,
		"furniture_overlap_after": _furniture_overlap() if mode == "fp" else {},
	}
	print("PRODUCT_RENDER_PROFILE " + JSON.stringify(payload))
	probe.active = false
	for path: Variant in Layout._asset_resources:
		var callback: Callable = _asset_changed.bind(String(path))
		if Layout._asset_resources[path].changed.is_connected(callback):
			Layout._asset_resources[path].changed.disconnect(callback)
	root.remove_child(probe)
	probe.free()
	probe = null
	root.remove_child(main)
	main.free()
	main = null
	# Diagnostic process is ending: release retained resources before renderer
	# teardown, rather than letting static script storage outlive the renderer.
	Layout.invalidate_all()
	Layout._asset_resources.clear()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	await create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	quit(0)

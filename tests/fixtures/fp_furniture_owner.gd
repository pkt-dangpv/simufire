extends SceneTree

## Real product transitions; headless ownership proof, not FPS/pixel parity.
const Scene := preload("res://scenes/SimulationScene.tscn")
const Layout := preload("res://view/furniture/FurnitureVisualLayout.gd")
const Overlap := preload("res://tests/fixtures/product_furniture_overlap.gd")
var checks: int = 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)


func _snapshot(node: Node) -> Array:
	var record: Array = [node.get_instance_id(), node.get_class()]
	if node is Node3D:
		record.append(node.transform)
	if node is MeshInstance3D:
		record.append(node.mesh)
		record.append(node.material_override)
		if node.material_override is StandardMaterial3D:
			record.append(node.material_override.albedo_color)
	if node is CollisionShape3D:
		record.append(node.shape)
		record.append(node.disabled)
	for child: Node in node.get_children():
		record.append(_snapshot(child))
	return record


func _furniture(fp: Node) -> PackedByteArray:
	var records: Array = []
	for item: Dictionary in fp._furniture_nodes_by_room.values():
		for node: Node in item.get("fuel_obj_nodes", {}).values():
			records.append(_snapshot(node))
	return var_to_bytes(records)


func _check_visible(main: Node, in_fp: bool) -> void:
	var overlap: Dictionary = Overlap.read(main)
	check(overlap["matching_objects"] == 39, "all 39 logical furniture objects retained")
	for pair: Dictionary in overlap["pairs"]:
		check(pair["positions_equal"], "furniture world pose unchanged")
		check(pair["fp_visible"] == in_fp, "FP furniture visibility follows FP mode")
		check(pair["overview_visible"] == not in_fp, "single visible furniture owner")


func _run() -> void:
	# Only the launcher's external APPDATA is written, never user preferences.
	var options := FileAccess.open("user://startup_sim_options.json", FileAccess.WRITE)
	options.store_string(JSON.stringify({"template_name": "simple_house",
		"building_type": "apartment", "apartment_floor_number": 15,
		"building_total_floors": 20, "exterior_lighting_mode": "Noche",
		"interior_lights_on": true, "smoke_visibility_representation": true,
		"glass_break_mode": 0, "hvac_mode": "none",
		"wind_direction_deg": 0.0, "wind_speed_m_s": 0.0}))
	options.close()
	var main = Scene.instantiate()
	root.add_child(main)
	main.set_physics_process(false)
	main.playback_paused = true
	main.engine.suppress_exit_graphs()
	main.first_person_controller.set_physics_process(false)
	main.visualizer_3d.set_process(false)
	await process_frame
	var overview = main.visualizer_3d
	var fp = main.first_person_controller
	check(not overview.show_fuel_objects_in_first_person, "product default suppresses duplicate")
	main._set_3d_view_enabled(true)
	var engine_before: PackedByteArray = var_to_bytes(main.engine.get_state())
	var furniture_before: PackedByteArray = _furniture(fp)
	_check_visible(main, false)
	for transition: int in range(3):
		main._set_first_person_enabled(true)
		# Test the entry policy on its own, before refresh can hide its mistake.
		overview._apply_overlay_visibility()
		_check_visible(main, true)
		check(_furniture(fp) == furniture_before, "FP nodes meshes materials and colliders retained")
		# Force a due tick: a throttle must not mask a missing ownership guard.
		overview._last_fp_fuel_object_update_msec = 0
		check(not overview._should_update_fuel_objects_this_pass(), "skip hidden furniture refresh")
		var stats_before: Dictionary = Layout.cache_stats()
		for tick: int in range(30):
			overview.set_state(main._build_view_state())
		check(Layout.cache_stats() == stats_before, "hidden overview does not normalize furniture")
		check(overview._last_fp_fuel_object_update_msec == 0, "no hidden update throttle activity")
		_check_visible(main, true)
		main._set_3d_view_enabled(true)
		_check_visible(main, false)
		check(overview._should_update_fuel_objects_this_pass(), "3D furniture refresh restored")
		check(_furniture(fp) == furniture_before, "round trip retains FP furniture identity")
	check(var_to_bytes(main.engine.get_state()) == engine_before, "view transitions do not alter engine")
	# Positive control: 3D must still consume a fresh furniture snapshot.
	var state: Dictionary = main._build_view_state()
	var before_refresh: Dictionary = Layout.cache_stats()
	overview.set_state(state)
	check(int(Layout.cache_stats()["hits"]) > int(before_refresh["hits"]), "3D still normalizes furniture")
	# Actual interaction entry point remains usable with the duplicate hidden.
	main._set_first_person_enabled(true)
	var op: OpeningModel = main.building.get_opening_at(0)
	var original_fraction: float = op.open_fraction
	var target: float = 1.0 if original_fraction < 0.5 else 0.0
	fp._apply_opening_fraction(0, target)
	check(is_equal_approx(op.open_fraction, target), "FP opening interaction retained")
	fp._apply_opening_fraction(0, original_fraction)
	check(is_equal_approx(op.open_fraction, original_fraction), "FP opening interaction restored")
	_check_visible(main, true)
	# Compatibility opt-in for a standalone visualizer is still explicit.
	overview.show_fuel_objects_in_first_person = true
	overview._apply_overlay_visibility()
	check(overview._should_update_fuel_objects_this_pass(), "explicit standalone opt-in retained")
	overview.show_fuel_objects_in_first_person = false
	overview._apply_overlay_visibility()
	main.playback_paused = false
	var clock_before: float = main.engine.sim_time_s
	for tick: int in range(60):
		main._physics_process(1.0 / 60.0)
	check(is_equal_approx(main.engine.sim_time_s - clock_before, 1.0), "Play keeps physical clock")
	_check_visible(main, true)
	main.playback_paused = true
	clock_before = main.engine.sim_time_s
	main._physics_process(0.5)
	check(main.engine.sim_time_s == clock_before, "pause keeps physical clock")
	main.free()
	Layout.invalidate_all()
	await process_frame
	print("FP_FURNITURE_OWNER " + JSON.stringify({"checks": checks,
		"failures": failures, "failure_count": failures.size()}))
	quit(0 if failures.is_empty() else 1)

extends Node

const BuildingModelScript := preload("res://sim/BuildingModel.gd")
const Visualizer3DScript := preload("res://view/3d/Visualizer3D.gd")

var _failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	await get_tree().process_frame

	var building: BuildingModel = BuildingModelScript.new()
	_expect(building.load_template_data(_make_template()), "BuildingModel rejected 3D overlay template")

	var visualizer: Visualizer3D = Visualizer3DScript.new()
	visualizer.name = "Validate3DTechnicalOverlays"
	visualizer.building = building
	visualizer.show_layer_gradient = true
	visualizer.show_wall_heatmap = true
	visualizer.show_fed_labels = true
	visualizer.debug_show_layer_heights = true
	visualizer.debug_show_room_temps = true
	visualizer.debug_show_hrr_values = true
	_add_visualizer_children(visualizer)
	add_child(visualizer)
	await get_tree().process_frame
	visualizer.rebuild_from_building()
	visualizer.set_state(_make_state(1.2))
	await get_tree().process_frame

	var gradient := visualizer.get_node_or_null("Atmosphere/LayerGradient_00") as MeshInstance3D
	_expect(gradient != null, "3D layer gradient node was not created")
	if gradient != null:
		_expect(gradient.visible, "3D layer gradient did not become visible")
		_expect_color_close(_mesh_color(gradient), visualizer.layer_gradient_top_color, 0.03, "3D layer gradient color mismatch")

	var wall := _find_first_wall(visualizer)
	_expect(wall != null, "3D room wall was not created")
	if wall != null:
		var wall_heat_t: float = clampf(
			inverse_lerp(visualizer.temp_heat_wall_start_c, visualizer.temp_heat_wall_full_c, 420.0),
			0.0,
			1.0
		)
		var expected_wall_color: Color = visualizer.wall_color.lerp(visualizer.hot_wall_color, wall_heat_t)
		_expect_color_close(_mesh_color(wall), expected_wall_color, 0.03, "3D wall heatmap did not use interpolated hot color")

	var fed_label := visualizer.get_node_or_null("Labels/FedLabel_00") as Label3D
	_expect(fed_label != null, "3D FED label was not created")
	if fed_label != null:
		_expect(fed_label.visible, "3D FED label did not become visible")
		_expect(fed_label.text == "FED 1.20", "3D FED label text mismatch: %s" % fed_label.text)
		_expect_color_close(fed_label.modulate, visualizer.fed_label_danger_color, 0.03, "3D FED label danger color mismatch")

	var room_label := visualizer.get_node_or_null("Labels/Label_00") as Label3D
	_expect(room_label != null, "3D room label was not created")
	if room_label != null:
		_expect(room_label.text.contains("L 1.0m"), "3D debug layer height missing from room label")
		_expect(room_label.text.contains("420"), "3D debug temperature missing from room label")
		_expect(room_label.text.contains("320kW"), "3D debug HRR missing from room label")

	visualizer.show_wall_heatmap = false
	visualizer.show_layer_gradient = false
	visualizer.show_fed_labels = false
	visualizer.set_state(_make_state(1.2))
	await get_tree().process_frame
	if wall != null:
		_expect_color_close(_mesh_color(wall), visualizer.wall_color, 0.03, "3D wall heatmap did not reset to base color")
	if gradient != null:
		_expect(not gradient.visible, "3D layer gradient ignored show_layer_gradient=false")
	if fed_label != null:
		_expect(not fed_label.visible, "3D FED label ignored show_fed_labels=false")

	remove_child(visualizer)
	visualizer.free()
	building.free()
	_finish()


func _make_template() -> Dictionary:
	return {
		"version": 1,
		"building_type": "single_family",
		"outside_temp_c": 20.0,
		"outside_o2": 0.209,
		"stop_time_s": 0.0,
		"hvac_mode": "none",
		"hvac_data": {"exists": false, "on": false, "mode": "none"},
		"room_rect_m": {
			"0": {"x": 0.0, "y": 0.0, "w": 4.0, "h": 3.0}
		},
		"rooms_data": [
			{
				"id": 0,
				"name": "Sala overlays 3D",
				"kind": "salon",
				"height_m": 2.5,
				"floor_level_z_m": 0.0,
				"fuel_energy_MJ": 0.0,
				"max_hrr_kw": 0.0,
				"fuel_objects": []
			}
		],
		"openings_data": [],
		"detectors": [],
		"victims": [
			{"id": "vic_overlay_0", "room_id": 0, "name": "Victima overlay", "x_m": 2.0, "y_m": 1.5}
		],
		"exterior_walls": []
	}


func _make_state(fed: float) -> Dictionary:
	return {
		"0": {
			"id": 0,
			"name": "Sala overlays 3D",
			"kind": "salon",
			"height_m": 2.5,
			"hrr_kw": 320.0,
			"temp_upper_c": 420.0,
			"smoke_kg": 1.4,
			"smoke_layer_m": 1.0,
			"smoke_display_layer_m": 1.0,
			"hot_layer_m": 1.2,
			"layer_150c_m": 1.8,
			"visibility_m": 5.0,
			"overpressure_pa": 0.0,
			"fuel_objects": []
		},
		"victims": [
			{"id": "vic_overlay_0", "room_id": 0, "fed": fed}
		]
	}


func _add_visualizer_children(visualizer: Node3D) -> void:
	for node_name in ["Rooms", "Openings", "Atmosphere", "Labels"]:
		var container := Node3D.new()
		container.name = node_name
		visualizer.add_child(container)
	var camera_rig := Node3D.new()
	camera_rig.name = "CameraRig"
	visualizer.add_child(camera_rig)
	var camera := Camera3D.new()
	camera.name = "Camera3D"
	camera.position = Vector3(0.0, 0.0, 12.0)
	camera_rig.add_child(camera)


func _find_first_wall(root: Node) -> MeshInstance3D:
	if root is MeshInstance3D and root.name.begins_with("Wall"):
		return root as MeshInstance3D
	for child in root.get_children():
		var hit := _find_first_wall(child)
		if hit != null:
			return hit
	return null


func _mesh_color(mesh: MeshInstance3D) -> Color:
	if mesh == null:
		return Color.TRANSPARENT
	var material := mesh.material_override as StandardMaterial3D
	if material == null:
		return Color.TRANSPARENT
	return material.albedo_color


func _finish() -> void:
	if _failures.is_empty():
		print("3D TECHNICAL OVERLAYS VALIDATION PASS")
		get_tree().quit(0)
		return
	push_error("3D TECHNICAL OVERLAYS VALIDATION FAILED")
	for failure in _failures:
		push_error("- " + failure)
	get_tree().quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _expect_color_close(actual: Color, expected: Color, tolerance: float, message: String) -> void:
	var delta: float = absf(actual.r - expected.r) + absf(actual.g - expected.g) + absf(actual.b - expected.b) + absf(actual.a - expected.a)
	if delta > tolerance:
		_failures.append("%s (actual=%s expected=%s)" % [message, str(actual), str(expected)])

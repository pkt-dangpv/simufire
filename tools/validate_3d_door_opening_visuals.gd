extends Node

const BuildingModelScript := preload("res://sim/BuildingModel.gd")
const Visualizer3DScript := preload("res://view/3d/Visualizer3D.gd")

var _failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	await get_tree().process_frame

	var building: BuildingModel = BuildingModelScript.new()
	_expect(building.load_template_data(_make_template()), "BuildingModel rejected 3D door visual template")

	var visualizer: Visualizer3D = Visualizer3DScript.new()
	visualizer.name = "Validate3DDoorOpeningVisuals"
	visualizer.building = building
	visualizer.show_door_leaf_animation_3d = true
	_add_visualizer_children(visualizer)
	add_child(visualizer)
	await get_tree().process_frame
	visualizer.rebuild_from_building()
	visualizer.set_state({})
	await get_tree().process_frame

	var pivot := visualizer.get_node_or_null("Openings/Opening_00/DoorLeafPivot_00") as Node3D
	var panel := visualizer.get_node_or_null("Openings/Opening_00/DoorLeafPivot_00/DoorLeaf_00") as MeshInstance3D
	_expect(pivot != null, "3D door leaf pivot was not created")
	_expect(panel != null, "3D door leaf panel was not created")
	if pivot == null or panel == null:
		_finish()
		return

	var full_angle: float = float(pivot.get_meta("full_open_angle_rad", 0.0))
	_expect(absf(full_angle) > deg_to_rad(70.0), "3D door full-open angle is too small")
	_expect_close(pivot.rotation.y, 0.0, 0.01, "3D door leaf did not start closed")
	_expect(panel.visible, "3D door leaf panel started hidden")

	_expect(building.set_opening_fraction(0, 0.5), "BuildingModel did not update door open_fraction")
	visualizer.set_state({})
	await get_tree().process_frame
	_expect_close(pivot.rotation.y, full_angle * 0.5, 0.02, "3D door leaf did not follow half-open fraction")

	_expect(building.set_opening_fraction(0, 1.0), "BuildingModel did not update full door open_fraction")
	visualizer.set_state({})
	await get_tree().process_frame
	_expect_close(pivot.rotation.y, full_angle, 0.02, "3D door leaf did not follow full-open fraction")

	visualizer.show_door_leaf_animation_3d = false
	visualizer.set_state({})
	await get_tree().process_frame
	_expect(not pivot.visible, "3D door leaf ignored show_door_leaf_animation_3d=false")
	_expect(not panel.visible, "3D door panel ignored show_door_leaf_animation_3d=false")

	var right_pivot := visualizer.get_node_or_null("Openings/Opening_01/DoorLeafPivot_01") as Node3D
	_expect(right_pivot != null, "3D right-wall door leaf pivot was not created")
	if right_pivot != null:
		var right_full_angle: float = float(right_pivot.get_meta("full_open_angle_rad", 0.0))
		_expect(absf(right_full_angle) > deg_to_rad(70.0), "3D right-wall door full-open angle is too small")

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
				"name": "Sala puertas 3D",
				"kind": "salon",
				"height_m": 2.5,
				"floor_level_z_m": 0.0,
				"fuel_energy_MJ": 0.0,
				"max_hrr_kw": 0.0,
				"fuel_objects": []
			}
		],
		"openings_data": [
			{
				"a": 0,
				"b": -1,
				"type": "door",
				"wall": "bottom",
				"offset_m": 0.50,
				"offset_is_fraction": true,
				"width_m": 0.9,
				"height_m": 2.0,
				"open_fraction": 0.0,
				"swing_direction": "in",
				"hinge_side": "left"
			},
			{
				"a": 0,
				"b": -1,
				"type": "door",
				"wall": "right",
				"offset_m": 0.55,
				"offset_is_fraction": true,
				"width_m": 0.8,
				"height_m": 2.0,
				"open_fraction": 0.75,
				"swing_direction": "out",
				"hinge_side": "right"
			}
		],
		"detectors": [],
		"victims": [],
		"exterior_walls": []
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


func _finish() -> void:
	if _failures.is_empty():
		print("3D DOOR OPENING VISUALS VALIDATION PASS")
		get_tree().quit(0)
		return
	push_error("3D DOOR OPENING VISUALS VALIDATION FAILED")
	for failure in _failures:
		push_error("- " + failure)
	get_tree().quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _expect_close(actual: float, expected: float, tolerance: float, message: String) -> void:
	if absf(actual - expected) > tolerance:
		_failures.append("%s (actual=%.4f expected=%.4f)" % [message, actual, expected])

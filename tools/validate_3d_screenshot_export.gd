extends Node

const BuildingModelScript := preload("res://sim/BuildingModel.gd")
const Visualizer3DScript := preload("res://view/3d/Visualizer3D.gd")

var _failures: Array[String] = []
var _saved_path: String = ""
var _failed_message: String = ""


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	await get_tree().process_frame

	var building: BuildingModel = BuildingModelScript.new()
	_expect(building.load_template_data(_make_template()), "BuildingModel rejected 3D screenshot template")

	var visualizer: Visualizer3D = Visualizer3DScript.new()
	visualizer.name = "Validate3DScreenshotExport"
	visualizer.building = building
	_add_visualizer_children(visualizer)
	add_child(visualizer)
	await get_tree().process_frame
	visualizer.rebuild_from_building()
	visualizer.set_state(_make_state())
	await get_tree().process_frame
	await get_tree().process_frame

	visualizer.screenshot_saved.connect(_on_screenshot_saved)
	visualizer.screenshot_failed.connect(_on_screenshot_failed)

	var output_dir: String = ProjectSettings.globalize_path("user://validate_3d_screenshot")
	DirAccess.make_dir_recursive_absolute(output_dir)
	visualizer.capture_screenshot_to(output_dir)
	await get_tree().process_frame

	if _saved_path != "":
		_expect(_failed_message == "", "3D screenshot emitted failure after saved path: %s" % _failed_message)
		_expect(_saved_path.begins_with(output_dir), "3D screenshot saved outside requested directory")
		_expect(FileAccess.file_exists(_saved_path), "3D screenshot PNG was not written")
		if FileAccess.file_exists(_saved_path):
			var file := FileAccess.open(_saved_path, FileAccess.READ)
			_expect(file != null, "3D screenshot PNG could not be opened")
			if file != null:
				_expect(file.get_length() > 8, "3D screenshot PNG is empty")
				var signature := file.get_buffer(8)
				_expect(_is_png_signature(signature), "3D screenshot file does not have PNG signature")
				file.close()
			DirAccess.remove_absolute(_saved_path)
	else:
		_expect(
			_failed_message.contains("get_image() devolvio null") or _failed_message.contains("Viewport no disponible"),
			"3D screenshot did not save and emitted unexpected failure: %s" % _failed_message
		)
	DirAccess.remove_absolute(output_dir)

	remove_child(visualizer)
	visualizer.free()
	building.free()
	_finish()


func _on_screenshot_saved(path: String) -> void:
	_saved_path = path


func _on_screenshot_failed(message: String) -> void:
	_failed_message = message


func _is_png_signature(bytes: PackedByteArray) -> bool:
	if bytes.size() < 8:
		return false
	var expected: Array[int] = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]
	for i in range(expected.size()):
		if int(bytes[i]) != expected[i]:
			return false
	return true


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
				"name": "Sala captura 3D",
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
		"victims": [],
		"exterior_walls": []
	}


func _make_state() -> Dictionary:
	return {
		"0": {
			"id": 0,
			"name": "Sala captura 3D",
			"kind": "salon",
			"height_m": 2.5,
			"hrr_kw": 0.0,
			"temp_upper_c": 24.0,
			"smoke_kg": 0.0,
			"smoke_layer_m": 2.5,
			"visibility_m": 30.0,
			"fuel_objects": []
		}
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
		print("3D SCREENSHOT EXPORT VALIDATION PASS")
		get_tree().quit(0)
		return
	push_error("3D SCREENSHOT EXPORT VALIDATION FAILED")
	for failure in _failures:
		push_error("- " + failure)
	get_tree().quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

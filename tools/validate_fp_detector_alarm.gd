extends Node

const BuildingModelScript := preload("res://sim/BuildingModel.gd")
const FirstPersonControllerScript := preload("res://view/fp/FirstPersonController.gd")

var _failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	await get_tree().process_frame

	var building: BuildingModel = BuildingModelScript.new()
	_expect(building.load_template_data(_make_template()), "BuildingModel rejected FP detector alarm template")

	var fp: FirstPersonController = FirstPersonControllerScript.new()
	fp.name = "ValidateFPDetectorAlarm"
	fp.exterior_context_enabled = false
	fp.show_fp_detectors = true
	fp.show_fp_victims = false
	fp.fp_detector_alarm_enabled = true
	fp.fp_detector_alarm_volume_db = -11.0
	fp.fp_detector_alarm_max_distance_m = 9.0
	add_child(fp)
	await get_tree().process_frame
	fp.setup(building)
	fp.set_active(true)
	await get_tree().physics_frame

	var detector := fp.get_node_or_null("FirstPersonWorld/SafetyMarkers/Detector_det_fp_0") as Node3D
	_expect(detector != null, "FP detector marker was not created")
	if detector == null:
		_finish()
		return
	var alarm := detector.get_node_or_null("DetectorAlarm") as AudioStreamPlayer3D
	_expect(alarm != null, "FP detector alarm player was not created")
	if alarm == null:
		_finish()
		return
	_expect(alarm.stream != null, "FP detector alarm stream missing")
	_expect(not bool(detector.get_meta("alarm_active", false)), "FP detector alarm started active")

	fp.set_state(_make_state(false))
	await get_tree().process_frame
	_expect_color_close(_marker_color(detector), fp.fp_detector_color, 0.02, "FP detector normal color mismatch")
	_expect(not bool(detector.get_meta("alarm_active", false)), "FP detector alarm activated for untriggered detector")
	_expect(not alarm.playing, "FP detector alarm player started for untriggered detector")

	fp.set_state(_make_state(true))
	await get_tree().process_frame
	_expect_color_close(_marker_color(detector), fp.fp_detector_triggered_color, 0.02, "FP detector triggered color mismatch")
	_expect(bool(detector.get_meta("alarm_triggered", false)), "FP detector alarm_triggered metadata missing")
	_expect(bool(detector.get_meta("alarm_active", false)), "FP detector alarm did not become active")
	_expect(alarm.playing, "FP detector alarm player did not start")
	_expect_close(alarm.volume_db, -11.0, 0.01, "FP detector alarm volume mismatch")
	_expect_close(alarm.max_distance, 9.0, 0.01, "FP detector alarm max distance mismatch")

	fp.fp_detector_alarm_enabled = false
	fp.set_state(_make_state(true))
	await get_tree().process_frame
	_expect(not bool(detector.get_meta("alarm_active", false)), "FP detector alarm ignored fp_detector_alarm_enabled=false")
	_expect(not alarm.playing, "FP detector alarm player kept playing when disabled")

	fp.fp_detector_alarm_enabled = true
	fp.show_fp_detectors = false
	fp.set_state(_make_state(true))
	await get_tree().process_frame
	_expect(not detector.visible, "FP detector marker ignored show_fp_detectors=false")
	_expect(not bool(detector.get_meta("alarm_active", false)), "FP detector alarm stayed active while marker hidden")
	_expect(not alarm.playing, "FP detector alarm player kept playing while marker hidden")

	fp.show_fp_detectors = true
	fp.set_state(_make_state(true))
	await get_tree().process_frame
	_expect(bool(detector.get_meta("alarm_active", false)), "FP detector alarm did not reactivate when marker was shown")

	fp.set_active(false)
	await get_tree().process_frame
	_expect(not bool(detector.get_meta("alarm_active", false)), "FP detector alarm stayed active after FP exit")
	_expect(not alarm.playing, "FP detector alarm player kept playing after FP exit")

	remove_child(fp)
	fp.free()
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
				"name": "Salon detector FP",
				"kind": "salon",
				"height_m": 2.5,
				"floor_level_z_m": 0.0,
				"fuel_energy_MJ": 0.0,
				"max_hrr_kw": 0.0,
				"fuel_objects": []
			}
		],
		"openings_data": [
			{"a": 0, "b": -1, "type": "door", "wall": "bottom", "width_m": 0.9, "height_m": 2.0, "open_fraction": 1.0}
		],
		"detectors": [
			{"id": "det_fp_0", "room_id": 0, "type": "smoke", "threshold": 0.02, "x_m": 2.0, "y_m": 1.4}
		],
		"victims": [],
		"player_start": {
			"room_id": 0,
			"position_m": {"x": 0.7, "y": 2.2},
			"floor_level_z_m": 0.0,
			"yaw_deg": 0.0
		},
		"exterior_walls": []
	}


func _make_state(triggered: bool) -> Dictionary:
	return {
		"0": {
			"id": 0,
			"name": "Salon detector FP",
			"kind": "salon",
			"height_m": 2.5,
			"visibility_m": 30.0,
			"smoke_kg": 0.0,
			"smoke_layer_m": 2.5,
			"fuel_objects": []
		},
		"detectors": [
			{"id": "det_fp_0", "room_id": 0, "type": "smoke", "triggered": triggered, "triggered_at_s": 12.0 if triggered else -1.0}
		]
	}


func _marker_color(marker: Node3D) -> Color:
	var mesh := marker.get_node_or_null("MarkerMesh") as MeshInstance3D
	if mesh == null:
		return Color.TRANSPARENT
	var material := mesh.material_override as StandardMaterial3D
	if material == null:
		return Color.TRANSPARENT
	return material.albedo_color


func _finish() -> void:
	if _failures.is_empty():
		print("FP DETECTOR ALARM VALIDATION PASS")
		get_tree().quit(0)
		return
	push_error("FP DETECTOR ALARM VALIDATION FAILED")
	for failure in _failures:
		push_error("- " + failure)
	get_tree().quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _expect_close(actual: float, expected: float, tolerance: float, message: String) -> void:
	if absf(actual - expected) > tolerance:
		_failures.append("%s (actual=%.4f expected=%.4f)" % [message, actual, expected])


func _expect_color_close(actual: Color, expected: Color, tolerance: float, message: String) -> void:
	var delta: float = absf(actual.r - expected.r) + absf(actual.g - expected.g) + absf(actual.b - expected.b) + absf(actual.a - expected.a)
	if delta > tolerance:
		_failures.append("%s (actual=%s expected=%s)" % [message, str(actual), str(expected)])

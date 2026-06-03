extends Node

const BuildingModelScript := preload("res://sim/BuildingModel.gd")
const FirstPersonControllerScript := preload("res://view/fp/FirstPersonController.gd")

var _failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	await get_tree().process_frame

	var building: BuildingModel = BuildingModelScript.new()
	_expect(building.load_template_data(_make_template()), "BuildingModel rejected FP player-start template")

	var fp: FirstPersonController = FirstPersonControllerScript.new()
	fp.name = "ValidateFPPlayerStart"
	fp.exterior_context_enabled = false
	fp.show_fp_detectors = false
	fp.show_fp_victims = false
	add_child(fp)
	await get_tree().process_frame
	fp.setup(building)
	await get_tree().physics_frame

	_expect_vec3_close(
		fp.global_position,
		Vector3(-0.75, 2.80, 0.60),
		0.02,
		"FP controller did not restore player_start position"
	)
	_expect_angle_close(rad_to_deg(fp.rotation.y), 123.0, 0.05, "FP controller did not restore player_start yaw")

	var marker_state: Dictionary = fp.get_player_marker_state()
	_expect(int(marker_state.get("room_id", -1)) == 0, "FP marker state did not report the restored room")
	_expect_vec2_close(
		Vector2(marker_state.get("position_m", Vector2.ZERO)),
		Vector2(4.25, 3.10),
		0.02,
		"FP marker state did not report absolute floor-plan position"
	)
	_expect_close(float(marker_state.get("floor_level_z_m", -1.0)), 2.75, 0.01, "FP marker state floor mismatch")
	_expect_angle_close(float(marker_state.get("yaw_deg", 0.0)), 123.0, 0.05, "FP marker state yaw mismatch")

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
			"0": {"x": 3.0, "y": 1.0, "w": 4.0, "h": 3.0}
		},
		"rooms_data": [
			{
				"id": 0,
				"name": "Salon inicio FP",
				"kind": "salon",
				"height_m": 2.5,
				"floor_level_z_m": 2.75,
				"fuel_energy_MJ": 120.0,
				"max_hrr_kw": 300.0,
				"fuel_objects": []
			}
		],
		"openings_data": [
			{"a": 0, "b": -1, "type": "door", "wall": "bottom", "width_m": 0.9, "height_m": 2.0, "open_fraction": 1.0}
		],
		"detectors": [],
		"victims": [],
		"player_start": {
			"room_id": 0,
			"position_m": {"x": 1.25, "y": 2.10},
			"floor_level_z_m": 2.75,
			"yaw_deg": 123.0
		},
		"exterior_walls": []
	}


func _finish() -> void:
	if _failures.is_empty():
		print("FP PLAYER START VALIDATION PASS")
		get_tree().quit(0)
		return
	push_error("FP PLAYER START VALIDATION FAILED")
	for failure in _failures:
		push_error("- " + failure)
	get_tree().quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _expect_close(actual: float, expected: float, tolerance: float, message: String) -> void:
	if absf(actual - expected) > tolerance:
		_failures.append("%s (actual=%.4f expected=%.4f)" % [message, actual, expected])


func _expect_angle_close(actual_deg: float, expected_deg: float, tolerance: float, message: String) -> void:
	var delta: float = absf(wrapf(actual_deg - expected_deg, -180.0, 180.0))
	if delta > tolerance:
		_failures.append("%s (actual=%.4f expected=%.4f)" % [message, actual_deg, expected_deg])


func _expect_vec2_close(actual: Vector2, expected: Vector2, tolerance: float, message: String) -> void:
	if actual.distance_to(expected) > tolerance:
		_failures.append("%s (actual=%s expected=%s)" % [message, str(actual), str(expected)])


func _expect_vec3_close(actual: Vector3, expected: Vector3, tolerance: float, message: String) -> void:
	if actual.distance_to(expected) > tolerance:
		_failures.append("%s (actual=%s expected=%s)" % [message, str(actual), str(expected)])

extends Node

const BuildingModelScript := preload("res://sim/BuildingModel.gd")
const FirstPersonControllerScript := preload("res://view/fp/FirstPersonController.gd")

var _failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	await get_tree().process_frame

	var building: BuildingModel = BuildingModelScript.new()
	_expect(building.load_template_data(_make_template()), "BuildingModel rejected stance easing template")

	var fp: FirstPersonController = FirstPersonControllerScript.new()
	fp.name = "ValidateFPStanceEasing"
	fp.exterior_context_enabled = false
	fp.show_fp_detectors = false
	fp.show_fp_victims = false
	add_child(fp)
	await get_tree().process_frame
	fp.setup(building)
	fp.set_active(true)
	await get_tree().physics_frame

	var camera := fp.get_node_or_null("FirstPersonCamera") as Camera3D
	_expect(camera != null, "FP camera node not found")
	if camera == null:
		_finish()
		return

	# Stand snap on init: camera must already be at stand target (1.72 m).
	_expect_close(camera.position.y, 1.72, 0.02, "stand camera height wrong after init snap")

	# Cycle to crouch: camera must NOT yet be at crouch target (0.97 m) — easing is active.
	fp._cycle_stance()
	_expect(
		absf(camera.position.y - 0.97) > 0.05,
		"camera snapped immediately on _cycle_stance — easing not active"
	)

	# After 30 physics frames the camera must reach near crouch target.
	for _i in range(30):
		await get_tree().physics_frame
	_expect_close(camera.position.y, 0.97, 0.02, "camera did not reach crouch target after easing")

	# Cycle to prone: easing from crouch to prone target (0.28 m).
	fp._cycle_stance()
	for _i in range(30):
		await get_tree().physics_frame
	_expect_close(camera.position.y, 0.28, 0.02, "camera did not reach prone target after easing")

	# Cycle back to stand: easing from prone to stand target (1.72 m).
	fp._cycle_stance()
	for _i in range(30):
		await get_tree().physics_frame
	_expect_close(camera.position.y, 1.72, 0.02, "camera did not return to stand target after easing")

	fp.set_active(false)
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
				"name": "Salon easing",
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
		"detectors": [],
		"victims": [],
		"player_start": {
			"room_id": 0,
			"position_m": {"x": 2.0, "y": 1.5},
			"floor_level_z_m": 0.0,
			"yaw_deg": 0.0
		},
		"exterior_walls": []
	}


func _finish() -> void:
	if _failures.is_empty():
		print("FP STANCE EASING VALIDATION PASS")
		get_tree().quit(0)
		return
	push_error("FP STANCE EASING VALIDATION FAILED")
	for failure in _failures:
		push_error("- " + failure)
	get_tree().quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _expect_close(actual: float, expected: float, tolerance: float, message: String) -> void:
	if absf(actual - expected) > tolerance:
		_failures.append("%s (actual=%.3f expected=%.3f tol=%.3f)" % [message, actual, expected, tolerance])

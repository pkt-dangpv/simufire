extends Node

const BuildingModelScript := preload("res://sim/BuildingModel.gd")
const FirstPersonControllerScript := preload("res://view/fp/FirstPersonController.gd")

var _failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	await get_tree().process_frame

	var building: BuildingModel = BuildingModelScript.new()
	_expect(building.load_template_data(_make_template()), "BuildingModel rejected FP victim template")

	var fp: FirstPersonController = FirstPersonControllerScript.new()
	fp.name = "ValidateFPVictimStates"
	fp.exterior_context_enabled = false
	fp.show_fp_detectors = false
	fp.show_fp_victims = true
	add_child(fp)
	await get_tree().process_frame
	fp.setup(building)
	fp.set_active(true)
	await get_tree().physics_frame

	var victim := fp.get_node_or_null("FirstPersonWorld/SafetyMarkers/Victim_vic_fp_0") as Node3D
	_expect(victim != null, "FP victim marker was not created")
	if victim == null:
		_finish()
		return
	_expect(victim.visible, "FP victim marker starts hidden")

	fp.set_state(_make_state(0.0))
	_expect_color_close(_marker_color(victim), fp.fp_victim_color, 0.02, "FP victim normal FED color mismatch")

	fp.set_state(_make_state(0.35))
	_expect_color_close(
		_marker_color(victim),
		fp.fp_victim_incapacitated_color,
		0.02,
		"FP victim incapacitated FED color mismatch"
	)

	fp.set_state(_make_state(1.20))
	_expect_color_close(_marker_color(victim), fp.fp_victim_fatal_color, 0.02, "FP victim fatal FED color mismatch")

	fp.show_fp_victims = false
	fp.set_state(_make_state(1.20))
	_expect(not victim.visible, "FP victim marker ignored show_fp_victims=false")

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
				"name": "Salon victima",
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
		"victims": [
			{"id": "vic_fp_0", "name": "Victima FP", "room_id": 0, "x_m": 2.0, "y_m": 1.4, "height_m": 0.9}
		],
		"player_start": {
			"room_id": 0,
			"position_m": {"x": 0.7, "y": 2.2},
			"floor_level_z_m": 0.0,
			"yaw_deg": 0.0
		},
		"exterior_walls": []
	}


func _make_state(fed: float) -> Dictionary:
	return {
		"0": {
			"id": 0,
			"name": "Salon victima",
			"kind": "salon",
			"height_m": 2.5,
			"visibility_m": 30.0,
			"smoke_kg": 0.0,
			"smoke_layer_m": 2.5,
			"fuel_objects": []
		},
		"victims": [
			{"id": "vic_fp_0", "fed": fed}
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
		print("FP VICTIM STATES VALIDATION PASS")
		get_tree().quit(0)
		return
	push_error("FP VICTIM STATES VALIDATION FAILED")
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

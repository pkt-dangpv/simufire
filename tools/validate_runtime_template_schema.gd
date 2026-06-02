extends Node

const BuildingModelScript := preload("res://sim/BuildingModel.gd")

var _failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	await get_tree().process_frame

	var building: BuildingModel = BuildingModelScript.new()
	var valid_template: Dictionary = _make_valid_template()
	_expect(building.validate_template_data(valid_template).is_empty(), "valid template reported schema errors")
	_expect(building.load_template_data(valid_template), "valid template was not loaded")
	_expect(building.get_rooms().size() == 1, "valid template did not create one room")
	_expect(building.get_opening_count() == 1, "valid template did not create one opening")

	var previous_room_count: int = building.get_rooms().size()
	_expect(not building.load_template_data({}), "empty template should be rejected")
	_expect(building.get_rooms().size() == previous_room_count, "invalid load cleared existing rooms")

	var missing_rect := _make_valid_template()
	missing_rect["room_rect_m"] = {}
	_expect(_has_schema_error(missing_rect, "room_rect_m"), "missing room rect should report schema error")
	_expect(not building.load_template_data(missing_rect), "missing room rect template should be rejected")
	_expect(building.get_rooms().size() == previous_room_count, "missing rect load cleared existing rooms")

	var broken_opening := _make_valid_template()
	var openings: Array = Array(broken_opening.get("openings_data", []))
	if not openings.is_empty() and typeof(openings[0]) == TYPE_DICTIONARY:
		var op: Dictionary = Dictionary(openings[0])
		op["b"] = 99
		openings[0] = op
	broken_opening["openings_data"] = openings
	_expect(_has_schema_error(broken_opening, "sala b=99"), "bad opening target should report schema error")
	_expect(not building.load_template_data(broken_opening), "bad opening template should be rejected")

	var bad_player_start := _make_valid_template()
	bad_player_start["player_start"] = {"room_id": 42, "position_m": {"x": 0.5, "y": 0.5}}
	_expect(_has_schema_error(bad_player_start, "player_start"), "bad player_start should report schema error")
	_expect(not building.load_template_data(bad_player_start), "bad player_start template should be rejected")

	var empty_editor_template: Dictionary = _make_empty_editor_template()
	_expect(building.validate_template_data(empty_editor_template, true).is_empty(), "empty editor template should be valid for preview")
	_expect(building.load_template_data(empty_editor_template, true), "empty editor template should load in preview mode")
	_expect(building.get_rooms().is_empty(), "empty editor template did not clear rooms")

	building.free()
	_finish()


func _make_valid_template() -> Dictionary:
	return {
		"version": 1,
		"building_type": "single_family",
		"outside_temp_c": 20.0,
		"outside_o2": 0.209,
		"stop_time_s": 0.0,
		"hvac_mode": "none",
		"hvac_data": {"exists": false, "on": false, "mode": "none"},
		"room_rect_m": {
			"0": {"x": 0.0, "y": 0.0, "w": 4.0, "h": 4.0}
		},
		"rooms_data": [
			{
				"id": 0,
				"name": "Sala ensayo",
				"kind": "salon",
				"height_m": 2.4,
				"fuel_energy_MJ": 1000.0,
				"max_hrr_kw": 800.0,
				"fuel_objects": [
					{
						"id": "sofa_test",
						"name": "Sofa test",
						"kind": "sofa",
						"room_id": 0,
						"position_m": {"x": 1.0, "y": 1.0},
						"size_m": {"x": 1.5, "y": 0.8},
						"fuel_energy_MJ": 200.0,
						"max_hrr_kw": 300.0
					}
				]
			}
		],
		"openings_data": [
			{"a": 0, "b": -1, "type": "door", "width_m": 0.9, "height_m": 2.0, "open_fraction": 1.0}
		],
		"detectors": [
			{"id": "det_0", "room_id": 0, "type": "smoke", "threshold": 0.01}
		],
		"victims": [
			{"id": "vic_0", "name": "Victima ensayo", "room_id": 0, "height_m": 0.9}
		],
		"player_start": {
			"room_id": 0,
			"position_m": {"x": 2.0, "y": 2.0},
			"floor_level_z_m": 0.0,
			"yaw_deg": 0.0
		},
		"exterior_walls": []
	}


func _make_empty_editor_template() -> Dictionary:
	return {
		"version": 1,
		"room_rect_m": {},
		"rooms_data": [],
		"openings_data": [],
		"detectors": [],
		"victims": [],
		"player_start": {},
		"exterior_walls": []
	}


func _has_schema_error(template_data: Dictionary, token: String) -> bool:
	var building: BuildingModel = BuildingModelScript.new()
	var errors: Array[String] = building.validate_template_data(template_data)
	building.free()
	for error in errors:
		if error.contains(token):
			return true
	return false


func _finish() -> void:
	if _failures.is_empty():
		print("RUNTIME TEMPLATE SCHEMA VALIDATION PASS")
		get_tree().quit(0)
		return
	push_error("RUNTIME TEMPLATE SCHEMA VALIDATION FAILED")
	for failure in _failures:
		push_error("- " + failure)
	get_tree().quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

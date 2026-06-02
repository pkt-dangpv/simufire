extends Node

const BuildingModelScript := preload("res://sim/BuildingModel.gd")
const Serializer := preload("res://editor/ScenarioSerializer.gd")
const SimulationEngineScript := preload("res://sim/core/SimulationEngine.gd")

const WORK_DIR: String = "user://editor_to_sim_flow_validation"
const RUNTIME_TEMPLATE_PATH: String = WORK_DIR + "/last_editor_runtime_template.json"
const OUTPUT_DIR_PATH: String = WORK_DIR + "/export"

var _failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	await get_tree().process_frame

	var work_dir_abs: String = ProjectSettings.globalize_path(WORK_DIR)
	var output_dir_abs: String = ProjectSettings.globalize_path(OUTPUT_DIR_PATH)
	DirAccess.make_dir_recursive_absolute(work_dir_abs)
	DirAccess.make_dir_recursive_absolute(output_dir_abs)

	var editor_data: Dictionary = _make_editor_data()
	_expect(Serializer.save_runtime_template(RUNTIME_TEMPLATE_PATH, editor_data), "runtime template was not written")
	_expect(FileAccess.file_exists(RUNTIME_TEMPLATE_PATH), "runtime template file does not exist")

	var runtime_template: Dictionary = _load_json(RUNTIME_TEMPLATE_PATH)
	_expect(not runtime_template.is_empty(), "runtime template JSON could not be loaded")
	_expect(String(runtime_template.get("exterior_lighting_mode", "")) == "Noche", "lighting option did not survive export")
	_expect(bool(runtime_template.get("interior_lights_on", true)) == false, "interior light option did not survive export")

	var building: BuildingModel = BuildingModelScript.new()
	_expect(building.validate_template_data(runtime_template).is_empty(), "exported runtime template failed schema validation")
	_expect(building.load_template_data(runtime_template), "BuildingModel rejected exported runtime template")
	_validate_loaded_building(building)

	var engine: SimulationEngine = SimulationEngineScript.new()
	engine.name = "EditorToSimFlowEngine"
	engine.building = building
	engine.auto_ignite_on_ready = false
	engine.auto_finish_on_extinction = false
	engine.time_scale = 1.0
	engine.enable_logging = true
	engine.enable_csv_log = true
	engine.log_interval_s = 0.25
	engine.log_file_path = output_dir_abs.path_join("sim_log.txt")
	engine.csv_log_file_path = output_dir_abs.path_join("sim_log.csv")

	engine.reset_simulation(building.default_ignition_room_id, true)
	engine.sim_duration_limit_s = 0.0
	var previous_time_s: float = engine.sim_time_s
	engine.step(0.1)
	_expect(engine.sim_time_s > previous_time_s, "simulation time did not advance")
	_expect(not engine.get_state().is_empty(), "SimulationEngine returned empty state")
	_expect(engine.export_technical_results("editor_to_sim_flow", output_dir_abs), "technical export failed")
	_validate_export(output_dir_abs)

	engine.free()
	building.free()
	_finish()


func _validate_loaded_building(building: BuildingModel) -> void:
	_expect(building.get_rooms().size() == 2, "expected two rooms from editor runtime template")
	_expect(building.get_opening_count() == 2, "expected two openings from editor runtime template")
	_expect(building.default_ignition_room_id == 0, "ignition room was not preserved")
	_expect(building.sim_stop_time_s == 12.0, "stop_time_s was not loaded")
	_expect(building.exterior_lighting_mode == "Noche", "exterior lighting mode was not loaded")
	_expect(not building.interior_lights_on, "interior_lights_on was not loaded")
	_expect(building.detectors.size() == 1, "detector was not loaded")
	_expect(building.victims.size() == 1, "victim was not loaded")
	_expect(int(building.player_start.get("room_id", -1)) == 0, "player_start room was not loaded")

	var room: RoomModel = building.get_room(0)
	_expect(room != null, "room 0 missing")
	if room == null:
		return
	_expect(room.fuel_objects.size() == 1, "room fuel object missing")
	if room.fuel_objects.is_empty():
		return
	var obj: FuelObjectModel = room.fuel_objects[0] as FuelObjectModel
	_expect(obj != null, "fuel object type mismatch")
	if obj == null:
		return
	_expect(obj.id == "flow_sofa", "fuel object id was not preserved")
	_expect_close(obj.position_m.x, 1.35, 0.01, "fuel object x was not preserved")
	_expect_close(obj.position_m.y, 1.10, 0.01, "fuel object y was not preserved")
	_expect_close(obj.rotation_deg, 18.0, 0.01, "fuel object rotation was not preserved")
	_expect(obj.visual_pose_locked, "fuel object visual pose lock was not preserved")


func _validate_export(output_dir_abs: String) -> void:
	for filename in ["summary.json", "events.json", "sim_log.txt", "sim_log.csv"]:
		_expect(FileAccess.file_exists(output_dir_abs.path_join(filename)), "%s was not exported" % filename)

	var summary: Dictionary = _load_json(output_dir_abs.path_join("summary.json"))
	_expect(String(summary.get("schema_version", "")) == "simufire_technical_summary_v1", "summary schema mismatch")
	_expect(float(summary.get("sim_duration_s", 0.0)) > 0.0, "summary duration did not advance")
	_expect(Array(summary.get("rooms", [])).size() == 2, "summary did not include exported rooms")
	_expect(Array(summary.get("victims", [])).size() == 1, "summary did not include exported victim")
	_expect(Array(summary.get("detectors", [])).size() == 1, "summary did not include exported detector")


func _make_editor_data() -> Dictionary:
	return {
		"version": 1,
		"building_type": "single_family",
		"outside_temp_c": 20.0,
		"outside_o2": 0.209,
		"stop_time_s": 12.0,
		"ignition_room_id": 0,
		"hvac_mode": "none",
		"hvac_data": {"exists": false, "on": false, "mode": "none"},
		"interior_lights_on": false,
		"exterior_lighting_mode": "Noche",
		"floors": [{"name": "PB", "level_m": 0.0}],
		"room_rect_m": {
			"0": {"x": 0.0, "y": 0.0, "w": 4.0, "h": 3.2},
			"1": {"x": 4.0, "y": 0.0, "w": 2.4, "h": 3.2}
		},
		"rooms_data": [
			{
				"id": 0,
				"name": "Salon test",
				"kind": "salon",
				"height_m": 2.5,
				"floor_level_z_m": 0.0,
				"fuel_energy_MJ": 450.0,
				"max_hrr_kw": 500.0,
				"fuel_objects": [
					{
						"id": "flow_sofa",
						"name": "Sofa flujo",
						"kind": "sofa",
						"room_id": 0,
						"position_m": {"x": 1.35, "y": 1.10},
						"size_m": {"x": 1.7, "y": 0.85},
						"rotation_deg": 18.0,
						"visual_pose_locked": true,
						"footprint_m2": 1.45,
						"fuel_energy_MJ": 240.0,
						"max_hrr_kw": 360.0,
						"is_primary_ignition_source": true
					}
				]
			},
			{
				"id": 1,
				"name": "Pasillo test",
				"kind": "pasillo",
				"height_m": 2.5,
				"floor_level_z_m": 0.0,
				"fuel_energy_MJ": 0.0,
				"max_hrr_kw": 0.0,
				"fuel_objects": []
			}
		],
		"openings_data": [
			{"a": 0, "b": 1, "type": "door", "wall": "right", "width_m": 0.9, "height_m": 2.0, "open_fraction": 1.0},
			{"a": 0, "b": -1, "type": "window", "wall": "bottom", "width_m": 1.2, "height_m": 1.0, "sill_m": 0.9, "open_fraction": 0.25}
		],
		"detectors": [
			{"id": "det_flow_0", "room_id": 0, "type": "smoke", "threshold": 0.01, "x_m": 2.0, "y_m": 1.5}
		],
		"victims": [
			{"id": "vic_flow_0", "name": "Victima flujo", "room_id": 1, "x_m": 5.0, "y_m": 1.5, "height_m": 0.9}
		],
		"player_start": {
			"room_id": 0,
			"position_m": {"x": 0.8, "y": 2.2},
			"floor_level_z_m": 0.0,
			"yaw_deg": 45.0
		},
		"exterior_walls": []
	}


func _load_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return Dictionary(parsed) if typeof(parsed) == TYPE_DICTIONARY else {}


func _finish() -> void:
	if _failures.is_empty():
		print("EDITOR TO SIM FLOW VALIDATION PASS")
		get_tree().quit(0)
		return
	push_error("EDITOR TO SIM FLOW VALIDATION FAILED")
	for failure in _failures:
		push_error("- " + failure)
	get_tree().quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _expect_close(actual: float, expected: float, tolerance: float, message: String) -> void:
	if absf(actual - expected) > tolerance:
		_failures.append("%s (actual=%.4f expected=%.4f)" % [message, actual, expected])

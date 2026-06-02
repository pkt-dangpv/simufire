extends Node

const BuildingModelScript := preload("res://sim/BuildingModel.gd")
const MainScript := preload("res://Main.gd")
const SimulationEngineScript := preload("res://sim/core/SimulationEngine.gd")

var _failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	await get_tree().process_frame

	var building: BuildingModel = BuildingModelScript.new()
	building.load_template_data(_make_template())

	var engine: SimulationEngine = SimulationEngineScript.new()
	engine.building = building
	engine.sim_time_s = 180.0

	var room: RoomModel = building.get_room(0)
	_expect(room != null, "expected room 0")
	if room != null:
		room.flashover_triggered = true
		room.flashover_time_s = 72.5
		room.fed = 0.74
		room.visibility_m = 2.35
		room.o2 = 0.151
		room.o2_lower = 0.146
		engine._room_peak_hrr[0] = 1250.0
		engine._room_peak_hrr_time[0] = 80.0
		engine._room_peak_temp[0] = 612.0
		engine._room_peak_temp_time[0] = 91.0
		engine._room_peak_co_upper[0] = 3420.0
		engine._room_peak_co_upper_time[0] = 105.0
		engine._room_peak_hcn_upper[0] = 18.4
		engine._room_peak_hcn_upper_time[0] = 108.0
		engine._room_min_o2[0] = 0.146
		engine._room_min_o2_time[0] = 112.0
		engine._room_min_visibility[0] = 2.35
		engine._room_min_visibility_time[0] = 119.0
		engine._room_peak_fed[0] = 0.74
		engine._room_peak_fed_time[0] = 180.0
		engine._room_min_svv[0] = 44.0
		engine._room_min_svv_time[0] = 160.0

	if not building.detectors.is_empty():
		building.detectors[0]["triggered"] = true
		building.detectors[0]["triggered_at_s"] = 35.0

	if not building.victims.is_empty():
		building.victims[0]["fed"] = 1.04
		building.victims[0]["incapacitated"] = true
		building.victims[0]["incapacitated_at_s"] = 142.0

	var output_dir: String = ProjectSettings.globalize_path("user://technical_summary_validation")
	DirAccess.make_dir_recursive_absolute(output_dir)
	engine._write_export_json(output_dir)

	var summary: Dictionary = engine.get_last_technical_summary()
	_validate_summary(summary)
	_validate_summary_file(output_dir.path_join("summary.json"))

	if _failures.is_empty():
		print("TECHNICAL SUMMARY VALIDATION PASS")
		get_tree().quit(0)
		return

	push_error("TECHNICAL SUMMARY VALIDATION FAILED")
	for failure in _failures:
		push_error("- " + failure)
	get_tree().quit(1)


func _validate_summary(summary: Dictionary) -> void:
	_expect(String(summary.get("schema_version", "")) == "simufire_technical_summary_v1", "schema version mismatch")
	_expect_close(float(summary.get("sim_duration_s", 0.0)), 180.0, 0.01, "duration mismatch")

	var global_summary: Dictionary = Dictionary(summary.get("global", {}))
	_expect_close(float(global_summary.get("peak_hrr_kw", 0.0)), 1250.0, 0.01, "global peak HRR missing")
	_expect_close(float(global_summary.get("peak_co_upper_ppm", 0.0)), 3420.0, 0.01, "global peak CO missing")
	_expect_close(float(global_summary.get("peak_hcn_upper_ppm", 0.0)), 18.4, 0.01, "global peak HCN missing")
	_expect_close(float(global_summary.get("min_o2_pct", 0.0)), 14.6, 0.01, "global min O2 missing")
	_expect_close(float(global_summary.get("min_visibility_m", 0.0)), 2.35, 0.01, "global min visibility missing")
	_expect(int(global_summary.get("detectors_triggered", 0)) == 1, "triggered detector count missing")
	_expect(int(global_summary.get("victims_incapacitated", 0)) == 1, "incapacitated victim count missing")

	var rooms: Array = Array(summary.get("rooms", []))
	_expect(rooms.size() == 1, "expected one room summary")
	if not rooms.is_empty():
		var room: Dictionary = Dictionary(rooms[0])
		_expect(bool(room.get("flashover_triggered", false)), "room flashover missing")
		_expect_close(float(room.get("flashover_time_s", -1.0)), 72.5, 0.01, "room flashover time missing")
		_expect_close(float(room.get("peak_hrr_time_s", -1.0)), 80.0, 0.01, "room peak HRR time missing")

	var victims: Array = Array(summary.get("victims", []))
	_expect(victims.size() == 1, "expected one victim summary")
	if not victims.is_empty():
		var victim: Dictionary = Dictionary(victims[0])
		_expect_close(float(victim.get("time_to_fed_1_s", -1.0)), 142.0, 0.01, "victim FED=1 time missing")

	var detectors: Array = Array(summary.get("detectors", []))
	_expect(detectors.size() == 1, "expected one detector summary")
	if not detectors.is_empty():
		var detector: Dictionary = Dictionary(detectors[0])
		_expect(bool(detector.get("triggered", false)), "detector triggered flag missing")
		_expect_close(float(detector.get("triggered_at_s", -1.0)), 35.0, 0.01, "detector trigger time missing")


func _validate_summary_file(path: String) -> void:
	_expect(FileAccess.file_exists(path), "summary.json was not written")
	var file := FileAccess.open(path, FileAccess.READ)
	_expect(file != null, "summary.json could not be opened")
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	_expect(typeof(parsed) == TYPE_DICTIONARY, "summary.json is not a dictionary")
	if typeof(parsed) == TYPE_DICTIONARY:
		_expect(String(Dictionary(parsed).get("schema_version", "")) == "simufire_technical_summary_v1", "summary.json schema mismatch")


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
				"fuel_objects": []
			}
		],
		"openings_data": [],
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


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _expect_close(actual: float, expected: float, tolerance: float, message: String) -> void:
	if absf(actual - expected) > tolerance:
		_failures.append("%s (actual=%.4f expected=%.4f)" % [message, actual, expected])

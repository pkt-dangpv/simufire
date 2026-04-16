extends Node
class_name CaseRunner

const BuildingTemplateScript = preload("res://sim/templates/BuildingTemplate.gd")

@export var building_path: NodePath
@export var engine_path: NodePath
@export var reports_dir: String = "res://sim/validation/reports"
@export var auto_quit: bool = true

var building: BuildingModel
var engine: SimulationEngine

var _active: bool = false
var _case_name: String = ""
var _case_config: Dictionary = {}
var _cli_args: Dictionary = {}
var _metrics: Dictionary = {}
var _output_path: String = ""
var _baseline_path: String = ""


func _ready() -> void:
	_resolve_refs()
	_cli_args = _parse_validation_args(OS.get_cmdline_user_args())
	if _cli_args.is_empty():
		return

	call_deferred("_begin_validation_run")


func _process(_delta: float) -> void:
	if not _active or engine == null:
		return

	var state: Dictionary = engine.get_state()
	_update_metrics(state)

	var sim_time_s: float = float(state.get("sim_time_s", 0.0))
	var duration_s: float = float(_case_config.get("duration_s", 600.0))
	if sim_time_s >= duration_s:
		_finalize_validation_run(state)


func _resolve_refs() -> void:
	if not building_path.is_empty():
		building = get_node_or_null(building_path) as BuildingModel
	if not engine_path.is_empty():
		engine = get_node_or_null(engine_path) as SimulationEngine


func _parse_validation_args(args: Array[String]) -> Dictionary:
	var parsed: Dictionary = {}
	var index: int = 0
	while index < args.size():
		var arg: String = String(args[index])
		if arg.begins_with("--validation-case="):
			parsed["validation_case"] = arg.get_slice("=", 1)
		elif arg == "--validation-case" and index + 1 < args.size():
			index += 1
			parsed["validation_case"] = String(args[index])
		elif arg.begins_with("--validation-output="):
			parsed["validation_output"] = arg.get_slice("=", 1)
		elif arg == "--validation-output" and index + 1 < args.size():
			index += 1
			parsed["validation_output"] = String(args[index])
		elif arg.begins_with("--validation-duration="):
			parsed["validation_duration"] = float(arg.get_slice("=", 1))
		elif arg == "--validation-duration" and index + 1 < args.size():
			index += 1
			parsed["validation_duration"] = float(args[index])
		elif arg == "--validation-no-quit":
			parsed["validation_no_quit"] = true
		index += 1

	if not parsed.has("validation_case"):
		return {}

	return parsed


func _begin_validation_run() -> void:
	if building == null or engine == null:
		push_error("CaseRunner: faltan referencias a BuildingModel / SimulationEngine")
		if auto_quit:
			get_tree().quit(1)
		return

	_case_name = String(_cli_args.get("validation_case", ""))
	_case_config = _load_case_config(_case_name)
	if _case_config.is_empty():
		push_error("CaseRunner: no se pudo cargar el caso '%s'" % _case_name)
		if auto_quit:
			get_tree().quit(1)
		return

	if _cli_args.has("validation_duration"):
		_case_config["duration_s"] = float(_cli_args["validation_duration"])

	var template_data: Dictionary = _build_case_template(_case_config)
	if template_data.is_empty():
		push_error("CaseRunner: template vacio para '%s'" % _case_name)
		if auto_quit:
			get_tree().quit(1)
		return

	building.load_template_data(template_data)
	_apply_engine_overrides(Dictionary(_case_config.get("engine_overrides", {})))
	engine.enable_logging = bool(_case_config.get("enable_logging", false))
	engine.ignition_room_id = int(_case_config.get("ignition_room_id", engine.ignition_room_id))
	engine.reset_simulation(engine.ignition_room_id, bool(_case_config.get("ignite_on_start", true)))

	_metrics.clear()
	_output_path = String(_cli_args.get(
		"validation_output",
		"%s/%s.json" % [reports_dir, _case_name]
	))
	_baseline_path = "res://sim/validation/baselines/%s.json" % _case_name
	_active = true

	print("[Validation] Ejecutando caso '%s' hasta %.1f s" % [
		_case_name,
		float(_case_config.get("duration_s", 600.0))
	])


func _load_case_config(case_name: String) -> Dictionary:
	var path: String = "res://sim/validation/cases/%s.json" % case_name
	var text: String = _read_text_file(path)
	if text.is_empty():
		return {}

	var parsed: Variant = JSON.parse_string(text)
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


func _build_case_template(case_config: Dictionary) -> Dictionary:
	var template_name: String = String(case_config.get("template", "simple_house"))
	var builder = BuildingTemplateScript.new()
	var template_data: Dictionary = {}

	match template_name:
		"simple_house":
			template_data = builder.create_simple_house()
		_:
			push_error("CaseRunner: template no soportado '%s'" % template_name)
			return {}

	_apply_room_overrides(template_data, case_config.get("room_overrides", []))
	_apply_opening_overrides(template_data, case_config.get("opening_overrides", []))
	return template_data


func _apply_room_overrides(template_data: Dictionary, overrides: Variant) -> void:
	if typeof(overrides) != TYPE_ARRAY:
		return

	var rooms_data: Array = template_data.get("rooms_data", [])
	for override_entry in overrides:
		if typeof(override_entry) != TYPE_DICTIONARY:
			continue

		var override_data: Dictionary = override_entry
		var room_id: int = int(override_data.get("id", -1))
		for room_entry in rooms_data:
			if typeof(room_entry) != TYPE_DICTIONARY:
				continue
			var room_data: Dictionary = room_entry
			if int(room_data.get("id", -1)) != room_id:
				continue

			for key in override_data.keys():
				if key == "id":
					continue
				room_data[key] = override_data[key]
			break


func _apply_opening_overrides(template_data: Dictionary, overrides: Variant) -> void:
	if typeof(overrides) != TYPE_ARRAY:
		return

	var openings_data: Array = template_data.get("openings_data", [])
	for override_entry in overrides:
		if typeof(override_entry) != TYPE_DICTIONARY:
			continue

		var override_data: Dictionary = override_entry
		var a_id: int = int(override_data.get("a", 999999))
		var b_id: int = int(override_data.get("b", 999999))
		var type_name: String = String(override_data.get("type", ""))

		for opening_entry in openings_data:
			if typeof(opening_entry) != TYPE_DICTIONARY:
				continue
			var opening_data: Dictionary = opening_entry
			if int(opening_data.get("a", -1)) != a_id:
				continue
			if int(opening_data.get("b", -1)) != b_id:
				continue
			if type_name != "" and String(opening_data.get("type", "")) != type_name:
				continue

			for key in override_data.keys():
				if key == "a" or key == "b" or key == "type":
					continue
				opening_data[key] = override_data[key]
			break


func _apply_engine_overrides(overrides: Dictionary) -> void:
	for key in overrides.keys():
		engine.set(String(key), overrides[key])


func _update_metrics(state: Dictionary) -> void:
	var sim_time_s: float = float(state.get("sim_time_s", 0.0))
	var room_ids: Array[int] = _collect_room_ids(state)
	var watch_room_ids: Array[int] = _get_watch_room_ids()
	if room_ids.is_empty():
		return

	var global_peak_hrr_kw: float = float(_metrics.get("peak_hrr_kw_global", 0.0))
	var global_peak_temp_upper_c: float = float(_metrics.get("peak_temp_upper_c_global", 0.0))
	var global_peak_co_ppm: float = float(_metrics.get("peak_co_ppm_global", 0.0))
	var all_rooms_extinguished: bool = true
	var all_rooms_quiescent: bool = true

	for room_id in room_ids:
		var room_state: Dictionary = state.get(str(room_id), {})
		if room_state.is_empty():
			continue

		var hrr_kw: float = float(room_state.get("hrr_kw", 0.0))
		var temp_upper_c: float = float(room_state.get("temp_upper_c", 0.0))
		var co_ppm: float = float(room_state.get("co_ppm", 0.0))

		global_peak_hrr_kw = maxf(global_peak_hrr_kw, hrr_kw)
		global_peak_temp_upper_c = maxf(global_peak_temp_upper_c, temp_upper_c)
		global_peak_co_ppm = maxf(global_peak_co_ppm, co_ppm)

		if hrr_kw > 0.01:
			all_rooms_extinguished = false
		if not bool(room_state.get("is_quiescent", false)):
			all_rooms_quiescent = false
		if watch_room_ids.has(room_id):
			_update_room_peak_metrics(room_id, room_state)

	_metrics["peak_hrr_kw_global"] = global_peak_hrr_kw
	_metrics["peak_temp_upper_c_global"] = global_peak_temp_upper_c
	_metrics["peak_co_ppm_global"] = global_peak_co_ppm

	var trigger_room_id: int = int(_case_config.get("smoke_trigger_room_id", 0))
	var target_room_id: int = int(_case_config.get("spread_target_room_id", 1))
	var l150_room_id: int = int(_case_config.get("l150_room_id", trigger_room_id))

	var trigger_room_state: Dictionary = state.get(str(trigger_room_id), {})
	var target_room_state: Dictionary = state.get(str(target_room_id), {})
	var l150_room_state: Dictionary = state.get(str(l150_room_id), {})

	if not trigger_room_state.is_empty():
		if not _metrics.has("time_room_%d_smoke_layer_2m_s" % trigger_room_id):
			if float(trigger_room_state.get("smoke_layer_m", 999.0)) <= 2.0:
				_metrics["time_room_%d_smoke_layer_2m_s" % trigger_room_id] = sim_time_s

	if not target_room_state.is_empty():
		if not _metrics.has("time_room_%d_smoke_start_s" % target_room_id):
			if float(target_room_state.get("smoke_kg", 0.0)) > 0.001:
				_metrics["time_room_%d_smoke_start_s" % target_room_id] = sim_time_s

	if not l150_room_state.is_empty():
		if not _metrics.has("time_room_%d_l150_below_1_8m_s" % l150_room_id):
			if float(l150_room_state.get("layer_150c_m", 999.0)) < 1.8:
				_metrics["time_room_%d_l150_below_1_8m_s" % l150_room_id] = sim_time_s
		if not _metrics.has("time_room_%d_l150_below_0_5m_s" % l150_room_id):
			if float(l150_room_state.get("layer_150c_m", 999.0)) < 0.5:
				_metrics["time_room_%d_l150_below_0_5m_s" % l150_room_id] = sim_time_s
		if not _metrics.has("time_room_%d_temp_1_8m_above_150c_s" % l150_room_id):
			if float(l150_room_state.get("temp_at_1_8m_c", 0.0)) >= float(engine.survival_temp_threshold_c):
				_metrics["time_room_%d_temp_1_8m_above_150c_s" % l150_room_id] = sim_time_s

	if all_rooms_extinguished and not _metrics.has("time_to_extinction_s"):
		_metrics["time_to_extinction_s"] = sim_time_s
	if all_rooms_quiescent and not _metrics.has("time_to_quiescent_s"):
		_metrics["time_to_quiescent_s"] = sim_time_s


func _update_room_peak_metrics(room_id: int, room_state: Dictionary) -> void:
	var prefix: String = "room_%d_" % room_id
	_metrics[prefix + "peak_hrr_kw"] = maxf(
		float(_metrics.get(prefix + "peak_hrr_kw", 0.0)),
		float(room_state.get("hrr_kw", 0.0))
	)
	_metrics[prefix + "peak_temp_upper_c"] = maxf(
		float(_metrics.get(prefix + "peak_temp_upper_c", 0.0)),
		float(room_state.get("temp_upper_c", 0.0))
	)
	_metrics[prefix + "peak_co_ppm"] = maxf(
		float(_metrics.get(prefix + "peak_co_ppm", 0.0)),
		float(room_state.get("co_ppm", 0.0))
	)
	_metrics[prefix + "min_l150_m"] = minf(
		float(_metrics.get(prefix + "min_l150_m", float(room_state.get("height_m", 0.0)))),
		float(room_state.get("layer_150c_m", float(room_state.get("height_m", 0.0))))
	)


func _capture_final_metrics(state: Dictionary) -> void:
	for room_id in _get_watch_room_ids():
		var room_state: Dictionary = state.get(str(room_id), {})
		if room_state.is_empty():
			continue

		var prefix: String = "room_%d_final_" % room_id
		_metrics[prefix + "smoke_kg"] = float(room_state.get("smoke_kg", 0.0))
		_metrics[prefix + "co_ppm"] = float(room_state.get("co_ppm", 0.0))
		_metrics[prefix + "hot_layer_m"] = float(room_state.get("hot_layer_m", 0.0))
		_metrics[prefix + "smoke_layer_m"] = float(room_state.get("smoke_layer_m", 0.0))
		_metrics[prefix + "layer_150c_m"] = float(room_state.get("layer_150c_m", 0.0))
		_metrics[prefix + "temp_at_1_8m_c"] = float(room_state.get("temp_at_1_8m_c", 0.0))


func _finalize_validation_run(state: Dictionary) -> void:
	_active = false
	_capture_final_metrics(state)

	var report: Dictionary = {
		"case": _case_name,
		"duration_s": float(_case_config.get("duration_s", 0.0)),
		"sim_time_s": float(state.get("sim_time_s", 0.0)),
		"metrics": _metrics,
		"baseline": {}
	}

	var baseline_text: String = _read_text_file(_baseline_path)
	if not baseline_text.is_empty():
		var baseline_data: Variant = JSON.parse_string(baseline_text)
		if typeof(baseline_data) == TYPE_DICTIONARY:
			report["baseline"] = _compare_against_baseline(_metrics, baseline_data)

	_write_json_file(_output_path, report)
	print("[Validation] Reporte guardado en %s" % _output_path)

	var baseline_result: Dictionary = report.get("baseline", {})
	var exit_code: int = 0
	if not baseline_result.is_empty():
		var all_pass: bool = bool(baseline_result.get("all_pass", false))
		print("[Validation] Baseline %s" % ("PASS" if all_pass else "FAIL"))
		if not all_pass:
			exit_code = 2

	if auto_quit and not bool(_cli_args.get("validation_no_quit", false)):
		get_tree().quit(exit_code)


func _compare_against_baseline(metrics: Dictionary, baseline_data: Dictionary) -> Dictionary:
	var checks: Dictionary = {}
	var all_pass: bool = true
	var baseline_metrics: Dictionary = baseline_data.get("metrics", {})

	for metric_name in baseline_metrics.keys():
		var rule: Dictionary = baseline_metrics.get(metric_name, {})
		var actual_value = metrics.get(metric_name, null)
		var passed: bool = actual_value != null

		if actual_value != null:
			var actual_float: float = float(actual_value)
			if rule.has("expected"):
				var expected: float = float(rule.get("expected", 0.0))
				var tolerance: float = float(rule.get("tolerance", 0.0))
				passed = absf(actual_float - expected) <= tolerance
			if rule.has("min"):
				passed = passed and actual_float >= float(rule.get("min", actual_float))
			if rule.has("max"):
				passed = passed and actual_float <= float(rule.get("max", actual_float))

		checks[metric_name] = {
			"actual": actual_value,
			"rule": rule,
			"pass": passed
		}
		all_pass = all_pass and passed

	return {
		"all_pass": all_pass,
		"checks": checks
	}


func _collect_room_ids(state: Dictionary) -> Array[int]:
	var room_ids: Array[int] = []
	for key in state.keys():
		var key_str: String = String(key)
		if key_str.is_valid_int():
			room_ids.append(int(key_str))
	room_ids.sort()
	return room_ids


func _get_watch_room_ids() -> Array[int]:
	var result: Array[int] = []
	var raw_ids: Variant = _case_config.get("watch_room_ids", [])
	if typeof(raw_ids) != TYPE_ARRAY:
		return result

	for raw_id in raw_ids:
		result.append(int(raw_id))
	return result


func _read_text_file(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text: String = file.get_as_text()
	file.close()
	return text


func _write_json_file(path: String, data: Dictionary) -> void:
	var resolved_path: String = path
	if path.begins_with("res://") or path.begins_with("user://"):
		resolved_path = ProjectSettings.globalize_path(path)

	var dir_path: String = resolved_path.get_base_dir()
	if not dir_path.is_empty():
		DirAccess.make_dir_recursive_absolute(dir_path)

	var file := FileAccess.open(resolved_path, FileAccess.WRITE)
	if file == null:
		push_error("CaseRunner: no se pudo escribir %s" % resolved_path)
		return

	file.store_string(JSON.stringify(data, "\t"))
	file.close()

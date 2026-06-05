extends Node
class_name CaseRunner

# ============================================================
# CASE RUNNER
# ------------------------------------------------------------
# Ejecuta un caso de validación desde un fichero JSON.
# Flujo:
#   1. Carga caso (.json) y baseline opcional
#   2. Configura el edificio con BuildingTemplate
#   3. Avanza la simulación hasta duration_s
#   4. Aplica engine_overrides y opening_events del JSON
#   5. Compara métricas contra baseline y guarda reporte
# Salida: informe JSON en reports_dir/
# ============================================================

const BuildingTemplateScript = preload("res://sim/templates/BuildingTemplate.gd")
const TargetModelScript = preload("res://sim/fire/TargetModel.gd")

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
var _opening_events: Array = []
var _suppression_events: Array = []
var _carbon_events: Array = []
var _engine_mode: String = "legacy"
var _fire_o2_mode: String = "legacy"
var _incident_started: bool = false
var _runtime_error_reported: bool = false


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
	if state.is_empty():
		_abort_validation_run("CaseRunner: engine devolvio estado vacio; abortando validacion")
		return

	var sim_time_s: float = float(state.get("sim_time_s", 0.0))
	if _apply_due_opening_events(sim_time_s):
		state = engine.get_state()
	if _apply_due_suppression_events(sim_time_s):
		state = engine.get_state()
	if _apply_due_carbon_events(sim_time_s):
		state = engine.get_state()
	_update_metrics(state)

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
		elif arg.begins_with("--validation-engine-mode="):
			parsed["validation_engine_mode"] = arg.get_slice("=", 1)
		elif arg == "--validation-engine-mode" and index + 1 < args.size():
			index += 1
			parsed["validation_engine_mode"] = String(args[index])
		elif arg.begins_with("--validation-fire-o2-mode="):
			parsed["validation_fire_o2_mode"] = arg.get_slice("=", 1)
		elif arg == "--validation-fire-o2-mode" and index + 1 < args.size():
			index += 1
			parsed["validation_fire_o2_mode"] = String(args[index])
		elif arg.begins_with("--validation-two-zone-opening-flow="):
			parsed["validation_two_zone_opening_flow"] = _parse_bool_arg(arg.get_slice("=", 1))
		elif arg == "--validation-two-zone-opening-flow":
			parsed["validation_two_zone_opening_flow"] = true
		elif arg.begins_with("--validation-canonical-pressure="):
			parsed["validation_canonical_pressure"] = _parse_bool_arg(arg.get_slice("=", 1))
		elif arg == "--validation-canonical-pressure":
			parsed["validation_canonical_pressure"] = true
		elif arg == "--validation-no-quit":
			parsed["validation_no_quit"] = true
		index += 1

	if not parsed.has("validation_case"):
		return {}

	return parsed


func _parse_bool_arg(value: String) -> bool:
	var normalized: String = value.strip_edges().to_lower()
	return normalized == "1" or normalized == "true" or normalized == "yes" or normalized == "on"


func _begin_validation_run() -> void:
	if building == null or engine == null:
		_abort_validation_run("CaseRunner: faltan referencias a BuildingModel / SimulationEngine")
		return

	if not engine.has_method("is_ready_for_validation") or not engine.is_ready_for_validation():
		_abort_validation_run("CaseRunner: SimulationEngine no esta operativo; revisa errores de compilacion")
		return

	_case_name = String(_cli_args.get("validation_case", ""))
	_case_config = _load_case_config(_case_name)
	if _case_config.is_empty():
		_abort_validation_run("CaseRunner: no se pudo cargar el caso '%s'" % _case_name)
		return

	if _cli_args.has("validation_duration"):
		_case_config["duration_s"] = float(_cli_args["validation_duration"])

	var template_data: Dictionary = _build_case_template(_case_config)
	if template_data.is_empty():
		_abort_validation_run("CaseRunner: template vacio para '%s'" % _case_name)
		return

	building.load_template_data(template_data)
	_apply_engine_overrides(Dictionary(_case_config.get("engine_overrides", {})))
	if not _configure_validation_engine_mode():
		return
	if not _configure_validation_fire_o2_mode():
		return
	_configure_validation_two_zone_opening_flow()
	_configure_validation_canonical_pressure()
	engine.auto_finish_on_extinction = false
	engine.enable_logging = bool(_case_config.get("enable_logging", false))
	engine.ignition_room_id = int(_case_config.get("ignition_room_id", engine.ignition_room_id))
	engine.reset_simulation(engine.ignition_room_id, bool(_case_config.get("ignite_on_start", true)))
	var initial_state: Dictionary = engine.get_state()
	if initial_state.is_empty():
		_abort_validation_run("CaseRunner: reset sin estado valido; abortando validacion")
		return

	_opening_events = _prepare_opening_events(_case_config.get("opening_events", []))
	_suppression_events = _prepare_suppression_events(_case_config.get("suppression_events", []))
	_carbon_events = _prepare_carbon_events(_case_config.get("carbon_events", []))

	# SF-AUD-029: cargar targets radiantes pasivos del caso
	var targets_data: Array = _case_config.get("targets", [])
	for tdata in targets_data:
		if typeof(tdata) != TYPE_DICTIONARY:
			continue
		var t = TargetModelScript.new()
		t.id = String(tdata.get("id", "target_%d" % engine.get_targets().size()))
		t.room_id = int(tdata.get("room_id", 0))
		t.height_m = float(tdata.get("height_m", 1.0))
		t.area_m2 = float(tdata.get("area_m2", 0.25))
		t.emissivity = float(tdata.get("emissivity", 0.9))
		t.angle_factor = float(tdata.get("angle_factor", 0.5))
		engine.add_target(t)

	_metrics.clear()
	_incident_started = false
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
	_run_validation_loop()


func _run_validation_loop() -> void:
	var duration_s: float = float(_case_config.get("duration_s", 600.0))
	var validation_step_s: float = maxf(
		0.001,
		float(_case_config.get("validation_step_s", 1.0 / 12.0))
	)
	var max_iterations: int = int(ceil(duration_s / validation_step_s)) + 1000
	var stagnant_steps: int = 0

	for _iteration in range(max_iterations):
		if not _active:
			return

		var state: Dictionary = engine.get_state()
		if state.is_empty():
			_abort_validation_run("CaseRunner: engine devolvio estado vacio; abortando validacion")
			return

		var sim_time_s: float = float(state.get("sim_time_s", 0.0))
		if _apply_due_opening_events(sim_time_s):
			state = engine.get_state()
			if state.is_empty():
				_abort_validation_run("CaseRunner: estado vacio tras evento de apertura")
				return
		if _apply_due_suppression_events(sim_time_s):
			state = engine.get_state()
			if state.is_empty():
				_abort_validation_run("CaseRunner: estado vacio tras evento de supresion")
				return
		if _apply_due_carbon_events(sim_time_s):
			state = engine.get_state()
			if state.is_empty():
				_abort_validation_run("CaseRunner: estado vacio tras evento de carbono")
				return

		if sim_time_s >= duration_s:
			_finalize_validation_run(state)
			return

		var previous_time_s: float = sim_time_s
		engine.step(validation_step_s / maxf(0.001, engine.time_scale))
		state = engine.get_state()
		if state.is_empty():
			_abort_validation_run("CaseRunner: estado vacio tras step de validacion")
			return

		sim_time_s = float(state.get("sim_time_s", 0.0))
		if sim_time_s <= previous_time_s + 0.000001:
			stagnant_steps += 1
			if stagnant_steps >= 10:
				_abort_validation_run("CaseRunner: la simulacion no avanza; abortando validacion")
				return
		else:
			stagnant_steps = 0

		_update_metrics(state)
		if sim_time_s >= duration_s:
			_finalize_validation_run(state)
			return

	_abort_validation_run("CaseRunner: se alcanzo el limite interno de iteraciones")


func _abort_validation_run(message: String, exit_code: int = 1) -> void:
	if _runtime_error_reported:
		return

	_runtime_error_reported = true
	_active = false
	push_error(message)
	if auto_quit and not bool(_cli_args.get("validation_no_quit", false)):
		get_tree().quit(exit_code)


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
	var template_data: Dictionary = builder.create_by_name(template_name)
	var supported_ids: Array[String] = []
	for preset in builder.get_preset_definitions():
		supported_ids.append(String(preset.get("id", "")))
	if not supported_ids.has(template_name):
		push_error("CaseRunner: template no soportado '%s'" % template_name)
		return {}
	if case_config.has("hvac_mode"):
		template_data["hvac_mode"] = String(case_config.get("hvac_mode", "none"))
	if case_config.has("hvac_data"):
		template_data["hvac_data"] = Dictionary(case_config.get("hvac_data", {})).duplicate(true)

	_apply_room_overrides(template_data, case_config.get("room_overrides", []))
	_apply_opening_overrides(template_data, case_config.get("opening_overrides", []))
	# Parámetros de nivel building (wind_speed_m_s, wind_direction_deg, outside_temp_c, etc.)
	if case_config.has("building_params"):
		var bparams: Dictionary = Dictionary(case_config.get("building_params", {}))
		for bkey: String in bparams.keys():
			template_data[bkey] = bparams[bkey]
	# SF-VIC-001: víctimas definidas en el caso
	if case_config.has("victims"):
		template_data["victims"] = Array(case_config.get("victims", [])).duplicate(true)
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


func _configure_validation_engine_mode() -> bool:
	var requested_mode: String = String(_cli_args.get("validation_engine_mode", "")).strip_edges().to_lower()
	if requested_mode.is_empty():
		_engine_mode = "two-zone" if engine.two_zone_solver_enabled else "legacy"
		return true
	if requested_mode != "legacy" and requested_mode != "two-zone":
		_abort_validation_run("CaseRunner: modo de motor no soportado '%s'" % requested_mode)
		return false
	engine.two_zone_solver_enabled = requested_mode == "two-zone"
	_engine_mode = requested_mode
	return true


func _configure_validation_fire_o2_mode() -> bool:
	var requested_mode: String = String(
		_cli_args.get("validation_fire_o2_mode", engine.fire_o2_mode)
	).strip_edges().to_lower()
	if requested_mode != "legacy" \
			and requested_mode != "upper" \
			and requested_mode != "lower" \
			and requested_mode != "interface":
		_abort_validation_run("CaseRunner: modo de O2 de fuego no soportado '%s'" % requested_mode)
		return false
	engine.fire_o2_mode = requested_mode
	_fire_o2_mode = requested_mode
	return true


func _configure_validation_two_zone_opening_flow() -> void:
	if not _cli_args.has("validation_two_zone_opening_flow"):
		return
	engine.two_zone_opening_flow_enabled = bool(_cli_args.get("validation_two_zone_opening_flow", false))


func _configure_validation_canonical_pressure() -> void:
	if not _cli_args.has("validation_canonical_pressure"):
		return
	engine.phase3_thermodynamic_pressure_enabled = true
	engine.phase3_pressure_canonical_enabled = bool(_cli_args.get("validation_canonical_pressure", false))


func _prepare_opening_events(raw_events: Variant) -> Array:
	var result: Array = []
	if typeof(raw_events) != TYPE_ARRAY:
		return result

	for raw_event in raw_events:
		if typeof(raw_event) != TYPE_DICTIONARY:
			continue

		var event_data: Dictionary = raw_event.duplicate(true)
		event_data["time_s"] = float(event_data.get("time_s", 0.0))
		event_data["applied"] = false
		result.append(event_data)

	return result


func _prepare_suppression_events(raw_events: Variant) -> Array:
	var result: Array = []
	if typeof(raw_events) != TYPE_ARRAY:
		return result

	for raw_event in raw_events:
		if typeof(raw_event) != TYPE_DICTIONARY:
			continue

		var raw_data: Dictionary = raw_event
		var event_data: Dictionary = raw_data.duplicate(true)
		var room_id: int = 0
		if event_data.has("room_id"):
			room_id = int(event_data["room_id"])
		elif event_data.has("room"):
			room_id = int(event_data["room"])
		event_data["time_s"] = float(event_data.get("time_s", 0.0))
		event_data["room_id"] = room_id
		event_data["duration_s"] = float(event_data.get("duration_s", 10.0))
		event_data["flow_lpm"] = float(event_data.get("flow_lpm", 570.0))
		event_data["effectiveness"] = float(event_data.get("effectiveness", 0.75))
		event_data["applied"] = false
		result.append(event_data)

	return result


func _prepare_carbon_events(raw_events: Variant) -> Array:
	var result: Array = []
	if typeof(raw_events) != TYPE_ARRAY:
		return result

	for raw_event in raw_events:
		if typeof(raw_event) != TYPE_DICTIONARY:
			continue
		var event_data: Dictionary = Dictionary(raw_event).duplicate(true)
		event_data["time_s"] = float(event_data.get("time_s", 0.0))
		event_data["room_id"] = int(event_data.get("room_id", 0))
		event_data["species"] = String(event_data.get("species", "co2_kg"))
		event_data["delta_kg"] = float(event_data.get("delta_kg", 0.0))
		event_data["applied"] = false
		result.append(event_data)

	return result


func _apply_due_opening_events(sim_time_s: float) -> bool:
	if building == null or _opening_events.is_empty():
		return false

	var changed: bool = false
	for index in range(_opening_events.size()):
		var event_data: Dictionary = _opening_events[index]
		if bool(event_data.get("applied", false)):
			continue
		if sim_time_s < float(event_data.get("time_s", 0.0)):
			continue

		var opening_index: int = _resolve_opening_event_index(event_data)
		if opening_index < 0:
			push_warning("CaseRunner: no se encontro apertura para evento %s" % JSON.stringify(event_data))
			event_data["applied"] = true
			_opening_events[index] = event_data
			continue

		var open_fraction: float = _resolve_opening_event_fraction(event_data)
		if building.set_opening_fraction(opening_index, open_fraction):
			print("[Validation] Evento apertura aplicado t=%.1f s -> #%d %.2f" % [
				sim_time_s,
				opening_index,
				open_fraction
			])
			_metrics["opening_event_%d_time_s" % index] = sim_time_s
			changed = true

		event_data["applied"] = true
		_opening_events[index] = event_data

	return changed


func _apply_due_suppression_events(sim_time_s: float) -> bool:
	if engine == null or _suppression_events.is_empty():
		return false

	var changed: bool = false
	for index in range(_suppression_events.size()):
		var event_data: Dictionary = _suppression_events[index]
		if bool(event_data.get("applied", false)):
			continue
		if sim_time_s < float(event_data.get("time_s", 0.0)):
			continue

		var room_id: int = int(event_data.get("room_id", 0))
		var duration_s: float = maxf(0.0, float(event_data.get("duration_s", 10.0)))
		var flow_lpm: float = maxf(0.0, float(event_data.get("flow_lpm", 570.0)))
		var effectiveness: float = clampf(float(event_data.get("effectiveness", 0.75)), 0.0, 1.0)
		engine.apply_suppression(room_id, duration_s, flow_lpm, effectiveness)
		print("[Validation] Supresion aplicada t=%.1f s -> room %d %.0f L/min %.1f s" % [
			sim_time_s,
			room_id,
			flow_lpm,
			duration_s
		])
		_metrics["suppression_event_%d_time_s" % index] = sim_time_s
		event_data["applied"] = true
		_suppression_events[index] = event_data
		changed = true

	return changed


func _apply_due_carbon_events(sim_time_s: float) -> bool:
	if building == null or _carbon_events.is_empty():
		return false

	var allowed_species: Array[String] = ["co_kg", "co2_kg", "hcn_kg", "smoke_kg"]
	var changed: bool = false
	for index in range(_carbon_events.size()):
		var event_data: Dictionary = _carbon_events[index]
		if bool(event_data.get("applied", false)):
			continue
		if sim_time_s < float(event_data.get("time_s", 0.0)):
			continue

		var room_id: int = int(event_data.get("room_id", 0))
		var species: String = String(event_data.get("species", "co2_kg"))
		var room: RoomModel = building.get_room(room_id)
		if room == null or not allowed_species.has(species):
			push_warning("CaseRunner: evento de carbono invalido %s" % JSON.stringify(event_data))
		else:
			var delta_kg: float = float(event_data.get("delta_kg", 0.0))
			room.set(species, maxf(0.0, float(room.get(species)) + delta_kg))
			_metrics["carbon_event_%d_time_s" % index] = sim_time_s
			changed = true

		event_data["applied"] = true
		_carbon_events[index] = event_data

	return changed


func _resolve_opening_event_index(event_data: Dictionary) -> int:
	if event_data.has("index"):
		return int(event_data.get("index", -1))

	var match_a: int = int(event_data.get("a", 999999))
	var match_b: int = int(event_data.get("b", 999999))
	var match_type: String = String(event_data.get("type", ""))

	for opening_index in range(building.get_opening_count()):
		var op: OpeningModel = building.get_opening_at(opening_index)
		if op == null:
			continue

		var same_direction: bool = op.a == match_a and op.b == match_b
		var reverse_direction: bool = op.a == match_b and op.b == match_a
		if not same_direction and not reverse_direction:
			continue

		if match_type != "":
			var type_name: String = "door"
			if op.type == OpeningModel.Type.WINDOW:
				type_name = "window"
			elif op.type == OpeningModel.Type.HOLE:
				type_name = "hole"
			if type_name != match_type:
				continue

		return opening_index

	return -1


func _resolve_opening_event_fraction(event_data: Dictionary) -> float:
	if event_data.has("open_fraction"):
		return clampf(float(event_data.get("open_fraction", 0.0)), 0.0, 1.0)

	match String(event_data.get("action", "open")).to_lower():
		"close":
			return 0.0
		"open":
			return 1.0
		_:
			return clampf(float(event_data.get("value", 1.0)), 0.0, 1.0)


func _update_metrics(state: Dictionary) -> void:
	var sim_time_s: float = float(state.get("sim_time_s", 0.0))
	var room_ids: Array[int] = _collect_room_ids(state)
	var watch_room_ids: Array[int] = _get_watch_room_ids()
	if room_ids.is_empty():
		return

	var global_peak_hrr_kw: float = float(_metrics.get("peak_hrr_kw_global", 0.0))
	var global_peak_temp_upper_c: float = float(_metrics.get("peak_temp_upper_c_global", 0.0))
	var global_peak_temp_upper_raw_c: float = float(_metrics.get("peak_temp_upper_raw_c_global", 0.0))
	var global_max_upper_radiative_loss_kw: float = float(_metrics.get("max_upper_radiative_loss_kw_global", 0.0))
	var global_peak_co_ppm: float = float(_metrics.get("peak_co_ppm_global", 0.0))
	var global_peak_co_upper_ppm: float = float(_metrics.get("peak_co_upper_ppm_global", 0.0))
	var all_rooms_extinguished: bool = true
	var all_rooms_quiescent: bool = true
	var extinction_hrr_kw: float = maxf(0.01, engine.fire_extinction_hrr_kw)
	var any_room_clamped: bool = false

	for room_id in room_ids:
		var room_state: Dictionary = state.get(str(room_id), {})
		if room_state.is_empty():
			continue

		var hrr_kw: float = float(room_state.get("hrr_kw", 0.0))
		var temp_upper_c: float = float(room_state.get("temp_upper_c", 0.0))
		var temp_upper_raw_c: float = float(room_state.get("temp_upper_raw_c", temp_upper_c))
		var upper_radiative_loss_kw: float = float(room_state.get("upper_radiative_loss_kw", 0.0))
		var co_ppm: float = float(room_state.get("co_ppm", 0.0))
		var co_upper_ppm: float = float(room_state.get("co_upper_ppm", 0.0))
		var has_fire: bool = bool(room_state.get("has_fire", false))
		var temp_upper_clamped: bool = bool(room_state.get("temp_upper_clamped", false))
		var fuel_pyrolyzing_count: int = int(room_state.get("fuel_objects_pyrolyzing_count", 0))
		var fuel_flaming_count: int = int(room_state.get("fuel_objects_flaming_count", 0))

		global_peak_hrr_kw = maxf(global_peak_hrr_kw, hrr_kw)
		global_peak_temp_upper_c = maxf(global_peak_temp_upper_c, temp_upper_c)
		global_peak_temp_upper_raw_c = maxf(global_peak_temp_upper_raw_c, temp_upper_raw_c)
		global_max_upper_radiative_loss_kw = maxf(global_max_upper_radiative_loss_kw, upper_radiative_loss_kw)
		global_peak_co_ppm = maxf(global_peak_co_ppm, co_ppm)
		global_peak_co_upper_ppm = maxf(global_peak_co_upper_ppm, co_upper_ppm)
		if temp_upper_clamped:
			any_room_clamped = true
			if not _metrics.has("time_room_%d_temp_upper_clamped_s" % room_id):
				_metrics["time_room_%d_temp_upper_clamped_s" % room_id] = sim_time_s
		if fuel_pyrolyzing_count > 0 and not _metrics.has("time_room_%d_fuel_pyrolysis_s" % room_id):
			_metrics["time_room_%d_fuel_pyrolysis_s" % room_id] = sim_time_s
		if fuel_flaming_count > 0 and not _metrics.has("time_room_%d_fuel_flaming_s" % room_id):
			_metrics["time_room_%d_fuel_flaming_s" % room_id] = sim_time_s
		if bool(room_state.get("passive_fuel_autoignite_ready", false)) \
				and not _metrics.has("time_room_%d_fuel_autoignite_ready_s" % room_id):
			_metrics["time_room_%d_fuel_autoignite_ready_s" % room_id] = sim_time_s
		if hrr_kw > extinction_hrr_kw:
			_incident_started = true

		if has_fire:
			all_rooms_extinguished = false
		if not bool(room_state.get("is_quiescent", false)):
			all_rooms_quiescent = false
		if watch_room_ids.has(room_id):
			_update_room_peak_metrics(room_id, room_state)

	_metrics["peak_hrr_kw_global"] = global_peak_hrr_kw
	_metrics["peak_temp_upper_c_global"] = global_peak_temp_upper_c
	_metrics["peak_temp_upper_raw_c_global"] = global_peak_temp_upper_raw_c
	_metrics["max_upper_radiative_loss_kw_global"] = global_max_upper_radiative_loss_kw
	_metrics["peak_co_ppm_global"] = global_peak_co_ppm
	_metrics["peak_co_upper_ppm_global"] = global_peak_co_upper_ppm
	if any_room_clamped:
		if not _metrics.has("time_temp_upper_clamped_global_s"):
			_metrics["time_temp_upper_clamped_global_s"] = sim_time_s
		_metrics["temp_upper_clamp_sample_count_global"] = int(
			_metrics.get("temp_upper_clamp_sample_count_global", 0)
		) + 1
	_metrics["smoke_generated_total_kg"] = float(state.get("smoke_generated_total_kg", 0.0))
	_metrics["smoke_vented_total_kg"] = float(state.get("smoke_vented_total_kg", 0.0))
	_metrics["smoke_deposited_total_kg"] = float(state.get("smoke_deposited_total_kg", 0.0))
	_metrics["suppression_water_applied_l"] = float(state.get("suppression_water_applied_l", 0.0))
	_metrics["suppression_cooling_total_kj"] = float(state.get("suppression_cooling_total_kj", 0.0))
	# SF-R6 Phase 3: violación de conservación de transporte acumulada.
	# -1.0 = conservation_check_enabled=false (dato no disponible).
	_metrics["conservation_max_violation_frac"] = float(state.get("conservation_max_violation_frac", -1.0))
	# SF-CBAL: error global de balance de carbono (kg C).
	var global_carbon_error_kg: float = float(state.get("global_carbon_error_kg", 0.0))
	var global_carbon_error_abs_kg: float = absf(global_carbon_error_kg)
	_metrics["global_carbon_error_kg"] = global_carbon_error_kg
	_metrics["global_carbon_error_kg_abs"] = global_carbon_error_abs_kg
	_metrics["peak_global_carbon_error_kg_abs"] = maxf(
		float(_metrics.get("peak_global_carbon_error_kg_abs", 0.0)),
		global_carbon_error_abs_kg
	)
	_metrics["global_carbon_preclamp_excess_kg"] = float(
		state.get("global_carbon_preclamp_excess_kg", 0.0)
	)
	_metrics["global_carbon_postclamp_excess_kg"] = float(
		state.get("global_carbon_postclamp_excess_kg", 0.0)
	)
	var transport_residual_kg: float = float(state.get("global_carbon_transport_residual_kg", 0.0))
	_metrics["global_carbon_transport_residual_kg"] = transport_residual_kg
	_metrics["peak_global_carbon_transport_residual_kg_abs"] = maxf(
		float(_metrics.get("peak_global_carbon_transport_residual_kg_abs", 0.0)),
		absf(transport_residual_kg)
	)
	_metrics["hvac_on"] = 1.0 if bool(state.get("hvac_on", false)) else 0.0
	_metrics["two_zone_solver_enabled"] = 1.0 if bool(state.get("two_zone_solver_enabled", false)) else 0.0
	_metrics["two_zone_opening_flow_enabled"] = 1.0 if bool(
		state.get("two_zone_opening_flow_enabled", false)
	) else 0.0
	_metrics["phase3_pressure_canonical_enabled"] = 1.0 if bool(
		state.get("phase3_pressure_canonical_enabled", false)
	) else 0.0

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

	_update_threshold_metrics(state, sim_time_s)
	_update_delta_max_metrics(state, sim_time_s)  # BV-013 / BV-028

	if _incident_started and all_rooms_extinguished and not _metrics.has("time_to_extinction_s"):
		_metrics["time_to_extinction_s"] = sim_time_s
	if _incident_started and all_rooms_quiescent and not _metrics.has("time_to_quiescent_s"):
		_metrics["time_to_quiescent_s"] = sim_time_s

	# SF-VIC-001: registrar primer instante de incapacitación de cada víctima
	for vic_state in state.get("victims", []):
		if typeof(vic_state) != TYPE_DICTIONARY:
			continue
		var vic_id: String = String(vic_state.get("id", ""))
		if vic_id.is_empty():
			continue
		var metric_key: String = "time_victim_%s_incapacitated_s" % vic_id
		if not _metrics.has(metric_key) and bool(vic_state.get("incapacitated", false)):
			_metrics[metric_key] = float(vic_state.get("incapacitated_at_s", sim_time_s))


func _update_room_peak_metrics(room_id: int, room_state: Dictionary) -> void:
	var prefix: String = "room_%d_" % room_id
	_metrics[prefix + "peak_hrr_kw"] = maxf(
		float(_metrics.get(prefix + "peak_hrr_kw", 0.0)),
		float(room_state.get("hrr_kw", 0.0))
	)
	_metrics[prefix + "peak_pyrolysis_kw"] = maxf(
		float(_metrics.get(prefix + "peak_pyrolysis_kw", 0.0)),
		float(room_state.get("pyrolysis_kw", 0.0))
	)
	_metrics[prefix + "peak_burned_hrr_kw"] = maxf(
		float(_metrics.get(prefix + "peak_burned_hrr_kw", 0.0)),
		float(room_state.get("burned_hrr_kw", room_state.get("hrr_kw", 0.0)))
	)
	_metrics[prefix + "max_unburned_generation_kw"] = maxf(
		float(_metrics.get(prefix + "max_unburned_generation_kw", 0.0)),
		float(room_state.get("unburned_generation_kw", 0.0))
	)
	_metrics[prefix + "peak_temp_upper_c"] = maxf(
		float(_metrics.get(prefix + "peak_temp_upper_c", 0.0)),
		float(room_state.get("temp_upper_c", 0.0))
	)
	_metrics[prefix + "peak_temp_upper_raw_c"] = maxf(
		float(_metrics.get(prefix + "peak_temp_upper_raw_c", 0.0)),
		float(room_state.get("temp_upper_raw_c", room_state.get("temp_upper_c", 0.0)))
	)
	_metrics[prefix + "max_upper_radiative_loss_kw"] = maxf(
		float(_metrics.get(prefix + "max_upper_radiative_loss_kw", 0.0)),
		float(room_state.get("upper_radiative_loss_kw", 0.0))
	)
	_metrics[prefix + "peak_upper_zone_mass_kg"] = maxf(
		float(_metrics.get(prefix + "peak_upper_zone_mass_kg", 0.0)),
		float(room_state.get("upper_zone_mass_kg", room_state.get("upper_gas_kg", 0.0)))
	)
	if not _metrics.has(prefix + "min_lower_zone_mass_kg"):
		_metrics[prefix + "min_lower_zone_mass_kg"] = float(room_state.get("lower_zone_mass_kg", 0.0))
	else:
		_metrics[prefix + "min_lower_zone_mass_kg"] = minf(
			float(_metrics[prefix + "min_lower_zone_mass_kg"]),
			float(room_state.get("lower_zone_mass_kg", 0.0))
		)
	_metrics[prefix + "peak_zone_total_energy_kj"] = maxf(
		float(_metrics.get(prefix + "peak_zone_total_energy_kj", 0.0)),
		float(room_state.get("zone_total_energy_kj", 0.0))
	)
	_metrics[prefix + "max_passive_fuel_surface_temp_c"] = maxf(
		float(_metrics.get(prefix + "max_passive_fuel_surface_temp_c", 0.0)),
		float(room_state.get("passive_fuel_surface_temp_c", 0.0))
	)
	_metrics[prefix + "max_passive_fuel_flux_kw_m2"] = maxf(
		float(_metrics.get(prefix + "max_passive_fuel_flux_kw_m2", 0.0)),
		float(room_state.get("passive_fuel_flux_kw_m2", 0.0))
	)
	_metrics[prefix + "max_fuel_objects_heating_count"] = maxi(
		int(_metrics.get(prefix + "max_fuel_objects_heating_count", 0)),
		int(room_state.get("fuel_objects_heating_count", 0))
	)
	_metrics[prefix + "max_fuel_objects_pyrolyzing_count"] = maxi(
		int(_metrics.get(prefix + "max_fuel_objects_pyrolyzing_count", 0)),
		int(room_state.get("fuel_objects_pyrolyzing_count", 0))
	)
	_metrics[prefix + "max_fuel_objects_flaming_count"] = maxi(
		int(_metrics.get(prefix + "max_fuel_objects_flaming_count", 0)),
		int(room_state.get("fuel_objects_flaming_count", 0))
	)
	_metrics[prefix + "peak_co_ppm"] = maxf(
		float(_metrics.get(prefix + "peak_co_ppm", 0.0)),
		float(room_state.get("co_ppm", 0.0))
	)
	_metrics[prefix + "peak_co_upper_ppm"] = maxf(
		float(_metrics.get(prefix + "peak_co_upper_ppm", 0.0)),
		float(room_state.get("co_upper_ppm", 0.0))
	)
	# Phase 4B: HCN observability — track peak HCN ppm for sanity checks
	_metrics[prefix + "peak_hcn_ppm"] = maxf(
		float(_metrics.get(prefix + "peak_hcn_ppm", 0.0)),
		float(room_state.get("hcn_ppm", 0.0))
	)
	_metrics[prefix + "peak_hcn_upper_ppm"] = maxf(
		float(_metrics.get(prefix + "peak_hcn_upper_ppm", 0.0)),
		float(room_state.get("hcn_upper_ppm", 0.0))
	)
	_metrics[prefix + "peak_co2_ppm"] = maxf(
		float(_metrics.get(prefix + "peak_co2_ppm", 0.0)),
		float(room_state.get("co2_ppm", 0.0))
	)
	_metrics[prefix + "peak_co2_upper_ppm"] = maxf(
		float(_metrics.get(prefix + "peak_co2_upper_ppm", 0.0)),
		float(room_state.get("co2_upper_ppm", 0.0))
	)
	_metrics[prefix + "max_fed"] = maxf(
		float(_metrics.get(prefix + "max_fed", 0.0)),
		float(room_state.get("fed", 0.0))
	)
	# SF-AUD-032: peak c_balance_frac (máximo alcanzado durante la simulación)
	_metrics[prefix + "peak_c_balance_frac"] = maxf(
		float(_metrics.get(prefix + "peak_c_balance_frac", 0.0)),
		float(room_state.get("c_balance_frac", 0.0))
	)
	_metrics[prefix + "min_visibility_m"] = minf(
		float(_metrics.get(prefix + "min_visibility_m", float(room_state.get("visibility_m", 30.0)))),
		float(room_state.get("visibility_m", 30.0))
	)
	_metrics[prefix + "min_l150_m"] = minf(
		float(_metrics.get(prefix + "min_l150_m", float(room_state.get("height_m", 0.0)))),
		float(room_state.get("layer_150c_m", float(room_state.get("height_m", 0.0))))
	)
	_metrics[prefix + "max_overpressure_pa"] = maxf(
		float(_metrics.get(prefix + "max_overpressure_pa", 0.0)),
		float(room_state.get("overpressure_pa", 0.0))
	)
	_metrics[prefix + "max_pressure_pa_therm"] = maxf(
		float(_metrics.get(prefix + "max_pressure_pa_therm", 0.0)),
		float(room_state.get("pressure_pa_therm", 0.0))
	)
	_metrics[prefix + "max_overpressure_model_pa"] = maxf(
		float(_metrics.get(prefix + "max_overpressure_model_pa", 0.0)),
		float(room_state.get("overpressure_model_pa", 0.0))
	)
	# B-03: O2 depletion en capa superior (min tracking)
	var _cur_o2_upper: float = float(room_state.get("o2_upper", room_state.get("o2", 0.209)))
	if not _metrics.has(prefix + "min_o2_upper"):
		_metrics[prefix + "min_o2_upper"] = _cur_o2_upper
	else:
		_metrics[prefix + "min_o2_upper"] = minf(float(_metrics[prefix + "min_o2_upper"]), _cur_o2_upper)
	var current_fire_o2_ref: float = float(room_state.get("fire_o2_ref", room_state.get("o2", 0.209)))
	if not _metrics.has(prefix + "min_fire_o2_ref"):
		_metrics[prefix + "min_fire_o2_ref"] = current_fire_o2_ref
	else:
		_metrics[prefix + "min_fire_o2_ref"] = minf(
			float(_metrics[prefix + "min_fire_o2_ref"]),
			current_fire_o2_ref
		)
	_metrics[prefix + "max_ceiling_jet_temp_c"] = maxf(
		float(_metrics.get(prefix + "max_ceiling_jet_temp_c", 0.0)),
		float(room_state.get("ceiling_jet_temp_c", 0.0))
	)


func _capture_final_metrics(state: Dictionary) -> void:
	var watched_clamp_time_s: float = 0.0
	var watched_clamp_count: int = 0
	for room_id in _get_watch_room_ids():
		var room_state: Dictionary = state.get(str(room_id), {})
		if room_state.is_empty():
			continue

		var prefix: String = "room_%d_final_" % room_id
		_metrics[prefix + "hrr_kw"] = float(room_state.get("hrr_kw", 0.0))
		_metrics[prefix + "hrr_target_kw"] = float(room_state.get("hrr_target_kw", 0.0))
		_metrics[prefix + "pyrolysis_kw"] = float(room_state.get("pyrolysis_kw", 0.0))
		_metrics[prefix + "burned_hrr_kw"] = float(room_state.get("burned_hrr_kw", room_state.get("hrr_kw", 0.0)))
		_metrics[prefix + "unburned_generation_kw"] = float(room_state.get("unburned_generation_kw", 0.0))
		_metrics[prefix + "flame_hrr_target_kw"] = float(room_state.get("flame_hrr_target_kw", 0.0))
		_metrics[prefix + "smolder_hrr_target_kw"] = float(room_state.get("smolder_hrr_target_kw", 0.0))
		_metrics[prefix + "pool_release_hrr_target_kw"] = float(room_state.get("pool_release_hrr_target_kw", 0.0))
		_metrics[prefix + "fire_time_s"] = float(room_state.get("fire_time_s", 0.0))
		_metrics[prefix + "o2"] = float(room_state.get("o2", 0.0))
		_metrics[prefix + "o2_upper"] = float(room_state.get("o2_upper", room_state.get("o2", 0.0)))
		_metrics[prefix + "fire_o2_ref"] = float(room_state.get("fire_o2_ref", room_state.get("o2", 0.0)))
		_metrics[prefix + "fire_o2_min_ref"] = float(room_state.get("fire_o2_min_ref", 0.0))
		_metrics[prefix + "temp_upper_raw_c"] = float(room_state.get("temp_upper_raw_c", room_state.get("temp_upper_c", 0.0)))
		_metrics[prefix + "temp_upper_clamped"] = bool(room_state.get("temp_upper_clamped", false))
		_metrics[prefix + "temp_upper_clamp_time_s"] = float(room_state.get("temp_upper_clamp_time_s", 0.0))
		_metrics[prefix + "temp_upper_clamp_count"] = int(room_state.get("temp_upper_clamp_count", 0))
		_metrics[prefix + "smoke_kg"] = float(room_state.get("smoke_kg", 0.0))
		_metrics[prefix + "visibility_m"] = float(room_state.get("visibility_m", 30.0))
		_metrics[prefix + "co_ppm"] = float(room_state.get("co_ppm", 0.0))
		_metrics[prefix + "co_upper_ppm"] = float(room_state.get("co_upper_ppm", 0.0))
		_metrics[prefix + "co2_ppm"] = float(room_state.get("co2_ppm", 0.0))
		_metrics[prefix + "co2_upper_ppm"] = float(room_state.get("co2_upper_ppm", 0.0))
		_metrics[prefix + "fed"] = float(room_state.get("fed", 0.0))
		# Phase 4B: per-component FED for calibration observability (informational, non-gating).
		_metrics[prefix + "fed_co"] = float(room_state.get("fed_co", 0.0))
		_metrics[prefix + "fed_hcn"] = float(room_state.get("fed_hcn", 0.0))
		_metrics[prefix + "fed_hypoxia"] = float(room_state.get("fed_hypoxia", 0.0))
		_metrics[prefix + "fed_heat"] = float(room_state.get("fed_heat", 0.0))
		# SF-AUD-032: balance elemental de carbono (fracción de C producido vs disponible)
		_metrics[prefix + "c_balance_frac"] = float(room_state.get("c_balance_frac", 0.0))
		_metrics[prefix + "hot_layer_m"] = float(room_state.get("hot_layer_m", 0.0))
		_metrics[prefix + "smoke_layer_m"] = float(room_state.get("smoke_layer_m", 0.0))
		_metrics[prefix + "layer_150c_m"] = float(room_state.get("layer_150c_m", 0.0))
		_metrics[prefix + "temp_at_0_9m_c"] = float(room_state.get("temp_at_0_9m_c", 0.0))
		_metrics[prefix + "temp_at_1_8m_c"] = float(room_state.get("temp_at_1_8m_c", 0.0))
		# SF-AUD-039: TC array a alturas ISO 9705
		_metrics[prefix + "temp_at_0_1m_c"] = float(room_state.get("temp_at_0_1m_c", 0.0))
		_metrics[prefix + "temp_at_0_5m_c"] = float(room_state.get("temp_at_0_5m_c", 0.0))
		_metrics[prefix + "temp_at_1_0m_c"] = float(room_state.get("temp_at_1_0m_c", 0.0))
		_metrics[prefix + "temp_at_1_1m_c"] = float(room_state.get("temp_at_1_1m_c", 0.0))
		_metrics[prefix + "temp_at_1_5m_c"] = float(room_state.get("temp_at_1_5m_c", 0.0))
		_metrics[prefix + "temp_at_2_2m_c"] = float(room_state.get("temp_at_2_2m_c", 0.0))
		_metrics[prefix + "remaining_fuel_MJ"] = float(room_state.get("remaining_fuel_MJ", 0.0))
		_metrics[prefix + "fuel_objects_remaining_MJ"] = float(room_state.get("fuel_objects_remaining_MJ", 0.0))
		_metrics[prefix + "fuel_objects_heating_count"] = int(room_state.get("fuel_objects_heating_count", 0))
		_metrics[prefix + "fuel_objects_pyrolyzing_count"] = int(room_state.get("fuel_objects_pyrolyzing_count", 0))
		_metrics[prefix + "fuel_objects_flaming_count"] = int(room_state.get("fuel_objects_flaming_count", 0))
		_metrics[prefix + "dominant_fuel_object_id"] = String(room_state.get("dominant_fuel_object_id", ""))
		_metrics[prefix + "dominant_fuel_object_state"] = String(room_state.get("dominant_fuel_object_state", "none"))
		_metrics[prefix + "dominant_fuel_object_exposure_s"] = float(room_state.get("dominant_fuel_object_exposure_s", 0.0))
		_metrics[prefix + "dominant_fuel_object_remaining_MJ"] = float(room_state.get("dominant_fuel_object_remaining_MJ", 0.0))
		_metrics[prefix + "retained_unburned_MJ"] = float(room_state.get("retained_unburned_MJ", 0.0))
		_metrics[prefix + "o2_hrr_factor"] = float(room_state.get("o2_hrr_factor", 0.0))
		_metrics[prefix + "ventilation_response_factor"] = float(room_state.get("ventilation_response_factor", 0.0))
		_metrics[prefix + "outside_open_path_factor"] = float(room_state.get("outside_open_path_factor", 0.0))
		_metrics[prefix + "pressure_pa_therm"] = float(room_state.get("pressure_pa_therm", 0.0))
		_metrics[prefix + "overpressure_model_pa"] = float(room_state.get("overpressure_model_pa", 0.0))
		_metrics[prefix + "upper_radiative_loss_kw"] = float(room_state.get("upper_radiative_loss_kw", 0.0))
		_metrics[prefix + "upper_zone_mass_kg"] = float(room_state.get("upper_zone_mass_kg", 0.0))
		_metrics[prefix + "lower_zone_mass_kg"] = float(room_state.get("lower_zone_mass_kg", 0.0))
		_metrics[prefix + "upper_zone_energy_kj"] = float(room_state.get("upper_zone_energy_kj", 0.0))
		_metrics[prefix + "lower_zone_energy_kj"] = float(room_state.get("lower_zone_energy_kj", 0.0))
		_metrics[prefix + "zone_total_mass_kg"] = float(room_state.get("zone_total_mass_kg", 0.0))
		_metrics[prefix + "zone_total_energy_kj"] = float(room_state.get("zone_total_energy_kj", 0.0))
		_metrics[prefix + "two_zone_boundary_mass_kg"] = float(
			room_state.get("two_zone_boundary_mass_kg", 0.0)
		)
		_metrics[prefix + "two_zone_boundary_energy_kj"] = float(
			room_state.get("two_zone_boundary_energy_kj", 0.0)
		)
		_metrics[prefix + "two_zone_opening_upper_in_kg"] = float(
			room_state.get("two_zone_opening_upper_in_kg", 0.0)
		)
		_metrics[prefix + "two_zone_opening_upper_out_kg"] = float(
			room_state.get("two_zone_opening_upper_out_kg", 0.0)
		)
		_metrics[prefix + "two_zone_opening_lower_in_kg"] = float(
			room_state.get("two_zone_opening_lower_in_kg", 0.0)
		)
		_metrics[prefix + "two_zone_opening_lower_out_kg"] = float(
			room_state.get("two_zone_opening_lower_out_kg", 0.0)
		)
		# SF-AUD-028: budget energético (disponible cuando energy_budget_enabled=true)
		var bud_e_fire: float = float(room_state.get("bud_e_fire_kj", 0.0))
		var bud_q_residual: float = float(room_state.get("bud_q_residual_kj", 0.0))
		_metrics[prefix + "bud_e_fire_kj"] = bud_e_fire
		_metrics[prefix + "bud_q_residual_kj"] = bud_q_residual
		_metrics[prefix + "bud_residual_frac"] = absf(bud_q_residual) / maxf(bud_e_fire, 1e-9)
		# SF-AUD-028: residual acumulado (Σ a lo largo de toda la simulación, tolerancia ≤ 10 %)
		var bud_cum_e_fire: float = float(room_state.get("bud_cum_e_fire_kj", 0.0))
		var bud_cum_q_residual: float = float(room_state.get("bud_cum_q_residual_kj", 0.0))
		_metrics[prefix + "bud_cum_e_fire_kj"] = bud_cum_e_fire
		_metrics[prefix + "bud_cum_q_residual_kj"] = bud_cum_q_residual
		_metrics[prefix + "bud_cum_residual_frac"] = absf(bud_cum_q_residual) / maxf(bud_cum_e_fire, 1e-9)
		# SF-AUD-030: perfil 1D pared Crank-Nicolson
		_metrics[prefix + "wall_T_mid_c"] = float(room_state.get("wall_T_mid_c", 20.0))
		_metrics[prefix + "wall_T_outer_c"] = float(room_state.get("wall_T_outer_c", 20.0))
		_metrics[prefix + "wall_k_kw_m_k"] = float(room_state.get("wall_k_kw_m_k", -1.0))
		_metrics[prefix + "wall_thickness_m"] = float(room_state.get("wall_thickness_m", -999.0))
		watched_clamp_time_s += float(room_state.get("temp_upper_clamp_time_s", 0.0))
		watched_clamp_count += int(room_state.get("temp_upper_clamp_count", 0))

	_metrics["watched_temp_upper_clamp_time_s"] = watched_clamp_time_s
	_metrics["watched_temp_upper_clamp_count"] = watched_clamp_count

	# SF-AUD-029: exportar métricas de targets radiantes pasivos
	var targets_state: Dictionary = state.get("targets", {})
	for target_id in targets_state.keys():
		var ts: Dictionary = targets_state.get(target_id, {})
		_metrics["target_%s_peak_qnet_kw_m2" % target_id] = float(ts.get("peak_qnet_kw_m2", 0.0))
		_metrics["target_%s_final_qnet_kw_m2" % target_id] = float(ts.get("qnet_kw_m2", 0.0))
		_metrics["target_%s_final_temp_c" % target_id] = float(ts.get("temp_c", 20.0))
		_metrics["target_%s_ignited" % target_id] = 1.0 if bool(ts.get("ignited", false)) else 0.0

	# SF-VIC-001: FED final e incapacitación de cada víctima
	for vic_state in state.get("victims", []):
		if typeof(vic_state) != TYPE_DICTIONARY:
			continue
		var vic_id: String = String(vic_state.get("id", ""))
		if vic_id.is_empty():
			continue
		_metrics["victim_%s_final_fed" % vic_id] = float(vic_state.get("fed", 0.0))
		_metrics["victim_%s_incapacitated" % vic_id] = 1.0 if bool(vic_state.get("incapacitated", false)) else 0.0


func _finalize_validation_run(state: Dictionary) -> void:
	_active = false
	_capture_final_metrics(state)

	var report: Dictionary = {
		"case": _case_name,
		"engine_mode": _engine_mode,
		"fire_o2_mode_requested": _fire_o2_mode,
		"fire_o2_mode": String(state.get("fire_o2_effective_mode", _fire_o2_mode)),
		"comparison_contract_version": 1,
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


func _update_threshold_metrics(state: Dictionary, sim_time_s: float) -> void:
	var raw_thresholds: Variant = _case_config.get("threshold_metrics", [])
	if typeof(raw_thresholds) != TYPE_ARRAY:
		return

	for raw_threshold in raw_thresholds:
		if typeof(raw_threshold) != TYPE_DICTIONARY:
			continue

		var threshold_config: Dictionary = raw_threshold
		var metric_name: String = String(threshold_config.get("metric_name", ""))
		if metric_name.is_empty() or _metrics.has(metric_name):
			continue
		if sim_time_s < float(threshold_config.get("after_time_s", 0.0)):
			continue

		var resolved: Dictionary = _resolve_threshold_value(state, threshold_config)
		if not bool(resolved.get("ok", false)):
			continue

		var actual_value: float = float(resolved.get("value", 0.0))
		var threshold_value: float = float(threshold_config.get("value", 0.0))
		var op: String = String(threshold_config.get("op", ">="))
		if _threshold_passes(actual_value, op, threshold_value):
			_metrics[metric_name] = sim_time_s


func _resolve_threshold_value(state: Dictionary, threshold_config: Dictionary) -> Dictionary:
	var field_name: String = String(threshold_config.get("field", ""))
	if field_name.is_empty():
		return {"ok": false}

	if threshold_config.has("room_id"):
		var room_id: int = int(threshold_config.get("room_id", -1))
		var room_state: Dictionary = state.get(str(room_id), {})
		if room_state.is_empty() or not room_state.has(field_name):
			return {"ok": false}
		return {
			"ok": true,
			"value": float(room_state.get(field_name, 0.0))
		}

	if not state.has(field_name):
		return {"ok": false}

	return {
		"ok": true,
		"value": float(state.get(field_name, 0.0))
	}


func _threshold_passes(actual_value: float, op: String, threshold_value: float) -> bool:
	match op:
		">":
			return actual_value > threshold_value
		">=":
			return actual_value >= threshold_value
		"<":
			return actual_value < threshold_value
		"<=":
			return actual_value <= threshold_value
		_:
			push_warning("CaseRunner: operador de umbral no soportado '%s'" % op)
			return false


## Procesa la lista `room_delta_max_metrics` del caso: para cada entrada, calcula
## (room_a.field_a − room_b.field_b) en cada paso y almacena el máximo histórico.
## Soporta distintas salas y/o distintos campos — BV-013 (presión entre plantas)
## y BV-028 (ceiling-jet vs. capa superior).
## Config: {metric_name, room_a_id, room_b_id, field_a|field, field_b|field, after_time_s?}
func _update_delta_max_metrics(state: Dictionary, sim_time_s: float) -> void:
	var raw_deltas: Variant = _case_config.get("room_delta_max_metrics", [])
	if typeof(raw_deltas) != TYPE_ARRAY:
		return
	for raw_delta in raw_deltas:
		if typeof(raw_delta) != TYPE_DICTIONARY:
			continue
		if sim_time_s < float(raw_delta.get("after_time_s", 0.0)):
			continue
		var metric_name: String = String(raw_delta.get("metric_name", ""))
		if metric_name.is_empty():
			continue
		var room_a_id: int = int(raw_delta.get("room_a_id", -1))
		var room_b_id: int = int(raw_delta.get("room_b_id", -1))
		var field_a: String = String(raw_delta.get("field_a", raw_delta.get("field", "")))
		var field_b: String = String(raw_delta.get("field_b", raw_delta.get("field", "")))
		if field_a.is_empty() or field_b.is_empty():
			continue
		var ra: Dictionary = state.get(str(room_a_id), {})
		var rb: Dictionary = state.get(str(room_b_id), {})
		if ra.is_empty() or rb.is_empty():
			continue
		var val_a: float = float(ra.get(field_a, 0.0))
		var val_b: float = float(rb.get(field_b, 0.0))
		var delta: float = val_a - val_b
		_metrics[metric_name] = maxf(float(_metrics.get(metric_name, delta)), delta)


func _read_text_file(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null and path.begins_with("res://"):
		file = FileAccess.open(ProjectSettings.globalize_path(path), FileAccess.READ)
	if file == null and path.begins_with("res://"):
		var project_root: String = ProjectSettings.globalize_path("res://")
		var absolute_path: String = project_root.path_join(path.trim_prefix("res://"))
		file = FileAccess.open(absolute_path, FileAccess.READ)
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

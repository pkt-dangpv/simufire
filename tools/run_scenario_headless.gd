extends Node

const BuildingModelScript := preload("res://sim/BuildingModel.gd")
const BuildingTemplateScript := preload("res://sim/templates/BuildingTemplate.gd")
const SimulationEngineScript := preload("res://sim/core/SimulationEngine.gd")
const TargetModelScript := preload("res://sim/fire/TargetModel.gd")

var _cli_args: Dictionary = {}
var _scenario_path: String = ""
var _out_dir: String = ""
var _failed: bool = false
var _projection_trace_enabled: bool = false
var _projection_trace_path: String = ""
var _projection_trace_file: FileAccess = null


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_cli_args = _parse_args(OS.get_cmdline_user_args())
	_scenario_path = _resolve_path(String(_cli_args.get("run_scenario", "")))
	_out_dir = _resolve_output_dir(String(_cli_args.get("out_dir", "")))

	if _scenario_path.is_empty():
		_abort("run_scenario_headless: missing --run-scenario <path>")
		return
	if not FileAccess.file_exists(_scenario_path):
		_abort("run_scenario_headless: scenario not found: %s" % _scenario_path)
		return
	if _out_dir.is_empty():
		_abort("run_scenario_headless: missing --out-dir <path>")
		return

	DirAccess.make_dir_recursive_absolute(_out_dir)
	var scenario: Dictionary = _load_json(_scenario_path)
	if scenario.is_empty():
		_abort("run_scenario_headless: scenario is empty or invalid JSON")
		return

	var template_data: Dictionary = _build_template_data(scenario)
	if template_data.is_empty():
		_abort("run_scenario_headless: could not build a runtime template")
		return

	var building: BuildingModel = BuildingModelScript.new()
	building.load_template_data(template_data)

	var engine: SimulationEngine = SimulationEngineScript.new()
	engine.name = "RunScenarioEngine"
	engine.building = building
	engine.auto_ignite_on_ready = false
	engine.auto_finish_on_extinction = false
	engine.enable_logging = true
	engine.enable_csv_log = true
	engine.log_interval_s = maxf(0.001, float(scenario.get("log_interval_s", 1.0)))
	engine.log_file_path = _out_dir.path_join("sim_log.txt")
	engine.csv_log_file_path = _out_dir.path_join("sim_log.csv")
	if scenario.has("ignition_room_id"):
		engine.ignition_room_id = int(scenario.get("ignition_room_id", engine.ignition_room_id))
	elif building.default_ignition_room_id != 0:
		engine.ignition_room_id = building.default_ignition_room_id

	add_child(engine)
	await get_tree().process_frame

	_apply_engine_overrides(engine, scenario.get("engine_overrides", {}))
	# The run artifact directory owns output paths even when a validation case
	# carries repository report paths inside engine_overrides.
	engine.log_file_path = _out_dir.path_join("sim_log.txt")
	engine.csv_log_file_path = _out_dir.path_join("sim_log.csv")
	if bool(_cli_args.get("phase3_zone_diagnostics", false)):
		engine.phase3_zone_diagnostics_enabled = true
	if bool(_cli_args.get("phase3_canonical_shadow", false)):
		engine.phase3_canonical_zone_shadow_enabled = true
	if bool(_cli_args.get("phase3_canonical_exterior_shadow", false)):
		engine.phase3_canonical_zone_shadow_enabled = true
		engine.phase3_canonical_exterior_boundary_shadow_enabled = true
	if bool(_cli_args.get("phase3_canonical_persistence_shadow", false)):
		engine.phase3_canonical_zone_shadow_enabled = true
		engine.phase3_canonical_exterior_boundary_shadow_enabled = true
		engine.phase3_canonical_persistence_shadow_enabled = true
	if bool(_cli_args.get("phase3_canonical_combustion_shadow", false)):
		engine.phase3_canonical_zone_shadow_enabled = true
		engine.phase3_canonical_exterior_boundary_shadow_enabled = true
		engine.phase3_canonical_persistence_shadow_enabled = true
		engine.phase3_canonical_combustion_shadow_enabled = true
	if bool(_cli_args.get("phase3_canonical_fire_proposal_shadow", false)):
		engine.phase3_canonical_zone_shadow_enabled = true
		engine.phase3_canonical_exterior_boundary_shadow_enabled = true
		engine.phase3_canonical_persistence_shadow_enabled = true
		engine.phase3_canonical_combustion_shadow_enabled = true
		engine.phase3_canonical_fire_proposal_shadow_enabled = true
	if bool(_cli_args.get(
		"phase3_canonical_unfiltered_fire_growth_shadow", false
	)):
		engine.phase3_canonical_zone_shadow_enabled = true
		engine.phase3_canonical_exterior_boundary_shadow_enabled = true
		engine.phase3_canonical_persistence_shadow_enabled = true
		engine.phase3_canonical_combustion_shadow_enabled = true
		engine.phase3_canonical_fire_proposal_shadow_enabled = true
		engine.phase3_canonical_unfiltered_fire_growth_shadow_enabled = true
	if bool(_cli_args.get("phase3_canonical_fire_products_shadow", false)):
		engine.phase3_canonical_zone_shadow_enabled = true
		engine.phase3_canonical_exterior_boundary_shadow_enabled = true
		engine.phase3_canonical_persistence_shadow_enabled = true
		engine.phase3_canonical_combustion_shadow_enabled = true
		engine.phase3_canonical_fire_proposal_shadow_enabled = true
		engine.phase3_canonical_fire_products_shadow_enabled = true
	if bool(_cli_args.get(
		"phase3_canonical_fire_products_routing_shadow", false
	)):
		engine.phase3_canonical_zone_shadow_enabled = true
		engine.phase3_canonical_exterior_boundary_shadow_enabled = true
		engine.phase3_canonical_persistence_shadow_enabled = true
		engine.phase3_canonical_combustion_shadow_enabled = true
		engine.phase3_canonical_plume_shadow_enabled = true
		engine.phase3_canonical_fire_proposal_shadow_enabled = true
		engine.phase3_canonical_fire_products_shadow_enabled = true
		engine.phase3_canonical_fire_products_routing_shadow_enabled = true
	if bool(_cli_args.get("phase3_canonical_fuel_object_sync_shadow", false)):
		engine.phase3_canonical_zone_shadow_enabled = true
		engine.phase3_canonical_exterior_boundary_shadow_enabled = true
		engine.phase3_canonical_persistence_shadow_enabled = true
		engine.phase3_canonical_combustion_shadow_enabled = true
		engine.phase3_canonical_plume_shadow_enabled = true
		engine.phase3_canonical_fire_proposal_shadow_enabled = true
		engine.phase3_canonical_fire_products_shadow_enabled = true
		engine.phase3_canonical_fire_products_routing_shadow_enabled = true
		engine.phase3_canonical_fuel_object_sync_shadow_enabled = true
	if bool(_cli_args.get("phase3_canonical_pressure_relaxation_shadow", false)):
		engine.phase3_canonical_zone_shadow_enabled = true
		engine.phase3_canonical_exterior_boundary_shadow_enabled = true
		engine.phase3_canonical_persistence_shadow_enabled = true
		engine.phase3_canonical_combustion_shadow_enabled = true
		engine.phase3_canonical_pressure_relaxation_shadow_enabled = true
	if bool(_cli_args.get("phase3_canonical_plume_shadow", false)):
		engine.phase3_canonical_zone_shadow_enabled = true
		engine.phase3_canonical_exterior_boundary_shadow_enabled = true
		engine.phase3_canonical_persistence_shadow_enabled = true
		engine.phase3_canonical_combustion_shadow_enabled = true
		engine.phase3_canonical_pressure_relaxation_shadow_enabled = true
		engine.phase3_canonical_plume_shadow_enabled = true
	if bool(_cli_args.get("phase3_canonical_interzone_heat_shadow", false)):
		engine.phase3_canonical_zone_shadow_enabled = true
		engine.phase3_canonical_exterior_boundary_shadow_enabled = true
		engine.phase3_canonical_persistence_shadow_enabled = true
		engine.phase3_canonical_combustion_shadow_enabled = true
		engine.phase3_canonical_pressure_relaxation_shadow_enabled = true
		engine.phase3_canonical_plume_shadow_enabled = true
		engine.phase3_canonical_interzone_heat_shadow_enabled = true
	if bool(_cli_args.get("phase3_canonical_wall_ambient_shadow", false)):
		engine.phase3_canonical_zone_shadow_enabled = true
		engine.phase3_canonical_exterior_boundary_shadow_enabled = true
		engine.phase3_canonical_persistence_shadow_enabled = true
		engine.phase3_canonical_combustion_shadow_enabled = true
		engine.phase3_canonical_pressure_relaxation_shadow_enabled = true
		engine.phase3_canonical_plume_shadow_enabled = true
		engine.phase3_canonical_interzone_heat_shadow_enabled = true
		engine.phase3_canonical_wall_ambient_shadow_enabled = true
	if bool(_cli_args.get("phase3_canonical_exterior_counterflow_shadow", false)):
		engine.phase3_canonical_zone_shadow_enabled = true
		engine.phase3_canonical_exterior_boundary_shadow_enabled = true
		engine.phase3_canonical_persistence_shadow_enabled = true
		engine.phase3_canonical_combustion_shadow_enabled = true
		engine.phase3_canonical_pressure_relaxation_shadow_enabled = true
		engine.phase3_canonical_plume_shadow_enabled = true
		engine.phase3_canonical_interzone_heat_shadow_enabled = true
		engine.phase3_canonical_wall_ambient_shadow_enabled = true
		engine.phase3_canonical_exterior_counterflow_shadow_enabled = true
	if bool(_cli_args.get("phase3_canonical_post_opening_coupling_shadow", false)):
		engine.phase3_canonical_zone_shadow_enabled = true
		engine.phase3_canonical_exterior_boundary_shadow_enabled = true
		engine.phase3_canonical_persistence_shadow_enabled = true
		engine.phase3_canonical_combustion_shadow_enabled = true
		engine.phase3_canonical_pressure_relaxation_shadow_enabled = true
		engine.phase3_canonical_plume_shadow_enabled = true
		engine.phase3_canonical_interzone_heat_shadow_enabled = true
		engine.phase3_canonical_wall_ambient_shadow_enabled = true
		engine.phase3_canonical_exterior_counterflow_shadow_enabled = true
		engine.phase3_canonical_post_opening_coupling_shadow_enabled = true
	if bool(_cli_args.get("phase3_canonical_interior_opening_shadow", false)):
		engine.phase3_canonical_zone_shadow_enabled = true
		engine.phase3_canonical_exterior_boundary_shadow_enabled = true
		engine.phase3_canonical_persistence_shadow_enabled = true
		engine.phase3_canonical_combustion_shadow_enabled = true
		engine.phase3_canonical_pressure_relaxation_shadow_enabled = true
		engine.phase3_canonical_plume_shadow_enabled = true
		engine.phase3_canonical_interzone_heat_shadow_enabled = true
		engine.phase3_canonical_wall_ambient_shadow_enabled = true
		engine.phase3_canonical_exterior_counterflow_shadow_enabled = true
		engine.phase3_canonical_post_opening_coupling_shadow_enabled = true
		engine.phase3_canonical_interior_opening_shadow_enabled = true
	if bool(_cli_args.get("phase3_canonical_interior_pressure_shadow", false)):
		engine.phase3_canonical_zone_shadow_enabled = true
		engine.phase3_canonical_exterior_boundary_shadow_enabled = true
		engine.phase3_canonical_persistence_shadow_enabled = true
		engine.phase3_canonical_combustion_shadow_enabled = true
		engine.phase3_canonical_pressure_relaxation_shadow_enabled = true
		engine.phase3_canonical_plume_shadow_enabled = true
		engine.phase3_canonical_interzone_heat_shadow_enabled = true
		engine.phase3_canonical_wall_ambient_shadow_enabled = true
		engine.phase3_canonical_exterior_counterflow_shadow_enabled = true
		engine.phase3_canonical_post_opening_coupling_shadow_enabled = true
		engine.phase3_canonical_interior_opening_shadow_enabled = true
		engine.phase3_canonical_interior_pressure_shadow_enabled = true
	if bool(_cli_args.get(
		"phase3_canonical_fixed_gross_pressure_skew_shadow", false
	)):
		engine.phase3_canonical_zone_shadow_enabled = true
		engine.phase3_canonical_exterior_boundary_shadow_enabled = true
		engine.phase3_canonical_persistence_shadow_enabled = true
		engine.phase3_canonical_combustion_shadow_enabled = true
		engine.phase3_canonical_pressure_relaxation_shadow_enabled = true
		engine.phase3_canonical_plume_shadow_enabled = true
		engine.phase3_canonical_interzone_heat_shadow_enabled = true
		engine.phase3_canonical_wall_ambient_shadow_enabled = true
		engine.phase3_canonical_exterior_counterflow_shadow_enabled = true
		engine.phase3_canonical_post_opening_coupling_shadow_enabled = true
		engine.phase3_canonical_interior_opening_shadow_enabled = true
		engine.phase3_canonical_interior_pressure_shadow_enabled = true
		engine.phase3_canonical_fixed_gross_pressure_skew_shadow_enabled = true
	if bool(_cli_args.get(
		"phase3_canonical_fixed_gross_pressure_network_shadow", false
	)):
		engine.phase3_canonical_zone_shadow_enabled = true
		engine.phase3_canonical_exterior_boundary_shadow_enabled = true
		engine.phase3_canonical_persistence_shadow_enabled = true
		engine.phase3_canonical_combustion_shadow_enabled = true
		engine.phase3_canonical_pressure_relaxation_shadow_enabled = true
		engine.phase3_canonical_plume_shadow_enabled = true
		engine.phase3_canonical_interzone_heat_shadow_enabled = true
		engine.phase3_canonical_wall_ambient_shadow_enabled = true
		engine.phase3_canonical_exterior_counterflow_shadow_enabled = true
		engine.phase3_canonical_post_opening_coupling_shadow_enabled = true
		engine.phase3_canonical_interior_opening_shadow_enabled = true
		engine.phase3_canonical_interior_pressure_shadow_enabled = true
		engine.phase3_canonical_fixed_gross_pressure_skew_shadow_enabled = true
		engine.phase3_canonical_fixed_gross_pressure_network_shadow_enabled = true
	if bool(_cli_args.get("phase3_coupled_pressure_solver_shadow", false)):
		engine.phase3_canonical_zone_shadow_enabled = true
		engine.phase3_canonical_exterior_boundary_shadow_enabled = true
		engine.phase3_canonical_persistence_shadow_enabled = true
		engine.phase3_canonical_combustion_shadow_enabled = true
		engine.phase3_canonical_pressure_relaxation_shadow_enabled = true
		engine.phase3_canonical_plume_shadow_enabled = true
		engine.phase3_canonical_interzone_heat_shadow_enabled = true
		engine.phase3_canonical_wall_ambient_shadow_enabled = true
		engine.phase3_canonical_exterior_counterflow_shadow_enabled = true
		engine.phase3_canonical_post_opening_coupling_shadow_enabled = true
		engine.phase3_canonical_interior_opening_shadow_enabled = true
		engine.phase3_canonical_interior_pressure_shadow_enabled = true
		engine.phase3_coupled_pressure_solver_shadow_enabled = true
	if bool(_cli_args.get("phase3_enthalpy_residence_diagnostics", false)):
		engine.phase3_canonical_zone_shadow_enabled = true
		engine.phase3_canonical_exterior_boundary_shadow_enabled = true
		engine.phase3_canonical_persistence_shadow_enabled = true
		engine.phase3_canonical_combustion_shadow_enabled = true
		engine.phase3_canonical_pressure_relaxation_shadow_enabled = true
		engine.phase3_canonical_plume_shadow_enabled = true
		engine.phase3_canonical_interzone_heat_shadow_enabled = true
		engine.phase3_canonical_wall_ambient_shadow_enabled = true
		engine.phase3_canonical_exterior_counterflow_shadow_enabled = true
		engine.phase3_canonical_post_opening_coupling_shadow_enabled = true
		engine.phase3_canonical_interior_opening_shadow_enabled = true
		engine.phase3_canonical_interior_pressure_shadow_enabled = true
		engine.phase3_enthalpy_residence_diagnostics_enabled = true
	if bool(_cli_args.get("phase3_mass_residence_diagnostics", false)):
		engine.phase3_canonical_zone_shadow_enabled = true
		engine.phase3_canonical_exterior_boundary_shadow_enabled = true
		engine.phase3_canonical_persistence_shadow_enabled = true
		engine.phase3_canonical_combustion_shadow_enabled = true
		engine.phase3_canonical_pressure_relaxation_shadow_enabled = true
		engine.phase3_canonical_plume_shadow_enabled = true
		engine.phase3_canonical_interzone_heat_shadow_enabled = true
		engine.phase3_canonical_wall_ambient_shadow_enabled = true
		engine.phase3_canonical_exterior_counterflow_shadow_enabled = true
		engine.phase3_canonical_post_opening_coupling_shadow_enabled = true
		engine.phase3_canonical_interior_opening_shadow_enabled = true
		engine.phase3_canonical_interior_pressure_shadow_enabled = true
		engine.phase3_mass_residence_diagnostics_enabled = true
	if bool(_cli_args.get("phase3_connection_residence_diagnostics", false)):
		engine.phase3_canonical_zone_shadow_enabled = true
		engine.phase3_canonical_exterior_boundary_shadow_enabled = true
		engine.phase3_canonical_persistence_shadow_enabled = true
		engine.phase3_canonical_combustion_shadow_enabled = true
		engine.phase3_canonical_pressure_relaxation_shadow_enabled = true
		engine.phase3_canonical_plume_shadow_enabled = true
		engine.phase3_canonical_interzone_heat_shadow_enabled = true
		engine.phase3_canonical_wall_ambient_shadow_enabled = true
		engine.phase3_canonical_exterior_counterflow_shadow_enabled = true
		engine.phase3_canonical_post_opening_coupling_shadow_enabled = true
		engine.phase3_canonical_interior_opening_shadow_enabled = true
		engine.phase3_canonical_interior_pressure_shadow_enabled = true
		engine.phase3_enthalpy_residence_diagnostics_enabled = true
		engine.phase3_mass_residence_diagnostics_enabled = true
		engine.phase3_connection_residence_diagnostics_enabled = true
	if bool(_cli_args.get("phase3_cfast_buoyancy_destination_shadow", false)):
		engine.phase3_canonical_zone_shadow_enabled = true
		engine.phase3_canonical_exterior_boundary_shadow_enabled = true
		engine.phase3_canonical_persistence_shadow_enabled = true
		engine.phase3_canonical_combustion_shadow_enabled = true
		engine.phase3_canonical_pressure_relaxation_shadow_enabled = true
		engine.phase3_canonical_plume_shadow_enabled = true
		engine.phase3_canonical_interzone_heat_shadow_enabled = true
		engine.phase3_canonical_wall_ambient_shadow_enabled = true
		engine.phase3_canonical_exterior_counterflow_shadow_enabled = true
		engine.phase3_canonical_post_opening_coupling_shadow_enabled = true
		engine.phase3_canonical_interior_opening_shadow_enabled = true
		engine.phase3_canonical_interior_pressure_shadow_enabled = true
		engine.phase3_enthalpy_residence_diagnostics_enabled = true
		engine.phase3_mass_residence_diagnostics_enabled = true
		engine.phase3_connection_residence_diagnostics_enabled = true
		engine.phase3_cfast_buoyancy_destination_shadow_enabled = true
	_projection_trace_enabled = bool(scenario.get("phase3_projection_trace_enabled", false))
	if _projection_trace_enabled:
		engine.phase3_zone_diagnostics_enabled = true
	var ignite_on_start: bool = not bool(_cli_args.get("no_ignite", false)) and bool(scenario.get("ignite_on_start", true))
	engine.reset_simulation(engine.ignition_room_id, ignite_on_start)
	engine.sim_duration_limit_s = 0.0
	_load_targets(engine, scenario.get("targets", []))

	var duration_s: float = _resolve_duration_s(scenario, building)
	var step_s: float = _resolve_step_s(scenario)
	var opening_events: Array = _prepare_opening_events(scenario.get("opening_events", []))
	var suppression_events: Array = _prepare_suppression_events(scenario.get("suppression_events", []))
	if not _open_projection_trace():
		return

	if not _run_loop(engine, building, duration_s, step_s, opening_events, suppression_events):
		_close_projection_trace()
		return
	_close_projection_trace()

	var details: String = "run_scenario scenario=%s duration_s=%.3f step_s=%.3f" % [
		_scenario_path.get_file(),
		duration_s,
		step_s
	]
	if not engine.export_technical_results(details, _out_dir):
		_abort("run_scenario_headless: technical export failed")
		return

	if not _write_manifest(engine, duration_s, step_s, ignite_on_start):
		_abort("run_scenario_headless: could not write run_manifest.json")
		return
	if not _validate_outputs():
		return

	var csv_path: String = engine.log_writer.resolve_csv_file_path()
	print("RUN_SCENARIO PASS")
	print("summary=%s" % _out_dir.path_join("summary.json"))
	print("events=%s" % _out_dir.path_join("events.json"))
	print("csv=%s" % csv_path)
	remove_child(engine)
	engine.free()
	building.free()
	get_tree().quit(0)


func _parse_args(args: Array[String]) -> Dictionary:
	var parsed: Dictionary = {}
	var index: int = 0
	while index < args.size():
		var arg: String = String(args[index])
		if arg.begins_with("--run-scenario="):
			parsed["run_scenario"] = arg.substr("--run-scenario=".length())
		elif arg == "--run-scenario" and index + 1 < args.size():
			index += 1
			parsed["run_scenario"] = String(args[index])
		elif arg.begins_with("--scenario="):
			parsed["run_scenario"] = arg.substr("--scenario=".length())
		elif arg == "--scenario" and index + 1 < args.size():
			index += 1
			parsed["run_scenario"] = String(args[index])
		elif arg.begins_with("--out-dir="):
			parsed["out_dir"] = arg.substr("--out-dir=".length())
		elif arg == "--out-dir" and index + 1 < args.size():
			index += 1
			parsed["out_dir"] = String(args[index])
		elif arg.begins_with("--duration="):
			parsed["duration_s"] = float(arg.substr("--duration=".length()))
		elif arg == "--duration" and index + 1 < args.size():
			index += 1
			parsed["duration_s"] = float(args[index])
		elif arg.begins_with("--step="):
			parsed["step_s"] = float(arg.substr("--step=".length()))
		elif arg == "--step" and index + 1 < args.size():
			index += 1
			parsed["step_s"] = float(args[index])
		elif arg == "--no-ignite":
			parsed["no_ignite"] = true
		elif arg == "--phase3-zone-diagnostics":
			parsed["phase3_zone_diagnostics"] = true
		elif arg == "--phase3-canonical-shadow":
			parsed["phase3_canonical_shadow"] = true
		elif arg == "--phase3-canonical-exterior-shadow":
			parsed["phase3_canonical_exterior_shadow"] = true
		elif arg == "--phase3-canonical-persistence-shadow":
			parsed["phase3_canonical_persistence_shadow"] = true
		elif arg == "--phase3-canonical-combustion-shadow":
			parsed["phase3_canonical_combustion_shadow"] = true
		elif arg == "--phase3-canonical-fire-proposal-shadow":
			parsed["phase3_canonical_fire_proposal_shadow"] = true
		elif arg == "--phase3-canonical-unfiltered-fire-growth-shadow":
			parsed["phase3_canonical_unfiltered_fire_growth_shadow"] = true
		elif arg == "--phase3-canonical-fire-products-shadow":
			parsed["phase3_canonical_fire_products_shadow"] = true
		elif arg == "--phase3-canonical-fire-products-routing-shadow":
			parsed["phase3_canonical_fire_products_routing_shadow"] = true
		elif arg == "--phase3-canonical-fuel-object-sync-shadow":
			parsed["phase3_canonical_fuel_object_sync_shadow"] = true
		elif arg == "--phase3-canonical-pressure-relaxation-shadow":
			parsed["phase3_canonical_pressure_relaxation_shadow"] = true
		elif arg == "--phase3-canonical-plume-shadow":
			parsed["phase3_canonical_plume_shadow"] = true
		elif arg == "--phase3-canonical-interzone-heat-shadow":
			parsed["phase3_canonical_interzone_heat_shadow"] = true
		elif arg == "--phase3-canonical-wall-ambient-shadow":
			parsed["phase3_canonical_wall_ambient_shadow"] = true
		elif arg == "--phase3-canonical-exterior-counterflow-shadow":
			parsed["phase3_canonical_exterior_counterflow_shadow"] = true
		elif arg == "--phase3-canonical-post-opening-coupling-shadow":
			parsed["phase3_canonical_post_opening_coupling_shadow"] = true
		elif arg == "--phase3-canonical-interior-opening-shadow":
			parsed["phase3_canonical_interior_opening_shadow"] = true
		elif arg == "--phase3-canonical-interior-pressure-shadow":
			parsed["phase3_canonical_interior_pressure_shadow"] = true
		elif arg == "--phase3-canonical-fixed-gross-pressure-skew-shadow":
			parsed["phase3_canonical_fixed_gross_pressure_skew_shadow"] = true
		elif arg == "--phase3-canonical-fixed-gross-pressure-network-shadow":
			parsed["phase3_canonical_fixed_gross_pressure_network_shadow"] = true
		elif arg == "--phase3-coupled-pressure-solver-shadow":
			parsed["phase3_coupled_pressure_solver_shadow"] = true
		elif arg == "--phase3-enthalpy-residence-diagnostics":
			parsed["phase3_enthalpy_residence_diagnostics"] = true
		elif arg == "--phase3-mass-residence-diagnostics":
			parsed["phase3_mass_residence_diagnostics"] = true
		elif arg == "--phase3-connection-residence-diagnostics":
			parsed["phase3_connection_residence_diagnostics"] = true
		elif arg == "--phase3-cfast-buoyancy-destination-shadow":
			parsed["phase3_cfast_buoyancy_destination_shadow"] = true
		index += 1
	return parsed


func _resolve_path(raw_path: String) -> String:
	var path: String = raw_path.strip_edges()
	if path.is_empty():
		return ""
	if path.begins_with("res://") or path.begins_with("user://"):
		return ProjectSettings.globalize_path(path)
	path = path.replace("\\", "/")
	if _is_absolute_path(path):
		return path
	return ProjectSettings.globalize_path("res://").path_join(path)


func _resolve_output_dir(raw_path: String) -> String:
	if raw_path.strip_edges().is_empty():
		return ProjectSettings.globalize_path("user://run_scenario")
	return _resolve_path(raw_path)


func _is_absolute_path(path: String) -> bool:
	if path.begins_with("/") or path.begins_with("\\"):
		return true
	return path.length() >= 3 and path.substr(1, 1) == ":" and path.substr(2, 1) == "/"


func _load_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


func _build_template_data(scenario: Dictionary) -> Dictionary:
	var template_data: Dictionary = {}
	if scenario.has("rooms_data") and scenario.has("room_rect_m"):
		template_data = scenario.duplicate(true)
	else:
		var template_name: String = String(scenario.get("template", "simple_house"))
		var builder = BuildingTemplateScript.new()
		if not _is_supported_template(builder, template_name):
			push_error("run_scenario_headless: unsupported template '%s'" % template_name)
			return {}
		template_data = builder.create_by_name(template_name)

	_apply_template_overrides(template_data, scenario)
	return template_data


func _is_supported_template(builder, template_name: String) -> bool:
	for preset in builder.get_preset_definitions():
		if String(preset.get("id", "")) == template_name:
			return true
	return false


func _apply_template_overrides(template_data: Dictionary, scenario: Dictionary) -> void:
	if scenario.has("hvac_mode"):
		template_data["hvac_mode"] = String(scenario.get("hvac_mode", "none"))
	if scenario.has("hvac_data") and typeof(scenario.get("hvac_data", {})) == TYPE_DICTIONARY:
		template_data["hvac_data"] = Dictionary(scenario.get("hvac_data", {})).duplicate(true)

	_apply_room_overrides(template_data, scenario.get("room_overrides", []))
	_apply_opening_overrides(template_data, scenario.get("opening_overrides", []))

	if typeof(scenario.get("building_params", {})) == TYPE_DICTIONARY:
		for key in Dictionary(scenario.get("building_params", {})).keys():
			template_data[key] = Dictionary(scenario.get("building_params", {}))[key]

	for key in [
		"victims",
		"detectors",
		"player_start",
		"exterior_walls",
		"interior_lights_on",
		"exterior_lighting_mode",
		"building_type",
		"apartment_floor_number",
		"outside_temp_c",
		"outside_o2",
		"wind_speed_m_s",
		"wind_direction_deg",
		"ignition_room_id",
		"stop_time_s"
	]:
		if scenario.has(key):
			template_data[key] = scenario[key]


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
				if key != "id":
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
			if int(opening_data.get("a", -1)) != a_id or int(opening_data.get("b", -1)) != b_id:
				continue
			if type_name != "" and String(opening_data.get("type", "")) != type_name:
				continue
			for key in override_data.keys():
				if key != "a" and key != "b" and key != "type":
					opening_data[key] = override_data[key]
			break


func _apply_engine_overrides(engine: SimulationEngine, raw_overrides: Variant) -> void:
	if typeof(raw_overrides) != TYPE_DICTIONARY:
		return
	var overrides: Dictionary = raw_overrides
	for key in overrides.keys():
		engine.set(String(key), overrides[key])


func _load_targets(engine: SimulationEngine, raw_targets: Variant) -> void:
	if typeof(raw_targets) != TYPE_ARRAY:
		return
	for target_data in raw_targets:
		if typeof(target_data) != TYPE_DICTIONARY:
			continue
		var data: Dictionary = target_data
		var target = TargetModelScript.new()
		target.id = String(data.get("id", "target_%d" % engine.get_targets().size()))
		target.room_id = int(data.get("room_id", 0))
		target.height_m = float(data.get("height_m", 1.0))
		target.area_m2 = float(data.get("area_m2", 0.25))
		target.emissivity = float(data.get("emissivity", 0.9))
		target.angle_factor = float(data.get("angle_factor", 0.5))
		engine.add_target(target)


func _resolve_duration_s(scenario: Dictionary, building: BuildingModel) -> float:
	if _cli_args.has("duration_s"):
		return maxf(0.001, float(_cli_args.get("duration_s", 0.0)))
	if scenario.has("duration_s"):
		return maxf(0.001, float(scenario.get("duration_s", 600.0)))
	if building != null and building.sim_stop_time_s > 0.0:
		return building.sim_stop_time_s
	return 600.0


func _resolve_step_s(scenario: Dictionary) -> float:
	if _cli_args.has("step_s"):
		return maxf(0.001, float(_cli_args.get("step_s", 0.0)))
	if scenario.has("run_step_s"):
		return maxf(0.001, float(scenario.get("run_step_s", 1.0 / 12.0)))
	if scenario.has("validation_step_s"):
		return maxf(0.001, float(scenario.get("validation_step_s", 1.0 / 12.0)))
	if scenario.has("simulation_step_s"):
		return maxf(0.001, float(scenario.get("simulation_step_s", 1.0 / 12.0)))
	return 1.0 / 12.0


func _prepare_opening_events(raw_events: Variant) -> Array:
	var result: Array = []
	if typeof(raw_events) != TYPE_ARRAY:
		return result
	for raw_event in raw_events:
		if typeof(raw_event) != TYPE_DICTIONARY:
			continue
		var event_data: Dictionary = Dictionary(raw_event).duplicate(true)
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
		var event_data: Dictionary = Dictionary(raw_event).duplicate(true)
		var room_id: int = int(event_data.get("room_id", event_data.get("room", 0)))
		event_data["time_s"] = float(event_data.get("time_s", 0.0))
		event_data["room_id"] = room_id
		event_data["duration_s"] = float(event_data.get("duration_s", 10.0))
		event_data["flow_lpm"] = float(event_data.get("flow_lpm", 570.0))
		event_data["effectiveness"] = float(event_data.get("effectiveness", 0.75))
		event_data["applied"] = false
		result.append(event_data)
	return result


func _run_loop(
	engine: SimulationEngine,
	building: BuildingModel,
	duration_s: float,
	step_s: float,
	opening_events: Array,
	suppression_events: Array
) -> bool:
	var max_iterations: int = int(ceil(duration_s / step_s)) + 1000
	var stagnant_steps: int = 0
	for _iteration in range(max_iterations):
		var state: Dictionary = engine.get_state()
		if state.is_empty():
			_abort("run_scenario_headless: engine returned an empty state")
			return false

		var sim_time_s: float = float(state.get("sim_time_s", 0.0))
		_apply_due_opening_events(building, opening_events, sim_time_s)
		_apply_due_suppression_events(engine, suppression_events, sim_time_s)
		if sim_time_s >= duration_s:
			return true

		var previous_time_s: float = sim_time_s
		engine.step(step_s / maxf(0.001, engine.time_scale))
		state = engine.get_state()
		if state.is_empty():
			_abort("run_scenario_headless: engine returned an empty state after step")
			return false

		sim_time_s = float(state.get("sim_time_s", 0.0))
		_append_projection_trace(state, sim_time_s)
		if sim_time_s <= previous_time_s + 0.000001:
			stagnant_steps += 1
			if stagnant_steps >= 10:
				_abort("run_scenario_headless: simulation time is not advancing")
				return false
		else:
			stagnant_steps = 0
		if sim_time_s >= duration_s:
			return true

	_abort("run_scenario_headless: internal iteration limit reached")
	return false


func _open_projection_trace() -> bool:
	if not _projection_trace_enabled:
		return true
	_projection_trace_path = _out_dir.path_join("projection_trace.jsonl")
	_projection_trace_file = FileAccess.open(_projection_trace_path, FileAccess.WRITE)
	if _projection_trace_file == null:
		_abort("run_scenario_headless: could not open projection_trace.jsonl")
		return false
	return true


func _append_projection_trace(state: Dictionary, sim_time_s: float) -> void:
	if not _projection_trace_enabled or _projection_trace_file == null:
		return
	var raw_trace: Variant = state.get("phase3_projection_trace", [])
	if typeof(raw_trace) != TYPE_ARRAY:
		return
	for raw_event in raw_trace:
		if typeof(raw_event) != TYPE_DICTIONARY:
			continue
		var event: Dictionary = Dictionary(raw_event).duplicate(true)
		event["sim_time_s"] = sim_time_s
		_projection_trace_file.store_line(JSON.stringify(event))


func _close_projection_trace() -> void:
	if _projection_trace_file != null:
		_projection_trace_file.flush()
		_projection_trace_file.close()
	_projection_trace_file = null


func _apply_due_opening_events(building: BuildingModel, opening_events: Array, sim_time_s: float) -> void:
	for index in range(opening_events.size()):
		var event_data: Dictionary = opening_events[index]
		if bool(event_data.get("applied", false)) or sim_time_s < float(event_data.get("time_s", 0.0)):
			continue
		var opening_index: int = _resolve_opening_event_index(building, event_data)
		if opening_index >= 0:
			var open_fraction: float = _resolve_opening_event_fraction(event_data)
			building.set_opening_fraction(opening_index, open_fraction)
		else:
			push_warning("run_scenario_headless: opening event could not be resolved: %s" % JSON.stringify(event_data))
		event_data["applied"] = true
		opening_events[index] = event_data


func _apply_due_suppression_events(engine: SimulationEngine, suppression_events: Array, sim_time_s: float) -> void:
	for index in range(suppression_events.size()):
		var event_data: Dictionary = suppression_events[index]
		if bool(event_data.get("applied", false)) or sim_time_s < float(event_data.get("time_s", 0.0)):
			continue
		engine.apply_suppression(
			int(event_data.get("room_id", 0)),
			maxf(0.0, float(event_data.get("duration_s", 10.0))),
			maxf(0.0, float(event_data.get("flow_lpm", 570.0))),
			clampf(float(event_data.get("effectiveness", 0.75)), 0.0, 1.0)
		)
		event_data["applied"] = true
		suppression_events[index] = event_data


func _resolve_opening_event_index(building: BuildingModel, event_data: Dictionary) -> int:
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
		if match_type != "" and _opening_type_name(op) != match_type:
			continue
		return opening_index
	return -1


func _opening_type_name(op: OpeningModel) -> String:
	if op.type == OpeningModel.Type.WINDOW:
		return "window"
	if op.type == OpeningModel.Type.HOLE:
		return "hole"
	return "door"


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


func _write_manifest(engine: SimulationEngine, duration_s: float, step_s: float, ignite_on_start: bool) -> bool:
	var manifest: Dictionary = {
		"schema_version": "simufire_run_scenario_manifest_v1",
		"scenario_path": _scenario_path,
		"output_dir": _out_dir,
		"duration_s": duration_s,
		"step_s": step_s,
		"ignite_on_start": ignite_on_start,
		"sim_time_s": engine.sim_time_s,
		"summary_path": _out_dir.path_join("summary.json"),
		"events_path": _out_dir.path_join("events.json"),
		"log_path": engine.log_writer.resolve_log_file_path(),
		"csv_path": engine.log_writer.resolve_csv_file_path()
	}
	if _projection_trace_enabled:
		manifest["projection_trace_path"] = _projection_trace_path
	var file := FileAccess.open(_out_dir.path_join("run_manifest.json"), FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(manifest, "\t"))
	file.close()
	return true


func _validate_outputs() -> bool:
	for filename in ["summary.json", "events.json", "sim_log.txt", "sim_log.csv", "run_manifest.json"]:
		var path: String = _out_dir.path_join(filename)
		if not FileAccess.file_exists(path):
			_abort("run_scenario_headless: expected output was not written: %s" % path)
			return false
	var summary: Dictionary = _load_json(_out_dir.path_join("summary.json"))
	if String(summary.get("schema_version", "")) != "simufire_technical_summary_v1":
		_abort("run_scenario_headless: summary.json schema mismatch")
		return false
	if _projection_trace_enabled and not FileAccess.file_exists(_projection_trace_path):
		_abort("run_scenario_headless: expected projection trace was not written")
		return false
	return true


func _abort(message: String) -> void:
	if _failed:
		return
	_failed = true
	push_error(message)
	get_tree().quit(1)

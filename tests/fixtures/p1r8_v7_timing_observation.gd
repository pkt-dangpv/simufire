extends SceneTree

const BuildingModelScript = preload("res://sim/BuildingModel.gd")
const SimulationEngineScript = preload("res://sim/core/SimulationEngine.gd")
const CaseRunnerScript = preload("res://sim/validation/CaseRunner.gd")

var _failed: bool = false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var output_path: String = _argument("--p1r8-v7-output=")
	if output_path.is_empty():
		_fail("explicit output path is required")
		return
	var case_file := FileAccess.open(
		"res://sim/validation/cases/v7_underventilated_co_peak.json",
		FileAccess.READ
	)
	if case_file == null:
		_fail("V7 case cannot be opened")
		return
	var parsed = JSON.parse_string(case_file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		_fail("V7 case is not a dictionary")
		return
	var case_config: Dictionary = parsed

	var building = BuildingModelScript.new()
	root.add_child(building)
	var runner = CaseRunnerScript.new()
	root.add_child(runner)
	runner.building = building
	runner._case_config = case_config.duplicate(true)
	var template_data: Dictionary = runner._build_case_template(runner._case_config)
	if template_data.is_empty() or not building.load_template_data(template_data):
		_fail("V7 template cannot be loaded")
		return

	var engine = SimulationEngineScript.new()
	engine.building = building
	root.add_child(engine)
	runner.engine = engine
	runner._cli_args = {}
	for key in ["validation_fire_o2_mode", "validation_engine_mode"]:
		if case_config.has(key):
			runner._cli_args[key] = String(case_config[key])
	runner._apply_engine_overrides(Dictionary(case_config.get("engine_overrides", {})))
	if not runner._configure_validation_two_zone_v1_profile():
		_fail("two-zone profile configuration failed")
		return
	if not runner._configure_validation_engine_mode():
		_fail("engine-mode configuration failed")
		return
	if not runner._configure_validation_fire_o2_mode():
		_fail("O2-mode configuration failed")
		return
	runner._configure_validation_two_zone_opening_flow()
	runner._configure_validation_canonical_pressure()
	engine.auto_finish_on_extinction = false
	engine.enable_logging = false
	engine.ignition_room_id = int(case_config.get("ignition_room_id", engine.ignition_room_id))
	engine.reset_simulation(engine.ignition_room_id, bool(case_config.get("ignite_on_start", true)))
	if not engine.is_ready_for_validation():
		_fail("engine is not ready after reset")
		return

	var duration_s: float = float(case_config.get("duration_s", 0.0))
	var step_s: float = maxf(0.001, float(case_config.get("validation_step_s", 1.0 / 12.0)))
	var crossings: Dictionary = {
		"time_room_0_o2_below_18pct_s": null,
		"time_room_0_o2_below_15pct_s": null,
		"time_room_0_co_upper_above_5000_s": null,
	}
	var previous_time: float = -1.0
	var samples: int = 0
	var state: Dictionary = engine.get_state()
	var max_iterations: int = int(ceil(duration_s / step_s)) + 1000
	for _iteration in range(max_iterations):
		if state.is_empty():
			_fail("engine returned an empty state")
			return
		var sim_time: float = float(state.get("sim_time_s", -1.0))
		if sim_time <= previous_time:
			_fail("non-monotonic simulation time")
			return
		previous_time = sim_time
		var room: Dictionary = Dictionary(state.get("0", {}))
		if room.is_empty():
			_fail("room 0 is missing")
			return
		var o2: float = float(room.get("o2", NAN))
		var co_upper: float = float(room.get("co_upper_ppm", NAN))
		if not is_finite(o2) or not is_finite(co_upper):
			_fail("non-finite species value")
			return
		if crossings["time_room_0_o2_below_18pct_s"] == null and o2 <= 0.18:
			crossings["time_room_0_o2_below_18pct_s"] = sim_time
		if crossings["time_room_0_o2_below_15pct_s"] == null and o2 <= 0.15:
			crossings["time_room_0_o2_below_15pct_s"] = sim_time
		if crossings["time_room_0_co_upper_above_5000_s"] == null and co_upper >= 5000.0:
			crossings["time_room_0_co_upper_above_5000_s"] = sim_time
		samples += 1
		if sim_time >= duration_s:
			break
		engine.step(step_s / maxf(0.001, engine.time_scale))
		state = engine.get_state()

	if float(state.get("sim_time_s", -1.0)) < duration_s:
		_fail("case did not reach declared duration")
		return
	var summary: Dictionary = engine.build_technical_summary("")
	var rooms: Array = Array(summary.get("rooms", []))
	if rooms.is_empty():
		_fail("technical summary has no rooms")
		return
	var room_summary: Dictionary = Dictionary(rooms[0])
	var result: Dictionary = {
		"case": "v7_underventilated_co_peak",
		"samples": samples,
		"final_sim_time_s": state["sim_time_s"],
		"threshold_crossings_s": crossings,
		"peak_hrr_kw": room_summary.get("peak_hrr_kw"),
		"peak_hrr_time_s": room_summary.get("peak_hrr_time_s"),
		"peak_co_upper_ppm": room_summary.get("peak_co_upper_ppm"),
		"peak_co_time_s": room_summary.get("peak_co_time_s"),
		"min_o2_fraction": room_summary.get("min_o2_fraction"),
		"min_o2_time_s": room_summary.get("min_o2_time_s"),
		"fire_o2_mode": engine.fire_o2_mode,
		"two_zone_solver_enabled": engine.two_zone_solver_enabled,
		"two_zone_opening_flow_enabled": engine.two_zone_opening_flow_enabled,
	}
	var output := FileAccess.open(output_path, FileAccess.WRITE)
	if output == null:
		_fail("output cannot be opened")
		return
	output.store_string(JSON.stringify(result, "  "))
	output.close()
	_finish()


func _argument(prefix: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if String(arg).begins_with(prefix):
			return String(arg).trim_prefix(prefix)
	return ""


func _fail(message: String) -> void:
	push_error("P1R8 V7 timing observation: " + message)
	_failed = true
	call_deferred("_finish")


func _finish() -> void:
	if _failed:
		quit(1)
		return
	print("P1R8_V7_TIMING_OBSERVATION_PASS")
	quit(0)

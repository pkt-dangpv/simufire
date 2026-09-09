extends SceneTree

const BuildingModelScript = preload("res://sim/BuildingModel.gd")
const SimulationEngineScript = preload("res://sim/core/SimulationEngine.gd")
const CaseRunnerScript = preload("res://sim/validation/CaseRunner.gd")
const Observer = preload("res://tests/fixtures/p1r8_post_extinction_observer.gd")

var _failed: bool = false
func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var output_path: String = _argument("--p1r8-observation-output=")
	var trace_path: String = _argument("--p1r8-observation-trace=")
	if output_path.is_empty() or trace_path.is_empty():
		_fail("explicit output and trace paths are required")
		quit(1)
		return

	var case_path := "res://sim/validation/cases/postfire_decay.json"
	var case_file := FileAccess.open(case_path, FileAccess.READ)
	if case_file == null:
		_fail("postfire case cannot be opened")
		quit(1)
		return
	var parsed = JSON.parse_string(case_file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		_fail("postfire case is not a dictionary")
		quit(1)
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
		_fail("postfire template cannot be loaded")
		quit(1)
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
		quit(1)
		return
	if not runner._configure_validation_engine_mode():
		_fail("engine-mode configuration failed")
		quit(1)
		return
	if not runner._configure_validation_fire_o2_mode():
		_fail("O2-mode configuration failed")
		quit(1)
		return
	runner._configure_validation_two_zone_opening_flow()
	runner._configure_validation_canonical_pressure()
	engine.auto_finish_on_extinction = false
	engine.enable_logging = false
	engine.ignition_room_id = int(case_config.get("ignition_room_id", engine.ignition_room_id))
	engine.reset_simulation(engine.ignition_room_id, bool(case_config.get("ignite_on_start", true)))
	if not engine.is_ready_for_validation():
		_fail("engine is not ready after reset")
		quit(1)
		return

	var room_ids: Array[int] = []
	for room_id in building.get_rooms().keys():
		room_ids.append(int(room_id))
	room_ids.sort()
	var observer = Observer.new(room_ids)
	var trace := FileAccess.open(trace_path, FileAccess.WRITE)
	if trace == null:
		_fail("trace output cannot be opened")
		quit(1)
		return

	var duration_s: float = float(case_config.get("duration_s", 0.0))
	var validation_step_s: float = maxf(0.001, float(case_config.get("validation_step_s", 1.0 / 12.0)))
	var tick: int = 0
	var state: Dictionary = engine.get_state()
	if not _observe(observer, trace, state, tick, room_ids):
		_fail("initial observation rejected")
		trace.close()
		quit(1)
		return
	var max_iterations: int = int(ceil(duration_s / validation_step_s)) + 1000
	for _iteration in range(max_iterations):
		if float(state["sim_time_s"]) >= duration_s:
			break
		engine.step(validation_step_s / maxf(0.001, engine.time_scale))
		state = engine.get_state()
		tick += 1
		if state.is_empty() or not _observe(observer, trace, state, tick, room_ids):
			_fail("runtime observation rejected at tick %d" % tick)
			break
	trace.close()
	if _failed:
		quit(1)
		return
	if float(state["sim_time_s"]) < duration_s:
		_fail("case did not reach declared duration")
		quit(1)
		return
	var result: Dictionary = observer.finalize(tick, float(state["sim_time_s"]))
	result["case"] = "postfire_decay"
	result["declared_duration_s"] = duration_s
	result["room_ids"] = room_ids
	result["final_tick"] = tick
	result["final_sim_time_s"] = float(state["sim_time_s"])
	var output := FileAccess.open(output_path, FileAccess.WRITE)
	if output == null:
		_fail("observation result cannot be opened")
		quit(1)
		return
	output.store_string(JSON.stringify(result, "  "))
	output.close()
	if not bool(result.get("valid", false)):
		_fail("observer finalized invalid: %s" % String(result.get("reason", "UNKNOWN")))
		quit(1)
		return
	print("P1R8_POSTFIRE_OBSERVATION_PASS")
	quit(0)


func _observe(observer, trace: FileAccess, state: Dictionary, tick: int, room_ids: Array[int]) -> bool:
	var sample: Dictionary = state.duplicate(true)
	sample["tick_index"] = tick
	if not observer.observe(sample):
		return false
	var record: Dictionary = {
		"tick_index": tick,
		"sim_time_s": sample["sim_time_s"],
		"smoke_generated_total_kg": sample["smoke_generated_total_kg"],
		"smoke_vented_total_kg": sample["smoke_vented_total_kg"],
		"smoke_deposited_total_kg": sample["smoke_deposited_total_kg"],
		"smoke_in_transit_kg": sample["smoke_in_transit_kg"],
		"rooms": {},
	}
	for room_id in room_ids:
		var room: Dictionary = sample[str(room_id)]
		record["rooms"][str(room_id)] = {
			"has_fire": room["has_fire"],
			"hrr_kw": room["hrr_kw"],
			"temp_upper_c": room["temp_upper_c"],
			"smoke_kg": room["smoke_kg"],
		}
	trace.store_line(JSON.stringify(record))
	return true


func _argument(prefix: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if String(arg).begins_with(prefix):
			return String(arg).trim_prefix(prefix)
	return ""


func _fail(message: String) -> void:
	_failed = true
	push_error("P1R8 postfire observation: " + message)

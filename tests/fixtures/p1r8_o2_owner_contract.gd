extends SceneTree

const BuildingModelScript = preload("res://sim/BuildingModel.gd")
const SimulationEngineScript = preload("res://sim/core/SimulationEngine.gd")
const CaseRunnerScript = preload("res://sim/validation/CaseRunner.gd")

const MIN_OBSERVED_HRR_KW: float = 50.0
const EPS_KG: float = 1.0e-12


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var output_path: String = _argument("--p1r8-o2-owner-output=")
	if output_path.is_empty():
		_fail("explicit output path is required")
		return
	var results: Array[Dictionary] = []
	results.append(_observe_case("layer150_tenability", "open_interior"))
	results.append(_observe_case("v7_underventilated_co_peak", "sealed"))
	for result in results:
		if result.is_empty() or not bool(result.get("observation_complete", false)):
			_write_result(output_path, results, false)
			_fail("a branch did not produce a complete observation")
			return
	var by_branch: Dictionary = {}
	for result in results:
		var selected_owner: String = String(result["selected_owner"])
		var debited_owner: String = String(result["debited_owner"])
		result["owner_match"] = selected_owner == debited_owner
		by_branch[String(result["branch"])] = result
	var open_result: Dictionary = by_branch.get("open_interior", {})
	var sealed_result: Dictionary = by_branch.get("sealed", {})
	var passed: bool = (
		String(open_result.get("selected_owner", "")) == "lower"
		and String(open_result.get("debited_owner", "")) == "bulk"
		and not bool(open_result.get("owner_match", true))
		and String(sealed_result.get("selected_owner", "")) == "lower"
		and String(sealed_result.get("debited_owner", "")) == "lower"
		and bool(sealed_result.get("owner_match", false))
	)
	_write_result(output_path, results, passed)
	if not passed:
		push_error("O2-OWNER-001 limitation was not reproduced exactly")
		quit(1)
		return
	print("P1R8_O2_OWNER_LIMITATION_CONFIRMED")
	quit(0)


func _observe_case(case_name: String, branch: String) -> Dictionary:
	var case_path := "res://sim/validation/cases/%s.json" % case_name
	var case_file := FileAccess.open(case_path, FileAccess.READ)
	if case_file == null:
		return {"branch": branch, "error": "case cannot be opened"}
	var parsed = JSON.parse_string(case_file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"branch": branch, "error": "case is not a dictionary"}
	var case_config: Dictionary = parsed

	var building = BuildingModelScript.new()
	root.add_child(building)
	var runner = CaseRunnerScript.new()
	root.add_child(runner)
	runner.building = building
	runner._case_config = case_config.duplicate(true)
	var template_data: Dictionary = runner._build_case_template(runner._case_config)
	if template_data.is_empty() or not building.load_template_data(template_data):
		_destroy(runner, null, building)
		return {"branch": branch, "error": "template cannot be loaded"}

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
		_destroy(runner, engine, building)
		return {"branch": branch, "error": "two-zone profile failed"}
	if not runner._configure_validation_engine_mode():
		_destroy(runner, engine, building)
		return {"branch": branch, "error": "engine mode failed"}
	if not runner._configure_validation_fire_o2_mode():
		_destroy(runner, engine, building)
		return {"branch": branch, "error": "O2 mode failed"}
	runner._configure_validation_two_zone_opening_flow()
	runner._configure_validation_canonical_pressure()
	engine.auto_finish_on_extinction = false
	engine.enable_logging = false
	engine.ignition_room_id = int(case_config.get("ignition_room_id", 0))
	engine.reset_simulation(engine.ignition_room_id, bool(case_config.get("ignite_on_start", true)))
	if not engine.is_ready_for_validation():
		_destroy(runner, engine, building)
		return {"branch": branch, "error": "engine is not ready"}
	if engine.fire_o2_canonical_enabled or engine.fire_o2_upper_throttle_enabled:
		_destroy(runner, engine, building)
		return {"branch": branch, "error": "forbidden default-OFF authority flag is active"}

	var step_s: float = maxf(0.001, float(case_config.get("validation_step_s", 1.0 / 12.0)))
	var room = building.get_room(engine.ignition_room_id)
	var observation: Dictionary = {}
	for _iteration in range(6000):
		var before: Dictionary = {
			"o2": room.o2,
			"o2_upper": room.o2_upper,
			"o2_lower": room.o2_lower,
		}
		engine.step(step_s / maxf(0.001, engine.time_scale))
		if room.hrr_kw < MIN_OBSERVED_HRR_KW or room.o2_consumed_fire_kg_step <= EPS_KG:
			continue
		var mode: String = room.fire_o2_mode_used
		var selected_owner: String = _selected_owner(mode)
		var debited_owner: String = _debited_owner(room, mode)
		observation = {
			"branch": branch,
			"case": case_name,
			"observation_complete": true,
			"sim_time_s": engine.sim_time_s,
			"hrr_kw": room.hrr_kw,
			"fire_o2_mode_requested": engine.fire_o2_mode,
			"fire_o2_mode_used": mode,
			"fire_o2_ref": room.fire_o2_ref,
			"selected_owner": selected_owner,
			"debited_owner": debited_owner,
			"o2_before": before,
			"o2_after": {
				"o2": room.o2,
				"o2_upper": room.o2_upper,
				"o2_lower": room.o2_lower,
			},
			"o2_consumed_bulk_kg_step": room.o2_consumed_bulk_kg_step,
			"o2_consumed_fire_kg_step": room.o2_consumed_fire_kg_step,
			"fire_o2_canonical_enabled": engine.fire_o2_canonical_enabled,
			"fire_o2_upper_throttle_enabled": engine.fire_o2_upper_throttle_enabled,
			"two_zone_solver_enabled": engine.two_zone_solver_enabled,
		}
		break
	_destroy(runner, engine, building)
	if observation.is_empty():
		return {"branch": branch, "case": case_name, "error": "no meaningful combustion debit observed"}
	return observation


func _selected_owner(mode: String) -> String:
	if mode == "plume_lower" or mode == "plume_blend" or mode == "lower":
		return "lower"
	if mode == "upper" or mode == "plume_upper":
		return "upper"
	return "bulk"


func _debited_owner(room, mode: String) -> String:
	if room.o2_consumed_bulk_kg_step > EPS_KG:
		return "bulk"
	if room.o2_consumed_fire_kg_step > EPS_KG:
		if mode == "upper" or mode == "plume_upper":
			return "upper"
		return "lower"
	return "none"


func _write_result(path: String, results: Array[Dictionary], passed: bool) -> void:
	var output := FileAccess.open(path, FileAccess.WRITE)
	if output == null:
		push_error("O2-OWNER-001: output cannot be opened")
		return
	output.store_string(JSON.stringify({"passed": passed, "branches": results}, "  "))
	output.close()


func _destroy(runner, engine, building) -> void:
	if runner != null:
		runner.free()
	if engine != null:
		engine.free()
	if building != null:
		building.free()


func _argument(prefix: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if String(arg).begins_with(prefix):
			return String(arg).trim_prefix(prefix)
	return ""


func _fail(message: String) -> void:
	push_error("O2-OWNER-001 fixture: " + message)
	quit(1)

extends SceneTree

## DIAGNOSIS, not acceptance. Records what the engine really writes to its oxygen
## numbers around the thermal coupling bench of the prescribed HRR source: every
## sink of a step with what it asked for, what it applied and what the state shows
## afterwards, on the mass base each one uses. It judges nothing: the runner
## evaluates hypotheses written down before this ran.
##
## It reads the probe the engine already has for the G3 ledger (read only) and the
## room state. It adds no physics and changes no engine file. The isolated source is
## reached through the bench, its only consumer, and is never named here.
const BuildingModelScript = preload("res://sim/BuildingModel.gd")
const EngineScript = preload("res://sim/core/SimulationEngine.gd")
const CouplingScript = preload("res://sim/fire/PrescribedThermalSourceCoupling.gd")
const SOURCE_FIXTURE: String = "res://tests/fixtures/g3_object_hrr_source_test016.json"
const ROOM_ID: int = 0
const LARGE_OPEN: Dictionary = {"width": 20.0, "length": 20.0, "height": 5.0, "opening": [2.0, 2.5]}
const SMALL_SEALED: Dictionary = {"width": 6.0, "length": 4.0, "height": 2.5, "opening": []}
const SMALL_CRACK: Dictionary = {"width": 6.0, "length": 4.0, "height": 2.5, "opening": [0.2, 0.2]}

var _failed: bool = false
var _notes: Array[String] = []
var _source: Dictionary = {}
var _identity: String = ""
var _out: Dictionary = {}


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var file: Variant = JSON.parse_string(FileAccess.get_file_as_string(SOURCE_FIXTURE))
	if typeof(file) != TYPE_DICTIONARY:
		_failed = true
		_notes.append("the source fixture is not readable")
	else:
		_source = file["source"]
		_identity = String(file["expected_identity"])
		_no_source_against_zero_energy()
		_open_room("open_dt_2.5", 2.5, false)
		_open_room("open_dt_1.0", 1.0, false)
		_open_room("open_dt_2.5_other_upper_branch", 2.5, true)
		_rejected_against_no_source("sealed_dt_2.5", SMALL_SEALED, 2.5, 40)
		_rejected_against_no_source("sealed_dt_1.0", SMALL_SEALED, 1.0, 40)
		_crack_and_recovery()
	print("G3_OBJECT_HRR_OXYGEN_DIAGNOSIS " + JSON.stringify({"notes": _notes, "cases": _out}, "", true, true))
	if _failed:
		quit(1)
	else:
		print("G3_OBJECT_HRR_OXYGEN_DIAGNOSIS_DONE")
		quit(0)


# ---------------------------------------------------------------- cases

## A bench with a table of zeros against an engine with the switch off: if the only
## channel of the source is the room power, every oxygen number is the same bit by bit.
func _no_source_against_zero_energy() -> void:
	var dt: float = 2.5
	var off: Dictionary = _bench(LARGE_OPEN, dt, {})
	var zeros: Dictionary = _synthetic([[0.0, 0.0], [600.0, 0.0]])
	var opened: RefCounted = CouplingScript.SourceScript.new()
	opened.open(zeros)
	var on: Dictionary = _bench(LARGE_OPEN, dt, _case(0.35, zeros, String(opened.report().get("source_fingerprint"))))
	var differing: int = 0
	var first: Dictionary = {}
	for index: int in range(120):
		var a: Dictionary = _step(off, dt)
		var b: Dictionary = _step(on, dt)
		for key: String in ["o2", "o2_upper", "o2_lower", "temp_upper_c", "temp_lower_c", "consumed_all_step_kg"]:
			if a[key] != b[key]:
				differing += 1
				if first.is_empty():
					first = {"step": index, "key": key, "switch_off": a[key], "zero_energy": b[key]}
	_out["no_source_against_zero_energy"] = {
		"dt_s": dt, "steps": 120, "numbers_compared_per_step": 6, "differing": differing, "first_difference": first,
		"zero_energy_state": on["engine"].get_g3_prescribed_thermal_source_report().get("state"),
		"zero_energy_accepted_kj": on["engine"].get_g3_prescribed_thermal_source_report().get("totals", {}).get("accepted_kj"),
		"final_o2": on["room"].o2, "final_o2_upper": on["room"].o2_upper, "final_o2_lower": on["room"].o2_lower,
	}
	_free(off)
	_free(on)


## The whole run in the open room. `other_branch` sets, in the oxygen system only, the
## two-zone flag the engine never hands to it: the upper write then takes its other branch.
func _open_room(name: String, dt: float, other_branch: bool) -> void:
	var bench: Dictionary = _bench(LARGE_OPEN, dt, _case(0.35, _source, _identity))
	if other_branch:
		bench["engine"].oxygen_exchange_system.two_zone_solver_enabled = true
	var room = bench["room"]
	var totals: Dictionary = _zero_totals()
	var window: Array = []
	var room_o2: PackedFloat64Array = PackedFloat64Array()
	var power: PackedFloat64Array = PackedFloat64Array()
	var steps: int = int(ceil(3768.0 / dt))
	var keep: Array = [0, 1, 2, int(1143.0 / dt) - 1, int(1143.0 / dt), int(1143.0 / dt) + 1, steps - 1]
	for index: int in range(steps):
		var row: Dictionary = _step(bench, dt)
		_accumulate(totals, row)
		room_o2.append(room.o2)
		power.append(room.hrr_kw)
		if keep.has(index):
			window.append(_compact(index, row))
	var report: Dictionary = bench["engine"].get_g3_prescribed_thermal_source_report()
	_out[name] = {
		"dt_s": dt, "steps": steps, "upper_branch_forced_to_the_other": other_branch,
		"state": report.get("state"), "exit": report.get("exit"),
		"accepted_kj": report.get("totals", {}).get("accepted_kj"),
		"bench_oxygen_debited_kg": report.get("totals", {}).get("oxygen_debited_kg"),
		"bench_second_number_kg": report.get("totals", {}).get("oxygen_zone_displacement_kg", report.get("totals", {}).get("upper_layer_number_written_kg")),
		"totals": totals, "window": window,
		"room_o2_sha256": _digest(room_o2), "power_sha256": _digest(power),
		"final": {"o2": room.o2, "o2_upper": room.o2_upper, "o2_lower": room.o2_lower},
	}
	_free(bench)


## A room where the bench must reject, beside its twin with the switch off. What differs
## between the two after the rejection is what the source left behind.
func _rejected_against_no_source(name: String, spec: Dictionary, dt: float, steps: int) -> void:
	var off: Dictionary = _bench(spec, dt, {})
	var on: Dictionary = _bench(spec, dt, _case(0.35, _source, _identity))
	var rows: Array = []
	var differing_steps: int = 0
	var last_difference: int = -1
	var totals: Dictionary = _zero_totals()
	for index: int in range(steps):
		var a: Dictionary = _step(off, dt)
		var b: Dictionary = _step(on, dt)
		_accumulate(totals, b)
		var gap: Dictionary = {}
		for key: String in ["o2", "o2_upper", "o2_lower"]:
			gap[key] = b[key] - a[key]
		var air_kg: float = b["air_mass_kg"]
		var differs: bool = gap["o2"] != 0.0 or gap["o2_upper"] != 0.0 or gap["o2_lower"] != 0.0
		if differs:
			differing_steps += 1
			last_difference = index
		if index < 4 or index == steps - 1:
			var item: Dictionary = _compact(index, b)
			item["minus_the_twin_without_source"] = gap
			item["room_number_gap_as_kg_on_the_room_base"] = gap["o2"] * air_kg
			item["twin_o2"] = a["o2"]
			item["twin_o2_upper"] = a["o2_upper"]
			item["twin_o2_lower"] = a["o2_lower"]
			rows.append(item)
	var report: Dictionary = on["engine"].get_g3_prescribed_thermal_source_report()
	_out[name] = {
		"dt_s": dt, "steps": steps, "state": report.get("state"), "exit": report.get("exit"),
		"accepted_kj": report.get("totals", {}).get("accepted_kj"),
		"to_the_gas_kj": report.get("totals", {}).get("to_the_gas_kj"),
		"bench_reports_debited_without_heat_kg": report.get("totals", {}).get("oxygen_debited_without_heat_kg"),
		"steps_whose_oxygen_numbers_differ_from_the_twin": differing_steps,
		"last_step_that_differs": last_difference,
		"totals": totals, "rows": rows,
	}
	_free(off)
	_free(on)


func _crack_and_recovery() -> void:
	var dt: float = 2.5
	var bench: Dictionary = _bench(SMALL_CRACK, dt, _case(0.35, _source, _identity))
	var room = bench["room"]
	var coupling = bench["engine"]._g3_prescribed_thermal_source
	var totals_inside: Dictionary = _zero_totals()
	var totals_after: Dictionary = _zero_totals()
	var guard: int = 0
	var exit_row: Dictionary = {}
	while guard < 1508:
		var before: String = coupling.state()
		var row: Dictionary = _step(bench, dt)
		guard += 1
		if coupling.state() != CouplingScript.STATE_REPLAYING and before == CouplingScript.STATE_REPLAYING:
			exit_row = _compact(guard - 1, row)
			_accumulate(totals_after, row)
			break
		_accumulate(totals_inside, row)
	for _i: int in range(60):
		_accumulate(totals_after, _step(bench, dt))
	var report: Dictionary = bench["engine"].get_g3_prescribed_thermal_source_report()
	var before_recovery: Dictionary = {"o2": room.o2, "o2_upper": room.o2_upper, "o2_lower": room.o2_lower}
	room.o2 = float(report["oxygen_at_ignition"]["room"])
	room.o2_lower = float(report["oxygen_at_ignition"]["lower"])
	room.o2_upper = float(report["oxygen_at_ignition"]["upper"])
	var recovered: Dictionary = _zero_totals()
	for _i: int in range(60):
		_accumulate(recovered, _step(bench, dt))
	_out["crack_and_recovery"] = {
		"dt_s": dt, "exit": report.get("exit"), "state_after_recovery": coupling.state(),
		"accepted_kj": report.get("totals", {}).get("accepted_kj"),
		"accepted_kj_after_recovery": bench["engine"].get_g3_prescribed_thermal_source_report().get("totals", {}).get("accepted_kj"),
		"inside_the_regime": totals_inside, "from_the_exit_step_on": totals_after, "after_the_oxygen_was_restored": recovered,
		"exit_step": exit_row, "numbers_before_the_recovery": before_recovery,
	}
	_free(bench)


# ---------------------------------------------------------------- one step and its probe

func _step(bench: Dictionary, dt: float) -> Dictionary:
	var engine = bench["engine"]
	var room = bench["room"]
	var before: Dictionary = {"o2": room.o2, "o2_upper": room.o2_upper, "o2_lower": room.o2_lower}
	engine.step(dt)
	var probe: Dictionary = {}
	for row: Dictionary in engine.combustion_system.g3_drain_fuel_ledger(bench["building"]):
		if int(row.get("room_id", -1)) == ROOM_ID and typeof(row.get("bal_o2")) == TYPE_DICTIONARY:
			probe = row["bal_o2"]
	if probe.is_empty():
		_failed = true
		if _notes.size() < 5:
			_notes.append("a step returned no oxygen probe")
	var sinks: Dictionary = probe.get("sinks", {})
	var air_kg: float = float(probe.get("air_mass_kg", 0.0))
	var upper_frac: float = float(probe.get("upper_frac", 0.0))
	var lower_frac: float = float(probe.get("lower_frac", 0.0))
	return {
		"power_kw": room.hrr_kw, "before": before,
		"o2": room.o2, "o2_upper": room.o2_upper, "o2_lower": room.o2_lower,
		"temp_upper_c": room.temp_upper_c, "temp_lower_c": room.temp_lower_c,
		"air_mass_kg": air_kg, "upper_frac": upper_frac, "lower_frac": lower_frac,
		"upper_air_mass_kg": float(probe.get("upper_air_mass_kg", 0.0)),
		"sinks": sinks, "entrainment": probe.get("entrainment", {}), "lower_ach": probe.get("lower_ach", {}),
		"bulk_ach_kg": float(probe.get("bulk_ach_kg", 0.0)),
		"bulk_fraction_before_write": probe.get("bulk_fraction_before_write"),
		"bulk_fraction_unclamped": probe.get("bulk_fraction_unclamped"),
		"bulk_fraction_after_write": probe.get("bulk_fraction_after_write"),
		"plume_lower_mode": probe.get("plume_lower_mode"), "bi_zone_invalid": probe.get("bi_zone_invalid"),
		"sink_sees_two_zones": probe.get("two_zone_solver_enabled"),
		"fire_primary_kg": float(probe.get("fire_primary_kg", 0.0)),
		"consumed_all_step_kg": float(room.o2_consumed_kg_step_all),
		"consumed_room_inventory_step_kg": float(room.o2_consumed_bulk_kg_step),
		"exterior_net_kg": float(room.o2_exterior_net_kg_step),
		"numbers_after_the_room_loop": {"o2": probe.get("o2_after"), "o2_upper": probe.get("o2_upper_after"), "o2_lower": probe.get("o2_lower_after")},
		"room_number_minus_weighted_layers": room.o2 - (upper_frac * room.o2_upper + lower_frac * room.o2_lower),
		"bench_state": engine.get_g3_prescribed_thermal_source_report().get("state"),
	}


func _zero_totals() -> Dictionary:
	return {
		"steps": 0, "steps_with_power": 0,
		"room_inventory_requested_kg": 0.0, "room_inventory_applied_kg": 0.0, "room_inventory_mass_change_at_the_write_kg": 0.0,
		"room_inventory_steps_capped": 0,
		"upper_number_requested_kg": 0.0, "upper_number_applied_kg": 0.0, "upper_number_state_change_on_its_base_kg": 0.0,
		"upper_number_steps_capped": 0, "upper_number_branches": {},
		"plume_lower_requested_kg": 0.0, "plume_lower_applied_kg": 0.0, "plume_lower_state_change_on_the_room_base_kg": 0.0,
		"accumulator_all_sinks_kg": 0.0, "accumulator_room_inventory_kg": 0.0, "accumulator_primary_kg": 0.0,
		"exterior_net_kg": 0.0, "ach_on_the_room_number_kg": 0.0,
		"lowest_o2": INF, "lowest_o2_upper": INF, "lowest_o2_lower": INF,
		"largest_room_number_minus_weighted_layers": 0.0,
		"lower_number_drained_towards_the_upper_fraction_sum": 0.0,
		"steps_with_plume_lower_route": 0,
	}


func _accumulate(totals: Dictionary, row: Dictionary) -> void:
	totals["steps"] += 1
	if row["power_kw"] > 0.0:
		totals["steps_with_power"] += 1
	var sinks: Dictionary = row["sinks"]
	if sinks.has("bulk"):
		var bulk: Dictionary = sinks["bulk"]
		totals["room_inventory_requested_kg"] += float(bulk.get("requested_kg", 0.0))
		totals["room_inventory_applied_kg"] += float(bulk.get("applied_kg", 0.0))
		totals["room_inventory_mass_change_at_the_write_kg"] += float(bulk.get("mass_before_kg", 0.0)) - float(bulk.get("mass_after_kg", 0.0))
		if float(bulk.get("requested_kg", 0.0)) > float(bulk.get("cap_kg", INF)):
			totals["room_inventory_steps_capped"] += 1
	if sinks.has("upper"):
		var upper: Dictionary = sinks["upper"]
		var branch: String = String(upper.get("branch", "none"))
		totals["upper_number_branches"][branch] = int(totals["upper_number_branches"].get(branch, 0)) + 1
		totals["upper_number_requested_kg"] += float(upper.get("requested_kg", 0.0))
		totals["upper_number_applied_kg"] += float(upper.get("applied_kg", 0.0))
		totals["upper_number_state_change_on_its_base_kg"] += (float(upper.get("fraction_before", 0.0)) - float(upper.get("fraction_after", 0.0))) \
				* float(upper.get("mass_base_kg", 0.0))
		if float(upper.get("requested_kg", 0.0)) > float(upper.get("cap_kg", INF)):
			totals["upper_number_steps_capped"] += 1
	if sinks.has("plume_lower"):
		var plume: Dictionary = sinks["plume_lower"]
		totals["plume_lower_requested_kg"] += float(plume.get("requested_kg", 0.0))
		totals["plume_lower_applied_kg"] += float(plume.get("applied_kg", 0.0))
		totals["plume_lower_state_change_on_the_room_base_kg"] += (float(plume.get("fraction_before", 0.0)) - float(plume.get("fraction_after", 0.0))) \
				* float(plume.get("mass_base_kg", 0.0))
	if row["plume_lower_mode"] == true:
		totals["steps_with_plume_lower_route"] += 1
	totals["accumulator_all_sinks_kg"] += row["consumed_all_step_kg"]
	totals["accumulator_room_inventory_kg"] += row["consumed_room_inventory_step_kg"]
	totals["accumulator_primary_kg"] += row["fire_primary_kg"]
	totals["exterior_net_kg"] += row["exterior_net_kg"]
	totals["ach_on_the_room_number_kg"] += row["bulk_ach_kg"]
	totals["lowest_o2"] = minf(totals["lowest_o2"], row["o2"])
	totals["lowest_o2_upper"] = minf(totals["lowest_o2_upper"], row["o2_upper"])
	totals["lowest_o2_lower"] = minf(totals["lowest_o2_lower"], row["o2_lower"])
	if absf(row["room_number_minus_weighted_layers"]) > absf(totals["largest_room_number_minus_weighted_layers"]):
		totals["largest_room_number_minus_weighted_layers"] = row["room_number_minus_weighted_layers"]
	totals["lower_number_drained_towards_the_upper_fraction_sum"] -= float(row["entrainment"].get("lower_delta_fraction", 0.0))


func _compact(index: int, row: Dictionary) -> Dictionary:
	var out: Dictionary = row.duplicate(true)
	out["step"] = index
	return out


func _digest(values: PackedFloat64Array) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(values.to_byte_array())
	return context.finish().hex_encode()


# ---------------------------------------------------------------- bench

func _bench(spec: Dictionary, dt: float, case: Dictionary) -> Dictionary:
	var building = BuildingModelScript.new()
	root.add_child(building)
	var rect := Rect2(0.0, 0.0, float(spec["width"]), float(spec["length"]))
	var openings: Array[Dictionary] = []
	var size: Array = spec["opening"]
	if size.size() == 2:
		openings.append({"a": ROOM_ID, "b": -1, "type": "door", "width_m": float(size[0]), "height_m": float(size[1]),
			"open_fraction": 1.0, "offset_m": 0.5, "offset_is_fraction": true, "sill_m": 0.0, "wall": "bottom"})
	var rooms: Array[Dictionary] = [{"id": ROOM_ID, "name": "Banco", "kind": "salon", "rect": rect,
		"height_m": float(spec["height"]), "fuel_energy_MJ": 0.0, "max_hrr_kw": 0.0}]
	building.load_template_data({"room_rect_m": {ROOM_ID: rect}, "rooms_data": rooms, "openings_data": openings})
	var engine = EngineScript.new()
	engine.building = building
	engine.enable_logging = false
	engine.auto_ignite_on_ready = false
	engine.auto_finish_on_extinction = false
	engine.energy_budget_enabled = true
	engine.energy_budget_warn_fraction = 1.0e9
	engine.sim_fixed_dt = dt
	root.add_child(engine)
	# The read-only probe of the G3 ledger, in every run alike.
	engine.combustion_system.g3_fuel_ledger_enabled = true
	if not case.is_empty():
		engine.g3_prescribed_thermal_source_enabled = true
		engine.g3_prescribed_thermal_source_case = case
	engine.reset_simulation(ROOM_ID, true)
	if not case.is_empty() and engine.g3_prescribed_thermal_source_failure != "":
		_failed = true
		_notes.append("a bench did not arm: " + str(engine.get_g3_prescribed_thermal_source_report().get("failure")))
	return {"engine": engine, "building": building, "room": building.get_room(ROOM_ID)}


func _free(bench: Dictionary) -> void:
	bench["engine"].queue_free()
	bench["building"].queue_free()


func _case(chi: float, source: Dictionary, identity: String) -> Dictionary:
	return {
		"schema": CouplingScript.CASE_SCHEMA, "room_id": ROOM_ID, "source": source,
		"expected_source_fingerprint": identity, "oxygen_kg_per_MJ": 0.076,
		"radiative_fraction": {"value": chi, "class": "assumed", "what": "engine default"},
		"regime": {"oxygen_drop_tolerance": 0.01, "layer_interface_min_m": 0.3, "status": CouplingScript.REGIME_STATUS},
	}


func _synthetic(points: Array) -> Dictionary:
	var samples: Array = []
	for point: Array in points:
		samples.append({"time_s": point[0], "hrr_kw": point[1]})
	var unknown: Dictionary = {}
	for key: String in CouplingScript.SourceScript.UNKNOWN_KEYS:
		unknown[key] = null
	return {
		"schema": CouplingScript.SourceScript.SOURCE_SCHEMA, "owner_id": "synthetic_object_as_tested", "run_id": "synthetic_run_1",
		"quantity": "measured_calorimetric_hrr", "time_unit": "s", "hrr_unit": "kW", "energy_unit": "kJ",
		"time_origin": "documented_ignition_event", "interpolation": "piecewise_linear",
		"outside_support": "reject", "negative_samples": "none_in_source", "regime": "open_air_as_tested",
		"provenance": {
			"dataset": "synthetic analytic table, not a measurement", "dataset_version": "v1",
			"license": "none needed", "source_file": "tests/fixtures/g3_object_hrr_oxygen_writes_diagnosis.gd",
			"source_sha256": "0".repeat(64), "source_column": "hrr_kw", "support_events": "0 to the last node",
			"importer": "written by hand", "table_fingerprint": "1".repeat(64),
		},
		"unknown": unknown, "samples": samples,
	}

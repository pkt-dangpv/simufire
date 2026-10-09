extends SceneTree

## Diagnostic bench of the thermal coupling of the prescribed HRR source, on the
## REAL SimulationEngine. Energy and an equivalent oxygen debit of one room with
## no fuel and no room fire. It validates no temperature, no combustion of the
## furniture, no CO, FED or SVV.
##
## Every expected number comes from the offline oracle or from a closed form;
## what the engine really did is read where it is written: the room power, the
## accumulator of the oxygen sink and the heat ThermalSystem reports.
## A refusal counts only when it is explicit; an aborted call is a failure.
const BuildingModelScript = preload("res://sim/BuildingModel.gd")
const EngineScript = preload("res://sim/core/SimulationEngine.gd")
const CouplingScript = preload("res://sim/fire/PrescribedThermalSourceCoupling.gd")
const SourceScript = preload("res://sim/fire/PrescribedObjectHrrSource.gd")
const FireModelScript = preload("res://sim/fire/FireModel.gd")
const FuelObjectModelScript = preload("res://sim/fire/FuelObjectModel.gd")
const SOURCE_FIXTURE: String = "res://tests/fixtures/g3_object_hrr_source_test016.json"
const ORACLE_FIXTURE: String = "res://tests/fixtures/g3_object_hrr_thermal_coupling_oracle.json"
const ABS_TOL: float = 1.0e-9
const REL_TOL: float = 1.0e-12
const ROOM_ID: int = 0
## Large and open: 2000 m3 with a 5 m2 opening to the outside.
const LARGE_OPEN: Dictionary = {"width": 20.0, "length": 20.0, "height": 5.0, "opening": [2.0, 2.5]}
## 60 m3, with no opening at all, and with a crack of 0.04 m2 to the outside.
const SMALL_SEALED: Dictionary = {"width": 6.0, "length": 4.0, "height": 2.5, "opening": []}
const SMALL_CRACK: Dictionary = {"width": 6.0, "length": 4.0, "height": 2.5, "opening": [0.2, 0.2]}
const TRIANGLE: Array = [[0.0, 0.0], [10.0, 100.0], [20.0, 0.0]]
const MAX_KEPT_FAILURES: int = 60
## The tracer is mixed with ambient air by the exterior exchange; that rounds, it does not produce.
## One step of production at 1 kW would move it a thousand times more than this.
const TRACER_TOL: float = 1.0e-12

var _failed: bool = false
var _checks: int = 0
var _group_name: String = ""
var _groups: Array[String] = []
var _failures: Array[String] = []
var _failure_count: int = 0
var _failures_by_group: Dictionary = {}
var _observations: Dictionary = {}
var _source: Dictionary = {}
var _identity: String = ""
var _oracle: Dictionary = {}
var _nodes: Array = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if _load_inputs():
		_off_by_default()
		_whole_run("1.0", 0)
		_whole_run("0.7", 0)
		_whole_run("2.5", 0)
		_radiative_fractions()
		_leaving_the_regime()
		_two_owners()
		_refused_cases()
		_life_cycle()
		_what_the_report_says()
	print("G3_OBJECT_HRR_THERMAL_COUPLING " + JSON.stringify({"checks": _checks, "groups": _groups,
		"failures": _failures, "failure_count": _failure_count, "failures_by_group": _failures_by_group,
		"observations": _observations}, "", true, true))
	if _failed:
		quit(1)
	else:
		print("G3_OBJECT_HRR_THERMAL_COUPLING_PASS")
		quit(0)


func _load_inputs() -> bool:
	_group("B00 inputs")
	var source_file: Variant = JSON.parse_string(FileAccess.get_file_as_string(SOURCE_FIXTURE))
	var oracle_file: Variant = JSON.parse_string(FileAccess.get_file_as_string(ORACLE_FIXTURE))
	var ok: bool = typeof(source_file) == TYPE_DICTIONARY and typeof(oracle_file) == TYPE_DICTIONARY \
			and typeof(source_file.get("source")) == TYPE_DICTIONARY and typeof(oracle_file.get("steps")) == TYPE_DICTIONARY
	_check(ok, "source and oracle fixtures are readable")
	if not ok:
		return false
	_source = source_file["source"]
	_identity = String(source_file["expected_identity"])
	_oracle = oracle_file
	for sample: Dictionary in _source["samples"]:
		_nodes.append(float(sample["hrr_kw"]))
	_check(_oracle.get("source_identity") == _identity, "the oracle was built for this source")
	_check(is_equal_approx(float(_oracle["oxygen"]["kg_per_MJ"]) / 0.076, 1.0), "the bench coefficient is the declared one")
	return true


# ---------------------------------------------------------------- B01 off by default

func _off_by_default() -> void:
	_group("B01 off by default, and a case alone switches nothing on")
	var bench: Dictionary = _bench(LARGE_OPEN, 1.0)
	var engine = bench["engine"]
	var room = bench["room"]
	_check(not engine.g3_prescribed_thermal_source_enabled, "the switch is off by default")
	engine.g3_prescribed_thermal_source_case = _case(_chi(0))
	engine.reset_simulation(ROOM_ID, true)
	_check(engine._g3_prescribed_thermal_source == null, "no coupling exists with the switch off")
	_check(engine.g3_prescribed_thermal_source_failure == "", "no failure is raised with the switch off")
	var report: Dictionary = engine.get_g3_prescribed_thermal_source_report()
	_check(report.get("state") == CouplingScript.STATE_INACTIVE and not report.has("totals"), "the report is inactive")
	for _i: int in range(20):
		engine.step(1.0)
	_check(engine.sim_time_s == 20.0 and room.hrr_kw == 0.0 and room.fire == null, "the room stays cold and the engine runs")
	_check(room.o2_consumed_kg_total_all == 0.0 and room.chi_rad_normal == -1.0, "nothing of the bench reached the room")
	_free(bench)


# ---------------------------------------------------------------- B02-B04 whole run, three steps

func _whole_run(key: String, chi_index: int) -> Dictionary:
	_group("B%s whole run inside the regime, step %s s" % ["02" if key == "1.0" else ("03" if key == "0.7" else "04"), key])
	var expected: Dictionary = _oracle["steps"][key]
	var dt: float = float(expected["dt_s"])
	var energies: Array = expected["step_energy_kj"]
	var chi: Dictionary = _chi(chi_index)
	var bench: Dictionary = _armed(LARGE_OPEN, dt, _case(chi))
	var engine = bench["engine"]
	var room = bench["room"]
	var coupling = engine._g3_prescribed_thermal_source
	var out: Dictionary = {"dt_s": dt, "radiative_fraction": chi["value"]}
	if coupling == null or coupling.state() != CouplingScript.STATE_REPLAYING:
		_check(false, "the bench starts replaying: %s" % str(engine.get_g3_prescribed_thermal_source_report().get("failure")))
		_free(bench)
		return out
	# A4a: the instantaneous peak of the source is the datum, whatever the step.
	var peak: Dictionary = coupling._source.hrr_kw(float(_oracle["instantaneous_peak"]["time_s"]))
	_check(peak.get("hrr_kw") == float(_oracle["instantaneous_peak"]["hrr_kw"]), "instantaneous peak of the source is the datum")
	var co2_kg_start: float = room.co2_kg
	var tracer_start: float = room.co2_upper
	var sum_accepted: float = 0.0
	var sum_oxygen: float = 0.0
	var sum_gas: float = 0.0
	var sum_radiative: float = 0.0
	var sum_displacement: float = 0.0
	var largest_kw: float = -1.0
	var largest_index: int = -1
	var lowest_o2: float = room.o2
	var lowest_o2_lower: float = room.o2_lower
	var lowest_interface: float = INF
	var highest_tracer: float = tracer_start
	var highest_temperature: float = room.temp_upper_c
	# Largest residual of each identity over the run, for the report. Not a tolerance.
	var worst_power_kw: float = 0.0
	var worst_oxygen_kg: float = 0.0
	var worst_split_kj: float = 0.0
	var steps: int = 0
	for index: int in range(energies.size()):
		engine.step(dt)
		steps += 1
		var energy: float = float(energies[index])
		var row: Dictionary = coupling.last_step()
		var tag: String = "step %d" % index
		# A2: power of the step = independent integral / whole step.
		_near(room.hrr_kw, energy / dt, tag + ": room power is the oracle energy over the whole step")
		_near(row.get("accepted_kj"), energy, tag + ": accepted energy is the oracle integral")
		_check(row.get("rejected_kj") == 0.0 and row.get("index") == index, tag + ": nothing rejected, one interval per step")
		# A5: the debit the sink really applied to the room inventory.
		_near_oxygen(room.o2_consumed_bulk_kg_step, energy / 1000.0 * 0.076, tag + ": oxygen debited by the sink")
		_check(room.o2_consumed_fire_kg_step == room.o2_consumed_bulk_kg_step, tag + ": the room inventory is the only primary sink")
		# A6: what ThermalSystem deposited and what it counted as radiated.
		var heat: Dictionary = engine.thermal_system.get_energy_budget().get(ROOM_ID, {})
		_near(_float(heat.get("e_fire_kj")), energy * (1.0 - float(chi["value"])), tag + ": heat to the gas")
		_near(_float(heat.get("q_fire_rad_kj")), energy * float(chi["value"]), tag + ": radiative term")
		_near(_float(heat.get("e_fire_kj")) + _float(heat.get("q_fire_rad_kj")), energy, tag + ": gas plus radiative is the accepted energy")
		_check(absf(_float(heat.get("chi_rad")) - float(chi["value"])) <= 1.0e-12, tag + ": radiative fraction applied is the one of the case")
		# A7: the room-fire route owns nothing here.
		_check(room.fire == null and room.fire_time_s == 0.0 and room.fuel_consumed_MJ_step == 0.0
			and room.retained_unburned_MJ == 0.0, tag + ": no room fire, no fire clock, no fuel")
		_check(room.co_generated_kg_step == 0.0 and room.co2_generated_kg_step == 0.0
			and room.hcn_generated_kg_step == 0.0 and room.smoke_generated_kg_step == 0.0, tag + ": no species generated")
		_check(absf(room.co2_upper - tracer_start) <= TRACER_TOL, tag + ": the carbon dioxide tracer produces nothing")
		highest_tracer = maxf(highest_tracer, room.co2_upper)
		highest_temperature = maxf(highest_temperature, room.temp_upper_c)
		worst_power_kw = maxf(worst_power_kw, absf(room.hrr_kw - energy / dt))
		worst_oxygen_kg = maxf(worst_oxygen_kg, absf(room.o2_consumed_bulk_kg_step - energy / 1000.0 * 0.076))
		worst_split_kj = maxf(worst_split_kj, absf(_float(heat.get("e_fire_kj")) + _float(heat.get("q_fire_rad_kj")) - energy))
		sum_accepted += float(row.get("accepted_kj", 0.0))
		sum_oxygen += room.o2_consumed_bulk_kg_step
		sum_gas += _float(heat.get("e_fire_kj"))
		sum_radiative += _float(heat.get("q_fire_rad_kj"))
		sum_displacement += room.o2_consumed_kg_step_all - room.o2_consumed_fire_kg_step
		if room.hrr_kw > largest_kw:
			largest_kw = room.hrr_kw
			largest_index = index
		lowest_o2 = minf(lowest_o2, room.o2)
		lowest_o2_lower = minf(lowest_o2_lower, room.o2_lower)
		lowest_interface = minf(lowest_interface, engine.thermal_system.effective_hot_layer_height_m(room))
		if coupling.state() == CouplingScript.STATE_FAILED:
			_check(false, tag + ": the bench failed: " + str(coupling.failure()))
			break
	var report: Dictionary = engine.get_g3_prescribed_thermal_source_report()
	var totals: Dictionary = report.get("totals", {})
	# A3 and A8.
	_check(report.get("state") == CouplingScript.STATE_COMPLETED and report.get("is_a_reproduction_of_the_input") == true, "final state is completed")
	_check(report.get("exit", {"x": 1}).is_empty(), "the regime was never left")
	_near(sum_accepted, float(_oracle["total_energy_kj"]), "accepted energy adds up to the table")
	_near(_float(totals.get("accepted_kj")), float(_oracle["total_energy_kj"]), "the bench total is the table")
	_check(totals.get("rejected_kj") == 0.0, "no rejected energy")
	_near(_float(totals.get("scheduled_kj")), _float(totals.get("accepted_kj")) + _float(totals.get("rejected_kj")), "scheduled is accepted plus rejected")
	_near_oxygen(sum_oxygen, _float(totals.get("oxygen_debited_kg")), "the bench counts the oxygen the sink debited")
	_near_oxygen(sum_oxygen, float(_oracle["total_energy_kj"]) / 1000.0 * 0.076, "oxygen debited in the whole run")
	_near(sum_gas, _float(totals.get("to_the_gas_kj")), "the bench counts the heat ThermalSystem deposited")
	_near(sum_radiative, _float(totals.get("radiative_term_kj")), "the bench counts the radiative term of ThermalSystem")
	_near(sum_gas + sum_radiative, sum_accepted, "accumulated: gas plus radiative is the accepted energy")
	_check(report.get("steps") == energies.size() and int(report.get("source_state", {}).get("generation", -1)) == energies.size(), "one confirmation per step")
	_check(_float(report.get("source_state", {}).get("time_s")) == float(_oracle["support_end_s"]), "the source clock ended at the end of the support")
	# A4b and A4c: the largest step power and where it falls are those of the oracle for THIS step.
	_near(largest_kw, float(expected["largest_step_power_kw"]), "largest step power is the one of the oracle for this step")
	_check(largest_index == int(expected["largest_step_index"]) and largest_index == int(expected["step_holding_the_instantaneous_peak"]),
		"the largest step is the one that holds the instantaneous peak: no delay")
	_check(largest_kw < float(_oracle["instantaneous_peak"]["hrr_kw"]), "a finite step stays below the instantaneous peak")
	# Last step: the energy of the shorter interval over the whole step.
	_near(float(expected["last_step_power_kw"]) * dt, float(expected["last_step_energy_kj"]), "oracle: last step power times the step is its energy")
	# A7, accumulated.
	_check(totals.get("room_fire_fuel_consumed_MJ") == 0.0 and totals.get("species_generated_kg") == 0.0
		and totals.get("unburned_inventory_MJ") == 0.0 and totals.get("steps_with_a_room_fire") == 0, "measured: the room-fire route did nothing")
	_check(room.fuel_consumed_MJ_total == 0.0 and room.co_kg == 0.0 and room.hcn_kg == 0.0 and room.smoke_kg == 0.0
		and room.co2_kg == co2_kg_start and room.hrr_kj_total == 0.0, "no fuel debited and no species in the room")
	_check(totals.get("oxygen_debited_without_heat_kg") == 0.0, "no oxygen was debited without its heat")
	# A10: after the support the power is zero and the source is not opened again.
	var closed: Dictionary = engine.get_g3_prescribed_thermal_source_report().get("source_state", {}).duplicate()
	for _i: int in range(40):
		engine.step(dt)
		_check(room.hrr_kw == 0.0 and room.o2_consumed_kg_step_all == 0.0 and coupling.last_step().is_empty(), "after the support: no power, no debit, no interval")
	_check(engine.get_g3_prescribed_thermal_source_report().get("source_state") == closed
		and coupling.state() == CouplingScript.STATE_COMPLETED, "after the support the source is closed and stays closed")
	_refused(coupling._source.propose(float(_oracle["support_end_s"]) + dt), "the source offers nothing after its support")
	out.merge({"steps": steps, "state": report.get("state"), "accepted_kj": sum_accepted, "oxygen_debited_kg": sum_oxygen,
		"to_the_gas_kj": sum_gas, "radiative_term_kj": sum_radiative, "largest_step_power_kw": largest_kw,
		"largest_step_index": largest_index, "oxygen_zone_displacement_kg": sum_displacement,
		"lowest_room_oxygen": lowest_o2, "lowest_lower_layer_oxygen": lowest_o2_lower,
		"lowest_layer_interface_m": lowest_interface, "temperature_upper_end_c": room.temp_upper_c,
		"carbon_dioxide_tracer_start": tracer_start, "carbon_dioxide_tracer_highest": highest_tracer,
		"highest_upper_temperature_c_not_validated": highest_temperature,
		"worst_step_power_residual_kw": worst_power_kw, "worst_step_oxygen_residual_kg": worst_oxygen_kg,
		"worst_step_heat_split_residual_kj": worst_split_kj,
		"rejected_kj": totals.get("rejected_kj")})
	_observations["whole_run_" + key] = out
	_free(bench)
	return out


# ---------------------------------------------------------------- B05 radiative fractions

func _radiative_fractions() -> void:
	_group("B05 four radiative fractions: same energy and oxygen, different split")
	var key: String = "2.5"
	var expected: Dictionary = _oracle["steps"][key]
	var dt: float = float(expected["dt_s"])
	var energies: Array = expected["step_energy_kj"]
	var rows: Array = []
	var accepted: Array = []
	var oxygen: Array = []
	for chi_index: int in range(4):
		var chi: Dictionary = _chi(chi_index)
		var bench: Dictionary = _armed(LARGE_OPEN, dt, _case(chi))
		var engine = bench["engine"]
		var room = bench["room"]
		var steps_accepted: Array = []
		var steps_oxygen: Array = []
		var gas: float = 0.0
		var radiative: float = 0.0
		var hottest: float = room.temp_upper_c
		for index: int in range(energies.size()):
			engine.step(dt)
			hottest = maxf(hottest, room.temp_upper_c)
			var heat: Dictionary = engine.thermal_system.get_energy_budget().get(ROOM_ID, {})
			var energy: float = float(energies[index])
			_near(_float(heat.get("e_fire_kj")), energy * (1.0 - float(chi["value"])), "fraction %s step %d: heat to the gas" % [chi["value"], index])
			_near(_float(heat.get("q_fire_rad_kj")), energy * float(chi["value"]), "fraction %s step %d: radiative term" % [chi["value"], index])
			steps_accepted.append(room.hrr_kw * dt)
			steps_oxygen.append(room.o2_consumed_bulk_kg_step)
			gas += _float(heat.get("e_fire_kj"))
			radiative += _float(heat.get("q_fire_rad_kj"))
		var report: Dictionary = engine.get_g3_prescribed_thermal_source_report()
		_check(report.get("state") == CouplingScript.STATE_COMPLETED, "fraction %s: completed" % chi["value"])
		_check(report.get("radiative_fraction") == chi, "fraction %s: the report keeps value, class and origin" % chi["value"])
		_near(gas + radiative, _float(report.get("totals", {}).get("accepted_kj")), "fraction %s: split closes" % chi["value"])
		_near(gas, float(_oracle["radiative_fractions"][chi_index]["to_the_gas_kj"]), "fraction %s: accumulated heat to the gas is the oracle" % chi["value"])
		_near(radiative, float(_oracle["radiative_fractions"][chi_index]["radiative_term_kj"]), "fraction %s: accumulated radiative term is the oracle" % chi["value"])
		accepted.append(steps_accepted)
		oxygen.append(steps_oxygen)
		rows.append({"radiative_fraction": chi["value"], "class": chi["class"], "accepted_kj": report.get("totals", {}).get("accepted_kj"),
			"oxygen_debited_kg": report.get("totals", {}).get("oxygen_debited_kg"), "to_the_gas_kj": gas, "radiative_term_kj": radiative,
			"highest_upper_temperature_c_not_validated": hottest, "state": report.get("state")})
		_free(bench)
	# A9: energy and equivalent oxygen do not depend on the fraction, step by step and bit by bit.
	for chi_index: int in range(1, 4):
		_check(accepted[chi_index] == accepted[0], "accepted energy per step does not depend on the fraction (%d)" % chi_index)
		_check(oxygen[chi_index] == oxygen[0], "oxygen debit per step does not depend on the fraction (%d)" % chi_index)
		_check(rows[chi_index]["accepted_kj"] == rows[0]["accepted_kj"] and rows[chi_index]["oxygen_debited_kg"] == rows[0]["oxygen_debited_kg"],
			"accumulated energy and oxygen do not depend on the fraction (%d)" % chi_index)
	_check(rows[1]["to_the_gas_kj"] < rows[2]["to_the_gas_kj"] and rows[2]["to_the_gas_kj"] < rows[0]["to_the_gas_kj"]
		and rows[3]["to_the_gas_kj"] < rows[1]["to_the_gas_kj"], "the split does depend on the fraction")
	_observations["radiative_fractions"] = rows


# ---------------------------------------------------------------- B06 leaving the regime

func _leaving_the_regime() -> void:
	_group("B06 leaving the declared regime: nothing accepted, latched, no queue")
	var dt: float = 2.5
	var energies: Array = _oracle["steps"]["2.5"]["step_energy_kj"]
	var total: float = float(_oracle["total_energy_kj"])
	# (a) 60 m3 with a crack to the outside: the room inventory is the sink, and it runs down.
	var bench: Dictionary = _armed(SMALL_CRACK, dt, _case(_chi(0)))
	var engine = bench["engine"]
	var room = bench["room"]
	var coupling = engine._g3_prescribed_thermal_source
	var exit_index: int = -1
	var accepted_before: float = 0.0
	var oxygen_before: float = 0.0
	for index: int in range(energies.size()):
		var was_inside: bool = coupling.state() == CouplingScript.STATE_REPLAYING
		engine.step(dt)
		var row: Dictionary = coupling.last_step()
		if row.get("state_after") != CouplingScript.STATE_OUTSIDE:
			accepted_before += float(row.get("accepted_kj", 0.0))
			oxygen_before += room.o2_consumed_bulk_kg_step
			_near(room.hrr_kw, float(energies[index]) / dt, "crack step %d: inside the regime the whole interval is applied" % index)
			_check(exit_index < 0, "crack step %d: no interval is accepted after the exit" % index)
			continue
		if exit_index < 0:
			exit_index = index
			_check(was_inside, "crack: the exit happens at a step that started inside")
		# From the exit on: all or nothing, and it is nothing.
		_check(room.hrr_kw == 0.0 and row.get("accepted_kj") == 0.0, "crack step %d: nothing accepted outside the regime" % index)
		_near(_float(row.get("rejected_kj")), float(energies[index]), "crack step %d: the interval is recorded as rejected" % index)
		_check(room.o2_consumed_kg_step_all == 0.0, "crack step %d: no oxygen debited outside the regime" % index)
		_check(_float(engine.thermal_system.get_energy_budget().get(ROOM_ID, {}).get("e_fire_kj")) == 0.0, "crack step %d: no heat deposited outside the regime" % index)
		_check(coupling.state() == CouplingScript.STATE_OUTSIDE, "crack step %d: the state stays latched" % index)
	var report: Dictionary = engine.get_g3_prescribed_thermal_source_report()
	var exit: Dictionary = report.get("exit", {})
	_check(exit_index > 0 and report.get("state") == CouplingScript.STATE_OUTSIDE, "the nearly closed room leaves the regime")
	_check(["oxygen_below_the_declared_tolerance", "hot_layer_below_the_declared_height"].has(exit.get("cause"))
		and exit.get("step") == exit_index, "cause and step of the exit are recorded")
	_check(_float(exit.get("source_time_s")) == float(exit_index) * dt, "instant of the exit is the start of the first rejected interval")
	_check(_float(exit.get("source_time_s")) < float(_oracle["instantaneous_peak"]["time_s"]), "it leaves the regime before the peak")
	_check(report.get("is_a_reproduction_of_the_input") == false, "a run that left the regime is not a reproduction")
	var totals: Dictionary = report.get("totals", {})
	_near(_float(totals.get("accepted_kj")), accepted_before, "accepted energy is what was applied before the exit")
	_near(_float(totals.get("accepted_kj")) + _float(totals.get("rejected_kj")), total, "accepted plus rejected is the whole table")
	_near(_float(totals.get("scheduled_kj")), total, "the clock went on to the end of the support")
	_near_oxygen(_float(totals.get("oxygen_debited_kg")), accepted_before / 1000.0 * 0.076, "oxygen debited matches the accepted energy only")
	_near(_float(totals.get("to_the_gas_kj")) + _float(totals.get("radiative_term_kj")), accepted_before, "heat counted matches the accepted energy only")
	_check(_float(report.get("source_state", {}).get("time_s")) == float(_oracle["support_end_s"]), "source clock reached the end of the support")
	_check(totals.get("unburned_inventory_MJ") == 0.0 and room.retained_unburned_MJ == 0.0 and room.fire == null
		and totals.get("room_fire_fuel_consumed_MJ") == 0.0, "rejected energy became neither unburned inventory nor a room fire")
	# (b) the oxygen comes back and the bench does not: latched until a reset.
	room.o2 = float(report["oxygen_at_ignition"]["room"])
	room.o2_lower = float(report["oxygen_at_ignition"]["lower"])
	room.o2_upper = float(report["oxygen_at_ignition"]["upper"])
	for _i: int in range(30):
		engine.step(dt)
		_check(room.hrr_kw == 0.0 and coupling.state() == CouplingScript.STATE_OUTSIDE, "oxygen restored: no reactivation")
	_check(engine.get_g3_prescribed_thermal_source_report().get("totals") == totals, "oxygen restored: no energy delivered later, no queue")
	_observations["small_room_with_a_crack"] = {"exit_step": exit_index, "exit": exit, "accepted_kj": totals.get("accepted_kj"),
		"rejected_kj": totals.get("rejected_kj"), "accepted_share": _float(totals.get("accepted_kj")) / total,
		"oxygen_debited_kg": totals.get("oxygen_debited_kg"), "state": report.get("state")}
	_free(bench)
	# (c) the same room recovering BEFORE the end of the support: still latched while intervals remain.
	bench = _armed(SMALL_CRACK, dt, _case(_chi(0)))
	engine = bench["engine"]
	room = bench["room"]
	coupling = engine._g3_prescribed_thermal_source
	var guard: int = 0
	while coupling.state() == CouplingScript.STATE_REPLAYING and guard < energies.size():
		engine.step(dt)
		guard += 1
	var at_exit: Dictionary = engine.get_g3_prescribed_thermal_source_report()
	room.o2 = float(at_exit["oxygen_at_ignition"]["room"])
	room.o2_lower = float(at_exit["oxygen_at_ignition"]["lower"])
	room.o2_upper = float(at_exit["oxygen_at_ignition"]["upper"])
	var before: float = _float(at_exit.get("totals", {}).get("accepted_kj"))
	for _i: int in range(60):
		engine.step(dt)
		_check(room.hrr_kw == 0.0 and coupling.state() == CouplingScript.STATE_OUTSIDE
			and _float(coupling.last_step().get("rejected_kj")) >= 0.0 and coupling.last_step().get("accepted_kj") == 0.0,
			"mid-run recovery of oxygen: intervals keep being rejected")
	_check(_float(engine.get_g3_prescribed_thermal_source_report().get("totals", {}).get("accepted_kj")) == before
		and guard < energies.size(), "mid-run recovery of oxygen: accepted energy did not grow")
	_free(bench)
	# (c2) the same room judged by the oxygen alone: the layer criterion at zero.
	bench = _armed(SMALL_CRACK, dt, _case(_chi(0), 0.076, 0.01, 0.0))
	engine = bench["engine"]
	room = bench["room"]
	coupling = engine._g3_prescribed_thermal_source
	for _i: int in range(energies.size()):
		engine.step(dt)
	report = engine.get_g3_prescribed_thermal_source_report()
	_check(report.get("state") == CouplingScript.STATE_OUTSIDE and report.get("exit", {}).get("cause") == "oxygen_below_the_declared_tolerance",
		"by the oxygen alone the nearly closed room leaves the regime too")
	_check(_float(report.get("exit", {}).get("room_drop")) > 0.01 or _float(report.get("exit", {}).get("lower_layer_drop")) > 0.01,
		"the exit records which oxygen number fell")
	_near(_float(report.get("totals", {}).get("accepted_kj")) + _float(report.get("totals", {}).get("rejected_kj")), total, "oxygen exit: accepted plus rejected is the whole table")
	_observations["small_room_with_a_crack_oxygen_only"] = {"exit": report.get("exit"), "accepted_kj": report.get("totals", {}).get("accepted_kj"),
		"accepted_share": _float(report.get("totals", {}).get("accepted_kj")) / total, "state": report.get("state")}
	_free(bench)
	# (d) 60 m3 with no opening: the engine sink takes another route; the bench cannot keep its contract.
	bench = _armed(SMALL_SEALED, dt, _case(_chi(0)))
	engine = bench["engine"]
	room = bench["room"]
	coupling = engine._g3_prescribed_thermal_source
	engine.step(dt)
	report = engine.get_g3_prescribed_thermal_source_report()
	_check(report.get("state") == CouplingScript.STATE_OUTSIDE and report.get("exit", {}).get("cause") == "oxygen_debit_is_not_the_committed_one"
		and report.get("exit", {}).get("step") == 0, "sealed room: invalid at the first step, by the route of the sink")
	_check(room.hrr_kw == 0.0 and _float(engine.thermal_system.get_energy_budget().get(ROOM_ID, {}).get("e_fire_kj")) == 0.0
		and report.get("totals", {}).get("accepted_kj") == 0.0 and report.get("totals", {}).get("to_the_gas_kj") == 0.0,
		"sealed room: the power was withdrawn before the heat; nothing counted as valid")
	_check(room.o2_consumed_bulk_kg_step == 0.0 and _float(report.get("totals", {}).get("oxygen_debited_without_heat_kg")) > 0.0,
		"sealed room: what the other route debited is reported, not hidden")
	for _i: int in range(20):
		engine.step(dt)
		_check(room.hrr_kw == 0.0 and room.o2_consumed_kg_step_all == 0.0 and coupling.state() == CouplingScript.STATE_OUTSIDE, "sealed room: latched")
	_observations["small_sealed_room"] = {"exit": report.get("exit"), "state": report.get("state"),
		"oxygen_debited_without_heat_kg": report.get("totals", {}).get("oxygen_debited_without_heat_kg")}
	_free(bench)
	# (e) a declared coefficient that is not the one of the sink: the debit differs, the heat is withdrawn.
	bench = _armed(LARGE_OPEN, dt, _case(_chi(0), 1.0 / 13.1))
	engine = bench["engine"]
	room = bench["room"]
	engine.step(dt)
	report = engine.get_g3_prescribed_thermal_source_report()
	_check(report.get("state") == CouplingScript.STATE_OUTSIDE and report.get("exit", {}).get("cause") == "oxygen_debit_is_not_the_committed_one"
		and room.hrr_kw == 0.0 and report.get("totals", {}).get("accepted_kj") == 0.0, "a coefficient that is not the sink's is not accepted as valid heat")
	_free(bench)
	# (f) a tolerance so small that the first debit breaks it: exit by the declared tolerance, early.
	bench = _armed(LARGE_OPEN, dt, _case(_chi(0), 0.076, 1.0e-9))
	engine = bench["engine"]
	for _i: int in range(12):
		engine.step(dt)
	report = engine.get_g3_prescribed_thermal_source_report()
	_check(report.get("state") == CouplingScript.STATE_OUTSIDE and report.get("exit", {}).get("cause") == "oxygen_below_the_declared_tolerance",
		"the oxygen tolerance is the one of the case")
	_free(bench)
	# (g) a layer criterion above the ceiling: exit by the declared height at the first step.
	bench = _armed(LARGE_OPEN, dt, _case(_chi(0), 0.076, 0.01, 99.0))
	engine = bench["engine"]
	engine.step(dt)
	report = engine.get_g3_prescribed_thermal_source_report()
	_check(report.get("state") == CouplingScript.STATE_OUTSIDE and report.get("exit", {}).get("cause") == "hot_layer_below_the_declared_height"
		and report.get("totals", {}).get("accepted_kj") == 0.0, "the layer criterion is the one of the case")
	_free(bench)


# ---------------------------------------------------------------- B07 two owners

func _two_owners() -> void:
	_group("B07 a second owner in the room stops the bench")
	var dt: float = 2.5
	for intruder: String in ["room_fire", "cold_fuel_object", "room_fuel_load", "suppression"]:
		var bench: Dictionary = _armed(LARGE_OPEN, dt, _case(_chi(0)))
		var engine = bench["engine"]
		var room = bench["room"]
		var coupling = engine._g3_prescribed_thermal_source
		for _i: int in range(40):
			engine.step(dt)
		var before: Dictionary = engine.get_g3_prescribed_thermal_source_report().get("totals", {}).duplicate()
		_check(coupling.state() == CouplingScript.STATE_REPLAYING and _float(before.get("accepted_kj")) > 0.0, intruder + ": replaying before the intruder")
		var cause: String = ""
		match intruder:
			"room_fire":
				# With its default fuel: a room fire without fuel puts itself out in the same step.
				room.fire = FireModelScript.new()
				cause = "the_room_has_a_room_fire"
			"cold_fuel_object":
				var chair = FuelObjectModelScript.new()
				chair.id = "cold_chair"
				chair.fuel_energy_MJ = 100.0
				chair.remaining_fuel_MJ = 100.0
				chair.max_hrr_kw = 500.0
				room.fuel_objects.append(chair)
				cause = "the_room_has_fuel"
			"room_fuel_load":
				room.fuel_energy_MJ = 500.0
				cause = "the_room_has_fuel"
			"suppression":
				engine.apply_suppression(ROOM_ID, 30.0)
				cause = "suppression_in_the_room"
		engine.step(dt)
		var report: Dictionary = engine.get_g3_prescribed_thermal_source_report()
		_check(report.get("state") == CouplingScript.STATE_OUTSIDE and report.get("exit", {}).get("cause") == cause, intruder + ": the bench leaves with its cause")
		_check(coupling.last_step().get("accepted_kj") == 0.0 and _float(coupling.last_step().get("rejected_kj")) > 0.0, intruder + ": the interval is rejected whole")
		_check(report.get("totals", {}).get("accepted_kj") == before.get("accepted_kj")
			and report.get("totals", {}).get("oxygen_debited_kg") == before.get("oxygen_debited_kg"), intruder + ": nothing more is counted as the bench's")
		for _i: int in range(10):
			engine.step(dt)
		_check(coupling.state() == CouplingScript.STATE_OUTSIDE
			and engine.get_g3_prescribed_thermal_source_report().get("totals", {}).get("accepted_kj") == before.get("accepted_kj"), intruder + ": latched")
		_free(bench)
	# A modifier of the heat split changed in the middle of the run. The engine was the
	# declared one when the bench was armed; ThermalSystem then deposits something else.
	# That cannot be undone, so the bench fails and the engine stops.
	var late: Dictionary = _armed(LARGE_OPEN, dt, _case(_chi(0)))
	var late_engine = late["engine"]
	for _i: int in range(40):
		late_engine.step(dt)
	var accepted: float = _float(late_engine.get_g3_prescribed_thermal_source_report().get("totals", {}).get("accepted_kj"))
	late_engine.two_zone_convective_heat_multiplier = 1.2
	late_engine.step(dt)
	var late_report: Dictionary = late_engine.get_g3_prescribed_thermal_source_report()
	_check(late_report.get("state") == CouplingScript.STATE_FAILED and late_engine.g3_prescribed_thermal_source_failure != ""
		and not late_report.get("failure", []).is_empty(), "heat that is not the accepted energy: the bench fails, with its reasons")
	_check(late_report.get("is_a_reproduction_of_the_input") == false and _float(late_report.get("totals", {}).get("accepted_kj")) > accepted,
		"the step whose heat differed is on record and the run is not a reproduction")
	var late_clock: float = late_engine.sim_time_s
	for _i: int in range(5):
		late_engine.step(dt)
	_check(late_engine.sim_time_s == late_clock, "after the failure the engine does not advance")
	_free(late)


# ---------------------------------------------------------------- B08 refused cases

func _refused_cases() -> void:
	_group("B08 invalid configuration: explicit failure, nothing simulated, nothing left in the room")
	var good: Dictionary = _case(_chi(0))
	# A source with the same energy and another content: two interior samples moved by +1 and -1 kW.
	var swapped: Dictionary = _source.duplicate(true)
	swapped["samples"][1000]["hrr_kw"] = float(swapped["samples"][1000]["hrr_kw"]) + 1.0
	swapped["samples"][2000]["hrr_kw"] = float(swapped["samples"][2000]["hrr_kw"]) - 1.0
	var probe: RefCounted = SourceScript.new()
	var probe_opened: Dictionary = probe.open(swapped)
	_check(_positive(probe_opened), "the swapped table is itself a valid source")
	_near(_float(probe.report().get("table_energy_kj")), float(_oracle["total_energy_kj"]), "the swapped table has the same energy")
	_check(probe.report().get("source_fingerprint") != _identity, "and another identity")
	var with_fraction: Dictionary = _source.duplicate(true)
	with_fraction["unknown"]["radiative_fraction"] = 0.52
	var cases: Dictionary = {
		"table swapped for another with the same energy": _with(good, "source", swapped),
		"radiative fraction kept inside the source": _with(good, "source", with_fraction),
		"wrong expected identity": _with(good, "expected_source_fingerprint", "0".repeat(64)),
		"case of another room": _with(good, "room_id", 7),
		"room id that is not an integer": _with(good, "room_id", "0"),
		"case with an extra field": _with(good, "fuel_mass_kg", 9.677),
		"case with a missing field": _without(good, "regime"),
		"case that is not a record": "case",
		"schema of something else": _with(good, "schema", "g3_prescribed_object_hrr_source_v1"),
		"coefficient zero": _with(good, "oxygen_kg_per_MJ", 0.0),
		"coefficient not a number": _with(good, "oxygen_kg_per_MJ", "0.076"),
		"coefficient not finite": _with(good, "oxygen_kg_per_MJ", NAN),
		"fraction presented as measured in an enclosure": _with(good, "radiative_fraction", {"value": 0.52, "class": "measured_in_the_enclosure", "what": "x"}),
		"fraction with no origin": _with(good, "radiative_fraction", {"value": 0.35, "class": "assumed", "what": " "}),
		"fraction of zero": _with(good, "radiative_fraction", {"value": 0.0, "class": "assumed", "what": "x"}),
		"fraction above one": _with(good, "radiative_fraction", {"value": 1.2, "class": "assumed", "what": "x"}),
		"fraction as a bare number": _with(good, "radiative_fraction", 0.35),
		"regime presented as validated": _with(good, "regime", {"oxygen_drop_tolerance": 0.01, "layer_interface_min_m": 0.3, "status": "validated_limit"}),
		"negative oxygen tolerance": _with(good, "regime", {"oxygen_drop_tolerance": -0.01, "layer_interface_min_m": 0.3, "status": CouplingScript.REGIME_STATUS}),
		"regime with a missing criterion": _with(good, "regime", {"oxygen_drop_tolerance": 0.01, "status": CouplingScript.REGIME_STATUS}),
		"source that is not a table": _with(good, "source", {"samples": []}),
	}
	for title: String in cases:
		_not_simulated(LARGE_OPEN, cases[title], {}, {}, title)
	# The engine is not the declared one.
	var engines: Dictionary = {
		"explicit oxygen mode upper": {"fire_o2_mode": "upper"},
		"explicit oxygen mode lower": {"fire_o2_mode": "lower"},
		"explicit oxygen mode interface": {"fire_o2_mode": "interface"},
		"historical lower-oxygen flag": {"fire_o2_lower_for_flame": true},
		"historical upper-oxygen flag": {"fire_o2_upper_for_flame": true},
		"heat not measured: energy budget off": {"energy_budget_enabled": false},
		"convective multiplier not neutral": {"two_zone_convective_heat_multiplier": 1.2},
		"window boost not neutral": {"outside_open_upper_heat_boost": 0.5},
		"run ends by extinction": {"auto_finish_on_extinction": true},
		"oxygen mass tracking on": {"fire_o2_mass_tracking_enabled": true},
	}
	for title: String in engines:
		_not_simulated(LARGE_OPEN, good, engines[title], {}, title)
	# Every condition the bench asks of the engine, one by one, on the coupling itself:
	# the engine as it describes itself, with a single answer changed.
	var probe_bench: Dictionary = _bench(LARGE_OPEN, 2.5)
	var probe_engine = probe_bench["engine"]
	probe_engine.reset_simulation(ROOM_ID, false)
	var described: Dictionary = probe_engine._g3_prescribed_thermal_environment()
	var hooks: Dictionary = {
		"oxygen_floor_MJ": Callable(probe_engine.oxygen_exchange_system, "fire_sink_heat_acceptance_floor_MJ"),
		"layer_interface_m": Callable(probe_engine.thermal_system, "effective_hot_layer_height_m"),
		"energy_budget": Callable(probe_engine.thermal_system, "get_energy_budget"),
		"suppression_active": Callable(probe_engine, "_g3_prescribed_thermal_suppression_active"),
	}
	_check(described.size() == CouplingScript.REQUIRED_ENVIRONMENT.size(), "the engine answers every condition and no other")
	var accepted_as_is = CouplingScript.new()
	_check(_positive(accepted_as_is.arm(probe_bench["room"], described, hooks, good))
		and accepted_as_is.state() == CouplingScript.STATE_ARMED, "the engine as it describes itself is accepted")
	for key: String in CouplingScript.REQUIRED_ENVIRONMENT:
		var wanted: Variant = CouplingScript.REQUIRED_ENVIRONMENT[key]
		var changed: Dictionary = described.duplicate(true)
		match typeof(wanted):
			TYPE_BOOL:
				changed[key] = not wanted
			TYPE_FLOAT:
				changed[key] = float(wanted) + 0.25
			_:
				changed[key] = "upper"
		var refused = CouplingScript.new()
		_refused(refused.arm(probe_bench["room"], changed, hooks, good), "engine condition " + key + " changed")
		_check(refused.state() == CouplingScript.STATE_FAILED and not refused.failure().is_empty(), "engine condition " + key + ": failed, with its reason")
		var absent: Dictionary = described.duplicate(true)
		absent.erase(key)
		_refused(CouplingScript.new().arm(probe_bench["room"], absent, hooks, good), "engine condition " + key + " not answered")
	for name: String in CouplingScript.CALLABLES:
		var fewer: Dictionary = hooks.duplicate()
		fewer.erase(name)
		_refused(CouplingScript.new().arm(probe_bench["room"], described, fewer, good), "hook " + name + " missing")
	_refused(accepted_as_is.arm(probe_bench["room"], described, hooks, good), "a coupling is armed once")
	_check(accepted_as_is.state() == CouplingScript.STATE_ARMED and accepted_as_is.failure().is_empty(), "and the refusal leaves it as it was")
	_free(probe_bench)
	# The room is not the declared one.
	var rooms: Dictionary = {
		"room with a fuel load": {"fuel_energy_MJ": 500.0},
		"room with a power cap": {"max_hrr_kw": 300.0},
		"room with a cold fuel object": {"fuel_object": true},
		"room with a room fire": {"room_fire": true},
		"room with unburned energy": {"retained_unburned_MJ": 1.0},
	}
	for title: String in rooms:
		_not_simulated(LARGE_OPEN, good, {}, rooms[title], title)


## Arms a bench that must be refused, and checks that nothing moved.
func _not_simulated(spec: Dictionary, case: Variant, engine_changes: Dictionary, room_changes: Dictionary, title: String) -> void:
	var bench: Dictionary = _bench(spec, 2.5)
	var engine = bench["engine"]
	var room = bench["room"]
	for key: String in engine_changes:
		engine.set(key, engine_changes[key])
	engine.g3_prescribed_thermal_source_enabled = true
	# The engine variable is typed; a case that is not a record reaches it as an empty one.
	engine.g3_prescribed_thermal_source_case = case if typeof(case) == TYPE_DICTIONARY else {}
	engine.reset_simulation(ROOM_ID, true)
	# The room is altered AFTER the reset has cleaned it and before arming again.
	if not room_changes.is_empty():
		_alter_room(room, room_changes)
		engine.reset_simulation(ROOM_ID, false)
		_alter_room(room, room_changes)
		engine._g3_prescribed_thermal_discard()
		engine._g3_prescribed_thermal_arm()
	var report: Dictionary = engine.get_g3_prescribed_thermal_source_report()
	_check(engine.g3_prescribed_thermal_source_failure != "" and report.get("state") == CouplingScript.STATE_FAILED, title + ": explicit failure")
	_check(typeof(report.get("failure")) == TYPE_ARRAY and not report["failure"].is_empty(), title + ": with its reasons")
	_check(not report.has("totals") or report["totals"].get("accepted_kj") == 0.0, title + ": nothing accepted")
	var time_before: float = engine.sim_time_s
	var o2_before: float = room.o2
	for _i: int in range(5):
		engine.step(2.5)
	_check(engine.sim_time_s == time_before, title + ": the engine does not advance")
	_check(room.hrr_kw == 0.0 and room.o2 == o2_before and room.chi_rad_normal == -1.0
		and room.combustion_regime != CouplingScript.REGIME_LABEL, title + ": nothing of the bench in the room")
	_check(room.o2_consumed_kg_total_all == 0.0 and room.hrr_kj_total == 0.0, title + ": no historical fallback ran")
	_free(bench)


func _alter_room(room, changes: Dictionary) -> void:
	if changes.has("fuel_energy_MJ"):
		room.fuel_energy_MJ = float(changes["fuel_energy_MJ"])
	if changes.has("max_hrr_kw"):
		room.max_hrr_kw = float(changes["max_hrr_kw"])
	if changes.has("retained_unburned_MJ"):
		room.retained_unburned_MJ = float(changes["retained_unburned_MJ"])
	if changes.has("room_fire") and room.fire == null:
		room.fire = FireModelScript.new()
	if changes.has("fuel_object") and room.fuel_objects.is_empty():
		var chair = FuelObjectModelScript.new()
		chair.id = "cold_chair"
		chair.fuel_energy_MJ = 100.0
		chair.remaining_fuel_MJ = 100.0
		room.fuel_objects.append(chair)


# ---------------------------------------------------------------- B09 life cycle on ONE engine

func _life_cycle() -> void:
	_group("B09 life cycle on the same engine: reset, revoke, no building, not ready, another table")
	var dt: float = 2.5
	var energies: Array = _oracle["steps"]["2.5"]["step_energy_kj"]
	var bench: Dictionary = _armed(LARGE_OPEN, dt, _case(_chi(1)))
	var engine = bench["engine"]
	var building = bench["building"]
	var room = bench["room"]
	var first = engine._g3_prescribed_thermal_source
	for _i: int in range(300):
		engine.step(dt)
	_check(first.state() == CouplingScript.STATE_REPLAYING and room.hrr_kw > 0.0 and room.chi_rad_normal == 0.52, "first run is replaying")
	var old_offer: Dictionary = first._source.propose(first._source.snapshot()["time_s"] + dt)
	_check(_positive(old_offer), "an offer of the first run exists")
	var old_totals: Dictionary = engine.get_g3_prescribed_thermal_source_report().get("totals", {})
	_check(_float(old_totals.get("accepted_kj")) > 0.0, "the first run delivered energy")
	# 1. Reset: a new instance, clock at the ignition, nothing inherited.
	engine.reset_simulation(ROOM_ID, true)
	var second = engine._g3_prescribed_thermal_source
	_check(second != null and second != first, "reset: a new instance")
	_check(first.state() == CouplingScript.STATE_INACTIVE and first.report().get("state") == CouplingScript.STATE_INACTIVE
		and not first.report().has("totals"), "reset: the previous instance was retired and says so")
	var report: Dictionary = engine.get_g3_prescribed_thermal_source_report()
	_check(report.get("state") == CouplingScript.STATE_REPLAYING and report.get("steps") == 0
		and report.get("totals", {}).get("accepted_kj") == 0.0 and _float(report.get("source_state", {}).get("time_s")) == 0.0, "reset: counters and clock start again")
	_check(room.hrr_kw == 0.0 and room.chi_rad_normal == -1.0 and engine.sim_time_s == 0.0, "reset: the room holds no power of the previous run")
	_refused(second._source.confirm(old_offer.get("proposal", {}), 0.0), "reset: an offer of the previous generation is refused")
	_refused(first._source.confirm(old_offer.get("proposal", {}), 0.0) if first._source != null else {"valid": false, "errors": ["retired"]}, "reset: the retired instance confirms nothing")
	engine.step(dt)
	_near(room.hrr_kw, float(energies[0]) / dt, "reset: the run starts again from the first interval")
	# A stale offer inside the same run.
	var stale: Dictionary = second._source.propose(second._source.snapshot()["time_s"] + dt)
	engine.step(dt)
	_refused(second._source.confirm(stale.get("proposal", {}), 0.0), "an offer overtaken by a step is refused")
	# 2. Revocation on the same engine.
	for _i: int in range(100):
		engine.step(dt)
	_check(room.hrr_kw > 0.0, "second run is delivering")
	engine.g3_prescribed_thermal_source_enabled = false
	engine.reset_simulation(ROOM_ID, true)
	report = engine.get_g3_prescribed_thermal_source_report()
	_check(engine._g3_prescribed_thermal_source == null and report.get("state") == CouplingScript.STATE_INACTIVE
		and not report.has("totals") and engine.g3_prescribed_thermal_source_failure == "", "revoked: no instance, inactive report, no failure")
	_check(second.state() == CouplingScript.STATE_INACTIVE, "revoked: the instance was retired")
	for _i: int in range(20):
		engine.step(dt)
	_check(room.hrr_kw == 0.0 and room.chi_rad_normal == -1.0 and room.o2_consumed_kg_total_all == 0.0
		and room.combustion_regime != CouplingScript.REGIME_LABEL and engine.sim_time_s == 50.0, "revoked: the same engine runs with a cold room")
	# 3. Reset without a building, after a run that was delivering.
	engine.g3_prescribed_thermal_source_enabled = true
	engine.reset_simulation(ROOM_ID, true)
	for _i: int in range(200):
		engine.step(dt)
	var third = engine._g3_prescribed_thermal_source
	_check(third.state() == CouplingScript.STATE_REPLAYING and room.hrr_kw > 0.0, "third run is delivering")
	var clock: float = engine.sim_time_s
	engine.building = null
	engine.reset_simulation(ROOM_ID, true)
	report = engine.get_g3_prescribed_thermal_source_report()
	_check(engine._g3_prescribed_thermal_source == null and report.get("state") == CouplingScript.STATE_INACTIVE and not report.has("totals"), "no building: retired, inactive report")
	_check(third.state() == CouplingScript.STATE_INACTIVE and room.hrr_kw == 0.0 and room.chi_rad_normal == -1.0
		and room.combustion_regime != CouplingScript.REGIME_LABEL, "no building: the power it wrote was withdrawn from the room")
	engine.step(dt)
	_check(engine.sim_time_s == clock, "no building: the clock does not advance")
	# 4. Building back but the engine not ready.
	engine.building = building
	engine.reset_simulation(ROOM_ID, true)
	for _i: int in range(150):
		engine.step(dt)
	var fourth = engine._g3_prescribed_thermal_source
	_check(fourth != null and fourth.state() == CouplingScript.STATE_REPLAYING and room.hrr_kw > 0.0, "fourth run is delivering")
	var hvac = engine.hvac_system
	engine.hvac_system = null
	_check(not engine.is_ready_for_validation(), "the engine is not ready")
	engine.reset_simulation(ROOM_ID, true)
	report = engine.get_g3_prescribed_thermal_source_report()
	_check(engine._g3_prescribed_thermal_source == null and report.get("state") == CouplingScript.STATE_INACTIVE and not report.has("totals"), "not ready: retired, inactive report")
	_check(fourth.state() == CouplingScript.STATE_INACTIVE and room.hrr_kw == 0.0 and room.chi_rad_normal == -1.0, "not ready: no inherited power in the room")
	engine.hvac_system = hvac
	_check(engine.is_ready_for_validation(), "the engine is ready again")
	# 5. Another table on the same engine: a synthetic triangle, its own identity, its own total.
	var triangle: Dictionary = _synthetic(TRIANGLE)
	var opened: RefCounted = SourceScript.new()
	opened.open(triangle)
	var triangle_identity: String = String(opened.report().get("source_fingerprint"))
	engine.g3_prescribed_thermal_source_case = _case(_chi(0), 0.076, 0.01, 0.3, triangle, triangle_identity)
	engine.reset_simulation(ROOM_ID, true)
	var fifth = engine._g3_prescribed_thermal_source
	report = engine.get_g3_prescribed_thermal_source_report()
	_check(fifth != null and report.get("state") == CouplingScript.STATE_REPLAYING and report.get("source_fingerprint") == triangle_identity
		and report.get("source_fingerprint") != _identity and report.get("totals", {}).get("accepted_kj") == 0.0, "another table: new instance, its own identity, nothing inherited")
	var largest: float = 0.0
	engine.sim_fixed_dt = 4.0
	for _i: int in range(5):
		engine.step(4.0)
		largest = maxf(largest, room.hrr_kw)
	engine.sim_fixed_dt = dt
	report = engine.get_g3_prescribed_thermal_source_report()
	_check(report.get("state") == CouplingScript.STATE_COMPLETED, "another table: completed")
	_near(_float(report.get("totals", {}).get("accepted_kj")), 1000.0, "another table: its own total, closed form")
	_near(largest, 90.0, "another table: a 4 s step returns 90 kW of a 100 kW peak, closed form")
	_near_oxygen(_float(report.get("totals", {}).get("oxygen_debited_kg")), 0.076, "another table: 1 MJ debits 0.076 kg")
	# 6. A refused case and then a valid one: the failure is not inherited.
	engine.g3_prescribed_thermal_source_case = _with(_case(_chi(0)), "expected_source_fingerprint", "f".repeat(64))
	engine.reset_simulation(ROOM_ID, true)
	_check(engine.g3_prescribed_thermal_source_failure != "" and engine.get_g3_prescribed_thermal_source_report().get("state") == CouplingScript.STATE_FAILED, "a refused case fails")
	clock = engine.sim_time_s
	engine.step(dt)
	_check(engine.sim_time_s == clock and room.hrr_kw == 0.0, "a refused case does not advance")
	engine.g3_prescribed_thermal_source_case = _case(_chi(0))
	engine.reset_simulation(ROOM_ID, true)
	engine.step(dt)
	_check(engine.g3_prescribed_thermal_source_failure == "" and engine.get_g3_prescribed_thermal_source_report().get("state") == CouplingScript.STATE_REPLAYING, "a valid case after a refused one runs")
	_near(room.hrr_kw, float(energies[0]) / dt, "and starts from the first interval of the real table")
	# 7. A reset that does not ignite leaves the source armed with its clock stopped.
	engine.reset_simulation(ROOM_ID, false)
	var armed = engine._g3_prescribed_thermal_source
	for _i: int in range(10):
		engine.step(dt)
	_check(armed.state() == CouplingScript.STATE_ARMED and room.hrr_kw == 0.0 and engine.get_g3_prescribed_thermal_source_report().get("steps") == 0, "armed and not ignited: the clock of the source waits")
	engine.ignite_room(ROOM_ID)
	_check(armed.state() == CouplingScript.STATE_REPLAYING and room.fire == null and _float(engine.get_g3_prescribed_thermal_source_report().get("ignition_time_s")) == 25.0,
		"ignition starts the clock and creates no room fire")
	engine.step(dt)
	_near(room.hrr_kw, float(energies[0]) / dt, "the first interval is delivered at the ignition, not at the reset")
	_free(bench)


# ---------------------------------------------------------------- B10 report

func _what_the_report_says() -> void:
	_group("B10 what the report says and does not say")
	var bench: Dictionary = _armed(LARGE_OPEN, 2.5, _case(_chi(1)))
	var engine = bench["engine"]
	engine.step(2.5)
	var report: Dictionary = engine.get_g3_prescribed_thermal_source_report()
	for key: String in ["combustion_of_the_object", "fuel_consumed", "species_produced", "temperatures_validated", "product_activation"]:
		_check(typeof(report.get(key)) == TYPE_BOOL and not report[key], "not claimed: " + key)
	for name: String in ["co", "co2", "hcn", "smoke_and_visibility", "fed", "svv", "fuel_mass", "gas_composition"]:
		_check(report.get("not_evaluated", []).has(name), "not evaluated: " + name)
	_check(String(report.get("not_evaluated_means", "")).contains("neither measured zeros nor a safe condition"), "zeros are not measurements")
	_check(String(report.get("gas_state", "")).contains("incomplete"), "the gas state is declared incomplete")
	_check(String(report.get("oxygen_is", "")).contains("not a validated stoichiometry"), "the oxygen debit is an equivalent demand")
	_check(String(report.get("radiative_term_is", "")).contains("not modelled"), "the radiative term has no modelled destination")
	_check(report.get("regime_criteria_are") == CouplingScript.REGIME_STATUS and report.get("regime", {}).get("status") == CouplingScript.REGIME_STATUS, "regime criteria are hypotheses")
	_check(report.get("radiative_fraction", {}).get("class") == "open_air_whole_test_estimate", "the fraction keeps its class")
	_check(report.get("scope") == CouplingScript.SCOPE and report.get("is_a_reproduction_of_the_input") == false, "scope, and not a reproduction until completed")
	_check(report.get("source_fingerprint") == _identity and report.get("oxygen_kg_per_MJ") == 0.076, "identity and coefficient")
	_check(CouplingScript.new().report().get("state") == CouplingScript.STATE_INACTIVE, "a coupling that was never armed is inactive")
	_observations["report_keys"] = report.keys()
	_free(bench)


# ---------------------------------------------------------------- helpers

func _template(spec: Dictionary) -> Dictionary:
	var rect := Rect2(0.0, 0.0, float(spec["width"]), float(spec["length"]))
	var openings: Array[Dictionary] = []
	var size: Array = spec["opening"]
	if size.size() == 2:
		openings.append({"a": ROOM_ID, "b": -1, "type": "door", "width_m": float(size[0]), "height_m": float(size[1]),
			"open_fraction": 1.0, "offset_m": 0.5, "offset_is_fraction": true, "sill_m": 0.0, "wall": "bottom"})
	var rooms: Array[Dictionary] = [{"id": ROOM_ID, "name": "Banco", "kind": "salon", "rect": rect,
		"height_m": float(spec["height"]), "fuel_energy_MJ": 0.0, "max_hrr_kw": 0.0}]
	return {"room_rect_m": {ROOM_ID: rect}, "rooms_data": rooms, "openings_data": openings}


## A building with one empty room and a real engine, with the switch still off.
func _bench(spec: Dictionary, dt: float) -> Dictionary:
	var building = BuildingModelScript.new()
	root.add_child(building)
	var loaded: bool = building.load_template_data(_template(spec))
	var engine = EngineScript.new()
	engine.building = building
	engine.enable_logging = false
	engine.auto_ignite_on_ready = false
	engine.auto_finish_on_extinction = false
	engine.energy_budget_enabled = true
	# The diagnostic is used to read the heat; its own warning about its residual is not judged here.
	engine.energy_budget_warn_fraction = 1.0e9
	engine.sim_fixed_dt = dt
	root.add_child(engine)
	var room = building.get_room(ROOM_ID)
	_check(loaded and room != null and engine.is_ready_for_validation() and room.fuel_objects.is_empty(), "the bench room exists, empty, and the engine is ready")
	return {"engine": engine, "building": building, "room": room}


func _armed(spec: Dictionary, dt: float, case: Dictionary) -> Dictionary:
	var bench: Dictionary = _bench(spec, dt)
	bench["engine"].g3_prescribed_thermal_source_enabled = true
	bench["engine"].g3_prescribed_thermal_source_case = case
	bench["engine"].reset_simulation(ROOM_ID, true)
	return bench


func _free(bench: Dictionary) -> void:
	bench["engine"].queue_free()
	bench["building"].queue_free()


func _chi(index: int) -> Dictionary:
	var row: Dictionary = _oracle["radiative_fractions"][index]
	return {"value": float(row["value"]), "class": String(row["class"]), "what": String(row["what"])}


func _case(chi: Dictionary, coefficient: float = 0.076, tolerance: float = 0.01, layer_m: float = 0.3,
		source: Dictionary = {}, identity: String = "") -> Dictionary:
	return {
		"schema": CouplingScript.CASE_SCHEMA, "room_id": ROOM_ID,
		"source": _source if source.is_empty() else source,
		"expected_source_fingerprint": _identity if identity.is_empty() else identity,
		"oxygen_kg_per_MJ": coefficient,
		"radiative_fraction": chi,
		"regime": {"oxygen_drop_tolerance": tolerance, "layer_interface_min_m": layer_m, "status": CouplingScript.REGIME_STATUS},
	}


func _with(case: Dictionary, key: String, value: Variant) -> Dictionary:
	var out: Dictionary = case.duplicate()
	out[key] = value
	return out


func _without(case: Dictionary, key: String) -> Dictionary:
	var out: Dictionary = case.duplicate()
	out.erase(key)
	return out


func _synthetic(points: Array) -> Dictionary:
	var samples: Array = []
	for point: Array in points:
		samples.append({"time_s": point[0], "hrr_kw": point[1]})
	var unknown: Dictionary = {}
	for key: String in SourceScript.UNKNOWN_KEYS:
		unknown[key] = null
	return {
		"schema": SourceScript.SOURCE_SCHEMA, "owner_id": "synthetic_object_as_tested", "run_id": "synthetic_run_1",
		"quantity": "measured_calorimetric_hrr", "time_unit": "s", "hrr_unit": "kW", "energy_unit": "kJ",
		"time_origin": "documented_ignition_event", "interpolation": "piecewise_linear",
		"outside_support": "reject", "negative_samples": "none_in_source", "regime": "open_air_as_tested",
		"provenance": {
			"dataset": "synthetic analytic table, not a measurement", "dataset_version": "v1",
			"license": "none needed", "source_file": "tests/fixtures/g3_object_hrr_thermal_coupling.gd",
			"source_sha256": "0".repeat(64), "source_column": "hrr_kw", "support_events": "0 to the last node",
			"importer": "written by hand", "table_fingerprint": "1".repeat(64),
		},
		"unknown": unknown, "samples": samples,
	}


func _float(value: Variant) -> float:
	return float(value) if typeof(value) in [TYPE_FLOAT, TYPE_INT] else NAN


func _positive(result: Variant) -> bool:
	return typeof(result) == TYPE_DICTIONARY and typeof(result.get("valid")) == TYPE_BOOL and result["valid"]


func _refused(result: Variant, label: String) -> void:
	_check(typeof(result) == TYPE_DICTIONARY and typeof(result.get("valid")) == TYPE_BOOL and not result["valid"]
		and typeof(result.get("errors")) == TYPE_ARRAY and not result["errors"].is_empty(), label + ": refused explicitly, with reasons")


func _near(actual: Variant, expected: float, label: String) -> void:
	var ok: bool = typeof(actual) == TYPE_FLOAT and not is_nan(actual) and not is_inf(actual)
	_check(ok and absf(actual - expected) <= ABS_TOL + REL_TOL * maxf(absf(actual), absf(expected)), label)


func _near_oxygen(actual: Variant, expected: float, label: String) -> void:
	var ok: bool = typeof(actual) == TYPE_FLOAT and not is_nan(actual) and not is_inf(actual)
	_check(ok and absf(actual - expected) <= 1.0e-13 + REL_TOL * maxf(absf(actual), absf(expected)), label)


func _group(title: String) -> void:
	_group_name = title.substr(0, 3)
	_groups.append(title)


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_failed = true
		_failure_count += 1
		_failures_by_group[_group_name] = int(_failures_by_group.get(_group_name, 0)) + 1
		# A few of every group are kept, so that a flood in one does not hide the others.
		if int(_failures_by_group[_group_name]) <= 8 and _failures.size() < MAX_KEPT_FAILURES * 2:
			_failures.append(_group_name + " " + label)

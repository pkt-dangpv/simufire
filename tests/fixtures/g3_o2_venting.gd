extends SceneTree

## Acceptance of stage M2-V of the oxygen authority, on the REAL SimulationEngine:
## the dilution of pressure venting is an operation of the owner of the room oxygen
## inventory, with an entry and an exit, on the inventory of stage M1 and with the
## selection of stage M2 untouched.
##
## What it judges: that a room that vents is not refused, that every venting event
## is one operation with the quantities the contract says, that nothing is clipped
## to a ceiling, that an event the owner cannot record writes nothing, and that the
## inventory and its transit still close. It MEASURES, without judging, what the
## fire does with the mode off and on.
##
## It validates no temperature, no fire behaviour, no CO, FED or SVV, and it does
## not say the dilution is a realistic distribution of the gas: a budget that
## closes does not prove that.
##
## On an engine without this stage the same checks fail one by one for what that
## engine does: the first venting event with a quantity refuses the run.
## Everything new is read with `get`, `in` and `has_method`.
##
## The smoke a venting event retires is read from the passive diagnostic counter the
## venting law already keeps (`phase3_diag_pressure_capped_vented_air_kg_total`): the
## smoke accumulator of the room also counts what leaves by other routes. Every world
## here turns that diagnostic on; it writes its own fields and nothing else.
const BuildingModelScript = preload("res://sim/BuildingModel.gd")
const EngineScript = preload("res://sim/core/SimulationEngine.gd")

## Oracle constants, written here and not read from the owner.
const O_M_O2_KG_PER_MOL: float = 2.0 * 15.999 / 1000.0
const O_M_DRY_AIR_KG_PER_MOL: float = 28.9647 / 1000.0
const O_REFERENCE_DENSITY_KG_M3: float = 1.2
const O_OXYGEN_KG_PER_MJ: float = 0.076
const O_CAP_FRACTION_PER_STEP: float = 0.05
const O_DELIVERY_DUE_S: float = 0.000001
## The share of the smoke a venting event retires that the historical law lets in as outside air.
const O_AIR_IN_PER_SMOKE_OUT: float = 0.40

## Budget gap accepted in every step, declared with stage M1 and not changed.
const GAP_KG: float = 1.0e-9
## One operation against its closed form: two ways of writing the same arithmetic.
const OPERATION_TOL_KG: float = 1.0e-12
const X_TOL: float = 1.0e-12
const AIR: float = 0.209
const ROOM_A: Dictionary = {"id": 0, "x": 0.0, "w": 5.0, "l": 4.0, "h": 2.4}
const ROOM_B: Dictionary = {"id": 1, "x": 5.0, "w": 4.0, "l": 4.0, "h": 2.4}
const VENTING: String = "pressure_venting"
const MAX_KEPT_FAILURES: int = 60

var _failed: bool = false
var _checks: int = 0
var _group_name: String = ""
var _groups: Array[String] = []
var _failures: Array[String] = []
var _failure_count: int = 0
var _failures_by_group: Dictionary = {}
var _observations: Dictionary = {}


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_no_venting()
	_a_room_that_vents()
	_sign_and_size()
	_two_steps_and_a_neighbour()
	_refused_whole()
	_life_cycle()
	# The mutation runner asks for the judged groups only; this one measures and judges nothing of the fire.
	if OS.get_environment("G3_O2_VENTING_JUDGED_ONLY") != "1":
		_effect_against_the_historical_route()
	print("G3_O2_VENTING " + JSON.stringify({"checks": _checks, "groups": _groups,
		"failures": _failures, "failure_count": _failure_count, "failures_by_group": _failures_by_group,
		"observations": _observations}, "", true, true))
	if _failed:
		quit(1)
	else:
		print("G3_O2_VENTING_PASS")
		quit(0)


# ---------------------------------------------------------------- V01

func _no_venting() -> void:
	_group("V01 with no venting there is no venting operation")
	# A room with a closed window and no fire: nothing pressurises it.
	var world: Dictionary = _world([ROOM_A], [_window()], {"dt": 0.25})
	var run: Dictionary = _measure(world, 80)
	_check(_valid(world) and run["events"] == 0 and run["smoke_retired_kg"] == 0.0, "cold room with a closed window: no event and no operation (%d)" % run["events"])
	_closes(run, "cold room")
	_free(world)
	# A room that burns with no way to the outside: it pressurises and has nowhere to vent.
	world = _world([ROOM_A], [], {"dt": 0.25, "fire": true})
	run = _measure(world, 720)
	var room = world["rooms"][0]
	_check(room.hrr_kj_total > 1000.0 and run["highest_pressure_pa"] > world["engine"].pressure_vent_threshold_pa,
		"sealed room: it burned and its pressure passed the threshold (%.1f Pa)" % run["highest_pressure_pa"])
	_check(_valid(world) and run["events"] == 0 and run["smoke_retired_kg"] == 0.0 and room.phase3_diag_pressure_raw_vented_air_kg_total == 0.0,
		"and with no way out there is no event and no operation")
	_closes(run, "sealed room")
	_free(world)


# ---------------------------------------------------------------- V02, V03, V06, V07

## One room with a closed window and a real fire: the case that refused the house.
func _a_room_that_vents() -> void:
	var world: Dictionary = _world([ROOM_A], [_window()], {"dt": 0.25, "fire": true})
	var room = world["rooms"][0]
	var start: float = _m(room)
	var run: Dictionary = _measure(world, 720)
	var totals: Dictionary = _totals_of(world, 0)
	_group("V02 the venting of a room that pressurises is an operation of the owner, and the run goes on")
	_check(run["smoke_retired_kg"] > 0.0, "the venting acted: it retired smoke (%s kg)" % str(run["smoke_retired_kg"]))
	_check(_valid(world) and run["steps_before_a_refusal"] == run["steps"], "the run is valid to its end (%d of %d steps)" % [run["steps_before_a_refusal"], run["steps"]])
	_check(run["events"] > 50, "venting events recorded as operations (%d)" % run["events"])
	_check(run["events"] == run["steps_with_smoke_retired"], "one operation in every step in which the venting retired smoke (%d of %d)" % [run["events"], run["steps_with_smoke_retired"]])
	_check(run["every_event_has_an_entry_and_an_exit"], "every event records an entry, an exit and the gas that entered, each above zero")
	_check((_report(world["engine"]).get("supported_routes", []) as Array).has(VENTING), "the owner names the route among the ones it supports")
	_group("V03 the quantities are the ones of the contract, by an oracle that calls nothing of the owner")
	_check(run["gas_is_the_law"], "the gas that enters is 0.40 of the smoke the event retired, in every event (worst %s kg)" % str(run["worst_gas_kg"]))
	_check(run["worst_operation_kg"] <= OPERATION_TOL_KG, "entry, exit and what is left are the closed forms of the dilution (worst %s kg)" % str(run["worst_operation_kg"]))
	_check(run["leaving_is_the_mixture"], "the gas leaves at the mole fraction of the mixture, not at the one of the room before")
	_closes(run, "room that vents")
	_check(absf(start + run["outside_kg"] - run["consumed_kg"] - _m(room)) <= GAP_KG, "the inventory ends at start plus exterior minus debit")
	_check(run["venting_net_kg"] > 0.0, "the venting gave oxygen back to a room the fire had depleted (%s kg)" % str(run["venting_net_kg"]))
	_group("V06 applied once: the totals and the accumulators say what the operations did")
	_check(run["events_per_room_and_step_at_most_one"], "never two venting operations of a room in a step")
	_check(int(totals.get("dilution_events", -1)) == run["events"], "the owner counts the same events (%s)" % str(totals.get("dilution_events")))
	_check(absf(float(totals.get("dilution_in_kg", NAN)) - run["venting_in_kg"]) <= GAP_KG and absf(float(totals.get("dilution_out_kg", NAN)) - run["venting_out_kg"]) <= GAP_KG
		and absf(float(totals.get("dilution_gas_kg", NAN)) - run["venting_gas_kg"]) <= GAP_KG, "and the same entry, exit and gas")
	_check(absf(float(totals.get("outside_in_kg", NAN)) - float(totals.get("outside_out_kg", NAN)) - run["outside_kg"]) <= GAP_KG,
		"the exchange with the outside of the owner is infiltration plus venting, once")
	_check(run["worst_accumulator_kg"] <= OPERATION_TOL_KG, "the exterior accumulator of the room moves in every step by the net the owner applied (worst %s kg)" % str(run["worst_accumulator_kg"]))
	_check(absf(room.o2_exterior_net_kg_total - run["outside_kg"]) <= GAP_KG, "and ends at that sum (%s against %s)" % [str(room.o2_exterior_net_kg_total), str(run["outside_kg"])])
	_group("V07 nobody writes the room number, and the selection of the step is not touched")
	_check(run["number_is_derived"] == run["steps"], "the room number is the one derived from the inventory in every step (%d of %d)" % [run["number_is_derived"], run["steps"]])
	_check(room.get("o2_unauthorized_write_count") == 0, "nobody wrote the room number behind the owner")
	_check(run["selection_keeps_the_opening"] == run["steps"], "the selection of every step keeps what the room held when the step opened (%d of %d)" % [run["selection_keeps_the_opening"], run["steps"]])
	_check(run["selection_served_to_fire_and_sink_only"], "it is served to the fire and to the sink, and to nobody else")
	_check(run["selection_ids_consecutive"], "and no selection is built in the middle of a step: the identifiers are consecutive")
	_check(run["highest_x"] <= AIR + X_TOL, "the room is never richer than the outside air")
	run["heat_MJ"] = room.hrr_kj_total / 1000.0
	_observe("room_that_vents", run)
	_free(world)


# ---------------------------------------------------------------- V04

## The venting law alone, on a cold room whose pressure and smoke are set here: equal
## to the outside, depleted and enriched. Three events each.
func _sign_and_size() -> void:
	_group("V04 sign and size: equal to the outside, depleted, and enriched with nothing clipped")
	for case: Array in [["equal to the outside", AIR], ["depleted", 0.15], ["enriched", 0.23]]:
		var world: Dictionary = _world([ROOM_A], [_window()], {"dt": 0.25})
		var engine = world["engine"]
		var room = world["rooms"][0]
		var label: String = String(case[0])
		_declare(world, 0, float(case[1]))
		var x: float = float(case[1])
		var m_room: float = room.volume_m3() * O_REFERENCE_DENSITY_KG_M3
		var worst: float = 0.0
		var events: int = 0
		var net_kg: float = 0.0
		var entered: bool = true
		var relieved: bool = true
		for _i: int in range(3):
			var event: Dictionary = _vent_once(world, 60.0, 2.0)
			if not bool(event["retired"]):
				continue
			var a: float = O_AIR_IN_PER_SMOKE_OUT * float(event["smoke_out_kg"])
			var expected: Dictionary = _oracle_dilution(float(event["m_before"]), a, m_room, AIR)
			x = (x * m_room + AIR * a) / (m_room + a)
			worst = maxf(worst, absf(_m(room) - float(expected["after_kg"])))
			worst = maxf(worst, absf(_oracle_x(_m(room), room.volume_m3()) - x) * m_room)
			var operation: Dictionary = event["operation"]
			if operation.is_empty():
				continue
			events += 1
			net_kg += float(operation["in_kg"]) - float(operation["out_kg"])
			entered = entered and float(operation["in_kg"]) > 0.0 and float(operation["out_kg"]) > 0.0
			worst = maxf(worst, absf(float(operation["in_kg"]) - float(expected["in_kg"])))
			worst = maxf(worst, absf(float(operation["out_kg"]) - float(expected["out_kg"])))
			relieved = relieved and float(event["pressure_after_pa"]) < float(event["pressure_relaxed_pa"]) and float(event["smoke_written_kg"]) > 0.0
		_check(events == 3 and entered, "%s: three events, each with an entry and an exit above zero (%d)" % [label, events])
		_check(relieved, "%s: and each retired smoke and relieved pressure, as an applied event does" % label)
		_check(worst <= OPERATION_TOL_KG, "%s: every event is the mixture of the historical law, with no clip (worst %s kg)" % [label, str(worst)])
		_check(_valid(world), "%s: the run is valid" % label)
		match label:
			"equal to the outside":
				_check(absf(net_kg) <= 1.0e-15 and absf(room.o2 - AIR) <= X_TOL, "equal to the outside: entry and exit cancel (net %s kg)" % str(net_kg))
			"depleted":
				_check(net_kg > 1.0e-6 and room.o2 > 0.15 and room.o2 < AIR, "depleted: the room gains oxygen and stays below the outside (net %s kg)" % str(net_kg))
			"enriched":
				_check(net_kg < -1.0e-7 and room.o2 < 0.23 and room.o2 > AIR + 0.02, "enriched: the room loses oxygen and stays above 0.209: nothing is clipped (net %s kg, x %s)" % [str(net_kg), str(room.o2)])
		_observations["sign " + label] = {"events": events, "net_kg": net_kg, "mole_fraction_at_the_end": room.o2, "worst_kg": worst}
		_free(world)


# ---------------------------------------------------------------- V05

## Two rooms with their door open, a real fire and a closed window in the one that
## burns, at two time steps: venting, interior exchange and transit in the same run.
func _two_steps_and_a_neighbour() -> void:
	_group("V05 two time steps, many events and a neighbour: the inventories and their transit close")
	for dt: float in [0.25, 0.125]:
		var world: Dictionary = _world([ROOM_A, ROOM_B], [_door(1.0), _window()], {"dt": dt, "fire": true})
		var run: Dictionary = _measure(world, int(round(150.0 / dt)))
		var label: String = "dt %s" % str(dt)
		_check(_valid(world) and run["steps_before_a_refusal"] == run["steps"], label + ": the run is valid to its end (%d of %d)" % [run["steps_before_a_refusal"], run["steps"]])
		_check(run["events"] > 50 and run["events"] == run["steps_with_smoke_retired"], label + ": many events, one operation each (%d)" % run["events"])
		_check(run["largest_transit_kg"] > 1.0e-4 and run["delayed"] > 0, label + ": oxygen was in transit while the room vented (%s kg)" % str(run["largest_transit_kg"]))
		_check(run["worst_operation_kg"] <= OPERATION_TOL_KG and run["gas_is_the_law"], label + ": every event is the closed form (worst %s kg)" % str(run["worst_operation_kg"]))
		_closes(run, label)
		run["heat_MJ"] = world["rooms"][0].hrr_kj_total / 1000.0
		_observe("two_rooms dt %s" % str(dt), run)
		_free(world)


# ---------------------------------------------------------------- V08

func _refused_whole() -> void:
	_group("V08 a quantity that is not valid is refused whole: no partial debit, and the event writes nothing")
	# 1. The operation itself, with quantities that are not amounts and fractions that are not fractions.
	for case: Array in [["a quantity that is not a number", NAN, AIR, "quantity_not_a_finite_amount"],
			["a negative quantity", -0.001, AIR, "quantity_not_a_finite_amount"],
			["an infinite quantity", INF, AIR, "quantity_not_a_finite_amount"],
			["a text", "0.1", AIR, "quantity_not_a_finite_amount"],
			["no quantity", null, AIR, "quantity_not_a_finite_amount"],
			["an outside fraction above one", 0.01, 1.5, "mole_fraction_not_a_fraction"],
			["a negative outside fraction", 0.01, -0.1, "mole_fraction_not_a_fraction"],
			["an outside fraction that is not a number", 0.01, NAN, "mole_fraction_not_a_fraction"]]:
		var world: Dictionary = _world([ROOM_A], [_window()], {"dt": 0.25})
		var inv = _inv(world["engine"])
		var room = world["rooms"][0]
		_declare(world, 0, 0.15)
		if inv == null or not inv.has_method("dilute_with_outside") or not inv.has_method("outside_dilution_would_apply"):
			_check(false, "%s: the owner has the operation of the dilution" % case[0])
			_free(world)
			continue
		var m: float = _m(room)
		_check(inv.outside_dilution_would_apply(room, case[1], case[2]) == false, "%s: the owner says beforehand that it would not apply" % case[0])
		_check(_same(_m(room), m) and inv.state() == "armed", "%s: asking writes nothing and refuses nothing" % case[0])
		var result: Dictionary = inv.dilute_with_outside(room, case[1], case[2], "fixture")
		_check(result.get("applied") == false and result.get("reason") == case[3], "%s is refused as %s (%s)" % [case[0], case[3], str(result.get("reason"))])
		_check(_same(_m(room), m) and inv.state() == "rejected", "%s: nothing is debited and the run is refused" % case[0])
		_free(world)
	# 2. A room that is not under this owner.
	var first: Dictionary = _world([ROOM_A], [_window()], {"dt": 0.25})
	var second: Dictionary = _world([ROOM_A], [_window()], {"dt": 0.25})
	var owner = _inv(first["engine"])
	var foreign = second["rooms"][0]
	if owner != null and owner.has_method("dilute_with_outside"):
		var m_foreign: float = _m(foreign)
		var refused: Dictionary = owner.dilute_with_outside(foreign, 0.01, AIR, "fixture")
		_check(refused.get("applied") == false and refused.get("reason") == "room_not_under_authority" and _same(_m(foreign), m_foreign),
			"the room of another owner is refused and not touched")
	else:
		_check(false, "the room of another owner: the owner has the operation of the dilution")
	_free(first)
	_free(second)
	# 3. The venting law itself, when the owner cannot record its event: the event writes nothing.
	var world: Dictionary = _world([ROOM_A], [_window()], {"dt": 0.25})
	var engine = world["engine"]
	var room = world["rooms"][0]
	_declare(world, 0, 0.15)
	world["building"].outside_o2 = 1.5
	var m: float = _m(room)
	var event: Dictionary = _vent_once(world, 60.0, 2.0)
	var report: Dictionary = _report(engine)
	var rejections: Array = report.get("rejections", [])
	_check(report.get("state") == "rejected" and rejections.size() == 1 and (rejections[0] as Dictionary).get("reason") == "mole_fraction_not_a_fraction"
		and (rejections[0] as Dictionary).get("cause") == VENTING, "an outside fraction that is not one: the venting event is refused by its name and its cause")
	_check(_same(_m(room), m) and room.get("o2_unauthorized_write_count") == 0, "nothing is debited and the room number is not written")
	_check(bool(event["retired"]), "the venting law did reach its event: its diagnostic counted what it was going to retire")
	_check(float(event["smoke_written_kg"]) == 0.0 and room.smoke_kg == 2.0 and float(event["co2_after"]) == float(event["co2_before"])
		and float(event["pressure_after_pa"]) == float(event["pressure_relaxed_pa"]),
		"and the event retired no smoke and no gas and relieved no pressure: it wrote nothing of its own (smoke %s kg)" % str(room.smoke_kg))
	# 4. And again with the owner already refused: no way back to the historical write.
	world["building"].outside_o2 = AIR
	var number: float = room.o2
	event = _vent_once(world, 60.0, 2.0)
	_check(float(event["smoke_written_kg"]) == 0.0 and room.smoke_kg == 2.0 and float(event["co2_after"]) == float(event["co2_before"]),
		"with the owner refused, the next event writes nothing either")
	_check(_same(_m(room), m) and room.o2 == number and room.get("o2_unauthorized_write_count") == 0, "and there is no historical write of the room number in its place")
	_free(world)


# ---------------------------------------------------------------- V09

func _life_cycle() -> void:
	_group("V09 a reset, a revocation and an engine with no owner")
	var world: Dictionary = _world([ROOM_A], [_window()], {"dt": 0.25, "fire": true})
	var engine = world["engine"]
	var room = world["rooms"][0]
	var first: Dictionary = _measure(world, 480)
	_check(first["events"] > 20 and int(_totals_of(world, 0).get("dilution_events", -1)) == first["events"], "first run: it vented (%d events)" % first["events"])
	engine.reset_simulation(0, true)
	var totals: Dictionary = _totals_of(world, 0)
	_check(_report(engine).get("state") == "armed" and totals.get("dilution_events") == 0 and totals.get("dilution_in_kg") == 0.0 and totals.get("dilution_out_kg") == 0.0
		and totals.get("outside_in_kg") == 0.0 and absf(room.o2 - AIR) <= X_TOL, "reset: no venting of the run before is left, and the room is at the air of the start")
	var second: Dictionary = _measure(world, 480)
	_check(_digest(first) == _digest(second) and _digest(first) != "", "reset: the same run gives the same inventories, numbers and events")
	_closes(second, "second run")
	# Revoked on the same engine: no owner, and the venting writes the room number as it did before.
	_switch(engine, false)
	engine.reset_simulation(0, true)
	_check(_report(engine).get("state") == "inactive" and engine.get("_o2_room_inventory") == null
		and engine.gas_exchange_system.get("room_o2_inventory") == null, "revoked: the venting holds no owner")
	_advance(world, 480)
	_check(room.get("o2_inventory_authority") == false and room.smoke_vented_kg_total > 0.0 and room.o2_exterior_net_kg_total > 0.0 and room.o2 < AIR,
		"revoked: the room vents by the historical route, which writes its number (%s kg from outside)" % str(room.o2_exterior_net_kg_total))
	_free(world)
	# An engine that never had the mode: the same historical route.
	world = _world([ROOM_A], [_window()], {"dt": 0.25, "fire": true, "inventory": false})
	_advance(world, 480)
	room = world["rooms"][0]
	_check(_report(world["engine"]).get("state") == "inactive" and room.smoke_vented_kg_total > 0.0 and room.o2_exterior_net_kg_total > 0.0,
		"with no owner at all the venting is the historical one")
	_free(world)


# ---------------------------------------------------------------- V10 (measured, not judged)

func _effect_against_the_historical_route() -> void:
	_group("V10 the effect against the historical route is measured (not a criterion)")
	var both: Dictionary = {}
	for mode_on: bool in [false, true]:
		var world: Dictionary = _world([ROOM_A], [_window()], {"dt": 0.25, "fire": true, "inventory": mode_on})
		var engine = world["engine"]
		var room = world["rooms"][0]
		var peak_kw: float = 0.0
		var lowest_number: float = INF
		var steps: int = 0
		while steps < 1200 and str(engine.get("o2_room_inventory_failure")) in ["", "<null>"]:
			engine.step(world["dt"])
			steps += 1
			peak_kw = maxf(peak_kw, room.hrr_kw)
			lowest_number = minf(lowest_number, room.o2)
		var totals: Dictionary = _totals_of(world, 0)
		both["on" if mode_on else "off"] = {
			"steps": steps, "time_s": engine.sim_time_s, "peak_kw": peak_kw, "heat_MJ": room.hrr_kj_total / 1000.0,
			"power_at_the_end_kw": room.hrr_kw, "lowest_room_number": lowest_number, "room_number_at_the_end": room.o2,
			"smoke_vented_kg": room.smoke_vented_kg_total, "exterior_accumulator_kg": room.o2_exterior_net_kg_total,
			"debit_of_the_room_kg": room.o2_consumed_bulk_kg_total,
			"venting_events": totals.get("dilution_events"), "venting_in_kg": totals.get("dilution_in_kg"),
			"venting_out_kg": totals.get("dilution_out_kg"), "venting_gas_kg": totals.get("dilution_gas_kg"),
			"clipped_by_the_cap_kg": float(totals.get("consumption_clipped_kg", 0.0)),
			"failure": str(engine.get("o2_room_inventory_failure")), "rejections": _report(engine).get("rejections", []),
		}
		_free(world)
	_check(float(both["off"]["heat_MJ"]) > 5.0 and float(both["off"]["smoke_vented_kg"]) > 0.0, "the historical route burned and vented")
	_check(both["on"]["failure"] == "" and int(both["on"]["steps"]) == 1200, "the mode ran the whole 300 s without refusing")
	_observations["effect room_that_vents"] = both


# ---------------------------------------------------------------- judging helpers

## The three budgets of a measured run, each within the accepted gap in every step.
func _closes(acc: Dictionary, label: String) -> void:
	_check(acc["inventory_read"], label + ": the inventory is read from the rooms")
	_check(acc["room_gap_kg"] <= GAP_KG, label + ": every room changes by its operations (worst %s kg)" % str(acc["room_gap_kg"]))
	_check(acc["building_gap_kg"] <= GAP_KG, label + ": inventories plus transit change by exterior minus debit (worst %s kg)" % str(acc["building_gap_kg"]))
	_check(acc["oracle_gap_kg"] <= GAP_KG, label + ": and by what the closed forms say (worst %s kg)" % str(acc["oracle_gap_kg"]))
	_check(acc["lowest_inventory_kg"] >= 0.0, label + ": no inventory below zero")


func _valid(world: Dictionary) -> bool:
	var report: Dictionary = _report(world["engine"])
	return report.get("state") == "armed" and (report.get("rejections", []) as Array).is_empty() \
			and world["engine"].get("o2_room_inventory_failure") == ""


# ---------------------------------------------------------------- measuring

## Steps the world and, in every step, reads the operations of the owner, the smoke
## the venting retired, the selections and three budgets:
## - by operations: every room changes by the operations the owner applied to it;
## - of the building: inventories plus transit change by exterior minus debit;
## - by closed form: the debit is the demand of the power of the step, capped at 5 %
##   of what the room holds when the sink runs; the infiltration is its law on that
##   same content; and every venting event is the dilution of the contract, with the
##   gas taken from the smoke the event retired and not from the operation. The
##   content the venting finds is taken from the state in a room with no neighbour
##   and from the record of the event otherwise, where the interior exchange of the
##   same step has moved it.
func _measure(world: Dictionary, steps: int) -> Dictionary:
	var acc: Dictionary = {"steps": 0, "steps_before_a_refusal": 0, "inventory_read": true,
		"events": 0, "steps_with_smoke_retired": 0, "smoke_retired_kg": 0.0, "every_event_has_an_entry_and_an_exit": true,
		"events_per_room_and_step_at_most_one": true, "gas_is_the_law": true, "worst_gas_kg": 0.0, "worst_operation_kg": 0.0,
		"leaving_is_the_mixture": true, "venting_in_kg": 0.0, "venting_out_kg": 0.0, "venting_net_kg": 0.0, "venting_gas_kg": 0.0,
		"largest_event_gas_kg": 0.0, "worst_accumulator_kg": 0.0, "number_is_derived": 0, "selection_keeps_the_opening": 0,
		"selection_served_to_fire_and_sink_only": true, "selection_ids_consecutive": true,
		"room_gap_kg": 0.0, "building_gap_kg": 0.0, "oracle_gap_kg": 0.0, "largest_transit_kg": 0.0, "lowest_inventory_kg": INF,
		"delayed": 0, "consumed_kg": 0.0, "clipped_kg": 0.0, "outside_kg": 0.0, "highest_x": 0.0, "peak_kw": 0.0,
		"highest_pressure_pa": 0.0, "digest_values": PackedFloat64Array()}
	var engine = world["engine"]
	var dt: float = float(world["dt"])
	var rooms: Array = world["rooms"]
	var alone: bool = rooms.size() == 1
	var last_selection_id: int = _largest_selection_id(_report(engine))
	for _i: int in range(steps):
		var before: Dictionary = _snapshot(world)
		engine.step(dt)
		acc["steps"] += 1
		# A refused run is not measured further: the engine does not step and the record of its last step stays.
		if str(engine.get("o2_room_inventory_failure")) != "":
			continue
		acc["steps_before_a_refusal"] += 1
		var after: Dictionary = _snapshot(world)
		var report: Dictionary = _report(engine)
		var operations: Array = report.get("step_operations", [])
		var selections: Dictionary = report.get("selections", {})
		var effects: Dictionary = _effects(world, operations)
		var expected_change_kg: float = 0.0
		var retired_in_the_step: bool = false
		for room in rooms:
			var m_before: float = float(before["m"][room.id])
			var m_after: float = float(after["m"][room.id])
			if is_nan(m_before) or is_nan(m_after):
				acc["inventory_read"] = false
				continue
			acc["room_gap_kg"] = maxf(acc["room_gap_kg"], absf(m_after - m_before - float(effects["by_room"][room.id])))
			acc["lowest_inventory_kg"] = minf(acc["lowest_inventory_kg"], m_after)
			acc["highest_x"] = maxf(acc["highest_x"], room.o2)
			acc["peak_kw"] = maxf(acc["peak_kw"], room.hrr_kw)
			acc["highest_pressure_pa"] = maxf(acc["highest_pressure_pa"], room.overpressure_pa)
			acc["digest_values"].append(m_after)
			acc["digest_values"].append(room.o2)
			if absf(room.o2 - _oracle_x(m_after, room.volume_m3())) <= X_TOL and room == rooms[0]:
				acc["number_is_derived"] += 1
			# --- the oxygen step, by closed form ---
			var held_kg: float = m_before + float(before["due"].get(room.id, 0.0))
			var demand_kg: float = float(room.hrr_kw) / 1000.0 * O_OXYGEN_KG_PER_MJ * dt
			var debit_kg: float = minf(demand_kg, held_kg * O_CAP_FRACTION_PER_STEP)
			var gas_kg: float = room.volume_m3() * (engine.ach_infiltration / 3600.0) * O_REFERENCE_DENSITY_KG_M3 * dt
			var oxygen_step_kg: float = _oracle_parcel_kg(world["building"].outside_o2 - _oracle_x(held_kg, room.volume_m3()), gas_kg) - debit_kg
			expected_change_kg += oxygen_step_kg
			# --- the venting of the room in this step ---
			var smoke_out_kg: float = float(after["smoke_vented"][room.id]) - float(before["smoke_vented"][room.id])
			var events: Array = effects["venting"].get(room.id, [])
			if smoke_out_kg > 0.0:
				retired_in_the_step = true
				acc["smoke_retired_kg"] += smoke_out_kg
			if events.size() > 1:
				acc["events_per_room_and_step_at_most_one"] = false
			for event: Dictionary in events:
				acc["events"] += 1
				var a: float = O_AIR_IN_PER_SMOKE_OUT * smoke_out_kg
				var gas_gap: float = absf(float(event.get("gas_kg", NAN)) - a)
				acc["worst_gas_kg"] = maxf(acc["worst_gas_kg"], gas_gap)
				if not (gas_gap <= 1.0e-15):
					acc["gas_is_the_law"] = false
				var found_kg: float = held_kg + oxygen_step_kg if alone else float(event.get("before_kg", NAN))
				var m_room: float = room.volume_m3() * O_REFERENCE_DENSITY_KG_M3
				var expected: Dictionary = _oracle_dilution(found_kg, a, m_room, world["building"].outside_o2)
				expected_change_kg += float(expected["in_kg"]) - float(expected["out_kg"])
				var in_kg: float = float(event.get("in_kg", NAN))
				var out_kg: float = float(event.get("out_kg", NAN))
				if not (in_kg > 0.0 and out_kg > 0.0 and float(event.get("gas_kg", NAN)) > 0.0):
					acc["every_event_has_an_entry_and_an_exit"] = false
				var exact: Dictionary = _oracle_dilution(float(event.get("before_kg", NAN)), a, m_room, world["building"].outside_o2)
				var worst: float = maxf(absf(in_kg - float(exact["in_kg"])), maxf(absf(out_kg - float(exact["out_kg"])),
					absf(float(event.get("after_kg", NAN)) - float(exact["after_kg"]))))
				acc["worst_operation_kg"] = maxf(acc["worst_operation_kg"], worst if not is_nan(worst) else INF)
				if not (absf(float(event.get("leaving_mole_fraction", NAN)) - float(exact["mixture_x"])) <= X_TOL):
					acc["leaving_is_the_mixture"] = false
				acc["venting_in_kg"] += in_kg
				acc["venting_out_kg"] += out_kg
				acc["venting_net_kg"] += in_kg - out_kg
				acc["venting_gas_kg"] += float(event.get("gas_kg", NAN))
				acc["largest_event_gas_kg"] = maxf(acc["largest_event_gas_kg"], float(event.get("gas_kg", 0.0)))
				acc["digest_values"].append(in_kg)
				acc["digest_values"].append(out_kg)
			# --- the exterior accumulator of the room: what the owner applied, once ---
			var accumulated: float = float(after["exterior"][room.id]) - float(before["exterior"][room.id])
			acc["worst_accumulator_kg"] = maxf(acc["worst_accumulator_kg"], absf(accumulated - float(effects["outside_by_room"][room.id])))
			# --- the selection of the step: the one built when it opened ---
			var selection: Dictionary = selections.get(room.id, {})
			if not selection.is_empty():
				if room == rooms[0] and absf(float(selection.get("inventory_kg", NAN)) - m_before) <= 1.0e-15 \
						and absf(float(selection.get("mole_fraction", NAN)) - _oracle_x(m_before, room.volume_m3())) <= X_TOL:
					acc["selection_keeps_the_opening"] += 1
				for consumer: Variant in selection.get("served_to", []):
					if not ["fire", "sink"].has(consumer):
						acc["selection_served_to_fire_and_sink_only"] = false
		if retired_in_the_step:
			acc["steps_with_smoke_retired"] += 1
		var largest_id: int = _largest_selection_id(report)
		if largest_id != last_selection_id + rooms.size():
			acc["selection_ids_consecutive"] = false
		last_selection_id = largest_id
		if not acc["inventory_read"]:
			continue
		var total_change_kg: float = float(after["total"]) - float(before["total"])
		acc["building_gap_kg"] = maxf(acc["building_gap_kg"], absf(total_change_kg - (float(effects["outside_kg"]) - float(effects["consumed_kg"]))))
		acc["oracle_gap_kg"] = maxf(acc["oracle_gap_kg"], absf(total_change_kg - expected_change_kg))
		acc["largest_transit_kg"] = maxf(acc["largest_transit_kg"], absf(float(after["transit"])))
		acc["consumed_kg"] += float(effects["consumed_kg"])
		acc["clipped_kg"] += float(effects["clipped_kg"])
		acc["outside_kg"] += float(effects["outside_kg"])
		acc["delayed"] += int(effects["delayed"])
		acc["digest_values"].append(float(after["transit"]))
	return acc


## What the operations of a step did, room by room. A delayed exchange changes the
## donor only: the receiver changes when its entry arrives, and only then.
func _effects(world: Dictionary, operations: Array) -> Dictionary:
	var by_room: Dictionary = {}
	var outside_by_room: Dictionary = {}
	for room in world["rooms"]:
		by_room[room.id] = 0.0
		outside_by_room[room.id] = 0.0
	var out: Dictionary = {"by_room": by_room, "outside_by_room": outside_by_room, "venting": {},
		"outside_kg": 0.0, "consumed_kg": 0.0, "clipped_kg": 0.0, "delayed": 0}
	for operation: Dictionary in operations:
		match String(operation.get("kind", "")):
			"consume":
				by_room[int(operation["room"])] -= float(operation["applied_kg"])
				out["consumed_kg"] += float(operation["applied_kg"])
				out["clipped_kg"] += float(operation["clipped_kg"])
			"outside":
				var net_kg: float = float(operation["in_kg"]) - float(operation["out_kg"])
				by_room[int(operation["room"])] += net_kg
				outside_by_room[int(operation["room"])] += net_kg
				out["outside_kg"] += net_kg
				if String(operation.get("cause", "")) == VENTING:
					out["venting"][int(operation["room"])] = out["venting"].get(int(operation["room"]), []) + [operation]
			"interior":
				by_room[int(operation["donor"])] += float(operation["to_donor_kg"]) - float(operation["to_receiver_kg"])
				if bool(operation["delayed"]):
					out["delayed"] += 1
				else:
					by_room[int(operation["receiver"])] += float(operation["to_receiver_kg"]) - float(operation["to_donor_kg"])
			"arrival":
				by_room[int(operation["room"])] += float(operation["net_kg"])
	return out


## What the state shows before a step: the inventory of every room, the transit, what
## is due to every room within the step, and the smoke and exterior accumulators.
func _snapshot(world: Dictionary) -> Dictionary:
	var report: Dictionary = _report(world["engine"])
	var dt: float = float(world["dt"])
	var m: Dictionary = {}
	var due: Dictionary = {}
	var smoke_vented: Dictionary = {}
	var exterior: Dictionary = {}
	var total: float = 0.0
	for room in world["rooms"]:
		m[room.id] = _m(room)
		total += _m(room)
		smoke_vented[room.id] = room.phase3_diag_pressure_capped_vented_air_kg_total
		exterior[room.id] = room.o2_exterior_net_kg_total
	var transit: float = 0.0
	for entry: Dictionary in report.get("transit", []):
		var receiver: int = int(entry["receiver"])
		transit += float(entry["net_kg"])
		if maxf(0.0, float(entry["delay_s"]) - dt) <= O_DELIVERY_DUE_S:
			due[receiver] = float(due.get(receiver, 0.0)) + float(entry["net_kg"])
	return {"m": m, "due": due, "transit": transit, "total": total + transit, "smoke_vented": smoke_vented, "exterior": exterior}


## One call of the venting law of the gas exchange, alone, on a room whose pressure
## and smoke are set here. Returns what the state showed before and after, and the
## operation the owner recorded, if any.
func _vent_once(world: Dictionary, overpressure_pa: float, smoke_kg: float) -> Dictionary:
	var engine = world["engine"]
	var room = world["rooms"][0]
	room.overpressure_pa = overpressure_pa
	room.smoke_kg = smoke_kg
	room.co2_kg = 0.5
	var recorded: int = (_report(engine).get("step_operations", []) as Array).size()
	var vented: float = room.phase3_diag_pressure_capped_vented_air_kg_total
	var written: float = room.smoke_vented_kg_total
	var out: Dictionary = {"m_before": _m(room), "co2_before": room.co2_kg}
	engine.gas_exchange_system.step_pressure_venting(world["building"], float(world["dt"]), engine._build_gas_exchange_hooks())
	# Only this law ran: what the smoke accumulator of the room moved is what the event wrote.
	out["smoke_written_kg"] = room.smoke_vented_kg_total - written
	out["pressure_after_pa"] = room.overpressure_pa
	# The pressure model relaxes the pressure before the venting decides, and its diagnostic keeps
	# that value; an event that is applied relieves the pressure further.
	out["pressure_relaxed_pa"] = room.phase3_diag_pressure_model_pa
	out["smoke_out_kg"] = room.phase3_diag_pressure_capped_vented_air_kg_total - vented
	out["retired"] = float(out["smoke_out_kg"]) > 0.0
	out["co2_after"] = room.co2_kg
	var operations: Array = _report(engine).get("step_operations", [])
	out["operation"] = {}
	for index: int in range(recorded, operations.size()):
		if (operations[index] as Dictionary).get("cause") == VENTING:
			out["operation"] = operations[index]
	return out


func _advance(world: Dictionary, steps: int) -> void:
	for _i: int in range(steps):
		world["engine"].step(float(world["dt"]))


func _declare(world: Dictionary, room_id: int, mole_fraction: float) -> void:
	if world["engine"].has_method("o2_room_inventory_declare_initial_mole_fraction"):
		world["engine"].call("o2_room_inventory_declare_initial_mole_fraction", room_id, mole_fraction)


func _digest(acc: Dictionary) -> String:
	var values: PackedFloat64Array = acc.get("digest_values", PackedFloat64Array())
	if values.is_empty():
		return ""
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(values.to_byte_array())
	return context.finish().hex_encode()


func _largest_selection_id(report: Dictionary) -> int:
	var largest: int = -1
	for selection: Dictionary in (report.get("selections", {}) as Dictionary).values():
		largest = maxi(largest, int(selection.get("id", -1)))
	return largest


func _observe(name: String, acc: Dictionary) -> void:
	var kept: Dictionary = {}
	for key: String in acc.keys():
		if key != "digest_values":
			kept[key] = acc[key]
	_observations[name] = kept


# ---------------------------------------------------------------- reading the mode

func _switch(engine, value: bool) -> void:
	if "o2_room_inventory_enabled" in engine:
		engine.set("o2_room_inventory_enabled", value)


func _inv(engine):
	return engine.get("_o2_room_inventory")


func _m(room) -> float:
	var value: Variant = room.get("o2_inventory_kg")
	return float(value) if typeof(value) == TYPE_FLOAT else NAN


func _report(engine) -> Dictionary:
	if not engine.has_method("get_o2_room_inventory_report"):
		return {"state": "absent"}
	return engine.call("get_o2_room_inventory_report")


func _totals_of(world: Dictionary, room_id: int) -> Dictionary:
	return _report(world["engine"]).get("rooms", {}).get(room_id, {})


# ---------------------------------------------------------------- oracle

func _oracle_x(o2_kg: float, volume_m3: float) -> float:
	return o2_kg / ((volume_m3 * O_REFERENCE_DENSITY_KG_M3 / O_M_DRY_AIR_KG_PER_MOL) * O_M_O2_KG_PER_MOL)


func _oracle_parcel_kg(mole_fraction: float, gas_kg: float) -> float:
	return mole_fraction * (gas_kg / O_M_DRY_AIR_KG_PER_MOL) * O_M_O2_KG_PER_MOL


## The dilution of the contract: `a` kg of outside gas enter, mix with the `m_room` kg
## of reference gas of the room, and `a` kg of that mixture leave.
func _oracle_dilution(held_kg: float, a: float, m_room: float, outside_x: float) -> Dictionary:
	var in_kg: float = outside_x * a * O_M_O2_KG_PER_MOL / O_M_DRY_AIR_KG_PER_MOL
	var after_kg: float = (held_kg + in_kg) * m_room / (m_room + a)
	return {"in_kg": in_kg, "after_kg": after_kg, "out_kg": (held_kg + in_kg) * a / (m_room + a),
		"mixture_x": (held_kg + in_kg) / ((m_room + a) * O_M_O2_KG_PER_MOL / O_M_DRY_AIR_KG_PER_MOL)}


# ---------------------------------------------------------------- building

func _world(specs: Array, openings: Array, options: Dictionary) -> Dictionary:
	# The building enters the tree first: its `_ready` loads the product preset and
	# would replace a template loaded before it.
	var building = BuildingModelScript.new()
	root.add_child(building)
	var rooms: Array = []
	var rects: Dictionary = {}
	for spec: Dictionary in specs:
		var burning: bool = bool(options.get("fire", false)) and int(spec["id"]) == 0
		var room: Dictionary = {
			"id": int(spec["id"]), "name": "Sala%d" % int(spec["id"]), "kind": "salon" if burning else "pasillo",
			"floor_level_z_m": 0.0, "height_m": float(spec["h"]), "rotation_deg": 0.0,
			"fuel_energy_MJ": 0.0, "max_hrr_kw": 0.0, "fuel_objects": [],
		}
		if burning:
			room["fuel_energy_MJ"] = 1100.0
			room["max_hrr_kw"] = 700.0
			room["fuel_objects"] = [{
				"id": "sofa", "kind": "mobiliario_tapizado", "name": "Sofa",
				"fuel_energy_MJ": 1100.0, "remaining_fuel_MJ": 1100.0, "max_hrr_kw": 700.0,
				"co_yield_kg_per_MJ": 0.0004, "smoke_yield_kg_per_MJ": 0.012,
				"o2_consumption_kg_per_MJ": 0.076, "elevation_m": 0.38,
				"exposed_area_m2": 3.6, "footprint_m2": 2.1, "ignition_flux_kw_m2": 16.0,
				"ignition_temp_c": 310.0, "is_primary_ignition_source": true,
				"position_m": {"x": 1.0, "y": 1.2}, "size_m": {"x": 0.9, "y": 2.35},
				"room_id": 0, "rotation_deg": 0.0,
			}]
		rooms.append(room)
		rects[str(int(spec["id"]))] = {"x": float(spec["x"]), "y": 0.0, "w": float(spec["w"]), "h": float(spec["l"])}
	building.load_template_data({
		"building_type": "house", "floors": [{"level_m": 0.0, "name": "PB"}], "rooms_data": rooms,
		"room_rect_m": rects, "openings_data": openings, "ignition_room_id": 0, "hvac_mode": "none",
	})
	var engine = EngineScript.new()
	engine.building = building
	engine.auto_ignite_on_ready = false
	engine.auto_finish_on_extinction = false
	engine.enable_logging = false
	engine.enable_csv_log = false
	engine.sim_fixed_dt = float(options["dt"])
	# Passive: the venting law counts what it retires. See the head of this file.
	engine.phase3_zone_diagnostics_enabled = true
	if bool(options.get("inventory", true)):
		_switch(engine, true)
	engine.suppress_exit_graphs()
	root.add_child(engine)
	engine.reset_simulation(0, bool(options.get("fire", false)))
	var models: Array = []
	for spec: Dictionary in specs:
		models.append(building.get_room(int(spec["id"])))
	return {"engine": engine, "building": building, "rooms": models, "dt": float(options["dt"])}


func _door(open_fraction: float) -> Dictionary:
	return {"a": 0, "b": 1, "type": "door", "width_m": 0.9, "height_m": 2.0, "sill_m": 0.0, "offset_m": 0.5,
		"offset_is_fraction": true, "open_fraction": open_fraction, "wall": "", "hinge_side": "left", "swing_direction": "in"}


## A closed window to the outside: the venting leaks through its frame.
func _window() -> Dictionary:
	return {"a": 0, "b": -1, "type": "window", "width_m": 1.2, "height_m": 1.2, "sill_m": 0.9, "offset_m": 0.5,
		"offset_is_fraction": true, "open_fraction": 0.0, "wall": "bottom"}


func _free(world: Dictionary) -> void:
	world["engine"].queue_free()
	world["building"].queue_free()


# ---------------------------------------------------------------- checks

func _same(a: float, b: float) -> bool:
	return a == b or (is_nan(a) and is_nan(b))


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

extends SceneTree

## Acceptance of stage M1 of the oxygen authority, on the REAL SimulationEngine: the
## oxygen inventory of a room and the oxygen in transit as state, the room number
## derived from it, every write through one owner.
##
## It judges conservation and ownership. It validates no temperature, no fire
## behaviour, no CO, FED or SVV, and it does not say the numbers resemble a test.
##
## Every expected number comes from a closed form written here with its own
## constants, never from the functions of the owner under test: the molar masses,
## the infiltration law, the demand of a known power, the heat the room reports.
## What the engine did is read where it is: the inventory in the room, the queue
## in transit and the operations of the step.
##
## Everything of the new mode is read with `get`, `in` and `has_method`, so that
## on an engine without the mode the checks fail one by one for the missing
## behaviour and not for a script error.
## A refusal counts only when it is explicit.
const BuildingModelScript = preload("res://sim/BuildingModel.gd")
const EngineScript = preload("res://sim/core/SimulationEngine.gd")

## Oracle constants, written here and not read from the owner.
const O_M_O2_KG_PER_MOL: float = 2.0 * 15.999 / 1000.0
const O_M_DRY_AIR_KG_PER_MOL: float = 28.9647 / 1000.0
const O_REFERENCE_DENSITY_KG_M3: float = 1.2
const O_OXYGEN_KG_PER_MJ: float = 0.076
const O_CAP_FRACTION_PER_STEP: float = 0.05
const O_DELIVERY_DUE_S: float = 0.000001

## Budget gap accepted in every step: four orders above the rounding measured on
## the historical route and more than five below the smallest debit of a step.
const GAP_KG: float = 1.0e-9
const X_TOL: float = 1.0e-12
const REL_TOL: float = 1.0e-12
const AIR: float = 0.209
const ROOM_A: Dictionary = {"id": 0, "x": 0.0, "w": 5.0, "l": 4.0, "h": 2.4}
const ROOM_B: Dictionary = {"id": 1, "x": 5.0, "w": 4.0, "l": 4.0, "h": 2.4}
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
	_off_by_default()
	_conversions()
	_state_and_not_a_counter()
	_rest()
	_controlled_demand()
	_real_fire()
	_transport()
	_exterior()
	_open_and_close()
	_layers_do_not_write_the_inventory()
	_cap()
	_reset_and_reuse()
	_refused_configurations()
	_transit_integrity()
	print("G3_O2_ROOM_INVENTORY " + JSON.stringify({"checks": _checks, "groups": _groups,
		"failures": _failures, "failure_count": _failure_count, "failures_by_group": _failures_by_group,
		"observations": _observations}, "", true, true))
	if _failed:
		quit(1)
	else:
		print("G3_O2_ROOM_INVENTORY_PASS")
		quit(0)


# ---------------------------------------------------------------- B01

func _off_by_default() -> void:
	_group("B01 off by default, not exported, and the historical route with it off")
	var world: Dictionary = _world([ROOM_A, ROOM_B], [_door(1.0)], {"dt": 0.25, "fire": true, "inventory": false})
	var engine = world["engine"]
	_check("o2_room_inventory_enabled" in engine, "the engine has the switch")
	_check(engine.get("o2_room_inventory_enabled") == false, "the switch is off by default")
	var exported: bool = false
	var found: bool = false
	for property: Dictionary in engine.get_property_list():
		if String(property["name"]) == "o2_room_inventory_enabled":
			found = true
			exported = (int(property["usage"]) & (PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_STORAGE)) != 0
	_check(found and not exported, "the switch is neither exported nor stored")
	_check(_report(engine).get("state") == "inactive", "with the switch off the report is inactive")
	_advance(world, 40)
	var room = world["rooms"][0]
	_check(engine.get("_o2_room_inventory") == null, "with the switch off no owner is ever created")
	_check(engine.oxygen_exchange_system.get("room_o2_inventory") == null
		and engine.gas_exchange_system.get("room_o2_inventory") == null, "with the switch off the subsystems hold no owner")
	_check(room.get("o2_inventory_authority") == false and is_nan(_m(room)), "with the switch off no room is under authority")
	_check(room.o2 < AIR and room.o2_consumed_bulk_kg_total > 0.0, "with the switch off the historical route burns and writes the room number")
	_free(world)
	world = _world([ROOM_A, ROOM_B], [_door(1.0)], {"dt": 0.5})
	engine = world["engine"]
	var report: Dictionary = _report(engine)
	_check(report.get("state") == "armed" and int(report.get("generation", 0)) >= 1, "with the switch on the inventory arms")
	_check(engine.get("o2_room_inventory_failure") == "", "armed with no failure")
	for item in world["rooms"]:
		_check(item.get("o2_inventory_authority") == true and is_finite(_m(item)) and _m(item) > 0.0,
			"room %d is under authority with a finite inventory" % item.id)
	_check(engine.oxygen_exchange_system.get("room_o2_inventory") != null, "the oxygen system holds the owner")
	_check(report.get("units", {}).get("inventory") == "kg of O2", "the report states its unit")
	_check(report.get("transit_owner", "") != "" and (report.get("approximations", []) as Array).size() >= 4,
		"the report states who owns the transit and its approximations")
	_free(world)


# ---------------------------------------------------------------- B02

func _conversions() -> void:
	_group("B02 conversions against an independent oracle: 0.209 is a mole fraction")
	var world: Dictionary = _world([ROOM_A, ROOM_B], [_door(1.0)], {"dt": 0.5})
	var a = world["rooms"][0]
	var b = world["rooms"][1]
	_near_rel(_m(a), _oracle_kg(AIR, 48.0), "48 m3 at 0.209 hold the oracle kilograms")
	_near_rel(_m(b), _oracle_kg(AIR, 38.4), "38.4 m3 at 0.209 hold the oracle kilograms")
	_check(absf(_m(a) - 13.2991) < 0.0001, "that is 13.299 kg of O2, the dry air figure")
	_check(_m(a) - AIR * 48.0 * O_REFERENCE_DENSITY_KG_M3 > 1.0, "and not the mole fraction multiplied by the mass of gas (12.038 kg)")
	_check(absf(a.o2 - AIR) <= X_TOL, "the derived number is the declared mole fraction")
	var declared: Dictionary = _declare(world, 1, 0.15)
	_check(declared.get("applied") == true, "a starting mole fraction is declared through the owner")
	_near_rel(_m(b), _oracle_kg(0.15, 38.4), "0.15 declared holds the oracle kilograms")
	_check(absf(b.o2 - 0.15) <= X_TOL, "and the derived number is 0.15")
	var inv = _inv(world["engine"])
	if inv == null:
		_check(false, "the owner exists to convert")
	else:
		for row: Array in [[0.209, 1.0], [0.15, 0.0081], [0.05, 37.5], [0.0, 2.0], [1.0, 0.5]]:
			_near_rel(inv.o2_kg_in_reference_gas(row[0], row[1]), _oracle_parcel_kg(row[0], row[1]),
				"oxygen of %s kg of gas at %s" % [str(row[1]), str(row[0])])
		for row: Array in [[0.209, 48.0], [0.12, 38.4], [0.0004, 2000.0]]:
			var kg: float = inv.o2_kg_from_mole_fraction(row[0], row[1])
			_near_rel(kg, _oracle_kg(row[0], row[1]), "inventory of %s m3 at %s" % [str(row[1]), str(row[0])])
			_check(absf(inv.mole_fraction_from_o2_kg(kg, row[1]) - float(row[0])) <= 1.0e-15, "and back to the same mole fraction")
		_near_rel(inv.o2_kg_in_reference_gas(1.0, 1.0), 31.998 / 28.9647, "one kg of reference gas of pure O2 carries M_O2 / M_air kg")
	_free(world)
	# A value that is not a mole fraction is refused; it is never read as zero.
	for bad: Variant in [NAN, -0.1, 1.5, null, "0.2", INF]:
		world = _world([ROOM_A], [], {"dt": 0.5})
		var room = world["rooms"][0]
		var before: float = _m(room)
		var refused: Dictionary = _declare(world, 0, bad, false)
		_check(refused.get("applied") == false and String(refused.get("reason", "")) == "mole_fraction_not_a_fraction",
			"%s declared as a mole fraction is refused" % str(bad))
		_check(_same(_m(room), before) and _report(world["engine"]).get("state") == "rejected",
			"%s: the inventory is untouched and the run is refused" % str(bad))
		_free(world)


# ---------------------------------------------------------------- B03

func _state_and_not_a_counter() -> void:
	_group("B03 the inventory is state: the room number follows it and never the other way")
	var world: Dictionary = _world([ROOM_A, ROOM_B], [_door(1.0)], {"dt": 0.5, "ach": 0.0})
	var engine = world["engine"]
	var room = world["rooms"][0]
	var inv = _inv(engine)
	var m0: float = _m(room)
	if inv == null:
		_check(false, "the owner exists")
		_free(world)
		return
	# An operation of the owner moves the state and the number follows.
	var debit: Dictionary = inv.consume(room, _selection(inv, room), 0.5, 0.5, "fixture")
	_check(debit.get("applied") == true and _same(_m(room), m0 - 0.5), "an operation of the owner changes the inventory by its amount")
	_check(absf(room.o2 - _oracle_x(m0 - 0.5, 48.0)) <= X_TOL, "and the room number is the one derived from it")
	# The audit accumulators govern nothing.
	var m1: float = _m(room)
	var x1: float = room.o2
	room.o2_consumed_bulk_kg_total = 123.0
	room.o2_consumed_kg_total_all = -7.0
	room.o2_net_transport_kg_total = 55.0
	room.o2_exterior_net_kg_total = -3.0
	inv.audit_room_numbers()
	_check(_same(_m(room), m1) and _same(room.o2, x1) and inv.state() == "armed", "rewriting every accumulator moves neither the inventory nor the number")
	# The layer numbers govern nothing.
	room.o2_upper = 0.03
	room.o2_lower = 0.19
	_advance(world, 4)
	_check(_same(_m(room) + _m(world["rooms"][1]), m1 + _oracle_kg(AIR, 38.4)) or
		absf(_m(room) + _m(world["rooms"][1]) - m1 - _oracle_kg(AIR, 38.4)) <= GAP_KG,
		"writing the layer numbers and stepping leaves the total inventory where it was")
	_check(_report(engine).get("state") == "armed", "and the run is still valid")
	# The inventory is not the room number on the historical base.
	_check(absf(_m(room) - room.o2 * 48.0 * O_REFERENCE_DENSITY_KG_M3) > 1.0, "the inventory cannot be rebuilt as the number times the mass of gas")
	# A write of the number that does not come from the owner is refused and counted.
	var m2: float = _m(room)
	var x2: float = room.o2
	room.o2 = 0.10
	_check(_same(room.o2, x2) and _same(_m(room), m2), "a direct write of the room number is not applied and moves no inventory")
	room.o2_inventory_kg = 1.0
	_check(_same(_m(room), m2) and _same(room.o2, x2), "a direct write of the inventory is not applied")
	_check(room.get("o2_unauthorized_write_count") == 2, "both writes are counted in the room")
	var clock: float = engine.sim_time_s
	engine.step(world["dt"])
	var report: Dictionary = _report(engine)
	_check(engine.get("o2_room_inventory_failure") == "o2_room_inventory_failed" and report.get("state") == "rejected",
		"the next step refuses the run")
	_check(_reasons(report).has("room_number_written_outside_the_owner"), "and names the write outside the owner")
	engine.step(world["dt"])
	_check(engine.sim_time_s == clock + world["dt"], "a refused run is not simulated any further")
	_free(world)


# ---------------------------------------------------------------- B04

func _rest() -> void:
	_group("B04 a sealed room at rest with the product infiltration: nothing changes")
	var world: Dictionary = _world([ROOM_A], [], {"dt": 0.5})
	var room = world["rooms"][0]
	var m0: float = _m(room)
	var acc: Dictionary = _measure(world, 240)
	_closes(acc, "rest")
	_check(absf(_m(room) - m0) <= GAP_KG, "the inventory of a sealed room with no fire does not move")
	_check(absf(room.o2 - AIR) <= X_TOL and absf(room.o2_upper - AIR) <= X_TOL and absf(room.o2_lower - AIR) <= X_TOL,
		"the three numbers stay at 0.209")
	_check(acc["consumed_kg"] == 0.0 and acc["largest_transit_kg"] == 0.0, "nothing consumed and nothing in transit")
	_check(_valid(world), "a sealed room with no fire is supported: it is not refused for having no opening")
	_observe("rest", acc)
	_free(world)


# ---------------------------------------------------------------- B05

func _controlled_demand() -> void:
	_group("B05 a known demand, two steps: the debit is the demand and the inventory closes (H04, H10)")
	var totals: Dictionary = {}
	for dt: float in [0.5, 0.25]:
		var world: Dictionary = _world([ROOM_A, ROOM_B], [_door(1.0)], {"dt": dt, "ach": 0.0})
		var steps: int = int(round(120.0 / dt))
		var start: float = _total(world)
		var acc: Dictionary = _measure(world, steps, {0: 20.0})
		var label: String = "20 kW for 120 s, dt %s" % str(dt)
		_closes(acc, label)
		var expected_kg: float = 20.0 / 1000.0 * O_OXYGEN_KG_PER_MJ * 120.0
		_check(absf(expected_kg - 0.1824) < 1.0e-12, "the oracle demand is 0.1824 kg")
		_check(absf(acc["consumed_kg"] - expected_kg) <= GAP_KG, label + ": the operations debit the demand")
		_check(absf(start - _total(world) - expected_kg) <= GAP_KG, label + ": the inventory and its transit lost exactly the demand")
		_check(absf(acc["largest_debit_error_kg"]) <= GAP_KG, label + ": every step debits its own demand")
		_check(acc["clipped_kg"] == 0.0, label + ": nothing clipped")
		var room = world["rooms"][0]
		_check(absf(room.o2_consumed_bulk_kg_total - expected_kg) <= GAP_KG and absf(room.o2_consumed_fire_kg_total - expected_kg) <= GAP_KG,
			label + ": the audit accumulators record the debit applied")
		_check(_totals_of(world, 0).get("consumed_kg", NAN) == acc["consumed_kg"], label + ": the totals of the owner are the sum of its operations")
		_check(acc["highest_x"] <= AIR + X_TOL, label + ": no room ends richer than the air it started with")
		_check(_valid(world), label + ": the run is valid")
		totals[dt] = acc["consumed_kg"]
		_observe("controlled_demand_dt_%s" % str(dt), acc)
		_free(world)
	_check(totals.size() == 2 and absf(float(totals[0.5]) - float(totals[0.25])) <= GAP_KG, "the two steps debit the same oxygen")


# ---------------------------------------------------------------- B06

func _real_fire() -> void:
	_group("B06 a real room fire, two steps: debit, transport and transit close in every step (H04, H10)")
	for dt: float in [0.25, 0.125]:
		var world: Dictionary = _world([ROOM_A, ROOM_B], [_door(1.0)], {"dt": dt, "fire": true})
		var steps: int = int(round(120.0 / dt))
		var start: float = _total(world)
		var acc: Dictionary = _measure(world, steps)
		var label: String = "real fire, dt %s" % str(dt)
		_closes(acc, label)
		var room = world["rooms"][0]
		var heat_mj: float = room.hrr_kj_total / 1000.0
		_check(heat_mj > 5.0, label + ": the room burned (%.2f MJ)" % heat_mj)
		_check(absf(acc["consumed_kg"] - O_OXYGEN_KG_PER_MJ * heat_mj) <= GAP_KG, label + ": the debit is 0.076 kg per MJ of the heat the room reports")
		_check(acc["clipped_kg"] == 0.0, label + ": nothing clipped")
		_check(absf(room.o2_consumed_bulk_kg_total - acc["consumed_kg"]) <= GAP_KG, label + ": the accumulator records the debit applied")
		_check(acc["largest_transit_kg"] > 1.0e-4 and acc["delayed"] > 0, label + ": oxygen was in transit")
		_check(absf(start + acc["outside_kg"] - acc["consumed_kg"] - _total(world)) <= GAP_KG,
			label + ": inventories plus transit end at start plus exterior minus debit")
		_check(acc["highest_x"] <= AIR + X_TOL, label + ": no room ends richer than the outside air")
		_check(acc["entries_well_formed"], label + ": every entry in transit names donor, receiver and this run")
		_check(_valid(world), label + ": the run is valid")
		acc["heat_MJ"] = heat_mj
		_observe("real_fire_dt_%s" % str(dt), acc)
		_free(world)


# ---------------------------------------------------------------- B07

func _transport() -> void:
	_group("B07 transport between two rooms, no fire: what leaves one enters the other (H05)")
	var world: Dictionary = _world([ROOM_A, ROOM_B], [_door(1.0)], {"dt": 0.5, "ach": 0.0})
	_declare(world, 1, 0.15)
	var start: float = _total(world)
	var b0: float = _m(world["rooms"][1])
	var acc: Dictionary = _measure(world, 480)
	_closes(acc, "transport")
	_check(acc["largest_total_change_kg"] <= GAP_KG, "inventories plus transit are the same in every step, read from the state alone")
	_check(absf(_total(world) - start) <= GAP_KG, "and the same at the end")
	_check(_m(world["rooms"][1]) - b0 > 0.1, "oxygen moved to the poorer room (%.4f kg)" % (_m(world["rooms"][1]) - b0))
	_check(acc["consumed_kg"] == 0.0 and acc["outside_kg"] == 0.0, "nothing consumed, nothing from outside")
	var monotone: bool = true
	var ordered: bool = true
	var previous: Array = [AIR, 0.15]
	for row: Array in acc["x_rows"]:
		monotone = monotone and float(row[0]) <= float(previous[0]) + X_TOL and float(row[1]) >= float(previous[1]) - X_TOL
		ordered = ordered and float(row[1]) <= float(row[0]) + X_TOL
		previous = row
	_check(monotone, "the rich room never gains and the poor room never loses")
	_check(ordered, "the poor room never becomes richer than the one that feeds it")
	_check(_valid(world), "the run is valid")
	_observe("transport", acc)
	_free(world)


# ---------------------------------------------------------------- B08

func _exterior() -> void:
	_group("B08 one room with an exterior door, no fire, two steps: the infiltration law and nothing else (H06)")
	for dt: float in [0.5, 0.25]:
		var world: Dictionary = _world([ROOM_A], [_outside_door()], {"dt": dt})
		_declare(world, 0, 0.15)
		var engine = world["engine"]
		var room = world["rooms"][0]
		var k: float = engine.ach_infiltration / 3600.0 * dt
		var steps: int = int(round(120.0 / dt))
		var label: String = "exterior, dt %s" % str(dt)
		var x: float = 0.15
		var worst: float = 0.0
		var acc: Dictionary = _empty_acc()
		for _i: int in range(steps):
			_measure_into(world, acc, {}, false)
			x = x + k * (AIR - x)
			worst = maxf(worst, absf(room.o2 - x))
		_closes(acc, label)
		_check(worst <= X_TOL, label + ": every step is x + k (x_out - x)")
		_check(absf(room.o2 - (AIR - (AIR - 0.15) * pow(1.0 - k, steps))) <= X_TOL, label + ": the end is the closed form")
		_check(absf(_m(room) - _oracle_kg(0.15, 48.0) - acc["outside_kg"]) <= GAP_KG, label + ": the inventory gained what came from outside")
		_check(acc["outside_kg"] > 0.0 and acc["consumed_kg"] == 0.0, label + ": only the exterior exchange acted")
		_check(acc["highest_x"] <= AIR + X_TOL, label + ": never richer than the outside air")
		_check(_valid(world), label + ": an open exterior door with no temperature difference is not refused")
		acc["largest_law_error"] = worst
		_observe("exterior_dt_%s" % str(dt), acc)
		_free(world)


# ---------------------------------------------------------------- B09

func _open_and_close() -> void:
	_group("B09 a door closed, opened and closed again (H07)")
	var world: Dictionary = _world([ROOM_A, ROOM_B], [_door(0.0)], {"dt": 0.5, "ach": 0.0})
	_declare(world, 1, 0.15)
	var door = world["building"].get_openings()[0]
	var start: float = _total(world)
	var all: Dictionary = _empty_acc()
	for phase: Array in [["closed", 0.0, 40], ["open", 1.0, 80], ["closed again", 0.0, 80]]:
		door.open_fraction = float(phase[1])
		var a0: float = _m(world["rooms"][0])
		var b0: float = _m(world["rooms"][1])
		var acc: Dictionary = _measure(world, int(phase[2]))
		_closes(acc, String(phase[0]))
		if float(phase[1]) == 0.0:
			_check(acc["operations"] == 0, "%s: no operation at all" % phase[0])
			_check(_same(_m(world["rooms"][0]), a0) and _same(_m(world["rooms"][1]), b0), "%s: both inventories bit for bit" % phase[0])
		else:
			_check(acc["operations"] > 0 and _m(world["rooms"][1]) - b0 > 0.01, "%s: oxygen crossed the door" % phase[0])
		all["room_gap_kg"] = maxf(all["room_gap_kg"], acc["room_gap_kg"])
		all["building_gap_kg"] = maxf(all["building_gap_kg"], acc["building_gap_kg"])
		all["oracle_gap_kg"] = maxf(all["oracle_gap_kg"], acc["oracle_gap_kg"])
		all["largest_total_change_kg"] = maxf(all["largest_total_change_kg"], acc["largest_total_change_kg"])
		all["highest_x"] = maxf(all["highest_x"], acc["highest_x"])
		all["lowest_inventory_kg"] = minf(all["lowest_inventory_kg"], acc["lowest_inventory_kg"])
		all["operations"] += acc["operations"]
		all["steps"] += acc["steps"]
	_check(absf(_total(world) - start) <= GAP_KG and all["largest_total_change_kg"] <= GAP_KG, "the total is the same through the three phases")
	_check(_valid(world), "the run is valid")
	_observe("open_and_close", all)
	_free(world)


# ---------------------------------------------------------------- B10

func _layers_do_not_write_the_inventory() -> void:
	_group("B10 the layer numbers move and the inventory does not (H08, H09)")
	var world: Dictionary = _world([ROOM_A], [], {"dt": 0.5, "ach": 0.0})
	var room = world["rooms"][0]
	_declare(world, 0, 0.18)
	_hot_upper_layer(room, 12.0, 45.6, 200.0)
	room.o2_upper = 0.12
	room.o2_lower = 0.20
	var m0: float = _m(room)
	var x0: float = room.o2
	var acc: Dictionary = _measure(world, 240)
	_check(acc["operations"] == 0, "two layers relaxing: no operation on the inventory")
	_check(_same(_m(room), m0) and _same(room.o2, x0), "two layers relaxing: inventory and room number bit for bit")
	_check(absf(room.o2_upper - 0.12) > 0.01, "while the upper number did move (%.4f)" % room.o2_upper)
	_check(_valid(world), "the run is valid")
	_observe("two_layers", acc)
	_free(world)
	world = _world([ROOM_A], [], {"dt": 0.5, "ach": 0.0})
	room = world["rooms"][0]
	_hot_upper_layer(room, 26.0, 5.0, 300.0)
	room.o2_upper = 0.12
	room.o2_lower = 0.20
	m0 = _m(room)
	acc = _measure(world, 20)
	_check(acc["operations"] == 0 and _same(_m(room), m0) and absf(room.o2 - AIR) <= X_TOL,
		"a collapsed lower layer: the inventory and the room number do not move")
	_check(absf(room.o2_upper - room.o2) <= X_TOL and absf(room.o2_lower - room.o2) <= X_TOL,
		"while both layer numbers were rewritten to the room number")
	_check(_valid(world), "the run is valid")
	_observe("collapse", acc)
	_free(world)


# ---------------------------------------------------------------- B11

func _cap() -> void:
	_group("B11 a demand above the cap of the sink: what is clipped is recorded, never discarded")
	var world: Dictionary = _world([ROOM_A, ROOM_B], [_door(1.0)], {"dt": 0.5, "ach": 0.0})
	var start: float = _total(world)
	var acc: Dictionary = _measure(world, 10, {0: 20000.0})
	_closes(acc, "cap")
	var requested_kg: float = 10.0 * 20000.0 / 1000.0 * O_OXYGEN_KG_PER_MJ * 0.5
	_check(acc["clipped_kg"] > 0.5, "the cap acted (%.4f kg clipped)" % acc["clipped_kg"])
	_check(absf(acc["consumed_kg"] + acc["clipped_kg"] - requested_kg) <= GAP_KG, "applied plus clipped is the whole demand")
	_check(absf(acc["consumed_kg"] - acc["expected_consumed_kg"]) <= GAP_KG, "every step applies the smaller of the demand and 5 % of the inventory")
	var totals: Dictionary = _totals_of(world, 0)
	_check(absf(float(totals.get("consumption_clipped_kg", NAN)) - acc["clipped_kg"]) <= GAP_KG
		and absf(float(totals.get("consumption_requested_kg", NAN)) - requested_kg) <= GAP_KG, "the owner keeps what was asked and what was clipped")
	_check(absf(start - _total(world) - acc["consumed_kg"]) <= GAP_KG, "the inventory lost what was applied and nothing more")
	_check(_valid(world), "a cap is not a rejection: the run is valid")
	_observe("cap", acc)
	_free(world)


# ---------------------------------------------------------------- B12

func _reset_and_reuse() -> void:
	_group("B12 life cycle on the same engine: reset, revoke, no building, not ready (H11)")
	var world: Dictionary = _world([ROOM_A, ROOM_B], [_door(1.0)], {"dt": 0.25, "fire": true})
	var engine = world["engine"]
	var building = world["building"]
	var inv = _inv(engine)
	var first: Dictionary = _measure(world, 160)
	var report: Dictionary = _report(engine)
	var generation: int = int(report.get("generation", -1))
	var last_id: int = _largest_id(report)
	_check((report.get("transit", []) as Array).size() > 0, "first run: entries in transit before the reset (%d)" % (report.get("transit", []) as Array).size())
	# 1. Reset: nothing of the first run is left.
	engine.reset_simulation(0, true)
	report = _report(engine)
	_check((report.get("transit", []) as Array).is_empty() and report.get("in_transit_kg") == 0.0, "reset: the transit is empty")
	_check(int(report.get("generation", -1)) == generation + 1 and report.get("step") == 0 and report.get("state") == "armed",
		"reset: a new generation, armed, at step zero")
	_check((report.get("rejections", []) as Array).is_empty() and engine.get("o2_room_inventory_failure") == "", "reset: no rejection inherited")
	for room in world["rooms"]:
		_near_rel(_m(room), _oracle_kg(AIR, room.volume_m3()), "reset: room %d starts again with the air inventory" % room.id)
	var second: Dictionary = _measure(world, 160)
	_check(_digest(first) == _digest(second) and _digest(first) != "", "reset: the same run gives the same inventories, numbers and transit")
	_check(_largest_id(_report(engine)) > last_id, "reset: delivery ids are not reused")
	_closes(second, "second run")
	# 2. Revoked on the same engine.
	_switch(engine, false)
	engine.reset_simulation(0, true)
	_check(engine.get("_o2_room_inventory") == null and _report(engine).get("state") == "inactive", "revoked: no owner, inactive report")
	_check(inv == null or inv.state() == "inactive", "revoked: the owner was retired")
	_check(engine.oxygen_exchange_system.get("room_o2_inventory") == null and engine.gas_exchange_system.get("room_o2_inventory") == null,
		"revoked: the subsystems hold no owner")
	var room_a = world["rooms"][0]
	_check(room_a.get("o2_inventory_authority") == false and is_nan(_m(room_a)), "revoked: the rooms are released")
	_advance(world, 40)
	_check(engine.sim_time_s == 10.0 and room_a.o2 < AIR and room_a.get("o2_unauthorized_write_count") == 0,
		"revoked: the same engine runs the historical route")
	# 3. Reset without a building, after a run with oxygen in transit.
	_switch(engine, true)
	engine.reset_simulation(0, true)
	_measure(world, 160)
	inv = _inv(engine)
	_check(inv != null and (_report(engine).get("transit", []) as Array).size() > 0, "third run: entries in transit")
	var clock: float = engine.sim_time_s
	engine.building = null
	engine.reset_simulation(0, true)
	report = _report(engine)
	_check(report.get("state") == "inactive" and (report.get("transit", []) as Array).is_empty(), "no building: retired, transit empty")
	_check(room_a.get("o2_inventory_authority") == false and is_nan(_m(room_a)), "no building: the rooms are released")
	_check(engine.oxygen_exchange_system.get("room_o2_inventory") == null, "no building: the oxygen system holds no owner")
	engine.step(world["dt"])
	_check(engine.sim_time_s == clock, "no building: the clock does not advance")
	# 4. Building back, and the engine not ready.
	engine.building = building
	engine.reset_simulation(0, true)
	_measure(world, 160)
	_check((_report(engine).get("transit", []) as Array).size() > 0, "fourth run: entries in transit")
	var hvac = engine.hvac_system
	engine.hvac_system = null
	_check(not engine.is_ready_for_validation(), "the engine is not ready")
	engine.reset_simulation(0, true)
	report = _report(engine)
	_check(report.get("state") == "inactive" and (report.get("transit", []) as Array).is_empty(), "not ready: retired, transit empty")
	_check(room_a.get("o2_inventory_authority") == false, "not ready: the rooms are released")
	engine.hvac_system = hvac
	# 5. And the run after all that is the first run again.
	engine.reset_simulation(0, true)
	var fifth: Dictionary = _measure(world, 160)
	_check(_digest(fifth) == _digest(first), "after every kind of reset the run is the first run again")
	_check(_valid(world), "the run is valid")
	_observe("reset_and_reuse", {"first_digest": _digest(first), "second_digest": _digest(second), "fifth_digest": _digest(fifth),
		"largest_transit_kg": first["largest_transit_kg"]})
	_free(world)


# ---------------------------------------------------------------- B13

func _refused_configurations() -> void:
	_group("B13 what M1 does not cover is refused by name and writes nothing")
	# 1. The pressure network.
	var world: Dictionary = _world([ROOM_A, ROOM_B], [_door(1.0)], {"dt": 0.5, "network_on": true})
	_not_armed(world, "environment_not_supported:pressure_network_enabled=true", "pressure network")
	_free(world)
	# 2. The diagnostic bench.
	world = _world([ROOM_A, ROOM_B], [_door(1.0)], {"dt": 0.5, "bench_on": true})
	_not_armed(world, "environment_not_supported:diagnostic_bench_enabled=true", "diagnostic bench")
	_free(world)
	# 3. A fire oxygen mode other than the historical one.
	world = _world([ROOM_A, ROOM_B], [_door(1.0)], {"dt": 0.5, "fire_o2_mode": "lower"})
	_not_armed(world, "environment_not_supported:fire_oxygen_mode=lower", "fire oxygen mode lower")
	_free(world)
	# 4. A sealed room that burns was refused here by stage M1. Stage M2 debits its
	# inventory: it is a supported route now, judged in g3_o2_selection.gd (group C04).
	# 5. An exterior door with a fire behind it. Refused where the route would write.
	world = _world([ROOM_A], [_outside_door()], {"dt": 0.25, "fire": true, "ignite": false})
	# The engine smooths an exterior opening from zero: the fire starts once the
	# door is fully open, so that the room is not sealed for the sink meanwhile.
	_advance(world, 80)
	_check(_valid(world), "exterior door with a fire: valid while nothing burns")
	world["engine"].ignite_room(0)
	_refused_while_running(world, 480, "exterior_opening_with_temperature_difference", "exterior door with a fire", false)
	_free(world)
	# 6. The switch turned off in the middle of a run, with no reset.
	world = _world([ROOM_A, ROOM_B], [_door(1.0)], {"dt": 0.5})
	var engine = world["engine"]
	_advance(world, 4)
	var clock: float = engine.sim_time_s
	_switch(engine, false)
	engine.step(world["dt"])
	_check(engine.get("o2_room_inventory_failure") == "o2_room_inventory_switch_changed_without_reset" and engine.sim_time_s == clock,
		"switch turned off without a reset: refused, the clock stops")
	_free(world)
	# 7. And turned on in the middle of a historical run.
	world = _world([ROOM_A, ROOM_B], [_door(1.0)], {"dt": 0.5, "inventory": false})
	engine = world["engine"]
	_advance(world, 4)
	clock = engine.sim_time_s
	var x: float = world["rooms"][0].o2
	_switch(engine, true)
	engine.step(world["dt"])
	_check(engine.get("o2_room_inventory_failure") == "o2_room_inventory_switch_changed_without_reset" and engine.sim_time_s == clock
		and _same(world["rooms"][0].o2, x) and world["rooms"][0].get("o2_inventory_authority") == false,
		"switch turned on without a reset: refused, nothing armed behind the run")
	_free(world)


# ---------------------------------------------------------------- B14

func _transit_integrity() -> void:
	_group("B14 a delivery happens once, belongs to its run, and a refused transfer leaves nothing half done")
	# 1. A delivery applied twice.
	var world: Dictionary = _world([ROOM_A, ROOM_B], [_door(1.0)], {"dt": 0.25, "fire": true})
	_measure(world, 160)
	var inv = _inv(world["engine"])
	if inv == null or (inv.get("_transit") as Array).is_empty():
		_check(false, "a run with entries in transit exists")
	else:
		var entry: Dictionary = (inv.get("_transit") as Array)[0]
		var receiver = world["building"].get_room(int(entry["receiver"]))
		var before: float = _m(receiver)
		var once: Dictionary = inv._deliver(entry)
		_check(once.get("applied") == true and absf(_m(receiver) - before - float(entry["net_kg"])) <= 1.0e-15, "a delivery credits its net once")
		var after_once: float = _m(receiver)
		var twice: Dictionary = inv._deliver(entry)
		_check(twice.get("applied") == false and twice.get("reason") == "delivery_applied_twice" and _same(_m(receiver), after_once),
			"the same delivery again is refused and credits nothing")
		_check(inv.state() == "rejected", "and the run is refused")
		var later: Dictionary = inv.consume(receiver, _selection(inv, receiver), 0.01, 0.01, "fixture")
		_check(later.get("applied") == false and _same(_m(receiver), after_once), "after a rejection no operation is applied")
	_free(world)
	# 2. A delivery of another run.
	world = _world([ROOM_A, ROOM_B], [_door(1.0)], {"dt": 0.5})
	inv = _inv(world["engine"])
	if inv == null:
		_check(false, "the owner exists")
	else:
		var b = world["rooms"][1]
		var before_b: float = _m(b)
		var foreign: Dictionary = {"id": 999, "generation": inv.generation() - 1, "state": "in_transit", "donor": 0, "receiver": 1,
			"delay_s": 0.0, "to_receiver_kg": 0.2, "advanced_to_donor_kg": 0.0, "net_kg": 0.2}
		var refused: Dictionary = inv._deliver(foreign)
		_check(refused.get("applied") == false and refused.get("reason") == "delivery_of_another_run" and _same(_m(b), before_b),
			"a delivery of another run is refused and credits nothing")
	_free(world)
	# 3. Transfers that cannot be applied whole are not applied at all.
	for case: Array in [
			["receiver would go negative, no delay", 0.0, -1.0, 0.0],
			["donor would go negative, with a delay", -1.0, 0.0, 5.0],
			["donor would go negative, no delay", -1.0, 0.0, 0.0],
			["an unknown quantity", null, 0.0, 0.0],
			["a quantity that is not a number", NAN, 0.0, 5.0],
			["a negative quantity", -0.5, 0.0, 0.0]]:
		world = _world([ROOM_A, ROOM_B], [_door(1.0)], {"dt": 0.5})
		inv = _inv(world["engine"])
		if inv == null:
			_check(false, "the owner exists")
			_free(world)
			continue
		var a = world["rooms"][0]
		var b2 = world["rooms"][1]
		var ma: float = _m(a)
		var mb: float = _m(b2)
		# -1 stands for "one kilogram more than the room holds".
		var donor_out: Variant = case[1]
		var receiver_out: Variant = case[2]
		if typeof(donor_out) == TYPE_FLOAT and donor_out == -1.0:
			donor_out = ma + mb + 1.0
		if typeof(receiver_out) == TYPE_FLOAT and receiver_out == -1.0:
			receiver_out = ma + mb + 1.0
		var result: Dictionary = inv.exchange_between_rooms(a, b2, donor_out, receiver_out, case[3], "fixture")
		_check(result.get("applied") == false and String(result.get("reason", "")) != "", "%s: refused with a reason" % case[0])
		_check(_same(_m(a), ma) and _same(_m(b2), mb) and (inv.get("_transit") as Array).is_empty() and inv.in_transit_kg() == 0.0,
			"%s: neither room changed and nothing entered the transit" % case[0])
		_check(inv.state() == "rejected", "%s: the run is refused" % case[0])
		_free(world)
	# 4. A debit the room cannot pay, and one larger than its own demand.
	for case: Array in [["more than the inventory", -1.0, -1.0, "debit_larger_than_the_inventory"],
			["more than the demand", 0.1, 0.2, "debit_larger_than_the_demand"],
			["an unknown debit", 0.1, null, "quantity_not_a_finite_amount"]]:
		world = _world([ROOM_A], [], {"dt": 0.5})
		inv = _inv(world["engine"])
		if inv == null:
			_check(false, "the owner exists")
			_free(world)
			continue
		var room = world["rooms"][0]
		var m: float = _m(room)
		var requested: Variant = m + 1.0 if (typeof(case[1]) == TYPE_FLOAT and case[1] == -1.0) else case[1]
		var applied: Variant = m + 1.0 if (typeof(case[2]) == TYPE_FLOAT and case[2] == -1.0) else case[2]
		var result: Dictionary = inv.consume(room, _selection(inv, room), requested, applied, "fixture")
		_check(result.get("applied") == false and result.get("reason") == case[3] and _same(_m(room), m), "a debit of %s is refused whole" % case[0])
		_free(world)
	# 5. A starting state declared after the first step.
	world = _world([ROOM_A], [], {"dt": 0.5})
	_advance(world, 1)
	var m_late: float = _m(world["rooms"][0])
	var late: Dictionary = _declare(world, 0, 0.15, false)
	_check(late.get("applied") == false and late.get("reason") == "initial_state_declared_after_the_first_step"
		and _same(_m(world["rooms"][0]), m_late), "a starting state declared after the first step is refused")
	_free(world)


# ---------------------------------------------------------------- judging helpers

## Not armed: an explicit failure, the reason named, no room under authority, and
## an engine that does not advance.
func _not_armed(world: Dictionary, reason: String, label: String) -> void:
	var engine = world["engine"]
	var report: Dictionary = _report(engine)
	_check(engine.get("o2_room_inventory_failure") == "o2_room_inventory_rejected" and report.get("state") == "rejected",
		label + ": the inventory does not arm and says so")
	var named: bool = false
	for record: Dictionary in report.get("rejections", []):
		named = named or (record.get("errors", []) as Array).has(reason)
	_check(named, label + ": the reason is " + reason)
	for room in world["rooms"]:
		_check(room.get("o2_inventory_authority") == false and is_nan(_m(room)), label + ": room %d is not under authority" % room.id)
	_check(engine.oxygen_exchange_system.get("room_o2_inventory") == null, label + ": the oxygen system holds no owner")
	engine.step(world["dt"])
	_check(engine.sim_time_s == 0.0, label + ": the engine does not advance")


## A run that is valid until a route M1 does not own acts: refused by its name in
## that step. The refused route moved nothing: the inventory changed in that step by
## the operations the owner applied before it and by nothing else.
func _refused_while_running(world: Dictionary, limit: int, route: String, label: String, sink_is_refused: bool) -> void:
	var engine = world["engine"]
	var steps: int = 0
	var before: Dictionary = {}
	while steps < limit and str(engine.get("o2_room_inventory_failure")) == "":
		before = _snapshot(world)
		engine.step(world["dt"])
		steps += 1
	var report: Dictionary = _report(engine)
	_check(engine.get("o2_room_inventory_failure") == "o2_room_inventory_failed" and report.get("state") == "rejected",
		label + ": refused while running (step %d)" % steps)
	var rejections: Array = report.get("rejections", [])
	_check(rejections.size() == 1 and (rejections[0] as Dictionary).get("reason") == "route_not_supported_in_m1"
		and (rejections[0] as Dictionary).get("route") == route, label + ": the route named is " + route)
	var room = world["rooms"][0]
	var effects: Dictionary = _effects(world, report.get("step_operations", []))
	_check(not before.is_empty() and absf(_m(room) - float(before.get("m", {}).get(room.id, NAN)) - float(effects["by_room"][room.id])) <= GAP_KG,
		label + ": in the refused step the inventory changed by the operations of the owner and by nothing else")
	if sink_is_refused:
		_check(effects["consumed_kg"] == 0.0 and room.o2_consumed_bulk_kg_step == 0.0 and room.hrr_kw > 0.0,
			label + ": the room has power and the refused sink debited nothing")
	_check(room.get("o2_unauthorized_write_count") == 0, label + ": nobody wrote the room number behind the owner")
	var clock: float = engine.sim_time_s
	var m: float = _m(room)
	engine.step(world["dt"])
	_check(engine.sim_time_s == clock and _same(_m(room), m), label + ": nothing is simulated after the refusal")
	_observations["refused " + label] = {"step": steps, "rejection": rejections[0] if not rejections.is_empty() else {}}


## The three budgets of a measured run, each within the accepted gap in every step.
func _closes(acc: Dictionary, label: String) -> void:
	_check(acc["inventory_read"], label + ": the inventory is read from the rooms")
	_check(acc["room_gap_kg"] <= GAP_KG, label + ": every room changes by its operations (worst %s kg)" % str(acc["room_gap_kg"]))
	_check(acc["building_gap_kg"] <= GAP_KG, label + ": inventories plus transit change by exterior minus debit (worst %s kg)" % str(acc["building_gap_kg"]))
	_check(acc["oracle_gap_kg"] <= GAP_KG, label + ": and by what the closed forms say, with no operation read (worst %s kg)" % str(acc["oracle_gap_kg"]))
	_check(acc["lowest_inventory_kg"] >= 0.0, label + ": no inventory below zero")


func _valid(world: Dictionary) -> bool:
	var report: Dictionary = _report(world["engine"])
	return report.get("state") == "armed" and (report.get("rejections", []) as Array).is_empty() \
			and world["engine"].get("o2_room_inventory_failure") == ""


# ---------------------------------------------------------------- measuring

func _empty_acc() -> Dictionary:
	return {"steps": 0, "inventory_read": true, "room_gap_kg": 0.0, "building_gap_kg": 0.0, "oracle_gap_kg": 0.0,
		"largest_total_change_kg": 0.0, "largest_transit_kg": 0.0, "highest_x": 0.0, "lowest_inventory_kg": INF,
		"operations": 0, "delayed": 0, "consumed_kg": 0.0, "clipped_kg": 0.0, "expected_consumed_kg": 0.0,
		"largest_debit_error_kg": 0.0, "outside_kg": 0.0, "entries_well_formed": true,
		"x_rows": [], "digest_values": PackedFloat64Array()}


func _measure(world: Dictionary, steps: int, imposed_kw: Dictionary = {}) -> Dictionary:
	var acc: Dictionary = _empty_acc()
	for _i: int in range(steps):
		_measure_into(world, acc, imposed_kw, not imposed_kw.is_empty())
	return acc


## One step and its three budgets.
## - by operations: every room changes by the operations the owner applied to it;
## - of the building: inventories plus transit change by exterior minus debit;
## - by closed form, with no operation read: the debit is the demand of the power
##   of the step, capped at 5 % of what the room holds when the sink runs, and the
##   exterior exchange is the infiltration law on that same content.
## An arrival moves oxygen from the transit to a room: it is in the first budget
## and cancels in the other two, so it is never counted twice.
func _measure_into(world: Dictionary, acc: Dictionary, imposed_kw: Dictionary, oxygen_sub_step_alone: bool) -> void:
	var engine = world["engine"]
	var dt: float = float(world["dt"])
	var before: Dictionary = _snapshot(world)
	if oxygen_sub_step_alone:
		_oxygen_sub_step(world, imposed_kw)
	else:
		engine.step(dt)
	var after: Dictionary = _snapshot(world)
	var report: Dictionary = _report(engine)
	var operations: Array = report.get("step_operations", [])
	acc["steps"] += 1
	acc["operations"] += operations.size()
	var effects: Dictionary = _effects(world, operations)
	var by_room: Dictionary = effects["by_room"]
	var outside_kg: float = effects["outside_kg"]
	var consumed_kg: float = effects["consumed_kg"]
	acc["clipped_kg"] += effects["clipped_kg"]
	acc["delayed"] += effects["delayed"]
	var expected_change_kg: float = 0.0
	var row: Array = []
	for room in world["rooms"]:
		var m_before: float = float(before["m"][room.id])
		var m_after: float = float(after["m"][room.id])
		if is_nan(m_before) or is_nan(m_after):
			acc["inventory_read"] = false
			continue
		acc["room_gap_kg"] = maxf(acc["room_gap_kg"], absf(m_after - m_before - float(by_room[room.id])))
		acc["lowest_inventory_kg"] = minf(acc["lowest_inventory_kg"], m_after)
		acc["highest_x"] = maxf(acc["highest_x"], room.o2)
		row.append(room.o2)
		acc["digest_values"].append(m_after)
		acc["digest_values"].append(room.o2)
		# Closed forms, on what the room holds when the oxygen step reaches it.
		var held_kg: float = m_before + float(before["due"].get(room.id, 0.0))
		var power_kw: float = float(imposed_kw.get(room.id, 0.0)) if oxygen_sub_step_alone else float(room.hrr_kw)
		var demand_kg: float = power_kw / 1000.0 * O_OXYGEN_KG_PER_MJ * dt
		var debit_kg: float = minf(demand_kg, held_kg * O_CAP_FRACTION_PER_STEP)
		var gas_kg: float = room.volume_m3() * (engine.ach_infiltration / 3600.0) * O_REFERENCE_DENSITY_KG_M3 * dt
		var exterior_kg: float = _oracle_parcel_kg(world["building"].outside_o2 - _oracle_x(held_kg, room.volume_m3()), gas_kg)
		expected_change_kg += exterior_kg - debit_kg
		acc["expected_consumed_kg"] += debit_kg
	if not acc["inventory_read"]:
		return
	var total_change_kg: float = float(after["total"]) - float(before["total"])
	acc["building_gap_kg"] = maxf(acc["building_gap_kg"], absf(total_change_kg - (outside_kg - consumed_kg)))
	acc["oracle_gap_kg"] = maxf(acc["oracle_gap_kg"], absf(total_change_kg - expected_change_kg))
	acc["largest_total_change_kg"] = maxf(acc["largest_total_change_kg"], absf(total_change_kg))
	acc["largest_transit_kg"] = maxf(acc["largest_transit_kg"], absf(float(after["transit"])))
	acc["consumed_kg"] += consumed_kg
	acc["outside_kg"] += outside_kg
	acc["digest_values"].append(float(after["transit"]))
	acc["x_rows"].append(row)
	# The debit of the step against the demand of its power, room by room.
	for operation: Dictionary in operations:
		if String(operation.get("kind", "")) == "consume":
			var room_id: int = int(operation["room"])
			var asked_kw: float = float(imposed_kw.get(room_id, 0.0)) if oxygen_sub_step_alone \
					else float(world["building"].get_room(room_id).hrr_kw)
			var asked_kg: float = asked_kw / 1000.0 * O_OXYGEN_KG_PER_MJ * dt
			acc["largest_debit_error_kg"] = maxf(acc["largest_debit_error_kg"],
				absf(float(operation["requested_kg"]) - asked_kg))
	for entry: Dictionary in report.get("transit", []):
		if int(entry.get("generation", -1)) != int(report.get("generation", -2)) or int(entry.get("donor", -1)) == int(entry.get("receiver", -1)) \
				or world["building"].get_room(int(entry.get("donor", -1))) == null or world["building"].get_room(int(entry.get("receiver", -1))) == null \
				or String(entry.get("state", "")) != "in_transit" \
				or absf(float(entry.get("net_kg", NAN)) - (float(entry.get("to_receiver_kg", NAN)) - float(entry.get("advanced_to_donor_kg", NAN)))) > 1.0e-15:
			acc["entries_well_formed"] = false


## What the operations of a step did, room by room. A delayed exchange changes the
## donor only: the receiver changes when its entry arrives, and only then.
func _effects(world: Dictionary, operations: Array) -> Dictionary:
	var by_room: Dictionary = {}
	for room in world["rooms"]:
		by_room[room.id] = 0.0
	var out: Dictionary = {"by_room": by_room, "outside_kg": 0.0, "consumed_kg": 0.0, "clipped_kg": 0.0, "delayed": 0}
	for operation: Dictionary in operations:
		match String(operation.get("kind", "")):
			"consume":
				by_room[int(operation["room"])] -= float(operation["applied_kg"])
				out["consumed_kg"] += float(operation["applied_kg"])
				out["clipped_kg"] += float(operation["clipped_kg"])
			"outside":
				by_room[int(operation["room"])] += float(operation["in_kg"]) - float(operation["out_kg"])
				out["outside_kg"] += float(operation["in_kg"]) - float(operation["out_kg"])
			"interior":
				by_room[int(operation["donor"])] += float(operation["to_donor_kg"]) - float(operation["to_receiver_kg"])
				if bool(operation["delayed"]):
					out["delayed"] += 1
				else:
					by_room[int(operation["receiver"])] += float(operation["to_receiver_kg"]) - float(operation["to_donor_kg"])
			"arrival":
				by_room[int(operation["room"])] += float(operation["net_kg"])
	return out


## What the state shows: the inventory of every room, the transit, and what is due
## to every room within one step. Read from the rooms and from the queue.
func _snapshot(world: Dictionary) -> Dictionary:
	var report: Dictionary = _report(world["engine"])
	var dt: float = float(world["dt"])
	var m: Dictionary = {}
	var due: Dictionary = {}
	var total: float = 0.0
	for room in world["rooms"]:
		m[room.id] = _m(room)
		total += _m(room)
	var transit: float = 0.0
	for entry: Dictionary in report.get("transit", []):
		transit += float(entry["net_kg"])
		if maxf(0.0, float(entry["delay_s"]) - dt) <= O_DELIVERY_DUE_S:
			due[int(entry["receiver"])] = float(due.get(int(entry["receiver"]), 0.0)) + float(entry["net_kg"])
	return {"m": m, "due": due, "transit": transit, "total": total + transit}


func _total(world: Dictionary) -> float:
	return float(_snapshot(world)["total"])


## The oxygen sub-step of the engine alone, with a power written by this fixture:
## a known demand. Nothing else of the step runs, so no heat and no fire exist.
func _oxygen_sub_step(world: Dictionary, imposed_kw: Dictionary) -> void:
	var engine = world["engine"]
	var dt: float = float(world["dt"])
	engine._step_exterior_opening_smooth(dt)
	engine._opening_flow_cache = engine._build_opening_flow_cache()
	var inv = _inv(engine)
	if inv != null:
		inv.begin_step(engine._o2_room_inventory_environment())
	for room in world["rooms"]:
		room.hrr_kw = float(imposed_kw.get(room.id, 0.0))
	engine._step_oxygen(dt)
	for room in world["rooms"]:
		room.hrr_kw = 0.0
	if inv != null:
		inv.audit_room_numbers()


func _advance(world: Dictionary, steps: int) -> void:
	for _i: int in range(steps):
		world["engine"].step(float(world["dt"]))


func _digest(acc: Dictionary) -> String:
	var values: PackedFloat64Array = acc.get("digest_values", PackedFloat64Array())
	if values.is_empty():
		return ""
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(values.to_byte_array())
	return context.finish().hex_encode()


func _largest_id(report: Dictionary) -> int:
	var largest: int = -1
	for entry: Dictionary in report.get("transit", []):
		largest = maxi(largest, int(entry.get("id", -1)))
	return largest


func _reasons(report: Dictionary) -> Array:
	var out: Array = []
	for record: Dictionary in report.get("rejections", []):
		out.append(record.get("reason"))
	return out


func _observe(name: String, acc: Dictionary) -> void:
	var kept: Dictionary = {}
	for key: String in acc.keys():
		if key != "x_rows" and key != "digest_values":
			kept[key] = acc[key]
	_observations[name] = kept


# ---------------------------------------------------------------- reading the new mode

func _switch(engine, value: bool) -> void:
	if "o2_room_inventory_enabled" in engine:
		engine.set("o2_room_inventory_enabled", value)


## The selection of the room for the step that is open (stage M2): a debit has to
## present it. On an owner without selections there is none to present.
func _selection(inv, room) -> Variant:
	return inv.selection_for(room, "fixture") if inv.has_method("selection_for") else null


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


## Declares the starting mole fraction of a room through the owner, and writes the
## two layer numbers, which are historical auxiliaries, to the same value.
func _declare(world: Dictionary, room_id: int, mole_fraction: Variant, with_layers: bool = true) -> Dictionary:
	var engine = world["engine"]
	if not engine.has_method("o2_room_inventory_declare_initial_mole_fraction"):
		return {"applied": false, "reason": "absent"}
	var result: Dictionary = engine.call("o2_room_inventory_declare_initial_mole_fraction", room_id, mole_fraction)
	if with_layers and bool(result.get("applied", false)):
		var room = world["building"].get_room(room_id)
		room.o2_upper = float(mole_fraction)
		room.o2_lower = float(mole_fraction)
	return result


# ---------------------------------------------------------------- oracle

func _oracle_kg(mole_fraction: float, volume_m3: float) -> float:
	return mole_fraction * (volume_m3 * O_REFERENCE_DENSITY_KG_M3 / O_M_DRY_AIR_KG_PER_MOL) * O_M_O2_KG_PER_MOL


func _oracle_x(o2_kg: float, volume_m3: float) -> float:
	return o2_kg / ((volume_m3 * O_REFERENCE_DENSITY_KG_M3 / O_M_DRY_AIR_KG_PER_MOL) * O_M_O2_KG_PER_MOL)


func _oracle_parcel_kg(mole_fraction: float, gas_kg: float) -> float:
	return mole_fraction * (gas_kg / O_M_DRY_AIR_KG_PER_MOL) * O_M_O2_KG_PER_MOL


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
	if options.has("ach"):
		# Declared isolation: no infiltration.
		engine.ach_infiltration = float(options["ach"])
	if bool(options.get("network_on", false)):
		# Negative control: the pressure network is not a route of M1.
		engine.pressure_network_solver_enabled = true
	if bool(options.get("bench_on", false)):
		# Negative control: only the switch of the diagnostic bench. The bench is never armed here.
		engine.g3_prescribed_thermal_source_enabled = true
	if options.has("fire_o2_mode"):
		engine.fire_o2_mode = String(options["fire_o2_mode"])
	if bool(options.get("inventory", true)):
		_switch(engine, true)
	engine.suppress_exit_graphs()
	root.add_child(engine)
	engine.reset_simulation(0, bool(options.get("ignite", options.get("fire", false))))
	var models: Array = []
	for spec: Dictionary in specs:
		models.append(building.get_room(int(spec["id"])))
	return {"engine": engine, "building": building, "rooms": models, "dt": float(options["dt"])}


func _hot_upper_layer(room, upper_kg: float, lower_kg: float, kj_per_kg: float) -> void:
	room.upper_gas_kg = upper_kg
	room.lower_gas_kg = lower_kg
	room.upper_energy_kj = upper_kg * kj_per_kg
	room.lower_energy_kj = 0.0


func _door(open_fraction: float) -> Dictionary:
	return {"a": 0, "b": 1, "type": "door", "width_m": 0.9, "height_m": 2.0, "sill_m": 0.0, "offset_m": 0.5,
		"offset_is_fraction": true, "open_fraction": open_fraction, "wall": "", "hinge_side": "left", "swing_direction": "in"}


func _outside_door() -> Dictionary:
	return {"a": 0, "b": -1, "type": "door", "width_m": 0.9, "height_m": 2.0, "open_fraction": 1.0, "offset_m": 0.5,
		"offset_is_fraction": true, "sill_m": 0.0, "wall": "bottom"}


func _free(world: Dictionary) -> void:
	world["engine"].queue_free()
	world["building"].queue_free()


# ---------------------------------------------------------------- checks

func _same(a: float, b: float) -> bool:
	return a == b or (is_nan(a) and is_nan(b))


func _near_rel(value: float, expected: float, label: String) -> void:
	_check(is_finite(value) and absf(value - expected) <= REL_TOL * maxf(1.0, absf(expected)), "%s (%s against %s)" % [label, str(value), str(expected)])


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

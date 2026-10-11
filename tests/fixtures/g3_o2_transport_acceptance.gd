extends "res://tests/fixtures/g3_o2_m3_diagnosis.gd"

## Acceptance of M2-T only: paired immediate O2 mixing on fixed reference gas.
## Neither the fire model, real gas mass, CO/FED nor species delays are validated.
const TRANSPORT_GAP_KG: float = 1.0e-9
const TRANSPORT_X_TOL: float = 1.0e-12
var _transport_checks: int = 0
var _transport_failures: Array[String] = []
var _transport_failed_by_group: Dictionary = {}
var _transport_group: String = ""


func _run() -> void:
	_matrix()
	_atomic_refusals()
	_callers()
	_live_engine()
	_lifecycle()
	print("G3_O2_TRANSPORT " + JSON.stringify({
		"checks": _transport_checks, "groups": ["T01", "T02", "T03", "T04", "T05"],
		"failures": _transport_failures, "failure_count": _transport_failures.size(),
		"failures_by_group": _transport_failed_by_group,
	}, "", true, true))
	if _transport_failures.is_empty():
		print("G3_O2_TRANSPORT_PASS")
		quit(0)
	else:
		quit(1)


func _transport_check(ok: bool, label: String) -> void:
	_transport_checks += 1
	if not ok:
		_transport_failures.append(_transport_group + ": " + label)
		_transport_failed_by_group[_transport_group] = int(_transport_failed_by_group.get(_transport_group, 0)) + 1


func _transport_near(actual: float, expected: float, tolerance: float, label: String) -> void:
	_transport_check(is_finite(actual) and absf(actual - expected) <= tolerance, label)


func _transport_world() -> Dictionary:
	return _world({"rooms": 2, "door": true, "dt": 0.25, "fire": SOFA})


func _release_world(world: Dictionary) -> void:
	world["engine"].queue_free()
	world["building"].queue_free()


func _matrix() -> void:
	_transport_group = "T01"
	for fractions: Array in [[0.209, 0.209], [0.10, 0.209], [0.209, 0.10], [0.30, 0.10], [0.0, 0.209]]:
		for share: float in [0.0, 0.04, 0.50, 1.0]:
			var world: Dictionary = _transport_world()
			var owner = world["engine"].get("_o2_room_inventory")
			var a = world["rooms"][0]
			var b = world["rooms"][1]
			owner.declare_initial_mole_fraction(a, fractions[0])
			owner.declare_initial_mole_fraction(b, fractions[1])
			_transport_check(owner.has_method("exchange_reference_gas_between_rooms"), "new live owner operation exists")
			if not owner.has_method("exchange_reference_gas_between_rooms"):
				_release_world(world)
				continue
			# Independent oracle: dry-air reference content, NOT owner constants.
			var ca: float = a.volume_m3() * 1.2
			var cb: float = b.volume_m3() * 1.2
			var q: float = minf(ca, cb) * share
			var initial_kg: float = a.o2_inventory_kg + b.o2_inventory_kg
			var answer: Dictionary = owner.exchange_reference_gas_between_rooms(a, b, q, "matrix")
			_transport_check(bool(answer.get("applied", false)), "matrix exchange applies")
			_transport_near(a.o2, float(fractions[0]) + q / ca * (float(fractions[1]) - float(fractions[0])), TRANSPORT_X_TOL, "donor convex mixture")
			_transport_near(b.o2, float(fractions[1]) + q / cb * (float(fractions[0]) - float(fractions[1])), TRANSPORT_X_TOL, "receiver convex mixture")
			_transport_near(a.o2_inventory_kg + b.o2_inventory_kg, initial_kg, TRANSPORT_GAP_KG, "sum of both rooms closes")
			_transport_check(not bool(answer.get("delayed", true)), "neither end is deferred")
			_transport_check(owner.report()["transit"].is_empty(), "no signed debt or positive future credit")
			_transport_near(float(answer.get("donor_net_kg", NAN)) + float(answer.get("receiver_net_kg", NAN)), 0.0, TRANSPORT_GAP_KG, "return nets cancel")
			owner.begin_step(world["engine"].call("_o2_room_inventory_environment"))
			var selected: Dictionary = owner.selection_for(b, "fire")
			_transport_near(float(selected.get("available_kg", NAN)), b.o2_inventory_kg, TRANSPORT_GAP_KG, "all present oxygen is uncommitted")
			var before_clock: float = a.o2_inventory_kg + b.o2_inventory_kg
			_transport_check(owner.advance_transit(100.0).is_empty(), "clock cannot apply a second credit")
			_transport_near(a.o2_inventory_kg + b.o2_inventory_kg, before_clock, TRANSPORT_GAP_KG, "clock leaves inventory unchanged")
			# An exterior operation followed by repeated exchange must remain convex.
			for repeat_index: int in range(25):
				var before_a: float = a.o2
				var before_b: float = b.o2
				owner.dilute_with_outside(a, 0.01 * ca, 0.209, "matrix_outside")
				var exchange: Dictionary = owner.exchange_reference_gas_between_rooms(a, b, 0.04 * minf(ca, cb), "matrix_repeat")
				_transport_check(bool(exchange.get("applied", false)), "repeated exchange applies")
				_transport_check(a.o2 <= maxf(0.209, maxf(before_a, before_b)) + TRANSPORT_X_TOL and b.o2 <= maxf(0.209, maxf(before_a, before_b)) + TRANSPORT_X_TOL, "mix/dilution create no enrichment")
			_release_world(world)


func _atomic_refusals() -> void:
	_transport_group = "T02"
	for quantity: float in [-1.0, NAN, INF, 100000.0]:
		var world: Dictionary = _transport_world()
		var owner = world["engine"].get("_o2_room_inventory")
		var a = world["rooms"][0]
		var b = world["rooms"][1]
		if owner.has_method("exchange_reference_gas_between_rooms"):
			var before: Dictionary = owner.report()["rooms"]
			var answer: Dictionary = owner.exchange_reference_gas_between_rooms(a, b, quantity, "invalid")
			_transport_check(not bool(answer.get("applied", true)), "invalid amount rejected")
			_transport_check(owner.report()["rooms"] == before, "refusal changes neither room nor its counters")
			_transport_check(owner.report()["transit"].is_empty(), "refusal creates no entry")
		_release_world(world)
	var world: Dictionary = _transport_world()
	var owner = world["engine"].get("_o2_room_inventory")
	var a = world["rooms"][0]
	var b = world["rooms"][1]
	if owner.has_method("exchange_reference_gas_between_rooms"):
		owner.exchange_between_rooms(a, b, 0.0, 0.10, 10.0, "explicit_legacy_diagnostic_debt")
		var before: Dictionary = owner.report()["rooms"]
		var answer: Dictionary = owner.exchange_reference_gas_between_rooms(a, b, 1.0, "must_not_mix_with_legacy_injection")
		_transport_check(not bool(answer.get("applied", true)), "live exchange refuses diagnostic legacy transit")
		_transport_check(owner.report()["rooms"] == before, "mixed-contract refusal is atomic")
	_release_world(world)


func _callers() -> void:
	_transport_group = "T03"
	for route: String in ["background", "active"]:
		var world: Dictionary = _transport_world()
		var engine = world["engine"]
		var owner = engine.get("_o2_room_inventory")
		var a = world["rooms"][0]
		var b = world["rooms"][1]
		owner.declare_initial_mole_fraction(a, 0.10)
		owner.declare_initial_mole_fraction(b, 0.209)
		var before_a: float = a.o2_inventory_kg
		var before_b: float = b.o2_inventory_kg
		var q: float = 0.04 * minf(a.volume_m3(), b.volume_m3()) * 1.2
		var oes = engine.get("oxygen_exchange_system")
		if route == "background":
			oes.call("_exchange_room_o2_immediate", a, b, q, 1.2)
		else:
			oes.call("_exchange_owned_o2_active_flow", world["building"], a, b, q)
		var expected_delta: float = q * (0.209 - 0.10) * (0.031998 / 0.0289647)
		_transport_near(a.o2_inventory_kg - before_a, expected_delta, TRANSPORT_GAP_KG, route + " donor change")
		_transport_near(b.o2_inventory_kg - before_b, -expected_delta, TRANSPORT_GAP_KG, route + " receiver changes immediately")
		_transport_near(a.o2_net_transport_kg_step, expected_delta, TRANSPORT_GAP_KG, route + " donor audit")
		_transport_near(b.o2_net_transport_kg_step, -expected_delta, TRANSPORT_GAP_KG, route + " receiver audit")
		_transport_check(owner.report()["transit"].is_empty(), route + " never dispatches debt")
		var operations: Array = owner.report()["step_operations"]
		_transport_check(not operations.is_empty() and operations.back().get("law", "") == "symmetric_reference_gas_immediate", route + " calls live law")
		_release_world(world)


func _live_engine() -> void:
	_transport_group = "T04"
	var world: Dictionary = _transport_world()
	var engine = world["engine"]
	var owner = engine.get("_o2_room_inventory")
	var active_calls: int = 0
	for step_index: int in range(480):
		var before: Dictionary = owner.report()
		var before_kg: float = _sum_room_inventory(before) + float(before["in_transit_kg"])
		engine.step(0.25)
		var after: Dictionary = owner.report()
		_transport_check(str(engine.get("o2_room_inventory_failure")) == "", "engine step not rejected")
		var outside_kg: float = 0.0
		var consumed_kg: float = 0.0
		for operation: Dictionary in after["step_operations"]:
			if operation["kind"] == "outside":
				outside_kg += float(operation["in_kg"]) - float(operation["out_kg"])
			if operation["kind"] == "consume":
				consumed_kg += float(operation["applied_kg"])
			if operation.get("cause", "") == "interior_active_flow":
				active_calls += 1
		_transport_near(_sum_room_inventory(after) - before_kg - outside_kg + consumed_kg, 0.0, TRANSPORT_GAP_KG, "per-step building O2 budget")
		_transport_check(after["transit"].is_empty(), "live engine has no future obligations")
		for room_state: Dictionary in after["rooms"].values():
			_transport_check(float(room_state["mole_fraction"]) <= 0.209 + TRANSPORT_X_TOL, "room does not enrich above initial/outside")
	_transport_check(active_calls > 0, "real fire exercises active doorway route")
	_release_world(world)


func _sum_room_inventory(report: Dictionary) -> float:
	var result: float = 0.0
	for room_state: Dictionary in report["rooms"].values():
		result += float(room_state["inventory_kg"])
	return result


func _lifecycle() -> void:
	_transport_group = "T05"
	var world: Dictionary = _transport_world()
	var engine = world["engine"]
	var owner = engine.get("_o2_room_inventory")
	owner.exchange_between_rooms(world["rooms"][0], world["rooms"][1], 0.0, 0.10, 10.0, "explicit_legacy_diagnostic_debt")
	engine.reset_simulation(0, true)
	owner = engine.get("_o2_room_inventory")
	_transport_check(owner.report()["transit"].is_empty(), "reset discards all diagnostic transit")
	_transport_check(owner.report().get("live_transport_policy", "") == "symmetric_reference_gas_immediate_o2_only", "report names new approximation")
	engine.set("o2_room_inventory_enabled", false)
	engine.reset_simulation(0, true)
	_transport_check(engine.get("_o2_room_inventory") == null, "flag OFF has no owner")
	_release_world(world)

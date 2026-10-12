extends SceneTree

## M3 owner acceptance only. Not an integrated fire, material or CO validation.
const Inventory = preload("res://sim/core/RoomOxygenInventory.gd")
const Room = preload("res://sim/building/RoomModel.gd")
const K: float = 0.076

class Rooms extends RefCounted:
	var outside_o2: float = 0.209
	var rooms: Dictionary = {}
	func get_rooms() -> Dictionary:
		return rooms
	func get_room(room_id: int):
		return rooms.get(room_id)

var checks: int = 0
var failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)

func _near(a: float, b: float, label: String) -> void:
	_check(absf(a - b) <= 1.0e-9, label)

func _world() -> Dictionary:
	var building = Rooms.new()
	for id: int in [0, 1]:
		var room = Room.new()
		room.id = id
		room.width_m = 5.0
		room.length_m = 4.0
		room.height_m = 2.4
		building.rooms[id] = room
	var owner = Inventory.new()
	var environment: Dictionary = Inventory.REQUIRED_ENVIRONMENT.duplicate(true)
	environment["combustion_acceptance_enabled"] = true
	_check(bool(owner.arm(building, 7, environment)["valid"]), "arming")
	owner.begin_step(environment)
	return {"building": building, "owner": owner, "a": building.rooms[0],
		"b": building.rooms[1], "environment": environment}

func _selection(world: Dictionary) -> Dictionary:
	return world.owner.selection_for(world.a, "fire")

func _reason(result: Dictionary, expected: String, label: String) -> void:
	_check(not bool(result.get("applied", true)) and result.get("reason") == expected, label)

func _run() -> void:
	var world: Dictionary = _world()
	var before: float = world.a.o2_inventory_kg
	var selected: Dictionary = _selection(world)
	var accepted: Dictionary = world.owner.reserve_combustion(world.a, selected, 1.0, K)
	_check(bool(accepted["applied"]), "normal proposal accepted")
	_near(float(accepted["fraction"]), 1.0, "normal fraction")
	_near(world.a.o2_inventory_kg, before, "reserve moves no oxygen")
	_near(float(accepted["reserved_kg"]), K, "oxygen of heat reserved")
	var debit: Dictionary = world.owner.consume_reserved_combustion(world.a, selected, 1.0, K)
	_check(bool(debit["applied"]), "debit accepted")
	_near(world.a.o2_inventory_kg, before - K, "exact debit")
	_near(float(debit["clipped_kg"]), 0.0, "no sink cap")
	world.owner.audit_combustion_reservations()
	_check(world.owner.state() == "armed", "settled step closes")

	world = _world()
	before = world.a.o2_inventory_kg
	selected = _selection(world)
	accepted = world.owner.reserve_combustion(world.a, selected, 2.0 * before / K, K)
	_near(float(accepted["fraction"]), 0.5, "scarcity scales whole proposal")
	_near(float(accepted["reserved_kg"]), before, "can reserve all available, not five percent")
	debit = world.owner.consume_reserved_combustion(world.a, selected, float(accepted["accepted_heat_MJ"]), K)
	_check(bool(debit["applied"]), "full-inventory settlement")
	_near(world.a.o2_inventory_kg, 0.0, "inventory exhausted without negative clamp")

	world = _world()
	selected = _selection(world)
	selected["available_kg"] = 0.0
	selected["inventory_kg"] = 0.0
	accepted = world.owner.reserve_combustion(world.a, selected, 1.0, K)
	_near(float(accepted["reserved_kg"]), K, "caller cannot forge availability")
	_check(bool(world.owner.consume_reserved_combustion(world.a, selected, 1.0, K)["applied"]),
		"forged availability still settles canonical selection")

	world = _world()
	selected = _selection(world)
	world.owner.exchange_with_outside(world.a, 1.0, 0.0, world.a.o2, "diagnostic_change")
	before = world.a.o2_inventory_kg
	_reason(world.owner.reserve_combustion(world.a, selected, 1.0, K),
		"inventory_changed_before_combustion_acceptance", "changed inventory refuses reservation")
	_near(world.a.o2_inventory_kg, before, "changed inventory refusal is atomic")

	world = _world()
	before = world.a.o2_inventory_kg
	world.owner.exchange_between_rooms(world.b, world.a, before, 0.0, 1.0, "diagnostic_positive_arrival")
	world.owner.begin_step(world.environment)
	selected = _selection(world)
	accepted = world.owner.reserve_combustion(world.a, selected, 2.0 * before / K, K)
	_near(float(accepted["reserved_kg"]), before, "positive pending arrival is not available")
	_near(float(accepted["fraction"]), 0.5, "pending arrival cannot increase accepted heat")

	world = _world()
	selected = _selection(world)
	accepted = world.owner.reserve_combustion(world.a, selected, 0.0, K)
	_near(float(accepted["fraction"]), 1.0, "zero heat does not divide by zero")
	_near(float(accepted["reserved_kg"]), 0.0, "zero heat reserves zero")
	_check(bool(world.owner.consume_reserved_combustion(world.a, selected, 0.0, K)["applied"]),
		"zero heat can be settled")
	world.owner.audit_combustion_reservations()
	_check(world.owner.state() == "armed", "zero heat reservation closes")

	for field: String in ["generation", "step", "room", "id"]:
		world = _world()
		selected = _selection(world)
		selected[field] = int(selected[field]) + 1
		before = world.a.o2_inventory_kg
		accepted = world.owner.reserve_combustion(world.a, selected, 1.0, K)
		_check(not bool(accepted["applied"]), "reject wrong selection " + field)
		_near(world.a.o2_inventory_kg, before, "wrong selection atomic " + field)

	for invalid: Variant in [-1.0, NAN, INF, "1", null]:
		world = _world()
		_reason(world.owner.reserve_combustion(world.a, _selection(world), invalid, K),
			"combustion_proposal_not_finite", "invalid heat " + str(invalid))
	for invalid: Variant in [0.0, -1.0, NAN, INF, "0.076", null]:
		world = _world()
		_reason(world.owner.reserve_combustion(world.a, _selection(world), 1.0, invalid),
			"combustion_proposal_not_finite", "invalid coefficient " + str(invalid))

	world = _world()
	selected = _selection(world)
	world.owner.reserve_combustion(world.a, selected, 1.0, K)
	_reason(world.owner.reserve_combustion(world.a, selected, 1.0, K),
		"combustion_already_reserved", "one reservation only")
	world = _world()
	selected = _selection(world)
	world.owner.reserve_combustion(world.a, selected, 1.0, K)
	world.owner.consume_reserved_combustion(world.a, selected, 1.0, K)
	_reason(world.owner.consume_reserved_combustion(world.a, selected, 1.0, K),
		"selection_already_debited", "one debit only")
	world = _world()
	_reason(world.owner.consume_reserved_combustion(world.a, _selection(world), 1.0, K),
		"combustion_without_reservation", "no invented reservation")
	world = _world()
	_reason(world.owner.consume(world.a, _selection(world), K, K, "old_sink"),
		"unreserved_fire_debit", "old debit cannot bypass acceptance")

	for heat: float in [0.0, 1.5, 2.2]:
		world = _world()
		selected = _selection(world)
		world.owner.reserve_combustion(world.a, selected, 1.0, K)
		before = world.a.o2_inventory_kg
		_reason(world.owner.consume_reserved_combustion(world.a, selected, heat, K),
			"heat_changed_after_combustion_acceptance", "post-acceptance heat change " + str(heat))
		_near(world.a.o2_inventory_kg, before, "invalid settlement atomic")

	world = _world()
	selected = _selection(world)
	world.owner.reserve_combustion(world.a, selected, 1.0, K)
	before = world.a.o2_inventory_kg
	_reason(world.owner.consume_reserved_combustion(world.a, selected, 1.0, K * 2.0),
		"heat_changed_after_combustion_acceptance", "coefficient cannot change after acceptance")
	_near(world.a.o2_inventory_kg, before, "changed coefficient refusal is atomic")

	for invalid: Variant in [-1.0, NAN, INF, "1", null]:
		world = _world()
		selected = _selection(world)
		world.owner.reserve_combustion(world.a, selected, 1.0, K)
		before = world.a.o2_inventory_kg
		_reason(world.owner.consume_reserved_combustion(world.a, selected, invalid, K),
			"combustion_settlement_not_finite", "invalid settlement quantity " + str(invalid))
		_near(world.a.o2_inventory_kg, before, "invalid settlement quantity is atomic")

	world = _world()
	world.owner.reserve_combustion(world.a, _selection(world), 1.0, K)
	world.owner.audit_combustion_reservations()
	var unsettled_rejections: Array = world.owner.report()["rejections"]
	_check(not unsettled_rejections.is_empty() and
		unsettled_rejections[-1]["reason"] == "combustion_reservation_not_debited",
		"unsettled reservation cannot close")
	world = _world()
	world.owner.reserve_combustion(world.a, _selection(world), 1.0, K)
	world.owner.begin_step(world.environment)
	_check(world.owner.state() == "rejected", "opening next step cannot discard outstanding reservation")

	for route: String in ["outside", "dilution", "live_exchange", "legacy_exchange"]:
		world = _world()
		before = world.a.o2_inventory_kg
		var other_before: float = world.b.o2_inventory_kg
		# Whole inventory reserved; an outgoing operation must be refused before either end changes.
		selected = _selection(world)
		world.owner.reserve_combustion(world.a, selected, 2.0 * before / K, K)
		var result: Dictionary
		match route:
			"outside":
				result = world.owner.exchange_with_outside(world.a, 1.0, 0.0, world.a.o2, "test_outside")
			"dilution":
				_check(not world.owner.outside_dilution_would_apply(world.a, 1.0, 0.0), "dilution preflight protects reservation")
				result = world.owner.dilute_with_outside(world.a, 1.0, 0.0, "test_dilution")
			"live_exchange":
				# Lower the OTHER room by a permitted operation before the attempted exchange.
				world.owner.exchange_with_outside(world.b, 1.0, 0.0, world.b.o2, "lower_other")
				other_before = world.b.o2_inventory_kg
				result = world.owner.exchange_reference_gas_between_rooms(world.a, world.b, 1.0, "test_live")
			_:
				result = world.owner.exchange_between_rooms(world.a, world.b, 0.01, 0.0, 0.0, "test_legacy")
		_reason(result, "operation_spends_reserved_combustion_oxygen", "protected " + route)
		_near(world.a.o2_inventory_kg, before, "reserved room unchanged " + route)
		_near(world.b.o2_inventory_kg, other_before, "other room unchanged on refusal " + route)

	world = _world()
	before = world.a.o2_inventory_kg
	# Historical debt is explicitly injected; the live M2-T transport does not generate it.
	world.owner.exchange_between_rooms(world.b, world.a, 0.0, before - 0.02, 1.0, "diagnostic_debt")
	world.owner.begin_step(world.environment)
	selected = _selection(world)
	accepted = world.owner.reserve_combustion(world.a, selected, 1.0, K)
	_near(float(accepted["reserved_kg"]), 0.02, "all negative obligations deducted")
	var arrivals: Array = world.owner.advance_transit(1.0)
	_check(arrivals.size() == 1, "negative arrival delivered without spending reservation")
	_check(bool(world.owner.consume_reserved_combustion(world.a, selected,
		float(accepted["accepted_heat_MJ"]), K)["applied"]), "debt plus reservation settles")
	_near(world.a.o2_inventory_kg, 0.0, "debt and accepted heat exactly exhaust room")

	world = _world()
	selected = _selection(world)
	world.owner.reserve_combustion(world.a, selected, 1.0, K)
	world.owner.discard()
	_check(world.owner.report()["selections"].is_empty(), "reset clears reservations")
	_check(not world.owner.combustion_acceptance_enabled(), "discard clears acceptance mode")
	print("G3_O2_M3_RESERVATION " + JSON.stringify({"checks": checks,
		"failure_count": failures.size(), "failures": failures}, "", true, true))
	quit(0 if failures.is_empty() else 1)

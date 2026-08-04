extends SceneTree

## H3.2-S0c runtime fixture: passive GasExchangeSystem physical-owner events.
##
## Every positive case drives a real legacy mutation site. The fixture never
## asserts on reconstructed stage deltas and never lets telemetry change a
## physical result.

const BuildingModelScript = preload("res://sim/BuildingModel.gd")
const GasExchangeSystemScript = preload("res://sim/core/GasExchangeSystem.gd")
const OpeningModelScript = preload("res://sim/building/OpeningModel.gd")
const Phase3PhysicalOwnerLedgerScript = preload("res://sim/core/Phase3PhysicalOwnerLedger.gd")
const RoomModelScript = preload("res://sim/building/RoomModel.gd")
const ThermalSystemScript = preload("res://sim/core/ThermalSystem.gd")

const EPS: float = 1.0e-12

var _failed: bool = false


func _init() -> void:
	_test_default_off_emits_nothing()
	_test_exterior_upper_removal_has_direction()
	_test_off_upper_removal_is_identical()
	_test_background_transport_conserves()
	_test_parcel_lifecycle_and_refund()
	_test_step_local_reset_and_pure_export()
	if _failed:
		quit(1)
		return
	print("PHASE3_H32S0C_GAS_PHYSICAL_OWNERS_PASS")
	quit(0)


func _test_default_off_emits_nothing() -> void:
	var gas = GasExchangeSystemScript.new()
	_expect(not gas.phase3_physical_owner_ledger_enabled, "flag default OFF")
	var room = _room(0)
	gas._record_phase3_physical_owner_event(
		"off_probe", "local_source", room, 0.0, 0.0, 1.0, 0.0
	)
	_expect(gas.get_phase3_physical_owner_events().is_empty(), "OFF emits nothing")
	var summary: Dictionary = gas.get_phase3_physical_owner_summary()
	_expect(int(summary["valid_event_count"]) == 0, "OFF has no valid events")
	_expect(bool(summary["valid"]), "OFF aggregate stays valid")


func _test_exterior_upper_removal_has_direction() -> void:
	var gas = GasExchangeSystemScript.new()
	gas.phase3_physical_owner_ledger_enabled = true
	var thermal = ThermalSystemScript.new()
	var room = _room(3)
	room.upper_gas_kg = 8.0
	room.upper_energy_kj = 900.0
	gas._call_room_fraction_owned(
		Callable(thermal, "remove_upper_layer_fraction"),
		room,
		0.25,
		"gas_pressure_vent_upper_removal",
		{"mechanism": "pressure_venting"}
	)
	var events: Array = gas.get_phase3_physical_owner_events()
	_expect(events.size() == 1, "one exterior removal event")
	if events.size() != 1:
		return
	var event: Dictionary = events[0]
	_expect(String(event["classification"]) == "exterior_boundary", "exterior class")
	_expect(int(event["source_room_id"]) == room.id, "room is the source side")
	_expect(int(event["destination_room_id"]) == -1, "exterior is the destination")
	_expect(String(event["source_zone"]) == "upper", "upper source zone")
	_expect(String(event["destination_zone"]).is_empty(), "exterior has no zone")
	_expect(
		String(event["metadata"]["direction"]) == "room_to_exterior",
		"direction is explicit"
	)
	_expect(absf(float(event["upper_mass_delta_kg"]) + 2.0) <= 1.0e-9, "accepted mass debit")
	_expect(
		absf(float(event["upper_energy_delta_kj"]) + 225.0) <= 1.0e-9,
		"accepted energy debit"
	)
	_expect(String(event["event_id"]).begins_with("gas:000000:"), "gas id namespace")
	_expect(bool(gas.get_phase3_physical_owner_summary()["valid"]), "removal aggregate valid")


func _test_off_upper_removal_is_identical() -> void:
	var thermal = ThermalSystemScript.new()
	var off_gas = GasExchangeSystemScript.new()
	var on_gas = GasExchangeSystemScript.new()
	on_gas.phase3_physical_owner_ledger_enabled = true
	var off_room = _room(4)
	off_room.upper_gas_kg = 6.0
	off_room.upper_energy_kj = 300.0
	var on_room = _room(4)
	on_room.upper_gas_kg = 6.0
	on_room.upper_energy_kj = 300.0
	off_gas._call_room_fraction_owned(
		Callable(thermal, "remove_upper_layer_fraction"), off_room, 0.4, "probe"
	)
	on_gas._call_room_fraction_owned(
		Callable(thermal, "remove_upper_layer_fraction"), on_room, 0.4, "probe"
	)
	_expect(off_room.upper_gas_kg == on_room.upper_gas_kg, "OFF/ON mass identical")
	_expect(off_room.upper_energy_kj == on_room.upper_energy_kj, "OFF/ON energy identical")
	_expect(off_gas.get_phase3_physical_owner_events().is_empty(), "OFF stays silent")


func _test_background_transport_conserves() -> void:
	var building = BuildingModelScript.new()
	building.outside_temp_c = 20.0
	building.outside_o2 = 0.209
	var hot = _room(0)
	hot.temp_upper_c = 250.0
	hot.upper_gas_kg = 5.0
	hot.upper_energy_kj = 900.0
	hot.smoke_kg = 4.0
	var cold = _room(1)
	cold.temp_upper_c = 25.0
	cold.upper_gas_kg = 0.5
	cold.upper_energy_kj = 5.0
	building.rooms = {0: hot, 1: cold}
	var opening = OpeningModelScript.new(0, 1, 0, 0.9, 2.0, 1.0, 0.0)
	opening.opening_index = 5
	building.openings = [opening]

	var gas = GasExchangeSystemScript.new()
	gas.phase3_physical_owner_ledger_enabled = true
	var hot_before_kg: float = hot.upper_gas_kg
	var cold_before_kg: float = cold.upper_gas_kg
	var deltas: Dictionary = _empty_deltas()
	gas._apply_background_species_exchange(
		building, hot, cold, opening, 1.0,
		deltas["smoke"], deltas["co"], deltas["co_upper"],
		deltas["co2"], deltas["co2_upper"], deltas["hcn"], deltas["hcn_upper"],
		deltas["hcl"], deltas["acrolein"], deltas["formaldehyde"], deltas["o2"]
	)
	var events: Array = gas.get_phase3_physical_owner_events()
	_expect(events.size() == 1, "one background transport event")
	if events.size() == 1:
		var event: Dictionary = events[0]
		_expect(
			String(event["classification"]) == "interior_transport",
			"background is interior transport"
		)
		_expect(int(event["source_room_id"]) == 0, "hot room is the source")
		_expect(int(event["destination_room_id"]) == 1, "cold room is the destination")
		_expect(float(event["upper_mass_delta_kg"]) < 0.0, "source debit is negative")
		_expect(
			float(event["counterparty_mass_delta_kg"]) > 0.0,
			"destination credit is positive"
		)
		_expect(
			absf(float(event["upper_mass_delta_kg"])
					+ float(event["counterparty_mass_delta_kg"])) <= EPS,
			"transport mass conserved"
		)
		_expect(
			absf(float(event["upper_energy_delta_kj"])
					+ float(event["counterparty_energy_delta_kj"])) <= EPS,
			"transport energy conserved"
		)
		_expect(
			absf(float(event["upper_mass_delta_kg"])
					- (hot.upper_gas_kg - hot_before_kg)) <= 1.0e-12,
			"event debit equals accepted mutation"
		)
		_expect(
			absf(float(event["counterparty_mass_delta_kg"])
					- (cold.upper_gas_kg - cold_before_kg)) <= 1.0e-12,
			"event credit equals accepted mutation"
		)
	var summary: Dictionary = gas.get_phase3_physical_owner_summary()
	_expect(bool(summary["valid"]), "background aggregate valid")
	_expect(
		absf(float(summary["interior_transport_mass_residual_kg"])) <= EPS,
		"interior mass residual closes"
	)
	_expect(
		absf(float(summary["interior_transport_energy_residual_kj"])) <= EPS,
		"interior energy residual closes"
	)
	building.free()


func _test_parcel_lifecycle_and_refund() -> void:
	var building = BuildingModelScript.new()
	building.outside_temp_c = 20.0
	building.outside_o2 = 0.209
	var source = _room(0)
	source.co_kg = 0.02
	source.co_upper_kg = 0.02
	var target = _room(1)
	target.co_kg = 0.40
	target.co_upper_kg = 0.40
	building.rooms = {0: source, 1: target}

	var gas = GasExchangeSystemScript.new()
	gas.phase3_physical_owner_ledger_enabled = true
	var entry: Dictionary = {
		"from": 0,
		"target": 1,
		"connection_id": "opening:2",
		"delay_s": 0.0,
		"smoke_kg": 0.5,
		"co_kg": 0.30,
		"co_upper_kg": 0.30,
		"co2_kg": 0.0,
		"co2_upper_kg": 0.0,
		"hcn_kg": 0.0,
		"hcn_upper_kg": 0.0,
		"hcl_kg": 0.0,
		"acrolein_kg": 0.0,
		"formaldehyde_kg": 0.0,
		"upper_gas_kg": 1.25,
		"upper_energy_kj": 62.5,
		"o2_kg": 0.0,
	}
	gas._assign_phase3_physical_owner_parcel_id(entry)
	_expect(
		String(entry["phase3_physical_owner_parcel_id"]) == "gas_parcel:000000",
		"deterministic parcel id"
	)
	var source_co_before_kg: float = source.co_kg
	var target_gas_before_kg: float = target.upper_gas_kg
	var pending: Array[Dictionary] = [entry]
	gas._pending_interior_deliveries = pending
	gas._release_pending_interior_deliveries(building, 1.0, Callable())

	var events: Array = gas.get_phase3_physical_owner_events()
	_expect(events.size() == 1, "one delivery event")
	if events.size() != 1:
		building.free()
		return
	var event: Dictionary = events[0]
	_expect(String(event["classification"]) == "delayed_parcel", "delivery is a parcel")
	_expect(String(event["metadata"]["lifecycle"]) == "delivered", "delivered lifecycle")
	_expect(
		String(event["metadata"]["parcel_id"]) == "gas_parcel:000000",
		"delivery keeps the parcel identity"
	)
	_expect(int(event["room_id"]) == 1, "delivery credits the destination")
	_expect(
		absf(float(event["upper_mass_delta_kg"])
				- (target.upper_gas_kg - target_gas_before_kg)) <= 1.0e-12,
		"delivered gas equals accepted mutation"
	)
	var original: Dictionary = event["metadata"]["original_species_kg"]
	var delivered: Dictionary = event["metadata"]["delivered_species_kg"]
	var refunded: Dictionary = event["metadata"]["refunded_species_kg"]
	_expect(float(refunded.get("co", 0.0)) > 0.0, "headroom forces a real CO refund")
	_expect(
		absf(float(original["co"]) - float(delivered["co"]) - float(refunded["co"])) <= 1.0e-12,
		"parcel CO inventory conserved"
	)
	_expect(
		absf((source.co_kg - source_co_before_kg) - float(refunded["co"])) <= 1.0e-12,
		"refund matches the source mutation"
	)
	var summary: Dictionary = gas.get_phase3_physical_owner_summary()
	_expect(bool(summary["valid"]), "parcel aggregate valid")
	var diagnostics: Dictionary = summary["gas_owner_diagnostics"]
	_expect(int(diagnostics["parcel_delivered_count"]) == 1, "one delivery counted")
	_expect(int(diagnostics["parcel_created_count"]) == 0, "no creation in this step")
	_expect(
		float(diagnostics["parcel_refund_max_residual_kg"]) <= EPS,
		"refund residual closes"
	)
	_expect(
		float(summary["totals_by_classification"]["interior_transport"]["mass_delta_kg"]) == 0.0,
		"a parcel is never consummated transport"
	)
	building.free()


func _test_step_local_reset_and_pure_export() -> void:
	var gas = GasExchangeSystemScript.new()
	gas.phase3_physical_owner_ledger_enabled = true
	var room = _room(2)
	gas._record_phase3_physical_owner_event(
		"probe_source", "local_source", room, 0.0, 0.0, 4.0, 0.0
	)
	gas._record_phase3_physical_owner_event(
		"probe_sink", "local_source", room, 0.0, 0.0, -1.0, 0.0
	)
	var events: Array = gas.get_phase3_physical_owner_events()
	_expect(events.size() == 2, "two probe events")
	_expect(String(events[0]["event_id"]) == "gas:000000:probe_source:r2", "first id")
	_expect(String(events[1]["event_id"]) == "gas:000001:probe_sink:r2", "second id")
	var before: String = JSON.stringify(gas.get_phase3_physical_owner_events())
	var first: String = JSON.stringify(gas.get_phase3_physical_owner_summary())
	var second: String = JSON.stringify(gas.get_phase3_physical_owner_summary())
	_expect(first == second, "summary export idempotent")
	_expect(JSON.stringify(gas.get_phase3_physical_owner_events()) == before, "export pure")

	gas.begin_phase3_physical_owner_step()
	_expect(gas.get_phase3_physical_owner_events().is_empty(), "step reset clears events")
	gas._record_phase3_physical_owner_event(
		"probe_source", "local_source", room, 0.0, 0.0, 4.0, 0.0
	)
	_expect(
		String(gas.get_phase3_physical_owner_events()[0]["event_id"])
				== "gas:000000:probe_source:r2",
		"sequence restarts each step"
	)

	# Fail-closed: a duplicated ID must be visible, never silently merged.
	var duplicated: Array = gas.get_phase3_physical_owner_events()
	duplicated.append(duplicated[0].duplicate(true))
	var duplicate_summary: Dictionary = _aggregate(duplicated)
	_expect(not bool(duplicate_summary["valid"]), "duplicate id fails closed")
	_expect(int(duplicate_summary["duplicate_event_count"]) == 1, "duplicate counted")


func _aggregate(events: Array) -> Dictionary:
	return Phase3PhysicalOwnerLedgerScript.aggregate_events(events)


func _empty_deltas() -> Dictionary:
	var deltas: Dictionary = {}
	for key in [
		"smoke", "co", "co_upper", "co2", "co2_upper", "hcn", "hcn_upper",
		"hcl", "acrolein", "formaldehyde", "o2",
	]:
		deltas[key] = {0: 0.0, 1: 0.0}
	return deltas


func _room(room_id: int):
	var room = RoomModelScript.new()
	room.id = room_id
	room.width_m = 5.0
	room.length_m = 4.0
	room.height_m = 2.5
	room.thermal_layer_m = 1.0
	room.temp_upper_c = 80.0
	room.temp_lower_c = 20.0
	room.upper_gas_kg = 2.0
	room.lower_gas_kg = 20.0
	room.upper_energy_kj = 120.0
	room.lower_energy_kj = 10.0
	room.o2 = 0.209
	room.o2_upper = 0.209
	room.o2_lower = 0.209
	return room


func _expect(condition: bool, label: String) -> void:
	if condition:
		return
	_failed = true
	push_error("H3.2-S0c ASSERTION FAILED: %s" % label)

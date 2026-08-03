extends SceneTree

const Ledger = preload("res://sim/core/Phase3PhysicalOwnerLedger.gd")

var _failed: bool = false


func _init() -> void:
	_test_local_source()
	_test_exterior_boundary()
	_test_interzone_both_directions()
	_test_interior_transport_and_counterflow()
	_test_parcel_and_numerical_are_not_sources()
	_test_invalid_events_fail_closed()
	_test_determinism_and_input_purity()
	_test_multi_owner_aggregation()
	if _failed:
		quit(1)
		return
	print("PHASE3_H32S0A_PHYSICAL_OWNER_LEDGER_PASS")
	quit(0)


func _test_local_source() -> void:
	var event: Dictionary = Ledger.make_event(
		"local:0", "combustion_heat", Ledger.CLASS_LOCAL_SOURCE, 0,
		-1, -1, "", "", 0.0, 0.1, 4.0, -0.5
	)
	_assert_valid(event, "local source")
	var source: Dictionary = Ledger.physical_source_for_room([event], 0)
	_assert_close(float(source["mass_delta_kg"]), 0.1, "local source mass")
	_assert_close(float(source["energy_delta_kj"]), 3.5, "local source energy")


func _test_exterior_boundary() -> void:
	var inflow: Dictionary = Ledger.make_event(
		"exterior:in", "pressure_inlet", Ledger.CLASS_EXTERIOR_BOUNDARY, 0,
		-1, 0, "", "lower", 0.0, 2.0, 0.0, 1.0
	)
	var outflow: Dictionary = Ledger.make_event(
		"exterior:out", "pressure_outlet", Ledger.CLASS_EXTERIOR_BOUNDARY, 0,
		0, -1, "upper", "", -1.0, 0.0, -8.0, 0.0
	)
	_assert_valid(inflow, "exterior inflow")
	_assert_valid(outflow, "exterior outflow")
	var source: Dictionary = Ledger.physical_source_for_room([inflow, outflow], 0)
	_assert_close(float(source["mass_delta_kg"]), 1.0, "exterior net mass")
	_assert_close(float(source["energy_delta_kj"]), -7.0, "exterior net energy")


func _test_interzone_both_directions() -> void:
	var upper_to_lower: Dictionary = Ledger.make_event(
		"interzone:u2l", "vertical_mix", Ledger.CLASS_INTERZONE_REDISTRIBUTION, 0,
		0, 0, "upper", "lower", -2.0, 2.0, -5.0, 5.0
	)
	var lower_to_upper: Dictionary = Ledger.make_event(
		"interzone:l2u", "plume", Ledger.CLASS_INTERZONE_REDISTRIBUTION, 0,
		0, 0, "lower", "upper", 3.0, -3.0, 1.0, -1.0
	)
	_assert_valid(upper_to_lower, "upper to lower")
	_assert_valid(lower_to_upper, "lower to upper")
	var aggregate: Dictionary = Ledger.aggregate_events([upper_to_lower, lower_to_upper])
	_assert_close(float(aggregate["interzone_mass_residual_kg"]), 0.0, "interzone mass")
	_assert_close(float(aggregate["interzone_energy_residual_kj"]), 0.0, "interzone energy")
	var source: Dictionary = Ledger.physical_source_for_room([upper_to_lower, lower_to_upper], 0)
	_assert_close(float(source["mass_delta_kg"]), 0.0, "interzone excluded from source")


func _test_interior_transport_and_counterflow() -> void:
	var a_to_b: Dictionary = _transport(
		"transport:a2b", 0, 1, "upper", "lower", -2.0, -10.0
	)
	var b_to_a: Dictionary = _transport(
		"transport:b2a", 1, 0, "lower", "upper", -1.0, -2.0
	)
	_assert_valid(a_to_b, "interior upper to lower")
	_assert_valid(b_to_a, "counterflow return")
	var aggregate: Dictionary = Ledger.aggregate_events([a_to_b, b_to_a])
	_assert_close(
		float(aggregate["interior_transport_mass_residual_kg"]), 0.0,
		"counterflow building mass"
	)
	_assert_close(
		float(aggregate["interior_transport_energy_residual_kj"]), 0.0,
		"counterflow building energy"
	)
	_assert_close(
		float(Ledger.physical_source_for_room([a_to_b, b_to_a], 0)["mass_delta_kg"]),
		0.0,
		"interior transport excluded from source"
	)


func _test_parcel_and_numerical_are_not_sources() -> void:
	var created: Dictionary = Ledger.make_event(
		"parcel:p0:created", "delayed_smoke", Ledger.CLASS_DELAYED_PARCEL, 0,
		0, 1, "upper", "upper", -1.0, 0.0, -4.0, 0.0, 1.0, 4.0,
		{"parcel_id": "p0", "lifecycle": "created"}
	)
	var delivered: Dictionary = Ledger.make_event(
		"parcel:p0:delivered", "delayed_smoke", Ledger.CLASS_DELAYED_PARCEL, 1,
		0, 1, "upper", "upper", 1.0, 0.0, 4.0, 0.0, -1.0, -4.0,
		{"parcel_id": "p0", "lifecycle": "delivered"}
	)
	var correction: Dictionary = Ledger.make_event(
		"projection:0", "project_room_state", Ledger.CLASS_NUMERICAL_CORRECTION, 0,
		-1, -1, "", "", 0.25, 0.0, 2.0, 0.0
	)
	_assert_valid(created, "parcel created")
	_assert_valid(delivered, "parcel delivered")
	_assert_valid(correction, "numerical correction")
	var source: Dictionary = Ledger.physical_source_for_room(
		[created, delivered, correction], 0
	)
	_assert_close(float(source["mass_delta_kg"]), 0.0, "parcel/correction source mass")
	_assert_close(float(source["energy_delta_kj"]), 0.0, "parcel/correction source energy")


func _test_invalid_events_fail_closed() -> void:
	var duplicate: Dictionary = Ledger.make_event(
		"duplicate", "owner", Ledger.CLASS_LOCAL_SOURCE, 0
	)
	var duplicate_result: Dictionary = Ledger.aggregate_events([duplicate, duplicate])
	_assert(not bool(duplicate_result["valid"]), "duplicate result invalid")
	_assert(int(duplicate_result["duplicate_event_count"]) == 1, "duplicate counted")
	_assert(int(duplicate_result["valid_event_count"]) == 0, "duplicates never aggregate")

	var unknown: Dictionary = Ledger.make_event("unknown", "owner", "unknown", 0)
	_assert_invalid(unknown, "unknown classification")
	var non_finite: Dictionary = Ledger.make_event(
		"nan", "owner", Ledger.CLASS_LOCAL_SOURCE, 0,
		-1, -1, "", "", NAN
	)
	_assert_invalid(non_finite, "non finite")
	var bad_zone: Dictionary = Ledger.make_event(
		"bad-zone", "vent", Ledger.CLASS_EXTERIOR_BOUNDARY, 0,
		0, -1, "ceiling", "", -1.0
	)
	_assert_invalid(bad_zone, "invalid zone")
	var bad_transport: Dictionary = Ledger.make_event(
		"bad-transport", "doorway", Ledger.CLASS_INTERIOR_TRANSPORT, 0,
		0, 1, "upper", "lower", -2.0, 0.0, -3.0, 0.0, 1.0, 3.0
	)
	_assert_invalid(bad_transport, "nonconservative transport")
	var bad_interzone: Dictionary = Ledger.make_event(
		"bad-interzone", "plume", Ledger.CLASS_INTERZONE_REDISTRIBUTION, 0,
		0, 0, "lower", "upper", 2.0, -1.0
	)
	_assert_invalid(bad_interzone, "nonconservative interzone")
	var bad_direction: Dictionary = Ledger.make_event(
		"bad-direction", "doorway", Ledger.CLASS_INTERIOR_TRANSPORT, 0,
		0, 1, "upper", "lower", 1.0, 0.0, 2.0, 0.0, -1.0, -2.0
	)
	_assert_invalid(bad_direction, "transport sign mismatch")
	var valid_source: Dictionary = Ledger.make_event(
		"valid-alongside-invalid", "fire", Ledger.CLASS_LOCAL_SOURCE, 0,
		-1, -1, "", "", 0.0, 0.0, 1.0, 0.0
	)
	var fail_closed_source: Dictionary = Ledger.physical_source_for_room(
		[valid_source, bad_direction], 0
	)
	_assert_close(
		float(fail_closed_source["energy_delta_kj"]), 0.0,
		"invalid aggregate exposes no partial source"
	)


func _test_determinism_and_input_purity() -> void:
	var events: Array = [
		Ledger.make_event("z", "heat", Ledger.CLASS_LOCAL_SOURCE, 1, -1, -1, "", "", 0.0, 0.0, 2.0),
		Ledger.make_event("a", "heat", Ledger.CLASS_LOCAL_SOURCE, 0, -1, -1, "", "", 0.0, 0.0, 1.0),
	]
	var before: String = JSON.stringify(events)
	var forward: String = JSON.stringify(Ledger.aggregate_events(events))
	var reversed: Array = events.duplicate(true)
	reversed.reverse()
	var backward: String = JSON.stringify(Ledger.aggregate_events(reversed))
	_assert(forward == backward, "aggregation deterministic under input reversal")
	_assert(JSON.stringify(events) == before, "input events are not mutated")


func _test_multi_owner_aggregation() -> void:
	var local: Dictionary = Ledger.make_event(
		"multi:local", "fire", Ledger.CLASS_LOCAL_SOURCE, 0,
		-1, -1, "", "", 0.0, 0.2, 8.0, 0.0
	)
	var exterior: Dictionary = Ledger.make_event(
		"multi:exterior", "vent", Ledger.CLASS_EXTERIOR_BOUNDARY, 0,
		0, -1, "upper", "", -0.1, 0.0, -2.0, 0.0
	)
	var transport: Dictionary = _transport(
		"multi:transport", 0, 1, "upper", "upper", -0.5, -1.0
	)
	var aggregate: Dictionary = Ledger.aggregate_events([transport, exterior, local])
	_assert(bool(aggregate["valid"]), "multi-owner aggregate valid")
	_assert(int(aggregate["valid_event_count"]) == 3, "all owners counted")
	var source: Dictionary = aggregate["physical_source_by_room"]["0"]
	_assert_close(float(source["mass_delta_kg"]), 0.1, "multi-owner source mass")
	_assert_close(float(source["energy_delta_kj"]), 6.0, "multi-owner source energy")


func _transport(
		event_id: String,
		source_room: int,
		destination_room: int,
		source_zone: String,
		destination_zone: String,
		source_mass: float,
		source_energy: float
	) -> Dictionary:
	var upper_mass: float = source_mass if source_zone == "upper" else 0.0
	var lower_mass: float = source_mass if source_zone == "lower" else 0.0
	var upper_energy: float = source_energy if source_zone == "upper" else 0.0
	var lower_energy: float = source_energy if source_zone == "lower" else 0.0
	return Ledger.make_event(
		event_id, "doorway", Ledger.CLASS_INTERIOR_TRANSPORT, source_room,
		source_room, destination_room, source_zone, destination_zone,
		upper_mass, lower_mass, upper_energy, lower_energy,
		-source_mass, -source_energy
	)


func _assert_valid(event: Dictionary, label: String) -> void:
	var result: Dictionary = Ledger.validate_event(event)
	_assert(bool(result.get("valid", false)), "%s: %s" % [label, result.get("reason", "")])


func _assert_invalid(event: Dictionary, label: String) -> void:
	_assert(not bool(Ledger.validate_event(event).get("valid", true)), label)


func _assert_close(actual: float, expected: float, label: String) -> void:
	_assert(absf(actual - expected) <= Ledger.CONSERVATION_EPSILON, label)


func _assert(condition: bool, label: String) -> void:
	if condition:
		return
	_failed = true
	push_error("PHASE3_H32S0A ASSERTION FAILED: %s" % label)

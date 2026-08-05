extends SceneTree

## H3.2-S0d2 fixture: experimental suppression lower-energy sink.
##
## OFF must reproduce the legacy write exactly. ON must remove energy from the
## zone the projection actually reads, survive the sync, never go negative and
## never record a requested value as accepted.

const Phase3PhysicalOwnerLedgerScript = preload("res://sim/core/Phase3PhysicalOwnerLedger.gd")
const RoomModelScript = preload("res://sim/building/RoomModel.gd")
const SimulationEngineScript = preload("res://sim/core/SimulationEngine.gd")
const SmokeModelScript = preload("res://sim/smoke/SmokeModel.gd")
const ZoneFireSolverScript = preload("res://sim/core/ZoneFireSolver.gd")

var _failed: bool = false


func _init() -> void:
	_test_flag_defaults_false()
	_test_off_reproduces_legacy_write()
	_test_on_two_zone_removes_lower_energy()
	_test_on_temperature_falls_after_sync()
	_test_accepted_is_bounded_by_availability()
	_test_empty_lower_layer_is_fail_safe()
	_test_upper_owner_is_not_duplicated()
	_test_legacy_regime_is_invariant()
	_test_deterministic_ids()
	if _failed:
		quit(1)
		return
	print("PHASE3_H32S0D2_SUPPRESSION_LOWER_SINK_PASS")
	quit(0)


func _test_flag_defaults_false() -> void:
	var engine = SimulationEngineScript.new()
	_expect(
		not engine.phase3_suppression_lower_energy_sink_enabled,
		"experimental flag defaults false"
	)
	engine.free()


func _test_off_reproduces_legacy_write() -> void:
	var off = _engine(false, true)
	var on_room = _room()
	var off_room = _room()
	# OFF: legacy writes a temperature that the projection then rebuilds.
	off._apply_suppression_to_room(off_room, 2.0, 1.0)
	# The reference is the pre-S0d2 behaviour: no lower_energy_kj mutation from
	# suppression, so the projection restores the temperature it derives.
	var reference = _engine(false, true)
	reference._apply_suppression_to_room(on_room, 2.0, 1.0)
	_expect(off_room.lower_energy_kj == on_room.lower_energy_kj, "OFF lower energy identical")
	_expect(off_room.temp_lower_c == on_room.temp_lower_c, "OFF lower temperature identical")
	_expect(off_room.upper_energy_kj == on_room.upper_energy_kj, "OFF upper energy identical")
	_expect(
		off.get_phase3_physical_owner_engine_events().size()
			== reference.get_phase3_physical_owner_engine_events().size(),
		"OFF emits no extra owner"
	)
	for raw_event in off.get_phase3_physical_owner_engine_events():
		_expect(
			String(raw_event["owner"]) != "suppression_lower_energy_sink",
			"OFF never emits the lower sink"
		)
	off.free()
	reference.free()


func _test_on_two_zone_removes_lower_energy() -> void:
	var engine = _engine(true, true)
	var room = _room()
	var lower_before_kj: float = room.lower_energy_kj
	engine._apply_suppression_to_room(room, 2.0, 1.0)
	_expect(room.lower_energy_kj < lower_before_kj, "ON reduces lower energy")
	_expect(room.lower_energy_kj >= 0.0, "lower energy never negative")
	_expect(is_finite(room.lower_energy_kj), "lower energy is finite")
	var events: Array = _lower_events(engine)
	_expect(events.size() == 1, "one lower sink event")
	if events.size() == 1:
		var event: Dictionary = events[0]
		_expect(String(event["classification"]) == "local_source", "signed local sink")
		_expect(float(event["lower_energy_delta_kj"]) < 0.0, "sink is negative")
		_expect(float(event["upper_energy_delta_kj"]) == 0.0, "sink stays in the lower zone")
		var metadata: Dictionary = event["metadata"]
		var accepted: float = float(metadata["accepted_lower_cooling_kj"])
		var requested: float = float(metadata["requested_lower_cooling_kj"])
		var rejected: float = float(metadata["rejected_lower_cooling_kj"])
		_expect(accepted <= requested + 1.0e-12, "accepted never exceeds requested")
		_expect(
			absf(requested - accepted - rejected) <= 1.0e-9,
			"requested equals accepted plus rejected"
		)
		# The owner must carry the accepted mutation, not the request.
		_expect(
			absf(float(event["lower_energy_delta_kj"]) + accepted) <= 1.0e-9,
			"owner records the accepted mutation"
		)
	_expect(
		bool(Phase3PhysicalOwnerLedgerScript.aggregate_events(
			engine.get_phase3_physical_owner_engine_events()
		)["valid"]),
		"aggregate valid"
	)
	engine.free()


func _test_on_temperature_falls_after_sync() -> void:
	var off = _engine(false, true)
	var on = _engine(true, true)
	var off_room = _room()
	var on_room = _room()
	var temp_before_c: float = on_room.temp_lower_c
	off._apply_suppression_to_room(off_room, 2.0, 1.0)
	on._apply_suppression_to_room(on_room, 2.0, 1.0)
	# S0d1 finding: with OFF the projection restores the pre-suppression value.
	_expect(
		absf(off_room.temp_lower_c - temp_before_c) <= 1.0e-9,
		"OFF lower temperature is restored by the projection"
	)
	# S0d2: the removal survives the sync because it is applied to the energy.
	_expect(
		on_room.temp_lower_c < temp_before_c - 1.0e-9,
		"ON lower temperature falls after the sync"
	)
	off.free()
	on.free()


func _test_accepted_is_bounded_by_availability() -> void:
	var engine = _engine(true, true)
	var room = _room()
	# Tiny lower reservoir: the request must be clipped to what exists.
	room.lower_gas_kg = 0.05
	room.lower_energy_kj = 3.0
	engine._apply_suppression_to_room(room, 40.0, 1.0)
	_expect(room.lower_energy_kj >= 0.0, "clipped sink stays non-negative")
	var events: Array = _lower_events(engine)
	_expect(events.size() == 1, "one clipped lower sink event")
	if events.size() == 1:
		var metadata: Dictionary = events[0]["metadata"]
		var accepted: float = float(metadata["accepted_lower_cooling_kj"])
		var available: float = float(metadata["available_lower_energy_kj"])
		_expect(accepted <= available + 1.0e-12, "accepted never exceeds availability")
		_expect(
			float(metadata["rejected_lower_cooling_kj"]) > 0.0,
			"the rejected remainder is visible"
		)
	engine.free()


func _test_empty_lower_layer_is_fail_safe() -> void:
	var engine = _engine(true, true)
	var room = _room()
	room.lower_gas_kg = 0.0
	room.lower_energy_kj = 0.0
	room.temp_lower_c = 20.0
	engine._apply_suppression_to_room(room, 5.0, 1.0)
	_expect(is_finite(room.lower_energy_kj), "no NaN with an empty lower layer")
	_expect(room.lower_energy_kj >= 0.0, "no negative energy with an empty lower layer")
	_expect(is_finite(room.temp_lower_c), "no NaN temperature with an empty lower layer")
	engine.free()


func _test_upper_owner_is_not_duplicated() -> void:
	var engine = _engine(true, true)
	var room = _room()
	engine._apply_suppression_to_room(room, 2.0, 1.0)
	var upper_count: int = 0
	var projection_count: int = 0
	for raw_event in engine.get_phase3_physical_owner_engine_events():
		var owner: String = String(raw_event["owner"])
		if owner == "suppression_upper_energy_sink":
			upper_count += 1
		if owner.contains("project") or owner.contains("sync"):
			projection_count += 1
	_expect(upper_count == 1, "upper sink still emitted exactly once")
	_expect(projection_count == 0, "projection is never counted as suppression")
	engine.free()


func _test_legacy_regime_is_invariant() -> void:
	var off = _engine(false, false)
	var on = _engine(true, false)
	var off_room = _room()
	var on_room = _room()
	off._apply_suppression_to_room(off_room, 2.0, 1.0)
	on._apply_suppression_to_room(on_room, 2.0, 1.0)
	_expect(off_room.temp_lower_c == on_room.temp_lower_c, "legacy temperature invariant")
	_expect(off_room.lower_energy_kj == on_room.lower_energy_kj, "legacy energy invariant")
	_expect(off_room.upper_energy_kj == on_room.upper_energy_kj, "legacy upper invariant")
	_expect(_lower_events(on).is_empty(), "legacy regime emits no lower sink")
	off.free()
	on.free()


func _test_deterministic_ids() -> void:
	var engine = _engine(true, true)
	var room = _room()
	room.id = 5
	engine._apply_suppression_to_room(room, 2.0, 1.0)
	var events: Array = engine.get_phase3_physical_owner_engine_events()
	_expect(events.size() == 2, "upper and lower owners")
	if events.size() == 2:
		_expect(
			String(events[0]["event_id"]) == "engine:000000:suppression_upper_energy_sink:r5",
			"upper id"
		)
		_expect(
			String(events[1]["event_id"]) == "engine:000001:suppression_lower_energy_sink:r5",
			"lower id"
		)
	engine.free()


func _lower_events(engine) -> Array:
	var matches: Array = []
	for raw_event in engine.get_phase3_physical_owner_engine_events():
		if String(raw_event["owner"]) == "suppression_lower_energy_sink":
			matches.append(raw_event)
	return matches


func _engine(lower_sink_enabled: bool, two_zone: bool):
	var engine = SimulationEngineScript.new()
	engine.phase3_physical_owner_ledger_enabled = true
	engine.phase3_suppression_lower_energy_sink_enabled = lower_sink_enabled
	engine.two_zone_solver_enabled = two_zone
	engine.zone_fire_solver.two_zone_energy_enabled = two_zone
	engine.thermal_system.set_zone_fire_solver(engine.zone_fire_solver)
	engine.thermal_system._smoke_model = SmokeModelScript.new()
	engine.thermal_system.two_zone_solver_enabled = two_zone
	engine._phase3_physical_owner_begin_step()
	return engine


func _room():
	var room = RoomModelScript.new()
	room.id = 0
	room.width_m = 5.0
	room.length_m = 4.0
	room.height_m = 2.5
	room.thermal_layer_m = 1.2
	room.temp_upper_c = 250.0
	room.temp_lower_c = 90.0
	room.upper_gas_kg = 5.0
	room.lower_gas_kg = 45.0
	room.upper_energy_kj = 4000.0
	room.lower_energy_kj = 3150.0
	room.o2 = 0.209
	return room


func _expect(condition: bool, label: String) -> void:
	if condition:
		return
	_failed = true
	push_error("H3.2-S0d2 ASSERTION FAILED: %s" % label)

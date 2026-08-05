extends SceneTree

## H3.2-S0d1 fixture: suppression owner plus the two donor-less mass seeds.
##
## Every positive case drives the real legacy mutation site. The suppression
## sink must appear as an accepted physical owner; the two seeds must appear as
## honest numerical corrections that never reach the source vector.

const BuildingModelScript = preload("res://sim/BuildingModel.gd")
const OpeningModelScript = preload("res://sim/building/OpeningModel.gd")
const Phase3PhysicalOwnerLedgerScript = preload("res://sim/core/Phase3PhysicalOwnerLedger.gd")
const RoomModelScript = preload("res://sim/building/RoomModel.gd")
const SimulationEngineScript = preload("res://sim/core/SimulationEngine.gd")
const SmokeModelScript = preload("res://sim/smoke/SmokeModel.gd")
const ThermalSystemScript = preload("res://sim/core/ThermalSystem.gd")
const ZoneFireSolverScript = preload("res://sim/core/ZoneFireSolver.gd")

const EPS: float = 1.0e-12

var _failed: bool = false


func _init() -> void:
	_test_suppression_default_off()
	_test_suppression_upper_sink_is_accepted()
	_test_suppression_lower_cooling_has_no_accepted_energy()
	_test_opening_radiation_seed_is_numerical()
	_test_counterflow_seed_is_numerical()
	_test_numerical_corrections_never_feed_sources()
	_test_engine_ids_and_pure_export()
	if _failed:
		quit(1)
		return
	print("PHASE3_H32S0D1_SUPPRESSION_AND_SEEDS_PASS")
	quit(0)


func _test_suppression_default_off() -> void:
	var engine = _engine(false)
	var room = _room(0)
	engine._apply_suppression_to_room(room, 10.0, 1.0)
	_expect(
		engine.get_phase3_physical_owner_engine_events().is_empty(),
		"suppression default OFF emits nothing"
	)
	engine.free()


func _test_suppression_upper_sink_is_accepted() -> void:
	var engine = _engine(true)
	var room = _room(0)
	room.upper_energy_kj = 4000.0
	var upper_before_kj: float = room.upper_energy_kj
	engine._apply_suppression_to_room(room, 2.0, 1.0)
	var events: Array = engine.get_phase3_physical_owner_engine_events()
	_expect(events.size() == 1, "one suppression event")
	if events.size() == 1:
		var event: Dictionary = events[0]
		_expect(
			String(event["owner"]) == "suppression_upper_energy_sink",
			"suppression owner name"
		)
		_expect(String(event["classification"]) == "local_source", "signed local sink")
		_expect(float(event["upper_energy_delta_kj"]) < 0.0, "sink is negative")
		_expect(float(event["upper_mass_delta_kg"]) == 0.0, "sink moves no mass")
		_expect(String(event["source_zone"]).is_empty(), "local source has no zones")
		_expect(int(event["source_room_id"]) == -1, "local source has no transport rooms")
		# 2 L x 950 kJ/L x 0.68 = 1292 kJ, fully available from 4000 kJ.
		_expect(
			absf(float(event["upper_energy_delta_kj"]) + 1292.0) <= 1.0e-9,
			"accepted magnitude equals the mutation"
		)
		_expect(
			float(event["metadata"]["steam_storage_kg"]) > 0.0,
			"steam counterpart is visible"
		)
		_expect(
			String(event["event_id"]).begins_with("engine:000000:"),
			"engine id namespace"
		)
		var upper_after_write_kj: float = upper_before_kj + float(event["upper_energy_delta_kj"])
		_expect(upper_after_write_kj >= 0.0, "sink never overdraws the layer")
	_expect(
		bool(Phase3PhysicalOwnerLedgerScript.aggregate_events(events)["valid"]),
		"suppression aggregate valid"
	)
	engine.free()


func _test_suppression_lower_cooling_has_no_accepted_energy() -> void:
	## S0d1 finding: the lower-zone cooling is written as a temperature and the
	## projection re-derives temp_lower_c from lower_energy_kj, so under the
	## default two-zone configuration it never reaches the state. There is no
	## accepted lower energy sink to own, and inventing one is forbidden.
	var thermal = ThermalSystemScript.new()
	var solver = ZoneFireSolverScript.new()
	solver.two_zone_energy_enabled = true
	thermal.set_zone_fire_solver(solver)
	thermal._smoke_model = SmokeModelScript.new()
	thermal.two_zone_solver_enabled = true

	var room = _room(0)
	room.lower_gas_kg = 50.0
	room.lower_energy_kj = 3000.0
	room.temp_lower_c = 80.0
	var temp_before_c: float = room.temp_lower_c
	room.temp_lower_c = maxf(20.0, room.temp_lower_c - 20.0)
	thermal.sync_room_upper_layer(room, 1.0, "suppression_sync")
	_expect(
		absf(room.temp_lower_c - temp_before_c) <= 1.0e-9,
		"projection discards the suppression lower temperature write"
	)


func _test_opening_radiation_seed_is_numerical() -> void:
	var thermal = _thermal(true)
	var building = _radiation_building()
	thermal.set_references(building, SmokeModelScript.new())
	thermal._step_radiation_openings(building, 1.0, 20.0)
	var events: Array = _seed_events(thermal, "thermal_opening_radiation_target_mass_seed")
	_expect(events.size() >= 1, "opening radiation seed emitted")
	if events.size() >= 1:
		var event: Dictionary = events[0]
		_expect(
			String(event["classification"]) == "numerical_correction",
			"seed is a numerical correction"
		)
		_expect(float(event["upper_mass_delta_kg"]) > 0.0, "seed creates upper mass")
		_expect(String(event["metadata"]["donor"]) == "none", "seed declares no donor")
		_expect(int(event["source_room_id"]) == -1, "seed has no transport identity")
	building.free()


func _test_counterflow_seed_is_numerical() -> void:
	var thermal = _thermal(true)
	thermal.doorway_thermal_counterflow_enabled = true
	var building = _radiation_building()
	thermal.set_references(building, SmokeModelScript.new())
	var hot: RoomModel = building.get_room(0)
	var cold: RoomModel = building.get_room(1)
	cold.upper_gas_kg = 0.0
	var op = building.get_openings()[0]
	thermal._apply_doorway_thermal_counterflow(hot, cold, op, {"hot_band_m": 0.0}, 1.0, 20.0)
	var events: Array = _seed_events(thermal, "thermal_counterflow_minimum_upper_mass")
	_expect(events.size() == 1, "counterflow seed emitted once")
	if events.size() == 1:
		var event: Dictionary = events[0]
		_expect(
			String(event["classification"]) == "numerical_correction",
			"counterflow seed is a numerical correction"
		)
		_expect(
			absf(float(event["upper_mass_delta_kg"]) - 0.005) <= 1.0e-12,
			"counterflow seed magnitude equals the mutation"
		)
		_expect(String(event["metadata"]["donor"]) == "none", "seed declares no donor")
	building.free()


func _test_numerical_corrections_never_feed_sources() -> void:
	var room = _room(4)
	var correction: Dictionary = Phase3PhysicalOwnerLedgerScript.make_event(
		"engine:000000:probe_seed:r4", "probe_seed", "numerical_correction",
		room.id, -1, -1, "", "", 3.0, 0.0, 40.0, 0.0, 0.0, 0.0, {}
	)
	var sink: Dictionary = Phase3PhysicalOwnerLedgerScript.make_event(
		"engine:000001:probe_sink:r4", "probe_sink", "local_source",
		room.id, -1, -1, "", "", 0.0, 0.0, -10.0, 0.0, 0.0, 0.0, {}
	)
	var source: Dictionary = Phase3PhysicalOwnerLedgerScript.physical_source_for_room(
		[correction, sink], room.id
	)
	_expect(
		absf(float(source["upper_energy_delta_kj"]) + 10.0) <= EPS,
		"only the local sink reaches the source vector"
	)
	_expect(
		float(source["upper_mass_delta_kg"]) == 0.0,
		"seed mass is excluded from the source vector"
	)
	var duplicated: Array = [correction, sink, sink.duplicate(true)]
	var aggregate: Dictionary = Phase3PhysicalOwnerLedgerScript.aggregate_events(duplicated)
	_expect(not bool(aggregate["valid"]), "duplicate id fails closed")
	var blocked: Dictionary = Phase3PhysicalOwnerLedgerScript.physical_source_for_room(
		duplicated, room.id
	)
	_expect(
		float(blocked["upper_energy_delta_kj"]) == 0.0,
		"invalid aggregate exposes no partial source"
	)


func _test_engine_ids_and_pure_export() -> void:
	var engine = _engine(true)
	var room = _room(7)
	room.upper_energy_kj = 9000.0
	engine._apply_suppression_to_room(room, 1.0, 1.0)
	engine._apply_suppression_to_room(room, 1.0, 1.0)
	var events: Array = engine.get_phase3_physical_owner_engine_events()
	_expect(events.size() == 2, "two suppression events")
	if events.size() == 2:
		_expect(
			String(events[0]["event_id"]) == "engine:000000:suppression_upper_energy_sink:r7",
			"first deterministic id"
		)
		_expect(
			String(events[1]["event_id"]) == "engine:000001:suppression_upper_energy_sink:r7",
			"second deterministic id"
		)
	var before: String = JSON.stringify(engine.get_phase3_physical_owner_engine_events())
	var _drop: Array = engine.get_phase3_physical_owner_engine_events()
	_drop.clear()
	_expect(
		JSON.stringify(engine.get_phase3_physical_owner_engine_events()) == before,
		"export is pure"
	)
	engine._phase3_physical_owner_begin_step()
	_expect(
		engine.get_phase3_physical_owner_engine_events().is_empty(),
		"step reset clears engine events"
	)
	engine.free()


func _seed_events(thermal, owner: String) -> Array:
	var matches: Array = []
	for raw_event in thermal.get_phase3_physical_owner_events():
		var event: Dictionary = raw_event
		if String(event.get("owner", "")) == owner:
			matches.append(event)
	return matches


func _engine(enabled: bool):
	var engine = SimulationEngineScript.new()
	engine.phase3_physical_owner_ledger_enabled = enabled
	var solver = ZoneFireSolverScript.new()
	solver.two_zone_energy_enabled = true
	engine.thermal_system.set_zone_fire_solver(solver)
	engine.thermal_system._smoke_model = SmokeModelScript.new()
	engine.thermal_system.two_zone_solver_enabled = true
	engine._phase3_physical_owner_begin_step()
	return engine


func _thermal(enabled: bool):
	var thermal = ThermalSystemScript.new()
	var solver = ZoneFireSolverScript.new()
	solver.two_zone_energy_enabled = true
	thermal.set_zone_fire_solver(solver)
	thermal._smoke_model = SmokeModelScript.new()
	thermal.two_zone_solver_enabled = true
	thermal.phase3_physical_owner_ledger_enabled = enabled
	return thermal


func _radiation_building():
	var building = BuildingModelScript.new()
	building.outside_temp_c = 20.0
	var hot = _room(0)
	hot.temp_upper_c = 700.0
	hot.upper_gas_kg = 8.0
	hot.upper_energy_kj = 5400.0
	var cold = _room(1)
	cold.temp_upper_c = 25.0
	cold.temp_lower_c = 22.0
	cold.upper_gas_kg = 0.0
	cold.upper_energy_kj = 0.0
	building.rooms = {0: hot, 1: cold}
	var opening = OpeningModelScript.new(
		0, 1, OpeningModelScript.Type.DOOR, 1.0, 2.0, 1.0, 0.0
	)
	opening.opening_index = 3
	opening.open_fraction_smooth = 1.0
	building.openings = [opening]
	return building


func _room(room_id: int):
	var room = RoomModelScript.new()
	room.id = room_id
	room.width_m = 5.0
	room.length_m = 4.0
	room.height_m = 2.5
	room.thermal_layer_m = 1.2
	room.temp_upper_c = 250.0
	room.temp_lower_c = 30.0
	room.upper_gas_kg = 5.0
	room.lower_gas_kg = 50.0
	room.upper_energy_kj = 4000.0
	room.lower_energy_kj = 500.0
	room.o2 = 0.209
	return room


func _expect(condition: bool, label: String) -> void:
	if condition:
		return
	_failed = true
	push_error("H3.2-S0d1 ASSERTION FAILED: %s" % label)

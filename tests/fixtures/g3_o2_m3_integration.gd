extends SceneTree

## Technical integration only. Synthetic O2 obligations are injected, not
## claimed to occur in the live transport. No material, CO or FED validation.
const Building = preload("res://sim/BuildingModel.gd")
const SimulationEngineScript = preload("res://sim/core/SimulationEngine.gd")
const K: float = 0.076
var checks: int = 0
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)


func _near(a: float, b: float, label: String) -> void:
	_check(is_finite(a) and is_finite(b) and absf(a - b) <= 1.0e-9, label)


func _world(overrides: Dictionary = {}, objects: Array = []) -> Dictionary:
	var building = Building.new()
	root.add_child(building)
	var room_data: Array = []
	var rects: Dictionary = {}
	for id: int in [0, 1]:
		room_data.append({"id": id, "name": "Sala%d" % id, "kind": "salon",
			"height_m": 2.4, "floor_level_z_m": 0.0,
			"fuel_energy_MJ": 1100.0 if id == 0 else 0.0,
			"max_hrr_kw": 700.0 if id == 0 else 0.0,
			"fuel_objects": objects.duplicate(true) if id == 0 else []})
		rects[str(id)] = {"x": float(id) * 5.0, "y": 0.0, "w": 5.0, "h": 4.0}
	building.load_template_data({"building_type": "house",
		"floors": [{"level_m": 0.0, "name": "PB"}], "rooms_data": room_data,
		"room_rect_m": rects, "openings_data": [], "ignition_room_id": 0,
		"hvac_mode": "none"})
	var engine = SimulationEngineScript.new()
	engine.building = building
	engine.auto_ignite_on_ready = false
	engine.auto_finish_on_extinction = false
	engine.enable_logging = false
	engine.enable_csv_log = false
	engine.sim_fixed_dt = 0.25
	engine.o2_room_inventory_enabled = true
	for key: String in overrides:
		engine.set(key, overrides[key])
	engine.suppress_exit_graphs()
	root.add_child(engine)
	engine.reset_simulation(0, true)
	engine.oxygen_exchange_system.ach_infiltration = 0.0
	return {"engine": engine, "building": building, "room": building.get_room(0),
		"other": building.get_room(1), "owner": engine.get("_o2_room_inventory")}


func _prepare(world: Dictionary) -> void:
	world.room.fire_time_s = 120.0
	world.room.hrr_kw = 400.0
	world.room.o2_hrr_factor = 0.8
	world.room.temp_upper_c = 250.0
	world.room.retained_unburned_MJ = 1.0
	for obj in world.room.fuel_objects:
		obj.hcl_yield_kg_per_MJ = 0.001
		obj.acrolein_yield_kg_per_MJ = 0.001
		obj.formaldehyde_yield_kg_per_MJ = 0.001


func _fire(world: Dictionary, dt: float = 1.0) -> bool:
	world.owner.begin_step(world.engine._o2_room_inventory_environment())
	return world.engine.combustion_system.step_room_fire(
		world.room, dt, world.engine._build_room_combustion_context(0))


func _dispose(world: Dictionary) -> void:
	world.engine.free()
	world.building.free()


func _limited_step(explicit_object: bool = false) -> void:
	var objects: Array = []
	if explicit_object:
		objects.append({"id": "m3_sofa", "name": "M3 synthetic sofa", "kind": "mobiliario_tapizado",
			"room_id": 0, "position_m": {"x": 0.2, "y": 1.4}, "size_m": {"x": 2.2, "y": 0.9},
			"fuel_energy_MJ": 1100.0, "remaining_fuel_MJ": 1100.0, "max_hrr_kw": 700.0,
			"ignition_temp_c": 310.0, "is_primary_ignition_source": true})
	var whole: Dictionary = _world({}, objects)
	var limited: Dictionary = _world({}, objects)
	_prepare(whole)
	_prepare(limited)
	var initial_o2: float = limited.room.o2_inventory_kg
	var injected: Dictionary = limited.owner.exchange_between_rooms(
		limited.other, limited.room, 0.0, initial_o2 - 0.02, 999.0, "synthetic_M3_obligation")
	_check(bool(injected["applied"]), "synthetic obligation injected")
	_check(_fire(whole) and _fire(limited), "both real fire phases complete")
	var report: Dictionary = limited.engine.get_o2_room_inventory_report()
	var selected: Dictionary = report.get("selections", {}).get(0, {})
	var f: float = float(selected.get("accepted_fraction", -1.0))
	_check(f > 0.0 and f < 1.0, "availability limits POST-filter power")
	_near(limited.room.hrr_kw, whole.room.hrr_kw * f, "accepted power uses one fraction")
	_near(limited.room.hrr_kj_total, whole.room.hrr_kj_total * f, "heat accumulator uses one fraction")
	_near(limited.room.fuel_consumed_MJ_step, whole.room.fuel_consumed_MJ_step * f, "fuel uses one fraction")
	_near(1100.0 - limited.room.fire.remaining_fuel_MJ,
		(1100.0 - whole.room.fire.remaining_fuel_MJ) * f, "fuel inventory debited by accepted amount")
	_near(limited.room.retained_unburned_MJ - 1.0,
		(whole.room.retained_unburned_MJ - 1.0) * f, "pool change uses one fraction")
	for field: String in ["smoke_prod_kg_s", "co_kg", "co_upper_kg", "co2_kg", "co2_upper_kg",
			"hcn_kg", "hcn_upper_kg", "hcl_kg", "acrolein_kg", "formaldehyde_kg",
			"c_burned_total_kg", "c_untracked_products_kg", "c_preclamp_excess_kg", "c_postclamp_excess_kg"]:
		_near(float(limited.room.get(field)), float(whole.room.get(field)) * f, "common fraction " + field)
	_near(limited.room.o2_inventory_kg, initial_o2, "fire reserves but does not debit O2")
	if explicit_object:
		_near(limited.room.fuel_objects[0].hrr_kw, whole.room.fuel_objects[0].hrr_kw * f,
			"explicit object power uses accepted fraction")
		_near(1100.0 - limited.room.fuel_objects[0].remaining_fuel_MJ,
			(1100.0 - whole.room.fuel_objects[0].remaining_fuel_MJ) * f,
			"explicit object fuel uses accepted fraction")
	limited.engine._step_oxygen(1.0)
	limited.owner.audit_combustion_reservations()
	_check(limited.owner.state() == "armed", "real sink settles reservation")
	_near(limited.room.o2_consumed_fire_kg_step, limited.room.hrr_kw * K / 1000.0,
		"sink debit equals accepted heat")
	_near(limited.room.o2_consumed_fire_kg_step, 0.02, "sink does not reapply five percent cap")
	_near(float(limited.owner.report()["selections"][0]["debited_kg"]), 0.02, "canonical exact debit")
	_dispose(whole)
	_dispose(limited)


func _refusal_is_atomic() -> void:
	var world: Dictionary = _world()
	_prepare(world)
	world.owner.begin_step(world.engine._o2_room_inventory_environment())
	world.owner.reserve_combustion(world.room, world.owner.selection_for(world.room, "fixture"), 0.1, K)
	var initial_fuel: float = world.room.fire.remaining_fuel_MJ
	var initial_o2: float = world.room.o2_inventory_kg
	var active: bool = world.engine.combustion_system.step_room_fire(
		world.room, 1.0, world.engine._build_room_combustion_context(0))
	_check(not active and world.owner.state() == "rejected", "duplicate reservation rejects real fire")
	_near(world.room.hrr_kw, 400.0, "refusal preserves previous power")
	_near(world.room.retained_unburned_MJ, 1.0, "refusal writes no pool")
	_near(world.room.fire.remaining_fuel_MJ, initial_fuel, "refusal writes no fuel")
	_near(world.room.o2_inventory_kg, initial_o2, "refusal writes no O2")
	_near(world.room.hrr_kj_total, 0.0, "refusal writes no heat")
	for field: String in ["co_kg", "co2_kg", "hcn_kg", "hcl_kg", "acrolein_kg", "formaldehyde_kg"]:
		_near(float(world.room.get(field)), 0.0, "refusal writes no " + field)
	_dispose(world)


func _flashover_and_reset() -> void:
	var world: Dictionary = _world()
	_prepare(world)
	world.engine.flashover_min_time_s = 0.0
	world.engine.flashover_temp_c = 0.0
	world.engine.flashover_layer_m = 3.0
	world.engine.flashover_breathing_temp_c = 0.0
	world.engine.flashover_require_tenability_loss = false
	world.room.fire.flashover_min_hrr_kw = 0.0
	_check(_fire(world), "fire phase before flashover")
	var accepted_power: float = world.room.hrr_kw
	world.engine._try_trigger_flashover(world.room)
	_check(world.room.flashover_triggered, "flashover criterion reached")
	_near(world.room.hrr_kw, accepted_power, "flashover cannot mutate accepted power")
	var pending: Dictionary = world.owner.report()["next_flashover_power_kw"]
	_check(float(pending.get(0, 0.0)) > accepted_power, "flashover is a next-step proposal")
	_near(world.owner.take_flashover_proposal_kw(world.room), 0.0, "same-tick flashover proposal cannot be spent")
	_check(world.owner.report()["next_flashover_power_kw"] == pending, "early read preserves deferred proposal")
	world.engine._step_oxygen(1.0)
	_check(world.owner.state() == "armed", "flashover tick still settles original heat")
	_near(world.room.o2_consumed_fire_kg_step, accepted_power * K / 1000.0, "flashover exact original debit")
	_check(_fire(world), "next-step proposal enters fire")
	_check(world.owner.report()["next_flashover_power_kw"].is_empty(), "next-step proposal consumed once")
	_check(bool(world.owner.schedule_flashover_proposal(world.room, 200.0)["applied"]),
		"reset control has a new pending proposal")
	world.engine.reset_simulation(0, true)
	_check(world.engine.get_o2_room_inventory_report()["next_flashover_power_kw"].is_empty(),
		"reset removes pending flashover")
	_dispose(world)


func _whole_engine() -> void:
	var world: Dictionary = _world()
	_prepare(world)
	for index: int in range(120):
		var heat_before: float = world.room.hrr_kj_total
		var consumed_before: float = world.room.o2_consumed_fire_kg_total
		world.engine.step(0.25)
		_check(world.engine.o2_room_inventory_failure.is_empty(), "whole engine accepts tick %d" % index)
		_near(world.room.o2_consumed_fire_kg_total - consumed_before,
			(world.room.hrr_kj_total - heat_before) * K / 1000.0, "whole engine heat/O2 tick %d" % index)
		_check(world.room.o2_inventory_kg >= 0.0, "whole engine nonnegative tick %d" % index)
	_dispose(world)


func _unsupported_combinations() -> void:
	for key: String in ["fire_o2_independent", "fire_explicit_object_fuel_ownership_enabled", "co_oxidation_enabled"]:
		var world: Dictionary = _world({key: true})
		_check(not world.engine.o2_room_inventory_failure.is_empty(), "arming rejects " + key)
		world.engine.step(0.25)
		_near(world.engine.sim_time_s, 0.0, "unsupported run cannot advance " + key)
		_dispose(world)


func _final_tick() -> void:
	var world: Dictionary = _world()
	world.room.fire_time_s = 10.0
	world.room.fire.remaining_fuel_MJ = 0.000001
	# Keep the synthetic fuel fraction at one, rather than asking a vanishing
	# 1e-9 curve fraction to consume the whole remnant in a single tick.
	world.room.fire.fuel_energy_MJ = 0.000001
	world.room.hrr_kw = 10.0
	var final_fire = world.room.fire
	_check(_fire(world), "last accepted fuel tick not erased")
	_check(world.room.hrr_kw > 0.0, "last fuel tick retains accepted power")
	world.engine._step_oxygen(1.0)
	_near(world.room.o2_consumed_fire_kg_step, world.room.hrr_kw * K / 1000.0, "last fuel tick exact debit")
	var heat_after: float = world.room.hrr_kj_total
	# Keep the original resource when the old late-retirement mutant clears
	# room.fire; its removal must fail assertions, not crash this fixture.
	_near(final_fire.remaining_fuel_MJ, 0.0, "final synthetic proposal exhausts solid fuel")
	_check(not _fire(world), "burned-out fire retires on next tick")
	_near(world.room.hrr_kw, 0.0, "retired fire proposes no heat")
	_near(world.room.hrr_kj_total, heat_after, "retirement cannot erase or duplicate accepted heat")
	world.engine._step_oxygen(1.0)
	world.owner.audit_combustion_reservations()
	_check(world.owner.state() == "armed", "idle sink needs no invented reservation")
	_dispose(world)


func _no_sink_cap() -> void:
	var world: Dictionary = _world()
	_prepare(world)
	# Synthetic filter memory, not a physically validated fire: enough requested
	# heat to need all the inventory, so a restored five-percent cap is visible.
	world.room.hrr_kw = 1000000.0
	var before: float = world.room.o2_inventory_kg
	_check(_fire(world), "synthetic high-memory proposal accepted")
	var selected: Dictionary = world.owner.report()["selections"][0]
	_check(float(selected["accepted_fraction"]) < 1.0, "high-memory filter output is limited")
	_near(world.room.hrr_kw * K / 1000.0, before, "full inventory backs accepted heat")
	world.engine._step_oxygen(1.0)
	_near(world.room.o2_consumed_fire_kg_step, before, "live sink has no five percent cap")
	_near(world.room.o2_inventory_kg, 0.0, "live sink exhausts inventory without clamp")
	_check(world.owner.state() == "armed", "full-inventory debit remains valid")
	_dispose(world)


func _zero_availability() -> void:
	var world: Dictionary = _world()
	_prepare(world)
	var before: float = world.room.o2_inventory_kg
	world.owner.exchange_between_rooms(world.other, world.room, 0.0, before, 999.0,
		"synthetic_zero_availability")
	_check(_fire(world), "zero-availability proposal is a valid zero acceptance")
	_near(world.room.hrr_kw, 0.0, "zero acceptance releases no power")
	_near(world.room.fire.remaining_fuel_MJ, 1100.0, "zero acceptance consumes no fuel")
	_near(world.room.retained_unburned_MJ, 1.0, "zero acceptance writes no pool")
	_near(world.room.smoke_prod_kg_s, 0.0, "zero acceptance generates no smoke")
	for field: String in ["co_kg", "co2_kg", "hcn_kg", "hcl_kg", "acrolein_kg", "formaldehyde_kg"]:
		_near(float(world.room.get(field)), 0.0, "zero acceptance generates no " + field)
	world.engine._step_oxygen(1.0)
	world.owner.audit_combustion_reservations()
	_check(world.owner.state() == "armed", "zero reservation settles without rejection")
	_near(world.room.o2_inventory_kg, before, "zero reservation debits no O2")
	_dispose(world)


func _rejected_engine_stops_before_thermal() -> void:
	var world: Dictionary = _world()
	_prepare(world)
	world.owner.refuse_combustion(world.room, "synthetic_rejection_before_step")
	var upper_before: float = world.room.temp_upper_c
	var lower_before: float = world.room.temp_lower_c
	world.engine.step(0.25)
	_check(not world.engine.o2_room_inventory_failure.is_empty(), "engine latches owner refusal")
	_near(world.room.temp_upper_c, upper_before, "rejected engine stops before upper heat")
	_near(world.room.temp_lower_c, lower_before, "rejected engine stops before lower heat")
	_near(world.room.hrr_kj_total, 0.0, "rejected engine never records heat")
	_dispose(world)


func _run() -> void:
	_limited_step()
	_limited_step(true)
	_refusal_is_atomic()
	_flashover_and_reset()
	_whole_engine()
	_unsupported_combinations()
	_final_tick()
	_no_sink_cap()
	_zero_availability()
	_rejected_engine_stops_before_thermal()
	print("G3_O2_M3_INTEGRATION " + JSON.stringify({"checks": checks,
		"failure_count": failures.size(), "failures": failures}, "", true, true))
	quit(0 if failures.is_empty() else 1)

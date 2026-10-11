extends SceneTree

## DIAGNOSIS, not acceptance. Small synthetic rooms on the real engine, to see what
## each oxygen number of the engine does when nothing, heat, a controlled demand, a
## transport, a mixing or a reset acts on it. It judges nothing: the runner evaluates
## hypotheses that were written down before this ran.
##
## It changes no engine file and no law. What a case sets is listed in its `setup`:
## the geometry, the state it starts from and, where it says so, a declared isolation
## (no infiltration), the passive per-writer ledger the engine already has, or a
## declared diagnostic mode (the pressure network), which is not the product route
## and is approved by nobody here.
const BuildingModelScript = preload("res://sim/BuildingModel.gd")
const EngineScript = preload("res://sim/core/SimulationEngine.gd")
const CouplingScript = preload("res://sim/fire/PrescribedThermalSourceCoupling.gd")
const REFERENCE_DENSITY_KG_M3: float = 1.2
const ROOM_A: Dictionary = {"id": 0, "x": 0.0, "w": 5.0, "l": 4.0, "h": 2.4}
const ROOM_B: Dictionary = {"id": 1, "x": 5.0, "w": 4.0, "l": 4.0, "h": 2.4}
const SUB_STEPS: Array[String] = ["_step_oxygen", "_step_gas_exchange", "thermal", "_step_hvac", "_clamp_rooms"]

var _failed: bool = false
var _notes: Array[String] = []
var _out: Dictionary = {}


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_rest()
	_heated(false)
	_heated(true)
	_controlled_demand("controlled_demand_dt_0.5", 0.5, false)
	_controlled_demand("controlled_demand_dt_0.25", 0.25, false)
	_controlled_demand("controlled_demand_network_on", 0.5, true)
	_two_layers()
	_transport()
	_exterior("exterior_dt_0.5", 0.5)
	_exterior("exterior_dt_0.25", 0.25)
	_open_and_close()
	_collapse()
	_reset_and_reuse()
	_real_fire("real_fire", false)
	_real_fire("real_fire_network_on", true)
	print("G3_O2_AUTHORITY_DIAGNOSIS " + JSON.stringify({"notes": _notes, "cases": _out}, "", true, true))
	if _failed:
		quit(1)
	else:
		print("G3_O2_AUTHORITY_DIAGNOSIS_DONE")
		quit(0)


# ---------------------------------------------------------------- cases

## One sealed room, no fire, nothing done to it.
func _rest() -> void:
	var world: Dictionary = _world([ROOM_A], [], {"dt": 0.5})
	_out["rest"] = {"setup": _setup(world, "one sealed room, no fire, product defaults"), "start": _sample(world),
		"rows": _advance(world, 240), "writers": _writers(world)}
	_free(world)


## The same room with a hot upper layer written as the starting state, no fire: heat
## and no oxygen demand. With the pressure network it is the declared diagnostic mode.
func _heated(network_on: bool) -> void:
	var world: Dictionary = _world([ROOM_A], [], {"dt": 0.5, "network_on": network_on})
	_hot_upper_layer(world["rooms"][0], 12.0, 45.6, 200.0)
	var name: String = "heated_network_on" if network_on else "heated"
	_out[name] = {
		"setup": _setup(world, "one sealed room, no fire; starting state: 12 kg of upper gas with 200 kJ/kg, 45.6 kg of lower gas"),
		"start": _sample(world), "rows": _advance(world, 120), "writers": _writers(world),
	}
	_free(world)


## Two rooms closed to the outside with their door open. The diagnostic bench delivers
## a known power in room A: a controlled oxygen demand and no exterior exchange.
func _controlled_demand(name: String, dt: float, network_on: bool) -> void:
	var world: Dictionary = _world([ROOM_A, ROOM_B], [_door(1.0)], {
		"dt": dt, "ach": 0.0, "network_on": network_on, "bench_kw": 20.0, "bench_s": 120.0})
	_out[name] = {
		"setup": _setup(world, "two rooms closed to the outside, door open, no infiltration (declared isolation); bench: 20 kW for 120 s in room 0"),
		"start": _sample(world), "rows": _advance(world, int(round(120.0 / dt))),
		"bench": world["engine"].get_g3_prescribed_thermal_source_report(), "writers": _writers(world),
	}
	_free(world)


## One sealed room, no fire, two layers that start with different numbers.
func _two_layers() -> void:
	_out["two_layers_one_sub_step_alone"] = _alone(Callable(self, "_two_layers_world"))
	var world: Dictionary = _two_layers_world()
	_out["two_layers"] = {
		"setup": _setup(world, "one sealed room, no fire, no infiltration (declared isolation); starting numbers: room 0.18, upper 0.12, lower 0.20; hot upper layer as in `heated`"),
		"start": _sample(world), "rows": _advance(world, 240), "writers": _writers(world),
	}
	_free(world)


## Two rooms closed to the outside, no fire, door open, room B starts poorer.
func _transport() -> void:
	_out["transport_one_sub_step_alone"] = _alone(Callable(self, "_transport_world"))
	var world: Dictionary = _transport_world()
	_out["transport"] = {
		"setup": _setup(world, "two rooms closed to the outside, no fire, door open, no infiltration (declared isolation); room 1 starts at 0.15 in its three numbers"),
		"start": _sample(world), "rows": _advance(world, 480), "writers": _writers(world),
	}
	_free(world)


## One room with an exterior door open, no fire, starting poorer: the only exchange is
## the one with the outside, at the infiltration rate of the product.
func _exterior(name: String, dt: float) -> void:
	if dt == 0.5:
		_out["exterior_one_sub_step_alone"] = _alone(Callable(self, "_exterior_world"))
	var world: Dictionary = _world([ROOM_A], [_outside_door()], {"dt": dt})
	_poor(world["rooms"][0], 0.15)
	_out[name] = {
		"setup": _setup(world, "one room, exterior door open, no fire, product infiltration; the room starts at 0.15 in its three numbers"),
		"start": _sample(world), "rows": _advance(world, int(round(120.0 / dt))), "writers": _writers(world),
	}
	_free(world)


## The transport case with the door closed, opened and closed again.
func _open_and_close() -> void:
	var world: Dictionary = _world([ROOM_A, ROOM_B], [_door(0.0)], {"dt": 0.5, "ach": 0.0})
	_poor(world["rooms"][1], 0.15)
	var door = world["building"].get_openings()[0]
	var start: Array = _sample(world)
	var rows: Array = []
	var phases: Array = []
	for phase: Array in [["closed", 0.0, 40], ["open", 1.0, 80], ["closed_again", 0.0, 80]]:
		door.open_fraction = float(phase[1])
		phases.append({"name": phase[0], "first_row": rows.size(), "steps": int(phase[2])})
		rows.append_array(_advance(world, int(phase[2])))
	_out["open_and_close"] = {
		"setup": _setup(world, "as `transport`, with the door closed for 40 steps, open for 80 and closed for 80"),
		"start": start, "phases": phases, "rows": rows, "writers": _writers(world),
	}
	_free(world)


## One sealed room, no fire, an upper layer that takes almost the whole height: the
## sink then stops treating the room as two layers.
func _collapse() -> void:
	var world: Dictionary = _world([ROOM_A], [], {"dt": 0.5, "ach": 0.0})
	var room = world["rooms"][0]
	_hot_upper_layer(room, 26.0, 5.0, 300.0)
	room.o2 = 0.209
	room.o2_upper = 0.12
	room.o2_lower = 0.20
	_out["collapse"] = {
		"setup": _setup(world, "one sealed room, no fire, no infiltration (declared isolation); starting state: 26 kg of upper gas with 300 kJ/kg, 5 kg of lower gas; numbers: room 0.209, upper 0.12, lower 0.20"),
		"start": _sample(world), "rows": _advance(world, 20), "writers": _writers(world),
	}
	_free(world)


## The controlled demand run, a reset of the same engine and the same run again.
func _reset_and_reuse() -> void:
	var world: Dictionary = _world([ROOM_A, ROOM_B], [_door(1.0)], {
		"dt": 0.5, "ach": 0.0, "bench_kw": 20.0, "bench_s": 120.0})
	var first: Array = _advance(world, 160)
	var system = world["engine"].oxygen_exchange_system
	var in_transit_before_reset: int = system._pending_o2_deliveries.size()
	var reserved_before_reset: int = system._reserved_transport_o2_delta_kg.size()
	world["engine"].reset_simulation(0, bool(world["ignite"]))
	var after_reset: Array = _sample(world)
	var in_transit_after_reset: int = system._pending_o2_deliveries.size()
	var reserved_after_reset: int = system._reserved_transport_o2_delta_kg.size()
	var second: Array = _advance(world, 160)
	_out["reset_and_reuse"] = {
		"setup": _setup(world, "as `controlled_demand_dt_0.5`: 160 steps, `reset_simulation` on the same engine, 160 steps again"),
		"in_transit_entries_before_reset": in_transit_before_reset, "reserved_entries_before_reset": reserved_before_reset,
		"in_transit_entries_after_reset": in_transit_after_reset, "reserved_entries_after_reset": reserved_after_reset,
		"after_reset": after_reset, "first_digest": _digest(first), "second_digest": _digest(second),
		"first_last": first[first.size() - 1], "second_last": second[second.size() - 1],
		"largest_in_transit_first_run_kg": _largest_in_transit(first),
		"bench_state_second_run": world["engine"].get_g3_prescribed_thermal_source_report().get("state"),
	}
	_free(world)


## Two rooms closed to the outside, door open, a real room fire in room A with the
## product infiltration: the deposit the fire reads against the one the sink debits.
## With the pressure network it is the declared diagnostic mode.
func _real_fire(name: String, network_on: bool) -> void:
	var world: Dictionary = _world([ROOM_A, ROOM_B], [_door(1.0)], {"dt": 0.25, "fire": true, "network_on": network_on})
	_out[name] = {
		"setup": _setup(world, "two rooms closed to the outside, door open, product infiltration; room 0 burns a 1100 MJ, 700 kW upholstered object ignited at the start"),
		"start": _sample(world), "rows": _advance(world, 480), "writers": _writers(world),
	}
	_free(world)


func _two_layers_world() -> Dictionary:
	var world: Dictionary = _world([ROOM_A], [], {"dt": 0.5, "ach": 0.0})
	var room = world["rooms"][0]
	_hot_upper_layer(room, 12.0, 45.6, 200.0)
	room.o2 = 0.18
	room.o2_upper = 0.12
	room.o2_lower = 0.20
	return world


func _transport_world() -> Dictionary:
	var world: Dictionary = _world([ROOM_A, ROOM_B], [_door(1.0)], {"dt": 0.5, "ach": 0.0})
	_poor(world["rooms"][1], 0.15)
	return world


func _exterior_world() -> Dictionary:
	var world: Dictionary = _world([ROOM_A], [_outside_door()], {"dt": 0.5})
	_poor(world["rooms"][0], 0.15)
	return world


# ---------------------------------------------------------------- measuring

func _advance(world: Dictionary, steps: int) -> Array:
	var rows: Array = []
	for index: int in range(steps):
		world["engine"].step(float(world["dt"]))
		rows.append(_sample(world))
	return rows


## What the state shows after a step, room by room. `ref_kg` is the kilogram figure on
## the base every writer of the room number uses; `layers_ref_kg` is the two layer
## numbers on the geometric shares of that same base, an overlapping representation;
## `layers_gas_kg` is the two layer numbers on the layer gas masses, the convention of
## the pressure network. None of the three is added to another here.
func _sample(world: Dictionary) -> Array:
	var engine = world["engine"]
	var in_transit: Dictionary = {}
	for entry: Dictionary in engine.oxygen_exchange_system._pending_o2_deliveries:
		var target: int = int(entry.get("target", -1))
		in_transit[target] = float(in_transit.get(target, 0.0)) + float(entry.get("delta_o2_kg", 0.0))
	var sample: Array = []
	for room in world["rooms"]:
		var base_kg: float = maxf(0.1, room.volume_m3()) * REFERENCE_DENSITY_KG_M3
		var interface_m: float = clampf(engine.thermal_system.flow_interface_height_m(room), 0.0, room.height_m)
		var upper_share: float = maxf(0.01, (room.height_m - interface_m) / maxf(0.01, room.height_m))
		sample.append({
			"room": room.id, "o2": room.o2, "o2_upper": room.o2_upper, "o2_lower": room.o2_lower,
			"base_kg": base_kg, "upper_share": upper_share,
			"ref_kg": base_kg * room.o2,
			"layers_ref_kg": base_kg * (upper_share * room.o2_upper + (1.0 - upper_share) * room.o2_lower),
			"upper_gas_kg": room.upper_gas_kg, "lower_gas_kg": room.lower_gas_kg,
			"layers_gas_kg": room.o2_upper * room.upper_gas_kg + room.o2_lower * room.lower_gas_kg,
			"boundary_gas_kg": room.two_zone_boundary_mass_kg,
			"temp_upper_c": room.temp_upper_c, "temp_lower_c": room.temp_lower_c,
			"overpressure_pa": room.overpressure_pa,
			"power_kw": room.hrr_kw, "heat_kj": room.hrr_kj_total,
			"debit_room_inventory_kg": room.o2_consumed_bulk_kg_total,
			"debit_primary_kg": room.o2_consumed_fire_kg_total,
			"debits_declared_kg": room.o2_consumed_kg_total_all,
			"exterior_kg": room.o2_exterior_net_kg_total,
			"transport_kg": room.o2_net_transport_kg_total,
			"zone_sync_kg": room.o2_zone_sync_kg_total,
			"in_transit_kg": float(in_transit.get(room.id, 0.0)),
			"fire_deposit": String(room.fire_o2_mode_used), "fire_reads": room.fire_o2_ref,
			"tracked_upper_kg": room.upper_o2_mass_tracked,
		})
	return sample


## Writers the passive ledger of the engine saw, by owner and number. The ledger sums
## fractions over rooms: it names who wrote and how often, not kilograms.
func _writers(world: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var totals: Dictionary = world["engine"]._phase3_o2_attribution_combined().get("totals", {})
	for key: String in totals.keys():
		var entry: Dictionary = totals[key]
		out[key] = {"applications": entry.get("applications"), "accepted_fraction_total": entry.get("accepted_fraction_total"),
			"requested_fraction_total": entry.get("requested_fraction_total"), "times_clamped": entry.get("strict_count")}
	return out


## One sub-step of the engine alone, on a fresh world each time: what a single call
## does to the three numbers of every room.
func _alone(builder: Callable) -> Dictionary:
	var out: Dictionary = {}
	for name: String in SUB_STEPS:
		var world: Dictionary = builder.call()
		var engine = world["engine"]
		var dt: float = float(world["dt"])
		engine._step_exterior_opening_smooth(dt)
		engine._opening_flow_cache = engine._build_opening_flow_cache()
		var before: Array = _sample(world)
		if name == "thermal":
			engine.thermal_system.step(world["building"], dt, {
				"outside_open_path_factor_callable": Callable(engine, "_outside_open_path_factor_for_room"),
				"opening_flow_cache": engine._opening_flow_cache,
			})
		else:
			engine.call(name, dt)
		var after: Array = _sample(world)
		var rooms: Array = []
		for index: int in range(before.size()):
			rooms.append({
				"room": before[index]["room"],
				"room_number_change_kg": after[index]["ref_kg"] - before[index]["ref_kg"],
				"room_number_change": after[index]["o2"] - before[index]["o2"],
				"upper_number_change": after[index]["o2_upper"] - before[index]["o2_upper"],
				"lower_number_change": after[index]["o2_lower"] - before[index]["o2_lower"],
				"transport_accumulator_kg": after[index]["transport_kg"] - before[index]["transport_kg"],
				"exterior_accumulator_kg": after[index]["exterior_kg"] - before[index]["exterior_kg"],
				"gas_change_kg": after[index]["upper_gas_kg"] + after[index]["lower_gas_kg"]
						- before[index]["upper_gas_kg"] - before[index]["lower_gas_kg"],
			})
		out[name] = rooms
		_free(world)
	return out


func _digest(rows: Array) -> String:
	var values := PackedFloat64Array()
	for sample: Array in rows:
		for row: Dictionary in sample:
			for key: String in ["o2", "o2_upper", "o2_lower", "upper_gas_kg", "lower_gas_kg", "temp_upper_c", "temp_lower_c",
					"debit_room_inventory_kg", "debits_declared_kg", "transport_kg", "in_transit_kg"]:
				values.append(float(row[key]))
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(values.to_byte_array())
	return context.finish().hex_encode()


func _largest_in_transit(rows: Array) -> float:
	var largest: float = 0.0
	for sample: Array in rows:
		for row: Dictionary in sample:
			largest = maxf(largest, absf(float(row["in_transit_kg"])))
	return largest


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
	var declared: Array[String] = []
	if options.has("ach"):
		engine.ach_infiltration = float(options["ach"])
		declared.append("ach_infiltration = %s (isolation)" % str(options["ach"]))
	if bool(options.get("network_on", false)):
		engine.pressure_network_solver_enabled = true
		declared.append("pressure_network_solver_enabled = true (diagnostic mode, not the product route)")
	if options.has("bench_kw"):
		var table: Dictionary = _synthetic([[0.0, float(options["bench_kw"])], [float(options["bench_s"]), float(options["bench_kw"])]])
		var opened: RefCounted = CouplingScript.SourceScript.new()
		opened.open(table)
		engine.energy_budget_enabled = true
		engine.energy_budget_warn_fraction = 1.0e9
		engine.g3_prescribed_thermal_source_enabled = true
		engine.g3_prescribed_thermal_source_case = {
			"schema": CouplingScript.CASE_SCHEMA, "room_id": 0, "source": table,
			"expected_source_fingerprint": String(opened.report().get("source_fingerprint")), "oxygen_kg_per_MJ": 0.076,
			"radiative_fraction": {"value": 0.35, "class": "assumed", "what": "engine default"},
			"regime": {"oxygen_drop_tolerance": 0.5, "layer_interface_min_m": 0.0, "status": CouplingScript.REGIME_STATUS},
		}
		declared.append("diagnostic bench armed in room 0 with a synthetic table (its regime limits widened: the regime is not what is measured here)")
	# The passive per-writer ledger the engine already has (off by default).
	engine.phase3_o2_attribution_diagnostics_enabled = true
	declared.append("phase3_o2_attribution_diagnostics_enabled = true (passive ledger of the engine)")
	engine.suppress_exit_graphs()
	root.add_child(engine)
	# The clock of the bench starts with the ignition event of the engine; in a room
	# with nothing to burn that event starts nothing else.
	var ignite: bool = bool(options.get("fire", false)) or options.has("bench_kw")
	engine.reset_simulation(0, ignite)
	if options.has("bench_kw") and engine.g3_prescribed_thermal_source_failure != "":
		_notes.append("a bench did not arm: " + str(engine.get_g3_prescribed_thermal_source_report().get("failure")))
	var models: Array = []
	for spec: Dictionary in specs:
		models.append(building.get_room(int(spec["id"])))
	return {"engine": engine, "building": building, "rooms": models, "dt": float(options["dt"]), "declared": declared,
		"ignite": ignite}


func _setup(world: Dictionary, what: String) -> Dictionary:
	var engine = world["engine"]
	var built_rooms: Array = []
	for room in world["building"].get_rooms().values():
		built_rooms.append({"id": room.id, "volume_m3": room.volume_m3(), "height_m": room.height_m,
			"fuel_energy_MJ": room.fuel_energy_MJ, "fuel_objects": room.fuel_objects.size()})
	var built_openings: Array = []
	for op in world["building"].get_openings():
		built_openings.append({"a": op.a, "b": op.b, "width_m": op.width_m, "height_m": op.height_m, "open_fraction": op.open_fraction})
	return {
		"what": what, "dt_s": world["dt"], "declared_changes": world["declared"],
		"rooms": built_rooms, "openings": built_openings,
		"engine": {
			"two_zone_solver_enabled": engine.two_zone_solver_enabled,
			"oxygen_system_sees_two_zones": engine.oxygen_exchange_system.two_zone_solver_enabled,
			"fire_o2_mode": engine.fire_o2_mode, "ach_infiltration": engine.ach_infiltration,
			"pressure_network_solver_enabled": engine.pressure_network_solver_enabled,
			"interior_transport_enabled": engine.interior_transport_enabled,
			"mass_tracking_of_the_upper_number": engine.oxygen_exchange_system.fire_o2_mass_tracking_enabled,
			"outside_o2": engine.building.outside_o2,
		},
	}


func _hot_upper_layer(room, upper_kg: float, lower_kg: float, kj_per_kg: float) -> void:
	room.upper_gas_kg = upper_kg
	room.lower_gas_kg = lower_kg
	room.upper_energy_kj = upper_kg * kj_per_kg
	room.lower_energy_kj = 0.0


func _poor(room, value: float) -> void:
	room.o2 = value
	room.o2_upper = value
	room.o2_lower = value


func _door(open_fraction: float) -> Dictionary:
	return {"a": 0, "b": 1, "type": "door", "width_m": 0.9, "height_m": 2.0, "sill_m": 0.0, "offset_m": 0.5,
		"offset_is_fraction": true, "open_fraction": open_fraction, "wall": "", "hinge_side": "left", "swing_direction": "in"}


func _outside_door() -> Dictionary:
	return {"a": 0, "b": -1, "type": "door", "width_m": 0.9, "height_m": 2.0, "open_fraction": 1.0, "offset_m": 0.5,
		"offset_is_fraction": true, "sill_m": 0.0, "wall": "bottom"}


func _synthetic(points: Array) -> Dictionary:
	var samples: Array = []
	for point: Array in points:
		samples.append({"time_s": point[0], "hrr_kw": point[1]})
	var unknown: Dictionary = {}
	for key: String in CouplingScript.SourceScript.UNKNOWN_KEYS:
		unknown[key] = null
	return {
		"schema": CouplingScript.SourceScript.SOURCE_SCHEMA, "owner_id": "synthetic_object_as_tested", "run_id": "synthetic_run_1",
		"quantity": "measured_calorimetric_hrr", "time_unit": "s", "hrr_unit": "kW", "energy_unit": "kJ",
		"time_origin": "documented_ignition_event", "interpolation": "piecewise_linear",
		"outside_support": "reject", "negative_samples": "none_in_source", "regime": "open_air_as_tested",
		"provenance": {
			"dataset": "synthetic analytic table, not a measurement", "dataset_version": "v1",
			"license": "none needed", "source_file": "tests/fixtures/g3_o2_authority_diagnosis.gd",
			"source_sha256": "0".repeat(64), "source_column": "hrr_kw", "support_events": "0 to the last node",
			"importer": "written by hand", "table_fingerprint": "1".repeat(64),
		},
		"unknown": unknown, "samples": samples,
	}


func _free(world: Dictionary) -> void:
	world["engine"].queue_free()
	world["building"].queue_free()

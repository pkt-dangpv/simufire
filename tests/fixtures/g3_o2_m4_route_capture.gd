extends "res://tests/fixtures/g3_o2_m3_diagnosis.gd"

## M4-B2: observer subclasses in this fixture ONLY. Calls parent once and
## records copies, never changes a flow, gas, oxygen inventory or physical flag.
## Paired vanilla worlds must produce identical full-precision physics states.


class Recorder:


	extends RefCounted

	var rows: Array[Dictionary] = []
	var owner = null
	var tick: int = 0
	var sequence: int = 0
	var mechanism: String = "unspecified_zone_transfer"
	var stage: String = "unassigned"
	var opening_index: int = -1
	var case_name: String = ""

	func snapshot(rooms: Array) -> Array:
		var result: Array = []
		for room in rooms:
			result.append({"id": room.id, "o2_inventory_kg": room.o2_inventory_kg,
				"volume_m3": room.volume_m3(),
				"room_reference_fraction": room.o2,
				"upper_auxiliary_fraction_not_inventory": room.o2_upper,
				"lower_auxiliary_fraction_not_inventory": room.o2_lower,
				"thermal_interface_m": room.thermal_layer_m, "height_m": room.height_m,
				"upper_gas_kg_not_reference_base": room.upper_gas_kg,
				"lower_gas_kg_not_reference_base": room.lower_gas_kg})
		return result

	func begin(route: String, rooms: Array, data: Dictionary = {}) -> Dictionary:
		sequence += 1
		return {"event_id": "%s:tick%d:call%d" % [case_name, tick, sequence], "tick": tick,
			"case": case_name,
			"generation": owner.generation(), "stage": stage,
			"route": route, "opening_index": opening_index, "mechanism": mechanism,
			"before": snapshot(rooms), "data": data.duplicate(true),
			"operation_offset": owner.report()["step_operations"].size()}

	func finish(row: Dictionary, rooms: Array) -> void:
		row["after"] = snapshot(rooms)
		var operations: Array = owner.report()["step_operations"]
		row["owner_operations"] = operations.slice(int(row["operation_offset"])).duplicate(true)
		rows.append(row)


class OxygenObserver:


	extends "res://sim/core/OxygenExchangeSystem.gd"

	var recorder = null

	func step(building: BuildingModel, dt: float, hooks: Dictionary) -> void:
		var previous: String = recorder.stage
		recorder.stage = "oxygen"
		var rooms: Array = building.get_rooms().values()
		var row: Dictionary = recorder.begin("oxygen_stage_container", rooms)
		super.step(building, dt, hooks)
		recorder.finish(row, rooms)
		recorder.stage = previous

	func _step_owned_room_inventory(building: BuildingModel, room: RoomModel,
			dt: float, air_density_kg_m3: float) -> float:
		var row: Dictionary = recorder.begin("oxygen_room_sink_and_ach", [room],
			{"dt": dt, "outside_fraction": building.outside_o2})
		var result: float = super._step_owned_room_inventory(building, room, dt, air_density_kg_m3)
		row["data"]["accepted_primary_o2_kg"] = result
		recorder.finish(row, [room])
		return result

	func _step_interior_opening_o2(building: BuildingModel, dt: float, op: OpeningModel,
			room_a: RoomModel, room_b: RoomModel, air_density_kg_m3: float, g_gravity: float,
			build_interior_flow_callable: Callable, outside_open_path_factor_callable: Callable,
			opening_flow_cache: Dictionary = {}) -> void:
		var previous: int = recorder.opening_index
		recorder.opening_index = op.opening_index
		super._step_interior_opening_o2(building, dt, op, room_a, room_b, air_density_kg_m3,
			g_gravity, build_interior_flow_callable, outside_open_path_factor_callable, opening_flow_cache)
		recorder.opening_index = previous

	func _exchange_room_o2_immediate(room_a: RoomModel, room_b: RoomModel,
			exchange_kg: float, air_density_kg_m3: float) -> void:
		var row: Dictionary = recorder.begin("interior_background", [room_a, room_b],
			{"accepted_reference_gas_kg": exchange_kg, "precap_request": null})
		super._exchange_room_o2_immediate(room_a, room_b, exchange_kg, air_density_kg_m3)
		recorder.finish(row, [room_a, room_b])

	func _exchange_room_o2_active_flow(building: BuildingModel, hot_room: RoomModel,
			cold_room: RoomModel, exchange_kg: float, air_density_kg_m3: float) -> void:
		var row: Dictionary = recorder.begin("interior_active", [hot_room, cold_room],
			{"accepted_reference_gas_kg": exchange_kg, "precap_request": null})
		super._exchange_room_o2_active_flow(building, hot_room, cold_room, exchange_kg, air_density_kg_m3)
		recorder.finish(row, [hot_room, cold_room])


class ThermalObserver:


	extends "res://sim/core/ThermalSystem.gd"

	var recorder = null

	func step(building: BuildingModel, dt: float, hooks: Dictionary = {}) -> void:
		var previous: String = recorder.stage
		recorder.stage = "thermal"
		super.step(building, dt, hooks)
		recorder.stage = previous

	func reconcile_two_zone_building(building: BuildingModel, dt: float) -> void:
		var previous: String = recorder.stage
		recorder.stage = "reconcile"
		super.reconcile_two_zone_building(building, dt)
		recorder.stage = previous

	func _step_two_zone_plume_entrainment(room: RoomModel, dt: float, ambient_c: float) -> void:
		var previous: String = recorder.mechanism
		recorder.mechanism = "thermal_plume"
		super._step_two_zone_plume_entrainment(room, dt, ambient_c)
		recorder.mechanism = previous

	func _ensure_minimal_upper_gas(room: RoomModel, ambient_c: float) -> void:
		var previous: String = recorder.mechanism
		recorder.mechanism = "thermal_minimal_upper_seed"
		super._ensure_minimal_upper_gas(room, ambient_c)
		recorder.mechanism = previous

	func sync_room_upper_layer(room: RoomModel, dt: float,
			projection_cause: String = "thermal_layer_sync") -> void:
		var row: Dictionary = recorder.begin("thermal_sync", [room], {"projection_cause": projection_cause})
		super.sync_room_upper_layer(room, dt, projection_cause)
		recorder.finish(row, [room])


class ZoneObserver:


	extends "res://sim/core/ZoneFireSolver.gd"

	var recorder = null

	func preview_lower_to_upper_transfer(room: RoomModel, requested_mass_kg: float) -> Dictionary:
		var row: Dictionary = recorder.begin("zone_preview", [room],
			{"solver_requested_physical_gas_kg": requested_mass_kg})
		var result: Dictionary = super.preview_lower_to_upper_transfer(room, requested_mass_kg)
		row["data"]["accepted_transfer"] = result.duplicate(true)
		recorder.finish(row, [room])
		return result

	func apply_lower_to_upper_transfer(room: RoomModel, transfer: Dictionary) -> void:
		var row: Dictionary = recorder.begin("zone_apply", [room], {"transfer": transfer.duplicate(true)})
		super.apply_lower_to_upper_transfer(room, transfer)
		recorder.finish(row, [room])


class GasObserver:


	extends "res://sim/core/GasExchangeSystem.gd"

	var recorder = null

	func step_pressure_venting(building: BuildingModel, dt: float, hooks: Dictionary) -> Dictionary:
		var previous: String = recorder.stage
		recorder.stage = "gas"
		var rooms: Array = building.get_rooms().values()
		var row: Dictionary = recorder.begin("pressure_venting", rooms,
			{"per_opening_request": null, "outside_fraction": building.outside_o2})
		var result: Dictionary = super.step_pressure_venting(building, dt, hooks)
		row["data"]["return"] = result.duplicate(true)
		recorder.finish(row, rooms)
		recorder.stage = previous
		return result

	func step_smoke(building: BuildingModel, smoke_model: SmokeModel,
			dt: float, hooks: Dictionary) -> Dictionary:
		var previous: String = recorder.stage
		recorder.stage = "gas"
		var result: Dictionary = super.step_smoke(building, smoke_model, dt, hooks)
		recorder.stage = previous
		return result


func _copy_service(source, target) -> void:
	for property: Dictionary in source.get_property_list():
		if int(property["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			target.set(str(property["name"]), source.get(str(property["name"])))


func _observe(world: Dictionary, name: String):
	var engine = world["engine"]
	var recorder = Recorder.new()
	recorder.case_name = name
	recorder.owner = engine.get("_o2_room_inventory")
	var oxygen = OxygenObserver.new()
	var thermal = ThermalObserver.new()
	var zone = ZoneObserver.new()
	var gas = GasObserver.new()
	_copy_service(engine.oxygen_exchange_system, oxygen)
	_copy_service(engine.thermal_system, thermal)
	_copy_service(engine.zone_fire_solver, zone)
	_copy_service(engine.gas_exchange_system, gas)
	for observer in [oxygen, thermal, zone, gas]:
		observer.recorder = recorder
	engine.oxygen_exchange_system = oxygen
	engine.thermal_system = thermal
	engine.zone_fire_solver = zone
	engine.gas_exchange_system = gas
	thermal.set_zone_fire_solver(zone)
	return recorder


func _primitive_state(object) -> Dictionary:
	var result: Dictionary = {}
	for property: Dictionary in object.get_property_list():
		if not (int(property["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		var value = object.get(str(property["name"]))
		if typeof(value) == TYPE_FLOAT and not is_finite(value):
			var label: String = "NaN" if is_nan(value) else "positive_infinity" if value > 0.0 else "negative_infinity"
			result[str(property["name"])] = {"nonfinite_float": label}
			continue
		if typeof(value) in [TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING]:
			result[str(property["name"])] = value
	return result


func _physics_state(world: Dictionary) -> String:
	var rooms: Array = []
	for room in world["rooms"]:
		var objects: Array = []
		for object in room.fuel_objects:
			objects.append(_primitive_state(object))
		rooms.append({"room": _primitive_state(room), "objects": objects,
			"fire": _primitive_state(room.fire) if room.fire != null else null})
	var openings: Array = []
	for opening in world.building.get_openings():
		openings.append(_primitive_state(opening))
	return JSON.stringify({"rooms": rooms, "time_s": world.engine.sim_time_s,
		"openings": openings,
		"oxygen": world.engine.get_o2_room_inventory_report(),
		"failure": world.engine.o2_room_inventory_failure}, "", true, true)


func _configure_case(world: Dictionary, name: String) -> void:
	var building = world["building"]
	if name == "two_doors":
		var second = OpeningModel.new(0, 1, OpeningModel.Type.DOOR, 0.9, 2.0)
		second.a = 0
		second.b = 1
		second.width_m = 0.9
		second.height_m = 2.0
		second.open_fraction = 1.0
		second.opening_index = building.get_openings().size()
		building.get_openings().append(second)
	elif name == "closed_window":
		var window = OpeningModel.new(0, BuildingModel.OUTSIDE_ID, OpeningModel.Type.WINDOW, 0.8, 1.0, 0.0, 0.8)
		window.a = 0
		window.b = BuildingModel.OUTSIDE_ID
		window.type = OpeningModel.Type.WINDOW
		window.width_m = 0.8
		window.height_m = 1.0
		window.sill_m = 0.8
		window.open_fraction = 0.0
		window.open_fraction_smooth = 0.0
		window.opening_index = building.get_openings().size()
		building.get_openings().append(window)


func _run() -> void:
	var failures: Array[String] = []
	var checks: int = 0
	var cases: Dictionary = {}
	var folder: String = OS.get_environment("G3_M4_ROUTE_OUT")
	if folder.is_empty():
		push_error("M4 route capture needs external output folder")
		quit(2)
		return
	for name: String in ["sealed", "one_door", "two_doors", "closed_window"]:
		var ticks: int = 1200 if name == "closed_window" else 240
		var setup: Dictionary = {"rooms": 2, "door": name in ["one_door", "two_doors"],
			"dt": 0.25, "fire": SOFA}
		var plain: Dictionary = _world(setup)
		var observed: Dictionary = _world(setup)
		_configure_case(plain, name)
		_configure_case(observed, name)
		var recorder = _observe(observed, name)
		var file = FileAccess.open(folder.path_join(name + ".jsonl"), FileAccess.WRITE)
		if file == null:
			failures.append("external rows unavailable")
			quit(2)
			return
		checks += 1
		if _physics_state(plain) != _physics_state(observed):
			failures.append(name + " initial state mismatch")
		for tick: int in range(ticks):
			recorder.tick = tick
			var before_tick: Array = recorder.snapshot(observed["rooms"])
			plain.engine.step(0.25)
			observed.engine.step(0.25)
			checks += 2
			if _physics_state(plain) != _physics_state(observed):
				failures.append("%s identity mismatch tick %d" % [name, tick])
			if not plain.engine.o2_room_inventory_failure.is_empty():
				failures.append(name + " owner rejected")
			for row: Dictionary in recorder.rows:
				file.store_line(JSON.stringify(row, "", true, true))
			file.store_line(JSON.stringify({"route": "tick_summary", "tick": tick,
				"before": before_tick, "after": recorder.snapshot(observed["rooms"]),
				"owner_operations": recorder.owner.report()["step_operations"]}, "", true, true))
			recorder.rows.clear()
		file.close()
		cases[name] = {"ticks": ticks, "duration_s": observed.engine.sim_time_s,
			"events": recorder.sequence, "owner_state": recorder.owner.state()}
		plain.engine.free()
		plain.building.free()
		observed.engine.free()
		observed.building.free()
	print("G3_M4_ROUTE_CAPTURE " + JSON.stringify({"checks": checks,
		"failure_count": failures.size(), "failures": failures, "cases": cases,
		"product_activation": false}, "", true, true))
	quit(0 if failures.is_empty() else 1)

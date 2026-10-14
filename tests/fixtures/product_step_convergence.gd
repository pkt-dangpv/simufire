extends SceneTree

## Independent numerical screening on real product-preset physics. This is not
## an experimental validation or a replacement for official reference cases.
const BuildingScript := preload("res://sim/BuildingModel.gd")
const TemplateScript := preload("res://sim/templates/BuildingTemplate.gd")
const EngineScript := preload("res://sim/core/SimulationEngine.gd")
const OpeningScript := preload("res://sim/building/OpeningModel.gd")
var denominator: int = 60
var schedule: String = "open"
var destination: String = ""
var duration_s: int = 180
var running: bool = false
var completed: bool = false


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--step-denominator="):
			denominator = int(arg.get_slice("=", 1))
		elif arg.begins_with("--door-schedule="):
			schedule = arg.get_slice("=", 1)
		elif arg.begins_with("--evidence-out="):
			destination = arg.trim_prefix("--evidence-out=")
		elif arg.begins_with("--duration-s="):
			duration_s = int(arg.get_slice("=", 1))
	call_deferred("_run")


func _process(_delta: float) -> bool:
	# _run is synchronous. Reaching another frame before it completes means a
	# runtime assertion aborted it; fail promptly instead of hanging until the
	# outer monitor timeout. This never interrupts an active numerical loop.
	if running and not completed:
		push_error("Numerical fixture aborted before writing its terminal result")
		quit(1)
	return false


func _run() -> void:
	running = true
	if denominator not in [12, 30, 40, 60] or schedule not in ["open", "close_reopen"] \
			or destination.is_empty() or duration_s <= 0:
		push_error("Invalid numerical screening request")
		quit(1)
		return
	seed(20261014)
	var building := BuildingScript.new()
	root.add_child(building)
	var data: Dictionary = TemplateScript.new().create_product_preset("simple_house")
	data["building_type"] = "apartment"
	data["apartment_floor_number"] = 15
	data["building_total_floors"] = 20
	data["wind_speed_m_s"] = 0.0
	data["hvac_mode"] = "none"
	if not building.load_template_data(data):
		push_error("Casa simple could not be loaded")
		quit(1)
		return
	var engine := EngineScript.new()
	engine.building = building
	engine.auto_ignite_on_ready = false
	engine.auto_finish_on_extinction = false
	engine.enable_logging = false
	engine.enable_csv_log = false
	root.add_child(engine)
	engine.apply_runtime_options({"glass_break_mode": 0, "hvac_mode": "none"})
	engine.time_scale = 1.0
	engine.sim_fixed_dt = 0.0
	engine.reset_simulation(0, true)
	# reset_simulation clears this flag; suppress after reset so cleanup does
	# not spawn the interactive chart/dashboard generators.
	engine.suppress_exit_graphs()
	engine.sim_duration_limit_s = 0.0
	var door_index: int = -1
	for index: int in range(building.openings.size()):
		var opening = building.openings[index]
		if opening.a == 0 and opening.b == 1 and opening.type == OpeningScript.Type.DOOR:
			door_index = index
	if door_index < 0 or building.rooms.size() != 6:
		push_error("Expected six-room preset and salon/pasillo door")
		quit(1)
		return
	var samples: Array = []
	var events: Array = []
	var started: int = Time.get_ticks_usec()
	var finite_values: bool = true
	for tick: int in range(duration_s * denominator):
		# Interventions occur at exactly the same simulated instant for every dt.
		if schedule == "close_reopen" and tick in [45 * denominator, 90 * denominator]:
			var fraction: float = 0.0 if tick == 45 * denominator else 1.0
			if not building.set_opening_fraction(door_index, fraction):
				push_error("Door intervention was not applied")
				quit(1)
				return
			events.append({"time_s": float(tick) / denominator, "fraction": fraction})
		engine.step(1.0 / denominator)
		if (tick + 1) % denominator != 0:
			continue
		var state: Dictionary = engine.get_state()
		var rooms: Dictionary = {}
		for room_id: Variant in building.rooms:
			var room = building.rooms[room_id]
			var exported: Dictionary = state[str(room_id)]
			var values: Array = [room.hrr_kw, room.temp_upper_c, room.temp_lower_c,
				room.smoke_kg, exported["co_upper_ppm"], room.o2_upper, room.o2_lower,
				exported["smoke_layer_m"], room.upper_energy_kj, room.lower_energy_kj,
				room.hrr_kj_total]
			for value: Variant in values:
				finite_values = finite_values and is_finite(float(value))
			rooms[str(room_id)] = values
		samples.append({"time_s": float(tick + 1) / denominator, "rooms": rooms,
			"clock_s": engine.sim_time_s,
			"carbon_error_kg": state["global_carbon_error_kg"]})
		if (tick + 1) % (30 * denominator) == 0:
			print("STEP_CONVERGENCE_PROGRESS " + JSON.stringify({"denominator": denominator,
				"schedule": schedule, "time_s": float(tick + 1) / denominator}))
	var clock_ok: bool = absf(engine.sim_time_s - duration_s) < 1.0e-6
	var report: Dictionary = {"denominator": denominator, "schedule": schedule,
		"duration_s": duration_s, "steps": duration_s * denominator,
		"wall_s": float(Time.get_ticks_usec() - started) / 1000000.0,
		"finite_values": finite_values, "clock_ok": clock_ok, "events": events,
		"room_count": building.rooms.size(), "samples": samples,
		"fields": ["hrr_kw", "temp_upper_c", "temp_lower_c", "smoke_kg", "co_upper_ppm",
			"o2_upper", "o2_lower", "smoke_layer_m", "upper_energy_kj", "lower_energy_kj",
			"released_heat_kj"]}
	var file := FileAccess.open(destination, FileAccess.WRITE)
	file.store_string(JSON.stringify(report))
	file.close()
	completed = true
	engine.free()
	building.free()
	print("STEP_CONVERGENCE_DONE " + JSON.stringify({"path": destination,
		"finite_values": finite_values, "clock_ok": clock_ok}))
	quit(0 if finite_values and clock_ok else 1)

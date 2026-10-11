extends SceneTree

## DIAGNOSIS, not acceptance. Stage M3 of the oxygen authority is not implemented:
## this fixture measures, on the REAL SimulationEngine and with the room oxygen
## inventory on, what the engine does today when the heat it accepts is and is not
## backed by the oxygen its owner can debit. It judges nothing and changes no engine
## file and no law: the runner evaluates the rows in Python.
##
## Every case steps the whole engine and writes one row per step with what the state
## shows: the power the fire proposed (its target), the power it kept after its
## filter, the heat the combustion system accounted, what the sink asked the owner
## for, what was applied and what the cap clipped, the fuel debited, the products
## generated, the inventory, the selection of the step, what the room owes in transit
## and what arrived.
##
## What a case sets is in its `setup`. Three cases put an operation of the owner
## between two steps, declared as such: they are not routes of the engine, they are
## the way to bring a state about (a drop of the inventory, a pending arrival, an
## obligation). The prescribed fire is the engine's own switch for a fire that ignores
## the oxygen limitation.
##
## The rows go to the folder named by G3_O2_M3_DIAGNOSIS_OUT, one file per case. With
## no folder only the summaries are printed.
const BuildingModelScript = preload("res://sim/BuildingModel.gd")
const EngineScript = preload("res://sim/core/SimulationEngine.gd")

const ROOM_A: Dictionary = {"id": 0, "x": 0.0, "w": 5.0, "l": 4.0, "h": 2.4}
const ROOM_B: Dictionary = {"id": 1, "x": 5.0, "w": 4.0, "l": 4.0, "h": 2.4}
## A small room, 9.6 m3: the same fire asks for a larger share of what it holds.
const ROOM_SMALL: Dictionary = {"id": 0, "x": 0.0, "w": 2.0, "l": 2.0, "h": 2.4}
const SOFA: Dictionary = {"max_hrr_kw": 700.0, "fuel_MJ": 1100.0}
## The object of the stress control `o2_stress_cap`: 3 MW, 300 MJ.
const STRESS: Dictionary = {"max_hrr_kw": 3000.0, "fuel_MJ": 300.0}
const STRESS_ALPHA_KW_S2: float = 0.188

var _out_dir: String = ""
var _summaries: Dictionary = {}


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_out_dir = OS.get_environment("G3_O2_M3_DIAGNOSIS_OUT")
	# 1. A demand that fits.
	_case("fits", {"what": "two rooms closed to the outside, door open, a 700 kW sofa; the demand always fits",
		"rooms": 2, "door": true, "dt": 0.25, "steps": 1200, "fire": SOFA})
	# 2. A demand large against the inventory, at four time steps: the object of the stress control
	#    in two rooms, and in one small sealed room, where the 5 % cap of the sink can come in.
	for dt: float in [2.0, 1.0, 0.5, 0.25]:
		_case("stress dt %s" % str(dt), {"what": "the object of o2_stress_cap (3 MW, 300 MJ, alpha 0.188, no secondary gain) in two rooms; 600 s",
			"rooms": 2, "door": true, "dt": dt, "steps": int(round(600.0 / dt)), "fire": STRESS, "alpha": STRESS_ALPHA_KW_S2, "no_secondary_gain": true})
	for dt: float in [2.0, 1.0, 0.5, 0.25]:
		_case("small room dt %s" % str(dt), {"what": "the same object in one sealed room of 9.6 m3; 300 s",
			"rooms": 1, "small": true, "door": false, "dt": dt, "steps": int(round(300.0 / dt)), "fire": STRESS, "alpha": STRESS_ALPHA_KW_S2, "no_secondary_gain": true})
	# 3. Towards running out: a sealed room and the engine's switch for a prescribed fire.
	_case("prescribed", {"what": "one sealed room and a fire with fire_o2_independent, 700 kW; 600 s",
		"rooms": 1, "door": false, "dt": 0.25, "steps": 2400, "fire": SOFA, "prescribed": true})
	# 4. The availability drops at once while the power is high.
	_case("drop to below the flame limit", {"what": "the fits case; at 150 s an operation of the owner moves 60 % of the oxygen of the room that burns to its neighbour",
		"rooms": 2, "door": true, "dt": 0.25, "steps": 1200, "fire": SOFA, "at_s": 150.0, "move_fraction": 0.60})
	_case("drop that keeps the flame", {"what": "the fits case; at 150 s an operation of the owner moves 20 % of the oxygen of the room that burns to its neighbour",
		"rooms": 2, "door": true, "dt": 0.25, "steps": 1200, "fire": SOFA, "at_s": 150.0, "move_fraction": 0.20})
	# 5. A positive arrival is pending.
	_case("pending arrival", {"what": "the fits case; at 150 s an operation of the owner sends 1 kg to the room that burns, to arrive 5 s later",
		"rooms": 2, "door": true, "dt": 0.25, "steps": 1200, "fire": SOFA, "at_s": 150.0, "arrival_kg": 1.0, "delay_s": 5.0})
	# 6. The room owes oxygen in transit.
	_case("obligation", {"what": "the fits case; at 150 s an operation of the owner makes the room that burns owe all it holds but 0.25 kg, due 30 s later",
		"rooms": 2, "door": true, "dt": 0.25, "steps": 1200, "fire": SOFA, "at_s": 150.0, "owe_all_but_kg": 0.25, "delay_s": 30.0})
	_case("obligation with the door closed", {"what": "two rooms with no door between them, the sofa in one; at 100 s an operation of the owner makes it owe all it holds but 0.02 kg, due 1 s later",
		"rooms": 2, "door": false, "dt": 0.25, "steps": 1200, "fire": SOFA, "at_s": 100.0, "owe_all_but_kg": 0.02, "delay_s": 1.0})
	# 7. The fuel runs out.
	_case("end of fuel", {"what": "the fits case with 40 MJ of fuel",
		"rooms": 2, "door": true, "dt": 0.25, "steps": 1200, "fire": {"max_hrr_kw": 700.0, "fuel_MJ": 40.0}})
	print("G3_O2_M3_DIAGNOSIS " + JSON.stringify({"cases": _summaries, "rows_written_to": _out_dir != ""}, "", true, true))
	quit(0)


func _case(name: String, setup: Dictionary) -> void:
	var world: Dictionary = _world(setup)
	var engine = world["engine"]
	var inv = engine.get("_o2_room_inventory")
	var room = world["rooms"][0]
	var other = world["rooms"][1] if (world["rooms"] as Array).size() > 1 else null
	var dt: float = float(setup["dt"])
	var file: FileAccess = null
	if _out_dir != "":
		file = FileAccess.open(_out_dir.path_join(name.replace(" ", "_") + ".jsonl"), FileAccess.WRITE)
	var injected: Dictionary = {}
	var rows: int = 0
	for index: int in range(int(setup["steps"])):
		if str(engine.get("o2_room_inventory_failure")) != "":
			break
		# The declared operation of the owner, between two steps, once.
		if setup.has("at_s") and injected.is_empty() and engine.sim_time_s >= float(setup["at_s"]) - 1.0e-9 and inv != null and other != null:
			injected = _inject(inv, room, other, setup)
			injected["at_s"] = engine.sim_time_s
		var before: Dictionary = _state(engine, room)
		engine.step(dt)
		var row: Dictionary = _row(engine, room, before, dt)
		rows += 1
		if file != null:
			file.store_line(JSON.stringify(row, "", true, true))
	if file != null:
		file.close()
	var report: Dictionary = engine.call("get_o2_room_inventory_report")
	_summaries[name] = {
		"setup": setup, "steps_run": rows, "time_s": engine.sim_time_s, "injected": injected,
		"failure": str(engine.get("o2_room_inventory_failure")), "rejections": report.get("rejections", []),
		"totals_of_the_room": report.get("rooms", {}).get(0, {}),
		"heat_MJ": room.hrr_kj_total / 1000.0, "fuel_MJ": room.fuel_consumed_MJ_total,
		"flashover": room.flashover_triggered, "flashover_time_s": room.flashover_time_s,
	}
	engine.queue_free()
	world["building"].queue_free()


## One operation of the owner, declared by the case. Returns what it was and what the owner answered.
func _inject(inv, room, other, setup: Dictionary) -> Dictionary:
	var held: float = float(room.get("o2_inventory_kg"))
	if setup.has("move_fraction"):
		var moved: float = held * float(setup["move_fraction"])
		return {"operation": "exchange_between_rooms, no delay: the room that burns gives", "kg": moved,
			"answer": inv.exchange_between_rooms(room, other, moved, 0.0, 0.0, "fixture_drop")}
	if setup.has("arrival_kg"):
		return {"operation": "exchange_between_rooms, delayed: the neighbour gives to the room that burns", "kg": float(setup["arrival_kg"]),
			"delay_s": float(setup["delay_s"]),
			"answer": inv.exchange_between_rooms(other, room, float(setup["arrival_kg"]), 0.0, float(setup["delay_s"]), "fixture_pending_arrival")}
	if setup.has("owe_all_but_kg"):
		var owed: float = held - float(setup["owe_all_but_kg"])
		return {"operation": "exchange_between_rooms, delayed: the neighbour is credited at once and the room that burns owes", "kg": owed,
			"delay_s": float(setup["delay_s"]),
			"answer": inv.exchange_between_rooms(other, room, 0.0, owed, float(setup["delay_s"]), "fixture_obligation")}
	return {}


## What the room and its owner show before a step.
func _state(engine, room) -> Dictionary:
	var report: Dictionary = engine.call("get_o2_room_inventory_report")
	var owed: float = 0.0
	var pending_in: float = 0.0
	for entry: Dictionary in report.get("transit", []):
		if int(entry["receiver"]) == room.id:
			owed -= minf(0.0, float(entry["net_kg"]))
			pending_in += maxf(0.0, float(entry["net_kg"]))
	return {"m": float(room.get("o2_inventory_kg")), "owed": owed, "pending_in": pending_in,
		"heat_kj": room.hrr_kj_total, "fuel_MJ": room.fuel_consumed_MJ_total, "co_kg": room.co_generated_kg_total,
		"smoke_kg": room.smoke_generated_kg_total, "power_kw": room.hrr_kw, "pool_MJ": room.retained_unburned_MJ,
		"flashover": room.flashover_triggered}


## One row: what the step did, read from the state and from the record of the owner.
func _row(engine, room, before: Dictionary, dt: float) -> Dictionary:
	var report: Dictionary = engine.call("get_o2_room_inventory_report")
	var requested: float = 0.0
	var applied: float = 0.0
	var clipped: float = 0.0
	var debits: int = 0
	var arrived: float = 0.0
	var infiltration: float = 0.0
	var interior: float = 0.0
	for operation: Dictionary in report.get("step_operations", []):
		match String(operation.get("kind", "")):
			"consume":
				if int(operation["room"]) == room.id:
					requested += float(operation["requested_kg"])
					applied += float(operation["applied_kg"])
					clipped += float(operation["clipped_kg"])
					debits += 1
			"arrival":
				if int(operation["room"]) == room.id:
					arrived += float(operation["net_kg"])
			"outside":
				if int(operation["room"]) == room.id:
					infiltration += float(operation["in_kg"]) - float(operation["out_kg"])
			"interior":
				if int(operation["donor"]) == room.id:
					interior += float(operation["to_donor_kg"]) - float(operation["to_receiver_kg"])
				elif int(operation["receiver"]) == room.id and not bool(operation["delayed"]):
					interior += float(operation["to_receiver_kg"]) - float(operation["to_donor_kg"])
	var selection: Dictionary = report.get("selections", {}).get(room.id, {})
	return {
		"t": engine.sim_time_s, "dt": dt, "failure": str(engine.get("o2_room_inventory_failure")),
		# The fire: what it proposed and what it kept.
		"target_kw": room.hrr_target_kw, "flame_target_kw": room.flame_hrr_target_kw, "smolder_target_kw": room.smolder_hrr_target_kw,
		"pool_release_target_kw": room.pool_release_hrr_target_kw, "pyrolysis_kw": room.pyrolysis_kw,
		"power_before_kw": before["power_kw"], "power_kw": room.hrr_kw,
		"heat_accounted_MJ": (room.hrr_kj_total - float(before["heat_kj"])) / 1000.0,
		"o2_factor": room.o2_hrr_factor, "fire_read": room.fire_o2_ref, "fire_reads": str(room.fire_o2_mode_used),
		"burning": room.fire != null, "flashover": room.flashover_triggered, "flashover_in_this_step": room.flashover_triggered and not bool(before["flashover"]),
		# Fuel and products of the step.
		"fuel_MJ": room.fuel_consumed_MJ_total - float(before["fuel_MJ"]), "co_kg": room.co_generated_kg_total - float(before["co_kg"]),
		"co2_kg": room.co2_generated_kg_step, "smoke_kg": room.smoke_generated_kg_total - float(before["smoke_kg"]),
		"smoke_rate_kg_s": room.smoke_prod_kg_s, "pool_MJ": room.retained_unburned_MJ, "pool_before_MJ": before["pool_MJ"],
		# The oxygen of the step.
		"m_before_kg": before["m"], "m_kg": float(room.get("o2_inventory_kg")), "owed_before_kg": before["owed"],
		"pending_in_before_kg": before["pending_in"], "requested_kg": requested, "applied_kg": applied, "clipped_kg": clipped,
		"debits": debits, "arrived_kg": arrived, "infiltration_kg": infiltration, "interior_kg": interior,
		"selection_x": selection.get("mole_fraction"), "selection_m_kg": selection.get("inventory_kg"),
		"selection_available_kg": selection.get("available_kg"), "selection_obligations_kg": selection.get("obligations_kg"),
		"selection_served_to": selection.get("served_to"), "x": room.o2,
	}


func _world(setup: Dictionary) -> Dictionary:
	# The building enters the tree first: its `_ready` loads the product preset and
	# would replace a template loaded before it.
	var building = BuildingModelScript.new()
	root.add_child(building)
	var specs: Array = [ROOM_A, ROOM_B] if int(setup["rooms"]) == 2 else [ROOM_SMALL if bool(setup.get("small", false)) else ROOM_A]
	var fire: Dictionary = setup["fire"]
	var rooms: Array = []
	var rects: Dictionary = {}
	for spec: Dictionary in specs:
		var burning: bool = int(spec["id"]) == 0
		var room: Dictionary = {
			"id": int(spec["id"]), "name": "Sala%d" % int(spec["id"]), "kind": "salon" if burning else "pasillo",
			"floor_level_z_m": 0.0, "height_m": float(spec["h"]), "rotation_deg": 0.0,
			"fuel_energy_MJ": 0.0, "max_hrr_kw": 0.0, "fuel_objects": [],
		}
		if burning:
			room["fuel_energy_MJ"] = float(fire["fuel_MJ"])
			room["max_hrr_kw"] = float(fire["max_hrr_kw"])
			room["fuel_objects"] = [{
				"id": "object", "kind": "mobiliario_tapizado", "name": "Object",
				"fuel_energy_MJ": float(fire["fuel_MJ"]), "remaining_fuel_MJ": float(fire["fuel_MJ"]), "max_hrr_kw": float(fire["max_hrr_kw"]),
				"co_yield_kg_per_MJ": 0.0004, "smoke_yield_kg_per_MJ": 0.012,
				"o2_consumption_kg_per_MJ": 0.076, "elevation_m": 0.38,
				"exposed_area_m2": 3.6, "footprint_m2": 2.1, "ignition_flux_kw_m2": 16.0,
				"ignition_temp_c": 310.0, "is_primary_ignition_source": true,
				"position_m": {"x": 1.0, "y": 1.2}, "size_m": {"x": 0.9, "y": 2.35},
				"room_id": 0, "rotation_deg": 0.0,
			}]
		rooms.append(room)
		rects[str(int(spec["id"]))] = {"x": float(spec["x"]), "y": 0.0, "w": float(spec["w"]), "h": float(spec["l"])}
	var openings: Array = []
	if bool(setup["door"]):
		openings.append({"a": 0, "b": 1, "type": "door", "width_m": 0.9, "height_m": 2.0, "sill_m": 0.0, "offset_m": 0.5,
			"offset_is_fraction": true, "open_fraction": 1.0, "wall": "", "hinge_side": "left", "swing_direction": "in"})
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
	engine.sim_fixed_dt = float(setup["dt"])
	if setup.has("alpha"):
		engine.fire_alpha_kw_s2 = float(setup["alpha"])
	if bool(setup.get("no_secondary_gain", false)):
		engine.fire_secondary_hrr_gain_kw = 0.0
	if bool(setup.get("prescribed", false)):
		# The engine's own switch for a fire that follows its curve and ignores the oxygen limitation.
		engine.fire_o2_independent = true
	engine.set("o2_room_inventory_enabled", true)
	engine.suppress_exit_graphs()
	root.add_child(engine)
	engine.reset_simulation(0, true)
	var models: Array = []
	for spec: Dictionary in specs:
		models.append(building.get_room(int(spec["id"])))
	return {"engine": engine, "building": building, "rooms": models}

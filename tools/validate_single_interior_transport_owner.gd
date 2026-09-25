extends SceneTree
## P3: un unico propietario del gas que cruza una abertura interior.
##
## Con `pressure_network_solver_enabled = true` la red mueve masa, entalpia y
## especies por las aberturas en los dos sentidos. ThermalSystem aplicaba OTRA
## VEZ la salida de la capa caliente por la misma abertura (mecanismo
## `canonical_doorway_upper`): medido en dos salas con la puerta abierta, 24,77 kg
## y 1 627 kJ en 808 pasos, siempre en el mismo paso que la red y en el mismo
## sentido. Ademas, la siembra de capa alta por radiacion creaba masa sin donante
## (1,4385 kg en un paso) porque con la red nada la reconcilia.
##
## Este validador fija:
##   O1  ON, puerta abierta: ningun evento de gas del termico por aberturas
##       interiores y cada sala cierra dM = red neta a 1e-9 kg en cada paso;
##   O2  ON, hueco vertical: idem;
##   O3  ON, puerta cerrada: sin transporte y masa de cada sala constante;
##   O4  OFF, puerta abierta: la ruta historica SIGUE moviendo gas por el
##       termico (el cambio no toca la red apagada) y su huella IEEE754 es la
##       de antes del cambio;
##   O5  ON, siembra por radiacion en una sala sin capa alta: la masa del
##       edificio no cambia;
##   O5b ON, la siembra es UN paquete de la capa baja: masa, entalpia, CO, CO2,
##       HCN y O2 con la composicion de la capa baja (P3b);
##   O6  los cinco escenarios distribuidos del ambito G0: red, D1, D2, D3 y R3
##       apagados;
##   O7  ON, control sin radiacion: nada se siembra ni cambia de capa.

const BuildingModelScript := preload("res://sim/BuildingModel.gd")
const SimulationEngineScript := preload("res://sim/core/SimulationEngine.gd")
const DT_S: float = 1.0 / 12.0
const MASS_TOL_KG: float = 1.0e-9
const GAS_MECHANISMS: Array[String] = [
	"canonical_doorway_upper", "canonical_doorway_lower", "doorway_thermal_counterflow",
]
## Huella de O4: identidad de la ruta con la red apagada. Si cambia, esa ruta
## ha cambiado. P3 la fijo en 4f375edf... (HEAD 8a8e205b) y P3/P3b la dejaron
## intacta. La fase "ruta normal" (2026-09-25) la cambia a proposito: el acarreo
## de gas caliente ya no saca CO2 de la capa baja del origen. Medido antes y
## despues: solo cambian co2_kg y co2_upper_kg (y FED por V_CO2); masa, energia,
## temperaturas, O2, CO, HCN, humo y HRR son identicos bit a bit
## (docs/validation/RUTA_NORMAL_CO2_ACARREO_CAPA_2026-09-25.md).
const OFF_FINGERPRINT: String = "a5ec9b8d65827be06ac2c59171ba92ddb7e7afbee5bd82ccab80836406af04c8"

var _failures: Array[String] = []
var _checks: int = 0


func _initialize() -> void:
	_o1_open_door_on()
	_o2_vertical_hole_on()
	_o3_closed_door_on()
	_o4_open_door_off()
	_o5_radiation_seed_on()
	_o6_ordinary_scenario_switches()
	_o7_no_radiation_control_on()
	if _failures.is_empty():
		print("  %d checks" % _checks)
		print("SINGLE INTERIOR TRANSPORT OWNER VALIDATION PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
		print("FAIL: " + failure)
	print("SINGLE INTERIOR TRANSPORT OWNER VALIDATION FAIL (%d)" % _failures.size())
	quit(1)


# ---------------------------------------------------------------- helpers

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _room(id: int, name: String, z: float, fuel: bool) -> Dictionary:
	var r: Dictionary = {
		"id": id, "name": name, "kind": "salon" if fuel else "pasillo",
		"floor_level_z_m": z, "height_m": 2.4, "rotation_deg": 0.0,
		"fuel_energy_MJ": 0.0, "max_hrr_kw": 0.0, "fuel_objects": [],
	}
	if fuel:
		r["fuel_energy_MJ"] = 1100.0
		r["max_hrr_kw"] = 700.0
		r["fuel_objects"] = [{
			"id": "sofa", "kind": "mobiliario_tapizado", "name": "Sofa",
			"fuel_energy_MJ": 1100.0, "remaining_fuel_MJ": 1100.0, "max_hrr_kw": 700.0,
			"co_yield_kg_per_MJ": 0.0004, "smoke_yield_kg_per_MJ": 0.012,
			"o2_consumption_kg_per_MJ": 0.076, "elevation_m": 0.38,
			"exposed_area_m2": 3.6, "footprint_m2": 2.1, "ignition_flux_kw_m2": 16.0,
			"ignition_temp_c": 310.0, "is_primary_ignition_source": true,
			"position_m": {"x": 1.0, "y": 1.2}, "size_m": {"x": 0.9, "y": 2.35},
			"room_id": id, "rotation_deg": 0.0,
		}]
	return r


## Dos salas a la misma cota con una puerta, o dos plantas con un hueco.
func _template(layout: String, door_open: bool, fire: bool) -> Dictionary:
	var floors: Array = [{"level_m": 0.0, "name": "PB"}]
	var rooms: Array = []
	var rects: Dictionary = {}
	var openings: Array = []
	if layout == "vertical":
		floors.append({"level_m": 2.4, "name": "P1"})
		rooms.append(_room(0, "Bajo", 0.0, fire))
		rooms.append(_room(1, "Alto", 2.4, false))
		rects["0"] = {"x": 0.0, "y": 0.0, "w": 4.0, "h": 4.0}
		rects["1"] = {"x": 0.0, "y": 0.0, "w": 4.0, "h": 4.0}
		openings.append({"a": 0, "b": 1, "type": "hole", "is_vertical": true,
			"width_m": 1.2, "height_m": 2.4, "sill_m": 0.0, "offset_m": 0.0,
			"offset_is_fraction": true, "open_fraction": 1.0, "wall": "",
			"hinge_side": "left", "swing_direction": "in"})
	else:
		rooms.append(_room(0, "Salon", 0.0, fire))
		rooms.append(_room(1, "Pasillo", 0.0, false))
		rects["0"] = {"x": 0.0, "y": 0.0, "w": 5.0, "h": 4.0}
		rects["1"] = {"x": 5.0, "y": 0.0, "w": 4.0, "h": 4.0}
		openings.append({"a": 0, "b": 1, "type": "door", "width_m": 0.9, "height_m": 2.0,
			"sill_m": 0.0, "offset_m": 0.5, "offset_is_fraction": true,
			"open_fraction": 1.0 if door_open else 0.0, "wall": "",
			"hinge_side": "left", "swing_direction": "in"})
	return {
		"building_type": "house", "floors": floors, "rooms_data": rooms,
		"room_rect_m": rects, "openings_data": openings, "ignition_room_id": 0,
		"hvac_mode": "none",
	}


func _engine(template: Dictionary, network_on: bool, ignite: bool) -> SimulationEngine:
	var building: BuildingModel = BuildingModelScript.new()
	building.load_template_data(template)
	var engine: SimulationEngine = SimulationEngineScript.new()
	engine.building = building
	engine.auto_ignite_on_ready = false
	engine.auto_finish_on_extinction = false
	engine.enable_logging = false
	engine.enable_csv_log = false
	engine.pressure_network_solver_enabled = network_on
	# Libro pasivo de propietarios: solo anota, no cambia la fisica.
	engine.phase3_runtime_ownership_ledger_enabled = true
	engine.suppress_exit_graphs()
	root.add_child(building)
	root.add_child(engine)
	engine.reset_simulation(0, ignite)
	return engine


func _dispose(engine: SimulationEngine) -> void:
	var building = engine.building
	engine.queue_free()
	building.queue_free()


func _room_mass_kg(room) -> float:
	return room.upper_gas_kg + room.lower_gas_kg


func _building_mass_kg(engine: SimulationEngine) -> float:
	var total: float = 0.0
	for rid in engine.building.get_rooms().keys():
		total += _room_mass_kg(engine.building.get_room(rid))
	return total


## Masa neta que la red ha puesto en cada sala en el ULTIMO paso.
func _network_net_kg(engine: SimulationEngine) -> Dictionary:
	var net: Dictionary = {}
	var tx: Dictionary = engine.pressure_network_last_result.get("transaction", {})
	for route in tx.get("routes", []):
		var mass_kg: float = float(route["bundle"]["mass_kg"])
		var src: String = String(route["source_room_id"])
		var dst: String = String(route["destination_room_id"])
		if src != "outside":
			net[int(src)] = float(net.get(int(src), 0.0)) - mass_kg
		if dst != "outside":
			net[int(dst)] = float(net.get(int(dst), 0.0)) + mass_kg
	return net


func _thermal_gas_events(engine: SimulationEngine) -> int:
	var count: int = 0
	for event in engine._phase3_runtime_ownership_thermal_events:
		if GAS_MECHANISMS.has(String(event.get("mechanism", ""))) \
				and absf(float(event.get("source_mass_delta_kg", 0.0))) > 0.0:
			count += 1
	return count


## Corre `steps` pasos con la red ON y devuelve [eventos termicos de gas,
## peor residuo por sala y paso, pasos en los que la red movio gas].
func _run_on(engine: SimulationEngine, steps: int) -> Array:
	var events: int = 0
	var worst_kg: float = 0.0
	var network_steps: int = 0
	var before: Dictionary = {}
	for rid in engine.building.get_rooms().keys():
		before[rid] = _room_mass_kg(engine.building.get_room(rid))
	for _i in range(steps):
		engine.step(DT_S)
		events += _thermal_gas_events(engine)
		var net: Dictionary = _network_net_kg(engine)
		if not net.is_empty():
			network_steps += 1
		for rid in engine.building.get_rooms().keys():
			var mass_kg: float = _room_mass_kg(engine.building.get_room(rid))
			var residual: float = mass_kg - float(before[rid]) - float(net.get(int(rid), 0.0))
			worst_kg = maxf(worst_kg, absf(residual))
			before[rid] = mass_kg
	return [events, worst_kg, network_steps]


# ---------------------------------------------------------------- O1..O6

func _o1_open_door_on() -> void:
	var engine := _engine(_template("door", true, true), true, true)
	var mass0: float = _building_mass_kg(engine)
	var result: Array = _run_on(engine, 720)
	_check(String(engine.pressure_network_failure).is_empty(),
			"O1 the network applied every step (%s)" % engine.pressure_network_failure)
	_check(int(result[2]) > 0, "O1 the network moved gas through the door")
	_check(int(result[0]) == 0,
			"O1 ON: ThermalSystem moved gas through an interior opening %d times" % int(result[0]))
	_check(float(result[1]) <= MASS_TOL_KG,
			"O1 ON: a room changed by %s kg that the network did not move" % str(float(result[1])))
	_check(absf(_building_mass_kg(engine) - mass0) <= MASS_TOL_KG,
			"O1 ON: building mass %.12f vs %.12f kg" % [_building_mass_kg(engine), mass0])
	_dispose(engine)


func _o2_vertical_hole_on() -> void:
	var engine := _engine(_template("vertical", true, true), true, true)
	var result: Array = _run_on(engine, 480)
	_check(int(result[2]) > 0, "O2 the network moved gas through the hole")
	_check(int(result[0]) == 0,
			"O2 ON: ThermalSystem moved gas through a vertical hole %d times" % int(result[0]))
	_check(float(result[1]) <= MASS_TOL_KG,
			"O2 ON: a room changed by %s kg that the network did not move" % str(float(result[1])))
	_dispose(engine)


func _o3_closed_door_on() -> void:
	var engine := _engine(_template("door", false, true), true, true)
	var result: Array = _run_on(engine, 360)
	_check(int(result[0]) == 0, "O3 closed door: thermal gas events %d" % int(result[0]))
	_check(float(result[1]) <= MASS_TOL_KG,
			"O3 closed door: room mass residual %s kg" % str(float(result[1])))
	_dispose(engine)


func _o4_open_door_off() -> void:
	var engine := _engine(_template("door", true, true), false, true)
	# Con la red apagada la capa caliente tarda mas en alcanzar el dintel: el
	# primer transporte termico por la puerta llega hacia el paso 920.
	var events: int = 0
	for _i in range(1200):
		engine.step(DT_S)
		events += _thermal_gas_events(engine)
	_check(events > 0,
			"O4 OFF: the historical route no longer moves gas through the door (%d)" % events)
	var bits := PackedFloat64Array()
	for rid in engine.building.get_rooms().keys():
		var room = engine.building.get_room(rid)
		for value in [room.upper_gas_kg, room.lower_gas_kg, room.upper_energy_kj,
				room.lower_energy_kj, room.temp_upper_c, room.temp_lower_c, room.o2,
				room.o2_upper, room.o2_lower, room.co_kg, room.co2_kg, room.hcn_kg,
				room.smoke_kg, room.hrr_kw, room.overpressure_pa,
				room.two_zone_boundary_mass_kg]:
			bits.append(float(value))
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(bits.to_byte_array())
	var fingerprint: String = ctx.finish().hex_encode()
	print("  O4 OFF fingerprint %s (thermal gas events %d)" % [fingerprint, events])
	_check(fingerprint == OFF_FINGERPRINT,
			"O4 OFF: state fingerprint %s differs from the pinned OFF route %s" % [
				fingerprint, OFF_FINGERPRINT])
	_dispose(engine)


## Sala sin capa alta frente a una capa caliente: la radiacion por la puerta
## necesita sembrarla. Con la red, sin fuego y en un solo paso, la masa del
## edificio no puede cambiar. (La sala fria, quiescente, puede colapsar la capa
## sembrada en los clamps finales: por eso se juzga la masa, no la capa.)
func _o5_radiation_seed_on() -> void:
	var engine := _engine(_template("door", true, false), true, false)
	var hot = engine.building.get_room(0)
	var cold = engine.building.get_room(1)
	var total_hot_kg: float = _room_mass_kg(hot)
	hot.upper_gas_kg = total_hot_kg * 0.3
	hot.lower_gas_kg = total_hot_kg - hot.upper_gas_kg
	hot.upper_energy_kj = hot.upper_gas_kg * 380.0
	hot.temp_upper_c = 400.0
	cold.upper_gas_kg = 0.0
	cold.upper_energy_kj = 0.0
	var mass0: float = _building_mass_kg(engine)
	engine.step(DT_S)
	_check(absf(_building_mass_kg(engine) - mass0) <= MASS_TOL_KG,
			"O5 ON: the radiation seed changed the building mass by %s kg"
			% str(_building_mass_kg(engine) - mass0))
	_dispose(engine)
	_o5b_seed_is_one_packet()


## Estado de una sala receptora sin capa alta con especies en su capa baja y un
## O2 alto rancio (0,0): el estado medido en la casa P3 justo antes de la
## siembra. Se llama SOLO a la radiacion por aberturas, sin el resto del paso.
func _seeded_pair(radiation_on: bool) -> SimulationEngine:
	var engine := _engine(_template("door", true, false), true, false)
	var hot = engine.building.get_room(0)
	var cold = engine.building.get_room(1)
	hot.upper_gas_kg = 13.55
	hot.lower_gas_kg = 39.94
	hot.upper_energy_kj = 2441.24
	hot.temp_upper_c = 200.16
	cold.upper_gas_kg = 0.0
	cold.lower_gas_kg = 50.1794
	cold.upper_energy_kj = 0.0
	cold.lower_energy_kj = 998.18
	cold.temp_upper_c = 39.89
	cold.temp_lower_c = 39.89
	cold.co_kg = 0.00102
	cold.co_upper_kg = 0.0
	cold.co2_kg = 0.21436
	cold.co2_upper_kg = 0.0
	cold.hcn_kg = 0.000102
	cold.hcn_upper_kg = 0.0
	cold.o2_upper = 0.0
	cold.o2_lower = 0.20514
	engine.thermal_system.radiation_opening_enabled = radiation_on
	engine.thermal_system._step_radiation_openings(
		engine.building, DT_S, engine.thermal_system.ambient_temp_c())
	return engine


func _o5b_seed_is_one_packet() -> void:
	var engine := _seeded_pair(true)
	var cold = engine.building.get_room(1)
	var hot = engine.building.get_room(0)
	var lower_before_kg: float = 50.1794
	var moved_kg: float = lower_before_kg - cold.lower_gas_kg
	_check(moved_kg > 0.0 and absf(cold.upper_gas_kg - moved_kg) <= MASS_TOL_KG,
			"O5b the seed moved %s kg from the lower layer into an upper layer of %s kg"
			% [str(moved_kg), str(cold.upper_gas_kg)])
	var share: float = moved_kg / lower_before_kg
	var totals: Dictionary = {"co": 0.00102, "co2": 0.21436, "hcn": 0.000102}
	for species in totals.keys():
		var total_kg: float = float(totals[species])
		var upper_kg: float = float(cold.get("%s_upper_kg" % species))
		_check(absf(float(cold.get("%s_kg" % species)) - total_kg) <= 1.0e-15,
				"O5b %s room total changed" % species)
		_check(absf(upper_kg - total_kg * share) <= 1.0e-12 * maxf(1.0, total_kg),
				"O5b %s did not travel with the gas: upper %s kg, packet %s kg"
				% [species, str(upper_kg), str(total_kg * share)])
	# O2 en la convencion masa-fraccion de la red: el paquete lleva la del
	# donante y el total de la sala no cambia.
	_check(absf(cold.o2_upper - 0.20514) <= 1.0e-12,
			"O5b the seeded layer has O2 fraction %s, the donor %s" % [str(cold.o2_upper), "0.20514"])
	var o2_after_kg: float = cold.o2_upper * cold.upper_gas_kg + cold.o2_lower * cold.lower_gas_kg
	_check(absf(o2_after_kg - 0.20514 * lower_before_kg) <= 1.0e-12,
			"O5b the seed changed the room O2 (x*m) by %s kg" % str(o2_after_kg - 0.20514 * lower_before_kg))
	# Entalpia: la especifica de la capa baja viaja con el gas; lo demas que
	# gana la sala es exactamente lo que irradia la fuente.
	var radiated_kj: float = 2441.24 - hot.upper_energy_kj
	var room_energy_gain_kj: float = cold.upper_energy_kj + cold.lower_energy_kj - 998.18
	_check(absf(room_energy_gain_kj - radiated_kj) <= 1.0e-9,
			"O5b room energy gain %s kJ vs radiated %s kJ" % [str(room_energy_gain_kj), str(radiated_kj)])
	_check(absf((cold.upper_energy_kj - radiated_kj) - moved_kg * 998.18 / lower_before_kg) <= 1.0e-9,
			"O5b the packet did not carry the lower-layer specific enthalpy")
	_dispose(engine)


func _o6_ordinary_scenario_switches() -> void:
	for scenario in ["compact_apartment_reference", "preset_simple_house",
			"long_hallway_reference", "preset_two_storey_house", "two_storey_reference"]:
		var text: String = FileAccess.get_file_as_string("res://scenarios/%s.json" % scenario)
		var data: Variant = JSON.parse_string(text)
		_check(typeof(data) == TYPE_DICTIONARY, "O6 %s loads" % scenario)
		if typeof(data) != TYPE_DICTIONARY:
			continue
		var building: BuildingModel = BuildingModelScript.new()
		building.load_template_data(data)
		var engine: SimulationEngine = SimulationEngineScript.new()
		engine.building = building
		engine.auto_ignite_on_ready = false
		engine.auto_finish_on_extinction = false
		engine.enable_logging = false
		engine.enable_csv_log = false
		engine.suppress_exit_graphs()
		root.add_child(building)
		root.add_child(engine)
		engine.reset_simulation(int(data.get("ignition_room_id", 0)), false)
		engine.step(DT_S)
		_check(not engine.pressure_network_solver_enabled, "O6 %s: the network is off" % scenario)
		_check(not engine.closed_door_leakage_enabled, "O6 %s: D1 is off" % scenario)
		_check(not engine.closed_door_deformation_enabled, "O6 %s: D2 is off" % scenario)
		_check(not engine.glazing_fallout_enabled, "O6 %s: D3 is off" % scenario)
		_check(not engine.exterior_envelope_leakage_enabled, "O6 %s: R3 is off" % scenario)
		_check(not engine.thermal_system.authoritative_transport_enabled,
				"O6 %s: ThermalSystem keeps the historical interior transport" % scenario)
		engine.queue_free()
		building.queue_free()


## Control: el mismo estado sin radiacion por aberturas no siembra nada ni
## cambia especies u O2 de capa.
func _o7_no_radiation_control_on() -> void:
	var engine := _seeded_pair(false)
	var cold = engine.building.get_room(1)
	_check(cold.upper_gas_kg == 0.0 and cold.lower_gas_kg == 50.1794,
			"O7 without radiation the cold room still changed its layers")
	_check(cold.co2_upper_kg == 0.0 and cold.o2_upper == 0.0,
			"O7 without radiation species or O2 changed layer")
	_dispose(engine)

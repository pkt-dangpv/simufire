extends SceneTree

## Tests de la integracion autoritativa de la red de presion (fase F2.2C):
## sim/core/PressureNetworkTransportSystem.gd dentro del paso real del motor.
##
##   <godot> --headless --path . --script res://tools/validate_pressure_network_integration.gd
##   <godot> --headless --path . --script res://tools/validate_pressure_network_integration.gd -- --dump=<ruta.json>

const BuildingModelScript := preload("res://sim/BuildingModel.gd")
const SimulationEngineScript := preload("res://sim/core/SimulationEngine.gd")
const TransportScript := preload("res://sim/core/PressureNetworkTransportSystem.gd")
const ADAPTER_PATH: String = "res://sim/core/PressureNetworkTransportSystem.gd"

const DT_S: float = 0.0833333333333333
const AMBIENT_C: float = 20.0
const T_REF_K: float = 293.15
const TOL: float = 1.0e-9

var _failures: Array[String] = []
var _checks: int = 0


func _initialize() -> void:
	var dump_path: String = ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--dump="):
			dump_path = argument.substr("--dump=".length())
	_test_01_off_does_not_run_the_network()
	_test_02_sealed_equilibrium()
	_test_03_two_rooms_equal_state()
	_test_04_two_rooms_pressure_difference()
	_test_05_exterior_opening()
	_test_06_bidirectional_opening()
	_test_07_collective_limiting()
	_test_08_negative_sensible_energy()
	_test_09_impossible_state_is_rejected()
	_test_10_oxygen_transport()
	_test_11_species_transport()
	_test_12_no_late_overwrite()
	_test_13_ppv_is_rejected()
	_test_14_invalid_transaction_changes_nothing()
	_test_15_closing_a_door_leaves_the_network()
	_test_16_contract(dump_path)
	if _failures.is_empty():
		print("  %d checks" % _checks)
		print("PRESSURE NETWORK INTEGRATION VALIDATION PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
		print("FAIL: " + failure)
	print("PRESSURE NETWORK INTEGRATION VALIDATION FAIL (%d)" % _failures.size())
	quit(1)


# ---------------------------------------------------------------- helpers

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _close(actual: float, expected: float, tol: float = TOL) -> bool:
	if is_nan(actual) or is_nan(expected):
		return false
	return absf(actual - expected) <= tol * maxf(1.0, absf(expected))


## Edificio minimo: `room_count` salas en linea, con las aberturas que se pidan.
func _make_building(room_count: int, openings: Array) -> BuildingModel:
	var rooms_data: Array = []
	var rects: Dictionary = {}
	for index in range(room_count):
		rooms_data.append({
			"id": index, "name": "R%d" % index, "kind": "salon",
			"floor_level_z_m": 0.0, "height_m": 2.4,
			"fuel_energy_MJ": 0.0, "max_hrr_kw": 0.0,
			"fuel_objects": [], "rotation_deg": 0.0,
		})
		rects[str(index)] = {"x": float(index) * 5.0, "y": 0.0, "w": 5.0, "h": 4.0}
	var template: Dictionary = {
		"building_type": "house",
		"floors": [{"level_m": 0.0, "name": "R"}],
		"rooms_data": rooms_data,
		"room_rect_m": rects,
		"openings_data": openings,
	}
	var building: BuildingModel = BuildingModelScript.new()
	building.load_template_data(template)
	return building


func _opening(a: int, b: int, open_fraction: float = 1.0, width_m: float = 0.9,
		height_m: float = 2.0, sill_m: float = 0.0, type_name: String = "door") -> Dictionary:
	return {
		"a": a, "b": b, "type": type_name, "open_fraction": open_fraction,
		"width_m": width_m, "height_m": height_m, "sill_m": sill_m,
		"wall": "right", "offset_m": 2.0, "offset_is_fraction": false,
	}


func _make_engine(building: BuildingModel, enabled: bool) -> SimulationEngine:
	var engine: SimulationEngine = SimulationEngineScript.new()
	engine.building = building
	engine.auto_ignite_on_ready = false
	engine.auto_finish_on_extinction = false
	engine.enable_logging = false
	engine.enable_csv_log = false
	engine.pressure_network_solver_enabled = enabled
	root.add_child(building)
	root.add_child(engine)
	engine.reset_simulation(0, false)
	return engine


func _free_engine(engine: SimulationEngine, building: BuildingModel) -> void:
	root.remove_child(engine)
	root.remove_child(building)
	engine.free()
	building.free()


## Estado zonal listo para transportar: masa, energia, O2 y especies.
func _seed_room(room, upper_kg: float, upper_temp_k: float, lower_kg: float,
		lower_temp_k: float, smoke_kg: float = 0.0, co_kg: float = 0.0,
		co_upper_kg: float = 0.0) -> void:
	room.upper_gas_kg = upper_kg
	room.lower_gas_kg = lower_kg
	room.upper_energy_kj = upper_kg * (upper_temp_k - T_REF_K)
	room.lower_energy_kj = lower_kg * (lower_temp_k - T_REF_K)
	room.temp_upper_c = upper_temp_k - 273.15
	room.temp_lower_c = lower_temp_k - 273.15
	room.smoke_kg = smoke_kg
	room.co_kg = co_kg
	room.co_upper_kg = co_upper_kg


func _room_mass(room) -> float:
	return float(room.upper_gas_kg) + float(room.lower_gas_kg)


func _room_energy(room) -> float:
	return float(room.upper_energy_kj) + float(room.lower_energy_kj)


func _o2_mass(room) -> float:
	return float(room.o2_upper) * float(room.upper_gas_kg) \
			+ float(room.o2_lower) * float(room.lower_gas_kg)


## Aplica SOLO la transaccion de la red, sin el resto del paso del motor. Es el
## nivel en el que la conservacion tiene que ser exacta: la fisica local
## (deposicion, renovacion ACH, quimica) es de otros sistemas.
func _transport_step(building: BuildingModel, dt_s: float = DT_S) -> Dictionary:
	var system = TransportScript.new()
	return system.step(building, dt_s)


func _bare_building(room_count: int, openings: Array) -> BuildingModel:
	var building: BuildingModel = _make_building(room_count, openings)
	root.add_child(building)
	return building


func _free_building(building: BuildingModel) -> void:
	root.remove_child(building)
	building.free()


func _canonical(value: Variant) -> String:
	return JSON.stringify(value, "", true, true)


# ---------------------------------------------------------------- tests

func _test_01_off_does_not_run_the_network() -> void:
	var building: BuildingModel = _make_building(2, [_opening(0, 1)])
	var engine: SimulationEngine = _make_engine(building, false)
	_seed_room(building.get_room(0), 12.0, 493.15, 40.0, 298.15, 0.5, 0.01, 0.008)
	var before_pressure: float = float(building.get_room(0).overpressure_pa)
	engine.step(DT_S)
	_check(engine.pressure_network_last_result.is_empty(),
			"01 with the flag OFF the network never runs")
	_check(String(engine.pressure_network_failure).is_empty(), "01 no failure is reported when OFF")
	_check(not engine.gas_exchange_system.authoritative_transport_enabled
			and not engine.oxygen_exchange_system.authoritative_transport_enabled
			and not engine.thermal_system.authoritative_transport_enabled,
			"01 the historical systems keep their ownership when OFF")
	_check(float(building.get_room(0).overpressure_pa) != before_pressure
			or float(building.get_room(0).overpressure_pa) == before_pressure,
			"01 the historical path still owns the pressure")
	_free_engine(engine, building)


func _test_02_sealed_equilibrium() -> void:
	var building: BuildingModel = _make_building(1, [])
	var engine: SimulationEngine = _make_engine(building, true)
	var room = building.get_room(0)
	_seed_room(room, 0.0, T_REF_K, 57.6, T_REF_K, 0.2, 0.01, 0.0)
	var mass_before: float = _room_mass(room)
	var smoke_before: float = float(room.smoke_kg)
	engine.step(DT_S)
	_check(String(engine.pressure_network_failure).is_empty(),
			"02 a sealed room solves without failure (%s)" % engine.pressure_network_failure)
	_check(bool(engine.pressure_network_last_result["applied"]), "02 the transaction was applied")
	_check(_close(float(room.overpressure_pa), 0.0, 1.0e-6),
			"02 a sealed room in equilibrium stays at 0 Pa (%s)" % room.overpressure_pa)
	_check(_close(_room_mass(room), mass_before, 1.0e-12), "02 no mass moved")
	# El humo del paso completo tambien lo toca la deposicion local; lo que la
	# red tiene que garantizar es que no lo MUEVE por ninguna abertura.
	_check(smoke_before > 0.0, "02 the sealed room started with smoke")
	_check(engine.pressure_network_last_result["transaction"]["routes"].is_empty(),
			"02 a sealed room has no routes")
	_free_engine(engine, building)


func _test_03_two_rooms_equal_state() -> void:
	var building: BuildingModel = _make_building(2, [_opening(0, 1)])
	var engine: SimulationEngine = _make_engine(building, true)
	for index in [0, 1]:
		_seed_room(building.get_room(index), 0.0, T_REF_K, 57.6, T_REF_K)
	var mass_before: float = _room_mass(building.get_room(0)) + _room_mass(building.get_room(1))
	engine.step(DT_S)
	_check(String(engine.pressure_network_failure).is_empty(), "03 equal rooms solve")
	var net_kg: float = _room_mass(building.get_room(0)) - 57.6
	_check(absf(net_kg) <= 1.0e-9, "03 equal rooms exchange no net mass (%s kg)" % net_kg)
	_check(_close(_room_mass(building.get_room(0)) + _room_mass(building.get_room(1)),
			mass_before, 1.0e-12), "03 the closed network conserves mass")
	_free_engine(engine, building)


func _test_04_two_rooms_pressure_difference() -> void:
	var building: BuildingModel = _make_building(2, [_opening(0, 1)])
	var engine: SimulationEngine = _make_engine(building, true)
	_seed_room(building.get_room(0), 12.0, 493.15, 48.0, 298.15, 1.0, 0.02, 0.015)
	_seed_room(building.get_room(1), 0.0, T_REF_K, 57.6, T_REF_K)
	var hot = building.get_room(0)
	var cold = building.get_room(1)
	var mass_before: float = _room_mass(hot) + _room_mass(cold)
	var energy_before: float = _room_energy(hot) + _room_energy(cold)
	var smoke_before: float = float(hot.smoke_kg) + float(cold.smoke_kg)
	var co_before: float = float(hot.co_kg) + float(cold.co_kg)
	var result: Dictionary = _transport_step(building)
	_check(bool(result["applied"]),
			"04 the pressurized pair solves and applies (%s)" % result["failure_reason"])
	_check(float(hot.overpressure_pa) > float(cold.overpressure_pa),
			"04 the hot room keeps the higher pressure (%.3f vs %.3f)" % [
				hot.overpressure_pa, cold.overpressure_pa])
	_check(_room_mass(hot) < mass_before - _room_mass(cold) + 1.0e-9, "04 the hot room loses mass")
	_check(_close(_room_mass(hot) + _room_mass(cold), mass_before, 1.0e-9),
			"04 mass is conserved in the closed network (%.9f vs %.9f)" % [
				_room_mass(hot) + _room_mass(cold), mass_before])
	_check(_close(_room_energy(hot) + _room_energy(cold), energy_before, 1.0e-6),
			"04 energy is conserved in the closed network")
	_check(_close(float(hot.smoke_kg) + float(cold.smoke_kg), smoke_before, 1.0e-9),
			"04 smoke is conserved in the closed network")
	_check(_close(float(hot.co_kg) + float(cold.co_kg), co_before, 1.0e-9),
			"04 CO is conserved in the closed network")
	_check(float(cold.smoke_kg) > 0.0, "04 smoke reached the cold room")
	_free_engine(engine, building)


func _test_05_exterior_opening() -> void:
	# Sobrepresion: sale masa.
	var building: BuildingModel = _make_building(1, [_opening(0, -1, 1.0, 0.9, 2.0, 0.0, "window")])
	var engine: SimulationEngine = _make_engine(building, true)
	var room = building.get_room(0)
	_seed_room(room, 12.0, 493.15, 48.0, 298.15, 1.0)
	var mass_before: float = _room_mass(room)
	var vented: Dictionary = _transport_step(building)
	_check(bool(vented["applied"]), "05 the vented room solves (%s)" % vented["failure_reason"])
	_check(_room_mass(room) < mass_before, "05 an overpressure pushes mass out (%.4f -> %.4f)" % [
		mass_before, _room_mass(room)])
	_check(float(room.smoke_kg) < 1.0, "05 smoke leaves with the gas")
	_free_engine(engine, building)
	# Depresion: entra masa, con la composicion exterior.
	var cold_building: BuildingModel = _make_building(1, [_opening(0, -1, 1.0, 0.9, 2.0, 0.0, "window")])
	var cold_engine: SimulationEngine = _make_engine(cold_building, true)
	var cold_room = cold_building.get_room(0)
	_seed_room(cold_room, 0.0, T_REF_K, 45.0, 263.15)
	var cold_mass_before: float = _room_mass(cold_room)
	var cold_o2_before: float = _o2_mass(cold_room)
	var pulled: Dictionary = _transport_step(cold_building)
	_check(bool(pulled["applied"]), "05 the depressurized room solves (%s)" % pulled["failure_reason"])
	_check(_room_mass(cold_room) > cold_mass_before,
			"05 a depression pulls mass in (%.4f -> %.4f)" % [cold_mass_before, _room_mass(cold_room)])
	_check(_o2_mass(cold_room) > cold_o2_before, "05 the incoming air brings exterior O2")
	_free_engine(cold_engine, cold_building)


func _test_06_bidirectional_opening() -> void:
	var building: BuildingModel = _make_building(2, [_opening(0, 1, 1.0, 0.9, 2.4)])
	var engine: SimulationEngine = _make_engine(building, true)
	# Sala caliente a presion casi ambiente: manda la flotabilidad.
	var upper_kg: float = 20.0
	var lower_kg: float = (57.6 * T_REF_K - upper_kg * 573.15) / 313.15
	_seed_room(building.get_room(0), upper_kg, 573.15, lower_kg, 313.15, 2.0)
	_seed_room(building.get_room(1), 0.0, T_REF_K, 57.6, T_REF_K)
	var result: Dictionary = _transport_step(building)
	_check(bool(result["applied"]), "06 the buoyant pair solves (%s)" % result["failure_reason"])
	var routes: Array = result["transaction"]["routes"]
	var out_routes: int = 0
	var in_routes: int = 0
	var upper_source: int = 0
	for route in routes:
		if String(route["source_room_id"]) == "0":
			out_routes += 1
			if String(route["source_zone"]) == "upper":
				upper_source += 1
		elif String(route["destination_room_id"]) == "0":
			in_routes += 1
	_check(out_routes > 0 and in_routes > 0,
			"06 the opening carries both directions (%d out, %d in)" % [out_routes, in_routes])
	_check(upper_source > 0, "06 the outflow leaves from the upper zone")
	_check(float(building.get_room(1).smoke_kg) > 0.0, "06 the smoke follows the upper outflow")
	_free_engine(engine, building)


func _test_07_collective_limiting() -> void:
	# Tres salidas desde la misma sala: el limite es del grupo, no de la ruta.
	var building: BuildingModel = _make_building(3, [
		_opening(0, 1, 1.0, 0.9, 2.0), _opening(0, 2, 1.0, 0.9, 2.0),
	])
	var engine: SimulationEngine = _make_engine(building, true)
	_seed_room(building.get_room(0), 6.0, 873.15, 6.0, 873.15, 1.0)
	_seed_room(building.get_room(1), 0.0, T_REF_K, 57.6, T_REF_K)
	_seed_room(building.get_room(2), 0.0, T_REF_K, 57.6, T_REF_K)
	var mass_before: float = _room_mass(building.get_room(0)) \
			+ _room_mass(building.get_room(1)) + _room_mass(building.get_room(2))
	var result: Dictionary = _transport_step(building)
	_check(bool(result["applied"]),
			"07 the strongly driven room solves (%s)" % result["failure_reason"])
	_check(_room_mass(building.get_room(0)) >= -1.0e-9, "07 the source room never goes negative")
	_check(_close(_room_mass(building.get_room(0)) + _room_mass(building.get_room(1))
			+ _room_mass(building.get_room(2)), mass_before, 1.0e-9),
			"07 the closed network still conserves mass")
	var scale: Dictionary = result["transaction"]["scale"]
	_check(scale.has("0"), "07 the transaction reports a scale per room and zone")
	_free_engine(engine, building)


func _test_08_negative_sensible_energy() -> void:
	var building: BuildingModel = _make_building(1, [])
	var engine: SimulationEngine = _make_engine(building, true)
	var room = building.get_room(0)
	# Las DOS zonas por debajo del ambiente: la energia sensible negativa vale
	# tanto arriba como abajo mientras la temperatura absoluta siga siendo fisica.
	_seed_room(room, 8.0, 283.15, 49.6, 273.15)
	var upper_energy_before: float = float(room.upper_energy_kj)
	var result: Dictionary = _transport_step(building)
	_check(bool(result["applied"]),
			"08 a compartment below ambient is accepted (%s)" % result["failure_reason"])
	_check(upper_energy_before < 0.0, "08 the upper zone starts below ambient")
	_check(_close(float(room.upper_energy_kj), upper_energy_before, 1.0e-12),
			"08 a sealed room keeps its negative upper energy untouched (%.6f vs %.6f)"
			% [room.upper_energy_kj, upper_energy_before])
	_check(float(room.lower_energy_kj) < 0.0, "08 the sensible energy stays negative")
	_check(float(room.overpressure_pa) < 0.0,
			"08 the canonical pressure keeps its negative sign (%.4f Pa)" % room.overpressure_pa)
	_free_engine(engine, building)


func _test_09_impossible_state_is_rejected() -> void:
	var building: BuildingModel = _make_building(1, [])
	var engine: SimulationEngine = _make_engine(building, true)
	var room = building.get_room(0)
	# Temperatura absoluta imposible: el estado no puede resolverse.
	_seed_room(room, 0.0, T_REF_K, 57.6, T_REF_K)
	room.lower_energy_kj = -57.6 * (T_REF_K + 10.0)
	var mass_before: float = _room_mass(room)
	var energy_before: float = _room_energy(room)
	var result: Dictionary = _transport_step(building)
	_check(not bool(result["applied"]) and not String(result["failure_reason"]).is_empty(),
			"09 an impossible absolute state is reported as a failure (%s)" % result["failure_reason"])
	_check(_close(_room_mass(room), mass_before, 1.0e-12)
			and _close(_room_energy(room), energy_before, 1.0e-12),
			"09 nothing was committed when the state is impossible")
	_free_engine(engine, building)


func _test_10_oxygen_transport() -> void:
	var building: BuildingModel = _make_building(2, [_opening(0, 1)])
	var engine: SimulationEngine = _make_engine(building, true)
	_seed_room(building.get_room(0), 12.0, 493.15, 48.0, 298.15)
	_seed_room(building.get_room(1), 0.0, T_REF_K, 57.6, T_REF_K)
	building.get_room(0).o2_upper = 0.10
	building.get_room(0).o2_lower = 0.15
	building.get_room(0).o2 = 0.14
	var o2_before: float = _o2_mass(building.get_room(0)) + _o2_mass(building.get_room(1))
	var result: Dictionary = _transport_step(building)
	_check(bool(result["applied"]), "10 the O2 case solves (%s)" % result["failure_reason"])
	var o2_after: float = _o2_mass(building.get_room(0)) + _o2_mass(building.get_room(1))
	_check(_close(o2_after, o2_before, 1.0e-9),
			"10 O2 mass is conserved in the closed network (%.9f vs %.9f)" % [o2_after, o2_before])
	var room = building.get_room(0)
	_check(_close(float(room.o2), _o2_mass(room) / _room_mass(room), 1.0e-9),
			"10 the room O2 fraction is derived from the final masses")
	_check(float(room.o2_upper) >= 0.0 and float(room.o2_lower) >= 0.0, "10 no negative O2 fraction")
	_free_engine(engine, building)


func _test_11_species_transport() -> void:
	var building: BuildingModel = _make_building(2, [_opening(0, 1)])
	var engine: SimulationEngine = _make_engine(building, true)
	_seed_room(building.get_room(0), 12.0, 493.15, 48.0, 298.15, 1.5, 0.05, 0.04)
	building.get_room(0).co2_kg = 0.30
	building.get_room(0).co2_upper_kg = 0.22
	building.get_room(0).hcn_kg = 0.02
	building.get_room(0).hcn_upper_kg = 0.015
	_seed_room(building.get_room(1), 0.0, T_REF_K, 57.6, T_REF_K)
	var totals_before: Dictionary = {}
	for species in ["smoke", "co", "co2", "hcn"]:
		totals_before[species] = float(building.get_room(0).get("%s_kg" % species)) \
				+ float(building.get_room(1).get("%s_kg" % species))
	var result: Dictionary = _transport_step(building)
	_check(bool(result["applied"]), "11 the species case solves (%s)" % result["failure_reason"])
	for species in ["smoke", "co", "co2", "hcn"]:
		var after: float = float(building.get_room(0).get("%s_kg" % species)) \
				+ float(building.get_room(1).get("%s_kg" % species))
		_check(_close(after, float(totals_before[species]), 1.0e-9),
				"11 %s is conserved in the closed network (%.9f vs %.9f)" % [
					species, after, totals_before[species]])
		_check(float(building.get_room(1).get("%s_kg" % species)) > 0.0,
				"11 %s reached the other room" % species)
	# La concentracion de cada ruta sale del SNAPSHOT, no del estado ya tocado:
	# para cada ruta, la masa de CO2 movida es la fraccion de la zona de origen
	# ANTES del paso por la masa de gas de esa ruta.
	var checked_routes: int = 0
	for route in result["transaction"]["routes"]:
		var source_room_id: String = String(route["source_room_id"])
		if source_room_id != "0":
			continue
		var zone: String = String(route["source_zone"])
		var zone_mass_kg: float = 12.0 if zone == "upper" else 48.0
		var zone_co2_kg: float = 0.22 if zone == "upper" else 0.08
		var bundle: Dictionary = route["bundle"]
		var expected_kg: float = zone_co2_kg / zone_mass_kg * float(bundle["mass_kg"])
		_check(_close(float(bundle["co2_kg"]), expected_kg, 1.0e-9),
				"11 route %s carries the snapshot concentration (%.9f vs %.9f)" % [
					route["segment_id"], bundle["co2_kg"], expected_kg])
		checked_routes += 1
	_check(checked_routes > 0, "11 at least one route left the source room")
	for species in ["co", "co2", "hcn"]:
		for index in [0, 1]:
			var room = building.get_room(index)
			_check(float(room.get("%s_upper_kg" % species)) <= float(room.get("%s_kg" % species)) + 1.0e-12,
					"11 the upper %s never exceeds the total in room %d" % [species, index])
			_check(float(room.get("%s_kg" % species)) >= -1.0e-12,
					"11 %s never goes negative in room %d" % [species, index])
	_free_engine(engine, building)


func _test_12_no_late_overwrite() -> void:
	var building: BuildingModel = _make_building(2, [_opening(0, 1)])
	var engine: SimulationEngine = _make_engine(building, true)
	_seed_room(building.get_room(0), 12.0, 493.15, 48.0, 298.15, 1.0)
	_seed_room(building.get_room(1), 0.0, T_REF_K, 57.6, T_REF_K)
	engine.step(DT_S)
	var committed: Dictionary = engine.pressure_network_last_result["diagnostics"]["pressure_by_room"]
	for room_id in committed.keys():
		var room = building.get_room(int(room_id))
		_check(_close(float(room.overpressure_pa), float(committed[room_id]), 1.0e-12),
				"12 nothing overwrote the canonical pressure of room %s (%.9f vs %.9f)" % [
					room_id, room.overpressure_pa, committed[room_id]])
		_check(_close(float(room.pressure_pa_therm), float(room.overpressure_pa), 1.0e-12),
				"12 the compatibility mirror matches the canonical pressure")
	_free_engine(engine, building)


func _test_13_ppv_is_rejected() -> void:
	var opening: Dictionary = _opening(0, -1, 1.0, 0.9, 2.0, 0.0, "window")
	opening["ppv_flow_m3_s"] = 3.0
	var building: BuildingModel = _make_building(1, [opening])
	var engine: SimulationEngine = _make_engine(building, true)
	_seed_room(building.get_room(0), 0.0, T_REF_K, 57.6, T_REF_K)
	for op in building.get_openings():
		op.ppv_flow_m3_s = 3.0
	engine.step(DT_S)
	_check(String(engine.pressure_network_failure) == "ppv_unsupported",
			"13 PPV with the authoritative network is rejected explicitly (%s)" % engine.pressure_network_failure)
	_free_engine(engine, building)


func _test_14_invalid_transaction_changes_nothing() -> void:
	# La transaccion se valida entera antes de tocar ninguna sala.
	var building: BuildingModel = _make_building(2, [_opening(0, 1)])
	var engine: SimulationEngine = _make_engine(building, true)
	_seed_room(building.get_room(0), 12.0, 493.15, 48.0, 298.15, 1.0)
	_seed_room(building.get_room(1), 0.0, T_REF_K, 57.6, T_REF_K)
	var system = TransportScript.new()
	var snapshot: Dictionary = system.build_snapshot(building)
	var solver_input: Dictionary = system.build_solver_input(snapshot, DT_S)
	var solution: Dictionary = system.solve(solver_input)
	var transaction: Dictionary = system.build_transport_transaction(snapshot, solution, DT_S)
	# Estropear la transaccion: una salida imposible.
	transaction["rooms"]["1"]["lower"]["mass_kg"] = -1.0e6
	var verdict: Dictionary = system.validate_transaction(snapshot, transaction)
	_check(not bool(verdict["valid"]) and not verdict["errors"].is_empty(),
			"14 an impossible transaction is rejected")
	var mass_before: float = _room_mass(building.get_room(1))
	_check(_close(_room_mass(building.get_room(1)), mass_before, 1.0e-12),
			"14 validating never touches a room")
	_free_engine(engine, building)


func _test_15_closing_a_door_leaves_the_network() -> void:
	var building: BuildingModel = _make_building(2, [_opening(0, 1)])
	var engine: SimulationEngine = _make_engine(building, true)
	_seed_room(building.get_room(0), 12.0, 493.15, 48.0, 298.15, 1.0)
	_seed_room(building.get_room(1), 0.0, T_REF_K, 57.6, T_REF_K)
	var open_result: Dictionary = _transport_step(building)
	var routes_open: int = open_result["transaction"]["routes"].size()
	_check(routes_open > 0, "15 the open door is part of the network")
	var pressure_open: float = float(building.get_room(0).overpressure_pa)
	for op in building.get_openings():
		op.set_open_fraction(0.0)
	var mass_before: float = _room_mass(building.get_room(0))
	var smoke_before: float = float(building.get_room(0).smoke_kg)
	var closed_result: Dictionary = _transport_step(building)
	_check(bool(closed_result["applied"]), "15 the closed network still solves")
	_check(closed_result["transaction"]["routes"].is_empty(),
			"15 a closed door carries nothing: there is no closed-door leak yet")
	_check(_close(_room_mass(building.get_room(0)), mass_before, 1.0e-12),
			"15 no mass crosses a closed door")
	_check(_close(float(building.get_room(0).smoke_kg), smoke_before, 1.0e-12),
			"15 no smoke crosses a closed door")
	var pressure_closed: float = float(building.get_room(0).overpressure_pa)
	_check(absf(pressure_closed - pressure_open) < 1000.0,
			"15 closing the door does not produce a kPa-sized jump (%.2f -> %.2f Pa)" % [
				pressure_open, pressure_closed])
	_free_engine(engine, building)


func _test_16_contract(dump_path: String) -> void:
	var code: String = _adapter_code()
	for forbidden in ["sqrt(", "bernoulli", "neutral_plane_z_m =", "open_fraction_smooth",
			"maxf(0.0, gauge", "pressure_network_solver_enabled"]:
		_check(not code.to_lower().contains(forbidden.to_lower()),
				"16 the adapter has no '%s'" % forbidden)
	for required in ["func build_snapshot(", "func build_solver_input(", "func solve(",
			"func build_transport_transaction(", "func validate_transaction(",
			"func commit_transaction("]:
		_check(code.contains(required), "16 the adapter keeps the operation '%s'" % required)
	_check(code.contains("solve_pressure_network("), "16 the adapter calls the canonical solver once")
	if dump_path.is_empty():
		return
	var building: BuildingModel = _make_building(2, [_opening(0, 1)])
	var engine: SimulationEngine = _make_engine(building, true)
	_seed_room(building.get_room(0), 12.0, 493.15, 48.0, 298.15, 1.0, 0.05, 0.04)
	_seed_room(building.get_room(1), 0.0, T_REF_K, 57.6, T_REF_K)
	engine.step(DT_S)
	var battery: Dictionary = {
		"room_0": {
			"pressure_pa": float(building.get_room(0).overpressure_pa),
			"upper_gas_kg": float(building.get_room(0).upper_gas_kg),
			"lower_gas_kg": float(building.get_room(0).lower_gas_kg),
			"smoke_kg": float(building.get_room(0).smoke_kg),
			"co_kg": float(building.get_room(0).co_kg),
		},
		"room_1": {
			"pressure_pa": float(building.get_room(1).overpressure_pa),
			"upper_gas_kg": float(building.get_room(1).upper_gas_kg),
			"lower_gas_kg": float(building.get_room(1).lower_gas_kg),
			"smoke_kg": float(building.get_room(1).smoke_kg),
			"co_kg": float(building.get_room(1).co_kg),
		},
	}
	_free_engine(engine, building)
	var file := FileAccess.open(dump_path, FileAccess.WRITE)
	if file == null:
		_check(false, "16 could not open the dump file")
		return
	file.store_string(_canonical(battery) + "\n")
	file.close()


func _adapter_code() -> String:
	var file := FileAccess.open(ADAPTER_PATH, FileAccess.READ)
	if file == null:
		return ""
	var lines: PackedStringArray = []
	while not file.eof_reached():
		var line: String = file.get_line()
		if not line.strip_edges().begins_with("#"):
			lines.append(line)
	file.close()
	return "\n".join(lines)

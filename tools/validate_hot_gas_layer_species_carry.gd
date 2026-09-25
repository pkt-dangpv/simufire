extends SceneTree
## Ruta normal (red de presion OFF): la parcela de gas caliente que cruza una
## abertura interior lleva las especies de SU capa.
##
## `ThermalSystem._transfer_hot_gas_contaminants()` mueve gas de la capa ALTA
## de la sala caliente a la capa ALTA de la fria (`hot_room.upper_gas_kg -=
## gas_moved_kg`). CO y HCN salian con esa fraccion de la capa alta del origen.
## El CO2 se dimensionaba sobre el TOTAL de la sala, y la parte que no estaba en
## la capa alta se restaba de la capa BAJA del origen sin que ningun gas de esa
## capa se moviera, y llegaba entera a la capa alta del receptor. Medido en
## `preset_simple_house` (300 s, ruta de producto): 6,713 kg de CO2 sacados de
## capas bajas en 17 343 de 21 280 acarreos, el primero en el paso 417.
##
## Este validador fija:
##   H1  la funcion real, con especies en las dos capas del origen: la capa baja
##       del origen no cambia (CO, CO2, HCN); el CO2 sale con la MISMA fraccion
##       de su capa alta que el CO; cada especie se conserva; la capa baja del
##       receptor no cambia;
##   H1c control: sin especies en la capa baja el acarreo es el de siempre;
##   H2  la ruta de producto (`preset_simple_house`, red OFF, 3 600 pasos): el
##       acarreo termico no saca ni un kg de especie de ninguna capa baja, y el
##       regimen se ejerce (hay acarreos desde origenes con CO2 en capa baja).

const BuildingModelScript := preload("res://sim/BuildingModel.gd")
const SimulationEngineScript := preload("res://sim/core/SimulationEngine.gd")
const ThermalSystemScript := preload("res://sim/core/ThermalSystem.gd")
const SCENARIO := "res://scenarios/preset_simple_house.json"
const DT_S: float = 1.0 / 12.0
const H2_STEPS: int = 3600
const SPECIES_TOL_KG: float = 1.0e-15
const LAYERED: Array[String] = ["co", "co2", "hcn"]

var _failures: Array[String] = []
var _checks: int = 0


## Observador del acarreo termico: llama a la funcion real y anota, por
## llamada, cuanto de cada especie salio de la capa baja del origen.
class CarryProbe extends "res://sim/core/ThermalSystem.gd":
	var events: int = 0
	var events_with_lower_co2: int = 0
	var lower_drawn_kg: Dictionary = {"co": 0.0, "co2": 0.0, "hcn": 0.0}
	var worst_event_kg: float = 0.0

	func _transfer_hot_gas_contaminants(source: RoomModel, target: RoomModel,
			gas_moved_kg: float, source_upper_gas_before_kg: float, carry_intensity: float,
			mechanism: String, opening_index: int = -1) -> void:
		var totals: Array = [_delta_co_kg, _delta_co2_kg, _delta_hcn_kg]
		var uppers: Array = [_delta_co_upper_kg, _delta_co2_upper_kg, _delta_hcn_upper_kg]
		var before: Array = []
		for i in range(3):
			before.append(float(totals[i].get(source.id, 0.0)) - float(uppers[i].get(source.id, 0.0)))
		if source.co2_kg - clampf(source.co2_upper_kg, 0.0, source.co2_kg) > 1.0e-9:
			events_with_lower_co2 += 1
		super(source, target, gas_moved_kg, source_upper_gas_before_kg, carry_intensity,
				mechanism, opening_index)
		events += 1
		for i in range(3):
			var after: float = float(totals[i].get(source.id, 0.0)) - float(uppers[i].get(source.id, 0.0))
			# delta_total - delta_upper es lo que cambio la capa baja del origen.
			var drawn: float = -(after - float(before[i]))
			lower_drawn_kg[LAYERED[i]] += drawn
			worst_event_kg = maxf(worst_event_kg, absf(drawn))


func _initialize() -> void:
	_h1_function_keeps_the_source_lower_layer()
	_h1c_upper_only_control()
	_h2_product_route()
	if _failures.is_empty():
		print("  %d checks" % _checks)
		print("HOT GAS LAYER SPECIES CARRY VALIDATION PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
		print("FAIL: " + failure)
	print("HOT GAS LAYER SPECIES CARRY VALIDATION FAIL (%d)" % _failures.size())
	quit(1)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _two_rooms() -> BuildingModel:
	var rooms: Array = []
	for i in range(2):
		rooms.append({"id": i, "name": "Caliente" if i == 0 else "Fria",
			"kind": "salon" if i == 0 else "pasillo", "floor_level_z_m": 0.0,
			"height_m": 2.4, "rotation_deg": 0.0, "fuel_energy_MJ": 0.0,
			"max_hrr_kw": 0.0, "fuel_objects": []})
	var building: BuildingModel = BuildingModelScript.new()
	building.load_template_data({
		"building_type": "house", "floors": [{"level_m": 0.0, "name": "PB"}],
		"rooms_data": rooms,
		"room_rect_m": {"0": {"x": 0.0, "y": 0.0, "w": 5.0, "h": 4.0},
			"1": {"x": 5.0, "y": 0.0, "w": 5.0, "h": 4.0}},
		"openings_data": [{"a": 0, "b": 1, "type": "door", "width_m": 0.9, "height_m": 2.0,
			"sill_m": 0.0, "offset_m": 0.5, "offset_is_fraction": true, "open_fraction": 1.0,
			"wall": "", "hinge_side": "left", "swing_direction": "in"}],
		"ignition_room_id": 0, "hvac_mode": "none",
	})
	return building


## El termico con los mismos coeficientes que le pasa el motor por defecto.
func _thermal(building: BuildingModel):
	var thermal = ThermalSystemScript.new()
	var engine = SimulationEngineScript.new()
	thermal.hot_gas_species_carry_fraction = engine.hot_gas_species_carry_fraction
	thermal.hot_gas_species_max_fraction_per_step = engine.hot_gas_species_max_fraction_per_step
	thermal.hot_gas_smoke_carry_fraction = engine.hot_gas_smoke_carry_fraction
	thermal.hot_gas_hcn_carry_fraction = engine.hot_gas_hcn_carry_fraction
	engine.free()
	thermal.set_references(building, null)
	return thermal


func _load(room: RoomModel, upper: Array, lower: Array) -> void:
	for i in range(3):
		room.set("%s_upper_kg" % LAYERED[i], float(upper[i]))
		room.set("%s_kg" % LAYERED[i], float(upper[i]) + float(lower[i]))


func _layers(room: RoomModel) -> Dictionary:
	var out: Dictionary = {}
	for s in LAYERED:
		var total: float = float(room.get("%s_kg" % s))
		var upper: float = float(room.get("%s_upper_kg" % s))
		out[s] = {"total": total, "upper": upper, "lower": total - upper}
	return out


## Una parcela de la capa alta: 0,5 kg de 5 kg (10 %), intensidad plena.
func _carry_once(upper: Array, lower: Array) -> Array:
	var building: BuildingModel = _two_rooms()
	var thermal = _thermal(building)
	var hot: RoomModel = building.get_room(0)
	var cold: RoomModel = building.get_room(1)
	_load(hot, upper, lower)
	_load(cold, [0.0, 0.0, 0.0], [0.0, 0.0, 0.0])
	var before_hot: Dictionary = _layers(hot)
	var before_cold: Dictionary = _layers(cold)
	thermal._transfer_hot_gas_contaminants(hot, cold, 0.5, 5.0, 1.0, "validator_parcel", 0)
	thermal._flush_contaminant_deltas(building)
	var result: Array = [before_hot, _layers(hot), before_cold, _layers(cold)]
	building.free()
	return result


func _h1_function_keeps_the_source_lower_layer() -> void:
	# CO 0,04 alta + 0,06 baja; CO2 0,4 + 0,6; HCN 0,004 + 0,006.
	var r: Array = _carry_once([0.04, 0.4, 0.004], [0.06, 0.6, 0.006])
	var hot0: Dictionary = r[0]
	var hot1: Dictionary = r[1]
	var cold0: Dictionary = r[2]
	var cold1: Dictionary = r[3]
	var fractions: Dictionary = {}
	for s in LAYERED:
		var drawn_lower: float = float(hot0[s]["lower"]) - float(hot1[s]["lower"])
		_check(absf(drawn_lower) <= SPECIES_TOL_KG,
				"H1 %s: the hot-gas parcel took %s kg from the source LOWER layer" % [s, str(drawn_lower)])
		var moved: float = float(hot0[s]["total"]) - float(hot1[s]["total"])
		_check(moved > 0.0, "H1 %s: nothing was carried" % s)
		_check(absf(float(cold1[s]["total"]) - float(cold0[s]["total"]) - moved) <= SPECIES_TOL_KG,
				"H1 %s: not conserved between the two rooms" % s)
		_check(absf(float(cold1[s]["lower"]) - float(cold0[s]["lower"])) <= SPECIES_TOL_KG,
				"H1 %s: the parcel reached the target LOWER layer" % s)
		fractions[s] = moved / float(hot0[s]["upper"])
	# Una misma parcela: CO2 sale de su capa alta con la fraccion del CO. (HCN
	# lleva ademas su propio factor de acarreo, asi que solo se le exige la capa.)
	_check(absf(float(fractions["co2"]) - float(fractions["co"])) <= 1.0e-12,
			"H1 CO2 left its upper layer with fraction %s, CO with %s" % [
				str(fractions["co2"]), str(fractions["co"])])
	print("  H1 carried fraction of the upper layer: CO %.6f CO2 %.6f HCN %.6f" % [
		float(fractions["co"]), float(fractions["co2"]), float(fractions["hcn"])])


func _h1c_upper_only_control() -> void:
	var r: Array = _carry_once([0.04, 0.4, 0.004], [0.0, 0.0, 0.0])
	var hot0: Dictionary = r[0]
	var hot1: Dictionary = r[1]
	var moved_co: float = float(hot0["co"]["total"]) - float(hot1["co"]["total"])
	var moved_co2: float = float(hot0["co2"]["total"]) - float(hot1["co2"]["total"])
	# 10 % de la capa alta x acarreo 0,72: 0,0288 kg de CO2 y 0,00288 kg de CO.
	_check(absf(moved_co2 - 0.4 * 0.1 * 0.72) <= 1.0e-12,
			"H1c upper-only CO2 carried %s kg, expected 0.0288" % str(moved_co2))
	_check(absf(moved_co - 0.04 * 0.1 * 0.72) <= 1.0e-12,
			"H1c upper-only CO carried %s kg, expected 0.00288" % str(moved_co))


func _h2_product_route() -> void:
	var template: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SCENARIO))
	var building: BuildingModel = BuildingModelScript.new()
	building.load_template_data(template)
	var engine = SimulationEngineScript.new()
	var probe := CarryProbe.new()
	engine.thermal_system = probe
	engine.building = building
	engine.auto_ignite_on_ready = false
	engine.auto_finish_on_extinction = false
	engine.enable_logging = false
	engine.enable_csv_log = false
	engine.ignition_room_id = int(template.get("ignition_room_id", 0))
	engine.reset_simulation(engine.ignition_room_id, true)
	engine.suppress_exit_graphs()
	# Como tools/run_scenario_headless.gd: la duracion la fija quien ejecuta.
	engine.sim_duration_limit_s = 0.0
	_check(not engine.pressure_network_solver_enabled, "H2 product route must run with the network OFF")
	for _i in range(H2_STEPS):
		engine.step(DT_S)
	print("  H2 preset_simple_house: %d carries, %d from sources with lower-layer CO2; lower drawn CO %s CO2 %s HCN %s kg" % [
		probe.events, probe.events_with_lower_co2, str(probe.lower_drawn_kg["co"]),
		str(probe.lower_drawn_kg["co2"]), str(probe.lower_drawn_kg["hcn"])])
	_check(probe.events > 1000, "H2 the hot-gas carry did not run (%d)" % probe.events)
	_check(probe.events_with_lower_co2 > 1000,
			"H2 the regime is not exercised: %d carries from sources with lower CO2" % probe.events_with_lower_co2)
	for s in LAYERED:
		_check(absf(float(probe.lower_drawn_kg[s])) <= 1.0e-12,
				"H2 the hot-gas carry took %s kg of %s from source LOWER layers" % [
					str(probe.lower_drawn_kg[s]), s])
	_check(probe.worst_event_kg <= SPECIES_TOL_KG,
			"H2 worst single carry drew %s kg from a lower layer" % str(probe.worst_event_kg))
	engine.free()
	building.free()

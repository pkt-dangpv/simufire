extends SceneTree

## F2.2-R3: fuga de envolvente exterior cerrada dentro de la red autoritativa.
##
## Diez casos que separan equilibrio, sobrepresion, depresion, contraflujo,
## multiplicidad, exclusividad, area cero, planta elevada, viento y atomicidad.
##
##   R3-M1  equilibrio: sin gradiente no hay caudal
##   R3-M2  sobrepresion: sale, y la presion se relaja
##   R3-M3  depresion: entra aire exterior con su O2 y su temperatura
##   R3-M4  contraflujo: entra por abajo y sale por arriba
##   R3-M5  varias ventanas cerradas: area aditiva e identificadores unicos
##   R3-M6  ventana abierta: solo abertura grande, sin doble area
##   R3-M7  area cero: equivalencia exacta con R3 apagada
##   R3-M8  planta elevada: perfil exterior correcto e invariancia al trasladar
##   R3-M9  viento: signo correcto y una sola aplicacion
##   R3-M10 fallo atomico: ningun recinto modificado
##   R3-M11 guardas del contrato: interruptor, exclusividad y cota del hueco
##
##   <godot> --headless --path . --script res://tools/validate_exterior_envelope_leakage.gd

const BuildingModelScript := preload("res://sim/BuildingModel.gd")
const TransportScript := preload("res://sim/core/PressureNetworkTransportSystem.gd")
const EnvelopeAdapterScript := preload("res://sim/core/ExteriorEnvelopeLeakageAdapter.gd")
const WindModelScript := preload("res://sim/core/ExteriorWindPressureModel.gd")
const SimulationEngineScript := preload("res://sim/core/SimulationEngine.gd")
## R3-M11 llama al adaptador DIRECTAMENTE, sin pasar por el punto de llamada.
const OpeningModelScript := preload("res://sim/building/OpeningModel.gd")

const DT_S: float = 0.0833333333333333
const HEIGHT_M: float = 2.5
const T_REF_K: float = 293.15
const RHO_REF: float = 1.2
## Area de fuga historica por abertura exterior cerrada. GEOMETRICA: el Cd va
## aparte, y esta fase no la calibra.
const LEAK_AREA_M2: float = 0.005
## Clave con la que la red nombra al exterior.
const EXTERIOR_KEY: String = "outside"

var _failures: Array[String] = []
var _checks: int = 0


func _initialize() -> void:
	_m1_equilibrium()
	_m2_overpressure()
	_m3_underpressure()
	_m4_counterflow()
	_m5_several_windows()
	_m6_open_window()
	_m7_zero_area()
	_m8_upper_floor()
	_m9_wind()
	_m10_atomic_failure()
	_m11_contract_guards()
	if _failures.is_empty():
		print("  %d checks" % _checks)
		print("EXTERIOR ENVELOPE LEAKAGE VALIDATION PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
		print("FAIL: " + failure)
	print("EXTERIOR ENVELOPE LEAKAGE VALIDATION FAIL (%d)" % _failures.size())
	quit(1)


# ---------------------------------------------------------------- helpers

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _close(actual: float, expected: float, tol: float) -> bool:
	if is_nan(actual) or is_nan(expected):
		return false
	return absf(actual - expected) <= tol


## Edificio de un recinto con `window_count` ventanas exteriores cerradas.
func _building(window_count: int = 1, floor_z_m: float = 0.0,
		open_fraction: float = 0.0, wall: String = "right",
		opening_kind: String = "window", sill_m: float = 1.0,
		opening_height_m: float = 1.0) -> BuildingModel:
	var openings: Array = []
	for index in range(window_count):
		openings.append({
			"a": 0, "b": -1, "type": opening_kind, "open_fraction": open_fraction,
			"width_m": 1.2, "height_m": opening_height_m, "sill_m": sill_m,
			"wall": wall, "offset_m": 1.0 + float(index), "offset_is_fraction": false,
		})
	var template: Dictionary = {
		"building_type": "house",
		"floors": [{"level_m": floor_z_m, "name": "R"}],
		"rooms_data": [{
			"id": 0, "name": "R0", "kind": "salon", "floor_level_z_m": floor_z_m,
			"height_m": HEIGHT_M, "fuel_energy_MJ": 0.0, "max_hrr_kw": 0.0,
			"fuel_objects": [], "rotation_deg": 0.0,
		}],
		"room_rect_m": {"0": {"x": 0.0, "y": 0.0, "w": 5.0, "h": 4.0}},
		"openings_data": openings,
	}
	var building: BuildingModel = BuildingModelScript.new()
	building.load_template_data(template)
	root.add_child(building)
	return building


## Sistema de transporte con R3 encendida.
func _system(area_m2: float = LEAK_AREA_M2, wind: bool = false):
	var system = TransportScript.new()
	system.exterior_envelope_leakage_enabled = true
	system.exterior_envelope_leakage_area_m2 = area_m2
	system.wind_effect_enabled = wind
	return system


## Siembra el recinto con masa y energia dadas.
func _seed(room, upper_kg: float, lower_kg: float,
		upper_energy_kj: float, lower_energy_kj: float) -> void:
	room.upper_gas_kg = upper_kg
	room.lower_gas_kg = lower_kg
	room.upper_energy_kj = upper_energy_kj
	room.lower_energy_kj = lower_energy_kj


## Masa de gas que llena el recinto a presion y temperatura de referencia.
func _ambient_mass_kg(room) -> float:
	return RHO_REF * room.volume_m3()


func _total_mass_kg(room) -> float:
	return float(room.upper_gas_kg) + float(room.lower_gas_kg)


## Elementos de envolvente de un snapshot.
func _envelope_elements(snapshot: Dictionary) -> Array:
	var found: Array = []
	for raw in snapshot.get("openings", []):
		var element: Dictionary = raw
		if String(element.get("provenance", "")) == EnvelopeAdapterScript.PROVENANCE:
			found.append(element)
	return found


## Area total que el solver integrara para un elemento.
func _integrated_area_m2(element: Dictionary) -> float:
	return float(element["width_m"]) * float(element["open_fraction"]) \
			* (float(element["top_z_m"]) - float(element["bottom_z_m"]))


func _free(building) -> void:
	if building != null:
		building.queue_free()


# ---------------------------------------------------------------- R3-M1

## Recinto en equilibrio con su exterior local: la fuga existe pero no mueve
## nada. Es el caso que distingue una fuga de un sumidero.
func _m1_equilibrium() -> void:
	var building: BuildingModel = _building()
	var room = building.get_room(0)
	# Masa ambiente y energia sensible cero: presion absoluta = la de referencia.
	_seed(room, 0.0, _ambient_mass_kg(room), 0.0, 0.0)
	var mass_before_kg: float = _total_mass_kg(room)
	var system = _system()
	var result: Dictionary = system.step(building, DT_S)
	_check(bool(result.get("applied", false)),
			"R3-M1 the network applies (%s)" % result.get("failure_reason", ""))
	_check(_close(_total_mass_kg(room), mass_before_kg, 1.0e-12),
			"R3-M1 equilibrium moves no mass (%.15f vs %.15f kg)" % [
				_total_mass_kg(room), mass_before_kg])
	_free(building)


# ---------------------------------------------------------------- R3-M2

## Recinto presurizado: sale gas y la presion se relaja.
func _m2_overpressure() -> void:
	var building: BuildingModel = _building()
	var room = building.get_room(0)
	# Mas masa de la ambiente: sobrepresion sin necesidad de calentar.
	_seed(room, 0.0, _ambient_mass_kg(room) * 1.10, 0.0, 0.0)
	var mass_before_kg: float = _total_mass_kg(room)
	var system = _system()
	var result: Dictionary = system.step(building, DT_S)
	_check(bool(result.get("applied", false)),
			"R3-M2 the network applies (%s)" % result.get("failure_reason", ""))
	_check(_total_mass_kg(room) < mass_before_kg,
			"R3-M2 an overpressurised room vents (%.9f vs %.9f kg)" % [
				_total_mass_kg(room), mass_before_kg])
	var elements: Array = _envelope_elements(system.build_snapshot(building, {}, DT_S))
	_check(elements.size() == 1, "R3-M2 exactly one envelope element (%d)" % elements.size())
	_free(building)


# ---------------------------------------------------------------- R3-M3

## Recinto en depresion: entra aire exterior. La ruta historica NO podia hacer
## esto —solo permitia salida—, asi que este caso es nuevo de R3.
func _m3_underpressure() -> void:
	var building: BuildingModel = _building()
	var room = building.get_room(0)
	_seed(room, 0.0, _ambient_mass_kg(room) * 0.90, 0.0, 0.0)
	var mass_before_kg: float = _total_mass_kg(room)
	var system = _system()
	var result: Dictionary = system.step(building, DT_S)
	_check(bool(result.get("applied", false)),
			"R3-M3 the network applies (%s)" % result.get("failure_reason", ""))
	_check(_total_mass_kg(room) > mass_before_kg,
			"R3-M3 an underpressurised room draws air in (%.9f vs %.9f kg)" % [
				_total_mass_kg(room), mass_before_kg])
	_free(building)


# ---------------------------------------------------------------- R3-M4

## Contraflujo: una capa caliente arriba y aire frio abajo dan signos opuestos
## de `dp(z)` a lo largo del propio hueco.
func _m4_counterflow() -> void:
	# Hueco alto, para que el plano neutro tenga donde caer.
	var building: BuildingModel = _building(1, 0.0, 0.0, "right", "window", 0.2, 2.0)
	var room = building.get_room(0)
	var ambient_kg: float = _ambient_mass_kg(room)
	# Calibracion por COMPENSACION, y es la parte que importa del caso: la EOS
	# canonica es p = (R/V)(M*T_ref + E/cp), asi que una capa caliente sube la
	# presion igual que masa de mas. Sembrar «menos masa y mucho calor» deja el
	# recinto a decenas de kPa y el flujo sale por todas las bandas a la vez.
	# Para que la FLOTABILIDAD decida el signo a cada altura hay que dejar la
	# presion total en ambiente: se fija la masa caliente y se despeja la fria.
	var upper_kg: float = 4.0
	var upper_energy_kj: float = upper_kg * 400.0
	var total_kg: float = (ambient_kg * T_REF_K - upper_energy_kj) / T_REF_K
	_seed(room, upper_kg, maxf(0.0, total_kg - upper_kg), upper_energy_kj, 0.0)
	var system = _system()
	var result: Dictionary = system.step(building, DT_S)
	_check(bool(result.get("applied", false)),
			"R3-M4 the network applies (%s)" % result.get("failure_reason", ""))
	var elements: Array = _envelope_elements(result.get("solution", {}))
	if elements.is_empty():
		# La solucion publica las aberturas con su id; se busca por prefijo.
		for raw in result.get("solution", {}).get("openings", []):
			var opening: Dictionary = raw
			if String(opening.get("opening_id", "")).begins_with(EnvelopeAdapterScript.ID_PREFIX):
				elements.append(opening)
	_check(not elements.is_empty(), "R3-M4 the solution reports the envelope element")
	if elements.is_empty():
		_free(building)
		return
	var element: Dictionary = elements[0]
	_check(bool(element.get("neutral_plane_inside", false)),
			"R3-M4 the neutral plane falls inside the leak (%s)" % [
				element.get("neutral_plane_z_m", "?")])
	_free(building)


# ---------------------------------------------------------------- R3-M5

## Dos ventanas cerradas iguales: cada una aporta su area, y sus identificadores
## no colisionan. Es la correccion de identificadores que D1 ya tuvo que hacer.
func _m5_several_windows() -> void:
	var building: BuildingModel = _building(3)
	var room = building.get_room(0)
	_seed(room, 0.0, _ambient_mass_kg(room), 0.0, 0.0)
	var system = _system()
	var elements: Array = _envelope_elements(system.build_snapshot(building, {}, DT_S))
	_check(elements.size() == 3, "R3-M5 three windows give three elements (%d)" % elements.size())
	var ids: Dictionary = {}
	var total_area_m2: float = 0.0
	for raw in elements:
		var element: Dictionary = raw
		ids[String(element["opening_id"])] = true
		total_area_m2 += _integrated_area_m2(element)
	_check(ids.size() == elements.size(),
			"R3-M5 the identifiers do not collide (%d unique of %d)" % [
				ids.size(), elements.size()])
	_check(_close(total_area_m2, 3.0 * LEAK_AREA_M2, 1.0e-15),
			"R3-M5 the area is additive (%.15f vs %.15f m2)" % [
				total_area_m2, 3.0 * LEAK_AREA_M2])
	_free(building)


# ---------------------------------------------------------------- R3-M6

## Ventana abierta: solo abertura grande. No se suma ademas la fuga de marco.
func _m6_open_window() -> void:
	for fraction in [0.05, 0.5, 1.0]:
		var building: BuildingModel = _building(1, 0.0, fraction)
		var room = building.get_room(0)
		_seed(room, 0.0, _ambient_mass_kg(room), 0.0, 0.0)
		var system = _system()
		var snapshot: Dictionary = system.build_snapshot(building, {}, DT_S)
		var envelope: Array = _envelope_elements(snapshot)
		_check(envelope.is_empty(),
				"R3-M6 an open window (%.2f) adds no envelope leak (%d)" % [
					fraction, envelope.size()])
		_check((snapshot.get("openings", []) as Array).size() == 1,
				"R3-M6 an open window is exactly one element (%.2f)" % fraction)
		_free(building)

	# Y un HOLE nunca recibe fuga cerrada: no se cierra.
	var hole_building: BuildingModel = _building(1, 0.0, 0.0, "right", "hole")
	var hole_room = hole_building.get_room(0)
	_seed(hole_room, 0.0, _ambient_mass_kg(hole_room), 0.0, 0.0)
	var hole_system = _system()
	_check(_envelope_elements(hole_system.build_snapshot(hole_building, {}, DT_S)).is_empty(),
			"R3-M6 a HOLE never gets envelope leakage")
	_free(hole_building)


# ---------------------------------------------------------------- R3-M7

## Area cero es exactamente no tener elemento.
func _m7_zero_area() -> void:
	var building: BuildingModel = _building()
	var room = building.get_room(0)
	_seed(room, 0.0, _ambient_mass_kg(room) * 1.10, 0.0, 0.0)
	var zero_system = _system(0.0)
	_check(_envelope_elements(zero_system.build_snapshot(building, {}, DT_S)).is_empty(),
			"R3-M7 a zero leak area contributes no element")

	# Y un area mayor que el propio hueco se RECHAZA, no se recorta en silencio.
	var huge_system = _system(999.0)
	_check(_envelope_elements(huge_system.build_snapshot(building, {}, DT_S)).is_empty(),
			"R3-M7 a leak larger than the opening is rejected, not clamped")
	_free(building)


# ---------------------------------------------------------------- R3-M8

## Planta elevada: el perfil exterior es el de C-R1, y trasladar el edificio
## entero junto con su referencia no puede inventar caudal.
func _m8_upper_floor() -> void:
	var ground: BuildingModel = _building(1, 0.0)
	var ground_room = ground.get_room(0)
	_seed(ground_room, 0.0, _ambient_mass_kg(ground_room), 0.0, 0.0)
	var ground_system = _system()
	var ground_mass_kg: float = _total_mass_kg(ground_room)
	ground_system.step(ground, DT_S)
	var ground_delta_kg: float = _total_mass_kg(ground_room) - ground_mass_kg

	# Mismo recinto, seis metros mas arriba, con la referencia exterior movida
	# con el. El estado relativo es identico, luego el caudal tambien.
	var raised: BuildingModel = _building(1, 6.0)
	var raised_room = raised.get_room(0)
	_seed(raised_room, 0.0, _ambient_mass_kg(raised_room), 0.0, 0.0)
	var raised_system = _system()
	var raised_mass_kg: float = _total_mass_kg(raised_room)
	raised_system.step(raised, DT_S, {"reference_z_m": 6.0})
	var raised_delta_kg: float = _total_mass_kg(raised_room) - raised_mass_kg

	_check(_close(raised_delta_kg, ground_delta_kg, 1.0e-12),
			"R3-M8 translating the building and its datum changes nothing (%.15f vs %.15f kg)" % [
				raised_delta_kg, ground_delta_kg])
	_check(_close(ground_delta_kg, 0.0, 1.0e-12),
			"R3-M8 a room in equilibrium moves no mass (%.15f kg)" % ground_delta_kg)
	_free(ground)
	_free(raised)


# ---------------------------------------------------------------- R3-M9

## Viento: signo correcto y una sola aplicacion.
func _m9_wind() -> void:
	# El modelo puro primero, que es donde vive la formula.
	var windward: float = WindModelScript.wind_dp_pa("right", 90.0, 10.0)
	var leeward: float = WindModelScript.wind_dp_pa("left", 90.0, 10.0)
	_check(windward > 0.0, "R3-M9 a windward facade gets positive pressure (%.6f Pa)" % windward)
	_check(leeward < 0.0, "R3-M9 a leeward facade gets suction (%.6f Pa)" % leeward)
	var perpendicular: float = WindModelScript.wind_dp_pa("top", 90.0, 10.0)
	_check(_close(perpendicular, 0.0, 1.0e-12),
			"R3-M9 a perpendicular facade gets nothing (%.15f Pa)" % perpendicular)
	_check(_close(WindModelScript.wind_dp_pa("right", 90.0, 0.0), 0.0, 0.0),
			"R3-M9 no wind means no pressure")
	_check(_close(WindModelScript.wind_dp_pa("", 90.0, 10.0), 0.0, 0.0),
			"R3-M9 an unknown facade gets nothing")

	# Y el elemento lo lleva UNA vez, con el valor del modelo.
	var building: BuildingModel = _building()
	building.wind_speed_m_s = 10.0
	building.wind_direction_deg = 90.0
	var room = building.get_room(0)
	_seed(room, 0.0, _ambient_mass_kg(room), 0.0, 0.0)
	var system = _system(LEAK_AREA_M2, true)
	var elements: Array = _envelope_elements(system.build_snapshot(building, {}, DT_S))
	_check(elements.size() == 1, "R3-M9 the element exists (%d)" % elements.size())
	if elements.is_empty():
		_free(building)
		return
	var expected_pa: float = WindModelScript.wind_dp_pa("right", 90.0, 10.0)
	_check(_close(float(elements[0].get("wind_dp_pa", 0.0)), expected_pa, 1.0e-12),
			"R3-M9 the element carries the wind exactly once (%.12f vs %.12f Pa)" % [
				elements[0].get("wind_dp_pa", 0.0), expected_pa])

	# Apagado el efecto, el elemento sigue existiendo pero sin viento.
	var calm_system = _system(LEAK_AREA_M2, false)
	var calm: Array = _envelope_elements(calm_system.build_snapshot(building, {}, DT_S))
	_check(not calm.is_empty() and _close(float(calm[0].get("wind_dp_pa", 1.0)), 0.0, 0.0),
			"R3-M9 with the wind effect off the element carries none")
	_free(building)


# ---------------------------------------------------------------- R3-M10

## Fallo atomico: si la transaccion no vale, no se aplica NADA. Se fuerza con un
## exterior invalido, que el solver rechaza antes de tocar ningun recinto.
func _m10_atomic_failure() -> void:
	var building: BuildingModel = _building()
	var room = building.get_room(0)
	_seed(room, 0.0, _ambient_mass_kg(room) * 1.10, 0.0, 0.0)
	var before: Array = [
		float(room.upper_gas_kg), float(room.lower_gas_kg),
		float(room.upper_energy_kj), float(room.lower_energy_kj),
	]
	var system = _system()
	# Presion exterior no fisica: el contrato de F2.2A la rechaza.
	var result: Dictionary = system.step(building, DT_S, {"pressure_abs_pa": -1.0})
	_check(not bool(result.get("applied", true)),
			"R3-M10 an invalid transaction is not applied")
	_check(not String(result.get("failure_reason", "")).is_empty(),
			"R3-M10 the failure has an explicit reason (%s)" % result.get("failure_reason", ""))
	var after: Array = [
		float(room.upper_gas_kg), float(room.lower_gas_kg),
		float(room.upper_energy_kj), float(room.lower_energy_kj),
	]
	_check(before == after,
			"R3-M10 no room was modified (%s vs %s)" % [after, before])
	_free(building)


# ---------------------------------------------------------------- R3-M11

## Guardas que los diez casos anteriores NO cubrian, y que la campana de
## mutaciones destapo:
##
##   - ninguno corria con R3 APAGADA, asi que nada comprobaba que el
##     interruptor apagase de verdad;
##   - la exclusividad la impone el punto de llamada de `build_snapshot`, de
##     modo que el adaptador podia dejar de defender su propio contrato sin que
##     nada fallara. Aqui se le llama DIRECTAMENTE;
##   - casi todos los recintos estaban a cota 0, asi que colocar el hueco en una
##     cota equivocada no cambiaba ningun resultado.
func _m11_contract_guards() -> void:
	# --- el interruptor apaga de verdad
	var building: BuildingModel = _building()
	var room = building.get_room(0)
	_seed(room, 0.0, _ambient_mass_kg(room) * 1.10, 0.0, 0.0)
	var off_system = TransportScript.new()
	off_system.exterior_envelope_leakage_enabled = false
	off_system.exterior_envelope_leakage_area_m2 = LEAK_AREA_M2
	var off_snapshot: Dictionary = off_system.build_snapshot(building, {}, DT_S)
	_check(_envelope_elements(off_snapshot).is_empty(),
			"R3-M11 with the switch off no envelope element is built")
	_check((off_snapshot.get("openings", []) as Array).is_empty(),
			"R3-M11 with the switch off a closed window stays sealed")

	# --- el adaptador defiende su contrato por si mismo, sin depender del
	#     punto de llamada
	var closed_window = building.get_openings()[0]
	_check(not EnvelopeAdapterScript.build_leakage_element(
				closed_window, -1, 0.0, "0", EXTERIOR_KEY, LEAK_AREA_M2).is_empty(),
			"R3-M11 the adapter does build for a closed exterior window")

	var open_window = OpeningModelScript.new(0, -1, OpeningModelScript.Type.WINDOW,
			1.2, 1.0, 1.0, 1.0)
	open_window.wall_side = "right"
	_check(EnvelopeAdapterScript.build_leakage_element(
				open_window, -1, 0.0, "0", EXTERIOR_KEY, LEAK_AREA_M2).is_empty(),
			"R3-M11 the adapter itself refuses an open window")

	var hole = OpeningModelScript.new(0, -1, OpeningModelScript.Type.HOLE,
			1.2, 1.0, 0.0, 1.0)
	hole.wall_side = "right"
	_check(EnvelopeAdapterScript.build_leakage_element(
				hole, -1, 0.0, "0", EXTERIOR_KEY, LEAK_AREA_M2).is_empty(),
			"R3-M11 the adapter itself refuses a HOLE")

	var interior = OpeningModelScript.new(0, 1, OpeningModelScript.Type.DOOR,
			0.9, 2.05, 0.0, 0.0)
	interior.wall_side = "right"
	_check(EnvelopeAdapterScript.build_leakage_element(
				interior, -1, 0.0, "0", "1", LEAK_AREA_M2).is_empty(),
			"R3-M11 the adapter itself refuses an interior opening")

	# --- la cota del hueco es la del recinto, no la del suelo del edificio
	var raised: BuildingModel = _building(1, 9.0)
	var raised_room = raised.get_room(0)
	_seed(raised_room, 0.0, _ambient_mass_kg(raised_room), 0.0, 0.0)
	var raised_system = _system()
	var raised_elements: Array = _envelope_elements(
			raised_system.build_snapshot(raised, {"reference_z_m": 9.0}, DT_S))
	_check(raised_elements.size() == 1,
			"R3-M11 the raised room has its element (%d)" % raised_elements.size())
	if not raised_elements.is_empty():
		# suelo 9 m + alfeizar 1 m, y el dintel un metro mas arriba.
		_check(_close(float(raised_elements[0]["bottom_z_m"]), 10.0, 1.0e-12),
				"R3-M11 the sill sits at the room floor plus its own height (%.6f m)" % [
					raised_elements[0]["bottom_z_m"]])
		_check(_close(float(raised_elements[0]["top_z_m"]), 11.0, 1.0e-12),
				"R3-M11 and so does the lintel (%.6f m)" % [raised_elements[0]["top_z_m"]])
	_free(building)
	_free(raised)

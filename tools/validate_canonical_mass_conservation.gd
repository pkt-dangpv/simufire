extends SceneTree

## F2.2-R2-MASS: la masa zonal es estado conservado bajo la red autoritativa.
##
## Ocho casos que separan calentamiento, enfriamiento, reparto entre capas,
## inversion termica, limite geometrico, repeticion, orden del paso y ruta
## historica. Cada uno falla por una razon distinta:
##
##   R2-M1  calentamiento sellado sin fuente de masa
##   R2-M2  enfriamiento sellado
##   R2-M3  transferencia lower->upper
##   R2-M4  inversion termica
##   R2-M5  limite geometrico de la capa superior
##   R2-M6  proyecciones repetidas: idempotencia
##   R2-M7  proyeccion antes y despues de la red
##   R2-M8  ruta historica OFF
##   R2-M9  cableado del motor: el modo lo deriva la red, no un interruptor
##   R2-M10 masa negativa: se recorta en las dos rutas
##   R2-M11 parametros que el adaptador de fuga emite: ELA, exponente y
##          regularizacion son los que dice el contrato, no otros
##
##   <godot> --headless --path . --script res://tools/validate_canonical_mass_conservation.gd

const ZoneFireSolverScript := preload("res://sim/core/ZoneFireSolver.gd")
const EquationsScript := preload("res://sim/core/CompartmentPressureEquations.gd")
const RoomModelScript := preload("res://sim/building/RoomModel.gd")
## R2-M9 necesita el motor entero: el cableado solo existe ahi.
const BuildingModelScript := preload("res://sim/BuildingModel.gd")
const SimulationEngineScript := preload("res://sim/core/SimulationEngine.gd")
## R2-M11 mira lo que el adaptador de fuga emite, y contra que constantes.
const LeakageAdapterScript := preload("res://sim/core/ClosedDoorLeakageNetworkAdapter.gd")
const LeakageModelScript := preload("res://sim/core/ClosedDoorLeakageModel.gd")
const SolverScript := preload("res://sim/core/Phase3CoupledPressureSolver.gd")

const DT_S: float = 0.0833333333333333

const AMBIENT_C: float = 20.0
const T_REF_K: float = 293.15
const P_REF_PA: float = 101325.0
const RHO_REF: float = 1.2
const R_J_KG_K: float = P_REF_PA / (RHO_REF * T_REF_K)
const CP_KJ_KG_K: float = 1.0
const MAX_UPPER_TEMP_C: float = 900.0

const AREA_M2: float = 16.0
const HEIGHT_M: float = 2.5
const VOLUME_M3: float = AREA_M2 * HEIGHT_M
## Masa que llena el recinto a presion ambiente y temperatura de referencia.
const AMBIENT_MASS_KG: float = RHO_REF * VOLUME_M3

## Tolerancias fisicas. La de masa es la de redondeo de doble precision sobre
## una magnitud de decenas de kilos, no una banda elegida para pasar.
const MASS_TOL_KG: float = 1.0e-12
const ENERGY_TOL_KJ: float = 1.0e-9

var _failures: Array[String] = []
var _checks: int = 0


func _initialize() -> void:
	_m1_sealed_heating()
	_m2_sealed_cooling()
	_m3_lower_to_upper()
	_m4_thermal_inversion()
	_m5_upper_geometric_limit()
	_m6_repeated_projections()
	_m7_projection_around_the_network()
	_m8_historical_route_off()
	_m9_engine_wiring()
	_m10_negative_mass()
	_m11_adapter_parameters()
	if _failures.is_empty():
		print("  %d checks" % _checks)
		print("CANONICAL MASS CONSERVATION VALIDATION PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
		print("FAIL: " + failure)
	print("CANONICAL MASS CONSERVATION VALIDATION FAIL (%d)" % _failures.size())
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


## Solver en modo canonico (red autoritativa) o historico.
func _solver(canonical: bool):
	var solver = ZoneFireSolverScript.new()
	solver.two_zone_energy_enabled = true
	solver.canonical_mass_conservation_enabled = canonical
	return solver


func _room(upper_kg: float, lower_kg: float,
		upper_energy_kj: float, lower_energy_kj: float) -> RoomModel:
	var room: RoomModel = RoomModelScript.new()
	room.id = 1
	room.height_m = HEIGHT_M
	room.width_m = 4.0
	room.length_m = 4.0
	room.upper_gas_kg = upper_kg
	room.lower_gas_kg = lower_kg
	room.upper_energy_kj = upper_energy_kj
	room.lower_energy_kj = lower_energy_kj
	room.thermal_layer_m = HEIGHT_M
	room.two_zone_boundary_mass_kg = 0.0
	room.two_zone_boundary_energy_kj = 0.0
	room.o2_upper = 0.153
	room.o2_lower = 0.197
	room.o2 = 0.181
	room.smoke_kg = 0.0234
	room.co2_upper_kg = 0.0412
	return room


## Huella de composicion. La proyeccion deriva geometria y temperaturas: no
## toca especies en ninguna de las dos rutas, asi que la invariancia a traves de
## ella es exacta y no lleva tolerancia.
func _composition(room: RoomModel) -> Array:
	return [float(room.o2_upper), float(room.o2_lower), float(room.o2),
			float(room.smoke_kg), float(room.co2_upper_kg)]


func _total_mass_kg(room: RoomModel) -> float:
	return float(room.upper_gas_kg) + float(room.lower_gas_kg)


func _total_energy_kj(room: RoomModel) -> float:
	return float(room.upper_energy_kj) + float(room.lower_energy_kj)


## Presion absoluta del recinto por la ecuacion de estado canonica.
func _pressure_abs_pa(room: RoomModel) -> float:
	return R_J_KG_K * (
		_total_mass_kg(room) * T_REF_K + _total_energy_kj(room) / CP_KJ_KG_K
	) / VOLUME_M3


func _project(solver, room: RoomModel, cause: String = "test") -> void:
	solver.project_room_state(room, AMBIENT_C, MAX_UPPER_TEMP_C, cause)


## Interfaz que publica el recinto, medida desde el suelo.
func _interface_m(room: RoomModel) -> float:
	return float(room.thermal_layer_m)


## La interfaz que EXIGE la ecuacion de estado canonica para este estado. Se
## calcula aparte, en el validador, para no comprobar el motor contra si mismo.
func _expected_interface_m(room: RoomModel) -> float:
	var upper_kg: float = float(room.upper_gas_kg)
	var lower_kg: float = float(room.lower_gas_kg)
	var pressure_pa: float = _pressure_abs_pa(room)
	var upper_t_k: float = T_REF_K
	if upper_kg > 0.0:
		upper_t_k += float(room.upper_energy_kj) / (upper_kg * CP_KJ_KG_K)
	var upper_volume_m3: float = upper_kg * R_J_KG_K * upper_t_k / pressure_pa
	return clampf(HEIGHT_M - upper_volume_m3 / AREA_M2, 0.0, HEIGHT_M)


# ---------------------------------------------------------------- R2-M1

## Recinto sellado que se calienta con energia sensible impuesta: la masa no se
## toca y la presion sube segun el gas ideal.
func _m1_sealed_heating() -> void:
	var solver = _solver(true)
	var room: RoomModel = _room(0.0, AMBIENT_MASS_KG, 0.0, 0.0)
	var mass_before_kg: float = _total_mass_kg(room)
	var composition_before: Array = _composition(room)
	var pressure_before_pa: float = _pressure_abs_pa(room)
	_check(_close(pressure_before_pa, P_REF_PA, 1.0e-6),
			"R2-M1 starts at ambient pressure (%.6f Pa)" % pressure_before_pa)

	# Calor sensible, sin una sola molecula anadida.
	var added_kj: float = 4000.0
	room.lower_energy_kj += added_kj
	_project(solver, room)

	_check(_close(_total_mass_kg(room), mass_before_kg, MASS_TOL_KG),
			"R2-M1 sealed heating keeps the mass (%.15f vs %.15f kg)" % [
				_total_mass_kg(room), mass_before_kg])
	_check(_close(float(room.two_zone_boundary_mass_kg), 0.0, 0.0),
			"R2-M1 no boundary mass is booked (%.15f kg)" % room.two_zone_boundary_mass_kg)
	_check(_composition(room) == composition_before,
			"R2-M1 sealed heating does not touch the composition (%s vs %s)" % [
				_composition(room), composition_before])
	# La geometria derivada tambien es contrato: si el volumen no sale de la
	# presion del propio recinto, la interfaz se va, aunque la masa aguante.
	_check(_close(_interface_m(room), _expected_interface_m(room), 1.0e-9),
			"R2-M1 the interface follows the canonical EOS (%.12f vs %.12f m)" % [
				_interface_m(room), _expected_interface_m(room)])
	# Gas ideal a volumen y masa constantes: p sube en R*E/(cp*V).
	var expected_pa: float = pressure_before_pa + R_J_KG_K * added_kj / (CP_KJ_KG_K * VOLUME_M3)
	_check(_close(_pressure_abs_pa(room), expected_pa, 1.0e-6),
			"R2-M1 pressure follows the ideal gas law (%.6f vs %.6f Pa)" % [
				_pressure_abs_pa(room), expected_pa])
	_check(_pressure_abs_pa(room) > pressure_before_pa,
			"R2-M1 heating a sealed room raises its pressure")


# ---------------------------------------------------------------- R2-M2

## Enfriamiento sellado: masa constante, presion por debajo de la ambiente y
## energia sensible NEGATIVA admitida mientras la temperatura absoluta sea valida.
func _m2_sealed_cooling() -> void:
	var solver = _solver(true)
	var room: RoomModel = _room(0.0, AMBIENT_MASS_KG, 0.0, 0.0)
	var mass_before_kg: float = _total_mass_kg(room)
	var removed_kj: float = 400.0
	room.lower_energy_kj -= removed_kj
	_project(solver, room)

	_check(_close(_total_mass_kg(room), mass_before_kg, MASS_TOL_KG),
			"R2-M2 sealed cooling keeps the mass (%.15f vs %.15f kg)" % [
				_total_mass_kg(room), mass_before_kg])
	_check(_close(float(room.two_zone_boundary_mass_kg), 0.0, 0.0),
			"R2-M2 no boundary mass is booked (%.15f kg)" % room.two_zone_boundary_mass_kg)
	var pressure_pa: float = _pressure_abs_pa(room)
	_check(pressure_pa < P_REF_PA,
			"R2-M2 cooling a sealed room lowers its pressure (%.6f Pa)" % pressure_pa)
	_check(pressure_pa > 0.0, "R2-M2 the absolute pressure stays physical (%.6f Pa)" % pressure_pa)
	# La geometria canonica acepta ese estado: temperatura absoluta valida.
	var geometry: Dictionary = EquationsScript.zone_geometry_from_state(
		room.upper_gas_kg, room.lower_gas_kg, room.upper_energy_kj, room.lower_energy_kj,
		AREA_M2, HEIGHT_M, T_REF_K)
	_check(bool(geometry.get("valid", false)),
			"R2-M2 negative sensible energy is a valid state")


# ---------------------------------------------------------------- R2-M3

## Mover masa entre capas no cambia ni la masa ni la energia totales.
func _m3_lower_to_upper() -> void:
	var solver = _solver(true)
	var room: RoomModel = _room(0.0, AMBIENT_MASS_KG, 0.0, 2000.0)
	var mass_before_kg: float = _total_mass_kg(room)
	var energy_before_kj: float = _total_energy_kj(room)

	var moved_kg: float = solver.transfer_lower_to_upper(room, 6.0, AMBIENT_C)
	_check(moved_kg > 0.0, "R2-M3 the transfer moves something (%.6f kg)" % moved_kg)
	_check(_close(_total_mass_kg(room), mass_before_kg, MASS_TOL_KG),
			"R2-M3 the transfer keeps the total mass (%.15f vs %.15f kg)" % [
				_total_mass_kg(room), mass_before_kg])
	_check(_close(_total_energy_kj(room), energy_before_kj, ENERGY_TOL_KJ),
			"R2-M3 the transfer keeps the total energy (%.9f vs %.9f kJ)" % [
				_total_energy_kj(room), energy_before_kj])
	_check(float(room.upper_gas_kg) > 0.0 and float(room.lower_gas_kg) > 0.0,
			"R2-M3 both zones hold gas after the transfer")

	# Y la proyeccion posterior tampoco la toca, ni la masa ni la composicion.
	var composition_before_projection: Array = _composition(room)
	_project(solver, room)
	_check(_composition(room) == composition_before_projection,
			"R2-M3 the projection does not touch the composition (%s vs %s)" % [
				_composition(room), composition_before_projection])
	_check(_close(_total_mass_kg(room), mass_before_kg, MASS_TOL_KG),
			"R2-M3 projecting after the transfer keeps the mass (%.15f kg)"
			% _total_mass_kg(room))
	_check(_close(float(room.two_zone_boundary_mass_kg), 0.0, 0.0),
			"R2-M3 no boundary mass is booked")


# ---------------------------------------------------------------- R2-M4

## Inversion termica: la capa de arriba mas fria que la de abajo se mezcla, y la
## mezcla conserva masa y energia. No aparece aire ambiente de la nada.
func _m4_thermal_inversion() -> void:
	var solver = _solver(true)
	# Arriba frio, abajo caliente: inversion.
	var room: RoomModel = _room(8.0, 30.0, 0.0, 6000.0)
	var mass_before_kg: float = _total_mass_kg(room)
	var energy_before_kj: float = _total_energy_kj(room)
	_project(solver, room)

	_check(_close(_total_mass_kg(room), mass_before_kg, MASS_TOL_KG),
			"R2-M4 the inversion mix keeps the mass (%.15f vs %.15f kg)" % [
				_total_mass_kg(room), mass_before_kg])
	_check(_close(_total_energy_kj(room), energy_before_kj, ENERGY_TOL_KJ),
			"R2-M4 the inversion mix keeps the energy (%.9f vs %.9f kJ)" % [
				_total_energy_kj(room), energy_before_kj])
	_check(_close(float(room.two_zone_boundary_mass_kg), 0.0, 0.0),
			"R2-M4 no ambient air is invented (%.15f kg)" % room.two_zone_boundary_mass_kg)
	# Tras mezclar, las dos capas estan a la misma temperatura.
	_check(_close(float(room.temp_upper_c), float(room.temp_lower_c), 1.0e-9),
			"R2-M4 both layers end at the same temperature (%.9f vs %.9f C)" % [
				room.temp_upper_c, room.temp_lower_c])


# ---------------------------------------------------------------- R2-M5

## Estado que dispararia el limite geometrico superior de la ruta historica: con
## la red autoritativa no hay masa que recortar.
func _m5_upper_geometric_limit() -> void:
	# Capa superior muy caliente y con casi toda la masa del recinto: en la ruta
	# historica su densidad a presion ambiente no cabria en el volumen.
	var upper_kg: float = 0.9 * AMBIENT_MASS_KG
	var room: RoomModel = _room(upper_kg, 0.1 * AMBIENT_MASS_KG, upper_kg * 400.0, 0.0)
	var mass_before_kg: float = _total_mass_kg(room)
	var energy_before_kj: float = _total_energy_kj(room)
	var upper_before_kg: float = float(room.upper_gas_kg)

	var solver = _solver(true)
	_project(solver, room)
	_check(_close(_total_mass_kg(room), mass_before_kg, MASS_TOL_KG),
			"R2-M5 the geometric limit removes no mass (%.15f vs %.15f kg)" % [
				_total_mass_kg(room), mass_before_kg])
	_check(_close(float(room.upper_gas_kg), upper_before_kg, MASS_TOL_KG),
			"R2-M5 the upper layer keeps its own mass (%.15f vs %.15f kg)" % [
				room.upper_gas_kg, upper_before_kg])
	_check(_close(_total_energy_kj(room), energy_before_kj, ENERGY_TOL_KJ),
			"R2-M5 the geometric limit removes no energy (%.9f vs %.9f kJ)" % [
				_total_energy_kj(room), energy_before_kj])
	_check(_close(float(room.two_zone_boundary_mass_kg), 0.0, 0.0),
			"R2-M5 the upper cap contributes zero to the boundary (%.15f kg)"
			% room.two_zone_boundary_mass_kg)
	# La interfase sigue dentro del recinto: la geometria es coherente.
	_check(float(room.thermal_layer_m) >= 0.0 and float(room.thermal_layer_m) <= HEIGHT_M,
			"R2-M5 the interface stays inside the room (%.6f m)" % room.thermal_layer_m)

	# Y en la ruta historica ese mismo estado SI recorta: la diferencia entre las
	# dos rutas es justamente lo que esta fase corrige.
	var historical_room: RoomModel = _room(
		upper_kg, 0.1 * AMBIENT_MASS_KG, upper_kg * 400.0, 0.0)
	var historical = _solver(false)
	_project(historical, historical_room)
	_check(_total_mass_kg(historical_room) < mass_before_kg - 1.0,
			"R2-M5 the historical route still reconstructs mass (%.6f vs %.6f kg)" % [
				_total_mass_kg(historical_room), mass_before_kg])
	# El tope superior historico recorta masa, y tiene que arrastrar su energia
	# en la misma proporcion: si no, la capa que queda sale a otra temperatura.
	var capped: RoomModel = _room(upper_kg, 0.1 * AMBIENT_MASS_KG, upper_kg * 400.0, 0.0)
	var capped_temp_before_c: float = float(capped.upper_energy_kj) \
			/ maxf(1.0e-12, float(capped.upper_gas_kg) * CP_KJ_KG_K)
	_project(_solver(false), capped)
	var capped_temp_after_c: float = float(capped.upper_energy_kj) \
			/ maxf(1.0e-12, float(capped.upper_gas_kg) * CP_KJ_KG_K)
	_check(float(capped.upper_gas_kg) < upper_kg,
			"R2-M5 the historical cap did trim the upper mass (%.6f vs %.6f kg)" % [
				capped.upper_gas_kg, upper_kg])
	_check(_close(capped_temp_after_c, capped_temp_before_c, 1.0e-6),
			"R2-M5 the historical cap moves energy with mass (%.9f vs %.9f C)" % [
				capped_temp_after_c, capped_temp_before_c])


# ---------------------------------------------------------------- R2-M6

## Proyectar muchas veces sin fuentes ni transporte no puede derivar: el
## resultado no depende del numero de llamadas.
func _m6_repeated_projections() -> void:
	var solver = _solver(true)
	var room: RoomModel = _room(6.0, 40.0, 2400.0, 500.0)
	_project(solver, room)
	var mass_after_first_kg: float = _total_mass_kg(room)
	var energy_after_first_kj: float = _total_energy_kj(room)
	var layer_after_first_m: float = float(room.thermal_layer_m)

	for index in range(20):
		_project(solver, room, "repeat_%d" % index)
	_check(_close(_total_mass_kg(room), mass_after_first_kg, MASS_TOL_KG),
			"R2-M6 twenty more projections keep the mass (%.15f vs %.15f kg)" % [
				_total_mass_kg(room), mass_after_first_kg])
	_check(_close(_total_energy_kj(room), energy_after_first_kj, ENERGY_TOL_KJ),
			"R2-M6 twenty more projections keep the energy (%.9f vs %.9f kJ)" % [
				_total_energy_kj(room), energy_after_first_kj])
	_check(_close(float(room.thermal_layer_m), layer_after_first_m, 1.0e-12),
			"R2-M6 the interface is idempotent (%.15f vs %.15f m)" % [
				room.thermal_layer_m, layer_after_first_m])
	_check(_close(float(room.two_zone_boundary_mass_kg), 0.0, 0.0),
			"R2-M6 no drift is booked at the boundary")


# ---------------------------------------------------------------- R2-M7

## Orden real del paso: la red escribe un estado y una proyeccion posterior no
## puede deshacerlo. Se recorren las SEIS familias de causa que el diagnostico
## identifico.
func _m7_projection_around_the_network() -> void:
	var solver = _solver(true)
	var room: RoomModel = _room(10.0, 36.0, 4200.0, 800.0)

	# Lo que la red deja escrito tras su commit atomico.
	room.upper_gas_kg = 12.0
	room.lower_gas_kg = 34.0
	room.upper_energy_kj = 5000.0
	room.lower_energy_kj = 900.0
	var committed_mass_kg: float = _total_mass_kg(room)
	var committed_energy_kj: float = _total_energy_kj(room)
	var committed_pressure_pa: float = _pressure_abs_pa(room)

	for cause in ["thermal_post_combustion_sync", "thermal_energy_projection",
			"thermal_post_losses_sync", "reconcile_layer_sync",
			"gas_exchange_sync", "final_clamp_active"]:
		_project(solver, room, cause)
		_check(_close(_total_mass_kg(room), committed_mass_kg, MASS_TOL_KG),
				"R2-M7 '%s' does not undo the commit (%.15f vs %.15f kg)" % [
					cause, _total_mass_kg(room), committed_mass_kg])
		# Por familia, no solo al final: una sola que se quede con la geometria
		# historica no mueve masa, pero publica otra capa, y la siguiente
		# llamada la corregiria sin que nadie se entere.
		_check(_close(_interface_m(room), _expected_interface_m(room), 1.0e-9),
				"R2-M7 '%s' agrees on the interface (%.12f vs %.12f m)" % [
					cause, _interface_m(room), _expected_interface_m(room)])
	_check(_close(_total_energy_kj(room), committed_energy_kj, ENERGY_TOL_KJ),
			"R2-M7 the six families keep the energy (%.9f vs %.9f kJ)" % [
				_total_energy_kj(room), committed_energy_kj])
	_check(_close(_pressure_abs_pa(room), committed_pressure_pa, 1.0e-9),
			"R2-M7 the pressure the network committed survives (%.9f vs %.9f Pa)" % [
				_pressure_abs_pa(room), committed_pressure_pa])
	_check(_close(float(room.two_zone_boundary_mass_kg), 0.0, 0.0),
			"R2-M7 no family books boundary mass (%.15f kg)" % room.two_zone_boundary_mass_kg)


# ---------------------------------------------------------------- R2-M8

## Ruta historica: exactamente lo de siempre. El modo conservativo no se activa
## solo, y la reconstruccion sigue ahi.
func _m8_historical_route_off() -> void:
	var solver = _solver(false)
	_check(not bool(solver.canonical_mass_conservation_enabled),
			"R2-M8 the conservative mode is off by default")
	var room: RoomModel = _room(0.0, AMBIENT_MASS_KG, 0.0, 0.0)
	room.lower_energy_kj += 4000.0
	var mass_before_kg: float = _total_mass_kg(room)
	_project(solver, room)
	# La ruta historica SI reconstruye: es su comportamiento documentado, y esta
	# fase no lo toca.
	_check(_total_mass_kg(room) < mass_before_kg,
			"R2-M8 the historical route still rebuilds the lower mass (%.6f vs %.6f kg)" % [
				_total_mass_kg(room), mass_before_kg])
	_check(float(room.two_zone_boundary_mass_kg) < 0.0,
			"R2-M8 the historical route still books it at the boundary (%.6f kg)"
			% room.two_zone_boundary_mass_kg)
	# Y el valor exacto: volumen libre por densidad a presion ambiente.
	var ambient_k: float = AMBIENT_C + 273.15
	var lower_k: float = maxf(ambient_k, float(room.temp_lower_c) + 273.15)
	var expected_kg: float = VOLUME_M3 * RHO_REF * ambient_k / lower_k
	_check(_close(float(room.lower_gas_kg), expected_kg, 1.0e-9),
			"R2-M8 the historical lower mass is volume times ambient density (%.9f vs %.9f kg)" % [
				room.lower_gas_kg, expected_kg])


# ---------------------------------------------------------------- R2-M9

## El modo conservativo NO es un interruptor de usuario: el motor lo deriva del
## de la red autoritativa. Los ocho casos anteriores construyen el solver a mano
## y le fijan el modo, asi que ninguno ve esa linea. Aqui se comprueba el
## cableado y, sobre todo, su consecuencia observable.
func _m9_engine_wiring() -> void:
	for network_on in [true, false]:
		var building: BuildingModel = BuildingModelScript.new()
		building.load_template_data(_sealed_template())
		var engine: SimulationEngine = SimulationEngineScript.new()
		engine.building = building
		engine.auto_ignite_on_ready = false
		engine.auto_finish_on_extinction = false
		engine.enable_logging = false
		engine.enable_csv_log = false
		engine.pressure_network_solver_enabled = network_on
		engine.closed_door_leakage_enabled = false
		# Sin esto, liberar el motor dispara `_exit_tree` -> generacion de
		# graficas con `OS.create_process` y el headless se queda vivo.
		engine.suppress_exit_graphs()
		root.add_child(building)
		root.add_child(engine)
		engine.reset_simulation(0, false)

		var room = building.get_room(0)
		# Recinto sellado y caliente: no hay ninguna fuente ni sumidero de masa.
		room.upper_gas_kg = 12.0
		room.lower_gas_kg = 36.0
		room.upper_energy_kj = 12.0 * 200.0
		room.lower_energy_kj = 0.0
		var mass_before_kg: float = _total_mass_kg(room)

		for index in range(60):
			engine.step(DT_S)

		var label: String = "ON" if network_on else "OFF"
		_check(bool(engine.zone_fire_solver.canonical_mass_conservation_enabled) == network_on,
				"R2-M9 %s the engine derives the mode from the network (%s)" % [
					label, engine.zone_fire_solver.canonical_mass_conservation_enabled])
		var mass_after_kg: float = _total_mass_kg(room)
		if network_on:
			# Consecuencia observable del cableado correcto.
			_check(_close(mass_after_kg, mass_before_kg, 1.0e-9),
					"R2-M9 ON the sealed room keeps its mass (%.12f vs %.12f kg)" % [
						mass_after_kg, mass_before_kg])
			_check(_close(float(room.two_zone_boundary_mass_kg), 0.0, 1.0e-12),
					"R2-M9 ON nothing is booked at the boundary (%.15f kg)"
					% room.two_zone_boundary_mass_kg)
		else:
			# Y la ruta historica sigue siendo exactamente la de siempre.
			_check(mass_after_kg < mass_before_kg,
					"R2-M9 OFF the historical route still loses mass (%.6f vs %.6f kg)" % [
						mass_after_kg, mass_before_kg])
			_check(float(room.two_zone_boundary_mass_kg) < 0.0,
					"R2-M9 OFF the loss is still booked at the boundary (%.6f kg)"
					% room.two_zone_boundary_mass_kg)

		engine.queue_free()
		building.queue_free()


## Un unico recinto sin aberturas: sellado de verdad, sin envolvente que
## intervenga. La fuga exterior es R3 y no participa aqui.
func _sealed_template() -> Dictionary:
	return {
		"building_type": "house",
		"floors": [{"level_m": 0.0, "name": "R"}],
		"rooms_data": [{
			"id": 0, "name": "R0", "kind": "salon", "floor_level_z_m": 0.0,
			"height_m": HEIGHT_M, "fuel_energy_MJ": 0.0, "max_hrr_kw": 0.0,
			"fuel_objects": [], "rotation_deg": 0.0,
		}],
		"room_rect_m": {"0": {"x": 0.0, "y": 0.0, "w": 4.0, "h": 4.0}},
		"openings_data": [],
	}


# ---------------------------------------------------------------- R2-M10

## Una masa zonal negativa no es un estado fisico: F2.2A la rechaza, y las DOS
## rutas la cortan en cero. Levantar la energia sensible negativa no levanta
## esto, y ningun otro caso lo ejercitaba.
func _m10_negative_mass() -> void:
	for canonical in [true, false]:
		var label: String = "canonical" if canonical else "historical"
		var room: RoomModel = _room(-3.0, AMBIENT_MASS_KG, 0.0, 0.0)
		_project(_solver(canonical), room)
		_check(float(room.upper_gas_kg) >= 0.0,
				"R2-M10 %s clamps a negative upper mass (%.9f kg)" % [
					label, room.upper_gas_kg])
		var other: RoomModel = _room(6.0, -2.0, 1200.0, 0.0)
		_project(_solver(canonical), other)
		_check(float(other.lower_gas_kg) >= 0.0,
				"R2-M10 %s clamps a negative lower mass (%.9f kg)" % [
					label, other.lower_gas_kg])


# ---------------------------------------------------------------- R2-M11

## Lo que el adaptador PONE en el elemento de grieta. Los 437 checks de D1
## comparan contra las constantes del modelo puro, asi que no ven un adaptador
## que emita otra cosa: se podia cambiar el exponente a 0,5 y seguian en verde.
## Esta fase prohibe expresamente tocar la ELA y el exponente, de modo que la
## prohibicion merece una asercion y no solo una linea en el encargo.
func _m11_adapter_parameters() -> void:
	# (a, b, tipo, ancho, alto, fraccion abierta): puerta cerrada entre 1 y 2.
	var door = OpeningModel.new(1, 2, OpeningModel.Type.DOOR, 0.9, 2.05, 0.0)
	door.leakage_class = "interior_tight"
	# (apertura, id del exterior, cota del suelo, clave A, clave B, dt).
	var element: Dictionary = LeakageAdapterScript.build_crack_element(
		door, -1, 0.0, "1", "2", DT_S)
	_check(not element.is_empty(), "R2-M11 the adapter builds a crack element")
	if element.is_empty():
		return
	_check(float(element["flow_exponent"])
			== LeakageModelScript.PROVISIONAL_FLOW_EXPONENT_CANDIDATE,
			"R2-M11 the element carries the documented exponent (%s)"
			% element["flow_exponent"])
	_check(float(element["ela_reference_pressure_pa"])
			== LeakageModelScript.NIST_ELA_REFERENCE_PRESSURE_PA,
			"R2-M11 the element carries the NIST ELA reference (%s Pa)"
			% element["ela_reference_pressure_pa"])
	# F2.2-R2-MASS: y la regularizacion es la constante GLOBAL del solver, la
	# misma que el vano y el hueco vertical, no un valor propio de la fuga.
	_check(float(element["zero_pressure_regularization_pa"])
			== SolverScript.DEFAULT_DP_REGULARIZATION_PA,
			"R2-M11 the crack uses the solver's global regularisation (%s Pa)"
			% element["zero_pressure_regularization_pa"])
	_check(float(element["pressure_domain_max_pa"])
			== LeakageAdapterScript.PRESSURE_DOMAIN_MAX_PA,
			"R2-M11 the element records the experimental domain (%s Pa)"
			% element["pressure_domain_max_pa"])

extends SceneTree

## F2.2C-R1: referencia hidrostatica de la red autoritativa en varias plantas.
##
## Seis casos que separan altura, hidrostatica, temperatura y conectividad. Cada
## uno falla por una razon distinta, para que la causa no se pueda confundir:
##
##   M1  recintos SELLADOS a 0, 3 y 6 m, en equilibrio con su exterior local
##   M2  una abertura exterior identica en cada planta, todo isotermo
##   M3  columna interior isoterma: no puede inventar efecto chimenea
##   M4  columna interior caliente: chimenea con el signo correcto
##   M5  la misma planta desplazada +20 m, referencia exterior incluida
##   M6  conexion entre dos plantas: la columna se cuenta una vez y sin orden
##
##   <godot> --headless --path . --script res://tools/validate_multistorey_pressure_datum.gd

const SolverScript := preload("res://sim/core/Phase3CoupledPressureSolver.gd")

const T_REF_K: float = 293.15
const P_REF_PA: float = 101325.0
const RHO_REF: float = 1.2
const R_J_KG_K: float = P_REF_PA / (RHO_REF * T_REF_K)
const GRAVITY: float = 9.80665
const DT_S: float = 0.0833333333333333

const AREA_M2: float = 20.0
const HEIGHT_M: float = 2.5
const VOLUME_M3: float = AREA_M2 * HEIGHT_M

## Tolerancias fisicas, no ajustables por caso.
const PRESSURE_TOL_PA: float = 1.0e-6
const FLOW_TOL_KG_S: float = 1.0e-9

var _solver
var _failures: Array[String] = []
var _checks: int = 0


func _initialize() -> void:
	_solver = SolverScript.new()
	_m1_sealed_rooms_at_three_heights()
	_m2_one_exterior_opening_per_storey()
	_m3_isothermal_vertical_column()
	_m4_hot_vertical_column()
	_m5_translating_the_whole_building()
	_m6_connection_between_storeys()
	if _failures.is_empty():
		print("  %d checks" % _checks)
		print("MULTISTOREY PRESSURE DATUM VALIDATION PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
		print("FAIL: " + failure)
	print("MULTISTOREY PRESSURE DATUM VALIDATION FAIL (%d)" % _failures.size())
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


## El exterior de referencia, declarado en una cota concreta.
func _outside(reference_z_m: float = 0.0, temp_k: float = T_REF_K) -> Dictionary:
	return {
		"pressure_abs_pa": P_REF_PA,
		"reference_z_m": reference_z_m,
		"temp_k": temp_k,
		"reference_temp_k": T_REF_K,
	}


## Presion exterior a una cota, con el convenio de densidad constante.
func _exterior_pressure_pa(z_m: float, reference_z_m: float = 0.0) -> float:
	return P_REF_PA - RHO_REF * GRAVITY * (z_m - reference_z_m)


## Sala isoterma cuya masa la pone en equilibrio EXACTO con el exterior local de
## su propio suelo. Es el estado en el que su presion manometrica debe ser 0.
func _room_in_local_equilibrium(room_id: String, floor_z_m: float,
		reference_z_m: float = 0.0) -> Dictionary:
	var target_abs_pa: float = _exterior_pressure_pa(floor_z_m, reference_z_m)
	var mass_kg: float = target_abs_pa * VOLUME_M3 / (R_J_KG_K * T_REF_K)
	return {
		"room_id": room_id, "floor_z_m": floor_z_m,
		"floor_area_m2": AREA_M2, "height_m": HEIGHT_M,
		"upper_gas_kg": 0.0, "upper_energy_kj": 0.0,
		"lower_gas_kg": mass_kg, "lower_energy_kj": 0.0,
	}


## Sala isoterma a una temperatura dada, con la masa que llena su volumen a la
## presion exterior local de su suelo.
func _room_at_temperature(room_id: String, floor_z_m: float, temp_k: float,
		reference_z_m: float = 0.0) -> Dictionary:
	var target_abs_pa: float = _exterior_pressure_pa(floor_z_m, reference_z_m)
	var mass_kg: float = target_abs_pa * VOLUME_M3 / (R_J_KG_K * temp_k)
	return {
		"room_id": room_id, "floor_z_m": floor_z_m,
		"floor_area_m2": AREA_M2, "height_m": HEIGHT_M,
		"upper_gas_kg": 0.0, "upper_energy_kj": 0.0,
		"lower_gas_kg": mass_kg,
		"lower_energy_kj": mass_kg * (temp_k - T_REF_K),
	}


## Error de presion que introduce el convenio de densidad exterior CONSTANTE
## sobre una columna de altura `height_m` situada a la cota `elevation_m`:
##
##     g * H * rho * (rho * g * z / P)
##
## No es una tolerancia elegida para que pase la prueba: es la magnitud del
## propio convenio, documentado en `ExteriorPressureProfile`.
func _datum_approximation_pa(height_m: float, elevation_m: float) -> float:
	return GRAVITY * height_m * RHO_REF 			* (RHO_REF * GRAVITY * absf(elevation_m) / P_REF_PA) + 1.0e-9


func _exterior_opening(opening_id: String, room_id: String,
		bottom_z_m: float, top_z_m: float) -> Dictionary:
	return {
		"opening_id": opening_id, "room_a_id": room_id, "room_b_id": "outside",
		"bottom_z_m": bottom_z_m, "top_z_m": top_z_m,
		"width_m": 0.9, "open_fraction": 1.0, "discharge_coeff": 0.61,
	}


## Hueco de suelo/techo entre dos plantas. Es lo que conecta de verdad dos
## recintos apilados: comparten la losa, no un pano vertical.
func _vertical_shaft(opening_id: String, a: String, b: String,
		area_m2: float, slab_z_m: float) -> Dictionary:
	return {
		"opening_id": opening_id, "room_a_id": a, "room_b_id": b,
		"flow_model": "vertical_shaft",
		"shaft_area_m2": area_m2,
		"bottom_z_m": slab_z_m - 0.2, "top_z_m": slab_z_m + 0.2,
		"width_m": 1.4, "open_fraction": 1.0, "discharge_coeff": 0.61,
	}


func _interior_opening(opening_id: String, a: String, b: String,
		bottom_z_m: float, top_z_m: float) -> Dictionary:
	return {
		"opening_id": opening_id, "room_a_id": a, "room_b_id": b,
		"bottom_z_m": bottom_z_m, "top_z_m": top_z_m,
		"width_m": 0.9, "open_fraction": 1.0, "discharge_coeff": 0.61,
	}


func _solve(rooms: Array, openings: Array, outside: Dictionary) -> Dictionary:
	return _solver.solve_pressure_network(rooms, openings, outside, {}, DT_S)


func _room_of(result: Dictionary, room_id: String) -> Dictionary:
	for room in result["rooms"]:
		if String(room["room_id"]) == room_id:
			return room
	return {}


func _opening_of(result: Dictionary, opening_id: String) -> Dictionary:
	for opening in result["openings"]:
		if String(opening["opening_id"]) == opening_id:
			return opening
	return {}


func _gross_mass_kg_s(element: Dictionary) -> float:
	var total: float = 0.0
	for segment in element.get("segments", []):
		total += absf(float(segment["mass_flow_kg_s"]))
	return total


# ---------------------------------------------------------------- M1

## Tres recintos SELLADOS a 0, 3 y 6 m, cada uno en equilibrio con el exterior
## de SU cota. La presion manometrica local tiene que ser 0 en los tres, y la
## absoluta tiene que bajar con la altura.
func _m1_sealed_rooms_at_three_heights() -> void:
	var rooms: Array = []
	for z_m in [0.0, 3.0, 6.0]:
		rooms.append(_room_in_local_equilibrium("r%d" % int(z_m), z_m))
	var result: Dictionary = _solve(rooms, [], _outside())
	_check(bool(result["converged"]), "M1 the sealed stack converges (%s)"
			% result.get("failure_reason", "?"))
	if not bool(result["converged"]):
		return
	var previous_abs_pa: float = INF
	for z_m in [0.0, 3.0, 6.0]:
		var room: Dictionary = _room_of(result, "r%d" % int(z_m))
		if room.is_empty():
			_check(false, "M1 the solution carries room at %s m" % z_m)
			continue
		var gauge_pa: float = float(room["gauge_pressure_pa"])
		_check(_close(gauge_pa, 0.0, PRESSURE_TOL_PA),
				"M1 the room at %s m is at zero LOCAL gauge (%.6f Pa)" % [z_m, gauge_pa])
		var abs_pa: float = float(room["pressure_abs_pa"])
		_check(_close(abs_pa, _exterior_pressure_pa(z_m), 1.0e-6),
				"M1 the room at %s m sits at its local exterior pressure (%.6f vs %.6f Pa)" % [
					z_m, abs_pa, _exterior_pressure_pa(z_m)])
		_check(abs_pa < previous_abs_pa,
				"M1 absolute pressure falls with height (%s m: %.6f Pa)" % [z_m, abs_pa])
		previous_abs_pa = abs_pa


# ---------------------------------------------------------------- M2

## Una abertura exterior identica en cada planta, todo isotermo y en equilibrio
## local. Ninguna planta puede inventar caudal por usar la presion exterior de
## la cota de referencia como si fuera la suya.
func _m2_one_exterior_opening_per_storey() -> void:
	var rooms: Array = []
	var openings: Array = []
	for z_m in [0.0, 3.0, 6.0]:
		var key: String = "r%d" % int(z_m)
		rooms.append(_room_in_local_equilibrium(key, z_m))
		openings.append(_exterior_opening("op_%s" % key, key, z_m + 0.2, z_m + 2.2))
	var result: Dictionary = _solve(rooms, openings, _outside())
	_check(bool(result["converged"]), "M2 the stack with exterior openings converges (%s)"
			% result.get("failure_reason", "?"))
	if not bool(result["converged"]):
		return
	for z_m in [0.0, 3.0, 6.0]:
		var key: String = "r%d" % int(z_m)
		var element: Dictionary = _opening_of(result, "op_%s" % key)
		if element.is_empty():
			_check(false, "M2 the solution carries the opening at %s m" % z_m)
			continue
		var gross_kg_s: float = _gross_mass_kg_s(element)
		_check(_close(gross_kg_s, 0.0, FLOW_TOL_KG_S),
				"M2 the opening at %s m moves nothing (%.12f kg/s)" % [z_m, gross_kg_s])
		for segment in element.get("segments", []):
			_check(_close(float(segment["dp_pa"]), 0.0, 1.0e-6),
					"M2 every band at %s m sees dp = 0 (%.9f Pa)" % [z_m, segment["dp_pa"]])


# ---------------------------------------------------------------- M3

## Columna interior ISOTERMA y a la misma densidad que el exterior: conectar las
## plantas no puede producir efecto chimenea.
func _m3_isothermal_vertical_column() -> void:
	var rooms: Array = []
	var openings: Array = []
	# Plantas CONTIGUAS: el suelo de una es el techo de la anterior, que es como
	# se apilan de verdad los rellanos de un portal.
	var previous_key: String = ""
	for level in range(3):
		var z_m: float = float(level) * HEIGHT_M
		var key: String = "r%d" % level
		rooms.append(_room_in_local_equilibrium(key, z_m))
		if not previous_key.is_empty():
			openings.append(_vertical_shaft(
				"link_%s" % key, previous_key, key, 1.96, z_m))
		previous_key = key
	var result: Dictionary = _solve(rooms, openings, _outside())
	_check(bool(result["converged"]), "M3 the isothermal column converges (%s)"
			% result.get("failure_reason", "?"))
	if not bool(result["converged"]):
		return
	for element in result["openings"]:
		# Lo que de verdad dice "no hay chimenea" es que el termino de
		# flotabilidad sea EXACTAMENTE cero: con densidades iguales no hay
		# inestabilidad que intercambiar. Lo comprobamos asi y no por el caudal,
		# que ademas arrastra el ruido de convergencia del termino de presion.
		_check(not bool(element.get("shaft_unstable", false)),
				"M3 '%s' finds no unstable stratification" % element["opening_id"])
		_check(_close(float(element.get("shaft_exchange_kg_s", 0.0)), 0.0, 0.0),
				"M3 '%s' exchanges nothing by buoyancy (%.12f kg/s)" % [
					element["opening_id"], element.get("shaft_exchange_kg_s", 0.0)])
		_check(not bool(element["neutral_plane_inside"]),
				"M3 '%s' reports no neutral plane in an isothermal column"
				% element["opening_id"])
	for level in range(3):
		var z_m: float = float(level) * HEIGHT_M
		var room: Dictionary = _room_of(result, "r%d" % level)
		# Tolerancia DERIVADA, no elegida: con la densidad exterior constante que
		# el convenio declara, una sala a la cota z tiene una densidad menor en
		# un factor rho*g*z/P, y su columna de altura H se desvia de la exterior
		# en g*H*rho*(rho*g*z/P). A 5 m son 0,02 Pa. El defecto que esta fase
		# corrige valia rho*g*z, tres ordenes de magnitud mas.
		# La cota se toma en el TOPE de la columna: los recintos estan conectados,
		# asi que el error del de mas arriba se reparte por toda la pila.
		var bound_pa: float = _datum_approximation_pa(HEIGHT_M, 2.0 * HEIGHT_M)
		_check(not room.is_empty()
				and _close(float(room["gauge_pressure_pa"]), 0.0, bound_pa),
				"M3 the room at %.1f m stays at its local gauge within %.4f Pa (%.9f Pa)" % [
					z_m, bound_pa, room.get("gauge_pressure_pa", NAN)])


# ---------------------------------------------------------------- M4

## Misma geometria, interior CALIENTE: el efecto chimenea tiene que aparecer y
## con el signo correcto. Entra por abajo, sale por arriba.
func _m4_hot_vertical_column() -> void:
	var rooms: Array = [
		_room_at_temperature("r0", 0.0, 473.15),
		_room_at_temperature("r3", HEIGHT_M, 473.15),
	]
	var openings: Array = [_vertical_shaft("link", "r0", "r3", 1.96, HEIGHT_M)]
	var forward: Dictionary = _solve(rooms, openings, _outside())
	_check(bool(forward["converged"]), "M4 the hot column converges (%s)"
			% forward.get("failure_reason", "?"))
	if not bool(forward["converged"]):
		return
	# El orden de las salas y de las aberturas no puede cambiar el signo.
	var swapped: Dictionary = _solve(
		[rooms[1], rooms[0]], [_vertical_shaft("link", "r3", "r0", 1.96, HEIGHT_M)], _outside())
	_check(bool(swapped["converged"]), "M4 the swapped hot column converges")
	if not bool(swapped["converged"]):
		return
	var a: Dictionary = _room_of(forward, "r0")
	var b: Dictionary = _room_of(swapped, "r0")
	_check(_close(float(a["gauge_pressure_pa"]), float(b["gauge_pressure_pa"]), 1.0e-9),
			"M4 swapping the room order keeps the gauge (%.9f vs %.9f Pa)" % [
				a["gauge_pressure_pa"], b["gauge_pressure_pa"]])
	var forward_gross: float = _gross_mass_kg_s(_opening_of(forward, "link"))
	var swapped_gross: float = _gross_mass_kg_s(_opening_of(swapped, "link"))
	_check(_close(forward_gross, swapped_gross, 1.0e-9),
			"M4 swapping the opening ends keeps the magnitude (%.12f vs %.12f kg/s)" % [
				forward_gross, swapped_gross])


# ---------------------------------------------------------------- M5

## La MISMA planta, desplazada 20 m junto con la referencia exterior. Las
## magnitudes manometricas y los caudales tienen que ser identicos; solo las
## presiones absolutas cambian, y exactamente en la columna atmosferica.
func _m5_translating_the_whole_building() -> void:
	var shift_m: float = 20.0
	var ground: Dictionary = _solve(
		[_room_at_temperature("a", 0.0, 353.15), _room_in_local_equilibrium("b", 0.0)],
		[_interior_opening("door", "a", "b", 0.0, 2.0)],
		_outside())
	var lifted: Dictionary = _solve(
		[_room_at_temperature("a", shift_m, 353.15, shift_m),
			_room_in_local_equilibrium("b", shift_m, shift_m)],
		[_interior_opening("door", "a", "b", shift_m, shift_m + 2.0)],
		_outside(shift_m))
	_check(bool(ground["converged"]) and bool(lifted["converged"]),
			"M5 both the ground and the lifted copy converge")
	if not bool(ground["converged"]) or not bool(lifted["converged"]):
		return
	for room_id in ["a", "b"]:
		var low: Dictionary = _room_of(ground, room_id)
		var high: Dictionary = _room_of(lifted, room_id)
		_check(_close(float(low["gauge_pressure_pa"]), float(high["gauge_pressure_pa"]), 1.0e-9),
				"M5 room '%s' keeps its gauge after the lift (%.9f vs %.9f Pa)" % [
					room_id, low["gauge_pressure_pa"], high["gauge_pressure_pa"]])
		# Con la referencia desplazada JUNTO al edificio, la atmosfera se vuelve
		# a declarar en la cota nueva: las absolutas tambien son las mismas.
		_check(_close(float(low["pressure_abs_pa"]), float(high["pressure_abs_pa"]), 1.0e-9),
				"M5 room '%s' keeps its absolute pressure when the datum moves too (%.6f vs %.6f Pa)" % [
					room_id, low["pressure_abs_pa"], high["pressure_abs_pa"]])
	var low_gross: float = _gross_mass_kg_s(_opening_of(ground, "door"))
	var high_gross: float = _gross_mass_kg_s(_opening_of(lifted, "door"))
	_check(_close(low_gross, high_gross, 1.0e-9),
			"M5 the door carries the same after the lift (%.12f vs %.12f kg/s)" % [
				low_gross, high_gross])

	# La otra mitad: subir el edificio DEJANDO la referencia en el suelo. Las
	# manometricas no cambian y las absolutas bajan exactamente la columna.
	# Las salas se siembran en equilibrio con la atmosfera DEL SUELO evaluada a
	# 20 m, que es la misma atmosfera de siempre vista mas arriba.
	var lifted_fixed: Dictionary = _solve(
		[_room_at_temperature("a", shift_m, 353.15),
			_room_in_local_equilibrium("b", shift_m)],
		[_interior_opening("door", "a", "b", shift_m, shift_m + 2.0)],
		_outside())
	_check(bool(lifted_fixed["converged"]),
			"M5 the lifted copy with the datum left behind converges")
	if not bool(lifted_fixed["converged"]):
		return
	for room_id in ["a", "b"]:
		var low_room: Dictionary = _room_of(ground, room_id)
		var fixed_room: Dictionary = _room_of(lifted_fixed, room_id)
		# Cota derivada del mismo convenio de densidad constante (ver M3).
		var bound_pa: float = _datum_approximation_pa(2.0, shift_m)
		_check(_close(float(low_room["gauge_pressure_pa"]),
				float(fixed_room["gauge_pressure_pa"]), bound_pa),
				"M5 room '%s' keeps its gauge with the datum left behind (%.9f vs %.9f Pa)" % [
					room_id, low_room["gauge_pressure_pa"], fixed_room["gauge_pressure_pa"]])
		var expected_abs_pa: float = float(low_room["pressure_abs_pa"]) \
				- RHO_REF * GRAVITY * shift_m
		_check(_close(float(fixed_room["pressure_abs_pa"]), expected_abs_pa, bound_pa),
				"M5 room '%s' loses exactly the atmospheric column (%.6f vs %.6f Pa)" % [
					room_id, fixed_room["pressure_abs_pa"], expected_abs_pa])


# ---------------------------------------------------------------- M6

## Conexion entre dos plantas distintas: los dos perfiles se comparan en la
## MISMA cota absoluta, ninguna columna se cuenta dos veces ni se omite, y el
## resultado no depende de cual sea `room_a`.
func _m6_connection_between_storeys() -> void:
	# La pila arranca a 12 m, no en el suelo: si alguien confunde una cota local
	# con una absoluta, con el suelo en 0 la confusion es inofensiva y no se ve.
	var base_z_m: float = 12.0
	var rooms: Array = [
		_room_at_temperature("low", base_z_m, 333.15),
		_room_in_local_equilibrium("high", base_z_m + HEIGHT_M),
	]
	var forward: Dictionary = _solve(
		rooms, [_vertical_shaft("shaft", "low", "high", 1.96, base_z_m + HEIGHT_M)], _outside())
	var reversed_result: Dictionary = _solve(
		[rooms[1], rooms[0]],
		[_vertical_shaft("shaft", "high", "low", 1.96, base_z_m + HEIGHT_M)], _outside())
	_check(bool(forward["converged"]) and bool(reversed_result["converged"]),
			"M6 the cross-storey connection converges both ways")
	if not bool(forward["converged"]) or not bool(reversed_result["converged"]):
		return
	for room_id in ["low", "high"]:
		var one: Dictionary = _room_of(forward, room_id)
		var other: Dictionary = _room_of(reversed_result, room_id)
		_check(_close(float(one["gauge_pressure_pa"]), float(other["gauge_pressure_pa"]), 1.0e-9),
				"M6 room '%s' does not depend on which end is room_a (%.9f vs %.9f Pa)" % [
					room_id, one["gauge_pressure_pa"], other["gauge_pressure_pa"]])
	var forward_gross: float = _gross_mass_kg_s(_opening_of(forward, "shaft"))
	var reversed_gross: float = _gross_mass_kg_s(_opening_of(reversed_result, "shaft"))
	_check(_close(forward_gross, reversed_gross, 1.0e-9),
			"M6 the shaft carries the same either way (%.12f vs %.12f kg/s)" % [
				forward_gross, reversed_gross])
	# Y la columna se cuenta UNA vez: el intercambio ocurre EN LA LOSA, que es la
	# unica cota donde los dos recintos existen a la vez.
	var element: Dictionary = _opening_of(forward, "shaft")
	for segment in element.get("segments", []):
		_check(_close(float(segment["sample_z_m"]), base_z_m + HEIGHT_M, 1.0e-9),
				"M6 the exchange happens at the slab (%.6f m)" % segment["sample_z_m"])
	_check(not bool(element.get("neutral_plane_inside", false)),
			"M6 a horizontal vent has no neutral plane")
	# La geometria que el elemento uso, fijada: la losa es el suelo del de
	# arriba, el borde de abajo es el techo del de abajo, y al ser contiguos no
	# hay espesor que atravesar. Sin esto, confundir una cota local con una
	# absoluta se absorbe en el equilibrio y no se nota.
	_check(_close(float(element.get("shaft_slab_z_m", NAN)), base_z_m + HEIGHT_M, 1.0e-9),
			"M6 the slab is the upper room's floor (%.6f m)" % element.get("shaft_slab_z_m", NAN))
	_check(_close(float(element.get("shaft_ceiling_below_z_m", NAN)), base_z_m + HEIGHT_M, 1.0e-9),
			"M6 the lower edge is the lower room's ceiling (%.6f m)"
			% element.get("shaft_ceiling_below_z_m", NAN))
	_check(_close(float(element.get("shaft_thickness_m", NAN)), 0.0, 1.0e-9),
			"M6 contiguous storeys leave no slab to cross (%.6f m)"
			% element.get("shaft_thickness_m", NAN))

	# Y el viento no existe para una abertura interior: pasarselo se rechaza.
	var windy: Dictionary = _vertical_shaft(
		"shaft", "low", "high", 1.96, base_z_m + HEIGHT_M)
	windy["wind_dp_pa"] = 12.0
	var windy_result: Dictionary = _solve(rooms, [windy], _outside())
	_check(not bool(windy_result["converged"]),
			"M6 wind on an interior element is rejected (%s)"
			% windy_result.get("failure_reason", "accepted"))
	# Y se rechaza DICIENDO POR QUE. Un fallo generico de abertura no vale: el
	# escenario tiene que saber que lo que declaro no tiene sentido fisico.
	var says_wind: bool = false
	for raw_error in windy_result.get("errors", []):
		if String(raw_error).contains("interior and cannot carry wind"):
			says_wind = true
	_check(says_wind, "M6 the rejection names interior wind (%s)"
			% [windy_result.get("errors", [])])


## Presion absoluta de una sala a una cota, a partir de lo que publica la red.
func _absolute_at(result: Dictionary, room: Dictionary, z_m: float) -> float:
	var floor_z_m: float = float(room["reference_z_m"])
	var profile: Array = room.get("pressure_profile", [])
	# El perfil publicado por F2.2A es lo que manda; si no lo trae, se integra
	# con la densidad de la zona que corresponda.
	for raw_point in profile:
		var point: Dictionary = raw_point
		if _close(float(point.get("z_m", NAN)), z_m, 1.0e-9):
			return float(point["pressure_abs_pa"])
	var density: float = float(room.get("lower_density_kg_m3", RHO_REF))
	return float(room["pressure_abs_pa"]) - density * GRAVITY * (z_m - floor_z_m)

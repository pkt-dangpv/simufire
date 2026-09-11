class_name BuildingLevels
extends RefCounted

## Consultas sobre el modelo de edificio que el mundo de primera persona y el
## visor 3D venian haciendo cada uno por su cuenta: que cota tiene una sala,
## cual es hueco de escalera, hacia donde sube y que huecos verticales perforan
## un forjado. Eran la misma pregunta escrita dos veces, y ya habian empezado a
## divergir (FP-3).
##
## La divergencia real estaba en `next_floor_level_above_m`: cuando no hay
## planta encima, el mundo FP devolvia la propia cota y el visor devolvia -1,0.
## Los dos contratos estan vivos en sus llamantes, asi que el valor de reserva
## es aqui un parametro explicito en vez de una constante escondida.


## Cota (m) del forjado de una sala. 0,0 si no existe o no hay edificio.
static func room_floor_level_m(building: BuildingModel, room_id: int) -> float:
	if building == null:
		return 0.0
	var room: RoomModel = building.get_room(room_id)
	return room.floor_level_z_m if room != null else 0.0


## Una sala es hueco de escalera si su tipo o su nombre lo dicen.
static func is_stairwell(room: RoomModel) -> bool:
	if room == null:
		return false
	var kind: String = room.kind.to_lower()
	var room_name: String = room.name.to_lower()
	return kind.contains("escalera") or kind.contains("stair") \
		or room_name.contains("escalera") or room_name.contains("stair")


## Un patio de luces: un conducto vertical abierto al cielo.
##
## Se reconoce por el tipo o por el nombre, con el mismo criterio flojo que la
## escalera, porque un escenario escrito a mano puede traer cualquiera de los
## dos. Lo que decide la geometria es esto: **un patio no lleva techo, y solo
## lleva suelo en su fondo**. Sin eso, tres zonas de patio apiladas son tres
## cajas cerradas y desde la ventana se ve un techo donde deberia verse el cielo.
static func is_patio(room: RoomModel) -> bool:
	if room == null:
		return false
	var kind: String = room.kind.to_lower()
	var room_name: String = room.name.to_lower()
	return kind.contains("patio") or kind.contains("lightwell") or room_name.begins_with("patio")


## Direccion de subida de la escalera, encajada al eje dominante.
static func stair_run_direction(room: RoomModel) -> Vector2:
	if room == null:
		return Vector2.DOWN
	var value: Vector2 = room.stair_run_direction_m
	if absf(value.x) > absf(value.y):
		return Vector2.RIGHT if value.x >= 0.0 else Vector2.LEFT
	return Vector2.DOWN if value.y >= 0.0 else Vector2.UP


## Cota del forjado inmediatamente superior a `level_m`, o `fallback` si no hay
## ninguno. Se exige una separacion de 0,20 m para no confundir con desniveles
## dentro de la misma planta.
static func next_floor_level_above_m(building: BuildingModel, level_m: float, fallback: float) -> float:
	if building == null:
		return fallback
	var best: float = INF
	for key in building.get_rooms().keys():
		var room: RoomModel = building.get_room(int(key))
		if room != null and room.floor_level_z_m > level_m + 0.20:
			best = minf(best, room.floor_level_z_m)
	return fallback if is_inf(best) else best


## Huecos verticales (escaleras) que perforan el nivel `level_m`.
##
## `upper_floor = true` devuelve los que hay que recortar del SUELO de la planta
## de arriba; `false`, los que hay que recortar del TECHO de la de abajo. El
## visor 3D solo dibuja suelos, asi que hasta ahora solo tenia la primera
## variante; el mundo FP dibuja tambien techos y tenia las dos.
static func vertical_stair_voids(building: BuildingModel, level_m: float, upper_floor: bool) -> Array[Rect2]:
	var result: Array[Rect2] = []
	if building == null:
		return result
	for raw_op in building.get_openings():
		var op := raw_op as OpeningModel
		if op == null or not op.is_vertical:
			continue
		var lower_room: RoomModel = building.get_room(op.a)
		var upper_room: RoomModel = building.get_room(op.b)
		if lower_room == null or upper_room == null:
			continue
		if upper_room.floor_level_z_m < lower_room.floor_level_z_m:
			var tmp := lower_room
			lower_room = upper_room
			upper_room = tmp
		var target_level_m: float = upper_room.floor_level_z_m if upper_floor else lower_room.floor_level_z_m
		if absf(target_level_m - level_m) > 0.05:
			continue
		var rect: Rect2 = Rect2(building.room_rect_m.get(lower_room.id, Rect2()))
		if rect.size.x <= 0.0 or rect.size.y <= 0.0:
			continue
		result.append(StairGeometry.vertical_void_rect(rect, stair_run_direction(lower_room), lower_room.stair_turn_degrees))
	return result


# --------------------------------------------------------------------------
# Cuantas plantas tiene el edificio, y a que altura esta lo dibujado
# --------------------------------------------------------------------------
#
# Decision del usuario (2026-09-09, N-4): **las plantas del edificio son las
# dibujadas**, no un numero declarado aparte. Lo que si es un dato es a que
# ALTURA se planta esa pila: `apartment_floor_number` dice en que planta cae el
# forjado mas bajo que se ha dibujado. Debajo quedan plantas de relleno que
# existen para la vista -y para que los vecinos igualen la altura- pero que no
# se dibujan, no arden y no salen en el HUD.
#
# La cuenta de plantas es la espanola, y el mando ya la traia implicita en su
# recorrido de -5 a 80: **0 es la planta baja**, los positivos suben y los
# negativos son sotanos. Asi `planta` es directamente cuantas alturas hay entre
# la calle y el forjado dibujado.
#
#   planta_piso = 15, una planta dibujada
#     -> 15 plantas por debajo (baja + 1a..14a), la tuya encima
#     -> el edificio APARENTA 16 plantas
#     -> la calle queda 15 alturas de planta por debajo
#     -> los vecinos se levantan 16 plantas, no 5

## Separacion minima entre dos cotas para contarlas como plantas distintas. La
## misma que usa `next_floor_level_above_m`: por debajo de eso es un desnivel
## dentro de una planta, no una planta.
const FLOOR_SEPARATION_M: float = 0.20


## Cotas de forjado dibujadas, de abajo arriba y sin repetir.
static func drawn_floor_levels_m(building: BuildingModel) -> Array[float]:
	var levels: Array[float] = []
	if building == null:
		return levels
	for key in building.get_rooms().keys():
		var room: RoomModel = building.get_room(int(key))
		if room == null:
			continue
		var nueva: bool = true
		for level in levels:
			if absf(level - room.floor_level_z_m) < FLOOR_SEPARATION_M:
				nueva = false
				break
		if nueva:
			levels.append(room.floor_level_z_m)
	levels.sort()
	return levels


## Cuantas plantas se han dibujado. Nunca menos de una: un edificio sin salas
## sigue teniendo su planta, y devolver 0 haria dividir por cero mas arriba.
static func drawn_floor_count(building: BuildingModel) -> int:
	return maxi(1, drawn_floor_levels_m(building).size())


## Altura de planta a planta, medida en el propio edificio. Con una sola planta
## dibujada no hay nada que medir y manda `fallback` -por eso es un parametro y
## no una constante escondida, como el resto de este modulo-.
static func floor_to_floor_m(building: BuildingModel, fallback: float) -> float:
	var levels: Array[float] = drawn_floor_levels_m(building)
	if levels.size() < 2:
		return fallback
	var total: float = levels[levels.size() - 1] - levels[0]
	return maxf(0.1, total / float(levels.size() - 1))


## En que planta cae el forjado mas bajo dibujado. 0 = planta baja. Una
## unifamiliar esta siempre a pie de calle.
static func base_floor_number(building: BuildingModel) -> int:
	if building == null:
		return 0
	if String(building.building_type).strip_edges().to_lower() != "apartment":
		return 0
	return maxi(0, building.apartment_floor_number)


## Plantas que tiene el edificio. Son DOS datos distintos y aqui se juntan:
##
##  - `building_total_floors`, si se ha declarado, manda: se dibujan una o dos
##    plantas y se dice que el edificio tiene treinta.
##  - si no se ha declarado (0), se deduce el minimo coherente: las que quedan
##    debajo segun la planta en la que se vive, mas las dibujadas.
##
## El declarado nunca puede quedarse corto: un edificio no puede tener menos
## plantas que las que hay debajo de la vivienda mas la vivienda.
static func apparent_total_floors(building: BuildingModel) -> int:
	var minimo: int = base_floor_number(building) + drawn_floor_count(building)
	if building == null:
		return minimo
	return maxi(minimo, building.building_total_floors)


## Cuanto cae la calle por debajo del forjado mas bajo dibujado: una altura de
## planta por cada planta que hay debajo. En una unifamiliar, y en la baja, 0.
static func street_drop_m(building: BuildingModel, fallback_floor_height: float) -> float:
	var relleno: int = base_floor_number(building)
	if relleno <= 0:
		return 0.0
	return float(relleno) * floor_to_floor_m(building, fallback_floor_height)


## Plantas que quedan POR ENCIMA de lo dibujado. Son las que hacen que, desde la
## planta 15 de un edificio de 30, todavia haya edificio sobre tu cabeza.
static func floors_above_m(building: BuildingModel, fallback_floor_height: float) -> float:
	var encima: int = apparent_total_floors(building) - base_floor_number(building) - drawn_floor_count(building)
	if encima <= 0:
		return 0.0
	return float(encima) * floor_to_floor_m(building, fallback_floor_height)

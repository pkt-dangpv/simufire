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

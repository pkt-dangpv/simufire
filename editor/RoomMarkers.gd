extends RefCounted
## Los marcadores que viven dentro de una sala: detectores y victimas.
##
## Sexto corte de D-1 (docs/AUDITORIA_EDITOR_2026-09-06.md). Aqui tampoco habia
## una funcion larga: habia **el mismo codigo dos veces**, una para cada lista.
## `_detector_index_for_id` y `_victim_index_for_id` eran identicas salvo la
## clave; `_find_detector_at` y `_find_victim_at`, identicas salvo la clave y el
## radio; `_move_detector_to` y `_move_victim_to`, identicas y punto.
##
## Un detector y una victima son la misma forma de dato —`{id, room_id, x_m,
## y_m}`, con la posicion **local a su sala**— y por eso el codigo salia igual
## las dos veces. Lo que cambia entre ellos es lo que se ve y lo que significan,
## no como se buscan.
##
## Estatico y puro, como PlanGeometry: recibe la lista, no `editor_data`. La
## unica concesion es `find_at()`, que necesita saber donde esta cada sala: se le
## pasa un diccionario `id de sala -> esquina de la sala en metros`, ya filtrado
## por planta, y asi la regla de «solo lo de esta planta» sigue viviendo en el
## editor, que es quien sabe en que planta esta.


## En que posicion de la lista esta el marcador con ese id, o -1.
static func index_for_id(list: Array, marker_id: String) -> int:
	for i in range(list.size()):
		if typeof(list[i]) != TYPE_DICTIONARY:
			continue
		if String(Dictionary(list[i]).get("id", "")) == marker_id:
			return i
	return -1


## El id del marcador que esta en esa posicion, o "" si no hay.
static func id_for_index(list: Array, index: int) -> String:
	if index < 0 or index >= list.size() or typeof(list[index]) != TYPE_DICTIONARY:
		return ""
	return String(Dictionary(list[index]).get("id", ""))


## Cual cae bajo el raton. `room_origins` lleva solo las salas donde se puede
## pinchar ahora mismo -las de la planta actual-, asi que un marcador de otra
## planta no aparece aqui y no hay que volver a preguntarlo.
static func find_at(list: Array, pos_m: Vector2, hit_radius_m: float, room_origins: Dictionary) -> int:
	for i in range(list.size()):
		if typeof(list[i]) != TYPE_DICTIONARY:
			continue
		var marker: Dictionary = list[i]
		var room_id: int = int(marker.get("room_id", -1))
		if not room_origins.has(room_id):
			continue
		if pos_m.distance_to(world_position(Vector2(room_origins[room_id]), marker)) <= hit_radius_m:
			return i
	return -1


## Donde cae el marcador en el plano. La posicion guardada es local a su sala:
## mover la sala mueve lo que tiene dentro, que es lo que se quiere.
static func world_position(room_origin_m: Vector2, marker: Dictionary) -> Vector2:
	return room_origin_m + Vector2(float(marker.get("x_m", 0.0)), float(marker.get("y_m", 0.0)))


## Deja el marcador en una sala y una posicion local ya ajustada. Devuelve el
## diccionario nuevo: quien llama decide si lo guarda.
static func placed(marker: Dictionary, room_id: int, local_pos_m: Vector2) -> Dictionary:
	var out: Dictionary = marker.duplicate()
	out["room_id"] = room_id
	out["x_m"] = local_pos_m.x
	out["y_m"] = local_pos_m.y
	return out

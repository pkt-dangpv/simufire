extends RefCounted
## Las preguntas sobre paredes del escenario: que pared comparten dos salas y
## por donde.
##
## Primer corte de la **capa de preguntas** (D-1). Medido el 2026-09-11 sobre
## `editor/ScenarioEditor.gd`: de sus 431 funciones, **58 son preguntas puras al
## escenario** -leen `editor_data` y no escriben, no tocan la escena ni la
## seleccion- y suman 1036 lineas. Ese es el bloque grande que de verdad se puede
## sacar del fichero, y no un tema como «escaleras» o «aperturas», que estan
## entretejidos con el estado del editor.
##
## Estatico y puro: recibe el diccionario del escenario, no lo guarda y no lo
## toca.
##
## **Lo que se colapso al mudarlo.** `_shared_wall_between` eran 70 lineas -la
## funcion mas larga del fichero- con **cuatro bloques casi identicos**, uno por
## par de paredes enfrentadas, que solo se diferenciaban en el eje y en el signo.
## Cuatro copias de la misma regla es como se acaba con una puerta que se puede
## poner entre dos salas por un lado y no por el otro. Aqui son cuatro entradas
## de una tabla y una sola regla que las recorre.

const Serializer = preload("res://editor/ScenarioSerializer.gd")

## Brecha maxima entre paredes para considerarlas conectadas (m).
const GAP_TOL: float = 0.30
## Solapamiento maximo admitido, en fraccion de la dimension menor.
const OVERLAP_FRAC: float = 0.85
## Longitud minima de pared compartida para que cuente (m).
const MIN_SHARED: float = 0.20
## Radio de clic para senalar una pared (m).
const CLICK_TOL: float = 0.40
## Valor centinela de «sin clic»: el filtro de proximidad no se aplica.
const NO_CLICK := Vector2(1.0e20, 1.0e20)


## El rectangulo de una sala, tal y como esta guardado.
static func room_rect(data: Dictionary, room_id: int) -> Rect2:
	var rects: Dictionary = data.get("room_rect_m", {})
	return Serializer.rect2_from_data(rects.get(str(room_id), Rect2()))


## La sala con ese id, o un diccionario vacio.
static func room_by_id(data: Dictionary, room_id: int) -> Dictionary:
	for raw_room in data.get("rooms_data", []):
		if typeof(raw_room) == TYPE_DICTIONARY and int(Dictionary(raw_room).get("id", -1)) == room_id:
			return raw_room
	return {}


## La cota de la planta en la que esta esa sala.
static func room_level_m(data: Dictionary, room_id: int) -> float:
	var room: Dictionary = room_by_id(data, room_id)
	return float(room.get("floor_level_z_m", 0.0)) if not room.is_empty() else 0.0


## Que pared comparten dos salas, y con que desplazamiento.
##
## Admite tres situaciones, y las tres hacen falta: contacto exacto, una brecha
## de hasta `GAP_TOL`, y un solape parcial de hasta `OVERLAP_FRAC` de la
## dimension menor. Con `click_m` ademas filtra por cercania al punto pulsado.
##
## Devuelve el par de paredes con la **menor separacion**, o `{}` si no hay
## conexion. Dos salas en plantas distintas nunca comparten pared.
static func shared_wall_between(data: Dictionary, a_id: int, b_id: int, click_m: Vector2 = NO_CLICK) -> Dictionary:
	if absf(room_level_m(data, a_id) - room_level_m(data, b_id)) > 0.05:
		return {}
	var a: Rect2 = room_rect(data, a_id)
	var b: Rect2 = room_rect(data, b_id)
	var filtra_clic: bool = click_m.x < 1.0e19

	# Las cuatro parejas de paredes enfrentadas. `eje` es el eje por el que se
	# mide la BRECHA; el otro es por el que se mide la pared compartida.
	#
	#   gap  separacion entre las dos caras enfrentadas (negativa = solapan)
	#   mid  coordenada de la junta, para el filtro de clic
	var candidatos: Array = [
		{"wall": "right", "eje_x": true, "gap": b.position.x - a.end.x, "mid": (a.end.x + b.position.x) * 0.5},
		{"wall": "left", "eje_x": true, "gap": a.position.x - b.end.x, "mid": (a.position.x + b.end.x) * 0.5},
		{"wall": "bottom", "eje_x": false, "gap": b.position.y - a.end.y, "mid": (a.end.y + b.position.y) * 0.5},
		{"wall": "top", "eje_x": false, "gap": a.position.y - b.end.y, "mid": (a.position.y + b.end.y) * 0.5},
	]

	var best: Dictionary = {}
	var best_gap: float = 1.0e20
	for raw in candidatos:
		var c: Dictionary = raw
		var eje_x: bool = bool(c["eje_x"])
		var gap: float = float(c["gap"])
		# La dimension menor del eje de la brecha acota cuanto pueden solapar.
		var min_dim: float = minf(a.size.x, b.size.x) if eje_x else minf(a.size.y, b.size.y)
		if gap < -min_dim * OVERLAP_FRAC or gap > GAP_TOL:
			continue
		# El tramo de pared que de verdad comparten, en el otro eje.
		var ini: float = maxf(a.position.y, b.position.y) if eje_x else maxf(a.position.x, b.position.x)
		var fin: float = minf(a.end.y, b.end.y) if eje_x else minf(a.end.x, b.end.x)
		if fin - ini < MIN_SHARED:
			continue
		var clic_eje: float = click_m.x if eje_x else click_m.y
		var clic_largo: float = click_m.y if eje_x else click_m.x
		if filtra_clic and (absf(clic_eje - float(c["mid"])) > CLICK_TOL
				or clic_largo < ini - 0.10 or clic_largo > fin + 0.10):
			continue
		var separacion: float = absf(gap)
		if separacion >= best_gap:
			continue
		best_gap = separacion
		var centro: float = clampf(clic_largo if filtra_clic else (ini + fin) * 0.5, ini, fin)
		var origen: float = a.position.y if eje_x else a.position.x
		best = {"a": a_id, "b": b_id, "wall": String(c["wall"]), "offset_m": centro - origen}
	return best


## El tramo de pared que dos salas comparten, como segmento. Vacio si no llegan
## a `MIN_SHARED`.
static func shared_wall_segment(data: Dictionary, room_id: int, other_id: int, wall: String) -> PackedVector2Array:
	var rect: Rect2 = room_rect(data, room_id)
	var other: Rect2 = room_rect(data, other_id)
	match wall:
		"left", "right":
			var start_y: float = maxf(rect.position.y, other.position.y)
			var end_y: float = minf(rect.end.y, other.end.y)
			if end_y - start_y < MIN_SHARED:
				return PackedVector2Array()
			var edge_x: float = rect.position.x if wall == "left" else rect.end.x
			return PackedVector2Array([Vector2(edge_x, start_y), Vector2(edge_x, end_y)])
		"top", "bottom":
			var start_x: float = maxf(rect.position.x, other.position.x)
			var end_x: float = minf(rect.end.x, other.end.x)
			if end_x - start_x < MIN_SHARED:
				return PackedVector2Array()
			var edge_y: float = rect.position.y if wall == "top" else rect.end.y
			return PackedVector2Array([Vector2(start_x, edge_y), Vector2(end_x, edge_y)])
	return PackedVector2Array()

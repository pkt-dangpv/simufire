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

const ScenarioQueries = preload("res://editor/ScenarioQueries.gd")

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


## Quien es cada sala, donde esta y en que planta lo contesta `ScenarioQueries`,
## que es la base de esta capa. Aqui solo quedan las preguntas sobre PAREDES.


## Que pared comparten dos salas, y con que desplazamiento.
##
## Admite tres situaciones, y las tres hacen falta: contacto exacto, una brecha
## de hasta `GAP_TOL`, y un solape parcial de hasta `OVERLAP_FRAC` de la
## dimension menor. Con `click_m` ademas filtra por cercania al punto pulsado.
##
## Devuelve el par de paredes con la **menor separacion**, o `{}` si no hay
## conexion. Dos salas en plantas distintas nunca comparten pared.
static func shared_wall_between(data: Dictionary, a_id: int, b_id: int, click_m: Vector2 = NO_CLICK) -> Dictionary:
	if absf(ScenarioQueries.room_level_m(data, a_id) - ScenarioQueries.room_level_m(data, b_id)) > 0.05:
		return {}
	var a: Rect2 = ScenarioQueries.room_rect(data, a_id)
	var b: Rect2 = ScenarioQueries.room_rect(data, b_id)
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
	var rect: Rect2 = ScenarioQueries.room_rect(data, room_id)
	var other: Rect2 = ScenarioQueries.room_rect(data, other_id)
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


## ── Aperturas ───────────────────────────────────────────────────────────────
##
## Donde cae una apertura sobre su pared, cuanto puede medir y a que planta
## pertenece. Todo sale del escenario y de la geometria; nada de esto necesita
## saber que hay seleccionado ni como se esta mirando el plano.

const StairPlanRules = preload("res://editor/StairPlanRules.gd")
const StairGeometry = preload("res://view/geometry/StairGeometry.gd")
const PlanGeometry = preload("res://editor/PlanGeometry.gd")

## Id que representa "el exterior" en el campo `b` de una apertura.
const OUTSIDE_ID: int = -1

static func max_opening_width_for_shared(data: Dictionary, room_id: int, other_id: int, wall: String) -> float:
	var segment: PackedVector2Array = shared_wall_segment(data, room_id, other_id, wall)
	if segment.size() != 2:
		return 0.30
	return maxf(0.30, segment[0].distance_to(segment[1]) - 0.10)


static func opening_segment_m(data: Dictionary, opening: Dictionary) -> PackedVector2Array:
	var a_id: int = int(opening.get("a", -1))
	if a_id < 0:
		return PackedVector2Array()
	var rect: Rect2 = ScenarioQueries.room_rect(data, a_id)
	var wall: String = String(opening.get("wall", ""))
	var b_id: int = int(opening.get("b", OUTSIDE_ID))
	if wall == "":
		var shared: Dictionary = shared_wall_between(data, a_id, b_id)
		wall = String(shared.get("wall", "top"))
	var width: float = float(opening.get("width_m", 0.9))
	var offset: float = float(opening.get("offset_m", PlanGeometry.wall_length(rect, wall) * 0.5))
	if bool(opening.get("offset_is_fraction", true)):
		if b_id != OUTSIDE_ID:
			var shared_segment: PackedVector2Array = shared_wall_segment(data, a_id, b_id, wall)
			if shared_segment.size() == 2:
				return PlanGeometry.line_segment_from_fraction(shared_segment[0], shared_segment[1], offset, width)
		offset = PlanGeometry.wall_length(rect, wall) * clampf(offset, 0.0, 1.0)
	return PlanGeometry.wall_segment(rect, wall, offset, width)


static func max_width_for_opening(data: Dictionary, opening: Dictionary) -> float:
	if bool(opening.get("is_vertical", false)):
		var room_rect: Rect2 = ScenarioQueries.room_rect(data, int(opening.get("a", -1)))
		return maxf(0.30, room_rect.size.x - 0.10)
	var a_id: int = int(opening.get("a", -1))
	var b_id: int = int(opening.get("b", OUTSIDE_ID))
	var wall: String = String(opening.get("wall", ""))
	if a_id >= 0 and b_id != OUTSIDE_ID and wall != "":
		return max_opening_width_for_shared(data, a_id, b_id, wall)
	if a_id >= 0:
		var rect: Rect2 = ScenarioQueries.room_rect(data, a_id)
		if wall == "":
			wall = "top"
		return maxf(0.30, PlanGeometry.wall_length(rect, wall) - 0.10)
	return 0.30


## Lo mas ancho que puede ser un balcon: la fachada de la que cuelga. Aqui se
## mide la del paramento de SU sala, que es la que el editor conoce sin salir
## de la abertura; la vista, que ve el lienzo entero, todavia lo recorta mas si
## la abertura esta cerca de la esquina.
static func max_balcony_width_for_opening(data: Dictionary, opening: Dictionary) -> float:
	var wall_m: float = PlanGeometry.wall_length(
		ScenarioQueries.room_rect(data, int(opening.get("a", -1))),
		String(opening.get("wall", "top"))
	)
	return maxf(float(opening.get("width_m", 0.9)), wall_m)


## Coordenada a lo largo del muro, medida desde su arranque, de un punto del
## plano. Es lo que espera `offset_m` de una abertura.
static func wall_offset_for_point(data: Dictionary, room_id: int, wall_name: String, coord_m: float, horizontal: bool) -> float:
	var rect: Rect2 = ScenarioQueries.room_rect(data, room_id)
	var wall_data: Dictionary = PlanGeometry.wall_start_dir(rect, wall_name)
	var start: Vector2 = wall_data["start"]
	var dir: Vector2 = wall_data["dir"]
	var point := Vector2(coord_m, start.y) if horizontal else Vector2(start.x, coord_m)
	return clampf((point - start).dot(dir), 0.0, PlanGeometry.wall_length(rect, wall_name))


static func vertical_opening_rect(data: Dictionary, opening: Dictionary) -> Rect2:
	var a_id: int = int(opening.get("a", -1))
	var room_rect: Rect2 = ScenarioQueries.room_rect(data, a_id)
	if room_rect.size.x <= 0.0 or room_rect.size.y <= 0.0:
		return Rect2()
	var room: Dictionary = ScenarioQueries.room_by_id(data, a_id)
	# El portal: el hueco va sobre la parte de los tramos, no sobre la zona
	# entera, igual que en la vista.
	var portal: Dictionary = portal_layout(data, room)
	if not portal.is_empty():
		return StairGeometry.vertical_void_rect(Rect2(portal["stair_rect"]), Vector2(portal["stair_dir"]), float(portal["turn_degrees"]))
	if not room.is_empty() and StairPlanRules.is_stair_room(room):
		var stair_dir: Vector2 = StairPlanRules.run_direction_for_room(room)
		var turn_degrees: float = float(room.get("stair_turn_degrees", 0.0))
		return StairGeometry.vertical_void_rect(room_rect, stair_dir, turn_degrees)
	var width_m: float = minf(float(opening.get("width_m", room_rect.size.x * 0.5)), maxf(0.2, room_rect.size.x - 0.2))
	var depth_m: float = minf(float(opening.get("height_m", room_rect.size.y * 0.55)), maxf(0.2, room_rect.size.y - 0.2))
	return Rect2(room_rect.get_center() - Vector2(width_m, depth_m) * 0.5, Vector2(width_m, depth_m))


## El reparto de una zona del portal -rellano y escalera- desde el diccionario
## del escenario. Es `PortalGeometry.layout` del lado del editor: el mismo voto
## de puertas entre todas las plantas del portal y el mismo `split`, para que el
## plano dibuje la escalera donde la construye la vista. Vacio si no es portal.
static func portal_layout(data: Dictionary, room: Dictionary) -> Dictionary:
	if room.is_empty() or not StairPlanRules.is_portal_room(room):
		return {}
	var rect: Rect2 = ScenarioQueries.room_rect(data, int(room.get("id", -1)))
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return {}
	var chain: Dictionary = {}
	for raw in data.get("rooms_data", []):
		if typeof(raw) != TYPE_DICTIONARY or not StairPlanRules.is_portal_room(raw):
			continue
		var other_id: int = int(Dictionary(raw).get("id", -1))
		if PortalGeometry.same_rect(ScenarioQueries.room_rect(data, other_id), rect):
			chain[other_id] = true
	var votes: Dictionary = {}
	for raw_op in data.get("openings_data", []):
		if typeof(raw_op) != TYPE_DICTIONARY or bool(Dictionary(raw_op).get("is_vertical", false)):
			continue
		var a_id: int = int(Dictionary(raw_op).get("a", OUTSIDE_ID))
		var b_id: int = int(Dictionary(raw_op).get("b", OUTSIDE_ID))
		var other: int = OUTSIDE_ID
		if chain.has(a_id) and b_id >= 0 and not chain.has(b_id):
			other = b_id
		elif chain.has(b_id) and a_id >= 0 and not chain.has(a_id):
			other = a_id
		if other < 0:
			continue
		var side: String = PortalGeometry.touching_side(rect, ScenarioQueries.room_rect(data, other))
		if side != "":
			votes[side] = int(votes.get(side, 0)) + 1
	return PortalGeometry.split(rect, PortalGeometry.side_from_votes(votes, StairPlanRules.run_direction_for_room(room)))


static func opening_on_level(data: Dictionary, opening: Dictionary, level_m: float) -> bool:
	var a_id: int = int(opening.get("a", -1))
	var b_id: int = int(opening.get("b", OUTSIDE_ID))
	if a_id < 0:
		return false
	if absf(ScenarioQueries.room_level_m(data, a_id) - level_m) < 0.05:
		return true
	return b_id != OUTSIDE_ID and absf(ScenarioQueries.room_level_m(data, b_id) - level_m) < 0.05

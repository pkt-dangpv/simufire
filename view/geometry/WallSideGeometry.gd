class_name WallSideGeometry
extends RefCounted

## Los cuatro lados de una sala en planta, y como se relacionan entre si.
##
## El mundo de primera persona levanta paramentos reales, partidos por cada
## hueco; el visor 3D dibuja cuatro cajas traslucidas de maqueta. Son dos cosas
## distintas a proposito y no se unifican. Lo que si era la misma pregunta
## escrita dos veces es esto: en que eje cae un lado, cual es su opuesto, hacia
## donde mira, y por que lado se tocan dos salas contiguas (FP-3).
##
## Los nombres canonicos son `top`, `bottom`, `left` y `right`, sobre el plano
## XZ con Z creciendo hacia `bottom`. Se aceptan tambien los alias cardinales
## que trae el modelo de huecos (`north`, `south`, `west`, `east`).

## Separacion maxima (m) para dar dos paramentos por coincidentes.
const ADJACENCY_EPS_M: float = 0.01

## Solape minimo (m) por defecto para considerar que dos salas comparten pared y
## no solo se rozan por una esquina.
const DEFAULT_MIN_OVERLAP_M: float = 0.05


## Nombre canonico de un lado. Cadena vacia si no se reconoce.
static func canonical(side: String) -> String:
	match side.strip_edges().to_lower():
		"top", "north":
			return "top"
		"bottom", "south":
			return "bottom"
		"left", "west":
			return "left"
		"right", "east":
			return "right"
	return ""


## Un lado es horizontal si corre a lo largo de X (`top` y `bottom`).
static func is_horizontal(side: String) -> bool:
	var canon: String = canonical(side)
	return canon == "top" or canon == "bottom"


## Lado de enfrente. Cadena vacia si el lado no se reconoce.
static func opposite(side: String) -> String:
	match canonical(side):
		"top":
			return "bottom"
		"bottom":
			return "top"
		"left":
			return "right"
		"right":
			return "left"
	return ""


## Normal en planta que apunta hacia AFUERA de la sala. Un lado desconocido cae
## en `top`, que es el criterio que ya tenia el visor.
static func outward_normal_2d(side: String) -> Vector2:
	match canonical(side):
		"bottom":
			return Vector2(0.0, 1.0)
		"left":
			return Vector2(-1.0, 0.0)
		"right":
			return Vector2(1.0, 0.0)
	return Vector2(0.0, -1.0)


## Normal 3D que apunta hacia ADENTRO de la sala: la de afuera, del reves.
static func inward_normal_3d(side: String) -> Vector3:
	var outward: Vector2 = outward_normal_2d(side)
	return Vector3(-outward.x, 0.0, -outward.y)


## Tramo del eje que ocupa un lado: X para `top`/`bottom`, Z para los otros.
static func side_span(rect: Rect2, side: String) -> Dictionary:
	if is_horizontal(side):
		return {"start": rect.position.x, "end": rect.position.x + rect.size.x}
	return {"start": rect.position.y, "end": rect.position.y + rect.size.y}


## Coordenada fija del lado sobre el eje perpendicular: la Z de `top`/`bottom`,
## la X de `left`/`right`.
static func side_offset_m(rect: Rect2, side: String) -> float:
	match canonical(side):
		"top":
			return rect.position.y
		"bottom":
			return rect.position.y + rect.size.y
		"left":
			return rect.position.x
		"right":
			return rect.position.x + rect.size.x
	return rect.position.y


## Por que lado toca `a` a `b`, y en que tramo. Devuelve
## `{ "side", "overlap_start", "overlap_end" }`, o vacio si no comparten pared.
##
## `min_overlap_m` es un parametro y no una constante escondida a proposito: el
## mundo FP exige 5 cm de solape para dar por buena una medianera y el visor 3D
## se conformaba con cualquier solape positivo. Los dos criterios siguen vivos,
## pero ahora se leen en la llamada.
static func shared_side(a: Rect2, b: Rect2, min_overlap_m: float = DEFAULT_MIN_OVERLAP_M) -> Dictionary:
	var a_right: float = a.position.x + a.size.x
	var b_right: float = b.position.x + b.size.x
	var a_bottom: float = a.position.y + a.size.y
	var b_bottom: float = b.position.y + b.size.y

	if absf(a_right - b.position.x) < ADJACENCY_EPS_M:
		var right_span: Dictionary = _overlap(a.position.y, a_bottom, b.position.y, b_bottom, min_overlap_m)
		if not right_span.is_empty():
			return _shared("right", right_span)
	if absf(a.position.x - b_right) < ADJACENCY_EPS_M:
		var left_span: Dictionary = _overlap(a.position.y, a_bottom, b.position.y, b_bottom, min_overlap_m)
		if not left_span.is_empty():
			return _shared("left", left_span)
	if absf(a_bottom - b.position.y) < ADJACENCY_EPS_M:
		var bottom_span: Dictionary = _overlap(a.position.x, a_right, b.position.x, b_right, min_overlap_m)
		if not bottom_span.is_empty():
			return _shared("bottom", bottom_span)
	if absf(a.position.y - b_bottom) < ADJACENCY_EPS_M:
		var top_span: Dictionary = _overlap(a.position.x, a_right, b.position.x, b_right, min_overlap_m)
		if not top_span.is_empty():
			return _shared("top", top_span)
	return {}


## Lado sobre el que cae un punto del contorno de la sala, o cadena vacia si el
## punto no esta en ninguno dentro de `eps_m`.
static func side_from_point(rect: Rect2, x_m: float, z_m: float, eps_m: float) -> String:
	if absf(z_m - rect.position.y) <= eps_m:
		return "top"
	if absf(z_m - (rect.position.y + rect.size.y)) <= eps_m:
		return "bottom"
	if absf(x_m - rect.position.x) <= eps_m:
		return "left"
	if absf(x_m - (rect.position.x + rect.size.x)) <= eps_m:
		return "right"
	return ""


static func _overlap(a_start: float, a_end: float, b_start: float, b_end: float, min_overlap_m: float) -> Dictionary:
	var start: float = maxf(a_start, b_start)
	var end: float = minf(a_end, b_end)
	if end - start > min_overlap_m:
		return {"start": start, "end": end}
	return {}


static func _shared(side: String, span: Dictionary) -> Dictionary:
	return {"side": side, "overlap_start": span["start"], "overlap_end": span["end"]}

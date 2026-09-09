extends RefCounted

## Que mueble va CON cual, y hacia donde mira cada uno.
##
## El problema que resuelve, con las palabras del usuario: *"cosas que no
## parecen muebles en medio del pasillo y muebles en sitios que no
## corresponden"*. La colocacion que habia cumple sus reglas -nada fuera de la
## sala, nada solapado, las de paramento contra un paramento- y aun asi un salon
## no parece un salon, porque le faltan las dos cosas que hacen que lo parezca:
##
##  1. **La orientacion.** Una pieza contra un muro heredaba una de cuatro
##     rotaciones, y una pieza exenta se orientaba segun si su hueco era mas
##     ancho que hondo (`0 si slot.x >= slot.y, si no 90`). O sea: al azar.
##  2. **La relacion.** No habia NINGUNA. La tele no miraba al sofa, la mesilla
##     no estaba junto a la cama, las sillas no rodeaban la mesa. Cada pieza se
##     colocaba sola, ignorando a las demas.
##
## Esto no lo arregla un modelo nuevo: una tele preciosa mirando a la pared
## sigue estando mal. Por eso vive aparte de la malla y del tamano.
##
## **Convencion de giro**, que es la del resto del modulo: `rotation_deg` mide
## hacia donde MIRA la pieza, y 0 es mirar hacia +y (una pieza contra el
## paramento `top` mira hacia dentro de la sala). De ahi:
##
##     direccion(g) = (sin g, cos g)     g = atan2(dx, dy)

const WallSideGeometry := preload("res://view/geometry/WallSideGeometry.gd")


## Con quien va cada pieza, y como.
##
## `anchor` son los arquetipos a los que se agarra, en orden de preferencia.
## `relation` dice donde se pone respecto a el:
##
##  - `beside`  al costado, alineada con el (mesilla junto a la cama)
##  - `front`   por delante, mirando lo mismo que el (mesa de centro)
##  - `facing`  por delante, mirandolo A EL (tele, silla de escritorio)
##  - `around`  repartida alrededor, mirandolo (sillas de una mesa)
##
## `gap_m` es la separacion libre entre las dos piezas.
const PAIRS: Dictionary = {
	"side_table": {"anchor": ["bed", "bed_double", "bed_single", "bed_bunk"], "relation": "beside", "gap_m": 0.06},
	"lamp_table": {"anchor": ["bed", "bed_single", "side_table", "sofa", "lounge_sofa_long"], "relation": "beside", "gap_m": 0.06},
	"coffee_table": {"anchor": ["lounge_sofa_long", "sofa"], "relation": "front", "gap_m": 0.42},
	"tv_stand": {"anchor": ["lounge_sofa_long", "sofa", "bed"], "relation": "facing", "gap_m": 2.20},
	"chair_desk": {"anchor": ["desk"], "relation": "facing", "gap_m": 0.12},
	"chair": {"anchor": ["table", "desk"], "relation": "around", "gap_m": 0.14},
	"armchair": {"anchor": ["coffee_table", "lounge_sofa_long", "sofa"], "relation": "beside", "gap_m": 0.35},
	"lamp_floor": {"anchor": ["armchair", "lounge_sofa_long", "sofa"], "relation": "beside", "gap_m": 0.12},
	"bench": {"anchor": ["table"], "relation": "around", "gap_m": 0.14},
}

## Piezas que eligen paramento por REGLA en vez de por cercania.
##
## Por cercania significaba "el muro mas proximo a donde el escenario la puso",
## y esas posiciones estan pensadas para el modelo de fuego: podia tocar
## cualquier muro. Una cama va contra el pano largo que no tenga puertas.
const WALL_RULE: Dictionary = {
	"bed": "longest_free",
	"bed_single": "longest_free",
	"bed_bunk": "longest_free",
	"lounge_sofa_long": "longest_free",
	"sofa": "longest_free",
	"wardrobe": "longest_free",
	"kitchen_fridge": "run:cocina",
	"kitchen_sink": "run:cocina",
	"kitchen_stove": "run:cocina",
	"kitchen_unit": "run:cocina",
}

## Piezas cuyo lado LARGO va en la direccion en la que miran, no cruzado.
##
## Es la diferencia entre una cama y un sofa. Los dos van contra un muro, pero
## el sofa apoya su lado largo y la cama apoya el CABECERO: su largo sale
## perpendicular al muro. El codigo daba por hecho lo primero para todo, asi que
## las camas salian tumbadas de lado -y con ellas, la mesilla no tenia donde
## ponerse: las 23 del catalogo estaban lejos de su cama-.
const LONG_ALONG_FACING: Dictionary = {
	"bed": true,
	"bed_single": true,
	"bed_bunk": true,
	"bathtub": true,
}


## Si el lado largo de esta pieza va en la direccion en la que mira.
static func long_axis_is_along(archetype: String) -> bool:
	return bool(LONG_ALONG_FACING.get(archetype, false))


## Orden de una fila de cocina a lo largo de su paramento. Es el triangulo de
## trabajo de toda la vida: se guarda en la nevera, se lava en el fregadero y se
## cocina en los fuegos, y en ese orden se anda menos.
const RUN_ORDER: Dictionary = {
	"kitchen_fridge": 0,
	"kitchen_unit": 1,
	"kitchen_sink": 2,
	"kitchen_stove": 3,
}


## Ficha de relacion de un arquetipo, o un diccionario vacio si va suelto.
static func relation_for(archetype: String) -> Dictionary:
	return PAIRS.get(archetype, {})


## Regla de paramento, o cadena vacia si vale la de siempre (el mas cercano).
static func wall_rule_for(archetype: String) -> String:
	return String(WALL_RULE.get(archetype, ""))


## Grupo de fila al que pertenece, o cadena vacia.
static func run_group_for(archetype: String) -> String:
	var rule: String = wall_rule_for(archetype)
	if rule.begins_with("run:"):
		return rule.substr(4)
	return ""


## Puesto que ocupa dentro de su fila.
static func run_order_for(archetype: String) -> int:
	return int(RUN_ORDER.get(archetype, 99))


## Giro para que una pieza en `from` mire a `to`.
static func facing_deg(from: Vector2, to: Vector2) -> float:
	var d: Vector2 = to - from
	if d.length_squared() < 0.0001:
		return 0.0
	return rad_to_deg(atan2(d.x, d.y))


## Hacia donde mira una pieza girada `deg`.
static func direction_of(deg: float) -> Vector2:
	var r: float = deg_to_rad(deg)
	return Vector2(sin(r), cos(r))


## Giro encajado al cuarto mas cercano. La mayoria del mobiliario de una casa
## esta a escuadra con la habitacion; una mesilla a 37 grados canta mas que una
## mesilla mal puesta.
static func snap_quarter(deg: float) -> float:
	return roundf(fposmod(deg, 360.0) / 90.0) * 90.0


## Largo de un paramento que no pisa ningun hueco, en metros. Es lo que decide
## cual es el "pano largo libre" donde va una cama.
static func free_wall_length_m(room: Rect2, side: String, doors: Array) -> float:
	var horizontal: bool = WallSideGeometry.is_horizontal(side)
	var total: float = room.size.x if horizontal else room.size.y
	var used: float = 0.0
	for raw in doors:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var door: Dictionary = raw
		if String(door.get("side", "")) != side:
			continue
		used += maxf(0.2, float(door.get("width_m", 0.8)))
	return maxf(0.0, total - used)

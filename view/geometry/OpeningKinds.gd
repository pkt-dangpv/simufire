extends RefCounted

## A QUE DA una abertura. No es lo mismo, y hasta ahora se trataban igual.
##
## El modelo solo distingue dos cosas: si es puerta o ventana, y si el otro lado
## es una sala o el ambiente (`b == -1`). Con eso, **una puerta de vivienda que
## da a un portal cerrado y la entrada de una unifamiliar a la calle son el
## mismo dato**, y la vista las pintaba igual: las dos echaban penacho de humo a
## la calle. Una de las dos es falsa. El humo que sale por la puerta de un piso
## no se va al cielo: choca contra el techo del rellano, se extiende por el y
## luego sube por la caja de escalera.
##
## Los casos que de verdad hay:
##
##   PORTAL_DOOR    puerta de vivienda -> rellano CERRADO. No ventila a la calle.
##   STREET_DOOR    entrada de unifamiliar -> calle.
##   BALCONY_DOOR   balconera -> calle, y con su losa colgada.
##   STREET_WINDOW  ventana -> calle.
##   PATIO_WINDOW   ventana de la vivienda -> zona de patio. Da a un conducto
##                  cerrado por los lados, no a la via publica.
##   PATIO_MOUTH    la boca del patio -> cielo. Es por donde sale el penacho.
##   PATIO_SHAFT    el encadenado entre dos zonas de patio de plantas seguidas.
##   ROOF_VENT      hueco horizontal de una sala normal al exterior (claraboya,
##                  trampilla de cubierta).
##   STAIR_VOID     hueco de forjado entre dos plantas.
##   INTERIOR       entre dos salas, y nada mas.
##
## Vive en `view/` porque es una pregunta de REPRESENTACION: el motor resuelve
## su balance de presiones con lo que tiene, y esto decide que se dibuja. El dia
## que el portal sea un recinto de verdad, `PORTAL_DOOR` pasara a ser una
## abertura interior y este modulo se quedara mas corto, que es como tiene que
## envejecer.

const INTERIOR: String = "interior"
const PORTAL_DOOR: String = "portal_door"
const STREET_DOOR: String = "street_door"
const BALCONY_DOOR: String = "balcony_door"
const STREET_WINDOW: String = "street_window"
const PATIO_WINDOW: String = "patio_window"
const PATIO_MOUTH: String = "patio_mouth"
const PATIO_SHAFT: String = "patio_shaft"
const ROOF_VENT: String = "roof_vent"
const STAIR_VOID: String = "stair_void"

## Las que dan a la via publica o al cielo. Son las unicas que pueden echar
## penacho: lo que sale por ahi se va al aire libre.
const OUTDOOR_KINDS: Array[String] = [
	STREET_DOOR, BALCONY_DOOR, STREET_WINDOW, PATIO_MOUTH, ROOF_VENT
]


## A que da esta abertura.
static func of(building: BuildingModel, op: OpeningModel) -> String:
	if op == null:
		return INTERIOR
	if not op.is_exterior_opening():
		return _interior_kind(building, op)

	var inner_id: int = op.b if op.a == BuildingModel.OUTSIDE_ID else op.a
	var inner: RoomModel = building.get_room(inner_id) if building != null else null
	if op.is_vertical:
		# La boca del patio y una claraboya son el mismo hueco horizontal al
		# cielo; lo que cambia es de que cuelga.
		return PATIO_MOUTH if BuildingLevels.is_patio(inner) else ROOF_VENT
	if op.type == OpeningModel.Type.WINDOW:
		return STREET_WINDOW
	if op.has_balcony and op.accepts_balcony():
		return BALCONY_DOOR
	# La ultima distincion, y la que no estaba: en un bloque de pisos, la puerta
	# de la vivienda da al rellano, no a la calle. En una unifamiliar, si.
	return PORTAL_DOOR if _is_apartment(building) else STREET_DOOR


## ¿Lo que sale por aqui se va al aire libre?
##
## La puerta de un piso NO cuenta, aunque el modelo la tenga puesta contra el
## ambiente: al otro lado hay un rellano cerrado.
static func vents_outdoors(building: BuildingModel, op: OpeningModel) -> bool:
	return OUTDOOR_KINDS.has(of(building, op))


## ¿Es la boca de un patio? Un hueco horizontal que remata el conducto.
static func is_patio_mouth(building: BuildingModel, op: OpeningModel) -> bool:
	return of(building, op) == PATIO_MOUTH


## ¿Es la puerta de entrada a la vivienda desde el portal?
static func is_portal_door(building: BuildingModel, op: OpeningModel) -> bool:
	return of(building, op) == PORTAL_DOOR


static func _interior_kind(building: BuildingModel, op: OpeningModel) -> String:
	var room_a: RoomModel = building.get_room(op.a) if building != null else null
	var room_b: RoomModel = building.get_room(op.b) if building != null else null
	var patio_a: bool = BuildingLevels.is_patio(room_a)
	var patio_b: bool = BuildingLevels.is_patio(room_b)
	if op.is_vertical:
		return PATIO_SHAFT if patio_a and patio_b else STAIR_VOID
	return PATIO_WINDOW if patio_a != patio_b else INTERIOR


static func _is_apartment(building: BuildingModel) -> bool:
	return building != null and String(building.building_type).strip_edges().to_lower() == "apartment"

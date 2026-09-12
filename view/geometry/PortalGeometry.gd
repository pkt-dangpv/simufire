class_name PortalGeometry
extends RefCounted

## Como se reparte por dentro una zona del PORTAL: el rellano junto a las puertas
## de las viviendas y la escalera en el resto.
##
## Una caja de escalera del editor usa su rectangulo entero para los tramos, que
## es lo correcto en una escalera interior: se entra por un hueco aparte. En un
## portal no. Con la escalera ocupando toda la zona, **la puerta del piso daba
## directamente contra los tramos**, sin un palmo de suelo delante, y en las
## plantas de arriba no habia forjado ninguno: el portal de 3 x 3 m era un pozo
## con peldanos. Visto en `tools/capture_portal.gd`.
##
## Lo que hace un portal de verdad, y lo que se reparte aqui:
##
##   - una FRANJA DE RELLANO a lo largo de la pared de las puertas,
##   - y la escalera en el resto, SUBIENDO EN SENTIDO CONTRARIO a esa pared: se
##     arranca desde el rellano, se da la vuelta en la meseta del fondo y se llega
##     al rellano de arriba.
##
## El reparto tiene que ser EL MISMO EN TODAS LAS PLANTAS, o los tramos no casan
## con el hueco del forjado de encima. Por eso el lado del rellano se vota entre
## todas las zonas del portal apiladas, no planta a planta: en la baja puede no
## haber vivienda, y en la de arriba del todo puede faltar la puerta.
##
## Es geometria de REPRESENTACION: el motor no la ve. Para el, cada zona sigue
## siendo una sala entera con su ojo de 1,4 m.

## Fondo de la franja de rellano, medido desde la pared de las puertas.
const LANDING_DEPTH_M: float = 1.30
## Lo minimo que se le deja a la escalera a lo largo. En un portal mas corto el
## rellano cede fondo antes que dejar la escalera sin sitio.
const MIN_STAIR_LONG_M: float = 1.20
## Tolerancia para dar por pegadas dos salas, o por iguales dos rectangulos.
const TOUCH_TOL_M: float = 0.35
const SAME_RECT_TOL_M: float = 0.05
## Ancho transversal que necesita una escalera de ida y vuelta. El mismo umbral
## que usan los tramos de la primera persona y de la maqueta.
const SWITCHBACK_MIN_CROSS_M: float = 1.65


## El reparto de una zona del portal. Vacio si la sala no es de portal.
##
##   rect           la zona entera
##   landing_side   pared del rellano: "left", "right", "top" o "bottom"
##   landing_rect   la franja de rellano (tamano cero si no cabe)
##   stair_rect     donde van los tramos
##   stair_dir      hacia donde sube la escalera: alejandose del rellano
##   turn_degrees   180 si cabe una escalera de ida y vuelta, 0 si no
static func layout(building: BuildingModel, room: RoomModel) -> Dictionary:
	if building == null or room == null or not BuildingLevels.is_portal(room):
		return {}
	var rect: Rect2 = _rect_of(building, room.id)
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return {}
	var side: String = landing_side(building, room)
	var stair_dir: Vector2 = _inward_direction(side)
	var along_x: bool = side == "left" or side == "right"
	var long_m: float = rect.size.x if along_x else rect.size.y
	var depth_m: float = clampf(LANDING_DEPTH_M, 0.0, maxf(0.0, long_m - MIN_STAIR_LONG_M))
	var landing_rect := Rect2()
	var stair_rect := rect
	match side:
		"left":
			landing_rect = Rect2(rect.position, Vector2(depth_m, rect.size.y))
			stair_rect = Rect2(rect.position + Vector2(depth_m, 0.0), Vector2(rect.size.x - depth_m, rect.size.y))
		"right":
			landing_rect = Rect2(Vector2(rect.end.x - depth_m, rect.position.y), Vector2(depth_m, rect.size.y))
			stair_rect = Rect2(rect.position, Vector2(rect.size.x - depth_m, rect.size.y))
		"top":
			landing_rect = Rect2(rect.position, Vector2(rect.size.x, depth_m))
			stair_rect = Rect2(rect.position + Vector2(0.0, depth_m), Vector2(rect.size.x, rect.size.y - depth_m))
		_:
			landing_rect = Rect2(Vector2(rect.position.x, rect.end.y - depth_m), Vector2(rect.size.x, depth_m))
			stair_rect = Rect2(rect.position, Vector2(rect.size.x, rect.size.y - depth_m))
	var cross_m: float = rect.size.y if along_x else rect.size.x
	return {
		"rect": rect,
		"landing_side": side,
		"landing_rect": landing_rect,
		"stair_rect": stair_rect,
		"stair_dir": stair_dir,
		"turn_degrees": 180.0 if cross_m >= SWITCHBACK_MIN_CROSS_M else 0.0,
	}


## La pared del rellano, votada entre TODAS las zonas del portal con el mismo
## rectangulo: gana la que tiene mas puertas de vivienda. Si ninguna tiene, la
## contraria a la direccion de subida que guarda la sala, que es lo que decidio
## quien la dibujo.
static func landing_side(building: BuildingModel, room: RoomModel) -> String:
	var rect: Rect2 = _rect_of(building, room.id)
	var chain: Dictionary = {}
	for key in building.get_rooms().keys():
		var other: RoomModel = building.get_room(int(key))
		if other != null and BuildingLevels.is_portal(other) and _same_rect(_rect_of(building, other.id), rect):
			chain[other.id] = other.floor_level_z_m
	var votes: Dictionary = {}
	for raw_op in building.get_openings():
		var op := raw_op as OpeningModel
		if op == null or op.is_vertical:
			continue
		var zone_id: int = -1
		var other_id: int = -1
		if chain.has(op.a) and op.b >= 0 and not chain.has(op.b):
			zone_id = op.a
			other_id = op.b
		elif chain.has(op.b) and op.a >= 0 and not chain.has(op.a):
			zone_id = op.b
			other_id = op.a
		if zone_id < 0:
			continue
		var side: String = touching_side(rect, _rect_of(building, other_id))
		if side != "":
			votes[side] = int(votes.get(side, 0)) + 1
	var best: String = ""
	var best_votes: int = 0
	for side in ["left", "top", "right", "bottom"]:
		if int(votes.get(side, 0)) > best_votes:
			best_votes = int(votes[side])
			best = side
	if best != "":
		return best
	return _side_behind(BuildingLevels.stair_run_direction(room))


## Que pared de `rect` toca a `other`, o "" si no se tocan.
static func touching_side(rect: Rect2, other: Rect2) -> String:
	if other.size.x <= 0.0 or other.size.y <= 0.0:
		return ""
	var overlap_y: bool = minf(rect.end.y, other.end.y) - maxf(rect.position.y, other.position.y) > 0.2
	var overlap_x: bool = minf(rect.end.x, other.end.x) - maxf(rect.position.x, other.position.x) > 0.2
	if overlap_y and absf(other.end.x - rect.position.x) <= TOUCH_TOL_M:
		return "left"
	if overlap_y and absf(other.position.x - rect.end.x) <= TOUCH_TOL_M:
		return "right"
	if overlap_x and absf(other.end.y - rect.position.y) <= TOUCH_TOL_M:
		return "top"
	if overlap_x and absf(other.position.y - rect.end.y) <= TOUCH_TOL_M:
		return "bottom"
	return ""


## ¿Hay otra zona del portal encadenada por encima (o por debajo) de esta?
static func has_zone_above(building: BuildingModel, room: RoomModel) -> bool:
	return _chained_zone(building, room, true)


static func has_zone_below(building: BuildingModel, room: RoomModel) -> bool:
	return _chained_zone(building, room, false)


static func _chained_zone(building: BuildingModel, room: RoomModel, above: bool) -> bool:
	if building == null or room == null:
		return false
	for raw_op in building.get_openings():
		var op := raw_op as OpeningModel
		if op == null or not op.is_vertical:
			continue
		var other_id: int = op.b if op.a == room.id else (op.a if op.b == room.id else -1)
		if other_id < 0:
			continue
		var other: RoomModel = building.get_room(other_id)
		if other == null or not BuildingLevels.is_portal(other):
			continue
		if (other.floor_level_z_m > room.floor_level_z_m) == above:
			return true
	return false


static func _inward_direction(side: String) -> Vector2:
	match side:
		"left":
			return Vector2.RIGHT
		"right":
			return Vector2.LEFT
		"top":
			return Vector2.DOWN
	return Vector2.UP


static func _side_behind(stair_dir: Vector2) -> String:
	if absf(stair_dir.x) > absf(stair_dir.y):
		return "left" if stair_dir.x > 0.0 else "right"
	return "top" if stair_dir.y > 0.0 else "bottom"


static func _rect_of(building: BuildingModel, room_id: int) -> Rect2:
	return Rect2(building.room_rect_m.get(room_id, Rect2()))


static func _same_rect(a: Rect2, b: Rect2) -> bool:
	return a.position.distance_to(b.position) <= SAME_RECT_TOL_M and a.size.distance_to(b.size) <= SAME_RECT_TOL_M

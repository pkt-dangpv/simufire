extends RefCounted
## Los tiradores de una caja girada del plano: los dos de tamaño y el de giro.
##
## Quinto corte de D-1 (docs/AUDITORIA_EDITOR_2026-09-06.md). Aqui no habia una
## funcion larga que partir: habia **el mismo concepto escrito dos veces**, para
## salas y para objetos, y en los tres niveles a la vez.
##
##   | | sala | objeto |
##   |---|---|---|
##   | donde estan los tiradores | `_room_handle_points_m` | `_object_handle_points_m` |
##   | cual ha pinchado el raton | `_find_selected_room_handle_at` | `_find_selected_object_handle_at` |
##   | como se dibujan | `_room_handles_view` | `_object_handles_view` |
##
## Las seis hacian lo mismo -centro, medias medidas giradas y un cuarto punto
## separado para el giro- y solo se diferenciaban en de donde salian el centro,
## el tamaño y el angulo. Una sala es una caja girada y un objeto tambien: la
## pregunta que las copias evitaban es esa.
##
## Estatico y puro, como PlanGeometry: sin nodos, sin `editor_data` y sin saber
## que hay seleccionado.
##
## **El orden importa.** Los puntos salen siempre en el mismo orden -ancho,
## fondo, giro- y `index_at()` devuelve una posicion de ese orden, no un valor
## del `enum ObjectMouseMode` del editor. Es a proposito: el enum es del editor y
## traerselo aqui seria la copia que se acaba de quitar. El editor lo traduce en
## un solo sitio, `HANDLE_MODES`.

## Posiciones dentro del array que devuelve `points_m()`.
const RESIZE_WIDTH: int = 0
const RESIZE_LENGTH: int = 1
const ROTATE: int = 2
## Ninguno: el raton no ha pinchado ningun tirador.
const NONE: int = -1


## Los tres tiradores de una caja de `size_m` centrada en `center_m` y girada
## `rotation_deg`. El de giro va separado `rotate_offset_m` por fuera del borde
## de arriba, que es lo que lo hace agarrable sin pelearse con el de fondo.
##
## Devuelve un array vacio si la caja no tiene medidas: una sala de ancho cero
## no tiene tiradores, y antes eso se comprobaba solo en el lado de las salas.
static func points_m(center_m: Vector2, size_m: Vector2, rotation_deg: float, rotate_offset_m: float) -> PackedVector2Array:
	if size_m.x <= 0.0 or size_m.y <= 0.0:
		return PackedVector2Array()
	var rot := Transform2D(deg_to_rad(rotation_deg), Vector2.ZERO)
	var points := PackedVector2Array()
	points.resize(3)
	points[RESIZE_WIDTH] = center_m + rot * Vector2(size_m.x * 0.5, 0.0)
	points[RESIZE_LENGTH] = center_m + rot * Vector2(0.0, size_m.y * 0.5)
	points[ROTATE] = center_m + rot * Vector2(0.0, -size_m.y * 0.5 - rotate_offset_m)
	return points


## Cual de los tres ha pinchado el raton, o `NONE`.
##
## El de giro se prueba primero, y no es un detalle: cuando la caja es estrecha
## cae encima del de fondo, y quien se lleve el clic decide si girar una sala
## fina es posible o no.
static func index_at(points: PackedVector2Array, pos_m: Vector2, radius_m: float) -> int:
	if points.size() < 3:
		return NONE
	for index in [ROTATE, RESIZE_WIDTH, RESIZE_LENGTH]:
		if pos_m.distance_to(points[index]) <= radius_m:
			return index
	return NONE

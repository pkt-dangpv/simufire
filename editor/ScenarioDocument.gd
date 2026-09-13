extends RefCounted
## El DUEÑO del escenario del editor (D-1, §22 de la auditoria del editor).
##
## Tiene el diccionario del escenario y es quien lo escribe. Las mutaciones son
## metodos suyos y **no tocan la interfaz**: no ponen estado, no cambian la
## seleccion y no redibujan. Devuelven un resultado -ids creados, cuantas puertas
## se reconectaron- y es el editor quien lo convierte en mensaje y seleccion.
##
## Se muda por FAMILIAS, con una sonda de equivalencia antes y despues
## (`tools/probe_vertical_family.gd`). La primera es la de los CONDUCTOS
## VERTICALES: escalera, patio y portal, y lo que comparten -crear una sala a una
## cota, encadenar con un hueco de forjado, añadir una planta-.
##
## **El historial es suyo.** Las acciones de una familia mudada son TRANSACCIONES:
## `begin()` guarda la instantanea y lo que se escribe hasta `commit()` es un solo
## paso de deshacer, aunque por dentro añada aberturas que por su cuenta
## guardarian otra. Asi una escalera se deshace con un Ctrl+Z; antes pedia dos,
## porque abrir el paso a la sala vecina guardaba instantanea en mitad de la
## accion. Las familias que aun no se han mudado siguen llamando a `snapshot()` a
## mano desde el editor.
##
## `changed` avisa cada vez que se guarda un paso nuevo: el editor lo usa para
## marcar cambios sin guardar y rehacer el 3D en vivo.

const Serializer = preload("res://editor/ScenarioSerializer.gd")
const ScenarioQueries = preload("res://editor/ScenarioQueries.gd")
const ScenarioWalls = preload("res://editor/ScenarioWalls.gd")
const StairPlanRules = preload("res://editor/StairPlanRules.gd")
const StairGeometry = preload("res://view/geometry/StairGeometry.gd")
const PlanGeometry = preload("res://editor/PlanGeometry.gd")

const OUTSIDE_ID: int = -1
const DEFAULT_FLOOR_HEIGHT_M: float = 2.90
## La rejilla del plano. Es la misma que `ScenarioEditor.GRID_M`: una sala que se
## coloca desde aqui cae donde caeria dibujada.
const GRID_M: float = 0.25

## Lado del OJO de la escalera del portal: el paso libre por el que sube el humo
## de un rellano al de arriba, no la huella de la escalera.
##
## Medido el 2026-09-12 sobre el mismo portal dibujado: con el hueco que calcula
## la escalera (2,46 x 3,0 m, casi todo el rellano) la planta alta se clava en
## 900,0 C -mas que el propio fuego, el tope del motor-; con un ojo de 1,4 m sale
## el tiro de una caja de escalera (346 / 119 / 96 C y 1,5 / 5,7 / 9,6 Pa). El
## motor toma el area del hueco como paso libre, y los tramos de una escalera de
## obra lo tapan casi entero. La vista no usa esta medida: dibuja el hueco de la
## escalera con su geometria.
const PORTAL_EYE_SIDE_M: float = 1.40
## La puerta del zaguan a la calle.
const PORTAL_STREET_DOOR_WIDTH_M: float = 1.20
const PORTAL_STREET_DOOR_HEIGHT_M: float = 2.10

## Se ha guardado un paso de deshacer nuevo.
signal changed(label: String)

## El escenario. Solo este objeto deberia escribir en el.
var data: Dictionary = {}
## Cuantos pasos se recuerdan en cada sentido.
var max_steps: int = 48

var _undo: Array[Dictionary] = []
var _redo: Array[Dictionary] = []
## Profundidad de transaccion abierta: dentro de una, `snapshot()` no guarda.
var _tx_depth: int = 0


# --------------------------------------------------------------------------
# Historial
# --------------------------------------------------------------------------

## Guarda el estado actual como paso de deshacer. Dentro de una transaccion no
## hace nada: el paso ya se guardo al abrirla.
func snapshot(label: String = "") -> void:
	if _tx_depth > 0 or data.is_empty():
		return
	_undo.append(data.duplicate(true))
	while _undo.size() > max_steps:
		_undo.remove_at(0)
	# Una accion nueva invalida el rehacer: a partir de aqui la historia es otra.
	_redo.clear()
	changed.emit(label)


## Abre una transaccion: un solo paso de deshacer para todo lo que venga hasta
## `commit()`. Se pueden anidar; guarda la de fuera.
func begin(label: String) -> void:
	snapshot(label)
	_tx_depth += 1


func commit() -> void:
	_tx_depth = maxi(0, _tx_depth - 1)


## El estado al que vuelve deshacer, o `{}` si no hay. Lo que habia pasa a rehacer.
## Devuelve la instantanea TAL CUAL: restaurarla sin normalizar es cosa del editor.
func take_undo() -> Dictionary:
	if _undo.is_empty():
		return {}
	var previous: Dictionary = _undo.pop_back()
	_redo.append(data.duplicate(true))
	while _redo.size() > max_steps:
		_redo.remove_at(0)
	return previous


func take_redo() -> Dictionary:
	if _redo.is_empty():
		return {}
	var next: Dictionary = _redo.pop_back()
	_undo.append(data.duplicate(true))
	while _undo.size() > max_steps:
		_undo.remove_at(0)
	return next


func clear_history() -> void:
	_undo.clear()
	_redo.clear()


# --------------------------------------------------------------------------
# Plantas
# --------------------------------------------------------------------------

func default_floors() -> Array:
	return [{"name": FloorNaming.label(0), "level_m": 0.0}]


## Deja `floors` en forma: una por cota, ordenadas, con nombre, y con las cotas de
## las salas que no tenian planta.
func ensure_floors() -> void:
	if typeof(data.get("floors", [])) != TYPE_ARRAY:
		data["floors"] = default_floors()
	var floors: Array = data.get("floors", [])
	if floors.is_empty():
		floors = default_floors()
	var normalized: Array = []
	for i in range(floors.size()):
		if typeof(floors[i]) != TYPE_DICTIONARY:
			continue
		var raw: Dictionary = floors[i]
		var level_m: float = float(raw.get("level_m", 0.0 if normalized.is_empty() else normalized.size() * DEFAULT_FLOOR_HEIGHT_M))
		normalized.append({
			"name": String(raw.get("name", FloorNaming.label(normalized.size()))),
			"level_m": level_m
		})
	for raw_room in data.get("rooms_data", []):
		if typeof(raw_room) != TYPE_DICTIONARY:
			continue
		var room: Dictionary = raw_room
		_add_floor_level_if_missing(normalized, float(room.get("floor_level_z_m", 0.0)))
	if normalized.is_empty():
		normalized = default_floors()
	normalized.sort_custom(func(a, b): return float(a.get("level_m", 0.0)) < float(b.get("level_m", 0.0)))
	for i in range(normalized.size()):
		var floor: Dictionary = normalized[i]
		floor["name"] = FloorNaming.migrated_name(String(floor.get("name", "")), i)
		normalized[i] = floor
	data["floors"] = normalized


func floors() -> Array:
	ensure_floors()
	return data.get("floors", [])


func _add_floor_level_if_missing(floor_list: Array, level_m: float) -> void:
	for raw in floor_list:
		if typeof(raw) == TYPE_DICTIONARY and absf(float(raw.get("level_m", 0.0)) - level_m) < 0.05:
			return
	floor_list.append({"name": FloorNaming.label(floor_list.size()), "level_m": level_m})


func next_floor_index_above(level_m: float) -> int:
	var floor_list: Array = floors()
	var best_index: int = -1
	var best_level: float = INF
	for i in range(floor_list.size()):
		if typeof(floor_list[i]) != TYPE_DICTIONARY:
			continue
		var floor_level_m: float = float(Dictionary(floor_list[i]).get("level_m", 0.0))
		if floor_level_m > level_m + 0.20 and floor_level_m < best_level:
			best_level = floor_level_m
			best_index = i
	return best_index


## Añade una planta a esa cota y devuelve su indice.
func add_floor_at_level(level_m: float) -> int:
	var floor_list: Array = floors()
	floor_list.append({"name": FloorNaming.label(floor_list.size()), "level_m": level_m})
	floor_list.sort_custom(func(a, b): return float(Dictionary(a).get("level_m", 0.0)) < float(Dictionary(b).get("level_m", 0.0)))
	data["floors"] = floor_list
	for i in range(floor_list.size()):
		if absf(float(Dictionary(floor_list[i]).get("level_m", 0.0)) - level_m) < 0.05:
			return i
	return floor_list.size() - 1


func floor_name_for_level(level_m: float) -> String:
	var floor_list: Array = floors()
	for i in range(floor_list.size()):
		if typeof(floor_list[i]) == TYPE_DICTIONARY and absf(float(Dictionary(floor_list[i]).get("level_m", 0.0)) - level_m) < 0.05:
			return String(Dictionary(floor_list[i]).get("name", FloorNaming.label(i)))
	return FloorNaming.label(floor_list.size())


## La cota de la planta de ese indice, encajado a las que hay. 0 sin plantas.
func _level_at_index(floor_list: Array, index: int) -> float:
	if floor_list.is_empty():
		return 0.0
	return float(Dictionary(floor_list[clampi(index, 0, floor_list.size() - 1)]).get("level_m", 0.0))


# --------------------------------------------------------------------------
# Plantas: crear, copiar, borrar y cambiar de cota (segunda familia de D-1)
# --------------------------------------------------------------------------

## Crea la planta de encima de la pila. Con `copy_contents`, con lo que hay en la
## planta de `source_floor_index`. Es una transaccion.
##
## Dos plantas distintas, y a proposito:
##
##  - la de DEBAJO de la nueva es la ultima de la pila, y es con la que hay que
##    encadenar la escalera: es la que tiene el forjado que se perfora.
##  - la que se COPIA es la que se esta mirando, que es la que dice el dialogo.
##    Dibujando un bloque de viviendas se termina la planta baja y se pide otra
##    igual; la ultima de la pila puede ser el hueco de escalera vacio que creo
##    sola la herramienta de escaleras, y copiar eso no es copiar nada.
##
## Devuelve `index` (el de la planta nueva), `source_level_m` y `copied` (lo que
## se copio, vacio si no se pidio copiar).
func create_floor_above(source_floor_index: int, copy_contents: bool) -> Dictionary:
	begin("add_floor")
	var floor_list: Array = floors()
	var source_level_m: float = _level_at_index(floor_list, source_floor_index)
	var lower_level_m: float = source_level_m
	var next_level_m: float = 0.0
	if not floor_list.is_empty():
		lower_level_m = float(floor_list[floor_list.size() - 1].get("level_m", 0.0))
		next_level_m = lower_level_m + DEFAULT_FLOOR_HEIGHT_M
	floor_list.append({"name": FloorNaming.label(floor_list.size()), "level_m": next_level_m})
	data["floors"] = floor_list
	# Las escaleras primero: encadenan las dos plantas y abren el hueco vertical.
	# La copia va despues y las respeta, para no duplicar ese hueco.
	copy_stairs_between_levels(lower_level_m, next_level_m)
	var copied: Dictionary = {}
	if copy_contents:
		copied = copy_floor_contents(source_level_m, next_level_m)
	commit()
	return {"index": floor_list.size() - 1, "source_level_m": source_level_m, "copied": copied}


## Coloca una sala, encajada a la rejilla. Una escalera arrastra a sus gemelas de
## arriba y de abajo, y el hueco de forjado que las une.
func set_room_rect(room_id: int, rect: Rect2) -> void:
	var rects: Dictionary = data.get("room_rect_m", {})
	var snapped_rect := Rect2(
		Vector2(snappedf(rect.position.x, GRID_M), snappedf(rect.position.y, GRID_M)),
		Vector2(maxf(0.25, snappedf(rect.size.x, GRID_M)), maxf(0.25, snappedf(rect.size.y, GRID_M)))
	)
	rects[str(room_id)] = Serializer.rect_to_data(snapped_rect)
	data["room_rect_m"] = rects
	var room: Dictionary = ScenarioQueries.room_by_id(data, room_id)
	if StairPlanRules.is_stair_room(room):
		sync_linked_stair_rects(room_id, snapped_rect)
		sync_vertical_stair_openings(room_id)


## Copia lo CONSTRUIDO de una planta a la de encima: salas, pasillos, sus
## aperturas, el mobiliario y los detectores.
##
## No copia victimas ni el inicio en primera persona: son personas, no obra, y
## repartir la misma victima por cada planta es lo contrario de lo que se quiere.
##
## Las escaleras no se duplican: ya estan arriba -las pone
## `copy_stairs_between_levels()`- y se emparejan por su rectangulo, para que la
## puerta que abajo daba a la escalera arriba de a la escalera de arriba.
func copy_floor_contents(from_level_m: float, to_level_m: float) -> Dictionary:
	var id_map: Dictionary = {}
	var copied_rooms: int = 0
	var copied_objects: int = 0
	var rooms: Array = data.get("rooms_data", [])
	var source_rooms: Array[Dictionary] = []
	for room in rooms:
		if typeof(room) != TYPE_DICTIONARY:
			continue
		var room_dict: Dictionary = room
		if absf(float(room_dict.get("floor_level_z_m", 0.0)) - from_level_m) < 0.05:
			source_rooms.append(room_dict)

	for source in source_rooms:
		var source_id: int = int(source.get("id", -1))
		var rect: Rect2 = ScenarioQueries.room_rect(data, source_id)
		if rect.size.x <= 0.0 or rect.size.y <= 0.0:
			continue
		if StairPlanRules.is_stair_room(source):
			var twin_id: int = find_matching_stair_room_at_level(rect, to_level_m)
			if twin_id >= 0:
				id_map[source_id] = twin_id
			continue
		var copy: Dictionary = source.duplicate(true)
		var new_id: int = ScenarioQueries.next_room_id(data)
		copy["id"] = new_id
		copy["floor_level_z_m"] = to_level_m
		rooms.append(copy)
		data["rooms_data"] = rooms
		set_room_rect(new_id, rect)
		# Los ids de mueble se piden DESPUES de meter la sala en la lista: la
		# cuenta de ids libres mira lo que hay, y si no esta puesta se repiten.
		var objects: Array = copy.get("fuel_objects", [])
		for i in range(objects.size()):
			if typeof(objects[i]) != TYPE_DICTIONARY:
				continue
			var obj: Dictionary = objects[i]
			obj["id"] = ScenarioQueries.next_object_id(data)
			obj["room_id"] = new_id
			objects[i] = obj
			copied_objects += 1
		copy["fuel_objects"] = objects
		id_map[source_id] = new_id
		copied_rooms += 1

	var copied_openings: int = _copy_openings_for_map(from_level_m, id_map)
	var copied_detectors: int = _copy_detectors_for_map(id_map)
	return {
		"rooms": copied_rooms,
		"objects": copied_objects,
		"openings": copied_openings,
		"detectors": copied_detectors
	}


## Rehace en la planta nueva las aperturas de la vieja, con los ids nuevos.
##
## Las verticales no: son el hueco de la escalera, que ya lo abre el encadenado,
## y repetirlo perforaria dos veces el mismo forjado.
func _copy_openings_for_map(from_level_m: float, id_map: Dictionary) -> int:
	var openings: Array = data.get("openings_data", [])
	var copies: Array[Dictionary] = []
	for raw_op in openings:
		if typeof(raw_op) != TYPE_DICTIONARY:
			continue
		var op: Dictionary = raw_op
		if bool(op.get("is_vertical", false)):
			continue
		var a_id: int = int(op.get("a", -1))
		var b_id: int = int(op.get("b", OUTSIDE_ID))
		if not id_map.has(a_id):
			continue
		if b_id != OUTSIDE_ID and not id_map.has(b_id):
			continue
		if absf(ScenarioQueries.room_level_m(data, a_id) - from_level_m) >= 0.05:
			continue
		var new_a: int = int(id_map[a_id])
		var new_b: int = OUTSIDE_ID if b_id == OUTSIDE_ID else int(id_map[b_id])
		# Dos escaleras que se mapean a si mismas serian el mismo paso otra vez:
		# ese lo abrio el encadenado al subir la escalera.
		if new_a == a_id and new_b == b_id:
			continue
		var copy: Dictionary = op.duplicate(true)
		copy["a"] = new_a
		copy["b"] = new_b
		copies.append(copy)
	for copy in copies:
		openings.append(copy)
	data["openings_data"] = openings
	return copies.size()


## Los detectores son instalacion del edificio: suben con su sala.
func _copy_detectors_for_map(id_map: Dictionary) -> int:
	var detectors: Array = data.get("detectors", [])
	var pending: Array[Dictionary] = []
	for raw in detectors:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var detector: Dictionary = raw
		var room_id: int = int(detector.get("room_id", -1))
		if not id_map.has(room_id) or int(id_map[room_id]) == room_id:
			continue
		var copy: Dictionary = detector.duplicate(true)
		copy["room_id"] = int(id_map[room_id])
		pending.append(copy)
	for copy in pending:
		detectors.append(copy)
		data["detectors"] = detectors
		# El id se pide con la copia ya en la lista, para que no se repita con la
		# siguiente.
		copy["id"] = ""
		copy["id"] = ScenarioQueries.next_detector_id(data)
		detectors[detectors.size() - 1] = copy
	data["detectors"] = detectors
	return pending.size()


## Borra la planta de ese indice con todo lo que hay en ella: salas, sus
## aperturas, detectores y victimas. Es una transaccion. La unica planta no se
## borra: devuelve `{}`, igual que con un indice fuera de rango.
##
## Devuelve `name` (el de la planta borrada) y `remaining` (cuantas quedan).
func delete_floor(index: int) -> Dictionary:
	var floor_list: Array = floors()
	if floor_list.size() <= 1 or index < 0 or index >= floor_list.size():
		return {}
	begin("delete_floor")
	var floor: Dictionary = floor_list[index]
	var level_m: float = float(floor.get("level_m", 0.0))
	var room_ids_to_delete: Array[int] = []
	for room in data.get("rooms_data", []):
		if typeof(room) == TYPE_DICTIONARY and absf(float(Dictionary(room).get("floor_level_z_m", 0.0)) - level_m) < 0.05:
			room_ids_to_delete.append(int(Dictionary(room).get("id", -1)))

	var rooms: Array = data.get("rooms_data", [])
	for i in range(rooms.size() - 1, -1, -1):
		if typeof(rooms[i]) == TYPE_DICTIONARY and room_ids_to_delete.has(int(Dictionary(rooms[i]).get("id", -1))):
			rooms.remove_at(i)
	data["rooms_data"] = rooms

	var rects: Dictionary = data.get("room_rect_m", {})
	for room_id in room_ids_to_delete:
		rects.erase(str(room_id))
	data["room_rect_m"] = rects

	var openings: Array = data.get("openings_data", [])
	for i in range(openings.size() - 1, -1, -1):
		if typeof(openings[i]) != TYPE_DICTIONARY:
			continue
		var op: Dictionary = openings[i]
		if room_ids_to_delete.has(int(op.get("a", -999))) or room_ids_to_delete.has(int(op.get("b", -999))):
			openings.remove_at(i)
	data["openings_data"] = openings

	var dets: Array = data.get("detectors", [])
	for i in range(dets.size() - 1, -1, -1):
		if typeof(dets[i]) == TYPE_DICTIONARY and room_ids_to_delete.has(int(Dictionary(dets[i]).get("room_id", -1))):
			dets.remove_at(i)
	data["detectors"] = dets

	var vics: Array = data.get("victims", [])
	for i in range(vics.size() - 1, -1, -1):
		if typeof(vics[i]) == TYPE_DICTIONARY and room_ids_to_delete.has(int(Dictionary(vics[i]).get("room_id", -1))):
			vics.remove_at(i)
	data["victims"] = vics

	floor_list.remove_at(index)
	data["floors"] = floor_list
	commit()
	return {"name": String(floor.get("name", "")), "remaining": floor_list.size()}


## Cambia la cota de la planta de ese indice y sube o baja con ella sus salas.
## Es una transaccion. Devuelve el indice que la planta tiene DESPUES -al
## reordenar puede cambiar-, o -1 si no ha cambiado nada.
func set_floor_level(index: int, value: float) -> int:
	var floor_list: Array = floors()
	if index < 0 or index >= floor_list.size():
		return -1
	var floor: Dictionary = floor_list[index]
	var selected_floor_name: String = String(floor.get("name", FloorNaming.label(index)))
	var previous_level_m: float = float(floor.get("level_m", 0.0))
	if absf(previous_level_m - value) <= 0.001:
		return -1
	begin("floor_level")
	floor["level_m"] = value
	floor_list[index] = floor
	data["floors"] = floor_list
	var rooms: Array = data.get("rooms_data", [])
	for i in range(rooms.size()):
		if typeof(rooms[i]) != TYPE_DICTIONARY:
			continue
		var room: Dictionary = rooms[i]
		if absf(float(room.get("floor_level_z_m", 0.0)) - previous_level_m) < 0.05:
			room["floor_level_z_m"] = value
			rooms[i] = room
	data["rooms_data"] = rooms
	ensure_floors()
	var normalized_floors: Array = data.get("floors", [])
	var new_index: int = clampi(index, 0, normalized_floors.size() - 1)
	for i in range(normalized_floors.size()):
		if typeof(normalized_floors[i]) != TYPE_DICTIONARY:
			continue
		var normalized_floor: Dictionary = normalized_floors[i]
		if String(normalized_floor.get("name", "")) == selected_floor_name and absf(float(normalized_floor.get("level_m", 0.0)) - value) < 0.05:
			new_index = i
			break
	commit()
	return new_index


# --------------------------------------------------------------------------
# Salas y aperturas
# --------------------------------------------------------------------------

func create_room_at_level(rect: Rect2, room_name: String = "", kind_name: String = "generic", floor_level_m: float = 0.0, height_m: float = 2.7) -> int:
	var id: int = ScenarioQueries.next_room_id(data)
	var rooms: Array = data.get("rooms_data", [])
	var rects: Dictionary = data.get("room_rect_m", {})
	var room := {
		"id": id,
		"name": room_name if room_name != "" else "Room %d" % id,
		"kind": kind_name,
		"rotation_deg": 0.0,
		"height_m": height_m,
		"floor_level_z_m": floor_level_m,
		"fuel_energy_MJ": 0.0,
		"max_hrr_kw": 0.0,
		"fuel_objects": []
	}
	rooms.append(room)
	rects[str(id)] = Serializer.rect_to_data(rect)
	data["rooms_data"] = rooms
	data["room_rect_m"] = rects
	return id


func update_room_fields(room_id: int, fields: Dictionary) -> bool:
	var index: int = ScenarioQueries.room_index_for_id(data, room_id)
	if index < 0:
		return false
	var rooms: Array = data.get("rooms_data", [])
	var room: Dictionary = rooms[index]
	for key in fields:
		room[key] = fields[key]
	rooms[index] = room
	data["rooms_data"] = rooms
	return true


## Una abertura nueva. Devuelve su indice; la seleccion la pone el editor.
func add_opening(a: int, b: int, type_str: String, wall: String, offset_m: float, width_m: float, height_m: float, sill_m: float, open_fraction: float, record_undo: bool = true) -> int:
	var openings: Array = data.get("openings_data", [])
	if type_str == "hole":
		sill_m = 0.0
		open_fraction = 1.0
	if record_undo:
		snapshot("add_opening")
	openings.append({
		"a": a,
		"b": b,
		"type": type_str,
		"wall": wall,
		"offset_m": offset_m,
		"offset_is_fraction": false,
		"width_m": width_m,
		"height_m": height_m,
		"sill_m": sill_m,
		"open_fraction": open_fraction,
		"swing_direction": "in",
		"hinge_side": "left"
	})
	data["openings_data"] = openings
	return openings.size() - 1


## Un hueco de FORJADO entre dos salas apiladas: el ojo de una escalera o un
## tramo de patio. No es una puerta en un tabique, asi que no tiene pared ni
## alfeizar, y el motor lo intercambia por flotabilidad y no por difusion.
##
## `b` puede ser `OUTSIDE_ID`: eso es la boca del patio, abierta al cielo.
##
## No duplica: si ya hay un vertical entre esas dos, no pone otro. Encadenando
## plantas se llama mas de una vez con el mismo par.
func add_vertical_opening(a_id: int, b_id: int, width_m: float, depth_m: float) -> void:
	var openings: Array = data.get("openings_data", [])
	for raw_op in openings:
		if typeof(raw_op) != TYPE_DICTIONARY:
			continue
		var op: Dictionary = raw_op
		if not bool(op.get("is_vertical", false)):
			continue
		if int(op.get("a", -1)) == a_id and int(op.get("b", -1)) == b_id:
			return
	openings.append({
		"a": a_id,
		"b": b_id,
		"type": "hole",
		"wall": "",
		"width_m": maxf(0.2, width_m),
		"height_m": maxf(0.2, depth_m),
		"sill_m": 0.0,
		"open_fraction": 1.0,
		"offset_m": 0.0,
		"offset_is_fraction": false,
		"is_vertical": true
	})
	data["openings_data"] = openings


## ¿Es un pasillo? Por el tipo o porque se llama asi.
static func is_corridor_room(room: Dictionary) -> bool:
	var kind_name: String = String(room.get("kind", "")).strip_edges().to_lower()
	var name_text: String = String(room.get("name", "")).strip_edges().to_lower()
	return kind_name in ["corridor", "pasillo", "hallway", "distribuidor"] or name_text.begins_with("pasillo")


## Engancha una sala recien dibujada a los pasillos y escaleras que toca.
##
## La circulacion existe para conectar, asi que se conecta sola y en los dos
## sentidos: da igual si dibujas antes el pasillo o la habitacion. Con dos salas
## normales no se hace: que dos dormitorios se toquen no significa que haya un
## hueco entre ellos.
##
## No guarda instantanea por cada paso: va dentro de la accion que dibuja la sala.
func open_passages_to_circulation(room_id: int, passage_width_m: float) -> Array[int]:
	var level_m: float = ScenarioQueries.room_level_m(data, room_id)
	var connected: Array[int] = []
	for room in data.get("rooms_data", []):
		if typeof(room) != TYPE_DICTIONARY:
			continue
		var other: Dictionary = room
		var other_id: int = int(other.get("id", -1))
		if other_id == room_id or other_id < 0:
			continue
		if not (is_corridor_room(other) or StairPlanRules.is_stair_room(other)):
			continue
		# Al portal no: de una vivienda al rellano se pasa por su puerta, y un
		# hueco libre a la caja de escalera es otro edificio para el humo.
		if StairPlanRules.is_portal_room(other):
			continue
		if absf(ScenarioQueries.room_level_m(data, other_id) - level_m) >= 0.05:
			continue
		var shared: Dictionary = ScenarioWalls.shared_wall_between(data, room_id, other_id)
		if shared.is_empty():
			continue
		var span_m: float = ScenarioWalls.max_opening_width_for_shared(data, int(shared["a"]), int(shared["b"]), String(shared["wall"]))
		if span_m < 0.45:
			continue
		add_opening(
			int(shared["a"]),
			int(shared["b"]),
			"hole",
			String(shared["wall"]),
			float(shared["offset_m"]),
			minf(maxf(0.90, passage_width_m), span_m),
			2.10,
			0.0,
			1.0
		)
		connected.append(other_id)
	return connected


# --------------------------------------------------------------------------
# Aperturas: balconera, borrar y editar (tercera familia de D-1)
# --------------------------------------------------------------------------

## Puerta de balcon, o balconera: una puerta exterior hasta el suelo con su
## balcon puesto. Se crea de una vez porque es UNA cosa -nadie pone una
## balconera y luego decide si le cuelga un balcon-. Es una transaccion.
##
## Para el motor es una puerta exterior y nada mas: el hueco que ventila es el
## de la hoja. Lo que la distingue de la puerta de entrada es que da a la calle
## -no al portal- y que llega al suelo. Devuelve el indice de la abertura.
func add_balcony_door(room_id: int, wall: String, offset_m: float, door_width_m: float, door_height_m: float, balcony_width_m: float, depth_m: float, parapet_m: float) -> int:
	begin("add_opening")
	var index: int = add_opening(room_id, OUTSIDE_ID, "door", wall, offset_m, door_width_m, door_height_m, 0.0, 0.0)
	var openings: Array = data.get("openings_data", [])
	if not openings.is_empty():
		var op: Dictionary = openings[openings.size() - 1]
		op["has_balcony"] = true
		op["balcony_width_m"] = balcony_width_m
		op["balcony_depth_m"] = depth_m
		op["balcony_parapet_m"] = parapet_m
		openings[openings.size() - 1] = op
		data["openings_data"] = openings
	commit()
	return index


## Borra la abertura de ese indice. Es una transaccion. Falso si no existe.
func delete_opening(opening_index: int) -> bool:
	var openings: Array = data.get("openings_data", [])
	if opening_index < 0 or opening_index >= openings.size():
		return false
	begin("delete_opening")
	openings.remove_at(opening_index)
	data["openings_data"] = openings
	commit()
	return true


## Aplica a la abertura de ese indice lo que dice la ficha. Es una transaccion.
##
## El tipo se puede cambiar. Es lo que convierte en puerta el paso que se abre
## solo entre dos tramos de pasillo. Una ventana, en cambio, cuelga de fachada: en
## un tabique interior se rechaza y el resto de la ficha se aplica igual.
##
## Devuelve `window_rejected`; vacio si el indice no existe.
func apply_opening_fields(opening_index: int, fields: Dictionary) -> Dictionary:
	var openings: Array = data.get("openings_data", [])
	if opening_index < 0 or opening_index >= openings.size():
		return {}
	begin("edit_opening")
	var window_rejected: bool = false
	var op: Dictionary = openings[opening_index]
	var op_type: String = String(op.get("type", "door"))
	var wanted_type: String = String(fields.get("type", ""))
	if wanted_type != "" and wanted_type != op_type and not bool(op.get("is_vertical", false)):
		# Una ventana cuelga de fachada; un hueco a la calle no existe.
		if wanted_type == "window" and int(op.get("b", OUTSIDE_ID)) != OUTSIDE_ID and int(op.get("a", -1)) != OUTSIDE_ID:
			window_rejected = true
		else:
			op["type"] = wanted_type
			op_type = wanted_type
			if wanted_type == "hole":
				op["sill_m"] = 0.0
				op["open_fraction"] = 1.0
			elif wanted_type == "window" and float(op.get("sill_m", 0.0)) <= 0.01:
				op["sill_m"] = 0.90
	op["width_m"] = minf(float(fields.get("width_m", 0.9)), ScenarioWalls.max_width_for_opening(data, op))
	op["height_m"] = float(fields.get("height_m", 2.0))
	if not bool(op.get("is_vertical", false)):
		op["offset_m"] = clampf(
			float(fields.get("offset_m", 0.0)),
			0.0,
			PlanGeometry.wall_length(ScenarioQueries.room_rect(data, int(op.get("a", -1))), String(op.get("wall", "top")))
		)
		op["offset_is_fraction"] = false
	op["sill_m"] = 0.0 if op_type == "hole" else float(fields.get("sill_m", 0.0))
	op["open_fraction"] = 1.0 if op_type == "hole" else (0.0 if int(fields.get("open_index", 1)) == 0 else 1.0)
	if op_type == "door":
		op["swing_direction"] = "out" if int(fields.get("swing_index", 0)) == 1 else "in"
		op["hinge_side"] = "right" if int(fields.get("hinge_index", 0)) == 1 else "left"
	_apply_balcony_fields(op, fields)
	openings[opening_index] = op
	data["openings_data"] = openings
	commit()
	return {"window_rejected": window_rejected}


## N-1: el balcon cuelga de una abertura EXTERIOR y no vertical. En un tabique
## interior no hay fachada de la que colgarlo, y un hueco vertical es un hueco
## de forjado.
static func opening_accepts_balcony(opening: Dictionary) -> bool:
	if bool(opening.get("is_vertical", false)):
		return false
	return int(opening.get("a", 0)) == OUTSIDE_ID or int(opening.get("b", -1)) == OUTSIDE_ID


## Guarda el balcon en la abertura. Sin balcon se BORRAN las medidas en vez de
## dejarlas dormidas: asi el JSON dice lo que hay, y una abertura que dejo de
## tener balcon no arrastra un vuelo de 1,20 m que no se usa.
func _apply_balcony_fields(op: Dictionary, fields: Dictionary) -> void:
	if not opening_accepts_balcony(op) or not bool(fields.get("has_balcony", false)):
		op.erase("has_balcony")
		op.erase("balcony_width_m")
		op.erase("balcony_depth_m")
		op.erase("balcony_parapet_m")
		return
	op["has_balcony"] = true
	op["balcony_width_m"] = clampf(
		float(fields.get("balcony_width_m", 0.0)),
		0.0,
		ScenarioWalls.max_balcony_width_for_opening(data, op)
	)
	op["balcony_depth_m"] = clampf(
		float(fields.get("balcony_depth_m", 1.20)),
		OpeningModel.BALCONY_MIN_DEPTH_M,
		OpeningModel.BALCONY_MAX_DEPTH_M
	)
	op["balcony_parapet_m"] = clampf(
		float(fields.get("balcony_parapet_m", 1.10)),
		OpeningModel.BALCONY_MIN_PARAPET_M,
		OpeningModel.BALCONY_MAX_PARAPET_M
	)


## Abre paso entre una sala recien dibujada y las que toca en su misma planta.
##
## `only_widest` abre solo el paso mas ancho -lo que necesita una escalera, que
## se entra por un sitio-; con falso abre paso a TODAS, que es lo que hace un
## pasillo: un pasillo existe justamente para conectar.
##
## Devuelve los ids conectados. Vacio significa que la sala ha quedado aislada, y
## eso hay que decirlo: en el plano no se ve, porque las salas se tocan, y en
## primera persona es un tabique.
func open_passages_to_neighbours(room_id: int, only_widest: bool, skip_stairs: bool, passage_width_m: float) -> Array[int]:
	var level_m: float = ScenarioQueries.room_level_m(data, room_id)
	var candidates: Array[Dictionary] = []
	for room in data.get("rooms_data", []):
		if typeof(room) != TYPE_DICTIONARY:
			continue
		var other: Dictionary = room
		var other_id: int = int(other.get("id", -1))
		if other_id == room_id or other_id < 0:
			continue
		if skip_stairs and StairPlanRules.is_stair_room(other):
			continue
		if absf(ScenarioQueries.room_level_m(data, other_id) - level_m) >= 0.05:
			continue
		var shared: Dictionary = ScenarioWalls.shared_wall_between(data, room_id, other_id)
		if shared.is_empty():
			continue
		var width_m: float = ScenarioWalls.max_opening_width_for_shared(data, int(shared["a"]), int(shared["b"]), String(shared["wall"]))
		# El codo de un pasillo en L comparte solo el ancho de la esquina, que puede
		# quedarse en medio metro largo. Por debajo de 45 cm ya no es un paso ni en
		# una esquina, y ahi si conviene no fingirlo.
		if width_m < 0.45:
			continue
		shared["_span_m"] = width_m
		candidates.append(shared)
	if candidates.is_empty():
		return []
	if only_widest:
		candidates.sort_custom(func(a, b): return float(a["_span_m"]) > float(b["_span_m"]))
		candidates = [candidates[0]]
	var connected: Array[int] = []
	for shared in candidates:
		var span_m: float = float(shared["_span_m"])
		add_opening(
			int(shared["a"]),
			int(shared["b"]),
			"hole",
			String(shared["wall"]),
			float(shared["offset_m"]),
			minf(maxf(1.00, passage_width_m), span_m),
			2.10,
			0.0,
			1.0
		)
		connected.append(int(shared["b"]) if int(shared["a"]) == room_id else int(shared["a"]))
	return connected


# --------------------------------------------------------------------------
# Escaleras
# --------------------------------------------------------------------------

func apply_stair_defaults(room_id: int, stair_dir: Vector2, turn_degrees: float = 0.0) -> void:
	var fields: Dictionary = {
		"stair_run_direction_m": Serializer.vector_to_data(stair_dir),
		# El hueco de escalera nace CON paredes. Sin ellas, en primera persona el
		# descansillo es una repisa en el vacio: un paso de lado y te caes al
		# piso de abajo. El paso a la sala se abre aparte, con su hueco.
		"stair_has_walls": true,
		"stair_has_railings": true,
		"stair_turn_degrees": turn_degrees,
		"stair_flight_count": 2 if turn_degrees >= 179.0 else 1,
		"rotation_deg": PlanGeometry.normalize_degrees_signed(rad_to_deg(atan2(stair_dir.y, stair_dir.x)) - 90.0),
	}
	# El modo de giro solo se pone si la sala no traia uno: es una eleccion del
	# usuario y los valores por defecto no la pisan.
	if not ScenarioQueries.room_by_id(data, room_id).has("stair_turn_mode"):
		fields["stair_turn_mode"] = StairPlanRules.turn_mode_from_degrees(turn_degrees)
	update_room_fields(room_id, fields)


func set_stair_turn_mode(room_id: int, mode: String) -> void:
	update_room_fields(room_id, {"stair_turn_mode": StairPlanRules.normalized_turn_mode(mode)})


func set_stair_turn_degrees(room_id: int, turn_degrees: float) -> void:
	update_room_fields(room_id, {
		"stair_turn_degrees": turn_degrees,
		"stair_flight_count": 2 if turn_degrees >= 179.0 else 1,
	})


func add_vertical_stair_opening(lower_id: int, upper_id: int, rect: Rect2) -> void:
	var lower_room: Dictionary = ScenarioQueries.room_by_id(data, lower_id)
	var stair_dir: Vector2 = StairPlanRules.run_direction_for_room(lower_room)
	var turn_degrees: float = float(lower_room.get("stair_turn_degrees", 0.0))
	var void_rect: Rect2 = StairGeometry.vertical_void_rect(rect, stair_dir, turn_degrees)
	var along_y: bool = absf(stair_dir.y) >= absf(stair_dir.x)
	add_vertical_opening(
		lower_id, upper_id,
		void_rect.size.x if along_y else void_rect.size.y,
		void_rect.size.y if along_y else void_rect.size.x
	)


## La escalera dibujada con la herramienta: la sala de abajo, la de arriba -con
## su planta si no existia-, el hueco entre las dos y el paso a la sala vecina.
##
## Lo que es de la interfaz entra como argumento: la planta desde la que se dibuja,
## su nombre, el modo de giro elegido y el ancho de paso.
##
## Devuelve `lower_id`, `upper_id`, `turn_degrees`, `access_room_id` (-1 si abajo
## no toca nada) y `upper_access` (los ids conectados arriba).
func create_stairs(rect: Rect2, start_m: Vector2, end_m: Vector2, lower_level_m: float, lower_floor_name: String, turn_mode: String, passage_width_m: float) -> Dictionary:
	begin("create_stairs")
	var upper_floor_index: int = next_floor_index_above(lower_level_m)
	if upper_floor_index < 0:
		upper_floor_index = add_floor_at_level(lower_level_m + DEFAULT_FLOOR_HEIGHT_M)
	var floor_list: Array = floors()
	var upper_level_m: float = float(Dictionary(floor_list[upper_floor_index]).get("level_m", lower_level_m + DEFAULT_FLOOR_HEIGHT_M))
	var lower_name: String = "Escalera %s" % lower_floor_name
	var upper_name: String = "Escalera %s" % String(Dictionary(floor_list[upper_floor_index]).get("name", FloorNaming.label(upper_floor_index)))
	var lower_id: int = create_room_at_level(rect, lower_name, "escalera", lower_level_m, minf(upper_level_m - lower_level_m, 3.2))
	var upper_id: int = create_room_at_level(rect, upper_name, "escalera", upper_level_m, 2.55)
	var stair_dir: Vector2 = StairPlanRules.run_direction_from_drag(start_m, end_m, rect)
	var turn_degrees: float = StairPlanRules.turn_degrees_for_mode(rect, stair_dir, turn_mode)
	apply_stair_defaults(lower_id, stair_dir, turn_degrees)
	apply_stair_defaults(upper_id, stair_dir, turn_degrees)
	set_stair_turn_mode(lower_id, turn_mode)
	set_stair_turn_mode(upper_id, turn_mode)
	add_vertical_stair_opening(lower_id, upper_id, rect)
	# La escalera nace con paso a la sala de al lado. Sin esto se dibujaba
	# tapiada: en el plano parecia conectada porque las salas se tocan, y en
	# primera persona te comias el tabique sin poder entrar.
	# Sin saltarse las escaleras: encadenando plantas, la vecina de una escalera
	# suele ser el hueco de la anterior, y es por donde se entra.
	var access_rooms: Array[int] = open_passages_to_neighbours(lower_id, true, false, passage_width_m)
	# Y arriba igual. Encadenando plantas, la escalera de arriba llega a un piso
	# que puede tener ya salas -las de la escalera anterior-, y sin esto nacia
	# tapiada aunque la de abajo estuviera bien.
	var upper_access: Array[int] = open_passages_to_neighbours(upper_id, true, false, passage_width_m)
	commit()
	return {
		"lower_id": lower_id,
		"upper_id": upper_id,
		"turn_degrees": turn_degrees,
		"access_room_id": access_rooms[0] if not access_rooms.is_empty() else -1,
		"upper_access": upper_access,
	}


func copy_stairs_between_levels(lower_level_m: float, upper_level_m: float) -> void:
	var lower_stairs: Array[Dictionary] = []
	for room in data.get("rooms_data", []):
		if typeof(room) != TYPE_DICTIONARY:
			continue
		var room_dict: Dictionary = room
		if absf(float(room_dict.get("floor_level_z_m", 0.0)) - lower_level_m) < 0.05 and StairPlanRules.is_stair_room(room_dict):
			lower_stairs.append(room_dict)
	if lower_stairs.is_empty():
		return

	for lower_room in lower_stairs:
		var lower_id: int = int(lower_room.get("id", -1))
		var rect: Rect2 = ScenarioQueries.room_rect(data, lower_id)
		if rect.size.x <= 0.0 or rect.size.y <= 0.0:
			continue
		var upper_id: int = find_matching_stair_room_at_level(rect, upper_level_m)
		if upper_id < 0:
			var floor_name: String = floor_name_for_level(upper_level_m)
			upper_id = create_room_at_level(rect, "Escalera %s" % floor_name, "escalera", upper_level_m, 2.55)
		var stair_dir: Vector2 = StairPlanRules.run_direction_for_room(lower_room)
		var turn_mode: String = StairPlanRules.turn_mode_for_room(lower_room)
		var turn_degrees: float = StairPlanRules.turn_degrees_for_mode(rect, stair_dir, turn_mode)
		apply_stair_defaults(lower_id, stair_dir, turn_degrees)
		apply_stair_defaults(upper_id, stair_dir, turn_degrees)
		set_stair_turn_mode(lower_id, turn_mode)
		set_stair_turn_mode(upper_id, turn_mode)
		add_vertical_stair_opening(lower_id, upper_id, rect)


func find_matching_stair_room_at_level(rect: Rect2, level_m: float) -> int:
	for room in data.get("rooms_data", []):
		if typeof(room) != TYPE_DICTIONARY:
			continue
		var room_dict: Dictionary = room
		if not StairPlanRules.is_stair_room(room_dict):
			continue
		if absf(float(room_dict.get("floor_level_z_m", 0.0)) - level_m) >= 0.05:
			continue
		var other_rect: Rect2 = ScenarioQueries.room_rect(data, int(room_dict.get("id", -1)))
		if rect.position.distance_to(other_rect.position) <= 0.05 and rect.size.distance_to(other_rect.size) <= 0.05:
			return int(room_dict.get("id", -1))
	return -1


func linked_vertical_room_ids(room_id: int) -> Array[int]:
	var ids: Array[int] = []
	for raw_op in data.get("openings_data", []):
		if typeof(raw_op) != TYPE_DICTIONARY:
			continue
		var op: Dictionary = raw_op
		if not bool(op.get("is_vertical", false)):
			continue
		var a_id: int = int(op.get("a", -1))
		var b_id: int = int(op.get("b", -1))
		if a_id == room_id and b_id >= 0:
			ids.append(b_id)
		elif b_id == room_id and a_id >= 0:
			ids.append(a_id)
	return ids


func sync_linked_stair_rects(room_id: int, rect: Rect2) -> void:
	var rects: Dictionary = data.get("room_rect_m", {})
	for linked_id in linked_vertical_room_ids(room_id):
		var linked_room: Dictionary = ScenarioQueries.room_by_id(data, linked_id)
		if StairPlanRules.is_stair_room(linked_room):
			rects[str(linked_id)] = Serializer.rect_to_data(rect)
	data["room_rect_m"] = rects


func apply_stair_rotation_to_linked_rooms(room_id: int, rotation_deg: float, stair_dir: Vector2) -> void:
	var linked_ids: Array[int] = linked_vertical_room_ids(room_id)
	if linked_ids.is_empty():
		return
	var rooms: Array = data.get("rooms_data", [])
	for i in range(rooms.size()):
		if typeof(rooms[i]) != TYPE_DICTIONARY:
			continue
		var linked_id: int = int(Dictionary(rooms[i]).get("id", -1))
		if linked_ids.find(linked_id) < 0:
			continue
		var room: Dictionary = rooms[i]
		if not StairPlanRules.is_stair_room(room):
			continue
		room["rotation_deg"] = rotation_deg
		room["stair_run_direction_m"] = Serializer.vector_to_data(stair_dir)
		rooms[i] = room
	data["rooms_data"] = rooms


func sync_vertical_stair_openings(room_id: int) -> void:
	var openings: Array = data.get("openings_data", [])
	var changed: bool = false
	for i in range(openings.size()):
		if typeof(openings[i]) != TYPE_DICTIONARY:
			continue
		var op: Dictionary = openings[i]
		if not bool(op.get("is_vertical", false)):
			continue
		var a_id: int = int(op.get("a", -1))
		var b_id: int = int(op.get("b", -1))
		if a_id != room_id and b_id != room_id:
			continue
		var lower_id: int = a_id
		if ScenarioQueries.room_level_m(data, b_id) < ScenarioQueries.room_level_m(data, a_id):
			lower_id = b_id
		var rect: Rect2 = ScenarioQueries.room_rect(data, lower_id)
		var lower_room: Dictionary = ScenarioQueries.room_by_id(data, lower_id)
		var stair_dir: Vector2 = StairPlanRules.run_direction_for_room(lower_room)
		var turn_mode: String = StairPlanRules.turn_mode_for_room(lower_room)
		var turn_degrees: float = StairPlanRules.turn_degrees_for_mode(rect, stair_dir, turn_mode)
		set_stair_turn_degrees(lower_id, turn_degrees)
		var other_id: int = b_id if lower_id == a_id else a_id
		if other_id >= 0:
			set_stair_turn_mode(other_id, turn_mode)
			set_stair_turn_degrees(other_id, turn_degrees)
		# El portal guarda su ojo: el paso libre no crece con la huella.
		if StairPlanRules.is_portal_room(lower_room):
			op["width_m"] = portal_eye_side_m(rect)
			op["height_m"] = portal_eye_side_m(rect)
			openings[i] = op
			changed = true
			continue
		var void_rect: Rect2 = StairGeometry.vertical_void_rect(rect, stair_dir, turn_degrees)
		op["width_m"] = void_rect.size.x if absf(stair_dir.y) >= absf(stair_dir.x) else void_rect.size.y
		op["height_m"] = void_rect.size.y if absf(stair_dir.y) >= absf(stair_dir.x) else void_rect.size.x
		openings[i] = op
		changed = true
	if changed:
		data["openings_data"] = openings


# --------------------------------------------------------------------------
# Patio
# --------------------------------------------------------------------------

## El patio de luces: un conducto vertical que atraviesa TODAS las plantas del
## edificio y remata abierto al cielo.
##
## La forma que menos inventa, y la que el motor ya entiende: **una zona por
## planta**, igual que una sala, encadenadas con aperturas verticales de la
## superficie completa del patio, y en la ultima una boca al exterior.
##
## Medido el 2026-09-11 antes de escribir esto: con esa representacion **el motor
## ya hace la fisica del patio sin tocar nada** -el humo sube con retardo
## creciente, entra en las viviendas altas y el O2 del conducto baja de 0,209 a
## 0,146 en cinco minutos-. Las cifras estan en `docs/PROMPT_MOTOR_PATIO.md`.
##
## Tres decisiones que conviene tener escritas:
##
## 1. **Atraviesa las plantas que HAY**, no crea ninguna. Una escalera si crea la
##    de arriba, porque una escalera existe para subir a algun sitio; un patio no
##    añade plantas al edificio, las atraviesa.
## 2. **No se conecta solo con las salas vecinas.** Un pasillo y una escalera si
##    -existen para conectar-, pero a un patio se da con una VENTANA, y donde va
##    esa ventana lo decide quien dibuja: la cocina y el bano dan al patio, el
##    salon casi nunca.
## 3. **La boca no lleva `wall_side`.** Es horizontal y esta abrigada: el viento
##    sobre ella produce succion, no presion frontal, y el motor devuelve 0,0 de
##    ΔP de viento cuando no hay `wall_side`, que como primera aproximacion es lo
##    correcto.
##
## Devuelve los ids de las zonas, de abajo arriba. Vacio si no hay plantas.
func create_patio(rect: Rect2) -> Array[int]:
	var floor_list: Array = floors()
	var ids: Array[int] = []
	if floor_list.is_empty():
		return ids
	begin("create_patio")
	for i in range(floor_list.size()):
		var level_m: float = float(Dictionary(floor_list[i]).get("level_m", 0.0))
		var floor_name: String = String(Dictionary(floor_list[i]).get("name", FloorNaming.label(i)))
		# La altura de la zona es la de la planta: el conducto es continuo y no
		# deja falso techo entre una zona y la siguiente.
		var height_m: float = DEFAULT_FLOOR_HEIGHT_M
		if i + 1 < floor_list.size():
			height_m = maxf(2.0, float(Dictionary(floor_list[i + 1]).get("level_m", level_m + DEFAULT_FLOOR_HEIGHT_M)) - level_m)
		ids.append(create_room_at_level(rect, "Patio %s" % floor_name, "patio", level_m, height_m))

	# Encadenado vertical, con TODA la superficie del patio: entre dos zonas del
	# mismo conducto no hay forjado que atravesar.
	for i in range(ids.size() - 1):
		add_vertical_opening(ids[i], ids[i + 1], rect.size.x, rect.size.y)

	# La boca. Sin ella el patio es un conducto ciego y se presuriza, que es justo
	# lo contrario de lo que hace un patio de luces.
	add_vertical_opening(ids[ids.size() - 1], OUTSIDE_ID, rect.size.x, rect.size.y)
	commit()
	return ids


# --------------------------------------------------------------------------
# Portal
# --------------------------------------------------------------------------

## El portal: el rellano y la caja de escalera comun de un bloque de pisos.
##
## Hasta ahora el rellano solo existia en la vista. En el modelo la puerta de la
## vivienda daba al ambiente, asi que el humo que salia por ella se iba a la calle
## y no subia por ninguna escalera. Medido el 2026-09-12 antes de escribir esto:
## con **una zona de escalera por planta, encadenadas por el ojo y con la puerta
## de cada vivienda dando a la suya**, el motor hace la fisica entera sin tocarlo
## -la caja cerrada se presuriza por arriba hasta 11,4 Pa y un exutorio la baja a
## 3,7-. Cifras en `docs/PROMPT_MOTOR_PORTAL.md`.
##
## Cuatro decisiones que conviene tener escritas:
##
## 1. **Tipo `escalera`**, que es con el que se midio y el que el motor ya trata
##    como caja de escalera. Lo que lo separa de una escalera interior es el
##    nombre, «Portal …», con el mismo criterio que el patio.
## 2. **Atraviesa las plantas que HAY**, como el patio: un portal no añade pisos.
## 3. **Se conecta solo, pero por las PUERTAS DE VIVIENDA, no abriendo huecos.**
##    La puerta de entrada que cae sobre el rellano deja de dar al ambiente y
##    pasa a dar a el, en el mismo sitio. A las demas salas que toque no les abre
##    nada: de una vivienda al portal se pasa por su puerta. Una balconera no se
##    toca aunque caiga ahi: detras de ella hay calle.
## 4. **Cerrado por arriba.** Es el caso que mata en plantas altas y no se
##    suaviza; el exutorio es un hueco que se añade a mano, no un regalo.
##
## Devuelve `ids` (de abajo arriba), `connected` (puertas reconectadas),
## `without_door` (nombres de planta que tocan el portal sin puerta) y
## `street_wall` (vacio si el zaguan no tiene lado libre). Vacio si no hay plantas.
func create_portal(rect: Rect2, start_m: Vector2, end_m: Vector2) -> Dictionary:
	var floor_list: Array = floors()
	if floor_list.is_empty():
		return {}
	begin("create_portal")
	var order: Array = range(floor_list.size())
	order.sort_custom(func(i, j): return float(Dictionary(floor_list[i]).get("level_m", 0.0)) < float(Dictionary(floor_list[j]).get("level_m", 0.0)))

	var stair_dir: Vector2 = StairPlanRules.run_direction_from_drag(start_m, end_m, rect)
	var turn_degrees: float = StairPlanRules.turn_degrees_for_mode(rect, stair_dir, StairPlanRules.MODE_AUTO)
	var ids: Array[int] = []
	var names: Array[String] = []
	for k in range(order.size()):
		var floor: Dictionary = floor_list[int(order[k])]
		var level_m: float = float(floor.get("level_m", 0.0))
		var floor_name: String = String(floor.get("name", FloorNaming.label(int(order[k]))))
		# La caja es continua: cada zona llega hasta el forjado de la siguiente.
		var height_m: float = DEFAULT_FLOOR_HEIGHT_M
		if k + 1 < order.size():
			height_m = maxf(2.0, float(Dictionary(floor_list[int(order[k + 1])]).get("level_m", level_m + DEFAULT_FLOOR_HEIGHT_M)) - level_m)
		var id: int = create_room_at_level(rect, "Portal %s" % floor_name, "escalera", level_m, height_m)
		apply_stair_defaults(id, stair_dir, turn_degrees)
		ids.append(id)
		names.append(floor_name)

	# El ojo de la escalera entre plantas seguidas: es lo que produce el tiro. Con
	# el paso libre del ojo, no con la huella de los tramos (`PORTAL_EYE_SIDE_M`).
	var eye_m: float = portal_eye_side_m(rect)
	for k in range(ids.size() - 1):
		add_vertical_opening(ids[k], ids[k + 1], eye_m, eye_m)

	var connected: int = 0
	var without_door: Array[String] = []
	for k in range(ids.size()):
		var linked: int = connect_dwelling_doors_to_portal(ids[k])
		connected += linked
		if linked == 0 and _portal_touches_rooms(ids[k]):
			without_door.append(names[k])

	# La orientacion del portal la deciden sus puertas, no el gesto: se guarda la
	# subida del reparto real (`ScenarioWalls.portal_layout`) y giro cero. Los
	# valores de escalera la sacaban del arrastre y ponian `rotation_deg` a -90,
	# y el plano dibujaba el portal girado encima de si mismo.
	for id in ids:
		var portal: Dictionary = ScenarioWalls.portal_layout(data, ScenarioQueries.room_by_id(data, id))
		if portal.is_empty():
			continue
		update_room_fields(id, {
			"rotation_deg": 0.0,
			"stair_run_direction_m": Serializer.vector_to_data(Vector2(portal["stair_dir"])),
			"stair_turn_degrees": float(portal["turn_degrees"]),
			"stair_flight_count": 2 if float(portal["turn_degrees"]) >= 179.0 else 1,
		})

	# El zaguan: abajo, la puerta del portal a la calle. Cerrada, que es como esta
	# un portal de verdad; abrirla es una decision del escenario.
	var street: Dictionary = _portal_street_door(ids[0], _portal_landing_wall(ids))
	var street_wall: String = String(street.get("wall", ""))
	if street_wall != "":
		add_opening(
			ids[0], OUTSIDE_ID, "door", street_wall,
			float(street["offset_m"]), float(street["width_m"]),
			PORTAL_STREET_DOOR_HEIGHT_M, 0.0, 0.0, false
		)
	commit()
	return {"ids": ids, "connected": connected, "without_door": without_door, "street_wall": street_wall}


## Las puertas de vivienda de la planta del portal que caen sobre el: dejan de
## dar al ambiente y pasan a dar al rellano, sin moverse de sitio.
##
## Solo puertas enteras dentro del tramo compartido. Una balconera no, aunque
## caiga ahi. Devuelve cuantas se han reconectado.
func connect_dwelling_doors_to_portal(portal_id: int) -> int:
	var level_m: float = ScenarioQueries.room_level_m(data, portal_id)
	var openings: Array = data.get("openings_data", [])
	var count: int = 0
	for i in range(openings.size()):
		if typeof(openings[i]) != TYPE_DICTIONARY:
			continue
		var op: Dictionary = openings[i]
		if String(op.get("type", "")) != "door" or bool(op.get("is_vertical", false)):
			continue
		if bool(op.get("has_balcony", false)):
			continue
		var a_id: int = int(op.get("a", OUTSIDE_ID))
		var b_id: int = int(op.get("b", OUTSIDE_ID))
		var room_id: int = a_id if b_id == OUTSIDE_ID else (b_id if a_id == OUTSIDE_ID else OUTSIDE_ID)
		var wall: String = String(op.get("wall", ""))
		if room_id < 0 or room_id == portal_id or wall == "":
			continue
		if absf(ScenarioQueries.room_level_m(data, room_id) - level_m) >= 0.05:
			continue
		var shared: Dictionary = ScenarioWalls.shared_wall_between(data, room_id, portal_id)
		if shared.is_empty() or String(shared["wall"]) != wall:
			continue
		var probe: Dictionary = op.duplicate()
		probe["a"] = room_id
		probe["b"] = OUTSIDE_ID
		var door_seg: PackedVector2Array = ScenarioWalls.opening_segment_m(data, probe)
		var shared_seg: PackedVector2Array = ScenarioWalls.shared_wall_segment(data, room_id, portal_id, wall)
		if door_seg.size() != 2 or shared_seg.size() != 2:
			continue
		var along_x: bool = WallSideGeometry.is_horizontal(wall)
		var lo: float = minf(shared_seg[0].x, shared_seg[1].x) if along_x else minf(shared_seg[0].y, shared_seg[1].y)
		var hi: float = maxf(shared_seg[0].x, shared_seg[1].x) if along_x else maxf(shared_seg[0].y, shared_seg[1].y)
		var d0: float = door_seg[0].x if along_x else door_seg[0].y
		var d1: float = door_seg[1].x if along_x else door_seg[1].y
		if minf(d0, d1) < lo - 0.02 or maxf(d0, d1) > hi + 0.02:
			continue
		op["a"] = room_id
		op["b"] = portal_id
		op["offset_m"] = PlanGeometry.offset_on_wall(ScenarioQueries.room_rect(data, room_id), wall, (door_seg[0] + door_seg[1]) * 0.5)
		op["offset_is_fraction"] = false
		openings[i] = op
		count += 1
	data["openings_data"] = openings
	return count


## El ojo cabe en el portal: en uno estrecho no puede ser mas ancho que la caja.
static func portal_eye_side_m(rect: Rect2) -> float:
	return minf(PORTAL_EYE_SIDE_M, maxf(0.2, minf(rect.size.x, rect.size.y) - 0.2))


## ¿Toca el portal alguna sala de su planta? Si toca y no hay puerta, conviene
## decirlo: en el plano parece conectado y en el modelo esta tapiado.
func _portal_touches_rooms(portal_id: int) -> bool:
	for raw in data.get("rooms_data", []):
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var other_id: int = int(Dictionary(raw).get("id", -1))
		if other_id < 0 or other_id == portal_id:
			continue
		if not ScenarioWalls.shared_wall_between(data, portal_id, other_id).is_empty():
			return true
	return false


## La pared del rellano: la del portal que da a mas puertas de vivienda, contadas
## en todas sus plantas. Es el mismo voto que hace la vista para repartir el
## rellano y la escalera (`PortalGeometry.landing_side`). Vacio si no hay puertas.
func _portal_landing_wall(ids: Array[int]) -> String:
	var votes: Dictionary = {}
	for raw in data.get("openings_data", []):
		if typeof(raw) != TYPE_DICTIONARY or bool(Dictionary(raw).get("is_vertical", false)):
			continue
		var a_id: int = int(Dictionary(raw).get("a", OUTSIDE_ID))
		var b_id: int = int(Dictionary(raw).get("b", OUTSIDE_ID))
		var zone_id: int = a_id if ids.has(a_id) else (b_id if ids.has(b_id) else OUTSIDE_ID)
		var other_id: int = b_id if zone_id == a_id else a_id
		if zone_id < 0 or other_id < 0 or ids.has(other_id):
			continue
		var shared: Dictionary = ScenarioWalls.shared_wall_between(data, zone_id, other_id)
		if not shared.is_empty():
			votes[String(shared["wall"])] = int(votes.get(String(shared["wall"]), 0)) + 1
	var best: String = ""
	for wall in ["left", "top", "right", "bottom"]:
		if int(votes.get(wall, 0)) > int(votes.get(best, 0)):
			best = wall
	return best


## La puerta del zaguan a la calle: pared, posicion y ancho.
##
## En un lado PERPENDICULAR a la pared del rellano, y centrada en la franja de
## rellano. La vista sube la escalera en sentido contrario a las puertas, asi que
## una puerta en el lado de enfrente quedaba detras de los tramos, bajo la meseta
## y sin paso. Si no hay lado perpendicular libre, se usa el resto de lados como
## antes: el opuesto a la vivienda y, si no, el mas largo.
func _portal_street_door(portal_id: int, landing_wall: String) -> Dictionary:
	var rect: Rect2 = ScenarioQueries.room_rect(data, portal_id)
	if landing_wall != "":
		for wall in ["top", "bottom", "left", "right"]:
			if wall == landing_wall or wall == WallSideGeometry.opposite(landing_wall):
				continue
			if _portal_wall_blocked(portal_id, wall):
				continue
			var length_m: float = PlanGeometry.wall_length(rect, wall)
			var depth_m: float = clampf(PortalGeometry.LANDING_DEPTH_M, 0.0, maxf(0.0, length_m - PortalGeometry.MIN_STAIR_LONG_M))
			if depth_m < 0.90:
				break
			# Los muros corren de izquierda a derecha y de arriba abajo: el rellano
			# empieza en el arranque del muro si esta a la izquierda o arriba.
			var from_start: bool = landing_wall == "left" or landing_wall == "top"
			return {
				"wall": wall,
				"offset_m": depth_m * 0.5 if from_start else length_m - depth_m * 0.5,
				"width_m": minf(PORTAL_STREET_DOOR_WIDTH_M, depth_m - 0.10),
			}
	var fallback: String = _portal_street_wall(portal_id)
	if fallback == "":
		return {}
	return {
		"wall": fallback,
		"offset_m": PlanGeometry.wall_length(rect, fallback) * 0.5,
		"width_m": minf(PORTAL_STREET_DOOR_WIDTH_M, PlanGeometry.wall_length(rect, fallback) - 0.10),
	}


func _portal_wall_blocked(portal_id: int, wall: String) -> bool:
	for raw in data.get("rooms_data", []):
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var other_id: int = int(Dictionary(raw).get("id", -1))
		if other_id < 0 or other_id == portal_id:
			continue
		var shared: Dictionary = ScenarioWalls.shared_wall_between(data, portal_id, other_id)
		if not shared.is_empty() and String(shared["wall"]) == wall:
			return true
	return false


## Un lado del portal que no toque ninguna sala de su planta. Se prefiere el
## opuesto a la vivienda y, si no, el mas largo. Vacio si esta rodeado.
func _portal_street_wall(portal_id: int) -> String:
	var rect: Rect2 = ScenarioQueries.room_rect(data, portal_id)
	var blocked: Dictionary = {}
	for raw in data.get("rooms_data", []):
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var other_id: int = int(Dictionary(raw).get("id", -1))
		if other_id < 0 or other_id == portal_id:
			continue
		var shared: Dictionary = ScenarioWalls.shared_wall_between(data, portal_id, other_id)
		if not shared.is_empty():
			blocked[String(shared["wall"])] = true
	var best: String = ""
	var best_score: float = -1.0
	for wall in ["top", "bottom", "left", "right"]:
		if blocked.has(wall):
			continue
		var score: float = PlanGeometry.wall_length(rect, wall)
		if blocked.has(WallSideGeometry.opposite(wall)):
			score += 100.0
		if score > best_score:
			best_score = score
			best = wall
	return best

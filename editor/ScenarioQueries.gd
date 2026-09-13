extends RefCounted
## Las preguntas basicas al escenario: quien es cada sala, cada objeto y cada
## marcador, y que id le toca al siguiente.
##
## Segundo corte de la **capa de preguntas** (D-1), y el sitio donde vive la
## capa: `ScenarioWalls` se apoya aqui, y los cortes siguientes tambien.
##
## Estatico y puro. Recibe el diccionario del escenario, **no lo guarda y no lo
## toca**. Esa es toda la frontera: si una funcion necesita escribir, no es de
## este modulo.
##
## Un aviso sobre lo que se devuelve: `room_by_id()` y `object_at()` devuelven el
## **diccionario de verdad, no una copia** —en GDScript un `Dictionary` es una
## referencia—. Quien lo reciba puede cambiarlo sin querer y el cambio se queda
## en el escenario. Se hace asi a proposito porque es lo que hacia el editor y
## cambiarlo ahora seria un cambio de comportamiento escondido en un refactor,
## pero conviene tenerlo presente.


const Serializer = preload("res://editor/ScenarioSerializer.gd")


## ── Salas ───────────────────────────────────────────────────────────────────

## El rectangulo de una sala en planta, tal y como esta guardado.
static func room_rect(data: Dictionary, room_id: int) -> Rect2:
	var rects: Dictionary = data.get("room_rect_m", {})
	return Serializer.rect2_from_data(rects.get(str(room_id), Rect2()))


## La sala con ese id, o un diccionario vacio.
static func room_by_id(data: Dictionary, room_id: int) -> Dictionary:
	for raw_room in data.get("rooms_data", []):
		if typeof(raw_room) == TYPE_DICTIONARY and int(Dictionary(raw_room).get("id", -1)) == room_id:
			return raw_room
	return {}


## En que posicion de `rooms_data` esta esa sala, o -1.
static func room_index_for_id(data: Dictionary, room_id: int) -> int:
	var rooms: Array = data.get("rooms_data", [])
	for i in range(rooms.size()):
		if typeof(rooms[i]) == TYPE_DICTIONARY and int(Dictionary(rooms[i]).get("id", -1)) == room_id:
			return i
	return -1


## La cota de la planta de una sala ya leida.
static func room_level_of(room: Dictionary) -> float:
	return float(room.get("floor_level_z_m", 0.0))


## La cota de la planta de la sala con ese id. Sin sala, la rasante.
static func room_level_m(data: Dictionary, room_id: int) -> float:
	var room: Dictionary = room_by_id(data, room_id)
	return room_level_of(room) if not room.is_empty() else 0.0


static func room_rotation_deg(data: Dictionary, room_id: int) -> float:
	var room: Dictionary = room_by_id(data, room_id)
	return float(room.get("rotation_deg", 0.0)) if not room.is_empty() else 0.0


## Los nombres de sala ya usados, como conjunto.
static func room_names(data: Dictionary) -> Dictionary:
	var names: Dictionary = {}
	for raw_room in data.get("rooms_data", []):
		if typeof(raw_room) == TYPE_DICTIONARY:
			names[String(Dictionary(raw_room).get("name", ""))] = true
	return names


static func victim_names(data: Dictionary) -> Dictionary:
	var names: Dictionary = {}
	for raw in Array(data.get("victims", [])):
		if typeof(raw) == TYPE_DICTIONARY:
			names[String(Dictionary(raw).get("name", ""))] = true
	return names


## ── Objetos de una sala ─────────────────────────────────────────────────────

## El objeto que ocupa esa posicion dentro de su sala, o un diccionario vacio.
static func object_at(data: Dictionary, room_id: int, object_index: int) -> Dictionary:
	var room: Dictionary = room_by_id(data, room_id)
	var objects: Array = room.get("fuel_objects", [])
	if object_index < 0 or object_index >= objects.size():
		return {}
	if typeof(objects[object_index]) != TYPE_DICTIONARY:
		return {}
	return objects[object_index]


static func object_index_for_id(data: Dictionary, room_id: int, object_id: String) -> int:
	var room: Dictionary = room_by_id(data, room_id)
	if room.is_empty():
		return -1
	var objects: Array = room.get("fuel_objects", [])
	for i in range(objects.size()):
		if typeof(objects[i]) == TYPE_DICTIONARY and String(Dictionary(objects[i]).get("id", "")) == object_id:
			return i
	return -1


## ── Identificadores ─────────────────────────────────────────────────────────

## El primer id libre con ese patron. `taken` es el conjunto de los usados.
static func first_free_id(pattern: String, taken: Dictionary) -> String:
	var n: int = 1
	while taken.has(pattern % n):
		n += 1
	return pattern % n


## Los ids ya usados de una lista de primer nivel ("detectors", "victims"...).
static func taken_ids(data: Dictionary, list_key: String) -> Dictionary:
	var taken: Dictionary = {}
	for raw in Array(data.get(list_key, [])):
		if typeof(raw) == TYPE_DICTIONARY:
			taken[String(Dictionary(raw).get("id", ""))] = true
	return taken


## Los ids de mueble ya usados, que viven repartidos por las salas y no en una
## lista de primer nivel. `pending` son los que todavia no estan en el escenario
## -una sala que se esta pegando, por ejemplo- y que tampoco se pueden repetir.
static func taken_object_ids(data: Dictionary, pending: Array = []) -> Dictionary:
	var taken: Dictionary = {}
	for raw_room in data.get("rooms_data", []):
		if typeof(raw_room) != TYPE_DICTIONARY:
			continue
		for raw_obj in Array(Dictionary(raw_room).get("fuel_objects", [])):
			if typeof(raw_obj) == TYPE_DICTIONARY:
				taken[String(Dictionary(raw_obj).get("id", ""))] = true
	for raw_pending in pending:
		if typeof(raw_pending) == TYPE_DICTIONARY:
			taken[String(Dictionary(raw_pending).get("id", ""))] = true
	return taken


## El siguiente id de sala: uno mas que el mayor que haya.
static func next_room_id(data: Dictionary) -> int:
	var next_id: int = 0
	for raw_room in data.get("rooms_data", []):
		if typeof(raw_room) == TYPE_DICTIONARY:
			next_id = maxi(next_id, int(Dictionary(raw_room).get("id", -1)) + 1)
	return next_id


static func next_object_id(data: Dictionary, pending: Array = []) -> String:
	return first_free_id("obj_%03d", taken_object_ids(data, pending))


static func next_detector_id(data: Dictionary) -> String:
	return first_free_id("det_%03d", taken_ids(data, "detectors"))


static func next_victim_id(data: Dictionary) -> String:
	return first_free_id("vic_%03d", taken_ids(data, "victims"))

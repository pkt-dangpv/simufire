extends RefCounted

## Puerta de entrada unica al mobiliario de una sala, para las dos vistas.
##
## Antes esto era una lista de poses escritas a mano por tipo de sala -salon,
## cocina, bano, pasillo- con las coordenadas metidas en el codigo. Tenia dos
## problemas. El primero, que solo se aplicaba a objetos SIN posicion, y como
## todas las plantillas del catalogo declaran una, no llegaba a ejecutarse
## nunca: era codigo muerto. El segundo, que un dormitorio no estaba
## contemplado, asi que ahi no habia ninguna regla en absoluto.
##
## Lo que decide donde va cada pieza esta ahora en `FurnitureRoomLayout`, y son
## reglas de vivienda -contra el paramento, sin pisarse, sin tapar una puerta-
## en vez de coordenadas fijas. El tamano lo decide `FurnitureDimensions`.
##
## Las dos vistas llaman aqui: el mundo en primera persona y la maqueta del
## visor 3D reparten el mobiliario igual, aunque luego cada una lo dibuje a su
## manera. Es la misma regla que impuso FP-3 para la geometria del edificio.

const FurnitureRoomFurnisher := preload("res://view/furniture/FurnitureRoomFurnisher.gd")
const FurnitureRoomLayout := preload("res://view/furniture/FurnitureRoomLayout.gd")
const FurnitureVisualClassifier := preload("res://view/3d/furniture/FurnitureVisualClassifier.gd")


## Resuelve el mobiliario de una sala: tamano real y pose definitiva.
##
## `building` puede ser nulo -entonces no se reservan bandas de paso ni se
## amuebla, que es lo unico que necesita el modelo del edificio-.
##
## `furnish_empty` pone ATREZO en las salas que el escenario deja sin objetos.
## Es un apano declarado y temporal: siete de las diez plantillas del catalogo
## declaran su carga de fuego a granel y sus habitaciones se recorren vacias.
## El atrezo no arde ni existe para el modelo; el dia que esas plantillas traigan
## objetos de verdad, la sala llega con `fuel_objects` y el atrezo no se genera.
static func normalize_room(building, room_id: int, rect: Rect2, raw_objects: Array, furnish_empty: bool = true) -> Array:
	var specs: Array = []
	for raw in raw_objects:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var spec: Dictionary = Dictionary(raw).duplicate(true)
		var obj_id: String = String(spec.get("id", ""))
		if obj_id == "" or obj_id.begins_with("room_proxy_"):
			continue
		# El atrezo llega diciendo lo que es; solo se clasifica lo que no lo
		# dice. Sin esto una "Cama" individual del atrezo se ascendia a cama de
		# matrimonio y dejaba de caber en la habitacion.
		if String(spec.get("visual_archetype", "")) == "":
			spec["visual_archetype"] = FurnitureVisualClassifier.visual_archetype(spec)
		specs.append(spec)
	if specs.is_empty():
		if not furnish_empty or building == null:
			return []
		specs = _props_for_room(building, room_id, rect)
		if specs.is_empty():
			return []
	var doors: Array = FurnitureRoomLayout.doors_for_room(building, room_id, rect)
	var placed: Array = FurnitureRoomLayout.layout_room(rect.size, doors, specs)
	var visible: Array = []
	for spec in placed:
		if typeof(spec) == TYPE_DICTIONARY and not bool(Dictionary(spec).get("visual_hidden", false)):
			visible.append(spec)
	return visible


static func _props_for_room(building, room_id: int, rect: Rect2) -> Array:
	var room: RoomModel = building.get_room(room_id)
	if room == null:
		return []
	return FurnitureRoomFurnisher.furnish(room_id, room.name, room.kind, rect.size)

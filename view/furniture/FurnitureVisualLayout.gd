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

const FurnitureRoomLayout := preload("res://view/furniture/FurnitureRoomLayout.gd")
const FurnitureVisualClassifier := preload("res://view/3d/furniture/FurnitureVisualClassifier.gd")


## Resuelve el mobiliario de una sala: tamano real y pose definitiva.
##
## `building` puede ser nulo -entonces no se reservan bandas de paso, que es lo
## unico que necesita el modelo del edificio-.
static func normalize_room(building, room_id: int, rect: Rect2, raw_objects: Array) -> Array:
	var specs: Array = []
	for raw in raw_objects:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var spec: Dictionary = Dictionary(raw).duplicate(true)
		var obj_id: String = String(spec.get("id", ""))
		if obj_id == "" or obj_id.begins_with("room_proxy_"):
			continue
		spec["visual_archetype"] = FurnitureVisualClassifier.visual_archetype(spec)
		specs.append(spec)
	if specs.is_empty():
		return []
	var doors: Array = FurnitureRoomLayout.doors_for_room(building, room_id, rect)
	return FurnitureRoomLayout.layout_room(rect.size, doors, specs)

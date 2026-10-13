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
const FurnitureAssetLoader := preload("res://view/3d/furniture/FurnitureAssetLoader.gd")

## Only these fields are dynamic and NOT read by the placement algorithm.
## Unknown fields stay in the exact key: conservative invalidation, not guesses.
const DYNAMIC_FIELDS: Array[String] = [
	"state", "hrr_kw", "remaining_fuel_MJ", "temp_c", "surface_temp_c", "temperature_c",
	"incident_heat_flux_kw_m2", "t_ignition_s", "is_primary_ignition_source",
]
const MAX_CACHED_ROOMS: int = 128
const MAX_ASSET_RESOURCES: int = 128
static var _room_cache: Dictionary = {}
static var _asset_resources: Dictionary = {}
static var _cache_hits: int = 0
static var _cache_misses: int = 0
static var _asset_invalidator: Callable = Callable()


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
static func normalize_room(building: BuildingModel, room_id: int, rect: Rect2, raw_objects: Array, furnish_empty: bool = true) -> Array:
	var specs: Array = _prepare_specs(building, room_id, rect, raw_objects, furnish_empty)
	var doors: Array = FurnitureRoomLayout.doors_for_room(building, room_id, rect)
	var geometry: Array = []
	for raw: Dictionary in specs:
		var spec: Dictionary = raw.duplicate(true)
		for field: String in DYNAMIC_FIELDS:
			spec.erase(field)
		geometry.append(spec)
	var key: PackedByteArray = var_to_bytes([rect, doors, geometry, _asset_tokens(specs)])
	_prune_dead_owners()
	var owner_id: int = building.get_instance_id() if building != null else 0
	var slot: String = "%d:%d" % [owner_id, room_id]
	if _room_cache.has(slot) and _room_cache[slot]["key"] == key:
		_cache_hits += 1
		return _apply_pose_patches(specs, _room_cache[slot]["patches"])
	_cache_misses += 1
	var placed: Array = FurnitureRoomLayout.layout_room(rect.size, doors, specs)
	var patches: Array = []
	for index: int in range(placed.size()):
		var patch: Dictionary = {}
		for field: Variant in placed[index]:
			if not specs[index].has(field) or placed[index][field] != specs[index][field]:
				patch[field] = _copy_value(placed[index][field])
		patches.append(patch)
	if not _room_cache.has(slot) and _room_cache.size() >= MAX_CACHED_ROOMS:
		_room_cache.erase(_room_cache.keys()[0])
	_room_cache[slot] = {"key": key, "patches": patches,
		"owner": weakref(building) if building != null else null}
	return _visible(placed)


## Independent uncached oracle: identical placement algorithm, no room cache.
static func normalize_room_uncached(building: BuildingModel, room_id: int, rect: Rect2, raw_objects: Array, furnish_empty: bool = true) -> Array:
	var specs: Array = _prepare_specs(building, room_id, rect, raw_objects, furnish_empty)
	var doors: Array = FurnitureRoomLayout.doors_for_room(building, room_id, rect)
	return _visible(FurnitureRoomLayout.layout_room(rect.size, doors, specs))


static func _prepare_specs(building: BuildingModel, room_id: int, rect: Rect2, raw_objects: Array, furnish_empty: bool) -> Array:
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
	# Un preset jugable puede pedir una vivienda completa aun cuando solo haya
	# un objeto de fuego. El relleno sigue en la vista: nunca entra en fuel_objects.
	if furnish_empty and building != null:
		var room: RoomModel = building.get_room(room_id)
		if room != null and room.visual_furniture_fill:
			var represented: Dictionary = {}
			for spec in specs:
				represented[String(spec.get("visual_archetype", ""))] = true
			for prop in _props_for_room(building, room_id, rect):
				if not represented.has(String(prop.get("visual_archetype", ""))):
					specs.append(prop)
	if specs.is_empty():
		if not furnish_empty or building == null:
			return []
		specs = _props_for_room(building, room_id, rect)
		if specs.is_empty():
			return []
	return specs


static func _visible(placed: Array) -> Array:
	var visible: Array = []
	for spec in placed:
		if typeof(spec) == TYPE_DICTIONARY and not bool(Dictionary(spec).get("visual_hidden", false)):
			visible.append(spec)
	return visible


static func _copy_value(value: Variant) -> Variant:
	return value.duplicate(true) if value is Array or value is Dictionary else value


static func _apply_pose_patches(specs: Array, patches: Array) -> Array:
	var placed: Array = []
	for index: int in range(specs.size()):
		var current: Dictionary = specs[index].duplicate(true)
		for field: Variant in patches[index]:
			current[field] = _copy_value(patches[index][field])
		placed.append(current)
	return _visible(placed)


static func _prune_dead_owners() -> void:
	for slot: String in _room_cache.keys():
		var owner: WeakRef = _room_cache[slot]["owner"]
		if owner != null and owner.get_ref() == null:
			_room_cache.erase(slot)


## Rebuild/reload invalidates placement AND the preexisting native-size cache.
## Asset resources are retained (bounded) so loading the same PackedScene does
## not manufacture a new identity every frame. No BuildingModel/Node is pinned.
static func invalidate_all() -> void:
	_room_cache.clear()
	FurnitureAssetLoader.invalidate_native_sizes()


static func cache_stats() -> Dictionary:
	_prune_dead_owners()
	return {"entries": _room_cache.size(), "hits": _cache_hits, "misses": _cache_misses,
		"asset_resources": _asset_resources.size()}


static func _asset_tokens(specs: Array) -> Array:
	var tokens: Array = []
	var seen: Dictionary = {}
	for spec: Dictionary in specs:
		var kind: String = String(spec.get("visual_archetype", ""))
		var path: String = FurnitureAssetLoader.model_path(kind)
		if seen.has(path):
			continue
		seen[path] = true
		if not ResourceLoader.exists(path):
			tokens.append([path, 0, "absent"])
			continue
		var packed := ResourceLoader.load(path) as PackedScene
		if packed == null:
			tokens.append([path, 0, "not_packed"])
			continue
		if not _asset_resources.has(path) or _asset_resources[path] != packed:
			if _asset_resources.has(path):
				invalidate_all()
			if not _asset_resources.has(path) and _asset_resources.size() >= MAX_ASSET_RESOURCES:
				_asset_resources.erase(_asset_resources.keys()[0])
				invalidate_all()
			_asset_resources[path] = packed
			if _asset_invalidator.is_null():
				_asset_invalidator = func(): invalidate_all()
			if not packed.changed.is_connected(_asset_invalidator):
				packed.changed.connect(_asset_invalidator)
		tokens.append([path, packed.get_instance_id(), FurnitureAssetLoader.declared_transform_mode(kind)])
	return tokens


static func _props_for_room(building: BuildingModel, room_id: int, rect: Rect2) -> Array:
	var room: RoomModel = building.get_room(room_id)
	if room == null:
		return []
	return FurnitureRoomFurnisher.furnish(room_id, room.name, room.kind, rect.size)

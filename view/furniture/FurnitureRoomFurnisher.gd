extends RefCounted

## Amuebla con ATREZO las salas que el escenario deja vacias.
##
## Siete de las diez plantillas del catalogo -compact_apartment, los pisos de
## dos y tres dormitorios, el adosado, el ranch, el bungalow y el piso
## mediterraneo- declaran su carga de fuego a granel, en MJ por sala, sin un
## solo `fuel_object`. El modelo de fuego se apana con eso, pero al recorrerlas
## a pie son cajas vacias.
##
## Lo que se pone aqui es atrezo: existe solo en la vista, no arde, no aparece
## en el HUD y no toca el modelo. Es deliberado y es temporal. Cuando el motor
## tenga objetos de verdad para esas plantillas, la sala llegara con
## `fuel_objects` y el atrezo NO se genera: esta condicionado a que la sala
## venga vacia, asi que la sustitucion no hay que acordarse de hacerla.
##
## Cada pieza se declara por lo que es y por donde deberia caer; el tamano lo
## pone `FurnitureDimensions` y el sitio exacto `FurnitureRoomLayout`. Aqui solo
## se decide QUE hay en una sala segun su tipo y lo grande que sea, que es lo
## unico que se sabe cuando el escenario no dice nada.

## Por debajo de esto una sala no se amuebla: un armario empotrado o un hueco
## de escalera no llevan nada.
const MIN_ROOM_AREA_M2: float = 2.0

## Los pasillos estrechos solo admiten cosas contra el paramento.
const NARROW_HALLWAY_M: float = 1.30


## Devuelve las fichas de atrezo de una sala, o vacio si no le toca ninguna.
static func furnish(room_id: int, room_name: String, room_kind: String, room_size: Vector2) -> Array:
	var w: float = maxf(0.1, room_size.x)
	var d: float = maxf(0.1, room_size.y)
	var area: float = w * d
	if area < MIN_ROOM_AREA_M2:
		return []
	var kind: String = room_kind.strip_edges().to_lower()
	var name: String = room_name.strip_edges().to_lower()

	# El nombre afina lo que el tipo no distingue: un estudio y un dormitorio
	# son los dos "dormitorio", y un lavadero puede venir como cocina, almacen
	# o trastero segun la plantilla.
	if _mentions(name, ["lavadero", "laundry", "lavanderia"]):
		return _laundry(room_id, w, d)
	if _mentions(name, ["estudio", "despacho", "office", "study"]):
		return _study(room_id, w, d)
	if _mentions(name, ["comedor", "dining"]) and not _mentions(name, ["salon", "living"]):
		return _dining(room_id, w, d)
	if _mentions(name, ["armario", "closet"]):
		return _storage_room(room_id, w, d)

	match kind:
		"salon":
			return _living(room_id, w, d)
		"dormitorio":
			return _bedroom(room_id, w, d)
		"cocina":
			return _kitchen(room_id, w, d)
		"bano":
			return _bathroom(room_id, w, d)
		"pasillo":
			return _hallway(room_id, w, d)
		"almacen", "trastero":
			return _storage_room(room_id, w, d)
		_:
			return []


static func _living(room_id: int, w: float, d: float) -> Array:
	var area: float = w * d
	var pieces: Array = []
	pieces.append(_piece(room_id, "sofa", "Sofa", Vector2(clampf(w * 0.5, 1.60, 3.20), 0.90), Vector2(w * 0.5, 0.45)))
	pieces.append(_piece(room_id, "tv_stand", "Mueble TV", Vector2(clampf(w * 0.35, 1.00, 2.00), 0.40), Vector2(w * 0.5, d - 0.25)))
	pieces.append(_piece(room_id, "coffee_table", "Mesa de centro", Vector2(clampf(w * 0.25, 0.80, 1.40), 0.60), Vector2(w * 0.5, d * 0.5)))
	pieces.append(_floor_piece(room_id, "rug", "Alfombra", Vector2(clampf(w * 0.55, 1.20, 3.20), clampf(d * 0.40, 0.90, 2.20)), Vector2(w * 0.5, d * 0.52)))
	if area >= 14.0:
		pieces.append(_piece(room_id, "armchair", "Sillon", Vector2(0.85, 0.85), Vector2(w * 0.82, d * 0.72)))
	if area >= 16.0:
		pieces.append(_piece(room_id, "bookcase", "Libreria", Vector2(clampf(d * 0.35, 0.60, 1.80), 0.30), Vector2(0.25, d * 0.5)))
	if area >= 20.0:
		pieces.append(_piece(room_id, "plant", "Planta", Vector2(0.50, 0.50), Vector2(w - 0.45, 0.45)))
	return pieces


static func _dining(room_id: int, w: float, d: float) -> Array:
	var pieces: Array = []
	pieces.append(_piece(room_id, "table", "Mesa de comedor", Vector2(clampf(w * 0.45, 1.00, 2.20), 0.85), Vector2(w * 0.5, d * 0.5)))
	pieces.append(_piece(room_id, "chair", "Silla", Vector2(0.45, 0.50), Vector2(w * 0.5 - 0.75, d * 0.5)))
	pieces.append(_piece(room_id, "chair", "Silla", Vector2(0.45, 0.50), Vector2(w * 0.5 + 0.75, d * 0.5), 2))
	pieces.append(_piece(room_id, "dresser", "Aparador", Vector2(clampf(w * 0.35, 0.70, 1.60), 0.45), Vector2(w * 0.5, 0.30)))
	if w * d >= 14.0:
		pieces.append(_floor_piece(room_id, "rug", "Alfombra", Vector2(clampf(w * 0.55, 1.20, 2.80), clampf(d * 0.45, 0.90, 2.20)), Vector2(w * 0.5, d * 0.5)))
	return pieces


static func _bedroom(room_id: int, w: float, d: float) -> Array:
	var area: float = w * d
	var pieces: Array = []
	# Una cama de matrimonio pide sitio; en un dormitorio pequeno va una
	# individual, que es lo que hay en una casa.
	var bed_kind: String = "bed" if area >= 11.0 else "bed_single"
	pieces.append(_piece(room_id, bed_kind, "Cama", Vector2(2.00, 1.50), Vector2(w * 0.5, d * 0.40)))
	pieces.append(_piece(room_id, "wardrobe", "Armario", Vector2(clampf(w * 0.40, 0.80, 2.40), 0.60), Vector2(0.35, d * 0.5)))
	pieces.append(_piece(room_id, "side_table", "Mesilla", Vector2(0.45, 0.40), Vector2(w * 0.5 - 1.20, d * 0.30)))
	if area >= 9.0:
		pieces.append(_floor_piece(room_id, "rug", "Alfombra", Vector2(clampf(w * 0.40, 0.90, 2.00), clampf(d * 0.30, 0.60, 1.40)), Vector2(w * 0.5, d * 0.75)))
	if area >= 12.0:
		pieces.append(_piece(room_id, "desk", "Escritorio", Vector2(clampf(w * 0.35, 0.90, 1.80), 0.60), Vector2(w - 0.40, d * 0.5)))
		pieces.append(_piece(room_id, "chair_desk", "Silla de escritorio", Vector2(0.60, 0.60), Vector2(w - 1.10, d * 0.5)))
	return pieces


static func _study(room_id: int, w: float, d: float) -> Array:
	var pieces: Array = []
	pieces.append(_piece(room_id, "desk", "Escritorio", Vector2(clampf(w * 0.45, 0.90, 1.80), 0.60), Vector2(w * 0.5, 0.40)))
	pieces.append(_piece(room_id, "chair_desk", "Silla de escritorio", Vector2(0.60, 0.60), Vector2(w * 0.5, 1.10)))
	pieces.append(_piece(room_id, "bookcase", "Libreria", Vector2(clampf(d * 0.40, 0.60, 1.80), 0.30), Vector2(0.25, d * 0.5)))
	if w * d >= 10.0:
		pieces.append(_piece(room_id, "storage", "Archivador", Vector2(clampf(w * 0.30, 0.60, 1.60), 0.40), Vector2(w - 0.35, d * 0.5)))
	return pieces


static func _kitchen(room_id: int, w: float, d: float) -> Array:
	var area: float = w * d
	var pieces: Array = []
	# El frente de cocina se lleva la pared larga entera menos el paso.
	var run_m: float = clampf(maxf(w, d) - 1.40, 0.60, 4.20)
	pieces.append(_piece(room_id, "kitchen_unit", "Encimera y bajos", Vector2(run_m, 0.60), Vector2(w * 0.5, 0.35)))
	pieces.append(_piece(room_id, "kitchen_fridge", "Nevera", Vector2(0.65, 0.60), Vector2(0.40, d - 0.40)))
	pieces.append(_piece(room_id, "kitchen_stove", "Placa y horno", Vector2(0.60, 0.60), Vector2(w * 0.30, 0.35)))
	pieces.append(_piece(room_id, "kitchen_sink", "Fregadero", Vector2(0.60, 0.60), Vector2(w * 0.70, 0.35)))
	if area >= 9.0:
		pieces.append(_piece(room_id, "table", "Mesa de cocina", Vector2(clampf(w * 0.30, 1.00, 1.60), 0.85), Vector2(w * 0.5, d * 0.72)))
	return pieces


static func _laundry(room_id: int, w: float, d: float) -> Array:
	var pieces: Array = []
	pieces.append(_piece(room_id, "washer", "Lavadora", Vector2(0.60, 0.60), Vector2(0.45, 0.40)))
	pieces.append(_piece(room_id, "dryer", "Secadora", Vector2(0.60, 0.60), Vector2(1.15, 0.40)))
	if w * d >= 4.0:
		pieces.append(_piece(room_id, "storage", "Estanteria", Vector2(clampf(w * 0.40, 0.60, 1.60), 0.40), Vector2(w * 0.5, d - 0.35)))
	pieces.append(_piece(room_id, "textile_pile", "Ropa", Vector2(0.50, 0.40), Vector2(w * 0.8, d * 0.6)))
	return pieces


static func _bathroom(room_id: int, w: float, d: float) -> Array:
	var area: float = w * d
	var pieces: Array = []
	pieces.append(_piece(room_id, "toilet", "Inodoro", Vector2(0.70, 0.38), Vector2(0.45, d * 0.72)))
	pieces.append(_piece(room_id, "sink", "Lavabo", Vector2(0.60, 0.45), Vector2(w * 0.5, 0.30)))
	# En un aseo pequeno no cabe banera: va ducha, que es lo que se pone.
	if area >= 5.5:
		pieces.append(_piece(room_id, "bathtub", "Banera", Vector2(1.70, 0.75), Vector2(w * 0.5, d - 0.45)))
	else:
		pieces.append(_piece(room_id, "shower", "Ducha", Vector2(0.90, 0.90), Vector2(w - 0.55, d - 0.55)))
	pieces.append(_piece(room_id, "textile_pile", "Toallas", Vector2(0.45, 0.35), Vector2(w - 0.40, d * 0.35)))
	return pieces


static func _hallway(room_id: int, w: float, d: float) -> Array:
	var pieces: Array = []
	var narrow: float = minf(w, d)
	var long_axis: float = maxf(w, d)
	# La alfombra de pasillo es una tira: sigue el eje largo.
	var runner := Vector2(clampf(long_axis - 1.20, 0.60, 6.00), clampf(narrow * 0.45, 0.40, 1.10))
	if d > w:
		runner = Vector2(runner.y, runner.x)
	pieces.append(_floor_piece(room_id, "rug", "Alfombra", runner, Vector2(w * 0.5, d * 0.5)))
	if narrow >= NARROW_HALLWAY_M:
		pieces.append(_piece(room_id, "dresser", "Consola", Vector2(clampf(long_axis * 0.25, 0.70, 1.20), 0.45), Vector2(0.30, d * 0.5)))
	if w * d >= 6.0:
		pieces.append(_piece(room_id, "plant", "Planta", Vector2(0.50, 0.50), Vector2(w - 0.40, d - 0.40)))
	return pieces


static func _storage_room(room_id: int, w: float, d: float) -> Array:
	var pieces: Array = []
	pieces.append(_piece(room_id, "storage", "Estanteria", Vector2(clampf(maxf(w, d) * 0.45, 0.60, 1.60), 0.40), Vector2(w * 0.5, 0.35)))
	pieces.append(_piece(room_id, "clutter", "Cajas", Vector2(0.60, 0.50), Vector2(w * 0.5, d - 0.45)))
	if w * d >= 4.0:
		pieces.append(_piece(room_id, "containers", "Cubos", Vector2(0.45, 0.45), Vector2(w - 0.40, d * 0.5), 2))
	return pieces


static func _piece(
	room_id: int,
	archetype: String,
	label: String,
	size_m: Vector2,
	center_m: Vector2,
	copy: int = 1
) -> Dictionary:
	return {
		"id": "decor_%d_%s_%d" % [room_id, archetype, copy],
		"name": label,
		"kind": archetype,
		"room_id": room_id,
		"visual_archetype": archetype,
		"visual_only": true,
		"state": "cold",
		"size_m": size_m,
		"position_m": center_m - size_m * 0.5,
		"rotation_deg": 0.0,
	}


static func _floor_piece(
	room_id: int,
	archetype: String,
	label: String,
	size_m: Vector2,
	center_m: Vector2
) -> Dictionary:
	return _piece(room_id, archetype, label, size_m, center_m)


static func _mentions(text: String, words: Array) -> bool:
	for word in words:
		if text.contains(String(word)):
			return true
	return false

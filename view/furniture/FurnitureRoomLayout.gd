extends RefCounted

## Coloca el mobiliario de una sala con las reglas de una vivienda.
##
## Antes no habia colocacion: cada pieza se dibujaba donde decia su ficha del
## escenario -una posicion pensada para el modelo de fuego- y lo unico que se
## hacia era meterla a la fuerza dentro de la sala. De ahi salian camas metidas
## dentro de la comoda, la butaca dentro de la libreria y un aparador cruzado
## con la mesa: 11 pares de piezas ocupando el mismo sitio en el catalogo.
##
## Las reglas son tres, y son las de cualquier casa:
##
##  1. Un armario, una cama, un sofa o una encimera van DE ESPALDAS A UN
##     PARAMENTO. Cual, lo dice la ficha: se elige el mas cercano a donde el
##     escenario la puso, para no reinventar la distribucion.
##  2. Dos piezas no ocupan el mismo sitio. Las que van contra un muro se
##     deslizan A LO LARGO de su paramento hasta el primer hueco libre; las
##     exentas se apartan por donde menos tengan que moverse.
##  3. Por delante de una puerta se pasa. Cada hueco reserva una banda libre
##     hacia dentro de la sala, y ninguna pieza puede invadirla.
##
## Las piezas rasantes -alfombras y derrames- quedan fuera de todo esto: es
## correcto que la mesa de centro este encima de la alfombra.

const FurnitureDimensions := preload("res://view/furniture/FurnitureDimensions.gd")
const FurnitureAssetLoader := preload("res://view/3d/furniture/FurnitureAssetLoader.gd")
const WallSideGeometry := preload("res://view/geometry/WallSideGeometry.gd")
const OpeningPlacement := preload("res://view/geometry/OpeningPlacement.gd")

## Separacion minima de una pieza al paramento. No es estetica: los rodapies y
## los marcos ocupan, y una pieza pegada al milimetro se ve atravesando el muro
## en cuanto el jugador se acerca.
const WALL_MARGIN_M: float = 0.04

## Holgura entre dos piezas para darlas por separadas.
const PIECE_GAP_M: float = 0.03

## Banda libre por delante de cada hueco, hacia dentro de la sala. Una puerta
## de paso pide poder abrirse y que alguien la cruce.
const DOOR_CLEARANCE_M: float = 0.75

## Margen que se anade al ancho del hueco por cada jamba.
const DOOR_SIDE_MARGIN_M: float = 0.05

## Paso con el que una pieza busca sitio deslizandose por su paramento.
const SLIDE_STEP_M: float = 0.05

## Vueltas maximas del apartado de las piezas exentas.
const SEPARATION_PASSES: int = 48

## A cuanto de su largo se prueba a encoger una pieza que no encuentra sitio,
## si su arquetipo admite dimension libre.
const SHRINK_STEPS: Array[float] = [0.75, 0.55, 0.40]

const SIDES: Array[String] = ["top", "bottom", "left", "right"]


## Resuelve la sala entera.
##
## `specs` son las fichas ya normalizadas (con `size_m`, `position_m` y
## `rotation_deg`); devuelve las mismas con la pose resuelta y marcada como
## definitiva, en el mismo orden en que entraron.
static func layout_room(room_size_m: Vector2, doors: Array, specs: Array) -> Array:
	var room := Rect2(Vector2.ZERO, Vector2(maxf(0.2, room_size_m.x), maxf(0.2, room_size_m.y)))
	var plan: Array = []
	for spec in specs:
		if typeof(spec) != TYPE_DICTIONARY:
			continue
		plan.append(_plan_piece(Dictionary(spec), room))

	# Bloqueos fijos: por delante de cada puerta no se pone nada.
	var blockers: Array[Rect2] = []
	for door in doors:
		if typeof(door) == TYPE_DICTIONARY:
			var band: Rect2 = _door_band(room, Dictionary(door))
			if band.size.x > 0.0 and band.size.y > 0.0:
				blockers.append(band)

	# Las mas grandes eligen sitio primero: una cama no cabe en el hueco que
	# deje una mesilla, y al reves si.
	var order: Array[int] = []
	for i in range(plan.size()):
		order.append(i)
	order.sort_custom(func(a, b): return _priority(plan[a]) > _priority(plan[b]))

	var occupied: Array[Rect2] = blockers.duplicate()

	# Lo que el usuario haya colocado a mano manda, y manda ANTES que nada: se
	# queda donde esta y las demas piezas lo esquivan. Recolocarselo seria
	# deshacerle el trabajo cada vez que se dibuja la sala.
	for piece in plan:
		if not bool(piece.get("locked", false)):
			continue
		occupied.append(_rect_of(piece))

	for index in order:
		var piece: Dictionary = plan[index]
		if bool(piece.get("locked", false)):
			continue
		if bool(piece.get("floor", false)):
			piece["center"] = _clamp_center(room, Vector2(piece["center"]), Vector2(piece["world_size"]))
			continue
		if bool(piece.get("wall", false)):
			_place_against_wall(room, piece, occupied)
		else:
			_place_free(room, piece, occupied)
		occupied.append(_rect_of(piece))

	var result: Array = []
	for i in range(plan.size()):
		result.append(_resolved_spec(plan[i]))
	return result


## Bandas libres por delante de los huecos de una sala, en coordenadas locales.
##
## La aritmetica de donde cae un hueco sobre su paramento no se repite aqui:
## sale de los mismos modulos que usan las dos vistas para dibujarlos.
static func doors_for_room(building, room_id: int, rect: Rect2) -> Array:
	var doors: Array = []
	if building == null:
		return doors
	var rects: Dictionary = building.get_room_rects_m()
	for op in building.get_openings():
		if op == null:
			continue
		# Un hueco vertical -el ojo de una escalera- no esta en ningun
		# paramento: no reserva banda de paso.
		if bool(op.is_vertical):
			continue
		# Una ventana con antepecho no estorba al mobiliario: se pasa por
		# debajo, y un aparador bajo la ventana es lo normal en una casa.
		if float(op.sill_m) > 0.45:
			continue
		var side: String = ""
		var segment_start: float = -1.0
		var segment_end: float = -1.0
		if int(op.a) == room_id and int(op.b) < 0:
			side = WallSideGeometry.canonical(String(op.wall_side))
			if side == "":
				side = "top"
		elif int(op.a) == room_id or int(op.b) == room_id:
			var other_id: int = int(op.b) if int(op.a) == room_id else int(op.a)
			if not rects.has(other_id):
				continue
			var shared: Dictionary = WallSideGeometry.shared_side(rect, Rect2(rects[other_id]))
			side = String(shared.get("side", ""))
			if side == "":
				continue
			segment_start = float(shared.get("overlap_start", 0.0))
			segment_end = float(shared.get("overlap_end", 0.0))
		else:
			continue

		var span: Dictionary = WallSideGeometry.side_span(rect, side)
		var side_start: float = float(span["start"])
		var side_end: float = float(span["end"])
		var allowed_start: float = side_start
		var allowed_end: float = side_end
		if segment_end > segment_start:
			allowed_start = maxf(side_start, segment_start)
			allowed_end = minf(side_end, segment_end)
		if allowed_end - allowed_start <= 0.05:
			continue
		var placement: Dictionary = OpeningPlacement.center_along_side(
			allowed_start, allowed_end, side_start, float(op.offset_m), bool(op.offset_is_fraction), float(op.width_m)
		)
		doors.append({
			"side": side,
			"center": float(placement["center"]) - _side_origin(rect, side),
			"width_m": float(placement["width_m"]),
		})
	return doors


static func _side_origin(rect: Rect2, side: String) -> float:
	if WallSideGeometry.is_horizontal(side):
		return rect.position.x
	return rect.position.y


static func _plan_piece(spec: Dictionary, room: Rect2) -> Dictionary:
	var archetype: String = String(spec.get("visual_archetype", spec.get("kind", "")))
	var slot: Vector2 = _to_vector2(spec.get("size_m", Vector2(0.5, 0.5)))
	slot.x = maxf(0.05, slot.x)
	slot.y = maxf(0.05, slot.y)
	# Se pide la caja en su orientacion canonica -el largo sobre la x- porque
	# la orientacion la decide la colocacion, no la ficha.
	var canonical_slot := Vector2(maxf(slot.x, slot.y), minf(slot.x, slot.y))
	var target: Vector3 = FurnitureDimensions.target_size_m(archetype, canonical_slot)
	# Dos tamanos, y hacen falta los dos. `size` es el que se PIDE, y es el que
	# viaja en la ficha porque quien construye la malla vuelve a resolver a
	# partir de el. `real` es lo que la malla va a medir de verdad: el ajuste
	# del modelo puede quedarse corto o pasarse dentro del limite de
	# deformacion, y colocar con la cifra equivocada saca la pieza de la sala.
	var size := Vector2(target.x, target.z)
	var achieved: Vector3 = FurnitureAssetLoader.resolved_size_m(archetype, target)
	var real: Vector2 = size if achieved == Vector3.ZERO else Vector2(achieved.x, achieved.z)
	var requested_center: Vector2 = _to_vector2(spec.get("position_m", Vector2.ZERO)) + slot * 0.5
	# Una ficha sin posicion no dice nada: se parte del centro de la sala.
	if requested_center.length_squared() <= 0.000001:
		requested_center = room.size * 0.5
	var rotation_deg: float = 0.0 if slot.x >= slot.y else 90.0
	var locked: bool = bool(spec.get("visual_pose_locked", false))
	if locked:
		# Pose curada: se respeta tal cual, tamano incluido. Lo unico que se
		# calcula es cuanto ocupa de verdad, para que las demas la esquiven.
		size = slot
		rotation_deg = float(spec.get("rotation_deg", 0.0))
		var locked_target: Vector3 = FurnitureDimensions.target_size_m(archetype, canonical_slot)
		var locked_real: Vector3 = FurnitureAssetLoader.resolved_size_m(archetype, locked_target)
		real = slot if locked_real == Vector3.ZERO else Vector2(locked_real.x, locked_real.z)
		if slot.x < slot.y:
			real = Vector2(real.y, real.x)
	return {
		"spec": spec,
		"archetype": archetype,
		"size": size,
		"real": real,
		"world_size": _world_size(real, rotation_deg),
		"rotation": rotation_deg,
		"center": requested_center,
		"base_size": Vector2(maxf(slot.x, slot.y), minf(slot.x, slot.y)),
		"visual_only": bool(spec.get("visual_only", false)),
		"locked": locked,
		"wall": FurnitureDimensions.is_wall_hugging(archetype),
		"floor": FurnitureDimensions.is_floor_level(archetype),
	}


## Que pieza elige sitio antes. Las de muro mandan sobre las exentas, y dentro
## de cada grupo la mas grande primero.
static func _priority(piece: Dictionary) -> float:
	var size: Vector2 = Vector2(piece["real"])
	var area: float = size.x * size.y
	if bool(piece.get("wall", false)):
		return 1000.0 + area
	return area


static func _place_against_wall(room: Rect2, piece: Dictionary, occupied: Array) -> void:
	var center: Vector2 = Vector2(piece["center"])
	var sides: Array[String] = SIDES.duplicate()
	sides.sort_custom(func(a, b): return _distance_to_side(room, center, a) < _distance_to_side(room, center, b))
	for side in sides:
		if _try_side(room, piece, side, occupied):
			return

	# Lo que tiene una dimension libre se encoge antes de rendirse: un frente de
	# cocina de cuatro metros no cabe en una cocina pequena, pero uno de dos si,
	# y es preferible a plantarlo delante de la puerta.
	for factor in SHRINK_STEPS:
		if not _shrink(piece, factor):
			break
		for side in sides:
			if _try_side(room, piece, side, occupied):
				return

	if bool(piece.get("visual_only", false)):
		# El atrezo que no cabe no se pone. Es decoracion: mejor una sala con
		# una pieza menos que una pieza metida dentro de otra.
		piece["hidden"] = true
		return
	# Una pieza del escenario nunca se descarta: es carga de fuego y tiene que
	# estar. Se queda contra el paramento mas cercano, apartada lo que se pueda.
	_apply_side(room, piece, sides[0], _along_of(Vector2(piece["center"]), sides[0]))
	_place_free(room, piece, occupied)


static func _try_side(room: Rect2, piece: Dictionary, side: String, occupied: Array) -> bool:
	var size: Vector2 = Vector2(piece["real"])
	var horizontal: bool = WallSideGeometry.is_horizontal(side)
	# Contra un paramento, el fondo de la pieza queda perpendicular a el.
	var along_len: float = size.x
	var wall_len: float = room.size.x if horizontal else room.size.y
	var half: float = along_len * 0.5
	var min_along: float = WALL_MARGIN_M + half
	var max_along: float = wall_len - WALL_MARGIN_M - half
	if min_along > max_along:
		return false
	var wanted: float = clampf(_along_of(Vector2(piece["center"]), side), min_along, max_along)

	var steps: int = int(ceil((max_along - min_along) / SLIDE_STEP_M)) + 1
	for step in range(steps):
		for direction in [1.0, -1.0]:
			var candidate: float = wanted + direction * float(step) * SLIDE_STEP_M
			if candidate < min_along or candidate > max_along:
				continue
			_apply_side(room, piece, side, candidate)
			if not _collides(_rect_of(piece), occupied):
				return true
			if step == 0:
				break
	return false


static func _apply_side(room: Rect2, piece: Dictionary, side: String, along_m: float) -> void:
	var size: Vector2 = Vector2(piece["real"])
	var horizontal: bool = WallSideGeometry.is_horizontal(side)
	var rotation_deg: float = 0.0
	match side:
		"top":
			rotation_deg = 0.0
		"bottom":
			rotation_deg = 180.0
		"left":
			rotation_deg = 90.0
		_:
			rotation_deg = -90.0
	var world: Vector2 = _world_size(size, rotation_deg)
	var away: float = 0.0
	if horizontal:
		away = WALL_MARGIN_M + world.y * 0.5
		if side == "bottom":
			away = room.size.y - away
		piece["center"] = Vector2(along_m, away)
	else:
		away = WALL_MARGIN_M + world.x * 0.5
		if side == "right":
			away = room.size.x - away
		piece["center"] = Vector2(away, along_m)
	piece["rotation"] = rotation_deg
	piece["world_size"] = world


static func _place_free(room: Rect2, piece: Dictionary, occupied: Array) -> void:
	var world: Vector2 = Vector2(piece["world_size"])
	var center: Vector2 = _clamp_center(room, Vector2(piece["center"]), world)
	for _pass in range(SEPARATION_PASSES):
		var rect := Rect2(center - world * 0.5, world)
		var pushed: bool = false
		for other in occupied:
			var other_rect := Rect2(other)
			var inter: Rect2 = rect.intersection(other_rect)
			if inter.size.x <= 0.0 or inter.size.y <= 0.0:
				continue
			# Se aparta por donde menos tenga que moverse.
			var other_center: Vector2 = other_rect.position + other_rect.size * 0.5
			if inter.size.x < inter.size.y:
				var dx: float = inter.size.x + PIECE_GAP_M
				center.x += dx if center.x >= other_center.x else -dx
			else:
				var dy: float = inter.size.y + PIECE_GAP_M
				center.y += dy if center.y >= other_center.y else -dy
			center = _clamp_center(room, center, world)
			pushed = true
		if not pushed:
			break
	piece["center"] = center
	if not _collides(_rect_of(piece), occupied):
		return
	# Apartarse a empujones puede no converger: entre la cama y la banda de
	# paso de la puerta, una mesilla rebota de una a otra. Cuando pasa, se
	# barre la sala y se coge el sitio libre mas cercano al que pedia la ficha.
	var wanted: Vector2 = Vector2(piece["center"])
	var best: Vector2 = wanted
	var best_distance: float = INF
	var steps_x: int = maxi(1, int(room.size.x / SLIDE_STEP_M))
	var steps_y: int = maxi(1, int(room.size.y / SLIDE_STEP_M))
	for ix in range(steps_x + 1):
		for iy in range(steps_y + 1):
			var candidate: Vector2 = _clamp_center(
				room, Vector2(float(ix) * SLIDE_STEP_M, float(iy) * SLIDE_STEP_M), world
			)
			var distance: float = candidate.distance_squared_to(wanted)
			if distance >= best_distance:
				continue
			if _collides(Rect2(candidate - world * 0.5, world), occupied):
				continue
			best = candidate
			best_distance = distance
	if best_distance == INF and bool(piece.get("visual_only", false)):
		piece["hidden"] = true
		return
	piece["center"] = best


static func _clamp_center(room: Rect2, center: Vector2, world: Vector2) -> Vector2:
	var half: Vector2 = world * 0.5
	var min_x: float = WALL_MARGIN_M + half.x
	var max_x: float = room.size.x - WALL_MARGIN_M - half.x
	var min_y: float = WALL_MARGIN_M + half.y
	var max_y: float = room.size.y - WALL_MARGIN_M - half.y
	return Vector2(
		clampf(center.x, min_x, max_x) if min_x <= max_x else room.size.x * 0.5,
		clampf(center.y, min_y, max_y) if min_y <= max_y else room.size.y * 0.5
	)


static func _door_band(room: Rect2, door: Dictionary) -> Rect2:
	var side: String = String(door.get("side", "top"))
	var center: float = float(door.get("center", 0.0))
	var width: float = maxf(0.2, float(door.get("width_m", 0.8))) + DOOR_SIDE_MARGIN_M * 2.0
	var depth: float = minf(DOOR_CLEARANCE_M, (room.size.y if WallSideGeometry.is_horizontal(side) else room.size.x) * 0.5)
	match side:
		"top":
			return Rect2(center - width * 0.5, 0.0, width, depth)
		"bottom":
			return Rect2(center - width * 0.5, room.size.y - depth, width, depth)
		"left":
			return Rect2(0.0, center - width * 0.5, depth, width)
		_:
			return Rect2(room.size.x - depth, center - width * 0.5, depth, width)


static func _distance_to_side(room: Rect2, center: Vector2, side: String) -> float:
	match side:
		"top":
			return center.y
		"bottom":
			return room.size.y - center.y
		"left":
			return center.x
		_:
			return room.size.x - center.x


static func _along_of(center: Vector2, side: String) -> float:
	return center.x if WallSideGeometry.is_horizontal(side) else center.y


static func _world_size(size: Vector2, rotation_deg: float) -> Vector2:
	var rot: float = deg_to_rad(rotation_deg)
	var c: float = absf(cos(rot))
	var s: float = absf(sin(rot))
	return Vector2(c * size.x + s * size.y, s * size.x + c * size.y)


static func _rect_of(piece: Dictionary) -> Rect2:
	var world: Vector2 = Vector2(piece["world_size"])
	return Rect2(Vector2(piece["center"]) - world * 0.5, world)


static func _collides(rect: Rect2, occupied: Array) -> bool:
	var grown := Rect2(rect.position - Vector2.ONE * PIECE_GAP_M, rect.size + Vector2.ONE * PIECE_GAP_M * 2.0)
	for other in occupied:
		var inter: Rect2 = grown.intersection(Rect2(other))
		if inter.size.x > 0.0 and inter.size.y > 0.0:
			return true
	return false


## Encoge la dimension libre de una pieza. Devuelve false si su arquetipo no
## tiene ninguna -una cama mide lo que mide- o si ya esta en su minimo.
static func _shrink(piece: Dictionary, factor: float) -> bool:
	var archetype: String = String(piece["archetype"])
	var spec_data: Dictionary = FurnitureDimensions.spec_for(archetype)
	var long_min: float = float(spec_data.get("long_min_m", 0.0))
	var long_max: float = float(spec_data.get("long_max_m", 0.0))
	if long_min <= 0.0 or long_max < long_min:
		return false
	var base: Vector2 = Vector2(piece["base_size"])
	var wanted: float = maxf(base.x, base.y) * factor
	if wanted <= long_min:
		wanted = long_min
	var canonical := Vector2(wanted, minf(base.x, base.y))
	var target: Vector3 = FurnitureDimensions.target_size_m(archetype, canonical)
	if absf(target.x - float(piece["size"].x)) < 0.01:
		return false
	var achieved: Vector3 = FurnitureAssetLoader.resolved_size_m(archetype, target)
	piece["size"] = Vector2(target.x, target.z)
	piece["real"] = Vector2(target.x, target.z) if achieved == Vector3.ZERO else Vector2(achieved.x, achieved.z)
	return true


static func _resolved_spec(piece: Dictionary) -> Dictionary:
	var spec: Dictionary = Dictionary(piece["spec"]).duplicate(true)
	if bool(piece.get("hidden", false)):
		spec["visual_hidden"] = true
		return spec
	if bool(piece.get("locked", false)):
		return spec
	var size: Vector2 = Vector2(piece["size"])
	spec["size_m"] = size
	spec["rotation_deg"] = float(piece["rotation"])
	spec["position_m"] = Vector2(piece["center"]) - size * 0.5
	spec["visual_pose_locked"] = true
	return spec


static func _to_vector2(value: Variant) -> Vector2:
	if typeof(value) == TYPE_VECTOR2:
		return value
	if typeof(value) == TYPE_DICTIONARY:
		var data: Dictionary = value
		return Vector2(float(data.get("x", 0.0)), float(data.get("y", 0.0)))
	if typeof(value) == TYPE_ARRAY:
		var values: Array = value
		if values.size() >= 2:
			return Vector2(float(values[0]), float(values[1]))
	return Vector2.ZERO

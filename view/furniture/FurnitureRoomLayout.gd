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
## Con solo esas tres, una sala cumple y aun asi no parece una sala: la tele
## mira a la pared y la mesilla esta en la otra punta. Lo que falta son las
## relaciones, y estan en `FurnitureRoomGrammar`: cual va con cual y hacia donde
## mira cada una. Se aplican en una PASADA POSTERIOR, sobre las piezas ya
## colocadas, para que una relacion que no cabe no estropee una colocacion que
## si valia: si la mesilla no cabe junto a la cama, se queda donde estaba.
##
## Las piezas rasantes -alfombras y derrames- quedan fuera de todo esto: es
## correcto que la mesa de centro este encima de la alfombra.

const FurnitureDimensions := preload("res://view/furniture/FurnitureDimensions.gd")
const FurnitureRoomGrammar := preload("res://view/furniture/FurnitureRoomGrammar.gd")
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

## Hueco que hay que dejar al pie de una cama puesta de cabecero. No es solo
## para salir de ella: es el paso de la habitacion, y con menos que esto la cama
## se come la sala entera y no queda sitio ni para la comoda. Si no cabe, la
## cama se pone en paralelo al muro, que es lo que se hace de verdad en una
## habitacion estrecha.
const BED_EXIT_M: float = 0.90

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
	# Se intenta la buena y, si no sale, la de siempre.
	#
	# Poner una cama de cabecero es lo correcto y casi siempre cabe, pero en una
	# habitacion muy cargada se come el sitio de lo demas y acaba habiendo dos
	# piezas en el mismo metro cuadrado. Cuando eso pasa, la sala entera se
	# rehace con las camas en paralelo al muro. Es preferible una habitacion
	# como las de antes a una habitacion nueva con un mueble dentro de otro.
	var intento: Array = _layout_pass(room_size_m, doors, specs, true)
	if _has_overlap(intento):
		return _layout_pass(room_size_m, doors, specs, false)
	return intento


static func _has_overlap(placed: Array) -> bool:
	var cajas: Array[Rect2] = []
	for raw in placed:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var spec: Dictionary = raw
		if bool(spec.get("visual_hidden", false)):
			continue
		if FurnitureDimensions.is_floor_level(String(spec.get("visual_archetype", ""))):
			continue
		var size: Vector2 = _to_vector2(spec.get("size_m", Vector2.ZERO))
		var world: Vector2 = _world_size(size, float(spec.get("rotation_deg", 0.0)))
		var center: Vector2 = _to_vector2(spec.get("position_m", Vector2.ZERO)) + size * 0.5
		var caja := Rect2(center - world * 0.5, world)
		for otra in cajas:
			var inter: Rect2 = caja.intersection(otra)
			if inter.size.x > 0.02 and inter.size.y > 0.02:
				return true
		cajas.append(caja)
	return false


static func _layout_pass(room_size_m: Vector2, doors: Array, specs: Array, cabecero: bool) -> Array:
	var room := Rect2(Vector2.ZERO, Vector2(maxf(0.2, room_size_m.x), maxf(0.2, room_size_m.y)))
	var plan: Array = []
	for spec in specs:
		if typeof(spec) != TYPE_DICTIONARY:
			continue
		plan.append(_plan_piece(Dictionary(spec), room, cabecero))

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

	# Estado compartido de la colocacion: las puertas -para saber que pano esta
	# libre- y el paramento que ya eligio cada fila (la de la cocina).
	var contexto: Dictionary = {"doors": doors, "runs": {}, "blockers": [], "cabecero": cabecero}

	contexto["blockers"] = blockers
	var occupied: Array[Rect2] = blockers.duplicate()

	# Lo que el usuario haya colocado a mano manda, y manda ANTES que nada: se
	# queda donde esta y las demas piezas lo esquivan. Recolocarselo seria
	# deshacerle el trabajo cada vez que se dibuja la sala.
	for piece in plan:
		if not bool(piece.get("locked", false)):
			continue
		occupied.append(_rect_of(piece))

	# Se coloca por GRUPOS, no pieza a pieza.
	#
	# Antes cada mueble buscaba sitio por su cuenta y por orden de tamano, asi
	# que cuando le tocaba a la mesilla el armario y el escritorio ya se habian
	# repartido los costados de la cama: de 23 mesillas del catalogo, 22
	# acababan lejos de su cama. Ahora, en cuanto una pieza se coloca, se
	# colocan INMEDIATAMENTE las que van con ella -su mesilla, el resto de la
	# fila de cocina-, antes de que otra les quite el sitio.
	var colocadas: Dictionary = {}
	for index in order:
		if colocadas.has(index):
			continue
		_place_one(room, plan, index, occupied, contexto, cabecero, colocadas)
		for seguidor in _followers_of(plan, index, colocadas):
			_place_one(room, plan, seguidor, occupied, contexto, cabecero, colocadas)

	_apply_grammar(room, plan, blockers)

	var result: Array = []
	for i in range(plan.size()):
		result.append(_resolved_spec(plan[i]))
	return result


## Coloca una pieza y la da por hecha.
static func _place_one(
	room: Rect2, plan: Array, index: int, occupied: Array,
	contexto: Dictionary, cabecero: bool, colocadas: Dictionary
) -> void:
	colocadas[index] = true
	var piece: Dictionary = plan[index]
	if bool(piece.get("locked", false)):
		return
	if bool(piece.get("floor", false)):
		piece["center"] = _clamp_center(room, Vector2(piece["center"]), Vector2(piece["world_size"]))
		return
	piece["cabecero"] = cabecero

	# Si va con alguien que ya esta puesto, se coloca respecto a el. Es lo que
	# pone la mesilla al costado de la cama en vez de en la otra punta.
	var rel: Dictionary = FurnitureRoomGrammar.relation_for(String(piece.get("archetype", "")))
	if not rel.is_empty():
		var ancla: int = _placed_anchor(plan, Array(rel.get("anchor", [])), index, colocadas)
		if ancla >= 0 and _place_related(
				room, piece, plan[ancla], rel, occupied, _rank_among_siblings(plan, index)):
			# Ya esta emparejada: la pasada final no vuelve a tocarla. Aplicar la
			# relacion dos veces la empeoraba -la segunda vez el sitio bueno ya
			# estaba ocupado por otra pieza y acababa girandola por girarla-.
			piece["emparejada"] = true
			occupied.append(_rect_of(piece))
			return

	if bool(piece.get("wall", false)):
		_place_against_wall(room, piece, occupied, contexto)
	else:
		_place_free(room, piece, occupied, contexto.get("blockers", []))
	occupied.append(_rect_of(piece))


## Quien va detras de esta pieza: las que se agarran a ella y las que comparten
## su fila. Las de fila salen en el orden del triangulo de trabajo -nevera,
## mueble, fregadero, fuegos- para que no queden barajadas.
static func _followers_of(plan: Array, index: int, colocadas: Dictionary) -> Array[int]:
	var archetype: String = String(Dictionary(plan[index]).get("archetype", ""))
	var grupo: String = FurnitureRoomGrammar.run_group_for(archetype)
	var out: Array[int] = []
	for i in range(plan.size()):
		if colocadas.has(i) or i == index:
			continue
		var otro: Dictionary = plan[i]
		var arq: String = String(otro.get("archetype", ""))
		if grupo != "" and FurnitureRoomGrammar.run_group_for(arq) == grupo:
			out.append(i)
			continue
		var rel: Dictionary = FurnitureRoomGrammar.relation_for(arq)
		if not rel.is_empty() and Array(rel.get("anchor", [])).has(archetype):
			out.append(i)
	if grupo != "":
		out.sort_custom(func(a, b):
			return FurnitureRoomGrammar.run_order_for(String(Dictionary(plan[a]).get("archetype", ""))) \
				< FurnitureRoomGrammar.run_order_for(String(Dictionary(plan[b]).get("archetype", ""))))
	return out


## La pareja de una pieza, si ya esta colocada.
static func _placed_anchor(plan: Array, anchors: Array, self_index: int, colocadas: Dictionary) -> int:
	for wanted in anchors:
		for i in range(plan.size()):
			if i == self_index or not colocadas.has(i):
				continue
			var other: Dictionary = plan[i]
			if bool(other.get("hidden", false)):
				continue
			if String(other.get("archetype", "")) == String(wanted):
				return i
	return -1


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


static func _plan_piece(spec: Dictionary, room: Rect2, cabecero: bool = true) -> Dictionary:
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
	var long_along: bool = cabecero and FurnitureRoomGrammar.long_axis_is_along(archetype)
	var footprint: Vector2 = _world_size(
		Vector2(real.y, real.x) if long_along else real, rotation_deg)
	return {
		"spec": spec,
		"archetype": archetype,
		"size": size,
		"real": real,
		"world_size": footprint,
		"rotation": rotation_deg,
		"center": requested_center,
		"base_size": Vector2(maxf(slot.x, slot.y), minf(slot.x, slot.y)),
		"visual_only": bool(spec.get("visual_only", false)),
		"locked": locked,
		"wall": FurnitureDimensions.is_wall_hugging(archetype),
		"floor": FurnitureDimensions.is_floor_level(archetype),
		"long_along": long_along,
		"cabecero": cabecero,
	}


## Que pieza elige sitio antes. Las de muro mandan sobre las exentas, y dentro
## de cada grupo la mas grande primero.
##
## Con una excepcion: **una fila va antes que nada, y en su orden**. Si primero
## se coloca el mueble grande de la cocina, se planta en mitad del paramento y
## la nevera ya no cabe a su lado; con la fila primero, cada pieza se pone a
## continuacion de la anterior y salen las cuatro seguidas.
static func _priority(piece: Dictionary) -> float:
	var archetype: String = String(piece.get("archetype", ""))
	if FurnitureRoomGrammar.run_group_for(archetype) != "":
		return 2000.0 - float(FurnitureRoomGrammar.run_order_for(archetype))
	var size: Vector2 = Vector2(piece["real"])
	var area: float = size.x * size.y
	if bool(piece.get("wall", false)):
		return 1000.0 + area
	return area


static func _place_against_wall(room: Rect2, piece: Dictionary, occupied: Array, contexto: Dictionary = {}) -> void:
	if _place_in_run(room, piece, occupied, contexto):
		return
	var center: Vector2 = Vector2(piece["center"])
	var sides: Array[String] = _sides_for(room, piece, center, contexto)
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
	_place_free(room, piece, occupied, contexto.get("blockers", []))


## En que orden se prueban los paramentos.
##
## Por defecto, el mas cercano a donde el escenario puso la pieza -esas
## posiciones vienen del modelo de fuego, asi que como criterio general vale-.
## Pero una cama no va "en el muro mas cercano": va contra el pano largo que no
## tenga puertas, y una fila de cocina va entera en el mismo pano.
static func _sides_for(room: Rect2, piece: Dictionary, center: Vector2, contexto: Dictionary) -> Array[String]:
	var sides: Array[String] = SIDES.duplicate()
	var archetype: String = String(piece.get("archetype", ""))
	var rule: String = FurnitureRoomGrammar.wall_rule_for(archetype)
	var doors: Array = contexto.get("doors", [])

	if rule == "":
		sides.sort_custom(func(a, b): return _distance_to_side(room, center, a) < _distance_to_side(room, center, b))
		return sides

	# Una fila -la cocina- ya se ha intentado colocar seguida en `_place_in_run`;
	# si se llega aqui es que no cabia, y entonces vale la regla general.
	# "longest_free": el pano mas largo sin huecos.
	return _by_free_length(room, doors)


## Coloca una pieza de fila a continuacion de la anterior.
##
## Una cocina no es "cuatro muebles contra un muro cualquiera": es una fila
## seguida, y en el orden del triangulo de trabajo -nevera, mueble, fregadero,
## fuegos-. Se lleva un cursor por el paramento y cada pieza se pone donde
## termino la de antes. La primera elige el pano mas largo sin huecos.
static func _place_in_run(room: Rect2, piece: Dictionary, occupied: Array, contexto: Dictionary) -> bool:
	var grupo: String = FurnitureRoomGrammar.run_group_for(String(piece.get("archetype", "")))
	if grupo == "":
		return false
	var runs: Dictionary = contexto.get("runs", {})
	var estado: Dictionary = runs.get(grupo, {})
	var side: String = String(estado.get("side", ""))
	if side == "":
		for candidato in _by_free_length(room, contexto.get("doors", [])):
			if _run_fits(room, piece, candidato, WALL_MARGIN_M, occupied):
				side = candidato
				break
		if side == "":
			return false
		estado = {"side": side, "cursor": WALL_MARGIN_M}

	var horizontal: bool = WallSideGeometry.is_horizontal(side)
	var largo: float = room.size.x if horizontal else room.size.y
	var apoyada: Vector2 = _footprint(piece, _rotation_for_side(side))
	var media: float = (apoyada.x if horizontal else apoyada.y) * 0.5
	var cursor: float = float(estado.get("cursor", WALL_MARGIN_M))
	var along: float = cursor + media
	if along + media > largo - WALL_MARGIN_M:
		# La fila se ha quedado sin paramento: esta pieza se busca la vida por
		# su cuenta, pero la fila sigue apuntada para las que vengan detras.
		contexto["runs"] = _with_run(runs, grupo, estado)
		return false
	_apply_side(room, piece, side, along)
	if _collides(_rect_of(piece), occupied):
		if not _try_side(room, piece, side, occupied):
			contexto["runs"] = _with_run(runs, grupo, estado)
			return false
		along = _along_of(Vector2(piece["center"]), side)
	estado["cursor"] = along + media + PIECE_GAP_M
	contexto["runs"] = _with_run(runs, grupo, estado)
	return true


## Si la primera pieza de la fila cabe en ese paramento.
static func _run_fits(room: Rect2, piece: Dictionary, side: String, desde: float, occupied: Array) -> bool:
	var horizontal: bool = WallSideGeometry.is_horizontal(side)
	var largo: float = room.size.x if horizontal else room.size.y
	var apoyada: Vector2 = _footprint(piece, _rotation_for_side(side))
	var ancho: float = apoyada.x if horizontal else apoyada.y
	if desde + ancho > largo - WALL_MARGIN_M:
		return false
	_apply_side(room, piece, side, desde + ancho * 0.5)
	return not _collides(_rect_of(piece), occupied)


static func _with_run(runs: Dictionary, grupo: String, estado: Dictionary) -> Dictionary:
	runs[grupo] = estado
	return runs


## Paramentos ordenados por metros libres de hueco, de mas a menos.
static func _by_free_length(room: Rect2, doors: Array) -> Array[String]:
	var sides: Array[String] = SIDES.duplicate()
	sides.sort_custom(func(a, b):
		return FurnitureRoomGrammar.free_wall_length_m(room, a, doors) \
			> FurnitureRoomGrammar.free_wall_length_m(room, b, doors))
	return sides


## Centro que tendria una pieza pegada a `side` a la distancia `along`.
static func _center_on_side(room: Rect2, side: String, along: float, world: Vector2) -> Vector2:
	if WallSideGeometry.is_horizontal(side):
		var y: float = WALL_MARGIN_M + world.y * 0.5
		if side == "bottom":
			y = room.size.y - y
		return Vector2(along, y)
	var x: float = WALL_MARGIN_M + world.x * 0.5
	if side == "right":
		x = room.size.x - x
	return Vector2(x, along)


# ============================================================
# GRAMATICA: que va con que, y mirando a donde
# ============================================================

## Segunda pasada: coloca cada pieza respecto a la suya.
##
## Va DESPUES de la colocacion general y nunca la empeora. Si la relacion no
## cabe, la pieza se queda donde estaba; y aunque no quepa moverla, al menos se
## la orienta hacia su pareja, que es la mitad del problema.
static func _apply_grammar(room: Rect2, plan: Array, blockers: Array) -> void:
	for i in range(plan.size()):
		var piece: Dictionary = plan[i]
		if bool(piece.get("locked", false)) or bool(piece.get("hidden", false)) or bool(piece.get("floor", false)):
			continue
		if bool(piece.get("emparejada", false)):
			continue
		var rel: Dictionary = FurnitureRoomGrammar.relation_for(String(piece.get("archetype", "")))
		if rel.is_empty():
			continue
		var anchor_index: int = _find_anchor(plan, Array(rel.get("anchor", [])), i)
		if anchor_index < 0:
			continue
		_place_related(room, piece, plan[anchor_index], rel,
			_occupancy_excluding(plan, blockers, i), _rank_among_siblings(plan, i))


## La pieza a la que se agarra: la primera de la lista de preferencia que este
## en la sala y colocada.
static func _find_anchor(plan: Array, anchors: Array, self_index: int) -> int:
	for wanted in anchors:
		for i in range(plan.size()):
			if i == self_index:
				continue
			var other: Dictionary = plan[i]
			if bool(other.get("hidden", false)):
				continue
			if String(other.get("archetype", "")) == String(wanted):
				return i
	return -1


## Cuantas piezas iguales hay antes que esta. Sirve para que la segunda mesilla
## se vaya al otro lado de la cama en vez de pelearse por el mismo sitio.
static func _rank_among_siblings(plan: Array, index: int) -> int:
	var archetype: String = String(Dictionary(plan[index]).get("archetype", ""))
	var rank: int = 0
	for i in range(index):
		if String(Dictionary(plan[i]).get("archetype", "")) == archetype:
			rank += 1
	return rank


static func _occupancy_excluding(plan: Array, blockers: Array, index: int) -> Array:
	var out: Array = []
	for rect in blockers:
		out.append(rect)
	for i in range(plan.size()):
		if i == index:
			continue
		var piece: Dictionary = plan[i]
		if bool(piece.get("hidden", false)) or bool(piece.get("floor", false)):
			continue
		out.append(_rect_of(piece))
	return out


## Coloca una pieza respecto a su pareja y la orienta.
## Devuelve `true` si la ha podido poner en su sitio de verdad. Si devuelve
## `false` la ha dejado orientada pero donde estaba, y quien llama tiene que
## colocarla por las bravas.
static func _place_related(
	room: Rect2, piece: Dictionary, anchor: Dictionary, rel: Dictionary,
	occupied: Array, rank: int
) -> bool:
	var relation: String = String(rel.get("relation", "beside"))
	var gap: float = float(rel.get("gap_m", 0.1))
	var anchor_center: Vector2 = Vector2(anchor["center"])
	var anchor_rot: float = float(anchor.get("rotation", 0.0))
	var frente: Vector2 = FurnitureRoomGrammar.direction_of(anchor_rot)
	var lado := Vector2(frente.y, -frente.x)

	# Una pieza de paramento no se despega del muro: lo que se elige es CUAL.
	# Es el caso de la tele, que va en el pano al que mira el sofa.
	if bool(piece.get("wall", false)) and relation == "facing":
		var side: String = _side_towards(room, anchor_center, frente)
		# `_try_side` va probando poses y, si no encuentra sitio, devuelve false
		# DEJANDO la ultima que probo. Hay que guardarse la pose entera -centro,
		# giro y caja- y devolverla, no solo el centro.
		var pose: Dictionary = _pose_of(piece)
		piece["center"] = anchor_center
		if _try_side(room, piece, side, occupied):
			return true
		_restore_pose(piece, pose)
		_reorient_in_place(room, piece, Vector2(pose["center"]), float(pose["rotation"]),
			FurnitureRoomGrammar.snap_quarter(anchor_rot + 180.0), occupied)
		return false

	var candidatos: Array[Dictionary] = []
	var media_anchor_f: float = _extent_along(Vector2(anchor["world_size"]), frente) * 0.5
	var media_anchor_l: float = _extent_along(Vector2(anchor["world_size"]), lado) * 0.5

	match relation:
		"front":
			# Mira lo mismo que su pareja: una mesa de centro no "mira" al sofa,
			# esta delante y en paralelo.
			candidatos.append({"rot": anchor_rot, "dir": frente, "media": media_anchor_f})
		"facing":
			candidatos.append({"rot": anchor_rot + 180.0, "dir": frente, "media": media_anchor_f})
		"around":
			for giro in [0, 1, 3, 2]:
				var d: Vector2 = [frente, lado, -frente, -lado][giro]
				candidatos.append({
					"rot": FurnitureRoomGrammar.facing_deg(d, Vector2.ZERO),
					"dir": d,
					"media": _extent_along(Vector2(anchor["world_size"]), d) * 0.5,
				})
		_:
			# beside: primero por un costado y luego por el otro, y la segunda
			# pieza igual empieza por el contrario.
			var primero: Vector2 = lado if rank % 2 == 0 else -lado
			candidatos.append({"rot": anchor_rot, "dir": primero, "media": media_anchor_l})
			candidatos.append({"rot": anchor_rot, "dir": -primero, "media": media_anchor_l})

	var antes_center: Vector2 = Vector2(piece["center"])
	var antes_rot: float = float(piece.get("rotation", 0.0))
	for candidato in candidatos:
		var rot: float = FurnitureRoomGrammar.snap_quarter(float(candidato["rot"]))
		var world: Vector2 = _footprint(piece, rot)
		var direccion: Vector2 = Vector2(candidato["dir"])
		var distancia: float = float(candidato["media"]) + gap + _extent_along(world, direccion) * 0.5
		var center: Vector2 = _clamp_center(room, anchor_center + direccion * distancia, world)
		if _collides(Rect2(center - world * 0.5, world), occupied):
			continue
		piece["center"] = center
		piece["rotation"] = rot
		piece["world_size"] = world
		return true

	# No cabe donde deberia: se queda donde estaba, pero al menos mirando a su
	# pareja. Una tele mal colocada que mira al sofa se lee mucho mejor que una
	# bien colocada que mira a la pared.
	var deseada: float = FurnitureRoomGrammar.snap_quarter(anchor_rot)
	if relation == "facing" or relation == "around":
		deseada = FurnitureRoomGrammar.snap_quarter(
			FurnitureRoomGrammar.facing_deg(antes_center, anchor_center))
	_reorient_in_place(room, piece, antes_center, antes_rot, deseada, occupied)
	return false


static func _pose_of(piece: Dictionary) -> Dictionary:
	return {
		"center": Vector2(piece["center"]),
		"rotation": float(piece.get("rotation", 0.0)),
		"world_size": Vector2(piece["world_size"]),
	}


static func _restore_pose(piece: Dictionary, pose: Dictionary) -> void:
	piece["center"] = Vector2(pose["center"])
	piece["rotation"] = float(pose["rotation"])
	piece["world_size"] = Vector2(pose["world_size"])


## Gira una pieza sin moverla de sitio, y solo si el giro no la mete en un lio.
##
## Girar cambia la caja que ocupa -el largo pasa a estar sobre el otro eje-, asi
## que un giro "gratis" puede sacar la pieza de la sala o meterla dentro de otra.
## Si eso pasa, se deja como estaba: mirar bien no vale una pieza atravesada.
static func _reorient_in_place(
	room: Rect2, piece: Dictionary, center: Vector2,
	rotacion_antes: float, rotacion_nueva: float, occupied: Array
) -> void:
	if is_equal_approx(rotacion_antes, rotacion_nueva):
		piece["center"] = center
		return
	var world: Vector2 = _footprint(piece, rotacion_nueva)
	# Girada, la pieza puede dejar de caber: el largo pasa al otro eje y la sala
	# es mas estrecha por ahi. `_clamp_center` no puede arreglar eso -devuelve el
	# centro de la sala y la pieza asoma por los dos lados-, asi que se
	# comprueba antes.
	if world.x > room.size.x or world.y > room.size.y:
		piece["center"] = center
		return
	var nuevo_centro: Vector2 = _clamp_center(room, center, world)
	if _collides(Rect2(nuevo_centro - world * 0.5, world), occupied):
		piece["center"] = center
		piece["rotation"] = rotacion_antes
		piece["world_size"] = _footprint(piece, rotacion_antes)
		return
	piece["center"] = nuevo_centro
	piece["rotation"] = rotacion_nueva
	piece["world_size"] = world


## Superficie que pisaria una pieza en ese sitio. Lo que tapa el paso de una
## puerta pesa el cuadruple: un mueble rozando otro se ve raro, uno delante de
## una puerta estorba de verdad.
static func _overlap_cost(rect: Rect2, occupied: Array, blockers: Array) -> float:
	var coste: float = 0.0
	for other in occupied:
		var inter: Rect2 = rect.intersection(Rect2(other))
		if inter.size.x <= 0.0 or inter.size.y <= 0.0:
			continue
		var area: float = inter.size.x * inter.size.y
		coste += area * (4.0 if _is_blocker(Rect2(other), blockers) else 1.0)
	return coste


static func _is_blocker(rect: Rect2, blockers: Array) -> bool:
	for blocker in blockers:
		if Rect2(blocker).is_equal_approx(rect):
			return true
	return false


## Cuanto ocupa una caja alineada con los ejes medida a lo largo de `axis`.
static func _extent_along(world: Vector2, axis: Vector2) -> float:
	return absf(axis.x) * world.x + absf(axis.y) * world.y


## A que paramento apunta una direccion desde un punto.
static func _side_towards(room: Rect2, from: Vector2, direccion: Vector2) -> String:
	if absf(direccion.x) >= absf(direccion.y):
		return "right" if direccion.x >= 0.0 else "left"
	return "bottom" if direccion.y >= 0.0 else "top"


static func _try_side(room: Rect2, piece: Dictionary, side: String, occupied: Array) -> bool:
	var horizontal: bool = WallSideGeometry.is_horizontal(side)
	piece["long_along"] = _effective_long_along(room, piece, side)
	# Cuanto ocupa la pieza A LO LARGO del paramento. No es siempre su lado
	# largo: una cama apoya el cabecero, asi que lo que corre por el muro es su
	# ancho.
	var apoyada: Vector2 = _footprint(piece, _rotation_for_side(side))
	var along_len: float = apoyada.x if horizontal else apoyada.y
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
	var horizontal: bool = WallSideGeometry.is_horizontal(side)
	piece["long_along"] = _effective_long_along(room, piece, side)
	var rotation_deg: float = _rotation_for_side(side)
	var world: Vector2 = _footprint(piece, rotation_deg)
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


static func _place_free(room: Rect2, piece: Dictionary, occupied: Array, blockers: Array = []) -> void:
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
	if best_distance == INF:
		if bool(piece.get("visual_only", false)):
			piece["hidden"] = true
			return
		# Antes de resignarse, se encoge lo que tenga dimension libre: es la
		# misma salida que ya tenian las piezas de paramento, y una comoda algo
		# mas corta es mejor que una comoda metida dentro de la cama.
		for factor in SHRINK_STEPS:
			if not _shrink(piece, factor):
				break
			world = Vector2(piece["world_size"])
			for ix in range(steps_x + 1):
				for iy in range(steps_y + 1):
					var libre: Vector2 = _clamp_center(
						room, Vector2(float(ix) * SLIDE_STEP_M, float(iy) * SLIDE_STEP_M), world
					)
					if _collides(Rect2(libre - world * 0.5, world), occupied):
						continue
					piece["center"] = libre
					return
		# Una pieza del escenario es carga de fuego y tiene que estar en algun
		# sitio. Si no queda ni un hueco libre, se elige el mal menor: el sitio
		# que menos superficie pise, contando el paso de una puerta cuadruple
		# -taparle el paso a una puerta es peor que rozar un mueble-.
		var menor: float = INF
		for ix in range(steps_x + 1):
			for iy in range(steps_y + 1):
				var candidato: Vector2 = _clamp_center(
					room, Vector2(float(ix) * SLIDE_STEP_M, float(iy) * SLIDE_STEP_M), world
				)
				var coste: float = _overlap_cost(Rect2(candidato - world * 0.5, world), occupied, blockers)
				if coste >= menor:
					continue
				menor = coste
				best = candidato
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


## Si esta pieza puede permitirse el lujo de ir de cabecero contra ESE muro.
##
## Una cama de 1,90 no cabe de cabecero en una habitacion de 2,00 de fondo: no
## quedaria por donde salir de ella, y ademas se come el paramento entero y deja
## sin sitio a la comoda. En una habitacion estrecha la cama va en paralelo, que
## es lo que se hace de verdad.
static func _effective_long_along(room: Rect2, piece: Dictionary, side: String) -> bool:
	if not bool(piece.get("cabecero", true)):
		return false
	if not FurnitureRoomGrammar.long_axis_is_along(String(piece.get("archetype", ""))):
		return false
	var fondo: float = room.size.y if WallSideGeometry.is_horizontal(side) else room.size.x
	var largo: float = maxf(Vector2(piece["real"]).x, Vector2(piece["real"]).y)
	return fondo >= largo + BED_EXIT_M


## Caja que ocupa una pieza girada, teniendo en cuenta por que eje le cae el
## lado largo. Para casi todo el largo va cruzado a la mirada -un sofa apoya el
## respaldo-; para una cama va en linea con ella, porque lo que toca el muro es
## el cabecero.
static func _footprint(piece: Dictionary, rotation_deg: float) -> Vector2:
	var real: Vector2 = Vector2(piece["real"])
	if bool(piece.get("long_along", false)):
		real = Vector2(real.y, real.x)
	return _world_size(real, rotation_deg)


## Giro que le toca a una pieza apoyada en cada paramento: siempre mirando
## hacia dentro de la sala.
static func _rotation_for_side(side: String) -> float:
	match side:
		"top":
			return 0.0
		"bottom":
			return 180.0
		"left":
			return 90.0
		_:
			return -90.0


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
	# Dos giros, y son cosas distintas. `rotation_deg` es el de la MALLA, y con
	# el mas `size_m` sale la huella: es el contrato que ya tenian las dos
	# vistas y los guardarrailes. `visual_facing_deg` es hacia donde MIRA la
	# pieza. Para casi todo coinciden; para una cama no, porque su largo va en
	# la direccion en la que mira y el de la malla va cruzado. Mezclarlos era lo
	# que dejaba a la cama tumbada de lado.
	var facing: float = float(piece["rotation"])
	var mesh_rotation: float = facing + (90.0 if bool(piece.get("long_along", false)) else 0.0)
	spec["size_m"] = size
	spec["rotation_deg"] = mesh_rotation
	spec["visual_facing_deg"] = facing
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

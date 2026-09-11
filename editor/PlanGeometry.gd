extends RefCounted
## La geometria del plano del editor: rectangulos girados, objetos dentro de su
## sala y distancias a un segmento.
##
## Funciones estaticas y puras. Las comparten las tres cosas que trabajan sobre
## el plano -el dibujo, los clics y el panel de propiedades-, y por eso estaban
## repartidas por el fichero del editor: cada una las usaba desde su lado.
##
## Cuarto modulo de E-12 (docs/AUDITORIA_EDITOR_2026-09-06.md). Sacarlas es lo
## que permite mover despues el dibujo sin arrastrar con el la mitad del editor.
##
## Dos convenios que conviene tener presentes al leerlas:
##
## - La posicion de un objeto se guarda **local a su sala** y sin girar; lo que
##   se ve y se agarra en el plano es su caja YA girada. `visual_min` y
##   `local_pos` son las dos caras de eso.
## - El lado de una pared admite alias cardinales, y se canonizan con
##   `WallSideGeometry.canonical()`: el mundo FP ya se comio una vez plantar las
##   ventanas del norte en la pared derecha por no hacerlo.


const Serializer = preload("res://editor/ScenarioSerializer.gd")

## La rejilla del plano, y lo que un objeto se pega a la pared al soltarlo
## cerca. Las dos las comparte el editor, que las lee de aqui.
const GRID_M: float = 0.25
const OBJECT_WALL_SNAP_M: float = GRID_M * 0.75


## La caja de un objeto girado: cuanto ocupa en X e Y una vez rota.
static func rotated_object_aabb_size(size_m: Vector2, rotation_deg: float) -> Vector2:
	var angle: float = deg_to_rad(rotation_deg)
	var c: float = absf(cos(angle))
	var s: float = absf(sin(angle))
	return Vector2(size_m.x * c + size_m.y * s, size_m.x * s + size_m.y * c)


static func object_transform(rotation_deg: float) -> Transform2D:
	return Transform2D(deg_to_rad(rotation_deg), Vector2.ZERO)


## Grados en [-180, 180]. Todo el editor guarda los giros asi.
static func normalize_degrees_signed(value: float) -> float:
	var wrapped: float = fposmod(value + 180.0, 360.0) - 180.0
	if wrapped <= -180.0:
		return 180.0
	return wrapped


## Angulo limpio de un objeto: normalizado y encajado al eje mas cercano si cae
## dentro del umbral. El umbral es un ajuste del inspector del editor, asi que
## entra como argumento y esta funcion se queda pura.
static func clean_object_rotation_deg(rotation_deg: float, axis_snap_threshold_deg: float) -> float:
	var value: float = normalize_degrees_signed(rotation_deg)
	var threshold: float = maxf(0.0, axis_snap_threshold_deg)
	for axis in [0.0, 90.0, -90.0, 180.0]:
		if absf(normalize_degrees_signed(value - axis)) <= threshold:
			return normalize_degrees_signed(axis)
	if absf(value) <= 0.001:
		return 0.0
	return value


static func normalized_rect(a: Vector2, b: Vector2) -> Rect2:
	var pos := Vector2(minf(a.x, b.x), minf(a.y, b.y))
	var size := Vector2(absf(a.x - b.x), absf(a.y - b.y))
	return Rect2(pos, size)


static func distance_to_segment(point: Vector2, a: Vector2, b: Vector2) -> float:
	var ab: Vector2 = b - a
	var len_sq: float = ab.length_squared()
	if len_sq <= 0.000001:
		return point.distance_to(a)
	var t: float = clampf((point - a).dot(ab) / len_sq, 0.0, 1.0)
	return point.distance_to(a + ab * t)


## Largo del paramento. Pasa por `WallSideGeometry` para que "north" y "top"
## midan lo mismo: el editor comparaba la cadena a pelo y cualquier alias
## cardinal caia en el lado vertical.
static func wall_length(rect: Rect2, wall: String) -> float:
	if WallSideGeometry.is_horizontal(wall):
		return rect.size.x
	return rect.size.y


static func rotated_rect_points_m(rect: Rect2, rotation_deg: float) -> PackedVector2Array:
	var center: Vector2 = rect.get_center()
	var half: Vector2 = rect.size * 0.5
	var rot := Transform2D(deg_to_rad(rotation_deg), Vector2.ZERO)
	return PackedVector2Array([
		center + rot * Vector2(-half.x, -half.y),
		center + rot * Vector2(half.x, -half.y),
		center + rot * Vector2(half.x, half.y),
		center + rot * Vector2(-half.x, half.y)
	])


static func rotated_rect_has_point(rect: Rect2, rotation_deg: float, pos_m: Vector2) -> bool:
	if absf(rotation_deg) <= 0.001:
		return rect.has_point(pos_m)
	var local: Vector2 = Transform2D(deg_to_rad(-rotation_deg), Vector2.ZERO) * (pos_m - rect.get_center())
	return absf(local.x) <= rect.size.x * 0.5 and absf(local.y) <= rect.size.y * 0.5


static func object_size_m(obj: Dictionary) -> Vector2:
	var size: Vector2 = Serializer.vector2_from_data(obj.get("size_m", Vector2.ONE))
	return Vector2(maxf(0.05, size.x), maxf(0.05, size.y))


static func object_world_center(room_rect: Rect2, obj: Dictionary) -> Vector2:
	var pos: Vector2 = Serializer.vector2_from_data(obj.get("position_m", Vector2.ZERO))
	return room_rect.position + pos + object_size_m(obj) * 0.5


static func object_corner_points_m(room_rect: Rect2, obj: Dictionary) -> PackedVector2Array:
	var size: Vector2 = object_size_m(obj)
	var half: Vector2 = size * 0.5
	var center: Vector2 = object_world_center(room_rect, obj)
	var rot := object_transform(float(obj.get("rotation_deg", 0.0)))
	return PackedVector2Array([
		center + rot * Vector2(-half.x, -half.y),
		center + rot * Vector2(half.x, -half.y),
		center + rot * Vector2(half.x, half.y),
		center + rot * Vector2(-half.x, half.y)
	])


static func object_visual_min_from_local_pos(size_m: Vector2, local_pos: Vector2, rotation_deg: float) -> Vector2:
	return local_pos + size_m * 0.5 - rotated_object_aabb_size(size_m, rotation_deg) * 0.5


static func object_local_pos_from_visual_min(size_m: Vector2, visual_min: Vector2, rotation_deg: float) -> Vector2:
	return visual_min + rotated_object_aabb_size(size_m, rotation_deg) * 0.5 - size_m * 0.5


static func clamp_object_local_pos(room_rect: Rect2, size_m: Vector2, local_pos: Vector2) -> Vector2:
	return clamp_object_local_pos_for_rotation(room_rect, size_m, local_pos, 0.0)


static func clamp_object_local_pos_for_rotation(room_rect: Rect2, size_m: Vector2, local_pos: Vector2, rotation_deg: float) -> Vector2:
	var clamped_size := Vector2(maxf(0.05, size_m.x), maxf(0.05, size_m.y))
	var center: Vector2 = local_pos + clamped_size * 0.5
	var extents: Vector2 = rotated_object_aabb_size(clamped_size, rotation_deg)
	var min_center: Vector2 = extents * 0.5
	var max_center: Vector2 = room_rect.size - extents * 0.5
	if max_center.x < min_center.x:
		center.x = room_rect.size.x * 0.5
	else:
		center.x = clampf(center.x, min_center.x, max_center.x)
		if center.x - min_center.x <= OBJECT_WALL_SNAP_M:
			center.x = min_center.x
		elif max_center.x - center.x <= OBJECT_WALL_SNAP_M:
			center.x = max_center.x
	if max_center.y < min_center.y:
		center.y = room_rect.size.y * 0.5
	else:
		center.y = clampf(center.y, min_center.y, max_center.y)
		if center.y - min_center.y <= OBJECT_WALL_SNAP_M:
			center.y = min_center.y
		elif max_center.y - center.y <= OBJECT_WALL_SNAP_M:
			center.y = max_center.y
	return center - clamped_size * 0.5

## Un punto del plano, visto desde el objeto: centrado en el y sin su giro. Con
## eso, «¿esta dentro?» es comparar contra medias medidas y ya.
static func world_to_object_local(pos_m: Vector2, center_m: Vector2, rotation_deg: float) -> Vector2:
	return Transform2D(deg_to_rad(-rotation_deg), Vector2.ZERO) * (pos_m - center_m)


## Si el punto cae dentro del objeto ya girado. El margen va aparte porque
## depende del zoom: pinchar una silla a 20 px/m y a 200 no es lo mismo.
static func object_has_point(room_rect: Rect2, obj: Dictionary, pos_m: Vector2, hit_padding_m: float) -> bool:
	var size: Vector2 = object_size_m(obj)
	var local: Vector2 = world_to_object_local(
		pos_m, object_world_center(room_rect, obj), float(obj.get("rotation_deg", 0.0))
	)
	return absf(local.x) <= size.x * 0.5 + hit_padding_m and absf(local.y) <= size.y * 0.5 + hit_padding_m


## ── Paredes de una sala ─────────────────────────────────────────────────────
##
## De donde arranca cada pared y hacia donde corre, y como se sacan tramos sobre
## ella. Estaban en ScenarioEditor y son geometria pura: solo entra un rectangulo
## y un nombre de pared.

static func wall_start_dir(rect: Rect2, wall: String) -> Dictionary:
	match wall:
		"top":
			return {"start": rect.position, "dir": Vector2.RIGHT}
		"bottom":
			return {"start": rect.position + Vector2(0.0, rect.size.y), "dir": Vector2.RIGHT}
		"left":
			return {"start": rect.position, "dir": Vector2.DOWN}
		"right":
			return {"start": rect.position + Vector2(rect.size.x, 0.0), "dir": Vector2.DOWN}
	return {"start": rect.position, "dir": Vector2.RIGHT}


static func wall_segment(rect: Rect2, wall: String, offset_m: float, width_m: float) -> PackedVector2Array:
	var wall_data: Dictionary = wall_start_dir(rect, wall)
	var start: Vector2 = wall_data["start"]
	var dir: Vector2 = wall_data["dir"]
	var length: float = wall_length(rect, wall)
	var half_width: float = minf(width_m, length) * 0.5
	var center_offset: float = clampf(offset_m, half_width, maxf(half_width, length - half_width))
	var center: Vector2 = start + dir * center_offset
	return PackedVector2Array([center - dir * half_width, center + dir * half_width])


static func line_segment_from_fraction(a: Vector2, b: Vector2, offset_fraction: float, width_m: float) -> PackedVector2Array:
	var axis: Vector2 = b - a
	var length: float = axis.length()
	if length <= 0.0001:
		return PackedVector2Array()
	var dir: Vector2 = axis / length
	var safe_width: float = minf(width_m, length)
	var center_offset: float = clampf(length * clampf(offset_fraction, 0.0, 1.0), safe_width * 0.5, maxf(safe_width * 0.5, length - safe_width * 0.5))
	var center: Vector2 = a + dir * center_offset
	return PackedVector2Array([center - dir * safe_width * 0.5, center + dir * safe_width * 0.5])


static func offset_on_wall(rect: Rect2, wall: String, pos_m: Vector2) -> float:
	match wall:
		"top", "bottom":
			return clampf(pos_m.x - rect.position.x, 0.0, rect.size.x)
		"left", "right":
			return clampf(pos_m.y - rect.position.y, 0.0, rect.size.y)
	return 0.0


static func segments_overlap_m(a1: Vector2, a2: Vector2, b1: Vector2, b2: Vector2) -> bool:
	if a1.distance_to(a2) <= 0.0001 or b1.distance_to(b2) <= 0.0001:
		return false
	var horizontal: bool = absf(a1.y - a2.y) <= 0.001
	if horizontal:
		if absf(a1.y - b1.y) > 0.05:
			return false
		var a_min: float = minf(a1.x, a2.x)
		var a_max: float = maxf(a1.x, a2.x)
		var b_min: float = minf(b1.x, b2.x)
		var b_max: float = maxf(b1.x, b2.x)
		return minf(a_max, b_max) - maxf(a_min, b_min) > 0.05
	if absf(a1.x - b1.x) > 0.05:
		return false
	var ay_min: float = minf(a1.y, a2.y)
	var ay_max: float = maxf(a1.y, a2.y)
	var by_min: float = minf(b1.y, b2.y)
	var by_max: float = maxf(b1.y, b2.y)
	return minf(ay_max, by_max) - maxf(ay_min, by_min) > 0.05

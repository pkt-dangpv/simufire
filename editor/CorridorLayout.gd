extends RefCounted
## La geometria de un pasillo: que piezas salen de un trazo, y como encajan con
## lo que ya hay dibujado.
##
## Quinto corte de D-1 (docs/AUDITORIA_EDITOR_2026-09-06.md). La auditoria
## señalaba «3D en vivo» y «objetos» como los dos bloques a sacar; midiendo el
## acoplamiento resulto que la vista 3D es **el bloque que mas mira hacia
## fuera** de todo el fichero -80 miembros del editor- y los pasillos el que
## menos de los grandes: 16 funciones, 461 lineas y 24 miembros. Por eso salen
## estos y no aquellos.
##
## Estatico y puro, como PlanGeometry y StairPlanRules. **No conoce
## `editor_data`, ni la planta actual, ni la seleccion**: las tres reglas que
## miran «lo que ya hay» reciben los rectangulos ya filtrados por planta. Eso es
## lo que las hace comprobables de una en una, que es justo lo que un pasillo en
## L necesitaba: sus reglas se pisan entre si y a ojo no se distinguen.
##
## Los tres pasos, en orden, y cada uno arregla un fallo distinto:
##
##   1. `layout()`  — que forma tiene el trazo: recto, en L o un descansillo.
##   2. `fit_piece()` — el codo (meterse dentro del pasillo que continua) y el
##      hueco (correrse al lado libre en vez de recortarse hasta desaparecer).
##   3. `trim()` — recortar lo que pise a lo que ya existe, porque **dos salas
##      solapadas son dos zonas que se reparten el mismo aire** y el modelo las
##      contaria dos veces.
##
## Aviso heredado del repositorio: **un `Array[Rect2]` descarta en silencio** lo
## que no sea un `Rect2`, y `duplicate()` conserva el tipo. Aqui las listas van
## como `Array` a secas y se comprueba el tipo al leerlas.


## Que piezas salen de un trazo de `start_m` a `end_m`.
##
## `forced_mode` es lo que el usuario impone mientras arrastra: `"l"` gira,
## `"recto"` no gira, `""` lo decide el gesto. Antes solo existia lo tercero, y
## un arrastre en diagonal moderada caia en el umbral y **salia recto sin
## avisar**: de ahi «hago un pasillo inclinado y no puedo hacer una U».
static func layout(start_m: Vector2, end_m: Vector2, width_m: float, forced_mode: String, grid_m: float) -> Dictionary:
	var dx: float = end_m.x - start_m.x
	var dy: float = end_m.y - start_m.y
	var abs_dx: float = absf(dx)
	var abs_dy: float = absf(dy)
	# Un clic sin arrastre es una pieza cuadrada del ancho del pasillo: eso es un
	# descansillo, y antes era un error. Componiendo piezas salen los giros, las
	# U y los rellanos, que es como se hacen los pasillos de verdad.
	if abs_dx < grid_m and abs_dy < grid_m:
		return {
			"mode": "straight",
			"orientation": "square",
			"rects": [Rect2(start_m - Vector2(width_m, width_m) * 0.5, Vector2(width_m, width_m))],
			"length_m": width_m
		}

	if forced_mode == "recto":
		# Recto forzado: manda el eje mas largo del gesto.
		if abs_dx >= abs_dy:
			return _straight(start_m, end_m, width_m, true, maxf(abs_dx, width_m), true)
		return _straight(start_m, end_m, width_m, false, maxf(abs_dy, width_m), true)

	if forced_mode != "l" and (abs_dx >= maxf(width_m * 1.25, abs_dy * 2.0) or abs_dy < width_m * 0.60):
		# Mas corto que ancho: se queda cuadrado, que sigue siendo una pieza util.
		return _straight(start_m, end_m, width_m, true, maxf(abs_dx, width_m), false)

	if forced_mode != "l" and (abs_dy >= maxf(width_m * 1.25, abs_dx * 2.0) or abs_dx < width_m * 0.60):
		return _straight(start_m, end_m, width_m, false, maxf(abs_dy, width_m), false)

	# Si un brazo no da para giro, no se rechaza el gesto: sale el tramo recto del
	# eje que manda, y el giro se hace dibujando otra pieza pegada.
	if forced_mode != "l" and (abs_dx < width_m * 1.5 or abs_dy < width_m * 1.5):
		var along_x: bool = abs_dx >= abs_dy
		return _straight(start_m, end_m, width_m, along_x, maxf(abs_dx if along_x else abs_dy, width_m), false)

	var sx: float = 1.0 if dx >= 0.0 else -1.0
	var sy: float = 1.0 if dy >= 0.0 else -1.0
	var corner_x: float = end_m.x
	var horizontal_rect: Rect2 = _normalized_rect(start_m, Vector2(corner_x, start_m.y + sy * width_m))
	var vertical_rect: Rect2 = _normalized_rect(Vector2(corner_x - sx * width_m, start_m.y + sy * width_m), end_m)
	# Una L cuyo brazo sea mas fino que el pasillo no es una L: es un tramo con
	# una rebaba. Sale el recto, y quien pidio la L se entera comparando lo que
	# pidio con el `mode` que recibe -que es lo que ya hace el editor para decir
	# «no cabe» en la previsualizacion-. Sin bandera aparte: una bandera que
	# nadie lee es adorno que no se puede comprobar.
	if horizontal_rect.size.x < width_m or horizontal_rect.size.y < grid_m \
			or vertical_rect.size.x < grid_m or vertical_rect.size.y < width_m:
		return _straight(start_m, end_m, width_m, true, maxf(abs_dx, width_m), false)

	return {
		"mode": "l",
		"orientation": "horizontal_first",
		"rects": [horizontal_rect, vertical_rect],
		"corner_m": Vector2(corner_x, start_m.y),
		"length_m": horizontal_rect.size.x + vertical_rect.size.y
	}


## El codo y el hueco, en ese orden. `corridor_rects` son los pasillos de la
## planta y `room_rects` todas las salas de la planta, los dos ya filtrados.
static func fit_piece(rect: Rect2, start_m: Vector2, end_m: Vector2, corridor_rects: Array, room_rects: Array, grid_m: float) -> Rect2:
	var along_x: bool = rect.size.x >= rect.size.y
	return slide_out_of_rooms(align_corner(rect, along_x, start_m, end_m, corridor_rects, grid_m), along_x, room_rects)


## El codo: el tramo nuevo se mete dentro del pasillo que continua.
##
## Solo se aplica al pasillo donde empieza o acaba el trazo -ahi es donde el
## usuario esta girando- y solo si el desplazamiento es menor que un ancho: mas
## lejos que eso ya no es su esquina, es otro pasillo cualquiera.
static func align_corner(rect: Rect2, along_x: bool, start_m: Vector2, end_m: Vector2, corridor_rects: Array, grid_m: float) -> Rect2:
	var band: Vector2 = cross_interval(rect, along_x)
	var width_m: float = band.y - band.x
	for raw in corridor_rects:
		if typeof(raw) != TYPE_RECT2:
			continue
		var other_rect: Rect2 = raw
		if other_rect.size.x <= 0.0 or other_rect.size.y <= 0.0:
			continue
		var reach: Rect2 = other_rect.grow(grid_m)
		if not (reach.has_point(start_m) or reach.has_point(end_m)):
			continue
		var host: Vector2 = cross_interval(other_rect, along_x)
		# Si el tramo no cabe de ancho dentro del otro, no hay codo que cuadrar.
		if host.y - host.x < width_m - 0.001:
			continue
		var lo: float = clampf(band.x, host.x, host.y - width_m)
		if absf(lo - band.x) > width_m + 0.001:
			continue
		band = Vector2(lo, lo + width_m)
	return with_cross_interval(rect, along_x, band.x, band.y)


## El hueco: si el tramo pisa de lado a lado una habitacion, se corre al hueco
## libre que tiene al lado en vez de recortarse hasta desaparecer.
##
## Lo que distingue "estorbo lateral" de "el tramo del que vengo" es cuanto del
## largo pisa: el pasillo anterior toca una PUNTA -y eso lo recorta el recorte-,
## mientras que la habitacion por cuya junta estas dibujando cruza el tramo
## entero.
static func slide_out_of_rooms(rect: Rect2, along_x: bool, room_rects: Array) -> Rect2:
	var band: Vector2 = cross_interval(rect, along_x)
	var width_m: float = band.y - band.x
	var run_lo: float = rect.position.x if along_x else rect.position.y
	var run_hi: float = rect.end.x if along_x else rect.end.y
	var run_span: float = maxf(0.001, run_hi - run_lo)
	var centre: float = (band.x + band.y) * 0.5
	var free_lo: float = -INF
	var free_hi: float = INF
	for raw in room_rects:
		if typeof(raw) != TYPE_RECT2:
			continue
		var other_rect: Rect2 = raw
		if other_rect.size.x <= 0.0 or other_rect.size.y <= 0.0:
			continue
		var other_run_lo: float = other_rect.position.x if along_x else other_rect.position.y
		var other_run_hi: float = other_rect.end.x if along_x else other_rect.end.y
		if minf(run_hi, other_run_hi) - maxf(run_lo, other_run_lo) < run_span * 0.80:
			continue
		var other_cross: Vector2 = cross_interval(other_rect, along_x)
		if other_cross.y <= centre + 0.001:
			free_lo = maxf(free_lo, other_cross.y)
		elif other_cross.x >= centre - 0.001:
			free_hi = minf(free_hi, other_cross.x)
		else:
			# El eje cae DENTRO de una habitacion: ahi no hay hueco al lado, y
			# mover el pasillo seria inventarse otro sitio.
			return rect
	if free_lo == -INF and free_hi == INF:
		return rect
	var lo: float = free_lo if free_lo != -INF else band.x
	var hi: float = free_hi if free_hi != INF else band.y
	var gap_m: float = hi - lo
	if free_lo != -INF and free_hi != INF and gap_m < width_m - 0.001:
		# El hueco es mas estrecho que el pasillo configurado: se estrecha el
		# pasillo, que es lo que el usuario esta dibujando. Por debajo de 60 cm
		# ya no es un paso y se deja como estaba.
		if gap_m < 0.60:
			return rect
		return with_cross_interval(rect, along_x, lo, hi)
	var start_lo: float = band.x
	if free_lo != -INF:
		start_lo = maxf(start_lo, free_lo)
	if free_hi != INF:
		start_lo = minf(start_lo, free_hi - width_m)
	return with_cross_interval(rect, along_x, start_lo, start_lo + width_m)


## Recorta un tramo de pasillo por donde pisa lo que ya existe.
##
## Dibujando en L, el segundo tramo se empieza donde acabo el primero, asi que lo
## normal es que SOLAPE con el en el codo. Dos salas solapadas son dos zonas que
## se reparten el mismo aire: el modelo las contaria dos veces. Se recorta el
## trozo invadido y las dos piezas quedan a tope, que es lo que hace que despues
## se puedan unir con un hueco.
static func trim(rect: Rect2, room_rects: Array, grid_m: float) -> Rect2:
	var trimmed: Rect2 = rect
	for raw in room_rects:
		if typeof(raw) != TYPE_RECT2:
			continue
		var other_rect: Rect2 = raw
		if other_rect.size.x <= 0.0 or other_rect.size.y <= 0.0:
			continue
		var overlap: Rect2 = trimmed.intersection(other_rect)
		if overlap.size.x <= grid_m * 0.5 or overlap.size.y <= grid_m * 0.5:
			continue
		# Se recorta por el eje largo del tramo: es el que se puede acortar sin
		# cambiar el ancho del pasillo.
		if trimmed.size.x >= trimmed.size.y:
			if absf(overlap.position.x - trimmed.position.x) < 0.001:
				var cut_start: float = overlap.end.x
				trimmed = Rect2(Vector2(cut_start, trimmed.position.y), Vector2(maxf(0.0, trimmed.end.x - cut_start), trimmed.size.y))
			elif absf(overlap.end.x - trimmed.end.x) < 0.001:
				trimmed = Rect2(trimmed.position, Vector2(maxf(0.0, overlap.position.x - trimmed.position.x), trimmed.size.y))
		else:
			if absf(overlap.position.y - trimmed.position.y) < 0.001:
				var cut_top: float = overlap.end.y
				trimmed = Rect2(Vector2(trimmed.position.x, cut_top), Vector2(trimmed.size.x, maxf(0.0, trimmed.end.y - cut_top)))
			elif absf(overlap.end.y - trimmed.end.y) < 0.001:
				trimmed = Rect2(trimmed.position, Vector2(trimmed.size.x, maxf(0.0, overlap.position.y - trimmed.position.y)))
	return trimmed


## El lado corto del tramo, como intervalo: es lo unico que el codo y el hueco
## mueven.
static func cross_interval(rect: Rect2, along_x: bool) -> Vector2:
	return Vector2(rect.position.y, rect.end.y) if along_x else Vector2(rect.position.x, rect.end.x)


static func with_cross_interval(rect: Rect2, along_x: bool, lo: float, hi: float) -> Rect2:
	if along_x:
		return Rect2(rect.position.x, lo, rect.size.x, hi - lo)
	return Rect2(lo, rect.position.y, hi - lo, rect.size.y)


## Un tramo recto por el eje que se le diga. Estaba escrito cinco veces en
## `layout()`, con las mismas cuatro cuentas cada vez.
static func _straight(start_m: Vector2, end_m: Vector2, width_m: float, along_x: bool, length_m: float, forced: bool) -> Dictionary:
	var rect: Rect2
	if along_x:
		rect = Rect2(Vector2(minf(start_m.x, end_m.x), start_m.y - width_m * 0.5), Vector2(length_m, width_m))
	else:
		rect = Rect2(Vector2(start_m.x - width_m * 0.5, minf(start_m.y, end_m.y)), Vector2(width_m, length_m))
	var out: Dictionary = {
		"mode": "straight",
		"orientation": "horizontal" if along_x else "vertical",
		"rects": [rect],
		"length_m": length_m,
	}
	if forced:
		out["forced"] = true
	return out


static func _normalized_rect(a: Vector2, b: Vector2) -> Rect2:
	return Rect2(Vector2(minf(a.x, b.x), minf(a.y, b.y)), (b - a).abs())

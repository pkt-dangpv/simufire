class_name EditorDraw2D
extends RefCounted

# Pure 2D drawing helpers for ScenarioEditor.
# All functions accept a CanvasItem as first argument and call draw_* on it.
# No dependency on ScenarioEditor state — safe to call from any CanvasItem.


## Draw the center-axis guide line for a corridor room.
## Indicates the circulation direction of the corridor.
static func corridor_room_guides(canvas: CanvasItem, rect_px: Rect2) -> void:
	var center: Vector2 = rect_px.get_center()
	var half_major: float = maxf(rect_px.size.x, rect_px.size.y) * 0.5 - 10.0
	if half_major <= 4.0:
		return
	var a: Vector2
	var b: Vector2
	if rect_px.size.x >= rect_px.size.y:
		a = center - Vector2(half_major, 0.0)
		b = center + Vector2(half_major, 0.0)
	else:
		a = center - Vector2(0.0, half_major)
		b = center + Vector2(0.0, half_major)
	canvas.draw_line(a, b, Color(0.80, 1.0, 0.92, 0.36), 2.0)
	canvas.draw_circle(a, 2.5, Color(0.80, 1.0, 0.92, 0.50))
	canvas.draw_circle(b, 2.5, Color(0.80, 1.0, 0.92, 0.50))


## Draw dimension labels (Largo / Ancho) for narrow rooms such as corridors and stairs.
## Labels are drawn above and to the right of rect_px using the fallback font.
static func narrow_room_dimension_labels(canvas: CanvasItem, rect_m: Rect2, rect_px: Rect2, is_stairs: bool) -> void:
	var label_color: Color = Color(0.72, 1.0, 0.94, 0.96) if not is_stairs else Color(1.0, 0.84, 0.34, 0.96)
	var long_m: float = maxf(rect_m.size.x, rect_m.size.y)
	var wide_m: float = minf(rect_m.size.x, rect_m.size.y)
	var long_label: String = "Largo %.2f m" % long_m
	var wide_label: String = "Ancho %.2f m" % wide_m
	if canvas.has_method("_draw_screen_string"):
		canvas.call("_draw_screen_string", rect_px.position, Vector2(4.0, -6.0), long_label, 180.0, 11, label_color)
		canvas.call("_draw_screen_string", rect_px.position + Vector2(rect_px.size.x, 0.0), Vector2(8.0, 18.0), wide_label, 160.0, 11, label_color)
		return
	if ThemeDB.fallback_font == null:
		return
	var inv_zoom: float = float(canvas.call("_screen_scale_inv")) if canvas.has_method("_screen_scale_inv") else 1.0
	var font_size: int = maxi(4, int(round(11.0 * inv_zoom)))
	var top_pos: Vector2 = rect_px.position + Vector2(4.0, -6.0) * inv_zoom
	canvas.draw_string(
		ThemeDB.fallback_font,
		top_pos,
		long_label,
		HORIZONTAL_ALIGNMENT_LEFT,
		180.0,
		font_size,
		label_color
	)
	var side_pos: Vector2 = Vector2(rect_px.position.x + rect_px.size.x + 8.0 * inv_zoom, rect_px.position.y + minf(18.0 * inv_zoom, rect_px.size.y * 0.5))
	canvas.draw_string(
		ThemeDB.fallback_font,
		side_pos,
		wide_label,
		HORIZONTAL_ALIGNMENT_LEFT,
		160.0,
		font_size,
		label_color
	)


## Draw stair-step guides for a straight or L-turn stair room.
## dir = stair run direction (normalized Vector2).
## turn_degrees = value of room["stair_turn_degrees"]; >= 179 triggers switchback layout.
static func stair_room_guides(canvas: CanvasItem, rect_px: Rect2, dir: Vector2, turn_degrees: float) -> void:
	var normal := Vector2(-dir.y, dir.x)
	var center: Vector2 = rect_px.get_center()
	var long_px: float = rect_px.size.x if absf(dir.x) > absf(dir.y) else rect_px.size.y
	var cross_px: float = rect_px.size.y if absf(dir.x) > absf(dir.y) else rect_px.size.x
	if turn_degrees >= 179.0:
		switchback_stair_room_guides(canvas, rect_px, dir, normal, center, long_px, cross_px)
		return
	var start: Vector2 = center - dir * (long_px * 0.5 - 8.0)
	var end: Vector2 = center + dir * (long_px * 0.5 - 8.0)
	var half_width: float = maxf(10.0, cross_px * 0.22)
	var steps: int = clampi(int(long_px / 22.0), 4, 14)
	for i in range(steps + 1):
		var t: float = float(i) / float(maxi(1, steps))
		var p: Vector2 = start.lerp(end, t)
		canvas.draw_line(p - normal * half_width, p + normal * half_width, Color(1.0, 0.78, 0.20, 0.62), 1.4)
	canvas.draw_line(start - normal * half_width, end - normal * half_width, Color(1.0, 0.78, 0.20, 0.34), 1.0)
	canvas.draw_line(start + normal * half_width, end + normal * half_width, Color(1.0, 0.78, 0.20, 0.34), 1.0)
	canvas.draw_circle(start, 4.0, Color(0.95, 1.0, 0.82, 0.95))
	canvas.draw_line(start, end, Color(1.0, 0.90, 0.35, 0.72), 2.0)
	var arrow_left: Vector2 = end - dir * 12.0 + normal * 6.0
	var arrow_right: Vector2 = end - dir * 12.0 - normal * 6.0
	canvas.draw_colored_polygon(PackedVector2Array([end, arrow_left, arrow_right]), Color(1.0, 0.90, 0.35, 0.86))
	if ThemeDB.fallback_font != null and long_px > 60.0:
		if canvas.has_method("_draw_screen_string"):
			canvas.call("_draw_screen_string", start, Vector2(5.0, -5.0), "ENTRA", 70.0, 9, Color(0.95, 1.0, 0.82, 0.82))
			canvas.call("_draw_screen_string", end, Vector2(5.0, -5.0), "SUBE", 60.0, 9, Color(1.0, 0.90, 0.35, 0.86))
		else:
			canvas.draw_string(ThemeDB.fallback_font, start + Vector2(5.0, -5.0), "ENTRA", HORIZONTAL_ALIGNMENT_LEFT, 70.0, 9, Color(0.95, 1.0, 0.82, 0.82))
			canvas.draw_string(ThemeDB.fallback_font, end + Vector2(5.0, -5.0), "SUBE", HORIZONTAL_ALIGNMENT_LEFT, 60.0, 9, Color(1.0, 0.90, 0.35, 0.86))


## Draw switchback (180°) stair guides — two parallel lanes with cross-step lines.
## Called by stair_room_guides when turn_degrees >= 179.
static func switchback_stair_room_guides(canvas: CanvasItem, rect_px: Rect2, dir: Vector2, normal: Vector2, center: Vector2, long_px: float, cross_px: float) -> void:
	var start_center: Vector2 = center - dir * (long_px * 0.5 - 10.0)
	var end_center: Vector2 = center + dir * (long_px * 0.5 - 20.0)
	var lane_offset: float = maxf(8.0, cross_px * 0.20)
	var lane_half_width: float = maxf(5.0, cross_px * 0.13)
	var a0: Vector2 = start_center - normal * lane_offset
	var a1: Vector2 = end_center - normal * lane_offset
	var b0: Vector2 = end_center + normal * lane_offset
	var b1: Vector2 = start_center + normal * lane_offset
	var color := Color(1.0, 0.78, 0.20, 0.62)
	for i in range(7):
		var t: float = float(i) / 6.0
		var pa: Vector2 = a0.lerp(a1, t)
		var pb: Vector2 = b0.lerp(b1, t)
		canvas.draw_line(pa - normal * lane_half_width, pa + normal * lane_half_width, color, 1.2)
		canvas.draw_line(pb - normal * lane_half_width, pb + normal * lane_half_width, color, 1.2)
	canvas.draw_line(a0, a1, Color(1.0, 0.90, 0.35, 0.72), 2.0)
	canvas.draw_line(b0, b1, Color(1.0, 0.90, 0.35, 0.72), 2.0)
	canvas.draw_line(a1 - normal * lane_half_width, b0 + normal * lane_half_width, Color(1.0, 0.90, 0.35, 0.68), 2.0)
	canvas.draw_circle(a0, 4.0, Color(0.95, 1.0, 0.82, 0.95))
	canvas.draw_colored_polygon(PackedVector2Array([b1, b1 + dir * 10.0 + normal * 5.0, b1 + dir * 10.0 - normal * 5.0]), Color(1.0, 0.90, 0.35, 0.86))
	if ThemeDB.fallback_font != null and long_px > 60.0:
		if canvas.has_method("_draw_screen_string"):
			canvas.call("_draw_screen_string", a0, Vector2(5.0, -5.0), "ENTRA", 70.0, 9, Color(0.95, 1.0, 0.82, 0.82))
			canvas.call("_draw_screen_string", end_center, Vector2(5.0, -5.0), "180", 42.0, 9, Color(1.0, 0.90, 0.35, 0.86))
		else:
			canvas.draw_string(ThemeDB.fallback_font, a0 + Vector2(5.0, -5.0), "ENTRA", HORIZONTAL_ALIGNMENT_LEFT, 70.0, 9, Color(0.95, 1.0, 0.82, 0.82))
			canvas.draw_string(ThemeDB.fallback_font, end_center + Vector2(5.0, -5.0), "180", HORIZONTAL_ALIGNMENT_LEFT, 42.0, 9, Color(1.0, 0.90, 0.35, 0.86))


## Draw the player-start arrow icon at pixel position px.
## dir = normalized direction vector (world); radius = triangle half-size in pixels.
static func player_start_icon(canvas: CanvasItem, px: Vector2, dir: Vector2, radius: float, color: Color) -> void:
	var inv_zoom: float = float(canvas.call("_screen_scale_inv")) if canvas.has_method("_screen_scale_inv") else 1.0
	var font_size: int = maxi(4, int(round(10.0 * inv_zoom)))
	var pts := PackedVector2Array([
		px + dir * (radius + 4.0),
		px + dir.rotated(2.35) * radius,
		px + dir.rotated(-2.35) * radius
	])
	canvas.draw_colored_polygon(pts, color)
	canvas.draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[0]]), Color(0.0, 0.0, 0.0, 0.78), 1.6)
	if ThemeDB.fallback_font != null:
		if canvas.has_method("_draw_screen_string"):
			canvas.call("_draw_screen_string", px, Vector2(11.0, 4.0), "FP", 32.0, 10, color)
		else:
			canvas.draw_string(ThemeDB.fallback_font, px + Vector2(11.0, 4.0) * inv_zoom, "FP", HORIZONTAL_ALIGNMENT_LEFT, 32.0, font_size, color)


## Draw a detector circle icon at pixel position px.
## label = single character identifier ("S", "H", or "C").
static func detector_icon(canvas: CanvasItem, px: Vector2, radius: float, color: Color, label: String, selected: bool) -> void:
	var inv_zoom: float = float(canvas.call("_screen_scale_inv")) if canvas.has_method("_screen_scale_inv") else 1.0
	var font_size: int = maxi(4, int(round(11.0 * inv_zoom)))
	canvas.draw_circle(px, radius + 2.0, Color(0.0, 0.0, 0.0, 0.7))
	canvas.draw_circle(px, radius, color)
	if selected:
		canvas.draw_circle(px, radius + 2.0, Color(1.0, 1.0, 1.0, 0.85), false, 2.0)
	if ThemeDB.fallback_font != null:
		if canvas.has_method("_draw_screen_string"):
			canvas.call("_draw_screen_string", px, Vector2(-4.0, 5.0), label, 20.0, 11, Color(0.0, 0.0, 0.0, 0.92))
		else:
			canvas.draw_string(ThemeDB.fallback_font, px + Vector2(-4.0, 5.0) * inv_zoom, label, HORIZONTAL_ALIGNMENT_LEFT, 20.0, font_size, Color(0.0, 0.0, 0.0, 0.92))


## Draw a victim diamond icon at pixel position px.
static func victim_icon(canvas: CanvasItem, px: Vector2, r: float, color: Color, selected: bool) -> void:
	var inv_zoom: float = float(canvas.call("_screen_scale_inv")) if canvas.has_method("_screen_scale_inv") else 1.0
	var font_size: int = maxi(4, int(round(10.0 * inv_zoom)))
	var pts := PackedVector2Array([
		px + Vector2(0.0, -r),
		px + Vector2(r, 0.0),
		px + Vector2(0.0, r),
		px + Vector2(-r, 0.0)
	])
	canvas.draw_colored_polygon(pts, color)
	canvas.draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]), Color(0.0, 0.0, 0.0, 0.7), 1.5)
	if selected:
		canvas.draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]), Color(1.0, 1.0, 1.0, 0.85), 2.0)
	if ThemeDB.fallback_font != null:
		if canvas.has_method("_draw_screen_string"):
			canvas.call("_draw_screen_string", px, Vector2(-4.0, 5.0), "V", 16.0, 10, Color(0.0, 0.0, 0.0, 0.92))
		else:
			canvas.draw_string(ThemeDB.fallback_font, px + Vector2(-4.0, 5.0) * inv_zoom, "V", HORIZONTAL_ALIGNMENT_LEFT, 16.0, font_size, Color(0.0, 0.0, 0.0, 0.92))


## Draw selection handles: resize handles (green) and a rotate handle (blue).
## center_px = center of the element in pixels.
## rotate_px  = pixel position of the rotate handle.
## resize_pxs = pixel positions of the resize handles (width, length).
## handle_radius = base circle radius in pixels.
static func selection_handles(canvas: CanvasItem, center_px: Vector2, rotate_px: Vector2, resize_pxs: PackedVector2Array, handle_radius: float) -> void:
	canvas.draw_line(center_px, rotate_px, Color(1.0, 1.0, 1.0, 0.45), 1.2)
	for px in resize_pxs:
		canvas.draw_circle(px, handle_radius + 2.0, Color(0.0, 0.0, 0.0, 0.72))
		canvas.draw_circle(px, handle_radius, Color(0.95, 1.0, 0.80, 1.0))
		canvas.draw_circle(px, handle_radius, Color(1.0, 1.0, 1.0, 0.92), false, 1.4)
	canvas.draw_circle(rotate_px, handle_radius + 2.0, Color(0.0, 0.0, 0.0, 0.72))
	canvas.draw_circle(rotate_px, handle_radius, Color(0.46, 0.88, 1.0, 1.0))
	canvas.draw_circle(rotate_px, handle_radius, Color(1.0, 1.0, 1.0, 0.92), false, 1.4)


## Draw the swing-arc preview for a door opening.
## hinge_px = hinge point in canvas pixels; open_end_px = far end of the open door panel.
static func door_swing_preview(canvas: CanvasItem, hinge_px: Vector2, open_end_px: Vector2, color: Color) -> void:
	canvas.draw_line(hinge_px, open_end_px, color.lightened(0.20), 2.0)
	canvas.draw_circle(hinge_px, 3.5, color.lightened(0.30))


## Draw a vertical opening (floor/ceiling hole) as a semi-transparent filled+outlined rect.
## rect_px = hole rect in canvas pixels; color = outline/fill accent color.
static func vertical_opening(canvas: CanvasItem, rect_px: Rect2, color: Color) -> void:
	canvas.draw_rect(rect_px, Color(0.0, 0.0, 0.0, 0.48), true)
	canvas.draw_rect(rect_px, color, false, 2.0)


## Draw a single exterior wall segment.
## a_px / b_px = endpoints in canvas pixels (already converted from metres).
## color = wall color (selected or default). thickness_px = computed wall thickness in pixels.
## selected = true draws endpoint circles.
static func plan(canvas: CanvasItem, view: Dictionary) -> void:
	var font: Font = view.get("font")
	var scale_inv: float = float(view.get("screen_scale_inv", 1.0))
	ghost_floor(canvas, view.get("ghost_rooms", []), view.get("ghost_openings", []), font, scale_inv)
	rooms(canvas, view.get("rooms", []), font, scale_inv)
	openings(canvas, view.get("openings", []))
	objects(canvas, view.get("objects", []), font, scale_inv)
	player_start(canvas, view.get("player_start", {}))
	detectors(canvas, view.get("detectors", []))
	victims(canvas, view.get("victims", []))
	# La ficha de la sala -nombre, medidas y superficie- va LA ULTIMA, encima
	# de todo. Se dibujaba con la sala, o sea antes que los muebles, y en un
	# salon amueblado el sofa se comia el nombre y las medidas: el dato que
	# mas se consulta era el mas tapado (D-3).
	room_labels(canvas, view.get("rooms", []), font, scale_inv)


## La planta de abajo, apagada: sirve para alinear lo que se dibuja encima.
static func ghost_floor(canvas: CanvasItem, rooms_view: Array, openings_view: Array, font: Font, scale_inv: float) -> void:
	for entry in rooms_view:
		var room: Dictionary = entry
		var rect_px: Rect2 = room.get("rect_px", Rect2())
		canvas.draw_rect(rect_px, room.get("fill", Color.WHITE), true)
		canvas.draw_rect(rect_px, room.get("outline", Color.WHITE), false, 1.2)
		if bool(room.get("is_stair", false)):
			stair_room_guides(canvas, rect_px, room.get("stair_dir", Vector2.DOWN), float(room.get("turn_degrees", 0.0)))
		if room.has("label"):
			screen_string(canvas, font, scale_inv, rect_px.position, Vector2(6.0, 16.0),
				String(room["label"]), float(room.get("label_width_px", 30.0)), 10, room.get("label_color", Color.WHITE))
	for entry in openings_view:
		var opening: Dictionary = entry
		canvas.draw_line(opening.get("a_px", Vector2.ZERO), opening.get("b_px", Vector2.ZERO), opening.get("color", Color.WHITE), 3.0)


## Cada sala: su relleno, sus guias si es pasillo o escalera, su ficha de nombre,
## medidas y superficie, y los tiradores si esta seleccionada.
static func rooms(canvas: CanvasItem, rooms_view: Array, font: Font, scale_inv: float) -> void:
	for entry in rooms_view:
		var room: Dictionary = entry
		var rect_px: Rect2 = room.get("rect_px", Rect2())
		var fill: Color = room.get("fill", Color.WHITE)
		var outline: Color = room.get("outline", Color.WHITE)
		var points_px: PackedVector2Array = room.get("points_px", PackedVector2Array())
		if points_px.size() == 4:
			canvas.draw_colored_polygon(points_px, fill)
			canvas.draw_polyline(PackedVector2Array([points_px[0], points_px[1], points_px[2], points_px[3], points_px[0]]), outline, 2.0)
		else:
			canvas.draw_rect(rect_px, fill, true)
			canvas.draw_rect(rect_px, outline, false, 2.0)
		var is_corridor: bool = bool(room.get("is_corridor", false))
		var is_stair: bool = bool(room.get("is_stair", false))
		# Borrar la junta entre tramos del mismo pasillo: se repinta encima del
		# contorno con el relleno, y la U se lee como una U y no como tres
		# cajas pegadas. Van antes de las guias para no taparlas.
		for raw_seam in room.get("seams_px", []):
			var seam: Array = raw_seam
			if seam.size() == 2:
				canvas.draw_line(seam[0], seam[1], fill, 3.0)
		if is_corridor:
			corridor_room_guides(canvas, rect_px)
		if is_stair:
			stair_room_guides(canvas, rect_px, room.get("stair_dir", Vector2.DOWN), float(room.get("turn_degrees", 0.0)))
		if is_corridor or is_stair:
			narrow_room_dimension_labels(canvas, room.get("rect_m", Rect2()), rect_px, is_stair)
		if room.has("handles"):
			handles(canvas, room["handles"])


## Las fichas de las salas, en una pasada aparte y por encima del mobiliario.
##
## Van al final a proposito (D-3): dibujadas con la sala caian debajo de los
## muebles, y en un salon amueblado el nombre y las medidas quedaban tapados
## por el sofa.
static func room_labels(canvas: CanvasItem, rooms_view: Array, font: Font, scale_inv: float) -> void:
	for entry in rooms_view:
		var room: Dictionary = entry
		var rect_px: Rect2 = room.get("rect_px", Rect2())
		var points_px: PackedVector2Array = room.get("points_px", PackedVector2Array())
		var label_width_px: float = float(room.get("label_width_px", 40.0))
		# La ficha se colgaba de `rect_px.position`, la esquina del rectangulo
		# SIN girar. Al girar la sala el poligono se movia y la ficha se
		# quedaba fuera. En una sala girada se ancla en su CENTRO, que si gira
		# con ella, y se centra el texto.
		var rotated: bool = points_px.size() == 4
		var anchor_px: Vector2 = Vector2(room.get("label_center_px", rect_px.get_center())) if rotated else rect_px.position
		var min_side_px: float = minf(rect_px.size.x, rect_px.size.y) if not rotated else float(room.get("label_min_side_px", rect_px.size.y))
		room_label_line(canvas, font, scale_inv, anchor_px, 18.0 if not rotated else -8.0,
			String(room.get("name", "")), label_width_px, 13, room.get("name_color", Color.WHITE), rotated)
		if rect_px.size.y >= 36.0 or (rotated and min_side_px >= 36.0):
			room_label_line(canvas, font, scale_inv, anchor_px, 32.0 if not rotated else 6.0,
				String(room.get("dim_text", "")), label_width_px, 11, room.get("dim_color", Color.WHITE), rotated)
		if rect_px.size.y >= 52.0 or (rotated and min_side_px >= 52.0):
			room_label_line(canvas, font, scale_inv, anchor_px, 46.0 if not rotated else 20.0,
				String(room.get("area_text", "")), label_width_px, 11, room.get("area_color", Color.WHITE), rotated)


## Huella del balcon en planta: losa translucida y el antepecho por los tres
## lados libres. El cuarto lado es la fachada y ahi no hay antepecho.
static func balcony(canvas: CanvasItem, corners_px: PackedVector2Array, color: Color) -> void:
	if corners_px.size() != 4:
		return
	canvas.draw_colored_polygon(corners_px, Color(color.r, color.g, color.b, 0.20))
	canvas.draw_polyline(
		PackedVector2Array([corners_px[0], corners_px[3], corners_px[2], corners_px[1]]),
		Color(color.r, color.g, color.b, 0.90),
		2.0
	)


static func openings(canvas: CanvasItem, openings_view: Array) -> void:
	for entry in openings_view:
		var opening: Dictionary = entry
		if bool(opening.get("vertical", false)):
			vertical_opening(canvas, opening.get("rect_px", Rect2()), opening.get("color", Color.WHITE))
			continue
		# El balcon va DEBAJO de la linea del hueco: es el suelo que cuelga por
		# fuera, no una pieza mas del paramento.
		if opening.has("balcony_px"):
			balcony(canvas, opening["balcony_px"], opening.get("color", Color.WHITE))
		var a_px: Vector2 = opening.get("a_px", Vector2.ZERO)
		var b_px: Vector2 = opening.get("b_px", Vector2.ZERO)
		canvas.draw_line(a_px, b_px, Color(0.04, 0.06, 0.07, 0.95), 8.0)
		canvas.draw_line(a_px, b_px, opening.get("color", Color.WHITE), 4.0)
		if opening.has("swing"):
			var swing: Dictionary = opening["swing"]
			door_swing_preview(canvas, swing.get("hinge_px", Vector2.ZERO), swing.get("open_end_px", Vector2.ZERO), opening.get("color", Color.WHITE))


## Los muebles, en planta y ya girados. El foco de ignicion lleva su punto.
static func objects(canvas: CanvasItem, objects_view: Array, font: Font, scale_inv: float) -> void:
	for entry in objects_view:
		var obj: Dictionary = entry
		var corners_px: PackedVector2Array = obj.get("corners_px", PackedVector2Array())
		if corners_px.size() != 4:
			continue
		canvas.draw_colored_polygon(corners_px, obj.get("fill", Color.WHITE))
		canvas.draw_polyline(
			PackedVector2Array([corners_px[0], corners_px[1], corners_px[2], corners_px[3], corners_px[0]]),
			Color(0.18, 0.09, 0.04, 0.92),
			1.5
		)
		var center_px: Vector2 = obj.get("center_px", Vector2.ZERO)
		if bool(obj.get("ignition", false)):
			canvas.draw_circle(center_px, 7.0, obj.get("ignition_color", Color.WHITE))
			canvas.draw_circle(center_px, 3.5, Color(1.0, 0.94, 0.25, 0.98))
		if obj.has("handles"):
			handles(canvas, obj["handles"])
		if obj.has("label"):
			screen_string(canvas, font, scale_inv, obj.get("label_anchor_px", center_px), Vector2(4.0, 12.0),
				String(obj["label"]), float(obj.get("label_width_px", 16.0)), 10, obj.get("label_color", Color.BLACK))


static func player_start(canvas: CanvasItem, start_view: Dictionary) -> void:
	if start_view.is_empty():
		return
	player_start_icon(
		canvas,
		start_view.get("px", Vector2.ZERO),
		start_view.get("dir", Vector2.UP),
		float(start_view.get("radius", 9.0)),
		start_view.get("color", Color.WHITE)
	)


static func detectors(canvas: CanvasItem, detectors_view: Array) -> void:
	for entry in detectors_view:
		var det: Dictionary = entry
		detector_icon(
			canvas,
			det.get("px", Vector2.ZERO),
			float(det.get("radius", 8.0)),
			det.get("color", Color.WHITE),
			String(det.get("label", "")),
			bool(det.get("selected", false))
		)


static func victims(canvas: CanvasItem, victims_view: Array) -> void:
	for entry in victims_view:
		var vic: Dictionary = entry
		victim_icon(
			canvas,
			vic.get("px", Vector2.ZERO),
			float(vic.get("radius", 7.0)),
			vic.get("color", Color.WHITE),
			bool(vic.get("selected", false))
		)


static func handles(canvas: CanvasItem, handles_view: Dictionary) -> void:
	selection_handles(
		canvas,
		handles_view.get("center_px", Vector2.ZERO),
		handles_view.get("rotate_px", Vector2.ZERO),
		handles_view.get("resize_pxs", PackedVector2Array()),
		float(handles_view.get("radius_px", 6.5))
	)


## Un cartel que no crece ni encoge con el zoom: se dibuja en coordenadas de
## pantalla, anclado a un punto del plano.
## Una linea de la ficha de la sala. `centered` la centra sobre el ancla en vez
## de arrancar en ella, que es lo que hace falta cuando el ancla es el centro
## de la sala y no su esquina.
static func room_label_line(
	canvas: CanvasItem,
	font: Font,
	scale_inv: float,
	anchor_px: Vector2,
	y_offset_px: float,
	text: String,
	max_width_px: float,
	font_size: int,
	color: Color,
	centered: bool
) -> void:
	if font == null or text == "":
		return
	var x_offset_px: float = 8.0
	if centered:
		x_offset_px = -font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, max_width_px, font_size).x * 0.5
	screen_string(canvas, font, scale_inv, anchor_px, Vector2(x_offset_px, y_offset_px), text, max_width_px, font_size, color)


static func screen_string(canvas: CanvasItem, font: Font, scale_inv: float, anchor_px: Vector2, offset_px: Vector2, text: String, max_width_px: float, font_size: int, color: Color) -> void:
	if font == null or text == "":
		return
	canvas.draw_set_transform(anchor_px, 0.0, Vector2(scale_inv, scale_inv))
	canvas.draw_string(font, offset_px, text, HORIZONTAL_ALIGNMENT_LEFT, max_width_px, font_size, color)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

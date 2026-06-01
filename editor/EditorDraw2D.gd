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
	if ThemeDB.fallback_font == null:
		return
	var label_color: Color = Color(0.72, 1.0, 0.94, 0.96) if not is_stairs else Color(1.0, 0.84, 0.34, 0.96)
	var long_m: float = maxf(rect_m.size.x, rect_m.size.y)
	var wide_m: float = minf(rect_m.size.x, rect_m.size.y)
	var long_label: String = "Largo %.2f m" % long_m
	var wide_label: String = "Ancho %.2f m" % wide_m
	var top_pos: Vector2 = rect_px.position + Vector2(4.0, -6.0)
	canvas.draw_string(
		ThemeDB.fallback_font,
		top_pos,
		long_label,
		HORIZONTAL_ALIGNMENT_LEFT,
		180.0,
		11,
		label_color
	)
	var side_pos: Vector2 = Vector2(rect_px.position.x + rect_px.size.x + 8.0, rect_px.position.y + minf(18.0, rect_px.size.y * 0.5))
	canvas.draw_string(
		ThemeDB.fallback_font,
		side_pos,
		wide_label,
		HORIZONTAL_ALIGNMENT_LEFT,
		160.0,
		11,
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
		canvas.draw_string(ThemeDB.fallback_font, a0 + Vector2(5.0, -5.0), "ENTRA", HORIZONTAL_ALIGNMENT_LEFT, 70.0, 9, Color(0.95, 1.0, 0.82, 0.82))
		canvas.draw_string(ThemeDB.fallback_font, end_center + Vector2(5.0, -5.0), "180", HORIZONTAL_ALIGNMENT_LEFT, 42.0, 9, Color(1.0, 0.90, 0.35, 0.86))


## Draw the player-start arrow icon at pixel position px.
## dir = normalized direction vector (world); radius = triangle half-size in pixels.
static func player_start_icon(canvas: CanvasItem, px: Vector2, dir: Vector2, radius: float, color: Color) -> void:
	var pts := PackedVector2Array([
		px + dir * (radius + 4.0),
		px + dir.rotated(2.35) * radius,
		px + dir.rotated(-2.35) * radius
	])
	canvas.draw_colored_polygon(pts, color)
	canvas.draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[0]]), Color(0.0, 0.0, 0.0, 0.78), 1.6)
	if ThemeDB.fallback_font != null:
		canvas.draw_string(ThemeDB.fallback_font, px + Vector2(11.0, 4.0), "FP", HORIZONTAL_ALIGNMENT_LEFT, 32.0, 10, color)


## Draw a detector circle icon at pixel position px.
## label = single character identifier ("S", "H", or "C").
static func detector_icon(canvas: CanvasItem, px: Vector2, radius: float, color: Color, label: String, selected: bool) -> void:
	canvas.draw_circle(px, radius + 2.0, Color(0.0, 0.0, 0.0, 0.7))
	canvas.draw_circle(px, radius, color)
	if selected:
		canvas.draw_circle(px, radius + 2.0, Color(1.0, 1.0, 1.0, 0.85), false, 2.0)
	if ThemeDB.fallback_font != null:
		canvas.draw_string(ThemeDB.fallback_font, px + Vector2(-4.0, 5.0), label, HORIZONTAL_ALIGNMENT_LEFT, 20.0, 11, Color(0.0, 0.0, 0.0, 0.92))


## Draw a victim diamond icon at pixel position px.
static func victim_icon(canvas: CanvasItem, px: Vector2, r: float, color: Color, selected: bool) -> void:
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
		canvas.draw_string(ThemeDB.fallback_font, px + Vector2(-4.0, 5.0), "V", HORIZONTAL_ALIGNMENT_LEFT, 16.0, 10, Color(0.0, 0.0, 0.0, 0.92))


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
static func exterior_wall(canvas: CanvasItem, a_px: Vector2, b_px: Vector2, color: Color, thickness_px: float, selected: bool) -> void:
	canvas.draw_line(a_px, b_px, Color(0.0, 0.0, 0.0, 0.76), thickness_px + 2.0)
	canvas.draw_line(a_px, b_px, color, thickness_px)
	if selected:
		canvas.draw_circle(a_px, 5.0, color)
		canvas.draw_circle(b_px, 5.0, color)

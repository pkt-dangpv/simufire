extends Control
class_name Minimap2D

const OpeningGeometry2D := preload("res://view/2d/openings/OpeningGeometry2D.gd")
const FurnitureVisualLayout := preload("res://view/furniture/FurnitureVisualLayout.gd")

@export var panel_color: Color = Color(0.01, 0.025, 0.03, 0.78)
@export var border_color: Color = Color(0.95, 0.58, 0.22, 0.70)
@export var room_fill: Color = Color(0.045, 0.095, 0.105, 0.86)
@export var room_outline: Color = Color(0.82, 0.91, 0.91, 0.94)
@export var smoke_color: Color = Color(0.36, 0.40, 0.40, 0.38)
@export var fire_color: Color = Color(1.0, 0.28, 0.04, 0.82)
@export var door_color: Color = Color(0.55, 1.0, 0.36, 0.95)
@export var window_color: Color = Color(0.00, 0.70, 0.88, 0.95)
@export var hole_color: Color = Color(1.0, 0.78, 0.0, 0.95)
@export var player_color: Color = Color(0.58, 0.88, 1.0, 0.98)
@export var live_player_color: Color = Color(0.30, 1.0, 0.64, 1.0)
## El atrezo no es carga de fuego: en el minimapa va en gris.
@export var decor_fill_color: Color = Color(0.62, 0.64, 0.66, 0.26)
@export var decor_outline_color: Color = Color(0.78, 0.82, 0.84, 0.44)

@export_group("Posicion")
## Margen respecto a la esquina de anclaje.
@export var margin_px: Vector2 = Vector2(14.0, 14.0)
## Tamano del minimapa en pantalla.
@export var map_size_px: Vector2 = Vector2(228.0, 160.0)
## En FP el minimapa pasa a arriba-derecha (el HUD FP ocupa arriba-izquierda).
@export var fp_top_right: bool = true

var building: BuildingModel = null
var state: Dictionary = {}
var selected_floor_level_m: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()


func bind_building(next_building: BuildingModel) -> void:
	building = next_building
	selected_floor_level_m = _initial_floor_level()
	queue_redraw()


## Recoloca el minimapa segun el modo de vista: arriba-izquierda en 3D,
## arriba-derecha en FP (configurable con los exports de Posicion).
func set_fp_mode(fp_enabled: bool) -> void:
	if fp_enabled and fp_top_right:
		set_anchors_preset(Control.PRESET_TOP_RIGHT)
		offset_left = -(margin_px.x + map_size_px.x)
		offset_top = margin_px.y
		offset_right = -margin_px.x
		offset_bottom = margin_px.y + map_size_px.y
	else:
		set_anchors_preset(Control.PRESET_TOP_LEFT)
		offset_left = margin_px.x
		offset_top = margin_px.y
		offset_right = margin_px.x + map_size_px.x
		offset_bottom = margin_px.y + map_size_px.y


func set_state(next_state: Dictionary) -> void:
	state = next_state
	_update_floor_from_player_start()
	queue_redraw()


func _draw() -> void:
	var bounds := Rect2(Vector2.ZERO, size)
	draw_rect(bounds, panel_color, true)
	draw_rect(bounds, border_color, false, 1.0)
	if building == null:
		return

	var rects: Dictionary = building.get_room_rects_m()
	if rects.is_empty():
		return
	var floor_ids: Array[int] = _room_ids_on_selected_floor(rects)
	if floor_ids.is_empty():
		return

	var plan_bounds: Rect2 = _bounds_for_room_ids(rects, floor_ids)
	var tf: Dictionary = _draw_transform(plan_bounds)
	for room_id in floor_ids:
		var room_rect: Rect2 = Rect2(rects[room_id])
		var rpx: Rect2 = _rect_to_px(room_rect, tf)
		draw_rect(rpx, room_fill, true)
		var room_state: Dictionary = state.get(str(room_id), {})
		var smoke_kg: float = float(room_state.get("smoke_kg", 0.0))
		if smoke_kg > 0.01:
			var alpha: float = clampf(0.16 + log(smoke_kg + 1.0) * 0.12, 0.16, 0.62)
			draw_rect(rpx.grow(-2.0), Color(smoke_color.r, smoke_color.g, smoke_color.b, alpha), true)
		if float(room_state.get("hrr_kw", 0.0)) > 1.0:
			draw_circle(rpx.get_center(), clampf(minf(rpx.size.x, rpx.size.y) * 0.18, 4.0, 14.0), fire_color)
		_draw_fuel_objects(room_id, room_rect, tf)
		draw_rect(rpx, room_outline, false, 1.1)

	_draw_openings(rects, tf)
	_draw_safety_markers(rects, tf)
	_draw_player_start(rects, tf)
	_draw_live_player(rects, tf)
	_draw_floor_badge()


func _draw_openings(rects: Dictionary, tf: Dictionary) -> void:
	for index in range(building.get_opening_count()):
		var op: OpeningModel = building.get_opening_at(index)
		if op == null or op.is_vertical:
			continue
		if not rects.has(op.a) or not _room_is_on_selected_floor(op.a):
			continue
		var ra: Rect2 = Rect2(rects[op.a])
		var rb: Rect2 = Rect2(rects[op.b]) if rects.has(op.b) else Rect2()
		var seg_m: PackedVector2Array = OpeningGeometry2D.shared_edge_segment_m(ra, rb) if rects.has(op.b) else OpeningGeometry2D.default_exterior_segment_m(ra, op.width_m, op.wall_side, op.offset_m, op.offset_is_fraction)
		if seg_m.size() != 2:
			continue
		var color: Color = door_color
		if op.type == OpeningModel.Type.WINDOW:
			color = window_color
			if op.glass_broken:
				color = Color(1.0, 0.72, 0.12, 1.0)
		elif op.type == OpeningModel.Type.HOLE:
			color = hole_color
		var p1: Vector2 = _point_to_px(seg_m[0], tf)
		var p2: Vector2 = _point_to_px(seg_m[1], tf)
		var width: float = 3.0 if op.type == OpeningModel.Type.WINDOW else 2.2
		draw_line(p1, p2, color, width)
		if op.type == OpeningModel.Type.WINDOW:
			var dir: Vector2 = (p2 - p1).normalized() if p1.distance_to(p2) > 0.01 else Vector2(1.0, 0.0)
			var normal := Vector2(-dir.y, dir.x)
			draw_line(p1 + normal * 2.0, p2 + normal * 2.0, Color(color.r, color.g, color.b, 0.56), 0.9)
			draw_line(p1 - normal * 2.0, p2 - normal * 2.0, Color(color.r, color.g, color.b, 0.56), 0.9)
			if op.glass_broken:
				var mid: Vector2 = (p1 + p2) * 0.5
				var crack_half: float = minf(6.0, maxf(3.0, p1.distance_to(p2) * 0.18))
				draw_line(mid - dir * crack_half - normal * 2.5, mid + dir * crack_half + normal * 2.5, Color(1.0, 0.95, 0.70, 0.90), 0.9)
				draw_line(mid - dir * crack_half + normal * 2.5, mid + dir * crack_half - normal * 2.5, Color(1.0, 0.95, 0.70, 0.90), 0.9)


func _draw_player_start(rects: Dictionary, tf: Dictionary) -> void:
	if building.player_start.is_empty():
		return
	var room_id: int = int(building.player_start.get("room_id", -1))
	if not rects.has(room_id) or not _room_is_on_selected_floor(room_id):
		return
	var rect: Rect2 = Rect2(rects[room_id])
	var local_pos: Vector2 = Vector2(building.player_start.get("position_m", rect.size * 0.5))
	var pos: Vector2 = rect.position + local_pos
	var px: Vector2 = _point_to_px(pos, tf)
	draw_circle(px, 4.5, player_color)
	draw_circle(px, 6.5, player_color, false, 1.4)


func _draw_live_player(rects: Dictionary, tf: Dictionary) -> void:
	var marker: Dictionary = Dictionary(state.get("fp_player", {})) if typeof(state.get("fp_player", {})) == TYPE_DICTIONARY else {}
	if marker.is_empty() or not bool(marker.get("active", false)):
		return
	var floor_level_m: float = float(marker.get("floor_level_z_m", selected_floor_level_m))
	if absf(floor_level_m - selected_floor_level_m) >= 0.05:
		return
	var pos: Vector2 = Vector2(marker.get("position_m", Vector2.ZERO))
	var room_id: int = int(marker.get("room_id", -1))
	if room_id >= 0 and (not rects.has(room_id) or not _room_is_on_selected_floor(room_id)):
		return
	var px: Vector2 = _point_to_px(pos, tf)
	var dir := Vector2(0.0, -1.0).rotated(-deg_to_rad(float(marker.get("yaw_deg", 0.0))))
	var radius: float = 7.0
	var pts := PackedVector2Array([
		px + dir * (radius + 3.0),
		px + dir.rotated(2.35) * radius,
		px + dir.rotated(-2.35) * radius
	])
	draw_circle(px, radius + 4.0, Color(live_player_color.r, live_player_color.g, live_player_color.b, 0.18), true)
	draw_colored_polygon(pts, live_player_color)
	draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[0]]), Color(0.0, 0.0, 0.0, 0.84), 1.4)


func _draw_fuel_objects(room_id: int, room_rect: Rect2, tf: Dictionary) -> void:
	var room: RoomModel = building.get_room(room_id) if building != null else null
	if room == null:
		return
	var is_bathroom: bool = _is_bathroom_room(room)
	var raw_objects: Array = []
	for obj in room.fuel_objects:
		if obj == null:
			continue
		raw_objects.append({
			"id": obj.id,
			"name": obj.name,
			"kind": obj.kind,
			"position_m": obj.position_m,
			"size_m": obj.size_m,
			"rotation_deg": obj.rotation_deg,
			"visual_pose_locked": obj.visual_pose_locked,
		})
	# El mismo reparto que las demas vistas: un minimapa que coloque los muebles
	# por su cuenta miente sobre lo que hay al otro lado de la puerta.
	for visual_obj in FurnitureVisualLayout.normalize_room(building, room_id, room_rect, raw_objects):
		var pos_m: Vector2 = Vector2(visual_obj.get("position_m", Vector2.ZERO))
		var size_m: Vector2 = Vector2(visual_obj.get("size_m", Vector2.ONE))
		var rotation_deg: float = float(visual_obj.get("rotation_deg", 0.0))
		var pose: Dictionary = _furniture_pose_mini(room_rect, pos_m, size_m, rotation_deg)
		var center_m: Vector2 = Vector2(pose.get("center_m", room_rect.position + pos_m + size_m * 0.5))
		var visual_size_m: Vector2 = Vector2(pose.get("size_m", size_m))
		var rot := Transform2D(deg_to_rad(rotation_deg), Vector2.ZERO)
		var half: Vector2 = visual_size_m * 0.5
		var points := PackedVector2Array([
			_point_to_px(center_m + rot * Vector2(-half.x, -half.y), tf),
			_point_to_px(center_m + rot * Vector2(half.x, -half.y), tf),
			_point_to_px(center_m + rot * Vector2(half.x, half.y), tf),
			_point_to_px(center_m + rot * Vector2(-half.x, half.y), tf)
		])
		var decor: bool = bool(visual_obj.get("visual_only", false))
		draw_colored_polygon(points, decor_fill_color if decor else Color(0.92, 0.34, 0.08, 0.34))
		draw_polyline(
			PackedVector2Array([points[0], points[1], points[2], points[3], points[0]]),
			decor_outline_color if decor else Color(1.0, 0.62, 0.22, 0.58),
			0.8
		)
	if is_bathroom:
		_draw_bathroom_fixtures(room_rect, tf)


func _furniture_pose_mini(room_rect: Rect2, local_pos: Vector2, size_m: Vector2, rotation_deg: float) -> Dictionary:
	var margin: float = 0.025
	var available := Vector2(maxf(0.08, room_rect.size.x - margin * 2.0), maxf(0.08, room_rect.size.y - margin * 2.0))
	var visual_size := Vector2(clampf(absf(size_m.x), 0.05, available.x), clampf(absf(size_m.y), 0.05, available.y))
	var angle: float = deg_to_rad(rotation_deg)
	var c: float = absf(cos(angle))
	var s: float = absf(sin(angle))
	var bbox_size := Vector2(c * visual_size.x + s * visual_size.y, s * visual_size.x + c * visual_size.y)
	if bbox_size.x > available.x or bbox_size.y > available.y:
		var scale_down: float = minf(available.x / maxf(0.001, bbox_size.x), available.y / maxf(0.001, bbox_size.y))
		visual_size *= clampf(scale_down, 0.10, 1.0)
		bbox_size = Vector2(c * visual_size.x + s * visual_size.y, s * visual_size.x + c * visual_size.y)
	var desired_center: Vector2 = room_rect.position + local_pos + visual_size * 0.5
	var min_center: Vector2 = room_rect.position + Vector2(margin, margin) + bbox_size * 0.5
	var max_center: Vector2 = room_rect.position + room_rect.size - Vector2(margin, margin) - bbox_size * 0.5
	return {
		"center_m": Vector2(clampf(desired_center.x, min_center.x, max_center.x), clampf(desired_center.y, min_center.y, max_center.y)),
		"size_m": visual_size,
	}


func _is_bathroom_room(room: RoomModel) -> bool:
	if room == null:
		return false
	var tokens: String = ("%s %s" % [room.kind, room.name]).to_lower()
	return tokens.contains("bano") or tokens.contains("baño") or tokens.contains("bath")


func _draw_bathroom_fixtures(room_rect: Rect2, tf: Dictionary) -> void:
	var w: float = room_rect.size.x
	var d: float = room_rect.size.y
	var fixture_color := Color(0.78, 0.88, 0.90, 0.46)
	var outline := Color(0.92, 0.98, 1.0, 0.64)
	for r in [
		Rect2(room_rect.position + Vector2(0.18, 0.18), Vector2(minf(1.00, maxf(0.55, w * 0.30)), minf(0.85, maxf(0.55, d * 0.40)))),
		Rect2(room_rect.position + Vector2(0.24, maxf(0.18, d - 0.92)), Vector2(0.56, 0.68)),
		Rect2(room_rect.position + Vector2(maxf(0.18, w - 1.05), maxf(0.18, d - 0.78)), Vector2(0.74, 0.46)),
	]:
		var px := _rect_to_px(r, tf)
		draw_rect(px, fixture_color, true)
		draw_rect(px, outline, false, 0.7)


func _draw_safety_markers(rects: Dictionary, tf: Dictionary) -> void:
	for det in building.detectors:
		if typeof(det) != TYPE_DICTIONARY:
			continue
		var room_id: int = int(Dictionary(det).get("room_id", -1))
		if not rects.has(room_id) or not _room_is_on_selected_floor(room_id):
			continue
		var rect: Rect2 = Rect2(rects[room_id])
		var pos: Vector2 = rect.position + Vector2(float(Dictionary(det).get("x_m", 0.0)), float(Dictionary(det).get("y_m", 0.0)))
		draw_circle(_point_to_px(pos, tf), 3.2, Color(0.35, 0.76, 1.0, 0.95))
	for vic in building.victims:
		if typeof(vic) != TYPE_DICTIONARY:
			continue
		var room_id: int = int(Dictionary(vic).get("room_id", -1))
		if not rects.has(room_id) or not _room_is_on_selected_floor(room_id):
			continue
		var rect: Rect2 = Rect2(rects[room_id])
		var pos: Vector2 = rect.position + Vector2(float(Dictionary(vic).get("x_m", 0.0)), float(Dictionary(vic).get("y_m", 0.0)))
		draw_circle(_point_to_px(pos, tf), 3.4, Color(0.95, 0.86, 0.48, 0.95))


func _draw_floor_badge() -> void:
	var text: String = _floor_label_for_level(selected_floor_level_m)
	if building != null and String(building.building_type).to_lower() == "apartment":
		text += "  P%d" % building.apartment_floor_number
	if ThemeDB.fallback_font != null:
		draw_string(ThemeDB.fallback_font, Vector2(8.0, 16.0), text, HORIZONTAL_ALIGNMENT_LEFT, maxf(40.0, size.x - 16.0), 11, Color(0.92, 0.96, 0.94, 0.92))


func _draw_transform(plan_bounds: Rect2) -> Dictionary:
	var pad := Vector2(10.0, 22.0)
	var usable := Vector2(maxf(10.0, size.x - pad.x * 2.0), maxf(10.0, size.y - pad.y - 10.0))
	var scale: float = minf(usable.x / maxf(0.01, plan_bounds.size.x), usable.y / maxf(0.01, plan_bounds.size.y))
	var offset: Vector2 = Vector2(
		pad.x + (usable.x - plan_bounds.size.x * scale) * 0.5,
		pad.y + (usable.y - plan_bounds.size.y * scale) * 0.5
	) - plan_bounds.position * scale
	return {"scale": scale, "offset": offset}


func _rect_to_px(rect: Rect2, tf: Dictionary) -> Rect2:
	var scale: float = float(tf.get("scale", 1.0))
	var offset: Vector2 = Vector2(tf.get("offset", Vector2.ZERO))
	return Rect2(rect.position * scale + offset, rect.size * scale)


func _point_to_px(point: Vector2, tf: Dictionary) -> Vector2:
	return point * float(tf.get("scale", 1.0)) + Vector2(tf.get("offset", Vector2.ZERO))


func _room_ids_on_selected_floor(rects: Dictionary) -> Array[int]:
	var ids: Array[int] = []
	for key in rects.keys():
		var room_id: int = int(key)
		if _room_is_on_selected_floor(room_id):
			ids.append(room_id)
	ids.sort()
	return ids


func _bounds_for_room_ids(rects: Dictionary, ids: Array[int]) -> Rect2:
	var first: bool = true
	var result := Rect2()
	for room_id in ids:
		var rect: Rect2 = Rect2(rects[room_id])
		if first:
			result = rect
			first = false
		else:
			result = result.merge(rect)
	return result


func _room_is_on_selected_floor(room_id: int) -> bool:
	var room: RoomModel = building.get_room(room_id) if building != null else null
	return room != null and absf(room.floor_level_z_m - selected_floor_level_m) < 0.05


func _initial_floor_level() -> float:
	if building == null:
		return 0.0
	var best: float = INF
	for room_id in building.get_rooms().keys():
		var room: RoomModel = building.get_room(int(room_id))
		if room != null:
			best = minf(best, room.floor_level_z_m)
	return 0.0 if is_inf(best) else best


func _update_floor_from_player_start() -> void:
	var marker: Dictionary = Dictionary(state.get("fp_player", {})) if typeof(state.get("fp_player", {})) == TYPE_DICTIONARY else {}
	if not marker.is_empty() and bool(marker.get("active", false)):
		selected_floor_level_m = float(marker.get("floor_level_z_m", selected_floor_level_m))
		return
	if building == null or building.player_start.is_empty():
		return
	selected_floor_level_m = float(building.player_start.get("floor_level_z_m", selected_floor_level_m))


func _floor_label_for_level(level_m: float) -> String:
	if absf(level_m) < 0.05:
		return "PB"
	return "P%d" % int(round(level_m / 2.9))

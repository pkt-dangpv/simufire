extends Node2D
class_name Visualizer

const OpeningGeometry2D := preload("res://view/2d/openings/OpeningGeometry2D.gd")
const FloorPlan2D := preload("res://view/2d/floors/FloorPlan2D.gd")
const RoomLabelLayout2D := preload("res://view/2d/rooms/RoomLabelLayout2D.gd")
const RoomStateVisuals2D := preload("res://view/2d/rooms/RoomStateVisuals2D.gd")

## ============================================================
## VISUALIZER
## ------------------------------------------------------------
## Responsabilidad:
## - Dibujar habitaciones a partir de rects del BuildingModel
## - Representar la atmosfera de cada sala en planta
## - Mostrar una mini-seccion lateral con la estratificacion real
## - Dibujar puertas/ventanas, barra HRR y etiquetas
##
## Este nodo NO calcula simulacion.
## Solo representa el estado que recibe desde Main / SimulationEngine.
## ============================================================


# ============================================================
# AJUSTES GENERALES
# ============================================================

@export var meters_to_px: float = 100.0
@export var wall_thickness: float = 2.0
@export var room_height_m_default: float = 2.4

@export var background_color: Color = Color(0.00, 0.01, 0.01, 1.0)
@export var room_outline_color: Color = Color(0.82, 0.87, 0.88, 1.0)
@export var room_fill_color: Color = Color(0.05, 0.07, 0.08, 0.48)

@export var auto_fit_to_view: bool = true
@export var view_margin_px: float = 20.0
# Espacio reservado para el panel de UI (HUD) en cada borde
@export var ui_reserved_right_px: float = 400.0
@export var ui_reserved_left_px: float = 0.0
@export var ui_reserved_top_px: float = 0.0
@export var ui_reserved_bottom_px: float = 0.0

# ============================================================
# TOGGLES DE DIBUJO
# ============================================================

@export var show_room_fill: bool = true
@export var show_plan_atmosphere_overlay: bool = true
@export var show_fire_overlay: bool = false
@export var show_section_gauge: bool = true
@export var show_flashover_highlight: bool = true
@export var show_smoke_layer: bool = true
@export var show_smoke_layer_line: bool = true
@export var show_hot_layer_overlay: bool = true
@export var show_150c_layer: bool = true
@export var show_hrr_bar: bool = true
@export var show_openings: bool = true
@export var show_room_labels: bool = true
@export var show_room_name: bool = true
@export var show_opening_labels: bool = false
@export var show_fuel_objects: bool = true
@export var show_fuel_object_names: bool = true
@export var show_detector_markers: bool = true
@export var show_victim_markers: bool = true
@export var show_floor_selector: bool = true
@export var floor_selector_position_px: Vector2 = Vector2(18.0, 18.0)
@export var floor_selector_button_size_px: Vector2 = Vector2(88.0, 26.0)
@export var floor_selector_gap_px: float = 6.0
@export var floor_selector_active_color: Color = Color(1.0, 0.56, 0.18, 0.92)
@export var floor_selector_inactive_color: Color = Color(0.08, 0.12, 0.14, 0.84)
@export var floor_selector_text_color: Color = Color(1.0, 0.96, 0.86, 0.98)

# ============================================================
# HUMO / CALOR / FUEGO
# ============================================================

@export var smoke_base_color: Color = Color(0.33, 0.38, 0.40, 1.0)
@export var smoke_min_alpha: float = 0.30
@export var smoke_max_alpha_bonus: float = 0.55
@export var smoke_mass_reference_kg: float = 8.0
@export var smoke_concentration_reference_kg_m3: float = 0.08
@export var smoke_visible_threshold_kg: float = 0.01
@export var smoke_layer_line_color: Color = Color(0.00, 0.70, 0.88, 0.95)
@export var smoke_layer_line_width: float = 2.0
@export var hot_layer_color: Color = Color(1.0, 0.25, 0.00, 0.18)
@export var layer_150c_color: Color = Color(1.0, 0.12, 0.04, 0.95)
@export var layer_150c_line_width: float = 2.0
@export var heat_room_tint_color: Color = Color(1.0, 0.42, 0.10, 1.0)
@export var fire_glow_color: Color = Color(1.0, 0.40, 0.10, 1.0)
@export var fire_core_color: Color = Color(1.0, 0.82, 0.35, 1.0)
@export var detector_marker_color: Color = Color(0.35, 0.76, 1.0, 1.0)
@export var detector_triggered_color: Color = Color(1.0, 0.38, 0.16, 1.0)
@export var victim_marker_color: Color = Color(0.95, 0.86, 0.48, 1.0)
@export var victim_incapacitated_color: Color = Color(0.58, 0.58, 0.62, 1.0)
@export var flashover_fill_color: Color = Color(1.0, 0.20, 0.05, 0.24)
@export var flashover_outline_color: Color = Color(1.0, 0.45, 0.05, 1.0)
@export var flashover_indicator_duration_s: float = 22.0
## Si es true, el aviso de flashover permanece visible mientras flashover_triggered sea true (ignorando la duración).
@export var flashover_indicator_permanent: bool = true
@export var active_fire_outline_color: Color = Color(1.0, 0.62, 0.14, 1.0)
@export var low_o2_outline_color: Color = Color(0.30, 0.68, 1.0, 1.0)

@export var fuel_object_fill_color: Color = Color(1.00, 0.30, 0.00, 0.76)
@export var fuel_object_outline_color: Color = Color(0.00, 0.01, 0.01, 0.95)
@export var fuel_object_label_color: Color = Color(1.0, 0.96, 0.86, 0.96)

# ============================================================
# MINI-SECCION
# ============================================================

@export var section_gauge_bg_color: Color = Color(0.0, 0.0, 0.0, 0.35)
@export var section_gauge_outline_color: Color = Color(1.0, 1.0, 1.0, 0.30)
@export var section_gauge_margin_px: float = 4.0
@export var section_gauge_width_px: float = 16.0
@export var section_gauge_min_height_px: float = 34.0

# ============================================================
# ETIQUETAS
# ============================================================

@export var room_label_font_size: int = 10
@export var room_label_color: Color = Color(1.0, 1.0, 1.0, 0.95)
## Cuando es false, solo se muestra el nombre/ID de la habitación (sin datos de simulación).
@export var show_room_data_in_label: bool = true
@export var room_label_shadow: bool = true
@export var room_label_bg: bool = false
@export var room_label_bg_color: Color = Color(0.0, 0.0, 0.0, 0.40)
@export var room_label_padding: float = 4.0
@export var room_label_offset: Vector2 = Vector2(4.0, 11.0)
@export var room_label_line_h: float = 11.0
@export var room_label_tiny_threshold_w_px: float = 60.0
@export var room_label_tiny_threshold_h_px: float = 40.0
@export var room_label_compact_threshold_w_px: float = 85.0
@export var room_label_compact_threshold_h_px: float = 72.0
@export var room_label_medium_threshold_w_px: float = 135.0
@export var room_label_medium_threshold_h_px: float = 120.0

# ============================================================
# MARCA DE AGUA (nombre de sala)
# ============================================================

## Muestra el nombre de la sala como texto grande y semitransparente centrado en el plano.
@export var show_room_name_watermark: bool = true
## Tamaño de fuente. 0 = automático (escala con el tamaño de la sala).
@export var room_watermark_font_size: int = 0
## Color/alpha del texto marca de agua. Alpha bajo para transparencia.
@export var room_watermark_color: Color = Color(0.90, 0.94, 0.96, 0.12)
## Tamaño mínimo de la sala (px) para mostrar la marca de agua.
@export var room_watermark_min_room_px: float = 40.0

# ============================================================
# BARRA HRR
# ============================================================

@export var hrr_bar_height_px: float = 4.0
@export var hrr_bar_margin_px: float = 3.0
@export var hrr_bar_max_kw: float = 3000.0
@export var hrr_bar_color: Color = Color(1.0, 0.25, 0.00, 0.92)
@export var hrr_bar_bg_color: Color = Color(0.00, 0.70, 0.88, 0.20)

# ============================================================
# OPENINGS
# ============================================================

@export var door_color: Color = Color(0.55, 1.00, 0.36, 1.0)
@export var window_color: Color = Color(0.00, 0.70, 0.88, 1.0)
@export var hole_color: Color = Color(1.00, 0.78, 0.00, 1.0)
@export var window_broken_color: Color = Color(1.00, 0.78, 0.00, 1.0)
@export var window_open_color: Color = Color(1.00, 0.25, 0.00, 1.0)
@export var opening_line_width: float = 4.0

# ============================================================
# BADGE DE VENTANA
# ============================================================

@export var show_window_badge: bool = true
@export var window_full_open_threshold: float = 0.5
@export var window_badge_size: Vector2 = Vector2(16.0, 7.0)

# ============================================================
# SELECCION DE SALA
# ============================================================

@export var selected_room_outline_color: Color = Color(1.0, 0.88, 0.18, 1.0)
@export var selected_room_outline_width: float = 3.5

# ============================================================
# ESTADO Y GEOMETRIA
# ============================================================

signal room_clicked(room_id: int)
signal opening_clicked(opening_index: int, screen_pos: Vector2)

var state: Dictionary = {}
var rects_m: Dictionary[int, Rect2] = {}
var selected_room_id: int = -1
var selected_opening_index: int = -1
var floor_levels_m: Array[float] = []
var selected_floor_index: int = 0

@export var building_path: NodePath
var building: BuildingModel = null


# ============================================================
# READY
# ============================================================

func _ready() -> void:
	_sync_building_geometry()
	queue_redraw()


# ============================================================
# API PUBLICA
# ============================================================

func set_state(s: Dictionary) -> void:
	state = s
	_sync_building_geometry()
	queue_redraw()


# ============================================================
# DRAW
# ============================================================

func _draw() -> void:
	_sync_building_geometry()
	_draw_background()

	var room_ids: Array[int] = _get_sorted_room_ids()
	for id in room_ids:
		if not _is_room_visible_on_selected_floor(id):
			continue
		var rm: Rect2 = rects_m[id]
		var rpx: Rect2 = _to_px(rm)

		if show_room_fill:
			draw_rect(rpx, room_fill_color, true)

		var rs: Dictionary = state.get(str(id), {})
		if rs.is_empty():
			draw_rect(rpx, room_outline_color, false, wall_thickness)
			continue

		var room_height_m: float = float(rs.get("height_m", room_height_m_default))
		var room_floor_area_m2: float = maxf(0.01, rm.size.x * rm.size.y)
		var smoke_layer_m: float = float(rs.get("smoke_display_layer_m", rs.get("smoke_layer_m", rs.get("h_layer_m", room_height_m))))
		var hot_layer_m: float = float(rs.get("hot_layer_m", rs.get("thermal_layer_m", room_height_m)))
		var layer_150c_m: float = float(rs.get("layer_150c_m", room_height_m))
		var smoke_kg: float = float(rs.get("smoke_kg", 0.0))
		var hrr_kw: float = float(rs.get("hrr_kw", 0.0))
		var content_rect: Rect2 = _get_room_content_rect(rpx)
		var gauge_rect: Rect2 = _build_section_gauge_rect(rpx)

		if show_plan_atmosphere_overlay:
			_draw_room_atmosphere_overlay(
				content_rect,
				rs,
				smoke_layer_m,
				hot_layer_m,
				smoke_kg,
				room_height_m,
				room_floor_area_m2
			)

		if show_fire_overlay:
			_draw_room_fire_overlay(content_rect, rs, id)

		if show_section_gauge:
			_draw_section_gauge(
				gauge_rect,
				smoke_layer_m,
				hot_layer_m,
				layer_150c_m,
				smoke_kg,
				room_height_m,
				room_floor_area_m2
			)

		if show_hrr_bar:
			_draw_hrr_bar(content_rect, hrr_kw)

		if show_fuel_objects:
			_draw_room_fuel_objects(id, rs)

		_draw_room_safety_markers(id, rm)

		if show_room_name_watermark:
			_draw_room_name_watermark(id, rs, content_rect)

		if show_room_labels:
			_draw_room_label(id, rpx, rs)

		if show_window_badge:
			_draw_window_badge(rpx, rs)

		var outline_style: Dictionary = _build_room_outline_style(rs)
		draw_rect(
			rpx,
			Color(outline_style.get("color", room_outline_color)),
			false,
			float(outline_style.get("width", wall_thickness))
		)
		if id == selected_room_id:
			draw_rect(rpx.grow(-wall_thickness - 1.0), selected_room_outline_color, false, selected_room_outline_width)

	if show_openings:
		_draw_openings()

	_draw_floor_selector()


# ============================================================
# FONDO
# ============================================================

func _sync_building_geometry() -> void:
	if building_path and not building_path.is_empty() and building == null:
		building = get_node_or_null(building_path) as BuildingModel
	if building == null:
		building = get_node_or_null("../BuildingModel") as BuildingModel
	if building == null:
		return
	rects_m = building.get_room_rects_m()
	_refresh_floor_levels()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not (mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT):
		return
	var local_pos: Vector2 = get_global_transform_with_canvas().affine_inverse() * mb.position
	if _handle_floor_selector_click(local_pos):
		get_viewport().set_input_as_handled()
		return
	var clicked_opening_index: int = _get_opening_index_at_local_pos(local_pos)
	if clicked_opening_index >= 0:
		selected_opening_index = clicked_opening_index
		queue_redraw()
		opening_clicked.emit(clicked_opening_index, mb.position)
		get_viewport().set_input_as_handled()
		return
	var clicked_id: int = _get_room_id_at_local_pos(local_pos)
	if clicked_id >= 0:
		selected_room_id = clicked_id
		selected_opening_index = -1
		queue_redraw()
		room_clicked.emit(clicked_id)
		get_viewport().set_input_as_handled()
	else:
		if selected_room_id >= 0 or selected_opening_index >= 0:
			selected_room_id = -1
			selected_opening_index = -1
			queue_redraw()
			room_clicked.emit(-1)
			get_viewport().set_input_as_handled()


func select_opening(opening_index: int) -> void:
	selected_opening_index = opening_index
	queue_redraw()


func _get_room_id_at_local_pos(local_pos: Vector2) -> int:
	var tf: Dictionary = _get_draw_transform()
	var scale_px: float = maxf(0.001, float(tf["scale"]))
	var offset: Vector2 = tf["offset"]
	var pos_m: Vector2 = (local_pos - offset) / scale_px
	for id in _get_sorted_room_ids():
		if not _is_room_visible_on_selected_floor(id):
			continue
		if rects_m[id].has_point(pos_m):
			return id
	return -1


func _get_opening_index_at_local_pos(local_pos: Vector2) -> int:
	if building == null:
		return -1
	var best_index: int = -1
	var best_distance: float = 999999.0
	for index in range(building.get_opening_count()):
		if not _is_opening_visible_on_selected_floor(index):
			continue
		var segment: PackedVector2Array = _get_opening_segment_px(index)
		if segment.size() != 2:
			continue
		var distance: float = OpeningGeometry2D.distance_point_to_segment(local_pos, segment[0], segment[1])
		if distance < best_distance:
			best_distance = distance
			best_index = index
	var tolerance_px: float = maxf(10.0, opening_line_width * 2.5)
	return best_index if best_distance <= tolerance_px else -1


func _get_opening_segment_px(index: int) -> PackedVector2Array:
	var empty := PackedVector2Array()
	if building == null or index < 0:
		return empty
	var op: OpeningModel = building.get_opening_at(index)
	if op == null or not rects_m.has(op.a):
		return empty
	if not _is_opening_visible_on_selected_floor(index):
		return empty

	var a_id: int = op.a
	var b_id: int = op.b
	var ra: Rect2 = rects_m[a_id]
	var rb: Rect2 = Rect2()
	var b_exists: bool = rects_m.has(b_id)
	if b_exists:
		rb = rects_m[b_id]

	var seg_m: PackedVector2Array = OpeningGeometry2D.shared_edge_segment_m(ra, rb) if b_exists else OpeningGeometry2D.default_exterior_segment_m(ra, op.width_m, op.wall_side)
	if seg_m.size() != 2:
		return empty

	var tf: Dictionary = _get_draw_transform()
	var scale_px: float = float(tf["scale"])
	var offset: Vector2 = tf["offset"]
	var p1: Vector2 = seg_m[0] * scale_px + offset
	var p2: Vector2 = seg_m[1] * scale_px + offset
	if op.type == OpeningModel.Type.DOOR and b_exists:
		var door_px: float = maxf(8.0, op.width_m * scale_px)
		var seg_dir: Vector2 = (p2 - p1).normalized() if p1.distance_to(p2) > 0.01 else Vector2(1, 0)
		var seg_mid: Vector2 = (p1 + p2) * 0.5
		var hinge_px: Vector2 = seg_mid - seg_dir * door_px * 0.5
		return PackedVector2Array([hinge_px, hinge_px + seg_dir * door_px])
	return PackedVector2Array([p1, p2])


func _draw_background() -> void:
	draw_rect(Rect2(-50, -50, 4000, 2500), background_color, true)


func _refresh_floor_levels() -> void:
	floor_levels_m = FloorPlan2D.collect_floor_levels(building)
	selected_floor_index = FloorPlan2D.clamp_floor_index(selected_floor_index, floor_levels_m)


func _is_room_visible_on_selected_floor(room_id: int) -> bool:
	return FloorPlan2D.is_room_visible(building, floor_levels_m, selected_floor_index, room_id)


func _is_opening_visible_on_selected_floor(opening_index: int) -> bool:
	return FloorPlan2D.is_opening_visible(building, rects_m, floor_levels_m, selected_floor_index, opening_index)


func _draw_floor_selector() -> void:
	var font := ThemeDB.fallback_font
	if not show_floor_selector or floor_levels_m.size() <= 1 or font == null:
		return
	for i in range(floor_levels_m.size()):
		var rect: Rect2 = FloorPlan2D.selector_button_rect(
			i,
			floor_selector_position_px,
			floor_selector_button_size_px,
			floor_selector_gap_px
		)
		var active: bool = i == selected_floor_index
		draw_rect(rect, floor_selector_active_color if active else floor_selector_inactive_color, true)
		draw_rect(rect, room_outline_color, false, 1.0)
		var label: String = FloorPlan2D.floor_label(i)
		draw_string(
			font,
			rect.position + Vector2(10.0, 17.0),
			label,
			HORIZONTAL_ALIGNMENT_LEFT,
			rect.size.x - 12.0,
			11,
			floor_selector_text_color
		)


func _handle_floor_selector_click(local_pos: Vector2) -> bool:
	if not show_floor_selector or floor_levels_m.size() <= 1:
		return false
	var hit_index: int = FloorPlan2D.selector_hit_index(
		local_pos,
		floor_levels_m,
		floor_selector_position_px,
		floor_selector_button_size_px,
		floor_selector_gap_px
	)
	if hit_index < 0:
		return false
	selected_floor_index = hit_index
	selected_room_id = -1
	selected_opening_index = -1
	queue_redraw()
	room_clicked.emit(-1)
	return true


# ============================================================
# ATMOSFERA / FUEGO
# ============================================================

func _draw_room_atmosphere_overlay(
	rpx: Rect2,
	rs: Dictionary,
	smoke_layer_m: float,
	hot_layer_m: float,
	smoke_kg: float,
	room_h: float,
	floor_area_m2: float
) -> void:
	if rpx.size.x <= 1.0 or rpx.size.y <= 1.0:
		return

	var upper_hot_thickness_m: float = maxf(0.0, room_h - hot_layer_m)
	var upper_smoke_thickness_m: float = maxf(0.0, room_h - smoke_layer_m)
	var temp_upper_c: float = float(rs.get("temp_upper_c", 20.0))
	var temp_lower_c: float = float(rs.get("temp_lower_c", 20.0))
	var temp_0_9m_c: float = float(rs.get("temp_at_0_9m_c", temp_lower_c))

	var hot_intensity: float = clampf(
		0.40 * maxf(0.0, temp_upper_c - 60.0) / 540.0
			+ 0.35 * maxf(0.0, temp_0_9m_c - 35.0) / 320.0
			+ 0.25 * (upper_hot_thickness_m / maxf(0.1, room_h)),
		0.0,
		1.0
	)
	if hot_intensity > 0.0001:
		draw_rect(
			rpx,
			Color(
				heat_room_tint_color.r,
				heat_room_tint_color.g,
				heat_room_tint_color.b,
				0.04 + 0.22 * hot_intensity
			),
			true
		)

	var upper_volume_m3: float = maxf(0.05, floor_area_m2 * maxf(0.05, upper_smoke_thickness_m))
	var smoke_concentration_kg_m3: float = smoke_kg / upper_volume_m3
	var smoke_intensity: float = clampf(
		0.45 * (upper_smoke_thickness_m / maxf(0.1, room_h))
			+ 0.35 * (smoke_concentration_kg_m3 / maxf(0.01, smoke_concentration_reference_kg_m3))
			+ 0.20 * (smoke_kg / maxf(0.1, smoke_mass_reference_kg)),
		0.0,
		1.0
	)
	if smoke_intensity > 0.0001:
		draw_rect(
			rpx,
			Color(
				smoke_base_color.r,
				smoke_base_color.g,
				smoke_base_color.b,
				0.05 + 0.28 * smoke_intensity
			),
			true
		)

	if show_flashover_highlight and _is_flashover_indicator_visible(rs):
		var pulse: float = 0.72 + 0.28 * (0.5 + 0.5 * sin(float(state.get("sim_time_s", 0.0)) * 6.0))
		draw_rect(
			rpx,
			Color(
				flashover_fill_color.r,
				flashover_fill_color.g,
				flashover_fill_color.b,
				flashover_fill_color.a * pulse
			),
			true
		)

	# Extra darkening when smoke layer drops to eye level (~1.8 m)
	if smoke_layer_m < 1.8 and smoke_kg > smoke_visible_threshold_kg:
		var eye_depth: float = clampf((1.8 - smoke_layer_m) / 1.8, 0.0, 1.0)
		var smoke_conc: float = clampf(smoke_concentration_kg_m3 / maxf(0.001, smoke_concentration_reference_kg_m3), 0.0, 1.0)
		var dark_alpha: float = 0.08 + 0.35 * eye_depth * smoke_conc
		draw_rect(rpx, Color(0.04, 0.04, 0.06, dark_alpha), true)


func _draw_room_fire_overlay(rpx: Rect2, rs: Dictionary, room_id: int = -1) -> void:
	var has_fire: bool = bool(rs.get("has_fire", false))
	var hrr_kw: float = float(rs.get("hrr_kw", 0.0))
	var fire_smoldering: bool = bool(rs.get("fire_smoldering", false))
	var backdraft_active: bool = bool(rs.get("backdraft_active", false))
	var backdraft_triggered: bool = bool(rs.get("backdraft_triggered", false))
	if not has_fire and hrr_kw <= 5.0 and not fire_smoldering and not backdraft_active and not backdraft_triggered:
		return

	if rpx.size.x <= 2.0 or rpx.size.y <= 2.0:
		return

	# Por defecto: centro de la sala. Si hay objetos con fuego, ancla al objeto dominante.
	var center: Vector2 = rpx.position + rpx.size * 0.5
	if room_id >= 0 and rects_m.has(room_id):
		var objects: Array = rs.get("fuel_objects", [])
		var best_obj: Dictionary = {}
		var best_score: float = -1.0
		for raw in objects:
			if typeof(raw) != TYPE_DICTIONARY:
				continue
			var s: String = String(raw.get("state", "cold"))
			if s != "flaming" and s != "pyrolyzing":
				continue
			var score: float = float(raw.get("hrr_kw", 0.0))
			if bool(raw.get("is_primary_ignition_source", false)):
				score += 1000.0
			if score > best_score:
				best_score = score
				best_obj = raw
		if not best_obj.is_empty():
			var rm: Rect2 = rects_m[room_id]
			var pos_m: Vector2 = RoomStateVisuals2D.vector2_from_variant(best_obj.get("position_m", Vector2.ZERO))
			var sz_m: Vector2 = RoomStateVisuals2D.vector2_from_variant(best_obj.get("size_m", Vector2.ONE))
			var tf: Dictionary = _get_draw_transform()
			var sc: float = float(tf["scale"])
			var off: Vector2 = Vector2(tf["offset"])
			center = (rm.position + pos_m + sz_m * 0.5) * sc + off
	var base_size: float = minf(rpx.size.x, rpx.size.y)

	# Indicador backdraft: destello blanco-naranja intenso durante la fase explosiva
	# Post-evento: halo naranja residual permanente (backdraft_triggered pero no active)
	if backdraft_active:
		var t: float = float(state.get("sim_time_s", 0.0))
		var flash: float = 0.70 + 0.30 * (0.5 + 0.5 * sin(t * 18.0))  # parpadeo rápido
		draw_circle(center, base_size * 0.55,
			Color(1.0, 0.85, 0.30, 0.18 + 0.22 * flash))  # fulgor exterior amarillo-blanco
		draw_circle(center, base_size * 0.32,
			Color(1.0, 0.95, 0.70, 0.55 + 0.35 * flash))  # núcleo blanco-caliente
	elif backdraft_triggered:
		# Halo naranja residual: indica que esta sala tuvo backdraft
		draw_circle(center, base_size * 0.40,
			Color(0.90, 0.40, 0.05, 0.12))

	# Indicador smoldering: halo naranja pulsante con símbolo de brasa
	if fire_smoldering:
		var t: float = float(state.get("sim_time_s", 0.0))
		var pulse: float = 0.5 + 0.5 * sin(t * 2.0)
		var smolder_radius: float = base_size * (0.10 + 0.04 * pulse)
		draw_circle(center, smolder_radius * 2.2,
			Color(0.65, 0.28, 0.05, 0.08 + 0.07 * pulse))
		draw_circle(center, smolder_radius,
			Color(0.75, 0.35, 0.05, 0.25 + 0.20 * pulse))
		if hrr_kw <= 5.0:
			return

	var fire_intensity: float = clampf(hrr_kw / maxf(1.0, hrr_bar_max_kw), 0.0, 1.0)
	var base_radius: float = base_size * (0.08 + 0.14 * fire_intensity)

	draw_circle(
		center,
		base_radius * 1.8,
		Color(fire_glow_color.r, fire_glow_color.g, fire_glow_color.b, 0.08 + 0.16 * fire_intensity)
	)
	draw_circle(
		center,
		base_radius,
		Color(fire_core_color.r, fire_core_color.g, fire_core_color.b, 0.14 + 0.34 * fire_intensity)
	)

	if _is_flashover_indicator_visible(rs):
		var pulse: float = 0.75 + 0.25 * (0.5 + 0.5 * sin(float(state.get("sim_time_s", 0.0)) * 7.0))
		draw_circle(
			center,
			base_radius * 2.6,
			Color(1.0, 0.30, 0.10, 0.08 + 0.10 * pulse)
		)


func _draw_section_gauge(
	gauge_rect: Rect2,
	smoke_layer_m: float,
	hot_layer_m: float,
	layer_150c_m: float,
	smoke_kg: float,
	room_h: float,
	floor_area_m2: float
) -> void:
	if gauge_rect.size.x <= 1.0 or gauge_rect.size.y <= 1.0:
		return

	draw_rect(gauge_rect, section_gauge_bg_color, true)

	if show_hot_layer_overlay:
		_draw_hot_layer_overlay(gauge_rect, hot_layer_m, room_h)
	if show_smoke_layer:
		_draw_smoke_layer(gauge_rect, smoke_layer_m, smoke_kg, room_h, floor_area_m2)
	if show_150c_layer:
		_draw_150c_line(gauge_rect, layer_150c_m, room_h)

	draw_rect(gauge_rect, section_gauge_outline_color, false, 1.0)


# ============================================================
# HUMO / CAPAS
# ============================================================

func _draw_smoke_layer(
	rpx: Rect2,
	h_layer_m: float,
	smoke_kg: float,
	room_h: float = room_height_m_default,
	floor_area_m2: float = 1.0
) -> void:
	if smoke_kg <= smoke_visible_threshold_kg:
		return

	var upper_thick_m: float = maxf(0.0, room_h - h_layer_m)
	var upper_frac: float = clampf(upper_thick_m / room_h, 0.0, 1.0)
	if upper_frac <= 0.0:
		return

	var upper_volume_m3: float = maxf(0.05, floor_area_m2 * upper_thick_m)
	var smoke_concentration_kg_m3: float = smoke_kg / upper_volume_m3
	var intensity: float = clampf(
		0.25 * upper_frac
			+ 0.55 * (smoke_concentration_kg_m3 / maxf(0.01, smoke_concentration_reference_kg_m3))
			+ 0.20 * (smoke_kg / maxf(0.1, smoke_mass_reference_kg)),
		0.0,
		1.0
	)

	var smoke_h_px: float = rpx.size.y * upper_frac
	var smoke_rect: Rect2 = Rect2(
		rpx.position.x,
		rpx.position.y,
		rpx.size.x,
		smoke_h_px
	)

	var alpha: float = smoke_min_alpha + smoke_max_alpha_bonus * intensity
	var smoke_color: Color = Color(
		smoke_base_color.r,
		smoke_base_color.g,
		smoke_base_color.b,
		alpha
	)
	draw_rect(smoke_rect, smoke_color, true)

	if show_smoke_layer_line:
		var layer_h_m: float = clampf(h_layer_m, 0.0, room_h)
		if layer_h_m <= 0.01:
			layer_h_m = 0.02
		elif layer_h_m >= room_h - 0.01:
			layer_h_m = room_h - 0.02

		var y_px: float = rpx.position.y + rpx.size.y * (1.0 - layer_h_m / maxf(0.01, room_h))
		draw_line(
			Vector2(rpx.position.x, y_px),
			Vector2(rpx.position.x + rpx.size.x, y_px),
			smoke_layer_line_color,
			smoke_layer_line_width
		)


func _draw_hot_layer_overlay(rpx: Rect2, hot_layer_m: float, room_h: float = room_height_m_default) -> void:
	var upper_thick_m: float = maxf(0.0, room_h - hot_layer_m)
	var upper_frac: float = clampf(upper_thick_m / room_h, 0.0, 1.0)
	if upper_frac <= 0.0:
		return

	var hot_rect: Rect2 = Rect2(
		rpx.position.x,
		rpx.position.y,
		rpx.size.x,
		rpx.size.y * upper_frac
	)
	draw_rect(hot_rect, hot_layer_color, true)


func _draw_150c_line(rpx: Rect2, layer_150c_m: float, room_h: float = room_height_m_default) -> void:
	var h_m: float = layer_150c_m
	if h_m <= 0.01:
		h_m = 0.02
	elif h_m >= room_h - 0.01:
		h_m = room_h - 0.02
	else:
		h_m = clampf(h_m, 0.0, room_h)

	var y_px: float = rpx.position.y + rpx.size.y * (1.0 - h_m / maxf(0.01, room_h))
	draw_line(
		Vector2(rpx.position.x, y_px),
		Vector2(rpx.position.x + rpx.size.x, y_px),
		layer_150c_color,
		layer_150c_line_width
	)


# ============================================================
# BARRA HRR
# ============================================================

func _draw_hrr_bar(rpx: Rect2, hrr_kw: float) -> void:
	var bar_w: float = maxf(0.0, rpx.size.x - hrr_bar_margin_px * 2.0)
	var bar_y: float = rpx.position.y + rpx.size.y - 10.0
	var bar_rect_bg: Rect2 = Rect2(
		rpx.position.x + hrr_bar_margin_px,
		bar_y,
		bar_w,
		hrr_bar_height_px
	)
	draw_rect(bar_rect_bg, hrr_bar_bg_color, true)

	var bar_frac: float = clampf(hrr_kw / maxf(1.0, hrr_bar_max_kw), 0.0, 1.0)
	var bar_rect: Rect2 = Rect2(
		rpx.position.x + hrr_bar_margin_px,
		bar_y,
		bar_w * bar_frac,
		hrr_bar_height_px
	)
	draw_rect(bar_rect, hrr_bar_color, true)


# ============================================================
# OBJETOS COMBUSTIBLES
# ============================================================

func _draw_room_fuel_objects(room_id: int, rs: Dictionary) -> void:
	if not rects_m.has(room_id):
		return

	var objects: Array = rs.get("fuel_objects", [])
	if objects.is_empty():
		return

	var room_rect_m: Rect2 = rects_m[room_id]
	for raw_obj in objects:
		if typeof(raw_obj) != TYPE_DICTIONARY:
			continue
		var obj: Dictionary = raw_obj
		if String(obj.get("id", "")).begins_with("room_proxy_"):
			continue
		var pos_m: Vector2 = RoomStateVisuals2D.vector2_from_variant(obj.get("position_m", Vector2.ZERO))
		var size_m: Vector2 = RoomStateVisuals2D.vector2_from_variant(obj.get("size_m", Vector2.ONE))
		if size_m.x <= 0.01 or size_m.y <= 0.01:
			continue

		var obj_rect_px: Rect2 = _to_px(Rect2(room_rect_m.position + pos_m, size_m))
		if obj_rect_px.size.x < 3.0 or obj_rect_px.size.y < 3.0:
			continue

		var state_name: String = String(obj.get("state", "cold"))
		var fill: Color = RoomStateVisuals2D.fuel_object_color_for_state(state_name, fuel_object_fill_color)
		var center_m: Vector2 = room_rect_m.position + pos_m + size_m * 0.5
		var rot := Transform2D(deg_to_rad(float(obj.get("rotation_deg", 0.0))), Vector2.ZERO)
		var half: Vector2 = size_m * 0.5
		var corners_px := PackedVector2Array([
			_point_to_px(center_m + rot * Vector2(-half.x, -half.y)),
			_point_to_px(center_m + rot * Vector2(half.x, -half.y)),
			_point_to_px(center_m + rot * Vector2(half.x, half.y)),
			_point_to_px(center_m + rot * Vector2(-half.x, half.y))
		])
		draw_colored_polygon(corners_px, fill)
		draw_polyline(PackedVector2Array([corners_px[0], corners_px[1], corners_px[2], corners_px[3], corners_px[0]]), fuel_object_outline_color, 1.0)

		if bool(obj.get("is_primary_ignition_source", false)):
			draw_circle(_point_to_px(center_m), minf(obj_rect_px.size.x, obj_rect_px.size.y) * 0.18, fire_core_color)

		# SF-AUD-004: llama por objeto — se dibuja cuando el objeto está en FLAMING o PYROLYZING.
		# Tamaño proporcional a hrr_kw del objeto (mínimo visible aunque sea 0).
		if state_name == "flaming" or state_name == "pyrolyzing":
			var obj_hrr_kw: float = maxf(0.0, float(obj.get("hrr_kw", 0.0)))
			var flame_r: float = clampf(
				minf(obj_rect_px.size.x, obj_rect_px.size.y) * 0.22
					+ sqrt(maxf(0.0, obj_hrr_kw)) * 0.18,
				3.0,
				minf(obj_rect_px.size.x, obj_rect_px.size.y) * 0.46
			)
			var center: Vector2 = _point_to_px(center_m)
			var flame_alpha: float = 0.90 if state_name == "flaming" else 0.55
			draw_circle(center, flame_r, Color(1.0, 0.55, 0.08, flame_alpha * 0.50))
			draw_circle(center, flame_r * 0.55, Color(1.0, 0.90, 0.22, flame_alpha))

		if show_fuel_object_names and ThemeDB.fallback_font != null and obj_rect_px.size.x >= 24.0 and obj_rect_px.size.y >= 14.0:
			var label: String = String(obj.get("name", obj.get("kind", "")))
			if label == "":
				label = String(obj.get("id", "obj"))
			var label_pos: Vector2 = obj_rect_px.position + Vector2(3.0, minf(13.0, obj_rect_px.size.y - 2.0))
			draw_string(
				ThemeDB.fallback_font,
				label_pos + Vector2(1.0, 1.0),
				label,
				HORIZONTAL_ALIGNMENT_LEFT,
				maxf(12.0, obj_rect_px.size.x - 6.0),
				9,
				Color(0.0, 0.0, 0.0, 0.80)
			)
			draw_string(
				ThemeDB.fallback_font,
				label_pos,
				label,
				HORIZONTAL_ALIGNMENT_LEFT,
				maxf(12.0, obj_rect_px.size.x - 6.0),
				9,
				fuel_object_label_color
			)


func _draw_room_safety_markers(room_id: int, room_rect_m: Rect2) -> void:
	if building == null:
		return
	if show_detector_markers:
		var detector_states: Dictionary = _state_records_by_id(Array(state.get("detectors", [])))
		for raw_det in building.detectors:
			if typeof(raw_det) != TYPE_DICTIONARY:
				continue
			var det: Dictionary = raw_det
			if int(det.get("room_id", -1)) != room_id:
				continue
			var det_id: String = String(det.get("id", ""))
			var triggered: bool = bool(Dictionary(detector_states.get(det_id, {})).get("triggered", det.get("triggered", false)))
			var px: Vector2 = _point_to_px(room_rect_m.position + _safety_local_position(det, room_rect_m))
			draw_circle(px, 9.0, Color(0.0, 0.0, 0.0, 0.72))
			draw_circle(px, 6.5, detector_triggered_color if triggered else detector_marker_color)
	if show_victim_markers:
		var victim_states: Dictionary = _state_records_by_id(Array(state.get("victims", [])))
		for raw_vic in building.victims:
			if typeof(raw_vic) != TYPE_DICTIONARY:
				continue
			var vic: Dictionary = raw_vic
			if int(vic.get("room_id", -1)) != room_id:
				continue
			var vic_id: String = String(vic.get("id", ""))
			var incapacitated: bool = bool(Dictionary(victim_states.get(vic_id, {})).get("incapacitated", vic.get("incapacitated", false)))
			var px: Vector2 = _point_to_px(room_rect_m.position + _safety_local_position(vic, room_rect_m))
			var r: float = 7.0
			var pts := PackedVector2Array([
				px + Vector2(0.0, -r),
				px + Vector2(r, 0.0),
				px + Vector2(0.0, r),
				px + Vector2(-r, 0.0)
			])
			draw_colored_polygon(pts, victim_incapacitated_color if incapacitated else victim_marker_color)
			draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]), Color(0.0, 0.0, 0.0, 0.75), 1.3)


func _state_records_by_id(records: Array) -> Dictionary:
	var result: Dictionary = {}
	for raw_record in records:
		if typeof(raw_record) != TYPE_DICTIONARY:
			continue
		var record: Dictionary = raw_record
		var id_text: String = String(record.get("id", ""))
		if id_text != "":
			result[id_text] = record
	return result


func _safety_local_position(data: Dictionary, room_rect_m: Rect2) -> Vector2:
	if data.has("x_m") and data.has("y_m"):
		return Vector2(
			clampf(float(data.get("x_m", room_rect_m.size.x * 0.5)), 0.0, room_rect_m.size.x),
			clampf(float(data.get("y_m", room_rect_m.size.y * 0.5)), 0.0, room_rect_m.size.y)
		)
	return room_rect_m.size * 0.5


func _draw_room_name_watermark(id: int, rs: Dictionary, content_rect: Rect2) -> void:
	if ThemeDB.fallback_font == null:
		return
	if content_rect.size.x < room_watermark_min_room_px or content_rect.size.y < room_watermark_min_room_px:
		return
	var label_text: String = _room_state_display_name(id, rs)
	var min_dim: float = minf(content_rect.size.x, content_rect.size.y)
	var font_size: int = room_watermark_font_size if room_watermark_font_size > 0 \
			else clampi(int(min_dim * 0.30), 14, 52)
	var text_size: Vector2 = ThemeDB.fallback_font.get_string_size(
			label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var center: Vector2 = content_rect.get_center()
	var text_x: float = center.x - text_size.x * 0.5
	var text_y: float = center.y + text_size.y * 0.35
	# Sombra para contraste sobre fondos claros
	draw_string(
			ThemeDB.fallback_font,
			Vector2(text_x + 1.0, text_y + 1.0),
			label_text,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			font_size,
			Color(0.0, 0.0, 0.0, room_watermark_color.a * 0.7)
	)
	draw_string(
			ThemeDB.fallback_font,
			Vector2(text_x, text_y),
			label_text,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			font_size,
			room_watermark_color
	)


# ============================================================
# ETIQUETA DE SALA
# ============================================================

func _draw_room_label(id: int, rpx: Rect2, rs: Dictionary) -> void:
	var content_rect: Rect2 = _get_room_content_rect(rpx)
	var lines: Array[String] = _build_room_label_lines(id, content_rect, rs)
	if lines.is_empty():
		return

	var base_pos: Vector2 = Vector2(
		content_rect.position.x + room_label_offset.x,
		content_rect.position.y + room_label_offset.y
	)

	if room_label_bg:
		var bottom_reserved_px: float = _get_room_label_bottom_reserved_px()
		var bg_w: float = minf(156.0, maxf(20.0, content_rect.size.x - 4.0))
		var bg_h: float = minf(
			maxf(18.0, content_rect.size.y - bottom_reserved_px - 4.0),
			room_label_padding * 2.0 + room_label_line_h * float(lines.size())
		)
		var bg_rect: Rect2 = Rect2(
			content_rect.position.x + 2.0,
			content_rect.position.y + 2.0,
			bg_w,
			bg_h
		)
		draw_rect(bg_rect, room_label_bg_color, true)

	var svv_pct: float = RoomStateVisuals2D.compute_svv_pct(rs)
	var svv_col: Color = RoomStateVisuals2D.svv_color(svv_pct)

	for i in range(lines.size()):
		var pos: Vector2 = base_pos + Vector2(0.0, room_label_line_h * float(i))
		var col: Color = svv_col if lines[i].begins_with("FED") else room_label_color
		_draw_text_line(lines[i], pos, col)


func _build_room_label_lines(id: int, content_rect: Rect2, rs: Dictionary) -> Array[String]:
	return _build_room_label_lines_full(id, content_rect, rs)


func _build_room_label_lines_full(id: int, content_rect: Rect2, rs: Dictionary) -> Array[String]:
	var up: float = float(rs.get("temp_upper_c", 0.0))
	var low: float = float(rs.get("temp_lower_c", 0.0))
	var temp_0_9m: float = float(rs.get("temp_at_0_9m_c", low))
	var smoke_lay: float = float(rs.get("smoke_layer_m", rs.get("h_layer_m", 0.0)))
	var hot_lay: float = float(rs.get("hot_layer_m", rs.get("thermal_layer_m", 0.0)))
	var layer_150c: float = float(rs.get("layer_150c_m", 0.0))
	var hrr: float = float(rs.get("hrr_kw", 0.0))
	var o2v: float = float(rs.get("o2", 0.0) * 100.0)
	var room_name: String = _room_state_display_name(id, rs)
	var fuel_mj: float = float(rs.get("fuel_capacity_MJ", rs.get("fuel_energy_MJ", 0.0)))
	var rem_mj: float = float(rs.get("fuel_objects_remaining_MJ", rs.get("remaining_fuel_MJ", 0.0)))
	var co_ppm: float = float(rs.get("co_ppm", 0.0))
	var fed_val: float = float(rs.get("fed", 0.0))
	var flashover_triggered: bool = _is_flashover_indicator_visible(rs)
	var detail: String = RoomLabelLayout2D.pick_detail(
		content_rect,
		Vector2(room_label_tiny_threshold_w_px, room_label_tiny_threshold_h_px),
		Vector2(room_label_compact_threshold_w_px, room_label_compact_threshold_h_px),
		Vector2(room_label_medium_threshold_w_px, room_label_medium_threshold_h_px)
	)

	var svv_pct_val: float = RoomStateVisuals2D.compute_svv_pct(rs)
	var lines: Array[String] = []
	if show_room_name and room_name != "":
		lines.append(room_name)

	# Cabecera: intencionalmente vacía (no mostrar ID ni nombre aquí)

	# Solo nombre/ID cuando show_room_data_in_label es false
	if not show_room_data_in_label:
		return lines

	match detail:
		"tiny":
			lines.append("T %.0fC" % temp_0_9m)
			lines.append("SVV %.0f%%" % svv_pct_val)
			if bool(rs.get("backdraft_active", false)):
				lines.append("BACKDRAFT")
			elif flashover_triggered:
				lines.append("FLASHOVER")
			elif bool(rs.get("fire_smoldering", false)):
				lines.append("SMOLD")
		"compact":
			lines.append("HRR %.0f kW" % hrr)
			lines.append("T %.0f / %.0f C" % [up, low])
			lines.append("O2 %.1f%%  CO %.0f" % [o2v, co_ppm])
			lines.append("Comb %.0f MJ" % rem_mj)
			lines.append("FED %.2f  SVV %.0f%%" % [fed_val, svv_pct_val])
			if bool(rs.get("backdraft_active", false)):
				lines.append("BACKDRAFT")
			elif flashover_triggered:
				lines.append("FLASHOVER")
			elif bool(rs.get("fire_smoldering", false)):
				lines.append("SMOLD")
		"medium":
			# 6 líneas: HRR, temp, capas, gases, FED/SVV
			lines.append("HRR %.0f kW" % hrr)
			lines.append("T↑ %.0f  T↓ %.0f C" % [up, low])
			lines.append("SmL %.2f m  L150 %.2f" % [smoke_lay, layer_150c])
			lines.append("O2 %.1f%%  CO %.0f ppm" % [o2v, co_ppm])
			lines.append("Comb %.0f / %.0f MJ" % [rem_mj, fuel_mj])
			lines.append("FED %.3f  SVV %.0f%%" % [fed_val, svv_pct_val])
			var med_win: String = RoomStateVisuals2D.window_status_label(rs, window_full_open_threshold)
			if med_win != "":
				lines.append(med_win)
			if bool(rs.get("backdraft_active", false)):
				lines.append("BACKDRAFT")
			elif flashover_triggered:
				lines.append("FLASHOVER")
			elif bool(rs.get("fire_smoldering", false)):
				lines.append("SMOLDERING")
		_:
			# Detalle completo
			lines.append("HRR %.0f kW" % hrr)
			lines.append("T↑ %.0f  T↓ %.0f C" % [up, low])
			lines.append("T@0.9m %.0f C" % temp_0_9m)
			lines.append("SmL %.2f  HotL %.2f m" % [smoke_lay, hot_lay])
			lines.append("L150 %.2f m" % layer_150c)
			lines.append("O2 %.1f%%  CO %.0f ppm" % [o2v, co_ppm])
			lines.append("FED %.3f  SVV %.0f%%" % [fed_val, svv_pct_val])
			lines.append("Comb %.0f / %.0f MJ" % [rem_mj, fuel_mj])
			var full_win: String = RoomStateVisuals2D.window_status_label(rs, window_full_open_threshold)
			if full_win != "":
				lines.append(full_win)
			if bool(rs.get("backdraft_active", false)):
				lines.append("BACKDRAFT")
			elif flashover_triggered:
				lines.append("FLASHOVER")
			elif bool(rs.get("fire_smoldering", false)):
				lines.append("SMOLDERING")

	return RoomLabelLayout2D.fit_lines(
		content_rect,
		lines,
		flashover_triggered,
		room_label_offset,
		room_label_line_h,
		room_label_padding,
		_get_room_label_bottom_reserved_px()
	)


func _room_state_display_name(id: int, rs: Dictionary) -> String:
	var name_text: String = String(rs.get("name", "")).strip_edges()
	if name_text != "":
		return name_text
	if building != null:
		var room: RoomModel = building.get_room(id)
		if room != null and room.name.strip_edges() != "":
			return room.name.strip_edges()
	return "R%d" % id


func _get_room_label_bottom_reserved_px() -> float:
	return RoomLabelLayout2D.bottom_reserved_px(show_hrr_bar, hrr_bar_height_px, hrr_bar_margin_px)


func _draw_text_line(text: String, pos: Vector2, color: Color) -> void:
	if ThemeDB.fallback_font == null:
		return

	if room_label_shadow:
		draw_string(
			ThemeDB.fallback_font,
			pos + Vector2(1.0, 1.0),
			text,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1.0,
			room_label_font_size,
			Color(0.0, 0.0, 0.0, color.a * 0.8)
		)

	draw_string(
		ThemeDB.fallback_font,
		pos,
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		room_label_font_size,
		color
	)


# ============================================================
# BADGE DE VENTANA
# ============================================================

func _draw_window_badge(rpx: Rect2, rs: Dictionary) -> void:
	var wmax: float = float(rs.get("window_open_max", -1.0))
	if wmax < 0.0:
		return

	var col: Color
	if wmax <= 0.0:
		col = Color(window_color.r, window_color.g, window_color.b, 0.75)
	elif wmax < window_full_open_threshold:
		var t: float = wmax / window_full_open_threshold
		var lerped: Color = window_color.lerp(window_broken_color, t)
		col = Color(lerped.r, lerped.g, lerped.b, 0.90)
	else:
		col = Color(window_open_color.r, window_open_color.g, window_open_color.b, 0.90)

	var bx: float = rpx.position.x + rpx.size.x - window_badge_size.x - 4.0
	var by_v: float = rpx.position.y + 4.0
	var badge_rect: Rect2 = Rect2(Vector2(bx, by_v), window_badge_size)
	draw_rect(badge_rect, col, true)

	if ThemeDB.fallback_font == null:
		return

	var badge_label: String
	if wmax <= 0.0:
		badge_label = "CRD"
	elif wmax < window_full_open_threshold:
		badge_label = "ROT"
	else:
		badge_label = "ABT"

	draw_string(
		ThemeDB.fallback_font,
		Vector2(bx + 1.0, by_v + 6.0),
		badge_label,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		7,
		Color(1.0, 1.0, 1.0, 0.95)
	)


# ============================================================
# OPENINGS
# ============================================================

func _draw_openings() -> void:
	if building == null:
		return

	for index in range(building.get_opening_count()):
		if not _is_opening_visible_on_selected_floor(index):
			continue
		var op: OpeningModel = building.get_opening_at(index)
		if op == null:
			continue
		if not rects_m.has(op.a):
			continue

		var a_id: int = op.a
		var b_id: int = op.b

		var ra: Rect2 = rects_m[a_id]
		var rb: Rect2 = Rect2()
		var b_exists: bool = rects_m.has(b_id)
		if b_exists:
			rb = rects_m[b_id]

		var seg_m: PackedVector2Array = PackedVector2Array()
		if b_exists:
			seg_m = OpeningGeometry2D.shared_edge_segment_m(ra, rb)
		else:
			seg_m = OpeningGeometry2D.default_exterior_segment_m(ra, op.width_m, op.wall_side)

		if seg_m.size() != 2:
			continue

		var tf: Dictionary = _get_draw_transform()
		var scale_px: float = float(tf["scale"])
		var offset: Vector2 = tf["offset"]

		var p1: Vector2 = seg_m[0] * scale_px + offset
		var p2: Vector2 = seg_m[1] * scale_px + offset

		var alpha: float = 0.25 + 0.75 * clampf(op.open_fraction, 0.0, 1.0)
		var col: Color
		if op.type == OpeningModel.Type.DOOR or op.type == OpeningModel.Type.HOLE:
			var base_color: Color = door_color if op.type == OpeningModel.Type.DOOR else hole_color
			col = Color(base_color.r, base_color.g, base_color.b, alpha)
			if b_exists:
				var tf2: Dictionary = _get_draw_transform()
				var scale_px2: float = float(tf2["scale"])
				var door_px: float = maxf(8.0, op.width_m * scale_px2)
				var seg_dir: Vector2 = (p2 - p1).normalized() if p1.distance_to(p2) > 0.01 else Vector2(1, 0)
				var seg_mid: Vector2 = (p1 + p2) * 0.5
				var hinge_px: Vector2 = seg_mid - seg_dir * door_px * 0.5
				# Borrar solo el vano de la apertura
				draw_line(hinge_px, hinge_px + seg_dir * door_px, background_color, wall_thickness + 2.0)
				if op.type == OpeningModel.Type.HOLE:
					draw_line(hinge_px, hinge_px + seg_dir * door_px, col, opening_line_width)
				else:
					# Door swings away from corridor → always into the destination room
					var _room_a_ref: RoomModel = building.get_room(a_id)
					var _room_b_ref: RoomModel = building.get_room(b_id)
					var _corridor_kinds: Array = ["pasillo", "distribuidor", "corridor", "hallway", "entrada", "recibidor"]
					var _a_is_corridor: bool = _room_a_ref != null and _corridor_kinds.has(_room_a_ref.kind.to_lower())
					var _b_is_corridor: bool = _room_b_ref != null and _corridor_kinds.has(_room_b_ref.kind.to_lower())
					var swing_ref_px: Vector2 = _to_px(ra).get_center() if (_a_is_corridor and not _b_is_corridor) else _to_px(rb).get_center()
					_draw_door_top_view(hinge_px, door_px, seg_dir, swing_ref_px, col, op.open_fraction)
			else:
				draw_line(p1, p2, background_color, wall_thickness + 2.0)
				draw_line(p1, p2, col, opening_line_width)
			if index == selected_opening_index:
				_draw_selected_opening_marker(index)
			continue
		else:
			col = Color(window_color.r, window_color.g, window_color.b, alpha)

		draw_line(p1, p2, col, opening_line_width)

		if show_opening_labels and ThemeDB.fallback_font != null:
			var mid: Vector2 = (p1 + p2) * 0.5
			var txt: String = "%.0f%%" % (op.open_fraction * 100.0)
			draw_string(
				ThemeDB.fallback_font,
				mid + Vector2(4.0, -4.0),
				txt,
				HORIZONTAL_ALIGNMENT_LEFT,
				-1.0,
				12,
				Color(1.0, 1.0, 1.0, 0.85)
			)
		if index == selected_opening_index:
			_draw_selected_opening_marker(index)


# ============================================================
# GEOMETRIA DE OPENINGS
# ============================================================

func _draw_door_top_view(
	hinge: Vector2,
	door_px: float,
	wall_dir: Vector2,
	room_b_center: Vector2,
	col: Color,
	open_fraction: float
) -> void:
	# wall_dir: dirección normalizada de la pared (desde bisagra hacia lado libre)
	# Perpendiculares respecto a la pared
	var perp_cw: Vector2 = Vector2(wall_dir.y, -wall_dir.x)
	var perp_ccw: Vector2 = Vector2(-wall_dir.y, wall_dir.x)
	# Abrir hacia la habitación A (hacia adentro)
	var to_a: Vector2 = (hinge - room_b_center).normalized()
	var swing: Vector2 = perp_cw if to_a.dot(perp_cw) >= 0.0 else perp_ccw
	# Hoja de puerta: posición abierta (perpendicular a la pared)
	var open_t: float = clampf(open_fraction, 0.0, 1.0)
	var door_dir: Vector2 = wall_dir.lerp(swing, open_t).normalized()
	if door_dir.length_squared() <= 0.000001:
		door_dir = wall_dir
	var tip_leaf: Vector2 = hinge + door_dir * door_px

	draw_line(hinge, tip_leaf, col, 1.5)
	# Marco libre (línea corta en la pared en el lado opuesto)
	draw_line(hinge + wall_dir * door_px, hinge + wall_dir * door_px + swing * 3.0, col, 1.0)
	# Arco de 90° desde posición abierta hasta posición cerrada
	var a_open: float = atan2(swing.y, swing.x)
	var a_close: float = atan2(wall_dir.y, wall_dir.x)
	var da: float = a_close - a_open
	while da > PI:
		da -= TAU
	while da < -PI:
		da += TAU
	draw_arc(hinge, door_px, a_open, a_open + da, 18, col, 1.0, true)


func _draw_selected_opening_marker(opening_index: int) -> void:
	var selected_segment: PackedVector2Array = _get_opening_segment_px(opening_index)
	if selected_segment.size() == 2:
		draw_line(selected_segment[0], selected_segment[1], selected_room_outline_color, opening_line_width + 4.0)


# ============================================================
# UTILS
# ============================================================

func _build_room_outline_style(rs: Dictionary) -> Dictionary:
	var outline_color: Color = room_outline_color
	var outline_width: float = wall_thickness
	var hrr_kw: float = float(rs.get("hrr_kw", 0.0))
	var o2_fraction: float = float(rs.get("o2", 0.209))
	var sim_time_s: float = float(state.get("sim_time_s", 0.0))

	if show_flashover_highlight and _is_flashover_indicator_visible(rs):
		var pulse: float = 0.70 + 0.30 * (0.5 + 0.5 * sin(sim_time_s * 6.0))
		outline_color = Color(
			flashover_outline_color.r,
			flashover_outline_color.g,
			flashover_outline_color.b,
			0.85 + 0.15 * pulse
		)
		outline_width = wall_thickness + 2.0 + pulse * 1.5
	elif hrr_kw > 20.0:
		var fire_intensity: float = clampf(hrr_kw / maxf(1.0, hrr_bar_max_kw), 0.0, 1.0)
		outline_color = Color(
			active_fire_outline_color.r,
			active_fire_outline_color.g,
			active_fire_outline_color.b,
			0.85
		)
		outline_width = wall_thickness + 0.6 + 1.6 * fire_intensity
	elif o2_fraction < 0.18:
		outline_color = low_o2_outline_color
		outline_width = wall_thickness + 0.8

	return {
		"color": outline_color,
		"width": outline_width
	}


func _is_flashover_indicator_visible(rs: Dictionary) -> bool:
	if not bool(rs.get("flashover_triggered", false)):
		return false
	if flashover_indicator_permanent:
		return true
	var flash_time_s: float = float(rs.get("flashover_time_s", -1.0))
	if flash_time_s < 0.0:
		return true
	var sim_time_s: float = float(state.get("sim_time_s", 0.0))
	return sim_time_s <= flash_time_s + maxf(1.0, flashover_indicator_duration_s)


func _build_section_gauge_rect(rpx: Rect2) -> Rect2:
	if not show_section_gauge:
		return Rect2()

	var gauge_h: float = maxf(0.0, rpx.size.y - section_gauge_margin_px * 2.0)
	if gauge_h < section_gauge_min_height_px:
		return Rect2()

	var gauge_w: float = minf(section_gauge_width_px, rpx.size.x * 0.20)
	gauge_w = maxf(10.0, gauge_w)
	if rpx.size.x < gauge_w + 18.0:
		return Rect2()

	return Rect2(
		rpx.position.x + rpx.size.x - gauge_w - section_gauge_margin_px,
		rpx.position.y + section_gauge_margin_px,
		gauge_w,
		gauge_h
	)


func _get_room_content_rect(rpx: Rect2) -> Rect2:
	var left: float = rpx.position.x + 1.0
	var top: float = rpx.position.y + 1.0
	var right: float = rpx.position.x + rpx.size.x - 1.0
	var bottom: float = rpx.position.y + rpx.size.y - 1.0

	var gauge_rect: Rect2 = _build_section_gauge_rect(rpx)
	if gauge_rect.size.x > 0.0:
		right = minf(right, gauge_rect.position.x - 4.0)

	return Rect2(
		left,
		top,
		maxf(6.0, right - left),
		maxf(6.0, bottom - top)
	)


func _to_px(rm: Rect2) -> Rect2:
	var tf: Dictionary = _get_draw_transform()
	var scale_px: float = float(tf["scale"])
	var offset: Vector2 = tf["offset"]

	var pos: Vector2 = rm.position * scale_px + offset
	var size: Vector2 = rm.size * scale_px
	return Rect2(pos, size)


func _point_to_px(pos_m: Vector2) -> Vector2:
	var tf: Dictionary = _get_draw_transform()
	var offset: Vector2 = tf["offset"]
	return pos_m * float(tf["scale"]) + offset


func _get_sorted_room_ids() -> Array[int]:
	var ids: Array[int] = []
	for k in rects_m.keys():
		ids.append(int(k))
	ids.sort()
	return ids


func _get_building_bounds_m() -> Rect2:
	var first: bool = true
	var bounds: Rect2 = Rect2()

	for id in _get_sorted_room_ids():
		if not _is_room_visible_on_selected_floor(id):
			continue
		var r: Rect2 = rects_m[id]
		if first:
			bounds = r
			first = false
		else:
			bounds = bounds.merge(r)

	if first:
		for id in _get_sorted_room_ids():
			var r: Rect2 = rects_m[id]
			if first:
				bounds = r
				first = false
			else:
				bounds = bounds.merge(r)

	return bounds


func _get_draw_transform() -> Dictionary:
	var bounds_m: Rect2 = _get_building_bounds_m()
	if bounds_m.size.x <= 0.0 or bounds_m.size.y <= 0.0:
		return {
			"scale": meters_to_px,
			"offset": Vector2.ZERO
		}

	var viewport_rect: Rect2 = get_viewport_rect()
	# Área disponible descontando el panel de UI y márgenes
	var avail_x: float = view_margin_px + ui_reserved_left_px
	var avail_y: float = view_margin_px + ui_reserved_top_px
	var available_w: float = maxf(1.0, viewport_rect.size.x - ui_reserved_left_px - ui_reserved_right_px - view_margin_px * 2.0)
	var available_h: float = maxf(1.0, viewport_rect.size.y - ui_reserved_top_px - ui_reserved_bottom_px - view_margin_px * 2.0)

	var scale_px: float = meters_to_px
	if auto_fit_to_view:
		var scale_x: float = available_w / bounds_m.size.x
		var scale_y: float = available_h / bounds_m.size.y
		scale_px = minf(scale_x, scale_y)

	var drawing_size_px: Vector2 = bounds_m.size * scale_px
	# Centrar en el área disponible (sin el HUD)
	var offset: Vector2 = Vector2(
		avail_x + (available_w - drawing_size_px.x) * 0.5,
		avail_y + (available_h - drawing_size_px.y) * 0.5
	) - bounds_m.position * scale_px

	return {
		"scale": scale_px,
		"offset": offset
	}

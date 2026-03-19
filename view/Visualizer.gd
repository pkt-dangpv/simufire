extends Node2D
class_name Visualizer

## ============================================================
## VISUALIZER
## ------------------------------------------------------------
## Responsabilidad:
## - Dibujar habitaciones a partir de rects del BuildingModel
## - Mostrar capa superior de humo usando h_layer_m / smoke_mass_kg
## - Dibujar puertas/ventanas (openings)
## - Dibujar barra HRR por habitación
## - Dibujar etiquetas de estado dentro de cada sala
##
## Este nodo NO calcula simulación.
## Solo representa el estado que recibe desde Main / SimulationEngine.
## ============================================================


# ============================================================
# AJUSTES GENERALES
# ============================================================

@export var meters_to_px: float = 100.0
@export var wall_thickness: float = 2.0
@export var room_height_m_default: float = 2.4

@export var background_color: Color = Color(0.10, 0.10, 0.11, 1.0)
@export var room_outline_color: Color = Color(1.0, 1.0, 1.0, 1.0)
@export var room_fill_color: Color = Color(1.0, 1.0, 1.0, 0.02)

# ============================================================
# TOGGLES DE DIBUJO
# ============================================================

@export var show_room_fill: bool = true
@export var show_smoke_layer: bool = true
@export var show_hrr_bar: bool = true
@export var show_openings: bool = true
@export var show_room_labels: bool = true
@export var show_room_name: bool = false
@export var show_opening_labels: bool = false

# ============================================================
# HUMO
# ============================================================

@export var smoke_base_color: Color = Color(0.32, 0.32, 0.36, 1.0)
@export var smoke_min_alpha: float = 0.30
@export var smoke_max_alpha_bonus: float = 0.55
@export var smoke_mass_reference_kg: float = 8.0

# ============================================================
# ETIQUETAS
# ============================================================

@export var room_label_font_size: int = 11
@export var room_label_color: Color = Color(1.0, 1.0, 1.0, 0.95)
@export var room_label_shadow: bool = true
@export var room_label_bg: bool = false
@export var room_label_bg_color: Color = Color(0.0, 0.0, 0.0, 0.40)
@export var room_label_padding: float = 4.0
@export var room_label_offset: Vector2 = Vector2(6.0, 14.0)
@export var room_label_line_h: float = 13.0

# ============================================================
# BARRA HRR
# ============================================================

@export var hrr_bar_height_px: float = 6.0
@export var hrr_bar_margin_px: float = 5.0
@export var hrr_bar_max_kw: float = 3000.0
@export var hrr_bar_color: Color = Color(1.0, 0.35, 0.15, 0.90)
@export var hrr_bar_bg_color: Color = Color(1.0, 1.0, 1.0, 0.08)

# ============================================================
# OPENINGS
# ============================================================

@export var door_color: Color = Color(0.30, 1.00, 0.40, 1.0)
@export var window_color: Color = Color(0.35, 0.70, 1.00, 1.0)
@export var opening_line_width: float = 4.0

# ============================================================
# ESTADO Y GEOMETRÍA
# ============================================================

## Estado recibido desde Main / SimulationEngine:
## state["0"] = {
##   "h_layer_m": ...,
##   "smoke_mass_kg": ...,
##   "hrr_kw": ...,
##   "temp_upper_c": ...,
##   "temp_lower_c": ...,
##   "o2": ...
## }
var state: Dictionary = {}

## Geometría en metros: room_id -> Rect2
var rects_m: Dictionary[int, Rect2] = {}

@onready var building: BuildingModel = $"../BuildingModel" as BuildingModel


# ============================================================
# READY
# ============================================================

func _ready() -> void:
	# Solo cacheamos geometría.
	# El estado lo debe enviar Main con set_state().
	if building != null:
		rects_m = building.get_room_rects_m()

	queue_redraw()


# ============================================================
# API PÚBLICA
# ============================================================

func set_state(s: Dictionary) -> void:
	state = s
	queue_redraw()


# ============================================================
# DRAW
# ============================================================

func _draw() -> void:
	_draw_background()

	var room_ids: Array[int] = _get_sorted_room_ids()

	for id in room_ids:
		var rm: Rect2 = rects_m[id]
		var rpx: Rect2 = _to_px(rm)

		# 1) relleno base de sala
		if show_room_fill:
			draw_rect(rpx, room_fill_color, true)

		# 2) paredes
		draw_rect(rpx, room_outline_color, false, wall_thickness)

		# 3) estado de esta sala
		var rs: Dictionary = state.get(str(id), {})
		if rs.is_empty():
			# Aunque no haya estado, seguimos dibujando openings después
			continue

		var h_layer_m: float = float(rs.get("h_layer_m", room_height_m_default))
		var smoke_kg: float = float(rs.get("smoke_mass_kg", 0.0))
		var hrr_kw: float = float(rs.get("hrr_kw", 0.0))

		# 4) humo
		if show_smoke_layer:
			_draw_smoke_layer(rpx, h_layer_m, smoke_kg)

		# 5) barra HRR
		if show_hrr_bar:
			_draw_hrr_bar(rpx, hrr_kw)

		# 6) etiqueta de sala
		if show_room_labels:
			_draw_room_label(id, rpx, rs)

	# 7) openings al final, para que queden por encima
	if show_openings:
		_draw_openings()


# ============================================================
# FONDO
# ============================================================

func _draw_background() -> void:
	draw_rect(Rect2(-50, -50, 4000, 2500), background_color, true)


# ============================================================
# HUMO
# ============================================================

func _draw_smoke_layer(rpx: Rect2, h_layer_m: float, smoke_kg: float) -> void:
	var room_h: float = room_height_m_default
	var upper_thick_m: float = maxf(0.0, room_h - h_layer_m)
	var upper_frac: float = clampf(upper_thick_m / room_h, 0.0, 1.0)

	if upper_frac <= 0.0:
		return

	# Intensidad combinando altura ocupada + masa de humo
	var intensity: float = clampf(
		0.35 * upper_frac + 0.65 * (smoke_kg / maxf(0.1, smoke_mass_reference_kg)),
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
# ETIQUETA DE SALA
# ============================================================

func _draw_room_label(id: int, rpx: Rect2, rs: Dictionary) -> void:
	var up: float = float(rs.get("temp_upper_c", 0.0))
	var low: float = float(rs.get("temp_lower_c", 0.0))
	var sm: float = float(rs.get("smoke_mass_kg", 0.0))
	var lay: float = float(rs.get("h_layer_m", 0.0))
	var hrr: float = float(rs.get("hrr_kw", 0.0))
	var o2v: float = float(rs.get("o2", 0.0))
	var room_name: String = String(rs.get("name", ""))

	var lines: Array[String] = []

	lines.append("R%d" % id)

	if show_room_name and room_name != "":
		lines.append(room_name)

	lines.append("HRR %.0f" % hrr)
	lines.append("Up %.0f" % up)
	lines.append("Low %.0f" % low)
	lines.append("Sm %.2f" % sm)
	lines.append("L %.2f" % lay)
	lines.append("O2 %.3f" % o2v)

	var base_pos: Vector2 = rpx.position + room_label_offset

	# Fondo de etiqueta (simple, ancho fijo suficiente para debug)
	if room_label_bg:
		var bg_w: float = minf(120.0, rpx.size.x - 12.0)
		var bg_h: float = room_label_padding * 2.0 + room_label_line_h * float(lines.size())
		var bg_rect: Rect2 = Rect2(
			rpx.position.x + 4.0,
			rpx.position.y + 4.0,
			bg_w,
			bg_h
		)
		draw_rect(bg_rect, room_label_bg_color, true)

	for i in range(lines.size()):
		var pos: Vector2 = base_pos + Vector2(0.0, room_label_line_h * float(i))
		_draw_text_line(lines[i], pos, room_label_color)


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
# OPENINGS
# ============================================================

func _draw_openings() -> void:
	if building == null:
		return

	for op: OpeningModel in building.openings:
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

		# Si conecta con otra habitación, calcular borde compartido real
		if b_exists:
			seg_m = _shared_edge_segment_m(ra, rb)
		else:
			# Exterior: segmento genérico en pared superior de A
			seg_m = _default_exterior_segment_m(ra, op.width_m)

		if seg_m.size() != 2:
			continue

		var p1: Vector2 = seg_m[0] * meters_to_px
		var p2: Vector2 = seg_m[1] * meters_to_px

		var alpha: float = 0.25 + 0.75 * clampf(op.open_fraction, 0.0, 1.0)

		var col: Color
		if op.type == OpeningModel.Type.DOOR:
			col = Color(door_color.r, door_color.g, door_color.b, alpha)
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
				Color(1, 1, 1, 0.85)
			)


# ============================================================
# GEOMETRÍA DE OPENINGS
# ============================================================

## Devuelve un segmento (2 puntos) en METROS del borde compartido
## entre dos rects (si se tocan).
func _shared_edge_segment_m(a: Rect2, b: Rect2) -> PackedVector2Array:
	var eps: float = 0.0001

	# a.right == b.left
	if absf((a.position.x + a.size.x) - b.position.x) < eps:
		var x: float = a.position.x + a.size.x
		var y1: float = maxf(a.position.y, b.position.y)
		var y2: float = minf(a.position.y + a.size.y, b.position.y + b.size.y)
		if y2 > y1:
			return PackedVector2Array([Vector2(x, y1), Vector2(x, y2)])

	# a.left == b.right
	if absf(a.position.x - (b.position.x + b.size.x)) < eps:
		var x2: float = a.position.x
		var yy1: float = maxf(a.position.y, b.position.y)
		var yy2: float = minf(a.position.y + a.size.y, b.position.y + b.size.y)
		if yy2 > yy1:
			return PackedVector2Array([Vector2(x2, yy1), Vector2(x2, yy2)])

	# a.bottom == b.top
	if absf((a.position.y + a.size.y) - b.position.y) < eps:
		var y: float = a.position.y + a.size.y
		var xx1: float = maxf(a.position.x, b.position.x)
		var xx2: float = minf(a.position.x + a.size.x, b.position.x + b.size.x)
		if xx2 > xx1:
			return PackedVector2Array([Vector2(xx1, y), Vector2(xx2, y)])

	# a.top == b.bottom
	if absf(a.position.y - (b.position.y + b.size.y)) < eps:
		var y2: float = a.position.y
		var xxx1: float = maxf(a.position.x, b.position.x)
		var xxx2: float = minf(a.position.x + a.size.x, b.position.x + b.size.x)
		if xxx2 > xxx1:
			return PackedVector2Array([Vector2(xxx1, y2), Vector2(xxx2, y2)])

	return PackedVector2Array()


func _default_exterior_segment_m(r: Rect2, width_m: float) -> PackedVector2Array:
	# Segmento centrado en la pared superior del rect
	var safe_width: float = clampf(width_m, 0.20, maxf(0.20, r.size.x))
	var x1: float = r.position.x + (r.size.x - safe_width) * 0.5
	var x2: float = x1 + safe_width
	var y: float = r.position.y
	return PackedVector2Array([Vector2(x1, y), Vector2(x2, y)])


# ============================================================
# UTILS
# ============================================================

func _to_px(rm: Rect2) -> Rect2:
	var pos: Vector2 = rm.position * meters_to_px
	var size: Vector2 = rm.size * meters_to_px
	return Rect2(pos, size)


func _get_sorted_room_ids() -> Array[int]:
	var ids: Array[int] = []
	for k in rects_m.keys():
		ids.append(int(k))
	ids.sort()
	return ids
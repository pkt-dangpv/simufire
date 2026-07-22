extends Control
class_name InteractiveLineChart

# ============================================================
# INTERACTIVE LINE CHART (nativo Godot, sin navegador)
# ------------------------------------------------------------
# Control que superpone varias series temporales. Cada serie lleva
# su PROPIO eje X (x[]) e Y (y[]), de modo que se pueden comparar
# series de salas distintas aunque su malla temporal difiera.
# Interactividad:
#   - hover: crosshair + tooltip con t y el valor de cada serie
#   - arrastrar horizontal: zoom al rango X seleccionado
#   - doble clic / clic derecho: reset de zoom
#   - clic en la leyenda: activa/desactiva una serie
# ============================================================

const MARGIN_LEFT: float = 64.0
const MARGIN_RIGHT: float = 18.0
const MARGIN_TOP: float = 26.0
const MARGIN_BOTTOM: float = 44.0
# Paleta alineada con ui/SimuFireTheme.gd (mismo look que el juego).
const AXIS_COLOR: Color = Color(0.18, 0.22, 0.25)      # BORDER
const GRID_COLOR: Color = Color(1, 1, 1, 0.06)
const BG_COLOR: Color = Color(0.00, 0.01, 0.01)        # BG
const PLOT_BG_COLOR: Color = Color(0.03, 0.07, 0.09)   # FIELD
const TEXT_COLOR: Color = Color(0.90, 0.94, 0.96)      # TEXT
const MUTED_COLOR: Color = Color(0.49, 0.55, 0.60)     # MUTED
const CROSSHAIR_COLOR: Color = Color(1.00, 0.78, 0.00, 0.55)  # YELLOW

# Series: Array de Dictionary con
#   { "name": String, "color": Color, "x": PackedFloat32Array,
#     "y": PackedFloat32Array, "dash": bool, "visible": bool }
var _series: Array = []
var _y_label: String = ""
var _thresholds: Array = []   # { "y", "color", "label" }
var _events: Array = []       # { "t", "color", "label" }

var _x_min: float = 0.0
var _x_max: float = 1.0
var _y_min: float = 0.0
var _y_max: float = 1.0
var _view_x_min: float = 0.0
var _view_x_max: float = 1.0

var _hover_px: Vector2 = Vector2(-1, -1)
var _hovering: bool = false
var _dragging: bool = false
var _drag_start_x: float = -1.0
var _drag_cur_x: float = -1.0
var _legend_hitboxes: Array = []   # { "rect": Rect2, "index": int }

var _font: Font = null
var _font_size: int = 13

## Si es true, no pinta el fondo opaco (para overlays translúcidos sobre el juego).
var transparent_background: bool = false
## Alfa del fondo del área de plot cuando transparent_background=true.
var bg_alpha: float = 0.28
## Mensaje cuando no hay series.
var empty_message: String = "Añade una serie para empezar (Habitación + Métrica → Añadir)"


func _ready() -> void:
	_font = ThemeDB.fallback_font
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(200, 120)


func set_data(series: Array, y_label: String,
		thresholds: Array = [], events: Array = []) -> void:
	_series = series
	_y_label = y_label
	_thresholds = thresholds
	_events = events
	for s in _series:
		if not s.has("visible"):
			s["visible"] = true
	_recompute_x_bounds()
	_view_x_min = _x_min
	_view_x_max = _x_max
	_recompute_y_bounds()
	queue_redraw()


func reset_zoom() -> void:
	_view_x_min = _x_min
	_view_x_max = _x_max
	_recompute_y_bounds()
	queue_redraw()


# -----------------------------------------------------------------------
# BOUNDS
# -----------------------------------------------------------------------

func _recompute_x_bounds() -> void:
	var lo: float = INF
	var hi: float = -INF
	for s in _series:
		var xs: PackedFloat32Array = s["x"]
		if xs.is_empty():
			continue
		lo = minf(lo, xs[0])
		hi = maxf(hi, xs[xs.size() - 1])
	if lo == INF or hi == -INF:
		lo = 0.0
		hi = 1.0
	if hi <= lo:
		hi = lo + 1.0
	_x_min = lo
	_x_max = hi


func _recompute_y_bounds() -> void:
	var lo: float = INF
	var hi: float = -INF
	for s in _series:
		if not bool(s.get("visible", true)):
			continue
		var xs: PackedFloat32Array = s["x"]
		var ys: PackedFloat32Array = s["y"]
		var n: int = mini(xs.size(), ys.size())
		for i in range(n):
			if xs[i] < _view_x_min or xs[i] > _view_x_max:
				continue
			lo = minf(lo, ys[i])
			hi = maxf(hi, ys[i])
	for th in _thresholds:
		var ty: float = float(th.get("y", 0.0))
		lo = minf(lo, ty)
		hi = maxf(hi, ty)
	if lo == INF or hi == -INF:
		lo = 0.0
		hi = 1.0
	if hi <= lo:
		hi = lo + 1.0
	var pad: float = (hi - lo) * 0.06
	_y_min = lo - pad
	_y_max = hi + pad
	if _y_min > 0.0 and _y_min < (hi - lo) * 0.5:
		_y_min = 0.0


# -----------------------------------------------------------------------
# TRANSFORMS
# -----------------------------------------------------------------------

func _plot_rect() -> Rect2:
	return Rect2(
		MARGIN_LEFT, MARGIN_TOP,
		maxf(10.0, size.x - MARGIN_LEFT - MARGIN_RIGHT),
		maxf(10.0, size.y - MARGIN_TOP - MARGIN_BOTTOM)
	)


func _data_to_px(t: float, y: float) -> Vector2:
	var r: Rect2 = _plot_rect()
	var fx: float = (t - _view_x_min) / maxf(1e-9, _view_x_max - _view_x_min)
	var fy: float = (y - _y_min) / maxf(1e-9, _y_max - _y_min)
	return Vector2(r.position.x + fx * r.size.x, r.position.y + (1.0 - fy) * r.size.y)


func _px_to_time(px_x: float) -> float:
	var r: Rect2 = _plot_rect()
	var fx: float = clampf((px_x - r.position.x) / maxf(1e-9, r.size.x), 0.0, 1.0)
	return _view_x_min + fx * (_view_x_max - _view_x_min)


# -----------------------------------------------------------------------
# DRAW
# -----------------------------------------------------------------------

func _draw() -> void:
	var r: Rect2 = _plot_rect()
	if transparent_background:
		draw_rect(r, Color(PLOT_BG_COLOR.r, PLOT_BG_COLOR.g, PLOT_BG_COLOR.b, bg_alpha), true)
	else:
		draw_rect(Rect2(Vector2.ZERO, size), BG_COLOR, true)
		draw_rect(r, PLOT_BG_COLOR, true)

	_legend_hitboxes.clear()
	if _series.is_empty():
		if _font != null:
			draw_string(_font, Vector2(r.position.x + 14, r.position.y + 28),
				empty_message, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, MUTED_COLOR)
		return

	_draw_grid_and_axes(r)
	_draw_thresholds(r)
	_draw_events(r)
	_draw_series(r)
	_draw_legend(r)
	_draw_hover(r)
	_draw_drag_selection(r)


func _draw_grid_and_axes(r: Rect2) -> void:
	draw_line(r.position, r.position + Vector2(0, r.size.y), AXIS_COLOR, 1.0)
	draw_line(r.position + Vector2(0, r.size.y), r.position + r.size, AXIS_COLOR, 1.0)

	for ty in _nice_ticks(_y_min, _y_max, 5):
		var p: Vector2 = _data_to_px(_view_x_min, ty)
		draw_line(Vector2(r.position.x, p.y), Vector2(r.position.x + r.size.x, p.y), GRID_COLOR, 1.0)
		if _font != null:
			draw_string(_font, Vector2(6, p.y + 4), _fmt_num(ty),
				HORIZONTAL_ALIGNMENT_LEFT, MARGIN_LEFT - 10, _font_size, MUTED_COLOR)

	for tx in _nice_ticks(_view_x_min, _view_x_max, 6):
		var p2: Vector2 = _data_to_px(tx, _y_min)
		draw_line(Vector2(p2.x, r.position.y), Vector2(p2.x, r.position.y + r.size.y), GRID_COLOR, 1.0)
		if _font != null:
			draw_string(_font, Vector2(p2.x - 16, r.position.y + r.size.y + 17),
				"%d" % int(round(tx)), HORIZONTAL_ALIGNMENT_LEFT, 48, _font_size, MUTED_COLOR)

	if _font != null:
		draw_string(_font, Vector2(r.position.x + r.size.x * 0.5 - 32, size.y - 7),
			"Tiempo (s)", HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size, MUTED_COLOR)
		draw_string(_font, Vector2(6, r.position.y - 9), _y_label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size, TEXT_COLOR)


func _draw_thresholds(r: Rect2) -> void:
	for th in _thresholds:
		var ty: float = float(th.get("y", 0.0))
		if ty < _y_min or ty > _y_max:
			continue
		var col: Color = th.get("color", Color(1, 0.3, 0.3, 0.6))
		var p: Vector2 = _data_to_px(_view_x_min, ty)
		draw_dashed_line(Vector2(r.position.x, p.y), Vector2(r.position.x + r.size.x, p.y), col, 1.0, 6.0)
		var lbl: String = String(th.get("label", ""))
		if lbl != "" and _font != null:
			draw_string(_font, Vector2(r.position.x + 6, p.y - 3), lbl,
				HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size, col)


func _draw_events(r: Rect2) -> void:
	for ev in _events:
		var et: float = float(ev.get("t", 0.0))
		if et < _view_x_min or et > _view_x_max:
			continue
		var col: Color = ev.get("color", Color(0.6, 0.6, 0.6, 0.5))
		var p: Vector2 = _data_to_px(et, _y_min)
		draw_dashed_line(Vector2(p.x, r.position.y), Vector2(p.x, r.position.y + r.size.y),
			Color(col.r, col.g, col.b, 0.4), 1.0, 5.0)
		var lbl: String = String(ev.get("label", ""))
		if lbl != "" and _font != null:
			draw_string(_font, Vector2(p.x + 3, r.position.y + 12), lbl,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 10, col)


func _draw_series(r: Rect2) -> void:
	for s in _series:
		if not bool(s.get("visible", true)):
			continue
		var xs: PackedFloat32Array = s["x"]
		var ys: PackedFloat32Array = s["y"]
		var col: Color = s.get("color", Color.WHITE)
		var n: int = mini(xs.size(), ys.size())
		var pts: PackedVector2Array = PackedVector2Array()
		for i in range(n):
			if xs[i] < _view_x_min - 1.0 or xs[i] > _view_x_max + 1.0:
				continue
			pts.append(_data_to_px(xs[i], ys[i]))
		if pts.size() < 2:
			continue
		if bool(s.get("dash", false)):
			for i in range(pts.size() - 1):
				draw_dashed_line(pts[i], pts[i + 1], col, 1.7, 6.0)
		else:
			draw_polyline(pts, col, 1.9, true)


func _draw_legend(r: Rect2) -> void:
	if _font == null:
		return
	var x: float = r.position.x + r.size.x - 8.0
	var y: float = r.position.y + 6.0
	for idx in range(_series.size()):
		var s: Dictionary = _series[idx]
		var nm: String = String(s.get("name", ""))
		var col: Color = s.get("color", Color.WHITE)
		var vis: bool = bool(s.get("visible", true))
		var tw: float = _font.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size).x
		var box_w: float = tw + 28.0
		var rect: Rect2 = Rect2(x - box_w, y, box_w, 19.0)
		draw_rect(rect, Color(0.0, 0.0, 0.0, 0.4), true)
		draw_rect(Rect2(rect.position + Vector2(5, 7), Vector2(14, 4)),
			col if vis else Color(col.r, col.g, col.b, 0.3), true)
		draw_string(_font, rect.position + Vector2(24, 14), nm,
			HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size,
			TEXT_COLOR if vis else Color(0.5, 0.5, 0.5))
		_legend_hitboxes.append({"rect": rect, "index": idx})
		y += 21.0


func _draw_hover(r: Rect2) -> void:
	if not _hovering or _series.is_empty() or not r.has_point(_hover_px):
		return
	var t_hover: float = _px_to_time(_hover_px.x)
	var px_line: Vector2 = _data_to_px(t_hover, _y_min)
	draw_line(Vector2(px_line.x, r.position.y), Vector2(px_line.x, r.position.y + r.size.y),
		CROSSHAIR_COLOR, 1.0)

	var lines: Array = ["t = %d s" % int(round(t_hover))]
	var colors: Array = [TEXT_COLOR]
	for s in _series:
		if not bool(s.get("visible", true)):
			continue
		var xs: PackedFloat32Array = s["x"]
		var ys: PackedFloat32Array = s["y"]
		var idx: int = _nearest_index(xs, t_hover)
		if idx < 0 or idx >= ys.size():
			continue
		lines.append("%s: %s" % [String(s.get("name", "")), _fmt_num(ys[idx])])
		colors.append(s.get("color", Color.WHITE))
		draw_circle(_data_to_px(xs[idx], ys[idx]), 3.0, s.get("color", Color.WHITE))

	if _font == null:
		return
	var tw2: float = 0.0
	for l in lines:
		tw2 = maxf(tw2, _font.get_string_size(l, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size).x)
	var box_w: float = tw2 + 16.0
	var box_h: float = lines.size() * 17.0 + 8.0
	var bx: float = _hover_px.x + 14.0
	if bx + box_w > r.position.x + r.size.x:
		bx = _hover_px.x - box_w - 14.0
	var by: float = clampf(_hover_px.y - box_h * 0.5, r.position.y, r.position.y + r.size.y - box_h)
	draw_rect(Rect2(bx, by, box_w, box_h), Color(0.04, 0.05, 0.06, 0.93), true)
	draw_rect(Rect2(bx, by, box_w, box_h), Color(0.4, 0.42, 0.45), false)
	for i in range(lines.size()):
		draw_string(_font, Vector2(bx + 8, by + 15 + i * 17), lines[i],
			HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size, colors[i])


func _draw_drag_selection(r: Rect2) -> void:
	if not _dragging:
		return
	var x0: float = clampf(minf(_drag_start_x, _drag_cur_x), r.position.x, r.position.x + r.size.x)
	var x1: float = clampf(maxf(_drag_start_x, _drag_cur_x), r.position.x, r.position.x + r.size.x)
	draw_rect(Rect2(x0, r.position.y, x1 - x0, r.size.y), Color(0.4, 0.6, 0.9, 0.18), true)
	draw_line(Vector2(x0, r.position.y), Vector2(x0, r.position.y + r.size.y), Color(0.5, 0.7, 1.0, 0.7), 1.0)
	draw_line(Vector2(x1, r.position.y), Vector2(x1, r.position.y + r.size.y), Color(0.5, 0.7, 1.0, 0.7), 1.0)


# -----------------------------------------------------------------------
# INPUT
# -----------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_hover_px = event.position
		_hovering = true
		if _dragging:
			_drag_cur_x = event.position.x
		queue_redraw()
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.double_click:
				reset_zoom()
				return
			if event.pressed:
				for hb in _legend_hitboxes:
					if (hb["rect"] as Rect2).has_point(event.position):
						var i: int = hb["index"]
						_series[i]["visible"] = not bool(_series[i].get("visible", true))
						_recompute_y_bounds()
						queue_redraw()
						return
				_dragging = true
				_drag_start_x = event.position.x
				_drag_cur_x = event.position.x
			else:
				if _dragging:
					_dragging = false
					_apply_drag_zoom()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			reset_zoom()


func _apply_drag_zoom() -> void:
	var x0: float = minf(_drag_start_x, _drag_cur_x)
	var x1: float = maxf(_drag_start_x, _drag_cur_x)
	if absf(x1 - x0) < 8.0:
		queue_redraw()
		return
	var t0: float = _px_to_time(x0)
	var t1: float = _px_to_time(x1)
	if t1 - t0 < 1e-3:
		return
	_view_x_min = t0
	_view_x_max = t1
	_recompute_y_bounds()
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		_hovering = false
		# Cancela cualquier selección de caja en curso al salir del área.
		_dragging = false
		queue_redraw()


# -----------------------------------------------------------------------
# HELPERS
# -----------------------------------------------------------------------

func _nearest_index(xs: PackedFloat32Array, t: float) -> int:
	if xs.is_empty():
		return -1
	# Búsqueda binaria (x ordenado ascendente).
	var lo: int = 0
	var hi: int = xs.size() - 1
	while lo < hi:
		var mid: int = (lo + hi) / 2
		if xs[mid] < t:
			lo = mid + 1
		else:
			hi = mid
	if lo > 0 and absf(xs[lo - 1] - t) <= absf(xs[lo] - t):
		return lo - 1
	return lo


func _nice_ticks(lo: float, hi: float, count: int) -> Array:
	var ticks: Array = []
	if hi <= lo or count < 2:
		return [lo, hi]
	var raw_step: float = (hi - lo) / float(count)
	var mag: float = pow(10.0, floor(log(raw_step) / log(10.0)))
	var norm: float = raw_step / mag
	var step: float
	if norm < 1.5:
		step = 1.0 * mag
	elif norm < 3.0:
		step = 2.0 * mag
	elif norm < 7.0:
		step = 5.0 * mag
	else:
		step = 10.0 * mag
	var v: float = ceil(lo / step) * step
	var guard: int = 0
	while v <= hi and guard < 200:
		ticks.append(v)
		v += step
		guard += 1
	return ticks


func _fmt_num(v: float) -> String:
	var a: float = absf(v)
	if a >= 100.0:
		return "%.0f" % v
	if a >= 10.0:
		return "%.1f" % v
	if a >= 1.0:
		return "%.2f" % v
	return "%.3f" % v

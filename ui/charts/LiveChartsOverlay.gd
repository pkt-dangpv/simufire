extends Control
class_name LiveChartsOverlay

# ============================================================
# LIVE CHARTS OVERLAY (tiempo real, HUD translúcido y flotante)
# ------------------------------------------------------------
# Recuadro semitransparente sobre el juego (2D / 3D / FP) que
# muestra una métrica de una sala en vivo. Es una mini-ventana:
#   - se ARRASTRA por su barra de cabecera
#   - se REDIMENSIONA por el tirador de la esquina inferior derecha
#   - se CONTRAE a solo la barra con el botón ▾ / ▸ (no se destruye)
#   - deja pasar el ratón al juego salvo en la barra y el tirador
#
# Parámetros configurables desde el editor (abre LiveChartsOverlay.tscn):
# tamaño, márgenes, opacidad, colores, métrica inicial, cadencia, etc.
#
# API usada por Main.gd:
#   seed_rooms(state)             -> puebla salas antes de arrancar
#   reset()                       -> limpia histórico (nuevo run)
#   sample(sim_time_s, state)     -> añade una muestra por sala
#   add_event(sim_time_s, type)   -> marca vertical de evento
# ============================================================

const InteractiveLineChartScript := preload("res://ui/charts/InteractiveLineChart.gd")
const SFTheme := preload("res://ui/SimuFireTheme.gd")
const NCW := preload("res://ui/charts/NativeChartsWindow.gd")

# --- Configuración editable desde Godot ---
@export var box_size: Vector2i = Vector2i(340, 200)
@export var min_box_size: Vector2i = Vector2i(230, 96)
@export var screen_margin: int = 16
@export_range(0.0, 1.0, 0.02) var panel_opacity: float = 0.62
@export_range(0.0, 1.0, 0.02) var chart_bg_alpha: float = 0.28
@export var panel_color: Color = Color(0.02, 0.05, 0.07)
@export var accent_color: Color = Color("#ff4000")
@export var default_metric_index: int = 0
@export var start_collapsed: bool = false
@export var movable: bool = true
@export var resizable: bool = true
## Cadencia de muestreo en segundos reales (la lee Main.gd).
@export_range(0.05, 2.0, 0.05) var sample_interval_s: float = 0.3

var _panel: PanelContainer = null
var _header: HBoxContainer = null
var _collapse_btn: Button = null
var _tag: Label = null
var _room_selector: OptionButton = null
var _metric_selector: OptionButton = null
var _chart: Control = null
var _grip: Control = null

var _dragging_move: bool = false
var _resizing: bool = false
var _collapsed: bool = false
var _expanded_size: Vector2 = Vector2(340, 200)

# rid -> { name, times: Array, cols: { c: Array } }
var _rooms: Dictionary = {}
var _room_ids: Array = []
var _events: Array = []


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # click-through salvo hijos STOP

	_panel = PanelContainer.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 3)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(vb)

	# --- Cabecera (barra de arrastre) ---
	_header = HBoxContainer.new()
	_header.add_theme_constant_override("separation", 6)
	_header.mouse_filter = Control.MOUSE_FILTER_STOP
	_header.gui_input.connect(_on_header_gui_input)
	vb.add_child(_header)

	_collapse_btn = Button.new()
	_collapse_btn.text = "▾"
	_collapse_btn.focus_mode = Control.FOCUS_NONE
	_collapse_btn.custom_minimum_size = Vector2(22, 20)
	_collapse_btn.add_theme_font_size_override("font_size", 11)
	_collapse_btn.pressed.connect(_toggle_collapse)
	_header.add_child(_collapse_btn)

	_tag = Label.new()
	_tag.text = "EN VIVO"
	_tag.add_theme_font_override("font", SFTheme.title_font())
	_tag.add_theme_font_size_override("font_size", 11)
	_tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_header.add_child(_tag)

	_room_selector = _mk_option(74)
	_room_selector.item_selected.connect(_on_selection_changed)
	_header.add_child(_room_selector)

	_metric_selector = _mk_option(122)
	for g in NCW.METRIC_GROUPS:
		_metric_selector.add_item(String(g["name"]))
	_metric_selector.item_selected.connect(_on_selection_changed)
	_header.add_child(_metric_selector)

	# --- Gráfico ---
	_chart = InteractiveLineChartScript.new()
	_chart.transparent_background = true
	_chart.empty_message = "Esperando datos de la simulación…"
	_chart.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chart.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chart.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(_chart)

	# --- Tirador de redimensión (esquina inferior derecha) ---
	_grip = Control.new()
	_grip.custom_minimum_size = Vector2(18, 18)
	_grip.anchor_left = 1.0
	_grip.anchor_top = 1.0
	_grip.anchor_right = 1.0
	_grip.anchor_bottom = 1.0
	_grip.offset_left = -18.0
	_grip.offset_top = -18.0
	_grip.offset_right = 0.0
	_grip.offset_bottom = 0.0
	_grip.mouse_filter = Control.MOUSE_FILTER_STOP
	_grip.mouse_default_cursor_shape = Control.CURSOR_FDIAGSIZE
	_grip.gui_input.connect(_on_grip_gui_input)
	add_child(_grip)


func _ready() -> void:
	_apply_config()


func _apply_config() -> void:
	# Estilo del panel translúcido.
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(panel_color.r, panel_color.g, panel_color.b, panel_opacity)
	sb.set_corner_radius_all(6)
	sb.border_color = Color(accent_color.r, accent_color.g, accent_color.b, 0.55)
	sb.set_border_width_all(1)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	_panel.add_theme_stylebox_override("panel", sb)

	_tag.add_theme_color_override("font_color", accent_color)
	_chart.bg_alpha = chart_bg_alpha

	if default_metric_index >= 0 and default_metric_index < NCW.METRIC_GROUPS.size():
		_metric_selector.select(default_metric_index)

	# Tamaño y posición inicial (esquina inferior derecha), como Control libre.
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	_expanded_size = Vector2(box_size)
	size = Vector2(box_size)
	var vp: Vector2 = get_viewport_rect().size
	position = Vector2(vp.x - size.x - screen_margin, vp.y - size.y - screen_margin)

	if start_collapsed:
		_toggle_collapse()


func _mk_option(min_w: int) -> OptionButton:
	var ob := OptionButton.new()
	ob.custom_minimum_size = Vector2(min_w, 20)
	ob.clip_text = true
	ob.focus_mode = Control.FOCUS_NONE
	ob.add_theme_font_override("font", SFTheme.body_font())
	ob.add_theme_font_size_override("font_size", 10)
	ob.add_theme_color_override("font_color", SFTheme.TEXT)
	var box := SFTheme.stylebox(Color(0.03, 0.07, 0.09, 0.9), SFTheme.BORDER, 1, 3, Vector2(6.0, 2.0))
	ob.add_theme_stylebox_override("normal", box)
	ob.add_theme_stylebox_override("hover", box)
	ob.add_theme_stylebox_override("pressed", box)
	return ob


func _draw() -> void:
	# Marca visual del tirador de redimensión (3 rayitas diagonales).
	if _collapsed or not resizable:
		return
	var c := Color(accent_color.r, accent_color.g, accent_color.b, 0.7)
	var br: Vector2 = size
	for i in range(3):
		var o: float = 4.0 + i * 4.0
		draw_line(Vector2(br.x - o, br.y - 3.0), Vector2(br.x - 3.0, br.y - o), c, 1.0)


# -----------------------------------------------------------------------
# INTERACCIÓN (mover / redimensionar / contraer)
# -----------------------------------------------------------------------

func _on_header_gui_input(event: InputEvent) -> void:
	if not movable:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging_move = event.pressed
	elif event is InputEventMouseMotion and _dragging_move:
		position += (event as InputEventMouseMotion).relative
		_clamp_to_viewport()


func _on_grip_gui_input(event: InputEvent) -> void:
	if not resizable:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_resizing = event.pressed
	elif event is InputEventMouseMotion and _resizing:
		var ns: Vector2 = size + (event as InputEventMouseMotion).relative
		ns.x = maxf(ns.x, float(min_box_size.x))
		ns.y = maxf(ns.y, float(min_box_size.y))
		size = ns
		_expanded_size = ns
		_clamp_to_viewport()
		queue_redraw()


func _toggle_collapse() -> void:
	_collapsed = not _collapsed
	_chart.visible = not _collapsed
	_grip.visible = not _collapsed
	if _collapsed:
		_expanded_size = size
		size = Vector2(size.x, _header.get_combined_minimum_size().y + 14.0)
	else:
		size = _expanded_size
	_collapse_btn.text = "▸" if _collapsed else "▾"
	_clamp_to_viewport()
	queue_redraw()


func _clamp_to_viewport() -> void:
	var vp: Vector2 = get_viewport_rect().size
	size.x = minf(size.x, vp.x)
	size.y = minf(size.y, vp.y)
	position.x = clampf(position.x, 0.0, maxf(0.0, vp.x - size.x))
	position.y = clampf(position.y, 0.0, maxf(0.0, vp.y - size.y))


# -----------------------------------------------------------------------
# DATOS (igual que antes)
# -----------------------------------------------------------------------

func reset() -> void:
	_rooms.clear()
	_room_ids.clear()
	_events.clear()
	if _room_selector != null:
		_room_selector.clear()
	_refresh()


func seed_rooms(state: Dictionary) -> void:
	for key in state.keys():
		var ks: String = String(key)
		if not ks.is_valid_int():
			continue
		var rs = state[key]
		if typeof(rs) != TYPE_DICTIONARY:
			continue
		var rid: int = int(ks)
		if not _rooms.has(rid):
			var cols_acc: Dictionary = {}
			for c in NCW.WANTED_COLS:
				cols_acc[c] = []
			_rooms[rid] = {"name": String(rs.get("name", str(rid))), "times": [], "cols": cols_acc}
			_room_ids.append(rid)
	_room_ids.sort()
	_rebuild_room_selector()


func sample(sim_time_s: float, state: Dictionary) -> void:
	var new_room: bool = false
	for key in state.keys():
		var ks: String = String(key)
		if not ks.is_valid_int():
			continue
		var rs = state[key]
		if typeof(rs) != TYPE_DICTIONARY:
			continue
		var rid: int = int(ks)
		if not _rooms.has(rid):
			var cols_acc: Dictionary = {}
			for c in NCW.WANTED_COLS:
				cols_acc[c] = []
			_rooms[rid] = {"name": String(rs.get("name", str(rid))), "times": [], "cols": cols_acc}
			_room_ids.append(rid)
			new_room = true
		var room: Dictionary = _rooms[rid]
		(room["times"] as Array).append(sim_time_s)
		var cols_ref: Dictionary = room["cols"]
		for c in NCW.WANTED_COLS:
			(cols_ref[c] as Array).append(float(rs.get(c, 0.0)))

	if new_room:
		_room_ids.sort()
		_rebuild_room_selector()
	if visible and not _collapsed:
		_refresh()


func add_event(sim_time_s: float, event_type: String) -> void:
	_events.append({"t": sim_time_s, "type": event_type})


func _on_selection_changed(_idx: int) -> void:
	_refresh()


func _rebuild_room_selector() -> void:
	var prev: int = _room_selector.selected
	_room_selector.clear()
	for rid in _room_ids:
		_room_selector.add_item("R%s %s" % [str(rid), String(_rooms[rid].get("name", str(rid)))])
	if prev >= 0 and prev < _room_ids.size():
		_room_selector.select(prev)
	elif not _room_ids.is_empty():
		_room_selector.select(0)


func _refresh() -> void:
	if _chart == null:
		return
	if _room_ids.is_empty():
		_chart.set_data([], "valor", [], [])
		return
	var ri: int = clampi(_room_selector.selected, 0, _room_ids.size() - 1)
	var mi: int = clampi(_metric_selector.selected, 0, NCW.METRIC_GROUPS.size() - 1)
	var rid = _room_ids[ri]
	var room: Dictionary = _rooms[rid]
	var group: Dictionary = NCW.METRIC_GROUPS[mi]
	var times_packed: PackedFloat32Array = PackedFloat32Array(room["times"])

	var series: Array = []
	var ci: int = 0
	for spec in group["series"]:
		var col_name: String = spec[0]
		var cols: Dictionary = room["cols"]
		if not cols.has(col_name):
			continue
		var scale: float = float(spec[3])
		var raw: Array = cols[col_name]
		var ys: PackedFloat32Array = PackedFloat32Array()
		if scale != 1.0:
			for v in raw:
				ys.append(v * scale)
		else:
			ys = PackedFloat32Array(raw)
		series.append({
			"name": String(spec[1]),
			"color": NCW.PALETTE[ci % NCW.PALETTE.size()],
			"x": times_packed,
			"y": ys,
			"dash": false,
			"visible": true,
		})
		ci += 1

	var events_for_chart: Array = []
	for ev in _events:
		events_for_chart.append({
			"t": ev["t"],
			"color": NCW.EVENT_COLORS.get(ev["type"], Color(0.6, 0.6, 0.6)),
			"label": String(ev["type"]),
		})

	_chart.set_data(series, String(group["y"]), group.get("thresholds", []), events_for_chart)

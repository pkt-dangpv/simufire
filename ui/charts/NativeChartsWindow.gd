extends Window
class_name NativeChartsWindow

# ============================================================
# NATIVE CHARTS WINDOW (post-simulación, sin navegador)
# ------------------------------------------------------------
# Visor interactivo nativo. Lee un sim_log.csv (+ sim_log.txt para
# eventos) y permite SUPERPONER varias series de cualquier sala y
# métrica para compararlas en la misma gráfica.
#
#   open(csv_path, txt_path) -> parsea y muestra
# ============================================================

const InteractiveLineChartScript := preload("res://ui/charts/InteractiveLineChart.gd")
const SFTheme := preload("res://ui/SimuFireTheme.gd")

# Grupos de métrica: [columna_csv, etiqueta, dash_en_solo, escala]
# El color se asigna por paleta al añadir, para distinguir trazas.
const METRIC_GROUPS: Array = [
	{"name": "HRR (kW)", "y": "HRR (kW)", "series": [
		["hrr_kw", "HRR", false, 1.0]], "thresholds": []},
	{"name": "Temperaturas (C)", "y": "Temperatura (C)", "series": [
		["temp_upper_c", "Capa alta", false, 1.0],
		["temp_lower_c", "Capa baja", false, 1.0]], "thresholds": []},
	{"name": "Capas / alturas (m)", "y": "Altura (m)", "series": [
		["smoke_layer_m", "Capa humo", false, 1.0],
		["hot_layer_m", "Capa caliente", true, 1.0],
		["layer_150c_m", "Isoterma 150C", true, 1.0]], "thresholds": []},
	{"name": "O2 (%)", "y": "O2 (%)", "series": [
		["o2", "O2", false, 100.0]],
		"thresholds": [{"y": 17.0, "color": Color(1, 0.35, 0.35, 0.6), "label": "17% O2"}]},
	{"name": "CO (ppm)", "y": "CO (ppm)", "series": [
		["co_ppm", "CO total", false, 1.0],
		["co_upper_ppm", "CO upper", true, 1.0]],
		"thresholds": [{"y": 1500.0, "color": Color(1, 0.35, 0.35, 0.6), "label": "1500 ppm"}]},
	{"name": "CO2 (ppm)", "y": "CO2 (ppm)", "series": [
		["co2_ppm", "CO2", false, 1.0]], "thresholds": []},
	{"name": "FED", "y": "FED", "series": [
		["fed", "FED", false, 1.0]],
		"thresholds": [
			{"y": 1.0, "color": Color("firebrick"), "label": "FED=1 incap."},
			{"y": 3.0, "color": Color("darkred"), "label": "FED=3 letal"}]},
	{"name": "SVV / Vis (%)", "y": "SVV / Vis (%)", "series": [
		["svv_worst_pct", "SVV", false, 1.0],
		["visibility_m", "Vis (% de 30m)", true, 3.3333]], "thresholds": []},
]

const WANTED_COLS: Array = [
	"hrr_kw", "temp_upper_c", "temp_lower_c", "smoke_layer_m", "hot_layer_m",
	"layer_150c_m", "o2", "co_ppm", "co_upper_ppm", "co2_ppm", "fed",
	"svv_worst_pct", "visibility_m",
]

# Paleta de series: arranca con los acentos de marca (naranja, azul, verde,
# amarillo de SimuFireTheme) y sigue con tonos distinguibles.
const PALETTE: Array = [
	Color("#ff4000"), Color("#00b3e0"), Color("#8cff5c"), Color("#ffc700"),
	Color("#e78ac3"), Color("#a6761d"), Color("#66c2a5"), Color("#8da0cb"),
	Color("#d6616b"), Color("#b3b3b3"), Color("#756bb1"), Color("#1b9e77"),
]

const EVENT_COLORS: Dictionary = {
	"glass_break": Color("#e74c3c"), "door_open": Color("#27ae60"),
	"door_close": Color("#e67e22"), "window_open": Color("#2980b9"),
	"window_close": Color("#8e44ad"), "sim_end": Color("#95a5a6"),
}

var _room_selector: OptionButton = null
var _metric_selector: OptionButton = null
var _chart: Control = null
var _header: Label = null

var _rooms: Dictionary = {}     # rid -> { name, times: PackedFloat32Array, cols: {c: PF32} }
var _room_ids: Array = []
var _events: Array = []

var _active_series: Array = []  # dicts listos para el chart
var _active_groups: Array = []  # índice de grupo por cada trace (para umbrales/label Y)
var _color_cursor: int = 0


func _init() -> void:
	title = "Gráficas interactivas"
	size = Vector2i(1200, 720)
	min_size = Vector2i(820, 520)
	close_requested.connect(hide)

	var base := Control.new()
	base.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	base.theme = SFTheme.build_theme()
	add_child(base)

	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = SFTheme.BG
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	base.add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	base.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	margin.add_child(root)

	# --- Cabecera de marca: logo + SIMUFIRE ---
	root.add_child(_build_brand_header())

	_header = Label.new()
	_header.text = "—"
	_header.add_theme_color_override("font_color", SFTheme.MUTED)
	root.add_child(_header)

	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	root.add_child(bar)

	bar.add_child(_mk_label("Habitación:"))
	_room_selector = OptionButton.new()
	_room_selector.custom_minimum_size = Vector2(200, 30)
	bar.add_child(_room_selector)

	bar.add_child(_mk_label("Métrica:"))
	_metric_selector = OptionButton.new()
	_metric_selector.custom_minimum_size = Vector2(190, 30)
	for g in METRIC_GROUPS:
		_metric_selector.add_item(String(g["name"]))
	bar.add_child(_metric_selector)

	var btn_add := _mk_button("＋ Añadir")
	btn_add.pressed.connect(_on_add)
	bar.add_child(btn_add)

	var btn_add_all := _mk_button("Añadir todas las salas")
	btn_add_all.pressed.connect(_on_add_all_rooms)
	bar.add_child(btn_add_all)

	var btn_clear := _mk_button("Limpiar")
	btn_clear.pressed.connect(_on_clear)
	bar.add_child(btn_clear)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)

	var hint := _mk_label("Arrastra para zoom · doble clic reset · clic en leyenda oculta")
	hint.add_theme_color_override("font_color", SFTheme.MUTED)
	bar.add_child(hint)

	_chart = InteractiveLineChartScript.new()
	_chart.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chart.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_chart)


# -----------------------------------------------------------------------
# API
# -----------------------------------------------------------------------

func open(csv_path: String, txt_path: String = "") -> bool:
	_rooms.clear()
	_room_ids.clear()
	_events.clear()
	_on_clear()

	if not FileAccess.file_exists(csv_path):
		_header.text = "No se encontró el CSV: %s" % csv_path
		_popup_bounded()
		return false
	if not _parse_csv(csv_path):
		_header.text = "No se pudo leer el CSV: %s" % csv_path
		_popup_bounded()
		return false
	if txt_path != "" and FileAccess.file_exists(txt_path):
		_parse_events(txt_path)

	_header.text = "Fuente: %s   ·   %d habitaciones   ·   %d eventos" % [
		csv_path, _room_ids.size(), _events.size()]

	_room_selector.clear()
	for rid in _room_ids:
		_room_selector.add_item("ROOM %s  %s" % [str(rid), String(_rooms[rid].get("name", str(rid)))])
	if _metric_selector.selected < 0:
		_metric_selector.select(0)
	if not _room_ids.is_empty():
		_room_selector.select(0)
		_add_traces_for(_room_ids[0], _metric_selector.selected)  # arranca con algo visible

	_refresh_chart()
	_popup_bounded()
	return true


## Muestra la ventana centrada y acotada a la ventana del juego (con márgenes).
func _popup_bounded() -> void:
	var bounded := Vector2i(1000, 640)
	var tree := get_tree()
	if tree != null and tree.root != null:
		var rw: Window = tree.root
		bounded = Vector2i(
			clampi(rw.size.x - 80, 640, rw.size.x),
			clampi(rw.size.y - 80, 460, rw.size.y))
	popup_centered(bounded)


# -----------------------------------------------------------------------
# TRAZAS
# -----------------------------------------------------------------------

func _on_add() -> void:
	if _room_ids.is_empty():
		return
	var ri: int = clampi(_room_selector.selected, 0, _room_ids.size() - 1)
	_add_traces_for(_room_ids[ri], _metric_selector.selected)
	_refresh_chart()


func _on_add_all_rooms() -> void:
	for rid in _room_ids:
		_add_traces_for(rid, _metric_selector.selected)
	_refresh_chart()


func _on_clear() -> void:
	_active_series.clear()
	_active_groups.clear()
	_color_cursor = 0
	_refresh_chart()


func _add_traces_for(rid, group_idx: int) -> void:
	if not _rooms.has(rid):
		return
	var gi: int = clampi(group_idx, 0, METRIC_GROUPS.size() - 1)
	var group: Dictionary = METRIC_GROUPS[gi]
	var room: Dictionary = _rooms[rid]
	var cols: Dictionary = room["cols"]
	var rname: String = String(room.get("name", str(rid)))
	for spec in group["series"]:
		var col_name: String = spec[0]
		if not cols.has(col_name):
			continue
		var scale: float = float(spec[3])
		var ys: PackedFloat32Array = cols[col_name]
		if scale != 1.0:
			var scaled: PackedFloat32Array = PackedFloat32Array()
			for v in ys:
				scaled.append(v * scale)
			ys = scaled
		var color: Color = PALETTE[_color_cursor % PALETTE.size()]
		_color_cursor += 1
		_active_series.append({
			"name": "%s · %s" % [rname, String(spec[1])],
			"color": color,
			"x": room["times"],
			"y": ys,
			"dash": false,
			"visible": true,
		})
		_active_groups.append(gi)


func _refresh_chart() -> void:
	# Umbrales y etiqueta Y solo si todas las trazas comparten grupo.
	var uniform_group: int = -1
	if not _active_groups.is_empty():
		uniform_group = _active_groups[0]
		for g in _active_groups:
			if g != uniform_group:
				uniform_group = -1
				break
	var y_label: String = "valor"
	var thresholds: Array = []
	if uniform_group >= 0:
		y_label = String(METRIC_GROUPS[uniform_group]["y"])
		thresholds = METRIC_GROUPS[uniform_group].get("thresholds", [])
	elif not _active_groups.is_empty():
		y_label = "valor (varias métricas)"

	var events_for_chart: Array = []
	for ev in _events:
		events_for_chart.append({
			"t": ev["t"],
			"color": EVENT_COLORS.get(ev["type"], Color(0.6, 0.6, 0.6)),
			"label": String(ev["type"]),
		})

	_chart.set_data(_active_series, y_label, thresholds, events_for_chart)


# -----------------------------------------------------------------------
# TEMA / WIDGETS
# -----------------------------------------------------------------------

func _build_brand_header() -> Control:
	var brand := HBoxContainer.new()
	brand.add_theme_constant_override("separation", 12)

	# Emblema (icon.svg = solo el hexágono, cuadrado). expand_mode IGNORE_SIZE
	# evita que el TextureRect adopte el tamaño natural del PNG.
	var logo_tex := load("res://icon.svg") as Texture2D
	if logo_tex != null:
		var logo := TextureRect.new()
		logo.texture = logo_tex
		logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		logo.custom_minimum_size = Vector2(32, 32)
		logo.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		brand.add_child(logo)

	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 0)
	title_row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var simu := Label.new()
	simu.text = "SIMU"
	simu.add_theme_font_override("font", SFTheme.title_font())
	simu.add_theme_font_size_override("font_size", 20)
	simu.add_theme_color_override("font_color", SFTheme.TEXT)
	title_row.add_child(simu)
	var fire := Label.new()
	fire.text = "FIRE"
	fire.add_theme_font_override("font", SFTheme.title_font())
	fire.add_theme_font_size_override("font_size", 20)
	fire.add_theme_color_override("font_color", SFTheme.ORANGE)
	title_row.add_child(fire)
	brand.add_child(title_row)

	var subtitle := Label.new()
	subtitle.text = "  Gráficas interactivas"
	subtitle.add_theme_color_override("font_color", SFTheme.MUTED)
	subtitle.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	brand.add_child(subtitle)
	return brand


func _mk_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", SFTheme.TEXT)
	return l


func _mk_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 30)
	return b


# -----------------------------------------------------------------------
# PARSING
# -----------------------------------------------------------------------

func _parse_csv(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var header_line: String = f.get_line()
	if header_line == "":
		return false
	var headers: PackedStringArray = header_line.split(",")
	var idx: Dictionary = {}
	for i in range(headers.size()):
		idx[headers[i].strip_edges()] = i
	if not idx.has("time_s") or not idx.has("room_id"):
		return false

	var col_indices: Dictionary = {}
	for c in WANTED_COLS:
		if idx.has(c):
			col_indices[c] = idx[c]

	# Acumular en Array (referencia): PackedFloat32Array es copy-on-write.
	var acc: Dictionary = {}
	while not f.eof_reached():
		var line: String = f.get_line()
		if line.strip_edges() == "":
			continue
		var parts: PackedStringArray = line.split(",")
		if parts.size() <= int(idx["room_id"]):
			continue
		var rid_str: String = parts[int(idx["room_id"])].strip_edges()
		if not rid_str.is_valid_int():
			continue
		var rid: int = int(rid_str)
		var t: float = float(parts[int(idx["time_s"])])

		if not acc.has(rid):
			var rname: String = ""
			if idx.has("room_name") and parts.size() > int(idx["room_name"]):
				rname = parts[int(idx["room_name"])].strip_edges().trim_prefix("\"").trim_suffix("\"")
			var cols_acc: Dictionary = {}
			for c in col_indices.keys():
				cols_acc[c] = []
			acc[rid] = {"name": rname, "times": [], "cols": cols_acc}
			_room_ids.append(rid)

		var room_acc: Dictionary = acc[rid]
		(room_acc["times"] as Array).append(t)
		var cols_ref: Dictionary = room_acc["cols"]
		for c in col_indices.keys():
			var ci: int = col_indices[c]
			var val: float = 0.0
			if parts.size() > ci:
				val = float(parts[ci])
			(cols_ref[c] as Array).append(val)

	f.close()

	for rid in acc.keys():
		var ra: Dictionary = acc[rid]
		var cols_final: Dictionary = {}
		for c in (ra["cols"] as Dictionary).keys():
			cols_final[c] = PackedFloat32Array(ra["cols"][c])
		_rooms[rid] = {
			"name": ra["name"],
			"times": PackedFloat32Array(ra["times"]),
			"cols": cols_final,
		}

	_room_ids.sort()
	return not _rooms.is_empty()


func _parse_events(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	while not f.eof_reached():
		var line: String = f.get_line().strip_edges()
		if not line.begins_with("EVENT "):
			continue
		var t: float = 0.0
		var etype: String = ""
		for tok in line.split(" ", false):
			if tok.begins_with("t="):
				t = float(tok.substr(2))
			elif tok.begins_with("type="):
				etype = tok.substr(5)
		if etype != "":
			_events.append({"t": t, "type": etype})
	f.close()

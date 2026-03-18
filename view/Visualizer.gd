extends Node2D
class_name Visualizer
## Visualizer:
## - Dibuja habitaciones a partir de rects (en metros) del BuildingModel
## - Pinta capa superior (humo) usando h_layer_m / smoke_mass_kg
## - Dibuja puertas/ventanas (aberturas) como segmentos en el borde compartido
## - Muestra una barra HRR por habitación (debug)

@export var meters_to_px: float = 100.0
@export var wall_thickness: float = 2.0
@export var room_height_m_default: float = 2.4

# Estado recibido desde BuildingModel.emit_state()
# state["0"] = {"h_layer_m":..., "smoke_mass_kg":..., "hrr_kw":...}
var state: Dictionary = {}

# Geometría (en metros): room_id -> Rect2
var rects_m: Dictionary[int, Rect2] = {}

@onready var building: BuildingModel = $"../BuildingModel" as BuildingModel


func _ready() -> void:
	# Cache de geometría y conexión a señal
	if building != null:
		rects_m = building.get_room_rects_m()
		building.state_changed.connect(set_state)
	queue_redraw()


func set_state(s: Dictionary) -> void:
	state = s
	queue_redraw()


func _draw() -> void:
	# Fondo
	draw_rect(Rect2(-50, -50, 4000, 2500), Color(0.10, 0.10, 0.11, 1.0), true)

	# Habitaciones + humo + HRR
	for id: int in rects_m.keys():
		var rm: Rect2 = rects_m[id]
		var rpx: Rect2 = _to_px(rm)

		# Paredes
		draw_rect(rpx, Color(1, 1, 1, 1), false, wall_thickness)

		var rs: Dictionary = state.get(str(id), {})
		if rs.is_empty():
			continue

		var h_layer_m: float = float(rs.get("h_layer_m", room_height_m_default))
		var smoke_kg: float = float(rs.get("smoke_mass_kg", 0.0))
		var hrr_kw: float = float(rs.get("hrr_kw", 0.0))

		var room_h: float = room_height_m_default
		var upper_thick_m: float = maxf(0.0, room_h - h_layer_m)
		var upper_frac: float = clampf(upper_thick_m / room_h, 0.0, 1.0)

		var intensity: float = clampf(0.35 * upper_frac + 0.65 * (smoke_kg / 8.0), 0.0, 1.0)

		if upper_frac > 0.0:
			var smoke_h_px: float = rpx.size.y * upper_frac
			var smoke_rect: Rect2 = Rect2(rpx.position.x, rpx.position.y, rpx.size.x, smoke_h_px)
			draw_rect(smoke_rect, Color(0.32, 0.32, 0.36, 0.30 + 0.55 * intensity), true)

		var bar_w: float = rpx.size.x - 10.0
		var bar_h: float = 6.0
		var bar_frac: float = clampf(hrr_kw / 3000.0, 0.0, 1.0)
		draw_rect(
			Rect2(rpx.position.x + 5.0, rpx.position.y + rpx.size.y - 10.0, bar_w * bar_frac, bar_h),
			Color(1.0, 0.35, 0.15, 0.9),
			true
		)

	_draw_openings()


func _draw_openings() -> void:
	if building == null:
		return

	# Leemos openings del building (array ya tipado allí)
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

		# Si hay habitación B, calculamos borde compartido por intersección de bordes
		if b_exists:
			seg_m = _shared_edge_segment_m(ra, rb)
		else:
			# Exterior: dibujamos una ventana "genérica" en la pared superior del cuarto A
			seg_m = _default_exterior_segment_m(ra, op.width_m)

		if seg_m.size() != 2:
			continue

		var p1: Vector2 = seg_m[0] * meters_to_px
		var p2: Vector2 = seg_m[1] * meters_to_px

		# Color según tipo y apertura
		var alpha: float = 0.25 + 0.75 * clampf(op.open_fraction, 0.0, 1.0)
		var col: Color = Color(0.3, 1.0, 0.4, alpha) if op.type == OpeningModel.Type.DOOR else Color(0.35, 0.7, 1.0, alpha)

		draw_line(p1, p2, col, 4.0)


# Devuelve un segmento (2 puntos) en METROS del borde compartido entre dos rects (si se tocan).
func _shared_edge_segment_m(a: Rect2, b: Rect2) -> PackedVector2Array:
	# Comprobamos si comparten un lado vertical (a derecha de b o viceversa)
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
	# Segmento centrado en pared superior del rect
	var x1: float = r.position.x + (r.size.x - width_m) * 0.5
	var x2: float = x1 + width_m
	var y: float = r.position.y
	return PackedVector2Array([Vector2(x1, y), Vector2(x2, y)])


func _to_px(rm: Rect2) -> Rect2:
	var pos: Vector2 = rm.position * meters_to_px
	var size: Vector2 = rm.size * meters_to_px
	return Rect2(pos, size)

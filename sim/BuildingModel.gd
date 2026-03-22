extends Node
class_name BuildingModel

# ============================================================
# BUILDING MODEL
# ------------------------------------------------------------
# Responsabilidad:
# - almacenar estructura del edificio
# - almacenar condiciones exteriores
# - cargar habitaciones y aperturas desde plantilla
# - ofrecer helpers geométricos / ventilación
#
# NO debe:
# - simular el incendio
# - crear fuego
# - llevar el tiempo
# - emitir estado para UI
# ============================================================

const OUTSIDE_ID: int = -1

# Condiciones exteriores
@export var outside_temp_c: float = 20.0
@export var outside_o2: float = 0.209

# Coeficiente geométrico simple para límite por ventilación
@export var vent_hrr_coeff_kw_per_sqrt_m5: float = 1500.0

# Recursos
var building_template = preload("res://sim/templates/BuildingTemplate.gd").new()

# Datos estructurales
var room_rect_m: Dictionary[int, Rect2] = {}
var rooms: Dictionary = {}
var openings: Array = []

# ============================================================
# READY
# ============================================================

func _ready() -> void:
	_load_from_template(building_template.create_simple_house())

# ============================================================
# GETTERS
# ============================================================

func get_room_rects_m() -> Dictionary[int, Rect2]:
	return room_rect_m

func get_room(room_id: int) -> RoomModel:
	return rooms.get(room_id)

func get_rooms() -> Dictionary:
	return rooms

func get_openings() -> Array:
	return openings

# ============================================================
# CARGA DE PLANTILLA
# ============================================================

func _load_from_template(data: Dictionary) -> void:
	rooms.clear()
	openings.clear()
	room_rect_m.clear()

	var rects_data: Dictionary = data.get("room_rect_m", {})

	# Geometría 2D
	for k in rects_data.keys():
		room_rect_m[int(k)] = rects_data[k] as Rect2

	# Habitaciones
	for room_data in data.get("rooms_data", []):
		var room_id: int = int(room_data["id"])
		var rect_m: Rect2 = rects_data[room_id] as Rect2

		_add_room_from_rect(
			room_id,
			String(room_data["name"]),
			String(room_data["kind"]),
			rect_m,
			float(room_data["height_m"])
		)

	# Aperturas
	for op_data in data.get("openings_data", []):
		var a: int = int(op_data["a"])
		var b: int = int(op_data["b"])
		var width_m: float = float(op_data["width_m"])
		var height_m: float = float(op_data["height_m"])
		var open_fraction: float = float(op_data.get("open_fraction", 1.0))
		var type_str: String = String(op_data.get("type", "door"))

		var op_type: int = OpeningModel.Type.DOOR
		if type_str == "window":
			op_type = OpeningModel.Type.WINDOW

		var op: OpeningModel = OpeningModel.new(a, b, op_type, width_m, height_m, 1.0)
		op.open_fraction = clampf(open_fraction, 0.0, 1.0)

		if op_data.has("sill_m"):
			op.sill_m = float(op_data["sill_m"])

		openings.append(op)

# ============================================================
# CREACIÓN DE HABITACIONES
# ============================================================

func _add_room_from_rect(
	id: int,
	room_name: String,
	kind_name: String,
	rect_m: Rect2,
	height_m: float
) -> void:
	var room: RoomModel = RoomModel.new()

	room.id = id
	room.name = room_name
	room.kind = kind_name

	room.width_m = rect_m.size.x
	room.length_m = rect_m.size.y
	room.height_m = height_m

	room.temp_upper_c = outside_temp_c
	room.temp_lower_c = outside_temp_c
	room.o2 = outside_o2
	room.h_layer_m = height_m

	rooms[id] = room

# ============================================================
# HELPERS GEOMÉTRICOS
# ============================================================

func has_outside_opening(room_id: int) -> bool:
	for op in openings:
		if op.open_fraction <= 0.0:
			continue

		var to_outside: bool = (
			(op.a == room_id and op.b == OUTSIDE_ID) or
			(op.b == room_id and op.a == OUTSIDE_ID)
		)

		if to_outside:
			return true

	return false

func estimate_vent_hrr_kw(room_id: int) -> float:
	var sum_AH_sqrtH: float = 0.0

	for op in openings:
		if op.open_fraction <= 0.0:
			continue

		var connects_outside: bool = (
			(op.a == room_id and op.b == OUTSIDE_ID) or
			(op.b == room_id and op.a == OUTSIDE_ID)
		)

		if not connects_outside:
			continue

		var width: float = maxf(0.0, op.width_m)
		var height: float = maxf(0.0, op.height_m)
		var area_open: float = width * height * clampf(op.open_fraction, 0.0, 1.0)

		sum_AH_sqrtH += area_open * sqrt(height)

	if sum_AH_sqrtH <= 0.0:
		return 0.0

	return vent_hrr_coeff_kw_per_sqrt_m5 * sum_AH_sqrtH

func get_connected_openings(room_id: int) -> Array:
	var result: Array = []

	for op in openings:
		if op.a == room_id or op.b == room_id:
			result.append(op)

	return result

func get_neighbor_room_ids(room_id: int) -> Array[int]:
	var neighbors: Array[int] = []

	for op in openings:
		if op.open_fraction <= 0.0:
			continue

		if op.a == room_id and op.b != OUTSIDE_ID:
			neighbors.append(op.b)
		elif op.b == room_id and op.a != OUTSIDE_ID:
			neighbors.append(op.a)

	return neighbors
extends Node
class_name BuildingModel

const FuelObjectModelScript = preload("res://sim/fire/FuelObjectModel.gd")

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

@export_enum("simple_house", "ghanekar_bedroom_hallway") var template_name: String = "simple_house"

# Datos estructurales
var room_rect_m: Dictionary[int, Rect2] = {}
var rooms: Dictionary = {}
var openings: Array = []

# ============================================================
# READY
# ============================================================

func _ready() -> void:
	match template_name:
		"ghanekar_bedroom_hallway":
			_load_from_template(building_template.create_ghanekar_bedroom_hallway())
		_:
			_load_from_template(building_template.create_simple_house())

# ============================================================
# GETTERS
# ============================================================

func get_room_rects_m() -> Dictionary[int, Rect2]:
	return room_rect_m


func get_room_centroid_m(room_id: int) -> Vector2:
	var rect: Rect2 = room_rect_m.get(room_id, Rect2())
	return rect.position + rect.size * 0.5


func estimate_room_connection_length_m(room_a_id: int, room_b_id: int) -> float:
	if not room_rect_m.has(room_a_id) or not room_rect_m.has(room_b_id):
		return 1.0

	return maxf(0.5, get_room_centroid_m(room_a_id).distance_to(get_room_centroid_m(room_b_id)))

func get_room(room_id: int) -> RoomModel:
	return rooms.get(room_id)

func get_rooms() -> Dictionary:
	return rooms

func get_openings() -> Array:
	return openings

func load_template_data(data: Dictionary) -> void:
	_load_from_template(data)

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
		# Carga de combustible — opcional en template (0.0 = usa default del engine)
		if room_data.has("fuel_energy_MJ"):
			rooms[room_id].fuel_energy_MJ = float(room_data["fuel_energy_MJ"])
		if room_data.has("max_hrr_kw"):
			rooms[room_id].max_hrr_kw = float(room_data["max_hrr_kw"])
		if room_data.has("fuel_objects"):
			rooms[room_id].fuel_objects = _build_fuel_objects(room_data["fuel_objects"])

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
		op.set_open_fraction(open_fraction)
		op.opening_index = openings.size()

		if op_data.has("sill_m"):
			op.sill_m = float(op_data["sill_m"])
		if op_data.has("wall"):
			op.wall_side = String(op_data["wall"]).to_lower()

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
	room.reset_dynamic_state(outside_temp_c, outside_o2)

	rooms[id] = room


func _build_fuel_objects(raw_objects: Variant) -> Array:
	var result: Array = []
	if typeof(raw_objects) != TYPE_ARRAY:
		return result

	for entry in raw_objects:
		if typeof(entry) != TYPE_DICTIONARY:
			continue

		var data: Dictionary = entry
		var obj = FuelObjectModelScript.new()
		obj.id = String(data.get("id", ""))
		obj.name = String(data.get("name", obj.id))
		obj.kind = String(data.get("kind", "generic"))
		obj.footprint_m2 = float(data.get("footprint_m2", 0.0))
		obj.exposed_area_m2 = float(data.get("exposed_area_m2", obj.footprint_m2))
		obj.elevation_m = float(data.get("elevation_m", 0.0))
		obj.fuel_energy_MJ = float(data.get("fuel_energy_MJ", 0.0))
		obj.remaining_fuel_MJ = float(data.get("remaining_fuel_MJ", obj.fuel_energy_MJ))
		obj.max_hrr_kw = float(data.get("max_hrr_kw", 0.0))
		obj.ignition_temp_c = float(data.get("ignition_temp_c", obj.ignition_temp_c))
		obj.ignition_flux_kw_m2 = float(data.get("ignition_flux_kw_m2", obj.ignition_flux_kw_m2))
		obj.smoke_yield_kg_per_MJ = float(data.get("smoke_yield_kg_per_MJ", obj.smoke_yield_kg_per_MJ))
		obj.co_yield_kg_per_MJ = float(data.get("co_yield_kg_per_MJ", obj.co_yield_kg_per_MJ))
		obj.o2_consumption_kg_per_MJ = float(data.get("o2_consumption_kg_per_MJ", obj.o2_consumption_kg_per_MJ))
		obj.is_primary_ignition_source = bool(data.get("is_primary_ignition_source", false))
		result.append(obj)

	return result

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


func get_opening_count() -> int:
	return openings.size()


func get_opening_at(index: int):
	if index < 0 or index >= openings.size():
		return null
	return openings[index]


func set_opening_fraction(index: int, open_fraction: float) -> bool:
	var op: OpeningModel = get_opening_at(index)
	if op == null:
		return false

	op.set_open_fraction(open_fraction)
	return true


func open_opening(index: int) -> bool:
	return set_opening_fraction(index, 1.0)


func close_opening(index: int) -> bool:
	return set_opening_fraction(index, 0.0)


func get_opening_label(index: int) -> String:
	var op: OpeningModel = get_opening_at(index)
	if op == null:
		return "Apertura"

	var prefix: String = "P" if op.type == OpeningModel.Type.DOOR else "V"
	return "%s%02d %s-%s" % [
		prefix,
		index,
		_get_room_display_name(op.a),
		_get_room_display_name(op.b)
	]


func get_opening_status_text(index: int) -> String:
	var op: OpeningModel = get_opening_at(index)
	if op == null:
		return "Sin apertura seleccionada"

	var area_eff_m2: float = op.width_m * op.height_m * clampf(op.open_fraction, 0.0, 1.0)
	return "%s | %.0f%% | Aeff %.2f m2" % [
		op.state_label(),
		op.open_fraction * 100.0,
		area_eff_m2
	]


func build_opening_summaries() -> Array[Dictionary]:
	var summaries: Array[Dictionary] = []
	for index in range(openings.size()):
		var op: OpeningModel = openings[index]
		if op == null:
			continue

		summaries.append({
			"index": index,
			"label": get_opening_label(index),
			"status": get_opening_status_text(index),
			"type": "door" if op.type == OpeningModel.Type.DOOR else "window",
			"state_label": op.state_label(),
			"open_fraction": op.open_fraction,
			"is_exterior": op.is_exterior_opening()
		})

	return summaries


func _get_room_display_name(room_id: int) -> String:
	if room_id == OUTSIDE_ID:
		return "Exterior"

	var room: RoomModel = get_room(room_id)
	if room == null:
		return "Sala %d" % room_id

	if room.name != "":
		return room.name
	return "Sala %d" % room.id

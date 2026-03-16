extends Node
class_name BuildingModel

# ============================================================
# BUILDING MODEL
# ------------------------------------------------------------
# Responsabilidad:
# - guardar estructura del edificio
# - guardar parámetros globales de simulación
# - cargar rooms / openings desde plantilla
# - crear el fuego inicial en la sala de ignición
# - ofrecer helpers al SimulationEngine
#
# NO debe:
# - ejecutar step() de simulación
# - emitir estado para HUD
# - hacer física del incendio
# ============================================================

signal state_changed(state: Dictionary)

const OUTSIDE_ID: int = -1

@export var outside_temp_c: float = 20.0
@export var outside_o2: float = 0.209

# Tiempo
@export var time_scale: float = 1.0
var sim_time_s: float = 0.0

# ============================================================
# TEMPLATE / GEOMETRÍA
# ============================================================

var room_rect_m: Dictionary[int, Rect2] = {}
var rooms: Dictionary = {}
var openings: Array = []

var building_template = preload("res://sim/templates/BuildingTemplate.gd").new()
var smoke_model = preload("res://sim/smoke/SmokeModel.gd").new()
var fire_model_script = preload("res://sim/fire/FireModel.gd")


func get_room_rects_m() -> Dictionary[int, Rect2]:
	return room_rect_m


# ============================================================
# FUEGO BASE
# ============================================================

@export var ignition_room_id: int = 0
@export var alpha_kw_s2: float = 0.0117
@export var hrr_max_kw: float = 3000.0
@export var secondary_hrr_gain_kw: float = 2500.0

# Humo
@export var smoke_yield_kg_per_MJ: float = 0.06
@export var smoke_density_kg_m3: float = 0.9

# Oxígeno
@export var o2_nominal: float = 0.209
@export var o2_min_for_flame: float = 0.12
@export var air_density_kg_m3: float = 1.2
@export var o2_mix_rate: float = 0.12
@export var o2_vent_rate: float = 0.08

# Ventilación-controlado (simple)
@export var vent_hrr_coeff_kw_per_sqrt_m5: float = 1500.0

# Flashover simple
@export var flashover_temp_c: float = 500.0
@export var flashover_layer_m: float = 1.2
@export var flashover_min_hrr_kw: float = 300.0
@export var flashover_hrr_multiplier: float = 2.2
@export var preflash_temp_c: float = 350.0
@export var preflash_layer_m: float = 1.6

# Pérdidas térmicas
@export var upper_to_lower_loss_rate: float = 0.035
@export var upper_to_ambient_loss_rate: float = 0.015
@export var lower_layer_warming_rate: float = 0.020
@export var max_upper_temp_c: float = 900.0

# Ajustes humo / transporte
@export var base_spill_kg_s_per_m2: float = 0.18
@export var temp_push_factor: float = 0.008
@export var max_spill_kg_s: float = 0.9
@export var max_fraction_out_per_s: float = 0.025
@export var layer_relax_down: float = 0.18
@export var layer_relax_up: float = 0.015


# ============================================================
# READY
# ============================================================

func _ready() -> void:
	_sync_smoke_model_settings()
	_load_from_template(building_template.create_simple_house())


# ============================================================
# CONFIGURACIÓN DE SMOKE MODEL
# ============================================================

func _sync_smoke_model_settings() -> void:
	smoke_model.smoke_density_kg_m3 = smoke_density_kg_m3
	smoke_model.base_spill_kg_s_per_m2 = base_spill_kg_s_per_m2
	smoke_model.temp_push_factor = temp_push_factor
	smoke_model.max_spill_kg_s = max_spill_kg_s
	smoke_model.max_fraction_out_per_s = max_fraction_out_per_s
	smoke_model.layer_relax_down = layer_relax_down
	smoke_model.layer_relax_up = layer_relax_up


# ============================================================
# CARGA DE PLANTILLA
# ============================================================

func _load_from_template(data: Dictionary) -> void:
	rooms.clear()
	openings.clear()
	room_rect_m.clear()

	var rects_data: Dictionary = data.get("room_rect_m", {})

	for k in rects_data.keys():
		room_rect_m[int(k)] = rects_data[k] as Rect2

	for room_data in data.get("rooms_data", []):
		_add_room_from_rect(
			int(room_data["id"]),
			String(room_data["name"]),
			String(room_data["kind"]),
			rects_data[int(room_data["id"])] as Rect2,
			float(room_data["height_m"])
		)

	for op_data in data.get("openings_data", []):
		var a: int = int(op_data["a"])
		var b: int = int(op_data["b"])
		var width_m: float = float(op_data["width_m"])
		var height_m: float = float(op_data["height_m"])
		var open_fraction: float = float(op_data["open_fraction"])
		var type_str: String = String(op_data["type"])

		var op_type: int = OpeningModel.Type.DOOR
		if type_str == "window":
			op_type = OpeningModel.Type.WINDOW

		var op: OpeningModel = OpeningModel.new(a, b, op_type, width_m, height_m, 1.0)
		op.open_fraction = open_fraction

		if op_data.has("sill_m"):
			op.sill_m = float(op_data["sill_m"])

		openings.append(op)

	# Crear fuego inicial en la sala de ignición
	var ignition_room: RoomModel = rooms.get(ignition_room_id)
	if ignition_room != null:
		var fire: FireModel = fire_model_script.new()
		ignition_room.fire = fire

		fire.growth_alpha_kw_s2 = alpha_kw_s2
		fire.max_hrr_kw = hrr_max_kw
		fire.secondary_hrr_gain_kw = secondary_hrr_gain_kw
		fire.flashover_hrr_multiplier = flashover_hrr_multiplier
		fire.flashover_min_hrr_kw = flashover_min_hrr_kw
		fire.o2_nominal = o2_nominal
		fire.o2_min_for_flame = o2_min_for_flame
		fire.smoke_yield_kg_per_MJ = smoke_yield_kg_per_MJ


func _add_room_from_rect(id: int, room_name: String, kind_name: String, rect_m: Rect2, height_m: float) -> void:
	var r: RoomModel = RoomModel.new()
	r.id = id
	r.name = room_name
	r.kind = kind_name
	r.width_m = rect_m.size.x
	r.length_m = rect_m.size.y
	r.height_m = height_m
	r.h_layer_m = height_m
	r.o2 = o2_nominal

	rooms[id] = r


# ============================================================
# HELPERS DE VENTILACIÓN / GEOMETRÍA
# ============================================================

func _has_outside_opening(room_id: int) -> bool:
	for op in openings:
		if op.open_fraction <= 0.0:
			continue

		var to_outside: bool = \
			(op.a == room_id and op.b == OUTSIDE_ID) or \
			(op.b == room_id and op.a == OUTSIDE_ID)

		if to_outside:
			return true

	return false


func _estimate_vent_hrr_kw(room_id: int) -> float:
	var sum_AH_sqrtH: float = 0.0

	for op in openings:
		if op.open_fraction <= 0.0:
			continue

		var connects_outside: bool = \
			(op.a == room_id and op.b == OUTSIDE_ID) or \
			(op.b == room_id and op.a == OUTSIDE_ID)

		if not connects_outside:
			continue

		var width: float = maxf(0.0, op.width_m)
		var height: float = maxf(0.0, op.height_m)
		var area_open: float = width * height * clampf(op.open_fraction, 0.0, 1.0)

		sum_AH_sqrtH += area_open * sqrt(height)

	if sum_AH_sqrtH <= 0.0:
		return hrr_max_kw + secondary_hrr_gain_kw

	return vent_hrr_coeff_kw_per_sqrt_m5 * sum_AH_sqrtH
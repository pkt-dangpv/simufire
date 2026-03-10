extends Node
class_name BuildingModel

signal state_changed(state: Dictionary)

const OUTSIDE_ID: int = -1

@export var outside_temp_c: float = 20.0
@export var outside_o2: float = 0.209

# Tiempo
@export var time_scale: float = 1.0
var sim_time_s: float = 0.0

# -------------------------
# Template / geometría
# -------------------------
var room_rect_m: Dictionary[int, Rect2] = {}
var rooms: Dictionary = {}
var openings: Array = []

var building_template = preload("res://sim/templates/BuildingTemplate.gd").new()
var smoke_model = preload("res://sim/SmokeModel.gd").new()

func get_room_rects_m() -> Dictionary[int, Rect2]:
	return room_rect_m


# -------------------------
# Fuego base
# -------------------------
@export var ignition_room_id: int = 0
@export var alpha_kw_s2: float = 0.0117
@export var hrr_max_kw: float = 3000.0
@export var secondary_hrr_gain_kw: float = 2500.0
var fire_time_s: float = 0.0

# Humo
@export var smoke_yield_kg_per_MJ: float = 0.06
@export var smoke_density_kg_m3: float = 0.9

# Oxígeno
@export var o2_nominal: float = 0.209
@export var o2_min_for_flame: float = 0.12
@export var air_density_kg_m3: float = 1.2
@export var o2_mix_rate: float = 0.12
@export var o2_vent_rate: float = 0.08

# Ventilación-controlado (muy simple)
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

# Ajustes humo/transporte (se copian al SmokeModel)
@export var base_spill_kg_s_per_m2: float = 0.18
@export var temp_push_factor: float = 0.008
@export var max_spill_kg_s: float = 0.9
@export var max_fraction_out_per_s: float = 0.025
@export var layer_relax_down: float = 0.18
@export var layer_relax_up: float = 0.015


func _ready() -> void:
	_sync_smoke_model_settings()
	_load_from_template(building_template.create_simple_house())


func _physics_process(delta: float) -> void:
	var sim_delta: float = delta * time_scale
	sim_time_s += sim_delta
	step(sim_delta)
	emit_state()


func _sync_smoke_model_settings() -> void:
	smoke_model.smoke_density_kg_m3 = smoke_density_kg_m3
	smoke_model.base_spill_kg_s_per_m2 = base_spill_kg_s_per_m2
	smoke_model.temp_push_factor = temp_push_factor
	smoke_model.max_spill_kg_s = max_spill_kg_s
	smoke_model.max_fraction_out_per_s = max_fraction_out_per_s
	smoke_model.layer_relax_down = layer_relax_down
	smoke_model.layer_relax_up = layer_relax_up


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


func _add_room_from_rect(id: int, room_name: String, kind: String, rect_m: Rect2, height_m: float) -> void:
	var area_m2: float = rect_m.size.x * rect_m.size.y
	var vol_m3: float = area_m2 * height_m

	var r: RoomModel = RoomModel.new(id, room_name, kind, vol_m3, height_m)
	r.o2 = o2_nominal
	rooms[id] = r


# -------------------------
# SIM STEP
# -------------------------
func step(delta: float) -> void:
	# Clamp inicial
	for r in rooms.values():
		r.clamp_state()

	# Fuego principal
	_apply_test_fire(delta)

	# Deltas de intercambio
	var d_smoke: Dictionary = {}
	var d_energy: Dictionary = {}
	var d_o2: Dictionary = {}

	for op in openings:
		smoke_model.process_opening(
			op,
			rooms,
			outside_temp_c,
			OUTSIDE_ID,
			delta,
			d_smoke,
			d_energy,
			d_o2,
			Callable(self, "_mix_o2"),
			Callable(self, "_ventilate_o2_to_outside")
		)

	# Aplicar humo
	for id in d_smoke.keys():
		if id == OUTSIDE_ID:
			continue
		var rs: RoomModel = rooms.get(id)
		if rs != null:
			rs.add_upper_smoke(d_smoke[id])

	# Aplicar energía
	for id2 in d_energy.keys():
		if id2 == OUTSIDE_ID:
			continue
		var re: RoomModel = rooms.get(id2)
		if re != null:
			re.add_upper_energy(d_energy[id2])

	# Aplicar O2
	for id3 in d_o2.keys():
		if id3 == OUTSIDE_ID:
			continue
		var ro: RoomModel = rooms.get(id3)
		if ro != null:
			ro.o2 = clampf(ro.o2 + d_o2[id3], 0.0, o2_nominal)

	# Recalcular capa de humo
	for r2 in rooms.values():
		smoke_model.update_layer_height(r2)

	# Pérdidas térmicas
	for rt in rooms.values():
		_apply_thermal_losses(rt, delta)

	# Flashover
	for rfo in rooms.values():
		_update_flashover(rfo)

	# Clamp final
	for r3 in rooms.values():
		r3.clamp_state()


# -------------------------
# Fuego
# -------------------------
func _apply_test_fire(delta: float) -> void:
	fire_time_s += delta

	var R: RoomModel = rooms.get(ignition_room_id)
	if R == null:
		return

	var current_hrr_cap_kw: float = hrr_max_kw
	if R.flashover_triggered:
		current_hrr_cap_kw += secondary_hrr_gain_kw

	var hrr_t2_kw: float = alpha_kw_s2 * fire_time_s * fire_time_s
	hrr_t2_kw = minf(hrr_t2_kw, current_hrr_cap_kw)

	var hrr_kw: float = hrr_t2_kw

	# limitar por ventilación solo si hay huecos abiertos al exterior y el fuego ya es serio
	if hrr_t2_kw > 200.0 and _has_outside_opening(ignition_room_id):
		var hrr_vent_kw: float = _estimate_vent_hrr_kw(ignition_room_id)
		hrr_kw = minf(hrr_t2_kw, hrr_vent_kw)

	# refuerzo post-flashover
	if R.flashover_triggered:
		hrr_kw = minf(
			maxf(hrr_kw, flashover_min_hrr_kw * flashover_hrr_multiplier),
			current_hrr_cap_kw
		)

	R.hrr_kw = hrr_kw

	# humo
	smoke_model.generate_fire_smoke(R, hrr_kw, delta, smoke_yield_kg_per_MJ)

	# energía directa del fuego a la capa upper
	R.add_upper_energy(hrr_kw * delta)


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

	# si no hay ventilación exterior abierta, no capar aquí
	if sum_AH_sqrtH <= 0.0:
		return hrr_max_kw + secondary_hrr_gain_kw

	return vent_hrr_coeff_kw_per_sqrt_m5 * sum_AH_sqrtH


# -------------------------
# Térmico
# -------------------------
func _apply_thermal_losses(room: RoomModel, delta: float) -> void:
	# Upper pierde hacia lower
	var excess_to_lower: float = maxf(0.0, room.temp_upper_c - room.temp_lower_c)
	room.temp_upper_c -= excess_to_lower * upper_to_lower_loss_rate * delta

	# Upper pierde hacia ambiente
	var excess_to_ambient: float = maxf(0.0, room.temp_upper_c - outside_temp_c)
	room.temp_upper_c -= excess_to_ambient * upper_to_ambient_loss_rate * delta

	# Lower se calienta un poco con upper
	var target_lower: float = minf(room.temp_upper_c, outside_temp_c + 120.0)
	room.temp_lower_c = lerpf(room.temp_lower_c, target_lower, lower_layer_warming_rate * delta)

	room.temp_upper_c = clampf(room.temp_upper_c, room.temp_lower_c, max_upper_temp_c)


# -------------------------
# Flashover
# -------------------------
func _update_flashover(room: RoomModel) -> void:
	if room == null:
		return

	room.pre_flashover = (
		room.temp_upper_c >= preflash_temp_c
		and room.h_layer_m <= preflash_layer_m
	)

	if room.flashover_triggered:
		return

	if room.temp_upper_c >= flashover_temp_c \
	and room.h_layer_m <= flashover_layer_m \
	and room.hrr_kw >= flashover_min_hrr_kw:
		room.flashover_triggered = true


# -------------------------
# O2
# -------------------------
func _mix_o2(
	from_id: int,
	from_room: RoomModel,
	to_id: int,
	to_room: RoomModel,
	dm: float,
	d_o2: Dictionary
) -> void:
	var air_from: float = air_density_kg_m3 * from_room.volume_m3
	var air_to: float = air_density_kg_m3 * to_room.volume_m3
	var denom: float = maxf(1.0, air_from + air_to)

	var mix: float = clampf(o2_mix_rate * (dm / denom) * 50.0, 0.0, 0.25)

	var o2a: float = from_room.o2
	var o2b: float = to_room.o2

	var new_a: float = lerpf(o2a, o2b, mix)
	var new_b: float = lerpf(o2b, o2a, mix)

	_accum(d_o2, from_id, new_a - o2a)
	_accum(d_o2, to_id, new_b - o2b)


func _ventilate_o2_to_outside(
	room_id: int,
	room: RoomModel,
	op: OpeningModel,
	dm: float,
	d_o2: Dictionary
) -> void:
	var vent: float = clampf(o2_vent_rate * op.open_fraction * (dm / maxf(0.01, smoke_model.max_spill_kg_s)), 0.0, 0.25)
	var new_o2: float = lerpf(room.o2, o2_nominal, vent)
	_accum(d_o2, room_id, new_o2 - room.o2)


func _accum(dict: Dictionary, key: int, value: float) -> void:
	dict[key] = dict.get(key, 0.0) + value


# -------------------------
# HUD / salida
# -------------------------
func emit_state() -> void:
	var out: Dictionary = {}
	out["sim_time_s"] = sim_time_s

	for rid in rooms.keys():
		var r: RoomModel = rooms[rid]
		out[str(rid)] = {
			"name": r.name,
			"kind": r.kind,
			"h_layer_m": r.h_layer_m,
			"temp_upper_c": r.temp_upper_c,
			"temp_lower_c": r.temp_lower_c,
			"o2": r.o2,
			"smoke_mass_kg": r.smoke_mass_kg,
			"hrr_kw": r.hrr_kw,
			"pre_flashover": r.pre_flashover,
			"flashover_triggered": r.flashover_triggered
		}

	state_changed.emit(out)

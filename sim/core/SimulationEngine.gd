extends Node
class_name SimulationEngine

# ============================================================
# SIMULATION ENGINE
# ------------------------------------------------------------
# Responsabilidad:
# - llevar el tiempo de simulación
# - coordinar subsistemas
# - crear ignición inicial
# - actualizar fuego, O2, temperatura y humo
# - exponer estado agregado
# ============================================================

@export var building_path: NodePath

var building: BuildingModel
var smoke_model: SmokeModel = SmokeModel.new()

const o2_consumption_kg_per_MJ: float = 0.35
const o2_nominal: float = 0.209

# ============================================================
# TIEMPO
# ============================================================

@export var time_scale: float = 5.0
var sim_time_s: float = 0.0

# ============================================================
# CONTABILIDAD GLOBAL DEL HUMO
# ============================================================

var smoke_generated_total_kg: float = 0.0
var smoke_vented_total_kg: float = 0.0

# ============================================================
# IGNICIÓN INICIAL
# ============================================================

@export var ignition_room_id: int = 0
@export var auto_ignite_on_ready: bool = true

# ============================================================
# PARÁMETROS BASE DEL FUEGO
# ============================================================

@export var fire_alpha_kw_s2: float = 0.12
@export var fire_max_hrr_kw: float = 3000.0
@export var fire_secondary_hrr_gain_kw: float = 2500.0

@export var fire_o2_nominal: float = 0.209
@export var fire_o2_min_for_flame: float = 0.10
@export var fire_o2_consumption_kg_per_MJ: float = 0.20
@export var fire_smoke_yield_kg_per_MJ: float = 0.06

@export var fire_flashover_hrr_multiplier: float = 2.2
@export var fire_flashover_min_hrr_kw: float = 300.0

# ============================================================
# FLASHOVER SIMPLE
# ============================================================

@export var flashover_temp_c: float = 500.0
@export var flashover_layer_m: float = 1.2

# ============================================================
# AJUSTES TÉRMICOS
# ============================================================

@export var upper_to_lower_loss_rate: float = 0.025
@export var upper_to_ambient_loss_rate: float = 0.008
@export var lower_layer_warming_rate: float = 0.012
@export var max_upper_temp_c: float = 900.0

# ============================================================
# OXÍGENO / MEZCLA
# ============================================================

@export var o2_mix_rate: float = 0.02
@export var o2_vent_rate: float = 0.08

# ============================================================
# AJUSTES DE HUMO (se copian al SmokeModel)
# ============================================================

@export var smoke_density_kg_m3: float = 0.3
@export var base_spill_kg_s_per_m2: float = 0.18
@export var temp_push_factor: float = 0.008
@export var max_spill_kg_s: float = 0.9
@export var max_fraction_out_per_s: float = 0.025
@export var layer_relax_down: float = 0.18
@export var layer_relax_up: float = 0.015

# ============================================================
# REGISTRO DE VALORES
# ============================================================

@export var enable_logging: bool = true
@export var log_interval_s: float = 10.0
@export var log_file_path: String = "user://sim_log.txt"

var _next_log_time_s: float = 0.0

# ============================================================
# READY
# ============================================================

func _ready() -> void:
	_resolve_building()
	_sync_smoke_model_settings()
	_reset_log_file()

	if auto_ignite_on_ready:
		ignite_room(ignition_room_id)

	print(ProjectSettings.globalize_path(log_file_path))

# ============================================================
# REINICIAR LOG
# ============================================================

func _reset_log_file() -> void:
	if not enable_logging:
		return

	var file := FileAccess.open(log_file_path, FileAccess.WRITE)
	if file == null:
		push_error("No se pudo crear/resetear el log: " + log_file_path)
		return

	file.store_line("SIMULATION LOG")
	file.store_line("")
	file.close()

	_next_log_time_s = 0.0

# ============================================================
# SETUP
# ============================================================

func _resolve_building() -> void:
	if not building_path.is_empty():
		building = get_node_or_null(building_path) as BuildingModel

	if building == null:
		push_error("SimulationEngine: no se encontró BuildingModel en building_path")

func _sync_smoke_model_settings() -> void:
	smoke_model.smoke_density_kg_m3 = smoke_density_kg_m3
	smoke_model.base_spill_kg_s_per_m2 = base_spill_kg_s_per_m2
	smoke_model.temp_push_factor = temp_push_factor
	smoke_model.max_spill_kg_s = max_spill_kg_s
	smoke_model.max_fraction_out_per_s = max_fraction_out_per_s
	smoke_model.layer_relax_down = layer_relax_down
	smoke_model.layer_relax_up = layer_relax_up

# ============================================================
# STEP PRINCIPAL
# ============================================================

func step(delta: float) -> void:
	if building == null:
		return

	var dt: float = maxf(0.0, delta * time_scale)
	if dt <= 0.0:
		return

	sim_time_s += dt

	_step_fire(dt)
	_step_oxygen(dt)
	_step_temperature(dt)
	_step_smoke(dt)
	_clamp_rooms()
	_maybe_log_state()

# ============================================================
# IGNICIÓN
# ============================================================

func ignite_room(room_id: int) -> void:
	if building == null:
		return

	var room: RoomModel = building.get_room(room_id)
	if room == null:
		return

	if room.fire != null:
		return

	var fire: FireModel = FireModel.new()
	fire.growth_alpha_kw_s2 = fire_alpha_kw_s2
	fire.max_hrr_kw = fire_max_hrr_kw
	fire.secondary_hrr_gain_kw = fire_secondary_hrr_gain_kw
	fire.flashover_hrr_multiplier = fire_flashover_hrr_multiplier
	fire.flashover_min_hrr_kw = fire_flashover_min_hrr_kw
	fire.o2_nominal = fire_o2_nominal
	fire.o2_min_for_flame = fire_o2_min_for_flame
	fire.smoke_yield_kg_per_MJ = fire_smoke_yield_kg_per_MJ
	fire.o2_consumption_kg_per_MJ = fire_o2_consumption_kg_per_MJ
	fire.remaining_fuel_MJ = fire.fuel_energy_MJ

	room.fire = fire
	room.fire_time_s = 0.0
	room.flashover_triggered = false

# ============================================================
# FUEGO
# ============================================================

func _step_fire(dt: float) -> void:
	for room_id in building.get_rooms().keys():
		var room: RoomModel = building.get_room(room_id)
		if room == null:
			continue

		if room.fire == null:
			room.hrr_kw = 0.0
			room.smoke_prod_kg_s = 0.0
			continue

		var fire: FireModel = room.fire

		room.fire_time_s += dt

		var hrr_target_kw: float = fire.compute_hrr_kw(room.fire_time_s)
		var fuel_limited_hrr_kw: float = fire.remaining_fuel_MJ * 0.2
		var burn_rate_limited_hrr_kw: float = fire.max_burn_rate_kw

		var hrr_kw: float = minf(
			hrr_target_kw,
			minf(fuel_limited_hrr_kw, burn_rate_limited_hrr_kw)
		)

		var o2_factor: float = clampf(
			(room.o2 - fire.o2_min_for_flame) / maxf(0.001, fire.o2_nominal - fire.o2_min_for_flame),
			0.0,
			1.0
		)

		if room.o2 <= fire.o2_min_for_flame + 0.01:
			room.hrr_kw = 0.0
			room.smoke_prod_kg_s = 0.0
			continue

		room.hrr_kw = hrr_kw * pow(o2_factor, 2.5)

		room.smoke_prod_kg_s = _compute_smoke_production_kg_s(
			room.hrr_kw,
			fire.smoke_yield_kg_per_MJ
		)

		var energy_released_MJ: float = room.hrr_kw * dt / 1000.0
		fire.remaining_fuel_MJ -= energy_released_MJ
		fire.remaining_fuel_MJ = maxf(0.0, fire.remaining_fuel_MJ)

		if fire.remaining_fuel_MJ <= 0.0:
			room.hrr_kw = 0.0
			room.smoke_prod_kg_s = 0.0
			continue

		_try_trigger_flashover(room)

func _compute_o2_factor(o2: float, nominal: float, min_o2: float) -> float:
	if o2 <= min_o2:
		return 0.0

	var o2_ratio: float = (o2 - min_o2) / maxf(0.001, nominal - min_o2)
	return clampf(o2_ratio, 0.0, 1.0)

func _compute_smoke_production_kg_s(hrr_kw: float, smoke_yield_kg_per_MJ: float) -> float:
	var hrr_MJ_s: float = hrr_kw / 1000.0
	return hrr_MJ_s * smoke_yield_kg_per_MJ

func _try_trigger_flashover(room: RoomModel) -> void:
	if room.fire == null:
		return

	if room.flashover_triggered:
		return

	var hot_enough: bool = room.temp_upper_c >= flashover_temp_c
	var low_layer: bool = room.h_layer_m <= flashover_layer_m
	var enough_hrr: bool = room.hrr_kw >= room.fire.flashover_min_hrr_kw

	if hot_enough and low_layer and enough_hrr:
		room.flashover_triggered = true
		room.fire.max_hrr_kw += room.fire.secondary_hrr_gain_kw
		room.hrr_kw *= room.fire.flashover_hrr_multiplier

# ============================================================
# OXÍGENO
# ============================================================

func _step_oxygen(dt: float) -> void:
	var air_density_kg_m3: float = 1.2

	for room_id in building.get_rooms().keys():
		var room: RoomModel = building.get_room(room_id)
		if room == null:
			continue

		var room_volume_m3: float = maxf(0.1, room.volume_m3())
		var air_mass_kg: float = room_volume_m3 * air_density_kg_m3
		var o2_mass_kg: float = air_mass_kg * room.o2

		if room.hrr_kw > 0.0:
			var consumption_rate: float = room.fire.o2_consumption_kg_per_MJ if room.fire != null else 0.20
			var consumed: float = (room.hrr_kw / 1000.0) * consumption_rate * dt

			var availability_factor: float = clampf(
				(room.o2 - 0.12) / maxf(0.001, o2_nominal - 0.12),
				0.0,
				1.0
			)

			consumed *= availability_factor
			consumed = minf(consumed, o2_mass_kg * 0.05)

			o2_mass_kg -= consumed
			o2_mass_kg = maxf(0.0, o2_mass_kg)

		var target_o2: float = o2_mass_kg / air_mass_kg
		room.o2 = lerpf(room.o2, target_o2, 0.40 * dt)
		room.o2 = clampf(room.o2, 0.10, o2_nominal)

# ============================================================
# TEMPERATURA
# ============================================================

func _step_temperature(dt: float) -> void:
	for room_id in building.get_rooms().keys():
		var room: RoomModel = building.get_room(room_id)
		if room == null:
			continue

		var hrr_term: float = room.hrr_kw * 0.02 * dt
		room.temp_upper_c += hrr_term

		var smoke_factor: float = clampf(room.smoke_kg / 2.0, 0.0, 1.0)
		room.temp_upper_c += room.temp_upper_c * smoke_factor * 0.04 * dt

		var smoke_heat_bonus: float = room.smoke_kg * 0.20 * dt
		room.temp_upper_c += smoke_heat_bonus

		var delta_ul: float = maxf(0.0, room.temp_upper_c - room.temp_lower_c)

		var loss_to_lower: float = delta_ul * upper_to_lower_loss_rate * dt
		var loss_to_ambient: float = maxf(0.0, room.temp_upper_c - building.outside_temp_c) * upper_to_ambient_loss_rate * dt
		var lower_warming: float = delta_ul * lower_layer_warming_rate * dt
		var lower_loss_to_ambient: float = maxf(0.0, room.temp_lower_c - building.outside_temp_c) * 0.010 * dt

		room.temp_upper_c -= loss_to_lower
		room.temp_upper_c -= loss_to_ambient

		room.temp_lower_c += lower_warming
		room.temp_lower_c -= lower_loss_to_ambient

		room.temp_lower_c = maxf(building.outside_temp_c, room.temp_lower_c)
		room.temp_lower_c = minf(room.temp_lower_c, room.temp_upper_c)

# ============================================================
# HUMO
# ============================================================

func _step_smoke(dt: float) -> void:
	var smoke_delta_kg: Dictionary = {}

	for room_id in building.get_rooms().keys():
		smoke_delta_kg[int(room_id)] = 0.0

	for room_id in building.get_rooms().keys():
		var room: RoomModel = building.get_room(room_id)
		if room == null:
			continue

		var generated_kg: float = smoke_model.add_generated_smoke(room, dt)
		smoke_generated_total_kg += generated_kg
		smoke_delta_kg[int(room_id)] += generated_kg

	var room_transfers: Array[Dictionary] = []

	for op in building.get_openings():
		if op.open_fraction <= 0.0:
			continue

		var room_out: RoomModel = null

		if op.a != BuildingModel.OUTSIDE_ID and op.b == BuildingModel.OUTSIDE_ID:
			room_out = building.get_room(op.a)
		elif op.b != BuildingModel.OUTSIDE_ID and op.a == BuildingModel.OUTSIDE_ID:
			room_out = building.get_room(op.b)

		if room_out != null:
			var vented_kg: float = smoke_model.compute_outside_vented_kg(room_out, op, dt)
			if vented_kg > 0.0:
				smoke_delta_kg[room_out.id] -= vented_kg
				smoke_vented_total_kg += vented_kg

				if room_out.smoke_kg > 0.0:
					var heat_loss_factor: float = vented_kg / (room_out.smoke_kg + 0.1)
					room_out.temp_upper_c *= (1.0 - heat_loss_factor * 0.5)

			continue

		var room_a: RoomModel = building.get_room(op.a)
		var room_b: RoomModel = building.get_room(op.b)

		if room_a == null or room_b == null:
			continue

		var transfer: Dictionary = smoke_model.compute_room_transfer(room_a, room_b, op, dt)
		var from_id: int = int(transfer.get("from", -1))
		var to_id: int = int(transfer.get("to", -1))
		var kg: float = float(transfer.get("kg", 0.0))

		var layer_factor: float = 1.0

		if room_a.h_layer_m < 1.8:
			layer_factor = 1.5
		if room_a.h_layer_m < 1.2:
			layer_factor = 2.5
		if room_a.h_layer_m < 0.8:
			layer_factor = 4.0

		kg *= layer_factor

		if from_id == -1 or to_id == -1 or kg <= 0.0:
			continue

		room_transfers.append({
			"from": from_id,
			"to": to_id,
			"kg": kg
		})

	var outgoing: Dictionary = {}

	for t in room_transfers:
		var from_id: int = int(t["from"])

		if not outgoing.has(from_id):
			outgoing[from_id] = []

		outgoing[from_id].append(t)

	for from_id in outgoing.keys():
		var room: RoomModel = building.get_room(int(from_id))
		if room == null:
			continue

		var total_requested: float = 0.0
		for t in outgoing[from_id]:
			total_requested += float(t["kg"])

		var max_allowed: float = room.smoke_kg * 0.12 * dt

		if total_requested > max_allowed and total_requested > 0.0:
			var scale: float = max_allowed / total_requested

			for t in outgoing[from_id]:
				t["kg"] = float(t["kg"]) * scale

	for t in room_transfers:
		var from_id: int = int(t["from"])
		var to_id: int = int(t["to"])
		var kg: float = float(t["kg"])

		if kg <= 0.0:
			continue

		smoke_delta_kg[from_id] -= kg
		smoke_delta_kg[to_id] += kg

		var source: RoomModel = building.get_room(from_id)
		var target: RoomModel = building.get_room(to_id)

		if source != null and target != null:
			var flow_ratio: float = kg / (target.smoke_kg + kg + 0.1)

			var temp_mix: float = 0.30 * flow_ratio

			target.temp_upper_c = lerp(
				target.temp_upper_c,
				source.temp_upper_c,
				temp_mix
			)

			source.temp_upper_c -= (
				(source.temp_upper_c - target.temp_upper_c)
				* temp_mix * 0.03
			)

			var o2_mix_factor: float = 0.15 * flow_ratio
			target.o2 = lerpf(target.o2, source.o2, o2_mix_factor)

			var back_mix: float = 0.03 * flow_ratio
			source.o2 = lerpf(source.o2, target.o2, back_mix)

	for room_id in building.get_rooms().keys():
		var room: RoomModel = building.get_room(room_id)
		if room == null:
			continue

		room.smoke_kg += float(smoke_delta_kg[int(room_id)])
		room.smoke_kg = maxf(0.0, room.smoke_kg)

		if room.h_layer_m < 0.5:
			room.smoke_kg *= 0.98

	for room_id in building.get_rooms().keys():
		var room: RoomModel = building.get_room(room_id)
		if room == null:
			continue

		smoke_model.recompute_layer_from_mass(room, dt)
		room.smoke_kg *= (1.0 - 0.001 * dt)

# ============================================================
# DEBUG DE CONSERVACIÓN DE MASA DE HUMO
# ============================================================

func debug_check_smoke_conservation() -> void:
	var total_in_rooms: float = 0.0

	for room_id in building.get_rooms().keys():
		var room: RoomModel = building.get_room(room_id)
		if room == null:
			continue

		total_in_rooms += room.smoke_kg

	var expected: float = smoke_generated_total_kg - smoke_vented_total_kg
	var error: float = abs(total_in_rooms - expected)

	if error > 0.01:
		print(
			"SMOKE MASS ERROR | rooms=",
			total_in_rooms,
			" expected=",
			expected,
			" error=",
			error
		)

# ============================================================
# CLAMP / LIMPIEZA
# ============================================================

func _clamp_rooms() -> void:
	for room_id in building.get_rooms().keys():
		var room: RoomModel = building.get_room(room_id)
		if room == null:
			continue

		room.o2 = clampf(room.o2, 0.0, fire_o2_nominal)
		room.h_layer_m = clampf(room.h_layer_m, 0.0, room.height_m)

		room.temp_lower_c = maxf(building.outside_temp_c, room.temp_lower_c)

		room.temp_upper_c = minf(room.temp_upper_c, max_upper_temp_c)
		if room.temp_upper_c < room.temp_lower_c:
			room.temp_lower_c = room.temp_upper_c

		room.hrr_kw = maxf(0.0, room.hrr_kw)
		room.smoke_prod_kg_s = maxf(0.0, room.smoke_prod_kg_s)
		room.smoke_kg = maxf(0.0, room.smoke_kg)

# ============================================================
# ESTADO AGREGADO
# ============================================================

func get_state() -> Dictionary:
	var state: Dictionary = {
		"sim_time_s": sim_time_s,
		"smoke_generated_total_kg": smoke_generated_total_kg,
		"smoke_vented_total_kg": smoke_vented_total_kg
	}

	for room_id in building.get_rooms().keys():
		var room: RoomModel = building.get_room(room_id)
		if room == null:
			continue

		state[str(room_id)] = {
			"id": room.id,
			"name": room.name,
			"kind": room.kind,

			"hrr_kw": room.hrr_kw,
			"fire_time_s": room.fire_time_s,

			"temp_upper_c": room.temp_upper_c,
			"temp_lower_c": room.temp_lower_c,

			"o2": room.o2,

			"h_layer_m": room.h_layer_m,
			"smoke_kg": room.smoke_kg,
			"smoke_prod_kg_s": room.smoke_prod_kg_s,

			"has_fire": room.fire != null,
			"flashover_triggered": room.flashover_triggered
		}
	return state

# ============================================================
# REGISTRO DE VALORES
# ============================================================

func _maybe_log_state() -> void:
	if not enable_logging:
		return

	if sim_time_s < _next_log_time_s:
		return

	_append_log_snapshot()
	_next_log_time_s += log_interval_s

func _append_log_snapshot() -> void:
	var file := FileAccess.open(log_file_path, FileAccess.READ_WRITE)
	if file == null:
		push_error("No se pudo abrir el log: " + log_file_path)
		return

	file.seek_end()

	file.store_line("==================================================")
	file.store_line("TIME=%.1f s" % sim_time_s)

	for room_id in building.get_rooms().keys():
		var room: RoomModel = building.get_room(room_id)
		if room == null:
			continue

		var line := "ROOM %s | HRR=%.2f | Up=%.2f | Low=%.2f | Smoke=%.4f | Layer=%.2f | O2=%.4f" % [
			str(room.id),
			room.hrr_kw,
			room.temp_upper_c,
			room.temp_lower_c,
			room.smoke_kg,
			room.h_layer_m,
			room.o2
		]
		file.store_line(line)

	file.store_line("")
	file.close()
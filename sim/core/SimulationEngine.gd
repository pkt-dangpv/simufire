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
#
# PRIORIDAD ACTUAL:
# - estabilidad del motor físico
# - conservación de masa de humo
# ============================================================

@export var building_path: NodePath

var building: BuildingModel
var smoke_model: SmokeModel = SmokeModel.new()

# ============================================================
# TIEMPO
# ============================================================

@export var time_scale: float = 1.0
var sim_time_s: float = 0.0

# ============================================================
# CONTABILIDAD GLOBAL DEL HUMO
# ------------------------------------------------------------
# Invariante buscada:
#
# smoke_generated_total_kg
# =
# sum(room.smoke_kg)
# +
# smoke_vented_total_kg
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

@export var upper_to_lower_loss_rate: float = 0.035
@export var upper_to_ambient_loss_rate: float = 0.015
@export var lower_layer_warming_rate: float = 0.010
@export var max_upper_temp_c: float = 900.0

# ============================================================
# OXÍGENO / MEZCLA
# ============================================================

@export var o2_mix_rate: float = 0.12
@export var o2_vent_rate: float = 0.08

# ============================================================
# AJUSTES DE HUMO (se copian al SmokeModel)
# ============================================================

@export var smoke_density_kg_m3: float = 0.9
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
	_resolve_building()
	_sync_smoke_model_settings()

	if auto_ignite_on_ready:
		ignite_room(ignition_room_id)

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

		room.fire_time_s += dt

		var hrr_ideal_kw: float = room.fire.compute_hrr_kw(room.fire_time_s)
		var vent_limit_kw: float = building.estimate_vent_hrr_kw(room.id)

		# Si no hay hueco exterior, por ahora usamos el máximo del fuego
		# para no colapsar artificialmente a 0.
		if vent_limit_kw <= 0.0:
			vent_limit_kw = room.fire.max_hrr_kw

		var o2_factor: float = _compute_o2_factor(
			room.o2,
			room.fire.o2_nominal,
			room.fire.o2_min_for_flame
		)

		var hrr_limited_kw: float = minf(hrr_ideal_kw, vent_limit_kw)

		room.hrr_kw = hrr_limited_kw * o2_factor
		room.smoke_prod_kg_s = _compute_smoke_production_kg_s(
			room.hrr_kw,
			room.fire.smoke_yield_kg_per_MJ
		)

		_try_trigger_flashover(room)

func _compute_o2_factor(o2: float, o2_nominal: float, o2_min_for_flame: float) -> float:
	if o2 <= o2_min_for_flame:
		return 0.0

	var span: float = maxf(0.0001, o2_nominal - o2_min_for_flame)
	return clampf((o2 - o2_min_for_flame) / span, 0.0, 1.0)

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
	for room_id in building.get_rooms().keys():
		var room: RoomModel = building.get_room(room_id)
		if room == null:
			continue

		var o2_consumption: float = 0.0

		if room.fire != null and room.hrr_kw > 0.0:
			o2_consumption = 0.000008 * room.hrr_kw * dt

		room.o2 -= o2_consumption

		# Mezcla interna simple
		room.o2 += (fire_o2_nominal - room.o2) * o2_mix_rate * dt

		# Recuperación exterior
		if building.has_outside_opening(room.id):
			room.o2 += (building.outside_o2 - room.o2) * o2_vent_rate * dt

# ============================================================
# TEMPERATURA
# ============================================================

func _step_temperature(dt: float) -> void:
	for room_id in building.get_rooms().keys():
		var room: RoomModel = building.get_room(room_id)
		if room == null:
			continue

		var hrr_term: float = room.hrr_kw * 0.006 * dt
		room.temp_upper_c += hrr_term

		var loss_to_lower: float = maxf(0.0, room.temp_upper_c - room.temp_lower_c) * upper_to_lower_loss_rate * dt
		var loss_to_ambient: float = maxf(0.0, room.temp_upper_c - building.outside_temp_c) * upper_to_ambient_loss_rate * dt
		var lower_warming: float = maxf(0.0, room.temp_upper_c - room.temp_lower_c) * lower_layer_warming_rate * dt
		var lower_loss_to_ambient: float = maxf(0.0, room.temp_lower_c - building.outside_temp_c) * 0.01 * dt

		room.temp_upper_c -= loss_to_lower
		room.temp_upper_c -= loss_to_ambient

		room.temp_lower_c += lower_warming
		room.temp_lower_c -= lower_loss_to_ambient
		room.temp_lower_c = minf(room.temp_lower_c, room.temp_upper_c)

# ============================================================
# HUMO
# ------------------------------------------------------------
# Orden correcto:
# 1) generar masa
# 2) transferir entre salas / exterior
# 3) recalcular capa desde masa
# 4) comprobar conservación
# ============================================================

func _step_smoke(dt: float) -> void:
	# --------------------------------------------------------
	# 1) Generación de humo
	# --------------------------------------------------------
	for room_id in building.get_rooms().keys():
		var room: RoomModel = building.get_room(room_id)
		if room == null:
			continue

		var generated_kg: float = smoke_model.add_generated_smoke(room, dt)
		smoke_generated_total_kg += generated_kg

	# --------------------------------------------------------
	# 2) Transferencias por aperturas
	# --------------------------------------------------------
	for op in building.get_openings():
		if op.open_fraction <= 0.0:
			continue

		var vented_kg: float = smoke_model.transfer_between_opening(building, op, dt)
		smoke_vented_total_kg += vented_kg

	# --------------------------------------------------------
	# 3) Recalcular capa desde masa
	# --------------------------------------------------------
	for room_id in building.get_rooms().keys():
		var room: RoomModel = building.get_room(room_id)
		if room == null:
			continue

		smoke_model.recompute_layer_from_mass(room, dt)

	#debug_check_smoke_conservation()

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
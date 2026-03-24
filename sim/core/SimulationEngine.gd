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

# Constantes de conversión y físicas que no estaban claras dónde ponerlas. 
# Se pueden mover a un archivo de configuración o a BuildingModel si se quiere.
const o2_consumption_kg_per_MJ: float = 0.27
const o2_nominal: float = 0.209

# ============================================================
# TIEMPO
# ============================================================

@export var time_scale: float = 5.0
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
	# Por debajo del mínimo: el fuego no se apaga del todo (fase latente)
	if o2 <= o2_min_for_flame:
		return 0.2

	# Por encima del nominal: sin limitación
	if o2 >= o2_nominal:
		return 1.0

	# Interpolación suave entre mínimo y nominal
	var t: float = (o2 - o2_min_for_flame) / (o2_nominal - o2_min_for_flame)
	t = clamp(t, 0.0, 1.0)

	# Curva suavizada (clave)
	return 0.2 + 0.8 * sqrt(t)

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

		if room.hrr_kw > 0.0:
			var o2_consumed: float = (room.hrr_kw / 1000.0) * o2_consumption_kg_per_MJ * dt
			room.o2 -= o2_consumed

		var mix_rate: float = o2_mix_rate * dt
		room.o2 = lerp(room.o2, o2_nominal, mix_rate)

		room.o2 = clamp(room.o2, 0.10, o2_nominal)
# ============================================================
# TEMPERATURA
# ============================================================

func _step_temperature(dt: float) -> void:
	for room_id in building.get_rooms().keys():
		var room: RoomModel = building.get_room(room_id)
		if room == null:
			continue

		# ----------------------------------------------------
		# 1) Aporte térmico del fuego
		# ----------------------------------------------------
		# Simplificación:
		# - más HRR => más calor
		# - más volumen => cuesta más calentar la sala
		var room_volume_m3: float = maxf(1.0, room.volume_m3())
		var hrr_term: float = room.hrr_kw * 0.006 * dt

		room.temp_upper_c += hrr_term

		# ----------------------------------------------------
		# 2) Pérdidas / transferencia entre capas
		# ----------------------------------------------------
		var delta_ul: float = maxf(0.0, room.temp_upper_c - room.temp_lower_c)

		var loss_to_lower: float = delta_ul * upper_to_lower_loss_rate * dt
		var loss_to_ambient: float = maxf(0.0, room.temp_upper_c - building.outside_temp_c) * upper_to_ambient_loss_rate * dt
		var lower_warming: float = delta_ul * lower_layer_warming_rate * dt
		var lower_loss_to_ambient: float = maxf(0.0, room.temp_lower_c - building.outside_temp_c) * 0.015 * dt

		room.temp_upper_c -= loss_to_lower
		room.temp_upper_c -= loss_to_ambient

		room.temp_lower_c += lower_warming
		room.temp_lower_c -= lower_loss_to_ambient

		# ----------------------------------------------------
		# 3) Seguridad numérica
		# ----------------------------------------------------
		room.temp_lower_c = maxf(building.outside_temp_c, room.temp_lower_c)
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
	# 0) Preparar deltas por sala
	# --------------------------------------------------------
	var smoke_delta_kg: Dictionary = {}

	for room_id in building.get_rooms().keys():
		smoke_delta_kg[int(room_id)] = 0.0

	# --------------------------------------------------------
	# 1) Generación de humo
	# --------------------------------------------------------
	for room_id in building.get_rooms().keys():
		var room: RoomModel = building.get_room(room_id)
		if room == null:
			continue

		var generated_kg: float = smoke_model.add_generated_smoke(room, dt)
		smoke_generated_total_kg += generated_kg
		smoke_delta_kg[int(room_id)] += generated_kg

	# --------------------------------------------------------
	# 2) Calcular transferencias usando snapshot del frame
	#    PERO SIN aplicarlas todavía
	# --------------------------------------------------------
	var room_transfers: Array[Dictionary] = []

	for op in building.get_openings():
		if op.open_fraction <= 0.0:
			continue

		# ----------------------------------------------------
		# Caso exterior
		# ----------------------------------------------------
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

				# Pérdida de calor con el humo al exterior
				if room_out.smoke_kg > 0.0:
					var heat_loss_factor: float = vented_kg / (room_out.smoke_kg + 0.1)
					room_out.temp_upper_c *= (1.0 - heat_loss_factor * 0.5)

			continue

		# ----------------------------------------------------
		# Caso entre salas
		# ----------------------------------------------------
		var room_a: RoomModel = building.get_room(op.a)
		var room_b: RoomModel = building.get_room(op.b)

		if room_a == null or room_b == null:
			continue

		var transfer: Dictionary = smoke_model.compute_room_transfer(room_a, room_b, op, dt)
		var from_id: int = int(transfer.get("from", -1))
		var to_id: int = int(transfer.get("to", -1))
		var kg: float = float(transfer.get("kg", 0.0))

		if from_id == -1 or to_id == -1 or kg <= 0.0:
			continue

		room_transfers.append({
			"from": from_id,
			"to": to_id,
			"kg": kg
		})

	# --------------------------------------------------------
	# 3) LIMITAR CAUDAL TOTAL POR SALA ORIGEN
	# --------------------------------------------------------
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

		var max_allowed: float = room.smoke_kg * 0.03 * dt

		if total_requested > max_allowed and total_requested > 0.0:
			var scale: float = max_allowed / total_requested

			for t in outgoing[from_id]:
				t["kg"] = float(t["kg"]) * scale

	# --------------------------------------------------------
	# 4) Convertir transfers limitados en deltas
	#    + mezclar temperatura con el humo
	# --------------------------------------------------------
	for t in room_transfers:
		var from_id: int = int(t["from"])
		var to_id: int = int(t["to"])
		var kg: float = float(t["kg"])

		if kg <= 0.0:
			continue

		smoke_delta_kg[from_id] -= kg
		smoke_delta_kg[to_id] += kg

		# Transferencia de calor con el humo
		var source: RoomModel = building.get_room(from_id)
		var target: RoomModel = building.get_room(to_id)

		if source != null and target != null:
			var mix_factor: float = kg / (target.smoke_kg + kg + 0.1)

			target.temp_upper_c = lerp(
				target.temp_upper_c,
				source.temp_upper_c,
				mix_factor * 1.4
			)

			source.temp_upper_c -= (
				(source.temp_upper_c - target.temp_upper_c)
				* mix_factor * 0.05
			)

	# --------------------------------------------------------
	# 5) Aplicar deltas al final
	# --------------------------------------------------------
	for room_id in building.get_rooms().keys():
		var room: RoomModel = building.get_room(room_id)
		if room == null:
			continue

		room.smoke_kg += float(smoke_delta_kg[int(room_id)])
		room.smoke_kg = maxf(0.0, room.smoke_kg)

	# --------------------------------------------------------
	# 6) Recalcular capa desde la masa final
	# --------------------------------------------------------
	for room_id in building.get_rooms().keys():
		var room: RoomModel = building.get_room(room_id)
		if room == null:
			continue

		smoke_model.recompute_layer_from_mass(room, dt)

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
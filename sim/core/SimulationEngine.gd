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
@export var fire_o2_consumption_kg_per_MJ: float = 0.076  # Regla de Thornton: 1/13.1 MJ/kgO2
@export var fire_smoke_yield_kg_per_MJ: float = 0.06

# Umbral de extinción: si el HRR real cae por debajo durante fire_extinction_delay_s
# segundos, el fuego se considera extinto (modela apagado por falta de ventilación).
@export var fire_extinction_hrr_kw: float = 8.0
@export var fire_extinction_delay_s: float = 120.0

# Tiempo máximo de actividad del fuego. Pasado este tiempo el combustible se considera
# agotado y el fuego se extingue (evita zombie fire en equilibrio O2/HRR).
@export var fire_max_active_s: float = 1800.0

@export var fire_flashover_hrr_multiplier: float = 2.2
@export var fire_flashover_min_hrr_kw: float = 300.0

# Retroalimentación radiativa: la capa superior caliente radia sobre el combustible
# aumentando la tasa de pirólisis. Modelo lineal sobre T_upper (simplificación de
# Stefan-Boltzmann). 0.0 = desactivado. Con 0.25: +25% de HRR a 520°C sobre ambiente.
@export var thermal_feedback_coeff: float = 0.15
@export var thermal_feedback_max: float = 1.5

# ============================================================
# PROPAGACIÓN DEL INCENDIO
# ============================================================

@export var fire_spread_enabled: bool = true
@export var fire_spread_ignition_temp_c: float = 300.0  # temperatura de la capa superior para ignición por calor

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

# Absorción de calor por paredes — término proporcional simple sobre (T_upper - T_ambient).
# Mismo patrón que upper_to_ambient_loss_rate: sin dividir por m_upper_kg → estable.
# 0.003 /s → a 800°C de diferencia: 2.4°C/s adicionales (modest, calibratable).
@export var wall_absorption_rate: float = 0.003

# Parámetro heredado de intento anterior (no usado en cálculo, conservado por compatibilidad)
@export var wall_heat_transfer_w_m2k: float = 6.0

# ============================================================
# VENTILACIÓN PULSANTE POR FUGAS EN VENTANAS
# ============================================================

# Área de fuga efectiva por ventana cerrada (huecos en marco, juntas degradadas).
# Valor típico residencial: 0.003-0.008 m². Con 0.005 m²/ventana y ΔP=5 Pa → ~0.01 kg/s.
@export var window_leakage_area_m2: float = 0.005

# Umbral de sobrepresión para iniciar venteo. Por debajo no hay fuga neta.
@export var pressure_vent_threshold_pa: float = 2.0

# ============================================================
# OXÍGENO / MEZCLA
# ============================================================

@export var o2_mix_rate: float = 0.02
@export var o2_vent_rate: float = 0.08
@export var ach_infiltration: float = 0.3  # Renovaciones de aire/hora por fugas del edificio

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
	_step_fire_spread(dt)
	_step_oxygen(dt)
	_step_temperature(dt)
	_step_pressure_venting(dt)
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

		# Verificar O2 ANTES de avanzar fire_time_s.
		# Si el fuego está sofocado, fire_time_s no avanza: cuando el O2 se recupere
		# el fuego reanuda desde el mismo HRR, sin salto artificial.
		var o2_factor: float = clampf(
			(room.o2 - fire.o2_min_for_flame) / maxf(0.001, fire.o2_nominal - fire.o2_min_for_flame),
			0.0,
			1.0
		)

		# Corte exacto en el mínimo absoluto. Sin buffer +0.01:
		# evita el ciclo on/off cuando O2 oscila justo en el umbral.
		# Para valores de O2 bajos pero > min, o2_factor ya reduce el HRR suavemente.
		if room.o2 <= fire.o2_min_for_flame:
			room.hrr_kw = 0.0
			room.smoke_prod_kg_s = 0.0
			# Fuego sofocado por O2 insuficiente: cuenta tiempo de agonía
			if room.fire_time_s > 60.0:
				room.fire_low_hrr_time_s += dt
				if room.fire_low_hrr_time_s >= fire_extinction_delay_s:
					room.fire = null
					room.fire_low_hrr_time_s = 0.0
			continue

		room.fire_time_s += dt

		var hrr_target_kw: float = fire.compute_hrr_kw(room.fire_time_s)

		# Decay phase: escalar HRR solo cuando queda < 15% de combustible
		var fuel_fraction: float = fire.remaining_fuel_MJ / maxf(0.001, fire.fuel_energy_MJ)
		var decay_factor: float = 1.0
		if fuel_fraction < 0.15:
			decay_factor = fuel_fraction / 0.15

		var hrr_kw: float = hrr_target_kw * decay_factor

		# Retroalimentación radiativa de la capa superior caliente sobre el combustible.
		# La radiación infrarroja del humo caliente acelera la pirólisis del material,
		# aumentando el HRR de forma continua (precursora del flashover).
		# A temperatura ambiente: factor = 1.0 (sin efecto).
		# A 520°C: factor ≈ 1.25 (+25%). Tope en thermal_feedback_max.
		var ambient_c: float = building.outside_temp_c if building != null else 20.0
		var rad_feedback: float = 1.0 + thermal_feedback_coeff \
				* maxf(0.0, room.temp_upper_c - ambient_c) / 500.0
		rad_feedback = minf(rad_feedback, thermal_feedback_max)
		hrr_kw *= rad_feedback

		# Escala lineal: físicamente correcto, fires se apagan al llegar a o2_min no antes
		room.hrr_kw = hrr_kw * o2_factor

		room.smoke_prod_kg_s = _compute_smoke_production_kg_s(
			room.hrr_kw,
			fire.smoke_yield_kg_per_MJ
		)

		# Extinción por HRR sostenido bajo (fuego en agonía post-pico)
		if room.hrr_kw < fire_extinction_hrr_kw and room.fire_time_s > 60.0:
			room.fire_low_hrr_time_s += dt
			if room.fire_low_hrr_time_s >= fire_extinction_delay_s:
				room.hrr_kw = 0.0
				room.smoke_prod_kg_s = 0.0
				room.fire = null
				room.fire_low_hrr_time_s = 0.0
				continue
		else:
			room.fire_low_hrr_time_s = 0.0

		var energy_released_MJ: float = room.hrr_kw * dt / 1000.0
		fire.remaining_fuel_MJ -= energy_released_MJ
		fire.remaining_fuel_MJ = maxf(0.0, fire.remaining_fuel_MJ)

		if fire.remaining_fuel_MJ <= 0.0:
			room.hrr_kw = 0.0
			room.smoke_prod_kg_s = 0.0
			room.fire = null
			continue

		# Extinción por tiempo máximo de actividad (combustible agotado)
		if room.fire_time_s >= fire_max_active_s:
			room.hrr_kw = 0.0
			room.smoke_prod_kg_s = 0.0
			room.fire = null
			continue

		_try_trigger_flashover(room)

# ============================================================
# PROPAGACIÓN DEL INCENDIO
# ============================================================

func _step_fire_spread(_dt: float) -> void:
	if not fire_spread_enabled:
		return

	for op in building.get_openings():
		if op.open_fraction <= 0.0:
			continue

		if op.a == BuildingModel.OUTSIDE_ID or op.b == BuildingModel.OUTSIDE_ID:
			continue

		var room_a: RoomModel = building.get_room(op.a)
		var room_b: RoomModel = building.get_room(op.b)

		if room_a == null or room_b == null:
			continue

		# Propagación A → B
		if room_a.fire != null and room_b.fire == null:
			if room_b.temp_upper_c >= fire_spread_ignition_temp_c:
				ignite_room(op.b)
				print("[FireSpread] Ignición por calor: Room %d → Room %d (%.0f°C)" % [op.a, op.b, room_b.temp_upper_c])

		# Propagación B → A
		if room_b.fire != null and room_a.fire == null:
			if room_a.temp_upper_c >= fire_spread_ignition_temp_c:
				ignite_room(op.a)
				print("[FireSpread] Ignición por calor: Room %d → Room %d (%.0f°C)" % [op.b, op.a, room_a.temp_upper_c])


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
	var enough_hrr: bool = room.hrr_kw >= room.fire.flashover_min_hrr_kw

	# Criterio físico: temperatura capa superior >= flashover_temp_c (estándar 500-600°C).
	# La altura de capa NO es criterio de flashover — se eliminó esa condición.
	if hot_enough and enough_hrr:
		room.flashover_triggered = true
		room.fire.max_hrr_kw += room.fire.secondary_hrr_gain_kw
		room.hrr_kw *= room.fire.flashover_hrr_multiplier
		# Sincronizar fire_time con el HRR boosted para que la curva t² no retroceda
		var t_to_hrr: float = sqrt(room.hrr_kw / maxf(0.001, room.fire.growth_alpha_kw_s2))
		room.fire_time_s = maxf(room.fire_time_s, t_to_hrr)

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
			# room.hrr_kw ya está reducido por o2_factor en _step_fire.
			# El consumo de O2 es directamente proporcional al calor liberado (Ley de Thornton).
			# No aplicar availability_factor adicional — sería doble penalización.
			var consumption_rate: float = room.fire.o2_consumption_kg_per_MJ if room.fire != null else 0.076
			var consumed: float = (room.hrr_kw / 1000.0) * consumption_rate * dt
			consumed = minf(consumed, o2_mass_kg * 0.05)

			o2_mass_kg -= consumed
			o2_mass_kg = maxf(0.0, o2_mass_kg)

		# ACH base infiltration: fugas por la envolvente del edificio (~0.3 ACH residencial).
		# Evita colapso total de O2 en edificio sellado con ventanas cerradas.
		var ach_o2_delta: float = room_volume_m3 * (ach_infiltration / 3600.0) * air_density_kg_m3 \
				* (building.outside_o2 - room.o2) * dt
		o2_mass_kg += ach_o2_delta

		room.o2 = o2_mass_kg / air_mass_kg
		room.o2 = clampf(room.o2, 0.0, o2_nominal)

	# --------------------------------------------------------
	# Intercambio de O2 por efecto chimenea (stack effect)
	# Habitación caliente → aire sale por arriba, aire fresco
	# entra por abajo desde sala adyacente / exterior.
	# Q_vent = 0.65 * 0.5 * A * sqrt(g * H * ΔT / T_avg)
	# --------------------------------------------------------
	var g_gravity: float = 9.8

	for op in building.get_openings():
		if op.open_fraction <= 0.0:
			continue

		var lintel_m: float = op.lintel_height_m()

		if op.a == BuildingModel.OUTSIDE_ID or op.b == BuildingModel.OUTSIDE_ID:
			var indoor_id: int = op.a if op.b == BuildingModel.OUTSIDE_ID else op.b
			var indoor: RoomModel = building.get_room(indoor_id)
			if indoor == null:
				continue

			# Solo hay flujo de gases calientes si la capa de humo ha bajado
			# hasta el dintel. La altura efectiva del intercambio es la banda
			# entre h_layer y el dintel (por arriba sale gas caliente,
			# por abajo entra aire fresco).
			var hot_band_m: float = maxf(0.0, lintel_m - indoor.h_layer_m)
			if hot_band_m <= 0.0:
				continue

			# Área efectiva proporcional a la banda caliente sobre el dintel
			var area_eff: float = op.width_m * minf(hot_band_m, op.height_m) * op.open_fraction
			if area_eff <= 0.0:
				continue

			var t_in_k: float = indoor.temp_upper_c + 273.15
			var t_out_k: float = building.outside_temp_c + 273.15
			var delta_t_k: float = maxf(0.0, t_in_k - t_out_k)
			var q: float = 0.65 * 0.5 * area_eff * sqrt(g_gravity * hot_band_m * delta_t_k / t_in_k)
			var air_in: float = q * air_density_kg_m3 * dt
			var mass_room: float = maxf(0.1, indoor.volume_m3()) * air_density_kg_m3
			indoor.o2 = clampf((indoor.o2 * mass_room + building.outside_o2 * air_in) / (mass_room + air_in), 0.0, o2_nominal)
		else:
			var room_a: RoomModel = building.get_room(op.a)
			var room_b: RoomModel = building.get_room(op.b)
			if room_a == null or room_b == null:
				continue

			# Dirección dominante: sala más caliente empuja gas caliente
			# hacia la más fría a través de la banda por encima del dintel.
			var hot_room: RoomModel
			var cold_room: RoomModel
			if room_a.temp_upper_c >= room_b.temp_upper_c:
				hot_room = room_a
				cold_room = room_b
			else:
				hot_room = room_b
				cold_room = room_a

			var hot_band_m: float = maxf(0.0, lintel_m - hot_room.h_layer_m)
			if hot_band_m <= 0.0:
				continue

			var t_hot_k: float = hot_room.temp_upper_c + 273.15
			var t_cold_k: float = cold_room.temp_upper_c + 273.15
			var delta_t_k: float = maxf(0.0, t_hot_k - t_cold_k)
			if delta_t_k < 2.0:
				continue

			var area_eff: float = op.width_m * minf(hot_band_m, op.height_m) * op.open_fraction
			var q: float = 0.65 * 0.5 * area_eff * sqrt(g_gravity * hot_band_m * delta_t_k / ((t_hot_k + t_cold_k) * 0.5))
			var exch: float = q * air_density_kg_m3 * dt
			var mass_hot: float = maxf(0.1, hot_room.volume_m3()) * air_density_kg_m3
			var mass_cold: float = maxf(0.1, cold_room.volume_m3()) * air_density_kg_m3
			var new_hot: float = (hot_room.o2 * mass_hot + cold_room.o2 * exch) / (mass_hot + exch)
			var new_cold: float = (cold_room.o2 * mass_cold + hot_room.o2 * exch) / (mass_cold + exch)
			hot_room.o2 = clampf(new_hot, 0.0, o2_nominal)
			cold_room.o2 = clampf(new_cold, 0.0, o2_nominal)

# ============================================================
# TEMPERATURA
# ============================================================

func _step_temperature(dt: float) -> void:
	for room_id in building.get_rooms().keys():
		var room: RoomModel = building.get_room(room_id)
		if room == null:
			continue

		# Físicamente correcto: dT = HRR_conv * dt / (rho_aire * Cp_aire * V_capa_superior)
		# conv_fraction = 0.35: fracción de HRR que calienta el gas (el resto a paredes/radiación)
		# Escala automáticamente con el volumen: habitaciones pequeñas se calientan más rápido
		var h_upper: float = maxf(0.1, room.height_m - room.h_layer_m)
		var v_upper_m3: float = maxf(0.5, room.floor_area_m2() * h_upper)
		var m_upper_kg: float = 1.2 * v_upper_m3  # rho = 1.2 kg/m³, Cp_aire = 1.0 kJ/(kg·K)
		room.temp_upper_c += room.hrr_kw * 0.35 * dt / m_upper_kg

		var delta_ul: float = maxf(0.0, room.temp_upper_c - room.temp_lower_c)

		var loss_to_lower: float = delta_ul * upper_to_lower_loss_rate * dt
		var loss_to_ambient: float = maxf(0.0, room.temp_upper_c - building.outside_temp_c) * upper_to_ambient_loss_rate * dt
		# Absorción por paredes: proporcional a (T_upper - T_ambient), sin denominar por masa.
		# No interacciona con la fase de crecimiento porque es pequeño (~37% del loss_to_ambient).
		var wall_absorption: float = maxf(0.0, room.temp_upper_c - building.outside_temp_c) * wall_absorption_rate * dt
		var lower_warming: float = delta_ul * lower_layer_warming_rate * dt
		var lower_loss_to_ambient: float = maxf(0.0, room.temp_lower_c - building.outside_temp_c) * 0.010 * dt

		room.temp_upper_c -= loss_to_lower
		room.temp_upper_c -= loss_to_ambient
		room.temp_upper_c -= wall_absorption

		room.temp_lower_c += lower_warming
		room.temp_lower_c -= lower_loss_to_ambient

		room.temp_lower_c = maxf(building.outside_temp_c, room.temp_lower_c)
		room.temp_lower_c = minf(room.temp_lower_c, room.temp_upper_c)

# ============================================================
# VENTILACIÓN PULSANTE POR FUGAS EN VENTANAS
# ============================================================
# Modelo de fuga por marco de ventana cerrada bajo condiciones de incendio.
# Física:
#   - La capa superior caliente genera una sobrepresión buoyante:
#       ΔP_buoyante = ρ_ext × g × h_humo × (1 - T_ext_K / T_upper_K)
#   - overpressure_pa se relaja hacia ΔP_buoyante (constante de tiempo 5 s).
#   - Cuando overpressure_pa > pressure_vent_threshold_pa: gas caliente sale por
#     el hueco del marco (venteo), baja la presión, entra aire fresco por abajo.
#   - El ciclo se repite → comportamiento pulsante a escala de la simulación.
# ============================================================

func _step_pressure_venting(dt: float) -> void:
	var g: float = 9.81
	var rho_ext: float = 1.2
	var T_ext_K: float = building.outside_temp_c + 273.15

	for room_id in building.get_rooms().keys():
		var room: RoomModel = building.get_room(room_id)
		if room == null:
			continue

		# ── 1. Calcular presión buoyante objetivo ──────────────────────────
		var T_upper_K: float = room.temp_upper_c + 273.15
		var h_smoke_m: float = maxf(0.0, room.height_m - room.h_layer_m)
		var dp_buoyancy: float = rho_ext * g * h_smoke_m * maxf(0.0, 1.0 - T_ext_K / T_upper_K)

		# La presión real se equilibra exponencialmente hacia dp_buoyancy (τ = 5 s).
		# Si la temperatura baja, dp_buoyancy cae y la presión se alivia sola.
		var tau_s: float = 5.0
		room.overpressure_pa += (dp_buoyancy - room.overpressure_pa) * minf(1.0, dt / tau_s)
		room.overpressure_pa = maxf(0.0, room.overpressure_pa)

		if room.overpressure_pa < pressure_vent_threshold_pa:
			continue

		# ── 2. Identificar ventanas hacia el exterior ─────────────────────
		var total_leakage_m2: float = 0.0
		for op in building.get_openings():
			var connects_outside: bool = (
				(op.a == room_id and op.b == BuildingModel.OUTSIDE_ID) or
				(op.b == room_id and op.a == BuildingModel.OUTSIDE_ID)
			)
			if connects_outside:
				total_leakage_m2 += window_leakage_area_m2

		if total_leakage_m2 <= 0.0:
			continue

		# ── 3. Caudal saliente (orificio compresible, Cd = 0.61) ──────────
		var rho_hot: float = rho_ext * T_ext_K / T_upper_K
		var v_out: float = sqrt(2.0 * room.overpressure_pa / maxf(0.05, rho_hot))
		var q_out_m3s: float = 0.61 * total_leakage_m2 * v_out
		var smoke_out_kg: float = q_out_m3s * rho_hot * dt

		# No sacar más del 15 % del humo disponible por paso (límite físico estable)
		smoke_out_kg = minf(smoke_out_kg, room.smoke_kg * 0.15)
		if smoke_out_kg <= 0.0:
			continue

		var frac_out: float = smoke_out_kg / maxf(0.001, room.smoke_kg)

		# ── 4. Actualizar humo y temperatura ─────────────────────────────
		room.smoke_kg -= smoke_out_kg
		room.smoke_kg = maxf(0.0, room.smoke_kg)
		smoke_vented_total_kg += smoke_out_kg

		# Al salir gas caliente, la capa superior pierde temperatura proporcional
		room.temp_upper_c -= maxf(0.0, room.temp_upper_c - building.outside_temp_c) * frac_out * 0.20

		# ── 5. Alivio de presión proporcional al venteo ───────────────────
		room.overpressure_pa = maxf(0.0, room.overpressure_pa * (1.0 - frac_out * 0.9))

		# ── 6. Entrada de aire fresco compensatorio (contra-flujo inferior) ─
		# Solo el 40 % de masa sale como humo (el resto es inerte); entra aire exterior.
		var air_in_kg: float = smoke_out_kg * 0.40
		var room_mass_kg: float = maxf(1.0, room.volume_m3()) * rho_ext
		room.o2 = clampf(
			(room.o2 * room_mass_kg + building.outside_o2 * air_in_kg) / (room_mass_kg + air_in_kg),
			0.0,
			o2_nominal
		)

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

			# Contra-flujo: humo sale source→target, aire fresco entra target→source
			var o2_mix_factor: float = 0.08 * flow_ratio
			target.o2 = lerpf(target.o2, source.o2, o2_mix_factor)
			source.o2 = lerpf(source.o2, target.o2, o2_mix_factor)

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
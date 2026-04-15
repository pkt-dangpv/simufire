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

# Segundos sin fuego activo antes de declarar la simulación terminada.
@export var extinction_grace_s: float = 30.0
var is_finished: bool = false
var _extinction_countdown: float = 30.0

# ============================================================
# ROTURA DE CRISTAL
# ============================================================
# Mantener desactivado por defecto: las ventanas solo cambian si se abren
# manualmente o si esta opción se reactiva explícitamente.
@export var glass_auto_break_enabled: bool = false
# Temperatura de capa superior a la que el cristal puede romperse.
@export var glass_break_temp_c: float = 250.0
# Dispersión aleatoria: ± esta cantidad sobre glass_break_temp_c (distribución uniforme).
@export var glass_break_temp_spread_c: float = 80.0
# Velocidad a la que sube open_fraction tras la rotura (fracción/segundo).
@export var glass_open_rate_per_s: float = 0.15
# open_fraction máxima al romperse el cristal (1.0 = apertura completa).
@export var glass_max_open_fraction: float = 0.85
# Dict: opening_index → temperatura de rotura asignada aleatoriamente al inicio.
var _glass_break_temps: Dictionary = {}

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

# Coeficiente de Kawagoe (SFPE/Drysdale): HRR_max = kawagoe_coeff × Σ(A_v × √H_v)
# Valor de referencia para madera: ~1500 kW/m^(5/2).  Reducir para materiales
# con rendimiento calórico menor.  Solo aplica cuando hay ventanas exteriores abiertas.
@export var kawagoe_coeff: float = 1500.0

@export var fire_o2_nominal: float = 0.209
@export var fire_o2_min_for_flame: float = 0.10
@export var fire_o2_consumption_kg_per_MJ: float = 0.076  # Regla de Thornton: 1/13.1 MJ/kgO2
# Rendimiento de humo (kg/MJ)
# SFPE: ~0.06 kg/kg ÷ 16 MJ/kg = 0.00375 kg/MJ
@export var fire_smoke_yield_kg_per_MJ: float = 0.00375
@export var fire_smoke_yield_low_o2_multiplier: float = 7.5
@export var fire_smoke_basis_min_fraction: float = 0.40
@export var fire_smolder_hrr_fraction: float = 0.10
@export var fire_smolder_smoke_multiplier: float = 2.8

# Rendimiento de CO (kg/MJ)
# Derivado de ISO 19706 dividiendo el yield másico (kg/kg) por el calor efectivo
# de combustión de madera (~16 MJ/kg):
#   Combustión ventilada: 0.004 kg/kg ÷ 16 = 0.00025 kg/MJ
#   Combustión en déficit: 0.200 kg/kg ÷ 16 = 0.01250 kg/MJ
@export var co_base_yield_kg_per_MJ: float = 0.00025
@export var co_max_yield_kg_per_MJ: float = 0.01250

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
@export var fire_spread_max_layer_m: float = 1.8
@export var fire_spread_min_smoke_kg: float = 0.05

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
@export var doorway_heat_exchange_coeff: float = 0.38
@export var smoke_heat_mix_coeff: float = 0.025

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
@export var doorway_o2_min_band_m: float = 0.25
@export var doorway_o2_exchange_coeff: float = 1.8
@export var o2_network_iterations: int = 4

# ============================================================
# AJUSTES DE HUMO (se copian al SmokeModel)
# ============================================================

@export var smoke_density_kg_m3: float = 0.3
@export var base_spill_kg_s_per_m2: float = 0.26
@export var temp_push_factor: float = 0.008
@export var max_spill_kg_s: float = 1.4
@export var max_fraction_out_per_s: float = 0.08
@export var layer_relax_down: float = 0.18
@export var layer_relax_up: float = 0.015
@export var plume_fill_depth_coeff: float = 0.60
@export var plume_fill_response_s: float = 12.0
@export var plume_fill_max_fraction: float = 0.85
@export var thermal_plume_depth_scale: float = 0.40

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
	if glass_auto_break_enabled:
		_step_glass_failure(dt)
	_step_pressure_venting(dt)
	_step_smoke(dt)
	_clamp_rooms()
	_maybe_log_state()

	# Detener simulación cuando todos los fuegos se hayan extinguido.
	var any_fire_active: bool = false
	for room_id in building.get_rooms().keys():
		var room: RoomModel = building.get_room(room_id)
		if room != null and room.fire != null and room.hrr_kw > 0.0:
			any_fire_active = true
			break
	if not any_fire_active:
		_extinction_countdown -= dt
		if _extinction_countdown <= 0.0:
			is_finished = true
	else:
		_extinction_countdown = extinction_grace_s

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
	# max_hrr_kw: usa el valor de la sala si está definido, si no el global del engine
	fire.max_hrr_kw = room.max_hrr_kw if room.max_hrr_kw > 0.0 else fire_max_hrr_kw
	fire.secondary_hrr_gain_kw = fire_secondary_hrr_gain_kw
	fire.flashover_hrr_multiplier = fire_flashover_hrr_multiplier
	fire.flashover_min_hrr_kw = fire_flashover_min_hrr_kw
	fire.o2_nominal = fire_o2_nominal
	fire.o2_min_for_flame = fire_o2_min_for_flame
	fire.smoke_yield_kg_per_MJ = fire_smoke_yield_kg_per_MJ
	fire.o2_consumption_kg_per_MJ = fire_o2_consumption_kg_per_MJ
	# Carga de combustible específica de la sala (MJ según tipo y área)
	fire.fuel_energy_MJ = room.fuel_energy_MJ if room.fuel_energy_MJ > 0.0 else fire.fuel_energy_MJ
	fire.remaining_fuel_MJ = fire.fuel_energy_MJ

	room.fire = fire
	room.fire_time_s = 0.0
	room.flashover_triggered = false

# ============================================================
# ROTURA DE CRISTAL
# ============================================================
# Cada ventana exterior recibe una temperatura de rotura aleatoria la primera
# vez que la capa superior supera glass_break_temp_c.  El cristal se abre
# progresivamente una vez alcanzada esa temperatura personalizada.
# La aleatoriedad modela variabilidad en calidad del cristal, sombreado, etc.

func _step_glass_failure(dt: float) -> void:
	var openings: Array = building.get_openings()
	for i in range(openings.size()):
		var op: OpeningModel = openings[i]
		if op.type != OpeningModel.Type.WINDOW:
			continue
		# Determinar cuál lado es interior
		var indoor_id: int = -1
		if op.b == BuildingModel.OUTSIDE_ID:
			indoor_id = op.a
		elif op.a == BuildingModel.OUTSIDE_ID:
			indoor_id = op.b
		else:
			continue
		var room: RoomModel = building.get_room(indoor_id)
		if room == null:
			continue
		# Asignar temperatura de rotura aleatoria una sola vez por ventana
		if not _glass_break_temps.has(i):
			_glass_break_temps[i] = glass_break_temp_c + randf_range(
					-glass_break_temp_spread_c * 0.5,
					glass_break_temp_spread_c)
		var break_temp: float = _glass_break_temps[i]
		# Abrir progresivamente una vez superada la temperatura de rotura
		if room.temp_upper_c >= break_temp:
			op.open_fraction = minf(glass_max_open_fraction,
					op.open_fraction + glass_open_rate_per_s * dt)


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
		var can_flame: bool = room.o2 > fire.o2_min_for_flame

		# Corte exacto en el mínimo absoluto. Sin buffer +0.01:
		# evita el ciclo on/off cuando O2 oscila justo en el umbral.
		# Para valores de O2 bajos pero > min, o2_factor ya reduce el HRR suavemente.
		if false:
			room.hrr_kw = 0.0
			room.smoke_prod_kg_s = 0.0
			# Fuego sofocado por O2 insuficiente: cuenta tiempo de agonía
			if room.fire_time_s > 60.0:
				room.fire_low_hrr_time_s += dt
				if room.fire_low_hrr_time_s >= fire_extinction_delay_s:
					room.fire = null
					room.fire_low_hrr_time_s = 0.0
			continue

		if can_flame:
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
		var smoke_basis_kw: float = lerpf(
			hrr_kw * fire_smoke_basis_min_fraction,
			hrr_kw,
			sqrt(o2_factor)
		)

		# Escala lineal: físicamente correcto, fires se apagan al llegar a o2_min no antes
		room.hrr_kw = hrr_kw * o2_factor

		# Límite de Kawagoe (ventilación controlada).
		# Con ventanas exteriores abiertas la combustión no puede superar el calor
		# que el flujo de O₂ a través de los huecos puede sostener.
		var _kaw_fac: float = _kawagoe_factor_for_room(room_id)
		if _kaw_fac > 0.0:
			room.hrr_kw = minf(room.hrr_kw, kawagoe_coeff * _kaw_fac)
		if not can_flame:
			room.hrr_kw = 0.0
			smoke_basis_kw = maxf(smoke_basis_kw, hrr_kw * fire_smolder_hrr_fraction)

		var smoke_yield_kg_per_MJ: float = lerpf(
			fire.smoke_yield_kg_per_MJ * fire_smoke_yield_low_o2_multiplier,
			fire.smoke_yield_kg_per_MJ,
			o2_factor
		)
		if not can_flame:
			smoke_yield_kg_per_MJ *= fire_smolder_smoke_multiplier
		room.smoke_prod_kg_s = _compute_smoke_production_kg_s(
			smoke_basis_kw,
			smoke_yield_kg_per_MJ
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

		# Generación de CO: mayor rendimiento con poco O2 (combustión incompleta)
		var co_yield: float = lerpf(co_max_yield_kg_per_MJ, co_base_yield_kg_per_MJ, o2_factor)
		var co_basis_MJ: float = maxf(energy_released_MJ, smoke_basis_kw * dt / 1000.0 * 0.35)
		room.co_kg += co_yield * co_basis_MJ

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
			if room_b.temp_upper_c >= fire_spread_ignition_temp_c \
					and room_b.h_layer_m <= fire_spread_max_layer_m \
					and room_b.smoke_kg >= fire_spread_min_smoke_kg:
				ignite_room(op.b)
				print("[FireSpread] Ignición por calor: Room %d → Room %d (%.0f°C)" % [op.a, op.b, room_b.temp_upper_c])

		# Propagación B → A
		if room_b.fire != null and room_a.fire == null:
			if room_a.temp_upper_c >= fire_spread_ignition_temp_c \
					and room_a.h_layer_m <= fire_spread_max_layer_m \
					and room_a.smoke_kg >= fire_spread_min_smoke_kg:
				ignite_room(op.a)
				print("[FireSpread] Ignición por calor: Room %d → Room %d (%.0f°C)" % [op.b, op.a, room_a.temp_upper_c])


# ============================================================
# KAWAGOE — FACTOR DE VENTILACIÓN EXTERIOR
# ============================================================

## Retorna Σ(A_v_eff × √H_v) para todas las ventanas exteriores abiertas de
## la sala indicada.  A_v_eff = width × height × open_fraction (m²).
## Resultado en m^(5/2).  0.0 si no hay ventanas abiertas.
func _kawagoe_factor_for_room(room_id: int) -> float:
	var factor: float = 0.0
	for op in building.get_openings():
		if op.type != OpeningModel.Type.WINDOW:
			continue
		if op.open_fraction <= 0.0:
			continue
		var indoor_id: int = -1
		if op.b == BuildingModel.OUTSIDE_ID:
			indoor_id = op.a
		elif op.a == BuildingModel.OUTSIDE_ID:
			indoor_id = op.b
		else:
			continue
		if indoor_id != room_id:
			continue
		var a_eff: float = op.width_m * op.height_m * op.open_fraction
		factor += a_eff * sqrt(op.height_m)
	return factor

## Retorna la open_fraction máxima entre las ventanas exteriores de la sala.
## Devuelve -1.0 si la sala no tiene ninguna ventana exterior.
func _window_open_max_for_room(room_id: int) -> float:
	var has_window: bool = false
	var max_frac: float = 0.0
	for op in building.get_openings():
		if op.type != OpeningModel.Type.WINDOW:
			continue
		var indoor_id: int = -1
		if op.b == BuildingModel.OUTSIDE_ID:
			indoor_id = op.a
		elif op.a == BuildingModel.OUTSIDE_ID:
			indoor_id = op.b
		else:
			continue
		if indoor_id != room_id:
			continue
		has_window = true
		max_frac = maxf(max_frac, op.open_fraction)
	return max_frac if has_window else -1.0

func _ambient_temp_c() -> float:
	return building.outside_temp_c if building != null else 20.0

func _gas_density_kg_m3(temp_c: float) -> float:
	var ambient_k: float = _ambient_temp_c() + 273.15
	var gas_k: float = maxf(ambient_k, temp_c + 273.15)
	return 1.2 * ambient_k / gas_k

func _estimate_target_upper_gas_mass_kg(room: RoomModel) -> float:
	if room == null:
		return 0.0

	var target_depth_m: float = _estimate_plume_upper_depth_m(room)
	if target_depth_m <= 0.0:
		return 0.0

	var target_volume_m3: float = room.floor_area_m2() * target_depth_m
	var entrained_temp_c: float = maxf(
		room.temp_lower_c + 60.0,
		minf(room.temp_upper_c, room.temp_lower_c + 180.0)
	)
	return target_volume_m3 * _gas_density_kg_m3(entrained_temp_c)

func _remove_upper_layer_fraction(room: RoomModel, fraction: float) -> void:
	if room == null:
		return

	var frac: float = clampf(fraction, 0.0, 1.0)
	if frac <= 0.0:
		return

	room.upper_gas_kg *= (1.0 - frac)
	room.upper_energy_kj *= (1.0 - frac)

func _sync_room_upper_layer(room: RoomModel, dt: float) -> void:
	if room == null:
		return

	var ambient_c: float = _ambient_temp_c()
	room.upper_gas_kg = maxf(0.0, room.upper_gas_kg)
	room.upper_energy_kj = maxf(0.0, room.upper_energy_kj)

	if room.upper_gas_kg <= 0.0001 or room.upper_energy_kj <= 0.0001:
		room.upper_gas_kg = 0.0
		room.upper_energy_kj = 0.0
		room.temp_upper_c = maxf(room.temp_lower_c, ambient_c)
		smoke_model.recompute_layer_from_mass(room, dt)
		return

	room.temp_upper_c = ambient_c + room.upper_energy_kj / maxf(0.05, room.upper_gas_kg)
	room.temp_upper_c = clampf(room.temp_upper_c, room.temp_lower_c, max_upper_temp_c)
	room.upper_energy_kj = room.upper_gas_kg * maxf(0.0, room.temp_upper_c - ambient_c)
	smoke_model.recompute_layer_from_mass(room, dt)

func _estimate_plume_upper_depth_m(room: RoomModel) -> float:
	if room == null or room.hrr_kw <= 0.0:
		return 0.0

	var floor_area_m2: float = maxf(1.0, room.floor_area_m2())
	var response: float = 1.0
	if plume_fill_response_s > 0.0:
		response = 1.0 - exp(-room.fire_time_s / plume_fill_response_s)

	# Heurística simple de entrainment para aproximar la masa de gases calientes
	# que alimenta la capa superior en un modelo zonal.
	var depth_m: float = plume_fill_depth_coeff * sqrt(room.hrr_kw) * response / floor_area_m2
	var max_depth_m: float = room.height_m * plume_fill_max_fraction
	return clampf(depth_m, 0.0, max_depth_m)

func _effective_hot_layer_height_m(room: RoomModel) -> float:
	if room == null:
		return 0.0

	var plume_layer_m: float = room.height_m - _estimate_plume_upper_depth_m(room)
	return clampf(minf(room.h_layer_m, plume_layer_m), 0.0, room.height_m)

func _compute_o2_factor(o2: float, nominal: float, min_o2: float) -> float:
	if o2 <= min_o2:
		return 0.0

	var o2_ratio: float = (o2 - min_o2) / maxf(0.001, nominal - min_o2)
	return clampf(o2_ratio, 0.0, 1.0)

func _compute_smoke_production_kg_s(hrr_kw: float, smoke_yield_kg_per_MJ: float) -> float:
	var hrr_MJ_s: float = hrr_kw / 1000.0
	return hrr_MJ_s * smoke_yield_kg_per_MJ

func _compute_room_air_mass_kg(room: RoomModel, air_density_kg_m3: float) -> float:
	if room == null:
		return 0.1

	return maxf(0.1, room.volume_m3()) * air_density_kg_m3

func _compute_room_o2_pull_factor(room: RoomModel) -> float:
	if room == null:
		return 1.0

	var deficit: float = clampf(
		(fire_o2_nominal - room.o2) / maxf(0.001, fire_o2_nominal - fire_o2_min_for_flame),
		0.0,
		1.0
	)
	var fire_pull: float = clampf(room.hrr_kw / maxf(1.0, fire_max_hrr_kw), 0.0, 1.0)
	var thermal_pull: float = clampf((room.temp_upper_c - room.temp_lower_c) / 250.0, 0.0, 1.0)
	return 1.0 + deficit * 1.5 + fire_pull * 1.25 + thermal_pull * 0.5

func _redistribute_o2_across_open_network(dt: float, air_density_kg_m3: float) -> void:
	var rooms: Dictionary = building.get_rooms()
	if rooms.is_empty():
		return

	var air_mass_by_room: Dictionary = {}
	var o2_mass_by_room: Dictionary = {}

	for room_id in rooms.keys():
		var room: RoomModel = building.get_room(room_id)
		if room == null:
			continue

		var air_mass_kg: float = _compute_room_air_mass_kg(room, air_density_kg_m3)
		air_mass_by_room[room_id] = air_mass_kg
		o2_mass_by_room[room_id] = air_mass_kg * clampf(room.o2, 0.0, o2_nominal)

	var iterations: int = max(1, o2_network_iterations)
	for _iteration in range(iterations):
		var delta_o2_mass: Dictionary = {}
		for room_id in air_mass_by_room.keys():
			delta_o2_mass[room_id] = 0.0

		for op in building.get_openings():
			if op.open_fraction <= 0.0:
				continue
			if op.a == BuildingModel.OUTSIDE_ID or op.b == BuildingModel.OUTSIDE_ID:
				continue

			var room_a: RoomModel = building.get_room(op.a)
			var room_b: RoomModel = building.get_room(op.b)
			if room_a == null or room_b == null:
				continue

			var air_mass_a: float = air_mass_by_room.get(op.a, 0.0)
			var air_mass_b: float = air_mass_by_room.get(op.b, 0.0)
			if air_mass_a <= 0.0 or air_mass_b <= 0.0:
				continue

			var o2_a: float = o2_mass_by_room.get(op.a, 0.0) / air_mass_a
			var o2_b: float = o2_mass_by_room.get(op.b, 0.0) / air_mass_b
			var o2_diff: float = absf(o2_a - o2_b)
			if o2_diff < 0.001:
				continue

			var source_id: int = op.a if o2_a >= o2_b else op.b
			var sink_id: int = op.b if source_id == op.a else op.a
			var sink_room: RoomModel = room_b if sink_id == op.b else room_a
			var source_air_mass: float = air_mass_by_room.get(source_id, 0.0)
			var sink_air_mass: float = air_mass_by_room.get(sink_id, 0.0)
			if source_air_mass <= 0.0 or sink_air_mass <= 0.0:
				continue

			var area_open_m2: float = op.width_m * op.height_m * op.open_fraction
			if area_open_m2 <= 0.0:
				continue

			var pull_factor: float = _compute_room_o2_pull_factor(sink_room)
			var gradient_factor: float = clampf(
				o2_diff / maxf(0.005, fire_o2_nominal - fire_o2_min_for_flame),
				0.0,
				1.0
			)
			var exchange_air_kg: float = area_open_m2 * air_density_kg_m3 * o2_mix_rate * dt
			exchange_air_kg *= lerpf(0.7, 2.4, gradient_factor) * pull_factor

			var min_air_mass: float = minf(source_air_mass, sink_air_mass)
			exchange_air_kg = minf(exchange_air_kg, min_air_mass * 0.04)
			if exchange_air_kg <= 0.0:
				continue

			var source_o2: float = o2_mass_by_room.get(source_id, 0.0) / source_air_mass
			var sink_o2: float = o2_mass_by_room.get(sink_id, 0.0) / sink_air_mass
			var net_source_delta: float = exchange_air_kg * (sink_o2 - source_o2)
			var net_sink_delta: float = -net_source_delta

			delta_o2_mass[source_id] = delta_o2_mass.get(source_id, 0.0) + net_source_delta
			delta_o2_mass[sink_id] = delta_o2_mass.get(sink_id, 0.0) + net_sink_delta

		for room_id in delta_o2_mass.keys():
			var air_mass_kg: float = air_mass_by_room.get(room_id, 0.0)
			if air_mass_kg <= 0.0:
				continue

			var updated_o2_mass: float = o2_mass_by_room.get(room_id, 0.0) + delta_o2_mass.get(room_id, 0.0)
			o2_mass_by_room[room_id] = clampf(updated_o2_mass, 0.0, air_mass_kg * o2_nominal)

	for room_id in air_mass_by_room.keys():
		var room: RoomModel = building.get_room(room_id)
		if room == null:
			continue

		var air_mass_kg: float = air_mass_by_room.get(room_id, 0.0)
		if air_mass_kg <= 0.0:
			continue

		room.o2 = clampf(o2_mass_by_room.get(room_id, 0.0) / air_mass_kg, 0.0, o2_nominal)

func _try_trigger_flashover(room: RoomModel) -> void:
	if room.fire == null:
		return

	if room.flashover_triggered:
		return

	var hot_enough: bool = room.temp_upper_c >= flashover_temp_c
	var enough_hrr: bool = room.hrr_kw >= room.fire.flashover_min_hrr_kw
	var layer_low_enough: bool = room.h_layer_m <= flashover_layer_m

	# Requerimos calor alto, HRR sostenido y un descenso real de la capa caliente.
	if hot_enough and enough_hrr and layer_low_enough:
		room.flashover_triggered = true
		# Escalar la ganancia secundaria en proporción al tamaño de la habitación.
		# Evita que habitaciones pequeñas (pasillo, baño) reciban el mismo
		# secondary_hrr_gain que la habitación de referencia (fire_max_hrr_kw).
		var gain: float = room.fire.secondary_hrr_gain_kw * (room.fire.max_hrr_kw / fire_max_hrr_kw)
		room.fire.max_hrr_kw += gain
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

			# Fuerza motriz del efecto chimenea a través de la apertura exterior.
			# Dos casos:
			#  A) Capa de humo por debajo del dintel: banda caliente empuja gases hacia fuera.
			#  B) Capa de humo por encima del dintel: la zona inferior (aire caliente limpio)
			#     también genera corriente convectiva — es el caso normal con ventana rota
			#     y fuego activo antes de que el humo llene la sala.
			var area_eff: float
			var t_in_k: float
			var h_drive: float

			var effective_layer_m: float = _effective_hot_layer_height_m(indoor)

			if effective_layer_m <= lintel_m:
				# (A) Humo ha bajado hasta el dintel o por debajo
				var hot_band_m: float = lintel_m - effective_layer_m
				h_drive = maxf(0.05, hot_band_m)
				area_eff = op.width_m * minf(h_drive, op.height_m) * op.open_fraction
				t_in_k = indoor.temp_upper_c + 273.15
			else:
				# (B) Humo por encima del dintel: zona inferior caliente impulsa el flujo
				h_drive = op.height_m
				area_eff = op.width_m * op.height_m * op.open_fraction
				t_in_k = indoor.temp_lower_c + 273.15

			if area_eff <= 0.0:
				continue

			var t_out_k: float = building.outside_temp_c + 273.15
			var delta_t_k: float = maxf(0.0, t_in_k - t_out_k)
			if delta_t_k < 2.0:
				continue
			var q: float = 0.65 * 0.5 * area_eff * sqrt(g_gravity * h_drive * delta_t_k / t_in_k)
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

			# Mantener el intercambio de especies acoplado al mismo mecanismo
			# que el calor y el humo entre salas: sin banda caliente sobre el
			# dintel, no trasladamos O2.
			var hot_band_m: float = lintel_m - _effective_hot_layer_height_m(hot_room)
			if hot_band_m <= 0.0:
				continue

			var h_drive_int: float = maxf(doorway_o2_min_band_m, hot_band_m)
			var t_hot_k: float = hot_room.temp_upper_c + 273.15

			var t_cold_k: float = cold_room.temp_upper_c + 273.15
			var delta_t_k: float = maxf(0.0, t_hot_k - t_cold_k)
			if delta_t_k < 2.0:
				continue

			var area_eff: float = op.width_m * minf(h_drive_int, op.height_m) * op.open_fraction
			var q: float = 0.65 * 0.5 * area_eff * sqrt(g_gravity * h_drive_int * delta_t_k / ((t_hot_k + t_cold_k) * 0.5))
			var exch: float = q * air_density_kg_m3 * dt * doorway_o2_exchange_coeff
			var mass_hot: float = maxf(0.1, hot_room.volume_m3()) * air_density_kg_m3
			var mass_cold: float = maxf(0.1, cold_room.volume_m3()) * air_density_kg_m3
			var new_hot: float = (hot_room.o2 * mass_hot + cold_room.o2 * exch) / (mass_hot + exch)
			var new_cold: float = (cold_room.o2 * mass_cold + hot_room.o2 * exch) / (mass_cold + exch)
			hot_room.o2 = clampf(new_hot, 0.0, o2_nominal)
			cold_room.o2 = clampf(new_cold, 0.0, o2_nominal)

	# Mezcla adicional a escala de red: una sala en combustión puede tirar O2
	# del resto del grafo de puertas abiertas, no solo de su vecino inmediato.
	_redistribute_o2_across_open_network(dt, air_density_kg_m3)

# ============================================================
# TEMPERATURA
# ============================================================

func _step_temperature(dt: float) -> void:
	var ambient_c: float = _ambient_temp_c()

	for room_id in building.get_rooms().keys():
		var room: RoomModel = building.get_room(room_id)
		if room == null:
			continue

		var target_upper_mass_kg: float = _estimate_target_upper_gas_mass_kg(room)
		if target_upper_mass_kg > room.upper_gas_kg:
			var mass_gain_kg: float = (target_upper_mass_kg - room.upper_gas_kg) * clampf(
				dt / maxf(1.0, plume_fill_response_s),
				0.0,
				1.0
			)
			room.upper_gas_kg += mass_gain_kg
			room.upper_energy_kj += mass_gain_kg * maxf(0.0, room.temp_lower_c - ambient_c)

		room.upper_energy_kj += room.hrr_kw * 0.35 * dt
		_sync_room_upper_layer(room, dt)

		var delta_ul: float = maxf(0.0, room.temp_upper_c - room.temp_lower_c)
		var energy_to_lower_kj: float = room.upper_gas_kg * delta_ul * upper_to_lower_loss_rate * dt
		var energy_to_ambient_kj: float = room.upper_gas_kg \
				* maxf(0.0, room.temp_upper_c - ambient_c) * upper_to_ambient_loss_rate * dt
		var wall_absorption_kj: float = room.upper_gas_kg \
				* maxf(0.0, room.temp_upper_c - ambient_c) * wall_absorption_rate * dt

		var requested_upper_loss_kj: float = energy_to_lower_kj + energy_to_ambient_kj + wall_absorption_kj
		if requested_upper_loss_kj > 0.0 and room.upper_energy_kj > 0.0:
			var loss_scale: float = minf(1.0, room.upper_energy_kj / requested_upper_loss_kj)
			energy_to_lower_kj *= loss_scale
			energy_to_ambient_kj *= loss_scale
			wall_absorption_kj *= loss_scale
			room.upper_energy_kj -= energy_to_lower_kj + energy_to_ambient_kj + wall_absorption_kj

		var lower_mass_kg: float = maxf(
			1.0,
			_gas_density_kg_m3(room.temp_lower_c) * room.floor_area_m2() * maxf(0.2, room.h_layer_m)
		)
		room.temp_lower_c += energy_to_lower_kj / lower_mass_kg
		room.temp_lower_c -= maxf(0.0, room.temp_lower_c - ambient_c) * 0.010 * dt
		room.temp_lower_c = maxf(ambient_c, room.temp_lower_c)
		_sync_room_upper_layer(room, dt)

	# --------------------------------------------------------
	# Transferencia convectiva entre habitaciones a través de
	# aperturas interiores abiertas (efecto chimenea bidireccional).
	# Usa la misma fórmula de flujo boyante que _step_oxygen.
	# --------------------------------------------------------
	var g_grav: float = 9.8
	var rho_air: float = 1.2  # kg/m³

	for op in building.get_openings():
		if op.open_fraction <= 0.0:
			continue
		if op.a == BuildingModel.OUTSIDE_ID or op.b == BuildingModel.OUTSIDE_ID:
			continue

		var room_a: RoomModel = building.get_room(op.a)
		var room_b: RoomModel = building.get_room(op.b)
		if room_a == null or room_b == null:
			continue

		var hot_room: RoomModel
		var cold_room: RoomModel
		if room_a.temp_upper_c >= room_b.temp_upper_c:
			hot_room = room_a
			cold_room = room_b
		else:
			hot_room = room_b
			cold_room = room_a

		var lintel_m: float = op.lintel_height_m()
		var hot_band_m: float = maxf(0.0, lintel_m - _effective_hot_layer_height_m(hot_room))
		if hot_band_m <= 0.0:
			continue

		var band_frac: float = clampf(hot_band_m / maxf(0.1, op.height_m), 0.0, 1.0)
		# El chorro que atraviesa la abertura no tiene la temperatura íntegra de la
		# capa superior: llega mezclado con gases más fríos de la zona inferior.
		var source_temp_c: float = lerpf(hot_room.temp_lower_c, hot_room.temp_upper_c, band_frac)
		var t_hot_k: float = source_temp_c + 273.15
		var t_cold_k: float = cold_room.temp_upper_c + 273.15
		var delta_t_k: float = maxf(0.0, t_hot_k - t_cold_k)
		if delta_t_k < 2.0:
			continue

		var area_eff: float = op.width_m * minf(hot_band_m, op.height_m) * op.open_fraction
		var q_vol: float = 0.65 * 0.5 * area_eff * sqrt(g_grav * hot_band_m * delta_t_k / ((t_hot_k + t_cold_k) * 0.5))
		var mass_exch: float = q_vol * rho_air * dt * doorway_heat_exchange_coeff

		var m_hot_kg: float = maxf(1.0, hot_room.volume_m3() * rho_air)
		var m_cold_kg: float = maxf(1.0, cold_room.volume_m3() * rho_air)

		# Limitar para evitar sobreoscilación: no puede transferirse más calor
		# del que equilibraría ambas habitaciones en un solo paso.
		var max_exch: float = (m_hot_kg * m_cold_kg) / (m_hot_kg + m_cold_kg)
		mass_exch = minf(mass_exch, max_exch)

		var gas_cap_kg: float = minf(hot_room.upper_gas_kg, maxf(0.10, hot_room.upper_gas_kg * 0.55))
		var gas_moved_kg: float = minf(mass_exch, gas_cap_kg)
		if gas_moved_kg <= 0.0:
			continue

		var energy_moved_kj: float = gas_moved_kg * maxf(0.0, source_temp_c - ambient_c)
		energy_moved_kj = minf(energy_moved_kj, hot_room.upper_energy_kj)

		hot_room.upper_gas_kg -= gas_moved_kg
		hot_room.upper_energy_kj = maxf(0.0, hot_room.upper_energy_kj - energy_moved_kj)

		cold_room.upper_gas_kg += gas_moved_kg
		cold_room.upper_energy_kj += energy_moved_kj

		_sync_room_upper_layer(hot_room, dt)
		_sync_room_upper_layer(cold_room, dt)

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

		_remove_upper_layer_fraction(room, frac_out)
		room.co_kg = maxf(0.0, room.co_kg * (1.0 - frac_out))
		_sync_room_upper_layer(room, dt)

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
	var co_delta_kg: Dictionary = {}
	var o2_delta_kg: Dictionary = {}
	var air_density_kg_m3_s: float = 1.2

	for room_id in building.get_rooms().keys():
		smoke_delta_kg[int(room_id)] = 0.0
		co_delta_kg[int(room_id)] = 0.0
		o2_delta_kg[int(room_id)] = 0.0

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
			var vented_kg: float = smoke_model.compute_outside_vented_kg(
				room_out,
				op,
				dt,
				_effective_hot_layer_height_m(room_out)
			)
			if vented_kg > 0.0:
				smoke_delta_kg[room_out.id] -= vented_kg
				smoke_vented_total_kg += vented_kg

				# CO ventilado proporcionalmente al humo que sale
				if room_out.smoke_kg > 0.001:
					var vent_frac: float = minf(1.0, vented_kg / room_out.smoke_kg)
					co_delta_kg[room_out.id] -= vent_frac * room_out.co_kg
					_remove_upper_layer_fraction(room_out, vent_frac)
					_sync_room_upper_layer(room_out, dt)

			continue

		var room_a: RoomModel = building.get_room(op.a)
		var room_b: RoomModel = building.get_room(op.b)

		if room_a == null or room_b == null:
			continue

		var transfers: Array[Dictionary] = smoke_model.compute_room_transfers(
			room_a,
			room_b,
			op,
			dt,
			_effective_hot_layer_height_m(room_a),
			_effective_hot_layer_height_m(room_b)
		)
		for transfer in transfers:
			var from_id: int = int(transfer.get("from", -1))
			var to_id: int = int(transfer.get("to", -1))
			var kg: float = float(transfer.get("kg", 0.0))

			var layer_factor: float = 1.0
			var source_room: RoomModel = null
			if from_id == room_a.id:
				source_room = room_a
			elif from_id == room_b.id:
				source_room = room_b

			if source_room != null and source_room.h_layer_m < 1.8:
				layer_factor = 1.5
			if source_room != null and source_room.h_layer_m < 1.2:
				layer_factor = 2.5
			if source_room != null and source_room.h_layer_m < 0.8:
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

		var max_allowed: float = room.smoke_kg * 0.25 * dt

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
			if source.smoke_kg > 0.001 and source.upper_gas_kg > 0.001:
				var transfer_frac: float = minf(1.0, kg / source.smoke_kg)
				var gas_moved_kg: float = minf(
					source.upper_gas_kg * transfer_frac,
					maxf(0.02, source.upper_gas_kg * 0.18)
				)
				var energy_moved_kj: float = minf(
					source.upper_energy_kj * transfer_frac,
					source.upper_energy_kj
				)

				source.upper_gas_kg = maxf(0.0, source.upper_gas_kg - gas_moved_kg)
				source.upper_energy_kj = maxf(0.0, source.upper_energy_kj - energy_moved_kj)
				target.upper_gas_kg += gas_moved_kg
				target.upper_energy_kj += energy_moved_kj

			# Contra-flujo: humo sale source→target, aire fresco entra target→source
			var o2_mix_factor: float = 0.08 * flow_ratio
			if o2_mix_factor > 0.0:
				var source_air_mass_kg: float = maxf(0.1, source.volume_m3()) * air_density_kg_m3_s
				var target_air_mass_kg: float = maxf(0.1, target.volume_m3()) * air_density_kg_m3_s
				var exchange_air_mass_kg: float = minf(source_air_mass_kg, target_air_mass_kg) \
						* clampf(o2_mix_factor, 0.0, 1.0)

				if exchange_air_mass_kg > 0.0:
					var source_o2_out_kg: float = source.o2 * exchange_air_mass_kg
					var target_o2_out_kg: float = target.o2 * exchange_air_mass_kg
					o2_delta_kg[from_id] += target_o2_out_kg - source_o2_out_kg
					o2_delta_kg[to_id] += source_o2_out_kg - target_o2_out_kg

			# CO viaja con el flujo de humo (misma proporción)
			if source.smoke_kg > 0.001:
				var co_moved: float = minf(kg / source.smoke_kg, 1.0) * source.co_kg
				co_delta_kg[from_id] -= co_moved
				co_delta_kg[to_id] += co_moved

	for room_id in building.get_rooms().keys():
		var room: RoomModel = building.get_room(room_id)
		if room == null:
			continue

		var room_volume_m3_s: float = maxf(0.1, room.volume_m3())
		var room_air_mass_kg: float = room_volume_m3_s * air_density_kg_m3_s
		var room_o2_mass_kg: float = room.o2 * room_air_mass_kg + float(o2_delta_kg[int(room_id)])
		room.o2 = clampf(room_o2_mass_kg / room_air_mass_kg, 0.0, o2_nominal)

		room.smoke_kg += float(smoke_delta_kg[int(room_id)])
		room.smoke_kg = maxf(0.0, room.smoke_kg)

		room.co_kg += float(co_delta_kg[int(room_id)])
		room.co_kg = maxf(0.0, room.co_kg)

		# ACH dilución: la misma infiltración que repone O2 arrastra CO y humo hacia fuera.
		# CO: delta = -room.co_kg * (ach / 3600) * dt  (exterior CO ≈ 0 ppm)
		var ach_rate: float = ach_infiltration / 3600.0
		var co_removed: float = room.co_kg * ach_rate * dt
		room.co_kg = maxf(0.0, room.co_kg - co_removed)

		# Humo: mismo mecanismo — partículas arrastradas por flujo de infiltración.
		var smoke_concentration: float = room.smoke_kg / (room_volume_m3_s * air_density_kg_m3_s)
		var smoke_removed: float = room_volume_m3_s * air_density_kg_m3_s * smoke_concentration * ach_rate * dt
		room.smoke_kg = maxf(0.0, room.smoke_kg - smoke_removed)

	for room_id in building.get_rooms().keys():
		var room: RoomModel = building.get_room(room_id)
		if room == null:
			continue

		_sync_room_upper_layer(room, dt)

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
		room.upper_gas_kg = maxf(0.0, room.upper_gas_kg)
		room.upper_energy_kj = maxf(0.0, room.upper_energy_kj)

		room.temp_lower_c = maxf(building.outside_temp_c, room.temp_lower_c)

		room.temp_upper_c = minf(room.temp_upper_c, max_upper_temp_c)
		if room.temp_upper_c < room.temp_lower_c:
			room.temp_lower_c = room.temp_upper_c
		room.upper_energy_kj = room.upper_gas_kg * maxf(0.0, room.temp_upper_c - _ambient_temp_c())

		room.hrr_kw = maxf(0.0, room.hrr_kw)
		room.smoke_prod_kg_s = maxf(0.0, room.smoke_prod_kg_s)
		room.smoke_kg = maxf(0.0, room.smoke_kg)
		room.co_kg = maxf(0.0, room.co_kg)

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
			"upper_gas_kg": room.upper_gas_kg,
			"upper_energy_kj": room.upper_energy_kj,

			"has_fire": room.fire != null,
			"flashover_triggered": room.flashover_triggered,

			"fuel_energy_MJ": room.fuel_energy_MJ,
			"remaining_fuel_MJ": room.fire.remaining_fuel_MJ if room.fire != null else 0.0,
			"co_ppm": room.co_kg * 29.0e6 / maxf(0.1, room.volume_m3() * 1.2 * 28.0),

			# Ventanas exteriores
			# window_open_max: -1 = sin ventanas, 0 = cerradas, >0 = rotas/abiertas
			"window_open_max": _window_open_max_for_room(room_id),
			"kawagoe_factor": _kawagoe_factor_for_room(room_id),
			"kawagoe_hrr_max_kw": kawagoe_coeff * maxf(0.0, _kawagoe_factor_for_room(room_id))
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

		var co_ppm_log: float = room.co_kg * 29.0e6 / maxf(0.1, room.volume_m3() * 1.2 * 28.0)
		var line := "ROOM %s | HRR=%.2f | Up=%.2f | Low=%.2f | Smoke=%.4f | Layer=%.2f | O2=%.4f | CO=%.0fppm" % [
			str(room.id),
			room.hrr_kw,
			room.temp_upper_c,
			room.temp_lower_c,
			room.smoke_kg,
			room.h_layer_m,
			room.o2,
			co_ppm_log
		]
		file.store_line(line)

	file.store_line("")
	file.close()

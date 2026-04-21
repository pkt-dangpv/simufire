extends Node
class_name SimulationEngine

const CombustionSystemScript = preload("res://sim/fire/CombustionSystem.gd")
const GasExchangeSystemScript = preload("res://sim/core/GasExchangeSystem.gd")
const OxygenExchangeSystemScript = preload("res://sim/core/OxygenExchangeSystem.gd")
const SimulationLogWriterScript = preload("res://sim/core/SimulationLogWriter.gd")
const SimulationStateBuilderScript = preload("res://sim/core/SimulationStateBuilder.gd")
const ThermalSystemScript = preload("res://sim/core/ThermalSystem.gd")
const FireSpreadSystemScript = preload("res://sim/core/FireSpreadSystem.gd")
const GlassFailureSystemScript = preload("res://sim/core/GlassFailureSystem.gd")

# ============================================================
# SIMULATION ENGINE
# ------------------------------------------------------------
# Coordinador central de la simulación.
# Responsabilidad:
# - llevar el tiempo de simulación
# - coordinar subsistemas (térmico, combustión, gases, humo,
#   propagación del fuego, rotura de cristal)
# - crear ignición inicial
# - exponer estado agregado
# ============================================================

@export var building_path: NodePath

var building: BuildingModel
var smoke_model: SmokeModel = SmokeModel.new()
var combustion_system: CombustionSystem = CombustionSystemScript.new()
var gas_exchange_system = GasExchangeSystemScript.new()
var oxygen_exchange_system = OxygenExchangeSystemScript.new()
var log_writer = SimulationLogWriterScript.new()
var state_builder = SimulationStateBuilderScript.new()
var thermal_system = ThermalSystemScript.new()
var fire_spread_system = FireSpreadSystemScript.new()
var glass_failure_system = GlassFailureSystemScript.new()

const o2_consumption_kg_per_MJ: float = 0.35
const o2_nominal: float = 0.209

# ============================================================
# TIEMPO
# ============================================================

@export var time_scale: float = 1.0
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

# ============================================================
# CONTABILIDAD GLOBAL DEL HUMO
# ============================================================

var smoke_generated_total_kg: float = 0.0
var smoke_vented_total_kg: float = 0.0
var smoke_deposited_total_kg: float = 0.0

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
@export var fire_smoke_yield_kg_per_MJ: float = 0.007
@export var fire_smoke_yield_low_o2_multiplier: float = 5.0
@export var fire_smoke_basis_min_fraction: float = 0.40
@export var fire_smolder_hrr_fraction: float = 0.10
@export var fire_smolder_smoke_multiplier: float = 2.8
@export var fire_subvent_o2_floor: float = 0.085
@export var fire_subvent_temp_start_c: float = 140.0
@export var fire_subvent_temp_full_c: float = 420.0
@export var fire_subvent_fill_start_fraction: float = 0.06
@export var fire_subvent_fill_full_fraction: float = 0.18
@export var fire_starvation_o2_factor: float = 0.003

# Rendimiento de CO (kg/MJ)
# Derivado de ISO 19706 dividiendo el yield másico (kg/kg) por el calor efectivo
# de combustión de madera (~16 MJ/kg):
#   Combustión ventilada: 0.004 kg/kg ÷ 16 = 0.00025 kg/MJ
#   Combustión en déficit: 0.200 kg/kg ÷ 16 = 0.01250 kg/MJ
@export var co_base_yield_kg_per_MJ: float = 0.00025
@export var co_max_yield_kg_per_MJ: float = 0.01250

# Rendimiento de CO2 (kg/MJ)
# Derivado de ISO 19706 dividiendo el yield másico (kg/kg) por el calor efectivo
# de combustión de madera (~16 MJ/kg):
#   Combustión ventilada: 1.33 kg/kg ÷ 16 = 0.0831 kg/MJ
#   Combustión en déficit: 0.95 kg/kg ÷ 16 = 0.0594 kg/MJ
@export var co2_base_yield_kg_per_MJ: float = 0.1000
@export var co2_min_yield_kg_per_MJ: float = 0.0715

# Umbral de extinción: si el HRR real cae por debajo durante fire_extinction_delay_s
# segundos, el fuego se considera extinto (modela apagado por falta de ventilación).
@export var fire_extinction_hrr_kw: float = 8.0
@export var fire_extinction_delay_s: float = 360.0

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
@export var fire_spread_ignition_temp_c: float = 340.0  # temperatura de la capa superior para ignición por calor
@export var fire_spread_max_layer_m: float = 1.6
@export var fire_spread_min_smoke_kg: float = 0.08
@export var fire_spread_min_source_hrr_kw: float = 180.0
@export var fire_spread_required_exposure_s: float = 35.0
@export var fire_spread_exposure_decay_s: float = 12.0

# ============================================================
# FLASHOVER SIMPLE
# ============================================================

@export var flashover_temp_c: float = 500.0
@export var flashover_layer_m: float = 1.2
@export var flashover_head_height_m: float = 1.8
@export var flashover_head_temp_c: float = 150.0
@export var flashover_require_tenability_loss: bool = true

# ============================================================
# AJUSTES TÉRMICOS
# ============================================================

@export var upper_to_lower_loss_rate: float = 0.025
@export var upper_to_ambient_loss_rate: float = 0.008
@export var lower_layer_warming_rate: float = 0.0180
@export var max_upper_temp_c: float = 900.0
@export var doorway_heat_exchange_coeff: float = 0.26
@export var smoke_heat_mix_coeff: float = 0.025
@export var thermal_gradient_min_band_m: float = 0.20
@export var thermal_gradient_max_band_m: float = 0.70
@export var thermal_gradient_band_fraction: float = 0.35
@export var floor_cooling_band_fraction: float = 0.24
@export var floor_cooling_band_max_m: float = 0.35
@export var survival_temp_threshold_c: float = 150.0
@export var layer_150c_relax_down_per_s: float = 0.35
@export var layer_150c_relax_up_per_s: float = 0.03

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

@export var ach_infiltration: float = 0.70  # Renovaciones de aire/hora — incluye fugas + retorno pasivo HVAC
@export var interior_transport_enabled: bool = true
@export var interior_transport_speed_m_s: float = 0.20
@export var interior_transport_min_distance_m: float = 0.50
@export var interior_o2_transport_delay_multiplier: float = 1.60
@export var doorway_o2_min_band_m: float = 0.25
@export var doorway_o2_exchange_coeff: float = 1.00
@export var doorway_o2_smoke_weight: float = 0.35
@export var doorway_o2_pressure_weight: float = 0.65
@export var doorway_o2_background_exchange_kg_s_m2: float = 0.035
@export var doorway_o2_background_max_fraction_per_step: float = 0.015
@export var doorway_o2_background_pressure_ref_pa: float = 1.5
@export var doorway_o2_background_min_factor: float = 0.30

# ============================================================
# AJUSTES DE HUMO (se copian al SmokeModel)
# ============================================================

@export var smoke_density_kg_m3: float = 0.22
@export var base_spill_kg_s_per_m2: float = 0.30
@export var temp_push_factor: float = 0.005
@export var max_spill_kg_s: float = 2.0
@export var max_fraction_out_per_s: float = 0.18
@export var layer_relax_down: float = 0.18
@export var layer_relax_up: float = 0.015
@export var plume_fill_depth_coeff: float = 0.60
@export var plume_fill_response_s: float = 12.0
@export var plume_fill_max_fraction: float = 0.85
@export var thermal_plume_depth_scale: float = 0.40
@export var target_smoke_resistance_coeff: float = 0.20
@export var target_layer_block_start_m: float = 0.65
@export var target_layer_block_full_m: float = 0.10
@export var interior_spill_start_layer_m: float = 2.0
@export var interior_spill_full_layer_m: float = 0.8
@export var pressure_spill_min_delta_pa: float = 0.5
@export var pressure_spill_ref_delta_pa: float = 8.0
@export var pressure_spill_max_multiplier: float = 2.5
@export var postfire_cleanup_hot_stop_c: float = 90.0
@export var postfire_cleanup_cool_full_c: float = 35.0
@export var postfire_cleanup_pressure_stop_pa: float = 0.8
@export var postfire_cleanup_pressure_full_pa: float = 0.10
@export var smoke_settling_base_per_s: float = 0.0
@export var smoke_settling_bonus_per_s: float = 0.0
@export var co_postfire_purge_base_per_s: float = 0.0
@export var co_postfire_purge_bonus_per_s: float = 0.0

# ============================================================
# REGISTRO DE VALORES
# ============================================================

@export var enable_logging: bool = true
@export var log_interval_s: float = 10.0
@export var log_file_path: String = "user://sim_log.txt"

# ============================================================
# SERVICIOS AUXILIARES
# ============================================================

func _sync_auxiliary_services() -> void:
	thermal_system.set_references(building, smoke_model)
	thermal_system.configure({
		"upper_to_lower_loss_rate": upper_to_lower_loss_rate,
		"upper_to_ambient_loss_rate": upper_to_ambient_loss_rate,
		"lower_layer_warming_rate": lower_layer_warming_rate,
		"wall_absorption_rate": wall_absorption_rate,
		"max_upper_temp_c": max_upper_temp_c,
		"doorway_heat_exchange_coeff": doorway_heat_exchange_coeff,
		"smoke_heat_mix_coeff": smoke_heat_mix_coeff,
		"thermal_gradient_min_band_m": thermal_gradient_min_band_m,
		"thermal_gradient_max_band_m": thermal_gradient_max_band_m,
		"thermal_gradient_band_fraction": thermal_gradient_band_fraction,
		"floor_cooling_band_fraction": floor_cooling_band_fraction,
		"floor_cooling_band_max_m": floor_cooling_band_max_m,
		"survival_temp_threshold_c": survival_temp_threshold_c,
		"layer_150c_relax_down_per_s": layer_150c_relax_down_per_s,
		"layer_150c_relax_up_per_s": layer_150c_relax_up_per_s,
		"plume_fill_depth_coeff": plume_fill_depth_coeff,
		"plume_fill_response_s": plume_fill_response_s,
		"plume_fill_max_fraction": plume_fill_max_fraction,
		"layer_relax_down": layer_relax_down,
		"layer_relax_up": layer_relax_up,
		"doorway_o2_min_band_m": doorway_o2_min_band_m,
		"doorway_o2_smoke_weight": doorway_o2_smoke_weight,
		"doorway_o2_pressure_weight": doorway_o2_pressure_weight,
		"pressure_spill_ref_delta_pa": pressure_spill_ref_delta_pa,
		"interior_spill_start_layer_m": interior_spill_start_layer_m
	})
	fire_spread_system.set_references(building, smoke_model)
	fire_spread_system.configure({
		"fire_spread_enabled": fire_spread_enabled,
		"fire_spread_ignition_temp_c": fire_spread_ignition_temp_c,
		"fire_spread_max_layer_m": fire_spread_max_layer_m,
		"fire_spread_min_smoke_kg": fire_spread_min_smoke_kg,
		"fire_spread_min_source_hrr_kw": fire_spread_min_source_hrr_kw,
		"fire_spread_required_exposure_s": fire_spread_required_exposure_s,
		"fire_spread_exposure_decay_s": fire_spread_exposure_decay_s
	})
	glass_failure_system.set_references(building)
	glass_failure_system.configure({
		"glass_break_temp_c": glass_break_temp_c,
		"glass_break_temp_spread_c": glass_break_temp_spread_c,
		"glass_open_rate_per_s": glass_open_rate_per_s,
		"glass_max_open_fraction": glass_max_open_fraction
	})
	gas_exchange_system.configure({
		"o2_nominal": o2_nominal,
		"window_leakage_area_m2": window_leakage_area_m2,
		"pressure_vent_threshold_pa": pressure_vent_threshold_pa,
		"ach_infiltration": ach_infiltration,
		"interior_transport_enabled": interior_transport_enabled,
		"interior_transport_speed_m_s": interior_transport_speed_m_s,
		"interior_transport_min_distance_m": interior_transport_min_distance_m,
		"postfire_cleanup_hot_stop_c": postfire_cleanup_hot_stop_c,
		"postfire_cleanup_cool_full_c": postfire_cleanup_cool_full_c,
		"postfire_cleanup_pressure_stop_pa": postfire_cleanup_pressure_stop_pa,
		"postfire_cleanup_pressure_full_pa": postfire_cleanup_pressure_full_pa,
		"smoke_settling_base_per_s": smoke_settling_base_per_s,
		"smoke_settling_bonus_per_s": smoke_settling_bonus_per_s,
		"co_postfire_purge_base_per_s": co_postfire_purge_base_per_s,
		"co_postfire_purge_bonus_per_s": co_postfire_purge_bonus_per_s
	})
	oxygen_exchange_system.configure({
		"o2_nominal": o2_nominal,
		"ach_infiltration": ach_infiltration,
		"interior_transport_enabled": interior_transport_enabled,
		"interior_transport_speed_m_s": interior_transport_speed_m_s,
		"interior_transport_min_distance_m": interior_transport_min_distance_m,
		"interior_o2_transport_delay_multiplier": interior_o2_transport_delay_multiplier,
		"doorway_o2_exchange_coeff": doorway_o2_exchange_coeff,
		"doorway_o2_background_exchange_kg_s_m2": doorway_o2_background_exchange_kg_s_m2,
		"doorway_o2_background_max_fraction_per_step": doorway_o2_background_max_fraction_per_step,
		"doorway_o2_background_pressure_ref_pa": doorway_o2_background_pressure_ref_pa,
		"doorway_o2_background_min_factor": doorway_o2_background_min_factor
	})
	log_writer.configure(enable_logging, log_interval_s, log_file_path)


func _build_state_context() -> Dictionary:
	return {
		"building": building,
		"smoke_model": smoke_model,
		"combustion_system": combustion_system,
		"sim_time_s": sim_time_s,
		"smoke_generated_total_kg": smoke_generated_total_kg,
		"smoke_vented_total_kg": smoke_vented_total_kg,
		"kawagoe_coeff": kawagoe_coeff,
		"estimate_temperature_callable": Callable(thermal_system, "estimate_temperature_at_height_m"),
		"effective_hot_layer_callable": Callable(thermal_system, "effective_hot_layer_height_m"),
		"compute_co_ppm_callable": Callable(thermal_system, "compute_co_ppm"),
		"compute_co2_ppm_callable": Callable(thermal_system, "compute_co2_ppm"),
		"is_quiescent_callable": Callable(thermal_system, "is_room_quiescent"),
		"window_open_max_callable": Callable(self, "_window_open_max_for_room"),
		"kawagoe_factor_callable": Callable(self, "_kawagoe_factor_for_room")
	}


func _build_gas_exchange_hooks() -> Dictionary:
	return {
		"effective_hot_layer_height_callable": Callable(thermal_system, "effective_hot_layer_height_m"),
		"remove_upper_layer_fraction_callable": Callable(thermal_system, "remove_upper_layer_fraction"),
		"sync_room_upper_layer_callable": Callable(thermal_system, "sync_room_upper_layer"),
		"compute_interroom_transfer_temp_callable": Callable(thermal_system, "compute_interroom_transfer_temp_c")
	}


func _build_oxygen_exchange_hooks() -> Dictionary:
	return {
		"effective_hot_layer_height_callable": Callable(thermal_system, "effective_hot_layer_height_m"),
		"build_interior_opening_flow_state_callable": Callable(thermal_system, "build_interior_opening_flow_state")
	}

# ============================================================
# READY
# ============================================================

func _ready() -> void:
	_resolve_building()
	combustion_system.bootstrap_building(building)
	_sync_smoke_model_settings()
	_sync_auxiliary_services()
	gas_exchange_system.reset()
	oxygen_exchange_system.reset()
	_reset_log_file()

	if auto_ignite_on_ready:
		ignite_room(ignition_room_id)

	print(log_writer.resolve_log_file_path())

# ============================================================
# REINICIAR LOG
# ============================================================

func _reset_log_file() -> void:
	_sync_auxiliary_services()
	log_writer.reset_log_file()

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
	smoke_model.target_smoke_resistance_coeff = target_smoke_resistance_coeff
	smoke_model.target_layer_block_start_m = target_layer_block_start_m
	smoke_model.target_layer_block_full_m = target_layer_block_full_m
	smoke_model.interior_spill_start_layer_m = interior_spill_start_layer_m
	smoke_model.interior_spill_full_layer_m = interior_spill_full_layer_m
	smoke_model.pressure_spill_min_delta_pa = pressure_spill_min_delta_pa
	smoke_model.pressure_spill_ref_delta_pa = pressure_spill_ref_delta_pa
	smoke_model.pressure_spill_max_multiplier = pressure_spill_max_multiplier

func reset_simulation(start_ignition_room_id: int = ignition_room_id, ignite_initial_fire: bool = true) -> void:
	if building == null:
		_resolve_building()
	if building == null:
		return

	_sync_smoke_model_settings()
	_sync_auxiliary_services()
	gas_exchange_system.reset()
	oxygen_exchange_system.reset()
	smoke_generated_total_kg = 0.0
	smoke_vented_total_kg = 0.0
	smoke_deposited_total_kg = 0.0
	sim_time_s = 0.0
	is_finished = false
	_extinction_countdown = extinction_grace_s
	glass_failure_system.reset()

	for room_id in building.get_rooms().keys():
		var room: RoomModel = building.get_room(room_id)
		_reset_room_state(room)

	combustion_system.bootstrap_building(building)
	_reset_log_file()

	if ignite_initial_fire:
		ignite_room(start_ignition_room_id)

func _reset_room_state(room: RoomModel) -> void:
	if room == null:
		return

	var ambient_c: float = thermal_system.ambient_temp_c()
	room.reset_dynamic_state(ambient_c, fire_o2_nominal)

	for obj in room.fuel_objects:
		if obj == null:
			continue
		obj.reset_dynamic_state(ambient_c)

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
	fire_spread_system.step(dt, Callable(self, "ignite_room"))
	_step_oxygen(dt)
	thermal_system.step(building, dt)
	if glass_auto_break_enabled:
		glass_failure_system.step(dt)
	_step_gas_exchange(dt)
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

	var fire: FireModel = combustion_system.create_legacy_room_fire(
		room,
		_build_fire_defaults()
	)
	if fire == null:
		return

	room.fire = fire
	room.fire_time_s = 0.0
	room.flashover_triggered = false
	room.fire_spread_exposure_s = 0.0
	room.fire_o2_extinguished = false


func _build_fire_defaults() -> Dictionary:
	return {
		"growth_alpha_kw_s2": fire_alpha_kw_s2,
		"max_hrr_kw": fire_max_hrr_kw,
		"secondary_hrr_gain_kw": fire_secondary_hrr_gain_kw,
		"flashover_hrr_multiplier": fire_flashover_hrr_multiplier,
		"flashover_min_hrr_kw": fire_flashover_min_hrr_kw,
		"o2_nominal": fire_o2_nominal,
		"o2_min_for_flame": fire_o2_min_for_flame,
		"smoke_yield_kg_per_MJ": fire_smoke_yield_kg_per_MJ,
		"o2_consumption_kg_per_MJ": fire_o2_consumption_kg_per_MJ
	}


func _build_room_combustion_context(room_id: int) -> Dictionary:
	var kawagoe_limit_kw: float = 0.0
	var kawagoe_factor: float = _kawagoe_factor_for_room(room_id)
	if kawagoe_factor > 0.0:
		kawagoe_limit_kw = kawagoe_coeff * kawagoe_factor

	return {
		"ambient_c": thermal_system.ambient_temp_c(),
		"thermal_feedback_coeff": thermal_feedback_coeff,
		"thermal_feedback_max": thermal_feedback_max,
		"fire_smoke_basis_min_fraction": fire_smoke_basis_min_fraction,
		"fire_smoke_yield_low_o2_multiplier": fire_smoke_yield_low_o2_multiplier,
		"fire_smolder_hrr_fraction": fire_smolder_hrr_fraction,
		"fire_smolder_smoke_multiplier": fire_smolder_smoke_multiplier,
		"fire_subvent_o2_floor": fire_subvent_o2_floor,
		"fire_subvent_temp_start_c": fire_subvent_temp_start_c,
		"fire_subvent_temp_full_c": fire_subvent_temp_full_c,
		"fire_subvent_fill_start_fraction": fire_subvent_fill_start_fraction,
		"fire_subvent_fill_full_fraction": fire_subvent_fill_full_fraction,
		"fire_starvation_o2_factor": fire_starvation_o2_factor,
		"fire_extinction_hrr_kw": fire_extinction_hrr_kw,
		"fire_extinction_delay_s": fire_extinction_delay_s,
		"fire_max_active_s": fire_max_active_s,
		"co_base_yield_kg_per_MJ": co_base_yield_kg_per_MJ,
		"co_max_yield_kg_per_MJ": co_max_yield_kg_per_MJ,
		"co2_base_yield_kg_per_MJ": co2_base_yield_kg_per_MJ,
		"co2_min_yield_kg_per_MJ": co2_min_yield_kg_per_MJ,
		"kawagoe_limit_kw": kawagoe_limit_kw
	}

# ============================================================
# INTERCAMBIO DE GASES
# ============================================================

func _step_gas_exchange(dt: float) -> void:
	if building == null:
		return

	var hooks: Dictionary = _build_gas_exchange_hooks()
	var pressure_result: Dictionary = gas_exchange_system.step_pressure_venting(building, dt, hooks)
	smoke_vented_total_kg += float(pressure_result.get("smoke_vented_kg", 0.0))

	var smoke_result: Dictionary = gas_exchange_system.step_smoke(building, smoke_model, dt, hooks)
	smoke_generated_total_kg += float(smoke_result.get("smoke_generated_kg", 0.0))
	smoke_vented_total_kg += float(smoke_result.get("smoke_vented_kg", 0.0))
	smoke_deposited_total_kg += float(smoke_result.get("smoke_deposited_kg", 0.0))


# ============================================================
# FUEGO
# ============================================================

func _step_fire(dt: float) -> void:
	for room_id in building.get_rooms().keys():
		var room: RoomModel = building.get_room(room_id)
		if room == null:
			continue

		var room_fire_active: bool = combustion_system.step_room_fire(
			room,
			dt,
			_build_room_combustion_context(room_id)
		)
		if room_fire_active:
			_try_trigger_flashover(room)

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

# ============================================================
# FLASHOVER
# ============================================================

func _try_trigger_flashover(room: RoomModel) -> void:
	if room.fire == null:
		return

	if room.flashover_triggered:
		return

	var hot_enough: bool = room.temp_upper_c >= flashover_temp_c
	var enough_hrr: bool = room.hrr_kw >= room.fire.flashover_min_hrr_kw
	var layer_low_enough: bool = smoke_model.get_visible_smoke_layer_height_m(room) <= flashover_layer_m
	var head_temp_c: float = thermal_system.estimate_temperature_at_height_m(room, flashover_head_height_m)
	var head_hot_enough: bool = head_temp_c >= flashover_head_temp_c
	var layer_150_low_enough: bool = room.layer_150c_m <= flashover_head_height_m
	var tenability_lost: bool = head_hot_enough or layer_150_low_enough

	# Requerimos calor alto, HRR sostenido y un descenso real de la capa caliente.
	if hot_enough and enough_hrr and layer_low_enough and (not flashover_require_tenability_loss or tenability_lost):
		room.flashover_triggered = true
		# Escalar la ganancia secundaria en proporción al tamaño de la habitación.
		# Evita que recintos con menor capacidad térmica reciban la misma
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
	if building == null:
		return

	oxygen_exchange_system.step(building, dt, _build_oxygen_exchange_hooks())

# ============================================================
# CONSERVACIÓN DE HUMO (DEBUG)
# ============================================================

func debug_check_smoke_conservation() -> void:
	var total_in_rooms: float = 0.0

	for room_id in building.get_rooms().keys():
		var room: RoomModel = building.get_room(room_id)
		if room == null:
			continue

		total_in_rooms += room.smoke_kg

	var expected: float = smoke_generated_total_kg - smoke_vented_total_kg - smoke_deposited_total_kg
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
		room.thermal_layer_m = clampf(room.thermal_layer_m, 0.0, room.height_m)
		room.layer_150c_m = clampf(room.layer_150c_m, 0.0, room.height_m)
		room.upper_gas_kg = maxf(0.0, room.upper_gas_kg)
		room.upper_energy_kj = maxf(0.0, room.upper_energy_kj)

		room.temp_lower_c = maxf(building.outside_temp_c, room.temp_lower_c)

		room.temp_upper_c = minf(room.temp_upper_c, max_upper_temp_c)
		if room.temp_upper_c < room.temp_lower_c:
			room.temp_lower_c = room.temp_upper_c
		if thermal_system.is_room_quiescent(room):
			room.upper_gas_kg = 0.0
			room.upper_energy_kj = 0.0
			room.temp_upper_c = room.temp_lower_c
			thermal_system.reset_thermal_layer(room)
			room.layer_150c_m = room.height_m
		else:
			room.upper_energy_kj = room.upper_gas_kg * maxf(0.0, room.temp_upper_c - thermal_system.ambient_temp_c())

		room.hrr_kw = maxf(0.0, room.hrr_kw)
		room.smoke_prod_kg_s = maxf(0.0, room.smoke_prod_kg_s)
		room.smoke_kg = maxf(0.0, room.smoke_kg)
		room.co_kg = maxf(0.0, room.co_kg)
		room.co2_kg = maxf(0.0, room.co2_kg)
		room.fed = maxf(0.0, room.fed)
		room.svv_pct = clampf(room.svv_pct, 0.0, 100.0)
		room.svv_worst_pct = minf(clampf(room.svv_worst_pct, 0.0, 100.0), room.svv_pct)

# ============================================================
# ESTADO AGREGADO
# ============================================================

func get_state() -> Dictionary:
	return state_builder.build_state(_build_state_context())

# ============================================================
# REGISTRO DE VALORES
# ============================================================

func _maybe_log_state() -> void:
	_sync_auxiliary_services()
	if not log_writer.should_log(sim_time_s):
		return

	log_writer.append_snapshot(sim_time_s, get_state())

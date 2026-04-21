extends Node
class_name SimulationEngine

const CombustionSystemScript = preload("res://sim/fire/CombustionSystem.gd")
const GasExchangeSystemScript = preload("res://sim/core/GasExchangeSystem.gd")
const OxygenExchangeSystemScript = preload("res://sim/core/OxygenExchangeSystem.gd")
const SimulationLogWriterScript = preload("res://sim/core/SimulationLogWriter.gd")
const SimulationStateBuilderScript = preload("res://sim/core/SimulationStateBuilder.gd")

# ============================================================
# SIMULATION ENGINE
# ------------------------------------------------------------
# Responsabilidad:
# - llevar el tiempo de simulaciÃ³n
# - coordinar subsistemas
# - crear igniciÃ³n inicial
# - actualizar fuego, O2, temperatura y humo
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

const o2_consumption_kg_per_MJ: float = 0.35
const o2_nominal: float = 0.209

# ============================================================
# TIEMPO
# ============================================================

@export var time_scale: float = 1.0
var sim_time_s: float = 0.0

# Segundos sin fuego activo antes de declarar la simulaciÃ³n terminada.
@export var extinction_grace_s: float = 30.0
var is_finished: bool = false
var _extinction_countdown: float = 30.0

# ============================================================
# ROTURA DE CRISTAL
# ============================================================
# Mantener desactivado por defecto: las ventanas solo cambian si se abren
# manualmente o si esta opciÃ³n se reactiva explÃ­citamente.
@export var glass_auto_break_enabled: bool = false
# Temperatura de capa superior a la que el cristal puede romperse.
@export var glass_break_temp_c: float = 250.0
# DispersiÃ³n aleatoria: Â± esta cantidad sobre glass_break_temp_c (distribuciÃ³n uniforme).
@export var glass_break_temp_spread_c: float = 80.0
# Velocidad a la que sube open_fraction tras la rotura (fracciÃ³n/segundo).
@export var glass_open_rate_per_s: float = 0.15
# open_fraction mÃ¡xima al romperse el cristal (1.0 = apertura completa).
@export var glass_max_open_fraction: float = 0.85
# Dict: opening_index â†’ temperatura de rotura asignada aleatoriamente al inicio.
var _glass_break_temps: Dictionary = {}

# ============================================================
# CONTABILIDAD GLOBAL DEL HUMO
# ============================================================

var smoke_generated_total_kg: float = 0.0
var smoke_vented_total_kg: float = 0.0
var smoke_deposited_total_kg: float = 0.0

# ============================================================
# IGNICIÃ“N INICIAL
# ============================================================

@export var ignition_room_id: int = 0
@export var auto_ignite_on_ready: bool = true

# ============================================================
# PARÃMETROS BASE DEL FUEGO
# ============================================================

@export var fire_alpha_kw_s2: float = 0.12
@export var fire_max_hrr_kw: float = 3000.0
@export var fire_secondary_hrr_gain_kw: float = 2500.0

# Coeficiente de Kawagoe (SFPE/Drysdale): HRR_max = kawagoe_coeff Ã— Î£(A_v Ã— âˆšH_v)
# Valor de referencia para madera: ~1500 kW/m^(5/2).  Reducir para materiales
# con rendimiento calÃ³rico menor.  Solo aplica cuando hay ventanas exteriores abiertas.
@export var kawagoe_coeff: float = 1500.0

@export var fire_o2_nominal: float = 0.209
@export var fire_o2_min_for_flame: float = 0.10
@export var fire_o2_consumption_kg_per_MJ: float = 0.076  # Regla de Thornton: 1/13.1 MJ/kgO2
# Rendimiento de humo (kg/MJ)
# SFPE: ~0.06 kg/kg Ã· 16 MJ/kg = 0.00375 kg/MJ
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
# Derivado de ISO 19706 dividiendo el yield mÃ¡sico (kg/kg) por el calor efectivo
# de combustiÃ³n de madera (~16 MJ/kg):
#   CombustiÃ³n ventilada: 0.004 kg/kg Ã· 16 = 0.00025 kg/MJ
#   CombustiÃ³n en dÃ©ficit: 0.200 kg/kg Ã· 16 = 0.01250 kg/MJ
@export var co_base_yield_kg_per_MJ: float = 0.00025
@export var co_max_yield_kg_per_MJ: float = 0.01250

# Umbral de extinciÃ³n: si el HRR real cae por debajo durante fire_extinction_delay_s
# segundos, el fuego se considera extinto (modela apagado por falta de ventilaciÃ³n).
@export var fire_extinction_hrr_kw: float = 8.0
@export var fire_extinction_delay_s: float = 360.0

# Tiempo mÃ¡ximo de actividad del fuego. Pasado este tiempo el combustible se considera
# agotado y el fuego se extingue (evita zombie fire en equilibrio O2/HRR).
@export var fire_max_active_s: float = 1800.0

@export var fire_flashover_hrr_multiplier: float = 2.2
@export var fire_flashover_min_hrr_kw: float = 300.0

# RetroalimentaciÃ³n radiativa: la capa superior caliente radia sobre el combustible
# aumentando la tasa de pirÃ³lisis. Modelo lineal sobre T_upper (simplificaciÃ³n de
# Stefan-Boltzmann). 0.0 = desactivado. Con 0.25: +25% de HRR a 520Â°C sobre ambiente.
@export var thermal_feedback_coeff: float = 0.15
@export var thermal_feedback_max: float = 1.5

# ============================================================
# PROPAGACIÃ“N DEL INCENDIO
# ============================================================

@export var fire_spread_enabled: bool = true
@export var fire_spread_ignition_temp_c: float = 340.0  # temperatura de la capa superior para igniciÃ³n por calor
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

# ============================================================
# AJUSTES TÃ‰RMICOS
# ============================================================

@export var upper_to_lower_loss_rate: float = 0.025
@export var upper_to_ambient_loss_rate: float = 0.008
@export var lower_layer_warming_rate: float = 0.012
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

# AbsorciÃ³n de calor por paredes â€” tÃ©rmino proporcional simple sobre (T_upper - T_ambient).
# Mismo patrÃ³n que upper_to_ambient_loss_rate: sin dividir por m_upper_kg â†’ estable.
# 0.003 /s â†’ a 800Â°C de diferencia: 2.4Â°C/s adicionales (modest, calibratable).
@export var wall_absorption_rate: float = 0.003

# ParÃ¡metro heredado de intento anterior (no usado en cÃ¡lculo, conservado por compatibilidad)
@export var wall_heat_transfer_w_m2k: float = 6.0

# ============================================================
# VENTILACIÃ“N PULSANTE POR FUGAS EN VENTANAS
# ============================================================

# Ãrea de fuga efectiva por ventana cerrada (huecos en marco, juntas degradadas).
# Valor tÃ­pico residencial: 0.003-0.008 mÂ². Con 0.005 mÂ²/ventana y Î”P=5 Pa â†’ ~0.01 kg/s.
@export var window_leakage_area_m2: float = 0.005

# Umbral de sobrepresiÃ³n para iniciar venteo. Por debajo no hay fuga neta.
@export var pressure_vent_threshold_pa: float = 2.0

# ============================================================
# OXÃGENO / MEZCLA
# ============================================================

@export var ach_infiltration: float = 0.5  # Renovaciones de aire/hora por fugas del edificio
@export var doorway_o2_min_band_m: float = 0.25
@export var doorway_o2_exchange_coeff: float = 1.70
@export var doorway_o2_smoke_weight: float = 0.35
@export var doorway_o2_pressure_weight: float = 0.65
@export var doorway_o2_background_exchange_kg_s_m2: float = 0.06
@export var doorway_o2_background_max_fraction_per_step: float = 0.015
@export var doorway_o2_background_pressure_ref_pa: float = 1.5
@export var doorway_o2_background_min_factor: float = 0.30

# ============================================================
# AJUSTES DE HUMO (se copian al SmokeModel)
# ============================================================

@export var smoke_density_kg_m3: float = 0.22
@export var base_spill_kg_s_per_m2: float = 0.50
@export var temp_push_factor: float = 0.008
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
	gas_exchange_system.configure({
		"o2_nominal": o2_nominal,
		"window_leakage_area_m2": window_leakage_area_m2,
		"pressure_vent_threshold_pa": pressure_vent_threshold_pa,
		"ach_infiltration": ach_infiltration,
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
		"estimate_temperature_callable": Callable(self, "_estimate_temperature_at_height_m"),
		"effective_hot_layer_callable": Callable(self, "_effective_hot_layer_height_m"),
		"compute_co_ppm_callable": Callable(self, "_compute_co_ppm"),
		"is_quiescent_callable": Callable(self, "_is_room_quiescent"),
		"window_open_max_callable": Callable(self, "_window_open_max_for_room"),
		"kawagoe_factor_callable": Callable(self, "_kawagoe_factor_for_room")
	}


func _build_gas_exchange_hooks() -> Dictionary:
	return {
		"effective_hot_layer_height_callable": Callable(self, "_effective_hot_layer_height_m"),
		"remove_upper_layer_fraction_callable": Callable(self, "_remove_upper_layer_fraction"),
		"sync_room_upper_layer_callable": Callable(self, "_sync_room_upper_layer"),
		"compute_interroom_transfer_temp_callable": Callable(self, "_compute_interroom_transfer_temp_c")
	}


func _build_oxygen_exchange_hooks() -> Dictionary:
	return {
		"effective_hot_layer_height_callable": Callable(self, "_effective_hot_layer_height_m"),
		"build_interior_opening_flow_state_callable": Callable(self, "_build_interior_opening_flow_state")
	}

# ============================================================
# READY
# ============================================================

func _ready() -> void:
	_resolve_building()
	combustion_system.bootstrap_building(building)
	_sync_smoke_model_settings()
	_sync_auxiliary_services()
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
		push_error("SimulationEngine: no se encontrÃ³ BuildingModel en building_path")

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
	smoke_generated_total_kg = 0.0
	smoke_vented_total_kg = 0.0
	smoke_deposited_total_kg = 0.0
	sim_time_s = 0.0
	is_finished = false
	_extinction_countdown = extinction_grace_s
	_glass_break_temps.clear()

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

	var ambient_c: float = _ambient_temp_c()
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
	_step_fire_spread(dt)
	_step_oxygen(dt)
	_step_temperature(dt)
	if glass_auto_break_enabled:
		_step_glass_failure(dt)
	_step_gas_exchange(dt)
	_clamp_rooms()
	_maybe_log_state()

	# Detener simulaciÃ³n cuando todos los fuegos se hayan extinguido.
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
# IGNICIÃ“N
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
		"ambient_c": _ambient_temp_c(),
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
		"kawagoe_limit_kw": kawagoe_limit_kw
	}

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
		# Determinar cuÃ¡l lado es interior
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
# PROPAGACIÃ“N DEL INCENDIO
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

		# PropagaciÃ³n A â†’ B
		if room_a.fire != null and room_b.fire == null:
			if _update_fire_spread_exposure(room_a, room_b, _dt):
				ignite_room(op.b)
				print("[FireSpread] IgniciÃ³n por calor: Room %d â†’ Room %d (%.0fÂ°C, %.1fs)" % [op.a, op.b, room_b.temp_upper_c, room_b.fire_spread_exposure_s])

		# PropagaciÃ³n B â†’ A
		if room_b.fire != null and room_a.fire == null:
			if _update_fire_spread_exposure(room_b, room_a, _dt):
				ignite_room(op.a)
				print("[FireSpread] IgniciÃ³n por calor: Room %d â†’ Room %d (%.0fÂ°C, %.1fs)" % [op.b, op.a, room_a.temp_upper_c, room_a.fire_spread_exposure_s])


func _update_fire_spread_exposure(source: RoomModel, target: RoomModel, dt: float) -> bool:
	if source == null or target == null:
		return false

	if source.fire == null or target.fire != null:
		target.fire_spread_exposure_s = 0.0
		return false

	var source_hot_enough: bool = source.hrr_kw >= fire_spread_min_source_hrr_kw
	var target_hot_enough: bool = target.temp_upper_c >= fire_spread_ignition_temp_c
	var target_layer_low_enough: bool = smoke_model.get_visible_smoke_layer_height_m(target) <= fire_spread_max_layer_m
	var target_smoky_enough: bool = target.smoke_kg >= fire_spread_min_smoke_kg

	if source_hot_enough and target_hot_enough and target_layer_low_enough and target_smoky_enough:
		target.fire_spread_exposure_s += dt
	else:
		var decay_step: float = dt * fire_spread_required_exposure_s / maxf(1.0, fire_spread_exposure_decay_s)
		target.fire_spread_exposure_s = maxf(0.0, target.fire_spread_exposure_s - decay_step)

	return target.fire_spread_exposure_s >= fire_spread_required_exposure_s


# ============================================================
# KAWAGOE â€” FACTOR DE VENTILACIÃ“N EXTERIOR
# ============================================================

## Retorna Î£(A_v_eff Ã— âˆšH_v) para todas las ventanas exteriores abiertas de
## la sala indicada.  A_v_eff = width Ã— height Ã— open_fraction (mÂ²).
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

## Retorna la open_fraction mÃ¡xima entre las ventanas exteriores de la sala.
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

func _reset_thermal_layer(room: RoomModel) -> void:
	if room == null:
		return

	room.thermal_layer_m = room.height_m

func _estimate_thermal_layer_height_m(room: RoomModel) -> float:
	if room == null:
		return 0.0

	if room.upper_gas_kg <= 0.000001:
		return room.height_m

	var hot_gas_density_kg_m3: float = _gas_density_kg_m3(room.temp_upper_c)
	var hot_gas_volume_m3: float = room.upper_gas_kg / maxf(0.05, hot_gas_density_kg_m3)
	var hot_depth_m: float = hot_gas_volume_m3 / maxf(0.01, room.floor_area_m2())
	return clampf(room.height_m - hot_depth_m, 0.0, room.height_m)

func _compute_interroom_transfer_temp_c(source: RoomModel, target: RoomModel, intensity: float) -> float:
	if source == null:
		return _ambient_temp_c()

	var transfer_intensity: float = clampf(intensity, 0.0, 1.0)
	var upper_weight: float = clampf(0.18 + 0.50 * transfer_intensity, 0.0, 0.78)
	var source_mix_temp_c: float = lerpf(source.temp_lower_c, source.temp_upper_c, upper_weight)
	var target_lower_c: float = target.temp_lower_c if target != null else _ambient_temp_c()
	var carry_factor: float = clampf(
		0.18 + 0.45 * transfer_intensity + smoke_heat_mix_coeff * 4.0,
		0.18,
		0.72
	)
	return lerpf(target_lower_c, source_mix_temp_c, carry_factor)

func _estimate_thermal_gradient_depth_m(room: RoomModel) -> float:
	if room == null:
		return 0.0

	var hot_depth_m: float = maxf(0.0, room.height_m - _effective_hot_layer_height_m(room))
	var smoke_depth_m: float = maxf(0.0, room.height_m - smoke_model.get_visible_smoke_layer_height_m(room))
	var ref_depth_m: float = maxf(hot_depth_m, smoke_depth_m * thermal_gradient_band_fraction)
	if ref_depth_m <= 0.000001:
		return 0.0

	var min_band_m: float = minf(thermal_gradient_min_band_m, room.height_m)
	var smooth_depth_m: float = ref_depth_m
	if min_band_m > 0.000001 and ref_depth_m < min_band_m:
		var blend: float = clampf(ref_depth_m / min_band_m, 0.0, 1.0)
		smooth_depth_m = lerpf(ref_depth_m, min_band_m, blend)

	return clampf(
		smooth_depth_m,
		0.0,
		minf(thermal_gradient_max_band_m, room.height_m)
	)


func _estimate_floor_cooling_band_m(room: RoomModel) -> float:
	if room == null:
		return 0.0

	var ambient_c: float = _ambient_temp_c()
	var lower_excess_c: float = maxf(0.0, room.temp_lower_c - ambient_c)
	if lower_excess_c <= 0.5:
		return 0.0

	var lower_layer_height_m: float = clampf(_effective_hot_layer_height_m(room), 0.0, room.height_m)
	if lower_layer_height_m <= 0.000001:
		return 0.0

	var activation: float = clampf(
		lower_excess_c / maxf(1.0, survival_temp_threshold_c - ambient_c),
		0.0,
		1.0
	)
	var band_m: float = lower_layer_height_m * floor_cooling_band_fraction * activation
	return clampf(band_m, 0.0, minf(floor_cooling_band_max_m, lower_layer_height_m))

func _estimate_temperature_at_height_m(room: RoomModel, height_m: float) -> float:
	if room == null:
		return _ambient_temp_c()

	var ambient_c: float = _ambient_temp_c()
	var z_m: float = clampf(height_m, 0.0, room.height_m)
	var gradient_depth_m: float = _estimate_thermal_gradient_depth_m(room)
	var floor_band_m: float = _estimate_floor_cooling_band_m(room)
	if gradient_depth_m <= 0.000001:
		if floor_band_m > 0.000001 and z_m <= floor_band_m:
			var floor_t_no_gradient: float = inverse_lerp(0.0, floor_band_m, z_m)
			return lerpf(ambient_c, room.temp_lower_c, floor_t_no_gradient)
		return room.temp_lower_c

	var gradient_bottom_m: float = clampf(room.height_m - gradient_depth_m, 0.0, room.height_m)
	if floor_band_m > 0.000001 and z_m <= floor_band_m:
		var floor_t: float = inverse_lerp(0.0, floor_band_m, z_m)
		return lerpf(ambient_c, room.temp_lower_c, floor_t)

	if z_m <= gradient_bottom_m:
		return room.temp_lower_c
	if z_m >= room.height_m:
		return room.temp_upper_c

	var t: float = inverse_lerp(gradient_bottom_m, room.height_m, z_m)
	return lerpf(room.temp_lower_c, room.temp_upper_c, t)

func _estimate_isotherm_height_m(room: RoomModel, threshold_c: float) -> float:
	if room == null:
		return 0.0

	var ambient_c: float = _ambient_temp_c()
	var floor_band_m: float = _estimate_floor_cooling_band_m(room)
	if threshold_c <= ambient_c:
		return 0.0
	if threshold_c <= room.temp_lower_c:
		if floor_band_m <= 0.000001 or absf(room.temp_lower_c - ambient_c) <= 0.001:
			return 0.0

		var floor_t: float = clampf(
			(threshold_c - ambient_c) / (room.temp_lower_c - ambient_c),
			0.0,
			1.0
		)
		return clampf(lerpf(0.0, floor_band_m, floor_t), 0.0, room.height_m)
	if threshold_c >= room.temp_upper_c:
		return room.height_m

	var gradient_depth_m: float = _estimate_thermal_gradient_depth_m(room)
	if gradient_depth_m <= 0.000001:
		return room.height_m

	var gradient_bottom_m: float = clampf(room.height_m - gradient_depth_m, 0.0, room.height_m)
	if absf(room.temp_upper_c - room.temp_lower_c) <= 0.001:
		return room.height_m

	var t: float = clampf(
		(threshold_c - room.temp_lower_c) / (room.temp_upper_c - room.temp_lower_c),
		0.0,
		1.0
	)
	return clampf(lerpf(gradient_bottom_m, room.height_m, t), 0.0, room.height_m)


func _update_room_layer_150c(room: RoomModel, dt: float) -> void:
	if room == null:
		return

	var raw_layer_150c_m: float = _estimate_isotherm_height_m(room, survival_temp_threshold_c)
	if room.layer_150c_m < 0.0 or room.layer_150c_m > room.height_m + 0.001:
		room.layer_150c_m = raw_layer_150c_m
		return

	if raw_layer_150c_m < room.layer_150c_m:
		var down_t: float = clampf(layer_150c_relax_down_per_s * dt, 0.0, 1.0)
		room.layer_150c_m = lerpf(room.layer_150c_m, raw_layer_150c_m, down_t)
	else:
		var up_t: float = clampf(layer_150c_relax_up_per_s * dt, 0.0, 1.0)
		room.layer_150c_m = lerpf(room.layer_150c_m, raw_layer_150c_m, up_t)

	room.layer_150c_m = clampf(room.layer_150c_m, 0.0, room.height_m)

func _compute_co_ppm(room: RoomModel) -> float:
	if room == null:
		return 0.0

	return room.co_kg * 29.0e6 / maxf(0.1, room.volume_m3() * 1.2 * 28.0)

func _is_room_quiescent(room: RoomModel) -> bool:
	if room == null:
		return true

	return (
		room.fire == null
		and room.hrr_kw <= 0.01
		and room.overpressure_pa <= 0.05
		and room.smoke_kg <= 0.0005
		and room.upper_gas_kg <= 0.001
		and room.upper_energy_kj <= 0.01
		and absf(room.temp_upper_c - _ambient_temp_c()) <= 0.5
	)


func _should_collapse_thermal_layer(room: RoomModel) -> bool:
	if room == null:
		return true

	return (
		room.fire == null
		and room.hrr_kw <= 0.01
		and room.overpressure_pa <= 0.10
		and room.smoke_kg <= 0.002
		and absf(room.temp_upper_c - room.temp_lower_c) <= 0.5
		and absf(room.temp_upper_c - _ambient_temp_c()) <= 1.0
	)

func _sync_room_upper_layer(room: RoomModel, dt: float) -> void:
	if room == null:
		return

	var ambient_c: float = _ambient_temp_c()
	room.upper_gas_kg = maxf(0.0, room.upper_gas_kg)
	room.upper_energy_kj = maxf(0.0, room.upper_energy_kj)

	if _should_collapse_thermal_layer(room):
		room.upper_gas_kg = 0.0
		room.upper_energy_kj = 0.0
		room.temp_upper_c = room.temp_lower_c
		_reset_thermal_layer(room)
		smoke_model.recompute_layer_from_mass(room, dt)
		return

	if room.upper_gas_kg <= 0.0001 or room.upper_energy_kj <= 0.0001:
		room.upper_gas_kg = 0.0
		room.upper_energy_kj = 0.0
		room.temp_upper_c = maxf(room.temp_lower_c, ambient_c)
		_reset_thermal_layer(room)
		smoke_model.recompute_layer_from_mass(room, dt)
		return

	room.temp_upper_c = ambient_c + room.upper_energy_kj / maxf(0.05, room.upper_gas_kg)
	room.temp_upper_c = clampf(room.temp_upper_c, room.temp_lower_c, max_upper_temp_c)
	room.upper_energy_kj = room.upper_gas_kg * maxf(0.0, room.temp_upper_c - ambient_c)
	var target_thermal_layer_m: float = _estimate_thermal_layer_height_m(room)
	if target_thermal_layer_m < room.thermal_layer_m:
		room.thermal_layer_m = lerpf(
			room.thermal_layer_m,
			target_thermal_layer_m,
			clampf(layer_relax_down * dt * 2.0, 0.0, 1.0)
		)
	else:
		room.thermal_layer_m = lerpf(
			room.thermal_layer_m,
			target_thermal_layer_m,
			clampf(layer_relax_up * dt, 0.0, 1.0)
		)
	smoke_model.recompute_layer_from_mass(room, dt)

func _estimate_plume_upper_depth_m(room: RoomModel) -> float:
	if room == null or room.hrr_kw <= 0.0:
		return 0.0

	var floor_area_m2: float = maxf(1.0, room.floor_area_m2())
	var response: float = 1.0
	if plume_fill_response_s > 0.0:
		response = 1.0 - exp(-room.fire_time_s / plume_fill_response_s)

	# HeurÃ­stica simple de entrainment para aproximar la masa de gases calientes
	# que alimenta la capa superior en un modelo zonal.
	var depth_m: float = plume_fill_depth_coeff * sqrt(room.hrr_kw) * response / floor_area_m2
	var max_depth_m: float = room.height_m * plume_fill_max_fraction
	return clampf(depth_m, 0.0, max_depth_m)

func _effective_hot_layer_height_m(room: RoomModel) -> float:
	if room == null:
		return 0.0

	var plume_layer_m: float = room.height_m - _estimate_plume_upper_depth_m(room)
	return clampf(minf(room.thermal_layer_m, plume_layer_m), 0.0, room.height_m)


func _interior_spill_trigger_layer_m(room: RoomModel, lintel_m: float) -> float:
	if room == null:
		return lintel_m

	return minf(lintel_m, clampf(interior_spill_start_layer_m, 0.0, room.height_m))

func _build_interior_opening_flow_state(room_a: RoomModel, room_b: RoomModel, op: OpeningModel) -> Dictionary:
	var state: Dictionary = {
		"active": false,
		"hot_room": null,
		"cold_room": null,
		"hot_band_m": 0.0,
		"smoke_band_m": 0.0,
		"h_drive_m": 0.0,
		"area_eff_m2": 0.0,
		"engagement": 0.0,
		"source_temp_c": 0.0,
		"temp_delta_k": 0.0
	}

	if room_a == null or room_b == null or op == null or op.open_fraction <= 0.0:
		return state

	var hot_room: RoomModel
	var cold_room: RoomModel
	if room_a.temp_upper_c > room_b.temp_upper_c:
		hot_room = room_a
		cold_room = room_b
	elif room_b.temp_upper_c > room_a.temp_upper_c:
		hot_room = room_b
		cold_room = room_a
	elif room_a.overpressure_pa >= room_b.overpressure_pa:
		hot_room = room_a
		cold_room = room_b
	else:
		hot_room = room_b
		cold_room = room_a

	var lintel_m: float = op.lintel_height_m()
	var spill_trigger_layer_m: float = _interior_spill_trigger_layer_m(hot_room, lintel_m)
	var hot_band_m: float = maxf(0.0, spill_trigger_layer_m - _effective_hot_layer_height_m(hot_room))
	var smoke_band_m: float = maxf(
		0.0,
		spill_trigger_layer_m - smoke_model.get_visible_smoke_layer_height_m(hot_room)
	)
	var band_ref_m: float = maxf(doorway_o2_min_band_m, op.height_m * 0.24)
	var smoke_factor: float = clampf(smoke_band_m / band_ref_m, 0.0, 1.0)
	var thermal_factor: float = clampf(hot_band_m / band_ref_m, 0.0, 1.0)
	var pressure_factor: float = clampf(
		maxf(0.0, hot_room.overpressure_pa - cold_room.overpressure_pa) / maxf(
			1.0,
			pressure_spill_ref_delta_pa
		),
		0.0,
		1.0
	)
	var band_factor: float = lerpf(thermal_factor, smoke_factor, doorway_o2_smoke_weight)
	var engagement: float = clampf(
		band_factor + pressure_factor * doorway_o2_pressure_weight,
		0.0,
		1.0
	)
	if engagement <= 0.0:
		return state

	var lower_counterflow_m: float = doorway_o2_min_band_m * clampf(0.35 + 0.65 * engagement, 0.0, 1.0)
	var h_drive_m: float = maxf(maxf(lower_counterflow_m, hot_band_m), smoke_band_m * 0.40)
	if h_drive_m <= 0.0:
		return state

	var area_eff_m2: float = op.width_m * minf(h_drive_m, op.height_m) * op.open_fraction
	if area_eff_m2 <= 0.0:
		return state

	var source_temp_c: float = _compute_interroom_transfer_temp_c(
		hot_room,
		cold_room,
		clampf(0.35 + 0.65 * engagement, 0.0, 1.0)
	)
	var sink_temp_c: float = lerpf(cold_room.temp_lower_c, cold_room.temp_upper_c, 0.20)
	var temp_delta_k: float = maxf(0.0, source_temp_c - sink_temp_c)
	if temp_delta_k < 2.0:
		return state

	state["active"] = true
	state["hot_room"] = hot_room
	state["cold_room"] = cold_room
	state["hot_band_m"] = hot_band_m
	state["smoke_band_m"] = smoke_band_m
	state["h_drive_m"] = h_drive_m
	state["area_eff_m2"] = area_eff_m2
	state["engagement"] = engagement
	state["source_temp_c"] = source_temp_c
	state["temp_delta_k"] = temp_delta_k
	return state

func _try_trigger_flashover(room: RoomModel) -> void:
	if room.fire == null:
		return

	if room.flashover_triggered:
		return

	var hot_enough: bool = room.temp_upper_c >= flashover_temp_c
	var enough_hrr: bool = room.hrr_kw >= room.fire.flashover_min_hrr_kw
	var layer_low_enough: bool = smoke_model.get_visible_smoke_layer_height_m(room) <= flashover_layer_m

	# Requerimos calor alto, HRR sostenido y un descenso real de la capa caliente.
	if hot_enough and enough_hrr and layer_low_enough:
		room.flashover_triggered = true
		# Escalar la ganancia secundaria en proporciÃ³n al tamaÃ±o de la habitaciÃ³n.
		# Evita que recintos con menor capacidad tÃ©rmica reciban la misma
		# secondary_hrr_gain que la habitaciÃ³n de referencia (fire_max_hrr_kw).
		var gain: float = room.fire.secondary_hrr_gain_kw * (room.fire.max_hrr_kw / fire_max_hrr_kw)
		room.fire.max_hrr_kw += gain
		room.hrr_kw *= room.fire.flashover_hrr_multiplier
		# Sincronizar fire_time con el HRR boosted para que la curva tÂ² no retroceda
		var t_to_hrr: float = sqrt(room.hrr_kw / maxf(0.001, room.fire.growth_alpha_kw_s2))
		room.fire_time_s = maxf(room.fire_time_s, t_to_hrr)

# ============================================================
# OXÃGENO
# ============================================================

func _step_oxygen(dt: float) -> void:
	if building == null:
		return

	oxygen_exchange_system.step(building, dt, _build_oxygen_exchange_hooks())

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
			_gas_density_kg_m3(room.temp_lower_c) * room.floor_area_m2() * maxf(0.2, _effective_hot_layer_height_m(room))
		)
		room.temp_lower_c += energy_to_lower_kj / lower_mass_kg
		room.temp_lower_c -= maxf(0.0, room.temp_lower_c - ambient_c) * 0.010 * dt
		room.temp_lower_c = maxf(ambient_c, room.temp_lower_c)
		_sync_room_upper_layer(room, dt)
		_update_room_layer_150c(room, dt)

	# --------------------------------------------------------
	# Transferencia convectiva entre habitaciones a travÃ©s de
	# aperturas interiores abiertas (efecto chimenea bidireccional).
	# Usa la misma fÃ³rmula de flujo boyante que _step_oxygen.
	# --------------------------------------------------------
	var g_grav: float = 9.8
	var rho_air: float = 1.2  # kg/mÂ³

	for op in building.get_openings():
		if op.open_fraction <= 0.0:
			continue
		if op.a == BuildingModel.OUTSIDE_ID or op.b == BuildingModel.OUTSIDE_ID:
			continue

		var room_a: RoomModel = building.get_room(op.a)
		var room_b: RoomModel = building.get_room(op.b)
		if room_a == null or room_b == null:
			continue

		var flow_state: Dictionary = _build_interior_opening_flow_state(room_a, room_b, op)
		if not bool(flow_state.get("active", false)):
			continue

		var hot_room: RoomModel = flow_state.get("hot_room", null)
		var cold_room: RoomModel = flow_state.get("cold_room", null)
		if hot_room == null or cold_room == null:
			continue

		var hot_band_m: float = float(flow_state.get("hot_band_m", 0.0))
		if hot_band_m <= 0.0:
			continue

		var engagement: float = float(flow_state.get("engagement", 0.0))
		var source_temp_c: float = float(flow_state.get("source_temp_c", hot_room.temp_upper_c))
		var t_hot_k: float = source_temp_c + 273.15
		var t_cold_k: float = cold_room.temp_upper_c + 273.15
		var delta_t_k: float = maxf(0.0, t_hot_k - t_cold_k)
		if delta_t_k < 2.0:
			continue

		var area_eff: float = float(flow_state.get("area_eff_m2", 0.0))
		if area_eff <= 0.0:
			continue

		var q_vol: float = 0.65 * 0.5 * area_eff * sqrt(g_grav * hot_band_m * delta_t_k / ((t_hot_k + t_cold_k) * 0.5))
		var thermal_engagement: float = engagement * 0.65
		var mass_exch: float = q_vol * rho_air * dt * doorway_heat_exchange_coeff * thermal_engagement

		var m_hot_kg: float = maxf(1.0, hot_room.volume_m3() * rho_air)
		var m_cold_kg: float = maxf(1.0, cold_room.volume_m3() * rho_air)

		# Limitar para evitar sobreoscilaciÃ³n: no puede transferirse mÃ¡s calor
		# del que equilibrarÃ­a ambas habitaciones en un solo paso.
		var max_exch: float = (m_hot_kg * m_cold_kg) / (m_hot_kg + m_cold_kg)
		mass_exch = minf(mass_exch, max_exch)

		var gas_cap_kg: float = minf(hot_room.upper_gas_kg, maxf(0.05, hot_room.upper_gas_kg * 0.16))
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
		_update_room_layer_150c(hot_room, dt)
		_update_room_layer_150c(cold_room, dt)

# ============================================================
# VENTILACIÃ“N PULSANTE POR FUGAS EN VENTANAS
# ============================================================
# Modelo de fuga por marco de ventana cerrada bajo condiciones de incendio.
# FÃ­sica:
#   - La capa superior caliente genera una sobrepresiÃ³n buoyante:
#       Î”P_buoyante = Ï_ext Ã— g Ã— h_humo Ã— (1 - T_ext_K / T_upper_K)
#   - overpressure_pa se relaja hacia Î”P_buoyante (constante de tiempo 5 s).
#   - Cuando overpressure_pa > pressure_vent_threshold_pa: gas caliente sale por
#     el hueco del marco (venteo), baja la presiÃ³n, entra aire fresco por abajo.
#   - El ciclo se repite â†’ comportamiento pulsante a escala de la simulaciÃ³n.
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
		if _is_room_quiescent(room):
			room.upper_gas_kg = 0.0
			room.upper_energy_kj = 0.0
			room.temp_upper_c = room.temp_lower_c
			_reset_thermal_layer(room)
			room.layer_150c_m = room.height_m
		else:
			room.upper_energy_kj = room.upper_gas_kg * maxf(0.0, room.temp_upper_c - _ambient_temp_c())

		room.hrr_kw = maxf(0.0, room.hrr_kw)
		room.smoke_prod_kg_s = maxf(0.0, room.smoke_prod_kg_s)
		room.smoke_kg = maxf(0.0, room.smoke_kg)
		room.co_kg = maxf(0.0, room.co_kg)

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

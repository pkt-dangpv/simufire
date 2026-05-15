extends RefCounted
class_name ThermalSystem

# ============================================================
# THERMAL SYSTEM
# ------------------------------------------------------------
# Responsabilidad:
# - cálculos de temperatura (capa superior/inferior)
# - gradientes térmicos y perfiles de temperatura
# - gestión de la capa de gases calientes (upper_gas_kg, upper_energy_kj)
# - isotermas y capas de tenabilidad (layer_150c)
# - flujo boyante convectivo entre habitaciones
# - funciones auxiliares térmicas (densidad, plume, etc.)
# ============================================================

# Dependencias externas
var _building: BuildingModel
var _smoke_model: SmokeModel

# Masa térmica de paredes
var wall_heat_capacity_kj_m2_k: float = 20.0  # kJ/m²K — cap. efectiva superficie (~5cm yeso)
var wall_core_decay_per_s: float = 0.0002     # τ ≈ 5000 s — conducción de la superficie al núcleo
# Temperatura actual de la superficie de pared por habitación (se resetea en configure())
var _wall_surface_temp_c: Dictionary = {}

const STEFAN_BOLTZMANN_KW_M2_K4: float = 5.670374419e-11

# Parámetros térmicos
var upper_to_lower_loss_rate: float = 0.025
var upper_to_ambient_loss_rate: float = 0.008
var lower_layer_warming_rate: float = 0.012
# Altura umbral de la zona inferior por debajo de la cual la transferencia upper→lower
# se atenúa linealmente hasta cero. Cuando la capa caliente desciende a nivel de
# suelo (<0.3 m), el volumen de la zona inferior es ínfimo y upper_gas_kg×rate
# sobreestima el flujo. CFAST muestra temp_lower estable (~67 °C) con HGT_1≈0.1 m.
var lower_layer_energy_fade_m: float = 0.50
var wall_absorption_rate: float = 0.003
var max_upper_temp_c: float = 900.0
var upper_radiative_loss_enabled: bool = true
# Umbral a partir del cual se activa la pérdida radiativa de la capa superior.
# FDS y modelos de dos zonas estándar incluyen radiación desde ~20°C; aquí se
# usa 80°C para evitar ruido numérico en los primeros instantes del arranque.
var upper_radiative_loss_start_c: float = 80.0
var upper_radiative_loss_emissivity: float = 0.90
var upper_radiative_loss_area_factor: float = 1.10
var upper_radiative_loss_max_fraction_per_step: float = 0.45
var doorway_heat_exchange_coeff: float = 1.0
var doorway_source_upper_weight: float = 0.60
var smoke_heat_mix_coeff: float = 0.025
var retained_hot_layer_temp_start_c: float = 100.0
var retained_hot_layer_temp_full_c: float = 350.0
var retained_hot_layer_o2_start: float = 0.18
var retained_hot_layer_o2_full: float = 0.10
var retained_hot_layer_max_fraction: float = 0.0
var outside_open_loss_area_fraction: float = 0.12
var outside_open_ambient_loss_multiplier: float = 5.0
var outside_open_wall_absorption_multiplier: float = 0.80
var outside_open_upper_mix_rate: float = 0.0
var outside_open_lower_warming_rate: float = 0.0
# Boost a la fracción convectiva cuando hay ventana exterior abierta.
# Modela que con aporte de aire fresco el fuego quema más completamente
# (chi_rad efectivo baja de ~0.70 a ~0.30 en fase bien ventilada).
# Efecto: conv_fraction_eff = conv_fraction * (1 + outside_open_upper_heat_boost * open_factor)
# Default 0.0 (sin efecto) — activar en JSON de caso para calibrar vs CFAST/FDS.
var outside_open_upper_heat_boost: float = 0.0
# Tasa de enfriamiento de la zona inferior por ingreso de aire fresco exterior.
# Solo actúa cuando outside_open_factor > 0 (ventana/puerta exterior abierta).
# Modela el reemplazamiento de gas caliente de la zona inferior por aire fresco.
# Default 0.0 — activar en JSON de caso para calibrar vs CFAST/FDS.
var outside_lower_fresh_air_cooling_rate: float = 0.0
var outside_open_background_heat_exchange_kg_s_m2: float = 0.030
var outside_open_background_heat_max_fraction_per_step: float = 0.020
var outside_open_background_heat_carry_factor: float = 0.42
var interior_background_heat_exchange_kg_s_m2: float = 0.015
var interior_background_heat_max_fraction_per_step: float = 0.012
var interior_background_heat_carry_factor: float = 0.38
var hot_gas_species_carry_fraction: float = 0.72
var hot_gas_smoke_carry_fraction: float = 0.38
var hot_gas_species_max_fraction_per_step: float = 0.22

# Propagación por radiación a través de aperturas interiores
# Basado en Stefan-Boltzmann: q''_rad = φ·ε·σ·(T_src⁴ − T_tgt⁴) · A_eff · smoke_atten
# φ=0.25 es el factor de vista efectivo para una apertura de puerta a sala adyacente.
var radiation_opening_enabled: bool = true
var radiation_flame_emissivity: float = 0.85
var radiation_opening_view_factor: float = 0.25
var radiation_smoke_attenuation_factor: float = 0.55
var radiation_min_source_temp_c: float = 200.0
var radiation_max_fraction_per_step: float = 0.25

# Gradiente térmico
var thermal_gradient_min_band_m: float = 0.20
var thermal_gradient_max_band_m: float = 0.70
var thermal_gradient_band_fraction: float = 0.35

# Banda de enfriamiento del suelo
var floor_cooling_band_fraction: float = 0.24
var floor_cooling_band_max_m: float = 0.35
var survival_temp_threshold_c: float = 150.0

# Relajación de capa 150°C
var layer_150c_relax_down_per_s: float = 0.05
var layer_150c_relax_up_per_s: float = 0.03

# Plume
var plume_fill_depth_coeff: float = 0.60
var plume_fill_response_s: float = 12.0
var plume_fill_max_fraction: float = 0.85
# McCaffrey (NBSIR 79-1910, 1979) far-field plume: ṁ_p = 0.071·Qc^(1/3)·z_eff^(5/3) [kg/s]
# Qc en kW, z_eff = max(0.1, z_interfaz - L_llama)  [m]
# Altura de llama Heskestad (1983): L_f = 0.235·Q_kW^0.4 - 1.02·D  [m]
# Cuando L_llama ≥ z_interfaz (llamas alcanzan capa superior) se usa el heurístico.
@export var plume_mccaffrey_enabled: bool = true
@export var plume_mccaffrey_qc_fraction: float = 0.70
# Diámetro de la base del fuego para la correlación de Heskestad.
# Valor por defecto 1.0 m, típico de un sofá/mueble residencial.
@export var plume_fire_diameter_m: float = 1.0
var plume_flame_region_entrainment_enabled: bool = false
var plume_flame_region_coeff: float = 0.071
var plume_flame_region_min_z_m: float = 0.20
var plume_flame_region_max_depth_fraction: float = 0.97

# FED calor
var fed_heat_enabled: bool = true
# ISO 13571 sec. 8.3: tIconv(min) = A * T^-n para exposicion convectiva.
# Rama por defecto: sujeto vestido, A=4.1e8 y n=3.61. La rama ligera/desnuda
# puede configurarse con A=5e7 y n=3.4 desde overrides.
@export var fed_heat_conv_a: float = 4.1e8
@export var fed_heat_conv_n: float = 3.61
# Umbral mínimo de temperatura para acumular FED térmico convectivo.
@export var fed_heat_conv_min_c: float = 60.0
# FED radiante: ISO 13571 §5.4.3
# Flujo crítico de tenabilidad: 2.5 kW/m² (ISO 13571, Table 1).
# t_tenab = fed_heat_rad_coeff / q^1.33 (ISO 13571 Eq. B.2).
@export var fed_heat_rad_a: float = 1.33e4   # constante para q en kW/m², t en s
# Factor de vista radiante cuando el ocupante está INMERSO en la capa caliente
# (hemisferio casi completo: ~0.50). Referencia: ISO 13571 §5.4.3.
@export var fed_heat_rad_view_factor: float = 0.50
# Factor de vista radiante cuando el ocupante está POR DEBAJO de la capa caliente
# (solo el hemisferio superior recibe la radiación de la capa: ~0.35).
@export var fed_heat_rad_view_factor_below: float = 0.35

# Relajación de capa
var layer_relax_down: float = 0.18
var layer_relax_up: float = 0.015

# Flujo en aberturas interiores
# Fracción radiativa χ_rad del HRR — física de zonas (SFPE Handbook 3rd Ed. §3.4).
# fracción convectiva = (1 − χ_rad) va directamente a la capa superior.
# A O2 normal (~21 %): χ_rad ≈ 0.35 → conv ≈ 0.65.
# A O2 bajo (6 %): combustión incompleta → más hollín → χ_rad sube a ≈ 0.50.
# Las variables upper_heat_capture_min/max se mantienen por compatibilidad de escenarios
# pero ya no controlan la física; usar hrr_chi_rad_normal/low_o2 para ajustar.
var hrr_chi_rad_normal: float = 0.35
var hrr_chi_rad_low_o2: float = 0.50
var hrr_rad_wall_fraction: float = 0.0       # fracción de χ_rad·HRR que va directamente a paredes
var upper_heat_capture_min: float = 0.10      # obsoleto — usar hrr_chi_rad_normal
var upper_heat_capture_max: float = 0.25      # obsoleto — usar hrr_chi_rad_normal
var upper_heat_capture_outside_open_bonus: float = 0.0  # obsoleto

var doorway_o2_min_band_m: float = 0.25
var doorway_o2_smoke_weight: float = 0.35
var doorway_o2_pressure_weight: float = 0.65
var pressure_spill_ref_delta_pa: float = 8.0
var interior_spill_start_layer_m: float = 2.0

# FED (ISO 13571) — componentes asfixiantes disponibles en el modelo
var fed_hypoxia_enabled: bool = true
var fed_hypoxia_a: float = 8.13
var fed_hypoxia_b: float = 0.54

# Conducción a través de paredes compartidas entre salas geométricamente adyacentes
# ──────────────────────────────────────────────────────────────────────────────────
# Modela la transferencia de calor a través de la pared sólida cuando la puerta
# entre dos salas está cerrada (o no existe apertura). El calor fluye desde la
# superficie de pared caliente (sala en fuego) hacia la capa superior de la sala
# fría adyacente.
#
# U = 1.5 W/m²K = 0.0015 kW/m²K: partición ligera (yeso + montante metálico).
# Para mampostería/ladrillo usar U ≈ 0.8–1.0 W/m²K = 0.0008–0.001 kW/m²K.
# Referencia: ISO 6946 / EN 1745 — resistencia térmica de particiones interiores.
var wall_conduction_enabled: bool = true
var wall_conduction_u_kw_m2_k: float = 0.0015
var wall_conduction_max_fraction_per_step: float = 0.08
var wall_adjacency_tolerance_m: float = 0.10
var _adjacent_pairs: Array = []
var _adjacency_built: bool = false

# Budget energético — diagnóstico CFAST-lite (no intrusivo)
# Activar con energy_budget_enabled=true en configure(). Warning si residual > umbral.
var energy_budget_enabled: bool = false
var energy_budget_warn_fraction: float = 0.10
## Último budget por sala: {room_id -> {e_fire_kj, q_rad_kj, q_to_lower_kj, q_to_ambient_kj,
## q_wall_abs_kj, q_wall_emit_kj, de_upper_kj, q_residual_kj, chi_rad}}
var _energy_budget: Dictionary = {}


func get_energy_budget() -> Dictionary:
	return _energy_budget


func set_references(building: BuildingModel, smoke_model: SmokeModel) -> void:
	_building = building
	_smoke_model = smoke_model


func configure(settings: Dictionary) -> void:
	upper_to_lower_loss_rate = float(settings.get("upper_to_lower_loss_rate", upper_to_lower_loss_rate))
	upper_to_ambient_loss_rate = float(settings.get("upper_to_ambient_loss_rate", upper_to_ambient_loss_rate))
	lower_layer_warming_rate = float(settings.get("lower_layer_warming_rate", lower_layer_warming_rate))
	lower_layer_energy_fade_m = float(settings.get("lower_layer_energy_fade_m", lower_layer_energy_fade_m))
	lower_layer_energy_fade_m = float(settings.get("lower_layer_energy_fade_m", lower_layer_energy_fade_m))
	wall_absorption_rate = float(settings.get("wall_absorption_rate", wall_absorption_rate))
	wall_heat_capacity_kj_m2_k = float(settings.get("wall_heat_capacity_kj_m2_k", wall_heat_capacity_kj_m2_k))
	wall_core_decay_per_s = float(settings.get("wall_core_decay_per_s", wall_core_decay_per_s))
	_wall_surface_temp_c.clear()  # Resetear temperaturas de pared al reconfigurar
	max_upper_temp_c = float(settings.get("max_upper_temp_c", max_upper_temp_c))
	upper_radiative_loss_enabled = bool(settings.get("upper_radiative_loss_enabled", upper_radiative_loss_enabled))
	upper_radiative_loss_start_c = float(settings.get("upper_radiative_loss_start_c", upper_radiative_loss_start_c))
	upper_radiative_loss_emissivity = float(settings.get("upper_radiative_loss_emissivity", upper_radiative_loss_emissivity))
	upper_radiative_loss_area_factor = float(settings.get("upper_radiative_loss_area_factor", upper_radiative_loss_area_factor))
	upper_radiative_loss_max_fraction_per_step = float(
		settings.get(
			"upper_radiative_loss_max_fraction_per_step",
			upper_radiative_loss_max_fraction_per_step
		)
	)
	doorway_heat_exchange_coeff = float(settings.get("doorway_heat_exchange_coeff", doorway_heat_exchange_coeff))
	doorway_source_upper_weight = float(settings.get("doorway_source_upper_weight", doorway_source_upper_weight))
	smoke_heat_mix_coeff = float(settings.get("smoke_heat_mix_coeff", smoke_heat_mix_coeff))
	retained_hot_layer_temp_start_c = float(
		settings.get("retained_hot_layer_temp_start_c", retained_hot_layer_temp_start_c)
	)
	retained_hot_layer_temp_full_c = float(
		settings.get("retained_hot_layer_temp_full_c", retained_hot_layer_temp_full_c)
	)
	retained_hot_layer_o2_start = float(
		settings.get("retained_hot_layer_o2_start", retained_hot_layer_o2_start)
	)
	retained_hot_layer_o2_full = float(
		settings.get("retained_hot_layer_o2_full", retained_hot_layer_o2_full)
	)
	retained_hot_layer_max_fraction = float(
		settings.get("retained_hot_layer_max_fraction", retained_hot_layer_max_fraction)
	)
	outside_open_loss_area_fraction = float(
		settings.get("outside_open_loss_area_fraction", outside_open_loss_area_fraction)
	)
	outside_open_ambient_loss_multiplier = float(
		settings.get(
			"outside_open_ambient_loss_multiplier",
			outside_open_ambient_loss_multiplier
		)
	)
	outside_open_wall_absorption_multiplier = float(
		settings.get(
			"outside_open_wall_absorption_multiplier",
			outside_open_wall_absorption_multiplier
		)
	)
	outside_open_upper_mix_rate = float(
		settings.get("outside_open_upper_mix_rate", outside_open_upper_mix_rate)
	)
	outside_open_upper_heat_boost = float(
		settings.get("outside_open_upper_heat_boost", outside_open_upper_heat_boost)
	)
	outside_open_lower_warming_rate = float(
		settings.get("outside_open_lower_warming_rate", outside_open_lower_warming_rate)
	)
	outside_lower_fresh_air_cooling_rate = float(
		settings.get("outside_lower_fresh_air_cooling_rate", outside_lower_fresh_air_cooling_rate)
	)
	outside_open_background_heat_exchange_kg_s_m2 = float(
		settings.get(
			"outside_open_background_heat_exchange_kg_s_m2",
			outside_open_background_heat_exchange_kg_s_m2
		)
	)
	outside_open_background_heat_max_fraction_per_step = float(
		settings.get(
			"outside_open_background_heat_max_fraction_per_step",
			outside_open_background_heat_max_fraction_per_step
		)
	)
	outside_open_background_heat_carry_factor = float(
		settings.get(
			"outside_open_background_heat_carry_factor",
			outside_open_background_heat_carry_factor
		)
	)
	interior_background_heat_exchange_kg_s_m2 = float(
		settings.get(
			"interior_background_heat_exchange_kg_s_m2",
			interior_background_heat_exchange_kg_s_m2
		)
	)
	interior_background_heat_max_fraction_per_step = float(
		settings.get(
			"interior_background_heat_max_fraction_per_step",
			interior_background_heat_max_fraction_per_step
		)
	)
	interior_background_heat_carry_factor = float(
		settings.get(
			"interior_background_heat_carry_factor",
			interior_background_heat_carry_factor
		)
	)
	hot_gas_species_carry_fraction = float(
		settings.get("hot_gas_species_carry_fraction", hot_gas_species_carry_fraction)
	)
	hot_gas_smoke_carry_fraction = float(
		settings.get("hot_gas_smoke_carry_fraction", hot_gas_smoke_carry_fraction)
	)
	hot_gas_species_max_fraction_per_step = float(
		settings.get("hot_gas_species_max_fraction_per_step", hot_gas_species_max_fraction_per_step)
	)
	thermal_gradient_min_band_m = float(settings.get("thermal_gradient_min_band_m", thermal_gradient_min_band_m))
	thermal_gradient_max_band_m = float(settings.get("thermal_gradient_max_band_m", thermal_gradient_max_band_m))
	thermal_gradient_band_fraction = float(settings.get("thermal_gradient_band_fraction", thermal_gradient_band_fraction))
	floor_cooling_band_fraction = float(settings.get("floor_cooling_band_fraction", floor_cooling_band_fraction))
	floor_cooling_band_max_m = float(settings.get("floor_cooling_band_max_m", floor_cooling_band_max_m))
	survival_temp_threshold_c = float(settings.get("survival_temp_threshold_c", survival_temp_threshold_c))
	layer_150c_relax_down_per_s = float(settings.get("layer_150c_relax_down_per_s", layer_150c_relax_down_per_s))
	layer_150c_relax_up_per_s = float(settings.get("layer_150c_relax_up_per_s", layer_150c_relax_up_per_s))
	plume_fill_depth_coeff = float(settings.get("plume_fill_depth_coeff", plume_fill_depth_coeff))
	plume_fill_response_s = float(settings.get("plume_fill_response_s", plume_fill_response_s))
	plume_fill_max_fraction = float(settings.get("plume_fill_max_fraction", plume_fill_max_fraction))
	layer_relax_down = float(settings.get("layer_relax_down", layer_relax_down))
	layer_relax_up = float(settings.get("layer_relax_up", layer_relax_up))
	doorway_o2_min_band_m = float(settings.get("doorway_o2_min_band_m", doorway_o2_min_band_m))
	doorway_o2_smoke_weight = float(settings.get("doorway_o2_smoke_weight", doorway_o2_smoke_weight))
	doorway_o2_pressure_weight = float(settings.get("doorway_o2_pressure_weight", doorway_o2_pressure_weight))
	pressure_spill_ref_delta_pa = float(settings.get("pressure_spill_ref_delta_pa", pressure_spill_ref_delta_pa))
	interior_spill_start_layer_m = float(settings.get("interior_spill_start_layer_m", interior_spill_start_layer_m))
	plume_mccaffrey_enabled = bool(settings.get("plume_mccaffrey_enabled", plume_mccaffrey_enabled))
	plume_mccaffrey_qc_fraction = float(settings.get("plume_mccaffrey_qc_fraction", plume_mccaffrey_qc_fraction))
	plume_fire_diameter_m = float(settings.get("plume_fire_diameter_m", plume_fire_diameter_m))
	plume_flame_region_entrainment_enabled = bool(
		settings.get("plume_flame_region_entrainment_enabled", plume_flame_region_entrainment_enabled)
	)
	plume_flame_region_coeff = float(
		settings.get("plume_flame_region_coeff", plume_flame_region_coeff)
	)
	plume_flame_region_min_z_m = float(
		settings.get("plume_flame_region_min_z_m", plume_flame_region_min_z_m)
	)
	plume_flame_region_max_depth_fraction = float(
		settings.get("plume_flame_region_max_depth_fraction", plume_flame_region_max_depth_fraction)
	)
	fed_hypoxia_enabled = bool(settings.get("fed_hypoxia_enabled", fed_hypoxia_enabled))
	fed_hypoxia_a = float(settings.get("fed_hypoxia_a", fed_hypoxia_a))
	fed_hypoxia_b = float(settings.get("fed_hypoxia_b", fed_hypoxia_b))
	wall_conduction_enabled = bool(settings.get("wall_conduction_enabled", wall_conduction_enabled))
	wall_conduction_u_kw_m2_k = float(settings.get("wall_conduction_u_kw_m2_k", wall_conduction_u_kw_m2_k))
	wall_conduction_max_fraction_per_step = float(
		settings.get("wall_conduction_max_fraction_per_step", wall_conduction_max_fraction_per_step)
	)
	wall_adjacency_tolerance_m = float(settings.get("wall_adjacency_tolerance_m", wall_adjacency_tolerance_m))
	_adjacency_built = false  # Reconstruir al reconfigurar
	fed_heat_enabled = bool(settings.get("fed_heat_enabled", fed_heat_enabled))
	fed_heat_conv_a = float(settings.get("fed_heat_conv_a", fed_heat_conv_a))
	fed_heat_conv_n = float(settings.get("fed_heat_conv_n", fed_heat_conv_n))
	fed_heat_conv_min_c = float(settings.get("fed_heat_conv_min_c", fed_heat_conv_min_c))
	fed_heat_rad_a = float(settings.get("fed_heat_rad_a", fed_heat_rad_a))
	fed_heat_rad_view_factor = float(settings.get("fed_heat_rad_view_factor", fed_heat_rad_view_factor))
	fed_heat_rad_view_factor_below = float(settings.get("fed_heat_rad_view_factor_below", fed_heat_rad_view_factor_below))
	upper_heat_capture_min = float(settings.get("upper_heat_capture_min", upper_heat_capture_min))
	upper_heat_capture_max = float(settings.get("upper_heat_capture_max", upper_heat_capture_max))
	upper_heat_capture_outside_open_bonus = float(
		settings.get("upper_heat_capture_outside_open_bonus", upper_heat_capture_outside_open_bonus)
	)
	hrr_chi_rad_normal = float(settings.get("hrr_chi_rad_normal", hrr_chi_rad_normal))
	hrr_chi_rad_low_o2 = float(settings.get("hrr_chi_rad_low_o2", hrr_chi_rad_low_o2))
	hrr_rad_wall_fraction = float(settings.get("hrr_rad_wall_fraction", hrr_rad_wall_fraction))
	radiation_opening_enabled = bool(settings.get("radiation_opening_enabled", radiation_opening_enabled))
	radiation_flame_emissivity = float(settings.get("radiation_flame_emissivity", radiation_flame_emissivity))
	radiation_opening_view_factor = float(settings.get("radiation_opening_view_factor", radiation_opening_view_factor))
	radiation_smoke_attenuation_factor = float(settings.get("radiation_smoke_attenuation_factor", radiation_smoke_attenuation_factor))
	radiation_min_source_temp_c = float(settings.get("radiation_min_source_temp_c", radiation_min_source_temp_c))
	radiation_max_fraction_per_step = float(settings.get("radiation_max_fraction_per_step", radiation_max_fraction_per_step))
	energy_budget_enabled = bool(settings.get("energy_budget_enabled", energy_budget_enabled))
	energy_budget_warn_fraction = float(settings.get("energy_budget_warn_fraction", energy_budget_warn_fraction))


# ============================================================
# STEP PRINCIPAL DE TEMPERATURA
# ============================================================

func step(building: BuildingModel, dt: float, hooks: Dictionary = {}) -> void:
	var _outside_open_path_factor_callable: Callable = hooks.get(
		"outside_open_path_factor_callable", Callable()
	)
	# Cache pre-computado en SimulationEngine: {op -> flow_state} para todas las
	# aberturas interiores. Si no se pasa (llamadas antiguas o tests), fallback al cálculo.
	var _flow_cache: Dictionary = hooks.get("opening_flow_cache", {})
	var ambient_c: float = ambient_temp_c()

	# Determinar si hay algún fuego activo en el edificio (para re-emisión de paredes).
	var any_fire_active: bool = false
	for room_id_check in building.get_rooms().keys():
		var room_check: RoomModel = building.get_room(room_id_check)
		if room_check != null and room_check.fire != null:
			any_fire_active = true
			break

	var _bud_total_fire_kj: float = 0.0
	var _bud_total_residual_kj: float = 0.0
	if energy_budget_enabled:
		_energy_budget.clear()

	for room_id in building.get_rooms().keys():
		var room: RoomModel = building.get_room(room_id)
		if room == null:
			continue

		room.upper_radiative_loss_kw = 0.0
		var _bud_e_before_kj: float = room.upper_energy_kj if energy_budget_enabled else 0.0
		# Entrainamiento de pluma — McCaffrey (NBSIR 79-1910) + Heskestad (1983)
		if plume_mccaffrey_enabled and room.hrr_kw > 0.0:
			var qc_kw: float = room.hrr_kw * plume_mccaffrey_qc_fraction
			# Altura de llama Heskestad: L_f = 0.235·Q^0.4 - 1.02·D  [Q en kW, L en m]
			var l_flame_m: float = maxf(0.0, 0.235 * pow(room.hrr_kw, 0.4) - 1.02 * plume_fire_diameter_m)
			var z_m: float = maxf(room.thermal_layer_m, l_flame_m + 0.05)
			if l_flame_m < z_m:
				var z_eff_m: float = maxf(0.1, z_m - l_flame_m)
				var m_dot_p_kg_s: float = 0.071 * pow(qc_kw, 1.0 / 3.0) * pow(z_eff_m, 5.0 / 3.0)
				# Cap: no consumir más masa de la zona inferior disponible en este paso
				var lower_mass_kg: float = room.floor_area_m2() * maxf(0.0, room.thermal_layer_m) * gas_density_kg_m3(room.temp_lower_c)
				m_dot_p_kg_s = minf(m_dot_p_kg_s, lower_mass_kg / maxf(dt, 0.1))
				var mass_gain_kg: float = m_dot_p_kg_s * dt
				room.upper_gas_kg += mass_gain_kg
				room.upper_energy_kj += mass_gain_kg * maxf(0.0, room.temp_lower_c - ambient_c)
			elif plume_flame_region_entrainment_enabled:
				_add_flame_region_entrainment(room, qc_kw, z_m, dt, ambient_c)
			else:
				var target_upper_mass_kg: float = estimate_target_upper_gas_mass_kg(room)
				if target_upper_mass_kg > room.upper_gas_kg:
					var mass_gain_kg: float = (target_upper_mass_kg - room.upper_gas_kg) * clampf(
						dt / maxf(1.0, plume_fill_response_s),
						0.0,
						1.0
					)
					room.upper_gas_kg += mass_gain_kg
					room.upper_energy_kj += mass_gain_kg * maxf(0.0, room.temp_lower_c - ambient_c)
		else:
			# Sin fuego activo o McCaffrey deshabilitado → heurístico
			var target_upper_mass_kg: float = estimate_target_upper_gas_mass_kg(room)
			if target_upper_mass_kg > room.upper_gas_kg:
				var mass_gain_kg: float = (target_upper_mass_kg - room.upper_gas_kg) * clampf(
					dt / maxf(1.0, plume_fill_response_s),
					0.0,
					1.0
				)
				room.upper_gas_kg += mass_gain_kg
				room.upper_energy_kj += mass_gain_kg * maxf(0.0, room.temp_lower_c - ambient_c)

		var outside_open_factor: float = estimate_room_outside_open_factor(room)
		# Fracción convectiva = (1 − χ_rad) — física de zonas CFAST/SFPE §3.4.
		# χ_rad aumenta con O2 bajo (combustión incompleta → más hollín → más radiación).
		var chi_rad: float = lerpf(
			hrr_chi_rad_low_o2,
			hrr_chi_rad_normal,
			clampf(inverse_lerp(0.06, 0.12, room.o2), 0.0, 1.0)
		)
		var conv_fraction: float = clampf(1.0 - chi_rad, 0.0, 0.90)
		# Cuando hay ventana exterior abierta: el aporte de O2 fresco reduce chi_rad
		# efectivo (combustión más completa). Modelado como boost proporcional a open_factor.
		if outside_open_factor > 0.0 and outside_open_upper_heat_boost > 0.0:
			conv_fraction = minf(0.90, conv_fraction * (1.0 + outside_open_upper_heat_boost * outside_open_factor))
		room.upper_energy_kj += room.hrr_kw * conv_fraction * dt
		var _bud_e_fire_kj: float = room.hrr_kw * conv_fraction * dt if energy_budget_enabled else 0.0
		var pre_sync_upper_temp_c: float = _estimate_raw_upper_temp_c(room, ambient_c)
		var radiative_loss_kj: float = _compute_upper_radiative_loss_kj(
			room,
			ambient_c,
			dt,
			outside_open_factor,
			pre_sync_upper_temp_c
		)
		if radiative_loss_kj > 0.0:
			room.upper_energy_kj = maxf(0.0, room.upper_energy_kj - radiative_loss_kj)
			room.upper_radiative_loss_kw = radiative_loss_kj / maxf(0.001, dt)
		sync_room_upper_layer(room, dt)

		var delta_ul: float = maxf(0.0, room.temp_upper_c - room.temp_lower_c)
		var lower_transfer_rate: float = upper_to_lower_loss_rate + lower_layer_warming_rate
		lower_transfer_rate += _compute_room_vertical_mix_bonus(room)
		# outside_open_lower_warming_rate puede ser positivo (añade transferencia al lower)
		# o negativo (reduce la transferencia, modelando que el aire fresco externo
		# sustituye el gas caliente de la zona inferior y la desacopla de la capa superior).
		lower_transfer_rate = maxf(0.0, lower_transfer_rate + outside_open_lower_warming_rate * outside_open_factor)
		# Fade factor: cuando la zona inferior tiene altura < lower_layer_energy_fade_m
		# el flujo upper→lower se atenúa linealmente (zona inferior con volumen ínfimo
		# no puede absorber la misma energía que una zona de altura normal).
		var _lower_zone_m: float = effective_hot_layer_height_m(room)
		var _lower_fade: float = clampf(_lower_zone_m / maxf(0.05, lower_layer_energy_fade_m), 0.0, 1.0)
		var energy_to_lower_kj: float = room.upper_gas_kg * delta_ul * lower_transfer_rate * _lower_fade * dt
		var energy_to_ambient_kj: float = room.upper_gas_kg \
				* maxf(0.0, room.temp_upper_c - ambient_c) \
				* upper_to_ambient_loss_rate \
				* (1.0 + outside_open_ambient_loss_multiplier * outside_open_factor) \
				* dt
		# Masa térmica de paredes: intercambio bidireccional gas ↔ pared.
		# Área efectiva ≈ 2·floor_area (aproximación para sala con proporciones normales).
		var t_wall_c: float = _wall_surface_temp_c.get(room.id, ambient_c)
		var wall_capacity_kj_k: float = wall_heat_capacity_kj_m2_k * room.floor_area_m2() * 2.0
		# Absorción gas → pared (cuando el gas superior está más caliente que la pared)
		var wall_abs_delta_t: float = maxf(0.0, room.temp_upper_c - t_wall_c)
		var wall_absorption_kj: float = room.upper_gas_kg \
				* wall_abs_delta_t \
				* wall_absorption_rate \
				* (1.0 + outside_open_wall_absorption_multiplier * outside_open_factor) \
				* dt
		# Re-emisión pared → gas (cuando la pared está más caliente que el gas superior)
		# Solo cuando no hay fuego activo en todo el edificio: durante el incendio
		# la emisión interferiría con la dinámica de combustión en salas adyacentes.
		# Después de la extinción, las paredes calientes sostienen la temperatura post-incendio.
		var wall_emit_delta_t: float = 0.0
		var wall_emission_kj: float = 0.0
		if not any_fire_active:
			wall_emit_delta_t = maxf(0.0, t_wall_c - room.temp_upper_c)
			wall_emission_kj = room.upper_gas_kg \
					* wall_emit_delta_t \
					* wall_absorption_rate \
					* dt
			# Limitar emisión a un 15% de la energía almacenada en la pared por encima de ambiente
			wall_emission_kj = minf(
				wall_emission_kj,
				maxf(0.0, t_wall_c - ambient_c) * wall_capacity_kj_k * 0.15
			)
		# Radiación directa del fuego → paredes (χ_rad · HRR · dt, bypasses upper gas)
		var q_rad_fire_kj: float = room.hrr_kw * chi_rad * dt
		# Actualizar temperatura de pared
		t_wall_c += (wall_absorption_kj + q_rad_fire_kj * hrr_rad_wall_fraction) / maxf(0.1, wall_capacity_kj_k)
		t_wall_c -= wall_emission_kj / maxf(0.1, wall_capacity_kj_k)
		# Enfriamiento lento de la superficie hacia el núcleo/ambiente
		t_wall_c = lerpf(t_wall_c, ambient_c, minf(wall_core_decay_per_s * dt, 0.99))
		_wall_surface_temp_c[room.id] = t_wall_c

		var requested_upper_loss_kj: float = energy_to_lower_kj + energy_to_ambient_kj + wall_absorption_kj
		if requested_upper_loss_kj > 0.0 and room.upper_energy_kj > 0.0:
			var loss_scale: float = minf(1.0, room.upper_energy_kj / requested_upper_loss_kj)
			energy_to_lower_kj *= loss_scale
			energy_to_ambient_kj *= loss_scale
			wall_absorption_kj *= loss_scale
			room.upper_energy_kj -= energy_to_lower_kj + energy_to_ambient_kj + wall_absorption_kj
		# Re-emisión: las paredes calientes calientan el gas superior al enfriarse el incendio
		room.upper_energy_kj += wall_emission_kj

		if outside_open_factor > 0.0 and room.upper_gas_kg > 0.0001:
			var upper_temp_excess_factor: float = clampf(
				(room.temp_upper_c - ambient_c) / maxf(50.0, retained_hot_layer_temp_full_c - ambient_c),
				0.0,
				1.0
			)
			var cooling_mix_kg: float = room.upper_gas_kg \
					* outside_open_upper_mix_rate \
					* outside_open_factor \
					* upper_temp_excess_factor \
					* dt
			room.upper_gas_kg += maxf(0.0, cooling_mix_kg)

		var lower_mass_kg: float = maxf(
			1.0,
			gas_density_kg_m3(room.temp_lower_c) * room.floor_area_m2() * maxf(0.2, effective_hot_layer_height_m(room))
		)

		room.temp_lower_c += energy_to_lower_kj / lower_mass_kg
		room.temp_lower_c -= maxf(0.0, room.temp_lower_c - ambient_c) * 0.0085 * dt
		# Enfriamiento por ingreso de aire fresco exterior (ventana/puerta abierta al exterior).
		# Modela el reemplazamiento gradual de gas caliente en la zona inferior por aire
		# ambiente entrante (análogo al flujo de entrada por debajo del plano neutro en CFAST).
		if outside_open_factor > 0.0 and outside_lower_fresh_air_cooling_rate > 0.0:
			room.temp_lower_c -= maxf(0.0, room.temp_lower_c - ambient_c) \
					* outside_lower_fresh_air_cooling_rate * outside_open_factor * dt
		room.temp_lower_c = maxf(ambient_c, room.temp_lower_c)
		sync_room_upper_layer(room, dt)
		update_room_layer_150c(room, dt)
		step_fed(room, dt)

		if energy_budget_enabled:
			var _bud_de_upper_kj: float = room.upper_energy_kj - _bud_e_before_kj
			# Residual: E_fire + Q_wall_emit - Q_rad - Q_to_lower - Q_to_ambient - Q_wall_abs - ΔE_upper
			# (el plume mueve energía de lower a upper; no crea ni destruye energía)
			var _bud_q_residual_kj: float = _bud_e_fire_kj + wall_emission_kj \
					- radiative_loss_kj - energy_to_lower_kj - energy_to_ambient_kj \
					- wall_absorption_kj - _bud_de_upper_kj
			_energy_budget[room.id] = {
				"e_fire_kj": _bud_e_fire_kj,
				"q_fire_rad_kj": q_rad_fire_kj,
				"q_rad_kj": radiative_loss_kj,
				"q_to_lower_kj": energy_to_lower_kj,
				"q_to_ambient_kj": energy_to_ambient_kj,
				"q_wall_abs_kj": wall_absorption_kj,
				"q_wall_emit_kj": wall_emission_kj,
				"de_upper_kj": _bud_de_upper_kj,
				"q_residual_kj": _bud_q_residual_kj,
				"chi_rad": chi_rad,
			}
			if _bud_e_fire_kj > 0.01:
				_bud_total_fire_kj += _bud_e_fire_kj
				_bud_total_residual_kj += _bud_q_residual_kj

	# ── Radiación inter-sala a través de aperturas ────────────────────────────
	_step_radiation_openings(building, dt, ambient_c)

	# ── Conducción inter-sala a través de paredes sólidas compartidas ──────────
	_step_wall_conduction(building, dt, ambient_c)

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

		var flow_state: Dictionary = _flow_cache.get(op, build_interior_opening_flow_state(room_a, room_b, op))
		_apply_outside_assisted_background_heat_exchange(
			room_a, room_b, op, dt, ambient_c, _outside_open_path_factor_callable
		)
		_apply_interior_background_heat_exchange(room_a, room_b, op, dt, ambient_c)
		if not bool(flow_state.get("active", false)):
			continue

		var hot_room: RoomModel = flow_state.get("hot_room", null)
		var cold_room: RoomModel = flow_state.get("cold_room", null)
		if hot_room == null or cold_room == null:
			continue

		var hot_band_m: float = float(flow_state.get("hot_band_m", 0.0))
		if hot_band_m <= 0.0:
			continue

		var band_ref_m: float = maxf(doorway_o2_min_band_m, op.height_m * 0.24)
		var thermal_factor: float = clampf(hot_band_m / band_ref_m, 0.0, 1.0)
		var smoke_factor: float = clampf(
			float(flow_state.get("smoke_band_m", 0.0)) / band_ref_m,
			0.0,
			1.0
		)
		var pressure_factor: float = clampf(
			maxf(0.0, hot_room.overpressure_pa - cold_room.overpressure_pa) / maxf(
				1.0,
				pressure_spill_ref_delta_pa
			),
			0.0,
			1.0
		)
		var heat_engagement: float = clampf(
			thermal_factor + pressure_factor * doorway_o2_pressure_weight * 0.35,
			0.0,
			1.0
		)
		if heat_engagement <= 0.0:
			continue

		var heat_h_drive_m: float = maxf(
			hot_band_m,
			doorway_o2_min_band_m * heat_engagement * 0.45
		)
		var area_eff: float = op.width_m * minf(heat_h_drive_m, op.height_m) * op.open_fraction
		var source_temp_c: float = compute_interroom_transfer_temp_c(
			hot_room,
			cold_room,
			clampf(0.25 + 0.75 * heat_engagement, 0.0, 1.0),
			minf(smoke_factor, 0.25)
		)
		# El volumen de flujo boyante se calcula con la temperatura de la sala caliente
		# referenciada al AMBIENTE (no a la sala fría). Esto evita que el flujo se
		# autolimite cuando la sala receptora alcanza la temperatura de la fuente:
		# en la realidad, el gas caliente sigue saliendo de la sala en llamas mientras
		# tenga diferencia con el ambiente, independientemente de lo caliente que esté
		# el pasillo. source_temp_c sólo se usa para la energía del gas transferido.
		var t_hot_k: float = hot_room.temp_upper_c + 273.15
		var t_amb_k: float = ambient_c + 273.15
		var delta_t_k: float = maxf(0.0, t_hot_k - t_amb_k)
		if delta_t_k < 2.0:
			continue

		if area_eff <= 0.0:
			continue

		var neutral_pf: float = float(flow_state.get("neutral_plane_f", 0.5))
		var q_vol: float = 0.65 * neutral_pf * area_eff * sqrt(g_grav * hot_band_m * delta_t_k / ((t_hot_k + t_amb_k) * 0.5))
		var thermal_engagement: float = clampf(0.12 + heat_engagement * 0.65, 0.12, 0.90)
		var mass_exch: float = q_vol * rho_air * dt * doorway_heat_exchange_coeff * thermal_engagement

		var m_hot_kg: float = maxf(1.0, hot_room.volume_m3() * rho_air)
		var m_cold_kg: float = maxf(1.0, cold_room.volume_m3() * rho_air)

		# Limitar para evitar sobreoscilación: no puede transferirse más calor
		# del que equilibraría ambas habitaciones en un solo paso.
		var max_exch: float = (m_hot_kg * m_cold_kg) / (m_hot_kg + m_cold_kg)
		mass_exch = minf(mass_exch, max_exch)

		var gas_cap_kg: float = minf(
			hot_room.upper_gas_kg,
			maxf(0.06, hot_room.upper_gas_kg * (0.17 + 0.12 * thermal_engagement))
		)
		var gas_moved_kg: float = minf(mass_exch, gas_cap_kg)
		if gas_moved_kg <= 0.0:
			continue

		var hot_upper_gas_before_kg: float = maxf(0.0, hot_room.upper_gas_kg)
		# Energía del gas transferido: usa la temperatura de mezcla de la SALA FUENTE
		# (no amortiguada por la temperatura baja de la sala destino).
		# Físicamente, el gas que sale por la parte superior de la puerta lleva la
		# temperatura del estrato superior de la sala caliente; la mezcla con el
		# estrato frío del destino la gestiona upper_to_lower_loss_rate internamente.
		var _src_intensity: float = clampf(0.25 + 0.75 * heat_engagement, 0.0, 1.0)
		var _src_w_max: float = clampf(doorway_source_upper_weight, 0.18, 1.0)
		var _src_upper_w: float = clampf(0.18 + (_src_w_max - 0.18) * _src_intensity, 0.18, _src_w_max)
		var source_mix_temp_c: float = lerpf(hot_room.temp_lower_c, hot_room.temp_upper_c, _src_upper_w)
		var energy_moved_kj: float = gas_moved_kg * maxf(0.0, source_mix_temp_c - ambient_c)
		energy_moved_kj = minf(energy_moved_kj, hot_room.upper_energy_kj)

		hot_room.upper_gas_kg -= gas_moved_kg
		hot_room.upper_energy_kj = maxf(0.0, hot_room.upper_energy_kj - energy_moved_kj)

		cold_room.upper_gas_kg += gas_moved_kg
		cold_room.upper_energy_kj += energy_moved_kj
		_transfer_hot_gas_contaminants(
			hot_room,
			cold_room,
			gas_moved_kg,
			hot_upper_gas_before_kg,
			thermal_engagement
		)

		sync_room_upper_layer(hot_room, dt)
		sync_room_upper_layer(cold_room, dt)
		_apply_post_transfer_vertical_mix(hot_room, dt)
		_apply_post_transfer_vertical_mix(cold_room, dt)
		update_room_layer_150c(hot_room, dt)
		update_room_layer_150c(cold_room, dt)

	if energy_budget_enabled and _bud_total_fire_kj > 0.1:
		var residual_frac: float = abs(_bud_total_residual_kj) / _bud_total_fire_kj
		if residual_frac > energy_budget_warn_fraction:
			push_warning(
				"[ThermalSystem] Budget: residual=%.2f kJ (%.1f%% de E_fire=%.2f kJ)" % [
					_bud_total_residual_kj, residual_frac * 100.0, _bud_total_fire_kj
				]
			)


# ============================================================
# RADIACIÓN INTER-SALA A TRAVÉS DE APERTURAS
# ============================================================
# q_rad = ε · σ · (T_src⁴ − T_tgt⁴) · A_eff · φ · smoke_atten
# Modela el calentamiento radiativo de salas adyacentes por la llama/capa caliente
# que irradia a través de puertas y ventanas abiertas (Drysdale, 2011 §9.2).
# ============================================================

func _step_radiation_openings(building: BuildingModel, dt: float, ambient_c: float) -> void:
	if not radiation_opening_enabled:
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

		# Identificar sala fuente (la más caliente que supera el umbral mínimo)
		var src: RoomModel = null
		var tgt: RoomModel = null
		if room_a.temp_upper_c >= radiation_min_source_temp_c \
				and room_a.temp_upper_c > room_b.temp_upper_c:
			src = room_a
			tgt = room_b
		elif room_b.temp_upper_c >= radiation_min_source_temp_c \
				and room_b.temp_upper_c > room_a.temp_upper_c:
			src = room_b
			tgt = room_a
		else:
			continue

		if src.upper_gas_kg <= 0.0001 or src.upper_energy_kj <= 0.0:
			continue

		var t_src_k: float = src.temp_upper_c + 273.15
		var t_tgt_k: float = maxf(ambient_c, tgt.temp_upper_c) + 273.15
		var dt4: float = maxf(0.0, pow(t_src_k, 4.0) - pow(t_tgt_k, 4.0))
		if dt4 <= 0.0:
			continue

		var area_eff: float = op.width_m * op.height_m * op.open_fraction
		if area_eff <= 0.0:
			continue

		# Atenuación por humo: ley de Beer-Lambert τ = exp(-κ·c·L)
		# κ ≈ 8.7 m²/kg (coef. extinción Jin 1978, modo reflexión).
		# c = concentración media en ambas salas; L = anchura del vano.
		var total_smoke_kg: float = src.smoke_kg + tgt.smoke_kg
		var smoke_atten: float = 1.0
		if total_smoke_kg > 0.0001:
			var total_vol_m3: float = maxf(0.1, src.volume_m3() + tgt.volume_m3())
			var c_smoke_kg_m3: float = total_smoke_kg / total_vol_m3
			var path_len_m: float = maxf(0.3, op.width_m)
			smoke_atten = exp(-8.7 * c_smoke_kg_m3 * path_len_m)

		var q_rad_kw: float = radiation_flame_emissivity \
				* STEFAN_BOLTZMANN_KW_M2_K4 \
				* dt4 \
				* area_eff \
				* radiation_opening_view_factor \
				* smoke_atten
		if q_rad_kw <= 0.0:
			continue

		var energy_kj: float = q_rad_kw * dt
		# Estabilidad: no transferir más del fraction máximo de la energía de la capa superior
		var max_transfer_kj: float = src.upper_energy_kj * radiation_max_fraction_per_step
		energy_kj = minf(energy_kj, max_transfer_kj)
		if energy_kj <= 0.0:
			continue

		src.upper_energy_kj = maxf(0.0, src.upper_energy_kj - energy_kj)

		# Si el destino no tiene capa superior formada, crear masa mínima para absorber la energía
		if tgt.upper_gas_kg <= 0.0001:
			var tgt_density: float = gas_density_kg_m3(tgt.temp_lower_c)
			tgt.upper_gas_kg = tgt.floor_area_m2() * 0.08 * tgt_density

		tgt.upper_energy_kj += energy_kj

		sync_room_upper_layer(src, dt)
		sync_room_upper_layer(tgt, dt)
		update_room_layer_150c(src, dt)
		update_room_layer_150c(tgt, dt)


# ============================================================
# CONDUCCIÓN INTER-SALA A TRAVÉS DE PAREDES SÓLIDAS
# ============================================================
# Calcula la transferencia de calor entre salas geométricamente adyacentes
# (que comparten una pared) a través de la pared sólida, independientemente
# de si existe una apertura entre ellas.
#
# Modelo: Q = U × A_neta × (T_pared_caliente - T_capa_superior_fría)
# La temperatura de la pared caliente se toma de _wall_surface_temp_c que ya
# refleja la absorción de calor del fuego durante el incendio.
# La energía se deposita en la capa superior de la sala fría.
# ============================================================

func _step_wall_conduction(building: BuildingModel, dt: float, ambient_c: float) -> void:
	if not wall_conduction_enabled:
		return
	if not _adjacency_built:
		_build_wall_adjacency(building)

	for pair in _adjacent_pairs:
		var room_a: RoomModel = building.get_room(pair["room_a_id"])
		var room_b: RoomModel = building.get_room(pair["room_b_id"])
		if room_a == null or room_b == null:
			continue

		var wall_area: float = pair["wall_area_m2"]
		var t_wall_a: float = _wall_surface_temp_c.get(pair["room_a_id"], ambient_c)
		var t_wall_b: float = _wall_surface_temp_c.get(pair["room_b_id"], ambient_c)
		var delta_t: float = t_wall_a - t_wall_b
		if absf(delta_t) < 1.0:
			continue

		# Q = U × A × ΔT  [kW]
		var q_kw: float = wall_conduction_u_kw_m2_k * wall_area * delta_t
		var energy_kj: float = q_kw * dt

		# Límite de estabilidad: no pasar más de max_fraction de la capacidad de la
		# pared más grande en un solo paso.
		var cap_a: float = wall_heat_capacity_kj_m2_k * room_a.floor_area_m2() * 2.0
		var cap_b: float = wall_heat_capacity_kj_m2_k * room_b.floor_area_m2() * 2.0
		var max_kj: float = maxf(cap_a, cap_b) * wall_conduction_max_fraction_per_step
		energy_kj = clampf(energy_kj, -max_kj, max_kj)

		if energy_kj > 0.0:
			# A→B: pared de A cede calor a la capa superior de B
			_wall_surface_temp_c[pair["room_a_id"]] = t_wall_a \
					- energy_kj / maxf(0.1, cap_a)
			_ensure_minimal_upper_gas(room_b, ambient_c)
			room_b.upper_energy_kj += energy_kj
			sync_room_upper_layer(room_b, dt)
			update_room_layer_150c(room_b, dt)
		elif energy_kj < 0.0:
			# B→A: pared de B cede calor a la capa superior de A
			var abs_kj: float = -energy_kj
			_wall_surface_temp_c[pair["room_b_id"]] = t_wall_b \
					- abs_kj / maxf(0.1, cap_b)
			_ensure_minimal_upper_gas(room_a, ambient_c)
			room_a.upper_energy_kj += abs_kj
			sync_room_upper_layer(room_a, dt)
			update_room_layer_150c(room_a, dt)


func _ensure_minimal_upper_gas(room: RoomModel, ambient_c: float) -> void:
	# Crea una capa superior mínima para poder depositar energía si aún no existe.
	if room.upper_gas_kg <= 0.0001:
		var density: float = gas_density_kg_m3(room.temp_lower_c)
		room.upper_gas_kg = room.floor_area_m2() * 0.08 * density


func _build_wall_adjacency(building: BuildingModel) -> void:
	# Construye la lista de pares de salas geométricamente adyacentes con el área
	# de pared sólida compartida (neta, descontando aperturas existentes).
	_adjacent_pairs.clear()
	var room_ids: Array = building.room_rect_m.keys()
	for i: int in range(room_ids.size()):
		for j: int in range(i + 1, room_ids.size()):
			var id_a: int = room_ids[i]
			var id_b: int = room_ids[j]
			var room_a: RoomModel = building.get_room(id_a)
			var room_b: RoomModel = building.get_room(id_b)
			if room_a == null or room_b == null:
				continue
			var rect_a: Rect2 = building.room_rect_m.get(id_a, Rect2())
			var rect_b: Rect2 = building.room_rect_m.get(id_b, Rect2())
			var shared_len: float = _compute_shared_wall_length_m(
					rect_a, rect_b, wall_adjacency_tolerance_m
			)
			if shared_len < 0.1:
				continue
			var wall_h: float = minf(room_a.height_m, room_b.height_m)
			var gross_area: float = shared_len * wall_h
			# Descontar área de aperturas entre estas dos salas (solo la pared sólida conduce)
			var net_area: float = gross_area
			for op in building.get_openings():
				if op.a == BuildingModel.OUTSIDE_ID or op.b == BuildingModel.OUTSIDE_ID:
					continue
				if (op.a == id_a and op.b == id_b) or (op.a == id_b and op.b == id_a):
					net_area -= op.width_m * op.height_m
			net_area = maxf(0.0, net_area)
			if net_area < 0.05:
				continue
			_adjacent_pairs.append({
				"room_a_id": id_a,
				"room_b_id": id_b,
				"wall_area_m2": net_area
			})
	_adjacency_built = true


func _compute_shared_wall_length_m(rect_a: Rect2, rect_b: Rect2, tol: float) -> float:
	# Devuelve la longitud de la arista compartida entre dos rectángulos.
	# Detecta paredes verticales (∥Y) y horizontales (∥X).
	var xa1: float = rect_a.position.x
	var xa2: float = xa1 + rect_a.size.x
	var ya1: float = rect_a.position.y
	var ya2: float = ya1 + rect_a.size.y
	var xb1: float = rect_b.position.x
	var xb2: float = xb1 + rect_b.size.x
	var yb1: float = rect_b.position.y
	var yb2: float = yb1 + rect_b.size.y

	# Pared vertical: lado derecho de A toca lado izquierdo de B (o viceversa)
	if absf(xa2 - xb1) < tol or absf(xb2 - xa1) < tol:
		var overlap: float = minf(ya2, yb2) - maxf(ya1, yb1)
		if overlap > 0.1:
			return overlap

	# Pared horizontal: lado inferior de A toca lado superior de B (o viceversa)
	if absf(ya2 - yb1) < tol or absf(yb2 - ya1) < tol:
		var overlap: float = minf(xa2, xb2) - maxf(xa1, xb1)
		if overlap > 0.1:
			return overlap

	return 0.0


# ============================================================
# FUNCIONES AUXILIARES TÉRMICAS
# ============================================================

func ambient_temp_c() -> float:
	return _building.outside_temp_c if _building != null else 20.0


func gas_density_kg_m3(temp_c: float) -> float:
	var ambient_k: float = ambient_temp_c() + 273.15
	var gas_k: float = maxf(ambient_k, temp_c + 273.15)
	return 1.2 * ambient_k / gas_k


func estimate_target_upper_gas_mass_kg(room: RoomModel) -> float:
	if room == null:
		return 0.0

	var target_depth_m: float = maxf(
		estimate_plume_upper_depth_m(room),
		estimate_retained_hot_layer_depth_m(room)
	)
	if target_depth_m <= 0.0:
		return 0.0

	var target_volume_m3: float = room.floor_area_m2() * target_depth_m
	var entrained_temp_c: float = maxf(
		room.temp_lower_c + 60.0,
		minf(room.temp_upper_c, room.temp_lower_c + 180.0)
	)
	return target_volume_m3 * gas_density_kg_m3(entrained_temp_c)


func _add_flame_region_entrainment(
	room: RoomModel,
	qc_kw: float,
	interface_height_m: float,
	dt: float,
	ambient_c: float
) -> void:
	if room == null or dt <= 0.0 or qc_kw <= 0.0:
		return

	var z_m: float = clampf(interface_height_m, 0.0, room.height_m)
	var lower_mass_kg: float = room.floor_area_m2() * maxf(0.0, z_m) * gas_density_kg_m3(room.temp_lower_c)
	if lower_mass_kg <= 0.001:
		return

	var effective_z_m: float = maxf(plume_flame_region_min_z_m, z_m)
	var m_dot_p_kg_s: float = maxf(0.0, plume_flame_region_coeff) \
			* pow(qc_kw, 1.0 / 3.0) \
			* pow(effective_z_m, 5.0 / 3.0)

	var max_depth_m: float = room.height_m * clampf(plume_flame_region_max_depth_fraction, 0.05, 1.0)
	var max_upper_mass_kg: float = room.floor_area_m2() \
			* max_depth_m \
			* gas_density_kg_m3(maxf(room.temp_lower_c + 40.0, room.temp_upper_c))
	var remaining_upper_capacity_kg: float = maxf(0.0, max_upper_mass_kg - room.upper_gas_kg)
	if remaining_upper_capacity_kg <= 0.001:
		return

	var mass_gain_kg: float = m_dot_p_kg_s * dt
	mass_gain_kg = minf(mass_gain_kg, lower_mass_kg)
	mass_gain_kg = minf(mass_gain_kg, remaining_upper_capacity_kg)
	if mass_gain_kg <= 0.0:
		return

	room.upper_gas_kg += mass_gain_kg
	room.upper_energy_kj += mass_gain_kg * maxf(0.0, room.temp_lower_c - ambient_c)


func estimate_retained_hot_layer_depth_m(room: RoomModel) -> float:
	if room == null:
		return 0.0
	if retained_hot_layer_max_fraction <= 0.0:
		return 0.0

	var heat_factor: float = inverse_lerp(
		retained_hot_layer_temp_start_c,
		retained_hot_layer_temp_full_c,
		room.temp_upper_c
	)
	heat_factor = clampf(heat_factor, 0.0, 1.0)
	if heat_factor <= 0.0:
		return 0.0

	var smoke_fill_fraction: float = clampf(
		(room.height_m - _smoke_model.get_visible_smoke_layer_height_m(room)) / maxf(0.1, room.height_m),
		0.0,
		1.0
	)
	var o2_span: float = maxf(0.0001, retained_hot_layer_o2_start - retained_hot_layer_o2_full)
	var o2_factor: float = clampf(
		(retained_hot_layer_o2_start - room.o2) / o2_span,
		0.0,
		1.0
	)
	var support_factor: float = maxf(smoke_fill_fraction, o2_factor)
	if support_factor <= 0.0:
		return 0.0

	return room.height_m * retained_hot_layer_max_fraction * heat_factor * support_factor
	

func estimate_room_outside_open_factor(room: RoomModel) -> float:
	if room == null or _building == null:
		return 0.0

	var total_open_area_m2: float = 0.0
	for op in _building.get_openings():
		if op.open_fraction <= 0.0:
			continue

		var connects_outside: bool = (
			(op.a == room.id and op.b == BuildingModel.OUTSIDE_ID)
			or (op.b == room.id and op.a == BuildingModel.OUTSIDE_ID)
		)
		if not connects_outside:
			continue

		total_open_area_m2 += op.width_m * op.height_m * op.open_fraction

	if total_open_area_m2 <= 0.0:
		return 0.0

	var reference_area_m2: float = maxf(0.20, room.floor_area_m2() * outside_open_loss_area_fraction)
	return clampf(total_open_area_m2 / reference_area_m2, 0.0, 1.0)


func _estimate_raw_upper_temp_c(room: RoomModel, ambient_c: float) -> float:
	if room == null:
		return ambient_c
	if room.upper_gas_kg <= 0.0001 or room.upper_energy_kj <= 0.0001:
		return maxf(room.temp_lower_c, ambient_c)
	return maxf(room.temp_lower_c, ambient_c + room.upper_energy_kj / maxf(0.05, room.upper_gas_kg))


func _compute_upper_radiative_loss_kj(
	room: RoomModel,
	ambient_c: float,
	dt: float,
	outside_open_factor: float,
	upper_temp_c: float
) -> float:
	if not upper_radiative_loss_enabled:
		return 0.0
	if room == null or dt <= 0.0 or room.upper_energy_kj <= 0.0:
		return 0.0
	if upper_temp_c <= upper_radiative_loss_start_c:
		return 0.0

	var hot_layer_depth_m: float = clampf(
		room.height_m - effective_hot_layer_height_m(room),
		0.0,
		room.height_m
	)
	var ceiling_area_m2: float = maxf(0.0, room.floor_area_m2())
	var hot_wall_area_m2: float = 2.0 * (room.width_m + room.length_m) * hot_layer_depth_m
	var exchange_area_m2: float = maxf(
		0.0,
		(ceiling_area_m2 + hot_wall_area_m2) * upper_radiative_loss_area_factor
	)
	if exchange_area_m2 <= 0.0:
		return 0.0

	# Activación lineal entre upper_radiative_loss_start_c y max_upper_temp_c.
	# El modelo previo usaba activación cuadrática que efectivamente suprimía
	# toda pérdida radiativa por debajo de ~880 °C, causando sobrecalentamiento
	# irreal de la capa superior en comparación con FDS.
	var activation: float = clampf(
		(upper_temp_c - upper_radiative_loss_start_c)
				/ maxf(1.0, max_upper_temp_c - upper_radiative_loss_start_c),
		0.0,
		1.0
	)

	var hot_k: float = upper_temp_c + 273.15
	var sink_k: float = maxf(ambient_c, room.temp_lower_c) + 273.15
	var temperature_power_delta: float = maxf(0.0, pow(hot_k, 4.0) - pow(sink_k, 4.0))
	var q_kw: float = upper_radiative_loss_emissivity \
			* STEFAN_BOLTZMANN_KW_M2_K4 \
			* exchange_area_m2 \
			* temperature_power_delta \
			* activation
	q_kw *= 1.0 + 0.25 * clampf(outside_open_factor, 0.0, 1.0)

	var requested_loss_kj: float = maxf(0.0, q_kw * dt)
	var max_loss_fraction: float = clampf(upper_radiative_loss_max_fraction_per_step, 0.0, 1.0)
	var max_loss_kj: float = room.upper_energy_kj * max_loss_fraction
	return minf(requested_loss_kj, max_loss_kj)


func _apply_outside_assisted_background_heat_exchange(
	room_a: RoomModel,
	room_b: RoomModel,
	op: OpeningModel,
	dt: float,
	ambient_c: float,
	outside_open_path_factor_callable: Callable = Callable()
) -> void:
	if room_a == null or room_b == null or op == null or dt <= 0.0:
		return
	if outside_open_background_heat_exchange_kg_s_m2 <= 0.0:
		return

	var outside_open_factor: float = maxf(
		estimate_room_outside_open_factor(room_a),
		estimate_room_outside_open_factor(room_b)
	)
	if outside_open_factor <= 0.0:
		# Comprueba si alguna sala está conectada INDIRECTAMENTE al exterior
		# (p.ej. R0–R1 cuando R2 tiene una ventana abierta). El factor de ruta
		# se atenúa para reflejar que la señal llega a través de puertas intermedias.
		var path_a: float = _call_path_factor(outside_open_path_factor_callable, room_a.id)
		var path_b: float = _call_path_factor(outside_open_path_factor_callable, room_b.id)
		outside_open_factor = maxf(path_a, path_b) * 0.30
		if outside_open_factor <= 0.0:
			return

	var source: RoomModel = room_a
	var target: RoomModel = room_b
	if room_b.temp_upper_c > room_a.temp_upper_c:
		source = room_b
		target = room_a

	var source_excess_c: float = maxf(0.0, source.temp_upper_c - ambient_c)
	var target_excess_c: float = maxf(0.0, target.temp_upper_c - ambient_c)
	var delta_excess_c: float = source_excess_c - target_excess_c
	if delta_excess_c <= 1.0:
		return

	var area_eff_m2: float = maxf(0.0, op.width_m * op.height_m * op.open_fraction)
	if area_eff_m2 <= 0.0:
		return

	var pressure_drive: float = clampf(
		maxf(room_a.overpressure_pa, room_b.overpressure_pa) / maxf(0.5, pressure_spill_ref_delta_pa * 0.35),
		0.0,
		1.0
	)
	var smoke_drive: float = clampf(
		maxf(room_a.smoke_kg, room_b.smoke_kg) / 0.20,
		0.0,
		1.0
	)
	var heat_drive: float = clampf(delta_excess_c / 120.0, 0.0, 1.0)
	var drive: float = clampf(
		0.22 + 0.35 * pressure_drive + 0.25 * smoke_drive + 0.18 * heat_drive,
		0.0,
		1.0
	)

	var exchange_kg: float = area_eff_m2 \
			* outside_open_background_heat_exchange_kg_s_m2 \
			* outside_open_factor \
			* drive \
			* dt
	var air_mass_limit_kg: float = minf(room_a.volume_m3(), room_b.volume_m3()) * 1.2 \
			* outside_open_background_heat_max_fraction_per_step
	exchange_kg = minf(exchange_kg, air_mass_limit_kg)
	if exchange_kg <= 0.0:
		return

	var carry_intensity: float = clampf(
		outside_open_background_heat_carry_factor * (0.45 + 0.55 * drive),
		0.05,
		0.65
	)
	var transfer_temp_c: float = compute_interroom_transfer_temp_c(
		source,
		target,
		carry_intensity,
		smoke_drive
	)
	var heat_excess_c: float = maxf(0.0, transfer_temp_c - ambient_c)
	if heat_excess_c <= 0.25:
		return

	if source.upper_gas_kg > 0.0001 and source.upper_energy_kj > 0.0001:
		var gas_moved_kg: float = minf(
			exchange_kg,
			maxf(0.01, source.upper_gas_kg * 0.035)
		)
		var source_energy_removed_kj: float = gas_moved_kg * source_excess_c
		source_energy_removed_kj = minf(source_energy_removed_kj, source.upper_energy_kj * 0.08)
		if source_energy_removed_kj > 0.0:
			var energy_moved_kj: float = minf(
				gas_moved_kg * heat_excess_c,
				source_energy_removed_kj * lerpf(0.45, 0.72, clampf(outside_open_factor, 0.0, 1.0))
			)
			if energy_moved_kj > 0.0:
				var source_upper_gas_before_kg: float = maxf(0.0, source.upper_gas_kg)
				source.upper_gas_kg = maxf(0.0, source.upper_gas_kg - gas_moved_kg)
				source.upper_energy_kj = maxf(0.0, source.upper_energy_kj - source_energy_removed_kj)
				target.upper_gas_kg = maxf(0.0, target.upper_gas_kg + gas_moved_kg)
				target.upper_energy_kj = maxf(0.0, target.upper_energy_kj + energy_moved_kj)
				_transfer_hot_gas_contaminants(
					source,
					target,
					gas_moved_kg,
					source_upper_gas_before_kg,
					carry_intensity
				)

	var source_bulk_temp_c: float = lerpf(source.temp_lower_c, source.temp_upper_c, 0.18)
	var target_bulk_temp_c: float = target.temp_lower_c
	var bulk_delta_c: float = source_bulk_temp_c - target_bulk_temp_c
	if bulk_delta_c > 0.25:
		var source_air_mass_kg: float = maxf(1.0, source.volume_m3() * 1.2)
		var target_air_mass_kg: float = maxf(1.0, target.volume_m3() * 1.2)
		var bulk_exchange_kg: float = minf(
			exchange_kg,
			source_air_mass_kg * outside_open_background_heat_max_fraction_per_step
		)
		var source_available_kj: float = source_air_mass_kg * maxf(0.0, source_bulk_temp_c - ambient_c)
		var bulk_removed_kj: float = bulk_exchange_kg * bulk_delta_c * lerpf(0.32, 0.55, drive)
		bulk_removed_kj = minf(bulk_removed_kj, source_available_kj * 0.025)
		if bulk_removed_kj > 0.0:
			var bulk_delivered_kj: float = bulk_removed_kj * lerpf(0.35, 0.62, outside_open_factor)
			source.temp_lower_c = maxf(
				ambient_c,
				source.temp_lower_c - bulk_removed_kj / source_air_mass_kg
			)
			if source.upper_gas_kg <= 0.0001:
				source.temp_upper_c = source.temp_lower_c

			target.temp_lower_c += bulk_delivered_kj / target_air_mass_kg
			if target.upper_gas_kg <= 0.0001:
				target.temp_upper_c = maxf(target.temp_upper_c, target.temp_lower_c)

	sync_room_upper_layer(source, dt)
	sync_room_upper_layer(target, dt)


func _apply_interior_background_heat_exchange(
	room_a: RoomModel,
	room_b: RoomModel,
	op: OpeningModel,
	dt: float,
	ambient_c: float
) -> void:
	if room_a == null or room_b == null or op == null or dt <= 0.0:
		return
	if interior_background_heat_exchange_kg_s_m2 <= 0.0:
		return

	var source: RoomModel = room_a
	var target: RoomModel = room_b
	if room_b.temp_upper_c > room_a.temp_upper_c:
		source = room_b
		target = room_a

	var source_excess_c: float = maxf(0.0, source.temp_upper_c - ambient_c)
	var target_excess_c: float = maxf(0.0, target.temp_upper_c - ambient_c)
	var delta_excess_c: float = source_excess_c - target_excess_c
	if delta_excess_c <= 1.0:
		return

	var area_eff_m2: float = maxf(0.0, op.width_m * op.height_m * op.open_fraction)
	if area_eff_m2 <= 0.0:
		return

	var pressure_drive: float = clampf(
		maxf(room_a.overpressure_pa, room_b.overpressure_pa) / maxf(0.5, pressure_spill_ref_delta_pa * 0.35),
		0.0,
		1.0
	)
	var smoke_drive: float = clampf(
		maxf(room_a.smoke_kg, room_b.smoke_kg) / 0.18,
		0.0,
		1.0
	)
	var heat_drive: float = clampf(delta_excess_c / 90.0, 0.0, 1.0)
	var drive: float = clampf(
		0.16 + 0.22 * pressure_drive + 0.26 * smoke_drive + 0.36 * heat_drive,
		0.0,
		1.0
	)
	if drive <= 0.0:
		return

	var exchange_kg: float = area_eff_m2 \
			* interior_background_heat_exchange_kg_s_m2 \
			* drive \
			* dt
	var air_mass_limit_kg: float = minf(room_a.volume_m3(), room_b.volume_m3()) * 1.2 \
			* interior_background_heat_max_fraction_per_step
	exchange_kg = minf(exchange_kg, air_mass_limit_kg)
	if exchange_kg <= 0.0:
		return

	var carry_intensity: float = clampf(
		interior_background_heat_carry_factor * (0.40 + 0.60 * drive),
		0.05,
		0.85
	)
	var transfer_temp_c: float = compute_interroom_transfer_temp_c(
		source,
		target,
		carry_intensity,
		smoke_drive
	)
	var heat_excess_c: float = maxf(0.0, transfer_temp_c - ambient_c)
	if heat_excess_c <= 0.25:
		return

	var touched_source: bool = false
	var touched_target: bool = false
	if source.upper_gas_kg > 0.0001 and source.upper_energy_kj > 0.0001:
		var gas_moved_kg: float = minf(
			exchange_kg,
			maxf(0.015, source.upper_gas_kg * (0.03 + 0.10 * drive))
		)
		var energy_moved_kj: float = minf(
			gas_moved_kg * heat_excess_c,
			source.upper_energy_kj * (0.03 + 0.09 * drive)
		)
		if gas_moved_kg > 0.0 and energy_moved_kj > 0.0:
			var source_upper_gas_before_kg: float = maxf(0.0, source.upper_gas_kg)
			source.upper_gas_kg = maxf(0.0, source.upper_gas_kg - gas_moved_kg)
			source.upper_energy_kj = maxf(0.0, source.upper_energy_kj - energy_moved_kj)
			target.upper_gas_kg = maxf(0.0, target.upper_gas_kg + gas_moved_kg)
			target.upper_energy_kj = maxf(0.0, target.upper_energy_kj + energy_moved_kj)
			_transfer_hot_gas_contaminants(
				source,
				target,
				gas_moved_kg,
				source_upper_gas_before_kg,
				carry_intensity
			)
			touched_source = true
			touched_target = true

	var source_bulk_temp_c: float = lerpf(source.temp_lower_c, source.temp_upper_c, 0.22 + 0.18 * drive)
	var target_bulk_temp_c: float = target.temp_lower_c
	var bulk_delta_c: float = source_bulk_temp_c - target_bulk_temp_c
	if bulk_delta_c > 0.25:
		var source_air_mass_kg: float = maxf(1.0, source.volume_m3() * 1.2)
		var target_air_mass_kg: float = maxf(1.0, target.volume_m3() * 1.2)
		var bulk_exchange_kg: float = minf(
			exchange_kg,
			source_air_mass_kg * interior_background_heat_max_fraction_per_step
		)
		var source_available_kj: float = source_air_mass_kg * maxf(0.0, source_bulk_temp_c - ambient_c)
		var bulk_moved_kj: float = minf(
			bulk_exchange_kg * bulk_delta_c * (0.30 + 0.30 * drive),
			source_available_kj * (0.012 + 0.025 * drive)
		)
		if bulk_moved_kj > 0.0:
			source.temp_lower_c = maxf(
				ambient_c,
				source.temp_lower_c - bulk_moved_kj / source_air_mass_kg
			)
			target.temp_lower_c += bulk_moved_kj / target_air_mass_kg
			touched_source = true
			touched_target = true

	if touched_source:
		sync_room_upper_layer(source, dt)
	if touched_target:
		sync_room_upper_layer(target, dt)


func remove_upper_layer_fraction(room: RoomModel, fraction: float) -> void:
	if room == null:
		return

	var frac: float = clampf(fraction, 0.0, 1.0)
	if frac <= 0.0:
		return

	room.upper_gas_kg *= (1.0 - frac)
	room.upper_energy_kj *= (1.0 - frac)


func _transfer_hot_gas_contaminants(
	source: RoomModel,
	target: RoomModel,
	gas_moved_kg: float,
	source_upper_gas_before_kg: float,
	carry_intensity: float
) -> void:
	if source == null or target == null:
		return
	if gas_moved_kg <= 0.0 or source_upper_gas_before_kg <= 0.0001:
		return

	var upper_fraction_moved: float = clampf(
		gas_moved_kg / maxf(0.0001, source_upper_gas_before_kg),
		0.0,
		clampf(hot_gas_species_max_fraction_per_step, 0.0, 1.0)
	)
	if upper_fraction_moved <= 0.0:
		return

	var carry: float = clampf(hot_gas_species_carry_fraction, 0.0, 1.0) \
			* clampf(carry_intensity, 0.0, 1.0)
	var smoke_carry: float = clampf(hot_gas_smoke_carry_fraction, 0.0, 1.0) \
			* clampf(carry_intensity, 0.0, 1.0)

	var co_upper_available_kg: float = clampf(source.co_upper_kg, 0.0, source.co_kg)
	var co_moved_kg: float = minf(source.co_kg, co_upper_available_kg * upper_fraction_moved * carry)
	var co2_moved_kg: float = minf(source.co2_kg, source.co2_kg * upper_fraction_moved * carry)
	var smoke_moved_kg: float = minf(source.smoke_kg, source.smoke_kg * upper_fraction_moved * smoke_carry)

	if co_moved_kg > 0.0:
		source.co_kg = maxf(0.0, source.co_kg - co_moved_kg)
		source.co_upper_kg = maxf(0.0, source.co_upper_kg - co_moved_kg)
		target.co_kg = maxf(0.0, target.co_kg + co_moved_kg)
		target.co_upper_kg = maxf(0.0, target.co_upper_kg + co_moved_kg)

	if co2_moved_kg > 0.0:
		source.co2_kg = maxf(0.0, source.co2_kg - co2_moved_kg)
		target.co2_kg = maxf(0.0, target.co2_kg + co2_moved_kg)

	if smoke_moved_kg > 0.0:
		source.smoke_kg = maxf(0.0, source.smoke_kg - smoke_moved_kg)
		target.smoke_kg = maxf(0.0, target.smoke_kg + smoke_moved_kg)

	source.co_upper_kg = clampf(source.co_upper_kg, 0.0, source.co_kg)
	target.co_upper_kg = clampf(target.co_upper_kg, 0.0, target.co_kg)


func reset_thermal_layer(room: RoomModel) -> void:
	if room == null:
		return

	room.thermal_layer_m = room.height_m


func reset_wall_temps() -> void:
	_wall_surface_temp_c.clear()


func estimate_thermal_layer_height_m(room: RoomModel) -> float:
	if room == null:
		return 0.0

	if room.upper_gas_kg <= 0.000001:
		return room.height_m

	var hot_gas_density_kg_m3: float = gas_density_kg_m3(room.temp_upper_c)
	var hot_gas_volume_m3: float = room.upper_gas_kg / maxf(0.05, hot_gas_density_kg_m3)
	var hot_depth_m: float = hot_gas_volume_m3 / maxf(0.01, room.floor_area_m2())
	return clampf(room.height_m - hot_depth_m, 0.0, room.height_m)


func compute_interroom_transfer_temp_c(
	source: RoomModel,
	target: RoomModel,
	intensity: float,
	smoke_coupling: float = 0.0
) -> float:
	if source == null:
		return ambient_temp_c()

	var transfer_intensity: float = clampf(intensity, 0.0, 1.0)
	var smoke_weight: float = clampf(smoke_coupling, 0.0, 1.0)
	var thermal_only_upper_weight: float = clampf(0.18 + 0.38 * transfer_intensity, 0.18, 0.60)
	var smoke_loaded_upper_weight: float = clampf(0.18 + 0.50 * transfer_intensity, 0.18, 0.78)
	var upper_weight: float = lerpf(thermal_only_upper_weight, smoke_loaded_upper_weight, smoke_weight)
	var source_mix_temp_c: float = lerpf(source.temp_lower_c, source.temp_upper_c, upper_weight)
	var target_lower_c: float = target.temp_lower_c if target != null else ambient_temp_c()
	var thermal_only_carry_factor: float = clampf(
		0.16 + 0.33 * transfer_intensity + smoke_heat_mix_coeff * 3.0,
		0.18,
		0.58
	)
	var smoke_loaded_carry_factor: float = clampf(
		0.18 + 0.45 * transfer_intensity + smoke_heat_mix_coeff * 4.0,
		0.18,
		0.72
	)
	var carry_factor: float = lerpf(thermal_only_carry_factor, smoke_loaded_carry_factor, smoke_weight)
	return lerpf(target_lower_c, source_mix_temp_c, carry_factor)


func estimate_thermal_gradient_depth_m(room: RoomModel) -> float:
	if room == null:
		return 0.0

	var hot_depth_m: float = maxf(0.0, room.height_m - effective_hot_layer_height_m(room))
	var smoke_depth_m: float = maxf(0.0, room.height_m - _smoke_model.get_visible_smoke_layer_height_m(room))
	var ref_depth_m: float = maxf(
		hot_depth_m * thermal_gradient_band_fraction,
		smoke_depth_m * thermal_gradient_band_fraction
	)
	if ref_depth_m <= 0.000001:
		return 0.0

	var min_span_m: float = maxf(0.50, minf(room.width_m, room.length_m))
	var max_span_m: float = maxf(room.width_m, room.length_m)
	if min_span_m > 0.0 and max_span_m > 0.0:
		var corridor_factor: float = clampf(inverse_lerp(2.0, 4.5, max_span_m / min_span_m), 0.0, 1.0)
		var heat_factor: float = clampf(inverse_lerp(80.0, 180.0, room.temp_upper_c), 0.0, 1.0)
		ref_depth_m *= lerpf(1.0, 0.72, corridor_factor * heat_factor)

	var min_band_m: float = minf(thermal_gradient_min_band_m, room.height_m)
	var smooth_depth_m: float = ref_depth_m
	if min_band_m > 0.000001 and ref_depth_m < min_band_m:
		var blend: float = clampf(ref_depth_m / min_band_m, 0.0, 1.0)
		smooth_depth_m = lerpf(ref_depth_m, min_band_m, blend)

	return clampf(
		smooth_depth_m,
		0.0,
		minf(minf(thermal_gradient_max_band_m, hot_depth_m), room.height_m)
	)


func _compute_room_vertical_mix_bonus(room: RoomModel) -> float:
	if room == null:
		return 0.0

	var min_span_m: float = maxf(0.50, minf(room.width_m, room.length_m))
	var max_span_m: float = maxf(room.width_m, room.length_m)
	if min_span_m <= 0.0 or max_span_m <= 0.0:
		return 0.0

	var slenderness: float = max_span_m / min_span_m
	if slenderness <= 2.0:
		return 0.0

	var corridor_factor: float = clampf(inverse_lerp(2.0, 4.5, slenderness), 0.0, 1.0)
	var hot_fill_m: float = maxf(0.0, room.height_m - effective_hot_layer_height_m(room))
	var fill_factor: float = clampf(hot_fill_m / maxf(0.35, room.height_m * 0.45), 0.0, 1.0)
	return 0.018 * corridor_factor * fill_factor


func _apply_post_transfer_vertical_mix(room: RoomModel, dt: float) -> void:
	if room == null or dt <= 0.0:
		return

	var mix_rate: float = _compute_room_vertical_mix_bonus(room)
	if mix_rate <= 0.0:
		return

	var delta_ul: float = maxf(0.0, room.temp_upper_c - room.temp_lower_c)
	if delta_ul <= 0.0 or room.upper_gas_kg <= 0.0001 or room.upper_energy_kj <= 0.0001:
		return

	var mix_energy_kj: float = room.upper_gas_kg * delta_ul * mix_rate * 0.45 * dt
	mix_energy_kj = minf(mix_energy_kj, room.upper_energy_kj)
	if mix_energy_kj <= 0.0:
		return

	room.upper_energy_kj -= mix_energy_kj
	var lower_mass_kg: float = maxf(
		1.0,
		gas_density_kg_m3(room.temp_lower_c) * room.floor_area_m2() * maxf(0.2, effective_hot_layer_height_m(room))
	)
	room.temp_lower_c += mix_energy_kj / lower_mass_kg
	sync_room_upper_layer(room, dt)


func estimate_floor_cooling_band_m(room: RoomModel) -> float:
	if room == null:
		return 0.0

	var ambient_c: float = ambient_temp_c()
	var lower_excess_c: float = maxf(0.0, room.temp_lower_c - ambient_c)
	if lower_excess_c <= 0.5:
		return 0.0

	var lower_layer_height_m: float = clampf(effective_hot_layer_height_m(room), 0.0, room.height_m)
	if lower_layer_height_m <= 0.000001:
		return 0.0

	var activation: float = clampf(
		lower_excess_c / maxf(1.0, survival_temp_threshold_c - ambient_c),
		0.0,
		1.0
	)
	var band_m: float = lower_layer_height_m * floor_cooling_band_fraction * activation
	return clampf(band_m, 0.0, minf(floor_cooling_band_max_m, lower_layer_height_m))


func estimate_temperature_at_height_m(room: RoomModel, height_m: float) -> float:
	if room == null:
		return ambient_temp_c()

	var ambient_c: float = ambient_temp_c()
	var z_m: float = clampf(height_m, 0.0, room.height_m)
	var gradient_depth_m: float = estimate_thermal_gradient_depth_m(room)
	var floor_band_m: float = estimate_floor_cooling_band_m(room)
	var interface_m: float = clampf(effective_hot_layer_height_m(room), 0.0, room.height_m)
	if gradient_depth_m <= 0.000001:
		if floor_band_m > 0.000001 and z_m <= floor_band_m:
			var floor_t_no_gradient: float = inverse_lerp(0.0, floor_band_m, z_m)
			return lerpf(ambient_c, room.temp_lower_c, floor_t_no_gradient)
		return room.temp_upper_c if z_m >= interface_m else room.temp_lower_c

	var gradient_bottom_m: float = clampf(interface_m - 0.5 * gradient_depth_m, 0.0, room.height_m)
	var gradient_top_m: float = clampf(interface_m + 0.5 * gradient_depth_m, gradient_bottom_m, room.height_m)
	if floor_band_m > 0.000001 and z_m <= floor_band_m:
		var floor_t: float = inverse_lerp(0.0, floor_band_m, z_m)
		return lerpf(ambient_c, room.temp_lower_c, floor_t)

	if z_m <= gradient_bottom_m:
		return room.temp_lower_c
	if z_m >= gradient_top_m:
		return room.temp_upper_c

	var t: float = inverse_lerp(gradient_bottom_m, gradient_top_m, z_m)
	return lerpf(room.temp_lower_c, room.temp_upper_c, t)


func estimate_isotherm_height_m(room: RoomModel, threshold_c: float) -> float:
	if room == null:
		return 0.0

	var ambient_c: float = ambient_temp_c()
	var floor_band_m: float = estimate_floor_cooling_band_m(room)
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

	var gradient_depth_m: float = estimate_thermal_gradient_depth_m(room)
	if gradient_depth_m <= 0.000001:
		return clampf(effective_hot_layer_height_m(room), 0.0, room.height_m)

	var interface_m: float = clampf(effective_hot_layer_height_m(room), 0.0, room.height_m)
	var gradient_bottom_m: float = clampf(interface_m - 0.5 * gradient_depth_m, 0.0, room.height_m)
	var gradient_top_m: float = clampf(interface_m + 0.5 * gradient_depth_m, gradient_bottom_m, room.height_m)
	if absf(room.temp_upper_c - room.temp_lower_c) <= 0.001:
		return room.height_m

	var t: float = clampf(
		(threshold_c - room.temp_lower_c) / (room.temp_upper_c - room.temp_lower_c),
		0.0,
		1.0
	)
	return clampf(lerpf(gradient_bottom_m, gradient_top_m, t), 0.0, room.height_m)


func update_room_layer_150c(room: RoomModel, dt: float) -> void:
	if room == null:
		return

	var raw_layer_150c_m: float = estimate_isotherm_height_m(room, survival_temp_threshold_c)
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


func compute_co_ppm(room: RoomModel) -> float:
	if room == null:
		return 0.0

	return room.co_kg * 29.0e6 / maxf(0.1, room.volume_m3() * 1.2 * 28.0)


func compute_hcn_ppm(room: RoomModel) -> float:
	if room == null:
		return 0.0

	# HCN MW = 27 g/mol; ppm = (hcn_kg / air_kg) × (MW_air/MW_hcn) × 1e6
	return room.hcn_kg * 29.0e6 / maxf(0.1, room.volume_m3() * 1.2 * 27.0)


func compute_hcl_ppm(room: RoomModel) -> float:
	if room == null:
		return 0.0
	# HCl MW = 36.5 g/mol
	return room.hcl_kg * 29.0e6 / maxf(0.1, room.volume_m3() * 1.2 * 36.5)


func compute_acrolein_ppm(room: RoomModel) -> float:
	if room == null:
		return 0.0
	# Acroleína MW = 56 g/mol
	return room.acrolein_kg * 29.0e6 / maxf(0.1, room.volume_m3() * 1.2 * 56.0)


func compute_formaldehyde_ppm(room: RoomModel) -> float:
	if room == null:
		return 0.0
	# Formaldehído MW = 30 g/mol
	return room.formaldehyde_kg * 29.0e6 / maxf(0.1, room.volume_m3() * 1.2 * 30.0)


func compute_co_upper_ppm(room: RoomModel) -> float:
	if room == null:
		return 0.0

	# Use the geometric upper-zone mass (CFAST-compatible zone model approach):
	# upper zone spans from the hot-layer interface up to the ceiling.
	var hot_h: float = effective_hot_layer_height_m(room)
	var upper_height_m: float = maxf(0.05, room.height_m - hot_h)
	var upper_zone_mass_kg: float = maxf(0.1,
		room.floor_area_m2() * upper_height_m * gas_density_kg_m3(room.temp_upper_c))
	var co_upper_kg: float = clampf(room.co_upper_kg, 0.0, room.co_kg)
	return co_upper_kg * 29.0e6 / maxf(0.1, upper_zone_mass_kg * 28.0)


func compute_co_lower_ppm(room: RoomModel) -> float:
	if room == null:
		return 0.0

	# Lower zone: from floor up to the hot-layer interface.
	var hot_h: float = effective_hot_layer_height_m(room)
	var lower_height_m: float = maxf(0.05, hot_h)
	var lower_zone_mass_kg: float = maxf(0.1,
		room.floor_area_m2() * lower_height_m * gas_density_kg_m3(room.temp_lower_c))
	var co_upper_kg: float = clampf(room.co_upper_kg, 0.0, room.co_kg)
	var co_lower_kg: float = maxf(0.0, room.co_kg - co_upper_kg)
	return co_lower_kg * 29.0e6 / maxf(0.1, lower_zone_mass_kg * 28.0)


func compute_co2_ppm(room: RoomModel) -> float:
	if room == null:
		return 0.0

	# Conversión masa CO2 → ppm volumétrico.
	# ppm = (m_co2 / M_co2) / (m_air / M_air) × 1e6
	# M_co2 = 44 g/mol, M_air = 29 g/mol
	return room.co2_kg * 29.0e6 / maxf(0.1, room.volume_m3() * 1.2 * 44.0)


## Paso incremental de FED (Fractional Effective Dose) según ISO 13571.
## Modelo asfixiante implementado:
## - FED_CO: narcosis por CO con factor de hiperventilación por CO2
## - FED_O2: hipoxia por depleción de oxígeno
## FED_total(Δt) = FED_CO(Δt) + FED_O2(Δt)
func step_fed(room: RoomModel, dt: float) -> void:
	if room == null or dt <= 0.0:
		return

	# Cuando la capa caliente desciende bajo la altura de respiración (1.8 m),
	# una persona de pie está inmersa en la capa superior — usar CO de capa alta.
	var in_upper_layer: bool = (room.h_layer_m < 1.8 and room.upper_gas_kg > 0.1)
	var co_ppm: float = compute_co_upper_ppm(room) if in_upper_layer else compute_co_ppm(room)
	var co2_ppm: float = compute_co2_ppm(room)

	var dt_min: float = dt / 60.0
	var delta_fed: float = 0.0

	# Factor de hiperventilación por CO2 (ISO 13571): se aplica a CO y a HCN.
	var co2_pct: float = co2_ppm / 10000.0
	var v_co2: float = 1.0
	if co2_pct > 2.0:
		v_co2 = exp(0.1903 * co2_pct + 2.0004) / 7.1

	# ISO 13571 Eq. 2-3: dosis incremental por CO, con ajuste por CO2 solo > 2% vol.
	if co_ppm > 0.0:
		delta_fed += 3.317e-5 * pow(co_ppm, 1.036) * v_co2 * dt_min

	# ISO 13571 §A.2.2: dosis incremental por HCN (cianuro de hidrógeno).
	# Modelo lineal de Purser: LC50 ≈ 4400 ppm·min (humano equivalente, 30 min).
	var hcn_ppm: float = compute_hcn_ppm(room)
	if hcn_ppm > 0.0:
		delta_fed += hcn_ppm / 4400.0 * v_co2 * dt_min

	# ISO 13571 (modelo asfixiante): componente de hipoxia por O2.
	if fed_hypoxia_enabled:
		var o2_pct: float = clampf(room.o2 * 100.0, 0.0, 20.9)
		var o2_deficit_pct: float = maxf(0.0, 20.9 - o2_pct)
		if o2_deficit_pct > 0.0:
			var t_crit_min: float = exp(fed_hypoxia_a - fed_hypoxia_b * o2_deficit_pct)
			if t_crit_min > 0.0:
				delta_fed += dt_min / t_crit_min

	# ISO 13571 §5.5 + §5.4.3: FED térmico (calor convectivo + radiante).
	if fed_heat_enabled and room.upper_gas_kg > 0.01:
		# --- Componente convectiva (ISO 13571 sec. 8.3) ---
		# Solo cuando el ocupante respira el gas caliente (inmerso en la capa superior).
		if in_upper_layer and room.temp_upper_c > fed_heat_conv_min_c:
			var tenab_min: float = fed_heat_conv_a * pow(room.temp_upper_c, -fed_heat_conv_n)
			var tenab_s: float = tenab_min * 60.0
			if tenab_s > 0.0:
				delta_fed += dt / tenab_s
		# --- Componente radiante (ISO 13571 §5.4.3) ---
		# Se aplica SIEMPRE que la capa superior esté caliente, incluso cuando el
		# ocupante está por debajo: la radiación viaja sin contacto con el gas.
		# CORRECCIÓN: fórmula Stefan-Boltzmann directa (la anterior usaba
		# upper_radiative_loss_kw × view_factor, que mezcla kW con kW/m²).
		# q''_rad = ε·σ·(T_capa⁴ − T_piel⁴) · F_vista
		var sigma_kw_m2_k4: float = 5.670374419e-11
		var t_upper_k: float = room.temp_upper_c + 273.15
		var t_skin_k: float = 310.0  # 37°C — temperatura superficie piel
		var vf: float = fed_heat_rad_view_factor if in_upper_layer else fed_heat_rad_view_factor_below
		var q_rad_kw_m2: float = maxf(0.0,
			0.85 * sigma_kw_m2_k4 * (pow(t_upper_k, 4.0) - pow(t_skin_k, 4.0)) * vf
		)
		if q_rad_kw_m2 > 2.5:
			var tenab_rad_s: float = fed_heat_rad_a / pow(q_rad_kw_m2, 1.33)
			if tenab_rad_s > 0.0 and tenab_rad_s < 3600.0:
				delta_fed += dt / tenab_rad_s

	room.fed += maxf(0.0, delta_fed)

	# FEC irritantes — SF-AUD-018 (ISO 13571 §A.3, sensory irritants).
	# FEC = [HCl]/IC50_HCl + [acrolein]/IC50_acrolein + [HCHO]/IC50_HCHO
	# IC50 (sensory incapacitation): HCl=900 ppm, acrolein=4 ppm, formaldehyde=250 ppm.
	# FEC ≥ 1.0 indica incapacitación por irritación; no es dosis acumulada.
	var hcl_ppm_fec: float = compute_hcl_ppm(room)
	var acrolein_ppm_fec: float = compute_acrolein_ppm(room)
	var formaldehyde_ppm_fec: float = compute_formaldehyde_ppm(room)
	room.fec_irritant = clampf(
		hcl_ppm_fec / 900.0 + acrolein_ppm_fec / 4.0 + formaldehyde_ppm_fec / 250.0,
		0.0,
		100.0
	)

	# Visibilidad instantánea (Purser): actualizar en room para SVV y exportación.
	room.visibility_m = _smoke_model.estimate_visibility_m(room) if _smoke_model != null else 30.0

	# SVV instantánea y peor histórica (monótona no creciente).
	room.svv_pct = _compute_svv_pct_from_room(room)
	room.svv_worst_pct = minf(room.svv_worst_pct, room.svv_pct)


func _compute_svv_pct_from_room(room: RoomModel) -> float:
	if room == null:
		return 100.0

	var height_m: float = maxf(0.1, room.height_m)
	var layer_150c: float = clampf(room.layer_150c_m, 0.0, height_m)
	var fed_val: float = maxf(0.0, room.fed)

	# Criterio térmico (isoterma 150°C, altura desde suelo).
	var thermal_svv: float
	if layer_150c >= 1.8:
		# La isoterma 150°C aún está por encima de 1.8 m.
		# Verificar si la capa caliente ha descendido bajo la altura de respiración
		# con temperatura suficiente para ser peligrosa (ISO 13571: límite 60°C a 1.8 m).
		var hot_h: float = clampf(room.h_layer_m, 0.0, height_m)
		if hot_h < 1.8 and room.temp_upper_c > 60.0:
			var penetration: float = clampf((1.8 - hot_h) / 0.3, 0.0, 1.0)
			var temp_factor: float = clampf((room.temp_upper_c - 60.0) / 90.0, 0.0, 1.0)
			thermal_svv = 1.0 - penetration * temp_factor
		else:
			thermal_svv = 1.0
	elif layer_150c >= 0.5:
		thermal_svv = 0.90 + 0.09 * (layer_150c - 0.5) / 1.3
	elif layer_150c > 0.10:
		thermal_svv = 0.05 + 0.85 * ((layer_150c - 0.10) / 0.40)
	else:
		thermal_svv = 0.0

	# Criterio FED (zonas tenabilidad):
	# <=0.1: ALTA, 0.1-0.3: MEDIA, 0.3-1.0: BAJA, >1.0: MÍNIMA hacia 0%.
	var fed_svv: float
	if fed_val <= 0.1:
		fed_svv = 1.0 - 0.01 * (fed_val / 0.1)
	elif fed_val <= 0.3:
		fed_svv = 0.99 - 0.09 * ((fed_val - 0.1) / 0.2)
	elif fed_val < 1.0:
		# BAJA→MÍNIMA: curva convexa potencia 1.5 (ISO 13571: FED=1.0 = incapacitación media)
		var t_fed: float = (fed_val - 0.3) / 0.7
		fed_svv = 0.90 * pow(1.0 - t_fed, 1.5)
	else:
		fed_svv = 0.0

	# Criterio visibilidad (Purser): ≥10m ALTA, 3–10m MEDIA, 1–3m BAJA, <1m MÍNIMA.
	var vis_val: float = maxf(0.0, room.visibility_m)
	var vis_svv: float
	if vis_val >= 10.0:
		vis_svv = 1.0
	elif vis_val >= 3.0:
		vis_svv = 0.90 + 0.10 * (vis_val - 3.0) / 7.0
	elif vis_val >= 1.0:
		vis_svv = 0.10 + 0.80 * (vis_val - 1.0) / 2.0
	else:
		vis_svv = 0.0

	return clampf(minf(minf(thermal_svv, fed_svv), vis_svv) * 100.0, 0.0, 100.0)


func is_room_quiescent(room: RoomModel) -> bool:
	if room == null:
		return true

	return (
		room.fire == null
		and room.hrr_kw <= 0.01
		and room.overpressure_pa <= 0.05
		and room.smoke_kg <= 0.0005
		and room.upper_gas_kg <= 0.001
		and room.upper_energy_kj <= 0.01
		and absf(room.temp_upper_c - ambient_temp_c()) <= 0.5
	)


func _should_collapse_thermal_layer(room: RoomModel) -> bool:
	if room == null:
		return true

	return (
		room.fire == null
		and room.hrr_kw <= 0.01
		and room.overpressure_pa <= 0.10
		and room.upper_energy_kj <= 0.5
		and absf(room.temp_upper_c - room.temp_lower_c) <= 0.5
		and absf(room.temp_upper_c - ambient_temp_c()) <= 1.0
	)


func _call_path_factor(callable: Callable, room_id: int) -> float:
	if not callable.is_valid():
		return 0.0
	return clampf(float(callable.call(room_id)), 0.0, 1.0)


func sync_room_upper_layer(room: RoomModel, dt: float) -> void:
	if room == null:
		return

	var ambient_c: float = ambient_temp_c()
	room.upper_gas_kg = maxf(0.0, room.upper_gas_kg)
	room.upper_energy_kj = maxf(0.0, room.upper_energy_kj)

	if _should_collapse_thermal_layer(room):
		room.upper_gas_kg = 0.0
		room.upper_energy_kj = 0.0
		room.co_upper_kg = 0.0
		room.temp_upper_c = room.temp_lower_c
		room.temp_upper_raw_c = room.temp_upper_c
		room.temp_upper_clamped = false
		room.upper_radiative_loss_kw = 0.0
		reset_thermal_layer(room)
		_smoke_model.recompute_layer_from_mass(room, dt, ambient_c)
		return

	if room.upper_gas_kg <= 0.0001 or room.upper_energy_kj <= 0.0001:
		room.upper_gas_kg = 0.0
		room.upper_energy_kj = 0.0
		room.co_upper_kg = 0.0
		room.temp_upper_c = maxf(room.temp_lower_c, ambient_c)
		room.temp_upper_raw_c = room.temp_upper_c
		room.temp_upper_clamped = false
		room.upper_radiative_loss_kw = 0.0
		reset_thermal_layer(room)
		_smoke_model.recompute_layer_from_mass(room, dt, ambient_c)
		return

	room.co_upper_kg = clampf(room.co_upper_kg, 0.0, room.co_kg)
	room.temp_upper_raw_c = _estimate_raw_upper_temp_c(room, ambient_c)
	room.temp_upper_clamped = room.temp_upper_raw_c > max_upper_temp_c
	room.temp_upper_c = maxf(room.temp_lower_c, minf(room.temp_upper_raw_c, max_upper_temp_c))
	room.upper_energy_kj = room.upper_gas_kg * maxf(0.0, room.temp_upper_c - ambient_c)
	var target_thermal_layer_m: float = estimate_thermal_layer_height_m(room)
	if target_thermal_layer_m < room.thermal_layer_m:
		# Capa descendiendo: asignación directa (sin relajación).
		# La masa en la capa superior ya es conservada — la interfaz ES la fórmula.
		room.thermal_layer_m = target_thermal_layer_m
	else:
		# Capa recuperándose (sube): relajación moderada para evitar saltos bruscos.
		room.thermal_layer_m = lerpf(
			room.thermal_layer_m,
			target_thermal_layer_m,
			clampf(layer_relax_up * dt, 0.0, 1.0)
		)
	_smoke_model.recompute_layer_from_mass(room, dt, ambient_c)


func update_temperature_cap_telemetry(room: RoomModel, dt: float) -> void:
	if room == null or dt <= 0.0:
		return
	if not room.temp_upper_clamped:
		return

	room.temp_upper_clamp_time_s += dt
	room.temp_upper_clamp_count += 1


func estimate_plume_upper_depth_m(room: RoomModel) -> float:
	if room == null or room.hrr_kw <= 0.0:
		return 0.0

	var floor_area_m2: float = maxf(1.0, room.floor_area_m2())
	var response: float = 1.0
	if plume_fill_response_s > 0.0:
		response = 1.0 - exp(-room.fire_time_s / plume_fill_response_s)

	# Heurístico calibrado: plume_fill_depth_coeff × √HRR / A_floor.
	# NOTA: McCaffrey (NBSIR 79-1910) da un caudal másico ṁ = 0.071·Qc^(1/3)·z^(5/3) [kg/s]
	# que requiere integración temporal dz/dt = -ṁ/(ρ·A) para obtener la posición de la interface,
	# no puede usarse directamente como "profundidad de capa" estática sin integración.
	# Mientras se implementa la ODE de descenso de capa, se mantiene el coeficiente empírico.
	var depth_m: float = plume_fill_depth_coeff * sqrt(room.hrr_kw) * response / floor_area_m2
	var max_depth_m: float = room.height_m * plume_fill_max_fraction
	return clampf(depth_m, 0.0, max_depth_m)


func effective_hot_layer_height_m(room: RoomModel) -> float:
	if room == null:
		return 0.0

	var hot_depth_m: float = maxf(
		estimate_plume_upper_depth_m(room),
		estimate_retained_hot_layer_depth_m(room)
	)
	var plume_layer_m: float = room.height_m - hot_depth_m
	return clampf(minf(room.thermal_layer_m, plume_layer_m), 0.0, room.height_m)


func _interior_spill_trigger_layer_m(room: RoomModel, lintel_m: float) -> float:
	if room == null:
		return lintel_m

	return minf(lintel_m, clampf(interior_spill_start_layer_m, 0.0, room.height_m))


func build_interior_opening_flow_state(room_a: RoomModel, room_b: RoomModel, op: OpeningModel) -> Dictionary:
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
	var hot_band_m: float = maxf(0.0, spill_trigger_layer_m - effective_hot_layer_height_m(hot_room))
	var smoke_band_m: float = maxf(
		0.0,
		spill_trigger_layer_m - _smoke_model.get_visible_smoke_layer_height_m(hot_room)
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

	var smoke_coupling: float = clampf(
		maxf(smoke_factor, cold_room.smoke_kg / 0.10),
		0.0,
		1.0
	)
	var source_temp_c: float = compute_interroom_transfer_temp_c(
		hot_room,
		cold_room,
		clampf(0.35 + 0.65 * engagement, 0.0, 1.0),
		smoke_coupling
	)
	var sink_temp_c: float = lerpf(cold_room.temp_lower_c, cold_room.temp_upper_c, 0.20)
	var temp_delta_k: float = maxf(0.0, source_temp_c - sink_temp_c)
	if temp_delta_k < 2.0:
		return state

	# Plano neutro físico — balance de presión hidrostática en dos zonas (SFPE §3.2).
	# h_n = h_thermal × (1/T_lower − 1/T_src) / (1/T_snk − 1/T_src)
	# Con T_lower ≈ T_snk (zona baja a temperatura ambiente): h_n ≈ h_thermal.
	# neutral_plane_f = fracción del vano [sill..lintel] ocupada por el gas caliente saliente.
	# Esto acopla el flujo térmico con la posición REAL de la interfaz capa caliente/fría.
	var t_src_k: float = source_temp_c + 273.15
	var t_snk_k: float = sink_temp_c + 273.15
	var t_lower_k: float = hot_room.temp_lower_c + 273.15
	var h_thermal_np: float = effective_hot_layer_height_m(hot_room)
	var inv_src_np: float = 1.0 / maxf(1.0, t_src_k)
	var inv_lower_np: float = 1.0 / maxf(1.0, t_lower_k)
	var inv_snk_np: float = 1.0 / maxf(1.0, t_snk_k)
	var denom_np: float = inv_snk_np - inv_src_np
	var neutral_plane_f: float
	if absf(denom_np) > 0.000005:
		var h_n: float = h_thermal_np * (inv_lower_np - inv_src_np) / denom_np
		h_n = clampf(h_n, 0.0, hot_room.height_m)
		var sill_np: float = op.sill_m
		var lintel_np: float = op.lintel_height_m()
		var outflow_h: float = clampf(lintel_np - h_n, 0.0, op.height_m)
		neutral_plane_f = clampf(outflow_h / maxf(0.01, op.height_m), 0.05, 0.90)
	else:
		neutral_plane_f = 0.50  # ambientes a igual temperatura: punto medio

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
	state["neutral_plane_f"] = neutral_plane_f
	return state

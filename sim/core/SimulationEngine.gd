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
const HVACSystemScript = preload("res://sim/core/HVACSystem.gd")

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
var hvac_system = HVACSystemScript.new()

# Cache de estados de flujo pre-computados para todas las aberturas interiores.
# Se recalcula una vez al comienzo de cada paso de tiempo y se comparte entre
# ThermalSystem y OxygenExchangeSystem para garantizar consistencia física.
var _opening_flow_cache: Dictionary = {}

const o2_nominal: float = 0.209

# ============================================================
# TIEMPO
# ============================================================

@export var time_scale: float = 1.0
var sim_time_s: float = 0.0

# Segundos sin fuego activo antes de declarar la simulación terminada.
@export var extinction_grace_s: float = 30.0
@export var auto_finish_on_extinction: bool = false
## Si > 0, la simulación se detiene automáticamente al alcanzar este tiempo (s).
@export var sim_duration_limit_s: float = 0.0
var is_finished: bool = false
var _extinction_countdown: float = 30.0
# Fraccion de apertura del step anterior por índice, para detectar cambios.
var _prev_open_fracs: Dictionary = {}
# Evita lanzar Python más de una vez por simulación.
var _graphs_launched: bool = false
var _last_graphs_dir: String = ""
var _last_graph_generation_ok: bool = false

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
var suppression_water_applied_l: float = 0.0
var suppression_cooling_total_kj: float = 0.0
var _active_suppression_by_room: Dictionary = {}

# ============================================================
# IGNICIÓN INICIAL
# ============================================================

@export var ignition_room_id: int = 0
@export var auto_ignite_on_ready: bool = true

# ============================================================
# PARÁMETROS BASE DEL FUEGO
# ============================================================

# NFPA 72 categorías: lento=0.003, medio=0.012, rápido=0.047, ultra-rápido=0.188 kW/s²
# Para mobiliario residencial tapizado (sofá, textiles) la categoría «rápido» es la
# referencia habitual en estudios NFPA/SFPE. Con α=0.047 el fuego alcanza 1 MW en ~146s.
@export var fire_alpha_kw_s2: float = 0.047
@export var fire_max_hrr_kw: float = 3000.0
# Incremento de max_hrr tras flashover. Refleja la incorporación simultánea de todos
# los combustibles de la sala. Limitado a 800 kW: el pico real está acotado por la
# ventilación (Kawagoe) y el O2 disponible, no por un bonus arbitrario.
@export var fire_secondary_hrr_gain_kw: float = 800.0

# Coeficiente de Kawagoe (SFPE/Drysdale): HRR_max = kawagoe_coeff × Σ(A_v × √H_v)
# Valor de referencia para madera: ~1500 kW/m^(5/2).  Reducir para materiales
# con rendimiento calórico menor.  Solo aplica cuando hay ventanas exteriores abiertas.
@export var kawagoe_coeff: float = 1500.0

@export var fire_o2_nominal: float = 0.209
@export var fire_o2_full_hrr_open: float = 0.209
# Concentración mínima de O2 (fracción volumétrica) para mantener llama sostenida.
# SFPE/Drysdale: la combustión con llama de sólidos orgánicos cesa generalmente
# por debajo del 12-14 % de O2. Valor de referencia: 0.122 (12.2 %).
@export var fire_o2_min_for_flame: float = 0.122
@export var fire_o2_consumption_kg_per_MJ: float = 0.076  # Regla de Thornton: 1/13.1 MJ/kgO2
# Rendimiento de humo (kg/MJ)
# SFPE: ~0.06 kg/kg ÷ 16 MJ/kg = 0.00375 kg/MJ
@export var fire_smoke_yield_kg_per_MJ: float = 0.0088
@export var fire_smoke_yield_low_o2_multiplier: float = 5.0
@export var fire_smoke_basis_min_fraction: float = 0.40
# Fracción del HRR ideal que se libera como smoldering cuando la llama se extingue.
# Literatura (Drysdale 2011, §1.2): smoldering típico es 5-15% del HRR en llama.
@export var fire_smolder_hrr_fraction: float = 0.06
@export var fire_smolder_smoke_multiplier: float = 2.8
@export var fire_retained_smoke_fraction: float = 0.38
@export var fire_pool_smoke_fraction: float = 0.42
@export var fire_latent_hrr_cap_min_fraction: float = 0.08
@export var fire_latent_hrr_cap_max_fraction: float = 0.35
# Multiplicador de yield de CO durante fase smoldering respecto a combustión deficiente.
# ISO 19706: smoldering madera CO ~0.08-0.15 kg/kg vs llama ~0.004 kg/kg → ×20-40.
# co_low_quality_yield ya es ×8 del base; multiplicar ×4 → ×32 total (≈0.008 kg/MJ).
@export var fire_latent_co_yield_multiplier: float = 4.0
@export var fire_retained_co_fraction: float = 0.08
@export var fire_pool_co_fraction: float = 0.40
@export var fire_co_low_quality_yield_multiplier: float = 8.0
@export var fire_co_max_effective_fraction: float = 0.22
@export var fire_subvent_o2_floor: float = 0.085
@export var fire_subvent_temp_start_c: float = 140.0
@export var fire_subvent_temp_full_c: float = 420.0
@export var fire_subvent_fill_start_fraction: float = 0.06
@export var fire_subvent_fill_full_fraction: float = 0.18
@export var fire_starvation_o2_factor: float = 0.003
# Cuando es true, el fuego ignora la limitacion de O2 y sigue la curva t2 pura.
# Util solo para pruebas analiticas: no representa el modelo de extincion de FDS.
@export var fire_o2_independent: bool = false
# Criterio simplificado inspirado en FDS EXTINCTION 1: a 20 C la llama deja de ser
# viable cerca de 13.5 % O2, y ese umbral baja al calentarse el gas. Como SimuFire
# es zonal, mantenemos un suelo de O2 para no liberar HRR sin oxidante local.
@export var fire_fds_extinction_enabled: bool = false
@export var fire_fds_extinction_o2_limit_ambient: float = 0.135
@export var fire_fds_extinction_ambient_c: float = 20.0
@export var fire_fds_extinction_hot_gas_c: float = 900.0
@export var fire_fds_extinction_hot_o2_floor: float = 0.105
@export var fire_fds_extinction_transition_width: float = 0.020
@export var fire_fds_extinction_pyrolysis_floor: float = 0.04

# Rendimiento de CO (kg/MJ)
# Derivado de ISO 19706 dividiendo el yield másico (kg/kg) por el calor efectivo
# de combustión de madera (~16 MJ/kg):
#   Combustión ventilada: 0.004 kg/kg ÷ 16 = 0.00025 kg/MJ
#   Combustión en déficit: 0.200 kg/kg ÷ 16 = 0.01250 kg/MJ
@export var co_base_yield_kg_per_MJ: float = 0.00025
@export var co_max_yield_kg_per_MJ: float = 0.01250

# Rendimiento de CO2 (kg/MJ)
# ISO 19706 — madera (combustible residencial dominante):
#   Combustión ventilada: 1.33 kg/kg ÷ 16 MJ/kg = 0.0831 kg/MJ
#   Combustión en déficit: 0.95 kg/kg ÷ 16 MJ/kg = 0.0594 kg/MJ
@export var co2_base_yield_kg_per_MJ: float = 0.0831
@export var co2_min_yield_kg_per_MJ: float = 0.0594
# Peso del combustion_completion_factor como suelo para el yield de CO2.
# Evita que CO2 caiga demasiado cuando el fuego está activo pero con déficit de O2.
# 0 = deshabilitado (comportamiento clásico); 0.55 = valor físicamente justificado.
@export var co2_completion_yield_weight: float = 0.75

# Rendimiento de HCN (kg/MJ)
# ISO 19706: madera ventilada ~0.001 kg/kg ÷ 20 MJ/kg = 0.00005 kg/MJ.
# Mezcla residencial con algo de espumas de poliuretano (muebles tapizados).
@export var hcn_base_yield_kg_per_MJ: float = 0.000040
@export var hcn_max_yield_kg_per_MJ: float = 0.000250

# Umbral de extinción: si el HRR real cae por debajo durante fire_extinction_delay_s
# segundos, el fuego se considera extinto (modela apagado por falta de ventilación).
@export var fire_extinction_hrr_kw: float = 8.0
@export var fire_extinction_delay_s: float = 180.0
@export var fire_latent_enabled: bool = true
@export var fire_latent_extinction_delay_s: float = 180.0
@export var fire_latent_hold_upper_temp_c: float = 140.0
@export var fire_latent_hold_lower_temp_c: float = 60.0
@export var fire_latent_min_remaining_fuel_MJ: float = 25.0
# Margen de O2 por encima de o2_min_for_flame necesario para sostener fuego latente.
# Con o2_min_for_flame=0.122, el fuego latente requiere O2 > 0.122+0.015 = 13.7 %.
# Evita el fuego zombi (ACH no puede mantener 13.7 % en sala casi sellada con fuego).
@export var fire_latent_o2_viable_margin: float = 0.015

# Supresion con agua: el caso UL/FSRI usa un golpe corto de 570 l/min durante 10 s
# (95 l) y reparte la extraccion termica a lo largo de la duracion del evento.
@export var suppression_heat_absorption_kj_per_l: float = 950.0
@export var suppression_hrr_decay_per_l: float = 0.024
@export var suppression_upper_heat_fraction: float = 0.68
@export var suppression_lower_cooling_fraction: float = 0.18
@export var suppression_surface_cooling_fraction: float = 0.26

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

# Filtrado temporal del oxidante efectivo y respuesta de HRR a la ventilacion.
@export var fire_o2_hrr_rise_tau_s: float = 14.0
@export var fire_o2_hrr_fall_tau_s: float = 32.0
@export var fire_subvent_pyrolysis_min_fraction: float = 0.08
@export var fire_subvent_pyrolysis_max_fraction: float = 0.18
@export var fire_unburned_generation_fraction: float = 0.30
@export var fire_unburned_capacity_MJ_per_m2: float = 1.20
@export var fire_unburned_decay_per_s: float = 0.0025
@export var fire_vent_response_temp_start_c: float = 140.0
@export var fire_vent_response_temp_full_c: float = 300.0
@export var fire_vent_response_rise_tau_s: float = 10.0
@export var fire_vent_response_fall_tau_s: float = 30.0
@export var fire_pool_release_tau_slow_s: float = 180.0
@export var fire_pool_release_tau_fast_s: float = 18.0
@export var fire_pool_release_max_fraction: float = 0.18
@export var fire_hrr_rise_tau_s: float = 6.0
@export var fire_hrr_fall_tau_s: float = 20.0
@export var fire_backdraft_pool_threshold_MJ: float = 8.0
@export var fire_backdraft_o2_max: float = 0.13
@export var fire_backdraft_temp_min_c: float = 180.0
@export var fire_backdraft_release_boost: float = 1.35
# Evento backdraft: multiplicador de HRR pico, duración del blast y cooldown de re-armado.
# Literatura (Gottuk 1992): bacakdraft genera picos de HRR 3-6× el máximo pre-extincion.
@export var fire_backdraft_hrr_multiplier: float = 4.0
@export var fire_backdraft_duration_s: float = 12.0
@export var fire_backdraft_cooldown_s: float = 180.0
@export var fire_remote_vent_path_enabled: bool = true
@export var fire_remote_vent_path_decay_per_door: float = 0.60
@export var fire_remote_vent_path_min_signal: float = 0.02
@export var fire_remote_vent_path_max_doors: int = 4

# ============================================================
# PROPAGACIÓN INTRA-SALA (ÍTEM 10 — GEOMETRÍA)
# ============================================================

# Activar cadena de ignición por radiación objeto-a-objeto dentro de la sala.
# Modelo punto fuente: q'' = Σ(hrr_src * view_factor / max(falloff², dist²)).
# Referencia: Drysdale "Introduction to Fire Dynamics", punto fuente de radiación.
@export var fire_intraroom_spread_enabled: bool = true
# Coeficiente de factor de vista punto-fuente para la sala (adimensional).
# 0.10 corresponde a un factor de vista efectivo de ~0.03 a 1.8 m — conservador.
@export var fire_intraroom_view_factor: float = 0.10
# Distancia de caída (m) que limita el flux en el campo cercano.
# Equivale a radio de zona de mezcla turbulenta de la llama (≈ 1 m).
@export var fire_intraroom_falloff_m: float = 1.0

# ============================================================
# PROPAGACIÓN DEL INCENDIO
# ============================================================

@export var fire_spread_enabled: bool = false
# Temperatura de capa superior del destino para propagación térmica directa.
# Referencia: temperatura de gas de ignición pilotada de madera ~300°C (SFPE).
@export var fire_spread_ignition_temp_c: float = 300.0
@export var fire_spread_max_layer_m: float = 1.6
@export var fire_spread_min_smoke_kg: float = 0.08
# Mínimo HRR de la sala fuente para iniciar evaluación de propagación.
@export var fire_spread_min_source_hrr_kw: float = 150.0
# Tiempo de exposición sostenida necesario para ignición. A 90 s equivale
# a ~1.5 min de condiciones críticas mantenidas antes de ignorizar.
@export var fire_spread_required_exposure_s: float = 90.0
# Semivida de decaimiento de la exposición cuando las condiciones no se cumplen.
@export var fire_spread_exposure_decay_s: float = 20.0

# La autoignicion de proxies "sala completa" genera propagaciones demasiado
# agresivas para el escenario base y las validaciones zonales. Se mantiene como
# capacidad opt-in para futuros casos con combustible objetual mas detallado.
@export var passive_room_autoignite_enabled: bool = false

# ============================================================
# FLASHOVER SIMPLE
# ============================================================

@export var flashover_temp_c: float = 500.0
@export var flashover_layer_m: float = 1.2
@export var flashover_head_height_m: float = 1.8
@export var flashover_head_temp_c: float = 150.0
@export var flashover_breathing_height_m: float = 0.9
@export var flashover_breathing_temp_c: float = 600.0
@export var flashover_require_tenability_loss: bool = true

# ============================================================
# AJUSTES TÉRMICOS
# ============================================================

@export var upper_to_lower_loss_rate: float = 0.025
@export var upper_to_ambient_loss_rate: float = 0.008
@export var lower_layer_warming_rate: float = 0.0120
@export var max_upper_temp_c: float = 900.0
@export var upper_radiative_loss_enabled: bool = true
@export var upper_radiative_loss_start_c: float = 80.0
@export var upper_radiative_loss_emissivity: float = 0.90
@export var upper_radiative_loss_area_factor: float = 1.10
@export var upper_radiative_loss_max_fraction_per_step: float = 0.45
@export var doorway_heat_exchange_coeff: float = 1.0
@export var doorway_source_upper_weight: float = 0.60
@export var smoke_heat_mix_coeff: float = 0.025
@export var upper_heat_capture_min: float = 0.10
@export var upper_heat_capture_max: float = 0.25
@export var upper_heat_capture_outside_open_bonus: float = 0.0
# Fracción radiativa χ_rad del HRR. Reemplaza upper_heat_capture_min/max con física real.
# 0.35 = valor típico para combustibles sólidos (SFPE Handbook 3rd Ed. §3.4).
@export var hrr_chi_rad_normal: float = 0.35
@export var hrr_chi_rad_low_o2: float = 0.50
@export var retained_hot_layer_temp_start_c: float = 100.0
@export var retained_hot_layer_temp_full_c: float = 350.0
@export var retained_hot_layer_o2_start: float = 0.18
@export var retained_hot_layer_o2_full: float = 0.10
@export var retained_hot_layer_max_fraction: float = 0.0
@export var outside_open_loss_area_fraction: float = 0.12
@export var outside_open_ambient_loss_multiplier: float = 5.0
@export var outside_open_wall_absorption_multiplier: float = 0.80
@export var outside_open_upper_mix_rate: float = 0.10
@export var outside_open_lower_warming_rate: float = 0.0
@export var natural_vent_inlet_fraction: float = 0.5
@export var outside_open_background_heat_exchange_kg_s_m2: float = 0.030
@export var outside_open_background_heat_max_fraction_per_step: float = 0.020
@export var outside_open_background_heat_carry_factor: float = 0.42
@export var interior_background_heat_exchange_kg_s_m2: float = 0.015
@export var interior_background_heat_max_fraction_per_step: float = 0.012
@export var interior_background_heat_carry_factor: float = 0.38
@export var hot_gas_species_carry_fraction: float = 0.72
@export var hot_gas_smoke_carry_fraction: float = 0.30
@export var hot_gas_species_max_fraction_per_step: float = 0.22
@export var thermal_gradient_min_band_m: float = 0.20
@export var thermal_gradient_max_band_m: float = 0.70
@export var thermal_gradient_band_fraction: float = 0.35
@export var floor_cooling_band_fraction: float = 0.24
@export var floor_cooling_band_max_m: float = 0.35
@export var survival_temp_threshold_c: float = 150.0
# Con dt=10 s: lerp = 0.05*10 = 0.50 (descenso rápido pero no instantáneo).
# ISO 19706 / NFPA: la interfaz 150°C desciende en segundos en flashover,
# pero no instantáneamente al primer step de 10 s.
@export var layer_150c_relax_down_per_s: float = 0.05

# ============================================================
# FED — HIPOXIA (ISO 13571)
# ============================================================
## Activar/desactivar el componente de hipoxia en el FED.
@export var fed_hypoxia_enabled: bool = true
## Constante a del modelo exponencial de hipoxia: t_crit = exp(a - b * déficit_O2%)
## Valor de referencia ISO 13571: a = 8.13
@export var fed_hypoxia_a: float = 8.13
## Constante b del modelo exponencial de hipoxia.
## Valor de referencia ISO 13571: b = 0.54
@export var fed_hypoxia_b: float = 0.54

# ============================================================
# FED — CALOR (ISO 13571 §5.5)
# ============================================================
## Activar/desactivar el componente térmico (calor convectivo + radiante) en el FED.
@export var fed_heat_enabled: bool = true
## Constante A de la curva convectiva ISO 13571 sec. 8.3: tIconv(min)=A*T^-n.
@export var fed_heat_conv_a: float = 4.1e8
## Exponente n de la curva convectiva ISO 13571 sec. 8.3.
@export var fed_heat_conv_n: float = 3.61
## Temperatura mínima de gas (°C) para acumular FED convectivo (ISO 13571: 60°C).
@export var fed_heat_conv_min_c: float = 60.0
## Constante para el tiempo de tenabilidad radiante (ISO 13571 §5.4.3): t = A/q^1.33 [s, kW/m²].
@export var fed_heat_rad_a: float = 1.33e4
## Factor de vista radiante: fracción del flujo radiante total que incide sobre la persona.
@export var fed_heat_rad_view_factor: float = 0.20

@export var layer_150c_relax_up_per_s: float = 0.01

# ============================================================
# PROPAGACIÓN POR RADIACIÓN A TRAVÉS DE APERTURAS
# ============================================================
# Modela la irradiación de la capa superior caliente hacia salas adyacentes a través
# de puertas y ventanas abiertas. Física: Stefan-Boltzmann con factor de vista empírico.
# φ=0.25 es representativo para apertura de puerta a habitación adyacente (Drysdale 2011).
@export var radiation_opening_enabled: bool = true
## Emisividad efectiva de la llama/capa caliente (mezcla gas + partículas de hollín).
@export var radiation_flame_emissivity: float = 0.85
## Factor de vista efectivo apertura→sala adyacente (geometría típica de puerta residencial).
@export var radiation_opening_view_factor: float = 0.25
## Fracción del flujo radiante que pasa a través del humo (resto es absorbido/dispersado).
@export var radiation_smoke_attenuation_factor: float = 0.55
## Temperatura mínima de la capa superior fuente para emitir radiación significativa.
@export var radiation_min_source_temp_c: float = 200.0
## Fracción máxima de la energía de la capa superior transferible por radiación en un paso.
@export var radiation_max_fraction_per_step: float = 0.25

## Budget energético por sala — diagnóstico CFAST-lite.
## Activar para imprimir warning si el residual térmico supera el umbral.
@export var energy_budget_enabled: bool = false
@export var energy_budget_warn_fraction: float = 0.10


# Absorción de calor por paredes — término proporcional simple sobre (T_upper - T_ambient).
# Mismo patrón que upper_to_ambient_loss_rate: sin dividir por m_upper_kg → estable.
# 0.003 /s → a 800°C de diferencia: 2.4°C/s adicionales (modest, calibratable).
@export var wall_absorption_rate: float = 0.003
@export var wall_heat_capacity_kj_m2_k: float = 20.0
@export var wall_core_decay_per_s: float = 0.0002
# Conducción a través de paredes entre salas adyacentes (sin apertura abierta).
# U = 1.5 W/m²K = 0.0015 kW/m²K — partición ligera (yeso + montante metálico).
# Para mampostería: reducir a 0.0008-0.001. Desactivar con wall_conduction_enabled=false.
@export var wall_conduction_enabled: bool = true
@export var wall_conduction_u_kw_m2_k: float = 0.0015

# ============================================================
# VENTILACIÓN PULSANTE POR FUGAS EN VENTANAS
# ============================================================

# Área de fuga efectiva por ventana cerrada (huecos en marco, juntas degradadas).
# Valor típico residencial: 0.003-0.008 m². Con 0.005 m²/ventana y ΔP=5 Pa → ~0.01 kg/s.
@export var window_leakage_area_m2: float = 0.005

# Umbral de sobrepresión para iniciar venteo. Por debajo no hay fuga neta.
@export var pressure_vent_threshold_pa: float = 2.0

# Efecto chimenea (stack effect): incrementa la sobrepresión en salas de plantas
# superiores (con floor_level_z_m > 0 en la plantilla) por el gradiente térmico
# vertical. Activo por defecto; desactivar para edificios de planta única.
@export var stack_effect_enabled: bool = true
# Efecto del viento en aperturas exteriores: modifica la presión efectiva de
# venteo según la orientación de la cara (wall_side en el template JSON) y las
# condiciones de viento en BuildingModel (wind_speed_m_s, wind_direction_deg).
@export var wind_effect_enabled: bool = true
# Deformación de puerta por temperatura: una puerta cerrada empieza a perder
# hermeticidad cuando la capa superior supera door_deform_temp_start_c.
# Útil para el escenario de formación "la puerta cerrada salva vidas".
@export var door_deform_enabled: bool = true
@export var door_deform_temp_start_c: float = 150.0
@export var door_deform_temp_full_c: float = 350.0
@export var door_deform_max_gap: float = 0.04
# Detectores automáticos (humo, calor, CO) definidos en la plantilla JSON.
# Cuando un detector se activa, se registra un evento "detector_triggered" en
# el log y se marca como triggered en building.detectors[].
@export var detectors_enabled: bool = true
# Modelo de jet de techo de Alpert (1972) para detectores de calor.
# Calcula la temperatura del jet en la posición del detector a partir de la
# potencia calorífica (HRR) y la distancia horizontal al penacho.
# Requiere que el detector JSON incluya x_m/y_m; si no, usa el centro de la sala.
@export var ceiling_jet_enabled: bool = true
# Fuego de charco (pool fire) con área de derrame que crece con el tiempo.
# Modela incendios de líquidos inflamables (gasolina, aceite) donde la potencia
# calorífica es proporcional al área del charco: HRR = pool_hrr_kw_m2 * area_m2.
@export var pool_fire_enabled: bool = true

# ============================================================
# OXÍGENO / MEZCLA
# ============================================================

@export var ach_infiltration: float = 0.50  # Renovaciones de aire/hora por fugas del edificio
@export var interior_transport_enabled: bool = true
@export var interior_transport_speed_m_s: float = 0.28
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
# Carry de O2 con el parcel de gas caliente en el transporte de humo inter-sala.
# 0.0 = deshabilitado (default; baselines sin cambio).
# Cuando > 0: bidireccional, neto = (source.o2 - target.o2) × gas_parcel_kg × coeff.
# Rango útil: 0.10-0.50. No usar con moved_upper_gas_kg (tiene floor de 0.03 kg).
@export var o2_smoke_carry_coeff: float = 0.0

# ============================================================
# AJUSTES DE HUMO (se copian al SmokeModel)
# ============================================================

@export var smoke_density_kg_m3: float = 0.18
@export var smoke_temp_expansion_upper_weight: float = 0.45
@export var smoke_temp_expansion_cap_c: float = 400.0
@export var smoke_visibility_extinction_m2_per_kg: float = 8700.0
@export var smoke_visibility_c_factor: float = 3.0
@export var smoke_visibility_max_m: float = 30.0
@export var base_spill_kg_s_per_m2: float = 0.30
@export var temp_push_factor: float = 0.005
@export var max_spill_kg_s: float = 2.0
@export var max_fraction_out_per_s: float = 0.18
@export var layer_relax_down: float = 0.18
@export var layer_relax_up: float = 0.10
@export var layer_recovery_gap_start_m: float = 0.20
@export var layer_recovery_gap_full_m: float = 1.00
@export var layer_recovery_boost_max: float = 6.0
@export var layer_recovery_low_hrr_threshold_kw: float = 120.0
@export var layer_recovery_low_hrr_boost: float = 1.6
@export var plume_fill_depth_coeff: float = 0.60
@export var plume_fill_response_s: float = 12.0
@export var plume_fill_max_fraction: float = 0.85
@export var plume_mccaffrey_enabled: bool = true
@export var plume_mccaffrey_qc_fraction: float = 0.70
@export var plume_fire_diameter_m: float = 1.0
@export var plume_flame_region_entrainment_enabled: bool = false
@export var plume_flame_region_coeff: float = 0.071
@export var plume_flame_region_min_z_m: float = 0.20
@export var plume_flame_region_max_depth_fraction: float = 0.97
@export var thermal_plume_depth_scale: float = 0.40
@export var target_smoke_resistance_coeff: float = 0.20
@export var target_layer_block_start_m: float = 0.65
@export var target_layer_block_full_m: float = 0.10
@export var interior_spill_start_layer_m: float = 2.0
@export var interior_spill_full_layer_m: float = 0.8
@export var pressure_spill_min_delta_pa: float = 0.5
@export var pressure_spill_ref_delta_pa: float = 8.0
@export var pressure_spill_max_multiplier: float = 2.5
@export var thermal_smoke_bridge_ref_kg_m3: float = 0.014
@export var thermal_smoke_bridge_max_weight: float = 0.35
@export var thermal_smoke_bridge_hot_temp_start_c: float = 150.0
@export var thermal_smoke_bridge_hot_temp_full_c: float = 360.0
@export var thermal_smoke_bridge_hot_max_weight: float = 0.18
@export var postfire_cleanup_hot_stop_c: float = 90.0
@export var postfire_cleanup_cool_full_c: float = 35.0
@export var postfire_cleanup_pressure_stop_pa: float = 0.8
@export var postfire_cleanup_pressure_full_pa: float = 0.10
@export var smoke_settling_base_per_s: float = 0.00004
@export var smoke_settling_bonus_per_s: float = 0.00018
@export var co_postfire_purge_base_per_s: float = 0.0
@export var co_postfire_purge_bonus_per_s: float = 0.0
@export var outside_open_species_purge_base_per_s: float = 0.015
@export var outside_open_species_purge_bonus_per_s: float = 0.11
@export var outside_open_species_temp_start_c: float = 60.0
@export var outside_open_species_temp_full_c: float = 220.0
@export var outside_open_species_pressure_ref_pa: float = 4.0
@export var outside_open_species_upper_bias: float = 0.80
@export var background_species_exchange_kg_s_m2: float = 0.035
@export var background_species_path_multiplier_max: float = 3.00
@export var background_species_max_fraction_closed: float = 0.010
@export var background_species_max_fraction_open: float = 0.040
@export var flow_path_direct_fire_vent_reduction: float = 0.0
@export var flow_path_direct_fire_min_vent_fraction: float = 0.0
@export var flow_path_interior_pull_boost: float = 0.0
@export var flow_path_interior_pull_max_multiplier: float = 1.0

# ============================================================
# REGISTRO DE VALORES
# ============================================================

@export var enable_logging: bool = true
@export var log_interval_s: float = 10.0
@export var log_file_path: String = "res://sim_log.txt"
## Si es true, también guarda el log en formato CSV al parar la simulación.
@export var enable_csv_log: bool = true
@export var csv_log_file_path: String = "res://sim_log.csv"

# ============================================================
# SERVICIOS AUXILIARES
# ============================================================

func _sync_auxiliary_services() -> void:
	if not is_ready_for_validation():
		push_error("SimulationEngine: subsistemas no inicializados; no se puede sincronizar")
		return

	thermal_system.set_references(building, smoke_model)
	thermal_system.configure({
		"upper_to_lower_loss_rate": upper_to_lower_loss_rate,
		"upper_to_ambient_loss_rate": upper_to_ambient_loss_rate,
		"lower_layer_warming_rate": lower_layer_warming_rate,
		"wall_absorption_rate": wall_absorption_rate,
		"wall_heat_capacity_kj_m2_k": wall_heat_capacity_kj_m2_k,
		"wall_core_decay_per_s": wall_core_decay_per_s,
		"wall_conduction_enabled": wall_conduction_enabled,
		"wall_conduction_u_kw_m2_k": wall_conduction_u_kw_m2_k,
		"max_upper_temp_c": max_upper_temp_c,
		"upper_radiative_loss_enabled": upper_radiative_loss_enabled,
		"upper_radiative_loss_start_c": upper_radiative_loss_start_c,
		"upper_radiative_loss_emissivity": upper_radiative_loss_emissivity,
		"upper_radiative_loss_area_factor": upper_radiative_loss_area_factor,
		"upper_radiative_loss_max_fraction_per_step": upper_radiative_loss_max_fraction_per_step,
		"doorway_heat_exchange_coeff": doorway_heat_exchange_coeff,
		"doorway_source_upper_weight": doorway_source_upper_weight,
		"smoke_heat_mix_coeff": smoke_heat_mix_coeff,
		"upper_heat_capture_min": upper_heat_capture_min,
		"upper_heat_capture_max": upper_heat_capture_max,
		"upper_heat_capture_outside_open_bonus": upper_heat_capture_outside_open_bonus,
		"hrr_chi_rad_normal": hrr_chi_rad_normal,
		"hrr_chi_rad_low_o2": hrr_chi_rad_low_o2,
		"retained_hot_layer_temp_start_c": retained_hot_layer_temp_start_c,
		"retained_hot_layer_temp_full_c": retained_hot_layer_temp_full_c,
		"retained_hot_layer_o2_start": retained_hot_layer_o2_start,
		"retained_hot_layer_o2_full": retained_hot_layer_o2_full,
		"retained_hot_layer_max_fraction": retained_hot_layer_max_fraction,
		"outside_open_loss_area_fraction": outside_open_loss_area_fraction,
		"outside_open_ambient_loss_multiplier": outside_open_ambient_loss_multiplier,
		"outside_open_wall_absorption_multiplier": outside_open_wall_absorption_multiplier,
		"outside_open_upper_mix_rate": outside_open_upper_mix_rate,
		"outside_open_lower_warming_rate": outside_open_lower_warming_rate,
		"outside_open_background_heat_exchange_kg_s_m2": outside_open_background_heat_exchange_kg_s_m2,
		"outside_open_background_heat_max_fraction_per_step": outside_open_background_heat_max_fraction_per_step,
		"outside_open_background_heat_carry_factor": outside_open_background_heat_carry_factor,
		"interior_background_heat_exchange_kg_s_m2": interior_background_heat_exchange_kg_s_m2,
		"interior_background_heat_max_fraction_per_step": interior_background_heat_max_fraction_per_step,
		"interior_background_heat_carry_factor": interior_background_heat_carry_factor,
		"hot_gas_species_carry_fraction": hot_gas_species_carry_fraction,
		"hot_gas_smoke_carry_fraction": hot_gas_smoke_carry_fraction,
		"hot_gas_species_max_fraction_per_step": hot_gas_species_max_fraction_per_step,
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
		"interior_spill_start_layer_m": interior_spill_start_layer_m,
		"plume_mccaffrey_enabled": plume_mccaffrey_enabled,
		"plume_mccaffrey_qc_fraction": plume_mccaffrey_qc_fraction,
		"plume_fire_diameter_m": plume_fire_diameter_m,
		"plume_flame_region_entrainment_enabled": plume_flame_region_entrainment_enabled,
		"plume_flame_region_coeff": plume_flame_region_coeff,
		"plume_flame_region_min_z_m": plume_flame_region_min_z_m,
		"plume_flame_region_max_depth_fraction": plume_flame_region_max_depth_fraction,
		"fed_hypoxia_enabled": fed_hypoxia_enabled,
		"fed_hypoxia_a": fed_hypoxia_a,
		"fed_hypoxia_b": fed_hypoxia_b,
		"fed_heat_enabled": fed_heat_enabled,
		"fed_heat_conv_a": fed_heat_conv_a,
		"fed_heat_conv_n": fed_heat_conv_n,
		"fed_heat_conv_min_c": fed_heat_conv_min_c,
		"fed_heat_rad_a": fed_heat_rad_a,
		"fed_heat_rad_view_factor": fed_heat_rad_view_factor,
		"radiation_opening_enabled": radiation_opening_enabled,
		"radiation_flame_emissivity": radiation_flame_emissivity,
		"radiation_opening_view_factor": radiation_opening_view_factor,
		"radiation_smoke_attenuation_factor": radiation_smoke_attenuation_factor,
		"radiation_min_source_temp_c": radiation_min_source_temp_c,
		"radiation_max_fraction_per_step": radiation_max_fraction_per_step,
		"energy_budget_enabled": energy_budget_enabled,
		"energy_budget_warn_fraction": energy_budget_warn_fraction
	})
	fire_spread_system.set_references(building, smoke_model, combustion_system)
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
		"co_postfire_purge_bonus_per_s": co_postfire_purge_bonus_per_s,
		"outside_open_species_purge_base_per_s": outside_open_species_purge_base_per_s,
		"outside_open_species_purge_bonus_per_s": outside_open_species_purge_bonus_per_s,
		"outside_open_species_temp_start_c": outside_open_species_temp_start_c,
		"outside_open_species_temp_full_c": outside_open_species_temp_full_c,
		"outside_open_species_pressure_ref_pa": outside_open_species_pressure_ref_pa,
		"outside_open_species_upper_bias": outside_open_species_upper_bias,
		"background_species_exchange_kg_s_m2": background_species_exchange_kg_s_m2,
		"background_species_path_multiplier_max": background_species_path_multiplier_max,
		"background_species_max_fraction_closed": background_species_max_fraction_closed,
		"background_species_max_fraction_open": background_species_max_fraction_open,
		"flow_path_direct_fire_vent_reduction": flow_path_direct_fire_vent_reduction,
		"flow_path_direct_fire_min_vent_fraction": flow_path_direct_fire_min_vent_fraction,
		"flow_path_interior_pull_boost": flow_path_interior_pull_boost,
		"flow_path_interior_pull_max_multiplier": flow_path_interior_pull_max_multiplier,
		"flow_path_remote_decay_per_door": fire_remote_vent_path_decay_per_door,
		"flow_path_remote_max_doors": fire_remote_vent_path_max_doors,
		"stack_effect_enabled": stack_effect_enabled,
		"wind_effect_enabled": wind_effect_enabled,
		"door_deform_enabled": door_deform_enabled,
		"door_deform_temp_start_c": door_deform_temp_start_c,
		"door_deform_temp_full_c": door_deform_temp_full_c,
		"door_deform_max_gap": door_deform_max_gap,
		"natural_vent_inlet_fraction": natural_vent_inlet_fraction,
		"o2_smoke_carry_coeff": o2_smoke_carry_coeff
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
	log_writer.configure_csv(enable_csv_log, csv_log_file_path)


func _build_state_context() -> Dictionary:
	return {
		"building": building,
		"smoke_model": smoke_model,
		"combustion_system": combustion_system,
		"sim_time_s": sim_time_s,
		"smoke_generated_total_kg": smoke_generated_total_kg,
		"smoke_vented_total_kg": smoke_vented_total_kg,
		"smoke_deposited_total_kg": smoke_deposited_total_kg,
		"suppression_water_applied_l": suppression_water_applied_l,
		"suppression_cooling_total_kj": suppression_cooling_total_kj,
		"hvac": building.build_hvac_summary() if building != null else {},
		"kawagoe_coeff": kawagoe_coeff,
		"estimate_temperature_callable": Callable(thermal_system, "estimate_temperature_at_height_m"),
		"effective_hot_layer_callable": Callable(thermal_system, "effective_hot_layer_height_m"),
		"compute_co_ppm_callable": Callable(thermal_system, "compute_co_ppm"),
		"compute_co_upper_ppm_callable": Callable(thermal_system, "compute_co_upper_ppm"),
		"compute_co_lower_ppm_callable": Callable(thermal_system, "compute_co_lower_ppm"),
		"compute_co2_ppm_callable": Callable(thermal_system, "compute_co2_ppm"),
		"compute_hcn_ppm_callable": Callable(thermal_system, "compute_hcn_ppm"),
		"is_quiescent_callable": Callable(thermal_system, "is_room_quiescent"),
		"window_open_max_callable": Callable(self, "_window_open_max_for_room"),
		"outside_open_path_factor_callable": Callable(self, "_outside_open_path_factor_for_room"),
		"kawagoe_factor_callable": Callable(self, "_kawagoe_factor_for_room"),
		"energy_budget": thermal_system.get_energy_budget() if energy_budget_enabled else {}
	}


func _build_gas_exchange_hooks() -> Dictionary:
	return {
		"effective_hot_layer_height_callable": Callable(thermal_system, "effective_hot_layer_height_m"),
		"remove_upper_layer_fraction_callable": Callable(thermal_system, "remove_upper_layer_fraction"),
		"sync_room_upper_layer_callable": Callable(thermal_system, "sync_room_upper_layer"),
		"compute_interroom_transfer_temp_callable": Callable(thermal_system, "compute_interroom_transfer_temp_c"),
		"outside_open_path_factor_callable": Callable(self, "_outside_open_path_factor_for_room"),
		"build_interior_opening_flow_state_callable": Callable(thermal_system, "build_interior_opening_flow_state")
	}


func _build_oxygen_exchange_hooks() -> Dictionary:
	return {
		"effective_hot_layer_height_callable": Callable(thermal_system, "effective_hot_layer_height_m"),
		"build_interior_opening_flow_state_callable": Callable(thermal_system, "build_interior_opening_flow_state"),
		"opening_flow_cache": _opening_flow_cache,
		"outside_open_path_factor_callable": Callable(self, "_outside_open_path_factor_for_room")
	}


# Construye un diccionario {op → flow_state} para todas las aberturas interiores
# activas. La clave es el objeto OpeningModel; el valor es el dict devuelto por
# ThermalSystem.build_interior_opening_flow_state(). Solo aberturas entre dos
# habitaciones (sin OUTSIDE_ID) y con open_fraction > 0 son incluidas.
func _build_opening_flow_cache() -> Dictionary:
	var cache: Dictionary = {}
	if building == null:
		return cache
	for op in building.get_openings():
		if op == null or op.open_fraction <= 0.0:
			continue
		if op.a == BuildingModel.OUTSIDE_ID or op.b == BuildingModel.OUTSIDE_ID:
			continue
		var room_a: RoomModel = building.get_room(op.a)
		var room_b: RoomModel = building.get_room(op.b)
		if room_a == null or room_b == null:
			continue
		cache[op] = thermal_system.build_interior_opening_flow_state(room_a, room_b, op)
	return cache


func _build_hvac_hooks() -> Dictionary:
	return {
		"effective_hot_layer_height_callable": Callable(thermal_system, "effective_hot_layer_height_m"),
		"estimate_temperature_callable": Callable(thermal_system, "estimate_temperature_at_height_m"),
		"remove_upper_layer_fraction_callable": Callable(thermal_system, "remove_upper_layer_fraction"),
		"sync_room_upper_layer_callable": Callable(thermal_system, "sync_room_upper_layer"),
		"ambient_temp_callable": Callable(thermal_system, "ambient_temp_c")
	}

# ============================================================
# READY
# ============================================================

func _ready() -> void:
	_resolve_building()
	if building != null and building.default_ignition_room_id != 0:
		ignition_room_id = building.default_ignition_room_id
	if building != null and building.sim_stop_time_s > 0.0:
		sim_duration_limit_s = building.sim_stop_time_s
	combustion_system.bootstrap_building(building)
	_sync_smoke_model_settings()
	_sync_auxiliary_services()
	gas_exchange_system.reset()
	oxygen_exchange_system.reset()
	hvac_system.reset()
	_reset_log_file()

	if auto_ignite_on_ready:
		ignite_room(ignition_room_id)

	print(log_writer.resolve_log_file_path())

# ============================================================
# REINICIAR LOG
# ============================================================

func _reset_log_file() -> void:
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
	smoke_model.smoke_temp_expansion_upper_weight = smoke_temp_expansion_upper_weight
	smoke_model.smoke_temp_expansion_cap_c = smoke_temp_expansion_cap_c
	smoke_model.visibility_extinction_m2_per_kg = smoke_visibility_extinction_m2_per_kg
	smoke_model.visibility_c_factor = smoke_visibility_c_factor
	smoke_model.visibility_max_m = smoke_visibility_max_m
	smoke_model.base_spill_kg_s_per_m2 = base_spill_kg_s_per_m2
	smoke_model.temp_push_factor = temp_push_factor
	smoke_model.max_spill_kg_s = max_spill_kg_s
	smoke_model.max_fraction_out_per_s = max_fraction_out_per_s
	smoke_model.layer_relax_down = layer_relax_down
	smoke_model.layer_relax_up = layer_relax_up
	smoke_model.layer_recovery_gap_start_m = layer_recovery_gap_start_m
	smoke_model.layer_recovery_gap_full_m = layer_recovery_gap_full_m
	smoke_model.layer_recovery_boost_max = layer_recovery_boost_max
	smoke_model.layer_recovery_low_hrr_threshold_kw = layer_recovery_low_hrr_threshold_kw
	smoke_model.layer_recovery_low_hrr_boost = layer_recovery_low_hrr_boost
	smoke_model.target_smoke_resistance_coeff = target_smoke_resistance_coeff
	smoke_model.target_layer_block_start_m = target_layer_block_start_m
	smoke_model.target_layer_block_full_m = target_layer_block_full_m
	smoke_model.interior_spill_start_layer_m = interior_spill_start_layer_m
	smoke_model.interior_spill_full_layer_m = interior_spill_full_layer_m
	smoke_model.pressure_spill_min_delta_pa = pressure_spill_min_delta_pa
	smoke_model.pressure_spill_ref_delta_pa = pressure_spill_ref_delta_pa
	smoke_model.pressure_spill_max_multiplier = pressure_spill_max_multiplier
	smoke_model.thermal_smoke_bridge_ref_kg_m3 = thermal_smoke_bridge_ref_kg_m3
	smoke_model.thermal_smoke_bridge_max_weight = thermal_smoke_bridge_max_weight
	smoke_model.thermal_smoke_bridge_hot_temp_start_c = thermal_smoke_bridge_hot_temp_start_c
	smoke_model.thermal_smoke_bridge_hot_temp_full_c = thermal_smoke_bridge_hot_temp_full_c
	smoke_model.thermal_smoke_bridge_hot_max_weight = thermal_smoke_bridge_hot_max_weight

func reset_simulation(start_ignition_room_id: int = ignition_room_id, ignite_initial_fire: bool = true) -> void:
	if building == null:
		_resolve_building()
	if building == null or not is_ready_for_validation():
		return

	_sync_smoke_model_settings()
	_sync_auxiliary_services()
	gas_exchange_system.reset()
	oxygen_exchange_system.reset()
	hvac_system.reset()
	smoke_generated_total_kg = 0.0
	smoke_vented_total_kg = 0.0
	smoke_deposited_total_kg = 0.0
	suppression_water_applied_l = 0.0
	suppression_cooling_total_kj = 0.0
	_active_suppression_by_room.clear()
	sim_time_s = 0.0
	is_finished = false
	_extinction_countdown = extinction_grace_s
	_prev_open_fracs.clear()
	_graphs_launched = false
	_last_graphs_dir = ""
	_last_graph_generation_ok = false
	glass_failure_system.reset()
	thermal_system.reset_wall_temps()
	if building != null:
		building.reset_detectors()

	for room_id in building.get_rooms().keys():
		var room: RoomModel = building.get_room(room_id)
		_reset_room_state(room)

	combustion_system.bootstrap_building(building)
	if building != null and building.sim_stop_time_s > 0.0:
		sim_duration_limit_s = building.sim_stop_time_s
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
	if building == null or is_finished:
		return

	var dt: float = maxf(0.0, delta * time_scale)
	if dt <= 0.0:
		return

	sim_time_s += dt

	# Límite de tiempo configurado desde el editor.
	if sim_duration_limit_s > 0.0 and sim_time_s >= sim_duration_limit_s:
		if not is_finished:
			is_finished = true
			_on_sim_finished()
		return

	# Pre-computar el estado de flujo de cada abertura interior una sola vez,
	# con las condiciones de sala al inicio de este paso. Esto garantiza que
	# ThermalSystem y OxygenExchangeSystem operen sobre la misma "realidad física"
	# dentro del mismo timestep, evitando que uno de ellos vea estados ya
	# modificados por el otro.
	_opening_flow_cache = _build_opening_flow_cache()

	_step_pool_fires(dt)
	_step_fire(dt)
	_step_oxygen(dt)
	thermal_system.step(building, dt, {
		"outside_open_path_factor_callable": Callable(self, "_outside_open_path_factor_for_room"),
		"opening_flow_cache": _opening_flow_cache
	})
	_step_suppression(dt)
	if glass_auto_break_enabled:
		glass_failure_system.step(dt)
		for broken_idx in glass_failure_system.newly_broken_indices:
			_log_opening_event(broken_idx, "glass_break")
	_step_gas_exchange(dt)
	_step_hvac(dt)
	_step_passive_fuel(dt)
	fire_spread_system.step(dt, Callable(self, "ignite_room"))
	_clamp_rooms(dt)
	_step_detectors(dt)
	_detect_and_log_opening_events()
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
			if auto_finish_on_extinction and not is_finished:
				is_finished = true
				_on_sim_finished()
			elif not auto_finish_on_extinction:
				_extinction_countdown = 0.0
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
	room.fire_dormant_time_s = 0.0
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
	var room: RoomModel = building.get_room(room_id) if building != null else null
	var local_outside_open_factor: float = thermal_system.estimate_room_outside_open_factor(room) if room != null else 0.0
	var outside_open_path_factor: float = _outside_open_path_factor_for_room(room_id)
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
		"fire_retained_smoke_fraction": fire_retained_smoke_fraction,
		"fire_pool_smoke_fraction": fire_pool_smoke_fraction,
		"fire_latent_hrr_cap_min_fraction": fire_latent_hrr_cap_min_fraction,
		"fire_latent_hrr_cap_max_fraction": fire_latent_hrr_cap_max_fraction,
		"fire_latent_co_yield_multiplier": fire_latent_co_yield_multiplier,
		"fire_retained_co_fraction": fire_retained_co_fraction,
		"fire_pool_co_fraction": fire_pool_co_fraction,
		"fire_co_low_quality_yield_multiplier": fire_co_low_quality_yield_multiplier,
		"fire_co_max_effective_fraction": fire_co_max_effective_fraction,
		"fire_subvent_o2_floor": fire_subvent_o2_floor,
		"fire_subvent_temp_start_c": fire_subvent_temp_start_c,
		"fire_subvent_temp_full_c": fire_subvent_temp_full_c,
		"fire_subvent_fill_start_fraction": fire_subvent_fill_start_fraction,
		"fire_subvent_fill_full_fraction": fire_subvent_fill_full_fraction,
		"fire_subvent_pyrolysis_min_fraction": fire_subvent_pyrolysis_min_fraction,
		"fire_subvent_pyrolysis_max_fraction": fire_subvent_pyrolysis_max_fraction,
		"fire_starvation_o2_factor": fire_starvation_o2_factor,
		"fire_o2_full_hrr_open": fire_o2_full_hrr_open,
		"fire_o2_hrr_rise_tau_s": fire_o2_hrr_rise_tau_s,
		"fire_o2_hrr_fall_tau_s": fire_o2_hrr_fall_tau_s,
		"fire_unburned_generation_fraction": fire_unburned_generation_fraction,
		"fire_unburned_capacity_MJ_per_m2": fire_unburned_capacity_MJ_per_m2,
		"fire_unburned_decay_per_s": fire_unburned_decay_per_s,
		"fire_vent_response_temp_start_c": fire_vent_response_temp_start_c,
		"fire_vent_response_temp_full_c": fire_vent_response_temp_full_c,
		"fire_vent_response_rise_tau_s": fire_vent_response_rise_tau_s,
		"fire_vent_response_fall_tau_s": fire_vent_response_fall_tau_s,
		"fire_pool_release_tau_slow_s": fire_pool_release_tau_slow_s,
		"fire_pool_release_tau_fast_s": fire_pool_release_tau_fast_s,
		"fire_pool_release_max_fraction": fire_pool_release_max_fraction,
		"fire_hrr_rise_tau_s": fire_hrr_rise_tau_s,
		"fire_hrr_fall_tau_s": fire_hrr_fall_tau_s,
		"fire_backdraft_pool_threshold_MJ": fire_backdraft_pool_threshold_MJ,
		"fire_backdraft_o2_max": fire_backdraft_o2_max,
		"fire_backdraft_temp_min_c": fire_backdraft_temp_min_c,
		"fire_backdraft_release_boost": fire_backdraft_release_boost,
		"fire_backdraft_hrr_multiplier": fire_backdraft_hrr_multiplier,
		"fire_backdraft_duration_s": fire_backdraft_duration_s,
		"fire_backdraft_cooldown_s": fire_backdraft_cooldown_s,
		"fire_extinction_hrr_kw": fire_extinction_hrr_kw,
		"fire_extinction_delay_s": fire_extinction_delay_s,
		"fire_latent_enabled": fire_latent_enabled,
		"fire_latent_extinction_delay_s": fire_latent_extinction_delay_s,
		"fire_latent_hold_upper_temp_c": fire_latent_hold_upper_temp_c,
		"fire_latent_hold_lower_temp_c": fire_latent_hold_lower_temp_c,
		"fire_latent_min_remaining_fuel_MJ": fire_latent_min_remaining_fuel_MJ,
		"fire_latent_o2_viable_margin": fire_latent_o2_viable_margin,
		"fire_max_active_s": fire_max_active_s,
		"co_base_yield_kg_per_MJ": co_base_yield_kg_per_MJ,
		"co_max_yield_kg_per_MJ": co_max_yield_kg_per_MJ,
		"co2_base_yield_kg_per_MJ": co2_base_yield_kg_per_MJ,
		"co2_min_yield_kg_per_MJ": co2_min_yield_kg_per_MJ,
		"co2_completion_yield_weight": co2_completion_yield_weight,
		"hcn_base_yield_kg_per_MJ": hcn_base_yield_kg_per_MJ,
		"hcn_max_yield_kg_per_MJ": hcn_max_yield_kg_per_MJ,
		"kawagoe_limit_kw": kawagoe_limit_kw,
		"window_open_max": _window_open_max_for_room(room_id),
		"outside_open_factor": local_outside_open_factor,
		"outside_open_path_factor": outside_open_path_factor,
		"fire_o2_independent": fire_o2_independent,
		"fire_fds_extinction_enabled": fire_fds_extinction_enabled,
		"fire_fds_extinction_o2_limit_ambient": fire_fds_extinction_o2_limit_ambient,
		"fire_fds_extinction_ambient_c": fire_fds_extinction_ambient_c,
		"fire_fds_extinction_hot_gas_c": fire_fds_extinction_hot_gas_c,
		"fire_fds_extinction_hot_o2_floor": fire_fds_extinction_hot_o2_floor,
		"fire_fds_extinction_transition_width": fire_fds_extinction_transition_width,
		"fire_fds_extinction_pyrolysis_floor": fire_fds_extinction_pyrolysis_floor,
		"fire_intraroom_spread_enabled": fire_intraroom_spread_enabled,
		"fire_intraroom_view_factor": fire_intraroom_view_factor,
		"fire_intraroom_falloff_m": fire_intraroom_falloff_m
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


func _step_hvac(dt: float) -> void:
	if building == null or hvac_system == null:
		return
	var result: Dictionary = hvac_system.step(building, dt, _build_hvac_hooks())
	smoke_vented_total_kg += float(result.get("smoke_exhausted_kg", 0.0))


func apply_suppression(
	room_id: int,
	duration_s: float,
	flow_lpm: float = 570.0,
	effectiveness: float = 0.75
) -> void:
	if duration_s <= 0.0 or flow_lpm <= 0.0:
		return

	if building == null:
		return

	var room: RoomModel = building.get_room(room_id)
	if room == null:
		return

	_active_suppression_by_room[room_id] = {
		"remaining_s": duration_s,
		"flow_lpm": flow_lpm,
		"effectiveness": clampf(effectiveness, 0.0, 1.0)
	}


func _step_suppression(dt: float) -> void:
	if building == null or _active_suppression_by_room.is_empty() or dt <= 0.0:
		return

	var finished_room_ids: Array = []
	for room_id in _active_suppression_by_room.keys():
		var event: Dictionary = _active_suppression_by_room.get(room_id, {})
		var remaining_s: float = float(event.get("remaining_s", 0.0))
		if remaining_s <= 0.0:
			finished_room_ids.append(room_id)
			continue

		var room: RoomModel = building.get_room(int(room_id))
		var applied_dt: float = minf(dt, remaining_s)
		var flow_lpm: float = maxf(0.0, float(event.get("flow_lpm", 0.0)))
		var effectiveness: float = clampf(float(event.get("effectiveness", 0.0)), 0.0, 1.0)
		var water_l: float = flow_lpm * applied_dt / 60.0 * effectiveness
		if room != null and water_l > 0.0:
			_apply_suppression_to_room(room, water_l, applied_dt)

		remaining_s -= applied_dt
		if remaining_s <= 0.000001:
			finished_room_ids.append(room_id)
		else:
			event["remaining_s"] = remaining_s
			_active_suppression_by_room[room_id] = event

	for room_id in finished_room_ids:
		_active_suppression_by_room.erase(room_id)


func _apply_suppression_to_room(room: RoomModel, water_l: float, dt: float) -> void:
	if room == null or water_l <= 0.0:
		return

	var ambient_c: float = thermal_system.ambient_temp_c()
	var cooling_kj: float = water_l * maxf(0.0, suppression_heat_absorption_kj_per_l)
	suppression_water_applied_l += water_l
	suppression_cooling_total_kj += cooling_kj

	var upper_loss_kj: float = minf(
		room.upper_energy_kj,
		cooling_kj * clampf(suppression_upper_heat_fraction, 0.0, 1.0)
	)
	room.upper_energy_kj = maxf(0.0, room.upper_energy_kj - upper_loss_kj)

	var lower_mass_kg: float = maxf(
		1.0,
		thermal_system.gas_density_kg_m3(room.temp_lower_c) * room.volume_m3()
	)
	var lower_cooling_kj: float = cooling_kj * clampf(suppression_lower_cooling_fraction, 0.0, 1.0)
	var lower_drop_c: float = minf(
		maxf(0.0, room.temp_lower_c - ambient_c),
		lower_cooling_kj / lower_mass_kg
	)
	room.temp_lower_c = maxf(ambient_c, room.temp_lower_c - lower_drop_c)

	var hrr_factor: float = exp(-water_l * maxf(0.0, suppression_hrr_decay_per_l))
	hrr_factor = clampf(hrr_factor, 0.03, 1.0)
	room.hrr_kw *= hrr_factor
	room.hrr_target_kw *= hrr_factor
	room.burned_hrr_kw = room.hrr_kw
	room.retained_unburned_MJ *= lerpf(0.30, 1.0, hrr_factor)
	if room.fire != null:
		room.fire_time_s *= sqrt(hrr_factor)
		room.fire_dormant_time_s = 0.0
		room.fire_low_hrr_time_s = 0.0

	var surface_cool_t: float = clampf(
		water_l / 120.0 * clampf(suppression_surface_cooling_fraction, 0.0, 1.0),
		0.0,
		0.85
	)
	for obj in room.fuel_objects:
		if obj == null:
			continue
		obj.surface_temp_c = lerpf(obj.surface_temp_c, ambient_c, surface_cool_t)
		obj.hrr_kw *= hrr_factor
		if obj.state == 3 and obj.surface_temp_c < obj.ignition_temp_c:
			obj.state = 4

	thermal_system.sync_room_upper_layer(room, dt)
	thermal_system.update_room_layer_150c(room, dt)


func _step_passive_fuel(dt: float) -> void:
	# Siempre actualiza el estado térmico de los combustibles pasivos (necesario para
	# FireSpreadSystem). La auto-ignición solo se dispara si passive_room_autoignite_enabled.
	if building == null:
		return

	var ambient_c: float = thermal_system.ambient_temp_c()
	var auto_ignite_room_ids: Array[int] = []

	for room_id in building.get_rooms().keys():
		var room: RoomModel = building.get_room(room_id)
		if room == null or room.fire != null:
			continue

		var ready: bool = combustion_system.update_passive_room_fuel(
			room,
			dt,
			ambient_c,
			_build_passive_fuel_context(int(room_id))
		)
		if ready and passive_room_autoignite_enabled:
			auto_ignite_room_ids.append(int(room_id))

	for room_id in auto_ignite_room_ids:
		ignite_room(room_id)


func _build_passive_fuel_context(room_id: int) -> Dictionary:
	var room: RoomModel = building.get_room(room_id)
	if room == null:
		return {}

	var max_opening_gas_temp_c: float = room.temp_lower_c
	var max_opening_engagement: float = 0.0
	var max_adjacent_source_hrr_kw: float = 0.0
	# Radiación directa desde sala adyacente con fuego, independiente del flujo convectivo.
	# φ = A_apertura / A_paredes_sala_pasiva × 2 (factor de vista simplificado).
	var max_adjacent_fire_temp_c: float = 0.0
	var max_adjacent_rad_engagement: float = 0.0

	for op in building.get_openings():
		if op == null or op.open_fraction <= 0.0:
			continue
		if op.a == BuildingModel.OUTSIDE_ID or op.b == BuildingModel.OUTSIDE_ID:
			continue
		if op.a != room_id and op.b != room_id:
			continue

		var other_room_id: int = op.b if op.a == room_id else op.a
		var other_room: RoomModel = building.get_room(other_room_id)
		if other_room == null or other_room.fire == null:
			continue

		# Radiación a través del vano: independiente del flujo (la luz viaja sin masa).
		# φ = A_vano / A_paredes × 2  →  fracción del campo radiante que llega al objeto.
		var opening_area_m2: float = op.width_m * op.height_m * op.open_fraction
		var wall_area_m2: float = maxf(
			1.0,
			2.0 * (room.width_m * room.height_m + room.length_m * room.height_m)
		)
		var rad_vf: float = clampf(opening_area_m2 / wall_area_m2 * 2.0, 0.0, 0.50)
		max_adjacent_fire_temp_c = maxf(max_adjacent_fire_temp_c, other_room.temp_upper_c)
		max_adjacent_rad_engagement = maxf(max_adjacent_rad_engagement, rad_vf)

		var flow_state: Dictionary = thermal_system.build_interior_opening_flow_state(
			room,
			other_room,
			op
		)
		if not bool(flow_state.get("active", false)):
			continue

		var hot_room: RoomModel = flow_state.get("hot_room", null)
		var cold_room: RoomModel = flow_state.get("cold_room", null)
		if hot_room != other_room or cold_room != room:
			continue

		max_opening_gas_temp_c = maxf(
			max_opening_gas_temp_c,
			float(flow_state.get("source_temp_c", other_room.temp_upper_c))
		)
		max_opening_engagement = maxf(
			max_opening_engagement,
			clampf(float(flow_state.get("engagement", 0.0)), 0.0, 1.0)
		)
		max_adjacent_source_hrr_kw = maxf(max_adjacent_source_hrr_kw, other_room.hrr_kw)

	return {
		"opening_gas_temp_c": max_opening_gas_temp_c,
		"opening_engagement": max_opening_engagement,
		"adjacent_source_hrr_kw": max_adjacent_source_hrr_kw,
		"adjacent_fire_temp_c": max_adjacent_fire_temp_c,
		"adjacent_rad_engagement": max_adjacent_rad_engagement
	}


# ============================================================
# FUEGO DE CHARCO (POOL FIRE)
# ============================================================
## Expande el charco de combustible líquido y actualiza el HRR máximo del fuego.
## Solo afecta a FuelObjectModel con pool_spread_rate_m2_s > 0.
## El área del charco crece en pool_spread_rate_m2_s·dt hasta alcanzar el límite
## (pool_max_area_m2 o el área del suelo de la sala).
## La potencia máxima del fuego se ajusta: fire.max_hrr_kw = pool_hrr_kw_m2 * area.
func _step_pool_fires(dt: float) -> void:
	if not pool_fire_enabled or building == null:
		return
	for room_id in building.get_rooms().keys():
		var room: RoomModel = building.get_room(room_id)
		if room == null or room.fire == null:
			continue
		var pool_hrr_kw: float = 0.0
		for obj_raw in room.fuel_objects:
			var obj: FuelObjectModel = obj_raw as FuelObjectModel
			if obj == null or obj.pool_spread_rate_m2_s <= 0.0:
				continue
			var max_area: float = obj.pool_max_area_m2 if obj.pool_max_area_m2 > 0.0 else room.floor_area_m2()
			obj.pool_area_m2 = minf(obj.pool_area_m2 + obj.pool_spread_rate_m2_s * dt, max_area)
			pool_hrr_kw += obj.pool_hrr_kw_m2 * obj.pool_area_m2
		if pool_hrr_kw > 0.0:
			# Actualizar el techo de HRR del fuego para reflejar el área actual del charco.
			room.fire.max_hrr_kw = maxf(room.fire.max_hrr_kw, pool_hrr_kw)


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


func _outside_open_path_factor_for_room(room_id: int) -> float:
	if building == null or not fire_remote_vent_path_enabled:
		return 0.0
	if thermal_system == null or building.get_room(room_id) == null:
		return 0.0

	var best_path_by_room: Dictionary = {}
	var depth_by_room: Dictionary = {}
	var queue: Array[int] = []
	best_path_by_room[room_id] = 1.0
	depth_by_room[room_id] = 0
	queue.append(room_id)

	var best_factor: float = 0.0
	while not queue.is_empty():
		var current_id: int = int(queue.pop_front())
		var current_room: RoomModel = building.get_room(current_id)
		var current_path_factor: float = float(best_path_by_room.get(current_id, 0.0))
		var current_depth: int = int(depth_by_room.get(current_id, 0))

		if current_room != null:
			best_factor = maxf(
				best_factor,
				thermal_system.estimate_room_outside_open_factor(current_room) * current_path_factor
			)

		if current_depth >= fire_remote_vent_path_max_doors:
			continue

		for op in building.get_connected_openings(current_id):
			if op == null or op.open_fraction <= 0.0:
				continue
			if op.type != OpeningModel.Type.DOOR:
				continue
			if op.a == BuildingModel.OUTSIDE_ID or op.b == BuildingModel.OUTSIDE_ID:
				continue

			var next_id: int = op.b if op.a == current_id else op.a
			if next_id == BuildingModel.OUTSIDE_ID or building.get_room(next_id) == null:
				continue

			var area_factor: float = clampf(
				(op.width_m * op.height_m) / maxf(0.1, 0.8 * 2.0),
				0.35,
				1.25
			)
			var next_path_factor: float = current_path_factor \
					* clampf(op.open_fraction, 0.0, 1.0) \
					* clampf(fire_remote_vent_path_decay_per_door, 0.0, 1.0) \
					* area_factor
			next_path_factor = clampf(next_path_factor, 0.0, 1.0)
			if next_path_factor < fire_remote_vent_path_min_signal:
				continue
			if next_path_factor <= float(best_path_by_room.get(next_id, -1.0)):
				continue

			best_path_by_room[next_id] = next_path_factor
			depth_by_room[next_id] = current_depth + 1
			queue.append(next_id)

	return clampf(best_factor, 0.0, 1.0)

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
	var effective_layer_m: float = smoke_model.get_effective_smoke_spill_layer_height_m(room)
	var layer_low_enough: bool = effective_layer_m <= flashover_layer_m
	var effective_thermal_layer_m: float = thermal_system.effective_hot_layer_height_m(room)
	var thermal_layer_low_enough: bool = effective_thermal_layer_m <= flashover_layer_m + 0.45
	var head_temp_c: float = thermal_system.estimate_temperature_at_height_m(room, flashover_head_height_m)
	var head_hot_enough: bool = head_temp_c >= flashover_head_temp_c
	var breathing_temp_c: float = thermal_system.estimate_temperature_at_height_m(
		room,
		flashover_breathing_height_m
	)
	var breathing_hot_enough: bool = breathing_temp_c >= flashover_breathing_temp_c
	var layer_150_low_enough: bool = room.layer_150c_m <= flashover_head_height_m
	var tenability_lost: bool = head_hot_enough or layer_150_low_enough

	# Criterio más cercano a la referencia residencial local:
	# no basta con T_upper alta; exigimos además un nivel térmico muy severo
	# a altura de respiración (0.9 m) y un descenso real de la capa.
	var direct_vent_open: bool = thermal_system.estimate_room_outside_open_factor(room) > 0.05
	var radiant_feedback_flashover: bool = direct_vent_open \
			and room.temp_upper_c >= flashover_temp_c + 100.0 \
			and enough_hrr \
			and thermal_layer_low_enough \
			and (head_hot_enough or effective_thermal_layer_m <= flashover_head_height_m) \
			and room.o2 >= room.fire.o2_min_for_flame

	if (hot_enough \
			and enough_hrr \
			and layer_low_enough \
			and breathing_hot_enough \
			and (not flashover_require_tenability_loss or tenability_lost)) \
			or radiant_feedback_flashover:
		room.flashover_triggered = true
		room.flashover_time_s = sim_time_s
		# Escalar la ganancia secundaria en proporción al tamaño de la habitación.
		# Evita que recintos con menor capacidad térmica reciban la misma
		# secondary_hrr_gain que la habitación de referencia (fire_max_hrr_kw).
		var gain: float = room.fire.secondary_hrr_gain_kw * (room.fire.max_hrr_kw / fire_max_hrr_kw)
		room.fire.max_hrr_kw += gain
		room.hrr_kw *= room.fire.flashover_hrr_multiplier
		combustion_system.generalize_room_combustion_after_flashover(room)
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

func _clamp_rooms(dt: float) -> void:
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

		if room.temp_upper_c > max_upper_temp_c:
			room.temp_upper_raw_c = maxf(room.temp_upper_raw_c, room.temp_upper_c)
			room.temp_upper_clamped = true
		room.temp_upper_c = minf(room.temp_upper_c, max_upper_temp_c)
		if room.temp_upper_c < room.temp_lower_c:
			room.temp_lower_c = room.temp_upper_c
		if thermal_system.is_room_quiescent(room):
			room.upper_gas_kg = 0.0
			room.upper_energy_kj = 0.0
			room.temp_upper_c = room.temp_lower_c
			room.temp_upper_raw_c = room.temp_upper_c
			room.temp_upper_clamped = false
			room.upper_radiative_loss_kw = 0.0
			thermal_system.reset_thermal_layer(room)
			room.layer_150c_m = room.height_m
		else:
			room.temp_upper_raw_c = maxf(room.temp_upper_raw_c, room.temp_upper_c)
			room.temp_upper_clamped = room.temp_upper_clamped or room.temp_upper_raw_c > max_upper_temp_c
			room.upper_energy_kj = room.upper_gas_kg * maxf(0.0, room.temp_upper_c - thermal_system.ambient_temp_c())
			thermal_system.update_temperature_cap_telemetry(room, dt)

		room.hrr_kw = maxf(0.0, room.hrr_kw)
		room.burned_hrr_kw = room.hrr_kw
		room.pyrolysis_kw = maxf(0.0, room.pyrolysis_kw)
		room.unburned_generation_kw = maxf(0.0, room.unburned_generation_kw)
		room.flame_hrr_target_kw = maxf(0.0, room.flame_hrr_target_kw)
		room.smolder_hrr_target_kw = maxf(0.0, room.smolder_hrr_target_kw)
		room.pool_release_hrr_target_kw = maxf(0.0, room.pool_release_hrr_target_kw)
		room.smoke_prod_kg_s = maxf(0.0, room.smoke_prod_kg_s)
		room.smoke_kg = maxf(0.0, room.smoke_kg)
		room.co_kg = maxf(0.0, room.co_kg)
		room.co_upper_kg = clampf(room.co_upper_kg, 0.0, room.co_kg)
		room.co2_kg = maxf(0.0, room.co2_kg)
		room.hcn_kg = maxf(0.0, room.hcn_kg)
		room.fed = maxf(0.0, room.fed)
		room.svv_pct = clampf(room.svv_pct, 0.0, 100.0)
		room.svv_worst_pct = minf(clampf(room.svv_worst_pct, 0.0, 100.0), room.svv_pct)

# ============================================================
# ESTADO AGREGADO
# ============================================================

func get_state() -> Dictionary:
	if state_builder == null:
		return {}
	return state_builder.build_state(_build_state_context())


func is_ready_for_validation() -> bool:
	return smoke_model != null \
			and combustion_system != null \
			and gas_exchange_system != null \
			and oxygen_exchange_system != null \
			and log_writer != null \
			and state_builder != null \
			and thermal_system != null \
			and fire_spread_system != null \
			and glass_failure_system != null \
			and hvac_system != null


func are_graphs_launched() -> bool:
	return _graphs_launched


func get_last_graphs_dir() -> String:
	return _last_graphs_dir


func was_last_graph_generation_ok() -> bool:
	return _last_graph_generation_ok


func stop_and_generate_graphs(details: String = "manual_stop_button", graphs_root: String = "") -> bool:
	if sim_time_s <= 0.0 or _graphs_launched:
		return false

	_finish_and_launch_graphs(details, graphs_root, true)
	return true

# ============================================================
# EVENTOS Y GENERACIÓN DE GRÁFICAS
# ============================================================

## Detecta cambios en open_fraction de puertas y ventanas y los registra como
## eventos en el log. Se llama cada step. Los eventos de rotura de cristal ya
## son registrados directamente en step() antes de llamar a esta función.
func _detect_and_log_opening_events() -> void:
	if building == null:
		return
	var openings: Array = building.get_openings()
	for i in range(openings.size()):
		var op: OpeningModel = openings[i]
		# Primera vez que vemos esta apertura: solo guardamos el estado base.
		if not _prev_open_fracs.has(i):
			_prev_open_fracs[i] = op.open_fraction
			continue
		var prev: float = float(_prev_open_fracs[i])
		var curr: float = op.open_fraction
		# Cambio significativo (>5 % de apertura total)
		if abs(curr - prev) > 0.05:
			# Los rotura de cristal ya están registradas; solo registrar el resto.
			var is_new_glass_break: bool = glass_failure_system.newly_broken_indices.has(i)
			if not is_new_glass_break:
				var opened: bool = curr > prev
				var etype: String
				if op.type == OpeningModel.Type.DOOR:
					etype = "door_open" if opened else "door_close"
				else:
					etype = "window_open" if opened else "window_close"
				_log_opening_event(i, etype)
		_prev_open_fracs[i] = curr


func _log_opening_event(opening_idx: int, event_type: String) -> void:
	var op: OpeningModel = building.get_opening_at(opening_idx)
	if op == null:
		return
	var type_str: String = "door" if op.type == OpeningModel.Type.DOOR else "window"
	var details: String = "opening=%d kind=%s room_a=%d room_b=%d frac=%.2f" % [
		opening_idx, type_str, op.a, op.b, op.open_fraction
	]
	log_writer.append_event(sim_time_s, event_type, details)


# ============================================================
# DETECTORES AUTOMÁTICOS
# ============================================================
## Comprueba el estado de cada detector definido en la plantilla JSON y
## registra el evento "detector_triggered" la primera vez que se activa.
## Tipos soportados:
##   "smoke" — threshold en kg/m³ (humo por volumen de sala)
##   "heat"  — threshold en °C (capa superior)
##   "co"    — threshold en ppm (CO en la sala)
func _step_detectors(_dt: float) -> void:
	if not detectors_enabled or building == null:
		return
	for det in building.detectors:
		if bool(det.get("triggered", false)):
			continue
		var room_id: int = int(det.get("room_id", -1))
		var room: RoomModel = building.get_room(room_id)
		if room == null:
			continue
		var det_type: String = String(det.get("type", "smoke"))
		var threshold: float = float(det.get("threshold", 0.025))
		var triggered: bool = false
		if det_type == "smoke":
			triggered = (room.smoke_kg / maxf(0.1, room.volume_m3())) >= threshold
		elif det_type == "heat":
			var measured_temp_c: float = room.temp_upper_c
			if ceiling_jet_enabled and room.hrr_kw > 0.0:
				measured_temp_c = maxf(measured_temp_c, _ceiling_jet_temp_c(room, det))
			triggered = measured_temp_c >= threshold
		elif det_type == "co":
			triggered = thermal_system.compute_co_ppm(room) >= threshold
		if triggered:
			det["triggered"] = true
			det["triggered_at_s"] = sim_time_s
			log_writer.append_event(
				sim_time_s,
				"detector_triggered",
				"id=%s type=%s room=%d threshold=%.3g" % [
					String(det.get("id", "?")), det_type, room_id, threshold
				]
			)


## Temperatura del jet de techo en la posición del detector según Alpert (1972).
## HRR: potencia del fuego en kW. H: altura suelo-techo en m.
## r: distancia horizontal desde el eje del penacho al detector en m.
## Fórmulas: ΔT = 16.9·Q^(2/3) / H^(5/3)  para r/H ≤ 0.18
##          ΔT = 5.38·(Q/r)^(2/3) / H      para r/H > 0.18
func _ceiling_jet_temp_c(room: RoomModel, det: Dictionary) -> float:
	var hrr: float = maxf(1.0, room.hrr_kw)
	var H: float = maxf(0.5, room.height_m)
	# Posición del foco dominante (objeto con mayor hrr_kw, o centro de sala)
	var fire_x: float = room.width_m * 0.5
	var fire_y: float = room.length_m * 0.5
	var max_obj_hrr: float = 0.0
	for obj in room.fuel_objects:
		if (obj as FuelObjectModel).hrr_kw > max_obj_hrr:
			max_obj_hrr = (obj as FuelObjectModel).hrr_kw
			fire_x = (obj as FuelObjectModel).position_m.x
			fire_y = (obj as FuelObjectModel).position_m.y
	# Posición del detector (por defecto: centro de la sala)
	var det_x: float = float(det.get("x_m", room.width_m * 0.5))
	var det_y: float = float(det.get("y_m", room.length_m * 0.5))
	var r: float = maxf(0.01, sqrt((det_x - fire_x) * (det_x - fire_x) + (det_y - fire_y) * (det_y - fire_y)))
	var delta_t: float
	if r / H <= 0.18:
		delta_t = 16.9 * pow(hrr, 2.0 / 3.0) / pow(H, 5.0 / 3.0)
	else:
		delta_t = 5.38 * pow(hrr / r, 2.0 / 3.0) / H
	return thermal_system.ambient_temp_c() + delta_t


## Llamado cuando la simulación termina naturalmente O cuando el usuario para el
## juego (a través de _exit_tree). Escribe sim_end y lanza Python.
func _on_sim_finished() -> void:
	_finish_and_launch_graphs("")


func _finish_and_launch_graphs(details: String, graphs_root: String = "", wait_for_finish: bool = false) -> void:
	if _graphs_launched or sim_time_s <= 0.0:
		return

	is_finished = true
	_force_log_final_snapshot()
	_graphs_launched = true
	_last_graphs_dir = ""
	_last_graph_generation_ok = false

	if details.is_empty():
		log_writer.append_event(sim_time_s, "sim_end", "")
	else:
		log_writer.append_event(sim_time_s, "sim_end", details)
	if _should_launch_graphs():
		_launch_graph_generator(graphs_root, wait_for_finish)


func _force_log_final_snapshot() -> void:
	_sync_auxiliary_services()
	log_writer.append_snapshot_now(sim_time_s, get_state())


func _launch_graph_generator(graphs_root: String = "", wait_for_finish: bool = false) -> void:
	var script_path: String = ProjectSettings.globalize_path("res://scripts/generate_fire_graphs.py")
	var latest_path: String = ProjectSettings.globalize_path("user://latest_graphs_dir.txt")
	var args: PackedStringArray = PackedStringArray([script_path, "--latest-file", latest_path, "--copy-log"])
	if enable_csv_log:
		var csv_path: String = log_writer.resolve_csv_file_path()
		if csv_path.strip_edges() != "":
			args.append("--csv")
			args.append(csv_path)
			args.append("--copy-csv")
	if graphs_root.strip_edges() != "":
		args.append("--out-root")
		args.append(graphs_root)

	var pid: int = -1
	var exit_code: int = -1
	var output: Array = []
	# En Windows, "python" puede no estar en el PATH de Godot.
	# cmd.exe /c busca en el PATH del sistema, igual que un terminal normal.
	if wait_for_finish:
		if OS.get_name() == "Windows":
			var win_args: PackedStringArray = PackedStringArray(["/c", "python"])
			win_args.append_array(args)
			exit_code = OS.execute("cmd.exe", win_args, output, true)
		else:
			exit_code = OS.execute("python3", args, output, true)
			if exit_code != 0:
				exit_code = OS.execute("python", args, output, true)

		_last_graph_generation_ok = exit_code == 0
		_last_graphs_dir = _read_latest_graphs_dir(latest_path)
		if _last_graph_generation_ok:
			print("[SimulationEngine] Graficas generadas en: %s" % _last_graphs_dir)
		else:
			push_warning("[SimulationEngine] No se pudieron generar graficas. Ejecuta: python scripts/generate_fire_graphs.py")
		return

	if OS.get_name() == "Windows":
		var win_process_args: PackedStringArray = PackedStringArray(["/c", "python"])
		win_process_args.append_array(args)
		pid = OS.create_process("cmd.exe", win_process_args)
	else:
		pid = OS.create_process("python3", args)
		if pid <= 0:
			pid = OS.create_process("python", args)
	if pid > 0:
		print("[SimulationEngine] Generando gráficas (PID %d)..." % pid)
	else:
		push_warning("[SimulationEngine] No se pudo lanzar Python. Ejecuta: python scripts/generate_fire_graphs.py")


func _read_latest_graphs_dir(latest_path: String) -> String:
	if not FileAccess.file_exists(latest_path):
		return ""
	var file := FileAccess.open(latest_path, FileAccess.READ)
	if file == null:
		return ""
	var value: String = file.get_as_text().strip_edges()
	file.close()
	return value


func _should_launch_graphs() -> bool:
	for arg in OS.get_cmdline_user_args():
		var arg_str: String = String(arg)
		if arg_str.begins_with("--validation-case"):
			return false
	return true


func _is_validation_mode() -> bool:
	for arg in OS.get_cmdline_user_args():
		var arg_str: String = String(arg)
		if arg_str == "--validation-case" or arg_str.begins_with("--validation-case="):
			return true
	return false


## Godot llama _exit_tree cuando se detiene el juego (botón Stop del editor
## o cierre de ventana). Garantiza que las gráficas se generen aunque la
## simulación no haya terminado por extinción natural del fuego.
func _exit_tree() -> void:
	if _is_validation_mode():
		return

	_finish_and_launch_graphs("forced")

# ============================================================
# REGISTRO DE VALORES
# ============================================================

func _maybe_log_state() -> void:
	_sync_auxiliary_services()
	if not log_writer.should_log(sim_time_s):
		return

	log_writer.append_snapshot(sim_time_s, get_state())

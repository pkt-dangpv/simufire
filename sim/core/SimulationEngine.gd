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
const ZoneFireSolverScript = preload("res://sim/core/ZoneFireSolver.gd")
const LayerInterfaceModel = preload("res://sim/core/LayerInterfaceModel.gd")
const Phase3ZoneMassSystemScript = preload("res://sim/core/Phase3ZoneMassSystem.gd")

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
# SF-R6: ZoneFireSolver — coordinador de flujos masa/energía/especies entre zonas.
var zone_fire_solver = ZoneFireSolverScript.new()
var phase3_zone_mass_system = Phase3ZoneMassSystemScript.new()

# Cache de estados de flujo pre-computados para todas las aberturas interiores.
# Se recalcula una vez al comienzo de cada paso de tiempo y se comparte entre
# ThermalSystem y OxygenExchangeSystem para garantizar consistencia física.
var _opening_flow_cache: Dictionary = {}
var _phase3_zone_diag_start: Dictionary = {}
var _phase3_zone_diag_checkpoint: Dictionary = {}
var _phase3_zone_diag_step: Dictionary = {}

const o2_nominal: float = 0.209

# ============================================================
# TIEMPO
# ============================================================

@export var time_scale: float = 1.0
## SF-AUD-019: dt fijo para barrido de sensibilidad numerica. Cuando > 0 sobreescribe
## delta*time_scale y la simulacion avanza exactamente este valor por frame.
@export var sim_fixed_dt: float = 0.0
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
var _graph_gen_pid: int = -1
var _html_dashboard_pid: int = -1
var _graph_gen_latest_path: String = ""
var _exit_graphs_suppressed: bool = false
var _python_available: bool = true
var _python_checked: bool = false
var _python_command: String = ""
var _python_prefix_args: PackedStringArray = PackedStringArray()
# W-01: picos por sala para el resumen técnico post-simulación.
var _room_peak_hrr: Dictionary = {}   # room_id (int) → float
var _room_peak_temp: Dictionary = {}  # room_id (int) → float
var _room_peak_co_upper: Dictionary = {}
var _room_peak_hcn_upper: Dictionary = {}
var _room_min_o2: Dictionary = {}
var _room_min_visibility: Dictionary = {}
var _room_peak_fed: Dictionary = {}
var _room_min_svv: Dictionary = {}
var _room_peak_hrr_time: Dictionary = {}
var _room_peak_temp_time: Dictionary = {}
var _room_peak_co_upper_time: Dictionary = {}
var _room_peak_hcn_upper_time: Dictionary = {}
var _room_min_o2_time: Dictionary = {}
var _room_min_visibility_time: Dictionary = {}
var _room_peak_fed_time: Dictionary = {}
var _room_min_svv_time: Dictionary = {}
var _last_technical_summary: Dictionary = {}
# W-01: emitido cuando la simulación finaliza y los archivos de exportación
# han sido escritos. Main.gd lo recibe para capturar la pantalla 3D.
signal export_screenshot_requested(output_dir: String)
signal technical_summary_ready(summary: Dictionary, output_dir: String)
# SF-AUD-029: targets radiantes pasivos
var _targets: Array = []

# ============================================================
# CONTRATO DE MIGRACION TWO-ZONE
# ============================================================
# R2-1 (2026-06-11): TwoZoneV1 es ahora el modo default.
# Legacy disponible como opt-in con two_zone_solver_enabled=false.
@export var two_zone_solver_enabled: bool = true
@export var two_zone_opening_flow_enabled: bool = true

# ============================================================
# ROTURA DE CRISTAL (SF-AUD-011)
# ============================================================
# Modo de rotura automatica:
#   DISABLED(0)      — nunca se rompe (por defecto; ventanas solo cambian manualmente)
#   DETERMINISTIC(1) — se rompe exactamente cuando T_upper >= glass_break_temp_c
#   PROBABILISTIC(2) — hazard rate: probabilidad crece con temperatura y exposicion
#                      sin umbral fijo, modela variabilidad real de cristales residenciales
enum GlassBreakMode { DISABLED = 0, DETERMINISTIC = 1, PROBABILISTIC = 2 }
@export var glass_break_mode: GlassBreakMode = GlassBreakMode.DISABLED
# Temperatura de referencia de rotura para modo DETERMINISTIC y referencia hazard en PROBABILISTIC.
@export var glass_break_temp_c: float = 250.0
# Dispersion aleatoria de la temperatura de rotura en modo DETERMINISTIC (± rango uniforme).
@export var glass_break_temp_spread_c: float = 80.0
# Velocidad a la que sube open_fraction tras la rotura (fraccion/segundo).
@export var glass_open_rate_per_s: float = 0.15
# open_fraction maxima al romperse el cristal (1.0 = apertura completa).
@export var glass_max_open_fraction: float = 0.85
# --- Parametros modo PROBABILISTIC (hazard rate) ---
# Temperatura a partir de la cual comienza a acumularse tiempo de exposicion.
@export var glass_break_exposure_start_temp_c: float = 100.0
# Tasa de hazard base (1/s) cuando T_upper = glass_break_temp_c y exposicion = 0.
# Con 0.008/s la vida media a T_ref es ~87 s; a T+100C sube mucho mas rapido.
@export var glass_break_hazard_base_per_s: float = 0.008
# Exponente de temperatura en la tasa de hazard: lambda ∝ f_temp^exp.
# exp=2 → hazard se cuadruplica al doblar la temperatura normalizada (cuadratico).
@export var glass_break_hazard_temp_exp: float = 2.0
# Constante de tiempo de exposicion (s): la tasa de hazard se duplica tras este tiempo.
# Con 120 s: en 2 min a temperatura critica la probabilidad de rotura se ha duplicado.
@export var glass_break_hazard_exposure_tau_s: float = 120.0

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
# SF-CBAL GLOBAL: BALANCE DE CARBONO A NIVEL DE EDIFICIO
# ============================================================
## Error global = inventario + pendientes + productos no modelados + sumideros
##                 − C_inicial − C_quemado.
## Positivo = creación espuria; negativo = pérdida numérica (clamp u otro).
## El transporte interno entre salas es invariante (se cancela en la suma).
var _cbal_initialized: bool = false
var _cbal_c_initial_kg: float = 0.0
var global_carbon_error_kg: float = 0.0
var global_carbon_preclamp_excess_kg: float = 0.0
var global_carbon_postclamp_excess_kg: float = 0.0
var global_carbon_transport_residual_kg: float = 0.0
# SF-CBAL: carbono acumulado que salió por exhaust del HVAC (kg C).
var _cbal_hvac_c_exhausted_kg: float = 0.0
# Guardrail: divergencia persistente entre capa termica e interfaz canonica de flujo.
var _layer_interface_divergence_s: Dictionary = {}
var _layer_interface_warning_rooms: Dictionary = {}

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
## M2: selector unico de la muestra de O2 usada por la combustion.
## `legacy` conserva flags/blend historicos; los otros modos activan O2 pre-HRR.
@export_enum("legacy", "upper", "lower", "interface") var fire_o2_mode: String = "legacy"
## Cuando true, la decisión de extincion/HRR usa `room.o2_upper` (capa caliente)
## en lugar de `room.o2` (promedio), con el umbral separado `fire_o2_upper_min_for_flame`.
## Compatibilidad legacy: ignorado cuando fire_o2_mode es explicito.
@export var fire_o2_upper_for_flame: bool = false
## Blend [0,1] para capear el HRR por O2 de capa superior.
## 0.0 = sin cambio (usa room.o2); 1.0 = effective_o2 = min(room.o2, room.o2_upper).
## Opt-in: activar por caso cuando la capa caliente ocupa la zona de combustión.
## Phase 4A RECHAZADO (2026-06): cualquier valor >0.03 rompe cfast_t35x_hot_layer_m checks.
## La brecha estructural one-zone no se cierra con blending. Permanece 0.0 (no-op).
## No activar sin arquitectura two-zone completa (Fase 2).
@export var fire_o2_upper_hrr_blend: float = 0.0
## Umbral de O2 en capa superior por debajo del cual la llama se extingue.
## Calibrado para upper-zone: ~0.07-0.08 (CFAST ULO2 en extincion ~8.5 %).
@export var fire_o2_upper_min_for_flame: float = 0.075
## Phase 2C: cuando true, el fuego usa room.o2_lower como referencia de O2.
## Activa el feed de zona baja via HVAC low-supply/high-return (benchmark CFAST GAP-9).
## Requiere phase2h_o2_doorway_two_zone_enabled=true para que HVAC reponga o2_lower.
## Compatibilidad legacy: ignorado cuando fire_o2_mode es explicito.
@export var fire_o2_lower_for_flame: bool = false
@export var fire_o2_consumption_kg_per_MJ: float = 0.076  # Regla de Thornton: 1/13.1 MJ/kgO2
## Phase 5 M1: routing canónico de consumo de O₂.
## Cuando true, OxygenExchangeSystem consume de o2_lower cuando fire_o2_mode_used="plume_lower".
## Phase 8 audit: activación global rompe throttle en salas abiertas con auto-select "plume_lower"
## (canonical_plume_lower activo → o2_upper se mantiene alto → fuego no throttlea → crash O2 inferior).
## Activar solo per-caso con fire_o2_mode="plume_lower" explícito vía engine_overrides.
@export var fire_o2_canonical_enabled: bool = false
## Phase 5 M4: ILV upper-O2 throttle guard.
## Cuando true, en modo two-zone (plume_lower/plume_blend), si room.o2_upper cae por debajo
## de fire_o2_upper_throttle_critical, el throttle de HRR usa min(room.o2, room.o2_upper) en
## lugar de o2_lower. Impide que HRR permanezca alto mientras la zona superior se agota.
## Default false — activar per-caso o como preparación de Phase 3+. No afecta salas selladas
## (que usan plume_lower_mode de OxygenExchangeSystem, no el two-zone path automático).
@export var fire_o2_upper_throttle_enabled: bool = false
@export var fire_o2_upper_throttle_critical: float = 0.10
## M5: guard post-backdraft — corta HRR/pool cuando el backdraft terminó, el pool está
## agotado y no existe llama ni latencia viable. Default false. Activar per-caso.
@export var fire_post_bd_hrr_cut_enabled: bool = false
## SF-D2: consumo estequiométrico de O2 por combustión (Thornton, default-off).
## Cuando activo: CombustionSystem descuenta o2_consumed_kg = hrr_kw*dt/1000 * o2_consumption_kg_per_MJ
## de o2_upper por paso. Activa o2_consumed_kg_step / o2_consumed_kg_total en CSV.
## Activar per-caso o globalmente solo cuando se quiera auditar/cerrar balance O2.
@export var fire_o2_stoich_consumption_enabled: bool = false
## Phase 5 M2: tracer conservado de masa O2 en zona superior.
## Phase 8 audit: activación global interactúa incorrectamente con plume_lower_mode.
## La dilución del tracker (upper_air_mass 1.2 kg/m³ vs upper_gas_kg en caliente) + delta_entr
## fija o2_upper cerca de ambient en salas selladas → room.o2 stuck at 0.209.
## Activar solo per-caso con engine_overrides. Consistencia con canonical Part A: ver canonical_o2_upper_updated.
@export var fire_o2_mass_tracking_enabled: bool = false
## Hotfix exterior smoothing: tau de suavizado exponencial para open_fraction de aperturas exteriores.
## Evita saltos instantáneos al abrir/cerrar ventanas/puertas ext. 0.0 = sin suavizado (inmediato).
@export var exterior_opening_smooth_tau_s: float = 2.0
## Phase 5 M3: contraflujo térmico bidireccional por puertas. Default false = no-op exacto.
@export var doorway_thermal_counterflow_enabled: bool = false
@export var doorway_thermal_counterflow_gain: float = 1.0
## Phase 5 M3b: fracción del flujo másico superior que retorna como aire fresco (zona inferior). 0.0 = no-op.
@export var doorway_thermal_counterflow_o2_return_fraction: float = 0.0
## Phase 6: intercambio canónico dos zonas por puertas (masa + entalpía + O₂). Default false = no-op.
@export var canonical_doorway_exchange_enabled: bool = false
## Phase 6: fracción del flujo Bernoulli inferior usada para flujo de zona inferior. 1.0 = completo.
@export var canonical_doorway_lower_flow_frac: float = 1.0
## Phase 2G: multiplicador del flujo inferior canónico para compensar subestimación Bernoulli vs CFAST PDE.
## 1.0 = no-op exacto. Activar sólo per-caso en engine_overrides.
@export var canonical_doorway_lower_inflow_multiplier: float = 1.0
## Phase 3A: ODE de sobrepresión termogénica. false = no-op (pressure_pa_therm siempre 0).
@export var phase3a_pressure_ode_enabled: bool = false
## Phase 3A: coeficiente de disipación [1/s]. 24000 → dp_ss≈0.1 Pa para 300kW/50m³.
@export var phase3a_pressure_vent_loss_coeff: float = 24000.0
## Phase 3A: cap de sobrepresión [Pa]. 500 Pa >> valor real (~0.1 Pa).
@export var phase3a_pressure_max_pa: float = 500.0
## Phase 3B: corrección del plano neutro con dp_fire. false = sin corrección.
@export var phase3b_neutral_plane_dp_correction: bool = false
## Phase 3D: fracción del inflow inferior enviada directamente a hot.upper. 0.0 = no-op.
@export var canonical_doorway_plume_direct_upper_frac: float = 0.0
## Phase 3+ F1a: el lower return flow del intercambio canónico mueve masa física
## lower_gas_kg (cold→hot) además de energía/O₂. Requiere two_zone_solver_enabled.
## Default false = no-op exacto (legacy conserva el agujero de masa que la
## proyección EOS reconstruye). Experimental — activar solo per-caso.
@export var phase3_conservative_lower_return_enabled: bool = false
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
# Phase 2: CO vent-limited cuando o2_upper < threshold (Beyler 1986, NIST TN 1603).
# Fuegos subventilados con deplección de O2 en zona superior generan CO masivamente.
# Activo únicamente cuando o2_upper baja del umbral; no afecta casos bien ventilados.
@export var fire_co_vent_limited_o2_threshold: float = 0.12
@export var fire_co_vent_limited_multiplier: float = 1.0
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
# Yield forzado constante (≥0): cuando se establece, sustituye el cálculo adaptativo
# de CO. Útil para comparación con CFAST/FDS que usan yields fijos por kg de combustible.
# Valor -1.0 (por defecto) desactiva el forzado.
@export var fire_co_yield_force_kg_per_MJ: float = -1.0
# Tasa de incremento de CO con el equivalence ratio φ (curva exponencial).
# y_CO = y_CO_base × exp(fire_co_phi_rate × (φ - 1)) para φ > 1.
# k=2.0 → ~50× a φ=3, coincidiendo con datos de Beyler (1986) y NIST TN 1603
# para madera residencial en condiciones subventiladas.
@export var fire_co_phi_rate: float = 2.0
# phi efectiva para smoldering (combustion sin llama). Valores tipicos: 3-5.
# phi=4 reproduce la alta emision de CO de brasas/smoldering (ISO 19706).
@export var fire_smolder_phi: float = 4.0
# R2-6: CO afterburning inhibition — activado en modo two-zone.
# Cuando o2_upper < threshold, el CO generado no se oxida a CO2 (Gottuk & Roby, SFPE §3.4).
# Sin override explícito, el modelo automático activa el boost de Gottuk/Lattimer.
# fire_co_afterburn_o2_threshold: O2 molar fraction donde comienza la inhibición.
# fire_co_afterburn_max_boost: factor máximo de boost del yield CO (a o2_upper→0).
@export var fire_co_afterburn_o2_threshold: float = 0.15
@export var fire_co_afterburn_max_boost: float = 30.0

# Rendimiento de CO2 (kg/MJ)
# ISO 19706 — madera (combustible residencial dominante):
#   Combustión ventilada: 1.33 kg/kg ÷ 16 MJ/kg = 0.0831 kg/MJ
#   Combustión en déficit: 0.95 kg/kg ÷ 16 MJ/kg = 0.0594 kg/MJ
@export var co2_base_yield_kg_per_MJ: float = 0.0831
@export var co2_min_yield_kg_per_MJ: float = 0.0594
# Tasa de decaimiento de CO2 con phi. co2_phi_decay_rate=2.5 → CO2 llega al
# minimo cuando phi=3.5 (Pitts, NIST TN 1603 datos de especies underventilated).
@export var co2_phi_decay_rate: float = 2.5

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
# SF-AUD-017: parámetros de vapor de agua generado por supresión
# Fracción del agua aplicada que efectivamente se evapora (el resto escurre como runoff).
# 0.27 → energía latente ≈ 0.27×2591 + 0.73×335 = 944 kJ/L ≈ suppression_heat_absorption_kj_per_l.
# Ref: NFPA 1710 §A.5; SFPE Handbook 4th §16.2.
@export var suppression_evaporation_fraction: float = 0.27
# Tasa de desaparición del vapor por condensación + arrastre ventilatorio [1/s].
# A 0.5 /s la vida media en sala ventilada es ~1.4 s.
@export var suppression_steam_condensation_rate: float = 0.5

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
# Multiplicador global de HRR — solo para mutation testing (M-HRR). Valor 1.0 = sin mutación.
@export var fire_hrr_global_multiplier: float = 1.0
@export var fire_backdraft_pool_threshold_MJ: float = 8.0
@export var fire_backdraft_o2_max: float = 0.13
@export var fire_backdraft_temp_min_c: float = 180.0
@export var fire_backdraft_release_boost: float = 1.35
# Evento backdraft: multiplicador de HRR pico, duración del blast y cooldown de re-armado.
# Literatura (Gottuk 1992): bacakdraft genera picos de HRR 3-6× el máximo pre-extincion.
@export var fire_backdraft_hrr_multiplier: float = 4.0
@export var fire_backdraft_duration_s: float = 12.0
@export var fire_backdraft_cooldown_s: float = 180.0
# LFL/UFL y deflagración — SF-AUD-013.
# LFL/UFL como fracción volumétrica del gas combustible no quemado en la sala.
# Gas de pirólisis en incendios subventilados: mezcla CO/H₂/HC. LFL≈2%, UFL≈20%.
# Si la fracción de gas no quemado está FUERA del rango inflamable, no hay backdraft.
@export var fire_backdraft_lfl: float = 0.02
@export var fire_backdraft_ufl: float = 0.20
# Calor de combustión del gas de pirólisis no quemado [kJ/kg].
# CO: ~10 000; H₂: ~120 000; HC mixtos: ~40 000 → mix: ~10 000 kJ/kg conservador.
@export var fire_backdraft_fuel_heat_kj_kg: float = 10000.0
# Densidad del gas de pirólisis no quemado a temperatura de compartimento [kg/m³].
# CO a ~300°C ≈ 0.80 kg/m³; mix típico ≈ 0.8 kg/m³.
@export var fire_backdraft_fuel_gas_density: float = 0.8
# Sobrepresión de deflagración instantánea al disparar backdraft [Pa].
# 500 Pa ≈ sobrepresión de onda de choque leve; suficiente para sentirla pero no destructiva.
@export var fire_backdraft_deflagration_overpressure_pa: float = 500.0
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
# Criterio de flujo radiante al suelo (ISO 9705 / SFPE): ~20 kW/m² desencadena ignicion
# generalizada de superficies. Se evalua con Stefan-Boltzmann de la capa superior.
# Habilitado como criterio alternativo (OR) al de temperatura.
@export var flashover_floor_flux_criterion_enabled: bool = true
@export var flashover_floor_flux_kw_m2: float = 20.0
# Emissividad efectiva de la capa caliente para el calculo radiante al suelo.
@export var flashover_layer_emissivity: float = 0.9
# Predictores Thomas (1981) y MQH (McCaffrey-Quintiere-Harkleroad, 1981) — SF-AUD-012.
# Thomas: Q_fo = 7.8·A_T + 378·A_v·√H_v [kW]   (A_T = superficie total compartimento)
# MQH:    Q_fo = 610·(h_k·A_T·A_v·√H_v)^½ [kW] (h_k = coef. transfer. térm. pared)
# Se usan como criterio OR adicional cuando HRR supera el HRR crítico predicho.
@export var flashover_thomas_enabled: bool = true
@export var flashover_mqh_enabled: bool = true
# Coeficiente de transferencia de calor efectivo de las paredes [kW/m²·K].
# 0.012 kW/m²·K ≈ placa de yeso 12 mm (k=0.17 W/m·K / d=0.014 m).
@export var flashover_mqh_hk_kw_m2k: float = 0.012
@export var flashover_min_time_s: float = 0.0

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
## Fracción de χ_rad·HRR que se deposita directamente en paredes/techo (0 = todo a capa superior).
@export var hrr_rad_wall_fraction: float = 0.0
@export var phase4b_wall_reradiation_during_fire_enabled: bool = false
@export var phase4b_wall_reradiation_during_fire_gain: float = 1.0
@export var two_zone_convective_heat_multiplier: float = 1.0
@export var retained_hot_layer_temp_start_c: float = 100.0
@export var retained_hot_layer_temp_full_c: float = 350.0
@export var retained_hot_layer_o2_start: float = 0.18
@export var retained_hot_layer_o2_full: float = 0.10
@export var retained_hot_layer_max_fraction: float = 0.0
@export var outside_open_loss_area_fraction: float = 0.12
@export var outside_open_ambient_loss_multiplier: float = 5.0
@export var outside_open_wall_absorption_multiplier: float = 0.80
@export var outside_open_upper_mix_rate: float = 0.0
@export var outside_open_lower_warming_rate: float = 0.0
@export var outside_open_upper_heat_boost: float = 0.0
@export var outside_lower_fresh_air_cooling_rate: float = 0.0
@export var natural_vent_inlet_fraction: float = 0.5
@export var outside_open_background_heat_exchange_kg_s_m2: float = 0.030
@export var outside_open_background_heat_max_fraction_per_step: float = 0.020
@export var outside_open_background_heat_carry_factor: float = 0.42
@export var interior_background_heat_exchange_kg_s_m2: float = 0.015
@export var interior_background_heat_max_fraction_per_step: float = 0.012
@export var interior_background_heat_carry_factor: float = 0.38
@export var phase3_stairwell_heat_bridge_enabled: bool = false
@export var phase3_stairwell_heat_bridge_kg_s_m2: float = 0.0
@export var phase3_stairwell_heat_bridge_max_fraction_per_step: float = 0.018
@export var phase3_stairwell_heat_bridge_hot_temp_start_c: float = 30.0
@export var phase3_stairwell_heat_bridge_hot_temp_full_c: float = 90.0
@export var phase3_stairwell_heat_bridge_hole_multiplier: float = 1.0
@export var phase3_stairwell_heat_bridge_vertical_multiplier: float = 2.0
@export var phase3_stairwell_heat_bridge_target_lift_fraction: float = 0.012
@export var phase3_stairwell_heat_bridge_target_max_temp_c: float = 120.0
@export var hot_gas_species_carry_fraction: float = 0.72
@export var hot_gas_smoke_carry_fraction: float = 0.30
@export var hot_gas_species_max_fraction_per_step: float = 0.22
# SF-R6 Phase 2: carry convectivo HCN/irritantes por flujo de gas caliente.
# Valores 0.40 / 0.30 calibrados para parity CFAST TN-1889.
@export var hot_gas_hcn_carry_fraction: float = 0.40
@export var hot_gas_irritant_carry_fraction: float = 0.30
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
## Altura máxima de capa superior para considerar al ocupante inmerso (m).
## Por defecto 1.8 m (adulto de pie, ISO 13571). Sobreescribir por caso para
## análisis con niños, ocupantes agachados o criterio conservador de exposición.
@export var fed_upper_layer_threshold_m: float = 1.8
## Plan B/F2: cuando true, FED usa CO₂ mass-derived (co2_upper_ppm_mass) para
## calcular v_co2 en lugar del tracer OES (room.co2_upper × 1e6). Default false
## = no-op exacto. Activar per-caso en engine_overrides: {"fed_co2_source_mass": true}.
@export var fed_co2_source_mass: bool = false

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
## Factor de vista para FED radiante cuando el ocupante está BAJO la capa caliente (ISO 13571 §5.4.3).
@export var fed_heat_rad_view_factor_below: float = 0.35

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
## SF-R6 Phase 3: verificación de conservación de masa en transporte de contaminantes.
## Cuando true, ZoneFireSolver.validate_conservation() se llama cada paso y acumula
## la peor violación relativa (expuesta como "conservation_max_violation_frac" en estado).
@export var conservation_check_enabled: bool = false
## Peor violación de conservación de transporte registrada (fracción relativa).
## -1.0 significa que conservation_check_enabled=false (sin datos).
var _conservation_max_violation_frac: float = -1.0
## Tiempo del último step() en microsegundos (para diagnóstico de rendimiento).
var _step_time_us: int = 0
# SF-AUD-010: Bernoulli dos zonas para flujos por aperturas interiores y exteriores.
# Cuando true: flujo calculado con Q = Cd·W·f·(2/3)·h^(3/2)·sqrt(2g·ΔT/T_ref) y plano
# neutro calculado desde densidades. Default true → paridad CFAST (2026-05-17).
@export var vent_bernoulli_enabled: bool = true
# Multiplicador sobre el caudal Bernoulli de vanos exteriores — solo para mutation testing (M-VENT).
@export var vent_bernoulli_flow_multiplier: float = 1.0


# Absorción de calor por paredes — término proporcional simple sobre (T_upper - T_ambient).
# Mismo patrón que upper_to_ambient_loss_rate: sin dividir por m_upper_kg → estable.
# 0.003 /s → a 800°C de diferencia: 2.4°C/s adicionales (modest, calibratable).
@export var wall_absorption_rate: float = 0.003
@export var wall_heat_capacity_kj_m2_k: float = 20.0
@export var wall_core_decay_per_s: float = 0.0002
# SF-AUD-030: activar/desactivar el perfil 1D pared (Crank-Nicolson 5 nodos).
# Si false, wall_T_mid_c / wall_T_outer_c vuelven a temperatura ambiente.
@export var wall_pde_enabled: bool = true
# Conducción a través de paredes entre salas adyacentes (sin apertura abierta).
# U = 1.5 W/m²K = 0.0015 kW/m²K — partición ligera (yeso + montante metálico).
# Para mampostería: reducir a 0.0008-0.001. Desactivar con wall_conduction_enabled=false.
@export var wall_conduction_enabled: bool = true
# SF-AUD-031: cuando true, la conducción inter-sala usa temperatura ponderada por capa
# (upper/lower) en lugar de la temperatura superficial promedio de la pared.
@export var wall_layer_aware_conduction: bool = false
@export var wall_conduction_u_kw_m2_k: float = 0.0015
## Fracción máxima de energía transferida por conducción por paso de tiempo (estabilidad numérica).
@export var wall_conduction_max_fraction_per_step: float = 0.08
## Tolerancia (m) para detectar paredes adyacentes entre salas vecinas.
@export var wall_adjacency_tolerance_m: float = 0.10

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
# Víctimas/ocupantes definidos en la plantilla JSON.
# Acumulan FED ISO 13571 a su altura respiratoria (height_m).
# Al alcanzar FED ≥ 1.0 se marcan incapacitated y se registra el evento.
@export var victims_enabled: bool = true
# Modelo de jet de techo de Alpert (1972) para detectores de calor.
# Calcula la temperatura del jet en la posición del detector a partir de la
# potencia calorífica (HRR) y la distancia horizontal al penacho.
# Requiere que el detector JSON incluya x_m/y_m; si no, usa el centro de la sala.
@export var ceiling_jet_enabled: bool = true
# Fuego de charco (pool fire) con área de derrame que crece con el tiempo.
# Modela incendios de líquidos inflamables (gasolina, aceite) donde la potencia
# calorífica es proporcional al área del charco: HRR = pool_hrr_kw_m2 * area_m2.
@export var pool_fire_enabled: bool = true
# SF-AUD-035: oxidación de CO en capa caliente.
# Cuando T_upper > co_oxidation_temp_min_c y O2 > co_oxidation_o2_min,
# parte del CO se oxida a CO2.  Referencia: Drysdale «Fire Dynamics» §3.2;
# Pitts NIST TN 1603.
@export var co_oxidation_enabled: bool = false
@export var co_oxidation_temp_min_c: float = 700.0
@export var co_oxidation_o2_min: float = 0.05
@export var co_oxidation_rate_per_s: float = 0.002

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
# Coeficiente de contraflujo de O2 en transporte de humo inter-sala (doorway).
# Controla cuánto O2 se intercambia cuando pasa humo. Default=0.18 (valor histórico).
@export var doorway_o2_counterflow_coeff: float = 0.18
# Multiplicador del intercambio O2 por gradiente de concentración en _apply_background_species_exchange.
# 0.0 = deshabilitado (default) — O2 room-to-room gestionado exclusivamente por OxygenExchangeSystem.
# Evita el doble transporte de O2 entre sistemas. ghanekar_bedroom_hallway usa 3.0 (caso especial).
@export var background_o2_exchange_multiplier: float = 0.0
# Tasa de entrainment penacho→zona superior (plume replenishes o2_upper from o2_lower).
# Default 0.010 (OxygenExchangeSystem baseline). cfast_single_room_closed overrides to 0.013
# for R3 calibration: rate=0.013 → t210_temp=177°C, t300_o2=0.088 (pass); structural gap
# remains at t450_o2=0.080 vs 0.053 (requires temperature-dependent density to close fully).
@export var o2_upper_plume_entr_rate: float = 0.010
# PHY-B2: rendimiento CO₂ para el tracer mol-fraction de zona superior (room.co2_upper).
# Solo afecta OxygenExchangeSystem (tracer); CombustionSystem usa su propio yield por combustible.
# Default 0.0831 kg CO₂/MJ = mismo que co2_base_yield_kg_per_MJ en CombustionSystem.
@export var co2_yield_kg_per_MJ: float = 0.0831

# ── Phase 3: modelo de presión termodinámica (campo paralelo) ──────────────
# R2-1: ambas flags activadas por default como parte del perfil TwoZoneV1.
@export var phase3_thermodynamic_pressure_enabled: bool = true
# Usa pressure_pa_therm como presión canónica para venting/doorways.
@export var phase3_pressure_canonical_enabled: bool = false
@export var phase3_leak_area_m2: float = 0.0
@export var phase3_chi_conv: float = 0.70

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
## Si true, el modelo de penacho aplica z_eff = plume_confined_z_eff_fraction * room.height_m.
@export var plume_confined_flame_enabled: bool = true
## Factor de escala de z_eff para penacho confinado (1.0 = altura física de la sala).
@export var plume_confined_z_eff_fraction: float = 1.0
@export var plume_fire_diameter_m: float = 1.0
@export var plume_flame_region_entrainment_enabled: bool = false
@export var plume_flame_region_coeff: float = 0.071
@export var plume_flame_region_min_z_m: float = 0.20
@export var plume_flame_region_max_depth_fraction: float = 0.97
@export var thermal_plume_depth_scale: float = 0.40
@export var target_smoke_resistance_coeff: float = 0.20
## Phase 2E — experimento transporte dos zonas (default OFF — no altera baseline)
@export var phase2e_two_zone_transport_enabled: bool = false
## Phase 2E — modo deposición CO cuando flag ON ("all_upper" | "geometric_split" | "upper_floor_90" | "upper_floor_95")
@export var phase2e_co_deposition_mode: String = "all_upper"
## Phase 2F — mixing CO inter-capa (default OFF — no altera baseline)
@export var phase2f_co_interlayer_mixing_enabled: bool = false
@export var phase2f_co_interlayer_mixing_rate: float = 0.0
@export var phase2f_co_interlayer_mixing_guard: String = "no_guard"
## Phase 2G — término fuente CO zona lower en generación (default OFF — no altera baseline)
## Fracción de generated_co_kg que se asigna directamente a lower (implícito = co_kg - co_upper_kg).
## co_kg total se mantiene invariante; sólo co_upper_kg recibe (1 - fraction) * generated_co_kg.
@export var phase2g_co_lower_source_enabled: bool = false
@export var phase2g_co_lower_source_fraction: float = 0.0
## "fire_room_only"               : aplica en cualquier sala con fuego activo (= all_rooms_with_fire en test cases)
## "only_when_hot_layer_above_1_8m": aplica sólo cuando interfaz capa caliente > 1.8 m
## "all_rooms_with_fire"           : equivalente a fire_room_only (todas las salas con combustión)
@export var phase2g_co_lower_source_guard: String = "fire_room_only"
## Phase 2H — O₂ lower-zone flow candidate (default OFF — no altera baseline)
## Cuando ON: protege o2_lower en salas sin doorway interior, mezcla la zona baja con
## mayor fuerza si hay doorway interior abierto, y permite mezcla moderada tras apertura exterior.
## room.o2, CO, HRR y FED siguen gobernados por los modelos base.
@export var phase2h_o2_doorway_two_zone_enabled: bool = false
## Exp 2H.2: ajusta la reposición directa de o2_lower desde flujos interiores activos.
@export var phase2h_cold_room_lower_routing_enabled: bool = false
## Exp 2H.2: gain del boost de reabastecimiento de zona baja desde apertura exterior/HVAC bajo.
## 0.0 = no-op (default OFF); valores experimentales: 0.25 / 0.5 / 1.0.
@export var phase2h_lower_replenish_gain: float = 0.0
## Phase 2A/2H experimento: drenaje de o2_lower por doorway interior sin soporte exterior.
## 0.0 conserva guard v4; 1.0 restaura el drenaje acelerado completo para barridos.
@export var phase2h_interior_no_exterior_drain_gain: float = 0.0
@export var phase2h_interior_no_exterior_drain_max_scale: float = 1.40
## Phase 2 opt-in: routing de O₂ zona alta por vano interior (CFAST two-zone doorway depletion).
## gain=0.0 = no-op exacto. Activar por caso en engine_overrides. Default 0.0 = sin impacto.
@export var doorway_o2_upper_routing_gain: float = 0.0
## Phase 2H: equilibrio CFAST-like de zona baja via doorway mixing (experimental, opt-in, default 0.0 = no-op).
## coeff = fracción objetivo de cold_room.o2 (ej. 0.56 → floor ≈ 0.17×0.56 = 0.095).
## Floor = max(room.o2, cold_room.o2×coeff): evita subdrenaje cuando room.o2 cae bajo target.
## Tasa = 4.0×exchange_kg/lower_mass (calibrado 2026-05-27: coeff=0.56 cierra 3/3 gaps two_room).
## Requiere phase2h_o2_doorway_two_zone_enabled=true. Default 0.0 = sin impacto en producción.
## Valor calibrado en engine_overrides de cfast_two_room_door_open.json. Victim FED delta=+0.0000.
@export var phase2h_lower_cf_drain_coeff: float = 0.0
## Tasa de mezcla cf_drain: ratio exchange_kg/lower_mass. Calibrado 4.0 → equilibrio a t=300s.
## Default 4.0 = invariante de producción (misma calibración). Solo activo con cf_drain_coeff > 0.
@export var phase2h_lower_cf_drain_rate: float = 4.0
## Phase 2H — Preset opt-in: activa two_zone + cold_routing + gain=0.25 con un solo flag.
## Validado 2026-05-26: 10/10 checks O2 lower PASS en runner targeted; default OFF.
## Safe como opt-in: no altera ninguna baseline required con default OFF. No requiere rebaseline.
## Nombre del preset: phase2h_o2_lower_replenish_candidate
## Uso en engine_overrides JSON: { "phase2h_candidate_preset": true }
@export var phase2h_candidate_preset: bool = false
## Phase 2D: HVAC return en zona alta extrae gas depleccionado; la zona superior se repone desde
## la zona baja (conservación de masa). Modela el balance two-zone que CFAST tiene en HVAC return.
## Cuando true: o2_upper ← lerp(o2_upper, o2_lower, flow/upper_vol) en cada paso del return.
## Default false = no-op exacto. Activar per-caso via engine_overrides.
@export var hvac_two_zone_o2_enabled: bool = false
## Phase 2I — CO₂ upper fraction floor en sala fuego (default OFF = 0.0)
## Cuando > 0.0: co2_upper_kg se eleva a mín. co2_kg × fraction en salas con fuego activo.
## co2_kg invariante (sin creación/destrucción). Rango experimental: [0.25, 0.50, 0.75, 1.0].
## Experimento 1 (2026-05-25): medir impacto en gaps CO₂ upper y sentinels FED/CO.
## Nota: afecta co2_upper_kg (kg-tracking). Las métricas ppm del log usan room.co2_upper
## (fracción molar de OxygenExchangeSystem) — ver diagnóstico en PHASE_2E_DESIGN.md §12.14.
@export var phase2i_co2_upper_fraction: float = 0.0
## Phase 2E Sub-C — CO\u2082 upper tracer boost en sala con fuego activo (default OFF).
## Amplifica la producci\u00f3n de room.co2_upper por un factor (1 + gain). gain=0.0 = no-op exacto.
## Sweep experimental: [0.0, 0.25, 0.50, 0.75, 1.0].
@export var phase2e_co2_subc_enabled: bool = false
@export var phase2e_co2_fire_upper_boost_gain: float = 0.0
## Phase 2E Sub-A — supresión de dilución de co2_upper por inflow exterior (PRODUCCIÓN: ON, gain=0.20).
## OFF: dilución proporcional con masa de sala completa (comportamiento original).
## ON: fracción efectiva de air_in que mezcla con zona alta = air_in × (1 − gain).
##   gain=0.0 → igual que OFF; gain=1.0 → sin dilución; candidato verificado: gain=0.20.
##   Verificado Exp 1E: t510=38356ppm ∈ [32300,72300]; t420=80512ppm ∈ [38800,82800].
@export var phase2e_co2_suba_enabled: bool = true
@export var phase2e_co2_upper_outflow_gain: float = 0.20
## Phase 2E Sub-B — fracción de intercambio CO₂ inter-room por flujo activo (default OFF).
## OFF: CO2_EXCHANGE_FRACTION constante = 0.25 (Fase 2B original, no-op exacto).
## ON: usa phase2e_co2_exchange_fraction; sweep [0.03, 0.05, 0.08].
@export var phase2e_co2_subb_enabled: bool = false
@export var phase2e_co2_exchange_fraction: float = 0.25
## Phase 2E Sub-D — omite snap bi-zona cuando sala tiene fuego activo (PRODUCCIÓN: ON).
## OFF: snap original a valor-masa (no-op exacto). ON: rama producción continúa cuando lower_frac baja.
## Verificado Exp 1D: t480=12.1% ∈ [6.91%,12.91%]; FED delta=0.000.
@export var phase2e_co2_subd_enabled: bool = true
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
@export var log_file_path: String = "user://sim_log.txt"
## Si es true, también guarda el log en formato CSV al parar la simulación.
@export var enable_csv_log: bool = true
@export var csv_log_file_path: String = "user://sim_log.csv"
## Si es true, genera además un dashboard.html interactivo (Plotly) al terminar,
## junto a los PNG. No sustituye a las gráficas matplotlib. Requiere Python+plotly.
@export var enable_html_dashboard: bool = true
## Phase 3+ F0: telemetria two-zone temporal. Default OFF conserva el schema legacy.
@export var phase3_zone_diagnostics_enabled: bool = false
## F3.0: transaccion two-zone shadow. Default OFF; nunca escribe estado legacy.
@export var phase3_canonical_zone_shadow_enabled: bool = false
## F3.2a: frontera exterior pressure/leakage solo en shadow. Requiere F3.0.
@export var phase3_canonical_exterior_boundary_shadow_enabled: bool = false
## F3.2b0: continuidad step-to-step solo en shadow. Default OFF; no cambia HRR.
@export var phase3_canonical_persistence_shadow_enabled: bool = false
## F3.2b1: transaccion cerrada combustion/plume solo en shadow. Default OFF.
@export var phase3_canonical_combustion_shadow_enabled: bool = false
## F3.2b2: relajacion exterior y reseed lower conservativos. Default OFF.
@export var phase3_canonical_pressure_relaxation_shadow_enabled: bool = false
## F3.2b3: plume evaluado desde geometria canonica pre-step. Default OFF.
@export var phase3_canonical_plume_shadow_enabled: bool = false
## F3.2b5a: intercambio upper/lower desde estado canonico pre-step. Default OFF.
@export var phase3_canonical_interzone_heat_shadow_enabled: bool = false
## F3.2b5b: pared/ambiente desde estado canonico y reservorio separado. Default OFF.
@export var phase3_canonical_wall_ambient_shadow_enabled: bool = false
## F3.3r2b: superficies canonicas independientes. Default OFF y excluye pared lumped.
@export var phase3_canonical_multisurface_shadow_enabled: bool = false
## F3.3t: plume Heskestad completo desde HRR/chi aceptados. Requiere multisurface.
@export var phase3_coupled_plume_shadow_enabled: bool = false
## F3.3v1: propuesta HRR pre-throttle, pura y solo diagnostica. Default OFF.
@export var phase3_canonical_fire_proposal_shadow_enabled: bool = false
## F3.3v2: productos puros de la propuesta aceptada. Default OFF.
@export var phase3_canonical_fire_products_shadow_enabled: bool = false
## F3.2b6: counterflow exterior compensado desde estado canonico. Default OFF.
@export var phase3_canonical_exterior_counterflow_shadow_enabled: bool = false
## F3.2b7: combustion usa lower O2 durante counterflow exterior real. Default OFF.
@export var phase3_canonical_post_opening_coupling_shadow_enabled: bool = false
## F3.3a: transporte two-zone horizontal interior, atomico y solo shadow.
@export var phase3_canonical_interior_opening_shadow_enabled: bool = false
## F3.3b: componente firmado por diferencia de presion interior. Default OFF.
@export var phase3_canonical_interior_pressure_shadow_enabled: bool = false
## F3.3c1: ledger acumulativo de entalpia aceptada por ruta. Default OFF.
@export var phase3_enthalpy_residence_diagnostics_enabled: bool = false
## F3.3d1: ledger acumulativo de masa aceptada por ruta. Default OFF.
@export var phase3_mass_residence_diagnostics_enabled: bool = false
## F3.3k: ledger aceptado por conexion; solo se exporta en summary.json.
@export var phase3_connection_residence_diagnostics_enabled: bool = false
## F3.3n: reparto receptor CFAST flogo; experimento shadow, default OFF.
@export var phase3_cfast_buoyancy_destination_shadow_enabled: bool = false

# ============================================================
# SERVICIOS AUXILIARES
# ============================================================

func _sync_auxiliary_services() -> void:
	if not is_ready_for_validation():
		push_error("SimulationEngine: subsistemas no inicializados; no se puede sincronizar")
		return

	zone_fire_solver.two_zone_energy_enabled = two_zone_solver_enabled
	zone_fire_solver.projection_diagnostics_enabled = phase3_zone_diagnostics_enabled
	zone_fire_solver.set_building(building)
	thermal_system.set_references(building, smoke_model)
	thermal_system.set_zone_fire_solver(zone_fire_solver)
	thermal_system.configure({
		"two_zone_solver_enabled": two_zone_solver_enabled,
		"phase3_zone_diagnostics_enabled": phase3_zone_diagnostics_enabled,
		"phase3_canonical_zone_shadow_enabled": phase3_canonical_zone_shadow_enabled,
		"upper_to_lower_loss_rate": upper_to_lower_loss_rate,
		"upper_to_ambient_loss_rate": upper_to_ambient_loss_rate,
		"lower_layer_warming_rate": lower_layer_warming_rate,
		"wall_absorption_rate": wall_absorption_rate,
		"wall_heat_capacity_kj_m2_k": wall_heat_capacity_kj_m2_k,
		"wall_core_decay_per_s": wall_core_decay_per_s,
		"wall_pde_enabled": wall_pde_enabled,
		"wall_conduction_enabled": wall_conduction_enabled,
		"wall_conduction_u_kw_m2_k": wall_conduction_u_kw_m2_k,
		"wall_conduction_max_fraction_per_step": wall_conduction_max_fraction_per_step,
		"wall_adjacency_tolerance_m": wall_adjacency_tolerance_m,
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
		"hrr_rad_wall_fraction": hrr_rad_wall_fraction,
		"phase4b_wall_reradiation_during_fire_enabled": phase4b_wall_reradiation_during_fire_enabled,
		"phase4b_wall_reradiation_during_fire_gain": phase4b_wall_reradiation_during_fire_gain,
		"two_zone_convective_heat_multiplier": two_zone_convective_heat_multiplier,
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
		"outside_open_upper_heat_boost": outside_open_upper_heat_boost,
		"outside_lower_fresh_air_cooling_rate": outside_lower_fresh_air_cooling_rate,
		"outside_open_background_heat_exchange_kg_s_m2": outside_open_background_heat_exchange_kg_s_m2,
		"outside_open_background_heat_max_fraction_per_step": outside_open_background_heat_max_fraction_per_step,
		"outside_open_background_heat_carry_factor": outside_open_background_heat_carry_factor,
		"interior_background_heat_exchange_kg_s_m2": interior_background_heat_exchange_kg_s_m2,
		"interior_background_heat_max_fraction_per_step": interior_background_heat_max_fraction_per_step,
		"interior_background_heat_carry_factor": interior_background_heat_carry_factor,
		"phase3_stairwell_heat_bridge_enabled": phase3_stairwell_heat_bridge_enabled,
		"phase3_stairwell_heat_bridge_kg_s_m2": phase3_stairwell_heat_bridge_kg_s_m2,
		"phase3_stairwell_heat_bridge_max_fraction_per_step": phase3_stairwell_heat_bridge_max_fraction_per_step,
		"phase3_stairwell_heat_bridge_hot_temp_start_c": phase3_stairwell_heat_bridge_hot_temp_start_c,
		"phase3_stairwell_heat_bridge_hot_temp_full_c": phase3_stairwell_heat_bridge_hot_temp_full_c,
		"phase3_stairwell_heat_bridge_hole_multiplier": phase3_stairwell_heat_bridge_hole_multiplier,
		"phase3_stairwell_heat_bridge_vertical_multiplier": phase3_stairwell_heat_bridge_vertical_multiplier,
		"phase3_stairwell_heat_bridge_target_lift_fraction": phase3_stairwell_heat_bridge_target_lift_fraction,
		"phase3_stairwell_heat_bridge_target_max_temp_c": phase3_stairwell_heat_bridge_target_max_temp_c,
		"hot_gas_species_carry_fraction": hot_gas_species_carry_fraction,
		"hot_gas_smoke_carry_fraction": hot_gas_smoke_carry_fraction,
		"hot_gas_species_max_fraction_per_step": hot_gas_species_max_fraction_per_step,
		"hot_gas_hcn_carry_fraction": hot_gas_hcn_carry_fraction,
		"hot_gas_irritant_carry_fraction": hot_gas_irritant_carry_fraction,
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
		"plume_confined_flame_enabled": plume_confined_flame_enabled,
		"plume_confined_z_eff_fraction": plume_confined_z_eff_fraction,
		"plume_fire_diameter_m": plume_fire_diameter_m,
		"plume_flame_region_entrainment_enabled": plume_flame_region_entrainment_enabled,
		"plume_flame_region_coeff": plume_flame_region_coeff,
		"plume_flame_region_min_z_m": plume_flame_region_min_z_m,
		"plume_flame_region_max_depth_fraction": plume_flame_region_max_depth_fraction,
		"fed_hypoxia_enabled": fed_hypoxia_enabled,
		"fed_hypoxia_a": fed_hypoxia_a,
		"fed_hypoxia_b": fed_hypoxia_b,
		"fed_upper_layer_threshold_m": fed_upper_layer_threshold_m,
		"fed_co2_source_mass": fed_co2_source_mass,
		"fed_heat_enabled": fed_heat_enabled,
		"fed_heat_conv_a": fed_heat_conv_a,
		"fed_heat_conv_n": fed_heat_conv_n,
		"fed_heat_conv_min_c": fed_heat_conv_min_c,
		"fed_heat_rad_a": fed_heat_rad_a,
		"fed_heat_rad_view_factor": fed_heat_rad_view_factor,
		"fed_heat_rad_view_factor_below": fed_heat_rad_view_factor_below,
		"radiation_opening_enabled": radiation_opening_enabled,
		"radiation_flame_emissivity": radiation_flame_emissivity,
		"radiation_opening_view_factor": radiation_opening_view_factor,
		"radiation_smoke_attenuation_factor": radiation_smoke_attenuation_factor,
		"radiation_min_source_temp_c": radiation_min_source_temp_c,
		"radiation_max_fraction_per_step": radiation_max_fraction_per_step,
		"energy_budget_enabled": energy_budget_enabled,
		"energy_budget_warn_fraction": energy_budget_warn_fraction,
		"vent_bernoulli_enabled": vent_bernoulli_enabled,
		"wall_layer_aware_conduction": wall_layer_aware_conduction,
		"phase2e_two_zone_transport_enabled": phase2e_two_zone_transport_enabled,
		"phase2e_co_deposition_mode": phase2e_co_deposition_mode,
		"phase2f_co_interlayer_mixing_enabled": phase2f_co_interlayer_mixing_enabled,
		"phase2f_co_interlayer_mixing_rate": phase2f_co_interlayer_mixing_rate,
		"phase2f_co_interlayer_mixing_guard": phase2f_co_interlayer_mixing_guard,
		"phase2i_co2_upper_fraction": phase2i_co2_upper_fraction,
		"doorway_thermal_counterflow_enabled": doorway_thermal_counterflow_enabled,
		"doorway_thermal_counterflow_gain": doorway_thermal_counterflow_gain,
		"doorway_thermal_counterflow_o2_return_fraction": doorway_thermal_counterflow_o2_return_fraction,
		"canonical_doorway_exchange_enabled": canonical_doorway_exchange_enabled,
		"canonical_doorway_lower_flow_frac": canonical_doorway_lower_flow_frac,
		"canonical_doorway_lower_inflow_multiplier": canonical_doorway_lower_inflow_multiplier,
		"phase3a_pressure_ode_enabled": phase3a_pressure_ode_enabled,
		"phase3a_pressure_vent_loss_coeff": phase3a_pressure_vent_loss_coeff,
		"phase3a_pressure_max_pa": phase3a_pressure_max_pa,
		"phase3b_neutral_plane_dp_correction": phase3b_neutral_plane_dp_correction,
		"canonical_doorway_plume_direct_upper_frac": canonical_doorway_plume_direct_upper_frac,
		"phase3_conservative_lower_return_enabled": phase3_conservative_lower_return_enabled,
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
		"glass_break_mode": int(glass_break_mode),
		"glass_break_temp_c": glass_break_temp_c,
		"glass_break_temp_spread_c": glass_break_temp_spread_c,
		"glass_open_rate_per_s": glass_open_rate_per_s,
		"glass_max_open_fraction": glass_max_open_fraction,
		"glass_break_exposure_start_temp_c": glass_break_exposure_start_temp_c,
		"glass_break_hazard_base_per_s": glass_break_hazard_base_per_s,
		"glass_break_hazard_temp_exp": glass_break_hazard_temp_exp,
		"glass_break_hazard_exposure_tau_s": glass_break_hazard_exposure_tau_s
	})
	gas_exchange_system.configure({
		"o2_nominal": o2_nominal,
		"phase3_zone_diagnostics_enabled": phase3_zone_diagnostics_enabled,
		"phase3_canonical_zone_shadow_enabled": phase3_canonical_zone_shadow_enabled,
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
		"vent_bernoulli_enabled": vent_bernoulli_enabled,
		"vent_bernoulli_flow_multiplier": vent_bernoulli_flow_multiplier,
		"o2_smoke_carry_coeff": o2_smoke_carry_coeff,
		"doorway_o2_counterflow_coeff": doorway_o2_counterflow_coeff,
		"background_o2_exchange_multiplier": background_o2_exchange_multiplier,
		"two_zone_opening_flow_enabled": two_zone_solver_enabled and two_zone_opening_flow_enabled,
		"phase3_thermodynamic_pressure_enabled": phase3_thermodynamic_pressure_enabled,
		"phase3_pressure_canonical_enabled": phase3_pressure_canonical_enabled,
		"phase3_leak_area_m2": phase3_leak_area_m2,
		"phase3_chi_conv": phase3_chi_conv,
	})
	# Phase 2H candidate preset — opt-in: expande phase2h_candidate_preset al trío de flags.
	# Solo activo si phase2h_candidate_preset = true (default = false → sin efecto en baseline).
	if phase2h_candidate_preset:
		phase2h_o2_doorway_two_zone_enabled = true
		phase2h_cold_room_lower_routing_enabled = true
		phase2h_lower_replenish_gain = 0.25
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
		"doorway_o2_background_min_factor": doorway_o2_background_min_factor,
		"vent_bernoulli_enabled": vent_bernoulli_enabled,
		"o2_upper_plume_entr_rate": o2_upper_plume_entr_rate,
		"co2_yield_kg_per_MJ": co2_yield_kg_per_MJ,
		"phase2h_o2_doorway_two_zone_enabled": phase2h_o2_doorway_two_zone_enabled,
		"phase2h_cold_room_lower_routing_enabled": phase2h_cold_room_lower_routing_enabled,
		"phase2h_lower_replenish_gain": phase2h_lower_replenish_gain,
		"phase2h_interior_no_exterior_drain_gain": phase2h_interior_no_exterior_drain_gain,
		"phase2h_interior_no_exterior_drain_max_scale": phase2h_interior_no_exterior_drain_max_scale,
		"doorway_o2_upper_routing_gain": doorway_o2_upper_routing_gain,
		"phase2h_lower_cf_drain_coeff": phase2h_lower_cf_drain_coeff,
		"phase2h_lower_cf_drain_rate": phase2h_lower_cf_drain_rate,
		"phase2e_co2_subc_enabled": phase2e_co2_subc_enabled,
		"phase2e_co2_fire_upper_boost_gain": phase2e_co2_fire_upper_boost_gain,
		"phase2e_co2_suba_enabled": phase2e_co2_suba_enabled,
		"phase2e_co2_upper_outflow_gain": phase2e_co2_upper_outflow_gain,
		"phase2e_co2_subb_enabled": phase2e_co2_subb_enabled,
		"phase2e_co2_exchange_fraction": phase2e_co2_exchange_fraction,
		"phase2e_co2_subd_enabled": phase2e_co2_subd_enabled,
		"fire_o2_mode": fire_o2_mode,
		"fire_o2_lower_for_flame": fire_o2_lower_for_flame,
		"fire_o2_canonical_enabled": fire_o2_canonical_enabled,
		"fire_o2_mass_tracking_enabled": fire_o2_mass_tracking_enabled,
		"phase3_canonical_zone_shadow_enabled": phase3_canonical_zone_shadow_enabled,
	})
	var phase3_enthalpy_residence_diagnostics_active: bool = \
			phase3_canonical_zone_shadow_enabled \
			and phase3_canonical_persistence_shadow_enabled \
			and phase3_canonical_combustion_shadow_enabled \
			and phase3_canonical_plume_shadow_enabled \
			and phase3_canonical_interzone_heat_shadow_enabled \
			and phase3_canonical_wall_ambient_shadow_enabled \
			and phase3_canonical_exterior_counterflow_shadow_enabled \
			and phase3_canonical_post_opening_coupling_shadow_enabled \
			and phase3_canonical_interior_opening_shadow_enabled \
			and phase3_canonical_interior_pressure_shadow_enabled \
			and phase3_enthalpy_residence_diagnostics_enabled
	phase3_zone_mass_system.configure_enthalpy_residence_diagnostics(
		phase3_enthalpy_residence_diagnostics_active
	)
	var phase3_mass_residence_diagnostics_active: bool = \
			phase3_canonical_zone_shadow_enabled \
			and phase3_canonical_persistence_shadow_enabled \
			and phase3_canonical_combustion_shadow_enabled \
			and phase3_canonical_plume_shadow_enabled \
			and phase3_canonical_interzone_heat_shadow_enabled \
			and phase3_canonical_wall_ambient_shadow_enabled \
			and phase3_canonical_exterior_counterflow_shadow_enabled \
			and phase3_canonical_post_opening_coupling_shadow_enabled \
			and phase3_canonical_interior_opening_shadow_enabled \
			and phase3_canonical_interior_pressure_shadow_enabled \
			and phase3_mass_residence_diagnostics_enabled
	phase3_zone_mass_system.configure_mass_residence_diagnostics(
		phase3_mass_residence_diagnostics_active
	)
	var phase3_connection_residence_diagnostics_active: bool = \
			phase3_enthalpy_residence_diagnostics_active \
			and phase3_mass_residence_diagnostics_active \
			and phase3_connection_residence_diagnostics_enabled
	phase3_zone_mass_system.configure_connection_residence_diagnostics(
		phase3_connection_residence_diagnostics_active
	)
	phase3_zone_mass_system.configure_canonical_multisurface_shadow(
		_phase3_canonical_multisurface_active()
	)
	log_writer.configure(enable_logging, log_interval_s, log_file_path)
	log_writer.configure_csv(enable_csv_log, csv_log_file_path)
	log_writer.configure_phase3_zone_diagnostics(phase3_zone_diagnostics_enabled)
	log_writer.configure_phase3_canonical_shadow(phase3_canonical_zone_shadow_enabled)
	log_writer.configure_phase3_canonical_exterior_boundary_shadow(
		phase3_canonical_zone_shadow_enabled \
				and phase3_canonical_exterior_boundary_shadow_enabled
	)
	log_writer.configure_phase3_canonical_persistence_shadow(
		phase3_canonical_zone_shadow_enabled \
				and phase3_canonical_persistence_shadow_enabled
	)
	log_writer.configure_phase3_canonical_combustion_shadow(
		phase3_canonical_zone_shadow_enabled \
				and phase3_canonical_persistence_shadow_enabled \
				and phase3_canonical_combustion_shadow_enabled
	)
	log_writer.configure_phase3_canonical_fire_proposal_shadow(
		phase3_canonical_zone_shadow_enabled \
				and phase3_canonical_persistence_shadow_enabled \
				and phase3_canonical_combustion_shadow_enabled \
				and phase3_canonical_fire_proposal_shadow_enabled
	)
	log_writer.configure_phase3_canonical_fire_products_shadow(
		phase3_canonical_zone_shadow_enabled \
				and phase3_canonical_persistence_shadow_enabled \
				and phase3_canonical_combustion_shadow_enabled \
				and phase3_canonical_fire_proposal_shadow_enabled \
				and phase3_canonical_fire_products_shadow_enabled
	)
	log_writer.configure_phase3_canonical_pressure_relaxation_shadow(
		phase3_canonical_zone_shadow_enabled \
				and phase3_canonical_exterior_boundary_shadow_enabled \
				and phase3_canonical_persistence_shadow_enabled \
				and phase3_canonical_combustion_shadow_enabled \
				and phase3_canonical_pressure_relaxation_shadow_enabled
	)
	log_writer.configure_phase3_canonical_interzone_heat_shadow(
		phase3_canonical_zone_shadow_enabled \
				and phase3_canonical_persistence_shadow_enabled \
				and phase3_canonical_plume_shadow_enabled \
				and phase3_canonical_interzone_heat_shadow_enabled
	)
	log_writer.configure_phase3_canonical_wall_ambient_shadow(
		phase3_canonical_zone_shadow_enabled \
				and phase3_canonical_persistence_shadow_enabled \
				and phase3_canonical_plume_shadow_enabled \
				and phase3_canonical_interzone_heat_shadow_enabled \
				and phase3_canonical_wall_ambient_shadow_enabled \
				and not phase3_canonical_multisurface_shadow_enabled
	)
	log_writer.configure_phase3_canonical_exterior_counterflow_shadow(
		phase3_canonical_zone_shadow_enabled \
				and phase3_canonical_exterior_boundary_shadow_enabled \
				and phase3_canonical_persistence_shadow_enabled \
				and phase3_canonical_pressure_relaxation_shadow_enabled \
				and phase3_canonical_exterior_counterflow_shadow_enabled
	)
	log_writer.configure_phase3_canonical_post_opening_coupling_shadow(
		phase3_canonical_zone_shadow_enabled \
				and phase3_canonical_persistence_shadow_enabled \
				and phase3_canonical_combustion_shadow_enabled \
				and phase3_canonical_exterior_counterflow_shadow_enabled \
				and phase3_canonical_post_opening_coupling_shadow_enabled
	)
	log_writer.configure_phase3_canonical_interior_opening_shadow(
		phase3_canonical_zone_shadow_enabled \
				and phase3_canonical_persistence_shadow_enabled \
				and phase3_canonical_interior_opening_shadow_enabled
	)
	log_writer.configure_phase3_canonical_interior_pressure_shadow(
		phase3_canonical_zone_shadow_enabled \
				and phase3_canonical_persistence_shadow_enabled \
				and phase3_canonical_interior_opening_shadow_enabled \
				and phase3_canonical_interior_pressure_shadow_enabled
	)
	log_writer.configure_phase3_enthalpy_residence_diagnostics(
		phase3_enthalpy_residence_diagnostics_active
	)
	log_writer.configure_phase3_mass_residence_diagnostics(
		phase3_mass_residence_diagnostics_active
	)
	# SF-R6: ZoneFireSolver — inyectar referencia al building.
	zone_fire_solver.set_building(building)
func _phase3_zone_diag_snapshot() -> Dictionary:
	var snapshot: Dictionary = {}
	if not phase3_zone_diagnostics_enabled or building == null:
		return snapshot
	for room_id in building.get_rooms().keys():
		var room: RoomModel = building.get_room(room_id)
		if room == null:
			continue
		snapshot[str(room_id)] = {
			"mass_kg": room.zone_total_mass_kg(),
			"energy_kj": room.zone_total_energy_kj(),
			"boundary_mass_kg": room.two_zone_boundary_mass_kg,
			"boundary_energy_kj": room.two_zone_boundary_energy_kj,
			"opening_upper_in_kg": room.two_zone_opening_upper_in_kg,
			"opening_upper_out_kg": room.two_zone_opening_upper_out_kg,
			"opening_lower_in_kg": room.two_zone_opening_lower_in_kg,
			"opening_lower_out_kg": room.two_zone_opening_lower_out_kg,
			"plume_entrained_kg": room.phase3_diag_plume_entrained_kg_total,
		}
	return snapshot


func _phase3_zone_diag_begin_step() -> void:
	if not phase3_zone_diagnostics_enabled:
		return
	zone_fire_solver.begin_projection_diagnostics_step()
	_phase3_zone_diag_step.clear()
	_phase3_zone_diag_start = _phase3_zone_diag_snapshot()
	_phase3_zone_diag_checkpoint = _phase3_zone_diag_start.duplicate(true)


func _phase3_zone_diag_record_stage(stage_name: String) -> void:
	if not phase3_zone_diagnostics_enabled:
		return
	var current: Dictionary = _phase3_zone_diag_snapshot()
	for room_key in current.keys():
		var before: Dictionary = _phase3_zone_diag_checkpoint.get(room_key, {})
		var after: Dictionary = current.get(room_key, {})
		var room_diag: Dictionary = _phase3_zone_diag_step.get(room_key, {})
		var mass_key: String = stage_name + "_mass_delta_kg_step"
		var energy_key: String = stage_name + "_energy_delta_kj_step"
		room_diag[mass_key] = float(room_diag.get(mass_key, 0.0)) \
				+ float(after.get("mass_kg", 0.0)) - float(before.get("mass_kg", 0.0))
		room_diag[energy_key] = float(room_diag.get(energy_key, 0.0)) \
				+ float(after.get("energy_kj", 0.0)) - float(before.get("energy_kj", 0.0))
		_phase3_zone_diag_step[room_key] = room_diag
	_phase3_zone_diag_checkpoint = current


func _phase3_zone_diag_export() -> Dictionary:
	if not phase3_zone_diagnostics_enabled:
		return {}
	var exported: Dictionary = _phase3_zone_diag_step.duplicate(true)
	var current: Dictionary = _phase3_zone_diag_snapshot()
	var stages: Array[String] = [
		"oxygen_exchange", "combustion", "thermal", "suppression",
		"gas_exchange", "hvac", "other", "reconcile", "projection_clamp"
	]
	for room_key in current.keys():
		var start: Dictionary = _phase3_zone_diag_start.get(room_key, {})
		var finish: Dictionary = current.get(room_key, {})
		var room_diag: Dictionary = exported.get(room_key, {})
		room_diag["two_zone_boundary_mass_kg_step"] = float(finish.get("boundary_mass_kg", 0.0)) \
				- float(start.get("boundary_mass_kg", finish.get("boundary_mass_kg", 0.0)))
		room_diag["two_zone_boundary_energy_kj_step"] = float(finish.get("boundary_energy_kj", 0.0)) \
				- float(start.get("boundary_energy_kj", finish.get("boundary_energy_kj", 0.0)))
		for opening_key in ["opening_upper_in_kg", "opening_upper_out_kg", "opening_lower_in_kg", "opening_lower_out_kg"]:
			room_diag[opening_key + "_step"] = float(finish.get(opening_key, 0.0)) \
					- float(start.get(opening_key, finish.get(opening_key, 0.0)))
		room_diag["plume_entrained_kg_step"] = float(finish.get("plume_entrained_kg", 0.0)) \
				- float(start.get("plume_entrained_kg", finish.get("plume_entrained_kg", 0.0)))
		var attributed_mass_kg: float = 0.0
		var attributed_energy_kj: float = 0.0
		for stage_name in stages:
			attributed_mass_kg += float(room_diag.get(stage_name + "_mass_delta_kg_step", 0.0))
			attributed_energy_kj += float(room_diag.get(stage_name + "_energy_delta_kj_step", 0.0))
		var observed_mass_kg: float = float(finish.get("mass_kg", 0.0)) \
				- float(start.get("mass_kg", finish.get("mass_kg", 0.0)))
		var observed_energy_kj: float = float(finish.get("energy_kj", 0.0)) \
				- float(start.get("energy_kj", finish.get("energy_kj", 0.0)))
		room_diag["attribution_mass_residual_kg_step"] = observed_mass_kg - attributed_mass_kg
		room_diag["attribution_energy_residual_kj_step"] = observed_energy_kj - attributed_energy_kj
		exported[room_key] = room_diag
	return exported


func _phase3_shadow_collect_thermal_requests(dt: float) -> void:
	var canonical_heat_by_room: Dictionary = {}
	var canonical_plume_by_room: Dictionary = {}
	var canonical_interzone_rooms: Dictionary = {}
	var canonical_wall_legacy_by_room: Dictionary = {}
	var canonical_wall_causes: Array[String] = [
		"thermal_upper_radiative_loss",
		"thermal_upper_to_ambient",
		"thermal_wall_absorption",
		"thermal_wall_emission",
		"thermal_lower_decay",
		"thermal_lower_fresh_air_cooling",
	]
	for flux in thermal_system.drain_phase3_shadow_flux_results():
		var room_id: int = int(flux.get("room_id", -1))
		var cause: String = String(flux.get("cause", ""))
		if phase3_canonical_interzone_heat_shadow_enabled \
				and cause == "thermal_upper_to_lower":
			_phase3_shadow_queue_canonical_interzone_heat(room_id, flux, dt)
			canonical_interzone_rooms[str(room_id)] = true
			continue
		if _phase3_canonical_multisurface_active() \
				and cause in canonical_wall_causes:
			# F3.3r2b owns the future physical surface path. Never enqueue the
			# lumped wall/ambient requests in parallel.
			continue
		if phase3_canonical_wall_ambient_shadow_enabled \
				and not _phase3_canonical_multisurface_active() \
				and cause in canonical_wall_causes:
			var legacy_by_cause: Dictionary = canonical_wall_legacy_by_room.get(
				str(room_id), {}
			).duplicate(true)
			legacy_by_cause[cause] = float(legacy_by_cause.get(cause, 0.0)) \
					+ maxf(0.0, float(flux.get("sensible_enthalpy_kj", 0.0)))
			canonical_wall_legacy_by_room[str(room_id)] = legacy_by_cause
			continue
		if phase3_canonical_combustion_shadow_enabled:
			if cause == "combustion_convective_heat":
				canonical_heat_by_room[str(room_id)] = flux.duplicate(true)
				continue
			if cause == "plume_entrainment":
				canonical_plume_by_room[str(room_id)] = flux.duplicate(true)
				continue
		_phase3_shadow_add_thermal_request(flux)
	if phase3_canonical_interzone_heat_shadow_enabled and building != null:
		for raw_room_id in building.get_rooms().keys():
			var room_id: int = int(raw_room_id)
			if not canonical_interzone_rooms.has(str(room_id)):
				_phase3_shadow_queue_canonical_interzone_heat(room_id, {}, dt)
	if phase3_canonical_wall_ambient_shadow_enabled \
			and not _phase3_canonical_multisurface_active() \
			and building != null:
		for raw_room_id in building.get_rooms().keys():
			var wall_room_id: int = int(raw_room_id)
			_phase3_shadow_queue_canonical_wall_ambient(
				wall_room_id,
				canonical_wall_legacy_by_room.get(str(wall_room_id), {}),
				dt
			)
	if _phase3_canonical_multisurface_active() and building != null:
		for raw_room_id in building.get_rooms().keys():
			var surface_room: RoomModel = building.get_room(int(raw_room_id))
			if surface_room == null:
				continue
			if _phase3_prepare_canonical_multisurface_room(surface_room):
				_phase3_shadow_queue_canonical_multisurface_exchange(
					surface_room, dt
				)
	if not phase3_canonical_combustion_shadow_enabled:
		return
	for room_id in phase3_zone_mass_system.get_canonical_combustion_room_ids():
		var plume_flux: Dictionary = canonical_plume_by_room.get(str(room_id), {})
		if phase3_canonical_plume_shadow_enabled and building != null:
			var room: RoomModel = building.get_room(room_id)
			var canonical_input: Dictionary = \
					phase3_zone_mass_system.get_canonical_thermodynamic_input(
						room, thermal_system.ambient_temp_c()
					)
			if phase3_coupled_plume_shadow_enabled \
					and _phase3_canonical_multisurface_active():
				plume_flux = thermal_system.preview_phase3_coupled_plume_flux(
					room,
					canonical_input,
					phase3_zone_mass_system.get_canonical_combustion_transaction(
						room_id
					),
					dt
				)
			else:
				var include_heskestad_source_term: bool = false
				if phase3_canonical_post_opening_coupling_shadow_enabled:
					var counterflow_request: Dictionary = \
							phase3_zone_mass_system.get_canonical_exterior_counterflow_request(
								room_id
							)
					include_heskestad_source_term = float(
						counterflow_request.get("requested_exchange_kg", 0.0)
					) > 0.000000001
				plume_flux = thermal_system.preview_phase3_canonical_plume_flux(
					room, canonical_input, dt, include_heskestad_source_term
				)
		phase3_zone_mass_system.finalize_canonical_combustion_bundle(
			room_id,
			canonical_heat_by_room.get(str(room_id), {}),
			plume_flux,
			"%.6f" % sim_time_s
		)


func _phase3_canonical_multisurface_active() -> bool:
	return phase3_canonical_zone_shadow_enabled \
			and phase3_canonical_persistence_shadow_enabled \
			and phase3_canonical_combustion_shadow_enabled \
			and phase3_canonical_multisurface_shadow_enabled


func _phase3_prepare_canonical_multisurface_room(room: RoomModel) -> bool:
	if room == null or not _phase3_canonical_multisurface_active():
		return false
	var ambient_c: float = thermal_system.ambient_temp_c()
	var thermo: Dictionary = phase3_zone_mass_system.get_canonical_thermodynamic_input(
		room, ambient_c
	)
	if thermo.is_empty() or not bool(thermo.get("valid", false)):
		return false
	var prepared: Dictionary = phase3_zone_mass_system.prepare_canonical_multisurface_room(
		room.id,
		{
			"floor_area_m2": room.floor_area_m2(),
			"perimeter_m": 2.0 * (room.width_m + room.length_m),
			"height_m": room.height_m,
			"interface_m": float(thermo.get("interface_m", room.height_m)),
		},
		{
			"conductivity_kw_m_k": room.wall_k_kw_m_k,
			"density_kg_m3": room.wall_rho_kg_m3,
			"cp_kj_kg_k": room.wall_cp_kj_kg_k,
			"thickness_m": room.wall_thickness_m,
			"emissivity": upper_radiative_loss_emissivity,
		},
		ambient_c
	)
	return bool(prepared.get("valid", false))


func _phase3_shadow_queue_canonical_multisurface_exchange(
		room: RoomModel,
		dt: float
	) -> void:
	if room == null:
		return
	var ambient_c: float = thermal_system.ambient_temp_c()
	var thermo: Dictionary = phase3_zone_mass_system.get_canonical_thermodynamic_input(
		room, ambient_c
	)
	if thermo.is_empty() or not bool(thermo.get("valid", false)):
		return
	var upper_temp_c: float = float(thermo.get("temp_upper_c", ambient_c))
	var radiation_activation: float = 0.0
	if upper_radiative_loss_enabled and upper_temp_c > upper_radiative_loss_start_c:
		radiation_activation = clampf(
			(upper_temp_c - upper_radiative_loss_start_c)
			/ maxf(1.0, max_upper_temp_c - upper_radiative_loss_start_c),
			0.0,
			1.0
		)
	var surface_boundaries: Dictionary = \
			phase3_zone_mass_system.build_canonical_surface_boundary_context(
				room.phase3_surface_boundaries,
				building.outside_temp_c if building != null else ambient_c
			)
	var preview: Dictionary = \
			phase3_zone_mass_system.preview_canonical_multisurface_exchange(
				room.id,
				{
					"dt_s": dt,
					"upper_temp_c": upper_temp_c,
					"lower_temp_c": float(
						thermo.get("temp_lower_c", ambient_c)
					),
					"upper_h_kw_m2_k": thermal_system.h_conv_int_kw_m2_k,
					"lower_h_kw_m2_k": thermal_system.h_conv_int_kw_m2_k,
					"upper_gas_emissivity": (
						upper_radiative_loss_emissivity
						* radiation_activation
					),
					"lower_gas_emissivity": 0.0,
					"exterior_by_surface": surface_boundaries.get(
						"exterior_by_surface", {}
					),
					"boundary_metadata_complete_flag": float(
						surface_boundaries.get(
							"boundary_metadata_complete_flag", 0.0
						)
					),
					"adiabatic_surface_count": float(
						surface_boundaries.get(
							"adiabatic_surface_count", 4.0
						)
					),
					"exterior_fraction_sum": float(
						surface_boundaries.get(
							"exterior_fraction_sum", 0.0
						)
					),
					"inter_room_fraction_sum": float(
						surface_boundaries.get(
							"inter_room_fraction_sum", 0.0
						)
					),
					"adiabatic_fraction_sum": float(
						surface_boundaries.get(
							"adiabatic_fraction_sum", 4.0
						)
					),
					"unsupported_inter_room_surface_count": float(
						surface_boundaries.get(
							"unsupported_inter_room_surface_count", 0.0
						)
					),
				}
			)
	if not bool(preview.get("valid", false)):
		return
	phase3_zone_mass_system.queue_canonical_multisurface_exchange(
		room.id, preview, "%.6f" % sim_time_s
	)


func _phase3_shadow_queue_canonical_interzone_heat(
		room_id: int,
		legacy_flux: Dictionary,
		dt: float
	) -> void:
	if building == null:
		return
	var room: RoomModel = building.get_room(room_id)
	if room == null:
		return
	var canonical_input: Dictionary = phase3_zone_mass_system.get_canonical_thermodynamic_input(
		room, thermal_system.ambient_temp_c()
	)
	var preview: Dictionary = thermal_system.preview_phase3_canonical_interzone_heat_flux(
		canonical_input, dt
	)
	preview["legacy_requested_kj"] = maxf(
		0.0, float(legacy_flux.get("sensible_enthalpy_kj", 0.0))
	)
	if not phase3_zone_mass_system.queue_canonical_interzone_heat_transfer(
		room_id, preview, "%.6f" % sim_time_s
	):
		return
	var requested_kj: float = maxf(
		0.0, float(preview.get("sensible_enthalpy_kj", 0.0))
	)
	if requested_kj <= 0.0:
		return
	phase3_zone_mass_system.register_semantic_claim({
		"connection_id": "room:%d:interlayer" % room_id,
		"producer": "ThermalSystem",
		"transport_family": "thermal_upper_to_lower",
		"boundary_kind": "interlayer",
		"source_room_id": room_id,
		"destination_room_id": room_id,
		"source_zone": "upper",
		"destination_zone": "lower",
		"quantity": "enthalpy",
		"amount": requested_kj,
	})


func _phase3_shadow_queue_canonical_wall_ambient(
		room_id: int,
		legacy_requested: Dictionary,
		dt: float
	) -> void:
	if building == null:
		return
	var room: RoomModel = building.get_room(room_id)
	if room == null:
		return
	var ambient_c: float = thermal_system.ambient_temp_c()
	var canonical_input: Dictionary = phase3_zone_mass_system.get_canonical_thermodynamic_input(
		room, ambient_c
	)
	if canonical_input.is_empty():
		return
	canonical_input["reference_temp_c"] = ambient_c
	var context: Dictionary = thermal_system.build_phase3_canonical_wall_ambient_context(room)
	var wall_input: Dictionary = phase3_zone_mass_system.get_canonical_wall_ambient_input(
		room_id,
		float(context.get("wall_capacity_kj_k", 0.1)),
		ambient_c
	)
	var preview: Dictionary = thermal_system.preview_phase3_canonical_wall_ambient_flux(
		canonical_input, wall_input, context, dt
	)
	if not phase3_zone_mass_system.queue_canonical_wall_ambient_transfer(
		room_id, preview, legacy_requested, "%.6f" % sim_time_s
	):
		return
	for wall_claim in [
		{
			"family": "canonical_upper_wall_ambient",
			"source_zone": "upper",
			"amount": absf(float(preview.get("upper_wall_requested_kj", 0.0)))
					+ float(preview.get("upper_ambient_requested_kj", 0.0)),
		},
		{
			"family": "canonical_lower_wall_ambient",
			"source_zone": "lower",
			"amount": absf(float(preview.get("lower_wall_requested_kj", 0.0)))
					+ float(preview.get("lower_ambient_requested_kj", 0.0)),
		},
	]:
		if float(wall_claim.get("amount", 0.0)) <= 0.0:
			continue
		phase3_zone_mass_system.register_semantic_claim({
			"connection_id": "room:%d:canonical_wall_ambient" % room_id,
			"producer": "ThermalSystem",
			"transport_family": String(wall_claim.get("family", "")),
			"boundary_kind": "thermal_reservoir",
			"source_room_id": room_id,
			"destination_room_id": -1,
			"source_zone": String(wall_claim.get("source_zone", "upper")),
			"destination_zone": String(wall_claim.get("source_zone", "upper")),
			"quantity": "enthalpy",
			"amount": float(wall_claim.get("amount", 0.0)),
		})


func _phase3_shadow_add_thermal_request(flux: Dictionary) -> void:
	var mass_kg: float = maxf(0.0, float(flux.get("gas_mass_kg", 0.0)))
	var energy_kj: float = maxf(0.0, float(flux.get("sensible_enthalpy_kj", 0.0)))
	var o2_kg: float = maxf(0.0, float(flux.get("o2_kg", 0.0)))
	var species_kg: Dictionary = flux.get("species_kg", {})
	if mass_kg <= 0.0 and energy_kj <= 0.0 and o2_kg <= 0.0 and species_kg.is_empty():
		return
	var room_id: int = int(flux.get("room_id", -1))
	var cause: String = String(flux.get("cause", ""))
	var request_id: String = "%s:%d:%.6f" % [cause, room_id, sim_time_s]
	phase3_zone_mass_system.add_request(
		phase3_zone_mass_system.make_request(
			request_id,
			cause,
			int(flux.get("source_room_id", room_id)),
			int(flux.get("destination_room_id", room_id)),
			String(flux.get("source_zone", "lower")),
			String(flux.get("destination_zone", "upper")),
			mass_kg,
			energy_kj,
			o2_kg,
			species_kg
		)
	)
	var thermal_connection_id: String = "room:%d:interlayer" % room_id
	var thermal_boundary_kind: String = "interlayer"
	if cause == "combustion_convective_heat":
		thermal_connection_id = "chemical:%d:combustion" % room_id
		thermal_boundary_kind = "chemical_combustion"
	elif cause != "plume_entrainment" and cause != "thermal_upper_to_lower":
		thermal_connection_id = "room:%d:thermal_reservoir" % room_id
		thermal_boundary_kind = "thermal_reservoir"
	for quantity_entry in [
		{"quantity": "gas_mass", "amount": mass_kg},
		{"quantity": "enthalpy", "amount": energy_kj},
		{"quantity": "o2", "amount": o2_kg},
	]:
		phase3_zone_mass_system.register_semantic_claim({
			"connection_id": thermal_connection_id,
			"producer": "ThermalSystem",
			"transport_family": cause,
			"boundary_kind": thermal_boundary_kind,
			"source_room_id": int(flux.get("source_room_id", room_id)),
			"destination_room_id": int(flux.get("destination_room_id", room_id)),
			"source_zone": String(flux.get("source_zone", "lower")),
			"destination_zone": String(flux.get("destination_zone", "upper")),
			"quantity": String(quantity_entry.get("quantity", "")),
			"amount": float(quantity_entry.get("amount", 0.0)),
		})


func _phase3_shadow_collect_thermal_species_events() -> void:
	for event in thermal_system.drain_phase3_shadow_thermal_species_events():
		if phase3_canonical_interior_opening_shadow_enabled \
				and _phase3_shadow_event_is_horizontal_interior_opening(event):
			continue
		phase3_zone_mass_system.apply_thermal_species_event(event)


func _phase3_shadow_collect_oxygen_requests() -> void:
	var fluxes: Array[Dictionary] = oxygen_exchange_system.drain_phase3_shadow_flux_results()
	var persistent_demand_by_room: Dictionary = {}
	for flux in fluxes:
		var o2_kg: float = maxf(0.0, float(flux.get("o2_kg", 0.0)))
		if o2_kg <= 0.0:
			continue
		var room_id: int = int(flux.get("room_id", -1))
		var cause: String = String(flux.get("cause", ""))
		if phase3_canonical_combustion_shadow_enabled \
				and cause.begins_with("combustion_o2_"):
			# F3.2b1 owns O2 inside the closed atomic combustion bundle.
			continue
		if phase3_canonical_persistence_shadow_enabled \
				and cause.begins_with("combustion_o2_"):
			persistent_demand_by_room[str(room_id)] = maxf(
				float(persistent_demand_by_room.get(str(room_id), 0.0)), o2_kg
			)
			continue
		var source_zone: String = String(flux.get("source_zone", "upper"))
		var request_id: String = "%s:%d:%s:%.6f" % [
			cause, room_id, source_zone, sim_time_s
		]
		phase3_zone_mass_system.add_request(
			phase3_zone_mass_system.make_request(
				request_id,
				cause,
				room_id,
				phase3_zone_mass_system.EXTERIOR_ID,
				source_zone,
				source_zone,
				0.0,
				0.0,
				o2_kg,
				{}
			)
		)
		phase3_zone_mass_system.register_semantic_claim({
			"connection_id": "chemical:%d:combustion" % room_id,
			"producer": "OxygenExchangeSystem",
			"transport_family": cause,
			"boundary_kind": "chemical_combustion",
			"source_room_id": room_id,
			"destination_room_id": phase3_zone_mass_system.EXTERIOR_ID,
			"source_zone": source_zone,
			"destination_zone": source_zone,
			"quantity": "o2",
			"amount": o2_kg,
		})
	if phase3_canonical_combustion_shadow_enabled \
			or not phase3_canonical_persistence_shadow_enabled:
		return
	for room_key in persistent_demand_by_room.keys():
		var room_id: int = int(room_key)
		var room: RoomModel = building.get_room(room_id) if building != null else null
		var o2_kg: float = float(persistent_demand_by_room[room_key])
		if room != null and room.o2_consumed_fire_kg_step > 0.0:
			o2_kg = room.o2_consumed_fire_kg_step
		if o2_kg <= 0.0:
			continue
		var cause: String = "combustion_o2_canonical_upper_sink"
		phase3_zone_mass_system.add_request(
			phase3_zone_mass_system.make_request(
				"%s:%d:upper:%.6f" % [cause, room_id, sim_time_s],
				cause,
				room_id,
				phase3_zone_mass_system.EXTERIOR_ID,
				"upper",
				"upper",
				0.0,
				0.0,
				o2_kg,
				{}
			)
		)
		phase3_zone_mass_system.register_semantic_claim({
			"connection_id": "chemical:%d:combustion" % room_id,
			"producer": "OxygenExchangeSystem",
			"transport_family": cause,
			"boundary_kind": "chemical_combustion",
			"source_room_id": room_id,
			"destination_room_id": phase3_zone_mass_system.EXTERIOR_ID,
			"source_zone": "upper",
			"destination_zone": "upper",
			"quantity": "o2",
			"amount": o2_kg,
		})


func _phase3_shadow_collect_species_requests(dt: float) -> void:
	var species_results: Array[Dictionary] = \
			combustion_system.drain_phase3_shadow_species_results()
	if phase3_canonical_combustion_shadow_enabled:
		var species_by_room: Dictionary = {}
		for result in species_results:
			species_by_room[str(int(result.get("room_id", -1)))] = result
		for raw_room_id in building.get_rooms().keys():
			var room_id: int = int(raw_room_id)
			var room: RoomModel = building.get_room(room_id)
			if room == null:
				continue
			var combustion_context: Dictionary = _build_room_combustion_context(room_id)
			if phase3_canonical_post_opening_coupling_shadow_enabled:
				var counterflow_context: Dictionary = \
						phase3_zone_mass_system.get_canonical_exterior_counterflow_request(
							room_id
						)
				combustion_context["phase3_post_opening_coupling_enabled"] = true
				combustion_context["phase3_post_opening_counterflow_exchange_kg"] = \
						float(counterflow_context.get("requested_exchange_kg", 0.0))
				combustion_context["phase3_post_opening_counterflow_incoming_o2_kg"] = \
						float(counterflow_context.get("requested_incoming_o2_kg", 0.0))
			var transaction: Dictionary = \
					combustion_system.evaluate_phase3_canonical_combustion_step(
						room,
						dt,
						combustion_context,
						phase3_zone_mass_system.get_canonical_combustion_input(room_id),
						phase3_zone_mass_system.get_persistent_combustion_state(room_id),
						species_by_room.get(str(room_id), {})
					)
			if not transaction.is_empty():
				var staged: bool = \
						phase3_zone_mass_system.stage_canonical_combustion_transaction(
							transaction
						)
				if staged and _phase3_canonical_multisurface_active():
					_phase3_prepare_canonical_multisurface_room(room)
		return
	for result in species_results:
		var room_id: int = int(result.get("room_id", -1))
		var cause: String = String(result.get("cause", "combustion_species_source"))
		for zone_name in ["upper", "lower"]:
			var species: Dictionary = result.get(zone_name + "_species_kg", {})
			var species_total_kg: float = 0.0
			for species_name in species.keys():
				species_total_kg += maxf(0.0, float(species[species_name]))
			if species_total_kg <= 0.0:
				continue
			var request_id: String = "%s:%d:%s:%.6f" % [
				cause, room_id, zone_name, sim_time_s
			]
			phase3_zone_mass_system.add_request(
				phase3_zone_mass_system.make_request(
					request_id,
					cause,
					phase3_zone_mass_system.EXTERIOR_ID,
					room_id,
					zone_name,
					zone_name,
					0.0,
					0.0,
					0.0,
					species
				)
			)
			for species_name in species.keys():
				phase3_zone_mass_system.register_semantic_claim({
					"connection_id": "chemical:%d:combustion_species" % room_id,
					"producer": "CombustionSystem",
					"transport_family": cause,
					"boundary_kind": "chemical_combustion",
					"source_room_id": phase3_zone_mass_system.EXTERIOR_ID,
					"destination_room_id": room_id,
					"source_zone": zone_name,
					"destination_zone": zone_name,
					"quantity": String(species_name),
					"amount": maxf(0.0, float(species[species_name])),
				})


func _phase3_shadow_collect_doorway_species_requests() -> void:
	for result in gas_exchange_system.drain_phase3_shadow_doorway_species_results():
		if phase3_canonical_interior_opening_shadow_enabled \
				and _phase3_shadow_event_is_horizontal_interior_opening(result):
			continue
		phase3_zone_mass_system.apply_atomic_transport_event(
			result,
			"GasExchangeSystem",
			"doorway_bulk",
			"interior_opening"
		)


func _phase3_shadow_collect_parcel_species_events() -> void:
	for event in gas_exchange_system.drain_phase3_shadow_parcel_events():
		if phase3_canonical_interior_opening_shadow_enabled \
				and _phase3_shadow_event_is_horizontal_interior_opening(event):
			continue
		phase3_zone_mass_system.apply_species_transit_event(event)


func _phase3_shadow_collect_immediate_species_events() -> void:
	for event in gas_exchange_system.drain_phase3_shadow_immediate_species_events():
		if phase3_canonical_interior_opening_shadow_enabled \
				and _phase3_shadow_event_is_horizontal_interior_opening(event):
			continue
		phase3_zone_mass_system.apply_immediate_species_event(event)


func _phase3_shadow_event_is_horizontal_interior_opening(event: Dictionary) -> bool:
	if building == null:
		return false
	var source_room_id: int = int(event.get("source_room_id", -1))
	var destination_room_id: int = int(event.get("destination_room_id", -1))
	if source_room_id < 0 or destination_room_id < 0 \
			or source_room_id == destination_room_id:
		return false
	for op in building.get_openings():
		if op == null or op.is_exterior_opening() or op.is_vertical \
				or op.open_fraction <= 0.0:
			continue
		var connects_pair: bool = (
			op.a == source_room_id and op.b == destination_room_id
		) or (
			op.a == destination_room_id and op.b == source_room_id
		)
		if not connects_pair:
			continue
		var room_a: RoomModel = building.get_room(op.a)
		var room_b: RoomModel = building.get_room(op.b)
		if room_a != null and room_b != null \
				and absf(room_a.floor_level_z_m - room_b.floor_level_z_m) <= 0.01:
			return true
	return false


func _phase3_shadow_collect_exterior_purge_events() -> void:
	for event in gas_exchange_system.drain_phase3_shadow_exterior_purge_events():
		if phase3_canonical_exterior_boundary_shadow_enabled \
				and phase3_zone_mass_system.suppress_legacy_pressure_purge_event(event):
			continue
		phase3_zone_mass_system.apply_exterior_purge_event(event)


func _build_state_context() -> Dictionary:
	return {
		"building": building,
		"smoke_model": smoke_model,
		"combustion_system": combustion_system,
		"sim_time_s": sim_time_s,
		"smoke_generated_total_kg": smoke_generated_total_kg,
		"smoke_vented_total_kg": smoke_vented_total_kg,
		"smoke_deposited_total_kg": smoke_deposited_total_kg,
		"smoke_in_transit_kg": gas_exchange_system.get_smoke_in_transit_kg(),
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
		"compute_co2_upper_ppm_callable": Callable(thermal_system, "compute_co2_upper_ppm"),
		"compute_co2_upper_ppm_mass_callable": Callable(thermal_system, "compute_co2_upper_ppm_mass"),
		"compute_co2_lower_ppm_callable": Callable(thermal_system, "compute_co2_lower_ppm"),
		"compute_hcn_ppm_callable": Callable(thermal_system, "compute_hcn_ppm"),
		"compute_hcn_upper_ppm_callable": Callable(thermal_system, "compute_hcn_upper_ppm"),
		"compute_hcn_lower_ppm_callable": Callable(thermal_system, "compute_hcn_lower_ppm"),
		"compute_hcl_ppm_callable": Callable(thermal_system, "compute_hcl_ppm"),
		"compute_acrolein_ppm_callable": Callable(thermal_system, "compute_acrolein_ppm"),
		"compute_formaldehyde_ppm_callable": Callable(thermal_system, "compute_formaldehyde_ppm"),
		"is_quiescent_callable": Callable(thermal_system, "is_room_quiescent"),
		"window_open_max_callable": Callable(self, "_window_open_max_for_room"),
		"outside_open_path_factor_callable": Callable(self, "_outside_open_path_factor_for_room"),
		"kawagoe_factor_callable": Callable(self, "_kawagoe_factor_for_room"),
		"energy_budget": thermal_system.get_energy_budget() if energy_budget_enabled else {},
		"conservation_max_violation_frac": _conservation_max_violation_frac,
		"global_carbon_error_kg": global_carbon_error_kg,
		"global_carbon_preclamp_excess_kg": global_carbon_preclamp_excess_kg,
		"global_carbon_postclamp_excess_kg": global_carbon_postclamp_excess_kg,
		"global_carbon_transport_residual_kg": global_carbon_transport_residual_kg,
		"two_zone_solver_enabled": two_zone_solver_enabled,
		"two_zone_opening_flow_enabled": two_zone_solver_enabled and two_zone_opening_flow_enabled,
		"phase3_zone_diagnostics_enabled": phase3_zone_diagnostics_enabled,
		"phase3_zone_diagnostics": _phase3_zone_diag_export(),
		"phase3_canonical_zone_shadow_enabled": phase3_canonical_zone_shadow_enabled,
		"phase3_canonical_exterior_boundary_shadow_enabled": \
				phase3_canonical_exterior_boundary_shadow_enabled,
		"phase3_canonical_persistence_shadow_enabled": \
				phase3_canonical_persistence_shadow_enabled,
		"phase3_canonical_combustion_shadow_enabled": \
				phase3_canonical_combustion_shadow_enabled,
		"phase3_canonical_pressure_relaxation_shadow_enabled": \
				phase3_canonical_pressure_relaxation_shadow_enabled,
		"phase3_canonical_plume_shadow_enabled": \
				phase3_canonical_plume_shadow_enabled,
		"phase3_canonical_interzone_heat_shadow_enabled": \
				phase3_canonical_interzone_heat_shadow_enabled,
		"phase3_canonical_wall_ambient_shadow_enabled": \
				phase3_canonical_wall_ambient_shadow_enabled,
		"phase3_canonical_multisurface_shadow_enabled": \
				phase3_canonical_multisurface_shadow_enabled,
		"phase3_coupled_plume_shadow_enabled": \
				phase3_coupled_plume_shadow_enabled,
		"phase3_canonical_fire_proposal_shadow_enabled": \
				phase3_canonical_fire_proposal_shadow_enabled,
		"phase3_canonical_fire_products_shadow_enabled": \
				phase3_canonical_fire_products_shadow_enabled,
		"phase3_canonical_exterior_counterflow_shadow_enabled": \
				phase3_canonical_exterior_counterflow_shadow_enabled,
		"phase3_canonical_post_opening_coupling_shadow_enabled": \
				phase3_canonical_post_opening_coupling_shadow_enabled,
		"phase3_canonical_interior_opening_shadow_enabled": \
				phase3_canonical_interior_opening_shadow_enabled,
		"phase3_canonical_interior_pressure_shadow_enabled": \
				phase3_canonical_interior_pressure_shadow_enabled,
		"phase3_enthalpy_residence_diagnostics_enabled": \
				phase3_enthalpy_residence_diagnostics_enabled,
		"phase3_mass_residence_diagnostics_enabled": \
				phase3_mass_residence_diagnostics_enabled,
		"phase3_connection_residence_diagnostics_enabled": \
				phase3_connection_residence_diagnostics_enabled,
		"phase3_cfast_buoyancy_destination_shadow_enabled": \
				phase3_cfast_buoyancy_destination_shadow_enabled,
		"phase3_canonical_zone_shadow": phase3_zone_mass_system.get_results() \
				if phase3_canonical_zone_shadow_enabled else {},
		"ambient_temp_c": thermal_system.ambient_temp_c(),
		"phase3_pressure_canonical_enabled": phase3_thermodynamic_pressure_enabled \
				and phase3_pressure_canonical_enabled,
		"fire_o2_mode": fire_o2_mode,
		"fire_o2_effective_mode": _resolve_fire_o2_mode(),
		"fire_o2_mass_tracking_enabled": fire_o2_mass_tracking_enabled,
		"doorway_thermal_counterflow_enabled": doorway_thermal_counterflow_enabled,
		"doorway_thermal_counterflow_o2_return_fraction": doorway_thermal_counterflow_o2_return_fraction,
		"canonical_doorway_exchange_enabled": canonical_doorway_exchange_enabled,
		"phase3_conservative_lower_return_enabled": phase3_conservative_lower_return_enabled,
		"step_time_us": _step_time_us,
	}


func _build_gas_exchange_hooks() -> Dictionary:
	return {
		"effective_hot_layer_height_callable": Callable(thermal_system, "flow_interface_height_m"),
		"remove_upper_layer_fraction_callable": Callable(thermal_system, "remove_upper_layer_fraction"),
		"sync_room_upper_layer_callable": Callable(self, "_sync_room_upper_layer_from_gas_exchange"),
		"compute_interroom_transfer_temp_callable": Callable(thermal_system, "compute_interroom_transfer_temp_c"),
		"outside_open_path_factor_callable": Callable(self, "_outside_open_path_factor_for_room"),
		"build_interior_opening_flow_state_callable": Callable(thermal_system, "build_interior_opening_flow_state"),
		"opening_flow_cache": _opening_flow_cache
	}


func _build_oxygen_exchange_hooks() -> Dictionary:
	return {
		"effective_hot_layer_height_callable": Callable(thermal_system, "flow_interface_height_m"),
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
		"effective_hot_layer_height_callable": Callable(thermal_system, "flow_interface_height_m"),
		"estimate_temperature_callable": Callable(thermal_system, "estimate_temperature_at_height_m"),
		"remove_upper_layer_fraction_callable": Callable(thermal_system, "remove_upper_layer_fraction"),
		"sync_room_upper_layer_callable": Callable(self, "_sync_room_upper_layer_from_hvac"),
		"ambient_temp_callable": Callable(thermal_system, "ambient_temp_c"),
		"two_zone_opening_flow_enabled": two_zone_solver_enabled and two_zone_opening_flow_enabled,
		"phase2h_o2_doorway_two_zone_enabled": phase2h_o2_doorway_two_zone_enabled,
		"hvac_two_zone_o2_enabled": hvac_two_zone_o2_enabled
	}


func _sync_room_upper_layer_from_gas_exchange(room: RoomModel, dt: float) -> void:
	thermal_system.sync_room_upper_layer(room, dt, "gas_exchange_sync")


func _sync_room_upper_layer_from_hvac(room: RoomModel, dt: float) -> void:
	thermal_system.sync_room_upper_layer(room, dt, "hvac_sync")

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
	phase3_zone_mass_system.reset()
	oxygen_exchange_system.reset()
	hvac_system.reset()
	_reset_log_file()

	if auto_ignite_on_ready:
		ignite_room(ignition_room_id)
	_force_log_initial_snapshot()

	print(log_writer.resolve_log_file_path())


func apply_runtime_options(options: Dictionary) -> void:
	if typeof(options) != TYPE_DICTIONARY:
		return

	var needs_sync: bool = false
	if options.has("glass_break_mode"):
		glass_break_mode = clampi(
				int(options.get("glass_break_mode", int(glass_break_mode))),
				GlassBreakMode.DISABLED,
				GlassBreakMode.PROBABILISTIC)
		needs_sync = true

	if needs_sync and is_ready_for_validation():
		_sync_auxiliary_services()
		glass_failure_system.reset()


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
	phase3_zone_mass_system.reset()
	oxygen_exchange_system.reset()
	hvac_system.reset()
	smoke_generated_total_kg = 0.0
	smoke_vented_total_kg = 0.0
	smoke_deposited_total_kg = 0.0
	suppression_water_applied_l = 0.0
	suppression_cooling_total_kj = 0.0
	_active_suppression_by_room.clear()
	_phase3_zone_diag_start.clear()
	_phase3_zone_diag_checkpoint.clear()
	_phase3_zone_diag_step.clear()
	# SF-CBAL global: resetear para que el próximo paso recapture el inventario inicial.
	_cbal_initialized = false
	_cbal_c_initial_kg = 0.0
	global_carbon_error_kg = 0.0
	global_carbon_preclamp_excess_kg = 0.0
	global_carbon_postclamp_excess_kg = 0.0
	global_carbon_transport_residual_kg = 0.0
	_cbal_hvac_c_exhausted_kg = 0.0
	_layer_interface_divergence_s.clear()
	_layer_interface_warning_rooms.clear()
	sim_time_s = 0.0
	is_finished = false
	_extinction_countdown = extinction_grace_s
	_prev_open_fracs.clear()
	_graphs_launched = false
	_last_graphs_dir = ""
	_last_graph_generation_ok = false
	_graph_gen_pid = -1
	_html_dashboard_pid = -1
	_graph_gen_latest_path = ""
	_exit_graphs_suppressed = false
	_room_peak_hrr.clear()
	_room_peak_temp.clear()
	_room_peak_co_upper.clear()
	_room_peak_hcn_upper.clear()
	_room_min_o2.clear()
	_room_min_visibility.clear()
	_room_peak_fed.clear()
	_room_min_svv.clear()
	_room_peak_hrr_time.clear()
	_room_peak_temp_time.clear()
	_room_peak_co_upper_time.clear()
	_room_peak_hcn_upper_time.clear()
	_room_min_o2_time.clear()
	_room_min_visibility_time.clear()
	_room_peak_fed_time.clear()
	_room_min_svv_time.clear()
	_last_technical_summary.clear()
	glass_failure_system.reset()
	thermal_system.reset_wall_temps()
	_targets.clear()
	if building != null:
		building.reset_detectors()
		building.reset_victims()

	for room_id in building.get_rooms().keys():
		var room: RoomModel = building.get_room(room_id)
		_reset_room_state(room)

	combustion_system.bootstrap_building(building)
	if building != null and building.sim_stop_time_s > 0.0:
		sim_duration_limit_s = building.sim_stop_time_s
	_reset_log_file()

	if ignite_initial_fire:
		ignite_room(start_ignition_room_id)
	_force_log_initial_snapshot()

func _reset_room_state(room: RoomModel) -> void:
	if room == null:
		return

	var ambient_c: float = thermal_system.ambient_temp_c()
	room.reset_dynamic_state(ambient_c, o2_nominal)

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

	var _t0_us: int = Time.get_ticks_usec()
	var dt: float = sim_fixed_dt if sim_fixed_dt > 0.0 else maxf(0.0, delta * time_scale)
	if dt <= 0.0:
		return

	sim_time_s += dt

	# Límite de tiempo configurado desde el editor.
	if sim_duration_limit_s > 0.0 and sim_time_s >= sim_duration_limit_s:
		if not is_finished:
			is_finished = true
			_on_sim_finished()
		return

	# Actualizar open_fraction_smooth de todas las aperturas.
	# Exteriores: suavizado exponencial con tau configurable (evita saltos de presión/O₂/humo).
	# Interiores: mirror directo (sin suavizado, usan effective_open_fraction para thermal gap).
	_step_exterior_opening_smooth(dt)

	# Pre-computar el estado de flujo de cada abertura interior una sola vez,
	# con las condiciones de sala al inicio de este paso. Esto garantiza que
	# ThermalSystem y OxygenExchangeSystem operen sobre la misma "realidad física"
	# dentro del mismo timestep, evitando que uno de ellos vea estados ya
	# modificados por el otro.
	_opening_flow_cache = _build_opening_flow_cache()

	# SF-CBAL: capturar inventario inicial antes de cualquier física.
	_ensure_carbon_balance_initialized()
	_phase3_zone_diag_begin_step()
	if phase3_canonical_zone_shadow_enabled:
		phase3_zone_mass_system.begin_step(
			building, phase3_canonical_persistence_shadow_enabled
		)
		if phase3_canonical_exterior_boundary_shadow_enabled:
			phase3_zone_mass_system.queue_canonical_exterior_boundary_requests(
				building,
				dt,
				thermal_system.ambient_temp_c(),
				building.outside_o2,
				window_leakage_area_m2,
				pressure_vent_threshold_pa,
				Phase3ZoneMassSystemScript.EXTERIOR_DISCHARGE_COEFF,
				phase3_canonical_pressure_relaxation_shadow_enabled
			)
			if phase3_canonical_exterior_counterflow_shadow_enabled:
				phase3_zone_mass_system.queue_canonical_exterior_counterflow_requests(
					building,
					dt,
					thermal_system.ambient_temp_c(),
					building.outside_o2,
					Phase3ZoneMassSystemScript.EXTERIOR_DISCHARGE_COEFF
				)
		if phase3_canonical_interior_opening_shadow_enabled:
			phase3_zone_mass_system.queue_canonical_interior_opening_requests(
				building,
				dt,
				thermal_system.ambient_temp_c(),
				Phase3ZoneMassSystemScript.EXTERIOR_DISCHARGE_COEFF,
				phase3_canonical_interior_pressure_shadow_enabled,
				false,
				false,
				phase3_cfast_buoyancy_destination_shadow_enabled
			)

	var pre_hrr_o2_step: bool = _uses_pre_hrr_oxygen_step()

	_step_pool_fires(dt)
	if pre_hrr_o2_step:
		_step_oxygen(dt)
		if phase3_canonical_zone_shadow_enabled:
			_phase3_shadow_collect_oxygen_requests()
		_phase3_zone_diag_record_stage("oxygen_exchange")
	if phase3_canonical_zone_shadow_enabled:
		combustion_system.begin_phase3_shadow_step(building)
	_step_fire(dt)
	if phase3_canonical_zone_shadow_enabled:
		if phase3_canonical_persistence_shadow_enabled:
			phase3_zone_mass_system.record_combustion_o2_probe(building)
		_phase3_shadow_collect_species_requests(dt)
	_step_co_oxidation(dt)
	_step_targets(dt)
	_phase3_zone_diag_record_stage("combustion")
	if not pre_hrr_o2_step:
		_step_oxygen(dt)
		if phase3_canonical_zone_shadow_enabled:
			_phase3_shadow_collect_oxygen_requests()
		_phase3_zone_diag_record_stage("oxygen_exchange")
	thermal_system.step(building, dt, {
		"outside_open_path_factor_callable": Callable(self, "_outside_open_path_factor_for_room"),
		"opening_flow_cache": _opening_flow_cache
	})
	if phase3_canonical_zone_shadow_enabled:
		_phase3_shadow_collect_thermal_requests(dt)
		_phase3_shadow_collect_thermal_species_events()
	_phase3_zone_diag_record_stage("thermal")
	# SF-R6 Phase 3: verificar conservación de transporte de contaminantes.
	if conservation_check_enabled:
		var _cons: Dictionary = zone_fire_solver.validate_conservation(
			building, thermal_system.get_transport_residuals(), dt
		)
		_conservation_max_violation_frac = float(_cons.get("conservation_max_violation_frac", 0.0))
	_step_suppression(dt)
	_step_steam_decay(dt)
	if glass_break_mode != GlassBreakMode.DISABLED:
		glass_failure_system.step(dt)
		for broken_idx in glass_failure_system.newly_broken_indices:
			_log_opening_event(broken_idx, "glass_break")
	_phase3_zone_diag_record_stage("suppression")
	if phase3_canonical_zone_shadow_enabled:
		gas_exchange_system.begin_phase3_shadow_step()
	_step_gas_exchange(dt)
	if phase3_canonical_zone_shadow_enabled:
		_phase3_shadow_collect_parcel_species_events()
		_phase3_shadow_collect_doorway_species_requests()
		_phase3_shadow_collect_immediate_species_events()
		_phase3_shadow_collect_exterior_purge_events()
	_phase3_zone_diag_record_stage("gas_exchange")
	_step_hvac(dt)
	_phase3_zone_diag_record_stage("hvac")
	_step_passive_fuel(dt)
	fire_spread_system.step(dt, Callable(self, "ignite_room"))
	_phase3_zone_diag_record_stage("other")
	if two_zone_solver_enabled:
		# M1: absorber los cambios termicos de sistemas legacy (HVAC/supresion/flujos)
		# como condiciones de contorno antes del clamp final.
		thermal_system.reconcile_two_zone_building(building, dt)
	_phase3_zone_diag_record_stage("reconcile")
	_clamp_rooms(dt)
	_phase3_zone_diag_record_stage("projection_clamp")
	if phase3_canonical_zone_shadow_enabled:
		phase3_zone_mass_system.finalize_step(building, thermal_system.ambient_temp_c())
	# Evaluar el estado final del paso, incluyendo cualquier pérdida por clamp.
	_check_carbon_balance()
	_check_layer_interface_guardrails(dt)
	_step_detectors(dt)
	_update_room_ceiling_jet_temps()  # BV-028: exportar ceiling_jet_temp_c a RoomModel
	_step_victims(dt)
	_detect_and_log_opening_events()
	_update_peak_tracking()
	_maybe_log_state()
	_step_time_us = Time.get_ticks_usec() - _t0_us

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
		"fire_co_vent_limited_o2_threshold": fire_co_vent_limited_o2_threshold,
		"fire_co_vent_limited_multiplier": fire_co_vent_limited_multiplier,
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
		"fire_hrr_global_multiplier": fire_hrr_global_multiplier,
		"fire_backdraft_pool_threshold_MJ": fire_backdraft_pool_threshold_MJ,
		"fire_backdraft_o2_max": fire_backdraft_o2_max,
		"fire_backdraft_temp_min_c": fire_backdraft_temp_min_c,
		"fire_backdraft_release_boost": fire_backdraft_release_boost,
		"fire_backdraft_hrr_multiplier": fire_backdraft_hrr_multiplier,
		"fire_backdraft_duration_s": fire_backdraft_duration_s,
		"fire_backdraft_cooldown_s": fire_backdraft_cooldown_s,
		"fire_backdraft_lfl": fire_backdraft_lfl,
		"fire_backdraft_ufl": fire_backdraft_ufl,
		"fire_backdraft_fuel_heat_kj_kg": fire_backdraft_fuel_heat_kj_kg,
		"fire_backdraft_fuel_gas_density": fire_backdraft_fuel_gas_density,
		"fire_backdraft_deflagration_overpressure_pa": fire_backdraft_deflagration_overpressure_pa,
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
		"fire_co_yield_force_kg_per_MJ": fire_co_yield_force_kg_per_MJ,
		"fire_co_phi_rate": fire_co_phi_rate,
		"fire_smolder_phi": fire_smolder_phi,
		"fire_co_afterburn_o2_threshold": fire_co_afterburn_o2_threshold,
		"fire_co_afterburn_max_boost": fire_co_afterburn_max_boost,
		"co2_base_yield_kg_per_MJ": co2_base_yield_kg_per_MJ,
		"co2_min_yield_kg_per_MJ": co2_min_yield_kg_per_MJ,
		"co2_phi_decay_rate": co2_phi_decay_rate,
		"hcn_base_yield_kg_per_MJ": hcn_base_yield_kg_per_MJ,
		"hcn_max_yield_kg_per_MJ": hcn_max_yield_kg_per_MJ,
		"kawagoe_limit_kw": kawagoe_limit_kw,
		"window_open_max": _window_open_max_for_room(room_id),
		"outside_open_factor": local_outside_open_factor,
		"outside_open_path_factor": outside_open_path_factor,
		"phase3_canonical_multisurface_shadow_enabled": \
				_phase3_canonical_multisurface_active(),
		"hrr_chi_rad_normal": hrr_chi_rad_normal,
		"hrr_chi_rad_low_o2": hrr_chi_rad_low_o2,
		"fire_o2_independent": fire_o2_independent,
		"fire_spread_enabled": fire_spread_enabled,
		"fire_o2_mode": fire_o2_mode,
		"fire_o2_upper_for_flame": fire_o2_upper_for_flame,
		"fire_o2_upper_hrr_blend": fire_o2_upper_hrr_blend,
		"fire_o2_lower_for_flame": fire_o2_lower_for_flame,
		"fire_o2_upper_min_for_flame": fire_o2_upper_min_for_flame,
		"fire_fds_extinction_enabled": fire_fds_extinction_enabled,
		"fire_fds_extinction_o2_limit_ambient": fire_fds_extinction_o2_limit_ambient,
		"fire_fds_extinction_ambient_c": fire_fds_extinction_ambient_c,
		"fire_fds_extinction_hot_gas_c": fire_fds_extinction_hot_gas_c,
		"fire_fds_extinction_hot_o2_floor": fire_fds_extinction_hot_o2_floor,
		"fire_fds_extinction_transition_width": fire_fds_extinction_transition_width,
		"fire_fds_extinction_pyrolysis_floor": fire_fds_extinction_pyrolysis_floor,
		"fire_intraroom_spread_enabled": fire_intraroom_spread_enabled,
		"fire_intraroom_view_factor": fire_intraroom_view_factor,
		"fire_intraroom_falloff_m": fire_intraroom_falloff_m,
		# Phase 2G — término fuente CO zona lower
		"phase2g_co_lower_source_enabled":  phase2g_co_lower_source_enabled,
		"phase2g_co_lower_source_fraction": phase2g_co_lower_source_fraction,
		"phase2g_co_lower_source_guard":    phase2g_co_lower_source_guard,
		"hot_layer_interface_m": thermal_system.effective_hot_layer_height_m(
			building.get_room(room_id)
		) if building != null and building.get_room(room_id) != null else 2.5,
		# R2-2: two-zone flag for plume-entrainment O2 selection in CombustionSystem.
		"two_zone_solver_enabled": two_zone_solver_enabled,
		# Phase 5 M4: ILV upper-O2 throttle guard (leído por CombustionSystem.step_room_fire).
		"fire_o2_upper_throttle_enabled": fire_o2_upper_throttle_enabled,
		"fire_o2_upper_throttle_critical": fire_o2_upper_throttle_critical,
		# M5: post-backdraft HRR cut guard (leído por CombustionSystem.step_room_fire).
		"fire_post_bd_hrr_cut_enabled": fire_post_bd_hrr_cut_enabled,
		# SF-D2: consumo estequiométrico O2 (default-off).
		"fire_o2_stoich_consumption_enabled": fire_o2_stoich_consumption_enabled,
		"phase3_canonical_zone_shadow_enabled": phase3_canonical_zone_shadow_enabled,
		"phase3_canonical_fire_proposal_shadow_enabled": \
				phase3_canonical_fire_proposal_shadow_enabled,
		"phase3_canonical_fire_products_shadow_enabled": \
				phase3_canonical_fire_products_shadow_enabled,
	}

# ============================================================
# SUAVIZADO DE APERTURAS EXTERIORES
# ============================================================

func _step_exterior_opening_smooth(dt: float) -> void:
	if building == null:
		return
	var blend: float = 1.0
	if exterior_opening_smooth_tau_s > 0.001:
		blend = 1.0 - exp(-dt / exterior_opening_smooth_tau_s)
	for op in building.get_openings():
		if not op.is_exterior_opening():
			op.open_fraction_smooth = op.open_fraction
			continue
		if op.open_fraction_smooth < 0.0:
			op.open_fraction_smooth = op.open_fraction
		else:
			op.open_fraction_smooth = lerpf(op.open_fraction_smooth, op.open_fraction, blend)


# ============================================================
# INTERCAMBIO DE GASES
# ============================================================

func _step_gas_exchange(dt: float) -> void:
	if building == null:
		return

	# 1.5A: resetear mdot_vent_kg_s antes de que los sistemas lo acumulen
	for room in building.get_rooms().values():
		if room != null:
			room.mdot_vent_kg_s = 0.0

	var hooks: Dictionary = _build_gas_exchange_hooks()
	var use_canonical_pressure: bool = phase3_thermodynamic_pressure_enabled \
			and phase3_pressure_canonical_enabled
	if use_canonical_pressure:
		gas_exchange_system.step_thermodynamic_pressure(building, dt)
	var pressure_result: Dictionary = gas_exchange_system.step_pressure_venting(building, dt, hooks)
	smoke_vented_total_kg += float(pressure_result.get("smoke_vented_kg", 0.0))
	# Phase 3: campo paralelo de presión termodinámica (no-op cuando flag=false).
	if not use_canonical_pressure:
		gas_exchange_system.step_thermodynamic_pressure(building, dt)

	# SF-AUD-036: PPV mechanical ventilation
	var ppv_result: Dictionary = gas_exchange_system.step_ppv(building, dt, hooks)
	smoke_vented_total_kg += float(ppv_result.get("ppv_smoke_purged_kg", 0.0))

	var smoke_result: Dictionary = gas_exchange_system.step_smoke(building, smoke_model, dt, hooks)
	smoke_generated_total_kg += float(smoke_result.get("smoke_generated_kg", 0.0))
	smoke_vented_total_kg += float(smoke_result.get("smoke_vented_kg", 0.0))
	smoke_deposited_total_kg += float(smoke_result.get("smoke_deposited_kg", 0.0))


func _step_hvac(dt: float) -> void:
	if building == null or hvac_system == null:
		return
	var result: Dictionary = hvac_system.step(building, dt, _build_hvac_hooks())
	smoke_vented_total_kg += float(result.get("smoke_exhausted_kg", 0.0))
	# SF-CBAL: acumular carbono exhaustado permanentemente por HVAC.
	_cbal_hvac_c_exhausted_kg += float(result.get("c_exhausted_kg", 0.0))


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

	# SF-AUD-017: vapor generado por evaporación del agua del chorro.
	# La energía de enfriamiento ya está contabilizada en cooling_kj (sin cambio);
	# solo añadimos el seguimiento de masa de vapor para exportación y futuros efectos.
	room.steam_kg += water_l * maxf(0.0, suppression_evaporation_fraction)

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

	thermal_system.sync_room_upper_layer(room, dt, "suppression_sync")
	thermal_system.update_room_layer_150c(room, dt)


# SF-AUD-017: decaimiento exponencial del vapor — condensación + arrastre ventilatorio.
# Se llama una vez por paso de simulación sobre todas las salas; el vapor converge a 0
# con constante de tiempo 1/suppression_steam_condensation_rate segundos.
func _step_steam_decay(dt: float) -> void:
	if building == null or dt <= 0.0:
		return
	var rate: float = maxf(0.0, suppression_steam_condensation_rate)
	if rate == 0.0:
		return
	for room_id in building.get_rooms().keys():
		var room: RoomModel = building.get_room(int(room_id))
		if room == null or room.steam_kg <= 0.0:
			continue
		room.steam_kg = maxf(0.0, room.steam_kg - room.steam_kg * rate * dt)


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
## SF-AUD-035: oxidación de CO en la capa caliente (upper layer).
## Cuando la capa superior supera co_oxidation_temp_min_c y hay suficiente O2,
## el CO se oxida parcialmente a CO2 (CO + ½O2 → CO2).
## La tasa co_oxidation_rate_per_s es una constante empírica de 1er orden.
## Pitts (NIST TN 1603): a T>700°C y O2>5%, la vida media del CO es ~0.5-1 s.
# ============================================================
# STEP TARGETS  — SF-AUD-029
# ============================================================
# Calcula el flujo neto incidente sobre cada TargetModel desde
# la capa superior caliente de su sala: radiación S-B con
# factor de visión (angle_factor) y emisividad superficial.
# ============================================================
func _step_targets(dt: float) -> void:
	if _targets.is_empty():
		return
	const SIGMA_KW: float = 5.67e-11  # Stefan-Boltzmann [kW/m²/K⁴]
	for t in _targets:
		var room: RoomModel = building.get_room(t.room_id) if building != null else null
		if room == null:
			continue
		var T_upper_K: float = room.temp_upper_c + 273.15
		var T_tgt_K: float = t.temp_c + 273.15
		var q_incident: float = t.angle_factor * t.emissivity * SIGMA_KW * pow(T_upper_K, 4.0)
		var q_emit: float = t.emissivity * SIGMA_KW * pow(T_tgt_K, 4.0)
		t.qnet_kw_m2 = maxf(q_incident - q_emit, 0.0)
		if t.qnet_kw_m2 > t.peak_qnet_kw_m2:
			t.peak_qnet_kw_m2 = t.qnet_kw_m2
		# Masa térmica: calentamiento por flujo absorbido (modelo de capacitancia concentrada)
		var q_abs_kw: float = t.qnet_kw_m2 * t.area_m2
		t.temp_c = minf(t.temp_c + (q_abs_kw * dt) / t.thermal_mass_kj_k, 1200.0)
		if not t.ignited and t.temp_c >= t.ignition_temp_c:
			t.ignited = true


func _step_co_oxidation(dt: float) -> void:
	if not co_oxidation_enabled or building == null:
		return
	for room_id in building.get_rooms().keys():
		var room: RoomModel = building.get_room(room_id)
		if room == null or room.co_upper_kg <= 0.0:
			continue
		if room.temp_upper_c < co_oxidation_temp_min_c:
			continue
		if room.o2 < co_oxidation_o2_min:
			continue
		# Oxidación de primer orden: dm_CO/dt = -k * m_CO
		var oxidized_kg: float = room.co_upper_kg * co_oxidation_rate_per_s * dt
		oxidized_kg = minf(oxidized_kg, room.co_upper_kg)
		var generated_co2_kg: float = oxidized_kg * (44.0 / 28.0)
		var consumed_o2_kg: float = oxidized_kg * (16.0 / 28.0)
		if phase3_canonical_zone_shadow_enabled:
			phase3_zone_mass_system.apply_co_oxidation_event({
				"event_id": "co_oxidation:%d:%.6f" % [room.id, sim_time_s],
				"room_id": room.id,
				"co_consumed_kg": oxidized_kg,
				"co2_generated_kg": generated_co2_kg,
				"o2_consumed_kg": consumed_o2_kg,
			})
		room.co_upper_kg -= oxidized_kg
		room.co_kg = maxf(0.0, room.co_kg - oxidized_kg)
		# CO + ½O2 → CO2: por cada kg CO se producen 44/28 kg CO2.
		room.co2_kg += generated_co2_kg


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
			# SF-AUD-038: corrección de Babrauskas por diámetro de charco.
			# Para charcos pequeños (D<1m), HRR/m² es inferior al valor de charco infinito.
			# eff_kw_m2 = pool_hrr_kw_m2 * (1 - exp(-k·β·D)), D = √(4·A/π).
			var hrr_per_m2: float = obj.pool_hrr_kw_m2
			if obj.pool_k_beta_per_m > 0.0 and obj.pool_area_m2 > 0.0:
				var diam_m: float = sqrt(4.0 * obj.pool_area_m2 / PI)
				hrr_per_m2 *= (1.0 - exp(-obj.pool_k_beta_per_m * diam_m))
			pool_hrr_kw += hrr_per_m2 * obj.pool_area_m2
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

	if sim_time_s < flashover_min_time_s:
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

	# Criterio de flujo radiante al suelo (SF-AUD-012 fix).
	# La capa superior irradia como cuerpo gris: q = ε·σ·T⁴ [kW/m²].
	# A 500°C → ~18 kW/m²; a 520°C → ~20 kW/m² (umbral ISO 9705 flashover).
	# Se usa como criterio alternativo (OR) cuando la temperatura de capa ya es
	# suficientemente alta aunque los criterios de capa/breathing no se cumplan.
	var floor_flux_met: bool = false
	if flashover_floor_flux_criterion_enabled and room.temp_upper_c > 200.0:
		var t_k: float = room.temp_upper_c + 273.15
		# σ = 5.67e-11 kW/m²K⁴
		var q_floor_kw_m2: float = flashover_layer_emissivity * 5.67e-11 * t_k * t_k * t_k * t_k
		room.floor_heat_flux_kw_m2 = q_floor_kw_m2
		floor_flux_met = q_floor_kw_m2 >= flashover_floor_flux_kw_m2 \
				and enough_hrr \
				and layer_low_enough \
				and breathing_hot_enough \
				and (not flashover_require_tenability_loss or tenability_lost)
	else:
		# Con capa fría, actualizar con valor calculado igualmente (sin activar flashover)
		if room.temp_upper_c > 0.0:
			var t_k: float = room.temp_upper_c + 273.15
			room.floor_heat_flux_kw_m2 = flashover_layer_emissivity * 5.67e-11 * t_k * t_k * t_k * t_k
		else:
			room.floor_heat_flux_kw_m2 = 0.0

	# ── Thomas (1981) y MQH (McCaffrey-Quintiere-Harkleroad, 1981) ─────────────────
	# Predictores de HRR crítico de flashover basados en geometría del compartimento
	# y factor de ventilación. Se usan como criterio OR adicional cuando HRR supera
	# Q_fo y la capa caliente ya ha descendido (kaw > 0 → hay ventilación exterior).
	# Thomas: Q_fo = 7.8·A_T + 378·A_v·√H_v [kW]
	# MQH:    Q_fo = 610·(h_k·A_T·A_v·√H_v)^½ [kW]
	var thomas_mqh_met: bool = false
	if (flashover_thomas_enabled or flashover_mqh_enabled) and enough_hrr and layer_low_enough:
		var a_floor: float = room.floor_area_m2()
		# Superficie total del compartimento: 2 suelos + 4 paredes
		var a_t: float = 2.0 * a_floor \
				+ 2.0 * (room.width_m + room.length_m) * room.height_m
		# Factor de ventilación exterior Σ(A_v·√H_v) [m^(5/2)]
		var kaw: float = _kawagoe_factor_for_room(room.id)
		if a_t > 0.0 and kaw > 0.0:
			if flashover_thomas_enabled:
				room.flashover_q_thomas_kw = 7.8 * a_t + 378.0 * kaw
			if flashover_mqh_enabled:
				# SF-AUD-014: usar h_k del material de pared por sala si está definido.
				var hk_eff: float = flashover_mqh_hk_kw_m2k
				if room.wall_k_kw_m_k > 0.0 and room.wall_thickness_m > 0.0:
					hk_eff = room.wall_k_kw_m_k / maxf(0.001, room.wall_thickness_m)
				room.flashover_q_mqh_kw = 610.0 * sqrt(
					maxf(0.0, hk_eff * a_t * kaw)
				)
			var thomas_ok: bool = flashover_thomas_enabled \
					and room.flashover_q_thomas_kw > 0.0 \
					and room.hrr_kw >= room.flashover_q_thomas_kw
			var mqh_ok: bool = flashover_mqh_enabled \
					and room.flashover_q_mqh_kw > 0.0 \
					and room.hrr_kw >= room.flashover_q_mqh_kw
			thomas_mqh_met = (thomas_ok or mqh_ok) \
					and breathing_hot_enough \
					and (not flashover_require_tenability_loss or tenability_lost)

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
			or radiant_feedback_flashover \
			or floor_flux_met \
			or thomas_mqh_met:
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


func _resolve_fire_o2_mode() -> String:
	var mode: String = fire_o2_mode.strip_edges().to_lower()
	if mode == "upper" or mode == "lower" or mode == "interface":
		return mode
	if fire_o2_upper_for_flame:
		return "upper"
	if fire_o2_lower_for_flame:
		return "lower"
	return "legacy"


func _uses_pre_hrr_oxygen_step() -> bool:
	var mode: String = fire_o2_mode.strip_edges().to_lower()
	return mode == "upper" or mode == "lower" or mode == "interface"


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
# BALANCE DE CARBONO (SF-CBAL)
# ============================================================

## Captura una sola vez el inventario inicial antes del primer paso de física.
func _ensure_carbon_balance_initialized() -> void:
	if _cbal_initialized or building == null:
		return
	_cbal_c_initial_kg = 0.0
	for room_id in building.get_rooms().keys():
		var room: RoomModel = building.get_room(room_id)
		if room == null:
			continue
		_cbal_c_initial_kg += room.co_kg * (12.0 / 28.0) \
				+ room.co2_kg * (12.0 / 44.0) \
				+ room.hcn_kg * (12.0 / 27.0) \
				+ room.smoke_kg * 0.87
	_cbal_initialized = true


## Calcula el error de conservación de carbono al final de cada paso.
## Diagnóstico puro: no modifica ningún campo físico.
## Error por sala = (CO·12/28 + CO₂·12/44 + HCN·12/27 + smoke·0.87) − c_burned_total_kg.
## Error global incluye productos no modelados, depósitos, salidas y transporte pendiente.
## Negativo = pérdida (clamp u otro); positivo = creación espuria.
func _check_carbon_balance() -> void:
	_ensure_carbon_balance_initialized()
	var c_in_system: float = 0.0
	var c_burned_total: float = 0.0
	var c_exited_total: float = 0.0
	var c_deposited_total: float = 0.0
	var c_untracked_total: float = 0.0
	var c_preclamp_excess_total: float = 0.0
	var c_postclamp_excess_total: float = 0.0

	for room_id in building.get_rooms().keys():
		var room: RoomModel = building.get_room(room_id)
		if room == null:
			continue
		var c_in_gases: float = room.co_kg * (12.0 / 28.0) \
				+ room.co2_kg * (12.0 / 44.0) \
				+ room.hcn_kg * (12.0 / 27.0) \
				+ room.smoke_kg * 0.87  # hollín ≈ 87% C (SFPE Handbook Table 3.4-3)
		room.carbon_conservation_error_kg = c_in_gases - room.c_burned_total_kg
		c_in_system += c_in_gases
		c_burned_total += room.c_burned_total_kg
		c_exited_total += room.c_exited_kg
		c_deposited_total += room.c_deposited_kg
		c_untracked_total += room.c_untracked_products_kg
		c_preclamp_excess_total += room.c_preclamp_excess_kg
		c_postclamp_excess_total += room.c_postclamp_excess_kg

	var c_pending_internal: float = 0.0
	if gas_exchange_system != null:
		c_pending_internal = gas_exchange_system.get_pending_carbon_kg()

	# Error global = inventarios + sumideros − inventario inicial − fuente de combustible.
	# Positivo = creación espuria; negativo = pérdida numérica (clamp u otro).
	global_carbon_error_kg = c_in_system + c_pending_internal + c_untracked_total \
			+ c_exited_total + c_deposited_total + _cbal_hvac_c_exhausted_kg \
			- _cbal_c_initial_kg - c_burned_total
	global_carbon_preclamp_excess_kg = c_preclamp_excess_total
	global_carbon_postclamp_excess_kg = c_postclamp_excess_total
	# Residual de flujos separado solo del exceso que realmente entró al estado físico.
	global_carbon_transport_residual_kg = global_carbon_error_kg - c_postclamp_excess_total


func _check_layer_interface_guardrails(dt: float) -> void:
	if building == null or dt <= 0.0:
		return
	var ambient_c: float = thermal_system.ambient_temp_c()
	for room_id in building.get_rooms().keys():
		var room: RoomModel = building.get_room(room_id)
		if room == null:
			continue
		if room.hrr_kw <= 100.0:
			_layer_interface_divergence_s.erase(room_id)
			continue
		var thermal_layer_m: float = LayerInterfaceModel.get_thermal_layer_height_m(room, ambient_c)
		var flow_interface_m: float = LayerInterfaceModel.get_flow_interface_height_m(
			room,
			smoke_model,
			ambient_c
		)
		var divergence_m: float = absf(flow_interface_m - thermal_layer_m)
		if divergence_m <= 1.0:
			_layer_interface_divergence_s.erase(room_id)
			continue
		var accumulated_s: float = float(_layer_interface_divergence_s.get(room_id, 0.0)) + dt
		_layer_interface_divergence_s[room_id] = accumulated_s
		if accumulated_s <= 30.0 or bool(_layer_interface_warning_rooms.get(room_id, false)):
			continue
		_layer_interface_warning_rooms[room_id] = true
		var details: String = "room=%d thermal=%.2f flow=%.2f divergence=%.2f duration=%.1f" % [
			room.id,
			thermal_layer_m,
			flow_interface_m,
			divergence_m,
			accumulated_s
		]
		push_warning("[LayerInterface] Divergencia persistente: %s" % details)
		log_writer.append_event(sim_time_s, "layer_interface_divergence", details)

# ============================================================
# CLAMP / LIMPIEZA
# ============================================================

func _clamp_rooms(dt: float) -> void:
	for room_id in building.get_rooms().keys():
		var room: RoomModel = building.get_room(room_id)
		if room == null:
			continue

		room.o2 = clampf(room.o2, 0.0, o2_nominal)
		room.h_layer_m = clampf(room.h_layer_m, 0.0, room.height_m)
		room.thermal_layer_m = clampf(room.thermal_layer_m, 0.0, room.height_m)
		room.layer_150c_m = clampf(room.layer_150c_m, 0.0, room.height_m)
		room.upper_gas_kg = maxf(0.0, room.upper_gas_kg)
		room.upper_energy_kj = maxf(0.0, room.upper_energy_kj)
		room.lower_gas_kg = maxf(0.0, room.lower_gas_kg)
		room.lower_energy_kj = maxf(0.0, room.lower_energy_kj)

		room.temp_lower_c = maxf(building.outside_temp_c, room.temp_lower_c)

		if room.temp_upper_c > max_upper_temp_c:
			room.temp_upper_raw_c = maxf(room.temp_upper_raw_c, room.temp_upper_c)
			room.temp_upper_clamped = true
		room.temp_upper_c = minf(room.temp_upper_c, max_upper_temp_c)
		if room.temp_upper_c < room.temp_lower_c:
			room.temp_lower_c = room.temp_upper_c
		if thermal_system.is_room_quiescent(room):
			if two_zone_solver_enabled:
				zone_fire_solver.collapse_upper_into_lower(room, thermal_system.ambient_temp_c())
				zone_fire_solver.project_room_state(
					room,
					thermal_system.ambient_temp_c(),
					max_upper_temp_c,
					"final_clamp_quiescent"
				)
			else:
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
			if two_zone_solver_enabled:
				zone_fire_solver.project_room_state(
					room,
					thermal_system.ambient_temp_c(),
					max_upper_temp_c,
					"final_clamp_active"
				)
			else:
				room.upper_energy_kj = room.upper_gas_kg \
						* maxf(0.0, room.temp_upper_c - thermal_system.ambient_temp_c())
			thermal_system.update_temperature_cap_telemetry(room, dt)

		_apply_phase3_stairwell_temperature_cap(room)

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
		room.hcl_kg = maxf(0.0, room.hcl_kg)
		room.acrolein_kg = maxf(0.0, room.acrolein_kg)
		room.formaldehyde_kg = maxf(0.0, room.formaldehyde_kg)
		room.fed = maxf(0.0, room.fed)
		room.svv_pct = clampf(room.svv_pct, 0.0, 100.0)
		room.svv_worst_pct = minf(clampf(room.svv_worst_pct, 0.0, 100.0), room.svv_pct)


func _apply_phase3_stairwell_temperature_cap(room: RoomModel) -> void:
	if room == null:
		return
	if not phase3_stairwell_heat_bridge_enabled:
		return
	if room.kind != "escalera":
		return
	if phase3_stairwell_heat_bridge_target_max_temp_c <= thermal_system.ambient_temp_c():
		return

	var ambient_c: float = thermal_system.ambient_temp_c()
	var cap_c: float = maxf(ambient_c, phase3_stairwell_heat_bridge_target_max_temp_c)
	var touched: bool = false

	if room.temp_lower_c > cap_c:
		room.temp_lower_c = cap_c
		room.lower_energy_kj = room.lower_gas_kg * maxf(0.0, cap_c - ambient_c)
		touched = true

	if room.temp_upper_c > cap_c or room.temp_upper_raw_c > cap_c:
		room.temp_upper_c = maxf(room.temp_lower_c, minf(room.temp_upper_c, cap_c))
		room.temp_upper_raw_c = room.temp_upper_c
		room.temp_upper_clamped = false
		room.upper_energy_kj = room.upper_gas_kg * maxf(0.0, room.temp_upper_c - ambient_c)
		touched = true

	if touched and two_zone_solver_enabled and zone_fire_solver != null:
		zone_fire_solver.project_room_state(
			room, ambient_c, cap_c, "stairwell_temperature_cap"
		)

# ============================================================
# ESTADO AGREGADO
# ============================================================

func get_state() -> Dictionary:
	if state_builder == null:
		return {}
	var state: Dictionary = state_builder.build_state(_build_state_context())
	if phase3_zone_diagnostics_enabled:
		state["phase3_projection_trace"] = zone_fire_solver.get_projection_trace_events()
	# SF-AUD-029: exportar targets al estado
	var targets_dict: Dictionary = {}
	for t in _targets:
		targets_dict[t.id] = {
			"qnet_kw_m2": t.qnet_kw_m2,
			"peak_qnet_kw_m2": t.peak_qnet_kw_m2,
			"temp_c": t.temp_c,
			"room_id": t.room_id,
			"ignited": t.ignited
		}
	state["targets"] = targets_dict
	return state


func add_target(t) -> void:
	_targets.append(t)


func get_targets() -> Array:
	return _targets


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


func check_python_available() -> bool:
	if _python_checked:
		return _python_available
	_python_checked = true
	_python_available = false
	_python_command = ""
	_python_prefix_args = PackedStringArray()
	var output: Array = []
	if OS.get_name() == "Windows":
		if OS.execute("cmd.exe", PackedStringArray(["/c", "python", "--version"]), output, true) == 0:
			_python_command = "python"
		elif OS.execute("cmd.exe", PackedStringArray(["/c", "py", "-3", "--version"]), output, true) == 0:
			_python_command = "py"
			_python_prefix_args = PackedStringArray(["-3"])
	else:
		if OS.execute("python3", PackedStringArray(["--version"]), output, true) == 0:
			_python_command = "python3"
		elif OS.execute("python", PackedStringArray(["--version"]), output, true) == 0:
			_python_command = "python"
	_python_available = not _python_command.is_empty()
	return _python_available


func is_python_available() -> bool:
	return _python_available


func suppress_exit_graphs() -> void:
	_exit_graphs_suppressed = true


func stop_and_generate_graphs(details: String = "manual_stop_button", graphs_root: String = "") -> bool:
	if sim_time_s <= 0.0 or _graphs_launched:
		return false
	if not check_python_available():
		return false

	return _finish_and_launch_graphs(details, graphs_root, false)


func poll_graph_generation() -> int:
	if _graph_gen_pid <= 0:
		return -2
	if OS.is_process_running(_graph_gen_pid):
		return 0
	var exit_code: int = OS.get_process_exit_code(_graph_gen_pid)
	_graph_gen_pid = -1
	return 1 if _complete_graph_generation(exit_code) else -1


func export_technical_results(details: String = "headless_export", output_dir: String = "") -> bool:
	if sim_time_s <= 0.0:
		return false

	is_finished = true
	_force_log_final_snapshot()
	if details.is_empty():
		log_writer.append_event(sim_time_s, "sim_end", "")
	else:
		log_writer.append_event(sim_time_s, "sim_end", details)

	var export_dir: String = output_dir.strip_edges()
	if export_dir.is_empty():
		export_dir = log_writer.resolve_log_file_path().get_base_dir()
	if export_dir.is_empty():
		return false
	DirAccess.make_dir_recursive_absolute(export_dir)
	_write_export_json(export_dir)
	export_screenshot_requested.emit(export_dir)
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
			if op.type == OpeningModel.Type.WINDOW and op.glass_broken:
				_prev_open_fracs[i] = curr
				continue
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


func _step_victims(dt: float) -> void:
	if not victims_enabled or building == null:
		return
	for vic in building.victims:
		if bool(vic.get("incapacitated", false)):
			continue
		var room_id: int = int(vic.get("room_id", -1))
		var room: RoomModel = building.get_room(room_id)
		if room == null:
			continue
		var height_m: float = float(vic.get("height_m", 0.9))
		var delta_fed: float = thermal_system.compute_fed_delta_for_height(room, dt, height_m)
		if delta_fed > 0.0:
			vic["fed"] = maxf(0.0, float(vic.get("fed", 0.0)) + delta_fed)
			if float(vic.get("fed", 0.0)) >= 1.0:
				vic["incapacitated"] = true
				vic["incapacitated_at_s"] = sim_time_s
				log_writer.append_event(
					sim_time_s,
					"victim_incapacitated",
					"id=%s room=%d fed=%.4g" % [String(vic.get("id", "?")), room_id, float(vic.get("fed", 0.0))]
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


## Actualiza room.ceiling_jet_temp_c para todas las salas con fuego activo — BV-028.
## Usa la fórmula de Alpert (1972) en el eje del penacho (r → 0+) sin duplicar física:
## el valor ya se computa en _ceiling_jet_temp_c(); aquí sólo se persiste en RoomModel
## para que SimulationStateBuilder lo exporte como campo de diagnóstico.
func _update_room_ceiling_jet_temps() -> void:
	if building == null:
		return
	for room in building.get_rooms().values():
		if room == null:
			continue
		if ceiling_jet_enabled and (room as RoomModel).hrr_kw > 0.0:
			(room as RoomModel).ceiling_jet_temp_c = _ceiling_jet_temp_c(room as RoomModel, {})
		else:
			(room as RoomModel).ceiling_jet_temp_c = (room as RoomModel).temp_upper_c


func _on_sim_finished() -> void:
	_finish_and_launch_graphs("")


# ============================================================
# W-01: PICOS Y EXPORTACIÓN JSON POST-SIMULACIÓN
# ============================================================

## Registra el HRR y temperatura pico por sala. Se llama cada step.
func _update_peak_tracking() -> void:
	if building == null:
		return
	for room_id in building.get_rooms().keys():
		var room: RoomModel = building.get_room(room_id)
		if room == null:
			continue
		_record_room_extreme(_room_peak_hrr, _room_peak_hrr_time, room_id, room.hrr_kw, 0.0, true)
		_record_room_extreme(_room_peak_temp, _room_peak_temp_time, room_id, room.temp_upper_c, 20.0, true)
		_record_room_extreme(_room_peak_co_upper, _room_peak_co_upper_time, room_id, thermal_system.compute_co_upper_ppm(room), 0.0, true)
		_record_room_extreme(_room_peak_hcn_upper, _room_peak_hcn_upper_time, room_id, thermal_system.compute_hcn_upper_ppm(room), 0.0, true)
		_record_room_extreme(_room_min_o2, _room_min_o2_time, room_id, minf(room.o2, room.o2_lower), o2_nominal, false)
		_record_room_extreme(_room_min_visibility, _room_min_visibility_time, room_id, room.visibility_m, smoke_visibility_max_m, false)
		_record_room_extreme(_room_peak_fed, _room_peak_fed_time, room_id, room.fed, 0.0, true)
		_record_room_extreme(_room_min_svv, _room_min_svv_time, room_id, room.svv_worst_pct, 100.0, false)


func _record_room_extreme(values: Dictionary, times: Dictionary, room_id: int, value: float, default_value: float, use_max: bool) -> void:
	if not values.has(room_id):
		values[room_id] = value
		times[room_id] = sim_time_s
		return
	var current: float = float(values.get(room_id, default_value))
	var should_update: bool = value > current if use_max else value < current
	if should_update:
		values[room_id] = value
		times[room_id] = sim_time_s


func get_last_technical_summary() -> Dictionary:
	return _last_technical_summary.duplicate(true)


func build_technical_summary(output_dir: String = "") -> Dictionary:
	var rooms_arr: Array = _build_technical_summary_rooms()
	var victims_arr: Array = _build_technical_summary_victims()
	var detectors_arr: Array = _build_technical_summary_detectors()
	var global_summary: Dictionary = _build_technical_summary_global(rooms_arr, victims_arr, detectors_arr)
	var summary: Dictionary = {
		"schema_version": "simufire_technical_summary_v1",
		"sim_duration_s": _snap_time(sim_time_s),
		"scenario": building.template_name if building != null else "",
		"global": global_summary,
		"rooms": rooms_arr,
		"victims": victims_arr,
		"detectors": detectors_arr,
	}
	if phase3_connection_residence_diagnostics_enabled:
		summary["phase3_connection_residence"] = \
				phase3_zone_mass_system.get_connection_residence_results()
	if not output_dir.strip_edges().is_empty():
		summary["output_dir"] = output_dir
	return summary


func _build_technical_summary_rooms() -> Array:
	var rooms_arr: Array = []
	if building == null:
		return rooms_arr
	var room_ids: Array[int] = _sorted_room_ids()
	for room_id in room_ids:
		var room: RoomModel = building.get_room(room_id)
		if room == null:
			continue
		var entry: Dictionary = {
			"room_id": room_id,
			"room_name": room.name,
			"flashover_triggered": room.flashover_triggered,
			"peak_hrr_kw": _snap_metric(float(_room_peak_hrr.get(room_id, room.hrr_kw)), 0.1),
			"peak_hrr_time_s": _snap_time(float(_room_peak_hrr_time.get(room_id, -1.0))),
			"peak_temp_upper_c": _snap_metric(float(_room_peak_temp.get(room_id, room.temp_upper_c)), 0.1),
			"peak_temp_time_s": _snap_time(float(_room_peak_temp_time.get(room_id, -1.0))),
			"peak_co_upper_ppm": _snap_metric(float(_room_peak_co_upper.get(room_id, thermal_system.compute_co_upper_ppm(room))), 1.0),
			"peak_co_time_s": _snap_time(float(_room_peak_co_upper_time.get(room_id, -1.0))),
			"peak_hcn_upper_ppm": _snap_metric(float(_room_peak_hcn_upper.get(room_id, thermal_system.compute_hcn_upper_ppm(room))), 0.1),
			"peak_hcn_time_s": _snap_time(float(_room_peak_hcn_upper_time.get(room_id, -1.0))),
			"min_o2_fraction": _snap_metric(float(_room_min_o2.get(room_id, minf(room.o2, room.o2_lower))), 0.0001),
			"min_o2_pct": _snap_metric(float(_room_min_o2.get(room_id, minf(room.o2, room.o2_lower))) * 100.0, 0.01),
			"min_o2_time_s": _snap_time(float(_room_min_o2_time.get(room_id, -1.0))),
			"min_visibility_m": _snap_metric(float(_room_min_visibility.get(room_id, room.visibility_m)), 0.01),
			"min_visibility_time_s": _snap_time(float(_room_min_visibility_time.get(room_id, -1.0))),
			"peak_fed": _snap_metric(float(_room_peak_fed.get(room_id, room.fed)), 0.0001),
			"peak_fed_time_s": _snap_time(float(_room_peak_fed_time.get(room_id, -1.0))),
			"min_svv_pct": _snap_metric(float(_room_min_svv.get(room_id, room.svv_worst_pct)), 0.1),
			"min_svv_time_s": _snap_time(float(_room_min_svv_time.get(room_id, -1.0))),
			"final_fed": _snap_metric(room.fed, 0.0001),
			"final_visibility_m": _snap_metric(room.visibility_m, 0.01),
		}
		if room.flashover_triggered:
			entry["flashover_time_s"] = _snap_time(room.flashover_time_s)
		rooms_arr.append(entry)
	return rooms_arr


func _build_technical_summary_victims() -> Array:
	var victims_arr: Array = []
	if building == null:
		return victims_arr
	for vic in building.victims:
		var incapacitated: bool = bool(vic.get("incapacitated", false))
		var fed_time: float = float(vic.get("incapacitated_at_s", -1.0)) if incapacitated else -1.0
		victims_arr.append({
			"victim_id": String(vic.get("id", "?")),
			"victim_name": String(vic.get("name", "")),
			"room_id": int(vic.get("room_id", -1)),
			"height_m": _snap_metric(float(vic.get("height_m", 0.9)), 0.01),
			"fed_final": _snap_metric(float(vic.get("fed", 0.0)), 0.0001),
			"time_to_fed_1_s": _snap_time(fed_time),
			"incapacitated": incapacitated,
		})
	return victims_arr


func _build_technical_summary_detectors() -> Array:
	var detectors_arr: Array = []
	if building == null:
		return detectors_arr
	for det in building.detectors:
		detectors_arr.append({
			"detector_id": String(det.get("id", "?")),
			"room_id": int(det.get("room_id", -1)),
			"type": String(det.get("type", "smoke")),
			"threshold": float(det.get("threshold", 0.0)),
			"triggered": bool(det.get("triggered", false)),
			"triggered_at_s": _snap_time(float(det.get("triggered_at_s", -1.0))),
		})
	return detectors_arr


func _build_technical_summary_global(rooms_arr: Array, victims_arr: Array, detectors_arr: Array) -> Dictionary:
	var flashover_count: int = 0
	var peak_hrr_kw: float = 0.0
	var peak_hrr_room_id: int = -1
	var peak_hrr_time_s: float = -1.0
	var peak_temp_c: float = 0.0
	var peak_temp_room_id: int = -1
	var peak_co_ppm: float = 0.0
	var peak_co_room_id: int = -1
	var peak_hcn_ppm: float = 0.0
	var peak_hcn_room_id: int = -1
	var min_o2_pct: float = 100.0
	var min_o2_room_id: int = -1
	var min_visibility_m: float = 1.0e20
	var min_visibility_room_id: int = -1
	var peak_fed: float = 0.0
	var peak_fed_room_id: int = -1

	for raw_room in rooms_arr:
		var room: Dictionary = Dictionary(raw_room)
		var room_id: int = int(room.get("room_id", -1))
		if bool(room.get("flashover_triggered", false)):
			flashover_count += 1
		var hrr: float = float(room.get("peak_hrr_kw", 0.0))
		if hrr > peak_hrr_kw:
			peak_hrr_kw = hrr
			peak_hrr_room_id = room_id
			peak_hrr_time_s = float(room.get("peak_hrr_time_s", -1.0))
		var temp_c: float = float(room.get("peak_temp_upper_c", 0.0))
		if temp_c > peak_temp_c:
			peak_temp_c = temp_c
			peak_temp_room_id = room_id
		var co_ppm: float = float(room.get("peak_co_upper_ppm", 0.0))
		if co_ppm > peak_co_ppm:
			peak_co_ppm = co_ppm
			peak_co_room_id = room_id
		var hcn_ppm: float = float(room.get("peak_hcn_upper_ppm", 0.0))
		if hcn_ppm > peak_hcn_ppm:
			peak_hcn_ppm = hcn_ppm
			peak_hcn_room_id = room_id
		var o2_pct: float = float(room.get("min_o2_pct", 100.0))
		if o2_pct < min_o2_pct:
			min_o2_pct = o2_pct
			min_o2_room_id = room_id
		var visibility_m: float = float(room.get("min_visibility_m", 1.0e20))
		if visibility_m < min_visibility_m:
			min_visibility_m = visibility_m
			min_visibility_room_id = room_id
		var fed: float = float(room.get("peak_fed", 0.0))
		if fed > peak_fed:
			peak_fed = fed
			peak_fed_room_id = room_id

	var victims_incapacitated: int = 0
	for raw_victim in victims_arr:
		if bool(Dictionary(raw_victim).get("incapacitated", false)):
			victims_incapacitated += 1

	var detectors_triggered: int = 0
	var first_detector_time_s: float = -1.0
	for raw_detector in detectors_arr:
		var detector: Dictionary = Dictionary(raw_detector)
		if not bool(detector.get("triggered", false)):
			continue
		detectors_triggered += 1
		var triggered_at: float = float(detector.get("triggered_at_s", -1.0))
		if triggered_at >= 0.0 and (first_detector_time_s < 0.0 or triggered_at < first_detector_time_s):
			first_detector_time_s = triggered_at

	if min_visibility_m >= 1.0e19:
		min_visibility_m = 0.0

	return {
		"room_count": rooms_arr.size(),
		"flashover_room_count": flashover_count,
		"victim_count": victims_arr.size(),
		"victims_incapacitated": victims_incapacitated,
		"detector_count": detectors_arr.size(),
		"detectors_triggered": detectors_triggered,
		"first_detector_time_s": _snap_time(first_detector_time_s),
		"peak_hrr_kw": _snap_metric(peak_hrr_kw, 0.1),
		"peak_hrr_room_id": peak_hrr_room_id,
		"peak_hrr_time_s": _snap_time(peak_hrr_time_s),
		"peak_temp_upper_c": _snap_metric(peak_temp_c, 0.1),
		"peak_temp_room_id": peak_temp_room_id,
		"peak_co_upper_ppm": _snap_metric(peak_co_ppm, 1.0),
		"peak_co_room_id": peak_co_room_id,
		"peak_hcn_upper_ppm": _snap_metric(peak_hcn_ppm, 0.1),
		"peak_hcn_room_id": peak_hcn_room_id,
		"min_o2_pct": _snap_metric(min_o2_pct, 0.01),
		"min_o2_room_id": min_o2_room_id,
		"min_visibility_m": _snap_metric(min_visibility_m, 0.01),
		"min_visibility_room_id": min_visibility_room_id,
		"peak_fed": _snap_metric(peak_fed, 0.0001),
		"peak_fed_room_id": peak_fed_room_id,
	}


func _sorted_room_ids() -> Array[int]:
	var room_ids: Array[int] = []
	if building == null:
		return room_ids
	for room_id in building.get_rooms().keys():
		room_ids.append(int(room_id))
	room_ids.sort()
	return room_ids


func _snap_metric(value: float, step: float) -> float:
	if step <= 0.0:
		return value
	return snappedf(value, step)


func _snap_time(value: float) -> float:
	if value < 0.0:
		return -1.0
	return snappedf(value, 0.1)


## Escribe events.json y summary.json en output_dir.
## Llamado desde _finish_and_launch_graphs() antes de lanzar Python.
func _write_export_json(output_dir: String) -> void:
	if output_dir.strip_edges().is_empty():
		return
	if not DirAccess.dir_exists_absolute(output_dir):
		return

	# --- events.json ---
	var events_path: String = output_dir.path_join("events.json")
	var ok: bool = log_writer.write_events_json(events_path)
	if ok:
		print("[SimulationEngine] events.json escrito en: %s" % events_path)
	else:
		push_warning("[SimulationEngine] No se pudo escribir events.json en: %s" % events_path)

	# --- summary.json ---
	var summary: Dictionary = build_technical_summary(output_dir)
	_last_technical_summary = summary.duplicate(true)

	var summary_path: String = output_dir.path_join("summary.json")
	var f := FileAccess.open(summary_path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(summary, "\t"))
		f.close()
		print("[SimulationEngine] summary.json escrito en: %s" % summary_path)
	else:
		push_warning("[SimulationEngine] No se pudo escribir summary.json en: %s" % summary_path)
	technical_summary_ready.emit(_last_technical_summary.duplicate(true), output_dir)


func _finish_and_launch_graphs(details: String, graphs_root: String = "", wait_for_finish: bool = false) -> bool:
	if _graphs_launched or sim_time_s <= 0.0:
		return false

	is_finished = true
	_force_log_final_snapshot()
	_graphs_launched = true
	_last_graphs_dir = ""
	_last_graph_generation_ok = false

	if details.is_empty():
		log_writer.append_event(sim_time_s, "sim_end", "")
	else:
		log_writer.append_event(sim_time_s, "sim_end", details)

	# W-01: exportar JSON de eventos y resumen técnico.
	var export_dir: String = graphs_root.strip_edges()
	if export_dir.is_empty():
		# Sin directorio de usuario: escribir junto al log.
		export_dir = log_writer.resolve_log_file_path().get_base_dir()
	_write_export_json(export_dir)
	export_screenshot_requested.emit(export_dir)

	if _should_launch_graphs():
		return _launch_graph_generator(graphs_root, wait_for_finish)
	return false


func _force_log_final_snapshot() -> void:
	_sync_auxiliary_services()
	log_writer.append_snapshot_now(sim_time_s, get_state())


func _force_log_initial_snapshot() -> void:
	_sync_auxiliary_services()
	log_writer.append_initial_snapshot(sim_time_s, get_state())


func _launch_graph_generator(graphs_root: String = "", wait_for_finish: bool = false) -> bool:
	if not check_python_available():
		push_warning("[SimulationEngine] Python no detectado. No se pueden generar graficas.")
		return false
	var script_path: String = ProjectSettings.globalize_path("res://scripts/generate_fire_graphs.py")
	var latest_path: String = ProjectSettings.globalize_path("user://latest_graphs_dir.txt")
	if FileAccess.file_exists(latest_path):
		var remove_error: Error = DirAccess.remove_absolute(latest_path)
		if remove_error != OK:
			push_warning("[SimulationEngine] No se pudo limpiar el marcador de graficas anterior.")
			return false
	_graph_gen_latest_path = latest_path
	var log_path: String = log_writer.resolve_log_file_path()
	var args: PackedStringArray = PackedStringArray([script_path, "--latest-file", latest_path, "--log", log_path, "--copy-log"])
	if enable_csv_log:
		var csv_path: String = log_writer.resolve_csv_file_path()
		if csv_path.strip_edges() != "":
			args.append("--csv")
			args.append(csv_path)
			args.append("--copy-csv")
	if graphs_root.strip_edges() != "":
		args.append("--out-root")
		args.append(graphs_root)

	if wait_for_finish:
		var output: Array = []
		var ok: bool = _complete_graph_generation(_execute_python(args, output))
		# Co-ubicar el dashboard en la misma carpeta que los PNG recién generados.
		_launch_html_dashboard(graphs_root, _last_graphs_dir, true)
		return ok

	_graph_gen_pid = _create_python_process(args)
	if _graph_gen_pid > 0:
		print("[SimulationEngine] Generando graficas (PID %d)..." % _graph_gen_pid)
		# Modo asíncrono: aún no conocemos la carpeta PNG, va a carpeta hermana.
		_launch_html_dashboard(graphs_root, "", false)
		return true
	push_warning("[SimulationEngine] No se pudo lanzar Python. Ejecuta: python scripts/generate_fire_graphs.py")
	return false


## Lanza el exportador Plotly (dashboard.html interactivo) en paralelo a los PNG.
## No interfiere con el flujo matplotlib: proceso independiente y fire-and-forget.
## - out_dir no vacío  -> co-ubica el dashboard en esa carpeta (--out-dir).
## - out_dir vacío     -> crea carpeta hermana bajo graphs_root (--out-root).
func _launch_html_dashboard(graphs_root: String, out_dir: String, wait_for_finish: bool) -> void:
	if not enable_html_dashboard:
		return
	if not check_python_available():
		return
	var script_path: String = ProjectSettings.globalize_path("res://scripts/generate_fire_graphs_html.py")
	if not FileAccess.file_exists(script_path):
		push_warning("[SimulationEngine] generate_fire_graphs_html.py no encontrado; se omite el dashboard.")
		return
	var log_path: String = log_writer.resolve_log_file_path()
	var args: PackedStringArray = PackedStringArray([script_path, "--log", log_path, "--plotlyjs", "shared"])
	if enable_csv_log:
		var csv_path: String = log_writer.resolve_csv_file_path()
		if csv_path.strip_edges() != "":
			args.append("--csv")
			args.append(csv_path)
	if out_dir.strip_edges() != "":
		args.append("--out-dir")
		args.append(out_dir)
	elif graphs_root.strip_edges() != "":
		args.append("--out-root")
		args.append(graphs_root)

	if wait_for_finish:
		var output: Array = []
		var exit_code: int = _execute_python(args, output)
		if exit_code == 0:
			print("[SimulationEngine] Dashboard HTML generado.")
		else:
			push_warning("[SimulationEngine] Falló el dashboard HTML (exit=%d). ¿plotly instalado?" % exit_code)
		return

	_html_dashboard_pid = _create_python_process(args)
	if _html_dashboard_pid > 0:
		print("[SimulationEngine] Generando dashboard HTML (PID %d)..." % _html_dashboard_pid)
	else:
		push_warning("[SimulationEngine] No se pudo lanzar el dashboard HTML.")


func _execute_python(args: PackedStringArray, output: Array) -> int:
	var process_args: PackedStringArray = _python_prefix_args.duplicate()
	process_args.append_array(args)
	if OS.get_name() == "Windows":
		var win_args: PackedStringArray = PackedStringArray(["/c", _python_command])
		win_args.append_array(process_args)
		return OS.execute("cmd.exe", win_args, output, true)
	return OS.execute(_python_command, process_args, output, true)


func _create_python_process(args: PackedStringArray) -> int:
	var process_args: PackedStringArray = _python_prefix_args.duplicate()
	process_args.append_array(args)
	if OS.get_name() == "Windows":
		var win_args: PackedStringArray = PackedStringArray(["/c", _python_command])
		win_args.append_array(process_args)
		return OS.create_process("cmd.exe", win_args)
	return OS.create_process(_python_command, process_args)


func _complete_graph_generation(exit_code: int) -> bool:
	_last_graphs_dir = _read_latest_graphs_dir(_graph_gen_latest_path)
	_last_graph_generation_ok = exit_code == 0 \
			and not _last_graphs_dir.is_empty() \
			and DirAccess.dir_exists_absolute(_last_graphs_dir)
	if _last_graph_generation_ok:
		print("[SimulationEngine] Graficas generadas en: %s" % _last_graphs_dir)
	else:
		push_warning("[SimulationEngine] No se pudieron generar graficas. Ejecuta: python scripts/generate_fire_graphs.py")
	return _last_graph_generation_ok


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
		if arg_str.begins_with("--validation-case") or arg_str.begins_with("--run-scenario") or arg_str.begins_with("--scenario"):
			return false
	return true


func _is_validation_mode() -> bool:
	for arg in OS.get_cmdline_user_args():
		var arg_str: String = String(arg)
		if arg_str == "--validation-case" or arg_str.begins_with("--validation-case="):
			return true
		if arg_str == "--run-scenario" or arg_str.begins_with("--run-scenario="):
			return true
		if arg_str == "--scenario" or arg_str.begins_with("--scenario="):
			return true
	return false


## Godot llama _exit_tree cuando se detiene el juego (botón Stop del editor
## o cierre de ventana). Garantiza que las gráficas se generen aunque la
## simulación no haya terminado por extinción natural del fuego.
func _exit_tree() -> void:
	if _is_validation_mode() or _exit_graphs_suppressed:
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

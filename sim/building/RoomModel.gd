extends RefCounted
class_name RoomModel

const FuelObjectModelScript = preload("res://sim/fire/FuelObjectModel.gd")

# ============================================================
# ROOM MODEL
# ------------------------------------------------------------
# Estado de una habitacion individual.
# Guarda:
# - geometria basica
# - estado termico
# - estado de gases/humo
# - referencia al fuego si existe
# ============================================================

var id: int = -1
var name: String = ""
var kind: String = ""

# Geometria
var width_m: float = 0.0
var length_m: float = 0.0
var height_m: float = 2.5
var rotation_deg: float = 0.0
# Nivel de suelo sobre la planta de referencia (planta baja = 0.0).
# Necesario para calcular el efecto chimenea (stack effect) en edificios
# con más de una planta. Unidades: metros.
var floor_level_z_m: float = 0.0
var stair_run_direction_m: Vector2 = Vector2(0.0, 1.0)
var stair_has_walls: bool = false
var stair_has_railings: bool = true
var stair_turn_degrees: float = 0.0
var stair_flight_count: int = 1

# Estado termico
var temp_upper_c: float = 20.0
var temp_upper_raw_c: float = 20.0
var temp_upper_clamped: bool = false
var temp_upper_clamp_time_s: float = 0.0
var temp_upper_clamp_count: int = 0
var temp_lower_c: float = 20.0

# Gases / oxigeno
var o2: float = 0.209
# Fraccion O2 en capa superior (zona caliente). Se inicializa igual a o2 (2026-05-17).
var o2_upper: float = 0.209
# Fraccion O2 en capa inferior (zona fría). Variable persistente; NO derivada de o2. Fase 2A (2026-05-20).
var o2_lower: float = 0.209
# Phase 5 M2: masa conservada de O₂ en zona superior [kg]. -1.0 = sin inicializar.
# Inicializado/actualizado por OxygenExchangeSystem cuando fire_o2_mass_tracking_enabled=true.
# Con flag OFF este campo nunca se lee ni escribe → no-op garantizado.
var upper_o2_mass_tracked: float = -1.0
# Phase 8: señal de que ThermalSystem (canonical Part A) actualizó o2_upper este paso.
# OxygenExchangeSystem re-sincroniza el tracker desde o2_upper en lugar de sobreescribirlo.
var canonical_o2_upper_updated: bool = false
# M2: muestra local de O2 realmente usada por CombustionSystem.
var fire_o2_mode_used: String = "legacy"
var fire_o2_ref: float = 0.209
var fire_o2_min_ref: float = 0.0
# Fraccion CO2 en capa superior (mol fraction 0-1). Tracked directo para evitar error de densidad.
# 0.0004 = 400 ppm CO2 ambiente. Fase 2B (2026-05-23).
var co2_upper: float = 0.0004

# Humo
var smoke_kg: float = 0.0
var smoke_prod_kg_s: float = 0.0
var soot_fraction: float = 1.0
var h_layer_m: float = 2.5
# Fracción radiativa efectiva del HRR (SF-AUD-015). Resuelta desde per-fuel chi_rad_normal.
# -1.0 = no hay objetos con chi_rad propio; ThermalSystem usa el global hrr_chi_rad_normal.
var chi_rad_normal: float = -1.0

# Capa superior de gases calientes
var thermal_layer_m: float = 2.5
# M1 two-zone: upper_gas_kg/upper_energy_kj se reutilizan como estado canonico
# superior. La zona inferior completa el ledger sin duplicar el estado upper.
var upper_gas_kg: float = 0.0
var upper_energy_kj: float = 0.0
var lower_gas_kg: float = 0.0
var lower_energy_kj: float = 0.0
# Masa neta añadida (+) o expulsada (-) por el cierre de volumen a presión de referencia.
# M3 sustituirá este término agregado por flujos upper/lower resueltos por apertura.
var two_zone_boundary_mass_kg: float = 0.0
# Energía sensible neta añadida (+) o retirada (-) por sistemas legacy,
# cierre de volumen y caps mientras M1 convive con ellos.
var two_zone_boundary_energy_kj: float = 0.0
var two_zone_opening_upper_in_kg: float = 0.0
var two_zone_opening_upper_out_kg: float = 0.0
var two_zone_opening_lower_in_kg: float = 0.0
var two_zone_opening_lower_out_kg: float = 0.0
var upper_radiative_loss_kw: float = 0.0
var layer_150c_m: float = 2.5

# Monoxido de carbono - masa en la sala (kg)
var co_kg: float = 0.0
var co_upper_kg: float = 0.0

# Dioxido de carbono - masa en la sala (kg)
var co2_kg: float = 0.0
var co2_upper_kg: float = 0.0  # CO2 en capa superior (kg)

# Cianuro de hidrógeno - masa en la sala (kg)
var hcn_kg: float = 0.0
var hcn_upper_kg: float = 0.0  # HCN en capa superior (kg)

# Fracción de carbono producida vs disponible (diagnóstico SF-AUD-032).
# Calculada en CombustionSystem cada paso; 1.0 = balance exacto; <1.0 = bien ventilado.
var c_balance_frac: float = 0.0
# SF-CBAL: integral de carbono consumido del combustible antes del clamp (kg C).
# Incrementado en CombustionSystem cada paso de combustión activa.
var c_burned_total_kg: float = 0.0
# Carbono consumido que no está representado por CO/CO2/HCN/soot (kg C).
# Se conserva explícitamente para que el ledger no confunda productos no modelados con pérdida.
var c_untracked_products_kg: float = 0.0
# Exceso acumulado solicitado por los yields antes del clamp de carbono (kg C).
var c_preclamp_excess_kg: float = 0.0
# Exceso acumulado que permanece en productos físicos después del clamp (kg C).
var c_postclamp_excess_kg: float = 0.0
# Error de conservación de carbono (kg C): C_en_gases − c_burned_total_kg.
# Negativo = C transportado a otras salas o exterior (normal en sala de fuego).
# Positivo en sala de fuego = posible creación espuria (diagnóstico SF-CBAL).
var carbon_conservation_error_kg: float = 0.0
# SF-CBAL global: carbono acumulado que salió por aperturas exteriores (kg C).
# Incrementado en GasExchangeSystem cada vez que CO/CO₂/HCN/humo se ventila
# al exterior (presión, flujo de humo, purgas, ACH o PPV).
var c_exited_kg: float = 0.0
# SF-CBAL: carbono depositado en paredes/suelo (hollín sedimentado, kg C).
# Incrementado en GasExchangeSystem en la fase de sedimentación de humo.
var c_deposited_kg: float = 0.0

# Irritantes — SF-AUD-018 (ISO 13571 FEC).
# Masa de gases irritantes: HCl (PVC), acroleína y formaldehído (madera/plásticos).
var hcl_kg: float = 0.0
var acrolein_kg: float = 0.0
var formaldehyde_kg: float = 0.0

# FEC instantáneo (Fractional Effective Concentration, ISO 13571 §A.3)
# FEC = [HCl]/900 + [acrolein]/4 + [HCHO]/250  (ppm/IC50)
# FEC ≥ 1.0 → incapacitación por irritación sensorial.
var fec_irritant: float = 0.0

# FED acumulado (Fractional Effective Dose) - ISO 13571
var fed: float = 0.0
# Phase 4B: FED por componente (observabilidad — no se usan en checks requeridos)
var fed_co: float = 0.0       # FED acumulado — componente CO (narcosis)
var fed_hcn: float = 0.0      # FED acumulado — componente HCN (toxicidad)
var fed_hypoxia: float = 0.0  # FED acumulado — componente hipoxia (O2)
var fed_heat: float = 0.0     # FED acumulado — componente térmico (conv+rad)

# Supervivencia de Victimas (%)
var svv_pct: float = 100.0
var svv_worst_pct: float = 100.0

# Visibilidad instantánea (Purser) en metros
var visibility_m: float = 30.0

# Carga de combustible y limite de HRR
var fuel_energy_MJ: float = 0.0
var max_hrr_kw: float = 0.0
var fuel_objects: Array = []

# Fuego
var fire: FireModel = null
var fire_time_s: float = 0.0
var hrr_kw: float = 0.0
var hrr_target_kw: float = 0.0
var pyrolysis_kw: float = 0.0
var burned_hrr_kw: float = 0.0
var unburned_generation_kw: float = 0.0
var flame_hrr_target_kw: float = 0.0
var smolder_hrr_target_kw: float = 0.0
var pool_release_hrr_target_kw: float = 0.0
var fire_smoldering: bool = false
var fire_dormant_time_s: float = 0.0
var fire_low_hrr_time_s: float = 0.0
var fire_o2_extinguished: bool = false
var o2_hrr_factor: float = 1.0
var retained_unburned_MJ: float = 0.0
var ventilation_response_factor: float = 0.0
# Régimen de combustión actual — clasificado por CombustionRegimeClassifier (Fase 1, solo diagnóstico).
# No altera ningún campo de física. Ver docs/architecture/ILV_COMBUSTION_REGIME_PLAN.md.
var combustion_regime: String = "EXTINGUISHED"

# Presion de la capa superior respecto al exterior
var overpressure_pa: float = 0.0
# Phase 3: presión termodinámica ODE (campo paralelo, no sustituye overpressure_pa).
# Solo no-nulo cuando phase3_thermodynamic_pressure_enabled=true en engine_overrides.
# El downstream (venteo, doorway, thermal) sigue usando overpressure_pa sin cambio.
var pressure_pa_therm: float = 0.0
## Temperatura del jet de techo en el eje del penacho según Alpert (1972) — BV-028.
## Actualizada por SimulationEngine._update_room_ceiling_jet_temps() en cada paso.
## Igual a temp_upper_c cuando no hay fuego activo en la sala.
var ceiling_jet_temp_c: float = 20.0
# Flujo radiante al suelo — SF-AUD-012.
# Calculado en cada paso como ε·σ·T_upper⁴ [kW/m²].
# ~20 kW/m² es el umbral ISO 9705 para flashover por ignicion generalizada de superficies.
var floor_heat_flux_kw_m2: float = 0.0
# HRR crítico de flashover predicho por Thomas (1981) y MQH (1981) [kW].
# 0.0 = aún sin ventilación exterior o sin fuego.
var flashover_q_thomas_kw: float = 0.0
var flashover_q_mqh_kw: float = 0.0

# Propiedades térmicas de pared por sala — R2-3 Crank-Nicolson 5-nodo.
# Default: yeso estándar (CFAST material por defecto, NIST SP 1041).
# Yeso 12.7mm: k=0.00017 kW/m·K, rho=960 kg/m³, cp=1.09 kJ/kg·K, d=0.013 m
# Hormigón 200mm: k=0.00100, rho=2300, cp=0.88, d=0.20
# Madera/OSB 100mm: k=0.00009, rho=600, cp=1.70, d=0.10
# Ref: SFPE Handbook Tabla 1-5.1; ISO 13786; NIST CFAST input guide
# Usar -1.0 para deshabilitar el PDE y caer al modelo lumped global.
var wall_k_kw_m_k: float = -1.0   # kW/(m·K); -1 = lumped fallback (PDE opt-in via room overrides)
var wall_rho_kg_m3: float = -1.0  # kg/m³
var wall_cp_kj_kg_k: float = -1.0 # kJ/(kg·K)
var wall_thickness_m: float = -1.0 # m; -1 = lumped fallback

# SF-AUD-030: temperaturas del perfil 1D de pared (nodos Crank-Nicolson).
# T[0]=cara interior (= _wall_surface_temp_c), T[2]=punto medio, T[4]=cara exterior.
# Solo se actualizan cuando los 4 parámetros de material están definidos.
var wall_T_mid_c: float = 20.0    # T[2] — nodo central  [°C]
var wall_T_outer_c: float = 20.0  # T[4] — cara exterior [°C]

# 1.5A: flujo másico total que pasa por aperturas exteriores [kg/s].
# Acumulado por GasExchangeSystem (venteo por presión + ventilación natural).
# Reseteado al inicio de cada _step_gas_exchange en SimulationEngine.
var mdot_vent_kg_s: float = 0.0

# Eventos
var flashover_triggered: bool = false
var flashover_time_s: float = -1.0
var fire_spread_exposure_s: float = 0.0
var backdraft_triggered: bool = false
var backdraft_time_s: float = -1.0
var backdraft_active: bool = false
var backdraft_phase_time_s: float = 0.0
var backdraft_cooldown_s: float = 0.0
# Fracción volumétrica del gas combustible no quemado en la sala — SF-AUD-013.
# Calculada a partir de retained_unburned_MJ, calor de combustión y densidad del gas.
# Se compara con LFL/UFL para determinar si la mezcla es inflamable (backdraft).
var unburned_gas_vol_frac: float = 0.0

# Masa de vapor de agua generado por evaporación del chorro de supresión — SF-AUD-017.
# Producido en proporción a suppression_evaporation_fraction; decae por condensación
# y arrastre ventilatorio (suppression_steam_condensation_rate [1/s]).
var steam_kg: float = 0.0


func floor_area_m2() -> float:
	return width_m * length_m


func volume_m3() -> float:
	return width_m * length_m * height_m


## Volumen de la zona superior (capa caliente), m³. Fase 2A.
func upper_volume_m3() -> float:
	var h_upper: float = maxf(0.0, height_m - clampf(thermal_layer_m, 0.0, height_m))
	return floor_area_m2() * h_upper


## Volumen de la zona inferior (capa fría), m³. Fase 2A.
func lower_volume_m3() -> float:
	return maxf(0.0, volume_m3() - upper_volume_m3())


func zone_total_mass_kg() -> float:
	return maxf(0.0, upper_gas_kg) + maxf(0.0, lower_gas_kg)


func zone_total_energy_kj() -> float:
	return maxf(0.0, upper_energy_kj) + maxf(0.0, lower_energy_kj)


## Masa de O₂ en la zona superior, kg. Fase 2A.
func upper_o2_mass_kg(air_density: float = 1.2) -> float:
	return upper_volume_m3() * air_density * o2_upper


## Masa de O₂ en la zona inferior, kg. Fase 2A.
func lower_o2_mass_kg(air_density: float = 1.2) -> float:
	return lower_volume_m3() * air_density * o2_lower


func reset_dynamic_state(ambient_temp_c: float, ambient_o2: float) -> void:
	temp_upper_c = ambient_temp_c
	temp_upper_raw_c = ambient_temp_c
	temp_upper_clamped = false
	temp_upper_clamp_time_s = 0.0
	temp_upper_clamp_count = 0
	temp_lower_c = ambient_temp_c
	o2 = ambient_o2
	o2_upper = ambient_o2
	o2_lower = ambient_o2
	upper_o2_mass_tracked = -1.0
	canonical_o2_upper_updated = false
	fire_o2_mode_used = "legacy"
	fire_o2_ref = ambient_o2
	fire_o2_min_ref = 0.0
	smoke_kg = 0.0
	smoke_prod_kg_s = 0.0
	soot_fraction = 1.0
	chi_rad_normal = -1.0
	h_layer_m = height_m
	thermal_layer_m = height_m
	upper_gas_kg = 0.0
	upper_energy_kj = 0.0
	lower_gas_kg = maxf(0.0, volume_m3() * 1.2)
	lower_energy_kj = 0.0
	two_zone_boundary_mass_kg = 0.0
	two_zone_boundary_energy_kj = 0.0
	two_zone_opening_upper_in_kg = 0.0
	two_zone_opening_upper_out_kg = 0.0
	two_zone_opening_lower_in_kg = 0.0
	two_zone_opening_lower_out_kg = 0.0
	upper_radiative_loss_kw = 0.0
	layer_150c_m = height_m
	co_kg = 0.0
	co_upper_kg = 0.0
	co2_kg = 0.0
	co2_upper = 0.0004
	co2_upper_kg = 0.0
	hcn_kg = 0.0
	hcn_upper_kg = 0.0
	hcl_kg = 0.0
	acrolein_kg = 0.0
	formaldehyde_kg = 0.0
	fec_irritant = 0.0
	fed = 0.0
	fed_co = 0.0
	fed_hcn = 0.0
	fed_hypoxia = 0.0
	fed_heat = 0.0
	svv_pct = 100.0
	svv_worst_pct = 100.0
	visibility_m = 30.0
	fire = null
	fire_time_s = 0.0
	hrr_kw = 0.0
	hrr_target_kw = 0.0
	pyrolysis_kw = 0.0
	burned_hrr_kw = 0.0
	unburned_generation_kw = 0.0
	flame_hrr_target_kw = 0.0
	smolder_hrr_target_kw = 0.0
	pool_release_hrr_target_kw = 0.0
	fire_smoldering = false
	fire_dormant_time_s = 0.0
	fire_low_hrr_time_s = 0.0
	fire_o2_extinguished = false
	o2_hrr_factor = 1.0
	retained_unburned_MJ = 0.0
	ventilation_response_factor = 0.0
	combustion_regime = "EXTINGUISHED"
	overpressure_pa = 0.0
	pressure_pa_therm = 0.0
	ceiling_jet_temp_c = ambient_temp_c
	floor_heat_flux_kw_m2 = 0.0
	flashover_q_thomas_kw = 0.0
	flashover_q_mqh_kw = 0.0
	flashover_triggered = false
	flashover_time_s = -1.0
	fire_spread_exposure_s = 0.0
	backdraft_triggered = false
	backdraft_time_s = -1.0
	backdraft_active = false
	backdraft_phase_time_s = 0.0
	backdraft_cooldown_s = 0.0
	unburned_gas_vol_frac = 0.0
	steam_kg = 0.0
	# SF-AUD-030: resetear perfil 1D de pared
	wall_T_mid_c = ambient_temp_c
	wall_T_outer_c = ambient_temp_c
	mdot_vent_kg_s = 0.0
	c_burned_total_kg = 0.0
	c_untracked_products_kg = 0.0
	c_preclamp_excess_kg = 0.0
	c_postclamp_excess_kg = 0.0
	carbon_conservation_error_kg = 0.0
	c_exited_kg = 0.0
	c_deposited_kg = 0.0

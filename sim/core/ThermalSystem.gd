extends RefCounted
class_name ThermalSystem

const LayerInterfaceModel = preload("res://sim/core/LayerInterfaceModel.gd")

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
var _zone_fire_solver: ZoneFireSolver

# M1: rama two-zone canonica. Default false conserva exactamente legacy.
var two_zone_solver_enabled: bool = false

# Phase 2A: sync zonal mass (upper_gas_kg/lower_gas_kg) desde geometría para todas las salas.
# Default false = no-op absoluto; no cambia ningún resultado hasta que un caso active el flag.
var phase2a_zone_mass_canonical: bool = false

# Masa térmica de paredes
var wall_heat_capacity_kj_m2_k: float = 20.0  # kJ/m²K — cap. efectiva superficie (~5cm yeso)
var wall_core_decay_per_s: float = 0.0002     # τ ≈ 5000 s — conducción de la superficie al núcleo
# Temperatura actual de la superficie de pared por habitación (se resetea en configure())
var _wall_surface_temp_c: Dictionary = {}

# SF-AUD-030: 5-nodo PDE 1D pared, Crank-Nicolson
# _wall_pde_nodes_c[room_id] = Array[float] — T[0..4] (T[0]=cara interior, T[4]=cara exterior)
var wall_pde_enabled: bool = true
var _wall_pde_nodes_c: Dictionary = {}
# Coeficiente convectivo interior gas→cara pared [kW/(m²·K)]
# BC Robin en T[0] del PDE. ISO 6946 Rsi≈0.13 m²K/W → h≈0.077; aquí 0.025 como valor por defecto
# (mismo orden que h_ext=0.025 exterior). Configurable via override "h_conv_int_kw_m2_k".
var h_conv_int_kw_m2_k: float = 0.025

const STEFAN_BOLTZMANN_KW_M2_K4: float = 5.670374419e-11

# SF-R6: ZoneFireSolver — carry convectivo HCN/irritantes (deshabilitado por defecto).
# Activar en fase 2 tras rebaseline de suite. Ver ZoneFireSolver.gd.
var hot_gas_hcn_carry_fraction: float = 0.0
var hot_gas_irritant_carry_fraction: float = 0.0

# Parámetros térmicos
# SF-R-2026-05-18: reducidos de 0.025→0.013 y 0.008→0.004 para mejorar
# realismo de la capa caliente. Las tasas empíricas anteriores enfriaban
# artificialmente la zona superior (CFAST no tiene estos términos explícitos),
# manteniendo la densidad del gas alta y la capa de interfaz demasiado alta.
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
var phase3_stairwell_heat_bridge_enabled: bool = false
var phase3_stairwell_heat_bridge_kg_s_m2: float = 0.0
var phase3_stairwell_heat_bridge_max_fraction_per_step: float = 0.018
var phase3_stairwell_heat_bridge_hot_temp_start_c: float = 30.0
var phase3_stairwell_heat_bridge_hot_temp_full_c: float = 90.0
var phase3_stairwell_heat_bridge_hole_multiplier: float = 1.0
var phase3_stairwell_heat_bridge_vertical_multiplier: float = 2.0
var phase3_stairwell_heat_bridge_target_lift_fraction: float = 0.012
var phase3_stairwell_heat_bridge_target_max_temp_c: float = 120.0
var hot_gas_species_carry_fraction: float = 0.72
var hot_gas_smoke_carry_fraction: float = 0.38
var hot_gas_species_max_fraction_per_step: float = 0.22
# Phase 2E — experimento transporte dos zonas (default OFF — no altera baseline)
# Cuando true: CO transportado al destino se reparte upper/lower según geometría de capa.
var phase2e_two_zone_transport_enabled: bool = false
## Phase 2E — modo de deposición CO cuando flag ON (ignorado si flag OFF)
## "all_upper"       : 100% CO al upper (igual que baseline; cancela el split geométrico)
## "geometric_split" : split según h_upper_tgt / height_m  (Experimento 1)
## "upper_floor_90"  : geometric_split con mínimo 90% a upper
## "upper_floor_95"  : geometric_split con mínimo 95% a upper
var phase2e_co_deposition_mode: String = "all_upper"
# Phase 2F — mixing CO inter-capa (mecanismo separado; default OFF — no altera baseline)
# co_kg total conservado: sólo reduce co_upper_kg (lower = co_kg - co_upper_kg aumenta implícitamente).
# Llamado DESPUÉS de _flush_contaminant_deltas(), sin interferir con el transporte principal.
var phase2f_co_interlayer_mixing_enabled: bool = false
## fracción de co_upper_kg por segundo transferida de upper a lower implícito (default 0.0)
var phase2f_co_interlayer_mixing_rate: float = 0.0
## guard que condiciona el mixing por sala:
## "no_guard"                                   : aplica siempre
## "only_when_upper_gas_kg_lt_0_1"              : sólo si room.upper_gas_kg < 0.1
## "only_when_hot_layer_interface_above_1_8m"   : sólo si interfaz > 1.8 m
## "only_when_no_occupant_in_upper_probe"       : sólo si ninguna víctima respira en upper
var phase2f_co_interlayer_mixing_guard: String = "no_guard"
# Phase 2I — CO₂ upper fraction floor en sala fuego (default OFF = 0.0)
# Cuando > 0.0: co2_upper_kg se eleva a mín. co2_kg × fraction en salas con fuego activo.
# co2_kg invariante (sin creación/destrucción). Afecta co2_lower_kg implícito = co2_kg - co2_upper_kg.
# NOTA: room.co2_upper (fracción molar, log CO2u=, FED V_CO2 en upper) NO se modifica.
# Objetivo del experimento: medir si elevar co2_upper_kg afecta sentinels FED/CO.
var phase2i_co2_upper_fraction: float = 0.0
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
# SF-AUD-009: fuego confinado — cuando L_llama ≥ room.height_m, la llama llena el
# compartimento y z_eff ya no es (z_interfaz - L_llama) ≈ 0.1 m sino room.height_m.
# plume_confined_z_eff_fraction permite escalar room.height_m (default 1.0 = físico).
@export var plume_confined_flame_enabled: bool = true
@export var plume_confined_z_eff_fraction: float = 1.0
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
var phase4b_wall_reradiation_during_fire_enabled: bool = false
var phase4b_wall_reradiation_during_fire_gain: float = 1.0
var hrr_rad_wall_fraction: float = 0.0       # fracción de χ_rad·HRR depositada en superficies (R2-4)
var two_zone_convective_heat_multiplier: float = 1.0
var upper_heat_capture_min: float = 0.10      # obsoleto — usar hrr_chi_rad_normal
var upper_heat_capture_max: float = 0.25      # obsoleto — usar hrr_chi_rad_normal
var upper_heat_capture_outside_open_bonus: float = 0.0  # obsoleto

var doorway_o2_min_band_m: float = 0.25
var doorway_o2_smoke_weight: float = 0.35
var doorway_o2_pressure_weight: float = 0.65
# SF-AUD-010: cuando true, el flujo inter-sala usa la fórmula Bernoulli dos zonas
# con plano neutro calculado (SFPE Handbook §3.2; CFAST TN 1889v1 §2.2).
# Q = Cd·W·f·(2/3)·h_zona^(3/2)·sqrt(2g·ΔT/T_ref) [m³/s].
# Default true → paridad CFAST (2026-05-17).
var vent_bernoulli_enabled: bool = true
var pressure_spill_ref_delta_pa: float = 8.0
var interior_spill_start_layer_m: float = 2.0

# Phase 5 M3: contraflujo térmico bidireccional por puertas interiores.
# Cuando true: flujo Bernoulli adicional desde zona caliente → zona fría incluso
# cuando hot_band_m ≈ 0 (capa caliente alta, flow_state active=false).
# Default false = no-op exacto. Activar por caso vía engine_overrides.
var doorway_thermal_counterflow_enabled: bool = false
var doorway_thermal_counterflow_gain: float = 1.0
var doorway_thermal_counterflow_min_delta_c: float = 5.0
# Phase 5 M3b: fracción del flujo másico superior que retorna como aire fresco por la zona inferior.
# 0.0 = no-op (default). 1.0 = retorno simétrico completo (conservación de masa).
# Repone O₂ en la sala de fuego → sostiene HRR → alcanza plateau 158-168°C (CFAST target).
var doorway_thermal_counterflow_o2_return_fraction: float = 0.0

# Phase 6: intercambio canónico dos zonas por puertas interiores (masa + entalpía + O₂).
# Reemplaza M3/M3b con un modelo físico conservativo bidireccional:
#   - Flujo superior (hot.upper → cold.upper): O₂ upper actualizado tras el movimiento de masa existente.
#   - Flujo inferior (cold.lower → hot.lower): masa + temperatura + O₂ de zona inferior.
# Default false = no-op exacto (M3/M3b mantienen su comportamiento previo).
var canonical_doorway_exchange_enabled: bool = false
## Fracción del flujo Bernoulli inferior aplicada al flujo de zona inferior (calibración).
## 1.0 = flujo conservativo completo (caudal inferior = upper × ρ_hot/ρ_cold).
var canonical_doorway_lower_flow_frac: float = 1.0
## Phase 2G: multiplicador sobre el flujo inferior canónico. 1.0 = no-op exacto.
## Compensa subestimación Bernoulli vs CFAST PDE. Activar sólo per-caso.
var canonical_doorway_lower_inflow_multiplier: float = 1.0

# Phase 3A: ODE de sobrepresión termogénica por fuego.
# dp/dt = (γ-1)×HRR_kw×1000/V [Pa/s] - loss_coeff×dp [Pa/s]
# Escribe en room.pressure_pa_therm (campo existente en RoomModel, default 0.0).
# Default false = no-op absoluto: pressure_pa_therm permanece en 0.0 siempre.
var phase3a_pressure_ode_enabled: bool = false
# Coeficiente de disipación [1/s]. Mayor = disipación más rápida → dp más bajo.
# Calibrado: coeff≈24000 → dp_ss≈0.1 Pa para 300kW en 50m³.
var phase3a_pressure_vent_loss_coeff: float = 24000.0
# Cap de dp_fire para evitar runaway numérico. 500 Pa >> valor real (~0.1 Pa).
var phase3a_pressure_max_pa: float = 500.0

# Phase 3B: corrección del plano neutro con dp_fire (pressure_pa_therm).
# Aplica post-caché: δh = dp_hot/(ρ_cold·g·H_door) → neutral_plane_f baja → más inflow.
# Default false = plano neutro sin modificar. No-op si Phase 3A = false o dp ≈ 0.
var phase3b_neutral_plane_dp_correction: bool = false

# Phase 3D: fracción del inflow inferior que va directamente a hot.upper vía pluma.
# 0.0 = no-op (todo el inflow va a hot.lower como antes).
# Activar per-caso. Solo activa si canonical_doorway_exchange_enabled=true.
var canonical_doorway_plume_direct_upper_frac: float = 0.0

# FED (ISO 13571) — componentes asfixiantes disponibles en el modelo
var fed_hypoxia_enabled: bool = true
var fed_hypoxia_a: float = 8.13
var fed_hypoxia_b: float = 0.54
# Altura de capa superior usada para determinar si el ocupante está inmerso (m).
# Valor por defecto 1.8 m (adulto de pie, ISO 13571). Puede sobreescribirse por caso
# cuando el escenario implica ocupantes agachados, niños, o análisis conservador.
var fed_upper_layer_threshold_m: float = 1.8
var _fed_layer_warning_keys: Dictionary = {}

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
# SF-AUD-031: reparte la conducción inter-sala entre sub-pared superior e inferior.
# Cuando true, la ΔT motriz pondera temp_upper/lower_c según la fracción de altura
# de cada sala que está en capa caliente; y el calor recibido se reparte entre
# upper_energy_kj y temp_lower_c en proporción a la capa caliente del receptor.
# Backward-compatible: false → comportamiento anterior.
var wall_layer_aware_conduction: bool = false
var _adjacent_pairs: Array = []
var _adjacency_built: bool = false

# Budget energético — diagnóstico CFAST-lite (no intrusivo)
# Activar con energy_budget_enabled=true en configure(). Warning si residual > umbral.
var energy_budget_enabled: bool = false
var energy_budget_warn_fraction: float = 0.10
## Último budget por sala: {room_id -> {e_fire_kj, q_rad_kj, q_to_lower_kj, q_to_ambient_kj,
## q_wall_abs_kj, q_wall_emit_kj, de_upper_kj, q_residual_kj, chi_rad}}
var _energy_budget: Dictionary = {}
## Acumulados por sala (toda la simulación): {room_id -> float}
## Solo activo cuando energy_budget_enabled=true.
var _bud_cum_e_fire_kj: Dictionary = {}
var _bud_cum_q_residual_kj: Dictionary = {}

# SF-R6 Phase 3: residuales de conservación del transporte de contaminantes.
# Se resetean al inicio de cada step(). Con Phase 4 (delta accumulation) el residual
# por llamada es siempre 0 por construcción. Se mantiene para compatibilidad con CI.
var _transport_co2_residual_kg: float = 0.0
var _transport_hcn_residual_kg: float = 0.0
var _transport_co_residual_kg: float = 0.0
var _transport_smoke_residual_kg: float = 0.0
var _transport_call_count: int = 0

# SF-R6 Phase 4: acumuladores delta para transporte simultáneo de contaminantes.
# Eliminan efectos de ordenación: todas las lecturas usan el estado pre-bucle,
# todas las escrituras se aplican juntas en _flush_contaminant_deltas().
# Indexados por room.id (int). Se resetean al inicio de step(), se aplican al final
# del bucle de aperturas.
var _delta_co_kg: Dictionary = {}
var _delta_co_upper_kg: Dictionary = {}
var _delta_co2_kg: Dictionary = {}
var _delta_co2_upper_kg: Dictionary = {}
var _delta_smoke_kg: Dictionary = {}
var _delta_hcn_kg: Dictionary = {}
var _delta_hcn_upper_kg: Dictionary = {}
var _delta_hcl_kg: Dictionary = {}
var _delta_acrolein_kg: Dictionary = {}
var _delta_formaldehyde_kg: Dictionary = {}


func get_energy_budget() -> Dictionary:
	# Fusiona el snapshot del paso actual con los acumulados de toda la simulación.
	var result: Dictionary = {}
	for room_id in _energy_budget.keys():
		result[room_id] = _energy_budget[room_id].duplicate()
		result[room_id]["cum_e_fire_kj"] = _bud_cum_e_fire_kj.get(room_id, 0.0)
		result[room_id]["cum_q_residual_kj"] = _bud_cum_q_residual_kj.get(room_id, 0.0)
	# Salas que tuvieron fuego antes pero no en el último paso (e.g. fuego extinto).
	for room_id in _bud_cum_e_fire_kj.keys():
		if room_id not in result:
			result[room_id] = {
				"e_fire_kj": 0.0, "q_fire_rad_kj": 0.0, "q_rad_kj": 0.0,
				"q_to_lower_kj": 0.0, "q_to_ambient_kj": 0.0,
				"q_wall_abs_kj": 0.0, "q_wall_emit_kj": 0.0,
				"de_upper_kj": 0.0, "q_residual_kj": 0.0, "chi_rad": 0.0,
				"cum_e_fire_kj": _bud_cum_e_fire_kj.get(room_id, 0.0),
				"cum_q_residual_kj": _bud_cum_q_residual_kj.get(room_id, 0.0),
			}
	return result


## Devuelve el residual acumulado de conservación de transporte para el último step().
## Cada especie debería ser ~0.0 en un transporte exactamente conservativo.
## Residuales > 1e-9 kg indican posibles bugs de contabilidad en _transfer_hot_gas_contaminants.
func get_transport_residuals() -> Dictionary:
	return {
		"co2_residual_kg": _transport_co2_residual_kg,
		"hcn_residual_kg": _transport_hcn_residual_kg,
		"co_residual_kg": _transport_co_residual_kg,
		"smoke_residual_kg": _transport_smoke_residual_kg,
		"call_count": _transport_call_count,
	}


func set_references(building: BuildingModel, smoke_model: SmokeModel) -> void:
	_building = building
	_smoke_model = smoke_model


func set_zone_fire_solver(solver: ZoneFireSolver) -> void:
	_zone_fire_solver = solver


func configure(settings: Dictionary) -> void:
	two_zone_solver_enabled = bool(settings.get("two_zone_solver_enabled", two_zone_solver_enabled))
	upper_to_lower_loss_rate = float(settings.get("upper_to_lower_loss_rate", upper_to_lower_loss_rate))
	upper_to_ambient_loss_rate = float(settings.get("upper_to_ambient_loss_rate", upper_to_ambient_loss_rate))
	lower_layer_warming_rate = float(settings.get("lower_layer_warming_rate", lower_layer_warming_rate))
	lower_layer_energy_fade_m = float(settings.get("lower_layer_energy_fade_m", lower_layer_energy_fade_m))
	lower_layer_energy_fade_m = float(settings.get("lower_layer_energy_fade_m", lower_layer_energy_fade_m))
	wall_absorption_rate = float(settings.get("wall_absorption_rate", wall_absorption_rate))
	wall_heat_capacity_kj_m2_k = float(settings.get("wall_heat_capacity_kj_m2_k", wall_heat_capacity_kj_m2_k))
	wall_core_decay_per_s = float(settings.get("wall_core_decay_per_s", wall_core_decay_per_s))
	wall_pde_enabled = bool(settings.get("wall_pde_enabled", wall_pde_enabled))
	h_conv_int_kw_m2_k = float(settings.get("h_conv_int_kw_m2_k", h_conv_int_kw_m2_k))
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
	phase3_stairwell_heat_bridge_enabled = bool(
		settings.get("phase3_stairwell_heat_bridge_enabled", phase3_stairwell_heat_bridge_enabled)
	)
	phase3_stairwell_heat_bridge_kg_s_m2 = float(
		settings.get("phase3_stairwell_heat_bridge_kg_s_m2", phase3_stairwell_heat_bridge_kg_s_m2)
	)
	phase3_stairwell_heat_bridge_max_fraction_per_step = float(
		settings.get(
			"phase3_stairwell_heat_bridge_max_fraction_per_step",
			phase3_stairwell_heat_bridge_max_fraction_per_step
		)
	)
	phase3_stairwell_heat_bridge_hot_temp_start_c = float(
		settings.get(
			"phase3_stairwell_heat_bridge_hot_temp_start_c",
			phase3_stairwell_heat_bridge_hot_temp_start_c
		)
	)
	phase3_stairwell_heat_bridge_hot_temp_full_c = float(
		settings.get(
			"phase3_stairwell_heat_bridge_hot_temp_full_c",
			phase3_stairwell_heat_bridge_hot_temp_full_c
		)
	)
	phase3_stairwell_heat_bridge_hole_multiplier = float(
		settings.get(
			"phase3_stairwell_heat_bridge_hole_multiplier",
			phase3_stairwell_heat_bridge_hole_multiplier
		)
	)
	phase3_stairwell_heat_bridge_vertical_multiplier = float(
		settings.get(
			"phase3_stairwell_heat_bridge_vertical_multiplier",
			phase3_stairwell_heat_bridge_vertical_multiplier
		)
	)
	phase3_stairwell_heat_bridge_target_lift_fraction = float(
		settings.get(
			"phase3_stairwell_heat_bridge_target_lift_fraction",
			phase3_stairwell_heat_bridge_target_lift_fraction
		)
	)
	phase3_stairwell_heat_bridge_target_max_temp_c = float(
		settings.get(
			"phase3_stairwell_heat_bridge_target_max_temp_c",
			phase3_stairwell_heat_bridge_target_max_temp_c
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
	# SF-R6 Phase 2: carry convectivo HCN / irritantes.
	hot_gas_hcn_carry_fraction = float(
		settings.get("hot_gas_hcn_carry_fraction", hot_gas_hcn_carry_fraction)
	)
	hot_gas_irritant_carry_fraction = float(
		settings.get("hot_gas_irritant_carry_fraction", hot_gas_irritant_carry_fraction)
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
	doorway_thermal_counterflow_enabled = bool(settings.get("doorway_thermal_counterflow_enabled", doorway_thermal_counterflow_enabled))
	doorway_thermal_counterflow_gain = float(settings.get("doorway_thermal_counterflow_gain", doorway_thermal_counterflow_gain))
	doorway_thermal_counterflow_min_delta_c = float(settings.get("doorway_thermal_counterflow_min_delta_c", doorway_thermal_counterflow_min_delta_c))
	doorway_thermal_counterflow_o2_return_fraction = float(settings.get("doorway_thermal_counterflow_o2_return_fraction", doorway_thermal_counterflow_o2_return_fraction))
	canonical_doorway_exchange_enabled = bool(settings.get("canonical_doorway_exchange_enabled", canonical_doorway_exchange_enabled))
	canonical_doorway_lower_flow_frac = float(settings.get("canonical_doorway_lower_flow_frac", canonical_doorway_lower_flow_frac))
	canonical_doorway_lower_inflow_multiplier = float(settings.get("canonical_doorway_lower_inflow_multiplier", canonical_doorway_lower_inflow_multiplier))
	phase3a_pressure_ode_enabled = bool(settings.get("phase3a_pressure_ode_enabled", phase3a_pressure_ode_enabled))
	phase3a_pressure_vent_loss_coeff = float(settings.get("phase3a_pressure_vent_loss_coeff", phase3a_pressure_vent_loss_coeff))
	phase3a_pressure_max_pa = float(settings.get("phase3a_pressure_max_pa", phase3a_pressure_max_pa))
	phase3b_neutral_plane_dp_correction = bool(settings.get("phase3b_neutral_plane_dp_correction", phase3b_neutral_plane_dp_correction))
	canonical_doorway_plume_direct_upper_frac = float(settings.get("canonical_doorway_plume_direct_upper_frac", canonical_doorway_plume_direct_upper_frac))
	plume_mccaffrey_enabled = bool(settings.get("plume_mccaffrey_enabled", plume_mccaffrey_enabled))
	plume_mccaffrey_qc_fraction = float(settings.get("plume_mccaffrey_qc_fraction", plume_mccaffrey_qc_fraction))
	plume_fire_diameter_m = float(settings.get("plume_fire_diameter_m", plume_fire_diameter_m))
	plume_confined_flame_enabled = bool(settings.get("plume_confined_flame_enabled", plume_confined_flame_enabled))
	plume_confined_z_eff_fraction = float(settings.get("plume_confined_z_eff_fraction", plume_confined_z_eff_fraction))
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
	fed_upper_layer_threshold_m = float(settings.get("fed_upper_layer_threshold_m", fed_upper_layer_threshold_m))
	wall_conduction_enabled = bool(settings.get("wall_conduction_enabled", wall_conduction_enabled))
	wall_conduction_u_kw_m2_k = float(settings.get("wall_conduction_u_kw_m2_k", wall_conduction_u_kw_m2_k))
	wall_conduction_max_fraction_per_step = float(
		settings.get("wall_conduction_max_fraction_per_step", wall_conduction_max_fraction_per_step)
	)
	wall_adjacency_tolerance_m = float(settings.get("wall_adjacency_tolerance_m", wall_adjacency_tolerance_m))
	wall_layer_aware_conduction = bool(settings.get("wall_layer_aware_conduction", wall_layer_aware_conduction))
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
	phase4b_wall_reradiation_during_fire_enabled = bool(settings.get("phase4b_wall_reradiation_during_fire_enabled", phase4b_wall_reradiation_during_fire_enabled))
	phase4b_wall_reradiation_during_fire_gain = float(settings.get("phase4b_wall_reradiation_during_fire_gain", phase4b_wall_reradiation_during_fire_gain))
	two_zone_convective_heat_multiplier = float(
		settings.get("two_zone_convective_heat_multiplier", two_zone_convective_heat_multiplier)
	)
	radiation_opening_enabled = bool(settings.get("radiation_opening_enabled", radiation_opening_enabled))
	radiation_flame_emissivity = float(settings.get("radiation_flame_emissivity", radiation_flame_emissivity))
	radiation_opening_view_factor = float(settings.get("radiation_opening_view_factor", radiation_opening_view_factor))
	radiation_smoke_attenuation_factor = float(settings.get("radiation_smoke_attenuation_factor", radiation_smoke_attenuation_factor))
	radiation_min_source_temp_c = float(settings.get("radiation_min_source_temp_c", radiation_min_source_temp_c))
	radiation_max_fraction_per_step = float(settings.get("radiation_max_fraction_per_step", radiation_max_fraction_per_step))
	energy_budget_enabled = bool(settings.get("energy_budget_enabled", energy_budget_enabled))
	energy_budget_warn_fraction = float(settings.get("energy_budget_warn_fraction", energy_budget_warn_fraction))
	vent_bernoulli_enabled = bool(settings.get("vent_bernoulli_enabled", vent_bernoulli_enabled))
	phase2e_two_zone_transport_enabled = bool(settings.get("phase2e_two_zone_transport_enabled", phase2e_two_zone_transport_enabled))
	phase2e_co_deposition_mode = String(settings.get("phase2e_co_deposition_mode", phase2e_co_deposition_mode))
	phase2f_co_interlayer_mixing_enabled = bool(settings.get("phase2f_co_interlayer_mixing_enabled", phase2f_co_interlayer_mixing_enabled))
	phase2f_co_interlayer_mixing_rate = float(settings.get("phase2f_co_interlayer_mixing_rate", phase2f_co_interlayer_mixing_rate))
	phase2f_co_interlayer_mixing_guard = String(settings.get("phase2f_co_interlayer_mixing_guard", phase2f_co_interlayer_mixing_guard))
	phase2i_co2_upper_fraction = float(settings.get("phase2i_co2_upper_fraction", phase2i_co2_upper_fraction))
	phase2a_zone_mass_canonical = bool(settings.get("phase2a_zone_mass_canonical", phase2a_zone_mass_canonical))


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

	# SF-R6 Phase 3: reset acumuladores de residual de transporte para este paso.
	_transport_co2_residual_kg = 0.0
	_transport_hcn_residual_kg = 0.0
	_transport_co_residual_kg = 0.0
	_transport_smoke_residual_kg = 0.0
	_transport_call_count = 0

	# SF-R6 Phase 4: reset delta accumuladores de contaminantes.
	_delta_co_kg.clear()
	_delta_co_upper_kg.clear()
	_delta_co2_kg.clear()
	_delta_co2_upper_kg.clear()
	_delta_smoke_kg.clear()
	_delta_hcn_kg.clear()
	_delta_hcn_upper_kg.clear()
	_delta_hcl_kg.clear()
	_delta_acrolein_kg.clear()
	_delta_formaldehyde_kg.clear()

	var _bud_total_fire_kj: float = 0.0
	var _bud_total_residual_kj: float = 0.0
	if energy_budget_enabled:
		_energy_budget.clear()

	# Phase 2A: sincronizar masa zonal desde geometría actual para todas las salas.
	# Con flag=false (default) este bloque no se ejecuta — no-op garantizado.
	if phase2a_zone_mass_canonical:
		for _p2a_id in building.get_rooms().keys():
			var _p2a_room: RoomModel = building.get_room(_p2a_id)
			if _p2a_room == null:
				continue
			_p2a_room.upper_gas_kg = maxf(0.0, _p2a_room.upper_volume_m3() * 1.2)
			_p2a_room.lower_gas_kg = maxf(0.0, _p2a_room.lower_volume_m3() * 1.2)

	for room_id in building.get_rooms().keys():
		var room: RoomModel = building.get_room(room_id)
		if room == null:
			continue

		if two_zone_solver_enabled and _zone_fire_solver != null:
			_zone_fire_solver.ensure_room_state(room, ambient_c)

		room.upper_radiative_loss_kw = 0.0
		var _bud_e_before_kj: float = room.upper_energy_kj if energy_budget_enabled else 0.0
		# Entrainamiento de pluma — McCaffrey (NBSIR 79-1910) + Heskestad (1983)
		if two_zone_solver_enabled:
			_step_two_zone_plume_entrainment(room, dt, ambient_c)
		elif plume_mccaffrey_enabled and room.hrr_kw > 0.0:
			var qc_kw: float = room.hrr_kw * plume_mccaffrey_qc_fraction
			# Altura de llama Heskestad: L_f = 0.235·Q^0.4 - 1.02·D  [Q en kW, L en m]
			var l_flame_m: float = maxf(0.0, 0.235 * pow(room.hrr_kw, 0.4) - 1.02 * plume_fire_diameter_m)
			var z_m: float = maxf(room.thermal_layer_m, l_flame_m + 0.05)
			if l_flame_m < z_m:
				var z_eff_m: float
				if plume_confined_flame_enabled and l_flame_m >= room.height_m:
					# SF-AUD-009: fuego confinado — llama alcanza o supera el techo.
					# z_eff físico = room.height_m en vez del clamp 0.1 m (84× subdimensionado).
					z_eff_m = maxf(0.1, room.height_m * plume_confined_z_eff_fraction)
				else:
					z_eff_m = maxf(0.1, z_m - l_flame_m)
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
		# SF-AUD-015: si room.chi_rad_normal ≥ 0, usa el valor resuelto por combustible;
		# en otro caso (−1.0 = sin per-fuel), usa los globales del motor.
		var eff_chi_rad_normal: float = hrr_chi_rad_normal
		if room.chi_rad_normal >= 0.0:
			eff_chi_rad_normal = room.chi_rad_normal
		var eff_chi_rad_low_o2: float = eff_chi_rad_normal \
				* (hrr_chi_rad_low_o2 / maxf(0.01, hrr_chi_rad_normal))
		var chi_rad: float = lerpf(
			eff_chi_rad_low_o2,
			eff_chi_rad_normal,
			clampf(inverse_lerp(0.06, 0.12, room.o2), 0.0, 1.0)
		)
		var conv_fraction: float = clampf(1.0 - chi_rad, 0.0, 0.90)
		if two_zone_solver_enabled and two_zone_convective_heat_multiplier > 0.0:
			conv_fraction = minf(0.90, conv_fraction * two_zone_convective_heat_multiplier)
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
		var wall_area_m2: float = room.floor_area_m2() * 2.0
		var t_wall_c: float = _wall_surface_temp_c.get(room.id, ambient_c)
		# SF-AUD-014: 1D lumped conduction per-material cuando k/d/rho/cp están definidos.
		# Si algún sentinel (-1.0) → fallback a parámetros globales legacy.
		# SF-AUD-030: cuando el PDE está activo, _wall_surface_temp_c viene de T[0] del PDE
		# (actualizado por _step_wall_pde en el paso anterior). En ese caso se usa h_conv_int
		# para el intercambio gas↔pared y se omite la actualización lumped de _wall_surface_temp_c.
		var wall_h_k_eff: float  # kW/m²·K → conductancia efectiva superficial
		var wall_capacity_kj_k: float
		var _use_material_wall: bool = room.wall_k_kw_m_k > 0.0 and room.wall_thickness_m > 0.0
		var _pde_drives_wall: bool = _use_material_wall and wall_pde_enabled
		if _use_material_wall:
			# Cuando el PDE está activo usa h_conv_int (BC Robin del PDE) para consistencia.
			# Cuando no está activo usa k/d (lumped through-wall conductance).
			wall_h_k_eff = h_conv_int_kw_m2_k if _pde_drives_wall else room.wall_k_kw_m_k / maxf(0.001, room.wall_thickness_m)
			var _rho: float = room.wall_rho_kg_m3 if room.wall_rho_kg_m3 > 0.0 else 800.0
			var _cp: float = room.wall_cp_kj_kg_k if room.wall_cp_kj_kg_k > 0.0 else 1.0
			wall_capacity_kj_k = _rho * _cp * room.wall_thickness_m * wall_area_m2
		else:
			wall_h_k_eff = -1.0
			wall_capacity_kj_k = wall_heat_capacity_kj_m2_k * wall_area_m2
		# Absorción gas → pared (cuando el gas superior está más caliente que la pared)
		var wall_abs_delta_t: float = maxf(0.0, room.temp_upper_c - t_wall_c)
		var _open_abs_mult: float = 1.0 + outside_open_wall_absorption_multiplier * outside_open_factor
		var wall_absorption_kj: float
		if _use_material_wall:
			wall_absorption_kj = wall_h_k_eff * wall_area_m2 * wall_abs_delta_t * _open_abs_mult * dt
		else:
			wall_absorption_kj = room.upper_gas_kg \
					* wall_abs_delta_t \
					* wall_absorption_rate \
					* _open_abs_mult \
					* dt
		# Re-emisión pared → gas (cuando la pared está más caliente que el gas superior)
		# Solo cuando no hay fuego activo en todo el edificio: durante el incendio
		# la emisión interferiría con la dinámica de combustión en salas adyacentes.
		# Después de la extinción, las paredes calientes sostienen la temperatura post-incendio.
		var wall_emit_delta_t: float = 0.0
		var wall_emission_kj: float = 0.0
		var wall_emit_allowed: bool = not any_fire_active or phase4b_wall_reradiation_during_fire_enabled
		if wall_emit_allowed:
			wall_emit_delta_t = maxf(0.0, t_wall_c - room.temp_upper_c)
			if _use_material_wall:
				wall_emission_kj = wall_h_k_eff * wall_area_m2 * wall_emit_delta_t * dt
			else:
				wall_emission_kj = room.upper_gas_kg \
						* wall_emit_delta_t \
						* wall_absorption_rate \
						* dt
			# Limitar emisión a un 15% de la energía almacenada en la pared por encima de ambiente
			if any_fire_active:
				wall_emission_kj *= maxf(0.0, phase4b_wall_reradiation_during_fire_gain)
			wall_emission_kj = minf(
				wall_emission_kj,
				maxf(0.0, t_wall_c - ambient_c) * wall_capacity_kj_k * 0.15
			)
		# Radiación directa del fuego → paredes (χ_rad · HRR · dt, bypasses upper gas)
		var q_rad_fire_kj: float = room.hrr_kw * chi_rad * dt
		# Actualizar temperatura de pared (solo modelo lumped — cuando PDE activo, lo hace _step_wall_pde)
		if not _pde_drives_wall:
			t_wall_c += (wall_absorption_kj + q_rad_fire_kj * hrr_rad_wall_fraction) / maxf(0.1, wall_capacity_kj_k)
			t_wall_c -= wall_emission_kj / maxf(0.1, wall_capacity_kj_k)
			# Enfriamiento lento de la superficie hacia el núcleo/ambiente
			t_wall_c = lerpf(t_wall_c, ambient_c, minf(wall_core_decay_per_s * dt, 0.99))
			_wall_surface_temp_c[room.id] = t_wall_c
			# SF-AUD-031b: exportar temperatura de pared del modelo lumped a wall_T_mid_c
			# para que el log y el validador reflejen la temperatura real (no 20°C constante).
			# No afecta física — wall_T_mid_c es sólo campo de estado/telemetría.
			room.wall_T_mid_c = t_wall_c

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

		if two_zone_solver_enabled and _zone_fire_solver != null:
			_zone_fire_solver.add_lower_energy(room, energy_to_lower_kj, ambient_c)
			_zone_fire_solver.remove_lower_energy_fraction(room, 0.0085 * dt, ambient_c)
			if outside_open_factor > 0.0 and outside_lower_fresh_air_cooling_rate > 0.0:
				_zone_fire_solver.remove_lower_energy_fraction(
					room,
					outside_lower_fresh_air_cooling_rate * outside_open_factor * dt,
					ambient_c
				)
			_zone_fire_solver.project_room_state(room, ambient_c, max_upper_temp_c)
		else:
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

		# Phase 3A: ODE de sobrepresión termogénica por fuego.
		# Integra dp_fire/dt = (γ-1)×HRR×1000/V - loss_coeff×dp.
		# No-op cuando phase3a_pressure_ode_enabled=false (default): no toca pressure_pa_therm.
		# GasExchangeSystem.step_thermodynamic_pressure() puede escribir en el mismo campo;
		# el else branch (= 0.0) destruia esa acumulacion -- eliminado.
		if phase3a_pressure_ode_enabled:
			var _p3a_v: float = maxf(1.0, room.volume_m3())
			var _p3a_source: float = 0.4 * room.hrr_kw * 1000.0 / _p3a_v  # Pa/s; 0.4 = γ-1
			var _p3a_loss: float = phase3a_pressure_vent_loss_coeff * room.pressure_pa_therm
			room.pressure_pa_therm += (_p3a_source - _p3a_loss) * dt
			room.pressure_pa_therm = clampf(room.pressure_pa_therm, 0.0, phase3a_pressure_max_pa)

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
				_bud_cum_e_fire_kj[room.id] = _bud_cum_e_fire_kj.get(room.id, 0.0) + _bud_e_fire_kj
				_bud_cum_q_residual_kj[room.id] = _bud_cum_q_residual_kj.get(room.id, 0.0) + _bud_q_residual_kj

	# ── Radiación inter-sala a través de aperturas ────────────────────────────
	_step_radiation_openings(building, dt, ambient_c)

	# ── Conducción inter-sala a través de paredes sólidas compartidas ──────────
	_step_wall_conduction(building, dt, ambient_c)

	# ── SF-AUD-030: perfil 1D pared Crank-Nicolson 5 nodos ────────────────────
	_step_wall_pde(building, dt, ambient_c)

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

		# Phase 3B: corrección post-caché del plano neutro con dp_fire (pressure_pa_therm).
		# dp_hot > 0 sólo cuando phase3a_pressure_ode_enabled=true y hay fuego activo.
		# Con defaults (3A=false → dp=0): esta corrección es 0 → no-op garantizado.
		if phase3b_neutral_plane_dp_correction and bool(flow_state.get("active", false)):
			var _p3b_hot: RoomModel = flow_state.get("hot_room", null)
			var _p3b_cold: RoomModel = flow_state.get("cold_room", null)
			if _p3b_hot != null and _p3b_cold != null and _p3b_hot.pressure_pa_therm > 0.01:
				var _p3b_rho_cold: float = gas_density_kg_m3(ambient_c)
				var _p3b_door_h: float = maxf(0.01, op.height_m)
				# δh = dp / (ρ_cold × g × H_door) → plano neutro sube → neutral_plane_f baja
				var _p3b_delta_f: float = _p3b_hot.pressure_pa_therm / (_p3b_rho_cold * 9.8 * _p3b_door_h * _p3b_door_h)
				var _p3b_npf: float = clampf(float(flow_state.get("neutral_plane_f", 0.5)) - _p3b_delta_f, 0.05, 0.90)
				if absf(_p3b_npf - float(flow_state.get("neutral_plane_f", 0.5))) > 0.001:
					flow_state["neutral_plane_f"] = _p3b_npf
					# Recompute Bernoulli flows with corrected neutral_plane_f
					var _p3b_cd: float = 0.65
					var _p3b_w: float = op.width_m * op.open_fraction
					var _p3b_g: float = 9.81
					var _p3b_hu: float = _p3b_npf * _p3b_door_h
					var _p3b_hl: float = (1.0 - _p3b_npf) * _p3b_door_h
					var _p3b_Th: float = _p3b_hot.temp_upper_c + 273.15
					var _p3b_Tc: float = _p3b_cold.temp_lower_c + 273.15
					var _p3b_Tref: float = (_p3b_Th + _p3b_Tc) * 0.5
					var _p3b_dTu: float = maxf(0.0, _p3b_Th - _p3b_Tc)
					var _p3b_qu: float = 0.0
					if _p3b_hu > 0.001 and _p3b_dTu > 0.5:
						_p3b_qu = _p3b_cd * _p3b_w * (2.0 / 3.0) * pow(_p3b_hu, 1.5) \
								* sqrt(2.0 * _p3b_g * _p3b_dTu / _p3b_Tref)
					var _p3b_Thl: float = _p3b_hot.temp_lower_c + 273.15
					var _p3b_dTl: float = maxf(0.0, _p3b_Tc - _p3b_Thl)
					var _p3b_ql: float = 0.0
					if _p3b_hl > 0.001 and _p3b_dTl > 0.5:
						_p3b_ql = _p3b_cd * _p3b_w * (2.0 / 3.0) * pow(_p3b_hl, 1.5) \
								* sqrt(2.0 * _p3b_g * _p3b_dTl / ((_p3b_Tc + _p3b_Thl) * 0.5))
					elif _p3b_qu > 0.0:
						_p3b_ql = _p3b_qu * (353.0 / maxf(50.0, _p3b_Th)) / maxf(0.001, 353.0 / maxf(50.0, _p3b_Tc))
					flow_state["bernoulli_upper_kg_s"] = _p3b_qu * (353.0 / maxf(50.0, _p3b_Th))
					flow_state["bernoulli_lower_kg_s"] = _p3b_ql * (353.0 / maxf(50.0, _p3b_Tc))

		_apply_outside_assisted_background_heat_exchange(
			room_a, room_b, op, dt, ambient_c, _outside_open_path_factor_callable
		)
		_apply_interior_background_heat_exchange(room_a, room_b, op, dt, ambient_c)
		_apply_stairwell_heat_bridge(room_a, room_b, op, dt, ambient_c)
		_apply_doorway_thermal_counterflow(room_a, room_b, op, flow_state, dt, ambient_c)
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
		var thermal_engagement: float = clampf(0.12 + heat_engagement * 0.65, 0.12, 0.90)
		var mass_exch: float
		if vent_bernoulli_enabled:
			# SF-AUD-010: flujo de masa Bernoulli dos zonas — capa alta saliente [kg/s · dt]
			# Phase 1.6: aplicar doorway_heat_exchange_coeff también al path Bernoulli
			# (antes solo se aplicaba al path clásico q_vol). Coeff=1.0 por defecto → sin cambio
			# para casos que no sobreescriben el parámetro.
			mass_exch = float(flow_state.get("bernoulli_upper_kg_s", 0.0)) * dt * doorway_heat_exchange_coeff
		else:
			var q_vol: float = 0.65 * neutral_pf * area_eff * sqrt(g_grav * hot_band_m * delta_t_k / ((t_hot_k + t_amb_k) * 0.5))
			mass_exch = q_vol * rho_air * dt * doorway_heat_exchange_coeff * thermal_engagement

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
		var stairwell_target_cap_enabled: bool = phase3_stairwell_heat_bridge_enabled \
				and (op.is_vertical or op.type == OpeningModel.Type.HOLE) \
				and (hot_room.kind == "escalera" or cold_room.kind == "escalera") \
				and phase3_stairwell_heat_bridge_target_max_temp_c > ambient_c
		var stairwell_target_cap_c: float = maxf(
			ambient_c,
			phase3_stairwell_heat_bridge_target_max_temp_c
		)
		if stairwell_target_cap_enabled:
			source_mix_temp_c = minf(source_mix_temp_c, stairwell_target_cap_c)
		var energy_moved_kj: float = gas_moved_kg * maxf(0.0, source_mix_temp_c - ambient_c)
		energy_moved_kj = minf(energy_moved_kj, maxf(0.0, hot_room.upper_energy_kj))
		if stairwell_target_cap_enabled:
			var cold_mass_after_kg: float = maxf(0.005, cold_room.upper_gas_kg + gas_moved_kg)
			var cold_energy_cap_kj: float = cold_mass_after_kg \
					* maxf(0.0, stairwell_target_cap_c - ambient_c)
			energy_moved_kj = minf(
				energy_moved_kj,
				maxf(0.0, cold_energy_cap_kj - cold_room.upper_energy_kj)
			)
		if energy_moved_kj <= 0.0:
			continue

		hot_room.upper_gas_kg = maxf(0.0, hot_room.upper_gas_kg - gas_moved_kg)
		cold_room.upper_gas_kg = maxf(0.0, cold_room.upper_gas_kg + gas_moved_kg)
		hot_room.upper_energy_kj = maxf(0.0, hot_room.upper_energy_kj - energy_moved_kj)
		cold_room.upper_energy_kj = maxf(0.0, cold_room.upper_energy_kj + energy_moved_kj)
		_transfer_hot_gas_contaminants(
			hot_room,
			cold_room,
			gas_moved_kg,
			hot_upper_gas_before_kg,
			thermal_engagement
		)

		# SF-R6: ZoneFireSolver — escribe la masa resuelta en el cache para downstream.
		flow_state["zone_resolved_upper_mass_kg"] = gas_moved_kg
		flow_state["zone_resolved_hot_room_id"] = hot_room.id
		flow_state["zone_resolved_cold_room_id"] = cold_room.id
		# Phase 6: intercambio canónico — O₂ upper + flujo inferior (cold.lower → hot.lower).
		if canonical_doorway_exchange_enabled:
			_apply_canonical_doorway_exchange(
				hot_room, cold_room, op, flow_state, dt, ambient_c, gas_moved_kg
			)
		sync_room_upper_layer(hot_room, dt)
		sync_room_upper_layer(cold_room, dt)
		_apply_post_transfer_vertical_mix(hot_room, dt)
		_apply_post_transfer_vertical_mix(cold_room, dt)
		update_room_layer_150c(hot_room, dt)
		update_room_layer_150c(cold_room, dt)

	# SF-R6 Phase 4: aplicar todos los deltas de contaminantes acumulados durante el bucle.
	_flush_contaminant_deltas(building)

	# Phase 2F: mixing experimental CO inter-capa (mecanismo separado; default OFF).
	_apply_phase2f_co_interlayer_mixing(building, dt)

	if two_zone_solver_enabled:
		reconcile_two_zone_building(building, dt)

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

		# Si el destino no tiene capa superior formada, crear masa mínima para absorber la energía
		if tgt.upper_gas_kg <= 0.0001:
			var tgt_density: float = gas_density_kg_m3(tgt.temp_lower_c)
			tgt.upper_gas_kg = tgt.floor_area_m2() * 0.08 * tgt_density

		var stairwell_target_cap_enabled: bool = phase3_stairwell_heat_bridge_enabled \
				and (op.is_vertical or op.type == OpeningModel.Type.HOLE) \
				and (src.kind == "escalera" or tgt.kind == "escalera") \
				and phase3_stairwell_heat_bridge_target_max_temp_c > ambient_c
		if stairwell_target_cap_enabled:
			var radiation_target_cap_c: float = maxf(
				ambient_c,
				phase3_stairwell_heat_bridge_target_max_temp_c
			)
			var radiation_energy_cap_kj: float = tgt.upper_gas_kg \
					* maxf(0.0, radiation_target_cap_c - ambient_c)
			energy_kj = minf(
				energy_kj,
				maxf(0.0, radiation_energy_cap_kj - tgt.upper_energy_kj)
			)
		if energy_kj <= 0.0:
			continue

		src.upper_energy_kj = maxf(0.0, src.upper_energy_kj - energy_kj)
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
		var delta_t: float
		# SF-AUD-031: hot-layer fraction for each room [0=no hot layer, 1=full hot layer]
		var frac_hot_a: float = 0.0
		var frac_hot_b: float = 0.0
		if wall_layer_aware_conduction:
			frac_hot_a = clampf((room_a.height_m - room_a.h_layer_m) / maxf(0.01, room_a.height_m), 0.0, 1.0)
			frac_hot_b = clampf((room_b.height_m - room_b.h_layer_m) / maxf(0.01, room_b.height_m), 0.0, 1.0)
			var t_drive_a: float = lerpf(room_a.temp_lower_c, room_a.temp_upper_c, frac_hot_a)
			var t_drive_b: float = lerpf(room_b.temp_lower_c, room_b.temp_upper_c, frac_hot_b)
			delta_t = t_drive_a - t_drive_b
		else:
			delta_t = t_wall_a - t_wall_b
		if absf(delta_t) < 1.0:
			continue

		# Q = U × A × ΔT  [kW]
		var q_kw: float = wall_conduction_u_kw_m2_k * wall_area * delta_t
		var energy_kj: float = q_kw * dt

		# Límite de estabilidad: no pasar más de max_fraction de la capacidad de la
		# pared más grande en un solo paso. SF-AUD-014: usa capacidad per-material si está definida.
		var cap_a: float
		var cap_b: float
		if room_a.wall_k_kw_m_k > 0.0 and room_a.wall_thickness_m > 0.0:
			var _rho_a: float = room_a.wall_rho_kg_m3 if room_a.wall_rho_kg_m3 > 0.0 else 800.0
			var _cp_a: float = room_a.wall_cp_kj_kg_k if room_a.wall_cp_kj_kg_k > 0.0 else 1.0
			cap_a = _rho_a * _cp_a * room_a.wall_thickness_m * room_a.floor_area_m2() * 2.0
		else:
			cap_a = wall_heat_capacity_kj_m2_k * room_a.floor_area_m2() * 2.0
		if room_b.wall_k_kw_m_k > 0.0 and room_b.wall_thickness_m > 0.0:
			var _rho_b: float = room_b.wall_rho_kg_m3 if room_b.wall_rho_kg_m3 > 0.0 else 800.0
			var _cp_b: float = room_b.wall_cp_kj_kg_k if room_b.wall_cp_kj_kg_k > 0.0 else 1.0
			cap_b = _rho_b * _cp_b * room_b.wall_thickness_m * room_b.floor_area_m2() * 2.0
		else:
			cap_b = wall_heat_capacity_kj_m2_k * room_b.floor_area_m2() * 2.0
		var max_kj: float = maxf(cap_a, cap_b) * wall_conduction_max_fraction_per_step
		energy_kj = clampf(energy_kj, -max_kj, max_kj)

		if energy_kj > 0.0:
			# A→B: pared de A cede calor a B
			_ensure_minimal_upper_gas(room_b, ambient_c)
			if phase3_stairwell_heat_bridge_enabled \
					and room_b.kind == "escalera" \
					and phase3_stairwell_heat_bridge_target_max_temp_c > ambient_c:
				var stairwell_wall_cap_c: float = maxf(
					ambient_c,
					phase3_stairwell_heat_bridge_target_max_temp_c
				)
				var upper_room_b_cap_kj: float = room_b.upper_gas_kg \
						* maxf(0.0, stairwell_wall_cap_c - ambient_c)
				var available_wall_target_kj: float = maxf(
					0.0,
					upper_room_b_cap_kj - room_b.upper_energy_kj
				)
				if wall_layer_aware_conduction and frac_hot_b < 1.0:
					var lower_mass_b_cap: float = room_b.floor_area_m2() \
							* maxf(0.1, room_b.h_layer_m) \
							* gas_density_kg_m3(room_b.temp_lower_c)
					available_wall_target_kj += lower_mass_b_cap \
							* maxf(0.0, stairwell_wall_cap_c - room_b.temp_lower_c)
				energy_kj = minf(energy_kj, available_wall_target_kj)
				if energy_kj <= 0.0:
					continue
			_wall_surface_temp_c[pair["room_a_id"]] = t_wall_a \
					- energy_kj / maxf(0.1, cap_a)
			if wall_layer_aware_conduction and frac_hot_b < 1.0:
				# SF-AUD-031: repartir entre capa superior e inferior del receptor B
				var e_upper_b: float = energy_kj * frac_hot_b
				var e_lower_b: float = energy_kj - e_upper_b
				room_b.upper_energy_kj += e_upper_b
				var lower_mass_b: float = room_b.floor_area_m2() \
						* maxf(0.1, room_b.h_layer_m) \
						* gas_density_kg_m3(room_b.temp_lower_c)
				room_b.temp_lower_c += e_lower_b / maxf(0.1, lower_mass_b)
			else:
				room_b.upper_energy_kj += energy_kj
			sync_room_upper_layer(room_b, dt)
			update_room_layer_150c(room_b, dt)
		elif energy_kj < 0.0:
			# B→A: pared de B cede calor a A
			var abs_kj: float = -energy_kj
			_ensure_minimal_upper_gas(room_a, ambient_c)
			if phase3_stairwell_heat_bridge_enabled \
					and room_a.kind == "escalera" \
					and phase3_stairwell_heat_bridge_target_max_temp_c > ambient_c:
				var stairwell_wall_cap_a_c: float = maxf(
					ambient_c,
					phase3_stairwell_heat_bridge_target_max_temp_c
				)
				var upper_room_a_cap_kj: float = room_a.upper_gas_kg \
						* maxf(0.0, stairwell_wall_cap_a_c - ambient_c)
				var available_wall_target_a_kj: float = maxf(
					0.0,
					upper_room_a_cap_kj - room_a.upper_energy_kj
				)
				if wall_layer_aware_conduction and frac_hot_a < 1.0:
					var lower_mass_a_cap: float = room_a.floor_area_m2() \
							* maxf(0.1, room_a.h_layer_m) \
							* gas_density_kg_m3(room_a.temp_lower_c)
					available_wall_target_a_kj += lower_mass_a_cap \
							* maxf(0.0, stairwell_wall_cap_a_c - room_a.temp_lower_c)
				abs_kj = minf(abs_kj, available_wall_target_a_kj)
				if abs_kj <= 0.0:
					continue
			_wall_surface_temp_c[pair["room_b_id"]] = t_wall_b \
					- abs_kj / maxf(0.1, cap_b)
			if wall_layer_aware_conduction and frac_hot_a < 1.0:
				# SF-AUD-031: repartir entre capa superior e inferior del receptor A
				var e_upper_a: float = abs_kj * frac_hot_a
				var e_lower_a: float = abs_kj - e_upper_a
				room_a.upper_energy_kj += e_upper_a
				var lower_mass_a: float = room_a.floor_area_m2() \
						* maxf(0.1, room_a.h_layer_m) \
						* gas_density_kg_m3(room_a.temp_lower_c)
				room_a.temp_lower_c += e_lower_a / maxf(0.1, lower_mass_a)
			else:
				room_a.upper_energy_kj += abs_kj
			sync_room_upper_layer(room_a, dt)
			update_room_layer_150c(room_a, dt)


func _ensure_minimal_upper_gas(room: RoomModel, ambient_c: float) -> void:
	# Crea una capa superior mínima para poder depositar energía si aún no existe.
	if room.upper_gas_kg <= 0.0001:
		var density: float = gas_density_kg_m3(room.temp_lower_c)
		var required_mass_kg: float = room.floor_area_m2() * 0.08 * density
		if two_zone_solver_enabled and _zone_fire_solver != null:
			_zone_fire_solver.transfer_lower_to_upper(room, required_mass_kg, ambient_c)
		else:
			room.upper_gas_kg = required_mass_kg


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
# SF-AUD-030: PDE 1D PARED — CRANK-NICOLSON 5 NODOS
# ------------------------------------------------------------
# Modela la difusión térmica a través del espesor de la pared
# con 5 nodos uniformes: T[0]=cara interior (Dirichlet, fijado
# por la temperatura de superficie existente), T[1..3] nodos
# interiores resueltos por C-N, T[4]=cara exterior (Robin BC
# con convección exterior h_ext).
#
#   ρ·c · ∂T/∂t = k · ∂²T/∂x²
#   dx = L/4;  r = k·dt / (2·ρ·c·dx²)
#
# Exporta room.wall_T_mid_c (T[2]) y room.wall_T_outer_c (T[4]).
# Solo actúa cuando los 4 parámetros de material están definidos.
# ============================================================

func _solve_tdma_4(
		al: Array, bm: Array, cu: Array, d: Array
) -> Array:
	# Thomas (TDMA) para sistema 4×4 tridiagonal.
	# al = subdiagonal (al[0] no se usa), bm = diagonal,
	# cu = superdiagonal (cu[3] no se usa), d = RHS.
	var n: int = 4
	var c_star: Array = [0.0, 0.0, 0.0, 0.0]
	var d_star: Array = [0.0, 0.0, 0.0, 0.0]
	c_star[0] = cu[0] / bm[0]
	d_star[0] = d[0] / bm[0]
	for i: int in range(1, n):
		var denom: float = bm[i] - al[i] * c_star[i - 1]
		if absf(denom) < 1e-30:
			denom = 1e-30
		if i < n - 1:
			c_star[i] = cu[i] / denom
		d_star[i] = (d[i] - al[i] * d_star[i - 1]) / denom
	var x: Array = [0.0, 0.0, 0.0, 0.0]
	x[n - 1] = d_star[n - 1]
	for i: int in range(n - 2, -1, -1):
		x[i] = d_star[i] - c_star[i] * x[i + 1]
	return x


func _solve_tdma_5(
		al: Array, bm: Array, cu: Array, d: Array
) -> Array:
	# Thomas (TDMA) para sistema 5×5 tridiagonal.
	# al = subdiagonal (al[0] no se usa), bm = diagonal,
	# cu = superdiagonal (cu[4] no se usa), d = RHS.
	var n: int = 5
	var c_star: Array = [0.0, 0.0, 0.0, 0.0, 0.0]
	var d_star: Array = [0.0, 0.0, 0.0, 0.0, 0.0]
	c_star[0] = cu[0] / bm[0]
	d_star[0] = d[0] / bm[0]
	for i: int in range(1, n):
		var denom: float = bm[i] - al[i] * c_star[i - 1]
		if absf(denom) < 1e-30:
			denom = 1e-30
		if i < n - 1:
			c_star[i] = cu[i] / denom
		d_star[i] = (d[i] - al[i] * d_star[i - 1]) / denom
	var x: Array = [0.0, 0.0, 0.0, 0.0, 0.0]
	x[n - 1] = d_star[n - 1]
	for i: int in range(n - 2, -1, -1):
		x[i] = d_star[i] - c_star[i] * x[i + 1]
	return x


func _step_wall_pde(building: BuildingModel, dt: float, ambient_c: float) -> void:
	if not wall_pde_enabled:
		return
	# h_ext = coef. convectivo exterior [kW/(m²·K)]
	# ~0.025 kW/(m²·K) para aire quiescente exterior (ISO 6946 Rse≈0.13 m²K/W)
	var h_ext: float = 0.025
	# h_ci = coef. convectivo interior gas→cara pared [kW/(m²·K)]
	# SF-AUD-030 Robin BC en T[0]: reemplaza Dirichlet previo para modelar
	# correctamente la inercia térmica de la cara interior.
	var h_ci: float = h_conv_int_kw_m2_k

	for room_id: int in building.get_rooms().keys():
		var room: RoomModel = building.get_room(room_id)
		if room == null:
			continue

		# Solo si los 4 parámetros de material están definidos
		if room.wall_k_kw_m_k <= 0.0 or room.wall_thickness_m <= 0.0:
			# SF-AUD-031b: el modelo lumped ya escribió wall_T_mid_c en step_rooms.
			# No sobreescribir — sólo garantizar wall_T_outer_c en ambient.
			room.wall_T_outer_c = ambient_c
			continue

		var k: float = room.wall_k_kw_m_k                                    # kW/(m·K)
		var rho: float = room.wall_rho_kg_m3 if room.wall_rho_kg_m3 > 0.0 else 800.0   # kg/m³
		var cp_v: float = room.wall_cp_kj_kg_k if room.wall_cp_kj_kg_k > 0.0 else 1.0 # kJ/(kg·K)
		var L: float = room.wall_thickness_m                                  # m
		var dx: float = L / 4.0                                               # m

		# Lazy-init nodos a temperatura ambiente
		if not _wall_pde_nodes_c.has(room_id):
			_wall_pde_nodes_c[room_id] = [ambient_c, ambient_c, ambient_c, ambient_c, ambient_c]
		var T: Array = _wall_pde_nodes_c[room_id]

		# Temperatura del gas en la sala (BC Robin interior)
		var T_gas: float = room.temp_upper_c

		# R2-4: flujo radiativo del fuego depositado en la cara interior de la pared.
		# q_fire = χ_rad·HRR·f_wall / A_wall  [kW/m²]
		# Solo cuando hrr_rad_wall_fraction > 0 y hay fuego activo.
		var wall_area_m2_pde: float = room.floor_area_m2() * 2.0
		var q_fire_rad_kw_m2: float = 0.0
		if hrr_rad_wall_fraction > 0.0 and room.hrr_kw > 0.0:
			var eff_chi_rad: float = hrr_chi_rad_normal
			if room.chi_rad_normal >= 0.0:
				eff_chi_rad = room.chi_rad_normal
			var chi_rad_pde: float = lerpf(
				eff_chi_rad * (hrr_chi_rad_low_o2 / maxf(0.01, hrr_chi_rad_normal)),
				eff_chi_rad,
				clampf(inverse_lerp(0.06, 0.12, room.o2), 0.0, 1.0)
			)
			q_fire_rad_kw_m2 = room.hrr_kw * chi_rad_pde * hrr_rad_wall_fraction \
					/ maxf(1.0, wall_area_m2_pde)

		# Parámetro de Crank-Nicolson: r = k·dt / (2·ρ·cp·dx²)
		var dxdx: float = dx * dx
		var r: float = k * dt / (2.0 * rho * cp_v * dxdx)

		# k/dx — difusividad nodal
		var k_dx: float = k / dx

		# Coeficiente de masa de semi-nodos: B = ρ·cp·(dx/2)/dt [kW/(m²·K)]
		var B_half: float = rho * cp_v * (dx * 0.5) / dt

		# Temperaturas antiguas de los 5 nodos
		var t0: float = T[0]
		var t1: float = T[1]
		var t2: float = T[2]
		var t3: float = T[3]
		var t4: float = T[4]

		# -------------------------------------------------------
		# Sistema 5×5 tridiagonal Crank-Nicolson para T[0..4]^{n+1}
		#
		# Nodo 0 (semi-nodo, Robin interior + fuente radiativa R2-4):
		#   (B_half + 0.5*(k_dx+h_ci))·T0 - 0.5*k_dx·T1 =
		#       (B_half - 0.5*(k_dx+h_ci))·t0 + 0.5*k_dx·t1 + h_ci·T_gas + q_fire_rad
		#
		# Nodos 1..3 (nodos interiores completos, C-N estándar):
		#   -r·T{i-1} + (1+2r)·Ti - r·T{i+1} =
		#        r·t{i-1} + (1-2r)·ti + r·t{i+1}
		#
		# Nodo 4 (semi-nodo, Robin exterior):
		#   -k_dx·T3 + (B_half+k_dx+h_ext)·T4 = B_half·t4 + h_ext·T_amb
		# -------------------------------------------------------

		var al5: Array = [0.0,   -r,              -r,              -r,              -k_dx         ]
		var bm5: Array = [
			B_half + 0.5 * (k_dx + h_ci),
			1.0 + 2.0 * r,
			1.0 + 2.0 * r,
			1.0 + 2.0 * r,
			B_half + k_dx + h_ext
		]
		var cu5: Array = [-0.5 * k_dx, -r,   -r,   -r,   0.0]
		var dv5: Array = [
			(B_half - 0.5 * (k_dx + h_ci)) * t0 + 0.5 * k_dx * t1 + h_ci * T_gas + q_fire_rad_kw_m2,
			r * t0 + (1.0 - 2.0 * r) * t1 + r * t2,
			r * t1 + (1.0 - 2.0 * r) * t2 + r * t3,
			r * t2 + (1.0 - 2.0 * r) * t3 + r * t4,
			B_half * t4 + h_ext * ambient_c
		]

		var sol: Array = _solve_tdma_5(al5, bm5, cu5, dv5)

		T[0] = sol[0]
		T[1] = sol[1]
		T[2] = sol[2]
		T[3] = sol[3]
		T[4] = sol[4]

		# Acotar: temperatura de pared entre casi-ambiente y 2000°C (evitar runaway numérico)
		for i: int in range(0, 5):
			T[i] = clampf(T[i], ambient_c - 2.0, 2000.0)

		_wall_pde_nodes_c[room_id] = T

		# La cara interior T[0] pasa a ser la temperatura de superficie de pared
		# para el intercambio gas↔pared del siguiente paso (sustituye al modelo lumped).
		_wall_surface_temp_c[room_id] = T[0]

		# Exportar a RoomModel para métricas de validación
		room.wall_T_mid_c   = T[2]
		room.wall_T_outer_c = T[4]


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
			minf(room.temp_upper_c, room.temp_lower_c + 180.0))
	return target_volume_m3 * gas_density_kg_m3(entrained_temp_c)


func _step_two_zone_plume_entrainment(room: RoomModel, dt: float, ambient_c: float) -> void:
	if room == null or dt <= 0.0 or room.hrr_kw <= 0.0 or _zone_fire_solver == null:
		return

	var qc_kw: float = maxf(0.0, room.hrr_kw * plume_mccaffrey_qc_fraction)
	if qc_kw <= 0.0:
		return

	var flame_length_m: float = maxf(
		0.0,
		0.235 * pow(room.hrr_kw, 0.4) - 1.02 * plume_fire_diameter_m
	)
	var interface_m: float = clampf(room.thermal_layer_m, 0.0, room.height_m)
	var z_eff_m: float
	if plume_confined_flame_enabled and flame_length_m >= room.height_m:
		z_eff_m = maxf(0.1, room.height_m * plume_confined_z_eff_fraction)
	else:
		z_eff_m = maxf(0.1, interface_m - flame_length_m)

	var m_dot_plume_kg_s: float = 0.071 \
			* pow(qc_kw, 1.0 / 3.0) \
			* pow(z_eff_m, 5.0 / 3.0)
	var max_upper_mass_kg: float = room.volume_m3() * gas_density_kg_m3(room.temp_upper_c)
	var remaining_capacity_kg: float = maxf(0.0, max_upper_mass_kg - room.upper_gas_kg)
	var requested_mass_kg: float = minf(m_dot_plume_kg_s * dt, remaining_capacity_kg)
	_zone_fire_solver.transfer_lower_to_upper(room, requested_mass_kg, ambient_c)


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

	if two_zone_solver_enabled and _zone_fire_solver != null:
		_zone_fire_solver.transfer_lower_to_upper(room, mass_gain_kg, ambient_c)
	else:
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
	var stairwell_target_cap_enabled: bool = phase3_stairwell_heat_bridge_enabled \
			and (op.is_vertical or op.type == OpeningModel.Type.HOLE) \
			and (source.kind == "escalera" or target.kind == "escalera") \
			and phase3_stairwell_heat_bridge_target_max_temp_c > ambient_c
	var stairwell_target_cap_c: float = maxf(
		ambient_c,
		phase3_stairwell_heat_bridge_target_max_temp_c
	)
	if stairwell_target_cap_enabled:
		transfer_temp_c = minf(transfer_temp_c, stairwell_target_cap_c)
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
	var stairwell_target_cap_enabled: bool = phase3_stairwell_heat_bridge_enabled \
			and (op.is_vertical or op.type == OpeningModel.Type.HOLE) \
			and (source.kind == "escalera" or target.kind == "escalera") \
			and phase3_stairwell_heat_bridge_target_max_temp_c > ambient_c
	var stairwell_target_cap_c: float = maxf(
		ambient_c,
		phase3_stairwell_heat_bridge_target_max_temp_c
	)
	if stairwell_target_cap_enabled:
		transfer_temp_c = minf(transfer_temp_c, stairwell_target_cap_c)
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
		if stairwell_target_cap_enabled:
			var target_upper_mass_after_kg: float = maxf(0.005, target.upper_gas_kg + gas_moved_kg)
			var target_upper_energy_cap_kj: float = target_upper_mass_after_kg \
					* maxf(0.0, stairwell_target_cap_c - ambient_c)
			energy_moved_kj = minf(
				energy_moved_kj,
				maxf(0.0, target_upper_energy_cap_kj - target.upper_energy_kj)
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
		if stairwell_target_cap_enabled:
			bulk_moved_kj = minf(
				bulk_moved_kj,
				target_air_mass_kg * maxf(0.0, stairwell_target_cap_c - target.temp_lower_c)
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


# Phase 5 M3: contraflujo térmico bidireccional por puertas interiores.
# Modela flujo Bernoulli caliente-frío a través de la puerta incluso cuando la capa
# caliente está cerca del techo (hot_band_m ≈ 0, flow_state.active = false).
# Referencia: SFPE §3.2 / CFAST TN 1889v1 §2.2 — igual fórmula que el path Bernoulli
# activo, pero sin requerir hot_band_m > 0.
func _apply_doorway_thermal_counterflow(
	room_a: RoomModel,
	room_b: RoomModel,
	op: OpeningModel,
	flow_state: Dictionary,
	dt: float,
	ambient_c: float
) -> void:
	if not doorway_thermal_counterflow_enabled:
		return
	if room_a == null or room_b == null or op == null or dt <= 0.0:
		return
	if op.open_fraction <= 0.0:
		return

	var hot_room: RoomModel = room_a
	var cold_room: RoomModel = room_b
	if room_b.temp_upper_c > room_a.temp_upper_c:
		hot_room = room_b
		cold_room = room_a

	var delta_c: float = maxf(0.0, hot_room.temp_upper_c - cold_room.temp_upper_c)
	if delta_c < doorway_thermal_counterflow_min_delta_c:
		return

	# Flujo Bernoulli: caudal volumétrico impulsado por boyantez (m³/s).
	# Usamos T_hot_upper vs T_cold_lower como diferencia motriz (mayor gradiente hidrostático).
	var T_hot_k: float = hot_room.temp_upper_c + 273.15
	var T_cold_k: float = cold_room.temp_lower_c + 273.15
	var T_ref_k: float = (T_hot_k + T_cold_k) * 0.5
	var dT_drive_k: float = maxf(0.0, T_hot_k - T_cold_k)
	if dT_drive_k < 0.5:
		return

	var g: float = 9.81
	var Cd: float = 0.65
	var w: float = op.width_m * op.open_fraction
	# h_upper = complemento del plano activo Bernoulli: resta hot_band_m para no duplicar
	# el flujo que ya gestiona el path activo cuando la capa caliente cruza el dintel.
	var hot_band_m: float = float(flow_state.get("hot_band_m", 0.0))
	var h_upper: float = maxf(0.0, op.height_m * 0.5 - hot_band_m)
	if h_upper < 0.05:
		return

	var q_upper_m3s: float = Cd * w * (2.0 / 3.0) * pow(h_upper, 1.5) \
			* sqrt(2.0 * g * dT_drive_k / T_ref_k)
	if q_upper_m3s <= 0.0:
		return

	# Modelo de conductancia convectiva pura: no se transfiere masa entre salas.
	# Q [kW] = ṁ_eff [kg/s] × (T_hot_upper − T_cold_upper) [kJ/kg] × gain
	# La tasa másica efectiva es el caudal Bernoulli × densidad del gas caliente.
	# La diferencia de temperatura usa upper−upper para reflejar el gradiente real de la zona superior.
	var rho_hot: float = 353.0 / maxf(50.0, T_hot_k)
	var dT_upper_k: float = maxf(0.0, hot_room.temp_upper_c - cold_room.temp_upper_c)
	var Q_kw: float = q_upper_m3s * rho_hot * dT_upper_k * doorway_thermal_counterflow_gain
	var energy_moved_kj: float = Q_kw * dt

	# Cap: no drenar más del 5% de la energía superior en un paso (estabilidad numérica)
	energy_moved_kj = minf(energy_moved_kj, maxf(0.0, hot_room.upper_energy_kj * 0.05))
	if energy_moved_kj <= 0.0:
		return

	# Transferencia de energía pura (sin movimiento de masa): evita acumulación de gas
	# en la sala receptora y conserva la estructura de capas de cada sala.
	hot_room.upper_energy_kj = maxf(0.0, hot_room.upper_energy_kj - energy_moved_kj)

	# Si la sala fría no tiene capa superior establecida, crear masa mínima para aceptar energía
	if cold_room.upper_gas_kg < 0.01:
		cold_room.upper_gas_kg += 0.005
	cold_room.upper_energy_kj = maxf(0.0, cold_room.upper_energy_kj + energy_moved_kj)

	sync_room_upper_layer(hot_room, dt)
	sync_room_upper_layer(cold_room, dt)

	# ── Phase 5 M3b: retorno de aire fresco (zona inferior) ──────────────────────────────────
	# Contraparte de conservación de masa del flujo superior: el gas caliente que sale por la
	# mitad superior de la puerta debe ser compensado por aire fresco que entra por la mitad
	# inferior (flujo de retorno Bernoulli / CFAST TN 1889v1 §2.3).
	# Solo aplica cuando la sala caliente tiene fuego activo (evita cascada O₂ entre salas sin fuego).
	# Efecto: repone O₂ en zona superior de la sala de fuego → mantiene HRR sostenido.
	if doorway_thermal_counterflow_o2_return_fraction <= 0.0:
		return
	# Phase 6: cuando el intercambio canónico está activo, el flujo inferior está manejado
	# correctamente por _apply_canonical_doorway_exchange — omitir M3b para evitar doble conteo.
	if canonical_doorway_exchange_enabled:
		return
	if hot_room.hrr_kw < 1.0:
		return
	var m_return_kg_s: float = q_upper_m3s * rho_hot * doorway_thermal_counterflow_o2_return_fraction
	var m_return_kg: float = m_return_kg_s * dt
	if m_return_kg < 0.0001:
		return

	# Fracción O₂ disponible en zona inferior de la sala fría (fuente del retorno).
	var cold_o2_src: float = maxf(cold_room.o2_lower, cold_room.o2)
	var rho_ambient: float = 353.0 / maxf(270.0, ambient_c + 273.15)
	var hot_lower_mass: float = maxf(0.1, hot_room.lower_volume_m3() * rho_ambient)
	var cold_lower_mass: float = maxf(0.1, cold_room.lower_volume_m3() * rho_ambient)

	# Cap: no extraer más del 5 % del O₂ de la zona inferior fría por paso.
	var cold_o2_avail_kg: float = cold_lower_mass * cold_o2_src
	var o2_delta_kg: float = minf(m_return_kg * cold_o2_src, cold_o2_avail_kg * 0.05)
	if o2_delta_kg <= 0.0:
		return

	# Sala caliente: O₂ entra en zona inferior (flujo de retorno) Y zona superior (pluma inmediata).
	# En el modelo 2-zonas el aire fresco que entra por la puerta baja es entrenado por la pluma
	# casi instantáneamente → se distribuye 50 % inferior / 50 % superior como aproximación.
	var hot_upper_mass: float = maxf(0.1, hot_room.upper_volume_m3() * rho_ambient)
	hot_room.o2_lower = clampf(hot_room.o2_lower + o2_delta_kg * 0.5 / hot_lower_mass, 0.0, 0.209)
	hot_room.o2_upper = clampf(hot_room.o2_upper + o2_delta_kg * 0.5 / hot_upper_mass, 0.0, 0.209)
	# SF-O1A: counterflow thermal doorway — hot recibe, cold cede (o2_delta_kg en kg).
	hot_room.o2_net_transport_kg_step += o2_delta_kg
	hot_room.o2_net_transport_kg_total += o2_delta_kg
	cold_room.o2_net_transport_kg_step -= o2_delta_kg
	cold_room.o2_net_transport_kg_total -= o2_delta_kg

	# Sala fría: pierde O₂ de la zona inferior (fuente del retorno).
	cold_room.o2_lower = clampf(cold_room.o2_lower - o2_delta_kg / cold_lower_mass, 0.0, 0.209)

	# Sincronizar o2 bulk como promedio volumétrico de las dos zonas.
	# SF-O1D: rastrear la corrección de sincronización zonal (diferencia entre blend y room.o2 previo).
	var _hot_total_vol: float = maxf(0.01, hot_room.volume_m3())
	var _hot_lower_vol: float = hot_room.lower_volume_m3()
	var _hot_upper_vol: float = _hot_total_vol - _hot_lower_vol
	var _hot_blend: float = clampf(
		(hot_room.o2_upper * _hot_upper_vol + hot_room.o2_lower * _hot_lower_vol) / _hot_total_vol,
		0.0, 0.209)
	var _hot_sync_kg: float = (_hot_blend - hot_room.o2) * _hot_total_vol * 1.2
	hot_room.o2_zone_sync_kg_step += _hot_sync_kg
	hot_room.o2_zone_sync_kg_total += _hot_sync_kg
	hot_room.o2 = _hot_blend

	var _cold_total_vol: float = maxf(0.01, cold_room.volume_m3())
	var _cold_lower_vol: float = cold_room.lower_volume_m3()
	var _cold_upper_vol: float = _cold_total_vol - _cold_lower_vol
	var _cold_blend: float = clampf(
		(cold_room.o2_upper * _cold_upper_vol + cold_room.o2_lower * _cold_lower_vol) / _cold_total_vol,
		0.0, 0.209)
	var _cold_sync_kg: float = (_cold_blend - cold_room.o2) * _cold_total_vol * 1.2
	cold_room.o2_zone_sync_kg_step += _cold_sync_kg
	cold_room.o2_zone_sync_kg_total += _cold_sync_kg
	cold_room.o2 = _cold_blend


# ============================================================
# PHASE 6: INTERCAMBIO CANÓNICO DOS ZONAS POR PUERTAS
# ------------------------------------------------------------
# Modelo conservativo bidireccional masa + entalpía + O₂.
# Llamado desde el bucle de aperturas DESPUÉS de que el bucle principal
# haya movido masa + energía de hot.upper → cold.upper.
#
# Parte A: O₂ zona superior — la masa que salió lleva o2_upper del origen.
#          Se actualiza cold.o2_upper con mezcla ponderada.
#
# Parte B: Flujo inferior — aire fresco de cold.lower entra a hot.lower.
#          Efecto (1): enfría zona inferior → reduce pico t=180.
#          Efecto (2): repone O₂ en hot.lower → difunde a upper por plume
#                      → sostiene HRR → meseta t=300-600.
# ============================================================

func _apply_canonical_doorway_exchange(
	hot_room: RoomModel,
	cold_room: RoomModel,
	op: OpeningModel,
	flow_state: Dictionary,
	dt: float,
	ambient_c: float,
	upper_gas_moved_kg: float
) -> void:
	if not canonical_doorway_exchange_enabled:
		return
	if hot_room == null or cold_room == null:
		return

	# ── PARTE A: O₂ zona superior ────────────────────────────────────────────────
	# El bucle principal movió upper_gas_moved_kg de hot.upper → cold.upper.
	# El gas transportado lleva la concentración o2_upper de la sala caliente.
	# cold.o2_upper = mezcla ponderada (masa_antes × o2_cold + masa_movida × o2_hot) / masa_después.
	if upper_gas_moved_kg > 0.0 and cold_room.upper_gas_kg > 0.0001:
		var cold_upper_mass_before: float = maxf(0.0001, cold_room.upper_gas_kg - upper_gas_moved_kg)
		cold_room.o2_upper = clampf(
			(cold_upper_mass_before * cold_room.o2_upper + upper_gas_moved_kg * hot_room.o2_upper)
			/ cold_room.upper_gas_kg,
			0.0, 0.209
		)
		# Señal M2: indica a OxygenExchangeSystem que o2_upper fue modificado por mixing canónico
		# este paso. O₂ExchangeSystem re-sincronizará el tracker desde el valor actual en lugar
		# de sobreescribirlo con el tracker antiguo (que daría un o2_upper erróneo).
		cold_room.canonical_o2_upper_updated = true

	# ── PARTE B: Flujo inferior (cold.lower → hot.lower) — Phase 7: conservación de entalpía ──
	# Phase 6 cambiaba temp_lower_c directamente, pero project_room_state() la sobreescribe
	# cada paso desde lower_energy_kj / lower_gas_kg → era un no-op.
	# Phase 7 actúa sobre lower_energy_kj, el estado conservado real del solver dos-zonas.
	var m_lower_kg_s: float = float(flow_state.get("bernoulli_lower_kg_s", 0.0)) \
			* canonical_doorway_lower_flow_frac \
			* canonical_doorway_lower_inflow_multiplier
	var m_lower_kg: float = m_lower_kg_s * dt
	if m_lower_kg < 0.0001:
		return

	var rho_hot_lower: float = gas_density_kg_m3(hot_room.temp_lower_c)
	var rho_cold_lower: float = gas_density_kg_m3(cold_room.temp_lower_c)
	var hot_lower_mass: float = maxf(0.1, hot_room.lower_volume_m3() * rho_hot_lower)
	var cold_lower_mass: float = maxf(0.1, cold_room.lower_volume_m3() * rho_cold_lower)

	# Cap: no extraer más del 5 % de la zona inferior fría por paso.
	m_lower_kg = minf(m_lower_kg, cold_lower_mass * 0.05)
	if m_lower_kg <= 0.0001:
		return

	# Phase 3D: fracción del inflow inferior que va directamente a hot.upper (pluma inmediata).
	# hot_layer_frac = fracción del vano interior en zona caliente del cuarto de fuego.
	# direct_frac = hot_layer_frac × canonical_doorway_plume_direct_upper_frac.
	# Conservativo: m_lower_kg = m_direct + m_to_lower (sin doble contabilidad).
	var _p3d_frac: float = 0.0
	if canonical_doorway_plume_direct_upper_frac > 0.0:
		var _p3d_door_h: float = maxf(0.01, op.height_m)
		var _p3d_hot_layer_f: float = clampf(
			1.0 - hot_room.thermal_layer_m / _p3d_door_h,
			0.0, 1.0
		)
		_p3d_frac = _p3d_hot_layer_f * canonical_doorway_plume_direct_upper_frac
	var m_direct_kg: float = m_lower_kg * _p3d_frac
	var m_to_lower_kg: float = m_lower_kg - m_direct_kg

	# cp = 1.0 kJ/(kg·K) — igual que ZoneFireSolver.AIR_CP_KJ_KG_K.
	# Δenergía_hot = m × (T_cold − T_hot) [negativo → enfría la capa inferior caliente].
	# Actuar sobre lower_energy_kj garantiza que project_room_state() derive
	# el temp_lower_c correcto en el paso siguiente.
	var _cp: float = 1.0
	if m_to_lower_kg > 0.0001:
		var delta_energy_hot_kj: float = \
				m_to_lower_kg * (cold_room.temp_lower_c - hot_room.temp_lower_c) * _cp
		hot_room.lower_energy_kj = maxf(0.0, hot_room.lower_energy_kj + delta_energy_hot_kj)
	# cold.lower pierde la entalpía (sobre ambiente) del aire exportado (total, incluso la fracción direct).
	var cold_energy_out_kj: float = \
			m_lower_kg * maxf(0.0, cold_room.temp_lower_c - ambient_c) * _cp
	cold_room.lower_energy_kj = maxf(0.0, cold_room.lower_energy_kj - cold_energy_out_kj)

	# Phase 3D: fracción directa entra en hot.upper — mezcla conservativa.
	# El gas frío entra con la entalpía del aire fresco (cold.lower temp).
	if m_direct_kg > 0.0001:
		var hot_upper_mass_before: float = maxf(0.001, hot_room.upper_gas_kg)
		hot_room.upper_gas_kg += m_direct_kg
		var direct_energy_kj: float = m_direct_kg * maxf(0.0, cold_room.temp_lower_c - ambient_c) * _cp
		hot_room.upper_energy_kj = maxf(0.0, hot_room.upper_energy_kj + direct_energy_kj)
		# O₂ zona superior: mezcla conservativa con o2_lower del cuarto frío.
		hot_room.o2_upper = clampf(
			(hot_upper_mass_before * hot_room.o2_upper + m_direct_kg * cold_room.o2_lower)
			/ hot_room.upper_gas_kg,
			0.0, 0.209
		)

	# O₂ zona inferior: mezcla conservativa con la fracción que va a lower.
	if m_to_lower_kg > 0.0001:
		hot_room.o2_lower = clampf(
			(hot_lower_mass * hot_room.o2_lower + m_to_lower_kg * cold_room.o2_lower)
			/ (hot_lower_mass + m_to_lower_kg),
			0.0, 0.209
		)
	# cold_room.o2_lower: fracción conservada al perder masa (mezcla perfecta).

	# SF-O1A: CDE moves O₂ mass between rooms physically, but room.o2 is set via zone blend
	# (lines below). Adding _cde_net_hot to o2_net_transport would double-count because the
	# zone sync already captures the net effect on room.o2. Leave transport untouched here.

	# Sync O₂ bulk para sala caliente: promedio volumétrico superior + inferior.
	# SF-O1D: rastrear la corrección de sincronización zonal.
	var hot_total_vol: float = maxf(0.01, hot_room.volume_m3())
	var hot_lower_vol: float = hot_room.lower_volume_m3()
	var hot_upper_vol: float = hot_total_vol - hot_lower_vol
	var _hot_cde_blend: float = clampf(
		(hot_room.o2_upper * hot_upper_vol + hot_room.o2_lower * hot_lower_vol) / hot_total_vol,
		0.0, 0.209
	)
	var _hot_cde_sync_kg: float = (_hot_cde_blend - hot_room.o2) * hot_total_vol * 1.2
	hot_room.o2_zone_sync_kg_step += _hot_cde_sync_kg
	hot_room.o2_zone_sync_kg_total += _hot_cde_sync_kg
	hot_room.o2 = _hot_cde_blend

	# Sync O₂ bulk para sala fría: Part A modificó cold_room.o2_upper (upper mixing),
	# pero cold_room.o2 no se actualizó. Sincronizar para que el balance O1 sea correcto.
	# Equivalente al sync que _apply_doorway_thermal_counterflow ya hace para ambas salas.
	var cold_total_vol: float = maxf(0.01, cold_room.volume_m3())
	var cold_lower_vol: float = cold_room.lower_volume_m3()
	var cold_upper_vol: float = cold_total_vol - cold_lower_vol
	var _cold_cde_blend: float = clampf(
		(cold_room.o2_upper * cold_upper_vol + cold_room.o2_lower * cold_lower_vol) / cold_total_vol,
		0.0, 0.209
	)
	var _cold_cde_sync_kg: float = (_cold_cde_blend - cold_room.o2) * cold_total_vol * 1.2
	cold_room.o2_zone_sync_kg_step += _cold_cde_sync_kg
	cold_room.o2_zone_sync_kg_total += _cold_cde_sync_kg
	cold_room.o2 = _cold_cde_blend


func _apply_stairwell_heat_bridge(
	room_a: RoomModel,
	room_b: RoomModel,
	op: OpeningModel,
	dt: float,
	ambient_c: float
) -> void:
	if not two_zone_solver_enabled:
		return
	if not phase3_stairwell_heat_bridge_enabled:
		return
	if phase3_stairwell_heat_bridge_kg_s_m2 <= 0.0:
		return
	if room_a == null or room_b == null or op == null or dt <= 0.0:
		return
	if op.open_fraction <= 0.0:
		return
	if not op.is_vertical and op.type != OpeningModel.Type.HOLE:
		return

	var connects_stairwell: bool = room_a.kind == "escalera" or room_b.kind == "escalera"
	if not connects_stairwell:
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
	if source.temp_upper_c < phase3_stairwell_heat_bridge_hot_temp_start_c:
		return
	if source.upper_energy_kj <= 0.0001 or source.upper_gas_kg <= 0.0001:
		return

	var area_eff_m2: float = maxf(0.0, op.width_m * op.height_m * op.open_fraction)
	if area_eff_m2 <= 0.0:
		return

	var opening_multiplier: float = phase3_stairwell_heat_bridge_hole_multiplier
	if op.is_vertical:
		opening_multiplier = phase3_stairwell_heat_bridge_vertical_multiplier
	if opening_multiplier <= 0.0:
		return

	var heat_factor: float = inverse_lerp(
		phase3_stairwell_heat_bridge_hot_temp_start_c,
		maxf(
			phase3_stairwell_heat_bridge_hot_temp_start_c + 1.0,
			phase3_stairwell_heat_bridge_hot_temp_full_c
		),
		source.temp_upper_c
	)
	heat_factor = clampf(heat_factor, 0.0, 1.0)
	if heat_factor <= 0.0:
		return

	var drive: float = clampf(0.25 + 0.75 * clampf(delta_excess_c / 70.0, 0.0, 1.0), 0.0, 1.0)
	var exchange_kg: float = area_eff_m2 \
			* phase3_stairwell_heat_bridge_kg_s_m2 \
			* opening_multiplier \
			* heat_factor \
			* drive \
			* dt
	if exchange_kg <= 0.0:
		return

	if target.upper_gas_kg <= 0.05 and _zone_fire_solver != null:
		var lift_mass_kg: float = minf(
			maxf(0.0, target.lower_gas_kg * phase3_stairwell_heat_bridge_target_lift_fraction),
			maxf(0.0, area_eff_m2 * 0.035 - target.upper_gas_kg)
		)
		if lift_mass_kg > 0.0:
			_zone_fire_solver.transfer_lower_to_upper(target, lift_mass_kg, ambient_c)

	var source_cap_kj: float = source.upper_energy_kj \
			* clampf(phase3_stairwell_heat_bridge_max_fraction_per_step, 0.0, 1.0)
	var target_mass_kg: float = maxf(0.0, target.upper_gas_kg)
	if target_mass_kg <= 0.005:
		return
	var target_max_rise_c: float = 1.8 + 5.2 * drive * heat_factor
	var target_temp_cap_c: float = minf(
		source.temp_upper_c - 0.1,
		maxf(ambient_c, phase3_stairwell_heat_bridge_target_max_temp_c)
	)
	target_temp_cap_c = minf(target.temp_upper_c + target_max_rise_c, target_temp_cap_c)
	var target_energy_cap_kj: float = target_mass_kg \
			* maxf(0.0, target_temp_cap_c - ambient_c) \
			- target.upper_energy_kj
	var energy_moved_kj: float = minf(
		exchange_kg * source_excess_c * 0.85,
		source_cap_kj
	)
	energy_moved_kj = minf(energy_moved_kj, maxf(0.0, target_energy_cap_kj))
	if energy_moved_kj <= 0.0:
		return

	source.upper_energy_kj = maxf(0.0, source.upper_energy_kj - energy_moved_kj)
	target.upper_energy_kj = maxf(0.0, target.upper_energy_kj + energy_moved_kj)
	sync_room_upper_layer(source, dt)
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

	var src_id: int = source.id
	var tgt_id: int = target.id

	# SF-R6 Phase 4: acumular deltas en lugar de aplicar directamente.
	# Todas las lecturas usan el estado PRE-bucle (rooms sin modificar aún).
	# _flush_contaminant_deltas() aplica todo al final del bucle de aperturas.
	# Esto elimina los efectos de ordenación (enfoque Jacobi vs Gauss-Seidel).

	var co_upper_available_kg: float = clampf(source.co_upper_kg, 0.0, source.co_kg)
	var co_moved_kg: float = minf(source.co_kg, co_upper_available_kg * upper_fraction_moved * carry)
	# Specie pumping fix: limitar CO al headroom de concentración fuente→receptor.
	# Mismo patrón que el bloque CO₂ de F0 (líneas ~2784–2791 debajo).
	var co_tgt_stock_kg: float = maxf(0.0, target.co_kg + _delta_co_kg.get(tgt_id, 0.0))
	var co_headroom_kg: float = maxf(
		0.0,
		source.co_kg / (maxf(0.1, source.volume_m3()) * 1.2)
			* (maxf(0.1, target.volume_m3()) * 1.2) - co_tgt_stock_kg
	)
	co_moved_kg = minf(co_moved_kg, co_headroom_kg)
	if co_moved_kg > 0.0:
		_delta_co_kg[src_id]       = _delta_co_kg.get(src_id, 0.0)       - co_moved_kg
		_delta_co_upper_kg[src_id] = _delta_co_upper_kg.get(src_id, 0.0) - co_moved_kg
		_delta_co_kg[tgt_id]       = _delta_co_kg.get(tgt_id, 0.0)       + co_moved_kg
		# Phase 2E Experimento 2 — barrido de estrategia de deposición CO:
		# Cuando flag OFF: comportamiento original (co_tgt_upper = co_moved_kg).
		# Cuando flag ON:  se selecciona modo mediante phase2e_co_deposition_mode.
		#   "all_upper"       — 100% a upper (igual que baseline; cancela split).
		#   "geometric_split" — split h_upper_tgt / height_m  (Exp 1).
		#   "upper_floor_90"  — geometric_split con mínimo 90% a upper.
		#   "upper_floor_95"  — geometric_split con mínimo 95% a upper.
		var co_tgt_upper: float = co_moved_kg
		if phase2e_two_zone_transport_enabled:
			var h_upper_tgt: float = maxf(0.0, target.height_m - effective_hot_layer_height_m(target))
			var geo_split: float = clampf(h_upper_tgt / maxf(0.01, target.height_m), 0.0, 1.0)
			match phase2e_co_deposition_mode:
				"geometric_split":
					co_tgt_upper = co_moved_kg * geo_split
				"upper_floor_90":
					co_tgt_upper = co_moved_kg * maxf(0.90, geo_split)
				"upper_floor_95":
					co_tgt_upper = co_moved_kg * maxf(0.95, geo_split)
				_: # "all_upper" o desconocido — 100% upper (= baseline)
					pass
		_delta_co_upper_kg[tgt_id] = _delta_co_upper_kg.get(tgt_id, 0.0) + co_tgt_upper

	# SF-R6 Phase 2: CO₂ transport con upper zone tracking.
	# El gas caliente transportado va a la zona superior del destino (flotabilidad).
	var co2_moved_kg: float = minf(source.co2_kg, source.co2_kg * upper_fraction_moved * carry)
	# F0 Plan B: cota de equilibrio por concentración (mismo limitador que el path
	# de GasExchangeSystem). El receptor no puede quedar por encima de la
	# concentración de la fuente por este movimiento. Masas de aire a densidad
	# ambiente (1.2 kg/m³), consistente con compute_co2_ppm.
	var co2_src_air_kg: float = maxf(0.1, source.volume_m3()) * 1.2
	var co2_tgt_air_kg: float = maxf(0.1, target.volume_m3()) * 1.2
	var co2_tgt_stock_kg: float = maxf(0.0, target.co2_kg + _delta_co2_kg.get(tgt_id, 0.0))
	var co2_headroom_kg: float = maxf(
		0.0,
		source.co2_kg / co2_src_air_kg * co2_tgt_air_kg - co2_tgt_stock_kg
	)
	co2_moved_kg = minf(co2_moved_kg, co2_headroom_kg)
	if co2_moved_kg > 0.0:
		_delta_co2_kg[src_id] = _delta_co2_kg.get(src_id, 0.0) - co2_moved_kg
		# Reducir zona superior del origen proporcionalmente (usando estado pre-bucle).
		if source.co2_kg > 0.0001:
			var src_upper_frac: float = clampf(source.co2_upper_kg / source.co2_kg, 0.0, 1.0)
			_delta_co2_upper_kg[src_id] = _delta_co2_upper_kg.get(src_id, 0.0) - co2_moved_kg * src_upper_frac
		_delta_co2_kg[tgt_id] = _delta_co2_kg.get(tgt_id, 0.0) + co2_moved_kg
		# CO₂ llega a la zona superior del destino (gas caliente → boyante).
		_delta_co2_upper_kg[tgt_id] = _delta_co2_upper_kg.get(tgt_id, 0.0) + co2_moved_kg

	var smoke_moved_kg: float = minf(source.smoke_kg, source.smoke_kg * upper_fraction_moved * smoke_carry)
	if smoke_moved_kg > 0.0:
		_delta_smoke_kg[src_id] = _delta_smoke_kg.get(src_id, 0.0) - smoke_moved_kg
		_delta_smoke_kg[tgt_id] = _delta_smoke_kg.get(tgt_id, 0.0) + smoke_moved_kg

	# SF-R6: carry convectivo HCN (gated — hot_gas_hcn_carry_fraction > 0 para activar).
	if hot_gas_hcn_carry_fraction > 0.0:
		var hcn_upper_available_kg: float = clampf(source.hcn_upper_kg, 0.0, source.hcn_kg)
		var hcn_moved_kg: float = minf(
			source.hcn_kg,
			hcn_upper_available_kg * upper_fraction_moved * carry * clampf(hot_gas_hcn_carry_fraction, 0.0, 1.0)
		)
		if hcn_moved_kg > 0.0:
			_delta_hcn_kg[src_id]    = _delta_hcn_kg.get(src_id, 0.0)    - hcn_moved_kg
			_delta_hcn_upper_kg[src_id] = _delta_hcn_upper_kg.get(src_id, 0.0) - hcn_moved_kg
			_delta_hcn_kg[tgt_id]    = _delta_hcn_kg.get(tgt_id, 0.0)    + hcn_moved_kg
			_delta_hcn_upper_kg[tgt_id] = _delta_hcn_upper_kg.get(tgt_id, 0.0) + hcn_moved_kg

	# SF-R6: carry convectivo irritantes HCl/acroleína/formaldehído (gated).
	if hot_gas_irritant_carry_fraction > 0.0:
		var _irr_frac: float = clampf(hot_gas_irritant_carry_fraction, 0.0, 1.0)
		var hcl_moved_kg: float = minf(source.hcl_kg, source.hcl_kg * upper_fraction_moved * carry * _irr_frac)
		if hcl_moved_kg > 0.0:
			_delta_hcl_kg[src_id] = _delta_hcl_kg.get(src_id, 0.0) - hcl_moved_kg
			_delta_hcl_kg[tgt_id] = _delta_hcl_kg.get(tgt_id, 0.0) + hcl_moved_kg
		var acrolein_moved_kg: float = minf(source.acrolein_kg, source.acrolein_kg * upper_fraction_moved * carry * _irr_frac)
		if acrolein_moved_kg > 0.0:
			_delta_acrolein_kg[src_id] = _delta_acrolein_kg.get(src_id, 0.0) - acrolein_moved_kg
			_delta_acrolein_kg[tgt_id] = _delta_acrolein_kg.get(tgt_id, 0.0) + acrolein_moved_kg
		var formaldehyde_moved_kg: float = minf(source.formaldehyde_kg, source.formaldehyde_kg * upper_fraction_moved * carry * _irr_frac)
		if formaldehyde_moved_kg > 0.0:
			_delta_formaldehyde_kg[src_id] = _delta_formaldehyde_kg.get(src_id, 0.0) - formaldehyde_moved_kg
			_delta_formaldehyde_kg[tgt_id] = _delta_formaldehyde_kg.get(tgt_id, 0.0) + formaldehyde_moved_kg

	# SF-R6 Phase 3+4: conservación trivialmente garantizada por construcción —
	# delta[src] + delta[tgt] = -moved + moved = 0 por cada especie.
	_transport_call_count += 1


# SF-R6 Phase 4: aplica todos los deltas acumulados en _transfer_hot_gas_contaminants()
# al final del bucle de aperturas. Garantiza que todos los transportes del paso leen
# el estado PRE-bucle (Jacobi), eliminando efectos de ordenación entre aperturas.
func _flush_contaminant_deltas(building: BuildingModel) -> void:
	# Recopilar todos los room_ids con cambios pendientes.
	var touched: Dictionary = {}
	for rid in _delta_co_kg.keys():         touched[rid] = true
	for rid in _delta_co_upper_kg.keys():   touched[rid] = true
	for rid in _delta_co2_kg.keys():        touched[rid] = true
	for rid in _delta_co2_upper_kg.keys():  touched[rid] = true
	for rid in _delta_smoke_kg.keys():      touched[rid] = true
	for rid in _delta_hcn_kg.keys():        touched[rid] = true
	for rid in _delta_hcn_upper_kg.keys():  touched[rid] = true
	for rid in _delta_hcl_kg.keys():        touched[rid] = true
	for rid in _delta_acrolein_kg.keys():   touched[rid] = true
	for rid in _delta_formaldehyde_kg.keys(): touched[rid] = true

	for rid in touched.keys():
		var room: RoomModel = building.get_room(rid)
		if room == null:
			continue
		var _co_pre_thermal: float = room.co_kg
		room.co_kg           = maxf(0.0, room.co_kg           + _delta_co_kg.get(rid, 0.0))
		room.co_net_transport_kg_total += room.co_kg - _co_pre_thermal
		room.co_upper_kg     = maxf(0.0, room.co_upper_kg     + _delta_co_upper_kg.get(rid, 0.0))
		room.co2_kg          = maxf(0.0, room.co2_kg          + _delta_co2_kg.get(rid, 0.0))
		room.co2_upper_kg    = maxf(0.0, room.co2_upper_kg    + _delta_co2_upper_kg.get(rid, 0.0))
		var _smoke_pre_thermal: float = room.smoke_kg
		room.smoke_kg        = maxf(0.0, room.smoke_kg        + _delta_smoke_kg.get(rid, 0.0))
		room.smoke_net_transport_kg_step  += room.smoke_kg - _smoke_pre_thermal
		room.smoke_net_transport_kg_total += room.smoke_kg - _smoke_pre_thermal
		room.hcn_kg          = maxf(0.0, room.hcn_kg          + _delta_hcn_kg.get(rid, 0.0))
		room.hcn_upper_kg    = maxf(0.0, room.hcn_upper_kg    + _delta_hcn_upper_kg.get(rid, 0.0))
		room.hcl_kg          = maxf(0.0, room.hcl_kg          + _delta_hcl_kg.get(rid, 0.0))
		room.acrolein_kg     = maxf(0.0, room.acrolein_kg     + _delta_acrolein_kg.get(rid, 0.0))
		room.formaldehyde_kg = maxf(0.0, room.formaldehyde_kg + _delta_formaldehyde_kg.get(rid, 0.0))
		# Clamp: upper_kg no puede superar total_kg (post-aplicación).
		room.co_upper_kg  = clampf(room.co_upper_kg, 0.0, room.co_kg)
		room.hcn_upper_kg = clampf(room.hcn_upper_kg, 0.0, room.hcn_kg)

	_delta_co_kg.clear()
	_delta_co_upper_kg.clear()
	_delta_co2_kg.clear()
	_delta_co2_upper_kg.clear()
	_delta_smoke_kg.clear()
	_delta_hcn_kg.clear()
	_delta_hcn_upper_kg.clear()
	_delta_hcl_kg.clear()
	_delta_acrolein_kg.clear()
	_delta_formaldehyde_kg.clear()


# ============================================================
# PHASE 2F — CO INTERLAYER MIXING (experimental, default OFF)
# ============================================================
# Transfiere una fracción de co_upper_kg a la zona lower implícita (co_kg total invariante).
# Llamado DESPUÉS de _flush_contaminant_deltas() para no interferir con el flush Jacobi.
# ============================================================
func _apply_phase2f_co_interlayer_mixing(building: BuildingModel, dt: float) -> void:
	if not phase2f_co_interlayer_mixing_enabled or phase2f_co_interlayer_mixing_rate <= 0.0:
		return
	for room_id in building.get_rooms().keys():
		var room: RoomModel = building.get_room(room_id)
		if room == null or room.co_upper_kg <= 0.0:
			continue
		# Evaluar guard
		match phase2f_co_interlayer_mixing_guard:
			"only_when_upper_gas_kg_lt_0_1":
				if room.upper_gas_kg >= 0.1:
					continue
			"only_when_hot_layer_interface_above_1_8m":
				if effective_hot_layer_height_m(room) <= 1.8:
					continue
			"only_when_no_occupant_in_upper_probe":
				var interface_m: float = effective_hot_layer_height_m(room)
				var blocked: bool = false
				for vic in building.victims:
					if int(vic.get("room_id", -1)) == room.id and float(vic.get("height_m", 0.9)) >= interface_m:
						blocked = true
						break
				if blocked:
					continue
			_: # "no_guard" — aplica siempre
				pass
		# Transferir: co_upper_kg decrece, co_kg total invariante (lower = co_kg - co_upper_kg aumenta)
		var transfer_kg: float = minf(room.co_upper_kg * phase2f_co_interlayer_mixing_rate * dt, room.co_upper_kg)
		room.co_upper_kg = maxf(0.0, room.co_upper_kg - transfer_kg)


func reset_thermal_layer(room: RoomModel) -> void:
	if room == null:
		return

	room.thermal_layer_m = room.height_m


func reset_wall_temps() -> void:
	_wall_surface_temp_c.clear()
	_wall_pde_nodes_c.clear()


func estimate_thermal_layer_height_m(room: RoomModel) -> float:
	return LayerInterfaceModel.get_thermal_layer_height_m(room, ambient_temp_c())


func flow_interface_height_m(room: RoomModel) -> float:
	return LayerInterfaceModel.get_flow_interface_height_m(room, _smoke_model, ambient_temp_c())


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
	if two_zone_solver_enabled and _zone_fire_solver != null:
		_zone_fire_solver.add_lower_energy(room, mix_energy_kj, ambient_temp_c())
	else:
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

	# Fase 2E (tracking seguro): si no hay capa caliente establecida
	# (upper_gas_kg < 0.1 kg), el CO está distribuido de forma uniforme en toda
	# la sala — no hay estratificación. Devolver concentración promedio de la sala.
	# Evita falsos bajos cuando sync_room_upper_layer resetea co_upper_kg = 0
	# (capa colapsada sin fuego activo) pero thermal_layer_m aún no ha subido
	# hasta el techo, lo que daría upper_frac > 0 → strat ≈ 0 pese a haber CO.
	# El FED de zona inferior ya usa compute_co_ppm (no esta función), así que
	# el cambio es puramente de tracking/exportación — sin impacto en required.
	if room.upper_gas_kg < 0.1:
		return compute_co_ppm(room)

	# Lower zone: from floor up to the hot-layer interface.
	var hot_h: float = effective_hot_layer_height_m(room)
	var lower_height_m: float = maxf(0.05, hot_h)
	var lower_zone_mass_kg: float = maxf(0.1,
		room.floor_area_m2() * lower_height_m * gas_density_kg_m3(room.temp_lower_c))
	var co_upper_kg: float = clampf(room.co_upper_kg, 0.0, room.co_kg)
	var co_lower_kg: float = maxf(0.0, room.co_kg - co_upper_kg)
	var raw_ppm: float = co_lower_kg * 29.0e6 / maxf(0.1, lower_zone_mass_kg * 28.0)
	# Fase 2C: Estratificación de dos zonas (CFAST).
	# En un modelo de dos zonas con capa caliente establecida, la zona inferior está
	# protegida del CO (producido/acumulado en zona superior).
	# Pequeños residuos numéricos en co_lower_kg se amplifican al dividir por la
	# masa ínfima de la zona inferior cuando la capa caliente desciende.
	# Factor de estratificación: 0 cuando la capa superior ocupa ≥ 33 % de la altura.
	var upper_frac: float = clampf(
		(room.height_m - hot_h) / maxf(0.01, room.height_m), 0.0, 1.0)
	var strat: float = clampf(1.0 - upper_frac * 3.0, 0.0, 1.0)
	return raw_ppm * strat


## CO₂ estratificado – capa superior e inferior (2026-05-17).
## Fase 2B (2026-05-23): co2_upper se trackea como fracción molar directa en
## OxygenExchangeSystem para evitar el error de densidad del gas caliente.
## compute_co2_upper_ppm = room.co2_upper × 10⁶ (conversion directa, sin masa).
## FED usa esta función (V_CO2 potentiation en ISO 13571); NO cambiar a mass-derived
## sin auditar impacto en fed_co/fed_hcn.
func compute_co2_upper_ppm(room: RoomModel) -> float:
	if room == null:
		return 0.0
	return room.co2_upper * 1.0e6


## CO₂ capa superior — representación mass-derived (D2 Fase 1, 2026-06-30).
## Mismo patrón que compute_co_upper_ppm: usa co2_upper_kg y masa de zona upper
## temperatura-corregida.  MW_CO2 = 44 g/mol (vs MW_CO = 28 g/mol).
## Cuando upper_gas_kg < 0.1 kg (sin zona caliente establecida), devuelve el valor
## tracer (room.co2_upper × 1e6) como fallback — evita divergencia espuria antes
## de que el fuego estratifique la sala.  FED sin cambio: sigue usando compute_co2_upper_ppm.
func compute_co2_upper_ppm_mass(room: RoomModel) -> float:
	if room == null:
		return 0.0
	if room.upper_gas_kg < 0.1:
		return room.co2_upper * 1.0e6
	var hot_h: float = effective_hot_layer_height_m(room)
	var upper_height_m: float = maxf(0.05, room.height_m - hot_h)
	var upper_zone_mass_kg: float = maxf(0.1,
		room.floor_area_m2() * upper_height_m * gas_density_kg_m3(room.temp_upper_c))
	var co2_upper_kg: float = clampf(room.co2_upper_kg, 0.0, room.co2_kg)
	return co2_upper_kg * 29.0e6 / maxf(0.1, upper_zone_mass_kg * 44.0)


func compute_co2_lower_ppm(room: RoomModel) -> float:
	if room == null:
		return 0.0
	var hot_h: float = effective_hot_layer_height_m(room)
	var lower_height_m: float = maxf(0.05, hot_h)
	var lower_zone_mass_kg: float = maxf(0.1,
		room.floor_area_m2() * lower_height_m * gas_density_kg_m3(room.temp_lower_c))
	var co2_upper_kg: float = clampf(room.co2_upper_kg, 0.0, room.co2_kg)
	var co2_lower_kg: float = maxf(0.0, room.co2_kg - co2_upper_kg)
	return co2_lower_kg * 29.0e6 / maxf(0.1, lower_zone_mass_kg * 44.0)


## HCN estratificado – capa superior e inferior (2026-05-17).
func compute_hcn_upper_ppm(room: RoomModel) -> float:
	if room == null:
		return 0.0
	var hot_h: float = effective_hot_layer_height_m(room)
	var upper_height_m: float = maxf(0.05, room.height_m - hot_h)
	var upper_zone_mass_kg: float = maxf(0.1,
		room.floor_area_m2() * upper_height_m * gas_density_kg_m3(room.temp_upper_c))
	var hcn_upper_kg: float = clampf(room.hcn_upper_kg, 0.0, room.hcn_kg)
	return hcn_upper_kg * 29.0e6 / maxf(0.1, upper_zone_mass_kg * 27.0)


func compute_hcn_lower_ppm(room: RoomModel) -> float:
	if room == null:
		return 0.0
	var hot_h: float = effective_hot_layer_height_m(room)
	var lower_height_m: float = maxf(0.05, hot_h)
	var lower_zone_mass_kg: float = maxf(0.1,
		room.floor_area_m2() * lower_height_m * gas_density_kg_m3(room.temp_lower_c))
	var hcn_upper_kg: float = clampf(room.hcn_upper_kg, 0.0, room.hcn_kg)
	var hcn_lower_kg: float = maxf(0.0, room.hcn_kg - hcn_upper_kg)
	return hcn_lower_kg * 29.0e6 / maxf(0.1, lower_zone_mass_kg * 27.0)


func compute_co2_ppm(room: RoomModel) -> float:
	if room == null:
		return 0.0

	# Conversión masa CO2 → ppm volumétrico.
	# ppm = (m_co2 / M_co2) / (m_air / M_air) × 1e6
	# M_co2 = 44 g/mol, M_air = 29 g/mol
	return room.co2_kg * 29.0e6 / maxf(0.1, room.volume_m3() * 1.2 * 44.0)


func _fed_breathing_zone_thermal_exposure_factor(room: RoomModel, breathing_height_m: float) -> float:
	if room == null:
		return 0.0

	var height_m: float = maxf(0.1, room.height_m)
	var z_m: float = clampf(breathing_height_m, 0.0, height_m)
	if room.thermal_layer_m < 0.0 or room.thermal_layer_m > height_m:
		_warn_invalid_fed_layer_once(room, "thermal_layer_m", room.thermal_layer_m)
		return 0.0

	# FED térmico usa la interfaz térmica canónica. La capa visible/legacy
	# de humo es óptica y no debe activar exposición a calor.
	var exposure_factor: float = LayerInterfaceModel.get_breathing_zone_exposure_factor(
		room,
		z_m,
		ambient_temp_c()
	)
	if room.layer_150c_m < 0.0 or room.layer_150c_m > height_m:
		_warn_invalid_fed_layer_once(room, "layer_150c_m", room.layer_150c_m)
		return clampf(exposure_factor, 0.0, 1.0)

	var layer_150c_m: float = clampf(room.layer_150c_m, 0.0, height_m)
	if z_m >= layer_150c_m and room.temp_upper_c > fed_heat_conv_min_c:
		exposure_factor = 1.0
	return clampf(exposure_factor, 0.0, 1.0)


func _warn_invalid_fed_layer_once(room: RoomModel, field_name: String, value: float) -> void:
	if room == null:
		return
	var key: String = "%d:%s" % [room.id, field_name]
	if _fed_layer_warning_keys.has(key):
		return
	_fed_layer_warning_keys[key] = true
	push_warning(
		"FED thermal exposure: %s invalid in room %d (%.3f); using safe thermal fallback." % [
			field_name,
			room.id,
			value
		]
	)


## Calcula el incremento de FED ISO 13571 para un ocupante a una altura específica,
## sin modificar room.fed. Permite acumulación externa por víctima.
## height_m: plano respiratorio (0.9m=tumbado, 1.5m=sentado, 1.8m=de pie).
func compute_fed_delta_for_height(room: RoomModel, dt: float, height_m: float) -> float:
	if room == null or dt <= 0.0:
		return 0.0

	var thermal_exposure_factor: float = _fed_breathing_zone_thermal_exposure_factor(room, height_m)
	var in_upper: bool = (thermal_exposure_factor >= 0.5 and room.upper_gas_kg > 0.1)
	var co_ppm: float   = compute_co_upper_ppm(room)  if in_upper else compute_co_ppm(room)
	var co2_ppm: float  = compute_co2_upper_ppm(room) if in_upper else compute_co2_lower_ppm(room)
	var dt_min: float   = dt / 60.0
	var delta: float    = 0.0

	var co2_pct: float = co2_ppm / 10000.0
	var v_co2: float = 1.0
	if co2_pct > 2.0:
		v_co2 = exp(0.1903 * co2_pct + 2.0004) / 7.1

	if co_ppm > 0.0:
		delta += 3.317e-5 * pow(co_ppm, 1.036) * v_co2 * dt_min

	var hcn_ppm: float = compute_hcn_upper_ppm(room) if in_upper else compute_hcn_lower_ppm(room)
	if hcn_ppm > 0.0:
		delta += hcn_ppm / 4400.0 * v_co2 * dt_min

	if fed_hypoxia_enabled:
		# Fase 2E-A: zona inferior usa o2_lower (protegida del fuego, siempre >= room.o2).
		var o2_pct: float = clampf((room.o2_upper if in_upper else room.o2_lower) * 100.0, 0.0, 20.9)
		var o2_deficit: float = maxf(0.0, 20.9 - o2_pct)
		if o2_deficit > 0.0:
			var t_crit: float = exp(fed_hypoxia_a - fed_hypoxia_b * o2_deficit)
			if t_crit > 0.0:
				delta += dt_min / t_crit

	if fed_heat_enabled and room.upper_gas_kg > 0.01:
		if in_upper and room.temp_upper_c > fed_heat_conv_min_c:
			var tenab: float = fed_heat_conv_a * pow(room.temp_upper_c, -fed_heat_conv_n)
			var tenab_s: float = tenab * 60.0
			if tenab_s > 0.0:
				delta += dt / tenab_s
		var sigma_kw: float = 5.670374419e-11
		var t_upper_k: float = room.temp_upper_c + 273.15
		var vf: float = fed_heat_rad_view_factor if in_upper else fed_heat_rad_view_factor_below
		var q_rad: float = maxf(0.0, 0.85 * sigma_kw * (pow(t_upper_k, 4.0) - pow(310.0, 4.0)) * vf)
		if q_rad > 2.5:
			var tenab_rad: float = fed_heat_rad_a / pow(q_rad, 1.33)
			if tenab_rad > 0.0 and tenab_rad < 3600.0:
				delta += dt / tenab_rad

	return maxf(0.0, delta)


## Paso incremental de FED (Fractional Effective Dose) según ISO 13571.
## Modelo asfixiante implementado:
## - FED_CO: narcosis por CO con factor de hiperventilación por CO2
## - FED_O2: hipoxia por depleción de oxígeno
## FED_total(Δt) = FED_CO(Δt) + FED_O2(Δt)
func step_fed(room: RoomModel, dt: float) -> void:
	if room == null or dt <= 0.0:
		return

	# Cuando la capa caliente desciende bajo la altura de respiración (configurable,
	# por defecto 1.8 m adulto de pie ISO 13571), el ocupante está inmerso.
	var thermal_exposure_factor: float = _fed_breathing_zone_thermal_exposure_factor(
		room,
		fed_upper_layer_threshold_m
	)
	var in_upper_layer: bool = (thermal_exposure_factor >= 0.5 and room.upper_gas_kg > 0.1)
	var co_ppm: float = compute_co_upper_ppm(room) if in_upper_layer else compute_co_ppm(room)
	var co2_ppm: float = compute_co2_upper_ppm(room) if in_upper_layer else compute_co2_lower_ppm(room)

	var dt_min: float = dt / 60.0
	# Phase 4B: per-component delta accumulators for observability.
	var delta_co: float = 0.0
	var delta_hcn: float = 0.0
	var delta_hypoxia: float = 0.0
	var delta_heat: float = 0.0

	# Factor de hiperventilación por CO2 (ISO 13571): se aplica a CO y a HCN.
	var co2_pct: float = co2_ppm / 10000.0
	var v_co2: float = 1.0
	if co2_pct > 2.0:
		v_co2 = exp(0.1903 * co2_pct + 2.0004) / 7.1

	# ISO 13571 Eq. 2-3: dosis incremental por CO, con ajuste por CO2 solo > 2% vol.
	if co_ppm > 0.0:
		delta_co = 3.317e-5 * pow(co_ppm, 1.036) * v_co2 * dt_min

	# ISO 13571 §A.2.2: dosis incremental por HCN (cianuro de hidrógeno).
	# Modelo lineal de Purser: LC50 ≈ 4400 ppm·min (humano equivalente, 30 min).
	var hcn_ppm: float = compute_hcn_upper_ppm(room) if in_upper_layer else compute_hcn_lower_ppm(room)
	if hcn_ppm > 0.0:
		delta_hcn = hcn_ppm / 4400.0 * v_co2 * dt_min

	# ISO 13571 (modelo asfixiante): componente de hipoxia por O2.
	if fed_hypoxia_enabled:
		# Fase 2E-A: zona inferior usa o2_lower (protegida del fuego, siempre >= room.o2).
		var o2_pct: float = clampf((room.o2_upper if in_upper_layer else room.o2_lower) * 100.0, 0.0, 20.9)
		var o2_deficit_pct: float = maxf(0.0, 20.9 - o2_pct)
		if o2_deficit_pct > 0.0:
			var t_crit_min: float = exp(fed_hypoxia_a - fed_hypoxia_b * o2_deficit_pct)
			if t_crit_min > 0.0:
				delta_hypoxia = dt_min / t_crit_min

	# ISO 13571 §5.5 + §5.4.3: FED térmico (calor convectivo + radiante).
	if fed_heat_enabled and room.upper_gas_kg > 0.01:
		# --- Componente convectiva (ISO 13571 sec. 8.3) ---
		# Solo cuando el ocupante respira el gas caliente (inmerso en la capa superior).
		if in_upper_layer and room.temp_upper_c > fed_heat_conv_min_c:
			var tenab_min: float = fed_heat_conv_a * pow(room.temp_upper_c, -fed_heat_conv_n)
			var tenab_s: float = tenab_min * 60.0
			if tenab_s > 0.0:
				delta_heat += dt / tenab_s
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
				delta_heat += dt / tenab_rad_s

	var delta_fed: float = delta_co + delta_hcn + delta_hypoxia + delta_heat
	room.fed += maxf(0.0, delta_fed)
	# Phase 4B: accumulate per-component for observability in logs/CSV.
	room.fed_co += maxf(0.0, delta_co)
	room.fed_hcn += maxf(0.0, delta_hcn)
	room.fed_hypoxia += maxf(0.0, delta_hypoxia)
	room.fed_heat += maxf(0.0, delta_heat)

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
		# Para el criterio térmico secundario usamos la capa térmica canónica,
		# no la capa visible legacy, porque pertenece a humo/óptica.
		var hot_h: float = LayerInterfaceModel.get_thermal_layer_height_m(
			room,
			ambient_temp_c()
		)
		hot_h = clampf(hot_h, 0.0, height_m)

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

	if two_zone_solver_enabled and _zone_fire_solver != null:
		_sync_room_two_zone_layer(room, dt)
		return

	var ambient_c: float = ambient_temp_c()
	room.upper_gas_kg = maxf(0.0, room.upper_gas_kg)
	room.upper_energy_kj = maxf(0.0, room.upper_energy_kj)

	if _should_collapse_thermal_layer(room):
		room.upper_gas_kg = 0.0
		room.upper_energy_kj = 0.0
		room.co_upper_kg = 0.0
		room.co2_upper_kg = 0.0
		room.hcn_upper_kg = 0.0
		room.temp_upper_c = room.temp_lower_c
		room.temp_upper_raw_c = room.temp_upper_c
		room.temp_upper_clamped = false
		room.upper_radiative_loss_kw = 0.0
		reset_thermal_layer(room)
		_smoke_model.recompute_layer_from_mass(room, dt, ambient_c)
		return

	if room.upper_gas_kg <= 0.0001 or room.upper_energy_kj <= 0.0001:
		# SF-AUD-XXX: Si la energía se agota (p.ej. absorción PDE drena toda la energía
		# del paso) pero la masa es finita, conservar la masa — el gas existe a temperatura
		# ambiente. Resetear solo la masa destruiría el acumulador del penacho y mantendría
		# la temperatura permanentemente en el ambiente aunque el fuego siga activo.
		if room.upper_gas_kg > 0.0001 and room.upper_energy_kj <= 0.0001:
			room.upper_energy_kj = 0.0
			room.temp_upper_c = maxf(room.temp_lower_c, ambient_c)
			room.temp_upper_raw_c = room.temp_upper_c
			room.temp_upper_clamped = false
			room.upper_radiative_loss_kw = 0.0
			var _tgt_h: float = estimate_thermal_layer_height_m(room)
			if _tgt_h < room.thermal_layer_m:
				room.thermal_layer_m = _tgt_h
			_smoke_model.recompute_layer_from_mass(room, dt, ambient_c)
			return
		# Sin masa (o ambas nulas): colapso completo de la capa.
		room.upper_gas_kg = 0.0
		room.upper_energy_kj = 0.0
		# Fase 2C: El colapso transitorio de la capa no debe destruir el seguimiento
		# de CO/CO₂ cuando el fuego está activo. En el modelo de dos zonas (CFAST),
		# los gases de combustión se producen en la zona superior. Si la capa se colapsa
		# momentáneamente (p.ej. por venteo de presión), sincronizar co_upper_kg = co_kg
		# preserva la propiedad co_lower_kg ≈ 0 hasta que la capa se reconstruya.
		# Solo resetear a 0 cuando el fuego está verdaderamente extinto.
		var fire_active: bool = room.hrr_kw > 0.1 or room.fire != null
		if fire_active:
			room.co_upper_kg = room.co_kg
			room.co2_upper_kg = room.co2_kg
			room.hcn_upper_kg = room.hcn_kg
		else:
			room.co_upper_kg = 0.0
			room.co2_upper_kg = 0.0
			room.hcn_upper_kg = 0.0
		room.temp_upper_c = maxf(room.temp_lower_c, ambient_c)
		room.temp_upper_raw_c = room.temp_upper_c
		room.temp_upper_clamped = false
		room.upper_radiative_loss_kw = 0.0
		reset_thermal_layer(room)
		_smoke_model.recompute_layer_from_mass(room, dt, ambient_c)
		return

	room.co_upper_kg = clampf(room.co_upper_kg, 0.0, room.co_kg)
	room.co2_upper_kg = clampf(room.co2_upper_kg, 0.0, room.co2_kg)
	room.hcn_upper_kg = clampf(room.hcn_upper_kg, 0.0, room.hcn_kg)
	# Phase 2I — CO₂ upper fraction floor en sala fuego (default OFF = 0.0)
	# Eleva co2_upper_kg a mín. co2_kg × fraction cuando hay fuego activo.
	# co2_kg permanece invariante. Afecta co2_lower_kg implícito (= co2_kg - co2_upper_kg).
	# NOTA: room.co2_upper (fracción molar, log CO2u=, FED V_CO2 en upper) NO se modifica aquí.
	if phase2i_co2_upper_fraction > 0.0 and (room.hrr_kw > 0.1 or room.fire != null):
		var _p2i_target: float = room.co2_kg * phase2i_co2_upper_fraction
		room.co2_upper_kg = clampf(maxf(room.co2_upper_kg, _p2i_target), 0.0, room.co2_kg)
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
	# BV-030: en un modelo de zona, la capa superior nunca puede ser más fría que la inferior.
	# Esta aserción defensiva detecta regresiones futuras; no debe activarse en operación normal.
	if room.temp_upper_c < room.temp_lower_c - 1.0:
		push_warning("BV-030: inversión de capa sala %d — T_upper=%.1f°C < T_lower=%.1f°C" % [
			room.id, room.temp_upper_c, room.temp_lower_c
		])


func _sync_room_two_zone_layer(room: RoomModel, dt: float) -> void:
	var ambient_c: float = ambient_temp_c()
	_zone_fire_solver.ensure_room_state(room, ambient_c)
	if _should_collapse_thermal_layer(room):
		_zone_fire_solver.collapse_upper_into_lower(room, ambient_c)
		room.co_upper_kg = 0.0
		room.co2_upper_kg = 0.0
		room.hcn_upper_kg = 0.0

	room.co_upper_kg = clampf(room.co_upper_kg, 0.0, room.co_kg)
	room.co2_upper_kg = clampf(room.co2_upper_kg, 0.0, room.co2_kg)
	room.hcn_upper_kg = clampf(room.hcn_upper_kg, 0.0, room.hcn_kg)
	_zone_fire_solver.project_room_state(room, ambient_c, max_upper_temp_c)
	_smoke_model.recompute_layer_from_mass(room, dt, ambient_c)

	if room.temp_upper_c < room.temp_lower_c - 1.0:
		push_warning("M1 two-zone: inversión de capa sala %d — T_upper=%.1f°C < T_lower=%.1f°C" % [
			room.id, room.temp_upper_c, room.temp_lower_c
		])


func reconcile_two_zone_building(building: BuildingModel, dt: float) -> void:
	if not two_zone_solver_enabled or _zone_fire_solver == null or building == null:
		return
	var ambient_c: float = ambient_temp_c()
	for room_id in building.get_rooms().keys():
		var room: RoomModel = building.get_room(room_id)
		if room == null:
			continue
		_zone_fire_solver.reconcile_projected_temperatures(room, ambient_c)
		_sync_room_two_zone_layer(room, dt)


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

	if two_zone_solver_enabled:
		return clampf(room.thermal_layer_m, 0.0, room.height_m)

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

	# SF-R7: Apertura vertical (hueco de suelo/techo entre plantas).
	# El flujo es impulsado por efecto chimenea: gas caliente sube, aire frío baja.
	# Formula: Q = Cd · A · sqrt(2 · g · H_z · ΔT / T_cold)  [SFPE §3.2 chimney effect]
	if op.is_vertical:
		var _flow_interface_v_m: float = flow_interface_height_m(hot_room)
		var _g_v: float = 9.81
		var _cd_v: float = 0.61
		# Area del hueco en plano horizontal (width × height ≡ dos dimensiones del suelo)
		var _area_v: float = op.width_m * op.height_m * op.open_fraction
		if _area_v <= 0.001:
			return state
		# Altura de accionamiento = diferencia de cota entre plantas
		# Si las salas no tienen floor_level_z_m asignado, usar la altura de sala como proxy.
		var _floor_low: float = minf(room_a.floor_level_z_m, room_b.floor_level_z_m)
		var _floor_high: float = maxf(room_a.floor_level_z_m, room_b.floor_level_z_m)
		var _H_z: float = maxf(0.5, _floor_high - _floor_low)
		if _floor_high <= _floor_low + 0.01:
			# floor_level_z_m no diferenciado; usar altura de sala caliente como proxy
			_H_z = maxf(0.5, hot_room.height_m)
		var _T_hot_v_k: float = hot_room.temp_upper_c + 273.15
		var _T_cold_v_k: float = cold_room.temp_upper_c + 273.15
		var _dT_v: float = maxf(0.0, _T_hot_v_k - _T_cold_v_k)
		if _dT_v < 2.0:
			return state
		var _q_vert_m3s: float = _cd_v * _area_v * sqrt(2.0 * _g_v * _H_z * _dT_v / _T_cold_v_k)
		var _rho_hot_v: float = 353.0 / maxf(50.0, _T_hot_v_k)
		var _rho_cold_v: float = 353.0 / maxf(50.0, _T_cold_v_k)
		# Punto de mezcla: temperatura de referencia para la entalpía transferida
		var _source_temp_v: float = hot_room.temp_upper_c
		var _sink_temp_v: float = cold_room.temp_upper_c
		var _temp_delta_v: float = maxf(0.0, _source_temp_v - _sink_temp_v)
		state["active"] = true
		state["hot_room"] = hot_room
		state["cold_room"] = cold_room
		state["hot_band_m"] = hot_room.height_m  # toda la capa caliente disponible
		state["smoke_band_m"] = hot_room.height_m
		state["h_drive_m"] = _H_z
		state["area_eff_m2"] = _area_v
		state["engagement"] = clampf(_dT_v / maxf(1.0, _dT_v + 50.0), 0.0, 1.0)
		state["source_temp_c"] = _source_temp_v
		state["temp_delta_k"] = _temp_delta_v
		state["neutral_plane_f"] = 0.5
		state["flow_interface_m"] = _flow_interface_v_m
		# Caudal másico: gas caliente asciende; aire frío desciende (conservación de masa)
		state["bernoulli_upper_kg_s"] = _q_vert_m3s * _rho_hot_v
		state["bernoulli_lower_kg_s"] = _q_vert_m3s * _rho_cold_v
		return state

	var lintel_m: float = op.lintel_height_m()
	var spill_trigger_layer_m: float = _interior_spill_trigger_layer_m(hot_room, lintel_m)
	var flow_interface_m: float = flow_interface_height_m(hot_room)
	var hot_band_m: float = maxf(0.0, spill_trigger_layer_m - flow_interface_m)
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
	var h_thermal_np: float = flow_interface_m
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
	state["flow_interface_m"] = flow_interface_m

	# ── SF-AUD-010: Bernoulli dos zonas (SFPE §3.2; CFAST TN 1889v1 §2.2) ──────
	# Q = Cd · W · f · (2/3) · h_zona^(3/2) · sqrt(2g · ΔT / T_ref)  [m³/s]
	# ρ_gas ≈ 353 / T_K  [kg/m³]  (gas ideal: M_aire ≈ 0.029 kg/mol, P ≈ 101 kPa)
	# Capa alta: gas caliente sale de hot_room por encima del plano neutro.
	# Capa baja: aire frío entra a hot_room por debajo del plano neutro.
	# Siempre calculado; solo se usa cuando vent_bernoulli_enabled = true.
	var _g_b: float = 9.81
	var _cd_b: float = 0.65
	var _w_b: float = op.width_m * op.open_fraction
	var _h_upper_b: float = neutral_plane_f * op.height_m
	var _h_lower_b: float = clampf((1.0 - neutral_plane_f) * op.height_m, 0.0, op.height_m)
	var _T_hot_b_k: float = hot_room.temp_upper_c + 273.15
	var _T_cold_b_k: float = cold_room.temp_lower_c + 273.15
	var _T_ref_b_k: float = (_T_hot_b_k + _T_cold_b_k) * 0.5
	var _dT_upper_b: float = maxf(0.0, _T_hot_b_k - _T_cold_b_k)
	var _T_hot_lower_b_k: float = hot_room.temp_lower_c + 273.15
	var _dT_lower_b: float = maxf(0.0, _T_cold_b_k - _T_hot_lower_b_k)
	var _q_upper_b: float = 0.0
	if _h_upper_b > 0.001 and _dT_upper_b > 0.5:
		_q_upper_b = _cd_b * _w_b * (2.0 / 3.0) * pow(_h_upper_b, 1.5) \
				* sqrt(2.0 * _g_b * _dT_upper_b / _T_ref_b_k)
	var _q_lower_b: float = 0.0
	if _h_lower_b > 0.001 and _dT_lower_b > 0.5:
		var _T_ref_lower_b: float = (_T_cold_b_k + _T_hot_lower_b_k) * 0.5
		_q_lower_b = _cd_b * _w_b * (2.0 / 3.0) * pow(_h_lower_b, 1.5) \
				* sqrt(2.0 * _g_b * _dT_lower_b / _T_ref_lower_b)
	elif _q_upper_b > 0.0:
		# Conservación de masa: caudal entrante compensa saliente (distintas densidades)
		var _rho_hot_b: float = 353.0 / maxf(50.0, _T_hot_b_k)
		var _rho_cold_b: float = 353.0 / maxf(50.0, _T_cold_b_k)
		_q_lower_b = _q_upper_b * _rho_hot_b / maxf(0.001, _rho_cold_b)
	state["bernoulli_upper_kg_s"] = _q_upper_b * (353.0 / maxf(50.0, _T_hot_b_k))
	state["bernoulli_lower_kg_s"] = _q_lower_b * (353.0 / maxf(50.0, _T_cold_b_k))
	return state

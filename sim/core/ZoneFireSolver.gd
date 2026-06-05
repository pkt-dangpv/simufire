extends RefCounted
class_name ZoneFireSolver

# ============================================================
# ZONE FIRE SOLVER  (SF-R6 — Consolidado)
# ------------------------------------------------------------
# Coordinador central de flujos de masa / entalpía / especies
# entre zonas (upper/lower) de habitaciones adyacentes.
#
# OBJETIVO: garantizar que ThermalSystem, GasExchangeSystem y
# OxygenExchangeSystem operen sobre los MISMOS flujos de masa
# para cada abertura en cada paso — evitando contabilidad doble
# y violaciones de conservación.
#
# ESTADO DE IMPLEMENTACIÓN:
#   Fase 1 (SF-R6 sesión 1):
#     - Esqueleto + registro en SimulationEngine.
#     - Fix: CO₂_upper tracking en hot_gas convective carry.
#     - Carry convectivo HCN/HCL/irritantes (gated, off por defecto).
#     - Campo "zone_resolved_upper_mass_kg" escrito en flow_cache
#       por ThermalSystem para uso futuro de GasExchange/OxygenExchange.
#   Fase 2 (SF-R6 sesión 2):
#     - CO₂ upper zone tracking activo en _transfer_hot_gas_contaminants.
#     - hot_gas_hcn_carry_fraction = 0.40 (HCN viaja con gas caliente).
#     - hot_gas_irritant_carry_fraction = 0.30 (HCl/acroleína/HCHO).
#     - @export vars en SimulationEngine; configure() en ThermalSystem.
#     - Re-baseline suite (CO₂ estratificado → FED más lento en destino).
#   Fases futuras:
#     - Fase 2: GasExchangeSystem lee zone_resolved_upper_mass_kg
#       para reemplazar la fórmula de background con el flujo canónico.
#     - Fase 3: OxygenExchangeSystem usa mismo flujo canónico.
#   Fase 4 (SF-R6 sesión 3):
#     - Delta-acumulación simultánea en _transfer_hot_gas_contaminants().
#       Todas las lecturas usan el estado pre-bucle; todas las escrituras se
#       aplican juntas en _flush_contaminant_deltas() (enfoque Jacobi).
#       Elimina efectos de ordenación entre aperturas.
# ============================================================

## Habilita la coordinación de flujos ZoneFireSolver.
## 1=skeleton, 2=CO₂/HCN upper transport, 3=validate_conservation(), 4=delta-acumulación.
var zone_solver_phase: int = 4

## M1: activa el ledger canonico de masa y energia de las dos zonas.
## Legacy permanece sin cambios cuando false.
var two_zone_energy_enabled: bool = false

const AIR_DENSITY_REF_KG_M3: float = 1.2
const AIR_CP_KJ_KG_K: float = 1.0
const ZONE_MASS_EPS_KG: float = 0.0001

## Fracción de carry convectivo para HCN (respecto al carry general).
## 0.40 calibrado para parity CFAST TN-1889 (HCN viaja con gas caliente).
var hot_gas_hcn_carry_fraction: float = 0.40

## Fracción de carry convectivo para irritantes (HCl, acroleína, HCHO).
## 0.30 = ~75% del carry HCN (irritantes más pesados, menor movilidad).
var hot_gas_irritant_carry_fraction: float = 0.30

## Umbral de violación relativa de conservación de transporte que emite push_warning.
## 0.0001 = 0.01% — errores de punto flotante genuinos son < 1e-12, cualquier cosa
## mayor a 0.0001 indica un posible bug de contabilidad en la transferencia de especies.
var conservation_violation_threshold: float = 0.0001

## Peor violación de conservación de transporte registrada desde inicio de simulación.
## Acumulado a lo largo de todos los pasos. Se expone en el estado para CI.
var conservation_max_violation_frac: float = 0.0

## Número de pasos en que se detectó una violación > conservation_violation_threshold.
var conservation_violation_count: int = 0

# ------------------------------------------------------------------
# Referencia al building (inyectada desde SimulationEngine)
# ------------------------------------------------------------------
var _building: BuildingModel = null

func set_building(b: BuildingModel) -> void:
	_building = b


# ------------------------------------------------------------------
# M1: ledger canonico de masa y energia two-zone.
# upper_gas_kg/upper_energy_kj son el estado superior existente;
# lower_gas_kg/lower_energy_kj completan el par conservativo.
# ------------------------------------------------------------------

func ensure_room_state(room: RoomModel, ambient_c: float) -> void:
	if not two_zone_energy_enabled or room == null:
		return

	room.upper_gas_kg = maxf(0.0, room.upper_gas_kg)
	room.upper_energy_kj = maxf(0.0, room.upper_energy_kj)
	room.lower_gas_kg = maxf(0.0, room.lower_gas_kg)
	room.lower_energy_kj = maxf(0.0, room.lower_energy_kj)

	if room.zone_total_mass_kg() <= ZONE_MASS_EPS_KG:
		room.lower_gas_kg = maxf(0.0, room.volume_m3() * AIR_DENSITY_REF_KG_M3)
	if room.lower_energy_kj <= 0.0 and room.temp_lower_c > ambient_c:
		room.lower_energy_kj = room.lower_gas_kg \
				* maxf(0.0, room.temp_lower_c - ambient_c) \
				* AIR_CP_KJ_KG_K


func transfer_lower_to_upper(room: RoomModel, requested_mass_kg: float, ambient_c: float) -> float:
	if not two_zone_energy_enabled or room == null or requested_mass_kg <= 0.0:
		return 0.0

	ensure_room_state(room, ambient_c)
	var moved_mass_kg: float = minf(maxf(0.0, requested_mass_kg), room.lower_gas_kg)
	if moved_mass_kg <= 0.0:
		return 0.0

	var lower_specific_energy_kj_kg: float = room.lower_energy_kj \
			/ maxf(ZONE_MASS_EPS_KG, room.lower_gas_kg)
	var moved_energy_kj: float = minf(
		room.lower_energy_kj,
		moved_mass_kg * lower_specific_energy_kj_kg
	)
	room.lower_gas_kg = maxf(0.0, room.lower_gas_kg - moved_mass_kg)
	room.lower_energy_kj = maxf(0.0, room.lower_energy_kj - moved_energy_kj)
	room.upper_gas_kg += moved_mass_kg
	room.upper_energy_kj += moved_energy_kj
	return moved_mass_kg


func add_lower_energy(room: RoomModel, energy_kj: float, ambient_c: float) -> void:
	if not two_zone_energy_enabled or room == null or energy_kj == 0.0:
		return
	ensure_room_state(room, ambient_c)
	room.lower_energy_kj = maxf(0.0, room.lower_energy_kj + energy_kj)


func remove_lower_energy_fraction(room: RoomModel, fraction: float, ambient_c: float) -> float:
	if not two_zone_energy_enabled or room == null:
		return 0.0
	ensure_room_state(room, ambient_c)
	var removed_kj: float = room.lower_energy_kj * clampf(fraction, 0.0, 1.0)
	room.lower_energy_kj = maxf(0.0, room.lower_energy_kj - removed_kj)
	return removed_kj


func reconcile_projected_temperatures(room: RoomModel, ambient_c: float) -> void:
	if not two_zone_energy_enabled or room == null:
		return
	ensure_room_state(room, ambient_c)
	var energy_before_kj: float = room.zone_total_energy_kj()
	room.upper_energy_kj = room.upper_gas_kg \
			* maxf(0.0, room.temp_upper_c - ambient_c) \
			* AIR_CP_KJ_KG_K
	room.lower_energy_kj = room.lower_gas_kg \
			* maxf(0.0, room.temp_lower_c - ambient_c) \
			* AIR_CP_KJ_KG_K
	room.two_zone_boundary_energy_kj += room.zone_total_energy_kj() - energy_before_kj


func project_room_state(room: RoomModel, ambient_c: float, max_upper_temp_c: float) -> void:
	if not two_zone_energy_enabled or room == null:
		return
	ensure_room_state(room, ambient_c)
	var projection_energy_before_kj: float = room.zone_total_energy_kj()

	var lower_temp_c: float = ambient_c
	if room.lower_gas_kg > ZONE_MASS_EPS_KG:
		lower_temp_c = ambient_c + room.lower_energy_kj \
				/ (room.lower_gas_kg * AIR_CP_KJ_KG_K)

	var upper_temp_raw_c: float = lower_temp_c
	if room.upper_gas_kg > ZONE_MASS_EPS_KG:
		upper_temp_raw_c = ambient_c + room.upper_energy_kj \
				/ (room.upper_gas_kg * AIR_CP_KJ_KG_K)

	# Una inversion termica se mezcla instantaneamente conservando energia sensible.
	if room.upper_gas_kg > ZONE_MASS_EPS_KG and upper_temp_raw_c < lower_temp_c:
		var total_mass_kg: float = room.zone_total_mass_kg()
		var mixed_temp_c: float = ambient_c + room.zone_total_energy_kj() \
				/ maxf(ZONE_MASS_EPS_KG, total_mass_kg * AIR_CP_KJ_KG_K)
		room.upper_energy_kj = room.upper_gas_kg \
				* maxf(0.0, mixed_temp_c - ambient_c) \
				* AIR_CP_KJ_KG_K
		room.lower_energy_kj = room.lower_gas_kg \
				* maxf(0.0, mixed_temp_c - ambient_c) \
				* AIR_CP_KJ_KG_K
		lower_temp_c = mixed_temp_c
		upper_temp_raw_c = mixed_temp_c

	room.temp_lower_c = maxf(ambient_c, lower_temp_c)
	room.temp_upper_raw_c = maxf(room.temp_lower_c, upper_temp_raw_c)
	room.temp_upper_clamped = room.temp_upper_raw_c > max_upper_temp_c
	room.temp_upper_c = minf(room.temp_upper_raw_c, max_upper_temp_c)
	if room.upper_gas_kg <= ZONE_MASS_EPS_KG:
		room.temp_upper_c = room.temp_lower_c
		room.temp_upper_raw_c = room.temp_upper_c
		room.temp_upper_clamped = false

	# El cap termico es un sumidero numerico explicito, igual que en legacy.
	room.upper_energy_kj = room.upper_gas_kg \
			* maxf(0.0, room.temp_upper_c - ambient_c) \
			* AIR_CP_KJ_KG_K
	room.lower_energy_kj = room.lower_gas_kg \
			* maxf(0.0, room.temp_lower_c - ambient_c) \
			* AIR_CP_KJ_KG_K

	var ambient_k: float = ambient_c + 273.15
	var upper_k: float = maxf(ambient_k, room.temp_upper_c + 273.15)
	var upper_density_kg_m3: float = AIR_DENSITY_REF_KG_M3 * ambient_k / upper_k
	var max_upper_mass_kg: float = room.volume_m3() * upper_density_kg_m3
	if room.upper_gas_kg > max_upper_mass_kg and room.upper_gas_kg > ZONE_MASS_EPS_KG:
		var upper_mass_before_kg: float = room.upper_gas_kg
		room.upper_energy_kj *= max_upper_mass_kg / upper_mass_before_kg
		room.upper_gas_kg = max_upper_mass_kg
		room.two_zone_boundary_mass_kg += room.upper_gas_kg - upper_mass_before_kg
	var upper_volume_m3: float = room.upper_gas_kg / maxf(0.05, upper_density_kg_m3)
	var upper_depth_m: float = upper_volume_m3 / maxf(0.01, room.floor_area_m2())
	room.thermal_layer_m = clampf(room.height_m - upper_depth_m, 0.0, room.height_m)

	# Cierre de volumen a presión de referencia. Mientras M3 no resuelva cada
	# apertura por zonas, la diferencia se trata como intercambio con el contorno:
	# entrada a temperatura ambiente o salida con la entalpía especifica lower.
	var lower_volume_m3: float = maxf(0.0, room.volume_m3() - minf(room.volume_m3(), upper_volume_m3))
	var lower_k: float = maxf(ambient_k, room.temp_lower_c + 273.15)
	var lower_density_kg_m3: float = AIR_DENSITY_REF_KG_M3 * ambient_k / lower_k
	var target_lower_mass_kg: float = lower_volume_m3 * lower_density_kg_m3
	var lower_mass_before_kg: float = room.lower_gas_kg
	if target_lower_mass_kg < lower_mass_before_kg and lower_mass_before_kg > ZONE_MASS_EPS_KG:
		room.lower_energy_kj *= target_lower_mass_kg / lower_mass_before_kg
	room.lower_gas_kg = maxf(0.0, target_lower_mass_kg)
	room.two_zone_boundary_mass_kg += room.lower_gas_kg - lower_mass_before_kg
	if room.lower_gas_kg > ZONE_MASS_EPS_KG:
		room.temp_lower_c = ambient_c + room.lower_energy_kj \
				/ (room.lower_gas_kg * AIR_CP_KJ_KG_K)
	else:
		room.lower_energy_kj = 0.0
		room.temp_lower_c = ambient_c
	room.two_zone_boundary_energy_kj += room.zone_total_energy_kj() - projection_energy_before_kj


func collapse_upper_into_lower(room: RoomModel, ambient_c: float) -> void:
	if not two_zone_energy_enabled or room == null:
		return
	ensure_room_state(room, ambient_c)
	room.lower_gas_kg += room.upper_gas_kg
	room.lower_energy_kj += room.upper_energy_kj
	room.upper_gas_kg = 0.0
	room.upper_energy_kj = 0.0


# ------------------------------------------------------------------
# Fase 1: enriquece el flow_cache con datos resueltos que
# ThermalSystem escribe tras procesar cada abertura.
# GasExchange y OxygenExchange leerán estos datos en fases 2-3.
# ------------------------------------------------------------------

## Devuelve la masa resuelta del flujo de gas caliente para la
## abertura `op` (escrita por ThermalSystem durante su step).
## Retorna 0.0 si ThermalSystem no procesó esta abertura (inactiva).
static func get_resolved_upper_mass_kg(flow_state: Dictionary) -> float:
	return float(flow_state.get("zone_resolved_upper_mass_kg", 0.0))

## Retorna la dirección del flujo: id de la sala caliente (→ fría).
static func get_resolved_hot_room_id(flow_state: Dictionary) -> int:
	return int(flow_state.get("zone_resolved_hot_room_id", -1))


# ------------------------------------------------------------------
# Fase 3: validación activa de conservación de transporte.
# Comprueba que _transfer_hot_gas_contaminants() no creó ni destruyó
# masa de CO₂/HCN/CO/smoke — los residuales deben ser ~0 (FP-only).
# Llamar desde SimulationEngine después de thermal_system.step().
# ------------------------------------------------------------------

## Verifica conservación de masa en el transporte de contaminantes por gas caliente.
## `transport_residuals` es el dict devuelto por ThermalSystem.get_transport_residuals().
## Retorna {} si phase < 3. Acumula conservation_max_violation_frac y
## conservation_violation_count a lo largo de toda la simulación.
func validate_conservation(
	building: BuildingModel,
	transport_residuals: Dictionary,
	dt: float
) -> Dictionary:
	if zone_solver_phase < 3 or building == null:
		return {}

	# Masa de referencia: total de cada especie en el edificio al final del paso.
	var total_co2_kg: float = 0.0
	var total_hcn_kg: float = 0.0
	var total_co_kg: float = 0.0
	var total_smoke_kg: float = 0.0
	for room_id in building.get_rooms().keys():
		var room: RoomModel = building.get_room(room_id)
		if room == null:
			continue
		total_co2_kg += maxf(0.0, room.co2_kg)
		total_hcn_kg += maxf(0.0, room.hcn_kg)
		total_co_kg  += maxf(0.0, room.co_kg)
		total_smoke_kg += maxf(0.0, room.smoke_kg)

	var co2_res_kg: float   = float(transport_residuals.get("co2_residual_kg",   0.0))
	var hcn_res_kg: float   = float(transport_residuals.get("hcn_residual_kg",   0.0))
	var co_res_kg: float    = float(transport_residuals.get("co_residual_kg",    0.0))
	var smoke_res_kg: float = float(transport_residuals.get("smoke_residual_kg", 0.0))
	var calls: int          = int(transport_residuals.get("call_count", 0))

	# Violación relativa: residual / masa total de esa especie en el edificio.
	var co2_viol: float   = co2_res_kg   / maxf(total_co2_kg,   1e-9)
	var hcn_viol: float   = hcn_res_kg   / maxf(total_hcn_kg,   1e-9)
	var co_viol: float    = co_res_kg    / maxf(total_co_kg,    1e-9)
	var smoke_viol: float = smoke_res_kg / maxf(total_smoke_kg, 1e-9)
	var max_viol: float   = maxf(co2_viol, maxf(hcn_viol, maxf(co_viol, smoke_viol)))

	# Actualizar acumulador de peor violación.
	if max_viol > conservation_max_violation_frac:
		conservation_max_violation_frac = max_viol

	var has_violation: bool = max_viol > conservation_violation_threshold
	if has_violation:
		conservation_violation_count += 1
		push_warning(
			"ZoneFireSolver [Phase 3] conservación violada dt=%.2f calls=%d: "
			+ "co2=%.2e hcn=%.2e co=%.2e smoke=%.2e (max_frac=%.2e > thresh=%.2e)" % [
				dt, calls,
				co2_res_kg, hcn_res_kg, co_res_kg, smoke_res_kg,
				max_viol, conservation_violation_threshold
			]
		)

	return {
		"dt": dt,
		"call_count": calls,
		"co2_residual_kg":   co2_res_kg,
		"hcn_residual_kg":   hcn_res_kg,
		"co_residual_kg":    co_res_kg,
		"smoke_residual_kg": smoke_res_kg,
		"co2_violation_frac":   co2_viol,
		"hcn_violation_frac":   hcn_viol,
		"co_violation_frac":    co_viol,
		"smoke_violation_frac": smoke_viol,
		"max_violation_frac":               max_viol,
		"has_violation":                    has_violation,
		"conservation_max_violation_frac":  conservation_max_violation_frac,
		"conservation_violation_count":     conservation_violation_count,
	}

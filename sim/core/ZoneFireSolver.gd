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
#     - Fase 4: Delta-accumulation simultáneo en lugar de aplicación
#       secuencial (eliminación de efectos de ordering).
# ============================================================

## Habilita la coordinación de flujos ZoneFireSolver (fase 3+).
## 1 = skeleton, 2 = CO₂/HCN upper transport activo, 3 = validate_conservation() activo.
var zone_solver_phase: int = 3

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

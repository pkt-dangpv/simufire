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
#   Fases futuras:
#     - Fase 2: GasExchangeSystem lee zone_resolved_upper_mass_kg
#       para reemplazar la fórmula de background con el flujo canónico.
#     - Fase 3: OxygenExchangeSystem usa mismo flujo canónico.
#     - Fase 4: Delta-accumulation simultáneo en lugar de aplicación
#       secuencial (eliminación de efectos de ordering).
# ============================================================

## Habilita la coordinación de flujos ZoneFireSolver (fase 2+).
## En fase 1 esta flag se ignora; el solver solo registra datos.
var zone_solver_phase: int = 1   # 1 = skeleton, 2+ = activo

## Fracción de carry convectivo para HCN (respecto al carry general).
## 0.0 = deshabilitado (defecto). Habilitar en fase 2 tras rebaseline.
## Física: HCN se produce en la capa caliente y debería viajar con el
## gas caliente convectivo (igual que CO). Valores razonables: 0.2-0.6.
var hot_gas_hcn_carry_fraction: float = 0.0

## Fracción de carry convectivo para irritantes (HCl, acroleína, HCHO).
## 0.0 = deshabilitado (defecto). Idéntica justificación física a HCN.
var hot_gas_irritant_carry_fraction: float = 0.0

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
# Fase 1: validación opcional de conservación (debug/CI).
# Computa el residuo de masa y energía tras un paso de simulación.
# En producción se deja en no-op; activar con zone_solver_phase >= 2.
# ------------------------------------------------------------------
func validate_conservation(
	building: BuildingModel,
	prev_total_upper_gas_kg: float,
	prev_total_upper_energy_kj: float,
	dt: float
) -> Dictionary:
	if zone_solver_phase < 2 or building == null:
		return {}

	var total_upper_gas_kg: float = 0.0
	var total_upper_energy_kj: float = 0.0
	for room_id in building.get_rooms().keys():
		var room: RoomModel = building.get_room(room_id)
		if room == null:
			continue
		total_upper_gas_kg += maxf(0.0, room.upper_gas_kg)
		total_upper_energy_kj += maxf(0.0, room.upper_energy_kj)

	return {
		"dt": dt,
		"upper_gas_delta_kg": total_upper_gas_kg - prev_total_upper_gas_kg,
		"upper_energy_delta_kj": total_upper_energy_kj - prev_total_upper_energy_kj,
		"total_upper_gas_kg": total_upper_gas_kg,
		"total_upper_energy_kj": total_upper_energy_kj,
	}

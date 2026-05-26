extends RefCounted
class_name OxygenExchangeSystem

# ============================================================
# OXYGEN EXCHANGE SYSTEM
# ------------------------------------------------------------
# Gestiona el transporte de O2 entre habitaciones y con el
# exterior:
# - Consumo de O2 por combustión (Regla de Thornton)
# - Infiltración ACH desde el exterior
# - Intercambio boyante por aperturas interiores (Kawagoe)
# - Intercambio directo por aperturas exteriores
# - Transporte retardado interior (pendientes en cola)
# ============================================================

var o2_nominal: float = 0.209
var ach_infiltration: float = 0.5
var interior_transport_enabled: bool = true
var interior_transport_speed_m_s: float = 0.20
var interior_transport_min_distance_m: float = 0.50
var interior_o2_transport_delay_multiplier: float = 1.0
var doorway_o2_exchange_coeff: float = 1.70
# SF-AUD-010: sync con ThermalSystem; cuando true usa bernoulli_lower_kg_s
# (aire fresco entrante por capa baja) para el intercambio de O2 activo.
var vent_bernoulli_enabled: bool = false
var doorway_o2_active_max_fraction_per_step: float = 0.08
var doorway_o2_background_exchange_kg_s_m2: float = 0.06
var doorway_o2_background_max_fraction_per_step: float = 0.015
var doorway_o2_background_pressure_ref_pa: float = 1.5
var doorway_o2_background_min_factor: float = 0.30
# Tasa de entrainment penacho: pluma usa room.o2 como fuente de reposicion de
# o2_upper. Equilibrio: o2_upper_eq = room.o2 - hrr*cr/(rate*upper_mass).
# Calibrado Fase 1.5 (0.025). Fase 2A: o2_lower desacoplado (near-ambient).
var o2_upper_plume_entr_rate: float = 0.025
# Fase 2B: rendimiento de CO₂ por MJ liberado para el tracker mol-fraction.
# Usado en la ecuación Δco2_upper = (hrr/1000) × co2_yield × o2_scale × 29/(44×upper_mass).
# Default: 0.0831 kg CO₂/MJ (mismo que co2_base_yield_kg_per_MJ en CombustionSystem).
var co2_yield_kg_per_MJ: float = 0.0831
# Phase 2H: O₂ lower-zone flow candidate (default OFF).
# Cuando ON: protege o2_lower en salas sin doorway interior, mezcla la zona baja
# cuando hay doorway interior abierto, y permite mezcla moderada tras apertura exterior.
var phase2h_o2_doorway_two_zone_enabled: bool = false
# Exp 2H.2: ajusta la reposición directa de o2_lower desde flujos interiores activos.
var phase2h_cold_room_lower_routing_enabled: bool = false
# Exp 2H.2: gain del boost de reabastecimiento de zona baja desde apertura exterior (0.0 = no-op).
var phase2h_lower_replenish_gain: float = 0.0
# Phase 2E Sub-C: CO₂ upper tracer boost en sala con fuego activo (default OFF = no-op).
# room.co2_upper es tracer calibrado (fracción molar), NO derivado de balance de masa co2_kg.
# Boost: delta_co2_boost = delta_co2_baseline × gain. gain=0.0 → comportamiento idéntico al baseline.
var phase2e_co2_subc_enabled: bool = false
var phase2e_co2_fire_upper_boost_gain: float = 0.0
# Phase 2E Sub-A: corrección de dilución/outflow de co2_upper por apertura exterior (default OFF = no-op).
# OFF: comportamiento original — mezcla proporcional con masa de sala completa.
# ON: reemplaza la dilución masiva por pérdida selectiva de capa alta proporcional a upper_outlet_height_m.
# gain=0.0 con flag ON → outflow nulo (removal_frac=0) → co2_upper sin cambio por la apertura.
var phase2e_co2_suba_enabled: bool = false
var phase2e_co2_upper_outflow_gain: float = 0.0
# Phase 2E Sub-B: fracción de intercambio CO₂ inter-room por flujo activo (default OFF = no-op).
# OFF: CO2_EXCHANGE_FRACTION constante = 0.25 (Fase 2B original).
# ON: usa phase2e_co2_exchange_fraction en lugar de la constante; sweep [0.03, 0.05, 0.08, 0.25].
# Mecanismo: reducir la fracción retiene más CO₂ en la sala fuego → cierra gap cfast_2r_r0_t480.
var phase2e_co2_subb_enabled: bool = false
var phase2e_co2_exchange_fraction: float = 0.25
# Phase 2E Sub-D: omite snap de co2_upper a valor-masa cuando bi-zona inválida y fuego activo.
# OFF: snap original (no-op exacto). ON: en sala con hrr_kw>0, capa delgada → rama producción.
var phase2e_co2_subd_enabled: bool = false
var _pending_o2_deliveries: Array[Dictionary] = []
var _reserved_transport_o2_delta_kg: Dictionary = {}


func configure(settings: Dictionary) -> void:
	o2_nominal = float(settings.get("o2_nominal", o2_nominal))
	ach_infiltration = float(settings.get("ach_infiltration", ach_infiltration))
	interior_transport_enabled = bool(settings.get("interior_transport_enabled", interior_transport_enabled))
	interior_transport_speed_m_s = float(settings.get("interior_transport_speed_m_s", interior_transport_speed_m_s))
	interior_transport_min_distance_m = float(settings.get("interior_transport_min_distance_m", interior_transport_min_distance_m))
	interior_o2_transport_delay_multiplier = float(
		settings.get("interior_o2_transport_delay_multiplier", interior_o2_transport_delay_multiplier)
	)
	doorway_o2_exchange_coeff = float(
		settings.get("doorway_o2_exchange_coeff", doorway_o2_exchange_coeff)
	)
	doorway_o2_active_max_fraction_per_step = float(
		settings.get(
			"doorway_o2_active_max_fraction_per_step",
			doorway_o2_active_max_fraction_per_step
		)
	)
	doorway_o2_background_exchange_kg_s_m2 = float(
		settings.get(
			"doorway_o2_background_exchange_kg_s_m2",
			doorway_o2_background_exchange_kg_s_m2
		)
	)
	doorway_o2_background_max_fraction_per_step = float(
		settings.get(
			"doorway_o2_background_max_fraction_per_step",
			doorway_o2_background_max_fraction_per_step
		)
	)
	doorway_o2_background_pressure_ref_pa = float(
		settings.get(
			"doorway_o2_background_pressure_ref_pa",
			doorway_o2_background_pressure_ref_pa
		)
	)
	doorway_o2_background_min_factor = float(
		settings.get(
			"doorway_o2_background_min_factor",
			doorway_o2_background_min_factor
		)
	)
	vent_bernoulli_enabled = bool(settings.get("vent_bernoulli_enabled", vent_bernoulli_enabled))
	o2_upper_plume_entr_rate = float(settings.get("o2_upper_plume_entr_rate", o2_upper_plume_entr_rate))
	co2_yield_kg_per_MJ = float(settings.get("co2_yield_kg_per_MJ", co2_yield_kg_per_MJ))
	phase2h_o2_doorway_two_zone_enabled = bool(
		settings.get("phase2h_o2_doorway_two_zone_enabled", phase2h_o2_doorway_two_zone_enabled)
	)
	phase2h_cold_room_lower_routing_enabled = bool(
		settings.get("phase2h_cold_room_lower_routing_enabled", phase2h_cold_room_lower_routing_enabled)
	)
	phase2h_lower_replenish_gain = float(
		settings.get("phase2h_lower_replenish_gain", phase2h_lower_replenish_gain)
	)
	phase2e_co2_subc_enabled = bool(
		settings.get("phase2e_co2_subc_enabled", phase2e_co2_subc_enabled)
	)
	phase2e_co2_fire_upper_boost_gain = float(
		settings.get("phase2e_co2_fire_upper_boost_gain", phase2e_co2_fire_upper_boost_gain)
	)
	phase2e_co2_suba_enabled = bool(
		settings.get("phase2e_co2_suba_enabled", phase2e_co2_suba_enabled)
	)
	phase2e_co2_upper_outflow_gain = float(
		settings.get("phase2e_co2_upper_outflow_gain", phase2e_co2_upper_outflow_gain)
	)
	phase2e_co2_subb_enabled = bool(
		settings.get("phase2e_co2_subb_enabled", phase2e_co2_subb_enabled)
	)
	phase2e_co2_exchange_fraction = float(
		settings.get("phase2e_co2_exchange_fraction", phase2e_co2_exchange_fraction)
	)
	phase2e_co2_subd_enabled = bool(
		settings.get("phase2e_co2_subd_enabled", phase2e_co2_subd_enabled)
	)


func reset() -> void:
	_pending_o2_deliveries.clear()
	_reserved_transport_o2_delta_kg.clear()


func step(building: BuildingModel, dt: float, hooks: Dictionary) -> void:
	if building == null:
		return

	var effective_hot_layer_callable: Callable = hooks.get(
		"effective_hot_layer_height_callable",
		Callable()
	)
	var build_interior_flow_callable: Callable = hooks.get(
		"build_interior_opening_flow_state_callable",
		Callable()
	)
	# Cache pre-computado en SimulationEngine: {op -> flow_state}. Tiene prioridad
	# sobre el callable; el callable se usa como fallback si la abertura no está en cache.
	var opening_flow_cache: Dictionary = hooks.get("opening_flow_cache", {})
	var outside_open_path_factor_callable: Callable = hooks.get(
		"outside_open_path_factor_callable",
		Callable()
	)
	var air_density_kg_m3: float = 1.2

	_release_pending_o2_deliveries(building, dt, air_density_kg_m3)

	for room_id in building.get_rooms().keys():
		var room: RoomModel = building.get_room(room_id)
		if room == null:
			continue

		var air_mass_kg: float = _compute_room_air_mass_kg(room, air_density_kg_m3)

		# ── room.o2: variable independiente (retrocompatibilidad con checks existentes) ─
		# La ruta de room.o2 es idéntica a la pre-Fase-2A para no romper los 299 checks.
		var o2_mass_kg: float = air_mass_kg * room.o2
		if room.hrr_kw > 0.0:
			var cr: float = room.fire.o2_consumption_kg_per_MJ if room.fire != null else 0.076
			var consumed: float = (room.hrr_kw / 1000.0) * cr * dt
			consumed = minf(consumed, o2_mass_kg * 0.05)
			o2_mass_kg = maxf(0.0, o2_mass_kg - consumed)
		var ach_o2_delta_kg: float = room.volume_m3() \
			* (ach_infiltration / 3600.0) \
			* air_density_kg_m3 \
			* (building.outside_o2 - room.o2) * dt
		o2_mass_kg += ach_o2_delta_kg
		room.o2 = clampf(o2_mass_kg / air_mass_kg, 0.0, o2_nominal)

		# ── Fase 2A: Two-zone O₂ tracking (o2_upper, o2_lower como estados) ──────────
		# room.o2 es la variable de retrocompatibilidad (ya actualizada arriba).
		# Fase 2A objetivo: o2_upper ≈ room.o2 (base retrocompatible, Phase 2B añadirá
		# la depleción diferencial por zona); o2_lower independiente, mantenida
		# cerca del ambiente por los flujos de entrada por la parte baja de las aberturas.
		# Evita el doble conteo: la combustión ya consumió de room.o2 arriba.
		var hot_h_upper: float = _call_room_float(effective_hot_layer_callable, room, room.thermal_layer_m)
		hot_h_upper = clampf(hot_h_upper, 0.0, room.height_m)
		var upper_frac: float = maxf(0.01, (room.height_m - hot_h_upper) / maxf(0.01, room.height_m))
		var lower_frac: float = 1.0 - upper_frac
		var upper_air_mass: float = air_mass_kg * upper_frac
		var lower_air_mass: float = maxf(0.001, air_mass_kg * lower_frac)

		if lower_frac < 0.15 or (lower_frac < 0.40 and room.o2 < 0.070):
			# Modelo bi-zona invalido: homogeniza ambas zonas a room.o2.
			room.o2_upper = room.o2
			# Phase 2H: cuando el flag ON está activo, no resetear o2_lower a room.o2
			# (permite que los boosts de HVAC/exterior-apertura acumulen). El floor
			# room.o2 se mantiene invariante. Con flag OFF: comportamiento idéntico al baseline.
			if phase2h_o2_doorway_two_zone_enabled:
				room.o2_lower = maxf(room.o2, room.o2_lower)
			else:
				room.o2_lower = room.o2
		elif room.hrr_kw > 0.0:
			# Fase 2A: o2_upper -> equilibrio calibrado (mismo que Fase 1.5).
			# Penacho usa room.o2 como fuente (equivalente al cap o2_lower=room.o2).
			var cr_upper: float = room.fire.o2_consumption_kg_per_MJ if room.fire != null else 0.076
			var upper_consumed: float = (room.hrr_kw / 1000.0) * cr_upper * dt
			upper_consumed = minf(upper_consumed, upper_air_mass * room.o2_upper * 0.20)
			room.o2_upper = clampf(
				(upper_air_mass * room.o2_upper - upper_consumed) / maxf(0.001, upper_air_mass),
				0.0, o2_nominal)
			var entr_frac: float = clampf(o2_upper_plume_entr_rate * dt, 0.0, 0.15)
			var delta_entr: float = entr_frac * maxf(0.0, room.o2 - room.o2_upper)
			room.o2_upper = clampf(room.o2_upper + delta_entr, 0.0, o2_nominal)
			# Fase 2A: o2_lower near-ambient, independiente de o2_upper.
			# Pluma la arrastra lentamente hacia el floor. ACH la repone.
			# Phase 2H Exp2H.1: floor room.o2 → room.o2_upper resultó en inversión
			# (o2_lower baja más, FED hipoxia sube +16%). Branch ON reverted a no-op.
			# Exp 2H.2 implementará boost de reabastecimiento de zona baja.
			var lower_entr_scale: float = 0.20
			if phase2h_o2_doorway_two_zone_enabled:
				var interior_open_factor: float = _estimate_room_interior_open_factor(building, room)
				if interior_open_factor <= 0.01:
					var outside_open_factor: float = _estimate_room_outside_open_factor(building, room)
					lower_entr_scale = 0.40 * outside_open_factor
				else:
					lower_entr_scale = lerpf(0.60, 1.40, interior_open_factor)
			var lower_entr: float = entr_frac * lower_entr_scale * maxf(0.0, room.o2_lower - room.o2)
			room.o2_lower = maxf(room.o2, room.o2_lower - lower_entr)
			var ach_lower_dt: float = (ach_infiltration / 3600.0) \
				* (building.outside_o2 - room.o2_lower) * dt
			room.o2_lower = clampf(room.o2_lower + ach_lower_dt, room.o2, o2_nominal)
		else:
			# Sin fuego: resync lento de zonas a room.o2 (difusion/mezcla)
			room.o2_lower = lerpf(room.o2_lower, room.o2, clampf(0.05 * dt, 0.0, 0.20))
			room.o2_upper = lerpf(room.o2_upper, room.o2, clampf(0.03 * dt, 0.0, 0.10))
		room.o2_upper = clampf(room.o2_upper, 0.0, o2_nominal)
		room.o2_lower = clampf(room.o2_lower, 0.0, o2_nominal)

		# ── Fase 2B: CO₂ upper-zone mol-fraction tracking ──────────────────────
		# Análogo a Fase 2A (o2_upper), pero para CO₂ producido por combustión.
		# Se usa room.co2_upper (fracción molar, 0–0.30) en lugar de co2_upper_kg
		# para evitar el error de densidad del gas caliente en compute_co2_upper_ppm.
		# Producción escala con o2_upper/o2_nominal:
		#   - vincula la tasa de CO₂ al O₂ de la zona alta correctamente calibrado
		#     (o2_upper ≈ CFAST ULO₂), compensando que room.hrr_kw usa room.o2.
		# Intercambio entre salas se hace en _exchange_room_o2_active_flow.
		const CO2_AMBIENT: float = 0.0004  # ~400 ppm CO₂ exterior
		const CO2_UPPER_MAX: float = 0.30  # cap al 30 % molar
		var _bi_zone_invalid: bool = lower_frac < 0.15 or (lower_frac < 0.40 and room.o2 < 0.070)
		# Phase 2E Sub-D: cuando bi-zona inválida y fuego activo, omite el snap → usa rama
		# producción. OFF (subd=false) → _snap = true siempre que _bi_zone_invalid → no-op exacto.
		var _subd_skip_snap: bool = phase2e_co2_subd_enabled and room.hrr_kw > 0.0 and _bi_zone_invalid
		if _bi_zone_invalid and not _subd_skip_snap:
			# Modelo bi-zona inválido: homogeniza con media de sala
			var room_co2_frac: float = room.co2_kg * 29.0 / maxf(0.001, air_mass_kg * 44.0)
			room.co2_upper = clampf(room_co2_frac, CO2_AMBIENT, CO2_UPPER_MAX)
		elif room.hrr_kw > 0.0:
			# CO₂ producido → zona superior (gas caliente)
			var cr_co2: float = co2_yield_kg_per_MJ
			var co2_produced: float = (room.hrr_kw / 1000.0) * cr_co2 * dt
			# Escalar por o2_upper para que la tasa de CO₂ refleje el O₂ disponible
			# en la zona alta (evita sobreestimación cuando room.hrr_kw > HRR_CFAST).
			var o2_scale: float = clampf(room.o2_upper / maxf(0.001, o2_nominal), 0.0, 1.0)
			co2_produced *= o2_scale
			# Δx_CO₂ = (kg CO₂ / M_CO₂) / (kg_aire / M_aire) = kg_CO₂ × 29 / (kg_aire × 44)
			var delta_co2: float = co2_produced * 29.0 / maxf(0.001, upper_air_mass * 44.0)
			room.co2_upper = room.co2_upper + delta_co2
			# Phase 2E Sub-C: boost adicional de producción CO₂ en zona alta.
			# room.co2_upper es tracer calibrado (fracción molar); el boost amplifica delta_co2.
			# gain=0.0 → rama inactiva, comportamiento idéntico al baseline (flag OFF = no-op).
			if phase2e_co2_subc_enabled and phase2e_co2_fire_upper_boost_gain > 0.0:
				var boost_increment: float = delta_co2 * phase2e_co2_fire_upper_boost_gain
				room.co2_upper = room.co2_upper + boost_increment
				# Diagnóstico no bloqueante: coherencia tracer vs masa CO₂ real.
				var co2_upper_equiv_kg: float = room.co2_upper * upper_air_mass * (44.0 / 29.0)
				if co2_upper_equiv_kg > room.co2_kg * 5.0 + 0.001:
					push_warning("Phase2E Sub-C: co2_upper_equiv_kg (%.4f) > co2_kg*5 (%.4f) room_%d" \
						% [co2_upper_equiv_kg, room.co2_kg * 5.0, room_id])
			# Infiltración ACH hacia CO₂ ambiente (muy pequeño; solo activo para sala sellada)
			var ach_co2_dt: float = (ach_infiltration / 3600.0) * (CO2_AMBIENT - room.co2_upper) * dt
			room.co2_upper = room.co2_upper + ach_co2_dt
		else:
			# Sin fuego: relajar lentamente hacia CO₂ ambiente (mezcla/difusión)
			room.co2_upper = lerpf(room.co2_upper, CO2_AMBIENT, clampf(0.05 * dt, 0.0, 0.20))
		room.co2_upper = clampf(room.co2_upper, CO2_AMBIENT, CO2_UPPER_MAX)

	var g_gravity: float = 9.8
	for op in building.get_openings():
		if op.open_fraction <= 0.0:
			continue

		var lintel_m: float = op.lintel_height_m()
		if op.a == BuildingModel.OUTSIDE_ID or op.b == BuildingModel.OUTSIDE_ID:
			_step_outside_opening_o2(
				building,
				dt,
				op,
				lintel_m,
				air_density_kg_m3,
				g_gravity,
				effective_hot_layer_callable
			)
			continue

		var room_a: RoomModel = building.get_room(op.a)
		var room_b: RoomModel = building.get_room(op.b)
		if room_a == null or room_b == null:
			continue

		_step_interior_opening_o2(
			building,
			dt,
			op,
			room_a,
			room_b,
			air_density_kg_m3,
			g_gravity,
			build_interior_flow_callable,
			outside_open_path_factor_callable,
			opening_flow_cache
		)


func _step_outside_opening_o2(
	building: BuildingModel,
	dt: float,
	op: OpeningModel,
	lintel_m: float,
	air_density_kg_m3: float,
	g_gravity: float,
	effective_hot_layer_callable: Callable
) -> void:
	var indoor_id: int = op.a if op.b == BuildingModel.OUTSIDE_ID else op.b
	var indoor: RoomModel = building.get_room(indoor_id)
	if indoor == null:
		return

	var effective_layer_m: float = _call_room_float(
		effective_hot_layer_callable,
		indoor,
		clampf(indoor.thermal_layer_m, 0.0, indoor.height_m)
	)
	var opening_bottom_m: float = op.sill_m
	var opening_top_m: float = lintel_m
	var available_inlet_height_m: float = clampf(
		minf(opening_top_m, effective_layer_m) - opening_bottom_m,
		0.0,
		op.height_m
	)
	var upper_outlet_height_m: float = clampf(
		opening_top_m - maxf(opening_bottom_m, effective_layer_m),
		0.0,
		op.height_m
	)
	var oxygen_deficit_factor: float = clampf(
		(o2_nominal - indoor.o2) / maxf(0.04, o2_nominal - 0.12),
		0.0,
		1.0
	)
	oxygen_deficit_factor *= oxygen_deficit_factor

	var baseline_inlet_height_m: float = minf(
		available_inlet_height_m,
		maxf(0.06, op.height_m * 0.08)
	)
	var lower_inlet_height_m: float = lerpf(
		baseline_inlet_height_m,
		available_inlet_height_m,
		oxygen_deficit_factor
	)

	# When the interface is very near the lintel, most of the opening is still
	# available for cool inflow. The previous model only used the tiny upper band,
	# so a "window open" behaved almost like a crack and the room never re-oxygenated.
	if lower_inlet_height_m <= 0.000001 and indoor.overpressure_pa > 0.2 and oxygen_deficit_factor > 0.35:
		lower_inlet_height_m = minf(op.height_m, maxf(0.10, op.height_m * 0.20))

	var inlet_area_m2: float = op.width_m * lower_inlet_height_m * op.open_fraction
	if inlet_area_m2 <= 0.0:
		return

	var t_out_k: float = building.outside_temp_c + 273.15
	var hot_reference_temp_c: float = lerpf(
		indoor.temp_lower_c,
		indoor.temp_upper_c,
		clampf(0.45 + 0.40 * (upper_outlet_height_m / maxf(0.05, op.height_m)), 0.45, 0.90)
	)
	var t_hot_k: float = hot_reference_temp_c + 273.15
	var delta_t_k: float = maxf(0.0, t_hot_k - t_out_k)
	if delta_t_k < 2.0:
		return

	var drive_height_m: float = maxf(
		0.10,
		maxf(upper_outlet_height_m, 0.08) + lower_inlet_height_m * (0.25 + 0.25 * oxygen_deficit_factor)
	)
	var buoyancy_dp_pa: float = air_density_kg_m3 * g_gravity * drive_height_m * maxf(
		0.0,
		1.0 - t_out_k / maxf(t_out_k, t_hot_k)
	)
	var pressure_dp_pa: float = maxf(0.0, indoor.overpressure_pa)
	var delta_p_pa: float = maxf(
		buoyancy_dp_pa,
		pressure_dp_pa * (0.20 + 0.55 * oxygen_deficit_factor)
	)
	if delta_p_pa <= 0.01:
		return

	var q_m3_s: float = 0.61 * inlet_area_m2 * sqrt(2.0 * delta_p_pa / maxf(0.05, air_density_kg_m3))
	var air_in_kg: float = q_m3_s * air_density_kg_m3 * dt
	var room_air_mass_kg: float = _compute_room_air_mass_kg(indoor, air_density_kg_m3)
	var max_exchange_fraction: float = lerpf(0.01, 0.12, oxygen_deficit_factor)
	air_in_kg = minf(air_in_kg, room_air_mass_kg * max_exchange_fraction)
	if air_in_kg <= 0.0:
		return

	indoor.o2 = clampf(
		(indoor.o2 * room_air_mass_kg + building.outside_o2 * air_in_kg) / (room_air_mass_kg + air_in_kg),
		0.0,
		o2_nominal
	)
	# Fase 2A: el aire fresco entra por la capa baja de la apertura exterior.
	# Reponer o2_lower directamente proporcional al flujo de entrada; la masa de
	# la zona baja es aproximadamente lower_frac * room_air_mass_kg.
	if air_in_kg > 0.0 and lower_inlet_height_m > 0.0:
		var lower_frac_ext: float = clampf(
			indoor.thermal_layer_m / maxf(0.01, indoor.height_m), 0.01, 0.99)
		var lower_mass_ext: float = maxf(0.001, room_air_mass_kg * lower_frac_ext)
		indoor.o2_lower = clampf(
			(indoor.o2_lower * lower_mass_ext + building.outside_o2 * air_in_kg) / (lower_mass_ext + air_in_kg),
			0.0, o2_nominal)
		# Phase 2H Exp 2H.2: boost adicional de reabastecimiento de zona baja desde apertura exterior.
		# Amplifica la fracción de inflow efectivo × (ambient − o2_lower) × gain.
		# Floor = indoor.o2 preserva invariante Phase 2E-A (o2_lower ≥ room.o2).
		if phase2h_o2_doorway_two_zone_enabled and phase2h_lower_replenish_gain > 0.0:
			var boost_frac: float = clampf(
				phase2h_lower_replenish_gain * air_in_kg / lower_mass_ext, 0.0, 0.50)
			indoor.o2_lower = clampf(
				indoor.o2_lower + boost_frac * (building.outside_o2 - indoor.o2_lower),
				indoor.o2, o2_nominal)
	# Fase 2B / Phase 2E Sub-A: actualización de co2_upper por apertura exterior.
	# Flag OFF (default): dilución proporcional con masa de sala completa (comportamiento original).
	# Flag ON: supresión de dilución por inflow exterior sobre co2_upper.
	# phase2e_co2_upper_outflow_gain = fracción de supresión:
	#   gain=0.0 → mismo que baseline (sin supresión, dilución completa)
	#   gain=0.5 → mitad del air_in efectivo mezcla con zona alta (dilución parcial)
	#   gain=1.0 → sin dilución de co2_upper (aire fresco va solo a zona baja)
	#   gain>1.0 → clampeado a 1.0 (sin dilución)
	# Física: en el modelo bi-zona, el aire fresco entra por la parte baja del hueco
	# y se dirige a la zona baja. La zona alta pierde gas por el hueco superior pero
	# su concentración de CO₂ no se diluye directamente por el inflow de aire fresco.
	if air_in_kg > 0.0:
		if phase2e_co2_suba_enabled:
			# Sub-A: fracción de air_in que efectivamente mezcla con zona alta = air_in × (1 − gain).
			var suppression: float = clampf(phase2e_co2_upper_outflow_gain, 0.0, 1.0)
			var effective_air_in: float = air_in_kg * (1.0 - suppression)
			if effective_air_in > 0.0:
				indoor.co2_upper = clampf(
					(indoor.co2_upper * room_air_mass_kg + 0.0004 * effective_air_in) / (room_air_mass_kg + effective_air_in),
					0.0, 0.30)
			# else: suppression=1.0 → co2_upper no cambia por el inflow exterior
		else:
			indoor.co2_upper = clampf(
				(indoor.co2_upper * room_air_mass_kg + 0.0004 * air_in_kg) / (room_air_mass_kg + air_in_kg),
				0.0, 0.30)
	indoor.overpressure_pa = maxf(0.0, indoor.overpressure_pa * (1.0 - minf(0.55, air_in_kg / room_air_mass_kg)))


func _step_interior_opening_o2(
	building: BuildingModel,
	dt: float,
	op: OpeningModel,
	room_a: RoomModel,
	room_b: RoomModel,
	air_density_kg_m3: float,
	g_gravity: float,
	build_interior_flow_callable: Callable,
	outside_open_path_factor_callable: Callable,
	opening_flow_cache: Dictionary = {}
) -> void:
	var base_area_eff_m2: float = maxf(0.0, op.width_m * op.height_m * op.open_fraction)
	if base_area_eff_m2 > 0.0:
		var mass_a_base_kg: float = _compute_room_air_mass_kg(room_a, air_density_kg_m3)
		var mass_b_base_kg: float = _compute_room_air_mass_kg(room_b, air_density_kg_m3)
		var outside_open_factor: float = maxf(
			_estimate_room_outside_open_factor(building, room_a),
			_estimate_room_outside_open_factor(building, room_b)
		)
		outside_open_factor = maxf(
			outside_open_factor,
			maxf(
				_call_room_id_float(outside_open_path_factor_callable, room_a.id, 0.0),
				_call_room_id_float(outside_open_path_factor_callable, room_b.id, 0.0)
			)
		)
		var background_pressure_factor: float = maxf(
			doorway_o2_background_min_factor,
			maxf(
				clampf(
					maxf(room_a.overpressure_pa, room_b.overpressure_pa) / maxf(
						0.1,
						doorway_o2_background_pressure_ref_pa
					),
					0.0,
					1.0
				),
				clampf(outside_open_factor * 0.80, 0.0, 1.0)
			)
		)
		# Smoke-buoyancy boost: smoke present while fire is alive (not yet permanently
		# extinguished) creates a thermal gradient that increases background O2 exchange
		# through the doorway. Gated on fire object existence to avoid boosting exchange
		# from residual smoke after final extinction (which would interfere with
		# postfire smoke decay scenarios).
		if (room_a.fire != null) or (room_b.fire != null):
			var smoke_conc_o2: float = maxf(
				room_a.smoke_kg / maxf(0.1, room_a.volume_m3()),
				room_b.smoke_kg / maxf(0.1, room_b.volume_m3())
			)
			var smoke_drive_o2: float = clampf(smoke_conc_o2 / 0.050, 0.0, 1.0)
			background_pressure_factor = maxf(background_pressure_factor, smoke_drive_o2)
		var base_exchange_kg: float = base_area_eff_m2 \
			* doorway_o2_background_exchange_kg_s_m2 \
			* background_pressure_factor \
			* dt
		var base_max_exchange_kg: float = minf(mass_a_base_kg, mass_b_base_kg) \
			* lerpf(
				doorway_o2_background_max_fraction_per_step,
				0.045,
				clampf(outside_open_factor, 0.0, 1.0)
			)
		base_exchange_kg *= lerpf(1.0, 3.0, clampf(outside_open_factor, 0.0, 1.0))
		base_exchange_kg = minf(base_exchange_kg, base_max_exchange_kg)
		if base_exchange_kg > 0.0:
			_exchange_room_o2_immediate(room_a, room_b, base_exchange_kg, air_density_kg_m3)

	# Usar el cache pre-computado si está disponible; fallback al callable si no.
	var flow_state: Dictionary
	if opening_flow_cache.has(op):
		flow_state = opening_flow_cache[op]
	else:
		flow_state = _call_interior_flow_state(build_interior_flow_callable, room_a, room_b, op)
	if not bool(flow_state.get("active", false)):
		return

	var hot_room: RoomModel = flow_state.get("hot_room", null)
	var cold_room: RoomModel = flow_state.get("cold_room", null)
	if hot_room == null or cold_room == null:
		return

	var h_drive_m: float = float(flow_state.get("h_drive_m", 0.0))
	var area_eff_m2: float = float(flow_state.get("area_eff_m2", 0.0))
	var engagement: float = float(flow_state.get("engagement", 0.0))
	if h_drive_m <= 0.0 or area_eff_m2 <= 0.0 or engagement <= 0.0:
		return

	var source_temp_c: float = float(flow_state.get("source_temp_c", hot_room.temp_upper_c))
	var t_hot_k: float = source_temp_c + 273.15
	var t_cold_k: float = cold_room.temp_lower_c + 273.15
	var delta_t_k: float = float(flow_state.get("temp_delta_k", 0.0))
	var neutral_pf: float = float(flow_state.get("neutral_plane_f", 0.5))
	var exchange_kg: float
	if vent_bernoulli_enabled:
		# SF-AUD-010: caudal másico Bernoulli — capa baja entrante (aire fresco)
		# determina el O2 repuesto en la sala caliente.
		exchange_kg = float(flow_state.get("bernoulli_lower_kg_s", 0.0)) * dt
	else:
		var q_m3_s: float = 0.65 * neutral_pf * area_eff_m2 * sqrt(
				g_gravity * h_drive_m * delta_t_k / ((t_hot_k + t_cold_k) * 0.5)
		)
		exchange_kg = q_m3_s * air_density_kg_m3 * dt * doorway_o2_exchange_coeff * engagement
	var mass_hot_kg: float = _compute_room_air_mass_kg(hot_room, air_density_kg_m3)
	var mass_cold_kg: float = _compute_room_air_mass_kg(cold_room, air_density_kg_m3)
	var max_exchange_kg: float = minf(mass_hot_kg, mass_cold_kg) * doorway_o2_active_max_fraction_per_step
	exchange_kg = minf(exchange_kg, max_exchange_kg)
	if exchange_kg <= 0.0:
		return

	_exchange_room_o2_active_flow(building, hot_room, cold_room, exchange_kg, air_density_kg_m3)


func _exchange_room_o2_immediate(
	room_a: RoomModel,
	room_b: RoomModel,
	exchange_kg: float,
	air_density_kg_m3: float
) -> void:
	if room_a == null or room_b == null or exchange_kg <= 0.0:
		return

	var mass_a_kg: float = _compute_room_air_mass_kg(room_a, air_density_kg_m3)
	var mass_b_kg: float = _compute_room_air_mass_kg(room_b, air_density_kg_m3)
	var o2_a_out_kg: float = room_a.o2 * exchange_kg
	var o2_b_out_kg: float = room_b.o2 * exchange_kg

	room_a.o2 = clampf((room_a.o2 * mass_a_kg - o2_a_out_kg) / mass_a_kg, 0.0, o2_nominal)
	room_b.o2 = clampf((room_b.o2 * mass_b_kg - o2_b_out_kg) / mass_b_kg, 0.0, o2_nominal)

	_apply_room_o2_mass_delta(room_a, o2_b_out_kg, air_density_kg_m3)
	_apply_room_o2_mass_delta(room_b, o2_a_out_kg, air_density_kg_m3)
	# CO2 lo gestiona exclusivamente GasExchangeSystem._apply_background_species_exchange()
	# para evitar doble transporte por step.


func _exchange_room_o2_active_flow(
	building: BuildingModel,
	hot_room: RoomModel,
	cold_room: RoomModel,
	exchange_kg: float,
	air_density_kg_m3: float
) -> void:
	if building == null or hot_room == null or cold_room == null or exchange_kg <= 0.0:
		return

	var hot_o2_parcel_kg: float = _effective_room_o2_fraction(hot_room, air_density_kg_m3) * exchange_kg
	var cold_o2_parcel_kg: float = _effective_room_o2_fraction(cold_room, air_density_kg_m3) * exchange_kg
	var hot_room_delta_o2_kg: float = cold_o2_parcel_kg - hot_o2_parcel_kg
	var cold_room_delta_o2_kg: float = hot_o2_parcel_kg - cold_o2_parcel_kg

	# Keep the fresh compensating inflow to the fire room immediate, but delay
	# the downstream room's net concentration change until the hot parcel arrives.
	_apply_room_o2_mass_delta(hot_room, hot_room_delta_o2_kg, air_density_kg_m3)
	# Two-zone: aire fresco entra por la capa baja del cuarto caliente (flujo
	# Bernoulli/Kawagoe: frío abajo, caliente arriba). Repone o2_lower para
	# evitar el colapso por falta de reposición ante intercambio por abertura.
	if hot_room_delta_o2_kg > 0.0:
		var lower_frac_hr: float = clampf(
			hot_room.thermal_layer_m / maxf(0.01, hot_room.height_m), 0.01, 0.99)
		var lower_mass_hr: float = maxf(
			0.001, _compute_room_air_mass_kg(hot_room, air_density_kg_m3) * lower_frac_hr)
		var lower_replenish_scale: float = 1.0
		if phase2h_o2_doorway_two_zone_enabled and phase2h_cold_room_lower_routing_enabled:
			var outside_support: float = _estimate_room_outside_open_factor(building, hot_room)
			if outside_support <= 0.01:
				lower_replenish_scale = 0.0
		if lower_replenish_scale > 0.0:
			hot_room.o2_lower = clampf(
				hot_room.o2_lower + hot_room_delta_o2_kg * lower_replenish_scale / lower_mass_hr,
				0.0, o2_nominal)

	var hot_air_mass_kg: float = _compute_room_air_mass_kg(hot_room, air_density_kg_m3)
	var cold_air_mass_kg: float = _compute_room_air_mass_kg(cold_room, air_density_kg_m3)

	# Fase 2B: CO₂ upper-zone exchange via hot-gas active flow (interior doorway).
	# El gas caliente sale de la sala caliente (alta CO₂) y entra frío desde la fría (baja CO₂).
	# Tasa: 25 % del exchange_kg de O₂ activo (calibrado para quasi-steady ~10 % en caso 2 salas).
	# Este exchange es proporcional al flujo activo, NO al background; así no duplica
	# el transporte de GasExchangeSystem que opera sobre co2_kg (masa, no fracción molar).
	# Phase 2E Sub-B: fracción configurable. Flag OFF → 0.25 (Fase 2B original, no-op exacto).
	const CO2_EXCHANGE_FRACTION: float = 0.25
	var effective_co2_frac: float = phase2e_co2_exchange_fraction if phase2e_co2_subb_enabled \
									 else CO2_EXCHANGE_FRACTION
	var co2_ex_kg: float = exchange_kg * effective_co2_frac
	if co2_ex_kg > 0.0 and hot_air_mass_kg > 0.001 and cold_air_mass_kg > 0.001:
		var hot_co2_parcel: float = hot_room.co2_upper * co2_ex_kg / hot_air_mass_kg
		var cold_co2_parcel: float = cold_room.co2_upper * co2_ex_kg / cold_air_mass_kg
		var net_co2: float = hot_co2_parcel - cold_co2_parcel
		hot_room.co2_upper  = clampf(hot_room.co2_upper  - net_co2, 0.0, 0.30)
		cold_room.co2_upper = clampf(cold_room.co2_upper + net_co2, 0.0, 0.30)

	# CO2 kg lo gestiona exclusivamente GasExchangeSystem — no se duplica aquí.
	var delay_s: float = _estimate_interior_transport_delay_s(building, hot_room.id, cold_room.id)
	if interior_transport_enabled and delay_s > 0.000001:
		_reserve_room_o2_delta(cold_room.id, cold_room_delta_o2_kg)
		_pending_o2_deliveries.append({
			"target": cold_room.id,
			"delay_s": delay_s,
			"delta_o2_kg": cold_room_delta_o2_kg
		})
		return

	_apply_room_o2_mass_delta(cold_room, cold_room_delta_o2_kg, air_density_kg_m3)


func _release_pending_o2_deliveries(building: BuildingModel, dt: float, air_density_kg_m3: float) -> void:
	if building == null or _pending_o2_deliveries.is_empty():
		return

	var remaining: Array[Dictionary] = []
	for raw_entry in _pending_o2_deliveries:
		var entry: Dictionary = raw_entry
		entry["delay_s"] = maxf(0.0, float(entry.get("delay_s", 0.0)) - dt)
		if float(entry.get("delay_s", 0.0)) > 0.000001:
			remaining.append(entry)
			continue

		var target_id: int = int(entry.get("target", -1))
		var target: RoomModel = building.get_room(target_id)
		if target == null:
			continue
		var delta_o2_kg: float = float(entry.get("delta_o2_kg", 0.0))
		_apply_room_o2_mass_delta(target, delta_o2_kg, air_density_kg_m3)
		_reserve_room_o2_delta(target_id, -delta_o2_kg)

	_pending_o2_deliveries = remaining


func _reserve_room_o2_delta(room_id: int, delta_o2_kg: float) -> void:
	if absf(delta_o2_kg) <= 0.000001:
		return

	var updated_delta_kg: float = float(_reserved_transport_o2_delta_kg.get(room_id, 0.0)) + delta_o2_kg
	if absf(updated_delta_kg) <= 0.000001:
		_reserved_transport_o2_delta_kg.erase(room_id)
	else:
		_reserved_transport_o2_delta_kg[room_id] = updated_delta_kg


func _apply_room_o2_mass_delta(room: RoomModel, delta_o2_kg: float, air_density_kg_m3: float) -> void:
	if room == null or absf(delta_o2_kg) <= 0.000001:
		return

	var room_air_mass_kg: float = _compute_room_air_mass_kg(room, air_density_kg_m3)
	var room_o2_mass_kg: float = room.o2 * room_air_mass_kg + delta_o2_kg
	room.o2 = clampf(room_o2_mass_kg / room_air_mass_kg, 0.0, o2_nominal)


func _effective_room_o2_fraction(room: RoomModel, air_density_kg_m3: float) -> float:
	if room == null:
		return o2_nominal

	var room_air_mass_kg: float = _compute_room_air_mass_kg(room, air_density_kg_m3)
	var reserved_delta_kg: float = float(_reserved_transport_o2_delta_kg.get(room.id, 0.0))
	var effective_o2_mass_kg: float = clampf(
		room.o2 * room_air_mass_kg + reserved_delta_kg,
		0.0,
		room_air_mass_kg * o2_nominal
	)
	return effective_o2_mass_kg / room_air_mass_kg


func _estimate_interior_transport_delay_s(building: BuildingModel, room_a_id: int, room_b_id: int) -> float:
	if building == null or not interior_transport_enabled:
		return 0.0

	var distance_m: float = maxf(
		interior_transport_min_distance_m,
		building.estimate_room_connection_length_m(room_a_id, room_b_id)
	)
	return distance_m / maxf(0.05, interior_transport_speed_m_s) * maxf(0.1, interior_o2_transport_delay_multiplier)


func _compute_room_air_mass_kg(room: RoomModel, air_density_kg_m3: float) -> float:
	if room == null:
		return 0.1
	return maxf(0.1, room.volume_m3()) * air_density_kg_m3


func _estimate_room_outside_open_factor(building: BuildingModel, room: RoomModel) -> float:
	if building == null or room == null:
		return 0.0

	var total_open_area_m2: float = 0.0
	for op in building.get_openings():
		if op == null or op.open_fraction <= 0.0:
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

	var reference_area_m2: float = maxf(0.20, room.floor_area_m2() * 0.12)
	return clampf(total_open_area_m2 / reference_area_m2, 0.0, 1.0)


func _estimate_room_interior_open_factor(building: BuildingModel, room: RoomModel) -> float:
	if building == null or room == null:
		return 0.0

	var total_open_area_m2: float = 0.0
	for op in building.get_openings():
		if op == null or op.open_fraction <= 0.0 or op.is_exterior_opening():
			continue

		if op.a != room.id and op.b != room.id:
			continue

		total_open_area_m2 += op.width_m * op.height_m * op.open_fraction

	if total_open_area_m2 <= 0.0:
		return 0.0

	var reference_area_m2: float = maxf(0.20, room.floor_area_m2() * 0.12)
	return clampf(total_open_area_m2 / reference_area_m2, 0.0, 1.0)


func _call_room_id_float(callable: Callable, room_id: int, default_value: float) -> float:
	if not callable.is_valid():
		return default_value
	return float(callable.call(room_id))


func _call_room_float(callable: Callable, room: RoomModel, default_value: float) -> float:
	if not callable.is_valid():
		return default_value
	return float(callable.call(room))


func _call_interior_flow_state(
	callable: Callable,
	room_a: RoomModel,
	room_b: RoomModel,
	op: OpeningModel
) -> Dictionary:
	if not callable.is_valid():
		return {}

	var result: Variant = callable.call(room_a, room_b, op)
	return result if result is Dictionary else {}

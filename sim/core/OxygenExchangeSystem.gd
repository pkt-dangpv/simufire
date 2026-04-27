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
var doorway_o2_background_exchange_kg_s_m2: float = 0.06
var doorway_o2_background_max_fraction_per_step: float = 0.015
var doorway_o2_background_pressure_ref_pa: float = 1.5
var doorway_o2_background_min_factor: float = 0.30
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
		var o2_mass_kg: float = air_mass_kg * room.o2

		if room.hrr_kw > 0.0:
			var consumption_rate: float = room.fire.o2_consumption_kg_per_MJ if room.fire != null else 0.076
			var consumed_kg: float = (room.hrr_kw / 1000.0) * consumption_rate * dt
			consumed_kg = minf(consumed_kg, o2_mass_kg * 0.05)
			o2_mass_kg = maxf(0.0, o2_mass_kg - consumed_kg)

		var ach_o2_delta_kg: float = room.volume_m3() * (ach_infiltration / 3600.0) * air_density_kg_m3 \
			* (building.outside_o2 - room.o2) * dt
		o2_mass_kg += ach_o2_delta_kg
		room.o2 = clampf(o2_mass_kg / air_mass_kg, 0.0, o2_nominal)

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
			outside_open_path_factor_callable
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
	outside_open_path_factor_callable: Callable
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

	var flow_state: Dictionary = _call_interior_flow_state(
		build_interior_flow_callable,
		room_a,
		room_b,
		op
	)
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
	var q_m3_s: float = 0.65 * 0.5 * area_eff_m2 * sqrt(
		g_gravity * h_drive_m * delta_t_k / ((t_hot_k + t_cold_k) * 0.5)
	)
	var exchange_kg: float = q_m3_s * air_density_kg_m3 * dt * doorway_o2_exchange_coeff * engagement
	var mass_hot_kg: float = _compute_room_air_mass_kg(hot_room, air_density_kg_m3)
	var mass_cold_kg: float = _compute_room_air_mass_kg(cold_room, air_density_kg_m3)
	var max_exchange_kg: float = minf(mass_hot_kg, mass_cold_kg) * 0.08
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

	# CO2 (gas de combustión) se mezcla bidireccional con el intercambio de aire.
	# El CO permanece ligado al transporte de humo (GasExchangeSystem) para preservar
	# la calibración de timing; CO2 sí difunde libremente como gas de combustión.
	var co2_conc_a: float = room_a.co2_kg / maxf(0.1, mass_a_kg)
	var co2_conc_b: float = room_b.co2_kg / maxf(0.1, mass_b_kg)
	var net_co2_a_to_b: float = (co2_conc_a - co2_conc_b) * exchange_kg
	room_a.co2_kg = maxf(0.0, room_a.co2_kg - net_co2_a_to_b)
	room_b.co2_kg = maxf(0.0, room_b.co2_kg + net_co2_a_to_b)


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

	var hot_air_mass_kg: float = _compute_room_air_mass_kg(hot_room, air_density_kg_m3)
	var cold_air_mass_kg: float = _compute_room_air_mass_kg(cold_room, air_density_kg_m3)

	# CO y CO2 se transportan con el flujo boyante (dirección dominante: caliente→frío)
	# El CO2 (gas de combustión) sigue el flujo boyante; el CO permanece ligado al
	# transporte de humo (GasExchangeSystem) para preservar la calibración de timing.
	var hot_co2_conc: float = hot_room.co2_kg / maxf(0.1, hot_air_mass_kg)
	var cold_co2_conc: float = cold_room.co2_kg / maxf(0.1, cold_air_mass_kg)
	var net_co2_hot_to_cold: float = (hot_co2_conc - cold_co2_conc) * exchange_kg
	hot_room.co2_kg = maxf(0.0, hot_room.co2_kg - net_co2_hot_to_cold)
	cold_room.co2_kg = maxf(0.0, cold_room.co2_kg + net_co2_hot_to_cold)

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

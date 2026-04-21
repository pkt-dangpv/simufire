extends RefCounted
class_name SimulationStateBuilder


func build_state(context: Dictionary) -> Dictionary:
	var state: Dictionary = {
		"sim_time_s": float(context.get("sim_time_s", 0.0)),
		"smoke_generated_total_kg": float(context.get("smoke_generated_total_kg", 0.0)),
		"smoke_vented_total_kg": float(context.get("smoke_vented_total_kg", 0.0))
	}

	var building: BuildingModel = context.get("building")
	if building == null:
		return state

	var smoke_model: SmokeModel = context.get("smoke_model")
	var combustion_system: CombustionSystem = context.get("combustion_system")
	var estimate_temperature_callable: Callable = context.get("estimate_temperature_callable", Callable())
	var effective_hot_layer_callable: Callable = context.get("effective_hot_layer_callable", Callable())
	var compute_co_ppm_callable: Callable = context.get("compute_co_ppm_callable", Callable())
	var compute_co2_ppm_callable: Callable = context.get("compute_co2_ppm_callable", Callable())
	var is_quiescent_callable: Callable = context.get("is_quiescent_callable", Callable())
	var window_open_max_callable: Callable = context.get("window_open_max_callable", Callable())
	var kawagoe_factor_callable: Callable = context.get("kawagoe_factor_callable", Callable())
	var kawagoe_coeff: float = float(context.get("kawagoe_coeff", 0.0))

	for room_id in _collect_sorted_room_ids(building):
		var room: RoomModel = building.get_room(room_id)
		if room == null:
			continue

		var smoke_layer_m: float = smoke_model.get_visible_smoke_layer_height_m(room) if smoke_model != null else clampf(room.h_layer_m, 0.0, room.height_m)
		var effective_hot_layer_m: float = _call_room_float(effective_hot_layer_callable, room, clampf(room.thermal_layer_m, 0.0, room.height_m))
		var thermal_layer_m: float = clampf(room.thermal_layer_m, 0.0, room.height_m)
		var layer_150c_m: float = clampf(room.layer_150c_m, 0.0, room.height_m)
		var kawagoe_factor: float = _call_room_id_float(kawagoe_factor_callable, room_id, 0.0)

		state[str(room_id)] = {
			"id": room.id,
			"name": room.name,
			"kind": room.kind,
			"height_m": room.height_m,

			"hrr_kw": room.hrr_kw,
			"fire_time_s": room.fire_time_s,

			"temp_upper_c": room.temp_upper_c,
			"temp_lower_c": room.temp_lower_c,

			"o2": room.o2,

			"h_layer_m": room.h_layer_m,
			"thermal_layer_m": thermal_layer_m,
			"hot_layer_m": effective_hot_layer_m,
			"smoke_layer_m": smoke_layer_m,
			"layer_150c_m": layer_150c_m,
			"overpressure_pa": room.overpressure_pa,
			"smoke_kg": room.smoke_kg,
			"smoke_prod_kg_s": room.smoke_prod_kg_s,
			"upper_gas_kg": room.upper_gas_kg,
			"upper_energy_kj": room.upper_energy_kj,
			"temp_at_1_8m_c": _call_room_height_float(estimate_temperature_callable, room, 1.8, room.temp_lower_c),
			"temp_at_1_5m_c": _call_room_height_float(estimate_temperature_callable, room, 1.5, room.temp_lower_c),
			"temp_at_1_1m_c": _call_room_height_float(estimate_temperature_callable, room, 1.1, room.temp_lower_c),
			"temp_at_0_9m_c": _call_room_height_float(estimate_temperature_callable, room, 0.9, room.temp_lower_c),

			"has_fire": room.fire != null,
			"flashover_triggered": room.flashover_triggered,

			"fuel_energy_MJ": room.fuel_energy_MJ,
			"remaining_fuel_MJ": room.fire.remaining_fuel_MJ if room.fire != null else 0.0,
			"fuel_object_count": room.fuel_objects.size(),
			"fuel_objects_remaining_MJ": combustion_system.get_room_total_remaining_fuel_MJ(room) if combustion_system != null else 0.0,
			"fuel_objects_max_hrr_kw": combustion_system.get_room_total_max_hrr_kw(room) if combustion_system != null else 0.0,
			"fuel_objects_active_count": combustion_system.get_room_active_object_count(room) if combustion_system != null else 0,
			"co_ppm": _call_room_float(compute_co_ppm_callable, room, 0.0),
			"co2_ppm": _call_room_float(compute_co2_ppm_callable, room, 0.0),
			"fed": room.fed,
			"svv_pct": room.svv_pct,
			"svv_worst_pct": room.svv_worst_pct,
			"is_quiescent": _call_room_bool(is_quiescent_callable, room, false),

			"window_open_max": _call_room_id_float(window_open_max_callable, room_id, -1.0),
			"kawagoe_factor": kawagoe_factor,
			"kawagoe_hrr_max_kw": kawagoe_coeff * maxf(0.0, kawagoe_factor)
		}

	return state


func _collect_sorted_room_ids(building: BuildingModel) -> Array[int]:
	var room_ids: Array[int] = []
	if building == null:
		return room_ids

	for room_id in building.get_rooms().keys():
		room_ids.append(int(room_id))
	room_ids.sort()
	return room_ids


func _call_room_float(callable: Callable, room: RoomModel, default_value: float) -> float:
	if not callable.is_valid():
		return default_value
	return float(callable.call(room))


func _call_room_id_float(callable: Callable, room_id: int, default_value: float) -> float:
	if not callable.is_valid():
		return default_value
	return float(callable.call(room_id))


func _call_room_height_float(callable: Callable, room: RoomModel, height_m: float, default_value: float) -> float:
	if not callable.is_valid():
		return default_value
	return float(callable.call(room, height_m))


func _call_room_bool(callable: Callable, room: RoomModel, default_value: bool) -> bool:
	if not callable.is_valid():
		return default_value
	return bool(callable.call(room))

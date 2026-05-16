extends RefCounted
class_name SimulationStateBuilder

# ============================================================
# SIMULATION STATE BUILDER
# ------------------------------------------------------------
# Convierte el estado interno del engine en un Dictionary
# serializable usado por CaseRunner, el log writer y la UI.
# Centraliza la construcción del snapshot para evitar
# duplicación entre subsistemas.
# ============================================================


func build_state(context: Dictionary) -> Dictionary:
	var state: Dictionary = {
		"sim_time_s": float(context.get("sim_time_s", 0.0)),
		"smoke_generated_total_kg": float(context.get("smoke_generated_total_kg", 0.0)),
		"smoke_vented_total_kg": float(context.get("smoke_vented_total_kg", 0.0)),
		"smoke_deposited_total_kg": float(context.get("smoke_deposited_total_kg", 0.0)),
		"suppression_water_applied_l": float(context.get("suppression_water_applied_l", 0.0)),
		"suppression_cooling_total_kj": float(context.get("suppression_cooling_total_kj", 0.0))
	}
	var hvac: Dictionary = context.get("hvac", {})
	state["hvac_exists"] = bool(hvac.get("exists", false))
	state["hvac_on"] = bool(hvac.get("on", false))
	state["hvac_mode"] = String(hvac.get("mode", "none"))
	state["hvac_status"] = String(hvac.get("status", "Sin HVAC"))
	state["hvac_fan_flow_m3_s"] = float(hvac.get("fan_flow_m3_s", 0.0))
	state["hvac_off_passive_flow_m3_s"] = float(hvac.get("off_passive_flow_m3_s", 0.0))
	state["hvac_outside_air_fraction"] = float(hvac.get("outside_air_fraction", 0.0))

	var building: BuildingModel = context.get("building")
	if building == null:
		return state

	var smoke_model: SmokeModel = context.get("smoke_model")
	var combustion_system: CombustionSystem = context.get("combustion_system")
	var estimate_temperature_callable: Callable = context.get("estimate_temperature_callable", Callable())
	var effective_hot_layer_callable: Callable = context.get("effective_hot_layer_callable", Callable())
	var compute_co_ppm_callable: Callable = context.get("compute_co_ppm_callable", Callable())
	var compute_co_upper_ppm_callable: Callable = context.get("compute_co_upper_ppm_callable", Callable())
	var compute_co_lower_ppm_callable: Callable = context.get("compute_co_lower_ppm_callable", Callable())
	var compute_co2_ppm_callable: Callable = context.get("compute_co2_ppm_callable", Callable())
	var compute_hcn_ppm_callable: Callable = context.get("compute_hcn_ppm_callable", Callable())
	var compute_hcl_ppm_callable: Callable = context.get("compute_hcl_ppm_callable", Callable())
	var compute_acrolein_ppm_callable: Callable = context.get("compute_acrolein_ppm_callable", Callable())
	var compute_formaldehyde_ppm_callable: Callable = context.get("compute_formaldehyde_ppm_callable", Callable())
	var is_quiescent_callable: Callable = context.get("is_quiescent_callable", Callable())
	var window_open_max_callable: Callable = context.get("window_open_max_callable", Callable())
	var outside_open_path_factor_callable: Callable = context.get("outside_open_path_factor_callable", Callable())
	var kawagoe_factor_callable: Callable = context.get("kawagoe_factor_callable", Callable())
	var kawagoe_coeff: float = float(context.get("kawagoe_coeff", 0.0))
	var energy_budget: Dictionary = context.get("energy_budget", {})

	for room_id in _collect_sorted_room_ids(building):
		var room: RoomModel = building.get_room(room_id)
		if room == null:
			continue

		# smoke_layer_m: usa get_effective_smoke_spill_layer_height_m que ya unifica capa óptica y
		# capa térmica internamente (SmokeModel). Eliminado doble-bridge empírico del StateBuilder
		# (pesos 0.70/0.25m/0.30kg arbitrarios). Única fuente de verdad para visibilidad y SVV.
		var smoke_layer_m: float = smoke_model.get_effective_smoke_spill_layer_height_m(room) if smoke_model != null else clampf(room.h_layer_m, 0.0, room.height_m)
		var visible_smoke_layer_m: float = smoke_model.get_visible_smoke_layer_height_m(room) if smoke_model != null else smoke_layer_m
		var effective_hot_layer_m: float = _call_room_float(effective_hot_layer_callable, room, clampf(room.thermal_layer_m, 0.0, room.height_m))
		if room.smoke_kg >= 0.30:
			smoke_layer_m = minf(smoke_layer_m, effective_hot_layer_m + 0.68)
		# Capa visual basada solo en masa de hollín — sin influencia del gas caliente limpio.
		# Evita que upper_gas_kg sin humo real arrastre el plano neutro visual hacia abajo
		# (p.ej. pasillo que recibe gas caliente cuando se reabre una puerta tras ventilar).
		var smoke_display_layer_m: float = smoke_layer_m
		if smoke_model != null:
			smoke_display_layer_m = maxf(smoke_layer_m, smoke_model.estimate_smoke_layer_height_m(room))
		var thermal_layer_m: float = clampf(room.thermal_layer_m, 0.0, room.height_m)
		var layer_150c_m: float = clampf(room.layer_150c_m, 0.0, room.height_m)
		# Visibilidad acoplada al smoke_layer_m efectivo que se exporta al CSV
		# (única fuente de verdad). Evita el desacople histórico room.visibility_m vs smoke_layer_m.
		var visibility_m: float = room.visibility_m
		if smoke_model != null:
			visibility_m = smoke_model.estimate_visibility_for_layer_m(room, smoke_layer_m)
			room.visibility_m = visibility_m
		var kawagoe_factor: float = _call_room_id_float(kawagoe_factor_callable, room_id, 0.0)
		state[str(room_id)] = {
			"id": room.id,
			"name": room.name,
			"kind": room.kind,
			"height_m": room.height_m,

			"hrr_kw": room.hrr_kw,
			"hrr_target_kw": room.hrr_target_kw,
			"pyrolysis_kw": room.pyrolysis_kw,
			"burned_hrr_kw": room.burned_hrr_kw,
			"unburned_generation_kw": room.unburned_generation_kw,
			"flame_hrr_target_kw": room.flame_hrr_target_kw,
			"smolder_hrr_target_kw": room.smolder_hrr_target_kw,
			"pool_release_hrr_target_kw": room.pool_release_hrr_target_kw,
			"fire_time_s": room.fire_time_s,

			"temp_upper_c": room.temp_upper_c,
			"temp_upper_raw_c": room.temp_upper_raw_c,
			"temp_upper_clamped": room.temp_upper_clamped,
			"temp_upper_clamp_time_s": room.temp_upper_clamp_time_s,
			"temp_upper_clamp_count": room.temp_upper_clamp_count,
			"temp_lower_c": room.temp_lower_c,

			# Fracción de O2 corregida por dilución molar de CO2 (solo para reporte/CSV).
			# La física de combustión sigue usando room.o2 directamente.
			# En salas con fuego activo el O2 ya se consume por combustión — no aplicar
			# la dilución CO2 (sería double-counting). Solo corregir en salas frías.
			# Fórmula salas frías: x_O2_eff = room.o2 / (1 + co2_kg/air_kg * Mair/Mco2)
			"o2": room.o2 if room.hrr_kw > 0.0 else room.o2 / (1.0 + room.co2_kg / maxf(0.1, room.volume_m3() * 1.2) * (29.0 / 44.0)),

			"h_layer_m": room.h_layer_m,
			"thermal_layer_m": thermal_layer_m,
			"hot_layer_m": effective_hot_layer_m,
			"smoke_layer_m": smoke_layer_m,
			"smoke_display_layer_m": smoke_display_layer_m,
			"layer_150c_m": layer_150c_m,
			"overpressure_pa": room.overpressure_pa,
			"smoke_kg": room.smoke_kg,
			"visibility_m": visibility_m,
			"smoke_prod_kg_s": room.smoke_prod_kg_s,
			"soot_fraction": room.soot_fraction,
			"chi_rad_normal": room.chi_rad_normal,
			"wall_k_kw_m_k": room.wall_k_kw_m_k,
			"wall_rho_kg_m3": room.wall_rho_kg_m3,
			"wall_cp_kj_kg_k": room.wall_cp_kj_kg_k,
			"wall_thickness_m": room.wall_thickness_m,
			# SF-AUD-030: perfil 1D pared Crank-Nicolson
			"wall_T_mid_c": room.wall_T_mid_c,
			"wall_T_outer_c": room.wall_T_outer_c,
			"upper_gas_kg": room.upper_gas_kg,
			"upper_energy_kj": room.upper_energy_kj,
			"upper_radiative_loss_kw": room.upper_radiative_loss_kw,
			"temp_at_1_8m_c": _call_room_height_float(estimate_temperature_callable, room, 1.8, room.temp_lower_c),
			"temp_at_1_5m_c": _call_room_height_float(estimate_temperature_callable, room, 1.5, room.temp_lower_c),
			"temp_at_1_1m_c": _call_room_height_float(estimate_temperature_callable, room, 1.1, room.temp_lower_c),
			"temp_at_1_0m_c": _call_room_height_float(estimate_temperature_callable, room, 1.0, room.temp_lower_c),
			"temp_at_0_9m_c": _call_room_height_float(estimate_temperature_callable, room, 0.9, room.temp_lower_c),
			"temp_at_0_5m_c": _call_room_height_float(estimate_temperature_callable, room, 0.5, room.temp_lower_c),
			"temp_at_2_2m_c": _call_room_height_float(estimate_temperature_callable, room, 2.2, room.temp_lower_c),
			"temp_at_0_1m_c": _call_room_height_float(estimate_temperature_callable, room, 0.1, room.temp_lower_c),

			"has_fire": room.fire != null,
			"fire_smoldering": room.fire_smoldering,
			"backdraft_triggered": room.backdraft_triggered,
			"backdraft_time_s": room.backdraft_time_s,
			"backdraft_active": room.backdraft_active,
			"flashover_triggered": room.flashover_triggered,
			"flashover_time_s": room.flashover_time_s,
			"floor_heat_flux_kw_m2": room.floor_heat_flux_kw_m2,
			"flashover_q_thomas_kw": room.flashover_q_thomas_kw,
			"flashover_q_mqh_kw": room.flashover_q_mqh_kw,
			"unburned_gas_vol_frac": room.unburned_gas_vol_frac,
			"steam_kg": room.steam_kg,
			"fuel_energy_MJ": room.fuel_energy_MJ,
			"fuel_capacity_MJ": _resolve_fuel_capacity_MJ(room),
			"remaining_fuel_MJ": _resolve_remaining_fuel_MJ(room, combustion_system),
			"fuel_objects": _build_fuel_object_snapshots(room, combustion_system),
			"fuel_object_count": room.fuel_objects.size(),
			"fuel_objects_remaining_MJ": combustion_system.get_room_total_remaining_fuel_MJ(room) if combustion_system != null else 0.0,
			"fuel_objects_max_hrr_kw": combustion_system.get_room_total_max_hrr_kw(room) if combustion_system != null else 0.0,
			"fuel_objects_heating_count": combustion_system.get_room_heating_object_count(room) if combustion_system != null else 0,
			"fuel_objects_pyrolyzing_count": combustion_system.get_room_pyrolyzing_object_count(room) if combustion_system != null else 0,
			"fuel_objects_flaming_count": combustion_system.get_room_flaming_object_count(room) if combustion_system != null else 0,
			"fuel_objects_active_count": combustion_system.get_room_active_object_count(room) if combustion_system != null else 0,
			"passive_fuel_surface_temp_c": combustion_system.get_room_passive_surface_temp_c(room) if combustion_system != null else 0.0,
			"passive_fuel_flux_kw_m2": combustion_system.get_room_passive_flux_kw_m2(room) if combustion_system != null else 0.0,
			"passive_fuel_autoignite_ready": combustion_system.is_room_passive_autoignite_ready(room) if combustion_system != null else false,
			"dominant_fuel_object_id": combustion_system.get_room_dominant_fuel_object_id(room) if combustion_system != null else "",
			"dominant_fuel_object_name": combustion_system.get_room_dominant_fuel_object_name(room) if combustion_system != null else "",
			"dominant_fuel_object_state": combustion_system.get_room_dominant_fuel_object_state(room) if combustion_system != null else "none",
			"dominant_fuel_object_exposure_s": combustion_system.get_room_dominant_fuel_object_exposure_s(room) if combustion_system != null else 0.0,
			"dominant_fuel_object_remaining_MJ": combustion_system.get_room_dominant_fuel_object_remaining_MJ(room) if combustion_system != null else 0.0,
			"fire_spread_exposure_s": room.fire_spread_exposure_s,
			"o2_hrr_factor": room.o2_hrr_factor,
			"retained_unburned_MJ": room.retained_unburned_MJ,
			"unburned_fuel_MJ": room.retained_unburned_MJ,
			"ventilation_response_factor": room.ventilation_response_factor,
			"co_ppm": _call_room_float(compute_co_ppm_callable, room, 0.0),
			"co_upper_ppm": _call_room_float(compute_co_upper_ppm_callable, room, 0.0),
			"co_lower_ppm": _call_room_float(compute_co_lower_ppm_callable, room, 0.0),
			"co2_ppm": _call_room_float(compute_co2_ppm_callable, room, 0.0),
			"hcn_ppm": _call_room_float(compute_hcn_ppm_callable, room, 0.0),
			"hcl_ppm": _call_room_float(compute_hcl_ppm_callable, room, 0.0),
			"acrolein_ppm": _call_room_float(compute_acrolein_ppm_callable, room, 0.0),
			"formaldehyde_ppm": _call_room_float(compute_formaldehyde_ppm_callable, room, 0.0),
			"fec_irritant": room.fec_irritant,
			"fed": room.fed,
			"c_balance_frac": room.c_balance_frac,
			"svv_pct": room.svv_pct,
			"svv_worst_pct": room.svv_worst_pct,
			"is_quiescent": _call_room_bool(is_quiescent_callable, room, false),

			"window_open_max": _call_room_id_float(window_open_max_callable, room_id, -1.0),
			"outside_open_path_factor": _call_room_id_float(outside_open_path_factor_callable, room_id, 0.0),
			"kawagoe_factor": kawagoe_factor,
			"kawagoe_hrr_max_kw": kawagoe_coeff * maxf(0.0, kawagoe_factor),

			# Budget energético (solo cuando energy_budget_enabled=true en el engine)
			"bud_e_fire_kj": float(energy_budget.get(room_id, {}).get("e_fire_kj", 0.0)),
			"bud_q_rad_kj": float(energy_budget.get(room_id, {}).get("q_rad_kj", 0.0)),
			"bud_q_to_lower_kj": float(energy_budget.get(room_id, {}).get("q_to_lower_kj", 0.0)),
			"bud_q_to_ambient_kj": float(energy_budget.get(room_id, {}).get("q_to_ambient_kj", 0.0)),
			"bud_q_wall_abs_kj": float(energy_budget.get(room_id, {}).get("q_wall_abs_kj", 0.0)),
			"bud_q_wall_emit_kj": float(energy_budget.get(room_id, {}).get("q_wall_emit_kj", 0.0)),
			"bud_de_upper_kj": float(energy_budget.get(room_id, {}).get("de_upper_kj", 0.0)),
			"bud_q_residual_kj": float(energy_budget.get(room_id, {}).get("q_residual_kj", 0.0)),
			"bud_chi_rad": float(energy_budget.get(room_id, {}).get("chi_rad", 0.0)),
			"bud_q_fire_rad_kj": float(energy_budget.get(room_id, {}).get("q_fire_rad_kj", 0.0))
		}

	# Detectores: estado triggered de cada detector definido en el template.
	if building.detectors.size() > 0:
		var det_list: Array = []
		for det in building.detectors:
			det_list.append({
				"id": String(det.get("id", "")),
				"room_id": int(det.get("room_id", -1)),
				"type": String(det.get("type", "smoke")),
				"threshold": float(det.get("threshold", 0.0)),
				"triggered": bool(det.get("triggered", false)),
				"triggered_at_s": float(det.get("triggered_at_s", -1.0))
			})
		state["detectors"] = det_list

	return state


func _resolve_fuel_capacity_MJ(room: RoomModel) -> float:
	if room == null:
		return 0.0
	var total_MJ: float = 0.0
	var has_explicit: bool = _has_explicit_fuel_objects(room)
	for obj in room.fuel_objects:
		if obj == null:
			continue
		if has_explicit and String(obj.id).begins_with("room_proxy_"):
			continue
		total_MJ += maxf(0.0, obj.fuel_energy_MJ)
	if total_MJ > 0.0:
		return total_MJ
	return maxf(0.0, room.fuel_energy_MJ)


func _resolve_remaining_fuel_MJ(room: RoomModel, combustion_system: CombustionSystem) -> float:
	if room == null:
		return 0.0
	if room.fire != null:
		return maxf(0.0, room.fire.remaining_fuel_MJ)
	if combustion_system == null:
		return 0.0
	if room.fire_time_s > 0.0:
		return combustion_system.get_room_legacy_proxy_remaining_fuel_MJ(room)
	return combustion_system.get_room_total_remaining_fuel_MJ(room)


func _build_fuel_object_snapshots(room: RoomModel, combustion_system: CombustionSystem) -> Array[Dictionary]:
	var snapshots: Array[Dictionary] = []
	if room == null:
		return snapshots

	var has_explicit: bool = _has_explicit_fuel_objects(room)
	for obj in room.fuel_objects:
		if obj == null:
			continue
		if has_explicit and String(obj.id).begins_with("room_proxy_"):
			continue
		var state_name: String = "unknown"
		if combustion_system != null:
			state_name = combustion_system.fuel_object_state_to_string(int(obj.state))
		snapshots.append({
			"id": String(obj.id),
			"name": String(obj.name),
			"kind": String(obj.kind),
			"room_id": int(obj.room_id),
			"position_m": obj.position_m,
			"size_m": obj.size_m,
			"rotation_deg": float(obj.rotation_deg),
			"fuel_energy_MJ": maxf(0.0, obj.fuel_energy_MJ),
			"remaining_fuel_MJ": maxf(0.0, obj.remaining_fuel_MJ),
			"max_hrr_kw": maxf(0.0, obj.max_hrr_kw),
			"hrr_kw": maxf(0.0, obj.hrr_kw),
			"state": state_name,
			"surface_temp_c": float(obj.surface_temp_c),
			"incident_heat_flux_kw_m2": float(obj.incident_heat_flux_kw_m2),
			"is_primary_ignition_source": bool(obj.is_primary_ignition_source),
			"alpha_kw_s2": float(obj.alpha_kw_s2),
			"t_ignition_s": float(obj.t_ignition_s),
			"critical_heat_flux_kw_m2": float(obj.critical_heat_flux_kw_m2),
			"heat_of_gasification_kj_kg": float(obj.heat_of_gasification_kj_kg),
			"heat_of_combustion_kj_kg": float(obj.heat_of_combustion_kj_kg),
			"soot_fraction": float(obj.soot_fraction),
			"co2_yield_kg_per_MJ": float(obj.co2_yield_kg_per_MJ),
			"chi_rad_normal": float(obj.chi_rad_normal)
		})
	return snapshots


func _has_explicit_fuel_objects(room: RoomModel) -> bool:
	if room == null:
		return false
	for obj in room.fuel_objects:
		if obj != null and not String(obj.id).begins_with("room_proxy_"):
			return true
	return false


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

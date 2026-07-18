extends RefCounted
class_name SimulationLogWriter

# ============================================================
# SIMULATION LOG WRITER
# ------------------------------------------------------------
# Escribe el estado de la simulación en un fichero de texto
# plano a intervalos configurables.
# - Formato legible por humanos y por generate_fire_graphs.py
# - Solo escribe si el tiempo supera _next_log_time_s
# - Falla de forma silenciosa si el fichero no es accesible
# ============================================================

var enabled: bool = true
var interval_s: float = 10.0
var log_file_path: String = "user://sim_log.txt"

var csv_enabled: bool = true
var csv_file_path: String = "user://sim_log.csv"

## Ruta del CSV de targets (se deriva de csv_file_path automáticamente).
var target_csv_file_path: String = "user://sim_log_targets.csv"

## Phase 3+ F0: columnas two-zone adicionales. Default OFF conserva el schema legacy.
var phase3_zone_diagnostics_enabled: bool = false
var phase3_canonical_zone_shadow_enabled: bool = false
var phase3_canonical_exterior_boundary_shadow_enabled: bool = false
var phase3_canonical_persistence_shadow_enabled: bool = false
var phase3_canonical_combustion_shadow_enabled: bool = false
var phase3_canonical_pressure_relaxation_shadow_enabled: bool = false

var _next_log_time_s: float = 0.0
## Último timestamp escrito (append_snapshot o append_snapshot_now).
## Usado para evitar snapshots duplicados cuando _maybe_log_state y
## _force_log_final_snapshot coinciden en el mismo tick.
var _last_written_time_s: float = -INF
var _resolved_log_file_path: String = ""
var _log_io_failed: bool = false
var _resolved_csv_file_path: String = ""
var _csv_io_failed: bool = false
var _csv_header_written: bool = false
var _target_csv_io_failed: bool = false
var _target_csv_header_written: bool = false
var _runtime_log_stamp: String = ""
## Lista en memoria de todos los eventos registrados durante la simulación.
## Cada elemento: {"t": float, "type": String, "details": String}
var _events: Array = []


func configure(is_enabled: bool, interval_seconds: float, path: String) -> void:
	enabled = is_enabled
	interval_s = maxf(0.0, interval_seconds)
	log_file_path = path


func configure_csv(is_enabled: bool, path: String) -> void:
	csv_enabled = is_enabled
	csv_file_path = path
	# Derivar ruta del CSV de targets automáticamente
	if path.ends_with(".csv"):
		target_csv_file_path = path.substr(0, path.length() - 4) + "_targets.csv"
	else:
		target_csv_file_path = path + "_targets.csv"


func configure_phase3_zone_diagnostics(is_enabled: bool) -> void:
	phase3_zone_diagnostics_enabled = is_enabled


func configure_phase3_canonical_shadow(is_enabled: bool) -> void:
	phase3_canonical_zone_shadow_enabled = is_enabled


func configure_phase3_canonical_exterior_boundary_shadow(is_enabled: bool) -> void:
	phase3_canonical_exterior_boundary_shadow_enabled = is_enabled


func configure_phase3_canonical_persistence_shadow(is_enabled: bool) -> void:
	phase3_canonical_persistence_shadow_enabled = is_enabled


func configure_phase3_canonical_combustion_shadow(is_enabled: bool) -> void:
	phase3_canonical_combustion_shadow_enabled = is_enabled


func configure_phase3_canonical_pressure_relaxation_shadow(is_enabled: bool) -> void:
	phase3_canonical_pressure_relaxation_shadow_enabled = is_enabled


func reset_log_file() -> void:
	_next_log_time_s = 0.0
	_last_written_time_s = -INF
	_resolved_log_file_path = ""
	_log_io_failed = false
	_resolved_csv_file_path = ""
	_csv_io_failed = false
	_csv_header_written = false
	_target_csv_io_failed = false
	_target_csv_header_written = false
	_runtime_log_stamp = ""

	_events.clear()

	if not enabled:
		return

	var file := _open_log_file(FileAccess.WRITE)
	if file == null:
		return

	file.store_line("SIMULATION LOG")
	file.store_line("")
	file.close()

	if csv_enabled:
		var csv_file := _open_csv_file(FileAccess.WRITE)
		if csv_file != null:
			csv_file.store_line(_build_csv_header())
			csv_file.close()
			_csv_header_written = true


func resolve_log_file_path() -> String:
	if not _resolved_log_file_path.is_empty():
		return _resolved_log_file_path

	var candidates: Array[String] = _get_log_file_candidates()
	return candidates[0] if not candidates.is_empty() else log_file_path


func resolve_csv_file_path() -> String:
	if not _resolved_csv_file_path.is_empty():
		return _resolved_csv_file_path

	var candidates: Array[String] = _get_csv_file_candidates()
	return candidates[0] if not candidates.is_empty() else _normalize_log_path(csv_file_path)


func should_log(sim_time_s: float) -> bool:
	return enabled and sim_time_s >= _next_log_time_s


func append_snapshot(sim_time_s: float, state: Dictionary) -> void:
	if not should_log(sim_time_s):
		return

	_append_snapshot(sim_time_s, state)
	if csv_enabled:
		_append_csv_snapshot(sim_time_s, state)
	_next_log_time_s += interval_s
	_last_written_time_s = sim_time_s


func append_snapshot_now(sim_time_s: float, state: Dictionary) -> void:
	if not enabled:
		return
	if is_equal_approx(sim_time_s, _last_written_time_s):
		return

	_append_snapshot(sim_time_s, state)
	if csv_enabled:
		_append_csv_snapshot(sim_time_s, state)
	_last_written_time_s = sim_time_s


func append_initial_snapshot(sim_time_s: float, state: Dictionary) -> void:
	append_snapshot_now(sim_time_s, state)
	if enabled and interval_s > 0.0:
		_next_log_time_s = maxf(_next_log_time_s, sim_time_s + interval_s)


## Escribe una línea de evento al log de forma inmediata (fuera del intervalo normal).
## Formato: EVENT t=600.0 type=door_open opening=2 room_a=1 room_b=-1 frac=1.00
## También almacena el evento en _events para exportación posterior a JSON.
func append_event(sim_time_s: float, event_type: String, details: String) -> void:
	if not enabled:
		return
	_events.append({"t": sim_time_s, "type": event_type, "details": details})
	var file := _open_log_file(FileAccess.READ_WRITE, true)
	if file == null:
		return
	file.seek_end()
	if details.is_empty():
		file.store_line("EVENT t=%.1f type=%s" % [sim_time_s, event_type])
	else:
		file.store_line("EVENT t=%.1f type=%s %s" % [sim_time_s, event_type, details])
	file.close()


## Escribe el listado de eventos en memoria a un fichero JSON estructurado.
## Cada entrada: {"t": float, "type": String, "details": {key: value, ...}}
## Devuelve true si el fichero se escribió correctamente.
func write_events_json(path: String) -> bool:
	var arr: Array = []
	for ev in _events:
		var entry: Dictionary = {
			"t": float(ev.get("t", 0.0)),
			"type": String(ev.get("type", ""))
		}
		var raw: String = String(ev.get("details", ""))
		if not raw.is_empty():
			entry["details"] = _parse_event_details(raw)
		arr.append(entry)
	var text: String = JSON.stringify(arr, "\t")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(text)
	f.close()
	return true


## Convierte una cadena de pares "key=value key2=value2" a Dictionary.
func _parse_event_details(details: String) -> Dictionary:
	var result: Dictionary = {}
	for part in details.split(" ", false):
		var idx: int = part.find("=")
		if idx > 0:
			result[part.substr(0, idx)] = part.substr(idx + 1)
	return result


func _normalize_log_path(path: String) -> String:
	if path.begins_with("user://") or path.begins_with("res://"):
		return ProjectSettings.globalize_path(path)
	return path


func _get_log_file_candidates() -> Array[String]:
	var candidates: Array[String] = []
	var primary_path: String = _normalize_log_path(log_file_path)
	candidates.append(primary_path)
	var fallback_path: String = _runtime_log_path("sim_log", "txt")
	if not candidates.has(fallback_path):
		candidates.append(fallback_path)

	return candidates


func _get_csv_file_candidates() -> Array[String]:
	var candidates: Array[String] = []
	var primary_path: String = _normalize_log_path(csv_file_path)
	candidates.append(primary_path)
	var fallback_path: String = _runtime_log_path("sim_log", "csv")
	if not candidates.has(fallback_path):
		candidates.append(fallback_path)

	return candidates


func _runtime_log_path(base_name: String, extension: String) -> String:
	if _runtime_log_stamp.is_empty():
		_runtime_log_stamp = str(int(Time.get_unix_time_from_system()))
	return ProjectSettings.globalize_path("res://.godot/runtime_logs/%s_%s.%s" % [base_name, _runtime_log_stamp, extension])


func _ensure_log_directory(resolved_path: String) -> bool:
	var dir_path: String = resolved_path.get_base_dir()
	if dir_path.is_empty():
		return true

	if DirAccess.open(dir_path) != null:
		return true

	return DirAccess.make_dir_recursive_absolute(dir_path) == OK


func _report_log_error_once(message: String) -> void:
	if _log_io_failed:
		return

	_log_io_failed = true
	push_error(message)


func _open_log_file(mode: FileAccess.ModeFlags, create_if_missing: bool = false) -> FileAccess:
	if _log_io_failed:
		return null

	var attempted_paths: Array[String] = []
	for resolved_path in _get_log_file_candidates():
		attempted_paths.append(resolved_path)
		if not _ensure_log_directory(resolved_path):
			continue

		var file := FileAccess.open(resolved_path, mode)
		if file != null:
			_resolved_log_file_path = resolved_path
			return file

		if create_if_missing:
			var create_file := FileAccess.open(resolved_path, FileAccess.WRITE)
			if create_file != null:
				create_file.close()
				file = FileAccess.open(resolved_path, mode)
				if file != null:
					_resolved_log_file_path = resolved_path
					return file

	_report_log_error_once(
		"No se pudo abrir log en ninguna ruta candidata: %s (err=%d)" % [
			", ".join(PackedStringArray(attempted_paths)),
			FileAccess.get_open_error()
		]
	)
	return null


func _append_snapshot(sim_time_s: float, state: Dictionary) -> void:
	var file := _open_log_file(FileAccess.READ_WRITE, true)
	if file == null:
		return

	file.seek_end()
	file.store_line("==================================================")
	file.store_line("TIME=%.1f s" % sim_time_s)

	for room_id in _collect_room_ids(state):
		var room_state: Dictionary = state.get(str(room_id), {})
		if room_state.is_empty():
			continue

		var fed_val: float = float(room_state.get("fed", 0.0))
		var svv_worst_pct_state: float = clampf(float(room_state.get("svv_worst_pct", -1.0)), 0.0, 100.0)
		var height_m: float = float(room_state.get("height_m", 2.4))
		var layer_150c: float = clampf(float(room_state.get("layer_150c_m", height_m)), 0.0, height_m)

		# Criterio térmico (isoterma 150°C) — diagrama SVV pág. 47
		var thermal_svv: float
		if layer_150c >= 1.8:
			thermal_svv = 1.0
		elif layer_150c >= 0.5:
			thermal_svv = 0.90 + 0.09 * (layer_150c - 0.5) / 1.3
		elif layer_150c > 0.10:
			thermal_svv = 0.05 + 0.85 * ((layer_150c - 0.10) / 0.40)
		else:
			thermal_svv = 0.0
		# Criterio FED (narcosis CO)
		var fed_svv: float
		if fed_val <= 0.1:
			fed_svv = 1.0 - 0.01 * (fed_val / 0.1)
		elif fed_val <= 0.3:
			fed_svv = 0.99 - 0.09 * ((fed_val - 0.1) / 0.2)
		elif fed_val < 1.0:
			var t_fed: float = (fed_val - 0.3) / 0.7
			fed_svv = 0.90 * pow(1.0 - t_fed, 1.5)
		else:
			fed_svv = 0.0
		var svv_pct: float = minf(thermal_svv, fed_svv) * 100.0
		if room_state.has("svv_worst_pct"):
			svv_pct = svv_worst_pct_state

		var svv_zone: String
		if svv_pct > 99.0:
			svv_zone = "ALTA"
		elif svv_pct >= 90.0:
			svv_zone = "MEDIA"
		elif svv_pct >= 5.0:
			svv_zone = "BAJA"
		else:
			svv_zone = "MINIMA"
		var room_name_val: String = str(room_state.get("name", ""))
		var room_label: String = str(room_state.get("id", room_id))
		if room_name_val != "":
			room_label = "%s(%s)" % [str(room_state.get("id", room_id)), room_name_val]
		var line := "ROOM %s | HRR=%.2f | Up=%.2f | Low=%.2f | Smoke=%.4f | Vis=%.1fm | SmokeLayer=%.2f | HotLayer=%.2f | L150=%.2f | P=%.2fPa | O2=%.4f | O2u=%.4f | O2l=%.4f | CO=%.0fppm | COu=%.0fppm | COl=%.0fppm | CO2=%.0fppm | CO2u=%.0fppm | HCN=%.1fppm | HCNu=%.1fppm | FED=%.3f(CO:%.4f HCN:%.4f O2:%.4f Q:%.4f) | SVV=%.0f%% [%s] | WallT=%.1f | MdotVent=%.4f" % [
			room_label,
			float(room_state.get("hrr_kw", 0.0)),
			float(room_state.get("temp_upper_c", 0.0)),
			float(room_state.get("temp_lower_c", 0.0)),
			float(room_state.get("smoke_kg", 0.0)),
			float(room_state.get("visibility_m", 30.0)),
			float(room_state.get("smoke_layer_m", 0.0)),
			float(room_state.get("hot_layer_m", 0.0)),
			float(room_state.get("layer_150c_m", 0.0)),
			float(room_state.get("overpressure_pa", 0.0)),
			float(room_state.get("o2", 0.0)),
			float(room_state.get("o2_upper", room_state.get("o2", 0.0))),
			float(room_state.get("o2_lower", room_state.get("o2", 0.0))),
			float(room_state.get("co_ppm", 0.0)),
			float(room_state.get("co_upper_ppm", 0.0)),
			float(room_state.get("co_lower_ppm", 0.0)),
			float(room_state.get("co2_ppm", 0.0)),
			float(room_state.get("co2_upper_ppm", 0.0)),
			float(room_state.get("hcn_ppm", 0.0)),
			float(room_state.get("hcn_upper_ppm", 0.0)),
			fed_val,
			float(room_state.get("fed_co", 0.0)),
			float(room_state.get("fed_hcn", 0.0)),
			float(room_state.get("fed_hypoxia", 0.0)),
			float(room_state.get("fed_heat", 0.0)),
			svv_pct,
			svv_zone,
			float(room_state.get("wall_T_mid_c", 20.0)),
			float(room_state.get("mdot_vent_kg_s", 0.0))
		]
		line += " | FuelH=%d | FuelP=%d | FuelT=%.0f | Flux=%.1f | Spread=%.1f" % [
			int(room_state.get("fuel_objects_heating_count", 0)),
			int(room_state.get("fuel_objects_pyrolyzing_count", 0)),
			float(room_state.get("passive_fuel_surface_temp_c", 0.0)),
			float(room_state.get("passive_fuel_flux_kw_m2", 0.0)),
			float(room_state.get("fire_spread_exposure_s", 0.0))
		]
		line += " | Obj=%s:%s | ObjExp=%.0f | ObjMJ=%.1f" % [
			String(room_state.get("dominant_fuel_object_id", "")),
			String(room_state.get("dominant_fuel_object_state", "none")),
			float(room_state.get("dominant_fuel_object_exposure_s", 0.0)),
			float(room_state.get("dominant_fuel_object_remaining_MJ", 0.0))
		]
		line += " | HRRt=%.1f | Pyro=%.1f | Burn=%.1f | UnburnGen=%.1f | O2f=%.2f | GasMJ=%.2f | VentR=%.2f" % [
			float(room_state.get("hrr_target_kw", 0.0)),
			float(room_state.get("pyrolysis_kw", 0.0)),
			float(room_state.get("burned_hrr_kw", room_state.get("hrr_kw", 0.0))),
			float(room_state.get("unburned_generation_kw", 0.0)),
			float(room_state.get("o2_hrr_factor", 0.0)),
			float(room_state.get("retained_unburned_MJ", 0.0)),
			float(room_state.get("ventilation_response_factor", 0.0))
		]
		line += " | RawUp=%.1f | Cap=%s | CapT=%.1f | Rad=%.1f" % [
			float(room_state.get("temp_upper_raw_c", room_state.get("temp_upper_c", 0.0))),
			"Y" if bool(room_state.get("temp_upper_clamped", false)) else "N",
			float(room_state.get("temp_upper_clamp_time_s", 0.0)),
			float(room_state.get("upper_radiative_loss_kw", 0.0))
		]
		file.store_line(line)

	file.store_line("")
	file.close()


func _collect_room_ids(state: Dictionary) -> Array[int]:
	var room_ids: Array[int] = []
	for key in state.keys():
		var key_str: String = String(key)
		if key_str.is_valid_int():
			room_ids.append(int(key_str))
	room_ids.sort()
	return room_ids


# ============================================================
# CSV
# ============================================================

func _build_csv_header() -> String:
	var header: String = "time_s,room_id,room_name,hrr_kw,temp_upper_c,temp_lower_c,temp_at_0_9m_c,smoke_kg,visibility_m,smoke_layer_m,visible_smoke_layer_m,thermal_layer_m,flow_interface_m,hot_layer_m,layer_150c_m,overpressure_pa,o2,o2_upper,o2_lower,fire_o2_mode_used,co_ppm,co_upper_ppm,co_lower_ppm,co2_ppm,co2_upper_ppm,co2_upper_ppm_mass,hcn_ppm,hcn_upper_ppm,hcl_ppm,acrolein_ppm,formaldehyde_ppm,fec_irritant,fed,fed_co,fed_hcn,fed_hypoxia,fed_heat,svv_worst_pct,flashover_triggered,flashover_time_s,floor_heat_flux_kw_m2,flashover_q_thomas_kw,flashover_q_mqh_kw,fuel_remaining_MJ,solid_fuel_remaining_MJ,ventilation_response_factor,pyrolysis_kw,burned_hrr_kw,unburned_generation_kw,retained_unburned_MJ,unburned_gas_vol_frac,steam_kg,flame_hrr_target_kw,smolder_hrr_target_kw,pool_release_hrr_target_kw,o2_hrr_factor,fire_smoldering,fire_latent_active,backdraft_triggered,backdraft_active,bud_e_fire_kj,bud_q_rad_kj,bud_q_to_lower_kj,bud_q_to_ambient_kj,bud_q_wall_abs_kj,bud_q_wall_emit_kj,bud_de_upper_kj,bud_q_residual_kj,bud_chi_rad,bud_q_fire_rad_kj,wall_T_mid_c,mdot_vent_kg_s,combustion_regime,c_balance_frac,carbon_conservation_error_kg,co_kg,co_generated_kg_step,co2_generated_kg_step,hcn_generated_kg_step,co_net_transport_kg_step,co_generated_kg_total,co_net_transport_kg_total,co_exterior_removed_kg_total,o2_consumed_kg_step,o2_consumed_kg_total,o2_consumed_kg_step_all,o2_consumed_kg_total_all,o2_consumed_bulk_kg_step,o2_consumed_bulk_kg_total,o2_consumed_fire_kg_step,o2_consumed_fire_kg_total,o2_exterior_net_kg_step,o2_exterior_net_kg_total,o2_net_transport_kg_step,o2_net_transport_kg_total,o2_zone_sync_kg_step,o2_zone_sync_kg_total,fuel_consumed_MJ_step,fuel_consumed_MJ_total,hrr_kj_total,smoke_generated_kg_step,smoke_generated_kg_total,smoke_vented_kg_step,smoke_vented_kg_total,smoke_deposited_kg_step,smoke_deposited_kg_total,smoke_net_transport_kg_step,smoke_net_transport_kg_total,smoke_generated_total_kg,smoke_vented_total_kg,smoke_deposited_total_kg,smoke_in_transit_kg,volume_m3,air_mass_kg,hvac_exists"
	if phase3_zone_diagnostics_enabled:
		header += ",upper_gas_kg,lower_gas_kg,upper_energy_kj,lower_energy_kj,upper_volume_m3_eos,lower_volume_m3_eos,volume_closure_error_m3,two_zone_boundary_mass_kg,two_zone_boundary_energy_kj,two_zone_boundary_mass_kg_step,two_zone_boundary_energy_kj_step,opening_upper_in_kg_step,opening_upper_out_kg_step,opening_lower_in_kg_step,opening_lower_out_kg_step,plume_entrained_kg_step,oxygen_exchange_mass_delta_kg_step,oxygen_exchange_energy_delta_kj_step,combustion_mass_delta_kg_step,combustion_energy_delta_kj_step,thermal_mass_delta_kg_step,thermal_energy_delta_kj_step,suppression_mass_delta_kg_step,suppression_energy_delta_kj_step,gas_exchange_mass_delta_kg_step,gas_exchange_energy_delta_kj_step,hvac_mass_delta_kg_step,hvac_energy_delta_kj_step,other_mass_delta_kg_step,other_energy_delta_kj_step,reconcile_mass_delta_kg_step,reconcile_energy_delta_kj_step,projection_clamp_mass_delta_kg_step,projection_clamp_energy_delta_kj_step,attribution_mass_residual_kg_step,attribution_energy_residual_kj_step,zone_doorway_upper_out_kg_total,zone_doorway_upper_in_kg_total,zone_parcel_upper_out_kg_total,zone_parcel_upper_in_kg_total,zone_upper_removed_kg_total,pressure_therm_pa,pressure_model_pa,pressure_effective_pa,pressure_buoyancy_pa,pressure_stack_pa,pressure_raw_vented_air_kg_total,pressure_capped_vented_air_kg_total"
	if phase3_canonical_zone_shadow_enabled:
		header += ",phase3_shadow_upper_gas_kg,phase3_shadow_lower_gas_kg,phase3_shadow_upper_energy_kj,phase3_shadow_lower_energy_kj,phase3_shadow_mass_residual_kg,phase3_shadow_energy_residual_kj,phase3_shadow_upper_mass_residual_kg,phase3_shadow_lower_mass_residual_kg,phase3_shadow_upper_energy_residual_kj,phase3_shadow_lower_energy_residual_kj,phase3_shadow_thermo_valid_flag,phase3_shadow_thermo_failure_code,phase3_shadow_thermo_temp_upper_c,phase3_shadow_thermo_temp_lower_c,phase3_shadow_thermo_pressure_abs_pa,phase3_shadow_thermo_pressure_gauge_pa,phase3_shadow_thermo_upper_volume_m3,phase3_shadow_thermo_lower_volume_m3,phase3_shadow_thermo_volume_closure_error_m3,phase3_shadow_thermo_interface_m,phase3_shadow_thermo_mass_invariance_residual_kg,phase3_shadow_thermo_energy_invariance_residual_kj,phase3_shadow_canonical_transaction_closure_flag,phase3_shadow_legacy_state_mass_divergence_kg,phase3_shadow_legacy_state_energy_divergence_kj,phase3_shadow_legacy_interface_divergence_m,phase3_shadow_legacy_pressure_divergence_pa,phase3_shadow_request_count,phase3_shadow_plume_mass_request_kg,phase3_shadow_combustion_energy_request_kj,phase3_shadow_combustion_o2_request_kg,phase3_shadow_combustion_o2_rejected_kg,phase3_shadow_combustion_co_request_kg,phase3_shadow_combustion_co2_request_kg,phase3_shadow_combustion_hcn_request_kg,phase3_shadow_combustion_species_rejected_kg,phase3_shadow_doorway_co_request_kg,phase3_shadow_doorway_co2_request_kg,phase3_shadow_doorway_hcn_request_kg,phase3_shadow_doorway_species_rejected_kg,phase3_shadow_background_co_kg_total,phase3_shadow_background_co2_kg_total,phase3_shadow_background_hcn_kg_total,phase3_shadow_counterflow_co_kg_total,phase3_shadow_counterflow_co2_kg_total,phase3_shadow_counterflow_hcn_kg_total,phase3_shadow_immediate_transfer_count,phase3_shadow_immediate_rejected_kg_total,phase3_shadow_immediate_co_residual_kg,phase3_shadow_immediate_co2_residual_kg,phase3_shadow_immediate_hcn_residual_kg,phase3_shadow_vertical_net_co_kg_total,phase3_shadow_vertical_net_co2_kg_total,phase3_shadow_vertical_net_hcn_kg_total,phase3_shadow_vertical_directed_co_kg_total,phase3_shadow_vertical_directed_co2_kg_total,phase3_shadow_vertical_directed_hcn_kg_total,phase3_shadow_vertical_transfer_count,phase3_shadow_vertical_rejected_kg_total,phase3_shadow_vertical_opposed_zone_direction_count,phase3_shadow_vertical_co_residual_kg,phase3_shadow_vertical_co2_residual_kg,phase3_shadow_vertical_hcn_residual_kg,phase3_shadow_thermal_co_kg_total,phase3_shadow_thermal_co2_kg_total,phase3_shadow_thermal_hcn_kg_total,phase3_shadow_thermal_source_upper_co_kg_total,phase3_shadow_thermal_source_upper_co2_kg_total,phase3_shadow_thermal_source_upper_hcn_kg_total,phase3_shadow_thermal_source_lower_co_kg_total,phase3_shadow_thermal_source_lower_co2_kg_total,phase3_shadow_thermal_source_lower_hcn_kg_total,phase3_shadow_thermal_destination_upper_co_kg_total,phase3_shadow_thermal_destination_upper_co2_kg_total,phase3_shadow_thermal_destination_upper_hcn_kg_total,phase3_shadow_thermal_destination_lower_co_kg_total,phase3_shadow_thermal_destination_lower_co2_kg_total,phase3_shadow_thermal_destination_lower_hcn_kg_total,phase3_shadow_thermal_applied_co_kg_total,phase3_shadow_thermal_applied_co2_kg_total,phase3_shadow_thermal_applied_hcn_kg_total,phase3_shadow_thermal_rejected_co_kg_total,phase3_shadow_thermal_rejected_co2_kg_total,phase3_shadow_thermal_rejected_hcn_kg_total,phase3_shadow_thermal_event_count,phase3_shadow_thermal_duplicate_event_count,phase3_shadow_thermal_co_residual_kg,phase3_shadow_thermal_co2_residual_kg,phase3_shadow_thermal_hcn_residual_kg,phase3_shadow_thermal_doorway_kg_total,phase3_shadow_thermal_outside_background_kg_total,phase3_shadow_thermal_interior_background_kg_total,phase3_shadow_thermal_interlayer_kg_total,phase3_shadow_purge_co_out_kg_total,phase3_shadow_purge_co2_out_kg_total,phase3_shadow_purge_hcn_out_kg_total,phase3_shadow_purge_upper_co_kg_total,phase3_shadow_purge_upper_co2_kg_total,phase3_shadow_purge_upper_hcn_kg_total,phase3_shadow_purge_lower_co_kg_total,phase3_shadow_purge_lower_co2_kg_total,phase3_shadow_purge_lower_hcn_kg_total,phase3_shadow_purge_applied_kg_total,phase3_shadow_purge_rejected_kg_total,phase3_shadow_purge_event_count,phase3_shadow_purge_duplicate_event_count,phase3_shadow_purge_co_residual_kg,phase3_shadow_purge_co2_residual_kg,phase3_shadow_purge_hcn_residual_kg,phase3_shadow_purge_pressure_kg_total,phase3_shadow_purge_smoke_vent_kg_total,phase3_shadow_purge_natural_vent_kg_total,phase3_shadow_purge_ach_kg_total,phase3_shadow_purge_outside_open_kg_total,phase3_shadow_purge_postfire_kg_total,phase3_shadow_purge_ppv_inlet_kg_total,phase3_shadow_purge_ppv_exhaust_kg_total,phase3_shadow_species_inflight_co_kg,phase3_shadow_species_inflight_co2_kg,phase3_shadow_species_inflight_hcn_kg,phase3_shadow_species_created_kg_total,phase3_shadow_species_delivered_kg_total,phase3_shadow_species_refunded_kg_total,phase3_shadow_species_cancelled_kg_total,phase3_shadow_species_active_parcel_count,phase3_shadow_species_orphan_delivery_count,phase3_shadow_species_duplicate_id_count,phase3_shadow_species_negative_balance_count,phase3_shadow_species_conservation_residual_kg,phase3_shadow_species_conservation_residual_co_kg,phase3_shadow_species_conservation_residual_co2_kg,phase3_shadow_species_conservation_residual_hcn_kg,phase3_shadow_species_transit_rejected_kg,phase3_shadow_parcel_atomic_inflight_gas_kg,phase3_shadow_parcel_atomic_inflight_energy_kj,phase3_shadow_parcel_atomic_inflight_o2_kg,phase3_shadow_parcel_atomic_inflight_species_kg,phase3_shadow_parcel_atomic_created_gas_kg_total,phase3_shadow_parcel_atomic_delivered_gas_kg_total,phase3_shadow_parcel_atomic_refunded_gas_kg_total,phase3_shadow_parcel_atomic_cancelled_gas_kg_total,phase3_shadow_parcel_atomic_created_energy_kj_total,phase3_shadow_parcel_atomic_delivered_energy_kj_total,phase3_shadow_parcel_atomic_refunded_energy_kj_total,phase3_shadow_parcel_atomic_cancelled_energy_kj_total,phase3_shadow_parcel_atomic_created_o2_kg_total,phase3_shadow_parcel_atomic_delivered_o2_kg_total,phase3_shadow_parcel_atomic_refunded_o2_kg_total,phase3_shadow_parcel_atomic_cancelled_o2_kg_total,phase3_shadow_parcel_atomic_mass_residual_kg,phase3_shadow_parcel_atomic_energy_residual_kj,phase3_shadow_parcel_atomic_o2_residual_kg,phase3_shadow_parcel_atomic_species_residual_kg,phase3_shadow_parcel_atomic_unfinalized_resolution_count,phase3_shadow_combustion_owned_mask,phase3_shadow_owned_cause_count,phase3_shadow_rejected_mass_kg,phase3_shadow_duplicate_owner_flag,phase3_shadow_zero_o2_flame_flag,phase3_shadow_needs_flux_owner_flag,phase3_shadow_semantic_claim_count,phase3_shadow_semantic_conflict_count,phase3_shadow_semantic_conflict_quantity_mask,phase3_shadow_semantic_conflict_mass_kg,phase3_shadow_semantic_conflict_energy_kj,phase3_shadow_semantic_conflict_o2_kg,phase3_shadow_semantic_conflict_species_kg,phase3_shadow_semantic_unknown_connection_count,phase3_shadow_thermal_semantic_suppressed_kg_total,phase3_shadow_semantic_accepted_claim_count,phase3_shadow_semantic_suppressed_claim_count,phase3_shadow_semantic_unresolved_claim_count,phase3_shadow_semantic_suppressed_quantity_mask,phase3_shadow_semantic_unresolved_quantity_mask,phase3_shadow_semantic_suppressed_species_kg,phase3_shadow_semantic_unresolved_mass_kg,phase3_shadow_semantic_unresolved_energy_kj,phase3_shadow_semantic_unresolved_o2_kg,phase3_shadow_semantic_unresolved_species_kg,phase3_shadow_semantic_unresolved_conflict_count,phase3_shadow_atomic_bundle_count,phase3_shadow_atomic_route_count,phase3_shadow_atomic_min_accepted_fraction,phase3_shadow_atomic_rejected_mass_kg,phase3_shadow_atomic_rejected_energy_kj,phase3_shadow_atomic_rejected_o2_kg,phase3_shadow_atomic_rejected_species_kg,phase3_shadow_atomic_duplicate_bundle_count,phase3_shadow_atomic_invalid_bundle_count,phase3_shadow_co_oxidation_co_sink_kg_step,phase3_shadow_co_oxidation_co2_source_kg_step,phase3_shadow_co_oxidation_carbon_residual_kg_step,phase3_shadow_co_oxidation_o2_sink_kg_step,phase3_shadow_co_oxidation_accepted_fraction,phase3_shadow_co_oxidation_accepted_co_sink_kg_step,phase3_shadow_co_oxidation_accepted_co2_source_kg_step,phase3_shadow_co_oxidation_accepted_o2_sink_kg_step,phase3_shadow_co_oxidation_o2_rejected_kg_step,phase3_shadow_co_oxidation_oxygen_residual_kg_step,phase3_shadow_co_oxidation_legacy_lower_co2_kg_step"
	if phase3_canonical_exterior_boundary_shadow_enabled:
		header += ",phase3_shadow_exterior_pressure_pre_pa,phase3_shadow_exterior_requested_gas_kg,phase3_shadow_exterior_requested_energy_kj,phase3_shadow_exterior_requested_o2_kg,phase3_shadow_exterior_requested_species_kg,phase3_shadow_exterior_accepted_gas_kg,phase3_shadow_exterior_accepted_energy_kj,phase3_shadow_exterior_accepted_o2_kg,phase3_shadow_exterior_accepted_species_kg,phase3_shadow_exterior_post_upper_o2_kg,phase3_shadow_exterior_post_lower_o2_kg,phase3_shadow_exterior_post_upper_o2_fraction,phase3_shadow_exterior_post_lower_o2_fraction,phase3_shadow_exterior_rejected_gas_kg,phase3_shadow_exterior_rejected_energy_kj,phase3_shadow_exterior_rejected_o2_kg,phase3_shadow_exterior_rejected_species_kg,phase3_shadow_exterior_direction,phase3_shadow_exterior_source_zone_code,phase3_shadow_exterior_event_count,phase3_shadow_exterior_legacy_pressure_suppressed_event_count,phase3_shadow_exterior_accepted_fraction,phase3_shadow_exterior_duplicate_owner_flag,phase3_shadow_exterior_mass_residual_kg,phase3_shadow_exterior_energy_residual_kj,phase3_shadow_exterior_o2_residual_kg,phase3_shadow_exterior_species_residual_kg"
	if phase3_canonical_persistence_shadow_enabled:
		header += ",phase3_shadow_persistent_step_index,phase3_shadow_persistent_seeded_from_legacy_flag,phase3_shadow_persistent_continuity_mass_residual_kg,phase3_shadow_persistent_continuity_energy_residual_kj,phase3_shadow_persistent_continuity_o2_residual_kg,phase3_shadow_persistent_continuity_species_residual_kg,phase3_shadow_persistent_pre_upper_o2_fraction,phase3_shadow_persistent_pre_lower_o2_fraction,phase3_shadow_persistent_post_upper_o2_fraction,phase3_shadow_persistent_post_lower_o2_fraction,phase3_shadow_persistent_combustion_o2_ref,phase3_shadow_persistent_legacy_combustion_o2_ref,phase3_shadow_persistent_combustion_o2_delta,phase3_shadow_persistent_combustion_zone_code,phase3_shadow_persistent_combustion_o2_requested_kg,phase3_shadow_persistent_combustion_o2_accepted_kg,phase3_shadow_persistent_combustion_o2_rejected_kg,phase3_shadow_persistent_combustion_o2_accepted_fraction,phase3_shadow_persistent_combustion_would_limit_flag,phase3_shadow_persistent_zone_collapse_count,phase3_shadow_persistent_zone_collapse_source_code,phase3_shadow_persistent_zone_collapse_mass_residual_kg,phase3_shadow_persistent_zone_collapse_energy_residual_kj,phase3_shadow_persistent_zone_collapse_o2_residual_kg,phase3_shadow_persistent_zone_collapse_species_residual_kg"
	if phase3_canonical_combustion_shadow_enabled:
		header += ",phase3_shadow_combustion_transaction_active_flag,phase3_shadow_combustion_canonical_o2_ref,phase3_shadow_combustion_o2_source_zone_code,phase3_shadow_combustion_extinction_o2_limit,phase3_shadow_combustion_canonical_o2_hrr_factor,phase3_shadow_combustion_legacy_o2_hrr_factor,phase3_shadow_combustion_legacy_hrr_kw,phase3_shadow_combustion_accepted_hrr_kw,phase3_shadow_combustion_decision_fraction,phase3_shadow_combustion_atomic_fraction,phase3_shadow_combustion_effective_fraction,phase3_shadow_combustion_requested_o2_kg,phase3_shadow_combustion_accepted_o2_kg,phase3_shadow_combustion_requested_fuel_MJ,phase3_shadow_combustion_accepted_fuel_MJ,phase3_shadow_combustion_requested_species_kg,phase3_shadow_combustion_accepted_species_kg,phase3_shadow_combustion_requested_convective_energy_kj,phase3_shadow_combustion_accepted_convective_energy_kj,phase3_shadow_combustion_requested_plume_mass_kg,phase3_shadow_combustion_accepted_plume_mass_kg,phase3_shadow_combustion_remaining_fuel_MJ,phase3_shadow_combustion_retained_unburned_MJ,phase3_shadow_combustion_zero_o2_flame_flag,phase3_shadow_combustion_o2_residual_kg,phase3_shadow_combustion_energy_residual_kj,phase3_shadow_combustion_species_residual_kg"
	if phase3_canonical_pressure_relaxation_shadow_enabled:
		header += ",phase3_shadow_exterior_relaxation_enabled_flag,phase3_shadow_exterior_raw_requested_gas_kg,phase3_shadow_exterior_raw_requested_energy_kj,phase3_shadow_exterior_pressure_equilibrium_fraction,phase3_shadow_exterior_pressure_full_delta_pa,phase3_shadow_exterior_pressure_limited_delta_pa,phase3_shadow_exterior_pressure_predicted_post_pa,phase3_shadow_exterior_pressure_crossing_prevented_flag,phase3_shadow_exterior_degenerate_lower_reseed_flag,phase3_shadow_exterior_degenerate_lower_reseed_mass_kg,phase3_shadow_exterior_lower_reseed_count_total,phase3_shadow_exterior_lower_reseed_mass_kg_total,phase3_shadow_exterior_lower_reseed_first_step_index"
	return header


func _open_csv_file(mode: FileAccess.ModeFlags) -> FileAccess:
	if _csv_io_failed:
		return null

	var attempted_paths: Array[String] = []
	for path in _get_csv_file_candidates():
		attempted_paths.append(path)
		if not _ensure_log_directory(path):
			continue
		var file := FileAccess.open(path, mode)
		if file != null:
			_resolved_csv_file_path = path
			return file
	_csv_io_failed = true
	push_error("SimulationLogWriter: no se pudo abrir CSV en ninguna ruta candidata: %s (err=%d)" % [
		", ".join(PackedStringArray(attempted_paths)),
		FileAccess.get_open_error()
	])
	return null


func _append_csv_snapshot(sim_time_s: float, state: Dictionary) -> void:
	var file := _open_csv_file(FileAccess.READ_WRITE)
	if file == null:
		return
	file.seek_end()

	for room_id in _collect_room_ids(state):
		var rs: Dictionary = state.get(str(room_id), {})
		if rs.is_empty():
			continue
		var fields: PackedStringArray = PackedStringArray()
		fields.append("%.1f" % sim_time_s)
		fields.append(str(room_id))
		fields.append(_csv_escape(str(rs.get("name", ""))))
		fields.append("%.2f" % float(rs.get("hrr_kw", 0.0)))
		fields.append("%.2f" % float(rs.get("temp_upper_c", 0.0)))
		fields.append("%.2f" % float(rs.get("temp_lower_c", 0.0)))
		fields.append("%.2f" % float(rs.get("temp_at_0_9m_c", rs.get("temp_lower_c", 0.0))))
		fields.append("%.4f" % float(rs.get("smoke_kg", 0.0)))
		fields.append("%.2f" % float(rs.get("visibility_m", 30.0)))
		fields.append("%.3f" % float(rs.get("smoke_layer_m", 0.0)))
		fields.append("%.3f" % float(rs.get("visible_smoke_layer_m", rs.get("smoke_layer_m", 0.0))))
		fields.append("%.3f" % float(rs.get("thermal_layer_m", 0.0)))
		fields.append("%.3f" % float(rs.get("flow_interface_m", rs.get("thermal_layer_m", 0.0))))
		fields.append("%.3f" % float(rs.get("hot_layer_m", 0.0)))
		fields.append("%.3f" % float(rs.get("layer_150c_m", 0.0)))
		fields.append("%.3f" % float(rs.get("overpressure_pa", 0.0)))
		fields.append("%.5f" % float(rs.get("o2", 0.0)))
		fields.append("%.5f" % float(rs.get("o2_upper", rs.get("o2", 0.0))))
		fields.append("%.5f" % float(rs.get("o2_lower", rs.get("o2", 0.0))))
		fields.append(str(rs.get("fire_o2_mode_used", "legacy")))
		fields.append("%.0f" % float(rs.get("co_ppm", 0.0)))
		fields.append("%.0f" % float(rs.get("co_upper_ppm", 0.0)))
		fields.append("%.0f" % float(rs.get("co_lower_ppm", 0.0)))
		fields.append("%.0f" % float(rs.get("co2_ppm", 0.0)))
		# SF-D2: CO2 upper-layer — tracer-derived y mass-derived en paralelo para D2-pre.
		fields.append("%.0f" % float(rs.get("co2_upper_ppm", 0.0)))
		fields.append("%.0f" % float(rs.get("co2_upper_ppm_mass", 0.0)))
		fields.append("%.2f" % float(rs.get("hcn_ppm", 0.0)))
		fields.append("%.2f" % float(rs.get("hcn_upper_ppm", 0.0)))
		fields.append("%.2f" % float(rs.get("hcl_ppm", 0.0)))
		fields.append("%.4f" % float(rs.get("acrolein_ppm", 0.0)))
		fields.append("%.4f" % float(rs.get("formaldehyde_ppm", 0.0)))
		fields.append("%.4f" % float(rs.get("fec_irritant", 0.0)))
		fields.append("%.4f" % float(rs.get("fed", 0.0)))
		fields.append("%.5f" % float(rs.get("fed_co", 0.0)))
		fields.append("%.5f" % float(rs.get("fed_hcn", 0.0)))
		fields.append("%.5f" % float(rs.get("fed_hypoxia", 0.0)))
		fields.append("%.5f" % float(rs.get("fed_heat", 0.0)))
		fields.append("%.1f" % float(rs.get("svv_worst_pct", 100.0)))
		fields.append("1" if bool(rs.get("flashover_triggered", false)) else "0")
		fields.append("%.1f" % float(rs.get("flashover_time_s", -1.0)))
		fields.append("%.3f" % float(rs.get("floor_heat_flux_kw_m2", 0.0)))
		fields.append("%.1f" % float(rs.get("flashover_q_thomas_kw", 0.0)))
		fields.append("%.1f" % float(rs.get("flashover_q_mqh_kw", 0.0)))
		fields.append("%.6f" % float(rs.get("fuel_objects_remaining_MJ", rs.get("remaining_fuel_MJ", 0.0))))
		fields.append("%.8f" % float(rs.get("solid_fuel_remaining_MJ", rs.get("remaining_fuel_MJ", 0.0))))
		fields.append("%.4f" % float(rs.get("ventilation_response_factor", 0.0)))
		fields.append("%.2f" % float(rs.get("pyrolysis_kw", 0.0)))
		fields.append("%.2f" % float(rs.get("burned_hrr_kw", rs.get("hrr_kw", 0.0))))
		fields.append("%.2f" % float(rs.get("unburned_generation_kw", 0.0)))
		fields.append("%.4f" % float(rs.get("retained_unburned_MJ", 0.0)))
		fields.append("%.5f" % float(rs.get("unburned_gas_vol_frac", 0.0)))
		fields.append("%.4f" % float(rs.get("steam_kg", 0.0)))
		fields.append("%.2f" % float(rs.get("flame_hrr_target_kw", 0.0)))
		fields.append("%.2f" % float(rs.get("smolder_hrr_target_kw", 0.0)))
		fields.append("%.2f" % float(rs.get("pool_release_hrr_target_kw", 0.0)))
		fields.append("%.4f" % float(rs.get("o2_hrr_factor", 0.0)))
		fields.append("1" if bool(rs.get("fire_smoldering", false)) else "0")
		fields.append("1" if bool(rs.get("fire_latent_active", false)) else "0")
		fields.append("1" if bool(rs.get("backdraft_triggered", false)) else "0")
		fields.append("1" if bool(rs.get("backdraft_active", false)) else "0")
		fields.append("%.4f" % float(rs.get("bud_e_fire_kj", 0.0)))
		fields.append("%.4f" % float(rs.get("bud_q_rad_kj", 0.0)))
		fields.append("%.4f" % float(rs.get("bud_q_to_lower_kj", 0.0)))
		fields.append("%.4f" % float(rs.get("bud_q_to_ambient_kj", 0.0)))
		fields.append("%.4f" % float(rs.get("bud_q_wall_abs_kj", 0.0)))
		fields.append("%.4f" % float(rs.get("bud_q_wall_emit_kj", 0.0)))
		fields.append("%.4f" % float(rs.get("bud_de_upper_kj", 0.0)))
		fields.append("%.4f" % float(rs.get("bud_q_residual_kj", 0.0)))
		fields.append("%.4f" % float(rs.get("bud_chi_rad", 0.0)))
		fields.append("%.4f" % float(rs.get("bud_q_fire_rad_kj", 0.0)))
		fields.append("%.2f" % float(rs.get("wall_T_mid_c", 20.0)))
		fields.append("%.4f" % float(rs.get("mdot_vent_kg_s", 0.0)))
		fields.append(str(rs.get("combustion_regime", "EXTINGUISHED")))
		fields.append("%.6f" % float(rs.get("c_balance_frac", 0.0)))
		fields.append("%.8f" % float(rs.get("carbon_conservation_error_kg", 0.0)))
		fields.append("%.8f" % float(rs.get("co_kg", 0.0)))
		fields.append("%.8f" % float(rs.get("co_generated_kg_step", 0.0)))
		fields.append("%.8f" % float(rs.get("co2_generated_kg_step", 0.0)))
		fields.append("%.8f" % float(rs.get("hcn_generated_kg_step", 0.0)))
		fields.append("%.8f" % float(rs.get("co_net_transport_kg_step", 0.0)))
		fields.append("%.8f" % float(rs.get("co_generated_kg_total", 0.0)))
		fields.append("%.8f" % float(rs.get("co_net_transport_kg_total", 0.0)))
		fields.append("%.8f" % float(rs.get("co_exterior_removed_kg_total", 0.0)))
		fields.append("%.8f" % float(rs.get("o2_consumed_kg_step", 0.0)))
		fields.append("%.8f" % float(rs.get("o2_consumed_kg_total", 0.0)))
		fields.append("%.8f" % float(rs.get("o2_consumed_kg_step_all", 0.0)))
		fields.append("%.8f" % float(rs.get("o2_consumed_kg_total_all", 0.0)))
		fields.append("%.8f" % float(rs.get("o2_consumed_bulk_kg_step", 0.0)))
		fields.append("%.8f" % float(rs.get("o2_consumed_bulk_kg_total", 0.0)))
		fields.append("%.8f" % float(rs.get("o2_consumed_fire_kg_step", 0.0)))
		fields.append("%.8f" % float(rs.get("o2_consumed_fire_kg_total", 0.0)))
		fields.append("%.8f" % float(rs.get("o2_exterior_net_kg_step", 0.0)))
		fields.append("%.8f" % float(rs.get("o2_exterior_net_kg_total", 0.0)))
		fields.append("%.8f" % float(rs.get("o2_net_transport_kg_step", 0.0)))
		fields.append("%.8f" % float(rs.get("o2_net_transport_kg_total", 0.0)))
		fields.append("%.8f" % float(rs.get("o2_zone_sync_kg_step", 0.0)))
		fields.append("%.8f" % float(rs.get("o2_zone_sync_kg_total", 0.0)))
		fields.append("%.8f" % float(rs.get("fuel_consumed_MJ_step", 0.0)))
		fields.append("%.8f" % float(rs.get("fuel_consumed_MJ_total", 0.0)))
		# SF-O2E1: energía HRR acumulada para auditoría de Thornton cruzada.
		fields.append("%.4f" % float(rs.get("hrr_kj_total", 0.0)))
		# SF-S1: acumuladores per-room de humo para balance local.
		fields.append("%.8f" % float(rs.get("smoke_generated_kg_step", 0.0)))
		fields.append("%.8f" % float(rs.get("smoke_generated_kg_total", 0.0)))
		fields.append("%.8f" % float(rs.get("smoke_vented_kg_step", 0.0)))
		fields.append("%.8f" % float(rs.get("smoke_vented_kg_total", 0.0)))
		fields.append("%.8f" % float(rs.get("smoke_deposited_kg_step", 0.0)))
		fields.append("%.8f" % float(rs.get("smoke_deposited_kg_total", 0.0)))
		fields.append("%.8f" % float(rs.get("smoke_net_transport_kg_step", 0.0)))
		fields.append("%.8f" % float(rs.get("smoke_net_transport_kg_total", 0.0)))
		# SF-S0: acumuladores globales de humo (mismo valor en todas las salas del mismo timestep).
		fields.append("%.8f" % float(state.get("smoke_generated_total_kg", 0.0)))
		fields.append("%.8f" % float(state.get("smoke_vented_total_kg", 0.0)))
		fields.append("%.8f" % float(state.get("smoke_deposited_total_kg", 0.0)))
		fields.append("%.8f" % float(state.get("smoke_in_transit_kg", 0.0)))
		fields.append("%.4f" % float(rs.get("volume_m3", 0.0)))
		fields.append("%.4f" % float(rs.get("air_mass_kg", 0.0)))
		# SF-O1F: HVAC configurado — O2 de suministro/retorno no está en los acumuladores O1.
		fields.append("1" if bool(state.get("hvac_exists", false)) else "0")
		if phase3_zone_diagnostics_enabled:
			for field_name in [
				"upper_gas_kg", "lower_gas_kg", "upper_energy_kj", "lower_energy_kj",
				"upper_volume_m3_eos", "lower_volume_m3_eos", "volume_closure_error_m3",
				"two_zone_boundary_mass_kg", "two_zone_boundary_energy_kj",
				"two_zone_boundary_mass_kg_step", "two_zone_boundary_energy_kj_step",
				"opening_upper_in_kg_step", "opening_upper_out_kg_step",
				"opening_lower_in_kg_step", "opening_lower_out_kg_step",
				"plume_entrained_kg_step", "oxygen_exchange_mass_delta_kg_step",
				"oxygen_exchange_energy_delta_kj_step", "combustion_mass_delta_kg_step",
				"combustion_energy_delta_kj_step", "thermal_mass_delta_kg_step",
				"thermal_energy_delta_kj_step", "suppression_mass_delta_kg_step",
				"suppression_energy_delta_kj_step", "gas_exchange_mass_delta_kg_step",
				"gas_exchange_energy_delta_kj_step", "hvac_mass_delta_kg_step",
				"hvac_energy_delta_kj_step", "other_mass_delta_kg_step",
				"other_energy_delta_kj_step", "reconcile_mass_delta_kg_step",
				"reconcile_energy_delta_kj_step", "projection_clamp_mass_delta_kg_step",
				"projection_clamp_energy_delta_kj_step", "attribution_mass_residual_kg_step",
				"attribution_energy_residual_kj_step",
				"zone_doorway_upper_out_kg_total", "zone_doorway_upper_in_kg_total",
				"zone_parcel_upper_out_kg_total", "zone_parcel_upper_in_kg_total",
				"zone_upper_removed_kg_total",
				"pressure_therm_pa", "pressure_model_pa", "pressure_effective_pa",
				"pressure_buoyancy_pa", "pressure_stack_pa",
				"pressure_raw_vented_air_kg_total", "pressure_capped_vented_air_kg_total"
			]:
				fields.append("%.8f" % float(rs.get(field_name, 0.0)))
		if phase3_canonical_zone_shadow_enabled:
			for field_name in [
				"phase3_shadow_upper_gas_kg", "phase3_shadow_lower_gas_kg",
				"phase3_shadow_upper_energy_kj", "phase3_shadow_lower_energy_kj",
				"phase3_shadow_mass_residual_kg", "phase3_shadow_energy_residual_kj",
				"phase3_shadow_upper_mass_residual_kg", "phase3_shadow_lower_mass_residual_kg",
				"phase3_shadow_upper_energy_residual_kj", "phase3_shadow_lower_energy_residual_kj",
				"phase3_shadow_thermo_valid_flag", "phase3_shadow_thermo_failure_code",
				"phase3_shadow_thermo_temp_upper_c", "phase3_shadow_thermo_temp_lower_c",
				"phase3_shadow_thermo_pressure_abs_pa", "phase3_shadow_thermo_pressure_gauge_pa",
				"phase3_shadow_thermo_upper_volume_m3", "phase3_shadow_thermo_lower_volume_m3",
				"phase3_shadow_thermo_volume_closure_error_m3",
				"phase3_shadow_thermo_interface_m",
				"phase3_shadow_thermo_mass_invariance_residual_kg",
				"phase3_shadow_thermo_energy_invariance_residual_kj",
				"phase3_shadow_canonical_transaction_closure_flag",
				"phase3_shadow_legacy_state_mass_divergence_kg",
				"phase3_shadow_legacy_state_energy_divergence_kj",
				"phase3_shadow_legacy_interface_divergence_m",
				"phase3_shadow_legacy_pressure_divergence_pa",
				"phase3_shadow_request_count", "phase3_shadow_plume_mass_request_kg",
				"phase3_shadow_combustion_energy_request_kj",
				"phase3_shadow_combustion_o2_request_kg",
				"phase3_shadow_combustion_o2_rejected_kg",
				"phase3_shadow_combustion_co_request_kg",
				"phase3_shadow_combustion_co2_request_kg",
				"phase3_shadow_combustion_hcn_request_kg",
				"phase3_shadow_combustion_species_rejected_kg",
				"phase3_shadow_doorway_co_request_kg",
				"phase3_shadow_doorway_co2_request_kg",
				"phase3_shadow_doorway_hcn_request_kg",
				"phase3_shadow_doorway_species_rejected_kg",
				"phase3_shadow_background_co_kg_total",
				"phase3_shadow_background_co2_kg_total",
				"phase3_shadow_background_hcn_kg_total",
				"phase3_shadow_counterflow_co_kg_total",
				"phase3_shadow_counterflow_co2_kg_total",
				"phase3_shadow_counterflow_hcn_kg_total",
				"phase3_shadow_immediate_transfer_count",
				"phase3_shadow_immediate_rejected_kg_total",
				"phase3_shadow_immediate_co_residual_kg",
				"phase3_shadow_immediate_co2_residual_kg",
				"phase3_shadow_immediate_hcn_residual_kg",
				"phase3_shadow_vertical_net_co_kg_total",
				"phase3_shadow_vertical_net_co2_kg_total",
				"phase3_shadow_vertical_net_hcn_kg_total",
				"phase3_shadow_vertical_directed_co_kg_total",
				"phase3_shadow_vertical_directed_co2_kg_total",
				"phase3_shadow_vertical_directed_hcn_kg_total",
				"phase3_shadow_vertical_transfer_count",
				"phase3_shadow_vertical_rejected_kg_total",
				"phase3_shadow_vertical_opposed_zone_direction_count",
				"phase3_shadow_vertical_co_residual_kg",
				"phase3_shadow_vertical_co2_residual_kg",
				"phase3_shadow_vertical_hcn_residual_kg",
				"phase3_shadow_thermal_co_kg_total",
				"phase3_shadow_thermal_co2_kg_total",
				"phase3_shadow_thermal_hcn_kg_total",
				"phase3_shadow_thermal_source_upper_co_kg_total",
				"phase3_shadow_thermal_source_upper_co2_kg_total",
				"phase3_shadow_thermal_source_upper_hcn_kg_total",
				"phase3_shadow_thermal_source_lower_co_kg_total",
				"phase3_shadow_thermal_source_lower_co2_kg_total",
				"phase3_shadow_thermal_source_lower_hcn_kg_total",
				"phase3_shadow_thermal_destination_upper_co_kg_total",
				"phase3_shadow_thermal_destination_upper_co2_kg_total",
				"phase3_shadow_thermal_destination_upper_hcn_kg_total",
				"phase3_shadow_thermal_destination_lower_co_kg_total",
				"phase3_shadow_thermal_destination_lower_co2_kg_total",
				"phase3_shadow_thermal_destination_lower_hcn_kg_total",
				"phase3_shadow_thermal_applied_co_kg_total",
				"phase3_shadow_thermal_applied_co2_kg_total",
				"phase3_shadow_thermal_applied_hcn_kg_total",
				"phase3_shadow_thermal_rejected_co_kg_total",
				"phase3_shadow_thermal_rejected_co2_kg_total",
				"phase3_shadow_thermal_rejected_hcn_kg_total",
				"phase3_shadow_thermal_event_count",
				"phase3_shadow_thermal_duplicate_event_count",
				"phase3_shadow_thermal_co_residual_kg",
				"phase3_shadow_thermal_co2_residual_kg",
				"phase3_shadow_thermal_hcn_residual_kg",
				"phase3_shadow_thermal_doorway_kg_total",
				"phase3_shadow_thermal_outside_background_kg_total",
				"phase3_shadow_thermal_interior_background_kg_total",
				"phase3_shadow_thermal_interlayer_kg_total",
				"phase3_shadow_purge_co_out_kg_total",
				"phase3_shadow_purge_co2_out_kg_total",
				"phase3_shadow_purge_hcn_out_kg_total",
				"phase3_shadow_purge_upper_co_kg_total",
				"phase3_shadow_purge_upper_co2_kg_total",
				"phase3_shadow_purge_upper_hcn_kg_total",
				"phase3_shadow_purge_lower_co_kg_total",
				"phase3_shadow_purge_lower_co2_kg_total",
				"phase3_shadow_purge_lower_hcn_kg_total",
				"phase3_shadow_purge_applied_kg_total",
				"phase3_shadow_purge_rejected_kg_total",
				"phase3_shadow_purge_event_count",
				"phase3_shadow_purge_duplicate_event_count",
				"phase3_shadow_purge_co_residual_kg",
				"phase3_shadow_purge_co2_residual_kg",
				"phase3_shadow_purge_hcn_residual_kg",
				"phase3_shadow_purge_pressure_kg_total",
				"phase3_shadow_purge_smoke_vent_kg_total",
				"phase3_shadow_purge_natural_vent_kg_total",
				"phase3_shadow_purge_ach_kg_total",
				"phase3_shadow_purge_outside_open_kg_total",
				"phase3_shadow_purge_postfire_kg_total",
				"phase3_shadow_purge_ppv_inlet_kg_total",
				"phase3_shadow_purge_ppv_exhaust_kg_total",
				"phase3_shadow_species_inflight_co_kg",
				"phase3_shadow_species_inflight_co2_kg",
				"phase3_shadow_species_inflight_hcn_kg",
				"phase3_shadow_species_created_kg_total",
				"phase3_shadow_species_delivered_kg_total",
				"phase3_shadow_species_refunded_kg_total",
				"phase3_shadow_species_cancelled_kg_total",
				"phase3_shadow_species_active_parcel_count",
				"phase3_shadow_species_orphan_delivery_count",
				"phase3_shadow_species_duplicate_id_count",
				"phase3_shadow_species_negative_balance_count",
				"phase3_shadow_species_conservation_residual_kg",
				"phase3_shadow_species_conservation_residual_co_kg",
				"phase3_shadow_species_conservation_residual_co2_kg",
				"phase3_shadow_species_conservation_residual_hcn_kg",
				"phase3_shadow_species_transit_rejected_kg",
				"phase3_shadow_parcel_atomic_inflight_gas_kg",
				"phase3_shadow_parcel_atomic_inflight_energy_kj",
				"phase3_shadow_parcel_atomic_inflight_o2_kg",
				"phase3_shadow_parcel_atomic_inflight_species_kg",
				"phase3_shadow_parcel_atomic_created_gas_kg_total",
				"phase3_shadow_parcel_atomic_delivered_gas_kg_total",
				"phase3_shadow_parcel_atomic_refunded_gas_kg_total",
				"phase3_shadow_parcel_atomic_cancelled_gas_kg_total",
				"phase3_shadow_parcel_atomic_created_energy_kj_total",
				"phase3_shadow_parcel_atomic_delivered_energy_kj_total",
				"phase3_shadow_parcel_atomic_refunded_energy_kj_total",
				"phase3_shadow_parcel_atomic_cancelled_energy_kj_total",
				"phase3_shadow_parcel_atomic_created_o2_kg_total",
				"phase3_shadow_parcel_atomic_delivered_o2_kg_total",
				"phase3_shadow_parcel_atomic_refunded_o2_kg_total",
				"phase3_shadow_parcel_atomic_cancelled_o2_kg_total",
				"phase3_shadow_parcel_atomic_mass_residual_kg",
				"phase3_shadow_parcel_atomic_energy_residual_kj",
				"phase3_shadow_parcel_atomic_o2_residual_kg",
				"phase3_shadow_parcel_atomic_species_residual_kg",
				"phase3_shadow_parcel_atomic_unfinalized_resolution_count",
				"phase3_shadow_combustion_owned_mask",
				"phase3_shadow_owned_cause_count", "phase3_shadow_rejected_mass_kg",
				"phase3_shadow_duplicate_owner_flag", "phase3_shadow_zero_o2_flame_flag",
				"phase3_shadow_needs_flux_owner_flag",
				"phase3_shadow_semantic_claim_count",
				"phase3_shadow_semantic_conflict_count",
				"phase3_shadow_semantic_conflict_quantity_mask",
				"phase3_shadow_semantic_conflict_mass_kg",
				"phase3_shadow_semantic_conflict_energy_kj",
				"phase3_shadow_semantic_conflict_o2_kg",
				"phase3_shadow_semantic_conflict_species_kg",
				"phase3_shadow_semantic_unknown_connection_count",
				"phase3_shadow_thermal_semantic_suppressed_kg_total",
				"phase3_shadow_semantic_accepted_claim_count",
				"phase3_shadow_semantic_suppressed_claim_count",
				"phase3_shadow_semantic_unresolved_claim_count",
				"phase3_shadow_semantic_suppressed_quantity_mask",
				"phase3_shadow_semantic_unresolved_quantity_mask",
				"phase3_shadow_semantic_suppressed_species_kg",
				"phase3_shadow_semantic_unresolved_mass_kg",
				"phase3_shadow_semantic_unresolved_energy_kj",
				"phase3_shadow_semantic_unresolved_o2_kg",
				"phase3_shadow_semantic_unresolved_species_kg",
				"phase3_shadow_semantic_unresolved_conflict_count",
				"phase3_shadow_atomic_bundle_count",
				"phase3_shadow_atomic_route_count",
				"phase3_shadow_atomic_min_accepted_fraction",
				"phase3_shadow_atomic_rejected_mass_kg",
				"phase3_shadow_atomic_rejected_energy_kj",
				"phase3_shadow_atomic_rejected_o2_kg",
				"phase3_shadow_atomic_rejected_species_kg",
				"phase3_shadow_atomic_duplicate_bundle_count",
				"phase3_shadow_atomic_invalid_bundle_count",
				"phase3_shadow_co_oxidation_co_sink_kg_step",
				"phase3_shadow_co_oxidation_co2_source_kg_step",
				"phase3_shadow_co_oxidation_carbon_residual_kg_step",
				"phase3_shadow_co_oxidation_o2_sink_kg_step",
				"phase3_shadow_co_oxidation_accepted_fraction",
				"phase3_shadow_co_oxidation_accepted_co_sink_kg_step",
				"phase3_shadow_co_oxidation_accepted_co2_source_kg_step",
				"phase3_shadow_co_oxidation_accepted_o2_sink_kg_step",
				"phase3_shadow_co_oxidation_o2_rejected_kg_step",
				"phase3_shadow_co_oxidation_oxygen_residual_kg_step",
				"phase3_shadow_co_oxidation_legacy_lower_co2_kg_step"
			]:
				fields.append("%.8f" % float(rs.get(field_name, 0.0)))
		if phase3_canonical_exterior_boundary_shadow_enabled:
			for field_name in [
				"phase3_shadow_exterior_pressure_pre_pa",
				"phase3_shadow_exterior_requested_gas_kg",
				"phase3_shadow_exterior_requested_energy_kj",
				"phase3_shadow_exterior_requested_o2_kg",
				"phase3_shadow_exterior_requested_species_kg",
				"phase3_shadow_exterior_accepted_gas_kg",
				"phase3_shadow_exterior_accepted_energy_kj",
				"phase3_shadow_exterior_accepted_o2_kg",
				"phase3_shadow_exterior_accepted_species_kg",
				"phase3_shadow_exterior_post_upper_o2_kg",
				"phase3_shadow_exterior_post_lower_o2_kg",
				"phase3_shadow_exterior_post_upper_o2_fraction",
				"phase3_shadow_exterior_post_lower_o2_fraction",
				"phase3_shadow_exterior_rejected_gas_kg",
				"phase3_shadow_exterior_rejected_energy_kj",
				"phase3_shadow_exterior_rejected_o2_kg",
				"phase3_shadow_exterior_rejected_species_kg",
				"phase3_shadow_exterior_direction",
				"phase3_shadow_exterior_source_zone_code",
				"phase3_shadow_exterior_event_count",
				"phase3_shadow_exterior_legacy_pressure_suppressed_event_count",
				"phase3_shadow_exterior_accepted_fraction",
				"phase3_shadow_exterior_duplicate_owner_flag",
				"phase3_shadow_exterior_mass_residual_kg",
				"phase3_shadow_exterior_energy_residual_kj",
				"phase3_shadow_exterior_o2_residual_kg",
				"phase3_shadow_exterior_species_residual_kg"
			]:
				fields.append("%.8f" % float(rs.get(field_name, 0.0)))
		if phase3_canonical_persistence_shadow_enabled:
			for field_name in [
				"phase3_shadow_persistent_step_index",
				"phase3_shadow_persistent_seeded_from_legacy_flag",
				"phase3_shadow_persistent_continuity_mass_residual_kg",
				"phase3_shadow_persistent_continuity_energy_residual_kj",
				"phase3_shadow_persistent_continuity_o2_residual_kg",
				"phase3_shadow_persistent_continuity_species_residual_kg",
				"phase3_shadow_persistent_pre_upper_o2_fraction",
				"phase3_shadow_persistent_pre_lower_o2_fraction",
				"phase3_shadow_persistent_post_upper_o2_fraction",
				"phase3_shadow_persistent_post_lower_o2_fraction",
				"phase3_shadow_persistent_combustion_o2_ref",
				"phase3_shadow_persistent_legacy_combustion_o2_ref",
				"phase3_shadow_persistent_combustion_o2_delta",
				"phase3_shadow_persistent_combustion_zone_code",
				"phase3_shadow_persistent_combustion_o2_requested_kg",
				"phase3_shadow_persistent_combustion_o2_accepted_kg",
				"phase3_shadow_persistent_combustion_o2_rejected_kg",
				"phase3_shadow_persistent_combustion_o2_accepted_fraction",
				"phase3_shadow_persistent_combustion_would_limit_flag",
				"phase3_shadow_persistent_zone_collapse_count",
				"phase3_shadow_persistent_zone_collapse_source_code",
				"phase3_shadow_persistent_zone_collapse_mass_residual_kg",
				"phase3_shadow_persistent_zone_collapse_energy_residual_kj",
				"phase3_shadow_persistent_zone_collapse_o2_residual_kg",
				"phase3_shadow_persistent_zone_collapse_species_residual_kg"
			]:
				fields.append("%.8f" % float(rs.get(field_name, 0.0)))
		if phase3_canonical_combustion_shadow_enabled:
			for field_name in [
				"phase3_shadow_combustion_transaction_active_flag",
				"phase3_shadow_combustion_canonical_o2_ref",
				"phase3_shadow_combustion_o2_source_zone_code",
				"phase3_shadow_combustion_extinction_o2_limit",
				"phase3_shadow_combustion_canonical_o2_hrr_factor",
				"phase3_shadow_combustion_legacy_o2_hrr_factor",
				"phase3_shadow_combustion_legacy_hrr_kw",
				"phase3_shadow_combustion_accepted_hrr_kw",
				"phase3_shadow_combustion_decision_fraction",
				"phase3_shadow_combustion_atomic_fraction",
				"phase3_shadow_combustion_effective_fraction",
				"phase3_shadow_combustion_requested_o2_kg",
				"phase3_shadow_combustion_accepted_o2_kg",
				"phase3_shadow_combustion_requested_fuel_MJ",
				"phase3_shadow_combustion_accepted_fuel_MJ",
				"phase3_shadow_combustion_requested_species_kg",
				"phase3_shadow_combustion_accepted_species_kg",
				"phase3_shadow_combustion_requested_convective_energy_kj",
				"phase3_shadow_combustion_accepted_convective_energy_kj",
				"phase3_shadow_combustion_requested_plume_mass_kg",
				"phase3_shadow_combustion_accepted_plume_mass_kg",
				"phase3_shadow_combustion_remaining_fuel_MJ",
				"phase3_shadow_combustion_retained_unburned_MJ",
				"phase3_shadow_combustion_zero_o2_flame_flag",
				"phase3_shadow_combustion_o2_residual_kg",
				"phase3_shadow_combustion_energy_residual_kj",
				"phase3_shadow_combustion_species_residual_kg"
			]:
				fields.append("%.8f" % float(rs.get(field_name, 0.0)))
		if phase3_canonical_pressure_relaxation_shadow_enabled:
			for field_name in [
				"phase3_shadow_exterior_relaxation_enabled_flag",
				"phase3_shadow_exterior_raw_requested_gas_kg",
				"phase3_shadow_exterior_raw_requested_energy_kj",
				"phase3_shadow_exterior_pressure_equilibrium_fraction",
				"phase3_shadow_exterior_pressure_full_delta_pa",
				"phase3_shadow_exterior_pressure_limited_delta_pa",
				"phase3_shadow_exterior_pressure_predicted_post_pa",
				"phase3_shadow_exterior_pressure_crossing_prevented_flag",
				"phase3_shadow_exterior_degenerate_lower_reseed_flag",
				"phase3_shadow_exterior_degenerate_lower_reseed_mass_kg",
				"phase3_shadow_exterior_lower_reseed_count_total",
				"phase3_shadow_exterior_lower_reseed_mass_kg_total",
				"phase3_shadow_exterior_lower_reseed_first_step_index"
			]:
				fields.append("%.8f" % float(rs.get(field_name, 0.0)))
		file.store_line(",".join(fields))

	file.close()

	# SF-AUD-029: targets CSV separado
	_append_target_csv_snapshot(sim_time_s, state)


func _append_target_csv_snapshot(sim_time_s: float, state: Dictionary) -> void:
	var targets: Dictionary = state.get("targets", {})
	if targets.is_empty():
		return
	if _target_csv_io_failed:
		return

	var path: String = _normalize_log_path(target_csv_file_path)
	if not _ensure_log_directory(path):
		return

	var file: FileAccess
	if not _target_csv_header_written:
		file = FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			_target_csv_io_failed = true
			push_error("SimulationLogWriter: no se pudo crear target CSV en %s (err=%d)" % [path, FileAccess.get_open_error()])
			return
		file.store_line("time_s,target_id,room_id,qnet_kw_m2,peak_qnet_kw_m2,temp_c,ignited")
		_target_csv_header_written = true
	else:
		file = FileAccess.open(path, FileAccess.READ_WRITE)
		if file == null:
			_target_csv_io_failed = true
			push_error("SimulationLogWriter: no se pudo abrir target CSV en %s (err=%d)" % [path, FileAccess.get_open_error()])
			return
		file.seek_end()

	for tid in targets.keys():
		var ts: Dictionary = targets[tid]
		var fields: PackedStringArray = PackedStringArray()
		fields.append("%.1f" % sim_time_s)
		fields.append(_csv_escape(str(tid)))
		fields.append(str(ts.get("room_id", -1)))
		fields.append("%.4f" % float(ts.get("qnet_kw_m2", 0.0)))
		fields.append("%.4f" % float(ts.get("peak_qnet_kw_m2", 0.0)))
		fields.append("%.2f" % float(ts.get("temp_c", 20.0)))
		fields.append("1" if bool(ts.get("ignited", false)) else "0")
		file.store_line(",".join(fields))

	file.close()


func _csv_escape(value: String) -> String:
	if value.find(",") >= 0 or value.find("\"") >= 0 or value.find("\n") >= 0:
		return "\"" + value.replace("\"", "\"\"") + "\""
	return value

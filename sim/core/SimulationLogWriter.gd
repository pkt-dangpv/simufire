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

var _next_log_time_s: float = 0.0
var _resolved_log_file_path: String = ""
var _log_io_failed: bool = false
var _resolved_csv_file_path: String = ""
var _csv_io_failed: bool = false
var _csv_header_written: bool = false


func configure(is_enabled: bool, interval_seconds: float, path: String) -> void:
	enabled = is_enabled
	interval_s = maxf(0.0, interval_seconds)
	log_file_path = path


func configure_csv(is_enabled: bool, path: String) -> void:
	csv_enabled = is_enabled
	csv_file_path = path


func reset_log_file() -> void:
	_next_log_time_s = 0.0
	_resolved_log_file_path = ""
	_log_io_failed = false
	_resolved_csv_file_path = ""
	_csv_io_failed = false
	_csv_header_written = false

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

	return _normalize_log_path(csv_file_path)


func should_log(sim_time_s: float) -> bool:
	return enabled and sim_time_s >= _next_log_time_s


func append_snapshot(sim_time_s: float, state: Dictionary) -> void:
	if not should_log(sim_time_s):
		return

	_append_snapshot(sim_time_s, state)
	if csv_enabled:
		_append_csv_snapshot(sim_time_s, state)
	_next_log_time_s += interval_s


func append_snapshot_now(sim_time_s: float, state: Dictionary) -> void:
	if not enabled:
		return

	_append_snapshot(sim_time_s, state)
	if csv_enabled:
		_append_csv_snapshot(sim_time_s, state)


## Escribe una línea de evento al log de forma inmediata (fuera del intervalo normal).
## Formato: EVENT t=600.0 type=door_open opening=2 room_a=1 room_b=-1 frac=1.00
func append_event(sim_time_s: float, event_type: String, details: String) -> void:
	if not enabled:
		return
	var file := _open_log_file(FileAccess.READ_WRITE, true)
	if file == null:
		return
	file.seek_end()
	if details.is_empty():
		file.store_line("EVENT t=%.1f type=%s" % [sim_time_s, event_type])
	else:
		file.store_line("EVENT t=%.1f type=%s %s" % [sim_time_s, event_type, details])
	file.close()


func _normalize_log_path(path: String) -> String:
	if path.begins_with("user://") or path.begins_with("res://"):
		return ProjectSettings.globalize_path(path)
	return path


func _get_log_file_candidates() -> Array[String]:
	var candidates: Array[String] = []
	var primary_path: String = _normalize_log_path(log_file_path)
	candidates.append(primary_path)

	var project_fallback_path: String = ProjectSettings.globalize_path("res://sim_log.txt")
	if not candidates.has(project_fallback_path):
		candidates.append(project_fallback_path)

	return candidates


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
		var line := "ROOM %s | HRR=%.2f | Up=%.2f | Low=%.2f | Smoke=%.4f | Vis=%.1fm | SmokeLayer=%.2f | HotLayer=%.2f | L150=%.2f | P=%.2fPa | O2=%.4f | CO=%.0fppm | COu=%.0fppm | CO2=%.0fppm | FED=%.3f | SVV=%.0f%% [%s]" % [
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
			float(room_state.get("co_ppm", 0.0)),
			float(room_state.get("co_upper_ppm", 0.0)),
			float(room_state.get("co2_ppm", 0.0)),
			fed_val,
			svv_pct,
			svv_zone
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
	return "time_s,room_id,room_name,hrr_kw,temp_upper_c,temp_lower_c,temp_at_0_9m_c,smoke_kg,visibility_m,smoke_layer_m,hot_layer_m,layer_150c_m,overpressure_pa,o2,co_ppm,co_upper_ppm,co2_ppm,fed,svv_worst_pct,flashover_triggered,flashover_time_s,fuel_remaining_MJ,ventilation_response_factor,pyrolysis_kw,burned_hrr_kw,unburned_generation_kw,retained_unburned_MJ,flame_hrr_target_kw,smolder_hrr_target_kw,pool_release_hrr_target_kw,o2_hrr_factor,fire_smoldering,backdraft_triggered"


func _open_csv_file(mode: FileAccess.ModeFlags) -> FileAccess:
	if _csv_io_failed:
		return null

	var path: String = _normalize_log_path(csv_file_path)
	if not _ensure_log_directory(path):
		return null
	var file := FileAccess.open(path, mode)
	if file != null:
		_resolved_csv_file_path = path
		return file

	_csv_io_failed = true
	push_error("SimulationLogWriter: no se pudo abrir CSV en %s (err=%d)" % [path, FileAccess.get_open_error()])
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
		fields.append("%.3f" % float(rs.get("hot_layer_m", 0.0)))
		fields.append("%.3f" % float(rs.get("layer_150c_m", 0.0)))
		fields.append("%.3f" % float(rs.get("overpressure_pa", 0.0)))
		fields.append("%.5f" % float(rs.get("o2", 0.0)))
		fields.append("%.0f" % float(rs.get("co_ppm", 0.0)))
		fields.append("%.0f" % float(rs.get("co_upper_ppm", 0.0)))
		fields.append("%.0f" % float(rs.get("co2_ppm", 0.0)))
		fields.append("%.4f" % float(rs.get("fed", 0.0)))
		fields.append("%.1f" % float(rs.get("svv_worst_pct", 100.0)))
		fields.append("1" if bool(rs.get("flashover_triggered", false)) else "0")
		fields.append("%.1f" % float(rs.get("flashover_time_s", -1.0)))
		fields.append("%.2f" % float(rs.get("fuel_objects_remaining_MJ", rs.get("remaining_fuel_MJ", 0.0))))
		fields.append("%.4f" % float(rs.get("ventilation_response_factor", 0.0)))
		fields.append("%.2f" % float(rs.get("pyrolysis_kw", 0.0)))
		fields.append("%.2f" % float(rs.get("burned_hrr_kw", rs.get("hrr_kw", 0.0))))
		fields.append("%.2f" % float(rs.get("unburned_generation_kw", 0.0)))
		fields.append("%.4f" % float(rs.get("retained_unburned_MJ", 0.0)))
		fields.append("%.2f" % float(rs.get("flame_hrr_target_kw", 0.0)))
		fields.append("%.2f" % float(rs.get("smolder_hrr_target_kw", 0.0)))
		fields.append("%.2f" % float(rs.get("pool_release_hrr_target_kw", 0.0)))
		fields.append("%.4f" % float(rs.get("o2_hrr_factor", 0.0)))
		fields.append("1" if bool(rs.get("fire_smoldering", false)) else "0")
		fields.append("1" if bool(rs.get("backdraft_triggered", false)) else "0")
		file.store_line(",".join(fields))

	file.close()


func _csv_escape(value: String) -> String:
	if value.find(",") >= 0 or value.find("\"") >= 0 or value.find("\n") >= 0:
		return "\"" + value.replace("\"", "\"\"") + "\""
	return value

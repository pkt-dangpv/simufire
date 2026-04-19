extends RefCounted
class_name SimulationLogWriter

var enabled: bool = true
var interval_s: float = 10.0
var log_file_path: String = "user://sim_log.txt"

var _next_log_time_s: float = 0.0
var _resolved_log_file_path: String = ""
var _log_io_failed: bool = false


func configure(is_enabled: bool, interval_seconds: float, path: String) -> void:
	enabled = is_enabled
	interval_s = maxf(0.0, interval_seconds)
	log_file_path = path


func reset_log_file() -> void:
	_next_log_time_s = 0.0
	_resolved_log_file_path = ""
	_log_io_failed = false

	if not enabled:
		return

	var file := _open_log_file(FileAccess.WRITE)
	if file == null:
		return

	file.store_line("SIMULATION LOG")
	file.store_line("")
	file.close()


func resolve_log_file_path() -> String:
	if not _resolved_log_file_path.is_empty():
		return _resolved_log_file_path

	var candidates: Array[String] = _get_log_file_candidates()
	return candidates[0] if not candidates.is_empty() else log_file_path


func should_log(sim_time_s: float) -> bool:
	return enabled and sim_time_s >= _next_log_time_s


func append_snapshot(sim_time_s: float, state: Dictionary) -> void:
	if not should_log(sim_time_s):
		return

	_append_snapshot(sim_time_s, state)
	_next_log_time_s += interval_s


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

		var line := "ROOM %s | HRR=%.2f | Up=%.2f | Low=%.2f | Smoke=%.4f | SmokeLayer=%.2f | HotLayer=%.2f | L150=%.2f | P=%.2fPa | O2=%.4f | CO=%.0fppm" % [
			str(room_state.get("id", room_id)),
			float(room_state.get("hrr_kw", 0.0)),
			float(room_state.get("temp_upper_c", 0.0)),
			float(room_state.get("temp_lower_c", 0.0)),
			float(room_state.get("smoke_kg", 0.0)),
			float(room_state.get("smoke_layer_m", 0.0)),
			float(room_state.get("hot_layer_m", 0.0)),
			float(room_state.get("layer_150c_m", 0.0)),
			float(room_state.get("overpressure_pa", 0.0)),
			float(room_state.get("o2", 0.0)),
			float(room_state.get("co_ppm", 0.0))
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

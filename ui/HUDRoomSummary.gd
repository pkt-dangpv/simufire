extends RefCounted
class_name HUDRoomSummary

const FLASHOVER_DISPLAY_DURATION_S: float = 22.0


static func card_summary(room_id: int, room_state: Dictionary, sim_time_s: float, flashover_permanent: bool) -> Dictionary:
	if room_state.is_empty():
		return {
			"header": "R%d" % room_id,
			"text": "Sin datos",
			"severity": "normal"
		}

	var hrr: float = float(room_state.get("hrr_kw", 0.0))
	var t_upper: float = float(room_state.get("temp_upper_c", 20.0))
	var t_lower: float = float(room_state.get("temp_lower_c", 20.0))
	var t09: float = float(room_state.get("temp_at_0_9m_c", t_lower))
	var o2_pct: float = float(room_state.get("o2", 0.209)) * 100.0
	var smoke_l: float = float(room_state.get("smoke_layer_m", room_state.get("h_layer_m", float(room_state.get("height_m", 2.4)))))
	var co_ppm: float = float(room_state.get("co_ppm", 0.0))
	var fed: float = float(room_state.get("fed", 0.0))
	var flashover: bool = is_flashover_visible(room_state, sim_time_s, flashover_permanent)
	var fuel_capacity_mj: float = float(room_state.get("fuel_capacity_MJ", room_state.get("fuel_energy_MJ", 0.0)))
	var remaining_fuel_mj: float = float(room_state.get("fuel_objects_remaining_MJ", room_state.get("remaining_fuel_MJ", 0.0)))

	var lines: PackedStringArray = PackedStringArray()
	var fire_line: String = "HRR %.0fkW" % hrr if hrr > 0.5 else "Sin fuego"
	lines.append("%s | T+ %.0f T- %.0fC" % [fire_line, t_upper, t_lower])
	lines.append("O2 %.1f%% | Sm %.2fm | FED %.2f" % [o2_pct, smoke_l, fed])
	if hrr > 0.5:
		lines.append("T@0.9 %.0fC | Comb %.0f/%.0fMJ" % [t09, remaining_fuel_mj, fuel_capacity_mj])
	elif co_ppm > 1.0:
		lines.append("CO %.0fppm | SVV %.0f%%" % [co_ppm, svv_pct(room_state)])
	else:
		lines.append("SVV %.0f%% | Comb %.0fMJ" % [svv_pct(room_state), remaining_fuel_mj])
	if flashover:
		lines.append("FLASHOVER")

	return {
		"header": card_header(room_id, room_state),
		"text": "\n".join(lines),
		"severity": card_severity(room_state, sim_time_s, flashover_permanent)
	}


static func detail_text(room_state: Dictionary) -> String:
	if room_state.is_empty():
		return "Sin datos"

	var room_name: String = String(room_state.get("name", ""))
	var fed: float = float(room_state.get("fed", 0.0))
	var svv: float = svv_pct(room_state)
	var header_line: String = ""
	if room_name != "":
		header_line = "%s\nFED %.3f  SVV %.0f%%" % [room_name, fed, svv]
	else:
		header_line = "FED %.3f  SVV %.0f%%" % [fed, svv]

	var data_lines: Array[String] = [
		"HRR: %.0f kW" % float(room_state.get("hrr_kw", 0.0)),
		"T+ %.0f  T- %.0f C" % [float(room_state.get("temp_upper_c", 0.0)), float(room_state.get("temp_lower_c", 0.0))],
		"T@0.9m: %.0f C  T@1.8m: %.0f C" % [float(room_state.get("temp_at_0_9m_c", room_state.get("temp_lower_c", 0.0))), float(room_state.get("temp_at_1_8m_c", 0.0))],
		"O2: %.1f%%  CO2: %.2f%%" % [float(room_state.get("o2", 0.0)) * 100.0, float(room_state.get("co2", 0.0)) * 100.0],
		"SmL: %.2f m  L150: %.2f m" % [float(room_state.get("smoke_layer_m", room_state.get("h_layer_m", 0.0))), float(room_state.get("layer_150c_m", 0.0))],
		"CO: %.0f ppm  HCN: %.1f ppm" % [float(room_state.get("co_ppm", 0.0)), float(room_state.get("hcn_ppm", 0.0))],
		"P: %.1f Pa  Smoke: %.3f kg" % [float(room_state.get("overpressure_pa", 0.0)), float(room_state.get("smoke_kg", 0.0))],
	]
	if bool(room_state.get("flashover_triggered", false)):
		data_lines.append("!!! FLASHOVER !!!")
	return header_line + "\n" + "\n".join(PackedStringArray(data_lines))


static func card_header(room_id: int, room_state: Dictionary) -> String:
	var room_name: String = String(room_state.get("name", ""))
	return "R%d %s" % [room_id, room_name] if room_name != "" else "R%d" % room_id


static func card_severity(room_state: Dictionary, sim_time_s: float, flashover_permanent: bool) -> String:
	var hrr: float = float(room_state.get("hrr_kw", 0.0))
	var o2_pct: float = float(room_state.get("o2", 0.209)) * 100.0
	var fed: float = float(room_state.get("fed", 0.0))
	if is_flashover_visible(room_state, sim_time_s, flashover_permanent) or hrr > 500.0:
		return "flash"
	if o2_pct < 18.0 or fed > 0.3:
		return "alert"
	return "normal"


static func svv_pct(room_state: Dictionary) -> float:
	var value: float = float(room_state.get("svv_worst_pct", -1.0))
	if value >= 0.0:
		return value
	var h_m: float = float(room_state.get("height_m", 2.4))
	var layer_150c_m: float = float(room_state.get("layer_150c_m", h_m))
	if layer_150c_m >= 1.8:
		return 100.0
	if layer_150c_m >= 0.5:
		return 90.0 + 9.0 * (layer_150c_m - 0.5) / 1.3
	return clampf(layer_150c_m / 0.5 * 90.0, 0.0, 90.0)


static func is_flashover_visible(room_state: Dictionary, sim_time_s: float, permanent: bool) -> bool:
	if not bool(room_state.get("flashover_triggered", false)):
		return false
	if permanent:
		return true
	var flash_time_s: float = float(room_state.get("flashover_time_s", -1.0))
	if flash_time_s < 0.0:
		return true
	return sim_time_s <= flash_time_s + FLASHOVER_DISPLAY_DURATION_S

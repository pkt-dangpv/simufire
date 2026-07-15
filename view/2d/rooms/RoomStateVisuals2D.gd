extends RefCounted


static func fuel_object_color_for_state(state_name: String, fallback_fill: Color) -> Color:
	match state_name:
		"flaming":
			return Color(1.0, 0.24, 0.10, 0.82)
		"pyrolyzing":
			return Color(1.0, 0.55, 0.12, 0.78)
		"heating":
			return Color(1.0, 0.78, 0.22, 0.72)
		"decaying":
			return Color(0.75, 0.38, 0.18, 0.62)
		"burned_out":
			return Color(0.24, 0.24, 0.24, 0.55)
		_:
			return fallback_fill


static func compute_svv_pct(rs: Dictionary) -> float:
	if rs.has("svv_worst_pct"):
		return clampf(float(rs.get("svv_worst_pct", 100.0)), 0.0, 100.0)

	var height_m: float = float(rs.get("height_m", 2.4))
	var layer_150c: float = clampf(float(rs.get("layer_150c_m", height_m)), 0.0, height_m)
	var fed_val: float = float(rs.get("fed", 0.0))
	var hot_layer_m: float = float(rs.get("hot_layer_m", height_m))
	var temp_upper_c: float = float(rs.get("temp_upper_c", 20.0))

	var thermal_svv: float
	if layer_150c >= 1.8:
		if hot_layer_m < 1.8 and temp_upper_c > 60.0:
			var penetration: float = clampf((1.8 - hot_layer_m) / 0.3, 0.0, 1.0)
			var temp_factor: float = clampf((temp_upper_c - 60.0) / 90.0, 0.0, 1.0)
			thermal_svv = 1.0 - penetration * temp_factor
		else:
			thermal_svv = 1.0
	elif layer_150c >= 0.5:
		thermal_svv = 0.90 + 0.09 * (layer_150c - 0.5) / 1.3
	elif layer_150c > 0.10:
		thermal_svv = 0.05 + 0.85 * ((layer_150c - 0.10) / 0.40)
	else:
		thermal_svv = 0.0

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

	return minf(thermal_svv, fed_svv) * 100.0


static func svv_color(svv_pct: float) -> Color:
	if svv_pct >= 90.0:
		return Color(0.30, 0.78, 0.35, 1.0)
	if svv_pct >= 60.0:
		return Color(1.00, 0.75, 0.15, 1.0)
	if svv_pct >= 20.0:
		return Color(1.00, 0.45, 0.10, 1.0)
	if svv_pct >= 5.0:
		return Color(0.95, 0.20, 0.20, 1.0)
	return Color(0.35, 0.35, 0.35, 1.0)


static func window_status_label(rs: Dictionary, full_open_threshold: float) -> String:
	var w_open: float = float(rs.get("window_open_max", -1.0))
	if w_open < 0.0:
		return ""
	if w_open <= 0.0:
		return "Win CLOSED"
	if w_open < full_open_threshold:
		return "Win BROKEN %.0f%%" % (w_open * 100.0)
	return "Win OPEN %.0f%%" % (w_open * 100.0)


static func vector2_from_variant(value: Variant) -> Vector2:
	if typeof(value) == TYPE_VECTOR2:
		return value
	if typeof(value) == TYPE_DICTIONARY:
		var data: Dictionary = value
		return Vector2(float(data.get("x", 0.0)), float(data.get("y", 0.0)))
	if typeof(value) == TYPE_ARRAY:
		var values: Array = value
		if values.size() >= 2:
			return Vector2(float(values[0]), float(values[1]))
	return Vector2.ZERO

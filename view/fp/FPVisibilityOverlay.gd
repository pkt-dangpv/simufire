extends RefCounted


static func compute(
	room_state: Dictionary,
	room_rect: Rect2,
	eye_height_m: float,
	settings: Dictionary
) -> Dictionary:
	var max_visibility_m: float = maxf(1.0, float(settings.get("clear_visibility_m", 30.0)))
	var visibility_reference_m: float = maxf(0.1, float(settings.get("visibility_reference_m", 14.0)))
	var layer_clearance_m: float = float(settings.get("layer_clearance_m", 0.10))
	var layer_transition_m: float = maxf(0.05, float(settings.get("layer_transition_m", 0.42)))
	var max_alpha: float = clampf(float(settings.get("max_alpha", 0.92)), 0.0, 1.0)

	var visibility_m: float = clampf(float(room_state.get("visibility_m", 30.0)), 0.0, max_visibility_m)
	var smoke_kg: float = float(room_state.get("smoke_kg", 0.0))
	var upper_temp_c: float = float(room_state.get("temp_upper_c", 20.0))
	var room_height_m: float = float(room_state.get("height_m", 2.4))
	var smoke_layer_m: float = clampf(
		float(room_state.get("smoke_display_layer_m", room_state.get("smoke_layer_m", room_state.get("h_layer_m", room_height_m)))),
		0.0,
		room_height_m
	)

	var immersion: float = clampf(
		(eye_height_m + layer_clearance_m - smoke_layer_m) / layer_transition_m,
		0.0,
		1.0
	)
	var upper_depth_m: float = maxf(0.05, room_height_m - smoke_layer_m)
	var upper_volume_m3: float = maxf(0.05, room_rect.size.x * room_rect.size.y * upper_depth_m)
	var smoke_density_t: float = clampf((smoke_kg / upper_volume_m3) / 0.018, 0.0, 1.0)
	var optical_block: float = immersion
	var alpha_from_visibility: float = clampf(
		(visibility_reference_m - visibility_m) / visibility_reference_m,
		0.0,
		0.86
	)
	var alpha_from_density: float = clampf(smoke_density_t * lerpf(0.18, 0.64, immersion), 0.0, 0.62)
	var alpha_from_mass: float = clampf(smoke_kg / 3.0, 0.0, 0.24)
	var alpha_from_layer: float = (0.18 + smoke_density_t * 0.58) * immersion
	var alpha_from_optics: float = alpha_from_visibility * lerpf(0.10, 1.0, optical_block)
	var heat_tint: float = clampf((upper_temp_c - 80.0) / 420.0, 0.0, 1.0)
	var alpha: float = clampf(
		maxf(maxf(alpha_from_optics, alpha_from_density * lerpf(0.18, 1.0, optical_block)), maxf(alpha_from_layer, alpha_from_mass * optical_block)),
		0.0,
		max_alpha
	)
	var display_block: float = clampf(maxf(optical_block, smoke_density_t * 0.34 * immersion), 0.0, 1.0)
	var fp_visibility_m: float = lerpf(max_visibility_m, visibility_m, display_block)
	return {
		"overlay_alpha": alpha,
		"heat_tint": heat_tint,
		"fp_visibility_m": fp_visibility_m,
		"raw_visibility_m": visibility_m,
		"optical_block": optical_block
	}


static func format_visibility(visibility_m: float, clear_visibility_m: float) -> String:
	var clear_m: float = maxf(1.0, clear_visibility_m)
	var v: float = clampf(visibility_m, 0.0, clear_m)
	if v >= clear_m - 0.25:
		return "Vis FP >%.0fm" % clear_m
	if v < 10.0:
		return "Vis FP %.1fm" % maxf(0.1, v)
	return "Vis FP %.0fm" % v

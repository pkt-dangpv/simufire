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
	var severe_visibility_m: float = maxf(0.1, float(settings.get("severe_visibility_m", 2.0)))

	var visibility_m: float = clampf(float(room_state.get("visibility_m", 30.0)), 0.0, max_visibility_m)
	var smoke_kg: float = float(room_state.get("smoke_kg", 0.0))
	var upper_temp_c: float = float(room_state.get("temp_upper_c", 20.0))
	var o2_upper: float = float(room_state.get("o2_upper", room_state.get("o2", 0.209)))
	var hrr_kw: float = float(room_state.get("hrr_kw", 0.0))
	var regime: String = String(room_state.get("combustion_regime", ""))
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
	var alpha_from_optics: float = alpha_from_visibility * lerpf(0.04, 1.0, optical_block)
	var heat_tint: float = clampf((upper_temp_c - 80.0) / 420.0, 0.0, 1.0)
	var ilv_t: float = 0.0
	if _is_ventilation_limited_regime(regime):
		ilv_t = maxf(ilv_t, 0.55)
		if o2_upper < 0.05 and hrr_kw > 0.5:
			ilv_t = 1.0
	if regime == "ILV_LATENT" or bool(room_state.get("fire_latent_active", false)):
		ilv_t = maxf(ilv_t, 0.88)
	var alpha: float = clampf(
		maxf(maxf(alpha_from_optics, alpha_from_density * lerpf(0.18, 1.0, optical_block)), maxf(alpha_from_layer, alpha_from_mass * optical_block)),
		0.0,
		max_alpha
	)
	var ilv_exposure_t: float = ilv_t * immersion
	if ilv_exposure_t > 0.0:
		var severe_alpha: float = lerpf(0.84, max_alpha, maxf(immersion, smoke_density_t))
		alpha = maxf(alpha, severe_alpha * ilv_exposure_t)
	var display_block: float = clampf(
		maxf(
			maxf(optical_block, smoke_density_t * 0.34 * immersion),
			alpha_from_visibility * lerpf(0.05, 0.85, immersion)
		),
		0.0,
		1.0
	)
	var below_layer_t: float = clampf((smoke_layer_m - eye_height_m) / layer_transition_m, 0.0, 1.0)
	var overhead_smoke_block: float = alpha_from_visibility * lerpf(0.35, 0.12, below_layer_t)
	display_block = maxf(display_block, overhead_smoke_block)
	var fp_visibility_m: float = lerpf(max_visibility_m, visibility_m, display_block)
	if ilv_exposure_t > 0.0:
		var severe_cap_m: float = minf(visibility_m, severe_visibility_m)
		fp_visibility_m = minf(fp_visibility_m, lerpf(fp_visibility_m, severe_cap_m, ilv_exposure_t))
	return {
		"overlay_alpha": alpha,
		"heat_tint": heat_tint,
		"fp_visibility_m": fp_visibility_m,
		"raw_visibility_m": visibility_m,
		"optical_block": optical_block,
		"ilv_block": ilv_exposure_t
	}


static func format_visibility(visibility_m: float, clear_visibility_m: float) -> String:
	var clear_m: float = maxf(1.0, clear_visibility_m)
	var v: float = clampf(visibility_m, 0.0, clear_m)
	if v >= clear_m - 0.25:
		return "Vis FP >%.0fm" % clear_m
	if v < 10.0:
		return "Vis FP %.1fm" % maxf(0.1, v)
	return "Vis FP %.0fm" % v


static func _is_ventilation_limited_regime(regime: String) -> bool:
	return regime in [
		"VENTILATION_STRESSED",
		"VENTILATION_CONTROLLED_BURNING",
		"VENTILATION_INDUCED_GROWTH",
		"ILV_LATENT",
		"BACKDRAFT_RISK",
		"BACKDRAFT_EVENT",
	]

extends RefCounted


static func animate(item: Dictionary, global_phase: float, settings: Dictionary) -> void:
	var fire_root := item.get("fire_root") as Node3D
	var fire_core := item.get("fire_core") as MeshInstance3D
	var fire_glow := item.get("fire_glow") as MeshInstance3D
	var fire_cap := item.get("fire_cap") as MeshInstance3D
	var fire_light := item.get("fire_light") as OmniLight3D
	if fire_root == null or fire_core == null or fire_glow == null:
		return

	var meters_to_units: float = float(settings.get("meters_to_units", 1.0))
	var fire_base_radius_m: float = float(settings.get("fire_base_radius_m", 0.22))
	var default_room_height_m: float = float(settings.get("default_room_height_m", 2.4))
	var fire_flicker_strength: float = float(settings.get("fire_flicker_strength", 0.12))
	var fire_ceiling_cap_thickness_m: float = float(settings.get("fire_ceiling_cap_thickness_m", 0.22))

	var height_m: float = float(item.get("fire_height_m", 0.0))
	var radius_m: float = float(item.get("fire_radius_m", fire_base_radius_m))
	var room_height_m: float = float(item.get("fire_available_height_m", item.get("height_m", default_room_height_m)))
	var cap_radius_m: float = float(item.get("fire_cap_radius_m", 0.0))
	var cap_weight: float = clampf(float(item.get("fire_cap_weight", 0.0)), 0.0, 1.0)
	var phase: float = float(item.get("fire_phase", 0.0))
	var flicker: float = 1.0 \
			+ sin(global_phase * 8.5 + phase) * fire_flicker_strength \
			+ sin(global_phase * 15.0 + phase * 0.7) * fire_flicker_strength * 0.45
	var max_column_h: float = maxf(0.04, room_height_m)
	var core_h: float = minf(max_column_h, maxf(0.04, height_m * flicker))
	var glow_h: float = minf(max_column_h, maxf(0.04, height_m * 0.76 * (1.0 + (flicker - 1.0) * 0.55)))
	var core_r: float = maxf(0.03, radius_m * flicker)
	var glow_r: float = maxf(0.04, radius_m * 1.85)

	fire_core.scale = Vector3(core_r, core_h, core_r) * meters_to_units
	fire_core.position = Vector3(0.0, core_h * meters_to_units * 0.5, 0.0)
	fire_glow.scale = Vector3(glow_r, glow_h, glow_r) * meters_to_units
	fire_glow.position = Vector3(0.0, glow_h * meters_to_units * 0.38, 0.0)

	var tongues: Array = item.get("fire_tongues", [])
	for i in range(tongues.size()):
		var tongue := tongues[i] as MeshInstance3D
		if tongue == null:
			continue
		var tongue_seed: float = float(tongue.get_meta("seed", i))
		var wave: float = 1.0 + sin(global_phase * (7.0 + fposmod(tongue_seed, 4.0)) + tongue_seed) * fire_flicker_strength * 0.85
		var angle: float = tongue_seed * 1.97 + sin(global_phase * 1.8 + tongue_seed) * 0.28
		var orbit_r: float = radius_m * (0.22 + fposmod(tongue_seed * 0.17, 0.38))
		var tongue_h: float = minf(max_column_h, maxf(0.04, height_m * lerpf(0.48, 0.92, fposmod(tongue_seed * 0.29, 1.0)) * wave))
		var tongue_r: float = maxf(0.025, radius_m * lerpf(0.34, 0.68, fposmod(tongue_seed * 0.41, 1.0)))
		tongue.visible = height_m > 0.05
		tongue.position = Vector3(
			cos(angle) * orbit_r * meters_to_units,
			tongue_h * meters_to_units * 0.48,
			sin(angle) * orbit_r * meters_to_units
		)
		tongue.scale = Vector3(tongue_r, tongue_h, tongue_r * 0.72) * meters_to_units
		tongue.rotation_degrees.y = rad_to_deg(angle) + 90.0

	if fire_light != null:
		var base_energy: float = float(item.get("fire_light_energy_target", fire_light.light_energy))
		fire_light.light_energy = base_energy * clampf(0.92 + (flicker - 1.0) * 0.85, 0.65, 1.35)

	if fire_cap != null:
		fire_cap.visible = cap_weight > 0.03 and cap_radius_m > 0.03
		if fire_cap.visible:
			var cap_wave: float = 1.0 + sin(global_phase * 5.4 + phase) * fire_flicker_strength * 0.22
			var cap_h: float = fire_ceiling_cap_thickness_m * lerpf(0.65, 1.25, cap_weight)
			var ceiling_y_m: float = maxf(cap_h, room_height_m)
			var cap_r: float = cap_radius_m * cap_wave
			fire_cap.scale = Vector3(cap_r, cap_h, cap_r * 0.82) * meters_to_units
			fire_cap.position = Vector3(0.0, (ceiling_y_m - cap_h * 0.5) * meters_to_units, 0.0)

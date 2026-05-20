extends RefCounted

const SmokePuffSpriteFactory := preload("res://view/3d/smoke/SmokePuffSpriteFactory.gd")


static func animate(item: Dictionary, global_phase: float, settings: Dictionary) -> void:
	var puffs_root := item.get("smoke_puffs_root") as Node3D
	if puffs_root == null or not puffs_root.visible:
		return
	var puffs: Array = item.get("smoke_puffs", [])
	if puffs.is_empty():
		return

	var meters_to_units: float = float(settings.get("meters_to_units", 1.0))
	var room_inset_m: float = float(settings.get("room_inset_m", 0.0))
	var default_room_height_m: float = float(settings.get("default_room_height_m", 2.4))
	var smoke_min_visible_depth_m: float = float(settings.get("smoke_min_visible_depth_m", 0.02))
	var smoke_puff_color: Color = settings.get("smoke_puff_color", Color(0.66, 0.68, 0.70, 0.18))
	var origin_offset_m: Vector2 = settings.get("origin_offset_m", Vector2.ZERO)
	var floor_level_m: float = float(item.get("floor_level_m", 0.0))

	var rect := Rect2(item.get("rect", Rect2()))
	var depth_m: float = float(item.get("smoke_visual_depth_m", 0.0))
	var bottom_m: float = float(item.get("smoke_bottom_m", float(item.get("height_m", default_room_height_m))))
	var height_m: float = float(item.get("height_m", default_room_height_m))
	var alpha: float = float(item.get("smoke_alpha", smoke_puff_color.a))
	if depth_m <= smoke_min_visible_depth_m:
		puffs_root.visible = false
		return

	var usable_w: float = maxf(0.08, rect.size.x - room_inset_m * 2.0)
	var usable_d: float = maxf(0.08, rect.size.y - room_inset_m * 2.0)
	var puff_base: float = clampf(minf(rect.size.x, rect.size.y) * 0.18, 0.26, 0.72)
	var smoke_texture: Texture2D = SmokePuffSpriteFactory.texture_for_alpha(alpha)
	for i in range(puffs.size()):
		var puff := puffs[i] as Sprite3D
		if puff == null:
			continue
		var seed: float = float(puff.get_meta("seed", i))
		var phase: float = global_phase * (0.34 + fposmod(seed, 5.0) * 0.035) + seed
		var x_frac: float = fposmod(seed * 0.618 + sin(phase) * 0.070, 1.0)
		var z_frac: float = fposmod(seed * 0.382 + cos(phase * 0.83) * 0.070, 1.0)
		var y_frac: float = 0.12 + fposmod(seed * 0.271, 0.78)
		var x_m: float = rect.position.x + room_inset_m + x_frac * usable_w
		var z_m: float = rect.position.y + room_inset_m + z_frac * usable_d
		var y_m: float = bottom_m + depth_m * y_frac + sin(phase * 1.7) * minf(depth_m * 0.055, 0.055)
		y_m = clampf(y_m, bottom_m + 0.06, height_m - 0.18)
		puff.position = _to_world(Vector3(x_m, floor_level_m + y_m, z_m), meters_to_units, origin_offset_m)
		var wobble: float = 1.0 + sin(phase * 1.3) * 0.10
		var sprite_scale: float = puff_base * lerpf(0.58, 1.05, fposmod(seed * 0.13, 1.0)) * wobble
		puff.scale = Vector3.ONE * sprite_scale * meters_to_units
		puff.rotation_degrees.z = sin(phase * 0.42) * 9.0 + seed * 3.0
		puff.texture = smoke_texture
		var frame_count: int = maxi(1, puff.hframes * puff.vframes)
		puff.frame = int(fposmod(floor(global_phase * 5.0 + seed), float(frame_count)))
		var y_density_t: float = y_frac * y_frac * (3.0 - 2.0 * y_frac)
		var puff_alpha: float = clampf(alpha * lerpf(0.16, 0.82, y_density_t) * lerpf(0.62, 1.0, fposmod(seed * 0.47, 1.0)), 0.025, 0.40)
		puff.modulate = Color(0.66, 0.68, 0.70, puff_alpha)


static func _to_world(meters: Vector3, meters_to_units: float, origin_offset_m: Vector2) -> Vector3:
	return Vector3(
		(meters.x + origin_offset_m.x) * meters_to_units,
		meters.y * meters_to_units,
		(meters.z + origin_offset_m.y) * meters_to_units
	)

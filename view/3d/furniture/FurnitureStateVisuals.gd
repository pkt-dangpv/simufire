extends RefCounted


static func color_for_state(state_name: String) -> Color:
	match state_name:
		"flaming":    return Color(1.00, 0.22, 0.08, 1.0)
		"pyrolyzing": return Color(1.00, 0.54, 0.10, 1.0)
		"heating":    return Color(1.00, 0.80, 0.22, 1.0)
		"decaying":   return Color(0.72, 0.36, 0.16, 1.0)
		"burned_out": return Color(0.18, 0.18, 0.18, 1.0)
		_:            return Color(0.55, 0.52, 0.48, 1.0)


static func apply(
	root: Node3D,
	state_name: String,
	state_color: Color,
	remaining_ratio: float,
	is_ignition_source: bool
) -> void:
	var heat_t: float = 0.0
	match state_name:
		"flaming":
			heat_t = 1.0
		"pyrolyzing":
			heat_t = 0.65
		"heating":
			heat_t = 0.32
		"decaying":
			heat_t = 0.18
		_:
			heat_t = 0.0
	var char_t: float = clampf(1.0 - remaining_ratio, 0.0, 1.0)
	_apply_materials_recursive(root, state_name, state_color, heat_t, char_t)

	var glow := root.get_node_or_null("HeatGlow") as MeshInstance3D
	if glow != null:
		glow.visible = heat_t > 0.05 or is_ignition_source
		var mat := glow.material_override as StandardMaterial3D
		if mat != null:
			var alpha: float = clampf(heat_t * 0.30 + (0.12 if is_ignition_source else 0.0), 0.0, 0.48)
			mat.albedo_color = Color(state_color.r, state_color.g * 0.60, state_color.b * 0.30, alpha)
			mat.emission_energy_multiplier = heat_t * 0.75 + (0.18 if is_ignition_source else 0.0)


static func _apply_materials_recursive(
	root: Node,
	state_name: String,
	state_color: Color,
	heat_t: float,
	char_t: float
) -> void:
	for child in root.get_children():
		if child is MeshInstance3D:
			var mesh_node := child as MeshInstance3D
			if mesh_node.name == "HeatGlow":
				continue
			var mat := mesh_node.material_override as StandardMaterial3D
			if mat != null:
				var base_color: Color = Color(mesh_node.get_meta("base_color", Color(0.55, 0.52, 0.48, 1.0)))
				var char_color: Color = Color(0.10, 0.09, 0.08, 1.0)
				var final_color: Color = base_color.lerp(char_color, clampf(char_t * 0.75, 0.0, 0.85))
				final_color = final_color.lerp(state_color, heat_t * 0.42)
				if state_name == "burned_out":
					final_color = Color(0.11, 0.11, 0.10, 1.0)
				mat.albedo_color = final_color
				mat.emission_enabled = heat_t > 0.05
				if mat.emission_enabled:
					mat.emission = Color(state_color.r, state_color.g * 0.65, state_color.b * 0.20, 1.0)
					mat.emission_energy_multiplier = heat_t * (1.55 if state_name == "flaming" else 0.65)
				else:
					mat.emission_energy_multiplier = 0.0
		if child.get_child_count() > 0:
			_apply_materials_recursive(child, state_name, state_color, heat_t, char_t)

extends RefCounted


static func apply_to_node(root: Node, state_name: String, remaining_ratio: float) -> void:
	if root == null:
		return
	var heat_t: float = heat_intensity(state_name)
	var char_t: float = clampf(1.0 - remaining_ratio, 0.0, 1.0)
	_apply_material_recursive(root, heat_t, char_t, heat_color(state_name))


static func heat_intensity(state_name: String) -> float:
	match state_name:
		"flaming":
			return 1.0
		"pyrolyzing":
			return 0.65
		"heating":
			return 0.32
		"decaying":
			return 0.18
		_:
			return 0.0


static func heat_color(state_name: String) -> Color:
	match state_name:
		"flaming":
			return Color(1.0, 0.24, 0.08, 1.0)
		"pyrolyzing":
			return Color(1.0, 0.52, 0.10, 1.0)
		"heating":
			return Color(1.0, 0.78, 0.22, 1.0)
		"decaying":
			return Color(0.72, 0.36, 0.16, 1.0)
		_:
			return Color(0.55, 0.52, 0.48, 1.0)


static func _apply_material_recursive(root: Node, heat_t: float, char_t: float, heat_col: Color) -> void:
	for child in root.get_children():
		if child is MeshInstance3D:
			var mesh_node := child as MeshInstance3D
			var mat := mesh_node.material_override as StandardMaterial3D
			if mat != null:
				var base_color: Color = Color(mesh_node.get_meta("base_color", Color(0.55, 0.52, 0.48, 1.0)))
				var final_color: Color = base_color.lerp(Color(0.10, 0.09, 0.08, base_color.a), clampf(char_t * 0.75, 0.0, 0.85))
				final_color = final_color.lerp(heat_col, heat_t * 0.38)
				if heat_t <= 0.001 and char_t <= 0.001:
					final_color = base_color
				mat.albedo_color = Color(final_color.r, final_color.g, final_color.b, base_color.a)
				mat.emission_enabled = heat_t > 0.05
				if mat.emission_enabled:
					mat.emission = Color(heat_col.r, heat_col.g * 0.65, heat_col.b * 0.20, 1.0)
					mat.emission_energy_multiplier = heat_t * 1.25
				else:
					mat.emission_energy_multiplier = 0.0
		if child.get_child_count() > 0:
			_apply_material_recursive(child, heat_t, char_t, heat_col)

extends RefCounted


static func try_build(parent: Node3D, kind_name: String, size_m: Vector2, meters_to_units: float) -> bool:
	if parent == null:
		return false
	var asset_kind: String = _asset_kind_for(kind_name)
	var scene_path: String = "res://assets/fp/furniture/%s.tscn" % asset_kind
	if not ResourceLoader.exists(scene_path):
		return false
	var packed := ResourceLoader.load(scene_path) as PackedScene
	if packed == null:
		return false
	var instance := packed.instantiate() as Node3D
	if instance == null:
		return false
	instance.name = "Asset_%s" % asset_kind
	instance.scale = Vector3(maxf(0.05, size_m.x), 1.0, maxf(0.05, size_m.y)) * meters_to_units
	_prepare_asset_materials(instance)
	parent.add_child(instance)
	return true


static func _asset_kind_for(kind_name: String) -> String:
	match kind_name:
		"storage":
			return "dresser"
		"containers":
			return "plastic_bin"
		"table":
			return "table"
		_:
			return kind_name


static func _prepare_asset_materials(root: Node) -> void:
	if root == null:
		return
	for child in root.get_children():
		if child is MeshInstance3D:
			var mesh_node := child as MeshInstance3D
			var mat := mesh_node.material_override as StandardMaterial3D
			if mat != null:
				var material_copy := mat.duplicate() as StandardMaterial3D
				mesh_node.material_override = material_copy
				if not mesh_node.has_meta("base_color"):
					mesh_node.set_meta("base_color", material_copy.albedo_color)
		if child.get_child_count() > 0:
			_prepare_asset_materials(child)

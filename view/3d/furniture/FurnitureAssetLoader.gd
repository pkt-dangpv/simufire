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
	# Añadimos a la escena antes de medir para que Godot calcule el AABB real
	parent.add_child(instance)
	_fit_instance(instance, size_m, meters_to_units)
	_prepare_asset_materials(instance)
	return true


# Ajusta un modelo GLB importado para que encaje en el slot del escenario:
#  - escala UNIFORME (preserva las proporciones reales, sin deformar)
#  - rota 90° si el eje largo del modelo no coincide con el del slot
#  - re-centra el footprint en el origen y apoya la base en el suelo (Y=0)
static func _fit_instance(instance: Node3D, size_m: Vector2, meters_to_units: float) -> void:
	var aabb: AABB = _get_combined_aabb(instance)
	var nx: float = maxf(0.001, aabb.size.x)
	var nz: float = maxf(0.001, aabb.size.z)
	var sx: float = maxf(0.05, size_m.x)
	var sz: float = maxf(0.05, size_m.y)

	# Alinea el eje largo del modelo con el eje largo del slot.
	var yaw: float = 0.0
	var eff_nx: float = nx
	var eff_nz: float = nz
	if (nx >= nz) != (sx >= sz):
		yaw = PI * 0.5
		eff_nx = nz
		eff_nz = nx

	# Escala uniforme que preserva el área del footprint objetivo (sin distorsión).
	var s: float = sqrt((sx / eff_nx) * (sz / eff_nz)) * meters_to_units

	var basis := Basis(Vector3.UP, yaw).scaled(Vector3(s, s, s))
	instance.transform.basis = basis

	# Re-centra: lleva el centro del footprint al origen y la base al suelo.
	var center: Vector3 = aabb.position + aabb.size * 0.5
	var anchor := Vector3(center.x, aabb.position.y, center.z)
	instance.position = -(basis * anchor)


static func _get_combined_aabb(root: Node3D) -> AABB:
	# Acumula transforms LOCALES desde el root (no usa global_transform, que
	# falla si el nodo aún no está dentro del árbol de escena).
	var state := [AABB(), false]
	_accumulate_aabb(root, Transform3D.IDENTITY, state)
	return state[0]


static func _accumulate_aabb(node: Node, xform: Transform3D, state: Array) -> void:
	for child in node.get_children():
		var child_xform: Transform3D = xform
		if child is Node3D:
			child_xform = xform * (child as Node3D).transform
		if child is MeshInstance3D:
			var mi := child as MeshInstance3D
			if mi.mesh != null:
				var aabb: AABB = _transform_aabb(child_xform, mi.get_aabb())
				if not state[1]:
					state[0] = aabb
					state[1] = true
				else:
					state[0] = state[0].merge(aabb)
		if child.get_child_count() > 0:
			_accumulate_aabb(child, child_xform, state)


static func _transform_aabb(xform: Transform3D, aabb: AABB) -> AABB:
	var p := aabb.position
	var s := aabb.size
	var corners := [
		xform * p,
		xform * Vector3(p.x + s.x, p.y, p.z),
		xform * Vector3(p.x, p.y + s.y, p.z),
		xform * Vector3(p.x, p.y, p.z + s.z),
		xform * Vector3(p.x + s.x, p.y + s.y, p.z),
		xform * Vector3(p.x + s.x, p.y, p.z + s.z),
		xform * Vector3(p.x, p.y + s.y, p.z + s.z),
		xform * Vector3(p.x + s.x, p.y + s.y, p.z + s.z),
	]
	var mn: Vector3 = corners[0]
	var mx: Vector3 = corners[0]
	for c: Vector3 in corners:
		mn = mn.min(c)
		mx = mx.max(c)
	return AABB(mn, mx - mn)


static func _asset_kind_for(kind_name: String) -> String:
	match kind_name:
		"storage":
			return "dresser"
		"containers":
			return "plastic_bin"
		"table":
			return "table"
		"bathtub", "bath":
			return "bathtub"
		"toilet":
			return "toilet"
		"sink", "bathroom_sink":
			return "bathroom_sink"
		"shower":
			return "shower"
		"bathroom_cabinet":
			return "bathroom_cabinet"
		"desk":
			return "desk"
		"chair":
			return "chair"
		"chair_desk":
			return "chair_desk"
		"bed_single":
			return "bed_single"
		"bed_bunk":
			return "bed_bunk"
		"fridge", "kitchen_fridge":
			return "kitchen_fridge"
		"stove", "kitchen_stove":
			return "kitchen_stove"
		"kitchen_sink":
			return "kitchen_sink"
		"washer":
			return "washer"
		"dryer":
			return "dryer"
		"lamp", "lamp_floor":
			return "lamp_floor"
		"lamp_table":
			return "lamp_table"
		"plant":
			return "plant"
		"side_table":
			return "side_table"
		"bench":
			return "bench"
		_:
			return kind_name


static func _prepare_asset_materials(root: Node) -> void:
	if root == null:
		return
	for child in root.get_children():
		if child is MeshInstance3D:
			var mesh_node := child as MeshInstance3D
			# BoxMesh primitivos usan material_override
			var mat := mesh_node.material_override as StandardMaterial3D
			if mat != null:
				var material_copy := mat.duplicate() as StandardMaterial3D
				mesh_node.material_override = material_copy
				if not mesh_node.has_meta("base_color"):
					mesh_node.set_meta("base_color", material_copy.albedo_color)
			else:
				# GLBs importados usan surface_material_override por superficie
				var mesh := mesh_node.mesh
				if mesh != null:
					for surf_idx in mesh.get_surface_count():
						var surf_mat := mesh_node.get_surface_override_material(surf_idx)
						if surf_mat == null:
							surf_mat = mesh.surface_get_material(surf_idx)
						if surf_mat is StandardMaterial3D:
							var material_copy := surf_mat.duplicate() as StandardMaterial3D
							mesh_node.set_surface_override_material(surf_idx, material_copy)
							if not mesh_node.has_meta("base_color"):
								mesh_node.set_meta("base_color", material_copy.albedo_color)
		if child.get_child_count() > 0:
			_prepare_asset_materials(child)

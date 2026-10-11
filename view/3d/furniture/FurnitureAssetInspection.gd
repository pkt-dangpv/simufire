extends RefCounted

## Inspeccion de solo lectura: usa el cargador real, no otra ley de ajuste.
## No resuelve distribucion de sala ni cambia ficheros/modelo de incendio.
const Loader := preload("res://view/3d/furniture/FurnitureAssetLoader.gd")
const Dimensions := preload("res://view/furniture/FurnitureDimensions.gd")


static func inspect(archetype: String, footprint_m: Vector2) -> Dictionary:
	var path: String = Loader.model_path(archetype)
	var target: Vector3 = Dimensions.target_size_m(archetype, footprint_m)
	var report: Dictionary = {
		"archetype": archetype, "scene_path": path,
		"requested_footprint_m": _vector2(footprint_m),
		"target_size_m": _vector3(target), "errors": [],
		"scope": "asset_loader_only_not_room_placement",
	}
	report["transform_mode"] = Loader.declared_transform_mode(archetype)
	var packed := ResourceLoader.load(path) as PackedScene
	if packed == null:
		report["errors"].append("missing_or_invalid_scene")
		return report
	var spawned: Node = packed.instantiate()
	if not spawned is Node3D:
		report["errors"].append("root_must_be_node3d")
		spawned.free()
		return report
	var original := spawned as Node3D
	var local_bounds: AABB = Loader._get_combined_aabb(original)
	var authored_bounds: AABB = Loader._transform_aabb(original.transform, local_bounds)
	report["native_local_bounds_m"] = _bounds(local_bounds)
	report["authored_bounds_m"] = _bounds(authored_bounds)
	report["authored_root_transform"] = _transform(original.transform)
	# La raiz importada se sustituye en _fit_instance, no se compone con ella.
	report["authored_root_is_identity"] = original.transform.is_equal_approx(Transform3D.IDENTITY)
	original.free()
	var scratch := Node3D.new()
	var predicted: Vector3 = Loader.resolved_size_m(archetype, target)
	var achieved: Vector3 = Loader.try_build(scratch, archetype, target, 1.0)
	# Mantener recursos de material vivos hasta destruir sus instancias. En el
	# renderer headless se consultan aun durante la destruccion de la malla.
	var material_keepalive: Array[Material] = []
	_keep_materials(scratch, material_keepalive)
	var drawn: AABB = Loader._get_combined_aabb(scratch)
	report["predicted_size_m"] = _vector3(predicted)
	report["achieved_size_m"] = _vector3(achieved)
	report["drawn_bounds_m"] = _bounds(drawn)
	report["tiled"] = Dimensions.is_tiled(archetype)
	var modules: Array = []
	for child in scratch.get_children():
		if child is Node3D:
			modules.append({"name": String(child.name), "transform": _transform(child.transform)})
	report["runtime_instances"] = modules
	if achieved == Vector3.ZERO:
		report["errors"].append("loader_did_not_build_asset")
	elif not drawn.size.is_equal_approx(achieved):
		# La caja informada por el cargador y la realmente dibujada son distintas.
		# Se registra, no se fuerza una medida para ocultar la discrepancia.
		report["reported_and_drawn_size_differ"] = true
	else:
		report["reported_and_drawn_size_differ"] = false
	scratch.free()
	material_keepalive.clear()
	return report


static func _keep_materials(node: Node, keepalive: Array[Material]) -> void:
	if node is MeshInstance3D:
		var mesh_node := node as MeshInstance3D
		if mesh_node.material_override != null:
			keepalive.append(mesh_node.material_override)
		if mesh_node.mesh != null:
			for index in mesh_node.mesh.get_surface_count():
				var material: Material = mesh_node.get_surface_override_material(index)
				if material == null:
					material = mesh_node.mesh.surface_get_material(index)
				if material != null:
					keepalive.append(material)
	for child in node.get_children():
		_keep_materials(child, keepalive)


static func _bounds(box: AABB) -> Dictionary:
	return {"position": _vector3(box.position), "size": _vector3(box.size)}


static func _transform(value: Transform3D) -> Dictionary:
	return {"origin": _vector3(value.origin), "basis_x": _vector3(value.basis.x),
		"basis_y": _vector3(value.basis.y), "basis_z": _vector3(value.basis.z),
		"scale": _vector3(value.basis.get_scale()),
		"rotation_deg": _vector3(value.basis.get_euler() * (180.0 / PI))}


static func _vector3(value: Vector3) -> Array:
	return [value.x, value.y, value.z]


static func _vector2(value: Vector2) -> Array:
	return [value.x, value.y]

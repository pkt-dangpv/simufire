extends RefCounted

const FireMaterialFactory := preload("res://view/3d/fire/FireMaterialFactory.gd")


static func create_flame_mesh(node_name: String, color: Color, core_color: Color) -> MeshInstance3D:
	var mesh := _create_cross_flame_mesh()
	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = mesh
	node.material_override = FireMaterialFactory.create_flame(color, core_color)
	_disable_shadow_casting(node)
	return node


static func create_ceiling_cap_mesh(node_name: String, color: Color, core_color: Color) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.82
	mesh.bottom_radius = 1.0
	mesh.height = 1.0
	mesh.radial_segments = 22
	mesh.rings = 2
	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = mesh
	node.material_override = FireMaterialFactory.create_ceiling_cap(color, core_color)
	_disable_shadow_casting(node)
	return node


static func _create_cross_flame_mesh() -> ArrayMesh:
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for i in range(3):
		var angle: float = float(i) * PI / 3.0
		var right := Vector3(cos(angle), 0.0, sin(angle))
		var start_index: int = vertices.size()
		vertices.append(-right)
		vertices.append(right)
		vertices.append(right + Vector3.UP)
		vertices.append(-right + Vector3.UP)
		uvs.append(Vector2(0.0, 0.0))
		uvs.append(Vector2(1.0, 0.0))
		uvs.append(Vector2(1.0, 1.0))
		uvs.append(Vector2(0.0, 1.0))
		indices.append_array(PackedInt32Array([
			start_index,
			start_index + 1,
			start_index + 2,
			start_index,
			start_index + 2,
			start_index + 3
		]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _disable_shadow_casting(root: Node) -> void:
	if root is GeometryInstance3D:
		(root as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in root.get_children():
		_disable_shadow_casting(child)

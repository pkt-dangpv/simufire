extends RefCounted

const VERTICAL_SEGMENT_COUNT: int = 18
const VERTICAL_RING_COUNT: int = 9

static func create(
	thin_axis_is_x: bool,
	opening_width_m: float,
	blend_depth_m: float,
	bottom_neg_local_y_m: float,
	bottom_pos_local_y_m: float,
	top_local_y_m: float,
	meters_to_units: float
) -> ArrayMesh:
	var half_w: float = maxf(0.025, opening_width_m * 0.5)
	var half_d: float = maxf(0.025, blend_depth_m * 0.5)
	var y_neg: float = minf(bottom_neg_local_y_m, top_local_y_m - 0.025)
	var y_pos: float = minf(bottom_pos_local_y_m, top_local_y_m - 0.025)
	var y_top: float = top_local_y_m

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	var n0: Vector3
	var n1: Vector3
	var p0: Vector3
	var p1: Vector3
	var tn0: Vector3
	var tn1: Vector3
	var tp0: Vector3
	var tp1: Vector3
	if thin_axis_is_x:
		n0 = Vector3(-half_d, y_neg, -half_w)
		n1 = Vector3(-half_d, y_neg, half_w)
		p0 = Vector3(half_d, y_pos, -half_w)
		p1 = Vector3(half_d, y_pos, half_w)
		tn0 = Vector3(-half_d, y_top, -half_w)
		tn1 = Vector3(-half_d, y_top, half_w)
		tp0 = Vector3(half_d, y_top, -half_w)
		tp1 = Vector3(half_d, y_top, half_w)
	else:
		n0 = Vector3(-half_w, y_neg, -half_d)
		n1 = Vector3(half_w, y_neg, -half_d)
		p0 = Vector3(-half_w, y_pos, half_d)
		p1 = Vector3(half_w, y_pos, half_d)
		tn0 = Vector3(-half_w, y_top, -half_d)
		tn1 = Vector3(half_w, y_top, -half_d)
		tp0 = Vector3(-half_w, y_top, half_d)
		tp1 = Vector3(half_w, y_top, half_d)

	_append_bridge_quad(vertices, normals, uvs, indices, n0, n1, tn1, tn0)
	_append_bridge_quad(vertices, normals, uvs, indices, p0, tp0, tp1, p1)
	_append_bridge_quad(vertices, normals, uvs, indices, n0, tn0, tp0, p0)
	_append_bridge_quad(vertices, normals, uvs, indices, n1, p1, tp1, tn1)
	# Intrados: une los dos bordes bajos (uno por sala) en una sola cara
	# inclinada. Sin ella el vano eran dos telones paralelos vistos desde
	# abajo -justo la altura de los ojos bajo la capa- y el shader no podia
	# aplicar bottom_surface_strength por falta de cara horizontal.
	if thin_axis_is_x:
		_append_bridge_quad(vertices, normals, uvs, indices, n0, p0, p1, n1)
	else:
		_append_bridge_quad(vertices, normals, uvs, indices, n0, n1, p1, p0)

	return _build_mesh(vertices, normals, uvs, indices, meters_to_units)


static func create_vertical(
	opening_width_m: float,
	opening_depth_m: float,
	height_m: float,
	meters_to_units: float
) -> ArrayMesh:
	var half_w: float = maxf(0.08, opening_width_m * 0.5)
	var half_d: float = maxf(0.08, opening_depth_m * 0.5)
	var safe_height_m: float = maxf(0.12, height_m)

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	for ring_i in range(VERTICAL_RING_COUNT):
		var v: float = float(ring_i) / float(VERTICAL_RING_COUNT - 1)
		var y_m: float = -safe_height_m * 0.5 + safe_height_m * v
		var rise_t: float = v * v * (3.0 - 2.0 * v)
		var taper: float = lerpf(0.58, 1.16, rise_t)
		var wobble: float = 1.0 + sin(v * PI * 4.0) * 0.045
		var radius_x_m: float = half_w * taper * wobble
		var radius_z_m: float = half_d * taper * (1.0 + cos(v * PI * 3.0) * 0.035)
		for segment_i in range(VERTICAL_SEGMENT_COUNT + 1):
			var u: float = float(segment_i) / float(VERTICAL_SEGMENT_COUNT)
			var angle: float = u * PI * 2.0
			var radial := Vector3(cos(angle), 0.0, sin(angle))
			vertices.append(Vector3(radial.x * radius_x_m, y_m, radial.z * radius_z_m))
			normals.append(radial.normalized())
			uvs.append(Vector2(u, v))

	for ring_i in range(VERTICAL_RING_COUNT - 1):
		for segment_i in range(VERTICAL_SEGMENT_COUNT):
			var start: int = ring_i * (VERTICAL_SEGMENT_COUNT + 1) + segment_i
			var next_ring: int = start + VERTICAL_SEGMENT_COUNT + 1
			indices.append_array(PackedInt32Array([
				start,
				next_ring,
				next_ring + 1,
				start,
				next_ring + 1,
				start + 1
			]))

	return _build_mesh(vertices, normals, uvs, indices, meters_to_units)


static func _build_mesh(
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	indices: PackedInt32Array,
	meters_to_units: float
) -> ArrayMesh:
	for i in range(vertices.size()):
		vertices[i] = vertices[i] * meters_to_units

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _append_bridge_quad(
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	indices: PackedInt32Array,
	a: Vector3,
	b: Vector3,
	c: Vector3,
	d: Vector3
) -> void:
	var normal: Vector3 = (b - a).cross(c - a).normalized()
	if normal.length_squared() <= 0.000001:
		normal = Vector3.UP
	var start: int = vertices.size()
	vertices.append_array(PackedVector3Array([a, b, c, d]))
	normals.append_array(PackedVector3Array([normal, normal, normal, normal]))
	uvs.append_array(PackedVector2Array([
		Vector2(0.0, 0.0),
		Vector2(1.0, 0.0),
		Vector2(1.0, 1.0),
		Vector2(0.0, 1.0)
	]))
	indices.append_array(PackedInt32Array([
		start,
		start + 1,
		start + 2,
		start,
		start + 2,
		start + 3
	]))

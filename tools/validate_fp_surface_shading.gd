extends Node
## Guardarrail de M-2 (docs/AUDITORIA_VISUAL_2026-08-29.md §7).
##
## Las superficies grandes de primera persona usan un shader propio que hace
## dos cosas que StandardMaterial3D no puede: proyectar el ruido en metros y
## oscurecer la franja cercana a las aristas, que es la oclusion de contacto
## que GL Compatibility no da (no hay SSAO).
##
## Lo que se fija aqui:
## - Muros, suelos y techos llevan ese shader cuando la oclusion esta activada.
## - Cada pieza publica SU tamano por instancia. Es el contrato critico: sin el,
##   el ancho de la franja de oclusion dejaria de medirse en metros y el
##   oscurecimiento saldria plano en vez de degradado, sin ningun error visible.
## - Con la oclusion desactivada se vuelve a StandardMaterial3D.

const BuildingModelScript := preload("res://sim/BuildingModel.gd")
const FirstPersonControllerScript := preload("res://view/fp/FirstPersonController.gd")
const FPSurfaceShader: Shader = preload("res://view/fp/fp_surface.gdshader")

var _failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	await get_tree().process_frame
	await _validate_shaded(true)
	await _validate_shaded(false)
	_finish()


func _validate_shaded(ao_enabled: bool) -> void:
	var building: BuildingModel = BuildingModelScript.new()
	_expect(building.load_template_data(_make_template()), "Surface shading template rejected")

	var fp: FirstPersonController = FirstPersonControllerScript.new()
	fp.name = "ValidateFPSurfaceShading_%s" % ("on" if ao_enabled else "off")
	fp.exterior_context_enabled = false
	fp.show_fp_detectors = false
	fp.show_fp_victims = false
	fp.surface_contact_ao_enabled = ao_enabled
	add_child(fp)
	await get_tree().process_frame
	fp.setup(building)
	await get_tree().physics_frame

	var world := fp.get_node_or_null("FirstPersonWorld")
	_expect(world != null, "FP world was not created")
	if world != null:
		var walls: Array[MeshInstance3D] = _find_meshes(world, "WallMesh")
		_expect(not walls.is_empty(), "No wall meshes were built")
		for mesh in walls:
			if ao_enabled:
				_check_shaded(mesh)
			else:
				_expect(
					mesh.material_override is StandardMaterial3D,
					"With contact AO off the surfaces must fall back to StandardMaterial3D"
				)

	remove_child(fp)
	fp.free()
	building.free()


func _check_shaded(mesh: MeshInstance3D) -> void:
	var material := mesh.material_override as ShaderMaterial
	_expect(material != null, "Wall surface is not using the FP surface shader")
	if material == null:
		return
	_expect(material.shader == FPSurfaceShader, "Wall surface uses a different shader")

	var declared: Variant = mesh.get_instance_shader_parameter("box_size_m")
	_expect(
		declared != null,
		"M-2 contract broken: the mesh does not publish box_size_m, so the contact band stops being measured in metres"
	)
	if declared == null:
		return
	var box: BoxMesh = mesh.mesh as BoxMesh
	_expect(box != null, "Wall mesh is not a BoxMesh")
	if box == null:
		return
	var size: Vector3 = Vector3(declared)
	_expect(
		size.is_equal_approx(box.size),
		"M-2 contract broken: box_size_m %s does not match the mesh size %s" % [str(size), str(box.size)]
	)


func _find_meshes(root_node: Node, token: String) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	_collect(root_node, token, result)
	return result


func _collect(node: Node, token: String, result: Array[MeshInstance3D]) -> void:
	var mesh := node as MeshInstance3D
	if mesh != null and String(mesh.name).contains(token):
		result.append(mesh)
	for child in node.get_children():
		_collect(child, token, result)


func _make_template() -> Dictionary:
	return {
		"version": 1,
		"building_type": "apartment",
		"outside_temp_c": 20.0,
		"outside_o2": 0.209,
		"stop_time_s": 0.0,
		"hvac_mode": "none",
		"hvac_data": {"exists": false, "on": false, "mode": "none"},
		"room_rect_m": {"0": {"x": 0.0, "y": 0.0, "w": 5.0, "h": 4.0}},
		"rooms_data": [
			{
				"id": 0, "name": "Salon", "kind": "salon", "height_m": 2.6,
				"floor_level_z_m": 0.0, "fuel_energy_MJ": 0.0, "max_hrr_kw": 0.0,
				"fuel_objects": []
			}
		],
		"openings_data": [],
		"detectors": [],
		"victims": [],
		"exterior_walls": []
	}


func _finish() -> void:
	if _failures.is_empty():
		print("FP SURFACE SHADING VALIDATION PASS")
		get_tree().quit(0)
		return
	push_error("FP SURFACE SHADING VALIDATION FAILED")
	for failure in _failures:
		push_error("- " + failure)
	get_tree().quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

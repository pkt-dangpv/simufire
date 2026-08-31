extends Node
## Guardarrail de FP-1 (docs/AUDITORIA_VISUAL_2026-08-29.md §5).
##
## Dos salas contiguas describen la MISMA medianera, cada una desde su lado.
## Si se construyen las dos cajas quedan exactamente coplanarias: z-fighting
## entre los colores de cada estancia al mover la camara, malla duplicada y
## colision duplicada. Aqui se fija que no haya dos tabiques con la misma caja,
## que la medianera exista (no se ha deduplicado de mas) y que el rodapie siga
## siendo de cada sala.

const BuildingModelScript := preload("res://sim/BuildingModel.gd")
const FirstPersonControllerScript := preload("res://view/fp/FirstPersonController.gd")

const SHARED_PLANE_X_M: float = 6.0

var _failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	await get_tree().process_frame

	var building: BuildingModel = BuildingModelScript.new()
	_expect(building.load_template_data(_make_template()), "FP party wall template rejected")

	var fp: FirstPersonController = FirstPersonControllerScript.new()
	fp.name = "ValidateFPPartyWalls"
	fp.exterior_context_enabled = false
	fp.show_fp_detectors = false
	fp.show_fp_victims = false
	add_child(fp)
	await get_tree().process_frame
	fp.setup(building)
	await get_tree().physics_frame

	var world := fp.get_node_or_null("FirstPersonWorld")
	_expect(world != null, "FP world was not created")
	if world != null:
		_validate_no_duplicate_walls(world)
		_validate_party_wall_exists(world)
		_validate_skirting_is_per_room(world)

	remove_child(fp)
	fp.free()
	building.free()
	_finish()


func _validate_no_duplicate_walls(world: Node) -> void:
	var seen: Dictionary = {}
	var duplicates: Array[String] = []
	for mesh in _find_meshes(world, "WallMesh"):
		var key: String = _box_key(mesh)
		if seen.has(key):
			duplicates.append(key)
		else:
			seen[key] = true
	_expect(
		duplicates.is_empty(),
		"FP-1 regression: %d coincident wall boxes (first: %s)" % [
			duplicates.size(), duplicates[0] if not duplicates.is_empty() else ""
		]
	)


## La deduplicacion no puede llevarse por delante la medianera: tiene que
## quedar exactamente una caja de tabique en el plano compartido.
func _validate_party_wall_exists(world: Node) -> void:
	var on_plane: int = 0
	for mesh in _find_meshes(world, "WallMesh"):
		var aabb: AABB = mesh.get_aabb()
		var center: Vector3 = mesh.global_transform * aabb.get_center()
		# El mundo esta centrado en el edificio (limites 0..10 en planta).
		if absf(center.x - (SHARED_PLANE_X_M - 5.0)) < 0.12 and aabb.size.y > 1.0:
			on_plane += 1
	_expect(on_plane >= 1, "Party wall between the two rooms disappeared")
	_expect(on_plane <= 2, "Party wall plane still has %d stacked boxes" % on_plane)


## El rodapie mira hacia dentro de cada estancia: en una medianera compartida
## tiene que seguir habiendo uno por sala, aunque el tabique sea unico.
##
## Se busca por geometria y no por nombre a proposito: Godot renombra a
## "@MeshInstance3D@NN" todo nodo cuyo nombre ya exista entre sus hermanos, y
## en el mundo FP hay decenas de "Skirting_top", asi que una busqueda por
## nombre solo encuentra el primero de cada lado (FP-8).
func _validate_skirting_is_per_room(world: Node) -> void:
	var near_plane: int = 0
	for mesh in _find_all_meshes(world):
		var size: Vector3 = mesh.get_aabb().size
		var is_skirting_profile: bool = absf(size.x - 0.028) < 0.002 and size.y < 0.30
		if not is_skirting_profile:
			continue
		var center: Vector3 = mesh.global_transform * mesh.get_aabb().get_center()
		if absf(center.x - (SHARED_PLANE_X_M - 5.0)) < 0.30:
			near_plane += 1
	_expect(
		near_plane >= 2,
		"Party wall lost the per-room skirting: expected one per side, found %d" % near_plane
	)


func _find_all_meshes(root_node: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	_collect_all_meshes(root_node, result)
	return result


func _collect_all_meshes(node: Node, result: Array[MeshInstance3D]) -> void:
	var mesh := node as MeshInstance3D
	if mesh != null:
		result.append(mesh)
	for child in node.get_children():
		_collect_all_meshes(child, result)


func _box_key(mesh: MeshInstance3D) -> String:
	var aabb: AABB = mesh.get_aabb()
	var center: Vector3 = mesh.global_transform * aabb.get_center()
	return "%.2f|%.2f|%.2f|%.2f|%.2f|%.2f" % [
		center.x, center.y, center.z, aabb.size.x, aabb.size.y, aabb.size.z
	]


func _find_meshes(root_node: Node, token: String) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	_collect_meshes(root_node, token, result)
	return result


func _collect_meshes(node: Node, token: String, result: Array[MeshInstance3D]) -> void:
	var mesh := node as MeshInstance3D
	# Godot renombra los nodos hermanos homonimos como "@Nombre@NN", asi que
	# aqui no vale comparar por prefijo: hay decenas de "Skirting_top".
	if mesh != null and String(mesh.name).contains(token):
		result.append(mesh)
	for child in node.get_children():
		_collect_meshes(child, token, result)


## Salon 6x4 y dormitorio 4x4 pegados por el plano x=6, unidos por una puerta.
func _make_template() -> Dictionary:
	return {
		"version": 1,
		"building_type": "apartment",
		"outside_temp_c": 20.0,
		"outside_o2": 0.209,
		"stop_time_s": 0.0,
		"hvac_mode": "none",
		"hvac_data": {"exists": false, "on": false, "mode": "none"},
		"room_rect_m": {
			"0": {"x": 0.0, "y": 0.0, "w": 6.0, "h": 4.0},
			"1": {"x": 6.0, "y": 0.0, "w": 4.0, "h": 4.0}
		},
		"rooms_data": [
			{
				"id": 0, "name": "Salon", "kind": "salon", "height_m": 2.62,
				"floor_level_z_m": 0.0, "fuel_energy_MJ": 0.0, "max_hrr_kw": 0.0,
				"fuel_objects": []
			},
			{
				"id": 1, "name": "Cocina", "kind": "cocina", "height_m": 2.62,
				"floor_level_z_m": 0.0, "fuel_energy_MJ": 0.0, "max_hrr_kw": 0.0,
				"fuel_objects": []
			}
		],
		"openings_data": [
			{"a": 0, "b": 1, "type": "door", "wall": "right", "offset_m": 1.6, "width_m": 0.92, "height_m": 2.05, "open_fraction": 1.0}
		],
		"detectors": [],
		"victims": [],
		"exterior_walls": []
	}


func _finish() -> void:
	if _failures.is_empty():
		print("FP PARTY WALLS VALIDATION PASS")
		get_tree().quit(0)
		return
	push_error("FP PARTY WALLS VALIDATION FAILED")
	for failure in _failures:
		push_error("- " + failure)
	get_tree().quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

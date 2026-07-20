extends Node

const BuildingModelScript := preload("res://sim/BuildingModel.gd")
const FirstPersonControllerScript := preload("res://view/fp/FirstPersonController.gd")

var _failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	await get_tree().process_frame
	var apartment := await _build_case("apartment")
	_validate_city(apartment)
	_cleanup_case(apartment)

	var house := await _build_case("single_family")
	_validate_residential(house)
	_cleanup_case(house)
	_finish()


func _build_case(building_type: String) -> Dictionary:
	var building: BuildingModel = BuildingModelScript.new()
	_expect(building.load_template_data(_make_template(building_type)), "%s exterior template rejected" % building_type)
	var host := Node3D.new()
	host.name = "ExteriorCase_" + building_type
	get_tree().root.add_child(host)
	var fp: FirstPersonController = FirstPersonControllerScript.new()
	fp.name = "FP_" + building_type
	fp.show_fp_detectors = false
	fp.show_fp_victims = false
	host.add_child(fp)
	await get_tree().process_frame
	fp.setup(building)
	await get_tree().physics_frame
	return {"building": building, "host": host, "fp": fp}


func _cleanup_case(ctx: Dictionary) -> void:
	var host := ctx.get("host") as Node
	if host != null:
		host.free()
	var building := ctx.get("building") as Node
	if building != null:
		building.free()


func _validate_city(ctx: Dictionary) -> void:
	var exterior := _exterior_root(ctx)
	if exterior == null:
		return
	var facades := _find_meshes(exterior, "CityFacadeBody_")
	_expect(facades.size() >= 4, "City exterior needs several facade modules")
	_expect(_find_meshes(exterior, "CityWindowGlass_").size() >= 24, "City facade windows missing")
	_expect(_find_meshes(exterior, "CityEntrance_").size() == facades.size(), "Each city module needs an entrance")
	_expect(_find_meshes(exterior, "CityCar_").size() >= 9, "City street scale objects missing")
	_expect(_find_meshes(exterior, "CityTree_").size() >= 8, "City tree trunks/crowns missing")
	_expect(_find_meshes(exterior, "CityCurbNear_").size() == 1, "Near city curb missing")
	_expect(_find_meshes(exterior, "CityCurbFar_").size() == 1, "Far city curb missing")
	_expect(_find_meshes(exterior, "OppositeFacade_").is_empty(), "Legacy monolithic facade must be retired")
	_expect(_find_meshes(exterior, "ResidentialHouseBody_").is_empty(), "Apartment exterior contains residential houses")
	_validate_pairwise_separation("city facade", facades)
	_validate_pairwise_separation("city skyline", _find_meshes(exterior, "Skyline_"))


func _validate_residential(ctx: Dictionary) -> void:
	var exterior := _exterior_root(ctx)
	if exterior == null:
		return
	var houses := _find_meshes(exterior, "ResidentialHouseBody_")
	var roofs := _find_meshes(exterior, "ResidentialRoof_")
	_expect(houses.size() == 3, "Residential exterior must create three full-size houses")
	_expect(roofs.size() == 3, "Residential houses need pitched roofs")
	_expect(_find_meshes(exterior, "ResidentialWindowGlass_").size() == 12, "Residential facade windows missing")
	_expect(_find_meshes(exterior, "ResidentialDoor_").size() == 3, "Residential front doors missing")
	_expect(_find_meshes(exterior, "ResidentialTree_").size() == 10, "Residential vegetation missing")
	_expect(_find_meshes(exterior, "ResidentialEntryPath_").size() == 1, "Residential entry path missing or duplicated")
	_expect(_find_meshes(exterior, "ResidentialStreet_").size() == 1, "Residential road missing or duplicated")
	_expect(_find_meshes(exterior, "ResidentialSidewalkNear_").size() == 1, "Near residential sidewalk missing")
	_expect(_find_meshes(exterior, "ResidentialSidewalkFar_").size() == 1, "Far residential sidewalk missing")
	_expect(_find_meshes(exterior, "CityFacadeBody_").is_empty(), "House exterior contains city facade modules")
	var world := _world_root(ctx)
	_expect(_find_meshes(world, "HouseStreet_").is_empty(), "Legacy duplicate house road still exists")
	_expect(_find_meshes(world, "HouseGarden_").is_empty(), "Legacy duplicate house garden still exists")
	_expect(_find_meshes(world, "NeighbourHouse_").is_empty(), "Legacy toy houses still exist")
	_validate_pairwise_separation("residential house", houses)
	for roof in roofs:
		var array_mesh := roof.mesh as ArrayMesh
		_expect(array_mesh != null and array_mesh.get_surface_count() == 1, "%s is not a valid gable mesh" % roof.name)


func _exterior_root(ctx: Dictionary) -> Node:
	var world := _world_root(ctx)
	_expect(world != null, "FP world missing")
	if world == null:
		return null
	var exterior := world.get_node_or_null("ExteriorContext")
	_expect(exterior != null, "ExteriorContext missing")
	return exterior


func _world_root(ctx: Dictionary) -> Node:
	var fp := ctx.get("fp") as Node
	return fp.get_node_or_null("FirstPersonWorld") if fp != null else null


func _validate_pairwise_separation(label: String, meshes: Array[MeshInstance3D]) -> void:
	for i in range(meshes.size()):
		for j in range(i + 1, meshes.size()):
			_expect(
				not _aabb_has_volume_overlap(_world_aabb(meshes[i]), _world_aabb(meshes[j]), 0.01),
				"%s volumes overlap: %s / %s" % [label, meshes[i].name, meshes[j].name]
			)


func _world_aabb(mesh: MeshInstance3D) -> AABB:
	return mesh.global_transform * mesh.get_aabb()


func _aabb_has_volume_overlap(a: AABB, b: AABB, epsilon: float) -> bool:
	var overlap: AABB = a.intersection(b)
	return overlap.size.x > epsilon and overlap.size.y > epsilon and overlap.size.z > epsilon


func _find_meshes(root_node: Node, token: String) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	_collect_meshes(root_node, token, result)
	return result


func _collect_meshes(node: Node, token: String, result: Array[MeshInstance3D]) -> void:
	var mesh := node as MeshInstance3D
	if mesh != null and String(mesh.name).contains(token):
		result.append(mesh)
	for child in node.get_children():
		_collect_meshes(child, token, result)


func _make_template(building_type: String) -> Dictionary:
	return {
		"version": 1,
		"building_type": building_type,
		"outside_temp_c": 20.0,
		"outside_o2": 0.209,
		"stop_time_s": 0.0,
		"hvac_mode": "none",
		"hvac_data": {"exists": false, "on": false, "mode": "none"},
		"room_rect_m": {"0": {"x": 0.0, "y": 0.0, "w": 6.0, "h": 4.0}},
		"rooms_data": [
			{
				"id": 0,
				"name": "Exterior test room",
				"kind": "salon",
				"height_m": 2.62,
				"floor_level_z_m": 0.0,
				"fuel_energy_MJ": 0.0,
				"max_hrr_kw": 0.0,
				"fuel_objects": [],
			},
		],
		"openings_data": [
			{
				"a": 0,
				"b": -1,
				"type": "door",
				"wall": "bottom",
				"offset_m": 1.45,
				"width_m": 0.92,
				"height_m": 2.05,
				"open_fraction": 1.0,
			},
			{
				"a": 0,
				"b": -1,
				"type": "window",
				"wall": "bottom",
				"offset_m": 4.25,
				"width_m": 1.30,
				"height_m": 1.20,
				"sill_m": 0.90,
				"open_fraction": 0.0,
			},
		],
		"detectors": [],
		"victims": [],
		"exterior_walls": [],
	}


func _finish() -> void:
	if _failures.is_empty():
		print("FP EXTERIOR CONTEXT VALIDATION PASS")
		get_tree().quit(0)
		return
	push_error("FP EXTERIOR CONTEXT VALIDATION FAILED")
	for failure in _failures:
		push_error("- " + failure)
	get_tree().quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

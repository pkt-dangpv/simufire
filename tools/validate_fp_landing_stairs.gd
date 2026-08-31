extends Node

const BuildingModelScript := preload("res://sim/BuildingModel.gd")
const FirstPersonControllerScript := preload("res://view/fp/FirstPersonController.gd")

var _failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	await get_tree().process_frame
	var building: BuildingModel = BuildingModelScript.new()
	_expect(building.load_template_data(_make_template()), "BuildingModel rejected apartment landing template")

	var fp: FirstPersonController = FirstPersonControllerScript.new()
	fp.name = "ValidateFPLandingStairs"
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
		_validate_stair_structure(world)
		_validate_landing_lighting(world)
		_validate_single_landing_per_floor(world)
		_validate_landing_front_is_closed(world)

	remove_child(fp)
	fp.free()
	building.free()
	_finish()


func _validate_stair_structure(world: Node) -> void:
	var up_current := _find_meshes(world, "LandingUpCurrent_00_Step_")
	var down_current := _find_meshes(world, "LandingDownCurrent_00_Step_")
	var up_next := _find_meshes(world, "LandingUpNext_00_Step_")
	var down_previous := _find_meshes(world, "LandingDownPrevious_00_Step_")
	for flight_data in [
		["up current", up_current],
		["down current", down_current],
		["up next", up_next],
		["down previous", down_previous],
	]:
		_expect(Array(flight_data[1]).size() >= 7, "Missing steps in %s flight" % String(flight_data[0]))

	_expect(_find_meshes(world, "LandingMidUpper_00").size() == 1, "Upper half-landing missing")
	_expect(_find_meshes(world, "LandingMidLower_00").size() == 1, "Lower half-landing missing")
	_expect(_find_meshes(world, "LandingLowerFloor_00").size() == 1, "Lower floor closure missing")
	_expect(_find_meshes(world, "LandingUpperCeiling_00").size() == 1, "Upper ceiling closure missing")
	_expect(_find_meshes(world, "LandingFloor_00_").size() >= 2, "Current floor must be split around stairwell")
	_expect(_find_meshes(world, "LandingCeiling_00_").size() >= 2, "Upper floor must be split around stairwell")
	_expect(_find_meshes(world, "LandingScreen").is_empty(), "Legacy screen wall must not occlude the two flights")

	_validate_flight_direction("up current", up_current, true)
	_validate_flight_direction("down current", down_current, false)
	_validate_flight_direction("up next", up_next, true)
	_validate_flight_direction("down previous", down_previous, false)

	var all_steps: Array[MeshInstance3D] = []
	all_steps.append_array(up_current)
	all_steps.append_array(down_current)
	all_steps.append_array(up_next)
	all_steps.append_array(down_previous)
	for i in range(all_steps.size()):
		for j in range(i + 1, all_steps.size()):
			var a: MeshInstance3D = all_steps[i]
			var b: MeshInstance3D = all_steps[j]
			if _flight_prefix(a.name) == _flight_prefix(b.name):
				continue
			_expect(
				not _aabb_has_volume_overlap(_world_aabb(a), _world_aabb(b), 0.002),
				"Stair solids overlap: %s / %s" % [a.name, b.name]
			)

	var doors := _find_meshes(world, "LandingDoor_00_")
	var stair_solids: Array[MeshInstance3D] = all_steps.duplicate()
	stair_solids.append_array(_find_meshes(world, "LandingMidUpper_00"))
	stair_solids.append_array(_find_meshes(world, "LandingMidLower_00"))
	for door in doors:
		if not String(door.name).contains("_Leaf"):
			continue
		for stair in stair_solids:
			_expect(
				not _aabb_has_volume_overlap(_world_aabb(door), _world_aabb(stair), 0.002),
				"Apartment door invades stair bay: %s / %s" % [door.name, stair.name]
			)


## El portal tiene luz propia: si solo lo iluminase el hueco de la puerta de
## la vivienda, con la puerta cerrada el rellano seria una caja negra.
func _validate_landing_lighting(world: Node) -> void:
	var ambient := _find_lights(world, "LandingAmbientLight_00")
	var stair_light := _find_lights(world, "LandingStairLight_00")
	_expect(ambient.size() == 1, "Landing ceiling light missing")
	_expect(stair_light.size() == 1, "Stairwell light missing")
	for light in ambient:
		_expect(light.light_energy > 0.0, "Landing ceiling light is off")
	for light in stair_light:
		_expect(light.light_energy > 0.0, "Stairwell light is off")


## Dos puertas exteriores en la misma fachada y planta comparten rellano: si
## se genera uno por puerta, los dos portales quedan interpenetrados.
func _validate_single_landing_per_floor(world: Node) -> void:
	_expect(
		_find_meshes(world, "LandingFloor_01_").is_empty(),
		"A second exterior door must reuse the landing, not duplicate it"
	)
	_expect(
		_find_meshes(world, "LandingUpCurrent_01_Step_").is_empty(),
		"Duplicated landing stairs for a second exterior door"
	)


## El rellano es mas ancho que el muro de la vivienda: sin frente propio, el
## resto del portal queda abierto al exterior y entra el sol.
func _validate_landing_front_is_closed(world: Node) -> void:
	_expect(
		_find_meshes(world, "LandingFrontWall_00_").size() == 2,
		"Landing front must be closed at both sides of the flat door"
	)
	_expect(
		_find_meshes(world, "LandingFrontLintel_00").size() == 1,
		"Landing front lintel missing above the flat door"
	)


func _find_lights(root_node: Node, token: String) -> Array[OmniLight3D]:
	var result: Array[OmniLight3D] = []
	_collect_lights(root_node, token, result)
	return result


func _collect_lights(node: Node, token: String, result: Array[OmniLight3D]) -> void:
	var light := node as OmniLight3D
	if light != null and String(light.name).contains(token):
		result.append(light)
	for child in node.get_children():
		_collect_lights(child, token, result)


func _validate_flight_direction(label: String, meshes: Array[MeshInstance3D], ascending: bool) -> void:
	if meshes.size() < 2:
		return
	meshes.sort_custom(func(a: MeshInstance3D, b: MeshInstance3D) -> bool: return _step_index(a.name) < _step_index(b.name))
	var first_top: float = _world_aabb(meshes.front()).end.y
	var last_top: float = _world_aabb(meshes.back()).end.y
	if ascending:
		_expect(last_top > first_top + 0.50, "%s flight does not rise" % label)
	else:
		_expect(last_top < first_top - 0.50, "%s flight does not descend" % label)


func _world_aabb(mesh: MeshInstance3D) -> AABB:
	return mesh.global_transform * mesh.get_aabb()


func _aabb_has_volume_overlap(a: AABB, b: AABB, epsilon: float) -> bool:
	var overlap: AABB = a.intersection(b)
	return overlap.size.x > epsilon and overlap.size.y > epsilon and overlap.size.z > epsilon


func _flight_prefix(node_name: StringName) -> String:
	return String(node_name).get_slice("_Step_", 0)


func _step_index(node_name: StringName) -> int:
	return int(String(node_name).get_slice("_Step_", 1))


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


func _make_template() -> Dictionary:
	return {
		"version": 1,
		"building_type": "apartment",
		"outside_temp_c": 20.0,
		"outside_o2": 0.209,
		"stop_time_s": 0.0,
		"hvac_mode": "none",
		"hvac_data": {"exists": false, "on": false, "mode": "none"},
		"room_rect_m": {"0": {"x": 0.0, "y": 0.0, "w": 4.0, "h": 4.0}},
		"rooms_data": [
			{
				"id": 0,
				"name": "Vivienda",
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
				"offset_m": 2.0,
				"width_m": 0.90,
				"height_m": 2.05,
				"open_fraction": 1.0,
			},
			{
				"a": 0,
				"b": -1,
				"type": "door",
				"wall": "bottom",
				"offset_m": 0.75,
				"width_m": 0.80,
				"height_m": 2.05,
				"open_fraction": 0.0,
			},
		],
		"detectors": [],
		"victims": [],
		"exterior_walls": [],
	}


func _finish() -> void:
	if _failures.is_empty():
		print("FP LANDING STAIRS VALIDATION PASS")
		get_tree().quit(0)
		return
	push_error("FP LANDING STAIRS VALIDATION FAILED")
	for failure in _failures:
		push_error("- " + failure)
	get_tree().quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

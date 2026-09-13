extends Node
## Guardarrail de E-4 (docs/AUDITORIA_VISUAL_2026-08-29.md §2).
##
## Entre el techo de una planta y el forjado de la siguiente quedaba un anillo
## perimetral sin cerrar (7 cm con los valores de preset_two_storey_house): por
## el entraba luz exterior desde dentro y se veia el interior desde fuera.
## Aqui se fija que no quede holgura vertical entre losas.

const BuildingModelScript := preload("res://sim/BuildingModel.gd")
const FirstPersonControllerScript := preload("res://view/fp/FirstPersonController.gd")

const GROUND_HEIGHT_M: float = 2.65
const UPPER_LEVEL_M: float = 2.90
const MAX_GAP_M: float = 0.01

var _failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	await get_tree().process_frame

	var building: BuildingModel = BuildingModelScript.new()
	_expect(building.load_template_data(_make_template()), "Interstitial seal template rejected")

	var fp: FirstPersonController = FirstPersonControllerScript.new()
	fp.name = "ValidateFPInterstitialSeal"
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
		_validate_no_interstitial_gap(world)

	remove_child(fp)
	fp.free()
	building.free()
	_finish()


func _validate_no_interstitial_gap(world: Node) -> void:
	# Losas horizontales: cajas anchas y delgadas (suelos y techos).
	var slabs: Array = []
	for mesh in _find_all_meshes(world):
		var size: Vector3 = mesh.get_aabb().size
		if size.y > 0.60 or size.x < 1.0 or size.z < 1.0:
			continue
		var center: Vector3 = mesh.global_transform * mesh.get_aabb().get_center()
		slabs.append({"bottom": center.y - size.y * 0.5, "top": center.y + size.y * 0.5})
	_expect(slabs.size() >= 3, "Expected floor and ceiling slabs on both levels, found %d" % slabs.size())
	if slabs.size() < 3:
		return

	# Cara inferior del forjado de la planta alta. Se identifica por su cara
	# vista, que esta exactamente en la cota de la planta: el techo de la
	# planta baja arranca en 2,65 y confundiria una busqueda por altura.
	var upper_floor_bottom: float = INF
	for slab in slabs:
		if absf(float(slab["top"]) - UPPER_LEVEL_M) < 0.01:
			upper_floor_bottom = minf(upper_floor_bottom, float(slab["bottom"]))
	_expect(not is_inf(upper_floor_bottom), "Upper storey floor slab not found")
	if is_inf(upper_floor_bottom):
		return

	# Cara superior del techo de la planta baja: la losa mas alta por debajo.
	var ceiling_top: float = -INF
	for slab in slabs:
		var top: float = float(slab["top"])
		if top <= upper_floor_bottom + 0.001:
			ceiling_top = maxf(ceiling_top, top)
	_expect(not is_inf(ceiling_top), "Ground storey ceiling slab not found")
	if is_inf(ceiling_top):
		return

	var gap_m: float = upper_floor_bottom - ceiling_top
	_expect(
		gap_m <= MAX_GAP_M,
		"E-4 regression: %.3f m of open perimeter ring between the ground ceiling (top %.3f) and the upper floor (bottom %.3f)" % [
			gap_m, ceiling_top, upper_floor_bottom
		]
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


## Dos plantas apiladas con los forjados de preset_two_storey_house.
func _make_template() -> Dictionary:
	return {
		"version": 1,
		"building_type": "single_family",
		"outside_temp_c": 20.0,
		"outside_o2": 0.209,
		"stop_time_s": 0.0,
		"hvac_mode": "none",
		"hvac_data": {"exists": false, "on": false, "mode": "none"},
		"room_rect_m": {
			"0": {"x": 0.0, "y": 0.0, "w": 5.0, "h": 4.0},
			"1": {"x": 0.0, "y": 0.0, "w": 5.0, "h": 4.0}
		},
		"rooms_data": [
			{
				"id": 0, "name": "Salon", "kind": "salon", "height_m": GROUND_HEIGHT_M,
				"floor_level_z_m": 0.0, "fuel_energy_MJ": 0.0, "max_hrr_kw": 0.0,
				"fuel_objects": []
			},
			{
				"id": 1, "name": "Dormitorio", "kind": "dormitorio", "height_m": 2.40,
				"floor_level_z_m": UPPER_LEVEL_M, "fuel_energy_MJ": 0.0, "max_hrr_kw": 0.0,
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
		print("FP INTERSTITIAL SEAL VALIDATION PASS")
		get_tree().quit(0)
		return
	push_error("FP INTERSTITIAL SEAL VALIDATION FAILED")
	for failure in _failures:
		push_error("- " + failure)
	get_tree().quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

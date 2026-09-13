extends Node
## Guardarrail de H-5 y H-7 (docs/AUDITORIA_VISUAL_2026-08-29.md §1).
##
## H-5: la cortina de humo de un hueco escalaba la opacidad por la fraccion de
## apertura pero ocupaba siempre el ancho completo del vano, asi que con la
## puerta entornada el humo atravesaba la hoja. Aqui se fija que el ancho siga
## al hueco libre y que se desplace al lado de la CERRADURA, que es por donde
## pasa: la hoja gira sobre su bisagra y tapa ese lado.
##
## H-7 no se cubre aqui: no es reproducible con el codigo actual. El visor crea
## un item por CADA sala del edificio, este o no en el estado, asi que el
## retorno temprano de _update_vertical solo se daria con una sala inexistente,
## y en ese caso ni siquiera se crea el nodo de cortina. Ver §1 del informe.

const BuildingModelScript := preload("res://sim/BuildingModel.gd")
const Visualizer3DScript := preload("res://view/3d/Visualizer3D.gd")

var _failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	await get_tree().process_frame
	await _validate_leaf_gap()
	_finish()


# ---------------------------------------------------------------------------
# H-5
# ---------------------------------------------------------------------------

func _validate_leaf_gap() -> void:
	var building: BuildingModel = BuildingModelScript.new()
	_expect(building.load_template_data(_make_horizontal_template()), "Curtain template rejected")

	var visualizer: Visualizer3D = Visualizer3DScript.new()
	visualizer.name = "ValidateCurtainLeafGap"
	visualizer.building = building
	_add_visualizer_children(visualizer)
	add_child(visualizer)
	await get_tree().process_frame
	visualizer.rebuild_from_building()

	var state: Dictionary = _smoky_state()

	_expect(building.set_opening_fraction(0, 1.0), "Could not open the door fully")
	visualizer.set_state(state)
	await _settle(visualizer, state, 40)
	var full: Dictionary = _curtain_metrics(visualizer)
	_expect(bool(full.get("visible", false)), "Curtain is not visible with the door fully open")

	_expect(building.set_opening_fraction(0, 0.5), "Could not half-open the door")
	visualizer.set_state(state)
	await _settle(visualizer, state, 40)
	var half: Dictionary = _curtain_metrics(visualizer)
	_expect(bool(half.get("visible", false)), "Curtain disappeared with the door half open")

	if bool(full.get("visible", false)) and bool(half.get("visible", false)):
		var full_w: float = float(full.get("width_m", 0.0))
		var half_w: float = float(half.get("width_m", 0.0))
		_expect(
			half_w < full_w * 0.85,
			"H-5 regression: the curtain keeps the full opening width when the door is half open (%.2f vs %.2f)" % [half_w, full_w]
		)
		_expect(
			half_w > full_w * 0.20,
			"The half-open curtain collapsed to nothing (%.2f vs %.2f)" % [half_w, full_w]
		)
		# Bisagra a la izquierda en la plantilla: el hueco libre queda del lado
		# opuesto, el de la cerradura, en +Z.
		var shift_m: float = float(half.get("center_along_width", 0.0)) - float(full.get("center_along_width", 0.0))
		_expect(
			shift_m > 0.05,
			"H-5 regression: the curtain did not move to the latch side (shift %.3f m)" % shift_m
		)

	remove_child(visualizer)
	visualizer.free()
	building.free()


## El humo del visor no salta a su valor final: alpha y profundidad suben por
## rampa, asi que hay que reaplicar el estado unos cuantos fotogramas.
func _settle(visualizer: Node, state: Dictionary, frames: int) -> void:
	for _i in range(frames):
		if not state.is_empty():
			visualizer.set_state(state)
		await get_tree().process_frame


func _curtain_metrics(visualizer: Node) -> Dictionary:
	var curtain := visualizer.get_node_or_null("Openings/Opening_00/SmokeCurtain_00") as MeshInstance3D
	if curtain == null:
		curtain = _find_curtain(visualizer)
	if curtain == null:
		_expect(false, "Opening smoke curtain node not found")
		return {}
	if curtain.mesh == null:
		return {"visible": false}
	var aabb: AABB = curtain.get_aabb()
	var center: Vector3 = curtain.global_transform * aabb.get_center()
	# La puerta esta en una pared "right", asi que el ancho del vano corre por Z
	# y es ahi donde hay que ver el desplazamiento hacia la cerradura.
	return {
		"visible": curtain.visible,
		"width_m": aabb.size.z,
		"center_along_width": center.z,
	}


func _find_curtain(node: Node) -> MeshInstance3D:
	var mesh := node as MeshInstance3D
	if mesh != null and String(mesh.name).contains("SmokeCurtain"):
		return mesh
	for child in node.get_children():
		var found: MeshInstance3D = _find_curtain(child)
		if found != null:
			return found
	return null


# ---------------------------------------------------------------------------
# Plantillas y utilidades
# ---------------------------------------------------------------------------

func _smoky_state() -> Dictionary:
	return {
		"0": {
			"id": 0, "name": "Salon", "kind": "salon", "height_m": 2.6,
			"has_fire": true, "hrr_kw": 700.0, "temp_upper_c": 300.0,
			"smoke_kg": 2.0, "visibility_m": 1.4,
			"smoke_layer_m": 0.9, "visible_smoke_layer_m": 0.9,
			"fuel_objects": []
		},
		"1": {
			"id": 1, "name": "Pasillo", "kind": "pasillo", "height_m": 2.6,
			"has_fire": false, "hrr_kw": 0.0, "temp_upper_c": 60.0,
			"smoke_kg": 0.1, "visibility_m": 14.0,
			"smoke_layer_m": 2.2, "visible_smoke_layer_m": 2.2,
			"fuel_objects": []
		}
	}


func _make_horizontal_template() -> Dictionary:
	return {
		"version": 1,
		"building_type": "apartment",
		"outside_temp_c": 20.0,
		"outside_o2": 0.209,
		"stop_time_s": 0.0,
		"hvac_mode": "none",
		"hvac_data": {"exists": false, "on": false, "mode": "none"},
		"room_rect_m": {
			"0": {"x": 0.0, "y": 0.0, "w": 5.0, "h": 4.0},
			"1": {"x": 5.0, "y": 0.0, "w": 4.0, "h": 4.0}
		},
		"rooms_data": [
			{
				"id": 0, "name": "Salon", "kind": "salon", "height_m": 2.6,
				"floor_level_z_m": 0.0, "fuel_energy_MJ": 400.0, "max_hrr_kw": 900.0,
				"fuel_objects": []
			},
			{
				"id": 1, "name": "Pasillo", "kind": "pasillo", "height_m": 2.6,
				"floor_level_z_m": 0.0, "fuel_energy_MJ": 0.0, "max_hrr_kw": 0.0,
				"fuel_objects": []
			}
		],
		"openings_data": [
			{
				"a": 0, "b": 1, "type": "door", "wall": "right", "offset_m": 1.5,
				"width_m": 1.60, "height_m": 2.05, "open_fraction": 1.0,
				"hinge_side": "left"
			}
		],
		"detectors": [],
		"victims": [],
		"exterior_walls": []
	}


func _add_visualizer_children(visualizer: Node3D) -> void:
	for node_name in ["Rooms", "Openings", "Atmosphere", "Labels"]:
		var container := Node3D.new()
		container.name = node_name
		visualizer.add_child(container)
	var camera_rig := Node3D.new()
	camera_rig.name = "CameraRig"
	visualizer.add_child(camera_rig)
	var camera := Camera3D.new()
	camera.name = "Camera3D"
	camera.position = Vector3(0.0, 0.0, 12.0)
	camera_rig.add_child(camera)


func _finish() -> void:
	if _failures.is_empty():
		print("3D SMOKE OPENING CURTAIN VALIDATION PASS")
		get_tree().quit(0)
		return
	push_error("3D SMOKE OPENING CURTAIN VALIDATION FAILED")
	for failure in _failures:
		push_error("- " + failure)
	get_tree().quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

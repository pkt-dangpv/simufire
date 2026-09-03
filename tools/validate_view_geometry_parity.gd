extends Node

## Guardarrail de FP-3: el mundo de primera persona y el visor 3D tienen que
## repartir la misma geometria.
##
## No compara pixeles ni materiales —son dos representaciones distintas a
## proposito, arquitectura recorrible frente a maqueta traslucida—; compara el
## REPARTO, que es lo que estaba escrito dos veces: que losas lleva el forjado
## de un hueco de escalera y como se llaman, por donde parte un hueco vertical
## el suelo de la planta de encima, y donde cae cada hueco a lo largo de su
## paramento.
##
## Con las dos implementaciones anteriores esto coincidia por suerte. El caso de
## la ventana declarada al norte falla directamente sin la correccion: el visor
## entendia el alias cardinal y el mundo FP la plantaba en la pared derecha.

const BuildingModelScript := preload("res://sim/BuildingModel.gd")
const FirstPersonControllerScript := preload("res://view/fp/FirstPersonController.gd")
const Visualizer3DScript := preload("res://view/3d/Visualizer3D.gd")
const OpeningPose3DScript := preload("res://view/3d/openings/OpeningPose3D.gd")

## Tolerancia (m). Un milimetro: las dos vistas hacen ya la misma cuenta con los
## mismos floats, asi que lo unico que se admite es el ruido de la conversion a
## unidades de escena del visor.
const TOL_M: float = 0.001

## Dos huecos de escalera distintos a proposito: el estrecho cae en el reparto
## de tiro unico y el ancho supera el umbral de ida y vuelta de SlabGeometry,
## asi que entre los dos casos se recorren las dos ramas del plan.
const STAIR_RECT_STRAIGHT := Rect2(0.0, 0.0, 1.40, 4.60)
## 3,10 m de ancho y no los 2,40 del validador de escaleras: con 2,40 el ojo se
## come el recinto entero y el plan de ida y vuelta sale vacio, que es correcto
## pero no comprueba nada.
const STAIR_RECT_SWITCHBACK := Rect2(0.0, 0.0, 3.10, 5.40)

const PB_LEVEL_M: float = 0.0
const P1_LEVEL_M: float = 3.00

## Identificadores de sala del escenario de prueba.
const STAIR_P1_ID: int = 1
const SHELL_P1_ID: int = 3

var _failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	await get_tree().process_frame

	var straight: Dictionary = await _build_case("straight", STAIR_RECT_STRAIGHT, 0.0, "straight")
	_validate_stairwell_slabs("straight", straight, false)
	_validate_vertical_void_split("straight", straight)
	_validate_opening_placement("straight", straight)
	_cleanup_case(straight)

	var switchback: Dictionary = await _build_case("switchback", STAIR_RECT_SWITCHBACK, 180.0, "switchback")
	_validate_stairwell_slabs("switchback", switchback, true)
	_validate_vertical_void_split("switchback", switchback)
	_validate_opening_placement("switchback", switchback)
	_cleanup_case(switchback)

	if _failures.is_empty():
		print("VIEW GEOMETRY PARITY VALIDATION PASS")
		get_tree().quit(0)
		return

	push_error("VIEW GEOMETRY PARITY VALIDATION FAILED")
	for failure in _failures:
		push_error("- " + failure)
	get_tree().quit(1)


# ---------------------------------------------------------------------------
# Comprobaciones
# ---------------------------------------------------------------------------

## El forjado del hueco de escalera en planta alta: las dos vistas tienen que
## emitir las mismas losas, con los mismos nombres y la misma huella, y las dos
## tienen que coincidir con el plan que da SlabGeometry.
func _validate_stairwell_slabs(case_name: String, ctx: Dictionary, expect_switchback: bool) -> void:
	var building: BuildingModel = ctx["building"]
	var stair_rect: Rect2 = ctx["stair_rect"]
	var upper_stair: RoomModel = building.get_room(STAIR_P1_ID)
	if upper_stair == null:
		_expect(false, case_name + ": falta la escalera de P1")
		return

	var plan: Array[Dictionary] = SlabGeometry.stairwell_upper_floor_slabs(
		STAIR_P1_ID,
		stair_rect,
		BuildingLevels.stair_run_direction(upper_stair),
		upper_stair.stair_turn_degrees
	)
	_expect(not plan.is_empty(), case_name + ": el plan de losas del hueco de escalera no puede salir vacio")

	# Los dos casos tienen que recorrer ramas distintas del plan; si no, uno de
	# los dos no esta comprobando lo que dice comprobar.
	var is_switchback_plan: bool = false
	for slab in plan:
		if String(slab["name"]).begins_with("StairSwitchback"):
			is_switchback_plan = true
	_expect(
		is_switchback_plan == expect_switchback,
		"%s: se esperaba el reparto %s y salio el otro" % [case_name, "de ida y vuelta" if expect_switchback else "de tiro unico"]
	)

	var wanted: Array[String] = []
	var expected: Array[String] = []
	for slab in plan:
		var rect: Rect2 = slab["rect"]
		wanted.append(String(slab["name"]))
		expected.append(_footprint_key(String(slab["name"]), rect.size.x, rect.size.y))
	expected.sort()

	var in_fp: Array[String] = _footprints(_fp_world(ctx), wanted)
	var in_3d: Array[String] = _footprints(ctx["visualizer"], wanted)

	_expect(
		in_fp == expected,
		"%s: las losas del hueco de escalera en primera persona no siguen el plan compartido\n  plan: %s\n  FP:   %s" % [case_name, expected, in_fp]
	)
	_expect(
		in_3d == expected,
		"%s: las losas del hueco de escalera en el visor 3D no siguen el plan compartido\n  plan: %s\n  3D:   %s" % [case_name, expected, in_3d]
	)


## Un hueco vertical recorta el suelo de la sala de encima. Las dos vistas
## tienen que partirlo en los mismos trozos, aunque los bauticen distinto: el
## mundo FP FloorPart_..., el visor FloorVoidPart_...
func _validate_vertical_void_split(case_name: String, ctx: Dictionary) -> void:
	var building: BuildingModel = ctx["building"]
	var shell_rect: Rect2 = ctx["shell_rect"]
	var voids: Array[Rect2] = BuildingLevels.vertical_stair_voids(building, P1_LEVEL_M, true)
	_expect(voids.size() == 1, "%s: se esperaba un unico hueco vertical sobre P1, hay %d" % [case_name, voids.size()])

	var fp_prefix: String = "FloorPart_%d" % SHELL_P1_ID
	var visor_prefix: String = "FloorVoidPart_%02d" % SHELL_P1_ID
	var fp_pieces: Array[Dictionary] = SlabGeometry.named_slab_pieces(shell_rect, voids, "Floor_%d" % SHELL_P1_ID, fp_prefix)
	var visor_pieces: Array[Dictionary] = SlabGeometry.named_slab_pieces(shell_rect, voids, "", visor_prefix)
	_expect(
		fp_pieces.size() > 1,
		case_name + ": el caso de prueba no llega a partir el suelo de P1; sin eso no comprueba nada"
	)

	var expected: Array[String] = []
	for piece in fp_pieces:
		var rect: Rect2 = piece["rect"]
		expected.append(_size_key(rect.size.x, rect.size.y))
	expected.sort()

	var in_fp: Array[String] = _sizes_only(_footprints(_fp_world(ctx), _names_of(fp_pieces)))
	var in_3d: Array[String] = _sizes_only(_footprints(ctx["visualizer"], _names_of(visor_pieces)))

	_expect(
		in_fp == expected,
		"%s: el suelo partido de P1 no coincide en primera persona\n  esperado: %s\n  FP:       %s" % [case_name, expected, in_fp]
	)
	_expect(
		in_3d == expected,
		"%s: el suelo partido de P1 no coincide en el visor 3D\n  esperado: %s\n  3D:       %s" % [case_name, expected, in_3d]
	)


## Cada hueco tiene que caer en el mismo sitio de su paramento en las dos
## vistas. Se compara en metros, antes de que cada una aplique su propia
## transformacion de mundo.
func _validate_opening_placement(case_name: String, ctx: Dictionary) -> void:
	var building: BuildingModel = ctx["building"]
	var fp: FirstPersonController = ctx["fp"]
	var rects: Dictionary = building.get_room_rects_m()
	var checked: int = 0

	for index in range(building.get_opening_count()):
		var op: OpeningModel = building.get_opening_at(index)
		if op == null or op.is_vertical:
			continue
		var info: Dictionary = fp._opening_info(index)
		var pose: Dictionary = OpeningPose3DScript.compute(op, rects, -1, 0.10)
		if info.is_empty() or pose.is_empty():
			_expect(
				info.is_empty() and pose.is_empty(),
				"%s: el hueco %d existe en una vista y no en la otra (FP=%s, 3D=%s)" % [case_name, index, not info.is_empty(), not pose.is_empty()]
			)
			continue

		var room_id: int = int(info["room_id"])
		var side: String = String(info.get("side_for_%d" % room_id, ""))
		var horizontal: bool = WallSideGeometry.is_horizontal(side)
		var pose_pos: Vector3 = pose["position"]
		var pose_axis: float = pose_pos.x if horizontal else pose_pos.z
		var fp_axis: float = float(info["axis_center"])
		var pose_fixed: float = pose_pos.z if horizontal else pose_pos.x
		var fp_fixed: float = WallSideGeometry.side_offset_m(Rect2(rects[room_id]), side)

		_expect(
			absf(fp_axis - pose_axis) <= TOL_M,
			"%s: el hueco %d (wall=%s, lado=%s) cae en %.4f m en FP y en %.4f m en el visor 3D" % [case_name, index, op.wall_side, side, fp_axis, pose_axis]
		)
		_expect(
			absf(fp_fixed - pose_fixed) <= TOL_M,
			"%s: el hueco %d (wall=%s) esta sobre paramentos distintos: %.4f m en FP y %.4f m en el visor 3D" % [case_name, index, op.wall_side, fp_fixed, pose_fixed]
		)
		checked += 1

	_expect(checked >= 3, "%s: solo se compararon %d huecos horizontales; el caso de prueba se ha quedado corto" % [case_name, checked])


# ---------------------------------------------------------------------------
# Montaje
# ---------------------------------------------------------------------------

func _build_case(case_name: String, stair_rect: Rect2, turn_degrees: float, turn_mode: String) -> Dictionary:
	var shell_rect: Rect2 = _shell_rect(stair_rect)
	var side_rect: Rect2 = _side_rect(shell_rect)
	var building: BuildingModel = BuildingModelScript.new()
	building.load_template_data(_make_template(stair_rect, shell_rect, side_rect, turn_degrees, turn_mode))

	var host := Node3D.new()
	host.name = "ValidateViewParity_%s" % case_name
	get_tree().root.add_child(host)

	var fp: FirstPersonController = FirstPersonControllerScript.new()
	fp.name = "FirstPersonController_%s" % case_name
	fp.exterior_context_enabled = false
	fp.show_fp_detectors = false
	fp.show_fp_victims = false
	host.add_child(fp)
	await get_tree().process_frame
	fp.setup(building)
	await get_tree().physics_frame

	var visualizer: Visualizer3D = Visualizer3DScript.new()
	visualizer.name = "Visualizer3D_%s" % case_name
	visualizer.building = building
	visualizer.show_room_labels = false
	visualizer.show_smoke_volume = false
	visualizer.show_hrr_columns = false
	visualizer.show_fuel_objects_3d = false
	host.add_child(visualizer)
	await get_tree().process_frame
	visualizer.rebuild_from_building()
	await get_tree().process_frame

	return {
		"building": building,
		"host": host,
		"fp": fp,
		"visualizer": visualizer,
		"stair_rect": stair_rect,
		"shell_rect": shell_rect,
	}


func _cleanup_case(ctx: Dictionary) -> void:
	var host := ctx.get("host") as Node
	if host != null:
		host.free()
	var building := ctx.get("building") as Node
	if building != null:
		building.free()


# ---------------------------------------------------------------------------
# Lectura de la geometria ya construida
# ---------------------------------------------------------------------------

func _fp_world(ctx: Dictionary) -> Node:
	var fp: FirstPersonController = ctx["fp"]
	var root: Node = fp.get_parent().get_node_or_null("FirstPersonWorld")
	return root if root != null else fp


## Huella (nombre + lados en planta, en metros) de las cajas cuyo nombre —o el
## del cuerpo que las contiene— esta en `wanted`.
##
## El nombre se hereda hacia abajo porque en primera persona la losa es una
## StaticBody3D con el nombre bueno y una malla generica dentro, mientras que en
## el visor es la propia malla la que lleva el nombre.
func _footprints(root: Node, wanted: Array[String]) -> Array[String]:
	var result: Array[String] = []
	_collect_named_boxes(root, wanted, "", result)
	result.sort()
	return result


func _collect_named_boxes(node: Node, wanted: Array[String], inherited_name: String, result: Array[String]) -> void:
	var own_name: String = String(node.name)
	var label: String = own_name if wanted.has(own_name) else inherited_name
	var mesh := node as MeshInstance3D
	if mesh != null and label != "":
		var box := mesh.mesh as BoxMesh
		if box != null:
			var mesh_scale: Vector3 = mesh.global_transform.basis.get_scale()
			result.append(_footprint_key(label, box.size.x * mesh_scale.x, box.size.z * mesh_scale.z))
	for child in node.get_children():
		_collect_named_boxes(child, wanted, label, result)


func _names_of(slabs: Array[Dictionary]) -> Array[String]:
	var result: Array[String] = []
	for slab in slabs:
		result.append(String(slab["name"]))
	return result


func _footprint_key(node_name: String, size_x_m: float, size_z_m: float) -> String:
	return "%s|%.3f|%.3f" % [node_name, size_x_m, size_z_m]


func _size_key(size_x_m: float, size_z_m: float) -> String:
	return "%.3f|%.3f" % [size_x_m, size_z_m]


## Se queda con la huella y tira el nombre: las dos vistas parten el suelo igual
## pero bautizan los trozos distinto, y el nombre no es lo que se compara aqui.
func _sizes_only(keys: Array[String]) -> Array[String]:
	var result: Array[String] = []
	for key in keys:
		var parts: PackedStringArray = key.split("|")
		if parts.size() >= 3:
			result.append("%s|%s" % [parts[parts.size() - 2], parts[parts.size() - 1]])
	result.sort()
	return result


# ---------------------------------------------------------------------------
# Escenario de prueba
# ---------------------------------------------------------------------------

## La sala que envuelve la escalera sobresale 0,70 m por cada lado, para que el
## hueco vertical caiga dentro de ella y llegue a partirle el suelo.
func _shell_rect(stair_rect: Rect2) -> Rect2:
	return Rect2(stair_rect.position - Vector2(0.70, 0.70), stair_rect.size + Vector2(1.40, 1.40))


## Sala contigua pegada al lado derecho de la envolvente, para tener medianera.
func _side_rect(shell_rect: Rect2) -> Rect2:
	return Rect2(Vector2(shell_rect.position.x + shell_rect.size.x, shell_rect.position.y), Vector2(4.00, shell_rect.size.y))


## Escalera pasante entre PB y P1, con una sala en cada planta que la envuelve
## —para que el hueco vertical parta de verdad el suelo de arriba— y una sala
## contigua en PB. Los huecos cubren los tres caminos que recorren las dos
## vistas: medianera compartida, hueco exterior con lado canonico y hueco
## exterior con alias cardinal.
func _make_template(stair_rect: Rect2, shell_rect: Rect2, side_rect: Rect2, turn_degrees: float, turn_mode: String) -> Dictionary:
	var flight_count: int = 2 if turn_degrees >= 179.0 else 1
	return {
		"version": 1,
		"building_type": "apartment",
		"outside_temp_c": 20.0,
		"outside_o2": 0.209,
		"stop_time_s": 0.0,
		"hvac_mode": "none",
		"hvac_data": {"exists": false, "on": false, "mode": "none"},
		"room_rect_m": {
			"0": _rect_to_data(stair_rect),
			"1": _rect_to_data(stair_rect),
			"2": _rect_to_data(shell_rect),
			"3": _rect_to_data(shell_rect),
			"4": _rect_to_data(side_rect),
		},
		"rooms_data": [
			_make_stair_room(0, "Escalera PB", stair_rect, PB_LEVEL_M, 3.00, turn_degrees, turn_mode, flight_count),
			_make_stair_room(1, "Escalera P1", stair_rect, P1_LEVEL_M, 2.55, turn_degrees, turn_mode, flight_count),
			_make_plain_room(2, "Salon PB", shell_rect, PB_LEVEL_M, 3.00),
			_make_plain_room(3, "Salon P1", shell_rect, P1_LEVEL_M, 2.55),
			_make_plain_room(4, "Dormitorio PB", side_rect, PB_LEVEL_M, 3.00),
		],
		"openings_data": [
			{
				"a": 0, "b": 1, "type": "hole", "wall": "vertical",
				"offset_m": 0.0, "width_m": stair_rect.size.x, "height_m": stair_rect.size.y,
				"sill_m": 0.0, "open_fraction": 1.0, "is_vertical": true,
			},
			{
				"a": 2, "b": 4, "type": "door", "wall": "right",
				"offset_m": 0.50, "width_m": 0.90, "height_m": 2.05,
				"sill_m": 0.0, "open_fraction": 0.0, "offset_is_fraction": true,
			},
			{
				"a": 2, "b": -1, "type": "window", "wall": "left",
				"offset_m": 2.00, "width_m": 1.30, "height_m": 1.20,
				"sill_m": 0.90, "open_fraction": 0.0,
			},
			{
				"a": 4, "b": -1, "type": "window", "wall": "north",
				"offset_m": 1.60, "width_m": 1.30, "height_m": 1.20,
				"sill_m": 0.90, "open_fraction": 0.0,
			},
		],
		"player_start": {
			"room_id": 2,
			"position_m": {"x": shell_rect.size.x * 0.5, "y": shell_rect.size.y * 0.5},
			"floor_level_z_m": PB_LEVEL_M,
			"yaw_deg": 0.0,
		},
		"detectors": [],
		"victims": [],
		"exterior_walls": [],
	}


func _make_stair_room(id: int, room_name: String, rect: Rect2, floor_level_m: float, height_m: float, turn_degrees: float, turn_mode: String, flight_count: int) -> Dictionary:
	return {
		"id": id,
		"name": room_name,
		"kind": "escalera",
		"height_m": height_m,
		"floor_level_z_m": floor_level_m,
		"rotation_deg": 0.0,
		"stair_run_direction_m": {"x": 0.0, "y": 1.0},
		"stair_has_walls": false,
		"stair_has_railings": true,
		"stair_turn_mode": turn_mode,
		"stair_turn_degrees": turn_degrees,
		"stair_flight_count": flight_count,
		"fuel_energy_MJ": 0.0,
		"max_hrr_kw": 0.0,
		"fuel_objects": [],
		"width_m": rect.size.x,
		"length_m": rect.size.y,
	}


func _make_plain_room(id: int, room_name: String, rect: Rect2, floor_level_m: float, height_m: float) -> Dictionary:
	return {
		"id": id,
		"name": room_name,
		"kind": "sala",
		"height_m": height_m,
		"floor_level_z_m": floor_level_m,
		"rotation_deg": 0.0,
		"fuel_energy_MJ": 0.0,
		"max_hrr_kw": 0.0,
		"fuel_objects": [],
		"width_m": rect.size.x,
		"length_m": rect.size.y,
	}


func _rect_to_data(rect: Rect2) -> Dictionary:
	return {"x": rect.position.x, "y": rect.position.y, "w": rect.size.x, "h": rect.size.y}


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

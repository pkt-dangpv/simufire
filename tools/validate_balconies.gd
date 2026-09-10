extends Node

## Guardarrail de N-1: los balcones del edificio del jugador.
##
## Tres cosas que comprobar, y la segunda es la que pidio el usuario:
##
##  1. **Se construye lo que se declara**: losa, antepecho en U y pasamanos,
##     con el ancho, el vuelo y el antepecho que dice la abertura, colgados a
##     la cota del suelo de la vivienda y por FUERA del paramento.
##  2. **No se puede salir**. La losa y el antepecho NO tienen colision, y el
##     hueco esta cerrado por un colisionador invisible. Se comprueba tirando
##     un rayo desde dentro de la sala hacia fuera, a la altura del hueco: con
##     balcon tiene que chocar contra la barrera Y en el plano de la fachada.
##
##     El control no puede ser "sin balcon el rayo sale", porque el mundo FP
##     ya tiene un `NoExitBoundary` que envuelve el edificio entero a 22 cm de
##     su caja: sin balcon el rayo tambien choca, solo que mas lejos. Lo que
##     se compara es DONDE para: la barrera del balcon detiene en la fachada,
##     el limite exterior detiene despues. Por eso la barrera no sobra aunque
##     el limite exista: el limite va por la caja del edificio y una fachada
##     retranqueada deja hueco por delante; la barrera va por el hueco.
##  3. **El balcon y el portal no comparten hueco**. El rellano es de la puerta
##     de entrada; una puerta con balcon es una balconera y da a la calle.
##
## Y dos que son del dato, no de la geometria: un balcon declarado en un
## tabique interior se borra al normalizar, y apagar `own_balconies_enabled`
## no deja ni una pieza.
##
##   <godot> --headless --path . res://tools/validate_balconies.tscn

const BuildingModelScript := preload("res://sim/BuildingModel.gd")
const BuildingTemplateScript := preload("res://sim/templates/BuildingTemplate.gd")
const Serializer := preload("res://editor/ScenarioSerializer.gd")
const FirstPersonControllerScript := preload("res://view/fp/FirstPersonController.gd")

## Medidas del balcon de prueba. No son las de por defecto a proposito: si el
## codigo se olvidase de leer el dato y usase su reserva, se veria aqui.
const SPAN_M: float = 2.40
const FLIGHT_M: float = 1.35
const PARAPET_M: float = 1.15

## Tolerancia de medida. Las piezas se situan por su centro y se miden por su
## caja, asi que no hay redondeos acumulados: un centimetro sobra.
const TOL_M: float = 0.01

var _failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	await get_tree().process_frame
	_check_serializer()
	await _check_geometry()
	_finish()


## --- El dato ---

func _check_serializer() -> void:
	var interior: Dictionary = Serializer.normalize_opening({
		"a": 1, "b": 2, "type": "door", "wall": "top",
		"has_balcony": true, "balcony_depth_m": 1.5,
	})
	if interior.has("has_balcony"):
		_fail("un balcon en un tabique interior sobrevive a la normalizacion")

	var vertical: Dictionary = Serializer.normalize_opening({
		"a": 1, "b": -1, "type": "hole", "is_vertical": true, "has_balcony": true,
	})
	if vertical.has("has_balcony"):
		_fail("un balcon en un hueco vertical sobrevive a la normalizacion")

	var recortado: Dictionary = Serializer.normalize_opening({
		"a": 1, "b": -1, "type": "door", "wall": "top",
		"has_balcony": true, "balcony_depth_m": 40.0, "balcony_parapet_m": 0.05,
	})
	if not bool(recortado.get("has_balcony", false)):
		_fail("un balcon en una abertura exterior no sobrevive a la normalizacion")
	if absf(float(recortado.get("balcony_depth_m", 0.0)) - 3.0) > TOL_M:
		_fail("el vuelo no se recorta al maximo: %.2f m" % float(recortado.get("balcony_depth_m", 0.0)))
	if absf(float(recortado.get("balcony_parapet_m", 0.0)) - 0.60) > TOL_M:
		_fail("el antepecho no se levanta al minimo: %.2f m" % float(recortado.get("balcony_parapet_m", 0.0)))


## --- La geometria y el paso ---

func _check_geometry() -> void:
	var editor_data: Dictionary = _scenario_with_balcony()
	if editor_data.is_empty():
		_fail("no se pudo preparar un escenario con balcon")
		return

	var con_balcon: Dictionary = await _build(editor_data, true)
	var fp: FirstPersonController = con_balcon.get("fp")
	if fp == null:
		return
	var index: int = int(editor_data.get("_balcony_index", 0))

	var slab: MeshInstance3D = _find_mesh(fp, "OwnBalconySlab_%02d" % index)
	var front: MeshInstance3D = _find_mesh(fp, "OwnBalconyParapet_%02d_F" % index)
	var left: MeshInstance3D = _find_mesh(fp, "OwnBalconyParapet_%02d_L" % index)
	var right: MeshInstance3D = _find_mesh(fp, "OwnBalconyParapet_%02d_R" % index)
	var rail: MeshInstance3D = _find_mesh(fp, "OwnBalconyHandrail_%02d_F" % index)
	var barrier: StaticBody3D = _find_node(fp, "OwnBalconyBarrier_%02d" % index) as StaticBody3D

	if slab == null:
		_fail("no se construyo la losa del balcon")
	if front == null:
		_fail("no se construyo el frente del antepecho")
	if left == null or right == null:
		_fail("no se construyeron los dos retornos del antepecho")
	if rail == null:
		_fail("no se construyo el pasamanos")
	if barrier == null:
		_fail("no se construyo el colisionador que cierra el hueco del balcon")
	if slab == null or barrier == null:
		_drop(con_balcon)
		return

	# Ancho y vuelo: se miden en la caja de la losa, sin saber por que eje cae
	# cada uno -depende de como este puesto el muro-.
	var slab_size: Vector3 = _box_size(slab)
	var flight_total_m: float = fp.own_facade_thickness_m + FLIGHT_M
	var along_m: float = maxf(slab_size.x, slab_size.z)
	var across_m: float = minf(slab_size.x, slab_size.z)
	if absf(along_m - SPAN_M) > TOL_M:
		_fail("el ancho de la losa es %.2f m y se pidio %.2f m" % [along_m, SPAN_M])
	if absf(across_m - flight_total_m) > TOL_M:
		_fail("el vuelo de la losa es %.2f m y se esperaba %.2f m" % [across_m, flight_total_m])
	if absf(slab_size.y - fp.own_balcony_slab_thickness_m) > TOL_M:
		_fail("el canto de la losa es %.2f m" % slab_size.y)

	# La cara de arriba de la losa tiene que estar al nivel del suelo de la
	# vivienda, deducido del centro del hueco: si se equivoca, el balcon queda
	# a media altura de la puerta o flotando.
	var opening: Dictionary = Dictionary(editor_data.get("_balcony_opening", {}))
	var sill_m: float = float(opening.get("sill_m", 0.0))
	var height_m: float = float(opening.get("height_m", 2.1))
	var floor_y: float = barrier.global_position.y - (sill_m + height_m * 0.5)
	var slab_top_y: float = slab.global_position.y + slab_size.y * 0.5
	if absf(slab_top_y - floor_y) > TOL_M:
		_fail("la losa no queda al nivel del suelo: %.2f m frente a %.2f m" % [slab_top_y, floor_y])
	if front != null:
		var front_top_y: float = front.global_position.y + _box_size(front).y * 0.5
		if absf(front_top_y - (floor_y + PARAPET_M)) > TOL_M:
			_fail("el antepecho mide %.2f m y se pidio %.2f m" % [front_top_y - floor_y, PARAPET_M])

	# La losa cuelga por FUERA: sale del plano del hueco en la direccion de la
	# calle. Es lo unico que distingue un balcon de un trozo de suelo dentro
	# de la sala.
	var outward: Vector3 = slab.global_position - barrier.global_position
	outward.y = 0.0
	if outward.length() <= 0.05:
		_fail("la losa no sale del plano de la fachada")
		_drop(con_balcon)
		return
	outward = outward.normalized()

	# Nada del balcon colisiona salvo la barrera.
	for body in _bodies_named(fp, "OwnBalcony"):
		if not String(body.name).begins_with("OwnBalconyBarrier"):
			_fail("%s tiene colision: al balcon no se puede subir" % String(body.name))

	# El portal no se planta en la balconera.
	if _find_node(fp, "LandingFloor_%02d" % index) != null:
		_fail("la puerta con balcon construyo tambien el rellano del portal")

	# El rayo: desde dentro de la sala hacia la calle, a la altura del centro
	# del hueco. Con balcon tiene que chocar contra la barrera, y ahi mismo.
	var eye: Vector3 = barrier.global_position - outward * 0.70
	var out_point: Vector3 = barrier.global_position + outward * 2.20
	var hit: Dictionary = _ray(fp, eye, out_point)
	var stop_m: float = -1.0
	if hit.is_empty():
		_fail("con balcon, el hueco deja pasar: no se puede salir tiene que ser de verdad")
	elif not String(hit.get("name", "")).begins_with("OwnBalconyBarrier"):
		_fail("con balcon, el hueco lo tapa %s y no la barrera" % String(hit.get("name", "")))
	else:
		stop_m = eye.distance_to(Vector3(hit.get("position", Vector3.ZERO)))
		if absf(stop_m - 0.70) > 0.15:
			_fail("la barrera no para en la fachada: para a %.2f m del ojo" % stop_m)
	_drop(con_balcon)

	# Control: el mismo escenario con los balcones apagados. El rayo tiene que
	# salir, y no puede quedar ni una pieza de balcon.
	var sin_balcon: Dictionary = await _build(editor_data, false)
	var fp2: FirstPersonController = sin_balcon.get("fp")
	if fp2 == null:
		return
	if _find_mesh(fp2, "OwnBalconySlab_%02d" % index) != null:
		_fail("con own_balconies_enabled = false se sigue construyendo la losa")
	if _find_node(fp2, "OwnBalconyBarrier_%02d" % index) != null:
		_fail("con own_balconies_enabled = false se sigue cerrando el hueco")
	# El control: sin barrera, por el hueco se pasa. Lo que para el rayo ya no
	# es la fachada sino el limite exterior del mundo, y para mas lejos.
	var hit2: Dictionary = _ray(fp2, eye, out_point)
	if not hit2.is_empty():
		if String(hit2.get("name", "")).begins_with("OwnBalconyBarrier"):
			_fail("sin balcon sigue habiendo barrera en el hueco")
		elif stop_m > 0.0:
			var stop2_m: float = eye.distance_to(Vector3(hit2.get("position", Vector3.ZERO)))
			if stop2_m <= stop_m + 0.10:
				_fail("sin balcon el rayo para igual de cerca (%.2f m frente a %.2f m): la barrera no esta haciendo nada" % [stop2_m, stop_m])
	_drop(sin_balcon)


## Un piso del catalogo, con su primera ventana exterior convertida en
## balconera: puerta hasta el suelo, con balcon. Se elige una ventana porque
## la puerta de un piso da al portal, y ahi no hay calle.
func _scenario_with_balcony() -> Dictionary:
	var builder = BuildingTemplateScript.new()
	var editor_data: Dictionary = Serializer.normalize_editor_data(builder.create_by_name("compact_apartment"))
	var openings: Array = editor_data.get("openings_data", [])
	for i in range(openings.size()):
		var op: Dictionary = openings[i]
		if String(op.get("type", "")) != "window":
			continue
		if int(op.get("a", 0)) != -1 and int(op.get("b", -1)) != -1:
			continue
		op["type"] = "door"
		op["sill_m"] = 0.0
		op["height_m"] = 2.10
		op["open_fraction"] = 1.0
		op["has_balcony"] = true
		op["balcony_width_m"] = SPAN_M
		op["balcony_depth_m"] = FLIGHT_M
		op["balcony_parapet_m"] = PARAPET_M
		openings[i] = op
		editor_data["openings_data"] = openings
		editor_data["_balcony_index"] = i
		editor_data["_balcony_opening"] = op.duplicate(true)
		return editor_data
	return {}


func _build(editor_data: Dictionary, balconies: bool) -> Dictionary:
	var runtime_json: Dictionary = Serializer.to_runtime_json_data(editor_data)
	var parsed: Variant = JSON.parse_string(JSON.stringify(runtime_json))
	if typeof(parsed) != TYPE_DICTIONARY:
		_fail("no se pudo construir el edificio")
		return {}
	var building: BuildingModel = BuildingModelScript.new()
	building.load_template_data(Dictionary(parsed))

	var fp: FirstPersonController = FirstPersonControllerScript.new()
	fp.name = "ValidateBalconyFP_%s" % ("on" if balconies else "off")
	fp.show_fp_detectors = false
	fp.show_fp_victims = false
	fp.own_balconies_enabled = balconies
	add_child(fp)
	await get_tree().process_frame
	fp.setup(building)
	await get_tree().physics_frame
	fp.set_state({})
	await get_tree().physics_frame
	return {"fp": fp, "building": building}


## --- Utiles ---

func _ray(fp: Node3D, from: Vector3, to: Vector3) -> Dictionary:
	var space := fp.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = false
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		return {}
	var collider = hit.get("collider")
	return {
		"name": String(collider.name) if collider != null else "",
		"position": hit.get("position", Vector3.ZERO),
	}


func _box_size(mesh: MeshInstance3D) -> Vector3:
	var box := mesh.mesh as BoxMesh
	return box.size if box != null else Vector3.ZERO


func _find_node(root: Node, node_name: String) -> Node:
	if String(root.name) == node_name:
		return root
	for child in root.get_children():
		var hit: Node = _find_node(child, node_name)
		if hit != null:
			return hit
	return null


func _find_mesh(root: Node, node_name: String) -> MeshInstance3D:
	return _find_node(root, node_name) as MeshInstance3D


func _bodies_named(root: Node, prefix: String) -> Array[CollisionObject3D]:
	var out: Array[CollisionObject3D] = []
	if root is CollisionObject3D and String(root.name).begins_with(prefix):
		out.append(root)
	for child in root.get_children():
		out.append_array(_bodies_named(child, prefix))
	return out


func _drop(built: Dictionary) -> void:
	var fp: Node = built.get("fp")
	var building: BuildingModel = built.get("building")
	if fp != null:
		remove_child(fp)
		fp.free()
	if building != null:
		building.free()


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("[validate_balconies] PASS")
		get_tree().quit(0)
		return
	push_error("[validate_balconies] FAILED")
	for failure in _failures:
		push_error("- " + failure)
	get_tree().quit(1)

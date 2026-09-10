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
##  4. **Los dos limites** que pidio el usuario: el ancho no pasa de la fachada
##     construida -y no basta con que no sea mas ancho, tiene que CABER: junto
##     a la esquina se estrecha, centrado en su hueco, para no asomar por el
##     canto del edificio- y el vuelo no puede ser incoherente. El tope son
##     2 m, y el canto de la losa sube con el vuelo (regla del voladizo,
##     canto >= vuelo / 10).
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

## Tool.ROOM del editor. Se copia el numero, como hacen los demas guardarrailes
## que manejan el editor: el enum es suyo y no se exporta.
const TOOL_ROOM: int = 1

var _failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	await get_tree().process_frame
	_check_serializer()
	await _check_editor_tool()
	await _check_geometry()
	await _check_limits()
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
	if absf(float(recortado.get("balcony_depth_m", 0.0)) - OpeningModel.BALCONY_MAX_DEPTH_M) > TOL_M:
		_fail("el vuelo no se recorta al maximo: %.2f m" % float(recortado.get("balcony_depth_m", 0.0)))
	if absf(float(recortado.get("balcony_parapet_m", 0.0)) - 0.60) > TOL_M:
		_fail("el antepecho no se levanta al minimo: %.2f m" % float(recortado.get("balcony_parapet_m", 0.0)))


## --- La herramienta del editor ---
##
## Una balconera es UNA cosa, no una puerta a la que despues se le marca una
## casilla: la herramienta la crea entera -exterior, hasta el suelo y con su
## balcon-. Y se niega en un tabique interior, porque ahi no hay fachada.
func _check_editor_tool() -> void:
	var packed := load("res://scenes/ScenarioEditorScene.tscn") as PackedScene
	var editor: Node = packed.instantiate()
	add_child(editor)
	await get_tree().process_frame
	await get_tree().process_frame

	editor.editor_data = {
		"floors": [{"name": FloorNaming.label(0), "level_m": 0.0}],
		"exterior_walls": [], "room_rect_m": {}, "rooms_data": [],
		"openings_data": [], "detectors": [], "victims": [],
		"player_start": {}, "ignition_room_id": -1,
	}
	editor.current_floor_index = 0
	# Dos salas pegadas: la fachada de la primera es exterior, el tabique que
	# comparten no lo es.
	editor.current_tool = TOOL_ROOM
	editor._handle_press(Vector2(0.0, 0.0))
	editor._handle_release(Vector2(5.0, 4.0))
	editor.current_tool = TOOL_ROOM
	editor._handle_press(Vector2(0.0, 4.0))
	editor._handle_release(Vector2(5.0, 8.0))

	editor._create_balcony_door_at(Vector2(2.5, 0.02))
	var openings: Array = editor.editor_data.get("openings_data", [])
	if openings.is_empty():
		_fail("la herramienta de puerta de balcon no creo nada en una fachada")
	else:
		var op: Dictionary = openings[openings.size() - 1]
		if String(op.get("type", "")) != "door":
			_fail("la puerta de balcon no se crea como puerta, sino como %s" % String(op.get("type", "")))
		if absf(float(op.get("sill_m", -1.0))) > TOL_M:
			_fail("la puerta de balcon no llega al suelo: alfeizar %.2f m" % float(op.get("sill_m", -1.0)))
		if not bool(op.get("has_balcony", false)):
			_fail("la puerta de balcon nace sin balcon")
		if int(op.get("b", 0)) != -1 and int(op.get("a", 0)) != -1:
			_fail("la puerta de balcon no da al exterior")
		if float(op.get("height_m", 0.0)) < 1.90:
			_fail("la puerta de balcon mide %.2f m de alto: no es una balconera" % float(op.get("height_m", 0.0)))

	# En el tabique compartido tiene que negarse.
	var antes: int = Array(editor.editor_data.get("openings_data", [])).size()
	editor._create_balcony_door_at(Vector2(2.5, 4.0))
	if Array(editor.editor_data.get("openings_data", [])).size() != antes:
		_fail("la herramienta cuelga un balcon de un tabique interior")

	var errores: Array = Serializer.validate_scenario(editor.editor_data)
	if not errores.is_empty():
		_fail("el escenario con puerta de balcon no valida: %s" % str(errores))

	remove_child(editor)
	editor.free()


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


## --- Los dos limites: el ancho y el vuelo ---
##
## El ancho no puede pasar de la fachada construida, y el vuelo no puede ser
## incoherente con lo que sostiene una losa en voladizo. Los dos se piden a lo
## bestia: si el codigo no los recorta, se ve enseguida.
func _check_limits() -> void:
	# Ancho absurdo: cuarenta metros de balcon en un piso de diez.
	var ancho: Dictionary = _scenario_with_balcony(40.0, FLIGHT_M, true)
	var built: Dictionary = await _build(ancho, true)
	var fp: FirstPersonController = built.get("fp")
	if fp == null:
		return
	var index: int = int(ancho.get("_balcony_index", 0))
	var slab: MeshInstance3D = _find_mesh(fp, "OwnBalconySlab_%02d" % index)
	var barrier: StaticBody3D = _find_node(fp, "OwnBalconyBarrier_%02d" % index) as StaticBody3D
	if slab == null or barrier == null:
		_fail("con un ancho absurdo no se construye el balcon en absoluto")
		_drop(built)
		return
	var slab_size: Vector3 = _box_size(slab)
	var along_m: float = maxf(slab_size.x, slab_size.z)
	# Cota independiente de lo que se valida: la fachada construida no puede
	# medir mas que la caja del edificio mas los margenes del lienzo.
	var techo_m: float = _building_extent_m(built.get("building"), slab_size.x >= slab_size.z) 		+ 2.0 * fp.own_facade_side_margin_m
	if along_m > techo_m + TOL_M:
		_fail("el balcon mide %.2f m y la fachada construida no llega a %.2f m" % [along_m, techo_m])
	if along_m < float(Dictionary(ancho.get("_balcony_opening", {})).get("width_m", 0.9)):
		_fail("el recorte del ancho se paso de largo: %.2f m para un hueco mas ancho" % along_m)
	# Y no basta con que no sea mas ANCHO que la fachada: tiene que caber
	# DENTRO. Un balcon junto a la esquina con el ancho de toda la fachada no
	# se pasa de ancho y sin embargo asoma por el canto del edificio.
	#
	# El mundo FP se centra en la caja del edificio, asi que el borde del
	# lienzo cae en +-(lado / 2 + margen). Se mide asi, y no preguntandoselo al
	# codigo que se valida.
	var along_x: bool = slab_size.x >= slab_size.z
	var borde_m: float = _building_extent_m(built.get("building"), along_x) * 0.5 		+ fp.own_facade_side_margin_m
	var centro_m: float = slab.global_position.x if along_x else slab.global_position.z
	if absf(centro_m) + along_m * 0.5 > borde_m + TOL_M:
		_fail("el balcon asoma %.2f m por el canto de la fachada" % (absf(centro_m) + along_m * 0.5 - borde_m))
	_drop(built)

	# Vuelo al maximo: la losa tiene que engordar con el.
	var hondo: Dictionary = _scenario_with_balcony(SPAN_M, OpeningModel.BALCONY_MAX_DEPTH_M)
	var built2: Dictionary = await _build(hondo, true)
	var fp2: FirstPersonController = built2.get("fp")
	if fp2 == null:
		return
	var slab2: MeshInstance3D = _find_mesh(fp2, "OwnBalconySlab_%02d" % int(hondo.get("_balcony_index", 0)))
	if slab2 == null:
		_fail("con el vuelo al maximo no se construye la losa")
		_drop(built2)
		return
	var canto_m: float = _box_size(slab2).y
	var esperado_m: float = maxf(
		fp2.own_balcony_slab_thickness_m,
		OpeningModel.BALCONY_MAX_DEPTH_M / OpeningModel.BALCONY_MIN_DEPTH_TO_THICKNESS
	)
	if absf(canto_m - esperado_m) > TOL_M:
		_fail("un balcon de %.2f m de vuelo lleva un canto de %.2f m y le tocan %.2f m" % [
			OpeningModel.BALCONY_MAX_DEPTH_M, canto_m, esperado_m])
	_drop(built2)


## Lo que mide el edificio a lo largo de un eje. Es la cota de arriba de lo que
## puede medir una fachada, y se calcula aparte para no preguntarselo al codigo
## que se esta validando.
func _building_extent_m(building: BuildingModel, along_x: bool) -> float:
	if building == null:
		return 0.0
	var bounds: Rect2 = Rect2()
	var first: bool = true
	for room_id in building.get_room_rects_m().keys():
		var rect: Rect2 = Rect2(building.get_room_rects_m()[room_id])
		bounds = rect if first else bounds.merge(rect)
		first = false
	return bounds.size.x if along_x else bounds.size.y


## Un piso del catalogo, con su primera ventana exterior convertida en
## balconera: puerta hasta el suelo, con balcon. Se elige una ventana porque
## la puerta de un piso da al portal, y ahi no hay calle.
func _scenario_with_balcony(span_m: float = SPAN_M, flight_m: float = FLIGHT_M, al_canto: bool = false) -> Dictionary:
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
		op["balcony_width_m"] = span_m
		op["balcony_depth_m"] = flight_m
		if al_canto:
			# Pegada a la esquina: es el caso donde recortar y descentrar dejan
			# de dar lo mismo. Con la abertura en mitad de su fachada, un
			# balcon demasiado ancho asoma por los dos lados por igual y un
			# recorte mal hecho pasa desapercibido.
			op["offset_m"] = 0.0
			op["offset_is_fraction"] = false
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

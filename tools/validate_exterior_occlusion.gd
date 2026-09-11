extends Node

## Guardarrail del fondo: por debajo del horizonte no puede verse el cielo.
##
## El sintoma que lo motiva: desde una planta alta, media ventana era una
## superficie gris uniforme. No era un edificio ni el telon del skyline; era el
## **domo del cielo por debajo del horizonte**, que se ve en cuanto no hay nada
## construido en esa direccion. A ras de calle no se nota porque el pavimento
## llena la mitad de abajo; desde la planta 35 no hay pavimento que llene.
##
## La causa, medida con `tools/probe_exterior_occlusion.gd`: el decorado se
## construia **por fachada**, y solo delante de las fachadas con ventana. Un
## rayo a 30 grados desde el hueco no encontraba nada porque en esa direccion
## no se habia construido nada. Es la leccion de EXT-1 otra vez: por manzana,
## no por fachada.
##
## Lo que fija esta red:
##
##  - **De la horizontal hacia abajo, ningun rayo puede acabar en cielo.** Es el
##    fondo que el usuario ve por la ventana.
##  - **Mirando claramente hacia arriba si tiene que haber cielo.** Taparlo todo
##    tambien esta mal: una ventana enteramente negra no es una ventana.
##
## Se comprueba en las tres tipologias -manzana, torre y rascacielos-, porque
## cada una construye el fondo con piezas distintas.
##
##   <godot> --headless --path . res://tools/validate_exterior_occlusion.tscn

const BuildingModelScript := preload("res://sim/BuildingModel.gd")
const CaptureTool := preload("res://tools/capture_visual_reference.gd")
const FirstPersonControllerScript := preload("res://view/fp/FirstPersonController.gd")

## Una planta de cada tramo, mas una baja de control.
const FLOORS: Array[int] = [0, 5, 15, 35, 65]

## Cabeceos que tienen que estar TAPADOS, en grados.
const BLOCKED_PITCHES: Array[float] = [0.0, -10.0, -25.0]

## Cabeceo que tiene que dejar ver cielo.
const OPEN_PITCH: float = 45.0

## Abanico horizontal, en grados. Es el que abarca una ventana al asomarse.
const YAWS: Array[float] = [-40.0, -30.0, -20.0, -10.0, 0.0, 10.0, 20.0, 30.0, 40.0]

var _failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	for planta in FLOORS:
		await _check(int(planta))
	if _failures.is_empty():
		print("EXTERIOR OCCLUSION VALIDATION PASS")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("[validate_exterior_occlusion] FAIL: " + failure)
	print("EXTERIOR OCCLUSION VALIDATION FAILED")
	get_tree().quit(1)


func _check(planta: int) -> void:
	var tool_node = CaptureTool.new()
	var tpl: Dictionary = tool_node._make_template()
	tool_node.free()
	tpl["apartment_floor_number"] = planta
	var building: BuildingModel = BuildingModelScript.new()
	building.load_template_data(tpl)

	var host := Node3D.new()
	add_child(host)
	var fp: FirstPersonController = FirstPersonControllerScript.new()
	host.add_child(fp)
	await get_tree().process_frame
	fp.setup(building)
	await get_tree().physics_frame
	await get_tree().process_frame

	var world := fp.get_node_or_null("FirstPersonWorld") as Node3D
	if world == null:
		_failures.append("planta %d: no se construyo el mundo" % planta)
		host.queue_free()
		building.free()
		return

	var cajas: Array = _boxes(world)
	var origen: Vector3 = _window_center(world)
	var frente := Vector3(1.0, 0.0, 0.0)

	var abiertos: Array[String] = []
	for pitch in BLOCKED_PITCHES:
		for yaw in YAWS:
			if _hits_sky(origen, _direction(frente, float(yaw), float(pitch)), cajas):
				abiertos.append("%+.0f/%+.0f" % [yaw, pitch])
	if not abiertos.is_empty():
		_failures.append("planta %d: %d rayos de %d acaban en cielo por debajo del horizonte (yaw/cabeceo: %s)" % [
			planta, abiertos.size(), BLOCKED_PITCHES.size() * YAWS.size(),
			", ".join(abiertos.slice(0, 6))])

	# **N-3: desde la ventana no se mira hacia ABAJO a la fila de fondo.**
	#
	# Decision del usuario del 2026-09-11: «siempre poner bloques un poco mas
	# altos que el propio edificio para tapar el horizonte». Que ningun rayo
	# acabe en cielo es la consecuencia; esto comprueba la causa, y salta antes:
	# en la prueba de mutacion la regla canto ya en la planta 5, donde los rayos
	# todavia daban todos tapados por pura suerte de geometria.
	#
	# Se mide contra la **altura del ojo**, no contra la cima del edificio en
	# coordenadas absolutas: el mundo se ancla en la vivienda y la calle cae por
	# debajo, asi que un numero absoluto no dice nada. Si un bloque de fondo
	# remata por debajo del ojo es que se le mira desde arriba, que es
	# exactamente lo que el usuario no quiere.
	var con_nombre: Array = _named_boxes(world)
	var bajo_el_ojo: Array[String] = []
	var medidos: int = 0
	for raw_caja in con_nombre:
		var caja: Dictionary = raw_caja
		var nombre: String = String(caja.get("name", ""))
		if not nombre.begins_with("BackBlock"):
			continue
		medidos += 1
		var aabb: AABB = caja["aabb"]
		var cima: float = aabb.position.y + aabb.size.y
		if cima < origen.y:
			bajo_el_ojo.append("%s (%.1f m)" % [nombre, cima])
	if medidos == 0:
		_failures.append("planta %d: no hay ni un bloque de fondo que medir" % planta)
	elif not bajo_el_ojo.is_empty():
		_failures.append("planta %d: %d de %d bloques de fondo rematan POR DEBAJO del ojo (%.1f m): se les mira desde arriba y dejan ver el horizonte: %s" % [
			planta, bajo_el_ojo.size(), medidos, origen.y, ", ".join(bajo_el_ojo.slice(0, 4))])

	var cielo_arriba: int = 0
	for yaw in YAWS:
		if _hits_sky(origen, _direction(frente, float(yaw), OPEN_PITCH), cajas):
			cielo_arriba += 1
	if cielo_arriba == 0:
		_failures.append("planta %d: mirando a %+.0f grados tampoco se ve cielo; el decorado tapa hasta arriba" % [
			planta, OPEN_PITCH])

	if _failures.is_empty() or true:
		print("  planta %2d: %d cajas, %d rayos tapados de %d, cielo arriba en %d de %d" % [
			planta, cajas.size(),
			BLOCKED_PITCHES.size() * YAWS.size() - abiertos.size(),
			BLOCKED_PITCHES.size() * YAWS.size(), cielo_arriba, YAWS.size()])
	host.queue_free()
	building.free()
	await get_tree().process_frame


func _direction(frente: Vector3, yaw: float, pitch: float) -> Vector3:
	var dir: Vector3 = frente.rotated(Vector3.UP, deg_to_rad(yaw))
	return dir.rotated(dir.cross(Vector3.UP).normalized(), deg_to_rad(pitch)).normalized()


## Cajas del decorado en coordenadas de mundo. No hay colision que consultar:
## el decorado son mallas sueltas, asi que se cruza el rayo contra su AABB.
func _boxes(world: Node3D) -> Array:
	var cajas: Array = []
	var pendientes: Array = [world]
	while not pendientes.is_empty():
		var node: Node = pendientes.pop_back()
		for child in node.get_children():
			pendientes.append(child)
		var mesh := node as MeshInstance3D
		if mesh == null or mesh.mesh == null or not mesh.visible:
			continue
		var local: AABB = mesh.get_aabb()
		var g: Transform3D = mesh.global_transform
		var caja := AABB(g * local.position, Vector3.ZERO)
		for i in range(1, 8):
			caja = caja.expand(g * local.get_endpoint(i))
		cajas.append(caja)
	return cajas


## Las mallas visibles del mundo, con su nombre. `_boxes()` devuelve solo cajas
## anonimas y para la regla de N-3 hace falta saber cual es cual.
func _named_boxes(world: Node3D) -> Array:
	var out: Array = []
	var pendientes: Array = [world]
	while not pendientes.is_empty():
		var node: Node = pendientes.pop_back()
		for child in node.get_children():
			pendientes.append(child)
		var mesh := node as MeshInstance3D
		# `visible` y no `is_visible_in_tree()`: este guardarrail mide el mundo
		# tal y como lo recorren sus propios rayos en `_boxes()`, y ahi el arbol
		# no siempre esta colgado. Mezclar los dos criterios daba cero cajas.
		if mesh == null or mesh.mesh == null or not mesh.visible:
			continue
		var local: AABB = mesh.get_aabb()
		var g: Transform3D = mesh.global_transform
		var caja := AABB(g * local.position, Vector3.ZERO)
		for i in range(1, 8):
			caja = caja.expand(g * local.get_endpoint(i))
		out.append({"name": String(mesh.name), "aabb": caja})
	return out


func _hits_sky(origen: Vector3, dir: Vector3, cajas: Array) -> bool:
	for caja in cajas:
		var punto = (caja as AABB).intersects_ray(origen, dir)
		if punto == null:
			continue
		if origen.distance_to(punto) >= 1.0:
			return false
	return true


## El hueco de la ventana del dormitorio del piso patron, un palmo por dentro.
func _window_center(world: Node3D) -> Vector3:
	var mejor := Vector3(9.0, 1.6, 2.6)
	var pendientes: Array = [world]
	while not pendientes.is_empty():
		var node: Node = pendientes.pop_back()
		for child in node.get_children():
			pendientes.append(child)
		if not String(node.name).begins_with("WindowGlass"):
			continue
		var n3 := node as Node3D
		if n3 != null:
			mejor = n3.global_position
			mejor.x -= 0.35
	return mejor

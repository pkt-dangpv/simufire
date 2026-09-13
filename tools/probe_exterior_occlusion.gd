extends Node

## Que hay delante del ojo al asomarse a la ventana, rayo a rayo.
##
## Nace de una pregunta que no supe contestar mirando una captura: desde la
## planta 35 media ventana era una superficie gris uniforme y no habia forma de
## saber si era un edificio, el telon del skyline o el propio domo del cielo por
## debajo del horizonte. Una foto no dice el nombre del nodo; esto si.
##
## Lanza un abanico de rayos desde el hueco de la ventana y, para cada uno,
## busca la primera caja del decorado que atraviesa. No usa fisica: el decorado
## no tiene colision, asi que se cruza el rayo contra el AABB de cada malla.
##
##   <godot> --headless --path . res://tools/probe_exterior_occlusion.tscn [-- --floor=35]

const BuildingModelScript := preload("res://sim/BuildingModel.gd")
const CaptureTool := preload("res://tools/capture_visual_reference.gd")
const FirstPersonControllerScript := preload("res://view/fp/FirstPersonController.gd")

## Plantas que se miran si no se pide otra cosa: una de cada tramo.
const FLOORS: Array[int] = [5, 15, 35, 65]

## Cabeceos del abanico, en grados. El 0 es la horizontal: es el que dice si el
## fondo esta tapado a la altura del ojo, que es lo que importa.
const PITCHES: Array[float] = [25.0, 10.0, 0.0, -10.0]

## Giros del abanico, en grados respecto a la normal de la fachada.
const YAWS: Array[float] = [-50.0, -40.0, -30.0, -20.0, -10.0, 0.0, 10.0, 20.0, 30.0, 40.0, 50.0]


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var floors: Array = FLOORS
	for arg in OS.get_cmdline_user_args():
		if String(arg).begins_with("--floor="):
			floors = [int(String(arg).trim_prefix("--floor="))]
	for planta in floors:
		await _probe(int(planta))
	get_tree().quit(0)


func _probe(planta: int) -> void:
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
		print("planta %d: no hay mundo" % planta)
		host.queue_free()
		building.free()
		return

	# Cajas del decorado, en coordenadas de mundo.
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
		var esquina: Vector3 = g * local.position
		var caja := AABB(esquina, Vector3.ZERO)
		for i in range(1, 8):
			caja = caja.expand(g * (local.position + local.get_endpoint(i) - local.position))
		cajas.append({"nombre": String(mesh.name), "aabb": caja})

	# El ojo: en el hueco de la ventana del dormitorio, mirando a la calle.
	var ventana: Vector3 = _window_center(fp)
	var origen: Vector3 = ventana
	var frente := Vector3(1.0, 0.0, 0.0)

	print("")
	print("=== planta %d — %d cajas de decorado, ojo a y=%.1f ===" % [planta, cajas.size(), origen.y])
	for pitch in PITCHES:
		var fila: String = "  cabeceo %+4.0f:" % pitch
		for yaw in YAWS:
			var dir: Vector3 = frente.rotated(Vector3.UP, deg_to_rad(yaw))
			dir = dir.rotated(dir.cross(Vector3.UP).normalized(), deg_to_rad(pitch)).normalized()
			fila += " %-10s" % _short_hit(origen, dir, cajas)
		print(fila)
	host.queue_free()
	building.free()
	await get_tree().process_frame


## Version corta para la tabla de barrido: familia y distancia.
func _short_hit(origen: Vector3, dir: Vector3, cajas: Array) -> String:
	var texto: String = _first_hit(origen, dir, cajas)
	if texto == "CIELO":
		return "-cielo-"
	var partes: PackedStringArray = texto.split(" @")
	var familia: String = partes[0].split("_")[0]
	return "%s %s" % [familia.substr(0, 7), partes[1] if partes.size() > 1 else ""]


## Nombre de la primera caja que atraviesa el rayo, o "CIELO" si no hay ninguna.
func _first_hit(origen: Vector3, dir: Vector3, cajas: Array) -> String:
	var mejor: float = INF
	var nombre: String = "CIELO"
	for caja in cajas:
		var aabb: AABB = caja["aabb"]
		var punto = aabb.intersects_ray(origen, dir)
		if punto == null:
			continue
		var d: float = origen.distance_to(punto)
		if d < 1.0 or d >= mejor:
			continue
		mejor = d
		nombre = String(caja["nombre"])
	if nombre == "CIELO":
		return "CIELO"
	return "%s @%.0fm" % [nombre, mejor]


## Centro del hueco de la ventana del dormitorio del piso patron, un palmo por
## dentro para no arrancar el rayo dentro del propio marco.
func _window_center(fp: Node) -> Vector3:
	var world := fp.get_node_or_null("FirstPersonWorld") as Node3D
	var mejor: Vector3 = Vector3(9.0, 1.6, 2.6)
	if world == null:
		return mejor
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

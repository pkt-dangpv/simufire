extends Node

## Que se VE cuando el HUD dice 850 kW: la llama construida, medida.
##
## El hallazgo G-5 dice que el fuego se lee flojo para lo que marca el numero, y
## no estaba diagnosticado. Comparar formulas no basta -la ley vieja da 1,79 m
## sobre el papel-, asi que esto monta el mundo de primera persona con el mismo
## estado de incendio que usan las capturas de referencia y mide **la malla que
## se construye de verdad**: hasta donde llega, cuanto ocupa y cuanta luz da.
##
##   <godot> --headless --path . res://tools/probe_fp_fire_scale.tscn

const BuildingModelScript := preload("res://sim/BuildingModel.gd")
const CaptureTool := preload("res://tools/capture_visual_reference.gd")
const FirstPersonControllerScript := preload("res://view/fp/FirstPersonController.gd")

## Los mismos HRR que se quieren poder leer de un vistazo.
const CASES: Array[float] = [120.0, 400.0, 850.0, 1800.0, 3500.0]


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	print("HRR del HUD   llama (m)   radio (m)   luz (energia)   alcance (m)   techo util (m)")
	for hrr in CASES:
		await _probe(float(hrr))
	get_tree().quit(0)


func _probe(hrr_kw: float) -> void:
	var tool_node = CaptureTool.new()
	var tpl: Dictionary = tool_node._make_template()
	tool_node.fire_hrr_kw = hrr_kw
	var estado: Dictionary = tool_node._make_fire_state()
	tool_node.free()

	var building: BuildingModel = BuildingModelScript.new()
	building.load_template_data(tpl)

	var host := Node3D.new()
	add_child(host)
	var fp: FirstPersonController = FirstPersonControllerScript.new()
	host.add_child(fp)
	await get_tree().process_frame
	fp.setup(building)
	# Sin activarlo, el mundo entero cuelga oculto y no hay nada que medir.
	fp.set_active(true)
	await get_tree().physics_frame
	fp.set_state(estado)
	# La llama se acerca a su tamano con suavizado: hay que dejarla llegar.
	# La llama crece con el reloj, y el reloj de la llama es el de fisica.
	for i in range(120):
		await get_tree().physics_frame

	var datos: Dictionary = _measure(fp)
	print("%9.0f kW   %7.2f     %7.2f     %11.2f     %7.2f       %7.2f" % [
		hrr_kw, datos.get("alto", 0.0), datos.get("radio", 0.0),
		datos.get("energia", 0.0), datos.get("alcance", 0.0), datos.get("util", 0.0)])
	host.queue_free()
	building.free()
	await get_tree().process_frame


## Mide la llama construida: la caja de todo lo que cuelga del nodo de fuego.
func _measure(fp: Node) -> Dictionary:
	var world := fp.get_node_or_null("FirstPersonWorld") as Node3D
	if world == null:
		return {}
	var raiz: Node3D = null
	var pendientes: Array = [world]
	while not pendientes.is_empty():
		var node: Node = pendientes.pop_back()
		for child in node.get_children():
			pendientes.append(child)
		if not (String(node.name).begins_with("FireRoot") or String(node.name).begins_with("FPFire")):
			continue
		var candidata := node as Node3D
		if candidata != null and candidata.is_visible_in_tree():
			raiz = candidata
	if raiz == null:
		return {}

	var caja := AABB()
	var primera: bool = true
	var luz: OmniLight3D = null
	pendientes = [raiz]
	while not pendientes.is_empty():
		var node: Node = pendientes.pop_back()
		for child in node.get_children():
			pendientes.append(child)
		if node is OmniLight3D:
			luz = node
		var mesh := node as MeshInstance3D
		# `visible` mira solo la propia bandera: la sala SIN fuego tiene su nodo
		# de llama construido y oculto por el padre, y sus mallas se colaban en
		# la medida como un metro de llama fantasma en el origen.
		if mesh == null or mesh.mesh == null or not mesh.is_visible_in_tree():
			continue
		var local: AABB = mesh.get_aabb()
		var g: Transform3D = mesh.global_transform
		var propia := AABB(g * local.position, Vector3.ZERO)
		for i in range(1, 8):
			propia = propia.expand(g * local.get_endpoint(i))
		if OS.get_environment("SF_DETALLE") != "":
			print("      %-22s alto=%.2f  ancho=%.2f  base_y=%.2f" % [
				String(mesh.name), propia.size.y, propia.size.x, propia.position.y])
		caja = propia if primera else caja.merge(propia)
		primera = false

	return {
		"alto": 0.0 if primera else caja.size.y,
		"radio": 0.0 if primera else maxf(caja.size.x, caja.size.z) * 0.5,
		"energia": luz.light_energy if luz != null else 0.0,
		"alcance": luz.omni_range if luz != null else 0.0,
		"util": raiz.get_meta("available_height_m", 0.0) if raiz.has_meta("available_height_m") else 0.0,
	}

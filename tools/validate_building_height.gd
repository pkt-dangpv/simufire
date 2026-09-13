extends Node

## Guardarrail de la altura: la planta en la que esta el piso tiene que llegar
## a la vista, y los vecinos tienen que acompanarla.
##
## Lo que fija, y por que existe cada regla:
##
## - **La calle cae segun la planta.** Antes se hundia una constante de 5,8 m
##   fuese cual fuese la planta (`exterior_floor_drop_m`), asi que daba igual
##   la 1 que la 50: ese era el hallazgo N-3. Ahora cae una altura de planta
##   por cada planta que hay debajo, y esto lo comprueba comparando plantas
##   distintas: si dos plantas dan la misma cota, la regresion ha vuelto.
## - **Los vecinos tienen las mismas plantas que nosotros.** Decision del
##   usuario en N-4. La fachada de enfrente medía 15 m constantes, asi que
##   desde una planta alta se miraba por encima de toda la manzana.
## - **Una fila de ventanas por planta.** El tope viejo era de cuatro filas
##   (G-4): una fachada de 45 m repartia cuatro ventanas cada once metros y se
##   leia como un muro liso. La regla mide las filas REALES contando las cotas
##   distintas de los cristales construidos, no lo que diga el codigo.
## - **Una unifamiliar no se eleva.** La planta solo manda en un piso.
##
##   <godot> --headless --path . res://tools/validate_building_height.tscn

const BuildingModelScript := preload("res://sim/BuildingModel.gd")
const BuildingTemplateScript := preload("res://sim/templates/BuildingTemplate.gd")
const FirstPersonControllerScript := preload("res://view/fp/FirstPersonController.gd")

## Dos cotas de ventana se cuentan como la misma fila si distan menos que esto.
const ROW_EPS_M: float = 0.35

var _failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var baja: Dictionary = await _measure("compact_apartment", 0)
	var media: Dictionary = await _measure("compact_apartment", 5)
	var alta: Dictionary = await _measure("compact_apartment", 15)
	var casa: Dictionary = await _measure("simple_house", 15)
	# El segundo dato: el edificio tiene 30 plantas aunque solo se dibuje una y
	# se viva en la 15. Antes el edificio terminaba en el techo de la vivienda.
	var declarado: Dictionary = await _measure("compact_apartment", 15, 30)

	# 1. La calle cae segun la planta, y cada planta da una cota distinta.
	# Tolerancia de 5 cm: el suelo exterior se planta unos milimetros por debajo
	# a proposito, para no compartir plano con el forjado y pelear por el pixel.
	if absf(float(baja["caida_m"])) > 0.05:
		_failures.append("en la planta baja la calle deberia estar al pie y cae %.2f m" % baja["caida_m"])
	if float(media["caida_m"]) <= float(baja["caida_m"]) + 1.0:
		_failures.append("la planta 5 no baja la calle respecto a la baja (%.2f vs %.2f)" % [media["caida_m"], baja["caida_m"]])
	if float(alta["caida_m"]) <= float(media["caida_m"]) + 1.0:
		_failures.append("la planta 15 no baja la calle respecto a la 5 (%.2f vs %.2f)" % [alta["caida_m"], media["caida_m"]])
	# Y cae lo que tiene que caer: una altura de planta por planta.
	var esperado: float = 15.0 * float(alta["pitch_m"])
	if absf(float(alta["caida_m"]) - esperado) > 0.05:
		_failures.append("en la planta 15 la calle cae %.2f m y deberia caer %.2f" % [alta["caida_m"], esperado])

	# 2. Los vecinos acompanan la altura.
	for caso in [media, alta]:
		var propia: float = float(caso["plantas"]) * float(caso["pitch_m"])
		if float(caso["vecinos_m"]) < propia - 0.05:
			_failures.append("planta %d: los vecinos miden %.1f m y el edificio aparenta %.1f" % [
				caso["planta"], caso["vecinos_m"], propia])

	# 3. Una fila de ventanas por planta, medida en lo construido.
	if int(alta["filas"]) <= int(baja["filas"]) :
		_failures.append("la fachada alta tiene %d filas de ventanas y la baja %d: no crecen con la altura" % [
			alta["filas"], baja["filas"]])
	# Menos dos, no menos una: los modulos de la fachada no miden todos lo
	# mismo a proposito -si midieran lo mismo seria un muro- y el mas bajo se
	# queda a una fila del tope.
	var filas_esperadas: int = int(float(alta["vecinos_m"]) / float(alta["pitch_m"])) - 2
	if int(alta["filas"]) < filas_esperadas:
		_failures.append("la fachada de %.1f m tiene %d filas de ventanas y le caben %d" % [
			alta["vecinos_m"], alta["filas"], filas_esperadas])

	# 4. Las plantas declaradas mandan sobre las deducidas.
	if int(declarado["plantas"]) != 30:
		_failures.append("con 30 plantas declaradas el edificio aparenta %d" % declarado["plantas"])
	if float(declarado["vecinos_m"]) < 30.0 * float(declarado["pitch_m"]) - 0.05:
		_failures.append("con 30 plantas declaradas los vecinos solo miden %.1f m" % declarado["vecinos_m"])
	if float(declarado["encima_m"]) <= 1.0:
		_failures.append("con 30 plantas declaradas y la vivienda en la 15 no queda edificio por encima (%.1f m)" % declarado["encima_m"])

	# 5. Una unifamiliar no se eleva por mucho que diga la planta.
	if absf(float(casa["caida_m"])) > 0.05:
		_failures.append("una unifamiliar en 'planta 15' se eleva %.2f m: la planta solo vale para un piso" % casa["caida_m"])

	if _failures.is_empty():
		print("BUILDING HEIGHT VALIDATION PASS")
		for caso in [baja, media, alta]:
			print("  planta %2d: calle -%.2f m, vecinos %.1f m, %d filas de ventanas" % [
				caso["planta"], caso["caida_m"], caso["vecinos_m"], caso["filas"]])
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("[validate_building_height] FAIL: " + failure)
	print("BUILDING HEIGHT VALIDATION FAILED")
	get_tree().quit(1)


## Monta el mundo FP de un escenario en una planta y mide lo que se ve.
func _measure(template_name: String, floor_number: int, total_floors: int = 0) -> Dictionary:
	var builder = BuildingTemplateScript.new()
	var data: Dictionary = builder.create_by_name(template_name)
	data["apartment_floor_number"] = floor_number
	data["building_total_floors"] = total_floors
	var building: BuildingModel = BuildingModelScript.new()
	building.load_template_data(data)

	var host := Node3D.new()
	add_child(host)
	var fp: FirstPersonController = FirstPersonControllerScript.new()
	host.add_child(fp)
	await get_tree().process_frame
	fp.setup(building)
	await get_tree().physics_frame
	await get_tree().process_frame

	var span: Dictionary = {"min_y": 0.0}
	for key in building.get_rooms().keys():
		var room: RoomModel = building.get_room(int(key))
		if room != null:
			span["min_y"] = minf(float(span["min_y"]), room.floor_level_z_m)
	var caida: float = float(span["min_y"]) - fp._exterior_ground_level_m()

	var out: Dictionary = {
		"planta": floor_number,
		"caida_m": caida,
		"pitch_m": BuildingLevels.floor_to_floor_m(building, fp.exterior_storey_pitch_m),
		"plantas": BuildingLevels.apparent_total_floors(building),
		"vecinos_m": fp._neighbour_facade_height_m(),
		"filas": _window_rows(fp),
		"encima_m": BuildingLevels.floors_above_m(building, fp.exterior_storey_pitch_m),
	}
	host.queue_free()
	building.free()
	await get_tree().process_frame
	return out


## Filas de ventanas de UN modulo de la fachada de enfrente.
##
## Contar cotas distintas en todo el decorado no vale: los modulos tienen
## alturas algo distintas a proposito, asi que sus filas no coinciden y la
## cuenta salia inflada -50 "filas" en una fachada de 45 m-. El nombre del nodo
## ya trae el indice de planta, `CityWindowGlass_<fachada>_<modulo>_<planta>_<columna>`,
## y eso es lo que hay que leer.
func _window_rows(fp: Node) -> int:
	var world := fp.get_node_or_null("FirstPersonWorld") as Node3D
	if world == null:
		return 0
	var por_modulo: Dictionary = {}
	var pendientes: Array = [world]
	while not pendientes.is_empty():
		var node: Node = pendientes.pop_back()
		for child in node.get_children():
			pendientes.append(child)
		var name: String = String(node.name)
		if not name.begins_with("CityWindowGlass_"):
			continue
		var partes: PackedStringArray = name.trim_prefix("CityWindowGlass_").split("_")
		if partes.size() < 3:
			continue
		var modulo: String = partes[0] + "_" + partes[1]
		var planta: int = int(partes[2])
		var filas: Dictionary = por_modulo.get(modulo, {})
		filas[planta] = true
		por_modulo[modulo] = filas
	var mejor: int = 0
	for modulo in por_modulo.keys():
		mejor = maxi(mejor, Dictionary(por_modulo[modulo]).size())
	return mejor

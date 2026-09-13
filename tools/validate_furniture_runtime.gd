extends Node

const BuildingModelScript := preload("res://sim/BuildingModel.gd")
const BuildingTemplateScript := preload("res://sim/templates/BuildingTemplate.gd")
const Serializer := preload("res://editor/ScenarioSerializer.gd")
const SimulationStateBuilderScript := preload("res://sim/core/SimulationStateBuilder.gd")
const Visualizer3DScript := preload("res://view/3d/Visualizer3D.gd")
const FirstPersonControllerScript := preload("res://view/fp/FirstPersonController.gd")
const FurnitureShapeBuilder := preload("res://view/3d/furniture/FurnitureShapeBuilder.gd")
const FurnitureStateVisuals := preload("res://view/3d/furniture/FurnitureStateVisuals.gd")
const FurnitureVisualClassifier := preload("res://view/3d/furniture/FurnitureVisualClassifier.gd")
const FurnitureAssetLoader := preload("res://view/3d/furniture/FurnitureAssetLoader.gd")

## Donde viven los modelos de mobiliario.
const FURNITURE_ASSET_DIR: String = "res://assets/fp/furniture"

## El fichero del clasificador, que se lee como texto: ver _check_contract_is_complete().
const CLASSIFIER_PATH: String = "res://view/3d/furniture/FurnitureVisualClassifier.gd"

## Donde acaba visual_archetype(): el salto de linea va aparte para que el
## literal no lleve uno dentro.
const NEXT_FUNCTION_MARK: String = "\nstatic func "

## Muebles con modelo de verdad, de los que traen varios materiales.
const BURN_KINDS: Array[String] = ["sofa", "bed", "wardrobe"]

var _failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


## La lista de arquetipos no puede descolgarse del clasificador.
##
## ARCHETYPES esta escrita a MANO, y la comprobacion de abajo solo mira lo que
## hay en ella: un `return "x"` nuevo en el clasificador que nadie apunte en la
## lista se salta la red entera, y vuelve exactamente el fallo mudo que la red
## venia a matar -el arquetipo cae a cajas y nadie se entera-. Asi que aqui la
## lista se compara con los returns del propio fichero, leido como texto.
func _check_contract_is_complete() -> void:
	var source: String = _classifier_source()
	if source == "":
		_expect(false, "no se puede leer %s para comprobar el contrato" % CLASSIFIER_PATH)
		return

	var returned: Dictionary = {}
	var pattern := RegEx.create_from_string('return "([a-z_]+)"')
	for found in pattern.search_all(source):
		returned[found.get_string(1)] = true
	_expect(not returned.is_empty(),
		"no se ha encontrado ningun `return` en visual_archetype(): la lectura del fichero no vale")

	var listed: Dictionary = {}
	for archetype in FurnitureVisualClassifier.ARCHETYPES:
		listed[archetype] = true

	var missing: PackedStringArray = PackedStringArray()
	for archetype in returned:
		if not listed.has(archetype):
			missing.append(archetype)
	missing.sort()
	_expect(missing.is_empty(),
		"el clasificador devuelve arquetipos que no estan en ARCHETYPES, o sea sin red: %s"
			% ", ".join(missing))

	var stale: PackedStringArray = PackedStringArray()
	for archetype in listed:
		if not returned.has(archetype):
			stale.append(archetype)
	stale.sort()
	_expect(stale.is_empty(),
		"ARCHETYPES nombra arquetipos que el clasificador ya no devuelve: %s" % ", ".join(stale))


## El cuerpo de visual_archetype(), sin el resto del fichero.
##
## Se recorta a esa funcion porque es la unica que devuelve arquetipos; leer el
## fichero entero colaria como arquetipo cualquier cadena devuelta por otra.
func _classifier_source() -> String:
	var file := FileAccess.open(CLASSIFIER_PATH, FileAccess.READ)
	if file == null:
		return ""
	var text: String = file.get_as_text()
	file.close()
	var from: int = text.find("static func visual_archetype")
	if from < 0:
		return ""
	var to: int = text.find(NEXT_FUNCTION_MARK, from + 1)
	if to < 0:
		to = text.length()
	return text.substr(from, to - from)


## Cada arquetipo tiene que salir con su modelo, no con las cajas de respaldo.
##
## Las cajas existen para no quedarse sin nada que dibujar, y por eso el fallo es
## silencioso: un arquetipo sin fichero, o un fichero renombrado, sigue pintando
## algo -peor, pero algo- y nadie se entera hasta que lo ve en la pantalla. Con el
## catalogo creciendo, esta es la red.
func _check_every_archetype_has_a_model() -> void:
	# Se le pregunta al CARGADOR, que es quien conoce el mapa de alias. Construir
	# la pieza y mirar si devuelve tamaño no vale: la ruta de respaldo también
	# devuelve el suyo, así que un arquetipo sin modelo pasaba por bueno.
	var fallen_back: PackedStringArray = PackedStringArray()
	for archetype in FurnitureVisualClassifier.ARCHETYPES:
		if not FurnitureAssetLoader.has_model(archetype):
			fallen_back.append(archetype)
	_expect(fallen_back.is_empty(),
		"arquetipos que salen como cajas por no encontrar modelo: %s" % ", ".join(fallen_back))

	# Y al reves: un modelo que no carga o que llega sin mallas es un asset roto,
	# y desde fuera se ve igual que uno que falta.
	var broken: PackedStringArray = PackedStringArray()
	var dir := DirAccess.open(FURNITURE_ASSET_DIR)
	if dir == null:
		_expect(false, "no se puede abrir %s" % FURNITURE_ASSET_DIR)
		return
	for file_name in dir.get_files():
		if not file_name.ends_with(".tscn"):
			continue
		var packed := load("%s/%s" % [FURNITURE_ASSET_DIR, file_name]) as PackedScene
		if packed == null:
			broken.append("%s (no carga)" % file_name)
			continue
		var instance := packed.instantiate() as Node
		if instance == null:
			broken.append("%s (no se instancia)" % file_name)
			continue
		add_child(instance)
		if _mesh_count(instance) == 0:
			broken.append("%s (sin mallas)" % file_name)
		remove_child(instance)
		instance.free()
	_expect(broken.is_empty(), "modelos de mobiliario rotos: %s" % ", ".join(broken))

	# Y el tercer sentido: un modelo que NINGUN arquetipo alcanza. No da error, no
	# rompe nada -simplemente no aparece nunca en la casa-, y por eso el mueble de
	# bano estuvo en el catalogo sin que se dibujara una sola vez. Con el catalogo
	# creciendo esto es lo que hay que cazar: un modelo comprado y no usado.
	var reachable: Dictionary = {}
	for archetype in FurnitureVisualClassifier.ARCHETYPES:
		reachable[FurnitureAssetLoader.model_path(archetype)] = true
	var unreached: PackedStringArray = PackedStringArray()
	for file_name in dir.get_files():
		if not file_name.ends_with(".tscn"):
			continue
		if not reachable.has("%s/%s" % [FURNITURE_ASSET_DIR, file_name]):
			unreached.append(file_name)
	unreached.sort()
	_expect(unreached.is_empty(),
		"modelos que ningun arquetipo alcanza, o sea que no se dibujan nunca: %s"
			% ", ".join(unreached))


func _mesh_count(node: Node) -> int:
	var count: int = 0
	for child in node.get_children():
		if child is MeshInstance3D:
			count += 1
		count += _mesh_count(child)
	return count


## El fuego tiene que verse en los muebles.
##
## Los modelos importados no llevan material_override: sus materiales van POR
## SUPERFICIE, y el tinte de estados solo miraba el override. Resultado: las
## formas de respaldo -cajas- se calentaban y se ennegrecian, y los muebles de
## verdad ardian sin cambiar de aspecto. En un simulador de incendios eso es el
## fallo entero: ves arder la casa y el mobiliario sigue como recien comprado.
##
## Importa mas ahora que nunca, porque el catalogo de modelos va a crecer.
func _check_burning_changes_furniture() -> void:
	for kind in BURN_KINDS:
		var node := Node3D.new()
		add_child(node)
		var achieved: Vector3 = FurnitureShapeBuilder.rebuild(node, kind, Vector2(2.0, 0.9), 1.0, 0.8)
		_expect(achieved != Vector3.ZERO, "%s se ha construido con cajas: falta su modelo" % kind)
		var cold: Array = _albedo_colors(node)
		_expect(not cold.is_empty(), "%s no tiene ningun material que tenir" % kind)
		FurnitureStateVisuals.apply(node, "flaming", Color(1.0, 0.45, 0.1), 0.2, true)
		var flaming: Array = _albedo_colors(node)
		FurnitureStateVisuals.apply(node, "burned_out", Color(0.2, 0.2, 0.2), 0.0, false)
		var burned: Array = _albedo_colors(node)
		_expect(_changed(cold, flaming) == cold.size(),
			"%s ardiendo: cambian %d de %d materiales" % [kind, _changed(cold, flaming), cold.size()])
		_expect(_changed(cold, burned) == cold.size(),
			"%s calcinado: cambian %d de %d materiales" % [kind, _changed(cold, burned), cold.size()])
		for color in burned:
			_expect(Color(color).get_luminance() < Color(0.35, 0.35, 0.35).get_luminance(),
				"%s calcinado sigue claro (luminancia %.2f)" % [kind, Color(color).get_luminance()])
		remove_child(node)
		node.free()


## El albedo de cada material que pinta la pieza, venga del override o de una
## superficie del modelo.
func _albedo_colors(node: Node) -> Array:
	var out: Array = []
	_collect_albedo(node, out)
	return out


func _collect_albedo(node: Node, out: Array) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			var mesh_node := child as MeshInstance3D
			if mesh_node.name != "HeatGlow":
				var override_mat := mesh_node.material_override as StandardMaterial3D
				if override_mat != null:
					out.append(override_mat.albedo_color)
				var mesh := mesh_node.mesh
				if mesh != null:
					for surface_index in mesh.get_surface_count():
						var surface_mat := mesh_node.get_surface_override_material(surface_index) as StandardMaterial3D
						if surface_mat != null:
							out.append(surface_mat.albedo_color)
		if child.get_child_count() > 0:
			_collect_albedo(child, out)


func _changed(before: Array, after: Array) -> int:
	var count: int = 0
	for i in range(mini(before.size(), after.size())):
		if Color(before[i]) != Color(after[i]):
			count += 1
	return count


func _run() -> void:
	await get_tree().process_frame

	_check_contract_is_complete()
	_check_every_archetype_has_a_model()
	_check_burning_changes_furniture()

	var editor_data: Dictionary = _make_moved_simple_house()
	var runtime_json: Dictionary = Serializer.to_runtime_json_data(editor_data)
	var parsed: Variant = JSON.parse_string(JSON.stringify(runtime_json))
	_expect(typeof(parsed) == TYPE_DICTIONARY, "runtime JSON did not round-trip")
	if typeof(parsed) != TYPE_DICTIONARY:
		_finish()
		return

	var building: BuildingModel = BuildingModelScript.new()
	building.load_template_data(Dictionary(parsed))

	var moved_obj = _find_room_object(building, 0, "salon_sofa")
	_expect(moved_obj != null, "moved sofa was not loaded into BuildingModel")
	if moved_obj != null:
		_expect_close((moved_obj as FuelObjectModel).position_m.x, 2.40, 0.01, "BuildingModel lost moved object x")
		_expect_close((moved_obj as FuelObjectModel).position_m.y, 0.40, 0.01, "BuildingModel lost moved object y")
		_expect_close((moved_obj as FuelObjectModel).rotation_deg, 33.0, 0.01, "BuildingModel lost moved object rotation")
		_expect(bool((moved_obj as FuelObjectModel).visual_pose_locked), "BuildingModel lost visual_pose_locked")

	var state_builder = SimulationStateBuilderScript.new()
	var state: Dictionary = state_builder.build_state({
		"building": building,
		"sim_time_s": 0.0,
		"hvac": building.build_hvac_summary()
	})
	var room_state: Dictionary = Dictionary(state.get("0", {}))
	var state_obj: Dictionary = _find_snapshot_object(Array(room_state.get("fuel_objects", [])), "salon_sofa")
	_expect(not state_obj.is_empty(), "SimulationStateBuilder did not export moved sofa")
	if not state_obj.is_empty():
		_expect(bool(state_obj.get("visual_pose_locked", false)), "SimulationStateBuilder lost visual_pose_locked")
		_expect_close(_vec2_from_variant(state_obj.get("position_m", Vector2.ZERO)).x, 2.40, 0.01, "SimulationStateBuilder lost object x")

	var visualizer: Visualizer3D = Visualizer3DScript.new()
	visualizer.name = "FurnitureRuntimeVisualizer"
	visualizer.building = building
	_add_visualizer_children(visualizer)
	add_child(visualizer)
	await get_tree().process_frame
	visualizer.rebuild_from_building()
	visualizer.set_state({})
	await get_tree().process_frame

	var fuel_root := visualizer.get_node_or_null("Atmosphere/FuelObjects_00") as Node3D
	_expect(fuel_root != null, "Visualizer3D did not create room fuel root")
	var node := _find_fuel_node(fuel_root, "salon_sofa")
	_expect(node != null, "Visualizer3D did not render furniture with empty editor state")
	if node != null:
		_expect_close(float(node.get_meta("size_x_m", 0.0)), 0.90, 0.01, "Visualizer3D lost sofa width")
		_expect_close(float(node.rotation_degrees.y), 33.0, 0.01, "Visualizer3D lost sofa rotation")
		var origin_offset_m: Vector2 = _origin_offset_for_building(building)
		var expected_x: float = 2.40 + 0.90 * 0.5 + origin_offset_m.x
		var expected_z: float = 0.40 + 2.35 * 0.5 + origin_offset_m.y
		_expect_close(node.position.x, expected_x, 0.05, "Visualizer3D did not preserve moved sofa x")
		_expect_close(node.position.z, expected_z, 0.05, "Visualizer3D did not preserve moved sofa z")

	visualizer.set_active(true, false, false, true)
	visualizer.set_state({})
	await get_tree().process_frame
	if fuel_root != null:
		_expect(fuel_root.visible, "Furniture hidden in first-person overlay")

	var fp: FirstPersonController = FirstPersonControllerScript.new()
	fp.name = "FurnitureRuntimeFP"
	fp.exterior_context_enabled = false
	fp.show_fp_detectors = false
	fp.show_fp_victims = false
	add_child(fp)
	await get_tree().process_frame
	fp.setup(building)
	await get_tree().physics_frame
	fp.set_state(state)
	await get_tree().process_frame

	var fp_fuel_root := fp.get_node_or_null("FirstPersonWorld/FPFurniture/FuelObjects_00") as Node3D
	_expect(fp_fuel_root != null, "FirstPersonController did not create FP furniture room root")
	var fp_node := _find_fuel_node(fp_fuel_root, "salon_sofa")
	_expect(fp_node != null, "FirstPersonController did not render moved furniture")
	if fp_node != null:
		_expect_close(float(fp_node.get_meta("size_x_m", 0.0)), 0.90, 0.01, "FirstPersonController lost sofa width")
		_expect_close(float(fp_node.rotation_degrees.y), 33.0, 0.01, "FirstPersonController lost sofa rotation")
		var origin_offset_m: Vector2 = _origin_offset_for_building(building)
		var expected_x: float = 2.40 + 0.90 * 0.5 + origin_offset_m.x
		var expected_z: float = 0.40 + 2.35 * 0.5 + origin_offset_m.y
		_expect_close(fp_node.position.x, expected_x, 0.05, "FirstPersonController did not preserve moved sofa x")
		_expect_close(fp_node.position.z, expected_z, 0.05, "FirstPersonController did not preserve moved sofa z")
	if fp_fuel_root != null:
		_expect(fp_fuel_root.visible, "FP furniture room root was hidden")

	remove_child(fp)
	fp.free()
	remove_child(visualizer)
	visualizer.free()
	building.free()
	_finish()


func _make_moved_simple_house() -> Dictionary:
	var builder = BuildingTemplateScript.new()
	var data: Dictionary = Serializer.normalize_editor_data(builder.create_by_name("simple_house"))
	var rooms: Array = data.get("rooms_data", [])
	for i in range(rooms.size()):
		if typeof(rooms[i]) != TYPE_DICTIONARY:
			continue
		var room: Dictionary = rooms[i]
		if int(room.get("id", -1)) != 0:
			continue
		var objects: Array = room.get("fuel_objects", [])
		for j in range(objects.size()):
			if typeof(objects[j]) != TYPE_DICTIONARY:
				continue
			var obj: Dictionary = objects[j]
			if String(obj.get("id", "")) != "salon_sofa":
				continue
			obj["position_m"] = {"x": 2.40, "y": 0.40}
			obj["size_m"] = {"x": 0.90, "y": 2.35}
			obj["rotation_deg"] = 33.0
			obj["visual_pose_locked"] = true
			objects[j] = obj
			room["fuel_objects"] = objects
			rooms[i] = room
			data["rooms_data"] = rooms
			return Serializer.normalize_editor_data(data)
	return data


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
	camera.position = Vector3(0.0, 0.0, 13.0)
	camera_rig.add_child(camera)


func _find_room_object(building: BuildingModel, room_id: int, object_id: String):
	var room: RoomModel = building.get_room(room_id)
	if room == null:
		return null
	for obj in room.fuel_objects:
		if obj != null and String(obj.id) == object_id:
			return obj
	return null


func _find_snapshot_object(objects: Array, object_id: String) -> Dictionary:
	for raw in objects:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var obj: Dictionary = raw
		if String(obj.get("id", "")) == object_id:
			return obj
	return {}


func _find_fuel_node(root: Node, object_id: String) -> Node3D:
	if root == null:
		return null
	for child in root.get_children():
		var node := child as Node3D
		if node != null and String(node.get_meta("object_id", "")) == object_id:
			return node
	return null


func _vec2_from_variant(value: Variant) -> Vector2:
	if typeof(value) == TYPE_VECTOR2:
		return value
	if typeof(value) == TYPE_DICTIONARY:
		var data: Dictionary = value
		return Vector2(float(data.get("x", 0.0)), float(data.get("y", 0.0)))
	return Vector2.ZERO


func _origin_offset_for_building(building: BuildingModel) -> Vector2:
	var rects: Dictionary = building.get_room_rects_m()
	var first: bool = true
	var bounds := Rect2()
	for value in rects.values():
		var rect := Rect2(value)
		if first:
			bounds = rect
			first = false
		else:
			bounds = bounds.merge(rect)
	if first:
		return Vector2.ZERO
	return -(bounds.position + bounds.size * 0.5)


func _finish() -> void:
	if _failures.is_empty():
		print("FURNITURE RUNTIME VALIDATION PASS")
		get_tree().quit(0)
		return
	push_error("FURNITURE RUNTIME VALIDATION FAILED")
	for failure in _failures:
		push_error("- " + failure)
	get_tree().quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _expect_close(actual: float, expected: float, tolerance: float, message: String) -> void:
	if absf(actual - expected) > tolerance:
		_failures.append("%s (actual=%.4f expected=%.4f)" % [message, actual, expected])

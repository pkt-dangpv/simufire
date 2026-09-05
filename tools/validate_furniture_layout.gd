extends Node

## Guardarrail del mobiliario: tamano real y colocacion con logica.
##
## Mide lo que se CONSTRUYE, no lo que se pide. Monta el mundo en primera
## persona de cada plantilla del catalogo y comprueba, pieza a pieza:
##
##  1. que no se sale de su sala
##  2. que no ocupa el mismo sitio que otra
##  3. que no atraviesa el techo
##  4. que las piezas que van contra un paramento estan CONTRA un paramento
##  5. que nada tapa el paso de una puerta
##  6. que la altura es la del mueble real, no la que salga
##
## El punto 6 es el que cierra el fallo de origen: el tamano visual se sacaba
## de `size_m`, que es la huella del modelo de FUEGO, y con modelos que no
## vienen a escala eso daba camas de 1,52 m de largo y un frente de cocina
## convertido en un cubo de 1,46. Si alguien vuelve a atar el tamano a la
## huella de fuego, este test lo caza.
##
##   <godot> --headless --path . res://tools/validate_furniture_layout.tscn

const BuildingModelScript := preload("res://sim/BuildingModel.gd")
const BuildingTemplateScript := preload("res://sim/templates/BuildingTemplate.gd")
const Serializer := preload("res://editor/ScenarioSerializer.gd")
const FirstPersonControllerScript := preload("res://view/fp/FirstPersonController.gd")
const FurnitureDimensions := preload("res://view/furniture/FurnitureDimensions.gd")
const FurnitureRoomLayout := preload("res://view/furniture/FurnitureRoomLayout.gd")

## Las plantillas que hoy traen mobiliario. Las demas del catalogo declaran la
## carga de fuego a granel, sin objetos, y no hay nada que colocar en ellas.
const TEMPLATES: Array[String] = [
	"simple_house",
	"two_storey_house",
	"ghanekar_bedroom_hallway",
]

## Tolerancia antes de decir que una pieza se sale de su sala.
const OUT_EPS_M: float = 0.02

## Solape en planta a partir del cual dos piezas ocupan el mismo sitio.
const MAX_OVERLAP_M2: float = 0.01

## Solape vertical minimo para que el de planta cuente.
const MIN_VERTICAL_OVERLAP_M: float = 0.05

## Una pieza que no llega a esta altura es rasante: otras pueden estar encima.
const FLOOR_LEVEL_TOP_M: float = 0.12

## Separacion maxima al paramento de una pieza que deberia ir apoyada en el.
const WALL_TOLERANCE_M: float = 0.15

## Cuanto puede desviarse la altura construida de la del catalogo. El limite de
## deformacion del ajuste es del 12 %; se deja algo de aire por encima.
const HEIGHT_TOLERANCE: float = 0.18

## Vuelca ademas la tabla completa de piezas medidas.
const VERBOSE: bool = false

var _failures: Array[String] = []
var _lines: Array[String] = []
var _case: String = ""
var _pieces_seen: int = 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	await get_tree().process_frame
	for template_name in TEMPLATES:
		_case = template_name
		await _check_template(template_name)
	_finish()


func _check_template(template_name: String) -> void:
	var builder = BuildingTemplateScript.new()
	var editor_data: Dictionary = Serializer.normalize_editor_data(builder.create_by_name(template_name))
	var runtime_json: Dictionary = Serializer.to_runtime_json_data(editor_data)
	var parsed: Variant = JSON.parse_string(JSON.stringify(runtime_json))
	if typeof(parsed) != TYPE_DICTIONARY:
		_fail("no se pudo construir el edificio")
		return
	var building: BuildingModel = BuildingModelScript.new()
	building.load_template_data(Dictionary(parsed))

	var fp: FirstPersonController = FirstPersonControllerScript.new()
	fp.name = "ValidateFurnitureFP"
	fp.exterior_context_enabled = false
	fp.show_fp_detectors = false
	fp.show_fp_victims = false
	add_child(fp)
	await get_tree().process_frame
	fp.setup(building)
	await get_tree().physics_frame
	fp.set_state({})
	await get_tree().process_frame

	var furniture_root := fp.get_node_or_null("FirstPersonWorld/FPFurniture") as Node3D
	if furniture_root == null:
		_fail("no se creo FPFurniture")
		_drop(fp, building)
		return

	var origin_offset: Vector2 = _origin_offset_for_building(building)
	var rects: Dictionary = building.get_room_rects_m()

	for room_root in furniture_root.get_children():
		var node3d := room_root as Node3D
		if node3d == null:
			continue
		var room_id: int = int(String(node3d.name).replace("FuelObjects_", ""))
		var room: RoomModel = building.get_room(room_id)
		if room == null:
			continue
		var rect: Rect2 = Rect2(rects.get(room_id, Rect2()))
		var room_min := Vector2(rect.position.x + origin_offset.x, rect.position.y + origin_offset.y)
		var room_max: Vector2 = room_min + rect.size
		var floor_level: float = room.floor_level_z_m
		var doors: Array = FurnitureRoomLayout.doors_for_room(building, room_id, rect)

		var pieces: Array[Dictionary] = []
		for child in node3d.get_children():
			var node := child as Node3D
			if node == null:
				continue
			var aabb: AABB = _world_aabb(node)
			if aabb.size == Vector3.ZERO:
				continue
			pieces.append({
				"id": String(node.get_meta("object_id", node.name)),
				"kind": String(node.get_meta("kind_name", "")),
				"aabb": aabb,
			})
		if pieces.is_empty():
			continue
		_pieces_seen += pieces.size()
		if VERBOSE:
			_lines.append("  %s sala %d %s: %d piezas" % [_case, room_id, room.name, pieces.size()])

		for piece in pieces:
			var aabb: AABB = piece["aabb"]
			var id: String = piece["id"]
			var kind: String = piece["kind"]
			var top_m: float = aabb.position.y + aabb.size.y - floor_level

			if VERBOSE:
				_lines.append("    %-24s %-14s %.2f x %.2f x %.2f" % [
					id, kind, aabb.size.x, aabb.size.z, aabb.size.y
				])

			# 1. Dentro de su sala.
			var out_m: float = maxf(
				maxf(room_min.x - aabb.position.x, (aabb.position.x + aabb.size.x) - room_max.x),
				maxf(room_min.y - aabb.position.z, (aabb.position.z + aabb.size.z) - room_max.y)
			)
			if out_m > OUT_EPS_M:
				_fail("%s: %s (%s) se sale %.2f m de la sala %d" % [_case, id, kind, out_m, room_id])

			# 3. Por debajo del techo.
			if top_m > room.height_m - 0.02:
				_fail("%s: %s (%s) llega a %.2f m y la sala %d mide %.2f" % [
					_case, id, kind, top_m, room_id, room.height_m])

			# 6. Altura de mueble real. Solo para las piezas con forma propia:
			# una alfombra, un monton de ropa o un derrame no tienen altura de
			# catalogo que comprobar, la pone el escenario.
			var expected_h: float = 0.0 if FurnitureDimensions.fits_exactly(kind) else FurnitureDimensions.height_m(kind)
			if expected_h > 0.0 and absf(aabb.size.y - expected_h) > expected_h * HEIGHT_TOLERANCE:
				_fail("%s: %s (%s) mide %.2f m de alto y un %s mide %.2f" % [
					_case, id, kind, aabb.size.y, kind, expected_h])

			# 4. Las piezas de paramento, contra el paramento.
			if FurnitureDimensions.is_wall_hugging(kind) and not FurnitureDimensions.is_floor_level(kind):
				var gap: float = minf(
					minf(aabb.position.x - room_min.x, room_max.x - (aabb.position.x + aabb.size.x)),
					minf(aabb.position.z - room_min.y, room_max.y - (aabb.position.z + aabb.size.z))
				)
				if gap > WALL_TOLERANCE_M:
					_fail("%s: %s (%s) deberia ir contra un paramento y esta a %.2f m de todos, sala %d" % [
						_case, id, kind, gap, room_id])

			# 5. El paso de las puertas, libre.
			if top_m > FLOOR_LEVEL_TOP_M:
				for door in doors:
					var band: Rect2 = _door_band_world(rect, origin_offset, Dictionary(door))
					var inter: Rect2 = _plan_rect(aabb).intersection(band)
					if inter.size.x > 0.0 and inter.size.y > 0.0 and inter.size.x * inter.size.y > MAX_OVERLAP_M2:
						_fail("%s: %s (%s) tapa el paso de una puerta en la sala %d (%.2f m2)" % [
							_case, id, kind, room_id, inter.size.x * inter.size.y])
						break

		# 2. Dos piezas no ocupan el mismo sitio.
		for i in range(pieces.size()):
			for j in range(i + 1, pieces.size()):
				var a: AABB = pieces[i]["aabb"]
				var b: AABB = pieces[j]["aabb"]
				if a.position.y + a.size.y - floor_level <= FLOOR_LEVEL_TOP_M:
					continue
				if b.position.y + b.size.y - floor_level <= FLOOR_LEVEL_TOP_M:
					continue
				var inter: Rect2 = _plan_rect(a).intersection(_plan_rect(b))
				if inter.size.x <= 0.0 or inter.size.y <= 0.0:
					continue
				var area: float = inter.size.x * inter.size.y
				if area <= MAX_OVERLAP_M2:
					continue
				var vertical: float = minf(a.position.y + a.size.y, b.position.y + b.size.y) - maxf(a.position.y, b.position.y)
				if vertical < MIN_VERTICAL_OVERLAP_M:
					continue
				_fail("%s: %s y %s ocupan el mismo sitio en la sala %d (%.2f m2)" % [
					_case, pieces[i]["id"], pieces[j]["id"], room_id, area])

	_drop(fp, building)


func _drop(fp: Node, building: BuildingModel) -> void:
	remove_child(fp)
	fp.free()
	building.free()


func _plan_rect(aabb: AABB) -> Rect2:
	return Rect2(Vector2(aabb.position.x, aabb.position.z), Vector2(aabb.size.x, aabb.size.z))


func _door_band_world(rect: Rect2, origin_offset: Vector2, door: Dictionary) -> Rect2:
	var side: String = String(door.get("side", "top"))
	var center: float = float(door.get("center", 0.0))
	var width: float = maxf(0.2, float(door.get("width_m", 0.8)))
	var depth: float = 0.55
	var base := Vector2(rect.position.x + origin_offset.x, rect.position.y + origin_offset.y)
	match side:
		"top":
			return Rect2(base.x + center - width * 0.5, base.y, width, depth)
		"bottom":
			return Rect2(base.x + center - width * 0.5, base.y + rect.size.y - depth, width, depth)
		"left":
			return Rect2(base.x, base.y + center - width * 0.5, depth, width)
		_:
			return Rect2(base.x + rect.size.x - depth, base.y + center - width * 0.5, depth, width)


func _world_aabb(root: Node3D) -> AABB:
	var state: Array = [AABB(), false]
	_accumulate(root, state)
	return state[0]


func _accumulate(node: Node, state: Array) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			var mi := child as MeshInstance3D
			if mi.mesh != null and String(mi.name) != "HeatGlow":
				var aabb: AABB = mi.global_transform * mi.get_aabb()
				if not bool(state[1]):
					state[0] = aabb
					state[1] = true
				else:
					state[0] = (state[0] as AABB).merge(aabb)
		if child.get_child_count() > 0:
			_accumulate(child, state)


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


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	for line in _lines:
		print(line)
	if _pieces_seen == 0:
		push_error("FURNITURE LAYOUT VALIDATION FAILED")
		push_error("- no se midio ni una pieza: el mobiliario no llego a construirse")
		get_tree().quit(1)
		return
	if _failures.is_empty():
		print("piezas medidas: %d" % _pieces_seen)
		print("FURNITURE LAYOUT VALIDATION PASS")
		get_tree().quit(0)
		return
	push_error("FURNITURE LAYOUT VALIDATION FAILED")
	for failure in _failures:
		push_error("- " + failure)
	get_tree().quit(1)

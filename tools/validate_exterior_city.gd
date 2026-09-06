extends Node

## Guardarrail del decorado urbano que se ve por la ventana.
##
## Dos cosas se pueden comprobar sin mirar, y las dos las reporto el usuario:
##
##  1. **La calle no puede terminar en nada.** Si la calzada mide mas que las
##     fachadas que la flanquean, por la ventana se ve donde se acaba el mundo.
##     Se mide el largo de la calzada y el largo de lo edificado a su lado.
##  2. **Nada puede atravesar la calle.** Cada fachada del edificio genera su
##     propio decorado, y con varias fachadas los bloques de una pueden caer en
##     mitad de la calzada de otra. Un bloque cruzado delante de una ventana es
##     de lo mas visible que hay.
##
## Y una tercera que no es de geometria sino de contenido: que haya mobiliario
## urbano. Sin farolas, senales ni paso de cebra no hay escala y la calle se lee
## como un descampado con bloques.
##
##   <godot> --headless --path . res://tools/validate_exterior_city.tscn

const BuildingModelScript := preload("res://sim/BuildingModel.gd")
const BuildingTemplateScript := preload("res://sim/templates/BuildingTemplate.gd")
const Serializer := preload("res://editor/ScenarioSerializer.gd")
const FirstPersonControllerScript := preload("res://view/fp/FirstPersonController.gd")

## Solo los pisos generan calle; en unifamiliar el decorado es residencial.
const CASES: Array[Dictionary] = [
	{"template": "compact_apartment", "night": false},
	{"template": "two_bed_apartment", "night": true},
	{"template": "piso_mediterraneo", "night": false},
]

## Familias que SI pueden estar sobre la calzada.
## Familias que SI pueden estar sobre la calzada. El domo del cielo envuelve
## la escena entera por definicion; los coches estan aparcados en ella.
const ROAD_ALLOWED: Array[String] = [
	"Road", "RoadMark", "Crossing", "CityCar", "Sidewalk", "CityCurb", "FPSkyDome",
]

## Altura desde la que una pieza sobre la calzada estorba de verdad. Por debajo
## son bordillos y marcas.
const ROAD_CLEAR_HEIGHT_M: float = 0.35

## Cuanto puede quedarse corto lo edificado respecto de la calzada antes de que
## se vea el final de la calle.
const STREET_SHORTFALL_M: float = 1.0

## Minimos de mobiliario urbano, en numero de piezas por escenario.
const MIN_FURNITURE: Dictionary = {
	"StreetLamp": 6,
	"TrafficSign": 2,
	"Crossing": 5,
	"Bollard": 4,
	"Shopfront": 3,
	"Balcony": 6,
}

const VERBOSE: bool = false

var _failures: Array[String] = []
var _case: String = ""


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	await get_tree().process_frame
	for case_data in CASES:
		_case = String(case_data["template"])
		await _check(_case, bool(case_data["night"]))
	_finish()


func _check(template_name: String, night: bool) -> void:
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
	fp.name = "ValidateCityFP"
	fp.show_fp_detectors = false
	fp.show_fp_victims = false
	fp.exterior_lighting_mode = "Noche" if night else "Dia"
	add_child(fp)
	await get_tree().process_frame
	fp.setup(building)
	await get_tree().physics_frame
	fp.set_state({})
	await get_tree().process_frame

	var root := fp.get_node_or_null("FirstPersonWorld/ExteriorContext") as Node3D
	if root == null:
		_fail("no se genero ExteriorContext")
		_drop(fp, building)
		return

	var counts: Dictionary = {}
	var roads: Array[AABB] = []
	var blocks: Array[AABB] = []
	var obstacles: Array[Dictionary] = []
	for child in root.get_children():
		var node := child as Node3D
		if node == null:
			continue
		var node_name: String = String(node.name)
		var family: String = _family_of(node_name)
		counts[family] = int(counts.get(family, 0)) + 1
		var aabb: AABB = _world_aabb(node)
		if aabb.size == Vector3.ZERO:
			continue
		if family == "Road":
			roads.append(aabb)
		if _is_building_mass(family):
			blocks.append(aabb)
		if not ROAD_ALLOWED.has(family):
			obstacles.append({"name": node_name, "family": family, "aabb": aabb})

	# 1. La calle no termina en nada.
	for road in roads:
		var road_long: float = maxf(road.size.x, road.size.z)
		var along_x: bool = road.size.x >= road.size.z
		var built: float = _built_extent_along(blocks, road, along_x)
		if built + STREET_SHORTFALL_M < road_long:
			_fail("%s: la calzada mide %.1f m y lo edificado a su lado solo %.1f m: se ve el final de la calle" % [
				_case, road_long, built])

	# 2. Nada atraviesa la calzada.
	for road in roads:
		var band := AABB(
			Vector3(road.position.x, road.position.y + ROAD_CLEAR_HEIGHT_M, road.position.z),
			Vector3(road.size.x, 12.0, road.size.z)
		)
		for obstacle in obstacles:
			var aabb: AABB = obstacle["aabb"]
			if not band.intersects(aabb):
				continue
			var overlap: AABB = _intersection(band, aabb)
			# Un roce de centimetros es el canto de una acera, no un bloque.
			if overlap.size.x * overlap.size.z < 0.60:
				continue
			_fail("%s: %s (%s) cruza la calzada, %.1f x %.1f m de solape" % [
				_case, obstacle["name"], obstacle["family"], overlap.size.x, overlap.size.z])

	# 3. Hay ciudad, no un descampado con bloques.
	for family in MIN_FURNITURE.keys():
		var found: int = int(counts.get(family, 0))
		if found < int(MIN_FURNITURE[family]):
			_fail("%s: solo %d piezas de %s, hacen falta %d" % [
				_case, found, family, int(MIN_FURNITURE[family])])

	if VERBOSE:
		var keys: Array = counts.keys()
		keys.sort()
		for family in keys:
			print("  %s %-18s %d" % [_case, family, int(counts[family])])

	_drop(fp, building)


## Cuanto frente edificado hay a lo largo de la calzada, midiendo la union de
## los intervalos que ocupan los bloques -no la suma, que contaria dos veces lo
## que se solapa-.
func _built_extent_along(blocks: Array[AABB], road: AABB, along_x: bool) -> float:
	var road_start: float = road.position.x if along_x else road.position.z
	var road_end: float = road_start + (road.size.x if along_x else road.size.z)
	var cross_start: float = road.position.z if along_x else road.position.x
	var cross_end: float = cross_start + (road.size.z if along_x else road.size.x)
	var intervals: Array = []
	for block in blocks:
		var b_cross_start: float = block.position.z if along_x else block.position.x
		var b_cross_end: float = b_cross_start + (block.size.z if along_x else block.size.x)
		# Solo cuenta lo que flanquea ESTA calzada: lo que esta cerca de ella
		# en la direccion transversal.
		if b_cross_end < cross_start - 26.0 or b_cross_start > cross_end + 26.0:
			continue
		var start: float = maxf(road_start, block.position.x if along_x else block.position.z)
		var end: float = minf(road_end, (block.position.x + block.size.x) if along_x else (block.position.z + block.size.z))
		if end <= start:
			continue
		intervals.append([start, end])
	if intervals.is_empty():
		return 0.0
	intervals.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	var total: float = 0.0
	var current_start: float = float(intervals[0][0])
	var current_end: float = float(intervals[0][1])
	for i in range(1, intervals.size()):
		var start: float = float(intervals[i][0])
		var end: float = float(intervals[i][1])
		if start > current_end:
			total += current_end - current_start
			current_start = start
			current_end = end
		else:
			current_end = maxf(current_end, end)
	total += current_end - current_start
	return total


func _is_building_mass(family: String) -> bool:
	return family in [
		"CityFacadeBody", "SideStreetBlock", "CornerReturn", "NearNeighbour", "BackBlock",
	]


func _family_of(node_name: String) -> String:
	# La familia es el primer token del nombre. Lo que va detras son indices o
	# la pieza sobre la que se monta -"Shopfront_SideStreetBlock_0_0_00" es un
	# escaparate, no una familia propia-.
	var cut: int = node_name.find("_")
	return node_name if cut <= 0 else node_name.substr(0, cut)


func _intersection(a: AABB, b: AABB) -> AABB:
	var min_v: Vector3 = a.position.max(b.position)
	var max_v: Vector3 = (a.position + a.size).min(b.position + b.size)
	return AABB(min_v, (max_v - min_v).max(Vector3.ZERO))


func _world_aabb(root: Node3D) -> AABB:
	var state: Array = [AABB(), false]
	_accumulate(root, state)
	return state[0]


func _accumulate(node: Node, state: Array) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			var aabb: AABB = mi.global_transform * mi.get_aabb()
			if not bool(state[1]):
				state[0] = aabb
				state[1] = true
			else:
				state[0] = (state[0] as AABB).merge(aabb)
	for child in node.get_children():
		_accumulate(child, state)


func _drop(fp: Node, building: BuildingModel) -> void:
	remove_child(fp)
	fp.free()
	building.free()


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("EXTERIOR CITY VALIDATION PASS")
		get_tree().quit(0)
		return
	push_error("EXTERIOR CITY VALIDATION FAILED")
	for failure in _failures:
		push_error("- " + failure)
	get_tree().quit(1)

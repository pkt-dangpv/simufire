extends Node

## Mide el decorado urbano que se ve por la ventana.
##
## Cuenta las piezas por familia y mide hasta donde llega cada cosa a lo largo
## de la calle, que es lo que decide si la vista "termina en nada": si la
## calzada mide mas que las fachadas que la flanquean, se ve el final.
##
##   <godot> --headless --path . res://tools/probe_exterior_city.tscn

const BuildingModelScript := preload("res://sim/BuildingModel.gd")
const BuildingTemplateScript := preload("res://sim/templates/BuildingTemplate.gd")
const Serializer := preload("res://editor/ScenarioSerializer.gd")
const FirstPersonControllerScript := preload("res://view/fp/FirstPersonController.gd")

const CASES: Array[Dictionary] = [
	{"template": "compact_apartment", "night": false},
	{"template": "simple_house", "night": false},
]

## Familias que interesan, por prefijo del nombre del nodo.
const FAMILIES: Array[String] = [
	"SidewalkNear", "SidewalkFar", "RoadMark", "Road", "CityCurb",
	"CityFacadeBody", "CityFacadePlinth", "CityFacadeCornice",
	"CityWindow", "CityEntrance",
	"CityCar", "CityTree",
	"Skyline", "SkyDome",
	"StreetLamp", "TrafficSign", "Bench", "Bin", "Bollard", "Crossing",
	"BusStop", "Planter", "Balcony", "Awning", "Shopfront", "SideStreet",
	"BackBlock", "CornerReturn", "NearNeighbour",
]


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	await get_tree().process_frame
	for case_data in CASES:
		await _probe(String(case_data["template"]), bool(case_data["night"]))
	get_tree().quit(0)


func _probe(template_name: String, night: bool) -> void:
	var builder = BuildingTemplateScript.new()
	var editor_data: Dictionary = Serializer.normalize_editor_data(builder.create_by_name(template_name))
	var runtime_json: Dictionary = Serializer.to_runtime_json_data(editor_data)
	var parsed: Variant = JSON.parse_string(JSON.stringify(runtime_json))
	if typeof(parsed) != TYPE_DICTIONARY:
		print("%s: no se pudo construir" % template_name)
		return
	var building: BuildingModel = BuildingModelScript.new()
	building.load_template_data(Dictionary(parsed))

	var fp: FirstPersonController = FirstPersonControllerScript.new()
	fp.name = "ProbeExteriorFP"
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
	print("")
	print("=== %s (%s) ===" % [template_name, "noche" if night else "dia"])
	if root == null:
		print("  no hay ExteriorContext")
		remove_child(fp)
		fp.free()
		building.free()
		return

	var counts: Dictionary = {}
	var extents: Dictionary = {}
	var total: int = 0
	var meshes: int = 0
	for child in root.get_children():
		total += 1
		var name: String = String(child.name)
		for family in FAMILIES:
			if not name.begins_with(family):
				continue
			counts[family] = int(counts.get(family, 0)) + 1
			var node := child as Node3D
			if node != null:
				var aabb: AABB = _world_aabb(node)
				if aabb.size != Vector3.ZERO:
					var current: AABB = extents.get(family, aabb)
					extents[family] = current.merge(aabb) if extents.has(family) else aabb
			break
	meshes = _count_meshes(root)

	print("  nodos hijos de ExteriorContext: %d, mallas totales: %d" % [total, meshes])
	for family in FAMILIES:
		if not counts.has(family):
			continue
		var aabb: AABB = extents.get(family, AABB())
		print("    %-18s %3d   extension %.1f x %.1f m, alto %.1f, base y=%.1f" % [
			family, int(counts[family]), aabb.size.x, aabb.size.z, aabb.size.y, aabb.position.y
		])
	for family in FAMILIES:
		if not counts.has(family):
			print("    %-18s   0" % family)

	remove_child(fp)
	fp.free()
	building.free()


func _count_meshes(node: Node) -> int:
	var total: int = 0
	for child in node.get_children():
		if child is MeshInstance3D:
			total += 1
		total += _count_meshes(child)
	return total


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

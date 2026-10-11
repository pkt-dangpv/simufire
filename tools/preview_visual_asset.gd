extends Node3D

## Banco de arte, fuera de las escenas distribuidas: original vs cargador.
const Loader := preload("res://view/3d/furniture/FurnitureAssetLoader.gd")
const Shapes := preload("res://view/3d/furniture/FurnitureShapeBuilder.gd")
const Inspection := preload("res://view/3d/furniture/FurnitureAssetInspection.gd")

@export var archetype: String = "sofa"
@export var requested_footprint_m := Vector2(2.10, 0.90)


func _ready() -> void:
	var report: Dictionary = Inspection.inspect(archetype, requested_footprint_m)
	print("VISUAL_ASSET_REPORT " + JSON.stringify(report))
	var original_root := Node3D.new()
	original_root.name = "OriginalAuthoredScene"
	original_root.position.x = -2.5
	add_child(original_root)
	var packed := ResourceLoader.load(Loader.model_path(archetype)) as PackedScene
	if packed != null:
		original_root.add_child(packed.instantiate())
	var runtime_root := Node3D.new()
	runtime_root.name = "RuntimeLoaderResult"
	runtime_root.position.x = 2.5
	add_child(runtime_root)
	Shapes.rebuild(runtime_root, archetype, requested_footprint_m, 1.0, 0.45)
	_label("ORIGINAL (sin ajuste)", Vector3(-2.5, 2.8, 0.0))
	_label("CARGADOR (sin autoamueblado)", Vector3(2.5, 2.8, 0.0))
	for index in range(-5, 6):
		_box("GridX_%d" % index, Vector3(10.0, 0.004, 0.008),
			Vector3(0.0, -0.01, float(index)), Color(0.4, 0.4, 0.4))
		_box("GridZ_%d" % index, Vector3(0.008, 0.004, 10.0),
			Vector3(float(index), -0.01, 0.0), Color(0.4, 0.4, 0.4))
	_box("PositiveX", Vector3(1.0, 0.015, 0.03), Vector3(0.5, 0.0, 0.0), Color.RED)
	_box("PositiveZ", Vector3(0.03, 0.015, 1.0), Vector3(0.0, 0.0, 0.5), Color.BLUE)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50.0, -25.0, 0.0)
	add_child(light)
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color(0.14, 0.16, 0.19)
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color.WHITE
	settings.ambient_light_energy = 0.6
	environment.environment = settings
	add_child(environment)
	var camera := Camera3D.new()
	camera.position = Vector3(7.0, 5.5, 9.0)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 10.5
	add_child(camera)
	camera.look_at(Vector3(0.0, 0.7, 0.0))
	camera.current = true
	print("VISUAL_ASSET_WORKBENCH_READY")


func _box(node_name: String, size: Vector3, center: Vector3, color: Color) -> void:
	var mesh := MeshInstance3D.new()
	mesh.name = node_name
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position = center
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	mesh.material_override = material
	add_child(mesh)


func _label(text: String, location: Vector3) -> void:
	var label := Label3D.new()
	label.text = text
	label.position = location
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.pixel_size = 0.006
	add_child(label)

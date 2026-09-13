extends SceneTree
## Sonda: una foto del editor tal y como se abre.
##
## El guardarrail mide -que todo tenga tooltip, unidad, foco, icono y sitio-,
## pero "no se ve profesional" es un juicio visual, y para eso hay que mirar.
## Esta sonda abre el editor, deja que se asiente y guarda un PNG.
##
## IMPORTANTE: hay que ejecutarla CON VENTANA REAL, como
## tools/capture_visual_reference.gd. En --headless no hay rasterizado y la
## imagen sale vacia.
##
##   <godot> --path . --resolution 1280x720 --script res://tools/capture_editor_ui.gd -- <salida.png>

const SETTLE_FRAMES: int = 45

var _editor: Node = null
var _frames: int = 0
var _out_path: String = "editor_ui.png"


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		_out_path = args[0]
	var packed := load("res://scenes/ScenarioEditorScene.tscn") as PackedScene
	if packed == null:
		print("[capture_editor_ui] no carga la escena")
		quit(1)
		return
	_editor = packed.instantiate()
	root.add_child(_editor)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < SETTLE_FRAMES:
		return false
	var image: Image = root.get_texture().get_image()
	if image == null:
		print("[capture_editor_ui] sin imagen: ¿se ha lanzado en --headless?")
		quit(1)
		return true
	var error: int = image.save_png(_out_path)
	print("[capture_editor_ui] %s (%dx%d, error=%d)" % [
		_out_path, image.get_width(), image.get_height(), error
	])
	quit(0 if error == OK else 1)
	return true

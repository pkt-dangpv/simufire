extends SceneTree
## U7c: hornea la UI del editor construida en runtime de vuelta a
## ScenarioEditorScene.tscn. Instancia la escena, deja que los _ensure_*
## inyecten los controles que faltan, asigna owner al subarbol de UI
## (solo CanvasLayer: el mundo 2D/3D de preview queda fuera) y empaqueta.
## Tras el horneado los _ensure_* encuentran todo en la escena y no
## vuelven a construir nada.
## Uso: godot --headless --path . --script res://tools/bake_editor_scene.gd

const SCENE_PATH := "res://scenes/ScenarioEditorScene.tscn"
const THEME_PATH := "res://ui/SimuFireTheme.tres"

var _editor: Node = null
var _frames: int = 0


func _initialize() -> void:
	var packed := load(SCENE_PATH) as PackedScene
	if packed == null:
		print("[bake_editor] FAIL: no carga la escena")
		quit(1)
		return
	_editor = packed.instantiate()
	root.add_child(_editor)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 3:
		return false
	_bake()
	return true


func _bake() -> void:
	var canvas := _editor.get_node_or_null("CanvasLayer")
	if canvas == null:
		print("[bake_editor] FAIL: sin CanvasLayer")
		quit(1)
		return

	# El runtime duplica el tema para sus tamanos de fuente; restaurar la
	# referencia al .tres compartido antes de empaquetar.
	var ui := canvas.get_node_or_null("UI") as Control
	if ui != null:
		ui.theme = load(THEME_PATH)

	_own_recursive(canvas, _editor)

	var out := PackedScene.new()
	var err: int = out.pack(_editor)
	if err != OK:
		print("[bake_editor] FAIL: pack error %d" % err)
		quit(1)
		return
	err = ResourceSaver.save(out, SCENE_PATH)
	if err != OK:
		print("[bake_editor] FAIL: save error %d" % err)
		quit(1)
		return
	print("[bake_editor] OK: escena horneada en ", SCENE_PATH)
	quit(0)


func _own_recursive(node: Node, new_owner: Node) -> void:
	if node != new_owner:
		node.owner = new_owner
	for child in node.get_children():
		_own_recursive(child, new_owner)

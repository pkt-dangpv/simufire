extends SceneTree
## Sonda: que se ve de verdad en el editor al arrancar.
##
## La escena guarda muchos controles con visible = false y el codigo los enseña
## segun la pestaña activa. Leer solo el .tscn hace creer que hay mandos
## escondidos que en realidad si aparecen.
##
## Uso: godot --headless --path . --script res://tools/probe_editor_visibility.gd

const WATCH: Array[String] = [
	"HoverHelpRow",
	"HoverHelpRow/HoverHelpCheck",
	"ControlsHelpToggle",
	"FloorSection",
	"ElementList",
	"BtnSave",
	"StatusLabel",
]

var _editor: Node = null
var _frames: int = 0


func _initialize() -> void:
	var packed := load("res://scenes/ScenarioEditorScene.tscn") as PackedScene
	_editor = packed.instantiate()
	root.add_child(_editor)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 5:
		return false
	var ui := _editor.get_node_or_null("CanvasLayer/UI")
	if ui == null:
		print("sin UI")
		quit(1)
		return true
	for base in ["LeftPanel/Scroll/VBox", "RightPanel/Scroll/VBox"]:
		var vbox := ui.get_node_or_null(base)
		print("--- %s: %s" % [base, "existe" if vbox != null else "NO EXISTE"])
	var left := ui.get_node_or_null("LeftPanel/Scroll/VBox")
	if left != null:
		for path in WATCH:
			var node := left.get_node_or_null(path) as Control
			if node == null:
				print("  %-32s no existe" % path)
				continue
			print("  %-32s visible=%s  visible_in_tree=%s" % [
				path, node.visible, node.is_visible_in_tree()
			])
	quit(0)
	return true

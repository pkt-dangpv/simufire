extends SceneTree
## Guardia U7c: comprueba que la UI del editor esta COMPLETA en la escena.
## Instancia ScenarioEditorScene, deja correr _ready (bind + _ensure_*) y
## verifica que ningun Control bajo CanvasLayer carece de owner: un nodo
## sin owner significa que el codigo lo inyecto en runtime (divergencia
## escena/juego que la migracion U7 elimino).
## Uso: godot --headless --path . --script res://tools/validate_editor_scene_complete.gd

var _editor: Node = null
var _frames: int = 0


func _initialize() -> void:
	var packed := load("res://scenes/ScenarioEditorScene.tscn") as PackedScene
	if packed == null:
		print("[validate_editor_scene] FAIL: no carga la escena")
		quit(1)
		return
	_editor = packed.instantiate()
	root.add_child(_editor)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 3:
		return false
	_run_checks()
	return true


func _run_checks() -> void:
	var canvas := _editor.get_node_or_null("CanvasLayer")
	if canvas == null:
		print("[validate_editor_scene] FAIL: sin CanvasLayer")
		quit(1)
		return
	var injected: Array[String] = []
	_collect_unowned(canvas, injected)
	if injected.is_empty():
		print("[validate_editor_scene] PASS: UI del editor 100% en escena")
		quit(0)
		return
	print("[validate_editor_scene] FAIL: %d nodos inyectados por codigo:" % injected.size())
	for path in injected:
		print("  - ", path)
	quit(1)


func _collect_unowned(node: Node, injected: Array[String]) -> void:
	for child in node.get_children():
		if child.owner == null:
			injected.append(String(_editor.get_path_to(child)))
		_collect_unowned(child, injected)

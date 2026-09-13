extends SceneTree
## Sonda: el arbol de la UI del editor, en orden, tal y como queda al arrancar.
##
## Sirve de foto antes/despues cuando se toca el codigo que enlaza la escena: si
## la lista sale identica, el cambio no ha movido nada de sitio. Es la unica
## forma barata de refactorizar _bind_existing_ui sin fiarse de la vista.
##
## Uso: godot --headless --path . --script res://tools/probe_editor_ui_tree.gd -- <salida.txt>

var _editor: Node = null
var _frames: int = 0
var _out_path: String = ""


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		_out_path = args[0]
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
	var out: PackedStringArray = PackedStringArray()
	_dump(ui, "UI", out)
	var text: String = "\n".join(out)
	if _out_path == "":
		print(text)
	else:
		var file := FileAccess.open(_out_path, FileAccess.WRITE)
		if file == null:
			print("no se puede escribir ", _out_path)
			quit(1)
			return true
		file.store_string(text)
		print("[probe_ui_tree] %d nodos -> %s" % [out.size(), _out_path])
	quit(0)
	return true


## Ruta, clase, visibilidad y lo que se lee: basta para notar que algo se ha
## movido, ha cambiado de tipo o ha perdido su texto.
func _dump(node: Node, path: String, out: PackedStringArray) -> void:
	for child in node.get_children():
		var child_path: String = "%s/%s" % [path, child.name]
		var line: String = "%s [%s]" % [child_path, child.get_class()]
		var control := child as Control
		if control != null:
			line += " visible=%s" % control.visible
			if "text" in control:
				line += " text=%s" % String(control.get("text")).replace("\n", "\\n")
			var spin := control as SpinBox
			if spin != null:
				line += " range=%s..%s step=%s suffix=%s" % [spin.min_value, spin.max_value, spin.step, spin.suffix]
			var option := control as OptionButton
			if option != null:
				line += " items=%d" % option.get_item_count()
		out.append(line)
		_dump(child, child_path, out)

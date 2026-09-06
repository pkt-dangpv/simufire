extends SceneTree
## Guardarrail de los mandos del editor: que se entiendan y que se alcancen.
##
## Sale de docs/AUDITORIA_EDITOR_2026-09-06.md, donde el usuario lo dijo asi:
## "hay cosas que no se decir que hacen que no se vea profesional". Medido
## entonces: 62 de 99 controles sin ninguna explicacion y 36 de 36 campos
## numericos sin unidad.
##
## Tres reglas, y las tres son de las que se rompen solas al anadir un control:
##
##  1. **Todo control interactivo dice que hace.** Un boton, una casilla o un
##     desplegable sin tooltip obliga a probarlo para averiguarlo.
##  2. **Todo campo numerico dice en que unidad esta.** El editor mezcla metros,
##     grados, megajulios, kilovatios, segundos y ppm en la misma columna de
##     casillas identicas. Teclear 2,4 donde iban 240 no lo avisa nadie hasta
##     que la simulacion sale rara.
##  3. **Los dos paneles se pueden desplazar.** Sin barra, en cuanto la ventana
##     no es alta lo de abajo se corta y no hay forma de llegar; y lo de abajo
##     del panel izquierdo es guardar, cargar, exportar y la unica linea de
##     estado del editor.
##
## Uso: godot --headless --path . --script res://tools/validate_editor_ui_affordances.gd

## Campos numericos que NO llevan unidad, y por que. Cualquier otro que aparezca
## sin ella es un fallo.
const NUMERIC_WITHOUT_UNIT: Array[String] = [
	# Es un numero de planta, no una medida.
	"ApartmentFloorSpin",
	# Su unidad depende del tipo de detector -kg/m3, grados o ppm- y se la pone
	# el codigo en _sync_detector_threshold_units().
	"DetectorThresholdSpin",
]

var _editor: Node = null
var _frames: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	var packed := load("res://scenes/ScenarioEditorScene.tscn") as PackedScene
	if packed == null:
		print("[validate_editor_ui] FAIL: no carga la escena")
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
		print("[validate_editor_ui] FAIL: sin CanvasLayer")
		quit(1)
		return

	var controls: Array[Control] = []
	_collect_controls(canvas, controls)

	var mute: Array[String] = []
	var unitless: Array[String] = []
	for control in controls:
		if String(control.tooltip_text).strip_edges() == "":
			mute.append(_path_of(control))
		if control is SpinBox and not NUMERIC_WITHOUT_UNIT.has(String(control.name)):
			var spin := control as SpinBox
			if String(spin.suffix).strip_edges() == "" and String(spin.prefix).strip_edges() == "":
				unitless.append(_path_of(control))

	if not mute.is_empty():
		_fail("%d controles no dicen que hacen (sin tooltip):" % mute.size())
		for path in mute:
			_fail("    " + path)
	if not unitless.is_empty():
		_fail("%d campos numericos no dicen su unidad (sin suffix ni prefix):" % unitless.size())
		for path in unitless:
			_fail("    " + path)

	# Los dos paneles laterales tienen que poder desplazarse.
	for panel_name in ["LeftPanel", "RightPanel"]:
		var panel := canvas.get_node_or_null("UI/" + panel_name)
		if panel == null:
			_fail("falta el panel %s" % panel_name)
			continue
		if _find_scroll(panel) == null:
			_fail("%s no tiene ScrollContainer: con la ventana baja, lo de abajo no se alcanza" % panel_name)

	if _failures.is_empty():
		print("[validate_editor_ui] PASS: %d controles con explicacion y unidad, paneles desplazables" % controls.size())
		quit(0)
		return
	print("[validate_editor_ui] FAIL:")
	for failure in _failures:
		print("  - " + failure)
	quit(1)


func _collect_controls(node: Node, out: Array[Control]) -> void:
	for child in node.get_children():
		# Un control invisible sigue siendo alcanzable: el editor esconde y
		# ensena secciones segun la pestana y la seleccion.
		if child is Button or child is OptionButton or child is SpinBox \
				or child is CheckBox or child is LineEdit or child is ItemList:
			out.append(child as Control)
		if child.get_child_count() > 0:
			_collect_controls(child, out)


func _find_scroll(node: Node) -> ScrollContainer:
	for child in node.get_children():
		if child is ScrollContainer:
			return child as ScrollContainer
		var deeper: ScrollContainer = _find_scroll(child)
		if deeper != null:
			return deeper
	return null


func _path_of(control: Control) -> String:
	var parts: Array[String] = [String(control.name)]
	var node: Node = control.get_parent()
	while node != null and node != _editor:
		parts.push_front(String(node.name))
		node = node.get_parent()
	return "/".join(parts)


func _fail(message: String) -> void:
	_failures.append(message)

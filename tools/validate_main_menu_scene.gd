extends SceneTree
## Valida que MainMenu.tscn contiene toda la UI (bind-only, sin fallback de
## codigo), que el script la puebla, y que la portada CABE en la ventana.
##
## La medida de altura esta aqui porque el menu viejo pedia 719 px en una
## ventana de 720 y nadie se enteraba: el hallazgo N-6 de
## docs/ESTADO_Y_PLAN_2026-09-09.md. Ahora los mandos viven detras de
## "Retocar", y esta red impide que vuelvan a la portada de uno en uno.
##
## Uso: godot --headless --path . --script res://tools/validate_main_menu_scene.gd

const TWEAK_ROWS: String = "TweakCenter/TweakPanel/Pad/Rows/"
## Altura de la ventana mas pequena que se soporta. La portada tiene que caber
## en ella sin recortar botones.
const MIN_WINDOW_H: float = 720.0

var _stage: int = 0
var _failures: Array[String] = []
var _resumen_inicial: String = ""


func _initialize() -> void:
	var packed := load("res://scenes/MainMenu.tscn") as PackedScene
	if packed == null:
		print("[validate_main_menu] FAIL: no se pudo cargar MainMenu.tscn")
		quit(1)
		return
	var menu := packed.instantiate()
	menu.name = "MainMenu"
	root.add_child(menu)


func _process(_delta: float) -> bool:
	var menu := root.get_node_or_null("MainMenu")
	match _stage:
		0:
			_stage = 1
			return false
		1:
			_run_checks()
			# Abrir los ajustes como lo haria el raton.
			var btn := _node(menu, "Center/VBox/ActionsRow/BtnTweak") as Button
			if btn != null:
				btn.emit_signal("pressed")
			_stage = 2
			return false
		2:
			_check_tweak_open(menu)
			var close := _node(menu, TWEAK_ROWS + "BtnTweakClose") as Button
			if close != null:
				close.emit_signal("pressed")
			_stage = 3
			return false
		_:
			_check_tweak_closed(menu)

	if _failures.is_empty():
		print("[validate_main_menu] PASS")
		quit(0)
	else:
		for failure in _failures:
			print("[validate_main_menu] FAIL: ", failure)
		quit(1)
	return true


func _run_checks() -> void:
	var menu := root.get_node_or_null("MainMenu")
	if menu == null:
		_failures.append("MainMenu no instanciado")
		return

	# --- La portada: escenario, resumen y cuatro botones ---
	for path in ["Center/VBox/Logo", "Center/VBox/Subtitle", "Center/VBox/ScenarioLabel",
			"Center/VBox/ScenarioScroll/ScenarioList", "Center/VBox/Summary",
			"Center/VBox/ActionsRow/BtnNewSim", "Center/VBox/ActionsRow/BtnTweak",
			"Center/VBox/SecondaryRow/BtnEditor", "Center/VBox/SecondaryRow/BtnQuit",
			"TweakDim", "TweakCenter"]:
		_expect_node(menu, path)

	# --- El panel de ajustes: los siete mandos, ya no en la portada ---
	for row in ["BuildingTypeRow", "ApartmentFloorRow", "HvacRow", "LightingRow",
			"InteriorLightsRow", "GlassBreakRow", "VisibilityRow"]:
		_expect_node(menu, TWEAK_ROWS + row)
	_expect_node(menu, TWEAK_ROWS + "BtnTweakClose")
	if not _failures.is_empty():
		return

	# Un mando en la portada es exactamente lo que N-6 vino a arreglar.
	var vbox := _node(menu, "Center/VBox")
	for child in vbox.get_children():
		if child is OptionButton or child is SpinBox:
			_failures.append("%s es un mando y esta en la portada: va en el panel de ajustes" % child.name)

	# --- Una ficha por escenario, con nombre y descripcion, y una elegida ---
	var lista := _node(menu, "Center/VBox/ScenarioScroll/ScenarioList")
	var presets: Array = load("res://sim/templates/BuildingTemplate.gd").new().get_preset_definitions()
	if lista.get_child_count() != presets.size():
		_failures.append("la lista tiene %d fichas y hay %d escenarios" % [lista.get_child_count(), presets.size()])
	var elegidas: int = 0
	for child in lista.get_children():
		var card := child as Button
		if card == null:
			_failures.append("la lista tiene un hijo que no es ficha: %s" % child.name)
			continue
		if not card.toggle_mode:
			_failures.append("%s no es un interruptor: la seleccion no se veria" % card.name)
		if card.button_pressed:
			elegidas += 1
		var nombre := card.get_node_or_null("Box/Name") as Label
		var desc := card.get_node_or_null("Box/Desc") as Label
		if nombre == null or nombre.text.strip_edges().is_empty():
			_failures.append("%s sin nombre" % card.name)
		if desc == null or desc.text.strip_edges().is_empty():
			_failures.append("%s sin descripcion: la ficha no dice de que va el escenario" % card.name)
	if elegidas != 1:
		_failures.append("hay %d fichas elegidas y tiene que haber exactamente 1" % elegidas)

	# --- Los desplegables, poblados ---
	_expect_items("BuildingTypeRow/Option", 2)
	_expect_items("HvacRow/Option", 3)
	_expect_items("LightingRow/Option", 2)
	_expect_items("InteriorLightsRow/Option", 2)
	_expect_items("GlassBreakRow/Option", 3)
	_expect_items("VisibilityRow/Option", 2)

	# --- El resumen: esconder los ajustes solo vale si se ven desde fuera ---
	var resumen := _node(menu, "Center/VBox/Summary") as Label
	_resumen_inicial = resumen.text
	if _resumen_inicial.strip_edges().is_empty():
		_failures.append("el resumen esta vacio: 'Retocar' seria una caja negra")

	# --- La planta del piso solo cuando el edificio es un piso ---
	var floor_row := _node(menu, TWEAK_ROWS + "ApartmentFloorRow") as Control
	var building := _node(menu, TWEAK_ROWS + "BuildingTypeRow/Option") as OptionButton
	if floor_row != null and building != null and floor_row.visible != (building.selected == 1):
		_failures.append("ApartmentFloorRow.visible=%s no coincide con tipo edificio seleccionado" % floor_row.visible)

	# --- N-6: la portada cabe en la ventana mas pequena ---
	var pedido: float = vbox.get_combined_minimum_size().y
	if pedido > MIN_WINDOW_H:
		_failures.append("la portada pide %.0f px y la ventana minima es de %.0f" % [pedido, MIN_WINDOW_H])

	if menu.theme == null:
		_failures.append("MainMenu sin theme asignado (debe ser ui/SimuFireTheme.tres)")


## Con el panel abierto: se ve, tapa la portada y el foco esta dentro.
func _check_tweak_open(menu: Node) -> void:
	var dim := _node(menu, "TweakDim") as Control
	var panel := _node(menu, "TweakCenter") as Control
	if dim == null or panel == null:
		return
	if not panel.visible:
		_failures.append("'Retocar' no abre el panel de ajustes")
	if not dim.visible:
		_failures.append("el panel se abre sin velo: la portada se leeria por debajo")
	var caja := _node(menu, "TweakCenter/TweakPanel") as Control
	if panel.visible and caja != null and caja.get_combined_minimum_size().y > MIN_WINDOW_H:
		_failures.append("el panel de ajustes tampoco cabe en la ventana minima")


## Y al cerrarlo vuelve a estar escondido, que es la mitad de la funcion.
func _check_tweak_closed(menu: Node) -> void:
	var dim := _node(menu, "TweakDim") as Control
	var panel := _node(menu, "TweakCenter") as Control
	if dim == null or panel == null:
		return
	if panel.visible or dim.visible:
		_failures.append("'Listo' no cierra el panel de ajustes")


func _node(menu: Node, path: String) -> Node:
	if menu == null:
		return null
	return menu.get_node_or_null(path)


func _expect_node(menu: Node, path: String) -> void:
	if menu.get_node_or_null(path) == null:
		_failures.append("falta nodo %s en la escena" % path)


func _expect_items(path: String, esperados: int) -> void:
	var menu := root.get_node_or_null("MainMenu")
	var opt := menu.get_node_or_null(TWEAK_ROWS + path) as OptionButton
	if opt == null or opt.item_count != esperados:
		_failures.append("%s debe tener %d items (tiene %d)" % [path, esperados, (opt.item_count if opt != null else -1)])

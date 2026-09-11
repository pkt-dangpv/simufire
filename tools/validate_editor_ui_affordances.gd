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
##  4. **Se llega a los controles con el teclado.** focus_mode = 0 apaga el
##     tabulador, y el tema ya trae estilo de foco: apagarlo no evitaba ningun
##     recuadro feo, solo quitaba la navegacion.
##  5. **Cada herramienta dice su tecla y lleva su nombre entero.** Un atajo que
##     no se anuncia no existe, y una etiqueta cortada se lee como prototipo.
##  6. **El texto que lee el usuario lleva tildes.** Escribir sin ellas en el
##     codigo es una convencion razonable; en la pantalla es una falta.
##  7. **Las teclas anunciadas cambian de herramienta de verdad.** Anunciar un
##     atajo que no responde es peor que no tenerlo.
##  9. **Cada herramienta lleva icono, le cabe el nombre entero y la barra no
##     pisa los paneles.** Una barra de texto abreviado en mayusculas se lee
##     como prototipo; una etiqueta recortada por el icono, tambien; y una barra
##     que crece al añadir una herramienta acaba tapando el panel de al lado.
##  8. **Duplicar una habitacion se lleva lo que hay dentro, y una sola vez.**
##     Copiar objetos, detectores y victimas es el motivo de la funcion; clonar
##     ademas el foco de ignicion dejaria dos focos y un escenario que se
##     contradice.
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

## Palabras sin tilde que no admiten discusion: no existe ninguna frase donde
## "habitacion" o "victima" sean correctas. Las ambiguas -"esta"/"esta",
## "mas"/"mas", "solo"/"solo"- se quedan fuera a proposito: aqui solo caben las
## que siempre son falta, para que el guardarrail no de falsos positivos.
const MISSPELLED: Array[String] = [
	"habitacion", "victima", "victimas", "simulacion", "seleccion", "ignicion",
	"edicion", "aparicion", "posicion", "direccion", "opcion", "geometria",
	"tamano", "pequeno", "pequena", "boton", "tambien", "maximo", "minimo",
	"maxima", "minima", "ultimo", "aqui", "anadir", "angulo", "numero",
	"deteccion", "informacion", "configuracion", "presion", "energia",
	"combustion", "oxigeno", "estan", "despues", "segun", "duracion",
	"clasico", "basico", "practico", "grafica", "graficas", "codigo",
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

	# 4. Se puede llegar a los controles con el teclado.
	#
	# Estaban los 57 con focus_mode = 0, que apaga el tabulador. No era para
	# evitar un recuadro feo: el tema ya trae estilo de foco para Button,
	# LineEdit, OptionButton y SpinBox.
	var unfocusable: Array[String] = []
	for control in controls:
		if control.focus_mode == Control.FOCUS_NONE:
			unfocusable.append(_path_of(control))
	if not unfocusable.is_empty():
		_fail("%d controles no se alcanzan con el teclado (focus_mode = 0):" % unfocusable.size())
		for path in unfocusable:
			_fail("    " + path)

	# 5. Cada herramienta dice su tecla y lleva su nombre entero.
	#
	# Un atajo que no se anuncia en ningun sitio es un atajo que no existe, y
	# una etiqueta cortada -"DETECT.", "VICT."- se lee como prototipo.
	var toolbar := canvas.get_node_or_null("UI/TopBar/HBox")
	if toolbar == null:
		_fail("falta la barra de herramientas")
	else:
		for child in toolbar.get_children():
			var button := child as Button
			if button == null:
				continue
			if not String(button.tooltip_text).contains("[tecla "):
				_fail("la herramienta %s no dice su tecla" % button.name)
			if String(button.text).ends_with("."):
				_fail("la herramienta %s lleva el nombre cortado: %s" % [button.name, button.text])

			# 9. Icono, y sitio para el icono.
			#
			# Un dibujo nuevo al lado de una etiqueta entera es justo la
			# combinacion que desborda un boton de ancho fijo, y lo que se
			# recorta entonces es el nombre.
			if button.icon == null:
				_fail("la herramienta %s no lleva icono" % button.name)
			var needed: float = button.get_combined_minimum_size().x
			if needed > button.size.x + 0.5:
				_fail("a %s no le cabe el contenido: necesita %d px y tiene %d" % [
					button.name, int(ceil(needed)), int(button.size.x)
				])

	# 6. El texto que lee el usuario lleva tildes.
	#
	# La guia rapida del editor, que es el texto mas largo que se lee dentro de
	# la aplicacion, iba sin ellas -"Seleccion", "Victima", "pequeno"- y convivia
	# con etiquetas que si las llevaban.
	var misspelled: Array[String] = []
	_collect_misspellings(canvas, misspelled)
	if not misspelled.is_empty():
		_fail("%d textos de pantalla sin tilde:" % misspelled.size())
		for hit in misspelled:
			_fail("    " + hit)

	# 7. Las teclas anunciadas cambian de herramienta de verdad.
	#
	# La regla 5 solo mira lo que dice el tooltip. Esta pulsa la tecla.
	for keycode in _editor.TOOL_SHORTCUTS:
		var expected: int = int(_editor.TOOL_SHORTCUTS[keycode])
		var event := InputEventKey.new()
		event.keycode = int(keycode)
		event.pressed = true
		_editor._unhandled_input(event)
		if int(_editor.current_tool) != expected:
			_fail("la tecla %s no cambia de herramienta (esperada %d, quedo %d)" % [
				OS.get_keycode_string(int(keycode)), expected, int(_editor.current_tool)
			])

	# 8. Duplicar una habitacion se lleva lo de dentro, y no clona el foco.
	_check_duplicate_room()

	# 9 (segunda mitad). La barra no se solapa con los paneles laterales.
	#
	# La barra esta centrada y crece sola con su contenido: cada herramienta
	# nueva, o cada etiqueta mas larga, la empuja hacia los lados hasta meterse
	# debajo del panel, donde los botones dejan de poder pulsarse.
	# Ni la barra ni el panel del 3D en vivo pueden meterse debajo de los paneles
	# laterales: lo que queda tapado no se puede pulsar.
	for floating_name in ["TopBar", "Preview3DPanel"]:
		var floating := canvas.get_node_or_null("UI/" + floating_name) as Control
		if floating == null:
			continue
		var floating_rect: Rect2 = floating.get_global_rect()
		for panel_name in ["LeftPanel", "RightPanel"]:
			var side := canvas.get_node_or_null("UI/" + panel_name) as Control
			if side == null:
				continue
			var side_rect: Rect2 = side.get_global_rect()
			if floating_rect.intersects(side_rect):
				_fail("%s (x %d..%d) se mete debajo de %s (x %d..%d)" % [
					floating_name,
					int(floating_rect.position.x), int(floating_rect.end.x),
					panel_name,
					int(side_rect.position.x), int(side_rect.end.x)
				])

	# Los dos paneles laterales tienen que poder desplazarse.
	for panel_name in ["LeftPanel", "RightPanel"]:
		var panel := canvas.get_node_or_null("UI/" + panel_name)
		if panel == null:
			_fail("falta el panel %s" % panel_name)
			continue
		if _find_scroll(panel) == null:
			_fail("%s no tiene ScrollContainer: con la ventana baja, lo de abajo no se alcanza" % panel_name)

	if _failures.is_empty():
		print("[validate_editor_ui] PASS: %d controles con explicacion, unidad, foco y tildes; paneles desplazables; %d teclas de herramienta responden; duplicar se lleva lo de dentro; 14 herramientas con icono" % [controls.size(), _editor.TOOL_SHORTCUTS.size()])
		quit(0)
		return
	print("[validate_editor_ui] FAIL:")
	for failure in _failures:
		print("  - " + failure)
	quit(1)


## Monta una sala con un objeto encendido, un detector y una victima, la duplica
## y mira que ha salido. Es la unica regla que toca los datos del editor, y lo
## hace sobre la instancia headless: no se guarda nada.
func _check_duplicate_room() -> void:
	_editor.adopt_scenario_data({
		"floors": [{"name": "PB", "level_m": 0.0}],
		"exterior_walls": [],
		"room_rect_m": {"7": {"x": 0.0, "y": 0.0, "w": 4.0, "h": 3.0}},
		"rooms_data": [{
			"id": 7,
			"name": "Dormitorio",
			"kind": "generic",
			"rotation_deg": 0.0,
			"height_m": 2.7,
			"floor_level_z_m": 0.0,
			"fuel_objects": [{
				"id": "obj_001",
				"room_id": 7,
				"name": "cama",
				"position_m": {"x": 0.5, "y": 0.5},
				"size_m": {"x": 1.4, "y": 2.0},
				"is_primary_ignition_source": true
			}]
		}],
		"openings_data": [],
		"detectors": [{"id": "det_001", "room_id": 7, "type": "smoke", "threshold": 0.025, "x_m": 1.0, "y_m": 1.0}],
		"victims": [{"id": "vic_001", "room_id": 7, "name": "Víctima 1", "x_m": 2.0, "y_m": 1.0, "height_m": 0.9}],
		"player_start": {},
		"ignition_room_id": 7
	}, 0)
	_editor._select_room(7)
	_editor._duplicate_selection()

	var rooms: Array = _editor.editor_data.get("rooms_data", [])
	if rooms.size() != 2:
		_fail("duplicar una habitacion no crea la copia (salas: %d)" % rooms.size())
		return
	var copy: Dictionary = rooms[1]
	var copy_id: int = int(copy.get("id", -1))
	if copy_id == 7:
		_fail("la copia de la habitacion se queda con el id del original")
	if String(copy.get("name", "")) != "Dormitorio (copia)":
		_fail("la copia no se renombra: %s" % copy.get("name", ""))
	if not _editor.editor_data.get("room_rect_m", {}).has(str(copy_id)):
		_fail("la copia no tiene entrada en room_rect_m: quedaria sin geometria")

	var copied_objects: Array = copy.get("fuel_objects", [])
	if copied_objects.size() != 1:
		_fail("la copia no se lleva los objetos (%d)" % copied_objects.size())
	else:
		var copied_object: Dictionary = copied_objects[0]
		if String(copied_object.get("id", "")) == "obj_001":
			_fail("el objeto copiado repite el id del original")
		if bool(copied_object.get("is_primary_ignition_source", false)):
			_fail("la copia clona el foco de ignicion: quedarian dos focos")

	var dets: Array = _editor.editor_data.get("detectors", [])
	var vics: Array = _editor.editor_data.get("victims", [])
	if dets.size() != 2 or int(Dictionary(dets[1]).get("room_id", -1)) != copy_id:
		_fail("el detector no acompaña a la copia")
	elif String(Dictionary(dets[1]).get("id", "")) == "det_001":
		_fail("el detector copiado repite el id del original")
	if vics.size() != 2 or int(Dictionary(vics[1]).get("room_id", -1)) != copy_id:
		_fail("la victima no acompaña a la copia")

	# Y lo simetrico: borrar la sala se lleva lo que hay dentro, que antes se
	# quedaba apuntando a un room_id inexistente.
	_editor._delete_room(copy_id)
	for list_key in ["detectors", "victims"]:
		for item in Array(_editor.editor_data.get(list_key, [])):
			if typeof(item) == TYPE_DICTIONARY and int(Dictionary(item).get("room_id", -1)) == copy_id:
				_fail("borrar la habitacion deja %s huerfanos apuntando a la sala %d" % [list_key, copy_id])
				break

	# Deshacer tiene que poder volver: duplicar es una accion como cualquier otra.
	_editor._undo_last_action()
	_editor._undo_last_action()
	if Array(_editor.editor_data.get("rooms_data", [])).size() != 1:
		_fail("deshacer no revierte el duplicado")


func _collect_controls(node: Node, out: Array[Control]) -> void:
	for child in node.get_children():
		# Un control invisible sigue siendo alcanzable: el editor esconde y
		# ensena secciones segun la pestana y la seleccion.
		if child is Button or child is OptionButton or child is SpinBox \
				or child is CheckBox or child is LineEdit or child is ItemList:
			out.append(child as Control)
		if child.get_child_count() > 0:
			_collect_controls(child, out)


## Recorre todo lo que se lee en pantalla -texto y tooltip de cualquier nodo que
## los tenga- buscando las palabras de MISSPELLED.
func _collect_misspellings(node: Node, out: Array[String]) -> void:
	for child in node.get_children():
		var control := child as Control
		if control != null:
			var pieces: Array[String] = [String(control.tooltip_text)]
			if "text" in control:
				pieces.append(String(control.get("text")))
			for piece in pieces:
				for word in MISSPELLED:
					if _contains_word(piece.to_lower(), word):
						out.append("%s: \"%s\" -> %s" % [_path_of(control), word, piece.substr(0, 60)])
		if child.get_child_count() > 0:
			_collect_misspellings(child, out)


## Palabra entera, no trozo: "area" no puede saltar dentro de "areas" ni
## "estan" dentro de "estanteria".
func _contains_word(haystack: String, word: String) -> bool:
	var from: int = 0
	while true:
		var at: int = haystack.find(word, from)
		if at < 0:
			return false
		var before_ok: bool = at == 0 or not _is_letter(haystack[at - 1])
		var after: int = at + word.length()
		var after_ok: bool = after >= haystack.length() or not _is_letter(haystack[after])
		if before_ok and after_ok:
			return true
		from = at + 1
	return false


func _is_letter(c: String) -> bool:
	return c.to_lower() != c.to_upper() or c == "ñ"


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

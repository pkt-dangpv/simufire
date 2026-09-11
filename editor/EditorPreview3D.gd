extends RefCounted
class_name EditorPreview3D

## El panel del «3D en vivo» del editor, sacado del monolito (D-1).
##
## `ScenarioEditor.gd` pasaba de 6871 lineas el 6 de septiembre a 9013 el 10:
## no son funciones largas, es UNA clase con 443 funciones. Este es el primero
## de los dos bloques que la auditoria del editor senalo como candidatos a
## modulo propio, y es el mas separable: catorce funciones y catorce variables
## que solo se hablan entre si.
##
## Lo que sigue viviendo en el editor es lo que NO es del panel: el mundo 3D
## compartido, el modelo de simulacion y cuando hay que rehacerlo. Este modulo
## se lo pide por `_editor`, y esa dependencia es a proposito y en un solo
## sentido: el panel sabe del editor, el editor no sabe de las tripas del panel.
##
## El truco que hace que el mismo mundo 3D se vea dentro del editor 2D: el
## `SubViewport` comparte el `World3D` de la ventana y trae SU PROPIA camara,
## asi que la del visor puede quedarse apagada. Con el visor visible pero sin
## camara activa, el mundo no se cuela detras del plano y si aparece aqui.

## Cada cuanto puede seguir al raton mientras se arrastra. 60 Hz son 16,7 ms,
## asi que 30 veces por segundo es lo que cabe sin que el plano se note pesado.
## Al soltar se rehace entero, ya con los muebles.
const FOLLOW_MS: int = 33
## Lo mas pequeno que se deja el panel: por debajo no se ve nada.
const MIN_SIZE_PX := Vector2(240.0, 180.0)
## Espera antes de rehacer el 3D tras el ultimo cambio. Cada cambio reinicia la
## cuenta, asi que arrastrar una sala entera cuesta UNA reconstruccion.
const REBUILD_DELAY_S: float = 0.25

## Angulo, inclinacion y distancia de partida de la camara.
const START_YAW: float = -0.7
const START_PITCH: float = -0.52
const START_DISTANCE_M: float = 16.0

var enabled: bool = false
var panel: PanelContainer = null
var viewport: SubViewport = null
var camera: Camera3D = null

var _editor: Node = null
var _toggle: Button = null
var _rebuild_delay_s: float = 0.0
var _last_follow_msec: int = 0

# Mover y agrandar el panel.
var _panel_drag: String = ""
var _panel_drag_mouse: Vector2 = Vector2.ZERO
var _panel_drag_rect := Rect2()

# La camara, en coordenadas esfericas alrededor del edificio.
var _yaw: float = START_YAW
var _pitch: float = START_PITCH
var _distance_m: float = START_DISTANCE_M
var _pivot: Vector3 = Vector3.ZERO
var _orbiting: bool = false
var _last_mouse: Vector2 = Vector2.ZERO


## Enlaza el panel, que vive en `ScenarioEditorScene.tscn`.
func setup(editor: Node) -> void:
	_editor = editor
	panel = _ui("Preview3DPanel") as PanelContainer
	viewport = _ui("Preview3DPanel/VBox/Preview3DViewportContainer/Preview3DViewport") as SubViewport
	camera = _ui("Preview3DPanel/VBox/Preview3DViewportContainer/Preview3DViewport/Preview3DCamera") as Camera3D
	_toggle = _editor.call("_get_left_node", "Preview3DToggle") as Button
	if _toggle != null:
		_toggle.toggle_mode = true
		if not _toggle.toggled.is_connected(_on_toggled):
			_toggle.toggled.connect(_on_toggled)

	# La barra del titulo mueve el panel y la esquina lo agranda. Era de tamano
	# y sitio fijos: servia para vigilar de reojo, no para trabajar mirandolo.
	var header := _ui("Preview3DPanel/VBox/HeaderRow") as Control
	if header != null:
		header.mouse_filter = Control.MOUSE_FILTER_STOP
		header.mouse_default_cursor_shape = Control.CURSOR_MOVE
		header.tooltip_text = "Arrastra esta barra para llevarte la vista 3D a otra esquina."
		if not header.gui_input.is_connected(_on_header_gui_input):
			header.gui_input.connect(_on_header_gui_input)

	# El visor escucha el raton: arrastrar gira, la rueda acerca. No tenia
	# ningun manejador -solo la cabecera y el agarre-, asi que la miniatura era
	# una foto fija desde un angulo que nadie habia elegido.
	var viewport_box := _ui("Preview3DPanel/VBox/Preview3DViewportContainer") as Control
	if viewport_box != null:
		viewport_box.mouse_filter = Control.MOUSE_FILTER_STOP
		viewport_box.tooltip_text = "Arrastra para girar alrededor del edificio y usa la rueda para acercarte. «Encuadrar» vuelve a la vista de conjunto."
		if not viewport_box.gui_input.is_connected(_on_viewport_gui_input):
			viewport_box.gui_input.connect(_on_viewport_gui_input)

	var grip := _ui("Preview3DPanel/VBox/Preview3DFooter/Preview3DResizeGrip") as Button
	if grip != null and not grip.gui_input.is_connected(_on_grip_gui_input):
		grip.gui_input.connect(_on_grip_gui_input)
	_editor.call("_connect_button", _ui("Preview3DPanel/VBox/HeaderRow/BtnPreview3DFrame"), frame)
	_editor.call("_connect_button", _ui("Preview3DPanel/VBox/HeaderRow/BtnPreview3DClose"), close)
	set_enabled(false)


func _ui(path: String) -> Node:
	return _editor.call("_get_ui_node", path)


# ── Encender, apagar y rehacer ─────────────────────────────────────────────

func _on_toggled(pressed: bool) -> void:
	set_enabled(pressed)


func close() -> void:
	set_enabled(false)


func set_enabled(value: bool) -> void:
	enabled = value
	if panel != null:
		panel.visible = value
	if _toggle != null and _toggle.button_pressed != value:
		_toggle.set_pressed_no_signal(value)
	if not value:
		# Se devuelve el mundo al estado que le toca por el modo de vista.
		_editor.call("_restore_world_3d_for_view_mode")
		return
	_editor.call("_ensure_editor_3d_nodes")
	if viewport != null:
		viewport.world_3d = _editor.get_viewport().world_3d
	_editor.call("_show_world_3d_for_preview")
	_editor.call("_sync_editor_runtime_views", false)
	frame()
	_editor.call("_set_status", _editor.tr("3D en vivo encendido: se rehace solo al soltar cada cambio."))


## Rehace el panel cuando se deja de mover.
func refresh(delta: float) -> void:
	if not enabled or not bool(_editor.get("_editor_runtime_dirty")):
		return
	_rebuild_delay_s -= delta
	if _rebuild_delay_s > 0.0:
		return
	_editor.call("_sync_editor_runtime_views", false)
	# Reconstruir NO reencuadra: si lo hiciera, cada cambio en el plano
	# devolveria la camara al angulo de fabrica y no habria forma de mirar el
	# edificio desde donde uno quiere.
	_apply_camera()


func schedule_rebuild() -> void:
	_rebuild_delay_s = REBUILD_DELAY_S


## El 3D sigue al raton mientras se arrastra, por el camino barato que toque.
##
## Moviendo un mueble no hacen falta paredes nuevas: basta recargar el modelo y
## dejar que el visor recoloque las piezas que ya existen (11 ms). Moviendo
## paredes hay que rehacer la caja, y desde que los muebles sobreviven a la
## reconstruccion eso cuesta 13 ms en vez de 47: cabe en un fotograma CON los
## muebles puestos.
##
## La camara no se reencuadra aqui a proposito: saltaria en cada paso.
func follow_drag(dragging_object: bool) -> void:
	if not enabled or _editor.get("_editor_visualizer_3d") == null:
		return
	var now_msec: int = Time.get_ticks_msec()
	if now_msec - _last_follow_msec < FOLLOW_MS:
		return
	_last_follow_msec = now_msec
	if dragging_object:
		_editor.call("_preview_3d_restate")
		return
	_editor.call("_sync_editor_runtime_views", false)
	_editor.call("_mark_editor_runtime_dirty")


# ── La camara ──────────────────────────────────────────────────────────────

## Vista de conjunto: la que hace que quepa el edificio entero.
##
## Se CALCULA desde la caja de las salas de la planta. Antes se le copiaba la
## matriz a la camara del visor 3D grande, que en modo 2D esta siempre en el
## mismo sitio: el boton copiaba lo mismo una y otra vez, y por eso no parecia
## hacer nada. Medido, a partir de 16 salas se salian 7 de las 8 esquinas del
## edificio (D-4).
func frame() -> void:
	if camera == null:
		return
	var bounds: Rect2 = _editor.call("_current_floor_bounds_m")
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		_pivot = Vector3.ZERO
		_distance_m = START_DISTANCE_M
	else:
		# El visor comparte mundo con el visor 3D grande, que centra la planta
		# en el origen: hay que mirar al centro de la caja en ESE mundo.
		var center: Vector2 = bounds.get_center()
		var origin: Vector2 = -(bounds.position + bounds.size * 0.5)
		_pivot = Vector3(center.x + origin.x, 1.3, center.y + origin.y)
		var radius: float = maxf(2.0, Vector2(bounds.size.x, bounds.size.y).length() * 0.5)
		_distance_m = radius / tan(deg_to_rad(camera.fov * 0.5)) * 1.25
	_yaw = START_YAW
	_pitch = START_PITCH
	_apply_camera()


## Coloca la camara desde el giro, la inclinacion y la distancia.
func _apply_camera() -> void:
	if camera == null:
		return
	_pitch = clampf(_pitch, -1.45, -0.05)
	_distance_m = clampf(_distance_m, 1.5, 220.0)
	var horizontal: float = cos(_pitch) * _distance_m
	var offset := Vector3(
		sin(_yaw) * horizontal,
		-sin(_pitch) * _distance_m,
		cos(_yaw) * horizontal
	)
	camera.position = _pivot + offset
	camera.look_at(_pivot, Vector3.UP)
	camera.current = true


## Girar arrastrando, acercarse con la rueda. La rueda no se cuela al zoom del
## plano porque el visor es un Control y se la queda el.
func _on_viewport_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_WHEEL_UP and button.pressed:
			_distance_m *= 0.88
			_apply_camera()
			return
		if button.button_index == MOUSE_BUTTON_WHEEL_DOWN and button.pressed:
			_distance_m /= 0.88
			_apply_camera()
			return
		if button.button_index == MOUSE_BUTTON_LEFT or button.button_index == MOUSE_BUTTON_MIDDLE:
			_orbiting = button.pressed
			_last_mouse = button.position
			return
	if event is InputEventMouseMotion and _orbiting:
		var motion := event as InputEventMouseMotion
		var delta: Vector2 = motion.position - _last_mouse
		_last_mouse = motion.position
		_yaw -= delta.x * 0.008
		_pitch -= delta.y * 0.006
		_apply_camera()


# ── Mover y agrandar el panel ──────────────────────────────────────────────

func _on_header_gui_input(event: InputEvent) -> void:
	_begin_panel_drag(event, "move")


func _on_grip_gui_input(event: InputEvent) -> void:
	_begin_panel_drag(event, "resize")


func _begin_panel_drag(event: InputEvent, mode: String) -> void:
	if panel == null or not (event is InputEventMouseButton):
		return
	var mouse_event: InputEventMouseButton = event
	if mouse_event.button_index != MOUSE_BUTTON_LEFT or not mouse_event.pressed:
		return
	_panel_drag = mode
	_panel_drag_mouse = _editor.get_viewport().get_mouse_position()
	_panel_drag_rect = Rect2(panel.position, panel.size)


## Cierto si el evento era para mover o agrandar el panel.
func handle_panel_drag(event: InputEvent) -> bool:
	if _panel_drag == "" or panel == null:
		return false
	if event is InputEventMouseMotion:
		var delta: Vector2 = (event as InputEventMouseMotion).position - _panel_drag_mouse
		if _panel_drag == "move":
			place(_panel_drag_rect.position + delta, _panel_drag_rect.size)
		else:
			place(_panel_drag_rect.position, _panel_drag_rect.size + delta)
		return true
	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and not mouse_event.pressed:
			_panel_drag = ""
			return true
	return false


## Deja el panel donde se pide, sin que se salga de la pantalla ni se quede tan
## pequeno que no se vea nada. Se ancla arriba-izquierda: con el anclaje de
## esquina que traia, mover y redimensionar peleaban entre si.
func place(position: Vector2, size: Vector2) -> void:
	if panel == null:
		return
	var screen: Vector2 = _editor.get_viewport().get_visible_rect().size
	var clamped_size := Vector2(
		clampf(size.x, MIN_SIZE_PX.x, screen.x),
		clampf(size.y, MIN_SIZE_PX.y, screen.y))
	var clamped_position := Vector2(
		clampf(position.x, 0.0, maxf(0.0, screen.x - clamped_size.x)),
		clampf(position.y, 0.0, maxf(0.0, screen.y - clamped_size.y)))
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT, false)
	panel.offset_left = clamped_position.x
	panel.offset_top = clamped_position.y
	panel.offset_right = clamped_position.x + clamped_size.x
	panel.offset_bottom = clamped_position.y + clamped_size.y
	panel.size = clamped_size

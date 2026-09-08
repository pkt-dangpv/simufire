extends RefCounted
## El panel de propiedades del editor: todo el lado derecho de la pantalla.
##
## Solo sabe de mandos. No conoce `editor_data`, ni que hay seleccionado, ni el
## deshacer: recibe en un diccionario lo que hay que enseñar (`show`) y devuelve
## en otro lo que el usuario ha tecleado (`read_*`). La geometria, las unidades
## y las reglas se quedan en ScenarioEditor, que es quien puede calcularlas.
##
## Primer modulo de E-12 (docs/AUDITORIA_EDITOR_2026-09-06.md): el fichero del
## editor pasaba de 7500 lineas y este panel eran 48 variables de nodo y una
## funcion de 185 lineas repartiendolas.
##
## Los nodos vienen de ScenarioEditorScene.tscn. Si falta alguno se dice y se
## sigue: fabricarlo en silencio es lo que produce la divergencia entre lo que
## se ve en Godot y lo que se ve al jugar.

## Lo que el panel PIDE. No lo hace: lo pide, y el editor decide, porque es quien
## tiene los datos, el deshacer y la linea de estado.
const ACTION_ROOM_APPLY: String = "room_apply"
const ACTION_ROOM_DELETE: String = "room_delete"
const ACTION_OBJECT_APPLY: String = "object_apply"
const ACTION_OPENING_APPLY: String = "opening_apply"
const ACTION_DETECTOR_APPLY: String = "detector_apply"
const ACTION_VICTIM_APPLY: String = "victim_apply"
## Borrar objeto, apertura, detector, victima o muro: el editor ya sabe cual esta
## seleccionado, asi que los cinco botones piden lo mismo.
const ACTION_DELETE_SELECTED: String = "delete_selected"

signal action_requested(action: String)

# ── Habitacion ──────────────────────────────────────────────────────────────
var _name_edit: LineEdit
var _kind_edit: LineEdit
var _room_x_spin: SpinBox
var _room_y_spin: SpinBox
var _room_width_spin: SpinBox
var _room_depth_spin: SpinBox
var _room_rotation_spin: SpinBox
var _height_spin: SpinBox
var _fuel_spin: SpinBox
var _hrr_spin: SpinBox
var _room_apply_button: Button
var _room_delete_button: Button
var _stair_turn_option: OptionButton
var _stair_walls_check: CheckBox
var _stair_railings_check: CheckBox
var _stair_angle_label: Label

# ── Objeto ──────────────────────────────────────────────────────────────────
var _obj_props_container: Control
var _obj_name_edit: LineEdit
var _obj_x_spin: SpinBox
var _obj_y_spin: SpinBox
var _obj_width_spin: SpinBox
var _obj_height_spin: SpinBox
var _obj_rotation_spin: SpinBox
var _obj_elevation_spin: SpinBox
var _obj_fuel_spin: SpinBox
var _obj_hrr_spin: SpinBox

# ── Apertura ────────────────────────────────────────────────────────────────
var _opening_props_container: Control
var _opening_type_label: Label
var _opening_width_spin: SpinBox
var _opening_height_spin: SpinBox
var _opening_sill_spin: SpinBox
var _opening_offset_spin: SpinBox
var _opening_open_option: OptionButton
var _opening_swing_option: OptionButton
var _opening_hinge_option: OptionButton

# ── Detector ────────────────────────────────────────────────────────────────
var _detector_props_container: Control
var _detector_id_edit: LineEdit
var _detector_type_option: OptionButton
var _detector_threshold_spin: SpinBox
var _detector_x_spin: SpinBox
var _detector_y_spin: SpinBox

# ── Victima ─────────────────────────────────────────────────────────────────
var _victim_props_container: Control
var _victim_name_edit: LineEdit
var _victim_x_spin: SpinBox
var _victim_y_spin: SpinBox
var _victim_height_spin: SpinBox

var _panel_root: Control = null


# ============================================================================
# Enlace con la escena
# ============================================================================
func bind(panel_root: Control) -> bool:
	_panel_root = panel_root
	if _panel_root == null:
		push_error("EditorPropertyPanel: sin RightPanel en ScenarioEditorScene.tscn")
		return false
	_bind_room()
	_bind_object()
	_bind_opening()
	_bind_detector()
	_bind_victim()
	return _name_edit != null and _kind_edit != null and _height_spin != null \
		and _fuel_spin != null and _hrr_spin != null


func _bind_room() -> void:
	_name_edit = _control("RoomNameEdit") as LineEdit
	_kind_edit = _control("RoomKindEdit") as LineEdit
	_room_x_spin = _spin("RoomGeometry/RoomXRow/RoomXSpin", -200.0, 200.0, 0.05)
	_room_y_spin = _spin("RoomGeometry/RoomYRow/RoomYSpin", -200.0, 200.0, 0.05)
	_room_width_spin = _spin("RoomGeometry/RoomWidthRow/RoomWidthSpin", 0.25, 200.0, 0.05)
	_room_depth_spin = _spin("RoomGeometry/RoomDepthRow/RoomDepthSpin", 0.25, 200.0, 0.05)
	_room_rotation_spin = _spin("RoomGeometry/RoomRotationRow/RoomRotationSpin", -180.0, 180.0, 1.0)
	_height_spin = _control("RoomHeightSpin") as SpinBox
	_fuel_spin = _control("FuelEnergySpin") as SpinBox
	_hrr_spin = _control("MaxHrrSpin") as SpinBox
	_stair_turn_option = _control("RoomGeometry/StairTurnRow/StairTurnOption") as OptionButton
	_stair_walls_check = _control("RoomGeometry/StairWallsRow/StairWallsCheck") as CheckBox
	_stair_railings_check = _control("RoomGeometry/StairRailingsRow/StairRailingsCheck") as CheckBox
	_stair_angle_label = _control("RoomGeometry/StairAngleLabel") as Label
	_room_apply_button = _control("BtnApplyRoom") as Button
	_room_delete_button = _control("BtnDeleteRoom") as Button
	_tooltip(_room_apply_button, "Aplica los cambios numéricos de la habitación seleccionada.")
	_tooltip(_room_delete_button, "Borra la habitación seleccionada.")
	_on_pressed(_room_apply_button, ACTION_ROOM_APPLY)
	_on_pressed(_room_delete_button, ACTION_ROOM_DELETE)


func _bind_object() -> void:
	_obj_props_container = _control("ObjProps")
	_obj_name_edit = _control("ObjProps/ObjNameEdit") as LineEdit
	_obj_x_spin = _spin("ObjProps/ObjXRow/ObjXSpin", -200.0, 200.0, 0.05)
	_obj_y_spin = _spin("ObjProps/ObjYRow/ObjYSpin", -200.0, 200.0, 0.05)
	_obj_width_spin = _control("ObjProps/ObjWidthSpin") as SpinBox
	_obj_height_spin = _control("ObjProps/ObjHeightSpin") as SpinBox
	_obj_rotation_spin = _control("ObjProps/ObjRotationSpin") as SpinBox
	_obj_elevation_spin = _control("ObjProps/ObjElevationSpin") as SpinBox
	_obj_fuel_spin = _control("ObjProps/ObjFuelSpin") as SpinBox
	_obj_hrr_spin = _control("ObjProps/ObjHrrSpin") as SpinBox
	_on_pressed(_control("ObjProps/BtnApplyObject") as Button, ACTION_OBJECT_APPLY)
	_on_pressed(_control("ObjProps/BtnDeleteObject") as Button, ACTION_DELETE_SELECTED)


func _bind_opening() -> void:
	_opening_props_container = _control("OpeningProps")
	_opening_type_label = _control("OpeningProps/OpeningTypeLabel") as Label
	_opening_width_spin = _control("OpeningProps/OpeningWidthSpin") as SpinBox
	_opening_height_spin = _control("OpeningProps/OpeningHeightSpin") as SpinBox
	_opening_sill_spin = _control("OpeningProps/OpeningSillSpin") as SpinBox
	_opening_offset_spin = _spin("OpeningProps/OpeningOffsetRow/OpeningOffsetSpin", 0.0, 200.0, 0.05)
	_opening_open_option = _control("OpeningProps/OpeningOpenOption") as OptionButton
	_opening_swing_option = _control("OpeningProps/OpeningSwingRow/OpeningSwingOption") as OptionButton
	_opening_hinge_option = _control("OpeningProps/OpeningHingeRow/OpeningHingeOption") as OptionButton
	if _opening_open_option != null and _opening_open_option.get_item_count() == 0:
		_opening_open_option.add_item("Cerrada", 0)
		_opening_open_option.add_item("Abierta", 1)
	if _opening_swing_option != null and _opening_swing_option.get_item_count() == 0:
		_opening_swing_option.add_item("Interior", 0)
		_opening_swing_option.add_item("Exterior", 1)
	if _opening_hinge_option != null and _opening_hinge_option.get_item_count() == 0:
		_opening_hinge_option.add_item("Izquierda", 0)
		_opening_hinge_option.add_item("Derecha", 1)
	_on_pressed(_control("OpeningProps/BtnApplyOpening") as Button, ACTION_OPENING_APPLY)


func _bind_detector() -> void:
	_detector_props_container = _control("DetectorProps")
	_detector_id_edit = _control("DetectorProps/DetectorIdEdit") as LineEdit
	_detector_type_option = _control("DetectorProps/DetectorTypeOption") as OptionButton
	_detector_threshold_spin = _control("DetectorProps/DetectorThresholdSpin") as SpinBox
	_detector_x_spin = _spin("DetectorProps/DetectorXRow/DetectorXSpin", 0.0, 200.0, 0.05)
	_detector_y_spin = _spin("DetectorProps/DetectorYRow/DetectorYSpin", 0.0, 200.0, 0.05)
	if _detector_type_option != null:
		if _detector_type_option.get_item_count() == 0:
			_detector_type_option.add_item("Humo", 0)
			_detector_type_option.add_item("Calor", 1)
			_detector_type_option.add_item("CO", 2)
		if not _detector_type_option.item_selected.is_connected(_on_detector_type_selected):
			_detector_type_option.item_selected.connect(_on_detector_type_selected)
	sync_detector_threshold_units()
	var apply_button := _control("DetectorProps/BtnApplyDetector") as Button
	var delete_button := _control("DetectorProps/BtnDeleteDetector") as Button
	_tooltip(apply_button, "Aplica tipo, umbral y posición del detector seleccionado.")
	_tooltip(delete_button, "Borra el detector seleccionado.")
	_on_pressed(apply_button, ACTION_DETECTOR_APPLY)
	_on_pressed(delete_button, ACTION_DELETE_SELECTED)


func _bind_victim() -> void:
	_victim_props_container = _control("VictimProps")
	_victim_name_edit = _control("VictimProps/VictimNameEdit") as LineEdit
	_victim_x_spin = _spin("VictimProps/VictimXRow/VictimXSpin", 0.0, 200.0, 0.05)
	_victim_y_spin = _spin("VictimProps/VictimYRow/VictimYSpin", 0.0, 200.0, 0.05)
	_victim_height_spin = _spin("VictimProps/VictimHeightRow/VictimHeightSpin", 0.2, 2.2, 0.05)
	var apply_button := _control("VictimProps/BtnApplyVictim") as Button
	var delete_button := _control("VictimProps/BtnDeleteVictim") as Button
	_tooltip(apply_button, "Aplica nombre, posición local y plano respiratorio de la víctima seleccionada.")
	_tooltip(delete_button, "Borra la víctima seleccionada.")
	_on_pressed(apply_button, ACTION_VICTIM_APPLY)
	_on_pressed(delete_button, ACTION_DELETE_SELECTED)


func stair_turn_option() -> OptionButton:
	return _stair_turn_option


# ============================================================================
# Enseñar
# ============================================================================
## Rellena el panel entero. `state` trae los datos crudos de lo seleccionado mas
## lo que el panel no puede calcular por si mismo: el rectangulo de la sala, si
## es escalera, el texto del angulo, la posicion visual del objeto y los topes de
## la apertura.
func show(state: Dictionary) -> void:
	if _name_edit == null:
		return
	var room: Dictionary = state.get("room", {})
	var has_room: bool = not room.is_empty()
	var is_stair: bool = bool(state.get("room_is_stair", false))
	var obj: Dictionary = state.get("object", {})
	var has_obj: bool = not obj.is_empty()
	var opening: Dictionary = state.get("opening", {})
	var has_opening: bool = not opening.is_empty()
	var det: Dictionary = state.get("detector", {})
	var has_detector: bool = not det.is_empty()
	var vic: Dictionary = state.get("victim", {})
	var has_victim: bool = not vic.is_empty()

	_fill_room(state)
	if has_obj:
		fill_object(
			obj,
			state.get("object_visual_pos", Vector2.ZERO),
			state.get("object_size", Vector2.ONE),
			float(state.get("object_rotation_deg", 0.0))
		)
	if has_opening:
		_fill_opening(state)
	if has_detector:
		fill_detector(det)
	if has_victim:
		fill_victim(vic)

	_set_visibility(has_room, has_obj, has_opening, has_detector, has_victim, is_stair)
	set_stair_angle_text(String(state.get("stair_angle_text", "")))


func _fill_room(state: Dictionary) -> void:
	var room: Dictionary = state.get("room", {})
	var rect: Rect2 = state.get("room_rect", Rect2())
	var is_stair: bool = bool(state.get("room_is_stair", false))
	var has_room: bool = not room.is_empty()
	_name_edit.editable = has_room
	_kind_edit.editable = has_room
	_set_spin_editable(_room_x_spin, has_room)
	_set_spin_editable(_room_y_spin, has_room)
	_set_spin_editable(_room_width_spin, has_room)
	_set_spin_editable(_room_depth_spin, has_room)
	_set_spin_editable(_room_rotation_spin, has_room)
	_set_spin_editable(_height_spin, has_room)
	_set_spin_editable(_fuel_spin, has_room)
	_set_spin_editable(_hrr_spin, has_room)
	if _stair_turn_option != null:
		_stair_turn_option.disabled = not is_stair
	if _stair_walls_check != null:
		_stair_walls_check.disabled = not is_stair
	if _stair_railings_check != null:
		_stair_railings_check.disabled = not is_stair

	if has_room:
		_name_edit.text = String(room.get("name", ""))
		_kind_edit.text = String(room.get("kind", "generic"))
		_set_spin(_room_x_spin, rect.position.x)
		_set_spin(_room_y_spin, rect.position.y)
		_set_spin(_room_width_spin, maxf(0.25, rect.size.x))
		_set_spin(_room_depth_spin, maxf(0.25, rect.size.y))
		_set_spin(_room_rotation_spin, float(state.get("room_rotation_deg", 0.0)))
		_select_item_id(_stair_turn_option, int(state.get("stair_turn_item_id", 0)))
		if _stair_walls_check != null:
			_stair_walls_check.button_pressed = bool(room.get("stair_has_walls", false))
		if _stair_railings_check != null:
			_stair_railings_check.button_pressed = bool(room.get("stair_has_railings", true))
		_set_spin(_height_spin, float(room.get("height_m", 2.7)))
		_set_spin(_fuel_spin, float(room.get("fuel_energy_MJ", 0.0)))
		_set_spin(_hrr_spin, float(room.get("max_hrr_kw", 0.0)))
	else:
		_name_edit.text = ""
		_kind_edit.text = ""
		_set_spin(_room_x_spin, 0.0)
		_set_spin(_room_y_spin, 0.0)
		_set_spin(_room_width_spin, 1.0)
		_set_spin(_room_depth_spin, 1.0)
		_set_spin(_room_rotation_spin, 0.0)
		_select_item_id(_stair_turn_option, 0)
		if _stair_walls_check != null:
			_stair_walls_check.button_pressed = false
		if _stair_railings_check != null:
			_stair_railings_check.button_pressed = true
		_set_spin(_height_spin, 2.7)
		_set_spin(_fuel_spin, 0.0)
		_set_spin(_hrr_spin, 0.0)


## Publica: el editor la llama tambien mientras se arrastra un objeto en el
## plano, sin rehacer el panel entero.
func fill_object(obj: Dictionary, visual_pos: Vector2, size_m: Vector2, rotation_deg: float) -> void:
	if obj.is_empty():
		return
	if _obj_name_edit != null:
		_obj_name_edit.text = String(obj.get("name", obj.get("kind", "")))
	_set_spin(_obj_x_spin, visual_pos.x)
	_set_spin(_obj_y_spin, visual_pos.y)
	_set_spin(_obj_width_spin, size_m.x)
	_set_spin(_obj_height_spin, size_m.y)
	_set_spin(_obj_rotation_spin, rotation_deg)
	_set_spin(_obj_elevation_spin, float(obj.get("elevation_m", 0.0)))
	_set_spin(_obj_fuel_spin, float(obj.get("fuel_energy_MJ", 0.0)))
	_set_spin(_obj_hrr_spin, float(obj.get("max_hrr_kw", 0.0)))


func _fill_opening(state: Dictionary) -> void:
	if _opening_width_spin == null:
		return
	var opening: Dictionary = state.get("opening", {})
	var type_label: String = String(state.get("opening_type_label", ""))
	var max_width_m: float = float(state.get("opening_max_width_m", 6.0))
	var max_offset_m: float = float(state.get("opening_max_offset_m", 200.0))
	var op_type: String = String(opening.get("type", "door"))
	var is_vertical: bool = bool(opening.get("is_vertical", false))
	if _opening_type_label != null:
		_opening_type_label.text = type_label
	_opening_width_spin.max_value = max_width_m
	_opening_width_spin.value = float(opening.get("width_m", 0.9))
	if _opening_height_spin != null:
		_opening_height_spin.value = float(opening.get("height_m", 2.0))
	if _opening_offset_spin != null:
		_opening_offset_spin.editable = not is_vertical
		_opening_offset_spin.max_value = max_offset_m
		_opening_offset_spin.value = float(opening.get("offset_m", 0.0))
	if _opening_sill_spin != null:
		_opening_sill_spin.editable = op_type == "window"
		_opening_sill_spin.value = float(opening.get("sill_m", 0.0))
	if _opening_open_option != null:
		var frac: float = float(opening.get("open_fraction", 1.0))
		_opening_open_option.disabled = op_type == "hole"
		_opening_open_option.select(0 if frac <= 0.01 else 1)
	# Abre hacia y bisagra solo tienen sentido en una puerta de verdad.
	var is_door: bool = op_type == "door" and not is_vertical
	if _opening_swing_option != null:
		_set_row_visible(_opening_swing_option, is_door)
		_opening_swing_option.select(1 if String(opening.get("swing_direction", "in")).to_lower() == "out" else 0)
	if _opening_hinge_option != null:
		_set_row_visible(_opening_hinge_option, is_door)
		_opening_hinge_option.select(1 if String(opening.get("hinge_side", "left")).to_lower() == "right" else 0)


func fill_detector(det: Dictionary) -> void:
	if det.is_empty():
		return
	if _detector_id_edit != null:
		_detector_id_edit.text = String(det.get("id", ""))
	if _detector_type_option != null:
		var det_type: String = String(det.get("type", "smoke"))
		_detector_type_option.selected = 0 if det_type == "smoke" else (1 if det_type == "heat" else 2)
	_set_spin(_detector_threshold_spin, float(det.get("threshold", 0.025)))
	sync_detector_threshold_units()
	_set_spin(_detector_x_spin, float(det.get("x_m", 0.0)))
	_set_spin(_detector_y_spin, float(det.get("y_m", 0.0)))


func fill_victim(vic: Dictionary) -> void:
	if vic.is_empty():
		return
	if _victim_name_edit != null:
		_victim_name_edit.text = String(vic.get("name", ""))
	_set_spin(_victim_x_spin, float(vic.get("x_m", 0.0)))
	_set_spin(_victim_y_spin, float(vic.get("y_m", 0.0)))
	_set_spin(_victim_height_spin, float(vic.get("height_m", 0.9)))


func fill_room_rect(rect: Rect2) -> void:
	_set_spin(_room_x_spin, rect.position.x)
	_set_spin(_room_y_spin, rect.position.y)
	_set_spin(_room_width_spin, rect.size.x)
	_set_spin(_room_depth_spin, rect.size.y)


## El texto del angulo lo calcula el editor -necesita la cota de la planta de
## arriba-; aqui solo se enseña o se esconde.
func set_stair_angle_text(text: String) -> void:
	if _stair_angle_label == null:
		return
	_stair_angle_label.visible = text != ""
	_stair_angle_label.text = text


## La unidad del umbral depende del tipo de detector: 0,025 son kg/m³ de humo, 57
## son grados y 300 son ppm de CO. Con la casilla muda no habia forma de saber
## cual se estaba tecleando.
func sync_detector_threshold_units() -> void:
	if _detector_threshold_spin == null:
		return
	var selected: int = _detector_type_option.selected if _detector_type_option != null else 0
	var unit: String = " kg/m³"
	var help: String = "Densidad de humo en la sala a partir de la cual salta el detector, en kilogramos por metro cúbico. Un detector domestico salta en torno a 0,025."
	if selected == 1:
		unit = " °C"
		help = "Temperatura de la capa superior a partir de la cual salta el detector, en grados. Un rociador domestico salta en torno a 57."
	elif selected == 2:
		unit = " ppm"
		help = "Concentración de CO en la sala a partir de la cual salta el detector, en partes por millón. Un detector domestico salta en torno a 50."
	_detector_threshold_spin.suffix = unit
	_tooltip(_detector_threshold_spin, help)


func _on_detector_type_selected(_index: int) -> void:
	sync_detector_threshold_units()


# ============================================================================
# Enseñar y esconder
# ============================================================================
## El panel derecho entero desaparece cuando no hay nada seleccionado, y dentro
## de el cada ficha se enseña sola. Los separadores solo salen si hay algo antes
## y algo despues: si no, quedan rayas sueltas.
func _set_visibility(has_room: bool, has_obj: bool, has_opening: bool, has_detector: bool, has_victim: bool, is_stair: bool) -> void:
	if _panel_root == null:
		return
	_panel_root.visible = has_room or has_obj or has_opening or has_detector or has_victim

	for node_name in [
		"RoomTitle", "RoomNameEdit", "RoomKindEdit",
		"RoomXLabel", "RoomXSpin", "RoomYLabel", "RoomYSpin",
		"RoomWidthLabel", "RoomWidthSpin", "RoomDepthLabel", "RoomDepthSpin",
		"RoomRotationLabel", "RoomRotationSpin",
		"RoomHeightLabel", "RoomHeightSpin",
		"FuelEnergyLabel", "FuelEnergySpin",
		"MaxHrrLabel", "MaxHrrSpin",
		"BtnApplyRoom", "BtnDeleteRoom", "SeparatorB"
	]:
		_set_node_visible(node_name, has_room)
	_set_row_visible(_name_edit, has_room)
	_set_row_visible(_kind_edit, has_room)
	_set_row_visible(_room_x_spin, has_room)
	_set_row_visible(_room_y_spin, has_room)
	_set_row_visible(_room_width_spin, has_room)
	_set_row_visible(_room_depth_spin, has_room)
	_set_row_visible(_room_rotation_spin, has_room)
	_set_row_visible(_height_spin, has_room)
	_set_row_visible(_fuel_spin, has_room)
	_set_row_visible(_hrr_spin, has_room)
	_set_row_visible(_stair_turn_option, has_room and is_stair)
	_set_row_visible(_stair_walls_check, has_room and is_stair)
	_set_row_visible(_stair_railings_check, has_room and is_stair)
	if _room_apply_button != null:
		_room_apply_button.visible = has_room
	if _room_delete_button != null:
		_room_delete_button.visible = has_room
	var before_detector: bool = has_room or has_obj or has_opening
	var before_victim: bool = before_detector or has_detector
	_set_node_visible("ObjectTitle", has_obj)
	_set_node_visible("SeparatorC", has_opening and (has_room or has_obj))
	_set_node_visible("OpeningTitle", has_opening)
	_set_node_visible("SeparatorD", has_detector and before_detector)
	_set_node_visible("DetectorTitle", has_detector)
	_set_node_visible("SeparatorE", has_victim and before_victim)
	_set_node_visible("VictimTitle", has_victim)
	_set_node_visible("ObjProps/ObjWidthLabel", has_obj)
	_set_node_visible("ObjProps/ObjWidthSpin", has_obj)
	_set_node_visible("ObjProps/ObjHeightLabel", has_obj)
	_set_node_visible("ObjProps/ObjHeightSpin", has_obj)
	if _obj_props_container != null:
		_obj_props_container.visible = has_obj
	if _opening_props_container != null:
		_opening_props_container.visible = has_opening
	if _detector_props_container != null:
		_detector_props_container.visible = has_detector
	if _victim_props_container != null:
		_victim_props_container.visible = has_victim


# ============================================================================
# Leer lo que ha tecleado el usuario
# ============================================================================
## Lo que hay escrito en la ficha de habitacion. El editor decide que hacer con
## ello: validarlo, encajarlo en la rejilla y guardarlo con su paso de deshacer.
func read_room() -> Dictionary:
	return {
		"name": _name_edit.text.strip_edges() if _name_edit != null else "",
		"kind": _kind_edit.text.strip_edges() if _kind_edit != null else "",
		"x_m": _value(_room_x_spin),
		"y_m": _value(_room_y_spin),
		"width_m": _value(_room_width_spin),
		"depth_m": _value(_room_depth_spin),
		"rotation_deg": _value(_room_rotation_spin),
		"height_m": _value(_height_spin),
		"fuel_energy_MJ": _value(_fuel_spin),
		"max_hrr_kw": _value(_hrr_spin),
		"stair_has_walls": _pressed(_stair_walls_check),
		"stair_has_railings": _pressed(_stair_railings_check),
		"stair_turn_item_id": _selected_item_id(_stair_turn_option)
	}


func read_object() -> Dictionary:
	return {
		"name": _obj_name_edit.text.strip_edges() if _obj_name_edit != null else "",
		"x_m": _value(_obj_x_spin),
		"y_m": _value(_obj_y_spin),
		"width_m": _value(_obj_width_spin),
		"height_m": _value(_obj_height_spin),
		"rotation_deg": _value(_obj_rotation_spin),
		"elevation_m": _value(_obj_elevation_spin),
		"fuel_energy_MJ": _value(_obj_fuel_spin),
		"max_hrr_kw": _value(_obj_hrr_spin)
	}


func read_opening() -> Dictionary:
	return {
		"width_m": _value(_opening_width_spin),
		"height_m": _value(_opening_height_spin),
		"sill_m": _value(_opening_sill_spin),
		"offset_m": _value(_opening_offset_spin),
		"open_index": _opening_open_option.selected if _opening_open_option != null else 1,
		"swing_index": _opening_swing_option.selected if _opening_swing_option != null else 0,
		"hinge_index": _opening_hinge_option.selected if _opening_hinge_option != null else 0
	}


func read_detector() -> Dictionary:
	return {
		"id": _detector_id_edit.text.strip_edges() if _detector_id_edit != null else "",
		"type_index": _detector_type_option.selected if _detector_type_option != null else 0,
		"threshold": _value(_detector_threshold_spin),
		"x_m": _value(_detector_x_spin),
		"y_m": _value(_detector_y_spin)
	}


func read_victim() -> Dictionary:
	return {
		"name": _victim_name_edit.text.strip_edges() if _victim_name_edit != null else "",
		"x_m": _value(_victim_x_spin),
		"y_m": _value(_victim_y_spin),
		"height_m": _value(_victim_height_spin)
	}


func _control(path: String) -> Control:
	if _panel_root == null:
		return null
	var control := _panel_root.get_node_or_null("Scroll/VBox/" + path) as Control
	if control == null:
		push_error("EditorPropertyPanel: falta RightPanel/Scroll/VBox/%s en ScenarioEditorScene.tscn" % path)
	return control


## Casilla numerica con sus limites. El rango y el paso los sabe el codigo; la
## etiqueta y la unidad las trae la escena.
func _spin(path: String, min_value: float, max_value: float, step: float) -> SpinBox:
	var spin := _control(path) as SpinBox
	if spin == null:
		return null
	spin.min_value = min_value
	spin.max_value = max_value
	spin.step = step
	return spin


func _on_pressed(button: Button, action: String) -> void:
	if button == null:
		return
	var callable := Callable(self, "_emit_action").bind(action)
	if not button.pressed.is_connected(callable):
		button.pressed.connect(callable)


func _emit_action(action: String) -> void:
	action_requested.emit(action)


func _tooltip(control: Control, text: String) -> void:
	if control != null:
		control.tooltip_text = text


func _set_node_visible(path: String, visible: bool) -> void:
	if _panel_root == null:
		return
	var node := _panel_root.get_node_or_null("Scroll/VBox/" + path) as Control
	if node != null:
		node.visible = visible


## Una casilla vive dentro de su fila con la etiqueta al lado: esconder la
## casilla sola dejaria la etiqueta huerfana.
func _set_row_visible(control: Control, visible: bool) -> void:
	if control == null:
		return
	var parent := control.get_parent() as Control
	if parent != null and parent is HBoxContainer:
		parent.visible = visible
	else:
		control.visible = visible


func _set_spin(spin: SpinBox, value: float) -> void:
	if spin != null:
		spin.value = value


func _set_spin_editable(spin: SpinBox, editable: bool) -> void:
	if spin != null:
		spin.editable = editable


func _value(spin: SpinBox) -> float:
	return spin.value if spin != null else 0.0


func _pressed(check: CheckBox) -> bool:
	return check.button_pressed if check != null else false


func _select_item_id(option: OptionButton, item_id: int) -> void:
	if option == null:
		return
	for i in range(option.get_item_count()):
		if option.get_item_id(i) == item_id:
			option.select(i)
			return


func _selected_item_id(option: OptionButton) -> int:
	if option == null or option.selected < 0:
		return 0
	return option.get_item_id(option.selected)

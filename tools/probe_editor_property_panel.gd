extends SceneTree
## Sonda: que enseña el panel de propiedades para cada tipo de seleccion.
##
## El volcado del arbol (tools/probe_editor_ui_tree.gd) dice si un refactor ha
## movido un nodo de sitio; este dice si ha cambiado lo que el panel muestra y
## deja tocar. Monta un escenario con una sala, un objeto, una apertura, un
## detector, una victima y un muro, los selecciona uno a uno y vuelca, en cada
## caso, el estado de todos los mandos del panel derecho.
##
## Foto antes, foto despues, diff. Es la red para mover el panel a su modulo.
##
## Uso: godot --headless --path . --script res://tools/probe_editor_property_panel.gd -- <salida.txt>

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
	_editor.editor_data = _scenario()
	_editor.current_floor_index = 0

	var out: PackedStringArray = PackedStringArray()
	_snapshot("sin seleccion", func(): _editor._clear_selection(), out)
	_snapshot("sala 7", func(): _editor._select_room(7), out)
	_snapshot("sala 8 (escalera)", func(): _editor._select_room(8), out)
	_snapshot("objeto 7/0", func(): _editor._select_object(7, 0), out)
	_snapshot("apertura 0", func(): _editor._select_opening(0), out)
	_snapshot("detector 0", func(): _editor._select_detector(0), out)
	_snapshot("victima 0", func(): _editor._select_victim(0), out)
	_snapshot("muro exterior 0", func(): _editor._select_exterior_wall(0), out)

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
		print("[probe_props] %d lineas -> %s" % [out.size(), _out_path])
	quit(0)
	return true


func _snapshot(label: String, select: Callable, out: PackedStringArray) -> void:
	select.call()
	out.append("")
	out.append("=== %s ===" % label)
	var panel := _editor.get_node_or_null("CanvasLayer/UI/RightPanel") as Control
	if panel == null:
		out.append("  sin RightPanel")
		return
	out.append("  RightPanel visible=%s" % panel.visible)
	_dump(panel, "RightPanel", out)


func _dump(node: Node, path: String, out: PackedStringArray) -> void:
	for child in node.get_children():
		var child_path: String = "%s/%s" % [path, child.name]
		var control := child as Control
		if control != null:
			var line: String = "  %s visible=%s" % [child_path, control.visible]
			var spin := control as SpinBox
			var edit := control as LineEdit
			var option := control as OptionButton
			var check := control as CheckBox
			var button := control as Button
			if spin != null:
				line += " value=%.3f editable=%s suffix=%s" % [spin.value, spin.editable, spin.suffix]
			elif edit != null:
				line += " text=%s editable=%s" % [edit.text, edit.editable]
			elif option != null:
				line += " selected=%d disabled=%s" % [option.selected, option.disabled]
			elif check != null:
				line += " pressed=%s disabled=%s" % [check.button_pressed, check.disabled]
			elif button != null:
				line += " disabled=%s" % button.disabled
			elif "text" in control:
				line += " text=%s" % String(control.get("text")).replace("\n", "\\n")
			out.append(line)
		_dump(child, child_path, out)


## Un escenario con uno de cada cosa, escrito a mano para que la sonda no dependa
## de ningun fichero de disco.
func _scenario() -> Dictionary:
	return {
		"floors": [{"name": "PB", "level_m": 0.0}, {"name": "P1", "level_m": 2.7}],
		"exterior_walls": [{"a": {"x": 0.0, "y": 0.0}, "b": {"x": 6.0, "y": 0.0}, "thickness_m": 0.16}],
		"room_rect_m": {
			"7": {"x": 0.0, "y": 0.0, "w": 4.0, "h": 3.0},
			"8": {"x": 4.5, "y": 0.0, "w": 2.4, "h": 3.0}
		},
		"rooms_data": [
			{
				"id": 7,
				"name": "Dormitorio",
				"kind": "generic",
				"rotation_deg": 15.0,
				"height_m": 2.55,
				"floor_level_z_m": 0.0,
				"fuel_energy_MJ": 320.0,
				"max_hrr_kw": 1250.0,
				"fuel_objects": [{
					"id": "obj_001",
					"room_id": 7,
					"name": "cama",
					"kind": "cama",
					"position_m": {"x": 0.5, "y": 0.4},
					"size_m": {"x": 1.4, "y": 2.0},
					"rotation_deg": 90.0,
					"fuel_energy_MJ": 180.0,
					"max_hrr_kw": 900.0,
					"is_primary_ignition_source": true
				}]
			},
			{
				"id": 8,
				"name": "Escalera PB",
				"kind": "escalera",
				"rotation_deg": 0.0,
				"height_m": 2.7,
				"floor_level_z_m": 0.0,
				"stair_has_walls": true,
				"stair_has_railings": false,
				"stair_turn_degrees": 180.0,
				"stair_turn_mode": "u",
				"fuel_objects": []
			}
		],
		"openings_data": [{
			"a": 7,
			"b": -1,
			"type": "window",
			"wall": "top",
			"offset_m": 1.2,
			"offset_is_fraction": false,
			"width_m": 1.1,
			"height_m": 1.3,
			"sill_m": 0.9,
			"open_fraction": 0.5,
			"swing_direction": "out",
			"hinge_side": "right"
		}],
		"detectors": [{"id": "det_001", "room_id": 7, "type": "heat", "threshold": 57.0, "x_m": 1.5, "y_m": 1.0}],
		"victims": [{"id": "vic_001", "room_id": 7, "name": "Víctima 1", "x_m": 2.0, "y_m": 1.2, "height_m": 0.95}],
		"player_start": {},
		"ignition_room_id": 7
	}

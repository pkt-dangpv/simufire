extends SceneTree
## Sonda de EQUIVALENCIA de la familia de APERTURAS del editor (D-1, §22 de la
## auditoria del editor): puertas, huecos, ventanas, balconeras, el paso que se
## abre solo hacia la circulacion, editar una apertura y borrarla.
##
## Se fotografia el escenario -y la apertura que queda seleccionada, que tambien
## es parte de lo que hace cada gesto- antes de mudar sus mutaciones a
## `ScenarioDocument`, y despues se compara byte a byte.
##
##   <godot> --headless --path . --script res://tools/probe_openings_family.gd -- <salida.json>

const TOOL_ROOM: int = 1

var _editor: Node = null
var _frames: int = 0
var _pasos: Array = []


func _initialize() -> void:
	_editor = (load("res://scenes/ScenarioEditorScene.tscn") as PackedScene).instantiate()
	root.add_child(_editor)


func _foto(nombre: String) -> void:
	_pasos.append({
		"paso": nombre,
		"seleccion": int(_editor.selected_opening_index),
		"escenario": _editor.editor_data.duplicate(true),
	})


func _process(_d: float) -> bool:
	_frames += 1
	if _frames < 4:
		return false
	# Dos salas pegadas y un pasillo debajo de las dos.
	_editor.adopt_scenario_data({
		"building_type": "apartment", "apartment_floor_number": 0,
		"floors": [{"name": "R", "level_m": 0.0}],
		"exterior_walls": [],
		"room_rect_m": {
			"1": {"x": 0.0, "y": 0.0, "w": 5.0, "h": 4.0},
			"2": {"x": 5.0, "y": 0.0, "w": 4.0, "h": 4.0},
			"3": {"x": 0.0, "y": 4.0, "w": 9.0, "h": 1.2},
		},
		"rooms_data": [
			{"id": 1, "name": "Salon", "kind": "salon", "rotation_deg": 0.0, "height_m": 2.6, "floor_level_z_m": 0.0, "fuel_objects": []},
			{"id": 2, "name": "Dormitorio", "kind": "dormitorio", "rotation_deg": 0.0, "height_m": 2.6, "floor_level_z_m": 0.0, "fuel_objects": []},
			{"id": 3, "name": "Pasillo", "kind": "pasillo", "rotation_deg": 0.0, "height_m": 2.6, "floor_level_z_m": 0.0, "fuel_objects": []},
		],
		"openings_data": [], "detectors": [], "victims": [],
		"player_start": {}, "ignition_room_id": 1,
	}, 0)
	_foto("00_inicio")

	_editor._create_door_at(Vector2(5.0, 1.0))
	_foto("01_puerta_entre_salas")
	_editor._create_door_at(Vector2(1.5, 0.0))
	_foto("02_puerta_exterior")
	_editor._create_hole_at(Vector2(5.0, 3.0))
	_foto("03_hueco")
	_editor._create_window_at(Vector2(3.5, 0.0))
	_foto("04_ventana")
	_editor._create_balcony_door_at(Vector2(7.0, 0.0))
	_foto("05_balconera_clic")
	_editor._create_balcony_door_from_drag(Vector2(0.0, 0.5), Vector2(-1.0, 3.5))
	_foto("06_balconera_arrastrada")

	# Una sala pegada al pasillo: el paso se abre solo.
	_editor.current_tool = TOOL_ROOM
	_editor._handle_press(Vector2(0.0, 5.2))
	_editor._handle_release(Vector2(4.0, 8.0))
	_editor.current_tool = 0
	_foto("07_sala_pegada_al_pasillo")

	# El hueco (apertura 2) se convierte en puerta desde la ficha, como lo hace
	# `validate_corridors`.
	var ops: Array = _editor.editor_data.get("openings_data", [])
	_editor.selected_opening_index = 2
	_editor._props.show({"opening": ops[2], "opening_type_label": "Hueco",
		"opening_max_width_m": 3.0, "opening_max_offset_m": 10.0,
		"opening_accepts_balcony": false, "opening_balcony_max_width_m": 3.0})
	_editor._props._opening_type_option.select(0)
	_editor._apply_opening_properties()
	_foto("08_hueco_hecho_puerta")

	_editor._delete_opening(1)
	_foto("09_apertura_borrada")

	_editor._undo_last_action()
	_foto("10_deshacer")
	_editor._undo_last_action()
	_foto("11_deshacer_otra")
	_editor._redo_last_action()
	_foto("12_rehacer")
	_editor._redo_last_action()
	_foto("13_rehacer_otra")

	var out: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://probe_openings_family.json"
	var f := FileAccess.open(out, FileAccess.WRITE)
	f.store_string(JSON.stringify(_pasos, "  ", true))
	f.close()
	print("[probe_openings_family] %d pasos -> %s" % [_pasos.size(), out])
	quit(0)
	return true

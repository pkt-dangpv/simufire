extends SceneTree
## Sonda de EQUIVALENCIA de la familia de MARCADORES del editor (D-1, §22 de la
## auditoria del editor): detectores, victimas, inicio FP y foco inicial.
##
## Se fotografia el escenario -y lo que queda seleccionado- tras cada gesto
## antes de mudar sus mutaciones a `ScenarioDocument`, y despues se compara byte
## a byte.
##
##   <godot> --headless --path . --script res://tools/probe_markers_family.gd -- <salida.json>

var _editor: Node = null
var _frames: int = 0
var _pasos: Array = []


func _initialize() -> void:
	_editor = (load("res://scenes/ScenarioEditorScene.tscn") as PackedScene).instantiate()
	root.add_child(_editor)


func _foto(nombre: String) -> void:
	_pasos.append({
		"paso": nombre,
		"seleccion": [int(_editor.selected_detector_index), int(_editor.selected_victim_index),
			int(_editor.selected_player_start_room_id), int(_editor.selected_object_room_id),
			int(_editor.selected_object_index), int(_editor.selected_room_id)],
		"escenario": _editor.editor_data.duplicate(true),
	})


func _process(_d: float) -> bool:
	_frames += 1
	if _frames < 4:
		return false
	_editor.adopt_scenario_data({
		"building_type": "apartment", "apartment_floor_number": 0,
		"floors": [{"name": "R", "level_m": 0.0}],
		"exterior_walls": [],
		"room_rect_m": {
			"1": {"x": 0.0, "y": 0.0, "w": 5.0, "h": 4.0},
			"2": {"x": 5.0, "y": 0.0, "w": 4.0, "h": 4.0},
		},
		"rooms_data": [
			{"id": 1, "name": "Salon", "kind": "salon", "rotation_deg": 0.0, "height_m": 2.6,
				"floor_level_z_m": 0.0, "fuel_energy_MJ": 400.0, "max_hrr_kw": 900.0,
				"fuel_objects": [{
					"id": "obj_001", "room_id": 1, "name": "sofa", "kind": "sofa",
					"position_m": {"x": 0.6, "y": 0.5}, "size_m": {"x": 2.0, "y": 0.9},
					"rotation_deg": 0.0, "elevation_m": 0.0,
					"fuel_energy_MJ": 260.0, "max_hrr_kw": 900.0}]},
			{"id": 2, "name": "Dormitorio", "kind": "dormitorio", "rotation_deg": 0.0, "height_m": 2.6,
				"floor_level_z_m": 0.0, "fuel_objects": []},
		],
		"openings_data": [], "detectors": [], "victims": [],
		"player_start": {}, "ignition_room_id": 1,
	}, 0)
	_foto("00_inicio")

	_editor._create_detector_at(Vector2(2.5, 2.0))
	_foto("01_detector")
	_editor._create_victim_at(Vector2(6.0, 2.0))
	_foto("02_victima")

	_editor._select_detector(0)
	_editor._props._detector_threshold_spin.value = 0.04
	_editor._apply_detector_properties()
	_foto("03_detector_editado")

	_editor._select_victim(0)
	_editor._props._victim_name_edit.text = "Ana"
	_editor._props._victim_height_spin.value = 1.2
	_editor._apply_victim_properties()
	_foto("04_victima_editada")

	_editor._create_player_start_at(Vector2(1.0, 1.0))
	_foto("05_inicio_fp")
	_editor._move_marker_to("detectors", 0, Vector2(7.0, 3.0))
	_foto("06_detector_movido_a_otra_sala")
	_editor._move_player_start_to(Vector2(6.5, 1.5))
	_foto("07_inicio_movido")
	_editor._mark_object_as_ignition(1, 0)
	_foto("08_foco_inicial")

	_editor._select_detector(0)
	_editor._duplicate_selection()
	_foto("09_detector_duplicado")
	_editor._select_victim(0)
	_editor._copy_selection()
	_editor._paste_clipboard_at(Vector2(3.0, 3.0))
	_foto("10_victima_pegada")
	_editor._select_victim(1)
	_editor._delete_selected()
	_foto("11_victima_borrada")
	_editor._select_player_start(2)
	_editor._delete_selected()
	_foto("12_inicio_borrado")

	_editor._undo_last_action()
	_foto("13_deshacer")
	_editor._undo_last_action()
	_foto("14_deshacer_otra")
	_editor._redo_last_action()
	_foto("15_rehacer")
	_editor._redo_last_action()
	_foto("16_rehacer_otra")

	var out: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://probe_markers_family.json"
	var f := FileAccess.open(out, FileAccess.WRITE)
	f.store_string(JSON.stringify(_pasos, "  ", true))
	f.close()
	print("[probe_markers_family] %d pasos -> %s" % [_pasos.size(), out])
	quit(0)
	return true

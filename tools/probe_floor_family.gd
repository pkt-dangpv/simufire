extends SceneTree
## Sonda de EQUIVALENCIA de la familia de PLANTAS del editor (D-1, §22 de la
## auditoria del editor): añadir planta vacia, añadirla copiando otra, cambiar
## la cota de una planta y borrarla.
##
## Se fotografia el escenario tras cada gesto antes de mudar sus mutaciones a
## `ScenarioDocument`, y despues se compara byte a byte. El piso de partida trae
## una de cada cosa que la copia sube -o no sube-: salas, puerta, ventana,
## mueble, detector, victima, inicio FP y una escalera.
##
##   <godot> --headless --path . --script res://tools/probe_floor_family.gd -- <salida.json>

const TOOL_STAIRS: int = 3

var _editor: Node = null
var _frames: int = 0
var _pasos: Array = []


func _initialize() -> void:
	_editor = (load("res://scenes/ScenarioEditorScene.tscn") as PackedScene).instantiate()
	root.add_child(_editor)


func _foto(nombre: String) -> void:
	_pasos.append({"paso": nombre, "planta": int(_editor.current_floor_index), "escenario": _editor.editor_data.duplicate(true)})


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
			"2": {"x": 5.0, "y": 0.0, "w": 3.0, "h": 4.0},
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
				"floor_level_z_m": 0.0, "fuel_energy_MJ": 300.0, "max_hrr_kw": 700.0, "fuel_objects": []},
		],
		"openings_data": [
			{"a": 1, "b": 2, "type": "door", "wall": "right", "offset_m": 2.0, "offset_is_fraction": false,
				"width_m": 0.82, "height_m": 2.05, "sill_m": 0.0, "open_fraction": 1.0},
			{"a": 1, "b": -1, "type": "window", "wall": "top", "offset_m": 2.5, "offset_is_fraction": false,
				"width_m": 1.2, "height_m": 1.1, "sill_m": 0.9, "open_fraction": 0.0},
		],
		"detectors": [{"id": "det_001", "room_id": 1, "type": "smoke", "threshold": 0.025, "x_m": 2.0, "y_m": 2.0}],
		"victims": [{"id": "vic_001", "room_id": 2, "name": "Victima 1", "x_m": 1.5, "y_m": 2.0, "height_m": 0.9}],
		"player_start": {"room_id": 1, "x_m": 1.0, "y_m": 1.0},
		"ignition_room_id": 1,
	}, 0)
	_foto("00_inicio")

	# Una escalera en la baja: al crear planta tiene que encadenarse.
	_editor.current_floor_index = 0
	_editor.current_tool = TOOL_STAIRS
	_editor._handle_press(Vector2(-3.0, 0.0))
	_editor._handle_release(Vector2(0.0, 4.0))
	_editor.current_tool = 0
	_foto("01_escalera")

	_editor.current_floor_index = 0
	_editor._create_floor(false)
	_foto("02_planta_vacia")

	_editor.current_floor_index = 0
	_editor._create_floor(true)
	_foto("03_planta_copiada")

	_editor.current_floor_index = 1
	_editor._on_floor_level_changed(3.2)
	_foto("04_cota_cambiada")

	_editor.current_floor_index = 2
	_editor._delete_floor_pressed()
	_foto("05_planta_borrada")

	# Sin nada que borrar: la unica planta no se borra.
	_editor._undo_last_action()
	_foto("06_deshacer_borrado")
	_editor._undo_last_action()
	_foto("07_deshacer_cota")
	_editor._redo_last_action()
	_foto("08_rehacer_cota")
	_editor._redo_last_action()
	_foto("09_rehacer_borrado")

	var out: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://probe_floor_family.json"
	var f := FileAccess.open(out, FileAccess.WRITE)
	f.store_string(JSON.stringify(_pasos, "  ", true))
	f.close()
	print("[probe_floor_family] %d pasos -> %s" % [_pasos.size(), out])
	quit(0)
	return true

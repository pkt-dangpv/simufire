extends SceneTree
## Sonda: que hace cada gesto de raton en el editor.
##
## La entrada del editor es una maquina de estados con memoria entre eventos
## -pulsar, mover, soltar-, y ninguna de las otras sondas la toca: el arbol mira
## la UI, el panel mira los mandos y las fotos miran el plano dibujado. Esta da
## gestos completos y vuelca lo que queda: la seleccion, las banderas de arrastre
## y el escenario entero en JSON ordenado.
##
## Los gestos se dan por el plano, en metros, llamando a los mismos manejadores
## que llama `_unhandled_input` despues de convertir la posicion del raton. Asi
## la sonda prueba la maquina y no la conversion de coordenadas.
##
##   godot --headless --path . --script res://tools/probe_editor_mouse.gd -- <salida.txt>

## Los numeros de herramienta, con su nombre: el enum vive en el editor y aqui
## se escribe una vez para no sembrar el fichero de cifras sueltas.
const SELECT: int = 0
const EXTERIOR_WALL: int = 1
const ROOM: int = 2
const CORRIDOR_L: int = 3
const STAIRS: int = 4
const DOOR: int = 5
const HOLE: int = 6
const WINDOW: int = 7
const OBJECT: int = 8
const IGNITION: int = 9
const PLAYER_START: int = 10
const DELETE: int = 11
const DETECTOR: int = 12
const VICTIM: int = 13

## Los nombres del enum Drag del editor, para que el volcado se lea.
const DRAG_NAMES: Array[String] = ["nada", "muro", "rect_sala", "geometria_sala", "objeto"]

var _editor: Node = null
var _frames: int = 0
var _out_path: String = ""
var _out: PackedStringArray = PackedStringArray()


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

	# Cada gesto arranca del mismo escenario: asi un fallo no arrastra al
	# siguiente y cada bloque del volcado se puede leer solo.
	_gesture("dibujar una sala", ROOM, [
		["press", Vector2(0.0, 6.0)],
		["motion", Vector2(2.0, 7.5)],
		["release", Vector2(4.0, 9.0)]
	])
	_gesture("dibujar un pasillo en L", CORRIDOR_L, [
		["press", Vector2(0.5, 6.0)],
		["motion", Vector2(3.0, 6.0)],
		["release", Vector2(5.0, 8.0)]
	])
	# Pasillos: pegado a una sala, y un clic seco como descansillo.
	_gesture("pasillo pegado a una sala", CORRIDOR_L, [
		["press", Vector2(0.5, 6.2)],
		["motion", Vector2(3.0, 6.2)],
		["release", Vector2(5.0, 6.2)]
	])
	_gesture("descansillo de un clic", CORRIDOR_L, [
		["press", Vector2(2.0, 6.2)],
		["release", Vector2(2.0, 6.2)]
	])
	# Componer: dos tramos pegados tienen que unirse entre si. Es lo que sustituye
	# al modo "L" y lo que permite hacer una U o un rellano.
	_gesture("dos tramos de pasillo en L", CORRIDOR_L, [
		["press", Vector2(0.5, 6.2)],
		["release", Vector2(5.0, 6.2)],
		["press", Vector2(5.0, 6.2)],
		["release", Vector2(5.0, 9.0)]
	])
	_gesture("dibujar una escalera", STAIRS, [
		["press", Vector2(7.0, 1.0)],
		["release", Vector2(9.4, 4.4)]
	])
	_gesture("dibujar un muro exterior", EXTERIOR_WALL, [
		["press", Vector2(-0.4, 6.4)],
		["motion", Vector2(4.0, 6.4)],
		["release", Vector2(7.6, 6.4)]
	])
	# La medida escrita: se arrastra a ojo y se teclea 4;3.
	_gesture("dibujar una sala escribiendo 4;3", ROOM, [
		["press", Vector2(0.0, 6.0)],
		["motion", Vector2(1.3, 7.1)],
		["type", "4;3"],
		["dump", Vector2.ZERO],
		["enter", Vector2.ZERO]
	])
	_gesture("dibujar una sala escribiendo 3,5", ROOM, [
		["press", Vector2(0.0, 6.0)],
		["motion", Vector2(1.3, 7.1)],
		["type", "3,5"],
		["enter", Vector2.ZERO]
	])
	_gesture("muro exterior escribiendo 6", EXTERIOR_WALL, [
		["press", Vector2(0.0, 6.0)],
		["motion", Vector2(1.0, 6.0)],
		["type", "6"],
		["enter", Vector2.ZERO]
	])
	_gesture("dibujar una sala, a medio arrastre", ROOM, [
		["press", Vector2(0.0, 6.0)],
		["motion", Vector2(2.0, 7.5)],
		["dump", Vector2.ZERO],
		["release", Vector2(4.0, 9.0)]
	])
	_gesture("seleccionar una sala", SELECT, [["press", Vector2(3.8, 2.9)], ["release", Vector2(3.8, 2.9)]])
	_gesture("mover la sala, a medio arrastre", SELECT, [
		["press", Vector2(3.8, 2.9)],
		["release", Vector2(3.8, 2.9)],
		["press", Vector2(3.8, 2.9)],
		["dump", Vector2.ZERO],
		["motion_room", Vector2(4.4, 3.4)],
		["dump", Vector2.ZERO],
		["release", Vector2(4.4, 3.4)]
	])
	_gesture("seleccionar un objeto y no soltarlo", SELECT, [
		["press", Vector2(1.2, 0.9)],
		["release", Vector2(1.2, 0.9)],
		["press", Vector2(1.2, 0.9)],
		["dump", Vector2.ZERO],
		["motion_object", Vector2(2.4, 1.6)],
		["dump", Vector2.ZERO],
		["release", Vector2(2.4, 1.6)]
	])
	_gesture("mover la sala seleccionada", SELECT, [
		["press", Vector2(2.0, 1.5)],
		["release", Vector2(2.0, 1.5)],
		["press", Vector2(2.0, 1.5)],
		["motion_room", Vector2(3.0, 2.0)],
		["release", Vector2(3.0, 2.0)]
	])
	_gesture("seleccionar un objeto", SELECT, [["press", Vector2(1.2, 0.9)], ["release", Vector2(1.2, 0.9)]])
	_gesture("mover el objeto seleccionado", SELECT, [
		["press", Vector2(1.2, 0.9)],
		["release", Vector2(1.2, 0.9)],
		["press", Vector2(1.2, 0.9)],
		["motion_object", Vector2(2.4, 1.6)],
		["release", Vector2(2.4, 1.6)]
	])
	_gesture("colocar una puerta", DOOR, [["press", Vector2(2.0, 3.4)], ["release", Vector2(2.0, 3.4)]])
	_gesture("colocar una ventana", WINDOW, [["press", Vector2(3.0, 0.02)], ["release", Vector2(3.0, 0.02)]])
	_gesture("colocar un hueco", HOLE, [["press", Vector2(5.0, 3.4)], ["release", Vector2(5.0, 3.4)]])
	_gesture("colocar un objeto", OBJECT, [["press", Vector2(3.4, 2.6)], ["release", Vector2(3.4, 2.6)]])
	_gesture("marcar ignicion", IGNITION, [["press", Vector2(1.2, 0.9)], ["release", Vector2(1.2, 0.9)]])
	_gesture("colocar un detector", DETECTOR, [["press", Vector2(2.0, 4.4)], ["release", Vector2(2.0, 4.4)]])
	_gesture("colocar una victima", VICTIM, [["press", Vector2(3.0, 4.4)], ["release", Vector2(3.0, 4.4)]])
	_gesture("colocar el inicio del jugador", PLAYER_START, [["press", Vector2(5.0, 4.4)], ["release", Vector2(5.0, 4.4)]])
	_gesture("borrar un objeto", DELETE, [["press", Vector2(1.2, 0.9)], ["release", Vector2(1.2, 0.9)]])
	_gesture("clic en el vacio", SELECT, [["press", Vector2(20.0, 20.0)], ["release", Vector2(20.0, 20.0)]])

	var text: String = "\n".join(_out)
	if _out_path == "":
		print(text)
	else:
		var file := FileAccess.open(_out_path, FileAccess.WRITE)
		if file == null:
			print("no se puede escribir ", _out_path)
			quit(1)
			return true
		file.store_string(text)
		print("[probe_mouse] %d lineas -> %s" % [_out.size(), _out_path])
	quit(0)
	return true


## Un gesto: herramienta, y la secuencia pulsar / mover / soltar en metros.
func _gesture(label: String, tool_id: int, steps: Array) -> void:
	_editor.editor_data = _scenario()
	_editor.current_floor_index = 0
	_editor._clear_selection()
	_editor._clear_drag()
	_editor.current_tool = tool_id
	for step in steps:
		var kind: String = String(step[0])
		var pos_m: Vector2 = step[1] if step[1] is Vector2 else Vector2.ZERO
		match kind:
			"press":
				_editor._handle_press(pos_m)
			"release":
				_editor._handle_release(pos_m)
			"motion":
				# Lo que hace el manejador de movimiento cuando hay un arrastre
				# de rectangulo en curso.
				_editor.drag_current_m = pos_m
			"motion_room":
				_editor._update_dragged_room_geometry(pos_m)
			"motion_object":
				_editor._update_dragged_object(pos_m)
			"type":
				# Teclas de verdad, por _unhandled_input: es donde vive el
				# teclado de medidas.
				for letter in String(step[1]):
					var key := InputEventKey.new()
					key.pressed = true
					key.unicode = letter.unicode_at(0)
					_editor._unhandled_input(key)
			"enter":
				var enter := InputEventKey.new()
				enter.pressed = true
				enter.keycode = KEY_ENTER
				_editor._unhandled_input(enter)
			"dump":
				# El estado con el arrastre abierto: es lo que distingue una
				# maquina de estados de una funcion.
				_out.append("")
				_out.append("--- %s, a mitad del gesto" % label)
				_dump_state()
	_out.append("")
	_out.append("=== %s (herramienta %d) ===" % [label, tool_id])
	_dump_state()
	_out.append(JSON.stringify(_editor.editor_data, "  ", true, true))


func _dump_state() -> void:
	_out.append("  seleccion: sala=%d apertura=%d objeto=%d/%d detector=%d victima=%d inicio=%d muro=%d" % [
		_editor.selected_room_id, _editor.selected_opening_index,
		_editor.selected_object_room_id, _editor.selected_object_index,
		_editor.selected_detector_index, _editor.selected_victim_index,
		_editor.selected_player_start_room_id, _editor.selected_exterior_wall_index
	])
	_out.append("  arrastre: %s modo_objeto=%d modo_sala=%d" % [
		DRAG_NAMES[int(_editor.drag)] if int(_editor.drag) < DRAG_NAMES.size() else str(_editor.drag),
		_editor.object_mouse_mode, _editor.room_mouse_mode
	])
	_out.append("  anclas: inicio=(%.3f, %.3f) actual=(%.3f, %.3f) puerta_pendiente=%d" % [
		_editor.drag_start_m.x, _editor.drag_start_m.y,
		_editor.drag_current_m.x, _editor.drag_current_m.y,
		_editor.pending_door_room_id
	])
	_out.append("  estado: %s" % (_editor._status_label.text if _editor._status_label != null else "-"))


## El mismo piso que usa la sonda de fotos, para poder leer las dos a la vez.
func _scenario() -> Dictionary:
	return {
		"floors": [{"name": "PB", "level_m": 0.0}, {"name": "P1", "level_m": 2.7}],
		"exterior_walls": [],
		"room_rect_m": {
			"7": {"x": 0.0, "y": 0.0, "w": 4.2, "h": 3.4},
			"8": {"x": 4.2, "y": 0.0, "w": 2.6, "h": 3.4},
			"9": {"x": 0.0, "y": 3.4, "w": 6.8, "h": 2.2}
		},
		"rooms_data": [
			{
				"id": 7, "name": "Salón", "kind": "generic", "rotation_deg": 0.0,
				"height_m": 2.7, "floor_level_z_m": 0.0,
				"fuel_energy_MJ": 420.0, "max_hrr_kw": 1600.0,
				"fuel_objects": [{
					"id": "obj_001", "room_id": 7, "name": "sofa", "kind": "sofa",
					"position_m": {"x": 0.6, "y": 0.5}, "size_m": {"x": 2.0, "y": 0.9},
					"rotation_deg": 0.0, "elevation_m": 0.0,
					"fuel_energy_MJ": 260.0, "max_hrr_kw": 900.0
				}]
			},
			{
				"id": 8, "name": "Escalera PB", "kind": "escalera", "rotation_deg": 0.0,
				"height_m": 2.7, "floor_level_z_m": 0.0,
				"stair_turn_degrees": 180.0, "stair_turn_mode": "switchback",
				"stair_run_direction_m": {"x": 0.0, "y": 1.0}, "fuel_objects": []
			},
			{
				"id": 9, "name": "Pasillo", "kind": "pasillo", "rotation_deg": 0.0,
				"height_m": 2.7, "floor_level_z_m": 0.0, "fuel_objects": []
			}
		],
		"openings_data": [],
		"detectors": [],
		"victims": [],
		"player_start": {},
		"ignition_room_id": -1
	}

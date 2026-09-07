extends SceneTree
## Sonda: la tabla de resultados de la geometria de escaleras.
##
## Sirve de foto antes/despues al mover esas funciones del editor a
## editor/StairGeometry.gd. Recorre una malla de rectangulos, direcciones y modos
## de giro y vuelca cada resultado con seis decimales: si el fichero sale igual,
## la mudanza no ha cambiado ni un numero.
##
## El mismo fichero vale para los dos lados, y ahi esta la gracia: se le dice a
## quien preguntar. `editor` llama a los metodos del editor -que llevan guion
## bajo delante-, `modulo` a las estaticas del modulo.
##
##   godot --headless --path . --script res://tools/probe_stair_geometry.gd -- <salida.txt> [editor|modulo]

const StairGeometryScript = preload("res://editor/StairGeometry.gd")

const RECTS: Array[Rect2] = [
	Rect2(0.0, 0.0, 4.0, 3.0),
	Rect2(1.5, -2.0, 2.4, 5.6),
	Rect2(0.0, 0.0, 1.2, 1.2),
	Rect2(-3.0, 2.0, 6.0, 1.9),
	Rect2(0.0, 0.0, 2.6, 2.6),
	Rect2(0.0, 0.0, 0.0, 0.0),
]
const DIRS: Array[Vector2] = [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN, Vector2(0.7, 0.71)]
const MODES: Array[String] = ["auto", "straight", "switchback", "AUTO", "  Recta  ", "loquesea"]

## Las estaticas del modulo se llaman igual sobre una instancia, y `callv` solo
## funciona sobre una instancia.
var _module: RefCounted = StairGeometryScript.new()
var _editor: Node = null
var _frames: int = 0
var _out_path: String = ""
var _ask_editor: bool = true


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		_out_path = args[0]
	if args.size() > 1:
		_ask_editor = args[1] != "modulo"
	if _ask_editor:
		var packed := load("res://scenes/ScenarioEditorScene.tscn") as PackedScene
		_editor = packed.instantiate()
		root.add_child(_editor)


func _process(_delta: float) -> bool:
	_frames += 1
	if _ask_editor and _frames < 5:
		return false
	var out: PackedStringArray = PackedStringArray()
	out.append("origen: %s" % ("editor" if _ask_editor else "modulo"))

	for mode in MODES:
		out.append("normalized_turn_mode(%s) = %s" % [mode, _call("normalized_turn_mode", [mode])])
		out.append("turn_mode_label(%s) = %s" % [mode, _call("turn_mode_label", [mode])])
	for degrees in [0.0, 90.0, 178.9, 179.0, 180.0]:
		out.append("turn_mode_from_degrees(%.1f) = %s" % [degrees, _call("turn_mode_from_degrees", [degrees])])
	for rotation in [-180.0, -90.0, -45.0, 0.0, 30.0, 90.0, 179.0]:
		out.append("direction_from_rotation(%.1f) = %s" % [rotation, _v(_call("direction_from_rotation", [rotation]))])

	for rect in RECTS:
		for dir in DIRS:
			out.append("--- rect %s dir %s" % [_r(rect), _v(dir)])
			out.append("  long_span_m       = %.6f" % _call("long_span_m", [rect, dir]))
			out.append("  cross_span_m      = %.6f" % _call("cross_span_m", [rect, dir]))
			out.append("  ramp_width_m      = %.6f" % _call("ramp_width_m", [rect, dir]))
			out.append("  landing_depth_m   = %.6f" % _call("landing_depth_m", [rect, dir]))
			out.append("  can_use_180       = %s" % _call("can_use_180_landing", [rect, dir]))
			for mode in ["auto", "straight", "switchback"]:
				var degrees: float = _call("turn_degrees_for_mode", [rect, dir, mode])
				out.append("  turn_degrees(%s) = %.6f" % [mode, degrees])
				out.append("    effective_run_m = %.6f" % _call("effective_run_m", [rect, dir, degrees]))
				out.append("    void_rect       = %s" % _r(_call("vertical_void_rect", [rect, dir, degrees])))
				for rise_m in [2.7, 3.2]:
					out.append("    slope(%.1f)      = %.6f" % [rise_m, _slope(rect, dir, degrees, rise_m)])
			out.append("  direction_label   = %s" % _call("direction_label", [dir]))
			out.append("  run_dir_from_drag = %s" % _v(_call("run_direction_from_drag", [rect.position, rect.end, rect])))

	for room in [
		{"kind": "escalera"},
		{"kind": "generic", "name": "Escalera PB"},
		{"kind": "generic", "name": "Salon"},
		{"kind": "stairs"},
		{"stair_turn_mode": "straight"},
		{"stair_turn_degrees": 180.0},
		{"stair_run_direction_m": {"x": -1.0, "y": 0.2}},
		{},
	]:
		out.append("--- room %s" % JSON.stringify(room))
		out.append("  is_stair_room     = %s" % _call("is_stair_room", [room]))
		out.append("  turn_mode_for_room= %s" % _call("turn_mode_for_room", [room]))
		out.append("  run_direction     = %s" % _v(_call("run_direction_for_room", [room])))

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
		print("[probe_stairs] %d lineas (%s) -> %s" % [out.size(), "editor" if _ask_editor else "modulo", _out_path])
	quit(0)
	return true


## El editor las tiene con guion bajo y con otros nombres; el modulo, sin.
const EDITOR_NAMES: Dictionary = {
	"normalized_turn_mode": "_normalized_stair_turn_mode",
	"turn_mode_label": "_stair_turn_mode_label",
	"turn_mode_from_degrees": "_stair_turn_mode_from_degrees",
	"direction_from_rotation": "_stair_direction_from_rotation",
	"long_span_m": "_stair_long_span_m",
	"cross_span_m": "_stair_cross_span_m",
	"ramp_width_m": "_stair_ramp_width_m",
	"landing_depth_m": "_stair_landing_depth_m",
	"can_use_180_landing": "_stair_can_use_180_landing",
	"turn_degrees_for_mode": "_stair_turn_degrees_for_mode",
	"effective_run_m": "_stair_effective_run_m",
	"vertical_void_rect": "_stair_vertical_void_rect",
	"direction_label": "_stair_direction_label",
	"run_direction_from_drag": "_stair_run_direction_from_drag",
	"is_stair_room": "_is_stair_room",
	"turn_mode_for_room": "_stair_turn_mode_for_room",
	"run_direction_for_room": "_room_stair_run_direction",
}


func _call(name: String, args: Array) -> Variant:
	if _ask_editor:
		return _editor.callv(String(EDITOR_NAMES[name]), args)
	return _module.callv(name, args)


## La pendiente es el unico caso donde la firma cambia a proposito: el editor la
## pedia con (room_id, room, rect) y buscaba la altura de la planta el solo; el
## modulo la recibe ya calculada, porque leer plantas no es geometria.
##
## Para que las dos den lo mismo, al editor se le monta un escenario de dos
## plantas separadas justo por la altura que se quiere probar.
func _slope(rect: Rect2, dir: Vector2, turn_degrees: float, rise_m: float) -> float:
	if _ask_editor:
		var room: Dictionary = {
			"stair_turn_degrees": turn_degrees,
			"stair_run_direction_m": {"x": dir.x, "y": dir.y},
			"floor_level_z_m": 0.0
		}
		_editor.editor_data = {
			"floors": [{"name": "PB", "level_m": 0.0}, {"name": "P1", "level_m": rise_m}],
			"rooms_data": [], "room_rect_m": {}, "openings_data": [],
			"detectors": [], "victims": [], "exterior_walls": [], "player_start": {}
		}
		return _editor._stair_slope_angle_deg(-1, room, rect)
	return _module.slope_angle_deg(rect, dir, turn_degrees, rise_m)


func _v(value: Vector2) -> String:
	return "(%.6f, %.6f)" % [value.x, value.y]


func _r(value: Rect2) -> String:
	return "(%.6f, %.6f, %.6f, %.6f)" % [value.position.x, value.position.y, value.size.x, value.size.y]

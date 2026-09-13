extends SceneTree
## Sonda: la tabla de la geometria del plano del editor.
##
## Misma idea que tools/probe_stair_geometry.gd, y por lo mismo: estas funciones
## las comparten el dibujo, los clics y el panel de propiedades, asi que moverlas
## toca las tres cosas a la vez. Una tabla de entradas, seis decimales, y diff.
##
## El mismo fichero pregunta a los dos lados: `editor` llama a los metodos del
## editor, `modulo` a las estaticas de editor/PlanGeometry.gd.
##
##   godot --headless --path . --script res://tools/probe_plan_geometry.gd -- <salida.txt> [editor|modulo]

const PlanGeometryScript = preload("res://editor/PlanGeometry.gd")

const RECTS: Array[Rect2] = [
	Rect2(0.0, 0.0, 4.0, 3.0),
	Rect2(-2.5, 1.25, 6.0, 2.0),
	Rect2(0.0, 0.0, 0.6, 0.6),
]
const SIZES: Array[Vector2] = [Vector2(1.4, 0.9), Vector2(0.4, 2.2), Vector2(3.0, 3.0)]
const ANGLES: Array[float] = [0.0, 15.0, 45.0, 90.0, 179.0, -90.0, -37.5, 360.0, 405.0]
const POINTS: Array[Vector2] = [Vector2(0.0, 0.0), Vector2(2.0, 1.5), Vector2(-1.0, 4.0), Vector2(3.9, 2.9)]
const WALLS: Array[String] = ["top", "bottom", "left", "right", "north", "vertical"]

var _module: RefCounted = PlanGeometryScript.new()
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

	for angle in ANGLES:
		out.append("clean_object_rotation_deg(%.1f) = %.6f" % [angle, _clean_rotation(angle)])
	for a in POINTS:
		for b in POINTS:
			out.append("normalized_rect(%s, %s) = %s" % [_v(a), _v(b), _r(_call("normalized_rect", [a, b]))])
	for point in POINTS:
		out.append("distance_to_segment(%s) = %.6f" % [
			_v(point), _call("distance_to_segment", [point, Vector2(0.0, 0.0), Vector2(4.0, 0.0)])
		])

	for rect in RECTS:
		for wall in WALLS:
			out.append("wall_length(%s, %s) = %.6f" % [_r(rect), wall, _call("wall_length", [rect, wall])])
		for angle in ANGLES:
			out.append("--- rect %s ang %.1f" % [_r(rect), angle])
			var points: PackedVector2Array = _call("rotated_rect_points_m", [rect, angle])
			var joined: PackedStringArray = PackedStringArray()
			for p in points:
				joined.append(_v(p))
			out.append("  rotated_points = %s" % " ".join(joined))
			for point in POINTS:
				out.append("  has_point(%s) = %s" % [_v(point), _call("rotated_rect_has_point", [rect, angle, point])])
			for size_m in SIZES:
				for local in [Vector2(0.0, 0.0), Vector2(0.5, 0.4), Vector2(-1.0, 2.5)]:
					out.append("  size %s local %s" % [_v(size_m), _v(local)])
					out.append("    visual_min   = %s" % _v(_call("object_visual_min_from_local_pos", [size_m, local, angle])))
					out.append("    local_again  = %s" % _v(_call("object_local_pos_from_visual_min", [size_m, local, angle])))
					out.append("    clamp        = %s" % _v(_call("clamp_object_local_pos", [rect, size_m, local])))
					out.append("    clamp_rot    = %s" % _v(_call("clamp_object_local_pos_for_rotation", [rect, size_m, local, angle])))
					var obj: Dictionary = {
						"size_m": {"x": size_m.x, "y": size_m.y},
						"position_m": {"x": local.x, "y": local.y},
						"rotation_deg": angle
					}
					out.append("    obj_size     = %s" % _v(_call("object_size_m", [obj])))
					out.append("    obj_center   = %s" % _v(_call("object_world_center", [rect, obj])))
					var corners: PackedVector2Array = _call("object_corner_points_m", [rect, obj])
					var corner_text: PackedStringArray = PackedStringArray()
					for c in corners:
						corner_text.append(_v(c))
					out.append("    obj_corners  = %s" % " ".join(corner_text))

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
		print("[probe_plan_geom] %d lineas (%s) -> %s" % [out.size(), "editor" if _ask_editor else "modulo", _out_path])
	quit(0)
	return true


func _call(name: String, args: Array) -> Variant:
	if _ask_editor:
		return _editor.callv("_" + name, args)
	return _module.callv(name, args)


## El umbral de encaje a los ejes es @export del editor; el modulo lo recibe.
func _clean_rotation(angle: float) -> float:
	if _ask_editor:
		return _editor._clean_object_rotation_deg(angle)
	return _module.clean_object_rotation_deg(angle, 5.0)


func _v(value: Vector2) -> String:
	return "(%.6f, %.6f)" % [value.x, value.y]


func _r(value: Rect2) -> String:
	return "(%.6f, %.6f, %.6f, %.6f)" % [value.position.x, value.position.y, value.size.x, value.size.y]

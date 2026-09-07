extends SceneTree
## Sonda: fotos del plano del editor, una por situacion de dibujo.
##
## El dibujo no se puede volcar a texto como los mandos: hay que mirarlo. Y para
## poder mover `_draw_*` sin fiarse de la vista, hay que poder comparar dos fotos
## exactas. Esta sonda pone la camara y el zoom a mano -nada de raton-, monta
## siempre el mismo escenario y guarda un PNG por situacion:
##
##   1. el plano quieto, sin seleccion
##   2. una sala seleccionada, con sus tiradores
##   3. un objeto seleccionado
##   4. una apertura seleccionada
##   5. arrastrando una sala nueva
##   6. arrastrando una escalera (guias, hueco vertical y los carteles)
##   7. arrastrando un pasillo en L
##   8. arrastrando un muro exterior
##   9. la planta de arriba, con el fantasma de la de abajo
##
## IMPORTANTE: con ventana real, como tools/capture_editor_ui.gd. En --headless
## no hay rasterizado y las fotos salen vacias.
##
##   <godot> --path . --resolution 1280x720 --script res://tools/capture_editor_plan.gd -- <carpeta>

const SETTLE_FRAMES: int = 30
## Camara fija: el mismo encuadre en las dos fotos, o la comparacion no vale.
const CAMERA_POS := Vector2(320.0, 190.0)
const CAMERA_ZOOM: float = 0.85

var _editor: Node = null
var _frames: int = 0
var _out_dir: String = "."
var _poses: Array[Dictionary] = []
var _pose_index: int = -1
var _wait: int = 0


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		_out_dir = args[0]
	var packed := load("res://scenes/ScenarioEditorScene.tscn") as PackedScene
	_editor = packed.instantiate()
	root.add_child(_editor)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < SETTLE_FRAMES:
		return false
	if _pose_index < 0:
		_setup()
		_pose_index = 0
		_apply_pose(_poses[0])
		_wait = 0
		return false
	# La pose se vuelve a poner en CADA fotograma, no solo al empezar: mientras
	# hay un arrastre en curso, cualquier movimiento del raton de verdad -y el
	# sistema manda uno al abrirse la ventana- reescribe drag_current_m con la
	# posicion real del cursor, y la foto sale distinta segun donde estuviera.
	_apply_pose(_poses[_pose_index])
	_wait += 1
	if _wait < 12:
		return false
	_shoot(_poses[_pose_index])
	_pose_index += 1
	if _pose_index >= _poses.size():
		quit(0)
		return true
	_apply_pose(_poses[_pose_index])
	_wait = 0
	return false


func _setup() -> void:
	# La ayuda contextual saca un cartel donde reposa el raton, y en una foto sin
	# manos eso depende del milisegundo: apagarla es lo que hace comparables dos
	# capturas del mismo plano.
	_editor._hover_help_enabled = false
	_editor._reset_hover_help()
	_editor.editor_data = _scenario()
	_editor.current_floor_index = 0
	var camera: Camera2D = _editor.get_node_or_null("World/Camera2D")
	if camera != null:
		camera.global_position = CAMERA_POS
		camera.zoom = Vector2(CAMERA_ZOOM, CAMERA_ZOOM)
	_poses = [
		{"name": "01_plano", "tool": 0},
		{"name": "02_sala", "tool": 0, "room": 7},
		{"name": "03_objeto", "tool": 0, "object": [7, 0]},
		{"name": "04_apertura", "tool": 0, "opening": 0},
		{"name": "05_arrastre_sala", "tool": 2, "drag_room": [Vector2(1.0, 5.5), Vector2(5.4, 8.2)]},
		{"name": "06_arrastre_escalera", "tool": 4, "drag_room": [Vector2(7.0, 1.0), Vector2(10.2, 5.4)]},
		{"name": "07_arrastre_pasillo", "tool": 3, "drag_room": [Vector2(0.5, 4.0), Vector2(6.0, 4.0)]},
		{"name": "08_arrastre_muro", "tool": 1, "drag_wall": [Vector2(-0.4, 6.4), Vector2(7.6, 6.4)]},
		{"name": "09_planta_alta", "tool": 0, "floor": 1},
		{"name": "10_3d_en_vivo", "tool": 0, "room": 7, "preview_3d": true},
	]


## Cada situacion se monta tocando el estado del editor a mano: es la unica forma
## de fotografiar un arrastre sin raton.
func _apply_pose(pose: Dictionary) -> void:
	_editor.current_floor_index = int(pose.get("floor", 0))
	_editor._clear_selection()
	_editor.drag = 0
	_editor.current_tool = int(pose.get("tool", 0))
	if pose.has("room"):
		_editor._select_room(int(pose["room"]))
	if pose.has("object"):
		var obj: Array = pose["object"]
		_editor._select_object(int(obj[0]), int(obj[1]))
	if pose.has("opening"):
		_editor._select_opening(int(pose["opening"]))
	# 0 NONE, 1 EXTERIOR_WALL, 2 ROOM_RECT: el enum Drag del editor.
	if pose.has("drag_room"):
		var drag: Array = pose["drag_room"]
		_editor.drag = 2
		_editor.drag_start_m = drag[0]
		_editor.drag_current_m = drag[1]
	# El 3D en vivo: se enciende solo en la pose que lo pide.
	var wants_preview: bool = bool(pose.get("preview_3d", false))
	if _editor._preview_3d_enabled != wants_preview:
		_editor._set_preview_3d_enabled(wants_preview)
	if pose.has("drag_wall"):
		var wall: Array = pose["drag_wall"]
		_editor.drag = 1
		_editor.drag_start_m = wall[0]
		_editor.drag_current_m = wall[1]
	_editor.queue_redraw()


func _shoot(pose: Dictionary) -> void:
	var image: Image = root.get_texture().get_image()
	if image == null:
		print("[capture_plan] sin imagen: ¿se ha lanzado en --headless?")
		quit(1)
		return
	var path: String = "%s/%s.png" % [_out_dir, String(pose.get("name", "pose"))]
	var error: int = image.save_png(path)
	print("[capture_plan] %s (error=%d)" % [path, error])


## Un piso pequeño pero con una de cada cosa que el editor dibuja: salas, muro
## exterior, puerta, ventana, hueco vertical de escalera, objeto encendido,
## detector, victima e inicio de jugador. Y una planta alta, para el fantasma.
func _scenario() -> Dictionary:
	return {
		"floors": [{"name": "PB", "level_m": 0.0}, {"name": "P1", "level_m": 2.7}],
		"exterior_walls": [
			{"a": {"x": -0.4, "y": -0.4}, "b": {"x": 9.4, "y": -0.4}, "thickness_m": 0.24},
			{"a": {"x": 9.4, "y": -0.4}, "b": {"x": 9.4, "y": 7.4}, "thickness_m": 0.24}
		],
		"room_rect_m": {
			"7": {"x": 0.0, "y": 0.0, "w": 4.2, "h": 3.4},
			"8": {"x": 4.2, "y": 0.0, "w": 2.6, "h": 3.4},
			"9": {"x": 0.0, "y": 3.4, "w": 6.8, "h": 2.2},
			"10": {"x": 0.0, "y": 0.0, "w": 4.2, "h": 3.4}
		},
		"rooms_data": [
			{
				"id": 7, "name": "Salón", "kind": "generic", "rotation_deg": 0.0,
				"height_m": 2.7, "floor_level_z_m": 0.0,
				"fuel_energy_MJ": 420.0, "max_hrr_kw": 1600.0,
				"fuel_objects": [
					{
						"id": "obj_001", "room_id": 7, "name": "sofa", "kind": "sofa",
						"position_m": {"x": 0.6, "y": 0.5}, "size_m": {"x": 2.0, "y": 0.9},
						"rotation_deg": 0.0, "elevation_m": 0.0,
						"fuel_energy_MJ": 260.0, "max_hrr_kw": 900.0,
						"is_primary_ignition_source": true
					},
					{
						"id": "obj_002", "room_id": 7, "name": "mesa", "kind": "mesa",
						"position_m": {"x": 2.9, "y": 1.9}, "size_m": {"x": 1.1, "y": 0.7},
						"rotation_deg": 35.0, "elevation_m": 0.0,
						"fuel_energy_MJ": 90.0, "max_hrr_kw": 300.0
					}
				]
			},
			{
				"id": 8, "name": "Escalera PB", "kind": "escalera", "rotation_deg": 0.0,
				"height_m": 2.7, "floor_level_z_m": 0.0,
				"stair_has_walls": false, "stair_has_railings": true,
				"stair_turn_degrees": 180.0, "stair_turn_mode": "switchback",
				"stair_run_direction_m": {"x": 0.0, "y": 1.0},
				"fuel_objects": []
			},
			{
				"id": 9, "name": "Pasillo", "kind": "pasillo", "rotation_deg": 0.0,
				"height_m": 2.7, "floor_level_z_m": 0.0, "fuel_objects": []
			},
			{
				"id": 10, "name": "Dormitorio P1", "kind": "generic", "rotation_deg": 0.0,
				"height_m": 2.55, "floor_level_z_m": 2.7, "fuel_objects": []
			}
		],
		"openings_data": [
			{
				"a": 7, "b": 9, "type": "door", "wall": "bottom", "offset_m": 1.4,
				"offset_is_fraction": false, "width_m": 0.9, "height_m": 2.03,
				"sill_m": 0.0, "open_fraction": 1.0,
				"swing_direction": "in", "hinge_side": "left"
			},
			{
				"a": 7, "b": -1, "type": "window", "wall": "top", "offset_m": 1.2,
				"offset_is_fraction": false, "width_m": 1.2, "height_m": 1.3,
				"sill_m": 0.9, "open_fraction": 0.0
			},
			{
				"a": 8, "b": 9, "type": "hole", "wall": "bottom", "offset_m": 0.8,
				"offset_is_fraction": false, "width_m": 1.0, "height_m": 2.1,
				"sill_m": 0.0, "open_fraction": 1.0
			}
		],
		"detectors": [{"id": "det_001", "room_id": 9, "type": "smoke", "threshold": 0.025, "x_m": 3.0, "y_m": 1.1}],
		"victims": [{"id": "vic_001", "room_id": 7, "name": "Víctima 1", "x_m": 3.4, "y_m": 0.6, "height_m": 0.9}],
		"player_start": {"room_id": 9, "x_m": 5.6, "y_m": 1.1},
		"ignition_room_id": 7
	}

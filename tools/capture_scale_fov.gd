extends Node
## Sensacion de tamano en primera persona: la misma sala, desde el mismo sitio,
## con distintos campos de vision.
##
## Sale de una observacion del usuario -"un salon de 20 m2 deberia verse mas
## grande de lo que parece"- y sirve para decidir un numero mirandolo, que es
## la unica forma de decidirlo: la escala es correcta en metros y aun asi la
## sensacion puede no serlo.
##
## El salon del piso patron mide 6,0 x 4,0 = **24 m2** y tiene 2,62 m de altura
## libre. Se fotografia con el mobiliario puesto, que es lo que da la escala:
## un sofa mide lo que mide y el ojo lo sabe.
##
## IMPORTANTE: con ventana real. En --headless no hay render.
##
##   <godot> --path . --resolution 1600x900 tools/capture_scale_fov.tscn -- --out=<dir>

const BuildingModelScript := preload("res://sim/BuildingModel.gd")
const FirstPersonControllerScript := preload("res://view/fp/FirstPersonController.gd")

@export_group("Salida")
@export var output_dir: String = ""

## Campos de vision HORIZONTALES a comparar. 107 es el que habia clavado en el
## codigo (75 vertical a 16:9); 90 es el estandar de primera persona; 75 y 65
## se acercan a la perspectiva natural de un ojo mirando una pantalla.
@export var fov_h_deg_list: Array[float] = [107.0, 90.0, 75.0, 65.0]

@export_group("Vistas")
## Tres encuadres que dicen cosas distintas: la sala entera desde una esquina,
## una pared de frente a distancia de conversacion, y el pasillo hacia la otra
## habitacion.
@export var fp_views: Array[Dictionary] = [
	{"nombre": "salon_desde_esquina", "desde_m": Vector2(0.9, 0.9), "mira_m": Vector2(5.4, 3.4), "cabeceo_rad": -0.04},
	{"nombre": "salon_pared_de_frente", "desde_m": Vector2(3.0, 3.2), "mira_m": Vector2(3.0, 0.0), "cabeceo_rad": 0.0},
	{"nombre": "salon_hacia_el_dormitorio", "desde_m": Vector2(1.6, 2.0), "mira_m": Vector2(6.0, 1.7), "cabeceo_rad": 0.0},
]
@export var plan_center_m: Vector2 = Vector2(5.0, 2.0)

@export_group("Reposo")
@export_range(1, 400, 1) var settle_frames_state: int = 70
@export_range(1, 120, 1) var settle_frames_view: int = 12

@export_group("Iluminacion del piso patron")
@export var fp_room_ceiling_light_energy: float = 0.58
@export var fp_landing_light_energy: float = 1.05
@export var fp_landing_light_range_m: float = 4.2
@export var fp_window_light_energy: float = 0.95

var _out_dir: String = ""
var _written: int = 0
var _failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var default_dir: String = output_dir.strip_edges()
	if default_dir == "":
		default_dir = ProjectSettings.globalize_path("res://.test_tmp/scale_fov")
	_out_dir = _cmdline_value("--out=", default_dir)
	DirAccess.make_dir_recursive_absolute(_out_dir)
	print("[capture] destino=%s display=%s" % [_out_dir, DisplayServer.get_name()])
	if DisplayServer.get_name() == "headless":
		push_error("capture_scale_fov necesita ventana real: en --headless no hay render.")
		get_tree().quit(1)
		return

	var building: BuildingModel = BuildingModelScript.new()
	if not building.load_template_data(_make_template()):
		_fail("la plantilla patron fue rechazada por BuildingModel")
		_finish()
		return

	var host := Node3D.new()
	host.name = "CaptureScaleWorld"
	add_child(host)
	var fp: FirstPersonController = FirstPersonControllerScript.new()
	fp.name = "CaptureScaleFP"
	fp.room_ceiling_light_energy = fp_room_ceiling_light_energy
	fp.landing_light_energy = fp_landing_light_energy
	fp.landing_light_range_m = fp_landing_light_range_m
	fp.window_light_energy = fp_window_light_energy
	host.add_child(fp)
	await get_tree().process_frame
	fp.setup(building)
	await get_tree().physics_frame
	fp.set_active(true)
	fp.set_state(_make_clean_state())
	await _settle(settle_frames_state)

	for fov_h in fov_h_deg_list:
		fp.fp_camera_fov_h_deg = float(fov_h)
		await get_tree().process_frame
		for view in fp_views:
			await _place_fp(
				fp,
				Vector2(view.get("desde_m", Vector2.ZERO)),
				Vector2(view.get("mira_m", Vector2.ZERO)),
				float(view.get("cabeceo_rad", 0.0))
			)
			await _capture("fov%03d_%s" % [int(round(float(fov_h))), String(view.get("nombre", "vista"))])

	fp.set_active(false)
	host.free()
	building.free()
	_finish()


func _place_fp(fp: Node3D, from_plan: Vector2, look_plan: Vector2, pitch: float) -> void:
	var target := Vector3(from_plan.x - plan_center_m.x, 0.05, from_plan.y - plan_center_m.y)
	var d: Vector2 = look_plan - from_plan
	var yaw: float = atan2(-d.x, -d.y)
	_pin_fp(fp, target, yaw, pitch)
	await _settle(settle_frames_view)
	_pin_fp(fp, target, yaw, pitch)
	await get_tree().process_frame


func _pin_fp(fp: Node3D, position: Vector3, yaw: float, pitch: float) -> void:
	fp.global_position = position
	fp.rotation.y = yaw
	if fp is CharacterBody3D:
		(fp as CharacterBody3D).velocity = Vector3.ZERO
	var cam := fp.get_node_or_null("FirstPersonCamera") as Camera3D
	if cam != null:
		cam.rotation.x = pitch
		cam.current = true


## El piso patron de `capture_visual_reference.gd`, con mobiliario: el salon de
## 6,0 x 4,0 m -24 m2- y el dormitorio de 4,0 x 4,0.
func _make_template() -> Dictionary:
	return {
		"version": 1,
		"building_type": "apartment",
		"apartment_floor_number": 2,
		"building_total_floors": 6,
		"outside_temp_c": 18.0,
		"outside_o2": 0.209,
		"stop_time_s": 0.0,
		"hvac_mode": "none",
		"hvac_data": {"exists": false, "on": false, "mode": "none"},
		"room_rect_m": {
			"0": {"x": 0.0, "y": 0.0, "w": 6.0, "h": 4.0},
			"1": {"x": 6.0, "y": 0.0, "w": 4.0, "h": 4.0}
		},
		"rooms_data": [
			{
				"id": 0, "name": "Salon", "kind": "salon", "height_m": 2.62,
				"floor_level_z_m": 0.0, "fuel_energy_MJ": 620.0, "max_hrr_kw": 1400.0,
				"fuel_objects": []
			},
			{
				"id": 1, "name": "Dormitorio", "kind": "dormitorio", "height_m": 2.62,
				"floor_level_z_m": 0.0, "fuel_energy_MJ": 240.0, "max_hrr_kw": 500.0,
				"fuel_objects": []
			}
		],
		"openings_data": [
			{"a": 0, "b": 1, "type": "door", "wall": "right", "offset_m": 1.6, "offset_is_fraction": false, "width_m": 0.92, "height_m": 2.05, "open_fraction": 1.0},
			{"a": 0, "b": -1, "type": "door", "wall": "bottom", "offset_m": 1.0, "offset_is_fraction": false, "width_m": 0.92, "height_m": 2.05, "open_fraction": 0.0},
			{"a": 0, "b": -1, "type": "window", "wall": "left", "offset_m": 2.0, "offset_is_fraction": false, "width_m": 1.30, "height_m": 1.20, "sill_m": 0.90, "open_fraction": 0.0},
			{"a": 1, "b": -1, "type": "window", "wall": "right", "offset_m": 2.0, "offset_is_fraction": false, "width_m": 1.30, "height_m": 1.20, "sill_m": 0.90, "open_fraction": 0.0}
		],
		"detectors": [],
		"victims": [],
		"exterior_walls": []
	}


func _make_clean_state() -> Dictionary:
	return {
		"0": _room_state(0, "Salon", "salon"),
		"1": _room_state(1, "Dormitorio", "dormitorio")
	}


func _room_state(room_id: int, name: String, kind: String) -> Dictionary:
	return {
		"id": room_id, "name": name, "kind": kind,
		"burning": false, "hrr_kw": 0.0,
		"temp_upper_c": 21.0, "temp_lower_c": 20.0,
		"o2": 0.209, "smoke_kg": 0.0,
		"visibility_m": 30.0, "layer_height_m": 2.62,
		"combustion_regime": ""
	}


func _capture(view_name: String) -> void:
	await RenderingServer.frame_post_draw
	var vp := get_viewport()
	if vp == null:
		_fail("%s: no hay viewport" % view_name)
		return
	var img: Image = vp.get_texture().get_image()
	if img == null:
		_fail("%s: get_image() devolvio null" % view_name)
		return
	var path: String = _out_dir.path_join("%s.png" % view_name)
	var err: Error = img.save_png(path)
	if err != OK:
		_fail("%s: error %d al guardar %s" % [view_name, err, path])
		return
	_written += 1
	print("[capture] %s (%dx%d)" % [path, img.get_width(), img.get_height()])


func _settle(frames: int) -> void:
	for _i in range(frames):
		await get_tree().process_frame


func _cmdline_value(prefix: String, fallback: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(prefix):
			return arg.substr(prefix.length())
	return fallback


func _fail(message: String) -> void:
	_failures.append(message)
	push_error("[capture] " + message)


func _finish() -> void:
	print("[capture] escritas %d vistas" % _written)
	get_tree().quit(0 if _failures.is_empty() else 1)

extends Node
## Capturas del balcon (N-1): lo unico que un guardarrail headless no dice es
## si se VE bien.
##
## Es el piso patron de `capture_visual_reference.gd` con la ventana del salon
## cambiada por una balconera, para que la comparacion con las capturas de
## referencia sea directa: mismo piso, misma luz, mismo encuadre, y lo unico
## que cambia es el hueco.
##
## Se saca cada vista con la puerta CERRADA y ABIERTA, porque son dos cosas
## distintas: cerrada se juzga el cristal, abierta se juzga la losa y el
## antepecho.
##
## IMPORTANTE: hay que ejecutarlo CON VENTANA REAL. En --headless no hay
## rasterizado y `RenderingServer.frame_post_draw` no dispara nunca.
##
##   <godot> --path . --resolution 1600x900 tools/capture_balcony.tscn -- --out=<dir>

const BuildingModelScript := preload("res://sim/BuildingModel.gd")
const FirstPersonControllerScript := preload("res://view/fp/FirstPersonController.gd")

@export_group("Salida")
@export var output_dir: String = ""
@export var output_label: String = ""

@export_group("Vistas")
## Mismo formato que en `capture_visual_reference.gd`: nombre, posicion en
## planta (m), punto al que se mira (m) y cabeceo en radianes.
@export var fp_views: Array[Dictionary] = [
	{"nombre": "salon_balconera", "desde_m": Vector2(3.6, 2.0), "mira_m": Vector2(0.0, 2.0), "cabeceo_rad": 0.0},
	{"nombre": "balconera_de_cerca", "desde_m": Vector2(1.7, 2.0), "mira_m": Vector2(0.0, 2.0), "cabeceo_rad": 0.0},
	{"nombre": "balcon_mirando_abajo", "desde_m": Vector2(1.1, 2.0), "mira_m": Vector2(0.0, 2.0), "cabeceo_rad": -0.55},
	{"nombre": "balcon_mirando_arriba", "desde_m": Vector2(1.1, 2.0), "mira_m": Vector2(0.0, 2.0), "cabeceo_rad": 0.42},
	{"nombre": "balcon_de_lado", "desde_m": Vector2(1.4, 3.4), "mira_m": Vector2(0.0, 1.6), "cabeceo_rad": 0.0},
	{"nombre": "balcon_desde_la_calle", "desde_m": Vector2(-5.0, 3.4), "mira_m": Vector2(0.0, 2.0), "cabeceo_rad": 0.20},
	{"nombre": "balcon_desde_la_calle_frente", "desde_m": Vector2(-4.2, 2.0), "mira_m": Vector2(0.0, 2.0), "cabeceo_rad": 0.28},
]
## El mobiliario tapa el hueco desde dentro y aqui lo que se juzga es el
## balcon. Se apaga en las vistas de interior; en la calle da igual.
@export var show_furniture: bool = false
## Centro del edificio patron en planta, para pasar de metros de plano a mundo.
@export var plan_center_m: Vector2 = Vector2(5.0, 2.0)

@export_group("El balcon que se retrata")
@export var balcony_width_m: float = 1.40
@export var balcony_door_height_m: float = 2.10
@export var balcony_depth_m: float = 1.20
@export var balcony_parapet_m: float = 1.10

@export_group("Altura del piso patron")
## La planta importa: desde la baja el balcon se ve contra la acera y desde la
## quinta contra la fachada de enfrente.
@export var apartment_floor_number: int = 2
@export var building_total_floors: int = 6

@export_group("Reposo")
@export_range(1, 400, 1) var settle_frames_state: int = 90
@export_range(1, 120, 1) var settle_frames_view: int = 12

@export_group("Iluminacion del piso patron")
## Mismos valores que scenes/SimulationScene.tscn.
@export var fp_room_ceiling_light_energy: float = 0.58
@export var fp_landing_light_energy: float = 1.05
@export var fp_landing_light_range_m: float = 4.2
@export var fp_window_light_energy: float = 0.95

var _out_dir: String = ""
var _label: String = ""
var _written: int = 0
var _failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var default_dir: String = output_dir.strip_edges()
	if default_dir == "":
		default_dir = ProjectSettings.globalize_path("res://.test_tmp/balcony_capture")
	_out_dir = _cmdline_value("--out=", default_dir)
	_label = _cmdline_value("--label=", output_label)
	var floor_arg: String = _cmdline_value("--floor=", "")
	if floor_arg != "":
		apartment_floor_number = int(floor_arg)
	DirAccess.make_dir_recursive_absolute(_out_dir)
	print("[capture] destino=%s display=%s" % [_out_dir, DisplayServer.get_name()])
	if DisplayServer.get_name() == "headless":
		push_error("capture_balcony necesita ventana real: en --headless no hay render.")
		get_tree().quit(1)
		return

	# Cerrada y abierta son dos edificios distintos a proposito: cambiar la
	# fraccion de apertura en caliente obliga a tocar el interior del
	# controlador, y aqui no hace falta.
	for pass_data in [["cerrada", 0.0], ["abierta", 1.0]]:
		await _capture_pass(String(pass_data[0]), float(pass_data[1]))
	_finish()


func _capture_pass(pass_name: String, open_fraction: float) -> void:
	var building: BuildingModel = BuildingModelScript.new()
	if not building.load_template_data(_make_template(open_fraction)):
		_fail("la plantilla con balconera fue rechazada por BuildingModel")
		building.free()
		return

	var host := Node3D.new()
	host.name = "CaptureBalconyWorld_%s" % pass_name
	add_child(host)
	var fp: FirstPersonController = FirstPersonControllerScript.new()
	fp.name = "CaptureBalconyFP"
	fp.room_ceiling_light_energy = fp_room_ceiling_light_energy
	fp.landing_light_energy = fp_landing_light_energy
	fp.landing_light_range_m = fp_landing_light_range_m
	fp.window_light_energy = fp_window_light_energy
	fp.show_fp_furniture = show_furniture
	host.add_child(fp)
	await get_tree().process_frame
	fp.setup(building)
	await get_tree().physics_frame
	fp.set_active(true)
	fp.set_state(_make_clean_state())
	await _settle(settle_frames_state)

	for view in fp_views:
		await _place_fp(
			fp,
			Vector2(view.get("desde_m", Vector2.ZERO)),
			Vector2(view.get("mira_m", Vector2.ZERO)),
			float(view.get("cabeceo_rad", 0.0))
		)
		await _capture("balcon_%s_%s" % [pass_name, String(view.get("nombre", "vista"))])

	fp.set_active(false)
	host.free()
	building.free()


func _place_fp(fp: Node3D, from_plan: Vector2, look_plan: Vector2, pitch: float) -> void:
	var target := Vector3(from_plan.x - plan_center_m.x, 0.05, from_plan.y - plan_center_m.y)
	var d: Vector2 = look_plan - from_plan
	var yaw: float = atan2(-d.x, -d.y)
	_pin_fp(fp, target, yaw, pitch)
	await _settle(settle_frames_view)
	# El jugador es un CharacterBody3D con gravedad: durante el reposo se
	# desliza y cae. Sin volver a fijarlo, dos ejecuciones del mismo codigo dan
	# encuadres distintos.
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


## El piso patron de `capture_visual_reference.gd`, con la ventana del salon
## -pared izquierda, la fachada a la calle- cambiada por una balconera.
func _make_template(open_fraction: float) -> Dictionary:
	return {
		"version": 1,
		"building_type": "apartment",
		"apartment_floor_number": apartment_floor_number,
		"building_total_floors": building_total_floors,
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
			{"a": 0, "b": 1, "type": "door", "wall": "right", "offset_m": 1.6, "width_m": 0.92, "height_m": 2.05, "open_fraction": 1.0},
			{"a": 0, "b": -1, "type": "door", "wall": "bottom", "offset_m": 1.0, "width_m": 0.92, "height_m": 2.05, "open_fraction": 1.0},
			{
				# offset_is_fraction EXPLICITO: `OpeningModel` lo da por cierto si
				# falta, asi que un 2.0 se lee como fraccion, se recorta a 1.0 y
				# el hueco se va al extremo del muro. Es la trampa que descoloco
				# las primeras capturas.
				"a": 0, "b": -1, "type": "door", "wall": "left",
				"offset_m": 2.0, "offset_is_fraction": false,
				"width_m": balcony_width_m, "height_m": balcony_door_height_m, "sill_m": 0.0,
				"open_fraction": open_fraction,
				"has_balcony": true,
				"balcony_width_m": 0.0,
				"balcony_depth_m": balcony_depth_m,
				"balcony_parapet_m": balcony_parapet_m
			},
			{"a": 1, "b": -1, "type": "window", "wall": "right", "offset_m": 1.4, "width_m": 1.30, "height_m": 1.20, "sill_m": 0.90, "open_fraction": 0.0}
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
		"id": room_id,
		"name": name,
		"kind": kind,
		"burning": false,
		"hrr_kw": 0.0,
		"temp_upper_c": 21.0,
		"temp_lower_c": 20.0,
		"o2": 0.209,
		"smoke_kg": 0.0,
		"visibility_m": 30.0,
		"layer_height_m": 2.62,
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
	var file_name: String = view_name if _label == "" else "%s__%s" % [_label, view_name]
	var path: String = _out_dir.path_join("%s.png" % file_name)
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
	var expected: int = fp_views.size() * 2
	print("[capture] escritas %d de %d vistas" % [_written, expected])
	if _failures.is_empty() and _written == expected:
		get_tree().quit(0)
		return
	get_tree().quit(1)

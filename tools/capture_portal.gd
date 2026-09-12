extends Node
## Capturas del PORTAL: el rellano y la caja de escalera como recinto dibujado.
##
## Lo que hay que juzgar en estas fotos:
##
##  - que al salir por la puerta del piso se este en un RELLANO: suelo, techo,
##    paredes y luz, no una losa en el vacio,
##  - que la escalera suba y baje por el ojo, y que por el se vean las plantas,
##  - que la caja este CERRADA por arriba: en el ultimo rellano hay techo, no
##    cielo, porque asi se ha modelado para el motor,
##  - y que abajo, en el zaguan, la puerta de la calle sea eso.
##
## El escenario es el que produce la herramienta del editor: se dibuja con ella,
## no se escribe a mano, para retratar lo mismo que vera quien la use.
##
## IMPORTANTE: hay que ejecutarlo CON VENTANA REAL. En --headless no hay
## rasterizado y `RenderingServer.frame_post_draw` no dispara nunca.
##
##   <godot> --path . --resolution 1600x900 tools/capture_portal.tscn -- --out=<dir>

const BuildingModelScript := preload("res://sim/BuildingModel.gd")
const FirstPersonControllerScript := preload("res://view/fp/FirstPersonController.gd")
const Serializer := preload("res://editor/ScenarioSerializer.gd")

const TOOL_PORTAL: int = 15
const PLANTA_H: float = 2.9
const PLANTAS: int = 3

@export_group("Salida")
@export var output_dir: String = ""

@export_group("Vistas")
## Nombre, planta, posicion en planta (m), punto al que se mira (m) y cabeceo
## (rad). El portal ocupa x 5..9, y 0..3: rellano en x 5..6,3 junto a la puerta
## del piso (pared derecha de la vivienda, y = 2) y escalera en x 6,3..9, subiendo
## hacia +x. La vivienda ocupa x 0..5, y 0..4.
@export var fp_views: Array[Dictionary] = [
	{"nombre": "piso_mira_puerta", "planta": 1, "desde_m": Vector2(3.4, 2.0), "mira_m": Vector2(6.0, 2.0), "cabeceo_rad": 0.0},
	{"nombre": "rellano_a_lo_largo", "planta": 1, "desde_m": Vector2(5.5, 2.8), "mira_m": Vector2(5.8, 0.0), "cabeceo_rad": 0.0},
	{"nombre": "rellano_escalera", "planta": 1, "desde_m": Vector2(5.3, 1.5), "mira_m": Vector2(8.5, 1.5), "cabeceo_rad": 0.05},
	{"nombre": "ojo_arriba", "planta": 1, "desde_m": Vector2(7.6, 1.5), "mira_m": Vector2(8.5, 1.5), "cabeceo_rad": 1.20},
	{"nombre": "ojo_abajo", "planta": 1, "desde_m": Vector2(7.6, 1.5), "mira_m": Vector2(8.5, 1.5), "cabeceo_rad": -1.20},
	{"nombre": "rellano_vuelta_al_piso", "planta": 1, "desde_m": Vector2(6.1, 2.4), "mira_m": Vector2(4.0, 2.0), "cabeceo_rad": 0.0},
	{"nombre": "ultimo_techo", "planta": 2, "desde_m": Vector2(5.6, 1.5), "mira_m": Vector2(6.5, 1.5), "cabeceo_rad": 1.20},
	{"nombre": "ultimo_al_frente", "planta": 2, "desde_m": Vector2(5.3, 1.5), "mira_m": Vector2(8.5, 1.5), "cabeceo_rad": 0.10},
	{"nombre": "zaguan_calle", "planta": 0, "desde_m": Vector2(5.6, 2.6), "mira_m": Vector2(5.65, -0.5), "cabeceo_rad": 0.0},
]
@export var show_furniture: bool = false

@export_group("Reposo")
@export_range(1, 400, 1) var settle_frames_state: int = 90
@export_range(1, 120, 1) var settle_frames_view: int = 12

var _out_dir: String = ""
var _written: int = 0
var _failures: Array[String] = []
var _portal_ids: Array[int] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var default_dir: String = output_dir.strip_edges()
	if default_dir == "":
		default_dir = ProjectSettings.globalize_path("res://.test_tmp/portal_capture")
	_out_dir = _cmdline_value("--out=", default_dir)
	DirAccess.make_dir_recursive_absolute(_out_dir)
	print("[capture] destino=%s display=%s" % [_out_dir, DisplayServer.get_name()])
	if DisplayServer.get_name() == "headless":
		push_error("capture_portal necesita ventana real: en --headless no hay render.")
		get_tree().quit(1)
		return

	var template: Dictionary = await _template_from_tool()
	var building: BuildingModel = BuildingModelScript.new()
	if template.is_empty() or not building.load_template_data(template):
		_fail("el portal dibujado fue rechazado por BuildingModel")
		building.free()
		_finish()
		return
	for rid in building.get_rooms().keys():
		if String(building.get_room(rid).name).begins_with("Portal"):
			_portal_ids.append(int(rid))

	var host := Node3D.new()
	host.name = "CapturePortalWorld"
	add_child(host)
	var fp: FirstPersonController = FirstPersonControllerScript.new()
	fp.name = "CapturePortalFP"
	fp.show_fp_furniture = show_furniture
	host.add_child(fp)
	await get_tree().process_frame
	fp.setup(building)
	await get_tree().physics_frame
	fp.set_active(true)
	# La caja de escalera tiene ojo: sin congelar la fisica la camara cae por el
	# entre el encuadre y el disparo, como pasaba en el patio.
	fp.set_physics_process(false)

	for caso in ["limpio", "caja_con_humo"]:
		fp.set_state(_make_state(building, caso == "caja_con_humo"))
		await _settle(settle_frames_state)
		for view in fp_views:
			await _place_fp(
				fp,
				int(view.get("planta", 1)),
				Vector2(view.get("desde_m", Vector2.ZERO)),
				Vector2(view.get("mira_m", Vector2.ZERO)),
				float(view.get("cabeceo_rad", 0.0))
			)
			await _capture("portal_%s_%s" % [caso, String(view.get("nombre", "vista"))])

	fp.set_active(false)
	host.free()
	building.free()
	_finish()


## El mismo edificio que se simulo: tres plantas con una vivienda, su puerta en
## la pared derecha y una ventana a la calle; el portal se DIBUJA con la
## herramienta del editor y se exporta por el camino real.
func _template_from_tool() -> Dictionary:
	var editor: Node = (load("res://scenes/ScenarioEditorScene.tscn") as PackedScene).instantiate()
	add_child(editor)
	await get_tree().process_frame
	await get_tree().process_frame
	var rects: Dictionary = {}
	var rooms: Array = []
	var ops: Array = []
	for p in range(PLANTAS):
		var id: int = p + 1
		rects[str(id)] = {"x": 0.0, "y": 0.0, "w": 5.0, "h": 4.0}
		rooms.append({"id": id, "name": "Vivienda P%d" % p, "kind": "salon", "rotation_deg": 0.0,
			"height_m": 2.5, "floor_level_z_m": PLANTA_H * p, "fuel_energy_MJ": 800.0,
			"max_hrr_kw": 900.0, "fuel_objects": []})
		ops.append({"a": id, "b": -1, "type": "door", "wall": "right", "offset_m": 0.5,
			"offset_is_fraction": true, "width_m": 0.92, "height_m": 2.05, "sill_m": 0.0,
			"open_fraction": 1.0})
		ops.append({"a": id, "b": -1, "type": "window", "wall": "left", "offset_m": 0.5,
			"offset_is_fraction": true, "width_m": 1.30, "height_m": 1.10, "sill_m": 0.90,
			"open_fraction": 0.0})
	editor.adopt_scenario_data({
		"building_type": "apartment", "apartment_floor_number": 1, "building_total_floors": PLANTAS,
		"floors": [{"name": "R", "level_m": 0.0}, {"name": "R+1", "level_m": PLANTA_H}, {"name": "R+2", "level_m": PLANTA_H * 2.0}],
		"exterior_walls": [], "room_rect_m": rects, "rooms_data": rooms, "openings_data": ops,
		"detectors": [], "victims": [], "player_start": {"room_id": 2, "x_m": 2.0, "y_m": 2.0},
		"ignition_room_id": 1,
	}, 0)
	editor.current_tool = TOOL_PORTAL
	editor._handle_press(Vector2(5.0, 0.0))
	editor._handle_release(Vector2(9.0, 3.0))
	var template: Dictionary = Serializer.to_runtime_template(editor.editor_data.duplicate(true))
	editor.queue_free()
	return template


func _place_fp(fp: FirstPersonController, planta: int, from_plan: Vector2, look_plan: Vector2, pitch: float) -> void:
	var nivel: float = float(planta) * PLANTA_H
	var target: Vector3 = fp._to_world(Vector3(from_plan.x, 0.05, from_plan.y), nivel)
	var d: Vector2 = look_plan - from_plan
	var yaw: float = atan2(-d.x, -d.y)
	_pin_fp(fp, target, yaw, pitch)
	await _settle(settle_frames_view)
	# El jugador es un CharacterBody3D: sin volver a fijarlo, dos ejecuciones
	# dan encuadres distintos.
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


## Limpio, o con la caja de escalera cargada de humo y las viviendas limpias.
func _make_state(building: BuildingModel, caja_con_humo: bool) -> Dictionary:
	var out: Dictionary = {}
	for rid in building.get_rooms().keys():
		var sucia: bool = caja_con_humo and _portal_ids.has(int(rid))
		out[str(rid)] = {
			"id": int(rid),
			"burning": false,
			"hrr_kw": 0.0,
			"visibility_m": 2.0 if sucia else 30.0,
			"smoke_kg": 1.5 if sucia else 0.0,
			"visible_smoke_layer_m": 1.2 if sucia else PLANTA_H,
			"combustion_regime": "WELL_VENTILATED",
			"o2_upper": 0.19 if sucia else 0.209,
			"temp_upper_c": 90.0 if sucia else 20.0,
			"temp_lower_c": 25.0 if sucia else 20.0,
		}
	return out


func _settle(frames: int) -> void:
	for i in range(maxi(1, frames)):
		await get_tree().process_frame


func _capture(nombre: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	if img == null:
		_fail("sin imagen en %s" % nombre)
		return
	var ruta: String = "%s/%s.png" % [_out_dir, nombre]
	if img.save_png(ruta) != OK:
		_fail("no se pudo escribir %s" % ruta)
		return
	_written += 1
	print("[capture] %s" % ruta)


func _cmdline_value(prefix: String, fallback: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if String(arg).begins_with(prefix):
			return String(arg).substr(prefix.length())
	return fallback


func _fail(motivo: String) -> void:
	_failures.append(motivo)
	push_error("[capture_portal] %s" % motivo)


func _finish() -> void:
	if _failures.is_empty():
		print("[capture_portal] OK (%d capturas)" % _written)
		get_tree().quit(0)
	else:
		push_error("[capture_portal] FALLO (%d)" % _failures.size())
		get_tree().quit(1)

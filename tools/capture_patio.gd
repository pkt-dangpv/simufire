extends Node
## Capturas del PATIO: lo unico que un guardarrail headless no dice es si se VE.
##
## Lo que hay que juzgar en estas fotos es concreto:
##
##  - que por la ventana se vea un CONDUCTO y el cielo al final, no un techo,
##  - que no quede repisa de forjado alrededor del pozo,
##  - y que el humo se lea como humo subiendo por el, no como una caja gris.
##
## Tres estados a proposito: limpio, humo solo en la zona baja, y el conducto
## lleno. El del medio es el que dice si el frente se ve subir.
##
## IMPORTANTE: hay que ejecutarlo CON VENTANA REAL. En --headless no hay
## rasterizado y `RenderingServer.frame_post_draw` no dispara nunca.
##
##   <godot> --path . --resolution 1600x900 tools/capture_patio.tscn -- --out=<dir>

const BuildingModelScript := preload("res://sim/BuildingModel.gd")
const FirstPersonControllerScript := preload("res://view/fp/FirstPersonController.gd")

const PLANTA_H: float = 2.9
const PLANTAS: int = 3
const PATIO_LADO_M: float = 2.5

@export_group("Salida")
@export var output_dir: String = ""

@export_group("Vistas")
## Nombre, posicion en planta (m), punto al que se mira (m) y cabeceo (rad).
@export var fp_views: Array[Dictionary] = [
	{"nombre": "desde_la_cocina", "desde_m": Vector2(3.2, 1.2), "mira_m": Vector2(6.2, 1.2), "cabeceo_rad": 0.0},
	{"nombre": "en_la_ventana", "desde_m": Vector2(4.6, 1.2), "mira_m": Vector2(6.2, 1.2), "cabeceo_rad": 0.0},
	{"nombre": "mirando_arriba", "desde_m": Vector2(4.6, 1.2), "mira_m": Vector2(6.2, 1.2), "cabeceo_rad": 0.70},
	{"nombre": "mirando_abajo", "desde_m": Vector2(4.6, 1.2), "mira_m": Vector2(6.2, 1.2), "cabeceo_rad": -0.60},
	# Asomado: la camara DENTRO del conducto. Desde la sala no se ve el pozo -el
	# antepecho tapa abajo y el dintel tapa arriba-, asi que las vistas de la
	# cocina no dicen nada sobre si el patio es un pozo o una caja.
	{"nombre": "asomado_arriba", "desde_m": Vector2(6.25, 1.25), "mira_m": Vector2(6.25, 0.25), "cabeceo_rad": 1.25},
	{"nombre": "asomado_abajo", "desde_m": Vector2(6.25, 1.25), "mira_m": Vector2(6.25, 0.25), "cabeceo_rad": -1.25},
	{"nombre": "asomado_al_frente", "desde_m": Vector2(6.25, 1.25), "mira_m": Vector2(6.25, 0.25), "cabeceo_rad": 0.35},
]
@export var show_furniture: bool = false
## Centro del edificio en planta, para pasar de metros de plano a mundo.
@export var plan_center_m: Vector2 = Vector2(3.75, 2.0)
## Desde que planta se mira. La baja ve el fondo; una intermedia ve pozo arriba
## y abajo, que es lo interesante.
## Cerrada se juzga el cristal; abierta, el conducto. Si con la ventana abierta
## el patio sigue negro, el problema no es el vidrio: es que ahi no entra luz.
@export_range(0.0, 1.0, 0.05) var window_open_fraction: float = 0.0
@export var apartment_floor_number: int = 3
@export var building_total_floors: int = 8

@export_group("Reposo")
@export_range(1, 400, 1) var settle_frames_state: int = 90
@export_range(1, 120, 1) var settle_frames_view: int = 12

var _out_dir: String = ""
var _written: int = 0
var _failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var default_dir: String = output_dir.strip_edges()
	if default_dir == "":
		default_dir = ProjectSettings.globalize_path("res://.test_tmp/patio_capture")
	_out_dir = _cmdline_value("--out=", default_dir)
	var abrir: String = _cmdline_value("--open=", "")
	if abrir != "":
		window_open_fraction = float(abrir)
	DirAccess.make_dir_recursive_absolute(_out_dir)
	print("[capture] destino=%s display=%s" % [_out_dir, DisplayServer.get_name()])
	if DisplayServer.get_name() == "headless":
		push_error("capture_patio necesita ventana real: en --headless no hay render.")
		get_tree().quit(1)
		return

	var building: BuildingModel = BuildingModelScript.new()
	if not building.load_template_data(_make_template(window_open_fraction)):
		_fail("la plantilla del patio fue rechazada por BuildingModel")
		building.free()
		_finish()
		return

	var host := Node3D.new()
	host.name = "CapturePatioWorld"
	add_child(host)
	var fp: FirstPersonController = FirstPersonControllerScript.new()
	fp.name = "CapturePatioFP"
	fp.show_fp_furniture = show_furniture
	host.add_child(fp)
	await get_tree().process_frame
	fp.setup(building)
	await get_tree().physics_frame
	fp.set_active(true)
	# Sin esto la camara SE CAE POR EL POZO: el patio no tiene forjado en las
	# plantas altas -que es justo lo que se quiere retratar-, asi que el
	# CharacterBody3D se desploma hasta el fondo entre el encuadre y el disparo,
	# y las fotos de las plantas altas salian tomadas desde la baja.
	fp.set_physics_process(false)

	for caso in [
		{"nombre": "limpio", "zonas": []},
		{"nombre": "humo_abajo", "zonas": [2]},
		{"nombre": "conducto_lleno", "zonas": [2, 12, 22]},
	]:
		fp.set_state(_make_state(Array(caso["zonas"])))
		await _settle(settle_frames_state)
		for view in fp_views:
			await _place_fp(
				fp,
				Vector2(view.get("desde_m", Vector2.ZERO)),
				Vector2(view.get("mira_m", Vector2.ZERO)),
				float(view.get("cabeceo_rad", 0.0))
			)
			await _capture("patio_%s_%s" % [String(caso["nombre"]), String(view.get("nombre", "vista"))])

	fp.set_active(false)
	host.free()
	building.free()
	_finish()


func _place_fp(fp: Node3D, from_plan: Vector2, look_plan: Vector2, pitch: float) -> void:
	var nivel: float = float(PLANTAS - 2) * PLANTA_H
	var target := Vector3(from_plan.x - plan_center_m.x, nivel + 0.05, from_plan.y - plan_center_m.y)
	var d: Vector2 = look_plan - from_plan
	var yaw: float = atan2(-d.x, -d.y)
	_pin_fp(fp, target, yaw, pitch)
	await _settle(settle_frames_view)
	# El jugador es un CharacterBody3D con gravedad: durante el reposo se
	# desliza y cae. Sin volver a fijarlo, dos ejecuciones dan encuadres
	# distintos.
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


## Tres plantas, vivienda + zona de patio en cada una, encadenadas, con la boca
## arriba y una ventana de la vivienda al patio en cada planta.
func _make_template(open_fraction: float) -> Dictionary:
	var rooms: Array = []
	var rects: Dictionary = {}
	var ops: Array = []
	for p in range(PLANTAS):
		var z: float = float(p) * PLANTA_H
		var viv: int = 10 * p + 1
		var pat: int = 10 * p + 2
		rooms.append({
			"id": viv, "name": "Cocina P%d" % p, "kind": "cocina", "height_m": 2.6,
			"floor_level_z_m": z, "fuel_energy_MJ": 400.0, "max_hrr_kw": 900.0,
			"fuel_objects": [],
		})
		rooms.append({
			"id": pat, "name": "Patio P%d" % p, "kind": "patio", "height_m": PLANTA_H,
			"floor_level_z_m": z, "fuel_energy_MJ": 0.0, "max_hrr_kw": 0.0,
			"fuel_objects": [],
		})
		rects[str(viv)] = {"x": 0.0, "y": 0.0, "w": 5.0, "h": 4.0}
		rects[str(pat)] = {"x": 5.0, "y": 0.0, "w": PATIO_LADO_M, "h": PATIO_LADO_M}
		ops.append({
			"a": viv, "b": pat, "type": "window", "wall": "right",
			"offset_m": 0.8, "offset_is_fraction": false,
			"width_m": 1.20, "height_m": 1.10, "sill_m": 0.95, "open_fraction": open_fraction,
		})
		ops.append({
			"a": viv, "b": -1, "type": "door", "wall": "left",
			"offset_m": 1.6, "offset_is_fraction": false,
			"width_m": 0.92, "height_m": 2.05, "open_fraction": 0.0,
		})
		if p + 1 < PLANTAS:
			ops.append({
				"a": pat, "b": 10 * (p + 1) + 2, "type": "hole", "wall": "",
				"offset_m": 0.0, "offset_is_fraction": true,
				"width_m": PATIO_LADO_M, "height_m": PATIO_LADO_M, "sill_m": 0.0,
				"open_fraction": 1.0, "is_vertical": true,
			})
	ops.append({
		"a": 10 * (PLANTAS - 1) + 2, "b": -1, "type": "hole", "wall": "",
		"offset_m": 0.0, "offset_is_fraction": true,
		"width_m": PATIO_LADO_M, "height_m": PATIO_LADO_M, "sill_m": 0.0,
		"open_fraction": 1.0, "is_vertical": true,
	})
	return {
		"version": 1,
		"building_type": "apartment",
		"apartment_floor_number": apartment_floor_number,
		"building_total_floors": building_total_floors,
		"outside_temp_c": 18.0, "outside_o2": 0.209, "stop_time_s": 0.0,
		"hvac_mode": "none", "hvac_data": {"exists": false, "on": false, "mode": "none"},
		"room_rect_m": rects, "rooms_data": rooms, "openings_data": ops,
		"detectors": [], "victims": [], "exterior_walls": [],
	}


## Estado con las zonas indicadas llenas de humo, y el resto limpio.
func _make_state(con_humo: Array) -> Dictionary:
	var out: Dictionary = {}
	for p in range(PLANTAS):
		for room_id in [10 * p + 1, 10 * p + 2]:
			var sucia: bool = con_humo.has(room_id)
			out[str(room_id)] = {
				"id": room_id,
				"burning": false,
				"hrr_kw": 0.0,
				"visibility_m": 1.2 if sucia else 30.0,
				"smoke_kg": 4.0 if sucia else 0.0,
				"visible_smoke_layer_m": 0.5 if sucia else PLANTA_H,
				"combustion_regime": "WELL_VENTILATED",
				"o2_upper": 0.18 if sucia else 0.209,
				"temp_upper_c": 120.0 if sucia else 20.0,
				"temp_lower_c": 30.0 if sucia else 20.0,
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
	push_error("[capture_patio] %s" % motivo)


func _finish() -> void:
	if _failures.is_empty():
		print("[capture_patio] OK (%d capturas)" % _written)
		get_tree().quit(0)
	else:
		push_error("[capture_patio] FALLO (%d)" % _failures.size())
		get_tree().quit(1)

extends Node
## Captura un juego fijo de vistas de referencia del aparato visual (F0 del
## plan de cierre visual, docs/AUDITORIA_VISUAL_2026-08-29.md §12.F0).
##
## Sirve para comparar antes/despues de cada fase: renderiza siempre el mismo
## piso patron, desde los mismos puntos de vista, en estado limpio y en
## incendio, y guarda un PNG por vista.
##
## IMPORTANTE: hay que ejecutarlo CON VENTANA REAL. En --headless no hay
## rasterizado y RenderingServer.frame_post_draw no dispara nunca, asi que las
## capturas saldrian vacias.
##
##   <godot> --path . --resolution 1600x900 tools/capture_visual_reference.tscn -- --out=<dir> [--label=<prefijo>]
##
## Salida: un PNG por vista en <dir>, mas una linea [capture] por fichero.
## Codigo de salida 0 si se escribieron todas las vistas, 1 si falto alguna.

const BuildingModelScript := preload("res://sim/BuildingModel.gd")
const FirstPersonControllerScript := preload("res://view/fp/FirstPersonController.gd")
const Visualizer3DScript := preload("res://view/3d/Visualizer3D.gd")

@export_group("Salida")
## Carpeta de destino. La linea de comandos (--out=) tiene prioridad sobre esto,
## para poder lanzarlo desde un script sin tocar la escena.
@export var output_dir: String = ""
## Prefijo del nombre de fichero, para guardar juegos antes/despues en la misma
## carpeta. Tambien se puede pasar con --label=.
@export var output_label: String = ""
@export var capture_first_person: bool = true
@export var capture_dollhouse: bool = true

@export_group("Vistas")
## Cada entrada es una vista FP: nombre del fichero, posicion en planta (m),
## punto al que se mira (m) y cabeceo en radianes. Editable desde el inspector:
## anade, quita o recoloca vistas sin tocar el codigo.
##
## Dos trampas que conviene recordar al colocar una vista nueva:
## - La pared "bottom" de un rectangulo es el lado y = y0 + alto, y su offset_m
##   corre en sentido inverso al eje x.
## - El jugador es un CharacterBody3D con gravedad: una vista sobre el hueco de
##   la escalera se cae por el y acaba fotografiando la calle.
@export var fp_views: Array[Dictionary] = [
	{"nombre": "salon_puerta_interior", "desde_m": Vector2(3.0, 2.0), "mira_m": Vector2(6.0, 1.6), "cabeceo_rad": 0.0},
	{"nombre": "salon_ventana_fachada", "desde_m": Vector2(3.0, 2.0), "mira_m": Vector2(0.0, 2.0), "cabeceo_rad": 0.0},
	{"nombre": "salon_fuego", "desde_m": Vector2(4.8, 3.0), "mira_m": Vector2(2.5, 1.2), "cabeceo_rad": -0.08},
	{"nombre": "salon_puerta_rellano", "desde_m": Vector2(5.55, 2.2), "mira_m": Vector2(5.55, 4.0), "cabeceo_rad": 0.0},
	{"nombre": "dormitorio_puerta", "desde_m": Vector2(8.2, 2.0), "mira_m": Vector2(6.0, 1.6), "cabeceo_rad": 0.0},
	{"nombre": "dormitorio_ventana", "desde_m": Vector2(8.0, 2.0), "mira_m": Vector2(10.0, 2.0), "cabeceo_rad": 0.0},
	{"nombre": "rellano_vivienda", "desde_m": Vector2(5.55, 4.35), "mira_m": Vector2(5.55, 6.0), "cabeceo_rad": 0.0},
	{"nombre": "rellano_suelo", "desde_m": Vector2(5.55, 4.35), "mira_m": Vector2(5.90, 4.95), "cabeceo_rad": -0.62},
	{"nombre": "calle_fachada", "desde_m": Vector2(-4.5, 2.0), "mira_m": Vector2(0.0, 2.0), "cabeceo_rad": 0.08},
]
## Centro del edificio patron en planta, para pasar de metros de plano a mundo.
@export var plan_center_m: Vector2 = Vector2(5.0, 2.0)

@export_group("Reposo")
## Fotogramas de espera tras cambiar de estado. La niebla FP tiene constante de
## tiempo propia (fp_fog_smooth_tau_s): con pocos fotogramas la captura sale a
## medio camino del estado pedido.
@export_range(1, 400, 1) var settle_frames_state: int = 90
## Fotogramas de espera tras recolocar la camara.
@export_range(1, 120, 1) var settle_frames_view: int = 12

@export_group("Iluminacion del piso patron")
## Mismos valores que scenes/SimulationScene.tscn, para que la captura
## corresponda con lo que ve el usuario y no con los defaults del script.
@export var fp_room_ceiling_light_energy: float = 0.58
@export var fp_landing_light_energy: float = 1.05
@export var fp_landing_light_range_m: float = 4.2
@export var fp_window_light_energy: float = 0.95

@export_group("Estado de incendio del piso patron")
@export var fire_hrr_kw: float = 850.0
@export var fire_room_temp_upper_c: float = 340.0
@export var fire_room_visibility_m: float = 3.2
@export var fire_room_layer_m: float = 1.15
## Sala contigua: enhumada pero sin fuego, que es el caso que destapo FP-6.
@export var smoky_room_temp_upper_c: float = 96.0
@export var smoky_room_visibility_m: float = 9.0
@export var smoky_room_layer_m: float = 1.95

var _out_dir: String = ""
var _label: String = ""
var _written: int = 0
var _failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var default_dir: String = output_dir.strip_edges()
	if default_dir == "":
		default_dir = ProjectSettings.globalize_path("res://.test_tmp/visual_reference")
	_out_dir = _cmdline_value("--out=", default_dir)
	_label = _cmdline_value("--label=", output_label)
	DirAccess.make_dir_recursive_absolute(_out_dir)
	print("[capture] destino=%s display=%s" % [_out_dir, DisplayServer.get_name()])
	if DisplayServer.get_name() == "headless":
		push_error("capture_visual_reference necesita ventana real: en --headless no hay render.")
		get_tree().quit(1)
		return

	var building: BuildingModel = BuildingModelScript.new()
	if not building.load_template_data(_make_template()):
		_fail("la plantilla patron fue rechazada por BuildingModel")
		_finish()
		return

	if capture_first_person:
		await _capture_first_person(building)
	if capture_dollhouse:
		await _capture_dollhouse(building)
	building.free()
	_finish()


# ---------------------------------------------------------------------------
# Primera persona
# ---------------------------------------------------------------------------

func _capture_first_person(building: BuildingModel) -> void:
	var host := Node3D.new()
	host.name = "CaptureFPWorld"
	add_child(host)
	var fp: FirstPersonController = FirstPersonControllerScript.new()
	fp.name = "CaptureFP"
	# Mismos valores que scenes/SimulationScene.tscn, para que la captura
	# corresponda con lo que ve el usuario y no con los defaults del script.
	fp.room_ceiling_light_energy = fp_room_ceiling_light_energy
	fp.landing_light_energy = fp_landing_light_energy
	fp.landing_light_range_m = fp_landing_light_range_m
	fp.window_light_energy = fp_window_light_energy
	host.add_child(fp)
	await get_tree().process_frame
	fp.setup(building)
	await get_tree().physics_frame
	fp.set_active(true)

	for pass_data in [["limpio", _make_clean_state()], ["incendio", _make_fire_state()]]:
		var state_name: String = pass_data[0]
		fp.set_state(pass_data[1])
		# La niebla FP tiene constante de tiempo propia (fp_fog_smooth_tau_s):
		# sin este reposo la captura sale a medio camino del estado pedido.
		await _settle(settle_frames_state)
		for view in fp_views:
			await _place_fp(
				fp,
				Vector2(view.get("desde_m", Vector2.ZERO)),
				Vector2(view.get("mira_m", Vector2.ZERO)),
				float(view.get("cabeceo_rad", 0.0))
			)
			await _capture("fp_%s_%s" % [state_name, String(view.get("nombre", "vista"))])

	fp.set_active(false)
	host.free()


func _place_fp(fp: Node3D, from_plan: Vector2, look_plan: Vector2, pitch: float) -> void:
	fp.global_position = Vector3(from_plan.x - plan_center_m.x, 0.05, from_plan.y - plan_center_m.y)
	var d: Vector2 = look_plan - from_plan
	fp.rotation.y = atan2(-d.x, -d.y)
	var cam := fp.get_node_or_null("FirstPersonCamera") as Camera3D
	if cam != null:
		cam.rotation.x = pitch
		cam.current = true
	await _settle(settle_frames_view)


# ---------------------------------------------------------------------------
# Visor 3D (dollhouse)
# ---------------------------------------------------------------------------

func _capture_dollhouse(building: BuildingModel) -> void:
	var vis: Visualizer3D = Visualizer3DScript.new()
	vis.name = "CaptureVisualizer3D"
	vis.building = building
	_add_visualizer_children(vis)
	add_child(vis)
	await get_tree().process_frame
	vis.rebuild_from_building()

	for pass_data in [["limpio", _make_clean_state()], ["incendio", _make_fire_state()]]:
		vis.set_state(pass_data[1])
		await _settle(settle_frames_state)
		await _capture("dollhouse_%s" % String(pass_data[0]))

	vis.free()


## Replica los hijos que Visualizer3D espera en scenes/SimulationScene.tscn,
## incluidas sol y luz de relleno: sin ellas la casa de munecas sale negra y la
## comparacion no vale para nada.
func _add_visualizer_children(visualizer: Node3D) -> void:
	for node_name in ["Rooms", "Openings", "Atmosphere", "Labels"]:
		var container := Node3D.new()
		container.name = node_name
		visualizer.add_child(container)

	var camera_rig := Node3D.new()
	camera_rig.name = "CameraRig"
	camera_rig.transform = Transform3D(
		Vector3(0.743145, -0.5547341, 0.3741732),
		Vector3(0.0, 0.55919325, 0.82903737),
		Vector3(-0.6691304, -0.61609495, 0.41556168),
		Vector3.ZERO
	)
	visualizer.add_child(camera_rig)

	var camera := Camera3D.new()
	camera.name = "Camera3D"
	camera.fov = 45.0
	camera.position = Vector3(0.0, 0.0, 13.0)
	camera.current = true
	camera_rig.add_child(camera)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.transform = Transform3D(
		Vector3(0.86602527, 0.38302252, -0.32139382),
		Vector3(0.0, 0.64278734, 0.7660447),
		Vector3(0.50000024, -0.66341406, 0.55667007),
		Vector3.ZERO
	)
	sun.light_energy = 1.8
	visualizer.add_child(sun)

	var fill := OmniLight3D.new()
	fill.name = "FillLight"
	fill.position = Vector3(0.0, 5.0, 0.0)
	fill.light_energy = 0.35
	fill.omni_range = 18.0
	visualizer.add_child(fill)


# ---------------------------------------------------------------------------
# Utilidades
# ---------------------------------------------------------------------------

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
	var expected: int = 0
	if capture_first_person:
		expected += fp_views.size() * 2
	if capture_dollhouse:
		expected += 2
	if _written != expected:
		_fail("se esperaban %d vistas y se escribieron %d" % [expected, _written])
	if _failures.is_empty():
		print("VISUAL REFERENCE CAPTURE PASS (%d vistas)" % _written)
		get_tree().quit(0)
		return
	push_error("VISUAL REFERENCE CAPTURE FAILED")
	for failure in _failures:
		push_error("- " + failure)
	get_tree().quit(1)


# ---------------------------------------------------------------------------
# Piso patron
# ---------------------------------------------------------------------------

## Salon 6x4 con ventana a fachada y puerta al rellano, dormitorio 4x4 con
## ventana, unidos por una puerta interior. Cubre en una sola escena: vano
## interior, hueco a fachada, rellano de portal y decorado urbano.
func _make_template() -> Dictionary:
	return {
		"version": 1,
		"building_type": "apartment",
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
			{"a": 0, "b": -1, "type": "window", "wall": "left", "offset_m": 1.2, "width_m": 1.30, "height_m": 1.20, "sill_m": 0.90, "open_fraction": 1.0},
			{"a": 1, "b": -1, "type": "window", "wall": "right", "offset_m": 1.4, "width_m": 1.30, "height_m": 1.20, "sill_m": 0.90, "open_fraction": 0.0}
		],
		"detectors": [],
		"victims": [],
		"exterior_walls": []
	}


func _make_clean_state() -> Dictionary:
	return {
		"0": _room_state(0, "Salon", "salon", false, 0.0, 21.0, 20.0, 0.209, 0.0, 30.0, 2.62, "cold"),
		"1": _room_state(1, "Dormitorio", "dormitorio", false, 0.0, 20.0, 20.0, 0.209, 0.0, 30.0, 2.62, "")
	}


## Salon en llamas y dormitorio contiguo enhumado pero sin fuego: es el caso
## que destapo FP-6 (la sala vecina se leia como una caja negra).
func _make_fire_state() -> Dictionary:
	return {
		"0": _room_state(
			0, "Salon", "salon", true, fire_hrr_kw, fire_room_temp_upper_c, 68.0, 0.135, 1.4,
			fire_room_visibility_m, fire_room_layer_m, "flaming"
		),
		"1": _room_state(
			1, "Dormitorio", "dormitorio", false, 0.0, smoky_room_temp_upper_c, 32.0, 0.19, 0.35,
			smoky_room_visibility_m, smoky_room_layer_m, ""
		)
	}


func _room_state(
	room_id: int,
	room_name: String,
	kind: String,
	has_fire: bool,
	hrr_kw: float,
	temp_upper_c: float,
	temp_lower_c: float,
	o2_upper: float,
	smoke_kg: float,
	visibility_m: float,
	layer_m: float,
	fuel_state: String
) -> Dictionary:
	var state: Dictionary = {
		"id": room_id,
		"name": room_name,
		"kind": kind,
		"height_m": 2.62,
		"has_fire": has_fire,
		"hrr_kw": hrr_kw,
		"temp_upper_c": temp_upper_c,
		"temp_lower_c": temp_lower_c,
		"o2": o2_upper,
		"o2_upper": o2_upper,
		"combustion_regime": "FUEL_CONTROLLED" if has_fire else "",
		"fire_latent_active": false,
		"smoke_kg": smoke_kg,
		"visibility_m": visibility_m,
		"smoke_layer_m": layer_m,
		"smoke_display_layer_m": layer_m,
		"visible_smoke_layer_m": layer_m,
		"thermal_layer_m": layer_m,
		"fuel_objects": []
	}
	if fuel_state != "":
		state["fuel_objects"] = [{
			"id": "capture_sofa",
			"name": "Sofa",
			"kind": "sofa",
			"room_id": room_id,
			"position_m": {"x": 2.5, "y": 1.2},
			"size_m": {"x": 1.9, "y": 0.9},
			"elevation_m": 0.0,
			"state": fuel_state,
			"hrr_kw": hrr_kw,
			"max_hrr_kw": 1400.0,
			"is_primary_ignition_source": true
		}]
	return state

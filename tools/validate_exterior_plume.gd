extends Node
## Guardarrail del PENACHO: por donde sale el humo al aire libre.
##
## El visor 3D dibujaba penacho en toda abertura cuyo otro lado fuese el
## ambiente. Eso metia uno en la puerta de entrada de un piso, **que da a un
## rellano cerrado**: lo que sale por ahi choca contra el techo del rellano y
## luego sube por la caja de escalera, no se va al cielo desde la fachada.
##
## Lo que se fija aqui, sobre el visor construido -no sobre la regla suelta-:
##
##  1. La puerta de un piso NO echa penacho.
##  2. La misma planta, declarada unifamiliar, SI: ahi la entrada da a la calle.
##  3. Una ventana a la calle SI, siempre.
##  4. **La boca del patio SI**, que es lo que se estrena: hasta ahora ninguna
##     abertura vertical podia echar penacho, y una boca es justo eso.
##  5. Y el penacho de la boca sale del hueco hacia ARRIBA, no de lado: una boca
##     es un agujero horizontal y lo que sale de ella sube por flotabilidad.
##
##   <godot> --path . --headless tools/validate_exterior_plume.tscn

const BuildingModelScript := preload("res://sim/BuildingModel.gd")
const Visualizer3DScript := preload("res://view/3d/Visualizer3D.gd")

const PLANTA_H: float = 2.9
const PATIO_LADO_M: float = 2.5

var _fails: int = 0


func _ready() -> void:
	call_deferred("_run")


func _eq(que: String, got, want) -> void:
	if str(got) == str(want):
		print("  ok   %s = %s" % [que, str(got)])
	else:
		print("  FAIL %s = %s (se esperaba %s)" % [que, str(got), str(want)])
		_fails += 1


## Un piso con las cuatro aberturas que importan:
##
##   0  Recibidor -> exterior, PUERTA   (portal si es bloque, calle si no)
##   1  Salon     -> exterior, VENTANA  (calle siempre)
##   2  Cocina    -> Patio P0, ventana  (conducto)
##   3  Patio P0  -> Patio P1           (encadenado)
##   4  Patio P1  -> exterior, vertical (la BOCA)
func _plantilla(tipo: String) -> Dictionary:
	return {
		"version": 1, "building_type": tipo, "apartment_floor_number": 0,
		"building_total_floors": 4, "exterior_walls": [],
		"floors": [{"name": "R", "level_m": 0.0}, {"name": "R+1", "level_m": PLANTA_H}],
		"room_rect_m": {
			"1": {"x": 0.0, "y": 0.0, "w": 3.0, "h": 3.0},
			"2": {"x": 3.0, "y": 0.0, "w": 4.0, "h": 3.0},
			"3": {"x": 7.0, "y": 0.0, "w": 3.0, "h": 3.0},
			"4": {"x": 10.0, "y": 0.0, "w": PATIO_LADO_M, "h": PATIO_LADO_M},
			"5": {"x": 10.0, "y": 0.0, "w": PATIO_LADO_M, "h": PATIO_LADO_M},
		},
		"rooms_data": [
			{"id": 1, "name": "Recibidor", "kind": "recibidor", "height_m": 2.5,
				"floor_level_z_m": 0.0, "fuel_energy_MJ": 200.0, "fuel_objects": []},
			{"id": 2, "name": "Salon", "kind": "salon", "height_m": 2.5,
				"floor_level_z_m": 0.0, "fuel_energy_MJ": 600.0, "fuel_objects": []},
			{"id": 3, "name": "Cocina", "kind": "cocina", "height_m": 2.5,
				"floor_level_z_m": 0.0, "fuel_energy_MJ": 300.0, "fuel_objects": []},
			{"id": 4, "name": "Patio P0", "kind": "patio", "height_m": PLANTA_H,
				"floor_level_z_m": 0.0, "fuel_energy_MJ": 0.0, "fuel_objects": []},
			{"id": 5, "name": "Patio P1", "kind": "patio", "height_m": PLANTA_H,
				"floor_level_z_m": PLANTA_H, "fuel_energy_MJ": 0.0, "fuel_objects": []},
		],
		"openings_data": [
			{"a": 1, "b": -1, "type": "door", "wall": "top", "offset_m": 1.0,
				"offset_is_fraction": false, "width_m": 0.92, "height_m": 2.05,
				"sill_m": 0.0, "open_fraction": 1.0},
			{"a": 2, "b": -1, "type": "window", "wall": "top", "offset_m": 1.4,
				"offset_is_fraction": false, "width_m": 1.30, "height_m": 1.10,
				"sill_m": 0.90, "open_fraction": 1.0},
			{"a": 3, "b": 4, "type": "window", "wall": "right", "offset_m": 0.8,
				"offset_is_fraction": false, "width_m": 1.20, "height_m": 1.10,
				"sill_m": 0.95, "open_fraction": 1.0},
			{"a": 4, "b": 5, "type": "hole", "wall": "", "offset_m": 0.0,
				"offset_is_fraction": true, "width_m": PATIO_LADO_M, "height_m": PATIO_LADO_M,
				"sill_m": 0.0, "open_fraction": 1.0, "is_vertical": true},
			{"a": 5, "b": -1, "type": "hole", "wall": "", "offset_m": 0.0,
				"offset_is_fraction": true, "width_m": PATIO_LADO_M, "height_m": PATIO_LADO_M,
				"sill_m": 0.0, "open_fraction": 1.0, "is_vertical": true},
		],
		"detectors": [], "victims": [],
		"player_start": {"room_id": 2, "x_m": 2.0, "y_m": 1.5}, "ignition_room_id": 2,
	}


## Todas las salas cargadas de humo, para que nada dependa de donde este el
## fuego: lo que se mide es DONDE se dibuja penacho, no cuanto.
func _estado_con_humo() -> Dictionary:
	var out: Dictionary = {}
	for room_id in [1, 2, 3, 4, 5]:
		out[str(room_id)] = {
			"id": room_id,
			"burning": room_id == 2,
			"hrr_kw": 900.0 if room_id == 2 else 0.0,
			"visibility_m": 0.8,
			"smoke_kg": 6.0,
			"smoke_alpha": 0.9,
			"smoke_bottom_m": 0.4,
			"visible_smoke_layer_m": 0.4,
			"smoke_layer_m": 0.4,
			"height_m": PLANTA_H if room_id >= 4 else 2.5,
			"combustion_regime": "WELL_VENTILATED",
			"o2_upper": 0.16,
			"temp_upper_c": 320.0,
			"temp_lower_c": 60.0,
		}
	return out


func _visor(tipo: String) -> Visualizer3D:
	var building: BuildingModel = BuildingModelScript.new()
	if not building.load_template_data(_plantilla(tipo)):
		_eq("la plantilla (%s) la acepta BuildingModel" % tipo, false, true)
		return null
	var visualizer: Visualizer3D = Visualizer3DScript.new()
	visualizer.name = "Visor_%s" % tipo
	visualizer.building = building
	for node_name in ["Rooms", "Openings", "Atmosphere", "Labels"]:
		var container := Node3D.new()
		container.name = node_name
		visualizer.add_child(container)
	var rig := Node3D.new()
	rig.name = "CameraRig"
	visualizer.add_child(rig)
	var camera := Camera3D.new()
	camera.name = "Camera3D"
	camera.position = Vector3(0.0, 0.0, 24.0)
	rig.add_child(camera)
	add_child(visualizer)
	return visualizer


## Que aberturas estan echando penacho, por indice.
func _con_penacho(visualizer: Node) -> String:
	var out: Array = []
	for index in range(5):
		var plume := _penacho(visualizer, index)
		if plume != null and plume.visible:
			out.append(str(index))
	return ",".join(out)


func _penacho(visualizer: Node, index: int) -> MeshInstance3D:
	# Los penachos cuelgan de `Atmosphere`, no del nodo de su hueco: son humo,
	# no herraje.
	return visualizer.get_node_or_null(
		"Atmosphere/SmokeExteriorPlume_%02d" % index
	) as MeshInstance3D


func _run() -> void:
	await get_tree().process_frame
	var estado: Dictionary = _estado_con_humo()

	# ── Bloque de pisos ──
	var piso: Visualizer3D = _visor("apartment")
	if piso != null:
		piso.rebuild_from_building()
		for _i in range(40):
			piso.set_state(estado)
			await get_tree().process_frame
		# 0 es la puerta del portal: fuera. 1 la ventana y 4 la boca: dentro.
		_eq("en un bloque, echan penacho", _con_penacho(piso), "1,4")
		# La boca echa hacia ARRIBA, y arranca en su propio plano. El hueco esta
		# en la cubierta de la zona alta del patio: 2,9 + 2,9 = 5,8 m.
		var boca := _penacho(piso, 4)
		if boca == null or not boca.visible:
			_eq("hay penacho en la boca que medir", false, true)
			_finalizar()
			return
		var caja: AABB = boca.get_aabb()
		var centro: Vector3 = boca.global_transform * caja.get_center()
		var base_m: float = centro.y - caja.size.y * 0.5
		_eq("el penacho de la boca arranca en la cubierta", "%.1f" % base_m, "5.8")
		_eq("y sube, no se tumba", caja.size.y > caja.size.x, true)
		# Sin inclinacion: el de fachada se ladea doce grados apoyado en el muro,
		# y una boca no tiene muro en el que apoyarse.
		_eq("y sube recto", "%.2f" % boca.rotation.x, "0.00")

	# ── La misma planta, declarada unifamiliar ──
	var casa: Visualizer3D = _visor("single_family")
	if casa != null:
		casa.rebuild_from_building()
		for _i in range(40):
			casa.set_state(estado)
			await get_tree().process_frame
		# Cambia UNA cosa: la entrada ya no da a un rellano, da a la calle.
		_eq("en una unifamiliar, echan penacho", _con_penacho(casa), "0,1,4")

	_finalizar()


func _finalizar() -> void:
	if _fails == 0:
		print("[validate_exterior_plume] PASS")
		get_tree().quit(0)
		return
	push_error("[validate_exterior_plume] FAIL (%d)" % _fails)
	get_tree().quit(1)

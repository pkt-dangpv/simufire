extends SceneTree
## Sonda: cuanto cuesta rehacer la vista 3D del editor.
##
## Es el dato que decide si se puede tener el 3D vivo mientras se dibuja en
## planta. Hoy la vista se reconstruye entera -_sync_editor_runtime_views()
## exporta el escenario, recarga el BuildingModel y llama a rebuild_from_building-
## y eso a 60 veces por segundo no se sostiene si cuesta mas que un fotograma.
##
## Mide con un piso de verdad, no con dos cajas: carga
## scenarios/compact_apartment_reference.json si esta, y si no monta uno.
##
##   godot --headless --path . --script res://tools/probe_editor_3d_cost.gd

const Serializer := preload("res://editor/ScenarioSerializer.gd")
const SAMPLES: int = 12

var _editor: Node = null
var _frames: int = 0


func _initialize() -> void:
	var packed := load("res://scenes/ScenarioEditorScene.tscn") as PackedScene
	_editor = packed.instantiate()
	root.add_child(_editor)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 5:
		return false

	var data: Dictionary = _load_reference()
	_editor.editor_data = data
	_editor.current_floor_index = 0
	print("escenario: %d salas, %d aperturas, %d objetos" % [
		Array(data.get("rooms_data", [])).size(),
		Array(data.get("openings_data", [])).size(),
		_count_objects(data)
	])

	# Por fases, para saber a donde se va el tiempo.
	var t0: int = Time.get_ticks_usec()
	var runtime: Dictionary = Serializer.to_runtime_template(_editor.editor_data)
	var t1: int = Time.get_ticks_usec()
	_editor._editor_building_model.load_template_data(runtime, true)
	var t2: int = Time.get_ticks_usec()
	_editor._editor_visualizer_3d.rebuild_from_building()
	var t3: int = Time.get_ticks_usec()
	print("  exportar escenario   %.1f ms" % ((t1 - t0) / 1000.0))
	print("  cargar el modelo     %.1f ms" % ((t2 - t1) / 1000.0))
	print("  rehacer la malla 3D  %.1f ms" % ((t3 - t2) / 1000.0))

	# El mundo de primera persona se rehace tambien, aunque se este dibujando en
	# planta: si pesa, ahi esta el grueso.
	if _editor._editor_fp_controller != null:
		var t_fp: int = Time.get_ticks_usec()
		_editor._editor_fp_controller.setup(_editor._editor_building_model)
		print("  rehacer el mundo FP  %.1f ms" % ((Time.get_ticks_usec() - t_fp) / 1000.0))
	else:
		print("  (no hay mundo FP montado)")

	# Y que pesa dentro del 3D: se apagan los adornos y se vuelve a medir.
	var viz: Node = _editor._editor_visualizer_3d
	for switch in ["furnish_empty_rooms", "show_room_labels", "show_smoke_volume", "show_wall_heatmap", "show_hrr_columns"]:
		if switch in viz:
			viz.set(switch, false)
	var t4: int = Time.get_ticks_usec()
	viz.rebuild_from_building()
	print("  sin muebles ni adornos %.1f ms" % ((Time.get_ticks_usec() - t4) / 1000.0))
	for switch in ["furnish_empty_rooms", "show_room_labels", "show_smoke_volume", "show_wall_heatmap", "show_hrr_columns"]:
		if switch in viz:
			viz.set(switch, true)

	# Primera pasada aparte: incluye construir nodos que luego ya existen.
	var first_us: int = _time_sync()
	var total_us: int = 0
	var worst_us: int = 0
	for i in range(SAMPLES):
		var us: int = _time_sync()
		total_us += us
		worst_us = maxi(worst_us, us)
	var mean_ms: float = float(total_us) / float(SAMPLES) / 1000.0
	print("rehacer la vista 3D: primera %.1f ms, media %.1f ms, peor %.1f ms" % [
		first_us / 1000.0, mean_ms, worst_us / 1000.0
	])
	print("un fotograma a 60 Hz son 16,7 ms")
	if mean_ms <= 16.0:
		print("-> cabe en un fotograma: se puede rehacer mientras se arrastra")
	elif mean_ms <= 120.0:
		print("-> no cabe en un fotograma, pero si en una pausa corta: rehacer al soltar y con retardo mientras se arrastra")
	else:
		print("-> demasiado caro para el tiempo real: haria falta actualizacion incremental")
	_measure_scaling()
	_measure_contents()
	_measure_drag_paths()
	quit(0)
	return true


## El coste, sala a sala: con esto se sabe si rehacer UNA sala sale a cuenta.
##
## Si casi todo es coste por sala, rehacer solo la que se esta moviendo divide el
## tiempo por el numero de salas. Si hay mucho coste fijo, el incremental apenas
## nota.
func _measure_scaling() -> void:
	print("")
	print("coste por tamaño del piso:")
	var previous_ms: float = 0.0
	for room_count in [1, 2, 4, 8, 16]:
		_editor.editor_data = _grid_scenario(room_count)
		var us: int = 0
		for i in range(4):
			us += _time_sync()
		var ms: float = float(us) / 4.0 / 1000.0
		var delta_text: String = ""
		if previous_ms > 0.0:
			delta_text = "  (+%.1f ms respecto al anterior)" % (ms - previous_ms)
		print("  %2d salas: %6.1f ms%s" % [room_count, ms, delta_text])
		previous_ms = ms


## Los dos caminos que hacen falta para que el 3D siga al raton:
##
##  - arrastrando PAREDES no hacen falta los muebles: se apagan y se rehace.
##  - arrastrando un OBJETO no hace falta rehacer nada: basta recargar el modelo
##    y dejar que el visor recoloque las piezas que ya existen.
func _measure_drag_paths() -> void:
	print("")
	print("caminos para seguir al raton (piso de referencia):")
	_editor.editor_data = _load_reference()
	var viz: Node = _editor._editor_visualizer_3d
	_time_sync()

	viz.show_fuel_objects_3d = false
	var us_walls: int = 0
	for i in range(6):
		us_walls += _time_sync()
	print("  rehacer sin muebles:      %6.1f ms" % (float(us_walls) / 6.0 / 1000.0))
	viz.show_fuel_objects_3d = true

	var us_state: int = 0
	for i in range(6):
		var start_us: int = Time.get_ticks_usec()
		var runtime: Dictionary = Serializer.to_runtime_template(_editor.editor_data)
		_editor._editor_building_model.load_template_data(runtime, true)
		viz.set_state({})
		us_state += Time.get_ticks_usec() - start_us
	print("  recolocar sin rehacer:    %6.1f ms" % (float(us_state) / 6.0 / 1000.0))
	var us_full: int = 0
	for i in range(4):
		us_full += _time_sync()
	print("  rehacer entero (hoy):     %6.1f ms" % (float(us_full) / 4.0 / 1000.0))


## Y ahora la otra pregunta: si las salas cuestan 2 ms, ¿de donde salen los 80 ms
## del piso de referencia? Se prueba con muebles y con aperturas por separado.
func _measure_contents() -> void:
	print("")
	print("coste del contenido (4 salas fijas):")
	for objects_per_room in [0, 1, 3, 6]:
		_editor.editor_data = _grid_scenario(4, objects_per_room, 0)
		var us: int = 0
		for i in range(4):
			us += _time_sync()
		print("  %d objetos por sala: %6.1f ms" % [objects_per_room, float(us) / 4.0 / 1000.0])
	for openings in [0, 3, 6]:
		_editor.editor_data = _grid_scenario(4, 0, openings)
		var us2: int = 0
		for i in range(4):
			us2 += _time_sync()
		print("  %d aperturas:        %6.1f ms" % [openings, float(us2) / 4.0 / 1000.0])


## Un piso de cajas en fila: lo que importa es el numero de salas, no su forma.
func _grid_scenario(room_count: int, objects_per_room: int = 0, opening_count: int = 0) -> Dictionary:
	var rooms: Array = []
	var rects: Dictionary = {}
	for i in range(room_count):
		var column: int = i % 4
		var row: int = int(i / 4)
		var objects: Array = []
		for k in range(objects_per_room):
			objects.append({
				"id": "obj_%d_%d" % [i, k],
				"room_id": i,
				"name": "sofa",
				"kind": "sofa",
				"position_m": {"x": 0.4 + k * 0.8, "y": 0.4},
				"size_m": {"x": 0.7, "y": 0.6},
				"rotation_deg": 0.0,
				"fuel_energy_MJ": 100.0,
				"max_hrr_kw": 400.0
			})
		rooms.append({
			"id": i,
			"name": "Sala %d" % i,
			"kind": "generic",
			"rotation_deg": 0.0,
			"height_m": 2.7,
			"floor_level_z_m": 0.0,
			"fuel_objects": objects
		})
		rects[str(i)] = {"x": column * 4.0, "y": row * 3.0, "w": 3.8, "h": 2.8}
	var openings: Array = []
	for i in range(opening_count):
		openings.append({
			"a": i % maxi(1, room_count), "b": -1, "type": "window", "wall": "top",
			"offset_m": 1.0, "offset_is_fraction": false,
			"width_m": 1.0, "height_m": 1.2, "sill_m": 0.9, "open_fraction": 0.0
		})
	return {
		"floors": [{"name": "PB", "level_m": 0.0}],
		"exterior_walls": [],
		"room_rect_m": rects,
		"rooms_data": rooms,
		"openings_data": openings,
		"detectors": [],
		"victims": [],
		"player_start": {},
		"ignition_room_id": -1
	}


func _time_sync() -> int:
	var start_us: int = Time.get_ticks_usec()
	# Solo la vista 3D: es lo que rehace el panel en vivo mientras se dibuja.
	_editor._sync_editor_runtime_views(false)
	return Time.get_ticks_usec() - start_us


func _count_objects(data: Dictionary) -> int:
	var total: int = 0
	for room in data.get("rooms_data", []):
		if typeof(room) == TYPE_DICTIONARY:
			total += Array(Dictionary(room).get("fuel_objects", [])).size()
	return total


func _load_reference() -> Dictionary:
	var path: String = "res://scenarios/compact_apartment_reference.json"
	if FileAccess.file_exists(path):
		var file := FileAccess.open(path, FileAccess.READ)
		if file != null:
			var parsed: Variant = JSON.parse_string(file.get_as_text())
			if typeof(parsed) == TYPE_DICTIONARY:
				return Serializer.normalize_editor_data(parsed)
	print("(no hay escenario de referencia; se mide con uno minimo)")
	return Serializer.normalize_editor_data({
		"floors": [{"name": "PB", "level_m": 0.0}],
		"room_rect_m": {"0": {"x": 0.0, "y": 0.0, "w": 4.0, "h": 3.0}},
		"rooms_data": [{"id": 0, "name": "Salón", "kind": "generic", "height_m": 2.7, "floor_level_z_m": 0.0, "fuel_objects": []}],
		"openings_data": [],
		"detectors": [],
		"victims": [],
		"player_start": {},
		"exterior_walls": []
	})

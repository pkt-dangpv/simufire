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
	quit(0)
	return true


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

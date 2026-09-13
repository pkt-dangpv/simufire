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
const SAMPLES: int = 24
## Pasadas de calentamiento que se tiran: la primera construye nodos que despues
## ya existen, y las siguientes todavia arrastran su reserva de memoria.
const WARMUP: int = 3
## Umbral de un fotograma a 60 Hz.
const FRAME_MS: float = 16.7

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
	_editor.adopt_scenario_data(data, 0)
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
	var band: Dictionary = _measure(SAMPLES)
	print("rehacer la vista 3D: primera %.1f ms, %s" % [first_us / 1000.0, _band_text(band)])
	print("un fotograma a 60 Hz son 16,7 ms")
	_verdict(band)
	_measure_scaling()
	_measure_contents()
	_measure_drag_paths()
	quit(0)
	return true


## ── D-6: medir sin mentir ────────────────────────────────────────────────────
##
## Esta sonda daba **la media de 12 pasadas** y de ahi sacaba un veredicto
## tajante: «cabe / no cabe en un fotograma». La auditoria del 2026-09-09 la
## pillo: cuatro pasadas sobre LA MISMA configuracion dieron 17,5 · 21,9 · 23,6 ·
## 25,4 ms, y esa misma mañana 13,5. Casi **8 ms de dispersion, mas que el efecto
## que se pretendia medir**, y el veredicto salia de una sola pasada.
##
## Dos cosas estaban mal, y son distintas:
##
##  1. **La media no aguanta esta distribucion.** Un paron del recolector o del
##     sistema mete una muestra de 60 ms y arrastra la media entera. La mediana
##     no se entera. Aqui se reporta **mediana con banda p10-p90**, que es la
##     forma de la dispersion, no un numero solo.
##  2. **El veredicto no puede ser mas preciso que la medida.** Ahora solo se da
##     si **toda la banda** cae del mismo lado del fotograma; si la banda cruza
##     los 16,7 ms, la sonda lo dice y no decide. Es exactamente lo que la
##     auditoria reprochaba.
func _measure(count: int) -> Dictionary:
	for i in range(WARMUP):
		_time_sync()
	var samples: Array[int] = []
	for i in range(count):
		samples.append(_time_sync())
	samples.sort()
	return {
		"min_ms": samples[0] / 1000.0,
		"p10_ms": _percentile_ms(samples, 0.10),
		"median_ms": _percentile_ms(samples, 0.50),
		"p90_ms": _percentile_ms(samples, 0.90),
		"max_ms": samples[samples.size() - 1] / 1000.0,
		"n": samples.size(),
	}


func _percentile_ms(sorted_us: Array[int], q: float) -> float:
	if sorted_us.is_empty():
		return 0.0
	var index: int = clampi(int(round(q * float(sorted_us.size() - 1))), 0, sorted_us.size() - 1)
	return sorted_us[index] / 1000.0


func _band_text(band: Dictionary) -> String:
	return "mediana %.1f ms (p10-p90 %.1f-%.1f, peor %.1f, n=%d)" % [
		band["median_ms"], band["p10_ms"], band["p90_ms"], band["max_ms"], band["n"]
	]


## El veredicto, solo cuando la medida lo sostiene.
func _verdict(band: Dictionary) -> void:
	var low: float = float(band["p10_ms"])
	var high: float = float(band["p90_ms"])
	if low <= FRAME_MS and high > FRAME_MS:
		print("-> la banda cruza el fotograma (%.1f-%.1f ms): ESTA MEDIDA NO DECIDE." % [low, high])
		print("   Para decidir hace falta bajar la dispersion, no repetir la sonda hasta que salga el numero que gusta.")
		return
	if high <= FRAME_MS:
		print("-> cabe en un fotograma en toda la banda: se puede rehacer mientras se arrastra")
	elif float(band["median_ms"]) <= 120.0:
		print("-> no cabe en un fotograma, pero si en una pausa corta: rehacer al soltar y con retardo mientras se arrastra")
	else:
		print("-> demasiado caro para el tiempo real: haria falta actualizacion incremental")


## Comparar dos configuraciones: la diferencia solo se afirma si las bandas no
## se solapan. Es lo que salva la *forma* -el coste crece con las salas- de la
## misma trampa que se llevo por delante la cifra absoluta.
func _compare_text(previous: Dictionary, current: Dictionary) -> String:
	if previous.is_empty():
		return ""
	var delta: float = float(current["median_ms"]) - float(previous["median_ms"])
	var overlap: bool = float(current["p10_ms"]) <= float(previous["p90_ms"])
	if overlap:
		return "  (%+.1f ms, dentro del ruido)" % delta
	return "  (%+.1f ms)" % delta


## El coste, sala a sala: con esto se sabe si rehacer UNA sala sale a cuenta.
##
## Si casi todo es coste por sala, rehacer solo la que se esta moviendo divide el
## tiempo por el numero de salas. Si hay mucho coste fijo, el incremental apenas
## nota.
func _measure_scaling() -> void:
	print("")
	print("coste por tamaño del piso:")
	var previous: Dictionary = {}
	for room_count in [1, 2, 4, 8, 16]:
		_editor.adopt_scenario_data(_grid_scenario(room_count))
		var band: Dictionary = _measure(8)
		print("  %2d salas: %s%s" % [room_count, _band_text(band), _compare_text(previous, band)])
		previous = band


## Los dos caminos que hacen falta para que el 3D siga al raton:
##
##  - arrastrando PAREDES no hacen falta los muebles: se apagan y se rehace.
##  - arrastrando un OBJETO no hace falta rehacer nada: basta recargar el modelo
##    y dejar que el visor recoloque las piezas que ya existen.
func _measure_drag_paths() -> void:
	print("")
	print("caminos para seguir al raton (piso de referencia):")
	_editor.adopt_scenario_data(_load_reference())
	var viz: Node = _editor._editor_visualizer_3d
	_time_sync()

	viz.show_fuel_objects_3d = false
	var walls: Dictionary = _measure(8)
	print("  rehacer sin muebles:   %s" % _band_text(walls))
	viz.show_fuel_objects_3d = true

	# Este camino no es _time_sync(): no rehace la malla, recoloca lo que ya
	# existe. Se mide aparte y con el mismo trato estadistico.
	for i in range(WARMUP):
		_relocate_once()
	var relocate: Array[int] = []
	for i in range(8):
		relocate.append(_relocate_once())
	relocate.sort()
	var relocate_band: Dictionary = {
		"min_ms": relocate[0] / 1000.0,
		"p10_ms": _percentile_ms(relocate, 0.10),
		"median_ms": _percentile_ms(relocate, 0.50),
		"p90_ms": _percentile_ms(relocate, 0.90),
		"max_ms": relocate[relocate.size() - 1] / 1000.0,
		"n": relocate.size(),
	}
	print("  recolocar sin rehacer: %s" % _band_text(relocate_band))
	var full: Dictionary = _measure(8)
	print("  rehacer entero (hoy):  %s%s" % [_band_text(full), _compare_text(walls, full)])


func _relocate_once() -> int:
	var start_us: int = Time.get_ticks_usec()
	var runtime: Dictionary = Serializer.to_runtime_template(_editor.editor_data)
	_editor._editor_building_model.load_template_data(runtime, true)
	_editor._editor_visualizer_3d.set_state({})
	return Time.get_ticks_usec() - start_us


## Y ahora la otra pregunta: si las salas cuestan 2 ms, ¿de donde salen los 80 ms
## del piso de referencia? Se prueba con muebles y con aperturas por separado.
func _measure_contents() -> void:
	print("")
	print("coste del contenido (4 salas fijas):")
	var previous: Dictionary = {}
	for objects_per_room in [0, 1, 3, 6]:
		_editor.adopt_scenario_data(_grid_scenario(4, objects_per_room, 0))
		var band: Dictionary = _measure(8)
		print("  %d objetos por sala: %s%s" % [objects_per_room, _band_text(band), _compare_text(previous, band)])
		previous = band
	previous = {}
	for openings in [0, 3, 6]:
		_editor.adopt_scenario_data(_grid_scenario(4, 0, openings))
		var band2: Dictionary = _measure(8)
		print("  %d aperturas:        %s%s" % [openings, _band_text(band2), _compare_text(previous, band2)])
		previous = band2


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

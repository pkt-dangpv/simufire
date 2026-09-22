extends SceneTree

## F2.2D4A: contrato persistente de la fisica prescrita de puertas y vidrio.
##
##   <godot> --headless --path . --script \
##       res://tools/validate_prescribed_physics_persistence.gd
##
## Lo que se demuestra aqui:
##   01 un escenario anterior a D4A no gana ninguna clave y carga igual;
##   02 ida y vuelta de D1, D2 y D3 sin perdida numerica;
##   03 ida y vuelta repetida, byte a byte;
##   04 abrir y cerrar una puerta no borra su carpinteria;
##   05 guardar y cargar no enciende ningun interruptor;
##   06 las historias conservan orden, instantes y geometria;
##   07 el paño multicapa conserva identidad y colocacion;
##   08 los datos invalidos se rechazan de forma explicita;
##   09 las claves desconocidas se conservan;
##   10 con D1, D2 y D3 apagadas el motor es identico con y sin declaraciones;
##   11 no aparece ninguna ruta nueva de caudal ni de transporte.

const BuildingModelScript := preload("res://sim/BuildingModel.gd")
const SimulationEngineScript := preload("res://sim/core/SimulationEngine.gd")
const Serializer := preload("res://editor/ScenarioSerializer.gd")
const Schema := preload("res://sim/building/PrescribedOpeningPhysicsSchema.gd")
const TransportScript := preload("res://sim/core/PressureNetworkTransportSystem.gd")

const WORK_DIR: String = "user://prescribed_physics_persistence"
## Identidad exacta: mayusculas y espacios exteriores cuentan.
const MIXED_PANEL_ID: String = " Pane_Mixed "

var _failures: Array[String] = []
var _checks: int = 0


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(WORK_DIR))
	_test_01_legacy_scenario_gains_nothing()
	_test_02_round_trip_is_numerically_exact()
	_test_03_round_trip_is_byte_stable()
	_test_04_operational_state_keeps_the_carpentry()
	_test_05_persistence_never_flips_a_switch()
	_test_06_histories_keep_order_times_and_geometry()
	_test_07_multilayer_panel_keeps_identity_and_placement()
	_test_08_invalid_data_is_rejected()
	_test_09_unknown_keys_are_preserved()
	_test_10_off_identity_against_the_engine()
	_test_11_no_new_flow_or_transport_route()
	if _failures.is_empty():
		print("  %d checks" % _checks)
		print("PRESCRIBED PHYSICS PERSISTENCE VALIDATION PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
		print("FAIL: " + failure)
	print("PRESCRIBED PHYSICS PERSISTENCE VALIDATION FAIL (%d)" % _failures.size())
	quit(1)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


# ------------------------------------------------------------
# Datos de prueba
# ------------------------------------------------------------

## Pistas de deformacion prescritas. Valores deliberadamente NO calibrados: solo
## prueban el contrato de persistencia, no una puerta residencial real.
func _deformation_tracks() -> Array:
	return [
		{
			"id": "top",
			"location": "top",
			"z_m": 1.95,
			"points": [[0.0, 0.0], [60.0, 0.0005], [120.0, 0.003], [300.0, 0.0025]],
			"metadata": {"source": "prieler_topology_only", "calibrated": false},
		},
		{
			"id": "latch_side_03",
			"location": "latch_side",
			"z_m": 1.05,
			"points": [[0.0, 0.0], [90.0, 0.00025], [180.0, 0.001]],
		},
	]


## Paño de dos hojas con historia de integridad por hoja. `host_x_m` lo coloca
## dentro del hueco anfitrion; `sill_z_m` es local a la base de la abertura.
func _glazing_panels() -> Array:
	return [
		{
			"id": "pane_upper",
			"host_x_m": 0.15,
			"width_m": 0.6,
			"height_m": 0.5,
			"sill_z_m": 1.2,
			"glass_type": "annealed",
			"thickness_m": 0.004,
			"leaf_count": 2,
			"leaf_spacing_m": 0.012,
			"frame_material": "wood",
			"edge_protection_depth_m": 0.01,
			"metadata": {"provenance": "prescribed_only"},
			"leaves": [
				{
					"id": "leaf_0",
					"index": 0,
					"events": [
						{"time_s": 0.0, "state": "INTACT", "fallout_fraction": 0.0},
						{"time_s": 120.0, "state": "CRACKED", "fallout_fraction": 0.0},
						{"time_s": 180.0, "state": "PARTIAL_FALLOUT", "fallout_fraction": 0.25},
					],
				},
				{
					"id": "leaf_1",
					"index": 1,
					"events": [
						{"time_s": 0.0, "state": "INTACT", "fallout_fraction": 0.0},
						{"time_s": 150.0, "state": "CRACKED", "fallout_fraction": 0.0},
						{"time_s": 180.0, "state": "PARTIAL_FALLOUT", "fallout_fraction": 0.5},
					],
				},
			],
		},
		# Identidad EXACTA (§15.2.1 del diseño de D3): mayusculas y espacios
		# exteriores forman parte del identificador y no se normalizan. Si la
		# persistencia los recortara, este paño dejaria de emparejar con su
		# entrada espacial.
		{
			"id": MIXED_PANEL_ID,
			"host_x_m": 0.15,
			"width_m": 0.6,
			"height_m": 0.5,
			"sill_z_m": 0.4,
			"glass_type": "laminated",
			"thickness_m": 0.006,
			"leaf_count": 1,
			"leaf_spacing_m": 0.0,
			"frame_material": "aluminium",
			"edge_protection_depth_m": 0.012,
			"leaves": [
				{
					"id": " Leaf_A ",
					"index": 0,
					"events": [
						{"time_s": 0.0, "state": "INTACT", "fallout_fraction": 0.0},
					],
				},
			],
		},
	]


## Instantaneas espaciales. La de 180 s da a la hoja 0 un cuarto del paño y a la
## hoja 1 la mitad, con solape parcial: el camino libre es la INTERSECCION.
func _glazing_spatial() -> Array:
	return [
		{
			"panel_id": "pane_upper",
			"snapshots": [
				{
					"time_s": 0.0,
					"leaves": [
						{"id": "leaf_0", "index": 0, "regions": []},
						{"id": "leaf_1", "index": 1, "regions": []},
					],
				},
				{
					"time_s": 120.0,
					"leaves": [
						{"id": "leaf_0", "index": 0, "regions": []},
						{"id": "leaf_1", "index": 1, "regions": []},
					],
				},
				{
					"time_s": 150.0,
					"leaves": [
						{"id": "leaf_0", "index": 0, "regions": []},
						{"id": "leaf_1", "index": 1, "regions": []},
					],
				},
				{
					"time_s": 180.0,
					"leaves": [
						{
							"id": "leaf_0",
							"index": 0,
							"regions": [
								{"id": "r0", "x_m": 0.0, "z_m": 0.25, "width_m": 0.3, "height_m": 0.25},
							],
						},
						{
							"id": "leaf_1",
							"index": 1,
							"regions": [
								{"id": "r0", "x_m": 0.0, "z_m": 0.0, "width_m": 0.3, "height_m": 0.5},
							],
						},
					],
				},
			],
		},
		{
			"panel_id": MIXED_PANEL_ID,
			"snapshots": [
				{
					"time_s": 0.0,
					"leaves": [{"id": " Leaf_A ", "index": 0, "regions": []}],
				},
			],
		},
	]


func _editor_data(with_prescribed: bool) -> Dictionary:
	var door: Dictionary = {
		"a": 0,
		"b": 1,
		"type": "door",
		"wall": "right",
		"width_m": 0.9,
		"height_m": 2.05,
		"sill_m": 0.0,
		"open_fraction": 0.0,
	}
	if with_prescribed:
		door["leakage_class"] = "interior_tight"
		door[Schema.SCHEMA_KEY] = Schema.SCHEMA_VERSION
		door[Schema.DEFORMATION_KEY] = _deformation_tracks()
		door[Schema.PANELS_KEY] = _glazing_panels()
		door[Schema.SPATIAL_KEY] = _glazing_spatial()
	return {
		"version": 1,
		"building_type": "single_family",
		"outside_temp_c": 20.0,
		"outside_o2": 0.209,
		"stop_time_s": 0.0,
		"ignition_room_id": 0,
		"hvac_mode": "none",
		"interior_lights_on": true,
		"exterior_lighting_mode": "Dia",
		"floors": [{"name": "PB", "level_m": 0.0}],
		"room_rect_m": {
			"0": {"x": 0.0, "y": 0.0, "w": 4.0, "h": 4.0},
			"1": {"x": 4.0, "y": 0.0, "w": 4.0, "h": 4.0},
		},
		"rooms_data": [
			{
				"id": 0,
				"name": "Salon",
				"kind": "salon",
				"height_m": 2.5,
				"floor_level_z_m": 0.0,
				"fuel_energy_MJ": 300.0,
				"max_hrr_kw": 400.0,
				"fuel_objects": [
					{
						"id": "sofa",
						"name": "Sofa",
						"kind": "sofa",
						"room_id": 0,
						"position_m": {"x": 1.5, "y": 1.5},
						"size_m": {"x": 1.7, "y": 0.85},
						"footprint_m2": 1.45,
						"fuel_energy_MJ": 300.0,
						"max_hrr_kw": 400.0,
						"is_primary_ignition_source": true,
					}
				],
			},
			{
				"id": 1,
				"name": "Dormitorio",
				"kind": "dormitorio",
				"height_m": 2.5,
				"floor_level_z_m": 0.0,
				"fuel_energy_MJ": 0.0,
				"max_hrr_kw": 0.0,
				"fuel_objects": [],
			},
		],
		"openings_data": [door],
		"detectors": [],
		"victims": [],
		"player_start": {},
		"exterior_walls": [],
	}


# ------------------------------------------------------------
# 01 escenario antiguo
# ------------------------------------------------------------

func _test_01_legacy_scenario_gains_nothing() -> void:
	var legacy: Dictionary = _editor_data(false)
	var normalized: Dictionary = Serializer.normalize_editor_data(legacy)
	var door: Dictionary = Array(normalized["openings_data"])[0]
	_check(not door.has(Schema.SCHEMA_KEY), "01 legacy opening gained the schema key")
	for key in Schema.PAYLOAD_KEYS:
		_check(not door.has(key), "01 legacy opening gained '%s'" % key)
	_check(not Schema.declares(door), "01 legacy opening declares prescribed physics")
	_check(Schema.validate(door, 0).is_empty(), "01 legacy opening failed validation")

	# Una lista vacia es exactamente "sin datos": se borra al normalizar.
	var empty_door: Dictionary = Dictionary(door).duplicate(true)
	for key in Schema.PAYLOAD_KEYS:
		empty_door[key] = []
	Schema.normalize(empty_door)
	for key in Schema.PAYLOAD_KEYS:
		_check(not empty_door.has(key), "01 an empty '%s' survived normalization" % key)
	_check(not empty_door.has(Schema.SCHEMA_KEY), "01 empty lists left a dangling version")

	var building = BuildingModelScript.new()
	_check(building.load_template_data(Serializer.to_runtime_template(legacy)),
			"01 legacy scenario no longer loads")
	var opening = _single_opening(building, "01")
	if opening == null:
		building.free()
		return
	_check(Array(opening.deformation_tracks).is_empty(), "01 legacy door invented tracks")
	_check(Array(opening.glazing_panels).is_empty(), "01 legacy door invented panels")
	_check(Array(opening.glazing_spatial).is_empty(), "01 legacy door invented spatial input")
	_check(String(opening.leakage_class) == "none", "01 legacy door invented a leakage class")
	building.free()


# ------------------------------------------------------------
# 02 ida y vuelta exacta
# ------------------------------------------------------------

func _test_02_round_trip_is_numerically_exact() -> void:
	var path: String = WORK_DIR + "/round_trip.json"
	var source: Dictionary = _editor_data(true)
	_check(Serializer.save_scenario(path, source), "02 the scenario could not be saved")
	var loaded: Dictionary = Serializer.load_scenario(path)
	_check(not loaded.is_empty(), "02 the scenario could not be loaded")
	var door: Dictionary = Array(loaded["openings_data"])[0]
	var original: Dictionary = Array(source["openings_data"])[0]
	if not _has_payload(door, "02"):
		return

	_check(int(door.get(Schema.SCHEMA_KEY, -1)) == Schema.SCHEMA_VERSION,
			"02 the schema version did not survive")
	_check(String(door.get("leakage_class", "")) == "interior_tight",
			"02 the D1 leakage class did not survive")
	for key in Schema.PAYLOAD_KEYS:
		_check(_deep_equal(door.get(key, null), original.get(key, null)),
				"02 '%s' did not survive the file exactly" % key)
	_check(Schema.validate(door, 0).is_empty(), "02 the round-tripped door failed validation")

	# La misma exactitud, ya dentro del motor.
	var template: Dictionary = Serializer.to_runtime_template(loaded)
	var building = BuildingModelScript.new()
	_check(building.load_template_data(template), "02 the round-tripped scenario did not load")
	var opening = _single_opening(building, "02")
	if opening == null:
		building.free()
		return
	if not _engine_payload_complete(opening, "02"):
		building.free()
		return
	_check(_deep_equal(opening.deformation_tracks, original[Schema.DEFORMATION_KEY]),
			"02 the tracks reached the engine altered")
	_check(_deep_equal(opening.glazing_panels, original[Schema.PANELS_KEY]),
			"02 the panels reached the engine altered")
	_check(_deep_equal(opening.glazing_spatial, original[Schema.SPATIAL_KEY]),
			"02 the spatial history reached the engine altered")
	# Copia profunda: la abertura cargada NO puede compartir memoria con el
	# diccionario del escenario del que salio, o el motor lo reescribiria.
	var template_door: Dictionary = Array(template["openings_data"])[0]
	Array(opening.deformation_tracks)[0]["z_m"] = -99.0
	Dictionary(Array(opening.glazing_panels)[0])["id"] = "mutated"
	Dictionary(Array(Dictionary(Array(opening.glazing_spatial)[0])["snapshots"])[0])["time_s"] = -1.0
	_check(float(Dictionary(Array(template_door[Schema.DEFORMATION_KEY])[0])["z_m"]) == 1.95,
			"02 the engine aliases the scenario track dictionary")
	_check(String(Dictionary(Array(template_door[Schema.PANELS_KEY])[0])["id"]) == "pane_upper",
			"02 the engine aliases the scenario panel dictionary")
	_check(float(Dictionary(Array(Dictionary(Array(template_door[Schema.SPATIAL_KEY])[0])
			["snapshots"])[0])["time_s"]) == 0.0,
			"02 the engine aliases the scenario spatial dictionary")
	building.free()


# ------------------------------------------------------------
# 03 estabilidad byte a byte
# ------------------------------------------------------------

func _test_03_round_trip_is_byte_stable() -> void:
	var first_path: String = WORK_DIR + "/stable_1.json"
	var second_path: String = WORK_DIR + "/stable_2.json"
	var third_path: String = WORK_DIR + "/stable_3.json"
	_check(Serializer.save_scenario(first_path, _editor_data(true)), "03 first save failed")
	_check(Serializer.save_scenario(second_path, Serializer.load_scenario(first_path)),
			"03 second save failed")
	_check(Serializer.save_scenario(third_path, Serializer.load_scenario(second_path)),
			"03 third save failed")
	var first: PackedByteArray = FileAccess.get_file_as_bytes(first_path)
	var second: PackedByteArray = FileAccess.get_file_as_bytes(second_path)
	var third: PackedByteArray = FileAccess.get_file_as_bytes(third_path)
	_check(first.size() > 0, "03 the saved scenario is empty")
	_check(first == second, "03 saving a loaded scenario is not byte-stable")
	_check(second == third, "03 the file drifts on the second round trip")

	# Un escenario legado tambien tiene que ser estable, y sin claves nuevas.
	var legacy_path: String = WORK_DIR + "/legacy_1.json"
	var legacy_again: String = WORK_DIR + "/legacy_2.json"
	_check(Serializer.save_scenario(legacy_path, _editor_data(false)), "03 legacy save failed")
	_check(Serializer.save_scenario(legacy_again, Serializer.load_scenario(legacy_path)),
			"03 legacy re-save failed")
	var legacy_text: String = FileAccess.get_file_as_string(legacy_path)
	_check(FileAccess.get_file_as_bytes(legacy_path) == FileAccess.get_file_as_bytes(legacy_again),
			"03 a legacy scenario is not byte-stable")
	_check(not legacy_text.contains(Schema.SCHEMA_KEY),
			"03 a legacy scenario file gained the schema key")
	for key in Schema.PAYLOAD_KEYS:
		_check(not legacy_text.contains(key), "03 a legacy scenario file gained '%s'" % key)


# ------------------------------------------------------------
# 04 estado operativo frente a carpinteria
# ------------------------------------------------------------

func _test_04_operational_state_keeps_the_carpentry() -> void:
	var data: Dictionary = _editor_data(true)
	var door: Dictionary = Array(data["openings_data"])[0]
	for fraction in [1.0, 0.5, 0.0, 1.0]:
		door["open_fraction"] = fraction
		var normalized: Dictionary = Serializer.normalize_editor_data(data)
		var result: Dictionary = Array(normalized["openings_data"])[0]
		_check(float(result["open_fraction"]) == fraction,
				"04 the operational state was not preserved at %f" % fraction)
		_check(String(result.get("leakage_class", "")) == "interior_tight",
				"04 opening the door erased its leakage class")
		_check(int(result.get(Schema.SCHEMA_KEY, -1)) == Schema.SCHEMA_VERSION,
				"04 opening the door erased the schema version")
		for key in Schema.PAYLOAD_KEYS:
			_check(_deep_equal(result.get(key, null), door.get(key, null)),
					"04 opening the door altered '%s'" % key)
		# Una puerta abierta conserva su carpinteria y el contrato la acepta:
		# que la fisica exija puerta cerrada es cosa del paso, no del fichero.
		_check(Schema.validate(result, 0).is_empty(),
				"04 an operationally open door was rejected at %f" % fraction)


# ------------------------------------------------------------
# 05 ningun interruptor
# ------------------------------------------------------------

func _test_05_persistence_never_flips_a_switch() -> void:
	var path: String = WORK_DIR + "/switches.json"
	_check(Serializer.save_scenario(path, _editor_data(true)), "05 the scenario could not be saved")
	var text: String = FileAccess.get_file_as_string(path)
	for flag in [
		"closed_door_leakage_enabled",
		"closed_door_deformation_enabled",
		"glazing_fallout_enabled",
		"pressure_network_solver_enabled",
		"exterior_envelope_leakage_enabled",
	]:
		_check(not text.contains(flag), "05 the scenario file carries '%s'" % flag)

	var building = BuildingModelScript.new()
	_check(building.load_template_data(Serializer.to_runtime_template(
			Serializer.load_scenario(path))), "05 the scenario did not load")
	var engine = SimulationEngineScript.new()
	engine.name = "PrescribedPersistenceSwitches"
	engine.building = building
	root.add_child(building)
	root.add_child(engine)
	_check(not bool(engine.pressure_network_solver_enabled), "05 the network switched itself on")
	_check(not bool(engine.closed_door_leakage_enabled), "05 D1 switched itself on")
	_check(not bool(engine.closed_door_deformation_enabled), "05 D2 switched itself on")
	_check(not bool(engine.glazing_fallout_enabled), "05 D3 switched itself on")
	_check(not bool(engine.exterior_envelope_leakage_enabled), "05 R3 switched itself on")
	var transport = engine.pressure_network_transport_system
	_check(transport != null, "05 the transport system is missing")
	if transport != null:
		_check(not bool(transport.closed_door_leakage_enabled), "05 D1 reached the transport ON")
		_check(not bool(transport.closed_door_deformation_enabled), "05 D2 reached the transport ON")
		_check(not bool(transport.glazing_fallout_enabled), "05 D3 reached the transport ON")
	root.remove_child(engine)
	root.remove_child(building)
	engine.free()
	building.free()


# ------------------------------------------------------------
# 06 orden, instantes y geometria
# ------------------------------------------------------------

func _test_06_histories_keep_order_times_and_geometry() -> void:
	var path: String = WORK_DIR + "/histories.json"
	_check(Serializer.save_scenario(path, _editor_data(true)), "06 the scenario could not be saved")
	var door: Dictionary = Array(Serializer.load_scenario(path)["openings_data"])[0]
	if not _has_payload(door, "06"):
		return

	var tracks: Array = Array(door[Schema.DEFORMATION_KEY])
	_check(tracks.size() == 2, "06 a deformation track was lost")
	_check(String(Dictionary(tracks[0])["id"]) == "top", "06 the track order changed")
	_check(String(Dictionary(tracks[1])["id"]) == "latch_side_03", "06 the track order changed")
	var points: Array = Array(Dictionary(tracks[0])["points"])
	_check(points.size() == 4, "06 a track point was lost")
	var expected_points: Array = [[0.0, 0.0], [60.0, 0.0005], [120.0, 0.003], [300.0, 0.0025]]
	for i in range(expected_points.size()):
		var point: Array = Array(points[i])
		_check(float(point[0]) == float(Array(expected_points[i])[0]),
				"06 track time %d drifted" % i)
		_check(float(point[1]) == float(Array(expected_points[i])[1]),
				"06 track area %d drifted" % i)
	_check(Dictionary(tracks[0]).has("metadata"), "06 the track provenance was dropped")

	var snapshots: Array = Array(Dictionary(Array(door[Schema.SPATIAL_KEY])[0])["snapshots"])
	_check(snapshots.size() == 4, "06 a spatial snapshot was lost")
	var expected_times: Array = [0.0, 120.0, 150.0, 180.0]
	for i in range(expected_times.size()):
		_check(float(Dictionary(snapshots[i])["time_s"]) == float(expected_times[i]),
				"06 spatial snapshot time %d drifted" % i)
	var region: Dictionary = Array(Dictionary(Array(
			Dictionary(snapshots[3])["leaves"])[0])["regions"])[0]
	_check(String(region["id"]) == "r0", "06 the region identity changed")
	_check(float(region["x_m"]) == 0.0 and float(region["z_m"]) == 0.25,
			"06 the region position drifted")
	_check(float(region["width_m"]) == 0.3 and float(region["height_m"]) == 0.25,
			"06 the region size drifted")

	# Un evento sin su instantanea espacial es una historia ambigua.
	var ambiguous: Dictionary = _editor_data(true)
	var ambiguous_door: Dictionary = Array(ambiguous["openings_data"])[0]
	var spatial: Array = Array(ambiguous_door[Schema.SPATIAL_KEY]).duplicate(true)
	Array(Dictionary(spatial[0])["snapshots"]).remove_at(3)
	ambiguous_door[Schema.SPATIAL_KEY] = spatial
	_check(not Schema.validate(ambiguous_door, 0).is_empty(),
			"06 an event without its spatial snapshot was accepted")


# ------------------------------------------------------------
# 07 paño multicapa
# ------------------------------------------------------------

func _test_07_multilayer_panel_keeps_identity_and_placement() -> void:
	var path: String = WORK_DIR + "/multilayer.json"
	_check(Serializer.save_scenario(path, _editor_data(true)), "07 the scenario could not be saved")
	var door: Dictionary = Array(Serializer.load_scenario(path)["openings_data"])[0]
	if not _has_payload(door, "07"):
		return
	var panel: Dictionary = Array(door[Schema.PANELS_KEY])[0]
	_check(String(panel["id"]) == "pane_upper", "07 the panel identity changed")
	_check(int(panel["leaf_count"]) == 2, "07 the leaf count changed")
	_check(float(panel["leaf_spacing_m"]) == 0.012, "07 the leaf spacing drifted")
	_check(String(panel["glass_type"]) == "annealed", "07 the glass type changed")
	_check(float(panel["thickness_m"]) == 0.004, "07 the thickness drifted")
	_check(String(panel["frame_material"]) == "wood", "07 the frame material changed")
	_check(float(panel["edge_protection_depth_m"]) == 0.01, "07 the edge protection drifted")
	_check(float(panel["host_x_m"]) == 0.15, "07 the panel placement drifted")
	_check(float(panel["sill_z_m"]) == 1.2, "07 the panel sill drifted")
	_check(float(panel["width_m"]) == 0.6 and float(panel["height_m"]) == 0.5,
			"07 the panel size drifted")
	var leaves: Array = Array(panel["leaves"])
	_check(leaves.size() == 2, "07 a leaf was lost")
	_check(String(Dictionary(leaves[0])["id"]) == "leaf_0"
			and int(Dictionary(leaves[0])["index"]) == 0, "07 leaf 0 identity changed")
	_check(String(Dictionary(leaves[1])["id"]) == "leaf_1"
			and int(Dictionary(leaves[1])["index"]) == 1, "07 leaf 1 identity changed")
	var events: Array = Array(Dictionary(leaves[1])["events"])
	_check(events.size() == 3, "07 a leaf event was lost")
	_check(String(Dictionary(events[2])["state"]) == "PARTIAL_FALLOUT",
			"07 the leaf state changed")
	_check(float(Dictionary(events[2])["fallout_fraction"]) == 0.5,
			"07 the fallout fraction drifted")

	# La identidad de la abertura anfitriona es el indice canonico del edificio.
	var building = BuildingModelScript.new()
	_check(building.load_template_data(Serializer.to_runtime_template(
			Serializer.load_scenario(path))), "07 the scenario did not load")
	var opening = _single_opening(building, "07")
	if opening == null:
		building.free()
		return
	_check(int(opening.opening_index) == 0, "07 the opening index is not stable")
	if _engine_payload_complete(opening, "07"):
		_check(String(Dictionary(Array(opening.glazing_panels)[0])["id"]) == "pane_upper",
				"07 the panel identity changed inside the engine")
		_check(String(Dictionary(Array(opening.glazing_panels)[1])["id"]) == MIXED_PANEL_ID,
				"07 the exact panel identity was normalized away inside the engine")
		_check(String(Dictionary(Array(Array(opening.glazing_panels)[1]["leaves"])[0])["id"])
				== " Leaf_A ", "07 the exact leaf identity was normalized away")
		_check(String(Dictionary(Array(opening.glazing_spatial)[1])["panel_id"]) == MIXED_PANEL_ID,
				"07 the spatial panel identity was normalized away")
	building.free()


# ------------------------------------------------------------
# 08 rechazos explicitos
# ------------------------------------------------------------

func _test_08_invalid_data_is_rejected() -> void:
	_reject("08 a non-finite track area", func(door: Dictionary) -> void:
		var tracks: Array = Array(door[Schema.DEFORMATION_KEY]).duplicate(true)
		Array(Dictionary(tracks[0])["points"])[1] = [60.0, INF]
		door[Schema.DEFORMATION_KEY] = tracks)
	_reject("08 a negative track area", func(door: Dictionary) -> void:
		var tracks: Array = Array(door[Schema.DEFORMATION_KEY]).duplicate(true)
		Array(Dictionary(tracks[0])["points"])[1] = [60.0, -0.001]
		door[Schema.DEFORMATION_KEY] = tracks)
	_reject("08 out-of-order track times", func(door: Dictionary) -> void:
		var tracks: Array = Array(door[Schema.DEFORMATION_KEY]).duplicate(true)
		Array(Dictionary(tracks[0])["points"])[2] = [10.0, 0.003]
		door[Schema.DEFORMATION_KEY] = tracks)
	_reject("08 an unknown track location", func(door: Dictionary) -> void:
		var tracks: Array = Array(door[Schema.DEFORMATION_KEY]).duplicate(true)
		Dictionary(tracks[0])["location"] = "middle"
		door[Schema.DEFORMATION_KEY] = tracks)
	_reject("08 deformation tracks on a window", func(door: Dictionary) -> void:
		door["type"] = "window"
		door.erase(Schema.PANELS_KEY)
		door.erase(Schema.SPATIAL_KEY))
	_reject("08 deformation tracks against the exterior", func(door: Dictionary) -> void:
		door["b"] = -1
		door.erase(Schema.PANELS_KEY)
		door.erase(Schema.SPATIAL_KEY))
	_reject("08 out-of-order spatial times", func(door: Dictionary) -> void:
		var spatial: Array = Array(door[Schema.SPATIAL_KEY]).duplicate(true)
		Dictionary(Array(Dictionary(spatial[0])["snapshots"])[2])["time_s"] = 10.0
		door[Schema.SPATIAL_KEY] = spatial)
	_reject("08 an unknown glass type", func(door: Dictionary) -> void:
		var panels: Array = Array(door[Schema.PANELS_KEY]).duplicate(true)
		Dictionary(panels[0])["glass_type"] = "gorilla"
		door[Schema.PANELS_KEY] = panels)
	_reject("08 a panel outside the host opening", func(door: Dictionary) -> void:
		var panels: Array = Array(door[Schema.PANELS_KEY]).duplicate(true)
		Dictionary(panels[0])["host_x_m"] = 0.8
		door[Schema.PANELS_KEY] = panels)
	_reject("08 a panel above the host lintel", func(door: Dictionary) -> void:
		var panels: Array = Array(door[Schema.PANELS_KEY]).duplicate(true)
		Dictionary(panels[0])["sill_z_m"] = 1.9
		door[Schema.PANELS_KEY] = panels)
	_reject("08 overlapping panels", func(door: Dictionary) -> void:
		var panels: Array = Array(door[Schema.PANELS_KEY]).duplicate(true)
		var clone: Dictionary = Dictionary(panels[0]).duplicate(true)
		clone["id"] = "pane_clone"
		clone["host_x_m"] = 0.3
		panels.append(clone)
		door[Schema.PANELS_KEY] = panels
		var spatial: Array = Array(door[Schema.SPATIAL_KEY]).duplicate(true)
		var spatial_clone: Dictionary = Dictionary(spatial[0]).duplicate(true)
		spatial_clone["panel_id"] = "pane_clone"
		spatial.append(spatial_clone)
		door[Schema.SPATIAL_KEY] = spatial)
	_reject("08 a region outside its panel", func(door: Dictionary) -> void:
		var spatial: Array = Array(door[Schema.SPATIAL_KEY]).duplicate(true)
		var region: Dictionary = Array(Dictionary(Array(Dictionary(
				Array(Dictionary(spatial[0])["snapshots"])[3])["leaves"])[0])["regions"])[0]
		region["width_m"] = 0.9
		door[Schema.SPATIAL_KEY] = spatial)
	_reject("08 spatial input without panels", func(door: Dictionary) -> void:
		door.erase(Schema.PANELS_KEY))
	_reject("08 panels without spatial input", func(door: Dictionary) -> void:
		door.erase(Schema.SPATIAL_KEY))
	_reject("08 an unsupported schema version", func(door: Dictionary) -> void:
		door[Schema.SCHEMA_KEY] = Schema.SCHEMA_VERSION + 1)
	_reject("08 prescribed data without a schema version", func(door: Dictionary) -> void:
		door.erase(Schema.SCHEMA_KEY))
	_reject("08 a schema version without prescribed data", func(door: Dictionary) -> void:
		for key in Schema.PAYLOAD_KEYS:
			door.erase(key))
	_reject("08 a payload key that is not an array", func(door: Dictionary) -> void:
		door[Schema.DEFORMATION_KEY] = {"id": "top"})
	# El defecto de representacion encontrado en D4A: un doble que el fichero no
	# devuelve exacto se RECHAZA en vez de guardarse redondeado en silencio.
	_reject("08 a double the file cannot represent exactly", func(door: Dictionary) -> void:
		var tracks: Array = Array(door[Schema.DEFORMATION_KEY]).duplicate(true)
		Array(Dictionary(tracks[0])["points"])[1] = [60.0, 1.0 / 3.0]
		door[Schema.DEFORMATION_KEY] = tracks)
	_reject("08 a magnitude the file flushes to zero", func(door: Dictionary) -> void:
		var tracks: Array = Array(door[Schema.DEFORMATION_KEY]).duplicate(true)
		Array(Dictionary(tracks[0])["points"])[1] = [60.0, 1e-300]
		door[Schema.DEFORMATION_KEY] = tracks)
	# Solo la comprobacion de representabilidad ve esto: los modelos puros
	# conservan los metadatos como procedencia y no los miran. Un infinito ahi
	# dentro dejaria el fichero sin poder volver a leerse.
	_reject("08 a non-finite number inside inert provenance", func(door: Dictionary) -> void:
		var tracks: Array = Array(door[Schema.DEFORMATION_KEY]).duplicate(true)
		Dictionary(tracks[0])["metadata"] = {"measured_gap_mm": INF}
		door[Schema.DEFORMATION_KEY] = tracks)
	# Un campo entero que no lo es NO se trunca en silencio.
	_reject("08 a fractional leaf count", func(door: Dictionary) -> void:
		var panels: Array = Array(door[Schema.PANELS_KEY]).duplicate(true)
		Dictionary(panels[0])["leaf_count"] = 2.5
		door[Schema.PANELS_KEY] = panels)
	_reject("08 a fractional leaf index", func(door: Dictionary) -> void:
		var panels: Array = Array(door[Schema.PANELS_KEY]).duplicate(true)
		Dictionary(Array(Dictionary(panels[0])["leaves"])[1])["index"] = 1.5
		door[Schema.PANELS_KEY] = panels)
	# La clase de fuga es de D1 y su dueño sigue siendo `BuildingModel`: el
	# esquema de D4A no la valida por segunda vez. Aqui se comprueba que esa
	# frontera sigue en pie y que una clase desconocida no entra al motor.
	_reject_in_the_engine("08 an unknown leakage class", func(door: Dictionary) -> void:
		door["leakage_class"] = "carpinteria_inventada")
	_reject_in_the_engine("08 a negative leakage override", func(door: Dictionary) -> void:
		door["leakage_area_override_m2"] = -0.5)


## Aplica una mutacion al escenario valido y exige que la rechacen los DOS
## propietarios: el validador del escenario del editor y el del motor.
func _reject(label: String, mutate: Callable) -> void:
	var data: Dictionary = _editor_data(true)
	var door: Dictionary = Array(data["openings_data"])[0]
	mutate.call(door)
	_check(not Schema.validate(door, 0).is_empty(), "%s was accepted by the schema" % label)
	# La ruta real de `tools/run_scenario_headless.gd`: el JSON entra tal cual en
	# BuildingModel, SIN pasar por el normalizador del editor. Es donde el
	# rechazo tiene que ser explicito y determinista.
	var template: Dictionary = Serializer.to_runtime_template(data)
	template["openings_data"] = [door]
	var building = BuildingModelScript.new()
	_check(not building.validate_template_data(template).is_empty(),
			"%s was accepted by BuildingModel" % label)
	_check(not building.load_template_data(template),
			"%s still loaded into the engine" % label)
	building.free()


## Igual que `_reject`, pero para lo que valida D1 y no D4A: el esquema no lo
## mira, y el motor tiene que seguir rechazandolo igual que antes de esta fase.
func _reject_in_the_engine(label: String, mutate: Callable) -> void:
	var data: Dictionary = _editor_data(true)
	var door: Dictionary = Array(data["openings_data"])[0]
	mutate.call(door)
	var template: Dictionary = Serializer.to_runtime_template(data)
	template["openings_data"] = [door]
	var building = BuildingModelScript.new()
	_check(not building.validate_template_data(template).is_empty(),
			"%s was accepted by BuildingModel" % label)
	_check(not building.load_template_data(template),
			"%s still loaded into the engine" % label)
	building.free()


# ------------------------------------------------------------
# 09 claves desconocidas
# ------------------------------------------------------------

func _test_09_unknown_keys_are_preserved() -> void:
	var data: Dictionary = _editor_data(true)
	var door: Dictionary = Array(data["openings_data"])[0]
	door["future_editor_hint"] = "d4b"
	var tracks: Array = Array(door[Schema.DEFORMATION_KEY]).duplicate(true)
	Dictionary(tracks[0])["future_track_note"] = "unused"
	door[Schema.DEFORMATION_KEY] = tracks
	var panels: Array = Array(door[Schema.PANELS_KEY]).duplicate(true)
	Dictionary(panels[0])["future_panel_note"] = 7
	door[Schema.PANELS_KEY] = panels

	var path: String = WORK_DIR + "/unknown_keys.json"
	_check(Serializer.save_scenario(path, data), "09 the scenario could not be saved")
	var loaded_door: Dictionary = Array(Serializer.load_scenario(path)["openings_data"])[0]
	if not _has_payload(loaded_door, "09"):
		return
	_check(String(loaded_door.get("future_editor_hint", "")) == "d4b",
			"09 an unknown opening key was dropped")
	_check(String(Dictionary(Array(loaded_door[Schema.DEFORMATION_KEY])[0])
			.get("future_track_note", "")) == "unused",
			"09 an unknown track key was dropped")
	_check(int(Dictionary(Array(loaded_door[Schema.PANELS_KEY])[0])
			.get("future_panel_note", -1)) == 7,
			"09 an unknown panel key was dropped")
	_check(Schema.validate(loaded_door, 0).is_empty(),
			"09 unknown keys were rejected instead of preserved")


# ------------------------------------------------------------
# 10 identidad con la fisica apagada
# ------------------------------------------------------------

func _test_10_off_identity_against_the_engine() -> void:
	var with_data: Array = _run_engine(_editor_data(true))
	var without_data: Array = _run_engine(_editor_data(false))
	_check(with_data.size() == without_data.size() and with_data.size() > 0,
			"10 the OFF identity runs are not comparable")
	var identical: bool = true
	for i in range(mini(with_data.size(), without_data.size())):
		if float(with_data[i]) != float(without_data[i]):
			identical = false
			break
	_check(identical, "10 declaring prescribed physics changed the OFF simulation")


## Estado observable tras unos pasos, con todos los interruptores apagados.
func _run_engine(editor_data: Dictionary) -> Array:
	var building = BuildingModelScript.new()
	if not building.load_template_data(Serializer.to_runtime_template(editor_data)):
		building.free()
		return []
	var engine = SimulationEngineScript.new()
	engine.name = "PrescribedPersistenceIdentity"
	engine.building = building
	engine.auto_ignite_on_ready = false
	engine.auto_finish_on_extinction = false
	engine.enable_logging = false
	engine.enable_csv_log = false
	root.add_child(building)
	root.add_child(engine)
	engine.reset_simulation(0, true)
	for _i in range(40):
		engine.step(0.25)
	var samples: Array = []
	for room_id in [0, 1]:
		var room = building.get_room(room_id)
		if room == null:
			continue
		samples.append(float(room.upper_gas_kg))
		samples.append(float(room.lower_gas_kg))
		samples.append(float(room.upper_energy_kj))
		samples.append(float(room.lower_energy_kj))
		samples.append(float(room.o2_upper))
		samples.append(float(room.o2_lower))
		samples.append(float(room.smoke_kg))
		samples.append(float(room.co_kg))
		samples.append(float(room.co2_kg))
	samples.append(float(engine.sim_time_s))
	root.remove_child(engine)
	root.remove_child(building)
	engine.free()
	building.free()
	return samples


# ------------------------------------------------------------
# 11 ninguna ruta nueva
# ------------------------------------------------------------

func _test_11_no_new_flow_or_transport_route() -> void:
	var building = BuildingModelScript.new()
	_check(building.load_template_data(Serializer.to_runtime_template(_editor_data(true))),
			"11 the scenario did not load")
	var transport = TransportScript.new()
	# Los tres interruptores apagados, que es como nace el motor.
	transport.closed_door_leakage_enabled = false
	transport.closed_door_deformation_enabled = false
	transport.glazing_fallout_enabled = false
	transport.exterior_envelope_leakage_enabled = false
	var snapshot: Dictionary = transport.build_snapshot(building, {}, 0.25, 180.0)
	_check(bool(snapshot["valid"]), "11 the OFF snapshot is invalid")
	_check(Array(snapshot["errors"]).is_empty(), "11 the OFF snapshot reported errors")
	var cracks: int = 0
	var glazing: int = 0
	for element in Array(snapshot["openings"]):
		var provenance: String = String(Dictionary(element).get("provenance", ""))
		if String(Dictionary(element).get("flow_model", "")) == "ela_crack":
			cracks += 1
		if provenance == "prescribed_glazing_fallout":
			glazing += 1
	_check(cracks == 0, "11 a crack element appeared with every switch off")
	_check(glazing == 0, "11 a glazing element appeared with every switch off")

	# El unico consumidor sigue siendo el de siempre: la persistencia no ha
	# creado un segundo propietario del caudal ni del transporte.
	var schema_code: String = _code_only(FileAccess.get_file_as_string(
		"res://sim/building/PrescribedOpeningPhysicsSchema.gd"
	))
	for forbidden in [
		"sqrt(", "pow(", "mass_flow", "volume_flow", "compute_flows",
		"compute_segment_flow_from_dp", "build_door_segments", "wind_dp",
		"open_fraction =", "thermal_gap_fraction", "discharge_coeff",
	]:
		_check(not schema_code.contains(forbidden),
				"11 the persistence schema contains '%s'" % forbidden)
	building.free()


# ------------------------------------------------------------
# utilidades
# ------------------------------------------------------------

## La abertura unica del escenario, o `null` con el fallo ya anotado. Cargar mal
## no puede convertirse en un acceso invalido que reviente el validador.
func _single_opening(building, label: String):
	var openings: Array = building.get_openings()
	if openings.size() != 1:
		_check(false, "%s the scenario did not produce exactly one opening" % label)
		return null
	return openings[0]


## La carga util ya dentro del motor, con las mismas cautelas.
func _engine_payload_complete(opening, label: String) -> bool:
	var complete: bool = true
	if Array(opening.deformation_tracks).is_empty():
		complete = false
		_check(false, "%s the engine lost the deformation tracks" % label)
	if Array(opening.glazing_panels).size() != 2:
		complete = false
		_check(false, "%s the engine lost a glazing panel" % label)
	var spatial: Array = Array(opening.glazing_spatial)
	if spatial.size() != 2 or typeof(spatial[0]) != TYPE_DICTIONARY 			or not Dictionary(spatial[0]).has("snapshots"):
		complete = false
		_check(false, "%s the engine lost the spatial history" % label)
	return complete


## Una abertura que perdio su carga util no puede seguir comprobandose campo a
## campo: se marca el fallo y se sale, en vez de reventar con un acceso invalido.
func _has_payload(door: Dictionary, label: String) -> bool:
	var complete: bool = true
	for key in Schema.PAYLOAD_KEYS:
		if typeof(door.get(key, null)) != TYPE_ARRAY or Array(door[key]).is_empty():
			complete = false
			_check(false, "%s the round-tripped door lost '%s'" % [label, key])
	return complete


## Solo las lineas de codigo: la documentacion nombra lo que el modulo NO hace.
func _code_only(source: String) -> String:
	var kept: PackedStringArray = []
	for line in source.split("
"):
		if line.strip_edges().begins_with("#"):
			continue
		kept.append(line)
	return "
".join(kept)


## Igualdad EXACTA, sin tolerancia: una historia prescrita que se redondea deja
## de ser la que escribio el autor.
func _deep_equal(left: Variant, right: Variant) -> bool:
	if typeof(left) != typeof(right):
		return false
	match typeof(left):
		TYPE_ARRAY:
			var left_array: Array = left
			var right_array: Array = right
			if left_array.size() != right_array.size():
				return false
			for i in range(left_array.size()):
				if not _deep_equal(left_array[i], right_array[i]):
					return false
			return true
		TYPE_DICTIONARY:
			var left_dict: Dictionary = left
			var right_dict: Dictionary = right
			if left_dict.size() != right_dict.size():
				return false
			for key in left_dict.keys():
				if not right_dict.has(key):
					return false
				if not _deep_equal(left_dict[key], right_dict[key]):
					return false
			return true
		_:
			return left == right

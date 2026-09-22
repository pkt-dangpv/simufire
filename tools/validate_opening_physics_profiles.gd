extends SceneTree

## F2.2D4B1: catalogo trazable de perfiles y gate cientifico de calibracion.
##
##   <godot> --headless --path . --script \
##       res://tools/validate_opening_physics_profiles.gd
##
## Grupos:
##   01 el catalogo cumple su propio contrato y es determinista;
##   02 identidad versionada, unica y estable;
##   03 el gate de evidencia y de producto;
##   04 ida y vuelta de un perfil con su copia congelada;
##   05 rechazos explicitos: desconocido, version incompatible, manipulado,
##      bloqueado, categoria equivocada;
##   06 un escenario de D4A sigue siendo valido y se guarda como esquema 1;
##   07 la fuga de marco por abertura SUSTITUYE a la global, no se suma;
##   08 ensayos puros de la ley de rendija con dp impuestas;
##   09 los rangos derivados se reproducen desde los numeros publicados;
##   10 el exponente observado por la fuente y donde cae el del motor;
##   11 ninguna formula nueva y ningun consumidor de editor o vista.

const BuildingModelScript := preload("res://sim/BuildingModel.gd")
const Serializer := preload("res://editor/ScenarioSerializer.gd")
const Schema := preload("res://sim/building/PrescribedOpeningPhysicsSchema.gd")
const Catalog := preload("res://sim/building/OpeningPhysicsProfileCatalog.gd")
const LeakageModel := preload("res://sim/core/ClosedDoorLeakageModel.gd")
const TransportScript := preload("res://sim/core/PressureNetworkTransportSystem.gd")

const WORK_DIR: String = "user://opening_physics_profiles"

## Aire seco a 20 C, el mismo con el que la fuente tabula sus caudales. Se toma
## del catalogo para que la densidad de TODA transformacion tenga un solo dueño.
const RHO_20C: float = Catalog.REFERENCE_AIR_DENSITY_KG_M3

## Gross y Haberman 1989, tabla 2 (p. 177): caudal por unidad de longitud de
## rendija, m3/s por metro, para una rendija RECTA de 40 mm de profundidad a
## 20 C. Filas: dp en Pa; columnas: espesor de rendija 0,5 / 1 / 5 / 10 mm.
## Se transcriben tal cual se publican, con sus tres cifras significativas.
const GH_TABLE2_DP_PA: Array[float] = [10.0, 25.0, 100.0]
const GH_TABLE2_GAP_M: Array[float] = [0.0005, 0.001, 0.005, 0.010]
const GH_TABLE2_FLOW_M3_S_M: Array = [
	[0.000144, 0.00106, 0.0146, 0.0323],
	[0.000358, 0.00227, 0.0243, 0.0507],
	[0.00138, 0.00628, 0.0507, 0.1012],
]

## La fuente imprime tres cifras significativas, asi que una comparacion contra
## su tabla solo es exigible a media unidad de la ultima cifra impresa. No es
## una tolerancia inventada: es la precision con la que el dato esta publicado.
const PRINTED_DIGITS: int = 3

var _failures: Array[String] = []
var _checks: int = 0
var _notes: Array[String] = []


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(WORK_DIR))
	_test_01_catalog_contract()
	_test_02_versioned_identity()
	_test_03_evidence_and_product_gate()
	_test_04_profile_round_trip()
	_test_05_explicit_rejections()
	_test_06_legacy_scenarios_stay_on_schema_1()
	_test_07_frame_leakage_precedence()
	_test_08_pure_crack_law_experiments()
	_test_09_derived_ranges_reproduce()
	_test_10_exponent_envelope()
	_test_11_no_new_formula_and_no_editor_consumer()
	for note in _notes:
		print("  note: " + note)
	if _failures.is_empty():
		print("  %d checks" % _checks)
		print("OPENING PHYSICS PROFILES VALIDATION PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
		print("FAIL: " + failure)
	print("OPENING PHYSICS PROFILES VALIDATION FAIL (%d)" % _failures.size())
	quit(1)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _note(text: String) -> void:
	_notes.append(text)


## Media unidad de la ultima cifra significativa impresa.
func _printed_tolerance(value: float) -> float:
	if value == 0.0:
		return 0.0
	var magnitude: float = floorf(log(absf(value)) / log(10.0))
	return 0.5 * pow(10.0, magnitude - float(PRINTED_DIGITS - 1))


# ------------------------------------------------------------
# 01 contrato del catalogo
# ------------------------------------------------------------

func _test_01_catalog_contract() -> void:
	var errors: Array[String] = Catalog.validate_catalog()
	_check(errors.is_empty(), "01 the catalogue breaks its own contract: %s" % str(errors))
	_check(Catalog.PROFILES.size() >= 8, "01 the catalogue is suspiciously small")
	# Determinismo: dos lecturas dan exactamente la misma lista, en el mismo orden.
	var first: Array[String] = Catalog.all_versioned_ids()
	var second: Array[String] = Catalog.all_versioned_ids()
	_check(first == second, "01 the catalogue listing is not deterministic")
	# Y una copia no comparte memoria con la constante.
	var profile: Dictionary = Catalog.find("door.entry.weatherstripped.ashrae2001", 1)
	_check(not profile.is_empty(), "01 a known profile could not be found")
	if not profile.is_empty():
		profile["evidence"] = "mutated"
		var again: Dictionary = Catalog.find("door.entry.weatherstripped.ashrae2001", 1)
		_check(String(again["evidence"]) == Catalog.EVIDENCE_RESEARCH_ONLY,
				"01 the catalogue can be mutated from outside")
	# Toda categoria declarada existe en algun perfil, y al reves.
	var seen_categories: Dictionary = {}
	for raw in Catalog.PROFILES:
		seen_categories[String(Dictionary(raw)["category"])] = true
	for category in Catalog.CATEGORIES:
		_check(seen_categories.has(category), "01 category '%s' has no profile" % category)
	# Las ranuras persistentes del esquema y las categorias que el catalogo
	# declara persistibles tienen que decir lo mismo. Si D4B2 anade una ranura
	# sin declararla aqui -o al reves-, esto lo detecta.
	var slot_categories: Array[String] = []
	for slot in Schema.PROFILE_KEYS:
		slot_categories.append(String(Schema.PROFILE_SLOT_CATEGORY[slot]))
	slot_categories.sort()
	var persistable: Array[String] = []
	for category in Catalog.PERSISTABLE_CATEGORIES:
		persistable.append(String(category))
	persistable.sort()
	_check(slot_categories == persistable,
			"01 the schema slots %s and the persistable categories %s disagree"
			% [str(slot_categories), str(persistable)])
	# Y cada ranura declara el parametro que congela.
	for slot in Schema.PROFILE_KEYS:
		_check(Schema.PROFILE_SLOT_PARAMETER.has(slot),
				"01 slot '%s' does not declare the parameter it freezes" % slot)
	# La convencion del ELA tiene un solo dueño y coincide con la del modelo.
	_check(Catalog.ELA_REFERENCE_PRESSURE_PA == LeakageModel.NIST_ELA_REFERENCE_PRESSURE_PA,
			"01 the catalogue and the pure model disagree on the ELA reference pressure")
	_check(Catalog.ELA_REFERENCE_DISCHARGE_COEFFICIENT == 1.0,
			"01 the catalogue no longer states Cd = 1 for the ELA convention")


# ------------------------------------------------------------
# 02 identidad versionada
# ------------------------------------------------------------

func _test_02_versioned_identity() -> void:
	var ids: Dictionary = {}
	for raw in Catalog.PROFILES:
		var profile: Dictionary = raw
		var key: String = Catalog.versioned_id(
			String(profile["profile_id"]), int(profile["version"])
		)
		_check(not ids.has(key), "02 duplicated versioned id '%s'" % key)
		ids[key] = true
		_check(int(profile["version"]) >= 1, "02 '%s' has a version below 1" % key)
		_check(key.contains("@"), "02 '%s' is not a versioned identity" % key)
	# La identidad es exacta: ni recortes ni mayusculas.
	_check(Catalog.find(" door.entry.weatherstripped.ashrae2001 ", 1).is_empty(),
			"02 a padded profile id resolved")
	_check(Catalog.find("Door.Entry.Weatherstripped.Ashrae2001", 1).is_empty(),
			"02 a differently-cased profile id resolved")
	_check(Catalog.find("door.entry.weatherstripped.ashrae2001", 2).is_empty(),
			"02 an unpublished version resolved")
	_check(Catalog.has_profile_id("door.entry.weatherstripped.ashrae2001"),
			"02 a published profile id is not recognised")
	_check(not Catalog.has_profile_id("door.invented"), "02 an invented id is recognised")


# ------------------------------------------------------------
# 03 gate de evidencia y de producto
# ------------------------------------------------------------

func _test_03_evidence_and_product_gate() -> void:
	var by_state: Dictionary = {}
	for raw in Catalog.PROFILES:
		var profile: Dictionary = raw
		var state: String = String(profile["evidence"])
		by_state[state] = int(by_state.get(state, 0)) + 1
		var label: String = String(profile["profile_id"])
		# Un bloqueado no produce configuracion, pase lo que pase.
		if state == Catalog.EVIDENCE_BLOCKED:
			_check(not Catalog.can_produce_configuration(profile),
					"03 blocked profile '%s' can produce configuration" % label)
			_check(Dictionary(profile["parameters"]).is_empty(),
					"03 blocked profile '%s' carries parameters" % label)
		# Nada que no sea validated/derived puede pedir producto.
		if bool(profile["product_activation"]):
			_check(Catalog.PRODUCT_CAPABLE_STATES.has(state),
					"03 '%s' asks for product with evidence '%s'" % [label, state])
		# Y validated/derived exigen fuente.
		if Catalog.PRODUCT_CAPABLE_STATES.has(state):
			_check(not Array(profile["references"]).is_empty(),
					"03 '%s' is '%s' without a reference" % [label, state])
	for state in Catalog.EVIDENCE_STATES:
		_note("evidence '%s': %d profile(s)" % [state, int(by_state.get(state, 0))])
	# Los perfiles que el gate dejo bloqueados siguen bloqueados y vacios. Si
	# alguno cambiara de estado sin traer datos, esto lo detecta.
	for blocked_id in [
		"door.interior.residential_passage",
		"door.interior.loose_fitting",
		"deformation.residential_door.thermal_law",
		"glazing.toughened.contradictory",
		"shaft.vertical_opening.uncalibrated",
	]:
		var blocked: Dictionary = Catalog.find(blocked_id, 1)
		_check(not blocked.is_empty(), "03 blocked profile '%s' disappeared" % blocked_id)
		if blocked.is_empty():
			continue
		_check(String(blocked["evidence"]) == Catalog.EVIDENCE_BLOCKED,
				"03 '%s' is no longer blocked" % blocked_id)
		_check(not Catalog.can_produce_configuration(blocked),
				"03 '%s' can now produce configuration" % blocked_id)
	# D4B1 no activa NADA en producto. Esta lista tiene que estar vacia.
	_check(Catalog.product_ready_ids().is_empty(),
			"03 a profile is already marked product-ready: %s" % str(Catalog.product_ready_ids()))
	# Un research_only no puede colarse como validado.
	var research: Dictionary = Catalog.find("door.interior.not_weatherstripped.ashrae2001", 1)
	_check(String(research.get("evidence", "")) == Catalog.EVIDENCE_RESEARCH_ONLY,
			"03 the ASHRAE interior estimate is no longer research_only")
	_check(not bool(research.get("product_activation", true)),
			"03 the ASHRAE interior estimate claims product activation")


# ------------------------------------------------------------
# 04 ida y vuelta con copia congelada
# ------------------------------------------------------------

func _test_04_profile_round_trip() -> void:
	var path: String = WORK_DIR + "/profile_round_trip.json"
	# F2.2D4B2A anadio la regla de compatibilidad: una fuga de MARCO no encaja
	# en una puerta interior, porque R3 es de envolvente exterior. El fixture
	# pasa a llevar solo el perfil de fuga fria, que es el que si le toca; la
	# fuga de marco se comprueba en su sitio, sobre la ventana del grupo 07.
	var source: Dictionary = _editor_data(true, false)
	_check(Serializer.save_scenario(path, source), "04 the scenario could not be saved")
	var loaded: Dictionary = Serializer.load_scenario(path)
	var door: Dictionary = Array(loaded["openings_data"])[0]
	_check(int(door.get(Schema.SCHEMA_KEY, -1)) == 2,
			"04 a scenario carrying a profile is not schema 2")
	var block: Dictionary = door.get(Schema.LEAKAGE_PROFILE_KEY, {})
	_check(not block.is_empty(), "04 the leakage profile did not survive the file")
	if block.is_empty():
		return
	_check(String(block[Schema.PROFILE_ID_KEY]) == "door.interior.not_weatherstripped.ashrae2001",
			"04 the profile id changed")
	_check(typeof(block[Schema.PROFILE_VERSION_KEY]) == TYPE_INT,
			"04 the profile version lost its integer type")
	_check(int(block[Schema.PROFILE_VERSION_KEY]) == 1, "04 the profile version changed")
	var frozen: Dictionary = block[Schema.PROFILE_EFFECTIVE_KEY]
	_check(float(frozen["ela_m2"]) == 0.0021, "04 the frozen ELA drifted")
	_check(Schema.validate(door, 0).is_empty(), "04 the round-tripped profile failed validation")

	# Estabilidad byte a byte desde la primera escritura, como exige D4A.
	var again: String = WORK_DIR + "/profile_round_trip_2.json"
	_check(Serializer.save_scenario(again, loaded), "04 the second save failed")
	_check(FileAccess.get_file_as_bytes(path) == FileAccess.get_file_as_bytes(again),
			"04 a scenario with profiles is not byte-stable")

	# Y el motor recibe EXACTAMENTE el numero congelado, mas la procedencia.
	var building = BuildingModelScript.new()
	var template: Dictionary = Serializer.to_runtime_template(loaded)
	_check(building.load_template_data(template), "04 the scenario did not load")
	var openings: Array = building.get_openings()
	if openings.size() == 1:
		var opening = openings[0]
		_check(float(opening.leakage_area_override_m2) == 0.0021,
				"04 the engine did not receive the frozen ELA")
		_check(String(opening.leakage_profile_ref)
				== "door.interior.not_weatherstripped.ashrae2001@1",
				"04 the profile provenance was lost")
		_check(float(opening.frame_leakage_area_m2) == -1.0,
				"04 an interior door received a frame leakage area")
		# La fisica sale de la COPIA, no de una consulta al catalogo en caliente.
		_check(float(opening.leakage_area_override_m2)
				== float(Dictionary(Catalog.find(
					"door.interior.not_weatherstripped.ashrae2001", 1
				)["parameters"])["ela_m2"]),
				"04 the frozen copy and the catalogue disagree today")
	else:
		_check(false, "04 the scenario did not produce exactly one opening")
	building.free()


# ------------------------------------------------------------
# 05 rechazos explicitos
# ------------------------------------------------------------

func _test_05_explicit_rejections() -> void:
	_reject("05 an unknown profile", func(door: Dictionary) -> void:
		var block: Dictionary = Dictionary(door[Schema.LEAKAGE_PROFILE_KEY]).duplicate(true)
		block[Schema.PROFILE_ID_KEY] = "door.invented.by.nobody"
		door[Schema.LEAKAGE_PROFILE_KEY] = block,
		"perfil desconocido")
	_reject("05 an incompatible profile version", func(door: Dictionary) -> void:
		var block: Dictionary = Dictionary(door[Schema.LEAKAGE_PROFILE_KEY]).duplicate(true)
		block[Schema.PROFILE_VERSION_KEY] = 99
		door[Schema.LEAKAGE_PROFILE_KEY] = block,
		"no tiene la version")
	_reject("05 a tampered frozen copy", func(door: Dictionary) -> void:
		var block: Dictionary = Dictionary(door[Schema.LEAKAGE_PROFILE_KEY]).duplicate(true)
		block[Schema.PROFILE_EFFECTIVE_KEY] = {"ela_m2": 0.0042}
		door[Schema.LEAKAGE_PROFILE_KEY] = block,
		"no coincide con el catalogo")
	_reject("05 a blocked profile relabelled as derived", func(door: Dictionary) -> void:
		var block: Dictionary = Dictionary(door[Schema.LEAKAGE_PROFILE_KEY]).duplicate(true)
		block[Schema.PROFILE_ID_KEY] = "door.interior.loose_fitting"
		door[Schema.LEAKAGE_PROFILE_KEY] = block,
		"no puede producir configuracion")
	_reject("05 a frozen copy missing the parameter", func(door: Dictionary) -> void:
		var block: Dictionary = Dictionary(door[Schema.LEAKAGE_PROFILE_KEY]).duplicate(true)
		block[Schema.PROFILE_EFFECTIVE_KEY] = {}
		door[Schema.LEAKAGE_PROFILE_KEY] = block)
	_reject("05 a blocked profile", func(door: Dictionary) -> void:
		var block: Dictionary = Dictionary(door[Schema.LEAKAGE_PROFILE_KEY]).duplicate(true)
		block[Schema.PROFILE_ID_KEY] = "door.interior.residential_passage"
		block[Schema.PROFILE_EFFECTIVE_KEY] = {"ela_m2": 0.0021}
		door[Schema.LEAKAGE_PROFILE_KEY] = block)
	# La categoria se comprueba POR SI MISMA: si solo se exigiera la coincidencia
	# de parametros, quitar la regla de categoria no cambiaria nada, porque las
	# dos ranuras piden magnitudes de nombre distinto. Por eso aqui se exige que
	# el error hable de la CATEGORIA.
	_reject("05 a profile from the wrong category", func(door: Dictionary) -> void:
		var block: Dictionary = Dictionary(door[Schema.LEAKAGE_PROFILE_KEY]).duplicate(true)
		block[Schema.PROFILE_ID_KEY] = "frame.exterior.window.legacy_engine_value"
		block[Schema.PROFILE_EFFECTIVE_KEY] = {"leak_area_m2": 0.005, "discharge_coefficient": 0.61}
		door[Schema.LEAKAGE_PROFILE_KEY] = block,
		"esta ranura exige")
	_reject("05 a profile block that is not a dictionary", func(door: Dictionary) -> void:
		door[Schema.LEAKAGE_PROFILE_KEY] = [1, 2, 3])
	_reject("05 a non-integer profile version", func(door: Dictionary) -> void:
		var block: Dictionary = Dictionary(door[Schema.LEAKAGE_PROFILE_KEY]).duplicate(true)
		block[Schema.PROFILE_VERSION_KEY] = 1.5
		door[Schema.LEAKAGE_PROFILE_KEY] = block)
	_reject("05 a profile declared under schema 1", func(door: Dictionary) -> void:
		door[Schema.SCHEMA_KEY] = 1)
	_reject("05 a schema version above the maximum", func(door: Dictionary) -> void:
		door[Schema.SCHEMA_KEY] = Schema.SCHEMA_VERSION + 1)
	# Un perfil de RANGO no puede servir como valor efectivo de una abertura.
	_reject("05 a range profile used as an effective value", func(door: Dictionary) -> void:
		door[Schema.FRAME_PROFILE_KEY] = Schema.build_profile_block(
			"frame.exterior.window.measured_range", 1
		))
	# Un valor no representable exactamente en JSON se rechaza ANTES de guardar.
	_reject("05 a frozen value the file cannot represent", func(door: Dictionary) -> void:
		var block: Dictionary = Dictionary(door[Schema.LEAKAGE_PROFILE_KEY]).duplicate(true)
		block[Schema.PROFILE_EFFECTIVE_KEY] = {"ela_m2": 1.0 / 3.0}
		door[Schema.LEAKAGE_PROFILE_KEY] = block)


## `expected_reason`, cuando se da, exige que el rechazo lo produzca la regla
## que se quiere probar y no otra que la tape.
func _reject(label: String, mutate: Callable, expected_reason: String = "") -> void:
	var data: Dictionary = _editor_data(true, false)
	var door: Dictionary = Array(data["openings_data"])[0]
	mutate.call(door)
	var reasons: Array[String] = Schema.validate(door, 0)
	_check(not reasons.is_empty(), "%s was accepted by the schema" % label)
	if not expected_reason.is_empty():
		var matched: bool = false
		for reason in reasons:
			if reason.contains(expected_reason):
				matched = true
		_check(matched, "%s was rejected, but not for '%s': %s"
				% [label, expected_reason, str(reasons)])
	var template: Dictionary = Serializer.to_runtime_template(data)
	template["openings_data"] = [door]
	var building = BuildingModelScript.new()
	_check(not building.validate_template_data(template).is_empty(),
			"%s was accepted by BuildingModel" % label)
	_check(not building.load_template_data(template),
			"%s still loaded into the engine" % label)
	building.free()


# ------------------------------------------------------------
# 06 escenarios de D4A
# ------------------------------------------------------------

func _test_06_legacy_scenarios_stay_on_schema_1() -> void:
	# Sin nada declarado: ni una clave, como en D4A.
	var bare: Dictionary = Serializer.normalize_editor_data(_editor_data(false, false))
	var bare_door: Dictionary = Array(bare["openings_data"])[0]
	_check(not bare_door.has(Schema.SCHEMA_KEY), "06 a bare opening gained the schema key")
	for key in Schema.PROFILE_KEYS:
		_check(not bare_door.has(key), "06 a bare opening gained '%s'" % key)

	# Con fisica prescrita de D4A pero sin perfiles: SIGUE siendo esquema 1.
	var legacy: Dictionary = _editor_data(false, false)
	var legacy_door: Dictionary = Array(legacy["openings_data"])[0]
	legacy_door[Schema.SCHEMA_KEY] = 1
	legacy_door[Schema.DEFORMATION_KEY] = _deformation_tracks()
	var normalized: Dictionary = Serializer.normalize_editor_data(legacy)
	var result: Dictionary = Array(normalized["openings_data"])[0]
	_check(int(result[Schema.SCHEMA_KEY]) == 1,
			"06 a D4A scenario was silently migrated to schema 2")
	_check(Schema.validate(result, 0).is_empty(), "06 a D4A scenario stopped validating")
	_check(Schema.required_schema_version(result) == 1,
			"06 prescribed physics alone now demands schema 2")

	# Y un escenario de D4A se vuelve a guardar byte a byte igual.
	var first: String = WORK_DIR + "/legacy_1.json"
	var second: String = WORK_DIR + "/legacy_2.json"
	_check(Serializer.save_scenario(first, legacy), "06 the legacy save failed")
	_check(Serializer.save_scenario(second, Serializer.load_scenario(first)),
			"06 the legacy re-save failed")
	_check(FileAccess.get_file_as_bytes(first) == FileAccess.get_file_as_bytes(second),
			"06 a D4A scenario is no longer byte-stable")
	_check(not FileAccess.get_file_as_string(first).contains("profile"),
			"06 a D4A scenario file gained a profile key")

	# La migracion 1 -> 2 sube la marca SOLO cuando el contenido lo exige.
	var upgraded: Dictionary = _editor_data(true, false)
	var upgraded_door: Dictionary = Array(upgraded["openings_data"])[0]
	upgraded_door[Schema.SCHEMA_KEY] = 1
	var migrated: Dictionary = Array(
		Serializer.normalize_editor_data(upgraded)["openings_data"]
	)[0]
	_check(int(migrated[Schema.SCHEMA_KEY]) == 2,
			"06 a profile did not raise the schema marker to 2")


# ------------------------------------------------------------
# 07 precedencia de la fuga de marco
# ------------------------------------------------------------

func _test_07_frame_leakage_precedence() -> void:
	# Dos numeros deliberadamente distintos, para que la precedencia se vea.
	# El propio de la abertura sale del perfil historico (0,005 m2); el global
	# se fija aqui en otro valor cualquiera.
	var global_area_m2: float = 0.009
	var own_area_m2: float = 0.005
	# Misma ventana, una con area propia y otra sin ella.
	for declares_own in [false, true]:
		var building = BuildingModelScript.new()
		var data: Dictionary = _window_scenario(declares_own, own_area_m2)
		if not building.load_template_data(Serializer.to_runtime_template(data)):
			_check(false, "07 the window scenario did not load")
			building.free()
			continue
		var transport = TransportScript.new()
		transport.exterior_envelope_leakage_enabled = true
		transport.exterior_envelope_leakage_area_m2 = global_area_m2
		if declares_own:
			var openings: Array = building.get_openings()
			if openings.size() == 1:
				_check(float(openings[0].frame_leakage_area_m2) == own_area_m2,
						"07 the engine did not receive the frozen frame area")
				_check(String(openings[0].frame_leakage_profile_ref)
						== "frame.exterior.window.legacy_engine_value@1",
						"07 the frame profile provenance was lost")
		var snapshot: Dictionary = transport.build_snapshot(building, {}, 0.25, 0.0)
		_check(bool(snapshot["valid"]), "07 the snapshot is invalid")
		var areas: Array = []
		for raw_element in Array(snapshot["openings"]):
			var element: Dictionary = raw_element
			if String(element.get("provenance", "")) == "exterior_envelope_leakage":
				areas.append(float(element["leak_area_m2"]))
		_check(areas.size() == 1, "07 expected exactly one envelope element")
		if areas.size() == 1:
			var expected: float = own_area_m2 if declares_own else global_area_m2
			_check(own_area_m2 != global_area_m2,
					"07 the test cannot distinguish precedence with equal areas")
			_check(float(areas[0]) == expected,
					"07 the envelope area is %f, expected %f" % [float(areas[0]), expected])
			# Lo decisivo: NO es la suma de las dos.
			_check(float(areas[0]) != global_area_m2 + own_area_m2,
					"07 the global and the per-opening leak were added together")
		building.free()


# ------------------------------------------------------------
# 08 ensayos puros con dp impuestas
# ------------------------------------------------------------

func _test_08_pure_crack_law_experiments() -> void:
	var ela_m2: float = 0.0021
	var segments: Array = [{"id": "probe", "z_m": 1.0, "area_m2": ela_m2}]
	var params: Dictionary = _crack_params(0.65)
	# Varios puntos DENTRO del dominio experimental declarado (50 Pa).
	var probes: Array[float] = [1.0, 4.0, 10.0, 25.0, 50.0]
	var previous_mass: float = -1.0
	for dp_pa in probes:
		var forward: Dictionary = LeakageModel.compute_flows(
			segments, _side(dp_pa), _side(0.0), params, 1.0
		)
		_check(bool(forward["valid"]), "08 the model rejected dp = %f Pa" % dp_pa)
		if not bool(forward["valid"]):
			continue
		var flow: Dictionary = Array(forward["flows"])[0]
		var mass_kg_s: float = float(flow["mass_flow_kg_s"])
		_check(mass_kg_s > 0.0, "08 dp = %f Pa gave no flow" % dp_pa)
		_check(mass_kg_s > previous_mass, "08 flow is not monotonic at dp = %f Pa" % dp_pa)
		previous_mass = mass_kg_s
		_check(not bool(forward["domain_exceeded"]),
				"08 dp = %f Pa was flagged out of domain" % dp_pa)
		# Sentido negativo: mismo modulo, signo contrario.
		var reverse: Dictionary = LeakageModel.compute_flows(
			segments, _side(0.0), _side(dp_pa), params, 1.0
		)
		_check(bool(reverse["valid"]), "08 the reversed case was rejected")
		if bool(reverse["valid"]):
			var back: Dictionary = Array(reverse["flows"])[0]
			_check(absf(float(back["mass_flow_kg_s"]) - mass_kg_s) <= 1.0e-12 * mass_kg_s,
					"08 the reversed magnitude differs at dp = %f Pa" % dp_pa)
			_check(String(back["direction"]) != String(flow["direction"]),
					"08 the reversed direction did not flip at dp = %f Pa" % dp_pa)
	# Fuera del dominio: se MARCA y no se recorta.
	var far: Dictionary = LeakageModel.compute_flows(
		segments, _side(5000.0), _side(0.0), params, 1.0
	)
	_check(bool(far["valid"]), "08 a far-field dp was rejected outright")
	_check(bool(far["domain_exceeded"]), "08 5 kPa was not flagged out of domain")
	if bool(far["valid"]):
		var far_flow: Dictionary = Array(far["flows"])[0]
		var at_50: Dictionary = LeakageModel.compute_flows(
			segments, _side(50.0), _side(0.0), params, 1.0
		)
		_check(float(far_flow["mass_flow_kg_s"])
				> float(Array(at_50["flows"])[0]["mass_flow_kg_s"]),
				"08 the out-of-domain flow was clipped instead of reported")
	# Continuidad alrededor de cero.
	var tiny_plus: Dictionary = LeakageModel.compute_flows(
		segments, _side(1.0e-6), _side(0.0), params, 1.0
	)
	var tiny_minus: Dictionary = LeakageModel.compute_flows(
		segments, _side(0.0), _side(1.0e-6), params, 1.0
	)
	var zero: Dictionary = LeakageModel.compute_flows(
		segments, _side(0.0), _side(0.0), params, 1.0
	)
	if bool(tiny_plus["valid"]) and bool(tiny_minus["valid"]) and bool(zero["valid"]):
		_check(float(Array(zero["flows"])[0]["mass_flow_kg_s"]) == 0.0,
				"08 zero dp gave a non-zero flow")
		var plus: float = float(Array(tiny_plus["flows"])[0]["mass_flow_kg_s"])
		var minus: float = float(Array(tiny_minus["flows"])[0]["mass_flow_kg_s"])
		_check(absf(plus - minus) <= 1.0e-15, "08 the law is not symmetric around zero")
		_check(plus < 1.0e-3, "08 the flow does not vanish as dp approaches zero")
	# Escala con el area, a dp fija.
	var doubled: Array = [{"id": "probe", "z_m": 1.0, "area_m2": 2.0 * ela_m2}]
	var single: Dictionary = LeakageModel.compute_flows(
		segments, _side(25.0), _side(0.0), params, 1.0
	)
	var twice: Dictionary = LeakageModel.compute_flows(
		doubled, _side(25.0), _side(0.0), params, 1.0
	)
	if bool(single["valid"]) and bool(twice["valid"]):
		var one: float = float(Array(single["flows"])[0]["mass_flow_kg_s"])
		var two: float = float(Array(twice["flows"])[0]["mass_flow_kg_s"])
		_check(absf(two - 2.0 * one) <= 1.0e-12 * two, "08 the flow does not scale with area")
	# Independencia del orden de los segmentos y repetibilidad byte a byte.
	var ordered: Array = [
		{"id": "low", "z_m": 0.1, "area_m2": 0.3 * ela_m2},
		{"id": "high", "z_m": 1.9, "area_m2": 0.7 * ela_m2},
	]
	var shuffled: Array = [ordered[1], ordered[0]]
	var run_a: Dictionary = LeakageModel.compute_flows(
		ordered, _side(25.0), _side(0.0), params, 1.0
	)
	var run_b: Dictionary = LeakageModel.compute_flows(
		shuffled, _side(25.0), _side(0.0), params, 1.0
	)
	var run_c: Dictionary = LeakageModel.compute_flows(
		ordered, _side(25.0), _side(0.0), params, 1.0
	)
	_check(JSON.stringify(run_a) == JSON.stringify(run_b),
			"08 the result depends on segment order")
	_check(JSON.stringify(run_a) == JSON.stringify(run_c),
			"08 the result is not byte-repeatable")
	# Conservacion: lo que sale de un lado es lo que llega al otro.
	if bool(run_a["valid"]):
		var gross: float = 0.0
		for raw_flow in Array(run_a["flows"]):
			gross += absf(float(Dictionary(raw_flow)["mass_flow_kg_s"]))
		_check(absf(gross - absf(float(run_a["net_mass_a_to_b_kg_s"]))) <= 1.0e-12 * gross,
				"08 a one-way case does not conserve mass across segments")


# ------------------------------------------------------------
# 09 reproduccion de los rangos derivados
# ------------------------------------------------------------

func _test_09_derived_ranges_reproduce() -> void:
	# Puerta interior: ELA = Q(25 Pa) * (4/25)^0,5 / sqrt(2*4/rho).
	var reference_velocity: float = sqrt(2.0 * 4.0 / RHO_20C)
	var scale: float = sqrt(4.0 / 25.0)
	var ela_min_m2: float = 0.013 * scale / reference_velocity
	var ela_max_m2: float = 0.151 * scale / reference_velocity
	var profile: Dictionary = Catalog.find("door.interior.installed_measured_range", 1)
	_check(not profile.is_empty(), "09 the derived door range profile is missing")
	if not profile.is_empty():
		var parameters: Dictionary = profile["parameters"]
		_check(absf(float(parameters["ela_min_m2"]) - ela_min_m2)
				<= _printed_tolerance(ela_min_m2),
				"09 ela_min_m2 does not reproduce: catalogue %.6f, computed %.6f"
				% [float(parameters["ela_min_m2"]), ela_min_m2])
		_check(absf(float(parameters["ela_max_m2"]) - ela_max_m2)
				<= _printed_tolerance(ela_max_m2),
				"09 ela_max_m2 does not reproduce: catalogue %.6f, computed %.6f"
				% [float(parameters["ela_max_m2"]), ela_max_m2])
	_note("derived interior-door ELA range: %.1f to %.1f cm2 at 4 Pa"
			% [ela_min_m2 * 1.0e4, ela_max_m2 * 1.0e4])
	# Las dos estimaciones de ASHRAE, situadas dentro de ese rango medido.
	var entry_m2: float = float(Dictionary(Catalog.find(
		"door.entry.weatherstripped.ashrae2001", 1)["parameters"])["ela_m2"])
	var interior_m2: float = float(Dictionary(Catalog.find(
		"door.interior.not_weatherstripped.ashrae2001", 1)["parameters"])["ela_m2"])
	_check(interior_m2 < ela_max_m2,
			"09 the ASHRAE interior estimate exceeds every measured door")
	_note("ASHRAE 21 cm2 sits at %.2f %% of the measured interior-door span"
			% [100.0 * (interior_m2 - ela_min_m2) / (ela_max_m2 - ela_min_m2)])
	_note("ASHRAE 12 cm2 entry estimate is %.2fx the tightest measured door"
			% [entry_m2 / ela_min_m2])

	# Ventana: A = Q / (Cd * sqrt(2*dp/rho)) a 100 Pa con Cd = 0,61.
	var window_velocity: float = sqrt(2.0 * 100.0 / RHO_20C)
	var crack_length_m: float = 2.0 * (1.2 + 1.0)
	var area_min_m2: float = (2.2 * crack_length_m / 3600.0) / (0.61 * window_velocity)
	var area_max_m2: float = (25.0 * crack_length_m / 3600.0) / (0.61 * window_velocity)
	var frame: Dictionary = Catalog.find("frame.exterior.window.measured_range", 1)
	_check(not frame.is_empty(), "09 the derived window range profile is missing")
	if not frame.is_empty():
		var parameters: Dictionary = frame["parameters"]
		_check(absf(float(parameters["leak_area_min_m2"]) - area_min_m2)
				<= _printed_tolerance(area_min_m2),
				"09 leak_area_min_m2 does not reproduce: catalogue %.6f, computed %.6f"
				% [float(parameters["leak_area_min_m2"]), area_min_m2])
		_check(absf(float(parameters["leak_area_max_m2"]) - area_max_m2)
				<= _printed_tolerance(area_max_m2),
				"09 leak_area_max_m2 does not reproduce: catalogue %.6f, computed %.6f"
				% [float(parameters["leak_area_max_m2"]), area_max_m2])
	_note("derived window leak-area range: %.1f to %.1f cm2 for a 1,2 x 1,0 m window"
			% [area_min_m2 * 1.0e4, area_max_m2 * 1.0e4])
	# El valor historico del motor queda POR ENCIMA de todo el rango medido, y
	# eso es justo lo que el perfil advierte.
	var legacy_m2: float = float(Dictionary(Catalog.find(
		"frame.exterior.window.legacy_engine_value", 1)["parameters"])["leak_area_m2"])
	_check(legacy_m2 > area_max_m2,
			"09 the legacy engine area no longer sits above the measured range")
	_note("legacy engine frame area is %.2fx the leakiest measured window"
			% [legacy_m2 / area_max_m2])


# ------------------------------------------------------------
# 10 exponente observado por la fuente
# ------------------------------------------------------------

func _test_10_exponent_envelope() -> void:
	# Exponente implicito entre 10 y 100 Pa, gap a gap, desde la tabla 2 de la
	# fuente. No se ajusta nada: se lee lo que la fuente publica.
	var exponents: Array[float] = []
	for column in range(GH_TABLE2_GAP_M.size()):
		var low: float = float(Array(GH_TABLE2_FLOW_M3_S_M[0])[column])
		var high: float = float(Array(GH_TABLE2_FLOW_M3_S_M[2])[column])
		_check(low > 0.0 and high > low, "10 the tabulated flows are not increasing")
		var exponent: float = log(high / low) / log(100.0 / 10.0)
		exponents.append(exponent)
		_note("Gross-Haberman gap %.1f mm: implied exponent %.3f between 10 and 100 Pa"
				% [GH_TABLE2_GAP_M[column] * 1000.0, exponent])
	# Lo que la fuente afirma en el texto: el exponente va de 0,5 a 1.
	for exponent in exponents:
		_check(exponent >= 0.49 and exponent <= 1.01,
				"10 an implied exponent (%.3f) falls outside the 0,5-1,0 span the source states"
				% exponent)
	# Y decrece al ensanchar la rendija: de casi lineal a casi raiz cuadrada.
	for index in range(1, exponents.size()):
		_check(exponents[index] < exponents[index - 1],
				"10 the implied exponent does not decrease with gap thickness")
	# El exponente fijo del motor cae DENTRO de la envolvente observada, pero no
	# coincide con ninguna rendija concreta: por eso sigue siendo provisional.
	var engine_exponent: float = LeakageModel.PROVISIONAL_FLOW_EXPONENT_CANDIDATE
	_check(engine_exponent > exponents[exponents.size() - 1] and engine_exponent < exponents[0],
			"10 the engine exponent %.3f is outside the observed envelope" % engine_exponent)
	var nearest_gap_mm: float = 0.0
	var nearest_delta: float = INF
	for index in range(exponents.size()):
		var delta: float = absf(exponents[index] - engine_exponent)
		if delta < nearest_delta:
			nearest_delta = delta
			nearest_gap_mm = GH_TABLE2_GAP_M[index] * 1000.0
	_note("the engine's fixed exponent %.2f is closest to a %.1f mm gap (delta %.3f)"
			% [engine_exponent, nearest_gap_mm, nearest_delta])
	# La tabla de NBSIR da 0,5 para holguras de puerta: el motor NO usa ese
	# valor, y la discrepancia se deja anotada en vez de resolverse a mano.
	_note("NBSIR 81-2214 table 1 lists n = 0,50 for door gaps; the engine uses %.2f"
			% engine_exponent)


# ------------------------------------------------------------
# 11 sin formulas nuevas ni consumidores de editor
# ------------------------------------------------------------

func _test_11_no_new_formula_and_no_editor_consumer() -> void:
	var catalog_code: String = _code_only(FileAccess.get_file_as_string(
		"res://sim/building/OpeningPhysicsProfileCatalog.gd"
	))
	for forbidden in [
		"sqrt(", "pow(", "compute_flows", "compute_segment_flow_from_dp",
		"build_door_segments", "compute_open_geometry", "wind", "mass_flow",
		"open_fraction", "thermal_gap_fraction", "FileAccess", "HTTP",
	]:
		_check(not catalog_code.contains(forbidden),
				"11 the catalogue contains '%s'" % forbidden)
	# La VISTA sigue sin leer el catalogo, y nunca debe leerlo.
	for directory in ["res://view", "res://ui", "res://scenes"]:
		_check(not _directory_mentions(directory, "OpeningPhysicsProfileCatalog"),
				"11 %s already consumes the catalogue" % directory)
	# F2.2D4B2A conecto el catalogo al EDITOR, que es lo que esa fase venia a
	# hacer, pero por UN solo fichero: el controlador de configuracion. Si
	# apareciera un segundo consumidor en `editor/`, la politica de seleccion
	# habria empezado a repartirse y esto lo detecta.
	var editor_consumers: PackedStringArray = []
	_collect_mentions("res://editor", "OpeningPhysicsProfileCatalog", editor_consumers)
	_check(editor_consumers.size() == 1 			and String(editor_consumers[0]).ends_with("OpeningPhysicsEditor.gd"),
			"11 the catalogue is consumed from editor/ by %s" % str(editor_consumers))
	# Y el unico sitio que resuelve un perfil es el esquema persistente.
	var schema_code: String = _code_only(FileAccess.get_file_as_string(
		"res://sim/building/PrescribedOpeningPhysicsSchema.gd"
	))
	_check(schema_code.contains("ProfileCatalog.find("),
			"11 the schema no longer resolves profiles against the catalogue")
	_check(not _directory_mentions("res://sim/core", "OpeningPhysicsProfileCatalog"),
			"11 sim/core consumes the catalogue directly")


## Los ficheros de un arbol que nombran algo, con su ruta. Se usa para poder
## exigir no solo "cuantos" sino "cual".
func _collect_mentions(directory: String, needle: String, out: PackedStringArray) -> void:
	for file_name in DirAccess.get_files_at(directory):
		if not file_name.ends_with(".gd"):
			continue
		if FileAccess.get_file_as_string(directory + "/" + file_name).contains(needle):
			out.append(directory + "/" + file_name)
	for sub in DirAccess.get_directories_at(directory):
		_collect_mentions(directory + "/" + sub, needle, out)


func _directory_mentions(directory: String, needle: String) -> bool:
	var found: bool = false
	var listing: PackedStringArray = DirAccess.get_files_at(directory)
	for file_name in listing:
		if not file_name.ends_with(".gd"):
			continue
		if FileAccess.get_file_as_string(directory + "/" + file_name).contains(needle):
			found = true
	for sub in DirAccess.get_directories_at(directory):
		if _directory_mentions(directory + "/" + sub, needle):
			found = true
	return found


# ------------------------------------------------------------
# utilidades
# ------------------------------------------------------------

## Solo CODIGO ejecutable: fuera los comentarios y fuera el contenido de las
## cadenas. El catalogo es un fichero de datos lleno de prosa cientifica, y esa
## prosa nombra por fuerza cosas como la raiz cuadrada de la transformacion o la
## palabra 'window'. Lo que se persigue aqui es una FORMULA, no una mencion.
func _code_only(source: String) -> String:
	var kept: PackedStringArray = []
	for line in source.split("\n"):
		if line.strip_edges().begins_with("#"):
			continue
		kept.append(_without_string_literals(line))
	return "\n".join(kept)


func _without_string_literals(line: String) -> String:
	var out: String = ""
	var inside: bool = false
	for index in range(line.length()):
		var character: String = line[index]
		if character == "\"":
			inside = not inside
			continue
		if not inside:
			out += character
	return out


func _crack_params(exponent: float) -> Dictionary:
	return {
		"ela_reference_pressure_pa": LeakageModel.NIST_ELA_REFERENCE_PRESSURE_PA,
		"flow_exponent": exponent,
		"zero_pressure_regularization_pa": 0.0,
		"pressure_domain_max_pa": 50.0,
	}


## Lado de la puerta con una sobrepresion impuesta y sin estratificacion, para
## que la dp del segmento sea exactamente la impuesta.
func _side(gauge_pa: float) -> Dictionary:
	return {
		"floor_z_m": 0.0,
		"interface_height_m": 2.5,
		"rho_lower_kg_m3": RHO_20C,
		"rho_upper_kg_m3": RHO_20C,
		"p_floor_pa": gauge_pa,
	}


func _deformation_tracks() -> Array:
	return [
		{
			"id": "top",
			"location": "top",
			"z_m": 1.95,
			"points": [[0.0, 0.0], [60.0, 0.0005]],
		},
	]


func _editor_data(with_profiles: bool, with_frame: bool) -> Dictionary:
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
	if with_profiles:
		door[Schema.SCHEMA_KEY] = 2
		door[Schema.LEAKAGE_PROFILE_KEY] = Schema.build_profile_block(
			"door.interior.not_weatherstripped.ashrae2001", 1
		)
		if with_frame:
			door[Schema.FRAME_PROFILE_KEY] = Schema.build_profile_block(
				"frame.exterior.window.legacy_engine_value", 1
			)
	return _scenario_with_openings([door])


func _window_scenario(declares_own: bool, own_area_m2: float) -> Dictionary:
	var window: Dictionary = {
		"a": 0,
		"b": -1,
		"type": "window",
		"wall": "bottom",
		"width_m": 1.2,
		"height_m": 1.0,
		"sill_m": 0.9,
		"open_fraction": 0.0,
	}
	if declares_own:
		window[Schema.SCHEMA_KEY] = 2
		# El perfil historico es el unico de marco con un valor unico y
		# aplicable; su `leak_area_m2` son justo los `own_area_m2` de la prueba.
		window[Schema.FRAME_PROFILE_KEY] = Schema.build_profile_block(
			"frame.exterior.window.legacy_engine_value", 1
		)
	return _scenario_with_openings([window])


func _scenario_with_openings(openings: Array) -> Dictionary:
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
		"openings_data": openings,
		"detectors": [],
		"victims": [],
		"player_start": {},
		"exterior_walls": [],
	}

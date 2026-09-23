extends SceneTree

## F2.2D4B2B: activacion experimental de la fisica de aberturas.
##
##   <godot> --headless --path . --script \
##       res://tools/validate_experimental_physics_activation.gd
##
## Lo que este validador mide, grupo a grupo:
##   01 sin autorizacion, un escenario con perfiles se comporta OFF byte a byte;
##   02 la confirmacion explicita enciende SOLO las familias pedidas;
##   03 revocar devuelve el escenario a OFF;
##   04 bloqueado, incompatible, version no publicada y copia congelada alterada
##      se rechazan de forma explicita;
##   05 D2 y D3 siguen siendo PRESCRIPCION: nadie rompe ni deforma por su cuenta;
##   06 la dependencia de red es obligatoria y no se enciende por detras;
##   07 ninguna fuga se suma dos veces;
##   08 el estado operativo es independiente del perfil y de la autorizacion;
##   09 la salida diagnostica esta completa y es determinista;
##   10 fuera de dominio se MARCA, y no se recorta ni se reajusta nada;
##   11 ningun escenario distribuido autoriza ni declara nada;
##   12 ningun perfil queda marcado apto para producto;
##   13 el consentimiento dice las cuatro cosas, y sin las cuatro no autoriza;
##   14 la autorizacion caduca sola cuando cambia lo que autorizo;
##   15 el recorrido real editor -> escenario guardado -> plantilla -> motor;
##   16 lo que el solver marca fuera de dominio llega al informe sin recortarse;
##   17 una autorizacion rechazada PARA la simulacion, no la deja correr apagada;
##   18 ciclo de vida en UN MISMO motor: autorizar, ejecutar, revocar, reiniciar;
##   19 propiedad de cada interruptor: la autorizacion solo retira lo que anadio.

const Auth := preload("res://sim/building/ExperimentalRunAuthorization.gd")
const Catalog := preload("res://sim/building/OpeningPhysicsProfileCatalog.gd")
const Schema := preload("res://sim/building/PrescribedOpeningPhysicsSchema.gd")
const Serializer := preload("res://editor/ScenarioSerializer.gd")
const DocumentScript := preload("res://editor/ScenarioDocument.gd")
const PhysicsEditor := preload("res://editor/OpeningPhysicsEditor.gd")
const BuildingModelScript := preload("res://sim/BuildingModel.gd")
const SimulationEngineScript := preload("res://sim/core/SimulationEngine.gd")
const TransportScript := preload("res://sim/core/PressureNetworkTransportSystem.gd")

const WORK_DIR: String = "user://experimental_physics_activation"

const RESEARCH_LEAKAGE: String = "door.interior.not_weatherstripped.ashrae2001"
const DERIVED_LEAKAGE: String = "door.interior.installed_measured_range"
const FRAME_PROFILE: String = "frame.exterior.window.legacy_engine_value"
const RESEARCH_DEFORMATION: String = "deformation.steel_fire_door.furnace_topology"
const DERIVED_GLAZING: String = "glazing.multilayer.free_path_rule"
const BLOCKED_GLAZING: String = "glazing.toughened.contradictory"

## Los cinco interruptores, escritos una vez.
const SWITCHES: Array[String] = [
	"pressure_network_solver_enabled",
	"closed_door_leakage_enabled",
	"closed_door_deformation_enabled",
	"glazing_fallout_enabled",
	"exterior_envelope_leakage_enabled",
]

var _failures: Array[String] = []
var _checks: int = 0


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(WORK_DIR))
	_test_01_no_authorization_is_off()
	_test_02_only_the_requested_families()
	_test_03_revoking_returns_to_off()
	_test_04_invalid_profiles_are_rejected()
	_test_05_d2_and_d3_stay_prescriptions()
	_test_06_the_network_dependency_is_mandatory()
	_test_07_no_leak_is_counted_twice()
	_test_08_operational_state_is_independent()
	_test_09_the_diagnostic_output_is_complete()
	_test_10_out_of_domain_is_marked_not_clipped()
	_test_11_no_distributed_scenario_authorizes()
	_test_12_no_profile_is_product_ready()
	_test_13_the_consent_says_the_four_things()
	_test_14_the_authorization_expires_by_itself()
	_test_15_the_real_editor_to_engine_path()
	_test_16_the_domain_mark_reaches_the_report()
	_test_17_a_rejected_authorization_stops_the_simulation()
	_test_18_the_lifecycle_on_one_engine()
	_test_19_switch_ownership_and_precedence()
	if _failures.is_empty():
		print("  %d checks" % _checks)
		print("EXPERIMENTAL PHYSICS ACTIVATION VALIDATION PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
		print("FAIL: " + failure)
	print("EXPERIMENTAL PHYSICS ACTIVATION VALIDATION FAIL (%d)" % _failures.size())
	quit(1)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


# ------------------------------------------------------------
# 01 sin autorizacion, OFF byte a byte
# ------------------------------------------------------------

func _test_01_no_authorization_is_off() -> void:
	var scenario: Dictionary = _configured_scenario()
	_check(not Auth.declares(scenario), "01 a configured scenario already authorizes")
	_check(not Auth.available_families(scenario).is_empty(),
			"01 the fixture does not configure any family")
	var verdict: Dictionary = Auth.resolve(scenario)
	_check(not bool(verdict["declares"]), "01 resolve saw an authorization that is not there")
	_check(not bool(verdict["authorized"]), "01 a scenario without a block was authorized")
	_check(Dictionary(verdict["switches"]).is_empty(), "01 a switch was requested with no block")
	_check(Auth.activation_report(verdict)["authorized"] == false,
			"01 the report claims an activation with no block")

	# El escenario normalizado y vuelto a guardar es el mismo, byte a byte.
	var once: Dictionary = Serializer.normalize_editor_data(scenario)
	var first: String = JSON.stringify(once, "\t")
	var twice: String = JSON.stringify(Serializer.normalize_editor_data(once), "\t")
	_check(first == twice, "01 normalizing twice changed the scenario")
	_check(not first.contains(Auth.AUTHORIZATION_KEY),
			"01 a scenario without authorization gained the key")

	# Y el motor nace con los cinco apagados y la red sin un solo elemento.
	var engine_flags: Dictionary = _engine_switches(once)
	for flag in SWITCHES:
		_check(not bool(engine_flags[flag]), "01 '%s' switched itself on" % flag)
	var elements: Dictionary = _off_elements(once)
	_check(int(elements["cracks"]) == 0, "01 a crack element appeared with everything off")
	_check(int(elements["glazing"]) == 0, "01 a glazing element appeared with everything off")
	_check(int(elements["envelopes"]) == 0, "01 an envelope element appeared with everything off")


# ------------------------------------------------------------
# 02 solo las familias pedidas
# ------------------------------------------------------------

func _test_02_only_the_requested_families() -> void:
	var scenario: Dictionary = _configured_scenario()
	# Una sola familia, de las cuatro disponibles.
	var granted: Dictionary = Auth.grant(
		scenario, [Auth.FAMILY_DOOR_LEAKAGE], Auth.REQUIRED_ACKNOWLEDGEMENTS, true
	)
	_check(bool(granted["ok"]), "02 a single-family authorization was refused: %s"
			% str(granted["errors"]))
	if not bool(granted["ok"]):
		return
	var authorized: Dictionary = scenario.duplicate(true)
	authorized[Auth.AUTHORIZATION_KEY] = granted["authorization"]
	var verdict: Dictionary = Auth.resolve(authorized)
	_check(bool(verdict["authorized"]), "02 the authorization did not resolve: %s"
			% str(verdict["errors"]))
	var switches: Dictionary = verdict["switches"]
	_check(bool(switches.get("pressure_network_solver_enabled", false)),
			"02 the network dependency was not requested")
	_check(bool(switches.get("closed_door_leakage_enabled", false)),
			"02 D1 was not switched on although it was requested")
	for other in [
		"closed_door_deformation_enabled", "glazing_fallout_enabled",
		"exterior_envelope_leakage_enabled",
	]:
		_check(not switches.has(other), "02 '%s' was switched on without being asked" % other)

	# Y el motor las aplica igual: las pedidas si, las demas no.
	var flags: Dictionary = _engine_switches(Serializer.normalize_editor_data(authorized))
	_check(bool(flags["pressure_network_solver_enabled"]), "02 the engine did not enable the network")
	_check(bool(flags["closed_door_leakage_enabled"]), "02 the engine did not enable D1")
	_check(not bool(flags["closed_door_deformation_enabled"]), "02 the engine enabled D2 by itself")
	_check(not bool(flags["glazing_fallout_enabled"]), "02 the engine enabled D3 by itself")
	_check(not bool(flags["exterior_envelope_leakage_enabled"]), "02 the engine enabled R3 by itself")
	_check(String(flags["failure"]).is_empty(), "02 a valid authorization was refused by the engine")

	# Las cuatro juntas tambien, y siguen siendo cuatro.
	var all_families: Array[String] = Auth.available_families(scenario)
	_check(all_families.size() == 4, "02 the fixture does not offer the four families")
	var all_granted: Dictionary = Auth.grant(
		scenario, all_families, Auth.REQUIRED_ACKNOWLEDGEMENTS, true
	)
	_check(bool(all_granted["ok"]), "02 the four-family authorization was refused: %s"
			% str(all_granted["errors"]))
	if not bool(all_granted["ok"]):
		return
	var four: Dictionary = scenario.duplicate(true)
	four[Auth.AUTHORIZATION_KEY] = all_granted["authorization"]
	var four_flags: Dictionary = _engine_switches(Serializer.normalize_editor_data(four))
	for flag in SWITCHES:
		_check(bool(four_flags[flag]), "02 '%s' stayed off with the four families granted" % flag)


# ------------------------------------------------------------
# 03 revocar devuelve a OFF
# ------------------------------------------------------------

func _test_03_revoking_returns_to_off() -> void:
	var scenario: Dictionary = _configured_scenario()
	var before: String = JSON.stringify(Serializer.normalize_editor_data(scenario), "\t")
	var document = DocumentScript.new()
	document.data = scenario.duplicate(true)
	var granted: Dictionary = document.grant_experimental_authorization(
		Auth.available_families(scenario), Auth.REQUIRED_ACKNOWLEDGEMENTS, true
	)
	_check(bool(granted["ok"]), "03 the document could not grant: %s" % str(granted["errors"]))
	_check(Auth.declares(document.data), "03 the granted authorization was not written")
	_check(document.revoke_experimental_authorization(), "03 revoking did nothing")
	_check(not Auth.declares(document.data), "03 the authorization survived the revocation")
	var after: String = JSON.stringify(Serializer.normalize_editor_data(document.data), "\t")
	_check(before == after, "03 revoking did not return the scenario to its previous bytes")
	var flags: Dictionary = _engine_switches(Serializer.normalize_editor_data(document.data))
	for flag in SWITCHES:
		_check(not bool(flags[flag]), "03 '%s' stayed on after revoking" % flag)
	# Revocar dos veces no hace nada y no apila un paso vacio.
	_check(not document.revoke_experimental_authorization(),
			"03 revoking twice reported a second change")


# ------------------------------------------------------------
# 04 rechazos explicitos
# ------------------------------------------------------------

func _test_04_invalid_profiles_are_rejected() -> void:
	# a) bloqueado: no llega ni a configurarse, y menos a autorizarse.
	var window: Dictionary = _glazed_window()
	var blocked: Dictionary = PhysicsEditor.set_profile(
		window, Schema.GLAZING_PROFILE_KEY, BLOCKED_GLAZING, 1, true
	)
	_check(not bool(blocked["ok"]), "04 a blocked profile could be configured")
	var forced: Dictionary = window.duplicate(true)
	forced[Schema.SCHEMA_KEY] = 3
	forced[Schema.GLAZING_PROFILE_KEY] = {
		Schema.PROFILE_ID_KEY: BLOCKED_GLAZING,
		Schema.PROFILE_VERSION_KEY: 1,
		Schema.PROFILE_EFFECTIVE_KEY: {},
	}
	_check_rejected(forced, [Auth.FAMILY_GLAZING], "04 blocked")

	# b) version no publicada.
	var unknown_version: Dictionary = _door_with_leakage_profile()
	unknown_version[Schema.LEAKAGE_PROFILE_KEY][Schema.PROFILE_VERSION_KEY] = 99
	_check_rejected(unknown_version, [Auth.FAMILY_DOOR_LEAKAGE], "04 unpublished version")

	# c) perfil desconocido.
	var unknown_profile: Dictionary = _door_with_leakage_profile()
	unknown_profile[Schema.LEAKAGE_PROFILE_KEY][Schema.PROFILE_ID_KEY] = "door.invented"
	_check_rejected(unknown_profile, [Auth.FAMILY_DOOR_LEAKAGE], "04 unknown profile")

	# d) incompatible: la fuga de puerta en una ventana exterior.
	var incompatible: Dictionary = _exterior_window()
	incompatible[Schema.SCHEMA_KEY] = 2
	incompatible[Schema.LEAKAGE_PROFILE_KEY] = Schema.build_profile_block(DERIVED_LEAKAGE, 1)
	_check_rejected(incompatible, [Auth.FAMILY_DOOR_LEAKAGE], "04 incompatible category")

	# e) copia congelada alterada: el numero ya no es el del catalogo.
	var tampered: Dictionary = _door_with_leakage_profile()
	tampered[Schema.LEAKAGE_PROFILE_KEY][Schema.PROFILE_EFFECTIVE_KEY]["ela_m2"] = 0.5
	_check_rejected(tampered, [Auth.FAMILY_DOOR_LEAKAGE], "04 tampered frozen copy")


## Una abertura invalida no se puede autorizar, y si alguien fabrica el bloque a
## mano la resolucion lo rechaza con un error, no en silencio.
func _check_rejected(opening: Dictionary, families: Array, label: String) -> void:
	var scenario: Dictionary = _scenario([opening])
	var granted: Dictionary = Auth.grant(
		scenario, families, Auth.REQUIRED_ACKNOWLEDGEMENTS, true
	)
	_check(not bool(granted["ok"]), "%s: grant() accepted it" % label)
	# Fabricado a mano, con huella valida: tiene que seguir rechazandose.
	var forged: Dictionary = scenario.duplicate(true)
	forged[Auth.AUTHORIZATION_KEY] = {
		Auth.VERSION_FIELD: Auth.AUTHORIZATION_VERSION,
		Auth.FAMILIES_FIELD: families,
		Auth.ACKNOWLEDGED_FIELD: Auth.REQUIRED_ACKNOWLEDGEMENTS.duplicate(),
		Auth.EXPERIMENTAL_FIELD: true,
		Auth.DIGEST_FIELD: Auth.digest(scenario, families),
	}
	var verdict: Dictionary = Auth.resolve(forged)
	_check(not bool(verdict["authorized"]), "%s: a forged block was authorized" % label)
	_check(not Array(verdict["errors"]).is_empty(), "%s: rejected without saying why" % label)
	# Y el motor se niega a simular en vez de correr apagado.
	var flags: Dictionary = _engine_switches(forged)
	_check(not String(flags["failure"]).is_empty(), "%s: the engine ran anyway" % label)
	for flag in SWITCHES:
		_check(not bool(flags[flag]), "%s: '%s' switched on with an invalid profile"
				% [label, flag])


# ------------------------------------------------------------
# 05 D2 y D3 siguen siendo prescripcion
# ------------------------------------------------------------

func _test_05_d2_and_d3_stay_prescriptions() -> void:
	_check(Auth.PRESCRIBED_FAMILIES.has(Auth.FAMILY_DEFORMATION),
			"05 D2 is no longer declared a prescription")
	_check(Auth.PRESCRIBED_FAMILIES.has(Auth.FAMILY_GLAZING),
			"05 D3 is no longer declared a prescription")
	_check(Auth.ACK_PRESCRIBED.contains("no predice"),
			"05 the consent no longer says the engine does not predict it")
	# Sus ranuras no aportan NINGUN numero al motor: siguen siendo procedencia.
	_check(String(Schema.PROFILE_SLOT_PARAMETER[Schema.DEFORMATION_PROFILE_KEY]).is_empty(),
			"05 the deformation slot started feeding a number to the engine")
	_check(String(Schema.PROFILE_SLOT_PARAMETER[Schema.GLAZING_PROFILE_KEY]).is_empty(),
			"05 the glazing slot started feeding a number to the engine")

	# Autorizadas y todo, el vidrio no se rompe solo: a t = 0 la ventana no
	# aporta area, y solo la aporta cuando la PRESCRIPCION lo dice.
	var scenario: Dictionary = _configured_scenario()
	var granted: Dictionary = Auth.grant(
		scenario, [Auth.FAMILY_GLAZING, Auth.FAMILY_DEFORMATION],
		Auth.REQUIRED_ACKNOWLEDGEMENTS, true
	)
	_check(bool(granted["ok"]), "05 D2+D3 could not be authorized: %s" % str(granted["errors"]))
	if not bool(granted["ok"]):
		return
	var authorized: Dictionary = Serializer.normalize_editor_data(scenario)
	authorized[Auth.AUTHORIZATION_KEY] = granted["authorization"]
	var early: Dictionary = _on_elements(authorized, 0.0)
	_check(int(early["glazing"]) == 0, "05 the glass broke by itself at t = 0")
	var late: Dictionary = _on_elements(authorized, 240.0)
	_check(int(late["glazing"]) > 0, "05 the prescribed fallout never reached the network")
	# El motor no gana ninguna ley: `glass_broken` sigue sin tocarse.
	_check(not Dictionary(_configured_scenario()["openings_data"][2]).has("glass_broken"),
			"05 the fixture window already carries an operational break")


# ------------------------------------------------------------
# 06 la dependencia de red
# ------------------------------------------------------------

func _test_06_the_network_dependency_is_mandatory() -> void:
	_check(Auth.REQUIRED_DEPENDENCY == "pressure_network_solver_enabled",
			"06 the declared dependency is not the network solver")
	var scenario: Dictionary = _configured_scenario()
	for family in Auth.FAMILIES:
		var granted: Dictionary = Auth.grant(
			scenario, [String(family)], Auth.REQUIRED_ACKNOWLEDGEMENTS, true
		)
		if not bool(granted["ok"]):
			_check(false, "06 '%s' could not be authorized alone: %s"
					% [String(family), str(granted["errors"])])
			continue
		var authorized: Dictionary = scenario.duplicate(true)
		authorized[Auth.AUTHORIZATION_KEY] = granted["authorization"]
		var switches: Dictionary = Auth.resolve(authorized)["switches"]
		_check(bool(switches.get(Auth.REQUIRED_DEPENDENCY, false)),
				"06 '%s' was granted without the network" % String(family))
	# Y al reves: la red NO se enciende cuando no hay ninguna familia autorizada.
	var bare: Dictionary = Auth.resolve(_configured_scenario())
	_check(Dictionary(bare["switches"]).is_empty(),
			"06 the network switched on with no family authorized")


# ------------------------------------------------------------
# 07 ninguna fuga se suma dos veces
# ------------------------------------------------------------

func _test_07_no_leak_is_counted_twice() -> void:
	# La regla es de D4B1 y aqui se vuelve a medir con la familia ENCENDIDA:
	# una ventana con area propia usa la SUYA, no la suya mas la global.
	var window: Dictionary = _exterior_window()
	window[Schema.SCHEMA_KEY] = 2
	window[Schema.FRAME_PROFILE_KEY] = Schema.build_profile_block(FRAME_PROFILE, 1)
	var scenario: Dictionary = _scenario([_interior_door(), window])
	var granted: Dictionary = Auth.grant(
		scenario, [Auth.FAMILY_FRAME_LEAKAGE], Auth.REQUIRED_ACKNOWLEDGEMENTS, true
	)
	_check(bool(granted["ok"]), "07 R3 could not be authorized: %s" % str(granted["errors"]))
	if not bool(granted["ok"]):
		return
	var authorized: Dictionary = Serializer.normalize_editor_data(scenario)
	authorized[Auth.AUTHORIZATION_KEY] = granted["authorization"]
	var building = BuildingModelScript.new()
	if not building.load_template_data(Serializer.to_runtime_template(authorized)):
		_check(false, "07 the authorized scenario did not load")
		building.free()
		return
	var transport = TransportScript.new()
	transport.exterior_envelope_leakage_enabled = true
	# La global historica, distinta de la del perfil, para que sumar se notase.
	transport.exterior_envelope_leakage_area_m2 = 0.123
	var snapshot: Dictionary = transport.build_snapshot(building, {}, 0.25, 10.0)
	var own: float = float(Dictionary(Catalog.find(FRAME_PROFILE, 1))["parameters"]["leak_area_m2"])
	var envelopes: int = 0
	for raw_element in Array(snapshot["openings"]):
		var element: Dictionary = raw_element
		if String(element.get("provenance", "")) != "exterior_envelope_leakage":
			continue
		envelopes += 1
		var area: float = float(element.get("leak_area_m2", element.get("area_m2", -1.0)))
		if area < 0.0:
			continue
		_check(absf(area - own) < 1.0e-12 or absf(area - 0.123) < 1.0e-12,
				"07 the envelope area is neither the profile's nor the global one: %f" % area)
		_check(absf(area - (own + 0.123)) > 1.0e-12,
				"07 the own area and the global one were added together")
	_check(envelopes > 0, "07 R3 produced no envelope element although it was authorized")
	building.free()


# ------------------------------------------------------------
# 08 estado operativo aparte
# ------------------------------------------------------------

func _test_08_operational_state_is_independent() -> void:
	var scenario: Dictionary = _configured_scenario()
	var granted: Dictionary = Auth.grant(
		scenario, Auth.available_families(scenario), Auth.REQUIRED_ACKNOWLEDGEMENTS, true
	)
	_check(bool(granted["ok"]), "08 the fixture could not be authorized")
	if not bool(granted["ok"]):
		return
	var authorized: Dictionary = scenario.duplicate(true)
	authorized[Auth.AUTHORIZATION_KEY] = granted["authorization"]
	# Abrir la puerta no toca ni el perfil ni la autorizacion.
	var opened: Dictionary = authorized.duplicate(true)
	Dictionary(Array(opened["openings_data"])[1])["open_fraction"] = 1.0
	_check(Auth.declares(opened), "08 opening a door erased the authorization")
	_check(Dictionary(Array(opened["openings_data"])[1]).has(Schema.LEAKAGE_PROFILE_KEY),
			"08 opening a door erased the profile")
	# Y la huella NO depende del estado operativo: abrir no caduca el permiso.
	_check(Auth.digest(opened, Auth.available_families(scenario))
			== Auth.digest(authorized, Auth.available_families(scenario)),
			"08 the operational state entered the authorization digest")
	_check(bool(Auth.resolve(opened)["authorized"]),
			"08 opening a door revoked the authorization")


# ------------------------------------------------------------
# 09 salida diagnostica
# ------------------------------------------------------------

func _test_09_the_diagnostic_output_is_complete() -> void:
	var scenario: Dictionary = _configured_scenario()
	var families: Array[String] = Auth.available_families(scenario)
	var granted: Dictionary = Auth.grant(
		scenario, families, Auth.REQUIRED_ACKNOWLEDGEMENTS, true
	)
	if not bool(granted["ok"]):
		_check(false, "09 the fixture could not be authorized: %s" % str(granted["errors"]))
		return
	var authorized: Dictionary = Serializer.normalize_editor_data(scenario)
	authorized[Auth.AUTHORIZATION_KEY] = granted["authorization"]
	var report: Dictionary = Auth.activation_report(Auth.resolve(authorized))
	for key in [
		"authorization_version", "declares", "authorized", "errors", "families",
		"switches", "dependency", "prescribed_families", "profiles", "limits",
		"scenario_digest", "product_activation_granted", "not_a_validation",
		"pressure_domain_max_pa", "domain_exceeded", "domain_exceeded_steps",
		"max_abs_dp_pa",
	]:
		_check(report.has(String(key)), "09 the report omits '%s'" % String(key))
	_check(not bool(report["product_activation_granted"]),
			"09 the report claims a product activation")
	_check(String(report["not_a_validation"]).contains("No es una validación"),
			"09 the report does not say it is not a validation")
	var profiles: Array = report["profiles"]
	_check(profiles.size() >= families.size(), "09 the report lists no provenance")
	var openings: Array = authorized["openings_data"]
	for raw_entry in profiles:
		var entry: Dictionary = raw_entry
		# La procedencia de una familia sale de SU ranura, no de otra. Sin esto,
		# leer siempre la ranura de fuga pasaria desapercibido.
		var slot: String = String(Auth.FAMILY_PROFILE_SLOT[String(entry["family"])])
		var opening: Dictionary = openings[int(entry["opening_index"])]
		var declared: String = ""
		if typeof(opening.get(slot, null)) == TYPE_DICTIONARY:
			declared = Catalog.versioned_id(
				String(Dictionary(opening[slot]).get(Schema.PROFILE_ID_KEY, "")),
				int(Dictionary(opening[slot]).get(Schema.PROFILE_VERSION_KEY, 0))
			)
		_check(String(entry["versioned_id"]) == declared,
				"09 family '%s' reports '%s' but its slot declares '%s'" % [
					String(entry["family"]), String(entry["versioned_id"]), declared
				])
		_check(String(Catalog.find(
					String(entry["profile_id"]), int(entry["profile_version"])
				).get("category", String(entry["family"]))) == String(entry["family"]),
				"09 family '%s' reports a profile of another category" % String(entry["family"]))
		for key2 in [
			"family", "opening_index", "profile_id", "profile_version",
			"versioned_id", "evidence", "product_activation", "effective",
			"units", "domain", "warnings", "prescribed",
		]:
			_check(entry.has(String(key2)), "09 a provenance entry omits '%s'" % String(key2))
		_check(not bool(entry["product_activation"]),
				"09 a provenance entry claims product activation")
	# Determinista: dos veces lo mismo, byte a byte.
	var first: String = JSON.stringify(report, "\t")
	var second: String = JSON.stringify(
		Auth.activation_report(Auth.resolve(authorized)), "\t"
	)
	_check(first == second, "09 the report is not deterministic")
	# Y el motor lo publica en el informe tecnico.
	var summary: Dictionary = _technical_summary(authorized)
	_check(summary.has("experimental_activation"),
			"09 the technical summary omits the activation block")
	# Un escenario sin autorizacion NO gana el bloque.
	var plain: Dictionary = _technical_summary(
		Serializer.normalize_editor_data(_configured_scenario())
	)
	_check(not plain.has("experimental_activation"),
			"09 a scenario without authorization gained the activation block")


# ------------------------------------------------------------
# 10 fuera de dominio: se marca, no se recorta
# ------------------------------------------------------------

func _test_10_out_of_domain_is_marked_not_clipped() -> void:
	_check(Auth.PRESSURE_DOMAIN_MAX_PA == 50.0,
			"10 the declared pressure domain moved away from the source's 50 Pa")
	var verdict: Dictionary = Auth.resolve(_authorized_scenario())
	var found: bool = false
	for limit in Array(verdict["limits"]):
		if String(limit).contains("Dominio de presión"):
			found = true
			_check(String(limit).contains("no se recorta"),
					"10 the limit does not say the flow is not clipped")
	_check(found, "10 the consent does not name the pressure domain")
	var report: Dictionary = Auth.activation_report(verdict)
	_check(not bool(report["domain_exceeded"]), "10 the report starts already out of domain")
	_check(int(report["domain_exceeded_steps"]) == 0, "10 the report starts with marks")
	_check(float(report["pressure_domain_max_pa"]) == Auth.PRESSURE_DOMAIN_MAX_PA,
			"10 the report publishes another domain")


# ------------------------------------------------------------
# 11 escenarios distribuidos
# ------------------------------------------------------------

func _test_11_no_distributed_scenario_authorizes() -> void:
	var seen: int = 0
	for folder in ["res://scenarios", "res://tests/fixtures"]:
		var dir := DirAccess.open(folder)
		if dir == null:
			continue
		for file_name in dir.get_files():
			if not String(file_name).ends_with(".json"):
				continue
			seen += 1
			var path: String = "%s/%s" % [folder, String(file_name)]
			var file := FileAccess.open(path, FileAccess.READ)
			if file == null:
				continue
			var text: String = file.get_as_text()
			file.close()
			_check(not text.contains(Auth.AUTHORIZATION_KEY),
					"11 %s declares an experimental authorization" % path)
			for flag in SWITCHES:
				_check(not text.contains(flag), "11 %s names the switch '%s'" % [path, flag])
			var parsed: Variant = JSON.parse_string(text)
			if typeof(parsed) != TYPE_DICTIONARY:
				continue
			_check(not Auth.declares(Dictionary(parsed)),
					"11 %s resolves to an authorization" % path)
			_check(Auth.available_families(Dictionary(parsed)).is_empty(),
					"11 %s configures an experimental family" % path)
	_check(seen > 0, "11 no distributed scenario was swept")


# ------------------------------------------------------------
# 12 nada apto para producto
# ------------------------------------------------------------

func _test_12_no_profile_is_product_ready() -> void:
	_check(Catalog.product_ready_ids().is_empty(),
			"12 a profile is declared ready for product activation")
	for raw_profile in Catalog.PROFILES:
		var profile: Dictionary = raw_profile
		_check(not bool(profile["product_activation"]),
				"12 '%s' claims product activation" % String(profile["profile_id"]))
	# Y autorizar una corrida experimental no lo cambia.
	var report: Dictionary = Auth.activation_report(Auth.resolve(_authorized_scenario()))
	_check(not bool(report["product_activation_granted"]),
			"12 authorizing a run granted product activation")
	_check(Catalog.product_ready_ids().is_empty(),
			"12 authorizing a run moved a profile into the product list")


# ------------------------------------------------------------
# 13 el consentimiento
# ------------------------------------------------------------

func _test_13_the_consent_says_the_four_things() -> void:
	_check(Auth.REQUIRED_ACKNOWLEDGEMENTS.size() == 4,
			"13 the contract no longer asks for four confirmations")
	_check(Auth.ACK_EXPERIMENTAL.contains("no validados para una vivienda"),
			"13 the experimental statement changed")
	var scenario: Dictionary = _configured_scenario()
	var families: Array[String] = Auth.available_families(scenario)
	var request: Dictionary = Auth.consent_request(scenario, families)
	_check(Array(request["errors"]).is_empty(), "13 the consent could not be built: %s"
			% str(request["errors"]))
	_check(Array(request["families"]).size() == families.size(),
			"13 the consent does not describe every family")
	var text: String = Auth.consent_text(request)
	_check(text.contains(Auth.ACK_EXPERIMENTAL), "13 the consent does not warn it is experimental")
	_check(text.contains(Auth.REQUIRED_DEPENDENCY), "13 the consent hides the network dependency")
	_check(text.contains("Dominio de presión"), "13 the consent hides the pressure domain")
	_check(text.contains(Auth.ACK_PRESCRIBED), "13 the consent hides that D2/D3 are prescriptions")
	_check(text.contains("ela_m2"), "13 the consent hides the effective values")
	# Sin las cuatro, no hay autorizacion.
	for index in range(Auth.REQUIRED_ACKNOWLEDGEMENTS.size()):
		var partial: Array[String] = []
		for other in range(Auth.REQUIRED_ACKNOWLEDGEMENTS.size()):
			if other != index:
				partial.append(Auth.REQUIRED_ACKNOWLEDGEMENTS[other])
		var granted: Dictionary = Auth.grant(scenario, families, partial, true)
		_check(not bool(granted["ok"]), "13 three confirmations were enough (missing %d)" % index)
	# Y fabricado a mano, saltandose `grant()`, tambien cae: quien exige las
	# cuatro no es solo quien concede, es tambien quien resuelve.
	for missing in range(Auth.REQUIRED_ACKNOWLEDGEMENTS.size()):
		var partial_block: Array[String] = []
		for other in range(Auth.REQUIRED_ACKNOWLEDGEMENTS.size()):
			if other != missing:
				partial_block.append(Auth.REQUIRED_ACKNOWLEDGEMENTS[other])
		var forged: Dictionary = _forged(scenario, families, partial_block, true)
		var verdict: Dictionary = Auth.resolve(forged)
		_check(not bool(verdict["authorized"]),
				"13 a forged block with three confirmations was authorized (missing %d)"
				% missing)
		_check(str(verdict["errors"]).contains("falta la confirmación"),
				"13 the rejection does not name the missing confirmation")

	# Y un perfil `research_only` exige ademas la confirmacion experimental.
	var research: Dictionary = _scenario([_door_with_leakage_profile()])
	var without: Dictionary = Auth.grant(
		research, [Auth.FAMILY_DOOR_LEAKAGE], Auth.REQUIRED_ACKNOWLEDGEMENTS, false
	)
	_check(not bool(without["ok"]),
			"13 a research_only profile ran without the experimental confirmation")
	var with_it: Dictionary = Auth.grant(
		research, [Auth.FAMILY_DOOR_LEAKAGE], Auth.REQUIRED_ACKNOWLEDGEMENTS, true
	)
	_check(bool(with_it["ok"]), "13 a research_only profile was refused with the confirmation: %s"
			% str(with_it["errors"]))


# ------------------------------------------------------------
# 14 caducidad
# ------------------------------------------------------------

func _test_14_the_authorization_expires_by_itself() -> void:
	var authorized: Dictionary = _authorized_scenario()
	_check(bool(Auth.resolve(authorized)["authorized"]), "14 the fixture does not resolve")
	# Cambiar el perfil de una abertura participante caduca el permiso.
	var swapped: Dictionary = authorized.duplicate(true)
	var door: Dictionary = Array(swapped["openings_data"])[1]
	door[Schema.LEAKAGE_PROFILE_KEY] = Schema.build_profile_block(DERIVED_LEAKAGE, 1)
	var swapped_verdict: Dictionary = Auth.resolve(swapped)
	_check(not bool(swapped_verdict["authorized"]),
			"14 swapping the profile kept the authorization alive")
	_check(str(swapped_verdict["errors"]).contains("huella"),
			"14 the rejection does not name the digest")
	# Añadir una prescripcion tambien.
	var grown: Dictionary = authorized.duplicate(true)
	var deformed: Dictionary = Array(grown["openings_data"])[1]
	var tracks: Array = Array(deformed[Schema.DEFORMATION_KEY]).duplicate(true)
	Dictionary(tracks[0])["points"] = [[0.0, 0.0], [60.0, 0.0005], [120.0, 0.004]]
	deformed[Schema.DEFORMATION_KEY] = tracks
	_check(not bool(Auth.resolve(grown)["authorized"]),
			"14 changing the prescription kept the authorization alive")
	# Una version de contrato no soportada tampoco.
	var other_version: Dictionary = authorized.duplicate(true)
	var block_v: Dictionary = Dictionary(other_version[Auth.AUTHORIZATION_KEY]).duplicate(true)
	block_v[Auth.VERSION_FIELD] = Auth.AUTHORIZATION_VERSION + 98
	other_version[Auth.AUTHORIZATION_KEY] = block_v
	var version_verdict: Dictionary = Auth.resolve(other_version)
	_check(not bool(version_verdict["authorized"]),
			"14 an unsupported authorization_version was accepted")
	_check(str(version_verdict["errors"]).contains("versión"),
			"14 the rejection does not name the version")
	# Y una version fraccionaria, que el fichero no sabe distinguir de un entero,
	# se deja intacta y se rechaza en vez de truncarse.
	var fractional: Dictionary = authorized.duplicate(true)
	var block_f: Dictionary = Dictionary(fractional[Auth.AUTHORIZATION_KEY]).duplicate(true)
	block_f[Auth.VERSION_FIELD] = 1.5
	fractional[Auth.AUTHORIZATION_KEY] = block_f
	_check(not bool(Auth.resolve(fractional)["authorized"]),
			"14 a fractional authorization_version was accepted")

	# Y una huella inventada no cuela.
	var forged: Dictionary = authorized.duplicate(true)
	var block: Dictionary = Dictionary(forged[Auth.AUTHORIZATION_KEY]).duplicate(true)
	block[Auth.DIGEST_FIELD] = "0".repeat(64)
	forged[Auth.AUTHORIZATION_KEY] = block
	_check(not bool(Auth.resolve(forged)["authorized"]), "14 a forged digest was accepted")
	# Una clave de mas tampoco.
	var extra: Dictionary = authorized.duplicate(true)
	var block2: Dictionary = Dictionary(extra[Auth.AUTHORIZATION_KEY]).duplicate(true)
	block2["product_activation"] = true
	extra[Auth.AUTHORIZATION_KEY] = block2
	_check(not bool(Auth.resolve(extra)["authorized"]),
			"14 an unknown key in the authorization was accepted")


# ------------------------------------------------------------
# 15 el recorrido real
# ------------------------------------------------------------

func _test_15_the_real_editor_to_engine_path() -> void:
	var document = DocumentScript.new()
	document.data = _configured_scenario()
	var families: Array[String] = Auth.available_families(document.data)
	var granted: Dictionary = document.grant_experimental_authorization(
		families, Auth.REQUIRED_ACKNOWLEDGEMENTS, true
	)
	_check(bool(granted["ok"]), "15 the document refused a valid grant: %s"
			% str(granted["errors"]))
	if not bool(granted["ok"]):
		return
	# Guardar y volver a leer, que es lo que hace el editor al ejecutar.
	var scenario_path: String = "%s/scenario.json" % WORK_DIR
	var template_path: String = "%s/runtime.json" % WORK_DIR
	_check(Serializer.save_scenario(scenario_path, document.data), "15 the scenario did not save")
	var reloaded: Dictionary = Serializer.load_scenario(scenario_path)
	_check(Auth.declares(reloaded), "15 the authorization did not survive the file")
	_check(Serializer.validate_scenario(reloaded).is_empty(),
			"15 the reloaded scenario does not validate: %s"
			% str(Serializer.validate_scenario(reloaded)))
	_check(Serializer.save_runtime_template(template_path, reloaded),
			"15 the runtime template did not save")
	var file := FileAccess.open(template_path, FileAccess.READ)
	_check(file != null, "15 the runtime template could not be read back")
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	_check(typeof(parsed) == TYPE_DICTIONARY, "15 the runtime template is not a dictionary")
	var template: Dictionary = parsed
	_check(template.has(Auth.AUTHORIZATION_KEY),
			"15 the runtime template lost the authorization")
	var building = BuildingModelScript.new()
	_check(building.load_template_data(template), "15 the runtime template did not load")
	_check(not building.experimental_physics_authorization.is_empty(),
			"15 the building did not keep the authorization")
	var engine: SimulationEngine = _engine_for(building, "Path")
	for flag in SWITCHES:
		_check(bool(engine.get(flag)), "15 '%s' stayed off along the real path" % flag)
	_check(String(engine.experimental_authorization_failure).is_empty(),
			"15 the engine refused a valid authorization: %s"
			% String(engine.experimental_authorization_failure))
	var report: Dictionary = engine.get_experimental_activation_report()
	_check(bool(report.get("authorized", false)), "15 the engine report is not authorized")
	_check(String(report.get("scenario_digest", "")).length() == 64,
			"15 the engine report carries no digest")
	_free_engine(engine, building)
	# Y una plantilla con la autorizacion rota no llega ni a cargar.
	var broken: Dictionary = template.duplicate(true)
	Dictionary(broken[Auth.AUTHORIZATION_KEY])[Auth.DIGEST_FIELD] = "0".repeat(64)
	var broken_building = BuildingModelScript.new()
	_check(not broken_building.load_template_data(broken),
			"15 a template with a broken authorization loaded anyway")
	broken_building.free()


# ------------------------------------------------------------
# 16 la marca de dominio llega al informe
# ------------------------------------------------------------

## El solver ya marca `domain_exceeded` y NO recorta el caudal: eso lo mide el
## validador de D1 a 5 kPa. Lo que se mide aqui es que esa marca llegue al
## informe de la corrida experimental en vez de quedarse por el camino.
func _test_16_the_domain_mark_reaches_the_report() -> void:
	var building = BuildingModelScript.new()
	if not building.load_template_data(
		Serializer.to_runtime_template(_authorized_scenario())
	):
		_check(false, "16 the authorized scenario did not load")
		building.free()
		return
	var engine: SimulationEngine = _engine_for(building, "Domain")
	var before: Dictionary = engine.get_experimental_activation_report()
	_check(not bool(before["domain_exceeded"]), "16 the report starts out of domain")
	_check(int(before["domain_exceeded_steps"]) == 0, "16 the report starts with marks")

	# Un resultado de red con una rendija fuera de dominio, tal cual lo publica
	# el solver. No se toca ninguna ley: se le da al motor lo que el solver
	# habria devuelto.
	engine.pressure_network_last_result = {
		"solution": {"openings": [
			{
				"opening_id": "op_0", "flow_model": "ela_crack",
				"domain_exceeded_count": 3.0, "max_abs_dp_pa": 5000.0,
			},
			{"opening_id": "op_1"},
		]},
	}
	engine._accumulate_experimental_domain_marks()
	var after: Dictionary = engine.get_experimental_activation_report()
	_check(bool(after["domain_exceeded"]), "16 the domain mark never reached the report")
	_check(int(after["domain_exceeded_steps"]) == 1, "16 the marked step was not counted")
	_check(float(after["max_abs_dp_pa"]) == 5000.0,
			"16 the observed pressure was not recorded")
	# Y el limite publicado no se mueve para tapar la marca.
	_check(float(after["pressure_domain_max_pa"]) == Auth.PRESSURE_DOMAIN_MAX_PA,
			"16 the published domain moved to hide the mark")
	# Un segundo paso marcado suma; uno limpio no.
	engine._accumulate_experimental_domain_marks()
	_check(int(engine.get_experimental_activation_report()["domain_exceeded_steps"]) == 2,
			"16 a second marked step was not counted")
	engine.pressure_network_last_result = {
		"solution": {"openings": [
			{"opening_id": "op_0", "flow_model": "ela_crack",
			"domain_exceeded_count": 0.0, "max_abs_dp_pa": 12.0},
		]},
	}
	engine._accumulate_experimental_domain_marks()
	var clean: Dictionary = engine.get_experimental_activation_report()
	_check(int(clean["domain_exceeded_steps"]) == 2, "16 a clean step was counted as marked")
	_check(float(clean["max_abs_dp_pa"]) == 5000.0,
			"16 a clean step lowered the observed maximum")
	_free_engine(engine, building)


# ------------------------------------------------------------
# 17 una autorizacion rechazada para la simulacion
# ------------------------------------------------------------

## El motor no corre con la fisica apagada cuando la autorizacion no resuelve:
## lo que se veria en pantalla no seria lo autorizado. Se comprueba sobre el
## camino que de verdad puede darse: la autorizacion se vuelve a resolver en
## cada `reset_simulation`, asi que un escenario que cambia entre una corrida y
## la siguiente tiene que pararla.
func _test_17_a_rejected_authorization_stops_the_simulation() -> void:
	var building = BuildingModelScript.new()
	if not building.load_template_data(
		Serializer.to_runtime_template(_authorized_scenario())
	):
		_check(false, "17 the authorized scenario did not load")
		building.free()
		return
	var engine: SimulationEngine = _engine_for(building, "Halt")
	_check(String(engine.experimental_authorization_failure).is_empty(),
			"17 a valid authorization was refused")
	engine.step(1.0)
	_check(float(engine.sim_time_s) > 0.0, "17 an authorized run did not advance")

	# Se altera la huella de lo que el modelo tiene cargado y se vuelve a montar
	# la corrida. La autorizacion deja de resolver.
	var tampered: Dictionary = building.experimental_physics_authorization.duplicate(true)
	tampered[Auth.DIGEST_FIELD] = "0".repeat(64)
	building.experimental_physics_authorization = tampered
	engine.reset_simulation(0, false)
	_check(not String(engine.experimental_authorization_failure).is_empty(),
			"17 the engine kept quiet about a rejected authorization")
	_check(float(engine.sim_time_s) == 0.0, "17 the reset did not rewind the clock")
	engine.step(1.0)
	_check(float(engine.sim_time_s) == 0.0,
			"17 the engine simulated with a rejected authorization")
	var report: Dictionary = engine.get_experimental_activation_report()
	_check(not bool(report["authorized"]), "17 the report still claims an activation")
	_check(not Array(report["errors"]).is_empty(), "17 the report does not say why")
	_free_engine(engine, building)


# ------------------------------------------------------------
# 18 ciclo de vida sobre UN MISMO motor
# ------------------------------------------------------------

## El defecto que motivo este grupo: revocar la autorizacion y reiniciar el
## MISMO `SimulationEngine` dejaba encendida la fisica de la corrida anterior, y
## el informe la daba por apagada. La prueba de revocacion que ya existia creaba
## un motor nuevo, asi que no podia verlo.
##
## Se miden las TRES cosas, no solo los booleanos: los interruptores, el
## informe y los elementos que la red emite de verdad.
func _test_18_the_lifecycle_on_one_engine() -> void:
	var building = BuildingModelScript.new()
	var authorized: Dictionary = _authorized_for([Auth.FAMILY_DOOR_LEAKAGE])
	if not building.load_template_data(Serializer.to_runtime_template(authorized)):
		_check(false, "18 the authorized scenario did not load")
		building.free()
		return
	var engine: SimulationEngine = _engine_for(building, "Lifecycle")

	# a) autorizada: D1 y la red encendidas, y la red emite su rendija.
	_check(bool(engine.pressure_network_solver_enabled), "18a the network stayed off")
	_check(bool(engine.closed_door_leakage_enabled), "18a D1 stayed off")
	_check(int(_engine_elements(engine, building)["cracks"]) > 0,
			"18a D1 was on but produced no crack element")
	engine.step(1.0)
	_check(float(engine.sim_time_s) > 0.0, "18a an authorized run did not advance")

	# b) revocada en el MISMO modelo y reiniciada en el MISMO motor.
	building.experimental_physics_authorization = {}
	engine.reset_simulation(0, false)
	for flag in SWITCHES:
		_check(not bool(engine.get(flag)),
				"18b '%s' survived the revocation on the same engine" % flag)
	_check(engine.get_experimental_activation_report().is_empty(),
			"18b the report is not inactive after revoking")
	_check(String(engine.experimental_authorization_failure).is_empty(),
			"18b revoking was reported as a failure")
	# Y lo que de verdad importa: la red deja de emitir.
	var after: Dictionary = _engine_elements(engine, building)
	_check(int(after["cracks"]) == 0, "18b a crack element survived the revocation")
	_check(int(after["glazing"]) == 0, "18b a glazing element survived the revocation")
	_check(int(after["envelopes"]) == 0, "18b an envelope element survived the revocation")

	# c) reinicios repetidos sin autorizacion: estable, sin acumulacion.
	for _repeat in range(3):
		engine.reset_simulation(0, false)
	for flag in SWITCHES:
		_check(not bool(engine.get(flag)), "18c '%s' came back on a later reset" % flag)
	_free_engine(engine, building)


## Cambiar de familia en el mismo motor: D1 se retira y D3 entra.
func _test_18b_swapping_families() -> void:
	var building = BuildingModelScript.new()
	if not building.load_template_data(
		Serializer.to_runtime_template(_authorized_for([Auth.FAMILY_DOOR_LEAKAGE]))
	):
		_check(false, "18d the D1 scenario did not load")
		building.free()
		return
	var engine: SimulationEngine = _engine_for(building, "Swap")
	_check(bool(engine.closed_door_leakage_enabled), "18d D1 did not come on")
	_check(not bool(engine.glazing_fallout_enabled), "18d D3 came on unasked")

	# La nueva autorizacion, solo D3, sobre el MISMO modelo y el MISMO motor.
	var glazing_only: Dictionary = _authorized_for([Auth.FAMILY_GLAZING])
	building.experimental_physics_authorization = Dictionary(
		glazing_only[Auth.AUTHORIZATION_KEY]
	).duplicate(true)
	engine.reset_simulation(0, false)
	_check(not bool(engine.closed_door_leakage_enabled),
			"18d D1 survived the switch to D3")
	_check(bool(engine.glazing_fallout_enabled), "18d D3 did not come on")
	_check(bool(engine.pressure_network_solver_enabled),
			"18d the network was dropped when swapping family")
	_check(not bool(engine.closed_door_deformation_enabled), "18d D2 came on unasked")
	_check(not bool(engine.exterior_envelope_leakage_enabled), "18d R3 came on unasked")
	var elements: Dictionary = _engine_elements(engine, building)
	_check(int(elements["cracks"]) == 0, "18d a crack element survived the swap to D3")
	_check(int(elements["glazing"]) > 0, "18d D3 was on but produced no glazing element")
	var report: Dictionary = engine.get_experimental_activation_report()
	_check(Array(report["families"]) == [Auth.FAMILY_GLAZING],
			"18d the report does not name exactly the new family")
	_free_engine(engine, building)


## Una autorizacion que deja de resolver no hereda la fisica de la anterior.
func _test_18c_a_tampered_block_inherits_nothing() -> void:
	var building = BuildingModelScript.new()
	if not building.load_template_data(
		Serializer.to_runtime_template(_authorized_for([Auth.FAMILY_DOOR_LEAKAGE]))
	):
		_check(false, "18e the scenario did not load")
		building.free()
		return
	var engine: SimulationEngine = _engine_for(building, "Tampered")
	_check(bool(engine.closed_door_leakage_enabled), "18e D1 did not come on")
	var tampered: Dictionary = building.experimental_physics_authorization.duplicate(true)
	tampered[Auth.DIGEST_FIELD] = "0".repeat(64)
	building.experimental_physics_authorization = tampered
	engine.reset_simulation(0, false)
	for flag in SWITCHES:
		_check(not bool(engine.get(flag)),
				"18e '%s' was inherited by a tampered authorization" % flag)
	_check(not String(engine.experimental_authorization_failure).is_empty(),
			"18e the tampered block was accepted")
	_check(float(engine.sim_time_s) == 0.0, "18e the clock was not rewound")
	engine.step(1.0)
	_check(float(engine.sim_time_s) == 0.0,
			"18e the engine advanced with a tampered authorization")
	var report: Dictionary = engine.get_experimental_activation_report()
	_check(not bool(report["authorized"]), "18e the report still claims an activation")
	var effective: Dictionary = report["effective_switches"]
	for flag in SWITCHES:
		_check(not bool(effective[flag]),
				"18e the report claims '%s' is on after a tampered block" % flag)
	_free_engine(engine, building)


# ------------------------------------------------------------
# 19 propiedad de cada interruptor
# ------------------------------------------------------------

## La autorizacion solo puede retirar lo que ELLA anadio. Apagar los cinco al
## reiniciar seria mas simple y estaria mal: borraria la configuracion de otro
## propietario.
func _test_19_switch_ownership_and_precedence() -> void:
	_test_18b_swapping_families()
	_test_18c_a_tampered_block_inherits_nothing()

	# a) la red estaba encendida ANTES por otro propietario: sobrevive.
	var building = BuildingModelScript.new()
	if not building.load_template_data(
		Serializer.to_runtime_template(_authorized_for([Auth.FAMILY_DOOR_LEAKAGE]))
	):
		_check(false, "19a the scenario did not load")
		building.free()
		return
	var engine: SimulationEngine = SimulationEngineScript.new()
	engine.name = "ExperimentalActivationOwnership"
	engine.building = building
	engine.auto_ignite_on_ready = false
	engine.auto_finish_on_extinction = false
	engine.enable_logging = false
	engine.enable_csv_log = false
	# Configuracion explicita de OTRO propietario, antes de que la autorizacion
	# toque nada.
	engine.pressure_network_solver_enabled = true
	root.add_child(engine)
	engine.reset_simulation(0, false)
	_check(bool(engine.pressure_network_solver_enabled), "19a the network was dropped")
	_check(bool(engine.closed_door_leakage_enabled), "19a D1 did not come on")

	building.experimental_physics_authorization = {}
	engine.reset_simulation(0, false)
	_check(bool(engine.pressure_network_solver_enabled),
			"19a revoking erased a network configured by another owner")
	_check(not bool(engine.closed_door_leakage_enabled),
			"19a D1 was not returned to its previous value")
	root.remove_child(engine)
	engine.free()
	building.free()

	# b) otro propietario apaga un interruptor DESPUES de la autorizacion: la
	# autorizacion deja de ser su dueno y no lo vuelve a escribir.
	var building_b = BuildingModelScript.new()
	if not building_b.load_template_data(
		Serializer.to_runtime_template(_authorized_for([Auth.FAMILY_DOOR_LEAKAGE]))
	):
		_check(false, "19b the scenario did not load")
		building_b.free()
		return
	var engine_b: SimulationEngine = _engine_for(building_b, "Ownership2")
	_check(bool(engine_b.closed_door_leakage_enabled), "19b D1 did not come on")
	# Otro propietario lo apaga a mano y ademas enciende D2 por su cuenta.
	engine_b.closed_door_leakage_enabled = false
	engine_b.closed_door_deformation_enabled = true
	building_b.experimental_physics_authorization = {}
	engine_b.reset_simulation(0, false)
	_check(not bool(engine_b.closed_door_leakage_enabled),
			"19b the authorization re-wrote a switch another owner had turned off")
	_check(bool(engine_b.closed_door_deformation_enabled),
			"19b revoking erased D2, which the authorization never set")
	_free_engine(engine_b, building_b)

	# b2) el caso que distingue de verdad las dos reglas: la autorizacion
	# encuentra la red YA encendida -asi que su `previous` es `true`- y despues
	# otro propietario la apaga a mano. Restituir `previous` a ciegas la
	# resucitaria; comparar contra lo que la autorizacion dejo puesto no.
	var building_d = BuildingModelScript.new()
	if not building_d.load_template_data(
		Serializer.to_runtime_template(_authorized_for([Auth.FAMILY_DOOR_LEAKAGE]))
	):
		_check(false, "19b2 the scenario did not load")
		building_d.free()
		return
	var engine_d: SimulationEngine = SimulationEngineScript.new()
	engine_d.name = "ExperimentalActivationOwnership3"
	engine_d.building = building_d
	engine_d.auto_ignite_on_ready = false
	engine_d.auto_finish_on_extinction = false
	engine_d.enable_logging = false
	engine_d.enable_csv_log = false
	engine_d.pressure_network_solver_enabled = true
	root.add_child(engine_d)
	engine_d.reset_simulation(0, false)
	_check(bool(engine_d.pressure_network_solver_enabled), "19b2 the network was dropped")
	# Otro propietario la apaga DESPUES de que la autorizacion la reclamara.
	engine_d.pressure_network_solver_enabled = false
	building_d.experimental_physics_authorization = {}
	engine_d.reset_simulation(0, false)
	_check(not bool(engine_d.pressure_network_solver_enabled),
			"19b2 revoking resurrected a network that another owner had turned off")
	_check(not bool(engine_d.closed_door_leakage_enabled), "19b2 D1 survived the revocation")
	root.remove_child(engine_d)
	engine_d.free()
	building_d.free()

	# c) sin bloque desde el principio, no se toca ni un interruptor.
	var building_c = BuildingModelScript.new()
	if not building_c.load_template_data(
		Serializer.to_runtime_template(_configured_scenario())
	):
		_check(false, "19c the plain scenario did not load")
		building_c.free()
		return
	var engine_c: SimulationEngine = SimulationEngineScript.new()
	engine_c.name = "ExperimentalActivationUntouched"
	engine_c.building = building_c
	engine_c.auto_ignite_on_ready = false
	engine_c.auto_finish_on_extinction = false
	engine_c.enable_logging = false
	engine_c.enable_csv_log = false
	engine_c.glazing_fallout_enabled = true
	engine_c.pressure_network_solver_enabled = true
	root.add_child(engine_c)
	for _repeat in range(3):
		engine_c.reset_simulation(0, false)
	_check(bool(engine_c.glazing_fallout_enabled),
			"19c a scenario without a block erased an unrelated configuration")
	_check(bool(engine_c.pressure_network_solver_enabled),
			"19c a scenario without a block erased the network")
	_check(engine_c.get_experimental_activation_report().is_empty(),
			"19c a scenario without a block produced an activation report")
	root.remove_child(engine_c)
	engine_c.free()
	building_c.free()


# ------------------------------------------------------------
# utilidades
# ------------------------------------------------------------

## Elementos que la red emite con los interruptores QUE TIENE EL MOTOR ahora
## mismo. Mide la consecuencia, no el booleano.
func _engine_elements(engine, building) -> Dictionary:
	var out: Dictionary = {"cracks": 0, "glazing": 0, "envelopes": 0}
	var transport = TransportScript.new()
	transport.closed_door_leakage_enabled = engine.closed_door_leakage_enabled
	transport.closed_door_deformation_enabled = engine.closed_door_deformation_enabled
	transport.glazing_fallout_enabled = engine.glazing_fallout_enabled
	transport.exterior_envelope_leakage_enabled = engine.exterior_envelope_leakage_enabled
	var snapshot: Dictionary = transport.build_snapshot(building, {}, 0.25, 240.0)
	if not bool(snapshot["valid"]):
		_check(false, "the engine-element snapshot is invalid")
		return out
	for raw_element in Array(snapshot["openings"]):
		var element: Dictionary = raw_element
		if String(element.get("flow_model", "")) == "ela_crack":
			out["cracks"] = int(out["cracks"]) + 1
		match String(element.get("provenance", "")):
			"prescribed_glazing_fallout":
				out["glazing"] = int(out["glazing"]) + 1
			"exterior_envelope_leakage":
				out["envelopes"] = int(out["envelopes"]) + 1
	return out


## El escenario de siempre, autorizado para las familias que se pidan.
func _authorized_for(families: Array) -> Dictionary:
	var scenario: Dictionary = Serializer.normalize_editor_data(_configured_scenario())
	var granted: Dictionary = Auth.grant(
		scenario, families, Auth.REQUIRED_ACKNOWLEDGEMENTS, true
	)
	if not bool(granted["ok"]):
		_check(false, "could not authorize %s: %s" % [str(families), str(granted["errors"])])
		return scenario
	scenario[Auth.AUTHORIZATION_KEY] = granted["authorization"]
	return scenario

## Un bloque de autorizacion fabricado a mano, saltandose `grant()`. Sirve para
## comprobar que quien exige el contrato no es solo quien concede.
func _forged(
	scenario: Dictionary, families: Array, acknowledged: Array, experimental: bool
) -> Dictionary:
	var forged: Dictionary = scenario.duplicate(true)
	forged[Auth.AUTHORIZATION_KEY] = {
		Auth.VERSION_FIELD: Auth.AUTHORIZATION_VERSION,
		Auth.FAMILIES_FIELD: families,
		Auth.ACKNOWLEDGED_FIELD: acknowledged,
		Auth.EXPERIMENTAL_FIELD: experimental,
		Auth.DIGEST_FIELD: Auth.digest(scenario, families),
	}
	return forged

## Los cinco interruptores tal cual quedan tras arrancar el motor con este
## escenario, mas el diagnostico de la autorizacion.
func _engine_switches(scenario: Dictionary) -> Dictionary:
	var out: Dictionary = {"failure": "load_failed"}
	for flag in SWITCHES:
		out[flag] = false
	var building = BuildingModelScript.new()
	if not building.load_template_data(Serializer.to_runtime_template(scenario)):
		building.free()
		return out
	var engine: SimulationEngine = _engine_for(building, "Probe%d" % _checks)
	for flag in SWITCHES:
		out[flag] = bool(engine.get(flag))
	out["failure"] = String(engine.experimental_authorization_failure)
	_free_engine(engine, building)
	return out


## Un motor montado como lo monta el resto de validadores de la red.
##
## El `BuildingModel` se queda FUERA del arbol a proposito: su `_ready` vuelve a
## leer `user://last_editor_runtime_template.json` y pisaria la plantilla que
## acabamos de cargar. `reset_simulation` hace el montaje que necesitamos, y es
## tambien donde el motor resuelve la autorizacion.
func _engine_for(building, label: String) -> SimulationEngine:
	var engine: SimulationEngine = SimulationEngineScript.new()
	engine.name = "ExperimentalActivation%s" % label
	engine.building = building
	engine.auto_ignite_on_ready = false
	engine.auto_finish_on_extinction = false
	engine.enable_logging = false
	engine.enable_csv_log = false
	root.add_child(engine)
	engine.reset_simulation(0, false)
	return engine


func _free_engine(engine: SimulationEngine, building) -> void:
	root.remove_child(engine)
	engine.free()
	building.free()


func _technical_summary(scenario: Dictionary) -> Dictionary:
	var building = BuildingModelScript.new()
	if not building.load_template_data(Serializer.to_runtime_template(scenario)):
		building.free()
		return {}
	var engine: SimulationEngine = _engine_for(building, "Summary%d" % _checks)
	var summary: Dictionary = engine.build_technical_summary()
	_free_engine(engine, building)
	return summary


## Elementos de la red con TODO apagado.
func _off_elements(scenario: Dictionary) -> Dictionary:
	return _count_elements(scenario, false, 180.0)


## Elementos de la red con las cuatro familias encendidas, a un instante dado.
func _on_elements(scenario: Dictionary, time_s: float) -> Dictionary:
	return _count_elements(scenario, true, time_s)


func _count_elements(scenario: Dictionary, enabled: bool, time_s: float) -> Dictionary:
	var out: Dictionary = {"cracks": 0, "glazing": 0, "envelopes": 0}
	var building = BuildingModelScript.new()
	if not building.load_template_data(Serializer.to_runtime_template(scenario)):
		_check(false, "the scenario did not load for the element count")
		building.free()
		return out
	var transport = TransportScript.new()
	transport.closed_door_leakage_enabled = enabled
	transport.closed_door_deformation_enabled = enabled
	transport.glazing_fallout_enabled = enabled
	transport.exterior_envelope_leakage_enabled = enabled
	var snapshot: Dictionary = transport.build_snapshot(building, {}, 0.25, time_s)
	_check(bool(snapshot["valid"]), "the element-count snapshot is invalid")
	for raw_element in Array(snapshot["openings"]):
		var element: Dictionary = raw_element
		if String(element.get("flow_model", "")) == "ela_crack":
			out["cracks"] = int(out["cracks"]) + 1
		match String(element.get("provenance", "")):
			"prescribed_glazing_fallout":
				out["glazing"] = int(out["glazing"]) + 1
			"exterior_envelope_leakage":
				out["envelopes"] = int(out["envelopes"]) + 1
	building.free()
	return out


# ------------------------------------------------------------
# fixtures
# ------------------------------------------------------------

func _interior_door() -> Dictionary:
	return {
		"id": "puerta", "a": 0, "b": 1, "type": "door", "wall": "right",
		"width_m": 0.9, "height_m": 2.05, "sill_m": 0.0, "open_fraction": 0.0,
	}


func _exterior_window() -> Dictionary:
	return {
		"id": "ventana", "a": 1, "b": -1, "type": "window", "wall": "bottom",
		"width_m": 1.2, "height_m": 1.0, "sill_m": 0.9, "open_fraction": 0.0,
	}


## Puerta interior con perfil de fuga `research_only` y deformacion prescrita.
func _door_with_leakage_profile() -> Dictionary:
	var door: Dictionary = _interior_door()
	door[Schema.SCHEMA_KEY] = 2
	door[Schema.LEAKAGE_PROFILE_KEY] = Schema.build_profile_block(RESEARCH_LEAKAGE, 1)
	return door


func _deformed_door() -> Dictionary:
	var door: Dictionary = _door_with_leakage_profile()
	door[Schema.SCHEMA_KEY] = 3
	door[Schema.DEFORMATION_PROFILE_KEY] = Schema.build_profile_block(RESEARCH_DEFORMATION, 1)
	door[Schema.DEFORMATION_KEY] = [{
		"id": "top", "location": "top", "z_m": 1.95,
		"points": [[0.0, 0.0], [60.0, 0.0005], [120.0, 0.003]],
	}]
	return door


func _glazed_window() -> Dictionary:
	var window: Dictionary = _exterior_window()
	window[Schema.SCHEMA_KEY] = 1
	window[Schema.PANELS_KEY] = [{
		"id": "pane_a", "host_x_m": 0.2, "width_m": 0.6, "height_m": 0.5,
		"sill_z_m": 0.2, "glass_type": "annealed", "thickness_m": 0.004,
		"leaf_count": 2, "leaf_spacing_m": 0.012, "frame_material": "wood",
		"edge_protection_depth_m": 0.01,
		"leaves": [
			{
				"id": "leaf_0", "index": 0,
				"events": [
					{"time_s": 0.0, "state": "INTACT", "fallout_fraction": 0.0},
					{"time_s": 120.0, "state": "CRACKED", "fallout_fraction": 0.0},
					{"time_s": 180.0, "state": "PARTIAL_FALLOUT", "fallout_fraction": 0.25},
				],
			},
			{
				"id": "leaf_1", "index": 1,
				"events": [
					{"time_s": 0.0, "state": "INTACT", "fallout_fraction": 0.0},
					{"time_s": 150.0, "state": "CRACKED", "fallout_fraction": 0.0},
					{"time_s": 180.0, "state": "PARTIAL_FALLOUT", "fallout_fraction": 0.5},
				],
			},
		],
	}]
	# D3 exige las instantaneas espaciales: sin ellas los paños no se pueden
	# convertir en geometria libre, y el modelo puro lo rechaza. Es la misma
	# prescripcion que usa el validador de D4B2A.
	window[Schema.SPATIAL_KEY] = [{
		"panel_id": "pane_a",
		"snapshots": [
			{"time_s": 0.0, "leaves": [
				{"id": "leaf_0", "index": 0, "regions": []},
				{"id": "leaf_1", "index": 1, "regions": []},
			]},
			{"time_s": 120.0, "leaves": [
				{"id": "leaf_0", "index": 0, "regions": []},
				{"id": "leaf_1", "index": 1, "regions": []},
			]},
			{"time_s": 150.0, "leaves": [
				{"id": "leaf_0", "index": 0, "regions": []},
				{"id": "leaf_1", "index": 1, "regions": []},
			]},
			{"time_s": 180.0, "leaves": [
				{"id": "leaf_0", "index": 0, "regions": [
					{"id": "r0", "x_m": 0.0, "z_m": 0.25, "width_m": 0.3, "height_m": 0.25},
				]},
				{"id": "leaf_1", "index": 1, "regions": [
					{"id": "r0", "x_m": 0.0, "z_m": 0.0, "width_m": 0.3, "height_m": 0.5},
				]},
			]},
		],
	}]
	return window


## La ventana con su perfil de marco y su perfil de vidrio, ya configurados.
func _configured_window() -> Dictionary:
	var window: Dictionary = _glazed_window()
	window[Schema.SCHEMA_KEY] = 3
	window[Schema.FRAME_PROFILE_KEY] = Schema.build_profile_block(FRAME_PROFILE, 1)
	window[Schema.GLAZING_PROFILE_KEY] = Schema.build_profile_block(DERIVED_GLAZING, 1)
	return window


## Escenario con las CUATRO familias configuradas y ninguna autorizada.
func _configured_scenario() -> Dictionary:
	return _scenario([_interior_door(), _deformed_door(), _configured_window()])


## El mismo, ya autorizado para las cuatro.
func _authorized_scenario() -> Dictionary:
	var scenario: Dictionary = Serializer.normalize_editor_data(_configured_scenario())
	var granted: Dictionary = Auth.grant(
		scenario, Auth.available_families(scenario), Auth.REQUIRED_ACKNOWLEDGEMENTS, true
	)
	if bool(granted["ok"]):
		scenario[Auth.AUTHORIZATION_KEY] = granted["authorization"]
	return scenario


func _scenario(openings: Array) -> Dictionary:
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
				"id": 0, "name": "Salon", "kind": "salon", "height_m": 2.5,
				"floor_level_z_m": 0.0, "fuel_energy_MJ": 300.0, "max_hrr_kw": 400.0,
				"fuel_objects": [{
					"id": "sofa", "name": "Sofa", "kind": "sofa", "room_id": 0,
					"position_m": {"x": 1.5, "y": 1.5}, "size_m": {"x": 1.7, "y": 0.85},
					"footprint_m2": 1.45, "fuel_energy_MJ": 300.0, "max_hrr_kw": 400.0,
					"is_primary_ignition_source": true,
				}],
			},
			{
				"id": 1, "name": "Dormitorio", "kind": "dormitorio", "height_m": 2.5,
				"floor_level_z_m": 0.0, "fuel_energy_MJ": 0.0, "max_hrr_kw": 0.0,
				"fuel_objects": [],
			},
		],
		"openings_data": openings,
		"detectors": [], "victims": [], "player_start": {}, "exterior_walls": [],
	}

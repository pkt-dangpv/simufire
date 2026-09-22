extends SceneTree

## F2.2D4B2A: configuracion de perfiles de aberturas desde el editor.
##
##   <godot> --headless --path . --script \
##       res://tools/validate_opening_profile_editor.gd
##
## Grupos:
##   01 sin perfil es la opcion por defecto y no añade nada;
##   02 un escenario antiguo no cambia al abrirlo ni al volver a guardarlo;
##   03 elegir un perfil NO enciende ningun interruptor;
##   04 `product_activation` se enseña y se respeta;
##   05 bloqueado visible pero no seleccionable;
##   06 incompatible no seleccionable, y cambiar el tipo lo trata explicito;
##   07 `research_only` exige confirmar el modo experimental;
##   08 referencia y copia congelada sobreviven a la ida y vuelta;
##   09 migraciones 1 -> 3 y 2 -> 3, deterministas;
##   10 la prescripcion conserva tiempos, posicion, capas y geometria;
##   11 los rechazos de D2 y D3 siguen llegando al editor;
##   12 abrir y cerrar no borra el perfil;
##   13 nada de color solo: cada estado lleva su texto;
##   14 los fixtures del paso 9, uno a uno;
##   15 añadir y quitar prescripcion desde los mandos del editor.

const BuildingModelScript := preload("res://sim/BuildingModel.gd")
const Serializer := preload("res://editor/ScenarioSerializer.gd")
const Schema := preload("res://sim/building/PrescribedOpeningPhysicsSchema.gd")
const Catalog := preload("res://sim/building/OpeningPhysicsProfileCatalog.gd")
const Selection := preload("res://sim/building/OpeningProfileSelection.gd")
const PhysicsEditor := preload("res://editor/OpeningPhysicsEditor.gd")
const SimulationEngineScript := preload("res://sim/core/SimulationEngine.gd")
const TransportScript := preload("res://sim/core/PressureNetworkTransportSystem.gd")

const WORK_DIR: String = "user://opening_profile_editor"

const DERIVED_GLAZING: String = "glazing.multilayer.free_path_rule"
const RESEARCH_DEFORMATION: String = "deformation.steel_fire_door.furnace_topology"
const RESEARCH_LEAKAGE: String = "door.interior.not_weatherstripped.ashrae2001"
const BLOCKED_GLAZING: String = "glazing.toughened.contradictory"
const FRAME_PROFILE: String = "frame.exterior.window.legacy_engine_value"

var _failures: Array[String] = []
var _checks: int = 0


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(WORK_DIR))
	_test_01_no_profile_is_the_default()
	_test_02_legacy_scenario_is_untouched()
	_test_03_selecting_a_profile_activates_nothing()
	_test_04_product_activation_is_shown_and_respected()
	_test_05_blocked_is_visible_but_not_selectable()
	_test_06_incompatible_and_type_change()
	_test_07_research_only_needs_confirmation()
	_test_08_reference_and_frozen_copy_round_trip()
	_test_09_migrations()
	_test_10_prescription_is_preserved()
	_test_11_pure_model_rejections_reach_the_editor()
	_test_12_operational_state_keeps_the_profile()
	_test_13_state_is_text_not_only_colour()
	_test_14_step9_fixtures()
	_test_15_adding_and_removing_prescription()
	if _failures.is_empty():
		print("  %d checks" % _checks)
		print("OPENING PROFILE EDITOR VALIDATION PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
		print("FAIL: " + failure)
	print("OPENING PROFILE EDITOR VALIDATION FAIL (%d)" % _failures.size())
	quit(1)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


# ------------------------------------------------------------
# 01 sin perfil
# ------------------------------------------------------------

func _test_01_no_profile_is_the_default() -> void:
	var door: Dictionary = _interior_door()
	var view: Dictionary = PhysicsEditor.inspect(door, false)
	_check(not bool(view["configured"]), "01 a bare door already declares physics")
	_check(int(view["schema_version"]) == 1, "01 a bare door does not sit on schema 1")
	var slots: Array = view["slots"]
	_check(slots.size() >= 3, "01 an interior door offers fewer slots than expected")
	for raw_slot in slots:
		var slot: Dictionary = raw_slot
		var rows: Array = slot["rows"]
		_check(rows.size() > 1, "01 slot '%s' offers no profile" % String(slot["slot"]))
		var first: Dictionary = rows[0]
		_check(String(first["versioned_id"]) == Selection.NO_PROFILE_ID,
				"01 the first row is not 'sin perfil'")
		_check(bool(first["selectable"]), "01 'sin perfil' is not selectable")
		_check(String(slot["selected_id"]) == Selection.NO_PROFILE_ID,
				"01 a bare door already has a profile selected")
	_check(Schema.validate(door, 0).is_empty(), "01 a bare door fails validation")


# ------------------------------------------------------------
# 02 escenario antiguo
# ------------------------------------------------------------

func _test_02_legacy_scenario_is_untouched() -> void:
	var legacy: Dictionary = _scenario([_interior_door()])
	var first: String = WORK_DIR + "/legacy_1.json"
	var second: String = WORK_DIR + "/legacy_2.json"
	_check(Serializer.save_scenario(first, legacy), "02 the legacy save failed")
	_check(Serializer.save_scenario(second, Serializer.load_scenario(first)),
			"02 the legacy re-save failed")
	_check(FileAccess.get_file_as_bytes(first) == FileAccess.get_file_as_bytes(second),
			"02 a legacy scenario is not byte-stable")
	var text: String = FileAccess.get_file_as_string(first)
	for key in Schema.PROFILE_KEYS:
		_check(not text.contains(key), "02 a legacy scenario gained '%s'" % key)
	_check(not text.contains(Schema.SCHEMA_KEY), "02 a legacy scenario gained the schema key")


# ------------------------------------------------------------
# 03 configurar no activa
# ------------------------------------------------------------

func _test_03_selecting_a_profile_activates_nothing() -> void:
	var door: Dictionary = _interior_door()
	var applied: Dictionary = PhysicsEditor.set_profile(
		door, Schema.LEAKAGE_PROFILE_KEY, RESEARCH_LEAKAGE, 1, true
	)
	_check(bool(applied["ok"]), "03 a research profile could not be configured: %s"
			% str(applied["errors"]))
	if not bool(applied["ok"]):
		return
	var configured: Dictionary = applied["opening"]
	# El estado operativo no se toca.
	_check(float(configured["open_fraction"]) == float(door["open_fraction"]),
			"03 configuring a profile moved open_fraction")
	_check(not configured.has("glass_broken"), "03 configuring a profile broke glass")
	# Y el motor sigue naciendo apagado con ese escenario cargado.
	var building = BuildingModelScript.new()
	var template: Dictionary = Serializer.to_runtime_template(_scenario([configured]))
	_check(building.load_template_data(template), "03 the configured scenario did not load")
	var engine = SimulationEngineScript.new()
	engine.name = "OpeningProfileEditorSwitches"
	engine.building = building
	root.add_child(building)
	root.add_child(engine)
	for flag in [
		"pressure_network_solver_enabled", "closed_door_leakage_enabled",
		"closed_door_deformation_enabled", "glazing_fallout_enabled",
		"exterior_envelope_leakage_enabled",
	]:
		_check(not bool(engine.get(flag)), "03 '%s' switched itself on" % flag)
	var transport = engine.pressure_network_transport_system
	if transport != null:
		_check(not bool(transport.closed_door_leakage_enabled),
				"03 D1 reached the transport ON")
		_check(not bool(transport.glazing_fallout_enabled), "03 D3 reached the transport ON")
	root.remove_child(engine)
	root.remove_child(building)
	engine.free()
	building.free()
	_check_no_elements_with_switches_off(configured)


## Con los interruptores APAGADOS, una abertura configurada no puede aportar ni
## un elemento a la red. Es la frontera de esta fase escrita como medida: no
## basta con que el interruptor siga en falso, tiene que no haber caudal.
func _check_no_elements_with_switches_off(opening: Dictionary) -> void:
	# La ventana lleva LO SUYO: vidrio prescrito y perfil de marco. Ponerle el
	# perfil de puerta seria justo lo que la regla de compatibilidad prohibe.
	var glazed: Dictionary = _glazed_window()
	var framed: Dictionary = PhysicsEditor.set_profile(
		glazed, Schema.FRAME_PROFILE_KEY, FRAME_PROFILE, 1, true
	)
	if bool(framed["ok"]):
		glazed = framed["opening"]
	else:
		_check(false, "03 the window could not take its frame profile: %s"
				% str(framed["errors"]))
	var building = BuildingModelScript.new()
	var template: Dictionary = Serializer.to_runtime_template(
		_scenario([_configured_door(), glazed])
	)
	if not building.load_template_data(template):
		_check(false, "03 the configured scenario did not load for the OFF snapshot")
		building.free()
		return
	var transport = TransportScript.new()
	transport.closed_door_leakage_enabled = false
	transport.closed_door_deformation_enabled = false
	transport.glazing_fallout_enabled = false
	transport.exterior_envelope_leakage_enabled = false
	var snapshot: Dictionary = transport.build_snapshot(building, {}, 0.25, 180.0)
	_check(bool(snapshot["valid"]), "03 the OFF snapshot is invalid")
	var cracks: int = 0
	var glazing: int = 0
	var envelopes: int = 0
	for raw_element in Array(snapshot["openings"]):
		var element: Dictionary = raw_element
		if String(element.get("flow_model", "")) == "ela_crack":
			cracks += 1
		match String(element.get("provenance", "")):
			"prescribed_glazing_fallout":
				glazing += 1
			"exterior_envelope_leakage":
				envelopes += 1
	_check(cracks == 0, "03 a configured profile produced a crack element with D1/D2 off")
	_check(glazing == 0, "03 a configured profile produced a glazing element with D3 off")
	_check(envelopes == 0, "03 a configured profile produced an envelope element with R3 off")
	building.free()


## Una puerta interior ya configurada, para las comprobaciones que la necesitan.
func _configured_door() -> Dictionary:
	var applied: Dictionary = PhysicsEditor.set_profile(
		_interior_door(), Schema.LEAKAGE_PROFILE_KEY, RESEARCH_LEAKAGE, 1, true
	)
	return applied["opening"] if bool(applied["ok"]) else _interior_door()


# ------------------------------------------------------------
# 04 product_activation
# ------------------------------------------------------------

func _test_04_product_activation_is_shown_and_respected() -> void:
	var door: Dictionary = _interior_door()
	var shown: int = 0
	for raw_slot in Array(PhysicsEditor.inspect(door, true)["slots"]):
		for raw_row in Array(Dictionary(raw_slot)["rows"]):
			var row: Dictionary = raw_row
			if String(row["versioned_id"]) == Selection.NO_PROFILE_ID:
				continue
			shown += 1
			_check(not bool(row["product_activation"]),
					"04 '%s' claims product activation" % String(row["versioned_id"]))
			_check(String(row["product_label"]) == Selection.PRODUCT_LABEL_OFF,
					"04 '%s' does not show the product label" % String(row["versioned_id"]))
	_check(shown > 0, "04 no profile was offered at all")
	_check(Catalog.product_ready_ids().is_empty(),
			"04 the catalogue now declares a product-ready profile")


# ------------------------------------------------------------
# 05 bloqueado
# ------------------------------------------------------------

func _test_05_blocked_is_visible_but_not_selectable() -> void:
	var window: Dictionary = _exterior_window()
	var rows: Array[Dictionary] = Selection.rows_for(
		window, Catalog.CATEGORY_GLAZING, true
	)
	var found: bool = false
	for row in rows:
		if String(row["profile_id"]) != BLOCKED_GLAZING:
			continue
		found = true
		_check(not bool(row["selectable"]), "05 the blocked glazing profile is selectable")
		_check(not String(row["disabled_reason"]).is_empty(),
				"05 the blocked profile gives no reason")
		_check(String(row["evidence_label"]).contains("BLOQUEADO"),
				"05 the blocked profile is not labelled as blocked")
	_check(found, "05 the blocked glazing profile is not even shown")
	# Y el controlador lo rechaza aunque alguien lo pida a mano.
	var applied: Dictionary = PhysicsEditor.set_profile(
		window, Schema.GLAZING_PROFILE_KEY, BLOCKED_GLAZING, 1, true
	)
	_check(not bool(applied["ok"]), "05 a blocked profile was configured")
	_check(not Dictionary(applied["opening"]).has(Schema.GLAZING_PROFILE_KEY),
			"05 a blocked profile left data behind")


# ------------------------------------------------------------
# 06 incompatible y cambio de tipo
# ------------------------------------------------------------

func _test_06_incompatible_and_type_change() -> void:
	# La fuga de marco de R3 no encaja en una puerta interior.
	var door: Dictionary = _interior_door()
	_check(not Catalog.category_applies_to(Catalog.CATEGORY_FRAME_LEAKAGE, door),
			"06 frame leakage is considered compatible with an interior door")
	var applied: Dictionary = PhysicsEditor.set_profile(
		door, Schema.FRAME_PROFILE_KEY, FRAME_PROFILE, 1, true
	)
	_check(not bool(applied["ok"]), "06 an incompatible profile was configured")
	# Y la ranura ni siquiera se ofrece.
	for raw_slot in Array(PhysicsEditor.inspect(door, true)["slots"]):
		_check(String(Dictionary(raw_slot)["slot"]) != Schema.FRAME_PROFILE_KEY,
				"06 the frame slot is offered on an interior door")
	# Cambiar el tipo con un perfil puesto: se avisa, no se borra en silencio.
	var configured: Dictionary = PhysicsEditor.set_profile(
		door, Schema.LEAKAGE_PROFILE_KEY, RESEARCH_LEAKAGE, 1, true
	)["opening"]
	var refused: Dictionary = PhysicsEditor.change_type(configured, "window", false)
	_check(not bool(refused["ok"]), "06 changing the type dropped a profile silently")
	_check(bool(refused["needs_confirmation"]), "06 the type change asked for no confirmation")
	_check(Array(refused["conflicting_slots"]).has(Schema.LEAKAGE_PROFILE_KEY),
			"06 the conflicting slot was not named")
	_check(Dictionary(refused["opening"]).has(Schema.LEAKAGE_PROFILE_KEY),
			"06 the refused change already lost the profile")
	var accepted: Dictionary = PhysicsEditor.change_type(configured, "window", true)
	_check(bool(accepted["ok"]), "06 the confirmed type change failed: %s"
			% str(accepted["errors"]))
	if bool(accepted["ok"]):
		_check(not Dictionary(accepted["opening"]).has(Schema.LEAKAGE_PROFILE_KEY),
				"06 the confirmed change kept an incompatible profile")
		_check(String(Dictionary(accepted["opening"])["type"]) == "window",
				"06 the type did not change")


# ------------------------------------------------------------
# 07 modo experimental
# ------------------------------------------------------------

func _test_07_research_only_needs_confirmation() -> void:
	var door: Dictionary = _interior_door()
	var rows: Array[Dictionary] = Selection.rows_for(
		door, Catalog.CATEGORY_DEFORMATION, false
	)
	var found: bool = false
	for row in rows:
		if String(row["profile_id"]) != RESEARCH_DEFORMATION:
			continue
		found = true
		_check(bool(row["requires_experimental"]),
				"07 the research profile does not ask for experimental mode")
		_check(not bool(row["selectable"]),
				"07 a research profile is selectable without confirmation")
		_check(String(row["disabled_reason"]).contains("experimental"),
				"07 the reason does not mention experimental mode")
	_check(found, "07 the research deformation profile is not offered")
	var refused: Dictionary = PhysicsEditor.set_profile(
		door, Schema.DEFORMATION_PROFILE_KEY, RESEARCH_DEFORMATION, 1, false
	)
	_check(not bool(refused["ok"]), "07 a research profile was configured unconfirmed")
	var accepted: Dictionary = PhysicsEditor.set_profile(
		door, Schema.DEFORMATION_PROFILE_KEY, RESEARCH_DEFORMATION, 1, true
	)
	_check(bool(accepted["ok"]), "07 the confirmed research profile failed: %s"
			% str(accepted["errors"]))
	if not bool(accepted["ok"]):
		return
	# Confirmar el modo experimental NO enciende nada.
	var configured: Dictionary = accepted["opening"]
	_check(int(configured[Schema.SCHEMA_KEY]) == 3,
			"07 a deformation profile did not raise the schema to 3")
	var building = BuildingModelScript.new()
	_check(building.load_template_data(
			Serializer.to_runtime_template(_scenario([configured]))),
			"07 the experimental scenario did not load")
	var engine = SimulationEngineScript.new()
	engine.name = "OpeningProfileEditorExperimental"
	engine.building = building
	root.add_child(building)
	root.add_child(engine)
	_check(not bool(engine.closed_door_deformation_enabled),
			"07 confirming experimental mode switched D2 on")
	root.remove_child(engine)
	root.remove_child(building)
	engine.free()
	building.free()


# ------------------------------------------------------------
# 08 ida y vuelta
# ------------------------------------------------------------

func _test_08_reference_and_frozen_copy_round_trip() -> void:
	var window: Dictionary = _glazed_window()
	var applied: Dictionary = PhysicsEditor.set_profile(
		window, Schema.GLAZING_PROFILE_KEY, DERIVED_GLAZING, 1, false
	)
	_check(bool(applied["ok"]), "08 the derived glazing profile failed: %s"
			% str(applied["errors"]))
	if not bool(applied["ok"]):
		return
	var path: String = WORK_DIR + "/profile_round_trip.json"
	var again: String = WORK_DIR + "/profile_round_trip_2.json"
	var scenario: Dictionary = _scenario([applied["opening"]])
	_check(Serializer.save_scenario(path, scenario), "08 the save failed")
	var loaded: Dictionary = Serializer.load_scenario(path)
	_check(Serializer.save_scenario(again, loaded), "08 the second save failed")
	_check(FileAccess.get_file_as_bytes(path) == FileAccess.get_file_as_bytes(again),
			"08 a scenario with a glazing profile is not byte-stable")
	var door: Dictionary = Array(loaded["openings_data"])[0]
	if not door.has(Schema.GLAZING_PROFILE_KEY):
		_check(false, "08 the glazing profile did not survive the file")
		return
	var block: Dictionary = door[Schema.GLAZING_PROFILE_KEY]
	if not block.has(Schema.PROFILE_ID_KEY) or not block.has(Schema.PROFILE_VERSION_KEY) \
			or typeof(block.get(Schema.PROFILE_EFFECTIVE_KEY, null)) != TYPE_DICTIONARY:
		_check(false, "08 the stored profile block lost a required field")
		return
	_check(String(block[Schema.PROFILE_ID_KEY]) == DERIVED_GLAZING,
			"08 the profile id changed")
	_check(typeof(block[Schema.PROFILE_VERSION_KEY]) == TYPE_INT,
			"08 the profile version lost its integer type")
	var frozen: Dictionary = block[Schema.PROFILE_EFFECTIVE_KEY]
	var catalog: Dictionary = Catalog.find(DERIVED_GLAZING, 1)["parameters"]
	_check(frozen.size() == catalog.size(), "08 the frozen copy lost a parameter")
	for key in catalog.keys():
		_check(frozen.has(key) and frozen[key] == catalog[key],
				"08 the frozen parameter '%s' does not match the catalogue" % String(key))
	# La resolucion es por par exacto: una version nueva no movería este escenario.
	_check(Catalog.find(DERIVED_GLAZING, 99).is_empty(),
			"08 an unpublished version resolves")
	# Y el motor recibe la procedencia sin recibir ningun numero nuevo.
	var building = BuildingModelScript.new()
	_check(building.load_template_data(Serializer.to_runtime_template(loaded)),
			"08 the round-tripped scenario did not load")
	var openings: Array = building.get_openings()
	if openings.size() == 1:
		_check(String(openings[0].glazing_profile_ref) == "%s@1" % DERIVED_GLAZING,
				"08 the glazing provenance was lost")
		_check(float(openings[0].leakage_area_override_m2) == -1.0,
				"08 a glazing profile supplied a leakage number")
	building.free()


# ------------------------------------------------------------
# 09 migraciones
# ------------------------------------------------------------

func _test_09_migrations() -> void:
	# 1 -> 3: un escenario de D4A que gana un perfil de vidrio.
	var window: Dictionary = _glazed_window()
	window[Schema.SCHEMA_KEY] = 1
	_check(Schema.required_schema_version(window) == 1,
			"09 prescribed glazing alone already demands schema 3")
	var migrated: Dictionary = PhysicsEditor.set_profile(
		window, Schema.GLAZING_PROFILE_KEY, DERIVED_GLAZING, 1, false
	)
	_check(bool(migrated["ok"]), "09 the 1 -> 3 migration failed: %s" % str(migrated["errors"]))
	if bool(migrated["ok"]):
		_check(int(Dictionary(migrated["opening"]).get(Schema.SCHEMA_KEY, -1)) == 3,
				"09 the 1 -> 3 migration did not raise the marker")
	# 2 -> 3: un escenario de D4B1 con fuga de marco que gana vidrio.
	var frame_window: Dictionary = _glazed_window()
	# El perfil de marco historico es `research_only`, asi que exige el modo
	# experimental confirmado: por eso entra con `true`.
	var with_frame: Dictionary = PhysicsEditor.set_profile(
		frame_window, Schema.FRAME_PROFILE_KEY, FRAME_PROFILE, 1, true
	)
	_check(bool(with_frame["ok"]), "09 the frame profile failed: %s" % str(with_frame["errors"]))
	if not bool(with_frame["ok"]):
		return
	var at_two: Dictionary = with_frame["opening"]
	if not at_two.has(Schema.SCHEMA_KEY):
		_check(false, "09 a configured opening carries no schema marker")
		return
	_check(int(at_two[Schema.SCHEMA_KEY]) == 2, "09 a frame profile alone is not schema 2")
	var at_three: Dictionary = PhysicsEditor.set_profile(
		at_two, Schema.GLAZING_PROFILE_KEY, DERIVED_GLAZING, 1, false
	)
	_check(bool(at_three["ok"]), "09 the 2 -> 3 migration failed: %s" % str(at_three["errors"]))
	if not bool(at_three["ok"]):
		return
	_check(int(Dictionary(at_three["opening"]).get(Schema.SCHEMA_KEY, -1)) == 3,
			"09 the 2 -> 3 migration did not raise the marker")
	# Determinista: normalizar dos veces da exactamente lo mismo.
	var once: Dictionary = Dictionary(at_three["opening"]).duplicate(true)
	var twice: Dictionary = once.duplicate(true)
	Schema.normalize(twice)
	_check(JSON.stringify(once) == JSON.stringify(twice), "09 the migration is not idempotent")
	# Y la marca no BAJA al quitar el perfil de vidrio.
	var without: Dictionary = PhysicsEditor.set_profile(
		at_three["opening"], Schema.GLAZING_PROFILE_KEY, "", 0, false
	)
	_check(bool(without["ok"]), "09 removing the glazing profile failed")
	if bool(without["ok"]):
		_check(int(Dictionary(without["opening"]).get(Schema.SCHEMA_KEY, -1)) == 3,
				"09 the schema marker went backwards")


# ------------------------------------------------------------
# 10 la prescripcion se conserva
# ------------------------------------------------------------

func _test_10_prescription_is_preserved() -> void:
	var door: Dictionary = _interior_door()
	var tracks: Array = _deformation_tracks()
	var applied: Dictionary = PhysicsEditor.set_prescription(
		door, Schema.DEFORMATION_KEY, tracks
	)
	_check(bool(applied["ok"]), "10 the prescribed deformation was rejected: %s"
			% str(applied["errors"]))
	if not bool(applied["ok"]):
		return
	var path: String = WORK_DIR + "/prescription.json"
	_check(Serializer.save_scenario(path, _scenario([applied["opening"]])), "10 the save failed")
	var back: Dictionary = Array(
		Serializer.load_scenario(path)["openings_data"]
	)[0]
	var loaded_tracks: Array = back[Schema.DEFORMATION_KEY]
	_check(loaded_tracks.size() == tracks.size(), "10 a track was lost")
	var first: Dictionary = loaded_tracks[0]
	_check(String(first["id"]) == "top", "10 the track identity changed")
	_check(String(first["location"]) == "top", "10 the track position changed")
	_check(float(first["z_m"]) == 1.95, "10 the track height drifted")
	var points: Array = first["points"]
	_check(points.size() == 3, "10 a track point was lost")
	_check(float(Array(points[1])[0]) == 60.0, "10 the point time drifted")
	_check(float(Array(points[1])[1]) == 0.0005, "10 the additional ELA drifted")
	# Y el arbol del editor la enseña en orden, con su unidad.
	var rows: Array[Dictionary] = PhysicsEditor.describe_prescription(back)
	_check(rows.size() >= 4, "10 the prescription tree is empty")
	_check(String(rows[0]["text"]).contains("Deformación"),
			"10 the tree does not name the deformation family")
	_check(String(rows[1]["detail"]).contains("m²"),
			"10 the tree does not show the ELA unit")
	# El vidrio, igual: paños, capas y geometria espacial.
	var window: Dictionary = _glazed_window()
	var glazing_rows: Array[Dictionary] = PhysicsEditor.describe_prescription(window)
	var families: Dictionary = {}
	for row in glazing_rows:
		families[String(row["family"])] = true
	_check(families.has(PhysicsEditor.PANEL_FAMILY), "10 the tree lost the panels")
	_check(families.has(PhysicsEditor.REGION_FAMILY), "10 the tree lost the spatial regions")
	var cracked_seen: bool = false
	for row in glazing_rows:
		if String(row["text"]).contains("CRACKED"):
			cracked_seen = true
			_check(String(row["detail"]).contains("NO crea"),
					"10 CRACKED is not explained as creating no vent area")
	_check(cracked_seen, "10 no CRACKED event reached the tree")


# ------------------------------------------------------------
# 11 rechazos de los modelos puros
# ------------------------------------------------------------

func _test_11_pure_model_rejections_reach_the_editor() -> void:
	var door: Dictionary = _interior_door()
	# Tiempo duplicado.
	var duplicated: Array = _deformation_tracks()
	Dictionary(duplicated[0])["points"] = [[0.0, 0.0], [60.0, 0.0005], [60.0, 0.001]]
	_check(not bool(PhysicsEditor.set_prescription(
			door, Schema.DEFORMATION_KEY, duplicated)["ok"]),
			"11 a duplicated track time was accepted")
	# Tiempos desordenados.
	var unordered: Array = _deformation_tracks()
	Dictionary(unordered[0])["points"] = [[0.0, 0.0], [120.0, 0.001], [60.0, 0.0005]]
	_check(not bool(PhysicsEditor.set_prescription(
			door, Schema.DEFORMATION_KEY, unordered)["ok"]),
			"11 an out-of-order track was accepted")
	# Area negativa y no finita.
	for bad_area in [-0.001, INF]:
		var bad: Array = _deformation_tracks()
		Dictionary(bad[0])["points"] = [[0.0, 0.0], [60.0, bad_area]]
		_check(not bool(PhysicsEditor.set_prescription(
				door, Schema.DEFORMATION_KEY, bad)["ok"]),
				"11 an invalid additional ELA (%s) was accepted" % str(bad_area))
	# Pano fuera del hueco.
	var window: Dictionary = _glazed_window()
	var outside: Array = Array(window[Schema.PANELS_KEY]).duplicate(true)
	Dictionary(outside[0])["host_x_m"] = 5.0
	_check(not bool(PhysicsEditor.set_prescription(
			window, Schema.PANELS_KEY, outside)["ok"]),
			"11 a panel outside the host opening was accepted")
	# Panos solapados.
	var overlapped: Array = Array(window[Schema.PANELS_KEY]).duplicate(true)
	var clone: Dictionary = Dictionary(overlapped[0]).duplicate(true)
	clone["id"] = "pane_clone"
	overlapped.append(clone)
	var spatial: Array = Array(window[Schema.SPATIAL_KEY]).duplicate(true)
	var spatial_clone: Dictionary = Dictionary(spatial[0]).duplicate(true)
	spatial_clone["panel_id"] = "pane_clone"
	spatial.append(spatial_clone)
	var both: Dictionary = window.duplicate(true)
	both[Schema.PANELS_KEY] = overlapped
	both[Schema.SPATIAL_KEY] = spatial
	_check(not Schema.validate(both, 0).is_empty(), "11 overlapping panels were accepted")


# ------------------------------------------------------------
# 12 estado operativo
# ------------------------------------------------------------

func _test_12_operational_state_keeps_the_profile() -> void:
	var window: Dictionary = _glazed_window()
	var configured: Dictionary = PhysicsEditor.set_profile(
		window, Schema.GLAZING_PROFILE_KEY, DERIVED_GLAZING, 1, false
	)["opening"]
	for fraction in [1.0, 0.0, 0.5, 1.0]:
		configured["open_fraction"] = fraction
		var normalized: Dictionary = Array(
			Serializer.normalize_editor_data(_scenario([configured]))["openings_data"]
		)[0]
		_check(normalized.has(Schema.GLAZING_PROFILE_KEY),
				"12 opening the window at %f erased its profile" % fraction)
		if normalized.has(Schema.GLAZING_PROFILE_KEY):
			_check(String(Dictionary(normalized[Schema.GLAZING_PROFILE_KEY])
					.get(Schema.PROFILE_ID_KEY, "")) == DERIVED_GLAZING,
					"12 the profile identity changed at %f" % fraction)
		_check(normalized.has(Schema.PANELS_KEY),
				"12 opening the window at %f erased its panels" % fraction)
		_check(float(normalized["open_fraction"]) == fraction,
				"12 the operational state was not preserved at %f" % fraction)


# ------------------------------------------------------------
# 13 texto, no solo color
# ------------------------------------------------------------

func _test_13_state_is_text_not_only_colour() -> void:
	var window: Dictionary = _exterior_window()
	var seen: Dictionary = {}
	for row in Selection.rows_for(window, Catalog.CATEGORY_GLAZING, true):
		if String(row["versioned_id"]) == Selection.NO_PROFILE_ID:
			continue
		seen[String(row["evidence"])] = true
		_check(not String(row["evidence_label"]).strip_edges().is_empty(),
				"13 a row carries no evidence text")
		_check(not String(row["evidence_note"]).strip_edges().is_empty(),
				"13 a row carries no evidence note")
		_check(not String(row["domain_text"]).strip_edges().is_empty(),
				"13 a row carries no domain text")
		_check(not String(row["source_text"]).strip_edges().is_empty(),
				"13 a row carries no source text")
		# Las advertencias son el aviso que el catalogo da sobre ese perfil.
		# Perderlas por el camino dejaria al usuario eligiendo a ciegas.
		var catalog_warnings: Array = Array(Catalog.find(
			String(row["profile_id"]), int(row["version"])
		).get("warnings", []))
		_check(Array(row["warnings"]).size() == catalog_warnings.size(),
				"13 '%s' shows %d warning(s) and the catalogue publishes %d"
				% [String(row["versioned_id"]), Array(row["warnings"]).size(),
					catalog_warnings.size()])
		if not bool(row["selectable"]):
			_check(not String(row["disabled_reason"]).strip_edges().is_empty(),
					"13 a disabled row gives no reason in text")
	_check(seen.has(Catalog.EVIDENCE_VALIDATED) and seen.has(Catalog.EVIDENCE_BLOCKED),
			"13 the glazing category no longer shows both validated and blocked")
	# Cada estado dice SU palabra, no la de otro: una clasificacion cientifica
	# mal presentada es peor que no presentarla.
	var expected_word: Dictionary = {
		Catalog.EVIDENCE_VALIDATED: "MEDIDO",
		Catalog.EVIDENCE_DERIVED: "DERIVADO",
		Catalog.EVIDENCE_RESEARCH_ONLY: "EXPERIMENTAL",
		Catalog.EVIDENCE_BLOCKED: "BLOQUEADO",
	}
	for opening in [_interior_door(), _exterior_window()]:
		for category in Selection.categories_for(opening):
			for row in Selection.rows_for(opening, category, true):
				var evidence: String = String(row["evidence"])
				if not expected_word.has(evidence):
					continue
				_check(String(row["evidence_label"]).begins_with(
						String(expected_word[evidence])),
						"13 '%s' is presented as '%s'" % [
							String(row["versioned_id"]), String(row["evidence_label"])
						])
	# Vocabulario prohibido. Se mira lo que el usuario LEE -las etiquetas, notas,
	# dominios, fuentes y avisos de cada fila- y no el codigo, cuya
	# documentacion nombra por fuerza las palabras que prohibe.
	var read_by_the_user: PackedStringArray = []
	for opening in [_interior_door(), _exterior_window()]:
		for category in Selection.categories_for(opening):
			for row in Selection.rows_for(opening, category, true):
				read_by_the_user.append(String(row["title"]))
				read_by_the_user.append(String(row["evidence_label"]))
				read_by_the_user.append(String(row["evidence_note"]))
				read_by_the_user.append(String(row["product_label"]))
				read_by_the_user.append(String(row["disabled_reason"]))
	read_by_the_user.append(Selection.CONFIGURED_NOT_ACTIVE_TEXT)
	_check(read_by_the_user.size() > 20, "13 almost nothing was collected to scan")
	for piece in read_by_the_user:
		var lowered: String = piece.to_lower()
		for forbidden in ["calibrado", "calibrada", "realista", "estándar residencial", "seguro"]:
			_check(not lowered.contains(forbidden),
					"13 the editor reads '%s' to the user: %s" % [forbidden, piece])


# ------------------------------------------------------------
# 14 fixtures del paso 9
# ------------------------------------------------------------

func _test_14_step9_fixtures() -> void:
	var fixtures: Array[Dictionary] = [
		{"name": "puerta interior sin perfil", "opening": _interior_door(), "configured": false},
		{
			"name": "puerta con perfil derivado",
			"opening": PhysicsEditor.set_profile(
				_glazed_window(), Schema.GLAZING_PROFILE_KEY, DERIVED_GLAZING, 1, false
			)["opening"],
			"configured": true,
		},
		{
			"name": "puerta con perfil experimental",
			"opening": PhysicsEditor.set_profile(
				_interior_door(), Schema.LEAKAGE_PROFILE_KEY, RESEARCH_LEAKAGE, 1, true
			)["opening"],
			"configured": true,
		},
		{"name": "ventana con vidrio prescrito", "opening": _glazed_window(), "configured": true},
	]
	for fixture in fixtures:
		var opening: Dictionary = fixture["opening"]
		_check(not opening.is_empty(), "14 fixture '%s' is empty" % String(fixture["name"]))
		if opening.is_empty():
			continue
		_check(Schema.validate(opening, 0).is_empty(),
				"14 fixture '%s' does not validate: %s" % [
					String(fixture["name"]), str(Schema.validate(opening, 0))
				])
		var view: Dictionary = PhysicsEditor.inspect(opening, true)
		_check(bool(view["configured"]) == bool(fixture["configured"]),
				"14 fixture '%s' reports the wrong configuration state" % String(fixture["name"]))
		if bool(fixture["configured"]):
			_check(String(view["status_text"]) == Selection.CONFIGURED_NOT_ACTIVE_TEXT,
					"14 fixture '%s' does not show the not-activated notice"
					% String(fixture["name"]))
		# Y todo fixture sobrevive al viaje por el fichero.
		var path: String = WORK_DIR + "/fixture.json"
		_check(Serializer.save_scenario(path, _scenario([opening])),
				"14 fixture '%s' could not be saved" % String(fixture["name"]))
		var back: Dictionary = Array(
			Serializer.load_scenario(path)["openings_data"]
		)[0]
		_check(Schema.validate(back, 0).is_empty(),
				"14 fixture '%s' failed validation after the round trip"
				% String(fixture["name"]))
	# Perfil incompatible: el hueco no admite ninguna categoria.
	var hole: Dictionary = _interior_door()
	hole["type"] = "hole"
	_check(Selection.categories_for(hole).is_empty(),
			"14 a hole is offered opening physics categories")


# ------------------------------------------------------------
# 15 añadir y quitar prescripcion
# ------------------------------------------------------------

func _test_15_adding_and_removing_prescription() -> void:
	# Un instante de deformacion, desde los mandos.
	var door: Dictionary = _interior_door()
	var first: Dictionary = PhysicsEditor.add_entry(door, {
		"entry_kind_index": PhysicsEditor.ENTRY_DEFORMATION_POINT,
		"id": "top", "location_index": 1, "z_m": 1.95,
		"time_s": 0.0, "additional_ela_m2": 0.0,
	})
	_check(bool(first["ok"]), "15 the first deformation point was rejected: %s"
			% str(first["errors"]))
	if not bool(first["ok"]):
		return
	var second: Dictionary = PhysicsEditor.add_entry(first["opening"], {
		"entry_kind_index": PhysicsEditor.ENTRY_DEFORMATION_POINT,
		"id": "top", "location_index": 1, "z_m": 1.95,
		"time_s": 60.0, "additional_ela_m2": 0.0005,
	})
	_check(bool(second["ok"]), "15 the second deformation point was rejected: %s"
			% str(second["errors"]))
	if not bool(second["ok"]):
		return
	var with_two: Dictionary = second["opening"]
	var tracks: Array = with_two[Schema.DEFORMATION_KEY]
	_check(tracks.size() == 1, "15 a second track was created instead of a second point")
	_check(Array(Dictionary(tracks[0])["points"]).size() == 2, "15 the point was not added")
	# Un instante REPETIDO lo rechaza el modelo puro, no el editor.
	var duplicated: Dictionary = PhysicsEditor.add_entry(with_two, {
		"entry_kind_index": PhysicsEditor.ENTRY_DEFORMATION_POINT,
		"id": "top", "location_index": 1, "z_m": 1.95,
		"time_s": 60.0, "additional_ela_m2": 0.002,
	})
	_check(not bool(duplicated["ok"]), "15 a duplicated instant was accepted")
	# Y un instante ANTERIOR se coloca en su sitio, no al final.
	var earlier: Dictionary = PhysicsEditor.add_entry(with_two, {
		"entry_kind_index": PhysicsEditor.ENTRY_DEFORMATION_POINT,
		"id": "top", "location_index": 1, "z_m": 1.95,
		"time_s": 30.0, "additional_ela_m2": 0.0002,
	})
	_check(bool(earlier["ok"]), "15 an earlier instant was rejected: %s" % str(earlier["errors"]))
	if bool(earlier["ok"]):
		var ordered: Array = Array(Dictionary(
			Array(Dictionary(earlier["opening"])[Schema.DEFORMATION_KEY])[0]
		)["points"])
		_check(float(Array(ordered[1])[0]) == 30.0,
				"15 the earlier instant was appended instead of inserted")
	# Un area negativa tecleada en el mando se RECHAZA; no se recorta a cero.
	for bad_area in [-0.001, -1.0]:
		var clamped: Dictionary = PhysicsEditor.add_entry(with_two, {
			"entry_kind_index": PhysicsEditor.ENTRY_DEFORMATION_POINT,
			"id": "top", "location_index": 1, "z_m": 1.95,
			"time_s": 240.0, "additional_ela_m2": bad_area,
		})
		_check(not bool(clamped["ok"]),
				"15 a negative additional ELA (%s) was accepted or clamped" % str(bad_area))
	# Un paño nuevo sale valido a la primera, con su entrada espacial.
	var window: Dictionary = _exterior_window()
	var panel: Dictionary = PhysicsEditor.add_entry(window, {
		"entry_kind_index": PhysicsEditor.ENTRY_GLAZING_PANEL,
		"id": "pane_new", "glass_index": 0, "leaf_count": 2,
		"x_m": 0.2, "z_m": 0.2, "width_m": 0.6, "height_m": 0.5,
	})
	_check(bool(panel["ok"]), "15 a new panel was rejected: %s" % str(panel["errors"]))
	if not bool(panel["ok"]):
		return
	var with_panel: Dictionary = panel["opening"]
	_check(Array(with_panel[Schema.PANELS_KEY]).size() == 1, "15 the panel was not added")
	_check(Array(with_panel[Schema.SPATIAL_KEY]).size() == 1,
			"15 the panel came without its spatial entry")
	# Un paño FUERA del hueco lo rechaza D3.
	var outside: Dictionary = PhysicsEditor.add_entry(window, {
		"entry_kind_index": PhysicsEditor.ENTRY_GLAZING_PANEL,
		"id": "pane_far", "glass_index": 0, "leaf_count": 1,
		"x_m": 5.0, "z_m": 0.2, "width_m": 0.6, "height_m": 0.5,
	})
	_check(not bool(outside["ok"]), "15 a panel outside the host opening was accepted")
	# Dos paños SOLAPADOS, tambien.
	var overlapped: Dictionary = PhysicsEditor.add_entry(with_panel, {
		"entry_kind_index": PhysicsEditor.ENTRY_GLAZING_PANEL,
		"id": "pane_over", "glass_index": 0, "leaf_count": 1,
		"x_m": 0.3, "z_m": 0.2, "width_m": 0.6, "height_m": 0.5,
	})
	_check(not bool(overlapped["ok"]), "15 two overlapping panels were accepted")
	# Un estado de hoja sobre una hoja que no existe se rechaza con su motivo.
	var missing_leaf: Dictionary = PhysicsEditor.add_entry(with_panel, {
		"entry_kind_index": PhysicsEditor.ENTRY_LEAF_EVENT,
		"id": "pane_new", "child_id": "no_existe",
		"time_s": 120.0, "state_index": 1, "fallout_percent": 0.0,
	})
	_check(not bool(missing_leaf["ok"]), "15 an event on a missing leaf was accepted")
	# Y uno valido entra, con su fraccion convertida desde el porcentaje.
	var cracked: Dictionary = PhysicsEditor.add_entry(with_panel, {
		"entry_kind_index": PhysicsEditor.ENTRY_LEAF_EVENT,
		"id": "pane_new", "child_id": "pane_new_leaf_0",
		"time_s": 120.0, "state_index": 1, "fallout_percent": 0.0,
	})
	_check(bool(cracked["ok"]), "15 a CRACKED event was rejected: %s" % str(cracked["errors"]))
	if bool(cracked["ok"]):
		var events: Array = Array(Dictionary(Array(Dictionary(
			cracked["opening"])[Schema.PANELS_KEY])[0])["leaves"])
		var leaf: Dictionary = events[0]
		var leaf_events: Array = leaf["events"]
		_check(leaf_events.size() == 2, "15 the event was not added")
		_check(String(Dictionary(leaf_events[1])["state"]) == "CRACKED",
				"15 the event state is wrong")
		_check(float(Dictionary(leaf_events[1])["fallout_fraction"]) == 0.0,
				"15 CRACKED did not keep a zero fallout fraction")
	# Un salto de estado prohibido por el contrato de D3 se rechaza.
	var illegal: Dictionary = PhysicsEditor.add_entry(with_panel, {
		"entry_kind_index": PhysicsEditor.ENTRY_LEAF_EVENT,
		"id": "pane_new", "child_id": "pane_new_leaf_0",
		"time_s": 120.0, "state_index": 3, "fallout_percent": 100.0,
	})
	_check(not bool(illegal["ok"]), "15 an INTACT -> OPEN jump was accepted")
	# Quitar: el listado da la ruta y el controlador la usa.
	var rows: Array[Dictionary] = PhysicsEditor.describe_prescription(with_two)
	var point_row: Dictionary = {}
	for row in rows:
		if int(row["depth"]) == 1 and String(row["family"]) == PhysicsEditor.TRACK_FAMILY:
			point_row = row
			break
	_check(not point_row.is_empty(), "15 the list gave no removable point")
	if not point_row.is_empty():
		var removed: Dictionary = PhysicsEditor.remove_entry(
			with_two, Array(point_row["path"])
		)
		_check(bool(removed["ok"]), "15 removing a point failed: %s" % str(removed["errors"]))
		if bool(removed["ok"]):
			_check(Array(Dictionary(Array(Dictionary(
					removed["opening"])[Schema.DEFORMATION_KEY])[0])["points"]).size() == 1,
					"15 the point was not removed")
	# Quitar un paño se lleva su entrada espacial.
	var panel_rows: Array[Dictionary] = PhysicsEditor.describe_prescription(with_panel)
	var panel_row: Dictionary = {}
	for row in panel_rows:
		if int(row["depth"]) == 0 and String(row["family"]) == PhysicsEditor.PANEL_FAMILY:
			panel_row = row
			break
	_check(not panel_row.is_empty(), "15 the list gave no removable panel")
	if not panel_row.is_empty():
		var dropped: Dictionary = PhysicsEditor.remove_entry(
			with_panel, Array(panel_row["path"])
		)
		_check(bool(dropped["ok"]), "15 removing a panel failed: %s" % str(dropped["errors"]))
		if bool(dropped["ok"]):
			var left: Dictionary = dropped["opening"]
			_check(not left.has(Schema.PANELS_KEY), "15 the panel survived removal")
			_check(not left.has(Schema.SPATIAL_KEY),
					"15 the spatial entry outlived its panel")
	# Los mandos ofrecen exactamente lo que el modelo puro admite.
	_check(PhysicsEditor.TRACK_LOCATIONS.size() == 4, "15 the locations no longer match D2")
	var expected_states: Array[String] = ["INTACT", "CRACKED", "PARTIAL_FALLOUT", "OPEN"]
	_check(PhysicsEditor.GLAZING_STATES == expected_states,
			"15 the glazing states no longer match D3")
	_check(PhysicsEditor.ENTRY_KINDS.size() == 4, "15 an entry kind disappeared")


# ------------------------------------------------------------
# fixtures
# ------------------------------------------------------------

func _interior_door() -> Dictionary:
	return {
		"a": 0, "b": 1, "type": "door", "wall": "right",
		"width_m": 0.9, "height_m": 2.05, "sill_m": 0.0, "open_fraction": 0.0,
	}


func _exterior_window() -> Dictionary:
	return {
		"a": 0, "b": -1, "type": "window", "wall": "bottom",
		"width_m": 1.2, "height_m": 1.0, "sill_m": 0.9, "open_fraction": 0.0,
	}


func _glazed_window() -> Dictionary:
	var window: Dictionary = _exterior_window()
	window[Schema.SCHEMA_KEY] = 1
	window[Schema.PANELS_KEY] = [{
		"id": "pane_a",
		"host_x_m": 0.2,
		"width_m": 0.6,
		"height_m": 0.5,
		"sill_z_m": 0.2,
		"glass_type": "annealed",
		"thickness_m": 0.004,
		"leaf_count": 2,
		"leaf_spacing_m": 0.012,
		"frame_material": "wood",
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


func _deformation_tracks() -> Array:
	return [{
		"id": "top",
		"location": "top",
		"z_m": 1.95,
		"points": [[0.0, 0.0], [60.0, 0.0005], [120.0, 0.003]],
	}]


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

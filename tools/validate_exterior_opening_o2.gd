extends SceneTree

## Guardarrail de la rareza (a): una puerta a la calle no puede alimentar el
## fuego peor que una puerta a una caja cerrada.
##
## Medido el 2026-09-15 (docs/PROMPT_MOTOR_RAREZAS_PORTAL_PATIO.md): la misma
## vivienda con la puerta abierta a la calle quemaba 344 MJ en 300 s y con la
## puerta abierta al portal, 401. Por la calle entraba MAS O2, pero las aperturas
## exteriores lo reponian con una heuristica contra la masa de la sala entera y
## las interiores con Bernoulli de dos zonas contra la zona inferior, que es la
## que lee el fuego. `exterior_opening_bernoulli_o2_enabled` hace que las
## exteriores usen tambien Bernoulli. Lo que se fija:
##
##  1. **Apagado por defecto**, en el motor y en el subsistema de O2: la suite
##     de validacion no se mueve.
##  2. **Apagado, se reproduce la rareza**: la puerta a la calle quema menos
##     que la puerta al portal. Si deja de reproducirse, la prueba no prueba nada.
##  3. **Encendido, la puerta a la calle alimenta al menos igual** que la
##     puerta al portal, y la zona inferior del fuego no se empobrece.
##  4. **Encendido no toca lo que no es una apertura exterior abierta**: la
##     variante del portal, con sus exteriores cerradas, quema lo mismo.
##
##   <godot> --headless --path . --script res://tools/validate_exterior_opening_o2.gd

const BuildingModelScript := preload("res://sim/BuildingModel.gd")
const BuildingTemplateScript := preload("res://sim/templates/BuildingTemplate.gd")
const Serializer := preload("res://editor/ScenarioSerializer.gd")
const OxygenExchangeSystemScript := preload("res://sim/core/OxygenExchangeSystem.gd")
const SimulationEngineScript := preload("res://sim/core/SimulationEngine.gd")

const FIXTURE_STREET: String = "res://tests/fixtures/exterior_o2_portal_C_door_to_street.json"
const FIXTURE_PORTAL: String = "res://tests/fixtures/exterior_o2_portal_D_door_to_portal.json"
const STEP_S: float = 0.5
const DURATION_S: float = 300.0
const FIRE_ROOM_ID: int = 1
## Medido: C 344 MJ, D 401 MJ con la heuristica; C 394 MJ con Bernoulli.
const STREET_VS_PORTAL_MIN_RATIO: float = 0.95

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_check_defaults()
	_check_editor_switch()
	var calle_off: Dictionary = await _run_fixture(FIXTURE_STREET, false)
	var portal_off: Dictionary = await _run_fixture(FIXTURE_PORTAL, false)
	var calle_on: Dictionary = await _run_fixture(FIXTURE_STREET, true)
	var portal_on: Dictionary = await _run_fixture(FIXTURE_PORTAL, true)
	if not (calle_off.is_empty() or portal_off.is_empty() or calle_on.is_empty() or portal_on.is_empty()):
		print("  calle: %.0f MJ apagado, %.0f encendido | portal: %.0f apagado, %.0f encendido" % [
			calle_off["burned_MJ"], calle_on["burned_MJ"], portal_off["burned_MJ"], portal_on["burned_MJ"]])
		_check_runs(calle_off, portal_off, calle_on, portal_on)
	if _failures.is_empty():
		print("EXTERIOR OPENING O2 VALIDATION PASS")
		quit(0)
		return
	for failure in _failures:
		push_error("[validate_exterior_opening_o2] FAIL: " + failure)
	print("EXTERIOR OPENING O2 VALIDATION FAILED")
	quit(1)


## 1. Apagado por defecto en los dos sitios.
func _check_defaults() -> void:
	var engine: SimulationEngine = SimulationEngineScript.new()
	if engine.exterior_opening_bernoulli_o2_enabled:
		_failures.append("el motor trae el Bernoulli exterior encendido por defecto: la suite de validacion cambiaria")
	engine.free()
	var oxygen: OxygenExchangeSystem = OxygenExchangeSystemScript.new()
	if oxygen.exterior_opening_bernoulli_o2_enabled:
		_failures.append("OxygenExchangeSystem trae el Bernoulli exterior encendido por defecto")
	oxygen.configure({"exterior_opening_bernoulli_o2_enabled": true})
	if not oxygen.exterior_opening_bernoulli_o2_enabled:
		_failures.append("OxygenExchangeSystem no lee exterior_opening_bernoulli_o2_enabled de sus ajustes")


## 5. Donde se enciende: los escenarios del editor lo llevan hasta el motor; una
## plantilla del catalogo (y un caso de validacion) no.
func _check_editor_switch() -> void:
	var builder = BuildingTemplateScript.new()
	var editor_data: Dictionary = Serializer.normalize_editor_data(builder.create_by_name("compact_apartment"))
	var parsed: Variant = JSON.parse_string(JSON.stringify(Serializer.to_runtime_json_data(editor_data)))
	var desde_editor: BuildingModel = BuildingModelScript.new()
	desde_editor.load_template_data(Dictionary(parsed))
	# La propiedad, no la igualdad con la constante del serializador: si la
	# constante pasara a false, comparar con ella se daria por bueno solo.
	if not desde_editor.exterior_opening_bernoulli_o2_enabled:
		_failures.append("un escenario del editor llega al modelo con el Bernoulli exterior apagado")
	var engine: SimulationEngine = SimulationEngineScript.new()
	engine.building = desde_editor
	if not engine._effective_exterior_opening_bernoulli_o2_enabled():
		_failures.append("con un escenario del editor el motor no aplica el Bernoulli exterior")
	var catalogo: BuildingModel = BuildingModelScript.new()
	catalogo.load_template_data(builder.create_by_name("compact_apartment"))
	engine.building = catalogo
	if engine._effective_exterior_opening_bernoulli_o2_enabled():
		_failures.append("una plantilla del catalogo enciende el Bernoulli exterior: los casos de validacion cambiarian")
	engine.building = null
	engine.free()
	desde_editor.free()
	catalogo.free()


## 2-4.
func _check_runs(calle_off: Dictionary, portal_off: Dictionary, calle_on: Dictionary, portal_on: Dictionary) -> void:
	var c_off: float = float(calle_off["burned_MJ"])
	var d_off: float = float(portal_off["burned_MJ"])
	var c_on: float = float(calle_on["burned_MJ"])
	var d_on: float = float(portal_on["burned_MJ"])
	# Medido 344 frente a 401 (0,86). Con Bernoulli siempre activo daria 392 frente
	# a 398: pedir solo "menos" dejaria pasar un interruptor que no apaga nada.
	if c_off >= 0.92 * d_off:
		_failures.append("apagado, la puerta a la calle quema %.0f MJ y la del portal %.0f (%.2f): el fixture ya no reproduce la rareza, o el interruptor no apaga" % [c_off, d_off, c_off / maxf(1.0, d_off)])
	if c_on < STREET_VS_PORTAL_MIN_RATIO * d_off:
		_failures.append("encendido, la puerta a la calle quema %.0f MJ y la del portal %.0f: la calle sigue alimentando peor" % [c_on, d_off])
	if float(calle_on["min_o2_lower_after_60s"]) < 0.205:
		_failures.append("encendido, la zona inferior del fuego con la puerta a la calle baja a %.3f de O2" % calle_on["min_o2_lower_after_60s"])
	# Lo que entra por la calle es O2 exterior, no transporte entre salas: el
	# balance de O2 (SF-O1A) lo lee de ahi.
	if float(calle_on["o2_exterior_net_kg"]) < 1.0:
		_failures.append("encendido, por la puerta a la calle solo se contabilizan %.2f kg de O2 exterior" % calle_on["o2_exterior_net_kg"])
	if absf(d_on - d_off) > 0.001:
		_failures.append("la variante del portal, sin aperturas exteriores abiertas, cambia al encender (%.3f -> %.3f MJ)" % [d_off, d_on])


func _run_fixture(path: String, enabled: bool) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		_failures.append("no se puede leer %s" % path)
		return {}
	var building: BuildingModel = BuildingModelScript.new()
	if not building.load_template_data(Dictionary(parsed)):
		_failures.append("%s rechazado por BuildingModel" % path)
		building.free()
		return {}
	var engine: SimulationEngine = SimulationEngineScript.new()
	engine.building = building
	engine.auto_ignite_on_ready = false
	engine.auto_finish_on_extinction = false
	engine.enable_logging = false
	engine.enable_csv_log = false
	engine.time_scale = 1.0
	engine.exterior_opening_bernoulli_o2_enabled = enabled
	root.add_child(engine)
	await process_frame
	engine.reset_simulation(building.default_ignition_room_id, true)
	var min_o2_lower: float = 1.0
	while engine.sim_time_s < DURATION_S:
		engine.step(STEP_S)
		var fire_room: RoomModel = building.get_room(FIRE_ROOM_ID)
		if engine.sim_time_s > 60.0:
			min_o2_lower = minf(min_o2_lower, fire_room.o2_lower)
	var fire: RoomModel = building.get_room(FIRE_ROOM_ID)
	var result: Dictionary = {
		"burned_MJ": float(fire.fuel_consumed_MJ_total),
		"min_o2_lower_after_60s": min_o2_lower,
		"o2_exterior_net_kg": float(fire.o2_exterior_net_kg_total),
	}
	root.remove_child(engine)
	engine.free()
	building.free()
	return result

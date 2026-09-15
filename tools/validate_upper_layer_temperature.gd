extends SceneTree

## Guardarrail de la temperatura de capa superior: el tope de 900 °C tapaba
## capas de gramos (docs/PROMPT_MOTOR_TOPE_900.md).
##
## Medido el 2026-09-15: en todos los picos de 900 °C del patio y del portal la
## capa superior tenia 0,7-16 g de gas y milimetros de espesor; con el tope
## subido a 5000 °C salian 2945 °C. `T = E/(m·cp)` con m casi cero no es una
## temperatura. Dos arreglos, los dos apagados por defecto:
##
##  A. **Capa casi vacia** (`thin_upper_layer_min_mass_fraction`): por debajo
##     de esa fraccion de la masa de la zona, la capa se mezcla con la inferior
##     conservando energia, igual que una inversion termica.
##       1. Apagado, una capa de 8 g con 7 kJ sale casi a 900 °C: la prueba
##          reproduce el fallo.
##       2. Encendido, sale la temperatura de la mezcla (energia total / masa
##          total), sin recorte.
##       3. Una capa gruesa de verdad no cambia.
##       4. En el patio real, apagado toca el tope; encendido no, y la sala
##          del fuego apenas se mueve.
##  B. **Techo radiativo propio** (`upper_radiative_loss_full_c`): la rampa de
##     la perdida radiativa iba de 80 °C al tope, asi que subir el tope le
##     quitaba radiacion a la capa (la vivienda del portal pasaba de 554 a 861).
##       5. Tope 5000 con techo 900 irradia lo mismo que tope 900.
##       6. Con el valor por defecto (-1) sigue al tope, como siempre; y un
##          techo por debajo del arranque cuenta como no fijado.
##
##   <godot> --headless --path . --script res://tools/validate_upper_layer_temperature.gd

const BuildingModelScript := preload("res://sim/BuildingModel.gd")
const BuildingTemplateScript := preload("res://sim/templates/BuildingTemplate.gd")
const Serializer := preload("res://editor/ScenarioSerializer.gd")
const RoomModelScript := preload("res://sim/building/RoomModel.gd")
const SimulationEngineScript := preload("res://sim/core/SimulationEngine.gd")
const ThermalSystemScript := preload("res://sim/core/ThermalSystem.gd")
const ZoneFireSolverScript := preload("res://sim/core/ZoneFireSolver.gd")

const PATIO_FIXTURE: String = "res://tests/fixtures/upper_layer_thin_patio.json"
const AMBIENT_C: float = 20.0
const THIN_FRACTION: float = 0.002
const ENGINE_STEP_S: float = 0.5
## Medido: Patio P1 toca 900 °C a t=167 s.
const ENGINE_DURATION_S: float = 220.0

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_check_thin_layer_unit()
	_check_radiative_ceiling_unit()
	_check_editor_switch()
	await _check_patio_engine()
	if _failures.is_empty():
		print("UPPER LAYER TEMPERATURE VALIDATION PASS")
		quit(0)
		return
	for failure in _failures:
		push_error("[validate_upper_layer_temperature] FAIL: " + failure)
	print("UPPER LAYER TEMPERATURE VALIDATION FAILED")
	quit(1)


func _zone_room(upper_kg: float, upper_kj: float, lower_kg: float, lower_kj: float) -> RoomModel:
	var room: RoomModel = RoomModelScript.new()
	room.width_m = 2.5
	room.length_m = 2.5
	room.height_m = 2.9
	room.reset_dynamic_state(AMBIENT_C, 0.209)
	room.upper_gas_kg = upper_kg
	room.upper_energy_kj = upper_kj
	room.lower_gas_kg = lower_kg
	room.lower_energy_kj = lower_kj
	room.temp_lower_c = AMBIENT_C + lower_kj / lower_kg
	return room


func _project(fraction: float, room: RoomModel) -> RoomModel:
	var solver: ZoneFireSolver = ZoneFireSolverScript.new()
	solver.two_zone_energy_enabled = true
	solver.thin_upper_layer_min_mass_fraction = fraction
	solver.project_room_state(room, AMBIENT_C, 900.0, "validate_upper_layer_temperature")
	return room


## A, 1-3: la capa de gramos, con y sin el arreglo, y una capa de verdad.
func _check_thin_layer_unit() -> void:
	# Lo medido en Patio P1: 8,6 g y 7,6 kJ sobre 21,6 kg de capa inferior.
	var off: RoomModel = _project(0.0, _zone_room(0.008, 7.0, 21.6, 30.0))
	if off.temp_upper_c < 800.0:
		_failures.append("apagado, una capa de 8 g con 7 kJ deberia reproducir el fallo (~900 °C) y da %.0f °C" % off.temp_upper_c)

	# 20 g con 30 kJ: la mezcla (22,8 °C) queda lejos de la capa inferior sola
	# (21,4 °C), asi que una mezcla que no conserve energia no pasa por buena.
	var on: RoomModel = _project(THIN_FRACTION, _zone_room(0.02, 30.0, 21.6, 30.0))
	var mezcla_c: float = AMBIENT_C + (30.0 + 30.0) / (0.02 + 21.6)
	if absf(on.temp_upper_c - mezcla_c) > 0.05:
		_failures.append("encendido, la capa de 8 g deberia quedar a la temperatura de la mezcla (%.1f °C) y queda a %.1f" % [mezcla_c, on.temp_upper_c])
	if on.temp_upper_clamped:
		_failures.append("encendido, la capa de 8 g sigue marcada como recortada")

	# Una capa de 10 kg a 600 °C es una capa: el arreglo no la toca.
	var gruesa_off: RoomModel = _project(0.0, _zone_room(10.0, 5800.0, 20.0, 100.0))
	var gruesa_on: RoomModel = _project(THIN_FRACTION, _zone_room(10.0, 5800.0, 20.0, 100.0))
	if absf(gruesa_on.temp_upper_c - gruesa_off.temp_upper_c) > 0.001:
		_failures.append("una capa de 10 kg a %.0f °C cambia a %.0f °C con el arreglo encendido" % [gruesa_off.temp_upper_c, gruesa_on.temp_upper_c])


func _radiative_loss_kj(max_c: float, full_c: float, upper_temp_c: float = 600.0) -> float:
	var thermal: ThermalSystem = ThermalSystemScript.new()
	thermal.max_upper_temp_c = max_c
	thermal.upper_radiative_loss_full_c = full_c
	thermal.upper_radiative_loss_max_fraction_per_step = 1.0
	var room: RoomModel = _zone_room(10.0, 1.0e6, 20.0, 100.0)
	room.thermal_layer_m = 1.5
	return thermal._compute_upper_radiative_loss_kj(room, AMBIENT_C, 0.5, 0.0, upper_temp_c)


## B, 5-6: la radiacion deja de depender del tope cuando se fija su techo.
func _check_radiative_ceiling_unit() -> void:
	var tope_900: float = _radiative_loss_kj(900.0, -1.0)
	var tope_5000_techo_900: float = _radiative_loss_kj(5000.0, 900.0)
	var tope_5000: float = _radiative_loss_kj(5000.0, -1.0)
	if tope_900 <= 0.0:
		_failures.append("una capa a 600 °C no irradia nada: la prueba de radiacion no prueba nada")
		return
	if absf(tope_5000_techo_900 - tope_900) > tope_900 * 1.0e-6:
		_failures.append("con tope 5000 y techo radiativo 900 la capa pierde %.1f kJ y con tope 900 %.1f: el techo no manda" % [tope_5000_techo_900, tope_900])
	if tope_5000 >= tope_900:
		_failures.append("por defecto la rampa deberia seguir al tope (tope 5000 irradia menos) y da %.1f frente a %.1f kJ" % [tope_5000, tope_900])
	# A 300 °C, por debajo del tope de 480: ahi la rampa no esta saturada y un
	# techo mal interpretado se nota.
	var techo_bajo: float = _radiative_loss_kj(480.0, 50.0, 300.0)
	var tope_480: float = _radiative_loss_kj(480.0, -1.0, 300.0)
	if absf(techo_bajo - tope_480) > tope_480 * 1.0e-6:
		_failures.append("un techo radiativo por debajo del arranque (50 °C) deberia contar como no fijado y cambia la perdida de %.1f a %.1f kJ" % [tope_480, techo_bajo])
	# El techo llega por los ajustes, que es por donde lo pasa el motor.
	var configurado: ThermalSystem = ThermalSystemScript.new()
	configurado.configure({"max_upper_temp_c": 5000.0, "upper_radiative_loss_full_c": 900.0})
	if not is_equal_approx(configurado._upper_radiative_full_c(), 900.0):
		_failures.append("ThermalSystem no toma el techo radiativo de sus ajustes (queda en %.0f °C)" % configurado._upper_radiative_full_c())
	var engine: SimulationEngine = SimulationEngineScript.new()
	if not is_equal_approx(engine._upper_radiative_full_c(), engine.max_upper_temp_c):
		_failures.append("en el motor, el techo radiativo por defecto deberia ser el tope")
	engine.upper_radiative_loss_full_c = 1100.0
	if not is_equal_approx(engine._upper_radiative_full_c(), 1100.0):
		_failures.append("en el motor, un techo radiativo fijado a 1100 °C no manda")
	engine.free()


## A, 7: donde se enciende. Los escenarios del editor llevan la fraccion hasta
## el motor; una plantilla del catalogo (y un caso de validacion) no.
func _check_editor_switch() -> void:
	var builder = BuildingTemplateScript.new()
	var editor_data: Dictionary = Serializer.normalize_editor_data(builder.create_by_name("compact_apartment"))
	var parsed: Variant = JSON.parse_string(JSON.stringify(Serializer.to_runtime_json_data(editor_data)))
	var desde_editor: BuildingModel = BuildingModelScript.new()
	desde_editor.load_template_data(Dictionary(parsed))
	# Comparar solo con la constante del serializador se daria por bueno a si
	# mismo si la constante bajase a 0: lo que se pide es que este ENCENDIDO.
	if desde_editor.thin_upper_layer_min_mass_fraction <= 0.0:
		_failures.append("un escenario del editor llega con la capa fina apagada: el patio y el portal volverian a tocar el tope")
	if not is_equal_approx(desde_editor.thin_upper_layer_min_mass_fraction, Serializer.EDITOR_THIN_UPPER_LAYER_MIN_MASS_FRACTION):
		_failures.append("un escenario del editor llega al modelo con fraccion de capa fina %.4f y deberia llevar %.4f" % [
			desde_editor.thin_upper_layer_min_mass_fraction, Serializer.EDITOR_THIN_UPPER_LAYER_MIN_MASS_FRACTION])
	var engine: SimulationEngine = SimulationEngineScript.new()
	engine.building = desde_editor
	if not is_equal_approx(engine._effective_thin_upper_layer_min_mass_fraction(), Serializer.EDITOR_THIN_UPPER_LAYER_MIN_MASS_FRACTION):
		_failures.append("con un escenario del editor el motor aplica fraccion %.4f" % engine._effective_thin_upper_layer_min_mass_fraction())

	var catalogo: BuildingModel = BuildingModelScript.new()
	catalogo.load_template_data(builder.create_by_name("compact_apartment"))
	engine.building = catalogo
	if engine._effective_thin_upper_layer_min_mass_fraction() != 0.0:
		_failures.append("una plantilla del catalogo enciende la capa fina (%.4f): los casos de validacion cambiarian" % engine._effective_thin_upper_layer_min_mass_fraction())
	engine.building = null
	engine.free()
	desde_editor.free()
	catalogo.free()


## A, 4: el patio de tres plantas que toca el tope.
func _check_patio_engine() -> void:
	var apagado: Dictionary = await _run_patio(0.0)
	var encendido: Dictionary = await _run_patio(THIN_FRACTION)
	if apagado.is_empty() or encendido.is_empty():
		return
	print("  patio apagado: patios %.0f °C, fuego %.0f °C | encendido: patios %.0f °C, fuego %.0f °C" % [
		apagado["patio_max_c"], apagado["fuego_max_c"], encendido["patio_max_c"], encendido["fuego_max_c"]])
	if float(apagado["patio_max_c"]) < 899.0:
		_failures.append("apagado, el patio deberia tocar el tope de 900 °C y llega a %.0f: el fixture ya no reproduce el fallo" % apagado["patio_max_c"])
	if float(encendido["patio_max_c"]) >= 899.0:
		_failures.append("encendido, una zona del patio sigue tocando el tope (%.0f °C)" % encendido["patio_max_c"])
	var fuego_off: float = float(apagado["fuego_max_c"])
	if fuego_off > 0.0 and absf(float(encendido["fuego_max_c"]) - fuego_off) > 0.10 * fuego_off:
		_failures.append("la sala del fuego pasa de %.0f a %.0f °C con el arreglo: deberia moverse menos de un 10 %%" % [fuego_off, encendido["fuego_max_c"]])


func _run_patio(fraction: float) -> Dictionary:
	var text: String = FileAccess.get_file_as_string(PATIO_FIXTURE)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		_failures.append("no se puede leer %s" % PATIO_FIXTURE)
		return {}
	var building: BuildingModel = BuildingModelScript.new()
	if not building.load_template_data(Dictionary(parsed)):
		_failures.append("%s rechazado por BuildingModel" % PATIO_FIXTURE)
		building.free()
		return {}
	var engine: SimulationEngine = SimulationEngineScript.new()
	engine.building = building
	engine.auto_ignite_on_ready = false
	engine.auto_finish_on_extinction = false
	engine.enable_logging = false
	engine.enable_csv_log = false
	engine.time_scale = 1.0
	engine.thin_upper_layer_min_mass_fraction = fraction
	root.add_child(engine)
	await process_frame
	engine.reset_simulation(building.default_ignition_room_id, true)
	var patio_max_c: float = 0.0
	var fuego_max_c: float = 0.0
	while engine.sim_time_s < ENGINE_DURATION_S:
		engine.step(ENGINE_STEP_S)
		for key in building.get_rooms().keys():
			var room: RoomModel = building.get_room(int(key))
			if String(room.name).begins_with("Patio"):
				patio_max_c = maxf(patio_max_c, room.temp_upper_c)
			elif int(key) == building.default_ignition_room_id:
				fuego_max_c = maxf(fuego_max_c, room.temp_upper_c)
	root.remove_child(engine)
	engine.free()
	building.free()
	return {"patio_max_c": patio_max_c, "fuego_max_c": fuego_max_c}

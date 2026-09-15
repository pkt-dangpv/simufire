extends SceneTree

## Guardarrail: al apagarse una sala, ningun mueble se queda con potencia.
##
## El 2026-07-15 el visor FP pinto una llama sobre un mueble de una sala ya
## apagada: se sospecho que `_extinguish_room_fire` ponia a cero la sala pero no
## sus `fuel_objects`. Medido el 2026-09-15 (`docs/PROMPT_MOTOR_HRR_RESIDUAL.md`)
## no se reproduce: la ruta pasiva, que corre en el mismo tick despues del fuego,
## recorre todos los objetos y les deja `hrr_kw = 0`. Pero la vista solo pinta
## llama con objetos en llama o decayendo, asi que si una refactorizacion
## rompiera esa puesta a cero **nadie lo veria**. Esta red lo comprueba:
##
##  1. **Sintetico**: sala con muebles ardiendo -> `_extinguish_room_fire` -> un
##     paso pasivo -> todos a potencia 0 y ninguno en llama ni decayendo.
##  2. **El apagado no impide reencender**: con la sala caliente otra vez, los
##     muebles vuelven a estar listos para autoignicion.
##  3. **Motor real**: `simple_house` cerrada hasta que el salon se apaga por
##     falta de O2, y 20 s mas; en ningun tick hay un objeto con potencia en una
##     sala sin fuego.
##
##   <godot> --headless --path . --script res://tools/validate_extinction_object_hrr.gd

const BuildingModelScript := preload("res://sim/BuildingModel.gd")
const BuildingTemplateScript := preload("res://sim/templates/BuildingTemplate.gd")
const CombustionSystemScript := preload("res://sim/fire/CombustionSystem.gd")
const FireModelScript := preload("res://sim/fire/FireModel.gd")
const FuelObjectModelScript := preload("res://sim/fire/FuelObjectModel.gd")
const RoomModelScript := preload("res://sim/building/RoomModel.gd")
const SimulationEngineScript := preload("res://sim/core/SimulationEngine.gd")

const ENGINE_TEMPLATE: String = "simple_house"
const ENGINE_STEP_S: float = 0.5
## Medido: el salon de simple_house se apaga a t=503,5 s. Con margen.
const ENGINE_MAX_S: float = 900.0
const ENGINE_AFTER_EXTINCTION_S: float = 20.0

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_check_synthetic_extinction()
	await _check_real_engine()
	if _failures.is_empty():
		print("EXTINCTION OBJECT HRR VALIDATION PASS")
		quit(0)
		return
	for failure in _failures:
		push_error("[validate_extinction_object_hrr] FAIL: " + failure)
	print("EXTINCTION OBJECT HRR VALIDATION FAILED")
	quit(1)


## 1 y 2. Sala sintetica: apagar, un paso pasivo, y que pueda reencenderse.
func _check_synthetic_extinction() -> void:
	var cs: CombustionSystem = CombustionSystemScript.new()
	var room: RoomModel = RoomModelScript.new()
	room.id = 0
	room.width_m = 4.0
	room.length_m = 5.0
	room.height_m = 2.5
	room.reset_dynamic_state(20.0, 0.209)
	var estados := [
		FuelObjectModelScript.State.FLAMING,
		FuelObjectModelScript.State.FLAMING,
		FuelObjectModelScript.State.DECAYING,
	]
	for i in estados.size():
		var obj: FuelObjectModel = FuelObjectModelScript.new()
		obj.id = "mueble_%d" % i
		obj.room_id = room.id
		obj.footprint_m2 = 1.0
		obj.exposed_area_m2 = 2.0
		obj.fuel_energy_MJ = 500.0
		obj.remaining_fuel_MJ = 400.0
		obj.max_hrr_kw = 800.0
		obj.state = estados[i]
		obj.hrr_kw = 300.0
		obj.surface_temp_c = 450.0
		obj.exposure_s = 120.0
		room.fuel_objects.append(obj)
	var fire: FireModel = FireModelScript.new()
	fire.max_hrr_kw = 2400.0
	fire.fuel_energy_MJ = 1500.0
	fire.remaining_fuel_MJ = 1200.0
	room.fire = fire
	room.hrr_kw = 900.0

	cs._extinguish_room_fire(room, fire)
	if room.fire != null or room.hrr_kw != 0.0:
		_failures.append("_extinguish_room_fire no apaga la sala (fire=%s, hrr=%.1f kW)" % [str(room.fire), room.hrr_kw])
	cs.update_passive_room_fuel(room, ENGINE_STEP_S, 20.0)
	for obj in room.fuel_objects:
		if obj.hrr_kw != 0.0:
			_failures.append("tras apagar la sala y un paso pasivo, %s sigue con %.1f kW en estado %s" % [
				obj.id, obj.hrr_kw, cs.fuel_object_state_to_string(obj.state)])
		if obj.state == FuelObjectModelScript.State.FLAMING or obj.state == FuelObjectModelScript.State.DECAYING:
			_failures.append("tras apagar la sala, %s sigue en estado %s" % [
				obj.id, cs.fuel_object_state_to_string(obj.state)])

	# El reset no puede dejar los muebles sin posibilidad de volver a arder.
	room.temp_upper_c = 650.0
	room.temp_lower_c = 180.0
	room.thermal_layer_m = 0.5
	room.h_layer_m = 0.5
	var listo: bool = false
	for _paso in range(240):
		if cs.update_passive_room_fuel(room, 1.0, 20.0):
			listo = true
			break
	if not listo:
		_failures.append("con la sala otra vez a 650 °C, ningun mueble apagado queda listo para reencenderse en 240 s")


## 3. Motor real: extincion por O2 y ningun tick con potencia en sala sin fuego.
func _check_real_engine() -> void:
	var builder = BuildingTemplateScript.new()
	var building: BuildingModel = BuildingModelScript.new()
	if not building.load_template_data(builder.create_by_name(ENGINE_TEMPLATE)):
		_failures.append("%s rechazada por BuildingModel" % ENGINE_TEMPLATE)
		building.free()
		return
	var engine: SimulationEngine = SimulationEngineScript.new()
	engine.building = building
	engine.auto_ignite_on_ready = false
	engine.auto_finish_on_extinction = false
	engine.enable_logging = false
	engine.enable_csv_log = false
	engine.time_scale = 1.0
	root.add_child(engine)
	await process_frame
	var ignition_id: int = building.default_ignition_room_id
	engine.reset_simulation(ignition_id, true)
	var cs = engine.combustion_system

	var extinction_t: float = -1.0
	var leaks: int = 0
	while engine.sim_time_s < ENGINE_MAX_S:
		engine.step(ENGINE_STEP_S)
		var ignition_room: RoomModel = building.get_room(ignition_id)
		if extinction_t < 0.0 and ignition_room.fire == null and engine.sim_time_s > ENGINE_STEP_S:
			extinction_t = engine.sim_time_s
		for room_id in building.get_rooms().keys():
			var room: RoomModel = building.get_room(room_id)
			if room.fire != null:
				continue
			for obj in room.fuel_objects:
				if obj.hrr_kw > 0.0:
					leaks += 1
					if leaks <= 3:
						_failures.append("t=%.1f s: %s en la sala apagada %d tiene %.2f kW en estado %s" % [
							engine.sim_time_s, String(obj.id), room_id, obj.hrr_kw,
							cs.fuel_object_state_to_string(obj.state)])
		if extinction_t >= 0.0 and engine.sim_time_s >= extinction_t + ENGINE_AFTER_EXTINCTION_S:
			break
	if extinction_t < 0.0:
		_failures.append("el salon de %s no se apaga en %.0f s: la prueba real no ha probado nada" % [ENGINE_TEMPLATE, ENGINE_MAX_S])
	elif leaks > 3:
		_failures.append("... y %d ticks mas con potencia en objetos de salas apagadas" % (leaks - 3))
	root.remove_child(engine)
	engine.free()
	building.free()

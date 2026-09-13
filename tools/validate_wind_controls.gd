extends SceneTree

## Guardarrail del viento: que el mando llegue al motor y empuje donde debe.
##
## El motor ya sabia de viento —`GasExchangeSystem` calcula ΔP = ½·ρ·v²·Cp
## apertura a apertura desde hace tiempo— pero **ninguna interfaz lo exponia**:
## ni el editor, ni el menu, ni un solo escenario del catalogo ponia
## `wind_speed_m_s`. Estaba dormido. Esta red comprueba las cuatro cosas que
## hacen falta para que siga despierto:
##
##  1. **El dato sobrevive el viaje** editor -> normalizacion -> json de
##     ejecucion -> `BuildingModel`. Es donde se pierden los datos nuevos.
##  2. **El signo es el correcto**: a barlovento el viento empuja hacia dentro
##     (ΔP > 0, dificulta ventear) y a sotavento succiona (ΔP < 0). Invertirlo
##     es el error clasico de la convencion meteorologica, que da los grados de
##     donde VIENE el viento y no hacia donde va.
##  3. **Con velocidad 0 no hay viento**, que es el valor por defecto de todo el
##     catalogo: encenderlo no puede cambiar lo que ya estaba medido.
##  4. **Toda apertura exterior tiene un lado canonico**. El calculo del viento
##     hace `match op.wall_side` con top/bottom/left/right y devuelve 0 para
##     cualquier otra cosa: una apertura con el lado vacio -o escrito "north"-
##     se quedaria sin viento **sin avisar**.
##
##   <godot> --headless --path . --script res://tools/validate_wind_controls.gd

const BuildingModelScript := preload("res://sim/BuildingModel.gd")
const BuildingTemplateScript := preload("res://sim/templates/BuildingTemplate.gd")
const Serializer := preload("res://editor/ScenarioSerializer.gd")

## Lados que el calculo de viento sabe leer. Cualquier otro se queda a cero.
const LADOS_CON_VIENTO: Array[String] = ["top", "bottom", "left", "right"]

var _failures: Array[String] = []


func _initialize() -> void:
	_check_round_trip()
	_check_pressure_signs()
	_check_wall_sides()
	if _failures.is_empty():
		print("WIND CONTROLS VALIDATION PASS")
		quit(0)
		return
	for failure in _failures:
		push_error("[validate_wind_controls] FAIL: " + failure)
	print("WIND CONTROLS VALIDATION FAILED")
	quit(1)


## 1. El dato llega desde el editor hasta el modelo sin perderse por el camino.
func _check_round_trip() -> void:
	var builder = BuildingTemplateScript.new()
	var editor_data: Dictionary = Serializer.normalize_editor_data(builder.create_by_name("compact_apartment"))
	editor_data["wind_speed_m_s"] = 12.5
	editor_data["wind_direction_deg"] = 225.0
	var runtime: Dictionary = Serializer.to_runtime_json_data(editor_data)
	var parsed: Variant = JSON.parse_string(JSON.stringify(runtime))
	if typeof(parsed) != TYPE_DICTIONARY:
		_failures.append("el escenario con viento no sobrevive a JSON")
		return
	var building: BuildingModel = BuildingModelScript.new()
	building.load_template_data(Dictionary(parsed))
	if not is_equal_approx(building.wind_speed_m_s, 12.5):
		_failures.append("la velocidad no llega al modelo: %.2f m/s en vez de 12,50" % building.wind_speed_m_s)
	if not is_equal_approx(building.wind_direction_deg, 225.0):
		_failures.append("la direccion no llega al modelo: %.0f grados en vez de 225" % building.wind_direction_deg)
	building.free()


## 2 y 3. El signo del empuje, y que a cero no pase nada.
func _check_pressure_signs() -> void:
	var builder = BuildingTemplateScript.new()
	var data: Dictionary = builder.create_by_name("compact_apartment")
	# Viento del norte: la fachada norte ("top") es barlovento y la sur, sotavento.
	data["wind_speed_m_s"] = 10.0
	data["wind_direction_deg"] = 0.0
	var building: BuildingModel = BuildingModelScript.new()
	building.load_template_data(data)

	var gas := GasExchangeSystem.new()
	gas.wind_effect_enabled = true
	var norte: float = _dp_for_side(gas, building, "top")
	var sur: float = _dp_for_side(gas, building, "bottom")
	var este: float = _dp_for_side(gas, building, "right")
	if norte <= 0.0:
		_failures.append("con viento del norte, la fachada norte deberia recibir empuje y da %.1f Pa" % norte)
	if sur >= 0.0:
		_failures.append("con viento del norte, la fachada sur deberia succionar y da %.1f Pa" % sur)
	if absf(este) > 0.5:
		_failures.append("una fachada perpendicular al viento no deberia notarlo y nota %.1f Pa" % este)

	# El cuadrado de la velocidad: al doblarla, el empuje se cuadruplica.
	building.wind_speed_m_s = 20.0
	var doble: float = _dp_for_side(gas, building, "top")
	if absf(doble - norte * 4.0) > 0.5:
		_failures.append("al doblar la velocidad el empuje pasa de %.1f a %.1f Pa y deberia cuadruplicarse" % [norte, doble])

	# Y a cero, nada.
	building.wind_speed_m_s = 0.0
	if absf(_dp_for_side(gas, building, "top")) > 0.001:
		_failures.append("con el viento a 0 sigue habiendo presion de viento")
	building.free()


## 4. Ninguna apertura exterior del catalogo se queda sin lado.
func _check_wall_sides() -> void:
	var builder = BuildingTemplateScript.new()
	for preset in builder.get_preset_definitions():
		var id: String = String(preset.get("id", ""))
		var building: BuildingModel = BuildingModelScript.new()
		building.load_template_data(builder.create_by_name(id))
		var huerfanas: int = 0
		for raw in building.get_openings():
			var op = raw
			if op.b >= 0:
				continue
			if not LADOS_CON_VIENTO.has(String(op.wall_side)):
				huerfanas += 1
		if huerfanas > 0:
			_failures.append("%s: %d aperturas exteriores sin lado canonico; el viento las saltaria sin avisar" % [id, huerfanas])
		building.free()


func _dp_for_side(gas, building: BuildingModel, side: String) -> float:
	for raw in building.get_openings():
		var op = raw
		if op.b >= 0 or String(op.wall_side) != side:
			continue
		return gas._compute_wind_dp_pa(op, building)
	_failures.append("el escenario de prueba no tiene ninguna apertura exterior en el lado '%s'" % side)
	return 0.0

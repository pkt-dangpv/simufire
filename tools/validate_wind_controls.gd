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
##  5. **El viento crece con la altura** (N-5), y solo cuando se pide: el
##     perfil v(z) = v10·(z/10)^α viene apagado para que la suite de validacion
##     no se mueva, y lo encienden los escenarios del editor. Encendido, subir
##     de planta empuja siempre mas; a 45 m con 10 m/s sopla a ~15 m/s (2,3
##     veces la presion de 10 m); y por debajo de 2 m no se sigue frenando.
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
	_check_height_profile()
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
	if not building.wind_height_profile_enabled:
		_failures.append("un escenario del editor llega al modelo sin el perfil de altura del viento")
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


## 5. El perfil de altura: apagado no cambia nada; encendido, la planta se nota.
func _check_height_profile() -> void:
	var builder = BuildingTemplateScript.new()
	var data: Dictionary = builder.create_by_name("compact_apartment")
	data["wind_speed_m_s"] = 10.0
	data["wind_direction_deg"] = 0.0
	var building: BuildingModel = BuildingModelScript.new()
	building.load_template_data(data)
	var gas := GasExchangeSystem.new()
	gas.wind_effect_enabled = true
	var op = null
	for raw in building.get_openings():
		if raw.b < 0 and String(raw.wall_side) == "top":
			op = raw
			break
	if op == null:
		_failures.append("el escenario de prueba no tiene apertura exterior a barlovento")
		building.free()
		return
	var room: RoomModel = building.get_room(op.a)

	# Apagado por defecto: un caso de validacion no sabe de plantas.
	if building.wind_height_profile_enabled:
		_failures.append("el perfil de altura viene encendido por defecto; los casos de validacion cambiarian")
	var calle: float = gas._compute_wind_dp_pa(op, building)
	room.floor_level_z_m = 42.0
	if gas._compute_wind_dp_pa(op, building) != calle:
		_failures.append("con el perfil apagado, subir la sala 42 m cambia el empuje del viento")
	room.floor_level_z_m = 0.0

	building.wind_height_profile_enabled = true
	# Subir de planta empuja siempre mas.
	var previo: float = -1.0
	for planta in range(16):
		room.floor_level_z_m = planta * 3.0
		var dp: float = absf(gas._compute_wind_dp_pa(op, building))
		if dp <= previo:
			_failures.append("en la planta %d el viento empuja %.2f Pa, no mas que en la de abajo (%.2f)" % [planta, dp, previo])
			break
		previo = dp
	room.floor_level_z_m = 0.0

	# Valor de contraste: 10 m/s a 10 m son ~15 m/s a 45 m, y 2,3 veces la presion.
	var v45: float = building.wind_speed_at_height_m_s(45.0)
	if v45 < 14.8 or v45 > 15.7:
		_failures.append("con 10 m/s a 10 m, a 45 m deberia soplar ~15,2 m/s y sopla %.2f" % v45)
	var centro_m: float = gas._opening_center_z_m(op, building)
	building.building_base_z_m = 10.0 - centro_m
	var dp10: float = gas._compute_wind_dp_pa(op, building)
	building.building_base_z_m = 45.0 - centro_m
	var dp45: float = gas._compute_wind_dp_pa(op, building)
	building.building_base_z_m = 0.0
	var factor: float = dp45 / dp10 if dp10 > 0.0 else 0.0
	if factor < 2.2 or factor > 2.45:
		_failures.append("la presion a 45 m deberia ser ~2,3 veces la de 10 m y es %.2f veces" % factor)

	# Suelo: por debajo de 2 m el perfil no sigue frenando.
	var v_suelo: float = building.wind_speed_at_height_m_s(0.5)
	if not is_equal_approx(v_suelo, building.wind_speed_at_height_m_s(2.0)):
		_failures.append("a 0,5 m el viento sopla %.2f m/s y deberia valer lo mismo que a 2 m" % v_suelo)
	if v_suelo > building.wind_speed_at_height_m_s(3.0):
		_failures.append("una apertura a 0,5 m recibe mas viento que una a 3 m")
	building.free()


func _dp_for_side(gas, building: BuildingModel, side: String) -> float:
	for raw in building.get_openings():
		var op = raw
		if op.b >= 0 or String(op.wall_side) != side:
			continue
		return gas._compute_wind_dp_pa(op, building)
	_failures.append("el escenario de prueba no tiene ninguna apertura exterior en el lado '%s'" % side)
	return 0.0

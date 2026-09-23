extends SceneTree

## Fase 1 FED/SVV: presentacion del indice de condiciones y de la dosis.
##
##   <godot> --headless --path . --script \
##       res://tools/validate_tenability_presentation.gd
##
## Grupos:
##   01 actual y peor historico se leen de campos DISTINTOS;
##   02 un campo ausente se dice `n/d`, no se fabrica;
##   03 ventilar sube el indice calculado ahora y NO el peor historico;
##   04 la FED acumulada mantiene bajo el indice aunque el aire mejore;
##   05 las lineas de tarjeta y de detalle enseñan las dos magnitudes;
##   06 ningun texto presenta el indice como probabilidad de supervivencia.

const Presentation := preload("res://ui/TenabilityPresentation.gd")
const HUDRoomSummaryScript := preload("res://ui/HUDRoomSummary.gd")
const RoomVisuals := preload("res://view/2d/rooms/RoomStateVisuals2D.gd")

var _failures: Array[String] = []
var _checks: int = 0


func _initialize() -> void:
	_test_01_current_and_worst_come_from_different_fields()
	_test_02_a_missing_field_is_unavailable()
	_test_03_venting_raises_current_but_not_worst()
	_test_04_accumulated_fed_keeps_the_index_down()
	_test_05_card_and_detail_show_both()
	_test_06_no_survival_wording()
	if _failures.is_empty():
		print("  %d checks" % _checks)
		print("TENABILITY PRESENTATION VALIDATION PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
		print("FAIL: " + failure)
	print("TENABILITY PRESENTATION VALIDATION FAIL (%d)" % _failures.size())
	quit(1)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


## Estado de sala como lo publica `SimulationStateBuilder`.
func _state(current: float, worst: float) -> Dictionary:
	return {
		"id": 0, "name": "Salon", "height_m": 2.5,
		"hrr_kw": 0.0, "temp_upper_c": 40.0, "temp_lower_c": 20.0,
		"o2": 0.209, "co_ppm": 0.0, "fed": 0.0,
		"smoke_layer_m": 2.5, "layer_150c_m": 2.5, "visibility_m": 30.0,
		"svv_pct": current, "svv_worst_pct": worst,
	}


# ------------------------------------------------------------
func _test_01_current_and_worst_come_from_different_fields() -> void:
	var s: Dictionary = _state(87.0, 12.0)
	_check(Presentation.current_index_pct(s) == 87.0,
			"01 el indice actual no sale de svv_pct")
	_check(Presentation.worst_index_pct(s) == 12.0,
			"01 el peor historico no sale de svv_worst_pct")
	_check(HUDRoomSummaryScript.current_index_pct(s) == 87.0,
			"01 el HUD no lee el actual")
	_check(HUDRoomSummaryScript.worst_index_pct(s) == 12.0,
			"01 el HUD no lee el peor")
	_check(RoomVisuals.compute_svv_pct(s) == 87.0, "01 la vista 2D no lee el actual")
	_check(RoomVisuals.compute_svv_worst_pct(s) == 12.0, "01 la vista 2D no lee el peor")


# ------------------------------------------------------------
func _test_02_a_missing_field_is_unavailable() -> void:
	var legacy: Dictionary = _state(50.0, 50.0)
	legacy.erase("svv_pct")
	_check(Presentation.current_index_pct(legacy) == Presentation.UNAVAILABLE,
			"02 un estado sin svv_pct no dice n/d")
	_check(Presentation.format_pct(Presentation.current_index_pct(legacy))
			== Presentation.UNAVAILABLE_TEXT,
			"02 el texto de un campo ausente no es n/d")
	# Y NO se fabrica desde el peor, que si esta.
	_check(Presentation.current_index_pct(legacy) != Presentation.worst_index_pct(legacy),
			"02 el actual se fabrico a partir del peor historico")
	var line: String = Presentation.compact_line(legacy)
	_check(line.contains(Presentation.UNAVAILABLE_TEXT),
			"02 la linea de tarjeta no marca el campo ausente")

	var both_missing: Dictionary = _state(50.0, 50.0)
	both_missing.erase("svv_pct")
	both_missing.erase("svv_worst_pct")
	_check(Presentation.worst_index_pct(both_missing) == Presentation.UNAVAILABLE,
			"02 un estado sin svv_worst_pct no dice n/d")
	# La vista 2D tampoco puede reconstruirlo desde la capa de 150 C.
	both_missing["layer_150c_m"] = 0.2
	both_missing["temp_upper_c"] = 400.0
	_check(RoomVisuals.compute_svv_pct(both_missing) == Presentation.UNAVAILABLE,
			"02 la vista 2D fabrica el indice desde la capa")


# ------------------------------------------------------------
## El caso que motivo la fase: al ventilar, el indice calculado ahora sube y el
## peor historico se queda donde estaba. Antes la interfaz solo enseñaba el
## segundo, asi que el numero no se movia nunca.
func _test_03_venting_raises_current_but_not_worst() -> void:
	var humo: Dictionary = _state(0.0, 0.0)
	_check(Presentation.current_index_pct(humo) == 0.0, "03 el indice no parte de 0")
	# Se ventila: el motor recalcula svv_pct y deja svv_worst_pct como estaba.
	var ventilado: Dictionary = _state(100.0, 0.0)
	_check(Presentation.current_index_pct(ventilado) == 100.0,
			"03 el indice calculado ahora no sube al ventilar")
	_check(Presentation.worst_index_pct(ventilado) == 0.0,
			"03 el peor historico se movio al ventilar")
	var line: String = Presentation.compact_line(ventilado)
	_check(line.contains("100%") and line.contains("0%"),
			"03 la tarjeta no enseña las dos: %s" % line)
	_check(line != Presentation.compact_line(humo),
			"03 la tarjeta no cambia al ventilar")


# ------------------------------------------------------------
## Matiz que la fase deja escrito: el indice se CALCULA ahora, pero uno de sus
## componentes es la FED acumulada. Con dosis alta puede seguir bajo con el aire
## ya limpio, y eso no es un fallo de presentacion.
func _test_04_accumulated_fed_keeps_the_index_down() -> void:
	var con_dosis: Dictionary = _state(8.0, 4.0)
	con_dosis["fed"] = 1.4
	con_dosis["visibility_m"] = 30.0
	_check(Presentation.current_index_pct(con_dosis) == 8.0,
			"04 el indice actual no respeta el valor del motor")
	_check(Presentation.current_index_pct(con_dosis)
			> Presentation.worst_index_pct(con_dosis),
			"04 el actual deberia poder estar por encima del peor")
	# La presentacion no recalcula: solo enseña lo que el motor publico.
	_check(Presentation.format_pct(8.0) == "8%", "04 el formato del porcentaje cambio")


# ------------------------------------------------------------
func _test_05_card_and_detail_show_both() -> void:
	var s: Dictionary = _state(73.0, 21.0)
	var card: Dictionary = HUDRoomSummaryScript.card_summary(0, s, 10.0, false)
	var text: String = String(card["text"])
	_check(text.contains("73%"), "05 la tarjeta no enseña el indice actual: %s" % text)
	_check(text.contains("21%"), "05 la tarjeta no enseña el peor: %s" % text)
	_check(not text.contains("SVV"), "05 la tarjeta conserva la etiqueta ambigua")

	var detail: String = HUDRoomSummaryScript.detail_text(s)
	_check(detail.contains("73%") and detail.contains("21%"),
			"05 el detalle no enseña las dos magnitudes")
	_check(detail.contains(Presentation.DISCLAIMER),
			"05 el detalle no lleva la aclaracion")
	_check(detail.contains("dosis acumulada"), "05 el detalle no nombra FED como dosis")
	_check(not detail.contains("SVV"), "05 el detalle conserva la etiqueta ambigua")


# ------------------------------------------------------------
func _test_06_no_survival_wording() -> void:
	var s: Dictionary = _state(50.0, 10.0)
	var textos: Array[String] = [
		Presentation.compact_line(s),
		Presentation.DISCLAIMER,
		Presentation.FED_CAPTION,
		HUDRoomSummaryScript.detail_text(s),
		String(HUDRoomSummaryScript.card_summary(0, s, 10.0, false)["text"]),
	]
	for raw in Presentation.detail_lines(s):
		textos.append(String(raw))
	for texto in textos:
		var bajo: String = texto.to_lower()
		_check(not bajo.contains("probabilidad de supervivencia")
				or bajo.contains("no es una probabilidad de supervivencia"),
				"06 se presenta como probabilidad de supervivencia: %s" % texto)
		for prohibido in ["% de supervivencia", "incap.", "letal"]:
			_check(not bajo.contains(prohibido),
					"06 vocabulario clinico en «%s»" % texto)
	_check(Presentation.DISCLAIMER.contains("No es una probabilidad de supervivencia"),
			"06 falta el descargo explicito")

extends RefCounted

const ScenarioValues := preload("res://sim/ScenarioValues.gd")
## Fase 1 FED/SVV: la vista 2D y el HUD comparten UN dueño de estas
## etiquetas. Sin el, cada capa se inventaba la suya y por eso llegaron a
## convivir cuatro presentaciones distintas del mismo numero.
const TenabilityPresentation := preload("res://ui/TenabilityPresentation.gd")


static func fuel_object_color_for_state(state_name: String, fallback_fill: Color) -> Color:
	match state_name:
		"flaming":
			return Color(1.0, 0.24, 0.10, 0.82)
		"pyrolyzing":
			return Color(1.0, 0.55, 0.12, 0.78)
		"heating":
			return Color(1.0, 0.78, 0.22, 0.72)
		"decaying":
			return Color(0.75, 0.38, 0.18, 0.62)
		"burned_out":
			return Color(0.24, 0.24, 0.24, 0.55)
		_:
			return fallback_fill


## Fase 1 FED/SVV: el indice combinado NO se recalcula aqui.
##
## Este fichero replicaba la formula entera de `ThermalSystem` para poder
## enseñar algo cuando el estado no traia el campo. Eso producia un numero
## fabricado, indistinguible del real y ya divergente de la formula buena. Ahora
## se lee lo que el estado trae, y si no lo trae se dice `n/d`.
##
## El calculo sigue donde estaba; esta fase es de presentacion.
static func compute_svv_pct(rs: Dictionary) -> float:
	return TenabilityPresentation.current_index_pct(rs)


static func compute_svv_worst_pct(rs: Dictionary) -> float:
	return TenabilityPresentation.worst_index_pct(rs)


static func svv_color(svv_pct: float) -> Color:
	# `n/d`: gris neutro, y nunca el color de una condicion extrema.
	if svv_pct < 0.0:
		return Color(0.55, 0.55, 0.55, 1.0)
	if svv_pct >= 90.0:
		return Color(0.30, 0.78, 0.35, 1.0)
	if svv_pct >= 60.0:
		return Color(1.00, 0.75, 0.15, 1.0)
	if svv_pct >= 20.0:
		return Color(1.00, 0.45, 0.10, 1.0)
	if svv_pct >= 5.0:
		return Color(0.95, 0.20, 0.20, 1.0)
	return Color(0.35, 0.35, 0.35, 1.0)


static func window_status_label(rs: Dictionary, full_open_threshold: float) -> String:
	var w_open: float = float(rs.get("window_open_max", -1.0))
	if w_open < 0.0:
		return ""
	if w_open <= 0.0:
		return "Win CLOSED"
	if w_open < full_open_threshold:
		return "Win BROKEN %.0f%%" % (w_open * 100.0)
	return "Win OPEN %.0f%%" % (w_open * 100.0)


## Igual que `ScenarioSerializer.vector2_from_data`: se queda por ser API
## publica -la vista 2D la llama por su nombre- pero la regla vive en un sitio.
static func vector2_from_variant(value: Variant) -> Vector2:
	return ScenarioValues.to_vector2(value)

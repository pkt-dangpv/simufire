extends RefCounted

## F2.2D1: convierte una puerta interior CERRADA en elementos de rendija ELA
## para la red autoritativa de presion.
##
## No resuelve presion, no calcula caudal, no toca salas, no toca
## `open_fraction` ni `thermal_gap_fraction`, no aplica transporte y no conoce
## el editor ni la vista. Solo describe geometria y procedencia: la ley la pone
## `ClosedDoorLeakageModel` y la resuelve el solver dentro de su residuo.
##
## Contrato de exclusividad (§9 del encargo):
##   - puerta operativamente cerrada (`is_closed()`): puede aportar rendijas;
##   - puerta con apertura operativa positiva: solo abertura grande;
##   - nunca las dos a la vez;
##   - `HOLE` nunca tiene fuga; una ventana tampoco;
##   - clase `none` sin override: estanca.
##
## `thermal_gap_fraction` NO participa: la deformacion prescrita es F2.2D2.

const LeakageModel = preload("res://sim/core/ClosedDoorLeakageModel.gd")

const CLASS_NONE: String = "none"
## Ocho bandas laterales, como pide el diseno provisional de D1.
const SIDE_BAND_COUNT: int = 8
## Dominio experimental senalado (NBSIR 81-2214). No recorta nada: se registra.
const PRESSURE_DOMAIN_MAX_PA: float = 50.0


## ¿Esta puerta aporta rendijas en este paso? Es la misma pregunta que responde
## el snapshot de la red, y se contesta en un solo sitio.
static func provides_leakage(opening, outside_id: int) -> bool:
	if opening == null:
		return false
	if int(opening.type) != OpeningModel.Type.DOOR:
		return false
	if int(opening.a) == outside_id or int(opening.b) == outside_id:
		return false
	if not opening.is_closed():
		return false
	return resolved_ela_m2(opening) > 0.0


## ELA resultante de la clase y el override. El override, si es valido, MANDA
## sobre la clase; un override negativo o no finito se rechaza mas arriba.
static func resolved_ela_m2(opening) -> float:
	if opening == null:
		return 0.0
	var override_m2: float = float(opening.leakage_area_override_m2)
	if is_finite(override_m2) and override_m2 >= 0.0:
		return override_m2
	return class_ela_m2(String(opening.leakage_class))


## Unica tabla: la del modelo puro. Aqui no se copia ningun numero.
static func class_ela_m2(leakage_class: String) -> float:
	if not LeakageModel.PLANNED_CLASS_ELA_M2.has(leakage_class):
		return NAN
	return float(LeakageModel.PLANNED_CLASS_ELA_M2[leakage_class])


static func is_known_class(leakage_class: String) -> bool:
	return LeakageModel.PLANNED_CLASS_ELA_M2.has(leakage_class)


## Elemento de rendija para el solver, o {} si esta puerta no aporta fuga.
##
## `floor_z_m` es la cota absoluta del suelo del paramento: las cotas locales
## que devuelve `build_door_segments` se trasladan aqui y solo aqui.
static func build_crack_element(
	opening,
	outside_id: int,
	floor_z_m: float,
	room_a_key: String,
	room_b_key: String,
	dt_s: float
) -> Dictionary:
	if not provides_leakage(opening, outside_id):
		return {}
	var ela_m2: float = resolved_ela_m2(opening)
	if not is_finite(ela_m2) or ela_m2 <= 0.0:
		return {}
	var built: Dictionary = LeakageModel.build_door_segments(
		ela_m2, 0.0, float(opening.height_m), LeakageModel.PROVISIONAL_SPLIT, SIDE_BAND_COUNT
	)
	if not bool(built["valid"]):
		return {}
	var segments: Array = []
	for raw_segment in built["segments"]:
		var segment: Dictionary = raw_segment
		segments.append({
			"segment_id": String(segment["id"]),
			"z_m": floor_z_m + float(segment["z_m"]),
			"area_m2": float(segment["area_m2"]),
		})
	return {
		"opening_id": int(opening.opening_index),
		"room_a_id": int(opening.a),
		"room_b_id": int(opening.b),
		"room_a_key": room_a_key,
		"room_b_key": room_b_key,
		"flow_model": "ela_crack",
		"crack_segments": segments,
		"ela_reference_pressure_pa": LeakageModel.NIST_ELA_REFERENCE_PRESSURE_PA,
		"flow_exponent": LeakageModel.PROVISIONAL_FLOW_EXPONENT_CANDIDATE,
		# Se empieza midiendo SIN regularizacion, como pide el encargo.
		"zero_pressure_regularization_pa": 0.0,
		"pressure_domain_max_pa": PRESSURE_DOMAIN_MAX_PA,
		"provenance": "cold_leakage",
		"leakage_class": String(opening.leakage_class),
		"leakage_area_override_m2": float(opening.leakage_area_override_m2),
		"resolved_ela_m2": ela_m2,
		"dt_s": dt_s,
	}

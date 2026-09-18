extends RefCounted

## Fuga permanente de una puerta interior CERRADA: modelo puro.
##
## Fase 1 de docs/PROMPT_MOTOR_FUGAS_PUERTA_CERRADA.md (§6.6). No esta conectado
## al motor: nadie lo carga en el paso de simulacion. No lee escenarios, no toca
## salas ni aberturas, no guarda estado y no cambia `open_fraction`: recibe
## numeros y devuelve una lista de flujos dirigidos que consumira despues un
## unico consumidor (masa, entalpia, O2, humo y especies juntos).
##
## Convencion del ELA (fuentes locales en docs/literature/NIST):
##
## - El dato es el area efectiva de fuga, ELA, en m2, referida a 4 Pa (NIST
##   TN 2329, p. 26). Los 12 y 21 cm2 de TN 2329 (p. 28) son ELA a 4 Pa.
## - CONTAM (NIST TN 1887r1, p. 266, ec. 28) define L = Q_r·sqrt(ρ/2ΔP_r)/C_d y
##   da dos convenciones habituales: C_d = 1,0 con ΔP_r = 4 Pa, o C_d = 0,6 con
##   ΔP_r = 10 Pa. Un ELA a 4 Pa va con C_d = 1,0.
## - Con la ec. 29 (C_b = L·C_d·√2·ΔP_r^(1/2-n)) y la ley de potencia en masa
##   F = C_b·sqrt(ρ_origen)·ΔP^n (ec. 24, p. 265), el caudal volumetrico es,
##   con C_d = 1,0 y ΔP_r = 4 Pa:
##
##       Q_ref = ELA · sqrt(2·ΔP_ref/ρ_origen)
##       Q     = Q_ref · (|ΔP|/ΔP_ref)^n
##
##   No hay coeficiente de descarga en la API ni en la formula: la convencion ya
##   lo lleva dentro, y asi no se puede aplicar dos veces. La otra convencion
##   (10 Pa / C_d = 0,6) NO esta implementada: se rechaza cualquier presion de
##   referencia distinta de 4 Pa y cualquier `discharge_coefficient`.
##
## Exponente (`flow_exponent`, obligatorio, en [0,5; 1,0]):
##
## - Las fuentes de puertas lo hacen depender del regimen: NBSIR 81-2214
##   (p. 4) da n entre 0,5 y 1,0 y usa 0,5 para holguras de puerta (tabla 1,
##   p. 17); Gross y Haberman 1989 (pp. 172-173) muestran el paso de lineal a
##   raiz cuadrada.
## - CONTAM considera razonable un valor entre 0,6 y 0,7 cuando no hay dato
##   experimental (TN 1887r1, p. 266).
## - 0,65 es el CANDIDATO PROVISIONAL para futuras integraciones
##   (`PROVISIONAL_FLOW_EXPONENT_CANDIDATE`, solo informativo). No es una
##   calibracion de puertas interiores residenciales y el modelo no lo usa: el
##   llamante tiene que pasar el exponente.
##
## Regularizacion en ΔP = 0 (`zero_pressure_regularization_pa`, obligatorio,
## >= 0): es un recurso NUMERICO, no un dato fisico medido. Con 0 se usa la ley
## de potencia pura (recomendado para la primera integracion salvo necesidad
## numerica demostrada). Con un valor positivo, por debajo de el el caudal es la
## recta desde el origen hasta la ley de potencia en ese punto: continua,
## monotona y con el mismo signo que ΔP.
##
## Dominio: NBSIR 81-2214 considera improbable que la ΔP a traves de una puerta
## interior pase de 50 Pa (p. 10). Por encima de `pressure_domain_max_pa` el
## resultado se MARCA (`domain_exceeded`), pero no se recorta: ningun limite
## oculta una entrada fisicamente invalida. Las entradas invalidas devuelven
## `valid = false` sin flujos.
##
## Reparto en cota: el ELA total se reparte entre holgura inferior, laterales
## en N bandas y dintel (Gross y Haberman, p. 177, observacion 4). El reparto
## solo decide la cota, el sentido y la zona de origen; la suma de areas es el
## ELA total.
##
## Lado receptor: el modelo describe SOLO el cruce por la abertura. Devuelve la
## zona que ocupa la cota del segmento en el recinto receptor y la densidad de
## esa zona; no decide flotabilidad, mezcla, ascenso ni en que capa se deposita
## la parcela. Eso es del futuro consumidor unico de transporte.
##
## Convenio de signo: ΔP(z) = p_a(z) - p_b(z). Positivo: el gas va de a a b.

const SIDE_A: String = "a"
const SIDE_B: String = "b"
const ZONE_LOWER: String = "lower"
const ZONE_UPPER: String = "upper"
const DIRECTION_A_TO_B: String = "a_to_b"
const DIRECTION_B_TO_A: String = "b_to_a"
const DIRECTION_NONE: String = "none"

const SEGMENT_BOTTOM: String = "bottom"
const SEGMENT_TOP: String = "top"
const SEGMENT_SIDE_PREFIX: String = "side_"

const GRAVITY_M_S2: float = 9.81

## Presion de referencia del ELA (NIST TN 2329, p. 26; convencion de CONTAM
## con C_d = 1,0, TN 1887r1, p. 266). Es la unica admitida.
const NIST_ELA_REFERENCE_PRESSURE_PA: float = 4.0

## Solo informativo: el modelo no lo usa y el llamante pasa el exponente.
## Intervalo razonable de CONTAM (0,6-0,7) sin dato experimental; no es una
## calibracion de puertas interiores residenciales.
const PROVISIONAL_FLOW_EXPONENT_CANDIDATE: float = 0.65

## Clases previstas para etapas posteriores. NO las usa todavia ningun modelo
## del motor; el modelo puro recibe el ELA directamente. ELA a 4 Pa con
## C_d = 1,0: NIST TN 2329 (p. 28), "best estimate" de ASHRAE 2001 para una
## puerta sencilla con burlete (12 cm2) y sin burlete (21 cm2); NIST aplica el
## segundo a la puerta garaje-vivienda y a la de sotano. Provisionales: 21 cm2
## no es una medicion universal de puertas interiores.
const PLANNED_CLASS_ELA_M2: Dictionary = {
	"none": 0.0,
	"entry_tight": 0.0012,
	"interior_tight": 0.0021,
}

## Reparto provisional (proporcion geometrica de una puerta de paso, ver el
## documento de diseño §6.2). No es un dato medido; el llamante lo pasa
## explicitamente.
const PROVISIONAL_SPLIT: Dictionary = {
	"bottom": 0.40,
	"sides": 0.47,
	"top": 0.13,
}

const SPLIT_SUM_TOLERANCE: float = 1.0e-9

const REQUIRED_PARAMS: Array[String] = [
	"ela_reference_pressure_pa",
	"flow_exponent",
	"zero_pressure_regularization_pa",
	"pressure_domain_max_pa",
]

## Claves que no pertenecen a la API ELA a 4 Pa: se rechazan para que nadie
## aplique un coeficiente de descarga encima de la convencion.
const FORBIDDEN_PARAMS: Array[String] = [
	"discharge_coefficient",
	"reference_pressure_pa",
	"linear_regime_pressure_pa",
]


## Construye los segmentos de fuga de una puerta a partir de su ELA total.
##
## Devuelve {valid, errors, segments}. Cada segmento es {id, z_m, area_m2}:
## `bottom` en la cota del umbral, `side_00`..`side_NN` en el centro de N
## bandas iguales de [sill, sill + H] y `top` en la cota del dintel.
static func build_door_segments(
	ela_m2: float,
	sill_z_m: float,
	door_height_m: float,
	split: Dictionary,
	side_band_count: int
) -> Dictionary:
	var errors: Array[String] = []
	if not _is_finite(ela_m2) or ela_m2 < 0.0:
		errors.append("ela_m2 must be finite and >= 0")
	if not _is_finite(sill_z_m):
		errors.append("sill_z_m must be finite")
	if not _is_finite(door_height_m) or door_height_m <= 0.0:
		errors.append("door_height_m must be finite and > 0")
	if side_band_count < 1:
		errors.append("side_band_count must be >= 1")
	var fractions: Dictionary = {}
	for key in ["bottom", "sides", "top"]:
		if not split.has(key):
			errors.append("split is missing '%s'" % key)
			continue
		var value: float = float(split[key])
		if not _is_finite(value) or value < 0.0:
			errors.append("split '%s' must be finite and >= 0" % key)
		fractions[key] = value
	if fractions.size() == 3:
		var fraction_sum: float = float(fractions["bottom"]) + float(fractions["sides"]) + float(fractions["top"])
		if absf(fraction_sum - 1.0) > SPLIT_SUM_TOLERANCE:
			errors.append("split fractions must add up to 1 (got %.12f)" % fraction_sum)
	if not errors.is_empty():
		return {"valid": false, "errors": errors, "segments": []}

	var bottom_area_m2: float = ela_m2 * float(fractions["bottom"])
	var top_area_m2: float = ela_m2 * float(fractions["top"])
	# Los laterales se quedan con el resto: asi la suma es el ELA total aunque
	# las fracciones traigan redondeo.
	var sides_area_m2: float = ela_m2 - bottom_area_m2 - top_area_m2
	var band_height_m: float = door_height_m / float(side_band_count)

	var segments: Array = []
	segments.append({"id": SEGMENT_BOTTOM, "z_m": sill_z_m, "area_m2": bottom_area_m2})
	var assigned_sides_m2: float = 0.0
	for band in range(side_band_count):
		var band_area_m2: float = sides_area_m2 / float(side_band_count)
		if band == side_band_count - 1:
			band_area_m2 = sides_area_m2 - assigned_sides_m2
		assigned_sides_m2 += band_area_m2
		segments.append({
			"id": "%s%02d" % [SEGMENT_SIDE_PREFIX, band],
			"z_m": sill_z_m + (float(band) + 0.5) * band_height_m,
			"area_m2": band_area_m2,
		})
	segments.append({"id": SEGMENT_TOP, "z_m": sill_z_m + door_height_m, "area_m2": top_area_m2})
	return {"valid": true, "errors": errors, "segments": segments}


## Estado de flujo de todos los segmentos para unos perfiles de presion dados.
##
## `side_a`/`side_b`: {floor_z_m, interface_height_m, rho_lower_kg_m3,
## rho_upper_kg_m3, p_floor_pa}. La presion en la cota absoluta z es la del
## suelo menos la columna hidrostatica de las dos zonas; la zona es `lower`
## por debajo de la interfaz y `upper` desde ella.
##
## `params`: {ela_reference_pressure_pa (= 4), flow_exponent,
## zero_pressure_regularization_pa, pressure_domain_max_pa}, todos
## obligatorios. `discharge_coefficient` se rechaza.
##
## `dt_s` >= 0: la masa transferible del paso es el caudal masico por dt_s.
##
## Devuelve {valid, errors, flows, net_mass_a_to_b_kg_s, gross_mass_kg_s,
## max_abs_dp_pa, domain_exceeded}. `flows` va ordenado por (z_m, segment_id),
## asi que el resultado no depende del orden de entrada. No modifica ninguna
## entrada ni devuelve presiones nuevas: no iguala presiones.
static func compute_flows(
	segments: Array,
	side_a: Dictionary,
	side_b: Dictionary,
	params: Dictionary,
	dt_s: float = 0.0
) -> Dictionary:
	var errors: Array[String] = []
	_validate_params(params, errors)
	_validate_side(side_a, SIDE_A, errors)
	_validate_side(side_b, SIDE_B, errors)
	if not _is_finite(dt_s) or dt_s < 0.0:
		errors.append("dt_s must be finite and >= 0")
	var ordered: Array = _validated_sorted_segments(segments, errors)
	if not errors.is_empty():
		return _invalid_result(errors)

	var reference_pa: float = float(params["ela_reference_pressure_pa"])
	var exponent: float = float(params["flow_exponent"])
	var regularization_pa: float = float(params["zero_pressure_regularization_pa"])
	var domain_max_pa: float = float(params["pressure_domain_max_pa"])

	var flows: Array = []
	var net_mass_kg_s: float = 0.0
	var gross_mass_kg_s: float = 0.0
	var max_abs_dp_pa: float = 0.0
	for segment in ordered:
		var z_m: float = float(segment["z_m"])
		var area_m2: float = float(segment["area_m2"])
		var dp_pa: float = pressure_at(side_a, z_m) - pressure_at(side_b, z_m)
		if not _is_finite(dp_pa):
			return _invalid_result(["non-finite pressure difference at %s" % segment["id"]])
		max_abs_dp_pa = maxf(max_abs_dp_pa, absf(dp_pa))

		var flow: Dictionary = {
			"segment_id": String(segment["id"]),
			"z_m": z_m,
			"area_m2": area_m2,
			"dp_pa": dp_pa,
			"direction": DIRECTION_NONE,
			"volume_flow_m3_s": 0.0,
			"signed_volume_flow_m3_s": 0.0,
			"mass_flow_kg_s": 0.0,
			"mass_step_kg": 0.0,
			"source_side": "",
			"source_zone": "",
			"source_density_kg_m3": 0.0,
			"destination_side": "",
			"destination_zone_at_height": "",
			"destination_density_at_height": 0.0,
		}
		if area_m2 > 0.0 and dp_pa != 0.0:
			var source: Dictionary = side_a if dp_pa > 0.0 else side_b
			var destination: Dictionary = side_b if dp_pa > 0.0 else side_a
			# Una sola ley, un solo sitio: el helper decide signo, densidad de
			# origen, potencia y regularizacion. El solver de red usa este mismo.
			var segment_flow: Dictionary = compute_segment_flow_from_dp(
				area_m2, dp_pa, density_at(side_a, z_m), density_at(side_b, z_m),
				reference_pa, exponent, regularization_pa, dt_s, domain_max_pa
			)
			var rho_source: float = float(segment_flow["source_density_kg_m3"])
			var volume_m3_s: float = float(segment_flow["volume_flow_m3_s"])
			var mass_kg_s: float = float(segment_flow["mass_flow_kg_s"])
			flow["direction"] = String(segment_flow["direction"])
			flow["volume_flow_m3_s"] = volume_m3_s
			flow["signed_volume_flow_m3_s"] = float(segment_flow["signed_volume_flow_m3_s"])
			flow["mass_flow_kg_s"] = mass_kg_s
			flow["mass_step_kg"] = float(segment_flow["mass_step_kg"])
			flow["source_side"] = SIDE_A if dp_pa > 0.0 else SIDE_B
			flow["source_zone"] = zone_at(source, z_m)
			flow["source_density_kg_m3"] = rho_source
			flow["destination_side"] = SIDE_B if dp_pa > 0.0 else SIDE_A
			# Solo geometria: la zona que ocupa esta cota en el receptor. Donde
			# acabe la parcela lo decide el consumidor de transporte.
			flow["destination_zone_at_height"] = zone_at(destination, z_m)
			flow["destination_density_at_height"] = density_at(destination, z_m)
			net_mass_kg_s += float(segment_flow["signed_mass_flow_kg_s"])
			gross_mass_kg_s += mass_kg_s
		flows.append(flow)

	return {
		"valid": true,
		"errors": errors,
		"flows": flows,
		"net_mass_a_to_b_kg_s": net_mass_kg_s,
		"gross_mass_kg_s": gross_mass_kg_s,
		"max_abs_dp_pa": max_abs_dp_pa,
		"domain_exceeded": max_abs_dp_pa > domain_max_pa,
	}


## Flujo de UN segmento de grieta a partir de una diferencia de presion CON
## SIGNO. Es el unico sitio donde viven, a la vez:
##   - el sentido (dp > 0 va de A a B);
##   - la eleccion de la densidad de ORIGEN (la del lado que empuja);
##   - la ley de potencia con ELA a `reference_pa` y `C_d = 1,0` incorporado;
##   - la regularizacion numerica cerca de dp = 0;
##   - la marca de dominio experimental excedido.
##
## Lo usan `compute_flows` (modelo puro, presiones impuestas) y el solver de red
## (F2.2B) dentro de su residuo de Newton. No hay una segunda copia de la ley.
##
## Devuelve {valid, errors, direction, abs_dp_pa, volume_flow_m3_s,
## signed_volume_flow_m3_s, mass_flow_kg_s, signed_mass_flow_kg_s, mass_step_kg,
## source_side, source_density_kg_m3, regularized, domain_exceeded}.
static func compute_segment_flow_from_dp(
	area_m2: float,
	dp_pa: float,
	rho_a_kg_m3: float,
	rho_b_kg_m3: float,
	reference_pa: float,
	exponent: float,
	regularization_pa: float,
	dt_s: float = 0.0,
	domain_max_pa: float = INF
) -> Dictionary:
	var result: Dictionary = {
		"valid": false,
		"errors": [],
		"direction": DIRECTION_NONE,
		"abs_dp_pa": 0.0,
		"volume_flow_m3_s": 0.0,
		"signed_volume_flow_m3_s": 0.0,
		"mass_flow_kg_s": 0.0,
		"signed_mass_flow_kg_s": 0.0,
		"mass_step_kg": 0.0,
		"source_side": "",
		"source_density_kg_m3": 0.0,
		"regularized": false,
		"domain_exceeded": false,
	}
	var errors: Array[String] = []
	if not _is_finite(area_m2) or area_m2 < 0.0:
		errors.append("area_m2 must be finite and >= 0")
	if not _is_finite(dp_pa):
		errors.append("dp_pa must be finite")
	if not _is_finite(rho_a_kg_m3) or rho_a_kg_m3 <= 0.0 \
			or not _is_finite(rho_b_kg_m3) or rho_b_kg_m3 <= 0.0:
		errors.append("both densities must be finite and > 0")
	if not _is_finite(reference_pa) or reference_pa <= 0.0:
		errors.append("reference_pa must be finite and > 0")
	if not _is_finite(exponent) or exponent <= 0.0:
		errors.append("flow_exponent must be finite and > 0")
	if not _is_finite(regularization_pa) or regularization_pa < 0.0:
		errors.append("zero_pressure_regularization_pa must be finite and >= 0")
	if not _is_finite(dt_s) or dt_s < 0.0:
		errors.append("dt_s must be finite and >= 0")
	if not errors.is_empty():
		result["errors"] = errors
		return result

	result["valid"] = true
	var abs_dp_pa: float = absf(dp_pa)
	result["abs_dp_pa"] = abs_dp_pa
	result["domain_exceeded"] = abs_dp_pa > domain_max_pa
	if area_m2 <= 0.0 or dp_pa == 0.0:
		return result
	var from_a: bool = dp_pa > 0.0
	var rho_source: float = rho_a_kg_m3 if from_a else rho_b_kg_m3
	var volume_m3_s: float = crack_volume_flow_m3_s(
		area_m2, abs_dp_pa, rho_source, reference_pa, exponent, regularization_pa
	)
	var mass_kg_s: float = rho_source * volume_m3_s
	result["direction"] = DIRECTION_A_TO_B if from_a else DIRECTION_B_TO_A
	result["source_side"] = SIDE_A if from_a else SIDE_B
	result["source_density_kg_m3"] = rho_source
	result["volume_flow_m3_s"] = volume_m3_s
	result["signed_volume_flow_m3_s"] = volume_m3_s if from_a else -volume_m3_s
	result["mass_flow_kg_s"] = mass_kg_s
	result["signed_mass_flow_kg_s"] = mass_kg_s if from_a else -mass_kg_s
	result["mass_step_kg"] = mass_kg_s * dt_s
	result["regularized"] = regularization_pa > 0.0 and abs_dp_pa < regularization_pa
	return result


## Caudal volumetrico (m3/s, >= 0) por una grieta de ELA `area_m2` (a 4 Pa,
## C_d = 1,0) con una diferencia de presion `abs_dp_pa` >= 0.
static func crack_volume_flow_m3_s(
	area_m2: float,
	abs_dp_pa: float,
	rho_source_kg_m3: float,
	reference_pa: float,
	exponent: float,
	regularization_pa: float
) -> float:
	if area_m2 <= 0.0 or abs_dp_pa <= 0.0:
		return 0.0
	var reference_flow_m3_s: float = area_m2 * sqrt(2.0 * reference_pa / rho_source_kg_m3)
	if regularization_pa <= 0.0 or abs_dp_pa >= regularization_pa:
		return reference_flow_m3_s * pow(abs_dp_pa / reference_pa, exponent)
	# Regularizacion numerica: recta desde el origen hasta el valor de la ley de
	# potencia en `regularization_pa`. Continua y monotona.
	var joint_flow_m3_s: float = reference_flow_m3_s * pow(regularization_pa / reference_pa, exponent)
	return joint_flow_m3_s * (abs_dp_pa / regularization_pa)


static func pressure_at(side: Dictionary, z_m: float) -> float:
	var z_rel_m: float = z_m - float(side["floor_z_m"])
	var interface_m: float = float(side["interface_height_m"])
	var rho_lower: float = float(side["rho_lower_kg_m3"])
	var rho_upper: float = float(side["rho_upper_kg_m3"])
	var column_kg_m2: float
	if z_rel_m <= interface_m:
		column_kg_m2 = rho_lower * z_rel_m
	else:
		column_kg_m2 = rho_lower * interface_m + rho_upper * (z_rel_m - interface_m)
	return float(side["p_floor_pa"]) - GRAVITY_M_S2 * column_kg_m2


static func zone_at(side: Dictionary, z_m: float) -> String:
	var z_rel_m: float = z_m - float(side["floor_z_m"])
	return ZONE_LOWER if z_rel_m < float(side["interface_height_m"]) else ZONE_UPPER


static func density_at(side: Dictionary, z_m: float) -> float:
	if zone_at(side, z_m) == ZONE_LOWER:
		return float(side["rho_lower_kg_m3"])
	return float(side["rho_upper_kg_m3"])


static func area_total_m2(segments: Array) -> float:
	var total: float = 0.0
	for segment in segments:
		total += float(segment["area_m2"])
	return total


static func _validate_params(params: Dictionary, errors: Array[String]) -> void:
	for key in FORBIDDEN_PARAMS:
		if params.has(key):
			errors.append("params '%s' is not part of the 4 Pa ELA API" % key)
	for key in REQUIRED_PARAMS:
		if not params.has(key):
			errors.append("params is missing '%s'" % key)
		elif not _is_finite(float(params[key])):
			errors.append("params '%s' must be finite" % key)
	if not errors.is_empty():
		return
	if float(params["ela_reference_pressure_pa"]) != NIST_ELA_REFERENCE_PRESSURE_PA:
		errors.append("ela_reference_pressure_pa must be 4 Pa (only the 4 Pa / Cd 1.0 convention is implemented)")
	var exponent: float = float(params["flow_exponent"])
	if exponent < 0.5 or exponent > 1.0:
		errors.append("flow_exponent must be within [0.5, 1.0]")
	if float(params["zero_pressure_regularization_pa"]) < 0.0:
		errors.append("zero_pressure_regularization_pa must be >= 0")
	if float(params["pressure_domain_max_pa"]) <= 0.0:
		errors.append("pressure_domain_max_pa must be > 0")


static func _validate_side(side: Dictionary, label: String, errors: Array[String]) -> void:
	for key in ["floor_z_m", "interface_height_m", "rho_lower_kg_m3", "rho_upper_kg_m3", "p_floor_pa"]:
		if not side.has(key):
			errors.append("side_%s is missing '%s'" % [label, key])
		elif not _is_finite(float(side[key])):
			errors.append("side_%s '%s' must be finite" % [label, key])
	if not errors.is_empty():
		return
	if float(side["interface_height_m"]) < 0.0:
		errors.append("side_%s interface_height_m must be >= 0" % label)
	if float(side["rho_lower_kg_m3"]) <= 0.0 or float(side["rho_upper_kg_m3"]) <= 0.0:
		errors.append("side_%s densities must be > 0" % label)


static func _validated_sorted_segments(segments: Array, errors: Array[String]) -> Array:
	var seen: Dictionary = {}
	var copies: Array = []
	for segment in segments:
		if typeof(segment) != TYPE_DICTIONARY \
				or not segment.has("id") or not segment.has("z_m") or not segment.has("area_m2"):
			errors.append("each segment needs id, z_m and area_m2")
			continue
		var segment_id: String = String(segment["id"])
		if seen.has(segment_id):
			errors.append("duplicate segment id '%s'" % segment_id)
		seen[segment_id] = true
		var z_m: float = float(segment["z_m"])
		var area_m2: float = float(segment["area_m2"])
		if not _is_finite(z_m):
			errors.append("segment '%s' z_m must be finite" % segment_id)
		if not _is_finite(area_m2) or area_m2 < 0.0:
			errors.append("segment '%s' area_m2 must be finite and >= 0" % segment_id)
		copies.append({"id": segment_id, "z_m": z_m, "area_m2": area_m2})
	copies.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return _segment_before(left, right))
	return copies


static func _segment_before(left: Dictionary, right: Dictionary) -> bool:
	if float(left["z_m"]) != float(right["z_m"]):
		return float(left["z_m"]) < float(right["z_m"])
	return String(left["id"]) < String(right["id"])


static func _invalid_result(errors: Array) -> Dictionary:
	return {
		"valid": false,
		"errors": errors,
		"flows": [],
		"net_mass_a_to_b_kg_s": 0.0,
		"gross_mass_kg_s": 0.0,
		"max_abs_dp_pa": 0.0,
		"domain_exceeded": false,
	}


static func _is_finite(value: float) -> bool:
	return not is_nan(value) and not is_inf(value)

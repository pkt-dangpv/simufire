extends RefCounted

## Deformacion PRESCRITA de una puerta cerrada: modelo puro.
##
## Fase 2 de docs/PROMPT_MOTOR_FUGAS_PUERTA_CERRADA.md. No esta conectado al
## motor ni al editor, no lee escenarios, no guarda estado y no modifica sus
## entradas. No calcula caudales: produce segmentos {id, z_m, area_m2} que
## consume el unico solver de flujo puro, ClosedDoorLeakageModel.
##
## Que representa: huecos LOCALIZADOS que una puerta cerrada deformada anade a
## su fuga fria, prescritos como pistas temporales. La topologia viene de los
## ensayos (Prieler et al. 2023, pp. 16-19, figs. 18-23: huecos principales en el
## borde superior y en el lado de la cerradura por encima de ella; menores en el
## lado de bisagras y pasadores). Las magnitudes NO estan calibradas para
## puertas residenciales, por eso no hay ninguna ley automatica: el modelo no
## lee temperaturas, no convierte milimetros ni deformacion central en area y
## no abre la hoja de forma uniforme. La fraccion de apertura operativa y el
## hueco termico heredado del motor no se leen ni se escriben aqui.
##
## Magnitud fisica: `additional_ela_m2`, AREA EFECTIVA ADICIONAL con la misma
## convencion que la fuga fria (ELA a 4 Pa con C_d = 1,0, NIST TN 1887r1). No es
## area geometrica. Los metadatos de una pista (milimetros de hueco, origen de la
## prescripcion, etc.) se conservan como procedencia y no entran en el calculo.
##
## Pistas: {id, location, z_m, points, metadata?}
##   - location: `bottom`, `top`, `hinge_side` o `latch_side`.
##   - id: `bottom`, `top`, `hinge_side_NN` o `latch_side_NN`, coherente con
##     `location`. NN son exactamente dos digitos ASCII '0'-'9' (00-99): se
##     rechazan signos, espacios, decimales, letras, digitos no ASCII y
##     cualquier otra longitud.
##   - points: [[time_s, additional_ela_m2], ...] con tiempos finitos
##     estrictamente crecientes y areas finitas >= 0. El area puede subir o bajar.
##
## Evaluacion en `time_s`:
##   - antes del primer punto: 0 (la prescripcion empieza en su primer punto);
##   - en cada punto: su valor exacto;
##   - entre puntos: interpolacion lineal;
##   - despues del ultimo punto: se mantiene el ultimo valor (sin extrapolar).
##
## Combinacion con la fuga fria:
##   ELA_total_local = ELA_fria_local + ELA_adicional_deformacion
##   - un segmento con el mismo id y la misma cota se fusiona sumando areas;
##     mismo id con otra cota es un error;
##   - un segmento de deformacion nuevo se inserta solo si su area evaluada es
##     positiva, de modo que deformacion cero deja exactamente los segmentos de
##     la fuga fria;
##   - la salida va ordenada por (z_m, id) y conserva la procedencia de cada
##     contribucion.

const LOCATION_BOTTOM: String = "bottom"
const LOCATION_TOP: String = "top"
const LOCATION_HINGE_SIDE: String = "hinge_side"
const LOCATION_LATCH_SIDE: String = "latch_side"
const LOCATIONS: Array[String] = [LOCATION_BOTTOM, LOCATION_TOP, LOCATION_HINGE_SIDE, LOCATION_LATCH_SIDE]

const SOURCE_COLD: String = "cold"
const SOURCE_DEFORMATION: String = "deformation"

## Contrato antes del primer punto de una pista.
const BEFORE_FIRST_POINT_VALUE_M2: float = 0.0

## Tolerancia de conservacion de las sumas de area (relativa, en epsilons).
const AREA_SUM_EPSILONS: float = 8.0


## Comprueba un conjunto de pistas. Devuelve {valid, errors}.
static func validate_tracks(tracks: Array) -> Dictionary:
	var errors: Array[String] = []
	var seen: Dictionary = {}
	for track in tracks:
		if typeof(track) != TYPE_DICTIONARY:
			errors.append("each track must be a dictionary")
			continue
		var complete: bool = true
		for key in ["id", "location", "z_m", "points"]:
			if not track.has(key):
				errors.append("track is missing '%s'" % key)
				complete = false
		if not complete:
			continue
		var track_id: String = String(track["id"])
		var location: String = String(track["location"])
		if seen.has(track_id):
			errors.append("duplicate track id '%s'" % track_id)
		seen[track_id] = true
		if not LOCATIONS.has(location):
			errors.append("track '%s' has unknown location '%s'" % [track_id, location])
		elif not _id_matches_location(track_id, location):
			errors.append("track id '%s' does not match location '%s'" % [track_id, location])
		if not _is_finite(float(track["z_m"])):
			errors.append("track '%s' z_m must be finite" % track_id)
		if track.has("metadata") and typeof(track["metadata"]) != TYPE_DICTIONARY:
			errors.append("track '%s' metadata must be a dictionary" % track_id)
		_validate_points(track_id, track["points"], errors)
	return {"valid": errors.is_empty(), "errors": errors}


## Area adicional de una pista (ya validada) en `time_s`.
static func area_at(points: Array, time_s: float) -> float:
	var first_time: float = float(points[0][0])
	if time_s < first_time:
		return BEFORE_FIRST_POINT_VALUE_M2
	var last: Array = points[points.size() - 1]
	if time_s >= float(last[0]):
		return float(last[1])
	for index in range(points.size() - 1):
		var t0: float = float(points[index][0])
		var t1: float = float(points[index + 1][0])
		if time_s == t0:
			return float(points[index][1])
		if time_s < t1:
			var a0: float = float(points[index][1])
			var a1: float = float(points[index + 1][1])
			var weight: float = (time_s - t0) / (t1 - t0)
			return a0 + (a1 - a0) * weight
	return float(last[1])


## Evalua las pistas en `time_s`. Devuelve {valid, errors, time_s, segments,
## additional_ela_total_m2}. Incluye todas las pistas, tambien las de area 0.
static func evaluate_tracks(tracks: Array, time_s: float) -> Dictionary:
	var errors: Array[String] = []
	if not _is_finite(time_s):
		errors.append("time_s must be finite")
	var checked: Dictionary = validate_tracks(tracks)
	errors.append_array(checked["errors"])
	if not errors.is_empty():
		return {"valid": false, "errors": errors, "time_s": time_s, "segments": [], "additional_ela_total_m2": 0.0}

	var segments: Array = []
	for track in tracks:
		var metadata: Dictionary = {}
		if track.has("metadata"):
			metadata = Dictionary(track["metadata"]).duplicate(true)
		segments.append({
			"id": String(track["id"]),
			"location": String(track["location"]),
			"z_m": float(track["z_m"]),
			"area_m2": area_at(track["points"], time_s),
			"source": SOURCE_DEFORMATION,
			"track_id": String(track["id"]),
			"metadata": metadata,
		})
	segments.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return _segment_before(left, right))
	return {
		"valid": true,
		"errors": errors,
		"time_s": time_s,
		"segments": segments,
		"additional_ela_total_m2": _area_sum(segments),
	}


## Suma la fuga fria y los segmentos de deformacion ya evaluados.
##
## Devuelve {valid, errors, segments, cold_ela_total_m2,
## additional_ela_total_m2, combined_ela_total_m2}. Cada segmento lleva
## {id, z_m, area_m2, cold_area_m2, additional_area_m2, location,
## contributions}; ClosedDoorLeakageModel solo lee id, z_m y area_m2.
static func combine_with_cold(cold_segments: Array, deformation_segments: Array) -> Dictionary:
	var errors: Array[String] = []
	var combined: Dictionary = {}
	for segment in cold_segments:
		if not _segment_ok(segment, "cold", errors):
			continue
		var segment_id: String = String(segment["id"])
		if combined.has(segment_id):
			errors.append("duplicate cold segment id '%s'" % segment_id)
			continue
		var area: float = float(segment["area_m2"])
		combined[segment_id] = {
			"id": segment_id,
			"z_m": float(segment["z_m"]),
			"area_m2": area,
			"cold_area_m2": area,
			"additional_area_m2": 0.0,
			"location": _location_from_id(segment_id),
			"contributions": [{"source": SOURCE_COLD, "track_id": "", "area_m2": area}],
		}
	var cold_total: float = _area_sum(cold_segments) if errors.is_empty() else 0.0

	var seen_deformation: Dictionary = {}
	for segment in deformation_segments:
		if not _segment_ok(segment, "deformation", errors):
			continue
		var segment_id: String = String(segment["id"])
		if seen_deformation.has(segment_id):
			errors.append("duplicate deformation segment id '%s'" % segment_id)
			continue
		seen_deformation[segment_id] = true
		var area: float = float(segment["area_m2"])
		var contribution: Dictionary = {
			"source": SOURCE_DEFORMATION,
			"track_id": String(segment.get("track_id", segment_id)),
			"area_m2": area,
		}
		if combined.has(segment_id):
			var entry: Dictionary = combined[segment_id]
			if float(entry["z_m"]) != float(segment["z_m"]):
				errors.append("segment '%s' has cold height %s and deformation height %s" % [
					segment_id, entry["z_m"], segment["z_m"]])
				continue
			entry["area_m2"] = float(entry["area_m2"]) + area
			entry["additional_area_m2"] = area
			entry["contributions"].append(contribution)
		elif area > 0.0:
			combined[segment_id] = {
				"id": segment_id,
				"z_m": float(segment["z_m"]),
				"area_m2": area,
				"cold_area_m2": 0.0,
				"additional_area_m2": area,
				"location": String(segment.get("location", _location_from_id(segment_id))),
				"contributions": [contribution],
			}
	if not errors.is_empty():
		return _invalid_combination(errors)

	var segments: Array = combined.values()
	segments.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return _segment_before(left, right))
	return {
		"valid": true,
		"errors": errors,
		"segments": segments,
		"cold_ela_total_m2": cold_total,
		"additional_ela_total_m2": _area_sum(deformation_segments),
		"combined_ela_total_m2": _area_sum(segments),
	}


## Evalua las pistas en `time_s` y las suma a la fuga fria.
static func evaluate_and_combine(cold_segments: Array, tracks: Array, time_s: float) -> Dictionary:
	var evaluated: Dictionary = evaluate_tracks(tracks, time_s)
	if not bool(evaluated["valid"]):
		var failed: Dictionary = _invalid_combination(evaluated["errors"])
		failed["time_s"] = time_s
		return failed
	var result: Dictionary = combine_with_cold(cold_segments, evaluated["segments"])
	result["time_s"] = time_s
	return result


## Cota del centro de la banda `band` de `count` bandas iguales, la misma
## convencion que ClosedDoorLeakageModel.build_door_segments.
##
## Devuelve {valid, errors, z_m}. Precondiciones, todas comprobadas:
## `sill_z_m` finito, `door_height_m` finito y > 0, `count` >= 1 y
## 0 <= `band` < `count`. Si alguna falla, `valid` es false, `errors` dice por
## que y `z_m` es NAN: nunca se divide por cero ni se devuelve una cota fuera de
## la puerta. Con entradas validas, sill < z_m < sill + altura.
static func side_band_center(sill_z_m: float, door_height_m: float, band: int, count: int) -> Dictionary:
	var errors: Array[String] = []
	if not _is_finite(sill_z_m):
		errors.append("sill_z_m must be finite")
	if not _is_finite(door_height_m) or door_height_m <= 0.0:
		errors.append("door_height_m must be finite and > 0")
	if count < 1:
		errors.append("count must be >= 1 (got %d)" % count)
	elif band < 0 or band >= count:
		errors.append("band must be within [0, %d) (got %d)" % [count, band])
	if not errors.is_empty():
		return {"valid": false, "errors": errors, "z_m": NAN}
	return {
		"valid": true,
		"errors": errors,
		"z_m": sill_z_m + (float(band) + 0.5) * door_height_m / float(count),
	}


static func _validate_points(track_id: String, points: Variant, errors: Array[String]) -> void:
	if typeof(points) != TYPE_ARRAY or Array(points).is_empty():
		errors.append("track '%s' needs at least one point" % track_id)
		return
	var previous_time: float = -INF
	for point in points:
		if typeof(point) != TYPE_ARRAY or Array(point).size() != 2:
			errors.append("track '%s' points must be [time_s, additional_ela_m2]" % track_id)
			return
		var time_s: float = float(point[0])
		var area: float = float(point[1])
		if not _is_finite(time_s):
			errors.append("track '%s' has a non-finite time" % track_id)
			return
		if not _is_finite(area):
			errors.append("track '%s' has a non-finite area" % track_id)
			return
		if area < 0.0:
			errors.append("track '%s' has a negative area at %s s" % [track_id, time_s])
			return
		if time_s <= previous_time:
			errors.append("track '%s' times must be strictly increasing (%s after %s)" % [track_id, time_s, previous_time])
			return
		previous_time = time_s


static func _id_matches_location(track_id: String, location: String) -> bool:
	if location == LOCATION_BOTTOM or location == LOCATION_TOP:
		return track_id == location
	var prefix: String = location + "_"
	if not track_id.begins_with(prefix):
		return false
	return _is_two_ascii_digits(track_id.substr(prefix.length()))


## Exactamente dos caracteres, cada uno un digito ASCII '0'..'9' (codigos 48-57).
## Sin signos, espacios, decimales, letras ni digitos Unicode de otros sistemas.
static func _is_two_ascii_digits(suffix: String) -> bool:
	if suffix.length() != 2:
		return false
	for index in range(2):
		var code: int = suffix.unicode_at(index)
		if code < 48 or code > 57:
			return false
	return true


static func _location_from_id(segment_id: String) -> String:
	for location in [LOCATION_HINGE_SIDE, LOCATION_LATCH_SIDE]:
		if segment_id.begins_with(location + "_"):
			return location
	if segment_id == LOCATION_BOTTOM or segment_id == LOCATION_TOP:
		return segment_id
	if segment_id.begins_with("side_"):
		return "sides"
	return ""


static func _segment_ok(segment: Variant, label: String, errors: Array[String]) -> bool:
	if typeof(segment) != TYPE_DICTIONARY \
			or not segment.has("id") or not segment.has("z_m") or not segment.has("area_m2"):
		errors.append("each %s segment needs id, z_m and area_m2" % label)
		return false
	var z_m: float = float(segment["z_m"])
	var area: float = float(segment["area_m2"])
	if not _is_finite(z_m) or not _is_finite(area) or area < 0.0:
		errors.append("%s segment '%s' needs a finite height and a finite area >= 0" % [label, segment["id"]])
		return false
	return true


static func _area_sum(segments: Array) -> float:
	# Suma en orden canonico para que el total no dependa del orden de entrada.
	var ordered: Array = segments.duplicate()
	ordered.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return _segment_before(left, right))
	var total: float = 0.0
	for segment in ordered:
		total += float(segment["area_m2"])
	return total


static func _segment_before(left: Dictionary, right: Dictionary) -> bool:
	if float(left["z_m"]) != float(right["z_m"]):
		return float(left["z_m"]) < float(right["z_m"])
	return String(left["id"]) < String(right["id"])


static func _invalid_combination(errors: Array) -> Dictionary:
	return {
		"valid": false,
		"errors": errors,
		"segments": [],
		"cold_ela_total_m2": 0.0,
		"additional_ela_total_m2": 0.0,
		"combined_ela_total_m2": 0.0,
	}


static func _is_finite(value: float) -> bool:
	return not is_nan(value) and not is_inf(value)

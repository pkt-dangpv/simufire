extends RefCounted

## F2.2D2: integra la deformacion PRESCRITA de una puerta cerrada en el mismo
## elemento ELA y en el mismo residuo de Newton que la fuga fria de D1.
##
## Este adaptador no calcula caudal, no lee temperaturas, no modifica
## `open_fraction` ni `thermal_gap_fraction` y no conoce el editor. Evalua las
## pistas puras de `ClosedDoorDeformationModel`, traslada sus cotas locales a
## cotas absolutas y entrega los segmentos combinados al unico solver.
##
## D1 y D2 son capacidades independientes:
##   - D1 ON, D2 OFF: elemento frio historico, sin pasar por este adaptador;
##   - D1 ON, D2 ON: ELA fria + ELA adicional prescrita;
##   - D1 OFF, D2 ON: solo los huecos prescritos positivos;
##   - deformacion evaluada a cero: devuelve el elemento D1 intacto o nada.

const DeformationModel = preload("res://sim/core/ClosedDoorDeformationModel.gd")
const LeakageModel = preload("res://sim/core/ClosedDoorLeakageModel.gd")
const LeakageAdapter = preload("res://sim/core/ClosedDoorLeakageNetworkAdapter.gd")

const PROVENANCE_DEFORMATION: String = "prescribed_deformation"
const PROVENANCE_COMBINED: String = "cold_leakage+prescribed_deformation"


## Una pista de D2 solo pertenece a una puerta interior operativamente cerrada.
static func provides_deformation(opening, outside_id: int) -> bool:
	if opening == null:
		return false
	if int(opening.type) != OpeningModel.Type.DOOR:
		return false
	if int(opening.a) == outside_id or int(opening.b) == outside_id:
		return false
	if not opening.is_closed():
		return false
	return not Array(opening.deformation_tracks).is_empty()


## Validacion fail-closed antes de construir el snapshot. Las pistas pueden
## existir con D2 apagada sin cambiar nada; quien llama solo usa esta funcion
## cuando la capacidad esta activa.
static func validate_opening(opening, outside_id: int, time_s: float) -> Dictionary:
	var errors: Array[String] = []
	if not is_finite(time_s):
		errors.append("deformation time_s must be finite")
	if opening == null:
		errors.append("deformation opening must exist")
		return {"valid": false, "errors": errors}
	var tracks: Array = Array(opening.deformation_tracks)
	if tracks.is_empty():
		return {"valid": errors.is_empty(), "errors": errors}
	if int(opening.type) != OpeningModel.Type.DOOR:
		errors.append("deformation tracks require a door")
	if int(opening.a) == outside_id or int(opening.b) == outside_id:
		errors.append("door deformation currently requires two interior rooms")
	if not opening.is_closed():
		errors.append("door deformation requires an operationally closed door")
	var checked: Dictionary = DeformationModel.validate_tracks(tracks)
	errors.append_array(checked["errors"])
	return {"valid": errors.is_empty(), "errors": errors}


## Elemento combinado para el solver. Se llama solo con pistas validadas.
##
## `floor_z_m` es absoluto; los `z_m` de las pistas son locales al suelo de la
## puerta, igual que los segmentos frios del modelo puro antes del adaptador D1.
static func build_crack_element(
	opening,
	outside_id: int,
	floor_z_m: float,
	room_a_key: String,
	room_b_key: String,
	dt_s: float,
	time_s: float,
	include_cold_leakage: bool
) -> Dictionary:
	var cold_element: Dictionary = {}
	if include_cold_leakage:
		cold_element = LeakageAdapter.build_crack_element(
			opening, outside_id, floor_z_m, room_a_key, room_b_key, dt_s
		)
	var tracks: Array = Array(opening.deformation_tracks)
	if tracks.is_empty():
		return cold_element

	var evaluated: Dictionary = DeformationModel.evaluate_tracks(tracks, time_s)
	if not bool(evaluated["valid"]):
		return {}
	var deformation_segments: Array = []
	for raw_segment in evaluated["segments"]:
		var segment: Dictionary = Dictionary(raw_segment).duplicate(true)
		segment["z_m"] = floor_z_m + float(segment["z_m"])
		deformation_segments.append(segment)

	var cold_segments: Array = []
	if not cold_element.is_empty():
		for raw_segment in cold_element["crack_segments"]:
			var segment: Dictionary = raw_segment
			cold_segments.append({
				"id": String(segment["segment_id"]),
				"z_m": float(segment["z_m"]),
				"area_m2": float(segment["area_m2"]),
			})
	var combined: Dictionary = DeformationModel.combine_with_cold(
		cold_segments, deformation_segments
	)
	if not bool(combined["valid"]):
		return {}
	var additional_m2: float = float(combined["additional_ela_total_m2"])
	# Contrato fuerte de identidad: una historia evaluada a cero no reempaqueta
	# D1 ni cambia sus metadatos. Con D1 apagada tampoco crea un elemento nulo.
	if additional_m2 <= 0.0:
		return cold_element

	var segments: Array = []
	for raw_segment in combined["segments"]:
		var segment: Dictionary = raw_segment
		segments.append({
			"segment_id": String(segment["id"]),
			"z_m": float(segment["z_m"]),
			"area_m2": float(segment["area_m2"]),
			"cold_area_m2": float(segment["cold_area_m2"]),
			"additional_area_m2": float(segment["additional_area_m2"]),
		})
	if segments.is_empty():
		return {}
	var cold_m2: float = float(combined["cold_ela_total_m2"])
	var provenance: String = PROVENANCE_DEFORMATION
	if cold_m2 > 0.0:
		provenance = PROVENANCE_COMBINED
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
		"zero_pressure_regularization_pa": LeakageAdapter.DP_REGULARIZATION_PA,
		"pressure_domain_max_pa": LeakageAdapter.PRESSURE_DOMAIN_MAX_PA,
		"provenance": provenance,
		"leakage_class": String(opening.leakage_class),
		"leakage_area_override_m2": float(opening.leakage_area_override_m2),
		"resolved_ela_m2": cold_m2,
		"cold_ela_total_m2": cold_m2,
		"additional_ela_total_m2": additional_m2,
		"combined_ela_total_m2": float(combined["combined_ela_total_m2"]),
		"deformation_time_s": time_s,
		"dt_s": dt_s,
	}

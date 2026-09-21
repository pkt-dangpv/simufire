extends RefCounted

## F2.2D3: convierte el camino libre PRESCRITO de paños acristalados en
## aberturas grandes de la red autoritativa de presion.
##
## No calcula caudal, no lee temperatura, no usa aleatoriedad y no cambia
## `open_fraction`, `glass_broken` ni `thermal_gap_fraction`. La fase 3A decide
## el estado por hoja; la 3B calcula la interseccion geometrica exacta; este
## adaptador solo coloca los rectangulos resultantes dentro del hueco anfitrion.

const IntegrityModel = preload("res://sim/core/GlazingIntegrityModel.gd")
const GeometryModel = preload("res://sim/core/GlazingOpeningGeometryModel.gd")

const DISCHARGE_COEFFICIENT: float = 0.61
const PROVENANCE: String = "prescribed_glazing_fallout"


static func has_declaration(opening) -> bool:
	if opening == null:
		return false
	return not Array(opening.glazing_panels).is_empty() \
			or not Array(opening.glazing_spatial).is_empty()


## Devuelve {valid, errors, elements, panel_count, open_area_m2, time_s}.
## Las declaraciones se validan aunque la abertura operativa este abierta;
## en ese estado no se emiten elementos para evitar doble conteo.
static func build_opening_elements(
	opening,
	outside_id: int,
	floor_z_m: float,
	room_a_key: String,
	room_b_key: String,
	time_s: float
) -> Dictionary:
	var errors: Array[String] = []
	var output: Dictionary = {
		"valid": false,
		"errors": errors,
		"elements": [],
		"panel_count": 0,
		"open_area_m2": 0.0,
		"time_s": time_s,
	}
	if opening == null:
		errors.append("glazing opening must exist")
		return output
	if not is_finite(time_s) or time_s < 0.0:
		errors.append("glazing time_s must be finite and >= 0")
	if int(opening.type) == OpeningModel.Type.HOLE:
		errors.append("glazing panels require a door or window")
	var panels: Array = Array(opening.glazing_panels)
	var spatials: Array = Array(opening.glazing_spatial)
	if panels.is_empty() and spatials.is_empty():
		output["valid"] = errors.is_empty()
		return output
	if panels.is_empty():
		errors.append("glazing spatial input exists without panels")
		return output
	if spatials.is_empty():
		errors.append("glazing panels require spatial input")
		return output

	var evaluated: Dictionary = IntegrityModel.evaluate_panels(panels, time_s)
	if not bool(evaluated["valid"]):
		for error in evaluated["errors"]:
			errors.append("integrity: %s" % String(error))
		return output
	var spatial_by_id: Dictionary = _spatial_by_panel_id(spatials, time_s, errors)
	var panel_by_id: Dictionary = {}
	var placements: Array = []
	for raw_panel in panels:
		if typeof(raw_panel) != TYPE_DICTIONARY:
			continue
		var panel: Dictionary = raw_panel
		var panel_id: String = String(panel.get("id", ""))
		panel_by_id[panel_id] = panel
		if not panel.has("host_x_m") or not _finite_number(panel["host_x_m"]):
			errors.append("panel '%s' needs finite host_x_m" % panel_id)
			continue
		var x_m: float = float(panel["host_x_m"])
		var z_m: float = float(panel.get("sill_z_m", NAN))
		var width_m: float = float(panel.get("width_m", NAN))
		var height_m: float = float(panel.get("height_m", NAN))
		if x_m < 0.0 or z_m < 0.0 \
				or x_m + width_m > float(opening.width_m) \
				or z_m + height_m > float(opening.height_m):
			errors.append("panel '%s' lies outside the host opening" % panel_id)
		placements.append({
			"panel_id": panel_id,
			"x_m": x_m,
			"z_m": z_m,
			"width_m": width_m,
			"height_m": height_m,
		})
	_check_panel_overlap(placements, errors)
	for panel_id in spatial_by_id.keys():
		if not panel_by_id.has(panel_id):
			errors.append("spatial input names unknown panel '%s'" % panel_id)
	for panel_id in panel_by_id.keys():
		if not spatial_by_id.has(panel_id):
			errors.append("panel '%s' has no spatial input" % panel_id)
	if not errors.is_empty():
		return output

	output["panel_count"] = Array(evaluated["panels"]).size()
	var elements: Array = []
	var open_area_m2: float = 0.0
	var operationally_closed: bool = opening.is_closed()
	var evaluated_panels: Array = Array(evaluated["panels"])
	for panel_index in range(evaluated_panels.size()):
		var snapshot: Dictionary = evaluated_panels[panel_index]
		var panel_id: String = String(snapshot["panel"]["id"])
		var geometry: Dictionary = GeometryModel.compute_open_geometry(
			snapshot, spatial_by_id[panel_id]
		)
		if not bool(geometry["valid"]):
			for error in geometry["errors"]:
				errors.append("panel '%s' geometry: %s" % [panel_id, String(error)])
			continue
		var rectangles: Array = Array(geometry["rectangles"])
		for rectangle_index in range(rectangles.size()):
			var rectangle: Dictionary = rectangles[rectangle_index]
			var bottom_z_m: float = floor_z_m + float(opening.sill_m) \
					+ float(rectangle["global_sill_z_m"])
			var height_m: float = float(rectangle["height_m"])
			var area_m2: float = float(rectangle["area_m2"])
			open_area_m2 += area_m2
			# Una abertura operativamente abierta ya entra como vano completo. Toda
			# la cadena 3A->3B se valida, pero no se suma el vidrio otra vez.
			if not operationally_closed:
				continue
			elements.append({
				"opening_id": "glazing_%d_%03d_%03d" % [
					int(opening.opening_index), panel_index, rectangle_index
				],
				"room_a_id": room_a_key,
				"room_b_id": room_b_key,
				"flow_model": "large_opening",
				"bottom_z_m": bottom_z_m,
				"top_z_m": bottom_z_m + height_m,
				"width_m": float(rectangle["width_m"]),
				"open_fraction": 1.0,
				"discharge_coeff": DISCHARGE_COEFFICIENT,
				"provenance": PROVENANCE,
				"host_opening_index": int(opening.opening_index),
				"panel_id": panel_id,
				"rectangle_id": String(rectangle["id"]),
				"rectangle_area_m2": area_m2,
				"contributors": Array(rectangle["contributors"]).duplicate(true),
				"glazing_time_s": time_s,
			})
	output["errors"] = errors
	output["valid"] = errors.is_empty()
	output["elements"] = elements if errors.is_empty() else []
	output["open_area_m2"] = open_area_m2 if errors.is_empty() else 0.0
	return output


static func _spatial_by_panel_id(spatials: Array, time_s: float,
		errors: Array[String]) -> Dictionary:
	var by_id: Dictionary = {}
	for raw_spatial in spatials:
		if typeof(raw_spatial) != TYPE_DICTIONARY:
			errors.append("glazing spatial entries must be dictionaries")
			continue
		var spatial: Dictionary = raw_spatial
		if not spatial.has("panel_id"):
			errors.append("glazing spatial entry needs panel_id")
			continue
		var panel_id: String = String(spatial["panel_id"])
		if panel_id.strip_edges().is_empty():
			errors.append("glazing spatial panel_id must not be blank")
			continue
		if by_id.has(panel_id):
			errors.append("spatial input for panel '%s' is duplicated" % panel_id)
			continue
		if not spatial.has("snapshots") or typeof(spatial["snapshots"]) != TYPE_ARRAY \
				or Array(spatial["snapshots"]).is_empty():
			errors.append("spatial input for panel '%s' needs snapshots" % panel_id)
			continue
		var selected: Dictionary = {}
		var previous_time_s: float = -INF
		var snapshots: Array = Array(spatial["snapshots"])
		for index in range(snapshots.size()):
			var raw_snapshot: Variant = snapshots[index]
			if typeof(raw_snapshot) != TYPE_DICTIONARY:
				errors.append("panel '%s' spatial snapshots must be dictionaries" % panel_id)
				continue
			var snapshot: Dictionary = raw_snapshot
			if not snapshot.has("time_s") or not _finite_number(snapshot["time_s"]):
				errors.append("panel '%s' spatial snapshot needs finite time_s" % panel_id)
				continue
			var snapshot_time_s: float = float(snapshot["time_s"])
			if snapshot_time_s < 0.0 or snapshot_time_s <= previous_time_s:
				errors.append("panel '%s' spatial times must be >= 0 and strictly increasing" % panel_id)
			previous_time_s = snapshot_time_s
			if not snapshot.has("leaves") or typeof(snapshot["leaves"]) != TYPE_ARRAY:
				errors.append("panel '%s' spatial snapshot needs a leaves array" % panel_id)
				continue
			if snapshot_time_s <= time_s:
				selected = {
					"panel_id": panel_id,
					"leaves": Array(snapshot["leaves"]).duplicate(true),
				}
		if typeof(snapshots[0]) != TYPE_DICTIONARY \
				or not Dictionary(snapshots[0]).has("time_s") \
				or not _finite_number(Dictionary(snapshots[0])["time_s"]) \
				or float(Dictionary(snapshots[0])["time_s"]) != 0.0:
			errors.append("panel '%s' first spatial snapshot must start at 0 s" % panel_id)
		if selected.is_empty():
			errors.append("panel '%s' has no spatial snapshot at time %.9f" % [panel_id, time_s])
			continue
		by_id[panel_id] = selected
	return by_id


static func _check_panel_overlap(placements: Array, errors: Array[String]) -> void:
	for left_index in range(placements.size()):
		var left: Dictionary = placements[left_index]
		for right_index in range(left_index + 1, placements.size()):
			var right: Dictionary = placements[right_index]
			var overlap_x: bool = float(left["x_m"]) \
					< float(right["x_m"]) + float(right["width_m"]) \
					and float(right["x_m"]) \
					< float(left["x_m"]) + float(left["width_m"])
			var overlap_z: bool = float(left["z_m"]) \
					< float(right["z_m"]) + float(right["height_m"]) \
					and float(right["z_m"]) \
					< float(left["z_m"]) + float(left["height_m"])
			if overlap_x and overlap_z:
				errors.append("panels '%s' and '%s' overlap in the host opening" % [
					String(left["panel_id"]), String(right["panel_id"])
				])


static func _finite_number(value: Variant) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	return is_finite(float(value))

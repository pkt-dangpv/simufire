extends RefCounted
class_name Phase3ZoneMassSystem

# F3.0: transaccion two-zone en sombra. Este componente nunca escribe RoomModel.

const ZONE_UPPER: String = "upper"
const ZONE_LOWER: String = "lower"
const EXTERIOR_ID: int = -1
const AIR_PRESSURE_REF_PA: float = 101325.0
const AIR_DENSITY_REF_KG_M3: float = 1.2
const AIR_CP_KJ_KG_K: float = 1.0
const EXTERIOR_DISCHARGE_COEFF: float = 0.61
const THERMO_MASS_EPS_KG: float = 1.0e-12
const THERMO_ENERGY_EPS_KJ: float = 1.0e-12
const TRANSIT_SPECIES: Array[String] = ["co", "co2", "hcn"]
const PARCEL_SPECIES: Array[String] = [
	"smoke", "co", "co2", "hcn", "hcl", "acrolein", "formaldehyde"
]
const SEMANTIC_QUANTITY_BITS: Dictionary = {
	"gas_mass": 1,
	"enthalpy": 2,
	"o2": 4,
	"co": 8,
	"co2": 16,
	"hcn": 32,
	"smoke": 64,
	"hcl": 128,
	"acrolein": 256,
	"formaldehyde": 512,
}

var _snapshots: Dictionary = {}
var _requests: Array[Dictionary] = []
var _transactions: Array[Dictionary] = []
var _request_ids: Dictionary = {}
var _atomic_bundles: Array[Dictionary] = []
var _atomic_bundle_ids: Dictionary = {}
var _duplicate_owner_count: int = 0
var _results: Dictionary = {}
var _species_transit_reservoir: Dictionary = {}
var _species_transit_created_kg: Dictionary = {}
var _species_transit_delivered_kg: Dictionary = {}
var _species_transit_refunded_kg: Dictionary = {}
var _species_transit_cancelled_kg: Dictionary = {}
var _species_transit_orphan_delivery_count: int = 0
var _species_transit_duplicate_id_count: int = 0
var _species_transit_negative_balance_count: int = 0
var _parcel_atomic_created_payload: Dictionary = {}
var _parcel_atomic_delivered_payload: Dictionary = {}
var _parcel_atomic_refunded_payload: Dictionary = {}
var _parcel_atomic_cancelled_payload: Dictionary = {}
var _parcel_atomic_unfinalized_resolution_count: int = 0
var _immediate_background_species_kg: Dictionary = {}
var _immediate_counterflow_species_kg: Dictionary = {}
var _vertical_net_species_kg: Dictionary = {}
var _vertical_directed_species_kg: Dictionary = {}
var _immediate_transfer_count: int = 0
var _immediate_rejected_kg_total: float = 0.0
var _immediate_debited_species_kg_step: Dictionary = {}
var _immediate_credited_species_kg_step: Dictionary = {}
var _vertical_transfer_count: int = 0
var _vertical_rejected_kg_total: float = 0.0
var _vertical_opposed_zone_direction_count: int = 0
var _vertical_debited_species_kg_step: Dictionary = {}
var _vertical_credited_species_kg_step: Dictionary = {}
var _exterior_purge_requested_species_kg: Dictionary = {}
var _exterior_purge_upper_species_kg: Dictionary = {}
var _exterior_purge_applied_species_kg: Dictionary = {}
var _exterior_purge_rejected_species_kg: Dictionary = {}
var _exterior_purge_mechanism_species_kg: Dictionary = {}
var _exterior_purge_event_ids: Dictionary = {}
var _exterior_purge_event_count: int = 0
var _exterior_purge_duplicate_event_count: int = 0
var _thermal_species_requested_kg: Dictionary = {}
var _thermal_species_source_upper_kg: Dictionary = {}
var _thermal_species_destination_upper_kg: Dictionary = {}
var _thermal_species_applied_kg: Dictionary = {}
var _thermal_species_rejected_kg: Dictionary = {}
var _thermal_species_semantic_suppressed_kg: Dictionary = {}
var _thermal_species_mechanism_kg: Dictionary = {}
var _thermal_species_event_ids: Dictionary = {}
var _thermal_species_event_count: int = 0
var _thermal_species_duplicate_event_count: int = 0
var _semantic_claims: Dictionary = {}
var _semantic_claim_count: int = 0
var _semantic_unknown_connection_count: int = 0
var _semantic_accepted_claim_count: int = 0
var _semantic_suppressed_claim_count: int = 0
var _semantic_unresolved_claim_count: int = 0
var _semantic_suppressed_quantity_mask: int = 0
var _semantic_unresolved_quantity_mask: int = 0
var _semantic_suppressed_amounts: Dictionary = {}
var _semantic_unresolved_amounts: Dictionary = {}
var _semantic_unresolved_keys: Dictionary = {}
var _co_oxidation_event_ids: Dictionary = {}
var _co_oxidation_co_sink_kg: float = 0.0
var _co_oxidation_co2_source_kg: float = 0.0
var _co_oxidation_carbon_residual_kg: float = 0.0
var _co_oxidation_o2_sink_kg: float = 0.0
var _co_oxidation_accepted_fraction: float = 1.0
var _co_oxidation_accepted_co_sink_kg: float = 0.0
var _co_oxidation_accepted_co2_source_kg: float = 0.0
var _co_oxidation_accepted_o2_sink_kg: float = 0.0
var _co_oxidation_o2_rejected_kg: float = 0.0
var _co_oxidation_oxygen_residual_kg: float = 0.0
var _co_oxidation_legacy_lower_co2_kg: float = 0.0
var _atomic_bundle_count: int = 0
var _atomic_route_count: int = 0
var _atomic_min_accepted_fraction: float = 1.0
var _atomic_rejected_mass_kg: float = 0.0
var _atomic_rejected_energy_kj: float = 0.0
var _atomic_rejected_o2_kg: float = 0.0
var _atomic_rejected_species_kg: float = 0.0
var _atomic_duplicate_bundle_count: int = 0
var _atomic_invalid_bundle_count: int = 0
var _canonical_exterior_boundary_by_room: Dictionary = {}
var _canonical_exterior_boundary_context: Dictionary = {}


func reset() -> void:
	_reset_step_state()
	_species_transit_reservoir.clear()
	_species_transit_created_kg.clear()
	_species_transit_delivered_kg.clear()
	_species_transit_refunded_kg.clear()
	_species_transit_cancelled_kg.clear()
	_species_transit_orphan_delivery_count = 0
	_species_transit_duplicate_id_count = 0
	_species_transit_negative_balance_count = 0
	_parcel_atomic_created_payload.clear()
	_parcel_atomic_delivered_payload.clear()
	_parcel_atomic_refunded_payload.clear()
	_parcel_atomic_cancelled_payload.clear()
	_parcel_atomic_unfinalized_resolution_count = 0
	_immediate_background_species_kg.clear()
	_immediate_counterflow_species_kg.clear()
	_vertical_net_species_kg.clear()
	_vertical_directed_species_kg.clear()
	_immediate_transfer_count = 0
	_immediate_rejected_kg_total = 0.0
	_vertical_transfer_count = 0
	_vertical_rejected_kg_total = 0.0
	_vertical_opposed_zone_direction_count = 0
	_exterior_purge_requested_species_kg.clear()
	_exterior_purge_upper_species_kg.clear()
	_exterior_purge_applied_species_kg.clear()
	_exterior_purge_rejected_species_kg.clear()
	_exterior_purge_mechanism_species_kg.clear()
	_exterior_purge_event_count = 0
	_exterior_purge_duplicate_event_count = 0
	_thermal_species_requested_kg.clear()
	_thermal_species_source_upper_kg.clear()
	_thermal_species_destination_upper_kg.clear()
	_thermal_species_applied_kg.clear()
	_thermal_species_rejected_kg.clear()
	_thermal_species_semantic_suppressed_kg.clear()
	_thermal_species_mechanism_kg.clear()
	_thermal_species_event_count = 0
	_thermal_species_duplicate_event_count = 0


func _reset_step_state() -> void:
	_snapshots.clear()
	_requests.clear()
	_transactions.clear()
	_request_ids.clear()
	_atomic_bundles.clear()
	_atomic_bundle_ids.clear()
	_duplicate_owner_count = 0
	_results.clear()
	_immediate_debited_species_kg_step.clear()
	_immediate_credited_species_kg_step.clear()
	_vertical_debited_species_kg_step.clear()
	_vertical_credited_species_kg_step.clear()
	_exterior_purge_event_ids.clear()
	_thermal_species_event_ids.clear()
	_semantic_claims.clear()
	_semantic_claim_count = 0
	_semantic_unknown_connection_count = 0
	_semantic_accepted_claim_count = 0
	_semantic_suppressed_claim_count = 0
	_semantic_unresolved_claim_count = 0
	_semantic_suppressed_quantity_mask = 0
	_semantic_unresolved_quantity_mask = 0
	_semantic_suppressed_amounts.clear()
	_semantic_unresolved_amounts.clear()
	_semantic_unresolved_keys.clear()
	_co_oxidation_event_ids.clear()
	_co_oxidation_co_sink_kg = 0.0
	_co_oxidation_co2_source_kg = 0.0
	_co_oxidation_carbon_residual_kg = 0.0
	_co_oxidation_o2_sink_kg = 0.0
	_co_oxidation_accepted_fraction = 1.0
	_co_oxidation_accepted_co_sink_kg = 0.0
	_co_oxidation_accepted_co2_source_kg = 0.0
	_co_oxidation_accepted_o2_sink_kg = 0.0
	_co_oxidation_o2_rejected_kg = 0.0
	_co_oxidation_oxygen_residual_kg = 0.0
	_co_oxidation_legacy_lower_co2_kg = 0.0
	_atomic_bundle_count = 0
	_atomic_route_count = 0
	_atomic_min_accepted_fraction = 1.0
	_atomic_rejected_mass_kg = 0.0
	_atomic_rejected_energy_kj = 0.0
	_atomic_rejected_o2_kg = 0.0
	_atomic_rejected_species_kg = 0.0
	_atomic_duplicate_bundle_count = 0
	_atomic_invalid_bundle_count = 0
	_canonical_exterior_boundary_by_room.clear()
	_canonical_exterior_boundary_context.clear()


func begin_step(building) -> void:
	_reset_step_state()
	if building == null:
		return
	for room_id in building.get_rooms().keys():
		var room: RoomModel = building.get_room(room_id)
		if room == null:
			continue
		_snapshots[str(room_id)] = _snapshot_room(room)


## F3.1e: cierre termodinamico puro. Masa y energia son entradas autoritativas;
## solo se derivan temperatura, presion, volumenes e interfaz.
func derive_canonical_thermodynamic_state(
		upper_gas_kg: float,
		lower_gas_kg: float,
		upper_energy_kj: float,
		lower_energy_kj: float,
		room_volume_m3: float,
		floor_area_m2: float,
		room_height_m: float,
		reference_temp_c: float
	) -> Dictionary:
	var result: Dictionary = {
		"valid": false,
		"failure_code": 0.0,
		"temp_upper_c": reference_temp_c,
		"temp_lower_c": reference_temp_c,
		"pressure_abs_pa": 0.0,
		"pressure_gauge_pa": -AIR_PRESSURE_REF_PA,
		"upper_volume_m3": 0.0,
		"lower_volume_m3": 0.0,
		"volume_closure_error_m3": -room_volume_m3,
		"interface_m": 0.0,
		"mass_invariance_residual_kg": 0.0,
		"energy_invariance_residual_kj": 0.0,
		"canonical_transaction_closure_flag": 0.0,
	}
	for value in [
		upper_gas_kg, lower_gas_kg, upper_energy_kj, lower_energy_kj,
		room_volume_m3, floor_area_m2, room_height_m, reference_temp_c
	]:
		if not is_finite(float(value)):
			result["failure_code"] = 1.0
			return result
	if upper_gas_kg < 0.0 or lower_gas_kg < 0.0 \
			or upper_energy_kj < 0.0 or lower_energy_kj < 0.0:
		result["failure_code"] = 2.0
		return result
	var reference_temp_k: float = reference_temp_c + 273.15
	if room_volume_m3 <= 0.0 or floor_area_m2 <= 0.0 \
			or room_height_m <= 0.0 or reference_temp_k <= 0.0:
		result["failure_code"] = 3.0
		return result
	if (upper_gas_kg <= THERMO_MASS_EPS_KG and upper_energy_kj > THERMO_ENERGY_EPS_KJ) \
			or (lower_gas_kg <= THERMO_MASS_EPS_KG and lower_energy_kj > THERMO_ENERGY_EPS_KJ):
		result["failure_code"] = 4.0
		return result
	if upper_gas_kg + lower_gas_kg <= THERMO_MASS_EPS_KG:
		result["failure_code"] = 5.0
		return result

	var upper_temp_k: float = reference_temp_k
	if upper_gas_kg > THERMO_MASS_EPS_KG:
		upper_temp_k += upper_energy_kj / (upper_gas_kg * AIR_CP_KJ_KG_K)
	var lower_temp_k: float = reference_temp_k
	if lower_gas_kg > THERMO_MASS_EPS_KG:
		lower_temp_k += lower_energy_kj / (lower_gas_kg * AIR_CP_KJ_KG_K)
	var gas_constant_model: float = AIR_PRESSURE_REF_PA \
			/ (AIR_DENSITY_REF_KG_M3 * reference_temp_k)
	var pressure_abs_pa: float = gas_constant_model * (
		upper_gas_kg * upper_temp_k + lower_gas_kg * lower_temp_k
	) / room_volume_m3
	if not is_finite(pressure_abs_pa) or pressure_abs_pa <= 0.0:
		result["failure_code"] = 6.0
		return result

	var upper_volume_m3: float = upper_gas_kg * gas_constant_model \
			* upper_temp_k / pressure_abs_pa
	var lower_volume_m3: float = lower_gas_kg * gas_constant_model \
			* lower_temp_k / pressure_abs_pa
	var volume_closure_error_m3: float = upper_volume_m3 + lower_volume_m3 \
			- room_volume_m3
	var interface_m: float = clampf(lower_volume_m3 / floor_area_m2, 0.0, room_height_m)
	var closure_ok: bool = absf(volume_closure_error_m3) <= 1.0e-9

	result["valid"] = true
	result["temp_upper_c"] = upper_temp_k - 273.15
	result["temp_lower_c"] = lower_temp_k - 273.15
	result["pressure_abs_pa"] = pressure_abs_pa
	result["pressure_gauge_pa"] = pressure_abs_pa - AIR_PRESSURE_REF_PA
	result["upper_volume_m3"] = upper_volume_m3
	result["lower_volume_m3"] = lower_volume_m3
	result["volume_closure_error_m3"] = volume_closure_error_m3
	result["interface_m"] = interface_m
	result["canonical_transaction_closure_flag"] = 1.0 if closure_ok else 0.0
	return result


## F3.2a: registra el contrato exterior del paso. El bundle se resuelve solo
## en finalize_step, despues de los fluxes internos, y nunca escribe legacy.
func queue_canonical_exterior_boundary_requests(
		building,
		dt: float,
		reference_temp_c: float,
		outside_o2: float,
		closed_leakage_area_m2: float,
		pressure_threshold_pa: float,
		discharge_coeff: float = EXTERIOR_DISCHARGE_COEFF
	) -> void:
	if building == null or dt <= 0.0 or discharge_coeff <= 0.0:
		return
	_canonical_exterior_boundary_context = {
		"dt": dt,
		"reference_temp_c": reference_temp_c,
		"outside_o2": outside_o2,
		"closed_leakage_area_m2": closed_leakage_area_m2,
		"pressure_threshold_pa": pressure_threshold_pa,
		"discharge_coeff": discharge_coeff,
	}


## Resuelve la frontera despues de las transacciones internas del paso. Sigue
## siendo no circular: parte del snapshot pre-step mas fluxes shadow explicitos.
func _apply_canonical_exterior_boundary_requests(
		shadow: Dictionary,
		building,
		dt: float,
		reference_temp_c: float,
		outside_o2: float,
		closed_leakage_area_m2: float,
		pressure_threshold_pa: float,
		discharge_coeff: float,
		rejected_by_room: Dictionary,
		rejected_doorway_species_by_room: Dictionary,
		rejected_transit_species_by_room: Dictionary
	) -> void:
	for raw_room_id in building.get_rooms().keys():
		var room_id: int = int(raw_room_id)
		var room = building.get_room(room_id)
		var room_key: String = str(room_id)
		if room == null or not shadow.has(room_key):
			continue
		var state: Dictionary = shadow[room_key]
		var thermo: Dictionary = derive_canonical_thermodynamic_state(
			float(state.get("upper_gas_kg", 0.0)),
			float(state.get("lower_gas_kg", 0.0)),
			float(state.get("upper_energy_kj", 0.0)),
			float(state.get("lower_energy_kj", 0.0)),
			room.volume_m3(),
			room.floor_area_m2(),
			room.height_m,
			reference_temp_c
		)
		var record: Dictionary = _canonical_exterior_boundary_by_room.get(
			room_key, _new_canonical_exterior_boundary_record()
		)
		record["pressure_pre_pa"] = float(thermo.get("pressure_gauge_pa", 0.0))
		_canonical_exterior_boundary_by_room[room_key] = record
		if not bool(thermo.get("valid", false)):
			continue
		var pressure_gauge_pa: float = float(thermo.get("pressure_gauge_pa", 0.0))
		if absf(pressure_gauge_pa) < maxf(0.0, pressure_threshold_pa):
			continue
		var area_by_zone: Dictionary = _canonical_exterior_area_by_zone(
			building,
			room_id,
			float(thermo.get("interface_m", room.height_m)),
			room.height_m,
			closed_leakage_area_m2
		)
		if float(area_by_zone.get(ZONE_UPPER, 0.0)) \
				+ float(area_by_zone.get(ZONE_LOWER, 0.0)) <= 0.0:
			continue

		var routes: Array = []
		var requested_totals: Dictionary = {
			"gas_mass_kg": 0.0,
			"sensible_enthalpy_kj": 0.0,
			"o2_kg": 0.0,
			"species_kg": 0.0,
		}
		var outflow: bool = pressure_gauge_pa > 0.0
		var active_zone_count: int = 0
		var source_zone_code: int = 0
		for zone_name in [ZONE_UPPER, ZONE_LOWER]:
			var area_m2: float = maxf(0.0, float(area_by_zone.get(zone_name, 0.0)))
			if area_m2 <= 0.0:
				continue
			var zone_volume_m3: float = float(
				thermo.get(zone_name + "_volume_m3", 0.0)
			)
			var zone_mass_kg: float = float(state.get(zone_name + "_gas_kg", 0.0))
			var density_kg_m3: float = AIR_DENSITY_REF_KG_M3
			if outflow:
				if zone_mass_kg <= THERMO_MASS_EPS_KG or zone_volume_m3 <= 1.0e-12:
					continue
				density_kg_m3 = zone_mass_kg / zone_volume_m3
			var requested_mass_kg: float = discharge_coeff * area_m2 \
					* sqrt(2.0 * absf(pressure_gauge_pa) * maxf(0.05, density_kg_m3)) \
					* dt
			if requested_mass_kg <= 0.0 or not is_finite(requested_mass_kg):
				continue
			var energy_kj: float = 0.0
			var o2_kg: float = requested_mass_kg * clampf(outside_o2, 0.0, 1.0)
			var species_kg: Dictionary = _parcel_species({})
			var source_room_id: int = EXTERIOR_ID
			var destination_room_id: int = room_id
			if outflow:
				var inventory_fraction: float = requested_mass_kg / zone_mass_kg
				energy_kj = float(state.get(zone_name + "_energy_kj", 0.0)) \
						* inventory_fraction
				o2_kg = float(state.get(zone_name + "_o2_kg", 0.0)) \
						* inventory_fraction
				var source_species: Dictionary = state.get(zone_name + "_species_kg", {})
				for species_name in PARCEL_SPECIES:
					species_kg[species_name] = float(
						source_species.get(species_name, 0.0)
					) * inventory_fraction
				source_room_id = room_id
				destination_room_id = EXTERIOR_ID
				active_zone_count += 1
				source_zone_code = 1 if zone_name == ZONE_UPPER else 2
			var route: Dictionary = make_atomic_route(
				"f32a_exterior:%d:%s" % [room_id, zone_name],
				"canonical_exterior_pressure",
				source_room_id,
				destination_room_id,
				zone_name,
				zone_name,
				requested_mass_kg,
				energy_kj,
				o2_kg,
				species_kg
			)
			routes.append(route)
			requested_totals["gas_mass_kg"] = float(
				requested_totals.get("gas_mass_kg", 0.0)
			) + requested_mass_kg
			requested_totals["sensible_enthalpy_kj"] = float(
				requested_totals.get("sensible_enthalpy_kj", 0.0)
			) + energy_kj
			requested_totals["o2_kg"] = float(
				requested_totals.get("o2_kg", 0.0)
			) + o2_kg
			requested_totals["species_kg"] = float(
				requested_totals.get("species_kg", 0.0)
			) + _sum_parcel_species(species_kg)
		if routes.is_empty():
			continue
		if outflow and active_zone_count > 1:
			source_zone_code = 3
		record["direction"] = 1.0 if outflow else -1.0
		record["source_zone_code"] = float(source_zone_code)
		record["event_count"] = 1.0
		record["requested_gas_kg"] = float(requested_totals["gas_mass_kg"])
		record["requested_energy_kj"] = float(requested_totals["sensible_enthalpy_kj"])
		record["requested_o2_kg"] = float(requested_totals["o2_kg"])
		record["requested_species_kg"] = float(requested_totals["species_kg"])
		_canonical_exterior_boundary_by_room[room_key] = record
		var bundle: Dictionary = make_atomic_bundle(
			"f32a_exterior:%d" % room_id,
			"canonical_exterior_pressure",
			routes,
			{
				"kind": "canonical_exterior_boundary",
				"room_id": room_id,
				"requested_totals": requested_totals,
			}
		)
		if not add_atomic_bundle(bundle):
			record["duplicate_owner_flag"] = 1.0
			_canonical_exterior_boundary_by_room[room_key] = record
		else:
			_apply_atomic_bundle(
				shadow,
				bundle,
				rejected_by_room,
				rejected_doorway_species_by_room,
				rejected_transit_species_by_room
			)


func suppress_legacy_pressure_purge_event(event: Dictionary) -> bool:
	if String(event.get("mechanism", "")) != "pressure_venting":
		return false
	var room_key: String = str(int(event.get("source_room_id", EXTERIOR_ID)))
	var record: Dictionary = _canonical_exterior_boundary_by_room.get(
		room_key, _new_canonical_exterior_boundary_record()
	)
	record["legacy_pressure_suppressed_event_count"] = float(
		record.get("legacy_pressure_suppressed_event_count", 0.0)
	) + 1.0
	_canonical_exterior_boundary_by_room[room_key] = record
	return true


func _canonical_exterior_area_by_zone(
		building,
		room_id: int,
		interface_m: float,
		room_height_m: float,
		closed_leakage_area_m2: float
	) -> Dictionary:
	var areas: Dictionary = {ZONE_UPPER: 0.0, ZONE_LOWER: 0.0}
	for op in building.get_openings():
		if op == null or not op.is_exterior_opening():
			continue
		if op.a != room_id and op.b != room_id:
			continue
		var bottom_m: float = clampf(op.sill_m, 0.0, room_height_m)
		var top_m: float = clampf(op.lintel_height_m(), bottom_m, room_height_m)
		var span_m: float = top_m - bottom_m
		if span_m <= 1.0e-9:
			continue
		var smooth_fraction: float = op.open_fraction_smooth
		if smooth_fraction < 0.0:
			smooth_fraction = op.open_fraction
		var area_m2: float = maxf(0.0, op.width_m * op.height_m) \
				* clampf(smooth_fraction, 0.0, 1.0)
		if area_m2 <= 1.0e-12:
			area_m2 = maxf(0.0, closed_leakage_area_m2)
		if area_m2 <= 0.0:
			continue
		var lower_span_m: float = maxf(
			0.0, minf(top_m, interface_m) - bottom_m
		)
		var upper_span_m: float = maxf(
			0.0, top_m - maxf(bottom_m, interface_m)
		)
		areas[ZONE_LOWER] = float(areas[ZONE_LOWER]) \
				+ area_m2 * lower_span_m / span_m
		areas[ZONE_UPPER] = float(areas[ZONE_UPPER]) \
				+ area_m2 * upper_span_m / span_m
	return areas


func _new_canonical_exterior_boundary_record() -> Dictionary:
	return {
		"pressure_pre_pa": 0.0,
		"requested_gas_kg": 0.0,
		"requested_energy_kj": 0.0,
		"requested_o2_kg": 0.0,
		"requested_species_kg": 0.0,
		"accepted_gas_kg": 0.0,
		"accepted_energy_kj": 0.0,
		"accepted_o2_kg": 0.0,
		"accepted_species_kg": 0.0,
		"rejected_gas_kg": 0.0,
		"rejected_energy_kj": 0.0,
		"rejected_o2_kg": 0.0,
		"rejected_species_kg": 0.0,
		"direction": 0.0,
		"source_zone_code": 0.0,
		"event_count": 0.0,
		"legacy_pressure_suppressed_event_count": 0.0,
		"accepted_fraction": 1.0,
		"duplicate_owner_flag": 0.0,
		"mass_residual_kg": 0.0,
		"energy_residual_kj": 0.0,
		"o2_residual_kg": 0.0,
		"species_residual_kg": 0.0,
	}


func apply_species_transit_event(event: Dictionary) -> void:
	var event_name: String = String(event.get("event", ""))
	var parcel_id: String = String(event.get("parcel_id", ""))
	if parcel_id.is_empty():
		_species_transit_orphan_delivery_count += 1
		return
	match event_name:
		"created":
			if _species_transit_reservoir.has(parcel_id):
				_species_transit_duplicate_id_count += 1
				return
			var created_species: Dictionary = _parcel_species(event.get("species_kg", {}))
			var created_upper_species: Dictionary = _bounded_upper_parcel_species(
				event.get("upper_species_kg", {}), created_species
			)
			var stored: Dictionary = {
				"source_room_id": int(event.get("source_room_id", EXTERIOR_ID)),
				"destination_room_id": int(event.get("destination_room_id", EXTERIOR_ID)),
				"connection_id": String(event.get("connection_id", "")),
				"gas_mass_kg": maxf(0.0, float(event.get("gas_mass_kg", 0.0))),
				"sensible_enthalpy_kj": maxf(
					0.0, float(event.get("sensible_enthalpy_kj", 0.0))
				),
				"o2_kg": float(event.get("o2_kg", 0.0)),
				"species_kg": created_species.duplicate(true),
				"upper_species_kg": created_upper_species.duplicate(true),
				"accepted_fraction": -1.0,
			}
			_species_transit_reservoir[parcel_id] = stored
			_add_parcel_species(_species_transit_created_kg, created_species)
			_register_split_parcel_species_claims(
				event,
				"GasExchangeSystem",
				"delayed_parcel",
				"interior_opening",
				created_species,
				created_upper_species
			)
			_register_parcel_quantity_claims(event)
			_add_parcel_carve_bundle(parcel_id, stored)
		"resolved":
			var delivered_species: Dictionary = _parcel_species(
				event.get("delivered_species_kg", {})
			)
			var refunded_species: Dictionary = _parcel_species(
				event.get("refunded_species_kg", {})
			)
			var delivered_upper_species: Dictionary = _bounded_upper_parcel_species(
				event.get("delivered_upper_species_kg", {}), delivered_species
			)
			var refunded_upper_species: Dictionary = _bounded_upper_parcel_species(
				event.get("refunded_upper_species_kg", {}), refunded_species
			)
			if not _species_transit_reservoir.has(parcel_id):
				_species_transit_orphan_delivery_count += 1
				return
			var resolved_stored: Dictionary = _species_transit_reservoir[parcel_id]
			var accepted_fraction: float = float(
				resolved_stored.get("accepted_fraction", -1.0)
			)
			if accepted_fraction < 0.0:
				_parcel_atomic_unfinalized_resolution_count += 1
				_species_transit_reservoir.erase(parcel_id)
				return
			var stored_species: Dictionary = resolved_stored.get("species_kg", {})
			for species_name in PARCEL_SPECIES:
				var resolved_kg: float = float(delivered_species.get(species_name, 0.0)) \
						+ float(refunded_species.get(species_name, 0.0))
				if absf(
					resolved_kg - float(stored_species.get(species_name, 0.0))
				) > 1.0e-9:
					_species_transit_negative_balance_count += 1
			_add_parcel_species(_species_transit_delivered_kg, delivered_species)
			_add_parcel_species(_species_transit_refunded_kg, refunded_species)
			_add_parcel_resolution_bundle(
				parcel_id,
				resolved_stored,
				delivered_species,
				delivered_upper_species,
				refunded_species,
				refunded_upper_species,
				false
			)
			_species_transit_reservoir.erase(parcel_id)
		"cancelled":
			var cancelled_species: Dictionary = _parcel_species(event.get("species_kg", {}))
			if not _species_transit_reservoir.has(parcel_id):
				_species_transit_orphan_delivery_count += 1
				return
			var stored_cancelled: Dictionary = _species_transit_reservoir[parcel_id]
			var cancelled_fraction: float = float(
				stored_cancelled.get("accepted_fraction", -1.0)
			)
			if cancelled_fraction < 0.0:
				_parcel_atomic_unfinalized_resolution_count += 1
				_species_transit_reservoir.erase(parcel_id)
				return
			var stored_cancelled_species: Dictionary = stored_cancelled.get("species_kg", {})
			for species_name in PARCEL_SPECIES:
				if absf(
					float(cancelled_species.get(species_name, 0.0))
							- float(stored_cancelled_species.get(species_name, 0.0))
				) > 1.0e-9:
					_species_transit_negative_balance_count += 1
			_add_parcel_species(_species_transit_cancelled_kg, cancelled_species)
			_add_parcel_resolution_bundle(
				parcel_id,
				stored_cancelled,
				{},
				{},
				cancelled_species,
				_bounded_upper_parcel_species(
					event.get("upper_species_kg", {}), cancelled_species
				),
				true
			)
			_species_transit_reservoir.erase(parcel_id)
		_:
			_species_transit_orphan_delivery_count += 1


func _register_parcel_quantity_claims(event: Dictionary) -> void:
	var source_room_id: int = int(event.get("source_room_id", EXTERIOR_ID))
	var destination_room_id: int = int(event.get("destination_room_id", EXTERIOR_ID))
	for quantity in ["gas_mass", "enthalpy"]:
		var amount: float = maxf(
			0.0,
			float(event.get(
				"gas_mass_kg" if quantity == "gas_mass" else "sensible_enthalpy_kj",
				0.0
			))
		)
		register_semantic_claim({
			"connection_id": String(event.get("connection_id", "")),
			"producer": "GasExchangeSystem",
			"transport_family": "delayed_parcel",
			"boundary_kind": "interior_opening",
			"source_room_id": source_room_id,
			"destination_room_id": destination_room_id,
			"source_zone": ZONE_UPPER,
			"destination_zone": ZONE_UPPER,
			"quantity": quantity,
			"amount": amount,
		})
	var signed_o2_kg: float = float(event.get("o2_kg", 0.0))
	register_semantic_claim({
		"connection_id": String(event.get("connection_id", "")),
		"producer": "GasExchangeSystem",
		"transport_family": "delayed_parcel",
		"boundary_kind": "interior_opening",
		"source_room_id": source_room_id if signed_o2_kg >= 0.0 else destination_room_id,
		"destination_room_id": destination_room_id if signed_o2_kg >= 0.0 else source_room_id,
		"source_zone": ZONE_UPPER,
		"destination_zone": ZONE_UPPER,
		"quantity": "o2",
		"amount": absf(signed_o2_kg),
	})


func _add_parcel_carve_bundle(parcel_id: String, stored: Dictionary) -> void:
	var source_room_id: int = int(stored.get("source_room_id", EXTERIOR_ID))
	var destination_room_id: int = int(stored.get("destination_room_id", EXTERIOR_ID))
	var upper_species: Dictionary = _bounded_upper_parcel_species(
		stored.get("upper_species_kg", {}), stored.get("species_kg", {})
	)
	var lower_species: Dictionary = _lower_parcel_species(
		stored.get("species_kg", {}), upper_species
	)
	var signed_o2_kg: float = float(stored.get("o2_kg", 0.0))
	var routes: Array = []
	routes.append(make_atomic_route(
		parcel_id + ":carve:upper",
		"delayed_parcel_carve",
		source_room_id,
		EXTERIOR_ID,
		ZONE_UPPER,
		ZONE_UPPER,
		float(stored.get("gas_mass_kg", 0.0)),
		float(stored.get("sensible_enthalpy_kj", 0.0)),
		maxf(0.0, signed_o2_kg),
		upper_species
	))
	if _sum_parcel_species(lower_species) > 0.0:
		routes.append(make_atomic_route(
			parcel_id + ":carve:lower",
			"delayed_parcel_carve",
			source_room_id,
			EXTERIOR_ID,
			ZONE_LOWER,
			ZONE_LOWER,
			0.0,
			0.0,
			0.0,
			lower_species
		))
	if signed_o2_kg < 0.0:
		routes.append(make_atomic_route(
			parcel_id + ":carve:o2_reverse",
			"delayed_parcel_carve",
			destination_room_id,
			EXTERIOR_ID,
			ZONE_UPPER,
			ZONE_UPPER,
			0.0,
			0.0,
			-signed_o2_kg,
			{}
		))
	for route in routes:
		_record_request_telemetry(route)
	add_atomic_bundle(make_atomic_bundle(
		parcel_id + ":carve",
		"delayed_parcel_carve",
		routes,
		{
			"kind": "delayed_parcel_carve",
			"parcel_id": parcel_id,
			"transport_family": "delayed_parcel",
		}
	))


func _add_parcel_resolution_bundle(
		parcel_id: String,
		stored: Dictionary,
		delivered_species: Dictionary,
		delivered_upper_species: Dictionary,
		refunded_species: Dictionary,
		refunded_upper_species: Dictionary,
		cancelled: bool
	) -> void:
	var accepted_fraction: float = clampf(
		float(stored.get("accepted_fraction", 0.0)), 0.0, 1.0
	)
	var source_room_id: int = int(stored.get("source_room_id", EXTERIOR_ID))
	var destination_room_id: int = int(stored.get("destination_room_id", EXTERIOR_ID))
	var signed_o2_kg: float = float(stored.get("o2_kg", 0.0))
	var routes: Array = []
	if cancelled:
		# Legacy drops the parcel when its destination no longer exists. Keep that
		# loss explicit as a terminal cancelled reservoir instead of fabricating a
		# refund to the source room.
		_add_parcel_payload(
			_parcel_atomic_cancelled_payload,
			_scaled_parcel_payload(stored, accepted_fraction)
		)
		return
	else:
		_append_parcel_resolution_routes(
			routes,
			parcel_id + ":delivery",
			destination_room_id,
			delivered_species,
			delivered_upper_species,
			float(stored.get("gas_mass_kg", 0.0)) * accepted_fraction,
			float(stored.get("sensible_enthalpy_kj", 0.0)) * accepted_fraction,
			maxf(0.0, signed_o2_kg) * accepted_fraction,
			accepted_fraction
		)
		_append_parcel_resolution_routes(
			routes,
			parcel_id + ":refund",
			source_room_id,
			refunded_species,
			refunded_upper_species,
			0.0,
			0.0,
			0.0,
			accepted_fraction
		)
		if signed_o2_kg < 0.0:
			routes.append(make_atomic_route(
				parcel_id + ":delivery:o2_reverse",
				"delayed_parcel_delivery",
				EXTERIOR_ID,
				source_room_id,
				ZONE_UPPER,
				ZONE_UPPER,
				0.0,
				0.0,
				-signed_o2_kg * accepted_fraction,
				{}
			))
		_add_parcel_payload(
			_parcel_atomic_delivered_payload,
			{
				"gas_mass_kg": float(stored.get("gas_mass_kg", 0.0)) * accepted_fraction,
				"sensible_enthalpy_kj": float(
					stored.get("sensible_enthalpy_kj", 0.0)
				) * accepted_fraction,
				"o2_kg": signed_o2_kg * accepted_fraction,
				"species_kg": _scaled_parcel_species(
					delivered_species, accepted_fraction
				),
			}
		)
		_add_parcel_payload(
			_parcel_atomic_refunded_payload,
			{
				"gas_mass_kg": 0.0,
				"sensible_enthalpy_kj": 0.0,
				"o2_kg": 0.0,
				"species_kg": _scaled_parcel_species(
					refunded_species, accepted_fraction
				),
			}
		)
	for route in routes:
		_record_request_telemetry(route)
	if not routes.is_empty():
		add_atomic_bundle(make_atomic_bundle(
			parcel_id + ":resolve",
			"delayed_parcel_resolve",
			routes,
			{
				"kind": "delayed_parcel_resolution",
				"parcel_id": parcel_id,
				"transport_family": "delayed_parcel",
				"persistent_accepted_fraction": accepted_fraction,
			}
		))


func _append_parcel_resolution_routes(
		routes: Array,
		route_prefix: String,
		destination_room_id: int,
		total_species: Dictionary,
		upper_species: Dictionary,
		gas_mass_kg: float,
		sensible_enthalpy_kj: float,
		o2_kg: float,
		accepted_fraction: float
	) -> void:
	var accepted_upper_species: Dictionary = _scaled_parcel_species(
		_bounded_upper_parcel_species(upper_species, total_species),
		accepted_fraction
	)
	var accepted_lower_species: Dictionary = _scaled_parcel_species(
		_lower_parcel_species(total_species, upper_species),
		accepted_fraction
	)
	if gas_mass_kg > 0.0 or sensible_enthalpy_kj > 0.0 or o2_kg > 0.0 \
			or _sum_parcel_species(accepted_upper_species) > 0.0:
		routes.append(make_atomic_route(
			route_prefix + ":upper",
			"delayed_parcel_resolution",
			EXTERIOR_ID,
			destination_room_id,
			ZONE_UPPER,
			ZONE_UPPER,
			gas_mass_kg,
			sensible_enthalpy_kj,
			o2_kg,
			accepted_upper_species
		))
	if _sum_parcel_species(accepted_lower_species) > 0.0:
		routes.append(make_atomic_route(
			route_prefix + ":lower",
			"delayed_parcel_resolution",
			EXTERIOR_ID,
			destination_room_id,
			ZONE_LOWER,
			ZONE_LOWER,
			0.0,
			0.0,
			0.0,
			accepted_lower_species
		))


func apply_immediate_species_event(event: Dictionary) -> void:
	var request_id: String = String(event.get("request_id", ""))
	var cause: String = String(event.get("cause", ""))
	if request_id.is_empty() or not _is_immediate_species_cause(cause):
		return
	var total_species: Dictionary = _transit_species(event.get("species_kg", {}))
	if _sum_transit_species(total_species) <= 0.0:
		return
	_register_event_species_claims(
		event,
		"GasExchangeSystem",
		_semantic_transport_family(cause),
		"vertical_opening" if _is_vertical_species_cause(cause) else "interior_opening",
		total_species
	)
	register_semantic_unresolved(event, ["gas_mass", "enthalpy", "o2"])
	match cause:
		"background_species_exchange":
			_add_transit_species(_immediate_background_species_kg, total_species)
		"doorway_species_counterflow":
			_add_transit_species(_immediate_counterflow_species_kg, total_species)
		"vertical_species_net_exchange":
			_add_transit_species(_vertical_net_species_kg, total_species)
			_vertical_transfer_count += 1
			if bool(event.get("opposed_zone_direction", false)):
				_vertical_opposed_zone_direction_count += 1
		"vertical_species_directed_exchange":
			_add_transit_species(_vertical_directed_species_kg, total_species)
			_vertical_transfer_count += 1
	_immediate_transfer_count += 1
	if event.has("source_zone") and event.has("destination_zone"):
		add_request(make_request(
			request_id,
			cause,
			int(event.get("source_room_id", EXTERIOR_ID)),
			int(event.get("destination_room_id", EXTERIOR_ID)),
			String(event.get("source_zone", ZONE_UPPER)),
			String(event.get("destination_zone", ZONE_UPPER)),
			0.0,
			0.0,
			0.0,
			total_species
		))
	else:
		var upper_species: Dictionary = _bounded_upper_transit_species(
			event.get("upper_species_kg", {}), total_species
		)
		_add_transit_zone_requests(
			request_id,
			cause,
			int(event.get("source_room_id", EXTERIOR_ID)),
			int(event.get("destination_room_id", EXTERIOR_ID)),
			total_species,
			upper_species
		)


func apply_atomic_transport_event(
		event: Dictionary,
		producer: String,
		transport_family: String,
		boundary_kind: String
	) -> bool:
	var request_id: String = String(event.get("request_id", ""))
	var cause: String = String(event.get("cause", ""))
	if request_id.is_empty() or cause.is_empty() or producer.is_empty():
		return false
	var gas_mass_kg: float = maxf(0.0, float(event.get("gas_mass_kg", 0.0)))
	var sensible_enthalpy_kj: float = maxf(
		0.0, float(event.get("sensible_enthalpy_kj", 0.0))
	)
	var o2_kg: float = maxf(0.0, float(event.get("o2_kg", 0.0)))
	var species: Dictionary = _transit_species(event.get("species_kg", {}))
	if gas_mass_kg <= 0.0 and sensible_enthalpy_kj <= 0.0 and o2_kg <= 0.0 \
			and _sum_transit_species(species) <= 0.0:
		return false
	var route: Dictionary = make_atomic_route(
		request_id + ":route",
		cause,
		int(event.get("source_room_id", EXTERIOR_ID)),
		int(event.get("destination_room_id", EXTERIOR_ID)),
		String(event.get("source_zone", ZONE_UPPER)),
		String(event.get("destination_zone", ZONE_UPPER)),
		gas_mass_kg,
		sensible_enthalpy_kj,
		o2_kg,
		species
	)
	if not bool(route.get("valid", false)):
		_atomic_invalid_bundle_count += 1
		return false
	for quantity in ["gas_mass", "enthalpy", "o2"]:
		var amount: float = gas_mass_kg
		if quantity == "enthalpy":
			amount = sensible_enthalpy_kj
		elif quantity == "o2":
			amount = o2_kg
		register_semantic_claim({
			"connection_id": String(event.get("connection_id", "")),
			"producer": producer,
			"transport_family": transport_family,
			"boundary_kind": boundary_kind,
			"source_room_id": int(event.get("source_room_id", EXTERIOR_ID)),
			"destination_room_id": int(event.get("destination_room_id", EXTERIOR_ID)),
			"source_zone": String(event.get("source_zone", ZONE_UPPER)),
			"destination_zone": String(event.get("destination_zone", ZONE_UPPER)),
			"quantity": quantity,
			"amount": amount,
		})
	_register_event_species_claims(
		event, producer, transport_family, boundary_kind, species
	)
	_record_request_telemetry(route)
	return add_atomic_bundle(make_atomic_bundle(
		request_id,
		cause,
		[route],
		{"kind": "atomic_transport", "transport_family": transport_family}
	))


func apply_exterior_purge_event(event: Dictionary) -> void:
	var event_id: String = String(event.get("event_id", ""))
	var mechanism: String = String(event.get("mechanism", ""))
	if event_id.is_empty() or mechanism.is_empty():
		return
	if _exterior_purge_event_ids.has(event_id):
		_exterior_purge_duplicate_event_count += 1
		_duplicate_owner_count += 1
		return
	_exterior_purge_event_ids[event_id] = true
	var total_species: Dictionary = _transit_species(event.get("species_kg", {}))
	if _sum_transit_species(total_species) <= 0.0:
		return
	var upper_species: Dictionary = _bounded_upper_transit_species(
		event.get("upper_species_kg", {}), total_species
	)
	_register_split_species_claims(
		event,
		"GasExchangeSystem",
		"exterior_purge",
		"exterior_opening",
		total_species,
		upper_species
	)
	register_semantic_unresolved(event, ["gas_mass", "enthalpy", "o2"])
	_exterior_purge_event_count += 1
	_add_transit_species(_exterior_purge_requested_species_kg, total_species)
	_add_transit_species(_exterior_purge_upper_species_kg, upper_species)
	if not _exterior_purge_mechanism_species_kg.has(mechanism):
		_exterior_purge_mechanism_species_kg[mechanism] = {}
	var mechanism_species: Dictionary = _exterior_purge_mechanism_species_kg[mechanism]
	_add_transit_species(mechanism_species, total_species)
	_exterior_purge_mechanism_species_kg[mechanism] = mechanism_species
	_add_transit_zone_requests(
		event_id,
		"exterior_species_purge:" + mechanism,
		int(event.get("source_room_id", EXTERIOR_ID)),
		EXTERIOR_ID,
		total_species,
		upper_species
	)


func apply_thermal_species_event(event: Dictionary) -> void:
	var event_id: String = String(event.get("event_id", ""))
	var mechanism: String = String(event.get("mechanism", ""))
	if event_id.is_empty() or mechanism.is_empty():
		return
	if _thermal_species_event_ids.has(event_id):
		_thermal_species_duplicate_event_count += 1
		_duplicate_owner_count += 1
		return
	_thermal_species_event_ids[event_id] = true
	var total_species: Dictionary = _transit_species(event.get("species_kg", {}))
	if _sum_transit_species(total_species) <= 0.0:
		return
	var source_upper_species: Dictionary = _bounded_upper_transit_species(
		event.get("source_upper_species_kg", {}), total_species
	)
	var destination_upper_species: Dictionary = _bounded_upper_transit_species(
		event.get("destination_upper_species_kg", {}), total_species
	)
	var shadow_owned: bool = _register_thermal_species_claims(
		event,
		total_species,
		source_upper_species,
		destination_upper_species
	)
	_thermal_species_event_count += 1
	_add_transit_species(_thermal_species_requested_kg, total_species)
	_add_transit_species(_thermal_species_source_upper_kg, source_upper_species)
	_add_transit_species(_thermal_species_destination_upper_kg, destination_upper_species)
	if not _thermal_species_mechanism_kg.has(mechanism):
		_thermal_species_mechanism_kg[mechanism] = {}
	var mechanism_species: Dictionary = _thermal_species_mechanism_kg[mechanism]
	_add_transit_species(mechanism_species, total_species)
	_thermal_species_mechanism_kg[mechanism] = mechanism_species
	if not shadow_owned:
		_add_transit_species(_thermal_species_semantic_suppressed_kg, total_species)
		register_semantic_unresolved(event, ["gas_mass", "enthalpy", "o2"])
		return
	_add_thermal_species_route_requests(
		event_id,
		"thermal_species_transport:" + mechanism,
		int(event.get("source_room_id", EXTERIOR_ID)),
		int(event.get("destination_room_id", EXTERIOR_ID)),
		total_species,
		source_upper_species,
		destination_upper_species
	)


func apply_co_oxidation_event(event: Dictionary) -> void:
	var event_id: String = String(event.get("event_id", ""))
	var room_id: int = int(event.get("room_id", EXTERIOR_ID))
	var co_sink_kg: float = maxf(0.0, float(event.get("co_consumed_kg", 0.0)))
	var co2_source_kg: float = maxf(0.0, float(event.get("co2_generated_kg", 0.0)))
	var o2_sink_kg: float = maxf(0.0, float(event.get("o2_consumed_kg", 0.0)))
	if event_id.is_empty() or room_id == EXTERIOR_ID \
			or co_sink_kg <= 0.0 or co2_source_kg <= 0.0 or o2_sink_kg <= 0.0:
		_atomic_invalid_bundle_count += 1
		return
	if _co_oxidation_event_ids.has(event_id):
		_duplicate_owner_count += 1
		_atomic_duplicate_bundle_count += 1
		return
	_co_oxidation_event_ids[event_id] = true
	var connection_id: String = "chemical:%d:co_oxidation" % room_id
	register_semantic_claim({
		"connection_id": connection_id,
		"producer": "SimulationEngine",
		"transport_family": "co_oxidation",
		"boundary_kind": "chemical_conversion",
		"source_room_id": room_id,
		"destination_room_id": EXTERIOR_ID,
		"source_zone": ZONE_UPPER,
		"destination_zone": ZONE_UPPER,
		"quantity": "co",
		"amount": co_sink_kg,
	})
	register_semantic_claim({
		"connection_id": connection_id,
		"producer": "SimulationEngine",
		"transport_family": "co_oxidation",
		"boundary_kind": "chemical_conversion",
		"source_room_id": room_id,
		"destination_room_id": EXTERIOR_ID,
		"source_zone": ZONE_UPPER,
		"destination_zone": ZONE_UPPER,
		"quantity": "o2",
		"amount": o2_sink_kg,
	})
	register_semantic_claim({
		"connection_id": connection_id,
		"producer": "SimulationEngine",
		"transport_family": "co_oxidation",
		"boundary_kind": "chemical_conversion",
		"source_room_id": EXTERIOR_ID,
		"destination_room_id": room_id,
		"source_zone": ZONE_UPPER,
		"destination_zone": ZONE_UPPER,
		"quantity": "co2",
		"amount": co2_source_kg,
	})
	var routes: Array = [
		make_atomic_route(
			event_id + ":reactants",
			"co_oxidation_reactants",
			room_id,
			EXTERIOR_ID,
			ZONE_UPPER,
			ZONE_UPPER,
			0.0,
			0.0,
			o2_sink_kg,
			{"co": co_sink_kg}
		),
		make_atomic_route(
			event_id + ":products",
			"co_oxidation_products",
			EXTERIOR_ID,
			room_id,
			ZONE_UPPER,
			ZONE_UPPER,
			0.0,
			0.0,
			0.0,
			{"co2": co2_source_kg}
		),
	]
	add_atomic_bundle(make_atomic_bundle(
		event_id,
		"co_oxidation",
		routes,
		{
			"kind": "co_oxidation",
			"room_id": room_id,
			"co_consumed_kg": co_sink_kg,
			"co2_generated_kg": co2_source_kg,
			"o2_consumed_kg": o2_sink_kg,
		}
	))
	_co_oxidation_co_sink_kg += co_sink_kg
	_co_oxidation_co2_source_kg += co2_source_kg
	_co_oxidation_o2_sink_kg += o2_sink_kg
	# Compatibility telemetry only: legacy still adds bulk CO2 without an upper split.
	_co_oxidation_legacy_lower_co2_kg += co2_source_kg
	_co_oxidation_carbon_residual_kg += \
			co_sink_kg * (12.0 / 28.0) - co2_source_kg * (12.0 / 44.0)


func _is_immediate_species_cause(cause: String) -> bool:
	return cause == "background_species_exchange" \
			or cause == "doorway_species_counterflow" \
			or cause == "vertical_species_net_exchange" \
			or cause == "vertical_species_directed_exchange"


func _is_exterior_purge_cause(cause: String) -> bool:
	return cause.begins_with("exterior_species_purge:")


func _is_thermal_species_cause(cause: String) -> bool:
	return cause.begins_with("thermal_species_transport:")


func _is_vertical_species_cause(cause: String) -> bool:
	return cause == "vertical_species_net_exchange" \
			or cause == "vertical_species_directed_exchange"


func register_semantic_claim(claim: Dictionary) -> String:
	var connection_id: String = String(claim.get("connection_id", ""))
	var producer: String = String(claim.get("producer", ""))
	var quantity: String = String(claim.get("quantity", ""))
	var amount: float = maxf(0.0, float(claim.get("amount", 0.0)))
	if producer.is_empty() or not SEMANTIC_QUANTITY_BITS.has(quantity) or amount <= 0.0:
		return "ignored"
	if connection_id.is_empty():
		_semantic_unknown_connection_count += 1
		return "unknown"
	var owner: String = _semantic_owner_for_claim(claim)
	var status: String = "unresolved"
	if not owner.is_empty():
		status = "accepted" if producer == owner else "suppressed"
	var key: String = "%s|%d|%d|%s|%s|%s" % [
		connection_id,
		int(claim.get("source_room_id", EXTERIOR_ID)),
		int(claim.get("destination_room_id", EXTERIOR_ID)),
		String(claim.get("source_zone", ZONE_UPPER)),
		String(claim.get("destination_zone", ZONE_UPPER)),
		quantity,
	]
	var record: Dictionary = _semantic_claims.get(key, {
		"quantity": quantity,
		"owner": owner,
		"producers": {},
		"mechanisms": {},
	})
	if String(record.get("owner", "")).is_empty() and not owner.is_empty():
		record["owner"] = owner
	var producers: Dictionary = record.get("producers", {})
	producers[producer] = float(producers.get(producer, 0.0)) + amount
	record["producers"] = producers
	var mechanisms: Dictionary = record.get("mechanisms", {})
	var mechanism: String = String(claim.get("transport_family", ""))
	var boundary_kind: String = String(claim.get("boundary_kind", ""))
	if not mechanism.is_empty():
		mechanisms[producer + ":" + mechanism + ":" + boundary_kind] = true
	record["mechanisms"] = mechanisms
	_semantic_claims[key] = record
	_semantic_claim_count += 1
	match status:
		"accepted":
			_semantic_accepted_claim_count += 1
		"suppressed":
			_semantic_suppressed_claim_count += 1
			_semantic_suppressed_quantity_mask |= int(
				SEMANTIC_QUANTITY_BITS.get(quantity, 0)
			)
			_add_semantic_amount(_semantic_suppressed_amounts, quantity, amount)
		_:
			_semantic_unresolved_claim_count += 1
			_semantic_unresolved_quantity_mask |= int(
				SEMANTIC_QUANTITY_BITS.get(quantity, 0)
			)
			_add_semantic_amount(_semantic_unresolved_amounts, quantity, amount)
	return status


func register_semantic_unresolved(event: Dictionary, quantities: Array) -> void:
	var connection_id: String = String(event.get("connection_id", ""))
	if connection_id.is_empty():
		_semantic_unknown_connection_count += 1
		return
	var source_zone: String = String(event.get("source_zone", "mixed"))
	var destination_zone: String = String(event.get("destination_zone", "mixed"))
	for raw_quantity in quantities:
		var quantity: String = String(raw_quantity)
		if not SEMANTIC_QUANTITY_BITS.has(quantity):
			continue
		var key: String = "%s|%d|%d|%s|%s|%s" % [
			connection_id,
			int(event.get("source_room_id", EXTERIOR_ID)),
			int(event.get("destination_room_id", EXTERIOR_ID)),
			source_zone,
			destination_zone,
			quantity,
		]
		if _semantic_unresolved_keys.has(key):
			continue
		_semantic_unresolved_keys[key] = true
		_semantic_unresolved_claim_count += 1
		_semantic_unresolved_quantity_mask |= int(SEMANTIC_QUANTITY_BITS[quantity])


func _semantic_owner_for_claim(claim: Dictionary) -> String:
	var boundary_kind: String = String(claim.get("boundary_kind", ""))
	var quantity: String = String(claim.get("quantity", ""))
	var transport_family: String = String(claim.get("transport_family", ""))
	match boundary_kind:
		"interior_opening", "vertical_opening", "exterior_opening":
			if quantity in TRANSIT_SPECIES:
				return "GasExchangeSystem"
			if transport_family == "delayed_parcel" \
					and quantity in PARCEL_SPECIES:
				return "GasExchangeSystem"
			if transport_family == "doorway_bulk" \
					and quantity in ["gas_mass", "enthalpy", "o2"]:
				return "GasExchangeSystem"
			if transport_family == "delayed_parcel" \
					and quantity in ["gas_mass", "enthalpy", "o2"]:
				return "GasExchangeSystem"
			return ""
		"interlayer":
			return "ThermalSystem"
		"thermal_reservoir":
			return "ThermalSystem" if quantity == "enthalpy" else ""
		"chemical_combustion":
			if quantity == "enthalpy":
				return "ThermalSystem"
			if quantity == "o2":
				return "OxygenExchangeSystem"
			if quantity in TRANSIT_SPECIES:
				return "CombustionSystem"
		"chemical_conversion":
			return "SimulationEngine" if quantity in ["co", "co2", "o2"] else ""
	return ""


func _add_semantic_amount(target: Dictionary, quantity: String, amount: float) -> void:
	target[quantity] = float(target.get(quantity, 0.0)) + maxf(0.0, amount)


func register_semantic_species_claim(
		event: Dictionary,
		producer: String,
		transport_family: String,
		boundary_kind: String
	) -> bool:
	var total_species: Dictionary = _transit_species(event.get("species_kg", {}))
	return _register_event_species_claims(
		event, producer, transport_family, boundary_kind, total_species
	)


func _register_event_species_claims(
		event: Dictionary,
		producer: String,
		transport_family: String,
		boundary_kind: String,
		total_species: Dictionary
	) -> bool:
	if event.has("source_zone") and event.has("destination_zone"):
		return _register_species_map_claims(
			event,
			producer,
			transport_family,
			boundary_kind,
			String(event.get("source_zone", ZONE_UPPER)),
			String(event.get("destination_zone", ZONE_UPPER)),
			total_species
		)
	var upper_species: Dictionary = _bounded_upper_transit_species(
		event.get("upper_species_kg", {}), total_species
	)
	return _register_split_species_claims(
		event, producer, transport_family, boundary_kind, total_species, upper_species
	)


func _register_split_species_claims(
		event: Dictionary,
		producer: String,
		transport_family: String,
		boundary_kind: String,
		total_species: Dictionary,
		upper_species: Dictionary
	) -> bool:
	var upper_accepted: bool = _register_species_map_claims(
		event,
		producer,
		transport_family,
		boundary_kind,
		ZONE_UPPER,
		ZONE_UPPER,
		upper_species
	)
	var lower_accepted: bool = _register_species_map_claims(
		event,
		producer,
		transport_family,
		boundary_kind,
		ZONE_LOWER,
		ZONE_LOWER,
		_lower_transit_species(total_species, upper_species)
	)
	return upper_accepted or lower_accepted


func _register_split_parcel_species_claims(
		event: Dictionary,
		producer: String,
		transport_family: String,
		boundary_kind: String,
		total_species: Dictionary,
		upper_species: Dictionary
	) -> bool:
	var upper_accepted: bool = _register_parcel_species_map_claims(
		event,
		producer,
		transport_family,
		boundary_kind,
		ZONE_UPPER,
		ZONE_UPPER,
		upper_species
	)
	var lower_accepted: bool = _register_parcel_species_map_claims(
		event,
		producer,
		transport_family,
		boundary_kind,
		ZONE_LOWER,
		ZONE_LOWER,
		_lower_parcel_species(total_species, upper_species)
	)
	return upper_accepted or lower_accepted


func _register_parcel_species_map_claims(
		event: Dictionary,
		producer: String,
		transport_family: String,
		boundary_kind: String,
		source_zone: String,
		destination_zone: String,
		species: Dictionary
	) -> bool:
	var connection_id: String = String(event.get("connection_id", ""))
	var any_accepted: bool = false
	for species_name in PARCEL_SPECIES:
		var mass_kg: float = maxf(0.0, float(species.get(species_name, 0.0)))
		if mass_kg <= 0.0:
			continue
		var status: String = register_semantic_claim({
			"connection_id": connection_id,
			"producer": producer,
			"transport_family": transport_family,
			"boundary_kind": boundary_kind,
			"source_room_id": int(event.get("source_room_id", EXTERIOR_ID)),
			"destination_room_id": int(event.get("destination_room_id", EXTERIOR_ID)),
			"source_zone": source_zone,
			"destination_zone": destination_zone,
			"quantity": species_name,
			"amount": mass_kg,
		})
		any_accepted = status == "accepted" or any_accepted
	return any_accepted


func _register_thermal_species_claims(
		event: Dictionary,
		total_species: Dictionary,
		source_upper_species: Dictionary,
		destination_upper_species: Dictionary
	) -> bool:
	var routes: Dictionary = {
		"upper_upper": {},
		"upper_lower": {},
		"lower_upper": {},
		"lower_lower": {},
	}
	for species_name in TRANSIT_SPECIES:
		var total_kg: float = float(total_species.get(species_name, 0.0))
		var source_upper_kg: float = float(source_upper_species.get(species_name, 0.0))
		var destination_upper_kg: float = float(
			destination_upper_species.get(species_name, 0.0)
		)
		var upper_upper_kg: float = minf(source_upper_kg, destination_upper_kg)
		routes["upper_upper"][species_name] = upper_upper_kg
		routes["upper_lower"][species_name] = maxf(0.0, source_upper_kg - upper_upper_kg)
		routes["lower_upper"][species_name] = maxf(0.0, destination_upper_kg - upper_upper_kg)
		routes["lower_lower"][species_name] = maxf(
			0.0,
			total_kg - float(routes["upper_upper"][species_name])
					- float(routes["upper_lower"][species_name])
					- float(routes["lower_upper"][species_name])
		)
	var any_accepted: bool = false
	for route_name in routes.keys():
		var route_parts: PackedStringArray = String(route_name).split("_")
		any_accepted = _register_species_map_claims(
			event,
			"ThermalSystem",
			"thermal_carry",
			"interlayer" if String(event.get("mechanism", "")) == "co_interlayer_mixing" \
					else "interior_opening",
			String(route_parts[0]),
			String(route_parts[1]),
			routes[route_name]
		) or any_accepted
	return any_accepted


func _register_species_map_claims(
		event: Dictionary,
		producer: String,
		transport_family: String,
		boundary_kind: String,
		source_zone: String,
		destination_zone: String,
		species: Dictionary
	) -> bool:
	var connection_id: String = String(event.get("connection_id", ""))
	var any_accepted: bool = false
	for species_name in TRANSIT_SPECIES:
		var mass_kg: float = maxf(0.0, float(species.get(species_name, 0.0)))
		if mass_kg <= 0.0:
			continue
		var status: String = register_semantic_claim({
			"connection_id": connection_id,
			"producer": producer,
			"transport_family": transport_family,
			"boundary_kind": boundary_kind,
			"source_room_id": int(event.get("source_room_id", EXTERIOR_ID)),
			"destination_room_id": int(event.get("destination_room_id", EXTERIOR_ID)),
			"source_zone": source_zone,
			"destination_zone": destination_zone,
			"quantity": species_name,
			"amount": mass_kg,
		})
		any_accepted = status == "accepted" or any_accepted
	return any_accepted


func _semantic_transport_family(cause: String) -> String:
	match cause:
		"background_species_exchange":
			return "background_exchange"
		"doorway_species_counterflow":
			return "doorway_bulk"
		"vertical_species_net_exchange", "vertical_species_directed_exchange":
			return "vertical_flow"
	return cause


func _semantic_conflict_summary() -> Dictionary:
	var conflict_count: int = 0
	var unresolved_conflict_count: int = 0
	var quantity_mask: int = 0
	var conflict_mass_kg: float = 0.0
	var conflict_energy_kj: float = 0.0
	var conflict_o2_kg: float = 0.0
	var conflict_species_kg: float = 0.0
	for record in _semantic_claims.values():
		var producers: Dictionary = record.get("producers", {})
		if producers.size() <= 1:
			continue
		conflict_count += 1
		if String(record.get("owner", "")).is_empty():
			unresolved_conflict_count += 1
		var quantity: String = String(record.get("quantity", ""))
		quantity_mask |= int(SEMANTIC_QUANTITY_BITS.get(quantity, 0))
		var total: float = 0.0
		var largest: float = 0.0
		for amount in producers.values():
			total += float(amount)
			largest = maxf(largest, float(amount))
		var contested: float = maxf(0.0, total - largest)
		match quantity:
			"gas_mass":
				conflict_mass_kg += contested
			"enthalpy":
				conflict_energy_kj += contested
			"o2":
				conflict_o2_kg += contested
			"smoke", "co", "co2", "hcn", "hcl", "acrolein", "formaldehyde":
				conflict_species_kg += contested
	return {
		"claim_count": _semantic_claim_count,
		"conflict_count": conflict_count,
		"quantity_mask": quantity_mask,
		"conflict_mass_kg": conflict_mass_kg,
		"conflict_energy_kj": conflict_energy_kj,
		"conflict_o2_kg": conflict_o2_kg,
		"conflict_species_kg": conflict_species_kg,
		"unknown_connection_count": _semantic_unknown_connection_count,
		"accepted_claim_count": _semantic_accepted_claim_count,
		"suppressed_claim_count": _semantic_suppressed_claim_count,
		"unresolved_claim_count": _semantic_unresolved_claim_count,
		"suppressed_quantity_mask": _semantic_suppressed_quantity_mask,
		"unresolved_quantity_mask": _semantic_unresolved_quantity_mask,
		"suppressed_species_kg": _semantic_species_amount(_semantic_suppressed_amounts),
		"unresolved_mass_kg": float(_semantic_unresolved_amounts.get("gas_mass", 0.0)),
		"unresolved_energy_kj": float(_semantic_unresolved_amounts.get("enthalpy", 0.0)),
		"unresolved_o2_kg": float(_semantic_unresolved_amounts.get("o2", 0.0)),
		"unresolved_species_kg": _semantic_species_amount(_semantic_unresolved_amounts),
		"unresolved_conflict_count": unresolved_conflict_count,
	}


func _semantic_species_amount(amounts: Dictionary) -> float:
	return _sum_parcel_species(amounts)


func _transit_species(raw_species) -> Dictionary:
	var species: Dictionary = raw_species if typeof(raw_species) == TYPE_DICTIONARY else {}
	var filtered: Dictionary = {}
	for species_name in TRANSIT_SPECIES:
		filtered[species_name] = maxf(0.0, float(species.get(species_name, 0.0)))
	return filtered


func _scaled_transit_species(species: Dictionary, fraction: float) -> Dictionary:
	var scaled: Dictionary = {}
	var safe_fraction: float = clampf(fraction, 0.0, 1.0)
	for species_name in TRANSIT_SPECIES:
		scaled[species_name] = maxf(
			0.0, float(species.get(species_name, 0.0)) * safe_fraction
		)
	return scaled


func _parcel_species(raw_species) -> Dictionary:
	var species: Dictionary = raw_species if typeof(raw_species) == TYPE_DICTIONARY else {}
	var filtered: Dictionary = {}
	for species_name in PARCEL_SPECIES:
		filtered[species_name] = maxf(0.0, float(species.get(species_name, 0.0)))
	return filtered


func _scaled_parcel_species(species: Dictionary, fraction: float) -> Dictionary:
	var scaled: Dictionary = {}
	var safe_fraction: float = clampf(fraction, 0.0, 1.0)
	for species_name in PARCEL_SPECIES:
		scaled[species_name] = maxf(
			0.0, float(species.get(species_name, 0.0)) * safe_fraction
		)
	return scaled


func _scaled_parcel_payload(stored: Dictionary, fraction: float) -> Dictionary:
	var safe_fraction: float = clampf(fraction, 0.0, 1.0)
	return {
		"gas_mass_kg": maxf(
			0.0, float(stored.get("gas_mass_kg", 0.0)) * safe_fraction
		),
		"sensible_enthalpy_kj": maxf(
			0.0,
			float(stored.get("sensible_enthalpy_kj", 0.0)) * safe_fraction
		),
		"o2_kg": float(stored.get("o2_kg", 0.0)) * safe_fraction,
		"species_kg": _scaled_parcel_species(
			stored.get("species_kg", {}), safe_fraction
		),
	}


func _add_parcel_payload(target: Dictionary, payload: Dictionary) -> void:
	target["gas_mass_kg"] = float(target.get("gas_mass_kg", 0.0)) \
			+ float(payload.get("gas_mass_kg", 0.0))
	target["sensible_enthalpy_kj"] = float(
		target.get("sensible_enthalpy_kj", 0.0)
	) + float(payload.get("sensible_enthalpy_kj", 0.0))
	target["o2_kg"] = float(target.get("o2_kg", 0.0)) \
			+ float(payload.get("o2_kg", 0.0))
	var target_species: Dictionary = target.get("species_kg", {})
	_add_parcel_species(target_species, payload.get("species_kg", {}))
	target["species_kg"] = target_species


func _bounded_upper_parcel_species(raw_upper, total_species: Dictionary) -> Dictionary:
	var upper: Dictionary = _parcel_species(raw_upper)
	for species_name in PARCEL_SPECIES:
		upper[species_name] = minf(
			float(upper.get(species_name, 0.0)),
			float(total_species.get(species_name, 0.0))
		)
	return upper


func _lower_parcel_species(total_species: Dictionary, upper_species: Dictionary) -> Dictionary:
	var lower: Dictionary = {}
	for species_name in PARCEL_SPECIES:
		lower[species_name] = maxf(
			0.0,
			float(total_species.get(species_name, 0.0))
					- float(upper_species.get(species_name, 0.0))
		)
	return lower


func _bounded_upper_transit_species(raw_upper, total_species: Dictionary) -> Dictionary:
	var upper: Dictionary = _transit_species(raw_upper)
	for species_name in TRANSIT_SPECIES:
		upper[species_name] = minf(
			float(upper.get(species_name, 0.0)),
			float(total_species.get(species_name, 0.0))
		)
	return upper


func _lower_transit_species(total_species: Dictionary, upper_species: Dictionary) -> Dictionary:
	var lower: Dictionary = {}
	for species_name in TRANSIT_SPECIES:
		lower[species_name] = maxf(
			0.0,
			float(total_species.get(species_name, 0.0))
					- float(upper_species.get(species_name, 0.0))
		)
	return lower


func _add_transit_zone_requests(
	request_id_prefix: String,
	cause: String,
	source_room_id: int,
	destination_room_id: int,
	total_species: Dictionary,
	upper_species: Dictionary
	) -> void:
	var lower_species: Dictionary = _lower_transit_species(total_species, upper_species)
	_add_transit_zone_request(
		request_id_prefix + ":upper",
		cause,
		source_room_id,
		destination_room_id,
		ZONE_UPPER,
		upper_species
	)
	_add_transit_zone_request(
		request_id_prefix + ":lower",
		cause,
		source_room_id,
		destination_room_id,
		ZONE_LOWER,
		lower_species
	)


func _add_transit_zone_request(
	request_id: String,
	cause: String,
	source_room_id: int,
	destination_room_id: int,
	zone_name: String,
	species: Dictionary
	) -> void:
	if _sum_transit_species(species) <= 0.0:
		return
	add_request(make_request(
		request_id,
		cause,
		source_room_id,
		destination_room_id,
		zone_name,
		zone_name,
		0.0,
		0.0,
		0.0,
		species
	))


func _add_thermal_species_route_requests(
		request_id_prefix: String,
		cause: String,
		source_room_id: int,
		destination_room_id: int,
		total_species: Dictionary,
		source_upper_species: Dictionary,
		destination_upper_species: Dictionary
	) -> void:
	var routes: Dictionary = {
		"upper_upper": {},
		"upper_lower": {},
		"lower_upper": {},
		"lower_lower": {},
	}
	for species_name in TRANSIT_SPECIES:
		var total_kg: float = float(total_species.get(species_name, 0.0))
		var source_upper_kg: float = float(source_upper_species.get(species_name, 0.0))
		var destination_upper_kg: float = float(
			destination_upper_species.get(species_name, 0.0)
		)
		var upper_upper_kg: float = minf(source_upper_kg, destination_upper_kg)
		var upper_lower_kg: float = maxf(0.0, source_upper_kg - upper_upper_kg)
		var lower_upper_kg: float = maxf(0.0, destination_upper_kg - upper_upper_kg)
		var lower_lower_kg: float = maxf(
			0.0, total_kg - upper_upper_kg - upper_lower_kg - lower_upper_kg
		)
		routes["upper_upper"][species_name] = upper_upper_kg
		routes["upper_lower"][species_name] = upper_lower_kg
		routes["lower_upper"][species_name] = lower_upper_kg
		routes["lower_lower"][species_name] = lower_lower_kg
	for route_name in routes.keys():
		var route_parts: PackedStringArray = String(route_name).split("_")
		var route_species: Dictionary = routes[route_name]
		if _sum_transit_species(route_species) <= 0.0:
			continue
		add_request(make_request(
			request_id_prefix + ":" + String(route_name),
			cause,
			source_room_id,
			destination_room_id,
			String(route_parts[0]),
			String(route_parts[1]),
			0.0,
			0.0,
			0.0,
			route_species
		))


func _add_transit_species(target: Dictionary, species: Dictionary) -> void:
	for species_name in TRANSIT_SPECIES:
		target[species_name] = float(target.get(species_name, 0.0)) \
				+ float(species.get(species_name, 0.0))


func _add_parcel_species(target: Dictionary, species: Dictionary) -> void:
	for species_name in PARCEL_SPECIES:
		target[species_name] = float(target.get(species_name, 0.0)) \
				+ float(species.get(species_name, 0.0))


func _sum_transit_species(species: Dictionary) -> float:
	var total_kg: float = 0.0
	for species_name in TRANSIT_SPECIES:
		total_kg += float(species.get(species_name, 0.0))
	return total_kg


func _sum_parcel_species(species: Dictionary) -> float:
	var total_kg: float = 0.0
	for species_name in PARCEL_SPECIES:
		total_kg += float(species.get(species_name, 0.0))
	return total_kg


func _exterior_purge_lower_for(species_name: String) -> float:
	return maxf(
		0.0,
		float(_exterior_purge_requested_species_kg.get(species_name, 0.0))
				- float(_exterior_purge_upper_species_kg.get(species_name, 0.0))
	)


func _exterior_purge_residual_for(species_name: String) -> float:
	return float(_exterior_purge_requested_species_kg.get(species_name, 0.0)) \
			- float(_exterior_purge_applied_species_kg.get(species_name, 0.0)) \
			- float(_exterior_purge_rejected_species_kg.get(species_name, 0.0))


func _exterior_purge_mechanism_total(mechanism: String) -> float:
	var species: Dictionary = _exterior_purge_mechanism_species_kg.get(mechanism, {})
	return _sum_transit_species(species)


func _thermal_species_lower_for(species_name: String, upper: Dictionary) -> float:
	return maxf(
		0.0,
		float(_thermal_species_requested_kg.get(species_name, 0.0))
				- float(upper.get(species_name, 0.0))
	)


func _thermal_species_residual_for(species_name: String) -> float:
	return float(_thermal_species_requested_kg.get(species_name, 0.0)) \
			- float(_thermal_species_applied_kg.get(species_name, 0.0)) \
			- float(_thermal_species_rejected_kg.get(species_name, 0.0)) \
			- float(_thermal_species_semantic_suppressed_kg.get(species_name, 0.0))


func _thermal_species_mechanism_total(mechanism: String) -> float:
	return _sum_transit_species(_thermal_species_mechanism_kg.get(mechanism, {}))


func _inflight_transit_species() -> Dictionary:
	var inflight: Dictionary = {}
	for raw_record in _species_transit_reservoir.values():
		var record: Dictionary = raw_record
		_add_parcel_species(inflight, record.get("species_kg", {}))
	return inflight


func _inflight_atomic_parcel_payload() -> Dictionary:
	var inflight: Dictionary = {}
	for raw_record in _species_transit_reservoir.values():
		var record: Dictionary = raw_record
		var accepted_fraction: float = maxf(
			0.0, float(record.get("accepted_fraction", -1.0))
		)
		_add_parcel_payload(
			inflight, _scaled_parcel_payload(record, accepted_fraction)
		)
	return inflight


func _parcel_atomic_payload_residual(quantity: String) -> float:
	var inflight: Dictionary = _inflight_atomic_parcel_payload()
	return float(_parcel_atomic_created_payload.get(quantity, 0.0)) \
			- float(_parcel_atomic_delivered_payload.get(quantity, 0.0)) \
			- float(_parcel_atomic_refunded_payload.get(quantity, 0.0)) \
			- float(_parcel_atomic_cancelled_payload.get(quantity, 0.0)) \
			- float(inflight.get(quantity, 0.0))


func _parcel_atomic_species_residual_kg() -> float:
	var inflight: Dictionary = _inflight_atomic_parcel_payload()
	return _sum_parcel_species(
		_parcel_atomic_created_payload.get("species_kg", {})
	) - _sum_parcel_species(
		_parcel_atomic_delivered_payload.get("species_kg", {})
	) - _sum_parcel_species(
		_parcel_atomic_refunded_payload.get("species_kg", {})
	) - _sum_parcel_species(
		_parcel_atomic_cancelled_payload.get("species_kg", {})
	) - _sum_parcel_species(inflight.get("species_kg", {}))


func _species_transit_conservation_residual_kg() -> float:
	return _sum_parcel_species(_species_transit_created_kg) \
			- _sum_parcel_species(_species_transit_delivered_kg) \
			- _sum_parcel_species(_species_transit_refunded_kg) \
			- _sum_parcel_species(_species_transit_cancelled_kg) \
			- _sum_parcel_species(_inflight_transit_species())


func _species_transit_conservation_residual_for(species_name: String) -> float:
	var inflight: Dictionary = _inflight_transit_species()
	return float(_species_transit_created_kg.get(species_name, 0.0)) \
			- float(_species_transit_delivered_kg.get(species_name, 0.0)) \
			- float(_species_transit_refunded_kg.get(species_name, 0.0)) \
			- float(_species_transit_cancelled_kg.get(species_name, 0.0)) \
			- float(inflight.get(species_name, 0.0))


func make_request(
		request_id: String,
		cause: String,
		source_room_id: int,
		destination_room_id: int,
		source_zone: String,
		destination_zone: String,
		gas_mass_kg: float,
		sensible_enthalpy_kj: float,
		o2_kg: float = 0.0,
		species_kg: Dictionary = {}
	) -> Dictionary:
	return {
		"request_id": request_id,
		"cause": cause,
		"source_room_id": source_room_id,
		"destination_room_id": destination_room_id,
		"source_zone": source_zone,
		"destination_zone": destination_zone,
		"gas_mass_kg": maxf(0.0, gas_mass_kg),
		"sensible_enthalpy_kj": maxf(0.0, sensible_enthalpy_kj),
		"o2_kg": maxf(0.0, o2_kg),
		"species_kg": species_kg.duplicate(true),
	}


func make_atomic_route(
		route_id: String,
		cause: String,
		source_room_id: int,
		destination_room_id: int,
		source_zone: String,
		destination_zone: String,
		gas_mass_kg: float,
		sensible_enthalpy_kj: float,
		o2_kg: float = 0.0,
		species_kg: Dictionary = {}
	) -> Dictionary:
	var valid: bool = gas_mass_kg >= 0.0 \
			and sensible_enthalpy_kj >= 0.0 and o2_kg >= 0.0
	for raw_species_name in species_kg.keys():
		var species_name: String = String(raw_species_name)
		if species_name not in PARCEL_SPECIES \
				or float(species_kg.get(raw_species_name, 0.0)) < 0.0:
			valid = false
	return {
		"route_id": route_id,
		"cause": cause,
		"source_room_id": source_room_id,
		"destination_room_id": destination_room_id,
		"source_zone": source_zone,
		"destination_zone": destination_zone,
		"gas_mass_kg": maxf(0.0, gas_mass_kg),
		"sensible_enthalpy_kj": maxf(0.0, sensible_enthalpy_kj),
		"o2_kg": maxf(0.0, o2_kg),
		"species_kg": _parcel_species(species_kg),
		"valid": valid,
	}


func make_atomic_bundle(
		bundle_id: String,
		cause: String,
		routes: Array,
		metadata: Dictionary = {}
	) -> Dictionary:
	var normalized_routes: Array[Dictionary] = []
	var valid: bool = not bundle_id.is_empty() and not cause.is_empty() \
			and not routes.is_empty()
	for raw_route in routes:
		if typeof(raw_route) != TYPE_DICTIONARY:
			valid = false
			continue
		var route: Dictionary = raw_route.duplicate(true)
		if not _atomic_route_is_valid(route):
			valid = false
		normalized_routes.append(route)
	return {
		"bundle_id": bundle_id,
		"cause": cause,
		"routes": normalized_routes,
		"metadata": metadata.duplicate(true),
		"valid": valid,
	}


func add_request(request: Dictionary) -> bool:
	var request_id: String = String(request.get("request_id", ""))
	var cause: String = String(request.get("cause", ""))
	if request_id.is_empty() or cause.is_empty():
		return false
	if _request_ids.has(request_id):
		_duplicate_owner_count += 1
		return false
	_request_ids[request_id] = true
	var record: Dictionary = request.duplicate(true)
	_requests.append(record)
	_transactions.append({"kind": "request", "value": record})
	return true


func _record_request_telemetry(request: Dictionary) -> void:
	_requests.append(request.duplicate(true))


func add_atomic_bundle(bundle: Dictionary) -> bool:
	var bundle_id: String = String(bundle.get("bundle_id", ""))
	if bundle_id.is_empty() or not bool(bundle.get("valid", false)):
		_atomic_invalid_bundle_count += 1
		return false
	if _atomic_bundle_ids.has(bundle_id):
		_atomic_duplicate_bundle_count += 1
		_duplicate_owner_count += 1
		return false
	_atomic_bundle_ids[bundle_id] = true
	var record: Dictionary = bundle.duplicate(true)
	_atomic_bundles.append(record)
	_transactions.append({"kind": "atomic_bundle", "value": record})
	return true


func finalize_step(building, reference_temp_c: float = 20.0) -> void:
	_results.clear()
	var shadow: Dictionary = _snapshots.duplicate(true)
	var rejected_by_room: Dictionary = {}
	var rejected_combustion_o2_by_room: Dictionary = {}
	var rejected_doorway_species_by_room: Dictionary = {}
	var rejected_transit_species_by_room: Dictionary = {}
	var rejected_immediate_species_by_room: Dictionary = {}
	for raw_transaction in _transactions:
		var transaction: Dictionary = raw_transaction
		match String(transaction.get("kind", "")):
			"request":
				_apply_request(
					shadow,
					transaction.get("value", {}),
					rejected_by_room,
					rejected_combustion_o2_by_room,
					rejected_doorway_species_by_room,
					rejected_transit_species_by_room,
					rejected_immediate_species_by_room
				)
			"atomic_bundle":
				_apply_atomic_bundle(
					shadow,
					transaction.get("value", {}),
					rejected_by_room,
					rejected_doorway_species_by_room,
					rejected_transit_species_by_room
				)
	if building == null:
		return
	if not _canonical_exterior_boundary_context.is_empty():
		_apply_canonical_exterior_boundary_requests(
			shadow,
			building,
			float(_canonical_exterior_boundary_context.get("dt", 0.0)),
			float(_canonical_exterior_boundary_context.get("reference_temp_c", reference_temp_c)),
			float(_canonical_exterior_boundary_context.get("outside_o2", 0.209)),
			float(_canonical_exterior_boundary_context.get("closed_leakage_area_m2", 0.0)),
			float(_canonical_exterior_boundary_context.get("pressure_threshold_pa", 0.0)),
			float(_canonical_exterior_boundary_context.get("discharge_coeff", EXTERIOR_DISCHARGE_COEFF)),
			rejected_by_room,
			rejected_doorway_species_by_room,
			rejected_transit_species_by_room
		)
	var inflight_transit_species: Dictionary = _inflight_transit_species()
	var transit_created_total_kg: float = _sum_parcel_species(_species_transit_created_kg)
	var transit_delivered_total_kg: float = _sum_parcel_species(_species_transit_delivered_kg)
	var transit_refunded_total_kg: float = _sum_parcel_species(_species_transit_refunded_kg)
	var transit_cancelled_total_kg: float = _sum_parcel_species(_species_transit_cancelled_kg)
	var transit_residual_kg: float = _species_transit_conservation_residual_kg()
	var parcel_atomic_inflight: Dictionary = _inflight_atomic_parcel_payload()
	var transit_residual_co_kg: float = float(_species_transit_created_kg.get("co", 0.0)) \
			- float(_species_transit_delivered_kg.get("co", 0.0)) \
			- float(_species_transit_refunded_kg.get("co", 0.0)) \
			- float(_species_transit_cancelled_kg.get("co", 0.0)) \
			- float(inflight_transit_species.get("co", 0.0))
	var transit_residual_co2_kg: float = float(_species_transit_created_kg.get("co2", 0.0)) \
			- float(_species_transit_delivered_kg.get("co2", 0.0)) \
			- float(_species_transit_refunded_kg.get("co2", 0.0)) \
			- float(_species_transit_cancelled_kg.get("co2", 0.0)) \
			- float(inflight_transit_species.get("co2", 0.0))
	var transit_residual_hcn_kg: float = float(_species_transit_created_kg.get("hcn", 0.0)) \
			- float(_species_transit_delivered_kg.get("hcn", 0.0)) \
			- float(_species_transit_refunded_kg.get("hcn", 0.0)) \
			- float(_species_transit_cancelled_kg.get("hcn", 0.0)) \
			- float(inflight_transit_species.get("hcn", 0.0))
	var parcel_atomic_mass_residual_kg: float = float(
		_parcel_atomic_created_payload.get("gas_mass_kg", 0.0)
	) - float(
		_parcel_atomic_delivered_payload.get("gas_mass_kg", 0.0)
	) - float(
		_parcel_atomic_refunded_payload.get("gas_mass_kg", 0.0)
	) - float(
		_parcel_atomic_cancelled_payload.get("gas_mass_kg", 0.0)
	) - float(parcel_atomic_inflight.get("gas_mass_kg", 0.0))
	var parcel_atomic_energy_residual_kj: float = float(
		_parcel_atomic_created_payload.get("sensible_enthalpy_kj", 0.0)
	) - float(
		_parcel_atomic_delivered_payload.get("sensible_enthalpy_kj", 0.0)
	) - float(
		_parcel_atomic_refunded_payload.get("sensible_enthalpy_kj", 0.0)
	) - float(
		_parcel_atomic_cancelled_payload.get("sensible_enthalpy_kj", 0.0)
	) - float(parcel_atomic_inflight.get("sensible_enthalpy_kj", 0.0))
	var parcel_atomic_o2_residual_kg: float = float(
		_parcel_atomic_created_payload.get("o2_kg", 0.0)
	) - float(
		_parcel_atomic_delivered_payload.get("o2_kg", 0.0)
	) - float(
		_parcel_atomic_refunded_payload.get("o2_kg", 0.0)
	) - float(
		_parcel_atomic_cancelled_payload.get("o2_kg", 0.0)
	) - float(parcel_atomic_inflight.get("o2_kg", 0.0))
	var parcel_atomic_species_residual_kg: float = _sum_parcel_species(
		_parcel_atomic_created_payload.get("species_kg", {})
	) - _sum_parcel_species(
		_parcel_atomic_delivered_payload.get("species_kg", {})
	) - _sum_parcel_species(
		_parcel_atomic_refunded_payload.get("species_kg", {})
	) - _sum_parcel_species(
		_parcel_atomic_cancelled_payload.get("species_kg", {})
	) - _sum_parcel_species(parcel_atomic_inflight.get("species_kg", {}))
	var immediate_co_residual_kg: float = float(
		_immediate_debited_species_kg_step.get("co", 0.0)
	) - float(_immediate_credited_species_kg_step.get("co", 0.0))
	var immediate_co2_residual_kg: float = float(
		_immediate_debited_species_kg_step.get("co2", 0.0)
	) - float(_immediate_credited_species_kg_step.get("co2", 0.0))
	var immediate_hcn_residual_kg: float = float(
		_immediate_debited_species_kg_step.get("hcn", 0.0)
	) - float(_immediate_credited_species_kg_step.get("hcn", 0.0))
	var vertical_co_residual_kg: float = float(
		_vertical_debited_species_kg_step.get("co", 0.0)
	) - float(_vertical_credited_species_kg_step.get("co", 0.0))
	var vertical_co2_residual_kg: float = float(
		_vertical_debited_species_kg_step.get("co2", 0.0)
	) - float(_vertical_credited_species_kg_step.get("co2", 0.0))
	var vertical_hcn_residual_kg: float = float(
		_vertical_debited_species_kg_step.get("hcn", 0.0)
	) - float(_vertical_credited_species_kg_step.get("hcn", 0.0))
	var semantic_summary: Dictionary = _semantic_conflict_summary()
	for room_key in shadow.keys():
		var room_id: int = int(room_key)
		var room: RoomModel = building.get_room(room_id)
		if room == null:
			continue
		var state: Dictionary = shadow[room_key]
		var legacy_mass_kg: float = room.zone_total_mass_kg()
		var legacy_energy_kj: float = room.zone_total_energy_kj()
		var mass_residual_kg: float = _state_mass(state) - legacy_mass_kg
		var energy_residual_kj: float = _state_energy(state) - legacy_energy_kj
		var upper_mass_residual_kg: float = float(state.get("upper_gas_kg", 0.0)) \
				- maxf(0.0, room.upper_gas_kg)
		var lower_mass_residual_kg: float = float(state.get("lower_gas_kg", 0.0)) \
				- maxf(0.0, room.lower_gas_kg)
		var upper_energy_residual_kj: float = float(state.get("upper_energy_kj", 0.0)) \
				- maxf(0.0, room.upper_energy_kj)
		var lower_energy_residual_kj: float = float(state.get("lower_energy_kj", 0.0)) \
				- maxf(0.0, room.lower_energy_kj)
		var thermo: Dictionary = derive_canonical_thermodynamic_state(
			float(state.get("upper_gas_kg", 0.0)),
			float(state.get("lower_gas_kg", 0.0)),
			float(state.get("upper_energy_kj", 0.0)),
			float(state.get("lower_energy_kj", 0.0)),
			room.volume_m3(),
			room.floor_area_m2(),
			room.height_m,
			reference_temp_c
		)
		var exterior_boundary: Dictionary = _canonical_exterior_boundary_by_room.get(
			room_key, _new_canonical_exterior_boundary_record()
		)
		_results[room_key] = {
			"phase3_shadow_upper_gas_kg": float(state.get("upper_gas_kg", 0.0)),
			"phase3_shadow_lower_gas_kg": float(state.get("lower_gas_kg", 0.0)),
			"phase3_shadow_upper_energy_kj": float(state.get("upper_energy_kj", 0.0)),
			"phase3_shadow_lower_energy_kj": float(state.get("lower_energy_kj", 0.0)),
			"phase3_shadow_mass_residual_kg": mass_residual_kg,
			"phase3_shadow_energy_residual_kj": energy_residual_kj,
			"phase3_shadow_upper_mass_residual_kg": upper_mass_residual_kg,
			"phase3_shadow_lower_mass_residual_kg": lower_mass_residual_kg,
			"phase3_shadow_upper_energy_residual_kj": upper_energy_residual_kj,
			"phase3_shadow_lower_energy_residual_kj": lower_energy_residual_kj,
			"phase3_shadow_thermo_valid_flag": 1.0 if bool(thermo.get("valid", false)) else 0.0,
			"phase3_shadow_thermo_failure_code": float(thermo.get("failure_code", 0.0)),
			"phase3_shadow_thermo_temp_upper_c": float(thermo.get("temp_upper_c", reference_temp_c)),
			"phase3_shadow_thermo_temp_lower_c": float(thermo.get("temp_lower_c", reference_temp_c)),
			"phase3_shadow_thermo_pressure_abs_pa": float(thermo.get("pressure_abs_pa", 0.0)),
			"phase3_shadow_thermo_pressure_gauge_pa": float(thermo.get("pressure_gauge_pa", 0.0)),
			"phase3_shadow_thermo_upper_volume_m3": float(thermo.get("upper_volume_m3", 0.0)),
			"phase3_shadow_thermo_lower_volume_m3": float(thermo.get("lower_volume_m3", 0.0)),
			"phase3_shadow_thermo_volume_closure_error_m3": float(
				thermo.get("volume_closure_error_m3", 0.0)
			),
			"phase3_shadow_thermo_interface_m": float(thermo.get("interface_m", 0.0)),
			"phase3_shadow_thermo_mass_invariance_residual_kg": float(
				thermo.get("mass_invariance_residual_kg", 0.0)
			),
			"phase3_shadow_thermo_energy_invariance_residual_kj": float(
				thermo.get("energy_invariance_residual_kj", 0.0)
			),
			"phase3_shadow_canonical_transaction_closure_flag": float(
				thermo.get("canonical_transaction_closure_flag", 0.0)
			),
			"phase3_shadow_legacy_state_mass_divergence_kg": mass_residual_kg,
			"phase3_shadow_legacy_state_energy_divergence_kj": energy_residual_kj,
			"phase3_shadow_legacy_interface_divergence_m": float(
				thermo.get("interface_m", 0.0)
			) - room.thermal_layer_m,
			"phase3_shadow_legacy_pressure_divergence_pa": float(
				thermo.get("pressure_gauge_pa", 0.0)
			) - room.overpressure_pa,
			"phase3_shadow_exterior_pressure_pre_pa": float(
				exterior_boundary.get("pressure_pre_pa", 0.0)
			),
			"phase3_shadow_exterior_requested_gas_kg": float(
				exterior_boundary.get("requested_gas_kg", 0.0)
			),
			"phase3_shadow_exterior_requested_energy_kj": float(
				exterior_boundary.get("requested_energy_kj", 0.0)
			),
			"phase3_shadow_exterior_requested_o2_kg": float(
				exterior_boundary.get("requested_o2_kg", 0.0)
			),
			"phase3_shadow_exterior_requested_species_kg": float(
				exterior_boundary.get("requested_species_kg", 0.0)
			),
			"phase3_shadow_exterior_accepted_gas_kg": float(
				exterior_boundary.get("accepted_gas_kg", 0.0)
			),
			"phase3_shadow_exterior_accepted_energy_kj": float(
				exterior_boundary.get("accepted_energy_kj", 0.0)
			),
			"phase3_shadow_exterior_accepted_o2_kg": float(
				exterior_boundary.get("accepted_o2_kg", 0.0)
			),
			"phase3_shadow_exterior_accepted_species_kg": float(
				exterior_boundary.get("accepted_species_kg", 0.0)
			),
			"phase3_shadow_exterior_post_upper_o2_kg": float(
				state.get("upper_o2_kg", 0.0)
			),
			"phase3_shadow_exterior_post_lower_o2_kg": float(
				state.get("lower_o2_kg", 0.0)
			),
			"phase3_shadow_exterior_post_upper_o2_fraction": clampf(float(
				state.get("upper_o2_kg", 0.0)
			) / maxf(THERMO_MASS_EPS_KG, float(state.get("upper_gas_kg", 0.0))), 0.0, 1.0),
			"phase3_shadow_exterior_post_lower_o2_fraction": clampf(float(
				state.get("lower_o2_kg", 0.0)
			) / maxf(THERMO_MASS_EPS_KG, float(state.get("lower_gas_kg", 0.0))), 0.0, 1.0),
			"phase3_shadow_exterior_rejected_gas_kg": float(
				exterior_boundary.get("rejected_gas_kg", 0.0)
			),
			"phase3_shadow_exterior_rejected_energy_kj": float(
				exterior_boundary.get("rejected_energy_kj", 0.0)
			),
			"phase3_shadow_exterior_rejected_o2_kg": float(
				exterior_boundary.get("rejected_o2_kg", 0.0)
			),
			"phase3_shadow_exterior_rejected_species_kg": float(
				exterior_boundary.get("rejected_species_kg", 0.0)
			),
			"phase3_shadow_exterior_direction": float(
				exterior_boundary.get("direction", 0.0)
			),
			"phase3_shadow_exterior_source_zone_code": float(
				exterior_boundary.get("source_zone_code", 0.0)
			),
			"phase3_shadow_exterior_event_count": float(
				exterior_boundary.get("event_count", 0.0)
			),
			"phase3_shadow_exterior_legacy_pressure_suppressed_event_count": float(
				exterior_boundary.get("legacy_pressure_suppressed_event_count", 0.0)
			),
			"phase3_shadow_exterior_accepted_fraction": float(
				exterior_boundary.get("accepted_fraction", 1.0)
			),
			"phase3_shadow_exterior_duplicate_owner_flag": float(
				exterior_boundary.get("duplicate_owner_flag", 0.0)
			),
			"phase3_shadow_exterior_mass_residual_kg": float(
				exterior_boundary.get("mass_residual_kg", 0.0)
			),
			"phase3_shadow_exterior_energy_residual_kj": float(
				exterior_boundary.get("energy_residual_kj", 0.0)
			),
			"phase3_shadow_exterior_o2_residual_kg": float(
				exterior_boundary.get("o2_residual_kg", 0.0)
			),
			"phase3_shadow_exterior_species_residual_kg": float(
				exterior_boundary.get("species_residual_kg", 0.0)
			),
			"phase3_shadow_request_count": _count_room_requests(room_id),
			"phase3_shadow_plume_mass_request_kg": _sum_room_cause_mass(
				room_id, "plume_entrainment"
			),
			"phase3_shadow_combustion_energy_request_kj": _sum_room_cause_energy(
				room_id, "combustion_convective_heat"
			),
			"phase3_shadow_combustion_o2_request_kg": _sum_room_cause_prefix_o2(
				room_id, "combustion_o2_"
			),
			"phase3_shadow_combustion_o2_rejected_kg": float(
				rejected_combustion_o2_by_room.get(room_key, 0.0)
			),
			"phase3_shadow_combustion_co_request_kg": _sum_room_cause_species(
				room_id, "combustion_species_source", "co"
			),
			"phase3_shadow_combustion_co2_request_kg": _sum_room_cause_species(
				room_id, "combustion_species_source", "co2"
			),
			"phase3_shadow_combustion_hcn_request_kg": _sum_room_cause_species(
				room_id, "combustion_species_source", "hcn"
			),
			# Combustion species originate in the exterior reservoir, so inventory
			# limiting cannot reject them. Keep the field explicit for future caps.
			"phase3_shadow_combustion_species_rejected_kg": 0.0,
			"phase3_shadow_doorway_co_request_kg": _sum_room_cause_species(
				room_id, "doorway_species_direct", "co"
			),
			"phase3_shadow_doorway_co2_request_kg": _sum_room_cause_species(
				room_id, "doorway_species_direct", "co2"
			),
			"phase3_shadow_doorway_hcn_request_kg": _sum_room_cause_species(
				room_id, "doorway_species_direct", "hcn"
			),
			"phase3_shadow_doorway_species_rejected_kg": float(
				rejected_doorway_species_by_room.get(room_key, 0.0)
			),
			"phase3_shadow_background_co_kg_total": float(
				_immediate_background_species_kg.get("co", 0.0)
			),
			"phase3_shadow_background_co2_kg_total": float(
				_immediate_background_species_kg.get("co2", 0.0)
			),
			"phase3_shadow_background_hcn_kg_total": float(
				_immediate_background_species_kg.get("hcn", 0.0)
			),
			"phase3_shadow_counterflow_co_kg_total": float(
				_immediate_counterflow_species_kg.get("co", 0.0)
			),
			"phase3_shadow_counterflow_co2_kg_total": float(
				_immediate_counterflow_species_kg.get("co2", 0.0)
			),
			"phase3_shadow_counterflow_hcn_kg_total": float(
				_immediate_counterflow_species_kg.get("hcn", 0.0)
			),
			"phase3_shadow_immediate_transfer_count": float(_immediate_transfer_count),
			"phase3_shadow_immediate_rejected_kg_total": _immediate_rejected_kg_total,
			"phase3_shadow_immediate_co_residual_kg": immediate_co_residual_kg,
			"phase3_shadow_immediate_co2_residual_kg": immediate_co2_residual_kg,
			"phase3_shadow_immediate_hcn_residual_kg": immediate_hcn_residual_kg,
			"phase3_shadow_vertical_net_co_kg_total": float(
				_vertical_net_species_kg.get("co", 0.0)
			),
			"phase3_shadow_vertical_net_co2_kg_total": float(
				_vertical_net_species_kg.get("co2", 0.0)
			),
			"phase3_shadow_vertical_net_hcn_kg_total": float(
				_vertical_net_species_kg.get("hcn", 0.0)
			),
			"phase3_shadow_vertical_directed_co_kg_total": float(
				_vertical_directed_species_kg.get("co", 0.0)
			),
			"phase3_shadow_vertical_directed_co2_kg_total": float(
				_vertical_directed_species_kg.get("co2", 0.0)
			),
			"phase3_shadow_vertical_directed_hcn_kg_total": float(
				_vertical_directed_species_kg.get("hcn", 0.0)
			),
			"phase3_shadow_vertical_transfer_count": float(_vertical_transfer_count),
			"phase3_shadow_vertical_rejected_kg_total": _vertical_rejected_kg_total,
			"phase3_shadow_vertical_opposed_zone_direction_count": float(
				_vertical_opposed_zone_direction_count
			),
			"phase3_shadow_vertical_co_residual_kg": vertical_co_residual_kg,
			"phase3_shadow_vertical_co2_residual_kg": vertical_co2_residual_kg,
			"phase3_shadow_vertical_hcn_residual_kg": vertical_hcn_residual_kg,
			"phase3_shadow_thermal_co_kg_total": float(
				_thermal_species_requested_kg.get("co", 0.0)
			),
			"phase3_shadow_thermal_co2_kg_total": float(
				_thermal_species_requested_kg.get("co2", 0.0)
			),
			"phase3_shadow_thermal_hcn_kg_total": float(
				_thermal_species_requested_kg.get("hcn", 0.0)
			),
			"phase3_shadow_thermal_source_upper_co_kg_total": float(
				_thermal_species_source_upper_kg.get("co", 0.0)
			),
			"phase3_shadow_thermal_source_upper_co2_kg_total": float(
				_thermal_species_source_upper_kg.get("co2", 0.0)
			),
			"phase3_shadow_thermal_source_upper_hcn_kg_total": float(
				_thermal_species_source_upper_kg.get("hcn", 0.0)
			),
			"phase3_shadow_thermal_source_lower_co_kg_total": _thermal_species_lower_for(
				"co", _thermal_species_source_upper_kg
			),
			"phase3_shadow_thermal_source_lower_co2_kg_total": _thermal_species_lower_for(
				"co2", _thermal_species_source_upper_kg
			),
			"phase3_shadow_thermal_source_lower_hcn_kg_total": _thermal_species_lower_for(
				"hcn", _thermal_species_source_upper_kg
			),
			"phase3_shadow_thermal_destination_upper_co_kg_total": float(
				_thermal_species_destination_upper_kg.get("co", 0.0)
			),
			"phase3_shadow_thermal_destination_upper_co2_kg_total": float(
				_thermal_species_destination_upper_kg.get("co2", 0.0)
			),
			"phase3_shadow_thermal_destination_upper_hcn_kg_total": float(
				_thermal_species_destination_upper_kg.get("hcn", 0.0)
			),
			"phase3_shadow_thermal_destination_lower_co_kg_total": _thermal_species_lower_for(
				"co", _thermal_species_destination_upper_kg
			),
			"phase3_shadow_thermal_destination_lower_co2_kg_total": _thermal_species_lower_for(
				"co2", _thermal_species_destination_upper_kg
			),
			"phase3_shadow_thermal_destination_lower_hcn_kg_total": _thermal_species_lower_for(
				"hcn", _thermal_species_destination_upper_kg
			),
			"phase3_shadow_thermal_applied_co_kg_total": float(
				_thermal_species_applied_kg.get("co", 0.0)
			),
			"phase3_shadow_thermal_applied_co2_kg_total": float(
				_thermal_species_applied_kg.get("co2", 0.0)
			),
			"phase3_shadow_thermal_applied_hcn_kg_total": float(
				_thermal_species_applied_kg.get("hcn", 0.0)
			),
			"phase3_shadow_thermal_rejected_co_kg_total": float(
				_thermal_species_rejected_kg.get("co", 0.0)
			),
			"phase3_shadow_thermal_rejected_co2_kg_total": float(
				_thermal_species_rejected_kg.get("co2", 0.0)
			),
			"phase3_shadow_thermal_rejected_hcn_kg_total": float(
				_thermal_species_rejected_kg.get("hcn", 0.0)
			),
			"phase3_shadow_thermal_event_count": float(_thermal_species_event_count),
			"phase3_shadow_thermal_duplicate_event_count": float(
				_thermal_species_duplicate_event_count
			),
			"phase3_shadow_thermal_co_residual_kg": _thermal_species_residual_for("co"),
			"phase3_shadow_thermal_co2_residual_kg": _thermal_species_residual_for("co2"),
			"phase3_shadow_thermal_hcn_residual_kg": _thermal_species_residual_for("hcn"),
			"phase3_shadow_thermal_semantic_suppressed_kg_total": _sum_transit_species(
				_thermal_species_semantic_suppressed_kg
			),
			"phase3_shadow_thermal_doorway_kg_total": _thermal_species_mechanism_total(
				"doorway_hot_gas"
			),
			"phase3_shadow_thermal_outside_background_kg_total": _thermal_species_mechanism_total(
				"outside_assisted_background_heat"
			),
			"phase3_shadow_thermal_interior_background_kg_total": _thermal_species_mechanism_total(
				"interior_background_heat"
			),
			"phase3_shadow_thermal_interlayer_kg_total": _thermal_species_mechanism_total(
				"co_interlayer_mixing"
			),
			"phase3_shadow_purge_co_out_kg_total": float(
				_exterior_purge_requested_species_kg.get("co", 0.0)
			),
			"phase3_shadow_purge_co2_out_kg_total": float(
				_exterior_purge_requested_species_kg.get("co2", 0.0)
			),
			"phase3_shadow_purge_hcn_out_kg_total": float(
				_exterior_purge_requested_species_kg.get("hcn", 0.0)
			),
			"phase3_shadow_purge_upper_co_kg_total": float(
				_exterior_purge_upper_species_kg.get("co", 0.0)
			),
			"phase3_shadow_purge_upper_co2_kg_total": float(
				_exterior_purge_upper_species_kg.get("co2", 0.0)
			),
			"phase3_shadow_purge_upper_hcn_kg_total": float(
				_exterior_purge_upper_species_kg.get("hcn", 0.0)
			),
			"phase3_shadow_purge_lower_co_kg_total": _exterior_purge_lower_for("co"),
			"phase3_shadow_purge_lower_co2_kg_total": _exterior_purge_lower_for("co2"),
			"phase3_shadow_purge_lower_hcn_kg_total": _exterior_purge_lower_for("hcn"),
			"phase3_shadow_purge_applied_kg_total": _sum_transit_species(
				_exterior_purge_applied_species_kg
			),
			"phase3_shadow_purge_rejected_kg_total": _sum_transit_species(
				_exterior_purge_rejected_species_kg
			),
			"phase3_shadow_purge_event_count": float(_exterior_purge_event_count),
			"phase3_shadow_purge_duplicate_event_count": float(
				_exterior_purge_duplicate_event_count
			),
			"phase3_shadow_purge_co_residual_kg": _exterior_purge_residual_for("co"),
			"phase3_shadow_purge_co2_residual_kg": _exterior_purge_residual_for("co2"),
			"phase3_shadow_purge_hcn_residual_kg": _exterior_purge_residual_for("hcn"),
			"phase3_shadow_purge_pressure_kg_total": _exterior_purge_mechanism_total(
				"pressure_venting"
			),
			"phase3_shadow_purge_smoke_vent_kg_total": _exterior_purge_mechanism_total(
				"exterior_smoke_vent"
			),
			"phase3_shadow_purge_natural_vent_kg_total": _exterior_purge_mechanism_total(
				"natural_ventilation"
			),
			"phase3_shadow_purge_ach_kg_total": _exterior_purge_mechanism_total(
				"ach_infiltration"
			),
			"phase3_shadow_purge_outside_open_kg_total": _exterior_purge_mechanism_total(
				"outside_open_species_purge"
			),
			"phase3_shadow_purge_postfire_kg_total": _exterior_purge_mechanism_total(
				"postfire_species_purge"
			),
			"phase3_shadow_purge_ppv_inlet_kg_total": _exterior_purge_mechanism_total(
				"ppv_inlet_dilution"
			),
			"phase3_shadow_purge_ppv_exhaust_kg_total": _exterior_purge_mechanism_total(
				"ppv_exhaust"
			),
			"phase3_shadow_species_inflight_co_kg": float(
				inflight_transit_species.get("co", 0.0)
			),
			"phase3_shadow_species_inflight_co2_kg": float(
				inflight_transit_species.get("co2", 0.0)
			),
			"phase3_shadow_species_inflight_hcn_kg": float(
				inflight_transit_species.get("hcn", 0.0)
			),
			"phase3_shadow_species_created_kg_total": transit_created_total_kg,
			"phase3_shadow_species_delivered_kg_total": transit_delivered_total_kg,
			"phase3_shadow_species_refunded_kg_total": transit_refunded_total_kg,
			"phase3_shadow_species_cancelled_kg_total": transit_cancelled_total_kg,
			"phase3_shadow_species_active_parcel_count": float(
				_species_transit_reservoir.size()
			),
			"phase3_shadow_species_orphan_delivery_count": float(
				_species_transit_orphan_delivery_count
			),
			"phase3_shadow_species_duplicate_id_count": float(
				_species_transit_duplicate_id_count
			),
			"phase3_shadow_species_negative_balance_count": float(
				_species_transit_negative_balance_count
			),
			"phase3_shadow_species_conservation_residual_kg": transit_residual_kg,
			"phase3_shadow_species_conservation_residual_co_kg": transit_residual_co_kg,
			"phase3_shadow_species_conservation_residual_co2_kg": transit_residual_co2_kg,
			"phase3_shadow_species_conservation_residual_hcn_kg": transit_residual_hcn_kg,
			"phase3_shadow_species_transit_rejected_kg": float(
				rejected_transit_species_by_room.get(room_key, 0.0)
			),
			"phase3_shadow_parcel_atomic_inflight_gas_kg": float(
				parcel_atomic_inflight.get("gas_mass_kg", 0.0)
			),
			"phase3_shadow_parcel_atomic_inflight_energy_kj": float(
				parcel_atomic_inflight.get("sensible_enthalpy_kj", 0.0)
			),
			"phase3_shadow_parcel_atomic_inflight_o2_kg": float(
				parcel_atomic_inflight.get("o2_kg", 0.0)
			),
			"phase3_shadow_parcel_atomic_inflight_species_kg": _sum_parcel_species(
				parcel_atomic_inflight.get("species_kg", {})
			),
			"phase3_shadow_parcel_atomic_created_gas_kg_total": float(
				_parcel_atomic_created_payload.get("gas_mass_kg", 0.0)
			),
			"phase3_shadow_parcel_atomic_delivered_gas_kg_total": float(
				_parcel_atomic_delivered_payload.get("gas_mass_kg", 0.0)
			),
			"phase3_shadow_parcel_atomic_refunded_gas_kg_total": float(
				_parcel_atomic_refunded_payload.get("gas_mass_kg", 0.0)
			),
			"phase3_shadow_parcel_atomic_cancelled_gas_kg_total": float(
				_parcel_atomic_cancelled_payload.get("gas_mass_kg", 0.0)
			),
			"phase3_shadow_parcel_atomic_created_energy_kj_total": float(
				_parcel_atomic_created_payload.get("sensible_enthalpy_kj", 0.0)
			),
			"phase3_shadow_parcel_atomic_delivered_energy_kj_total": float(
				_parcel_atomic_delivered_payload.get("sensible_enthalpy_kj", 0.0)
			),
			"phase3_shadow_parcel_atomic_refunded_energy_kj_total": float(
				_parcel_atomic_refunded_payload.get("sensible_enthalpy_kj", 0.0)
			),
			"phase3_shadow_parcel_atomic_cancelled_energy_kj_total": float(
				_parcel_atomic_cancelled_payload.get("sensible_enthalpy_kj", 0.0)
			),
			"phase3_shadow_parcel_atomic_created_o2_kg_total": float(
				_parcel_atomic_created_payload.get("o2_kg", 0.0)
			),
			"phase3_shadow_parcel_atomic_delivered_o2_kg_total": float(
				_parcel_atomic_delivered_payload.get("o2_kg", 0.0)
			),
			"phase3_shadow_parcel_atomic_refunded_o2_kg_total": float(
				_parcel_atomic_refunded_payload.get("o2_kg", 0.0)
			),
			"phase3_shadow_parcel_atomic_cancelled_o2_kg_total": float(
				_parcel_atomic_cancelled_payload.get("o2_kg", 0.0)
			),
			"phase3_shadow_parcel_atomic_mass_residual_kg": \
				parcel_atomic_mass_residual_kg,
			"phase3_shadow_parcel_atomic_energy_residual_kj": \
				parcel_atomic_energy_residual_kj,
			"phase3_shadow_parcel_atomic_o2_residual_kg": parcel_atomic_o2_residual_kg,
			"phase3_shadow_parcel_atomic_species_residual_kg": \
				parcel_atomic_species_residual_kg,
			"phase3_shadow_parcel_atomic_unfinalized_resolution_count": float(
				_parcel_atomic_unfinalized_resolution_count
			),
			# Bit mask: energy=1, O2=2, species=4. Bulk O2 remains unowned.
			"phase3_shadow_combustion_owned_mask": _combustion_owned_mask(room_id),
			"phase3_shadow_owned_cause_count": _count_room_causes(room_id),
			"phase3_shadow_rejected_mass_kg": float(rejected_by_room.get(room_key, 0.0)),
			"phase3_shadow_duplicate_owner_flag": 1.0 if _duplicate_owner_count > 0 else 0.0,
			"phase3_shadow_zero_o2_flame_flag": 1.0 \
					if room.hrr_kw > 0.5 and (
						room.fire_o2_ref < room.fire_o2_min_ref or room.o2_upper < 0.05
					) else 0.0,
			"phase3_shadow_needs_flux_owner_flag": 1.0 \
					if absf(mass_residual_kg) > 1.0e-6 or absf(energy_residual_kj) > 1.0e-4 else 0.0,
			"phase3_shadow_semantic_claim_count": float(
				semantic_summary.get("claim_count", 0)
			),
			"phase3_shadow_semantic_conflict_count": float(
				semantic_summary.get("conflict_count", 0)
			),
			"phase3_shadow_semantic_conflict_quantity_mask": float(
				semantic_summary.get("quantity_mask", 0)
			),
			"phase3_shadow_semantic_conflict_mass_kg": float(
				semantic_summary.get("conflict_mass_kg", 0.0)
			),
			"phase3_shadow_semantic_conflict_energy_kj": float(
				semantic_summary.get("conflict_energy_kj", 0.0)
			),
			"phase3_shadow_semantic_conflict_o2_kg": float(
				semantic_summary.get("conflict_o2_kg", 0.0)
			),
			"phase3_shadow_semantic_conflict_species_kg": float(
				semantic_summary.get("conflict_species_kg", 0.0)
			),
			"phase3_shadow_semantic_unknown_connection_count": float(
				semantic_summary.get("unknown_connection_count", 0)
			),
			"phase3_shadow_semantic_accepted_claim_count": float(
				semantic_summary.get("accepted_claim_count", 0)
			),
			"phase3_shadow_semantic_suppressed_claim_count": float(
				semantic_summary.get("suppressed_claim_count", 0)
			),
			"phase3_shadow_semantic_unresolved_claim_count": float(
				semantic_summary.get("unresolved_claim_count", 0)
			),
			"phase3_shadow_semantic_suppressed_quantity_mask": float(
				semantic_summary.get("suppressed_quantity_mask", 0)
			),
			"phase3_shadow_semantic_unresolved_quantity_mask": float(
				semantic_summary.get("unresolved_quantity_mask", 0)
			),
			"phase3_shadow_semantic_suppressed_species_kg": float(
				semantic_summary.get("suppressed_species_kg", 0.0)
			),
			"phase3_shadow_semantic_unresolved_mass_kg": float(
				semantic_summary.get("unresolved_mass_kg", 0.0)
			),
			"phase3_shadow_semantic_unresolved_energy_kj": float(
				semantic_summary.get("unresolved_energy_kj", 0.0)
			),
			"phase3_shadow_semantic_unresolved_o2_kg": float(
				semantic_summary.get("unresolved_o2_kg", 0.0)
			),
			"phase3_shadow_semantic_unresolved_species_kg": float(
				semantic_summary.get("unresolved_species_kg", 0.0)
			),
			"phase3_shadow_semantic_unresolved_conflict_count": float(
				semantic_summary.get("unresolved_conflict_count", 0)
			),
			"phase3_shadow_atomic_bundle_count": float(_atomic_bundle_count),
			"phase3_shadow_atomic_route_count": float(_atomic_route_count),
			"phase3_shadow_atomic_min_accepted_fraction": \
					_atomic_min_accepted_fraction,
			"phase3_shadow_atomic_rejected_mass_kg": _atomic_rejected_mass_kg,
			"phase3_shadow_atomic_rejected_energy_kj": _atomic_rejected_energy_kj,
			"phase3_shadow_atomic_rejected_o2_kg": _atomic_rejected_o2_kg,
			"phase3_shadow_atomic_rejected_species_kg": \
					_atomic_rejected_species_kg,
			"phase3_shadow_atomic_duplicate_bundle_count": float(
				_atomic_duplicate_bundle_count
			),
			"phase3_shadow_atomic_invalid_bundle_count": float(
				_atomic_invalid_bundle_count
			),
			"phase3_shadow_co_oxidation_co_sink_kg_step": _co_oxidation_co_sink_kg,
			"phase3_shadow_co_oxidation_co2_source_kg_step": _co_oxidation_co2_source_kg,
			"phase3_shadow_co_oxidation_carbon_residual_kg_step": \
					_co_oxidation_carbon_residual_kg,
			"phase3_shadow_co_oxidation_o2_sink_kg_step": _co_oxidation_o2_sink_kg,
			"phase3_shadow_co_oxidation_accepted_fraction": \
					_co_oxidation_accepted_fraction,
			"phase3_shadow_co_oxidation_accepted_co_sink_kg_step": \
					_co_oxidation_accepted_co_sink_kg,
			"phase3_shadow_co_oxidation_accepted_co2_source_kg_step": \
					_co_oxidation_accepted_co2_source_kg,
			"phase3_shadow_co_oxidation_accepted_o2_sink_kg_step": \
					_co_oxidation_accepted_o2_sink_kg,
			"phase3_shadow_co_oxidation_o2_rejected_kg_step": \
					_co_oxidation_o2_rejected_kg,
			"phase3_shadow_co_oxidation_oxygen_residual_kg_step": \
					_co_oxidation_oxygen_residual_kg,
			"phase3_shadow_co_oxidation_legacy_lower_co2_kg_step": \
					_co_oxidation_legacy_lower_co2_kg,
		}


func get_results() -> Dictionary:
	return _results.duplicate(true)


func get_request_count() -> int:
	return _requests.size()


func _snapshot_room(room: RoomModel) -> Dictionary:
	return {
		"upper_gas_kg": maxf(0.0, room.upper_gas_kg),
		"lower_gas_kg": maxf(0.0, room.lower_gas_kg),
		"upper_energy_kj": maxf(0.0, room.upper_energy_kj),
		"lower_energy_kj": maxf(0.0, room.lower_energy_kj),
		"upper_o2_kg": maxf(0.0, room.upper_gas_kg * room.o2_upper),
		"lower_o2_kg": maxf(0.0, room.lower_gas_kg * room.o2_lower),
		"upper_species_kg": {
			"smoke": maxf(0.0, room.smoke_kg),
			"co": maxf(0.0, room.co_upper_kg),
			"co2": maxf(0.0, room.co2_upper_kg),
			"hcn": maxf(0.0, room.hcn_upper_kg),
			"hcl": maxf(0.0, room.hcl_kg),
			"acrolein": maxf(0.0, room.acrolein_kg),
			"formaldehyde": maxf(0.0, room.formaldehyde_kg),
		},
		"lower_species_kg": {
			"smoke": 0.0,
			"co": maxf(0.0, room.co_kg - room.co_upper_kg),
			"co2": maxf(0.0, room.co2_kg - room.co2_upper_kg),
			"hcn": maxf(0.0, room.hcn_kg - room.hcn_upper_kg),
			"hcl": 0.0,
			"acrolein": 0.0,
			"formaldehyde": 0.0,
		},
	}


func _atomic_route_is_valid(route: Dictionary) -> bool:
	if not bool(route.get("valid", true)):
		return false
	if String(route.get("route_id", "")).is_empty() \
			or String(route.get("cause", "")).is_empty():
		return false
	var source_id: int = int(route.get("source_room_id", EXTERIOR_ID))
	var destination_id: int = int(route.get("destination_room_id", EXTERIOR_ID))
	if source_id == EXTERIOR_ID and destination_id == EXTERIOR_ID:
		return false
	var source_zone: String = String(route.get("source_zone", ""))
	var destination_zone: String = String(route.get("destination_zone", ""))
	if source_zone not in [ZONE_UPPER, ZONE_LOWER] \
			or destination_zone not in [ZONE_UPPER, ZONE_LOWER]:
		return false
	for quantity_name in ["gas_mass_kg", "sensible_enthalpy_kj", "o2_kg"]:
		if float(route.get(quantity_name, 0.0)) < 0.0:
			return false
	var raw_species = route.get("species_kg", {})
	if typeof(raw_species) != TYPE_DICTIONARY:
		return false
	for raw_species_name in raw_species.keys():
		if String(raw_species_name) not in PARCEL_SPECIES \
				or float(raw_species.get(raw_species_name, 0.0)) < 0.0:
			return false
	return float(route.get("gas_mass_kg", 0.0)) > 0.0 \
			or float(route.get("sensible_enthalpy_kj", 0.0)) > 0.0 \
			or float(route.get("o2_kg", 0.0)) > 0.0 \
			or _sum_parcel_species(raw_species) > 0.0


func _apply_atomic_bundle(
		shadow: Dictionary,
		bundle: Dictionary,
		rejected_by_room: Dictionary,
		rejected_doorway_species_by_room: Dictionary,
		rejected_transit_species_by_room: Dictionary
	) -> void:
	if not bool(bundle.get("valid", false)):
		_atomic_invalid_bundle_count += 1
		return
	var routes: Array = bundle.get("routes", [])
	if routes.is_empty():
		_atomic_invalid_bundle_count += 1
		return
	var source_demands: Dictionary = {}
	for raw_route in routes:
		if typeof(raw_route) != TYPE_DICTIONARY:
			_atomic_invalid_bundle_count += 1
			return
		var route: Dictionary = raw_route
		if not _atomic_route_is_valid(route):
			_atomic_invalid_bundle_count += 1
			return
		var source_id: int = int(route.get("source_room_id", EXTERIOR_ID))
		var destination_id: int = int(route.get("destination_room_id", EXTERIOR_ID))
		if (source_id != EXTERIOR_ID and not shadow.has(str(source_id))) \
				or (destination_id != EXTERIOR_ID and not shadow.has(str(destination_id))):
			_atomic_invalid_bundle_count += 1
			return
		if source_id == EXTERIOR_ID:
			continue
		var source_zone: String = String(route.get("source_zone", ZONE_UPPER))
		var demand_key: String = "%d|%s" % [source_id, source_zone]
		var demand: Dictionary = source_demands.get(demand_key, {
			"room_id": source_id,
			"zone": source_zone,
			"gas_mass_kg": 0.0,
			"sensible_enthalpy_kj": 0.0,
			"o2_kg": 0.0,
			"species_kg": _parcel_species({}),
		})
		demand["gas_mass_kg"] = float(demand.get("gas_mass_kg", 0.0)) \
				+ float(route.get("gas_mass_kg", 0.0))
		demand["sensible_enthalpy_kj"] = float(
			demand.get("sensible_enthalpy_kj", 0.0)
		) + float(route.get("sensible_enthalpy_kj", 0.0))
		demand["o2_kg"] = float(demand.get("o2_kg", 0.0)) \
				+ float(route.get("o2_kg", 0.0))
		var demand_species: Dictionary = demand.get("species_kg", {})
		_add_parcel_species(demand_species, route.get("species_kg", {}))
		demand["species_kg"] = demand_species
		source_demands[demand_key] = demand

	var accepted_fraction: float = 1.0
	for raw_demand in source_demands.values():
		var demand: Dictionary = raw_demand
		var source_key: String = str(int(demand.get("room_id", EXTERIOR_ID)))
		if not shadow.has(source_key):
			accepted_fraction = 0.0
			break
		var source: Dictionary = shadow[source_key]
		var zone: String = String(demand.get("zone", ZONE_UPPER))
		accepted_fraction = _limit_atomic_fraction(
			accepted_fraction,
			float(source.get(zone + "_gas_kg", 0.0)),
			float(demand.get("gas_mass_kg", 0.0))
		)
		accepted_fraction = _limit_atomic_fraction(
			accepted_fraction,
			float(source.get(zone + "_energy_kj", 0.0)),
			float(demand.get("sensible_enthalpy_kj", 0.0))
		)
		accepted_fraction = _limit_atomic_fraction(
			accepted_fraction,
			float(source.get(zone + "_o2_kg", 0.0)),
			float(demand.get("o2_kg", 0.0))
		)
		var source_species: Dictionary = source.get(zone + "_species_kg", {})
		var requested_species: Dictionary = demand.get("species_kg", {})
		for species_name in PARCEL_SPECIES:
			accepted_fraction = _limit_atomic_fraction(
				accepted_fraction,
				float(source_species.get(species_name, 0.0)),
				float(requested_species.get(species_name, 0.0))
			)
	accepted_fraction = clampf(accepted_fraction, 0.0, 1.0)

	_atomic_bundle_count += 1
	_atomic_route_count += routes.size()
	if _atomic_bundle_count == 1:
		_atomic_min_accepted_fraction = accepted_fraction
	else:
		_atomic_min_accepted_fraction = minf(
			_atomic_min_accepted_fraction, accepted_fraction
		)
	var rejected_fraction: float = 1.0 - accepted_fraction
	for raw_route in routes:
		var route: Dictionary = raw_route
		_atomic_rejected_mass_kg += float(route.get("gas_mass_kg", 0.0)) \
				* rejected_fraction
		_atomic_rejected_energy_kj += float(
			route.get("sensible_enthalpy_kj", 0.0)
		) * rejected_fraction
		_atomic_rejected_o2_kg += float(route.get("o2_kg", 0.0)) \
				* rejected_fraction
		_atomic_rejected_species_kg += _sum_parcel_species(
			route.get("species_kg", {})
		) * rejected_fraction
		_apply_atomic_route(shadow, route, accepted_fraction)
	for raw_demand in source_demands.values():
		var demand: Dictionary = raw_demand
		var source_key: String = str(int(demand.get("room_id", EXTERIOR_ID)))
		rejected_by_room[source_key] = float(rejected_by_room.get(source_key, 0.0)) \
				+ float(demand.get("gas_mass_kg", 0.0)) * rejected_fraction
		var metadata: Dictionary = bundle.get("metadata", {})
		if String(metadata.get("transport_family", "")) == "doorway_bulk":
			rejected_doorway_species_by_room[source_key] = float(
				rejected_doorway_species_by_room.get(source_key, 0.0)
			) + _sum_parcel_species(demand.get("species_kg", {})) * rejected_fraction
		elif String(metadata.get("transport_family", "")) == "delayed_parcel":
			rejected_transit_species_by_room[source_key] = float(
				rejected_transit_species_by_room.get(source_key, 0.0)
			) + _sum_parcel_species(demand.get("species_kg", {})) * rejected_fraction
	_record_atomic_bundle_result(bundle, accepted_fraction)


func _limit_atomic_fraction(
		current_fraction: float,
		available: float,
		requested: float
	) -> float:
	if requested <= 0.0:
		return current_fraction
	return minf(current_fraction, maxf(0.0, available) / requested)


func _apply_atomic_route(
		shadow: Dictionary,
		route: Dictionary,
		accepted_fraction: float
	) -> void:
	var source_id: int = int(route.get("source_room_id", EXTERIOR_ID))
	var destination_id: int = int(route.get("destination_room_id", EXTERIOR_ID))
	var source_zone: String = String(route.get("source_zone", ZONE_UPPER))
	var destination_zone: String = String(route.get("destination_zone", ZONE_UPPER))
	var moved_mass_kg: float = float(route.get("gas_mass_kg", 0.0)) \
			* accepted_fraction
	var moved_energy_kj: float = float(route.get("sensible_enthalpy_kj", 0.0)) \
			* accepted_fraction
	var moved_o2_kg: float = float(route.get("o2_kg", 0.0)) * accepted_fraction
	var moved_species: Dictionary = _parcel_species(route.get("species_kg", {}))
	if source_id != EXTERIOR_ID:
		var source_key: String = str(source_id)
		var source: Dictionary = shadow[source_key]
		source[source_zone + "_gas_kg"] = maxf(
			0.0, float(source.get(source_zone + "_gas_kg", 0.0)) - moved_mass_kg
		)
		source[source_zone + "_energy_kj"] = maxf(
			0.0, float(source.get(source_zone + "_energy_kj", 0.0)) - moved_energy_kj
		)
		source[source_zone + "_o2_kg"] = maxf(
			0.0, float(source.get(source_zone + "_o2_kg", 0.0)) - moved_o2_kg
		)
		var source_species: Dictionary = source.get(source_zone + "_species_kg", {})
		for species_name in PARCEL_SPECIES:
			source_species[species_name] = maxf(
				0.0,
				float(source_species.get(species_name, 0.0))
						- float(moved_species.get(species_name, 0.0)) * accepted_fraction
			)
		source[source_zone + "_species_kg"] = source_species
		shadow[source_key] = source
	if destination_id != EXTERIOR_ID:
		var destination_key: String = str(destination_id)
		var destination: Dictionary = shadow[destination_key]
		destination[destination_zone + "_gas_kg"] = float(
			destination.get(destination_zone + "_gas_kg", 0.0)
		) + moved_mass_kg
		destination[destination_zone + "_energy_kj"] = float(
			destination.get(destination_zone + "_energy_kj", 0.0)
		) + moved_energy_kj
		destination[destination_zone + "_o2_kg"] = float(
			destination.get(destination_zone + "_o2_kg", 0.0)
		) + moved_o2_kg
		var destination_species: Dictionary = destination.get(
			destination_zone + "_species_kg", {}
		)
		for species_name in PARCEL_SPECIES:
			destination_species[species_name] = float(
				destination_species.get(species_name, 0.0)
			) + float(moved_species.get(species_name, 0.0)) * accepted_fraction
		destination[destination_zone + "_species_kg"] = destination_species
		shadow[destination_key] = destination


func _record_atomic_bundle_result(bundle: Dictionary, accepted_fraction: float) -> void:
	var metadata: Dictionary = bundle.get("metadata", {})
	var result_kind: String = String(metadata.get("kind", ""))
	if result_kind == "canonical_exterior_boundary":
		var room_key: String = str(int(metadata.get("room_id", EXTERIOR_ID)))
		var record: Dictionary = _canonical_exterior_boundary_by_room.get(
			room_key, _new_canonical_exterior_boundary_record()
		)
		var totals: Dictionary = metadata.get("requested_totals", {})
		var accepted: float = clampf(accepted_fraction, 0.0, 1.0)
		var rejected: float = 1.0 - accepted
		record["accepted_fraction"] = accepted
		for quantity_name in ["gas", "energy", "o2", "species"]:
			var metadata_key: String = {
				"gas": "gas_mass_kg",
				"energy": "sensible_enthalpy_kj",
				"o2": "o2_kg",
				"species": "species_kg",
			}[quantity_name]
			var requested_value: float = maxf(
				0.0, float(totals.get(metadata_key, 0.0))
			)
			var suffix: String = "_kg" if quantity_name != "energy" else "_kj"
			record["accepted_" + quantity_name + suffix] = requested_value * accepted
			record["rejected_" + quantity_name + suffix] = requested_value * rejected
			record[quantity_name + "_residual" + suffix] = requested_value \
					- float(record["accepted_" + quantity_name + suffix]) \
					- float(record["rejected_" + quantity_name + suffix])
		_canonical_exterior_boundary_by_room[room_key] = record
		return
	if result_kind == "delayed_parcel_carve":
		var parcel_id: String = String(metadata.get("parcel_id", ""))
		if not _species_transit_reservoir.has(parcel_id):
			_species_transit_orphan_delivery_count += 1
			return
		var stored: Dictionary = _species_transit_reservoir[parcel_id]
		stored["accepted_fraction"] = clampf(accepted_fraction, 0.0, 1.0)
		_species_transit_reservoir[parcel_id] = stored
		_add_parcel_payload(
			_parcel_atomic_created_payload,
			_scaled_parcel_payload(stored, accepted_fraction)
		)
		return
	if result_kind != "co_oxidation":
		return
	var requested_co_kg: float = maxf(
		0.0, float(metadata.get("co_consumed_kg", 0.0))
	)
	var requested_co2_kg: float = maxf(
		0.0, float(metadata.get("co2_generated_kg", 0.0))
	)
	var requested_o2_kg: float = maxf(
		0.0, float(metadata.get("o2_consumed_kg", 0.0))
	)
	_co_oxidation_accepted_fraction = minf(
		_co_oxidation_accepted_fraction, accepted_fraction
	)
	var accepted_co_kg: float = requested_co_kg * accepted_fraction
	var accepted_co2_kg: float = requested_co2_kg * accepted_fraction
	var accepted_o2_kg: float = requested_o2_kg * accepted_fraction
	_co_oxidation_accepted_co_sink_kg += accepted_co_kg
	_co_oxidation_accepted_co2_source_kg += accepted_co2_kg
	_co_oxidation_accepted_o2_sink_kg += accepted_o2_kg
	_co_oxidation_o2_rejected_kg += requested_o2_kg - accepted_o2_kg
	_co_oxidation_oxygen_residual_kg += accepted_co_kg * (16.0 / 28.0) \
			- accepted_o2_kg


func _apply_request(
		shadow: Dictionary,
		request: Dictionary,
		rejected_by_room: Dictionary,
		rejected_combustion_o2_by_room: Dictionary,
		rejected_doorway_species_by_room: Dictionary,
		rejected_transit_species_by_room: Dictionary,
		rejected_immediate_species_by_room: Dictionary
	) -> void:
	var source_id: int = int(request.get("source_room_id", EXTERIOR_ID))
	var destination_id: int = int(request.get("destination_room_id", EXTERIOR_ID))
	var source_zone: String = String(request.get("source_zone", ZONE_UPPER))
	var destination_zone: String = String(request.get("destination_zone", ZONE_UPPER))
	var requested_mass_kg: float = maxf(0.0, float(request.get("gas_mass_kg", 0.0)))
	var accepted_fraction: float = 1.0
	if source_id != EXTERIOR_ID:
		var source_key: String = str(source_id)
		var source: Dictionary = shadow.get(source_key, {})
		var available_kg: float = float(source.get(source_zone + "_gas_kg", 0.0))
		if requested_mass_kg > 0.0:
			accepted_fraction = minf(1.0, available_kg / requested_mass_kg)
		var requested_o2_kg: float = maxf(0.0, float(request.get("o2_kg", 0.0)))
		if requested_o2_kg > 0.0:
			accepted_fraction = minf(accepted_fraction,
					float(source.get(source_zone + "_o2_kg", 0.0)) / requested_o2_kg)
		var requested_species: Dictionary = request.get("species_kg", {})
		var source_species: Dictionary = source.get(source_zone + "_species_kg", {})
		for species_name in requested_species.keys():
			var requested_species_kg: float = maxf(0.0, float(requested_species[species_name]))
			if requested_species_kg > 0.0:
				accepted_fraction = minf(accepted_fraction,
						float(source_species.get(species_name, 0.0)) / requested_species_kg)
		accepted_fraction = clampf(accepted_fraction, 0.0, 1.0)
		var accepted_mass_kg: float = requested_mass_kg * accepted_fraction
		source[source_zone + "_gas_kg"] = maxf(0.0, available_kg - accepted_mass_kg)
		source[source_zone + "_energy_kj"] = maxf(0.0,
			float(source.get(source_zone + "_energy_kj", 0.0))
			- float(request.get("sensible_enthalpy_kj", 0.0)) * accepted_fraction)
		source[source_zone + "_o2_kg"] = maxf(0.0,
			float(source.get(source_zone + "_o2_kg", 0.0)) - requested_o2_kg * accepted_fraction)
		for species_name in requested_species.keys():
			source_species[species_name] = maxf(0.0,
					float(source_species.get(species_name, 0.0))
					- float(requested_species[species_name]) * accepted_fraction)
		source[source_zone + "_species_kg"] = source_species
		shadow[source_key] = source
		if accepted_fraction < 1.0:
			rejected_by_room[source_key] = float(rejected_by_room.get(source_key, 0.0)) \
					+ requested_mass_kg * (1.0 - accepted_fraction)
			if String(request.get("cause", "")).begins_with("combustion_o2_"):
				rejected_combustion_o2_by_room[source_key] = float(
					rejected_combustion_o2_by_room.get(source_key, 0.0)
				) + requested_o2_kg * (1.0 - accepted_fraction)
			if String(request.get("cause", "")) == "doorway_species_direct":
				var rejected_species_kg: float = 0.0
				for species_name in requested_species.keys():
					rejected_species_kg += maxf(
						0.0, float(requested_species[species_name])
					) * (1.0 - accepted_fraction)
				rejected_doorway_species_by_room[source_key] = float(
					rejected_doorway_species_by_room.get(source_key, 0.0)
				) + rejected_species_kg
			if String(request.get("cause", "")).begins_with("delayed_species_parcel_"):
				var rejected_transit_species_kg: float = 0.0
				for species_name in requested_species.keys():
					rejected_transit_species_kg += maxf(
						0.0, float(requested_species[species_name])
					) * (1.0 - accepted_fraction)
				rejected_transit_species_by_room[source_key] = float(
					rejected_transit_species_by_room.get(source_key, 0.0)
				) + rejected_transit_species_kg
			if _is_immediate_species_cause(String(request.get("cause", ""))):
				var rejected_immediate_kg: float = 0.0
				for species_name in requested_species.keys():
					rejected_immediate_kg += maxf(
						0.0, float(requested_species[species_name])
					) * (1.0 - accepted_fraction)
				rejected_immediate_species_by_room[source_key] = float(
					rejected_immediate_species_by_room.get(source_key, 0.0)
				) + rejected_immediate_kg
				_immediate_rejected_kg_total += rejected_immediate_kg
				if _is_vertical_species_cause(String(request.get("cause", ""))):
					_vertical_rejected_kg_total += rejected_immediate_kg
	var request_cause: String = String(request.get("cause", ""))
	if _is_exterior_purge_cause(request_cause):
		var accepted_purge_species: Dictionary = {}
		var rejected_purge_species: Dictionary = {}
		for species_name in TRANSIT_SPECIES:
			var requested_purge_kg: float = maxf(
				0.0, float(request.get("species_kg", {}).get(species_name, 0.0))
			)
			accepted_purge_species[species_name] = requested_purge_kg * accepted_fraction
			rejected_purge_species[species_name] = requested_purge_kg * (1.0 - accepted_fraction)
		_add_transit_species(_exterior_purge_applied_species_kg, accepted_purge_species)
		_add_transit_species(_exterior_purge_rejected_species_kg, rejected_purge_species)
	if _is_immediate_species_cause(request_cause):
		var accepted_immediate_species: Dictionary = {}
		for species_name in TRANSIT_SPECIES:
			accepted_immediate_species[species_name] = maxf(
				0.0, float(request.get("species_kg", {}).get(species_name, 0.0))
			) * accepted_fraction
		_add_transit_species(_immediate_debited_species_kg_step, accepted_immediate_species)
		_add_transit_species(_immediate_credited_species_kg_step, accepted_immediate_species)
		if _is_vertical_species_cause(request_cause):
			_add_transit_species(_vertical_debited_species_kg_step, accepted_immediate_species)
			_add_transit_species(_vertical_credited_species_kg_step, accepted_immediate_species)
	if _is_thermal_species_cause(request_cause):
		var accepted_thermal_species: Dictionary = {}
		var rejected_thermal_species: Dictionary = {}
		for species_name in TRANSIT_SPECIES:
			var requested_thermal_kg: float = maxf(
				0.0, float(request.get("species_kg", {}).get(species_name, 0.0))
			)
			accepted_thermal_species[species_name] = requested_thermal_kg * accepted_fraction
			rejected_thermal_species[species_name] = requested_thermal_kg * (1.0 - accepted_fraction)
		_add_transit_species(_thermal_species_applied_kg, accepted_thermal_species)
		_add_transit_species(_thermal_species_rejected_kg, rejected_thermal_species)
	if destination_id != EXTERIOR_ID:
		var destination_key: String = str(destination_id)
		var destination: Dictionary = shadow.get(destination_key, {})
		var moved_mass_kg: float = requested_mass_kg * accepted_fraction
		destination[destination_zone + "_gas_kg"] = \
				float(destination.get(destination_zone + "_gas_kg", 0.0)) + moved_mass_kg
		destination[destination_zone + "_energy_kj"] = \
				float(destination.get(destination_zone + "_energy_kj", 0.0)) \
				+ float(request.get("sensible_enthalpy_kj", 0.0)) * accepted_fraction
		destination[destination_zone + "_o2_kg"] = \
				float(destination.get(destination_zone + "_o2_kg", 0.0)) \
				+ float(request.get("o2_kg", 0.0)) * accepted_fraction
		var destination_species: Dictionary = destination.get(destination_zone + "_species_kg", {})
		var moved_species: Dictionary = request.get("species_kg", {})
		for species_name in moved_species.keys():
			destination_species[species_name] = float(destination_species.get(species_name, 0.0)) \
					+ maxf(0.0, float(moved_species[species_name])) * accepted_fraction
		destination[destination_zone + "_species_kg"] = destination_species
		shadow[destination_key] = destination


func _count_room_requests(room_id: int) -> int:
	var count: int = 0
	for request in _requests:
		if int(request.get("source_room_id", EXTERIOR_ID)) == room_id \
				or int(request.get("destination_room_id", EXTERIOR_ID)) == room_id:
			count += 1
	return count


func _count_room_causes(room_id: int) -> int:
	var causes: Dictionary = {}
	for request in _requests:
		if int(request.get("source_room_id", EXTERIOR_ID)) == room_id \
				or int(request.get("destination_room_id", EXTERIOR_ID)) == room_id:
			causes[String(request.get("cause", ""))] = true
	return causes.size()


func _room_has_cause(room_id: int, cause: String) -> bool:
	for request in _requests:
		if String(request.get("cause", "")) != cause:
			continue
		if int(request.get("source_room_id", EXTERIOR_ID)) == room_id \
				or int(request.get("destination_room_id", EXTERIOR_ID)) == room_id:
			return true
	return false


func _room_has_cause_prefix(room_id: int, cause_prefix: String) -> bool:
	for request in _requests:
		if not String(request.get("cause", "")).begins_with(cause_prefix):
			continue
		if int(request.get("source_room_id", EXTERIOR_ID)) == room_id \
				or int(request.get("destination_room_id", EXTERIOR_ID)) == room_id:
			return true
	return false


func _combustion_owned_mask(room_id: int) -> float:
	var mask: int = 0
	if _room_has_cause(room_id, "combustion_convective_heat"):
		mask |= 1
	if _room_has_cause_prefix(room_id, "combustion_o2_"):
		mask |= 2
	if _room_has_cause(room_id, "combustion_species_source"):
		mask |= 4
	return float(mask)


func _sum_room_cause_mass(room_id: int, cause: String) -> float:
	var total_kg: float = 0.0
	for request in _requests:
		if String(request.get("cause", "")) != cause:
			continue
		if int(request.get("source_room_id", EXTERIOR_ID)) == room_id \
				or int(request.get("destination_room_id", EXTERIOR_ID)) == room_id:
			total_kg += maxf(0.0, float(request.get("gas_mass_kg", 0.0)))
	return total_kg


func _sum_room_cause_energy(room_id: int, cause: String) -> float:
	var total_kj: float = 0.0
	for request in _requests:
		if String(request.get("cause", "")) != cause:
			continue
		if int(request.get("source_room_id", EXTERIOR_ID)) == room_id \
				or int(request.get("destination_room_id", EXTERIOR_ID)) == room_id:
			total_kj += maxf(0.0, float(request.get("sensible_enthalpy_kj", 0.0)))
	return total_kj


func _sum_room_cause_prefix_o2(room_id: int, cause_prefix: String) -> float:
	var total_kg: float = 0.0
	for request in _requests:
		if not String(request.get("cause", "")).begins_with(cause_prefix):
			continue
		if int(request.get("source_room_id", EXTERIOR_ID)) == room_id \
				or int(request.get("destination_room_id", EXTERIOR_ID)) == room_id:
			total_kg += maxf(0.0, float(request.get("o2_kg", 0.0)))
	return total_kg


func _sum_room_cause_species(room_id: int, cause: String, species_name: String) -> float:
	var total_kg: float = 0.0
	for request in _requests:
		if String(request.get("cause", "")) != cause:
			continue
		if int(request.get("source_room_id", EXTERIOR_ID)) != room_id \
				and int(request.get("destination_room_id", EXTERIOR_ID)) != room_id:
			continue
		var species: Dictionary = request.get("species_kg", {})
		total_kg += maxf(0.0, float(species.get(species_name, 0.0)))
	return total_kg


func _state_mass(state: Dictionary) -> float:
	return float(state.get("upper_gas_kg", 0.0)) + float(state.get("lower_gas_kg", 0.0))


func _state_energy(state: Dictionary) -> float:
	return float(state.get("upper_energy_kj", 0.0)) + float(state.get("lower_energy_kj", 0.0))

extends RefCounted
class_name Phase3ZoneMassSystem

# F3.0: transaccion two-zone en sombra. Este componente nunca escribe RoomModel.

const Phase3SurfaceEnergySolverScript = preload(
	"res://sim/core/Phase3SurfaceEnergySolver.gd"
)
const ZONE_UPPER: String = "upper"
const ZONE_LOWER: String = "lower"
const EXTERIOR_ID: int = -1
const AIR_PRESSURE_REF_PA: float = 101325.0
const AIR_DENSITY_REF_KG_M3: float = 1.2
const AIR_CP_KJ_KG_K: float = 1.0
const EXTERIOR_DISCHARGE_COEFF: float = 0.61
const EXTERIOR_COUNTERFLOW_SEGMENTS: int = 64
const INTERIOR_PRESSURE_SOLVE_ITERATIONS: int = 32
const GRAVITY_M_S2: float = 9.81
const POREH_AIR_DENSITY_TEMPERATURE_KG_K_M3: float = 352.981915
const POREH_ENTRAINMENT_COEFFICIENT: float = 0.44
const POREH_COOL_JET_MIXING_FACTOR: float = 0.25
const CFAST_DESTINATION_DELTA_TEMP_K: float = 1.0
const THERMO_MASS_EPS_KG: float = 1.0e-12
const THERMO_ENERGY_EPS_KJ: float = 1.0e-12
const STEFAN_BOLTZMANN_KW_M2_K4: float = 5.670374419e-11
const CANONICAL_EXTERIOR_H_KW_M2_K: float = 0.025
const CANONICAL_SURFACE_NAMES: Array[String] = [
	"ceiling", "upper_wall", "lower_wall", "floor"
]
const SURFACE_FRACTION_TOLERANCE: float = 1.0e-6
const TRANSIT_SPECIES: Array[String] = ["co", "co2", "hcn"]
const PARCEL_SPECIES: Array[String] = [
	"smoke", "co", "co2", "hcn", "hcl", "acrolein", "formaldehyde"
]
const FIRE_PRODUCT_SCALAR_FIELDS: Array[String] = [
	"active_flag", "supported_flag", "object_sync_required_flag",
	"profile_object_count", "quality_phi", "carbon_scale", "common_fraction",
	"requested_fuel_MJ", "accepted_fuel_MJ", "requested_o2_kg",
	"accepted_o2_kg", "requested_total_energy_kj", "accepted_total_energy_kj",
	"effective_chi_rad", "requested_radiative_energy_kj",
	"accepted_radiative_energy_kj", "requested_convective_energy_kj",
	"accepted_convective_energy_kj", "accepted_plume_driver_hrr_kw",
	"accepted_plume_driver_qc_kw", "requested_carbon_available_kg",
	"requested_carbon_products_kg", "requested_carbon_untracked_kg",
	"requested_carbon_residual_kg", "accepted_carbon_available_kg",
	"accepted_carbon_products_kg", "accepted_carbon_untracked_kg",
	"accepted_carbon_residual_kg", "fuel_residual_MJ", "o2_residual_kg",
	"energy_residual_kj", "species_common_fraction_residual_kg",
]
const ENTHALPY_RESIDENCE_FAMILIES: Array[String] = [
	"combustion", "plume", "interzone", "wall", "ambient", "exterior",
	"exterior_counterflow", "interior_opening", "interior_pressure", "parcel",
	"doorway_jet", "legacy", "zone_collapse", "other",
]
const MASS_RESIDENCE_FAMILIES: Array[String] = [
	"combustion", "plume", "interzone", "wall", "ambient", "exterior",
	"exterior_counterflow", "interior_opening", "interior_pressure", "parcel",
	"doorway_jet", "legacy", "zone_collapse", "reconcile", "other",
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
var _canonical_exterior_counterflow_by_room: Dictionary = {}
var _canonical_exterior_counterflow_cumulative_kg: Dictionary = {}
var _canonical_interior_opening_by_room: Dictionary = {}
var _persistent_zone_state: Dictionary = {}
var _persistent_step_index: int = 0
var _persistent_combustion_state: Dictionary = {}
var _persistence_enabled_step: bool = false
var _persistence_seeded_by_room: Dictionary = {}
var _persistence_continuity_by_room: Dictionary = {}
var _combustion_o2_probe_by_room: Dictionary = {}
var _persistent_zone_collapse_by_room: Dictionary = {}
var _canonical_combustion_by_room: Dictionary = {}
var _persistent_lower_reseed_by_room: Dictionary = {}
var _canonical_interzone_heat_by_room: Dictionary = {}
var _canonical_interzone_heat_cumulative_kj: Dictionary = {}
var _canonical_wall_state_by_room: Dictionary = {}
var _canonical_wall_ambient_by_room: Dictionary = {}
var _canonical_wall_ambient_cumulative_by_room: Dictionary = {}
var canonical_multisurface_shadow_enabled: bool = false
var _canonical_surface_state_by_room: Dictionary = {}
var _canonical_multisurface_by_room: Dictionary = {}
var _canonical_multisurface_exchange_by_room: Dictionary = {}
var _canonical_multisurface_cumulative_by_room: Dictionary = {}
var _canonical_multisurface_radiation_committed_by_room: Dictionary = {}
var _canonical_multisurface_duplicate_commit_count: int = 0
var enthalpy_residence_diagnostics_enabled: bool = false
var _enthalpy_residence_initial_by_room: Dictionary = {}
var _enthalpy_residence_cumulative_by_room: Dictionary = {}
var mass_residence_diagnostics_enabled: bool = false
var _mass_residence_initial_by_room: Dictionary = {}
var _mass_residence_cumulative_by_room: Dictionary = {}
var connection_residence_diagnostics_enabled: bool = false
var _connection_residence_cumulative: Dictionary = {}


func configure_enthalpy_residence_diagnostics(is_enabled: bool) -> void:
	enthalpy_residence_diagnostics_enabled = is_enabled
	if not is_enabled:
		_enthalpy_residence_initial_by_room.clear()
		_enthalpy_residence_cumulative_by_room.clear()


func configure_mass_residence_diagnostics(is_enabled: bool) -> void:
	mass_residence_diagnostics_enabled = is_enabled
	if not is_enabled:
		_mass_residence_initial_by_room.clear()
		_mass_residence_cumulative_by_room.clear()


func configure_connection_residence_diagnostics(is_enabled: bool) -> void:
	connection_residence_diagnostics_enabled = is_enabled
	if not is_enabled:
		_connection_residence_cumulative.clear()


func configure_canonical_multisurface_shadow(is_enabled: bool) -> void:
	canonical_multisurface_shadow_enabled = is_enabled
	if not is_enabled:
		_canonical_surface_state_by_room.clear()
		_canonical_multisurface_by_room.clear()
		_canonical_multisurface_exchange_by_room.clear()
		_canonical_multisurface_cumulative_by_room.clear()
		_canonical_multisurface_radiation_committed_by_room.clear()
		_canonical_multisurface_duplicate_commit_count = 0


func reset() -> void:
	_reset_step_state()
	_persistent_zone_state.clear()
	_persistent_step_index = 0
	_persistent_combustion_state.clear()
	_persistent_lower_reseed_by_room.clear()
	_canonical_interzone_heat_cumulative_kj.clear()
	_canonical_exterior_counterflow_cumulative_kg.clear()
	_canonical_wall_state_by_room.clear()
	_canonical_wall_ambient_cumulative_by_room.clear()
	_canonical_surface_state_by_room.clear()
	_canonical_multisurface_by_room.clear()
	_canonical_multisurface_exchange_by_room.clear()
	_canonical_multisurface_cumulative_by_room.clear()
	_canonical_multisurface_radiation_committed_by_room.clear()
	_canonical_multisurface_duplicate_commit_count = 0
	_enthalpy_residence_initial_by_room.clear()
	_enthalpy_residence_cumulative_by_room.clear()
	_mass_residence_initial_by_room.clear()
	_mass_residence_cumulative_by_room.clear()
	_connection_residence_cumulative.clear()
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
	_canonical_exterior_counterflow_by_room.clear()
	_canonical_interior_opening_by_room.clear()
	_persistence_enabled_step = false
	_persistence_seeded_by_room.clear()
	_persistence_continuity_by_room.clear()
	_combustion_o2_probe_by_room.clear()
	_persistent_zone_collapse_by_room.clear()
	_canonical_combustion_by_room.clear()
	_canonical_interzone_heat_by_room.clear()
	_canonical_wall_ambient_by_room.clear()
	_canonical_multisurface_by_room.clear()
	_canonical_multisurface_exchange_by_room.clear()
	_canonical_multisurface_radiation_committed_by_room.clear()
	_canonical_multisurface_duplicate_commit_count = 0


func begin_step(building, persistence_enabled: bool = false) -> void:
	_reset_step_state()
	_persistence_enabled_step = persistence_enabled
	if not persistence_enabled:
		_persistent_zone_state.clear()
		_persistent_step_index = 0
		_persistent_combustion_state.clear()
		_persistent_lower_reseed_by_room.clear()
		_canonical_exterior_counterflow_cumulative_kg.clear()
		_canonical_wall_state_by_room.clear()
		_canonical_wall_ambient_cumulative_by_room.clear()
		_canonical_surface_state_by_room.clear()
		_canonical_multisurface_cumulative_by_room.clear()
		_enthalpy_residence_initial_by_room.clear()
		_enthalpy_residence_cumulative_by_room.clear()
		_mass_residence_initial_by_room.clear()
		_mass_residence_cumulative_by_room.clear()
		_connection_residence_cumulative.clear()
	if building == null:
		return
	for room_id in building.get_rooms().keys():
		var room: RoomModel = building.get_room(room_id)
		if room == null:
			continue
		var room_key: String = str(room_id)
		var legacy_snapshot: Dictionary = _snapshot_room(room)
		if persistence_enabled and _persistent_zone_state.has(room_key):
			var persisted: Dictionary = _persistent_zone_state[room_key].duplicate(true)
			_snapshots[room_key] = persisted
			_persistence_seeded_by_room[room_key] = false
			_persistence_continuity_by_room[room_key] = _state_delta_summary(
				persisted, _persistent_zone_state[room_key]
			)
		else:
			_snapshots[room_key] = legacy_snapshot
			_persistence_seeded_by_room[room_key] = persistence_enabled
			_persistence_continuity_by_room[room_key] = _zero_state_delta_summary()
		if enthalpy_residence_diagnostics_enabled \
				and not _enthalpy_residence_initial_by_room.has(room_key):
			var initial_state: Dictionary = _snapshots[room_key]
			_enthalpy_residence_initial_by_room[room_key] = {
				"upper_energy_kj": maxf(
					0.0, float(initial_state.get("upper_energy_kj", 0.0))
				),
				"lower_energy_kj": maxf(
					0.0, float(initial_state.get("lower_energy_kj", 0.0))
				),
			}
			_enthalpy_residence_cumulative_by_room[room_key] = \
					_new_enthalpy_residence_record()
		if mass_residence_diagnostics_enabled \
				and not _mass_residence_initial_by_room.has(room_key):
			var initial_mass_state: Dictionary = _snapshots[room_key]
			_mass_residence_initial_by_room[room_key] = {
				"upper_gas_kg": maxf(
					0.0, float(initial_mass_state.get("upper_gas_kg", 0.0))
				),
				"lower_gas_kg": maxf(
					0.0, float(initial_mass_state.get("lower_gas_kg", 0.0))
				),
			}
			_mass_residence_cumulative_by_room[room_key] = \
					_new_mass_residence_record()


## F3.2b0: registra que zona eligio realmente CombustionSystem, pero no cambia
## HRR ni RoomModel. El candidato usa el inventario canonico pre-step.
func record_combustion_o2_probe(building) -> void:
	if not _persistence_enabled_step or building == null:
		return
	for raw_room_id in building.get_rooms().keys():
		var room_id: int = int(raw_room_id)
		var room: RoomModel = building.get_room(room_id)
		var room_key: String = str(room_id)
		if room == null or not _snapshots.has(room_key):
			continue
		var state: Dictionary = _snapshots[room_key]
		var upper_o2: float = _zone_o2_fraction(state, ZONE_UPPER)
		var lower_o2: float = _zone_o2_fraction(state, ZONE_LOWER)
		var legacy_mode: String = room.fire_o2_mode_used
		# F3.2b0 candidate policy: combustion reads and debits upper-zone O2.
		# The live engine keeps its legacy selected mode until an authority gate.
		var selected: Dictionary = _canonical_o2_for_selected_mode(
			"upper", upper_o2, lower_o2, room
		)
		var canonical_ref: float = float(selected.get("o2_ref", 0.0))
		var legacy_ref: float = clampf(room.fire_o2_ref, 0.0, 1.0)
		_combustion_o2_probe_by_room[room_key] = {
			"pre_upper_o2_fraction": upper_o2,
			"pre_lower_o2_fraction": lower_o2,
			"canonical_o2_ref": canonical_ref,
			"legacy_o2_ref": legacy_ref,
			"legacy_mode": legacy_mode,
			"selected_zone_code": float(selected.get("zone_code", 0.0)),
			"would_limit_flag": 1.0 if canonical_ref + 1.0e-12 < legacy_ref else 0.0,
		}


## Input read-only para el evaluador F3.2b1. Siempre sale del snapshot canonico
## pre-step, nunca del RoomModel ya mutado por el tick legacy.
func get_canonical_combustion_input(room_id: int) -> Dictionary:
	var room_key: String = str(room_id)
	if not _snapshots.has(room_key):
		return {}
	var state: Dictionary = _snapshots[room_key]
	return {
		"upper_gas_kg": maxf(0.0, float(state.get("upper_gas_kg", 0.0))),
		"lower_gas_kg": maxf(0.0, float(state.get("lower_gas_kg", 0.0))),
		"upper_energy_kj": maxf(0.0, float(state.get("upper_energy_kj", 0.0))),
		"lower_energy_kj": maxf(0.0, float(state.get("lower_energy_kj", 0.0))),
		"upper_o2_kg": maxf(0.0, float(state.get("upper_o2_kg", 0.0))),
		"lower_o2_kg": maxf(0.0, float(state.get("lower_o2_kg", 0.0))),
		"upper_o2_fraction": _zone_o2_fraction(state, ZONE_UPPER),
		"lower_o2_fraction": _zone_o2_fraction(state, ZONE_LOWER),
	}


## F3.2b7: contexto pre-step del counterflow ya encolado. Permite que el
## evaluador de combustion seleccione la reserva lower sin observar el estado
## post-mutacion ni anticipar el resultado aceptado del bundle.
func get_canonical_exterior_counterflow_request(room_id: int) -> Dictionary:
	var record: Dictionary = _canonical_exterior_counterflow_by_room.get(
		str(room_id), _new_canonical_exterior_counterflow_record()
	)
	return {
		"requested_exchange_kg": maxf(
			0.0, float(record.get("requested_exchange_kg", 0.0))
		),
		"requested_incoming_o2_kg": maxf(
			0.0, float(record.get("requested_incoming_o2_kg", 0.0))
		),
		"opening_count": maxf(0.0, float(record.get("opening_count", 0.0))),
	}


## Estado termodinamico pre-step para evaluadores canonicos. Deriva geometria
## exclusivamente desde masa y energia persistentes; nunca lee la interfaz legacy.
func get_canonical_thermodynamic_input(
		room: RoomModel,
		reference_temp_c: float
	) -> Dictionary:
	if room == null:
		return {}
	var canonical_input: Dictionary = get_canonical_combustion_input(room.id)
	if canonical_input.is_empty():
		return {}
	var thermo: Dictionary = derive_canonical_thermodynamic_state(
		float(canonical_input.get("upper_gas_kg", 0.0)),
		float(canonical_input.get("lower_gas_kg", 0.0)),
		float(canonical_input.get("upper_energy_kj", 0.0)),
		float(canonical_input.get("lower_energy_kj", 0.0)),
		room.volume_m3(),
		room.floor_area_m2(),
		room.height_m,
		reference_temp_c
	)
	canonical_input.merge(thermo, true)
	return canonical_input


## F3.2b5a: encola una transferencia energy-only como bundle atomico. El
## limitador comun del ledger vuelve a acotar por la energia upper disponible
## en el punto real de aplicacion, despues de solicitudes previas del tick.
func queue_canonical_interzone_heat_transfer(
		room_id: int,
		preview: Dictionary,
		step_token: String
	) -> bool:
	var room_key: String = str(room_id)
	if room_id == EXTERIOR_ID or not _snapshots.has(room_key):
		return false
	var requested_kj: float = maxf(
		0.0, float(preview.get("sensible_enthalpy_kj", 0.0))
	)
	var record: Dictionary = {
		"legacy_requested_kj": maxf(
			0.0, float(preview.get("legacy_requested_kj", 0.0))
		),
		"legacy_candidate_kj": maxf(
			0.0, float(preview.get("legacy_candidate_kj", 0.0))
		),
		"capacity_candidate_kj": maxf(
			0.0, float(preview.get("capacity_candidate_kj", 0.0))
		),
		"equilibrium_limit_kj": maxf(
			0.0, float(preview.get("equilibrium_limit_kj", 0.0))
		),
		"requested_kj": requested_kj,
		"accepted_kj": 0.0,
		"rejected_kj": 0.0,
		"pre_delta_t_c": float(preview.get("pre_delta_t_c", 0.0)),
		"direction_code": float(preview.get("direction_code", 0.0)),
		"rate_per_s": maxf(0.0, float(preview.get("rate_per_s", 0.0))),
		"lower_fade": clampf(float(preview.get("lower_fade", 0.0)), 0.0, 1.0),
		"energy_residual_kj": 0.0,
	}
	_canonical_interzone_heat_by_room[room_key] = record
	if requested_kj <= THERMO_ENERGY_EPS_KJ:
		return true
	var bundle_id: String = "canonical_interzone_heat:%d:%s" % [room_id, step_token]
	var route: Dictionary = make_atomic_route(
		bundle_id + ":upper_to_lower",
		"thermal_upper_to_lower",
		room_id,
		room_id,
		ZONE_UPPER,
		ZONE_LOWER,
		0.0,
		requested_kj,
		0.0,
		{}
	)
	return add_atomic_bundle(make_atomic_bundle(
		bundle_id,
		"canonical_interzone_heat",
		[route],
		{
			"kind": "canonical_interzone_heat",
			"room_id": room_id,
			"requested_energy_kj": requested_kj,
		}
	))


## Persistent wall reservoir input for F3.2b5b. The state is independent of
## ThermalSystem's legacy wall dictionaries and is referenced to ambient.
func get_canonical_wall_ambient_input(
		room_id: int,
		wall_capacity_kj_k: float,
		reference_temp_c: float
	) -> Dictionary:
	var room_key: String = str(room_id)
	var capacity_kj_k: float = maxf(0.1, wall_capacity_kj_k)
	if not _canonical_wall_state_by_room.has(room_key):
		_canonical_wall_state_by_room[room_key] = {
			"wall_energy_kj": 0.0,
			"wall_capacity_kj_k": capacity_kj_k,
			"reference_temp_c": reference_temp_c,
		}
	var state: Dictionary = _canonical_wall_state_by_room[room_key].duplicate(true)
	state["wall_capacity_kj_k"] = capacity_kj_k
	state["reference_temp_c"] = reference_temp_c
	state["wall_temp_c"] = reference_temp_c + maxf(
		0.0, float(state.get("wall_energy_kj", 0.0))
	) / capacity_kj_k
	return state


## F3.3r2b: seeds or migrates four independent surface snapshots. The method
## is inert while the experimental flag is disabled and never reads RoomModel.
func prepare_canonical_multisurface_room(
		room_id: int,
		geometry: Dictionary,
		material: Dictionary,
		reference_temp_c: float
	) -> Dictionary:
	if not canonical_multisurface_shadow_enabled or room_id == EXTERIOR_ID:
		return {"valid": false, "error": "multisurface shadow disabled"}
	var geometry_error: String = _validate_multisurface_geometry(geometry)
	if not geometry_error.is_empty():
		return {"valid": false, "error": geometry_error}
	var material_error: String = _validate_multisurface_material(material)
	if not material_error.is_empty():
		return {"valid": false, "error": material_error}
	if not is_finite(reference_temp_c):
		return {"valid": false, "error": "invalid reference temperature"}

	var room_key: String = str(room_id)
	var previous_step_record: Dictionary = _canonical_multisurface_by_room.get(
		room_key, {}
	)
	var floor_area_m2: float = float(geometry["floor_area_m2"])
	var perimeter_m: float = float(geometry["perimeter_m"])
	var height_m: float = float(geometry["height_m"])
	var interface_m: float = clampf(
		float(geometry["interface_m"]), 0.0, height_m
	)
	var areas: Dictionary = {
		"ceiling": floor_area_m2,
		"upper_wall": perimeter_m * (height_m - interface_m),
		"lower_wall": perimeter_m * interface_m,
		"floor": floor_area_m2,
	}
	var migration_residual_kj: float = 0.0
	var migrated_energy_kj: float = 0.0
	var seeded: bool = false
	var state: Dictionary = {}

	if not _canonical_surface_state_by_room.has(room_key):
		seeded = true
		var surfaces: Dictionary = {}
		for surface_name in ["ceiling", "upper_wall", "lower_wall", "floor"]:
			surfaces[surface_name] = _make_canonical_surface_state(
				float(areas[surface_name]), material, reference_temp_c
			)
		state = {
			"reference_temp_c": reference_temp_c,
			"interface_m": interface_m,
			"height_m": height_m,
			"floor_area_m2": floor_area_m2,
			"perimeter_m": perimeter_m,
			"material": material.duplicate(true),
			"surfaces": surfaces,
			"step_index": _persistent_step_index,
		}
	else:
		state = _canonical_surface_state_by_room[room_key].duplicate(true)
		if not _multisurface_material_matches(
				state.get("material", {}), material
		):
			return {"valid": false, "error": "surface material changed"}
		if absf(float(state.get("floor_area_m2", 0.0)) - floor_area_m2) > 1.0e-9 \
				or absf(float(state.get("perimeter_m", 0.0)) - perimeter_m) > 1.0e-9 \
				or absf(float(state.get("height_m", 0.0)) - height_m) > 1.0e-9:
			return {"valid": false, "error": "room enclosure geometry changed"}
		var energy_pre_kj: float = _canonical_multisurface_total_energy(state)
		var surfaces: Dictionary = state.get("surfaces", {}).duplicate(true)
		var upper: Dictionary = surfaces.get("upper_wall", {}).duplicate(true)
		var lower: Dictionary = surfaces.get("lower_wall", {}).duplicate(true)
		var old_upper_area_m2: float = float(upper.get("area_m2", 0.0))
		var old_lower_area_m2: float = float(lower.get("area_m2", 0.0))
		var new_upper_area_m2: float = float(areas["upper_wall"])
		var new_lower_area_m2: float = float(areas["lower_wall"])
		if new_upper_area_m2 > old_upper_area_m2 + 1.0e-12:
			var moved_area_m2: float = new_upper_area_m2 - old_upper_area_m2
			upper = _mix_surface_area_profiles(
				upper, old_upper_area_m2, lower, moved_area_m2, new_upper_area_m2
			)
			lower["area_m2"] = new_lower_area_m2
			migrated_energy_kj = absf(
				_surface_energy_for_area(lower, moved_area_m2)
			)
		elif new_lower_area_m2 > old_lower_area_m2 + 1.0e-12:
			var moved_area_m2: float = new_lower_area_m2 - old_lower_area_m2
			lower = _mix_surface_area_profiles(
				lower, old_lower_area_m2, upper, moved_area_m2, new_lower_area_m2
			)
			upper["area_m2"] = new_upper_area_m2
			migrated_energy_kj = absf(
				_surface_energy_for_area(upper, moved_area_m2)
			)
		else:
			upper["area_m2"] = new_upper_area_m2
			lower["area_m2"] = new_lower_area_m2
		surfaces["upper_wall"] = upper
		surfaces["lower_wall"] = lower
		state["surfaces"] = surfaces
		state["interface_m"] = interface_m
		state["step_index"] = _persistent_step_index
		var energy_post_kj: float = _canonical_multisurface_total_energy(state)
		migration_residual_kj = energy_post_kj - energy_pre_kj

	_canonical_surface_state_by_room[room_key] = state.duplicate(true)
	var record: Dictionary = {
		"valid": true,
		"error": "",
		"seeded_flag": 1.0 if seeded else 0.0,
		"interface_m": interface_m,
		"migration_energy_kj": float(
			previous_step_record.get("migration_energy_kj", 0.0)
		) + migrated_energy_kj,
		"migration_residual_kj": float(
			previous_step_record.get("migration_residual_kj", 0.0)
		) + migration_residual_kj,
		"radiation_requested_kj": 0.0,
		"radiation_accepted_kj": 0.0,
		"radiation_routed_kj": 0.0,
		"radiation_residual_kj": 0.0,
		"surface_energy_pre_kj": _canonical_multisurface_total_energy(state),
		"surface_energy_post_kj": _canonical_multisurface_total_energy(state),
	}
	_canonical_multisurface_by_room[room_key] = record
	return record.duplicate(true)


func get_canonical_multisurface_state(room_id: int) -> Dictionary:
	return _canonical_surface_state_by_room.get(str(room_id), {}).duplicate(true)


func get_canonical_multisurface_record(room_id: int) -> Dictionary:
	return _canonical_multisurface_by_room.get(str(room_id), {}).duplicate(true)


func get_canonical_multisurface_exchange_record(room_id: int) -> Dictionary:
	return _canonical_multisurface_exchange_by_room.get(
		str(room_id), {}
	).duplicate(true)


## F3.3r2b2: validates explicit physical enclosure metadata and converts only
## its exterior fraction into a surface boundary coefficient. Missing or
## invalid metadata never infers topology: all surfaces remain adiabatic.
## Inter-room fractions are diagnostic until paired-surface correspondence.
func build_canonical_surface_boundary_context(
		raw_topology: Variant,
		exterior_temp_c: float
	) -> Dictionary:
	# Inter-room area remains adiabatic until paired-surface correspondence.
	var failed: Dictionary = {
		"valid": false,
		"error": "missing surface topology",
		"boundary_metadata_complete_flag": 0.0,
		"adiabatic_surface_count": 4.0,
		"exterior_by_surface": {},
		"topology_by_surface": {},
		"exterior_fraction_sum": 0.0,
		"inter_room_fraction_sum": 0.0,
		"adiabatic_fraction_sum": 4.0,
		"unsupported_inter_room_surface_count": 0.0,
	}
	if not is_finite(exterior_temp_c):
		failed["error"] = "invalid exterior temperature"
		return failed
	if typeof(raw_topology) != TYPE_DICTIONARY:
		return failed
	var topology: Dictionary = raw_topology
	var normalized: Dictionary = {}
	var exterior_by_surface: Dictionary = {}
	var exterior_sum: float = 0.0
	var inter_room_sum: float = 0.0
	var adiabatic_sum: float = 0.0
	var fully_adiabatic_count: int = 0
	var unsupported_inter_room_count: int = 0
	for surface_name in CANONICAL_SURFACE_NAMES:
		if not topology.has(surface_name) \
				or typeof(topology[surface_name]) != TYPE_DICTIONARY:
			failed["error"] = "missing or invalid surface: " + surface_name
			return failed
		var raw_surface: Dictionary = topology[surface_name]
		for fraction_name in [
			"exterior_fraction",
			"inter_room_fraction",
			"adiabatic_fraction",
		]:
			if not raw_surface.has(fraction_name):
				failed["error"] = "missing %s for %s" % [
					fraction_name, surface_name
				]
				return failed
			var raw_value: Variant = raw_surface[fraction_name]
			if typeof(raw_value) != TYPE_FLOAT and typeof(raw_value) != TYPE_INT:
				failed["error"] = "non-numeric %s for %s" % [
					fraction_name, surface_name
				]
				return failed
		var exterior_fraction: float = float(
			raw_surface["exterior_fraction"]
		)
		var inter_room_fraction: float = float(
			raw_surface["inter_room_fraction"]
		)
		var adiabatic_fraction: float = float(
			raw_surface["adiabatic_fraction"]
		)
		if not is_finite(exterior_fraction) \
				or not is_finite(inter_room_fraction) \
				or not is_finite(adiabatic_fraction) \
				or exterior_fraction < 0.0 or exterior_fraction > 1.0 \
				or inter_room_fraction < 0.0 or inter_room_fraction > 1.0 \
				or adiabatic_fraction < 0.0 or adiabatic_fraction > 1.0:
			failed["error"] = "out-of-range fractions for " + surface_name
			return failed
		var fraction_total: float = exterior_fraction \
				+ inter_room_fraction + adiabatic_fraction
		if absf(fraction_total - 1.0) > SURFACE_FRACTION_TOLERANCE:
			failed["error"] = "fractions do not sum to one for " + surface_name
			return failed
		normalized[surface_name] = {
			"exterior_fraction": exterior_fraction,
			"inter_room_fraction": inter_room_fraction,
			"adiabatic_fraction": adiabatic_fraction,
		}
		if exterior_fraction > SURFACE_FRACTION_TOLERANCE:
			exterior_by_surface[surface_name] = {
				"exterior_h_kw_m2_k": (
					CANONICAL_EXTERIOR_H_KW_M2_K * exterior_fraction
				),
				"exterior_temp_c": exterior_temp_c,
			}
		if adiabatic_fraction >= 1.0 - SURFACE_FRACTION_TOLERANCE:
			fully_adiabatic_count += 1
		if inter_room_fraction > SURFACE_FRACTION_TOLERANCE:
			unsupported_inter_room_count += 1
		exterior_sum += exterior_fraction
		inter_room_sum += inter_room_fraction
		adiabatic_sum += adiabatic_fraction
	return {
		"valid": true,
		"error": "",
		"boundary_metadata_complete_flag": 1.0,
		"adiabatic_surface_count": float(fully_adiabatic_count),
		"exterior_by_surface": exterior_by_surface,
		"topology_by_surface": normalized,
		"exterior_fraction_sum": exterior_sum,
		"inter_room_fraction_sum": inter_room_sum,
		"adiabatic_fraction_sum": adiabatic_sum,
		"unsupported_inter_room_surface_count": float(
			unsupported_inter_room_count
		),
	}


## F3.3r2b1: evaluates gas/surface/exterior exchange from immutable pre-step
## snapshots. It never queues routes or mutates the persistent surface state.
func preview_canonical_multisurface_exchange(
		room_id: int,
		context: Dictionary
	) -> Dictionary:
	var invalid: Dictionary = {"valid": false, "error": ""}
	if not canonical_multisurface_shadow_enabled:
		invalid["error"] = "multisurface shadow disabled"
		return invalid
	var room_key: String = str(room_id)
	if room_id == EXTERIOR_ID or not _snapshots.has(room_key) \
			or not _canonical_surface_state_by_room.has(room_key):
		invalid["error"] = "missing canonical room or surface snapshot"
		return invalid
	var dt_s: float = float(context.get("dt_s", 0.0))
	var upper_temp_c: float = float(context.get("upper_temp_c", NAN))
	var lower_temp_c: float = float(context.get("lower_temp_c", NAN))
	var upper_h: float = float(context.get("upper_h_kw_m2_k", 0.0))
	var lower_h: float = float(context.get("lower_h_kw_m2_k", 0.0))
	var upper_gas_emissivity: float = float(
		context.get("upper_gas_emissivity", 0.0)
	)
	var lower_gas_emissivity: float = float(
		context.get("lower_gas_emissivity", 0.0)
	)
	if dt_s <= 0.0 or not is_finite(dt_s) \
			or not is_finite(upper_temp_c) or not is_finite(lower_temp_c) \
			or not is_finite(upper_h) or not is_finite(lower_h) \
			or not is_finite(upper_gas_emissivity) \
			or not is_finite(lower_gas_emissivity) \
			or upper_h < 0.0 or lower_h < 0.0 \
			or upper_gas_emissivity < 0.0 or upper_gas_emissivity > 1.0 \
			or lower_gas_emissivity < 0.0 or lower_gas_emissivity > 1.0:
		invalid["error"] = "invalid multisurface exchange context"
		return invalid

	var state: Dictionary = _canonical_surface_state_by_room[
		room_key
	].duplicate(true)
	var surfaces: Dictionary = state.get("surfaces", {})
	var exterior_by_surface: Dictionary = context.get(
		"exterior_by_surface", {}
	)
	var boundary_metadata_complete_flag: float = float(
		context.get(
			"boundary_metadata_complete_flag",
			1.0 if exterior_by_surface.size() == 4 else 0.0
		)
	)
	var adiabatic_surface_count: float = float(
		context.get(
			"adiabatic_surface_count",
			float(4 - exterior_by_surface.size())
		)
	)
	var surface_fluxes: Dictionary = {}
	var upper_exchange_kj: float = 0.0
	var lower_exchange_kj: float = 0.0
	var exterior_removed_kj: float = 0.0
	var solver_residual_kj: float = 0.0
	for surface_name in CANONICAL_SURFACE_NAMES:
		var surface: Dictionary = surfaces.get(surface_name, {}).duplicate(true)
		if surface.is_empty():
			invalid["error"] = "missing surface: " + surface_name
			return invalid
		var is_upper: bool = surface_name in ["ceiling", "upper_wall"]
		var gas_temp_c: float = upper_temp_c if is_upper else lower_temp_c
		var interior_h: float = upper_h if is_upper else lower_h
		var gas_emissivity: float = (
			upper_gas_emissivity if is_upper else lower_gas_emissivity
		)
		var area_m2: float = maxf(0.0, float(surface.get("area_m2", 0.0)))
		var surface_temp_c: float = float(
			(surface.get("nodes_c", [gas_temp_c]) as Array)[0]
		)
		var gas_radiation_kj: float = 0.0
		if area_m2 > THERMO_ENERGY_EPS_KJ and gas_emissivity > 0.0:
			var gas_temp_k: float = maxf(1.0, gas_temp_c + 273.15)
			var surface_temp_k: float = maxf(1.0, surface_temp_c + 273.15)
			gas_radiation_kj = (
				maxf(0.0, float(surface.get("emissivity", 0.0)))
				* gas_emissivity
				* STEFAN_BOLTZMANN_KW_M2_K4
				* area_m2
				* (pow(gas_temp_k, 4.0) - pow(surface_temp_k, 4.0))
				* dt_s
			)
		var exterior: Dictionary = {}
		if exterior_by_surface.has(surface_name):
			if typeof(exterior_by_surface[surface_name]) != TYPE_DICTIONARY:
				invalid["error"] = "invalid exterior metadata: " + surface_name
				return invalid
			exterior = exterior_by_surface[surface_name]
		var exterior_h: float = float(
			exterior.get("exterior_h_kw_m2_k", 0.0)
		)
		var exterior_temp_c: float = float(
			exterior.get("exterior_temp_c", surface_temp_c)
		)
		if not is_finite(exterior_h) or exterior_h < 0.0 \
				or not is_finite(exterior_temp_c):
			invalid["error"] = "invalid exterior boundary: " + surface_name
			return invalid
		var solved: Dictionary = Phase3SurfaceEnergySolverScript.step_surface(
			surface,
			{
				"dt_s": dt_s,
				"interior_gas_temp_c": gas_temp_c,
				"interior_h_kw_m2_k": interior_h,
				"exterior_temp_c": exterior_temp_c,
				"exterior_h_kw_m2_k": exterior_h,
				"gas_radiation_energy_kj": gas_radiation_kj,
				"fire_radiation_energy_kj": 0.0,
			}
		)
		if not bool(solved.get("valid", false)):
			invalid["error"] = String(solved.get("error", "surface preview failed"))
			return invalid
		var convection_kj: float = float(
			solved.get("interior_convection_energy_kj", 0.0)
		)
		var surface_exchange_kj: float = convection_kj + gas_radiation_kj
		if is_upper:
			upper_exchange_kj += surface_exchange_kj
		else:
			lower_exchange_kj += surface_exchange_kj
		var surface_exterior_kj: float = float(
			solved.get("exterior_energy_removed_kj", 0.0)
		)
		exterior_removed_kj += surface_exterior_kj
		solver_residual_kj += float(solved.get("energy_residual_kj", 0.0))
		surface_fluxes[surface_name] = {
			"zone": ZONE_UPPER if is_upper else ZONE_LOWER,
			"convection_requested_kj": convection_kj,
			"gas_radiation_requested_kj": gas_radiation_kj,
			"exterior_removed_requested_kj": surface_exterior_kj,
		}
	return {
		"valid": true,
		"error": "",
		"dt_s": dt_s,
		"upper_exchange_requested_kj": upper_exchange_kj,
		"lower_exchange_requested_kj": lower_exchange_kj,
		"exterior_removed_requested_kj": exterior_removed_kj,
		"surface_fluxes": surface_fluxes,
		"boundary_metadata_complete_flag": boundary_metadata_complete_flag,
		"adiabatic_surface_count": adiabatic_surface_count,
		"exterior_fraction_sum": float(
			context.get("exterior_fraction_sum", 0.0)
		),
		"inter_room_fraction_sum": float(
			context.get("inter_room_fraction_sum", 0.0)
		),
		"adiabatic_fraction_sum": float(
			context.get("adiabatic_fraction_sum", 4.0)
		),
		"unsupported_inter_room_surface_count": float(
			context.get("unsupported_inter_room_surface_count", 0.0)
		),
		"preview_solver_residual_kj": solver_residual_kj,
	}


## Queues only the gas-facing signed energy routes. Exterior loss and surface
## storage are committed later with the same accepted atomic fraction.
func queue_canonical_multisurface_exchange(
		room_id: int,
		preview: Dictionary,
		step_token: String
	) -> bool:
	var room_key: String = str(room_id)
	if not canonical_multisurface_shadow_enabled or room_id == EXTERIOR_ID \
			or not _snapshots.has(room_key) \
			or not bool(preview.get("valid", false)) \
			or _canonical_multisurface_exchange_by_room.has(room_key):
		return false
	var record: Dictionary = preview.duplicate(true)
	record["accepted_fraction"] = 1.0
	record["accepted_upper_exchange_kj"] = 0.0
	record["accepted_lower_exchange_kj"] = 0.0
	record["accepted_exterior_removed_kj"] = 0.0
	record["combined_energy_residual_kj"] = 0.0
	_canonical_multisurface_exchange_by_room[room_key] = record
	var bundle_id: String = "canonical_multisurface_exchange:%d:%s" % [
		room_id, step_token
	]
	var routes: Array = []
	for zone_name in [ZONE_UPPER, ZONE_LOWER]:
		var requested_kj: float = float(
			preview.get(zone_name + "_exchange_requested_kj", 0.0)
		)
		if requested_kj > THERMO_ENERGY_EPS_KJ:
			routes.append(make_atomic_route(
				bundle_id + ":" + zone_name + "_to_surface",
				"canonical_" + zone_name + "_to_multisurface",
				room_id, EXTERIOR_ID, zone_name, zone_name,
				0.0, requested_kj, 0.0, {}
			))
		elif requested_kj < -THERMO_ENERGY_EPS_KJ:
			routes.append(make_atomic_route(
				bundle_id + ":surface_to_" + zone_name,
				"canonical_multisurface_to_" + zone_name,
				EXTERIOR_ID, room_id, zone_name, zone_name,
				0.0, -requested_kj, 0.0, {}
			))
	if routes.is_empty():
		return true
	return add_atomic_bundle(make_atomic_bundle(
		bundle_id,
		"canonical_multisurface_exchange",
		routes,
		{
			"kind": "canonical_multisurface_exchange",
			"room_id": room_id,
		}
	))


func commit_canonical_multisurface_combustion_radiation(room_id: int) -> bool:
	if not canonical_multisurface_shadow_enabled:
		return false
	var room_key: String = str(room_id)
	if _canonical_multisurface_radiation_committed_by_room.has(room_key):
		_canonical_multisurface_duplicate_commit_count += 1
		var duplicate_record: Dictionary = _canonical_multisurface_by_room.get(
			room_key, {}
		).duplicate(true)
		duplicate_record["duplicate_commit_count"] = \
				float(_canonical_multisurface_duplicate_commit_count)
		_canonical_multisurface_by_room[room_key] = duplicate_record
		return false
	var has_combustion: bool = _canonical_combustion_by_room.has(room_key)
	var has_exchange: bool = _canonical_multisurface_exchange_by_room.has(room_key)
	if (not has_combustion and not has_exchange) \
			or not _canonical_surface_state_by_room.has(room_key):
		return false
	var combustion: Dictionary = _canonical_combustion_by_room.get(
		room_key, {}
	).duplicate(true)
	var atomic_fraction: float = clampf(
		float(combustion.get("atomic_accepted_fraction", 1.0)), 0.0, 1.0
	)
	var requested_radiation_kj: float = maxf(
		0.0, float(combustion.get("requested_radiative_energy_kj", 0.0))
	)
	var pre_atomic_accepted_radiation_kj: float = maxf(
		0.0, float(combustion.get("accepted_radiative_energy_kj", 0.0))
	)
	var accepted_radiation_kj: float = (
		pre_atomic_accepted_radiation_kj * atomic_fraction
	)
	var decision_rejected_radiation_kj: float = maxf(
		0.0, requested_radiation_kj - pre_atomic_accepted_radiation_kj
	)
	var atomic_rejected_radiation_kj: float = maxf(
		0.0, pre_atomic_accepted_radiation_kj - accepted_radiation_kj
	)
	var state_pre: Dictionary = _canonical_surface_state_by_room[
		room_key
	].duplicate(true)
	var state_post: Dictionary = state_pre.duplicate(true)
	var surface_energy_pre_kj: float = _canonical_multisurface_total_energy(state_pre)
	var routed_radiation_kj: float = 0.0
	var solver_residual_kj: float = 0.0
	var exchange: Dictionary = _canonical_multisurface_exchange_by_room.get(
		room_key, {}
	).duplicate(true)
	var exchange_fraction: float = clampf(
		float(exchange.get("accepted_fraction", 1.0)), 0.0, 1.0
	)
	var dt_s: float = maxf(
		0.000000001,
		float(exchange.get("dt_s", combustion.get("dt_s", 0.0)))
	)
	var surfaces: Dictionary = state_pre.get("surfaces", {})
	var weighted_area: float = 0.0
	for surface_name in ["ceiling", "upper_wall", "lower_wall", "floor"]:
		var weighted_surface: Dictionary = surfaces.get(surface_name, {})
		weighted_area += maxf(
			0.0, float(weighted_surface.get("area_m2", 0.0))
		) * maxf(0.0, float(weighted_surface.get("emissivity", 0.0)))
	if accepted_radiation_kj > THERMO_ENERGY_EPS_KJ \
			and weighted_area <= THERMO_ENERGY_EPS_KJ:
		return false

	var candidate_surfaces: Dictionary = surfaces.duplicate(true)
	var surface_fluxes: Dictionary = exchange.get("surface_fluxes", {})
	var accepted_gas_exchange_kj: float = 0.0
	var accepted_exterior_removed_kj: float = 0.0
	var cumulative: Dictionary = _canonical_multisurface_cumulative_by_room.get(
		room_key,
		{
			"step_count": 0.0,
			"upper_gas_exchange_kj": 0.0,
			"lower_gas_exchange_kj": 0.0,
			"gas_exchange_kj": 0.0,
			"requested_fire_radiation_kj": 0.0,
			"pre_atomic_accepted_fire_radiation_kj": 0.0,
			"decision_rejected_fire_radiation_kj": 0.0,
			"atomic_rejected_fire_radiation_kj": 0.0,
			"fire_radiation_kj": 0.0,
			"migration_energy_kj": 0.0,
			"exterior_removed_kj": 0.0,
			"combined_energy_residual_kj": 0.0,
			"solver_residual_kj": 0.0,
			"surfaces": {},
		}
	).duplicate(true)
	var cumulative_surfaces: Dictionary = cumulative.get(
		"surfaces", {}
	).duplicate(true)
	for surface_name in ["ceiling", "upper_wall", "lower_wall", "floor"]:
		var surface: Dictionary = surfaces.get(surface_name, {}).duplicate(true)
		var flux: Dictionary = surface_fluxes.get(surface_name, {})
		var convection_kj: float = float(
			flux.get("convection_requested_kj", 0.0)
		) * exchange_fraction
		var gas_radiation_kj: float = float(
			flux.get("gas_radiation_requested_kj", 0.0)
		) * exchange_fraction
		var exterior_removed_kj: float = float(
			flux.get("exterior_removed_requested_kj", 0.0)
		) * exchange_fraction
		var surface_radiation_kj: float = 0.0
		if accepted_radiation_kj > THERMO_ENERGY_EPS_KJ:
			surface_radiation_kj = accepted_radiation_kj * (
				maxf(0.0, float(surface.get("area_m2", 0.0)))
				* maxf(0.0, float(surface.get("emissivity", 0.0)))
				/ weighted_area
			)
		var solved: Dictionary = Phase3SurfaceEnergySolverScript.step_surface(
			surface,
			{
				"dt_s": dt_s,
				"interior_convection_energy_kj": convection_kj,
				"gas_radiation_energy_kj": gas_radiation_kj,
				"fire_radiation_energy_kj": surface_radiation_kj,
				"exterior_energy_removed_kj": exterior_removed_kj,
			}
		)
		if not bool(solved.get("valid", false)):
			return false
		candidate_surfaces[surface_name] = solved["post_state"]
		var surface_gas_exchange_kj: float = convection_kj + gas_radiation_kj
		accepted_gas_exchange_kj += surface_gas_exchange_kj
		accepted_exterior_removed_kj += exterior_removed_kj
		routed_radiation_kj += surface_radiation_kj
		solver_residual_kj += float(solved.get("energy_residual_kj", 0.0))
		var surface_cumulative: Dictionary = cumulative_surfaces.get(
			surface_name,
			{
				"gas_exchange_kj": 0.0,
				"fire_radiation_kj": 0.0,
				"exterior_removed_kj": 0.0,
			}
		).duplicate(true)
		surface_cumulative["gas_exchange_kj"] = float(
			surface_cumulative.get("gas_exchange_kj", 0.0)
		) + surface_gas_exchange_kj
		surface_cumulative["fire_radiation_kj"] = float(
			surface_cumulative.get("fire_radiation_kj", 0.0)
		) + surface_radiation_kj
		surface_cumulative["exterior_removed_kj"] = float(
			surface_cumulative.get("exterior_removed_kj", 0.0)
		) + exterior_removed_kj
		cumulative_surfaces[surface_name] = surface_cumulative
	state_post["surfaces"] = candidate_surfaces

	var surface_energy_post_kj: float = _canonical_multisurface_total_energy(state_post)
	var storage_residual_kj: float = (
		surface_energy_post_kj - surface_energy_pre_kj
		- accepted_gas_exchange_kj - routed_radiation_kj
		+ accepted_exterior_removed_kj
	)
	var accepted_upper_exchange_kj: float = float(
		exchange.get("upper_exchange_requested_kj", 0.0)
	) * exchange_fraction
	var accepted_lower_exchange_kj: float = float(
		exchange.get("lower_exchange_requested_kj", 0.0)
	) * exchange_fraction
	var combined_energy_residual_kj: float = (
		-accepted_gas_exchange_kj
		+ surface_energy_post_kj - surface_energy_pre_kj
		+ accepted_exterior_removed_kj - routed_radiation_kj
	)
	cumulative["step_count"] = float(cumulative.get("step_count", 0.0)) + 1.0
	cumulative["upper_gas_exchange_kj"] = float(
		cumulative.get("upper_gas_exchange_kj", 0.0)
	) + accepted_upper_exchange_kj
	cumulative["lower_gas_exchange_kj"] = float(
		cumulative.get("lower_gas_exchange_kj", 0.0)
	) + accepted_lower_exchange_kj
	cumulative["gas_exchange_kj"] = float(
		cumulative.get("gas_exchange_kj", 0.0)
	) + accepted_gas_exchange_kj
	cumulative["requested_fire_radiation_kj"] = float(
		cumulative.get("requested_fire_radiation_kj", 0.0)
	) + requested_radiation_kj
	cumulative["pre_atomic_accepted_fire_radiation_kj"] = float(
		cumulative.get("pre_atomic_accepted_fire_radiation_kj", 0.0)
	) + pre_atomic_accepted_radiation_kj
	cumulative["decision_rejected_fire_radiation_kj"] = float(
		cumulative.get("decision_rejected_fire_radiation_kj", 0.0)
	) + decision_rejected_radiation_kj
	cumulative["atomic_rejected_fire_radiation_kj"] = float(
		cumulative.get("atomic_rejected_fire_radiation_kj", 0.0)
	) + atomic_rejected_radiation_kj
	cumulative["fire_radiation_kj"] = float(
		cumulative.get("fire_radiation_kj", 0.0)
	) + routed_radiation_kj
	var multisurface_record_pre: Dictionary = _canonical_multisurface_by_room.get(
		room_key, {}
	)
	cumulative["migration_energy_kj"] = float(
		cumulative.get("migration_energy_kj", 0.0)
	) + float(multisurface_record_pre.get("migration_energy_kj", 0.0))
	cumulative["exterior_removed_kj"] = float(
		cumulative.get("exterior_removed_kj", 0.0)
	) + accepted_exterior_removed_kj
	cumulative["combined_energy_residual_kj"] = float(
		cumulative.get("combined_energy_residual_kj", 0.0)
	) + combined_energy_residual_kj
	cumulative["solver_residual_kj"] = float(
		cumulative.get("solver_residual_kj", 0.0)
	) + solver_residual_kj
	cumulative["surfaces"] = cumulative_surfaces
	_canonical_multisurface_cumulative_by_room[room_key] = cumulative
	_canonical_surface_state_by_room[room_key] = state_post
	_canonical_multisurface_radiation_committed_by_room[room_key] = true
	if has_combustion:
		combustion["atomic_accepted_radiative_energy_kj"] = accepted_radiation_kj
		combustion["routed_surface_radiation_kj"] = routed_radiation_kj
		combustion["radiative_route_residual_kj"] = (
			accepted_radiation_kj - routed_radiation_kj
		)
		if float(combustion.get(
			"canonical_fire_products_routing_active_flag", 0.0
		)) > 0.5:
			combustion[
				"canonical_fire_products_total_energy_route_residual_kj"
			] = float(combustion.get(
				"accepted_total_fire_energy_kj", 0.0
			)) * atomic_fraction - float(combustion.get(
				"routed_convective_energy_kj", 0.0
			)) - routed_radiation_kj
		_canonical_combustion_by_room[room_key] = combustion
	if has_exchange:
		exchange["accepted_upper_exchange_kj"] = accepted_upper_exchange_kj
		exchange["accepted_lower_exchange_kj"] = accepted_lower_exchange_kj
		exchange["accepted_exterior_removed_kj"] = accepted_exterior_removed_kj
		exchange["surface_storage_delta_kj"] = (
			surface_energy_post_kj - surface_energy_pre_kj
		)
		exchange["combined_energy_residual_kj"] = combined_energy_residual_kj
		exchange["solver_residual_kj"] = solver_residual_kj
		_canonical_multisurface_exchange_by_room[room_key] = exchange
	var record: Dictionary = _canonical_multisurface_by_room.get(
		room_key, {}
	).duplicate(true)
	record["radiation_requested_kj"] = requested_radiation_kj
	record["radiation_accepted_kj"] = accepted_radiation_kj
	record["radiation_routed_kj"] = routed_radiation_kj
	record["radiation_residual_kj"] = accepted_radiation_kj \
			- routed_radiation_kj + solver_residual_kj + storage_residual_kj
	record["surface_energy_pre_kj"] = surface_energy_pre_kj
	record["surface_energy_post_kj"] = surface_energy_post_kj
	record["gas_exchange_accepted_kj"] = accepted_gas_exchange_kj
	record["exterior_removed_accepted_kj"] = accepted_exterior_removed_kj
	record["combined_energy_residual_kj"] = (
		-accepted_gas_exchange_kj
		+ surface_energy_post_kj - surface_energy_pre_kj
		+ accepted_exterior_removed_kj - routed_radiation_kj
	)
	record["duplicate_commit_count"] = \
			float(_canonical_multisurface_duplicate_commit_count)
	_canonical_multisurface_by_room[room_key] = record
	return true


func _make_canonical_surface_state(
		area_m2: float,
		material: Dictionary,
		reference_temp_c: float
	) -> Dictionary:
	var state: Dictionary = Phase3SurfaceEnergySolverScript.make_uniform_state(
		area_m2,
		float(material["thickness_m"]),
		float(material["conductivity_kw_m_k"]),
		float(material["density_kg_m3"]),
		float(material["cp_kj_kg_k"]),
		reference_temp_c,
		reference_temp_c
	)
	state["emissivity"] = float(material["emissivity"])
	return state


func _canonical_multisurface_total_energy(state: Dictionary) -> float:
	var total_kj: float = 0.0
	var surfaces: Dictionary = state.get("surfaces", {})
	for surface_name in ["ceiling", "upper_wall", "lower_wall", "floor"]:
		var surface: Dictionary = surfaces.get(surface_name, {})
		if surface.is_empty():
			continue
		total_kj += Phase3SurfaceEnergySolverScript.stored_energy_kj(surface)
	return total_kj


func _surface_energy_for_area(surface: Dictionary, area_m2: float) -> float:
	var surface_area_m2: float = maxf(
		0.000000001, float(surface.get("area_m2", 0.0))
	)
	return Phase3SurfaceEnergySolverScript.stored_energy_kj(surface) \
			* area_m2 / surface_area_m2


func _mix_surface_area_profiles(
		target: Dictionary,
		target_area_m2: float,
		donor: Dictionary,
		moved_area_m2: float,
		new_target_area_m2: float
	) -> Dictionary:
	var result: Dictionary = target.duplicate(true)
	if new_target_area_m2 <= 0.0:
		result["area_m2"] = 0.0
		return result
	var target_nodes: Array = target.get("nodes_c", [])
	var donor_nodes: Array = donor.get("nodes_c", [])
	var mixed_nodes: Array = []
	for index: int in range(Phase3SurfaceEnergySolverScript.NODE_COUNT):
		mixed_nodes.append(
			(
				float(target_nodes[index]) * target_area_m2
				+ float(donor_nodes[index]) * moved_area_m2
			) / new_target_area_m2
		)
	result["area_m2"] = new_target_area_m2
	result["nodes_c"] = mixed_nodes
	return result


func _validate_multisurface_geometry(geometry: Dictionary) -> String:
	for field_name in ["floor_area_m2", "perimeter_m", "height_m", "interface_m"]:
		if not geometry.has(field_name):
			return "missing geometry field: " + field_name
		var value: float = float(geometry[field_name])
		if not is_finite(value):
			return "non-finite geometry field: " + field_name
	for field_name in ["floor_area_m2", "perimeter_m", "height_m"]:
		if float(geometry[field_name]) <= 0.0:
			return "invalid positive geometry field: " + field_name
	var interface_m: float = float(geometry["interface_m"])
	if interface_m < 0.0 or interface_m > float(geometry["height_m"]):
		return "interface_m outside room"
	return ""


func _validate_multisurface_material(material: Dictionary) -> String:
	for field_name in [
		"conductivity_kw_m_k",
		"density_kg_m3",
		"cp_kj_kg_k",
		"thickness_m",
		"emissivity",
	]:
		if not material.has(field_name):
			return "missing material field: " + field_name
		var value: float = float(material[field_name])
		if not is_finite(value) or value <= 0.0:
			return "invalid positive material field: " + field_name
	if float(material["emissivity"]) > 1.0:
		return "emissivity above one"
	return ""


func _multisurface_material_matches(
		existing: Dictionary,
		candidate: Dictionary
	) -> bool:
	for field_name in [
		"conductivity_kw_m_k",
		"density_kg_m3",
		"cp_kj_kg_k",
		"thickness_m",
		"emissivity",
	]:
		if not existing.has(field_name) or not candidate.has(field_name):
			return false
		var existing_value: float = float(existing[field_name])
		var candidate_value: float = float(candidate[field_name])
		if not is_finite(existing_value) or not is_finite(candidate_value) \
				or absf(existing_value - candidate_value) > 1.0e-12:
			return false
	return true


## Queues the gas-facing part as one atomic energy bundle. Wall storage and
## ambient accounting are committed after all routes have resolved, including
## the no-route wall-decay case.
func queue_canonical_wall_ambient_transfer(
		room_id: int,
		preview: Dictionary,
		legacy_requested: Dictionary,
		step_token: String
	) -> bool:
	if canonical_multisurface_shadow_enabled:
		return false
	var room_key: String = str(room_id)
	if room_id == EXTERIOR_ID or not _snapshots.has(room_key) \
			or not bool(preview.get("valid", false)):
		return false
	var upper_wall_signed_kj: float = float(
		preview.get("upper_wall_requested_kj", 0.0)
	)
	var lower_wall_signed_kj: float = float(
		preview.get("lower_wall_requested_kj", 0.0)
	)
	var upper_ambient_kj: float = maxf(
		0.0, float(preview.get("upper_ambient_requested_kj", 0.0))
	)
	var lower_ambient_kj: float = maxf(
		0.0, float(preview.get("lower_ambient_requested_kj", 0.0))
	)
	var record: Dictionary = preview.duplicate(true)
	record["legacy_upper_radiative_requested_kj"] = maxf(
		0.0, float(legacy_requested.get("thermal_upper_radiative_loss", 0.0))
	)
	record["legacy_upper_ambient_requested_kj"] = maxf(
		0.0, float(legacy_requested.get("thermal_upper_to_ambient", 0.0))
	)
	record["legacy_wall_absorption_requested_kj"] = maxf(
		0.0, float(legacy_requested.get("thermal_wall_absorption", 0.0))
	)
	record["legacy_wall_emission_requested_kj"] = maxf(
		0.0, float(legacy_requested.get("thermal_wall_emission", 0.0))
	)
	record["legacy_lower_decay_requested_kj"] = maxf(
		0.0, float(legacy_requested.get("thermal_lower_decay", 0.0))
	)
	record["legacy_lower_fresh_requested_kj"] = maxf(
		0.0, float(legacy_requested.get("thermal_lower_fresh_air_cooling", 0.0))
	)
	record["accepted_fraction"] = 1.0
	record["accepted_upper_wall_kj"] = 0.0
	record["accepted_lower_wall_kj"] = 0.0
	record["accepted_upper_ambient_kj"] = 0.0
	record["accepted_lower_ambient_kj"] = 0.0
	record["wall_energy_post_kj"] = float(preview.get("wall_energy_pre_kj", 0.0))
	record["wall_temp_post_c"] = float(preview.get("wall_temp_pre_c", 20.0))
	record["gas_wall_energy_residual_kj"] = 0.0
	record["total_boundary_energy_residual_kj"] = 0.0
	_canonical_wall_ambient_by_room[room_key] = record
	var routes: Array = []
	var bundle_id: String = "canonical_wall_ambient:%d:%s" % [room_id, step_token]
	if upper_wall_signed_kj > THERMO_ENERGY_EPS_KJ:
		routes.append(make_atomic_route(
			bundle_id + ":upper_to_wall", "canonical_upper_to_wall", room_id,
			EXTERIOR_ID, ZONE_UPPER, ZONE_UPPER, 0.0, upper_wall_signed_kj, 0.0, {}
		))
	elif upper_wall_signed_kj < -THERMO_ENERGY_EPS_KJ:
		routes.append(make_atomic_route(
			bundle_id + ":wall_to_upper", "canonical_wall_to_upper", EXTERIOR_ID,
			room_id, ZONE_UPPER, ZONE_UPPER, 0.0, -upper_wall_signed_kj, 0.0, {}
		))
	if lower_wall_signed_kj > THERMO_ENERGY_EPS_KJ:
		routes.append(make_atomic_route(
			bundle_id + ":lower_to_wall", "canonical_lower_to_wall", room_id,
			EXTERIOR_ID, ZONE_LOWER, ZONE_LOWER, 0.0, lower_wall_signed_kj, 0.0, {}
		))
	elif lower_wall_signed_kj < -THERMO_ENERGY_EPS_KJ:
		routes.append(make_atomic_route(
			bundle_id + ":wall_to_lower", "canonical_wall_to_lower", EXTERIOR_ID,
			room_id, ZONE_LOWER, ZONE_LOWER, 0.0, -lower_wall_signed_kj, 0.0, {}
		))
	if upper_ambient_kj > THERMO_ENERGY_EPS_KJ:
		routes.append(make_atomic_route(
			bundle_id + ":upper_to_ambient", "canonical_upper_to_ambient", room_id,
			EXTERIOR_ID, ZONE_UPPER, ZONE_UPPER, 0.0, upper_ambient_kj, 0.0, {}
		))
	if lower_ambient_kj > THERMO_ENERGY_EPS_KJ:
		routes.append(make_atomic_route(
			bundle_id + ":lower_to_ambient", "canonical_lower_to_ambient", room_id,
			EXTERIOR_ID, ZONE_LOWER, ZONE_LOWER, 0.0, lower_ambient_kj, 0.0, {}
		))
	if routes.is_empty():
		return true
	return add_atomic_bundle(make_atomic_bundle(
		bundle_id,
		"canonical_wall_ambient",
		routes,
		{
			"kind": "canonical_wall_ambient",
			"room_id": room_id,
			"upper_wall_signed_kj": upper_wall_signed_kj,
			"lower_wall_signed_kj": lower_wall_signed_kj,
			"upper_ambient_kj": upper_ambient_kj,
			"lower_ambient_kj": lower_ambient_kj,
		}
	))


func get_persistent_combustion_state(room_id: int) -> Dictionary:
	return _persistent_combustion_state.get(str(room_id), {}).duplicate(true)


func stage_canonical_combustion_transaction(transaction: Dictionary) -> bool:
	var room_id: int = int(transaction.get("room_id", EXTERIOR_ID))
	var room_key: String = str(room_id)
	if room_id == EXTERIOR_ID or not _snapshots.has(room_key):
		return false
	var record: Dictionary = transaction.duplicate(true)
	record["atomic_accepted_fraction"] = 1.0
	record["effective_fraction"] = clampf(
		float(record.get("decision_fraction", 0.0)), 0.0, 1.0
	)
	var products_routing_active: bool = float(
		record.get("canonical_fire_products_routing_active_flag", 0.0)
	) > 0.5
	record["requested_convective_energy_kj"] = maxf(
		0.0,
		float(record.get(
			"canonical_fire_products_requested_convective_energy_kj", 0.0
		))
	) if products_routing_active else 0.0
	record["accepted_convective_energy_kj"] = maxf(
		0.0,
		float(record.get(
			"canonical_fire_products_accepted_convective_energy_kj", 0.0
		))
	) if products_routing_active else 0.0
	record["requested_radiative_energy_kj"] = maxf(
		0.0, float(record.get("requested_radiative_energy_kj", 0.0))
	)
	record["accepted_radiative_energy_kj"] = maxf(
		0.0, float(record.get("accepted_radiative_energy_kj", 0.0))
	)
	record["atomic_accepted_radiative_energy_kj"] = 0.0
	record["routed_surface_radiation_kj"] = 0.0
	record["radiative_route_residual_kj"] = 0.0
	record["fire_partition_residual_kj"] = 0.0
	record["requested_plume_mass_kg"] = 0.0
	record["accepted_plume_mass_kg"] = 0.0
	record["requested_plume_energy_kj"] = 0.0
	record["accepted_plume_energy_kj"] = 0.0
	record["committed_fire_state"] = record.get(
		"fire_state_proposed", {}
	).duplicate(true)
	_canonical_combustion_by_room[room_key] = record
	return true


func get_canonical_combustion_room_ids() -> Array[int]:
	var room_ids: Array[int] = []
	for room_key in _canonical_combustion_by_room.keys():
		room_ids.append(int(room_key))
	return room_ids


func get_canonical_combustion_transaction(room_id: int) -> Dictionary:
	return _canonical_combustion_by_room.get(str(room_id), {}).duplicate(true)


## Completa una unica transaccion atomica con calor convectivo y plume observados.
## El evaluador ya tomo una decision comun; este bundle solo impone inventario.
func finalize_canonical_combustion_bundle(
		room_id: int,
		convective_flux: Dictionary,
		plume_flux: Dictionary,
		step_token: String
	) -> bool:
	var room_key: String = str(room_id)
	if not _canonical_combustion_by_room.has(room_key):
		return false
	var record: Dictionary = _canonical_combustion_by_room[room_key].duplicate(true)
	var decision_fraction: float = clampf(
		float(record.get("decision_fraction", 0.0)), 0.0, 1.0
	)
	var heat_scale: float = clampf(float(record.get("heat_scale", 0.0)), 0.0, 1.0)
	var plume_scale: float = 1.0 if bool(
		plume_flux.get("o2_decision_applied", false)
	) else clampf(float(record.get("plume_scale", 0.0)), 0.0, 1.0)
	var products_routing_active: bool = float(
		record.get("canonical_fire_products_routing_active_flag", 0.0)
	) > 0.5
	var requested_heat_kj: float = maxf(
		0.0, float(record.get(
			"canonical_fire_products_requested_convective_energy_kj", 0.0
		))
	) if products_routing_active else maxf(
		0.0, float(convective_flux.get("sensible_enthalpy_kj", 0.0))
	)
	var accepted_heat_kj: float = maxf(
		0.0, float(record.get(
			"canonical_fire_products_accepted_convective_energy_kj", 0.0
		))
	) if products_routing_active else requested_heat_kj * heat_scale
	var requested_plume_mass_kg: float = maxf(
		0.0, float(plume_flux.get("gas_mass_kg", 0.0))
	)
	var requested_plume_energy_kj: float = maxf(
		0.0, float(plume_flux.get("sensible_enthalpy_kj", 0.0))
	)
	var canonical_input: Dictionary = get_canonical_combustion_input(room_id)
	var lower_zone_available: bool = float(
		canonical_input.get("lower_gas_kg", 0.0)
	) > THERMO_MASS_EPS_KG
	var accepted_plume_mass_kg: float = requested_plume_mass_kg * plume_scale \
			if lower_zone_available else 0.0
	var accepted_plume_energy_kj: float = requested_plume_energy_kj * plume_scale \
			if lower_zone_available else 0.0
	var accepted_o2_kg: float = maxf(0.0, float(record.get("accepted_o2_kg", 0.0)))
	var o2_source_zone: String = String(record.get("o2_source_zone", ZONE_UPPER))
	if o2_source_zone not in [ZONE_UPPER, ZONE_LOWER]:
		o2_source_zone = ZONE_UPPER
	var lower_o2_fraction: float = clampf(
		float(canonical_input.get("lower_o2_fraction", 0.0)), 0.0, 1.0
	)
	var coupled_lower_combustion: bool = bool(
		float(record.get("post_opening_coupling_active_flag", 0.0)) > 0.5
	) and o2_source_zone == ZONE_LOWER
	var combustion_air_min_plume_mass_kg: float = 0.0
	if coupled_lower_combustion and accepted_o2_kg > 0.0 \
			and lower_o2_fraction > 0.000000001 and lower_zone_available:
		combustion_air_min_plume_mass_kg = accepted_o2_kg / lower_o2_fraction
		accepted_plume_mass_kg = minf(
			maxf(accepted_plume_mass_kg, combustion_air_min_plume_mass_kg),
			maxf(0.0, float(canonical_input.get("lower_gas_kg", 0.0)))
		)
		var lower_mass_kg: float = maxf(
			0.000000001, float(canonical_input.get("lower_gas_kg", 0.0))
		)
		accepted_plume_energy_kj = maxf(
			0.0, float(canonical_input.get("lower_energy_kj", 0.0))
		) * accepted_plume_mass_kg / lower_mass_kg
	var entrained_plume_o2_kg: float = accepted_plume_mass_kg * lower_o2_fraction
	var accepted_plume_o2_kg: float = entrained_plume_o2_kg
	if coupled_lower_combustion:
		# Combustion and plume share one lower-air parcel. The O2 sink consumes
		# part of that parcel; only the unburned remainder reaches upper.
		accepted_plume_o2_kg = maxf(0.0, entrained_plume_o2_kg - accepted_o2_kg)
	record["requested_convective_energy_kj"] = requested_heat_kj
	record["accepted_convective_energy_kj"] = accepted_heat_kj
	var requested_total_fire_energy_kj: float = maxf(
		0.0, float(record.get("requested_total_fire_energy_kj", 0.0))
	)
	var accepted_total_fire_energy_kj: float = maxf(
		0.0, float(record.get("accepted_total_fire_energy_kj", 0.0))
	)
	if not products_routing_active \
			and (requested_total_fire_energy_kj > THERMO_ENERGY_EPS_KJ \
			or accepted_total_fire_energy_kj > THERMO_ENERGY_EPS_KJ):
		# Thermal owns the exact convective route, including its two-zone and
		# opening modifiers. Radiation is the complementary accepted fire
		# energy, so two independent chi_rad formulas cannot double count.
		record["requested_radiative_energy_kj"] = maxf(
			0.0, requested_total_fire_energy_kj - requested_heat_kj
		)
		record["accepted_radiative_energy_kj"] = maxf(
			0.0, accepted_total_fire_energy_kj - accepted_heat_kj
		)
		record["effective_chi_rad"] = (
			float(record["accepted_radiative_energy_kj"])
			/ accepted_total_fire_energy_kj
			if accepted_total_fire_energy_kj > THERMO_ENERGY_EPS_KJ
			else 0.0
		)
	record["fire_partition_residual_kj"] = float(
		record.get("accepted_total_fire_energy_kj", 0.0)
	) - accepted_heat_kj - float(
		record.get("accepted_radiative_energy_kj", 0.0)
	)
	record["requested_plume_mass_kg"] = requested_plume_mass_kg
	record["accepted_plume_mass_kg"] = accepted_plume_mass_kg
	record["requested_plume_energy_kj"] = requested_plume_energy_kj
	record["accepted_plume_energy_kj"] = accepted_plume_energy_kj
	record["post_opening_combustion_air_min_plume_mass_kg"] = \
			combustion_air_min_plume_mass_kg
	record["post_opening_plume_height_term_mass_kg"] = maxf(
		0.0, float(plume_flux.get("height_term_mass_kg", 0.0))
	)
	record["post_opening_plume_source_term_mass_kg"] = maxf(
		0.0, float(plume_flux.get("source_term_mass_kg", 0.0))
	)
	record["post_opening_plume_o2_to_upper_kg"] = accepted_plume_o2_kg
	record["canonical_fire_products_coupled_plume_qc_kw"] = maxf(
		0.0, float(plume_flux.get("coupled_qc_kw", 0.0))
	)
	record["canonical_fire_products_plume_qc_residual_kw"] = float(
		record.get("canonical_fire_products_plume_driver_qc_kw", 0.0)
	) - float(record["canonical_fire_products_coupled_plume_qc_kw"]) \
			if products_routing_active else 0.0
	record["post_opening_lower_o2_closure_residual_kg"] = entrained_plume_o2_kg \
			- accepted_o2_kg - accepted_plume_o2_kg if coupled_lower_combustion else 0.0

	var routes: Array = []
	if accepted_o2_kg > 0.0:
		routes.append(make_atomic_route(
			"f32b1:%s:%d:o2" % [step_token, room_id],
			"canonical_combustion_o2_sink",
			room_id,
			EXTERIOR_ID,
			o2_source_zone,
			o2_source_zone,
			0.0,
			0.0,
			accepted_o2_kg,
			{}
		))
	var accepted_species: Dictionary = _parcel_species(
		record.get("accepted_species_kg", {})
	)
	if _sum_parcel_species(accepted_species) > 0.0:
		routes.append(make_atomic_route(
			"f32b1:%s:%d:species" % [step_token, room_id],
			"canonical_combustion_species_source",
			EXTERIOR_ID,
			room_id,
			ZONE_UPPER,
			ZONE_UPPER,
			0.0,
			0.0,
			0.0,
			accepted_species
		))
	if accepted_heat_kj > 0.0:
		routes.append(make_atomic_route(
			"f32b1:%s:%d:heat" % [step_token, room_id],
			"canonical_combustion_convective_heat",
			EXTERIOR_ID,
			room_id,
			ZONE_UPPER,
			ZONE_UPPER,
			0.0,
			accepted_heat_kj,
			0.0,
			{}
		))
	if accepted_plume_mass_kg > 0.0 or accepted_plume_energy_kj > 0.0:
		routes.append(make_atomic_route(
			"f32b1:%s:%d:plume" % [step_token, room_id],
			"canonical_combustion_plume",
			room_id,
			room_id,
			ZONE_LOWER,
			ZONE_UPPER,
			accepted_plume_mass_kg,
			accepted_plume_energy_kj,
			accepted_plume_o2_kg,
			{}
		))

	if routes.is_empty():
		record["atomic_accepted_fraction"] = 1.0
		record["effective_fraction"] = decision_fraction
		record["atomic_accepted_radiative_energy_kj"] = maxf(
			0.0, float(record.get("accepted_radiative_energy_kj", 0.0))
		)
		record["radiative_route_residual_kj"] = float(
			record.get("atomic_accepted_radiative_energy_kj", 0.0)
		)
		record["committed_fire_state"] = record.get(
			"fire_state_proposed", {}
		).duplicate(true)
		_canonical_combustion_by_room[room_key] = record
		return true

	var bundle: Dictionary = make_atomic_bundle(
		"f32b1:%s:%d" % [step_token, room_id],
		"canonical_combustion_transaction",
		routes,
		{
			"kind": "canonical_combustion",
			"room_id": room_id,
			"transport_family": "canonical_combustion",
		}
	)
	_canonical_combustion_by_room[room_key] = record
	return add_atomic_bundle(bundle)


## Una zona sin masa no puede conservar energia ni especies independientes.
## Fusiona ese inventario en la zona restante sin cambiar los totales del room.
func _collapse_degenerate_zones(shadow: Dictionary) -> void:
	for room_key in shadow.keys():
		var state: Dictionary = shadow[room_key]
		var upper_mass_kg: float = maxf(0.0, float(state.get("upper_gas_kg", 0.0)))
		var lower_mass_kg: float = maxf(0.0, float(state.get("lower_gas_kg", 0.0)))
		var source_zone: String = ""
		var destination_zone: String = ""
		if lower_mass_kg <= THERMO_MASS_EPS_KG and upper_mass_kg > THERMO_MASS_EPS_KG:
			source_zone = ZONE_LOWER
			destination_zone = ZONE_UPPER
		elif upper_mass_kg <= THERMO_MASS_EPS_KG and lower_mass_kg > THERMO_MASS_EPS_KG:
			source_zone = ZONE_UPPER
			destination_zone = ZONE_LOWER
		else:
			continue
		var before: Dictionary = state.duplicate(true)
		_record_enthalpy_zone_collapse(
			int(room_key),
			source_zone,
			destination_zone,
			maxf(0.0, float(state.get(source_zone + "_energy_kj", 0.0)))
		)
		_record_mass_zone_collapse(
			int(room_key),
			source_zone,
			destination_zone,
			maxf(0.0, float(state.get(source_zone + "_gas_kg", 0.0)))
		)
		state[destination_zone + "_gas_kg"] = float(
			state.get(destination_zone + "_gas_kg", 0.0)
		) + float(state.get(source_zone + "_gas_kg", 0.0))
		state[destination_zone + "_energy_kj"] = float(
			state.get(destination_zone + "_energy_kj", 0.0)
		) + float(state.get(source_zone + "_energy_kj", 0.0))
		state[destination_zone + "_o2_kg"] = float(
			state.get(destination_zone + "_o2_kg", 0.0)
		) + float(state.get(source_zone + "_o2_kg", 0.0))
		var destination_species: Dictionary = state.get(
			destination_zone + "_species_kg", {}
		).duplicate(true)
		var source_species: Dictionary = state.get(source_zone + "_species_kg", {})
		for species_name in PARCEL_SPECIES:
			destination_species[species_name] = float(
				destination_species.get(species_name, 0.0)
			) + float(source_species.get(species_name, 0.0))
		state[destination_zone + "_species_kg"] = destination_species
		state[source_zone + "_gas_kg"] = 0.0
		state[source_zone + "_energy_kj"] = 0.0
		state[source_zone + "_o2_kg"] = 0.0
		state[source_zone + "_species_kg"] = _empty_species_inventory()
		shadow[room_key] = state
		var delta: Dictionary = _state_delta_summary(state, before)
		_persistent_zone_collapse_by_room[room_key] = {
			"count": 1.0,
			"source_zone_code": 1.0 if source_zone == ZONE_UPPER else 2.0,
			"mass_residual_kg": float(delta.get("mass_kg", 0.0)),
			"energy_residual_kj": float(delta.get("energy_kj", 0.0)),
			"o2_residual_kg": float(delta.get("o2_kg", 0.0)),
			"species_residual_kg": float(delta.get("species_kg", 0.0)),
		}


func _new_zone_collapse_record() -> Dictionary:
	return {
		"count": 0.0,
		"source_zone_code": 0.0,
		"mass_residual_kg": 0.0,
		"energy_residual_kj": 0.0,
		"o2_residual_kg": 0.0,
		"species_residual_kg": 0.0,
	}


func _new_enthalpy_residence_record() -> Dictionary:
	var record: Dictionary = {
		"accepted_route_count": 0.0,
		"legacy_route_count": 0.0,
	}
	for zone_name in [ZONE_UPPER, ZONE_LOWER]:
		record[zone_name + "_in_kj_total"] = 0.0
		record[zone_name + "_out_kj_total"] = 0.0
		for family_name in ENTHALPY_RESIDENCE_FAMILIES:
			record[family_name + "_" + zone_name + "_in_kj_total"] = 0.0
			record[family_name + "_" + zone_name + "_out_kj_total"] = 0.0
	return record


func _ensure_enthalpy_residence_record(room_key: String) -> Dictionary:
	if not _enthalpy_residence_cumulative_by_room.has(room_key):
		_enthalpy_residence_cumulative_by_room[room_key] = \
				_new_enthalpy_residence_record()
	return _enthalpy_residence_cumulative_by_room[room_key]


func _enthalpy_cause_family(cause: String) -> String:
	match cause:
		"canonical_combustion_convective_heat":
			return "combustion"
		"canonical_combustion_plume":
			return "plume"
		"thermal_upper_to_lower":
			return "interzone"
		"canonical_upper_to_wall", "canonical_lower_to_wall", \
		"canonical_wall_to_upper", "canonical_wall_to_lower":
			return "wall"
		"canonical_upper_to_ambient", "canonical_lower_to_ambient":
			return "ambient"
		"canonical_exterior_pressure":
			return "exterior"
		"canonical_exterior_counterflow_upper_out", \
		"canonical_exterior_counterflow_lower_in":
			return "exterior_counterflow"
		"canonical_interior_opening":
			return "interior_opening"
		"canonical_doorway_jet_entrainment":
			return "doorway_jet"
		"canonical_interior_pressure":
			return "interior_pressure"
		"delayed_parcel_carve", "delayed_parcel_delivery", \
		"delayed_parcel_resolution":
			return "parcel"
		"zone_collapse":
			return "zone_collapse"
	if cause.begins_with("delayed_parcel") \
			or cause.begins_with("delayed_species_parcel_"):
		return "parcel"
	return "legacy" if not cause.begins_with("canonical_") else "other"


func _accumulate_enthalpy_residence(
		room_id: int,
		zone_name: String,
		direction: String,
		family_name: String,
		energy_kj: float
	) -> void:
	if room_id == EXTERIOR_ID or energy_kj <= THERMO_ENERGY_EPS_KJ:
		return
	var room_key: String = str(room_id)
	var record: Dictionary = _ensure_enthalpy_residence_record(room_key)
	var total_key: String = zone_name + "_" + direction + "_kj_total"
	var family_key: String = family_name + "_" + zone_name + "_" \
			+ direction + "_kj_total"
	record[total_key] = float(record.get(total_key, 0.0)) + energy_kj
	record[family_key] = float(record.get(family_key, 0.0)) + energy_kj
	_enthalpy_residence_cumulative_by_room[room_key] = record


func _record_enthalpy_residence_route(
		shadow: Dictionary,
		route: Dictionary,
		accepted_fraction: float,
		is_legacy_request: bool = false
	) -> void:
	if not enthalpy_residence_diagnostics_enabled:
		return
	var moved_energy_kj: float = maxf(
		0.0, float(route.get("sensible_enthalpy_kj", 0.0))
	) * clampf(accepted_fraction, 0.0, 1.0)
	if moved_energy_kj <= THERMO_ENERGY_EPS_KJ:
		return
	var source_id: int = int(route.get("source_room_id", EXTERIOR_ID))
	var destination_id: int = int(route.get("destination_room_id", EXTERIOR_ID))
	var source_zone: String = String(route.get("source_zone", ZONE_UPPER))
	var destination_zone: String = String(route.get("destination_zone", ZONE_UPPER))
	var family_name: String = _enthalpy_cause_family(
		String(route.get("cause", ""))
	)
	var source_out_kj: float = moved_energy_kj
	if source_id != EXTERIOR_ID:
		var source: Dictionary = shadow.get(str(source_id), {})
		source_out_kj = minf(
			moved_energy_kj,
			maxf(0.0, float(source.get(source_zone + "_energy_kj", 0.0)))
		)
		_accumulate_enthalpy_residence(
			source_id, source_zone, "out", family_name, source_out_kj
		)
	if destination_id != EXTERIOR_ID:
		_accumulate_enthalpy_residence(
			destination_id, destination_zone, "in", family_name, moved_energy_kj
		)
	var touched_rooms: Dictionary = {}
	if source_id != EXTERIOR_ID:
		touched_rooms[str(source_id)] = true
	if destination_id != EXTERIOR_ID:
		touched_rooms[str(destination_id)] = true
	for room_key in touched_rooms.keys():
		var record: Dictionary = _ensure_enthalpy_residence_record(String(room_key))
		record["accepted_route_count"] = float(
			record.get("accepted_route_count", 0.0)
		) + 1.0
		if is_legacy_request:
			record["legacy_route_count"] = float(
				record.get("legacy_route_count", 0.0)
			) + 1.0
		_enthalpy_residence_cumulative_by_room[String(room_key)] = record


func _record_enthalpy_zone_collapse(
		room_id: int,
		source_zone: String,
		destination_zone: String,
		energy_kj: float
	) -> void:
	if not enthalpy_residence_diagnostics_enabled \
			or energy_kj <= THERMO_ENERGY_EPS_KJ:
		return
	_accumulate_enthalpy_residence(
		room_id, source_zone, "out", "zone_collapse", energy_kj
	)
	_accumulate_enthalpy_residence(
		room_id, destination_zone, "in", "zone_collapse", energy_kj
	)
	var record: Dictionary = _ensure_enthalpy_residence_record(str(room_id))
	record["accepted_route_count"] = float(
		record.get("accepted_route_count", 0.0)
	) + 1.0
	_enthalpy_residence_cumulative_by_room[str(room_id)] = record


func _enthalpy_residence_result(room_key: String, state: Dictionary) -> Dictionary:
	var initial: Dictionary = _enthalpy_residence_initial_by_room.get(room_key, {})
	var cumulative: Dictionary = _ensure_enthalpy_residence_record(room_key)
	var initial_upper_kj: float = float(initial.get("upper_energy_kj", 0.0))
	var initial_lower_kj: float = float(initial.get("lower_energy_kj", 0.0))
	var upper_in_kj: float = float(cumulative.get("upper_in_kj_total", 0.0))
	var upper_out_kj: float = float(cumulative.get("upper_out_kj_total", 0.0))
	var lower_in_kj: float = float(cumulative.get("lower_in_kj_total", 0.0))
	var lower_out_kj: float = float(cumulative.get("lower_out_kj_total", 0.0))
	var expected_upper_kj: float = initial_upper_kj + upper_in_kj - upper_out_kj
	var expected_lower_kj: float = initial_lower_kj + lower_in_kj - lower_out_kj
	var observed_upper_kj: float = float(state.get("upper_energy_kj", 0.0))
	var observed_lower_kj: float = float(state.get("lower_energy_kj", 0.0))
	var result: Dictionary = {
		"phase3_shadow_enthalpy_initial_upper_kj": initial_upper_kj,
		"phase3_shadow_enthalpy_initial_lower_kj": initial_lower_kj,
		"phase3_shadow_enthalpy_upper_in_kj_total": upper_in_kj,
		"phase3_shadow_enthalpy_upper_out_kj_total": upper_out_kj,
		"phase3_shadow_enthalpy_lower_in_kj_total": lower_in_kj,
		"phase3_shadow_enthalpy_lower_out_kj_total": lower_out_kj,
		"phase3_shadow_enthalpy_expected_upper_kj": expected_upper_kj,
		"phase3_shadow_enthalpy_expected_lower_kj": expected_lower_kj,
		"phase3_shadow_enthalpy_observed_upper_kj": observed_upper_kj,
		"phase3_shadow_enthalpy_observed_lower_kj": observed_lower_kj,
		"phase3_shadow_enthalpy_upper_residual_kj": \
				observed_upper_kj - expected_upper_kj,
		"phase3_shadow_enthalpy_lower_residual_kj": \
				observed_lower_kj - expected_lower_kj,
		"phase3_shadow_enthalpy_room_residual_kj": \
				observed_upper_kj + observed_lower_kj \
				- expected_upper_kj - expected_lower_kj,
		"phase3_shadow_enthalpy_accepted_route_count": float(
			cumulative.get("accepted_route_count", 0.0)
		),
		"phase3_shadow_enthalpy_legacy_route_count": float(
			cumulative.get("legacy_route_count", 0.0)
		),
	}
	for family_name in ENTHALPY_RESIDENCE_FAMILIES:
		for zone_name in [ZONE_UPPER, ZONE_LOWER]:
			for direction in ["in", "out"]:
				var source_key: String = family_name + "_" + zone_name + "_" \
						+ direction + "_kj_total"
				var result_key: String = "phase3_shadow_enthalpy_" + source_key
				result[result_key] = float(cumulative.get(source_key, 0.0))
	return result


func _new_mass_residence_record() -> Dictionary:
	var record: Dictionary = {
		"accepted_route_count": 0.0,
		"legacy_route_count": 0.0,
	}
	for zone_name in [ZONE_UPPER, ZONE_LOWER]:
		record[zone_name + "_in_kg_total"] = 0.0
		record[zone_name + "_out_kg_total"] = 0.0
		for family_name in MASS_RESIDENCE_FAMILIES:
			record[family_name + "_" + zone_name + "_in_kg_total"] = 0.0
			record[family_name + "_" + zone_name + "_out_kg_total"] = 0.0
	return record


func _ensure_mass_residence_record(room_key: String) -> Dictionary:
	if not _mass_residence_cumulative_by_room.has(room_key):
		_mass_residence_cumulative_by_room[room_key] = \
				_new_mass_residence_record()
	return _mass_residence_cumulative_by_room[room_key]


func _mass_cause_family(cause: String) -> String:
	if "reconcile" in cause or "projection" in cause:
		return "reconcile"
	return _enthalpy_cause_family(cause)


func _accumulate_mass_residence(
		room_id: int,
		zone_name: String,
		direction: String,
		family_name: String,
		mass_kg: float
	) -> void:
	if room_id == EXTERIOR_ID or mass_kg <= THERMO_MASS_EPS_KG:
		return
	var room_key: String = str(room_id)
	var record: Dictionary = _ensure_mass_residence_record(room_key)
	var total_key: String = zone_name + "_" + direction + "_kg_total"
	var family_key: String = family_name + "_" + zone_name + "_" \
			+ direction + "_kg_total"
	record[total_key] = float(record.get(total_key, 0.0)) + mass_kg
	record[family_key] = float(record.get(family_key, 0.0)) + mass_kg
	_mass_residence_cumulative_by_room[room_key] = record


func _record_mass_residence_route(
		route: Dictionary,
		accepted_fraction: float,
		is_legacy_request: bool = false
	) -> void:
	if not mass_residence_diagnostics_enabled:
		return
	var moved_mass_kg: float = maxf(
		0.0, float(route.get("gas_mass_kg", 0.0))
	) * clampf(accepted_fraction, 0.0, 1.0)
	if moved_mass_kg <= THERMO_MASS_EPS_KG:
		return
	var source_id: int = int(route.get("source_room_id", EXTERIOR_ID))
	var destination_id: int = int(route.get("destination_room_id", EXTERIOR_ID))
	var source_zone: String = String(route.get("source_zone", ZONE_UPPER))
	var destination_zone: String = String(route.get("destination_zone", ZONE_UPPER))
	var family_name: String = _mass_cause_family(String(route.get("cause", "")))
	_accumulate_mass_residence(
		source_id, source_zone, "out", family_name, moved_mass_kg
	)
	_accumulate_mass_residence(
		destination_id, destination_zone, "in", family_name, moved_mass_kg
	)
	var touched_rooms: Dictionary = {}
	if source_id != EXTERIOR_ID:
		touched_rooms[str(source_id)] = true
	if destination_id != EXTERIOR_ID:
		touched_rooms[str(destination_id)] = true
	for room_key in touched_rooms.keys():
		var record: Dictionary = _ensure_mass_residence_record(String(room_key))
		record["accepted_route_count"] = float(
			record.get("accepted_route_count", 0.0)
		) + 1.0
		if is_legacy_request:
			record["legacy_route_count"] = float(
				record.get("legacy_route_count", 0.0)
			) + 1.0
		_mass_residence_cumulative_by_room[String(room_key)] = record


func _record_mass_zone_collapse(
		room_id: int,
		source_zone: String,
		destination_zone: String,
		mass_kg: float
	) -> void:
	if not mass_residence_diagnostics_enabled \
			or mass_kg <= THERMO_MASS_EPS_KG:
		return
	_accumulate_mass_residence(
		room_id, source_zone, "out", "zone_collapse", mass_kg
	)
	_accumulate_mass_residence(
		room_id, destination_zone, "in", "zone_collapse", mass_kg
	)
	var record: Dictionary = _ensure_mass_residence_record(str(room_id))
	record["accepted_route_count"] = float(
		record.get("accepted_route_count", 0.0)
	) + 1.0
	_mass_residence_cumulative_by_room[str(room_id)] = record


func _mass_residence_result(room_key: String, state: Dictionary) -> Dictionary:
	var initial: Dictionary = _mass_residence_initial_by_room.get(room_key, {})
	var cumulative: Dictionary = _ensure_mass_residence_record(room_key)
	var initial_upper_kg: float = float(initial.get("upper_gas_kg", 0.0))
	var initial_lower_kg: float = float(initial.get("lower_gas_kg", 0.0))
	var upper_in_kg: float = float(cumulative.get("upper_in_kg_total", 0.0))
	var upper_out_kg: float = float(cumulative.get("upper_out_kg_total", 0.0))
	var lower_in_kg: float = float(cumulative.get("lower_in_kg_total", 0.0))
	var lower_out_kg: float = float(cumulative.get("lower_out_kg_total", 0.0))
	var expected_upper_kg: float = initial_upper_kg + upper_in_kg - upper_out_kg
	var expected_lower_kg: float = initial_lower_kg + lower_in_kg - lower_out_kg
	var observed_upper_kg: float = float(state.get("upper_gas_kg", 0.0))
	var observed_lower_kg: float = float(state.get("lower_gas_kg", 0.0))
	var result: Dictionary = {
		"phase3_shadow_mass_residence_initial_upper_kg": initial_upper_kg,
		"phase3_shadow_mass_residence_initial_lower_kg": initial_lower_kg,
		"phase3_shadow_mass_residence_upper_in_kg_total": upper_in_kg,
		"phase3_shadow_mass_residence_upper_out_kg_total": upper_out_kg,
		"phase3_shadow_mass_residence_lower_in_kg_total": lower_in_kg,
		"phase3_shadow_mass_residence_lower_out_kg_total": lower_out_kg,
		"phase3_shadow_mass_residence_expected_upper_kg": expected_upper_kg,
		"phase3_shadow_mass_residence_expected_lower_kg": expected_lower_kg,
		"phase3_shadow_mass_residence_observed_upper_kg": observed_upper_kg,
		"phase3_shadow_mass_residence_observed_lower_kg": observed_lower_kg,
		"phase3_shadow_mass_residence_upper_residual_kg": \
				observed_upper_kg - expected_upper_kg,
		"phase3_shadow_mass_residence_lower_residual_kg": \
				observed_lower_kg - expected_lower_kg,
		"phase3_shadow_mass_residence_room_residual_kg": \
				observed_upper_kg + observed_lower_kg \
				- expected_upper_kg - expected_lower_kg,
		"phase3_shadow_mass_residence_accepted_route_count": float(
			cumulative.get("accepted_route_count", 0.0)
		),
		"phase3_shadow_mass_residence_legacy_route_count": float(
			cumulative.get("legacy_route_count", 0.0)
		),
	}
	for family_name in MASS_RESIDENCE_FAMILIES:
		for zone_name in [ZONE_UPPER, ZONE_LOWER]:
			for direction in ["in", "out"]:
				var source_key: String = family_name + "_" + zone_name + "_" \
						+ direction + "_kg_total"
				var result_key: String = "phase3_shadow_mass_residence_" + source_key
				result[result_key] = float(cumulative.get(source_key, 0.0))
	return result


func _empty_species_inventory() -> Dictionary:
	var result: Dictionary = {}
	for species_name in PARCEL_SPECIES:
		result[species_name] = 0.0
	return result


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


## F3.2b6: preview puro del intercambio exterior por flotabilidad. El offset
## hidrostatico se resuelve para flujo masico neto cero; el alivio neto por
## presion sigue perteneciendo exclusivamente a F3.2a/F3.2b2.
func preview_canonical_exterior_counterflow(
		canonical_input: Dictionary,
		opening_geometry: Dictionary,
		outside_temp_c: float,
		discharge_coeff: float,
		dt: float,
		integration_segments: int = EXTERIOR_COUNTERFLOW_SEGMENTS
	) -> Dictionary:
	var result: Dictionary = _new_canonical_exterior_counterflow_preview()
	if not bool(canonical_input.get("valid", false)) or dt <= 0.0 \
			or discharge_coeff <= 0.0:
		result["invalid_flag"] = 1.0
		return result
	var bottom_m: float = maxf(0.0, float(opening_geometry.get("bottom_m", 0.0)))
	var top_m: float = maxf(bottom_m, float(opening_geometry.get("top_m", bottom_m)))
	var width_m: float = maxf(0.0, float(opening_geometry.get("width_m", 0.0)))
	var open_fraction: float = clampf(
		float(opening_geometry.get("open_fraction", 0.0)), 0.0, 1.0
	)
	var room_height_m: float = maxf(
		top_m, float(opening_geometry.get("room_height_m", top_m))
	)
	if top_m - bottom_m <= 1.0e-9 or width_m <= 0.0 or open_fraction <= 0.0 \
			or room_height_m <= 0.0:
		return result
	var upper_volume_m3: float = maxf(
		0.0, float(canonical_input.get("upper_volume_m3", 0.0))
	)
	var lower_volume_m3: float = maxf(
		0.0, float(canonical_input.get("lower_volume_m3", 0.0))
	)
	var upper_mass_kg: float = maxf(
		0.0, float(canonical_input.get("upper_gas_kg", 0.0))
	)
	var lower_mass_kg: float = maxf(
		0.0, float(canonical_input.get("lower_gas_kg", 0.0))
	)
	if upper_volume_m3 <= 1.0e-12 or upper_mass_kg <= THERMO_MASS_EPS_KG:
		return result
	var outside_temp_k: float = outside_temp_c + 273.15
	if outside_temp_k <= 0.0:
		result["invalid_flag"] = 1.0
		return result
	var reference_temp_k: float = float(
		canonical_input.get("reference_temp_c", outside_temp_c)
	) + 273.15
	var outside_density_kg_m3: float = AIR_DENSITY_REF_KG_M3 \
			* reference_temp_k / outside_temp_k
	var upper_density_kg_m3: float = upper_mass_kg / upper_volume_m3
	var lower_density_kg_m3: float = outside_density_kg_m3
	if lower_volume_m3 > 1.0e-12 and lower_mass_kg > THERMO_MASS_EPS_KG:
		lower_density_kg_m3 = lower_mass_kg / lower_volume_m3
	var interface_m: float = clampf(
		float(canonical_input.get("interface_m", room_height_m)), 0.0, room_height_m
	)
	if absf(upper_density_kg_m3 - outside_density_kg_m3) <= 1.0e-10 \
			and absf(lower_density_kg_m3 - outside_density_kg_m3) <= 1.0e-10:
		result["valid"] = true
		result["neutral_plane_m"] = 0.5 * (bottom_m + top_m)
		result["pressure_relief_pre_pa"] = float(
			canonical_input.get("pressure_gauge_pa", 0.0)
		)
		return result
	var segments: int = maxi(8, integration_segments)
	var pressure_bound_pa: float = maxf(
		1.0,
		GRAVITY_M_S2 * room_height_m * maxf(
			outside_density_kg_m3,
			maxf(upper_density_kg_m3, lower_density_kg_m3)
		) * 2.0
	)
	var low_offset_pa: float = -pressure_bound_pa
	var high_offset_pa: float = pressure_bound_pa
	for _iteration in range(72):
		var mid_offset_pa: float = 0.5 * (low_offset_pa + high_offset_pa)
		var mid_flow: Dictionary = _integrate_canonical_exterior_opening(
			bottom_m, top_m, width_m, open_fraction, interface_m,
			upper_density_kg_m3, lower_density_kg_m3, outside_density_kg_m3,
			mid_offset_pa, discharge_coeff, segments
		)
		if float(mid_flow.get("net_kg_s", 0.0)) > 0.0:
			high_offset_pa = mid_offset_pa
		else:
			low_offset_pa = mid_offset_pa
	var neutral_offset_pa: float = 0.5 * (low_offset_pa + high_offset_pa)
	var flow: Dictionary = _integrate_canonical_exterior_opening(
		bottom_m, top_m, width_m, open_fraction, interface_m,
		upper_density_kg_m3, lower_density_kg_m3, outside_density_kg_m3,
		neutral_offset_pa, discharge_coeff, segments
	)
	var gross_upper_out_kg_s: float = maxf(
		0.0, float(flow.get("upper_out_kg_s", 0.0))
	)
	var gross_lower_in_kg_s: float = maxf(0.0, float(flow.get("in_kg_s", 0.0)))
	var exchange_kg_s: float = minf(gross_upper_out_kg_s, gross_lower_in_kg_s)
	result["valid"] = true
	result["neutral_plane_m"] = _counterflow_neutral_plane_m(
		bottom_m, top_m, interface_m,
		upper_density_kg_m3, lower_density_kg_m3, outside_density_kg_m3,
		neutral_offset_pa
	)
	result["neutral_pressure_offset_pa"] = neutral_offset_pa
	result["gross_out_kg_s"] = maxf(0.0, float(flow.get("out_kg_s", 0.0)))
	result["gross_in_kg_s"] = gross_lower_in_kg_s
	result["gross_upper_out_kg_s"] = gross_upper_out_kg_s
	result["gross_lower_in_kg_s"] = gross_lower_in_kg_s
	result["exchange_kg_s"] = exchange_kg_s
	result["exchange_kg"] = exchange_kg_s * dt
	result["hydrostatic_net_kg_s"] = float(flow.get("net_kg_s", 0.0))
	result["opposed_out_kg_s"] = maxf(
		0.0, float(flow.get("out_kg_s", 0.0)) - gross_upper_out_kg_s
	)
	result["pressure_relief_pre_pa"] = float(
		canonical_input.get("pressure_gauge_pa", 0.0)
	)
	return result


func _integrate_canonical_exterior_opening(
		bottom_m: float,
		top_m: float,
		width_m: float,
		open_fraction: float,
		interface_m: float,
		upper_density_kg_m3: float,
		lower_density_kg_m3: float,
		outside_density_kg_m3: float,
		floor_pressure_offset_pa: float,
		discharge_coeff: float,
		segments: int
	) -> Dictionary:
	var out_kg_s: float = 0.0
	var upper_out_kg_s: float = 0.0
	var in_kg_s: float = 0.0
	var dz_m: float = (top_m - bottom_m) / float(maxi(1, segments))
	for segment_index in range(maxi(1, segments)):
		var z_m: float = bottom_m + (float(segment_index) + 0.5) * dz_m
		var inside_density_kg_m3: float = upper_density_kg_m3 \
				if z_m >= interface_m else lower_density_kg_m3
		var delta_p_pa: float = _canonical_exterior_delta_p_pa(
			z_m, interface_m, upper_density_kg_m3, lower_density_kg_m3,
			outside_density_kg_m3, floor_pressure_offset_pa
		)
		var strip_area_m2: float = width_m * open_fraction * dz_m
		if delta_p_pa > 0.0:
			var out_strip_kg_s: float = discharge_coeff * strip_area_m2 \
					* sqrt(2.0 * maxf(0.05, inside_density_kg_m3) * delta_p_pa)
			out_kg_s += out_strip_kg_s
			if z_m >= interface_m:
				upper_out_kg_s += out_strip_kg_s
		elif delta_p_pa < 0.0:
			in_kg_s += discharge_coeff * strip_area_m2 \
					* sqrt(2.0 * maxf(0.05, outside_density_kg_m3) * -delta_p_pa)
	return {
		"out_kg_s": out_kg_s,
		"upper_out_kg_s": upper_out_kg_s,
		"in_kg_s": in_kg_s,
		"net_kg_s": out_kg_s - in_kg_s,
	}


func _canonical_exterior_delta_p_pa(
		z_m: float,
		interface_m: float,
		upper_density_kg_m3: float,
		lower_density_kg_m3: float,
		outside_density_kg_m3: float,
		floor_pressure_offset_pa: float
	) -> float:
	var lower_height_m: float = minf(maxf(0.0, z_m), interface_m)
	var upper_height_m: float = maxf(0.0, z_m - interface_m)
	return floor_pressure_offset_pa + GRAVITY_M_S2 * (
		(outside_density_kg_m3 - lower_density_kg_m3) * lower_height_m
				+ (outside_density_kg_m3 - upper_density_kg_m3) * upper_height_m
	)


func _counterflow_neutral_plane_m(
		bottom_m: float,
		top_m: float,
		interface_m: float,
		upper_density_kg_m3: float,
		lower_density_kg_m3: float,
		outside_density_kg_m3: float,
		floor_pressure_offset_pa: float
	) -> float:
	var low_m: float = bottom_m
	var high_m: float = top_m
	var low_dp: float = _canonical_exterior_delta_p_pa(
		low_m, interface_m, upper_density_kg_m3, lower_density_kg_m3,
		outside_density_kg_m3, floor_pressure_offset_pa
	)
	var high_dp: float = _canonical_exterior_delta_p_pa(
		high_m, interface_m, upper_density_kg_m3, lower_density_kg_m3,
		outside_density_kg_m3, floor_pressure_offset_pa
	)
	if low_dp * high_dp > 0.0:
		return bottom_m if absf(low_dp) <= absf(high_dp) else top_m
	for _iteration in range(64):
		var mid_m: float = 0.5 * (low_m + high_m)
		var mid_dp: float = _canonical_exterior_delta_p_pa(
			mid_m, interface_m, upper_density_kg_m3, lower_density_kg_m3,
			outside_density_kg_m3, floor_pressure_offset_pa
		)
		if low_dp * mid_dp <= 0.0:
			high_m = mid_m
		else:
			low_m = mid_m
			low_dp = mid_dp
	return 0.5 * (low_m + high_m)


func _new_canonical_exterior_counterflow_preview() -> Dictionary:
	return {
		"valid": false,
		"invalid_flag": 0.0,
		"neutral_plane_m": 0.0,
		"neutral_pressure_offset_pa": 0.0,
		"gross_out_kg_s": 0.0,
		"gross_in_kg_s": 0.0,
		"gross_upper_out_kg_s": 0.0,
		"gross_lower_in_kg_s": 0.0,
		"exchange_kg_s": 0.0,
		"exchange_kg": 0.0,
		"hydrostatic_net_kg_s": 0.0,
		"opposed_out_kg_s": 0.0,
		"pressure_relief_pre_pa": 0.0,
	}


## Encola un intercambio bruto compensado por abertura. Cada bundle contiene
## exactamente dos rutas con la misma masa; por tanto no puede aliviar ni crear
## presion neta. F3.2a se ejecuta despues y conserva esa autoridad exclusiva.
func queue_canonical_exterior_counterflow_requests(
		building,
		dt: float,
		reference_temp_c: float,
		outside_o2: float,
		discharge_coeff: float = EXTERIOR_DISCHARGE_COEFF
	) -> void:
	if building == null or dt <= 0.0 or discharge_coeff <= 0.0:
		return
	var openings: Array = building.get_openings()
	for opening_position in range(openings.size()):
		var op = openings[opening_position]
		if op == null or not op.is_exterior_opening():
			continue
		var room_id: int = op.b if op.a == EXTERIOR_ID else op.a
		var room = building.get_room(room_id)
		var room_key: String = str(room_id)
		if room == null or not _snapshots.has(room_key):
			continue
		var smooth_fraction: float = op.open_fraction_smooth
		if smooth_fraction < 0.0:
			smooth_fraction = op.open_fraction
		smooth_fraction = clampf(smooth_fraction, 0.0, 1.0)
		if smooth_fraction <= 0.0:
			continue
		var canonical_input: Dictionary = get_canonical_thermodynamic_input(
			room, reference_temp_c
		)
		var preview: Dictionary = preview_canonical_exterior_counterflow(
			canonical_input,
			{
				"bottom_m": clampf(op.sill_m, 0.0, room.height_m),
				"top_m": clampf(op.lintel_height_m(), 0.0, room.height_m),
				"width_m": maxf(0.0, op.width_m),
				"open_fraction": smooth_fraction,
				"room_height_m": room.height_m,
			},
			reference_temp_c,
			discharge_coeff,
			dt
		)
		var record: Dictionary = _canonical_exterior_counterflow_by_room.get(
			room_key, _new_canonical_exterior_counterflow_record()
		).duplicate(true)
		record["opening_count"] = float(record.get("opening_count", 0.0)) + 1.0
		if not bool(preview.get("valid", false)):
			record["invalid_preview_count"] = float(
				record.get("invalid_preview_count", 0.0)
			) + float(preview.get("invalid_flag", 0.0))
			_canonical_exterior_counterflow_by_room[room_key] = record
			continue
		var raw_upper_out_kg: float = maxf(
			0.0, float(preview.get("gross_upper_out_kg_s", 0.0)) * dt
		)
		var raw_lower_in_kg: float = maxf(
			0.0, float(preview.get("gross_lower_in_kg_s", 0.0)) * dt
		)
		var exchange_kg: float = maxf(0.0, float(preview.get("exchange_kg", 0.0)))
		var neutral_weight_kg: float = maxf(exchange_kg, 1.0e-12)
		record["neutral_plane_weighted_m_kg"] = float(
			record.get("neutral_plane_weighted_m_kg", 0.0)
		) + float(preview.get("neutral_plane_m", 0.0)) * neutral_weight_kg
		record["neutral_plane_weight_kg"] = float(
			record.get("neutral_plane_weight_kg", 0.0)
		) + neutral_weight_kg
		record["neutral_plane_m"] = float(record["neutral_plane_weighted_m_kg"]) \
				/ maxf(1.0e-12, float(record["neutral_plane_weight_kg"]))
		record["neutral_pressure_offset_pa"] = float(
			preview.get("neutral_pressure_offset_pa", 0.0)
		)
		record["pressure_relief_pre_pa"] = float(
			preview.get("pressure_relief_pre_pa", 0.0)
		)
		record["raw_upper_out_kg"] = float(record.get("raw_upper_out_kg", 0.0)) \
				+ raw_upper_out_kg
		record["raw_lower_in_kg"] = float(record.get("raw_lower_in_kg", 0.0)) \
				+ raw_lower_in_kg
		record["hydrostatic_net_kg"] = float(
			record.get("hydrostatic_net_kg", 0.0)
		) + float(preview.get("hydrostatic_net_kg_s", 0.0)) * dt
		record["opposed_out_kg"] = float(record.get("opposed_out_kg", 0.0)) \
				+ float(preview.get("opposed_out_kg_s", 0.0)) * dt
		if exchange_kg <= THERMO_MASS_EPS_KG:
			_canonical_exterior_counterflow_by_room[room_key] = record
			continue
		var source_state: Dictionary = _snapshots[room_key]
		var upper_mass_kg: float = maxf(
			THERMO_MASS_EPS_KG, float(source_state.get("upper_gas_kg", 0.0))
		)
		var inventory_fraction: float = exchange_kg / upper_mass_kg
		var outgoing_energy_kj: float = float(
			source_state.get("upper_energy_kj", 0.0)
		) * inventory_fraction
		var outgoing_o2_kg: float = float(
			source_state.get("upper_o2_kg", 0.0)
		) * inventory_fraction
		var outgoing_species_kg: Dictionary = _parcel_species({})
		var source_species: Dictionary = source_state.get("upper_species_kg", {})
		for species_name in PARCEL_SPECIES:
			outgoing_species_kg[species_name] = float(
				source_species.get(species_name, 0.0)
			) * inventory_fraction
		var incoming_o2_kg: float = exchange_kg * clampf(outside_o2, 0.0, 1.0)
		record["requested_exchange_kg"] = float(
			record.get("requested_exchange_kg", 0.0)
		) + exchange_kg
		record["requested_outgoing_energy_kj"] = float(
			record.get("requested_outgoing_energy_kj", 0.0)
		) + outgoing_energy_kj
		record["requested_outgoing_o2_kg"] = float(
			record.get("requested_outgoing_o2_kg", 0.0)
		) + outgoing_o2_kg
		record["requested_incoming_o2_kg"] = float(
			record.get("requested_incoming_o2_kg", 0.0)
		) + incoming_o2_kg
		record["requested_outgoing_species_kg"] = float(
			record.get("requested_outgoing_species_kg", 0.0)
		) + _sum_parcel_species(outgoing_species_kg)
		_canonical_exterior_counterflow_by_room[room_key] = record
		var opening_id: int = op.opening_index if op.opening_index >= 0 else opening_position
		var bundle_id: String = "f32b6_exterior_counterflow:%d:%d" % [room_id, opening_id]
		var routes: Array = [
			make_atomic_route(
				bundle_id + ":upper_out",
				"canonical_exterior_counterflow_upper_out",
				room_id,
				EXTERIOR_ID,
				ZONE_UPPER,
				ZONE_UPPER,
				exchange_kg,
				outgoing_energy_kj,
				outgoing_o2_kg,
				outgoing_species_kg
			),
			make_atomic_route(
				bundle_id + ":lower_in",
				"canonical_exterior_counterflow_lower_in",
				EXTERIOR_ID,
				room_id,
				ZONE_LOWER,
				ZONE_LOWER,
				exchange_kg,
				0.0,
				incoming_o2_kg,
				{}
			),
		]
		var bundle: Dictionary = make_atomic_bundle(
			bundle_id,
			"canonical_exterior_counterflow",
			routes,
			{
				"kind": "canonical_exterior_counterflow",
				"room_id": room_id,
				"exchange_kg": exchange_kg,
				"outgoing_energy_kj": outgoing_energy_kj,
				"outgoing_o2_kg": outgoing_o2_kg,
				"incoming_o2_kg": incoming_o2_kg,
				"outgoing_species_kg": _sum_parcel_species(outgoing_species_kg),
			}
		)
		if not add_atomic_bundle(bundle):
			record = _canonical_exterior_counterflow_by_room[room_key].duplicate(true)
			record["duplicate_owner_flag"] = 1.0
			_canonical_exterior_counterflow_by_room[room_key] = record


func _new_canonical_exterior_counterflow_record() -> Dictionary:
	return {
		"opening_count": 0.0,
		"invalid_preview_count": 0.0,
		"neutral_plane_m": 0.0,
		"neutral_plane_weighted_m_kg": 0.0,
		"neutral_plane_weight_kg": 0.0,
		"neutral_pressure_offset_pa": 0.0,
		"pressure_relief_pre_pa": 0.0,
		"raw_upper_out_kg": 0.0,
		"raw_lower_in_kg": 0.0,
		"hydrostatic_net_kg": 0.0,
		"opposed_out_kg": 0.0,
		"requested_exchange_kg": 0.0,
		"accepted_exchange_kg": 0.0,
		"rejected_exchange_kg": 0.0,
		"requested_outgoing_energy_kj": 0.0,
		"accepted_outgoing_energy_kj": 0.0,
		"rejected_outgoing_energy_kj": 0.0,
		"requested_outgoing_o2_kg": 0.0,
		"accepted_outgoing_o2_kg": 0.0,
		"rejected_outgoing_o2_kg": 0.0,
		"requested_incoming_o2_kg": 0.0,
		"accepted_incoming_o2_kg": 0.0,
		"rejected_incoming_o2_kg": 0.0,
		"requested_outgoing_species_kg": 0.0,
		"accepted_outgoing_species_kg": 0.0,
		"rejected_outgoing_species_kg": 0.0,
		"accepted_fraction": 1.0,
		"mass_residual_kg": 0.0,
		"energy_residual_kj": 0.0,
		"o2_residual_kg": 0.0,
		"species_residual_kg": 0.0,
		"duplicate_owner_flag": 0.0,
		"cumulative_exchange_kg": 0.0,
	}


## F3.3a: pure hydrostatic exchange across one horizontal interior opening.
## The pressure offset is solved so the opening carries equal gross mass in
## both directions. Signed room-pressure relief remains outside this contract.
func preview_canonical_interior_opening(
		canonical_a: Dictionary,
		canonical_b: Dictionary,
		opening_geometry: Dictionary,
		discharge_coeff: float,
		dt: float,
		_integration_segments: int = EXTERIOR_COUNTERFLOW_SEGMENTS,
		source_preserving_destination_enabled: bool = false,
		buoyancy_destination_enabled: bool = false
	) -> Dictionary:
	var result: Dictionary = {
		"valid": false,
		"invalid_flag": 0.0,
		"neutral_plane_m": 0.0,
		"neutral_pressure_offset_pa": 0.0,
		"gross_a_to_b_kg": 0.0,
		"gross_b_to_a_kg": 0.0,
		"net_a_to_b_kg": 0.0,
		"exchange_kg": 0.0,
		"routes": [],
		"slabs": [],
	}
	if not bool(canonical_a.get("valid", false)) \
			or not bool(canonical_b.get("valid", false)) \
			or discharge_coeff <= 0.0 or dt <= 0.0:
		result["invalid_flag"] = 1.0
		return result
	var bottom_m: float = maxf(0.0, float(opening_geometry.get("bottom_m", 0.0)))
	var top_m: float = maxf(bottom_m, float(opening_geometry.get("top_m", bottom_m)))
	var width_m: float = maxf(0.0, float(opening_geometry.get("width_m", 0.0)))
	var open_fraction: float = clampf(
		float(opening_geometry.get("open_fraction", 0.0)), 0.0, 1.0
	)
	if top_m - bottom_m <= 1.0e-9 or width_m <= 0.0 or open_fraction <= 0.0:
		result["valid"] = true
		return result
	var densities_a: Dictionary = _canonical_zone_densities(canonical_a)
	var densities_b: Dictionary = _canonical_zone_densities(canonical_b)
	if not bool(densities_a.get("valid", false)) \
			or not bool(densities_b.get("valid", false)):
		result["invalid_flag"] = 1.0
		return result
	var max_density: float = maxf(
		float(densities_a.get("upper", 0.0)),
		maxf(
			float(densities_a.get("lower", 0.0)),
			maxf(
				float(densities_b.get("upper", 0.0)),
				float(densities_b.get("lower", 0.0))
			)
		)
	)
	var pressure_bound_pa: float = maxf(
		1.0, GRAVITY_M_S2 * maxf(0.1, top_m) * max_density * 2.0
	)
	var low_offset_pa: float = -pressure_bound_pa
	var high_offset_pa: float = pressure_bound_pa
	for _iteration in range(INTERIOR_PRESSURE_SOLVE_ITERATIONS):
		var mid_offset_pa: float = 0.5 * (low_offset_pa + high_offset_pa)
		var mid_flow: Dictionary = _integrate_canonical_interior_opening(
			canonical_a, canonical_b, densities_a, densities_b,
			bottom_m, top_m, width_m, open_fraction,
			mid_offset_pa, discharge_coeff,
			source_preserving_destination_enabled,
			buoyancy_destination_enabled
		)
		if float(mid_flow.get("net_a_to_b_kg_s", 0.0)) > 0.0:
			high_offset_pa = mid_offset_pa
		else:
			low_offset_pa = mid_offset_pa
	var neutral_offset_pa: float = 0.5 * (low_offset_pa + high_offset_pa)
	var flow: Dictionary = _integrate_canonical_interior_opening(
		canonical_a, canonical_b, densities_a, densities_b,
		bottom_m, top_m, width_m, open_fraction,
		neutral_offset_pa, discharge_coeff,
		source_preserving_destination_enabled,
		buoyancy_destination_enabled
	)
	var routes: Array[Dictionary] = []
	for raw_key in flow.get("route_kg_s", {}).keys():
		var parts: PackedStringArray = String(raw_key).split("|")
		if parts.size() != 4:
			continue
		var route_mass_kg: float = maxf(
			0.0, float(flow["route_kg_s"].get(raw_key, 0.0)) * dt
		)
		if route_mass_kg <= THERMO_MASS_EPS_KG:
			continue
		routes.append({
			"source_side": parts[0],
			"source_zone": parts[1],
			"destination_side": parts[2],
			"destination_zone": parts[3],
			"gas_mass_kg": route_mass_kg,
		})
	var slabs: Array[Dictionary] = []
	for raw_slab in flow.get("slabs", []):
		var slab: Dictionary = raw_slab.duplicate(true)
		slab["gas_mass_kg"] = maxf(
			0.0, float(slab.get("mass_flow_kg_s", 0.0)) * dt
		)
		slabs.append(slab)
	result["valid"] = true
	result["neutral_plane_m"] = float(flow.get("neutral_plane_m", 0.0))
	result["neutral_pressure_offset_pa"] = neutral_offset_pa
	result["gross_a_to_b_kg"] = maxf(0.0, float(flow.get("a_to_b_kg_s", 0.0)) * dt)
	result["gross_b_to_a_kg"] = maxf(0.0, float(flow.get("b_to_a_kg_s", 0.0)) * dt)
	result["net_a_to_b_kg"] = float(flow.get("net_a_to_b_kg_s", 0.0)) * dt
	result["exchange_kg"] = minf(
		float(result["gross_a_to_b_kg"]), float(result["gross_b_to_a_kg"])
	)
	result["routes"] = routes
	result["slabs"] = slabs
	return result


## F3.3b: signed pressure component for one horizontal opening. The gross
## buoyant exchange remains owned by F3.3a; this preview returns only the
## directional excess implied by the canonical room-pressure difference.
func preview_canonical_interior_pressure_flow(
		canonical_a: Dictionary,
		canonical_b: Dictionary,
		opening_geometry: Dictionary,
		discharge_coeff: float,
		dt: float,
		source_preserving_destination_enabled: bool = false,
		buoyancy_destination_enabled: bool = false
	) -> Dictionary:
	var result: Dictionary = {
		"valid": false,
		"invalid_flag": 0.0,
		"pressure_delta_pa": float(canonical_a.get("pressure_gauge_pa", 0.0))
				- float(canonical_b.get("pressure_gauge_pa", 0.0)),
		"raw_a_to_b_kg": 0.0,
		"raw_b_to_a_kg": 0.0,
		"signed_net_a_to_b_kg": 0.0,
		"routes": [],
		"slabs": [],
	}
	if not bool(canonical_a.get("valid", false)) \
			or not bool(canonical_b.get("valid", false)) \
			or discharge_coeff <= 0.0 or dt <= 0.0:
		result["invalid_flag"] = 1.0
		return result
	var bottom_m: float = maxf(0.0, float(opening_geometry.get("bottom_m", 0.0)))
	var top_m: float = maxf(bottom_m, float(opening_geometry.get("top_m", bottom_m)))
	var width_m: float = maxf(0.0, float(opening_geometry.get("width_m", 0.0)))
	var open_fraction: float = clampf(
		float(opening_geometry.get("open_fraction", 0.0)), 0.0, 1.0
	)
	if top_m - bottom_m <= 1.0e-9 or width_m <= 0.0 or open_fraction <= 0.0:
		result["valid"] = true
		return result
	var densities_a: Dictionary = _canonical_zone_densities(canonical_a)
	var densities_b: Dictionary = _canonical_zone_densities(canonical_b)
	if not bool(densities_a.get("valid", false)) \
			or not bool(densities_b.get("valid", false)):
		result["invalid_flag"] = 1.0
		return result
	var pressure_delta_pa: float = float(result["pressure_delta_pa"])
	var flow: Dictionary = _integrate_canonical_interior_opening(
		canonical_a, canonical_b, densities_a, densities_b,
		bottom_m, top_m, width_m, open_fraction,
		pressure_delta_pa, discharge_coeff,
		source_preserving_destination_enabled,
		buoyancy_destination_enabled
	)
	var a_to_b_kg_s: float = maxf(0.0, float(flow.get("a_to_b_kg_s", 0.0)))
	var b_to_a_kg_s: float = maxf(0.0, float(flow.get("b_to_a_kg_s", 0.0)))
	var net_a_to_b_kg_s: float = a_to_b_kg_s - b_to_a_kg_s
	var dominant_side: String = "a" if net_a_to_b_kg_s > 0.0 else "b"
	var dominant_total_kg_s: float = a_to_b_kg_s \
			if dominant_side == "a" else b_to_a_kg_s
	var signed_scale: float = absf(net_a_to_b_kg_s) \
			/ maxf(THERMO_MASS_EPS_KG, dominant_total_kg_s)
	var routes: Array[Dictionary] = []
	var slabs: Array[Dictionary] = []
	if absf(net_a_to_b_kg_s) > THERMO_MASS_EPS_KG:
		for raw_key in flow.get("route_kg_s", {}).keys():
			var parts: PackedStringArray = String(raw_key).split("|")
			if parts.size() != 4 or parts[0] != dominant_side:
				continue
			var route_mass_kg: float = maxf(
				0.0,
				float(flow["route_kg_s"].get(raw_key, 0.0)) * signed_scale * dt
			)
			if route_mass_kg <= THERMO_MASS_EPS_KG:
				continue
			routes.append({
				"source_side": parts[0],
				"source_zone": parts[1],
				"destination_side": parts[2],
				"destination_zone": parts[3],
				"gas_mass_kg": route_mass_kg,
			})
		for raw_slab in flow.get("slabs", []):
			var slab: Dictionary = raw_slab
			if String(slab.get("source_side", "")) != dominant_side:
				continue
			var scaled_slab: Dictionary = slab.duplicate(true)
			scaled_slab["mass_flow_kg_s"] = maxf(
				0.0, float(slab.get("mass_flow_kg_s", 0.0)) * signed_scale
			)
			scaled_slab["gas_mass_kg"] = float(
				scaled_slab.get("mass_flow_kg_s", 0.0)
			) * dt
			slabs.append(scaled_slab)
	result["valid"] = true
	result["raw_a_to_b_kg"] = a_to_b_kg_s * dt
	result["raw_b_to_a_kg"] = b_to_a_kg_s * dt
	result["signed_net_a_to_b_kg"] = net_a_to_b_kg_s * dt
	result["routes"] = routes
	result["slabs"] = slabs
	return result


## F3.3v3f0: recompone el counterflow existente con el neto de presion sin
## aumentar la masa bruta. Es una funcion pura; no registra ni aplica rutas.
func preview_fixed_gross_interior_pressure_skew(
		opening_routes: Array,
		pressure_routes: Array
	) -> Dictionary:
	var result: Dictionary = {
		"valid": false,
		"invalid_flag": 0.0,
		"opening_gross_mass_kg": 0.0,
		"preview_gross_mass_kg": 0.0,
		"pressure_net_mass_kg": 0.0,
		"accepted_pressure_net_mass_kg": 0.0,
		"opening_net_enthalpy_kj": 0.0,
		"preview_net_enthalpy_kj": 0.0,
		"cap_count": 0.0,
		"mass_residual_kg": 0.0,
		"energy_residual_kj": 0.0,
		"o2_residual_kg": 0.0,
		"species_residual_kg": 0.0,
		"routes": [],
		"connections": [],
	}
	var groups: Dictionary = {}
	for raw_route in opening_routes:
		var route: Dictionary = raw_route
		if not bool(route.get("valid", false)):
			result["invalid_flag"] = 1.0
			return result
		var connection_id: String = String(route.get("connection_id", ""))
		var source_id: int = int(route.get("source_room_id", EXTERIOR_ID))
		var destination_id: int = int(
			route.get("destination_room_id", EXTERIOR_ID)
		)
		if connection_id.is_empty() or source_id == EXTERIOR_ID \
				or destination_id == EXTERIOR_ID or source_id == destination_id:
			result["invalid_flag"] = 1.0
			return result
		if not groups.has(connection_id):
			groups[connection_id] = {
				"low_room_id": mini(source_id, destination_id),
				"high_room_id": maxi(source_id, destination_id),
				"opening_routes": [],
				"pressure_routes": [],
			}
		groups[connection_id]["opening_routes"].append(route)
	for raw_route in pressure_routes:
		var route: Dictionary = raw_route
		if not bool(route.get("valid", false)):
			result["invalid_flag"] = 1.0
			return result
		var connection_id: String = String(route.get("connection_id", ""))
		if not groups.has(connection_id):
			result["invalid_flag"] = 1.0
			return result
		groups[connection_id]["pressure_routes"].append(route)

	var preview_routes: Array[Dictionary] = []
	var connections: Array[Dictionary] = []
	for raw_connection_id in groups.keys():
		var connection_id: String = String(raw_connection_id)
		var group: Dictionary = groups[connection_id]
		var low_room_id: int = int(group["low_room_id"])
		var high_room_id: int = int(group["high_room_id"])
		var low_to_high_kg: float = 0.0
		var high_to_low_kg: float = 0.0
		var pressure_low_to_high_kg: float = 0.0
		var pressure_high_to_low_kg: float = 0.0
		for raw_route in group["opening_routes"]:
			var route: Dictionary = raw_route
			var route_mass_kg: float = maxf(
				0.0, float(route.get("gas_mass_kg", 0.0))
			)
			if int(route.get("source_room_id", EXTERIOR_ID)) == low_room_id:
				low_to_high_kg += route_mass_kg
			else:
				high_to_low_kg += route_mass_kg
		for raw_route in group["pressure_routes"]:
			var route: Dictionary = raw_route
			var route_mass_kg: float = maxf(
				0.0, float(route.get("gas_mass_kg", 0.0))
			)
			if int(route.get("source_room_id", EXTERIOR_ID)) == low_room_id:
				pressure_low_to_high_kg += route_mass_kg
			else:
				pressure_high_to_low_kg += route_mass_kg
		var pressure_net_kg: float = pressure_low_to_high_kg \
				- pressure_high_to_low_kg
		var requested_half_skew_kg: float = 0.5 * pressure_net_kg
		var accepted_half_skew_kg: float = clampf(
			requested_half_skew_kg, -low_to_high_kg, high_to_low_kg
		)
		if absf(accepted_half_skew_kg - requested_half_skew_kg) > 1.0e-12:
			result["cap_count"] = float(result["cap_count"]) + 1.0
		var target_low_to_high_kg: float = low_to_high_kg \
				+ accepted_half_skew_kg
		var target_high_to_low_kg: float = high_to_low_kg \
				- accepted_half_skew_kg
		if (low_to_high_kg <= THERMO_MASS_EPS_KG \
				and target_low_to_high_kg > THERMO_MASS_EPS_KG) \
				or (high_to_low_kg <= THERMO_MASS_EPS_KG \
				and target_high_to_low_kg > THERMO_MASS_EPS_KG):
			result["invalid_flag"] = 1.0
			return result
		var low_scale: float = target_low_to_high_kg \
				/ maxf(THERMO_MASS_EPS_KG, low_to_high_kg)
		var high_scale: float = target_high_to_low_kg \
				/ maxf(THERMO_MASS_EPS_KG, high_to_low_kg)
		for raw_route in group["opening_routes"]:
			var route: Dictionary = raw_route
			var route_scale: float = low_scale \
					if int(route.get("source_room_id", EXTERIOR_ID)) == low_room_id \
					else high_scale
			var scaled_route: Dictionary = route.duplicate(true)
			for quantity_name in [
				"gas_mass_kg", "sensible_enthalpy_kj", "o2_kg"
			]:
				scaled_route[quantity_name] = maxf(
					0.0, float(route.get(quantity_name, 0.0)) * route_scale
				)
			var scaled_species: Dictionary = {}
			for species_name in PARCEL_SPECIES:
				scaled_species[species_name] = maxf(
					0.0,
					float(route.get("species_kg", {}).get(species_name, 0.0))
							* route_scale
				)
			scaled_route["species_kg"] = scaled_species
			scaled_route["cause"] = "canonical_interior_fixed_gross_preview"
			preview_routes.append(scaled_route)
		connections.append({
			"connection_id": connection_id,
			"low_room_id": low_room_id,
			"high_room_id": high_room_id,
			"opening_low_to_high_kg": low_to_high_kg,
			"opening_high_to_low_kg": high_to_low_kg,
			"pressure_net_low_to_high_kg": pressure_net_kg,
			"accepted_pressure_net_low_to_high_kg": \
					2.0 * accepted_half_skew_kg,
			"preview_low_to_high_kg": target_low_to_high_kg,
			"preview_high_to_low_kg": target_high_to_low_kg,
		})
		result["opening_gross_mass_kg"] = float(
			result["opening_gross_mass_kg"]
		) + low_to_high_kg + high_to_low_kg
		result["preview_gross_mass_kg"] = float(
			result["preview_gross_mass_kg"]
		) + target_low_to_high_kg + target_high_to_low_kg
		result["pressure_net_mass_kg"] = float(
			result["pressure_net_mass_kg"]
		) + pressure_net_kg
		result["accepted_pressure_net_mass_kg"] = float(
			result["accepted_pressure_net_mass_kg"]
		) + 2.0 * accepted_half_skew_kg

	for route in opening_routes:
		var direction: float = 1.0 \
				if int(route.get("source_room_id", EXTERIOR_ID)) \
						< int(route.get("destination_room_id", EXTERIOR_ID)) \
				else -1.0
		result["opening_net_enthalpy_kj"] = float(
			result["opening_net_enthalpy_kj"]
		) + direction * float(route.get("sensible_enthalpy_kj", 0.0))
	for route in preview_routes:
		var direction: float = 1.0 \
				if int(route.get("source_room_id", EXTERIOR_ID)) \
						< int(route.get("destination_room_id", EXTERIOR_ID)) \
				else -1.0
		result["preview_net_enthalpy_kj"] = float(
			result["preview_net_enthalpy_kj"]
		) + direction * float(route.get("sensible_enthalpy_kj", 0.0))
	var opening_gross_kg: float = float(result["opening_gross_mass_kg"])
	var preview_gross_kg: float = float(result["preview_gross_mass_kg"])
	result["mass_residual_kg"] = preview_gross_kg - opening_gross_kg
	# Every preview route is still an atomic source debit/destination credit.
	# These global residuals are therefore identically zero by construction.
	result["energy_residual_kj"] = 0.0
	result["o2_residual_kg"] = 0.0
	result["species_residual_kg"] = 0.0
	result["routes"] = preview_routes
	result["connections"] = connections
	result["valid"] = absf(float(result["mass_residual_kg"])) <= 1.0e-9
	return result


## One scalar keeps the explicit signed network from reversing any connected
## canonical pressure difference after the already-requested F3.3a gross
## exchange. The EOS pressure response is linear in gas mass and energy.
func compute_interior_network_pressure_relaxation(
		pressure_by_room: Dictionary,
		base_delta_by_room: Dictionary,
		signed_delta_by_room: Dictionary,
		connection_pairs: Array
	) -> Dictionary:
	var result: Dictionary = {
		"fraction": 1.0,
		"crossing_prevented_count": 0.0,
		"limiting_pressure_delta_pa": 0.0,
	}
	for raw_pair in connection_pairs:
		var pair: Dictionary = raw_pair
		var room_a_key: String = str(int(pair.get("room_a_id", EXTERIOR_ID)))
		var room_b_key: String = str(int(pair.get("room_b_id", EXTERIOR_ID)))
		if not pressure_by_room.has(room_a_key) or not pressure_by_room.has(room_b_key):
			continue
		var pressure_difference_pa: float = float(pressure_by_room[room_a_key]) \
				- float(pressure_by_room[room_b_key]) \
				+ float(base_delta_by_room.get(room_a_key, 0.0)) \
				- float(base_delta_by_room.get(room_b_key, 0.0))
		var signed_difference_delta_pa: float = float(
			signed_delta_by_room.get(room_a_key, 0.0)
		) - float(signed_delta_by_room.get(room_b_key, 0.0))
		if absf(pressure_difference_pa) <= 1.0e-9 \
				or pressure_difference_pa * signed_difference_delta_pa >= 0.0:
			continue
		var predicted_difference_pa: float = pressure_difference_pa \
				+ signed_difference_delta_pa
		if pressure_difference_pa * predicted_difference_pa >= 0.0:
			continue
		var pair_fraction: float = clampf(
			-pressure_difference_pa / signed_difference_delta_pa, 0.0, 1.0
		)
		if pair_fraction < float(result["fraction"]):
			result["fraction"] = pair_fraction
			result["limiting_pressure_delta_pa"] = pressure_difference_pa
		result["crossing_prevented_count"] = float(
			result["crossing_prevented_count"]
		) + 1.0
	return result


func _canonical_zone_densities(canonical: Dictionary) -> Dictionary:
	var upper_volume_m3: float = maxf(0.0, float(canonical.get("upper_volume_m3", 0.0)))
	var lower_volume_m3: float = maxf(0.0, float(canonical.get("lower_volume_m3", 0.0)))
	var upper_mass_kg: float = maxf(0.0, float(canonical.get("upper_gas_kg", 0.0)))
	var lower_mass_kg: float = maxf(0.0, float(canonical.get("lower_gas_kg", 0.0)))
	var upper_valid: bool = upper_volume_m3 > 1.0e-12 \
			and upper_mass_kg > THERMO_MASS_EPS_KG
	var lower_valid: bool = lower_volume_m3 > 1.0e-12 \
			and lower_mass_kg > THERMO_MASS_EPS_KG
	if not upper_valid and not lower_valid:
		return {"valid": false, "upper": 0.0, "lower": 0.0}
	# A cold receiving room legitimately starts as one ambient zone. The empty
	# geometric zone has no inventory to move, but hydrostatic integration still
	# needs a density at every height. Extend the occupied zone's density across
	# the degenerate zone without creating mass or energy.
	var upper_density_kg_m3: float = upper_mass_kg / upper_volume_m3 \
			if upper_valid else lower_mass_kg / lower_volume_m3
	var lower_density_kg_m3: float = lower_mass_kg / lower_volume_m3 \
			if lower_valid else upper_mass_kg / upper_volume_m3
	return {
		"valid": true,
		"upper": upper_density_kg_m3,
		"lower": lower_density_kg_m3,
	}


func _integrate_canonical_interior_opening(
		canonical_a: Dictionary,
		canonical_b: Dictionary,
		densities_a: Dictionary,
		densities_b: Dictionary,
		bottom_m: float,
		top_m: float,
		width_m: float,
		open_fraction: float,
		floor_pressure_offset_pa: float,
		discharge_coeff: float,
		source_preserving_destination_enabled: bool = false,
		buoyancy_destination_enabled: bool = false
	) -> Dictionary:
	var route_kg_s: Dictionary = {}
	var slabs: Array[Dictionary] = []
	var a_to_b_kg_s: float = 0.0
	var b_to_a_kg_s: float = 0.0
	var neutral_plane_m: float = 0.5 * (bottom_m + top_m)
	var min_abs_dp_pa: float = INF
	var boundaries: Array[float] = [bottom_m, top_m]
	for canonical in [canonical_a, canonical_b]:
		var interface_m: float = float(canonical.get("interface_m", 0.0))
		if interface_m > bottom_m + 1.0e-9 and interface_m < top_m - 1.0e-9:
			boundaries.append(interface_m)
	boundaries.sort()
	var unique_boundaries: Array[float] = []
	for boundary_m in boundaries:
		if unique_boundaries.is_empty() \
				or absf(boundary_m - unique_boundaries[-1]) > 1.0e-9:
			unique_boundaries.append(boundary_m)
	for boundary_index in range(unique_boundaries.size() - 1):
		var interval_bottom_m: float = unique_boundaries[boundary_index]
		var interval_top_m: float = unique_boundaries[boundary_index + 1]
		var dp_bottom_pa: float = _canonical_interior_delta_p_pa(
			canonical_a, canonical_b, densities_a, densities_b,
			floor_pressure_offset_pa, interval_bottom_m
		)
		var dp_top_pa: float = _canonical_interior_delta_p_pa(
			canonical_a, canonical_b, densities_a, densities_b,
			floor_pressure_offset_pa, interval_top_m
		)
		for endpoint in [
			{"z_m": interval_bottom_m, "dp_pa": dp_bottom_pa},
			{"z_m": interval_top_m, "dp_pa": dp_top_pa},
		]:
			if absf(float(endpoint["dp_pa"])) < min_abs_dp_pa:
				min_abs_dp_pa = absf(float(endpoint["dp_pa"]))
				neutral_plane_m = float(endpoint["z_m"])
		if dp_bottom_pa * dp_top_pa < 0.0:
			var zero_fraction: float = absf(dp_bottom_pa) \
					/ maxf(1.0e-12, absf(dp_bottom_pa) + absf(dp_top_pa))
			var zero_m: float = lerpf(interval_bottom_m, interval_top_m, zero_fraction)
			neutral_plane_m = zero_m
			min_abs_dp_pa = 0.0
			var lower_flow: Dictionary = _canonical_interior_interval_flow(
				canonical_a, canonical_b, densities_a, densities_b,
				interval_bottom_m, zero_m, dp_bottom_pa, 0.0,
				width_m, open_fraction, discharge_coeff,
				source_preserving_destination_enabled,
				buoyancy_destination_enabled
			)
			var upper_flow: Dictionary = _canonical_interior_interval_flow(
				canonical_a, canonical_b, densities_a, densities_b,
				zero_m, interval_top_m, 0.0, dp_top_pa,
				width_m, open_fraction, discharge_coeff,
				source_preserving_destination_enabled,
				buoyancy_destination_enabled
			)
			for interval_flow in [lower_flow, upper_flow]:
				var mass_flow_kg_s: float = float(interval_flow.get("mass_flow_kg_s", 0.0))
				var source_side: String = String(interval_flow.get("source_side", ""))
				if source_side == "a":
					a_to_b_kg_s += mass_flow_kg_s
				elif source_side == "b":
					b_to_a_kg_s += mass_flow_kg_s
				_accumulate_canonical_interior_route(route_kg_s, interval_flow)
				_append_canonical_interior_slab(slabs, interval_flow)
		else:
			var interval_flow: Dictionary = _canonical_interior_interval_flow(
				canonical_a, canonical_b, densities_a, densities_b,
				interval_bottom_m, interval_top_m, dp_bottom_pa, dp_top_pa,
				width_m, open_fraction, discharge_coeff,
				source_preserving_destination_enabled,
				buoyancy_destination_enabled
			)
			var mass_flow_kg_s: float = float(interval_flow.get("mass_flow_kg_s", 0.0))
			var source_side: String = String(interval_flow.get("source_side", ""))
			if source_side == "a":
				a_to_b_kg_s += mass_flow_kg_s
			elif source_side == "b":
				b_to_a_kg_s += mass_flow_kg_s
			_accumulate_canonical_interior_route(route_kg_s, interval_flow)
			_append_canonical_interior_slab(slabs, interval_flow)
	return {
		"route_kg_s": route_kg_s,
		"slabs": slabs,
		"a_to_b_kg_s": a_to_b_kg_s,
		"b_to_a_kg_s": b_to_a_kg_s,
		"net_a_to_b_kg_s": a_to_b_kg_s - b_to_a_kg_s,
		"neutral_plane_m": neutral_plane_m,
	}


func _canonical_interior_delta_p_pa(
		canonical_a: Dictionary,
		canonical_b: Dictionary,
		densities_a: Dictionary,
		densities_b: Dictionary,
		floor_pressure_offset_pa: float,
		height_m: float
	) -> float:
	return floor_pressure_offset_pa \
			- _canonical_hydrostatic_drop_pa(canonical_a, densities_a, height_m) \
			+ _canonical_hydrostatic_drop_pa(canonical_b, densities_b, height_m)


func _canonical_interior_interval_flow(
		canonical_a: Dictionary,
		canonical_b: Dictionary,
		densities_a: Dictionary,
		densities_b: Dictionary,
		bottom_m: float,
		top_m: float,
		dp_bottom_pa: float,
		dp_top_pa: float,
		width_m: float,
		open_fraction: float,
		discharge_coeff: float,
		source_preserving_destination_enabled: bool = false,
		buoyancy_destination_enabled: bool = false
	) -> Dictionary:
	var result: Dictionary = {
		"mass_flow_kg_s": 0.0,
		"source_side": "",
		"destination_side": "",
		"source_zone": "",
		"geometric_destination_zone": "",
		"destination_zone": "",
		"destination_fractions": {},
		"source_temp_c": 0.0,
		"bottom_m": bottom_m,
		"top_m": top_m,
	}
	var dz_m: float = maxf(0.0, top_m - bottom_m)
	if dz_m <= 1.0e-12:
		return result
	var midpoint_dp_pa: float = 0.5 * (dp_bottom_pa + dp_top_pa)
	if absf(midpoint_dp_pa) <= 1.0e-12:
		return result
	var source_side: String = "a" if midpoint_dp_pa > 0.0 else "b"
	var destination_side: String = "b" if source_side == "a" else "a"
	var source_canonical: Dictionary = canonical_a if source_side == "a" else canonical_b
	var destination_canonical: Dictionary = canonical_b if source_side == "a" else canonical_a
	var source_densities: Dictionary = densities_a if source_side == "a" else densities_b
	var midpoint_m: float = 0.5 * (bottom_m + top_m)
	var source_zone: String = _canonical_zone_at_height(source_canonical, midpoint_m)
	var geometric_destination_zone: String = _canonical_zone_at_height(
		destination_canonical, midpoint_m
	)
	var destination_zone: String = _canonical_interior_destination_zone(
		source_zone,
		destination_canonical,
		midpoint_m,
		source_preserving_destination_enabled
	)
	var source_temp_c: float = float(source_canonical.get(
		"temp_" + source_zone + "_c", 0.0
	))
	var destination_fractions: Dictionary = {}
	if buoyancy_destination_enabled:
		destination_fractions = preview_cfast_buoyancy_destination_split(
			source_temp_c,
			float(destination_canonical.get("temp_upper_c", 0.0)),
			float(destination_canonical.get("temp_lower_c", 0.0))
		)
	var source_density_kg_m3: float = maxf(
		0.0, float(source_densities.get(source_zone, 0.0))
	)
	var pressure_integral_pa_sqrt_m: float = _integral_sqrt_abs_linear(
		dp_bottom_pa, dp_top_pa, dz_m
	)
	result["mass_flow_kg_s"] = discharge_coeff * width_m * open_fraction \
			* sqrt(2.0 * source_density_kg_m3) * pressure_integral_pa_sqrt_m
	result["source_side"] = source_side
	result["destination_side"] = destination_side
	result["source_zone"] = source_zone
	result["geometric_destination_zone"] = geometric_destination_zone
	result["destination_zone"] = destination_zone
	result["destination_fractions"] = destination_fractions
	result["source_temp_c"] = source_temp_c
	result["route_key"] = "%s|%s|%s|%s" % [
		source_side, source_zone, destination_side, destination_zone
	]
	return result


func _integral_sqrt_abs_linear(value_a: float, value_b: float, length_m: float) -> float:
	if length_m <= 0.0:
		return 0.0
	var delta: float = value_b - value_a
	if absf(delta) <= 1.0e-12:
		return length_m * sqrt(absf(0.5 * (value_a + value_b)))
	var primitive_delta: float = _signed_pow_three_halves(value_b) \
			- _signed_pow_three_halves(value_a)
	return maxf(0.0, (2.0 * length_m / (3.0 * delta)) * primitive_delta)


func _signed_pow_three_halves(value: float) -> float:
	return signf(value) * pow(absf(value), 1.5)


func _accumulate_canonical_interior_route(
		route_kg_s: Dictionary,
		interval_flow: Dictionary
	) -> void:
	var mass_flow_kg_s: float = maxf(
		0.0, float(interval_flow.get("mass_flow_kg_s", 0.0))
	)
	if mass_flow_kg_s <= 0.0:
		return
	var destination_fractions: Dictionary = interval_flow.get(
		"destination_fractions", {}
	)
	if not destination_fractions.is_empty():
		for destination_zone in [ZONE_LOWER, ZONE_UPPER]:
			var fraction: float = clampf(
				float(destination_fractions.get(destination_zone, 0.0)), 0.0, 1.0
			)
			if fraction <= 0.0:
				continue
			var split_route_key: String = "%s|%s|%s|%s" % [
				String(interval_flow.get("source_side", "")),
				String(interval_flow.get("source_zone", "")),
				String(interval_flow.get("destination_side", "")),
				destination_zone,
			]
			route_kg_s[split_route_key] = float(
				route_kg_s.get(split_route_key, 0.0)
			) + mass_flow_kg_s * fraction
		return
	var route_key: String = String(interval_flow.get("route_key", ""))
	if route_key.is_empty():
		return
	route_kg_s[route_key] = float(route_kg_s.get(route_key, 0.0)) + mass_flow_kg_s


func _append_canonical_interior_slab(
		slabs: Array[Dictionary],
		interval_flow: Dictionary
	) -> void:
	if float(interval_flow.get("mass_flow_kg_s", 0.0)) <= THERMO_MASS_EPS_KG \
			or String(interval_flow.get("source_side", "")).is_empty():
		return
	slabs.append(interval_flow.duplicate(true))


func _canonical_hydrostatic_drop_pa(
		canonical: Dictionary,
		densities: Dictionary,
		height_m: float
	) -> float:
	var interface_m: float = maxf(0.0, float(canonical.get("interface_m", 0.0)))
	var lower_depth_m: float = minf(maxf(0.0, height_m), interface_m)
	var upper_depth_m: float = maxf(0.0, height_m - interface_m)
	return GRAVITY_M_S2 * (
		float(densities.get("lower", 0.0)) * lower_depth_m
		+ float(densities.get("upper", 0.0)) * upper_depth_m
	)


func _canonical_zone_at_height(canonical: Dictionary, height_m: float) -> String:
	return ZONE_UPPER if height_m >= float(canonical.get("interface_m", 0.0)) else ZONE_LOWER


## F3.3f1 candidate: direct horizontal vent flow retains the thermodynamic
## identity of its source layer. Door-jet entrainment is a separate physical
## owner and must not be approximated by reclassifying the direct destination.
func _canonical_interior_destination_zone(
		source_zone: String,
		destination_canonical: Dictionary,
		height_m: float,
		source_preserving_destination_enabled: bool = false
	) -> String:
	if source_preserving_destination_enabled:
		return source_zone
	return _canonical_zone_at_height(destination_canonical, height_m)


## F3.3h1: exact CFAST flogo receiver split. The source slab temperature is
## compared with the receiver layer temperatures; source removal remains a
## separate geometric decision.
func preview_cfast_buoyancy_destination_split(
		source_temp_c: float,
		destination_upper_temp_c: float,
		destination_lower_temp_c: float
	) -> Dictionary:
	var effective_lower_temp_c: float = minf(
		destination_lower_temp_c, destination_upper_temp_c
	)
	var upper_fraction: float = _cfast_tanhsmooth(
		source_temp_c,
		destination_upper_temp_c + CFAST_DESTINATION_DELTA_TEMP_K,
		effective_lower_temp_c - CFAST_DESTINATION_DELTA_TEMP_K,
		1.0,
		0.0
	)
	return {
		ZONE_LOWER: 1.0 - upper_fraction,
		ZONE_UPPER: upper_fraction,
	}


func _cfast_tanhsmooth(
		x: float,
		xmax: float,
		xmin: float,
		ymax: float,
		ymin: float
	) -> float:
	if xmax <= xmin:
		return ymax if x >= xmax else ymin
	var fraction: float = clampf(
		0.5 + 0.5025 * tanh(6.0 / (xmax - xmin) * (x - xmin) - 3.0),
		0.0,
		1.0
	)
	return fraction * (ymax - ymin) + ymin


## F3.3g: pure receiver-side mixing preview matching current CFAST
## flowhorizontal.f90 spill_plume/poreh_plume ownership. Direct vent flow is
## intentionally absent: this is only the additional internal receiver route.
func preview_canonical_doorway_jet_entrainment(
		source_canonical: Dictionary,
		destination_canonical: Dictionary,
		source_zone: String,
		slab_bottom_m: float,
		slab_top_m: float,
		vent_bottom_m: float,
		vent_top_m: float,
		opening_width_m: float,
		source_flow_kg_s: float,
		dt: float
	) -> Dictionary:
	var result: Dictionary = {
		"valid": false,
		"invalid_flag": 0.0,
		"active": false,
		"mixing_kind": "",
		"source_zone": source_zone,
		"geometric_destination_zone": "",
		"entrained_source_zone": "",
		"entrained_destination_zone": "",
		"mixing_factor": 0.0,
		"mixing_depth_m": 0.0,
		"heat_flow_w": 0.0,
		"entrainment_rate_kg_s": 0.0,
		"gas_mass_kg": 0.0,
	}
	if not bool(source_canonical.get("valid", false)) \
			or not bool(destination_canonical.get("valid", false)) \
			or source_zone not in [ZONE_UPPER, ZONE_LOWER]:
		result["invalid_flag"] = 1.0
		return result
	for value in [
		slab_bottom_m, slab_top_m, vent_bottom_m, vent_top_m,
		opening_width_m, source_flow_kg_s, dt,
	]:
		if not is_finite(float(value)):
			result["invalid_flag"] = 1.0
			return result
	if slab_top_m <= slab_bottom_m or vent_top_m <= vent_bottom_m \
			or slab_bottom_m < vent_bottom_m - 1.0e-9 \
			or slab_top_m > vent_top_m + 1.0e-9 \
			or opening_width_m < 0.0 or source_flow_kg_s < 0.0 or dt < 0.0:
		result["invalid_flag"] = 1.0
		return result

	result["valid"] = true
	if opening_width_m <= 0.0 or source_flow_kg_s <= 0.0 or dt <= 0.0:
		return result
	var slab_midpoint_m: float = 0.5 * (slab_bottom_m + slab_top_m)
	var destination_zone: String = _canonical_zone_at_height(
		destination_canonical, slab_midpoint_m
	)
	result["geometric_destination_zone"] = destination_zone
	if destination_zone == source_zone:
		return result

	var source_interface_m: float = maxf(
		0.0, float(source_canonical.get("interface_m", 0.0))
	)
	var destination_interface_m: float = maxf(
		0.0, float(destination_canonical.get("interface_m", 0.0))
	)
	var upper_temp_k: float = 0.0
	var lower_temp_k: float = 0.0
	var mixing_depth_m: float = 0.0
	var mixing_factor: float = 0.0
	if source_zone == ZONE_UPPER and destination_zone == ZONE_LOWER:
		upper_temp_k = float(source_canonical.get("temp_upper_c", 0.0)) + 273.15
		lower_temp_k = float(destination_canonical.get("temp_lower_c", 0.0)) + 273.15
		mixing_depth_m = maxf(
			0.0,
			destination_interface_m - maxf(vent_bottom_m, source_interface_m)
		)
		mixing_factor = 1.0
		result["mixing_kind"] = "hot_jet_lower_to_upper"
		result["entrained_source_zone"] = ZONE_LOWER
		result["entrained_destination_zone"] = ZONE_UPPER
	elif source_zone == ZONE_LOWER and destination_zone == ZONE_UPPER:
		upper_temp_k = float(destination_canonical.get("temp_upper_c", 0.0)) + 273.15
		lower_temp_k = float(source_canonical.get("temp_lower_c", 0.0)) + 273.15
		mixing_depth_m = maxf(
			0.0,
			minf(vent_top_m, source_interface_m)
					- maxf(destination_interface_m, vent_bottom_m)
		)
		mixing_factor = POREH_COOL_JET_MIXING_FACTOR
		result["mixing_kind"] = "cool_jet_upper_to_lower"
		result["entrained_source_zone"] = ZONE_UPPER
		result["entrained_destination_zone"] = ZONE_LOWER
	else:
		return result

	result["mixing_factor"] = mixing_factor
	result["mixing_depth_m"] = mixing_depth_m
	if upper_temp_k <= lower_temp_k or lower_temp_k <= 0.0 \
			or mixing_depth_m <= 0.0:
		return result
	var air_cp_j_kg_k: float = AIR_CP_KJ_KG_K * 1000.0
	var heat_flow_w: float = air_cp_j_kg_k * (upper_temp_k - lower_temp_k) \
			* source_flow_kg_s
	var lower_density_kg_m3: float = POREH_AIR_DENSITY_TEMPERATURE_KG_K_M3 \
			/ lower_temp_k
	var entrainment_rate_kg_s: float = mixing_factor \
			* POREH_ENTRAINMENT_COEFFICIENT \
			* pow(lower_temp_k / upper_temp_k, 2.0 / 3.0) \
			* pow(
				GRAVITY_M_S2 * lower_density_kg_m3 * lower_density_kg_m3
						/ (air_cp_j_kg_k * lower_temp_k),
				1.0 / 3.0
			) \
			* pow(heat_flow_w, 1.0 / 3.0) \
			* pow(opening_width_m, 2.0 / 3.0) \
			* mixing_depth_m
	if not is_finite(entrainment_rate_kg_s) or entrainment_rate_kg_s <= 0.0:
		return result
	result["active"] = true
	result["heat_flow_w"] = heat_flow_w
	result["entrainment_rate_kg_s"] = entrainment_rate_kg_s
	result["gas_mass_kg"] = entrainment_rate_kg_s * dt
	return result


## Build the receiver-internal atomic route from the pre-step destination
## inventory. All payloads therefore share the same application-time cap.
func make_canonical_doorway_jet_entrainment_route(
		route_id: String,
		destination_room_id: int,
		preview: Dictionary
	) -> Dictionary:
	if not bool(preview.get("valid", false)) or not bool(preview.get("active", false)):
		return {}
	var room_key: String = str(destination_room_id)
	if destination_room_id == EXTERIOR_ID or not _snapshots.has(room_key):
		return {}
	var source_zone: String = String(preview.get("entrained_source_zone", ""))
	var destination_zone: String = String(
		preview.get("entrained_destination_zone", "")
	)
	if source_zone not in [ZONE_UPPER, ZONE_LOWER] \
			or destination_zone not in [ZONE_UPPER, ZONE_LOWER] \
			or source_zone == destination_zone:
		return {}
	var requested_mass_kg: float = maxf(0.0, float(preview.get("gas_mass_kg", 0.0)))
	if requested_mass_kg <= THERMO_MASS_EPS_KG:
		return {}
	var source_state: Dictionary = _snapshots[room_key]
	var source_mass_kg: float = maxf(
		THERMO_MASS_EPS_KG,
		float(source_state.get(source_zone + "_gas_kg", 0.0))
	)
	var inventory_fraction: float = requested_mass_kg / source_mass_kg
	var species_kg: Dictionary = _parcel_species({})
	var source_species: Dictionary = source_state.get(source_zone + "_species_kg", {})
	for species_name in PARCEL_SPECIES:
		species_kg[species_name] = maxf(
			0.0, float(source_species.get(species_name, 0.0)) * inventory_fraction
		)
	return make_atomic_route(
		route_id,
		"canonical_doorway_jet_entrainment",
		destination_room_id,
		destination_room_id,
		source_zone,
		destination_zone,
		requested_mass_kg,
		maxf(0.0, float(source_state.get(source_zone + "_energy_kj", 0.0)))
				* inventory_fraction,
		maxf(0.0, float(source_state.get(source_zone + "_o2_kg", 0.0)))
				* inventory_fraction,
		species_kg
	)


func build_canonical_doorway_jet_entrainment_routes(
		route_prefix: String,
		room_a_id: int,
		room_b_id: int,
		canonical_a: Dictionary,
		canonical_b: Dictionary,
		opening_geometry: Dictionary,
		slabs: Array,
		dt: float
	) -> Array[Dictionary]:
	var routes: Array[Dictionary] = []
	var vent_bottom_m: float = float(opening_geometry.get("bottom_m", 0.0))
	var vent_top_m: float = float(opening_geometry.get("top_m", vent_bottom_m))
	var opening_width_m: float = maxf(0.0, float(opening_geometry.get("width_m", 0.0)))
	for slab_position in range(slabs.size()):
		var slab: Dictionary = slabs[slab_position]
		var source_is_a: bool = String(slab.get("source_side", "")) == "a"
		var source_canonical: Dictionary = canonical_a if source_is_a else canonical_b
		var destination_canonical: Dictionary = canonical_b if source_is_a else canonical_a
		var destination_room_id: int = room_b_id if source_is_a else room_a_id
		var preview: Dictionary = preview_canonical_doorway_jet_entrainment(
			source_canonical,
			destination_canonical,
			String(slab.get("source_zone", "")),
			float(slab.get("bottom_m", vent_bottom_m)),
			float(slab.get("top_m", vent_bottom_m)),
			vent_bottom_m,
			vent_top_m,
			opening_width_m,
			maxf(0.0, float(slab.get("mass_flow_kg_s", 0.0))),
			dt
		)
		var route: Dictionary = make_canonical_doorway_jet_entrainment_route(
			"%s:%03d" % [route_prefix, slab_position],
			destination_room_id,
			preview
		)
		if not route.is_empty():
			routes.append(route)
	return routes


func _scaled_canonical_interior_slabs(slabs: Array, fraction: float) -> Array[Dictionary]:
	var scaled: Array[Dictionary] = []
	var bounded_fraction: float = clampf(fraction, 0.0, 1.0)
	for raw_slab in slabs:
		var slab: Dictionary = raw_slab.duplicate(true)
		slab["mass_flow_kg_s"] = maxf(
			0.0, float(slab.get("mass_flow_kg_s", 0.0)) * bounded_fraction
		)
		slab["gas_mass_kg"] = maxf(
			0.0, float(slab.get("gas_mass_kg", 0.0)) * bounded_fraction
		)
		scaled.append(slab)
	return scaled


## Build one opening-order-independent network bundle from the common pre-step
## canonical snapshots. Vertical openings deliberately remain owned by the
## existing stairwell contract.
func queue_canonical_interior_opening_requests(
		building,
		dt: float,
		reference_temp_c: float,
		discharge_coeff: float = EXTERIOR_DISCHARGE_COEFF,
		signed_pressure_enabled: bool = false,
		source_preserving_destination_enabled: bool = false,
		doorway_jet_entrainment_enabled: bool = false,
		buoyancy_destination_enabled: bool = false
	) -> void:
	if building == null or dt <= 0.0 or discharge_coeff <= 0.0:
		return
	var descriptors: Array[Dictionary] = []
	var openings: Array = building.get_openings()
	for opening_position in range(openings.size()):
		var op = openings[opening_position]
		if op == null or op.is_exterior_opening():
			continue
		var room_a = building.get_room(op.a)
		var room_b = building.get_room(op.b)
		if room_a == null or room_b == null:
			continue
		if op.is_vertical or absf(room_a.floor_level_z_m - room_b.floor_level_z_m) > 0.01:
			_record_canonical_interior_skip(room_a.id, room_b.id, "vertical")
			continue
		var open_fraction: float = clampf(op.open_fraction, 0.0, 1.0)
		if open_fraction <= 0.0:
			continue
		var opening_id: int = op.opening_index if op.opening_index >= 0 else opening_position
		descriptors.append({
			"sort_key": "%010d|%010d|%010d" % [opening_id, mini(op.a, op.b), maxi(op.a, op.b)],
			"opening_id": opening_id,
			"opening": op,
			"room_a": room_a,
			"room_b": room_b,
			"open_fraction": open_fraction,
		})
	descriptors.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return String(left.get("sort_key", "")) < String(right.get("sort_key", ""))
	)
	var network_routes: Array[Dictionary] = []
	var pressure_routes_raw: Array[Dictionary] = []
	var doorway_jet_routes: Array[Dictionary] = []
	var pressure_jet_inputs: Array[Dictionary] = []
	var room_totals: Dictionary = {}
	var pressure_by_room: Dictionary = {}
	var pressure_connection_pairs: Array[Dictionary] = []
	var global_out_mass_kg: float = 0.0
	var global_in_mass_kg: float = 0.0
	var global_out_energy_kj: float = 0.0
	var global_in_energy_kj: float = 0.0
	var global_out_o2_kg: float = 0.0
	var global_in_o2_kg: float = 0.0
	var global_out_species_kg: float = 0.0
	var global_in_species_kg: float = 0.0
	var direct_source_preserving: bool = (
		source_preserving_destination_enabled or doorway_jet_entrainment_enabled
	) and not buoyancy_destination_enabled
	for descriptor in descriptors:
		var op = descriptor["opening"]
		var room_a = descriptor["room_a"]
		var room_b = descriptor["room_b"]
		var opening_id: int = int(descriptor["opening_id"])
		var input_a: Dictionary = get_canonical_thermodynamic_input(room_a, reference_temp_c)
		var input_b: Dictionary = get_canonical_thermodynamic_input(room_b, reference_temp_c)
		var opening_geometry: Dictionary = {
			"bottom_m": maxf(0.0, op.sill_m),
			"top_m": minf(minf(room_a.height_m, room_b.height_m), op.lintel_height_m()),
			"width_m": maxf(0.0, op.width_m),
			"open_fraction": float(descriptor["open_fraction"]),
		}
		var preview: Dictionary = preview_canonical_interior_opening(
			input_a, input_b, opening_geometry,
			discharge_coeff, dt,
			EXTERIOR_COUNTERFLOW_SEGMENTS,
			direct_source_preserving,
			buoyancy_destination_enabled
		)
		if doorway_jet_entrainment_enabled:
			doorway_jet_routes.append_array(
				build_canonical_doorway_jet_entrainment_routes(
					"f33g_opening:%d" % opening_id,
					room_a.id,
					room_b.id,
					input_a,
					input_b,
					opening_geometry,
					preview.get("slabs", []),
					dt
				)
			)
		_record_canonical_interior_preview(room_a.id, room_b.id, preview)
		if signed_pressure_enabled:
			pressure_by_room[str(room_a.id)] = float(input_a.get("pressure_gauge_pa", 0.0))
			pressure_by_room[str(room_b.id)] = float(input_b.get("pressure_gauge_pa", 0.0))
			pressure_connection_pairs.append({
				"room_a_id": room_a.id,
				"room_b_id": room_b.id,
			})
			_record_canonical_interior_pressure_input(room_a.id, input_a)
			_record_canonical_interior_pressure_input(room_b.id, input_b)
			var pressure_preview: Dictionary = preview_canonical_interior_pressure_flow(
				input_a, input_b, opening_geometry, discharge_coeff, dt,
				direct_source_preserving,
				buoyancy_destination_enabled
			)
			if doorway_jet_entrainment_enabled:
				pressure_jet_inputs.append({
					"route_prefix": "f33g_pressure:%d" % opening_id,
					"room_a_id": room_a.id,
					"room_b_id": room_b.id,
					"canonical_a": input_a,
					"canonical_b": input_b,
					"opening_geometry": opening_geometry,
					"slabs": pressure_preview.get("slabs", []),
				})
			if bool(pressure_preview.get("valid", false)):
				var pressure_route_position: int = 0
				for route_preview in pressure_preview.get("routes", []):
					var pressure_source_is_a: bool = String(
						route_preview.get("source_side", "")
					) == "a"
					var pressure_source_room_id: int = room_a.id \
							if pressure_source_is_a else room_b.id
					var pressure_destination_room_id: int = room_b.id \
							if pressure_source_is_a else room_a.id
					var pressure_source_zone: String = String(
						route_preview.get("source_zone", ZONE_UPPER)
					)
					var pressure_destination_zone: String = String(
						route_preview.get("destination_zone", ZONE_UPPER)
					)
					var pressure_gas_kg: float = maxf(
						0.0, float(route_preview.get("gas_mass_kg", 0.0))
					)
					var pressure_source_state: Dictionary = _snapshots.get(
						str(pressure_source_room_id), {}
					)
					var pressure_source_mass_kg: float = maxf(
						THERMO_MASS_EPS_KG,
						float(pressure_source_state.get(
							pressure_source_zone + "_gas_kg", 0.0
						))
					)
					var pressure_inventory_fraction: float = pressure_gas_kg \
							/ pressure_source_mass_kg
					var pressure_energy_kj: float = float(pressure_source_state.get(
						pressure_source_zone + "_energy_kj", 0.0
					)) * pressure_inventory_fraction
					var pressure_o2_kg: float = float(pressure_source_state.get(
						pressure_source_zone + "_o2_kg", 0.0
					)) * pressure_inventory_fraction
					var pressure_species_kg: Dictionary = _parcel_species({})
					var pressure_source_species: Dictionary = pressure_source_state.get(
						pressure_source_zone + "_species_kg", {}
					)
					for species_name in PARCEL_SPECIES:
						pressure_species_kg[species_name] = float(
							pressure_source_species.get(species_name, 0.0)
						) * pressure_inventory_fraction
					var pressure_route: Dictionary = make_atomic_route(
						"f33b_pressure:%d:%03d" % [opening_id, pressure_route_position],
						"canonical_interior_pressure",
						pressure_source_room_id,
						pressure_destination_room_id,
						pressure_source_zone,
						pressure_destination_zone,
						pressure_gas_kg,
						pressure_energy_kj,
						pressure_o2_kg,
						pressure_species_kg
					)
					_tag_connection_route(
						pressure_route, opening_id, reference_temp_c
					)
					pressure_routes_raw.append(pressure_route)
					pressure_route_position += 1
		if not bool(preview.get("valid", false)):
			continue
		var route_position: int = 0
		for route_preview in preview.get("routes", []):
			var source_is_a: bool = String(route_preview.get("source_side", "")) == "a"
			var source_room_id: int = room_a.id if source_is_a else room_b.id
			var destination_room_id: int = room_b.id if source_is_a else room_a.id
			var source_zone: String = String(route_preview.get("source_zone", ZONE_UPPER))
			var destination_zone: String = String(
				route_preview.get("destination_zone", ZONE_UPPER)
			)
			var gas_mass_kg: float = maxf(0.0, float(route_preview.get("gas_mass_kg", 0.0)))
			var source_state: Dictionary = _snapshots.get(str(source_room_id), {})
			var source_mass_kg: float = maxf(
				THERMO_MASS_EPS_KG, float(source_state.get(source_zone + "_gas_kg", 0.0))
			)
			var inventory_fraction: float = gas_mass_kg / source_mass_kg
			var energy_kj: float = float(
				source_state.get(source_zone + "_energy_kj", 0.0)
			) * inventory_fraction
			var o2_kg: float = float(
				source_state.get(source_zone + "_o2_kg", 0.0)
			) * inventory_fraction
			var species_kg: Dictionary = _parcel_species({})
			var source_species: Dictionary = source_state.get(source_zone + "_species_kg", {})
			for species_name in PARCEL_SPECIES:
				species_kg[species_name] = float(
					source_species.get(species_name, 0.0)
				) * inventory_fraction
			var route_id: String = "f33a_interior:%d:%03d" % [opening_id, route_position]
			route_position += 1
			var opening_route: Dictionary = make_atomic_route(
				route_id,
				"canonical_interior_opening",
				source_room_id,
				destination_room_id,
				source_zone,
				destination_zone,
				gas_mass_kg,
				energy_kj,
				o2_kg,
				species_kg
			)
			_tag_connection_route(opening_route, opening_id, reference_temp_c)
			network_routes.append(opening_route)
			_accumulate_canonical_interior_room_total(
				room_totals, source_room_id, "out", gas_mass_kg, energy_kj, o2_kg,
				_sum_parcel_species(species_kg)
			)
			_accumulate_canonical_interior_room_total(
				room_totals, destination_room_id, "in", gas_mass_kg, energy_kj, o2_kg,
				_sum_parcel_species(species_kg)
			)
			global_out_mass_kg += gas_mass_kg
			global_in_mass_kg += gas_mass_kg
			global_out_energy_kj += energy_kj
			global_in_energy_kj += energy_kj
			global_out_o2_kg += o2_kg
			global_in_o2_kg += o2_kg
			global_out_species_kg += _sum_parcel_species(species_kg)
			global_in_species_kg += _sum_parcel_species(species_kg)
	var pressure_room_totals_raw: Dictionary = {}
	var pressure_room_totals: Dictionary = {}
	var pressure_base_delta_by_room: Dictionary = {}
	var pressure_full_delta_by_room: Dictionary = {}
	var pressure_limited_delta_by_room: Dictionary = {}
	var pressure_relaxation: Dictionary = {
		"fraction": 1.0,
		"crossing_prevented_count": 0.0,
		"limiting_pressure_delta_pa": 0.0,
	}
	if signed_pressure_enabled:
		pressure_base_delta_by_room = _canonical_route_pressure_delta_by_room(
			network_routes, building, reference_temp_c
		)
		pressure_full_delta_by_room = _canonical_route_pressure_delta_by_room(
			pressure_routes_raw, building, reference_temp_c
		)
		pressure_relaxation = compute_interior_network_pressure_relaxation(
			pressure_by_room,
			pressure_base_delta_by_room,
			pressure_full_delta_by_room,
			pressure_connection_pairs
		)
		var pressure_fraction: float = clampf(
			float(pressure_relaxation.get("fraction", 1.0)), 0.0, 1.0
		)
		var pressure_routes: Array = _scaled_atomic_routes(
			pressure_routes_raw, pressure_fraction
		)
		pressure_limited_delta_by_room = _canonical_route_pressure_delta_by_room(
			pressure_routes, building, reference_temp_c
		)
		for raw_pressure_route in pressure_routes_raw:
			_accumulate_canonical_atomic_route_totals(
				pressure_room_totals_raw, raw_pressure_route
			)
		for raw_pressure_route in pressure_routes:
			var pressure_route: Dictionary = raw_pressure_route
			network_routes.append(pressure_route)
			_accumulate_canonical_atomic_route_totals(room_totals, pressure_route)
			_accumulate_canonical_atomic_route_totals(
				pressure_room_totals, pressure_route
			)
			var pressure_gas_kg: float = float(pressure_route.get("gas_mass_kg", 0.0))
			var pressure_energy_kj: float = float(
				pressure_route.get("sensible_enthalpy_kj", 0.0)
			)
			var pressure_o2_kg: float = float(pressure_route.get("o2_kg", 0.0))
			var pressure_species_sum_kg: float = _sum_parcel_species(
				pressure_route.get("species_kg", {})
			)
			global_out_mass_kg += pressure_gas_kg
			global_in_mass_kg += pressure_gas_kg
			global_out_energy_kj += pressure_energy_kj
			global_in_energy_kj += pressure_energy_kj
			global_out_o2_kg += pressure_o2_kg
			global_in_o2_kg += pressure_o2_kg
			global_out_species_kg += pressure_species_sum_kg
			global_in_species_kg += pressure_species_sum_kg
		if doorway_jet_entrainment_enabled and pressure_fraction > 0.0:
			for pressure_jet_input in pressure_jet_inputs:
				doorway_jet_routes.append_array(
					build_canonical_doorway_jet_entrainment_routes(
						String(pressure_jet_input.get("route_prefix", "")),
						int(pressure_jet_input.get("room_a_id", EXTERIOR_ID)),
						int(pressure_jet_input.get("room_b_id", EXTERIOR_ID)),
						pressure_jet_input.get("canonical_a", {}),
						pressure_jet_input.get("canonical_b", {}),
						pressure_jet_input.get("opening_geometry", {}),
						_scaled_canonical_interior_slabs(
							pressure_jet_input.get("slabs", []), pressure_fraction
						),
						dt
					)
				)
		_record_canonical_interior_pressure_network(
			pressure_by_room,
			pressure_room_totals_raw,
			pressure_room_totals,
			pressure_base_delta_by_room,
			pressure_full_delta_by_room,
			pressure_limited_delta_by_room,
			pressure_relaxation
		)
	if network_routes.is_empty() and doorway_jet_routes.is_empty():
		return
	for room_key in room_totals.keys():
		var record: Dictionary = _canonical_interior_opening_by_room.get(
			room_key, _new_canonical_interior_opening_record()
		).duplicate(true)
		var totals: Dictionary = room_totals[room_key]
		for direction in ["out", "in"]:
			for quantity in ["gas_kg", "energy_kj", "o2_kg", "species_kg"]:
				record["requested_%s_%s" % [direction, quantity]] = float(
					totals.get("%s_%s" % [direction, quantity], 0.0)
				)
		record["route_count"] = float(totals.get("route_count", 0.0))
		_canonical_interior_opening_by_room[room_key] = record
	if not network_routes.is_empty():
		var bundle: Dictionary = make_atomic_bundle(
			"f33a_interior_network",
			"canonical_interior_opening_network",
			network_routes,
			{
				"kind": "canonical_interior_opening_network",
				"transport_family": "canonical_interior_opening",
				"room_totals": room_totals,
				"pressure_room_totals": pressure_room_totals,
				"pressure_pre_by_room": pressure_by_room,
				"pressure_base_delta_by_room": pressure_base_delta_by_room,
				"pressure_limited_delta_by_room": pressure_limited_delta_by_room,
				"mass_residual_kg": global_out_mass_kg - global_in_mass_kg,
				"energy_residual_kj": global_out_energy_kj - global_in_energy_kj,
				"o2_residual_kg": global_out_o2_kg - global_in_o2_kg,
				"species_residual_kg": global_out_species_kg - global_in_species_kg,
			}
		)
		if not add_atomic_bundle(bundle):
			for room_key in room_totals.keys():
				var duplicate_record: Dictionary = _canonical_interior_opening_by_room.get(
					room_key, _new_canonical_interior_opening_record()
				).duplicate(true)
				duplicate_record["duplicate_owner_flag"] = 1.0
				_canonical_interior_opening_by_room[room_key] = duplicate_record
	if not doorway_jet_routes.is_empty():
		var mixing_bundle: Dictionary = make_atomic_bundle(
			"f33g_doorway_jet_network",
			"canonical_doorway_jet_entrainment_network",
			doorway_jet_routes,
			{
				"kind": "canonical_doorway_jet_entrainment_network",
				"transport_family": "canonical_interior_opening",
			}
		)
		add_atomic_bundle(mixing_bundle)


func _record_canonical_interior_skip(room_a_id: int, room_b_id: int, reason: String) -> void:
	for room_id in [room_a_id, room_b_id]:
		var room_key: String = str(room_id)
		var record: Dictionary = _canonical_interior_opening_by_room.get(
			room_key, _new_canonical_interior_opening_record()
		).duplicate(true)
		if reason == "vertical":
			record["vertical_skipped_count"] = float(
				record.get("vertical_skipped_count", 0.0)
			) + 1.0
		_canonical_interior_opening_by_room[room_key] = record


func _record_canonical_interior_preview(
		room_a_id: int,
		room_b_id: int,
		preview: Dictionary
	) -> void:
	var exchange_kg: float = maxf(0.0, float(preview.get("exchange_kg", 0.0)))
	for room_id in [room_a_id, room_b_id]:
		var room_key: String = str(room_id)
		var record: Dictionary = _canonical_interior_opening_by_room.get(
			room_key, _new_canonical_interior_opening_record()
		).duplicate(true)
		record["opening_count"] = float(record.get("opening_count", 0.0)) + 1.0
		if not bool(preview.get("valid", false)):
			record["invalid_preview_count"] = float(
				record.get("invalid_preview_count", 0.0)
			) + float(preview.get("invalid_flag", 1.0))
		else:
			record["active_opening_count"] = float(
				record.get("active_opening_count", 0.0)
			) + (1.0 if exchange_kg > THERMO_MASS_EPS_KG else 0.0)
			record["neutral_plane_weighted_m_kg"] = float(
				record.get("neutral_plane_weighted_m_kg", 0.0)
			) + float(preview.get("neutral_plane_m", 0.0)) * maxf(exchange_kg, 1.0e-12)
			record["neutral_plane_weight_kg"] = float(
				record.get("neutral_plane_weight_kg", 0.0)
			) + maxf(exchange_kg, 1.0e-12)
			record["neutral_plane_m"] = float(record["neutral_plane_weighted_m_kg"]) \
					/ maxf(1.0e-12, float(record["neutral_plane_weight_kg"]))
		_canonical_interior_opening_by_room[room_key] = record


func _accumulate_canonical_interior_room_total(
		room_totals: Dictionary,
		room_id: int,
		direction: String,
		gas_kg: float,
		energy_kj: float,
		o2_kg: float,
		species_kg: float
	) -> void:
	var room_key: String = str(room_id)
	var totals: Dictionary = room_totals.get(room_key, {})
	for entry in [
		{"name": "gas_kg", "value": gas_kg},
		{"name": "energy_kj", "value": energy_kj},
		{"name": "o2_kg", "value": o2_kg},
		{"name": "species_kg", "value": species_kg},
	]:
		var key: String = "%s_%s" % [direction, String(entry["name"])]
		totals[key] = float(totals.get(key, 0.0)) + float(entry["value"])
	totals["route_count"] = float(totals.get("route_count", 0.0)) + 1.0
	room_totals[room_key] = totals


func _accumulate_canonical_atomic_route_totals(
		room_totals: Dictionary,
		route: Dictionary
	) -> void:
	var gas_kg: float = maxf(0.0, float(route.get("gas_mass_kg", 0.0)))
	var energy_kj: float = maxf(0.0, float(route.get("sensible_enthalpy_kj", 0.0)))
	var o2_kg: float = maxf(0.0, float(route.get("o2_kg", 0.0)))
	var species_kg: float = _sum_parcel_species(route.get("species_kg", {}))
	_accumulate_canonical_interior_room_total(
		room_totals,
		int(route.get("source_room_id", EXTERIOR_ID)),
		"out",
		gas_kg,
		energy_kj,
		o2_kg,
		species_kg
	)
	_accumulate_canonical_interior_room_total(
		room_totals,
		int(route.get("destination_room_id", EXTERIOR_ID)),
		"in",
		gas_kg,
		energy_kj,
		o2_kg,
		species_kg
	)


func _canonical_route_pressure_delta_by_room(
		routes: Array,
		building,
		reference_temp_c: float
	) -> Dictionary:
	var delta_by_room: Dictionary = {}
	if building == null:
		return delta_by_room
	var reference_temp_k: float = maxf(1.0, reference_temp_c + 273.15)
	var gas_constant_model: float = AIR_PRESSURE_REF_PA \
			/ (AIR_DENSITY_REF_KG_M3 * reference_temp_k)
	for raw_route in routes:
		var route: Dictionary = raw_route
		var gas_kg: float = maxf(0.0, float(route.get("gas_mass_kg", 0.0)))
		var energy_kj: float = maxf(
			0.0, float(route.get("sensible_enthalpy_kj", 0.0))
		)
		var pressure_inventory_term: float = gas_kg * reference_temp_k \
				+ energy_kj / AIR_CP_KJ_KG_K
		for endpoint in [
			{"room_id": int(route.get("source_room_id", EXTERIOR_ID)), "sign": -1.0},
			{"room_id": int(route.get("destination_room_id", EXTERIOR_ID)), "sign": 1.0},
		]:
			var room_id: int = int(endpoint["room_id"])
			if room_id == EXTERIOR_ID:
				continue
			var room = building.get_room(room_id)
			if room == null or room.volume_m3() <= 1.0e-12:
				continue
			var room_key: String = str(room_id)
			delta_by_room[room_key] = float(delta_by_room.get(room_key, 0.0)) \
					+ float(endpoint["sign"]) * gas_constant_model \
					/ room.volume_m3() * pressure_inventory_term
	return delta_by_room


func _record_canonical_interior_pressure_input(
		room_id: int,
		canonical_input: Dictionary
	) -> void:
	var room_key: String = str(room_id)
	var record: Dictionary = _canonical_interior_opening_by_room.get(
		room_key, _new_canonical_interior_opening_record()
	).duplicate(true)
	record["pressure_enabled_flag"] = 1.0
	record["pressure_opening_count"] = float(
		record.get("pressure_opening_count", 0.0)
	) + 1.0
	record["pressure_pre_pa"] = float(canonical_input.get("pressure_gauge_pa", 0.0))
	_canonical_interior_opening_by_room[room_key] = record


func _record_canonical_interior_pressure_network(
		pressure_by_room: Dictionary,
		raw_totals_by_room: Dictionary,
		limited_totals_by_room: Dictionary,
		base_delta_by_room: Dictionary,
		full_delta_by_room: Dictionary,
		limited_delta_by_room: Dictionary,
		relaxation: Dictionary
	) -> void:
	var room_keys: Dictionary = {}
	for source in [pressure_by_room, raw_totals_by_room, limited_totals_by_room]:
		for raw_room_key in source.keys():
			room_keys[String(raw_room_key)] = true
	var equilibrium_fraction: float = clampf(
		float(relaxation.get("fraction", 1.0)), 0.0, 1.0
	)
	var pressure_residuals: Dictionary = {}
	for quantity in ["gas_kg", "energy_kj", "o2_kg", "species_kg"]:
		var total_out: float = 0.0
		var total_in: float = 0.0
		for raw_totals in limited_totals_by_room.values():
			var totals: Dictionary = raw_totals
			total_out += float(totals.get("out_" + quantity, 0.0))
			total_in += float(totals.get("in_" + quantity, 0.0))
		pressure_residuals[quantity] = total_out - total_in
	for raw_room_key in room_keys.keys():
		var room_key: String = String(raw_room_key)
		var record: Dictionary = _canonical_interior_opening_by_room.get(
			room_key, _new_canonical_interior_opening_record()
		).duplicate(true)
		var raw_totals: Dictionary = raw_totals_by_room.get(room_key, {})
		var limited_totals: Dictionary = limited_totals_by_room.get(room_key, {})
		for direction in ["out", "in"]:
			record["pressure_raw_%s_gas_kg" % direction] = float(
				raw_totals.get("%s_gas_kg" % direction, 0.0)
			)
			for quantity in ["gas_kg", "energy_kj", "o2_kg", "species_kg"]:
				record["pressure_requested_%s_%s" % [direction, quantity]] = float(
					limited_totals.get("%s_%s" % [direction, quantity], 0.0)
				)
		record["pressure_equilibrium_fraction"] = equilibrium_fraction
		record["pressure_full_delta_pa"] = float(full_delta_by_room.get(room_key, 0.0))
		record["pressure_limited_delta_pa"] = float(
			limited_delta_by_room.get(room_key, 0.0)
		)
		record["pressure_predicted_post_pa"] = float(
			pressure_by_room.get(room_key, 0.0)
		) + float(base_delta_by_room.get(room_key, 0.0)) \
				+ float(limited_delta_by_room.get(room_key, 0.0))
		record["pressure_crossing_prevented_count"] = float(
			relaxation.get("crossing_prevented_count", 0.0)
		)
		record["pressure_mass_residual_kg"] = float(
			pressure_residuals.get("gas_kg", 0.0)
		)
		record["pressure_energy_residual_kj"] = float(
			pressure_residuals.get("energy_kj", 0.0)
		)
		record["pressure_o2_residual_kg"] = float(
			pressure_residuals.get("o2_kg", 0.0)
		)
		record["pressure_species_residual_kg"] = float(
			pressure_residuals.get("species_kg", 0.0)
		)
		_canonical_interior_opening_by_room[room_key] = record


func _new_canonical_interior_opening_record() -> Dictionary:
	return {
		"opening_count": 0.0,
		"active_opening_count": 0.0,
		"vertical_skipped_count": 0.0,
		"invalid_preview_count": 0.0,
		"route_count": 0.0,
		"neutral_plane_m": 0.0,
		"neutral_plane_weighted_m_kg": 0.0,
		"neutral_plane_weight_kg": 0.0,
		"requested_out_gas_kg": 0.0,
		"requested_in_gas_kg": 0.0,
		"requested_out_energy_kj": 0.0,
		"requested_in_energy_kj": 0.0,
		"requested_out_o2_kg": 0.0,
		"requested_in_o2_kg": 0.0,
		"requested_out_species_kg": 0.0,
		"requested_in_species_kg": 0.0,
		"accepted_out_gas_kg": 0.0,
		"accepted_in_gas_kg": 0.0,
		"accepted_out_energy_kj": 0.0,
		"accepted_in_energy_kj": 0.0,
		"accepted_out_o2_kg": 0.0,
		"accepted_in_o2_kg": 0.0,
		"accepted_out_species_kg": 0.0,
		"accepted_in_species_kg": 0.0,
		"accepted_fraction": 1.0,
		"net_mass_kg": 0.0,
		"net_energy_kj": 0.0,
		"net_o2_kg": 0.0,
		"net_species_kg": 0.0,
		"mass_residual_kg": 0.0,
		"energy_residual_kj": 0.0,
		"o2_residual_kg": 0.0,
		"species_residual_kg": 0.0,
		"duplicate_owner_flag": 0.0,
		"pressure_enabled_flag": 0.0,
		"pressure_opening_count": 0.0,
		"pressure_pre_pa": 0.0,
		"pressure_raw_out_gas_kg": 0.0,
		"pressure_raw_in_gas_kg": 0.0,
		"pressure_requested_out_gas_kg": 0.0,
		"pressure_requested_in_gas_kg": 0.0,
		"pressure_requested_out_energy_kj": 0.0,
		"pressure_requested_in_energy_kj": 0.0,
		"pressure_requested_out_o2_kg": 0.0,
		"pressure_requested_in_o2_kg": 0.0,
		"pressure_requested_out_species_kg": 0.0,
		"pressure_requested_in_species_kg": 0.0,
		"pressure_accepted_out_gas_kg": 0.0,
		"pressure_accepted_in_gas_kg": 0.0,
		"pressure_net_mass_kg": 0.0,
		"pressure_equilibrium_fraction": 1.0,
		"pressure_full_delta_pa": 0.0,
		"pressure_limited_delta_pa": 0.0,
		"pressure_predicted_post_pa": 0.0,
		"pressure_crossing_prevented_count": 0.0,
		"pressure_mass_residual_kg": 0.0,
		"pressure_energy_residual_kj": 0.0,
		"pressure_o2_residual_kg": 0.0,
		"pressure_species_residual_kg": 0.0,
	}


## F3.2a: registra el contrato exterior del paso. El bundle se resuelve solo
## en finalize_step, despues de los fluxes internos, y nunca escribe legacy.
func queue_canonical_exterior_boundary_requests(
		building,
		dt: float,
		reference_temp_c: float,
		outside_o2: float,
		closed_leakage_area_m2: float,
		pressure_threshold_pa: float,
		discharge_coeff: float = EXTERIOR_DISCHARGE_COEFF,
		pressure_relaxation_enabled: bool = false
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
		"pressure_relaxation_enabled": pressure_relaxation_enabled,
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
		var outflow: bool = pressure_gauge_pa > 0.0
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
		var pressure_relaxation_enabled: bool = bool(
			_canonical_exterior_boundary_context.get(
				"pressure_relaxation_enabled", false
			)
		)
		# F3.2b2: fresh exterior inflow recreates a lower layer when the
		# persistent state has reached the conservative one-zone upper limit.
		# Routing the inflow back to upper would make that collapse irreversible.
		if pressure_relaxation_enabled and not outflow \
				and float(area_by_zone.get("actual_open_area_m2", 0.0)) > 1.0e-12 \
				and float(state.get("lower_gas_kg", 0.0)) <= THERMO_MASS_EPS_KG \
				and float(state.get("upper_gas_kg", 0.0)) > THERMO_MASS_EPS_KG:
			var total_exterior_area_m2: float = maxf(
				0.0,
				float(area_by_zone.get(ZONE_UPPER, 0.0))
						+ float(area_by_zone.get(ZONE_LOWER, 0.0))
			)
			area_by_zone[ZONE_UPPER] = 0.0
			area_by_zone[ZONE_LOWER] = total_exterior_area_m2
			record["degenerate_lower_reseed_flag"] = 1.0

		var routes: Array = []
		var requested_totals: Dictionary = {
			"gas_mass_kg": 0.0,
			"sensible_enthalpy_kj": 0.0,
			"o2_kg": 0.0,
			"species_kg": 0.0,
		}
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
		var raw_requested_totals: Dictionary = requested_totals.duplicate(true)
		var relaxation: Dictionary = compute_exterior_pressure_relaxation(
			pressure_gauge_pa,
			float(raw_requested_totals.get("gas_mass_kg", 0.0)),
			float(raw_requested_totals.get("sensible_enthalpy_kj", 0.0)),
			outflow,
			room.volume_m3(),
			reference_temp_c
		) if pressure_relaxation_enabled else {
			"fraction": 1.0,
			"full_delta_pa": 0.0,
			"limited_delta_pa": 0.0,
			"predicted_post_pa": pressure_gauge_pa,
			"crossing_prevented_flag": 0.0,
		}
		var equilibrium_fraction: float = clampf(
			float(relaxation.get("fraction", 1.0)), 0.0, 1.0
		)
		if equilibrium_fraction < 1.0 - 1.0e-12:
			routes = _scaled_atomic_routes(routes, equilibrium_fraction)
			for quantity_name in [
				"gas_mass_kg", "sensible_enthalpy_kj", "o2_kg", "species_kg"
			]:
				requested_totals[quantity_name] = float(
					raw_requested_totals.get(quantity_name, 0.0)
				) * equilibrium_fraction
		if outflow and active_zone_count > 1:
			source_zone_code = 3
		record["relaxation_enabled_flag"] = 1.0 if pressure_relaxation_enabled else 0.0
		record["raw_requested_gas_kg"] = float(
			raw_requested_totals.get("gas_mass_kg", 0.0)
		)
		record["raw_requested_energy_kj"] = float(
			raw_requested_totals.get("sensible_enthalpy_kj", 0.0)
		)
		record["pressure_equilibrium_fraction"] = equilibrium_fraction
		record["pressure_full_delta_pa"] = float(
			relaxation.get("full_delta_pa", 0.0)
		)
		record["pressure_limited_delta_pa"] = float(
			relaxation.get("limited_delta_pa", 0.0)
		)
		record["pressure_predicted_post_pa"] = float(
			relaxation.get("predicted_post_pa", pressure_gauge_pa)
		)
		record["pressure_crossing_prevented_flag"] = float(
			relaxation.get("crossing_prevented_flag", 0.0)
		)
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
	var areas: Dictionary = {
		ZONE_UPPER: 0.0,
		ZONE_LOWER: 0.0,
		"actual_open_area_m2": 0.0,
	}
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
		if area_m2 > 1.0e-12:
			areas["actual_open_area_m2"] = float(
				areas.get("actual_open_area_m2", 0.0)
			) + area_m2
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


## F3.2b2: fraction of one explicit orifice step that reaches, but never
## crosses, ambient pressure. The EOS is linear in total gas mass and sensible
## energy, so this is an exact equilibrium bound rather than an empirical cap.
func compute_exterior_pressure_relaxation(
		pressure_gauge_pa: float,
		requested_gas_kg: float,
		requested_energy_kj: float,
		outflow: bool,
		room_volume_m3: float,
		reference_temp_c: float
	) -> Dictionary:
	var result: Dictionary = {
		"fraction": 1.0,
		"full_delta_pa": 0.0,
		"limited_delta_pa": 0.0,
		"predicted_post_pa": pressure_gauge_pa,
		"crossing_prevented_flag": 0.0,
	}
	var reference_temp_k: float = reference_temp_c + 273.15
	if room_volume_m3 <= 0.0 or reference_temp_k <= 0.0 \
			or requested_gas_kg < 0.0 or requested_energy_kj < 0.0:
		return result
	var gas_constant_model: float = AIR_PRESSURE_REF_PA \
			/ (AIR_DENSITY_REF_KG_M3 * reference_temp_k)
	var direction_sign: float = -1.0 if outflow else 1.0
	var full_delta_pa: float = direction_sign * gas_constant_model \
			/ room_volume_m3 * (
				requested_gas_kg * reference_temp_k
						+ requested_energy_kj / AIR_CP_KJ_KG_K
			)
	result["full_delta_pa"] = full_delta_pa
	result["limited_delta_pa"] = full_delta_pa
	result["predicted_post_pa"] = pressure_gauge_pa + full_delta_pa
	if absf(full_delta_pa) <= 1.0e-12 \
			or pressure_gauge_pa * full_delta_pa >= 0.0:
		return result
	var full_post_pa: float = pressure_gauge_pa + full_delta_pa
	if pressure_gauge_pa * full_post_pa >= 0.0:
		return result
	var equilibrium_fraction: float = clampf(
		-pressure_gauge_pa / full_delta_pa, 0.0, 1.0
	)
	result["fraction"] = equilibrium_fraction
	result["limited_delta_pa"] = full_delta_pa * equilibrium_fraction
	result["predicted_post_pa"] = pressure_gauge_pa \
			+ float(result["limited_delta_pa"])
	result["crossing_prevented_flag"] = 1.0
	return result


func _scaled_atomic_routes(routes: Array, fraction: float) -> Array:
	var scaled_routes: Array = []
	var accepted_fraction: float = clampf(fraction, 0.0, 1.0)
	for raw_route in routes:
		var route: Dictionary = raw_route.duplicate(true)
		for quantity_name in ["gas_mass_kg", "sensible_enthalpy_kj", "o2_kg"]:
			route[quantity_name] = float(route.get(quantity_name, 0.0)) \
					* accepted_fraction
		var species_kg: Dictionary = _parcel_species(route.get("species_kg", {}))
		for species_name in PARCEL_SPECIES:
			species_kg[species_name] = float(species_kg.get(species_name, 0.0)) \
					* accepted_fraction
		route["species_kg"] = species_kg
		scaled_routes.append(route)
	return scaled_routes


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
		"relaxation_enabled_flag": 0.0,
		"raw_requested_gas_kg": 0.0,
		"raw_requested_energy_kj": 0.0,
		"pressure_equilibrium_fraction": 1.0,
		"pressure_full_delta_pa": 0.0,
		"pressure_limited_delta_pa": 0.0,
		"pressure_predicted_post_pa": 0.0,
		"pressure_crossing_prevented_flag": 0.0,
		"degenerate_lower_reseed_flag": 0.0,
		"degenerate_lower_reseed_mass_kg": 0.0,
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


func _tag_connection_route(
		route: Dictionary,
		opening_id: int,
		reference_temp_c: float
	) -> void:
	route["connection_id"] = "opening:%d" % opening_id
	route["opening_id"] = opening_id
	route["reference_temp_c"] = reference_temp_c


func _record_connection_residence_route(
		route: Dictionary,
		accepted_fraction: float
	) -> void:
	if not connection_residence_diagnostics_enabled:
		return
	var family_name: String = _mass_cause_family(String(route.get("cause", "")))
	if family_name not in ["interior_opening", "interior_pressure"]:
		return
	var connection_id: String = String(route.get("connection_id", ""))
	if connection_id.is_empty():
		return
	var accepted_mass_kg: float = maxf(
		0.0, float(route.get("gas_mass_kg", 0.0))
	) * clampf(accepted_fraction, 0.0, 1.0)
	if accepted_mass_kg <= THERMO_MASS_EPS_KG:
		return
	var accepted_energy_kj: float = maxf(
		0.0, float(route.get("sensible_enthalpy_kj", 0.0))
	) * clampf(accepted_fraction, 0.0, 1.0)
	var source_room_id: int = int(route.get("source_room_id", EXTERIOR_ID))
	var destination_room_id: int = int(
		route.get("destination_room_id", EXTERIOR_ID)
	)
	var source_zone: String = String(route.get("source_zone", ZONE_UPPER))
	var destination_zone: String = String(
		route.get("destination_zone", ZONE_UPPER)
	)
	var record_key: String = "%s|%d>%d|%s" % [
		connection_id, source_room_id, destination_room_id, family_name
	]
	var record: Dictionary = _connection_residence_cumulative.get(
		record_key,
		{
			"connection_id": connection_id,
			"opening_id": int(route.get("opening_id", -1)),
			"family": family_name,
			"source_room_id": source_room_id,
			"destination_room_id": destination_room_id,
			"accepted_mass_kg": 0.0,
			"accepted_enthalpy_kj": 0.0,
			"source_upper_mass_kg": 0.0,
			"source_lower_mass_kg": 0.0,
			"destination_upper_mass_kg": 0.0,
			"destination_lower_mass_kg": 0.0,
			"source_temp_mass_c_kg": 0.0,
			"accepted_route_count": 0,
		}
	).duplicate(true)
	var reference_temp_c: float = float(route.get("reference_temp_c", 20.0))
	var source_temp_c: float = reference_temp_c
	if accepted_mass_kg > THERMO_MASS_EPS_KG:
		source_temp_c += accepted_energy_kj \
				/ (accepted_mass_kg * AIR_CP_KJ_KG_K)
	record["accepted_mass_kg"] = float(
		record.get("accepted_mass_kg", 0.0)
	) + accepted_mass_kg
	record["accepted_enthalpy_kj"] = float(
		record.get("accepted_enthalpy_kj", 0.0)
	) + accepted_energy_kj
	record["source_" + source_zone + "_mass_kg"] = float(
		record.get("source_" + source_zone + "_mass_kg", 0.0)
	) + accepted_mass_kg
	record["destination_" + destination_zone + "_mass_kg"] = float(
		record.get("destination_" + destination_zone + "_mass_kg", 0.0)
	) + accepted_mass_kg
	record["source_temp_mass_c_kg"] = float(
		record.get("source_temp_mass_c_kg", 0.0)
	) + source_temp_c * accepted_mass_kg
	record["accepted_route_count"] = int(
		record.get("accepted_route_count", 0)
	) + 1
	_connection_residence_cumulative[record_key] = record


func get_connection_residence_results() -> Array:
	var records: Array = []
	for record_key in _connection_residence_cumulative.keys():
		var record: Dictionary = _connection_residence_cumulative[
			record_key
		].duplicate(true)
		var accepted_mass_kg: float = maxf(
			0.0, float(record.get("accepted_mass_kg", 0.0))
		)
		record["mass_weighted_source_temp_c"] = (
			float(record.get("source_temp_mass_c_kg", 0.0)) / accepted_mass_kg
			if accepted_mass_kg > THERMO_MASS_EPS_KG
			else 0.0
		)
		record["destination_upper_fraction"] = (
			float(record.get("destination_upper_mass_kg", 0.0))
					/ accepted_mass_kg
			if accepted_mass_kg > THERMO_MASS_EPS_KG
			else 0.0
		)
		record.erase("source_temp_mass_c_kg")
		records.append(record)
	records.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_key: String = "%010d|%010d|%010d|%s" % [
			int(left.get("opening_id", -1)),
			int(left.get("source_room_id", EXTERIOR_ID)),
			int(left.get("destination_room_id", EXTERIOR_ID)),
			String(left.get("family", "")),
		]
		var right_key: String = "%010d|%010d|%010d|%s" % [
			int(right.get("opening_id", -1)),
			int(right.get("source_room_id", EXTERIOR_ID)),
			int(right.get("destination_room_id", EXTERIOR_ID)),
			String(right.get("family", "")),
		]
		return left_key < right_key
	)
	return records


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
	_commit_canonical_multisurface_records()
	_commit_canonical_wall_ambient_records(reference_temp_c)
	if building == null:
		return
	if _persistence_enabled_step:
		_collapse_degenerate_zones(shadow)
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
	var persistence_step_index: int = _persistent_step_index + 1 \
			if _persistence_enabled_step else 0
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
		var exterior_counterflow: Dictionary = _canonical_exterior_counterflow_by_room.get(
			room_key, _new_canonical_exterior_counterflow_record()
		)
		var interior_opening: Dictionary = _canonical_interior_opening_by_room.get(
			room_key, _new_canonical_interior_opening_record()
		)
		var lower_reseed_history: Dictionary = _persistent_lower_reseed_by_room.get(
			room_key,
			{"count": 0.0, "mass_kg": 0.0, "first_step_index": 0.0}
		)
		var continuity: Dictionary = _persistence_continuity_by_room.get(
			room_key, _zero_state_delta_summary()
		)
		var combustion_probe: Dictionary = _combustion_o2_probe_by_room.get(room_key, {})
		var zone_collapse: Dictionary = _persistent_zone_collapse_by_room.get(
			room_key, _new_zone_collapse_record()
		)
		var canonical_combustion: Dictionary = _canonical_combustion_by_room.get(
			room_key, {}
		)
		var canonical_interzone_heat: Dictionary = _canonical_interzone_heat_by_room.get(
			room_key, {}
		)
		var canonical_wall_ambient: Dictionary = _canonical_wall_ambient_by_room.get(
			room_key, {}
		)
		var canonical_multisurface: Dictionary = _canonical_multisurface_by_room.get(
			room_key, {}
		)
		var canonical_multisurface_exchange: Dictionary = \
				_canonical_multisurface_exchange_by_room.get(room_key, {})
		var canonical_multisurface_cumulative: Dictionary = \
				_canonical_multisurface_cumulative_by_room.get(room_key, {})
		var canonical_multisurface_state: Dictionary = \
				_canonical_surface_state_by_room.get(room_key, {})
		var canonical_multisurface_surfaces: Dictionary = \
				canonical_multisurface_state.get("surfaces", {})
		var canonical_multisurface_cumulative_surfaces: Dictionary = \
				canonical_multisurface_cumulative.get("surfaces", {})
		var canonical_combustion_atomic_fraction: float = clampf(
			float(canonical_combustion.get("atomic_accepted_fraction", 1.0)), 0.0, 1.0
		)
		var canonical_combustion_state: Dictionary = canonical_combustion.get(
			"committed_fire_state", {}
		)
		var combustion_o2_requested_kg: float = _sum_room_cause_prefix_o2(
			room_id, "combustion_o2_"
		)
		var combustion_o2_rejected_kg: float = float(
			rejected_combustion_o2_by_room.get(room_key, 0.0)
		)
		var combustion_o2_accepted_kg: float = maxf(
			0.0, combustion_o2_requested_kg - combustion_o2_rejected_kg
		)
		var combustion_o2_accepted_fraction: float = 1.0
		if combustion_o2_requested_kg > THERMO_MASS_EPS_KG:
			combustion_o2_accepted_fraction = clampf(
				combustion_o2_accepted_kg / combustion_o2_requested_kg, 0.0, 1.0
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
			"phase3_shadow_persistent_step_index": float(persistence_step_index),
			"phase3_shadow_persistent_seeded_from_legacy_flag": 1.0 \
					if bool(_persistence_seeded_by_room.get(room_key, false)) else 0.0,
			"phase3_shadow_persistent_continuity_mass_residual_kg": float(
				continuity.get("mass_kg", 0.0)
			),
			"phase3_shadow_persistent_continuity_energy_residual_kj": float(
				continuity.get("energy_kj", 0.0)
			),
			"phase3_shadow_persistent_continuity_o2_residual_kg": float(
				continuity.get("o2_kg", 0.0)
			),
			"phase3_shadow_persistent_continuity_species_residual_kg": float(
				continuity.get("species_kg", 0.0)
			),
			"phase3_shadow_persistent_pre_upper_o2_fraction": float(
				combustion_probe.get(
					"pre_upper_o2_fraction", _zone_o2_fraction(_snapshots[room_key], ZONE_UPPER)
				)
			),
			"phase3_shadow_persistent_pre_lower_o2_fraction": float(
				combustion_probe.get(
					"pre_lower_o2_fraction", _zone_o2_fraction(_snapshots[room_key], ZONE_LOWER)
				)
			),
			"phase3_shadow_persistent_post_upper_o2_fraction": _zone_o2_fraction(
				state, ZONE_UPPER
			),
			"phase3_shadow_persistent_post_lower_o2_fraction": _zone_o2_fraction(
				state, ZONE_LOWER
			),
			"phase3_shadow_persistent_combustion_o2_ref": float(
				combustion_probe.get("canonical_o2_ref", 0.0)
			),
			"phase3_shadow_persistent_legacy_combustion_o2_ref": float(
				combustion_probe.get("legacy_o2_ref", 0.0)
			),
			"phase3_shadow_persistent_combustion_o2_delta": float(
				combustion_probe.get("canonical_o2_ref", 0.0)
			) - float(combustion_probe.get("legacy_o2_ref", 0.0)),
			"phase3_shadow_persistent_combustion_zone_code": float(
				combustion_probe.get("selected_zone_code", 0.0)
			),
			"phase3_shadow_persistent_combustion_o2_requested_kg": \
					combustion_o2_requested_kg,
			"phase3_shadow_persistent_combustion_o2_accepted_kg": \
					combustion_o2_accepted_kg,
			"phase3_shadow_persistent_combustion_o2_rejected_kg": \
					combustion_o2_rejected_kg,
			"phase3_shadow_persistent_combustion_o2_accepted_fraction": \
					combustion_o2_accepted_fraction,
			"phase3_shadow_persistent_combustion_would_limit_flag": float(
				combustion_probe.get("would_limit_flag", 0.0)
			),
			"phase3_shadow_persistent_zone_collapse_count": float(
				zone_collapse.get("count", 0.0)
			),
			"phase3_shadow_persistent_zone_collapse_source_code": float(
				zone_collapse.get("source_zone_code", 0.0)
			),
			"phase3_shadow_persistent_zone_collapse_mass_residual_kg": float(
				zone_collapse.get("mass_residual_kg", 0.0)
			),
			"phase3_shadow_persistent_zone_collapse_energy_residual_kj": float(
				zone_collapse.get("energy_residual_kj", 0.0)
			),
			"phase3_shadow_persistent_zone_collapse_o2_residual_kg": float(
				zone_collapse.get("o2_residual_kg", 0.0)
			),
			"phase3_shadow_persistent_zone_collapse_species_residual_kg": float(
				zone_collapse.get("species_residual_kg", 0.0)
			),
			"phase3_shadow_combustion_transaction_active_flag": 1.0 \
					if not canonical_combustion.is_empty() else 0.0,
			"phase3_shadow_combustion_canonical_o2_ref": float(
				canonical_combustion.get("canonical_o2_ref", 0.0)
			),
			"phase3_shadow_combustion_o2_source_zone_code": float(
				canonical_combustion.get("o2_source_zone_code", 0.0)
			),
			"phase3_shadow_combustion_extinction_o2_limit": float(
				canonical_combustion.get("extinction_o2_limit", 0.0)
			),
			"phase3_shadow_combustion_canonical_o2_hrr_factor": float(
				canonical_combustion.get("canonical_o2_hrr_factor", 0.0)
			),
			"phase3_shadow_combustion_legacy_o2_hrr_factor": float(
				canonical_combustion.get("legacy_o2_hrr_factor", 0.0)
			),
			"phase3_shadow_combustion_legacy_hrr_kw": float(
				canonical_combustion.get("legacy_hrr_kw", 0.0)
			),
			"phase3_shadow_combustion_accepted_hrr_kw": float(
				canonical_combustion.get("accepted_hrr_kw", 0.0)
			) * canonical_combustion_atomic_fraction,
			"phase3_shadow_combustion_requested_radiative_energy_kj": float(
				canonical_combustion.get("requested_radiative_energy_kj", 0.0)
			),
			"phase3_shadow_combustion_accepted_radiative_energy_kj": float(
				canonical_combustion.get(
					"atomic_accepted_radiative_energy_kj", 0.0
				)
			),
			"phase3_shadow_combustion_routed_surface_radiation_kj": float(
				canonical_combustion.get("routed_surface_radiation_kj", 0.0)
			),
			"phase3_shadow_combustion_radiative_route_residual_kj": float(
				canonical_combustion.get("radiative_route_residual_kj", 0.0)
			),
			"phase3_shadow_combustion_fire_partition_residual_kj": float(
				canonical_combustion.get("fire_partition_residual_kj", 0.0)
			) * canonical_combustion_atomic_fraction,
			"phase3_shadow_combustion_decision_fraction": float(
				canonical_combustion.get("decision_fraction", 0.0)
			),
			"phase3_shadow_combustion_atomic_fraction": \
					canonical_combustion_atomic_fraction,
			"phase3_shadow_combustion_effective_fraction": float(
				canonical_combustion.get("effective_fraction", 0.0)
			),
			"phase3_shadow_combustion_requested_o2_kg": float(
				canonical_combustion.get("requested_o2_kg", 0.0)
			),
			"phase3_shadow_combustion_accepted_o2_kg": float(
				canonical_combustion.get("accepted_o2_kg", 0.0)
			) * canonical_combustion_atomic_fraction,
			"phase3_shadow_combustion_requested_fuel_MJ": float(
				canonical_combustion.get("requested_fuel_MJ", 0.0)
			),
			"phase3_shadow_combustion_accepted_fuel_MJ": float(
				canonical_combustion.get("accepted_fuel_MJ", 0.0)
			) * canonical_combustion_atomic_fraction,
			"phase3_shadow_combustion_requested_species_kg": _sum_parcel_species(
				canonical_combustion.get("requested_species_kg", {})
			),
			"phase3_shadow_combustion_accepted_species_kg": _sum_parcel_species(
				canonical_combustion.get("accepted_species_kg", {})
			) * canonical_combustion_atomic_fraction,
			"phase3_shadow_combustion_requested_convective_energy_kj": float(
				canonical_combustion.get("requested_convective_energy_kj", 0.0)
			),
			"phase3_shadow_combustion_accepted_convective_energy_kj": float(
				canonical_combustion.get("accepted_convective_energy_kj", 0.0)
			) * canonical_combustion_atomic_fraction,
			"phase3_shadow_combustion_requested_plume_mass_kg": float(
				canonical_combustion.get("requested_plume_mass_kg", 0.0)
			),
			"phase3_shadow_combustion_accepted_plume_mass_kg": float(
				canonical_combustion.get("accepted_plume_mass_kg", 0.0)
			) * canonical_combustion_atomic_fraction,
			"phase3_shadow_combustion_remaining_fuel_MJ": float(
				canonical_combustion_state.get("remaining_fuel_MJ", 0.0)
			),
			"phase3_shadow_combustion_retained_unburned_MJ": float(
				canonical_combustion_state.get("retained_unburned_MJ", 0.0)
			),
			"phase3_shadow_combustion_zero_o2_flame_flag": float(
				canonical_combustion.get("zero_o2_flame_flag", 0.0)
			),
			"phase3_shadow_combustion_o2_residual_kg": float(
				canonical_combustion.get("o2_residual_kg", 0.0)
			),
			"phase3_shadow_combustion_energy_residual_kj": float(
				canonical_combustion.get("energy_residual_kj", 0.0)
			),
			"phase3_shadow_combustion_species_residual_kg": float(
				canonical_combustion.get("species_residual_kg", 0.0)
			),
			"phase3_shadow_fire_proposal_active_flag": float(
				canonical_combustion.get(
					"canonical_fire_proposal_active_flag", 0.0
				)
			),
			"phase3_shadow_fire_proposal_supported_flag": float(
				canonical_combustion.get(
					"canonical_fire_proposal_supported_flag", 0.0
				)
			),
			"phase3_shadow_fire_proposal_unsupported_reason_mask": float(
				canonical_combustion.get(
					"canonical_fire_proposal_unsupported_reason_mask", 0.0
				)
			),
			"phase3_shadow_fire_proposal_age_s": float(
				canonical_combustion.get(
					"canonical_fire_proposal_proposal_age_s", 0.0
				)
			),
			"phase3_shadow_fire_proposal_curve_hrr_kw": float(
				canonical_combustion.get(
					"canonical_fire_proposal_curve_hrr_kw", 0.0
				)
			),
			"phase3_shadow_fire_proposal_target_kw": float(
				canonical_combustion.get(
					"canonical_fire_proposal_proposal_target_kw", 0.0
				)
			),
			"phase3_shadow_fire_proposal_hrr_kw": float(
				canonical_combustion.get(
					"canonical_fire_proposal_proposal_hrr_kw", 0.0
				)
			),
			"phase3_shadow_fire_proposal_unfiltered_growth_flag": float(
				canonical_combustion.get(
					"canonical_fire_proposal_unfiltered_growth_flag", 0.0
				)
			),
			"phase3_shadow_fire_proposal_remaining_fuel_pre_MJ": float(
				canonical_combustion.get(
					"canonical_fire_proposal_remaining_fuel_pre_MJ", 0.0
				)
			),
			"phase3_shadow_fire_proposal_remaining_fuel_post_MJ": float(
				canonical_combustion.get(
					"canonical_fire_proposal_remaining_fuel_post_MJ", 0.0
				)
			),
			"phase3_shadow_fire_proposal_hard_extinction_flag": float(
				canonical_combustion.get(
					"canonical_fire_proposal_hard_extinction_flag", 0.0
				)
			),
			"phase3_shadow_fire_proposal_o2_inventory_cap_kw": float(
				canonical_combustion.get(
					"canonical_fire_proposal_o2_inventory_cap_kw", 0.0
				)
			),
			"phase3_shadow_fire_proposal_ventilation_cap_kw": float(
				canonical_combustion.get(
					"canonical_fire_proposal_ventilation_cap_kw", -1.0
				)
			),
			"phase3_shadow_fire_proposal_fuel_cap_kw": float(
				canonical_combustion.get(
					"canonical_fire_proposal_fuel_cap_kw", 0.0
				)
			),
			"phase3_shadow_fire_proposal_decision_fraction": float(
				canonical_combustion.get(
					"canonical_fire_proposal_decision_fraction", 0.0
				)
			),
			"phase3_shadow_fire_proposal_accepted_hrr_kw": float(
				canonical_combustion.get(
					"canonical_fire_proposal_accepted_hrr_kw", 0.0
				)
			),
			"phase3_shadow_fire_proposal_requested_o2_kg": float(
				canonical_combustion.get(
					"canonical_fire_proposal_requested_o2_kg", 0.0
				)
			),
			"phase3_shadow_fire_proposal_accepted_o2_kg": float(
				canonical_combustion.get(
					"canonical_fire_proposal_accepted_o2_kg", 0.0
				)
			),
			"phase3_shadow_fire_proposal_accepted_fuel_MJ": float(
				canonical_combustion.get(
					"canonical_fire_proposal_accepted_fuel_MJ", 0.0
				)
			),
			"phase3_shadow_fire_proposal_zero_o2_flame_flag": float(
				canonical_combustion.get(
					"canonical_fire_proposal_zero_o2_flame_flag", 0.0
				)
			),
			"phase3_shadow_post_opening_coupling_active_flag": float(
				canonical_combustion.get("post_opening_coupling_active_flag", 0.0)
			),
			"phase3_shadow_post_opening_source_switched_to_lower_flag": float(
				canonical_combustion.get(
					"post_opening_source_switched_to_lower_flag", 0.0
				)
			),
			"phase3_shadow_post_opening_counterflow_exchange_kg_step": float(
				canonical_combustion.get("post_opening_counterflow_exchange_kg", 0.0)
			),
			"phase3_shadow_post_opening_counterflow_incoming_o2_kg_step": float(
				canonical_combustion.get(
					"post_opening_counterflow_incoming_o2_kg", 0.0
				)
			),
			"phase3_shadow_post_opening_source_o2_available_kg": float(
				canonical_combustion.get("post_opening_source_o2_available_kg", 0.0)
			),
			"phase3_shadow_post_opening_full_hrr_o2_demand_kg_step": float(
				canonical_combustion.get("post_opening_full_hrr_o2_demand_kg", 0.0)
			),
			"phase3_shadow_post_opening_o2_supply_margin_kg_step": float(
				canonical_combustion.get("post_opening_o2_supply_margin_kg", 0.0)
			),
			"phase3_shadow_post_opening_combustion_air_min_plume_mass_kg_step": float(
				canonical_combustion.get(
					"post_opening_combustion_air_min_plume_mass_kg", 0.0
				)
			),
			"phase3_shadow_post_opening_plume_height_term_mass_kg_step": float(
				canonical_combustion.get(
					"post_opening_plume_height_term_mass_kg", 0.0
				)
			),
			"phase3_shadow_post_opening_plume_source_term_mass_kg_step": float(
				canonical_combustion.get(
					"post_opening_plume_source_term_mass_kg", 0.0
				)
			),
			"phase3_shadow_post_opening_plume_o2_to_upper_kg_step": float(
				canonical_combustion.get("post_opening_plume_o2_to_upper_kg", 0.0)
			),
			"phase3_shadow_post_opening_lower_o2_closure_residual_kg": float(
				canonical_combustion.get(
					"post_opening_lower_o2_closure_residual_kg", 0.0
				)
			),
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
			"phase3_shadow_exterior_relaxation_enabled_flag": float(
				exterior_boundary.get("relaxation_enabled_flag", 0.0)
			),
			"phase3_shadow_exterior_raw_requested_gas_kg": float(
				exterior_boundary.get("raw_requested_gas_kg", 0.0)
			),
			"phase3_shadow_exterior_raw_requested_energy_kj": float(
				exterior_boundary.get("raw_requested_energy_kj", 0.0)
			),
			"phase3_shadow_exterior_pressure_equilibrium_fraction": float(
				exterior_boundary.get("pressure_equilibrium_fraction", 1.0)
			),
			"phase3_shadow_exterior_pressure_full_delta_pa": float(
				exterior_boundary.get("pressure_full_delta_pa", 0.0)
			),
			"phase3_shadow_exterior_pressure_limited_delta_pa": float(
				exterior_boundary.get("pressure_limited_delta_pa", 0.0)
			),
			"phase3_shadow_exterior_pressure_predicted_post_pa": float(
				exterior_boundary.get("pressure_predicted_post_pa", 0.0)
			),
			"phase3_shadow_exterior_pressure_crossing_prevented_flag": float(
				exterior_boundary.get("pressure_crossing_prevented_flag", 0.0)
			),
			"phase3_shadow_exterior_degenerate_lower_reseed_flag": float(
				exterior_boundary.get("degenerate_lower_reseed_flag", 0.0)
			),
			"phase3_shadow_exterior_degenerate_lower_reseed_mass_kg": float(
				exterior_boundary.get("degenerate_lower_reseed_mass_kg", 0.0)
			),
			"phase3_shadow_exterior_lower_reseed_count_total": float(
				lower_reseed_history.get("count", 0.0)
			),
			"phase3_shadow_exterior_lower_reseed_mass_kg_total": float(
				lower_reseed_history.get("mass_kg", 0.0)
			),
			"phase3_shadow_exterior_lower_reseed_first_step_index": float(
				lower_reseed_history.get("first_step_index", 0.0)
			),
			"phase3_shadow_counterflow_neutral_plane_m": float(
				exterior_counterflow.get("neutral_plane_m", 0.0)
			),
			"phase3_shadow_counterflow_neutral_pressure_offset_pa": float(
				exterior_counterflow.get("neutral_pressure_offset_pa", 0.0)
			),
			"phase3_shadow_counterflow_raw_upper_out_kg_step": float(
				exterior_counterflow.get("raw_upper_out_kg", 0.0)
			),
			"phase3_shadow_counterflow_raw_lower_in_kg_step": float(
				exterior_counterflow.get("raw_lower_in_kg", 0.0)
			),
			"phase3_shadow_counterflow_requested_exchange_kg_step": float(
				exterior_counterflow.get("requested_exchange_kg", 0.0)
			),
			"phase3_shadow_counterflow_accepted_exchange_kg_step": float(
				exterior_counterflow.get("accepted_exchange_kg", 0.0)
			),
			"phase3_shadow_counterflow_rejected_exchange_kg_step": float(
				exterior_counterflow.get("rejected_exchange_kg", 0.0)
			),
			"phase3_shadow_counterflow_cumulative_exchange_kg": float(
				exterior_counterflow.get("cumulative_exchange_kg", 0.0)
			),
			"phase3_shadow_counterflow_cumulative_upper_out_kg": float(
				exterior_counterflow.get("cumulative_exchange_kg", 0.0)
			),
			"phase3_shadow_counterflow_cumulative_lower_in_kg": float(
				exterior_counterflow.get("cumulative_exchange_kg", 0.0)
			),
			"phase3_shadow_counterflow_hydrostatic_net_kg_step": float(
				exterior_counterflow.get("hydrostatic_net_kg", 0.0)
			),
			"phase3_shadow_counterflow_pressure_relief_kg_step": float(
				exterior_boundary.get("accepted_gas_kg", 0.0)
			),
			"phase3_shadow_counterflow_pressure_relief_net_kg_step": float(
				exterior_boundary.get("accepted_gas_kg", 0.0)
			) * float(exterior_boundary.get("direction", 0.0)),
			"phase3_shadow_counterflow_outgoing_energy_kj_step": float(
				exterior_counterflow.get("accepted_outgoing_energy_kj", 0.0)
			),
			"phase3_shadow_counterflow_outgoing_o2_kg_step": float(
				exterior_counterflow.get("accepted_outgoing_o2_kg", 0.0)
			),
			"phase3_shadow_counterflow_incoming_o2_kg_step": float(
				exterior_counterflow.get("accepted_incoming_o2_kg", 0.0)
			),
			"phase3_shadow_counterflow_outgoing_species_kg_step": float(
				exterior_counterflow.get("accepted_outgoing_species_kg", 0.0)
			),
			"phase3_shadow_counterflow_accepted_fraction": float(
				exterior_counterflow.get("accepted_fraction", 1.0)
			),
			"phase3_shadow_counterflow_mass_residual_kg": float(
				exterior_counterflow.get("mass_residual_kg", 0.0)
			),
			"phase3_shadow_counterflow_energy_residual_kj": float(
				exterior_counterflow.get("energy_residual_kj", 0.0)
			),
			"phase3_shadow_counterflow_o2_residual_kg": float(
				exterior_counterflow.get("o2_residual_kg", 0.0)
			),
			"phase3_shadow_counterflow_species_residual_kg": float(
				exterior_counterflow.get("species_residual_kg", 0.0)
			),
			"phase3_shadow_counterflow_opening_count": float(
				exterior_counterflow.get("opening_count", 0.0)
			),
			"phase3_shadow_counterflow_duplicate_owner_flag": float(
				exterior_counterflow.get("duplicate_owner_flag", 0.0)
			),
			"phase3_shadow_counterflow_invalid_preview_count": float(
				exterior_counterflow.get("invalid_preview_count", 0.0)
			),
			"phase3_shadow_counterflow_opposed_out_kg_step": float(
				exterior_counterflow.get("opposed_out_kg", 0.0)
			),
			"phase3_shadow_interior_opening_active_flag": 1.0 if float(
				interior_opening.get("active_opening_count", 0.0)
			) > 0.0 else 0.0,
			"phase3_shadow_interior_opening_count": float(
				interior_opening.get("opening_count", 0.0)
			),
			"phase3_shadow_interior_active_opening_count": float(
				interior_opening.get("active_opening_count", 0.0)
			),
			"phase3_shadow_interior_vertical_skipped_count": float(
				interior_opening.get("vertical_skipped_count", 0.0)
			),
			"phase3_shadow_interior_invalid_preview_count": float(
				interior_opening.get("invalid_preview_count", 0.0)
			),
			"phase3_shadow_interior_route_count": float(
				interior_opening.get("route_count", 0.0)
			),
			"phase3_shadow_interior_neutral_plane_m": float(
				interior_opening.get("neutral_plane_m", 0.0)
			),
			"phase3_shadow_interior_requested_out_gas_kg_step": float(
				interior_opening.get("requested_out_gas_kg", 0.0)
			),
			"phase3_shadow_interior_requested_in_gas_kg_step": float(
				interior_opening.get("requested_in_gas_kg", 0.0)
			),
			"phase3_shadow_interior_accepted_out_gas_kg_step": float(
				interior_opening.get("accepted_out_gas_kg", 0.0)
			),
			"phase3_shadow_interior_accepted_in_gas_kg_step": float(
				interior_opening.get("accepted_in_gas_kg", 0.0)
			),
			"phase3_shadow_interior_accepted_out_energy_kj_step": float(
				interior_opening.get("accepted_out_energy_kj", 0.0)
			),
			"phase3_shadow_interior_accepted_in_energy_kj_step": float(
				interior_opening.get("accepted_in_energy_kj", 0.0)
			),
			"phase3_shadow_interior_accepted_out_o2_kg_step": float(
				interior_opening.get("accepted_out_o2_kg", 0.0)
			),
			"phase3_shadow_interior_accepted_in_o2_kg_step": float(
				interior_opening.get("accepted_in_o2_kg", 0.0)
			),
			"phase3_shadow_interior_accepted_out_species_kg_step": float(
				interior_opening.get("accepted_out_species_kg", 0.0)
			),
			"phase3_shadow_interior_accepted_in_species_kg_step": float(
				interior_opening.get("accepted_in_species_kg", 0.0)
			),
			"phase3_shadow_interior_accepted_fraction": float(
				interior_opening.get("accepted_fraction", 1.0)
			),
			"phase3_shadow_interior_net_mass_kg_step": float(
				interior_opening.get("net_mass_kg", 0.0)
			),
			"phase3_shadow_interior_net_energy_kj_step": float(
				interior_opening.get("net_energy_kj", 0.0)
			),
			"phase3_shadow_interior_net_o2_kg_step": float(
				interior_opening.get("net_o2_kg", 0.0)
			),
			"phase3_shadow_interior_net_species_kg_step": float(
				interior_opening.get("net_species_kg", 0.0)
			),
			"phase3_shadow_interior_mass_residual_kg": float(
				interior_opening.get("mass_residual_kg", 0.0)
			),
			"phase3_shadow_interior_energy_residual_kj": float(
				interior_opening.get("energy_residual_kj", 0.0)
			),
			"phase3_shadow_interior_o2_residual_kg": float(
				interior_opening.get("o2_residual_kg", 0.0)
			),
			"phase3_shadow_interior_species_residual_kg": float(
				interior_opening.get("species_residual_kg", 0.0)
			),
			"phase3_shadow_interior_duplicate_owner_flag": float(
				interior_opening.get("duplicate_owner_flag", 0.0)
			),
			"phase3_shadow_interior_pressure_enabled_flag": float(
				interior_opening.get("pressure_enabled_flag", 0.0)
			),
			"phase3_shadow_interior_pressure_opening_count": float(
				interior_opening.get("pressure_opening_count", 0.0)
			),
			"phase3_shadow_interior_pressure_pre_pa": float(
				interior_opening.get("pressure_pre_pa", 0.0)
			),
			"phase3_shadow_interior_pressure_raw_out_gas_kg_step": float(
				interior_opening.get("pressure_raw_out_gas_kg", 0.0)
			),
			"phase3_shadow_interior_pressure_raw_in_gas_kg_step": float(
				interior_opening.get("pressure_raw_in_gas_kg", 0.0)
			),
			"phase3_shadow_interior_pressure_requested_out_gas_kg_step": float(
				interior_opening.get("pressure_requested_out_gas_kg", 0.0)
			),
			"phase3_shadow_interior_pressure_requested_in_gas_kg_step": float(
				interior_opening.get("pressure_requested_in_gas_kg", 0.0)
			),
			"phase3_shadow_interior_pressure_accepted_out_gas_kg_step": float(
				interior_opening.get("pressure_accepted_out_gas_kg", 0.0)
			),
			"phase3_shadow_interior_pressure_accepted_in_gas_kg_step": float(
				interior_opening.get("pressure_accepted_in_gas_kg", 0.0)
			),
			"phase3_shadow_interior_pressure_net_mass_kg_step": float(
				interior_opening.get("pressure_net_mass_kg", 0.0)
			),
			"phase3_shadow_interior_pressure_equilibrium_fraction": float(
				interior_opening.get("pressure_equilibrium_fraction", 1.0)
			),
			"phase3_shadow_interior_pressure_full_delta_pa": float(
				interior_opening.get("pressure_full_delta_pa", 0.0)
			),
			"phase3_shadow_interior_pressure_limited_delta_pa": float(
				interior_opening.get("pressure_limited_delta_pa", 0.0)
			),
			"phase3_shadow_interior_pressure_predicted_post_pa": float(
				interior_opening.get("pressure_predicted_post_pa", 0.0)
			),
			"phase3_shadow_interior_pressure_crossing_prevented_count": float(
				interior_opening.get("pressure_crossing_prevented_count", 0.0)
			),
			"phase3_shadow_interior_pressure_mass_residual_kg": float(
				interior_opening.get("pressure_mass_residual_kg", 0.0)
			),
			"phase3_shadow_interior_pressure_energy_residual_kj": float(
				interior_opening.get("pressure_energy_residual_kj", 0.0)
			),
			"phase3_shadow_interior_pressure_o2_residual_kg": float(
				interior_opening.get("pressure_o2_residual_kg", 0.0)
			),
			"phase3_shadow_interior_pressure_species_residual_kg": float(
				interior_opening.get("pressure_species_residual_kg", 0.0)
			),
			"phase3_shadow_request_count": _count_room_requests(room_id),
			"phase3_shadow_interzone_legacy_requested_kj": float(
				canonical_interzone_heat.get("legacy_requested_kj", 0.0)
			),
			"phase3_shadow_interzone_legacy_candidate_kj": float(
				canonical_interzone_heat.get("legacy_candidate_kj", 0.0)
			),
			"phase3_shadow_interzone_capacity_candidate_kj": float(
				canonical_interzone_heat.get("capacity_candidate_kj", 0.0)
			),
			"phase3_shadow_interzone_equilibrium_limit_kj": float(
				canonical_interzone_heat.get("equilibrium_limit_kj", 0.0)
			),
			"phase3_shadow_interzone_requested_kj": float(
				canonical_interzone_heat.get("requested_kj", 0.0)
			),
			"phase3_shadow_interzone_accepted_kj": float(
				canonical_interzone_heat.get("accepted_kj", 0.0)
			),
			"phase3_shadow_interzone_rejected_kj": float(
				canonical_interzone_heat.get("rejected_kj", 0.0)
			),
			"phase3_shadow_interzone_cumulative_accepted_kj": float(
				_canonical_interzone_heat_cumulative_kj.get(room_key, 0.0)
			),
			"phase3_shadow_interzone_pre_delta_t_c": float(
				canonical_interzone_heat.get("pre_delta_t_c", 0.0)
			),
			"phase3_shadow_interzone_direction_code": float(
				canonical_interzone_heat.get("direction_code", 0.0)
			),
			"phase3_shadow_interzone_energy_residual_kj": float(
				canonical_interzone_heat.get("energy_residual_kj", 0.0)
			),
			"phase3_shadow_multisurface_enabled_flag": \
					1.0 if canonical_multisurface_shadow_enabled else 0.0,
			"phase3_shadow_multisurface_migration_energy_kj": float(
				canonical_multisurface.get("migration_energy_kj", 0.0)
			),
			"phase3_shadow_multisurface_migration_residual_kj": float(
				canonical_multisurface.get("migration_residual_kj", 0.0)
			),
			"phase3_shadow_multisurface_energy_pre_kj": float(
				canonical_multisurface.get("surface_energy_pre_kj", 0.0)
			),
			"phase3_shadow_multisurface_energy_post_kj": float(
				canonical_multisurface.get("surface_energy_post_kj", 0.0)
			),
			"phase3_shadow_multisurface_radiation_residual_kj": float(
				canonical_multisurface.get("radiation_residual_kj", 0.0)
			),
			"phase3_shadow_multisurface_upper_exchange_kj": float(
				canonical_multisurface_exchange.get(
					"accepted_upper_exchange_kj", 0.0
				)
			),
			"phase3_shadow_multisurface_lower_exchange_kj": float(
				canonical_multisurface_exchange.get(
					"accepted_lower_exchange_kj", 0.0
				)
			),
			"phase3_shadow_multisurface_exterior_removed_kj": float(
				canonical_multisurface_exchange.get(
					"accepted_exterior_removed_kj", 0.0
				)
			),
			"phase3_shadow_multisurface_combined_energy_residual_kj": float(
				canonical_multisurface_exchange.get(
					"combined_energy_residual_kj", 0.0
				)
			),
			"phase3_shadow_multisurface_boundary_metadata_complete_flag": float(
				canonical_multisurface_exchange.get(
					"boundary_metadata_complete_flag", 0.0
				)
			),
			"phase3_shadow_multisurface_adiabatic_surface_count": float(
				canonical_multisurface_exchange.get(
					"adiabatic_surface_count", 0.0
				)
			),
			"phase3_shadow_multisurface_exterior_fraction_sum": float(
				canonical_multisurface_exchange.get(
					"exterior_fraction_sum", 0.0
				)
			),
			"phase3_shadow_multisurface_inter_room_fraction_sum": float(
				canonical_multisurface_exchange.get(
					"inter_room_fraction_sum", 0.0
				)
			),
			"phase3_shadow_multisurface_adiabatic_fraction_sum": float(
				canonical_multisurface_exchange.get(
					"adiabatic_fraction_sum", 0.0
				)
			),
			"phase3_shadow_multisurface_unsupported_inter_room_count": float(
				canonical_multisurface_exchange.get(
					"unsupported_inter_room_surface_count", 0.0
				)
			),
			"phase3_shadow_multisurface_duplicate_commit_count": float(
				_canonical_multisurface_duplicate_commit_count
			),
			"phase3_shadow_multisurface_cumulative_step_count": float(
				canonical_multisurface_cumulative.get("step_count", 0.0)
			),
			"phase3_shadow_multisurface_cumulative_upper_exchange_kj": float(
				canonical_multisurface_cumulative.get(
					"upper_gas_exchange_kj", 0.0
				)
			),
			"phase3_shadow_multisurface_cumulative_lower_exchange_kj": float(
				canonical_multisurface_cumulative.get(
					"lower_gas_exchange_kj", 0.0
				)
			),
			"phase3_shadow_multisurface_cumulative_gas_exchange_kj": float(
				canonical_multisurface_cumulative.get("gas_exchange_kj", 0.0)
			),
			"phase3_shadow_multisurface_cumulative_requested_fire_radiation_kj": \
					float(canonical_multisurface_cumulative.get(
						"requested_fire_radiation_kj", 0.0
					)),
			"phase3_shadow_multisurface_cumulative_pre_atomic_fire_radiation_kj": \
					float(canonical_multisurface_cumulative.get(
						"pre_atomic_accepted_fire_radiation_kj", 0.0
					)),
			"phase3_shadow_multisurface_cumulative_decision_rejected_radiation_kj": \
					float(canonical_multisurface_cumulative.get(
						"decision_rejected_fire_radiation_kj", 0.0
					)),
			"phase3_shadow_multisurface_cumulative_atomic_rejected_radiation_kj": \
					float(canonical_multisurface_cumulative.get(
						"atomic_rejected_fire_radiation_kj", 0.0
					)),
			"phase3_shadow_multisurface_cumulative_fire_radiation_kj": float(
				canonical_multisurface_cumulative.get("fire_radiation_kj", 0.0)
			),
			"phase3_shadow_multisurface_cumulative_migration_energy_kj": float(
				canonical_multisurface_cumulative.get("migration_energy_kj", 0.0)
			),
			"phase3_shadow_multisurface_cumulative_exterior_removed_kj": float(
				canonical_multisurface_cumulative.get(
					"exterior_removed_kj", 0.0
				)
			),
			"phase3_shadow_multisurface_cumulative_energy_residual_kj": float(
				canonical_multisurface_cumulative.get(
					"combined_energy_residual_kj", 0.0
				)
			),
			"phase3_shadow_multisurface_cumulative_solver_residual_kj": float(
				canonical_multisurface_cumulative.get("solver_residual_kj", 0.0)
			),
			"phase3_shadow_wall_energy_pre_kj": float(
				canonical_wall_ambient.get("wall_energy_pre_kj", 0.0)
			),
			"phase3_shadow_wall_energy_post_kj": float(
				canonical_wall_ambient.get("wall_energy_post_kj", 0.0)
			),
			"phase3_shadow_wall_temp_pre_c": float(
				canonical_wall_ambient.get("wall_temp_pre_c", reference_temp_c)
			),
			"phase3_shadow_wall_temp_post_c": float(
				canonical_wall_ambient.get("wall_temp_post_c", reference_temp_c)
			),
			"phase3_shadow_wall_decay_kj": float(
				canonical_wall_ambient.get("wall_decay_requested_kj", 0.0)
			),
			"phase3_shadow_wall_upper_requested_kj": float(
				canonical_wall_ambient.get("upper_wall_requested_kj", 0.0)
			),
			"phase3_shadow_wall_lower_requested_kj": float(
				canonical_wall_ambient.get("lower_wall_requested_kj", 0.0)
			),
			"phase3_shadow_wall_upper_accepted_kj": float(
				canonical_wall_ambient.get("accepted_upper_wall_kj", 0.0)
			),
			"phase3_shadow_wall_lower_accepted_kj": float(
				canonical_wall_ambient.get("accepted_lower_wall_kj", 0.0)
			),
			"phase3_shadow_wall_upper_convective_requested_kj": float(
				canonical_wall_ambient.get("upper_wall_convective_requested_kj", 0.0)
			),
			"phase3_shadow_wall_lower_convective_requested_kj": float(
				canonical_wall_ambient.get("lower_wall_convective_requested_kj", 0.0)
			),
			"phase3_shadow_wall_upper_radiative_requested_kj": float(
				canonical_wall_ambient.get("upper_wall_radiative_requested_kj", 0.0)
			),
			"phase3_shadow_wall_upper_ambient_requested_kj": float(
				canonical_wall_ambient.get("upper_ambient_requested_kj", 0.0)
			),
			"phase3_shadow_wall_lower_ambient_requested_kj": float(
				canonical_wall_ambient.get("lower_ambient_requested_kj", 0.0)
			),
			"phase3_shadow_wall_upper_ambient_accepted_kj": float(
				canonical_wall_ambient.get("accepted_upper_ambient_kj", 0.0)
			),
			"phase3_shadow_wall_lower_ambient_accepted_kj": float(
				canonical_wall_ambient.get("accepted_lower_ambient_kj", 0.0)
			),
			"phase3_shadow_wall_accepted_fraction": float(
				canonical_wall_ambient.get("accepted_fraction", 1.0)
			),
			"phase3_shadow_wall_equilibrium_temp_c": float(
				canonical_wall_ambient.get("equilibrium_temp_c", reference_temp_c)
			),
			"phase3_shadow_wall_cumulative_absorbed_kj": float(
				canonical_wall_ambient.get("cumulative_wall_absorbed_kj", 0.0)
			),
			"phase3_shadow_wall_cumulative_emitted_kj": float(
				canonical_wall_ambient.get("cumulative_wall_emitted_kj", 0.0)
			),
			"phase3_shadow_wall_cumulative_ambient_removed_kj": float(
				canonical_wall_ambient.get("cumulative_ambient_removed_kj", 0.0)
			),
			"phase3_shadow_wall_gas_residual_kj": float(
				canonical_wall_ambient.get("gas_wall_energy_residual_kj", 0.0)
			),
			"phase3_shadow_wall_boundary_residual_kj": float(
				canonical_wall_ambient.get("total_boundary_energy_residual_kj", 0.0)
			),
			"phase3_shadow_wall_clamp_kj": float(
				canonical_wall_ambient.get("wall_clamp_kj", 0.0)
			),
			"phase3_shadow_wall_legacy_requested_kj": \
				float(canonical_wall_ambient.get("legacy_upper_radiative_requested_kj", 0.0)) \
				+ float(canonical_wall_ambient.get("legacy_upper_ambient_requested_kj", 0.0)) \
				+ float(canonical_wall_ambient.get("legacy_wall_absorption_requested_kj", 0.0)) \
				+ float(canonical_wall_ambient.get("legacy_lower_decay_requested_kj", 0.0)) \
				+ float(canonical_wall_ambient.get("legacy_lower_fresh_requested_kj", 0.0)) \
				- float(canonical_wall_ambient.get("legacy_wall_emission_requested_kj", 0.0)),
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
		var fire_products_room_result: Dictionary = _results[room_key]
		for product_field in FIRE_PRODUCT_SCALAR_FIELDS:
			fire_products_room_result[
				"phase3_shadow_fire_products_" + product_field
			] = float(canonical_combustion.get(
				"canonical_fire_products_" + product_field, 0.0
			))
		for acceptance_name in ["requested", "accepted"]:
			var product_species: Dictionary = canonical_combustion.get(
				"canonical_fire_products_%s_species_kg" % acceptance_name, {}
			)
			for species_name in PARCEL_SPECIES:
				fire_products_room_result[
					"phase3_shadow_fire_products_%s_%s_kg" % [
						acceptance_name, species_name
					]
				] = float(product_species.get(species_name, 0.0))
		fire_products_room_result[
			"phase3_shadow_fire_products_routing_active_flag"
		] = float(canonical_combustion.get(
			"canonical_fire_products_routing_active_flag", 0.0
		))
		fire_products_room_result[
			"phase3_shadow_fire_products_routing_atomic_fraction"
		] = float(canonical_combustion.get("atomic_accepted_fraction", 1.0))
		fire_products_room_result[
			"phase3_shadow_fire_products_routing_effective_fraction"
		] = float(canonical_combustion.get("effective_fraction", 0.0))
		fire_products_room_result[
			"phase3_shadow_fire_products_routing_committed_fuel_MJ"
		] = float(canonical_combustion.get(
			"canonical_fire_products_committed_fuel_MJ", 0.0
		))
		fire_products_room_result[
			"phase3_shadow_fire_products_routing_fuel_residual_MJ"
		] = float(canonical_combustion.get(
			"canonical_fire_products_fuel_route_residual_MJ", 0.0
		))
		fire_products_room_result[
			"phase3_shadow_fire_products_routing_o2_residual_kg"
		] = float(canonical_combustion.get("o2_residual_kg", 0.0))
		fire_products_room_result[
			"phase3_shadow_fire_products_routing_species_residual_kg"
		] = float(canonical_combustion.get("species_residual_kg", 0.0))
		fire_products_room_result[
			"phase3_shadow_fire_products_routing_convective_residual_kj"
		] = float(canonical_combustion.get("energy_residual_kj", 0.0))
		fire_products_room_result[
			"phase3_shadow_fire_products_routing_radiative_residual_kj"
		] = float(canonical_combustion.get(
			"radiative_route_residual_kj", 0.0
		))
		fire_products_room_result[
			"phase3_shadow_fire_products_routing_total_energy_residual_kj"
		] = float(canonical_combustion.get(
			"canonical_fire_products_total_energy_route_residual_kj", 0.0
		))
		fire_products_room_result[
			"phase3_shadow_fire_products_routing_coupled_plume_qc_kw"
		] = float(canonical_combustion.get(
			"canonical_fire_products_coupled_plume_qc_kw", 0.0
		))
		fire_products_room_result[
			"phase3_shadow_fire_products_routing_plume_qc_residual_kw"
		] = float(canonical_combustion.get(
			"canonical_fire_products_plume_qc_residual_kw", 0.0
		))
		for object_sync_field in [
			"active_flag", "supported_flag", "rejection_mask", "object_count",
			"identity_signature", "eligible_count", "pre_fuel_MJ",
			"proposed_fuel_MJ",
			"committed_fuel_MJ", "requested_debit_MJ",
			"allocated_debit_MJ", "committed_debit_MJ",
			"allocation_residual_MJ", "atomic_residual_MJ",
			"aggregate_residual_MJ", "exhausted_count",
			"minimum_remaining_MJ", "live_fuel_MJ", "live_delta_MJ",
			"seed_residual_MJ"
		]:
			fire_products_room_result[
				"phase3_shadow_fuel_object_sync_" + object_sync_field
			] = float(canonical_combustion.get(
				"canonical_fuel_object_sync_" + object_sync_field, 0.0
			))
		_results[room_key] = fire_products_room_result
		var multisurface_room_result: Dictionary = _results[room_key]
		for surface_name in CANONICAL_SURFACE_NAMES:
			var surface: Dictionary = canonical_multisurface_surfaces.get(
				surface_name, {}
			)
			var surface_nodes: Array = surface.get("nodes_c", [])
			var surface_cumulative: Dictionary = \
					canonical_multisurface_cumulative_surfaces.get(
						surface_name, {}
					)
			var surface_prefix: String = (
				"phase3_shadow_multisurface_" + surface_name
			)
			multisurface_room_result[surface_prefix + "_area_m2"] = float(
				surface.get("area_m2", 0.0)
			)
			multisurface_room_result[surface_prefix + "_energy_kj"] = (
				Phase3SurfaceEnergySolverScript.stored_energy_kj(surface)
				if not surface.is_empty() else 0.0
			)
			multisurface_room_result[surface_prefix + "_temp_inner_c"] = (
				float(surface_nodes[0]) if surface_nodes.size() >= 1
				else reference_temp_c
			)
			multisurface_room_result[surface_prefix + "_temp_middle_c"] = (
				float(surface_nodes[2]) if surface_nodes.size() >= 3
				else reference_temp_c
			)
			multisurface_room_result[surface_prefix + "_temp_outer_c"] = (
				float(surface_nodes[4]) if surface_nodes.size() >= 5
				else reference_temp_c
			)
			multisurface_room_result[
				surface_prefix + "_cumulative_gas_exchange_kj"
			] = float(surface_cumulative.get("gas_exchange_kj", 0.0))
			multisurface_room_result[
				surface_prefix + "_cumulative_fire_radiation_kj"
			] = float(surface_cumulative.get("fire_radiation_kj", 0.0))
			multisurface_room_result[
				surface_prefix + "_cumulative_exterior_removed_kj"
			] = float(surface_cumulative.get("exterior_removed_kj", 0.0))
		_results[room_key] = multisurface_room_result
	if enthalpy_residence_diagnostics_enabled:
		var building_residual_kj: float = 0.0
		for room_key in shadow.keys():
			if not _results.has(room_key):
				continue
			var ledger_result: Dictionary = _enthalpy_residence_result(
				String(room_key), shadow[room_key]
			)
			for ledger_key in ledger_result.keys():
				_results[room_key][ledger_key] = ledger_result[ledger_key]
			building_residual_kj += float(
				ledger_result.get("phase3_shadow_enthalpy_room_residual_kj", 0.0)
			)
		for room_key in _results.keys():
			_results[room_key]["phase3_shadow_enthalpy_building_residual_kj"] = \
					building_residual_kj
	if mass_residence_diagnostics_enabled:
		var building_mass_residual_kg: float = 0.0
		for room_key in shadow.keys():
			if not _results.has(room_key):
				continue
			var mass_ledger_result: Dictionary = _mass_residence_result(
				String(room_key), shadow[room_key]
			)
			for ledger_key in mass_ledger_result.keys():
				_results[room_key][ledger_key] = mass_ledger_result[ledger_key]
			building_mass_residual_kg += float(
				mass_ledger_result.get(
					"phase3_shadow_mass_residence_room_residual_kg", 0.0
				)
			)
		for room_key in _results.keys():
			_results[room_key][
				"phase3_shadow_mass_residence_building_residual_kg"
			] = building_mass_residual_kg
	if _persistence_enabled_step:
		_persistent_zone_state = shadow.duplicate(true)
		_persistent_step_index = persistence_step_index
		for combustion_room_key in _canonical_combustion_by_room.keys():
			var combustion_record: Dictionary = _canonical_combustion_by_room[
				combustion_room_key
			]
			_persistent_combustion_state[combustion_room_key] = combustion_record.get(
				"committed_fire_state", {}
			).duplicate(true)


func _commit_canonical_multisurface_records() -> void:
	if not canonical_multisurface_shadow_enabled:
		return
	var room_keys: Dictionary = {}
	for room_key in _canonical_combustion_by_room.keys():
		room_keys[room_key] = true
	for room_key in _canonical_multisurface_exchange_by_room.keys():
		room_keys[room_key] = true
	for room_key in room_keys.keys():
		if not _canonical_surface_state_by_room.has(room_key):
			continue
		commit_canonical_multisurface_combustion_radiation(int(room_key))


func _commit_canonical_wall_ambient_records(reference_temp_c: float) -> void:
	for room_key in _canonical_wall_ambient_by_room.keys():
		var record: Dictionary = _canonical_wall_ambient_by_room[room_key].duplicate(true)
		var capacity_kj_k: float = maxf(
			0.1, float(record.get("wall_capacity_kj_k", 0.1))
		)
		var wall_energy_pre_kj: float = maxf(
			0.0, float(record.get("wall_energy_pre_kj", 0.0))
		)
		var wall_decay_kj: float = minf(
			wall_energy_pre_kj,
			maxf(0.0, float(record.get("wall_decay_requested_kj", 0.0)))
		)
		var accepted_upper_wall_kj: float = float(
			record.get("accepted_upper_wall_kj", 0.0)
		)
		var accepted_lower_wall_kj: float = float(
			record.get("accepted_lower_wall_kj", 0.0)
		)
		var wall_exchange_kj: float = accepted_upper_wall_kj + accepted_lower_wall_kj
		var wall_energy_post_raw_kj: float = wall_energy_pre_kj - wall_decay_kj \
				+ wall_exchange_kj
		var wall_energy_post_kj: float = maxf(0.0, wall_energy_post_raw_kj)
		var wall_clamp_kj: float = wall_energy_post_kj - wall_energy_post_raw_kj
		var accepted_upper_ambient_kj: float = maxf(
			0.0, float(record.get("accepted_upper_ambient_kj", 0.0))
		)
		var accepted_lower_ambient_kj: float = maxf(
			0.0, float(record.get("accepted_lower_ambient_kj", 0.0))
		)
		var gas_wall_delta_kj: float = -wall_exchange_kj
		var wall_delta_kj: float = wall_energy_post_kj - wall_energy_pre_kj
		var ambient_removed_kj: float = wall_decay_kj \
				+ accepted_upper_ambient_kj + accepted_lower_ambient_kj
		var gas_total_delta_kj: float = gas_wall_delta_kj \
				- accepted_upper_ambient_kj - accepted_lower_ambient_kj
		record["wall_energy_post_kj"] = wall_energy_post_kj
		record["wall_temp_post_c"] = reference_temp_c \
				+ wall_energy_post_kj / capacity_kj_k
		record["wall_clamp_kj"] = wall_clamp_kj
		record["gas_wall_energy_residual_kj"] = gas_wall_delta_kj \
				+ wall_delta_kj + wall_decay_kj
		record["total_boundary_energy_residual_kj"] = gas_total_delta_kj \
				+ wall_delta_kj + ambient_removed_kj
		var cumulative: Dictionary = _canonical_wall_ambient_cumulative_by_room.get(
			room_key,
			{
				"wall_absorbed_kj": 0.0,
				"wall_emitted_kj": 0.0,
				"ambient_removed_kj": 0.0,
			}
		).duplicate(true)
		for accepted_wall_kj in [accepted_upper_wall_kj, accepted_lower_wall_kj]:
			if accepted_wall_kj >= 0.0:
				cumulative["wall_absorbed_kj"] = float(
					cumulative.get("wall_absorbed_kj", 0.0)
				) + accepted_wall_kj
			else:
				cumulative["wall_emitted_kj"] = float(
					cumulative.get("wall_emitted_kj", 0.0)
				) - accepted_wall_kj
		cumulative["ambient_removed_kj"] = float(
			cumulative.get("ambient_removed_kj", 0.0)
		) + ambient_removed_kj
		_canonical_wall_ambient_cumulative_by_room[room_key] = cumulative
		record["cumulative_wall_absorbed_kj"] = float(
			cumulative.get("wall_absorbed_kj", 0.0)
		)
		record["cumulative_wall_emitted_kj"] = float(
			cumulative.get("wall_emitted_kj", 0.0)
		)
		record["cumulative_ambient_removed_kj"] = float(
			cumulative.get("ambient_removed_kj", 0.0)
		)
		_canonical_wall_state_by_room[room_key] = {
			"wall_energy_kj": wall_energy_post_kj,
			"wall_capacity_kj_k": capacity_kj_k,
			"reference_temp_c": reference_temp_c,
		}
		_canonical_wall_ambient_by_room[room_key] = record


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
		_record_enthalpy_residence_route(shadow, route, accepted_fraction)
		_record_mass_residence_route(route, accepted_fraction)
		_record_connection_residence_route(route, accepted_fraction)
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
	if result_kind == "canonical_multisurface_exchange":
		var exchange_room_key: String = str(int(
			metadata.get("room_id", EXTERIOR_ID)
		))
		if not _canonical_multisurface_exchange_by_room.has(exchange_room_key):
			return
		var exchange_record: Dictionary = _canonical_multisurface_exchange_by_room[
			exchange_room_key
		].duplicate(true)
		var exchange_fraction: float = clampf(accepted_fraction, 0.0, 1.0)
		exchange_record["accepted_fraction"] = exchange_fraction
		exchange_record["accepted_upper_exchange_kj"] = float(
			exchange_record.get("upper_exchange_requested_kj", 0.0)
		) * exchange_fraction
		exchange_record["accepted_lower_exchange_kj"] = float(
			exchange_record.get("lower_exchange_requested_kj", 0.0)
		) * exchange_fraction
		exchange_record["accepted_exterior_removed_kj"] = float(
			exchange_record.get("exterior_removed_requested_kj", 0.0)
		) * exchange_fraction
		_canonical_multisurface_exchange_by_room[
			exchange_room_key
		] = exchange_record
		return
	if result_kind == "canonical_combustion":
		var combustion_room_key: String = str(int(metadata.get("room_id", EXTERIOR_ID)))
		if not _canonical_combustion_by_room.has(combustion_room_key):
			return
		var combustion_record: Dictionary = _canonical_combustion_by_room[
			combustion_room_key
		].duplicate(true)
		var atomic_fraction: float = clampf(accepted_fraction, 0.0, 1.0)
		combustion_record["atomic_accepted_fraction"] = atomic_fraction
		combustion_record["atomic_accepted_radiative_energy_kj"] = maxf(
			0.0, float(
				combustion_record.get("accepted_radiative_energy_kj", 0.0)
			)
		) * atomic_fraction
		combustion_record["radiative_route_residual_kj"] = float(
			combustion_record.get("atomic_accepted_radiative_energy_kj", 0.0)
		)
		combustion_record["effective_fraction"] = clampf(
			float(combustion_record.get("decision_fraction", 0.0)) * atomic_fraction,
			0.0,
			1.0
		)
		var routed_o2_kg: float = 0.0
		var routed_energy_kj: float = 0.0
		var routed_species_kg: float = 0.0
		for raw_route in bundle.get("routes", []):
			var route: Dictionary = raw_route
			var route_cause: String = String(route.get("cause", ""))
			if route_cause == "canonical_combustion_o2_sink":
				routed_o2_kg += float(route.get("o2_kg", 0.0)) * atomic_fraction
			elif route_cause == "canonical_combustion_convective_heat":
				routed_energy_kj += float(
					route.get("sensible_enthalpy_kj", 0.0)
				) * atomic_fraction
			elif route_cause == "canonical_combustion_species_source":
				routed_species_kg += _sum_parcel_species(
					route.get("species_kg", {})
				) * atomic_fraction
		combustion_record["routed_o2_kg"] = routed_o2_kg
		combustion_record["routed_convective_energy_kj"] = routed_energy_kj
		combustion_record["routed_species_kg"] = routed_species_kg
		combustion_record["o2_residual_kg"] = float(
			combustion_record.get("accepted_o2_kg", 0.0)
		) * atomic_fraction - routed_o2_kg
		combustion_record["energy_residual_kj"] = float(
			combustion_record.get("accepted_convective_energy_kj", 0.0)
		) * atomic_fraction - routed_energy_kj
		combustion_record["species_residual_kg"] = _sum_parcel_species(
			combustion_record.get("accepted_species_kg", {})
		) * atomic_fraction - routed_species_kg
		combustion_record["committed_fire_state"] = _interpolate_combustion_state(
			combustion_record.get("fire_state_before", {}),
			combustion_record.get("fire_state_proposed", {}),
			atomic_fraction
		)
		var state_before: Dictionary = combustion_record.get(
			"fire_state_before", {}
		)
		var committed_state: Dictionary = combustion_record.get(
			"committed_fire_state", {}
		)
		var committed_fuel_MJ: float = maxf(
			0.0,
			float(state_before.get("remaining_fuel_MJ", 0.0))
					- float(committed_state.get("remaining_fuel_MJ", 0.0))
		)
		combustion_record["canonical_fire_products_committed_fuel_MJ"] = \
				committed_fuel_MJ
		combustion_record["canonical_fire_products_fuel_route_residual_MJ"] = \
				float(combustion_record.get("accepted_fuel_MJ", 0.0)) \
				* atomic_fraction - committed_fuel_MJ
		if float(combustion_record.get(
			"canonical_fuel_object_sync_active_flag", 0.0
		)) > 0.5:
			var pre_object_fuel_MJ: float = _sum_fuel_object_ledger(
				state_before.get("fuel_object_ledger", [])
			)
			var proposed_object_fuel_MJ: float = _sum_fuel_object_ledger(
				combustion_record.get(
					"fire_state_proposed", {}
				).get("fuel_object_ledger", [])
			)
			var committed_object_fuel_MJ: float = _sum_fuel_object_ledger(
				committed_state.get("fuel_object_ledger", [])
			)
			combustion_record["canonical_fuel_object_sync_pre_fuel_MJ"] = \
					pre_object_fuel_MJ
			combustion_record["canonical_fuel_object_sync_proposed_fuel_MJ"] = \
					proposed_object_fuel_MJ
			combustion_record["canonical_fuel_object_sync_committed_fuel_MJ"] = \
					committed_object_fuel_MJ
			combustion_record[
				"canonical_fuel_object_sync_committed_debit_MJ"
			] = pre_object_fuel_MJ - committed_object_fuel_MJ
			combustion_record[
				"canonical_fuel_object_sync_atomic_residual_MJ"
			] = float(combustion_record.get("accepted_fuel_MJ", 0.0)) \
					* atomic_fraction \
					- (pre_object_fuel_MJ - committed_object_fuel_MJ)
			combustion_record[
				"canonical_fuel_object_sync_aggregate_residual_MJ"
			] = float(committed_state.get("remaining_fuel_MJ", 0.0)) \
					- committed_object_fuel_MJ
		_canonical_combustion_by_room[combustion_room_key] = combustion_record
		return
	if result_kind == "canonical_interior_opening_network":
		var interior_fraction: float = clampf(accepted_fraction, 0.0, 1.0)
		var room_totals: Dictionary = metadata.get("room_totals", {})
		var pressure_room_totals: Dictionary = metadata.get("pressure_room_totals", {})
		var pressure_pre_by_room: Dictionary = metadata.get("pressure_pre_by_room", {})
		var pressure_base_delta_by_room: Dictionary = metadata.get(
			"pressure_base_delta_by_room", {}
		)
		var pressure_limited_delta_by_room: Dictionary = metadata.get(
			"pressure_limited_delta_by_room", {}
		)
		for raw_room_key in room_totals.keys():
			var room_key: String = String(raw_room_key)
			var totals: Dictionary = room_totals[raw_room_key]
			var record: Dictionary = _canonical_interior_opening_by_room.get(
				room_key, _new_canonical_interior_opening_record()
			).duplicate(true)
			record["accepted_fraction"] = interior_fraction
			for direction in ["out", "in"]:
				for quantity in ["gas_kg", "energy_kj", "o2_kg", "species_kg"]:
					var requested_key: String = "requested_%s_%s" % [direction, quantity]
					var accepted_key: String = "accepted_%s_%s" % [direction, quantity]
					record[accepted_key] = float(record.get(requested_key, 0.0)) \
							* interior_fraction
			record["net_mass_kg"] = float(record.get("accepted_in_gas_kg", 0.0)) \
					- float(record.get("accepted_out_gas_kg", 0.0))
			record["net_energy_kj"] = float(record.get("accepted_in_energy_kj", 0.0)) \
					- float(record.get("accepted_out_energy_kj", 0.0))
			record["net_o2_kg"] = float(record.get("accepted_in_o2_kg", 0.0)) \
					- float(record.get("accepted_out_o2_kg", 0.0))
			record["net_species_kg"] = float(record.get("accepted_in_species_kg", 0.0)) \
					- float(record.get("accepted_out_species_kg", 0.0))
			record["mass_residual_kg"] = float(metadata.get("mass_residual_kg", 0.0)) \
					* interior_fraction
			record["energy_residual_kj"] = float(
				metadata.get("energy_residual_kj", 0.0)
			) * interior_fraction
			record["o2_residual_kg"] = float(metadata.get("o2_residual_kg", 0.0)) \
					* interior_fraction
			record["species_residual_kg"] = float(
				metadata.get("species_residual_kg", 0.0)
			) * interior_fraction
			if float(record.get("pressure_enabled_flag", 0.0)) > 0.0:
				var pressure_totals: Dictionary = pressure_room_totals.get(room_key, {})
				for direction in ["out", "in"]:
					record["pressure_accepted_%s_gas_kg" % direction] = float(
						pressure_totals.get("%s_gas_kg" % direction, 0.0)
					) * interior_fraction
				record["pressure_net_mass_kg"] = float(
					record.get("pressure_accepted_in_gas_kg", 0.0)
				) - float(record.get("pressure_accepted_out_gas_kg", 0.0))
				record["pressure_predicted_post_pa"] = float(
					pressure_pre_by_room.get(room_key, record.get("pressure_pre_pa", 0.0))
				) + (
					float(pressure_base_delta_by_room.get(room_key, 0.0))
					+ float(pressure_limited_delta_by_room.get(room_key, 0.0))
				) * interior_fraction
				for residual_key in [
					"pressure_mass_residual_kg",
					"pressure_energy_residual_kj",
					"pressure_o2_residual_kg",
					"pressure_species_residual_kg",
				]:
					record[residual_key] = float(record.get(residual_key, 0.0)) \
							* interior_fraction
			_canonical_interior_opening_by_room[room_key] = record
		return
	if result_kind == "canonical_exterior_counterflow":
		var counterflow_room_key: String = str(int(metadata.get("room_id", EXTERIOR_ID)))
		var counterflow_record: Dictionary = _canonical_exterior_counterflow_by_room.get(
			counterflow_room_key, _new_canonical_exterior_counterflow_record()
		).duplicate(true)
		var counterflow_fraction: float = clampf(accepted_fraction, 0.0, 1.0)
		var exchange_kg: float = maxf(0.0, float(metadata.get("exchange_kg", 0.0)))
		var accepted_exchange_kg: float = exchange_kg * counterflow_fraction
		counterflow_record["accepted_fraction"] = minf(
			float(counterflow_record.get("accepted_fraction", 1.0)), counterflow_fraction
		)
		counterflow_record["accepted_exchange_kg"] = float(
			counterflow_record.get("accepted_exchange_kg", 0.0)
		) + accepted_exchange_kg
		counterflow_record["rejected_exchange_kg"] = float(
			counterflow_record.get("rejected_exchange_kg", 0.0)
		) + exchange_kg * (1.0 - counterflow_fraction)
		for quantity_name in ["outgoing_energy_kj", "outgoing_o2_kg", "incoming_o2_kg", "outgoing_species_kg"]:
			var accepted_key: String = "accepted_" + quantity_name
			var rejected_key: String = "rejected_" + quantity_name
			var requested_value: float = maxf(0.0, float(metadata.get(quantity_name, 0.0)))
			counterflow_record[accepted_key] = float(
				counterflow_record.get(accepted_key, 0.0)
			) + requested_value * counterflow_fraction
			counterflow_record[rejected_key] = float(
				counterflow_record.get(rejected_key, 0.0)
			) + requested_value * (1.0 - counterflow_fraction)
		counterflow_record["mass_residual_kg"] = 0.0
		counterflow_record["energy_residual_kj"] = float(
			counterflow_record.get("requested_outgoing_energy_kj", 0.0)
		) - float(counterflow_record.get("accepted_outgoing_energy_kj", 0.0)) \
				- float(counterflow_record.get("rejected_outgoing_energy_kj", 0.0))
		counterflow_record["o2_residual_kg"] = float(
			counterflow_record.get("requested_outgoing_o2_kg", 0.0)
		) + float(counterflow_record.get("requested_incoming_o2_kg", 0.0)) \
				- float(counterflow_record.get("accepted_outgoing_o2_kg", 0.0)) \
				- float(counterflow_record.get("accepted_incoming_o2_kg", 0.0)) \
				- float(counterflow_record.get("rejected_outgoing_o2_kg", 0.0)) \
				- float(counterflow_record.get("rejected_incoming_o2_kg", 0.0))
		counterflow_record["species_residual_kg"] = float(
			counterflow_record.get("requested_outgoing_species_kg", 0.0)
		) - float(counterflow_record.get("accepted_outgoing_species_kg", 0.0)) \
				- float(counterflow_record.get("rejected_outgoing_species_kg", 0.0))
		_canonical_exterior_counterflow_cumulative_kg[counterflow_room_key] = float(
			_canonical_exterior_counterflow_cumulative_kg.get(counterflow_room_key, 0.0)
		) + accepted_exchange_kg
		counterflow_record["cumulative_exchange_kg"] = float(
			_canonical_exterior_counterflow_cumulative_kg[counterflow_room_key]
		)
		_canonical_exterior_counterflow_by_room[counterflow_room_key] = counterflow_record
		return
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
		record["pressure_predicted_post_pa"] = float(
			record.get("pressure_pre_pa", 0.0)
		) + float(record.get("pressure_limited_delta_pa", 0.0)) * accepted
		if float(record.get("degenerate_lower_reseed_flag", 0.0)) > 0.5:
			record["degenerate_lower_reseed_mass_kg"] = float(
				record.get("accepted_gas_kg", 0.0)
			)
			var history: Dictionary = _persistent_lower_reseed_by_room.get(
				room_key,
				{"count": 0.0, "mass_kg": 0.0, "first_step_index": 0.0}
			).duplicate(true)
			if float(history.get("count", 0.0)) <= 0.0:
				history["first_step_index"] = float(_persistent_step_index + 1)
			history["count"] = float(history.get("count", 0.0)) + 1.0
			history["mass_kg"] = float(history.get("mass_kg", 0.0)) \
					+ float(record.get("degenerate_lower_reseed_mass_kg", 0.0))
			_persistent_lower_reseed_by_room[room_key] = history
		_canonical_exterior_boundary_by_room[room_key] = record
		return
	if result_kind == "canonical_interzone_heat":
		var interzone_room_key: String = str(int(metadata.get("room_id", EXTERIOR_ID)))
		var interzone_record: Dictionary = _canonical_interzone_heat_by_room.get(
			interzone_room_key, {}
		).duplicate(true)
		if interzone_record.is_empty():
			return
		var requested_interzone_kj: float = maxf(
			0.0, float(metadata.get("requested_energy_kj", 0.0))
		)
		var accepted_interzone_kj: float = requested_interzone_kj \
				* clampf(accepted_fraction, 0.0, 1.0)
		var rejected_interzone_kj: float = requested_interzone_kj \
				- accepted_interzone_kj
		interzone_record["accepted_kj"] = accepted_interzone_kj
		interzone_record["rejected_kj"] = rejected_interzone_kj
		interzone_record["energy_residual_kj"] = requested_interzone_kj \
				- accepted_interzone_kj - rejected_interzone_kj
		_canonical_interzone_heat_by_room[interzone_room_key] = interzone_record
		_canonical_interzone_heat_cumulative_kj[interzone_room_key] = float(
			_canonical_interzone_heat_cumulative_kj.get(interzone_room_key, 0.0)
		) + accepted_interzone_kj
		return
	if result_kind == "canonical_wall_ambient":
		var wall_room_key: String = str(int(metadata.get("room_id", EXTERIOR_ID)))
		var wall_record: Dictionary = _canonical_wall_ambient_by_room.get(
			wall_room_key, {}
		).duplicate(true)
		if wall_record.is_empty():
			return
		var accepted_wall_fraction: float = clampf(accepted_fraction, 0.0, 1.0)
		wall_record["accepted_fraction"] = accepted_wall_fraction
		wall_record["accepted_upper_wall_kj"] = float(
			metadata.get("upper_wall_signed_kj", 0.0)
		) * accepted_wall_fraction
		wall_record["accepted_lower_wall_kj"] = float(
			metadata.get("lower_wall_signed_kj", 0.0)
		) * accepted_wall_fraction
		wall_record["accepted_upper_ambient_kj"] = maxf(
			0.0, float(metadata.get("upper_ambient_kj", 0.0))
		) * accepted_wall_fraction
		wall_record["accepted_lower_ambient_kj"] = maxf(
			0.0, float(metadata.get("lower_ambient_kj", 0.0))
		) * accepted_wall_fraction
		_canonical_wall_ambient_by_room[wall_room_key] = wall_record
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


func _interpolate_combustion_state(
		before: Dictionary,
		proposed: Dictionary,
		fraction: float
	) -> Dictionary:
	var accepted: float = clampf(fraction, 0.0, 1.0)
	var result: Dictionary = before.duplicate(true)
	for key in [
		"hrr_kw", "hrr_target_kw", "o2_hrr_factor", "remaining_fuel_MJ",
		"retained_unburned_MJ", "fire_time_s", "fire_dormant_time_s",
		"proposal_age_s", "proposal_hrr_kw", "proposal_target_kw",
		"proposal_remaining_fuel_MJ"
	]:
		result[key] = lerpf(
			float(before.get(key, proposed.get(key, 0.0))),
			float(proposed.get(key, before.get(key, 0.0))),
			accepted
		)
	for key in ["active_flag", "extinguished_flag"]:
		result[key] = proposed.get(key, before.get(key, false)) \
				if accepted > 0.0 else before.get(key, false)
	if bool(proposed.get("fuel_object_sync_active_flag", false)) \
			and proposed.has("fuel_object_ledger"):
		var committed_ledger: Array = _interpolate_fuel_object_ledger(
			before.get("fuel_object_ledger", []),
			proposed.get("fuel_object_ledger", []),
			accepted
		)
		result["fuel_object_ledger"] = committed_ledger
		var committed_object_fuel_MJ: float = 0.0
		for raw_entry in committed_ledger:
			committed_object_fuel_MJ += maxf(
				0.0, float(Dictionary(raw_entry).get("remaining_fuel_MJ", 0.0))
			)
		result["remaining_fuel_MJ"] = committed_object_fuel_MJ
		result["proposal_remaining_fuel_MJ"] = committed_object_fuel_MJ
	return result


func _interpolate_fuel_object_ledger(
		before_ledger: Array,
		proposed_ledger: Array,
		fraction: float
	) -> Array:
	var proposed_by_id: Dictionary = {}
	for raw_entry in proposed_ledger:
		if raw_entry is Dictionary:
			var entry: Dictionary = Dictionary(raw_entry)
			proposed_by_id[String(entry.get("id", ""))] = entry
	var result: Array = []
	var accepted: float = clampf(fraction, 0.0, 1.0)
	for raw_before in before_ledger:
		if not raw_before is Dictionary:
			continue
		var before_entry: Dictionary = Dictionary(raw_before)
		var object_id: String = String(before_entry.get("id", ""))
		var proposed_entry: Dictionary = proposed_by_id.get(
			object_id, before_entry
		)
		var committed: Dictionary = proposed_entry.duplicate(true)
		committed["id"] = object_id
		committed["remaining_fuel_MJ"] = lerpf(
			maxf(0.0, float(before_entry.get("remaining_fuel_MJ", 0.0))),
			maxf(0.0, float(proposed_entry.get("remaining_fuel_MJ", 0.0))),
			accepted
		)
		committed["allocated_debit_MJ"] = maxf(
			0.0,
			float(before_entry.get("remaining_fuel_MJ", 0.0))
					- float(committed["remaining_fuel_MJ"])
		)
		result.append(committed)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.get("id", "")) < String(b.get("id", ""))
	)
	return result


func _sum_fuel_object_ledger(ledger: Array) -> float:
	var total_MJ: float = 0.0
	for raw_entry in ledger:
		if raw_entry is Dictionary:
			total_MJ += maxf(
				0.0, float(Dictionary(raw_entry).get("remaining_fuel_MJ", 0.0))
			)
	return total_MJ


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
	var enthalpy_route_recorded: bool = false
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
		_record_enthalpy_residence_route(shadow, request, accepted_fraction, true)
		enthalpy_route_recorded = true
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
	if not enthalpy_route_recorded:
		_record_enthalpy_residence_route(shadow, request, accepted_fraction, true)
	_record_mass_residence_route(request, accepted_fraction, true)
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


func _state_o2(state: Dictionary) -> float:
	return float(state.get("upper_o2_kg", 0.0)) + float(state.get("lower_o2_kg", 0.0))


func _state_species(state: Dictionary) -> float:
	return _sum_parcel_species(state.get("upper_species_kg", {})) \
			+ _sum_parcel_species(state.get("lower_species_kg", {}))


func _zone_o2_fraction(state: Dictionary, zone: String) -> float:
	var gas_kg: float = maxf(0.0, float(state.get(zone + "_gas_kg", 0.0)))
	if gas_kg <= THERMO_MASS_EPS_KG:
		return 0.0
	return clampf(float(state.get(zone + "_o2_kg", 0.0)) / gas_kg, 0.0, 1.0)


func _zero_state_delta_summary() -> Dictionary:
	return {"mass_kg": 0.0, "energy_kj": 0.0, "o2_kg": 0.0, "species_kg": 0.0}


func _state_delta_summary(candidate: Dictionary, reference: Dictionary) -> Dictionary:
	return {
		"mass_kg": _state_mass(candidate) - _state_mass(reference),
		"energy_kj": _state_energy(candidate) - _state_energy(reference),
		"o2_kg": _state_o2(candidate) - _state_o2(reference),
		"species_kg": _state_species(candidate) - _state_species(reference),
	}


func _canonical_o2_for_selected_mode(
		mode: String,
		upper_o2: float,
		lower_o2: float,
		room: RoomModel
	) -> Dictionary:
	if mode == "upper" or mode == "plume_upper":
		return {"o2_ref": upper_o2, "zone_code": 1.0}
	if mode == "lower" or mode == "plume_lower":
		return {"o2_ref": lower_o2, "zone_code": 2.0}
	if mode == "interface":
		return {"o2_ref": lerpf(lower_o2, upper_o2, 0.5), "zone_code": 3.0}
	if mode == "plume_blend":
		var legacy_span: float = room.o2_lower - room.o2_upper
		var blend: float = 0.5
		if absf(legacy_span) > 1.0e-9:
			blend = clampf((room.fire_o2_ref - room.o2_upper) / legacy_span, 0.0, 1.0)
		return {"o2_ref": lerpf(upper_o2, lower_o2, blend), "zone_code": 3.0}
	var total_gas_kg: float = maxf(
		0.0,
		float(_snapshots.get(str(room.id), {}).get("upper_gas_kg", 0.0))
				+ float(_snapshots.get(str(room.id), {}).get("lower_gas_kg", 0.0))
	)
	var bulk_o2: float = 0.0
	if total_gas_kg > THERMO_MASS_EPS_KG:
		bulk_o2 = (
			float(_snapshots.get(str(room.id), {}).get("upper_o2_kg", 0.0))
					+ float(_snapshots.get(str(room.id), {}).get("lower_o2_kg", 0.0))
		) / total_gas_kg
	return {"o2_ref": clampf(bulk_o2, 0.0, 1.0), "zone_code": 4.0}

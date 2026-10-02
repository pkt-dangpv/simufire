extends RefCounted
class_name CombustionSystem

const FuelObjectModelScript = preload("res://sim/fire/FuelObjectModel.gd")
const FireModelScript = preload("res://sim/fire/FireModel.gd")
const CombustionRegimeClassifierScript = preload("res://sim/fire/CombustionRegimeClassifier.gd")

const PHASE3_PROPOSAL_UNSUPPORTED_NO_FIRE: int = 1
const PHASE3_PROPOSAL_UNSUPPORTED_SECONDARY_HRR: int = 2
const PHASE3_PROPOSAL_UNSUPPORTED_FLASHOVER: int = 4
const PHASE3_PROPOSAL_UNSUPPORTED_THERMAL_FEEDBACK: int = 8
const PHASE3_PROPOSAL_UNSUPPORTED_RETAINED_POOL: int = 16
const PHASE3_PROPOSAL_UNSUPPORTED_BACKDRAFT: int = 32
const PHASE3_PROPOSAL_UNSUPPORTED_SPREAD: int = 64
const PHASE3_PROPOSAL_UNSUPPORTED_LATENT: int = 128
const PHASE3_PROPOSAL_UNSUPPORTED_O2_INDEPENDENT: int = 256

var _phase3_shadow_species_results: Array[Dictionary] = []
var _phase3_shadow_pre_fire_state: Dictionary = {}

# G3-3: libro contable pasivo de combustible por paso y propietario. Solo lo
# activa el runner headless (`--g3-fuel-ledger-v3`); la física nunca lo lee.
# Con false no se ejecuta ninguna instrucción del libro.
var g3_fuel_ledger_enabled: bool = false
var _g3_fuel_ledger_pending: Dictionary = {}
# G3 balance (g3_balance_v1): observables de otros sistemas del mismo paso.
var _g3_balance_external: Dictionary = {}

# G3: propiedad de energía y potencia por objeto activo (OFF por defecto).
# Solo en salas cuyo combustible se declara únicamente con objetos explícitos.
const G3_OWNERSHIP_SWITCH: String = "fire_explicit_object_fuel_ownership_enabled"

# G3 DIAGNÓSTICO (OFF por defecto; NO es física de producto). Hace continuo el
# objetivo de llama alrededor del umbral can_flame para aislar el efecto de su
# salto. Solo se fija desde engine_overrides de un escenario de diagnóstico.
# Diseño: G3_ENERGY_DELAY_DESIGN §13.
const G3_DIAG_FLAME_TARGET_WINDOW: String = "fire_diag_flame_target_window"
const G3_DIAG_FLAME_TARGET_JUMP_FRACTION: String = "fire_diag_flame_target_jump_fraction"
# El mismo umbral que `can_flame = flame_drive > 0.08`; aquí no se decide can_flame.
const G3_DIAG_CAN_FLAME_DRIVE: float = 0.08

# ============================================================
# COMBUSTION SYSTEM
# ------------------------------------------------------------
# Punto de entrada para migrar desde "un fuego por sala" a
# "muchos objetos combustibles por sala".
# ============================================================


func begin_phase3_shadow_step(building = null) -> void:
	_phase3_shadow_species_results.clear()
	_phase3_shadow_pre_fire_state.clear()
	if building == null:
		return
	for raw_room_id in building.get_rooms().keys():
		var room: RoomModel = building.get_room(raw_room_id)
		if room != null:
			_phase3_shadow_pre_fire_state[str(int(raw_room_id))] = \
					_snapshot_phase3_fire_state(room)


func drain_phase3_shadow_species_results() -> Array[Dictionary]:
	var results: Array[Dictionary] = _phase3_shadow_species_results.duplicate(true)
	_phase3_shadow_species_results.clear()
	return results


## F3.3v1: pure room-level fire-potential preview. It never reads or writes
## RoomModel and never owns live fuel/species. O2, ventilation and fuel caps
## are explicit outputs so later phases can promote the whole transaction.
func evaluate_phase3_canonical_fire_proposal(
	dt: float,
	context: Dictionary,
	canonical_source: Dictionary,
	state_before: Dictionary
	) -> Dictionary:
	var result: Dictionary = {
		"active_flag": 0.0,
		"supported_flag": 0.0,
		"unsupported_reason_mask": 0.0,
		"proposal_age_s": maxf(
			0.0, float(state_before.get("proposal_age_s", 0.0))
		),
		"curve_hrr_kw": 0.0,
		"proposal_target_kw": 0.0,
		"proposal_hrr_kw": 0.0,
		"unfiltered_growth_flag": 0.0,
		"remaining_fuel_pre_MJ": maxf(
			0.0, float(state_before.get("proposal_remaining_fuel_MJ", 0.0))
		),
		"remaining_fuel_post_MJ": maxf(
			0.0, float(state_before.get("proposal_remaining_fuel_MJ", 0.0))
		),
		"hard_extinction_flag": 0.0,
		"o2_inventory_cap_kw": 0.0,
		"ventilation_cap_kw": -1.0,
		"fuel_cap_kw": 0.0,
		"decision_fraction": 0.0,
		"accepted_hrr_kw": 0.0,
		"requested_o2_kg": 0.0,
		"accepted_o2_kg": 0.0,
		"accepted_fuel_MJ": 0.0,
		"zero_o2_flame_flag": 0.0,
		"persistent_updates": {},
	}
	if dt <= 0.0:
		return result

	var active: bool = bool(state_before.get("active_flag", false))
	var reason_mask: int = 0
	if not active:
		reason_mask |= PHASE3_PROPOSAL_UNSUPPORTED_NO_FIRE
	if float(state_before.get("secondary_hrr_gain_kw", 0.0)) > 0.000001:
		reason_mask |= PHASE3_PROPOSAL_UNSUPPORTED_SECONDARY_HRR
	if bool(state_before.get("flashover_triggered_flag", false)) \
			or float(state_before.get("flashover_hrr_multiplier", 1.0)) > 1.000001:
		reason_mask |= PHASE3_PROPOSAL_UNSUPPORTED_FLASHOVER
	if absf(float(context.get("thermal_feedback_coeff", 0.0))) > 0.000001:
		reason_mask |= PHASE3_PROPOSAL_UNSUPPORTED_THERMAL_FEEDBACK
	if float(context.get("fire_unburned_generation_fraction", 0.0)) > 0.000001 \
			or float(context.get("fire_pool_release_max_fraction", 0.0)) > 0.000001 \
			or float(state_before.get("retained_unburned_MJ", 0.0)) > 0.000001:
		reason_mask |= PHASE3_PROPOSAL_UNSUPPORTED_RETAINED_POOL
	if bool(state_before.get("backdraft_active_flag", false)) \
			or bool(state_before.get("backdraft_triggered_flag", false)):
		reason_mask |= PHASE3_PROPOSAL_UNSUPPORTED_BACKDRAFT
	# The simple-house aggregate fire coexists with an enabled furniture-radiation
	# capability. F3.3v1 may diagnose that aggregate contract; only authoritative
	# room-to-room spread puts the proposal outside its current scope.
	if bool(context.get("fire_spread_enabled", false)):
		reason_mask |= PHASE3_PROPOSAL_UNSUPPORTED_SPREAD
	if bool(state_before.get("fire_latent_active_flag", false)):
		reason_mask |= PHASE3_PROPOSAL_UNSUPPORTED_LATENT
	if bool(context.get("fire_o2_independent", false)):
		reason_mask |= PHASE3_PROPOSAL_UNSUPPORTED_O2_INDEPENDENT

	result["active_flag"] = 1.0 if active else 0.0
	result["unsupported_reason_mask"] = float(reason_mask)
	if reason_mask != 0:
		return result
	result["supported_flag"] = 1.0

	var o2_ref: float = clampf(
		float(canonical_source.get("o2_ref", 0.0)), 0.0, 1.0
	)
	var extinction_limit: float = clampf(
		float(canonical_source.get("extinction_limit", 0.0)), 0.0, 1.0
	)
	var hard_extinguished: bool = o2_ref <= extinction_limit
	var proposal_age_s: float = maxf(
		0.0,
		float(state_before.get("proposal_age_s", 0.0))
	)
	var remaining_fuel_MJ: float = maxf(
		0.0,
		float(state_before.get(
			"proposal_remaining_fuel_MJ",
			state_before.get("fuel_energy_MJ", 0.0)
		))
	)
	if active and remaining_fuel_MJ > 0.000001 and not hard_extinguished:
		proposal_age_s += dt

	var growth_alpha_kw_s2: float = maxf(
		0.0, float(state_before.get("growth_alpha_kw_s2", 0.0))
	)
	var max_hrr_kw: float = maxf(
		0.0, float(state_before.get("max_hrr_kw", 0.0))
	)
	var initial_fuel_MJ: float = maxf(
		0.000001, float(state_before.get("fuel_energy_MJ", remaining_fuel_MJ))
	)
	var curve_hrr_kw: float = minf(
		growth_alpha_kw_s2 * proposal_age_s * proposal_age_s,
		max_hrr_kw
	)
	var fuel_fraction: float = remaining_fuel_MJ / initial_fuel_MJ
	var fuel_decay: float = clampf(fuel_fraction / 0.15, 0.0, 1.0)
	var proposal_target_kw: float = curve_hrr_kw * fuel_decay
	var previous_proposal_hrr_kw: float = maxf(
		0.0,
		float(state_before.get("proposal_hrr_kw", 0.0))
	)
	var proposal_hrr_kw: float = _smooth_state_value(
		previous_proposal_hrr_kw,
		proposal_target_kw,
		dt,
		float(context.get("fire_hrr_rise_tau_s", 6.0)),
		float(context.get("fire_hrr_fall_tau_s", 20.0))
	)
	var unfiltered_growth: bool = bool(
		context.get(
			"phase3_canonical_unfiltered_fire_growth_shadow_enabled", false
		)
	)
	if unfiltered_growth:
		proposal_hrr_kw = proposal_target_kw

	var o2_rate_kg_per_MJ: float = maxf(
		0.0, float(state_before.get("o2_consumption_kg_per_MJ", 0.076))
	)
	var available_o2_kg: float = maxf(
		0.0, float(canonical_source.get("available_o2_kg", 0.0))
	)
	var o2_inventory_cap_kw: float = INF
	if o2_rate_kg_per_MJ > 0.000000001:
		o2_inventory_cap_kw = available_o2_kg * 1000.0 \
				/ (dt * o2_rate_kg_per_MJ)
	var kawagoe_limit_kw: float = float(context.get("kawagoe_limit_kw", 0.0))
	var ventilation_cap_kw: float = INF
	if kawagoe_limit_kw > 0.0:
		ventilation_cap_kw = kawagoe_limit_kw
	var fuel_cap_kw: float = remaining_fuel_MJ * 1000.0 / dt

	var accepted_hrr_kw: float = 0.0
	if not hard_extinguished:
		accepted_hrr_kw = minf(
			proposal_hrr_kw,
			minf(o2_inventory_cap_kw, minf(ventilation_cap_kw, fuel_cap_kw))
		)
	accepted_hrr_kw = maxf(0.0, accepted_hrr_kw)
	var decision_fraction: float = 1.0
	if proposal_hrr_kw > 0.000000001:
		decision_fraction = clampf(accepted_hrr_kw / proposal_hrr_kw, 0.0, 1.0)
	elif accepted_hrr_kw <= 0.000000001:
		decision_fraction = 0.0
	var requested_o2_kg: float = proposal_hrr_kw * dt / 1000.0 \
			* o2_rate_kg_per_MJ
	var accepted_o2_kg: float = accepted_hrr_kw * dt / 1000.0 \
			* o2_rate_kg_per_MJ
	var accepted_fuel_MJ: float = minf(
		remaining_fuel_MJ, accepted_hrr_kw * dt / 1000.0
	)
	var remaining_post_MJ: float = maxf(
		0.0, remaining_fuel_MJ - accepted_fuel_MJ
	)

	result.merge({
		"proposal_age_s": proposal_age_s,
		"curve_hrr_kw": curve_hrr_kw,
		"proposal_target_kw": proposal_target_kw,
		"proposal_hrr_kw": proposal_hrr_kw,
		"unfiltered_growth_flag": 1.0 if unfiltered_growth else 0.0,
		"remaining_fuel_pre_MJ": remaining_fuel_MJ,
		"remaining_fuel_post_MJ": remaining_post_MJ,
		"hard_extinction_flag": 1.0 if hard_extinguished else 0.0,
		"o2_inventory_cap_kw": o2_inventory_cap_kw,
		"ventilation_cap_kw": ventilation_cap_kw \
				if is_finite(ventilation_cap_kw) else -1.0,
		"fuel_cap_kw": fuel_cap_kw,
		"decision_fraction": decision_fraction,
		"accepted_hrr_kw": accepted_hrr_kw,
		"requested_o2_kg": requested_o2_kg,
		"accepted_o2_kg": accepted_o2_kg,
		"accepted_fuel_MJ": accepted_fuel_MJ,
		"zero_o2_flame_flag": 1.0 \
				if hard_extinguished and accepted_hrr_kw > 0.000001 else 0.0,
		"persistent_updates": {
			"proposal_age_s": proposal_age_s,
			"proposal_hrr_kw": proposal_hrr_kw,
			"proposal_target_kw": proposal_target_kw,
			"proposal_remaining_fuel_MJ": remaining_post_MJ,
		},
	}, true)
	return result


## F3.3v2: pure products for the accepted F3.3v1 proposal. Geometry-dependent
## plume mass remains owned by ThermalSystem; this result exports only its Qc
## driver. Requested products use one frozen fuel profile and every accepted
## product receives the proposal's common decision fraction.
func evaluate_phase3_canonical_fire_products(
	dt: float,
	context: Dictionary,
	canonical_source: Dictionary,
	state_before: Dictionary,
	fire_proposal: Dictionary
	) -> Dictionary:
	var result: Dictionary = {
		"active_flag": 0.0,
		"supported_flag": 0.0,
		"object_sync_required_flag": 0.0,
		"profile_object_count": 0.0,
		"quality_phi": 0.0,
		"carbon_scale": 0.0,
		"common_fraction": 0.0,
		"requested_fuel_MJ": 0.0,
		"accepted_fuel_MJ": 0.0,
		"requested_o2_kg": 0.0,
		"accepted_o2_kg": 0.0,
		"requested_total_energy_kj": 0.0,
		"accepted_total_energy_kj": 0.0,
		"effective_chi_rad": 0.0,
		"requested_radiative_energy_kj": 0.0,
		"accepted_radiative_energy_kj": 0.0,
		"requested_convective_energy_kj": 0.0,
		"accepted_convective_energy_kj": 0.0,
		"accepted_plume_driver_hrr_kw": 0.0,
		"accepted_plume_driver_qc_kw": 0.0,
		"requested_species_kg": {},
		"accepted_species_kg": {},
		"requested_carbon_available_kg": 0.0,
		"requested_carbon_products_kg": 0.0,
		"requested_carbon_untracked_kg": 0.0,
		"requested_carbon_residual_kg": 0.0,
		"accepted_carbon_available_kg": 0.0,
		"accepted_carbon_products_kg": 0.0,
		"accepted_carbon_untracked_kg": 0.0,
		"accepted_carbon_residual_kg": 0.0,
		"fuel_residual_MJ": 0.0,
		"o2_residual_kg": 0.0,
		"energy_residual_kj": 0.0,
		"species_common_fraction_residual_kg": 0.0,
	}
	if dt <= 0.0 or fire_proposal.is_empty():
		return result
	var active: bool = float(fire_proposal.get("active_flag", 0.0)) > 0.5
	var supported: bool = float(
		fire_proposal.get("supported_flag", 0.0)
	) > 0.5
	var profile: Dictionary = state_before.get("product_profile", {})
	result["active_flag"] = 1.0 if active else 0.0
	result["supported_flag"] = 1.0 if supported else 0.0
	result["object_sync_required_flag"] = float(
		profile.get("object_sync_required_flag", 0.0)
	)
	result["profile_object_count"] = float(profile.get("object_count", 0.0))
	if not active or not supported:
		return result

	var proposal_hrr_kw: float = maxf(
		0.0, float(fire_proposal.get("proposal_hrr_kw", 0.0))
	)
	var accepted_hrr_kw: float = maxf(
		0.0, float(fire_proposal.get("accepted_hrr_kw", 0.0))
	)
	var common_fraction: float = clampf(
		float(fire_proposal.get("decision_fraction", 0.0)), 0.0, 1.0
	)
	var requested_fuel_MJ: float = proposal_hrr_kw * dt / 1000.0
	var accepted_fuel_MJ: float = minf(
		requested_fuel_MJ,
		maxf(0.0, float(fire_proposal.get("accepted_fuel_MJ", 0.0)))
	)
	var o2_rate_kg_per_MJ: float = maxf(
		0.0, float(state_before.get("o2_consumption_kg_per_MJ", 0.076))
	)
	var requested_o2_kg: float = requested_fuel_MJ * o2_rate_kg_per_MJ
	var accepted_o2_kg: float = minf(
		requested_o2_kg,
		maxf(0.0, float(fire_proposal.get("accepted_o2_kg", 0.0)))
	)
	# Combustion quality is limited by oxidant supply, not by fuel exhaustion.
	# The common fraction may also contain a fuel cap, which must stop every
	# product without spuriously turning the last fuel step into a rich fire.
	var quality_fraction: float = 1.0
	if proposal_hrr_kw > 0.000001:
		quality_fraction = minf(
			quality_fraction,
			clampf(
				float(fire_proposal.get("o2_inventory_cap_kw", 0.0))
						/ proposal_hrr_kw,
				0.0,
				1.0
			)
		)
		var ventilation_cap_kw: float = float(
			fire_proposal.get("ventilation_cap_kw", -1.0)
		)
		if ventilation_cap_kw >= 0.0:
			quality_fraction = minf(
				quality_fraction,
				clampf(ventilation_cap_kw / proposal_hrr_kw, 0.0, 1.0)
			)
	var quality_phi: float = clampf(
		1.0 / maxf(0.1, quality_fraction), 1.0, 10.0
	)

	var smoke_yield: float = maxf(
		0.0,
		_phase3_profile_value(
			profile,
			"smoke_yield_kg_per_MJ",
			float(context.get("smoke_yield_kg_per_MJ", 0.0))
		)
	)
	var co_base_yield: float = maxf(
		0.0,
		_phase3_profile_value(
			profile,
			"co_yield_kg_per_MJ",
			float(context.get("co_base_yield_kg_per_MJ", 0.0))
		)
	)
	var co_max_yield: float = maxf(
		co_base_yield, float(context.get("co_max_yield_kg_per_MJ", co_base_yield))
	)
	var co_yield: float = clampf(
		co_base_yield * exp(
			float(context.get("fire_co_phi_rate", 2.0)) * (quality_phi - 1.0)
		),
		co_base_yield,
		co_max_yield
	)
	var forced_co_yield: float = float(
		context.get("fire_co_yield_force_kg_per_MJ", -1.0)
	)
	if forced_co_yield >= 0.0:
		co_yield = forced_co_yield

	var co2_base_global: float = maxf(
		0.0, float(context.get("co2_base_yield_kg_per_MJ", 0.0831))
	)
	var co2_base_yield: float = maxf(
		0.0,
		_phase3_profile_value(
			profile, "co2_yield_kg_per_MJ", co2_base_global
		)
	)
	var co2_min_global: float = maxf(
		0.0, float(context.get("co2_min_yield_kg_per_MJ", 0.0594))
	)
	var co2_min_yield: float = co2_base_yield * (
		co2_min_global / maxf(0.0001, co2_base_global)
	)
	var co2_phi_fraction: float = clampf(
		1.0 - (quality_phi - 1.0) / maxf(
			0.0001, float(context.get("co2_phi_decay_rate", 2.5))
		),
		0.0,
		1.0
	)
	var co2_yield: float = lerpf(
		co2_min_yield, co2_base_yield, co2_phi_fraction
	)

	var hcn_base_global: float = maxf(
		0.0, float(context.get("hcn_base_yield_kg_per_MJ", 0.0))
	)
	var hcn_base_yield: float = maxf(
		0.0,
		_phase3_profile_value(
			profile, "hcn_yield_kg_per_MJ", hcn_base_global
		)
	)
	var hcn_max_global: float = maxf(
		hcn_base_yield, float(context.get("hcn_max_yield_kg_per_MJ", hcn_base_yield))
	)
	var hcn_max_yield: float = maxf(
		hcn_max_global,
		hcn_base_yield * (
			hcn_max_global / maxf(hcn_base_global, 0.000001)
		)
	)
	var hcn_yield: float = 0.0
	if hcn_base_yield > 0.0:
		hcn_yield = clampf(
			hcn_base_yield * exp(
				float(context.get("fire_co_phi_rate", 2.0)) * (quality_phi - 1.0)
			),
			hcn_base_yield,
			hcn_max_yield
		)
	var hcl_yield: float = maxf(
		0.0, _phase3_profile_value(profile, "hcl_yield_kg_per_MJ", 0.0)
	)
	var acrolein_base_yield: float = maxf(
		0.0, _phase3_profile_value(profile, "acrolein_yield_kg_per_MJ", 0.0)
	)
	var formaldehyde_base_yield: float = maxf(
		0.0, _phase3_profile_value(profile, "formaldehyde_yield_kg_per_MJ", 0.0)
	)
	var acrolein_yield: float = minf(
		acrolein_base_yield * 4.0,
		acrolein_base_yield * exp(
			float(context.get("fire_co_phi_rate", 2.0))
					* (quality_phi - 1.0) * 0.7
		)
	)
	var formaldehyde_yield: float = minf(
		formaldehyde_base_yield * 3.0,
		formaldehyde_base_yield * exp(
			float(context.get("fire_co_phi_rate", 2.0))
					* (quality_phi - 1.0) * 0.5
		)
	)
	var requested_species: Dictionary = {
		"smoke": requested_fuel_MJ * smoke_yield,
		"co": requested_fuel_MJ * co_yield,
		"co2": requested_fuel_MJ * co2_yield,
		"hcn": requested_fuel_MJ * hcn_yield,
		"hcl": requested_fuel_MJ * hcl_yield,
		"acrolein": requested_fuel_MJ * acrolein_yield,
		"formaldehyde": requested_fuel_MJ * formaldehyde_yield,
	}

	var carbon_available_kg: float = requested_fuel_MJ * maxf(
		0.0, float(context.get("fuel_c_kg_per_MJ", 0.027))
	)
	var raw_carbon_products_kg: float = _phase3_products_carbon_kg(
		requested_species
	)
	var carbon_scale: float = 1.0
	if raw_carbon_products_kg > carbon_available_kg \
			and raw_carbon_products_kg > 0.000000001:
		carbon_scale = clampf(
			carbon_available_kg / raw_carbon_products_kg, 0.0, 1.0
		)
	for species_name in [
		"smoke", "co", "co2", "hcn", "acrolein", "formaldehyde"
	]:
		requested_species[species_name] = maxf(
			0.0, float(requested_species.get(species_name, 0.0)) * carbon_scale
		)
	var requested_carbon_products_kg: float = _phase3_products_carbon_kg(
		requested_species
	)
	var requested_carbon_untracked_kg: float = maxf(
		0.0, carbon_available_kg - requested_carbon_products_kg
	)
	var accepted_species: Dictionary = _scale_phase3_species(
		requested_species, common_fraction
	)
	var accepted_carbon_available_kg: float = \
			carbon_available_kg * common_fraction
	var accepted_carbon_products_kg: float = _phase3_products_carbon_kg(
		accepted_species
	)
	var accepted_carbon_untracked_kg: float = \
			requested_carbon_untracked_kg * common_fraction

	var requested_total_energy_kj: float = proposal_hrr_kw * dt
	var accepted_total_energy_kj: float = accepted_hrr_kw * dt
	var canonical_o2_ref: float = clampf(
		float(canonical_source.get("o2_ref", 0.0)), 0.0, 1.0
	)
	var normal_chi_rad: float = clampf(
		_phase3_profile_value(
			profile,
			"chi_rad_normal",
			float(context.get("hrr_chi_rad_normal", 0.35))
		),
		0.0,
		1.0
	)
	var configured_normal_chi_rad: float = maxf(
		0.01, float(context.get("hrr_chi_rad_normal", 0.35))
	)
	var low_o2_chi_rad: float = normal_chi_rad * (
		float(context.get("hrr_chi_rad_low_o2", 0.50))
		/ configured_normal_chi_rad
	)
	var effective_chi_rad: float = clampf(
		lerpf(
			low_o2_chi_rad,
			normal_chi_rad,
			clampf(inverse_lerp(0.06, 0.12, canonical_o2_ref), 0.0, 1.0)
		),
		0.0,
		1.0
	)
	var requested_radiative_kj: float = \
			requested_total_energy_kj * effective_chi_rad
	var requested_convective_kj: float = \
			requested_total_energy_kj - requested_radiative_kj
	var accepted_radiative_kj: float = \
			requested_radiative_kj * common_fraction
	var accepted_convective_kj: float = \
			requested_convective_kj * common_fraction
	var species_fraction_residual_kg: float = 0.0
	for species_name in requested_species.keys():
		species_fraction_residual_kg = maxf(
			species_fraction_residual_kg,
			absf(
				float(accepted_species.get(species_name, 0.0))
						- float(requested_species.get(species_name, 0.0))
						* common_fraction
			)
		)

	result.merge({
		"quality_phi": quality_phi,
		"carbon_scale": carbon_scale,
		"common_fraction": common_fraction,
		"requested_fuel_MJ": requested_fuel_MJ,
		"accepted_fuel_MJ": accepted_fuel_MJ,
		"requested_o2_kg": requested_o2_kg,
		"accepted_o2_kg": accepted_o2_kg,
		"requested_total_energy_kj": requested_total_energy_kj,
		"accepted_total_energy_kj": accepted_total_energy_kj,
		"effective_chi_rad": effective_chi_rad,
		"requested_radiative_energy_kj": requested_radiative_kj,
		"accepted_radiative_energy_kj": accepted_radiative_kj,
		"requested_convective_energy_kj": requested_convective_kj,
		"accepted_convective_energy_kj": accepted_convective_kj,
		"accepted_plume_driver_hrr_kw": accepted_hrr_kw,
		"accepted_plume_driver_qc_kw": accepted_hrr_kw * (1.0 - effective_chi_rad),
		"requested_species_kg": requested_species,
		"accepted_species_kg": accepted_species,
		"requested_carbon_available_kg": carbon_available_kg,
		"requested_carbon_products_kg": requested_carbon_products_kg,
		"requested_carbon_untracked_kg": requested_carbon_untracked_kg,
		"requested_carbon_residual_kg": carbon_available_kg \
				- requested_carbon_products_kg - requested_carbon_untracked_kg,
		"accepted_carbon_available_kg": accepted_carbon_available_kg,
		"accepted_carbon_products_kg": accepted_carbon_products_kg,
		"accepted_carbon_untracked_kg": accepted_carbon_untracked_kg,
		"accepted_carbon_residual_kg": accepted_carbon_available_kg \
				- accepted_carbon_products_kg - accepted_carbon_untracked_kg,
		"fuel_residual_MJ": accepted_fuel_MJ \
				- accepted_hrr_kw * dt / 1000.0,
		"o2_residual_kg": accepted_o2_kg \
				- accepted_fuel_MJ * o2_rate_kg_per_MJ,
		"energy_residual_kj": accepted_total_energy_kj \
				- accepted_radiative_kj - accepted_convective_kj,
		"species_common_fraction_residual_kg": species_fraction_residual_kg,
	}, true)
	return result


func _phase3_profile_value(
	profile: Dictionary,
	key: String,
	fallback: float
	) -> float:
	var value: float = float(profile.get(key, -1.0))
	return value if value >= 0.0 else fallback


func _phase3_products_carbon_kg(species: Dictionary) -> float:
	return maxf(0.0, float(species.get("smoke", 0.0))) * 0.87 \
			+ maxf(0.0, float(species.get("co", 0.0))) * (12.0 / 28.0) \
			+ maxf(0.0, float(species.get("co2", 0.0))) * (12.0 / 44.0) \
			+ maxf(0.0, float(species.get("hcn", 0.0))) * (12.0 / 27.0) \
			+ maxf(0.0, float(species.get("acrolein", 0.0))) * (36.0 / 56.0) \
			+ maxf(0.0, float(species.get("formaldehyde", 0.0))) * (12.0 / 30.0)


## F3.3v2c1: pure bounded allocation of one accepted aggregate fuel debit.
## Entries are dictionaries so this evaluator cannot mutate live fuel objects.
func evaluate_phase3_canonical_fuel_object_sync(
		pre_ledger: Array,
		accepted_fuel_MJ: float
	) -> Dictionary:
	var result: Dictionary = {
		"active_flag": 0.0,
		"supported_flag": 0.0,
		"rejection_mask": 0.0,
		"object_count": 0.0,
		"identity_signature": 0.0,
		"eligible_count": 0.0,
		"pre_fuel_MJ": 0.0,
		"proposed_fuel_MJ": 0.0,
		"requested_debit_MJ": maxf(0.0, accepted_fuel_MJ),
		"allocated_debit_MJ": 0.0,
		"allocation_residual_MJ": 0.0,
		"minimum_remaining_MJ": 0.0,
		"exhausted_count": 0.0,
		"proposed_ledger": [],
	}
	if pre_ledger.is_empty():
		result["rejection_mask"] = 1.0
		return result
	var seen: Dictionary = {}
	var entries: Array = []
	var total_weight: float = 0.0
	for raw_entry in pre_ledger:
		if not raw_entry is Dictionary:
			result["rejection_mask"] = 2.0
			return result
		var entry: Dictionary = Dictionary(raw_entry).duplicate(true)
		var object_id: String = String(entry.get("id", "")).strip_edges()
		if object_id.is_empty():
			result["rejection_mask"] = 4.0
			return result
		if seen.has(object_id):
			result["rejection_mask"] = 8.0
			return result
		seen[object_id] = true
		var remaining_MJ: float = maxf(
			0.0, float(entry.get("remaining_fuel_MJ", 0.0))
		)
		var eligible: bool = bool(entry.get("eligible_flag", false)) \
				and remaining_MJ > 0.000000001
		var weight: float = maxf(0.0, float(entry.get("allocation_weight", 0.0))) \
				if eligible else 0.0
		entry["id"] = object_id
		entry["remaining_fuel_MJ"] = remaining_MJ
		entry["allocated_debit_MJ"] = 0.0
		entry["_weight"] = weight
		entries.append(entry)
		result["pre_fuel_MJ"] = float(result["pre_fuel_MJ"]) + remaining_MJ
		if weight > 0.0:
			result["eligible_count"] = float(result["eligible_count"]) + 1.0
			total_weight += weight
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.get("id", "")) < String(b.get("id", ""))
	)
	var identity_signature: int = 17
	for entry in entries:
		var object_id: String = String(entry.get("id", ""))
		for index in range(object_id.length()):
			identity_signature = int(
				(identity_signature * 131 + object_id.unicode_at(index))
				% 2147483647
			)
	result["object_count"] = float(entries.size())
	result["identity_signature"] = float(identity_signature)
	result["active_flag"] = 1.0
	var requested_debit_MJ: float = minf(
		maxf(0.0, accepted_fuel_MJ), float(result["pre_fuel_MJ"])
	)
	result["requested_debit_MJ"] = requested_debit_MJ
	if requested_debit_MJ > 0.000000001 and total_weight <= 0.0:
		result["rejection_mask"] = 16.0
		return result

	var allocated_MJ: float = 0.0
	for entry in entries:
		if float(entry["_weight"]) <= 0.0:
			continue
		var share_MJ: float = minf(
			float(entry["remaining_fuel_MJ"]),
			requested_debit_MJ * float(entry["_weight"]) / total_weight
		)
		entry["allocated_debit_MJ"] = share_MJ
		entry["remaining_fuel_MJ"] = float(entry["remaining_fuel_MJ"]) - share_MJ
		allocated_MJ += share_MJ
	var leftover_MJ: float = maxf(0.0, requested_debit_MJ - allocated_MJ)
	if leftover_MJ > 0.000000001:
		var capacity_MJ: float = 0.0
		for entry in entries:
			if float(entry["_weight"]) > 0.0:
				capacity_MJ += float(entry["remaining_fuel_MJ"])
		if capacity_MJ > 0.000000001:
			for entry in entries:
				if float(entry["_weight"]) <= 0.0:
					continue
				var extra_MJ: float = minf(
					float(entry["remaining_fuel_MJ"]),
					leftover_MJ * float(entry["remaining_fuel_MJ"]) / capacity_MJ
				)
				entry["allocated_debit_MJ"] = \
						float(entry["allocated_debit_MJ"]) + extra_MJ
				entry["remaining_fuel_MJ"] = \
						float(entry["remaining_fuel_MJ"]) - extra_MJ
				allocated_MJ += extra_MJ
	var proposed_total_MJ: float = 0.0
	var minimum_remaining_MJ: float = INF
	var exhausted_count: int = 0
	for entry in entries:
		entry.erase("_weight")
		var remaining_MJ: float = maxf(
			0.0, float(entry["remaining_fuel_MJ"])
		)
		entry["remaining_fuel_MJ"] = remaining_MJ
		proposed_total_MJ += remaining_MJ
		minimum_remaining_MJ = minf(minimum_remaining_MJ, remaining_MJ)
		if remaining_MJ <= 0.000000001:
			exhausted_count += 1
	result["supported_flag"] = 1.0
	result["allocated_debit_MJ"] = allocated_MJ
	result["proposed_fuel_MJ"] = proposed_total_MJ
	result["allocation_residual_MJ"] = requested_debit_MJ - allocated_MJ
	result["minimum_remaining_MJ"] = \
			0.0 if minimum_remaining_MJ == INF else minimum_remaining_MJ
	result["exhausted_count"] = float(exhausted_count)
	result["proposed_ledger"] = entries
	return result


## F3.2b1: evaluates one closed, passive combustion transaction. The live fire
## remains the proposal source; canonical O2 accepts the whole bundle together.
## This function never writes RoomModel or FireModel.
func evaluate_phase3_canonical_combustion_step(
		room: RoomModel,
		dt: float,
		context: Dictionary,
		canonical_input: Dictionary,
		previous_state: Dictionary,
		legacy_species_result: Dictionary
	) -> Dictionary:
	if room == null or dt <= 0.0:
		return {}
	var room_key: String = str(room.id)
	var pre_state: Dictionary = _phase3_shadow_pre_fire_state.get(
		room_key, _snapshot_phase3_fire_state(room)
	).duplicate(true)
	var state_before: Dictionary = previous_state.duplicate(true) \
			if not previous_state.is_empty() else pre_state.duplicate(true)
	var fire_active: bool = bool(state_before.get("active_flag", false)) \
			or bool(pre_state.get("active_flag", false))

	var upper_gas_kg: float = maxf(
		0.0, float(canonical_input.get("upper_gas_kg", 0.0))
	)
	var lower_gas_kg: float = maxf(
		0.0, float(canonical_input.get("lower_gas_kg", 0.0))
	)
	var upper_o2_kg: float = clampf(
		float(canonical_input.get("upper_o2_kg", 0.0)), 0.0, upper_gas_kg
	)
	var lower_o2_kg: float = clampf(
		float(canonical_input.get("lower_o2_kg", 0.0)), 0.0, lower_gas_kg
	)
	# A zero-mass upper zone cannot supply oxidant. Bootstrap the first plume
	# from lower, then move the whole transaction to upper once that zone exists.
	# F3.2b7 keeps the lower reservoir as source while a real canonical exterior
	# counterflow is feeding it. The debit still happens atomically in the
	# combustion bundle; this selection neither creates nor pre-credits O2.
	var post_opening_coupling_enabled: bool = bool(
		context.get("phase3_post_opening_coupling_enabled", false)
	)
	var counterflow_exchange_kg: float = maxf(
		0.0, float(context.get("phase3_post_opening_counterflow_exchange_kg", 0.0))
	)
	var counterflow_incoming_o2_kg: float = maxf(
		0.0, float(context.get("phase3_post_opening_counterflow_incoming_o2_kg", 0.0))
	)
	var post_opening_lower_source: bool = post_opening_coupling_enabled \
			and counterflow_exchange_kg > 0.000000001 \
			and lower_gas_kg > 0.000001
	var o2_source_zone: String = "upper"
	if upper_gas_kg <= 0.000001 \
			or String(context.get("fire_o2_mode", "legacy")).to_lower() == "lower" \
			or post_opening_lower_source:
		o2_source_zone = "lower"
	var source_gas_kg: float = upper_gas_kg if o2_source_zone == "upper" else lower_gas_kg
	var source_o2_kg: float = upper_o2_kg if o2_source_zone == "upper" else lower_o2_kg
	var canonical_o2_ref: float = clampf(
		source_o2_kg / source_gas_kg if source_gas_kg > 0.000001 else 0.0,
		0.0,
		1.0
	)
	var nominal_o2: float = maxf(
		0.001, float(state_before.get("o2_nominal", 0.209))
	)
	var minimum_o2: float = clampf(
		float(state_before.get("o2_min_for_flame", 0.12)), 0.0, nominal_o2
	)
	var early_opening_signal: float = clampf(
		maxf(
			maxf(
				float(context.get("outside_open_factor", 0.0)),
				float(context.get("outside_open_path_factor", 0.0))
			),
			maxf(
				maxf(0.0, float(context.get("window_open_max", 0.0))),
				1.0 if _has_explicit_fire_o2_mode(context) else 0.0
			)
		),
		0.0,
		1.0
	)
	var full_hrr_o2: float = maxf(
		minimum_o2 + 0.001,
		lerpf(
			nominal_o2,
			float(context.get("fire_o2_full_hrr_open", nominal_o2)),
			early_opening_signal
		)
	)
	var ambient_c: float = float(context.get("ambient_c", 20.0))
	var use_fds_extinction: bool = bool(context.get("fire_fds_extinction_enabled", false))
	var extinction_limit: float = minimum_o2
	if use_fds_extinction:
		extinction_limit = _compute_extinction_o2_limit(
			room, context, ambient_c, minimum_o2
		)
	var raw_factor: float = _compute_o2_factor(
		canonical_o2_ref, full_hrr_o2, minimum_o2
	)
	var target_factor: float = raw_factor
	if use_fds_extinction:
		target_factor = _compute_extinction_factor(
			canonical_o2_ref,
			extinction_limit,
			float(context.get("fire_fds_extinction_transition_width", 0.030))
		)
	var oxygen_independent: bool = bool(context.get("fire_o2_independent", false))
	var extinguished: bool = not oxygen_independent \
			and canonical_o2_ref <= extinction_limit
	var previous_factor: float = clampf(
		float(state_before.get("o2_hrr_factor", 1.0)), 0.0, 1.0
	)
	var canonical_factor: float = 1.0 if oxygen_independent else _smooth_state_value(
		previous_factor,
		target_factor,
		dt,
		float(context.get("fire_o2_hrr_rise_tau_s", 14.0)),
		float(context.get("fire_o2_hrr_fall_tau_s", 32.0))
	)
	if extinguished:
		canonical_factor = 0.0
	canonical_factor = clampf(canonical_factor, 0.0, 1.0)

	var legacy_hrr_kw: float = maxf(0.0, room.hrr_kw)
	var legacy_target_kw: float = maxf(0.0, room.hrr_target_kw)
	var legacy_factor: float = clampf(room.o2_hrr_factor, 0.0, 1.0)
	var throttle_fraction: float = 1.0
	if not oxygen_independent:
		if canonical_factor <= 0.0:
			throttle_fraction = 0.0
		elif legacy_factor > 0.000001:
			throttle_fraction = minf(1.0, canonical_factor / legacy_factor)
	var o2_rate_kg_per_MJ: float = maxf(
		0.0, float(state_before.get("o2_consumption_kg_per_MJ", 0.076))
	)
	var requested_o2_kg: float = legacy_hrr_kw * dt / 1000.0 * o2_rate_kg_per_MJ
	var throttled_o2_kg: float = requested_o2_kg * throttle_fraction
	var protected_o2_kg: float = source_gas_kg * extinction_limit
	var available_o2_kg: float = maxf(0.0, source_o2_kg - protected_o2_kg)
	var canonical_fire_proposal: Dictionary = {}
	if bool(context.get("phase3_canonical_fire_proposal_shadow_enabled", false)):
		canonical_fire_proposal = evaluate_phase3_canonical_fire_proposal(
			dt,
			context,
			{
				"o2_ref": canonical_o2_ref,
				"extinction_limit": extinction_limit,
				"available_o2_kg": available_o2_kg,
			},
			state_before
		)
	var canonical_fire_products: Dictionary = {}
	if bool(context.get("phase3_canonical_fire_products_shadow_enabled", false)) \
			and not canonical_fire_proposal.is_empty():
		canonical_fire_products = evaluate_phase3_canonical_fire_products(
			dt,
			context,
			{"o2_ref": canonical_o2_ref},
			state_before,
			canonical_fire_proposal
		)
	var products_routing_active: bool = bool(
		context.get(
			"phase3_canonical_fire_products_routing_shadow_enabled", false
		)
	) and float(canonical_fire_products.get("active_flag", 0.0)) > 0.5 \
			and float(canonical_fire_products.get("supported_flag", 0.0)) > 0.5
	var inventory_fraction: float = 1.0
	if throttled_o2_kg > 0.000000001:
		inventory_fraction = minf(1.0, available_o2_kg / throttled_o2_kg)
	var accepted_fraction: float = clampf(
		throttle_fraction * inventory_fraction, 0.0, 1.0
	)
	if not fire_active:
		accepted_fraction = 0.0

	var accepted_hrr_kw: float = legacy_hrr_kw * accepted_fraction
	var accepted_target_kw: float = legacy_target_kw * accepted_fraction
	var accepted_o2_kg: float = requested_o2_kg * accepted_fraction
	var requested_fuel_MJ: float = maxf(0.0, room.fuel_consumed_MJ_step)
	var accepted_fuel_MJ: float = requested_fuel_MJ * accepted_fraction
	var requested_species: Dictionary = _phase3_combustion_species_proposal(
		room, dt, pre_state, legacy_species_result
	)
	var accepted_species: Dictionary = _scale_phase3_species(
		requested_species, accepted_fraction
	)
	var multisurface_enabled: bool = bool(
		context.get("phase3_canonical_multisurface_shadow_enabled", false)
	)
	var requested_total_fire_energy_kj: float = legacy_hrr_kw * dt \
			if multisurface_enabled else 0.0
	var accepted_total_fire_energy_kj: float = accepted_hrr_kw * dt \
			if multisurface_enabled else 0.0
	var effective_chi_rad: float = 0.0
	if multisurface_enabled:
		var normal_chi_rad: float = clampf(
			room.chi_rad_normal if room.chi_rad_normal >= 0.0 else float(
				context.get("hrr_chi_rad_normal", 0.35)
			),
			0.0,
			1.0
		)
		var configured_normal_chi_rad: float = maxf(
			0.01, float(context.get("hrr_chi_rad_normal", 0.35))
		)
		var low_o2_chi_rad: float = normal_chi_rad * (
			float(context.get("hrr_chi_rad_low_o2", 0.50))
			/ configured_normal_chi_rad
		)
		effective_chi_rad = clampf(
			lerpf(
				low_o2_chi_rad,
				normal_chi_rad,
				clampf(inverse_lerp(0.06, 0.12, canonical_o2_ref), 0.0, 1.0)
			),
			0.0,
			1.0
		)
	var requested_radiative_energy_kj: float = (
		requested_total_fire_energy_kj * effective_chi_rad
	)
	var accepted_radiative_energy_kj: float = (
		requested_radiative_energy_kj * accepted_fraction
	)
	if products_routing_active:
		accepted_fraction = clampf(
			float(canonical_fire_products.get("common_fraction", 0.0)),
			0.0,
			1.0
		)
		accepted_hrr_kw = maxf(
			0.0,
			float(canonical_fire_products.get(
				"accepted_plume_driver_hrr_kw", 0.0
			))
		)
		accepted_target_kw = maxf(
			0.0, float(canonical_fire_proposal.get("proposal_target_kw", 0.0))
		) * accepted_fraction
		requested_o2_kg = maxf(
			0.0, float(canonical_fire_products.get("requested_o2_kg", 0.0))
		)
		accepted_o2_kg = maxf(
			0.0, float(canonical_fire_products.get("accepted_o2_kg", 0.0))
		)
		requested_fuel_MJ = maxf(
			0.0, float(canonical_fire_products.get("requested_fuel_MJ", 0.0))
		)
		accepted_fuel_MJ = maxf(
			0.0, float(canonical_fire_products.get("accepted_fuel_MJ", 0.0))
		)
		requested_species = canonical_fire_products.get(
			"requested_species_kg", {}
		).duplicate(true)
		accepted_species = canonical_fire_products.get(
			"accepted_species_kg", {}
		).duplicate(true)
		requested_total_fire_energy_kj = maxf(
			0.0,
			float(canonical_fire_products.get(
				"requested_total_energy_kj", 0.0
			))
		)
		accepted_total_fire_energy_kj = maxf(
			0.0,
			float(canonical_fire_products.get(
				"accepted_total_energy_kj", 0.0
			))
		)
		effective_chi_rad = clampf(
			float(canonical_fire_products.get("effective_chi_rad", 0.0)),
			0.0,
			1.0
		)
		requested_radiative_energy_kj = maxf(
			0.0,
			float(canonical_fire_products.get(
				"requested_radiative_energy_kj", 0.0
			))
		)
		accepted_radiative_energy_kj = maxf(
			0.0,
			float(canonical_fire_products.get(
				"accepted_radiative_energy_kj", 0.0
			))
		)
	var fuel_object_sync: Dictionary = {}
	var fuel_object_sync_active: bool = products_routing_active and bool(
		context.get("phase3_canonical_fuel_object_sync_shadow_enabled", false)
	)
	if fuel_object_sync_active:
		var object_ledger: Array = state_before.get(
			"fuel_object_ledger", pre_state.get("fuel_object_ledger", [])
		).duplicate(true)
		fuel_object_sync = evaluate_phase3_canonical_fuel_object_sync(
			object_ledger, accepted_fuel_MJ
		)
		var live_object_fuel_MJ: float = get_room_total_remaining_fuel_MJ(room)
		fuel_object_sync["live_fuel_MJ"] = live_object_fuel_MJ
		fuel_object_sync["live_delta_MJ"] = live_object_fuel_MJ - float(
			fuel_object_sync.get("proposed_fuel_MJ", 0.0)
		)
		fuel_object_sync["seed_residual_MJ"] = float(
			state_before.get("remaining_fuel_MJ", 0.0)
		) - float(fuel_object_sync.get("pre_fuel_MJ", 0.0))
		if float(fuel_object_sync.get("supported_flag", 0.0)) <= 0.5:
			products_routing_active = false
			accepted_fraction = 0.0
			accepted_hrr_kw = 0.0
			accepted_target_kw = 0.0
			accepted_o2_kg = 0.0
			accepted_fuel_MJ = 0.0
			accepted_species = _scale_phase3_species(requested_species, 0.0)
			accepted_total_fire_energy_kj = 0.0
			accepted_radiative_energy_kj = 0.0

	var legacy_retained_delta_MJ: float = float(room.retained_unburned_MJ) \
			- float(pre_state.get("retained_unburned_MJ", room.retained_unburned_MJ))
	var legacy_fire_time_delta_s: float = float(room.fire_time_s) \
			- float(pre_state.get("fire_time_s", room.fire_time_s))
	var next_remaining_fuel_MJ: float = maxf(
		0.0,
		float(state_before.get("remaining_fuel_MJ", 0.0)) - accepted_fuel_MJ
	)
	if products_routing_active:
		next_remaining_fuel_MJ = maxf(
			0.0,
			float(canonical_fire_proposal.get(
				"persistent_updates", {}
			).get("proposal_remaining_fuel_MJ", next_remaining_fuel_MJ))
		)
	if fuel_object_sync_active \
			and float(fuel_object_sync.get("supported_flag", 0.0)) > 0.5:
		next_remaining_fuel_MJ = maxf(
			0.0, float(fuel_object_sync.get("proposed_fuel_MJ", 0.0))
		)
	var next_retained_MJ: float = maxf(
		0.0,
		float(state_before.get("retained_unburned_MJ", 0.0))
				+ legacy_retained_delta_MJ * accepted_fraction
	)
	var next_fire_time_s: float = maxf(
		0.0,
		float(state_before.get("fire_time_s", 0.0))
				+ maxf(0.0, legacy_fire_time_delta_s) * accepted_fraction
	)
	var next_dormant_s: float = 0.0 if accepted_hrr_kw > 0.5 else \
			maxf(0.0, float(state_before.get("fire_dormant_time_s", 0.0)) + dt)
	var next_state: Dictionary = state_before.duplicate(true)
	next_state.merge({
		"active_flag": fire_active and (next_remaining_fuel_MJ > 0.0 or next_retained_MJ > 0.0),
		"hrr_kw": accepted_hrr_kw,
		"hrr_target_kw": accepted_target_kw,
		"o2_hrr_factor": canonical_factor,
		"remaining_fuel_MJ": next_remaining_fuel_MJ,
		"retained_unburned_MJ": next_retained_MJ,
		"fire_time_s": next_fire_time_s,
		"fire_dormant_time_s": next_dormant_s,
		"extinguished_flag": extinguished,
	}, true)
	if not canonical_fire_proposal.is_empty():
		next_state.merge(
			canonical_fire_proposal.get("persistent_updates", {}), true
		)
	if fuel_object_sync_active:
		next_state["fuel_object_sync_active_flag"] = true
		next_state["fuel_object_ledger"] = fuel_object_sync.get(
			"proposed_ledger", state_before.get("fuel_object_ledger", [])
		).duplicate(true)
		next_state["remaining_fuel_MJ"] = next_remaining_fuel_MJ
		next_state["proposal_remaining_fuel_MJ"] = next_remaining_fuel_MJ

	var transaction: Dictionary = {
		"room_id": room.id,
		"active_flag": fire_active,
		"canonical_o2_ref": canonical_o2_ref,
		"o2_source_zone": o2_source_zone,
		"o2_source_zone_code": 1.0 if o2_source_zone == "upper" else 2.0,
		"extinction_o2_limit": extinction_limit,
		"canonical_o2_hrr_factor": canonical_factor,
		"legacy_o2_hrr_factor": legacy_factor,
		"legacy_hrr_kw": legacy_hrr_kw,
		"legacy_hrr_target_kw": legacy_target_kw,
		"accepted_hrr_kw": accepted_hrr_kw,
		"accepted_hrr_target_kw": accepted_target_kw,
		"decision_fraction": accepted_fraction,
		"throttle_fraction": throttle_fraction,
		"inventory_fraction": inventory_fraction,
		"requested_o2_kg": requested_o2_kg,
		"accepted_o2_kg": accepted_o2_kg,
		"requested_fuel_MJ": requested_fuel_MJ,
		"accepted_fuel_MJ": accepted_fuel_MJ,
		"requested_species_kg": requested_species,
		"accepted_species_kg": accepted_species,
		"dt_s": dt,
		"effective_chi_rad": effective_chi_rad,
		"requested_total_fire_energy_kj": requested_total_fire_energy_kj,
		"accepted_total_fire_energy_kj": accepted_total_fire_energy_kj,
		"requested_radiative_energy_kj": requested_radiative_energy_kj,
		"accepted_radiative_energy_kj": accepted_radiative_energy_kj,
		"canonical_fire_products_routing_active_flag": \
				1.0 if products_routing_active else 0.0,
		"canonical_fire_products_requested_convective_energy_kj": maxf(
			0.0,
			float(canonical_fire_products.get(
				"requested_convective_energy_kj", 0.0
			))
		),
		"canonical_fire_products_accepted_convective_energy_kj": maxf(
			0.0,
			float(canonical_fire_products.get(
				"accepted_convective_energy_kj", 0.0
			))
		),
		"canonical_fire_products_plume_driver_qc_kw": maxf(
			0.0,
			float(canonical_fire_products.get(
				"accepted_plume_driver_qc_kw", 0.0
			))
		),
		"canonical_fuel_object_sync_active_flag": \
				1.0 if fuel_object_sync_active else 0.0,
		"heat_scale": accepted_fraction,
		"plume_scale": pow(accepted_fraction, 1.0 / 3.0) if accepted_fraction > 0.0 else 0.0,
		"post_opening_coupling_active_flag": 1.0 if post_opening_lower_source else 0.0,
		"post_opening_source_switched_to_lower_flag": 1.0 \
				if post_opening_lower_source else 0.0,
		"post_opening_counterflow_exchange_kg": counterflow_exchange_kg,
		"post_opening_counterflow_incoming_o2_kg": counterflow_incoming_o2_kg,
		"post_opening_source_o2_available_kg": available_o2_kg,
		"post_opening_full_hrr_o2_demand_kg": requested_o2_kg,
		"post_opening_o2_supply_margin_kg": counterflow_incoming_o2_kg - requested_o2_kg,
		"zero_o2_flame_flag": 1.0 if canonical_o2_ref <= extinction_limit \
				and accepted_hrr_kw > 0.01 else 0.0,
		"fire_state_before": state_before,
		"fire_state_proposed": next_state,
	}
	if not canonical_fire_proposal.is_empty():
		for proposal_key in canonical_fire_proposal.keys():
			if proposal_key == "persistent_updates":
				continue
			transaction["canonical_fire_proposal_" + String(proposal_key)] = \
					canonical_fire_proposal[proposal_key]
	if not canonical_fire_products.is_empty():
		for products_key in canonical_fire_products.keys():
			transaction["canonical_fire_products_" + String(products_key)] = \
					canonical_fire_products[products_key]
	if not fuel_object_sync.is_empty():
		for sync_key in fuel_object_sync.keys():
			if sync_key == "proposed_ledger":
				continue
			transaction["canonical_fuel_object_sync_" + String(sync_key)] = \
					fuel_object_sync[sync_key]
	return transaction


func _snapshot_phase3_fire_state(room: RoomModel) -> Dictionary:
	var fire = room.fire if room != null else null
	return {
		"active_flag": fire != null,
		"hrr_kw": maxf(0.0, room.hrr_kw) if room != null else 0.0,
		"hrr_target_kw": maxf(0.0, room.hrr_target_kw) if room != null else 0.0,
		"o2_hrr_factor": clampf(room.o2_hrr_factor, 0.0, 1.0) if room != null else 1.0,
		"remaining_fuel_MJ": maxf(0.0, fire.remaining_fuel_MJ) if fire != null else 0.0,
		"retained_unburned_MJ": maxf(0.0, room.retained_unburned_MJ) \
				if room != null else 0.0,
		"fire_time_s": maxf(0.0, room.fire_time_s) if room != null else 0.0,
		"fire_dormant_time_s": maxf(0.0, room.fire_dormant_time_s) \
				if room != null else 0.0,
		"proposal_age_s": 0.0,
		"proposal_hrr_kw": 0.0,
		"proposal_target_kw": 0.0,
		"proposal_remaining_fuel_MJ": maxf(0.0, fire.fuel_energy_MJ) \
				if fire != null else 0.0,
		"product_profile": _snapshot_phase3_fire_product_profile(room, fire),
		"fuel_object_ledger": _snapshot_phase3_fuel_object_ledger(room),
		"growth_alpha_kw_s2": maxf(0.0, fire.growth_alpha_kw_s2) \
				if fire != null else 0.0,
		"max_hrr_kw": maxf(0.0, fire.max_hrr_kw) if fire != null else 0.0,
		"fuel_energy_MJ": maxf(0.0, fire.fuel_energy_MJ) if fire != null else 0.0,
		"secondary_hrr_gain_kw": maxf(0.0, fire.secondary_hrr_gain_kw) \
				if fire != null else 0.0,
		"flashover_hrr_multiplier": maxf(0.0, fire.flashover_hrr_multiplier) \
				if fire != null else 1.0,
		"flashover_triggered_flag": room.flashover_triggered \
				if room != null else false,
		"backdraft_active_flag": room.backdraft_active if room != null else false,
		"backdraft_triggered_flag": room.backdraft_triggered \
				if room != null else false,
		"fire_latent_active_flag": room.fire_latent_active if room != null else false,
		"o2_nominal": maxf(0.001, fire.o2_nominal) if fire != null else 0.209,
		"o2_min_for_flame": maxf(0.0, fire.o2_min_for_flame) if fire != null else 0.12,
		"o2_consumption_kg_per_MJ": maxf(0.0, fire.o2_consumption_kg_per_MJ) \
				if fire != null else 0.076,
		"hcl_kg": maxf(0.0, room.hcl_kg) if room != null else 0.0,
		"acrolein_kg": maxf(0.0, room.acrolein_kg) if room != null else 0.0,
		"formaldehyde_kg": maxf(0.0, room.formaldehyde_kg) if room != null else 0.0,
	}


func _snapshot_phase3_fire_product_profile(room: RoomModel, fire) -> Dictionary:
	var object_count: int = 0
	if room != null:
		for obj in room.fuel_objects:
			if obj != null and not _is_legacy_room_proxy(obj):
				object_count += 1
	return {
		"object_count": float(object_count),
		"object_sync_required_flag": 1.0 if object_count > 0 else 0.0,
		"smoke_yield_kg_per_MJ": _resolve_room_smoke_yield_kg_per_MJ(
			room, maxf(0.0, fire.smoke_yield_kg_per_MJ) if fire != null else 0.0
		),
		"soot_fraction": _resolve_room_soot_fraction(room, 1.0),
		"co_yield_kg_per_MJ": _resolve_room_co_yield_kg_per_MJ(room, -1.0),
		"co2_yield_kg_per_MJ": _resolve_room_co2_yield_kg_per_MJ(room, -1.0),
		"hcn_yield_kg_per_MJ": _resolve_room_hcn_base_yield_kg_per_MJ(room, -1.0),
		"hcl_yield_kg_per_MJ": _resolve_room_irritant_yield_kg_per_MJ(
			room, "hcl_yield_kg_per_MJ", -1.0
		),
		"acrolein_yield_kg_per_MJ": _resolve_room_irritant_yield_kg_per_MJ(
			room, "acrolein_yield_kg_per_MJ", -1.0
		),
		"formaldehyde_yield_kg_per_MJ": _resolve_room_irritant_yield_kg_per_MJ(
			room, "formaldehyde_yield_kg_per_MJ", -1.0
		),
		"chi_rad_normal": _resolve_room_chi_rad_normal(room, -1.0),
	}


func _snapshot_phase3_fuel_object_ledger(room: RoomModel) -> Array:
	var ledger: Array = []
	if room == null or not _has_explicit_fuel_objects(room):
		return ledger
	for obj in room.fuel_objects:
		if obj == null or _is_legacy_room_proxy(obj):
			continue
		var remaining_MJ: float = maxf(0.0, float(obj.remaining_fuel_MJ))
		var state_code: int = int(obj.state)
		var eligible: bool = remaining_MJ > 0.000000001 and (
			bool(obj.is_primary_ignition_source)
			or state_code == FuelObjectModelScript.State.PYROLYZING
			or state_code == FuelObjectModelScript.State.FLAMING
		)
		var weight: float = maxf(0.01, float(obj.max_hrr_kw)) \
				if eligible else 0.0
		if eligible and bool(obj.is_primary_ignition_source):
			weight *= 1.40
		ledger.append({
			"id": String(obj.id),
			"initial_fuel_MJ": maxf(0.0, float(obj.fuel_energy_MJ)),
			"remaining_fuel_MJ": remaining_MJ,
			"eligible_flag": eligible,
			"allocation_weight": weight,
			"state_code": float(state_code),
			"primary_flag": 1.0 if bool(obj.is_primary_ignition_source) else 0.0,
		})
	ledger.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.get("id", "")) < String(b.get("id", ""))
	)
	return ledger


func _phase3_combustion_species_proposal(
		room: RoomModel,
		dt: float,
		pre_state: Dictionary,
		legacy_species_result: Dictionary
	) -> Dictionary:
	var total: Dictionary = legacy_species_result.get("total_species_kg", {})
	return {
		"smoke": maxf(0.0, room.smoke_prod_kg_s * dt),
		"co": maxf(0.0, float(total.get("co", 0.0))),
		"co2": maxf(0.0, float(total.get("co2", 0.0))),
		"hcn": maxf(0.0, float(total.get("hcn", 0.0))),
		"hcl": maxf(0.0, room.hcl_kg - float(pre_state.get("hcl_kg", room.hcl_kg))),
		"acrolein": maxf(
			0.0,
			room.acrolein_kg - float(pre_state.get("acrolein_kg", room.acrolein_kg))
		),
		"formaldehyde": maxf(
			0.0,
			room.formaldehyde_kg - float(
				pre_state.get("formaldehyde_kg", room.formaldehyde_kg)
			)
		),
	}


func _scale_phase3_species(species: Dictionary, scale: float) -> Dictionary:
	var result: Dictionary = {}
	for species_name in species.keys():
		result[String(species_name)] = maxf(
			0.0, float(species.get(species_name, 0.0)) * clampf(scale, 0.0, 1.0)
		)
	return result


func _apply_species_generation_result(room: RoomModel, result: Dictionary) -> void:
	var total: Dictionary = result.get("total_species_kg", {})
	var upper: Dictionary = result.get("upper_species_kg", {})
	var co_kg: float = maxf(0.0, float(total.get("co", 0.0)))
	var co2_kg: float = maxf(0.0, float(total.get("co2", 0.0)))
	var hcn_kg: float = maxf(0.0, float(total.get("hcn", 0.0)))
	room.co_generated_kg_step = co_kg
	room.co2_generated_kg_step = co2_kg
	room.hcn_generated_kg_step = hcn_kg
	room.co_generated_kg_total += co_kg
	room.co_kg += co_kg
	room.co_upper_kg += maxf(0.0, float(upper.get("co", 0.0)))
	room.co2_kg += co2_kg
	room.co2_upper_kg += maxf(0.0, float(upper.get("co2", 0.0)))
	room.hcn_kg += hcn_kg
	room.hcn_upper_kg += maxf(0.0, float(upper.get("hcn", 0.0)))


func ensure_room_fuel_objects(room: RoomModel) -> void:
	if room == null:
		return

	if room.fuel_objects == null:
		room.fuel_objects = []

	# Si ya existe un proxy, no crear otro.
	if _get_legacy_room_proxy(room) != null:
		return

	if room.fuel_energy_MJ <= 0.0 and room.max_hrr_kw <= 0.0 and get_room_total_remaining_fuel_MJ(room) <= 0.0:
		return

	var proxy = FuelObjectModelScript.new()
	proxy.configure_from_legacy_room(room)
	room.fuel_objects.append(proxy)


func bootstrap_building(building: BuildingModel) -> void:
	if building == null:
		return

	for room_id in building.get_rooms().keys():
		var room: RoomModel = building.get_room(room_id)
		ensure_room_fuel_objects(room)


func create_legacy_room_fire(room: RoomModel, defaults: Dictionary) -> FireModel:
	if room == null:
		return null

	ensure_room_fuel_objects(room)
	if not _has_ignitable_fuel_object(room):
		return null
	_mark_room_ignition_object(room)

	var fire: FireModel = FireModelScript.new()
	fire.growth_alpha_kw_s2 = float(defaults.get("growth_alpha_kw_s2", fire.growth_alpha_kw_s2))
	fire.secondary_hrr_gain_kw = float(defaults.get("secondary_hrr_gain_kw", fire.secondary_hrr_gain_kw))
	fire.flashover_hrr_multiplier = float(defaults.get("flashover_hrr_multiplier", fire.flashover_hrr_multiplier))
	fire.flashover_min_hrr_kw = float(defaults.get("flashover_min_hrr_kw", fire.flashover_min_hrr_kw))
	fire.o2_nominal = float(defaults.get("o2_nominal", fire.o2_nominal))
	fire.o2_min_for_flame = float(defaults.get("o2_min_for_flame", fire.o2_min_for_flame))
	fire.smoke_yield_kg_per_MJ = float(defaults.get("smoke_yield_kg_per_MJ", fire.smoke_yield_kg_per_MJ))
	fire.o2_consumption_kg_per_MJ = float(defaults.get("o2_consumption_kg_per_MJ", fire.o2_consumption_kg_per_MJ))
	fire.max_hrr_kw = _resolve_room_max_hrr_kw(
		room,
		float(defaults.get("max_hrr_kw", fire.max_hrr_kw))
	)
	fire.fuel_energy_MJ = _resolve_room_fuel_energy_MJ(
		room,
		float(defaults.get("fuel_energy_MJ", fire.fuel_energy_MJ))
	)
	fire.remaining_fuel_MJ = fire.fuel_energy_MJ

	_sync_legacy_proxy_from_fire(room, fire, 0.0, false)
	return fire


func step_room_fire(room: RoomModel, dt: float, context: Dictionary) -> bool:
	if room == null:
		return false

	# SF-O1A/O1C/O1D/O2E1: zero per-step O₂ accumulators at the start of every engine tick.
	room.o2_consumed_kg_step_all = 0.0
	room.o2_consumed_bulk_kg_step = 0.0
	room.o2_consumed_fire_kg_step = 0.0
	room.o2_exterior_net_kg_step = 0.0
	room.o2_net_transport_kg_step = 0.0
	room.o2_zone_sync_kg_step = 0.0
	room.smoke_generated_kg_step = 0.0
	room.smoke_vented_kg_step = 0.0
	room.smoke_deposited_kg_step = 0.0
	room.smoke_net_transport_kg_step = 0.0

	if room.fire == null:
		var idle_o2_selection: Dictionary = _resolve_fire_o2_selection(room, null, context)
		room.fire_o2_mode_used = String(idle_o2_selection.get("mode", "legacy"))
		room.fire_o2_ref = float(idle_o2_selection.get("o2_ref", room.o2))
		room.fire_o2_min_ref = 0.0
		room.hrr_kw = 0.0
		room.hrr_target_kw = 0.0
		room.pyrolysis_kw = 0.0
		room.burned_hrr_kw = 0.0
		room.unburned_generation_kw = 0.0
		room.flame_hrr_target_kw = 0.0
		room.smolder_hrr_target_kw = 0.0
		room.pool_release_hrr_target_kw = 0.0
		room.smoke_prod_kg_s = 0.0
		room.fire_smoldering = false
		room.fire_latent_active = false
		room.combustion_regime = "EXTINGUISHED"
		_sync_legacy_proxy_idle(room)
		if bool(context.get(G3_OWNERSHIP_SWITCH, false)):
			_g3_end_tails(room)
		room.co_generated_kg_step = 0.0
		room.co2_generated_kg_step = 0.0
		room.hcn_generated_kg_step = 0.0
		room.o2_consumed_kg_step = 0.0
		room.fuel_consumed_MJ_step = 0.0
		if g3_fuel_ledger_enabled:
			_g3_ledger_begin(room, null, dt, context)
		return false

	var fire: FireModel = room.fire
	if g3_fuel_ledger_enabled:
		_g3_ledger_begin(room, fire, dt, context)
	var ambient_c: float = float(context.get("ambient_c", 20.0))
	var early_opening_signal: float = clampf(
		maxf(
			maxf(float(context.get("outside_open_factor", 0.0)), float(context.get("outside_open_path_factor", 0.0))),
			maxf(
				maxf(0.0, float(context.get("window_open_max", 0.0))),
				1.0 if _has_explicit_fire_o2_mode(context) else 0.0
			)
		),
		0.0,
		1.0
	)
	var full_hrr_o2: float = lerpf(
		fire.o2_nominal,
		float(context.get("fire_o2_full_hrr_open", fire.o2_nominal)),
		early_opening_signal
	)
	var o2_selection: Dictionary = _resolve_fire_o2_selection(room, fire, context)
	var o2_min_ref: float = float(o2_selection.get("o2_min_ref", fire.o2_min_for_flame))
	var o2_ref: float = float(o2_selection.get("o2_ref", room.o2))
	room.fire_o2_mode_used = String(o2_selection.get("mode", "legacy"))
	room.fire_o2_ref = o2_ref
	room.fire_o2_min_ref = o2_min_ref
	# Phase 5 M4: ILV upper-O2 throttle guard.
	# Cuando fire_o2_upper_throttle_enabled=true y el path two-zone eligió o2_lower como
	# referencia de throttle (plume_lower/blend), pero o2_upper ha caído por debajo del
	# umbral crítico: usar min(room.o2, room.o2_upper) en su lugar. Impide que el fuego
	# mantenga HRR alto ignorando el agotamiento de O₂ en la zona superior.
	# No-op exacto con flag false (default). No afecta modos upper/lower/interface explícitos.
	if bool(context.get("fire_o2_upper_throttle_enabled", false)):
		var _sel_mode: String = String(o2_selection.get("mode", "legacy"))
		if _sel_mode == "plume_lower" or _sel_mode == "plume_blend":
			var _upper_crit: float = float(context.get("fire_o2_upper_throttle_critical", 0.10))
			if room.o2_upper < _upper_crit:
				o2_ref = minf(room.o2, room.o2_upper)
				room.fire_o2_ref = o2_ref
	# Fuego prescrito: ignora la limitacion de O2 y sigue la curva t2.
	var o2_independent: bool = bool(context.get("fire_o2_independent", false))
	full_hrr_o2 = maxf(o2_min_ref + 0.001, full_hrr_o2)
	var raw_o2_factor: float = _compute_o2_factor(o2_ref, full_hrr_o2, o2_min_ref)
	var use_fds_extinction: bool = bool(context.get("fire_fds_extinction_enabled", false))
	var extinction_o2_limit: float = _compute_extinction_o2_limit(
		room,
		context,
		ambient_c,
		o2_min_ref
	)
	var extinction_factor: float = raw_o2_factor
	if use_fds_extinction:
		extinction_factor = _compute_extinction_factor(
			o2_ref,
			extinction_o2_limit,
			float(context.get("fire_fds_extinction_transition_width", 0.030))
		)
	var selected_o2_extinguished: bool = not o2_independent and (
		(not use_fds_extinction and o2_ref <= o2_min_ref)
		or (use_fds_extinction and o2_ref <= extinction_o2_limit)
	)
	var previous_hrr_kw: float = room.hrr_kw

	var smoke_fill_fraction: float = clampf(
		(room.height_m - clampf(room.h_layer_m, 0.0, room.height_m)) / maxf(0.1, room.height_m),
		0.0,
		1.0
	)
	var subvent_temp_factor: float = inverse_lerp(
		float(context.get("fire_subvent_temp_start_c", ambient_c)),
		float(context.get("fire_subvent_temp_full_c", ambient_c)),
		room.temp_upper_c
	)
	var subvent_fill_factor: float = inverse_lerp(
		float(context.get("fire_subvent_fill_start_fraction", 0.0)),
		float(context.get("fire_subvent_fill_full_fraction", 1.0)),
		smoke_fill_fraction
	)
	var subvent_engagement: float = clampf(maxf(subvent_temp_factor, subvent_fill_factor), 0.0, 1.0)
	var subvent_o2_floor: float = float(context.get("fire_subvent_o2_floor", 0.0)) \
			* clampf(subvent_temp_factor, 0.0, 1.0) \
			* clampf(subvent_fill_factor, 0.0, 1.0)
	var latent_enabled: bool = bool(context.get("fire_latent_enabled", true))
	var latent_viable: bool = latent_enabled and _can_sustain_latent_fire(
		room,
		fire,
		context,
		ambient_c
	)

	var o2_factor_target: float = extinction_factor if use_fds_extinction else raw_o2_factor
	if room.fire_time_s > 45.0:
		o2_factor_target = maxf(o2_factor_target, subvent_o2_floor)
	room.o2_hrr_factor = _smooth_state_value(
		room.o2_hrr_factor,
		o2_factor_target,
		dt,
		float(context.get("fire_o2_hrr_rise_tau_s", 14.0)),
		float(context.get("fire_o2_hrr_fall_tau_s", 32.0))
	)
	room.o2_hrr_factor = clampf(room.o2_hrr_factor, 0.0, 1.0)

	var flame_possible_factor: float = extinction_factor
	if not use_fds_extinction:
		flame_possible_factor = clampf(
			inverse_lerp(
				o2_min_ref - 0.015,
				o2_min_ref + 0.025,
				o2_ref
			),
			0.0,
			1.0
		)
	var flame_drive: float = room.o2_hrr_factor * flame_possible_factor
	var latent_drive: float = 0.0
	if latent_viable:
		latent_drive = subvent_o2_floor * lerpf(0.35, 1.0, subvent_engagement)
	var pyrolysis_drive: float = maxf(flame_drive, latent_drive)
	var can_flame: bool = flame_drive > 0.08
	if use_fds_extinction and not can_flame and room.temp_upper_c > ambient_c:
		var hot_pyrolysis_floor: float = float(context.get("fire_fds_extinction_pyrolysis_floor", 0.0)) \
				* subvent_engagement \
				* (1.0 - flame_possible_factor)
		pyrolysis_drive = maxf(pyrolysis_drive, hot_pyrolysis_floor)

	if o2_independent:
		# Fuego prescrito: ignora limitacion O2, HRR sigue curva t2 sin restriccion.
		pyrolysis_drive = 1.0
		can_flame = true
		room.o2_hrr_factor = 1.0
	if can_flame or latent_viable:
		var fire_time_gain_factor: float = clampf(
			maxf(0.15 if latent_viable else 0.0, pyrolysis_drive),
			0.0,
			1.0
		)
		room.fire_time_s += dt * fire_time_gain_factor
		if can_flame:
			room.fire_dormant_time_s = 0.0
			room.fire_o2_extinguished = false
		else:
			room.fire_dormant_time_s += dt
	else:
		room.fire_dormant_time_s += dt

	# G3 explicit_objects (OFF por defecto): energía y potencia solo de los objetos
	# activos al inicio del paso; los inactivos no aportan ni elevan el tope.
	var g3_owned: bool = _g3_explicit_owned_room(room, context)
	var g3_active: Array = []
	var g3_power_cap_kw: float = 0.0
	var g3_available_MJ: float = 0.0
	var g3_active_remaining_MJ: float = 0.0
	var g3_active_energy_MJ: float = 0.0
	var g3_burns: Array = []
	var g3_step_state: Dictionary = {}
	var g3_release_MJ: float = 0.0
	if g3_owned:
		for obj in room.fuel_objects:
			if not _explicit_object_is_active(room, obj):
				continue
			var obj_cap_kw: float = maxf(0.0, float(obj.max_hrr_kw))
			g3_active.append(obj)
			g3_power_cap_kw += obj_cap_kw
			g3_active_remaining_MJ += obj.remaining_fuel_MJ
			g3_active_energy_MJ += maxf(obj.remaining_fuel_MJ, float(obj.fuel_energy_MJ))
			g3_available_MJ += minf(obj.remaining_fuel_MJ, obj_cap_kw * dt / 1000.0)
		if g3_fuel_ledger_enabled:
			_g3_ledger_note(room, {"power_cap_kw": g3_power_cap_kw})

	var ideal_hrr_kw: float = fire.compute_hrr_kw(room.fire_time_s)
	var fuel_fraction: float = fire.remaining_fuel_MJ / maxf(0.001, fire.fuel_energy_MJ)
	if g3_owned:
		ideal_hrr_kw = minf(ideal_hrr_kw, g3_power_cap_kw)
		fuel_fraction = g3_active_remaining_MJ / maxf(0.001, g3_active_energy_MJ)
	var decay_factor: float = 1.0
	if fuel_fraction < 0.15:
		decay_factor = fuel_fraction / 0.15

	ideal_hrr_kw *= decay_factor
	var thermal_feedback_coeff: float = float(context.get("thermal_feedback_coeff", 0.0))
	var thermal_feedback_max: float = float(context.get("thermal_feedback_max", 1.0))
	var rad_feedback: float = 1.0 + thermal_feedback_coeff \
			* maxf(0.0, room.temp_upper_c - ambient_c) / 500.0
	rad_feedback = minf(rad_feedback, thermal_feedback_max)
	var feedback_o2_engagement: float = room.o2_hrr_factor if use_fds_extinction else clampf(
		inverse_lerp(
			o2_min_ref - 0.005,
			o2_min_ref + 0.035,
			o2_ref
		),
		0.0,
		1.0
	)
	rad_feedback = lerpf(1.0, rad_feedback, feedback_o2_engagement)
	ideal_hrr_kw *= rad_feedback
	if g3_owned:
		ideal_hrr_kw = minf(ideal_hrr_kw, g3_power_cap_kw)

	var smolder_fraction: float = float(context.get("fire_smolder_hrr_fraction", 0.10))
	var latent_cap_basis_kw: float = minf(fire.max_hrr_kw, maxf(previous_hrr_kw, ideal_hrr_kw))
	var extinction_hrr_kw: float = float(context.get("fire_extinction_hrr_kw", 0.0))
	if not can_flame and latent_viable:
		var dormant_decay: float = clampf(
			inverse_lerp(45.0, 120.0, room.fire_dormant_time_s),
			0.0,
			1.0
		)
		latent_cap_basis_kw = lerpf(
			latent_cap_basis_kw,
			maxf(previous_hrr_kw, extinction_hrr_kw * 0.5),
			dormant_decay
		)
	var latent_cap_scale: float = lerpf(
		float(context.get("fire_latent_hrr_cap_min_fraction", 0.15)),
		float(context.get("fire_latent_hrr_cap_max_fraction", 1.0)),
		subvent_engagement
	)
	var residual_smolder_cap_kw: float = maxf(
		extinction_hrr_kw * 0.25,
		latent_cap_basis_kw * smolder_fraction * latent_cap_scale
	)

	var pyrolysis_floor_fraction: float = 0.0
	if latent_viable:
		pyrolysis_floor_fraction = lerpf(
			float(context.get("fire_subvent_pyrolysis_min_fraction", 0.20)),
			float(context.get("fire_subvent_pyrolysis_max_fraction", 0.40)),
			subvent_engagement
		)
	var solid_pyrolysis_fraction: float = clampf(
		maxf(pyrolysis_drive, pyrolysis_floor_fraction),
		0.0,
		1.0
	)
	var solid_pyrolysis_kw: float = ideal_hrr_kw * solid_pyrolysis_fraction
	var fresh_flame_target_kw: float = 0.0
	if can_flame:
		fresh_flame_target_kw = minf(
			solid_pyrolysis_kw,
			ideal_hrr_kw * clampf(flame_drive, 0.0, 1.0)
		)
		# G3 DIAGNÓSTICO (clave ausente o 0: no se ejecuta nada de esto). Dentro de
		# la ventana (umbral, umbral + ancho) sustituye el objetivo de llama por una
		# recta que une el valor del umbral con el original en el borde superior.
		# No cambia can_flame, pirólisis, filtro, recorte de D, O2 ni especies.
		var g3_diag_window: float = float(context.get(G3_DIAG_FLAME_TARGET_WINDOW, 0.0))
		if g3_diag_window > 0.0:
			# El rescoldo que la regla da justo por debajo del umbral.
			var g3_diag_smolder_kw: float = 0.0
			if latent_viable:
				g3_diag_smolder_kw = minf(
					residual_smolder_cap_kw,
					solid_pyrolysis_kw * smolder_fraction * lerpf(0.40, 1.0, subvent_engagement)
				)
			var g3_diag_jump_fraction: float = clampf(
				float(context.get(G3_DIAG_FLAME_TARGET_JUMP_FRACTION, 0.0)), 0.0, 1.0
			)
			var g3_diag_original_kw: float = fresh_flame_target_kw
			fresh_flame_target_kw = minf(
				solid_pyrolysis_kw,
				g3_diag_flame_target_kw(
					g3_diag_original_kw, ideal_hrr_kw, flame_drive,
					g3_diag_smolder_kw, g3_diag_window, g3_diag_jump_fraction
				)
			)
			if g3_fuel_ledger_enabled and flame_drive < G3_DIAG_CAN_FLAME_DRIVE + g3_diag_window:
				_g3_ledger_note(room, {"diag_flame_target": {
					"window": g3_diag_window,
					"jump_fraction": g3_diag_jump_fraction,
					"flame_drive": flame_drive,
					"ideal_kw": ideal_hrr_kw,
					"smolder_at_threshold_kw": g3_diag_smolder_kw,
					"original_target_kw": g3_diag_original_kw,
					"target_kw": fresh_flame_target_kw,
				}})
	var smolder_target_kw: float = 0.0
	if not can_flame:
		if latent_viable:
			smolder_target_kw = minf(
				residual_smolder_cap_kw,
				solid_pyrolysis_kw * smolder_fraction * lerpf(0.40, 1.0, subvent_engagement)
			)
		else:
			smolder_target_kw = 0.0
	var retained_generation_kw: float = maxf(
		0.0,
		solid_pyrolysis_kw - fresh_flame_target_kw - smolder_target_kw
	) * float(context.get("fire_unburned_generation_fraction", 0.30))
	if not can_flame and latent_viable:
		# En fase latente no seguimos cargando la bolsa de gases retenidos.
		retained_generation_kw = 0.0

	var available_fuel_MJ: float = maxf(0.0, fire.remaining_fuel_MJ)
	if g3_owned:
		available_fuel_MJ = g3_available_MJ
	var solid_fuel_demand_MJ: float = solid_pyrolysis_kw * dt / 1000.0
	var g3_demand_unscaled_MJ: float = solid_fuel_demand_MJ
	var solid_fuel_scale: float = 1.0
	if solid_fuel_demand_MJ > 0.000001:
		solid_fuel_scale = minf(1.0, available_fuel_MJ / solid_fuel_demand_MJ)
	solid_pyrolysis_kw *= solid_fuel_scale
	fresh_flame_target_kw *= solid_fuel_scale
	smolder_target_kw *= solid_fuel_scale
	retained_generation_kw *= solid_fuel_scale
	solid_fuel_demand_MJ = solid_pyrolysis_kw * dt / 1000.0

	# F3.1: below the selected source's declared extinction limit there is no
	# oxidant available for pyrolysis heat release or retained-gas generation.
	# Apply this before updating the retained pool so the cutoff is atomic.
	if selected_o2_extinguished:
		solid_pyrolysis_kw = 0.0
		solid_fuel_demand_MJ = 0.0
		fresh_flame_target_kw = 0.0
		smolder_target_kw = 0.0
		retained_generation_kw = 0.0
	if g3_fuel_ledger_enabled:
		_g3_ledger_note(room, {
			"demand_unscaled_MJ": g3_demand_unscaled_MJ,
			"available_MJ": available_fuel_MJ,
			"fuel_scale": solid_fuel_scale,
			"demand_after_scale_MJ": solid_fuel_demand_MJ,
			"o2_extinguished": selected_o2_extinguished,
		})

	# M5 early guard: bloquea re-acumulación de gases sin quemar post-backdraft.
	# Condición: backdraft ya ocurrió, no estamos en la explosión activa, y O₂ aún no
	# ha superado el umbral de backdraft (mezcla demasiado pobre para re-acumular).
	# No-op cuando flag=false (default). No cambia física de combustión.
	if bool(context.get("fire_post_bd_hrr_cut_enabled", false)) \
			and room.backdraft_triggered \
			and not room.backdraft_active \
			and room.o2 < float(context.get("fire_backdraft_o2_max", 0.13)):
		retained_generation_kw = 0.0

	var pool_capacity_MJ: float = maxf(
		0.0,
		room.floor_area_m2() * float(context.get("fire_unburned_capacity_MJ_per_m2", 1.20))
	)
	var g3_bal_pool: Dictionary = {}
	if g3_fuel_ledger_enabled:
		g3_bal_pool = {
			"moment": "CombustionSystem.step_room_fire: tras cada escritura del deposito",
			"before_MJ": float(room.retained_unburned_MJ),
			"credit_requested_MJ": retained_generation_kw * dt / 1000.0,
			"capacity_MJ": pool_capacity_MJ,
		}
	room.retained_unburned_MJ = minf(
		pool_capacity_MJ,
		maxf(0.0, room.retained_unburned_MJ + retained_generation_kw * dt / 1000.0)
	)
	if g3_fuel_ledger_enabled:
		g3_bal_pool["after_credit_MJ"] = float(room.retained_unburned_MJ)

	var local_opening_signal: float = maxf(
		float(context.get("outside_open_factor", 0.0)),
		maxf(0.0, float(context.get("window_open_max", 0.0)))
	)
	var opening_signal: float = clampf(
		maxf(local_opening_signal, float(context.get("outside_open_path_factor", 0.0))),
		0.0,
		1.0
	)
	var temp_signal: float = clampf(
		inverse_lerp(
			float(context.get("fire_vent_response_temp_start_c", 140.0)),
			float(context.get("fire_vent_response_temp_full_c", 300.0)),
			room.temp_upper_c
		),
		0.0,
		1.0
	)
	var pool_signal: float = clampf(
		room.retained_unburned_MJ / maxf(1.0, pool_capacity_MJ * 0.35),
		0.0,
		1.0
	)
	var oxygen_recovery_signal: float = clampf(
		inverse_lerp(0.10, 0.45, room.o2_hrr_factor),
		0.0,
		1.0
	)
	var vent_response_target: float = opening_signal \
			* temp_signal \
			* maxf(pool_signal, oxygen_recovery_signal * 0.40)
	room.ventilation_response_factor = _smooth_state_value(
		room.ventilation_response_factor,
		vent_response_target,
		dt,
		float(context.get("fire_vent_response_rise_tau_s", 10.0)),
		float(context.get("fire_vent_response_fall_tau_s", 30.0))
	)
	room.ventilation_response_factor = clampf(room.ventilation_response_factor, 0.0, 1.0)

	var pool_release_target_kw: float = 0.0
	# Temporizador de re-armado del backdraft
	if room.backdraft_cooldown_s > 0.0:
		room.backdraft_cooldown_s = maxf(0.0, room.backdraft_cooldown_s - dt)
	if not selected_o2_extinguished \
			and room.retained_unburned_MJ > 0.001 \
			and opening_signal > 0.01:
		var release_drive: float = room.ventilation_response_factor * maxf(0.15, oxygen_recovery_signal)

		# ── LFL/UFL: comprobar que la mezcla gas/aire está en rango inflamable ──────
		# SF-AUD-013: masa de gas no quemado → volumen a densidad del gas de pirólisis.
		# Fracción volumétrica = vol_gas / vol_compartimento.
		# LFL ≈ 2% y UFL ≈ 20% para gas de pirólisis subventilado (CO/HC mix).
		var fuel_heat_kj_kg: float = float(context.get("fire_backdraft_fuel_heat_kj_kg", 10000.0))
		var fuel_density: float = maxf(0.1, float(context.get("fire_backdraft_fuel_gas_density", 0.8)))
		var fuel_kg: float = room.retained_unburned_MJ * 1000.0 / maxf(1.0, fuel_heat_kj_kg)
		var fuel_vol_m3: float = fuel_kg / fuel_density
		var room_vol: float = maxf(0.1, room.volume_m3())
		var fuel_vol_frac: float = fuel_vol_m3 / room_vol
		room.unburned_gas_vol_frac = fuel_vol_frac
		var lfl: float = float(context.get("fire_backdraft_lfl", 0.02))
		var ufl: float = float(context.get("fire_backdraft_ufl", 0.20))
		var mixture_flammable: bool = fuel_vol_frac >= lfl and fuel_vol_frac <= ufl

		var backdraft_ready: bool = room.retained_unburned_MJ \
				>= float(context.get("fire_backdraft_pool_threshold_MJ", 8.0)) \
				and room.o2 <= float(context.get("fire_backdraft_o2_max", 0.13)) \
				and room.temp_upper_c >= float(context.get("fire_backdraft_temp_min_c", 180.0)) \
				and opening_signal > 0.08 \
				and mixture_flammable
		if backdraft_ready:
			release_drive *= float(context.get("fire_backdraft_release_boost", 1.35))
			# Disparo del evento backdraft: acumulación de inquémados + entrada súbita de O2
			if not room.backdraft_active and room.backdraft_cooldown_s <= 0.0:
				room.backdraft_triggered = true
				room.backdraft_time_s = room.fire_time_s
				room.backdraft_active = true
				room.backdraft_phase_time_s = 0.0
				room.backdraft_cooldown_s = float(context.get("fire_backdraft_cooldown_s", 180.0))
				# Sobrepresión de deflagración instantánea — SF-AUD-013.
				# La combustión explosiva del gas acumulado genera una onda de
				# sobrepresión (ref: NFPA 921 §23; NIST backdraft experiments).
				var def_pa: float = float(context.get(
					"fire_backdraft_deflagration_overpressure_pa", 500.0
				))
				# F2.2C: con la red autoritativa hay un único propietario de la
				# presión; la deflagración no puede escribir encima del solver.
				if not bool(context.get("authoritative_transport_enabled", false)):
					room.overpressure_pa += def_pa

		# M7: solo liberar pool cuando hay suficiente O₂ para quemar.
		# Con O₂ < umbral de backdraft, el pool acumula gas sin quemar hasta que
		# una apertura introduce O₂ y dispara el backdraft.
		var o2_allows_pool_burn: bool = room.o2 >= float(context.get("fire_backdraft_o2_max", 0.13))
		if o2_allows_pool_burn:
			var release_tau_s: float = lerpf(
				float(context.get("fire_pool_release_tau_slow_s", 180.0)),
				float(context.get("fire_pool_release_tau_fast_s", 18.0)),
				room.ventilation_response_factor
			)
			var pool_release_cap_kw: float = fire.max_hrr_kw \
					* float(context.get("fire_pool_release_max_fraction", 0.18)) \
					* lerpf(0.55, 1.0, opening_signal)
			pool_release_target_kw = minf(
				room.retained_unburned_MJ * 1000.0 / maxf(1.0, release_tau_s),
				pool_release_cap_kw
			) * clampf(release_drive, 0.0, 2.0)

	if selected_o2_extinguished:
		pool_release_target_kw = 0.0

	var kawagoe_limit_kw: float = float(context.get("kawagoe_limit_kw", 0.0))
	room.pyrolysis_kw = maxf(0.0, solid_pyrolysis_kw)
	room.unburned_generation_kw = maxf(0.0, retained_generation_kw)
	room.flame_hrr_target_kw = maxf(0.0, fresh_flame_target_kw)
	room.smolder_hrr_target_kw = maxf(0.0, smolder_target_kw)
	room.pool_release_hrr_target_kw = maxf(0.0, pool_release_target_kw)
	room.hrr_target_kw = fresh_flame_target_kw + smolder_target_kw + pool_release_target_kw
	if not latent_viable and not can_flame and room.o2_hrr_factor < 0.02:
		room.hrr_target_kw = 0.0
	if kawagoe_limit_kw > 0.0:
		room.hrr_target_kw = minf(room.hrr_target_kw, kawagoe_limit_kw)
	room.hrr_target_kw = maxf(0.0, room.hrr_target_kw)

	var hrr_rise_tau_s: float = lerpf(
		float(context.get("fire_hrr_rise_tau_s", 6.0)) * 1.8,
		float(context.get("fire_hrr_rise_tau_s", 6.0)),
		room.ventilation_response_factor
	)
	room.hrr_kw = _smooth_state_value(
		previous_hrr_kw,
		room.hrr_target_kw,
		dt,
		hrr_rise_tau_s,
		float(context.get("fire_hrr_fall_tau_s", 20.0))
	)
	if not latent_viable \
			and room.hrr_target_kw <= 0.0 \
			and room.hrr_kw < float(context.get("fire_extinction_hrr_kw", 0.0)) * 0.25:
		room.hrr_kw = 0.0
	room.burned_hrr_kw = maxf(0.0, room.hrr_kw)

	# M-HRR mutation: multiplicador global de HRR para mutation testing.
	var _hrr_mult: float = float(context.get("fire_hrr_global_multiplier", 1.0))
	if _hrr_mult != 1.0 and room.hrr_kw > 0.0:
		room.hrr_kw *= _hrr_mult
		room.burned_hrr_kw = maxf(0.0, room.hrr_kw)

	# Backdraft: fase explosiva — pico de HRR con envolvente sinusoidal.
	# Gottuk (1992): backdraft genera picos de HRR 3-6× el máximo pre-extinción en <15 s.
	if room.backdraft_active:
		room.backdraft_phase_time_s += dt
		var bd_duration: float = float(context.get("fire_backdraft_duration_s", 12.0))
		if room.backdraft_phase_time_s >= bd_duration:
			room.backdraft_active = false
		else:
			var bd_progress: float = room.backdraft_phase_time_s / bd_duration
			var bd_envelope: float = sin(bd_progress * PI)  # 0→1→0 en [0, dur]
			var bd_hrr_kw: float = fire.max_hrr_kw \
					* float(context.get("fire_backdraft_hrr_multiplier", 4.0)) \
					* bd_envelope
			room.hrr_kw = maxf(room.hrr_kw, bd_hrr_kw)
			room.hrr_target_kw = maxf(room.hrr_target_kw, bd_hrr_kw)
			room.burned_hrr_kw = maxf(0.0, room.hrr_kw)

	if selected_o2_extinguished:
		_apply_selected_o2_extinction_guard(room)

	# M5 late guard: corta HRR zombie post-backdraft cuando no hay llama ni latencia.
	# Opera durante la ventana en que O₂ está agotado y el fuego no puede sustentar llama,
	# evitando que la inercia del smooth HRR genere filas A3 y O2E1 WARNs.
	# No-op cuando flag=false (default). No cambia física de combustión.
	if bool(context.get("fire_post_bd_hrr_cut_enabled", false)) \
			and room.backdraft_triggered \
			and not room.backdraft_active \
			and not can_flame \
			and not latent_viable:
		room.hrr_kw = 0.0
		room.hrr_target_kw = 0.0

	var total_target_kw: float = maxf(
		0.0001,
		fresh_flame_target_kw + smolder_target_kw + pool_release_target_kw
	)
	var actual_pool_burn_kw: float = room.hrr_kw * pool_release_target_kw / total_target_kw
	actual_pool_burn_kw = minf(actual_pool_burn_kw, room.retained_unburned_MJ * 1000.0 / maxf(0.001, dt))
	var actual_solid_burn_kw: float = maxf(0.0, room.hrr_kw - actual_pool_burn_kw)
	if g3_owned:
		# G3 Gate B opción D (prototipo): el débito del paso se asigna primero a
		# los objetos activos; el calor sólido es B0 = min(petición del filtro, T_s)
		# más la liberación del saldo R de cada dueño, acotada por el permiso de
		# potencia del modelo (flame_drive) Y por la cota de masa de O2 del
		# sumidero del fuego. Diseño: G3_ENERGY_DELAY_DESIGN §8–§9.
		g3_burns = _g3_allocate_owned(room, g3_active, solid_fuel_demand_MJ, dt, context)
		g3_step_state = _g3_option_d_step(
			room, g3_active, g3_burns, actual_solid_burn_kw, actual_pool_burn_kw,
			fresh_flame_target_kw + smolder_target_kw, solid_pyrolysis_kw,
			flame_drive, can_flame, selected_o2_extinguished, dt,
			fire.o2_consumption_kg_per_MJ, context
		)
		actual_solid_burn_kw = float(g3_step_state["solid_kw"])
		g3_release_MJ = float(g3_step_state["release_MJ"])
		room.hrr_kw = actual_solid_burn_kw + actual_pool_burn_kw
		room.burned_hrr_kw = maxf(0.0, room.hrr_kw)
	if g3_fuel_ledger_enabled:
		_g3_ledger_note(room, {
			"hrr_requested_kw": room.hrr_target_kw,
			"hrr_applied_kw": room.hrr_kw,
			"actual_solid_burn_kw": actual_solid_burn_kw,
			"actual_pool_burn_kw": actual_pool_burn_kw,
			"pool_generation_MJ": retained_generation_kw * dt / 1000.0,
			"flame_target_kw": fresh_flame_target_kw,
			"smolder_target_kw": smolder_target_kw,
			"pyrolysis_kw": solid_pyrolysis_kw,
		})
	if g3_fuel_ledger_enabled:
		_g3_ledger_note(room, {"bal_fuel": {
			"moment": "CombustionSystem.step_room_fire: tras el reparto solido/deposito",
			"flame_drive": flame_drive,
			"o2_hrr_factor": float(room.o2_hrr_factor),
			"can_flame": can_flame,
			"latent_viable": latent_viable,
			"o2_extinguished": selected_o2_extinguished,
			"pyrolysis_MJ": solid_pyrolysis_kw * dt / 1000.0,
			"flame_target_MJ": fresh_flame_target_kw * dt / 1000.0,
			"smolder_target_MJ": smolder_target_kw * dt / 1000.0,
			"pool_generation_MJ": retained_generation_kw * dt / 1000.0,
			"unburned_generation_fraction": float(context.get("fire_unburned_generation_fraction", 0.30)),
			# U: derivado, sin variable ni inventario en el motor.
			"unburned_without_inventory_MJ": (
				solid_pyrolysis_kw - fresh_flame_target_kw - smolder_target_kw - retained_generation_kw
			) * dt / 1000.0,
			"physical_inventory": false,
			"solid_heat_MJ": actual_solid_burn_kw * dt / 1000.0,
			"pool_heat_MJ": actual_pool_burn_kw * dt / 1000.0,
			"release_from_R_MJ": g3_release_MJ,
		}})
		g3_bal_pool["burn_requested_MJ"] = actual_pool_burn_kw * dt / 1000.0
	room.retained_unburned_MJ = maxf(
		0.0,
		room.retained_unburned_MJ - actual_pool_burn_kw * dt / 1000.0
	)
	if g3_fuel_ledger_enabled:
		g3_bal_pool["after_burn_MJ"] = float(room.retained_unburned_MJ)
	room.retained_unburned_MJ = maxf(
		0.0,
		room.retained_unburned_MJ - room.retained_unburned_MJ \
			* float(context.get("fire_unburned_decay_per_s", 0.0)) \
			* (1.0 + opening_signal * 1.5 + (1.0 - temp_signal) * 0.5) \
			* dt
	)
	if g3_fuel_ledger_enabled:
		g3_bal_pool["decay_per_s"] = float(context.get("fire_unburned_decay_per_s", 0.0))
		g3_bal_pool["opening_signal"] = opening_signal
		g3_bal_pool["temp_signal"] = temp_signal
		g3_bal_pool["after_decay_MJ"] = float(room.retained_unburned_MJ)

	# Backdraft: consume retained fuel explosivamente (bypass del límite pool_release_max_fraction)
	if room.backdraft_active and room.retained_unburned_MJ > 0.0:
		var bd_consume_MJ: float = minf(
			room.retained_unburned_MJ,
			room.hrr_kw * dt / 1000.0 * 0.60
		)
		room.retained_unburned_MJ = maxf(0.0, room.retained_unburned_MJ - bd_consume_MJ)

	if g3_fuel_ledger_enabled:
		g3_bal_pool["backdraft_active"] = bool(room.backdraft_active)
		g3_bal_pool["backdraft_hrr_kw"] = float(room.hrr_kw)
		g3_bal_pool["after_backdraft_MJ"] = float(room.retained_unburned_MJ)
		_g3_ledger_note(room, {"bal_pool": g3_bal_pool})

	var smoke_basis_multiplier: float = lerpf(
		1.0 + float(context.get("fire_smoke_basis_min_fraction", 0.0)),
		1.0,
		sqrt(room.o2_hrr_factor)
	)
	var retained_smoke_basis_kw: float = retained_generation_kw \
			* float(context.get("fire_retained_smoke_fraction", 0.38))
	var pool_smoke_basis_kw: float = actual_pool_burn_kw \
			* float(context.get("fire_pool_smoke_fraction", 0.42))
	var smoke_basis_kw: float = maxf(
		actual_solid_burn_kw,
		(fresh_flame_target_kw + smolder_target_kw) * smoke_basis_multiplier
	)
	smoke_basis_kw += retained_smoke_basis_kw + pool_smoke_basis_kw
	if not can_flame:
		if latent_viable:
			smoke_basis_kw = maxf(smoke_basis_kw, smolder_target_kw + retained_smoke_basis_kw)
		else:
			smoke_basis_kw = 0.0

	var base_smoke_yield_kg_per_MJ: float = _resolve_room_smoke_yield_kg_per_MJ(
		room,
		fire.smoke_yield_kg_per_MJ
	)
	var smoke_yield_kg_per_MJ: float = lerpf(
		base_smoke_yield_kg_per_MJ * float(context.get("fire_smoke_yield_low_o2_multiplier", 1.0)),
		base_smoke_yield_kg_per_MJ,
		room.o2_hrr_factor
	)
	if not can_flame:
		smoke_yield_kg_per_MJ *= float(context.get("fire_smolder_smoke_multiplier", 1.0))

	var smoke_basis_MJ: float = smoke_basis_kw * dt / 1000.0
	var heat_release_MJ: float = room.hrr_kw * dt / 1000.0
	room.smoke_prod_kg_s = _compute_smoke_production_kg_s(smoke_basis_kw, smoke_yield_kg_per_MJ)
	var g3_bal_species: Dictionary = {}
	if g3_fuel_ledger_enabled:
		g3_bal_species = {
			"moment": "CombustionSystem.step_room_fire: humo antes de las extinciones; gases alrededor de la escritura",
			"committed": false,
			"smoke": {
				"solid_heat_term_kw": actual_solid_burn_kw,
				"flame_target_kw": fresh_flame_target_kw,
				"smolder_target_kw": smolder_target_kw,
				"basis_multiplier": smoke_basis_multiplier,
				"retained_term_kw": retained_smoke_basis_kw,
				"pool_term_kw": pool_smoke_basis_kw,
				"basis_kw": smoke_basis_kw,
				"yield_base_kg_per_MJ": base_smoke_yield_kg_per_MJ,
				"yield_kg_per_MJ": smoke_yield_kg_per_MJ,
				"requested_kg": float(room.smoke_prod_kg_s) * dt,
			},
		}
		_g3_ledger_note(room, {"bal_species": g3_bal_species})
	# SF-AUD-008: fracción de smoke_kg que es soot ópticamente activo (K_m = 8700 m²/kg).
	room.soot_fraction = _resolve_room_soot_fraction(room, 1.0)
	# SF-AUD-015: fracción radiativa bien ventilada por combustible (-1.0 = usar global del motor).
	room.chi_rad_normal = _resolve_room_chi_rad_normal(room, -1.0)

	var latent_timeout_s: float = float(
		context.get("fire_latent_extinction_delay_s", context.get("fire_extinction_delay_s", 0.0))
	)
	if not can_flame \
			and latent_viable \
			and room.fire_dormant_time_s >= latent_timeout_s:
		if room.retained_unburned_MJ < 0.5 or room.hrr_kw <= extinction_hrr_kw:
			if g3_owned:
				_g3_note_uncommitted(room, g3_step_state, actual_pool_burn_kw)
			return _extinguish_room_fire(room, fire)

	var extinction_delay_s: float = float(context.get("fire_extinction_delay_s", 0.0))
	if not can_flame \
			and not latent_viable \
			and room.fire_dormant_time_s >= extinction_delay_s:
		if g3_owned:
			_g3_note_uncommitted(room, g3_step_state, actual_pool_burn_kw)
		return _extinguish_room_fire(room, fire)

	var starvation_factor: float = extinction_factor if use_fds_extinction else raw_o2_factor
	var oxygen_starved: bool = room.fire_time_s > 60.0 \
			and starvation_factor <= float(context.get("fire_starvation_o2_factor", 0.0)) \
			and room.retained_unburned_MJ < 0.5
	var heat_release_collapsed: bool = room.hrr_target_kw <= extinction_hrr_kw * 0.25
	if not (not can_flame and latent_viable) \
			and (room.hrr_kw < extinction_hrr_kw or oxygen_starved or heat_release_collapsed) \
			and room.fire_time_s > 60.0:
		room.fire_low_hrr_time_s += dt
		if room.fire_low_hrr_time_s >= extinction_delay_s:
			if g3_owned:
				_g3_note_uncommitted(room, g3_step_state, actual_pool_burn_kw)
			return _extinguish_room_fire(room, fire)
	else:
		room.fire_low_hrr_time_s = 0.0

	var combustion_completion_factor: float = clampf(
		fresh_flame_target_kw / maxf(0.001, solid_pyrolysis_kw),
		0.0,
		1.0
	)
	# Equivalence ratio φ: cuantas veces mas combustible se gasifica del que puede
	# quemarse estequiometricamente con el O2 disponible.
	# φ=1 → combustion completa (bien ventilado).
	# φ>1 → subventilado → CO y soot aumentan drasticamente.
	# Para smoldering (sin llama): φ fijo alto para reproducir emision de CO elevada.
	# Referencia: Beyler (1986) SFPE; Gottuk & Roby, SFPE Handbook §3.4;
	# Pitts, NIST TN 1603 (especies en fuegos ISO 9705 subventilados).
	var phi: float
	if can_flame:
		# φ = razón de combustible disponible / capacidad de combustión con O2 actual.
		# Usar o2_hrr_factor (suavizado, 0-1 según O2 disponible) como proxy:
		# φ=1 cuando O2=nominal (bien ventilado), φ→10 cuando O2→o2_min_for_flame.
		# Beyler (1986): CO aumenta exponencialmente cuando φ>1 (subventilado).
		phi = clampf(1.0 / maxf(0.01, room.o2_hrr_factor), 1.0, 10.0)
	else:
		# Smoldering: combustion muy incompleta, phi efectiva alta
		phi = float(context.get("fire_smolder_phi", 4.0))
	var co_base_yield: float = _resolve_room_co_yield_kg_per_MJ(
		room,
		float(context.get("co_base_yield_kg_per_MJ", 0.0))
	)
	var co_max_yield: float = float(context.get("co_max_yield_kg_per_MJ", 0.0))
	# CO yield sube exponencialmente con phi para phi > 1.
	# y_CO = y_CO_base * exp(k * (phi - 1)), con k = fire_co_phi_rate.
	# k=2.0 → ~7x a phi=2, ~55x a phi=3, capeado en co_max_yield.
	var k_phi_co: float = float(context.get("fire_co_phi_rate", 2.0))
	var co_yield: float = clampf(
		co_base_yield * exp(k_phi_co * (phi - 1.0)),
		co_base_yield,
		co_max_yield
	)
	# Phase 2: CO vent-limited via o2_upper (Beyler 1986, NIST TN 1603).
	# Cuando el O2 de la zona superior cae bajo el umbral, la combustión en la
	# interfaz upper/lower genera CO masivamente (fuego subventilado real).
	# El engagement es suave: 0 % a o2_upper=threshold, 100 % a o2_upper=threshold/2.
	var co_vent_threshold: float = float(context.get("fire_co_vent_limited_o2_threshold", 0.12))
	var co_vent_multiplier: float = float(context.get("fire_co_vent_limited_multiplier", 1.0))
	if can_flame and co_vent_multiplier > 1.0 and room.o2_upper < co_vent_threshold:
		var vent_engagement: float = clampf(
			inverse_lerp(co_vent_threshold, co_vent_threshold * 0.5, room.o2_upper),
			0.0,
			1.0
		)
		co_yield = lerpf(co_yield, co_yield * co_vent_multiplier, vent_engagement)
		co_yield = minf(co_yield, co_max_yield * co_vent_multiplier)
	# R2-6: CO afterburning inhibition in two-zone mode (Gottuk & Roby, SFPE §3.4).
	# When o2_upper drops below threshold, CO oxidation to CO2 is inhibited — CO
	# accumulates instead. Only activates when no explicit multiplier override is set.
	var two_zone_co_active: bool = bool(context.get("two_zone_solver_enabled", false))
	var co_vent_explicit: bool = co_vent_multiplier > 1.0
	if two_zone_co_active and not co_vent_explicit and can_flame:
		var afterburn_threshold: float = float(context.get("fire_co_afterburn_o2_threshold", 0.15))
		var afterburn_max_boost: float = float(context.get("fire_co_afterburn_max_boost", 30.0))
		if room.o2_upper < afterburn_threshold:
			var t: float = clampf(
				inverse_lerp(afterburn_threshold, afterburn_threshold * 0.4, room.o2_upper),
				0.0, 1.0
			)
			co_yield = minf(co_yield * (1.0 + (afterburn_max_boost - 1.0) * t), co_max_yield)
	if not can_flame and latent_viable:
		co_yield *= float(context.get("fire_latent_co_yield_multiplier", 1.0))
	# Permite fijar un yield constante desde el caso (ej. para comparación CFAST que
	# usa CO_YIELD fijo por kg de combustible sin escalar con la relación de equivalencia).
	var co_yield_force: float = float(context.get("fire_co_yield_force_kg_per_MJ", -1.0))
	if co_yield_force >= 0.0:
		co_yield = co_yield_force
	var retained_co_basis_kw: float = retained_generation_kw \
			* float(context.get("fire_retained_co_fraction", 0.08))
	var pool_co_basis_kw: float = actual_pool_burn_kw \
			* float(context.get("fire_pool_co_fraction", 0.40))
	var co_basis_kw: float = actual_solid_burn_kw + pool_co_basis_kw + retained_co_basis_kw
	if not can_flame and latent_viable:
		co_basis_kw = maxf(co_basis_kw, smolder_target_kw * 0.75 + retained_co_basis_kw)
	var co_basis_MJ: float = co_basis_kw * dt / 1000.0
	var generated_co_kg: float = co_yield * co_basis_MJ
	# room.co_kg / co_upper_kg se añaden más abajo, tras el balance de C (SF-AUD-032).

	# HCN yield: tambien aumenta con phi (mas combustion incompleta = mas HCN).
	# SF-AUD-006: el yield base se resuelve por combustible segun su contenido de N.
	# Madera ~0.00004, PU flexible ~0.001-0.004, Nylon ~0.003-0.010 kg/MJ (ISO 19706).
	var hcn_global_base: float = float(context.get("hcn_base_yield_kg_per_MJ", 0.0))
	var hcn_base_yield: float = _resolve_room_hcn_base_yield_kg_per_MJ(room, hcn_global_base)
	# El maximo escala proporcionalmente: si un objeto N-rico tiene base 25x mayor,
	# su maximo tambien es 25x mayor (mantiene la relacion base/max = 1/6.25).
	var hcn_global_max: float = float(context.get("hcn_max_yield_kg_per_MJ", 0.0))
	var hcn_max_yield: float = maxf(
		hcn_global_max,
		hcn_base_yield * (hcn_global_max / maxf(hcn_global_base, 0.000001))
	)
	# HCN se acumula en generated_hcn_kg y se aplica DESPUÉS del balance de C (SF-AUD-032).
	var generated_hcn_kg: float = 0.0
	if hcn_base_yield > 0.0:
		var hcn_yield: float = clampf(
			hcn_base_yield * exp(k_phi_co * (phi - 1.0)),
			hcn_base_yield,
			hcn_max_yield
		)
		generated_hcn_kg = hcn_yield * co_basis_MJ
		if g3_fuel_ledger_enabled:
			g3_bal_species["hcn_yield_kg_per_MJ"] = hcn_yield

	# HCl, acroleína, formaldehído — SF-AUD-018 (FEC irritantes, ISO 13571 §A.3).
	# Default yield = 0.0 → retrocompatible. Solo activos si el combustible tiene Cl / es PU/madera.
	# HCl: solo materiales con Cl (PVC). No aumenta con phi (no es producto de combustion incompleta).
	if g3_fuel_ledger_enabled:
		g3_bal_species["irritants"] = {
			"basis_kw": co_basis_kw,
			"hcl_before_kg": float(room.hcl_kg),
			"acrolein_before_kg": float(room.acrolein_kg),
			"formaldehyde_before_kg": float(room.formaldehyde_kg),
			"acrolein_yield_kg_per_MJ": 0.0,
			"formaldehyde_yield_kg_per_MJ": 0.0,
		}
	var hcl_yield: float = _resolve_room_irritant_yield_kg_per_MJ(room, "hcl_yield_kg_per_MJ", 0.0)
	if hcl_yield > 0.0:
		room.hcl_kg += hcl_yield * co_basis_MJ
	# Acroleína y formaldehído aumentan con combustión incompleta (phi > 1), como CO.
	var acrolein_yield: float = _resolve_room_irritant_yield_kg_per_MJ(room, "acrolein_yield_kg_per_MJ", 0.0)
	if acrolein_yield > 0.0:
		var acrolein_yield_eff: float = clampf(
			acrolein_yield * exp(k_phi_co * (phi - 1.0) * 0.7),
			acrolein_yield,
			acrolein_yield * 4.0
		)
		room.acrolein_kg += acrolein_yield_eff * co_basis_MJ
		if g3_fuel_ledger_enabled:
			g3_bal_species["irritants"]["acrolein_yield_kg_per_MJ"] = acrolein_yield_eff
	var formaldehyde_yield: float = _resolve_room_irritant_yield_kg_per_MJ(room, "formaldehyde_yield_kg_per_MJ", 0.0)
	if formaldehyde_yield > 0.0:
		var formaldehyde_yield_eff: float = clampf(
			formaldehyde_yield * exp(k_phi_co * (phi - 1.0) * 0.5),
			formaldehyde_yield,
			formaldehyde_yield * 3.0
		)
		room.formaldehyde_kg += formaldehyde_yield_eff * co_basis_MJ
		if g3_fuel_ledger_enabled:
			g3_bal_species["irritants"]["formaldehyde_yield_kg_per_MJ"] = formaldehyde_yield_eff
	if g3_fuel_ledger_enabled:
		g3_bal_species["irritants"]["hcl_yield_kg_per_MJ"] = hcl_yield
		g3_bal_species["irritants"]["hcl_after_kg"] = float(room.hcl_kg)
		g3_bal_species["irritants"]["acrolein_after_kg"] = float(room.acrolein_kg)
		g3_bal_species["irritants"]["formaldehyde_after_kg"] = float(room.formaldehyde_kg)

	# CO2 decrece a medida que mas carbono va a CO en lugar de CO2.
	# Balance aproximado de carbono: a phi=3, ~40% del carbono forma CO en vez de CO2.
	# Lineal: y_CO2 = lerp(co2_min, co2_base, max(0, 1 - (phi-1)/co2_phi_decay_rate)).
	# co2_phi_decay_rate=2.5 → y_CO2 llega al minimo en phi=3.5 (Pitts, NIST TN 1603).
	# SF-AUD-005: co2_base puede ser por combustible (co2_yield_kg_per_MJ en FuelObjectModel).
	# co2_min escala proporcionalmente al base para mantener la relacion min/base constante.
	var co2_base_global: float = float(context.get("co2_base_yield_kg_per_MJ", 0.0831))
	var co2_base: float = _resolve_room_co2_yield_kg_per_MJ(room, co2_base_global)
	var co2_min_global: float = float(context.get("co2_min_yield_kg_per_MJ", 0.0594))
	var co2_min: float = co2_base * (co2_min_global / maxf(0.0001, co2_base_global))
	var co2_phi_t: float = clampf(1.0 - (phi - 1.0) / float(context.get("co2_phi_decay_rate", 2.5)), 0.0, 1.0)
	var co2_yield: float = lerpf(co2_min, co2_base, co2_phi_t)
	var generated_co2_kg: float = co2_yield * maxf(heat_release_MJ, smoke_basis_MJ * 0.60)

	# SF-AUD-032: balance elemental de carbono.
	# El total de C en productos gaseosos (CO + CO₂ + HCN) no puede superar el C
	# disponible en el combustible sólido quemado en este paso.
	# Referencia: NFPA 921 §5.5; SFPE Handbook Table 3.4-1; Pitts NIST TN 1603.
	# fuel_c_kg_per_MJ ≈ carbono disponible por MJ liberado (madera=0.027, PU=0.024).
	# Nota: el carbono en soot/humo se contabiliza por separado en SmokeModel; aquí
	# se conservan las especies gaseosas principales que forman el gas tóxico de capas.
	var c_per_MJ: float = float(context.get("fuel_c_kg_per_MJ", 0.027))
	var c_avail_kg: float = solid_fuel_demand_MJ * c_per_MJ
	var c_in_co: float = generated_co_kg * (12.0 / 28.0)
	var c_in_co2: float = generated_co2_kg * (12.0 / 44.0)
	var c_in_hcn: float = generated_hcn_kg * (12.0 / 27.0)
	var c_total: float = c_in_co + c_in_co2 + c_in_hcn
	var c_in_soot: float = room.smoke_prod_kg_s * dt * 0.87
	# G3 opción D: el calor liberado desde el saldo R quema pirolizado debitado en
	# pasos anteriores; su carbono cuenta para el tope de especies del paso (las
	# especies siguen al HRR aplicado), no para c_burned_total (ya se contó al
	# debitarse). Sin liberación, c_clamp_kg == c_avail_kg exactamente.
	var c_clamp_kg: float = c_avail_kg
	if g3_release_MJ > 0.0:
		c_clamp_kg = c_avail_kg + g3_release_MJ * c_per_MJ
	# SF-CBAL: registrar el exceso real solicitado por los yields ANTES del clamp.
	# Diagnóstico SF-CBAL: siempre contra el carbono del combustible del paso; en
	# un paso con liberación de R incluye el carbono diferido de R (declarado).
	room.c_preclamp_excess_kg += maxf(0.0, c_total + c_in_soot - c_avail_kg)
	if g3_fuel_ledger_enabled:
		g3_bal_species["co"] = {
			"solid_heat_term_kw": actual_solid_burn_kw,
			"pool_term_kw": pool_co_basis_kw,
			"retained_term_kw": retained_co_basis_kw,
			"smolder_target_kw": smolder_target_kw,
			"basis_kw": co_basis_kw,
			"phi": phi,
			"yield_base_kg_per_MJ": co_base_yield,
			"yield_kg_per_MJ": co_yield,
			"requested_kg": generated_co_kg,
		}
		g3_bal_species["hcn"] = {
			"basis_kw": co_basis_kw,
			"yield_base_kg_per_MJ": hcn_base_yield,
			"yield_kg_per_MJ": float(g3_bal_species.get("hcn_yield_kg_per_MJ", 0.0)),
			"requested_kg": generated_hcn_kg,
		}
		g3_bal_species.erase("hcn_yield_kg_per_MJ")
		g3_bal_species["co2"] = {
			"heat_term_MJ": heat_release_MJ,
			"smoke_basis_term_MJ": smoke_basis_MJ * 0.60,
			"yield_base_kg_per_MJ": co2_base,
			"yield_min_kg_per_MJ": co2_min,
			"yield_kg_per_MJ": co2_yield,
			"requested_kg": generated_co2_kg,
		}
		g3_bal_species["carbon_clamp"] = {
			"c_kg_per_MJ": c_per_MJ,
			"fuel_debit_MJ": solid_fuel_demand_MJ,
			"release_from_R_MJ": g3_release_MJ,
			"c_available_kg": c_avail_kg,
			"c_clamp_kg": c_clamp_kg,
			"c_requested_gas_kg": c_total,
			"c_in_soot_kg": c_in_soot,
			"soot_inside_clamp": false,
			"applied": false,
			"scale": 1.0,
		}
	if c_clamp_kg > 0.0 and c_total > c_clamp_kg:
		var c_scale: float = c_clamp_kg / c_total
		if g3_fuel_ledger_enabled:
			g3_bal_species["carbon_clamp"]["applied"] = true
			g3_bal_species["carbon_clamp"]["scale"] = c_scale
		generated_co_kg *= c_scale
		generated_co2_kg *= c_scale
		generated_hcn_kg *= c_scale
	# Fracción de carbono POST-clamp (diagnóstico SF-AUD-032).
	# Siempre ≤ 1.0; confirma que la conservación se cumple paso a paso.
	if c_clamp_kg > 0.0:
		var c_produced: float = generated_co_kg * (12.0 / 28.0) \
				+ generated_co2_kg * (12.0 / 44.0) \
				+ generated_hcn_kg * (12.0 / 27.0)
		room.c_balance_frac = c_produced / c_clamp_kg
	else:
		room.c_balance_frac = 0.0
	# SF-D2: tracking estequiométrico de O2 (Thornton, default-off).
	# OxygenExchangeSystem ya aplica esta tasa sobre o2_upper (líneas 386-395) y room.o2
	# (línea 356) usando fire.o2_consumption_kg_per_MJ. Aquí solo contabilizamos para
	# diagnóstico sin modificar o2_upper (evita doble-descuento).
	# Flag: fire_o2_stoich_consumption_enabled=false (no activa por defecto).
	if bool(context.get("fire_o2_stoich_consumption_enabled", false)):
		var hrr_energy_MJ_step: float = maxf(0.0, room.hrr_kw) * dt / 1000.0
		var o2_consumed_kg: float = hrr_energy_MJ_step * fire.o2_consumption_kg_per_MJ
		room.o2_consumed_kg_step = o2_consumed_kg
		room.o2_consumed_kg_total += o2_consumed_kg
	else:
		room.o2_consumed_kg_step = 0.0

	# SF-CBAL: la fuente canónica es el carbono consumido del combustible PRE-clamp.
	# La fracción no representada por especies se mantiene como producto no modelado.
	var c_products_postclamp: float = generated_co_kg * (12.0 / 28.0) \
			+ generated_co2_kg * (12.0 / 44.0) \
			+ generated_hcn_kg * (12.0 / 27.0) \
			+ c_in_soot
	room.c_burned_total_kg += c_avail_kg
	room.c_untracked_products_kg += maxf(0.0, c_avail_kg - c_products_postclamp)
	room.c_postclamp_excess_kg += maxf(0.0, c_products_postclamp - c_avail_kg)

	# Phase 2G — término fuente CO zona lower en generación (experimental, default OFF).
	# Cuando flag ON: una fracción de generated_co_kg se asigna al lower implícito;
	# co_kg total no cambia — sólo co_upper_kg recibe (1 - fracción) * generated_co_kg.
	var _p2g_upper_frac: float = 1.0
	if bool(context.get("phase2g_co_lower_source_enabled", false)):
		var _p2g_frac: float = float(context.get("phase2g_co_lower_source_fraction", 0.0))
		var _p2g_guard: String = String(context.get("phase2g_co_lower_source_guard", "fire_room_only"))
		var _p2g_apply: bool = false
		match _p2g_guard:
			"only_when_hot_layer_above_1_8m":
				_p2g_apply = float(context.get("hot_layer_interface_m", 2.5)) > 1.8
			_: # "fire_room_only" y "all_rooms_with_fire" — siempre aplica en sala con fuego
				_p2g_apply = true
		if _p2g_apply:
			_p2g_upper_frac = 1.0 - clampf(_p2g_frac, 0.0, 1.0)
	var species_generation_result: Dictionary = {
		"cause": "combustion_species_source",
		"room_id": room.id,
		# Preserve the exact post-clamp legacy totals; upper/lower are the zonal split.
		"total_species_kg": {
			"co": generated_co_kg,
			"co2": generated_co2_kg,
			"hcn": generated_hcn_kg,
		},
		"upper_species_kg": {
			"co": generated_co_kg * _p2g_upper_frac,
			"co2": generated_co2_kg,
			"hcn": generated_hcn_kg,
		},
		"lower_species_kg": {
			"co": generated_co_kg * (1.0 - _p2g_upper_frac),
			"co2": 0.0,
			"hcn": 0.0,
		},
	}
	if bool(context.get("phase3_canonical_zone_shadow_enabled", false)):
		# F3.0d: registrar el resultado post-clamp antes de cualquier write de especies.
		_phase3_shadow_species_results.append(species_generation_result.duplicate(true))
	if g3_fuel_ledger_enabled:
		g3_bal_species["co"]["applied_kg"] = generated_co_kg
		g3_bal_species["co"]["applied_upper_kg"] = generated_co_kg * _p2g_upper_frac
		g3_bal_species["co2"]["applied_kg"] = generated_co2_kg
		g3_bal_species["hcn"]["applied_kg"] = generated_hcn_kg
		g3_bal_species["inventory_before"] = _g3_balance_gas_inventory(room)
	_apply_species_generation_result(room, species_generation_result)
	if g3_fuel_ledger_enabled:
		g3_bal_species["inventory_after"] = _g3_balance_gas_inventory(room)
		g3_bal_species["committed"] = true
	if g3_fuel_ledger_enabled:
		_g3_ledger_note(room, {
			"species": {
				"co_kg": generated_co_kg,
				"co2_kg": generated_co2_kg,
				"hcn_kg": generated_hcn_kg,
				"smoke_kg": room.smoke_prod_kg_s * dt,
			},
			"consumed_MJ": solid_fuel_demand_MJ,
		})

	fire.remaining_fuel_MJ = maxf(0.0, fire.remaining_fuel_MJ - solid_fuel_demand_MJ)
	# SF-E1: capturar consumo de combustible sólido para auditoría de balance energético.
	room.fuel_consumed_MJ_step = solid_fuel_demand_MJ
	room.fuel_consumed_MJ_total += solid_fuel_demand_MJ
	# SF-O2E1: acumular energía HRR liberada (kJ). Tracking-only — no modifica física.
	# OES aplica Thornton sobre hrr_kw; este acumulador permite verificar la coherencia
	# entre ambos subsistemas: delta(o2_consumed_kg_total_all) ≈ delta(hrr_kj_total) * 7.6e-5.
	room.hrr_kj_total += maxf(0.0, room.hrr_kw) * dt
	if g3_owned:
		_g3_apply_owned(room, g3_active, g3_burns, g3_step_state, can_flame)
		# El FireModel refleja el inventario de objetos: un único propietario.
		fire.remaining_fuel_MJ = get_room_total_remaining_fuel_MJ(room)
	else:
		_sync_explicit_objects_from_active_fire(
			room,
			actual_solid_burn_kw,
			solid_fuel_demand_MJ,
			can_flame,
			dt,
			context
		)

	_sync_legacy_proxy_from_fire(room, fire, room.hrr_kw, can_flame)

	# Actualizar flag de smoldering para UI y exportación.
	# "smoldering" = fuego latente activo (sin llama) con emisión de humo/CO visible.
	room.fire_latent_active = (not can_flame) and latent_viable
	room.fire_smoldering = (not can_flame) and latent_viable and (room.hrr_kw > 0.5)
	# Fase 1/2 ILV: clasificador diagnóstico read-only — no altera física.
	room.combustion_regime = CombustionRegimeClassifierScript.classify(room)

	if fire.remaining_fuel_MJ <= 0.0 and room.retained_unburned_MJ <= 0.01:
		return _extinguish_room_fire(room, fire, true)

	if room.fire_time_s >= float(context.get("fire_max_active_s", 0.0)) \
			and room.retained_unburned_MJ <= 0.5:
		return _extinguish_room_fire(room, fire)

	return true


func is_any_object_autoignite_ready(room: RoomModel) -> bool:
	if room == null:
		return false
	for obj in room.fuel_objects:
		if _should_skip_object_for_room(room, obj):
			continue
		if bool(obj.autoignite_ready):
			return true
	return false


func get_room_total_remaining_fuel_MJ(room: RoomModel) -> float:
	if room == null:
		return 0.0

	var total_MJ: float = 0.0
	var ignore_legacy_proxy: bool = _has_explicit_fuel_objects(room)
	for obj in room.fuel_objects:
		if obj == null:
			continue
		if ignore_legacy_proxy and _is_legacy_room_proxy(obj):
			continue
		total_MJ += maxf(0.0, obj.remaining_fuel_MJ)
	return total_MJ


func get_room_total_max_hrr_kw(room: RoomModel) -> float:
	if room == null:
		return 0.0

	var total_kw: float = 0.0
	var ignore_legacy_proxy: bool = _has_explicit_fuel_objects(room)
	for obj in room.fuel_objects:
		if obj == null:
			continue
		if ignore_legacy_proxy and _is_legacy_room_proxy(obj):
			continue
		total_kw += maxf(0.0, obj.max_hrr_kw)
	return total_kw


func get_room_legacy_proxy_remaining_fuel_MJ(room: RoomModel) -> float:
	var proxy = _get_legacy_room_proxy(room)
	if proxy == null:
		return 0.0
	return maxf(0.0, proxy.remaining_fuel_MJ)


func get_room_active_object_count(room: RoomModel) -> int:
	if room == null:
		return 0

	var count: int = 0
	for obj in room.fuel_objects:
		if _should_skip_object_for_room(room, obj):
			continue
		if obj.state == FuelObjectModelScript.State.PYROLYZING or obj.state == FuelObjectModelScript.State.FLAMING:
			count += 1
	return count


func get_room_heating_object_count(room: RoomModel) -> int:
	if room == null:
		return 0

	var count: int = 0
	for obj in room.fuel_objects:
		if _should_skip_object_for_room(room, obj):
			continue
		if obj.state == FuelObjectModelScript.State.HEATING:
			count += 1
	return count


func get_room_pyrolyzing_object_count(room: RoomModel) -> int:
	if room == null:
		return 0

	var count: int = 0
	for obj in room.fuel_objects:
		if _should_skip_object_for_room(room, obj):
			continue
		if obj.state == FuelObjectModelScript.State.PYROLYZING:
			count += 1
	return count


func get_room_flaming_object_count(room: RoomModel) -> int:
	if room == null:
		return 0

	var count: int = 0
	for obj in room.fuel_objects:
		if _should_skip_object_for_room(room, obj):
			continue
		if obj.state == FuelObjectModelScript.State.FLAMING:
			count += 1
	return count


func get_room_passive_surface_temp_c(room: RoomModel) -> float:
	var obj = _get_dominant_fuel_object(room)
	return obj.surface_temp_c if obj != null else 0.0


func get_room_passive_flux_kw_m2(room: RoomModel) -> float:
	var obj = _get_dominant_fuel_object(room)
	return obj.incident_heat_flux_kw_m2 if obj != null else 0.0


func get_room_passive_ignition_flux_kw_m2(room: RoomModel) -> float:
	var obj = _get_dominant_fuel_object(room)
	return obj.ignition_flux_kw_m2 if obj != null else 18.0


func is_room_passive_autoignite_ready(room: RoomModel) -> bool:
	return is_any_object_autoignite_ready(room)


func generalize_room_combustion_after_flashover(room: RoomModel) -> void:
	if room == null or not _has_explicit_fuel_objects(room):
		return

	for obj in room.fuel_objects:
		if _should_skip_object_for_room(room, obj):
			continue
		if obj.remaining_fuel_MJ <= 0.001:
			continue

		obj.state = FuelObjectModelScript.State.FLAMING
		obj.surface_temp_c = maxf(obj.surface_temp_c, obj.ignition_temp_c + 80.0)
		obj.exposure_s = maxf(obj.exposure_s, 90.0)
		obj.autoignite_ready = false
		if String(obj.ignited_by_object_id).is_empty():
			obj.ignited_by_object_id = "flashover"


func get_room_dominant_fuel_object_id(room: RoomModel) -> String:
	var obj = _get_dominant_fuel_object(room)
	return String(obj.id) if obj != null else ""


func get_room_dominant_fuel_object_name(room: RoomModel) -> String:
	var obj = _get_dominant_fuel_object(room)
	return String(obj.name) if obj != null else ""


func get_room_dominant_fuel_object_state(room: RoomModel) -> String:
	var obj = _get_dominant_fuel_object(room)
	return fuel_object_state_to_string(int(obj.state)) if obj != null else "none"


func get_room_dominant_fuel_object_exposure_s(room: RoomModel) -> float:
	var obj = _get_dominant_fuel_object(room)
	return float(obj.exposure_s) if obj != null else 0.0


func get_room_dominant_fuel_object_remaining_MJ(room: RoomModel) -> float:
	var obj = _get_dominant_fuel_object(room)
	return maxf(0.0, obj.remaining_fuel_MJ) if obj != null else 0.0


func fuel_object_state_to_string(state: int) -> String:
	match state:
		FuelObjectModelScript.State.COLD:
			return "cold"
		FuelObjectModelScript.State.HEATING:
			return "heating"
		FuelObjectModelScript.State.PYROLYZING:
			return "pyrolyzing"
		FuelObjectModelScript.State.FLAMING:
			return "flaming"
		FuelObjectModelScript.State.DECAYING:
			return "decaying"
		FuelObjectModelScript.State.BURNED_OUT:
			return "burned_out"
		_:
			return "unknown"


func update_passive_room_fuel(
	room: RoomModel,
	dt: float,
	ambient_c: float,
	context: Dictionary = {}
) -> bool:
	if room == null:
		return false

	if room.fire != null:
		return false

	ensure_room_fuel_objects(room)
	var any_autoignite_ready: bool = false
	for obj in room.fuel_objects:
		if _should_skip_object_for_room(room, obj):
			continue
		if _update_passive_fuel_object(room, obj, dt, ambient_c, context):
			any_autoignite_ready = true

	return any_autoignite_ready


func _update_passive_fuel_object(
	room: RoomModel,
	obj,
	dt: float,
	ambient_c: float,
	context: Dictionary = {}
) -> bool:
	if obj == null:
		return false

	if obj.remaining_fuel_MJ <= 0.001:
		obj.state = FuelObjectModelScript.State.BURNED_OUT
		obj.hrr_kw = 0.0
		obj.incident_heat_flux_kw_m2 = 0.0
		obj.autoignite_ready = false
		return false

	var hot_fill_fraction: float = clampf(
		(room.height_m - clampf(room.thermal_layer_m, 0.0, room.height_m)) / maxf(0.1, room.height_m),
		0.0,
		1.0
	)
	var smoke_fill_fraction: float = clampf(
		(room.height_m - clampf(room.h_layer_m, 0.0, room.height_m)) / maxf(0.1, room.height_m),
		0.0,
		1.0
	)
	var smoke_layer_depth_m: float = maxf(0.0, room.height_m - clampf(room.h_layer_m, 0.0, room.height_m))
	var smoke_volume_m3: float = maxf(0.1, room.floor_area_m2() * maxf(0.1, smoke_layer_depth_m))
	var smoke_density_signal: float = clampf(room.smoke_kg / maxf(0.02, smoke_volume_m3 * 0.08), 0.0, 1.0)
	var smoke_radiation_factor: float = maxf(smoke_fill_fraction, smoke_density_signal)
	var coupled_fill_fraction: float = maxf(hot_fill_fraction, smoke_fill_fraction)
	var object_height_factor: float = clampf(
		inverse_lerp(0.0, maxf(0.1, room.height_m), float(obj.elevation_m)),
		0.0,
		1.0
	)
	var upper_influence: float = clampf(
		0.10 + 0.72 * coupled_fill_fraction + 0.12 * object_height_factor,
		0.12,
		0.90
	)
	var upper_target_surface_temp_c: float = lerpf(
		room.temp_lower_c,
		room.temp_upper_c,
		upper_influence
	)
	var opening_gas_temp_c: float = maxf(
		room.temp_lower_c,
		float(context.get("opening_gas_temp_c", room.temp_lower_c))
	)
	var opening_engagement: float = clampf(
		float(context.get("opening_engagement", 0.0)),
		0.0,
		1.0
	)
	var adjacent_source_hrr_kw: float = maxf(
		0.0,
		float(context.get("adjacent_source_hrr_kw", 0.0))
	)
	var upper_radiation_flux_kw_m2: float = _estimate_radiative_flux_kw_m2(
		room.temp_upper_c,
		obj.surface_temp_c,
		0.82
	) * clampf(0.08 + 0.60 * hot_fill_fraction + 0.28 * smoke_radiation_factor, 0.08, 0.96)
	var doorway_radiation_flux_kw_m2: float = _estimate_radiative_flux_kw_m2(
		opening_gas_temp_c,
		obj.surface_temp_c,
		0.70
	) * opening_engagement * 0.85
	var layer_convective_flux_kw_m2: float = maxf(0.0, room.temp_upper_c - obj.surface_temp_c) \
			* 0.006 \
			* coupled_fill_fraction
	var doorway_convective_flux_kw_m2: float = maxf(0.0, opening_gas_temp_c - obj.surface_temp_c) \
			* lerpf(0.0, 0.018, opening_engagement)
	var flame_bonus_flux_kw_m2: float = minf(
		6.0,
		adjacent_source_hrr_kw * 0.0008 * opening_engagement
	)
	# Radiación directa desde sala adyacente en llamas — independiente del flujo convectivo.
	# Cubre la fase temprana cuando la capa caliente no ha alcanzado el dintel todavía.
	var adjacent_fire_temp_c: float = maxf(
		room.temp_lower_c,
		float(context.get("adjacent_fire_temp_c", 0.0))
	)
	var adjacent_rad_engagement: float = clampf(
		float(context.get("adjacent_rad_engagement", 0.0)), 0.0, 0.50
	)
	var direct_fire_rad_flux_kw_m2: float = _estimate_radiative_flux_kw_m2(
		adjacent_fire_temp_c, obj.surface_temp_c, 0.80
	) * adjacent_rad_engagement
	obj.incident_heat_flux_kw_m2 = upper_radiation_flux_kw_m2 \
			+ doorway_radiation_flux_kw_m2 \
			+ layer_convective_flux_kw_m2 \
			+ doorway_convective_flux_kw_m2 \
			+ flame_bonus_flux_kw_m2 \
			+ direct_fire_rad_flux_kw_m2

	var flux_ratio: float = clampf(
		obj.incident_heat_flux_kw_m2 / maxf(1.0, obj.ignition_flux_kw_m2),
		0.0,
		1.25
	)
	var opening_target_surface_temp_c: float = lerpf(
		upper_target_surface_temp_c,
		maxf(upper_target_surface_temp_c, opening_gas_temp_c),
		opening_engagement
	)
	var target_surface_temp_c: float = lerpf(
		upper_target_surface_temp_c,
		opening_target_surface_temp_c,
		clampf(0.25 + 0.55 * flux_ratio, 0.0, 1.0)
	)
	var exposed_area_factor: float = clampf(
		maxf(0.1, float(obj.exposed_area_m2)) / maxf(0.1, float(obj.footprint_m2)),
		0.35,
		2.0
	)
	var heating_rate: float = clampf(dt / maxf(5.0, lerpf(210.0, 35.0, flux_ratio)) * sqrt(exposed_area_factor), 0.0, 1.0)
	var cooling_rate: float = clampf(dt / 240.0, 0.0, 1.0)
	if target_surface_temp_c >= obj.surface_temp_c:
		obj.surface_temp_c = lerpf(obj.surface_temp_c, target_surface_temp_c, heating_rate)
	else:
		obj.surface_temp_c = lerpf(obj.surface_temp_c, target_surface_temp_c, cooling_rate)

	var heating_threshold_c: float = ambient_c + 35.0
	var pyrolysis_threshold_c: float = obj.ignition_temp_c - 45.0
	var heating_flux_threshold_kw_m2: float = obj.ignition_flux_kw_m2 * 0.30
	var pyrolysis_flux_threshold_kw_m2: float = obj.ignition_flux_kw_m2 * 0.70

	var thermal_signal: float = clampf(
		inverse_lerp(heating_threshold_c, obj.ignition_temp_c, obj.surface_temp_c),
		0.0,
		1.0
	)
	var flux_signal: float = clampf(
		inverse_lerp(heating_flux_threshold_kw_m2, obj.ignition_flux_kw_m2, obj.incident_heat_flux_kw_m2),
		0.0,
		1.0
	)
	var preheat_signal: float = maxf(thermal_signal, flux_signal)

	if preheat_signal > 0.0:
		obj.exposure_s += dt * lerpf(0.35, 1.35, preheat_signal)
	else:
		obj.exposure_s = maxf(0.0, obj.exposure_s - dt * 1.5)

	var pyrolysis_ready: bool = (
		obj.surface_temp_c >= pyrolysis_threshold_c
		or obj.incident_heat_flux_kw_m2 >= pyrolysis_flux_threshold_kw_m2
	) and obj.exposure_s >= 30.0
	var autoignite_ready: bool = obj.exposure_s >= 75.0 and (
		obj.surface_temp_c >= obj.ignition_temp_c
		or (
			pyrolysis_ready
			and obj.incident_heat_flux_kw_m2 >= obj.ignition_flux_kw_m2
		)
	)
	obj.autoignite_ready = autoignite_ready

	if pyrolysis_ready:
		obj.state = FuelObjectModelScript.State.PYROLYZING
	elif obj.surface_temp_c >= heating_threshold_c \
			or obj.incident_heat_flux_kw_m2 >= heating_flux_threshold_kw_m2:
		obj.state = FuelObjectModelScript.State.HEATING
	else:
		obj.state = FuelObjectModelScript.State.COLD

	obj.hrr_kw = 0.0
	obj.t_ignition_s = -1.0

	# SF-AUD-016: MLR física (Tewarson): ṁ = (q_inc − q_crit) × A_eff / ΔHg; hrr = ṁ × ΔHc.
	# Solo activa cuando ΔHg y ΔHc están configurados explícitamente (> 0); sentinel -1.0 = modelo heredado.
	if obj.state == FuelObjectModelScript.State.PYROLYZING \
			and float(obj.heat_of_gasification_kj_kg) > 0.0 \
			and float(obj.heat_of_combustion_kj_kg) > 0.0:
		# SF-AUD-034: LOI — si O2 de sala < LOI, el material no puede arder en aire empobrecido.
		if float(obj.loi_fraction) > 0.0 and room.o2 < float(obj.loi_fraction):
			obj.state = FuelObjectModelScript.State.HEATING
			obj.hrr_kw = 0.0
			return false
		# SF-AUD-034: char layer — atenúa el flujo efectivo mediante resistencia térmica.
		# R_char [m²K/kW] = char_thickness / k_char; factor adimensional = R_char × h_ref (0.025 kW/m²K).
		var q_inc_eff_kw_m2: float = obj.incident_heat_flux_kw_m2
		if float(obj.char_thickness_m) > 0.0 and float(obj.k_char_kw_m_k) > 0.0:
			var R_char: float = float(obj.char_thickness_m) / maxf(1.0e-9, float(obj.k_char_kw_m_k))
			q_inc_eff_kw_m2 = obj.incident_heat_flux_kw_m2 / maxf(1.0, 1.0 + R_char * 0.025)
		var q_net_kw_m2: float = maxf(0.0,
			q_inc_eff_kw_m2 - float(obj.critical_heat_flux_kw_m2))
		var A_eff_m2: float = maxf(0.0,
			float(obj.exposed_area_m2) if float(obj.exposed_area_m2) > 0.001
			else float(obj.footprint_m2) * 0.5)
		# ṁ [kg/s] = q_net [kW/m²] × A [m²] / ΔHg [kJ/kg]
		var mlr_kg_s: float = q_net_kw_m2 * A_eff_m2 / float(obj.heat_of_gasification_kj_kg)
		# hrr [kW] = ṁ [kg/s] × ΔHc [kJ/kg]; acotado por 35% del max_hrr_kw en fase pre-ignición
		obj.hrr_kw = clampf(mlr_kg_s * float(obj.heat_of_combustion_kj_kg),
			0.0, maxf(0.0, float(obj.max_hrr_kw)) * 0.35)
		# Auto-extinción: si el flujo cae bajo el 70% del umbral crítico, la combustión no es sostenible
		if obj.incident_heat_flux_kw_m2 < float(obj.critical_heat_flux_kw_m2) * 0.70:
			obj.state = FuelObjectModelScript.State.HEATING
			obj.hrr_kw = 0.0

	return autoignite_ready


func _resolve_room_fuel_energy_MJ(room: RoomModel, fallback_MJ: float) -> float:
	if room == null:
		return fallback_MJ
	if room.fuel_energy_MJ > 0.0:
		return room.fuel_energy_MJ

	var total_remaining_MJ: float = get_room_total_remaining_fuel_MJ(room)
	if total_remaining_MJ > 0.0:
		return total_remaining_MJ

	return fallback_MJ


func _resolve_room_max_hrr_kw(room: RoomModel, fallback_kw: float) -> float:
	if room == null:
		return fallback_kw
	if room.max_hrr_kw > 0.0:
		return room.max_hrr_kw

	var total_max_kw: float = get_room_total_max_hrr_kw(room)
	if total_max_kw > 0.0:
		return total_max_kw

	return fallback_kw


func _resolve_fire_o2_selection(room: RoomModel, fire: FireModel, context: Dictionary) -> Dictionary:
	var mode: String = _resolve_fire_o2_mode(context)
	var o2_min_ref: float = fire.o2_min_for_flame if fire != null else 0.0
	var o2_ref: float = room.o2
	if mode == "upper":
		o2_ref = room.o2_upper
		if fire != null and not _has_explicit_fire_o2_mode(context):
			o2_min_ref = float(context.get("fire_o2_upper_min_for_flame", fire.o2_min_for_flame))
	elif mode == "lower":
		o2_ref = room.o2_lower
	elif mode == "interface":
		# Primera aproximacion M2: muestra en la banda de mezcla de la interfaz.
		o2_ref = lerpf(room.o2_lower, room.o2_upper, 0.5)
	else:
		# R2-2: en modo two-zone, el fuego consume O₂ de la capa donde se encuentra.
		# Mientras la interfaz de capa esté por encima del fuego → pluma entrana desde
		# la capa inferior (o2_lower, cercano al ambiente). Cuando la interfaz desciende
		# sobre el fuego → se usa o2_upper (capa caliente y empobrecida en O₂).
		# Transición suave en una banda de 0.3 m alrededor de la interfaz/fuego.
		# Equivalente al modelo de entrenamiento de CFAST (Allen & Quintiere, 1982).
		var two_zone_active: bool = bool(context.get("two_zone_solver_enabled", false))
		if two_zone_active and not _has_explicit_fire_o2_mode(context):
			var interface_m: float = float(context.get("hot_layer_interface_m", room.height_m))
			# Zona de transición: 0.0 m (base del fuego/suelo) a 0.3 m (altura mínima llama)
			var fire_base_m: float = 0.0
			var transition_m: float = 0.3
			if interface_m >= fire_base_m + transition_m:
				# Interfaz por encima del fuego: pluma en zona fría → usa o2_lower
				o2_ref = room.o2_lower
				mode = "plume_lower"
			elif interface_m <= fire_base_m:
				# Fuego completamente inmerso en capa caliente → usa o2_upper
				o2_ref = room.o2_upper
				mode = "plume_upper"
			else:
				# Interfaz dentro de la banda de transición → interpola
				var t: float = (interface_m - fire_base_m) / transition_m
				o2_ref = lerpf(room.o2_upper, room.o2_lower, t)
				mode = "plume_blend"
		else:
			var upper_blend: float = clampf(
				float(context.get("fire_o2_upper_hrr_blend", 0.0)),
				0.0,
				1.0
			)
			o2_ref = lerpf(room.o2, minf(room.o2, room.o2_upper), upper_blend)
	return {
		"mode": mode,
		"o2_ref": o2_ref,
		"o2_min_ref": o2_min_ref
	}


func _resolve_fire_o2_mode(context: Dictionary) -> String:
	var mode: String = String(context.get("fire_o2_mode", "legacy")).strip_edges().to_lower()
	if mode == "upper" or mode == "lower" or mode == "interface":
		return mode
	# Compatibilidad exacta: los flags historicos solo se interpretan bajo legacy.
	if bool(context.get("fire_o2_upper_for_flame", false)):
		return "upper"
	if bool(context.get("fire_o2_lower_for_flame", false)):
		return "lower"
	return "legacy"


func _has_explicit_fire_o2_mode(context: Dictionary) -> bool:
	var mode: String = String(context.get("fire_o2_mode", "legacy")).strip_edges().to_lower()
	return mode == "upper" or mode == "lower" or mode == "interface"


func _compute_o2_factor(o2: float, nominal: float, min_o2: float) -> float:
	if o2 <= min_o2:
		return 0.0

	var o2_ratio: float = (o2 - min_o2) / maxf(0.001, nominal - min_o2)
	return clampf(o2_ratio, 0.0, 1.0)


func _compute_extinction_o2_limit(
	room: RoomModel,
	context: Dictionary,
	ambient_c: float,
	fallback_min_o2: float
) -> float:
	if not bool(context.get("fire_fds_extinction_enabled", false)):
		return fallback_min_o2
	if room == null:
		return fallback_min_o2

	var ambient_limit: float = float(context.get("fire_fds_extinction_o2_limit_ambient", 0.135))
	var ambient_ref_c: float = float(context.get("fire_fds_extinction_ambient_c", ambient_c))
	var hot_gas_c: float = maxf(
		ambient_ref_c + 1.0,
		float(context.get("fire_fds_extinction_hot_gas_c", 900.0))
	)
	var hot_floor: float = clampf(
		float(context.get("fire_fds_extinction_hot_o2_floor", 0.105)),
		0.0,
		ambient_limit
	)
	var gas_temp_c: float = maxf(room.temp_upper_c, ambient_c)
	var hot_fraction: float = clampf(
		(gas_temp_c - ambient_ref_c) / maxf(1.0, hot_gas_c - ambient_ref_c),
		0.0,
		1.0
	)

	return clampf(
		lerpf(ambient_limit, hot_floor, hot_fraction),
		0.0,
		float(context.get("o2_nominal", 0.209))
	)


func _compute_extinction_factor(o2: float, o2_limit: float, transition_width: float) -> float:
	var width: float = maxf(0.001, transition_width)
	return clampf((o2 - o2_limit) / width, 0.0, 1.0)


func _compute_smoke_production_kg_s(hrr_kw: float, smoke_yield_kg_per_MJ: float) -> float:
	var hrr_MJ_s: float = maxf(0.0, hrr_kw) / 1000.0
	return hrr_MJ_s * maxf(0.0, smoke_yield_kg_per_MJ)


func _resolve_room_smoke_yield_kg_per_MJ(room: RoomModel, fallback_yield: float) -> float:
	if room == null or not _has_explicit_fuel_objects(room):
		return fallback_yield

	var weighted_yield: float = 0.0
	var total_weight: float = 0.0
	for obj in room.fuel_objects:
		if _should_skip_object_for_room(room, obj):
			continue
		if obj.remaining_fuel_MJ <= 0.001:
			continue

		var object_yield: float = maxf(0.0, float(obj.smoke_yield_kg_per_MJ))
		if object_yield <= 0.0:
			continue

		var preheat_fraction: float = clampf(_fuel_object_preheat_score(obj) / 8.0, 0.0, 1.0)
		var weight: float = maxf(1.0, obj.max_hrr_kw) * lerpf(0.35, 1.0, preheat_fraction)
		if bool(obj.is_primary_ignition_source):
			weight *= 1.40
		if obj.state == FuelObjectModelScript.State.FLAMING:
			weight *= 1.35
		elif obj.state == FuelObjectModelScript.State.PYROLYZING:
			weight *= 1.20

		weighted_yield += object_yield * weight
		total_weight += weight

	if total_weight <= 0.000001:
		return fallback_yield

	return weighted_yield / total_weight


func _resolve_room_co_yield_kg_per_MJ(room: RoomModel, fallback_yield: float) -> float:
	if room == null or not _has_explicit_fuel_objects(room):
		return fallback_yield

	var weighted_yield: float = 0.0
	var total_weight: float = 0.0
	for obj in room.fuel_objects:
		if _should_skip_object_for_room(room, obj):
			continue
		if obj.remaining_fuel_MJ <= 0.001:
			continue

		var object_yield: float = maxf(0.0, float(obj.co_yield_kg_per_MJ))
		if object_yield <= 0.0:
			continue

		var preheat_fraction: float = clampf(_fuel_object_preheat_score(obj) / 8.0, 0.0, 1.0)
		var weight: float = maxf(1.0, obj.max_hrr_kw) * lerpf(0.35, 1.0, preheat_fraction)
		if bool(obj.is_primary_ignition_source):
			weight *= 1.40
		if obj.state == FuelObjectModelScript.State.FLAMING:
			weight *= 1.35
		elif obj.state == FuelObjectModelScript.State.PYROLYZING:
			weight *= 1.20

		weighted_yield += object_yield * weight
		total_weight += weight

	if total_weight <= 0.000001:
		return fallback_yield

	return weighted_yield / total_weight


func _resolve_room_soot_fraction(room: RoomModel, fallback_fraction: float) -> float:
	# SF-AUD-008: fracción soot ponderada por HRR de objetos activos.
	# Determina qué parte de smoke_kg es ópticamente activa (K_m = 8700 m²/kg).
	# Retrocompatible: objetos sin soot_fraction propio (= 1.0) conservan visibilidad original.
	if room == null or not _has_explicit_fuel_objects(room):
		return fallback_fraction

	var weighted_frac: float = 0.0
	var total_weight: float = 0.0
	for obj in room.fuel_objects:
		if _should_skip_object_for_room(room, obj):
			continue
		if obj.remaining_fuel_MJ <= 0.001:
			continue

		var preheat_fraction: float = clampf(_fuel_object_preheat_score(obj) / 8.0, 0.0, 1.0)
		var weight: float = maxf(1.0, obj.max_hrr_kw) * lerpf(0.35, 1.0, preheat_fraction)
		if bool(obj.is_primary_ignition_source):
			weight *= 1.40
		if obj.state == FuelObjectModelScript.State.FLAMING:
			weight *= 1.35
		elif obj.state == FuelObjectModelScript.State.PYROLYZING:
			weight *= 1.20

		weighted_frac += clampf(float(obj.soot_fraction), 0.0, 1.0) * weight
		total_weight += weight

	if total_weight <= 0.000001:
		return fallback_fraction

	return clampf(weighted_frac / total_weight, 0.0, 1.0)


func _resolve_room_co2_yield_kg_per_MJ(room: RoomModel, fallback_yield: float) -> float:
	# SF-AUD-005: CO₂ yield base ponderado por HRR de objetos activos.
	# Sentinel -1.0 en el objeto = excluir de la ponderación (usa fallback global).
	# Retrocompatible: si ningún objeto define co2_yield_kg_per_MJ > 0, devuelve fallback.
	if room == null or not _has_explicit_fuel_objects(room):
		return fallback_yield

	var weighted_yield: float = 0.0
	var total_weight: float = 0.0
	for obj in room.fuel_objects:
		if _should_skip_object_for_room(room, obj):
			continue
		if obj.remaining_fuel_MJ <= 0.001:
			continue

		var object_yield: float = float(obj.co2_yield_kg_per_MJ)
		if object_yield < 0.0:
			continue  # sentinel: no contribuye a la media ponderada

		var preheat_fraction: float = clampf(_fuel_object_preheat_score(obj) / 8.0, 0.0, 1.0)
		var weight: float = maxf(1.0, obj.max_hrr_kw) * lerpf(0.35, 1.0, preheat_fraction)
		if bool(obj.is_primary_ignition_source):
			weight *= 1.40
		if obj.state == FuelObjectModelScript.State.FLAMING:
			weight *= 1.35
		elif obj.state == FuelObjectModelScript.State.PYROLYZING:
			weight *= 1.20

		weighted_yield += object_yield * weight
		total_weight += weight

	if total_weight <= 0.000001:
		return fallback_yield

	return maxf(0.0, weighted_yield / total_weight)


func _resolve_room_chi_rad_normal(room: RoomModel, fallback: float) -> float:
	# SF-AUD-015: fracción radiativa (φ=1, bien ventilado) ponderada por HRR de objetos activos.
	# Sentinel -1.0 en el objeto = excluir de la ponderación (usa global del motor).
	# Retrocompatible: si ningún objeto define chi_rad_normal ≥ 0, devuelve fallback (-1.0).
	if room == null or not _has_explicit_fuel_objects(room):
		return fallback

	var weighted_frac: float = 0.0
	var total_weight: float = 0.0
	for obj in room.fuel_objects:
		if _should_skip_object_for_room(room, obj):
			continue
		if obj.remaining_fuel_MJ <= 0.001:
			continue

		var frac: float = float(obj.chi_rad_normal)
		if frac < 0.0:
			continue  # sentinel: no contribuye

		var preheat_fraction: float = clampf(_fuel_object_preheat_score(obj) / 8.0, 0.0, 1.0)
		var weight: float = maxf(1.0, obj.max_hrr_kw) * lerpf(0.35, 1.0, preheat_fraction)
		if bool(obj.is_primary_ignition_source):
			weight *= 1.40
		if obj.state == FuelObjectModelScript.State.FLAMING:
			weight *= 1.35
		elif obj.state == FuelObjectModelScript.State.PYROLYZING:
			weight *= 1.20

		weighted_frac += clampf(frac, 0.0, 1.0) * weight
		total_weight += weight

	if total_weight <= 0.000001:
		return fallback

	return clampf(weighted_frac / total_weight, 0.0, 1.0)


func _resolve_room_hcn_base_yield_kg_per_MJ(room: RoomModel, fallback_yield: float) -> float:
	# SF-AUD-006: yield de HCN ponderado por HRR de objetos activos.
	# Solo usa objetos con hcn_yield_kg_per_MJ definido (> 0).
	if room == null or not _has_explicit_fuel_objects(room):
		return fallback_yield

	var weighted_yield: float = 0.0
	var total_weight: float = 0.0
	for obj in room.fuel_objects:
		if _should_skip_object_for_room(room, obj):
			continue
		if obj.remaining_fuel_MJ <= 0.001:
			continue

		var object_yield: float = maxf(0.0, float(obj.hcn_yield_kg_per_MJ))
		var preheat_fraction: float = clampf(_fuel_object_preheat_score(obj) / 8.0, 0.0, 1.0)
		var weight: float = maxf(1.0, obj.max_hrr_kw) * lerpf(0.35, 1.0, preheat_fraction)
		if bool(obj.is_primary_ignition_source):
			weight *= 1.40
		if obj.state == FuelObjectModelScript.State.FLAMING:
			weight *= 1.35
		elif obj.state == FuelObjectModelScript.State.PYROLYZING:
			weight *= 1.20

		weighted_yield += object_yield * weight
		total_weight += weight

	if total_weight <= 0.000001:
		return fallback_yield

	return weighted_yield / total_weight


func _resolve_room_irritant_yield_kg_per_MJ(room: RoomModel, field: String, fallback: float) -> float:
	# SF-AUD-018: yield ponderado para HCl/acroleína/formaldehído. Mismo patron que HCN.
	if room == null or not _has_explicit_fuel_objects(room):
		return fallback

	var weighted_yield: float = 0.0
	var total_weight: float = 0.0
	for obj in room.fuel_objects:
		if _should_skip_object_for_room(room, obj):
			continue
		if obj.remaining_fuel_MJ <= 0.001:
			continue

		var object_yield: float = maxf(0.0, float(obj.get(field)))
		var preheat_fraction: float = clampf(_fuel_object_preheat_score(obj) / 8.0, 0.0, 1.0)
		var weight: float = maxf(1.0, obj.max_hrr_kw) * lerpf(0.35, 1.0, preheat_fraction)
		if bool(obj.is_primary_ignition_source):
			weight *= 1.40
		if obj.state == FuelObjectModelScript.State.FLAMING:
			weight *= 1.35
		elif obj.state == FuelObjectModelScript.State.PYROLYZING:
			weight *= 1.20

		weighted_yield += object_yield * weight
		total_weight += weight

	if total_weight <= 0.000001:
		return fallback

	return weighted_yield / total_weight


func _smooth_state_value(
	current: float,
	target: float,
	dt: float,
	rise_tau_s: float,
	fall_tau_s: float
) -> float:
	var tau_s: float = rise_tau_s if target >= current else fall_tau_s
	if tau_s <= 0.000001:
		return target
	var blend: float = clampf(1.0 - exp(-dt / tau_s), 0.0, 1.0)
	return lerpf(current, target, blend)


func _estimate_radiative_flux_kw_m2(
	emitter_temp_c: float,
	receiver_temp_c: float,
	emissivity: float = 0.80
) -> float:
	var emitter_k: float = maxf(_celsius_to_kelvin(receiver_temp_c), _celsius_to_kelvin(emitter_temp_c))
	var receiver_k: float = _celsius_to_kelvin(receiver_temp_c)
	var sigma_kw_m2_k4: float = 5.670374419e-11
	return maxf(
		0.0,
		emissivity * sigma_kw_m2_k4 * (pow(emitter_k, 4.0) - pow(receiver_k, 4.0))
	)


func _celsius_to_kelvin(temp_c: float) -> float:
	return temp_c + 273.15


func _can_sustain_latent_fire(
	room: RoomModel,
	fire: FireModel,
	context: Dictionary,
	ambient_c: float
) -> bool:
	if room == null or fire == null:
		return false

	var upper_hold_c: float = float(context.get("fire_latent_hold_upper_temp_c", ambient_c))
	var lower_hold_c: float = float(context.get("fire_latent_hold_lower_temp_c", ambient_c))
	var thermal_hold: bool = room.temp_upper_c >= upper_hold_c or room.temp_lower_c >= lower_hold_c
	if not thermal_hold:
		return false

	var latent_o2_floor: float = minf(
		fire.o2_min_for_flame,
		maxf(0.02, fire.o2_min_for_flame * 0.25)
	)
	if room.o2 < latent_o2_floor:
		return false

	# El pool retenido necesita O2 significativamente por encima del mínimo de llama
	# para sostener combustión latente/smoldering. Si O2 está apenas por encima del
	# umbral (ej. equilibrio ACH), la infiltración mantiene el fuego zombi vivo.
	# fire_latent_o2_viable_margin = margen mínimo por encima del umbral efectivo.
	var latent_o2_viable_margin: float = float(context.get("fire_latent_o2_viable_margin", 0.008))
	var latent_o2_limit: float = _compute_extinction_o2_limit(
		room,
		context,
		ambient_c,
		fire.o2_min_for_flame
	)
	if room.o2 < latent_o2_limit + latent_o2_viable_margin:
		return false

	if room.retained_unburned_MJ >= 1.0:
		return true

	if fire.remaining_fuel_MJ <= float(context.get("fire_latent_min_remaining_fuel_MJ", 25.0)):
		return false

	# Extinción por dormancia prolongada: si la llama está ausente durante más de
	# 2× el timeout de extinción latente Y el HRR está por debajo de 3× el umbral
	# de extinción, dejar de sostener la fase latente. Esto evita el fuego zombi
	# en salas con mucho combustible pero O2 agotado (ej. pasillo tras flashover).
	var latent_timeout_s: float = float(
		context.get("fire_latent_extinction_delay_s", float(context.get("fire_extinction_delay_s", 0.0)))
	)
	var extinction_hrr_kw: float = float(context.get("fire_extinction_hrr_kw", 0.0))
	if latent_timeout_s > 0.0 \
			and room.fire_dormant_time_s >= latent_timeout_s * 2.0 \
			and extinction_hrr_kw > 0.0 \
			and room.hrr_kw <= extinction_hrr_kw * 3.0:
		return false

	return true


func _apply_selected_o2_extinction_guard(room: RoomModel) -> void:
	if room == null:
		return
	room.flame_hrr_target_kw = 0.0
	room.smolder_hrr_target_kw = 0.0
	room.pool_release_hrr_target_kw = 0.0
	room.hrr_target_kw = 0.0
	room.hrr_kw = 0.0
	room.burned_hrr_kw = 0.0
	room.fire_o2_extinguished = true


func _extinguish_room_fire(room: RoomModel, fire: FireModel, burned_out: bool = false) -> bool:
	if room == null:
		return false

	if g3_fuel_ledger_enabled:
		_g3_ledger_note(room, {"bal_extinction": {
			"moment": "CombustionSystem._extinguish_room_fire",
			"burned_out": burned_out,
			"pool_before_MJ": float(room.retained_unburned_MJ),
			"hrr_cancelled_kw": float(room.hrr_kw),
			"pyrolysis_cancelled_kw": float(room.pyrolysis_kw),
			"pool_generation_cancelled_kw": float(room.unburned_generation_kw),
			"smoke_cancelled_kg_s": float(room.smoke_prod_kg_s),
		}})
	room.combustion_regime = "EXTINGUISHED"
	if burned_out:
		_mark_legacy_proxy_burned_out(room)
	elif fire != null:
		_sync_legacy_proxy_from_fire(room, fire, 0.0, false)

	room.hrr_kw = 0.0
	room.hrr_target_kw = 0.0
	room.pyrolysis_kw = 0.0
	room.burned_hrr_kw = 0.0
	room.unburned_generation_kw = 0.0
	room.flame_hrr_target_kw = 0.0
	room.smolder_hrr_target_kw = 0.0
	room.pool_release_hrr_target_kw = 0.0
	room.smoke_prod_kg_s = 0.0
	room.fire = null
	room.fire_low_hrr_time_s = 0.0
	room.fire_dormant_time_s = 0.0
	if burned_out:
		room.retained_unburned_MJ = 0.0
	return false


func _mark_room_ignition_object(room: RoomModel) -> void:
	if room == null or not _has_explicit_fuel_objects(room):
		return

	var ignition_object = _select_room_ignition_object(room)
	if ignition_object == null:
		return

	for obj in room.fuel_objects:
		if _should_skip_object_for_room(room, obj):
			continue
		obj.hrr_kw = 0.0
		obj.autoignite_ready = false
		if obj == ignition_object:
			obj.is_primary_ignition_source = true
			obj.state = FuelObjectModelScript.State.FLAMING
			obj.surface_temp_c = maxf(obj.surface_temp_c, obj.ignition_temp_c + 35.0)
			obj.exposure_s = maxf(obj.exposure_s, 75.0)
			obj.ignited_by_object_id = String(obj.id)


func _select_room_ignition_object(room: RoomModel):
	var best_obj = null
	var best_score: float = -1.0e20

	for obj in room.fuel_objects:
		if _should_skip_object_for_room(room, obj):
			continue
		if obj.remaining_fuel_MJ <= 0.001:
			continue

		var score: float = _fuel_object_preheat_score(obj)
		if bool(obj.is_primary_ignition_source):
			score += 8.0
		if bool(obj.autoignite_ready):
			score += 12.0
		if obj.state == FuelObjectModelScript.State.PYROLYZING:
			score += 6.0
		elif obj.state == FuelObjectModelScript.State.HEATING:
			score += 3.0
		score += 2.0 / maxf(1.0, obj.ignition_flux_kw_m2)
		score += 1.0 / maxf(1.0, obj.ignition_temp_c)

		if score > best_score:
			best_score = score
			best_obj = obj

	return best_obj


func _apply_intraroom_object_radiation(room: RoomModel, context: Dictionary) -> void:
	# Point-source radiation model: burning objects irradiate nearby non-burning
	# objects, causing sequential ignition based on geometry (position_m).
	# q'' = Σ(hrr_src * view_factor_coeff / max(falloff_m², dist²))
	# Reference: Drysdale "Introduction to Fire Dynamics", point source model.
	if room == null or not _has_explicit_fuel_objects(room):
		return
	if not bool(context.get("fire_intraroom_spread_enabled", true)):
		return

	var view_factor_coeff: float = float(context.get("fire_intraroom_view_factor", 0.10))
	var falloff_m2: float = float(context.get("fire_intraroom_falloff_m", 1.0)) \
			* float(context.get("fire_intraroom_falloff_m", 1.0))

	# Collect FLAMING source objects (need hrr > 1 kW to contribute).
	var sources: Array = []
	for src_obj in room.fuel_objects:
		if _should_skip_object_for_room(room, src_obj):
			continue
		if src_obj.remaining_fuel_MJ <= 0.001 or float(src_obj.hrr_kw) < 1.0:
			continue
		if int(src_obj.state) == FuelObjectModelScript.State.FLAMING:
			sources.append({
				"pos": Vector2(float(src_obj.position_m.x), float(src_obj.position_m.y)),
				"hrr_kw": float(src_obj.hrr_kw)
			})

	if sources.is_empty():
		return

	# Apply radiation flux to non-burning target objects.
	for tgt_obj in room.fuel_objects:
		if _should_skip_object_for_room(room, tgt_obj):
			continue
		if tgt_obj.remaining_fuel_MJ <= 0.001:
			continue
		var tgt_state: int = int(tgt_obj.state)
		if tgt_state == FuelObjectModelScript.State.FLAMING \
				or tgt_state == FuelObjectModelScript.State.BURNED_OUT:
			continue

		var tgt_pos: Vector2 = Vector2(float(tgt_obj.position_m.x), float(tgt_obj.position_m.y))
		var total_flux_kw_m2: float = 0.0
		for src in sources:
			var dist_sq: float = tgt_pos.distance_squared_to(src["pos"])
			total_flux_kw_m2 += float(src["hrr_kw"]) * view_factor_coeff \
					/ maxf(falloff_m2, dist_sq)

		if total_flux_kw_m2 < 0.5:
			continue

		# Store 55% of computed radiation as incident flux (view factor, orientation).
		tgt_obj.incident_heat_flux_kw_m2 = maxf(
			float(tgt_obj.incident_heat_flux_kw_m2), total_flux_kw_m2 * 0.55
		)

		# Advance state to PYROLYZING when flux reaches 70% of ignition threshold
		# and the object has been exposed for at least 15 s.
		var ign_flux: float = maxf(8.0, float(tgt_obj.ignition_flux_kw_m2))
		if total_flux_kw_m2 >= ign_flux * 0.70 \
				and tgt_state != FuelObjectModelScript.State.PYROLYZING \
				and float(tgt_obj.exposure_s) >= 15.0:
			tgt_obj.state = FuelObjectModelScript.State.PYROLYZING

		# Mark autoignite_ready: PYROLYZING + full flux + 60 s exposure.
		# The main loop in _sync_explicit_objects_from_active_fire reads and then
		# clears this flag via was_autoignite_ready, so the object becomes a burn
		# candidate in the same timestep.
		if total_flux_kw_m2 >= ign_flux \
				and tgt_state == FuelObjectModelScript.State.PYROLYZING \
				and float(tgt_obj.exposure_s) >= 60.0:
			tgt_obj.autoignite_ready = true


func _sync_explicit_objects_from_active_fire(
	room: RoomModel,
	actual_solid_burn_kw: float,
	solid_fuel_demand_MJ: float,
	can_flame: bool,
	dt: float,
	context: Dictionary = {}
) -> void:
	if room == null or not _has_explicit_fuel_objects(room):
		return

	# Intra-room object-to-object radiation: burning objects irradiate nearby
	# non-burning objects, accelerating sequential ignition based on geometry.
	_apply_intraroom_object_radiation(room, context)

	var candidates: Array = []
	var total_weight: float = 0.0
	for obj in room.fuel_objects:
		if _should_skip_object_for_room(room, obj):
			continue

		# Save before clearing — preserves radiation-triggered flag from above.
		var was_autoignite_ready: bool = bool(obj.autoignite_ready)
		obj.autoignite_ready = false
		if obj.remaining_fuel_MJ <= 0.001:
			obj.remaining_fuel_MJ = 0.0
			obj.hrr_kw = 0.0
			obj.state = FuelObjectModelScript.State.BURNED_OUT
			continue

		var active_target_temp_c: float = maxf(room.temp_upper_c, obj.ignition_temp_c + 80.0)
		var heat_blend: float = clampf(dt / 60.0, 0.0, 1.0)
		obj.surface_temp_c = lerpf(obj.surface_temp_c, active_target_temp_c, heat_blend)
		obj.incident_heat_flux_kw_m2 = maxf(
			obj.incident_heat_flux_kw_m2,
			_estimate_radiative_flux_kw_m2(room.temp_upper_c, obj.surface_temp_c, 0.85)
		)

		var preheat_score: float = _fuel_object_preheat_score(obj)
		var active_burn_candidate: bool = room.flashover_triggered \
				or bool(obj.is_primary_ignition_source) \
				or was_autoignite_ready \
				or obj.state == FuelObjectModelScript.State.FLAMING \
				or obj.state == FuelObjectModelScript.State.PYROLYZING \
				or preheat_score >= 6.0
		if not active_burn_candidate:
			obj.hrr_kw = 0.0
			if obj.remaining_fuel_MJ <= 0.001:
				obj.state = FuelObjectModelScript.State.BURNED_OUT
			elif obj.surface_temp_c >= obj.ignition_temp_c - 45.0:
				obj.state = FuelObjectModelScript.State.PYROLYZING
			elif obj.surface_temp_c >= room.temp_lower_c + 35.0:
				obj.state = FuelObjectModelScript.State.HEATING
			continue

		# SF-AUD-004: si el objeto tiene su propia curva t², registrar ignición y calcular
		# su HRR ideal independiente. Esto permite que objetos encendidos en distintos
		# momentos crezcan según su propio alpha, en vez de compartir el alpha global.
		# SF-AUD-033: también registrar ignición si el objeto tiene curva HRR tabulada.
		if obj.state == FuelObjectModelScript.State.FLAMING:
			if float(obj.alpha_kw_s2) > 0.0 or not obj.hrr_curve.is_empty():
				if float(obj.t_ignition_s) < 0.0:
					obj.t_ignition_s = room.fire_time_s
		var weight: float
		if float(obj.alpha_kw_s2) > 0.0 and float(obj.t_ignition_s) >= 0.0:
			# Peso = HRR ideal del objeto en su propio tiempo t² desde su ignición.
			var t_obj: float = maxf(0.0, room.fire_time_s - float(obj.t_ignition_s))
			var obj_ideal_kw: float = float(obj.alpha_kw_s2) * t_obj * t_obj
			if float(obj.max_hrr_kw) > 0.0:
				obj_ideal_kw = minf(obj_ideal_kw, float(obj.max_hrr_kw))
			weight = maxf(0.01, obj_ideal_kw)
		elif not obj.hrr_curve.is_empty() and float(obj.t_ignition_s) >= 0.0:
			# SF-AUD-033: curva HRR tabulada — interpolación lineal por tramos.
			var t_obj: float = maxf(0.0, room.fire_time_s - float(obj.t_ignition_s))
			var obj_ideal_kw: float = _interp_hrr_curve(obj.hrr_curve, t_obj)
			if float(obj.max_hrr_kw) > 0.0:
				obj_ideal_kw = minf(obj_ideal_kw, float(obj.max_hrr_kw))
			weight = maxf(0.01, obj_ideal_kw)
		elif float(obj.heat_of_gasification_kj_kg) > 0.0 \
				and float(obj.heat_of_combustion_kj_kg) > 0.0 \
				and obj.state == FuelObjectModelScript.State.FLAMING:
			# SF-AUD-016: MLR-based weight cuando no hay curva t² propia.
			# Peso = HRR instantáneo por pirólisis física: ṁ × ΔHc.
			var q_net_kw_m2: float = maxf(0.0,
				obj.incident_heat_flux_kw_m2 - float(obj.critical_heat_flux_kw_m2))
			var A_eff_m2: float = maxf(0.01,
				float(obj.exposed_area_m2) if float(obj.exposed_area_m2) > 0.001
				else float(obj.footprint_m2) * 0.5)
			var mlr_kg_s: float = q_net_kw_m2 * A_eff_m2 / float(obj.heat_of_gasification_kj_kg)
			var obj_ideal_kw: float = mlr_kg_s * float(obj.heat_of_combustion_kj_kg)
			if float(obj.max_hrr_kw) > 0.0:
				obj_ideal_kw = minf(obj_ideal_kw, float(obj.max_hrr_kw))
			weight = maxf(0.01, obj_ideal_kw)
		else:
			weight = maxf(1.0, obj.max_hrr_kw) * (0.35 + 0.65 * preheat_score / 8.0)
			if bool(obj.is_primary_ignition_source):
				weight *= 1.40
			if obj.state == FuelObjectModelScript.State.FLAMING:
				weight *= 1.35
			elif obj.state == FuelObjectModelScript.State.PYROLYZING:
				weight *= 1.20
			weight = maxf(0.01, weight)

		candidates.append({
			"obj": obj,
			"weight": weight,
			"burn_MJ": 0.0
		})
		total_weight += weight

	if candidates.is_empty():
		if g3_fuel_ledger_enabled:
			_g3_ledger_note(room, {
				"allocation_unassigned_MJ": solid_fuel_demand_MJ,
				"allocation_no_candidates": true,
			})
		return

	if solid_fuel_demand_MJ <= 0.000001 or actual_solid_burn_kw <= 0.000001:
		for index in range(candidates.size()):
			var idle_obj = candidates[index]["obj"]
			idle_obj.hrr_kw = 0.0
			if idle_obj.state == FuelObjectModelScript.State.FLAMING:
				idle_obj.state = FuelObjectModelScript.State.DECAYING
		return

	var consumed_MJ: float = 0.0
	for index in range(candidates.size()):
		var entry: Dictionary = candidates[index]
		var obj = entry["obj"]
		var share_MJ: float = solid_fuel_demand_MJ * float(entry["weight"]) / maxf(0.001, total_weight)
		share_MJ = minf(maxf(0.0, share_MJ), obj.remaining_fuel_MJ)
		obj.remaining_fuel_MJ = maxf(0.0, obj.remaining_fuel_MJ - share_MJ)
		entry["burn_MJ"] = share_MJ
		candidates[index] = entry
		consumed_MJ += share_MJ

	var leftover_MJ: float = maxf(0.0, solid_fuel_demand_MJ - consumed_MJ)
	if leftover_MJ > 0.000001:
		var remaining_capacity_MJ: float = 0.0
		for entry in candidates:
			var capacity_obj = entry["obj"]
			remaining_capacity_MJ += maxf(0.0, capacity_obj.remaining_fuel_MJ)
		if remaining_capacity_MJ > 0.000001:
			for index in range(candidates.size()):
				var entry: Dictionary = candidates[index]
				var obj = entry["obj"]
				var extra_MJ: float = leftover_MJ * maxf(0.0, obj.remaining_fuel_MJ) / remaining_capacity_MJ
				extra_MJ = minf(extra_MJ, obj.remaining_fuel_MJ)
				obj.remaining_fuel_MJ = maxf(0.0, obj.remaining_fuel_MJ - extra_MJ)
				entry["burn_MJ"] = float(entry["burn_MJ"]) + extra_MJ
				candidates[index] = entry
				consumed_MJ += extra_MJ

	if g3_fuel_ledger_enabled:
		var g3_allocations: Dictionary = {}
		for entry in candidates:
			g3_allocations[String(entry["obj"].id)] = float(entry["burn_MJ"])
		_g3_ledger_note(room, {
			"allocations": g3_allocations,
			"allocation_unassigned_MJ": maxf(0.0, solid_fuel_demand_MJ - consumed_MJ),
		})

	for entry in candidates:
		var obj = entry["obj"]
		var burn_MJ: float = float(entry["burn_MJ"])
		if burn_MJ > 0.000001 and consumed_MJ > 0.000001:
			obj.hrr_kw = actual_solid_burn_kw * burn_MJ / consumed_MJ
			# SF-AUD-034: LOI — si O2_sala < LOI, la llama se apaga por falta de oxígeno.
			if float(obj.loi_fraction) > 0.0 and room.o2 < float(obj.loi_fraction):
				obj.state = FuelObjectModelScript.State.DECAYING
				obj.hrr_kw = 0.0
			else:
				obj.state = FuelObjectModelScript.State.FLAMING if can_flame else FuelObjectModelScript.State.DECAYING
				obj.exposure_s = maxf(obj.exposure_s, 75.0)
				# SF-AUD-034: char growth — acumular espesor de char proporcional a masa quemada.
				if float(obj.char_growth_rate_m_per_kg) > 0.0 and float(obj.heat_of_combustion_kj_kg) > 0.0:
					var mass_kg: float = burn_MJ * 1000.0 / maxf(1.0, float(obj.heat_of_combustion_kj_kg))
					obj.char_thickness_m = maxf(0.0, float(obj.char_thickness_m) + float(obj.char_growth_rate_m_per_kg) * mass_kg)
		else:
			obj.hrr_kw = 0.0
			if obj.remaining_fuel_MJ <= 0.001:
				obj.state = FuelObjectModelScript.State.BURNED_OUT
			elif obj.surface_temp_c >= obj.ignition_temp_c - 45.0:
				obj.state = FuelObjectModelScript.State.PYROLYZING
			elif obj.surface_temp_c >= room.temp_lower_c + 35.0:
				obj.state = FuelObjectModelScript.State.HEATING


func _get_dominant_fuel_object(room: RoomModel):
	if room == null:
		return null

	var best_obj = null
	var best_score: float = -1.0e20
	for obj in room.fuel_objects:
		if _should_skip_object_for_room(room, obj):
			continue

		var score: float = _fuel_object_preheat_score(obj)
		if score > best_score:
			best_score = score
			best_obj = obj

	return best_obj


func _fuel_object_preheat_score(obj) -> float:
	if obj == null:
		return -1.0e20

	var state_score: float = 0.0
	match int(obj.state):
		FuelObjectModelScript.State.HEATING:
			state_score = 2.0
		FuelObjectModelScript.State.PYROLYZING:
			state_score = 5.0
		FuelObjectModelScript.State.FLAMING:
			state_score = 7.0
		FuelObjectModelScript.State.DECAYING:
			state_score = 1.0
		FuelObjectModelScript.State.BURNED_OUT:
			state_score = -6.0
		_:
			state_score = 0.0

	var thermal_signal: float = clampf(
		inverse_lerp(obj.ignition_temp_c - 75.0, obj.ignition_temp_c, obj.surface_temp_c),
		0.0,
		1.0
	)
	var flux_signal: float = clampf(
		obj.incident_heat_flux_kw_m2 / maxf(1.0, obj.ignition_flux_kw_m2),
		0.0,
		1.5
	)
	var exposure_signal: float = clampf(obj.exposure_s / 75.0, 0.0, 1.5)
	var hrr_signal: float = clampf(obj.hrr_kw / maxf(1.0, obj.max_hrr_kw), 0.0, 1.0)
	var ready_bonus: float = 3.0 if bool(obj.autoignite_ready) else 0.0
	return state_score + ready_bonus + maxf(thermal_signal, flux_signal) * 2.0 + exposure_signal + hrr_signal


func _get_legacy_room_proxy(room: RoomModel):
	if room == null or room.fuel_objects.is_empty():
		return null

	for obj in room.fuel_objects:
		if _is_legacy_room_proxy(obj):
			return obj

	return null


func _has_explicit_fuel_objects(room: RoomModel) -> bool:
	if room == null or room.fuel_objects.is_empty():
		return false

	for obj in room.fuel_objects:
		if obj != null and not _is_legacy_room_proxy(obj):
			return true

	return false


func _has_ignitable_fuel_object(room: RoomModel) -> bool:
	if room == null:
		return false
	if not _has_explicit_fuel_objects(room):
		return room.fuel_energy_MJ > 0.001 \
			or room.max_hrr_kw > 0.001 \
			or get_room_total_remaining_fuel_MJ(room) > 0.001

	for obj in room.fuel_objects:
		if _should_skip_object_for_room(room, obj):
			continue
		if obj.remaining_fuel_MJ > 0.001:
			return true

	return false


func _is_legacy_room_proxy(obj) -> bool:
	return obj != null and String(obj.id).begins_with("room_proxy_")


func _should_skip_object_for_room(room: RoomModel, obj) -> bool:
	if obj == null:
		return true
	return _has_explicit_fuel_objects(room) and _is_legacy_room_proxy(obj)


func _sync_legacy_proxy_idle(room: RoomModel) -> void:
	var proxy = _get_legacy_room_proxy(room)
	if proxy == null:
		return

	proxy.hrr_kw = 0.0
	proxy.incident_heat_flux_kw_m2 = 0.0
	proxy.autoignite_ready = false
	if proxy.remaining_fuel_MJ <= 0.001:
		proxy.state = FuelObjectModelScript.State.BURNED_OUT
	elif room.fire_time_s > 0.0:
		proxy.state = FuelObjectModelScript.State.DECAYING
	else:
		proxy.state = FuelObjectModelScript.State.COLD


func _sync_legacy_proxy_from_fire(room: RoomModel, fire: FireModel, hrr_kw: float, can_flame: bool) -> void:
	var proxy = _get_legacy_room_proxy(room)
	if proxy == null or fire == null:
		return

	proxy.max_hrr_kw = fire.max_hrr_kw
	proxy.remaining_fuel_MJ = maxf(0.0, fire.remaining_fuel_MJ + room.retained_unburned_MJ)
	proxy.hrr_kw = maxf(0.0, hrr_kw)
	proxy.incident_heat_flux_kw_m2 = 0.0
	proxy.autoignite_ready = false

	if proxy.remaining_fuel_MJ <= 0.001:
		proxy.state = FuelObjectModelScript.State.BURNED_OUT
	elif proxy.hrr_kw > 0.01 and can_flame:
		proxy.state = FuelObjectModelScript.State.FLAMING
	elif proxy.hrr_kw > 0.01:
		proxy.state = FuelObjectModelScript.State.DECAYING
	elif room.fire_time_s > 0.0:
		proxy.state = FuelObjectModelScript.State.DECAYING
	else:
		proxy.state = FuelObjectModelScript.State.COLD


func _mark_legacy_proxy_burned_out(room: RoomModel) -> void:
	var proxy = _get_legacy_room_proxy(room)
	if proxy == null:
		return

	proxy.remaining_fuel_MJ = 0.0
	proxy.hrr_kw = 0.0
	proxy.incident_heat_flux_kw_m2 = 0.0
	proxy.autoignite_ready = false
	proxy.state = FuelObjectModelScript.State.BURNED_OUT


# ============================================================
# SF-AUD-033: CURVA HRR TABULADA — interpolación lineal
# ============================================================
# Interpola linealmente la curva [[t0, h0], [t1, h1], ...] en t_s.
# t_s es el tiempo desde la ignición del objeto (no el tiempo global).
# Fuera del rango: se extrapola con el valor del extremo más cercano.
func _interp_hrr_curve(curve: Array, t_s: float) -> float:
	var n: int = curve.size()
	if n == 0:
		return 0.0
	var first_entry: Variant = curve[0]
	if typeof(first_entry) != TYPE_ARRAY or (first_entry as Array).size() < 2:
		return 0.0
	var t0: float = float((first_entry as Array)[0])
	var h0: float = float((first_entry as Array)[1])
	if t_s <= t0:
		return maxf(0.0, h0)
	var last_entry: Variant = curve[n - 1]
	if typeof(last_entry) != TYPE_ARRAY or (last_entry as Array).size() < 2:
		return 0.0
	var t_last: float = float((last_entry as Array)[0])
	var h_last: float = float((last_entry as Array)[1])
	if t_s >= t_last:
		return maxf(0.0, h_last)
	for i: int in range(n - 1):
		var entry_a: Variant = curve[i]
		var entry_b: Variant = curve[i + 1]
		if typeof(entry_a) != TYPE_ARRAY or (entry_a as Array).size() < 2:
			continue
		if typeof(entry_b) != TYPE_ARRAY or (entry_b as Array).size() < 2:
			continue
		var ta: float = float((entry_a as Array)[0])
		var tb: float = float((entry_b as Array)[0])
		if t_s >= ta and t_s <= tb:
			var ha: float = float((entry_a as Array)[1])
			var hb: float = float((entry_b as Array)[1])
			var alpha: float = (t_s - ta) / maxf(0.0001, tb - ta)
			return maxf(0.0, lerpf(ha, hb, alpha))
	return maxf(0.0, h_last)


# ============================================================
# G3-3 — LIBRO CONTABLE PASIVO DE COMBUSTIBLE
# ------------------------------------------------------------
# Solo se ejecuta con g3_fuel_ledger_enabled. Lee el estado y copia valores
# locales del paso; ninguna variable física lee lo que escribe.
# ============================================================

func _g3_ownership_mode(room: RoomModel, context: Dictionary) -> String:
	if not _has_explicit_fuel_objects(room):
		return "aggregate"
	if room.fuel_energy_MJ > 0.0 or room.max_hrr_kw > 0.0:
		return "legacy_room_load"
	if _g3_explicit_owned_room(room, context):
		return "explicit_owned"
	return "legacy_objects_only"


func _g3_ledger_begin(room: RoomModel, fire: FireModel, dt: float, context: Dictionary) -> void:
	var objects: Array = []
	for obj in room.fuel_objects:
		if obj == null:
			continue
		objects.append({
			"id": String(obj.id),
			"is_proxy": _is_legacy_room_proxy(obj),
			"remaining_before_MJ": float(obj.remaining_fuel_MJ),
			"state_before": fuel_object_state_to_string(int(obj.state)),
			"active_before": _explicit_object_is_active(room, obj),
			"max_hrr_kw": float(obj.max_hrr_kw),
			"co_yield_kg_per_MJ": float(obj.co_yield_kg_per_MJ),
		})
		if bool(context.get(G3_OWNERSHIP_SWITCH, false)):
			objects[objects.size() - 1]["r_balance_before_MJ"] = float(obj.g3_r_balance_MJ)
			objects[objects.size() - 1]["tail_state_before"] = int(obj.g3_r_tail_state)
	_g3_fuel_ledger_pending[room.id] = {
		"schema_version": "g3_fuel_ledger_v3",
		"room_id": room.id,
		"dt_s": dt,
		"switch_on": bool(context.get(G3_OWNERSHIP_SWITCH, false)),
		"ownership_mode": _g3_ownership_mode(room, context),
		"declared_room_fuel_MJ": float(room.fuel_energy_MJ),
		"declared_room_max_hrr_kw": float(room.max_hrr_kw),
		"fire_present_before": fire != null,
		"_fire": fire,
		"fire_fuel_energy_MJ": float(fire.fuel_energy_MJ) if fire != null else 0.0,
		"fire_max_hrr_kw": float(fire.max_hrr_kw) if fire != null else 0.0,
		"fire_remaining_before_MJ": float(fire.remaining_fuel_MJ) if fire != null else 0.0,
		"power_cap_kw": float(fire.max_hrr_kw) if fire != null else 0.0,
		"pool_before_MJ": float(room.retained_unburned_MJ),
		"demand_unscaled_MJ": 0.0,
		"available_MJ": 0.0,
		"fuel_scale": 1.0,
		"consumed_MJ": 0.0,
		"hrr_requested_kw": 0.0,
		"hrr_applied_kw": 0.0,
		"actual_solid_burn_kw": 0.0,
		"actual_pool_burn_kw": 0.0,
		"pool_generation_MJ": 0.0,
		"allocations": {},
		"allocation_unassigned_MJ": 0.0,
		"species": {"co_kg": 0.0, "co2_kg": 0.0, "hcn_kg": 0.0, "smoke_kg": 0.0},
		"objects": objects,
	}
	_g3_fuel_ledger_pending[room.id]["bal_schema"] = "g3_balance_v1"
	_g3_fuel_ledger_pending[room.id]["bal_state_before"] = _g3_balance_room_state(room)


## G3 DIAGNÓSTICO (no es física de producto). Objetivo de llama con la clave:
## fuera de la ventana (umbral, umbral + ancho) devuelve el original sin tocar;
## dentro, la recta entre
##   - el umbral:  rescoldo + fracción_de_salto · (ideal · umbral − rescoldo)
##   - el borde:   ideal · (umbral + ancho), el valor de la regla original.
## Con fracción 0 es continuo en el umbral; con fracción 1 es la regla original.
static func g3_diag_flame_target_kw(
	original_kw: float,
	ideal_kw: float,
	flame_drive: float,
	smolder_at_threshold_kw: float,
	window: float,
	jump_fraction: float
) -> float:
	var outside_window: bool = (
		flame_drive <= G3_DIAG_CAN_FLAME_DRIVE
		or flame_drive >= G3_DIAG_CAN_FLAME_DRIVE + window
	)
	if window <= 0.0 or outside_window:
		return original_kw
	var at_threshold_kw: float = lerpf(
		smolder_at_threshold_kw, ideal_kw * G3_DIAG_CAN_FLAME_DRIVE, jump_fraction
	)
	var at_window_top_kw: float = ideal_kw * (G3_DIAG_CAN_FLAME_DRIVE + window)
	return lerpf(
		at_threshold_kw, at_window_top_kw, (flame_drive - G3_DIAG_CAN_FLAME_DRIVE) / window
	)


func _g3_ledger_note(room: RoomModel, values: Dictionary) -> void:
	if not _g3_fuel_ledger_pending.has(room.id):
		return
	var record: Dictionary = _g3_fuel_ledger_pending[room.id]
	for key in values.keys():
		record[key] = values[key]


## G3 balance (g3_balance_v1). Solo lectura: estado de la sala tal cual, sin
## redondear. Lo usa el libro al empezar step_room_fire y al cerrar el paso.
func _g3_balance_room_state(room: RoomModel) -> Dictionary:
	var state: Dictionary = _g3_balance_gas_inventory(room)
	state["pool_MJ"] = float(room.retained_unburned_MJ)
	state["o2"] = float(room.o2)
	state["o2_upper"] = float(room.o2_upper)
	state["o2_lower"] = float(room.o2_lower)
	state["co2_upper_tracer"] = float(room.co2_upper)
	state["hcl_kg"] = float(room.hcl_kg)
	state["acrolein_kg"] = float(room.acrolein_kg)
	state["formaldehyde_kg"] = float(room.formaldehyde_kg)
	state["smoke_kg"] = float(room.smoke_kg)
	state["hrr_kw"] = float(room.hrr_kw)
	state["fuel_consumed_MJ_total"] = float(room.fuel_consumed_MJ_total)
	state["hrr_kj_total"] = float(room.hrr_kj_total)
	return state


func _g3_balance_gas_inventory(room: RoomModel) -> Dictionary:
	return {
		"co_kg": float(room.co_kg),
		"co_upper_kg": float(room.co_upper_kg),
		"co2_kg": float(room.co2_kg),
		"co2_upper_kg": float(room.co2_upper_kg),
		"hcn_kg": float(room.hcn_kg),
		"hcn_upper_kg": float(room.hcn_upper_kg),
	}


## Acumulados del paso que escriben otros sistemas (humo generado por
## GasExchangeSystem, O2 por OxygenExchangeSystem), leídos al cerrar el paso.
func _g3_balance_room_step_counters(room: RoomModel) -> Dictionary:
	return {
		"smoke_generated_kg": float(room.smoke_generated_kg_step),
		"smoke_vented_kg": float(room.smoke_vented_kg_step),
		"smoke_deposited_kg": float(room.smoke_deposited_kg_step),
		"smoke_net_transport_kg": float(room.smoke_net_transport_kg_step),
		"co_generated_kg": float(room.co_generated_kg_step),
		"co2_generated_kg": float(room.co2_generated_kg_step),
		"hcn_generated_kg": float(room.hcn_generated_kg_step),
		"o2_consumed_all_kg": float(room.o2_consumed_kg_step_all),
		"o2_consumed_bulk_kg": float(room.o2_consumed_bulk_kg_step),
		"o2_consumed_fire_kg": float(room.o2_consumed_fire_kg_step),
		"o2_exterior_net_kg": float(room.o2_exterior_net_kg_step),
		"o2_net_transport_kg": float(room.o2_net_transport_kg_step),
		"o2_zone_sync_kg": float(room.o2_zone_sync_kg_step),
		"fuel_consumed_MJ": float(room.fuel_consumed_MJ_step),
	}


## Otros sistemas del mismo paso (O2, supresión) entregan aquí sus
## observables; se unen al registro en g3_drain_fuel_ledger. Con el libro
## apagado no guarda nada.
func g3_balance_note_external(room_id: int, key: String, value: Dictionary) -> void:
	if not g3_fuel_ledger_enabled:
		return
	if not _g3_balance_external.has(room_id):
		_g3_balance_external[room_id] = {}
	_g3_balance_external[room_id][key] = value


## Reparte la sonda que OxygenExchangeSystem.step rellenó por sala.
func g3_balance_note_o2_probe(probe: Dictionary) -> void:
	for room_id in probe.keys():
		var row: Dictionary = probe[room_id]
		if row.has("co2_tracer"):
			g3_balance_note_external(int(room_id), "bal_co2_tracer", row["co2_tracer"])
			row.erase("co2_tracer")
		g3_balance_note_external(int(room_id), "bal_o2", row)


## Completa y devuelve los registros del paso; lo llama el runner tras engine.step().
func g3_drain_fuel_ledger(building) -> Array:
	var rows: Array = []
	for room_id in _g3_fuel_ledger_pending.keys():
		var record: Dictionary = _g3_fuel_ledger_pending[room_id]
		var room: RoomModel = building.get_room(room_id) if building != null else null
		var fire = record.get("_fire", null)
		record.erase("_fire")
		record["fire_extinguished_this_step"] = bool(record["fire_present_before"]) \
				and (room == null or room.fire == null)
		record["fire_remaining_after_MJ"] = float(fire.remaining_fuel_MJ) if fire != null else 0.0
		record["hrr_after_engine_step_kw"] = float(room.hrr_kw) if room != null else 0.0
		record["pool_after_MJ"] = float(room.retained_unburned_MJ) if room != null else 0.0
		var after: Dictionary = {}
		if room != null:
			for obj in room.fuel_objects:
				if obj != null:
					after[String(obj.id)] = obj
		var allocations: Dictionary = record["allocations"]
		for entry in record["objects"]:
			var obj = after.get(entry["id"], null)
			entry["remaining_after_MJ"] = float(obj.remaining_fuel_MJ) if obj != null else 0.0
			entry["state_after"] = fuel_object_state_to_string(int(obj.state)) if obj != null else "removed"
			entry["hrr_after_kw"] = float(obj.hrr_kw) if obj != null else 0.0
			entry["allocated_MJ"] = float(allocations.get(entry["id"], 0.0))
			if entry.has("r_balance_before_MJ"):
				entry["r_balance_after_MJ"] = float(obj.g3_r_balance_MJ) if obj != null else 0.0
				entry["tail_state_after"] = int(obj.g3_r_tail_state) if obj != null else 0
		if room != null:
			record["bal_state_after"] = _g3_balance_room_state(room)
			record["bal_state_after"]["step"] = _g3_balance_room_step_counters(room)
		var external: Dictionary = _g3_balance_external.get(room_id, {})
		for key in external.keys():
			record[key] = external[key]
		record.erase("allocations")
		rows.append(record)
	_g3_fuel_ledger_pending.clear()
	_g3_balance_external.clear()
	return rows


# ============================================================
# G3 — PROPIEDAD DE ENERGÍA Y POTENCIA (explicit_objects, OFF por defecto)
# ============================================================

## La sala es explicit_objects solo si el interruptor está activo, no declara
## carga de sala ni potencia de sala y tiene objetos explícitos. Las salas con
## carga de sala positiva conservan la ruta legacy aunque el interruptor esté ON.
func _g3_explicit_owned_room(room: RoomModel, context: Dictionary) -> bool:
	return bool(context.get(G3_OWNERSHIP_SWITCH, false)) \
			and room.fuel_energy_MJ <= 0.0 \
			and room.max_hrr_kw <= 0.0 \
			and _has_explicit_fuel_objects(room)


## Mismo criterio de candidato que _sync_explicit_objects_from_active_fire,
## evaluado con el estado al inicio del paso.
func _explicit_object_is_active(room: RoomModel, obj) -> bool:
	if obj == null or _is_legacy_room_proxy(obj):
		return false
	if obj.remaining_fuel_MJ <= 0.001:
		return false
	return room.flashover_triggered \
			or bool(obj.is_primary_ignition_source) \
			or bool(obj.autoignite_ready) \
			or obj.state == FuelObjectModelScript.State.FLAMING \
			or obj.state == FuelObjectModelScript.State.PYROLYZING \
			or _fuel_object_preheat_score(obj) >= 6.0


## Reparto con topes (water-filling): distribuye `total` según `weights` sin
## superar `caps`; lo que no cabe queda sin asignar (el libro lo registra).
func _g3_waterfill(total: float, weights: Array, caps: Array) -> Array:
	var n: int = weights.size()
	var out: Array = []
	var local_weights: Array = []
	for i in range(n):
		out.append(0.0)
		local_weights.append(maxf(0.0, float(weights[i])))
	var open: Array = []
	for i in range(n):
		if float(caps[i]) > 0.0:
			open.append(i)
	var remaining: float = maxf(0.0, total)
	for _pass in range(n + 1):
		if remaining <= 0.0 or open.is_empty():
			break
		var weight_sum: float = 0.0
		for i in open:
			weight_sum += float(local_weights[i])
		if weight_sum <= 0.0:
			for i in open:
				local_weights[i] = 1.0
			weight_sum = float(open.size())
		var saturated: Array = []
		for i in open:
			var share: float = remaining * float(local_weights[i]) / weight_sum
			if float(out[i]) + share >= float(caps[i]):
				saturated.append(i)
		if saturated.is_empty():
			for i in open:
				out[i] = float(out[i]) + remaining * float(local_weights[i]) / weight_sum
			remaining = 0.0
			break
		for i in saturated:
			remaining -= float(caps[i]) - float(out[i])
			out[i] = float(caps[i])
			open.erase(i)
	return out


## Peso de reparto: copia literal de la fórmula de _sync_explicit_objects_from_active_fire.
func _g3_object_weight(room: RoomModel, obj, preheat_score: float) -> float:
	if obj.state == FuelObjectModelScript.State.FLAMING:
		if float(obj.alpha_kw_s2) > 0.0 or not obj.hrr_curve.is_empty():
			if float(obj.t_ignition_s) < 0.0:
				obj.t_ignition_s = room.fire_time_s
	var weight: float
	if float(obj.alpha_kw_s2) > 0.0 and float(obj.t_ignition_s) >= 0.0:
		var t_obj: float = maxf(0.0, room.fire_time_s - float(obj.t_ignition_s))
		var obj_ideal_kw: float = float(obj.alpha_kw_s2) * t_obj * t_obj
		if float(obj.max_hrr_kw) > 0.0:
			obj_ideal_kw = minf(obj_ideal_kw, float(obj.max_hrr_kw))
		weight = maxf(0.01, obj_ideal_kw)
	elif not obj.hrr_curve.is_empty() and float(obj.t_ignition_s) >= 0.0:
		var t_obj: float = maxf(0.0, room.fire_time_s - float(obj.t_ignition_s))
		var obj_ideal_kw: float = _interp_hrr_curve(obj.hrr_curve, t_obj)
		if float(obj.max_hrr_kw) > 0.0:
			obj_ideal_kw = minf(obj_ideal_kw, float(obj.max_hrr_kw))
		weight = maxf(0.01, obj_ideal_kw)
	elif float(obj.heat_of_gasification_kj_kg) > 0.0 \
			and float(obj.heat_of_combustion_kj_kg) > 0.0 \
			and obj.state == FuelObjectModelScript.State.FLAMING:
		var q_net_kw_m2: float = maxf(0.0,
			obj.incident_heat_flux_kw_m2 - float(obj.critical_heat_flux_kw_m2))
		var A_eff_m2: float = maxf(0.01,
			float(obj.exposed_area_m2) if float(obj.exposed_area_m2) > 0.001
			else float(obj.footprint_m2) * 0.5)
		var mlr_kg_s: float = q_net_kw_m2 * A_eff_m2 / float(obj.heat_of_gasification_kj_kg)
		var obj_ideal_kw: float = mlr_kg_s * float(obj.heat_of_combustion_kj_kg)
		if float(obj.max_hrr_kw) > 0.0:
			obj_ideal_kw = minf(obj_ideal_kw, float(obj.max_hrr_kw))
		weight = maxf(0.01, obj_ideal_kw)
	else:
		weight = maxf(1.0, obj.max_hrr_kw) * (0.35 + 0.65 * preheat_score / 8.0)
		if bool(obj.is_primary_ignition_source):
			weight *= 1.40
		if obj.state == FuelObjectModelScript.State.FLAMING:
			weight *= 1.35
		elif obj.state == FuelObjectModelScript.State.PYROLYZING:
			weight *= 1.20
		weight = maxf(0.01, weight)
	return weight


## explicit_objects: cada MJ consumido se debita de un objeto activo al inicio
## del paso, con tope por su energía restante y su potencia máxima. Los objetos
## inactivos no reciben energía; su bandera de autoignición se conserva para el
## paso siguiente. Calentamiento, pesos y reparto copian la ruta legacy; la
## química (rendimientos) no se toca. Se evalúa antes de las especies porque la
## opción D necesita el dueño de cada MJ para acumular y liberar el saldo R; el
## débito y los estados solo se aplican en _g3_apply_owned (si no hay extinción).
func _g3_allocate_owned(
	room: RoomModel,
	active: Array,
	solid_fuel_demand_MJ: float,
	dt: float,
	context: Dictionary
) -> Array:
	_apply_intraroom_object_radiation(room, context)

	var preheat_by_obj: Dictionary = {}
	for obj in room.fuel_objects:
		if obj == null or _is_legacy_room_proxy(obj):
			continue
		if obj.remaining_fuel_MJ <= 0.001:
			# Sin descarte: el residuo <= 1 kJ queda registrado en el inventario.
			obj.hrr_kw = 0.0
			obj.state = FuelObjectModelScript.State.BURNED_OUT
			continue
		var active_target_temp_c: float = maxf(room.temp_upper_c, obj.ignition_temp_c + 80.0)
		var heat_blend: float = clampf(dt / 60.0, 0.0, 1.0)
		obj.surface_temp_c = lerpf(obj.surface_temp_c, active_target_temp_c, heat_blend)
		obj.incident_heat_flux_kw_m2 = maxf(
			obj.incident_heat_flux_kw_m2,
			_estimate_radiative_flux_kw_m2(room.temp_upper_c, obj.surface_temp_c, 0.85)
		)
		preheat_by_obj[obj] = _fuel_object_preheat_score(obj)

	var weights: Array = []
	var caps_MJ: Array = []
	for obj in active:
		weights.append(_g3_object_weight(room, obj, float(preheat_by_obj.get(obj, _fuel_object_preheat_score(obj)))))
		caps_MJ.append(minf(maxf(0.0, obj.remaining_fuel_MJ), maxf(0.0, float(obj.max_hrr_kw)) * dt / 1000.0))
	var burns: Array = _g3_waterfill(solid_fuel_demand_MJ, weights, caps_MJ)
	if g3_fuel_ledger_enabled:
		var allocated_MJ: float = 0.0
		for burn in burns:
			allocated_MJ += float(burn)
		var g3_allocations: Dictionary = {}
		for i in range(active.size()):
			g3_allocations[String(active[i].id)] = float(burns[i])
		_g3_ledger_note(room, {
			"allocations": g3_allocations,
			"allocation_unassigned_MJ": maxf(0.0, solid_fuel_demand_MJ - allocated_MJ),
		})
	return burns


## G3 Gate B opción D (prototipo; diseño G3_ENERGY_DELAY_DESIGN §8–§9).
## Saldo R por dueño: acumula w_i·(T_s − B0)·dt en cualquier estado; se libera
## solo por la llama propia del dueño (activo, con débito, FLAMING al inicio del
## paso) o por su cola posagotamiento, y cada liberación está acotada a la vez por
##   - el PERMISO DE POTENCIA del modelo: can_flame, no extinguido por O2, todo el
##     pirolizado fresco del paso quemado (P <= T_s) y calor del objeto
##     <= flame_drive · max_hrr_kw (no es una cota de oxígeno);
##   - la COTA DE MASA DE O2 del sumidero del fuego (OxygenExchangeSystem):
##     0,076 · (B0 + pool + R liberado) · dt no supera lo que step() aceptará;
##   - la guarda de extinción tardía: si el paso acabará sin combustible o por
##     fire_max_active_s (el HRR se anula tras las especies), no se libera R.
## Solo CALCULA: no toca objetos. El saldo y las colas se confirman en
## _g3_apply_owned; si el paso termina en una extinción temprana no se confirma
## nada (_g3_note_uncommitted). R nunca pasa a retained_unburned_MJ, a
## remaining_fuel_MJ ni a otro dueño.
func _g3_option_d_step(
	room: RoomModel,
	active: Array,
	burns: Array,
	requested_solid_kw: float,
	pool_kw: float,
	target_kw: float,
	pyrolysis_kw: float,
	flame_drive: float,
	can_flame: bool,
	o2_extinguished: bool,
	dt: float,
	o2_kg_per_MJ: float,
	context: Dictionary
) -> Dictionary:
	var request_kw: float = maxf(0.0, requested_solid_kw)
	var base_kw: float = minf(request_kw, maxf(0.0, target_kw))
	var alloc_total_MJ: float = 0.0
	for burn in burns:
		alloc_total_MJ += float(burn)
	var lag_MJ: float = (maxf(0.0, target_kw) - base_kw) * dt / 1000.0
	var unowned_lag_MJ: float = lag_MJ if alloc_total_MJ <= 0.0 and lag_MJ > 0.0 else 0.0
	var fresh_all_burn: bool = pyrolysis_kw - target_kw <= 0.000000001
	# Extinción tardía (tras especies y débito, step_room_fire la anula con hrr=0).
	var remaining_after_MJ: float = 0.0
	for obj in room.fuel_objects:
		if obj == null or _is_legacy_room_proxy(obj):
			continue
		remaining_after_MJ += maxf(0.0, obj.remaining_fuel_MJ)
	remaining_after_MJ -= alloc_total_MJ
	var late_extinction: bool = (remaining_after_MJ <= 0.0 and room.retained_unburned_MJ <= 0.01) \
			or room.fire_time_s >= float(context.get("fire_max_active_s", 0.0))
	var power_ok: bool = can_flame and not o2_extinguished and fresh_all_burn
	var o2_floor_MJ: float = 0.0
	var floor_callable: Callable = context.get("g3_o2_sink_floor_callable", Callable())
	if floor_callable.is_valid():
		o2_floor_MJ = float(floor_callable.call(room, dt, o2_kg_per_MJ))
	var mass_headroom_MJ: float = maxf(0.0, o2_floor_MJ - (base_kw + maxf(0.0, pool_kw)) * dt / 1000.0)
	var tau_f_s: float = maxf(0.001, float(context.get("fire_hrr_fall_tau_s", 20.0)))
	var tail_min_kw: float = 0.25 * float(context.get("fire_extinction_hrr_kw", 0.0))

	var weight_by_id: Dictionary = {}
	var flaming_before: Dictionary = {}
	var r_before: Dictionary = {}
	var accrued: Dictionary = {}
	var r_new: Dictionary = {}
	var tail_new: Dictionary = {}
	for i in range(active.size()):
		var obj = active[i]
		var key: String = String(obj.id)
		weight_by_id[key] = float(burns[i]) / alloc_total_MJ if alloc_total_MJ > 0.0 else 0.0
		flaming_before[key] = obj.state == FuelObjectModelScript.State.FLAMING
	for obj in room.fuel_objects:
		if obj == null or _is_legacy_room_proxy(obj):
			continue
		var key: String = String(obj.id)
		r_before[key] = obj.g3_r_balance_MJ
		accrued[key] = float(weight_by_id.get(key, 0.0)) * lag_MJ
		r_new[key] = obj.g3_r_balance_MJ + float(accrued[key])
		tail_new[key] = int(obj.g3_r_tail_state)

	# Candidatos: llama propia (reparto del exceso del filtro por saldo R) y colas.
	var excess_MJ: float = maxf(0.0, request_kw - maxf(0.0, target_kw)) * dt / 1000.0
	var own_ids: Array = []
	var own_weights: Array = []
	var own_caps: Array = []
	var allowed: Dictionary = {}
	var reason: Dictionary = {}
	for i in range(active.size()):
		var obj = active[i]
		var key: String = String(obj.id)
		var own: bool = float(burns[i]) > 0.0 and bool(flaming_before[key])
		allowed[key] = own and power_ok and not late_extinction
		if bool(allowed[key]):
			reason[key] = "allowed"
		elif not own:
			reason[key] = "not_own_flame"
		elif late_extinction:
			reason[key] = "late_extinction_guard"
		else:
			reason[key] = "power_permit"
		if not bool(allowed[key]):
			continue
		var room_kw: float = maxf(0.0, flame_drive * float(obj.max_hrr_kw) - float(weight_by_id[key]) * base_kw)
		own_ids.append(key)
		own_weights.append(float(r_new[key]))
		own_caps.append(minf(float(r_new[key]), room_kw * dt / 1000.0))
	var own_rel: Array = _g3_waterfill(excess_MJ, own_weights, own_caps)
	var release_by_id: Dictionary = {}
	for i in range(own_ids.size()):
		release_by_id[own_ids[i]] = float(own_rel[i])
	var tail_state_before: Dictionary = {}
	for obj in room.fuel_objects:
		if obj == null or _is_legacy_room_proxy(obj) or active.has(obj):
			continue
		var key: String = String(obj.id)
		tail_state_before[key] = int(obj.g3_r_tail_state)
		if int(obj.g3_r_tail_state) != 1:
			allowed[key] = false
			reason[key] = "tail_ended" if int(obj.g3_r_tail_state) == 2 else "not_own_flame"
			continue
		if not power_ok:
			tail_new[key] = 2
			allowed[key] = false
			reason[key] = "tail_interrupted"
			continue
		if float(r_new[key]) / tau_f_s * 1000.0 < tail_min_kw:
			tail_new[key] = 2
			allowed[key] = false
			reason[key] = "tail_ended"
			continue
		if late_extinction:
			allowed[key] = false
			reason[key] = "late_extinction_guard"
			continue
		allowed[key] = true
		reason[key] = "tail"
		release_by_id[key] = minf(
			float(r_new[key]) * (1.0 - exp(-dt / tau_f_s)),
			maxf(0.0, flame_drive * float(obj.max_hrr_kw)) * dt / 1000.0
		)

	# Cota de masa de O2: la liberación total nunca excede lo que el sumidero
	# aceptará tras el calor base del paso; si no cabe, se reduce (queda en R).
	var release_MJ: float = 0.0
	for key in release_by_id.keys():
		release_MJ += float(release_by_id[key])
	var mass_limited: bool = false
	if release_MJ > mass_headroom_MJ:
		mass_limited = true
		var scale: float = mass_headroom_MJ / release_MJ if release_MJ > 0.0 else 0.0
		release_MJ = 0.0
		for key in release_by_id.keys():
			release_by_id[key] = float(release_by_id[key]) * scale
			release_MJ += float(release_by_id[key])

	var heat_by_id: Dictionary = {}
	var ledger_objects: Dictionary = {}
	for key in r_new.keys():
		var rel: float = float(release_by_id.get(key, 0.0))
		r_new[key] = float(r_new[key]) - rel
		heat_by_id[key] = float(weight_by_id.get(key, 0.0)) * base_kw + rel * 1000.0 / dt
		ledger_objects[key] = {
			"R_before_MJ": float(r_before[key]),
			"acc_MJ": float(accrued[key]),
			"rel_MJ": rel,
			"R_after_MJ": float(r_new[key]),
			"B0_MJ": float(weight_by_id.get(key, 0.0)) * base_kw * dt / 1000.0,
			"weight": float(weight_by_id.get(key, 0.0)),
			"release_allowed": bool(allowed.get(key, false)),
			"reason": String(reason.get(key, "not_own_flame")),
			"tail_state_before": int(tail_state_before.get(key, 0)),
		}
	var solid_kw: float = base_kw + release_MJ * 1000.0 / dt
	return {
		"solid_kw": solid_kw,
		"base_kw": base_kw,
		"heat_by_id": heat_by_id,
		"flaming_before": flaming_before,
		"release_MJ": release_MJ,
		"r_new": r_new,
		"tail_new": tail_new,
		"ledger": {
			"request_solid_kw": request_kw,
			"base_kw": base_kw,
			"Ts_kw": maxf(0.0, target_kw),
			"P_kw": pyrolysis_kw,
			"flame_drive": flame_drive,
			"can_flame": can_flame,
			"fresh_all_burn": fresh_all_burn,
			"power_permit": power_ok,
			"late_extinction_guard": late_extinction,
			"o2_floor_MJ": o2_floor_MJ,
			"mass_headroom_MJ": mass_headroom_MJ,
			"mass_limited": mass_limited,
			"release_MJ": release_MJ,
			"unowned_lag_MJ": unowned_lag_MJ,
			"solid_kw": solid_kw,
			"objects": ledger_objects,
		},
	}


## Paso con extinción temprana (antes de especies y débito): no se debita nada y
## la opción D no confirma saldo ni colas; el libro anota solo el calor base.
func _g3_note_uncommitted(room: RoomModel, step: Dictionary, pool_kw: float) -> void:
	if not g3_fuel_ledger_enabled or step.is_empty():
		return
	var base_kw: float = float(step.get("base_kw", 0.0))
	_g3_ledger_note(room, {
		"hrr_applied_kw": base_kw + maxf(0.0, pool_kw),
		"actual_solid_burn_kw": base_kw,
		"allocations": {},
		"allocation_unassigned_MJ": 0.0,
		"optd_uncommitted": true,
	})


## Aplica el débito y los estados del paso (explicit_objects) y confirma la
## opción D: saldo R y colas calculados en _g3_option_d_step. El calor de cada
## objeto es su parte de B0 más su liberación de R; un objeto que se agota
## ARDIENDO con saldo R > 0 abre su cola (una sola vez).
func _g3_apply_owned(
	room: RoomModel,
	active: Array,
	burns: Array,
	step: Dictionary,
	can_flame: bool
) -> void:
	var heat_by_id: Dictionary = step.get("heat_by_id", {})
	var flaming_before: Dictionary = step.get("flaming_before", {})
	var r_new: Dictionary = step.get("r_new", {})
	var tail_new: Dictionary = step.get("tail_new", {})
	for obj in room.fuel_objects:
		if obj == null or _is_legacy_room_proxy(obj):
			continue
		var key: String = String(obj.id)
		if r_new.has(key):
			obj.g3_r_balance_MJ = float(r_new[key])
			obj.g3_r_tail_state = int(tail_new[key])
	if g3_fuel_ledger_enabled and step.has("ledger"):
		_g3_ledger_note(room, {"optd": step["ledger"]})

	for i in range(active.size()):
		var obj = active[i]
		var key: String = String(obj.id)
		obj.autoignite_ready = false
		var burn_MJ: float = float(burns[i])
		var heat_kw: float = float(heat_by_id.get(key, 0.0))
		obj.remaining_fuel_MJ = maxf(0.0, obj.remaining_fuel_MJ - burn_MJ)
		if burn_MJ > 0.0 and heat_kw > 0.0:
			obj.hrr_kw = heat_kw
			if float(obj.loi_fraction) > 0.0 and room.o2 < float(obj.loi_fraction):
				obj.state = FuelObjectModelScript.State.DECAYING
				obj.hrr_kw = 0.0
			else:
				obj.state = FuelObjectModelScript.State.FLAMING if can_flame else FuelObjectModelScript.State.DECAYING
				obj.exposure_s = maxf(obj.exposure_s, 75.0)
				if float(obj.char_growth_rate_m_per_kg) > 0.0 and float(obj.heat_of_combustion_kj_kg) > 0.0:
					var mass_kg: float = burn_MJ * 1000.0 / maxf(1.0, float(obj.heat_of_combustion_kj_kg))
					obj.char_thickness_m = maxf(0.0, float(obj.char_thickness_m) + float(obj.char_growth_rate_m_per_kg) * mass_kg)
		else:
			obj.hrr_kw = 0.0
			if obj.state == FuelObjectModelScript.State.FLAMING:
				obj.state = FuelObjectModelScript.State.DECAYING
		if obj.remaining_fuel_MJ <= 0.001:
			obj.hrr_kw = 0.0
			obj.state = FuelObjectModelScript.State.BURNED_OUT
			if bool(flaming_before.get(key, false)) and int(obj.g3_r_tail_state) == 0 \
					and obj.g3_r_balance_MJ > 0.0:
				obj.g3_r_tail_state = 1

	for obj in room.fuel_objects:
		if obj == null or _is_legacy_room_proxy(obj) or active.has(obj):
			continue
		if obj.remaining_fuel_MJ <= 0.001:
			# Objeto agotado: su única fuente de calor posible es su propia cola.
			obj.hrr_kw = float(heat_by_id.get(String(obj.id), 0.0))
			continue
		obj.hrr_kw = 0.0
		if obj.surface_temp_c >= obj.ignition_temp_c - 45.0:
			obj.state = FuelObjectModelScript.State.PYROLYZING
		elif obj.surface_temp_c >= room.temp_lower_c + 35.0:
			obj.state = FuelObjectModelScript.State.HEATING


## Sin fuego en la sala ninguna cola de la opción D puede seguir ni reanudarse.
func _g3_end_tails(room: RoomModel) -> void:
	for obj in room.fuel_objects:
		if obj == null or _is_legacy_room_proxy(obj):
			continue
		if int(obj.g3_r_tail_state) == 1:
			obj.g3_r_tail_state = 2

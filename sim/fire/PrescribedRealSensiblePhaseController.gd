extends "res://sim/fire/PrescribedSensiblePhaseController.gd"

## Versioned successor of the sensible owner that composes the approved real
## n-heptane Cp profiles with the canonical sensible ledger. Isolated: no
## engine, EOS, transport, editor, scenario or product loads it.
## REAL, with limits: the two property profiles (HeptaneRealCpProfiles).
## DECLARED, not real: the reference chemistry and latent heat of the prototype
## (nominal C12/H1/O16 atoms), the prescribed release program and prescribed
## heating, and the SYNTHETIC independent budget B. Evaluating ideal-gas
## properties at a prescribed temperature predicts neither vapour availability
## nor phase equilibrium. Not a validated fire, not an evaporation prediction.
## It adds no law: the transaction, the accounts and every check are inherited.
## A state is accepted or written only on an explicit positive verdict.
const Real = preload("res://sim/fire/HeptaneRealCpProfiles.gd")
const REAL_LABELS: Dictionary = {
	"version": "prescribed_real_sensible_phase_controller_v1",
	"context": "g3_prescribed_real_sensible_context_v1",
	"seed": "g3_prescribed_real_sensible_seed_v1",
	"request": "g3_prescribed_real_sensible_request_v1",
	"snapshot": "g3_prescribed_real_sensible_snapshot_v1",
	"phase": "g3_phase_real_sensible_state_v1",
	"scope": "isolated_real_property_composition_prescribed_release_synthetic_budget_not_fire_validation",
}


func _label(name: String) -> String:
	return REAL_LABELS[name]


func _ledger(state: Dictionary, request: Dictionary, material: Dictionary) -> Dictionary:
	return Budget.propose_phase_sensible_real(state, request, material)


## An empty error list is not acceptance: an interrupted check adds no error.
## Accept only the canonical audit, valid, from a check that reported nothing.
func _admits(value: Variant, context: Dictionary, errors: Array[String]) -> bool:
	var reported: int = errors.size()
	var audit: Variant = _check_owned(value, context, errors)
	if errors.size() == reported and _positive(audit):
		return true
	if errors.size() == reported:
		errors.append("state validation ended without a positive verdict")
	return false


## Nothing short of valid = true with its candidate and step reaches the write.
func _confirmed(proposal: Dictionary) -> bool:
	return (_positive(proposal) and typeof(proposal.get("candidate")) == TYPE_DICTIONARY
		and typeof(proposal.get("step")) == TYPE_DICTIONARY and not proposal["candidate"].is_empty())


static func _positive(result: Variant) -> bool:
	return (typeof(result) == TYPE_DICTIONARY and typeof(result.get("valid")) == TYPE_BOOL
		and result["valid"])


## A refusal always says why, also when the gate itself stopped without a word.
func _failure(errors: Array[String]) -> Dictionary:
	if errors.is_empty():
		return super._failure(["state validation ended without a positive verdict"])
	return super._failure(errors)


## Adds to each step the evidence of the PRESCRIBED emission temperature.
func preview_step(request: Variant) -> Dictionary:
	var proposal: Dictionary = super.preview_step(request)
	if not _positive(proposal):
		if typeof(proposal.get("valid")) == TYPE_BOOL:
			return proposal
		return _failure(["step preview returned no explicit result"])
	var emitted: Dictionary = Real.evaluate(_context["material"]["vapour_profile"],
		request["emitted_vapour_temperature_k"])
	if not _positive(emitted):
		return _failure(["emitted vapour evidence unavailable: " + str(emitted.get("errors"))])
	proposal["step"]["emitted_vapour_evidence"] = {
		"temperature_k": emitted["candidate"]["temperature_k"],
		"temperature_is_prescribed_not_predicted": true,
		"enthalpy_interval_k": emitted["candidate"]["enthalpy_interval_k"],
		"evidence_tiers": emitted["candidate"]["evidence_tiers"],
	}
	return proposal


## A commit or a restore that stops midway is a refusal, never a silent result.
func commit_step(request: Variant, expected_generation: Variant) -> Dictionary:
	var result: Dictionary = super.commit_step(request, expected_generation)
	# A commit result carries `no_op`; an unconfirmed preview handed back does not.
	if typeof(result.get("valid")) != TYPE_BOOL or (result["valid"] and typeof(result.get("no_op")) != TYPE_BOOL):
		return _failure(["commit ended without an explicit result"])
	return result


func restore(saved: Variant, expected_generation: Variant) -> Dictionary:
	var result: Dictionary = super.restore(saved, expected_generation)
	if typeof(result.get("valid")) != TYPE_BOOL:
		return _failure(["restore ended without an explicit result"])
	return result


## Separates what is real from what is declared or synthetic. No total
## uncertainty is claimed and no temperature is inferred from an enthalpy.
func _report() -> Dictionary:
	var result: Dictionary = super._report()
	result["co_fed_approval"] = false
	result["fire_validation_approval"] = false
	var composition: Dictionary = {
		"property_evidence": "real_limited_primary_source_property",
		"chemistry_and_latent_heat": "declared_prototype_reference_nominal_CHO_not_heptane_calibration",
		"release_program": "prescribed_input_not_predicted_evaporation",
		"heating": "prescribed_input_per_step",
		"thermal_budget": BOUNDARY_KIND,
		"profiles_molar_mass_role": "unit_conversion_of_the_source_heat_capacity",
		"atom_mass_basis_role": "stoichiometry_of_the_declared_prototype",
		"mass_bases_reconciled": false,
		"total_uncertainty_quantified": false,
	}
	if not _owned.is_empty():
		var material: Dictionary = _context["material"]
		var phase: Dictionary = _owned["phase"]
		composition["reference_material_provenance"] = material["reference_material"]["provenance"]
		composition["atom_mass_basis"] = material["reference_material"]["atom_mass_basis"]
		composition["release_program_provenance"] = _context["attribution"]["provenance"]
		composition["thermal_budget_provenance"] = _context["seed"]["energy_boundary_provenance"]
		composition["liquid"] = _phase_evidence(material["liquid_profile"],
			phase["liquid_fuel_kg"], phase["liquid_sensible_kj"])
		composition["vapour"] = _phase_evidence(material["vapour_profile"],
			phase["vapour_fuel_kg"], phase["vapour_sensible_kj"])
	result["composition"] = composition
	return result


## Evidence classes crossed between the reference and the confirmed specific
## enthalpy of one phase, compared in enthalpy; no temperature is derived.
func _phase_evidence(profile: Dictionary, mass: float, sensible: float) -> Dictionary:
	var evidence: Dictionary = {"approved_profile": false, "present": mass > 0.0,
		"temperature_inferred": false, "evidence_kinds": []}
	# Evidence is read only from a profile the adapter itself approves.
	if not _positive(Real.validate_profile(profile)):
		return evidence
	evidence["approved_profile"] = true
	evidence["provenance"] = profile["provenance"]
	evidence["molar_mass_g_mol"] = profile["molar_mass_g_mol"]
	evidence["declared_errors"] = profile["declared_errors"].duplicate(true)
	if mass <= 0.0:
		return evidence
	var specific: float = sensible / mass
	var low: float = minf(0.0, specific)
	var high: float = maxf(0.0, specific)
	for tier: Dictionary in profile["evidence_tiers"]:
		var start: Dictionary = Real.evaluate(profile, tier["its90_range_k"][0])
		var end: Dictionary = Real.evaluate(profile, tier["its90_range_k"][1])
		var first: float = start["candidate"]["specific_sensible_enthalpy_kj_kg"]
		var last: float = end["candidate"]["specific_sensible_enthalpy_kj_kg"]
		if minf(last, high) - maxf(first, low) > 0.0 or (low == high and first <= low and low <= last):
			evidence["evidence_kinds"].append(tier["evidence_kind"])
	evidence["specific_sensible_enthalpy_kj_kg"] = specific
	evidence["enthalpy_interval_kj_kg"] = [low, high]
	return evidence

extends RefCounted

## G3-D1 pure, unintegrated budget. Requests are kg/STEP, not predicted MLR.
## V1: equal specific chemical energy before/after release. The explicit
## propose_phase_reference API adds a LIQUID/GAS reference-potential ledger.
## One declared CHO component; complete oxidation only. No moisture, char, drips, surface reaction,
## transport, ignition, CO/HCN yields, or conversion of legacy energy accounts.
## Products include combustion water VAPOUR; chemical heat uses a NET basis.
## A prescribed release is a boundary input, not a thermal prediction. In
## thermal_budgeted mode its declared cost is paid only by the supplied budget,
## never by oxidation heat produced in this same proposal.

const MASS_ABS_TOL_KG: float = 1.0e-12
const ENERGY_ABS_TOL_KJ: float = 1.0e-9
const REL_TOL: float = 1.0e-12
const STATE_KEYS: Array[String] = [
	"initial_fuel_mass_kg", "solid_fuel_kg", "released_fuel_kg", "o2_kg",
]
const REQUEST_KEYS: Array[String] = [
	"dt_s", "release_kg", "oxidation_kg", "release_mode", "release_heat_budget_kj",
]
const MATERIAL_KEYS: Array[String] = [
	"mass_fractions", "chemical_heat_kj_per_kg", "chemical_energy_basis",
	"provenance", "heat_of_gasification_kj_kg",
]
const ELEMENTS: Array[String] = ["C", "H", "O"]
const PHASE_STATE_KEYS: Array[String] = [
	"initial_fuel_mass_kg", "liquid_fuel_kg", "vapour_fuel_kg", "o2_kg",
	"thermal_budget_kj", "deposited_heat_kj",
]
const PHASE_REQUEST_KEYS: Array[String] = ["dt_s", "release_kg", "oxidation_kg"]
const PHASE_MATERIAL_KEYS: Array[String] = [
	"schema", "liquid_phase", "vapour_phase", "reference_temperature_k",
	"reference_pressure_pa", "water_product_phase", "atom_mass_basis",
	"chemical_energy_basis", "mass_fractions", "liquid_heat_kj_kg",
	"vapour_heat_kj_kg", "phase_enthalpy_kj_kg", "provenance",
]
const SensibleProperties = preload("res://sim/fire/SensibleEnthalpyModel.gd")
const SENSIBLE_STATE_KEYS: Array[String] = ["schema", "component_id",
	"initial_fuel_mass_kg", "liquid_fuel_kg", "vapour_fuel_kg", "o2_kg",
	"thermal_budget_kj", "deposited_heat_kj", "liquid_sensible_kj", "vapour_sensible_kj"]
const SENSIBLE_REQUEST_KEYS: Array[String] = ["dt_s", "release_kg", "oxidation_kg",
	"heat_liquid_kj", "heat_vapour_kj", "emitted_vapour_temperature_k"]
const SENSIBLE_MATERIAL_KEYS: Array[String] = ["schema", "component_id",
	"reference_material", "liquid_profile", "vapour_profile"]


## Returns a new candidate, never writes inputs. Rejection returns no candidate.
## Nominal atomic masses C=12, H=1, O=16 define this algebraic test scope.
static func propose(state: Variant, request: Variant, material: Variant) -> Dictionary:
	var errors: Array[String] = []
	var s: Dictionary = _dictionary(state, STATE_KEYS, "state", errors)
	var r: Dictionary = _dictionary(request, REQUEST_KEYS, "request", errors)
	var m: Dictionary = _dictionary(material, MATERIAL_KEYS, "material", errors)
	var numbers: Dictionary = {}
	for key in STATE_KEYS:
		numbers[key] = _nonnegative(s, key, "state", errors)
	for key in ["dt_s", "release_kg", "oxidation_kg"]:
		numbers[key] = _nonnegative(r, key, "request", errors)
	var heat: float = _nonnegative(m, "chemical_heat_kj_per_kg", "material", errors)
	if heat <= 0.0:
		errors.append("chemical_heat_kj_per_kg must be > 0")
	if typeof(m.get("chemical_energy_basis")) not in [TYPE_STRING, TYPE_STRING_NAME] or m.get("chemical_energy_basis") != "complete_oxidation_net":
		errors.append("chemical_energy_basis must be complete_oxidation_net")
	if typeof(m.get("provenance")) != TYPE_STRING or String(m.get("provenance", "")).strip_edges().is_empty():
		errors.append("material.provenance must be a nonempty string")
	var fractions: Dictionary = _dictionary(m.get("mass_fractions"), ELEMENTS, "mass_fractions", errors)
	var c: float = _nonnegative(fractions, "C", "mass_fractions", errors)
	var h: float = _nonnegative(fractions, "H", "mass_fractions", errors)
	var o: float = _nonnegative(fractions, "O", "mass_fractions", errors)
	if absf(c + h + o - 1.0) > REL_TOL:
		errors.append("CHO mass fractions must sum to 1")
	var oxygen_per_kg: float = _oxygen_required(c, h, o)
	if oxygen_per_kg <= 0.0 or not _finite(oxygen_per_kg):
		errors.append("declared CHO component must require positive O2")
	var mode: String = String(r.get("release_mode", "")) if typeof(r.get("release_mode")) == TYPE_STRING else ""
	var gasification_heat: float = 0.0
	var thermal_budget: float = 0.0
	if mode == "thermal_budgeted":
		gasification_heat = _nonnegative(m, "heat_of_gasification_kj_kg", "material", errors)
		thermal_budget = _nonnegative(r, "release_heat_budget_kj", "request", errors)
		if gasification_heat <= 0.0:
			errors.append("thermal_budgeted release requires Hgas > 0")
	elif mode == "prescribed_mass_transfer":
		if r.has("release_heat_budget_kj") or m.has("heat_of_gasification_kj_kg"):
			errors.append("thermal inputs require thermal_budgeted mode")
	else:
		errors.append("release_mode must be prescribed_mass_transfer or thermal_budgeted")
	var solid: float = float(numbers["solid_fuel_kg"])
	var released: float = float(numbers["released_fuel_kg"])
	var oxygen: float = float(numbers["o2_kg"])
	var total_fuel: float = solid + released
	if not _finite(total_fuel) or total_fuel > float(numbers["initial_fuel_mass_kg"]):
		errors.append("remaining solid + released fuel exceeds initial fuel mass")
	if not errors.is_empty():
		return _rejected(errors)

	var release_requested: float = float(numbers["release_kg"])
	var oxidation_requested: float = float(numbers["oxidation_kg"])
	var accepted: Dictionary = _accepted_masses(float(numbers["dt_s"]), release_requested,
		oxidation_requested, solid, released, oxygen, oxygen_per_kg, mode, thermal_budget, gasification_heat)
	var transferred: float = accepted["transferred"]
	var oxidized: float = accepted["oxidized"]
	var products: Dictionary = _oxidation_quantities(oxidized, oxygen, oxygen_per_kg, c, h)
	var o2_used: float = products["o2_used"]
	var co2: float = products["co2"]
	var water: float = products["water"]
	var oxidation_heat: float = oxidized * heat
	var release_cost: float = minf(thermal_budget, transferred * gasification_heat)
	var after: Dictionary = {
		"initial_fuel_mass_kg": float(numbers["initial_fuel_mass_kg"]),
		"solid_fuel_kg": solid - transferred,
		"released_fuel_kg": released + transferred - oxidized,
		"o2_kg": oxygen - o2_used,
	}
	var remaining: float = float(after["solid_fuel_kg"]) + float(after["released_fuel_kg"])
	var chemical_before: float = total_fuel * heat
	var chemical_after: float = remaining * heat
	var thermal_after: float = thermal_budget - release_cost
	var balances: Dictionary = _mass_element_balance(total_fuel, oxygen, remaining,
		float(after["o2_kg"]), co2, water, c, h, o, errors)
	_check_balance(chemical_before, chemical_after + oxidation_heat, ENERGY_ABS_TOL_KJ, "chemical energy", errors)
	_check_balance(thermal_budget, thermal_after + release_cost, ENERGY_ABS_TOL_KJ, "release heat budget", errors)
	for key in ["solid_fuel_kg", "released_fuel_kg", "o2_kg"]:
		if not _finite(float(after[key])) or float(after[key]) < -MASS_ABS_TOL_KG:
			errors.append("invalid candidate inventory: " + key)
	for quantity in [transferred, oxidized, o2_used, co2, water, oxidation_heat, release_cost, thermal_after]:
		if not _finite(float(quantity)) or float(quantity) < 0.0:
			errors.append("nonfinite or negative proposal quantity")
	if not errors.is_empty():
		return _rejected(errors)
	return {
		"valid": true, "errors": errors, "candidate": after,
		"accepted_release_kg": transferred, "rejected_release_kg": release_requested - transferred,
		"accepted_oxidation_kg": oxidized, "rejected_oxidation_kg": oxidation_requested - oxidized,
		"o2_consumed_kg": o2_used, "products_kg": {"co2": co2, "water_vapour": water},
		"oxidation_heat_kj": oxidation_heat, "release_cost_kj": release_cost,
		"remaining_release_heat_budget_kj": thermal_after,
		"chemical_before_kj": chemical_before, "chemical_after_kj": chemical_after,
		"mass_residual_kg": balances["mass_residual_kg"], "element_residuals_kg": balances["element_residuals_kg"],
		"chemical_residual_kj": chemical_after + oxidation_heat - chemical_before,
		"release_heat_residual_kj": thermal_after + release_cost - thermal_budget,
		"scope": "synthetic_budget_not_material_calibration",
		"excluded": ["moisture", "char", "drips", "surface_reaction", "transport", "ignition", "partial_oxidation"],
		"release_mode": mode, "provenance": String(m["provenance"]),
	}


## Explicit v2 reference ledger only. Never calls v1 with liquid as solid.
## Same CHO/caps/products owner, different phase-specific potential accounting.
static func propose_phase_reference(state: Variant, request: Variant, material: Variant) -> Dictionary:
	var errors: Array[String] = []
	var s: Dictionary = _dictionary(state, PHASE_STATE_KEYS, "phase_state", errors)
	var r: Dictionary = _dictionary(request, PHASE_REQUEST_KEYS, "phase_request", errors)
	var m: Dictionary = _dictionary(material, PHASE_MATERIAL_KEYS, "phase_material", errors)
	var numbers: Dictionary = {}
	for key in PHASE_STATE_KEYS:
		numbers[key] = _nonnegative(s, key, "phase_state", errors)
	for key in PHASE_REQUEST_KEYS:
		numbers[key] = _nonnegative(r, key, "phase_request", errors)
	var required: Dictionary = {
		"schema": "g3_phase_reference_CHO_material_v1", "liquid_phase": "liquid",
		"vapour_phase": "gas", "water_product_phase": "gas",
		"atom_mass_basis": "nominal_C12_H1_O16", "chemical_energy_basis": "complete_oxidation_net",
	}
	for key in required:
		if typeof(m.get(key)) not in [TYPE_STRING, TYPE_STRING_NAME] or m.get(key) != required[key]:
			errors.append("phase_material incompatible " + key)
	var reference_temp: float = _nonnegative(m, "reference_temperature_k", "phase_material", errors)
	var reference_pressure: float = _nonnegative(m, "reference_pressure_pa", "phase_material", errors)
	if reference_temp != 298.15 or reference_pressure != 100000.0:
		errors.append("phase ledger requires 298.15 K / 1 bar reference")
	if typeof(m.get("provenance")) != TYPE_STRING or String(m.get("provenance", "")).strip_edges().is_empty():
		errors.append("phase_material.provenance must be a nonempty string")
	var fractions: Dictionary = _dictionary(m.get("mass_fractions"), ELEMENTS, "mass_fractions", errors)
	var c: float = _nonnegative(fractions, "C", "mass_fractions", errors)
	var h: float = _nonnegative(fractions, "H", "mass_fractions", errors)
	var o: float = _nonnegative(fractions, "O", "mass_fractions", errors)
	if absf(c + h + o - 1.0) > REL_TOL:
		errors.append("CHO mass fractions must sum to 1")
	var oxygen_per_kg: float = _oxygen_required(c, h, o)
	if oxygen_per_kg <= 0.0 or not _finite(oxygen_per_kg):
		errors.append("declared CHO component must require positive O2")
	var liquid_heat: float = _nonnegative(m, "liquid_heat_kj_kg", "phase_material", errors)
	var vapour_heat: float = _nonnegative(m, "vapour_heat_kj_kg", "phase_material", errors)
	var latent: float = _nonnegative(m, "phase_enthalpy_kj_kg", "phase_material", errors)
	if liquid_heat <= 0.0 or vapour_heat <= 0.0 or latent <= 0.0:
		errors.append("phase heat magnitudes must be positive")
	_check_balance(vapour_heat, liquid_heat + latent, ENERGY_ABS_TOL_KJ, "reference phase enthalpy", errors)
	var liquid: float = numbers["liquid_fuel_kg"]
	var vapour: float = numbers["vapour_fuel_kg"]
	var oxygen: float = numbers["o2_kg"]
	var budget: float = numbers["thermal_budget_kj"]
	var deposited: float = numbers["deposited_heat_kj"]
	var total_fuel: float = liquid + vapour
	if not _finite(total_fuel) or total_fuel > float(numbers["initial_fuel_mass_kg"]):
		errors.append("remaining liquid + vapour exceeds initial fuel mass")
	if not errors.is_empty():
		return _rejected(errors)
	var release_requested: float = numbers["release_kg"]
	var oxidation_requested: float = numbers["oxidation_kg"]
	var accepted: Dictionary = _accepted_masses(float(numbers["dt_s"]), release_requested,
		oxidation_requested, liquid, vapour, oxygen, oxygen_per_kg, "thermal_budgeted", budget, latent)
	var transferred: float = accepted["transferred"]
	var oxidized: float = accepted["oxidized"]
	var products: Dictionary = _oxidation_quantities(oxidized, oxygen, oxygen_per_kg, c, h)
	var phase_cost: float = minf(budget, transferred * latent)
	var phase_oxidation_heat: float = oxidized * vapour_heat
	var after: Dictionary = {
		"initial_fuel_mass_kg": float(numbers["initial_fuel_mass_kg"]),
		"liquid_fuel_kg": liquid - transferred,
		"vapour_fuel_kg": vapour + transferred - oxidized,
		"o2_kg": oxygen - float(products["o2_used"]),
		"thermal_budget_kj": budget - phase_cost,
		"deposited_heat_kj": deposited + phase_oxidation_heat,
	}
	var remaining: float = float(after["liquid_fuel_kg"]) + float(after["vapour_fuel_kg"])
	var balances: Dictionary = _mass_element_balance(total_fuel, oxygen, remaining,
		float(after["o2_kg"]), float(products["co2"]), float(products["water"]), c, h, o, errors)
	var potential_before: float = liquid * liquid_heat + vapour * vapour_heat
	var potential_after: float = float(after["liquid_fuel_kg"]) * liquid_heat + float(after["vapour_fuel_kg"]) * vapour_heat
	var total_before: float = potential_before + budget + deposited
	var total_after: float = potential_after + float(after["thermal_budget_kj"]) + float(after["deposited_heat_kj"])
	_check_balance(potential_before + transferred * latent, potential_after + phase_oxidation_heat,
		ENERGY_ABS_TOL_KJ, "phase potential", errors)
	_check_balance(budget, float(after["thermal_budget_kj"]) + phase_cost, ENERGY_ABS_TOL_KJ, "phase thermal budget", errors)
	_check_balance(total_before, total_after, ENERGY_ABS_TOL_KJ, "phase total energy", errors)
	for key in PHASE_STATE_KEYS:
		if not _finite(float(after[key])) or float(after[key]) < 0.0:
			errors.append("invalid phase candidate inventory: " + key)
	for quantity in [transferred, oxidized, phase_cost, phase_oxidation_heat, potential_before, potential_after]:
		if not _finite(float(quantity)) or float(quantity) < 0.0:
			errors.append("nonfinite or negative phase proposal quantity")
	if not errors.is_empty():
		return _rejected(errors)
	return {
		"valid": true, "errors": errors, "candidate": after,
		"accepted_release_kg": transferred, "rejected_release_kg": release_requested - transferred,
		"accepted_oxidation_kg": oxidized, "rejected_oxidation_kg": oxidation_requested - oxidized,
		"o2_consumed_kg": products["o2_used"], "products_kg": {"co2": products["co2"], "water_vapour": products["water"]},
		"phase_cost_kj": phase_cost, "oxidation_heat_kj": phase_oxidation_heat,
		"potential_before_kj": potential_before, "potential_after_kj": potential_after,
		"total_before_kj": total_before, "total_after_kj": total_after,
		"total_residual_kj": total_after - total_before,
		"mass_residual_kg": balances["mass_residual_kg"], "element_residuals_kg": balances["element_residuals_kg"],
		"scope": "reference_phase_budget_not_evaporation_or_material_calibration",
		"schema": "g3_phase_reference_budget_v1", "provenance": m["provenance"],
		"excluded": ["sensible_energy", "partial_oxidation", "evaporation_prediction", "transport", "engine_integration"],
	}


static func _oxygen_required(c: float, h: float, o: float) -> float:
	return (8.0 / 3.0) * c + 8.0 * h - o


static func _accepted_masses(dt_s: float, release_requested: float, oxidation_requested: float,
	reservoir: float, released: float, oxygen: float, oxygen_per_kg: float,
	mode: String, thermal_budget: float, gasification_heat: float) -> Dictionary:
	var transferred: float = 0.0
	var oxidized: float = 0.0
	if dt_s > 0.0:
		transferred = minf(release_requested, reservoir)
		if mode == "thermal_budgeted":
			transferred = minf(transferred, thermal_budget / gasification_heat)
		oxidized = minf(oxidation_requested, minf(released + transferred, oxygen / oxygen_per_kg))
	return {"transferred": transferred, "oxidized": oxidized}


static func _oxidation_quantities(oxidized: float, oxygen: float, oxygen_per_kg: float, c: float, h: float) -> Dictionary:
	# Preserve availability caps at the last floating-point ulp as well.
	var o2_used: float = minf(oxygen, oxidized * oxygen_per_kg)
	var co2: float = oxidized * c * (11.0 / 3.0)
	var water: float = oxidized * h * 9.0
	return {"o2_used": o2_used, "co2": co2, "water": water}


static func _mass_element_balance(total_fuel: float, oxygen: float, remaining: float,
	oxygen_after: float, co2: float, water: float, c: float, h: float, o: float,
	errors: Array[String]) -> Dictionary:
	var mass_before: float = total_fuel + oxygen
	var mass_after: float = remaining + oxygen_after + co2 + water
	var element_before: Dictionary = {
		"C": total_fuel * c, "H": total_fuel * h, "O": total_fuel * o + oxygen,
	}
	var element_after: Dictionary = {
		"C": remaining * c + co2 * (3.0 / 11.0),
		"H": remaining * h + water / 9.0,
		"O": remaining * o + oxygen_after + co2 * (8.0 / 11.0) + water * (8.0 / 9.0),
	}
	var element_residuals: Dictionary = {}
	for element in ELEMENTS:
		element_residuals[element] = float(element_after[element]) - float(element_before[element])
		_check_balance(float(element_before[element]), float(element_after[element]), MASS_ABS_TOL_KG, element, errors)
	_check_balance(mass_before, mass_after, MASS_ABS_TOL_KG, "mass", errors)
	return {"mass_residual_kg": mass_after - mass_before, "element_residuals_kg": element_residuals}


static func _dictionary(
	value: Variant, allowed: Array[String], label: String, errors: Array[String]
) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		errors.append(label + " must be a dictionary")
		return {}
	for key in value:
		if typeof(key) != TYPE_STRING or key not in allowed:
			errors.append(label + " has unsupported key: " + str(key))
	return value


static func _nonnegative(data: Dictionary, key: String, label: String, errors: Array[String]) -> float:
	var value: Variant = data.get(key)
	if typeof(value) not in [TYPE_FLOAT, TYPE_INT]:
		errors.append(label + "." + key + " must be a finite nonnegative number")
		return 0.0
	var number: float = float(value)
	if not _finite(number) or number < 0.0:
		errors.append(label + "." + key + " must be a finite nonnegative number")
		return 0.0
	return number


static func _finite(value: float) -> bool:
	return not is_nan(value) and not is_inf(value)


static func _check_balance(
	before: float, after: float, absolute_tol: float, label: String, errors: Array[String]
) -> void:
	var tolerance: float = absolute_tol + REL_TOL * maxf(absf(before), absf(after))
	if not _finite(before) or not _finite(after) or absf(after - before) > tolerance:
		errors.append(label + " balance is invalid")


static func _rejected(errors: Array[String]) -> Dictionary:
	return {"valid": false, "errors": errors, "candidate": {}}


## Explicit v3 isobaric enthalpy ledger. No zone EOS, thermal prediction or caller.
## Heating requests are prescribed kJ/STEP; insufficient B rejects atomically.
## O2/products at reference. Signed Q includes the oxidized fuel's sensible.
static func propose_phase_sensible(state: Variant, request: Variant, material: Variant) -> Dictionary:
	var errors: Array[String] = []
	var s: Dictionary = _sensible_closed(state, SENSIBLE_STATE_KEYS, "state", errors)
	var r: Dictionary = _sensible_closed(request, SENSIBLE_REQUEST_KEYS, "request", errors)
	var m: Dictionary = _sensible_closed(material, SENSIBLE_MATERIAL_KEYS, "material", errors)
	_sensible_literal(s, "schema", "g3_phase_sensible_state_v1", errors)
	_sensible_literal(m, "schema", "g3_phase_sensible_material_v1", errors)
	for data: Dictionary in [s, m]:
		if typeof(data.get("component_id")) != TYPE_STRING or data["component_id"].strip_edges().is_empty():
			errors.append("component_id must be nonempty String")
	if errors.is_empty() and s["component_id"] != m["component_id"]:
		errors.append("state/material component mismatch")
	var n: Dictionary = {}
	for key: String in PHASE_STATE_KEYS:
		n[key] = _sensible_number(s, key, key != "deposited_heat_kj", errors)
	for key: String in ["liquid_sensible_kj", "vapour_sensible_kj"]:
		n[key] = _sensible_number(s, key, false, errors)
	for key: String in SENSIBLE_REQUEST_KEYS:
		n[key] = _sensible_number(r, key, true, errors)
	var ref: Dictionary = _sensible_closed(m.get("reference_material"), PHASE_MATERIAL_KEYS, "reference", errors)
	# Old material validation is reused only after guarding its string comparisons.
	for key: String in ["schema", "liquid_phase", "vapour_phase", "water_product_phase",
		"atom_mass_basis", "chemical_energy_basis", "provenance"]:
		if typeof(ref.get(key)) != TYPE_STRING:
			errors.append("reference." + key + " must be String")
	var profiles: Dictionary = {}
	for key: String in ["liquid_profile", "vapour_profile"]:
		var checked: Dictionary = SensibleProperties.validate_profile(m.get(key))
		if not checked["valid"]:
			errors.append(key + ": " + str(checked["errors"]))
		else:
			profiles[key] = checked["candidate"]
			_sensible_literal(profiles[key], "phase", "liquid" if key == "liquid_profile" else "gas", errors)
			if typeof(m.get("component_id")) == TYPE_STRING:
				_sensible_literal(profiles[key], "component_id", m["component_id"], errors)
	if not errors.is_empty():
		return _sensible_rejected(errors)
	var audit_state: Dictionary = {}
	for key: String in PHASE_STATE_KEYS:
		audit_state[key] = n[key] if key not in ["thermal_budget_kj", "deposited_heat_kj"] else 0.0
	var audit: Dictionary = propose_phase_reference(audit_state,
		{"dt_s": 0.0, "release_kg": 0.0, "oxidation_kg": 0.0}, ref)
	if not audit["valid"]:
		errors.append("reference contract: " + str(audit["errors"]))
	var liquid: float = n["liquid_fuel_kg"]
	var vapour: float = n["vapour_fuel_kg"]
	var sl: float = n["liquid_sensible_kj"]
	var sv: float = n["vapour_sensible_kj"]
	_sensible_account(liquid, sl, profiles["liquid_profile"], "liquid initial", errors)
	_sensible_account(vapour, sv, profiles["vapour_profile"], "vapour initial", errors)
	var emission: Dictionary = SensibleProperties.evaluate(profiles["vapour_profile"], n["emitted_vapour_temperature_k"])
	if not emission["valid"]:
		errors.append("emitted vapour: " + str(emission["errors"]))
	if not errors.is_empty():
		return _sensible_rejected(errors)
	var heat_l: float = n["heat_liquid_kj"] if n["dt_s"] > 0.0 else 0.0
	var heat_v: float = n["heat_vapour_kj"] if n["dt_s"] > 0.0 else 0.0
	var heating: float = heat_l + heat_v
	var budget: float = n["thermal_budget_kj"]
	if not _finite(heating) or heating > budget:
		return _sensible_rejected(["prescribed heating exceeds independent B or overflows"])
	var heated_sl: float = sl + heat_l
	var heated_sv: float = sv + heat_v
	_sensible_account(liquid, heated_sl, profiles["liquid_profile"], "liquid heated", errors)
	_sensible_account(vapour, heated_sv, profiles["vapour_profile"], "vapour heated", errors)
	if not errors.is_empty():
		return _sensible_rejected(errors)
	var sl_specific: float = heated_sl / liquid if liquid > 0.0 else 0.0
	var emitted_specific: float = emission["candidate"]["specific_sensible_enthalpy_kj_kg"]
	var latent: float = ref["phase_enthalpy_kj_kg"]
	var cost_per_kg: float = latent
	if liquid > 0.0 and n["release_kg"] > 0.0 and n["dt_s"] > 0.0:
		cost_per_kg = latent + emitted_specific - sl_specific
	if not _finite(cost_per_kg) or cost_per_kg <= 0.0:
		return _sensible_rejected(["nonpositive or nonfinite release cost requires another contract"])
	var available_budget: float = budget - heating
	var release_deficit: float = maxf(0.0, minf(float(n["release_kg"]), liquid) * cost_per_kg - available_budget) if n["dt_s"] > 0.0 else 0.0
	if not _finite(release_deficit):
		return _sensible_rejected(["reported release budget deficit overflow"])
	var fractions: Dictionary = ref["mass_fractions"]
	var c: float = fractions["C"]
	var h: float = fractions["H"]
	var o: float = fractions["O"]
	var oxygen: float = n["o2_kg"]
	var oxygen_per_kg: float = _oxygen_required(c, h, o)
	var accepted: Dictionary = _accepted_masses(n["dt_s"], n["release_kg"], n["oxidation_kg"],
		liquid, vapour, oxygen, oxygen_per_kg, "thermal_budgeted", available_budget, cost_per_kg)
	var transferred: float = accepted["transferred"]
	var oxidized: float = accepted["oxidized"]
	var products: Dictionary = _oxidation_quantities(oxidized, oxygen, oxygen_per_kg, c, h)
	var release_cost: float = minf(available_budget, transferred * cost_per_kg)
	var mixed_mass: float = vapour + transferred
	var mixed_sensible: float = heated_sv + transferred * emitted_specific
	if not _finite(mixed_mass) or not _finite(mixed_sensible):
		return _sensible_rejected(["vapour mixing overflow"])
	var mixed_specific: float = mixed_sensible / mixed_mass if mixed_mass > 0.0 else 0.0
	var oxidized_sensible: float = oxidized * mixed_specific
	var chemical_heat: float = oxidized * float(ref["vapour_heat_kj_kg"])
	var deposited_increment: float = chemical_heat + oxidized_sensible
	var after: Dictionary = {"schema": s["schema"], "component_id": s["component_id"],
		"initial_fuel_mass_kg": n["initial_fuel_mass_kg"], "liquid_fuel_kg": liquid - float(transferred),
		"vapour_fuel_kg": mixed_mass - oxidized, "o2_kg": oxygen - float(products["o2_used"]),
		"thermal_budget_kj": available_budget - release_cost,
		"deposited_heat_kj": n["deposited_heat_kj"] + deposited_increment,
		"liquid_sensible_kj": (liquid - transferred) * sl_specific,
		"vapour_sensible_kj": (mixed_mass - oxidized) * mixed_specific}
	# Preserve idle accounts bit-for-bit rather than round-tripping S/m*m.
	if heating == 0.0 and transferred == 0.0 and oxidized == 0.0:
		after = s.duplicate(true)
	_sensible_account(after["liquid_fuel_kg"], after["liquid_sensible_kj"], profiles["liquid_profile"], "liquid final", errors)
	_sensible_account(after["vapour_fuel_kg"], after["vapour_sensible_kj"], profiles["vapour_profile"], "vapour final", errors)
	var a_before: float = liquid * float(ref["liquid_heat_kj_kg"]) + vapour * float(ref["vapour_heat_kj_kg"])
	var a_after: float = float(after["liquid_fuel_kg"]) * float(ref["liquid_heat_kj_kg"]) + float(after["vapour_fuel_kg"]) * float(ref["vapour_heat_kj_kg"])
	var sensible_before: float = sl + sv
	var sensible_after: float = float(after["liquid_sensible_kj"]) + float(after["vapour_sensible_kj"])
	var release_sensible: float = transferred * (emitted_specific - sl_specific)
	var total_before: float = a_before + sensible_before + budget + float(n["deposited_heat_kj"])
	var total_after: float = a_after + sensible_after + float(after["thermal_budget_kj"]) + float(after["deposited_heat_kj"])
	_check_balance(a_before + transferred * latent, a_after + chemical_heat, ENERGY_ABS_TOL_KJ, "sensible A", errors)
	_check_balance(sensible_before + heating + release_sensible, sensible_after + oxidized_sensible, ENERGY_ABS_TOL_KJ, "sensible S", errors)
	_check_balance(budget, float(after["thermal_budget_kj"]) + heating + release_cost, ENERGY_ABS_TOL_KJ, "sensible B", errors)
	_check_balance(float(n["deposited_heat_kj"]) + deposited_increment, float(after["deposited_heat_kj"]), ENERGY_ABS_TOL_KJ, "sensible Q", errors)
	_check_balance(total_before, total_after, ENERGY_ABS_TOL_KJ, "sensible total", errors)
	var balances: Dictionary = _mass_element_balance(liquid + vapour, oxygen,
		float(after["liquid_fuel_kg"]) + float(after["vapour_fuel_kg"]), after["o2_kg"],
		products["co2"], products["water"], c, h, o, errors)
	for key: String in PHASE_STATE_KEYS:
		if not _finite(float(after[key])) or (key != "deposited_heat_kj" and float(after[key]) < 0.0):
			errors.append("invalid sensible candidate: " + key)
	for quantity: float in [sl_specific, emitted_specific, mixed_specific, oxidized_sensible,
		chemical_heat, deposited_increment, release_sensible, total_before, total_after]:
		if not _finite(quantity):
			errors.append("nonfinite sensible intermediate")
	if not errors.is_empty():
		return _sensible_rejected(errors)
	return {"valid": true, "errors": [], "candidate": after,
		"schema": "g3_phase_sensible_budget_v1", "scope": "synthetic_isobaric_ledger_not_material_calibration",
		"physical_approval": false, "integration_enabled": false, "product_activation": false,
		"accepted_release_kg": transferred, "rejected_release_kg": float(n["release_kg"]) - transferred,
		"accepted_oxidation_kg": oxidized, "rejected_oxidation_kg": float(n["oxidation_kg"]) - oxidized,
		"accepted_heating_kj": heating, "release_cost_kj": release_cost, "release_cost_kj_kg": cost_per_kg,
		"release_budget_deficit_kj": release_deficit,
		"chemical_oxidation_heat_kj": chemical_heat, "oxidized_sensible_kj": oxidized_sensible,
		"deposited_increment_kj": deposited_increment, "o2_consumed_kg": products["o2_used"],
		"products_kg": {"co2": products["co2"], "water_vapour": products["water"]},
		"potential_before_kj": a_before, "potential_after_kj": a_after,
		"sensible_before_kj": sensible_before, "sensible_after_kj": sensible_after,
		"total_before_kj": total_before, "total_after_kj": total_after,
		"total_residual_kj": total_after - total_before,
		"mass_residual_kg": balances["mass_residual_kg"], "element_residuals_kg": balances["element_residuals_kg"],
		"excluded": ["cooling", "hot_oxidant_products", "enthalpy_to_EOS", "evaporation_prediction", "engine_integration"]}


static func _sensible_closed(value: Variant, keys: Array[String], label: String, errors: Array[String]) -> Dictionary:
	var result: Dictionary = _dictionary(value, keys, label, errors)
	for key: String in keys:
		if not result.has(key):
			errors.append(label + " missing " + key)
	return result


static func _sensible_literal(data: Dictionary, key: String, expected: String, errors: Array[String]) -> void:
	if typeof(data.get(key)) != TYPE_STRING or data[key] != expected:
		errors.append("incompatible " + key)


static func _sensible_number(data: Dictionary, key: String, nonnegative: bool, errors: Array[String]) -> float:
	var value: Variant = data.get(key)
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT]:
		errors.append(key + " must be finite numeric, never bool")
		return 0.0
	var number: float = float(value)
	if not _finite(number) or (nonnegative and number < 0.0):
		errors.append("invalid numeric " + key)
		return 0.0
	return number


static func _sensible_account(mass: float, sensible: float, profile: Dictionary, label: String, errors: Array[String]) -> void:
	if not _finite(mass) or mass < 0.0 or not _finite(sensible):
		errors.append(label + " invalid mass/sensible")
		return
	if mass == 0.0:
		if sensible != 0.0:
			errors.append(label + " absent phase requires zero sensible")
		return
	var samples: Array = profile["samples"]
	var low: Dictionary = SensibleProperties.evaluate(profile, samples[0]["temperature_k"])
	var high: Dictionary = SensibleProperties.evaluate(profile, samples[-1]["temperature_k"])
	if not low["valid"] or not high["valid"]:
		errors.append(label + " profile endpoint overflow")
		return
	var lower: float = mass * float(low["candidate"]["specific_sensible_enthalpy_kj_kg"])
	var upper: float = mass * float(high["candidate"]["specific_sensible_enthalpy_kj_kg"])
	if not _finite(lower) or not _finite(upper) or sensible < lower or sensible > upper:
		errors.append(label + " sensible outside declared support")


static func _sensible_rejected(errors: Array[String]) -> Dictionary:
	return {"valid": false, "errors": errors, "candidate": {},
		"schema": "g3_phase_sensible_budget_v1", "scope": "synthetic_isobaric_ledger_not_material_calibration",
		"physical_approval": false, "integration_enabled": false, "product_activation": false}

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
	if m.get("chemical_energy_basis") != "complete_oxidation_net":
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
		if m.get(key) != required[key]:
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

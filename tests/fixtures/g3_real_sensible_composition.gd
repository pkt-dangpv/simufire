extends SceneTree

## Isolated composition of the approved real n-heptane profiles, the sensible
## ledger and its atomic owner. The expected numbers are NOT taken from the
## owner: an independent Python restatement of the step law writes them (see
## scripts/simulation/build_g3_real_sensible_composition.py). The property data
## are shared with it; the method is not. A failed check is recorded and the
## run goes on, so a broken mutant does not become an unrelated script error.
const Budget = preload("res://sim/fire/FuelMassBudgetModel.gd")
const Real = preload("res://sim/fire/HeptaneRealCpProfiles.gd")
const Owner = preload("res://sim/fire/PrescribedRealSensiblePhaseController.gd")
const Synthetic = preload("res://sim/fire/PrescribedSensiblePhaseController.gd")
const LIQUID: String = "g3_real_liquid_isobaric_cp_v1"
const GAS: String = "g3_real_ideal_gas_cp_v1"
const APPROVALS: Array[String] = ["scientific_approval", "predictive_evaporation_approval",
	"engine_integration", "production_activation", "co_fed_approval", "fire_validation_approval"]
const PHASE_NUMBERS: Array[String] = ["initial_fuel_mass_kg", "liquid_fuel_kg", "vapour_fuel_kg",
	"o2_kg", "thermal_budget_kj", "deposited_heat_kj", "liquid_sensible_kj", "vapour_sensible_kj"]
const STEP_NUMBERS: Array[String] = ["physical_dt_s", "source_dt_s", "requested_release_kg",
	"accepted_release_kg", "rejected_release_kg", "accepted_oxidation_kg", "rejected_oxidation_kg",
	"release_cost_kj", "release_cost_kj_kg", "heating_liquid_kj", "heating_vapour_kj",
	"released_liquid_sensible_kj", "emitted_vapour_sensible_kj", "oxidized_sensible_kj",
	"chemical_oxidation_heat_kj", "deposited_increment_kj", "co2_kg", "water_vapour_kg", "o2_consumed_kg"]
const ACCOUNTS: Array[String] = ["potential_a_kj", "sensible_s_kj", "budget_b_kj", "deposited_q_kj", "total_kj"]
# BEGIN GENERATED COMPOSITION EXPECTATIONS (scripts/simulation/build_g3_real_sensible_composition.py)
const EXPECTED: Dictionary = {
	"liquid_support_kj_kg": [-40.165288739730016, 174.59886923508722],
	"gas_support_kj_kg": [-0.023951505536310806, 348.3918196182203],
	"liquid_support_k": [279.985531, 371.102911],
	"gas_support_k": [298.135458, 469.991581],
	"molar_mass_g_mol": [100.2, 100.2],
	"nominal_molar_mass_g_mol": 100.0,
	"analytic": {
		"context": {
			"schema": "g3_prescribed_real_sensible_context_v1",
			"program": {
				"profile_id": "declared_ramp",
				"component_id": "n-heptane",
				"initial_mass_kg": 1.0,
				"mode": "prescribed",
				"quantity": "modeled_component_emission",
				"unit": "kg/s",
				"time_origin": "declared_zero",
				"outside_domain": "reject",
				"interpolation": "piecewise_linear",
				"samples": [
					{"time_s": 0.0, "rate_kg_s": 0.05},
					{"time_s": 4.0, "rate_kg_s": 0.05},
					{"time_s": 8.0, "rate_kg_s": 0.0},
				],
			},
			"material": {
				"schema": "g3_phase_real_sensible_material_v1",
				"component_id": "n-heptane",
				"reference_material": {
					"schema": "g3_phase_reference_CHO_material_v1",
					"liquid_phase": "liquid",
					"vapour_phase": "gas",
					"water_product_phase": "gas",
					"atom_mass_basis": "nominal_C12_H1_O16",
					"chemical_energy_basis": "complete_oxidation_net",
					"reference_temperature_k": 298.15,
					"reference_pressure_pa": 100000.0,
					"mass_fractions": {
						"C": 0.84,
						"H": 0.16000000000000003,
						"O": 0.0,
					},
					"liquid_heat_kj_kg": 44559.68063872255,
					"vapour_heat_kj_kg": 44925.44910179641,
					"phase_enthalpy_kj_kg": 365.7684630738523,
					"provenance": "declared prototype: NIST TN 2126-upd1 heats per kg on 100.20 g/mol with nominal C7H16 atom fractions; not a heptane calibration",
				},
			},
			"attribution": {
				"input_component_id": "n-heptane",
				"modeled_component_id": "n-heptane",
				"input_quantity": "modeled_component_emission",
				"rule": "same_declared_component",
				"status": "synthetic_declared_emission",
				"provenance": "declared: prescribed emission program, not a measured or predicted evaporation",
			},
			"seed": {
				"schema": "g3_prescribed_real_sensible_seed_v1",
				"initial_o2_kg": 10.0,
				"initial_thermal_budget_kj": 600.0,
				"initial_liquid_sensible_kj": 73.35990741649884,
				"energy_boundary_kind": "synthetic_independent_initial_budget",
				"energy_boundary_provenance": "synthetic: independent initial budget, not a measured heat flux",
			},
		},
		"steps": [
			{
				"request": [1.0, 0.0, 0.0, 0.0, 399.968914],
				"release_cost_kj_kg": 483.30829845011766,
				"phase": {
					"initial_fuel_mass_kg": 1.0,
					"liquid_fuel_kg": 0.95,
					"vapour_fuel_kg": 0.05,
					"o2_kg": 10.0,
					"thermal_budget_kj": 575.8345850774941,
					"deposited_heat_kj": 0.0,
					"liquid_sensible_kj": 69.6919120456739,
					"vapour_sensible_kj": 9.544987139638213,
				},
				"potential_a_kj": 44577.96906187624,
				"total_kj": 45233.04054613905,
			},
			{
				"request": [2.0, 0.04, 22.71548350968054, 0.0, 399.968914],
				"release_cost_kj_kg": 459.39726317676974,
				"phase": {
					"initial_fuel_mass_kg": 1.0,
					"liquid_fuel_kg": 0.9,
					"vapour_fuel_kg": 0.060000000000000005,
					"o2_kg": 9.8592,
					"thermal_budget_kj": 530.1492384089751,
					"deposited_heat_kj": 1804.653953783567,
					"liquid_sensible_kj": 87.5438484208621,
					"vapour_sensible_kj": 11.453984567565856,
				},
				"potential_a_kj": 42799.23952095808,
				"total_kj": 45233.04054613905,
			},
		],
		"liquid_knot_k": 329.965047,
		"next_liquid_knot_k": 339.964031,
		"gas_knot_k": 399.968914,
		"knot_enthalpies_kj_kg": [73.35990741649884, 97.27094268984678, 190.89974279276424],
	},
	"sequences": {
		"main": {
			"context": {
				"schema": "g3_prescribed_real_sensible_context_v1",
				"program": {
					"profile_id": "declared_ramp",
					"component_id": "n-heptane",
					"initial_mass_kg": 1.0,
					"mode": "prescribed",
					"quantity": "modeled_component_emission",
					"unit": "kg/s",
					"time_origin": "declared_zero",
					"outside_domain": "reject",
					"interpolation": "piecewise_linear",
					"samples": [
						{"time_s": 0.0, "rate_kg_s": 0.05},
						{"time_s": 4.0, "rate_kg_s": 0.05},
						{"time_s": 8.0, "rate_kg_s": 0.0},
					],
				},
				"material": {
					"schema": "g3_phase_real_sensible_material_v1",
					"component_id": "n-heptane",
					"reference_material": {
						"schema": "g3_phase_reference_CHO_material_v1",
						"liquid_phase": "liquid",
						"vapour_phase": "gas",
						"water_product_phase": "gas",
						"atom_mass_basis": "nominal_C12_H1_O16",
						"chemical_energy_basis": "complete_oxidation_net",
						"reference_temperature_k": 298.15,
						"reference_pressure_pa": 100000.0,
						"mass_fractions": {
							"C": 0.84,
							"H": 0.16000000000000003,
							"O": 0.0,
						},
						"liquid_heat_kj_kg": 44559.68063872255,
						"vapour_heat_kj_kg": 44925.44910179641,
						"phase_enthalpy_kj_kg": 365.7684630738523,
						"provenance": "declared prototype: NIST TN 2126-upd1 heats per kg on 100.20 g/mol with nominal C7H16 atom fractions; not a heptane calibration",
					},
				},
				"attribution": {
					"input_component_id": "n-heptane",
					"modeled_component_id": "n-heptane",
					"input_quantity": "modeled_component_emission",
					"rule": "same_declared_component",
					"status": "synthetic_declared_emission",
					"provenance": "declared: prescribed emission program, not a measured or predicted evaporation",
				},
				"seed": {
					"schema": "g3_prescribed_real_sensible_seed_v1",
					"initial_o2_kg": 10.0,
					"initial_thermal_budget_kj": 600.0,
					"initial_liquid_sensible_kj": -5.0,
					"energy_boundary_kind": "synthetic_independent_initial_budget",
					"energy_boundary_provenance": "synthetic: independent initial budget, not a measured heat flux",
				},
			},
			"steps": [
				{
					"request": [1.0, 0.0, 100.0, 0.0, 371.0],
					"accepted": true,
					"step": {
						"no_op": false,
						"physical_dt_s": 1.0,
						"source_dt_s": 1.0,
						"requested_release_kg": 0.05,
						"accepted_release_kg": 0.05,
						"rejected_release_kg": 0.0,
						"accepted_oxidation_kg": 0.0,
						"rejected_oxidation_kg": 0.0,
						"release_cost_kj": 20.132317468422173,
						"release_cost_kj_kg": 402.6463493684434,
						"heating_liquid_kj": 100.0,
						"heating_vapour_kj": 0.0,
						"released_liquid_sensible_kj": 4.75,
						"emitted_vapour_sensible_kj": 6.593894314729557,
						"oxidized_sensible_kj": 0.0,
						"chemical_oxidation_heat_kj": 0.0,
						"deposited_increment_kj": 0.0,
						"co2_kg": 0.0,
						"water_vapour_kg": 0.0,
						"o2_consumed_kg": 0.0,
						"mixed_specific_kj_kg": 131.87788629459112,
						"temperature_average_specific_kj_kg": null,
						"emitted_kinds": ["assumption_adopted_by_source_for_vapour_pressure_consistency", "fitted_correlation_of_cited_flow_calorimetry_extrapolated_to_zero_pressure"],
					},
					"phase": {
						"initial_fuel_mass_kg": 1.0,
						"liquid_fuel_kg": 0.95,
						"vapour_fuel_kg": 0.05,
						"o2_kg": 10.0,
						"thermal_budget_kj": 479.8676825315778,
						"deposited_heat_kj": 0.0,
						"liquid_sensible_kj": 90.25,
						"vapour_sensible_kj": 6.593894314729557,
					},
					"time_s": 1.0,
					"accounts": {
						"potential_a_kj": 44577.96906187624,
						"sensible_s_kj": 96.84389431472955,
						"budget_b_kj": 479.8676825315778,
						"deposited_q_kj": 0.0,
						"total_kj": 45154.680638722544,
					},
					"liquid_kinds": ["tabulated_Csat_of_the_source_converted_to_Cp_here"],
					"vapour_kinds": ["assumption_adopted_by_source_for_vapour_pressure_consistency", "fitted_correlation_of_cited_flow_calorimetry_extrapolated_to_zero_pressure"],
				},
				{
					"request": [2.0, 0.03, 50.0, 2.0, 350.0],
					"accepted": true,
					"step": {
						"no_op": false,
						"physical_dt_s": 1.0,
						"source_dt_s": 1.0,
						"requested_release_kg": 0.05,
						"accepted_release_kg": 0.05,
						"rejected_release_kg": 0.0,
						"accepted_oxidation_kg": 0.03,
						"rejected_oxidation_kg": 0.0,
						"release_cost_kj": 15.478077621940628,
						"release_cost_kj_kg": 309.56155243881256,
						"heating_liquid_kj": 50.0,
						"heating_vapour_kj": 2.0,
						"released_liquid_sensible_kj": 7.381578947368422,
						"emitted_vapour_sensible_kj": 4.571233415616435,
						"oxidized_sensible_kj": 3.9495383191037976,
						"chemical_oxidation_heat_kj": 1347.7634730538923,
						"deposited_increment_kj": 1351.713011372996,
						"co2_kg": 0.09239999999999998,
						"water_vapour_kg": 0.0432,
						"o2_consumed_kg": 0.1056,
						"mixed_specific_kj_kg": 131.65127730345992,
						"temperature_average_specific_kj_kg": 130.7227667699046,
						"emitted_kinds": ["assumption_adopted_by_source_for_vapour_pressure_consistency"],
					},
					"phase": {
						"initial_fuel_mass_kg": 1.0,
						"liquid_fuel_kg": 0.8999999999999999,
						"vapour_fuel_kg": 0.07,
						"o2_kg": 9.8944,
						"thermal_budget_kj": 412.3896049096372,
						"deposited_heat_kj": 1351.713011372996,
						"liquid_sensible_kj": 132.8684210526316,
						"vapour_sensible_kj": 9.215589411242195,
					},
					"time_s": 2.0,
					"accounts": {
						"potential_a_kj": 43248.49401197604,
						"sensible_s_kj": 142.0840104638738,
						"budget_b_kj": 412.3896049096372,
						"deposited_q_kj": 1351.713011372996,
						"total_kj": 45154.68063872255,
					},
					"liquid_kinds": ["tabulated_Csat_of_the_source_converted_to_Cp_here", "same_table_with_source_error_rising_above_360_K"],
					"vapour_kinds": ["assumption_adopted_by_source_for_vapour_pressure_consistency", "fitted_correlation_of_cited_flow_calorimetry_extrapolated_to_zero_pressure"],
				},
				{
					"request": [2.0, 0.5, 9.0, 9.0, 400.0],
					"accepted": true,
					"step": {"no_op": true},
					"phase": {
						"initial_fuel_mass_kg": 1.0,
						"liquid_fuel_kg": 0.8999999999999999,
						"vapour_fuel_kg": 0.07,
						"o2_kg": 9.8944,
						"thermal_budget_kj": 412.3896049096372,
						"deposited_heat_kj": 1351.713011372996,
						"liquid_sensible_kj": 132.8684210526316,
						"vapour_sensible_kj": 9.215589411242195,
					},
					"time_s": 2.0,
					"accounts": {
						"potential_a_kj": 43248.49401197604,
						"sensible_s_kj": 142.0840104638738,
						"budget_b_kj": 412.3896049096372,
						"deposited_q_kj": 1351.713011372996,
						"total_kj": 45154.68063872255,
					},
					"liquid_kinds": ["tabulated_Csat_of_the_source_converted_to_Cp_here", "same_table_with_source_error_rising_above_360_K"],
					"vapour_kinds": ["assumption_adopted_by_source_for_vapour_pressure_consistency", "fitted_correlation_of_cited_flow_calorimetry_extrapolated_to_zero_pressure"],
				},
				{
					"request": [3.0, 0.5, 0.0, 0.0, 420.0],
					"accepted": true,
					"step": {
						"no_op": false,
						"physical_dt_s": 1.0,
						"source_dt_s": 1.0,
						"requested_release_kg": 0.05,
						"accepted_release_kg": 0.05,
						"rejected_release_kg": 0.0,
						"accepted_oxidation_kg": 0.12000000000000001,
						"rejected_oxidation_kg": 0.38,
						"release_cost_kj": 22.5993313522075,
						"release_cost_kj_kg": 451.98662704414994,
						"heating_liquid_kj": 0.0,
						"heating_vapour_kj": 0.0,
						"released_liquid_sensible_kj": 7.381578947368422,
						"emitted_vapour_sensible_kj": 11.692487145883305,
						"oxidized_sensible_kj": 20.9080765571255,
						"chemical_oxidation_heat_kj": 5391.053892215569,
						"deposited_increment_kj": 5411.9619687726945,
						"co2_kg": 0.3696,
						"water_vapour_kg": 0.17280000000000004,
						"o2_consumed_kg": 0.42240000000000005,
						"mixed_specific_kj_kg": 174.23397130937917,
						"temperature_average_specific_kj_kg": 172.95278680808678,
						"emitted_kinds": ["assumption_adopted_by_source_for_vapour_pressure_consistency", "fitted_correlation_of_cited_flow_calorimetry_extrapolated_to_zero_pressure"],
					},
					"phase": {
						"initial_fuel_mass_kg": 1.0,
						"liquid_fuel_kg": 0.8499999999999999,
						"vapour_fuel_kg": 0.0,
						"o2_kg": 9.472,
						"thermal_budget_kj": 389.7902735574297,
						"deposited_heat_kj": 6763.674980145691,
						"liquid_sensible_kj": 125.48684210526315,
						"vapour_sensible_kj": 0.0,
					},
					"time_s": 3.0,
					"accounts": {
						"potential_a_kj": 37875.72854291416,
						"sensible_s_kj": 125.48684210526315,
						"budget_b_kj": 389.7902735574297,
						"deposited_q_kj": 6763.674980145691,
						"total_kj": 45154.680638722544,
					},
					"liquid_kinds": ["tabulated_Csat_of_the_source_converted_to_Cp_here", "same_table_with_source_error_rising_above_360_K"],
					"vapour_kinds": [],
				},
				{
					"request": [5.0, 0.01, 10.0, 1.0, 469.0],
					"accepted": false,
					"step": {},
					"phase": {
						"initial_fuel_mass_kg": 1.0,
						"liquid_fuel_kg": 0.8499999999999999,
						"vapour_fuel_kg": 0.0,
						"o2_kg": 9.472,
						"thermal_budget_kj": 389.7902735574297,
						"deposited_heat_kj": 6763.674980145691,
						"liquid_sensible_kj": 125.48684210526315,
						"vapour_sensible_kj": 0.0,
					},
					"time_s": 3.0,
					"accounts": {
						"potential_a_kj": 37875.72854291416,
						"sensible_s_kj": 125.48684210526315,
						"budget_b_kj": 389.7902735574297,
						"deposited_q_kj": 6763.674980145691,
						"total_kj": 45154.680638722544,
					},
					"liquid_kinds": ["tabulated_Csat_of_the_source_converted_to_Cp_here", "same_table_with_source_error_rising_above_360_K"],
					"vapour_kinds": [],
				},
				{
					"request": [9.0, 0.0, 0.0, 0.0, 298.15],
					"accepted": true,
					"step": {
						"no_op": false,
						"physical_dt_s": 6.0,
						"source_dt_s": 5.0,
						"requested_release_kg": 0.15000000000000002,
						"accepted_release_kg": 0.15000000000000002,
						"rejected_release_kg": 0.0,
						"accepted_oxidation_kg": 0.0,
						"rejected_oxidation_kg": 0.0,
						"release_cost_kj": 32.72053261897258,
						"release_cost_kj_kg": 218.13688412648384,
						"heating_liquid_kj": 0.0,
						"heating_vapour_kj": 0.0,
						"released_liquid_sensible_kj": 22.14473684210527,
						"emitted_vapour_sensible_kj": 0.0,
						"oxidized_sensible_kj": 0.0,
						"chemical_oxidation_heat_kj": 0.0,
						"deposited_increment_kj": 0.0,
						"co2_kg": 0.0,
						"water_vapour_kg": 0.0,
						"o2_consumed_kg": 0.0,
						"mixed_specific_kj_kg": 0.0,
						"temperature_average_specific_kj_kg": null,
						"emitted_kinds": ["assumption_adopted_by_source_for_vapour_pressure_consistency"],
					},
					"phase": {
						"initial_fuel_mass_kg": 1.0,
						"liquid_fuel_kg": 0.6999999999999998,
						"vapour_fuel_kg": 0.15000000000000002,
						"o2_kg": 9.472,
						"thermal_budget_kj": 357.06974093845713,
						"deposited_heat_kj": 6763.674980145691,
						"liquid_sensible_kj": 103.34210526315789,
						"vapour_sensible_kj": 0.0,
					},
					"time_s": 9.0,
					"accounts": {
						"potential_a_kj": 37930.59381237524,
						"sensible_s_kj": 103.34210526315789,
						"budget_b_kj": 357.06974093845713,
						"deposited_q_kj": 6763.674980145691,
						"total_kj": 45154.68063872255,
					},
					"liquid_kinds": ["tabulated_Csat_of_the_source_converted_to_Cp_here", "same_table_with_source_error_rising_above_360_K"],
					"vapour_kinds": ["assumption_adopted_by_source_for_vapour_pressure_consistency"],
				},
			],
		},
		"budget_limited": {
			"context": {
				"schema": "g3_prescribed_real_sensible_context_v1",
				"program": {
					"profile_id": "declared_ramp",
					"component_id": "n-heptane",
					"initial_mass_kg": 1.0,
					"mode": "prescribed",
					"quantity": "modeled_component_emission",
					"unit": "kg/s",
					"time_origin": "declared_zero",
					"outside_domain": "reject",
					"interpolation": "piecewise_linear",
					"samples": [
						{"time_s": 0.0, "rate_kg_s": 0.05},
						{"time_s": 4.0, "rate_kg_s": 0.05},
						{"time_s": 8.0, "rate_kg_s": 0.0},
					],
				},
				"material": {
					"schema": "g3_phase_real_sensible_material_v1",
					"component_id": "n-heptane",
					"reference_material": {
						"schema": "g3_phase_reference_CHO_material_v1",
						"liquid_phase": "liquid",
						"vapour_phase": "gas",
						"water_product_phase": "gas",
						"atom_mass_basis": "nominal_C12_H1_O16",
						"chemical_energy_basis": "complete_oxidation_net",
						"reference_temperature_k": 298.15,
						"reference_pressure_pa": 100000.0,
						"mass_fractions": {
							"C": 0.84,
							"H": 0.16000000000000003,
							"O": 0.0,
						},
						"liquid_heat_kj_kg": 44559.68063872255,
						"vapour_heat_kj_kg": 44925.44910179641,
						"phase_enthalpy_kj_kg": 365.7684630738523,
						"provenance": "declared prototype: NIST TN 2126-upd1 heats per kg on 100.20 g/mol with nominal C7H16 atom fractions; not a heptane calibration",
					},
				},
				"attribution": {
					"input_component_id": "n-heptane",
					"modeled_component_id": "n-heptane",
					"input_quantity": "modeled_component_emission",
					"rule": "same_declared_component",
					"status": "synthetic_declared_emission",
					"provenance": "declared: prescribed emission program, not a measured or predicted evaporation",
				},
				"seed": {
					"schema": "g3_prescribed_real_sensible_seed_v1",
					"initial_o2_kg": 10.0,
					"initial_thermal_budget_kj": 30.0,
					"initial_liquid_sensible_kj": 0.0,
					"energy_boundary_kind": "synthetic_independent_initial_budget",
					"energy_boundary_provenance": "synthetic: independent initial budget, not a measured heat flux",
				},
			},
			"steps": [
				{
					"request": [1.0, 0.0, 20.0, 0.0, 371.0],
					"accepted": true,
					"step": {
						"no_op": false,
						"physical_dt_s": 1.0,
						"source_dt_s": 1.0,
						"requested_release_kg": 0.05,
						"accepted_release_kg": 0.020935991687620482,
						"rejected_release_kg": 0.02906400831237952,
						"accepted_oxidation_kg": 0.0,
						"rejected_oxidation_kg": 0.0,
						"release_cost_kj": 10.0,
						"release_cost_kj_kg": 477.6463493684434,
						"heating_liquid_kj": 20.0,
						"heating_vapour_kj": 0.0,
						"released_liquid_sensible_kj": 0.4187198337524096,
						"emitted_vapour_sensible_kj": 2.7609943312445187,
						"oxidized_sensible_kj": 0.0,
						"chemical_oxidation_heat_kj": 0.0,
						"deposited_increment_kj": 0.0,
						"co2_kg": 0.0,
						"water_vapour_kg": 0.0,
						"o2_consumed_kg": 0.0,
						"mixed_specific_kj_kg": 131.87788629459112,
						"temperature_average_specific_kj_kg": null,
						"emitted_kinds": ["assumption_adopted_by_source_for_vapour_pressure_consistency", "fitted_correlation_of_cited_flow_calorimetry_extrapolated_to_zero_pressure"],
					},
					"phase": {
						"initial_fuel_mass_kg": 1.0,
						"liquid_fuel_kg": 0.9790640083123795,
						"vapour_fuel_kg": 0.020935991687620482,
						"o2_kg": 10.0,
						"thermal_budget_kj": 0.0,
						"deposited_heat_kj": 0.0,
						"liquid_sensible_kj": 19.58128016624759,
						"vapour_sensible_kj": 2.7609943312445187,
					},
					"time_s": 1.0,
					"accounts": {
						"potential_a_kj": 44567.33836422506,
						"sensible_s_kj": 22.34227449749211,
						"budget_b_kj": 0.0,
						"deposited_q_kj": 0.0,
						"total_kj": 44589.68063872255,
					},
					"liquid_kinds": ["tabulated_Csat_of_the_source_converted_to_Cp_here"],
					"vapour_kinds": ["assumption_adopted_by_source_for_vapour_pressure_consistency", "fitted_correlation_of_cited_flow_calorimetry_extrapolated_to_zero_pressure"],
				},
				{
					"request": [2.0, 0.0, 0.0, 0.0, 371.0],
					"accepted": true,
					"step": {
						"no_op": false,
						"physical_dt_s": 1.0,
						"source_dt_s": 1.0,
						"requested_release_kg": 0.05,
						"accepted_release_kg": 0.0,
						"rejected_release_kg": 0.05,
						"accepted_oxidation_kg": 0.0,
						"rejected_oxidation_kg": 0.0,
						"release_cost_kj": 0.0,
						"release_cost_kj_kg": 477.6463493684434,
						"heating_liquid_kj": 0.0,
						"heating_vapour_kj": 0.0,
						"released_liquid_sensible_kj": 0.0,
						"emitted_vapour_sensible_kj": 0.0,
						"oxidized_sensible_kj": 0.0,
						"chemical_oxidation_heat_kj": 0.0,
						"deposited_increment_kj": 0.0,
						"co2_kg": 0.0,
						"water_vapour_kg": 0.0,
						"o2_consumed_kg": 0.0,
						"mixed_specific_kj_kg": 131.87788629459112,
						"temperature_average_specific_kj_kg": null,
						"emitted_kinds": ["assumption_adopted_by_source_for_vapour_pressure_consistency", "fitted_correlation_of_cited_flow_calorimetry_extrapolated_to_zero_pressure"],
					},
					"phase": {
						"initial_fuel_mass_kg": 1.0,
						"liquid_fuel_kg": 0.9790640083123795,
						"vapour_fuel_kg": 0.020935991687620482,
						"o2_kg": 10.0,
						"thermal_budget_kj": 0.0,
						"deposited_heat_kj": 0.0,
						"liquid_sensible_kj": 19.58128016624759,
						"vapour_sensible_kj": 2.7609943312445187,
					},
					"time_s": 2.0,
					"accounts": {
						"potential_a_kj": 44567.33836422506,
						"sensible_s_kj": 22.34227449749211,
						"budget_b_kj": 0.0,
						"deposited_q_kj": 0.0,
						"total_kj": 44589.68063872255,
					},
					"liquid_kinds": ["tabulated_Csat_of_the_source_converted_to_Cp_here"],
					"vapour_kinds": ["assumption_adopted_by_source_for_vapour_pressure_consistency", "fitted_correlation_of_cited_flow_calorimetry_extrapolated_to_zero_pressure"],
				},
				{
					"request": [3.0, 0.2, 0.0, 0.0, 330.0],
					"accepted": true,
					"step": {
						"no_op": false,
						"physical_dt_s": 1.0,
						"source_dt_s": 1.0,
						"requested_release_kg": 0.05,
						"accepted_release_kg": 0.0,
						"rejected_release_kg": 0.05,
						"accepted_oxidation_kg": 0.020935991687620482,
						"rejected_oxidation_kg": 0.17906400831237954,
						"release_cost_kj": 0.0,
						"release_cost_kj_kg": 400.50272782122744,
						"heating_liquid_kj": 0.0,
						"heating_vapour_kj": 0.0,
						"released_liquid_sensible_kj": 0.0,
						"emitted_vapour_sensible_kj": 0.0,
						"oxidized_sensible_kj": 2.7609943312445187,
						"chemical_oxidation_heat_kj": 940.5588289578267,
						"deposited_increment_kj": 943.3198232890712,
						"co2_kg": 0.06448285439787108,
						"water_vapour_kg": 0.0301478280301735,
						"o2_consumed_kg": 0.0736946907404241,
						"mixed_specific_kj_kg": 131.87788629459112,
						"temperature_average_specific_kj_kg": null,
						"emitted_kinds": ["assumption_adopted_by_source_for_vapour_pressure_consistency"],
					},
					"phase": {
						"initial_fuel_mass_kg": 1.0,
						"liquid_fuel_kg": 0.9790640083123795,
						"vapour_fuel_kg": 0.0,
						"o2_kg": 9.926305309259575,
						"thermal_budget_kj": 0.0,
						"deposited_heat_kj": 943.3198232890712,
						"liquid_sensible_kj": 19.58128016624759,
						"vapour_sensible_kj": 0.0,
					},
					"time_s": 3.0,
					"accounts": {
						"potential_a_kj": 43626.77953526723,
						"sensible_s_kj": 19.58128016624759,
						"budget_b_kj": 0.0,
						"deposited_q_kj": 943.3198232890712,
						"total_kj": 44589.68063872255,
					},
					"liquid_kinds": ["tabulated_Csat_of_the_source_converted_to_Cp_here"],
					"vapour_kinds": [],
				},
				{
					"request": [4.0, 0.0, 0.0, 0.0, 371.0],
					"accepted": true,
					"step": {
						"no_op": false,
						"physical_dt_s": 1.0,
						"source_dt_s": 1.0,
						"requested_release_kg": 0.05,
						"accepted_release_kg": 0.0,
						"rejected_release_kg": 0.05,
						"accepted_oxidation_kg": 0.0,
						"rejected_oxidation_kg": 0.0,
						"release_cost_kj": 0.0,
						"release_cost_kj_kg": 477.6463493684434,
						"heating_liquid_kj": 0.0,
						"heating_vapour_kj": 0.0,
						"released_liquid_sensible_kj": 0.0,
						"emitted_vapour_sensible_kj": 0.0,
						"oxidized_sensible_kj": 0.0,
						"chemical_oxidation_heat_kj": 0.0,
						"deposited_increment_kj": 0.0,
						"co2_kg": 0.0,
						"water_vapour_kg": 0.0,
						"o2_consumed_kg": 0.0,
						"mixed_specific_kj_kg": 0.0,
						"temperature_average_specific_kj_kg": null,
						"emitted_kinds": ["assumption_adopted_by_source_for_vapour_pressure_consistency", "fitted_correlation_of_cited_flow_calorimetry_extrapolated_to_zero_pressure"],
					},
					"phase": {
						"initial_fuel_mass_kg": 1.0,
						"liquid_fuel_kg": 0.9790640083123795,
						"vapour_fuel_kg": 0.0,
						"o2_kg": 9.926305309259575,
						"thermal_budget_kj": 0.0,
						"deposited_heat_kj": 943.3198232890712,
						"liquid_sensible_kj": 19.58128016624759,
						"vapour_sensible_kj": 0.0,
					},
					"time_s": 4.0,
					"accounts": {
						"potential_a_kj": 43626.77953526723,
						"sensible_s_kj": 19.58128016624759,
						"budget_b_kj": 0.0,
						"deposited_q_kj": 943.3198232890712,
						"total_kj": 44589.68063872255,
					},
					"liquid_kinds": ["tabulated_Csat_of_the_source_converted_to_Cp_here"],
					"vapour_kinds": [],
				},
				{
					"request": [5.0, 0.0, 1.0, 0.0, 371.0],
					"accepted": false,
					"step": {},
					"phase": {
						"initial_fuel_mass_kg": 1.0,
						"liquid_fuel_kg": 0.9790640083123795,
						"vapour_fuel_kg": 0.0,
						"o2_kg": 9.926305309259575,
						"thermal_budget_kj": 0.0,
						"deposited_heat_kj": 943.3198232890712,
						"liquid_sensible_kj": 19.58128016624759,
						"vapour_sensible_kj": 0.0,
					},
					"time_s": 4.0,
					"accounts": {
						"potential_a_kj": 43626.77953526723,
						"sensible_s_kj": 19.58128016624759,
						"budget_b_kj": 0.0,
						"deposited_q_kj": 943.3198232890712,
						"total_kj": 44589.68063872255,
					},
					"liquid_kinds": ["tabulated_Csat_of_the_source_converted_to_Cp_here"],
					"vapour_kinds": [],
				},
			],
		},
		"oxygen_limited": {
			"context": {
				"schema": "g3_prescribed_real_sensible_context_v1",
				"program": {
					"profile_id": "declared_ramp",
					"component_id": "n-heptane",
					"initial_mass_kg": 1.0,
					"mode": "prescribed",
					"quantity": "modeled_component_emission",
					"unit": "kg/s",
					"time_origin": "declared_zero",
					"outside_domain": "reject",
					"interpolation": "piecewise_linear",
					"samples": [
						{"time_s": 0.0, "rate_kg_s": 0.05},
						{"time_s": 4.0, "rate_kg_s": 0.05},
						{"time_s": 8.0, "rate_kg_s": 0.0},
					],
				},
				"material": {
					"schema": "g3_phase_real_sensible_material_v1",
					"component_id": "n-heptane",
					"reference_material": {
						"schema": "g3_phase_reference_CHO_material_v1",
						"liquid_phase": "liquid",
						"vapour_phase": "gas",
						"water_product_phase": "gas",
						"atom_mass_basis": "nominal_C12_H1_O16",
						"chemical_energy_basis": "complete_oxidation_net",
						"reference_temperature_k": 298.15,
						"reference_pressure_pa": 100000.0,
						"mass_fractions": {
							"C": 0.84,
							"H": 0.16000000000000003,
							"O": 0.0,
						},
						"liquid_heat_kj_kg": 44559.68063872255,
						"vapour_heat_kj_kg": 44925.44910179641,
						"phase_enthalpy_kj_kg": 365.7684630738523,
						"provenance": "declared prototype: NIST TN 2126-upd1 heats per kg on 100.20 g/mol with nominal C7H16 atom fractions; not a heptane calibration",
					},
				},
				"attribution": {
					"input_component_id": "n-heptane",
					"modeled_component_id": "n-heptane",
					"input_quantity": "modeled_component_emission",
					"rule": "same_declared_component",
					"status": "synthetic_declared_emission",
					"provenance": "declared: prescribed emission program, not a measured or predicted evaporation",
				},
				"seed": {
					"schema": "g3_prescribed_real_sensible_seed_v1",
					"initial_o2_kg": 0.05,
					"initial_thermal_budget_kj": 600.0,
					"initial_liquid_sensible_kj": 0.0,
					"energy_boundary_kind": "synthetic_independent_initial_budget",
					"energy_boundary_provenance": "synthetic: independent initial budget, not a measured heat flux",
				},
			},
			"steps": [
				{
					"request": [1.0, 0.04, 0.0, 0.0, 371.0],
					"accepted": true,
					"step": {
						"no_op": false,
						"physical_dt_s": 1.0,
						"source_dt_s": 1.0,
						"requested_release_kg": 0.05,
						"accepted_release_kg": 0.05,
						"rejected_release_kg": 0.0,
						"accepted_oxidation_kg": 0.014204545454545456,
						"rejected_oxidation_kg": 0.025795454545454545,
						"release_cost_kj": 24.882317468422173,
						"release_cost_kj_kg": 497.6463493684434,
						"heating_liquid_kj": 0.0,
						"heating_vapour_kj": 0.0,
						"released_liquid_sensible_kj": 0.0,
						"emitted_vapour_sensible_kj": 6.593894314729557,
						"oxidized_sensible_kj": 1.8732654303208969,
						"chemical_oxidation_heat_kj": 638.1455838323354,
						"deposited_increment_kj": 640.0188492626563,
						"co2_kg": 0.04375,
						"water_vapour_kg": 0.02045454545454546,
						"o2_consumed_kg": 0.05,
						"mixed_specific_kj_kg": 131.87788629459112,
						"temperature_average_specific_kj_kg": null,
						"emitted_kinds": ["assumption_adopted_by_source_for_vapour_pressure_consistency", "fitted_correlation_of_cited_flow_calorimetry_extrapolated_to_zero_pressure"],
					},
					"phase": {
						"initial_fuel_mass_kg": 1.0,
						"liquid_fuel_kg": 0.95,
						"vapour_fuel_kg": 0.03579545454545455,
						"o2_kg": 0.0,
						"thermal_budget_kj": 575.1176825315779,
						"deposited_heat_kj": 640.0188492626563,
						"liquid_sensible_kj": 0.0,
						"vapour_sensible_kj": 4.72062888440866,
					},
					"time_s": 1.0,
					"accounts": {
						"potential_a_kj": 43939.8234780439,
						"sensible_s_kj": 4.72062888440866,
						"budget_b_kj": 575.1176825315779,
						"deposited_q_kj": 640.0188492626563,
						"total_kj": 45159.680638722544,
					},
					"liquid_kinds": ["tabulated_Csat_of_the_source_converted_to_Cp_here"],
					"vapour_kinds": ["assumption_adopted_by_source_for_vapour_pressure_consistency", "fitted_correlation_of_cited_flow_calorimetry_extrapolated_to_zero_pressure"],
				},
				{
					"request": [2.0, 0.04, 0.0, 0.0, 371.0],
					"accepted": true,
					"step": {
						"no_op": false,
						"physical_dt_s": 1.0,
						"source_dt_s": 1.0,
						"requested_release_kg": 0.05,
						"accepted_release_kg": 0.05,
						"rejected_release_kg": 0.0,
						"accepted_oxidation_kg": 0.0,
						"rejected_oxidation_kg": 0.04,
						"release_cost_kj": 24.882317468422173,
						"release_cost_kj_kg": 497.6463493684434,
						"heating_liquid_kj": 0.0,
						"heating_vapour_kj": 0.0,
						"released_liquid_sensible_kj": 0.0,
						"emitted_vapour_sensible_kj": 6.593894314729557,
						"oxidized_sensible_kj": 0.0,
						"chemical_oxidation_heat_kj": 0.0,
						"deposited_increment_kj": 0.0,
						"co2_kg": 0.0,
						"water_vapour_kg": 0.0,
						"o2_consumed_kg": 0.0,
						"mixed_specific_kj_kg": 131.87788629459112,
						"temperature_average_specific_kj_kg": 131.87788629459112,
						"emitted_kinds": ["assumption_adopted_by_source_for_vapour_pressure_consistency", "fitted_correlation_of_cited_flow_calorimetry_extrapolated_to_zero_pressure"],
					},
					"phase": {
						"initial_fuel_mass_kg": 1.0,
						"liquid_fuel_kg": 0.8999999999999999,
						"vapour_fuel_kg": 0.08579545454545455,
						"o2_kg": 0.0,
						"thermal_budget_kj": 550.2353650631558,
						"deposited_heat_kj": 640.0188492626563,
						"liquid_sensible_kj": 0.0,
						"vapour_sensible_kj": 11.314523199138216,
					},
					"time_s": 2.0,
					"accounts": {
						"potential_a_kj": 43958.1119011976,
						"sensible_s_kj": 11.314523199138216,
						"budget_b_kj": 550.2353650631558,
						"deposited_q_kj": 640.0188492626563,
						"total_kj": 45159.680638722544,
					},
					"liquid_kinds": ["tabulated_Csat_of_the_source_converted_to_Cp_here"],
					"vapour_kinds": ["assumption_adopted_by_source_for_vapour_pressure_consistency", "fitted_correlation_of_cited_flow_calorimetry_extrapolated_to_zero_pressure"],
				},
				{
					"request": [3.0, 0.04, 0.0, 0.0, 371.0],
					"accepted": true,
					"step": {
						"no_op": false,
						"physical_dt_s": 1.0,
						"source_dt_s": 1.0,
						"requested_release_kg": 0.05,
						"accepted_release_kg": 0.05,
						"rejected_release_kg": 0.0,
						"accepted_oxidation_kg": 0.0,
						"rejected_oxidation_kg": 0.04,
						"release_cost_kj": 24.882317468422173,
						"release_cost_kj_kg": 497.6463493684434,
						"heating_liquid_kj": 0.0,
						"heating_vapour_kj": 0.0,
						"released_liquid_sensible_kj": 0.0,
						"emitted_vapour_sensible_kj": 6.593894314729557,
						"oxidized_sensible_kj": 0.0,
						"chemical_oxidation_heat_kj": 0.0,
						"deposited_increment_kj": 0.0,
						"co2_kg": 0.0,
						"water_vapour_kg": 0.0,
						"o2_consumed_kg": 0.0,
						"mixed_specific_kj_kg": 131.87788629459115,
						"temperature_average_specific_kj_kg": 131.87788629459112,
						"emitted_kinds": ["assumption_adopted_by_source_for_vapour_pressure_consistency", "fitted_correlation_of_cited_flow_calorimetry_extrapolated_to_zero_pressure"],
					},
					"phase": {
						"initial_fuel_mass_kg": 1.0,
						"liquid_fuel_kg": 0.8499999999999999,
						"vapour_fuel_kg": 0.13579545454545455,
						"o2_kg": 0.0,
						"thermal_budget_kj": 525.3530475947337,
						"deposited_heat_kj": 640.0188492626563,
						"liquid_sensible_kj": 0.0,
						"vapour_sensible_kj": 17.908417513867775,
					},
					"time_s": 3.0,
					"accounts": {
						"potential_a_kj": 43976.40032435129,
						"sensible_s_kj": 17.908417513867775,
						"budget_b_kj": 525.3530475947337,
						"deposited_q_kj": 640.0188492626563,
						"total_kj": 45159.68063872255,
					},
					"liquid_kinds": ["tabulated_Csat_of_the_source_converted_to_Cp_here"],
					"vapour_kinds": ["assumption_adopted_by_source_for_vapour_pressure_consistency", "fitted_correlation_of_cited_flow_calorimetry_extrapolated_to_zero_pressure"],
				},
			],
		},
		"heating_does_not_fit": {
			"context": {
				"schema": "g3_prescribed_real_sensible_context_v1",
				"program": {
					"profile_id": "declared_ramp",
					"component_id": "n-heptane",
					"initial_mass_kg": 1.0,
					"mode": "prescribed",
					"quantity": "modeled_component_emission",
					"unit": "kg/s",
					"time_origin": "declared_zero",
					"outside_domain": "reject",
					"interpolation": "piecewise_linear",
					"samples": [
						{"time_s": 0.0, "rate_kg_s": 0.05},
						{"time_s": 4.0, "rate_kg_s": 0.05},
						{"time_s": 8.0, "rate_kg_s": 0.0},
					],
				},
				"material": {
					"schema": "g3_phase_real_sensible_material_v1",
					"component_id": "n-heptane",
					"reference_material": {
						"schema": "g3_phase_reference_CHO_material_v1",
						"liquid_phase": "liquid",
						"vapour_phase": "gas",
						"water_product_phase": "gas",
						"atom_mass_basis": "nominal_C12_H1_O16",
						"chemical_energy_basis": "complete_oxidation_net",
						"reference_temperature_k": 298.15,
						"reference_pressure_pa": 100000.0,
						"mass_fractions": {
							"C": 0.84,
							"H": 0.16000000000000003,
							"O": 0.0,
						},
						"liquid_heat_kj_kg": 44559.68063872255,
						"vapour_heat_kj_kg": 44925.44910179641,
						"phase_enthalpy_kj_kg": 365.7684630738523,
						"provenance": "declared prototype: NIST TN 2126-upd1 heats per kg on 100.20 g/mol with nominal C7H16 atom fractions; not a heptane calibration",
					},
				},
				"attribution": {
					"input_component_id": "n-heptane",
					"modeled_component_id": "n-heptane",
					"input_quantity": "modeled_component_emission",
					"rule": "same_declared_component",
					"status": "synthetic_declared_emission",
					"provenance": "declared: prescribed emission program, not a measured or predicted evaporation",
				},
				"seed": {
					"schema": "g3_prescribed_real_sensible_seed_v1",
					"initial_o2_kg": 10.0,
					"initial_thermal_budget_kj": 80.0,
					"initial_liquid_sensible_kj": 0.0,
					"energy_boundary_kind": "synthetic_independent_initial_budget",
					"energy_boundary_provenance": "synthetic: independent initial budget, not a measured heat flux",
				},
			},
			"steps": [
				{
					"request": [1.0, 0.0, 60.0, 0.0, 371.0],
					"accepted": true,
					"step": {
						"no_op": false,
						"physical_dt_s": 1.0,
						"source_dt_s": 1.0,
						"requested_release_kg": 0.05,
						"accepted_release_kg": 0.04569899881230931,
						"rejected_release_kg": 0.004301001187690695,
						"accepted_oxidation_kg": 0.0,
						"rejected_oxidation_kg": 0.0,
						"release_cost_kj": 20.0,
						"release_cost_kj_kg": 437.6463493684434,
						"heating_liquid_kj": 60.0,
						"heating_vapour_kj": 0.0,
						"released_liquid_sensible_kj": 2.7419399287385584,
						"emitted_vapour_sensible_kj": 6.026687369146382,
						"oxidized_sensible_kj": 0.0,
						"chemical_oxidation_heat_kj": 0.0,
						"deposited_increment_kj": 0.0,
						"co2_kg": 0.0,
						"water_vapour_kg": 0.0,
						"o2_consumed_kg": 0.0,
						"mixed_specific_kj_kg": 131.87788629459112,
						"temperature_average_specific_kj_kg": null,
						"emitted_kinds": ["assumption_adopted_by_source_for_vapour_pressure_consistency", "fitted_correlation_of_cited_flow_calorimetry_extrapolated_to_zero_pressure"],
					},
					"phase": {
						"initial_fuel_mass_kg": 1.0,
						"liquid_fuel_kg": 0.9543010011876907,
						"vapour_fuel_kg": 0.04569899881230931,
						"o2_kg": 10.0,
						"thermal_budget_kj": 0.0,
						"deposited_heat_kj": 0.0,
						"liquid_sensible_kj": 57.25806007126144,
						"vapour_sensible_kj": 6.026687369146382,
					},
					"time_s": 1.0,
					"accounts": {
						"potential_a_kj": 44576.39589128215,
						"sensible_s_kj": 63.28474744040782,
						"budget_b_kj": 0.0,
						"deposited_q_kj": 0.0,
						"total_kj": 44639.68063872255,
					},
					"liquid_kinds": ["tabulated_Csat_of_the_source_converted_to_Cp_here"],
					"vapour_kinds": ["assumption_adopted_by_source_for_vapour_pressure_consistency", "fitted_correlation_of_cited_flow_calorimetry_extrapolated_to_zero_pressure"],
				},
				{
					"request": [2.0, 0.0, 60.0, 0.0, 371.0],
					"accepted": false,
					"step": {},
					"phase": {
						"initial_fuel_mass_kg": 1.0,
						"liquid_fuel_kg": 0.9543010011876907,
						"vapour_fuel_kg": 0.04569899881230931,
						"o2_kg": 10.0,
						"thermal_budget_kj": 0.0,
						"deposited_heat_kj": 0.0,
						"liquid_sensible_kj": 57.25806007126144,
						"vapour_sensible_kj": 6.026687369146382,
					},
					"time_s": 1.0,
					"accounts": {
						"potential_a_kj": 44576.39589128215,
						"sensible_s_kj": 63.28474744040782,
						"budget_b_kj": 0.0,
						"deposited_q_kj": 0.0,
						"total_kj": 44639.68063872255,
					},
					"liquid_kinds": ["tabulated_Csat_of_the_source_converted_to_Cp_here"],
					"vapour_kinds": ["assumption_adopted_by_source_for_vapour_pressure_consistency", "fitted_correlation_of_cited_flow_calorimetry_extrapolated_to_zero_pressure"],
				},
				{
					"request": [2.0, 0.0, 5.0, 0.0, 371.0],
					"accepted": false,
					"step": {},
					"phase": {
						"initial_fuel_mass_kg": 1.0,
						"liquid_fuel_kg": 0.9543010011876907,
						"vapour_fuel_kg": 0.04569899881230931,
						"o2_kg": 10.0,
						"thermal_budget_kj": 0.0,
						"deposited_heat_kj": 0.0,
						"liquid_sensible_kj": 57.25806007126144,
						"vapour_sensible_kj": 6.026687369146382,
					},
					"time_s": 1.0,
					"accounts": {
						"potential_a_kj": 44576.39589128215,
						"sensible_s_kj": 63.28474744040782,
						"budget_b_kj": 0.0,
						"deposited_q_kj": 0.0,
						"total_kj": 44639.68063872255,
					},
					"liquid_kinds": ["tabulated_Csat_of_the_source_converted_to_Cp_here"],
					"vapour_kinds": ["assumption_adopted_by_source_for_vapour_pressure_consistency", "fitted_correlation_of_cited_flow_calorimetry_extrapolated_to_zero_pressure"],
				},
			],
		},
		"support": {
			"context": {
				"schema": "g3_prescribed_real_sensible_context_v1",
				"program": {
					"profile_id": "declared_ramp",
					"component_id": "n-heptane",
					"initial_mass_kg": 1.0,
					"mode": "prescribed",
					"quantity": "modeled_component_emission",
					"unit": "kg/s",
					"time_origin": "declared_zero",
					"outside_domain": "reject",
					"interpolation": "piecewise_linear",
					"samples": [
						{"time_s": 0.0, "rate_kg_s": 0.05},
						{"time_s": 4.0, "rate_kg_s": 0.05},
						{"time_s": 8.0, "rate_kg_s": 0.0},
					],
				},
				"material": {
					"schema": "g3_phase_real_sensible_material_v1",
					"component_id": "n-heptane",
					"reference_material": {
						"schema": "g3_phase_reference_CHO_material_v1",
						"liquid_phase": "liquid",
						"vapour_phase": "gas",
						"water_product_phase": "gas",
						"atom_mass_basis": "nominal_C12_H1_O16",
						"chemical_energy_basis": "complete_oxidation_net",
						"reference_temperature_k": 298.15,
						"reference_pressure_pa": 100000.0,
						"mass_fractions": {
							"C": 0.84,
							"H": 0.16000000000000003,
							"O": 0.0,
						},
						"liquid_heat_kj_kg": 44559.68063872255,
						"vapour_heat_kj_kg": 44925.44910179641,
						"phase_enthalpy_kj_kg": 365.7684630738523,
						"provenance": "declared prototype: NIST TN 2126-upd1 heats per kg on 100.20 g/mol with nominal C7H16 atom fractions; not a heptane calibration",
					},
				},
				"attribution": {
					"input_component_id": "n-heptane",
					"modeled_component_id": "n-heptane",
					"input_quantity": "modeled_component_emission",
					"rule": "same_declared_component",
					"status": "synthetic_declared_emission",
					"provenance": "declared: prescribed emission program, not a measured or predicted evaporation",
				},
				"seed": {
					"schema": "g3_prescribed_real_sensible_seed_v1",
					"initial_o2_kg": 10.0,
					"initial_thermal_budget_kj": 600.0,
					"initial_liquid_sensible_kj": 0.0,
					"energy_boundary_kind": "synthetic_independent_initial_budget",
					"energy_boundary_provenance": "synthetic: independent initial budget, not a measured heat flux",
				},
			},
			"steps": [
				{
					"request": [1.0, 0.0, 0.0, 0.0, 480.0],
					"accepted": false,
					"step": {},
					"phase": {
						"initial_fuel_mass_kg": 1.0,
						"liquid_fuel_kg": 1.0,
						"vapour_fuel_kg": 0.0,
						"o2_kg": 10.0,
						"thermal_budget_kj": 600.0,
						"deposited_heat_kj": 0.0,
						"liquid_sensible_kj": 0.0,
						"vapour_sensible_kj": 0.0,
					},
					"time_s": 0.0,
					"accounts": {
						"potential_a_kj": 44559.68063872255,
						"sensible_s_kj": 0.0,
						"budget_b_kj": 600.0,
						"deposited_q_kj": 0.0,
						"total_kj": 45159.68063872255,
					},
					"liquid_kinds": ["tabulated_Csat_of_the_source_converted_to_Cp_here"],
					"vapour_kinds": [],
				},
				{
					"request": [1.0, 0.0, 0.0, 0.0, 298.0],
					"accepted": false,
					"step": {},
					"phase": {
						"initial_fuel_mass_kg": 1.0,
						"liquid_fuel_kg": 1.0,
						"vapour_fuel_kg": 0.0,
						"o2_kg": 10.0,
						"thermal_budget_kj": 600.0,
						"deposited_heat_kj": 0.0,
						"liquid_sensible_kj": 0.0,
						"vapour_sensible_kj": 0.0,
					},
					"time_s": 0.0,
					"accounts": {
						"potential_a_kj": 44559.68063872255,
						"sensible_s_kj": 0.0,
						"budget_b_kj": 600.0,
						"deposited_q_kj": 0.0,
						"total_kj": 45159.68063872255,
					},
					"liquid_kinds": ["tabulated_Csat_of_the_source_converted_to_Cp_here"],
					"vapour_kinds": [],
				},
				{
					"request": [1.0, 0.0, 0.0, 0.0, 371.0],
					"accepted": true,
					"step": {
						"no_op": false,
						"physical_dt_s": 1.0,
						"source_dt_s": 1.0,
						"requested_release_kg": 0.05,
						"accepted_release_kg": 0.05,
						"rejected_release_kg": 0.0,
						"accepted_oxidation_kg": 0.0,
						"rejected_oxidation_kg": 0.0,
						"release_cost_kj": 24.882317468422173,
						"release_cost_kj_kg": 497.6463493684434,
						"heating_liquid_kj": 0.0,
						"heating_vapour_kj": 0.0,
						"released_liquid_sensible_kj": 0.0,
						"emitted_vapour_sensible_kj": 6.593894314729557,
						"oxidized_sensible_kj": 0.0,
						"chemical_oxidation_heat_kj": 0.0,
						"deposited_increment_kj": 0.0,
						"co2_kg": 0.0,
						"water_vapour_kg": 0.0,
						"o2_consumed_kg": 0.0,
						"mixed_specific_kj_kg": 131.87788629459112,
						"temperature_average_specific_kj_kg": null,
						"emitted_kinds": ["assumption_adopted_by_source_for_vapour_pressure_consistency", "fitted_correlation_of_cited_flow_calorimetry_extrapolated_to_zero_pressure"],
					},
					"phase": {
						"initial_fuel_mass_kg": 1.0,
						"liquid_fuel_kg": 0.95,
						"vapour_fuel_kg": 0.05,
						"o2_kg": 10.0,
						"thermal_budget_kj": 575.1176825315779,
						"deposited_heat_kj": 0.0,
						"liquid_sensible_kj": 0.0,
						"vapour_sensible_kj": 6.593894314729557,
					},
					"time_s": 1.0,
					"accounts": {
						"potential_a_kj": 44577.96906187624,
						"sensible_s_kj": 6.593894314729557,
						"budget_b_kj": 575.1176825315779,
						"deposited_q_kj": 0.0,
						"total_kj": 45159.680638722544,
					},
					"liquid_kinds": ["tabulated_Csat_of_the_source_converted_to_Cp_here"],
					"vapour_kinds": ["assumption_adopted_by_source_for_vapour_pressure_consistency", "fitted_correlation_of_cited_flow_calorimetry_extrapolated_to_zero_pressure"],
				},
				{
					"request": [2.0, 0.0, 200.0, 0.0, 371.0],
					"accepted": false,
					"step": {},
					"phase": {
						"initial_fuel_mass_kg": 1.0,
						"liquid_fuel_kg": 0.95,
						"vapour_fuel_kg": 0.05,
						"o2_kg": 10.0,
						"thermal_budget_kj": 575.1176825315779,
						"deposited_heat_kj": 0.0,
						"liquid_sensible_kj": 0.0,
						"vapour_sensible_kj": 6.593894314729557,
					},
					"time_s": 1.0,
					"accounts": {
						"potential_a_kj": 44577.96906187624,
						"sensible_s_kj": 6.593894314729557,
						"budget_b_kj": 575.1176825315779,
						"deposited_q_kj": 0.0,
						"total_kj": 45159.680638722544,
					},
					"liquid_kinds": ["tabulated_Csat_of_the_source_converted_to_Cp_here"],
					"vapour_kinds": ["assumption_adopted_by_source_for_vapour_pressure_consistency", "fitted_correlation_of_cited_flow_calorimetry_extrapolated_to_zero_pressure"],
				},
				{
					"request": [2.0, 0.0, 0.0, 12.0, 371.0],
					"accepted": false,
					"step": {},
					"phase": {
						"initial_fuel_mass_kg": 1.0,
						"liquid_fuel_kg": 0.95,
						"vapour_fuel_kg": 0.05,
						"o2_kg": 10.0,
						"thermal_budget_kj": 575.1176825315779,
						"deposited_heat_kj": 0.0,
						"liquid_sensible_kj": 0.0,
						"vapour_sensible_kj": 6.593894314729557,
					},
					"time_s": 1.0,
					"accounts": {
						"potential_a_kj": 44577.96906187624,
						"sensible_s_kj": 6.593894314729557,
						"budget_b_kj": 575.1176825315779,
						"deposited_q_kj": 0.0,
						"total_kj": 45159.680638722544,
					},
					"liquid_kinds": ["tabulated_Csat_of_the_source_converted_to_Cp_here"],
					"vapour_kinds": ["assumption_adopted_by_source_for_vapour_pressure_consistency", "fitted_correlation_of_cited_flow_calorimetry_extrapolated_to_zero_pressure"],
				},
				{
					"request": [2.0, 0.0, 100.0, 5.0, 371.0],
					"accepted": true,
					"step": {
						"no_op": false,
						"physical_dt_s": 1.0,
						"source_dt_s": 1.0,
						"requested_release_kg": 0.05,
						"accepted_release_kg": 0.05,
						"rejected_release_kg": 0.0,
						"accepted_oxidation_kg": 0.0,
						"rejected_oxidation_kg": 0.0,
						"release_cost_kj": 19.61915957368533,
						"release_cost_kj_kg": 392.3831914737066,
						"heating_liquid_kj": 100.0,
						"heating_vapour_kj": 5.0,
						"released_liquid_sensible_kj": 5.2631578947368425,
						"emitted_vapour_sensible_kj": 6.593894314729557,
						"oxidized_sensible_kj": 0.0,
						"chemical_oxidation_heat_kj": 0.0,
						"deposited_increment_kj": 0.0,
						"co2_kg": 0.0,
						"water_vapour_kg": 0.0,
						"o2_consumed_kg": 0.0,
						"mixed_specific_kj_kg": 181.87788629459112,
						"temperature_average_specific_kj_kg": 180.61537926135796,
						"emitted_kinds": ["assumption_adopted_by_source_for_vapour_pressure_consistency", "fitted_correlation_of_cited_flow_calorimetry_extrapolated_to_zero_pressure"],
					},
					"phase": {
						"initial_fuel_mass_kg": 1.0,
						"liquid_fuel_kg": 0.8999999999999999,
						"vapour_fuel_kg": 0.1,
						"o2_kg": 10.0,
						"thermal_budget_kj": 450.49852295789253,
						"deposited_heat_kj": 0.0,
						"liquid_sensible_kj": 94.73684210526315,
						"vapour_sensible_kj": 18.187788629459114,
					},
					"time_s": 2.0,
					"accounts": {
						"potential_a_kj": 44596.257485029935,
						"sensible_s_kj": 112.92463073472226,
						"budget_b_kj": 450.49852295789253,
						"deposited_q_kj": 0.0,
						"total_kj": 45159.68063872255,
					},
					"liquid_kinds": ["tabulated_Csat_of_the_source_converted_to_Cp_here"],
					"vapour_kinds": ["assumption_adopted_by_source_for_vapour_pressure_consistency", "fitted_correlation_of_cited_flow_calorimetry_extrapolated_to_zero_pressure"],
				},
			],
		},
		"separate_supports": {
			"context": {
				"schema": "g3_prescribed_real_sensible_context_v1",
				"program": {
					"profile_id": "declared_ramp",
					"component_id": "n-heptane",
					"initial_mass_kg": 1.0,
					"mode": "prescribed",
					"quantity": "modeled_component_emission",
					"unit": "kg/s",
					"time_origin": "declared_zero",
					"outside_domain": "reject",
					"interpolation": "piecewise_linear",
					"samples": [
						{"time_s": 0.0, "rate_kg_s": 0.05},
						{"time_s": 4.0, "rate_kg_s": 0.05},
						{"time_s": 8.0, "rate_kg_s": 0.0},
					],
				},
				"material": {
					"schema": "g3_phase_real_sensible_material_v1",
					"component_id": "n-heptane",
					"reference_material": {
						"schema": "g3_phase_reference_CHO_material_v1",
						"liquid_phase": "liquid",
						"vapour_phase": "gas",
						"water_product_phase": "gas",
						"atom_mass_basis": "nominal_C12_H1_O16",
						"chemical_energy_basis": "complete_oxidation_net",
						"reference_temperature_k": 298.15,
						"reference_pressure_pa": 100000.0,
						"mass_fractions": {
							"C": 0.84,
							"H": 0.16000000000000003,
							"O": 0.0,
						},
						"liquid_heat_kj_kg": 44559.68063872255,
						"vapour_heat_kj_kg": 44925.44910179641,
						"phase_enthalpy_kj_kg": 365.7684630738523,
						"provenance": "declared prototype: NIST TN 2126-upd1 heats per kg on 100.20 g/mol with nominal C7H16 atom fractions; not a heptane calibration",
					},
				},
				"attribution": {
					"input_component_id": "n-heptane",
					"modeled_component_id": "n-heptane",
					"input_quantity": "modeled_component_emission",
					"rule": "same_declared_component",
					"status": "synthetic_declared_emission",
					"provenance": "declared: prescribed emission program, not a measured or predicted evaporation",
				},
				"seed": {
					"schema": "g3_prescribed_real_sensible_seed_v1",
					"initial_o2_kg": 10.0,
					"initial_thermal_budget_kj": 600.0,
					"initial_liquid_sensible_kj": 170.0,
					"energy_boundary_kind": "synthetic_independent_initial_budget",
					"energy_boundary_provenance": "synthetic: independent initial budget, not a measured heat flux",
				},
			},
			"steps": [
				{
					"request": [1.0, 0.0, 0.0, 0.0, 469.99],
					"accepted": true,
					"step": {
						"no_op": false,
						"physical_dt_s": 1.0,
						"source_dt_s": 1.0,
						"requested_release_kg": 0.05,
						"accepted_release_kg": 0.05,
						"rejected_release_kg": 0.0,
						"accepted_oxidation_kg": 0.0,
						"rejected_oxidation_kg": 0.0,
						"release_cost_kj": 27.207824907415365,
						"release_cost_kj_kg": 544.1564981483073,
						"heating_liquid_kj": 0.0,
						"heating_vapour_kj": 0.0,
						"released_liquid_sensible_kj": 8.5,
						"emitted_vapour_sensible_kj": 17.41940175372275,
						"oxidized_sensible_kj": 0.0,
						"chemical_oxidation_heat_kj": 0.0,
						"deposited_increment_kj": 0.0,
						"co2_kg": 0.0,
						"water_vapour_kg": 0.0,
						"o2_consumed_kg": 0.0,
						"mixed_specific_kj_kg": 348.38803507445493,
						"temperature_average_specific_kj_kg": null,
						"emitted_kinds": ["assumption_adopted_by_source_for_vapour_pressure_consistency", "fitted_correlation_of_cited_flow_calorimetry_extrapolated_to_zero_pressure", "extrapolation_tabulated_by_source"],
					},
					"phase": {
						"initial_fuel_mass_kg": 1.0,
						"liquid_fuel_kg": 0.95,
						"vapour_fuel_kg": 0.05,
						"o2_kg": 10.0,
						"thermal_budget_kj": 572.7921750925847,
						"deposited_heat_kj": 0.0,
						"liquid_sensible_kj": 161.5,
						"vapour_sensible_kj": 17.41940175372275,
					},
					"time_s": 1.0,
					"accounts": {
						"potential_a_kj": 44577.96906187624,
						"sensible_s_kj": 178.91940175372275,
						"budget_b_kj": 572.7921750925847,
						"deposited_q_kj": 0.0,
						"total_kj": 45329.680638722544,
					},
					"liquid_kinds": ["tabulated_Csat_of_the_source_converted_to_Cp_here", "same_table_with_source_error_rising_above_360_K"],
					"vapour_kinds": ["assumption_adopted_by_source_for_vapour_pressure_consistency", "fitted_correlation_of_cited_flow_calorimetry_extrapolated_to_zero_pressure", "extrapolation_tabulated_by_source"],
				},
				{
					"request": [2.0, 0.01, 0.0, 0.0, 298.14],
					"accepted": true,
					"step": {
						"no_op": false,
						"physical_dt_s": 1.0,
						"source_dt_s": 1.0,
						"requested_release_kg": 0.05,
						"accepted_release_kg": 0.05,
						"rejected_release_kg": 0.0,
						"accepted_oxidation_kg": 0.01,
						"rejected_oxidation_kg": 0.0,
						"release_cost_kj": 9.787599620001984,
						"release_cost_kj_kg": 195.75199240003968,
						"heating_liquid_kj": 0.0,
						"heating_vapour_kj": 0.0,
						"released_liquid_sensible_kj": 8.5,
						"emitted_vapour_sensible_kj": -0.0008235336906302097,
						"oxidized_sensible_kj": 1.7418578220032117,
						"chemical_oxidation_heat_kj": 449.2544910179641,
						"deposited_increment_kj": 450.9963488399673,
						"co2_kg": 0.030799999999999998,
						"water_vapour_kg": 0.014400000000000003,
						"o2_consumed_kg": 0.0352,
						"mixed_specific_kj_kg": 174.18578220032117,
						"temperature_average_specific_kj_kg": 158.03840993144155,
						"emitted_kinds": ["assumption_adopted_by_source_for_vapour_pressure_consistency"],
					},
					"phase": {
						"initial_fuel_mass_kg": 1.0,
						"liquid_fuel_kg": 0.8999999999999999,
						"vapour_fuel_kg": 0.09000000000000001,
						"o2_kg": 9.9648,
						"thermal_budget_kj": 563.0045754725827,
						"deposited_heat_kj": 450.9963488399673,
						"liquid_sensible_kj": 152.99999999999997,
						"vapour_sensible_kj": 15.676720398028907,
					},
					"time_s": 2.0,
					"accounts": {
						"potential_a_kj": 44147.00299401197,
						"sensible_s_kj": 168.6767203980289,
						"budget_b_kj": 563.0045754725827,
						"deposited_q_kj": 450.9963488399673,
						"total_kj": 45329.680638722544,
					},
					"liquid_kinds": ["tabulated_Csat_of_the_source_converted_to_Cp_here", "same_table_with_source_error_rising_above_360_K"],
					"vapour_kinds": ["assumption_adopted_by_source_for_vapour_pressure_consistency", "fitted_correlation_of_cited_flow_calorimetry_extrapolated_to_zero_pressure"],
				},
			],
		},
		"cold_liquid": {
			"context": {
				"schema": "g3_prescribed_real_sensible_context_v1",
				"program": {
					"profile_id": "declared_ramp",
					"component_id": "n-heptane",
					"initial_mass_kg": 1.0,
					"mode": "prescribed",
					"quantity": "modeled_component_emission",
					"unit": "kg/s",
					"time_origin": "declared_zero",
					"outside_domain": "reject",
					"interpolation": "piecewise_linear",
					"samples": [
						{"time_s": 0.0, "rate_kg_s": 0.05},
						{"time_s": 4.0, "rate_kg_s": 0.05},
						{"time_s": 8.0, "rate_kg_s": 0.0},
					],
				},
				"material": {
					"schema": "g3_phase_real_sensible_material_v1",
					"component_id": "n-heptane",
					"reference_material": {
						"schema": "g3_phase_reference_CHO_material_v1",
						"liquid_phase": "liquid",
						"vapour_phase": "gas",
						"water_product_phase": "gas",
						"atom_mass_basis": "nominal_C12_H1_O16",
						"chemical_energy_basis": "complete_oxidation_net",
						"reference_temperature_k": 298.15,
						"reference_pressure_pa": 100000.0,
						"mass_fractions": {
							"C": 0.84,
							"H": 0.16000000000000003,
							"O": 0.0,
						},
						"liquid_heat_kj_kg": 44559.68063872255,
						"vapour_heat_kj_kg": 44925.44910179641,
						"phase_enthalpy_kj_kg": 365.7684630738523,
						"provenance": "declared prototype: NIST TN 2126-upd1 heats per kg on 100.20 g/mol with nominal C7H16 atom fractions; not a heptane calibration",
					},
				},
				"attribution": {
					"input_component_id": "n-heptane",
					"modeled_component_id": "n-heptane",
					"input_quantity": "modeled_component_emission",
					"rule": "same_declared_component",
					"status": "synthetic_declared_emission",
					"provenance": "declared: prescribed emission program, not a measured or predicted evaporation",
				},
				"seed": {
					"schema": "g3_prescribed_real_sensible_seed_v1",
					"initial_o2_kg": 10.0,
					"initial_thermal_budget_kj": 600.0,
					"initial_liquid_sensible_kj": -40.0,
					"energy_boundary_kind": "synthetic_independent_initial_budget",
					"energy_boundary_provenance": "synthetic: independent initial budget, not a measured heat flux",
				},
			},
			"steps": [
				{
					"request": [1.0, 0.0, 0.0, 0.0, 298.15],
					"accepted": true,
					"step": {
						"no_op": false,
						"physical_dt_s": 1.0,
						"source_dt_s": 1.0,
						"requested_release_kg": 0.05,
						"accepted_release_kg": 0.05,
						"rejected_release_kg": 0.0,
						"accepted_oxidation_kg": 0.0,
						"rejected_oxidation_kg": 0.0,
						"release_cost_kj": 20.288423153692616,
						"release_cost_kj_kg": 405.7684630738523,
						"heating_liquid_kj": 0.0,
						"heating_vapour_kj": 0.0,
						"released_liquid_sensible_kj": -2.0,
						"emitted_vapour_sensible_kj": 0.0,
						"oxidized_sensible_kj": 0.0,
						"chemical_oxidation_heat_kj": 0.0,
						"deposited_increment_kj": 0.0,
						"co2_kg": 0.0,
						"water_vapour_kg": 0.0,
						"o2_consumed_kg": 0.0,
						"mixed_specific_kj_kg": 0.0,
						"temperature_average_specific_kj_kg": null,
						"emitted_kinds": ["assumption_adopted_by_source_for_vapour_pressure_consistency"],
					},
					"phase": {
						"initial_fuel_mass_kg": 1.0,
						"liquid_fuel_kg": 0.95,
						"vapour_fuel_kg": 0.05,
						"o2_kg": 10.0,
						"thermal_budget_kj": 579.7115768463074,
						"deposited_heat_kj": 0.0,
						"liquid_sensible_kj": -38.0,
						"vapour_sensible_kj": 0.0,
					},
					"time_s": 1.0,
					"accounts": {
						"potential_a_kj": 44577.96906187624,
						"sensible_s_kj": -38.0,
						"budget_b_kj": 579.7115768463074,
						"deposited_q_kj": 0.0,
						"total_kj": 45119.680638722544,
					},
					"liquid_kinds": ["tabulated_Csat_of_the_source_converted_to_Cp_here"],
					"vapour_kinds": ["assumption_adopted_by_source_for_vapour_pressure_consistency"],
				},
				{
					"request": [2.0, 0.02, 0.0, 0.0, 298.14],
					"accepted": true,
					"step": {
						"no_op": false,
						"physical_dt_s": 1.0,
						"source_dt_s": 1.0,
						"requested_release_kg": 0.05,
						"accepted_release_kg": 0.05,
						"rejected_release_kg": 0.0,
						"accepted_oxidation_kg": 0.02,
						"rejected_oxidation_kg": 0.0,
						"release_cost_kj": 20.287599620001984,
						"release_cost_kj_kg": 405.7519924000397,
						"heating_liquid_kj": 0.0,
						"heating_vapour_kj": 0.0,
						"released_liquid_sensible_kj": -2.0,
						"emitted_vapour_sensible_kj": -0.0008235336906302097,
						"oxidized_sensible_kj": -0.00016470673812604196,
						"chemical_oxidation_heat_kj": 898.5089820359282,
						"deposited_increment_kj": 898.50881732919,
						"co2_kg": 0.061599999999999995,
						"water_vapour_kg": 0.028800000000000006,
						"o2_consumed_kg": 0.0704,
						"mixed_specific_kj_kg": -0.008235336906302097,
						"temperature_average_specific_kj_kg": -0.008235393046516305,
						"emitted_kinds": ["assumption_adopted_by_source_for_vapour_pressure_consistency"],
					},
					"phase": {
						"initial_fuel_mass_kg": 1.0,
						"liquid_fuel_kg": 0.8999999999999999,
						"vapour_fuel_kg": 0.08,
						"o2_kg": 9.9296,
						"thermal_budget_kj": 559.4239772263054,
						"deposited_heat_kj": 898.50881732919,
						"liquid_sensible_kj": -36.0,
						"vapour_sensible_kj": -0.0006588269525041678,
					},
					"time_s": 2.0,
					"accounts": {
						"potential_a_kj": 43697.74850299401,
						"sensible_s_kj": -36.0006588269525,
						"budget_b_kj": 559.4239772263054,
						"deposited_q_kj": 898.50881732919,
						"total_kj": 45119.680638722544,
					},
					"liquid_kinds": ["tabulated_Csat_of_the_source_converted_to_Cp_here"],
					"vapour_kinds": ["assumption_adopted_by_source_for_vapour_pressure_consistency"],
				},
			],
		},
		"history_cold": {
			"context": {
				"schema": "g3_prescribed_real_sensible_context_v1",
				"program": {
					"profile_id": "declared_ramp",
					"component_id": "n-heptane",
					"initial_mass_kg": 1.0,
					"mode": "prescribed",
					"quantity": "modeled_component_emission",
					"unit": "kg/s",
					"time_origin": "declared_zero",
					"outside_domain": "reject",
					"interpolation": "piecewise_linear",
					"samples": [
						{"time_s": 0.0, "rate_kg_s": 0.05},
						{"time_s": 4.0, "rate_kg_s": 0.05},
						{"time_s": 8.0, "rate_kg_s": 0.0},
					],
				},
				"material": {
					"schema": "g3_phase_real_sensible_material_v1",
					"component_id": "n-heptane",
					"reference_material": {
						"schema": "g3_phase_reference_CHO_material_v1",
						"liquid_phase": "liquid",
						"vapour_phase": "gas",
						"water_product_phase": "gas",
						"atom_mass_basis": "nominal_C12_H1_O16",
						"chemical_energy_basis": "complete_oxidation_net",
						"reference_temperature_k": 298.15,
						"reference_pressure_pa": 100000.0,
						"mass_fractions": {
							"C": 0.84,
							"H": 0.16000000000000003,
							"O": 0.0,
						},
						"liquid_heat_kj_kg": 44559.68063872255,
						"vapour_heat_kj_kg": 44925.44910179641,
						"phase_enthalpy_kj_kg": 365.7684630738523,
						"provenance": "declared prototype: NIST TN 2126-upd1 heats per kg on 100.20 g/mol with nominal C7H16 atom fractions; not a heptane calibration",
					},
				},
				"attribution": {
					"input_component_id": "n-heptane",
					"modeled_component_id": "n-heptane",
					"input_quantity": "modeled_component_emission",
					"rule": "same_declared_component",
					"status": "synthetic_declared_emission",
					"provenance": "declared: prescribed emission program, not a measured or predicted evaporation",
				},
				"seed": {
					"schema": "g3_prescribed_real_sensible_seed_v1",
					"initial_o2_kg": 10.0,
					"initial_thermal_budget_kj": 600.0,
					"initial_liquid_sensible_kj": 0.0,
					"energy_boundary_kind": "synthetic_independent_initial_budget",
					"energy_boundary_provenance": "synthetic: independent initial budget, not a measured heat flux",
				},
			},
			"steps": [
				{
					"request": [1.0, 0.0, 0.0, 0.0, 371.0],
					"accepted": true,
					"step": {
						"no_op": false,
						"physical_dt_s": 1.0,
						"source_dt_s": 1.0,
						"requested_release_kg": 0.05,
						"accepted_release_kg": 0.05,
						"rejected_release_kg": 0.0,
						"accepted_oxidation_kg": 0.0,
						"rejected_oxidation_kg": 0.0,
						"release_cost_kj": 24.882317468422173,
						"release_cost_kj_kg": 497.6463493684434,
						"heating_liquid_kj": 0.0,
						"heating_vapour_kj": 0.0,
						"released_liquid_sensible_kj": 0.0,
						"emitted_vapour_sensible_kj": 6.593894314729557,
						"oxidized_sensible_kj": 0.0,
						"chemical_oxidation_heat_kj": 0.0,
						"deposited_increment_kj": 0.0,
						"co2_kg": 0.0,
						"water_vapour_kg": 0.0,
						"o2_consumed_kg": 0.0,
						"mixed_specific_kj_kg": 131.87788629459112,
						"temperature_average_specific_kj_kg": null,
						"emitted_kinds": ["assumption_adopted_by_source_for_vapour_pressure_consistency", "fitted_correlation_of_cited_flow_calorimetry_extrapolated_to_zero_pressure"],
					},
					"phase": {
						"initial_fuel_mass_kg": 1.0,
						"liquid_fuel_kg": 0.95,
						"vapour_fuel_kg": 0.05,
						"o2_kg": 10.0,
						"thermal_budget_kj": 575.1176825315779,
						"deposited_heat_kj": 0.0,
						"liquid_sensible_kj": 0.0,
						"vapour_sensible_kj": 6.593894314729557,
					},
					"time_s": 1.0,
					"accounts": {
						"potential_a_kj": 44577.96906187624,
						"sensible_s_kj": 6.593894314729557,
						"budget_b_kj": 575.1176825315779,
						"deposited_q_kj": 0.0,
						"total_kj": 45159.680638722544,
					},
					"liquid_kinds": ["tabulated_Csat_of_the_source_converted_to_Cp_here"],
					"vapour_kinds": ["assumption_adopted_by_source_for_vapour_pressure_consistency", "fitted_correlation_of_cited_flow_calorimetry_extrapolated_to_zero_pressure"],
				},
				{
					"request": [2.0, 0.02, 0.0, 0.0, 371.0],
					"accepted": true,
					"step": {
						"no_op": false,
						"physical_dt_s": 1.0,
						"source_dt_s": 1.0,
						"requested_release_kg": 0.05,
						"accepted_release_kg": 0.05,
						"rejected_release_kg": 0.0,
						"accepted_oxidation_kg": 0.02,
						"rejected_oxidation_kg": 0.0,
						"release_cost_kj": 24.882317468422173,
						"release_cost_kj_kg": 497.6463493684434,
						"heating_liquid_kj": 0.0,
						"heating_vapour_kj": 0.0,
						"released_liquid_sensible_kj": 0.0,
						"emitted_vapour_sensible_kj": 6.593894314729557,
						"oxidized_sensible_kj": 2.6375577258918224,
						"chemical_oxidation_heat_kj": 898.5089820359282,
						"deposited_increment_kj": 901.14653976182,
						"co2_kg": 0.061599999999999995,
						"water_vapour_kg": 0.028800000000000006,
						"o2_consumed_kg": 0.0704,
						"mixed_specific_kj_kg": 131.87788629459112,
						"temperature_average_specific_kj_kg": 131.87788629459112,
						"emitted_kinds": ["assumption_adopted_by_source_for_vapour_pressure_consistency", "fitted_correlation_of_cited_flow_calorimetry_extrapolated_to_zero_pressure"],
					},
					"phase": {
						"initial_fuel_mass_kg": 1.0,
						"liquid_fuel_kg": 0.8999999999999999,
						"vapour_fuel_kg": 0.08,
						"o2_kg": 9.9296,
						"thermal_budget_kj": 550.2353650631558,
						"deposited_heat_kj": 901.14653976182,
						"liquid_sensible_kj": 0.0,
						"vapour_sensible_kj": 10.55023090356729,
					},
					"time_s": 2.0,
					"accounts": {
						"potential_a_kj": 43697.74850299401,
						"sensible_s_kj": 10.55023090356729,
						"budget_b_kj": 550.2353650631558,
						"deposited_q_kj": 901.14653976182,
						"total_kj": 45159.68063872255,
					},
					"liquid_kinds": ["tabulated_Csat_of_the_source_converted_to_Cp_here"],
					"vapour_kinds": ["assumption_adopted_by_source_for_vapour_pressure_consistency", "fitted_correlation_of_cited_flow_calorimetry_extrapolated_to_zero_pressure"],
				},
			],
		},
		"history_hot": {
			"context": {
				"schema": "g3_prescribed_real_sensible_context_v1",
				"program": {
					"profile_id": "declared_ramp",
					"component_id": "n-heptane",
					"initial_mass_kg": 1.0,
					"mode": "prescribed",
					"quantity": "modeled_component_emission",
					"unit": "kg/s",
					"time_origin": "declared_zero",
					"outside_domain": "reject",
					"interpolation": "piecewise_linear",
					"samples": [
						{"time_s": 0.0, "rate_kg_s": 0.05},
						{"time_s": 4.0, "rate_kg_s": 0.05},
						{"time_s": 8.0, "rate_kg_s": 0.0},
					],
				},
				"material": {
					"schema": "g3_phase_real_sensible_material_v1",
					"component_id": "n-heptane",
					"reference_material": {
						"schema": "g3_phase_reference_CHO_material_v1",
						"liquid_phase": "liquid",
						"vapour_phase": "gas",
						"water_product_phase": "gas",
						"atom_mass_basis": "nominal_C12_H1_O16",
						"chemical_energy_basis": "complete_oxidation_net",
						"reference_temperature_k": 298.15,
						"reference_pressure_pa": 100000.0,
						"mass_fractions": {
							"C": 0.84,
							"H": 0.16000000000000003,
							"O": 0.0,
						},
						"liquid_heat_kj_kg": 44559.68063872255,
						"vapour_heat_kj_kg": 44925.44910179641,
						"phase_enthalpy_kj_kg": 365.7684630738523,
						"provenance": "declared prototype: NIST TN 2126-upd1 heats per kg on 100.20 g/mol with nominal C7H16 atom fractions; not a heptane calibration",
					},
				},
				"attribution": {
					"input_component_id": "n-heptane",
					"modeled_component_id": "n-heptane",
					"input_quantity": "modeled_component_emission",
					"rule": "same_declared_component",
					"status": "synthetic_declared_emission",
					"provenance": "declared: prescribed emission program, not a measured or predicted evaporation",
				},
				"seed": {
					"schema": "g3_prescribed_real_sensible_seed_v1",
					"initial_o2_kg": 10.0,
					"initial_thermal_budget_kj": 600.0,
					"initial_liquid_sensible_kj": 0.0,
					"energy_boundary_kind": "synthetic_independent_initial_budget",
					"energy_boundary_provenance": "synthetic: independent initial budget, not a measured heat flux",
				},
			},
			"steps": [
				{
					"request": [1.0, 0.0, 90.0, 0.0, 371.0],
					"accepted": true,
					"step": {
						"no_op": false,
						"physical_dt_s": 1.0,
						"source_dt_s": 1.0,
						"requested_release_kg": 0.05,
						"accepted_release_kg": 0.05,
						"rejected_release_kg": 0.0,
						"accepted_oxidation_kg": 0.0,
						"rejected_oxidation_kg": 0.0,
						"release_cost_kj": 20.382317468422173,
						"release_cost_kj_kg": 407.6463493684434,
						"heating_liquid_kj": 90.0,
						"heating_vapour_kj": 0.0,
						"released_liquid_sensible_kj": 4.5,
						"emitted_vapour_sensible_kj": 6.593894314729557,
						"oxidized_sensible_kj": 0.0,
						"chemical_oxidation_heat_kj": 0.0,
						"deposited_increment_kj": 0.0,
						"co2_kg": 0.0,
						"water_vapour_kg": 0.0,
						"o2_consumed_kg": 0.0,
						"mixed_specific_kj_kg": 131.87788629459112,
						"temperature_average_specific_kj_kg": null,
						"emitted_kinds": ["assumption_adopted_by_source_for_vapour_pressure_consistency", "fitted_correlation_of_cited_flow_calorimetry_extrapolated_to_zero_pressure"],
					},
					"phase": {
						"initial_fuel_mass_kg": 1.0,
						"liquid_fuel_kg": 0.95,
						"vapour_fuel_kg": 0.05,
						"o2_kg": 10.0,
						"thermal_budget_kj": 489.6176825315778,
						"deposited_heat_kj": 0.0,
						"liquid_sensible_kj": 85.5,
						"vapour_sensible_kj": 6.593894314729557,
					},
					"time_s": 1.0,
					"accounts": {
						"potential_a_kj": 44577.96906187624,
						"sensible_s_kj": 92.09389431472955,
						"budget_b_kj": 489.6176825315778,
						"deposited_q_kj": 0.0,
						"total_kj": 45159.680638722544,
					},
					"liquid_kinds": ["tabulated_Csat_of_the_source_converted_to_Cp_here"],
					"vapour_kinds": ["assumption_adopted_by_source_for_vapour_pressure_consistency", "fitted_correlation_of_cited_flow_calorimetry_extrapolated_to_zero_pressure"],
				},
				{
					"request": [2.0, 0.02, 40.0, 3.0, 371.0],
					"accepted": true,
					"step": {
						"no_op": false,
						"physical_dt_s": 1.0,
						"source_dt_s": 1.0,
						"requested_release_kg": 0.05,
						"accepted_release_kg": 0.05,
						"rejected_release_kg": 0.0,
						"accepted_oxidation_kg": 0.02,
						"rejected_oxidation_kg": 0.0,
						"release_cost_kj": 18.277054310527433,
						"release_cost_kj_kg": 365.54108621054866,
						"heating_liquid_kj": 40.0,
						"heating_vapour_kj": 3.0,
						"released_liquid_sensible_kj": 6.605263157894737,
						"emitted_vapour_sensible_kj": 6.593894314729557,
						"oxidized_sensible_kj": 3.2375577258918224,
						"chemical_oxidation_heat_kj": 898.5089820359282,
						"deposited_increment_kj": 901.74653976182,
						"co2_kg": 0.061599999999999995,
						"water_vapour_kg": 0.028800000000000006,
						"o2_consumed_kg": 0.0704,
						"mixed_specific_kj_kg": 161.87788629459112,
						"temperature_average_specific_kj_kg": 161.40039588768636,
						"emitted_kinds": ["assumption_adopted_by_source_for_vapour_pressure_consistency", "fitted_correlation_of_cited_flow_calorimetry_extrapolated_to_zero_pressure"],
					},
					"phase": {
						"initial_fuel_mass_kg": 1.0,
						"liquid_fuel_kg": 0.8999999999999999,
						"vapour_fuel_kg": 0.08,
						"o2_kg": 9.9296,
						"thermal_budget_kj": 428.3406282210504,
						"deposited_heat_kj": 901.74653976182,
						"liquid_sensible_kj": 118.89473684210526,
						"vapour_sensible_kj": 12.95023090356729,
					},
					"time_s": 2.0,
					"accounts": {
						"potential_a_kj": 43697.74850299401,
						"sensible_s_kj": 131.84496774567256,
						"budget_b_kj": 428.3406282210504,
						"deposited_q_kj": 901.74653976182,
						"total_kj": 45159.68063872255,
					},
					"liquid_kinds": ["tabulated_Csat_of_the_source_converted_to_Cp_here"],
					"vapour_kinds": ["assumption_adopted_by_source_for_vapour_pressure_consistency", "fitted_correlation_of_cited_flow_calorimetry_extrapolated_to_zero_pressure"],
				},
			],
		},
		"exhaust": {
			"context": {
				"schema": "g3_prescribed_real_sensible_context_v1",
				"program": {
					"profile_id": "declared_exhaust",
					"component_id": "n-heptane",
					"initial_mass_kg": 1.0,
					"mode": "prescribed",
					"quantity": "modeled_component_emission",
					"unit": "kg/s",
					"time_origin": "declared_zero",
					"outside_domain": "reject",
					"interpolation": "piecewise_linear",
					"samples": [
						{"time_s": 0.0, "rate_kg_s": 0.5},
						{"time_s": 2.0, "rate_kg_s": 0.5},
					],
				},
				"material": {
					"schema": "g3_phase_real_sensible_material_v1",
					"component_id": "n-heptane",
					"reference_material": {
						"schema": "g3_phase_reference_CHO_material_v1",
						"liquid_phase": "liquid",
						"vapour_phase": "gas",
						"water_product_phase": "gas",
						"atom_mass_basis": "nominal_C12_H1_O16",
						"chemical_energy_basis": "complete_oxidation_net",
						"reference_temperature_k": 298.15,
						"reference_pressure_pa": 100000.0,
						"mass_fractions": {
							"C": 0.84,
							"H": 0.16000000000000003,
							"O": 0.0,
						},
						"liquid_heat_kj_kg": 44559.68063872255,
						"vapour_heat_kj_kg": 44925.44910179641,
						"phase_enthalpy_kj_kg": 365.7684630738523,
						"provenance": "declared prototype: NIST TN 2126-upd1 heats per kg on 100.20 g/mol with nominal C7H16 atom fractions; not a heptane calibration",
					},
				},
				"attribution": {
					"input_component_id": "n-heptane",
					"modeled_component_id": "n-heptane",
					"input_quantity": "modeled_component_emission",
					"rule": "same_declared_component",
					"status": "synthetic_declared_emission",
					"provenance": "declared: prescribed emission program, not a measured or predicted evaporation",
				},
				"seed": {
					"schema": "g3_prescribed_real_sensible_seed_v1",
					"initial_o2_kg": 10.0,
					"initial_thermal_budget_kj": 2000.0,
					"initial_liquid_sensible_kj": 0.0,
					"energy_boundary_kind": "synthetic_independent_initial_budget",
					"energy_boundary_provenance": "synthetic: independent initial budget, not a measured heat flux",
				},
			},
			"steps": [
				{
					"request": [1.0, 0.0, 0.0, 0.0, 371.0],
					"accepted": true,
					"step": {
						"no_op": false,
						"physical_dt_s": 1.0,
						"source_dt_s": 1.0,
						"requested_release_kg": 0.5,
						"accepted_release_kg": 0.5,
						"rejected_release_kg": 0.0,
						"accepted_oxidation_kg": 0.0,
						"rejected_oxidation_kg": 0.0,
						"release_cost_kj": 248.8231746842217,
						"release_cost_kj_kg": 497.6463493684434,
						"heating_liquid_kj": 0.0,
						"heating_vapour_kj": 0.0,
						"released_liquid_sensible_kj": 0.0,
						"emitted_vapour_sensible_kj": 65.93894314729556,
						"oxidized_sensible_kj": 0.0,
						"chemical_oxidation_heat_kj": 0.0,
						"deposited_increment_kj": 0.0,
						"co2_kg": 0.0,
						"water_vapour_kg": 0.0,
						"o2_consumed_kg": 0.0,
						"mixed_specific_kj_kg": 131.87788629459112,
						"temperature_average_specific_kj_kg": null,
						"emitted_kinds": ["assumption_adopted_by_source_for_vapour_pressure_consistency", "fitted_correlation_of_cited_flow_calorimetry_extrapolated_to_zero_pressure"],
					},
					"phase": {
						"initial_fuel_mass_kg": 1.0,
						"liquid_fuel_kg": 0.5,
						"vapour_fuel_kg": 0.5,
						"o2_kg": 10.0,
						"thermal_budget_kj": 1751.1768253157784,
						"deposited_heat_kj": 0.0,
						"liquid_sensible_kj": 0.0,
						"vapour_sensible_kj": 65.93894314729556,
					},
					"time_s": 1.0,
					"accounts": {
						"potential_a_kj": 44742.56487025948,
						"sensible_s_kj": 65.93894314729556,
						"budget_b_kj": 1751.1768253157784,
						"deposited_q_kj": 0.0,
						"total_kj": 46559.68063872255,
					},
					"liquid_kinds": ["tabulated_Csat_of_the_source_converted_to_Cp_here"],
					"vapour_kinds": ["assumption_adopted_by_source_for_vapour_pressure_consistency", "fitted_correlation_of_cited_flow_calorimetry_extrapolated_to_zero_pressure"],
				},
				{
					"request": [2.0, 0.1, 0.0, 0.0, 371.0],
					"accepted": true,
					"step": {
						"no_op": false,
						"physical_dt_s": 1.0,
						"source_dt_s": 1.0,
						"requested_release_kg": 0.5,
						"accepted_release_kg": 0.5,
						"rejected_release_kg": 0.0,
						"accepted_oxidation_kg": 0.1,
						"rejected_oxidation_kg": 0.0,
						"release_cost_kj": 248.8231746842217,
						"release_cost_kj_kg": 497.6463493684434,
						"heating_liquid_kj": 0.0,
						"heating_vapour_kj": 0.0,
						"released_liquid_sensible_kj": 0.0,
						"emitted_vapour_sensible_kj": 65.93894314729556,
						"oxidized_sensible_kj": 13.187788629459114,
						"chemical_oxidation_heat_kj": 4492.544910179641,
						"deposited_increment_kj": 4505.7326988091,
						"co2_kg": 0.308,
						"water_vapour_kg": 0.14400000000000004,
						"o2_consumed_kg": 0.35200000000000004,
						"mixed_specific_kj_kg": 131.87788629459112,
						"temperature_average_specific_kj_kg": 131.87788629459112,
						"emitted_kinds": ["assumption_adopted_by_source_for_vapour_pressure_consistency", "fitted_correlation_of_cited_flow_calorimetry_extrapolated_to_zero_pressure"],
					},
					"phase": {
						"initial_fuel_mass_kg": 1.0,
						"liquid_fuel_kg": 0.0,
						"vapour_fuel_kg": 0.9,
						"o2_kg": 9.648,
						"thermal_budget_kj": 1502.3536506315568,
						"deposited_heat_kj": 4505.7326988091,
						"liquid_sensible_kj": 0.0,
						"vapour_sensible_kj": 118.69009766513201,
					},
					"time_s": 2.0,
					"accounts": {
						"potential_a_kj": 40432.90419161677,
						"sensible_s_kj": 118.69009766513201,
						"budget_b_kj": 1502.3536506315568,
						"deposited_q_kj": 4505.7326988091,
						"total_kj": 46559.68063872256,
					},
					"liquid_kinds": [],
					"vapour_kinds": ["assumption_adopted_by_source_for_vapour_pressure_consistency", "fitted_correlation_of_cited_flow_calorimetry_extrapolated_to_zero_pressure"],
				},
				{
					"request": [3.0, 0.1, 5.0, 0.0, 371.0],
					"accepted": false,
					"step": {},
					"phase": {
						"initial_fuel_mass_kg": 1.0,
						"liquid_fuel_kg": 0.0,
						"vapour_fuel_kg": 0.9,
						"o2_kg": 9.648,
						"thermal_budget_kj": 1502.3536506315568,
						"deposited_heat_kj": 4505.7326988091,
						"liquid_sensible_kj": 0.0,
						"vapour_sensible_kj": 118.69009766513201,
					},
					"time_s": 2.0,
					"accounts": {
						"potential_a_kj": 40432.90419161677,
						"sensible_s_kj": 118.69009766513201,
						"budget_b_kj": 1502.3536506315568,
						"deposited_q_kj": 4505.7326988091,
						"total_kj": 46559.68063872256,
					},
					"liquid_kinds": [],
					"vapour_kinds": ["assumption_adopted_by_source_for_vapour_pressure_consistency", "fitted_correlation_of_cited_flow_calorimetry_extrapolated_to_zero_pressure"],
				},
				{
					"request": [3.0, 0.1, 0.0, 5.0, 371.0],
					"accepted": true,
					"step": {
						"no_op": false,
						"physical_dt_s": 1.0,
						"source_dt_s": 0.0,
						"requested_release_kg": 0.0,
						"accepted_release_kg": 0.0,
						"rejected_release_kg": 0.0,
						"accepted_oxidation_kg": 0.1,
						"rejected_oxidation_kg": 0.0,
						"release_cost_kj": 0.0,
						"release_cost_kj_kg": 365.7684630738523,
						"heating_liquid_kj": 0.0,
						"heating_vapour_kj": 5.0,
						"released_liquid_sensible_kj": 0.0,
						"emitted_vapour_sensible_kj": 0.0,
						"oxidized_sensible_kj": 13.74334418501467,
						"chemical_oxidation_heat_kj": 4492.544910179641,
						"deposited_increment_kj": 4506.288254364656,
						"co2_kg": 0.308,
						"water_vapour_kg": 0.14400000000000004,
						"o2_consumed_kg": 0.35200000000000004,
						"mixed_specific_kj_kg": 137.4334418501467,
						"temperature_average_specific_kj_kg": null,
						"emitted_kinds": ["assumption_adopted_by_source_for_vapour_pressure_consistency", "fitted_correlation_of_cited_flow_calorimetry_extrapolated_to_zero_pressure"],
					},
					"phase": {
						"initial_fuel_mass_kg": 1.0,
						"liquid_fuel_kg": 0.0,
						"vapour_fuel_kg": 0.8,
						"o2_kg": 9.296,
						"thermal_budget_kj": 1497.3536506315568,
						"deposited_heat_kj": 9012.020953173756,
						"liquid_sensible_kj": 0.0,
						"vapour_sensible_kj": 109.94675348011737,
					},
					"time_s": 3.0,
					"accounts": {
						"potential_a_kj": 35940.35928143713,
						"sensible_s_kj": 109.94675348011737,
						"budget_b_kj": 1497.3536506315568,
						"deposited_q_kj": 9012.020953173756,
						"total_kj": 46559.68063872256,
					},
					"liquid_kinds": [],
					"vapour_kinds": ["assumption_adopted_by_source_for_vapour_pressure_consistency", "fitted_correlation_of_cited_flow_calorimetry_extrapolated_to_zero_pressure"],
				},
			],
		},
		"small_mass": {
			"context": {
				"schema": "g3_prescribed_real_sensible_context_v1",
				"program": {
					"profile_id": "declared_ramp",
					"component_id": "n-heptane",
					"initial_mass_kg": 1e-09,
					"mode": "prescribed",
					"quantity": "modeled_component_emission",
					"unit": "kg/s",
					"time_origin": "declared_zero",
					"outside_domain": "reject",
					"interpolation": "piecewise_linear",
					"samples": [
						{"time_s": 0.0, "rate_kg_s": 5.000000000000001e-11},
						{"time_s": 4.0, "rate_kg_s": 5.000000000000001e-11},
						{"time_s": 8.0, "rate_kg_s": 0.0},
					],
				},
				"material": {
					"schema": "g3_phase_real_sensible_material_v1",
					"component_id": "n-heptane",
					"reference_material": {
						"schema": "g3_phase_reference_CHO_material_v1",
						"liquid_phase": "liquid",
						"vapour_phase": "gas",
						"water_product_phase": "gas",
						"atom_mass_basis": "nominal_C12_H1_O16",
						"chemical_energy_basis": "complete_oxidation_net",
						"reference_temperature_k": 298.15,
						"reference_pressure_pa": 100000.0,
						"mass_fractions": {
							"C": 0.84,
							"H": 0.16000000000000003,
							"O": 0.0,
						},
						"liquid_heat_kj_kg": 44559.68063872255,
						"vapour_heat_kj_kg": 44925.44910179641,
						"phase_enthalpy_kj_kg": 365.7684630738523,
						"provenance": "declared prototype: NIST TN 2126-upd1 heats per kg on 100.20 g/mol with nominal C7H16 atom fractions; not a heptane calibration",
					},
				},
				"attribution": {
					"input_component_id": "n-heptane",
					"modeled_component_id": "n-heptane",
					"input_quantity": "modeled_component_emission",
					"rule": "same_declared_component",
					"status": "synthetic_declared_emission",
					"provenance": "declared: prescribed emission program, not a measured or predicted evaporation",
				},
				"seed": {
					"schema": "g3_prescribed_real_sensible_seed_v1",
					"initial_o2_kg": 10.0,
					"initial_thermal_budget_kj": 600.0,
					"initial_liquid_sensible_kj": 0.0,
					"energy_boundary_kind": "synthetic_independent_initial_budget",
					"energy_boundary_provenance": "synthetic: independent initial budget, not a measured heat flux",
				},
			},
			"steps": [
				{
					"request": [1.0, 1e-11, 5e-08, 0.0, 371.0],
					"accepted": true,
					"step": {
						"no_op": false,
						"physical_dt_s": 1.0,
						"source_dt_s": 1.0,
						"requested_release_kg": 5.000000000000001e-11,
						"accepted_release_kg": 5.000000000000001e-11,
						"rejected_release_kg": 0.0,
						"accepted_oxidation_kg": 1e-11,
						"rejected_oxidation_kg": 0.0,
						"release_cost_kj": 2.2382317468422173e-08,
						"release_cost_kj_kg": 447.6463493684434,
						"heating_liquid_kj": 5e-08,
						"heating_vapour_kj": 0.0,
						"released_liquid_sensible_kj": 2.5e-09,
						"emitted_vapour_sensible_kj": 6.593894314729557e-09,
						"oxidized_sensible_kj": 1.318778862945911e-09,
						"chemical_oxidation_heat_kj": 4.4925449101796405e-07,
						"deposited_increment_kj": 4.5057326988090997e-07,
						"co2_kg": 3.08e-11,
						"water_vapour_kg": 1.4400000000000002e-11,
						"o2_consumed_kg": 3.52e-11,
						"mixed_specific_kj_kg": 131.87788629459112,
						"temperature_average_specific_kj_kg": null,
						"emitted_kinds": ["assumption_adopted_by_source_for_vapour_pressure_consistency", "fitted_correlation_of_cited_flow_calorimetry_extrapolated_to_zero_pressure"],
					},
					"phase": {
						"initial_fuel_mass_kg": 1e-09,
						"liquid_fuel_kg": 9.5e-10,
						"vapour_fuel_kg": 4.000000000000001e-11,
						"o2_kg": 9.9999999999648,
						"thermal_budget_kj": 599.9999999276176,
						"deposited_heat_kj": 4.5057326988090997e-07,
						"liquid_sensible_kj": 4.7499999999999995e-08,
						"vapour_sensible_kj": 5.275115451783646e-09,
					},
					"time_s": 1.0,
					"accounts": {
						"potential_a_kj": 4.412871457085828e-05,
						"sensible_s_kj": 5.277511545178364e-08,
						"budget_b_kj": 599.9999999276176,
						"deposited_q_kj": 4.5057326988090997e-07,
						"total_kj": 600.0000445596805,
					},
					"liquid_kinds": ["tabulated_Csat_of_the_source_converted_to_Cp_here"],
					"vapour_kinds": ["assumption_adopted_by_source_for_vapour_pressure_consistency", "fitted_correlation_of_cited_flow_calorimetry_extrapolated_to_zero_pressure"],
				},
				{
					"request": [9.0, 1.0, 0.0, 0.0, 400.0],
					"accepted": true,
					"step": {
						"no_op": false,
						"physical_dt_s": 8.0,
						"source_dt_s": 7.0,
						"requested_release_kg": 2.5e-10,
						"accepted_release_kg": 2.5e-10,
						"rejected_release_kg": 0.0,
						"accepted_oxidation_kg": 2.9000000000000003e-10,
						"rejected_oxidation_kg": 0.99999999971,
						"release_cost_kj": 1.2668338001061353e-07,
						"release_cost_kj_kg": 506.7335200424541,
						"heating_liquid_kj": 0.0,
						"heating_vapour_kj": 0.0,
						"released_liquid_sensible_kj": 1.25e-08,
						"emitted_vapour_sensible_kj": 4.7741264242150456e-08,
						"oxidized_sensible_kj": 5.30163796939341e-08,
						"chemical_oxidation_heat_kj": 1.302838023952096e-05,
						"deposited_increment_kj": 1.3081396619214895e-05,
						"co2_kg": 8.932e-10,
						"water_vapour_kg": 4.1760000000000014e-10,
						"o2_consumed_kg": 1.0208e-09,
						"mixed_specific_kj_kg": 182.81510239287618,
						"temperature_average_specific_kj_kg": 182.5953935165775,
						"emitted_kinds": ["assumption_adopted_by_source_for_vapour_pressure_consistency", "fitted_correlation_of_cited_flow_calorimetry_extrapolated_to_zero_pressure"],
					},
					"phase": {
						"initial_fuel_mass_kg": 1e-09,
						"liquid_fuel_kg": 7.000000000000001e-10,
						"vapour_fuel_kg": 0.0,
						"o2_kg": 9.999999998944,
						"thermal_budget_kj": 599.9999998009342,
						"deposited_heat_kj": 1.3531969889095806e-05,
						"liquid_sensible_kj": 3.4999999999999996e-08,
						"vapour_sensible_kj": 0.0,
					},
					"time_s": 9.0,
					"accounts": {
						"potential_a_kj": 3.119177644710579e-05,
						"sensible_s_kj": 3.4999999999999996e-08,
						"budget_b_kj": 599.9999998009342,
						"deposited_q_kj": 1.3531969889095806e-05,
						"total_kj": 600.0000445596805,
					},
					"liquid_kinds": ["tabulated_Csat_of_the_source_converted_to_Cp_here"],
					"vapour_kinds": [],
				},
			],
		},
	},
}
# END GENERATED COMPOSITION EXPECTATIONS
var _failures: Array[String] = []
var _failed: bool = false
var _checks: int = 0
var _groups: Array[String] = []
var _observations: Dictionary = {}


## Test double: a coherence check that stops and reports nothing.
class Mute extends "res://sim/fire/PrescribedRealSensiblePhaseController.gd":
	var verdict: Variant = null

	func _check_owned(value: Variant, context: Dictionary, errors: Array[String]) -> Dictionary:
		if typeof(verdict) == TYPE_DICTIONARY:
			return verdict
		return super._check_owned(value, context, errors)


## Test double: a step preview that ends without an explicit positive result.
class Loose extends "res://sim/fire/PrescribedRealSensiblePhaseController.gd":
	var forged: Variant = null

	func preview_step(request: Variant) -> Dictionary:
		if typeof(forged) == TYPE_DICTIONARY:
			return forged
		return super.preview_step(request)


## Test double: the acceptance gate itself stops, as an aborted typed function
## does in Godot 4.7.1: it returns the default of its type and adds no error.
## `stop_at` chooses which call stops: -1 every one, n only the n-th, 0 none.
class Stopped extends "res://sim/fire/PrescribedRealSensiblePhaseController.gd":
	var stop_at: int = 0
	var calls: int = 0

	func arm(which: int) -> void:
		calls = 0
		stop_at = which

	func _admits(value: Variant, context: Dictionary, errors: Array[String]) -> bool:
		calls += 1
		if stop_at < 0 or calls == stop_at:
			return false
		return super._admits(value, context, errors)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_groups.append("K01")
	_ledger_contract()
	_groups.append("K02")
	_analytic()
	_groups.append("K03")
	for name: String in EXPECTED.get("sequences", {}):
		_play(name, _start(_parts(name)), 0, -1, true)
	_groups.append("K04")
	_mixing()
	_groups.append("K05")
	_limits()
	_groups.append("K06")
	_histories()
	_groups.append("K07")
	_restart()
	_groups.append("K08")
	_restore_rejections()
	_groups.append("K09")
	_positive_verdict()
	_groups.append("K10")
	_identity()
	_groups.append("K11")
	_separation()
	_groups.append("K12")
	_support()
	_groups.append("K13")
	_atomicity()
	_groups.append("K14")
	_labels()
	print("G3_REAL_SENSIBLE_COMPOSITION " + JSON.stringify({"groups": _groups, "checks": _checks,
		"failures": _failures, "observations": _observations}, "", false, true))
	if _failed:
		quit(1)
		return
	print("G3_REAL_SENSIBLE_COMPOSITION_PASS")
	quit(0)


# --- K01: the ledger entry of the real contract --------------------------------

func _ledger_contract() -> void:
	var material: Dictionary = _context(_parts("main"))["material"]
	var state: Dictionary = _state(1.0, 1.0, 0.0, 10.0, 600.0, 0.0, -5.0, 0.0)
	var request: Dictionary = {"dt_s": 1.0, "release_kg": 0.05, "oxidation_kg": 0.0, "heat_liquid_kj": 100.0,
		"heat_vapour_kj": 0.0, "emitted_vapour_temperature_k": 371.0}
	var result: Dictionary = Budget.propose_phase_sensible_real(state, request, material)
	_valid(result, "real ledger accepts the real contract")
	_expect(result.get("schema") == "g3_phase_real_sensible_budget_v1", "real ledger result schema")
	_expect(result.get("scope") == "real_limited_properties_declared_chemistry_synthetic_budget_not_fire_validation",
		"real ledger scope separates properties, chemistry and budget")
	for flag: String in ["physical_approval", "integration_enabled", "product_activation"]:
		_expect(result.get(flag, true) == false, "real ledger " + flag + " stays false")
	var first: Dictionary = _row("main", 0)
	for key: String in PHASE_NUMBERS:
		_close(_n(_d(result, "candidate"), key), first["phase"][key], 1.0, "ledger " + key)
	_expect(_d(result, "candidate").get("schema") == "g3_phase_real_sensible_state_v1", "candidate keeps the real state schema")
	for excluded: String in ["cooling", "evaporation_prediction", "engine_integration", "enthalpy_to_EOS"]:
		_expect(excluded in result.get("excluded", []), "ledger still excludes " + excluded)
	# The synthetic entry and the real entry never accept each other's contract.
	_refuses(Budget.propose_phase_sensible(state, request, material), "synthetic ledger refuses the real contract")
	var relabelled: Dictionary = state.duplicate(true)
	relabelled["schema"] = "g3_phase_sensible_state_v1"
	_refuses(Budget.propose_phase_sensible_real(relabelled, request, material), "real ledger refuses a synthetic state")
	var synthetic_material: Dictionary = material.duplicate(true)
	synthetic_material["schema"] = "g3_phase_sensible_material_v1"
	_refuses(Budget.propose_phase_sensible_real(state, request, synthetic_material), "real ledger refuses a synthetic material")
	_refuses(Budget.propose_phase_sensible(relabelled, request, synthetic_material),
		"synthetic ledger refuses real profiles under synthetic labels")
	for key: String in ["liquid_profile", "vapour_profile"]:
		var mixed: Dictionary = material.duplicate(true)
		mixed[key] = _synthetic_profile("liquid" if key == "liquid_profile" else "gas")
		_refuses(Budget.propose_phase_sensible_real(state, request, mixed), "real ledger refuses a synthetic " + key)
	var swapped: Dictionary = material.duplicate(true)
	swapped["liquid_profile"] = material["vapour_profile"].duplicate(true)
	_refuses(Budget.propose_phase_sensible_real(state, request, swapped), "real ledger refuses the gas profile as liquid")
	swapped = material.duplicate(true)
	swapped["vapour_profile"] = material["liquid_profile"].duplicate(true)
	_refuses(Budget.propose_phase_sensible_real(state, request, swapped), "real ledger refuses the liquid profile as vapour")
	var other: Dictionary = state.duplicate(true)
	other["component_id"] = "n-octane"
	_refuses(Budget.propose_phase_sensible_real(other, request, material), "real ledger refuses another component")
	var renamed: Dictionary = material.duplicate(true)
	renamed["component_id"] = "n-octane"
	_refuses(Budget.propose_phase_sensible_real(other, request, renamed),
		"real ledger refuses the heptane profiles under another component")
	# Each phase on its own support and prescribed heat all or nothing, at the ledger itself.
	var gas_k: Array = EXPECTED.get("gas_support_k", [NAN, NAN])
	for temperature: float in [gas_k[0] - 1.0e-9, gas_k[1] + 1.0e-9, 279.99, 480.0]:
		var outside: Dictionary = request.duplicate(true)
		outside["emitted_vapour_temperature_k"] = temperature
		_refuses(Budget.propose_phase_sensible_real(state, outside, material),
			"real ledger refuses an emission outside the gas support " + str(temperature))
	for temperature: float in [gas_k[0], gas_k[1]]:
		var inside: Dictionary = request.duplicate(true)
		inside["emitted_vapour_temperature_k"] = temperature
		_valid(Budget.propose_phase_sensible_real(state, inside, material), "real ledger accepts an emission at the end of the gas support")
	var poor: Dictionary = state.duplicate(true)
	poor["thermal_budget_kj"] = 10.0
	var heated: Dictionary = request.duplicate(true)
	heated["heat_liquid_kj"] = 20.0
	_refuses(Budget.propose_phase_sensible_real(poor, heated, material), "real ledger refuses heating that B cannot pay: all or nothing")
	heated["heat_liquid_kj"] = 10.0
	var paid: Dictionary = Budget.propose_phase_sensible_real(poor, heated, material)
	_valid(paid, "real ledger accepts heating that exactly empties B")
	_expect(_n(paid, "accepted_heating_kj") == 10.0 and _n(paid, "accepted_release_kg") == 0.0
		and _n(_d(paid, "candidate"), "thermal_budget_kj") == 0.0, "after it nothing is left to pay any release")
	var overheated: Dictionary = request.duplicate(true)
	overheated["heat_liquid_kj"] = 200.0
	_refuses(Budget.propose_phase_sensible_real(state, overheated, material), "real ledger refuses a liquid heated beyond its support")
	for sensible: float in [-41.0, 175.0]:
		var beyond: Dictionary = state.duplicate(true)
		beyond["liquid_sensible_kj"] = sensible
		_refuses(Budget.propose_phase_sensible_real(beyond, request, material), "real ledger refuses a liquid outside its support " + str(sensible))
	for bad: Variant in [null, [], "state", 1, true]:
		_refuses(Budget.propose_phase_sensible_real(bad, request, material), "real ledger refuses a state that is not a Dictionary")
		_refuses(Budget.propose_phase_sensible_real(state, bad, material), "real ledger refuses a request that is not a Dictionary")
		_refuses(Budget.propose_phase_sensible_real(state, request, bad), "real ledger refuses a material that is not a Dictionary")


# --- K02: closed form on knots of the real profiles ----------------------------

func _analytic() -> void:
	var analytic: Dictionary = EXPECTED.get("analytic", {})
	var owner: RefCounted = _start(analytic.get("context", {}))
	var liquid: Dictionary = Real.evaluate(_approved(LIQUID), analytic.get("liquid_knot_k"))
	var gas: Dictionary = Real.evaluate(_approved(GAS), analytic.get("gas_knot_k"))
	var knots: Array = analytic.get("knot_enthalpies_kj_kg", [NAN, NAN, NAN])
	_close(_n(_d(liquid, "candidate"), "specific_sensible_enthalpy_kj_kg"), knots[0], 1.0, "liquid knot enthalpy")
	_close(_n(_d(gas, "candidate"), "specific_sensible_enthalpy_kj_kg"), knots[2], 1.0, "gas knot enthalpy")
	for row: Dictionary in analytic.get("steps", []):
		var result: Dictionary = owner.commit_step(_request(row["request"]), _generation(owner))
		_valid(result, "analytic step")
		var label: String = "analytic t=" + str(row["request"][0]) + " "
		_close(_n(_d(result, "step"), "release_cost_kj_kg"), row["release_cost_kj_kg"], 1.0, label + "cost per kg")
		for key: String in PHASE_NUMBERS:
			_close(_n(_d(owner.snapshot(), "phase"), key), row["phase"][key], 1.0, label + key)
		var accounts: Dictionary = _d(_d(result, "report"), "accounts")
		_close(_n(accounts, "potential_a_kj"), row["potential_a_kj"], 1.0, label + "A")
		_close(_n(accounts, "total_kj"), row["total_kj"], 1.0, label + "A+S+B+Q")
		_observe("analytic_total_" + str(row["request"][0]), _n(accounts, "total_kj"))


# --- K03: every prescribed sequence against the independent oracle -------------

func _play(name: String, owner: RefCounted, first: int, last: int, check: bool) -> void:
	var rows: Array = EXPECTED["sequences"][name]["steps"]
	var scale: float = EXPECTED["sequences"][name]["context"]["program"]["initial_mass_kg"]
	var material: Dictionary = EXPECTED["sequences"][name]["context"]["material"]["reference_material"]
	var total: float = _n(_d(_report_of(owner), "accounts"), "total_kj")
	for index: int in range(first, rows.size() if last < 0 else last):
		var row: Dictionary = rows[index]
		var label: String = name + "[" + str(index) + "] "
		var before: Dictionary = owner.snapshot()
		var result: Dictionary = owner.commit_step(_request(row["request"]), _generation(owner))
		if not check:
			continue
		if not row["accepted"]:
			_refused(owner, result, before, label + "step outside the contract")
			continue
		_valid(result, label + "accepted")
		var step: Dictionary = _d(result, "step")
		var after: Dictionary = owner.snapshot()
		if row["step"]["no_op"]:
			_expect(result.get("no_op") == true, label + "is reported as a no-op")
			_expect(_bits(after) == _bits(before), label + "no-op leaves every bit of the root")
			continue
		_expect(result.get("no_op") == false, label + "is a committed step")
		_expect(_generation(owner) == int(before.get("generation", -9)) + 1, label + "advances one generation")
		for key: String in STEP_NUMBERS:
			_close(_n(step, key), row["step"][key], scale, label + key)
		for key: String in PHASE_NUMBERS:
			_close(_n(_d(after, "phase"), key), row["phase"][key], scale, label + "phase " + key)
		_close(_n(after, "physical_time_s"), row["time_s"], 1.0, label + "physical clock")
		var accounts: Dictionary = _d(_d(result, "report"), "accounts")
		for key: String in ACCOUNTS:
			_close(_n(accounts, key), row["accounts"][key], 1.0, label + "account " + key)
		_balances(before, after, step, material, label)
		_energy(_n(accounts, "total_kj"), total, label + "A+S+B+Q is conserved: no cooling and no loss")
		var composition: Dictionary = _d(_d(result, "report"), "composition")
		_expect(_d(composition, "liquid").get("evidence_kinds") == row["liquid_kinds"], label + "liquid evidence classes")
		_expect(_d(composition, "vapour").get("evidence_kinds") == row["vapour_kinds"], label + "vapour evidence classes")
		var emitted: Dictionary = _d(step, "emitted_vapour_evidence")
		_expect(_kinds(emitted) == row["step"]["emitted_kinds"], label + "emission evidence classes")
		_expect(emitted.get("temperature_is_prescribed_not_predicted") == true, label + "emission temperature is labelled prescribed")
		_expect(emitted.get("temperature_k") == row["request"][4], label + "emission evidence is that of the requested temperature")


## Each account closes by itself, from the confirmed states and the step accounts.
func _balances(before: Dictionary, after: Dictionary, step: Dictionary, material: Dictionary, label: String) -> void:
	var p: Dictionary = _d(before, "phase")
	var q: Dictionary = _d(after, "phase")
	var hl: float = material["liquid_heat_kj_kg"]
	var hv: float = material["vapour_heat_kj_kg"]
	var latent: float = material["phase_enthalpy_kj_kg"]
	var heating: float = _n(step, "heating_liquid_kj") + _n(step, "heating_vapour_kj")
	var a_before: float = _n(p, "liquid_fuel_kg") * hl + _n(p, "vapour_fuel_kg") * hv
	var a_after: float = _n(q, "liquid_fuel_kg") * hl + _n(q, "vapour_fuel_kg") * hv
	_energy(a_before + _n(step, "accepted_release_kg") * latent, a_after + _n(step, "chemical_oxidation_heat_kj"), label + "A closes")
	_energy(_n(p, "liquid_sensible_kj") + _n(step, "heating_liquid_kj"),
		_n(q, "liquid_sensible_kj") + _n(step, "released_liquid_sensible_kj"), label + "liquid S closes")
	_energy(_n(p, "vapour_sensible_kj") + _n(step, "heating_vapour_kj") + _n(step, "emitted_vapour_sensible_kj"),
		_n(q, "vapour_sensible_kj") + _n(step, "oxidized_sensible_kj"), label + "vapour S closes")
	_energy(_n(p, "thermal_budget_kj"), _n(q, "thermal_budget_kj") + heating + _n(step, "release_cost_kj"), label + "B closes")
	_energy(_n(p, "deposited_heat_kj") + _n(step, "chemical_oxidation_heat_kj") + _n(step, "oxidized_sensible_kj"),
		_n(q, "deposited_heat_kj"), label + "Q closes")
	_energy(_n(step, "release_cost_kj") + _n(step, "released_liquid_sensible_kj"),
		_n(step, "accepted_release_kg") * latent + _n(step, "emitted_vapour_sensible_kj"), label + "release cost pays latent and sensible")
	# B only decreases: nothing deposited in Q comes back to pay heating or release.
	_expect(_n(q, "thermal_budget_kj") <= _n(p, "thermal_budget_kj"), label + "B never grows")
	_expect(_n(step, "deposited_increment_kj") == _n(step, "chemical_oxidation_heat_kj") + _n(step, "oxidized_sensible_kj"),
		label + "Q increment is chemical plus the signed sensible of what burned")


# --- K04: mixing adds enthalpy; it does not average temperatures ---------------

func _mixing() -> void:
	var separated: int = 0
	for name: String in EXPECTED.get("sequences", {}):
		var owner: RefCounted = _start(_parts(name))
		var rows: Array = EXPECTED["sequences"][name]["steps"]
		for index: int in range(rows.size()):
			var row: Dictionary = rows[index]
			owner.commit_step(_request(row["request"]), _generation(owner))
			if not row["accepted"] or row["step"]["no_op"] or row["step"]["temperature_average_specific_kj_kg"] == null:
				continue
			var phase: Dictionary = _d(owner.snapshot(), "phase")
			if _n(phase, "vapour_fuel_kg") <= 0.0:
				continue
			var specific: float = _n(phase, "vapour_sensible_kj") / _n(phase, "vapour_fuel_kg")
			var label: String = name + "[" + str(index) + "] "
			_close(specific, row["step"]["mixed_specific_kj_kg"], 1.0, label + "vapour holds the mixed enthalpy")
			var average: float = row["step"]["temperature_average_specific_kj_kg"]
			if absf(average - float(row["step"]["mixed_specific_kj_kg"])) > 1.0e-3:
				separated += 1
				_expect(absf(specific - average) > 1.0e-4, label + "is not the enthalpy of a temperature average")
	_observe("mixing_rows_where_a_temperature_average_differs", float(separated))
	_expect(separated >= 3, "the corpus holds mixtures that a temperature average gets wrong")


# --- K05: release and oxidation are capped by B, by O2 and by inventory --------

func _limits() -> void:
	var capped: Dictionary = _final("budget_limited", 1)
	var first: Dictionary = _row("budget_limited", 0)
	_expect(_n(_d(capped, "phase"), "thermal_budget_kj") == 0.0, "B-limited release leaves B exactly empty")
	_expect(first["step"]["accepted_release_kg"] < first["step"]["requested_release_kg"], "the oracle case is B-limited")
	var owner: RefCounted = _start(_parts("budget_limited"))
	_play("budget_limited", owner, 0, 4, false)
	var phase: Dictionary = _d(owner.snapshot(), "phase")
	_expect(_n(phase, "deposited_heat_kj") > 900.0 and _n(phase, "thermal_budget_kj") == 0.0, "Q is large while B is empty")
	_expect(_n(phase, "liquid_fuel_kg") == _n(_d(capped, "phase"), "liquid_fuel_kg"), "Q did not finance any later release")
	var before: Dictionary = owner.snapshot()
	_refused(owner, owner.commit_step(_request(_row("budget_limited", 4)["request"]), _generation(owner)), before,
		"heating that B cannot pay is refused although Q could")
	var starved: Dictionary = _final("oxygen_limited", 1)
	_expect(_n(_d(starved, "phase"), "o2_kg") == 0.0, "O2-limited oxidation leaves O2 exactly empty")
	_expect(_row("oxygen_limited", 0)["step"]["accepted_oxidation_kg"] < 0.04, "the oracle case is O2-limited")
	_expect(_row("oxygen_limited", 1)["step"]["accepted_oxidation_kg"] == 0.0, "no oxidation without O2 in the oracle")
	var emptied: Dictionary = _final("main", 4)
	_expect(_n(_d(emptied, "phase"), "vapour_fuel_kg") == 0.0 and _n(_d(emptied, "phase"), "vapour_sensible_kj") == 0.0,
		"inventory-limited oxidation leaves no vapour and no orphan sensible")
	_expect(_row("main", 3)["step"]["accepted_oxidation_kg"] < 0.5, "the oracle case is inventory-limited")
	var gone: Dictionary = _final("exhaust", 2)
	_expect(_n(_d(gone, "phase"), "liquid_fuel_kg") == 0.0 and _n(_d(gone, "phase"), "liquid_sensible_kj") == 0.0,
		"an exhausted liquid leaves no orphan sensible")


# --- K06: equal masses, different thermal histories ----------------------------

func _histories() -> void:
	var cold: RefCounted = _start(_parts("history_cold"))
	var hot: RefCounted = _start(_parts("history_hot"))
	_expect(cold.snapshot().get("context_fingerprint") == hot.snapshot().get("context_fingerprint"), "both histories share one context")
	_play("history_cold", cold, 0, -1, false)
	_play("history_hot", hot, 0, -1, false)
	var a: Dictionary = _d(cold.snapshot(), "phase")
	var b: Dictionary = _d(hot.snapshot(), "phase")
	for key: String in ["liquid_fuel_kg", "vapour_fuel_kg", "o2_kg", "initial_fuel_mass_kg"]:
		_expect(_n(a, key) == _n(b, key), "histories end with the same " + key)
	for key: String in ["liquid_sensible_kj", "vapour_sensible_kj", "thermal_budget_kj", "deposited_heat_kj"]:
		_expect(absf(_n(a, key) - _n(b, key)) > 0.5, "histories differ in " + key)
	# The thermal accounts travel with the snapshot; they cannot be rebuilt from mass.
	var saved: Dictionary = hot.snapshot()
	var restored: Dictionary = cold.restore(saved, _generation(cold))
	_valid(restored, "a hot history is restored in an owner that ran cold")
	for key: String in PHASE_NUMBERS:
		_expect(_n(_d(cold.snapshot(), "phase"), key) == _n(_d(saved, "phase"), key), "restored history keeps " + key)
	var fresh: RefCounted = _start(_parts("history_cold"))
	_play("history_cold", fresh, 0, -1, false)
	for key: String in ["liquid_sensible_kj", "vapour_sensible_kj", "thermal_budget_kj", "deposited_heat_kj"]:
		var forged: Dictionary = fresh.snapshot()
		_put(forged, "phase", key, _n(_d(saved, "phase"), key))
		var before: Dictionary = fresh.snapshot()
		_refused(fresh, fresh.restore(forged, _generation(fresh)), before, "cold masses with a hot " + key)
	var grafted: Dictionary = fresh.snapshot()
	grafted["totals"] = _d(saved, "totals").duplicate(true)
	var untouched: Dictionary = fresh.snapshot()
	_refused(fresh, fresh.restore(grafted, _generation(fresh)), untouched, "cold phase with hot cumulative accounts")


# --- K07: a run continued after a restart equals the uninterrupted run ---------

func _restart() -> void:
	var continuous: RefCounted = _start(_parts("main"))
	_play("main", continuous, 0, -1, false)
	var first: RefCounted = _start(_parts("main"))
	_play("main", first, 0, 2, false)
	var saved: Dictionary = first.snapshot()
	var second: RefCounted = _start(_parts("main"))
	_valid(second.restore(saved, 0), "restart restores the saved root")
	_expect(_generation(second) == 1, "restore takes a new generation")
	_play("main", second, 2, -1, false)
	var a: Dictionary = continuous.snapshot()
	var b: Dictionary = second.snapshot()
	for key: String in ["schema", "context_fingerprint", "physical_time_s", "progress", "phase", "totals"]:
		_expect(_bits(a.get(key)) == _bits(b.get(key)), "restart reproduces " + key + " bit for bit")
	_expect(_bits(_d(_report_of(continuous), "accounts")) == _bits(_d(_report_of(second), "accounts")), "restart reproduces the accounts")
	_close(_n(a, "physical_time_s"), 9.0, 1.0, "physical clock passes the end of the source")
	_close(_n(_d(a, "progress"), "time_s"), 8.0, 1.0, "source clock stops at the end of its domain")
	_expect(_report_of(continuous).get("source_finished") == true, "source reported finished")


# --- K08: an incoherent or foreign snapshot is refused and nothing is written --

func _restore_rejections() -> void:
	var owner: RefCounted = _start(_parts("main"))
	_play("main", owner, 0, 2, false)
	var good: Dictionary = owner.snapshot()
	var before: Dictionary = owner.snapshot()
	var edits: Array = [
		["phase", "liquid_fuel_kg", 0.5], ["phase", "vapour_fuel_kg", 0.2], ["phase", "o2_kg", 10.0],
		["phase", "thermal_budget_kj", 600.0], ["phase", "deposited_heat_kj", 0.0],
		["phase", "liquid_sensible_kj", 0.0], ["phase", "vapour_sensible_kj", 0.0],
		["phase", "initial_fuel_mass_kg", 2.0], ["phase", "schema", "g3_phase_sensible_state_v1"],
		["phase", "component_id", "n-octane"],
		["totals", "oxidized_fuel_kg", 0.0], ["totals", "heating_liquid_kj", 0.0], ["totals", "release_cost_kj", 0.0],
		["totals", "released_liquid_sensible_kj", 0.0], ["totals", "emitted_vapour_sensible_kj", 0.0],
		["totals", "oxidized_sensible_kj", 0.0], ["totals", "chemical_oxidation_heat_kj", 0.0],
		["totals", "co2_kg", 0.0], ["totals", "water_vapour_kg", 0.0], ["totals", "o2_consumed_kg", 0.0],
		["progress", "time_s", 1.0], ["progress", "accepted_kg", 0.0], ["progress", "fingerprint", "0"],
		["", "physical_time_s", 3.0], ["", "schema", "g3_prescribed_sensible_snapshot_v1"],
		["", "context_fingerprint", "0"], ["", "generation", -1], ["", "generation", 1.0],
		["phase", "liquid_sensible_kj", NAN], ["phase", "thermal_budget_kj", INF], ["totals", "co2_kg", "0"],
		["phase", "o2_kg", true], ["", "physical_time_s", null],
	]
	for edit: Array in edits:
		var forged: Dictionary = good.duplicate(true)
		_put(forged, edit[0], edit[1], edit[2])
		_refused(owner, owner.restore(forged, _generation(owner)), before, "restore with " + str(edit[0]) + "." + str(edit[1]) + " changed")
	for part: String in ["schema", "context_fingerprint", "generation", "physical_time_s", "progress", "phase", "totals"]:
		var partial: Dictionary = good.duplicate(true)
		partial.erase(part)
		_refused(owner, owner.restore(partial, _generation(owner)), before, "partial restore without " + part)
	for part: String in ["liquid_sensible_kj", "vapour_sensible_kj", "thermal_budget_kj"]:
		var partial: Dictionary = good.duplicate(true)
		_d(partial, "phase").erase(part)
		_refused(owner, owner.restore(partial, _generation(owner)), before, "restore without the thermal account " + part)
	for bad: Variant in [null, [], "snapshot", 1, true, {}]:
		_refused(owner, owner.restore(bad, _generation(owner)), before, "restore of something that is not a snapshot")
	for stale: Variant in [_generation(owner) - 1, _generation(owner) + 1, -1, null, "2", 2.0, true]:
		_refused(owner, owner.restore(good, stale), before, "restore under a generation that is not the current one")
	var extra: Dictionary = good.duplicate(true)
	extra["signature"] = "0"
	_refused(owner, owner.restore(extra, _generation(owner)), before, "restore with an undeclared field")
	_valid(owner.restore(good, _generation(owner)), "control: the coherent snapshot is restored")
	_expect(_generation(owner) == int(before.get("generation", -9)) + 1, "control restore takes a new generation")


# --- K09: without an explicit positive verdict nothing is accepted or written --

func _positive_verdict() -> void:
	var silent: Array = [{}, {"valid": false}, {"valid": 1}, {"valid": "true"}, {"valid": null}, {"errors": []}]
	for verdict: Dictionary in silent:
		var unborn: RefCounted = Mute.new()
		unborn.verdict = verdict
		var refused: Dictionary = unborn.initialize(_context(_parts("main")))
		_expect(refused.get("valid", true) == false and unborn.snapshot().is_empty(),
			"initialize without a positive verdict writes nothing " + str(verdict))
		_expect("positive verdict" in str(refused.get("errors", [])), "the refusal is explained " + str(verdict))
	var owner: RefCounted = Mute.new()
	_valid(owner.initialize(_context(_parts("main"))), "control: the double initializes with the real check")
	_valid(owner.commit_step(_request(_row("main", 0)["request"]), 0), "control: the double commits with the real check")
	var before: Dictionary = owner.snapshot()
	var forged: Dictionary = owner.snapshot()
	_put(forged, "phase", "liquid_fuel_kg", 0.5)
	_put(forged, "phase", "thermal_budget_kj", 9000.0)
	var next: Dictionary = _request(_row("main", 1)["request"])
	for verdict: Dictionary in silent:
		owner.verdict = verdict
		_refused(owner, owner.preview_step(next), before, "preview without a positive verdict " + str(verdict))
		_refused(owner, owner.commit_step(next, _generation(owner)), before, "commit without a positive verdict " + str(verdict))
		_refused(owner, owner.restore(forged, _generation(owner)), before, "forged restore without a positive verdict " + str(verdict))
		_refused(owner, owner.restore(before, _generation(owner)), before, "even a coherent restore needs the verdict " + str(verdict))
	owner.verdict = null
	_refused(owner, owner.restore(forged, _generation(owner)), before, "control: the real check refuses the forged snapshot")
	_valid(owner.commit_step(next, _generation(owner)), "control: the real check accepts the next step")
	# Control of the double: with a positive answer the forged state would pass, so
	# the refusals above come from the missing verdict and from nothing else.
	var control: RefCounted = Mute.new()
	_valid(control.initialize(_context(_parts("main"))), "control double initializes")
	control.verdict = {"valid": true}
	var planted: Dictionary = control.snapshot()
	_put(planted, "phase", "thermal_budget_kj", 9000.0)
	_expect(control.restore(planted, 0).get("valid", false) == true, "control: the double really replaces the check")
	# The gate itself stops in silence: no error is added, and still nothing passes.
	for which: int in [-1, 1]:
		var unborn_stopped: RefCounted = Stopped.new()
		unborn_stopped.arm(which)
		var silence: Dictionary = unborn_stopped.initialize(_context(_parts("main")))
		_expect(silence.get("valid", true) == false and unborn_stopped.snapshot().is_empty(), "initialize behind a stopped gate writes nothing")
		_expect("positive verdict" in str(silence.get("errors", [])), "a stopped gate is still an explained refusal")
	var halted: RefCounted = Stopped.new()
	_valid(halted.initialize(_context(_parts("main"))), "control: the stopped double initializes with the real gate")
	_valid(halted.commit_step(_request(_row("main", 0)["request"]), 0), "control: the stopped double commits with the real gate")
	var held: Dictionary = halted.snapshot()
	var altered: Dictionary = halted.snapshot()
	_put(altered, "phase", "thermal_budget_kj", 9000.0)
	# Each acceptance point alone: the confirmed state (1) and the candidate or the saved state (2).
	for which: int in [-1, 1, 2]:
		var label: String = " behind a gate stopped at " + str(which)
		halted.arm(which)
		_refused(halted, halted.preview_step(next), held, "preview" + label)
		halted.arm(which)
		_refused(halted, halted.commit_step(next, _generation(halted)), held, "commit" + label)
		halted.arm(which)
		_refused(halted, halted.restore(altered, _generation(halted)), held, "forged restore" + label)
		halted.arm(which)
		_refused(halted, halted.restore(held, _generation(halted)), held, "coherent restore" + label)
	halted.arm(0)
	_valid(halted.commit_step(next, _generation(halted)), "control: the real gate accepts the next step")
	# A preview that ends without an explicit positive result never reaches the write.
	var loose: RefCounted = Loose.new()
	_valid(loose.initialize(_context(_parts("main"))), "control: the loose double initializes")
	var rest: Dictionary = loose.snapshot()
	var candidate: Dictionary = loose.snapshot()
	_put(candidate, "phase", "thermal_budget_kj", 9000.0)
	for result: Dictionary in [{}, {"valid": true}, {"valid": true, "candidate": {}, "step": {"physical_dt_s": 1.0}},
		{"valid": 1, "candidate": candidate, "step": {"physical_dt_s": 1.0}},
		{"valid": "true", "candidate": candidate, "step": {"physical_dt_s": 1.0}},
		{"valid": true, "candidate": candidate}, {"candidate": candidate, "step": {"physical_dt_s": 1.0}}]:
		loose.forged = result
		var outcome: Dictionary = loose.commit_step(next, _generation(loose))
		_expect(outcome.get("valid", true) == false, "commit of an inexplicit preview is refused " + str(result.keys()))
		_expect(_bits(loose.snapshot()) == _bits(rest), "commit of an inexplicit preview writes nothing " + str(result.keys()))
	loose.forged = null
	_valid(loose.commit_step(_request(_row("main", 0)["request"]), 0), "control: the loose double commits a real preview")


# --- K10: the context identity binds the whole content -------------------------

func _identity() -> void:
	# Reported for the contract test, which recomputes them outside Godot.
	var identities: Dictionary = {}
	for name: String in EXPECTED.get("sequences", {}):
		identities[name] = _start(_parts(name)).snapshot().get("context_fingerprint")
	_observations["identities"] = identities
	var whole: Dictionary = Owner._canonical(_context(_parts("main")))
	var paths: Array = []
	_leaves(whole, [], paths)
	var listed: Array = []
	for path: Array in paths:
		listed.append([path, _leaf_text(_at(whole, path))])
	_observations["main_context_leaves"] = listed
	# Every leaf of the content moves the identity: profiles, program, material, seed.
	var probe: RefCounted = Owner.new()
	var base: Variant = probe._fingerprint(whole)
	_expect(base == identities.get("main"), "the identity of the owner is that of its whole canonical context")
	var moved: Dictionary = {base: true}
	var kinds: Dictionary = {}
	for path: Array in paths:
		var changed: Dictionary = whole.duplicate(true)
		var holder: Variant = changed
		for index: int in range(path.size() - 1):
			holder = holder[path[index]]
		var value: Variant = holder[path[-1]]
		kinds[typeof(value)] = true
		match typeof(value):
			TYPE_FLOAT:
				holder[path[-1]] = value * (1.0 + 1.0e-15) if value != 0.0 else 1.0e-300
			TYPE_STRING:
				holder[path[-1]] = value + "x"
			TYPE_BOOL:
				holder[path[-1]] = not value
			TYPE_NIL:
				holder[path[-1]] = 0.0
		var identity: Variant = probe._fingerprint(changed)
		_expect(typeof(identity) == TYPE_STRING and not moved.has(identity), "identity moves with " + str(path))
		moved[identity] = true
	_observe("identity_leaves", float(paths.size()))
	_expect(paths.size() >= 200, "the walk covers the whole content")
	for kind: int in [TYPE_FLOAT, TYPE_STRING, TYPE_BOOL, TYPE_NIL]:
		_expect(kinds.has(kind), "the content holds leaves of type " + str(kind))
	for part: String in ["program", "seed", "attribution"]:
		var without: Dictionary = whole.duplicate(true)
		without.erase(part)
		_expect(probe._fingerprint(without) != base, "identity moves without " + part)
	for part: String in ["liquid_profile", "vapour_profile", "reference_material"]:
		var without: Dictionary = whole.duplicate(true)
		without["material"].erase(part)
		_expect(probe._fingerprint(without) != base, "identity moves without " + part)
	_expect(Synthetic.new()._fingerprint(whole) != base, "the same content under the synthetic owner version has another identity")
	var main: RefCounted = _start(_parts("main"))
	var origin: Dictionary = main.snapshot()
	var seen: Dictionary = {origin.get("context_fingerprint"): true}
	var edits: Array = [
		["seed", "initial_thermal_budget_kj", 601.0], ["seed", "initial_o2_kg", 9.0],
		["seed", "initial_liquid_sensible_kj", -5.5], ["seed", "energy_boundary_provenance", "synthetic: another seed"],
		["program", "profile_id", "declared_other"], ["program", "time_origin", "another_zero"],
		["attribution", "provenance", "declared: another program"],
		["reference", "provenance", "declared prototype: another text"],
		["reference", "mass_fractions", {"C": 0.8, "H": 0.2, "O": 0.0}],
		["rate", 1, 0.04], ["time", 2, 9.0], ["latent", 0, 1.0],
	]
	for edit: Array in edits:
		var context: Dictionary = _context(_parts("main"))
		match edit[0]:
			"seed":
				context["seed"][edit[1]] = edit[2]
			"program":
				context["program"][edit[1]] = edit[2]
			"attribution":
				context["attribution"][edit[1]] = edit[2]
			"reference":
				context["material"]["reference_material"][edit[1]] = edit[2]
			"rate":
				context["program"]["samples"][edit[1]]["rate_kg_s"] = edit[2]
			"time":
				context["program"]["samples"][edit[1]]["time_s"] = edit[2]
			"latent":
				context["material"]["reference_material"]["phase_enthalpy_kj_kg"] += edit[2]
				context["material"]["reference_material"]["vapour_heat_kj_kg"] += edit[2]
		var other: RefCounted = Owner.new()
		var label: String = "context with " + str(edit[0]) + " " + str(edit[1]) + " changed"
		_valid(other.initialize(context), label + " is itself a valid context")
		var identity: Variant = other.snapshot().get("context_fingerprint")
		_expect(typeof(identity) == TYPE_STRING and not seen.has(identity), label + " has another identity")
		seen[identity] = true
		var before: Dictionary = other.snapshot()
		_refused(other, other.restore(origin, 0), before, label + " refuses the snapshot of the original")
		var relabelled: Dictionary = origin.duplicate(true)
		relabelled["context_fingerprint"] = identity
		if edit[0] in ["seed", "rate", "time"] and edit[1] not in ["energy_boundary_provenance"]:
			_refused(other, other.restore(relabelled, 0), before, label + " refuses it also under its own identity")
	# The profiles are bound twice: by identity and by equality with the approved content.
	var changes: Array = [
		["liquid_profile", "molar_mass_g_mol", EXPECTED.get("nominal_molar_mass_g_mol")],
		["vapour_profile", "molar_mass_g_mol", EXPECTED.get("nominal_molar_mass_g_mol")],
		["liquid_profile", "provenance", "another source"], ["vapour_profile", "calibration_status", "validated"],
		["liquid_profile", "temperature_scale", "synthetic_kelvin"], ["vapour_profile", "component_id", "n-octane"],
		["liquid_profile", "extra", 1.0],
	]
	for change: Array in changes:
		var context: Dictionary = _context(_parts("main"))
		context["material"][change[0]][change[1]] = change[2]
		var unborn: RefCounted = Owner.new()
		var refused: Dictionary = unborn.initialize(context)
		_expect(refused.get("valid", true) == false and unborn.snapshot().is_empty(),
			"a profile with " + str(change[1]) + " changed under the same schema is refused")
	for key: String in ["liquid_profile", "vapour_profile"]:
		var knots: Dictionary = _context(_parts("main"))
		knots["material"][key]["samples"][3]["cp_kj_kg_k"] += 1.0e-9
		_expect(Owner.new().initialize(knots).get("valid", true) == false, "one knot of the " + key + " moved is refused")
		var errors: Dictionary = _context(_parts("main"))
		for name: String in errors["material"][key]["declared_errors"]:
			if errors["material"][key]["declared_errors"][name] == null:
				errors["material"][key]["declared_errors"][name] = 0.0
		_expect(Owner.new().initialize(errors).get("valid", true) == false, "an absent uncertainty of the " + key + " filled with a number is refused")
		var tiers: Dictionary = _context(_parts("main"))
		tiers["material"][key]["evidence_tiers"][0]["evidence_kind"] = "measured"
		_expect(Owner.new().initialize(tiers).get("valid", true) == false, "an evidence class of the " + key + " relabelled is refused")
	var basis: Dictionary = _context(_parts("main"))
	basis["material"]["reference_material"]["atom_mass_basis"] = "IUPAC_standard_atomic_weights"
	_expect(Owner.new().initialize(basis).get("valid", true) == false, "the declared prototype keeps its nominal atom basis")


# --- K11: the synthetic and the real path never accept each other --------------

func _separation() -> void:
	var real_context: Dictionary = _context(_parts("main"))
	_expect(Synthetic.new().initialize(real_context).get("valid", true) == false, "synthetic owner refuses the real context")
	var disguised: Dictionary = real_context.duplicate(true)
	disguised["schema"] = "g3_prescribed_sensible_context_v1"
	disguised["seed"]["schema"] = "g3_prescribed_sensible_seed_v1"
	disguised["material"]["schema"] = "g3_phase_sensible_material_v1"
	_expect(Synthetic.new().initialize(disguised).get("valid", true) == false, "synthetic owner refuses real profiles under its own labels")
	var synthetic: Dictionary = _synthetic_context()
	_valid(Synthetic.new().initialize(synthetic), "control: the synthetic owner accepts its own context")
	_expect(Owner.new().initialize(synthetic).get("valid", true) == false, "real owner refuses the synthetic context")
	var dressed: Dictionary = synthetic.duplicate(true)
	dressed["schema"] = "g3_prescribed_real_sensible_context_v1"
	dressed["seed"]["schema"] = "g3_prescribed_real_sensible_seed_v1"
	dressed["material"]["schema"] = "g3_phase_real_sensible_material_v1"
	_expect(Owner.new().initialize(dressed).get("valid", true) == false, "real owner refuses synthetic profiles under real labels")
	for part: String in ["schema", "seed", "material"]:
		var half: Dictionary = real_context.duplicate(true)
		if part == "schema":
			half["schema"] = "g3_prescribed_sensible_context_v1"
		else:
			half[part]["schema"] = synthetic[part]["schema"]
		_expect(Owner.new().initialize(half).get("valid", true) == false, "real owner refuses a synthetic " + part + " label")
	var owner: RefCounted = _start(_parts("main"))
	var before: Dictionary = owner.snapshot()
	var request: Dictionary = _request(_row("main", 0)["request"])
	request["schema"] = "g3_prescribed_sensible_request_v1"
	_refused(owner, owner.commit_step(request, 0), before, "real owner refuses a synthetic request")
	var other: RefCounted = Synthetic.new()
	other.initialize(synthetic)
	_refused(owner, owner.restore(other.snapshot(), 0), before, "real owner refuses a synthetic snapshot")
	var theirs: Dictionary = other.snapshot()
	_expect(other.restore(before, 0).get("valid", true) == false and _bits(other.snapshot()) == _bits(theirs),
		"synthetic owner refuses a real snapshot and writes nothing")
	var ours: Dictionary = _report_of(owner)
	var their_report: Dictionary = _report_of(other)
	_expect(their_report.get("controller_version") == "prescribed_sensible_phase_controller_v1"
		and ours.get("controller_version") != their_report.get("controller_version"), "the two owners carry different versions")
	_expect(their_report.get("scope") == "isolated_synthetic_sensible_owner_not_evaporation_prediction_or_EOS"
		and ours.get("scope") != their_report.get("scope"), "the two owners carry different scopes")
	_expect(not their_report.has("composition") and not their_report.has("co_fed_approval"), "the synthetic report gained no real-composition block")
	var twin: Dictionary = synthetic.duplicate(true)
	var first: RefCounted = Synthetic.new()
	first.initialize(twin)
	_expect(first.snapshot().get("context_fingerprint") == theirs.get("context_fingerprint"), "synthetic identity is deterministic")
	_observe("synthetic_fingerprint_is_text", 1.0 if typeof(theirs.get("context_fingerprint")) == TYPE_STRING else 0.0)


# --- K12: each phase is checked on its own support; nothing is clipped ---------

func _support() -> void:
	var liquid: Array = EXPECTED.get("liquid_support_kj_kg", [NAN, NAN])
	var gas_k: Array = EXPECTED.get("gas_support_k", [NAN, NAN])
	var ends: Array = []
	for index: int in range(2):
		var end: Dictionary = Real.evaluate(_approved(LIQUID), EXPECTED.get("liquid_support_k", [NAN, NAN])[index])
		ends.append(_n(_d(end, "candidate"), "specific_sensible_enthalpy_kj_kg"))
		_close(ends[index], liquid[index], 1.0, "liquid support end in enthalpy")
	for seed: float in [ends[0], ends[1], 0.0, -40.0, 174.0]:
		var inside: Dictionary = _parts("main")
		inside["seed"]["initial_liquid_sensible_kj"] = seed
		_valid(Owner.new().initialize(_context(inside)), "liquid seed inside its own support " + str(seed))
	for seed: float in [liquid[0] - 1.0e-9, liquid[1] + 1.0e-9, -41.0, 175.0, 348.0, -1.0e308, 1.0e308]:
		var outside: Dictionary = _parts("main")
		outside["seed"]["initial_liquid_sensible_kj"] = seed
		var unborn: RefCounted = Owner.new()
		_expect(unborn.initialize(_context(outside)).get("valid", true) == false and unborn.snapshot().is_empty(),
			"liquid seed outside its support is refused, not clipped " + str(seed))
	for bad: Variant in [NAN, INF, -INF, true, "0", null]:
		for key: String in ["initial_o2_kg", "initial_thermal_budget_kj", "initial_liquid_sensible_kj"]:
			var wrong: Dictionary = _parts("main")
			wrong["seed"][key] = bad
			_expect(Owner.new().initialize(_context(wrong)).get("valid", true) == false, "seed " + key + " refuses " + str(bad))
	for temperature: float in [gas_k[0], gas_k[1], 298.15, 371.0]:
		var probe: RefCounted = _start(_parts("support"))
		_valid(probe.commit_step(_request([1.0, 0.0, 0.0, 0.0, temperature]), 0), "emission inside the gas support " + str(temperature))
	var owner: RefCounted = _start(_parts("support"))
	var before: Dictionary = owner.snapshot()
	# 279.99 K is inside what the liquid profile supports; the gas profile does not lend it.
	for temperature: float in [gas_k[0] - 1.0e-9, gas_k[1] + 1.0e-9, 279.99, 298.0, 480.0, 0.0, 1.0e308]:
		_refused(owner, owner.commit_step(_request([1.0, 0.0, 0.0, 0.0, temperature]), 0), before,
			"emission outside the gas support is refused, not clipped " + str(temperature))
	# The liquid may sit near its own upper end while the vapour leaves far above it.
	var hot: Dictionary = _final("separate_supports", 1)
	_expect(_n(_d(hot, "phase"), "liquid_sensible_kj") / _n(_d(hot, "phase"), "liquid_fuel_kg") > 169.0, "liquid near its upper support")
	_expect(_row("separate_supports", 0)["request"][4] > float(EXPECTED.get("liquid_support_k", [0.0, INF])[1]) + 90.0,
		"vapour emitted above anything the liquid profile supports")
	_expect(_row("separate_supports", 0)["accepted"] and _row("separate_supports", 1)["accepted"], "no common temperature is imposed")
	for key: String in ["end_time_s", "oxidation_kg", "heat_liquid_kj", "heat_vapour_kj", "emitted_vapour_temperature_k"]:
		for bad: Variant in [NAN, INF, -INF, -1.0, true, "1", null, [], {}]:
			var request: Dictionary = _request([1.0, 0.0, 0.0, 0.0, 371.0])
			request[key] = bad
			_refused(owner, owner.commit_step(request, 0), before, "request " + key + " refuses " + str(bad))
	_refused(owner, owner.commit_step(_request([1.0, 0.0, 1.0e308, 1.0e308, 371.0]), 0), before, "heating that overflows is refused")
	_refused(owner, owner.commit_step(_request([1.0, 0.0, 1.0e308, 0.0, 371.0]), 0), before, "heating beyond B is refused")
	_refused(owner, owner.commit_step(_request([1.0, 0.0, 0.0, 1.0, 371.0]), 0), before, "heating an absent vapour phase is refused")
	_valid(owner.commit_step(_request([1.0, 1.0e308, 0.0, 0.0, 371.0]), 0), "an oxidation request beyond inventory is capped, not an overflow")
	_valid(owner.commit_step(_request([1.0e300, 0.0, 0.0, 0.0, 371.0]), 1), "a far physical time is clamped to the source domain")
	for extra: String in ["dt_s", "release_kg", "candidate"]:
		var request: Dictionary = _request([2.0e300, 0.0, 0.0, 0.0, 371.0])
		request[extra] = 1.0
		var state: Dictionary = owner.snapshot()
		_refused(owner, owner.commit_step(request, _generation(owner)), state, "request with the undeclared field " + extra)


# --- K13: one aggregate root, pure preview, deep copies, generations -----------

func _atomicity() -> void:
	var unborn: RefCounted = Owner.new()
	_expect(unborn.snapshot().is_empty(), "a new owner holds nothing")
	for result: Dictionary in [unborn.preview_step(_request([1.0, 0.0, 0.0, 0.0, 371.0])),
		unborn.commit_step(_request([1.0, 0.0, 0.0, 0.0, 371.0]), 0), unborn.restore({}, 0)]:
		_expect(result.get("valid", true) == false and unborn.snapshot().is_empty(), "an uninitialized owner refuses and stays empty")
	var context: Dictionary = _context(_parts("main"))
	var owner: RefCounted = Owner.new()
	_valid(owner.initialize(context), "initialize")
	var origin: Dictionary = owner.snapshot()
	_refused(owner, owner.initialize(_context(_parts("support"))), origin, "a second initialize")
	# The owner keeps its own copy of the context.
	context["seed"]["initial_thermal_budget_kj"] = 9000.0
	context["material"]["liquid_profile"]["samples"][0]["cp_kj_kg_k"] = 99.0
	context["program"]["samples"][0]["rate_kg_s"] = 0.0
	var request: Dictionary = _request(_row("main", 0)["request"])
	var preview: Dictionary = owner.preview_step(request)
	_valid(preview, "preview after the caller changed its own context")
	_close(_n(_d(_d(preview, "candidate"), "phase"), "thermal_budget_kj"), _row("main", 0)["phase"]["thermal_budget_kj"], 1.0,
		"the owner context is a deep copy")
	_expect(_bits(owner.snapshot()) == _bits(origin), "preview writes nothing")
	var again: Dictionary = owner.preview_step(request)
	_expect(_bits(_d(again, "candidate")) == _bits(_d(preview, "candidate")) and _bits(_d(again, "step")) == _bits(_d(preview, "step")),
		"preview is repeatable")
	# What the owner returns is a copy: changing it changes nothing inside.
	_put(_d(preview, "candidate"), "phase", "thermal_budget_kj", 9000.0)
	_put(_d(_d(preview, "report"), "confirmed"), "phase", "o2_kg", 0.0)
	var leaked: Dictionary = owner.snapshot()
	_put(leaked, "phase", "liquid_fuel_kg", 0.0)
	_put(leaked, "totals", "co2_kg", 5.0)
	_expect(_bits(owner.snapshot()) == _bits(origin), "returned copies cannot reach the root")
	var committed: Dictionary = owner.commit_step(request, 0)
	_valid(committed, "commit recomputes the intent")
	_close(_n(_d(owner.snapshot(), "phase"), "thermal_budget_kj"), _row("main", 0)["phase"]["thermal_budget_kj"], 1.0,
		"commit ignores what was done to the previewed candidate")
	request["heat_liquid_kj"] = 0.0
	_close(_n(_d(owner.snapshot(), "phase"), "liquid_sensible_kj"), _row("main", 0)["phase"]["liquid_sensible_kj"], 1.0,
		"changing the request afterwards changes nothing")
	var state: Dictionary = owner.snapshot()
	for stale: Variant in [0, 2, -1, null, "1", 1.0, true]:
		_refused(owner, owner.commit_step(_request(_row("main", 1)["request"]), stale), state, "commit under a generation that is not current")
	_refused(owner, owner.commit_step(_request([0.5, 0.0, 0.0, 0.0, 371.0]), 1), state, "physical time cannot go backwards")
	# dt = 0: nothing prescribed is applied and no bit of the root moves.
	var idle: Dictionary = owner.commit_step(_request([1.0, 0.5, 50.0, 2.0, 400.0]), 1)
	_valid(idle, "a step of zero duration is accepted")
	_expect(idle.get("no_op") == true and _bits(owner.snapshot()) == _bits(state), "a step of zero duration is an exact no-op")
	for key: String in ["accepted_release_kg", "accepted_oxidation_kg", "heating_liquid_kj", "heating_vapour_kj",
		"release_cost_kj", "deposited_increment_kj", "physical_dt_s"]:
		_expect(_n(_d(idle, "step"), key) == 0.0, "a no-op reports zero " + key)
	_refused(owner, owner.commit_step(_request([1.0, 0.0, 0.0, 0.0, 500.0]), 1), state, "a no-op still validates its emission temperature")
	var still: Dictionary = owner.preview_step(_request([1.0, 0.5, 50.0, 2.0, 400.0]))
	_expect(_bits(_d(still, "candidate")) == _bits(state), "the preview of a step of zero duration proposes the confirmed root, bit for bit")
	# The finite accumulators equal the sum of the step accounts.
	var runner: RefCounted = _start(_parts("main"))
	var sums: Dictionary = {}
	for row: Dictionary in EXPECTED["sequences"]["main"]["steps"]:
		var result: Dictionary = runner.commit_step(_request(row["request"]), _generation(runner))
		if result.get("valid", false) == true and result.get("no_op") == false:
			for key: String in _d(runner.snapshot(), "totals"):
				var name: String = "accepted_oxidation_kg" if key == "oxidized_fuel_kg" else key
				sums[key] = float(sums.get(key, 0.0)) + _n(_d(result, "step"), name)
	for key: String in sums:
		_energy(_n(_d(runner.snapshot(), "totals"), key), sums[key], "cumulative " + key + " is the sum of the steps")
	_expect(sums.size() == 11, "every cumulative account is covered")
	_expect(_generation(runner) == 4, "four steps of positive duration, four generations")


# --- K14: what is real, what is declared and what is synthetic -----------------

func _labels() -> void:
	var unborn: Dictionary = _report_of(Owner.new())
	_expect(unborn.get("initialized") == false, "report of an empty owner")
	var owner: RefCounted = _start(_parts("main"))
	_play("main", owner, 0, 2, false)
	for shown: Dictionary in [unborn, _report_of(owner), _d(owner.preview_step(_request([3.0, 0.0, 0.0, 0.0, 371.0])), "report"),
		_d(owner.preview_step(_request([3.0, 0.0, 0.0, 0.0, 500.0])), "report"),
		_d(owner.commit_step(_request([2.0, 0.0, 0.0, 0.0, 371.0]), 2), "report"),
		_d(owner.restore(owner.snapshot(), 2), "report"), _d(owner.restore({}, 3), "report")]:
		for key: String in APPROVALS:
			_expect(shown.get(key, true) == false, key + " stays false")
		_expect(shown.get("scope") == "isolated_real_property_composition_prescribed_release_synthetic_budget_not_fire_validation", "scope of the composition")
		_expect(shown.get("controller_version") == "prescribed_real_sensible_phase_controller_v1", "owner version")
		_expect(shown.get("fingerprint_scope") == "context_content_binding_not_signature_or_history_proof", "the identity is not presented as a signature")
		var composition: Dictionary = _d(shown, "composition")
		_expect(composition.get("property_evidence") == "real_limited_primary_source_property", "properties: real with limits")
		_expect(composition.get("chemistry_and_latent_heat") == "declared_prototype_reference_nominal_CHO_not_heptane_calibration", "chemistry: declared prototype")
		_expect(composition.get("release_program") == "prescribed_input_not_predicted_evaporation", "release: prescribed")
		_expect(composition.get("heating") == "prescribed_input_per_step", "heating: prescribed")
		_expect(composition.get("thermal_budget") == "synthetic_independent_initial_budget", "budget: synthetic")
		_expect(composition.get("mass_bases_reconciled") == false, "the two mass bases are not reconciled")
		_expect(composition.get("total_uncertainty_quantified") == false, "no total uncertainty is claimed")
		_expect(composition.get("profiles_molar_mass_role") == "unit_conversion_of_the_source_heat_capacity", "role of the molar mass")
		_expect(composition.get("atom_mass_basis_role") == "stoichiometry_of_the_declared_prototype", "role of the atom basis")
	# The declared and synthetic inputs cannot arrive under a better name.
	for kind: Variant in ["measured_heat_flux", "real_independent_budget", "", 1, null, true]:
		var relabelled: Dictionary = _context(_parts("main"))
		relabelled["seed"]["energy_boundary_kind"] = kind
		var refused: RefCounted = Owner.new()
		_expect(refused.initialize(relabelled).get("valid", true) == false and refused.snapshot().is_empty(),
			"a budget labelled " + str(kind) + " is refused")
	for change: Array in [["status", "measured_emission"], ["status", "predicted_evaporation"],
		["rule", "measured_component"], ["modeled_component_id", "n-octane"], ["input_quantity", "measured_reservoir_depletion"]]:
		var relabelled: Dictionary = _context(_parts("main"))
		relabelled["attribution"][change[0]] = change[1]
		var refused: RefCounted = Owner.new()
		_expect(refused.initialize(relabelled).get("valid", true) == false and refused.snapshot().is_empty(),
			"an emission with " + str(change[0]) + " " + str(change[1]) + " is refused")
	var report: Dictionary = _report_of(owner)
	var confirmed: Dictionary = _d(report, "composition")
	_expect(report.get("energy_boundary_kind") == "synthetic_independent_initial_budget", "the budget is not relabelled as measured")
	_expect(_d(report, "attribution").get("status") == "synthetic_declared_emission", "the emission stays a declared input")
	_expect(confirmed.get("atom_mass_basis") == "nominal_C12_H1_O16", "atom basis of the prototype")
	_expect("not a heptane calibration" in str(confirmed.get("reference_material_provenance")), "chemistry provenance says what it is not")
	_expect("not a measured" in str(confirmed.get("thermal_budget_provenance")), "budget provenance says what it is not")
	_expect("not a measured or predicted evaporation" in str(confirmed.get("release_program_provenance")), "program provenance says what it is not")
	var masses: Array = EXPECTED.get("molar_mass_g_mol", [NAN, NAN])
	var index: int = 0
	for phase: String in ["liquid", "vapour"]:
		var evidence: Dictionary = _d(confirmed, phase)
		_expect(evidence.get("molar_mass_g_mol") == masses[index], phase + " keeps the molar mass of its source")
		_expect(evidence.get("molar_mass_g_mol") != EXPECTED.get("nominal_molar_mass_g_mol"), phase + " molar mass is not the nominal one")
		_expect(evidence.get("temperature_inferred") == false, phase + " temperature is not inferred from enthalpy")
		_expect(evidence.get("approved_profile") == true, phase + " evidence comes from a profile the adapter approves")
		_expect(evidence.get("present") == true and not evidence.get("evidence_kinds", []).is_empty(), phase + " evidence classes reach the report")
		_expect(typeof(evidence.get("provenance")) == TYPE_STRING, phase + " provenance reaches the report")
		var declared: Dictionary = _d(evidence, "declared_errors")
		var approved: Dictionary = _approved(LIQUID if phase == "liquid" else GAS)["declared_errors"]
		_expect(_bits(declared) == _bits(approved), phase + " declared errors are propagated unchanged")
		var absent: int = 0
		for key: String in declared:
			if declared[key] == null:
				absent += 1
		_expect(absent > 0, phase + " keeps its absent uncertainties as null")
		_expect(not evidence.has("total_uncertainty") and not evidence.has("temperature_k"), phase + " invents no figure")
		index += 1
	var empty: RefCounted = _start(_parts("main"))
	var vapour: Dictionary = _d(_d(_report_of(empty), "composition"), "vapour")
	_expect(vapour.get("present") == false and vapour.get("evidence_kinds") == [], "an absent phase claims no evidence")
	_expect(not vapour.has("specific_sensible_enthalpy_kj_kg"), "an absent phase has no specific enthalpy")


# --- helpers -------------------------------------------------------------------

func _parts(name: String) -> Dictionary:
	return _d(_d(_d(EXPECTED, "sequences"), name), "context").duplicate(true)


func _row(name: String, index: int) -> Dictionary:
	return EXPECTED["sequences"][name]["steps"][index]


func _approved(schema: String) -> Dictionary:
	return _d(Real.approved_profile(schema), "candidate")


func _context(parts: Dictionary) -> Dictionary:
	var context: Dictionary = parts.duplicate(true)
	if typeof(context.get("material")) == TYPE_DICTIONARY:
		context["material"]["liquid_profile"] = _approved(LIQUID)
		context["material"]["vapour_profile"] = _approved(GAS)
	return context


func _request(row: Array) -> Dictionary:
	return {"schema": "g3_prescribed_real_sensible_request_v1", "end_time_s": row[0], "oxidation_kg": row[1],
		"heat_liquid_kj": row[2], "heat_vapour_kj": row[3], "emitted_vapour_temperature_k": row[4]}


func _state(initial: float, liquid: float, vapour: float, oxygen: float, budget: float, deposited: float,
	liquid_sensible: float, vapour_sensible: float) -> Dictionary:
	return {"schema": "g3_phase_real_sensible_state_v1", "component_id": "n-heptane",
		"initial_fuel_mass_kg": initial, "liquid_fuel_kg": liquid, "vapour_fuel_kg": vapour, "o2_kg": oxygen,
		"thermal_budget_kj": budget, "deposited_heat_kj": deposited,
		"liquid_sensible_kj": liquid_sensible, "vapour_sensible_kj": vapour_sensible}


func _start(parts: Dictionary) -> RefCounted:
	var owner: RefCounted = Owner.new()
	_valid(owner.initialize(_context(parts)), "initialize")
	return owner


## Snapshot of a fresh owner after the first `count` steps of a sequence.
func _final(name: String, count: int) -> Dictionary:
	var owner: RefCounted = _start(_parts(name))
	_play(name, owner, 0, count, false)
	return owner.snapshot()


## The report of the confirmed state, read through the public surface.
func _report_of(owner: RefCounted) -> Dictionary:
	var time: float = _n(owner.snapshot(), "physical_time_s")
	return _d(owner.preview_step(_request([0.0 if is_nan(time) else time, 0.0, 0.0, 0.0, 298.15])), "report")


func _generation(owner: RefCounted) -> int:
	var value: Variant = owner.snapshot().get("generation")
	return value if typeof(value) == TYPE_INT else -1


func _synthetic_profile(phase: String) -> Dictionary:
	return {"schema": "g3_synthetic_isobaric_cp_v1", "component_id": "n-heptane",
		"phase": phase, "caloric_model": "declared_liquid" if phase == "liquid" else "ideal_gas",
		"pressure_path": "constant_pressure", "reference_temperature_k": 298.15,
		"reference_pressure_pa": 100000.0, "temperature_scale": "synthetic_kelvin",
		"quantity": "isobaric_specific_heat", "quantity_unit": "kJ/(kg*K)",
		"interpolation": "piecewise_linear", "calibration_status": "synthetic_not_material_calibration",
		"provenance": "synthetic: separation control", "samples": [
			{"temperature_k": 273.15, "cp_kj_kg_k": 2.0 if phase == "liquid" else 1.0},
			{"temperature_k": 498.15, "cp_kj_kg_k": 2.0 if phase == "liquid" else 1.0}]}


func _synthetic_context() -> Dictionary:
	var context: Dictionary = _parts("main")
	context["schema"] = "g3_prescribed_sensible_context_v1"
	context["seed"]["schema"] = "g3_prescribed_sensible_seed_v1"
	context["material"]["schema"] = "g3_phase_sensible_material_v1"
	context["material"]["liquid_profile"] = _synthetic_profile("liquid")
	context["material"]["vapour_profile"] = _synthetic_profile("gas")
	return context


func _leaves(value: Variant, path: Array, out: Array) -> void:
	if typeof(value) == TYPE_DICTIONARY:
		for key: Variant in value:
			_leaves(value[key], path + [key], out)
	elif typeof(value) == TYPE_ARRAY:
		for index: int in range(value.size()):
			_leaves(value[index], path + [index], out)
	else:
		out.append(path)


func _at(value: Variant, path: Array) -> Variant:
	var holder: Variant = value
	for key: Variant in path:
		holder = holder[key]
	return holder


## A leaf as text that loses nothing: the eight bytes of a number, never its decimals.
func _leaf_text(value: Variant) -> Array:
	match typeof(value):
		TYPE_FLOAT:
			return ["f64", PackedFloat64Array([value]).to_byte_array().hex_encode()]
		TYPE_STRING:
			return ["text", value]
		TYPE_BOOL:
			return ["bool", "true" if value else "false"]
		TYPE_NIL:
			return ["null", ""]
	return ["unsupported", str(typeof(value))]


## Writes into a copy only where the section exists: a broken mutant may hand back {}.
func _put(target: Dictionary, section: String, key: Variant, value: Variant) -> void:
	if section == "":
		target[key] = value
	elif typeof(target.get(section)) == TYPE_DICTIONARY:
		target[section][key] = value


func _d(source: Variant, key: Variant) -> Dictionary:
	if typeof(source) == TYPE_DICTIONARY and typeof(source.get(key)) == TYPE_DICTIONARY:
		return source[key]
	return {}


func _n(source: Variant, key: Variant) -> float:
	if typeof(source) != TYPE_DICTIONARY:
		return NAN
	var value: Variant = source.get(key)
	return float(value) if typeof(value) in [TYPE_INT, TYPE_FLOAT] else NAN


func _kinds(evidence: Dictionary) -> Array:
	var kinds: Array = []
	var tiers: Variant = evidence.get("evidence_tiers")
	if typeof(tiers) == TYPE_ARRAY:
		for tier: Variant in tiers:
			kinds.append(tier.get("evidence_kind") if typeof(tier) == TYPE_DICTIONARY else null)
	return kinds


func _bits(value: Variant) -> PackedByteArray:
	return var_to_bytes(value)


func _observe(key: String, value: float) -> void:
	# JSON has no NaN: a broken mutant must still print a parseable report.
	_observations[key] = null if is_nan(value) or is_inf(value) else value


func _valid(result: Variant, label: String) -> void:
	var accepted: bool = typeof(result) == TYPE_DICTIONARY and typeof(result.get("valid")) == TYPE_BOOL and result["valid"]
	_expect(accepted, label + " " + (str(result.get("errors")) if typeof(result) == TYPE_DICTIONARY else "no result"))


func _refuses(result: Variant, label: String) -> void:
	var refused: bool = typeof(result) == TYPE_DICTIONARY and typeof(result.get("valid")) == TYPE_BOOL and not result["valid"]
	refused = refused and typeof(result.get("errors")) == TYPE_ARRAY and not result["errors"].is_empty()
	refused = refused and typeof(result.get("candidate")) == TYPE_DICTIONARY and result["candidate"].is_empty()
	_expect(refused, label)


## An explicit, explained refusal that wrote nothing and approves nothing.
func _refused(owner: RefCounted, result: Variant, before: Dictionary, label: String) -> void:
	_refuses(result, label + " is refused")
	_expect(_bits(owner.snapshot()) == _bits(before), label + " writes nothing")
	var report: Dictionary = _d(result, "report")
	for key: String in APPROVALS:
		_expect(report.get(key, true) == false, label + " approves nothing")


## Oracle comparison: relative, with a floor that follows the mass of the case.
func _close(actual: float, expected: Variant, scale: float, label: String) -> void:
	var wanted: float = float(expected) if typeof(expected) in [TYPE_INT, TYPE_FLOAT] else NAN
	_expect(not is_nan(actual) and not is_inf(actual) and not is_nan(wanted)
		and absf(actual - wanted) <= 1.0e-12 * scale + 1.0e-12 * maxf(absf(actual), absf(wanted)),
		label + " observed=" + str(actual) + " expected=" + str(wanted))


## Balance comparison at the tolerance the ledger itself declares.
func _energy(a: float, b: float, label: String) -> void:
	_expect(not is_nan(a) and not is_nan(b) and not is_inf(a) and not is_inf(b)
		and absf(a - b) <= 1.0e-9 + 1.0e-12 * maxf(absf(a), absf(b)), label + " " + str(a) + " vs " + str(b))


func _expect(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failed = true
		if _failures.size() < 60:
			_failures.append(label)

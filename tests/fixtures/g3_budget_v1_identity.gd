extends SceneTree

const Budget = preload("res://sim/fire/FuelMassBudgetModel.gd")


func _initialize() -> void:
	var traces: Array = []
	for mode in ["prescribed_mass_transfer", "thermal_budgeted"]:
		for fractions in [{"C": 0.75, "H": 0.25, "O": 0.0}, {"C": 0.5, "H": 0.06, "O": 0.44}]:
			for oxygen in [0.0, 0.1, 10.0]:
				for dt in [0.0, 0.1, 1.0]:
					for release in [0.0, 0.1, 5.0]:
						for oxidation in [0.0, 0.05, 5.0]:
							var s: Dictionary = {"initial_fuel_mass_kg": 1.0, "solid_fuel_kg": 0.8,
								"released_fuel_kg": 0.2, "o2_kg": oxygen}
							var r: Dictionary = {"dt_s": dt, "release_kg": release, "oxidation_kg": oxidation, "release_mode": mode}
							var m: Dictionary = {"mass_fractions": fractions, "chemical_heat_kj_per_kg": 20000.0,
								"chemical_energy_basis": "complete_oxidation_net", "provenance": "synthetic v1 identity"}
							if mode == "thermal_budgeted":
								r["release_heat_budget_kj"] = 50.0
								m["heat_of_gasification_kj_kg"] = 1000.0
							traces.append(Budget.propose(s, r, m))
							for family in ["state", "request", "material"]:
								var a: Dictionary = s.duplicate(true)
								var b: Dictionary = r.duplicate(true)
								var c: Dictionary = m.duplicate(true)
								var target: Dictionary = a if family == "state" else (b if family == "request" else c)
								target["fuel_energy_MJ"] = 1.0
								traces.append(Budget.propose(a, b, c))
	traces.append(Budget.propose(null, null, null))
	traces.append(Budget.propose({}, {}, {}))
	print("G3_BUDGET_V1_IDENTITY " + JSON.stringify(traces, "", true, true))
	quit(0)

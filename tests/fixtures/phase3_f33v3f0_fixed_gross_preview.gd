extends SceneTree

const SystemScript = preload("res://sim/core/Phase3ZoneMassSystem.gd")


func _init() -> void:
	var system = SystemScript.new()
	var opening: Array = [
		_route("open-a", "canonical_interior_opening", 0, 1, 8.0, 800.0),
		_route("open-b", "canonical_interior_opening", 1, 0, 8.0, 80.0),
	]
	var pressure: Array = [
		_route("pressure-a", "canonical_interior_pressure", 0, 1, 2.0, 200.0),
	]
	var preview: Dictionary = system.preview_fixed_gross_interior_pressure_skew(
		opening, pressure
	)
	_assert(bool(preview.get("valid", false)), "preview valid")
	_close(float(preview["opening_gross_mass_kg"]), 16.0, "opening gross")
	_close(float(preview["preview_gross_mass_kg"]), 16.0, "fixed gross")
	_close(float(preview["accepted_pressure_net_mass_kg"]), 2.0, "net pressure")
	var connection: Dictionary = preview["connections"][0]
	_close(float(connection["preview_low_to_high_kg"]), 9.0, "out skew")
	_close(float(connection["preview_high_to_low_kg"]), 7.0, "in skew")
	_close(float(preview["opening_net_enthalpy_kj"]), 720.0, "opening energy")
	_close(float(preview["preview_net_enthalpy_kj"]), 830.0, "preview energy")
	_close(float(preview["mass_residual_kg"]), 0.0, "mass closure")
	_close(float(preview["energy_residual_kj"]), 0.0, "energy closure")
	_close(float(preview["o2_residual_kg"]), 0.0, "o2 closure")
	_close(float(preview["species_residual_kg"]), 0.0, "species closure")
	var routes: Array = preview["routes"]
	_close(float(routes[0]["o2_kg"]), 0.9, "out O2 scaled")
	_close(float(routes[1]["o2_kg"]), 0.7, "in O2 scaled")
	_close(float(routes[0]["species_kg"]["co2"]), 0.09, "out species scaled")
	_close(float(routes[1]["species_kg"]["co2"]), 0.07, "in species scaled")

	var capped: Dictionary = system.preview_fixed_gross_interior_pressure_skew(
		opening,
		[_route("pressure-cap", "canonical_interior_pressure", 0, 1, 30.0, 3000.0)]
	)
	_assert(bool(capped.get("valid", false)), "capped preview valid")
	_close(float(capped["cap_count"]), 1.0, "cap count")
	_close(float(capped["accepted_pressure_net_mass_kg"]), 16.0, "capped net")
	_close(float(capped["preview_gross_mass_kg"]), 16.0, "capped gross")
	print("PHASE3_F33V3F0_FIXED_GROSS_PREVIEW_PASS")
	quit(0)


func _route(
		route_id: String,
		cause: String,
		source_id: int,
		destination_id: int,
		mass_kg: float,
		energy_kj: float
	) -> Dictionary:
	var route: Dictionary = SystemScript.new().make_atomic_route(
		route_id,
		cause,
		source_id,
		destination_id,
		"upper",
		"upper",
		mass_kg,
		energy_kj,
		0.8,
		{"co2": 0.08}
	)
	route["connection_id"] = "opening:0"
	route["opening_id"] = 0
	return route


func _close(actual: float, expected: float, label: String) -> void:
	if absf(actual - expected) > 1.0e-9:
		push_error("%s: got %.12f expected %.12f" % [label, actual, expected])
		quit(1)


func _assert(condition: bool, label: String) -> void:
	if not condition:
		push_error(label)
		quit(1)

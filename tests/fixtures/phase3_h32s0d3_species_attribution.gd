extends SceneTree

## H3.2-S0d3 fixture: passive measurement of the aggregate species/O2 clamp.
##
## The component only measures. It never distributes a clamped deficit between
## owners, never promotes a request to an acceptance and never invents a zone.

const BuildingModelScript = preload("res://sim/BuildingModel.gd")
const GasExchangeSystemScript = preload("res://sim/core/GasExchangeSystem.gd")
const OpeningModelScript = preload("res://sim/building/OpeningModel.gd")
const RoomModelScript = preload("res://sim/building/RoomModel.gd")
const SmokeModelScript = preload("res://sim/smoke/SmokeModel.gd")
const ThermalSystemScript = preload("res://sim/core/ThermalSystem.gd")

const EPS: float = 1.0e-12

var _failed: bool = false


func _init() -> void:
	_test_default_off_records_nothing()
	_test_non_binding_clamp_accepts_the_request()
	_test_binding_clamp_is_visible_and_not_distributed()
	_test_o2_upper_clamp_is_measured_separately()
	_test_zone_identity_is_honest()
	_test_real_step_smoke_is_measured()
	_test_zonal_guard_detects_upper_over_bulk()
	_test_zonal_guard_is_off_by_default()
	_test_export_is_pure_and_deterministic()
	if _failed:
		quit(1)
		return
	print("PHASE3_H32S0D3_SPECIES_ATTRIBUTION_PASS")
	quit(0)


func _test_default_off_records_nothing() -> void:
	var gas = GasExchangeSystemScript.new()
	_expect(
		not gas.phase3_species_attribution_diagnostics_enabled,
		"diagnostics flag defaults false"
	)
	gas._record_species_attribution("co", 1.0, -5.0)
	gas._record_species_attribution_o2(0.2, 0.9, 60.0, 40.0)
	_expect(
		gas.get_phase3_species_attribution_summary().is_empty(),
		"OFF records nothing"
	)


func _test_non_binding_clamp_accepts_the_request() -> void:
	## Case A: the clamp does not bind, so the accepted delta equals the
	## requested delta exactly and every owner keeps its own contribution.
	var gas = _gas()
	gas._record_species_attribution("co", 10.0, -2.5)
	gas._record_species_attribution("co", 7.5, 1.5)
	var entry: Dictionary = gas.get_phase3_species_attribution_summary()["co"]
	_expect(int(entry["applications"]) == 2, "two applications")
	_expect(int(entry["clamp_bound_count"]) == 0, "clamp did not bind")
	_expect(int(entry["negative_request_count"]) == 1, "one negative request")
	_expect(int(entry["positive_request_count"]) == 1, "one positive request")
	_expect(
		absf(float(entry["requested_kg_total"]) - float(entry["accepted_kg_total"])) <= EPS,
		"accepted equals requested when the clamp is slack"
	)
	_expect(float(entry["max_clamp_deficit_kg"]) == 0.0, "no deficit")


func _test_binding_clamp_is_visible_and_not_distributed() -> void:
	## Case C: the clamp binds. The deficit must stay visible as a single
	## aggregate number; the component must not attribute it to any owner.
	var gas = _gas()
	gas._record_species_attribution("hcl", 1.0, -4.0)
	var entry: Dictionary = gas.get_phase3_species_attribution_summary()["hcl"]
	_expect(int(entry["clamp_bound_count"]) == 1, "clamp bound once")
	_expect(
		absf(float(entry["max_clamp_deficit_kg"]) - 3.0) <= 1.0e-9,
		"deficit is the exact shortfall"
	)
	_expect(
		absf(float(entry["requested_kg_total"]) + 4.0) <= 1.0e-9,
		"requested is preserved verbatim"
	)
	_expect(
		absf(float(entry["accepted_kg_total"]) + 1.0) <= 1.0e-9,
		"accepted is the stock actually removed"
	)
	_expect(
		float(entry["accepted_kg_total"]) > float(entry["requested_kg_total"]),
		"accepted differs from requested when the clamp bites"
	)
	# No per-owner field exists at all: indeterminacy cannot be papered over.
	_expect(not entry.has("owner_share_kg"), "no invented per-owner share")
	_expect(not entry.has("proportional_share_kg"), "no proportional split")


func _test_o2_upper_clamp_is_measured_separately() -> void:
	var gas = _gas()
	# Below zero: low bound.
	gas._record_species_attribution_o2(0.01, -0.02, 60.0, -1.8)
	# Above nominal: high bound.
	gas._record_species_attribution_o2(0.20, 0.30, 60.0, 6.0)
	var entry: Dictionary = gas.get_phase3_species_attribution_summary()["o2"]
	_expect(int(entry["applications"]) == 2, "two O2 applications")
	_expect(int(entry["clamp_bound_count"]) == 1, "one low-bound clamp")
	_expect(int(entry["clamp_high_bound_count"]) == 1, "one high-bound clamp")
	_expect(float(entry["max_clamp_excess_kg"]) > 0.0, "excess above nominal is visible")
	_expect(String(entry["zone_identity"]) == "bulk_only", "O2 has no zone identity")


func _test_zone_identity_is_honest() -> void:
	var gas = _gas()
	for species in ["o2", "smoke", "hcl", "acrolein", "formaldehyde"]:
		gas._record_species_attribution(species, 1.0, 0.1)
	for species in ["co", "co2", "hcn"]:
		gas._record_species_attribution(species, 1.0, 0.1)
	for species in ["co_upper", "co2_upper", "hcn_upper"]:
		gas._record_species_attribution(species, 1.0, 0.1)
	var summary: Dictionary = gas.get_phase3_species_attribution_summary()
	for species in ["smoke", "hcl", "acrolein", "formaldehyde"]:
		_expect(
			String(summary[species]["zone_identity"]) == "bulk_only",
			"%s is bulk only" % species
		)
	for species in ["co", "co2", "hcn"]:
		_expect(
			String(summary[species]["zone_identity"]) == "bulk_and_upper",
			"%s carries an upper split" % species
		)
	for species in ["co_upper", "co2_upper", "hcn_upper"]:
		_expect(
			String(summary[species]["zone_identity"]) == "upper_zone",
			"%s is the upper accumulator" % species
		)


func _test_real_step_smoke_is_measured() -> void:
	var building = BuildingModelScript.new()
	building.outside_temp_c = 20.0
	building.outside_o2 = 0.209
	var source = _room(0)
	source.smoke_kg = 20.0
	source.co_kg = 0.5
	source.co_upper_kg = 0.5
	source.temp_upper_c = 300.0
	var target = _room(1)
	building.rooms = {0: source, 1: target}
	var door = OpeningModelScript.new(0, 1, OpeningModelScript.Type.DOOR, 0.9, 2.0, 1.0, 0.0)
	door.opening_index = 0
	door.open_fraction_smooth = 1.0
	building.openings = [door]

	var thermal = ThermalSystemScript.new()
	var smoke_model = SmokeModelScript.new()
	thermal.set_references(building, smoke_model)
	var gas = _gas()
	gas.step_smoke(building, smoke_model, 1.0, {
		"remove_upper_layer_fraction_callable": Callable(
			thermal, "remove_upper_layer_fraction"
		),
		"compute_interroom_transfer_temp_callable": Callable(
			thermal, "compute_interroom_transfer_temp_c"
		),
		"opening_flow_cache": {},
	})
	var summary: Dictionary = gas.get_phase3_species_attribution_summary()
	_expect(summary.has("co"), "real step measured CO")
	_expect(summary.has("o2"), "real step measured O2")
	_expect(int(summary["co"]["applications"]) == 2, "one application per room")
	for species in summary.keys():
		var entry: Dictionary = summary[species]
		_expect(
			float(entry["max_clamp_deficit_kg"]) >= 0.0,
			"deficit is never negative for %s" % species
		)
	building.free()


func _test_zonal_guard_detects_upper_over_bulk() -> void:
	## H3.2-S0d4: `lower = bulk - upper` only means something while
	## `upper <= bulk`. When it is violated the legacy clamp rewrites the split
	## with no owner, so the zonal attribution of that step is not
	## reconstructible. The guard must see it, not repair it.
	var gas = _gas()
	gas._record_zonal_guard("co", 1.0, 0.4)
	gas._record_zonal_guard("co", 0.3, 0.5)
	gas._record_zonal_guard("co", 0.2, 0.9)
	var entry: Dictionary = gas.get_phase3_species_attribution_summary()["co"]
	_expect(int(entry["zonal_guard_applications"]) == 3, "three guard applications")
	_expect(
		int(entry["zonal_guard_upper_over_bulk_count"]) == 2,
		"two upper-over-bulk violations"
	)
	_expect(
		absf(float(entry["zonal_guard_max_excess_kg"]) - 0.7) <= 1.0e-9,
		"max excess is the worst violation"
	)
	_expect(
		int(entry["zonal_guard_upper_negative_count"]) == 0,
		"no negative upper stock"
	)
	# The guard only observes: it must not expose a repaired or shared split.
	_expect(not entry.has("zonal_guard_repaired_kg"), "guard never repairs")
	_expect(not entry.has("zonal_owner_share_kg"), "guard never attributes")


func _test_zonal_guard_is_off_by_default() -> void:
	var gas = GasExchangeSystemScript.new()
	gas._record_zonal_guard("co", 0.1, 0.9)
	_expect(
		gas.get_phase3_species_attribution_summary().is_empty(),
		"zonal guard is silent when OFF"
	)


func _test_export_is_pure_and_deterministic() -> void:
	var gas = _gas()
	gas._record_species_attribution("co2", 5.0, -1.0)
	var first: String = JSON.stringify(gas.get_phase3_species_attribution_summary())
	var mutated: Dictionary = gas.get_phase3_species_attribution_summary()
	mutated.clear()
	var second: String = JSON.stringify(gas.get_phase3_species_attribution_summary())
	_expect(first == second, "export is pure")
	var gas_b = _gas()
	gas_b._record_species_attribution("co2", 5.0, -1.0)
	_expect(
		JSON.stringify(gas_b.get_phase3_species_attribution_summary()) == first,
		"export is deterministic"
	)


func _gas():
	var gas = GasExchangeSystemScript.new()
	gas.phase3_species_attribution_diagnostics_enabled = true
	return gas


func _room(room_id: int):
	var room = RoomModelScript.new()
	room.id = room_id
	room.width_m = 5.0
	room.length_m = 4.0
	room.height_m = 2.5
	room.thermal_layer_m = 1.2
	room.temp_upper_c = 60.0
	room.temp_lower_c = 20.0
	room.upper_gas_kg = 3.0
	room.lower_gas_kg = 50.0
	room.upper_energy_kj = 200.0
	room.lower_energy_kj = 10.0
	room.o2 = 0.209
	return room


func _expect(condition: bool, label: String) -> void:
	if condition:
		return
	_failed = true
	push_error("H3.2-S0d3 ASSERTION FAILED: %s" % label)

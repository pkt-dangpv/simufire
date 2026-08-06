extends SceneTree

## H3.2-S0d5d fixture: diagnostic ownership of the species clamps.
##
## The species clamps rewrite stocks with no physical donor. Until now only the
## `upper <= bulk` clamp of the room loop was observed, and only as a count: the
## corrected mass was never measured, and the second application site -- parcel
## delivery -- was never observed at all. This fixture pins the diagnostic
## contract: the correction is measured, classified `numerical_correction`,
## separated by family and by site, and it changes no state. The clamp itself is
## neither removed nor relaxed.

const BuildingModelScript = preload("res://sim/BuildingModel.gd")
const GasExchangeSystemScript = preload("res://sim/core/GasExchangeSystem.gd")
const Phase3PhysicalOwnerLedgerScript = preload("res://sim/core/Phase3PhysicalOwnerLedger.gd")
const RoomModelScript = preload("res://sim/building/RoomModel.gd")
const SmokeModelScript = preload("res://sim/smoke/SmokeModel.gd")
const ThermalSystemScript = preload("res://sim/core/ThermalSystem.gd")

const EPS: float = 1.0e-12

var _failed: bool = false


func _init() -> void:
	_test_off_records_nothing()
	_test_correction_is_classified_numerical_correction()
	_test_families_are_counted_separately()
	_test_sites_are_counted_separately()
	_test_zero_correction_counts_an_application_only()
	_test_upper_le_bulk_correction_is_signed_negative()
	_test_bulk_non_negative_correction_is_signed_positive()
	_test_material_threshold_is_per_species()
	_test_recording_mutates_no_state()
	_test_summary_is_a_copy()
	_test_reset_clears_the_ledger()
	_test_sample_carries_the_full_field_set()
	_test_sample_closes_pre_plus_correction_equals_post()
	_test_sample_records_the_room_and_is_bounded()
	_test_unpaired_species_report_nan_not_zero()
	_test_clamp_is_still_applied()
	if _failed:
		quit(1)
		return
	print("PHASE3_H32S0D5D_CLAMP_OWNERSHIP_PASS")
	quit(0)


func _test_off_records_nothing() -> void:
	var gas = GasExchangeSystemScript.new()
	_expect(
		not gas.phase3_species_attribution_diagnostics_enabled,
		"the reused species diagnostics flag defaults false"
	)
	gas._record_zonal_guard("co", 1.0, 2.0)
	gas._record_species_attribution("co", 1.0, -5.0)
	gas._record_zonal_clamp_correction("co2", 1.0, 2.0, "parcel_delivery")
	_expect(
		gas.get_phase3_clamp_correction_summary().is_empty(),
		"OFF records no clamp correction at any site"
	)


func _test_correction_is_classified_numerical_correction() -> void:
	var gas = _gas_on()
	gas._record_zonal_guard("co", 1.0, 1.5)
	var entry: Dictionary = _entry(gas, "co", "upper_le_bulk", "room_loop")
	_expect(
		String(entry["classification"]) \
				== Phase3PhysicalOwnerLedgerScript.CLASS_NUMERICAL_CORRECTION,
		"a clamp correction is classified numerical_correction"
	)
	# It must be a classification the ledger refuses to treat as a source: a
	# valid event carrying the same mass contributes nothing to the room source.
	var event: Dictionary = Phase3PhysicalOwnerLedgerScript.make_event(
		"gas:000001:species_clamp:r0", "species_clamp",
		Phase3PhysicalOwnerLedgerScript.CLASS_NUMERICAL_CORRECTION, 0,
		Phase3PhysicalOwnerLedgerScript.EXTERIOR_ID,
		Phase3PhysicalOwnerLedgerScript.EXTERIOR_ID,
		"", "", -0.5, 0.0, 0.0, 0.0, 0.0, 0.0
	)
	_expect(
		bool(Phase3PhysicalOwnerLedgerScript.validate_event(event)["valid"]),
		"the clamp event shape is valid for the ledger"
	)
	var source: Dictionary = Phase3PhysicalOwnerLedgerScript.physical_source_for_room(
		[event], 0
	)
	_expect(
		absf(float(source["upper_mass_delta_kg"])) <= EPS \
				and absf(float(source["lower_mass_delta_kg"])) <= EPS \
				and absf(float(source["mass_delta_kg"])) <= EPS,
		"numerical_correction can never feed a physical source"
	)


func _test_families_are_counted_separately() -> void:
	var gas = _gas_on()
	# Family C: upper above bulk.
	gas._record_zonal_guard("co", 1.0, 1.5)
	# Family A: bulk driven negative by the accumulator.
	gas._record_species_attribution("co", 1.0, -3.0)
	# Family B: upper driven negative by the accumulator.
	gas._record_species_attribution("co_upper", 0.5, -2.0)
	var totals: Dictionary = _totals(gas)
	_expect(totals.has("co|upper_le_bulk|room_loop"), "family C has its own key")
	_expect(
		totals.has("co|bulk_non_negative|accumulator_application"),
		"family A has its own key"
	)
	_expect(
		totals.has("co_upper|upper_non_negative|accumulator_application"),
		"family B has its own key"
	)
	_expect(totals.size() == 3, "the three families never merge into one entry")


func _test_sites_are_counted_separately() -> void:
	var gas = _gas_on()
	gas._record_zonal_guard("co", 1.0, 1.5)                              # room loop
	gas._record_zonal_clamp_correction("co", 1.0, 1.9, "parcel_delivery")
	var room_loop: Dictionary = _entry(gas, "co", "upper_le_bulk", "room_loop")
	var parcel: Dictionary = _entry(gas, "co", "upper_le_bulk", "parcel_delivery")
	_expect(int(room_loop["strict_count"]) == 1, "the room loop site keeps its own count")
	_expect(int(parcel["strict_count"]) == 1, "the parcel site keeps its own count")
	_expect(
		absf(float(parcel["corrected_mass_abs_kg"]) - 0.9) <= 1.0e-9,
		"the parcel site measures its own corrected mass"
	)
	# The parcel site must not inflate the guard counters already reported by
	# S0d5a2/S0d5b/S0d5c, which are room-loop observations.
	var attribution: Dictionary = gas.get_phase3_species_attribution_summary()
	_expect(
		int(attribution["co"]["zonal_guard_applications"]) == 1,
		"the parcel site does not touch the zonal guard counters"
	)


func _test_zero_correction_counts_an_application_only() -> void:
	var gas = _gas_on()
	gas._record_zonal_guard("co", 2.0, 1.0)   # upper below bulk: nothing to correct
	var entry: Dictionary = _entry(gas, "co", "upper_le_bulk", "room_loop")
	_expect(int(entry["applications"]) == 1, "a non-binding pass still counts an application")
	_expect(int(entry["strict_count"]) == 0, "a non-binding pass corrects nothing")
	_expect(
		float(entry["corrected_mass_abs_kg"]) == 0.0,
		"a non-binding pass moves no mass"
	)


func _test_upper_le_bulk_correction_is_signed_negative() -> void:
	var gas = _gas_on()
	gas._record_zonal_guard("co2", 1.0, 1.25)
	var entry: Dictionary = _entry(gas, "co2", "upper_le_bulk", "room_loop")
	_expect(
		absf(float(entry["corrected_mass_signed_kg"]) + 0.25) <= 1.0e-12,
		"the zonal clamp removes upper mass, so the signed correction is negative"
	)
	_expect(
		absf(float(entry["max_correction_kg"]) - 0.25) <= 1.0e-12,
		"the peak correction is the excess above bulk"
	)


func _test_bulk_non_negative_correction_is_signed_positive() -> void:
	var gas = _gas_on()
	gas._record_species_attribution("hcn", 1.0, -1.75)
	var entry: Dictionary = _entry(gas, "hcn", "bulk_non_negative", "accumulator_application")
	_expect(
		absf(float(entry["corrected_mass_signed_kg"]) - 0.75) <= 1.0e-12,
		"the non-negative clamp invents mass, so the signed correction is positive"
	)


func _test_material_threshold_is_per_species() -> void:
	var gas = _gas_on()
	gas._record_zonal_guard("co", 1.0, 1.0 + 5.0e-9)
	gas._record_zonal_guard("co2", 1.0, 1.0 + 5.0e-9)
	gas._record_zonal_guard("hcn", 1.0, 1.0 + 5.0e-9)
	gas._record_zonal_guard("smoke", 1.0, 1.0 + 5.0e-9)
	var co: Dictionary = _entry(gas, "co", "upper_le_bulk", "room_loop")
	var co2: Dictionary = _entry(gas, "co2", "upper_le_bulk", "room_loop")
	var hcn: Dictionary = _entry(gas, "hcn", "upper_le_bulk", "room_loop")
	var smoke: Dictionary = _entry(gas, "smoke", "upper_le_bulk", "room_loop")
	_expect(
		absf(float(co["material_epsilon_kg"]) - 1.0e-9) <= 1.0e-18,
		"CO keeps its own derived threshold"
	)
	_expect(
		absf(float(co2["material_epsilon_kg"]) - 1.0e-8) <= 1.0e-18,
		"CO2 keeps its own derived threshold"
	)
	_expect(
		absf(float(hcn["material_epsilon_kg"]) - 1.0e-7) <= 1.0e-18,
		"HCN keeps its own derived threshold"
	)
	_expect(
		float(smoke["material_epsilon_kg"]) == 0.0,
		"a species with no derived threshold reports zero, never an inherited one"
	)
	# Strict and material are always reported together.
	_expect(int(co["strict_count"]) == 1, "CO strict count is reported")
	_expect(int(co["material_count"]) == 1, "5e-9 kg is material for CO")
	_expect(int(co2["strict_count"]) == 1, "CO2 strict count is reported")
	_expect(int(co2["material_count"]) == 0, "5e-9 kg is below the CO2 threshold")
	_expect(int(hcn["strict_count"]) == 1, "HCN strict count is reported")
	_expect(int(hcn["material_count"]) == 0, "5e-9 kg is far below the HCN threshold")


func _test_recording_mutates_no_state() -> void:
	var gas = _gas_on()
	var room = _room(0)
	room.co_kg = 1.0
	room.co_upper_kg = 1.6
	gas._record_zonal_guard("co", room.co_kg, room.co_upper_kg)
	gas._record_zonal_clamp_correction("co", room.co_kg, room.co_upper_kg, "parcel_delivery")
	_expect(absf(room.co_kg - 1.0) <= EPS, "measuring the clamp leaves bulk untouched")
	_expect(
		absf(room.co_upper_kg - 1.6) <= EPS,
		"measuring the clamp leaves upper untouched: it observes, it does not repair"
	)


func _test_summary_is_a_copy() -> void:
	var gas = _gas_on()
	gas._record_zonal_guard("co", 1.0, 1.5)
	var summary: Dictionary = gas.get_phase3_clamp_correction_summary()
	summary["totals"]["co|upper_le_bulk|room_loop"]["strict_count"] = 999
	_expect(
		int(_entry(gas, "co", "upper_le_bulk", "room_loop")["strict_count"]) == 1,
		"the exported summary is a deep copy of the internal ledger"
	)


func _test_reset_clears_the_ledger() -> void:
	var gas = _gas_on()
	gas._record_zonal_guard("co", 1.0, 1.5)
	_expect(
		not gas.get_phase3_clamp_correction_summary().is_empty(),
		"the ledger holds the observation before reset"
	)
	gas.reset()
	_expect(
		gas.get_phase3_clamp_correction_summary().is_empty(),
		"reset clears the clamp ledger, so runs never leak into each other"
	)


func _test_sample_carries_the_full_field_set() -> void:
	var gas = _gas_on()
	var room = _room(3)
	gas._record_zonal_guard("co", 1.0, 1.4, "room_loop", room)
	var samples: Array = _samples(gas)
	_expect(samples.size() == 1, "a binding clamp emits exactly one sample")
	var sample: Dictionary = samples[0]
	for key in [
		"step", "room_id", "species", "clamp_kind", "site", "classification",
		"pre_bulk_kg", "pre_upper_kg", "requested_bulk_kg", "requested_upper_kg",
		"post_bulk_kg", "post_upper_kg", "correction_bulk_kg", "correction_upper_kg",
		"lower_derived_before_kg", "lower_derived_after_kg",
		"strict_bound", "material_bound", "material_epsilon_kg",
		"cause", "writer_before_clamp", "flags",
	]:
		_expect(sample.has(key), "the sample carries %s" % key)
	_expect(
		String(sample["writer_before_clamp"]) == "unknown",
		"an untraced writer is reported unknown, never guessed"
	)
	_expect(
		not bool(sample["flags"]["phase3_co_zonal_transport_consistency_enabled"]),
		"the sample records which experimental flags were active"
	)


func _test_sample_closes_pre_plus_correction_equals_post() -> void:
	var gas = _gas_on()
	var room = _room(0)
	# Family C: the correction is the only term between requested and post.
	gas._record_zonal_guard("co2", 2.0, 2.75, "room_loop", room)
	var c: Dictionary = _samples(gas)[0]
	_expect(
		absf(
			float(c["requested_upper_kg"]) + float(c["correction_upper_kg"])
			- float(c["post_upper_kg"])
		) <= EPS,
		"upper: requested + correction = post"
	)
	_expect(
		absf(float(c["correction_bulk_kg"])) <= EPS,
		"the zonal clamp never corrects bulk"
	)
	_expect(
		absf(float(c["lower_derived_before_kg"]) + 0.75) <= EPS,
		"the derived lower stock before the clamp is reported as it truly is: negative"
	)
	_expect(
		float(c["lower_derived_after_kg"]) == 0.0,
		"the clamp drives the derived lower stock to exactly zero"
	)
	# Family A: same closure on the bulk side.
	var gas_a = _gas_on()
	gas_a._record_species_attribution("hcl", 1.0, -1.5, room)
	var a: Dictionary = _samples(gas_a)[0]
	_expect(
		absf(
			float(a["requested_bulk_kg"]) + float(a["correction_bulk_kg"])
			- float(a["post_bulk_kg"])
		) <= EPS,
		"bulk: requested + correction = post"
	)
	_expect(
		absf(float(a["correction_upper_kg"])) <= EPS,
		"the non-negative bulk clamp never corrects upper"
	)


func _test_sample_records_the_room_and_is_bounded() -> void:
	var gas = _gas_on()
	var room_a = _room(7)
	var room_b = _room(9)
	gas._record_zonal_guard("co", 1.0, 1.2, "room_loop", room_a)
	gas._record_zonal_guard("co", 1.0, 1.2, "room_loop", room_b)
	gas._record_zonal_guard("co", 5.0, 1.0, "room_loop", room_a)   # non-binding
	var entry: Dictionary = _entry(gas, "co", "upper_le_bulk", "room_loop")
	_expect(
		Array(entry["strict_rooms"]).size() == 2,
		"affected rooms are counted once each"
	)
	_expect(
		Array(entry["material_rooms"]).size() == 2,
		"material rooms are tracked apart from strict rooms"
	)
	_expect(_samples(gas).size() == 2, "a non-binding pass emits no sample")
	var summary: Dictionary = gas.get_phase3_clamp_correction_summary()
	_expect(
		int(summary["sample_limit"]) > 0 and int(summary["sample_overflow"]) == 0,
		"the sample list is bounded and reports what it dropped"
	)


func _test_unpaired_species_report_nan_not_zero() -> void:
	var gas = _gas_on()
	var room = _room(0)
	gas._record_species_attribution("smoke", 1.0, -2.0, room)
	var sample: Dictionary = _samples(gas)[0]
	_expect(
		is_nan(float(sample["pre_upper_kg"])),
		"a species with no upper stock reports NAN, not a zero that looks measured"
	)
	_expect(
		absf(float(sample["correction_bulk_kg"]) - 1.0) <= EPS,
		"the bulk correction is still exact for an unpaired species"
	)


func _test_clamp_is_still_applied() -> void:
	# The diagnostic must not relax the invariant it measures: after the room
	# loop runs, upper stays at or below bulk with the flag both off and on.
	for enabled in [false, true]:
		var building = BuildingModelScript.new()
		building.outside_temp_c = 20.0
		building.outside_o2 = 0.209
		var room = _room(0)
		room.co_kg = 1.0
		room.co_upper_kg = 1.9
		room.co2_kg = 2.0
		room.co2_upper_kg = 3.4
		room.hcn_kg = 0.4
		room.hcn_upper_kg = 0.9
		building.rooms = {0: room}
		var thermal = ThermalSystemScript.new()
		var smoke_model = SmokeModelScript.new()
		thermal.set_references(building, smoke_model)
		var gas = GasExchangeSystemScript.new()
		gas.phase3_species_attribution_diagnostics_enabled = enabled
		gas.ach_infiltration = 0.0
		gas.background_species_exchange_kg_s_m2 = 0.0
		gas.step_smoke(building, smoke_model, 1.0, {
			"remove_upper_layer_fraction_callable": Callable(
				thermal, "remove_upper_layer_fraction"
			),
			"compute_interroom_transfer_temp_callable": Callable(
				thermal, "compute_interroom_transfer_temp_c"
			),
			"opening_flow_cache": {},
		})
		_expect(
			room.co_upper_kg <= room.co_kg + EPS,
			"the CO clamp still binds (enabled=%s)" % enabled
		)
		_expect(
			room.co2_upper_kg <= room.co2_kg + EPS,
			"the CO2 clamp still binds (enabled=%s)" % enabled
		)
		_expect(
			room.hcn_upper_kg <= room.hcn_kg + EPS,
			"the HCN clamp still binds (enabled=%s)" % enabled
		)
		building.free()


func _gas_on():
	var gas = GasExchangeSystemScript.new()
	gas.phase3_species_attribution_diagnostics_enabled = true
	return gas


func _totals(gas) -> Dictionary:
	var summary: Dictionary = gas.get_phase3_clamp_correction_summary()
	return summary.get("totals", {})


func _samples(gas) -> Array:
	var summary: Dictionary = gas.get_phase3_clamp_correction_summary()
	return summary.get("samples", [])


func _entry(gas, species: String, kind: String, site: String) -> Dictionary:
	var key: String = "%s|%s|%s" % [species, kind, site]
	var totals: Dictionary = _totals(gas)
	if not totals.has(key):
		_failed = true
		push_error("H3.2-S0d5d ASSERTION FAILED: missing clamp entry %s" % key)
		return {}
	return totals[key]


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
	push_error("H3.2-S0d5d ASSERTION FAILED: %s" % label)

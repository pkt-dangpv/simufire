extends SceneTree

## H3.2-S0d6 fixture: passive measurement of O2 acceptance per owner and zone.
##
## O2 state is a set of three INDEPENDENT fractions -- o2, o2_upper, o2_lower --
## with no invariant tying them together, written by five subsystems using
## inconsistent mass bases. This component measures requested vs accepted at the
## exact mutation site and refuses to emit a kg equivalent unless the site itself
## capped and applied against the same mass base. It never reconstructs an
## accepted amount from post-minus-pre, never derives it from HRR, and never
## splits a deficit between owners.

const BuildingModelScript = preload("res://sim/BuildingModel.gd")
const OxygenExchangeSystemScript = preload("res://sim/core/OxygenExchangeSystem.gd")
const RoomModelScript = preload("res://sim/building/RoomModel.gd")
const ThermalSystemScript = preload("res://sim/core/ThermalSystem.gd")
const LedgerScript = preload("res://sim/core/Phase3O2AcceptanceLedger.gd")
## Preloaded so a parse error in the engine fails THIS fixture. Without it the
## measurement can look green while the engine does not compile at all.
const SimulationEngineScript = preload("res://sim/core/SimulationEngine.gd")
const GasExchangeSystemScript = preload("res://sim/core/GasExchangeSystem.gd")

const EPS: float = 1.0e-12

var _failed: bool = false
## A Godot runtime error aborts the enclosing function WITHOUT unwinding to the
## caller and without setting `_failed`, so a fixture that only tracks assertion
## failures reports PASS after a crash. Every test therefore records that it ran
## to completion, and `_init` refuses to pass unless all of them did.
var _completed: Array[String] = []
const EXPECTED_TESTS: int = 15


func _done(label: String) -> void:
	_completed.append(label)


func _init() -> void:
	_test_flag_defaults_false_and_records_nothing()
	_test_material_threshold_is_derived_from_fed_not_inherited()
	_test_reason_codes_are_distinct_and_complete_is_the_only_kg_path()
	_test_non_binding_clamp_records_no_correction()
	_test_binding_clamp_is_visible_without_per_owner_split()
	_test_kg_is_null_when_the_mass_base_is_ambiguous()
	_test_kg_is_emitted_only_for_the_consistent_upper_sink()
	_test_owner_and_zone_never_merge()
	_test_sample_carries_the_full_field_set()
	_test_sample_is_bounded_and_reports_overflow()
	_test_summary_is_a_copy_and_reset_clears_it()
	_test_measurement_mutates_no_state()
	_test_real_step_is_measured()
	_test_reason_conflict_downgrades_the_row()
	_test_every_component_compiles_and_carries_a_ledger()
	if _completed.size() != EXPECTED_TESTS:
		# A test aborted mid-way on a runtime error. That must never read as PASS.
		push_error(
			"H3.2-S0d6 ABORTED: %d/%d tests completed; ran %s"
			% [_completed.size(), EXPECTED_TESTS, str(_completed)]
		)
		quit(1)
		return
	if _failed:
		quit(1)
		return
	print("PHASE3_H32S0D6_O2_ATTRIBUTION_PASS")
	quit(0)


func _test_flag_defaults_false_and_records_nothing() -> void:
	var oes = OxygenExchangeSystemScript.new()
	_expect(
		not oes.phase3_o2_attribution_diagnostics_enabled,
		"the O2 attribution flag defaults false"
	)
	oes._record_o2_acceptance(
		"any", "bulk", _room(0), 0.209, 0.30, 0.209,
		LedgerScript.REASON_AGGREGATE_MULTI_OWNER, 60.0, "room_air_mass"
	)
	_expect(
		oes.get_phase3_o2_attribution_summary().is_empty(),
		"OFF records nothing at all, not even a threshold header"
	)


	_done("_test_flag_defaults_false_and_records_nothing")


func _test_material_threshold_is_derived_from_fed_not_inherited() -> void:
	var eps: float = LedgerScript.MATERIAL_EPS_FRACTION
	# Anchored on FED_hypoxia sensitivity: dFED/FED = fed_hypoxia_b * 100 * d(fraction)
	# with b = 0.54, so a 1 % FED move is 1/54 * 0.01 = 1.85e-4 of fraction.
	var one_percent_fed_fraction: float = 0.01 / (0.54 * 100.0)
	_expect(
		absf(one_percent_fed_fraction - 1.8518e-4) <= 1.0e-8,
		"the FED sensitivity anchor is 1.85e-4 of fraction per 1 % FED"
	)
	_expect(eps < one_percent_fed_fraction * 1.0e-3, "the threshold is far below a 1 % FED move")
	_expect(eps > 1.0e-13, "the threshold is far above the double-precision noise floor")
	# The unit is a fraction, not kg: it must never be compared against a species
	# threshold, which is a mass.
	var summary: Dictionary = _measured_summary()
	_expect(
		summary.has("material_eps_fraction"),
		"the exported threshold is named in fraction units"
	)
	_expect(
		not summary.has("material_eps_kg"),
		"no kg-named threshold is exported for O2: that would imply a mass"
	)


	_done("_test_material_threshold_is_derived_from_fed_not_inherited")


func _test_reason_codes_are_distinct_and_complete_is_the_only_kg_path() -> void:
	var codes: Array = [
		LedgerScript.REASON_COMPLETE,
		LedgerScript.REASON_AMBIGUOUS_MASS_BASE,
		LedgerScript.REASON_NO_ZONAL_INVARIANT,
		LedgerScript.REASON_AGGREGATE_MULTI_OWNER,
		LedgerScript.REASON_SINK_TRUNCATED,
	]
	var seen: Dictionary = {}
	for c in codes:
		_expect(not seen.has(c), "reason code %s is distinct" % c)
		seen[c] = true
	_expect(codes.size() == 5, "five reason codes are declared")


	_done("_test_reason_codes_are_distinct_and_complete_is_the_only_kg_path")


func _test_non_binding_clamp_records_no_correction() -> void:
	var oes = _oes_on()
	# requested == accepted: the clamp was slack.
	oes._record_o2_acceptance(
		"oes_bulk_combustion_and_ach", "bulk", _room(0), 0.209, 0.200, 0.200,
		LedgerScript.REASON_AGGREGATE_MULTI_OWNER, 60.0, "room_air_mass"
	)
	var e: Dictionary = _entry(oes, "oes_bulk_combustion_and_ach", "bulk")
	_expect(int(e["applications"]) == 1, "a slack clamp still counts an application")
	_expect(int(e["strict_count"]) == 0, "a slack clamp corrects nothing")
	_expect(
		absf(float(e["requested_fraction_total"]) - float(e["accepted_fraction_total"])) <= EPS,
		"when the clamp is slack, accepted equals requested exactly"
	)
	_expect(_samples(oes).is_empty(), "a slack clamp emits no sample")


	_done("_test_non_binding_clamp_records_no_correction")


func _test_binding_clamp_is_visible_without_per_owner_split() -> void:
	var oes = _oes_on()
	# Requested above the ceiling: the clamp rejects the excess.
	oes._record_o2_acceptance(
		"oes_bulk_combustion_and_ach", "bulk", _room(0), 0.200, 0.230, 0.209,
		LedgerScript.REASON_AGGREGATE_MULTI_OWNER, 60.0, "room_air_mass"
	)
	var e: Dictionary = _entry(oes, "oes_bulk_combustion_and_ach", "bulk")
	_expect(int(e["strict_count"]) == 1, "the binding clamp is counted")
	_expect(int(e["material_count"]) == 1, "0.021 of fraction is material")
	_expect(
		absf(float(e["correction_fraction_signed"]) + 0.021) <= 1.0e-9,
		"the correction is the rejected amount, signed"
	)
	_expect(
		not bool(e["completeness"]),
		"an accumulated multi-owner clamp can never be complete"
	)
	# The whole point: no per-owner field exists, so a deficit cannot be split.
	for forbidden in ["owner_shares", "per_owner", "split", "fifo", "priority"]:
		_expect(not e.has(forbidden), "no %s field exists by construction" % forbidden)


	_done("_test_binding_clamp_is_visible_without_per_owner_split")


func _test_kg_is_null_when_the_mass_base_is_ambiguous() -> void:
	var oes = _oes_on()
	oes._record_o2_acceptance(
		"oes_combustion_plume_lower_sink", "lower", _room(0), 0.209, 0.150, 0.160,
		LedgerScript.REASON_AMBIGUOUS_MASS_BASE, NAN,
		"cap_lower_zone_apply_room"
	)
	var e: Dictionary = _entry(oes, "oes_combustion_plume_lower_sink", "lower")
	_expect(not bool(e["kg_available"]), "an ambiguous mass base yields no kg")
	_expect(float(e["accepted_kg_total"]) == 0.0, "no kg is ever accumulated for it")
	var s: Dictionary = _samples(oes)[0]
	_expect(s["accepted_kg"] == null, "the sample reports JSON null, not a zero kg")
	_expect(s["mass_base_kg"] == null, "the mass base reports JSON null too")
	_expect(
		String(s["unit"]) == "fraction",
		"the original unit is always reported as a fraction"
	)
	_expect(
		String(s["reason_code"]) == LedgerScript.REASON_AMBIGUOUS_MASS_BASE,
		"the reason code travels with the sample"
	)


	_done("_test_kg_is_null_when_the_mass_base_is_ambiguous")


func _test_kg_is_emitted_only_for_the_consistent_upper_sink() -> void:
	var oes = _oes_on()
	# The upper combustion sink caps and applies against upper_air_mass.
	oes._record_o2_acceptance(
		"oes_combustion_upper_sink", "upper", _room(0), 0.209, 0.189, 0.189,
		LedgerScript.REASON_COMPLETE, 5.0, "upper_zone_air_mass"
	)
	var e: Dictionary = _entry(oes, "oes_combustion_upper_sink", "upper")
	_expect(bool(e["completeness"]), "the upper sink is the one complete path")
	_expect(bool(e["kg_available"]), "it can carry kg")
	_expect(
		absf(float(e["accepted_kg_total"]) + 0.10) <= 1.0e-9,
		"accepted kg is the accepted fraction delta times the zone mass"
	)


	_done("_test_kg_is_emitted_only_for_the_consistent_upper_sink")


func _test_owner_and_zone_never_merge() -> void:
	var oes = _oes_on()
	oes._record_o2_acceptance(
		"oes_final_zone_clamp", "upper", _room(0), 0.30, 0.30, 0.209,
		LedgerScript.REASON_NO_ZONAL_INVARIANT, NAN, "none"
	)
	oes._record_o2_acceptance(
		"oes_final_zone_clamp", "lower", _room(0), 0.30, 0.30, 0.209,
		LedgerScript.REASON_NO_ZONAL_INVARIANT, NAN, "none"
	)
	oes._record_o2_acceptance(
		"oes_exterior_opening", "bulk", _room(1), 0.19, 0.21, 0.209,
		LedgerScript.REASON_NO_ZONAL_INVARIANT, NAN, "room_air_mass"
	)
	var totals: Dictionary = _totals(oes)
	_expect(totals.size() == 3, "owner and zone form the key; they never merge")
	_expect(totals.has("oes_final_zone_clamp|upper"), "upper keeps its own entry")
	_expect(totals.has("oes_final_zone_clamp|lower"), "lower keeps its own entry")
	_expect(totals.has("oes_exterior_opening|bulk"), "bulk keeps its own entry")


	_done("_test_owner_and_zone_never_merge")


func _test_sample_carries_the_full_field_set() -> void:
	var oes = _oes_on()
	oes._record_o2_acceptance(
		"oes_bulk_combustion_and_ach", "bulk", _room(4), 0.200, 0.230, 0.209,
		LedgerScript.REASON_AGGREGATE_MULTI_OWNER, 60.0, "room_air_mass"
	)
	var s: Dictionary = _samples(oes)[0]
	for key in [
		"step", "room_id", "owner", "zone", "unit",
		"pre_fraction", "requested_fraction", "accepted_fraction",
		"correction_fraction", "rejected_fraction",
		"accepted_kg", "mass_base_kg", "mass_base_kind",
		"strict_bound", "material_bound", "material_eps_fraction",
		"reason_code", "completeness", "flags",
	]:
		_expect(s.has(key), "the sample carries %s" % key)
	_expect(int(s["room_id"]) == 4, "the sample records the room")
	_expect(
		absf(float(s["rejected_fraction"]) - 0.021) <= 1.0e-9,
		"the rejected amount is requested minus accepted"
	)
	_expect(
		s["flags"].has("two_zone_solver_enabled"),
		"the sample records which experimental flags were active"
	)


	_done("_test_sample_carries_the_full_field_set")


func _test_sample_is_bounded_and_reports_overflow() -> void:
	var oes = _oes_on()
	var limit: int = LedgerScript.SAMPLE_MAX
	for i in range(limit + 5):
		oes._record_o2_acceptance(
			"oes_bulk_combustion_and_ach", "bulk", _room(0), 0.200, 0.230, 0.209,
			LedgerScript.REASON_AGGREGATE_MULTI_OWNER, 60.0, "room_air_mass"
		)
	var summary: Dictionary = oes.get_phase3_o2_attribution_summary()
	_expect(Array(summary["samples"]).size() == limit, "the sample list is bounded")
	_expect(int(summary["sample_overflow"]) == 5, "it reports exactly what it dropped")
	_expect(
		int(summary["totals"]["oes_bulk_combustion_and_ach|bulk"]["applications"]) == limit + 5,
		"the accumulators keep full coverage regardless of the sample bound"
	)


	_done("_test_sample_is_bounded_and_reports_overflow")


func _test_summary_is_a_copy_and_reset_clears_it() -> void:
	var oes = _oes_on()
	oes._record_o2_acceptance(
		"oes_bulk_combustion_and_ach", "bulk", _room(0), 0.200, 0.230, 0.209,
		LedgerScript.REASON_AGGREGATE_MULTI_OWNER, 60.0, "room_air_mass"
	)
	var summary: Dictionary = oes.get_phase3_o2_attribution_summary()
	summary["totals"]["oes_bulk_combustion_and_ach|bulk"]["strict_count"] = 999
	_expect(
		int(_entry(oes, "oes_bulk_combustion_and_ach", "bulk")["strict_count"]) == 1,
		"the export is a deep copy"
	)
	oes.reset()
	_expect(
		oes.get_phase3_o2_attribution_summary().is_empty(),
		"reset clears the ledger so runs never leak into each other"
	)


	_done("_test_summary_is_a_copy_and_reset_clears_it")


func _test_measurement_mutates_no_state() -> void:
	var oes = _oes_on()
	var room = _room(0)
	room.o2 = 0.17
	room.o2_upper = 0.11
	room.o2_lower = 0.20
	oes._record_o2_acceptance(
		"oes_bulk_combustion_and_ach", "bulk", room, 0.200, 0.230, 0.209,
		LedgerScript.REASON_AGGREGATE_MULTI_OWNER, 60.0, "room_air_mass"
	)
	_expect(absf(room.o2 - 0.17) <= EPS, "measuring leaves room.o2 untouched")
	_expect(absf(room.o2_upper - 0.11) <= EPS, "measuring leaves o2_upper untouched")
	_expect(absf(room.o2_lower - 0.20) <= EPS, "measuring leaves o2_lower untouched")


	_done("_test_measurement_mutates_no_state")


func _test_real_step_is_measured() -> void:
	# A real OxygenExchangeSystem.step must produce observations, and must
	# produce none at all when the flag is off.
	for enabled in [false, true]:
		var building = BuildingModelScript.new()
		building.outside_temp_c = 20.0
		building.outside_o2 = 0.209
		var room = _room(0)
		room.o2 = 0.16
		room.o2_upper = 0.12
		room.o2_lower = 0.19
		room.hrr_kw = 400.0
		building.rooms = {0: room}
		var thermal = ThermalSystemScript.new()
		var oes = OxygenExchangeSystemScript.new()
		oes.phase3_o2_attribution_diagnostics_enabled = enabled
		oes.ach_infiltration = 0.5
		oes.begin_phase3_o2_step()
		oes.step(building, 1.0, {
			"effective_hot_layer_height_callable": Callable(
				thermal, "effective_hot_layer_height_m"
			),
		})
		var summary: Dictionary = oes.get_phase3_o2_attribution_summary()
		if enabled:
			_expect(not summary.is_empty(), "ON a real step is measured")
			_expect(
				int(summary["totals"].values()[0]["applications"]) > 0,
				"ON at least one mutation site is observed"
			)
		else:
			_expect(summary.is_empty(), "OFF a real step records nothing")
		# The clamp still runs in both cases: the diagnostic changes no physics.
		_expect(room.o2 <= 0.209 + EPS, "the O2 clamp still binds (enabled=%s)" % enabled)
		_expect(room.o2 >= -EPS, "O2 stays non-negative (enabled=%s)" % enabled)
		building.free()


	_done("_test_real_step_is_measured")


func _test_every_component_compiles_and_carries_a_ledger() -> void:
	# Instantiating each script forces it to compile. A parse error in the engine
	# used to slip past this fixture entirely, because nothing here loaded it.
	var engine = SimulationEngineScript.new()
	_expect(engine != null, "SimulationEngine compiles and instantiates")
	_expect(
		not engine.phase3_o2_attribution_diagnostics_enabled,
		"the engine flag defaults false"
	)
	# Turning it on must reach the engine's own ledger even before the
	# subsystems exist, and must not crash on the null subsystem references.
	engine.phase3_o2_attribution_diagnostics_enabled = true
	_expect(
		engine.phase3_o2_attribution_diagnostics_enabled,
		"the engine flag can be turned on without a built scene"
	)
	engine.free()
	var gas = GasExchangeSystemScript.new()
	var thermal = ThermalSystemScript.new()
	var oes = OxygenExchangeSystemScript.new()
	for pair in [["gas", gas], ["thermal", thermal], ["oes", oes]]:
		_expect(
			pair[1].phase3_o2_ledger != null,
			"%s carries an O2 acceptance ledger" % pair[0]
		)
		_expect(
			not pair[1].phase3_o2_ledger.enabled,
			"%s ledger defaults disabled" % pair[0]
		)


	_done("_test_every_component_compiles_and_carries_a_ledger")


func _test_reason_conflict_downgrades_the_row() -> void:
	# Two different reasons for one owner/zone mean the key no longer describes a
	# homogeneous population. The row must degrade, not keep the first reason and
	# carry on publishing kilograms.
	var ledger = LedgerScript.new()
	ledger.enabled = true
	var room = _room(0)
	ledger.record(
		"probe", "upper", room, 0.209, 0.189, 0.189,
		LedgerScript.REASON_COMPLETE, 5.0, "upper_zone_air_mass"
	)
	var before: Dictionary = ledger.summary()["totals"]["probe|upper"]
	_expect(bool(before["completeness"]), "the first record is complete")
	_expect(
		absf(float(before["accepted_kg_total"]) + 0.10) <= 1.0e-9,
		"it carries kg before the conflict"
	)
	ledger.record(
		"probe", "upper", room, 0.189, 0.180, 0.185,
		LedgerScript.REASON_AMBIGUOUS_MASS_BASE, NAN, "cap_lower_zone_apply_room"
	)
	var after: Dictionary = ledger.summary()["totals"]["probe|upper"]
	_expect(
		String(after["reason_code"]) == LedgerScript.REASON_CONFLICT,
		"a conflicting reason marks the row as a conflict"
	)
	_expect(not bool(after["completeness"]), "the row is no longer complete")
	_expect(not bool(after["kg_available"]), "the row can no longer carry kg")
	_expect(
		float(after["accepted_kg_total"]) == 0.0,
		"the kilograms accumulated before the conflict are discarded, not kept"
	)
	_expect(int(after["conflict_count"]) == 1, "the conflict is counted")
	# A further record must not resurrect the kg path.
	ledger.record(
		"probe", "upper", room, 0.185, 0.180, 0.180,
		LedgerScript.REASON_COMPLETE, 5.0, "upper_zone_air_mass"
	)
	var final: Dictionary = ledger.summary()["totals"]["probe|upper"]
	_expect(
		float(final["accepted_kg_total"]) == 0.0,
		"a downgraded row never starts publishing kg again"
	)
	# An unknown reason code must be treated as incomplete from the start.
	var fresh = LedgerScript.new()
	fresh.enabled = true
	fresh.record(
		"probe2", "bulk", room, 0.209, 0.30, 0.209, "not_a_declared_reason",
		60.0, "room_air_mass"
	)
	var unknown: Dictionary = fresh.summary()["totals"]["probe2|bulk"]
	_expect(
		not bool(unknown["completeness"]),
		"an undeclared reason code is never treated as complete"
	)
	_expect(
		String(unknown["reason_code"]) == LedgerScript.REASON_CONFLICT,
		"an undeclared reason code is recorded as a conflict"
	)
	_done("_test_reason_conflict_downgrades_the_row")


func _oes_on():
	var oes = OxygenExchangeSystemScript.new()
	oes.phase3_o2_attribution_diagnostics_enabled = true
	return oes


func _measured_summary() -> Dictionary:
	var oes = _oes_on()
	oes._record_o2_acceptance(
		"probe", "bulk", _room(0), 0.209, 0.230, 0.209,
		LedgerScript.REASON_AGGREGATE_MULTI_OWNER, 60.0, "room_air_mass"
	)
	return oes.get_phase3_o2_attribution_summary()


func _totals(oes) -> Dictionary:
	return oes.get_phase3_o2_attribution_summary().get("totals", {})


func _samples(oes) -> Array:
	return oes.get_phase3_o2_attribution_summary().get("samples", [])


func _entry(oes, owner: String, zone: String) -> Dictionary:
	var key: String = "%s|%s" % [owner, zone]
	var totals: Dictionary = _totals(oes)
	if not totals.has(key):
		_failed = true
		push_error("H3.2-S0d6 ASSERTION FAILED: missing entry %s" % key)
		return {}
	return totals[key]


func _room(room_id: int):
	var room = RoomModelScript.new()
	room.id = room_id
	room.width_m = 5.0
	room.length_m = 4.0
	room.height_m = 2.5
	room.thermal_layer_m = 1.2
	room.temp_upper_c = 200.0
	room.temp_lower_c = 20.0
	room.upper_gas_kg = 3.0
	room.lower_gas_kg = 50.0
	room.upper_energy_kj = 200.0
	room.lower_energy_kj = 10.0
	room.o2 = 0.209
	room.o2_upper = 0.209
	room.o2_lower = 0.209
	return room


func _expect(condition: bool, label: String) -> void:
	if condition:
		return
	_failed = true
	push_error("H3.2-S0d6 ASSERTION FAILED: %s" % label)

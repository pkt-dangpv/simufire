extends SceneTree

## H3.2b2 fixture: the pure residual projection primitive.
##
## It preloads the primitive and NOTHING else. No engine, no solver, no room
## model: the primitive has zero call sites by design, and a fixture that reached
## into the engine to exercise it would be the first one.
##
## Every assertion here is about the primitive as a function. No scenario is run,
## because without a call site a scenario would be empty evidence.
##
## The canonical equation of state is checked two ways: against the reference
## state the rest of the engine is built around (a room at ambient holding
## `1.2 * V` kg must derive exactly 101325 Pa), and against an INDEPENDENT
## recomputation of `Phase3CoupledPressureSolver`'s own algebraic form, written
## out here rather than imported so the primitive stays autonomous.

const ResidualProjection = preload("res://sim/core/Phase3ResidualProjection.gd")

const EXPECTED_TESTS: int = 22

## An ordinary room: 4 m x 5 m x 2.5 m = 50 m3, ambient 20 C.
const AREA_M2: float = 20.0
const HEIGHT_M: float = 2.5
const AMBIENT_C: float = 20.0

var _failed: bool = false
var _completed: Array[String] = []


func _done(label: String) -> void:
	_completed.append(label)


func _init() -> void:
	_test_ordinary_two_zone()
	_test_volume_closure_matches_an_independent_derivation()
	_test_eos_matches_the_canonical_solver_form()
	_test_ambient_room_derives_reference_pressure()
	_test_upper_absent()
	_test_lower_absent()
	_test_one_zone_interface_is_exact()
	_test_equal_temperatures()
	_test_hot_upper_cold_lower()
	_test_very_small_but_valid_masses()
	_test_energy_without_mass_fails_closed()
	_test_negative_mass_and_energy_fail_closed()
	_test_non_finite_inputs_fail_closed()
	_test_invalid_geometry_fails_closed()
	_test_both_zones_absent_fails_closed()
	_test_mass_and_energy_are_returned_bit_identical()
	_test_corrections_are_exactly_zero()
	_test_valid_results_contain_no_nan_or_inf()
	_test_absent_zone_omits_derived_fields()
	_test_binary_determinism_and_idempotence()
	_test_negative_control_invalid_carries_no_derived_field()
	_test_transition_is_two_independent_evaluations()
	if _completed.size() != EXPECTED_TESTS:
		push_error("H3.2b2 ABORTED: %d/%d completed; ran %s"
			% [_completed.size(), EXPECTED_TESTS, str(_completed)])
		quit(1)
		return
	if _failed:
		quit(1)
		return
	print("PHASE3_H32B2_RESIDUAL_PROJECTION_PASS")
	quit(0)


# --------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------

func _derive(mu: float, eu: float, ml: float, el: float,
		area: float = AREA_M2, height: float = HEIGHT_M,
		ambient: float = AMBIENT_C) -> Dictionary:
	return ResidualProjection.derive(mu, eu, ml, el, area, height, ambient)


func _identical_bytes(a, b) -> bool:
	## TRUE binary identity: the complete serialisations are compared byte for
	## byte. No approximate comparison and no special case for any value.
	var pa: PackedByteArray = var_to_bytes(a)
	var pb: PackedByteArray = var_to_bytes(b)
	if pa.size() != pb.size():
		return false
	for i in range(pa.size()):
		if pa[i] != pb[i]:
			return false
	return true


func _has_non_finite(value) -> bool:
	## Recursive walk. Any NAN or INF anywhere below `value` is reported.
	if value is float:
		return not is_finite(value)
	if value is Dictionary:
		for key in value.keys():
			if _has_non_finite(value[key]):
				return true
		return false
	if value is Array:
		for item in value:
			if _has_non_finite(item):
				return true
	return false


func _budget(result: Dictionary) -> float:
	return float(result["volume_closure_budget_m3"])


func _gas_constant(ambient_c: float) -> float:
	## The canonical solver's own form, written out independently.
	var reference_temp_k: float = ambient_c + 273.15
	return ResidualProjection.AIR_PRESSURE_REF_PA \
			/ (ResidualProjection.AIR_DENSITY_REF_KG_M3 * reference_temp_k)


# --------------------------------------------------------------------------
# Ordinary states
# --------------------------------------------------------------------------

func _test_ordinary_two_zone() -> void:
	# Upper: 10 kg carrying 2000 kJ -> 200 K above ambient.
	# Lower: 45 kg carrying 90 kJ   -> 2 K above ambient.
	var r: Dictionary = _derive(10.0, 2000.0, 45.0, 90.0)
	_expect(r["valid"], "an ordinary two-zone state is valid")
	_expect(r["reason_code"] == ResidualProjection.REASON_OK, "reason code is ok")
	_expect(r["upper"]["present"] and r["lower"]["present"], "both zones present")
	_expect(is_equal_approx(float(r["upper"]["temperature_k"]), 293.15 + 200.0),
		"upper temperature follows E/(M*cp) from ambient")
	_expect(is_equal_approx(float(r["lower"]["temperature_k"]), 293.15 + 2.0),
		"lower temperature follows E/(M*cp) from ambient")
	_expect(float(r["pressure_abs_pa"]) > 0.0 and is_finite(float(r["pressure_abs_pa"])),
		"pressure is finite and positive")
	_expect(absf(float(r["volume_closure_error_m3"])) <= _budget(r),
		"volume closes inside the derived rounding budget")
	_expect(float(r["interface_height_m"]) >= 0.0
			and float(r["interface_height_m"]) <= HEIGHT_M,
		"the interface lies inside [0, room_height]")
	_expect(float(r["upper"]["density_kg_m3"]) < float(r["lower"]["density_kg_m3"]),
		"the hotter zone is the less dense one")
	_done("ordinary_two_zone")


func _test_volume_closure_matches_an_independent_derivation() -> void:
	## Independent route to the same volumes. From the closure,
	##     V_zone = V_room * (M_zone * T_zone) / (M_u*T_u + M_l*T_l)
	## which never mentions pressure, density or the gas constant, so it
	## exercises a different algebraic path than the primitive does.
	var cases: Array = [
		[10.0, 2000.0, 45.0, 90.0],
		[1.0, 5000.0, 58.0, 0.0],
		[30.0, 100.0, 30.0, 100.0],
		[0.5, 0.0, 59.0, 1180.0],
		[1.0e-9, 1.0e-9, 60.0, 6000.0],
		[59.0, 29500.0, 1.0, 0.0],
	]
	var worst_ulp: float = 0.0
	for c in cases:
		var r: Dictionary = _derive(c[0], c[1], c[2], c[3])
		_expect(r["valid"], "independent-closure case is valid")
		var tu: float = float(r["upper"]["temperature_k"])
		var tl: float = float(r["lower"]["temperature_k"])
		var sum_mt: float = c[0] * tu + c[2] * tl
		var v_room: float = float(r["room_volume_m3"])
		var expected_upper: float = v_room * (c[0] * tu) / sum_mt
		var expected_lower: float = v_room * (c[2] * tl) / sum_mt
		var bound: float = _budget(r)
		_expect(absf(float(r["upper"]["volume_m3"]) - expected_upper) <= bound,
			"upper volume matches the independent mass-temperature fraction")
		_expect(absf(float(r["lower"]["volume_m3"]) - expected_lower) <= bound,
			"lower volume matches the independent mass-temperature fraction")
		_expect(absf(float(r["upper"]["volume_m3"]) + float(r["lower"]["volume_m3"])
				- v_room) <= bound,
			"the two volumes sum to the room volume inside the budget")
		var ulp: float = absf(float(r["volume_closure_error_m3"])) \
				/ (ResidualProjection.DOUBLE_EPSILON * v_room)
		worst_ulp = maxf(worst_ulp, ulp)
	# Reported so the budget can be seen to be a derived bound with headroom
	# rather than a number fitted to make these cases pass.
	print("H3.2B2_CLOSURE_WORST_ULP=%.3f BUDGET_ULP=%d"
		% [worst_ulp, ResidualProjection.VOLUME_CLOSURE_ROUNDING_BUDGET])
	_expect(worst_ulp <= float(ResidualProjection.VOLUME_CLOSURE_ROUNDING_BUDGET),
		"the measured worst closure error stays inside the derived budget")
	_done("independent_closure")


func _test_eos_matches_the_canonical_solver_form() -> void:
	## `Phase3CoupledPressureSolver.gd:1252-1254` writes the same pressure as
	##     gas_constant * (M_total * T_ref + E_total / cp) / V
	## which is algebraically identical to this primitive's
	##     (gas_constant / V) * (M_u * T_u + M_l * T_l)
	## but rounds differently. Agreement between the two is the check that this
	## file did not introduce a second definition of air.
	var cases: Array = [
		[10.0, 2000.0, 45.0, 90.0, 20.0],
		[1.0, 5000.0, 58.0, 0.0, 20.0],
		[0.5, 0.0, 59.0, 1180.0, 20.0],
		[1.0e-9, 1.0e-9, 60.0, 6000.0, 20.0],
		[59.0, 29500.0, 1.0, 0.0, 20.0],
		[8.0, 4000.0, 50.0, 0.0, -10.0],
		[8.0, 4000.0, 50.0, 0.0, 35.0],
	]
	var worst_ulp: float = 0.0
	for c in cases:
		var ambient_c: float = c[4]
		var r: Dictionary = _derive(c[0], c[1], c[2], c[3], AREA_M2, HEIGHT_M, ambient_c)
		_expect(r["valid"], "canonical-EOS case is valid")
		var reference_temp_k: float = ambient_c + 273.15
		var gas_constant: float = _gas_constant(ambient_c)
		_expect(is_equal_approx(float(r["gas_constant_j_kg_k"]), gas_constant),
			"the primitive reports the canonical gas constant")
		_expect(is_equal_approx(float(r["reference_temp_k"]), reference_temp_k),
			"and the canonical reference temperature")
		var total_mass_kg: float = c[0] + c[2]
		var total_energy_kj: float = c[1] + c[3]
		var solver_pressure_pa: float = gas_constant * (
			total_mass_kg * reference_temp_k
			+ total_energy_kj / ResidualProjection.AIR_CP_KJ_KG_K
		) / float(r["room_volume_m3"])
		var ulp: float = absf(float(r["pressure_abs_pa"]) - solver_pressure_pa) \
				/ (ResidualProjection.DOUBLE_EPSILON * solver_pressure_pa)
		worst_ulp = maxf(worst_ulp, ulp)
		_expect(ulp <= float(ResidualProjection.AMBIENT_PRESSURE_ROUNDING_BUDGET),
			"the pressure matches the canonical solver form to within rounding")
	print("H3.2B2_EOS_VS_SOLVER_WORST_ULP=%.3f BUDGET_ULP=%d"
		% [worst_ulp, ResidualProjection.AMBIENT_PRESSURE_ROUNDING_BUDGET])
	_done("eos_matches_solver")


func _test_ambient_room_derives_reference_pressure() -> void:
	## The reference state the whole engine is built around: a room holding
	## exactly `AIR_DENSITY_REF_KG_M3 * V` kilograms at ambient must derive
	## `AIR_PRESSURE_REF_PA`. This is what a second, incompatible gas constant
	## would break -- the first issue of this primitive missed it by 345.5 Pa.
	var rooms: Array = [
		[20.0, 2.5, 20.0], [3.0, 2.4, 20.0], [100.0, 3.0, 20.0],
		[12.5, 2.7, 15.0], [7.0, 2.2, 25.0], [20.0, 2.5, 0.0],
		[45.0, 2.6, -10.0], [60.0, 4.0, 35.0],
	]
	var splits: Array = [0.0, 0.001, 0.3, 0.5, 0.7, 1.0]
	var reference_pa: float = ResidualProjection.AIR_PRESSURE_REF_PA
	var budget_pa: float = float(ResidualProjection.AMBIENT_PRESSURE_ROUNDING_BUDGET) \
			* ResidualProjection.DOUBLE_EPSILON * reference_pa
	var worst_pa: float = 0.0
	for room in rooms:
		var area: float = room[0]
		var height: float = room[1]
		var ambient_c: float = room[2]
		var total_mass_kg: float = ResidualProjection.AIR_DENSITY_REF_KG_M3 \
				* area * height
		for split in splits:
			var upper_mass_kg: float = split * total_mass_kg
			var lower_mass_kg: float = total_mass_kg - upper_mass_kg
			var r: Dictionary = _derive(upper_mass_kg, 0.0, lower_mass_kg, 0.0,
				area, height, ambient_c)
			_expect(r["valid"], "an ambient room is a valid state")
			var deviation_pa: float = absf(float(r["pressure_abs_pa"]) - reference_pa)
			worst_pa = maxf(worst_pa, deviation_pa)
			_expect(deviation_pa <= budget_pa,
				"an ambient room derives the reference pressure")
	print("H3.2B2_AMBIENT_PRESSURE_WORST_ULP=%.3f BUDGET_ULP=%d"
		% [worst_pa / (ResidualProjection.DOUBLE_EPSILON * reference_pa),
			ResidualProjection.AMBIENT_PRESSURE_ROUNDING_BUDGET])
	_done("ambient_reference_pressure")


func _test_upper_absent() -> void:
	var r: Dictionary = _derive(0.0, 0.0, 60.0, 600.0)
	_expect(r["valid"], "an absent upper zone is a valid one-zone state")
	_expect(not r["upper"]["present"], "the upper zone is reported absent")
	_expect(r["lower"]["present"], "the lower zone is present")
	_expect(float(r["upper"]["volume_m3"]) == 0.0,
		"an absent zone occupies exactly zero volume")
	_expect(absf(float(r["lower"]["volume_m3"]) - float(r["room_volume_m3"]))
			<= _budget(r),
		"the present zone fills the room exactly")
	_done("upper_absent")


func _test_lower_absent() -> void:
	var r: Dictionary = _derive(60.0, 600.0, 0.0, 0.0)
	_expect(r["valid"], "an absent lower zone is a valid one-zone state")
	_expect(r["upper"]["present"] and not r["lower"]["present"],
		"only the upper zone is present")
	_expect(float(r["lower"]["volume_m3"]) == 0.0,
		"the absent lower zone occupies exactly zero volume")
	_expect(absf(float(r["upper"]["volume_m3"]) - float(r["room_volume_m3"]))
			<= _budget(r),
		"the upper zone fills the room exactly")
	_done("lower_absent")


func _test_one_zone_interface_is_exact() -> void:
	## The boundary of a one-zone room is not a rounded quantity. It is known
	## from the presence state, so it is returned EXACTLY -- never `h - 1e-16`
	## and never `+1e-16`. Exact equality is required here, not approximation.
	var no_upper: Dictionary = _derive(0.0, 0.0, 60.0, 600.0)
	_expect(float(no_upper["interface_height_m"]) == HEIGHT_M,
		"with no upper zone the interface is exactly the room height")
	_expect(float(no_upper["interface_height_raw_m"]) == HEIGHT_M,
		"and the raw value carries the same exact boundary")

	var no_lower: Dictionary = _derive(60.0, 600.0, 0.0, 0.0)
	_expect(float(no_lower["interface_height_m"]) == 0.0,
		"with no lower zone the interface is exactly zero")
	_expect(float(no_lower["interface_height_raw_m"]) == 0.0,
		"and the raw value carries the same exact boundary")

	# The exactness must not depend on the room, the ambient or the inventory.
	var rooms: Array = [[3.0, 2.4, 20.0], [100.0, 3.0, -5.0], [7.5, 2.7, 30.0]]
	for room in rooms:
		var a: Dictionary = _derive(0.0, 0.0, 33.0, 700.0, room[0], room[1], room[2])
		_expect(float(a["interface_height_m"]) == float(room[1]),
			"upper-absent interface is exact in any room")
		var b: Dictionary = _derive(33.0, 700.0, 0.0, 0.0, room[0], room[1], room[2])
		_expect(float(b["interface_height_m"]) == 0.0,
			"lower-absent interface is exact in any room")

	# Two zones present: the ordinary geometric derivation, inside the budget.
	var both: Dictionary = _derive(10.0, 2000.0, 45.0, 90.0)
	var interface_budget_m: float = float(
		ResidualProjection.VOLUME_CLOSURE_ROUNDING_BUDGET) \
		* ResidualProjection.DOUBLE_EPSILON * HEIGHT_M
	_expect(float(both["interface_height_m"]) > 0.0
			and float(both["interface_height_m"]) < HEIGHT_M,
		"with both zones present the interface is strictly inside the room")
	_expect(absf(float(both["interface_height_m"])
			- float(both["interface_height_raw_m"])) <= interface_budget_m,
		"and the projection into [0, h] moves it at most a rounding step")
	_done("one_zone_interface_exact")


func _test_equal_temperatures() -> void:
	# Both zones 10 K above ambient: 20 kg/200 kJ and 40 kg/400 kJ.
	var r: Dictionary = _derive(20.0, 200.0, 40.0, 400.0)
	_expect(r["valid"], "equal temperatures are a valid state")
	_expect(float(r["upper"]["temperature_k"]) == float(r["lower"]["temperature_k"]),
		"the two derived temperatures are identical")
	_expect(float(r["upper"]["density_kg_m3"]) == float(r["lower"]["density_kg_m3"]),
		"equal temperatures give equal densities")
	# With equal densities the volumes split by mass alone.
	var v_room: float = float(r["room_volume_m3"])
	_expect(absf(float(r["upper"]["volume_m3"]) - v_room / 3.0) <= _budget(r),
		"volume splits in the mass ratio when temperatures are equal")
	_done("equal_temperatures")


func _test_hot_upper_cold_lower() -> void:
	var r: Dictionary = _derive(8.0, 4000.0, 50.0, 0.0)
	_expect(r["valid"], "a hot upper over an ambient lower is valid")
	_expect(float(r["upper"]["temperature_k"]) > float(r["lower"]["temperature_k"]),
		"the upper zone is the hotter one")
	_expect(float(r["lower"]["temperature_k"]) == 293.15,
		"a zone with zero energy sits exactly at ambient")
	_expect(float(r["interface_height_m"]) < HEIGHT_M,
		"a hot upper layer pushes the interface below the ceiling")
	_expect(absf(float(r["volume_closure_error_m3"])) <= _budget(r),
		"closure holds under a large temperature contrast")
	_done("hot_upper_cold_lower")


func _test_very_small_but_valid_masses() -> void:
	# Tiny but strictly positive, with energy scaled so the temperature stays
	# sane: 1e-9 kg carrying 1e-9 kJ is exactly 1 K above ambient.
	var r: Dictionary = _derive(1.0e-9, 1.0e-9, 1.0e-9, 1.0e-9)
	_expect(r["valid"], "vanishingly small but positive masses are valid")
	_expect(r["upper"]["present"] and r["lower"]["present"],
		"presence is decided by a strictly positive mass, not by a threshold")
	_expect(is_equal_approx(float(r["upper"]["temperature_k"]), 293.15 + 1.0),
		"the derived temperature is unaffected by the absolute scale of the mass")
	_expect(absf(float(r["volume_closure_error_m3"])) <= _budget(r),
		"closure still holds at 1e-9 kg")
	_expect(float(r["pressure_abs_pa"]) > 0.0,
		"pressure stays positive, though far below the reference pressure")
	_expect(not _has_non_finite(r), "and the result is still free of NAN and INF")
	_done("small_masses")


# --------------------------------------------------------------------------
# Invalid states: every one fails closed
# --------------------------------------------------------------------------

func _test_energy_without_mass_fails_closed() -> void:
	var upper: Dictionary = _derive(0.0, 1.0, 45.0, 90.0)
	_expect(not upper["valid"], "upper energy without upper mass is invalid")
	_expect(upper["reason_code"] == ResidualProjection.REASON_ENERGY_WITHOUT_MASS,
		"and it says so")
	var lower: Dictionary = _derive(10.0, 100.0, 0.0, 5.0)
	_expect(not lower["valid"], "lower energy without lower mass is invalid")
	_expect(lower["reason_code"] == ResidualProjection.REASON_ENERGY_WITHOUT_MASS,
		"and it says so too")
	_expect(float(upper["energy_correction_kj"]) == 0.0,
		"the orphaned energy is not zeroed, moved or absorbed")
	_done("energy_without_mass")


func _test_negative_mass_and_energy_fail_closed() -> void:
	var nm: Dictionary = _derive(-1.0, 0.0, 45.0, 90.0)
	_expect(not nm["valid"] and nm["reason_code"] == ResidualProjection.REASON_NEGATIVE_MASS,
		"negative mass is invalid")
	var ne: Dictionary = _derive(10.0, -1.0, 45.0, 90.0)
	_expect(not ne["valid"] and ne["reason_code"] == ResidualProjection.REASON_NEGATIVE_ENERGY,
		"negative energy is invalid")
	var nml: Dictionary = _derive(10.0, 100.0, -0.001, 0.0)
	_expect(not nml["valid"] and nml["reason_code"] == ResidualProjection.REASON_NEGATIVE_MASS,
		"a negative lower mass is invalid as well")
	_done("negative_inputs")


func _test_non_finite_inputs_fail_closed() -> void:
	var values: Array = [NAN, INF, -INF]
	for v in values:
		var a: Dictionary = _derive(v, 0.0, 45.0, 90.0)
		_expect(not a["valid"]
				and a["reason_code"] == ResidualProjection.REASON_NON_FINITE_INPUT,
			"a non-finite mass is rejected")
		var b: Dictionary = _derive(10.0, v, 45.0, 90.0)
		_expect(not b["valid"]
				and b["reason_code"] == ResidualProjection.REASON_NON_FINITE_INPUT,
			"a non-finite energy is rejected")
		var c: Dictionary = _derive(10.0, 100.0, 45.0, 90.0, v, HEIGHT_M)
		_expect(not c["valid"]
				and c["reason_code"] == ResidualProjection.REASON_NON_FINITE_INPUT,
			"a non-finite area is rejected")
		var d: Dictionary = _derive(10.0, 100.0, 45.0, 90.0, AREA_M2, HEIGHT_M, v)
		_expect(not d["valid"]
				and d["reason_code"] == ResidualProjection.REASON_NON_FINITE_INPUT,
			"a non-finite ambient temperature is rejected")
	_done("non_finite_inputs")


func _test_invalid_geometry_fails_closed() -> void:
	var zero_area: Dictionary = _derive(10.0, 100.0, 45.0, 90.0, 0.0, HEIGHT_M)
	_expect(not zero_area["valid"]
			and zero_area["reason_code"] == ResidualProjection.REASON_INVALID_GEOMETRY,
		"a zero floor area is invalid")
	var neg_height: Dictionary = _derive(10.0, 100.0, 45.0, 90.0, AREA_M2, -2.5)
	_expect(not neg_height["valid"]
			and neg_height["reason_code"] == ResidualProjection.REASON_INVALID_GEOMETRY,
		"a negative height is invalid")
	var cold: Dictionary = _derive(10.0, 100.0, 45.0, 90.0, AREA_M2, HEIGHT_M, -300.0)
	_expect(not cold["valid"]
			and cold["reason_code"] == ResidualProjection.REASON_INVALID_AMBIENT,
		"an ambient below absolute zero is invalid")
	# The fallible auxiliary helper refuses rather than guessing. NAN is a
	# legitimate return here precisely because this is NOT a valid result.
	_expect(is_nan(ResidualProjection.floor_area_from_volume_m2(50.0, 0.0)),
		"the geometry helper returns NAN for an unusable height")
	_expect(is_nan(ResidualProjection.floor_area_from_volume_m2(NAN, 2.5)),
		"the geometry helper returns NAN for a non-finite volume")
	_expect(is_equal_approx(
			ResidualProjection.floor_area_from_volume_m2(50.0, 2.5), 20.0),
		"and otherwise derives the area exactly")
	_done("invalid_geometry")


func _test_both_zones_absent_fails_closed() -> void:
	var r: Dictionary = _derive(0.0, 0.0, 0.0, 0.0)
	_expect(not r["valid"], "a room with no gas at all is invalid")
	_expect(r["reason_code"] == ResidualProjection.REASON_BOTH_ZONES_ABSENT,
		"and it names that specific state")
	_done("both_zones_absent")


# --------------------------------------------------------------------------
# Purity properties
# --------------------------------------------------------------------------

func _test_mass_and_energy_are_returned_bit_identical() -> void:
	var mu: float = 10.123456789012345
	var eu: float = 2000.987654321098
	var ml: float = 45.55555555555555
	var el: float = 90.111111111111
	var r: Dictionary = _derive(mu, eu, ml, el)
	_expect(r["valid"], "the precision case is valid")
	_expect(_identical_bytes(r["upper"]["mass_kg"], mu),
		"upper mass is returned bit-identical")
	_expect(_identical_bytes(r["upper"]["energy_kj"], eu),
		"upper energy is returned bit-identical")
	_expect(_identical_bytes(r["lower"]["mass_kg"], ml),
		"lower mass is returned bit-identical")
	_expect(_identical_bytes(r["lower"]["energy_kj"], el),
		"lower energy is returned bit-identical")
	_done("bit_identical_inventories")


func _test_corrections_are_exactly_zero() -> void:
	var r: Dictionary = _derive(10.0, 2000.0, 45.0, 90.0)
	_expect(float(r["mass_correction_kg"]) == 0.0,
		"a valid state needs exactly zero mass correction")
	_expect(float(r["energy_correction_kj"]) == 0.0,
		"a valid state needs exactly zero energy correction")
	_expect(r["thermal_limit_applied"] == false,
		"no thermal limit is applied here; H3.2b5 owns that")
	_done("zero_corrections")


func _test_valid_results_contain_no_nan_or_inf() -> void:
	## Walked recursively, including the nested zone dictionaries. A `valid`
	## result must be usable end to end without a reader having to guard.
	var states: Array = [
		[10.0, 2000.0, 45.0, 90.0],
		[0.0, 0.0, 60.0, 600.0],
		[60.0, 600.0, 0.0, 0.0],
		[20.0, 200.0, 40.0, 400.0],
		[8.0, 4000.0, 50.0, 0.0],
		[1.0e-9, 1.0e-9, 1.0e-9, 1.0e-9],
		[1.0e-9, 0.0, 60.0, 0.0],
	]
	for s in states:
		var r: Dictionary = _derive(s[0], s[1], s[2], s[3])
		_expect(r["valid"], "the state under test is valid")
		_expect(not _has_non_finite(r),
			"a valid result carries no NAN and no INF anywhere")
	# The walker must be able to find one, or the check above proves nothing.
	_expect(_has_non_finite({"a": {"b": [1.0, NAN]}}),
		"the recursive walker really does detect a nested NAN")
	_expect(_has_non_finite({"a": INF}), "and a nested INF")
	_expect(not _has_non_finite({"a": {"b": [1.0, 2.0]}}),
		"and does not fire on finite content")
	_done("no_nan_in_valid_results")


func _test_absent_zone_omits_derived_fields() -> void:
	## Bidirectional. An absent zone must not carry a temperature or a density
	## at all -- not as NAN, not as ambient. A present zone must carry both, and
	## both must be finite and positive.
	var r: Dictionary = _derive(0.0, 0.0, 60.0, 600.0)
	var absent: Dictionary = r["upper"]
	var present: Dictionary = r["lower"]
	for forbidden in ["temperature_k", "density_kg_m3"]:
		_expect(not absent.has(forbidden),
			"an absent zone omits %s entirely" % forbidden)
		_expect(present.has(forbidden),
			"a present zone carries %s" % forbidden)
	for required in ["present", "mass_kg", "energy_kj", "volume_m3"]:
		_expect(absent.has(required), "an absent zone still reports %s" % required)
	_expect(float(absent["mass_kg"]) == 0.0 and float(absent["energy_kj"]) == 0.0,
		"an absent zone reports exact zeros for its inventory")
	_expect(float(present["temperature_k"]) > 0.0
			and is_finite(float(present["temperature_k"])),
		"a present zone temperature is finite and positive")
	_expect(float(present["density_kg_m3"]) > 0.0
			and is_finite(float(present["density_kg_m3"])),
		"a present zone density is finite and positive")
	# The mirror case, so the check cannot pass because the keys never exist.
	var both: Dictionary = _derive(10.0, 100.0, 45.0, 90.0)
	for zone_key in ["upper", "lower"]:
		var zone: Dictionary = both[zone_key]
		_expect(zone.has("temperature_k") and zone.has("density_kg_m3"),
			"both present zones carry their derived fields")
		_expect(float(zone["temperature_k"]) > 0.0
				and float(zone["density_kg_m3"]) > 0.0,
			"and both are strictly positive")
	_done("absent_zone_omits_fields")


func _test_binary_determinism_and_idempotence() -> void:
	## Byte-for-byte identity of the complete serialised results. No approximate
	## comparison and no special case for any value: with NAN gone from valid
	## results there is nothing left that needs one.
	var inputs: Array = [
		[10.0, 2000.0, 45.0, 90.0],   # two zones
		[0.0, 0.0, 60.0, 600.0],      # upper absent
		[60.0, 600.0, 0.0, 0.0],      # lower absent
	]
	for s in inputs:
		var first: Dictionary = _derive(s[0], s[1], s[2], s[3])
		var second: Dictionary = _derive(s[0], s[1], s[2], s[3])
		_expect(_identical_bytes(first, second),
			"the same input gives a byte-identical result")
		# Idempotence: feeding the returned inventories back in changes nothing.
		# The legacy path cannot do this, because it overwrites lower_gas_kg
		# from the remaining volume and so answers differently on a second call.
		var again: Dictionary = _derive(
			float(first["upper"]["mass_kg"]), float(first["upper"]["energy_kj"]),
			float(first["lower"]["mass_kg"]), float(first["lower"]["energy_kj"]))
		_expect(_identical_bytes(first, again),
			"re-evaluating with the returned M and E is byte-identical")
	# The comparator must be able to tell two results apart, or the checks above
	# prove nothing.
	_expect(not _identical_bytes(_derive(10.0, 2000.0, 45.0, 90.0),
			_derive(10.0, 2000.0, 45.0, 90.000000001)),
		"the byte comparator really does separate two different results")
	_done("binary_determinism")


func _test_negative_control_invalid_carries_no_derived_field() -> void:
	## Negative control. If the primitive ever started reporting a pressure, a
	## temperature or a volume for a rejected state, this fails -- that is the
	## shape of a fail-open regression.
	var r: Dictionary = _derive(0.0, 5.0, 0.0, 0.0)
	_expect(not r["valid"], "the control state is invalid")
	for forbidden in ["pressure_abs_pa", "upper", "lower", "room_volume_m3",
			"interface_height_m", "interface_height_raw_m",
			"volume_closure_error_m3", "gas_constant_j_kg_k", "reference_temp_k"]:
		_expect(not r.has(forbidden),
			"an invalid result exposes no derived field: %s" % forbidden)
	_expect(not _has_non_finite(r),
		"and an invalid result carries no NAN or INF either")
	# And the inverse control: a valid state really does carry them, so the
	# check above cannot pass merely because the keys never exist.
	var ok: Dictionary = _derive(10.0, 2000.0, 45.0, 90.0)
	for required in ["pressure_abs_pa", "upper", "lower", "room_volume_m3",
			"interface_height_m", "volume_closure_error_m3",
			"gas_constant_j_kg_k", "reference_temp_k"]:
		_expect(ok.has(required), "a valid result does carry %s" % required)
	_done("negative_control")


func _test_transition_is_two_independent_evaluations() -> void:
	## A one-zone to two-zone transition is represented here as two SEPARATE
	## evaluations of a stateless function. The primitive holds no history and
	## counts no transitions.
	##
	## This asserts nothing about the runtime transition counters. H3.2b1a
	## measured those counters missing at least 29 real births across ten
	## topologies, because they compare the pre and post of a single projection
	## call. Repairing them is H3.2b1b and has not been done.
	var before: Dictionary = _derive(0.0, 0.0, 60.0, 600.0)
	var after: Dictionary = _derive(0.5, 250.0, 59.5, 595.0)
	_expect(before["valid"] and after["valid"], "both sides of the transition are valid")
	_expect(not before["upper"]["present"] and after["upper"]["present"],
		"the upper zone is absent before and present after")
	_expect(float(before["interface_height_m"]) == HEIGHT_M,
		"before the transition the interface is exactly the ceiling")
	_expect(absf(float(after["volume_closure_error_m3"]))
			<= float(after["volume_closure_budget_m3"]),
		"closure holds on the two-zone side")
	_expect(float(after["interface_height_m"]) < float(before["interface_height_m"]),
		"the interface descends once an upper layer exists")
	for key in before.keys():
		var name: String = String(key)
		_expect(not name.contains("birth") and not name.contains("death")
				and not name.contains("transition"),
			"the primitive counts no transitions: %s" % name)
	_done("transition_two_evaluations")


func _expect(condition: bool, label: String) -> void:
	if condition:
		return
	_failed = true
	push_error("H3.2b2 ASSERTION FAILED: %s" % label)

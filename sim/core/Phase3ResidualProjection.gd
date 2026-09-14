extends RefCounted

## H3.2b2: pure residual projection primitive.
##
## It derives geometry FROM the authoritative inventories. It does not derive
## inventories from geometry. That inversion is the whole point of H3.2b: today
## `ZoneFireSolver.project_room_state()` overwrites `lower_gas_kg` from the
## remaining volume (`ZoneFireSolver.gd:281`) and re-derives both energies from
## clamped temperatures (`:246-251`), so mass and energy are back-filled to make
## a derived quantity close. Here nothing is back-filled: `M` and `E` are inputs,
## every other quantity follows from them, and volume closure is an algebraic
## consequence rather than a constraint to enforce.
##
## PURITY. This script has no member state, no `class_name` registration, no
## call sites and no side effects. Every entry point is `static`, reads only its
## arguments, and returns a fresh Dictionary. It never touches a RoomModel, a
## BuildingModel, the engine, the solver or any subsystem.
##
## AUTHORITY. None. This phase creates the primitive only. It is not wired
## anywhere, it has no flag, no shadow path and no fallback.
##
## THE EQUATION OF STATE IS THE CANONICAL ONE, NOT A SECOND DEFINITION OF AIR.
## The first issue of this primitive hard-coded a dry-air specific gas constant
## of 287.052874 J/(kg*K). That was wrong: it made this file a second, competing
## definition of air and manufactured a 345.5 Pa disagreement with
## `Phase3CoupledPressureSolver` out of nothing. The constants and the closure
## below are now exactly that solver's convention
## (`Phase3CoupledPressureSolver.gd:78-79`, `:1115-1119`), reproduced rather than
## imported so this primitive stays autonomous and pure:
##     reference_temp_k = ambient_temp_c + 273.15
##     gas_constant     = AIR_PRESSURE_REF_PA
##                        / (AIR_DENSITY_REF_KG_M3 * reference_temp_k)
## The gas constant therefore depends on the ambient temperature, exactly as it
## does in the canonical solver. It is not a universal constant and is not
## presented as one.
##
## ENERGY CONVENTION. `E_zone` is SENSIBLE energy measured FROM AMBIENT, in kJ,
## exactly as the engine already treats it at `ZoneFireSolver.gd:214-221`:
##     T_zone_k = reference_temp_k + E_zone / (M_zone * cp)
## so `E = 0` means "this zone is at ambient", not "this zone has no energy".
## A negative `E` would mean a zone below ambient; the engine has no owner that
## produces one, so it is rejected as invalid rather than silently allowed.
##
## THE CLOSURE, and its proof. Writing `K` for `gas_constant`:
##     p_abs    = (K / V_room) * (M_upper * T_upper_k + M_lower * T_lower_k)
##     rho_zone = p_abs / (K * T_zone_k)
##     V_zone   = M_zone / rho_zone
## Substituting rho into V:
##     V_upper + V_lower = M_u*K*T_u/p + M_l*K*T_l/p
##                       = (K/p) * (M_u*T_u + M_l*T_l)
## and from the pressure line, (M_u*T_u + M_l*T_l) = p * V_room / K, hence
##     V_upper + V_lower = (K/p) * (p * V_room / K) = V_room
## identically, for ANY masses and energies satisfying the validity contract, and
## for ANY value of `K`. No mass or energy is adjusted to make this hold. In
## floating point the identity holds to a rounding budget derived below, never to
## a physical tolerance.
##
## THE AMBIENT IDENTITY. A room holding exactly `M_total = AIR_DENSITY_REF_KG_M3
## * V_room` at `E = 0` derives `p_abs = AIR_PRESSURE_REF_PA` identically:
##     p = (K/V) * (1.2*V) * T_ref
##       = (P_ref / (1.2 * T_ref) / V) * 1.2 * V * T_ref = P_ref
## This is the check that the equation of state agrees with the reference state
## the rest of the engine is built around.
##
## ONE ZONE ABSENT is a special case of the same identity, not an exception: if
## M_upper = 0 then p = (K/V)*M_l*T_l and V_lower = M_l*K*T_l/p = V_room, so the
## present zone fills the room exactly and the absent zone occupies exactly zero.
## No temperature, density or composition is invented for the absent zone, and
## no field carrying one is emitted for it at all.
##
## NO NaN OR INF EVER APPEARS IN A `valid: true` RESULT. An absent zone carries
## only the fields that have a meaning for it. A present zone always carries a
## finite, positive temperature and density. The one fallible helper,
## `floor_area_from_volume_m2()`, is not a result and is documented as such.
##
## THE THERMAL LIMIT IS NOT APPLIED HERE. H3.2b1a measured zero activations of
## the upper-temperature limit across ten topologies at 120 s, and H3.2b5 is the
## phase that owns it. This primitive therefore reports the derived temperature
## UNLIMITED, removes no energy, and never treats a maximum temperature as
## authorisation to change `E`. `thermal_limit_applied` is always false.

## Specific heat of air. Shared by `ZoneFireSolver.AIR_CP_KJ_KG_K` and
## `Phase3CoupledPressureSolver.AIR_CP_KJ_KG_K`; mirrored here so the derived
## temperature matches both conventions exactly. Not scenario-configurable.
const AIR_CP_KJ_KG_K: float = 1.0

## Reference state of the canonical equation of state, identical to
## `Phase3CoupledPressureSolver.gd:78-79`. These two values, together with the
## ambient temperature, define the gas constant; there is no separate specific
## gas constant in this file and there must never be one.
const AIR_PRESSURE_REF_PA: float = 101325.0
const AIR_DENSITY_REF_KG_M3: float = 1.2

const KELVIN_OFFSET_C: float = 273.15

## IEEE-754 binary64 machine epsilon. GDScript floats are doubles.
const DOUBLE_EPSILON: float = 2.220446049250313e-16

## Rounding budget for the volume closure, DERIVED not fitted. The dependency
## path from the inputs to `V_zone` is: the gas constant (multiply, divide = 2),
## temperature (multiply, divide, add = 3), pressure (two multiplies, an add, a
## divide and a multiply = 5), density (multiply, divide = 2), volume (divide
## = 1) and the final sum (1) -- fourteen rounding operations, each bounded by
## half an ulp of a quantity of order `V_room`. Rounded up to the next power of
## two for propagation headroom, the budget is 16 ulp. It is a NUMERICAL bound
## on `V_room`, never a physical tolerance, and the fixture reports the measured
## worst case so the budget can be seen to be loose rather than tuned to pass.
const VOLUME_CLOSURE_ROUNDING_BUDGET: int = 16

## Rounding budget for the ambient identity above, derived the same way: the
## gas constant (2), the mass-temperature product and sum (2), and the final
## divide and multiply (2) -- six roundings, rounded up to 8 ulp of
## `AIR_PRESSURE_REF_PA`. The identity is exact in real arithmetic; this bounds
## only its floating-point evaluation.
const AMBIENT_PRESSURE_ROUNDING_BUDGET: int = 8

## Compact observable layout used by the passive runtime shadow. The public
## `derive()` API still returns the documented Dictionary; these indices avoid
## constructing nested dictionaries hundreds of thousands of times merely to
## read the same scalar observables internally.
enum Observable {
	VALID,
	REASON,
	ROOM_VOLUME_M3,
	REFERENCE_TEMP_K,
	GAS_R_J_KG_K,
	PRESSURE_ABS_PA,
	UPPER_PRESENT,
	UPPER_TEMP_K,
	UPPER_DENSITY_KG_M3,
	UPPER_VOLUME_M3,
	LOWER_PRESENT,
	LOWER_TEMP_K,
	LOWER_DENSITY_KG_M3,
	LOWER_VOLUME_M3,
	INTERFACE_HEIGHT_M,
	INTERFACE_RAW_M,
	CLOSURE_ERROR_M3,
	CLOSURE_BUDGET_M3,
}

## Reason codes. `REASON_OK` is the only one a valid result carries.
const REASON_OK: String = "ok"
const REASON_NON_FINITE_INPUT: String = "non_finite_input"
const REASON_INVALID_GEOMETRY: String = "invalid_geometry"
const REASON_INVALID_AMBIENT: String = "invalid_ambient_temperature"
const REASON_NEGATIVE_MASS: String = "negative_mass"
const REASON_NEGATIVE_ENERGY: String = "negative_energy"
const REASON_ENERGY_WITHOUT_MASS: String = "energy_without_mass"
const REASON_BOTH_ZONES_ABSENT: String = "both_zones_absent"
const REASON_NON_FINITE_RESULT: String = "non_finite_result"
const REASON_NON_POSITIVE_PRESSURE: String = "non_positive_pressure"
const REASON_VOLUME_CLOSURE_OUT_OF_BUDGET: String = "volume_closure_out_of_budget"
const REASON_INTERFACE_OUT_OF_BUDGET: String = "interface_out_of_budget"


static func floor_area_from_volume_m2(room_volume_m3: float, room_height_m: float) -> float:
	## FALLIBLE AUXILIARY API, not a result. It returns NAN to signal "unusable
	## input" rather than guessing a floor area. That is the one place in this
	## file where NAN is a legitimate return value, and it is legitimate
	## precisely because this is not a `valid: true` result -- callers must test
	## it with `is_nan()` before passing the value to `derive()`, which will
	## reject a non-finite area anyway.
	##
	## The conversion is exact rather than approximate in this codebase:
	## `RoomModel` defines `volume_m3()` as `width_m * length_m * height_m` and
	## `floor_area_m2()` as `width_m * length_m`, so `V = A * h` is an identity
	## there, not a modelling assumption added here.
	if not is_finite(room_volume_m3) or not is_finite(room_height_m):
		return NAN
	if room_height_m <= 0.0 or room_volume_m3 <= 0.0:
		return NAN
	return room_volume_m3 / room_height_m


static func derive(
	upper_mass_kg: float,
	upper_energy_kj: float,
	lower_mass_kg: float,
	lower_energy_kj: float,
	floor_area_m2: float,
	room_height_m: float,
	ambient_temp_c: float
) -> Dictionary:
	## Public compatibility API. All arithmetic and validation live in the
	## compact primitive below; this function only materializes the documented
	## Dictionary shape for external callers.
	var observables: Array = derive_observables(
		upper_mass_kg, upper_energy_kj, lower_mass_kg, lower_energy_kj,
		floor_area_m2, room_height_m, ambient_temp_c)
	if not bool(observables[Observable.VALID]):
		return _invalid(String(observables[Observable.REASON]))
	return {
		"valid": true,
		"reason_code": REASON_OK,
		"room_volume_m3": float(observables[Observable.ROOM_VOLUME_M3]),
		"floor_area_m2": floor_area_m2,
		"room_height_m": room_height_m,
		"reference_temp_k": float(observables[Observable.REFERENCE_TEMP_K]),
		"gas_constant_j_kg_k": float(observables[Observable.GAS_R_J_KG_K]),
		"pressure_abs_pa": float(observables[Observable.PRESSURE_ABS_PA]),
		"upper": _zone(
			bool(observables[Observable.UPPER_PRESENT]), upper_mass_kg, upper_energy_kj,
			float(observables[Observable.UPPER_TEMP_K]),
			float(observables[Observable.UPPER_DENSITY_KG_M3]),
			float(observables[Observable.UPPER_VOLUME_M3])),
		"lower": _zone(
			bool(observables[Observable.LOWER_PRESENT]), lower_mass_kg, lower_energy_kj,
			float(observables[Observable.LOWER_TEMP_K]),
			float(observables[Observable.LOWER_DENSITY_KG_M3]),
			float(observables[Observable.LOWER_VOLUME_M3])),
		"interface_height_m": float(observables[Observable.INTERFACE_HEIGHT_M]),
		"interface_height_raw_m": float(observables[Observable.INTERFACE_RAW_M]),
		"volume_closure_error_m3": float(observables[Observable.CLOSURE_ERROR_M3]),
		"volume_closure_budget_m3": float(observables[Observable.CLOSURE_BUDGET_M3]),
		"mass_correction_kg": 0.0,
		"energy_correction_kj": 0.0,
		"thermal_limit_applied": false,
	}


static func derive_observables(
	upper_mass_kg: float,
	upper_energy_kj: float,
	lower_mass_kg: float,
	lower_energy_kj: float,
	floor_area_m2: float,
	room_height_m: float,
	ambient_temp_c: float
) -> Array:
	## The primitive. Pure: it reads its arguments and returns a compact Array.
	##
	## GEOMETRY CONTRACT. The caller passes `floor_area_m2` and `room_height_m`
	## explicitly; the room volume is `A * h`. The interface height is the depth
	## of the lower layer, `V_lower / A`, which assumes the room has a CONSTANT
	## HORIZONTAL CROSS-SECTION. That assumption is stated rather than hidden. It
	## is exact for every room this codebase can express, because `RoomModel`
	## carries only `width_m`, `length_m` and `height_m`; it would not be exact
	## for a room whose cross-section varied with height, and such a room cannot
	## currently be represented. The same form appears in the canonical solver at
	## `Phase3CoupledPressureSolver.gd:1261`, and is algebraically identical to
	## the legacy `h - V_upper / A` of `ZoneFireSolver.gd:267` precisely because
	## the volumes close.
	##
	## VALIDATION ORDER is fixed so that a state failing several checks always
	## reports the same reason code: non-finite inputs, geometry, ambient,
	## negative mass, negative energy, energy without mass, both zones absent,
	## then the numerical post-conditions.
	var invalid_input: String = _validate_inputs(
		upper_mass_kg, upper_energy_kj, lower_mass_kg, lower_energy_kj,
		floor_area_m2, room_height_m, ambient_temp_c)
	if invalid_input != REASON_OK:
		return _invalid_observables(invalid_input)

	var room_volume_m3: float = floor_area_m2 * room_height_m
	if not is_finite(room_volume_m3) or room_volume_m3 <= 0.0:
		return _invalid_observables(REASON_INVALID_GEOMETRY)

	var reference_temp_k: float = ambient_temp_c + KELVIN_OFFSET_C
	var gas_constant: float = AIR_PRESSURE_REF_PA \
			/ (AIR_DENSITY_REF_KG_M3 * reference_temp_k)
	if not is_finite(gas_constant) or gas_constant <= 0.0:
		return _invalid_observables(REASON_INVALID_AMBIENT)

	var upper_present: bool = upper_mass_kg > 0.0
	var lower_present: bool = lower_mass_kg > 0.0

	# A zone with no mass has no temperature. Nothing is invented for it, and
	# no field carrying an invented value is emitted for it later.
	var upper_temp_k: float = 0.0
	var lower_temp_k: float = 0.0
	if upper_present:
		upper_temp_k = reference_temp_k \
				+ upper_energy_kj / (upper_mass_kg * AIR_CP_KJ_KG_K)
	if lower_present:
		lower_temp_k = reference_temp_k \
				+ lower_energy_kj / (lower_mass_kg * AIR_CP_KJ_KG_K)

	# Only present zones contribute to the pressure sum. An absent zone
	# contributes exactly nothing, which is what makes the closure identity hold
	# unchanged when a zone is missing.
	var mass_temperature_sum: float = 0.0
	if upper_present:
		mass_temperature_sum += upper_mass_kg * upper_temp_k
	if lower_present:
		mass_temperature_sum += lower_mass_kg * lower_temp_k

	var pressure_abs_pa: float = (gas_constant / room_volume_m3) * mass_temperature_sum
	if not is_finite(pressure_abs_pa):
		return _invalid_observables(REASON_NON_FINITE_RESULT)
	if pressure_abs_pa <= 0.0:
		return _invalid_observables(REASON_NON_POSITIVE_PRESSURE)

	var upper_density_kg_m3: float = 0.0
	var lower_density_kg_m3: float = 0.0
	var upper_volume_m3: float = 0.0
	var lower_volume_m3: float = 0.0
	if upper_present:
		upper_density_kg_m3 = pressure_abs_pa / (gas_constant * upper_temp_k)
		upper_volume_m3 = upper_mass_kg / upper_density_kg_m3
	if lower_present:
		lower_density_kg_m3 = pressure_abs_pa / (gas_constant * lower_temp_k)
		lower_volume_m3 = lower_mass_kg / lower_density_kg_m3

	# Everything a valid result will carry must be finite here, and every
	# quantity a PRESENT zone carries must additionally be positive. A result
	# that cannot satisfy that is rejected rather than emitted with a hole in it.
	if not _present_zone_is_sound(upper_present, upper_temp_k,
			upper_density_kg_m3, upper_volume_m3):
		return _invalid_observables(REASON_NON_FINITE_RESULT)
	if not _present_zone_is_sound(lower_present, lower_temp_k,
			lower_density_kg_m3, lower_volume_m3):
		return _invalid_observables(REASON_NON_FINITE_RESULT)

	# The closure is algebraically exact; what is left is rounding. The budget is
	# a numerical bound on the room volume, not a physical tolerance, and a state
	# outside it fails closed rather than being nudged into range.
	var closure_error_m3: float = upper_volume_m3 + lower_volume_m3 - room_volume_m3
	var closure_budget_m3: float = float(VOLUME_CLOSURE_ROUNDING_BUDGET) \
			* DOUBLE_EPSILON * room_volume_m3
	if absf(closure_error_m3) > closure_budget_m3:
		return _invalid_observables(REASON_VOLUME_CLOSURE_OUT_OF_BUDGET)

	# INTERFACE. When one zone is absent the boundary is not a rounded quantity
	# at all: it is a geometric fact known from the presence state, so it is
	# returned EXACTLY. This corrects no mass and no energy; it simply refuses to
	# let a known boundary be reported as `h - 1e-16`.
	var interface_height_m: float = 0.0
	var interface_raw_m: float = 0.0
	if not upper_present:
		# No hot layer: the interface is the ceiling, exactly.
		interface_height_m = room_height_m
		interface_raw_m = room_height_m
	elif not lower_present:
		# No cold layer: the interface is the floor, exactly.
		interface_height_m = 0.0
		interface_raw_m = 0.0
	else:
		var interface_budget_m: float = float(VOLUME_CLOSURE_ROUNDING_BUDGET) \
				* DOUBLE_EPSILON * room_height_m
		interface_raw_m = lower_volume_m3 / floor_area_m2
		if not is_finite(interface_raw_m):
			return _invalid_observables(REASON_NON_FINITE_RESULT)
		if interface_raw_m < -interface_budget_m \
				or interface_raw_m > room_height_m + interface_budget_m:
			return _invalid_observables(REASON_INTERFACE_OUT_OF_BUDGET)
		interface_height_m = clampf(interface_raw_m, 0.0, room_height_m)

	return [
		true, REASON_OK, room_volume_m3, reference_temp_k, gas_constant,
		pressure_abs_pa, upper_present, upper_temp_k, upper_density_kg_m3,
		upper_volume_m3, lower_present, lower_temp_k, lower_density_kg_m3,
		lower_volume_m3, interface_height_m, interface_raw_m, closure_error_m3,
		closure_budget_m3,
	]


static func _zone(
	present: bool,
	mass_kg: float,
	energy_kj: float,
	temperature_k: float,
	density_kg_m3: float,
	volume_m3: float
) -> Dictionary:
	## An ABSENT zone carries only the fields that have a meaning for it. It has
	## no temperature, no density and no composition, so no such field is
	## emitted -- not as NAN, not as ambient, not as a reference value. A reader
	## that wants those must test `present` first, and will get a missing key
	## rather than a plausible number if it does not.
	if not present:
		return {
			"present": false,
			"mass_kg": 0.0,
			"energy_kj": 0.0,
			"volume_m3": 0.0,
		}
	return {
		"present": true,
		"mass_kg": mass_kg,
		"energy_kj": energy_kj,
		"temperature_k": temperature_k,
		"density_kg_m3": density_kg_m3,
		"volume_m3": volume_m3,
	}


static func _present_zone_is_sound(
	present: bool,
	temperature_k: float,
	density_kg_m3: float,
	volume_m3: float
) -> bool:
	## A present zone must carry a finite, strictly positive temperature and
	## density and a finite volume. An absent zone carries only exact zeros.
	if not present:
		return true
	if not is_finite(temperature_k) or temperature_k <= 0.0:
		return false
	if not is_finite(density_kg_m3) or density_kg_m3 <= 0.0:
		return false
	if not is_finite(volume_m3):
		return false
	return true


static func _validate_inputs(
	upper_mass_kg: float,
	upper_energy_kj: float,
	lower_mass_kg: float,
	lower_energy_kj: float,
	floor_area_m2: float,
	room_height_m: float,
	ambient_temp_c: float
) -> String:
	for value in [upper_mass_kg, upper_energy_kj, lower_mass_kg, lower_energy_kj,
			floor_area_m2, room_height_m, ambient_temp_c]:
		if not is_finite(value):
			return REASON_NON_FINITE_INPUT
	if floor_area_m2 <= 0.0 or room_height_m <= 0.0:
		return REASON_INVALID_GEOMETRY
	if ambient_temp_c + KELVIN_OFFSET_C <= 0.0:
		return REASON_INVALID_AMBIENT
	if upper_mass_kg < 0.0 or lower_mass_kg < 0.0:
		return REASON_NEGATIVE_MASS
	if upper_energy_kj < 0.0 or lower_energy_kj < 0.0:
		return REASON_NEGATIVE_ENERGY
	# Energy with no mass is an invalid state, not a repairable one. It is
	# rejected; the energy is not zeroed, not redistributed and not sent
	# anywhere.
	if upper_mass_kg == 0.0 and upper_energy_kj > 0.0:
		return REASON_ENERGY_WITHOUT_MASS
	if lower_mass_kg == 0.0 and lower_energy_kj > 0.0:
		return REASON_ENERGY_WITHOUT_MASS
	if upper_mass_kg == 0.0 and lower_mass_kg == 0.0:
		return REASON_BOTH_ZONES_ABSENT
	return REASON_OK


static func _invalid(reason_code: String) -> Dictionary:
	## Fail-closed result. It carries no derived quantity at all, so an invalid
	## state cannot be mistaken for a usable one by reading a field: there is no
	## pressure, no temperature, no density and no volume to read. The only
	## numbers present are the two exact zeros that say nothing was corrected.
	return {
		"valid": false,
		"reason_code": reason_code,
		"mass_correction_kg": 0.0,
		"energy_correction_kj": 0.0,
		"thermal_limit_applied": false,
	}


static func _invalid_observables(reason_code: String) -> Array:
	return [false, reason_code]

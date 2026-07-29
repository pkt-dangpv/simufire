extends RefCounted
class_name Phase3CoupledPressureSolver

# ============================================================
# F3.3v3h1: PURE COUPLED PRESSURE SOLVER
# ------------------------------------------------------------
# This component is a pure function library. It has no runtime
# call site, no exported flag, no persistent state and no access
# to RoomModel, BuildingModel, SimulationEngine or the canonical
# ledgers. It receives dictionaries and returns dictionaries.
#
# WHY IT EXISTS
# -------------
# F3.3v3g3 promoted a transport candidate whose acceptance factor
# minimised a residual built from the interior openings alone. The
# F3.3v3h0 attribution measured that the neglected owners are the
# same order of magnitude and opposite in sign, so the interior-only
# optimum leaves the entire neglected sum as a persistent, single
# signed forcing term. That compounds geometrically. No scalar
# multiplier can repair a sign-level modelling error.
#
# This solver removes the error at its source: the residual it
# reduces contains every pressure owner, and the directional flux
# is a consequence of the solved pressure field rather than a free
# variable that can be scaled.
#
# THE EXACT PROPERTY THIS RESTS ON
# --------------------------------
# The canonical EOS is exactly affine in room total mass and energy:
#
#     p_r = (R / V_r) * (M_r * T_ref + E_r / cp)
#     R   = P_ref / (rho_ref * T_ref)
#
# so the pressure subsystem needs ONE unknown per room, and owner
# contributions superpose with no cross terms. Species and O2 do not
# appear in the EOS at all, so they are advected after convergence
# with exactly zero feedback error and are deliberately absent here.
#
# WHY THE UNKNOWN IS A GAUGE PRESSURE
# -----------------------------------
# F3.3v3h2.5c captured a real solve that reached a normalized residual of
# 1.147e-12 against a 1e-12 tolerance and then could not finish. The Newton
# correction it still owed was about 5.5e-12 Pa, while one ulp of a double near
# 101325 Pa is 1.455e-11 Pa: the step was 0.38 ulp, so `p + damping * step` was
# not a different number, every damped trial evaluated the same state, and the
# line search exhausted with the answer already in sight.
#
# Iterating on the gauge pressure removes that floor. The unknown is order
# 10 Pa instead of 101325 Pa, so the same physical correction is thousands of
# ulps rather than a fraction of one. Two further cancellations disappear with
# it: the opening difference is now q_a - q_b directly instead of a subtraction
# of two numbers near 101325, and the EOS residual is assembled around a
# per-room reference mass rather than by subtracting the reference pressure
# from an implied absolute pressure. That last point matters - forming
# `implied_abs - reference_abs` would have reintroduced exactly the
# cancellation this change exists to remove.
#
# This is a change of variable, not of physics. The residual, the flux law, the
# Jacobian, the merit, the damping schedule, the tolerance, the regularization
# and the band quadrature are untouched, and `pressure_by_room` is rebuilt in
# absolute terms on the way out.
#
# WHAT IS IMPLICIT AND WHAT IS FROZEN
# -----------------------------------
# Implicit in the Newton solve:
#   - room pressures;
#   - every opening flux, interior and exterior, through dp(z).
# Frozen within one solve, as documented coefficients:
#   - the hydrostatic density profile and interface height;
#   - the donor-cell specific enthalpy carried by each band;
#   - the owner source terms (combustion, multisurface, any other),
#     which are supplied by the caller as totals over the step.
# Freezing the profile is a coefficient linearisation, not an owner
# omission: the sources are INSIDE the residual, which is precisely
# what F3.3v3g3 lacked.
# ============================================================

const AIR_PRESSURE_REF_PA: float = 101325.0
const AIR_DENSITY_REF_KG_M3: float = 1.2
const AIR_CP_KJ_KG_K: float = 1.0
const GRAVITY_M_S2: float = 9.81
const EXTERIOR_ID: int = -1
const MASS_EPS_KG: float = 1.0e-12
const VOLUME_EPS_M3: float = 1.0e-12

const DEFAULT_MAX_ITERATIONS: int = 24
## Convergence is measured as the mass-balance residual expressed as a
## fraction of the room's own inventory. That denominator is independent
## of the pressure iterate, so successive iterates stay comparable.
const DEFAULT_RESIDUAL_TOLERANCE: float = 1.0e-12
const DEFAULT_DP_REGULARIZATION_PA: float = 0.01
const DEFAULT_JACOBIAN_STEP_PA: float = 1.0e-3
const DEFAULT_BAND_SEGMENTS: int = 16
const DEFAULT_MAX_DAMPING_HALVINGS: int = 12

# ------------------------------------------------------------
# F3.3v3h2.5g: bounded Levenberg-Marquardt recovery.
#
# The ordinary line search accepts any strict decrease of the L-infinity
# residual. On the captured `corridor_chain` step that test rejects a Newton
# direction which fixes two rooms out of three, because it worsens the room
# that currently holds the maximum by 2.4%. No damping helps, so the solve dies
# with the answer still reachable.
#
# The recovery is reached ONLY from that dead end. It damps the SAME Jacobian
# toward steepest descent on a sum-of-squares merit and asks for a sufficient
# decrease of that merit - not merely a strict one, so a step that barely moves
# is rejected instead of being accepted forever.
#
# Bounded on purpose, and measured that way offline before being written here:
#   - at most one accepted recovery step per solve;
#   - at most five regularization strengths tried to find it;
#   - control returns to the ordinary Newton/L-infinity loop immediately;
#   - a second dead end fails as `damping_exhausted`, exactly as today.
# These are global constants. They are never per-case and never exposed.
# ------------------------------------------------------------
const LM_RESCUE_MAX_ACCEPTED_STEPS: int = 1
const LM_RESCUE_LAMBDA_LADDER: Array[float] = [1.0e-3, 1.0e-2, 1.0e-1, 1.0, 1.0e1]
## Armijo constant for the recovery merit. Sufficient decrease, not any decrease.
const LM_RESCUE_ARMIJO_C: float = 1.0e-4

# Failure codes. Zero means "no failure recorded".
const FAILURE_NONE: float = 0.0
const FAILURE_BAD_ARGUMENTS: float = 1.0
const FAILURE_BAD_ROOM_STATE: float = 2.0
const FAILURE_BAD_OPENING: float = 3.0
const FAILURE_BAD_SOURCE: float = 4.0
const FAILURE_SINGULAR_JACOBIAN: float = 5.0
const FAILURE_NOT_CONVERGED: float = 6.0
const FAILURE_NON_FINITE_STATE: float = 7.0
const FAILURE_COUNTERFLOW_VIOLATION: float = 8.0


## Solve one connected set of rooms for the pressure field that satisfies the
## complete end-of-step mass balance, then report the directional fluxes that
## field implies. Pure: nothing outside the returned dictionary is touched.
##
## `rooms`      room_key -> {volume_m3, floor_area_m2, height_m,
##                           upper_gas_kg, lower_gas_kg,
##                           upper_energy_kj, lower_energy_kj}
## `openings`   [{opening_id, room_a_id, room_b_id, bottom_m, top_m, width_m,
##                open_fraction, discharge_coeff}]  room_b_id may be EXTERIOR_ID
## `sources`    room_key -> {mass_kg, energy_kj}  owner totals over the step
## `dt`         physical timestep in seconds
func solve_coupled_pressure(
		rooms: Dictionary,
		openings: Array,
		sources: Dictionary,
		dt: float,
		reference_temp_c: float,
		options: Dictionary = {}
	) -> Dictionary:
	var result: Dictionary = _new_result()
	var context: Dictionary = _build_context(
		rooms, openings, sources, dt, reference_temp_c, options
	)
	if not bool(context.get("valid", false)):
		result["failure_code"] = float(context.get("failure_code", FAILURE_BAD_ARGUMENTS))
		return result
	var room_keys: Array = context["room_keys"]
	var room_count: int = room_keys.size()
	# The iterate is a GAUGE pressure throughout. The seed is assembled from the
	# reference mass rather than as `pressure_abs_pa - exterior`, so even the
	# starting point avoids the cancellation.
	var pressure: Array[float] = []
	for room_key in room_keys:
		pressure.append(float(context["rooms"][room_key]["gauge_pressure_pa"]))

	var evaluation: Dictionary = _evaluate(context, pressure)
	if not bool(evaluation.get("valid", false)):
		result["failure_code"] = FAILURE_NON_FINITE_STATE
		return result
	var norm: float = float(evaluation["normalized_residual"])
	result["residual_history"].append(norm)

	var tolerance: float = float(context["residual_tolerance"])
	var max_iterations: int = int(context["max_iterations"])
	var jacobian_step_pa: float = float(context["jacobian_step_pa"])
	var max_halvings: int = int(context["max_damping_halvings"])
	var iterations: int = 0
	var converged: bool = norm <= tolerance
	var rescue_budget_left: int = LM_RESCUE_MAX_ACCEPTED_STEPS

	while not converged and iterations < max_iterations:
		iterations += 1
		# Numerical Jacobian. With one unknown per room and a component that is
		# at most a handful of rooms wide, a dense difference quotient is both
		# affordable and far less error-prone than hand-differentiating the
		# band integration.
		var jacobian: Array = []
		for row_index in range(room_count):
			var row: Array[float] = []
			row.resize(room_count)
			jacobian.append(row)
		var jacobian_valid: bool = true
		for column in range(room_count):
			var perturbed: Array[float] = pressure.duplicate()
			perturbed[column] = perturbed[column] + jacobian_step_pa
			var forward: Dictionary = _evaluate(context, perturbed)
			if not bool(forward.get("valid", false)):
				jacobian_valid = false
				break
			for row_index in range(room_count):
				jacobian[row_index][column] = (
					float(forward["residual"][row_index])
					- float(evaluation["residual"][row_index])
				) / jacobian_step_pa
		if not jacobian_valid:
			result["failure_code"] = FAILURE_NON_FINITE_STATE
			result["iterations"] = float(iterations)
			return result

		var negative_residual: Array[float] = []
		for row_index in range(room_count):
			negative_residual.append(-float(evaluation["residual"][row_index]))
		var step: Array = _solve_linear_system(jacobian, negative_residual)
		if step.is_empty():
			result["failure_code"] = FAILURE_SINGULAR_JACOBIAN
			result["iterations"] = float(iterations)
			result["limiting_reason"] = "singular_jacobian"
			return result

		# Damped update: accept the first factor that actually reduces the
		# residual norm. A step that cannot reduce it at any damping is a
		# failure, never something to accept anyway.
		var damping: float = 1.0
		var halvings: int = 0
		var accepted: bool = false
		var candidate_pressure: Array[float] = pressure.duplicate()
		var candidate_evaluation: Dictionary = evaluation
		while halvings <= max_halvings:
			var trial: Array[float] = []
			for row_index in range(room_count):
				trial.append(pressure[row_index] + damping * float(step[row_index]))
			var trial_evaluation: Dictionary = _evaluate(context, trial)
			if bool(trial_evaluation.get("valid", false)) \
					and float(trial_evaluation["normalized_residual"]) < norm:
				candidate_pressure = trial
				candidate_evaluation = trial_evaluation
				accepted = true
				break
			damping *= 0.5
			halvings += 1
		if not accepted:
			# FAIL-ONLY RECOVERY. Reachable on exactly one path: the one where
			# this solver used to return `damping_exhausted`. Every successful
			# solve therefore executes byte-identical code, which is asserted
			# rather than assumed.
			var rescue: Dictionary = _try_lm_rescue(
				context, pressure, evaluation, jacobian, room_count,
				max_halvings, rescue_budget_left
			)
			result["rescue_attempted"] += 1.0
			result["rescue_trials"] += float(rescue.get("trials", 0.0))
			if not bool(rescue.get("accepted", false)):
				result["failure_code"] = FAILURE_NOT_CONVERGED
				result["iterations"] = float(iterations)
				result["limiting_reason"] = "damping_exhausted"
				result["pressure_by_room"] = _pressure_map(context, pressure)
				return result
			rescue_budget_left -= 1
			result["rescue_accepted"] += 1.0
			result["rescue_initial_norm"] = norm
			result["rescue_lambda"] = float(rescue["lambda"])
			pressure = rescue["pressure"]
			evaluation = rescue["evaluation"]
			norm = float(evaluation["normalized_residual"])
			result["rescue_final_norm"] = norm
			result["residual_history"].append(norm)
			result["damping_history"].append(float(rescue["damping"]))
			# A rescue is never convergence by itself. Control returns to the
			# ordinary Newton/L-infinity loop, which decides that as always.
			converged = norm <= tolerance
			continue
		pressure = candidate_pressure
		evaluation = candidate_evaluation
		norm = float(evaluation["normalized_residual"])
		result["residual_history"].append(norm)
		result["damping_history"].append(damping)
		converged = norm <= tolerance

	result["iterations"] = float(iterations)
	if not converged:
		result["failure_code"] = FAILURE_NOT_CONVERGED
		result["limiting_reason"] = "iteration_cap"
		result["pressure_by_room"] = _pressure_map(context, pressure)
		return result

	# Structural counterflow contract: whenever the neutral plane lies strictly
	# inside the opening span, both directions must carry strictly positive
	# mass. F3.3v3g3 produced exactly the state this rejects.
	var counterflow_violation_count: float = 0.0
	for raw_connection in evaluation["connections"]:
		var connection: Dictionary = raw_connection
		if not bool(connection.get("neutral_plane_inside", false)):
			continue
		if float(connection.get("a_to_b_kg", 0.0)) <= 0.0 \
				or float(connection.get("b_to_a_kg", 0.0)) <= 0.0:
			counterflow_violation_count += 1.0
	if counterflow_violation_count > 0.0:
		result["failure_code"] = FAILURE_COUNTERFLOW_VIOLATION
		result["counterflow_violation_count"] = counterflow_violation_count
		result["limiting_reason"] = "counterflow_violation"
		result["pressure_by_room"] = _pressure_map(context, pressure)
		return result

	result["valid"] = true
	result["converged"] = true
	result["limiting_reason"] = "converged"
	result["pressure_by_room"] = _pressure_map(context, pressure)
	result["gauge_pressure_by_room"] = _pressure_map(context, pressure, true)
	result["connections"] = evaluation["connections"]
	result["mass_by_room"] = evaluation["mass_by_room"]
	result["energy_by_room"] = evaluation["energy_by_room"]
	result["net_mass_by_room"] = evaluation["net_mass_by_room"]
	result["net_energy_by_room"] = evaluation["net_energy_by_room"]
	result["residual_pa_by_room"] = evaluation["residual_pa_by_room"]
	result["residual_kg_by_room"] = evaluation["residual_kg_by_room"]
	result["max_abs_residual_kg"] = float(evaluation["max_abs_residual_kg"])
	result["normalized_residual"] = norm
	result["throughput_normalized_residual"] = float(
		evaluation["throughput_normalized_residual"]
	)
	result["interior_transport_residual_kg"] = float(
		evaluation["interior_transport_residual_kg"]
	)
	result["regularization_active_count"] = float(
		evaluation["regularization_active_count"]
	)
	result["counterflow_connection_count"] = float(
		evaluation["counterflow_connection_count"]
	)
	return result


## Sum-of-squares recovery merit over the per-room normalized residuals. It is
## used ONLY to accept or reject a recovery step; convergence is still decided
## by the L-infinity measure against the unchanged tolerance.
func _rescue_merit(evaluation: Dictionary) -> float:
	var total: float = 0.0
	for room_key in evaluation["residual_kg_by_room"].keys():
		var value: float = float(
			evaluation["per_room_normalized"][room_key]
		)
		total += value * value
	return 0.5 * total


## One bounded Levenberg-Marquardt recovery step, or nothing.
##
## Damps the SAME Jacobian the Newton step came from - no new differencing, no
## new step size - toward steepest descent on `_rescue_merit`, walking a fixed
## ladder of regularization strengths and backtracking within each. Accepts the
## first trial that achieves a sufficient decrease of that merit.
func _try_lm_rescue(
		context: Dictionary,
		pressure: Array,
		evaluation: Dictionary,
		jacobian: Array,
		room_count: int,
		max_halvings: int,
		budget_left: int
	) -> Dictionary:
	var outcome: Dictionary = {
		"accepted": false, "trials": 0.0, "lambda": 0.0, "damping": 0.0,
	}
	if budget_left <= 0:
		return outcome
	var merit_before: float = _rescue_merit(evaluation)
	if merit_before <= 0.0 or not is_finite(merit_before):
		return outcome

	# Scale the added diagonal by the Jacobian's own magnitude so the ladder is
	# dimensionless and behaves the same whatever the component's conditioning.
	var jacobian_scale: float = 0.0
	for row_index in range(room_count):
		for column in range(room_count):
			jacobian_scale = maxf(
				jacobian_scale, absf(float(jacobian[row_index][column]))
			)
	if jacobian_scale <= 0.0:
		jacobian_scale = 1.0

	var negative_residual: Array[float] = []
	for row_index in range(room_count):
		negative_residual.append(-float(evaluation["residual"][row_index]))

	for lambda_value in LM_RESCUE_LAMBDA_LADDER:
		var damped: Array = []
		for row_index in range(room_count):
			var row: Array[float] = []
			row.resize(room_count)
			for column in range(room_count):
				row[column] = float(jacobian[row_index][column])
				if row_index == column:
					row[column] += lambda_value * jacobian_scale
			damped.append(row)
		var direction: Array = _solve_linear_system(damped, negative_residual)
		if direction.is_empty():
			continue
		var scale: float = 1.0
		for _halving in range(max_halvings + 1):
			var trial: Array[float] = []
			for row_index in range(room_count):
				trial.append(
					float(pressure[row_index]) + scale * float(direction[row_index])
				)
			var trial_evaluation: Dictionary = _evaluate(context, trial)
			outcome["trials"] += 1.0
			if bool(trial_evaluation.get("valid", false)):
				var merit_after: float = _rescue_merit(trial_evaluation)
				if merit_after <= (1.0 - LM_RESCUE_ARMIJO_C * scale) * merit_before:
					outcome["accepted"] = true
					outcome["lambda"] = lambda_value
					outcome["damping"] = scale
					outcome["pressure"] = trial
					outcome["evaluation"] = trial_evaluation
					return outcome
			scale *= 0.5
	return outcome


func _new_result() -> Dictionary:
	return {
		"valid": false,
		"converged": false,
		"failure_code": FAILURE_NONE,
		"limiting_reason": "invalid",
		"iterations": 0.0,
		"residual_history": [],
		"damping_history": [],
		"pressure_by_room": {},
		"gauge_pressure_by_room": {},
		"mass_by_room": {},
		"energy_by_room": {},
		"net_mass_by_room": {},
		"net_energy_by_room": {},
		"residual_pa_by_room": {},
		"residual_kg_by_room": {},
		"connections": [],
		"max_abs_residual_kg": 0.0,
		"normalized_residual": 0.0,
		"throughput_normalized_residual": 0.0,
		"interior_transport_residual_kg": 0.0,
		"regularization_active_count": 0.0,
		"counterflow_connection_count": 0.0,
		"counterflow_violation_count": 0.0,
		# F3.3v3h2.5g recovery telemetry. All zero unless the recovery path was
		# reached, which is itself the assertion that it never runs otherwise.
		"rescue_attempted": 0.0,
		"rescue_accepted": 0.0,
		"rescue_trials": 0.0,
		"rescue_initial_norm": 0.0,
		"rescue_final_norm": 0.0,
		"rescue_lambda": 0.0,
	}


# ------------------------------------------------------------
# context assembly
# ------------------------------------------------------------

func _build_context(
		rooms: Dictionary,
		openings: Array,
		sources: Dictionary,
		dt: float,
		reference_temp_c: float,
		options: Dictionary
	) -> Dictionary:
	var context: Dictionary = {"valid": false, "failure_code": FAILURE_BAD_ARGUMENTS}
	if rooms.is_empty() or not is_finite(dt) or dt <= 0.0 \
			or not is_finite(reference_temp_c):
		return context
	var reference_temp_k: float = reference_temp_c + 273.15
	if reference_temp_k <= 0.0:
		return context
	var gas_constant: float = AIR_PRESSURE_REF_PA \
			/ (AIR_DENSITY_REF_KG_M3 * reference_temp_k)

	# The gauge reference is the exterior pressure this solve was given, never a
	# hardcoded constant: every gauge quantity below is relative to it, so it has
	# to be one single well-defined value for the whole solve.
	var exterior_pressure_abs_pa: float = float(options.get(
		"exterior_pressure_abs_pa", AIR_PRESSURE_REF_PA
	))
	if not is_finite(exterior_pressure_abs_pa) or exterior_pressure_abs_pa <= 0.0:
		return context

	var room_keys: Array = rooms.keys()
	room_keys.sort()
	var index_by_key: Dictionary = {}
	var room_context: Dictionary = {}
	for position in range(room_keys.size()):
		var room_key: String = String(room_keys[position])
		index_by_key[room_key] = position
		var derived: Dictionary = _derive_room(
			rooms[room_keys[position]],
			reference_temp_k,
			gas_constant,
			exterior_pressure_abs_pa
		)
		if not bool(derived.get("valid", false)):
			context["failure_code"] = FAILURE_BAD_ROOM_STATE
			return context
		var source: Dictionary = sources.get(room_key, {})
		var source_mass_kg: float = float(source.get("mass_kg", 0.0))
		var source_energy_kj: float = float(source.get("energy_kj", 0.0))
		if not is_finite(source_mass_kg) or not is_finite(source_energy_kj):
			context["failure_code"] = FAILURE_BAD_SOURCE
			return context
		derived["source_mass_kg"] = source_mass_kg
		derived["source_energy_kj"] = source_energy_kj
		room_context[room_key] = derived

	var exterior_density_kg_m3: float = exterior_pressure_abs_pa \
			/ (gas_constant * reference_temp_k)
	var opening_context: Array[Dictionary] = []
	for raw_opening in openings:
		var opening: Dictionary = raw_opening
		var built: Dictionary = _build_opening(
			opening,
			room_context,
			index_by_key,
			exterior_density_kg_m3,
			dt
		)
		if not bool(built.get("valid", false)):
			context["failure_code"] = FAILURE_BAD_OPENING
			return context
		if built.get("skip", false):
			continue
		opening_context.append(built)
	# Deterministic order so the assembled Jacobian and the reported
	# connections never depend on the caller's iteration order.
	opening_context.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return String(left.get("sort_key", "")) < String(right.get("sort_key", ""))
	)

	context["valid"] = true
	context["failure_code"] = FAILURE_NONE
	context["room_keys"] = room_keys
	context["index_by_key"] = index_by_key
	context["rooms"] = room_context
	context["openings"] = opening_context
	context["dt"] = dt
	context["reference_temp_k"] = reference_temp_k
	context["gas_constant"] = gas_constant
	context["exterior_pressure_abs_pa"] = exterior_pressure_abs_pa
	context["residual_tolerance"] = maxf(
		0.0, float(options.get("residual_tolerance", DEFAULT_RESIDUAL_TOLERANCE))
	)
	context["max_iterations"] = maxi(
		1, int(options.get("max_iterations", DEFAULT_MAX_ITERATIONS))
	)
	context["dp_regularization_pa"] = maxf(
		1.0e-12,
		float(options.get("dp_regularization_pa", DEFAULT_DP_REGULARIZATION_PA))
	)
	context["jacobian_step_pa"] = maxf(
		1.0e-9, float(options.get("jacobian_step_pa", DEFAULT_JACOBIAN_STEP_PA))
	)
	context["band_segments"] = maxi(
		1, int(options.get("band_segments", DEFAULT_BAND_SEGMENTS))
	)
	context["max_damping_halvings"] = maxi(
		0, int(options.get("max_damping_halvings", DEFAULT_MAX_DAMPING_HALVINGS))
	)
	return context


func _derive_room(
		raw_state: Dictionary,
		reference_temp_k: float,
		gas_constant: float,
		exterior_pressure_abs_pa: float
	) -> Dictionary:
	var state: Dictionary = raw_state
	var volume_m3: float = float(state.get("volume_m3", 0.0))
	var floor_area_m2: float = float(state.get("floor_area_m2", 0.0))
	var height_m: float = float(state.get("height_m", 0.0))
	var upper_gas_kg: float = float(state.get("upper_gas_kg", 0.0))
	var lower_gas_kg: float = float(state.get("lower_gas_kg", 0.0))
	var upper_energy_kj: float = float(state.get("upper_energy_kj", 0.0))
	var lower_energy_kj: float = float(state.get("lower_energy_kj", 0.0))
	for value in [
		volume_m3, floor_area_m2, height_m,
		upper_gas_kg, lower_gas_kg, upper_energy_kj, lower_energy_kj
	]:
		if not is_finite(value):
			return {"valid": false}
	if volume_m3 <= VOLUME_EPS_M3 or floor_area_m2 <= 0.0 or height_m <= 0.0:
		return {"valid": false}
	if upper_gas_kg < 0.0 or lower_gas_kg < 0.0 \
			or upper_energy_kj < 0.0 or lower_energy_kj < 0.0:
		return {"valid": false}
	var total_mass_kg: float = upper_gas_kg + lower_gas_kg
	if total_mass_kg <= MASS_EPS_KG:
		return {"valid": false}
	# A zone holding energy but no mass has no defined temperature.
	if (upper_gas_kg <= MASS_EPS_KG and upper_energy_kj > 0.0) \
			or (lower_gas_kg <= MASS_EPS_KG and lower_energy_kj > 0.0):
		return {"valid": false}
	var total_energy_kj: float = upper_energy_kj + lower_energy_kj
	var upper_temp_k: float = reference_temp_k
	if upper_gas_kg > MASS_EPS_KG:
		upper_temp_k += upper_energy_kj / (upper_gas_kg * AIR_CP_KJ_KG_K)
	var lower_temp_k: float = reference_temp_k
	if lower_gas_kg > MASS_EPS_KG:
		lower_temp_k += lower_energy_kj / (lower_gas_kg * AIR_CP_KJ_KG_K)
	var pressure_abs_pa: float = gas_constant * (
		total_mass_kg * reference_temp_k + total_energy_kj / AIR_CP_KJ_KG_K
	) / volume_m3
	if not is_finite(pressure_abs_pa) or pressure_abs_pa <= 0.0:
		return {"valid": false}
	var upper_volume_m3: float = upper_gas_kg * gas_constant * upper_temp_k \
			/ pressure_abs_pa
	var lower_volume_m3: float = lower_gas_kg * gas_constant * lower_temp_k \
			/ pressure_abs_pa
	var interface_m: float = clampf(
		lower_volume_m3 / floor_area_m2, 0.0, height_m
	)
	# A degenerate zone has no inventory to move, but the hydrostatic integral
	# still needs a density at every height. Extend the occupied zone across it
	# without inventing mass, exactly as the canonical EOS path already does.
	var upper_density_kg_m3: float = upper_gas_kg / upper_volume_m3 \
			if upper_volume_m3 > VOLUME_EPS_M3 and upper_gas_kg > MASS_EPS_KG \
			else lower_gas_kg / maxf(VOLUME_EPS_M3, lower_volume_m3)
	var lower_density_kg_m3: float = lower_gas_kg / lower_volume_m3 \
			if lower_volume_m3 > VOLUME_EPS_M3 and lower_gas_kg > MASS_EPS_KG \
			else upper_gas_kg / maxf(VOLUME_EPS_M3, upper_volume_m3)
	# Mass that would sit at exactly the exterior pressure at the reference
	# temperature. Expressing the EOS around it is what lets the residual be
	# built in gauge terms without ever forming `implied_abs - exterior_abs`.
	var reference_mass_kg: float = exterior_pressure_abs_pa * volume_m3 \
			/ (gas_constant * reference_temp_k)
	var gauge_pressure_pa: float = gas_constant * (
		(total_mass_kg - reference_mass_kg) * reference_temp_k
		+ total_energy_kj / AIR_CP_KJ_KG_K
	) / volume_m3
	return {
		"valid": true,
		"volume_m3": volume_m3,
		"floor_area_m2": floor_area_m2,
		"height_m": height_m,
		"mass_kg": total_mass_kg,
		"reference_mass_kg": reference_mass_kg,
		"energy_kj": total_energy_kj,
		"pressure_abs_pa": pressure_abs_pa,
		"gauge_pressure_pa": gauge_pressure_pa,
		"interface_m": interface_m,
		"upper_density_kg_m3": maxf(0.0, upper_density_kg_m3),
		"lower_density_kg_m3": maxf(0.0, lower_density_kg_m3),
		# Donor-cell specific sensible enthalpy carried out of each zone.
		"upper_specific_kj_kg": upper_energy_kj / maxf(MASS_EPS_KG, upper_gas_kg),
		"lower_specific_kj_kg": lower_energy_kj / maxf(MASS_EPS_KG, lower_gas_kg),
	}


func _side_profile(
		room_key: String,
		room_context: Dictionary,
		exterior_density_kg_m3: float
	) -> Dictionary:
	if room_key.is_empty():
		return {
			"exterior": true,
			"interface_m": INF,
			"upper_density_kg_m3": exterior_density_kg_m3,
			"lower_density_kg_m3": exterior_density_kg_m3,
			"upper_specific_kj_kg": 0.0,
			"lower_specific_kj_kg": 0.0,
		}
	var room: Dictionary = room_context[room_key]
	return {
		"exterior": false,
		"interface_m": float(room["interface_m"]),
		"upper_density_kg_m3": float(room["upper_density_kg_m3"]),
		"lower_density_kg_m3": float(room["lower_density_kg_m3"]),
		"upper_specific_kj_kg": float(room["upper_specific_kj_kg"]),
		"lower_specific_kj_kg": float(room["lower_specific_kj_kg"]),
	}


func _build_opening(
		opening: Dictionary,
		room_context: Dictionary,
		index_by_key: Dictionary,
		exterior_density_kg_m3: float,
		dt: float
	) -> Dictionary:
	var room_a_id: int = int(opening.get("room_a_id", EXTERIOR_ID))
	var room_b_id: int = int(opening.get("room_b_id", EXTERIOR_ID))
	if room_a_id == room_b_id:
		return {"valid": false}
	var room_a_key: String = "" if room_a_id == EXTERIOR_ID else str(room_a_id)
	var room_b_key: String = "" if room_b_id == EXTERIOR_ID else str(room_b_id)
	if room_a_key.is_empty() and room_b_key.is_empty():
		return {"valid": false}
	if (not room_a_key.is_empty() and not room_context.has(room_a_key)) \
			or (not room_b_key.is_empty() and not room_context.has(room_b_key)):
		return {"valid": false}
	var bottom_m: float = float(opening.get("bottom_m", 0.0))
	var top_m: float = float(opening.get("top_m", 0.0))
	var width_m: float = float(opening.get("width_m", 0.0))
	var open_fraction: float = float(opening.get("open_fraction", 0.0))
	var discharge_coeff: float = float(opening.get("discharge_coeff", 0.0))
	for value in [bottom_m, top_m, width_m, open_fraction, discharge_coeff]:
		if not is_finite(value) or value < 0.0:
			return {"valid": false}
	if top_m <= bottom_m or width_m <= 0.0 or discharge_coeff <= 0.0:
		return {"valid": false}
	if open_fraction <= 0.0:
		# A shut opening is well formed and simply carries nothing.
		return {"valid": true, "skip": true}

	var side_a: Dictionary = _side_profile(
		room_a_key, room_context, exterior_density_kg_m3
	)
	var side_b: Dictionary = _side_profile(
		room_b_key, room_context, exterior_density_kg_m3
	)
	# Split the span at every density discontinuity so that within a band both
	# profiles are constant and dp(z) is exactly linear.
	var boundaries: Array[float] = [bottom_m, top_m]
	for interface_m in [
		float(side_a["interface_m"]), float(side_b["interface_m"])
	]:
		if is_finite(interface_m) and interface_m > bottom_m + 1.0e-9 \
				and interface_m < top_m - 1.0e-9:
			boundaries.append(interface_m)
	boundaries.sort()
	var unique_boundaries: Array[float] = []
	for boundary_m in boundaries:
		if unique_boundaries.is_empty() \
				or absf(boundary_m - unique_boundaries[-1]) > 1.0e-9:
			unique_boundaries.append(boundary_m)

	var bands: Array[Dictionary] = []
	for boundary_index in range(unique_boundaries.size() - 1):
		var z0: float = unique_boundaries[boundary_index]
		var z1: float = unique_boundaries[boundary_index + 1]
		bands.append({
			"z0": z0,
			"z1": z1,
			"hydrostatic_z0_pa": _hydrostatic_offset_pa(side_a, side_b, z0),
			"hydrostatic_z1_pa": _hydrostatic_offset_pa(side_a, side_b, z1),
			"density_a_kg_m3": _density_at(side_a, 0.5 * (z0 + z1)),
			"density_b_kg_m3": _density_at(side_b, 0.5 * (z0 + z1)),
			"specific_a_kj_kg": _specific_at(side_a, 0.5 * (z0 + z1)),
			"specific_b_kj_kg": _specific_at(side_b, 0.5 * (z0 + z1)),
		})
	var opening_id: int = int(opening.get("opening_id", -1))
	return {
		"valid": true,
		"skip": false,
		"sort_key": "%010d|%010d|%010d" % [
			opening_id, mini(room_a_id, room_b_id), maxi(room_a_id, room_b_id)
		],
		"opening_id": opening_id,
		"room_a_id": room_a_id,
		"room_b_id": room_b_id,
		"room_a_key": room_a_key,
		"room_b_key": room_b_key,
		"index_a": int(index_by_key.get(room_a_key, -1)),
		"index_b": int(index_by_key.get(room_b_key, -1)),
		"bottom_m": bottom_m,
		"top_m": top_m,
		"coefficient": discharge_coeff * width_m * open_fraction * dt,
		"bands": bands,
	}


## Hydrostatic part of dp(z), i.e. everything except the (p_a - p_b) term:
##   dp(z) = (p_a - p_b) - g * integral_0^z ( rho_a - rho_b ) dz'
func _hydrostatic_offset_pa(
		side_a: Dictionary,
		side_b: Dictionary,
		height_m: float
	) -> float:
	return -GRAVITY_M_S2 * (
		_column_mass_per_area(side_a, height_m)
		- _column_mass_per_area(side_b, height_m)
	)


func _column_mass_per_area(side: Dictionary, height_m: float) -> float:
	var interface_m: float = float(side["interface_m"])
	var lower_density_kg_m3: float = float(side["lower_density_kg_m3"])
	var upper_density_kg_m3: float = float(side["upper_density_kg_m3"])
	if not is_finite(interface_m) or height_m <= interface_m:
		return lower_density_kg_m3 * height_m
	return lower_density_kg_m3 * interface_m \
			+ upper_density_kg_m3 * (height_m - interface_m)


func _density_at(side: Dictionary, height_m: float) -> float:
	var interface_m: float = float(side["interface_m"])
	return float(side["lower_density_kg_m3"]) \
			if (not is_finite(interface_m) or height_m <= interface_m) \
			else float(side["upper_density_kg_m3"])


func _specific_at(side: Dictionary, height_m: float) -> float:
	var interface_m: float = float(side["interface_m"])
	return float(side["lower_specific_kj_kg"]) \
			if (not is_finite(interface_m) or height_m <= interface_m) \
			else float(side["upper_specific_kj_kg"])


# ------------------------------------------------------------
# residual
# ------------------------------------------------------------

func _evaluate(context: Dictionary, pressure: Array) -> Dictionary:
	var room_keys: Array = context["room_keys"]
	var room_count: int = room_keys.size()
	var rooms: Dictionary = context["rooms"]
	var gas_constant: float = float(context["gas_constant"])
	var reference_temp_k: float = float(context["reference_temp_k"])
	# `pressure` holds GAUGE pressures relative to the exterior. The physical
	# validity test is still on the absolute pressure they represent.
	var exterior_pressure_abs_pa: float = float(
		context["exterior_pressure_abs_pa"]
	)
	for value in pressure:
		if not is_finite(float(value)) \
				or float(value) + exterior_pressure_abs_pa <= 0.0:
			return {"valid": false}

	var net_mass_kg: Array[float] = []
	var net_energy_kj: Array[float] = []
	var gross_mass_kg: Array[float] = []
	net_mass_kg.resize(room_count)
	net_energy_kj.resize(room_count)
	gross_mass_kg.resize(room_count)
	for index in range(room_count):
		net_mass_kg[index] = 0.0
		net_energy_kj[index] = 0.0
		gross_mass_kg[index] = 0.0

	var connections: Array[Dictionary] = []
	var regularization_active_count: float = 0.0
	var counterflow_connection_count: float = 0.0
	var interior_transport_residual_kg: float = 0.0
	for raw_opening in context["openings"]:
		var opening: Dictionary = raw_opening
		var index_a: int = int(opening["index_a"])
		var index_b: int = int(opening["index_b"])
		# Gauge by construction, so the exterior is exactly zero and the opening
		# difference is a direct subtraction of two small numbers instead of two
		# numbers near ambient.
		var pressure_a_pa: float = float(pressure[index_a]) if index_a >= 0 else 0.0
		var pressure_b_pa: float = float(pressure[index_b]) if index_b >= 0 else 0.0
		var flux: Dictionary = _integrate_opening(
			opening,
			pressure_a_pa - pressure_b_pa,
			float(context["dp_regularization_pa"]),
			int(context["band_segments"])
		)
		if not bool(flux.get("valid", false)):
			return {"valid": false}
		regularization_active_count += float(flux["regularization_active_count"])
		var a_to_b_kg: float = float(flux["a_to_b_kg"])
		var b_to_a_kg: float = float(flux["b_to_a_kg"])
		var a_to_b_kj: float = float(flux["a_to_b_kj"])
		var b_to_a_kj: float = float(flux["b_to_a_kj"])
		# Antisymmetry is structural: one integration produces both directions
		# and each endpoint receives exactly what the other gives up.
		if index_a >= 0:
			net_mass_kg[index_a] += b_to_a_kg - a_to_b_kg
			net_energy_kj[index_a] += b_to_a_kj - a_to_b_kj
			gross_mass_kg[index_a] += a_to_b_kg + b_to_a_kg
		if index_b >= 0:
			net_mass_kg[index_b] += a_to_b_kg - b_to_a_kg
			net_energy_kj[index_b] += a_to_b_kj - b_to_a_kj
			gross_mass_kg[index_b] += a_to_b_kg + b_to_a_kg
		if bool(flux["neutral_plane_inside"]):
			counterflow_connection_count += 1.0
		connections.append({
			"opening_id": int(opening["opening_id"]),
			"room_a_id": int(opening["room_a_id"]),
			"room_b_id": int(opening["room_b_id"]),
			"delta_p_pa": pressure_a_pa - pressure_b_pa,
			"a_to_b_kg": a_to_b_kg,
			"b_to_a_kg": b_to_a_kg,
			"a_to_b_kj": a_to_b_kj,
			"b_to_a_kj": b_to_a_kj,
			"gross_mass_kg": a_to_b_kg + b_to_a_kg,
			"net_mass_a_to_b_kg": a_to_b_kg - b_to_a_kg,
			"neutral_plane_m": float(flux["neutral_plane_m"]),
			"neutral_plane_inside": bool(flux["neutral_plane_inside"]),
			"regularization_active_count": float(
				flux["regularization_active_count"]
			),
		})

	var residual_pa: Array[float] = []
	var residual_pa_by_room: Dictionary = {}
	var residual_kg_by_room: Dictionary = {}
	var per_room_normalized: Dictionary = {}
	var mass_by_room: Dictionary = {}
	var energy_by_room: Dictionary = {}
	var net_mass_by_room: Dictionary = {}
	var net_energy_by_room: Dictionary = {}
	var normalized_residual: float = 0.0
	var throughput_normalized_residual: float = 0.0
	var max_abs_residual_kg: float = 0.0
	residual_pa.resize(room_count)
	for index in range(room_count):
		var room_key: String = String(room_keys[index])
		var room: Dictionary = rooms[room_key]
		var volume_m3: float = float(room["volume_m3"])
		var balance_mass_kg: float = float(room["mass_kg"]) \
				+ float(room["source_mass_kg"]) + net_mass_kg[index]
		var balance_energy_kj: float = float(room["energy_kj"]) \
				+ float(room["source_energy_kj"]) + net_energy_kj[index]
		# The residual is the EOS pressure implied by the complete end-of-step
		# balance minus the pressure iterate. Every owner is inside it: the
		# opening fluxes through net_*, and combustion/multisurface/anything
		# else through source_*.
		#
		# Built around the room's reference mass so that both terms are already
		# gauge quantities. Computing an absolute implied pressure and then
		# subtracting the exterior would discard about four significant digits
		# to cancellation, which is the defect this formulation removes.
		var implied_pressure_pa: float = gas_constant * (
			(balance_mass_kg - float(room["reference_mass_kg"])) * reference_temp_k
			+ balance_energy_kj / AIR_CP_KJ_KG_K
		) / volume_m3
		var residual: float = implied_pressure_pa - float(pressure[index])
		if not is_finite(residual):
			return {"valid": false}
		residual_pa[index] = residual
		var pressure_per_kg: float = gas_constant * reference_temp_k / volume_m3
		var residual_kg: float = residual / pressure_per_kg
		# The convergence measure and the line-search merit function must be
		# comparable BETWEEN iterates, so the denominator has to be independent
		# of the pressure iterate. Room inventory is; gross throughput is not,
		# because it collapses as the solve approaches equilibrium and would
		# make a genuinely improving step look worse.
		var room_normalized: float = absf(residual_kg) \
				/ maxf(MASS_EPS_KG, float(room["mass_kg"]))
		normalized_residual = maxf(normalized_residual, room_normalized)
		# Kept per room as well: the L-infinity measure above decides
		# convergence, while the F3.3v3h2.5g recovery needs the whole vector to
		# form its sum-of-squares merit.
		per_room_normalized[room_key] = room_normalized
		# Reported separately: closure against what actually moved. This is the
		# physically meaningful number where the net is a large cancellation,
		# but it is telemetry only and never drives an accept/reject decision.
		var throughput_kg: float = gross_mass_kg[index] \
				+ absf(float(room["source_mass_kg"])) \
				+ absf(float(room["source_energy_kj"])) \
						/ (AIR_CP_KJ_KG_K * reference_temp_k) \
				+ MASS_EPS_KG
		throughput_normalized_residual = maxf(
			throughput_normalized_residual, absf(residual_kg) / throughput_kg
		)
		max_abs_residual_kg = maxf(max_abs_residual_kg, absf(residual_kg))
		residual_pa_by_room[room_key] = residual
		residual_kg_by_room[room_key] = residual_kg
		mass_by_room[room_key] = balance_mass_kg
		energy_by_room[room_key] = balance_energy_kj
		net_mass_by_room[room_key] = net_mass_kg[index]
		net_energy_by_room[room_key] = net_energy_kj[index]
		interior_transport_residual_kg += net_mass_kg[index]

	return {
		"valid": true,
		"residual": residual_pa,
		"residual_pa_by_room": residual_pa_by_room,
		"residual_kg_by_room": residual_kg_by_room,
		"per_room_normalized": per_room_normalized,
		"mass_by_room": mass_by_room,
		"energy_by_room": energy_by_room,
		"net_mass_by_room": net_mass_by_room,
		"net_energy_by_room": net_energy_by_room,
		"connections": connections,
		"normalized_residual": normalized_residual,
		"throughput_normalized_residual": throughput_normalized_residual,
		"max_abs_residual_kg": max_abs_residual_kg,
		# For a fully interior component this is zero to round-off: every
		# route debits one room and credits another.
		"interior_transport_residual_kg": interior_transport_residual_kg,
		"regularization_active_count": regularization_active_count,
		"counterflow_connection_count": counterflow_connection_count,
	}


## Integrate the orifice law over the opening span at the supplied pressure
## difference. The neutral plane is found from the sign change of dp(z), and
## each side of it is integrated separately, so counterflow is a structural
## consequence rather than an imposed constraint.
func _integrate_opening(
		opening: Dictionary,
		delta_p_pa: float,
		dp_regularization_pa: float,
		band_segments: int
	) -> Dictionary:
	var a_to_b_kg: float = 0.0
	var b_to_a_kg: float = 0.0
	var a_to_b_kj: float = 0.0
	var b_to_a_kj: float = 0.0
	var regularization_active_count: float = 0.0
	var neutral_plane_m: float = NAN
	var neutral_plane_inside: bool = false
	var coefficient: float = float(opening["coefficient"])
	var bottom_m: float = float(opening["bottom_m"])
	var top_m: float = float(opening["top_m"])
	for raw_band in opening["bands"]:
		var band: Dictionary = raw_band
		var z0: float = float(band["z0"])
		var z1: float = float(band["z1"])
		var dp0: float = delta_p_pa + float(band["hydrostatic_z0_pa"])
		var dp1: float = delta_p_pa + float(band["hydrostatic_z1_pa"])
		if not is_finite(dp0) or not is_finite(dp1):
			return {"valid": false}
		var sub_bands: Array = []
		if dp0 * dp1 < 0.0:
			# dp(z) is linear inside a band, so the crossing is exact.
			var crossing_fraction: float = absf(dp0) \
					/ maxf(1.0e-30, absf(dp0) + absf(dp1))
			var crossing_m: float = lerpf(z0, z1, crossing_fraction)
			neutral_plane_m = crossing_m
			if crossing_m > bottom_m + 1.0e-9 and crossing_m < top_m - 1.0e-9:
				neutral_plane_inside = true
			sub_bands.append({"z0": z0, "z1": crossing_m, "dp0": dp0, "dp1": 0.0})
			sub_bands.append({"z0": crossing_m, "z1": z1, "dp0": 0.0, "dp1": dp1})
		else:
			sub_bands.append({"z0": z0, "z1": z1, "dp0": dp0, "dp1": dp1})
		for raw_sub_band in sub_bands:
			var sub_band: Dictionary = raw_sub_band
			var span_m: float = float(sub_band["z1"]) - float(sub_band["z0"])
			if span_m <= 1.0e-12:
				continue
			var segment_height_m: float = span_m / float(band_segments)
			for segment_index in range(band_segments):
				var mid_fraction: float = (float(segment_index) + 0.5) \
						/ float(band_segments)
				var dp_pa: float = lerpf(
					float(sub_band["dp0"]), float(sub_band["dp1"]), mid_fraction
				)
				var from_a: bool = dp_pa > 0.0
				var density_kg_m3: float = float(band["density_a_kg_m3"]) \
						if from_a else float(band["density_b_kg_m3"])
				var specific_kj_kg: float = float(band["specific_a_kj_kg"]) \
						if from_a else float(band["specific_b_kj_kg"])
				var factor: Dictionary = _regularized_flux_factor(
					dp_pa, density_kg_m3, dp_regularization_pa
				)
				if bool(factor["regularized"]):
					regularization_active_count += 1.0
				var mass_kg: float = coefficient * segment_height_m \
						* float(factor["magnitude"])
				if not is_finite(mass_kg):
					return {"valid": false}
				if dp_pa >= 0.0:
					a_to_b_kg += mass_kg
					a_to_b_kj += mass_kg * specific_kj_kg
				else:
					b_to_a_kg += mass_kg
					b_to_a_kj += mass_kg * specific_kj_kg
	return {
		"valid": true,
		"a_to_b_kg": a_to_b_kg,
		"b_to_a_kg": b_to_a_kg,
		"a_to_b_kj": a_to_b_kj,
		"b_to_a_kj": b_to_a_kj,
		"neutral_plane_m": neutral_plane_m,
		"neutral_plane_inside": neutral_plane_inside,
		"regularization_active_count": regularization_active_count,
	}


## sqrt(2 rho |dp|), linearised below `dp_regularization_pa`.
##
## The orifice derivative d(mdot)/d(dp) = mdot / (2 dp) is unbounded as dp -> 0,
## and F3.3v3g2 measured the pressure-crossing regime active in 93% of steps, so
## that is the normal regime rather than an edge case. The blend is C0 and has a
## bounded derivative at the origin. `dp_regularization_pa` is a global numerical
## constant justified by Jacobian conditioning; it is never a per-case knob and
## never fitted to a checkpoint.
func _regularized_flux_factor(
		delta_p_pa: float,
		density_kg_m3: float,
		dp_regularization_pa: float
	) -> Dictionary:
	var density: float = maxf(0.0, density_kg_m3)
	var magnitude_pa: float = absf(delta_p_pa)
	if magnitude_pa >= dp_regularization_pa:
		return {
			"magnitude": sqrt(2.0 * density * magnitude_pa),
			"regularized": false,
		}
	return {
		"magnitude": sqrt(2.0 * density * dp_regularization_pa)
				* (magnitude_pa / dp_regularization_pa),
		"regularized": true,
	}


## The solve carries gauge pressures, so the absolute field is reconstructed
## here and nowhere else. The returned contract is unchanged: callers still get
## `pressure_by_room` in absolute pascals and `gauge_pressure_by_room` relative
## to the exterior reference this solve was given.
func _pressure_map(
		context: Dictionary,
		pressure: Array,
		gauge: bool = false
	) -> Dictionary:
	var mapped: Dictionary = {}
	var room_keys: Array = context["room_keys"]
	var exterior_pressure_abs_pa: float = float(
		context["exterior_pressure_abs_pa"]
	)
	for index in range(room_keys.size()):
		var value: float = float(pressure[index])
		mapped[String(room_keys[index])] = value \
				if gauge else value + exterior_pressure_abs_pa
	return mapped


# ------------------------------------------------------------
# dense linear solve
# ------------------------------------------------------------

## Gaussian elimination with partial pivoting. Returns an empty array when the
## matrix is singular, so the caller fails closed rather than stepping on noise.
func _solve_linear_system(matrix: Array, rhs: Array) -> Array:
	var size: int = rhs.size()
	if size == 0 or matrix.size() != size:
		return []
	var augmented: Array = []
	for row_index in range(size):
		var row: Array[float] = []
		for column in range(size):
			var value: float = float(matrix[row_index][column])
			if not is_finite(value):
				return []
			row.append(value)
		var rhs_value: float = float(rhs[row_index])
		if not is_finite(rhs_value):
			return []
		row.append(rhs_value)
		augmented.append(row)
	for pivot_index in range(size):
		var best_row: int = pivot_index
		var best_magnitude: float = absf(float(augmented[pivot_index][pivot_index]))
		for row_index in range(pivot_index + 1, size):
			var magnitude: float = absf(float(augmented[row_index][pivot_index]))
			if magnitude > best_magnitude:
				best_magnitude = magnitude
				best_row = row_index
		if best_magnitude <= 1.0e-14:
			return []
		if best_row != pivot_index:
			var swap: Array = augmented[pivot_index]
			augmented[pivot_index] = augmented[best_row]
			augmented[best_row] = swap
		var pivot_value: float = float(augmented[pivot_index][pivot_index])
		for row_index in range(pivot_index + 1, size):
			var factor: float = float(augmented[row_index][pivot_index]) / pivot_value
			if factor == 0.0:
				continue
			for column in range(pivot_index, size + 1):
				augmented[row_index][column] = float(augmented[row_index][column]) \
						- factor * float(augmented[pivot_index][column])
	var solution: Array[float] = []
	solution.resize(size)
	for row_index in range(size - 1, -1, -1):
		var accumulator: float = float(augmented[row_index][size])
		for column in range(row_index + 1, size):
			accumulator -= float(augmented[row_index][column]) * solution[column]
		var diagonal: float = float(augmented[row_index][row_index])
		if absf(diagonal) <= 1.0e-14:
			return []
		solution[row_index] = accumulator / diagonal
		if not is_finite(solution[row_index]):
			return []
	return solution

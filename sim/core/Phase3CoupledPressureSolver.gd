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

## F2.2A es el evaluador AUTORITATIVO de las ecuaciones locales. El solver
## conserva su propia aritmetica interna para construir el Jacobiano, pero
## ningun candidato se acepta ni se devuelve sin que F2.2A lo confirme.
const CompartmentPressureEquationsScript = preload(
	"res://sim/core/CompartmentPressureEquations.gd"
)

const AIR_PRESSURE_REF_PA: float = 101325.0
const AIR_DENSITY_REF_KG_M3: float = 1.2
const AIR_CP_KJ_KG_K: float = 1.0
const GRAVITY_M_S2: float = 9.81
const EXTERIOR_ID: int = -1
## F3.3v3h3.2a reporting labels. They match Phase3ZoneMassSystem's zone names so
## the decomposition can later feed the atomic route primitives unchanged.
const ZONE_UPPER: String = "upper"
const ZONE_LOWER: String = "lower"
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

## F2.2B: tolerancias fisicas de la convergencia canonica. Son globales y
## justificadas por la precision doble, nunca knobs por caso.
const DEFAULT_PRESSURE_TOLERANCE_PA: float = 1.0e-6
const DEFAULT_MASS_TOLERANCE_KG: float = 1.0e-9
const DEFAULT_ENERGY_TOLERANCE_KJ: float = 1.0e-6

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

# ------------------------------------------------------------
# F3.3v3h2.5j: accepted-cycle safeguard.
#
# H2.5i measured a real `iteration_cap` where the ordinary L-infinity line
# search accepted 22 consecutive full Newton steps even though the opening
# pressure difference and all 16 quadrature donors flipped direction every
# iteration. Successive Newton directions had cosine ~= -1, while the actual
# sum-of-squares improvement was at most a few percent of the linear model's
# prediction. The strict `< norm` test therefore kept a period-2 zigzag alive.
#
# This guard does not replace the ordinary line search. It only recognizes two
# consecutive, already-accepted full steps that are both poor model matches and
# nearly opposite. That state is redirected once to the same bounded LM rescue
# used by H2.5g. A declined rescue preserves the accepted Newton candidate, so
# the safeguard cannot turn an improving legacy step into a new failure.
# ------------------------------------------------------------
const CYCLE_GUARD_MIN_MODEL_GAIN_RATIO: float = 0.05
const CYCLE_GUARD_MAX_STEP_COSINE: float = -0.99

# ------------------------------------------------------------
# F3.3v3h2.5m: analytic half step for the period-2 orbit.
#
# H2.5m traced the post-budget cycle and found it is not a numerical artifact.
# The differencing width is irrelevant (the Newton direction is stable to a
# cosine of 1.000000 across four decades of h), the connections sit three
# orders above the dp regularization, and the regularization never activates.
# What the trace does show is that the merit along the Newton direction has its
# minimum at alpha = 0.50 exactly, and that it is LINEAR in |alpha - 0.5|:
# fitting `merit ~ |alpha - 0.5|^p` gives p = 1.0014 at R^2 = 0.9999, so the
# residual behaves as |u|^(1/2) along that line. That is the orifice law
# sqrt(2 rho dp) appearing in the convergence structure.
#
# For F(u) = C sign(u) |u|^(1/2) the Newton correction is exactly -2u, so
#
#     u_next = u - 2u = -u
#
# a period-2 orbit whose multiplier is exactly -1: it never converges and never
# diverges. A damped step with factor theta gives u_next = (1 - 2 theta) u, so
# theta = 1/2 annihilates the orbit in a single step. The value is derived, not
# fitted to any corpus, and the measured minimum agrees with it to the
# resolution of the scan.
#
# Bounded exactly like the H2.5g recovery:
#   - reachable ONLY after `cycle_detected`;
#   - reuses the Newton direction already computed, no new differencing;
#   - accepted only on a strictly decreasing L-infinity residual;
#   - declined, it leaves the state untouched and the existing cycle guard and
#     LM rescue run exactly as before;
#   - it neither consumes nor extends the LM rescue budget;
#   - it is never convergence by itself.
# ------------------------------------------------------------
const CYCLE_ANALYTIC_HALF_STEP: float = 0.5

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
	var previous_full_step: Array = []
	var previous_full_step_gain_ratio: float = INF
	# H2.5l-A passive observation only. These norms never participate in a
	# numerical decision; they measure whether a detected period-2 sequence is
	# contracting after the one-step rescue budget has already been spent.
	var previous_full_step_norm: float = NAN
	var previous_previous_full_step_norm: float = NAN
	# H2.5l-B: consecutive post-budget cycle streak. Never governs behaviour.
	var post_budget_cycle_streak: int = 0

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
			# H2.10 fail-only recovery. The shipped forward Jacobian and its
			# line search have already failed before this branch is reachable.
			# Probe both unilateral sides and refine the width until two
			# consecutive branch-consistent Jacobians independently produce a
			# strict L-infinity decrease. Failure leaves the state untouched and
			# falls through to the existing LM recovery below.
			result["adaptive_jacobian_attempt_total"] += 1.0
			var adaptive: Dictionary = _try_adaptive_branch_jacobian_recovery(
				context, pressure, evaluation, room_count,
				jacobian_step_pa, max_halvings
			)
			for adaptive_field in [
				"columns_forward_total", "columns_backward_total",
				"columns_reduced_total", "branch_crossing_avoided_total",
				"derivative_consistency_fail_total",
			]:
				result["adaptive_jacobian_" + adaptive_field] += float(
					adaptive.get(adaptive_field, 0.0)
				)
			var adaptive_min_step: float = float(
				adaptive.get("min_effective_jacobian_step_pa", 0.0)
			)
			if adaptive_min_step > 0.0:
				var prior_adaptive_min: float = float(
					result["adaptive_jacobian_min_effective_step_pa"]
				)
				result["adaptive_jacobian_min_effective_step_pa"] = (
					adaptive_min_step if prior_adaptive_min <= 0.0
					else minf(prior_adaptive_min, adaptive_min_step)
				)
			if bool(adaptive.get("accepted", false)):
				result["adaptive_jacobian_accept_total"] += 1.0
				pressure = adaptive["pressure"]
				evaluation = adaptive["evaluation"]
				norm = float(evaluation["normalized_residual"])
				result["residual_history"].append(norm)
				result["damping_history"].append(float(adaptive["damping"]))
				previous_full_step.clear()
				previous_full_step_gain_ratio = INF
				previous_full_step_norm = NAN
				previous_previous_full_step_norm = NAN
				post_budget_cycle_streak = 0
				converged = norm <= tolerance
				continue
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
			previous_full_step.clear()
			previous_full_step_gain_ratio = INF
			previous_full_step_norm = NAN
			previous_previous_full_step_norm = NAN
			post_budget_cycle_streak = 0
			# A rescue is never convergence by itself. Control returns to the
			# ordinary Newton/L-infinity loop, which decides that as always.
			converged = norm <= tolerance
			continue

		var model_gain_ratio: float = _model_gain_ratio(
			context, evaluation, candidate_evaluation, jacobian, step, damping
		)
		var step_cosine: float = 1.0
		var cycle_detected: bool = false
		var cycle_min_gain_ratio: float = INF
		var cycle_gain_alternates: bool = false
		if damping == 1.0 and not previous_full_step.is_empty():
			step_cosine = _step_cosine(previous_full_step, step)
			# F3.3v3h2.8: the gain ratio of a period-2 orbit has period two too.
			#
			# H2.5j required BOTH consecutive gain ratios to be poor. That held
			# on the corridor capture it was written from, where the pair was
			# 0.00090 and 0.0084. H2.7 replayed four large-network captures and
			# found the pair straddles the threshold instead - about 0.08 on one
			# phase and -0.01 on the other - while the step cosine sits at
			# -0.9999 throughout. The conjunction therefore never fired, the
			# orbit ran for 17 to 34 iterations, and the solve died at the cap.
			#
			# Taking the minimum asks the question the sequence can actually
			# answer: does EITHER phase of the orbit show that the linear model
			# is not being delivered? The threshold is unchanged, and so is
			# every geometric condition - two accepted full steps, a previous
			# step to compare against, and a period-2 cosine.
			cycle_min_gain_ratio = minf(
				previous_full_step_gain_ratio, model_gain_ratio
			)
			cycle_detected = (
				cycle_min_gain_ratio < CYCLE_GUARD_MIN_MODEL_GAIN_RATIO
				and step_cosine < CYCLE_GUARD_MAX_STEP_COSINE
			)
			# Passive split of the population, so the two regimes stay legible.
			cycle_gain_alternates = cycle_detected and maxf(
				previous_full_step_gain_ratio, model_gain_ratio
			) >= CYCLE_GUARD_MIN_MODEL_GAIN_RATIO
		# Observation is deliberately outside the rescue-budget gate. H2.5k
		# proved that a second cycle can appear after the only authorised rescue
		# has been accepted; previously that cycle was no longer even counted.
		if cycle_detected:
			result["cycle_detect_total"] += 1.0
			if cycle_gain_alternates:
				result["cycle_detect_alternating_gain_total"] += 1.0
			else:
				result["cycle_detect_both_phases_low_total"] += 1.0
			if rescue_budget_left <= 0:
				result["cycle_detect_after_budget_total"] += 1.0
				post_budget_cycle_streak += 1
				result["post_budget_cycle_streak_max"] = maxf(
					float(result["post_budget_cycle_streak_max"]),
					float(post_budget_cycle_streak)
				)
			if is_finite(previous_previous_full_step_norm):
				var contraction: float = _step_norm(step) / maxf(
					previous_previous_full_step_norm, 1.0e-300
				)
				if is_finite(contraction):
					var prior_min: float = float(
						result["cycle_contraction_min"]
					)
					result["cycle_contraction_min"] = contraction \
							if prior_min <= 0.0 \
							else minf(prior_min, contraction)
					result["cycle_contraction_max"] = maxf(
						float(result["cycle_contraction_max"]), contraction
					)
		else:
			post_budget_cycle_streak = 0
		# H2.5m analytic half step. Tried before the LM guard because it is the
		# closed-form answer to exactly this orbit and costs one evaluation of
		# the direction already in hand. It has no budget of its own and cannot
		# touch the LM budget; if it declines, control falls through to the
		# unchanged H2.5j/H2.5g path.
		if cycle_detected:
			result["analytic_half_step_attempt_total"] += 1.0
			var half_pressure: Array[float] = []
			for row_index in range(room_count):
				half_pressure.append(
					pressure[row_index]
					+ CYCLE_ANALYTIC_HALF_STEP * float(step[row_index])
				)
			var half_evaluation: Dictionary = _evaluate(context, half_pressure)
			if bool(half_evaluation.get("valid", false)):
				var half_norm: float = float(
					half_evaluation["normalized_residual"]
				)
				if is_finite(half_norm) and half_norm < norm:
					result["analytic_half_step_accept_total"] += 1.0
					result["analytic_half_step_last_initial_norm"] = norm
					result["analytic_half_step_last_final_norm"] = half_norm
					pressure = half_pressure
					evaluation = half_evaluation
					norm = half_norm
					result["residual_history"].append(norm)
					result["damping_history"].append(CYCLE_ANALYTIC_HALF_STEP)
					previous_full_step.clear()
					previous_full_step_gain_ratio = INF
					previous_full_step_norm = NAN
					previous_previous_full_step_norm = NAN
					post_budget_cycle_streak = 0
					# Never convergence by itself: the ordinary L-infinity test
					# against the unchanged tolerance still decides.
					converged = norm <= tolerance
					continue
		if cycle_detected and rescue_budget_left > 0:
			result["cycle_guard_attempt_total"] += 1.0
			result["cycle_guard_last_rho"] = model_gain_ratio
			result["cycle_guard_last_cosine"] = step_cosine
			var cycle_rescue: Dictionary = _try_lm_rescue(
				context, pressure, evaluation, jacobian, room_count,
				max_halvings, rescue_budget_left
			)
			result["rescue_attempted"] += 1.0
			result["rescue_trials"] += float(cycle_rescue.get("trials", 0.0))
			if bool(cycle_rescue.get("accepted", false)):
				rescue_budget_left -= 1
				result["cycle_guard_accept_total"] += 1.0
				result["rescue_accepted"] += 1.0
				result["rescue_initial_norm"] = norm
				result["rescue_lambda"] = float(cycle_rescue["lambda"])
				pressure = cycle_rescue["pressure"]
				evaluation = cycle_rescue["evaluation"]
				norm = float(evaluation["normalized_residual"])
				result["rescue_final_norm"] = norm
				result["residual_history"].append(norm)
				result["damping_history"].append(
					float(cycle_rescue["damping"])
				)
				previous_full_step.clear()
				previous_full_step_gain_ratio = INF
				previous_full_step_norm = NAN
				previous_previous_full_step_norm = NAN
				post_budget_cycle_streak = 0
				converged = norm <= tolerance
				continue

		if damping == 1.0:
			previous_full_step = step.duplicate()
			previous_full_step_gain_ratio = model_gain_ratio
			previous_previous_full_step_norm = previous_full_step_norm
			previous_full_step_norm = _step_norm(step)
		else:
			previous_full_step.clear()
			previous_full_step_gain_ratio = INF
			previous_full_step_norm = NAN
			previous_previous_full_step_norm = NAN
			post_budget_cycle_streak = 0
		result["pressure_change_history_pa"].append(
			_max_abs_difference(pressure, candidate_pressure)
		)
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
	_summarize_zonal_decomposition(result, evaluation)
	return result


## H3.2a solve-level totals. Interior connections decide global validity;
## exterior ones are counted separately and never invalidate the network.
## ============================================================
## F2.2B: entrada canonica de la red presion-aberturas.
##
## `solve_coupled_pressure` sigue siendo la envoltura historica de la
## maquinaria de sombra de la fase 3 y comparte exactamente este nucleo: aqui
## no se reimplementa ninguna ecuacion.
##
## Convenciones:
##   - presion manometrica respecto al exterior, referencia en el SUELO de cada
##     recinto (`floor_z_m`), con signo: puede ser negativa;
##   - alturas en cota ABSOLUTA del edificio; una abertura puede declararlas
##     como locales, y entonces se convierten explicitamente;
##   - positivo = entra en el recinto y en la zona indicada;
##   - masa kg, caudal kg/s, energia kJ, entalpia kW, temperatura K, cotas m.
##
## El exterior es un nodo de presion impuesta, nunca una sala ficticia: aporta
## presion absoluta, temperatura, densidad y, por abertura, presion de viento.
func solve_pressure_network(
		rooms: Array,
		openings: Array,
		outside: Dictionary,
		sources: Dictionary,
		dt_s: float,
		options: Dictionary = {}
	) -> Dictionary:
	var result: Dictionary = _new_network_result()
	var errors: Array[String] = []
	var prepared: Dictionary = _prepare_network(
		rooms, openings, outside, sources, dt_s, options, errors
	)
	if not errors.is_empty():
		result["errors"] = errors
		result["failure_reason"] = "invalid_input"
		result["failure_code"] = FAILURE_BAD_ARGUMENTS
		return result

	var solved: Dictionary = solve_coupled_pressure(
		prepared["rooms"], prepared["openings"], prepared["sources"],
		dt_s, prepared["reference_temp_c"], prepared["options"]
	)
	result["iterations"] = float(solved["iterations"])
	result["residual_history"] = solved["residual_history"]
	result["pressure_change_history_pa"] = solved["pressure_change_history_pa"]
	result["max_pressure_change_pa"] = _max_of(solved["pressure_change_history_pa"])
	result["failure_code"] = float(solved["failure_code"])
	result["solver_limiting_reason"] = String(solved["limiting_reason"])
	if not bool(solved["valid"]):
		result["failure_reason"] = String(solved["limiting_reason"])
		result["errors"] = ["coupled solve did not converge: %s" % solved["limiting_reason"]]
		return result

	# Una unica reevaluacion en la MISMA presion aceptada, solo para recoger
	# segmentos y flujo por zona. No cambia ninguna aritmetica.
	var final_options: Dictionary = prepared["options"].duplicate(true)
	final_options["collect_segments"] = true
	var context: Dictionary = _build_context(
		prepared["rooms"], prepared["openings"], prepared["sources"],
		dt_s, prepared["reference_temp_c"], final_options
	)
	if not bool(context.get("valid", false)):
		result["failure_reason"] = "context_rebuild_failed"
		result["errors"] = ["the final evaluation context could not be rebuilt"]
		return result
	var pressure: Array[float] = []
	for room_key in context["room_keys"]:
		pressure.append(float(solved["gauge_pressure_by_room"][room_key]))
	var evaluation: Dictionary = _evaluate(context, pressure)
	if not bool(evaluation.get("valid", false)):
		result["failure_reason"] = "final_evaluation_failed"
		result["errors"] = ["the accepted pressure did not evaluate"]
		return result

	return _finish_network(result, prepared, context, evaluation, pressure, dt_s, solved)


func _new_network_result() -> Dictionary:
	return {
		"valid": false,
		"errors": [],
		"converged": false,
		"failure_reason": "invalid",
		"failure_code": FAILURE_BAD_ARGUMENTS,
		"solver_limiting_reason": "",
		"iterations": 0.0,
		"residual_history": [],
		"pressure_change_history_pa": [],
		"max_pressure_change_pa": 0.0,
		"max_mass_residual_kg": 0.0,
		"max_energy_residual_kj": 0.0,
		"max_pressure_residual_pa": 0.0,
		"owed_pressure_change_pa": 0.0,
		"rooms": [],
		"openings": [],
	}


func _max_of(values: Array) -> float:
	var top: float = 0.0
	for value in values:
		top = maxf(top, absf(float(value)))
	return top


func _max_abs_difference(before: Array, after: Array) -> float:
	var top: float = 0.0
	for index in range(mini(before.size(), after.size())):
		top = maxf(top, absf(float(after[index]) - float(before[index])))
	return top


func _summarize_zonal_decomposition(
		result: Dictionary, evaluation: Dictionary
	) -> void:
	var interior_connections: int = 0
	var exterior_skipped: int = 0
	var exterior_unzoned_bands: int = 0
	var unclassified_interior_bands: int = 0
	var worst_mass_residual_kg: float = 0.0
	var worst_energy_residual_kj: float = 0.0
	for raw_connection in evaluation.get("connections", []):
		var connection: Dictionary = raw_connection
		exterior_unzoned_bands += int(
			connection.get("exterior_unzoned_band_count", 0)
		)
		if not bool(connection.get("zonal_decomposition_applicable", false)):
			exterior_skipped += 1
			continue
		interior_connections += 1
		unclassified_interior_bands += int(
			connection.get("unclassified_interior_band_count", 0)
		)
		worst_mass_residual_kg = maxf(
			worst_mass_residual_kg,
			float(connection.get("zonal_mass_residual_kg", 0.0))
		)
		worst_energy_residual_kj = maxf(
			worst_energy_residual_kj,
			float(connection.get("zonal_energy_residual_kj", 0.0))
		)
	result["zonal_interior_connection_count"] = float(interior_connections)
	result["zonal_exterior_connection_skipped_count"] = float(exterior_skipped)
	result["zonal_exterior_unzoned_band_count"] = float(exterior_unzoned_bands)
	result["zonal_unclassified_interior_band_count"] = float(
		unclassified_interior_bands
	)
	result["zonal_mass_residual_kg"] = worst_mass_residual_kg
	result["zonal_energy_residual_kj"] = worst_energy_residual_kj
	result["zonal_decomposition_valid"] = unclassified_interior_bands == 0


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


## Sum-of-squares merit predicted by the current linear model for an accepted
## damped Newton step. This uses the same fixed room-inventory normalization as
## `_rescue_merit`, so the actual/predicted ratio compares like with like.
func _linear_model_merit(
		context: Dictionary,
		evaluation: Dictionary,
		jacobian: Array,
		step: Array,
		damping: float
	) -> float:
	var total: float = 0.0
	var room_keys: Array = context["room_keys"]
	var rooms: Dictionary = context["rooms"]
	var gas_constant: float = float(context["gas_constant"])
	var reference_temp_k: float = float(context["reference_temp_k"])
	var residual: Array = evaluation["residual"]
	for row_index in range(room_keys.size()):
		var predicted_pa: float = float(residual[row_index])
		for column in range(room_keys.size()):
			predicted_pa += damping \
					* float(jacobian[row_index][column]) \
					* float(step[column])
		var room: Dictionary = rooms[String(room_keys[row_index])]
		var pressure_per_kg: float = gas_constant * reference_temp_k \
				/ float(room["volume_m3"])
		var normalized: float = predicted_pa / pressure_per_kg \
				/ maxf(MASS_EPS_KG, float(room["mass_kg"]))
		total += normalized * normalized
	return 0.5 * total


## Trust-style agreement ratio for the already accepted Newton candidate.
## A value near one means the nonlinear solve delivered what its linear model
## promised; a value near zero is the measured signature of the period-2
## opening-flow reversal. Invalid/non-improving predictions are not classified
## as this specific cycle and return +INF.
func _model_gain_ratio(
		context: Dictionary,
		evaluation: Dictionary,
		candidate_evaluation: Dictionary,
		jacobian: Array,
		step: Array,
		damping: float
	) -> float:
	var merit_before: float = _rescue_merit(evaluation)
	var merit_after: float = _rescue_merit(candidate_evaluation)
	var merit_predicted: float = _linear_model_merit(
		context, evaluation, jacobian, step, damping
	)
	var predicted_reduction: float = merit_before - merit_predicted
	if predicted_reduction <= 0.0 or not is_finite(predicted_reduction):
		return INF
	var ratio: float = (merit_before - merit_after) / predicted_reduction
	return ratio if is_finite(ratio) else INF


func _step_cosine(first: Array, second: Array) -> float:
	if first.size() != second.size() or first.is_empty():
		return 1.0
	var dot: float = 0.0
	var first_norm_sq: float = 0.0
	var second_norm_sq: float = 0.0
	for index in range(first.size()):
		var first_value: float = float(first[index])
		var second_value: float = float(second[index])
		dot += first_value * second_value
		first_norm_sq += first_value * first_value
		second_norm_sq += second_value * second_value
	var denominator: float = sqrt(first_norm_sq * second_norm_sq)
	if denominator <= 0.0 or not is_finite(denominator):
		return 1.0
	return clampf(dot / denominator, -1.0, 1.0)


func _step_norm(step: Array) -> float:
	var norm_sq: float = 0.0
	for raw_value in step:
		var value: float = float(raw_value)
		norm_sq += value * value
	return sqrt(norm_sq)


## H2.10 fail-only branch-preserving adaptive unilateral recovery.
##
## No new tuning threshold is used. A candidate is accepted only when two
## consecutive widths independently find a strict L-infinity decrease and use
## the same unilateral side for every column. The finer candidate wins. If
## that evidence is unavailable, the caller continues into the unchanged LM
## fallback.
func _try_adaptive_branch_jacobian_recovery(
		context: Dictionary,
		pressure: Array,
		evaluation: Dictionary,
		room_count: int,
		initial_step_pa: float,
		max_halvings: int
	) -> Dictionary:
	var outcome: Dictionary = {
		"accepted": false,
		"columns_forward_total": 0.0,
		"columns_backward_total": 0.0,
		"columns_reduced_total": 0.0,
		"branch_crossing_avoided_total": 0.0,
		"derivative_consistency_fail_total": 0.0,
		"min_effective_jacobian_step_pa": 0.0,
	}
	var previous_candidate: Dictionary = {}
	var previous_sides: Array = []
	var step_pa: float = initial_step_pa
	for refinement in range(max_halvings + 1):
		if step_pa <= 0.0 or not is_finite(step_pa):
			break
		var built: Dictionary = _build_branch_preserving_jacobian(
			context, pressure, evaluation, room_count, step_pa
		)
		for field in [
			"columns_forward_total", "columns_backward_total",
			"branch_crossing_avoided_total",
		]:
			outcome[field] = float(outcome[field]) + float(built.get(field, 0.0))
		if refinement > 0:
			outcome["columns_reduced_total"] = float(
				outcome["columns_reduced_total"]
			) + float(room_count)
		var prior_min_step: float = float(outcome["min_effective_jacobian_step_pa"])
		outcome["min_effective_jacobian_step_pa"] = (
			step_pa if prior_min_step <= 0.0 else minf(prior_min_step, step_pa)
		)
		if not bool(built.get("valid", false)):
			outcome["derivative_consistency_fail_total"] += 1.0
			previous_candidate.clear()
			previous_sides.clear()
			step_pa *= 0.5
			continue
		var negative_residual: Array[float] = []
		for row_index in range(room_count):
			negative_residual.append(-float(evaluation["residual"][row_index]))
		var direction: Array = _solve_linear_system(
			built["jacobian"], negative_residual
		)
		if direction.is_empty():
			outcome["derivative_consistency_fail_total"] += 1.0
			previous_candidate.clear()
			previous_sides.clear()
			step_pa *= 0.5
			continue
		var candidate: Dictionary = _try_strict_linf_candidate(
			context, pressure, evaluation, direction, max_halvings
		)
		if not bool(candidate.get("accepted", false)):
			outcome["derivative_consistency_fail_total"] += 1.0
			previous_candidate.clear()
			previous_sides.clear()
			step_pa *= 0.5
			continue
		var sides: Array = built["sides"]
		if not previous_candidate.is_empty():
			if sides == previous_sides:
				outcome["accepted"] = true
				outcome["pressure"] = candidate["pressure"]
				outcome["evaluation"] = candidate["evaluation"]
				outcome["damping"] = candidate["damping"]
				return outcome
			outcome["derivative_consistency_fail_total"] += 1.0
		previous_candidate = candidate
		previous_sides = sides.duplicate()
		step_pa *= 0.5
	return outcome


func _build_branch_preserving_jacobian(
		context: Dictionary,
		pressure: Array,
		evaluation: Dictionary,
		room_count: int,
		step_pa: float
	) -> Dictionary:
	var outcome: Dictionary = {
		"valid": false,
		"columns_forward_total": 0.0,
		"columns_backward_total": 0.0,
		"branch_crossing_avoided_total": 0.0,
	}
	var jacobian: Array = []
	for row_index in range(room_count):
		var row: Array[float] = []
		row.resize(room_count)
		jacobian.append(row)
	var sides: Array = []
	for column in range(room_count):
		var forward_pressure: Array = pressure.duplicate()
		var backward_pressure: Array = pressure.duplicate()
		forward_pressure[column] = float(forward_pressure[column]) + step_pa
		backward_pressure[column] = float(backward_pressure[column]) - step_pa
		if float(forward_pressure[column]) == float(pressure[column]) \
				or float(backward_pressure[column]) == float(pressure[column]):
			return outcome
		var forward: Dictionary = _evaluate(context, forward_pressure)
		var backward: Dictionary = _evaluate(context, backward_pressure)
		if not bool(forward.get("valid", false)) \
				or not bool(backward.get("valid", false)):
			return outcome
		var forward_rank: Array = _branch_change_rank(evaluation, forward)
		var backward_rank: Array = _branch_change_rank(evaluation, backward)
		var use_backward: bool = _branch_rank_less(backward_rank, forward_rank)
		var selected: Dictionary = backward if use_backward else forward
		if use_backward:
			outcome["columns_backward_total"] += 1.0
			if int(backward_rank[0]) < int(forward_rank[0]):
				outcome["branch_crossing_avoided_total"] += 1.0
			sides.append(-1)
		else:
			outcome["columns_forward_total"] += 1.0
			sides.append(1)
		for row_index in range(room_count):
			jacobian[row_index][column] = (
				(float(evaluation["residual"][row_index])
				- float(selected["residual"][row_index])) / step_pa
			) if use_backward else (
				(float(selected["residual"][row_index])
				- float(evaluation["residual"][row_index])) / step_pa
			)
	outcome["valid"] = true
	outcome["jacobian"] = jacobian
	outcome["sides"] = sides
	return outcome


## Categorical, lexicographic branch distance: donor/direction first,
## neutral-plane topology second, regularization membership last.
func _branch_change_rank(base: Dictionary, probe: Dictionary) -> Array:
	var donor_changes: int = 0
	var neutral_changes: int = 0
	var regularization_changes: int = 0
	var base_connections: Array = base.get("connections", [])
	var probe_connections: Array = probe.get("connections", [])
	if base_connections.size() != probe_connections.size():
		return [2147483647, 2147483647, 2147483647]
	for index in range(base_connections.size()):
		var before: Dictionary = base_connections[index]
		var after: Dictionary = probe_connections[index]
		if signf(float(before["delta_p_pa"])) \
				!= signf(float(after["delta_p_pa"])):
			donor_changes += 1
		if (float(before["a_to_b_kg"]) > 0.0) \
				!= (float(after["a_to_b_kg"]) > 0.0):
			donor_changes += 1
		if (float(before["b_to_a_kg"]) > 0.0) \
				!= (float(after["b_to_a_kg"]) > 0.0):
			donor_changes += 1
		if bool(before["neutral_plane_inside"]) \
				!= bool(after["neutral_plane_inside"]):
			neutral_changes += 1
		if float(before["regularization_active_count"]) \
				!= float(after["regularization_active_count"]):
			regularization_changes += 1
	return [donor_changes, neutral_changes, regularization_changes]


func _branch_rank_less(left: Array, right: Array) -> bool:
	for index in range(mini(left.size(), right.size())):
		if int(left[index]) == int(right[index]):
			continue
		return int(left[index]) < int(right[index])
	return false


func _try_strict_linf_candidate(
		context: Dictionary,
		pressure: Array,
		evaluation: Dictionary,
		step: Array,
		max_halvings: int
	) -> Dictionary:
	var norm: float = float(evaluation["normalized_residual"])
	var damping: float = 1.0
	for _halving in range(max_halvings + 1):
		var trial: Array[float] = []
		for row_index in range(pressure.size()):
			trial.append(float(pressure[row_index]) + damping * float(step[row_index]))
		var trial_evaluation: Dictionary = _evaluate(context, trial)
		if bool(trial_evaluation.get("valid", false)) \
				and float(trial_evaluation["normalized_residual"]) < norm:
			return {
				"accepted": true,
				"pressure": trial,
				"evaluation": trial_evaluation,
				"damping": damping,
			}
		damping *= 0.5
	return {"accepted": false}


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
		# F2.2B: max |dp| accepted at each iteration, for the canonical
		# convergence test. Reporting only for the historical entry point.
		"pressure_change_history_pa": [],
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
		# F3.3v3h2.5j accepted-cycle telemetry. Counts are per solve here; the
		# passive preview accumulates them across scenario steps.
		"cycle_guard_attempt_total": 0.0,
		"cycle_guard_accept_total": 0.0,
		"cycle_guard_last_rho": 0.0,
		"cycle_guard_last_cosine": 0.0,
		# H2.5l-A passive cycle observation. These values never feed back into
		# acceptance, rescue authority or convergence.
		"cycle_detect_total": 0.0,
		"cycle_detect_after_budget_total": 0.0,
		"cycle_contraction_min": 0.0,
		"cycle_contraction_max": 0.0,
		# H2.5l-B per-solve recurrence ledger.
		"post_budget_cycle_streak_max": 0.0,
		# H2.5m analytic half step. Observation of an authority branch; these
		# values are reported, never read back into a decision.
		"analytic_half_step_attempt_total": 0.0,
		"analytic_half_step_accept_total": 0.0,
		"analytic_half_step_last_initial_norm": 0.0,
		"analytic_half_step_last_final_norm": 0.0,
		# H2.8 splits the detected population by which regime fired. Both are
		# reported, never read back into a decision.
		"cycle_detect_both_phases_low_total": 0.0,
		"cycle_detect_alternating_gain_total": 0.0,
		# H3.2a zonal decomposition. Reporting only; no aggregate is derived
		# from these and no state is written from them.
		"zonal_interior_connection_count": 0.0,
		"zonal_exterior_connection_skipped_count": 0.0,
		"zonal_exterior_unzoned_band_count": 0.0,
		"zonal_unclassified_interior_band_count": 0.0,
		"zonal_mass_residual_kg": 0.0,
		"zonal_energy_residual_kj": 0.0,
		"zonal_decomposition_valid": false,
		# H2.10 fail-only adaptive unilateral Jacobian telemetry.
		"adaptive_jacobian_attempt_total": 0.0,
		"adaptive_jacobian_accept_total": 0.0,
		"adaptive_jacobian_columns_forward_total": 0.0,
		"adaptive_jacobian_columns_backward_total": 0.0,
		"adaptive_jacobian_columns_reduced_total": 0.0,
		"adaptive_jacobian_branch_crossing_avoided_total": 0.0,
		"adaptive_jacobian_derivative_consistency_fail_total": 0.0,
		"adaptive_jacobian_min_effective_step_pa": 0.0,
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

	# F2.2B: the exterior can sit at its own temperature. When the caller does
	# not say otherwise it is the reference temperature, which is the historical
	# behaviour and keeps the density and the carried enthalpy unchanged.
	var exterior_temp_k: float = float(options.get("exterior_temp_k", reference_temp_k))
	if not is_finite(exterior_temp_k) or exterior_temp_k <= 0.0:
		return context
	var exterior_density_kg_m3: float = exterior_pressure_abs_pa \
			/ (gas_constant * exterior_temp_k)
	var exterior_specific_kj_kg: float = AIR_CP_KJ_KG_K * (exterior_temp_k - reference_temp_k)
	var opening_context: Array[Dictionary] = []
	for raw_opening in openings:
		var opening: Dictionary = raw_opening
		if exterior_specific_kj_kg != 0.0 and not opening.has("exterior_specific_kj_kg"):
			opening = opening.duplicate(true)
			opening["exterior_specific_kj_kg"] = exterior_specific_kj_kg
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
	context["exterior_temp_k"] = exterior_temp_k
	context["exterior_density_kg_m3"] = exterior_density_kg_m3
	context["exterior_specific_kj_kg"] = exterior_specific_kj_kg
	# Reporting only, and only ever enabled for the single final evaluation at
	# the accepted pressure: it changes no arithmetic.
	context["collect_segments"] = bool(options.get("collect_segments", false))
	return context


func _derive_room(
		raw_state: Dictionary,
		reference_temp_k: float,
		gas_constant: float,
		exterior_pressure_abs_pa: float
	) -> Dictionary:
	var state: Dictionary = raw_state
	# F2.2B: the pressure datum of a room is its own floor. Callers that do not
	# declare one keep the historical single-storey frame with every floor at 0.
	var floor_z_m: float = float(state.get("floor_z_m", 0.0))
	if not is_finite(floor_z_m):
		return {"valid": false}
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
	if upper_gas_kg < 0.0 or lower_gas_kg < 0.0:
		return {"valid": false}
	var total_mass_kg: float = upper_gas_kg + lower_gas_kg
	if total_mass_kg <= MASS_EPS_KG:
		return {"valid": false}
	# F2.2B: the zone energy is SENSIBLE and measured from the reference
	# temperature, so a zone colder than ambient holds negative energy and is
	# physically valid. What is rejected is an unphysical state, never a sign:
	# the zone temperature and the absolute pressure below still have to be
	# finite and positive, exactly as CompartmentPressureEquations demands.
	# A zone holding energy but no mass has no defined temperature.
	if (upper_gas_kg <= MASS_EPS_KG and absf(upper_energy_kj) > 0.0) \
			or (lower_gas_kg <= MASS_EPS_KG and absf(lower_energy_kj) > 0.0):
		return {"valid": false}
	var total_energy_kj: float = upper_energy_kj + lower_energy_kj
	var upper_temp_k: float = reference_temp_k
	if upper_gas_kg > MASS_EPS_KG:
		upper_temp_k += upper_energy_kj / (upper_gas_kg * AIR_CP_KJ_KG_K)
	var lower_temp_k: float = reference_temp_k
	if lower_gas_kg > MASS_EPS_KG:
		lower_temp_k += lower_energy_kj / (lower_gas_kg * AIR_CP_KJ_KG_K)
	# Physical floor: an absolute temperature has to be above 0 K. This is what
	# replaces the old "energy must be non-negative" rule.
	if not is_finite(upper_temp_k) or not is_finite(lower_temp_k) \
			or upper_temp_k <= 0.0 or lower_temp_k <= 0.0:
		return {"valid": false}
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
		# F2.2B: absolute frame. `interface_z_m` is the same interface expressed
		# in building coordinates, so two rooms on different storeys compare at
		# the same physical height.
		"floor_z_m": floor_z_m,
		"upper_gas_kg": upper_gas_kg,
		"lower_gas_kg": lower_gas_kg,
		"upper_energy_kj": upper_energy_kj,
		"lower_energy_kj": lower_energy_kj,
		"upper_temp_k": upper_temp_k,
		"lower_temp_k": lower_temp_k,
		"mass_kg": total_mass_kg,
		"reference_mass_kg": reference_mass_kg,
		"energy_kj": total_energy_kj,
		"pressure_abs_pa": pressure_abs_pa,
		"gauge_pressure_pa": gauge_pressure_pa,
		"interface_m": interface_m,
		"interface_z_m": floor_z_m + interface_m,
		"upper_density_kg_m3": maxf(0.0, upper_density_kg_m3),
		"lower_density_kg_m3": maxf(0.0, lower_density_kg_m3),
		# Donor-cell specific sensible enthalpy carried out of each zone.
		"upper_specific_kj_kg": upper_energy_kj / maxf(MASS_EPS_KG, upper_gas_kg),
		"lower_specific_kj_kg": lower_energy_kj / maxf(MASS_EPS_KG, lower_gas_kg),
	}


## Perfil vertical de un lado de la abertura, en cota ABSOLUTA.
##
## `datum_z_m` es la cota desde la que se integra la columna. Para una sala es
## su propio suelo; para el exterior es el suelo de la sala que hay al otro
## lado, porque la presion manometrica de esa sala esta definida justo ahi. Con
## todos los suelos en 0 (marco historico de una sola planta) esto reproduce
## exactamente la formula anterior.
##
## `exterior_specific_kj_kg` es la entalpia sensible del aire exterior respecto
## a la temperatura de referencia: 0 solo cuando el exterior esta a esa misma
## temperatura.
func _side_profile(
		room_key: String,
		room_context: Dictionary,
		exterior_density_kg_m3: float,
		datum_z_m: float = 0.0,
		exterior_specific_kj_kg: float = 0.0
	) -> Dictionary:
	if room_key.is_empty():
		return {
			"exterior": true,
			"interface_m": INF,
			"interface_z_m": INF,
			"floor_z_m": datum_z_m,
			"upper_density_kg_m3": exterior_density_kg_m3,
			"lower_density_kg_m3": exterior_density_kg_m3,
			"upper_specific_kj_kg": exterior_specific_kj_kg,
			"lower_specific_kj_kg": exterior_specific_kj_kg,
		}
	var room: Dictionary = room_context[room_key]
	return {
		"exterior": false,
		"interface_m": float(room["interface_m"]),
		"interface_z_m": float(room["interface_z_m"]),
		"floor_z_m": float(room["floor_z_m"]),
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
	# F2.2B: heights are ABSOLUTE building coordinates. `bottom_z_m`/`top_z_m`
	# are the canonical keys; the historical `bottom_m`/`top_m` mean the same
	# numbers in the single-storey frame where every floor sits at 0, and the
	# canonical entry converts local spans before calling here.
	var bottom_m: float = float(opening.get("bottom_z_m", opening.get("bottom_m", 0.0)))
	var top_m: float = float(opening.get("top_z_m", opening.get("top_m", 0.0)))
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

	# The exterior integrates its column from the floor of the room it faces,
	# because that is where that room's gauge pressure is defined.
	var floor_a_z_m: float = 0.0
	if not room_a_key.is_empty():
		floor_a_z_m = float(room_context[room_a_key].get("floor_z_m", 0.0))
	var floor_b_z_m: float = 0.0
	if not room_b_key.is_empty():
		floor_b_z_m = float(room_context[room_b_key].get("floor_z_m", 0.0))
	var exterior_specific_kj_kg: float = float(
		opening.get("exterior_specific_kj_kg", 0.0)
	)
	var side_a: Dictionary = _side_profile(
		room_a_key, room_context, exterior_density_kg_m3,
		floor_b_z_m if room_a_key.is_empty() else floor_a_z_m,
		exterior_specific_kj_kg
	)
	var side_b: Dictionary = _side_profile(
		room_b_key, room_context, exterior_density_kg_m3,
		floor_a_z_m if room_b_key.is_empty() else floor_b_z_m,
		exterior_specific_kj_kg
	)
	# Wind is a property of the exterior node at this opening, applied once as a
	# constant gauge offset of the exterior side. An interior opening has no
	# exterior side and therefore cannot carry wind.
	var exterior_gauge_pa: float = float(opening.get("wind_dp_pa", 0.0))
	if not is_finite(exterior_gauge_pa):
		return {"valid": false}
	if exterior_gauge_pa != 0.0 and not room_a_key.is_empty() \
			and not room_b_key.is_empty():
		return {"valid": false}
	# Split the span at every density discontinuity so that within a band both
	# profiles are constant and dp(z) is exactly linear.
	var boundaries: Array[float] = [bottom_m, top_m]
	for interface_z_m in [
		float(side_a.get("interface_z_m", INF)),
		float(side_b.get("interface_z_m", INF))
	]:
		if is_finite(interface_z_m) and interface_z_m > bottom_m + 1.0e-9 \
				and interface_z_m < top_m - 1.0e-9:
			boundaries.append(interface_z_m)
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
			# H3.2a: reporting only. Same midpoint as the density and specific
			# enthalpy above, so the label cannot disagree with the profile the
			# integration used.
			"zone_a": _zone_at(side_a, 0.5 * (z0 + z1)),
			"zone_b": _zone_at(side_b, 0.5 * (z0 + z1)),
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
		"exterior_gauge_pa": exterior_gauge_pa,
		"coefficient": discharge_coeff * width_m * open_fraction * dt,
		"bands": bands,
		# H3.2a: an opening is zonable only when BOTH sides are rooms. The
		# exterior has no layers, so exterior openings are reported as
		# inapplicable rather than labelled with an invented one.
		"interior": not bool(side_a.get("exterior", false)) \
				and not bool(side_b.get("exterior", false)),
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


## Columna de masa por unidad de area entre el datum del lado y la cota z,
## ambas ABSOLUTAS. Con el datum en 0 y la interfaz local coincide byte a byte
## con la version anterior de una sola planta.
func _column_mass_per_area(side: Dictionary, height_m: float) -> float:
	var datum_z_m: float = float(side.get("floor_z_m", 0.0))
	var interface_z_m: float = float(side.get("interface_z_m", INF))
	var lower_density_kg_m3: float = float(side["lower_density_kg_m3"])
	var upper_density_kg_m3: float = float(side["upper_density_kg_m3"])
	if not is_finite(interface_z_m) or height_m <= interface_z_m:
		return lower_density_kg_m3 * (height_m - datum_z_m)
	return lower_density_kg_m3 * (interface_z_m - datum_z_m) \
			+ upper_density_kg_m3 * (height_m - interface_z_m)


func _density_at(side: Dictionary, height_m: float) -> float:
	var interface_z_m: float = float(side.get("interface_z_m", INF))
	return float(side["lower_density_kg_m3"]) \
			if (not is_finite(interface_z_m) or height_m <= interface_z_m) \
			else float(side["upper_density_kg_m3"])


func _specific_at(side: Dictionary, height_m: float) -> float:
	var interface_z_m: float = float(side.get("interface_z_m", INF))
	return float(side["lower_specific_kj_kg"]) \
			if (not is_finite(interface_z_m) or height_m <= interface_z_m) \
			else float(side["upper_specific_kj_kg"])


## H3.2a: build the deterministic zonal route list for one connection.
##
## The routes are a decomposition of aggregates that are already final. The
## residual is reported, never corrected, and the aggregates are never rebuilt
## from the routes - a structural test enforces that.
func _attach_zonal_decomposition(
		connection: Dictionary,
		opening: Dictionary,
		flux: Dictionary
	) -> void:
	var interior: bool = bool(opening.get("interior", false))
	var connection_id: String = "opening:%d" % int(opening["opening_id"])
	connection["connection_id"] = connection_id
	connection["zonal_decomposition_applicable"] = interior
	connection["unclassified_interior_band_count"] = int(
		flux.get("unclassified_interior_band_count", 0)
	)
	connection["exterior_unzoned_band_count"] = int(
		flux.get("exterior_unzoned_band_count", 0)
	)
	if not interior:
		# The exterior has no layers. Report nothing rather than invent a zone.
		connection["zonal_routes"] = []
		connection["zonal_decomposition_valid"] = false
		connection["zonal_mass_residual_kg"] = 0.0
		connection["zonal_energy_residual_kj"] = 0.0
		return

	var routes: Array[Dictionary] = []
	var zonal_totals: Dictionary = flux.get("zonal_totals", {})
	for raw_key in zonal_totals.keys():
		var entry: Dictionary = zonal_totals[raw_key]
		var direction: String = String(entry["direction"])
		var a_to_b: bool = direction == "a_to_b"
		routes.append({
			"connection_id": connection_id,
			"direction": direction,
			"source_room_id": int(opening["room_a_id"]) if a_to_b \
					else int(opening["room_b_id"]),
			"destination_room_id": int(opening["room_b_id"]) if a_to_b \
					else int(opening["room_a_id"]),
			"source_zone": String(entry["source_zone"]),
			"destination_zone": String(entry["destination_zone"]),
			"gas_mass_kg": float(entry["gas_mass_kg"]),
			"sensible_energy_kj": float(entry["sensible_energy_kj"]),
			"band_count": int(Dictionary(entry["band_indices"]).size()),
		})
	# Deterministic: connection, then direction, then source and target zone.
	routes.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return "%s|%s|%s|%s" % [
			String(left["connection_id"]), String(left["direction"]),
			String(left["source_zone"]), String(left["destination_zone"]),
		] < "%s|%s|%s|%s" % [
			String(right["connection_id"]), String(right["direction"]),
			String(right["source_zone"]), String(right["destination_zone"]),
		]
	)

	var a_to_b_mass: float = 0.0
	var b_to_a_mass: float = 0.0
	var a_to_b_energy: float = 0.0
	var b_to_a_energy: float = 0.0
	for route in routes:
		if String(route["direction"]) == "a_to_b":
			a_to_b_mass += float(route["gas_mass_kg"])
			a_to_b_energy += float(route["sensible_energy_kj"])
		else:
			b_to_a_mass += float(route["gas_mass_kg"])
			b_to_a_energy += float(route["sensible_energy_kj"])

	var unclassified: int = int(
		flux.get("unclassified_interior_band_count", 0)
	)
	connection["zonal_routes"] = routes
	connection["zonal_mass_residual_kg"] = maxf(
		absf(a_to_b_mass - float(connection["a_to_b_kg"])),
		absf(b_to_a_mass - float(connection["b_to_a_kg"]))
	)
	connection["zonal_energy_residual_kj"] = maxf(
		absf(a_to_b_energy - float(connection["a_to_b_kj"])),
		absf(b_to_a_energy - float(connection["b_to_a_kj"]))
	)
	connection["zonal_decomposition_valid"] = unclassified == 0


## F3.3v3h3.2a: which layer a height belongs to, for REPORTING only.
##
## This is a pure read of a decision the solver has already made. It mirrors
## `_density_at` and `_specific_at` exactly - `height_m <= interface_m` is the
## lower layer - so the zone label always agrees with the density and specific
## enthalpy the integration actually used for that band. Because
## `_build_opening` splits the span at both interfaces, no band midpoint can
## ever land on an interface, so the boundary case is unreachable by
## construction; the convention is mirrored anyway so it cannot drift.
##
## The exterior has no layers. `_density_at` maps its non-finite interface to
## the lower profile, which is harmless there because both exterior profiles
## hold the same density, but it is NOT a statement that the exterior has a
## lower layer. Zoning therefore returns an empty label and the caller marks
## the connection inapplicable rather than inventing a layer.
func _zone_at(side: Dictionary, height_m: float) -> String:
	if bool(side.get("exterior", false)):
		return ""
	var interface_z_m: float = float(side.get("interface_z_m", INF))
	if not is_finite(interface_z_m):
		return ""
	return ZONE_LOWER if height_m <= interface_z_m else ZONE_UPPER


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

	var collect_segments: bool = bool(context.get("collect_segments", false))
	var zone_flux_by_room: Dictionary = {}
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
		# The exterior node is gauge zero by construction, plus the wind offset
		# of this opening when it has one.
		var exterior_gauge_pa: float = float(opening.get("exterior_gauge_pa", 0.0))
		var pressure_a_pa: float = float(pressure[index_a]) if index_a >= 0 \
				else exterior_gauge_pa
		var pressure_b_pa: float = float(pressure[index_b]) if index_b >= 0 \
				else exterior_gauge_pa
		var flux: Dictionary = _integrate_opening(
			opening,
			pressure_a_pa - pressure_b_pa,
			float(context["dp_regularization_pa"]),
			int(context["band_segments"]),
			collect_segments
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
		# H3.2a: attach the parallel decomposition. Purely additive - every
		# aggregate above is already final and is never recomputed from it.
		_attach_zonal_decomposition(
			connections[connections.size() - 1], opening, flux
		)
		if collect_segments:
			connections[connections.size() - 1]["segments"] = flux["segments"]
			connections[connections.size() - 1]["exterior_gauge_pa"] = exterior_gauge_pa
			for raw_entry in flux["zone_flux"].values():
				var entry: Dictionary = raw_entry
				var side_key: String = String(opening["room_a_key"]) \
						if String(entry["side"]) == "a" else String(opening["room_b_key"])
				if side_key.is_empty():
					continue
				var by_zone: Dictionary = zone_flux_by_room.get(side_key, {})
				var zone_entry: Dictionary = by_zone.get(String(entry["zone"]), {
					"mass_kg": 0.0, "energy_kj": 0.0,
				})
				zone_entry["mass_kg"] = float(zone_entry["mass_kg"]) + float(entry["mass_kg"])
				zone_entry["energy_kj"] = float(zone_entry["energy_kj"]) + float(entry["energy_kj"])
				by_zone[String(entry["zone"])] = zone_entry
				zone_flux_by_room[side_key] = by_zone

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
		"zone_flux_by_room": zone_flux_by_room,
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
		band_segments: int,
		collect_segments: bool = false
	) -> Dictionary:
	# F2.2B reporting. Purely additive: the aggregates below are never read
	# back from these lists, and collection is only enabled for the single
	# final evaluation at the accepted pressure.
	var segments: Array[Dictionary] = []
	var zone_flux: Dictionary = {}
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
	# H3.2a zonal decomposition, accumulated strictly in parallel. The aggregate
	# accumulators above are never read back from these, and their summation
	# order is untouched.
	var zonal_totals: Dictionary = {}
	var unclassified_interior_band_count: int = 0
	var exterior_unzoned_band_count: int = 0
	var band_index: int = -1
	for raw_band in opening["bands"]:
		var band: Dictionary = raw_band
		band_index += 1
		var zone_a: String = String(band.get("zone_a", ""))
		var zone_b: String = String(band.get("zone_b", ""))
		var band_zoned: bool = not zone_a.is_empty() and not zone_b.is_empty()
		if not band_zoned:
			if zone_a.is_empty() and zone_b.is_empty():
				exterior_unzoned_band_count += 1
			elif bool(opening.get("interior", false)):
				unclassified_interior_band_count += 1
			else:
				exterior_unzoned_band_count += 1
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
				if collect_segments:
					var sample_z_m: float = lerpf(
						float(sub_band["z0"]), float(sub_band["z1"]), mid_fraction
					)
					var energy_kj: float = mass_kg * specific_kj_kg
					var source_side: String = "a" if dp_pa >= 0.0 else "b"
					var destination_side: String = "b" if dp_pa >= 0.0 else "a"
					var source_zone_label: String = zone_a if dp_pa >= 0.0 else zone_b
					var destination_zone_label: String = zone_b if dp_pa >= 0.0 else zone_a
					segments.append({
						"segment_id": "band%03d_seg%03d_%s" % [
							band_index, segment_index,
							"a_to_b" if dp_pa >= 0.0 else "b_to_a"
						],
						"z_from_m": float(sub_band["z0"]) + segment_height_m * float(segment_index),
						"z_to_m": float(sub_band["z0"]) + segment_height_m * float(segment_index + 1),
						"sample_z_m": sample_z_m,
						"dp_pa": dp_pa,
						"direction": "a_to_b" if dp_pa >= 0.0 else "b_to_a",
						"source_side": source_side,
						"destination_side": destination_side,
						"source_zone": source_zone_label,
						"destination_zone": destination_zone_label,
						"source_density_kg_m3": density_kg_m3,
						"source_specific_kj_kg": specific_kj_kg,
						"mass_kg": mass_kg,
						"enthalpy_kj": energy_kj,
						"regularized": bool(factor["regularized"]),
					})
					_accumulate_zone_flux(
						zone_flux, source_side, source_zone_label, -mass_kg, -energy_kj
					)
					_accumulate_zone_flux(
						zone_flux, destination_side, destination_zone_label, mass_kg, energy_kj
					)
				# H3.2a: mirror the same branch into the zonal ledger. Zones are
				# constant across a band, so the label is read once per band and
				# reused for every segment inside it.
				if band_zoned:
					var direction: String = "a_to_b" if dp_pa >= 0.0 else "b_to_a"
					var source_zone: String = zone_a if dp_pa >= 0.0 else zone_b
					var target_zone: String = zone_b if dp_pa >= 0.0 else zone_a
					var key: String = "%s|%s|%s" % [
						direction, source_zone, target_zone
					]
					var entry: Dictionary = zonal_totals.get(key, {
						"direction": direction,
						"source_zone": source_zone,
						"destination_zone": target_zone,
						"gas_mass_kg": 0.0,
						"sensible_energy_kj": 0.0,
						"band_indices": {},
					})
					entry["gas_mass_kg"] = float(entry["gas_mass_kg"]) + mass_kg
					entry["sensible_energy_kj"] = float(
						entry["sensible_energy_kj"]
					) + mass_kg * specific_kj_kg
					var seen: Dictionary = entry["band_indices"]
					seen[band_index] = true
					entry["band_indices"] = seen
					zonal_totals[key] = entry
	return {
		"valid": true,
		"a_to_b_kg": a_to_b_kg,
		"b_to_a_kg": b_to_a_kg,
		"a_to_b_kj": a_to_b_kj,
		"b_to_a_kj": b_to_a_kj,
		"neutral_plane_m": neutral_plane_m,
		"neutral_plane_inside": neutral_plane_inside,
		"regularization_active_count": regularization_active_count,
		"zonal_totals": zonal_totals,
		"unclassified_interior_band_count": unclassified_interior_band_count,
		"exterior_unzoned_band_count": exterior_unzoned_band_count,
		"segments": segments,
		"zone_flux": zone_flux,
	}


## Suma con signo por (lado, zona): positivo entra en esa zona, negativo sale.
## El lado exterior no tiene zonas y se ignora aqui.
func _accumulate_zone_flux(
		zone_flux: Dictionary,
		side: String,
		zone: String,
		mass_kg: float,
		energy_kj: float
	) -> void:
	if zone.is_empty():
		return
	var key: String = "%s|%s" % [side, zone]
	var entry: Dictionary = zone_flux.get(key, {
		"side": side, "zone": zone, "mass_kg": 0.0, "energy_kj": 0.0,
	})
	entry["mass_kg"] = float(entry["mass_kg"]) + mass_kg
	entry["energy_kj"] = float(entry["energy_kj"]) + energy_kj
	zone_flux[key] = entry


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


## ============================================================
## F2.2B: preparacion canonica y cierre autoritativo con F2.2A.
## ============================================================

## Identificador del nodo exterior en la entrada canonica. El exterior no es
## una sala: es una presion impuesta.
const EXTERIOR_ROOM_ID: String = "outside"

const NETWORK_ROOM_KEYS: Array[String] = [
	"floor_z_m", "floor_area_m2", "height_m",
	"upper_gas_kg", "lower_gas_kg", "upper_energy_kj", "lower_energy_kj",
]
const NETWORK_SOURCE_KEYS: Array[String] = [
	"upper_mass_kg_s", "lower_mass_kg_s", "upper_enthalpy_kw", "lower_enthalpy_kw",
]


func _prepare_network(
		rooms: Array,
		openings: Array,
		outside: Dictionary,
		sources: Dictionary,
		dt_s: float,
		options: Dictionary,
		errors: Array[String]
	) -> Dictionary:
	if not is_finite(dt_s) or dt_s <= 0.0:
		errors.append("dt_s must be finite and > 0")
	var exterior_pressure_abs_pa: float = float(outside.get("pressure_abs_pa", NAN))
	var exterior_temp_k: float = float(outside.get("temp_k", NAN))
	var reference_temp_k: float = float(outside.get("reference_temp_k", exterior_temp_k))
	for pair in [["pressure_abs_pa", exterior_pressure_abs_pa],
			["temp_k", exterior_temp_k], ["reference_temp_k", reference_temp_k]]:
		if not is_finite(float(pair[1])) or float(pair[1]) <= 0.0:
			errors.append("outside %s must be finite and > 0" % pair[0])
	if outside.has("density_kg_m3"):
		var declared_density: float = float(outside["density_kg_m3"])
		if not is_finite(declared_density) or declared_density <= 0.0:
			errors.append("outside density_kg_m3 must be finite and > 0")
	if not errors.is_empty():
		return {}

	# --- salas ---------------------------------------------------------------
	var by_id: Dictionary = {}
	var ordered_ids: Array[String] = []
	for raw_room in rooms:
		if typeof(raw_room) != TYPE_DICTIONARY:
			errors.append("each room must be a dictionary")
			continue
		var room: Dictionary = raw_room
		var room_id: String = String(room.get("room_id", ""))
		if room_id.strip_edges().is_empty():
			errors.append("each room needs a non-empty room_id")
			continue
		if room_id == EXTERIOR_ROOM_ID:
			errors.append("'%s' is reserved for the exterior node" % EXTERIOR_ROOM_ID)
			continue
		if by_id.has(room_id):
			errors.append("room '%s' is listed twice" % room_id)
			continue
		var checked: Dictionary = {"room_id": room_id}
		for key in NETWORK_ROOM_KEYS:
			if not room.has(key):
				errors.append("room '%s' is missing '%s'" % [room_id, key])
				continue
			var value: float = float(room[key])
			if not is_finite(value):
				errors.append("room '%s' %s must be finite" % [room_id, key])
				continue
			checked[key] = value
		if checked.size() != NETWORK_ROOM_KEYS.size() + 1:
			continue
		if float(checked["floor_area_m2"]) <= 0.0 or float(checked["height_m"]) <= 0.0:
			errors.append("room '%s' needs floor_area_m2 and height_m > 0" % room_id)
		if float(checked["upper_gas_kg"]) < 0.0 or float(checked["lower_gas_kg"]) < 0.0:
			errors.append("room '%s' cannot hold negative mass" % room_id)
		var volume_m3: float = float(checked["floor_area_m2"]) * float(checked["height_m"])
		if room.has("volume_m3"):
			var declared_volume: float = float(room["volume_m3"])
			if not is_finite(declared_volume) or declared_volume <= 0.0 \
					or absf(declared_volume - volume_m3) > 1.0e-9 * volume_m3:
				errors.append("room '%s' volume_m3 must be floor_area_m2 * height_m" % room_id)
			volume_m3 = declared_volume
		checked["volume_m3"] = volume_m3
		by_id[room_id] = checked
		ordered_ids.append(room_id)
	if ordered_ids.is_empty() and errors.is_empty():
		errors.append("the network needs at least one room")
	if not errors.is_empty():
		return {}
	ordered_ids.sort()

	var index_by_id: Dictionary = {}
	var historical_rooms: Dictionary = {}
	var historical_sources: Dictionary = {}
	var source_rates: Dictionary = {}
	for position in range(ordered_ids.size()):
		var room_id: String = ordered_ids[position]
		index_by_id[room_id] = position
		var room: Dictionary = by_id[room_id]
		historical_rooms[str(position)] = {
			"volume_m3": float(room["volume_m3"]),
			"floor_area_m2": float(room["floor_area_m2"]),
			"height_m": float(room["height_m"]),
			"floor_z_m": float(room["floor_z_m"]),
			"upper_gas_kg": float(room["upper_gas_kg"]),
			"lower_gas_kg": float(room["lower_gas_kg"]),
			"upper_energy_kj": float(room["upper_energy_kj"]),
			"lower_energy_kj": float(room["lower_energy_kj"]),
		}
		var rates: Dictionary = {}
		var declared_source: Variant = sources.get(room_id, {})
		if typeof(declared_source) != TYPE_DICTIONARY:
			errors.append("sources for room '%s' must be a dictionary" % room_id)
			continue
		var source_dict: Dictionary = declared_source
		for key in NETWORK_SOURCE_KEYS:
			var rate: float = float(source_dict.get(key, 0.0))
			if not is_finite(rate):
				errors.append("source '%s' of room '%s' must be finite" % [key, room_id])
				rate = 0.0
			rates[key] = rate
		source_rates[room_id] = rates
		# El nucleo historico recibe totales del paso; las tasas por zona se
		# conservan para el estado candidato y para F2.2A.
		historical_sources[str(position)] = {
			"mass_kg": dt_s * (float(rates["upper_mass_kg_s"]) + float(rates["lower_mass_kg_s"])),
			"energy_kj": dt_s * (float(rates["upper_enthalpy_kw"]) + float(rates["lower_enthalpy_kw"])),
		}
	for unknown_id in sources.keys():
		if not by_id.has(String(unknown_id)):
			errors.append("sources name unknown room '%s'" % unknown_id)
	if not errors.is_empty():
		return {}

	# --- aberturas -----------------------------------------------------------
	var opening_ids: Array[String] = []
	var opening_by_id: Dictionary = {}
	for raw_opening in openings:
		if typeof(raw_opening) != TYPE_DICTIONARY:
			errors.append("each opening must be a dictionary")
			continue
		var opening: Dictionary = raw_opening
		var opening_id: String = String(opening.get("opening_id", ""))
		if opening_id.strip_edges().is_empty():
			errors.append("each opening needs a non-empty opening_id")
			continue
		if opening_by_id.has(opening_id):
			errors.append("opening '%s' is listed twice" % opening_id)
			continue
		opening_by_id[opening_id] = opening
		opening_ids.append(opening_id)
	if not errors.is_empty():
		return {}
	opening_ids.sort()

	var historical_openings: Array = []
	var opening_index_by_id: Dictionary = {}
	for position in range(opening_ids.size()):
		var opening_id: String = opening_ids[position]
		var opening: Dictionary = opening_by_id[opening_id]
		opening_index_by_id[opening_id] = position
		var room_a_id: String = String(opening.get("room_a_id", ""))
		var room_b_id: String = String(opening.get("room_b_id", ""))
		var a_exterior: bool = room_a_id == EXTERIOR_ROOM_ID
		var b_exterior: bool = room_b_id == EXTERIOR_ROOM_ID
		if a_exterior and b_exterior:
			errors.append("opening '%s' cannot join the exterior to itself" % opening_id)
			continue
		if (not a_exterior and not by_id.has(room_a_id)) \
				or (not b_exterior and not by_id.has(room_b_id)):
			errors.append("opening '%s' names an unknown room" % opening_id)
			continue
		if room_a_id == room_b_id:
			errors.append("opening '%s' joins a room to itself" % opening_id)
			continue
		var span: Dictionary = _network_opening_span(
			opening, opening_id, room_a_id, room_b_id, a_exterior, b_exterior, by_id, errors
		)
		if span.is_empty():
			continue
		var width_m: float = float(opening.get("width_m", NAN))
		var open_fraction: float = float(opening.get("open_fraction", NAN))
		var discharge_coeff: float = float(opening.get("discharge_coeff", NAN))
		if not is_finite(width_m) or width_m <= 0.0:
			errors.append("opening '%s' needs width_m > 0" % opening_id)
		if not is_finite(open_fraction) or open_fraction < 0.0 or open_fraction > 1.0:
			errors.append("opening '%s' needs open_fraction in [0, 1]" % opening_id)
		if not is_finite(discharge_coeff) or discharge_coeff <= 0.0:
			errors.append("opening '%s' needs discharge_coeff > 0" % opening_id)
		var wind_dp_pa: float = float(opening.get("wind_dp_pa", 0.0))
		if not is_finite(wind_dp_pa):
			errors.append("opening '%s' wind_dp_pa must be finite" % opening_id)
			wind_dp_pa = 0.0
		if wind_dp_pa != 0.0 and not a_exterior and not b_exterior:
			errors.append("opening '%s' is interior and cannot carry wind" % opening_id)
		historical_openings.append({
			"opening_id": position,
			"room_a_id": EXTERIOR_ID if a_exterior else int(index_by_id[room_a_id]),
			"room_b_id": EXTERIOR_ID if b_exterior else int(index_by_id[room_b_id]),
			"bottom_z_m": float(span["bottom_z_m"]),
			"top_z_m": float(span["top_z_m"]),
			"width_m": width_m,
			"open_fraction": open_fraction,
			"discharge_coeff": discharge_coeff,
			"wind_dp_pa": wind_dp_pa,
		})
	if not errors.is_empty():
		return {}

	var historical_options: Dictionary = {
		"exterior_pressure_abs_pa": exterior_pressure_abs_pa,
		"exterior_temp_k": exterior_temp_k,
	}
	for key in ["max_iterations", "residual_tolerance", "dp_regularization_pa",
			"jacobian_step_pa", "band_segments", "max_damping_halvings",
			"pressure_tolerance_pa", "mass_tolerance_kg", "energy_tolerance_kj"]:
		if options.has(key):
			historical_options[key] = options[key]
	return {
		"rooms": historical_rooms,
		"openings": historical_openings,
		"sources": historical_sources,
		"source_rates": source_rates,
		"options": historical_options,
		"reference_temp_c": reference_temp_k - 273.15,
		"reference_temp_k": reference_temp_k,
		"exterior_pressure_abs_pa": exterior_pressure_abs_pa,
		"exterior_temp_k": exterior_temp_k,
		"ordered_ids": ordered_ids,
		"index_by_id": index_by_id,
		"room_by_id": by_id,
		"opening_ids": opening_ids,
		"opening_index_by_id": opening_index_by_id,
	}


## Cota de una abertura. Se admite forma absoluta (`bottom_z_m`/`top_z_m`) o
## local a la sala (`bottom_m`/`top_m` con `height_reference = "local"`), pero
## NUNCA las dos a la vez: mezclarlas en silencio es exactamente el defecto que
## esta convencion evita.
func _network_opening_span(
		opening: Dictionary,
		opening_id: String,
		room_a_id: String,
		room_b_id: String,
		a_exterior: bool,
		b_exterior: bool,
		room_by_id: Dictionary,
		errors: Array[String]
	) -> Dictionary:
	var has_absolute: bool = opening.has("bottom_z_m") or opening.has("top_z_m")
	var has_local: bool = opening.has("bottom_m") or opening.has("top_m")
	if has_absolute and has_local:
		errors.append("opening '%s' mixes absolute and local heights" % opening_id)
		return {}
	var declared_reference: String = String(opening.get("height_reference", ""))
	if has_absolute and declared_reference == "local":
		errors.append("opening '%s' declares local heights but gives absolute keys" % opening_id)
		return {}
	if has_local and declared_reference != "local":
		errors.append("opening '%s' must declare height_reference = \"local\"" % opening_id)
		return {}
	if not has_absolute and not has_local:
		errors.append("opening '%s' needs a vertical span" % opening_id)
		return {}
	var bottom_m: float = float(opening.get("bottom_z_m", opening.get("bottom_m", NAN)))
	var top_m: float = float(opening.get("top_z_m", opening.get("top_m", NAN)))
	if not is_finite(bottom_m) or not is_finite(top_m) or top_m <= bottom_m:
		errors.append("opening '%s' needs a finite span with top above bottom" % opening_id)
		return {}
	if has_local:
		# Una cota local solo es univoca si las dos salas tienen el mismo suelo.
		var floor_a_z_m: float = 0.0
		var floor_b_z_m: float = 0.0
		if not a_exterior:
			floor_a_z_m = float(room_by_id[room_a_id]["floor_z_m"])
		if not b_exterior:
			floor_b_z_m = float(room_by_id[room_b_id]["floor_z_m"])
		if a_exterior:
			floor_a_z_m = floor_b_z_m
		if b_exterior:
			floor_b_z_m = floor_a_z_m
		if absf(floor_a_z_m - floor_b_z_m) > 1.0e-9:
			errors.append(
				"opening '%s' uses local heights between floors at different levels" % opening_id
			)
			return {}
		bottom_m += floor_a_z_m
		top_m += floor_a_z_m
	return {"bottom_z_m": bottom_m, "top_z_m": top_m}


## Cierre del punto fijo: estado candidato por zona, veredicto de F2.2A y
## criterios de convergencia. Todo sale de la MISMA evaluacion aceptada.
func _finish_network(
		result: Dictionary,
		prepared: Dictionary,
		context: Dictionary,
		evaluation: Dictionary,
		pressure: Array,
		dt_s: float,
		solved: Dictionary
	) -> Dictionary:
	var equations = CompartmentPressureEquationsScript
	var outside_state: Dictionary = {
		"pressure_abs_pa": float(prepared["exterior_pressure_abs_pa"]),
		"temp_k": float(prepared["exterior_temp_k"]),
		"reference_temp_k": float(prepared["reference_temp_k"]),
	}
	var zone_flux_by_room: Dictionary = evaluation["zone_flux_by_room"]
	var flux_by_room: Dictionary = _network_flux_by_room(prepared, context, evaluation, dt_s)

	var rooms_out: Array = []
	var max_mass_residual_kg: float = 0.0
	var max_energy_residual_kj: float = 0.0
	var max_pressure_residual_pa: float = 0.0
	var all_valid: bool = true
	var errors: Array[String] = []
	for room_id in prepared["ordered_ids"]:
		var index: int = int(prepared["index_by_id"][room_id])
		var room_key: String = str(index)
		var source: Dictionary = prepared["source_rates"][room_id]
		var previous: Dictionary = prepared["room_by_id"][room_id]
		var zone_flux: Dictionary = zone_flux_by_room.get(room_key, {})
		var gauge_pressure_pa: float = float(pressure[index])
		var candidate: Dictionary = {
			"room_id": room_id,
			"floor_z_m": float(previous["floor_z_m"]),
			"height_m": float(previous["height_m"]),
			"floor_area_m2": float(previous["floor_area_m2"]),
			"gauge_pressure_pa": gauge_pressure_pa,
		}
		for zone in [ZONE_UPPER, ZONE_LOWER]:
			var entry: Dictionary = zone_flux.get(zone, {"mass_kg": 0.0, "energy_kj": 0.0})
			candidate["%s_gas_kg" % zone] = float(previous["%s_gas_kg" % zone]) \
					+ dt_s * float(source["%s_mass_kg_s" % zone]) + float(entry["mass_kg"])
			candidate["%s_energy_kj" % zone] = float(previous["%s_energy_kj" % zone]) \
					+ dt_s * float(source["%s_enthalpy_kw" % zone]) + float(entry["energy_kj"])
		var previous_state: Dictionary = {
			"room_id": room_id,
			"floor_z_m": float(previous["floor_z_m"]),
			"height_m": float(previous["height_m"]),
			"floor_area_m2": float(previous["floor_area_m2"]),
			"upper_gas_kg": float(previous["upper_gas_kg"]),
			"lower_gas_kg": float(previous["lower_gas_kg"]),
			"upper_energy_kj": float(previous["upper_energy_kj"]),
			"lower_energy_kj": float(previous["lower_energy_kj"]),
		}
		# F2.2A manda: si rechaza el candidato, el solver no lo acepta.
		var verdict: Dictionary = equations.evaluate_compartment_residual(
			previous_state, candidate, source, flux_by_room.get(room_id, []),
			outside_state, dt_s
		)
		var room_out: Dictionary = {
			"room_id": room_id,
			"reference_z_m": float(previous["floor_z_m"]),
			"gauge_pressure_pa": gauge_pressure_pa,
			"pressure_abs_pa": float(prepared["exterior_pressure_abs_pa"]) + gauge_pressure_pa,
			"candidate_upper_gas_kg": float(candidate["upper_gas_kg"]),
			"candidate_lower_gas_kg": float(candidate["lower_gas_kg"]),
			"candidate_upper_energy_kj": float(candidate["upper_energy_kj"]),
			"candidate_lower_energy_kj": float(candidate["lower_energy_kj"]),
			"net_mass_kg_s": float(evaluation["net_mass_by_room"].get(room_key, 0.0)) / dt_s,
			"net_enthalpy_kw": float(evaluation["net_energy_by_room"].get(room_key, 0.0)) / dt_s,
			"equations_valid": bool(verdict["valid"]),
			"equations_errors": verdict["errors"],
			"pressure_profile": verdict["pressure_profile"],
			"mass_residual_kg": float(verdict["mass_residual_kg"]),
			"energy_residual_kj": float(verdict["energy_residual_kj"]),
			"pressure_residual_pa": float(verdict["pressure_residual_pa"]),
			"diagnostics": verdict["diagnostics"],
		}
		if not bool(verdict["valid"]):
			all_valid = false
			errors.append("room '%s' rejected by the compartment equations: %s" % [
				room_id, str(verdict["errors"])
			])
		else:
			max_mass_residual_kg = maxf(max_mass_residual_kg, absf(float(verdict["mass_residual_kg"])))
			max_energy_residual_kj = maxf(
				max_energy_residual_kj, absf(float(verdict["energy_residual_kj"]))
			)
			max_pressure_residual_pa = maxf(
				max_pressure_residual_pa, absf(float(verdict["pressure_residual_pa"]))
			)
		rooms_out.append(room_out)

	result["rooms"] = rooms_out
	result["openings"] = _network_openings(prepared, context, evaluation, dt_s)
	result["max_mass_residual_kg"] = max_mass_residual_kg
	result["max_energy_residual_kj"] = max_energy_residual_kj
	result["max_pressure_residual_pa"] = max_pressure_residual_pa
	result["errors"] = errors

	var options: Dictionary = prepared["options"]
	var pressure_tolerance_pa: float = float(options.get(
		"pressure_tolerance_pa", DEFAULT_PRESSURE_TOLERANCE_PA))
	var mass_tolerance_kg: float = float(options.get(
		"mass_tolerance_kg", DEFAULT_MASS_TOLERANCE_KG))
	var energy_tolerance_kj: float = float(options.get(
		"energy_tolerance_kj", DEFAULT_ENERGY_TOLERANCE_KJ))

	# Convergencia fisica: todos los criterios a la vez. Agotar iteraciones,
	# bajar el residuo o dar un paso pequeño no bastan por si solos.
	var unclassified: float = float(solved.get("zonal_unclassified_interior_band_count", 0.0))
	var reasons: Array[String] = []
	if not all_valid:
		reasons.append("compartment_equations_rejected_candidate")
	if max_pressure_residual_pa > pressure_tolerance_pa:
		reasons.append("pressure_closure_above_tolerance")
	if max_mass_residual_kg > mass_tolerance_kg:
		reasons.append("mass_residual_above_tolerance")
	if max_energy_residual_kj > energy_tolerance_kj:
		reasons.append("energy_residual_above_tolerance")
	if unclassified > 0.0:
		reasons.append("unclassified_interior_band")
	# El criterio de presion es el cambio que TODAVIA se debe, no el tamano del
	# ultimo paso aceptado: un paso de Newton puede ser grande y aterrizar justo
	# en la solucion. Ese cambio pendiente es exactamente el cierre de F2.2A en
	# Pa, ya comprobado arriba. El historial de cambios se publica como
	# diagnostico.
	result["owed_pressure_change_pa"] = max_pressure_residual_pa
	if reasons.is_empty():
		result["valid"] = true
		result["converged"] = true
		result["failure_reason"] = ""
		result["failure_code"] = FAILURE_NONE
	else:
		result["valid"] = false
		result["converged"] = false
		result["failure_reason"] = reasons[0]
		result["failure_code"] = FAILURE_NOT_CONVERGED
		for reason in reasons:
			result["errors"].append(reason)
	return result


## Flujos por abertura y zona, en tasas, tal como los consume F2.2A.
func _network_flux_by_room(
		prepared: Dictionary,
		context: Dictionary,
		evaluation: Dictionary,
		dt_s: float
	) -> Dictionary:
	var by_room: Dictionary = {}
	var id_by_index: Dictionary = {}
	for room_id in prepared["ordered_ids"]:
		id_by_index[int(prepared["index_by_id"][room_id])] = room_id
		by_room[room_id] = []
	var opening_id_by_index: Dictionary = {}
	for opening_id in prepared["opening_ids"]:
		opening_id_by_index[int(prepared["opening_index_by_id"][opening_id])] = opening_id
	for raw_connection in evaluation["connections"]:
		var connection: Dictionary = raw_connection
		var opening_label: String = String(opening_id_by_index.get(
			int(connection["opening_id"]), str(connection["opening_id"])
		))
		var totals: Dictionary = {}
		for raw_segment in connection.get("segments", []):
			var segment: Dictionary = raw_segment
			for side in ["source", "destination"]:
				var side_letter: String = String(segment["%s_side" % side])
				var zone: String = String(segment["%s_zone" % side])
				if zone.is_empty():
					continue
				var room_index: int = int(connection["room_a_id"]) if side_letter == "a" \
						else int(connection["room_b_id"])
				if not id_by_index.has(room_index):
					continue
				var sign: float = 1.0 if side == "destination" else -1.0
				var key: String = "%s|%d|%s" % [opening_label, room_index, zone]
				var entry: Dictionary = totals.get(key, {
					"room_index": room_index, "zone": zone,
					"mass_kg": 0.0, "energy_kj": 0.0,
				})
				entry["mass_kg"] = float(entry["mass_kg"]) + sign * float(segment["mass_kg"])
				entry["energy_kj"] = float(entry["energy_kj"]) + sign * float(segment["enthalpy_kj"])
				totals[key] = entry
		var keys: Array = totals.keys()
		keys.sort()
		for key in keys:
			var entry: Dictionary = totals[key]
			var room_id: String = String(id_by_index[int(entry["room_index"])])
			by_room[room_id].append({
				"opening_id": opening_label,
				"segment_id": String(entry["zone"]),
				"zone": String(entry["zone"]),
				"mass_flow_kg_s": float(entry["mass_kg"]) / dt_s,
				"enthalpy_flow_kw": float(entry["energy_kj"]) / dt_s,
			})
	return by_room


## Salida canonica por abertura y por segmento, con identificadores del
## llamante y no con los indices internos.
func _network_openings(
		prepared: Dictionary,
		context: Dictionary,
		evaluation: Dictionary,
		dt_s: float
	) -> Array:
	var id_by_index: Dictionary = {}
	for room_id in prepared["ordered_ids"]:
		id_by_index[int(prepared["index_by_id"][room_id])] = room_id
	var opening_id_by_index: Dictionary = {}
	for opening_id in prepared["opening_ids"]:
		opening_id_by_index[int(prepared["opening_index_by_id"][opening_id])] = opening_id
	var openings_out: Array = []
	for raw_connection in evaluation["connections"]:
		var connection: Dictionary = raw_connection
		var room_a_id: String = String(id_by_index.get(
			int(connection["room_a_id"]), EXTERIOR_ROOM_ID))
		var room_b_id: String = String(id_by_index.get(
			int(connection["room_b_id"]), EXTERIOR_ROOM_ID))
		var segments_out: Array = []
		for raw_segment in connection.get("segments", []):
			var segment: Dictionary = raw_segment
			var source_is_a: bool = String(segment["source_side"]) == "a"
			segments_out.append({
				"segment_id": String(segment["segment_id"]),
				"z_from_m": float(segment["z_from_m"]),
				"z_to_m": float(segment["z_to_m"]),
				"sample_z_m": float(segment["sample_z_m"]),
				"dp_pa": float(segment["dp_pa"]),
				"direction": String(segment["direction"]),
				"source_room_id": room_a_id if source_is_a else room_b_id,
				"source_zone": String(segment["source_zone"]),
				"destination_room_id": room_b_id if source_is_a else room_a_id,
				"destination_zone": String(segment["destination_zone"]),
				"source_density_kg_m3": float(segment["source_density_kg_m3"]),
				"mass_flow_kg_s": float(segment["mass_kg"]) / dt_s,
				"enthalpy_flow_kw": float(segment["enthalpy_kj"]) / dt_s,
				"regularized": bool(segment["regularized"]),
			})
		openings_out.append({
			"opening_id": String(opening_id_by_index.get(
				int(connection["opening_id"]), str(connection["opening_id"]))),
			"room_a_id": room_a_id,
			"room_b_id": room_b_id,
			"neutral_plane_z_m": float(connection["neutral_plane_m"]),
			"neutral_plane_inside": bool(connection["neutral_plane_inside"]),
			"net_mass_kg_s": float(connection["net_mass_a_to_b_kg"]) / dt_s,
			"wind_dp_pa": float(connection.get("exterior_gauge_pa", 0.0)),
			"segments": segments_out,
		})
	return openings_out

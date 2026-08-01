# Phase 3+ F3.3v3h2.9 - uk_bungalow damping-exhausted diagnosis

Date: 2026-08-01

Status: **GO as diagnosis only. NO-GO for changing the motor in this phase.**

H2 remains open. H3 remains blocked.

## Scope

H2.8 removed every `iteration_cap` in the ten-case topology corpus but left
one distinct failure mode in `uk_bungalow_smoke`: `damping_exhausted` after
the ordinary Newton line search and the single bounded LM recovery had both
been used. This phase diagnoses that exact, versioned failure without changing
`sim/core`, solver constants, validation reports, expected values, tolerances,
CTRL envelopes or VALID_GAP classifications.

The exact input is:

`tests/fixtures/data/coupled_solver_damping_exhausted_uk_bungalow.json`

The read-only harness is:

`tools/diagnostics/phase3_h29_uk_damping_anatomy.gd`

It replays the solver's current gauge-pressure equations and records every
Newton trial, LM trial, residual component, Jacobian condition and opening
branch. It also compares candidate differentiation policies over all nine
versioned captures and deterministic neighbourhoods of those captures.

## Exact reproduction

The shipped solver reproduces the capture exactly:

| Result | Value |
|---|---:|
| converged | false |
| limiting reason | `damping_exhausted` |
| iterations | 12 |
| final L-infinity residual | `6.43957668480162e-6` |
| final L2 merit | `4.32397744861877e-11` |
| accepted LM rescues | 1 |
| remaining LM budget | 0 |

Iterations 1-9 accept damped Newton steps. Iteration 10 cannot find an
L-infinity-decreasing Newton step, so LM accepts one step at lambda `1e-3`.
Iteration 11 accepts Newton at damping `0.125`. Iteration 12 again finds no
decreasing Newton trial, but the LM budget is already spent.

## LM budget is not the cause

Increasing only the offline LM budget does not close the solve:

| Accepted-step budget | Result | Iterations | Final residual |
|---:|---|---:|---:|
| 1 (shipped) | damping_exhausted | 12 | `6.4396e-6` |
| 2 | damping_exhausted | 15 | `4.3788e-6` |
| 4 | damping_exhausted | 24 | `4.2919e-6` |

A forced second LM step is available and initially decreases the L2 merit, but
the trajectory reaches the same class of dead end again. Raising or removing
`LM_RESCUE_MAX_ACCEPTED_STEPS` is therefore **NO-GO**: it treats repeated bad
Jacobians as a budget problem and does not remove the cause.

## Root cause

At the final failed iteration, opening 1 has gauge pressure difference
`-5.3073730305897e-4 Pa`. The shipped forward-difference width is `1e-3 Pa`.
Perturbing room column 1 by that width changes the opening to
`+4.69262696938699e-4 Pa`: the quotient crosses zero and changes the donor
side used by the upwind flux law.

This matters because the regularized flux is only piecewise differentiable at
zero when the two donor densities or specific enthalpies differ. Below the
`0.01 Pa` regularization scale the magnitude is linear in `abs(dp)`, but the
coefficient still changes with the donor. A unilateral quotient that crosses
zero is a secant through two different branches, not the local derivative
used by the subsequent line search.

The failure trace confirms that mismatch:

- Jacobian condition is finite (`1.17e4`), not singular.
- The linear model predicts L2 descent.
- Every actual Newton trial increases both L-infinity and L2.
- Even the smallest trial (`alpha=1/4096`) increases L-infinity by 1.28%.
- The small actual trials remain on the original branch; the forward
  Jacobian perturbation does not.

At the same state:

| Jacobian | Best L-inf ratio | Best L2 ratio | Verdict |
|---|---:|---:|---|
| forward `h=1e-3` | 1.01283 | 1.02516 | no descent |
| forward `h=1e-4` | 1.00120 | 1.00231 | no descent at this state |
| forward `h=1e-5` | 0.16986 | 0.01911 | strong descent |
| forward `h=1e-6` | 0.01772 | 0.000208 | strong descent |
| central `h=1e-4` | 0.00319 | `6.77e-6` | strong descent |

Central differencing is not recommended: H2.5c already measured a catastrophic
runtime regression on `r0_window_360` (86.33% to 0.14% convergence). This phase
does not reopen that rejected path.

## Candidate comparison

### Fixed smaller forward width

The exact UK capture converges in 8 iterations with forward widths `1e-4`,
`1e-5` and `1e-6`, with no LM rescue. Across all nine exact captures, all
other captures continue to converge. Maximum shared-root delta is:

- `7.23e-11 Pa` for `1e-4`;
- `2.07e-11 Pa` for `1e-5`;
- `5.62e-11 Pa` for `1e-6`.

Across 189 deterministic perturbed states (21 per capture):

| Policy | Baseline successes | Candidate successes | Regressions | Gains |
|---|---:|---:|---:|---:|
| forward `h=1e-4` | 182 | 189 | 0 | 7 |
| forward `h=1e-5` | 182 | 189 | 0 | 7 |

The maximum shared-root difference is `7.11e-10 Pa`. All seven gains belong
to the UK topology.

This is strong evidence that the shipped width is too large near the donor
kink, but changing `1e-3` to a selected decimal globally would still be a
numerical tuning decision without a policy tied to local branch geometry.

### Branch-preserving unilateral quotient

An offline candidate keeps `h=1e-3` but evaluates both unilateral directions
for each pressure column and chooses the side with fewer opening branch
changes (pressure sign, neutral-plane state, donor direction and
regularization membership).

The exact UK capture converges in 11 iterations at `3.39e-13`, with no LM
rescue. The other eight captures remain converged; maximum shared-root delta is
`9.11e-12 Pa`.

On the 189-state neighbourhood:

| Baseline successes | Candidate successes | Regressions | Gains |
|---:|---:|---:|---:|
| 182 | 187 | 0 | 5 |

Two perturbed UK states still end in `damping_exhausted` at residuals
`2.55e-6` and `1.29e-5`. Branch selection removes the dominant discontinuity
but does not guarantee a sufficiently local quotient in every curved region.
It is therefore a design direction, not yet a complete fix.

## H2.10 recommendation

Do not raise the iteration cap, expand LM budget, restore central differences
or simply replace the global Jacobian width.

H2.10 should implement and audit a **branch-preserving adaptive unilateral
Jacobian**:

1. Keep the shipped forward quotient for columns where its perturbation stays
   on the same opening branches and the derivative is locally stable.
2. Where it crosses a donor, neutral-plane or regularization boundary, compare
   the opposite unilateral direction.
3. If neither side is locally stable, reduce the column width by a deterministic
   scale hierarchy derived from the existing `dp_regularization_pa`, not from
   a case name or topology.
4. Require derivative self-consistency across two widths before accepting the
   column; expose passive counters for reversed and reduced columns.
5. Preserve the existing Newton, L-infinity convergence, analytic half step,
   LM rescue, cap, EOS, orifice law and counterflow equations.

The H2.10 STOP gate must include:

- all nine exact captures;
- the 189-state deterministic neighbourhood;
- the ten committed runtime topology cases from H2.8;
- OFF byte identity and shared ON-column identity;
- zero converged-to-failed solves;
- root-delta bound reported rather than hidden;
- counterflow, mass and energy conservation;
- deterministic complete runs with row-count validation;
- explicit evidence that LM usage falls in UK rather than merely moving the
  failure to another recovery branch.

H2 may close only after that runtime gate and after the C8 parallel-opening
coverage decision is recorded. H3 remains blocked until H2 closes.

## STOP decision

**GO to record H2.9 as a diagnosis. NO-GO for a motor commit in H2.9.**

The root cause is sufficiently localized to design H2.10, but neither offline
candidate has yet passed the required runtime matrix as an implemented motor
policy.

Final checks:

| Check | Result |
|---|---|
| H2.9 structural contracts | 16/16 PASS |
| Physics coherence | 9 PASS / 15 CTRL / 5 WARN / 0 FAIL |
| ILV coherence | 15 PASS / 14 CTRL / 0 FAIL |
| Gap inventory | sync OK - 353 required, 6 VALID_GAP, 71 non-gating |
| Validation guardrails | 10/10 PASS |
| Godot 4.7.1 diagnostic run | PASS, sequential, explicit log, no warning |
| Residual Godot processes | 0 |

The broad `pytest` collection attempted during this phase is explicitly not a
gate result: it invoked a direct Godot fixture inside the restricted process
environment, failed to open `user://logs`, and crashed with signal 11. That
run was invalidated. It did not modify reports or motor state. Godot fixtures
must remain sequential, outside the sandbox and use an explicit log path.

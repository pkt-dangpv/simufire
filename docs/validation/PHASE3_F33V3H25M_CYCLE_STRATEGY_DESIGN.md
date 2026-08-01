# Phase 3+ F3.3v3h2.5m Post-Budget Cycle Strategy Design

Date: 2026-07-31.

Diagnostic phase only. `sim/core` was read, never modified. No runtime
authority was added, no threshold was calibrated, and H2.5m implementation has
not begun.

## Summary

The post-budget period-2 cycle is **not** a numerical artifact. It is the exact
analytic fixed-point structure of Newton's method applied to a residual that is
homogeneous of degree `1/2` along the step direction, which is what the orifice
flow law `sqrt(2 rho dp)` makes it.

For `F(u) = C sign(u) |u|^(1/2)` the Newton map is

```text
u_new = u - F/F' = u - 2u = -u
```

a period-2 orbit with multiplier exactly `-1`. Damped Newton with factor
`theta` gives `u -> (1 - 2 theta) u`, so `theta = 1` reproduces the observed
cycle exactly and **`theta = 1/2` annihilates it in one step**. That value is
analytic, not fitted.

## Corpus provenance defect, found first

Three records report `corridor_chain 120 s` differently:

| Record | converged | iteration_cap | damping_exhausted | detects | after budget |
|---|---:|---:|---:|---:|---:|
| H2.5g (2026-07-28) | 84.18% | 217 | 11 | - | - |
| H2.5l-A (2026-07-29) | 92.16% | 113 | 0 | 2722 | 2211 |
| H2.5l-B (2026-07-29) | 73.77% | 378 | 0 | 9558 | 8835 |

H2.5g to H2.5l-A is explained by the H2.5j cycle guard. **H2.5l-A to H2.5l-B is
not**: both are purely passive and cannot move the trajectory.

Determinism was tested directly. Three independent runs of
`sim/validation/cases/cfast_corridor_chain.json` at 120 s produced the
identical CSV:

```text
9a50cdf2d6a20c39c8701720bc3925da7eaae82abc205eb1d78dcc8aa47ce971
```

including the earlier H2.5l-B artifact. **The runtime is deterministic.** The
committed case gives 378 `iteration_cap`.

H2.5l-A's runtime matrix was therefore measured on the "scratch case
definitions" its own text admits are mutable, and is not reproducible from the
repository. The contraction ranges `0.7731..1.0465` / `1.0038..1.0480` that
H2.5l-A used to conclude "contraction does not separate the topologies" come
from that unpinned corpus and carry no weight here. Nothing in H2.5l-B is
affected: its numbers reproduce exactly.

**Any H2.5m runtime matrix must cite the committed case files only.**

## Diagnosis

`tools/diagnostics/phase3_h25m_cycle_trace.gd` replays the captured late
corridor solve through the committed solver's own primitives and instruments
every iteration. It reproduces the shipped outcome exactly: 24 iterations,
`iteration_cap`, first residual `2.775125e-03`.

### What the cycle is not

| Hypothesis | Test | Result |
|---|---|---|
| Jacobian differencing error | sweep `h` over `1e-6..1e0` | **refuted** - direction cosine `+1.000000` and step norm stable to 0.05% across four decades |
| One-sided vs central difference | central difference at the same point | **refuted** - gain ratio `0.00909` vs `0.00841`, cosine between the two steps `0.99999989` |
| Switching-manifold chatter | per-connection `dp` census | **refuted** - `dp = ±0.92` and `±0.35 Pa`, three orders above the `0.01 Pa` regularization |
| Regularization boundary | `regularization_active_count` | **refuted** - exactly `0` on every iteration |
| Neutral-plane crossing | `neutral_plane_inside` | **refuted** - `false` on every iteration |

The residual is smooth, the Jacobian is a faithful derivative of it, and the
connections are far from any kink. None of the assumed mechanisms survive.

### What the cycle is

The merit along the Newton direction, `p + alpha * s`, has a sharp minimum at
`alpha = 0.50`, identically at iteration 4 and iteration 14:

| alpha | merit | L-infinity |
|---:|---:|---:|
| 0.00 | 8.145716e-06 | 2.764388e-03 |
| 0.25 | 4.073931e-06 | 1.953156e-03 |
| **0.50** | **1.530194e-09** | **4.690597e-05** |
| 0.75 | 4.026346e-06 | 1.948171e-03 |
| 1.00 | 8.077189e-06 | 2.757000e-03 |

The full Newton step is **exactly twice too long**, and lands almost exactly as
far from the root as it started - hence cosine `-1.0000` and gain ratio
`0.0008..0.0084`.

The shape identifies the mechanism. `merit(0.25)/merit(0.00) = 0.500`, not the
`0.25` a parabola would give, so the merit is linear in `|alpha - 0.5|` and the
residual is its square root. Fitting `merit ~ |alpha - 0.5|^p`:

| Probe | exponent `p` | `R^2` | implied `\|F\| ~ \|u\|^(p/2)` |
|---|---:|---:|---:|
| iteration 4 | 1.00141 | 0.99990208 | 0.50070 |
| iteration 14 | 1.00137 | 0.99990937 | 0.50068 |

`|F| ~ |u|^0.5007`. The orifice law is visible in the convergence structure to
three decimal places.

### Consequence

The cycle is a genuine, smooth, analytic period-2 orbit. It is not pathological
and it does eventually decay - offline replay with the cap lifted to 400
converges at **204 iterations** and 819 residual evaluations. The shipped cap of
24 is nowhere near enough, and raising it is both forbidden and roughly 45 times
more expensive than the alternative below.

## Candidate strategies, measured

`tools/diagnostics/phase3_h25m_strategy_probe.gd`, all four committed captures,
shipped cap 24, shipped tolerance, shipped Jacobian.

- **S0** baseline as shipped.
- **S1** on period-2 cycle detection take the analytic half step
  (`theta = 1/2`), accepted only if it strictly decreases the residual; the
  H2.5g LM rescue is retained unchanged.
- **S2** half step only, LM rescue removed - a control, to test whether the two
  mechanisms are redundant.

| Capture | S0 | S1 | S2 |
|---|---|---|---|
| `failure_corridor_chain` | 6 it, `6.477e-17` | **6 it, `6.477e-17`** | **FAILS** `damping_exhausted` |
| `failure_r0_window_360` | 3 it, `9.523e-17` | **3 it, `9.523e-17`** | 3 it, `9.523e-17` |
| `iteration_cap_after_rescue_corridor_chain` | **FAILS** 24 it, `2.625e-03` | **4 it, `1.046e-16`** | 4 it, `1.046e-16` |
| `iteration_cap_corridor_chain` | 8 it, `1.664e-16` | **7 it, `4.137e-17`** | 7 it, `4.137e-17` |

Two findings:

1. **S1 fixes the capture nothing else could.** 24 iterations of failure become
   4 iterations to `1.046e-16`, using 18 residual evaluations instead of the
   819 the uncapped baseline needs.
2. **S2 proves the mechanisms are complementary, not redundant.** Removing the
   LM rescue breaks `failure_corridor_chain`. The LM rescue answers the
   `damping_exhausted` dead end where L-infinity refuses a trade (H2.5g); the
   half step answers the period-2 square-root orbit. They address different
   failures and both are required.

## Non-interference, measured

`tools/diagnostics/phase3_h25m_neighbourhood_sweep.gd` perturbs all four
captures over owner sources `x0.25..x3.0`, room energy `x0.98..x1.02` and
timestep `x0.5..x2.0`: **600 cases**, each solved by S0 and S1 at the shipped
cap and compared field by field.

| | S0 | S1 |
|---|---:|---:|
| converged | 527 / 600 (87.83%) | **596 / 600 (99.33%)** |
| fixed by candidate | - | **69** |
| **broken by candidate** | - | **0** |
| both converged, bit-identical | 334 | |
| both converged, differing | 193 | |
| **worst divergence over all 600** | | **1.857e-11 Pa** |

Per topology:

| Capture | cases | bit-identical | differing | fixed | broken |
|---|---:|---:|---:|---:|---:|
| `failure_r0_window_360` | 150 | **150** | **0** | 0 | 0 |
| `failure_corridor_chain` | 150 | 113 | 13 | 20 | 0 |
| `iteration_cap_corridor_chain` | 150 | 41 | 109 | 0 | 0 |
| `iteration_cap_after_rescue_corridor_chain` | 150 | 30 | 71 | 49 | 0 |

Two points must be stated precisely rather than overclaimed.

**This is not the bit-identical guarantee H2.5g had.** 193 of 527 shared
successes converge to a different field. The bound on that difference is
`1.857e-11 Pa` over the whole population, against gauge pressures of order
`1 Pa` - eleven orders below the physical scale, and at the level of the
`1e-12` tolerance ball rather than a different root. The worst case is
instructive: baseline `7.036e-13`, candidate `4.841e-16`. The fields differ
because **the candidate converges deeper**, not because it converges elsewhere.

**`r0_window_360` is completely inert.** 150 of 150 bit-identical, zero half
steps taken, zero divergence. That is the exact regression H2.5d caused with a
global merit change, and this candidate does not reproduce it.

## Why this satisfies the binding constraints

| Constraint | How it is met |
|---|---|
| no scenario-calibrated threshold | `theta = 1/2` is the analytic annihilator of a degree-`1/2` Newton orbit, derived not fitted; the measured `alpha_min` is `0.50` at two independent iterations |
| do not raise the iteration cap | cap stays 24; the candidate converges the failing capture in 4 |
| do not simply add LM rescues | rescue budget unchanged at 1; the half step is a different mechanism, and S2 shows the LM rescue is still load-bearing |
| do not relax tolerance | tolerance unchanged at `1e-12`; the candidate reaches deeper residuals than the baseline |
| do not alter openings, EOS, neutral plane, counterflow, physics | untouched; the flux law is the *diagnosis*, not the target |
| fail-only reachability | the half step is reachable only from an already-detected period-2 cycle and is accepted only on strict decrease; declined, it falls through to the existing paths |

## What is proven, and what is not

Proven:

- the mechanism, to `R^2 = 0.9999`;
- `theta = 1/2` is analytically optimal and empirically optimal;
- on four real captures: one previously unfixable failure fixed, no regression;
- on 600 perturbed cases: 69 fixed, **0 broken**, divergence bounded by
  `1.857e-11 Pa`;
- the `r0_window` topology is untouched;
- the LM rescue must be retained.

**Not** proven, and required before any GO on implementation:

- runtime scenario-matrix behaviour, which cannot be measured without changing
  `sim/core` and is therefore H2.5m implementation work;
- behaviour on topologies other than corridor and `r0_window` - the corpus is
  still two topologies, which is the same limitation H2.5l-B recorded;
- whether the corridor 120 s recurrence rate of 38.8% actually falls, which
  needs a runtime run against the **committed** case files.

## Implementation (2026-07-31)

`CYCLE_ANALYTIC_HALF_STEP = 0.5` in `Phase3CoupledPressureSolver.gd`, a global
constant that is never read from `options` or `context`. After a cycle is
detected the solver evaluates `pressure + 0.5 * step`, reusing the Newton
direction already in hand, and accepts it only if the evaluation is valid and
finite and the L-infinity residual strictly decreases. It is tried before the
H2.5j guard, costs exactly one extra residual evaluation, neither consumes nor
extends the LM budget, and is never convergence by itself. Declined, it writes
nothing and control falls through to the unchanged H2.5j/H2.5g path.

## Runtime matrix

Baseline from a clean worktree at `4ec0f09a`; candidate from the modified tree;
Godot 4.7.1, sequential, outside the sandbox, editor closed. Committed case
files only:

| case | SHA-256 |
|---|---|
| `cfast_corridor_chain.json` | `9e8eace869cf2f4f989d84c2f1bdf737320ddaea6f8789f608f1277b1ce1bef2` |
| `cfast_r0_window_360.json` | `660e50020d1f09c19f4c1e14c253c5f1a5e280cdd902296396d12ff82d2a4fdf` |

The baseline reproduced the H2.5l-B ledger exactly, including the corridor
120 s ON artifact SHA-256 `9a50cdf2...`, which confirms the worktree is a true
baseline.

| stage | solves | convergence b/a | iteration_cap b/a | damping_exhausted b/a | post-budget solves b/a | attempts/accepts | max accepts/solve | runtime b/a |
|---|---:|---|---:|---:|---|---:|---:|---|
| corridor 30 s | 361 | 98.06% -> **100.00%** | 7 -> **0** | 0 -> 0 | 17 -> **0** | 143 / 143 | 1 | 14 s -> 16 s |
| corridor 60 s | 720 | 99.03% -> **100.00%** | 7 -> **0** | 0 -> 0 | 17 -> **0** | 143 / 143 | 1 | 39 s -> 34 s |
| corridor 120 s | 1441 | 73.77% -> **100.00%** | 378 -> **0** | 0 -> 0 | 559 -> **0** | 723 / 723 | 1 | 63 s -> 74 s |
| r0-window 120 s | 1441 | 100.00% -> 100.00% | 0 -> 0 | 0 -> 0 | 0 -> 0 | 204 / 204 | 1 | 62 s -> 71 s |

Every stage converges on every solve. `iteration_cap` is eliminated. Attempts
equal accepts everywhere and the per-solve maximum is 1, so the half step never
declines and never fires twice in one solve - exactly what a one-step
annihilator of a period-2 orbit should do.

### Where the interventions went

| stage | LM rescues accepted b/a | cycle-guard accepts b/a |
|---|---:|---:|
| corridor 30 s | 145 -> 2 | 143 -> 0 |
| corridor 60 s | 148 -> 5 | 143 -> 0 |
| corridor 120 s | 728 -> **5** | 723 -> **0** |
| r0-window 120 s | 204 -> **0** | 204 -> 0 |

The half step displaced every cycle-guard rescue. On corridor 120 s exactly the
5 fail-only `damping_exhausted` rescues remain - the same 5 the baseline had
once its 723 cycle rescues are subtracted. The H2.5g path is untouched and
still load-bearing.

### r0-window: the offline prediction was incomplete

The offline sweep reported zero half steps on the `r0_window` capture, and the
runtime reports **204**. Both are correct and they are not the same
measurement. The capture is one specific `damping_exhausted` step, which the
half step correctly does not touch. The 120 s scenario contains 204 steps that
hit a period-2 cycle; the baseline sent all 204 to the LM cycle guard, and the
candidate closes them with a half step instead. Convergence stays at 100% and
the solved field is unchanged, so this is a cheaper mechanism reaching the same
root, not a behavioural regression. The fixture assertion "r0-window makes zero
attempts" holds for the capture and is stated at capture scope; at scenario
scope the honest number is 204.

## Gates

| Gate | Result |
|---|---|
| OFF CSV SHA-256 identical | **PASS**, all four stages |
| legacy ON columns unchanged | **PASS**, 0 differences over 594 columns x 4 stages |
| solves that converged and now fail | **0** |
| converged residual under original tolerance | **PASS**, `max_normalized_residual = 0.0` |
| counterflow violations | **0**, all stages |
| mass / energy conservation | physics coherence 0 FAIL |
| determinism | **PASS**, 3 repetitions of corridor 120 s ON plus the matrix run, 4/4 SHA-256 `5b383291...` |
| corpus-dependent threshold | **none**; the only constant is the analytic `0.5` |
| Godot residual processes | **0** |

### Shared-root divergence, stated precisely

On every logged row where baseline and candidate both converged, the solved
gauge pressure is **bit-identical** (worst delta `0.000000e+00`).

That is a weaker statement than it appears and must not be over-read: the CSV
samples at the 10 s cadence, so it observes 9 to 60 rows per stage out of up to
1441 solves. The stronger bound remains the offline one - `1.857e-11 Pa` over
600 perturbed cases, against gauge pressures of order 1 Pa, arising because the
candidate converges *deeper* than the baseline rather than elsewhere. Neither
measurement is a claim of bit-identity across all solves, and none is made.

## Consequence for the H2.5l passive telemetry

The half step fires at the **first** cycle detection and does not spend the
rescue budget, so on the committed captures the budget is never exhausted and
the post-budget regime does not arise at all. On the `after_rescue` capture,
`cycle_detect_after_budget_total` falls from 21 to 0 and
`post_budget_cycle_streak_max` from 21 to 0; across the runtime matrix
post-budget solves fall from 559 to 0.

The H2.5l-A and H2.5l-B counters remain wired, correct and asserted, but **no
committed capture exercises the post-budget branch any more**. Their fixtures
were retargeted to assert the new regime plus the invariants that survive
(`after_budget <= total`, `streak <= after_budget`, `accepts <= attempts`,
determinism) with the change recorded in the fixture text rather than silently
weakened.

**This is a recorded coverage gap, not a solved problem.** Closing it needs a
capture in which the half step declines. No such step exists in the current
corpus: attempts equal accepts in all four stages. Until one is found, the
post-budget branch is covered structurally and by invariant only.

## STOP gate

**Recommendation: GO for the analytic half step as implemented.**

Everything the design phase promised was met and measured: `iteration_cap` is
gone on every stage, no solve regressed, the LM rescue is intact and still
needed, the factor is analytic rather than fitted, OFF and legacy ON artifacts
are unchanged, and the result is deterministic across repetitions.

Three things are recorded rather than claimed away:

1. **post-budget coverage is now a gap** - no committed capture drives that
   branch, so it rests on structure and invariants;
2. **shared-root bit-identity is sampled, not exhaustive** - the runtime CSV
   sees a small fraction of solves; the population bound is the offline
   `1.857e-11 Pa`;
3. **the corpus is still two topologies** - the same limitation H2.5l-B
   recorded. 100% convergence on corridor and r0-window is not evidence about
   topologies neither exercises.

**H2 is not closed by this.** The corpus improved dramatically, but H2's
closure criteria are broader than the coupled solver's convergence rate, and
point 3 above is exactly the kind of evidence gap that should prevent an
automatic close. H3 remains blocked. No commit and no push were made.

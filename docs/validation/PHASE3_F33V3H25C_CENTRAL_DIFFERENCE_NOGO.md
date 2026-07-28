# Phase 3+ F3.3v3h2.5c central-difference Jacobian

Date: 2026-07-28

## Decision

F3.3v3h2.5c is **NO-GO**. The runtime patch was applied, measured on five real
scenario runs, and **fully reverted**. `Phase3CoupledPressureSolver.gd` is the
committed H2 primitive, unchanged.

What survives is test data: a second real failure capture, its deterministic
replay fixture, and this record.

## What was tried

H2.5b traced the captured `corridor_chain` `damping_exhausted` stall to the
Jacobian: a one-sided forward difference of `1e-3 Pa`, evaluated where the
residual's curvature scale is set by `dp_regularization_pa = 1e-2 Pa`, measures
a chord across the regularization threshold instead of a tangent. The Newton
direction it produced was 23% too long in its first component and was not a
descent direction for the max-norm at any damping.

The patch changed exactly one block - the difference was centred, at the same
step size, with no new constant, no mode flag and no change to the flux law:

```text
forward:  ( r(p + h) - r(p) ) / h
centred:  ( r(p + h) - r(p - h) ) / (2h)
```

## Measured result

Ten scenario runs before, ten after, all through
`scripts/run_scenario.py` -> `res://tools/run_scenario_headless.tscn`, all
reaching their full `duration_s`.

| stage | convergence before | convergence after |
|---|---:|---:|
| corridor 10 s | 66.67% | 63.33% |
| corridor 30 s | 82.83% | **87.53%** |
| corridor 60 s | 86.39% | **93.75%** |
| corridor 120 s | 81.33% | **85.01%** |
| **r0_window_360 120 s** | **86.33%** | **0.14%** |

| stage | `damping_exhausted` | `iteration_cap` |
|---|---:|---:|
| corridor 30 s | 16 -> 1 | 46 -> 44 |
| corridor 60 s | 52 -> 1 | 46 -> 44 |
| corridor 120 s | 52 -> 1 | 217 -> 215 |
| **r0_window_360 120 s** | 72 -> 0 | **125 -> 1439** |

The patch does what H2.5b predicted for `damping_exhausted` and destroys
`r0_window_360`. Cost on that scenario: `91.0 s -> 152.9 s` (1.68x).

Isolation and mechanics were correct throughout: OFF runs byte-identical
before and after on all five pairs (SHA-256), zero counterflow violations,
`max_normalized_residual = 0.0` on converged steps, all five Godot fixtures
PASS, and a mutation control confirmed the structural tests caught a regression
to the one-sided quotient. The patch failed on numerics, not on wiring.

## Why it failed

A step was captured from `r0_window_360` under the patched solver and replayed
offline. The obvious hypothesis - that the centred Jacobian was wrong - is
false. At that state the centred difference is **more** accurate than the
forward one (0.01% versus 0.34% against the true derivative), and the two
first-iteration Newton steps agree to four figures.

The divergence appears later:

```text
FORWARD   it2 norm=1.3012e-03  damping=1.0
          it3 norm=1.2990e-03  damping=0.5   <- breaks the symmetry
          it4 norm=9.7019e-06                <- converges
CENTRAL   it2 norm=1.2995e-03  damping=1.0
          it3 norm=1.2986e-03  damping=1.0
          it4 norm=1.2982e-03  damping=1.0
          ... 24 iterations, norm=1.2837e-03
```

The steps alternate sign: `-2.006e-2, +1.962e-2, -1.961e-2, +1.959e-2`. It is a
**period-2 limit cycle**. The merit drops about 0.03% per turn, and the
acceptance test - a bare `< norm`, with no sufficient-decrease condition -
accepts it at full damping forever. The forward quotient falls into the same
cycle but its accidental bias forced a `0.5` damping at iteration 3, which
knocked it out.

**The centred difference fixes nothing. It removes the asymmetry that happened
to break the cycle.**

That reframes the H2 failure taxonomy. `damping_exhausted` and `iteration_cap`
are not two separate problems: they are the same missing globalization seen at
two extremes - either no decrease is available at all, or decrease is available
but vanishingly small.

## What the synthetic family missed

H2.5b built a 204-case family by perturbing the single H2.5a capture, required
the baseline to fail 48.5% of it so it could not be vacuous, and scored the
candidate at 95.6%. That family was still insufficient, and for a reason it
could not have detected from the inside: **every case in it perturbed one
topology**. `corridor_chain` is a chain. `r0_window_360` is a star - five rooms,
four openings, all meeting at room 1. Perturbing one capture explores states,
not topologies.

## Retained artifacts

| File | Purpose |
|---|---|
| `tests/fixtures/data/coupled_solver_failure_r0_window_360.json` | second real capture, star topology, IEEE754-exact |
| `tests/fixtures/phase3_f33v3h25c_r0_window_solver_failure.gd` | deterministic replay, asserts the failure still reproduces |
| `tests/test_phase3_f33v3h25c_r0_window_capture.py` | 12 contracts, including that the solver was not modified |
| `docs/validation/PHASE3_F33V3H25C_CENTRAL_DIFFERENCE_NOGO.md` | this record |

### What the second capture is, and is not

It is **not** the period-2 cycle. That cycle belongs to the reverted candidate,
so nothing in the repository can reproduce it, and the fixture says so
explicitly rather than implying otherwise.

It is a **third failure mode**, found in shipped code, and arguably the more
useful find:

```text
it1  1.835e-03   accepted at damping 0.5
it2  1.790e-04   accepted
it3  7.741e-12   accepted
it4  1.147e-12   13 dampings, all rejected -> damping_exhausted
```

The solve reaches `1.147e-12` against a `1.0e-12` tolerance - 15% short. The
correction that would close it is about `5.5e-12 Pa`, while one ulp of the
absolute-pressure iterate near `101325 Pa` is `1.455e-11 Pa`. The step is
**0.38 ulp**, so `p + damping * step` is not a different double: every damped
trial evaluates the same state, none improves strictly, and the line search
exhausts. The tolerance is reachable in principle - jittering the solution by
one ulp per room finds `3.24e-13` - but not by any step this iterate can
express.

The solver iterates on **absolute** pressure, spending seven decimal digits
representing `101325 Pa` before the first digit that matters. A gauge-pressure
unknown would not have this floor. That is a hypothesis for H2.5d, not a change
made here.

## Binding constraints for H2.5d

1. **Both real captures are a mandatory gate, before any scenario run.** They
   record `damping_exhausted` at opposite ends of the residual scale -
   `2.2e-4` far from the answer, `1.1e-12` at the numerical floor. A change that
   only addresses one of them is not a fix.
2. **Do not tune the Jacobian step or centre the difference.** Measured, twice.
3. The named candidate is an Armijo / sufficient-decrease condition, plus cycle
   detection. The bare `< norm` test is what let the limit cycle survive.
4. `iteration_cap` remains **uncaptured**. The capture instrumentation records
   only the first failure, and on both scenarios that is `damping_exhausted`.
   Capturing an `iteration_cap` step needs an instrumentation change, which is
   itself a separate, motor-touching decision.

## Unchanged

No legacy physics, FED, HVAC, visual, official case, report, baseline, expected
value, tolerance, CTRL envelope or VALID_GAP classification changed. The solver
and the engine are untouched. H3 remains blocked.

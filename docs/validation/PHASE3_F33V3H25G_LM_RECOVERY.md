# Phase 3+ F3.3v3h2.5f/g bounded Levenberg-Marquardt recovery

Date: 2026-07-28

## Decision

**GO** - for the canonical `damping_exhausted` mode, and only that.

Both real captures now converge, and `damping_exhausted` drops sharply on every
corridor stage. That is the whole of the claim. `corridor_chain` itself is NOT
closed: at 120 s it still sits at **84.18%**, with **217 `iteration_cap`** and
**11 `damping_exhausted`** that reached a second dead end after the one-step LM
budget was spent.

**H2 remains blocked**, now principally on `iteration_cap`.

## H2.5f - the design, measured before it was written

The previous attempt at this failure (H2.5d) rejected a global L2 acceptance
merit because it closed `corridor_chain` and wrecked `r0_window_360`. The
lesson taken was that the merit change must be **fail-only**: reachable from
exactly the dead end where the solver returns `damping_exhausted`, and nowhere
else. On every other path the code is the baseline, so a successful solve is
bit-identical by construction.

Two recoveries were compared offline on both captures and their neighbourhoods.

| | corridor capture | r0 capture | 450-case sweep | 240-case damping-dense |
|---|---|---|---:|---|
| baseline | FAIL | PASS | 432 ok | 201/240, 39 `damping_exhausted` |
| L2 rescue | PASS (1 step) | PASS, 0 rescues | 0 regressions | 216/240, **20/39** invocations found a step |
| **LM rescue** | **PASS (1 step)** | **PASS, 0 rescues** | **0 regressions** | **230/240, 39/39** invocations found a step |

LM was chosen on that last column: given the same dead ends it finds an
acceptable step every time, L2 roughly half the time. Both are free of
regressions.

## What it does

The `corridor_chain` stall is the L-infinity acceptance test refusing a Newton
direction that fixes two rooms out of three, because the third - the one
currently holding the maximum - gets 2.4% worse. No damping helps, so the solve
dies with the answer still reachable.

The recovery damps the **same** Jacobian the Newton step came from - no new
differencing, no new step size - toward steepest descent on

```text
phi = 0.5 * sum over rooms of (normalized residual)^2
```

and requires a **sufficient** decrease of it, `phi_new <= (1 - c t) phi_old`
with `c = 1e-4`, not merely a strict one. The telling detail is that the
accepted step **raises** L-infinity, `2.169e-04 -> 2.348e-04`, while lowering
phi. That is precisely the trade the ordinary test was refusing, and one such
step unblocks a solve that then converges to `6.5e-17`.

### Bounds

- one accepted recovery step per solve (`LM_RESCUE_MAX_ACCEPTED_STEPS = 1`);
- at most five regularization strengths (`LM_RESCUE_LAMBDA_LADDER`);
- control returns to the ordinary Newton/L-infinity loop immediately;
- a second dead end fails as `damping_exhausted`, exactly as before;
- a recovery is **never** convergence by itself - the final criterion is still
  L-infinity against the unchanged `1e-12` tolerance.

All three are global constants, never read from `options`, never per case.

## Runtime gate

| stage | convergence | `damping_exhausted` | `iteration_cap` | attempts/accepted | trials |
|---|---:|---:|---:|---:|---:|
| corridor 10 s | 67.50% -> **67.50%** | 0 -> 0 | 39 -> 39 | 0 / 0 | 0 |
| corridor 30 s | 83.10% -> **87.26%** | 15 -> **0** | 46 -> 46 | 15 / 15 | 22 |
| corridor 60 s | 86.53% -> **92.08%** | 51 -> **11** | 46 -> 46 | 51 / 51 | 90 |
| corridor 120 s | 81.40% -> **84.18%** | 51 -> **11** | 217 -> 217 | 51 / 51 | 90 |
| r0_window 120 s | 91.33% -> **91.33%** | 0 -> 0 | 125 -> 125 | **0 / 0** | 0 |

- **No stage regressed.**
- **`iteration_cap` is identical in every stage**, so there is no
  damping-to-iteration shift to account for. The recovery converts dead ends
  into convergence, not into a different failure.
- The residual `damping_exhausted` at 60 s and 120 s is the budget working as
  designed: 51 steps hit the dead end, all 51 were rescued, 40 then converged
  and 11 hit a **second** dead end and failed - which is what one accepted step
  per solve means.
- Lambda was always the first rung, `1e-3`; trials averaged 1.47 and 1.76 per
  rescue, so the backtracking inside the recovery is used but shallow.
- 10 s is unchanged because it has no `damping_exhausted` to recover.

### Isolation and invariants

- OFF byte-identical on all five pairs (SHA-256);
- the isolation analyzer exits 0 on all five, so no shared live column moved;
- zero counterflow violations; `max_normalized_residual = 0.0` on converged
  steps;
- the coupled-vs-legacy net-mass divergence is **bit-identical** before and
  after - the recovery changes how often the solve finishes, not what the
  preview measures;
- runtime cost flat (`corridor_120_on` 108.6 s vs 108.6 s; `r0w360_120_on`
  81.5 s vs 85.6 s).

Physics 9 PASS / 15 CTRL / 5 WARN / 0 FAIL; ILV 15 PASS / 14 CTRL / 0 FAIL; gap
inventory unchanged at 6 VALID_GAP + 71; guardrails 9/10 with only the expected
dirty-motor R2-1.

### Non-interference, measured

Over **432** baseline-successful solves across both topologies, the residual
history, the iterate and the final result are **bit-identical** with the
recovery compiled in, and the recovery fired **zero** times. That is the whole
safety argument, and it is measured rather than asserted.

## Two gaps, recorded rather than papered over

**No physical case exists where the recovery declines.** Across roughly 2500
offline solves on both topologies and seven regularization widths, it found a
sufficient-decrease step on every single invocation. That is what a lambda
ladder reaching steepest descent on a smooth merit should do, so the mandated
"LM finds no improvement" fixture could not be built from real physics. The
branch is covered structurally - the decline path still sets
`damping_exhausted` and returns - plus a mutation control, plus the real
budget-exhausted case, which does end in `damping_exhausted`.

**The per-step telemetry is nearly unobservable.** `rescue_lambda`,
`rescue_trials` and the rest are written per step, but the CSV samples at the
10 s log cadence and recoveries land on arbitrary steps, so a logged row almost
never coincides with one. The three `_total` counters are the usable signal;
the per-step columns are effectively diagnostic-only. Lambda and trial figures
in this record come from the offline replay, which is validated bit-exact
against the runtime on both captures.

## What is still open

`corridor_chain` is not solved. At 120 s it is 84.18%, and what remains is
**217 `iteration_cap`** plus **11 `damping_exhausted`** that hit a second dead
end after the one-step budget - so the budget is itself a live constraint, not
just a safety bound.

`iteration_cap` is the dominant remaining mode, and it is still
**uncaptured**: the capture instrumentation records only the first failure per
run, and on both scenarios that is `damping_exhausted`. Capturing an
`iteration_cap` step needs an instrumentation change, which is a separate,
motor-touching decision.

## Unchanged

Jacobian (one-sided forward at `1e-3 Pa`), tolerance, main L-infinity merit,
ordinary damping schedule, the H2.5e gauge formulation, EOS, openings and flux
law. No legacy physics, FED, HVAC, visual, official case, report, baseline,
expected value, CTRL envelope or VALID_GAP classification changed.

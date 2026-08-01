# Phase 3+ F3.3v3h2.7 Iteration Budget Diagnosis and Design

Date: 2026-08-01.

Diagnosis and design only. `sim/core` was read, never modified.
`DEFAULT_MAX_ITERATIONS` is untouched. No runtime patch was applied.

## Headline

**The iteration cap is not the defect, and no budget policy is recommended.**

H2.6 handed this phase a blocker phrased as a budget problem: `two_storey_smoke`
keeps 20 `iteration_cap` and its capture converges at 39 iterations when the
budget is raised. Replaying five captures across eight budgets shows the real
cause: every large-network `iteration_cap` is the **same period-2 square-root
orbit H2.5m already solved**, running undetected for 17 to 34 iterations
because the H2.5j detector cannot fire on it.

The detector requires two consecutive model gain ratios to be below `0.05`.
In a period-2 orbit the gain ratio **also has period two** - one phase near
`0.08`, the other near `-0.01` - so the conjunction is never satisfied even
though the step cosine sits at `-0.9999` throughout. The orbit ends only when
the ordinary line search happens to damp and break it by accident.

Fixing the detector converges every affected capture in 10 to 14 iterations
**inside the unchanged cap of 24**, using 41% fewer residual evaluations than
the baseline and 51% fewer than raising the cap to 48.

## Baseline correction

`C:\Users\dangp\h26_base` sat at `4ec0f09a`, which predates H2.5m, and was
therefore unusable as an H2.7 baseline. It was verified clean and removed.
The H2.7 baseline is `C:\Users\dangp\h27_base` at

```text
5e535722327082a07057e45636bfee3c3db1be91
```

which includes H2.5m and H2.6. `Phase3CoupledPressureSolver.gd` there hashes
`fdcb1d4645703eb82aad562b002d41d6...`.

## Captures

Bit-exact, taken with the committed selector through `scripts/run_scenario.py`,
Godot 4.7.1, sequential, outside the sandbox, editor closed. Stored under
`runs/h27/captures/`.

| capture | rooms | openings | reason | residual at cap |
|---|---:|---:|---|---|
| `cfast_two_floor_stairwell` | 11 | 9 | `iteration_cap` | 1.666e-02 -> 2.524e-11 |
| `two_storey_smoke` | 11 | 9 | `iteration_cap` | 8.272e-02 -> 4.640e-02 |
| `three_bed_apartment_smoke` | 7 | 6 | `iteration_cap` | 1.132e-01 -> 1.503e-12 |
| `flashover_simple_house` | 6 | 5 | `iteration_cap` | 4.984e-02 -> 6.879e-04 |
| `uk_bungalow_smoke` | 5 | 5 | `damping_exhausted` | 2.114e-01 -> 6.440e-06 |

Two of them - stairwell at `2.5e-11` and three_bed at `1.5e-12` - are cut off
within one or two iterations of the `1e-12` tolerance.

## Anatomy

`tools/diagnostics/phase3_h27_budget_anatomy.gd`, budgets 24/32/40/48/64/96/128/256.

| capture | rooms | openings | diameter | cycles | kappa_inf(J) | iterations needed | cycles detected | half steps | LM | final residual |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|
| `cfast_two_floor_stairwell` | 11 | 9 | 2 | 0 | 19291 | **25** | 0 | 0 | 0 | 1.44e-13 |
| `flashover_simple_house` | 6 | 5 | 2 | 0 | 474 | **28** | 0 | 0 | 0 | 9.93e-15 |
| `three_bed_apartment_smoke` | 7 | 6 | 4 | 0 | 27119 | **25** | 0 | 0 | 0 | 1.01e-14 |
| `two_storey_smoke` | 11 | 9 | 2 | 0 | 16428 | **39** | 1 | 1 | 0 | 6.64e-14 |
| `uk_bungalow_smoke` | 5 | 5 | 2 | 1 | 317 | **never <= 256** | 0 | 0 | 1 | 6.44e-06 |

Every budget that converges lands on a **bit-identical root**
(`max_abs_delta_pa = 0.000e+00` within the sweep). A larger budget changes
whether the answer is reached, never what it is.

### The requirement does not scale with anything structural

- **rooms**: 6 needs 28, 7 needs 25, 11 needs 25, 11 needs 39. A six-room star
  needs *more* than an eleven-room tree.
- **openings**: same ordering, same contradiction.
- **diameter**: 2, 2, 4, 2 - uncorrelated.
- **cycles**: 0 for all four failures; the only case with a cycle in the graph
  is the one no budget fixes.
- **conditioning**: 474 needs 28, 27119 needs 25, 16428 needs 39. Not monotone.

**Hypotheses A, B, C and D are refuted.** Any formula in rooms, openings,
diameter or condition would be fitted to noise.

### What the iterations are actually spent on

Every failure has the identical two-phase shape: a long stall at a residual
ratio near one, then a sudden break into quadratic convergence.

| capture | stall | breaks at | iterations after the break | total |
|---|---|---:|---:|---:|
| `cfast_two_floor_stairwell` | 0-16 | 17 | 8 | 25 |
| `flashover_simple_house` | 0-20 | 21 | 7 | 28 |
| `three_bed_apartment_smoke` | 2-18 | 19 | 6 | 25 |
| `two_storey_smoke` | 0-33 | **34** | 5 | 39 |

The terminal phase is always 5 to 8 iterations. **The whole variance is the
stall length.** And during the stall the reduction ratio alternates -
`0.976, 0.996, 0.976, 0.997` on stairwell, `0.979, 0.99x` on two_storey - which
is the signature of a period-2 orbit.

## Root cause

`tools/diagnostics/phase3_h27_stall_anatomy.gd` records, per iteration, the
three quantities the H2.5j detector tests.

The cosine is **-0.9999 or -1.0000 through the entire stall** on all four
captures. The orbit is unambiguous. What blocks detection is the gain ratio,
which alternates in step with the orbit:

| capture | gain on phase A | gain on phase B | blocked because |
|---|---|---|---|
| `cfast_two_floor_stairwell` | 0.082 | -0.012 | 13 iterations by `gain >= 0.05`, 13 by `previous_gain >= 0.05` |
| `flashover_simple_house` | 0.06-0.09 | 0.004-0.05 | 16 and 16 |
| `two_storey_smoke` | 0.08-0.27 | -0.01 to -0.14 | 19 and 20 |

The predicate is

```gdscript
previous_full_step_gain_ratio < 0.05 and model_gain_ratio < 0.05
```

On an alternating sequence whose high phase exceeds `0.05`, **that conjunction
can never hold**. H2.5j chose it on the corridor capture, where both phases
happened to be tiny (`0.00090` and `0.0084`). It does not generalise.

The stall ends only when the ordinary line search damps for unrelated reasons -
`damped_step` appears exactly at the break iteration on stairwell (17),
flashover (21) and three_bed (19). That is an accidental escape, not a
mechanism.

`uk_bungalow_smoke` is different and must not be conflated: `damping != 1.0` on
every iteration, so `previous_full_step` is cleared each time and the detector
is structurally unreachable. It exhausts its single LM rescue and dies. **No
budget fixes it** - it fails identically at 256.

So of the listed hypotheses, the answer is **H, and only H**: a cycle that the
detector cannot see. Not A, B, C, D. Not E - the seed residual is unremarkable.
Not G - the tail is not genuine linear convergence, it is an orbit.

## Policy comparison

`tools/diagnostics/phase3_h27_policy_probe.gd`, at the shipped cap unless the
policy raises it. P2 replaces the conjunction with a disjunction over the same
pair - `minf(previous_gain, gain) < 0.05`, which is exactly
`previous_gain < 0.05 or gain < 0.05`. **It introduces no new constant.**
P3 drops the gain test entirely.

| capture | P0 baseline | P1 cap=48 (control) | **P2 min-gain** | P3 cosine-only |
|---|---|---|---|---|
| `cfast_two_floor_stairwell` | fail, 293 evals | 25 it, 305 | **11 it, 137** | 9 it, 112 |
| `flashover_simple_house` | fail, 172 | 28 it, 200 | **12 it, 88** | 10 it, 75 |
| `three_bed_apartment_smoke` | fail, 195 | 25 it, 203 | **14 it, 115** | 12 it, 101 |
| `two_storey_smoke` | fail, 289 | 39 it, 471 | **10 it, 123** | 8 it, 100 |
| `uk_bungalow_smoke` | fail, 121 | fail, 121 | fail, 121 | fail, 121 |
| `failure_corridor_chain` | 6 it, 40 | 6 it, 40 | **6 it, 40** | 7 it, 45 |
| `failure_r0_window_360` | 3 it, 20 | 3 it, 20 | **3 it, 20** | 3 it, 20 |
| `iteration_cap_after_rescue_corridor` | 4 it, 18 | 4 it, 18 | **4 it, 18** | 4 it, 18 |
| `iteration_cap_corridor_chain` | 7 it, 31 | 7 it, 31 | **7 it, 31** | 9 it, 41 |
| **total** | **4/9, 1179 evals** | 8/9, 1409 | **8/9, 693** | 8/9, 633 |

P2 reaches the same convergence as raising the cap while spending **41% fewer
evaluations than the baseline** and **51% fewer than P1**, because it removes
the orbit instead of tolerating it. Cross-policy root agreement stays between
`0.000e+00` and `3.9e-11 Pa`.

P3 converges marginally faster but **perturbs solves that were already
healthy**: `failure_corridor_chain` 6 -> 7 and `iteration_cap_corridor_chain`
7 -> 9. P2 leaves all four committed captures bit-identical to baseline.

## Leave-one-topology-out

P2 was motivated **only** by the four large-network captures - two-storey
branched trees, a seven-room branched tree and a six-room star. Held out
entirely from its design:

| held out | topology | P0 | P2 | verdict |
|---|---|---|---|---|
| `iteration_cap_corridor_chain` | 3-room chain | 7 it | 7 it | unchanged |
| `iteration_cap_after_rescue_corridor` | 3-room chain | 4 it | 4 it | unchanged |
| `failure_corridor_chain` | 3-room chain | 6 it | 6 it | unchanged |
| `failure_r0_window_360` | 5-room star | 3 it | 3 it | unchanged |
| `uk_bungalow_smoke` | 5-room loop | fail | fail | unchanged, different mode |

Every held-out capture is **identical** under P2. The change is structural, not
fitted: it introduces no constant, and the two thresholds it reuses (`0.05` and
`-0.99`) are the ones H2.5j already ships.

## Iteration distribution

From the H2.6 candidate runs, 5016 logged solves. Censored at the cap.

| case | n | P50 | P90 | P99 | max | at cap |
|---|---:|---:|---:|---:|---:|---:|
| `cfast_two_floor_stairwell` | 132 | 12 | 14 | 14 | 14 | 0 |
| `compact_apartment_smoke` | 480 | 8 | 9 | 12 | 13 | 0 |
| `flashover_simple_house` | 720 | 9 | 18 | 21 | 21 | 0 |
| `ghanekar_bedroom_hallway` | 84 | 6 | 8 | 9 | 9 | 0 |
| `piso_mediterraneo_smoke` | 840 | 9 | 10 | 14 | 17 | 0 |
| `three_bed_apartment_smoke` | 840 | 8 | 12 | 14 | 14 | 0 |
| `two_storey_smoke` | 1320 | 10 | 14 | 24 | 24 | 22 |
| `uk_bungalow_smoke` | 600 | 8 | 10 | 12 | 13 | 0 |
| **all** | **5016** | **9** | **13** | **20** | **24** | **22** |

The cap of 24 already sits **above the P99 of 20**. A typical solve needs 9
iterations. The failures are a thin tail of 22 samples in 5016, and that tail
is the undetected orbit. A budget policy would be sizing for a tail that a
detector fix deletes.

## The ten questions

1. **Is 24 the defect?** No. It sits above P99 and it is cutting off an orbit
   that should never have run that long.
2. **Why does an eleven-room network need 39?** It does not, structurally. It
   spends 34 iterations in an undetected period-2 orbit and 5 converging.
3. **Does the need correlate with N, E, diameter, condition or state?** No.
   All four are refuted above; a six-room star needs more than an eleven-room
   tree.
4. **P50/P90/P99/max?** 9 / 13 / 20 / 24 (censored), over 5016 solves.
5. **Does a topology policy generalise?** There is nothing to generalise: the
   requirement is not a function of topology.
6. **Does a progress-based extension separate slow convergence from a stall?**
   Not usefully here - the orbit *is* making progress, about 2% per iteration,
   so a progress test would keep extending it. That is an argument against
   adaptive budgets for this failure, not for them.
7. **Can a better seed keep cap=24?** Not investigated, and it should not be:
   P2 keeps cap=24 with no seed change and no new constant, which is a smaller
   and more provable intervention.
8. **Reasonable maximum cost?** P2 *reduces* cost. Baseline 1179 evaluations
   over the corpus, P2 693.
9. **What if a solve still fails at the ceiling?** It must fail explicitly, as
   it does today: `iteration_cap` with the residual reported and no state
   written. `uk_bungalow_smoke` shows this path is still needed - P2 does not
   rescue it and must not pretend to.
10. **Which policy is easiest to demonstrate?** P2, decisively. It adds no
    constant, changes one boolean operator, is derived from the measured
    period-2 structure of the gain ratio, and leaves every held-out capture
    bit-identical.

## Recommendation

**NO-GO for any iteration-budget policy**, static or adaptive. The premise that
large networks need a larger budget is not supported: the requirement does not
scale with size, and the cap already exceeds P99.

**GO to design a detector correction (P2) as its own phase, H2.8.** It is a
`sim/core` change and therefore out of scope here; it needs its own STOP gate,
its own full runtime matrix against the committed cases, and its own
non-interference evidence.

Recorded as unresolved: `uk_bungalow_smoke`'s `damping_exhausted` is a distinct
mode that neither budget nor detector addresses. It is bounded by the H2.5g
one-accept LM budget and would need its own analysis.

## Implementation plan for H2.8, file by file, NOT applied

1. `sim/core/Phase3CoupledPressureSolver.gd` - replace the conjunction in the
   cycle predicate with a disjunction over the same pair, and document why the
   gain ratio alternates. No new constant, no change to `0.05`, `-0.99`, the
   cap, the tolerance, the Jacobian, the gauge, the half step or the LM budget.
2. `tests/fixtures/data/` - commit the four H2.7 captures so the large-network
   orbits become permanent regression artifacts.
3. `tests/fixtures/phase3_f33v3h28_*.gd` - a new fixture asserting each
   captured orbit converges inside the unchanged cap of 24, and that
   `uk_bungalow_smoke` still fails as `damping_exhausted`.
4. `tests/test_phase3_f33v3h25j_cycle_guard.py` - update the structural
   assertion on the predicate; keep the mutation control.
5. `tests/fixtures/phase3_f33v3h25h_iteration_cap.gd` and
   `phase3_f33v3h25m_analytic_half_step.gd` - **expected to need no change**;
   P2 leaves those captures at 7 and 4 iterations exactly as today. Verify
   rather than assume.
6. Full runtime matrix over the H2.6 corpus plus corridor and r0-window,
   baseline `5e535722`, reporting OFF identity, legacy ON invariance, root
   divergence, determinism and cost.
7. Documentation and the H2.5j record, which must be corrected the way H2.5m's
   "one accept per solve" was: the measurement stands, the generalisation does
   not.

## STOP gate

Diagnosis complete. **No solver change was made and none is authorised by this
document.** H2 remains open; its blocker is now correctly identified as the
cycle detector rather than the iteration budget. H3 remains blocked.

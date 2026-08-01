# Phase 3+ F3.3v3h2.8 Alternating-Gain Cycle Detector

Date: 2026-08-01.

Baseline `5e535722` (worktree `C:\Users\dangp\h27_base`), candidate the working
tree on `34f58e59`. The solver blob is identical across `f073c3a3`,
`5e535722` and `34f58e59`, so the H2.5m and H2.6 runtime artifacts are valid
baselines; three freshly-run baselines reproduced them **byte for byte**.

## The change

One predicate. H2.5j asked for both consecutive model gain ratios to be poor:

```gdscript
previous_full_step_gain_ratio < CYCLE_GUARD_MIN_MODEL_GAIN_RATIO
and model_gain_ratio < CYCLE_GUARD_MIN_MODEL_GAIN_RATIO
and step_cosine < CYCLE_GUARD_MAX_STEP_COSINE
```

H2.7 measured four large-network captures and found the gain ratio of a
period-2 orbit **also has period two** - about `0.08` on one phase and `-0.01`
on the other - while the step cosine sits at `-0.9999` throughout. The
conjunction therefore could never hold, the orbit ran for 17 to 34 iterations,
and the solve died at the cap. H2.8 takes the minimum instead:

```gdscript
cycle_min_gain_ratio = minf(previous_full_step_gain_ratio, model_gain_ratio)
cycle_detected = (
    cycle_min_gain_ratio < CYCLE_GUARD_MIN_MODEL_GAIN_RATIO
    and step_cosine < CYCLE_GUARD_MAX_STEP_COSINE
)
```

It asks the question the sequence can answer: does **either** phase of the
orbit show the linear model is not being delivered? The threshold is the same
`0.05`, the cosine test is unchanged, and so is every geometric precondition -
two accepted full steps and a previous step to compare against. **No new
constant enters the predicate**, which a structural test enforces.

Nothing else moved: `DEFAULT_MAX_ITERATIONS = 24`, the tolerance, the half-step
factor `0.5` and its strict-descent rule, the LM rescue and its one-accept
budget, the Jacobian, the gauge, the regularization, the flux law, the EOS and
the counterflow contract are all untouched.

### Telemetry

Two passive counters split the detected population so the regimes stay legible:
`cycle_detect_both_phases_low_total` (the original H2.5j shape) and
`cycle_detect_alternating_gain_total` (what H2.8 added). Neither is read back
into any decision. The OFF schema is unchanged.

## Captures

At the shipped cap of 24, against the committed captures:

| capture | rooms | before | after | regime |
|---|---:|---|---|---|
| `cfast_two_floor_stairwell` | 11 | `iteration_cap`, 24 | **converged, 11** | alternating |
| `two_storey_smoke` | 11 | `iteration_cap`, 24 | **converged, 10** | alternating |
| `three_bed_apartment` | 7 | `iteration_cap`, 24 | **converged, 14** | alternating |
| `flashover_simple_house` | 6 | `iteration_cap`, 24 | **converged, 12** | alternating |
| `uk_bungalow` | 5 | `damping_exhausted`, 12 | `damping_exhausted`, 12 | none detected |
| `iteration_cap_corridor_chain` | 3 | converged, 7 | converged, 7 | both-low |
| `iteration_cap_after_rescue_corridor` | 3 | converged, 4 | converged, 4 | both-low |
| `failure_corridor_chain` | 3 | converged, 6 | converged, 6 | none detected |
| `failure_r0_window_360` | 5 | converged, 3 | converged, 3 | none detected |

The iteration counts match H2.7's offline P2 prediction exactly (11, 10, 14,
12). The four orbits close through the **new** branch and spend no LM budget;
the two corridor captures close through the **original** branch at unchanged
iteration counts, which is what taking a minimum of a pair that was already
both-low must do.

`uk_bungalow` is not reclassified. It damps on every iteration, so
`previous_full_step` is cleared each time and the detector - widened or not -
is structurally unreachable.

## Runtime matrix

Ten committed cases, 120 s, Godot 4.7.1, sequential, outside the sandbox,
editor closed, via `scripts/run_scenario.py`.

| case | convergence b/a | itcap b/a | damping b/a | half att/acc | max acc/solve | alt-gain | both-low | counterflow |
|---|---|---:|---:|---|---:|---:|---:|---:|
| `cfast_corridor_chain` | 100.00% -> 100.00% | 0 -> 0 | 0 -> 0 | 724 / 724 | 2 | 1 | 723 | 0 |
| `cfast_r0_window_360` | 100.00% -> 100.00% | 0 -> 0 | 0 -> 0 | 430 / 430 | 1 | 343 | 87 | 0 |
| `cfast_two_floor_stairwell` | 99.93% -> **100.00%** | **1 -> 0** | 0 -> 0 | 834 / 834 | 2 | 717 | 117 | 0 |
| `two_storey_smoke` | 98.61% -> **100.00%** | **20 -> 0** | 0 -> 0 | 754 / 754 | 2 | 640 | 114 | 0 |
| `ghanekar_bedroom_hallway` | 99.93% -> 99.93% | 0 -> 0 | 1 -> 1 | 470 / 470 | 2 | 63 | 407 | 0 |
| `piso_mediterraneo_smoke` | 100.00% -> 100.00% | 0 -> 0 | 0 -> 0 | 310 / 310 | 2 | 10 | 300 | 0 |
| `uk_bungalow_smoke` | 99.93% -> 99.93% | 0 -> 0 | **1 -> 1** | 804 / 804 | 2 | 62 | 742 | 0 |
| `compact_apartment_smoke` | 99.31% -> 99.31% | 0 -> 0 | 10 -> 10 | 467 / 467 | 1 | 119 | 348 | 0 |
| `three_bed_apartment_smoke` | 99.93% -> **100.00%** | **1 -> 0** | 0 -> 0 | 298 / 298 | 2 | 32 | 266 | 0 |
| `flashover_simple_house` | 98.89% -> **98.96%** | **1 -> 0** | 15 -> 15 | 481 / 481 | 2 | 416 | 65 | 0 |

**Every `iteration_cap` in the corpus is gone - 22 to 0.** `two_storey_smoke`,
the H2.6 blocker, goes from 98.61% to 100.00%. No case regressed, and
`damping_exhausted` is unchanged everywhere, so nothing was displaced from one
failure mode into another.

The regime split confirms the diagnosis rather than merely restating it. On the
three-room corridor the original both-low shape dominates (723 against 1); on
the eleven-room networks the alternating shape does (717 and 640). The detector
H2.5j wrote was correct for the topology it was written from.

## Gates

| # | gate | result |
|---|---|---|
| 1 | the four orbits converge inside 24 | **PASS** - 11, 10, 14, 12 |
| 2 | zero baseline-converged solves now fail | **PASS** |
| 3 | uk_bungalow keeps its separate mode | **PASS** - unchanged at 1 |
| 4 | zero converged residuals above tolerance | **PASS** |
| 5 | OFF SHA-256 identical | **PASS** - 10/10 |
| 6 | legacy ON columns invariant | **PASS** - 0 differences |
| 7 | counterflow violations | **PASS** - 0 |
| 8 | mass and energy conservation | **PASS** - physics 0 FAIL |
| 9 | no displacement to another limiting_reason | **PASS** |
| 10 | shared-root divergence measured | **PASS** - `0.000000e+00 Pa` over **5078 rows** |
| 11 | determinism on corridor, r0-window, multi-floor, loop | **PASS** - 3/3 each |
| 12 | cost reported | see below |
| 13 | no knobs, no topology dependence | **PASS** |
| 14 | zero residual Godot processes | **PASS** |

### Activation on already-healthy solves, reported as asked

P2 fires far more often than H2.5j did - `cfast_r0_window_360` goes from 204
detections to 430, and it was already converging 100% of the time. Every one of
those solves still lands on the **bit-identical** root: the worst shared-root
divergence across all ten cases and 5078 logged rows is `0.000000e+00 Pa`. The
wider detector reaches the same answers sooner, it does not reach different
ones.

### Cost

Offline, over the nine captures, H2.7 measured 1179 residual evaluations for
the baseline against 693 for P2 - 41% fewer, because the orbit is removed
rather than tolerated. At runtime the ON-mode wall clock is within noise of the
baseline (for example `two_storey_smoke` 220 s against 190 s, `uk_bungalow`
102 s against 98 s); the shadow preview cost is dominated by the number of
solves, not by this predicate.

### More than one accept per solve

Eight of the ten cases reach a per-solve maximum of 2, as H2.6 first recorded.
Each accept independently requires a detected orbit and a strictly decreasing
L-infinity residual, and there is no artificial budget, so a second distinct
orbit in the same solve is handled like the first. No budget was reintroduced.

## What this does not close

**`uk_bungalow_smoke` remains open and separate.** It damps on every iteration,
so the cycle detector cannot see it by construction; it exhausts the single LM
rescue and fails at `damping_exhausted`, identically at 24, 64 and 256
iterations. H2.8 neither fixes it nor pretends to. Nine of ten cases retain
some `damping_exhausted` or none, unchanged from baseline: `flashover` 15,
`compact_apartment` 10, `ghanekar` 1, `uk_bungalow` 1.

**H2.6's C8 gap stands**: no template defines two openings between the same room
pair, so parallel openings remain unexercised.

**The half step's rejection branch is still untaken.** Attempts equal accepts in
all ten cases here, as in H2.6 and H2.5m. Across twenty-two topology runs no
real solve has ever declined a half step.

## Two methodological notes, binding on later phases

### Filesystem SHA-256 is not a cross-worktree identity

Comparing the ten case files between `HEAD` and the `h27_base` worktree showed
eight of ten "differing". They are not different. The main tree stores them with
CRLF and a fresh worktree checkout normalises to LF, so the files differ by
exactly one byte per line - 50 bytes on `two_storey_smoke.json` - while the
parsed JSON is identical and `git diff` between the two commits is empty.

The case hashes recorded in the H2.6 and H2.7 documents are therefore
**tree-local**, reproducible only under the same line-ending configuration.

**For any cross-worktree or cross-machine provenance check, use the Git blob
hash (`git rev-parse <commit>:<path>`) or a canonical JSON serialisation. Do not
use filesystem SHA-256.** All ten blob hashes matched, which is what made
`h27_base` usable as a baseline. Filesystem SHA-256 remains the right tool for
comparing run artifacts produced within one tree, which is how it is used for
the OFF-identity gate.

### One truncated run was excluded from the determinism check

The first determinism attempt on `two_storey_smoke` reported two distinct
hashes across three runs. That was not nondeterminism. The third artifact had
**1183 rows instead of 1573** and **zero differing cells** over the rows it did
contain: the run was killed part-way through by an external ten-minute command
timeout while still writing.

An incomplete run is invalid evidence in either direction, so it was discarded
and re-run. Three complete runs are byte-identical, and the same holds for
`cfast_corridor_chain`, `cfast_r0_window_360` and `ghanekar_bedroom_hallway`.
Row count is checked alongside the hash so a truncated artifact cannot be
mistaken for a numerical difference again.

## Corrections to earlier records

- **H2.6** framed the blocker as iteration-cap sizing. H2.7 refuted that and
  H2.8 confirms it: the cap was never changed and every `iteration_cap`
  disappeared. That correction is recorded in the H2.6 document itself.
- **H2.5j**'s conjunction is not withdrawn as a measurement - it was right for
  the corridor capture it was written from, where the pair was `0.00090` and
  `0.0084`, and that regime still fires through the both-low branch. What is
  corrected is the generalisation to topologies whose gain straddles the
  threshold.

## STOP gate

**Recommendation: GO for P2.**

Every gate passes. The change is one predicate, introduces no constant, is
derived from a measured period-2 structure rather than fitted, eliminates all
22 `iteration_cap` failures in the corpus, causes no regression, and leaves
every shared root bit-identical over 5078 rows.

**H2 is NOT closed.** `uk_bungalow_smoke`'s `damping_exhausted` remains an open
numerical mode, and the C8 and rejection-branch coverage gaps stand. **H3
remains blocked.** No work on `uk_bungalow` was started in this phase.

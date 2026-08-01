# Phase 3+ F3.3v3h2.6 Cross-Topology Audit

Date: 2026-08-01.

Audit only. `sim/core` was not touched: no solver, half step, LM rescue,
iteration cap, tolerance or telemetry changed. Baseline `4ec0f09a` (pre-H2.5m),
candidate `db2815df` (post-H2.5m).

## Verdict

**GO as an audit. NO-GO for closing H2.**

H2.5m was validated on two topologies. This phase extended the runtime corpus
to eight cases spanning chain, star, branched tree, loop and multi-floor
networks. The half step holds up: **zero regressions across 32 runs**, and
convergence rises sharply everywhere it was failing - `uk_bungalow_smoke` goes
from 68.63% to 99.93%.

H2 nevertheless stays open on one blocker: **`two_storey_smoke` keeps 20
`iteration_cap` failures**, and the cause is not the half step.

## Static network vs effective network

The single most important methodological point in this audit.

Topology lives in the ten scenario templates, not in the 108 validation cases;
the cases override fire, ventilation and opening state on top of a template. So
the *declared* network is an upper bound, and the network the solver actually
sees is the connected component of rooms joined by openings the case leaves
open.

`cfast_corridor_chain` makes this concrete: the template `simple_house` is a
**star**, but the case shuts three doors through `opening_overrides` and the
solver ends up on a **three-room, two-opening chain** - exactly the shape the
H2.5a capture recorded. Classifying by template alone would have claimed star
coverage the corpus does not have and missed chain coverage it does.

`scripts/simulation/inventory_phase3_opening_topology.py` therefore reports
both, and derives the effective graph from `template + opening_overrides`.

Effective shape distribution over all 108 committed cases:

| shape | cases |
|---|---:|
| star | 89 |
| loop | 11 |
| branched tree | 6 |
| chain | 2 |

## Class inventory C1-C14

| class | covered by |
|---|---|
| C1 single room + exterior | H1 fixture `_test_exterior_opening_relieves_pressure` |
| C2 two rooms / one link | H1 fixture `_test_single_opening_equalizes_pressure` |
| C3 linear chain | runtime: `cfast_corridor_chain` 3r/2l, `compact_apartment_smoke` 4r/3l |
| C4 star | runtime: `cfast_r0_window_360`, `flashover_simple_house` |
| C5 branched tree | runtime: `cfast_two_floor_stairwell` / `two_storey_smoke` 11r/10l, `three_bed_apartment_smoke` |
| C6 interior loop | runtime: `ghanekar_bedroom_hallway`, `piso_mediterraneo_smoke`, `uk_bungalow_smoke` |
| C7 multi-floor | runtime: `cfast_two_floor_stairwell`, `two_storey_smoke` |
| **C8 parallel openings** | **NOT COVERED - no template has two openings between the same room pair** |
| C9 interior + exterior | runtime: `ghanekar_bedroom_hallway` (2 exterior vents open) |
| C10 asymmetric vents | all ten templates |
| C11 neutral plane inside | runtime (counterflow connections > 0) and H1 fixture |
| C12 unidirectional flow | H1 fixture `_test_one_way_flow_when_neutral_plane_is_outside` |
| C13 counterflow | runtime (counterflow connections > 0) and H1 fixture |
| C14 near-zero / sign-changing dp | H1 fixture `_test_regularization_bounds_the_near_zero_derivative` |

C1, C2, C12 and C14 are covered at unit level on the exact shipped solver
rather than in a scenario. That is deliberate and is stated as such: they are
degenerate limits (one and two unknowns, and the derivative blow-up at dp = 0)
which a fixture pins deterministically and a scenario would only reach by
accident.

## Corpus

Committed case files only.

> **H2.8 NOTE.** The SHA-256 values below are **filesystem** hashes and are
> tree-local: a fresh worktree checkout normalises CRLF to LF, so the same
> committed file hashes differently there. For cross-worktree provenance use the
> Git blob hash (`git rev-parse <commit>:<path>`) or canonical JSON. These
> hashes remain valid for identifying the files within this tree.

SHA-256:

| case | SHA-256 |
|---|---|
| `cfast_two_floor_stairwell` | `2a068a9c949df10e76d74e2ebc7b2746778bb3f8297a507620e77e99bf8e5272` |
| `two_storey_smoke` | `a8f9a00c6206f959e043d0b13bfb3d0d67bf4b198165ad501ad3a20e8172200f` |
| `ghanekar_bedroom_hallway` | `9ece06c9df444a196f94caf6fc867622bda8bcb900826824a70cfe0b13ef15bf` |
| `piso_mediterraneo_smoke` | `6c25d05562f53d836e575230e220e2a913d223de3707bb901e55068c9f54e3d7` |
| `uk_bungalow_smoke` | `ef715e5a2213248d6e41ca566780b1377b7a8c219cbb3f770d9c20de63bd5221` |
| `compact_apartment_smoke` | `486a87cb197454800580ca943abdd70d440af452970b9c0acfbd1fef9719245f` |
| `three_bed_apartment_smoke` | `2cfc830b643d20ea72602ee3ed91c67cbe524d368a8f363c756fc9d26a23a382` |
| `flashover_simple_house` | `25b70560f657c64db194d7194cec1f5daa4286c01d8dd2f2f4eb840f664ce731` |

`cfast_corridor_chain` and `cfast_r0_window_360` carry over unchanged from
H2.5m. All runs 120 s, Godot 4.7.1, sequential, outside the sandbox, editor
closed, via `scripts/run_scenario.py`.

## Matrix

| case | shape | convergence b/a | itcap b/a | damping b/a | half att/acc | max acc/solve | counterflow | runtime ON b/a |
|---|---|---|---:|---:|---|---:|---:|---|
| `cfast_two_floor_stairwell` | branched 11r | 99.86% -> 99.93% | 1 -> 1 | 1 -> **0** | 124 / 124 | 1 | 0 | 240 s -> 214 s |
| `two_storey_smoke` | branched 11r | 98.61% -> 98.61% | **20 -> 20** | 0 -> 0 | 118 / 118 | 1 | 0 | 190 s -> 230 s |
| `ghanekar_bedroom_hallway` | loop 7r | 94.80% -> **99.93%** | 74 -> **0** | 1 -> 1 | 454 / 454 | **2** | 0 | 130 s -> 144 s |
| `piso_mediterraneo_smoke` | loop 7r | 83.14% -> **100.00%** | 243 -> **0** | 0 -> 0 | 304 / 304 | **2** | 0 | 158 s -> 155 s |
| `uk_bungalow_smoke` | loop 5r | 68.63% -> **99.93%** | 451 -> **0** | 1 -> 1 | 758 / 758 | 1 | 0 | 98 s -> 144 s |
| `compact_apartment_smoke` | chain 4r | 91.39% -> **99.31%** | 114 -> **0** | 10 -> 10 | 421 / 421 | 1 | 0 | 85 s -> 141 s |
| `three_bed_apartment_smoke` | branched 7r | 98.06% -> 99.93% | 28 -> **1** | 0 -> 0 | 271 / 271 | **2** | 0 | 145 s -> 183 s |
| `flashover_simple_house` | star 6r | 97.29% -> 98.89% | 23 -> **1** | 16 -> 15 | 150 / 150 | 1 | 0 | 148 s -> 191 s |

Runtime cost: the shadow preview is expensive and scales with room count
(OFF 15-40 s, ON 85-240 s). It is diagnostic-only and does not run in
production. Candidate and baseline are within noise of each other; neither is
systematically slower.

## Gates

| # | gate | result |
|---|---|---|
| 1 | zero solves that converged and now fail | **PASS** - 0 across all 8 |
| 2 | zero residuals accepted above tolerance | **PASS** |
| 3 | zero counterflow violations | **PASS** |
| 4 | mass and energy conservation | **PASS** - physics 0 FAIL |
| 5 | OFF byte-identical | **PASS** - 8/8 |
| 6 | legacy ON columns invariant | **PASS** - 0 differences |
| 7 | determinism (corridor, r0, multi-floor, loop) | **PASS** - 4/4, 4/4, 3/3, 3/3 |
| 8 | factor 0.5 with no configuration | **PASS** |
| 9 | **no case needs more than one accept per solve** | **FAIL** - see below |
| 10 | no displacement to another limiting_reason | **PASS** - damping stable or lower |
| 11 | runtime cost documented | **PASS** |
| 12 | zero residual Godot processes | **PASS** |

Shared-root divergence is **0.000000e+00 across 4567 rows** where baseline and
candidate both converged - a sample 75 times larger than H2.5m's.

## Blocker: `two_storey_smoke` keeps 20 iteration_cap

> **H2.7 CORRECTION (2026-08-01).** The measurements in this section are
> reproducible and stand. **The interpretation below does not.**
>
> This audit read the evidence as "the iteration cap of 24 is sized for
> three-room networks" and handed H2.7 a budget-sizing problem. H2.7 replayed
> five captures across eight budgets and found that reading is wrong:
>
> - the requirement does **not** scale with size - a six-room star needs 28
>   iterations while an eleven-room tree needs 25;
> - it does not correlate with openings, diameter or Jacobian conditioning
>   either;
> - the cap of 24 already sits **above the P99 of 20** over 5016 logged solves.
>
> The real cause is that these solves sit in the **same period-2 square-root
> orbit H2.5m solved**, undetected for 17 to 34 iterations, because the H2.5j
> detector requires two consecutive model gain ratios below `0.05` and the gain
> alternates - one phase near `0.08`, the other near `-0.01` - so the
> conjunction never fires even though the step cosine is `-0.9999` throughout.
>
> The sentence "the iteration cap of 24 is sized for three-room networks" is
> therefore **withdrawn**, along with the framing of H2.7 as cap sizing. What
> remains correct is that this is a real open failure mode on the multi-floor
> class. See `PHASE3_F33V3H27_ITERATION_BUDGET_DESIGN.md`.

Captured with the committed selector and replayed offline
(`tools/diagnostics/phase3_h26_capture_probe.gd`):

| budget | outcome | iterations | final residual | cycles detected | half steps |
|---|---|---:|---|---:|---:|
| 24 (shipped) | `iteration_cap` | 24 | 4.640e-02 | **0** | 0 |
| raised | **converged** | **39** | 7e-14 | 1 | 1 accepted |

The network is 11 rooms and 9 openings. Before the cap the residual falls
**monotonically** at about 0.976 per iteration with **zero cycles detected**, so
this is not an unresolved orbit and the half step is not failing - it is simply
not reached. Past iteration 24 a cycle does form, the half step annihilates it,
and the solve closes at 39.

The diagnosis is therefore that **the iteration cap of 24 is sized for
three-room networks**. It is a real open failure mode, and it is precisely the
multi-floor class this phase existed to cover.

**This does not license changing 24 to 48.** H2.7 must derive how the required
budget scales with rooms and openings and justify a rule, not pick a number.

## Correction: "at most one accept per solve"

H2.5m recorded `max accepts per solve = 1` across its four stages. **That
measurement stands** - it was correct for that corpus. The wider corpus shows it
is not a general property:

| case | accepts | solves with an accept | solves taking two |
|---|---:|---:|---:|
| `ghanekar_bedroom_hallway` | 454 | 450 | 4 |
| `piso_mediterraneo_smoke` | 304 | 303 | 1 |
| `three_bed_apartment_smoke` | 271 | 268 | 3 |

Eight solves out of roughly 2600 (0.3%), only on loop and branched topologies:
a second, distinct orbit forms later in the same solve.

The property that actually holds, and that the implementation guarantees, is
narrower and stronger:

- every accept requires a valid, finite, **strictly decreasing** L-infinity
  residual;
- there is **no artificial budget**, so a second orbit is handled like the
  first;
- the maximum observed on the widened corpus is **2**, not 1.

This is a vindication of the design rather than a defect. Had the half step
been budgeted at one accept per solve - as the LM rescue is - those eight
solves would have reproduced exactly the post-budget recurrence H2.5k
diagnosed.

## Coverage that is absent, not solved

**C8 parallel openings.** No template defines two openings between the same
room pair, so the class cannot be exercised by any committed case. Covering it
needs a new template, which is a larger change than an audit should make.

**The half step's rejection branch.** Attempts equal accepts in all eight cases
here and in all four of H2.5m: across twelve topology runs **no real solve has
ever declined a half step**. The decline path is covered structurally and by
the synthetic fixture only. This remains the same absent coverage H2.5m
recorded, now measured over a much wider corpus.

**Post-budget cycle telemetry.** Still unexercised, for the reason H2.5m gave:
the orbit closes before the rescue budget is spent.

## Remaining failure modes

| case | itcap | damping_exhausted | note |
|---|---:|---:|---|
| `two_storey_smoke` | 20 | 0 | the H2.7 blocker |
| `flashover_simple_house` | 1 | 15 | LM budget is one accept by design |
| `compact_apartment_smoke` | 0 | 10 | same |
| `ghanekar_bedroom_hallway` | 0 | 1 | same |
| `uk_bungalow_smoke` | 0 | 1 | same |
| `cfast_two_floor_stairwell` | 1 | 0 | |
| `three_bed_apartment_smoke` | 1 | 0 | |

`iteration_cap` is essentially eliminated except on `two_storey_smoke`.
Residual `damping_exhausted` is the H2.5g bounded budget behaving as specified.

## Decision

**H2 remains OPEN.** Two closure criteria are unmet: gate 9 fails empirically,
and a real numerical failure mode is open on exactly the topology class this
audit was meant to cover. A solver that loses 20 solves on a standard
two-storey scenario because its iteration budget is sized for three rooms is
not yet "numerically validated in shadow" across topologies.

**H3 remains BLOCKED.** Closing H2 would not by itself authorise H3 or
persistent physics.

Single remaining principal blocker: **H2.7, iteration-cap sizing for large
networks.** The representative capture is already taken and replayable. H2.7
has not started.

> **H2.7 CORRECTION.** "Single remaining principal blocker" is withdrawn. H2.7
> found the cap is not the cause and that H2 has at least **two** distinct open
> items: the alternating-gain cycle detector (H2.8) and `uk_bungalow_smoke`'s
> `damping_exhausted`, which no budget closes even at 256 iterations and which
> is bounded by the H2.5g one-accept LM budget rather than by iterations.

# Phase 3 F3.3v3h2.5l-A - Passive cycle observation

Date: 2026-07-29

> **PROVENANCE CORRECTION (H2.5m, 2026-07-31).**
>
> The "Runtime matrix" table below was measured on scratch case definitions,
> not on the committed case files, and **is not reproducible from the
> repository**. Re-running `sim/validation/cases/cfast_corridor_chain.json` at
> 120 s on the same checkpoint gives 73.77% convergence with **378**
> `iteration_cap`, not the 92.16% / 113 recorded here. Three independent runs
> produced the identical CSV (SHA-256 `9a50cdf2...`), so the runtime is
> deterministic and the discrepancy is one of corpus provenance.
>
> Consequently **the contraction ranges `0.7731..1.0465` (corridor) and
> `1.0038..1.0480` (r0-window) are withdrawn**, together with the conclusion
> drawn from them in "Interpretation" - that the overlap shows contraction
> cannot separate the topologies. That conclusion rested solely on those
> unpinned numbers and no longer supports anything.
>
> What this correction does **not** touch:
>
> - the implementation, which is unchanged and still correct;
> - the deterministic capture table, which replays a committed artifact;
> - **H2.5l-B**, whose ledger was measured on the committed case files,
>   reproduced three times byte for byte, and remains valid in full.
>
> H2.5m superseded this phase's runtime measurements entirely. See
> `PHASE3_F33V3H25M_CYCLE_STRATEGY_DESIGN.md`.

## Decision

**GO for passive telemetry only. NO-GO for H2.5m solver authority.**

H2.5k proved that a period-2 Newton cycle can recur after the one accepted LM
rescue has consumed the complete rescue budget. Before this change, cycle
detection was inside the budget gate, so the solver stopped observing the
phenomenon exactly when it became most important.

H2.5l-A separates observation from intervention. It does not add a rescue,
change a step, alter acceptance, increase the iteration cap, change a
tolerance, or modify any physical state.

## Implementation

The coupled solver now publishes four passive values:

- `cycle_detect_total`;
- `cycle_detect_after_budget_total`;
- `cycle_contraction_min`;
- `cycle_contraction_max`.

The contraction is the dimensionless two-step ratio

`norm(step_k) / max(norm(step_k_minus_2), epsilon)`.

Observation runs before and outside the existing
`cycle_detected and rescue_budget_left > 0` authority gate. The LM rescue and
its one-accepted-step budget remain byte-for-byte in the original gate.

The four values are accumulated by `Phase3ZoneMassSystem` and exported only
with the existing coupled-pressure shadow CSV stack. The legacy schema remains
unchanged when the shadow is OFF.

## Deterministic real capture

`coupled_solver_iteration_cap_after_rescue_corridor_chain.json` records a real
late corridor solve selected by `iteration_cap_after_rescue`.

Its pure fixture replays the committed solver without a scenario or engine:

| Value | Result |
|---|---:|
| Limiting reason | `iteration_cap` |
| Iterations | 24 |
| Cycle-guard attempts / accepts | 1 / 1 |
| Cycle detections | 22 |
| Detections after budget | 21 |
| Contraction min / max | 0.990546 / 0.990952 |

The numerical outcome is intentionally unchanged. The fixture fails if passive
telemetry changes the failure mode, iteration budget, or rescue authority.

## Runtime matrix

All runs used `scripts/run_scenario.py`, Godot 4.7.1, a closed editor, one
process at a time, an explicit log, and no sandbox. The baseline was produced
from a detached clean worktree at `35d54f38`; candidate runs used the same
cases and flags.

| Stage | Steps | Converged | Iteration cap | Damping exhausted | Cycle detects | After budget | Contraction min / max |
|---|---:|---:|---:|---:|---:|---:|---:|
| corridor 30 s | 361 | 98.61% | 5 | 0 | 292 | 178 | 0.7731 / 1.0465 |
| corridor 60 s | 720 | 99.31% | 5 | 0 | 292 | 178 | 0.7731 / 1.0465 |
| corridor 120 s | 1441 | 92.16% | 113 | 0 | 2722 | 2211 | 0.7731 / 1.0465 |
| r0-window 120 s | 1441 | 100.00% | 0 | 0 | 204 | 0 | 1.0038 / 1.0480 |

For every stage:

- OFF CSV SHA-256 is identical to the clean-worktree baseline;
- all pre-existing ON columns are identical;
- exactly four opt-in telemetry columns are added;
- counterflow violations remain zero.

The current scratch case definitions are mutable diagnostics, so this table is
an invariance and distribution measurement for the current checkpoint. It
does not replace the historical H2.5j validation table.

## Interpretation

Post-budget recurrence is real and material in the late corridor regime:
`2211` detections are observed after intervention authority has ended. The
r0-window topology has `204` detections but none after budget, consistent with
its solve closing after the authorised rescue.

**WITHDRAWN (H2.5m).** This section originally argued that the contraction
scalar cannot separate the topologies, using corridor `0.7731..1.0465` against
r0-window `1.0038..1.0480`. Those ranges came from the unpinned scratch corpus
described in the correction at the head of this document and are withdrawn.

The caution the section expressed was nonetheless the right one, and it was
honoured: H2.5m did not adopt any contraction threshold. It found instead that
the orbit is the exact fixed point of Newton on a residual of degree `1/2` -
the orifice law - and used the analytic annihilator `theta = 1/2`, which is
derived rather than fitted to any corpus.

The four aggregate scalars also cannot report the exact number of distinct
solves that enter a second cycle or the full per-solve contraction
distribution. A sampled CSV cannot reconstruct those events after the fact.
That limitation is explicit; no extra authority or silently inferred count was
added.

## Verification

| Check | Result |
|---|---|
| Solver fixtures | 7/7 PASS |
| H2.5l targeted pytest | 20/20 PASS |
| `pytest -k "phase3 or guardrail"` | 1093 PASS / 2 known FAIL |
| Physics coherence | 9 PASS / 15 CTRL / 5 WARN / 0 FAIL |
| ILV coherence | 15 PASS / 14 CTRL / 0 FAIL |
| Gap inventory | 353 required + 6 VALID_GAP + 71 non-gating |
| Guardrails | 9/10; only R2-1 from dirty motor |
| Godot residual processes | 0 |

The second pytest failure is the historical
`test_csv_exports_three_canonical_layers`. R2-1 is expected until a future
approved commit is followed by the separate timestamp refresh.

## Next step

H2 remains open and H3 remains blocked.

Before H2.5m may change solver authority, choose and instrument a per-solve
event measure, for example:

- count of solves with a post-budget recurrence;
- maximum post-budget cycle streak per solve;
- whether such a solve later converges or reaches `iteration_cap`.

That follow-up must remain passive first. Only a measured cross-topology
separation can justify another rescue strategy.

# Phase 3+ F3.3v3h2.5l-B Per-Solve Recurrence Ledger

Date: 2026-07-29.

## Purpose

H2.5l-A proved that cycle recurrence exists after the one-step LM rescue
budget is exhausted but could not answer how many distinct solves are affected,
whether they eventually converge, or how long the recurrence persists within a
single solve. This document records the per-solve recurrence ledger that
answers those questions.

## What changed

### Solver (`Phase3CoupledPressureSolver.gd`)

One new result field: `post_budget_cycle_streak_max`. It tracks the longest
consecutive run of `cycle_detected AND rescue_budget_left <= 0` within a
single solver invocation.

The streak:
- increments on each iteration where the period-2 detector fires and the
  budget is already exhausted;
- resets to zero on: no cycle detected, accepted fail-only rescue, accepted
  cycle-guard rescue, damped (non-full) step;
- never appears in any `if`, `while`, `return`, `converged`, or `accepted`
  expression.

No Newton step, acceptance criterion, merit function, damping, tolerance,
Jacobian, gauge formulation, regularization, iteration cap, or rescue budget
was changed.

### Zone mass system (`Phase3ZoneMassSystem.gd`)

Five cumulative counters derived per solver invocation:

| Field | Meaning |
|---|---|
| `post_budget_cycle_solve_count` | Solves where `post_budget_cycle_streak_max > 0` |
| `post_budget_cycle_converged_solve_count` | Subset that converged |
| `post_budget_cycle_iteration_cap_solve_count` | Subset that hit iteration_cap |
| `post_budget_cycle_damping_exhausted_solve_count` | Subset that hit damping_exhausted |
| `post_budget_cycle_streak_max` | Global maximum streak across all solves |

Each solve adds at most one to any outcome counter. The classification is
mutually exclusive: converged, iteration_cap, or damping_exhausted.

### CSV columns (`SimulationLogWriter.gd`)

Per-step (cumulative through the unsuffixed opt-in path):
- `phase3_shadow_coupled_solver_post_budget_cycle_streak_max`

Cumulative totals:
- `phase3_shadow_coupled_solver_post_budget_cycle_solve_count_total`
- `phase3_shadow_coupled_solver_post_budget_cycle_converged_solve_count_total`
- `phase3_shadow_coupled_solver_post_budget_cycle_iteration_cap_solve_count_total`
- `phase3_shadow_coupled_solver_post_budget_cycle_damping_exhausted_solve_count_total`
- `phase3_shadow_coupled_solver_post_budget_cycle_streak_max_total`

## Corpus results

### corridor_chain

| Duration | Physical solves | Post-budget solves | Converged after | iteration_cap | damping_exhausted | Streak max | Recurrence rate |
|---|---|---|---|---|---|---|---|
| 30 s | 361 | 17 | 10 | 7 | 0 | 21 | 4.7% |
| 60 s | 720 | 17 | 10 | 7 | 0 | 21 | 2.4% |
| 120 s | 1441 | 559 | 181 | 378 | 0 | 21 | 38.8% |

At 30 and 60 s the corridor has not yet entered the regime where failures
appear (convergence rate >98%). By 120 s, 378 of the 559 recurring solves
end at iteration_cap, and 181 converge. The 120 s convergence rate overall is
73.8%.

The streak maximum of 21 (identical across all durations) corresponds to
exactly 21 consecutive post-budget detections in a single solve. This equals
the `cycle_detect_after_budget_total` from a single solve in the H2.5l-A
capture: the entire post-budget sequence is one unbroken recurrence.

### r0_window_360

| Duration | Physical solves | Post-budget solves | Converged after | iteration_cap | damping_exhausted | Streak max | Recurrence rate |
|---|---|---|---|---|---|---|---|
| 120 s | 1441 | 0 | 0 | 0 | 0 | 0 | 0.0% |

Zero post-budget recurrence. All 1441 solves converge. The 204 cycle
detections all occur with rescue budget available and all are successfully
rescued.

## Cross-topology separation

The per-solve flag cleanly separates corridor from r0_window:

- corridor has `post_budget_cycle_solve_count > 0` starting from 30 s;
- r0_window has `post_budget_cycle_solve_count == 0` at 120 s.

This is the evidence H2.5l-A could not provide. The cumulative iteration
counts in H2.5l-A were ambiguous about whether the detections came from one
solve or many; the per-solve ledger proves they come from 559 distinct solves
in corridor.

## Isolation

OFF SHA-256 hashes:

| Case | SHA-256 |
|---|---|
| corridor_chain 30 s | `7135a76aeb523e5cef30ba4a1378d9e10854ef8f29ca658a89bdd237fa1fe0a7` |
| corridor_chain 60 s | `77277312a03fc02dff1beb42a8bf18981283b5996f6269b3ec2d28bd681aa8a3` |
| corridor_chain 120 s | `15a7a84fc1b0f8d8282dabb0a3c1f892f33047a28957b0f730142284600ca081` |
| r0_window_360 120 s | `5ad6ea0de2796379128e2ac8af8e92409027fa1c0429d1d03438ebe0df574eea` |

All shared ON columns are byte-identical to their OFF counterparts (zero
shared value differences across all four cases).

## Fixture

`tests/fixtures/phase3_f33v3h25lb_per_solve_recurrence_ledger.gd` replays the
same corridor capture as H2.5l-A. It verifies:

- `post_budget_cycle_streak_max > 0`
- streak cannot exceed `cycle_detect_after_budget_total`
- deterministic across two consecutive replays
- the real `iteration_cap` at 24 iterations and one accepted rescue survive

## Tests

`tests/test_phase3_f33v3h25lb_per_solve_recurrence_ledger.py` (15 tests):

- streak tracking inside the observation block, outside the budget gate;
- streak resets on all four trajectory breaks;
- streak never controls solver behaviour (no `if`/`while`/`converged`/
  `accepted`);
- per-solve classification is mutually exclusive;
- each solve adds at most one to the solve counter;
- cumulative fields present in record, cumulative, and CSV;
- mutation test: streak inside budget gate is detectable;
- mutation test: streak used for convergence would fail;
- fixture structural assertions;
- no numerical setting changed.

## STOP gate decision

**GO for passive per-solve recurrence ledger.**

- streak tracks correctly and resets on trajectory breaks: PASS;
- outcome classification mutually exclusive and bounded: PASS;
- clean cross-topology separation on the per-solve flag: PASS;
- OFF CSVs byte-identical: PASS;
- all shared ON columns identical: PASS;
- zero counterflow violations: PASS;
- Physics/ILV at 0 FAIL: PASS;
- no physical report, tolerance, CTRL or VALID_GAP changed: PASS.

**H2.5m solver authority remains blocked.** The per-solve separation is clear
but limited to two topologies. Before proposing a second rescue or contraction
threshold, the separation must be confirmed on a wider corpus and the
persistence duration (21 iterations) must be shown to be robust rather than
a single-topology artifact.

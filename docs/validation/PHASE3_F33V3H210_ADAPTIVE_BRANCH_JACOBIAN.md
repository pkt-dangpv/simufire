# Phase 3 F3.3v3h2.10 - Adaptive branch-preserving Jacobian

## Status

STOP gate passed on 2026-08-01. H2 closes as numerical readiness for the
passive coupled pressure solver; H3 is unblocked but not started. This phase
targets the `damping_exhausted` mode pinned by the committed
`uk_bungalow_smoke` capture without changing the successful primary solve.

## Problem

H2.9 measured a piecewise-differentiable residual. The shipped forward
difference uses `h = 1e-3 Pa`; in the UK capture an opening sits at
`dp = -5.307e-4 Pa`, so the forward probe crosses zero and changes the upwind
donor. The resulting column is not the local derivative of the active branch.
The Jacobian is finite and solvable, but every Newton and LM trial increases
the real residual.

A global smaller step is not accepted as a design: it would be an unexplained
numerical tuning knob. A central quotient is also excluded because H2.5c
measured a catastrophic runtime regression in `r0_window_360`.

## Authority boundary

The shipped forward Jacobian, Newton step and strict L-infinity line search run
unchanged. The adaptive path is reachable only after that line search has
failed and before the existing LM fallback. Therefore every solve that already
succeeds executes the same numerical path and produces the same result.

The adaptive path is a recovery step, never a convergence decision. If it
accepts a state, control returns to the ordinary loop and the unchanged
`1e-12` L-infinity criterion decides convergence. If it cannot establish a
locally coherent derivative, control falls through to LM unchanged.

## Branch-preserving column

For every pressure column and width, evaluate both unilateral probes. Compare
their opening branch changes lexicographically:

1. pressure/donor direction changes;
2. neutral-plane and directional-flow presence changes;
3. regularization-membership changes.

The backward side is selected only when it is strictly closer to the current
branch. A tie preserves the shipped forward bias. This ordering is categorical;
there is no weighted score or case-dependent threshold.

## Adaptive width and self-consistency

Start from the existing `jacobian_step_pa` and halve it deterministically. The
existing `max_damping_halvings` bounds the refinement work; no new option or
per-case knob is introduced.

At each width:

1. assemble a branch-preserving unilateral Jacobian;
2. solve its Newton system;
3. apply the unchanged strict L-infinity backtracking test;
4. require two consecutive widths to produce an accepted real step with the
   same per-column side selection;
5. accept the finer candidate only.

This is behavioural derivative self-consistency. It does not compare floating
derivatives with a fitted tolerance. Failure to obtain two consecutive coherent
candidates leaves the state untouched and hands authority to the existing LM
path.

## Telemetry

Opt-in shadow telemetry records attempts, accepts, forward/backward columns,
reduced-width columns, avoided branch crossings, consistency failures and the
minimum effective step. Counters are outputs only and must never govern solver
behaviour.

## Cost bound

Successful solves pay zero additional residual evaluations. On the fail-only
path, one refinement level costs two probes per room plus at most the existing
line-search budget. Refinement is bounded by the existing halving budget and
normally stops after the first two coherent widths.

## Required STOP gate

- all nine committed exact captures;
- the deterministic 189-state H2.9 neighbourhood;
- a C8 fixture with parallel openings;
- ten committed runtime topology cases;
- OFF byte identity and shared ON-column identity;
- zero converged-to-failed solves and an explicit shared-root delta bound;
- unchanged iteration cap, tolerance, LM budget, cycle detector, gauge, EOS,
  regularization and orifice law;
- mass/energy conservation and zero counterflow violations;
- deterministic complete runs with row-count validation;
- LM-use delta in the UK topology, not merely a renamed failure.

No H2.10 commit or push is allowed before this gate is reported.

## STOP gate result

### Exact and synthetic gates

- all nine committed exact captures converge;
- deterministic H2.9 neighbourhood: `182/189 -> 189/189`;
- C8 parallel-opening fixture: both routes preserved, conservation and
  reordering symmetry pass, zero counterflow violations;
- twelve direct Godot 4.7.1 fixtures pass sequentially with explicit logs.

### Runtime matrix

Ten committed cases ran for 120 s through `scripts/run_scenario.py`:

| case | convergence before | after | damping before | after | adaptive |
|---|---:|---:|---:|---:|---:|
| cfast_corridor_chain | 100.000% | 100.000% | 0 | 0 | 5/5 |
| cfast_r0_window_360 | 100.000% | 100.000% | 0 | 0 | 0/0 |
| cfast_two_floor_stairwell | 100.000% | 100.000% | 0 | 0 | 0/0 |
| two_storey_smoke | 100.000% | 100.000% | 0 | 0 | 2/2 |
| ghanekar_bedroom_hallway | 99.931% | 100.000% | 1 | 0 | 2/2 |
| piso_mediterraneo_smoke | 100.000% | 100.000% | 0 | 0 | 0/0 |
| uk_bungalow_smoke | 99.931% | 100.000% | 1 | 0 | 1/1 |
| compact_apartment_smoke | 99.306% | 100.000% | 10 | 0 | 10/10 |
| three_bed_apartment_smoke | 100.000% | 100.000% | 0 | 0 | 2/2 |
| flashover_simple_house | 98.959% | 100.000% | 15 | 0 | 32/32 |

Aggregate: `damping_exhausted 27 -> 0`, `iteration_cap 0 -> 0`, adaptive
attempts/accepts `54/54`, LM acceptances `54 -> 0`, no converged-to-failed
solve and zero counterflow violations.

### Isolation, determinism and suites

- OFF CSV byte-identical in 10/10 cases;
- zero differences in shared ON legacy columns;
- sampled shared-root divergence `0.000000e+00 Pa`;
- three complete runs each of UK bungalow, compact apartment and flashover
  house have identical SHA-256, row count and completed manifest;
- Physics coherence 9 PASS / 15 CTRL / 5 WARN / 0 FAIL;
- ILV 15 PASS / 14 CTRL / 0 FAIL;
- gap inventory unchanged: 353 required, 6 VALID_GAP and 71 non-gating;
- focused structural tests 213/213 PASS;
- guardrails 9/10 only because R2-1 correctly detects the uncommitted motor
  patch. No reference report was refreshed before this STOP.

## Decision and limits

**GO.** H2 is closed as numerical readiness for the passive coupled pressure
solver, and H3 is unblocked. H3 has not started and this decision grants no
runtime authority to the shadow solver by itself.

Two limits remain explicit:

1. runtime coverage is ten committed topologies plus the synthetic C8
   parallel-opening contract;
2. every real adaptive attempt succeeded, so a real runtime decline into LM is
   not represented in this corpus, although the fallback remains structurally
   reachable and tested.

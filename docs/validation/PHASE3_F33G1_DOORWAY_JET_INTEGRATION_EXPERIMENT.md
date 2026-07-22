# Phase 3+ F3.3g1 - Per-slab doorway-jet integration experiment

Date: 2026-07-22

## Decision

**Integration contract GO; runtime candidate NO-GO at the 180 s STOP.**

The per-slab transport representation, the Poreh receiver routes and their
atomic accounting are retained as internal, default-false building blocks.
The temporary Engine, CLI and CSV runtime surface was removed. No official
case, report, baseline, tolerance, CTRL or VALID_GAP changed.

The failed physical hypothesis was the composition of two operations:

1. direct opening transport preserves the source zone; and
2. Poreh mixing independently transfers receiver inventory between zones.

That composition is conservative and deterministic, but it does not reproduce
the CFAST Group C upper/lower flow split. Longer 300/590 s runs were therefore
not started.

## Implemented internal contract

F3.3a and F3.3b previews now preserve each nonzero hydrostatic slab with:

- lower and upper slab bounds;
- source and destination side;
- source zone;
- geometric and selected destination zone;
- mass-flow rate.

The signed-pressure slabs are scaled only after network pressure relaxation.
The optional internal candidate then creates two distinct atomic bundles from
one pre-step snapshot:

- `f33a_interior_network`: direct source-preserving transport;
- `f33g_doorway_jet_network`: receiver-internal Poreh mixing.

The direct bundle is applied before the mixing bundle. Opening order does not
change the final state. The candidate remains an internal function parameter
whose default is `false`; there is no public runtime flag.

## OFF identity

The 180 s OFF run is byte-identical to the prior F3.3f2 checkpoint:

- SHA-256: `6F7FD18D3C451D2AE615D695B066A08F9F593DF5708E864DD50067CECF09ED70`;
- 114 CSV rows;
- 667 columns.

All 115 legacy columns are also identical between OFF and the temporary ON
run. The experiment therefore did not alter legacy physics.

## Group C 180 s STOP

R0 cumulative accepted opening plus signed-pressure inflow:

| Quantity | OFF | Candidate ON | CFAST target |
|---|---:|---:|---:|
| Lower direct inflow | 46.143 kg | 51.901 kg | 65.782 kg |
| Upper direct inflow | 7.516 kg | 0.482 kg | 3.662 kg |
| Total direct inflow | 53.659 kg | 52.383 kg | 69.444 kg |

Candidate Poreh receiver mixing:

| Route | Accepted mass | Accepted energy |
|---|---:|---:|
| Hot lower to upper | 0.036 kg | 0.206 kJ |
| Cool upper to lower | 0.738 kg | 56.119 kJ |

R0 state at 180 s:

| Quantity | OFF | Candidate ON | CFAST target |
|---|---:|---:|---:|
| Upper temperature | 125.70 C | 128.68 C | 159.82 C |
| Interface height | 1.101 m | 1.158 m | 0.736 m |
| Upper gas mass | 22.921 kg | 21.745 kg | 26.940 kg |
| Lower gas mass | 25.000 kg | 27.264 kg | n/a |

The hot Poreh branch is too small to restore the missing upper stream, while
the cool branch is about twenty times larger and transfers upper receiver gas
downward. Temperature improves slightly, but upper mass and interface move
away from CFAST. This triggers the explicit physical rollback criterion.

## Conservation and acceptance

Both OFF and ON close exactly:

- building mass residence residual: `0.0 kg`;
- building enthalpy residence residual: `0.0 kJ`;
- interior mass, energy, O2 and species residuals: `0.0`;
- minimum atomic accepted fraction: `1.0`;
- rejected candidate mass: `0.0 kg`.

The generic legacy-versus-shadow energy residual is not a transaction
conservation residual and is not used to reject this candidate.

## Root-cause interpretation

The result invalidates the assumed mapping between CFAST output quantities and
SimuFire route ownership. It does not invalidate the Poreh equation itself.
Before another runtime candidate, the CFAST source and output writer must be
traced end to end to answer:

1. whether reported upper/lower doorway flow contains the direct stream,
   induced mixing, or both;
2. where `UFLW`, `UFLW2` and `UFLW3` are accumulated and transformed;
3. whether direct destination is geometric, source-preserving, or output-only;
4. whether the Poreh route changes reported layer flow without representing a
   separate physical mass crossing the doorway;
5. which quantities are comparable to SimuFire's direct and residence ledgers.

This source-to-output correspondence audit is F3.3h. No new runtime flag,
coefficient, Qc coupling or long Group C run is allowed before it closes.

F3.3h subsequently closed that audit. CFAST direct receiver deposition uses
the `flogo` temperature split, not source-preserving routing. Standard vent
output excludes Poreh even though the ODE includes it. This explains the
F3.3g1 result and selects pure buoyancy routing as F3.3h1.

## Verification

| Check | Result |
|---|---|
| Focused F3.3g/F3.3g1 tests | 16 PASS |
| All `test_phase3*.py` | 448 PASS |
| Godot 4.7.1 isolated fixture | PASS |
| Physics coherence | 9 PASS / 15 CTRL / 5 WARN / 0 FAIL |
| ILV coherence | 15 PASS / 14 CTRL / 0 FAIL |
| Gap inventory | 348/353 PASS; 5 VALID_GAP; 71 non-gating |
| Validation guardrails | 9/10; only expected R2-1 from dirty motor |
| Slab aggregate equivalence | exact |
| Atomic mass/energy/O2/species closure | exact |
| Opening-order equivalence | exact |
| Public Engine/CLI/CSV candidate surface | removed |
| Official reports/baselines/tolerances/gaps | unchanged |

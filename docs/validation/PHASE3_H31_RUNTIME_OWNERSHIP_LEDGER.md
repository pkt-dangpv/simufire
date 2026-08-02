# Phase 3 H3.1 - Passive Runtime Ownership Ledger

Date: 2026-08-02

## Decision

**GO at the implementation STOP gate, without runtime authority.** H3.1 adds
opt-in observation only. It does not move the coupled solver, reorder the tick,
change a transport equation, commit canonical state, or alter a validation
baseline.

H3.2 remains blocked until this ledger is used to design the shadow bundle.
H3.2b remains a hard prerequisite before any H3.3 mass/energy commit.

## Flag semantics

`phase3_runtime_ownership_ledger_enabled` is exported and defaults to `false`.
Projection tracing uses the effective condition:

```gdscript
phase3_zone_diagnostics_enabled or phase3_runtime_ownership_ledger_enabled
```

Neither flag mutates the other. Both requested flags and the effective state
are exported. Enabling both records each projection once: the 10 s corridor
probe produced seven calls with H3.1 alone and seven with both flags; all 68
H3.1 columns were identical.

## What is observed

The ledger snapshots upper/lower gas mass and sensible energy around the real
writer families in tick order:

1. pool fire;
2. oxygen exchange;
3. combustion and targets;
4. thermal;
5. suppression, steam and glass;
6. gas exchange;
7. HVAC;
8. passive fuel and spread;
9. two-zone reconcile;
10. final clamp/projection.

`ThermalSystem` additionally emits passive events for the three distinct
interior paths that must not be conflated in H3.3:

- canonical upper hot-gas transport;
- canonical lower return;
- thermal counterflow.

These events are explanatory sub-ownership and are not added again to the
stage total. That prevents double counting.

## Projection reuse

H3.1 reuses `ZoneFireSolver._projection_trace_events`; no second snapshot or
counter was added to `project_room_state`. Events are aggregated by room and
cause, and their total energy delta is compared with the existing
`two_zone_boundary_energy_kj` increment.

The structured per-cause map is exported as
`phase3_runtime_ownership_projection_by_cause`. CSV keeps the aggregate totals
needed for corpus analysis.

## Delayed parcels

The existing real parcel event stream is observed when either the canonical
shadow or H3.1 is active. H3.1 adds no parcel and changes no delivery. It records
step-boundary inventory and created, delivered and cancelled mass/enthalpy.

The per-step checks are:

```text
post = pre + created - delivered - cancelled
```

for gas mass and sensible enthalpy. Events are peeked before the canonical
shadow drains them; H3.1-only runs drain them after observation. Therefore the
two consumers neither duplicate nor lose events.

## Runtime gate

All runs used committed case files, Godot 4.7.1, `scripts/run_scenario.py`,
120 s, sequential execution, explicit logs, and no editor process.

| Case | Rows | Projection calls max/row | Parcel events max/row |
|---|---:|---:|---:|
| `cfast_corridor_chain` | 78 | 16 | 8 |
| `cfast_r0_window_360` | 78 | 8 | 0 |
| `cfast_two_floor_stairwell` | 169 | 13 | 2 |
| `two_storey_smoke` | 1573 | 14 | 2 |
| `ghanekar_bedroom_hallway` | 130 | 19 | 7 |
| `piso_mediterraneo_smoke` | 1210 | 15 | 5 |
| `uk_bungalow_smoke` | 847 | 13 | 6 |
| `compact_apartment_smoke` | 605 | 13 | 6 |
| `three_bed_apartment_smoke` | 1089 | 13 | 6 |
| `flashover_simple_house` | 726 | 20 | 12 |
| `fuel_balance_diag_sealed` | 150 | 13 | 0 |
| `o2_stoich_diag_sealed` | 150 | 13 | 0 |

Across all twelve:

- maximum stage attribution mass residual: `0 kg`;
- maximum stage attribution energy residual: `0 kJ`;
- maximum parcel mass residual: `0 kg`;
- maximum parcel energy residual: `0 kJ`;
- maximum projection-vs-boundary energy residual: `0 kJ`;
- Godot errors or truncated manifests: `0`.

The ten opening-network cases were compared against the H2.10 OFF artifacts:
row counts matched and all 115 shared legacy columns had **zero differences**.
A fresh short OFF/ON probe independently produced the same result.

The corpus exercises non-zero upper transport, lower-return energy,
counterflow energy, projection and delayed parcels. The sealed controls confirm
that zero parcel activity is represented explicitly rather than inferred from
missing columns.

## Interpretation limit

The stage residual closes by observing every stage boundary. It proves that
the listed runtime writer families account for the state delta; it does **not**
prove that those legacy writes are physically correct. In particular:

- projection still reconstructs energy;
- clamp remains a writer, not a residual-only validator;
- delayed parcels still own transport across timesteps;
- the coupled solver remains passive and runs after the legacy state is final.

H3.1 therefore grants no authority and closes no CFAST VALID_GAP.

## Verification

- focused H3.1/F0/F2.0 structural tests: PASS;
- Physics coherence: `9 PASS / 15 CTRL / 5 WARN / 0 FAIL`;
- ILV coherence: `15 PASS / 14 CTRL / 0 FAIL`;
- gap inventory: `353 required, 6 VALID_GAP, 71 non-gating`, synchronized;
- broad Phase 3/guardrail selection: H3.1-related contracts PASS; only R2-1
  (dirty motor, expected before commit) and the historical layer-interface
  parser test remain.

## Next phase

H3.2 may now design the passive accepted bundle from measured ownership.
Before H3.3 can write mass or energy, H3.2b must convert
`project_room_state` from reconstruction to residual projection while keeping
the thermal cap as an explicit, measured sink.

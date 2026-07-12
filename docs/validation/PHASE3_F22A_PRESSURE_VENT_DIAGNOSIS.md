# Phase 3+ F2.2a — Pressure vent diagnosis

Date: 2026-07-12

## Decision

Physical patch: **NO-GO**. Passive diagnostics: **GO / accepted for the
Phase 3+ clean-start baseline**.

The pressure shown by the legacy CSV was not the pressure driving the vent.
`SimulationStateBuilder` preferred `pressure_pa_therm` whenever it was positive,
while `step_pressure_venting()` used `room.overpressure_pa` because
`phase3_pressure_canonical_enabled` was false.

## Causal path

```text
HRR -> parallel thermodynamic pressure (diagnostic, not authoritative)
temperature/interface -> legacy buoyancy pressure (authoritative)
legacy pressure -> Bernoulli q_out -> raw vented gas mass
raw gas mass -> smoke particle cap -> smoke_out_kg
smoke_out_kg / smoke stock -> frac_out
frac_out -> remove_upper_layer_fraction -> upper gas and energy deletion
project_room_state -> EOS backfill -> two_zone_boundary_mass
```

The unit mismatch is at `smoke_out_kg / smoke_kg`: a particle-stock fraction
is reused as a gas-zone fraction.

## Measurements

| Metric (room 0) | cfast_r0_window_360 | cfast_corridor_chain |
|---|---:|---:|
| Maximum parallel pressure | 405,297 Pa | 145.83 Pa |
| Maximum authoritative pressure | 6.20 Pa | 2.00 Pa |
| Maximum buoyancy pressure | 6.45 Pa | 2.14 Pa |
| Raw Bernoulli gas mass | 24.47 kg | 0.302 kg |
| Gas mass after smoke cap | 4.01 kg | 0.302 kg |
| Upper-zone mass deleted | 266.60 kg | 54.46 kg |
| Parcel upper out / in | not dominant | 1240.47 / 866.69 kg |
| Final room boundary mass | +260.19 kg | +449.93 kg |

## Rejected physical experiment

An opt-in experiment used `raw_vented_air_kg / upper_gas_kg` for the upper-zone
purge while keeping the soot cap independent. It made removed upper mass agree
with raw gas transport, but exposed an unstable zone inventory:

| R0 metric | Legacy | Gas-mass purge |
|---|---:|---:|
| Raw gas mass | 24.47 kg | 87.58 kg |
| Upper mass removed | 266.60 kg | 88.00 kg |
| Minimum lower gas mass | 18.52 kg | 0.03 kg |
| Final boundary mass | +260.19 kg | +77.35 kg |
| Upper temperature at 510 s | 291.07 C | 305.46 C |

The experiment was reverted. A local vent correction cannot be accepted while
`project_room_state()` reconstructs lower mass from EOS after every subsystem.

## Instrumentation retained

When `phase3_zone_diagnostics_enabled` is true, the CSV now exposes:

- `pressure_therm_pa`
- `pressure_model_pa`
- `pressure_effective_pa`
- `pressure_buoyancy_pa`
- `pressure_stack_pa`
- `pressure_raw_vented_air_kg_total`
- `pressure_capped_vented_air_kg_total`

The instrumentation is passive and diagnostic-only. OFF/ON comparison produced
zero differences across 156 shared columns and all rows in both control cases.
It is part of the diagnostic baseline for the next phase and should be kept.

## Required next architecture

1. Make upper/lower mass and interface the integrated canonical state.
2. Make EOS a diagnostic/closure equation instead of a mass backfill source.
3. Separate transported air mass from soot-particle mass in exterior venting.
4. Apply gas, energy, oxygen and species transport from one gas-mass fraction.
5. Retry ledger-aware projection only after the canonical zone inventory is
   stable without reconstruction.

F2.1 must not be retried before these prerequisites.

## Status for new work

This document closes the local pressure-vent patch route. The next active work
is not another pressure or projection correction; it is F3.0 shadow canonical
two-zone state as described in
`docs/validation/PHASE3_CANONICAL_TWO_ZONE_ARCHITECTURE.md`.

# Phase 3+ F3.2a canonical exterior boundary shadow

Date: 2026-07-18

## Decision

**GO for the passive exterior-boundary contract. NO-GO for canonical room-state
authority or for claiming Group A closed.**

This is the implementation STOP-gate recommendation. The patch is not yet
committed or pushed.

F3.2a adds one opt-in, default-OFF pressure/leakage bundle to the canonical
shadow. The bundle moves gas mass, sensible energy, O2 and all seven parcel
species with one direction and one inventory-limited accepted fraction. It
never writes `RoomModel` and changes no legacy output.

The runtime audit also corrects an initial ordering assumption. Computing the
boundary directly from the legacy pre-step snapshot returned almost exactly
ambient pressure in `cfast_r0_window_360`, because legacy EOS projection had
already erased the previous pressure surplus. The accepted order is:

```text
legacy pre-step snapshot
  + explicit canonical internal transactions
  -> F3.1e thermodynamic candidate state
  -> F3.2a exterior boundary bundle
  -> final passive canonical state and telemetry
```

This remains non-circular: the boundary consumes only the immutable snapshot
plus explicit shadow fluxes. It does not observe a legacy post-mutation delta.

## Ownership scope

Only the legacy `pressure_venting` shadow purge event is suppressed when F3.2a
is enabled. Smoke venting, natural ventilation, ACH/infiltration,
outside-open species purge, post-fire purge and PPV remain separate visible
legacy contracts.

F3.2a uses immediate atomic routes to exterior ID `-1`; it does not create a
delayed parcel. Positive pressure produces zonal outflow with source-specific
enthalpy, O2 and species. Negative pressure produces ambient inflow with
outside O2, zero sensible energy relative to the ambient reference and zero
pollutant inventory. Opening area is split across upper/lower zones using the
F3.1e canonical interface. Closed openings use the configured leakage area.

## Implementation

- `SimulationEngine.gd`: default-OFF flag, step registration, shadow-only
  legacy pressure-owner suppression and state context.
- `Phase3ZoneMassSystem.gd`: deferred canonical pressure solve, Bernoulli
  request, atomic bundle, inventory arbitration and residual telemetry.
- `SimulationStateBuilder.gd` and `SimulationLogWriter.gd`: flag and 27 CSV
  fields, emitted only when F3.2a is active.
- `scripts/run_scenario.py` and `tools/run_scenario_headless.gd`: explicit
  scratch-run flag; F3.2a implies its F3.0 parent shadow.
- `tests/test_phase3_f32a_exterior_boundary_shadow.py` and the direct Godot
  fixture cover wiring, ownership, direction, inventory limits, conservation
  and determinism.

The telemetry includes requested/accepted/rejected gas, energy, O2 and
species, pre-boundary pressure, direction, zonal source code, accepted
fraction, owner suppression/duplication, four independent residuals and the
post-bundle upper/lower O2 inventories and fractions.

## Runtime evidence

The direct Godot fixture passes no-area, positive-pressure,
negative-pressure, inventory-cap and deterministic controls. Mass, energy,
O2 and species split residuals are exact zero.

The 30 s sealed control has zero exterior events, requested mass and
suppressed pressure events. OFF and ON have 363 shared CSV columns with zero
byte-level value differences. F3.2a adds only its 27 gated columns.

Scratch `cfast_r0_window_360`, 520 s, six rooms:

| Metric | Result |
|---|---:|
| Canonical pressure range | `-0.83..125.85 Pa` |
| Rows with active bundle | `48` (room 0 only) |
| Maximum gas request/acceptance per step | `1.98864253 kg` |
| Minimum accepted fraction | `1.0` |
| Maximum rejected gas | `0 kg` |
| Legacy pressure events suppressed in shadow | `25` |
| Duplicate owner flag | `0` |
| Mass/energy/O2/species boundary residuals | exact `0` |
| Thermodynamic volume closure | exact `0 m3` |
| Room 0 upper/lower gas minima after initial row | `1.054 / 18.500 kg` |

All 115 legacy CSV columns are byte-identical OFF versus ON across all 318
rows. Existing canonical-shadow columns change as intended because F3.2a
changes only the parallel state.

## Group A result

F3.2a does not close the three Group A O2 checks. They occur before or at the
window-opening instant, and closed leakage cannot correct upper-zone O2
bookkeeping.

| Time | CFAST upper O2 | Legacy upper O2 | F3.2a shadow upper O2 |
|---:|---:|---:|---:|
| 240 s | `0.085108` | `0.15951` | `0.15948788` |
| 350 s | `0.0659799` | `0.09819` | `0.09820105` |
| 360 s | `0.0645067` | `0.09345` | `0.09346822` |

This is not a regression: legacy values are identical. It proves that
exterior pressure ownership is necessary but insufficient. Canonical state is
still reseeded from legacy every timestep, and combustion still follows legacy
O2 rather than a persistent canonical upper-zone inventory.

## STOP gate

| Check | Result |
|---|---|
| New F3.2a structural tests | PASS |
| All Phase 3 structural tests | `305 PASS` |
| Direct Godot fixture | PASS |
| Physics coherence | `9 PASS / 15 CTRL / 5 WARN / 0 FAIL` |
| ILV coherence | `15 PASS / 14 CTRL / 0 FAIL` |
| Gap inventory | `348/353`, five VALID_GAP, unchanged |
| Selected coherence/guardrail pytest | `287 PASS / 1 expected R2-1 failure` |
| Validation guardrails | only R2-1 because `sim/core` is uncommitted |
| Baselines, tolerances, official reports | unchanged |
| Legacy OFF/ON values | 115/115 columns byte-identical |

The initial direct fixture attempt crashed before script execution while Godot
rotated `user://logs`. All accepted Godot evidence used a unique workspace
`--log-file`; those runs completed with exit 0. The crash is infrastructure,
not a motor result.

## Limits and next gate

- No wind pressure term is included in F3.2a.
- Exterior inflow carries ambient O2 but no background CO2/pollutants yet.
- Other exterior mechanisms remain separate by design.
- Canonical state does not persist across timesteps.
- No canonical value is published to live room state or FED.

F3.2b must design and test persistent canonical step-to-step continuity for a
single-room/no-HVAC scope, including the O2 source seen by combustion. It must
remain default OFF and prove that Group A moves toward CFAST before any
authority flag can be considered. F3.3 Group C and HVAC-last ordering remain
unchanged.

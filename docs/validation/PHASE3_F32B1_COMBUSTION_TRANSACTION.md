# Phase 3+ F3.2b1 closed combustion shadow transaction

Date: 2026-07-18

## Decision

F3.2b1 closes with two distinct decisions:

- **GO for the passive closed combustion mechanism.** One canonical pre-step
  O2 decision now governs HRR, fuel, the O2 sink, generated species,
  convective heat and plume transport.
- **NO-GO for canonical room-state authority and Group A retirement.** The
  exterior-opening pressure transient and lower-zone collapse are still not
  physically acceptable.

The feature is default OFF. It does not write live `RoomModel` or `FireModel`
state, change FED, update baselines or alter legacy CSV output.

## Delivered contract

`phase3_canonical_combustion_shadow_enabled` implies the canonical,
exterior-boundary and persistent-shadow parents in the headless runner.

When enabled:

1. `CombustionSystem` snapshots the live fire before the legacy fire step.
2. A pure evaluator reads canonical pre-step upper/lower mass and O2 plus the
   persistent shadow fire state.
3. The evaluator chooses one O2 source zone, applies the extinction contract
   and derives one decision fraction.
4. HRR, fuel, O2, CO, CO2, HCN, smoke, irritants and convective heat use that
   same fraction. Plume entrainment uses the corresponding cube-root scale.
5. `Phase3ZoneMassSystem` stages those terms as one atomic multi-route bundle.
6. The accepted atomic fraction commits only the internal shadow fire state.

No term is reconstructed from independently mutated legacy output. No O2-only
throttle exists.

## Zone bootstrap and collapse

At ignition, an empty canonical upper zone cannot provide an O2 fraction. The
transaction therefore bootstraps from lower-zone O2 until upper gas mass
exists. Once upper mass exists, upper O2 is the source unless the configured
combustion mode explicitly selects lower O2.

If the lower zone later collapses to zero mass, combustion continues in the
upper zone but the lower-to-upper plume route is omitted. This prevents an
atomic rejection deadlock and keeps the route graph honest. It does not solve
the underlying degenerate-zone representation; that remains a blocker for
authority.

## Telemetry

The flag adds 27 CSV columns covering:

- source-zone selection and canonical/legacy O2 factors;
- legacy and accepted HRR;
- decision, atomic and effective fractions;
- requested/accepted O2, fuel, species, heat and plume mass;
- persistent fuel and retained-unburned state;
- zero-O2 flame detection;
- O2, energy and species transaction residuals.

The schema is emitted only while F3.2b1 is enabled. A short schema run produced
442 header fields and 442 values per row.

## Group A evidence

Scratch evidence is under `runs/phase3_f32b1/`; official reports were not
modified.

| Time | CFAST expected | Tolerance | Legacy upper O2 | F3.2b1 shadow upper O2 | Result |
|---:|---:|---:|---:|---:|---|
| 240 s | `0.085108` | `0.031` | `0.15951` | `0.10793` | PASS |
| 350 s | `0.065980` | `0.015` | `0.09819` | `0.07157` | PASS |
| 360 s | `0.064507` | `0.015` | `0.09345` | `0.07242` | PASS |

The three values pass the existing checks without changing expected values or
tolerances. Atomic fraction remains `1.0`, the zero-O2 flame flag remains zero,
and O2, energy, species and persistence residuals remain exactly zero.

Across 228 rows, all 115 shared legacy columns are identical between the
F3.2b0 control and F3.2b1. The feature is therefore passive with respect to
live physics.

## Authority blockers

The combustion loop is no longer the blocker. Two canonical representation
problems remain:

1. The lower zone reaches zero mass before the exterior opening. Continuing
   as a one-zone upper state is conservative, but not yet an approved
   two-zone transition.
2. Gauge pressure spans about `-1.04 kPa` to `+26.9 kPa`; the positive peak
   occurs after the window opens. The pre-opening maximum is still about
   `+2.82 kPa`. These magnitudes fail the realistic-pressure authority gate.

The closed single-room control also reaches about `+2.58 kPa`, confirming that
the pressure issue is not created by Group A validation data alone.

## Verification

| Check | Result |
|---|---|
| Direct Godot transaction fixture | PASS |
| Focused F3.2b0/b1 tests | `67 PASS` |
| Broad Phase 3 tests excluding known analyzer-tempfile failures | `332 PASS` |
| Physics coherence | `9 PASS / 15 CTRL / 5 WARN / 0 FAIL` |
| ILV coherence | `15 PASS / 14 CTRL / 0 FAIL` |
| Gap inventory | `348/353`, five VALID_GAP, unchanged |
| Legacy shared columns | `115/115` identical |
| Group A shadow checks | `3/3 PASS` |
| Transaction residuals | exact zero |
| Zero-O2 flame | absent |
| Realistic pressure | FAIL; authority NO-GO |

Guardrails are expected to report only R2-1 while `sim/core` is dirty. The
reference report timestamp is deliberately not refreshed before commit.

## Next gate: F3.2b2

F3.2b2 must diagnose and then correct the canonical exterior-opening pressure
relaxation and degenerate-zone transition without changing the accepted
combustion transaction. It must remain default OFF and conserve gas mass,
energy, O2 and all species atomically.

Group A remains in `VALID_GAP` until canonical authority passes that STOP gate.
Group C, HVAC, FED authority, baselines and tolerances remain out of scope.

### F3.2b2 outcome

F3.2b2 eliminated the exterior-opening pressure overshoot and recreated lower
conservatively on real fresh-air inflow. The mechanisms are passive GO, but
room-state authority remains NO-GO because pre-opening pressure and the early
one-zone transition still differ from the reference. See
`docs/validation/PHASE3_F32B2_PRESSURE_RELAXATION.md`.

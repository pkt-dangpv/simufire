# Phase 3+ F3.1c single-room thermal ownership

Date: 2026-07-17

## Decision

F3.1c is a **PARTIAL GO for passive flux ownership** and a **NO-GO for
canonical authority**.

The one-room control now gives explicit owners to every exact local physical
energy transfer exercised by the legacy thermal step and to the bulk-O2 debit
used when the lower zone is invalid. Combustion ownership reaches mask 7 for
all 36 fire snapshots, with zero semantic conflicts and zero unresolved
claims. Legacy output remains identical.

The transaction still reports `needs_flux_owner=1` because the remaining
mass and energy residual is introduced by lower-zone EOS projection and
reconciliation. That term is not a physical flux and must not be disguised as
one. F3.2 exterior pressure/leakage remains blocked.

## Canonical control

The scratch fixture contains exactly one room and no opening objects. HVAC,
ACH, leakage, pressure ODEs and exterior flow are disabled. It runs the
two-zone solver, Phase 3 diagnostics, the passive canonical shadow and the
energy budget for a 180 s fire.

The fixture and its outputs live under `runs/phase3_f31c/` and are intentionally
ignored. No official case, report, expected value, tolerance, CTRL envelope or
VALID_GAP classification changed.

## Ownership map

| Cause | Source | Destination | Quantity | Owner |
|---|---|---|---|---|
| `combustion_convective_heat` | chemical reservoir | upper | enthalpy | ThermalSystem |
| `combustion_o2_*_sink` | upper/lower gas | chemical reservoir | O2 | OxygenExchangeSystem |
| `plume_entrainment` | lower | upper | gas, enthalpy, O2 | ThermalSystem |
| `thermal_upper_to_lower` | upper | lower | enthalpy | ThermalSystem |
| `thermal_upper_radiative_loss` | upper | exterior reservoir | enthalpy | ThermalSystem |
| `thermal_upper_to_ambient` | upper | exterior reservoir | enthalpy | ThermalSystem |
| `thermal_wall_absorption` | upper | wall reservoir | enthalpy | ThermalSystem |
| `thermal_wall_emission` | wall reservoir | upper | enthalpy | ThermalSystem |
| `thermal_lower_decay` | lower | exterior reservoir | enthalpy | ThermalSystem |
| `thermal_lower_fresh_air_cooling` | lower | exterior reservoir | enthalpy | ThermalSystem |

The lower-invalid O2 path records the exact legacy bulk debit and splits it
between upper and lower zones by their geometric fractions. The two requests
sum to the existing debit; they do not alter O2 state.

## Flow

```text
pre-step snapshot
  -> exact physical request owners
       combustion heat and O2
       plume lower -> upper
       upper/lower/wall/ambient thermal transfers
  -> passive canonical transaction
  -> compare with legacy post-step state
       upper physical terms close
       lower EOS/projection residual remains visible
```

## Runtime evidence

| Metric | Before F3.1c | After F3.1c |
|---|---:|---:|
| CSV rows | 37 | 37 |
| Fire snapshots with ownership mask 7 | 22 | 36 |
| Snapshots with `needs_flux_owner=1` | 36 | 36 |
| Maximum mass residual | 0.03016636 kg | 0.03016636 kg |
| Maximum energy residual | 36.26236788 kJ | 6.94237481 kJ |
| Semantic conflicts | 0 | 0 |
| Unresolved claims | 0 | 0 |
| Shared legacy CSV cell differences | - | 0 |

At the final snapshot, upper mass and energy residuals are zero. The remaining
residual is entirely lower-zone (`-0.00289985 kg`, `0.17752121 kJ`). The peak
residual follows the same lower-zone projection/reconcile path.

## Verification

| Check | Result |
|---|---|
| Godot 4.6.3 headless parse | PASS |
| Focused F3.1c/contracts | 73 PASS |
| Broad Phase 3/two-zone tests | 306 PASS, 4 pre-existing structural failures |
| Physics coherence | 9 PASS / 15 CTRL / 5 WARN / 0 FAIL |
| ILV coherence | 15 PASS / 14 CTRL / 0 FAIL |
| Gap inventory | 348/353 required, 5 VALID_GAP, sync PASS |
| Guardrails | 9/10; only R2-1 because motor is dirty before STOP-gate commit |
| Full pytest | 905 PASS, 19 known failures |

The 19 full-suite failures are the 17 pre-existing structural failures, one
concurrent visual async-overlay test and the expected R2-1 dirty-motor
integration test. None exercises a changed F3.1c contract.

## Invariants

- All new requests are gated by the existing passive shadow flag.
- Requests are recorded from exact accepted values before the legacy mutation.
- No new authority flag was added.
- No request is inferred from a post-step state delta.
- Internal upper-to-lower energy is not classified as an exterior sink.
- Wall emission has the reverse direction of wall absorption.
- The legacy state and CSV values are unchanged.

## STOP conditions

Canonical authority remains forbidden while any of these is true:

- `needs_flux_owner` remains non-zero.
- Lower-zone projection/reconcile produces unexplained mass or energy.
- A proposed owner is derived from the residual it is meant to explain.
- A fix changes legacy output while the shadow is passive.

## Next phase

F3.1d must isolate the lower-zone EOS/projection transaction. It must identify
the exact pre-projection inventory, geometric/EOS target and reconcile delta,
then decide whether the canonical model should derive geometry from conserved
mass/energy or explicitly own a boundary reservoir. It may not label the
residual as transport and may not publish the shadow into `RoomModel`.

F3.2 starts only after a one-room control reaches mask 7 and
`needs_flux_owner=0` with bounded residuals and unchanged legacy output.

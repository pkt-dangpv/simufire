# Phase 3+ F3.2b4 pressure source and boundary equivalence

Date: 2026-07-19

## Scope

F3.2b4 is a diagnostic-only gate. It explains why the persistent canonical
two-zone shadow still differs from CFAST after F3.2b3 corrected plume geometry.
It does not change motor code, legacy output, expected values, tolerances,
official reports or VALID_GAP classification.

All experiments used Godot 4.7.1, the accepted F3.2b3 canonical plume stack
and isolated output under `runs/phase3_f32b4/`.

## Exact pressure decomposition

The canonical EOS is:

```text
P_abs = R_model / V * (m_upper * T_upper + m_lower * T_lower)
```

With sensible energy referenced to 20 C, gauge pressure decomposes exactly
into a total-mass term and a total-sensible-energy term. Pressure agreement is
therefore insufficient when those two terms are individually wrong and cancel.

Representative baseline values are:

| Time | Canonical pressure | Mass term | Energy term | CFAST pressure |
|---:|---:|---:|---:|---:|
| 100 s | +324 Pa | -5,767 Pa | +6,091 Pa | +692 Pa |
| 160 s | +1,812 Pa | -19,371 Pa | +21,183 Pa | +1,061 Pa |
| 240 s | +734 Pa | -42,329 Pa | +43,064 Pa | +13 Pa |
| 350 s | -341 Pa | -33,279 Pa | +32,938 Pa | +167 Pa |

At 160 s SimuFire retains about 11.10 kg more gas than CFAST while carrying
about 3.05 MJ less sensible energy. The apparently close pressure is a
cancellation, not state equivalence. At 240 s the signs reverse: SimuFire has
3.63 kg too little gas and about 1.27 MJ too much energy.

## One-cause experiments

The matrix changed only declared CFAST-equivalence candidates: radiative
fraction 0.35 instead of 0.70, leakage area 0.00905 m2 instead of 0.005 m2,
and the concrete wall properties declared by the CFAST input.

| Experiment | Pressure RMSE | Mass RMSE | Energy RMSE | Upper-T RMSE | Lower-T RMSE | First thermal inversion |
|---|---:|---:|---:|---:|---:|---:|
| Baseline | 507 Pa | 8.09 kg | 2,311 kJ | 70.5 C | 93.2 C | 313 s |
| Radiation only | 2,867 Pa | 5.48 kg | 1,569 kJ | 142.2 C | 164.3 C | 290 s |
| Leakage only | 598 Pa | 8.20 kg | 2,454 kJ | 83.0 C | 59.7 C | none by 360 s |
| Radiation + leakage | 449 Pa | 7.42 kg | 2,212 kJ | 223.2 C | 102.5 C | 350 s |
| Concrete only | 610 Pa | 11.05 kg | 3,261 kJ | 98.4 C | 58.2 C | 300 s |
| All three | 444 Pa | 6.23 kg | 1,850 kJ | 73.7 C | 77.6 C | 310 s |

The full combination slightly improves pressure RMSE but still produces a
268 C lower layer at 350 s, versus 66.5 C in CFAST. Radiation-only produces a
496 C lower layer. No isolated input-equivalence change closes pressure,
mass, energy, interface and both zone temperatures together. These values
must not be promoted as per-case tuning.

## Root cause

F3.2b3 fixed one cross-state contract for plume mass. The thermal loss path
still has the same class of mismatch:

1. `ThermalSystem` calculates upper-to-lower, upper-to-ambient and wall heat
   requests from legacy room temperatures, masses and wall state.
2. Those requests are then applied to the persistent canonical reservoirs.
3. The canonical lower zone becomes much smaller and hotter than the legacy
   lower zone, so the legacy temperature gradient is no longer valid for it.
4. Heat continues to flow upper-to-lower even after the canonical lower zone
   is hotter than the canonical upper zone.

At 350 s in the baseline, legacy upper/lower temperatures are approximately
149.9/34.2 C, while canonical temperatures are 150.9/309.1 C. Nevertheless,
the shadow receives another 0.7607 kJ upper-to-lower request in that physics
step. Approximately 4.63 MJ is requested in that direction after the first
canonical inversion at 313 s.

This is a state-contract error, not a pressure-cap problem. Internal energy
redistribution does not change total room pressure directly, but it corrupts
zone temperature, interface, plume geometry and O2 residence, and prevents
the canonical state from becoming authoritative.

## STOP gate

| Item | Result |
|---|---|
| Motor or production code changed | No |
| Baselines, tolerances or gaps changed | No |
| Official reports changed | No |
| Six isolated Godot 4.7.1 runs | PASS |
| Canonical volume and transaction closure | Preserved |
| Pressure source/boundary authority | NO-GO |
| Group A retirement | NO-GO |

Decision: **diagnostic GO, canonical authority NO-GO**.

## Next phase

F3.2b5 must address canonical thermal ownership before another pressure
authority attempt:

1. F3.2b5a: pure canonical upper/lower heat-transfer preview, derived from
   canonical pre-step mass and temperature. It must stop or reverse transfer
   according to the canonical gradient and conserve total gas energy exactly.
2. F3.2b5b: canonical ambient and wall exchange preview with an explicit wall
   reservoir; no request may be calculated from legacy gas state and applied
   to canonical state.
3. F3.2b5c: repeat the mass/energy/pressure equivalence matrix and independent
   no-fire, sealed-fire and exterior-leak controls.

All phases remain default OFF and shadow-only. No state may be published to
`RoomModel` until mass, energy, temperature ordering, interface and pressure
are simultaneously credible.

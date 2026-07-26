# Phase 3+ F3.3v3d pressure inventory attribution

Date: 2026-07-26

## Decision

F3.3v3d is **diagnostic GO** and **NO-GO for pressure, leakage-area or
relaxation tuning**.

The canonical ideal-gas equation and the cumulative mass/enthalpy residence
ledgers reconstruct every published R0 pressure checkpoint to less than
`2.8e-5 Pa`. The negative pressure is therefore not a missing ledger term or
an EOS implementation error.

The read-only analyzer is:

```text
scripts/simulation/analyze_phase3_f33v3d_pressure_inventory.py
```

No motor, scenario, official report, expected value, tolerance, CTRL,
VALID_GAP, FED, HVAC or visual path changed.

## Exact pressure reconstruction

The shadow thermodynamic pressure is:

```text
p_abs = R_model / V * (T_ref * m_total + E_sensible / cp)
```

For every residence family the corresponding pressure contribution is:

```text
delta_p_family =
    R_model / V
    * (T_ref * delta_m_family + delta_E_family / cp)
```

The analyzer verifies both independent closures:

1. observed upper/lower mass and energy reproduce the reported pressure;
2. initial inventory plus every cumulative owner reproduces the same pressure.

| Candidate | Maximum EOS residual | Maximum owner residual |
|---|---:|---:|
| Unfiltered fire growth | < `2.8e-5 Pa` | < `2.8e-5 Pa` |
| Filtered fire growth | < `2.6e-5 Pa` | < `2.6e-5 Pa` |

The residence family `other` is also resolved. At all checkpoints it has zero
net mass and its enthalpy is exactly the negative of
`phase3_shadow_multisurface_cumulative_gas_exchange_kj`. It is therefore
reported as `multisurface`, not left as an unknown owner.

## First sign reversal

CFAST R0 remains at `+60.35 Pa` at 120 s. The current unfiltered candidate
reaches:

| Stage at 120 s | Pressure |
|---|---:|
| Before interior-pressure correction | `-407.17 Pa` |
| Predicted after interior-pressure correction | `-83.17 Pa` |
| Before exterior-pressure correction | `-46.01 Pa` |
| Final canonical pressure | `-41.32 Pa` |

The negative sign exists **before** either pressure corrector. Both correctors
then move the current candidate toward ambient. They do not create this first
sign error.

The 110-120 s pressure change decomposes as:

| Owner | Pressure contribution |
|---|---:|
| Combustion energy | `+11701.4 Pa` |
| Multisurface gas-energy loss | `-7275.8 Pa` |
| Interior-opening mass and enthalpy | `-3489.8 Pa` |
| Interior-pressure routing | `-869.6 Pa` |
| Exterior routing | `-199.6 Pa` |
| Net reported change | `-133.2 Pa` |

This is a near-cancellation of terms two orders of magnitude larger than the
result. No single owner independently explains the crossing:

- `multisurface` is the largest negative energy owner;
- `interior_opening` is the largest negative inventory-routing owner;
- together with the smaller routing terms they exceed combustion by only
  about `133 Pa` in this window.

At 120 s the cumulative owner inventory also closes exactly:

| Cumulative owner | Pressure contribution |
|---|---:|
| Combustion | `+78238.8 Pa` |
| Multisurface | `-38479.0 Pa` |
| Interior opening | `-18204.9 Pa` |
| Interior pressure | `-11063.2 Pa` |
| Exterior | `-10533.0 Pa` |
| Total | `-41.3 Pa` |

## Filtered control

The filtered candidate changes the timing but not the owner order:

| Candidate | CFAST/SF sign-mismatch checkpoints |
|---|---|
| Unfiltered | 120, 130, 140, 180 s |
| Filtered | 120, 150, 170, 180 s |

At its first mismatch, the filtered candidate is already at `-1389.71 Pa`
before the interior-pressure solver. That solver then moves to
`-1420.79 Pa`, while the exterior solver restores part of the error.

This does not make the pressure solver the source of the negative sign: the
sign is already wrong on entry. It does show strong state sensitivity in the
feedback loop. Tuning pressure relaxation against one candidate could move
the oscillation to another checkpoint rather than repair its upstream budget.

## STOP gate

| Check | Result |
|---|---|
| Observed inventory reproduces EOS pressure | PASS |
| Initial inventory plus owners reproduces pressure | PASS |
| `other` identified as multisurface exchange | PASS |
| First sign error located before pressure solvers | PASS |
| Primary energy sink identified | multisurface |
| Primary routing sink identified | interior opening |
| Filtered/unfiltered owner order | consistent |
| Area-only leakage experiment | NO-GO |
| Pressure-relaxation tuning | NO-GO |
| Motor/cases/reports/baselines | unchanged |

## Next gate: F3.3v3e

There is not yet a justified motor patch. F3.3v3e must compare the two owners
that dominate the cancellation with CFAST:

1. cumulative gas-to-surface energy and wall storage;
2. interior-opening net mass and transported sensible enthalpy;
3. their pressure-equivalent contributions over 10-second windows.

The committed CFAST wall temperatures, zone/slab exports, vent flows and local
CFAST source are sufficient to determine whether the first authority gap is
surface energy loss, doorway enthalpy, or both.

Do not change pressure relaxation, leakage area/topology, HRR, multisurface
coefficients or doorway flow coefficients until F3.3v3e assigns that
cross-model correspondence.

# Phase 3+ F3.3e - Coupled convective-source/plume Qc design

Date: 2026-07-22

## Decision

**Design GO for one future default-OFF runtime experiment. No motor physics,
case, report, baseline, tolerance, gap or authority change is authorized by
this document.**

The current canonical shadow has three independent inputs for one physical
fire source:

1. `accepted_hrr_kw`, decided by the canonical combustion/O2 transaction;
2. convective energy, derived in `ThermalSystem` from `1 - chi_rad`;
3. plume entrainment, derived separately from
   `plume_mccaffrey_qc_fraction` and then scaled after evaluation.

F3.3d and F3.3d2 proved that changing energy or plume mass independently
cannot close Group C. F3.3e finds a more fundamental issue: the canonical
plume does not implement the Heskestad virtual origin. It subtracts flame
length from the interface instead. Those quantities use different
coefficients and are not interchangeable.

The next candidate must therefore use one accepted total HRR and one
convective HRR (`Qc`) for both energy and plume, and it must evaluate the
complete Heskestad expression from the virtual origin before any atomic
inventory limit is applied.

## Authoritative contract

The proposed shadow-only contract is:

```text
Q_accepted = canonical combustion HRR after fuel and O2 acceptance [kW]
chi_rad    = effective radiative fraction evaluated from the same canonical O2 state
Qc         = Q_accepted * clamp(1 - chi_rad, 0, 0.90) [kW]

convective upper-zone source = Qc * dt [kJ]

z0 = -1.02 * D + 0.083 * Q_accepted^(2/5) [m]
z_eff = max(0.1, interface_height - fire_base_height - z0) [m]

plume height term = 0.071 * Qc^(1/3) * z_eff^(5/3) [kg/s]
plume source term = 0.071 * 0.026 * Qc [kg/s]
plume total       = height term + source term
```

`Q_accepted` is upstream of both routes. O2 throttling is applied exactly
once when that value is decided. There is no downstream `heat_scale` or
common `plume_scale` in the coupled candidate. The atomic bundle may still
reduce the completed routes together when an actual inventory limit is hit.

This follows the Heskestad form documented in the NIST CFAST technical guide:

```text
m_dot = 0.071 * Qc^(1/3) * (z - z0)^(5/3)
        * (1 + 0.026 * Qc^(2/3) * (z - z0)^(-5/3))
```

Expanding the parenthesis gives the height term plus a linear source term of
`0.001846 * Qc`. F3.3d2 used `0.0018 * Qc`; that 2.6% coefficient difference
is minor. The binding error is the geometry and authority split.

Primary reference: NIST CFAST Version 7 Technical Reference Guide,
NIST TN 1889v1, plume entrainment section:
https://doi.org/10.6028/NIST.TN.1889v1

## Current implementation mismatch

`ThermalSystem.preview_phase3_canonical_plume_flux()` currently computes:

```text
Qc = room.hrr_kw * plume_mccaffrey_qc_fraction
flame_length = 0.235 * Q^(2/5) - 1.02 * D
z_eff = interface - flame_length
```

The virtual origin is instead:

```text
z0 = 0.083 * Q^(2/5) - 1.02 * D
z_eff = interface - z0
```

Using `0.235` in place of `0.083` changes the sign and magnitude of the
effective plume height. The current post-evaluation
`plume_scale = accepted_fraction^(1/3)` is only algebraically valid for the
height term. It is wrong for the linear source term, which must scale with
`accepted_fraction` through `Qc` itself.

The Group C inputs contain a second correspondence mismatch:

| Input | CFAST | SimuFire case |
|---|---:|---:|
| Radiative fraction | 0.35 | 0.70 |
| Convective fraction | 0.65 | 0.30 |
| Maximum fire area | 0.3015 m2 | not represented |
| Equivalent fire diameter | 0.6196 m | 3.5 m override |
| Full-fire flame height | 1.669 m | 0 m after clamp |

The repository's override registry classifies both radiation fraction and
fire diameter as physical inputs. The Group C values were inherited as
calibration values; they do not describe the CFAST fire used as reference.
No official case value is changed in this phase.

## Direct CFAST equation check

Using CFAST's own `Q=300 kW`, `Qc=195 kW`, `D=0.6196 m` and exported layer
height, the complete Heskestad equation reproduces the exported CFAST plume
flow without tuning:

| t | CFAST interface | Predicted plume | CFAST plume | Error |
|---:|---:|---:|---:|---:|
| 180 s | 0.7357 m | 0.5143 kg/s | 0.5027 kg/s | +2.3% |
| 300 s | 0.7731 m | 0.5320 kg/s | 0.5283 kg/s | +0.7% |
| 590 s | 0.8079 m | 0.5492 kg/s | 0.5521 kg/s | -0.5% |

This is the strongest available evidence that the formula and input mapping,
not another opening multiplier, own the remaining plume correspondence gap.

## Window budgets and prediction

Energy values are exact integrations of accepted HRR. Plume values for the
two proposed Qc fractions are an **open-loop first iteration** over the F3.3d1
baseline interface trajectory. They are not runtime predictions: a coupled
run will move the interface and feed that change back into entrainment.

| Window | CFAST Qc energy | SF Qc at 0.30 | SF Qc at 0.65 |
|---|---:|---:|---:|
| 0-180 s | 24.872 MJ | 11.014 MJ | 23.863 MJ |
| 180-300 s | 23.400 MJ | 10.114 MJ | 21.913 MJ |
| 300-590 s | 56.550 MJ | 19.030 MJ | 41.231 MJ |

| Window | CFAST plume | Current accepted plume | Correct equation, Qc=0.30Q | Correct equation, Qc=0.65Q |
|---|---:|---:|---:|---:|
| 0-180 s | 97.716 kg | 70.766 kg | 85.636 kg | 128.555 kg |
| 180-300 s | 62.244 kg | 43.935 kg | 52.522 kg | 84.255 kg |
| 300-590 s | 157.101 kg | 100.887 kg | 123.798 kg | 190.849 kg |

The open-loop `Qc=0.65Q` plume overshoot is expected to reduce when the extra
entrainment lowers the interface. That feedback is exactly what the rejected
independent controls could not represent. It must be measured, not estimated
by adding the old `chi_rad=0.35` and F3.3d2 deltas.

The late energy row also sets a hard boundary: SimuFire accepts only
63.42 MJ total HRR from 300-590 s, versus CFAST's prescribed 87.00 MJ. Even
with the correct 65% split, only 41.23 MJ is available. A plume correction
must not manufacture the missing 15.32 MJ. Late residual error belongs to the
canonical O2/combustion authority and requires a separate gate if F3.3e does
not improve the 590 s checkpoint sufficiently.

## Options

| Option | Verdict | Reason |
|---|---|---|
| Keep independent `chi_rad` and plume Qc fraction | NO-GO | Two authorities can request incompatible mass and energy. |
| Add only the source term | NO-GO | F3.3d2 improved mass but cooled both temperature checkpoints. |
| Change only `chi_rad` | NO-GO | Existing control overheats early because plume mass/geometry remain wrong. |
| Force CFAST's 300 kW after O2 throttle | NO-GO | Breaks the zero-O2 flame invariant and hides the combustion owner. |
| Tune plume/opening coefficients | NO-GO | The NIST equation already reproduces CFAST plume within 2.3%. |
| Unified accepted Q/Qc plus correct virtual origin | GO for default-OFF experiment | One dimensional source, correct equation, exact ledgers remain available. |

## Future implementation plan: F3.3e1

No implementation is included here. The authorized next experiment should be
small and reversible:

1. Add `phase3_coupled_qc_shadow_enabled=false`, requiring the complete
   canonical F3.3d1 stack.
2. Resolve and store once per room/step:
   `accepted_total_hrr_kw`, `effective_chi_rad`, `accepted_qc_kw`, fire
   diameter, `z0` and `z_eff`.
3. Build convective energy directly as `accepted_qc_kw * dt`.
4. Build both plume terms from the same accepted Q/Qc and virtual origin.
5. Feed already accepted heat and plume requests to the atomic bundle. Do not
   apply legacy `heat_scale` or `plume_scale` again.
6. Keep the existing lower-inventory cap and proportional lower enthalpy/O2
   payload. Keep mass and enthalpy residence ledgers exact.
7. Use a scratch Group C overlay with the physical CFAST inputs
   `chi_rad=0.35` and `D=0.6196 m`. Do not edit the official case during the
   experiment.

The current `FireModel` has no prescribed fire-area state. F3.3e1 may use the
existing physical diameter input for isolation. Dynamic fire area ownership
is separate debt and must be designed before this candidate can become a
general production authority.

## Runtime order and STOP gates

1. Structural tests and a direct Godot fixture for the three CFAST equation
   checkpoints above.
2. Group C 180 s scratch run. STOP if upper temperature, upper mass or
   interface moves farther from CFAST than baseline.
3. Group C 600 s scratch run only after the 180 s gate passes.
4. Compare all three mass and energy windows, exact ledgers, O2, pressure and
   opening flow. STOP before any case/report/baseline change.
5. Run Group A, closed single-room and two-room doorway controls only if both
   Group C temperature errors improve.

Acceptance requires:

- default OFF and exact shared-column invariance;
- direct fixture plume error <= 3% at 180/300/590 s;
- zero mass and enthalpy residuals within float tolerance;
- no zero-O2 flame, O2E1, D1, S1, FED or pressure regression;
- both Group C temperature checkpoints improve, not merely one;
- no new coefficient, opening retune, expected/tolerance update or CTRL
  reclassification.

Rollback if the candidate double-applies O2 acceptance, scales the linear
source term with a cube root, reads legacy `room.o2` after canonical O2 has
already decided HRR, or improves temperature by corrupting mass/energy
closure.

## STOP gate

| Check | Result |
|---|---|
| `sim/core` change in F3.3e design | none |
| Official case/report/baseline change | none |
| NIST equation mapped dimensionally | yes |
| CFAST plume reproduced without tuning | within 2.3% at all checkpoints |
| Three-window energy prediction | complete |
| Three-window open-loop plume prediction | complete and explicitly bounded |
| Independent old patches authorized | no |
| F3.3e1 default-OFF runtime experiment | design GO; separate STOP required |
| Canonical authority / Group C retirement | NO-GO |

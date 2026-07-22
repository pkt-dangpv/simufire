# Phase 3+ F3.3d - CFAST source/boundary correspondence

Date: 2026-07-21

## Decision

**Diagnostic GO. No physical coefficient change and no canonical authority are
authorized.**

The exact F3.3c1 enthalpy ledger closes, but its source and sink magnitudes do
not correspond one-for-one with CFAST. The largest explicit mismatch is the
combustion/radiation split. However, the existing `chi_rad=0.35` control proves
that correcting that split alone overheats the early layer because the
canonical upper-zone mass and volume are also too small.

The next target is F3.3d1: an exact, passive mass-residence ledger by accepted
route. It must select the owner of the upper/lower partition error before any
source, plume, wall or opening physics changes.

## Inputs and method

The comparison uses:

- CFAST `cfast_corridor_chain_compartments.csv` for actual convective HRR;
- CFAST `cfast_corridor_chain_zone.csv` for layer state and doorway slabs;
- F3.3c1 `runs/phase3_f33c1/corridor_on/sim_log.csv` for accepted canonical
  energy by route;
- the existing `chi_rad=0.35` scratch run in
  `runs/phase3_f33c/chi035_f33b` as a non-authoritative control.

CFAST layer sensible energy is reconstructed with the same convention as the
canonical shadow:

```text
E_zone = rho_zone * V_zone * 1.0 kJ/(kg K) * (T_zone - 20 C)
```

CFAST doorway enthalpy is integrated directly from its signed horizontal-vent
slabs:

```text
Q_door,R0 = integral(sum(mdot_slab * (T_source_slab - 293.15 K))) dt
```

Positive slab flow is R0 to Hall and negative flow is Hall to R0. The exported
source temperature verifies the sign: at 180 s the positive upper slab is
432.97 K, equal to R0 upper gas, while negative slabs match Hall gas.

The CFAST wall CSV exports surface temperatures, not heat flux. Therefore the
remaining gas boundary sink is bounded by exact closure:

```text
Q_other_boundary = Q_convective_source - Q_door_net_out - delta(E_upper + E_lower)
```

It includes wall transfer and exterior leakage and is not split further.
SimuFire's corresponding boundary term is the exact sum of wall, ambient,
exterior pressure and exterior counterflow families. Its doorway term is the
sum of inter-zone heat, F3.3a opening flow, F3.3b pressure flow and parcels.

CFAST exports `0..590 s` at 10 s intervals for a nominal 600 s run. The final
window is consequently reported as `300-590 s`; no synthetic 600 s row is
invented.

## Window budgets

All values are MJ for R0. Positive door/boundary values are net losses from
the room.

| Window | CFAST source | SF source | SF/CF | CFAST door | SF door | SF/CF | CFAST other boundary | SF boundary | SF/CF | CFAST dE | SF dE |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 0-180 | 24.872 | 11.015 | 44.3% | 6.302 | 3.802 | 60.3% | 14.163 | 4.371 | 30.9% | +4.407 | +2.842 |
| 180-300 | 23.400 | 10.114 | 43.2% | 6.766 | 4.640 | 68.6% | 16.389 | 5.418 | 33.1% | +0.244 | +0.057 |
| 300-590 | 56.550 | 19.026 | 33.6% | 17.117 | 8.671 | 50.7% | 39.296 | 10.995 | 28.0% | +0.137 | -0.639 |

Both budgets close. SimuFire's F3.3c1 room residual remains exactly `0.0 kJ`.
Its door and non-door losses are lower than CFAST in absolute terms, so an
excessive absolute wall or doorway sink does not explain the late energy
deficit.

Relative to its much smaller source, SimuFire does export more through the
door: 34-46% of source energy versus 25-30% in CFAST. That is a secondary
coupling difference, not evidence for another doorway multiplier.

## Source decomposition

CFAST uses `RADIATIVE_FRACTION=0.35`, hence 65% convective HRR. The SimuFire
case explicitly uses `hrr_chi_rad_normal=0.7` and
`hrr_chi_rad_low_o2=0.7`, hence only 30% convective heat.

| Window | CFAST actual HRR | SF accepted HRR before radiation | SF/CF | SF convective energy if chi_rad=0.35 |
|---|---:|---:|---:|---:|
| 0-180 | 38.264 MJ | 36.718 MJ | 96.0% | 23.867 MJ |
| 180-300 | 36.000 MJ | 33.713 MJ | 93.6% | 21.913 MJ |
| 300-590 | 87.000 MJ | 63.421 MJ | 72.9% | 41.224 MJ |

The early source difference is almost entirely the radiation split. After
300 s it also includes SimuFire O2 throttling: HRR falls from 300 kW to about
186 kW by 590 s while the prescribed CFAST fire remains at 300 kW.

This mismatch is real, but it is not independently actionable. The existing
`chi_rad=0.35` run matches late temperature and badly overshoots early
temperature.

## State and partition evidence

The decisive comparison is the CFAST-aligned radiation control. `SF base` is
the F3.3c1 canonical state; `SF chi035` is the scratch control.

| t | State | CFAST | SF base | SF chi035 |
|---:|---|---:|---:|---:|
| 180 | upper mass (kg) | 26.943 | 22.921 | 18.432 |
| 180 | lower mass (kg) | 15.406 | 25.000 | 23.889 |
| 180 | upper energy (MJ) | 3.767 | 2.423 | 3.656 |
| 180 | upper temperature (C) | 159.82 | 125.70 | 218.35 |
| 180 | interface (m) | 0.736 | 1.101 | 1.110 |
| 590 | upper mass (kg) | 25.249 | 23.794 | 19.491 |
| 590 | lower mass (kg) | 15.794 | 25.802 | 25.507 |
| 590 | upper energy (MJ) | 3.757 | 1.845 | 2.863 |
| 590 | upper temperature (C) | 168.80 | 97.53 | 166.88 |
| 590 | interface (m) | 0.808 | 1.140 | 1.179 |

At 180 s, the CFAST-aligned source puts upper energy within 3% of CFAST, but
upper mass is 32% low and the interface is 0.37 m too high. The same energy is
concentrated in too little gas, producing the 218 C overshoot. At 590 s, the
near-perfect temperature hides simultaneous upper-energy and upper-mass
deficits of about 24% and 23%.

The plume signal is consistent with this partition error. At representative
times CFAST entrains about `0.50-0.59 kg/s`; the accepted canonical plume is
about `0.34-0.46 kg/s` using the validation step of `1/12 s`. This is not yet
an exact cumulative attribution, which is why F3.3d1 is required.

## Hypothesis verdicts

| Hypothesis | Verdict | Evidence |
|---|---|---|
| A: source/radiation | Real but not independently safe | The 30% versus 65% convective split dominates source magnitude; scalar correction trades the late deficit for an early overshoot. |
| B: wall/ambient loss | Rejected as primary cause | SimuFire non-door boundary loss is only 28-33% of CFAST in absolute terms. Lowering it would worsen source/state inconsistency. |
| C: doorway enthalpy | Rejected as primary cause | SimuFire net doorway loss is only 51-69% of CFAST absolute loss. Its larger source-normalized share is secondary and does not justify a coefficient change. |
| D: upper/lower mass partition | Selected next owner | CFAST-aligned source nearly matches early upper energy but leaves 32% too little upper mass and a 0.37 m high interface. |

No single A, B or C coefficient satisfies the existing rule that both the
180 s and late errors must improve without corrupting mass/energy state.

## F3.3d1 next gate

F3.3d1 is instrumentation, not a plume fix. Add a default-OFF cumulative
accepted mass-residence ledger parallel to F3.3c1, with upper/lower in/out for
at least:

- plume entrainment;
- interior opening and signed pressure transport;
- exterior pressure/counterflow;
- delayed parcels;
- zone collapse/reconcile and any legacy route;
- unclassified accepted mass.

It must export initial, expected and observed upper/lower gas mass plus exact
zone, room and building residuals. It should also accumulate chemical HRR
before the radiative split and accepted convective energy so radiation and O2
throttling remain independently measurable.

The comparison set is:

1. Group C baseline (`chi_rad=0.7`);
2. Group C scratch control (`chi_rad=0.35`);
3. Group A `cfast_r0_window_360` as the exterior-boundary control;
4. one closed one-room fixture and one two-room doorway fixture.

### F3.3d1 acceptance

- flag default OFF and exact OFF/ON invariance for all shared columns;
- zero upper/lower/room/building mass residual within float tolerance;
- CFAST slab mass and plume comparisons over the same three windows;
- no motor authority, case change, report regeneration, baseline update,
  tolerance change, gap retirement or CTRL reclassification;
- STOP before changing plume entrainment, radiation split or opening flow.

Rollback if the ledger derives accepted flux from post-mutation state, double
counts an existing owner, or cannot distinguish internal upper/lower transfer
from room/building boundary mass.

## STOP gate

| Check | Result |
|---|---|
| `sim/core` changes | None |
| Case/report/baseline changes | None |
| F3.3c1 residual | `0.0 kJ`, unchanged evidence |
| CFAST source integration | Direct (`HRRC_1`) |
| CFAST doorway enthalpy | Direct signed slab integration |
| CFAST wall/leak split | Not exported; bounded together by closure |
| Scalar source change | NO-GO |
| Wall or doorway coefficient change | NO-GO |
| F3.3d1 passive mass ledger | GO as next target |
| Group C retirement / canonical authority | NO-GO |


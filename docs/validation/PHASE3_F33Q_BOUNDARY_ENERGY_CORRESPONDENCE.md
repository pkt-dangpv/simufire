# Phase 3+ F3.3q boundary-energy correspondence

Date: 2026-07-24

Decision: **diagnostic GO; motor candidate remains NO-GO**.

## Purpose

F3.3q explains the upper-temperature NO-GO from F3.3p1 without changing
physics. It reconstructs the R0 energy balance over `0-60`, `60-120` and
`120-180 s` using:

- the valid corrected F3.3p1 shadow run;
- committed CFAST compartment, zone and wall exports;
- canonical enthalpy-residence ledgers.

The reusable read-only analyzer is:

```text
scripts/simulation/analyze_phase3_f33q_boundary_energy.py
```

Scratch JSON is written to:

```text
runs/phase3_f33q_boundary_energy.json
```

No motor behavior, official case/report, expected value, tolerance, gap,
CTRL, FED or HVAC path changes in F3.3q.

## Shared balance

For each time window the CFAST boundary sink is inferred as:

```text
boundary sink =
    convective fire source
  + signed net interior-doorway enthalpy
  - change in room sensible energy
```

The inferred term includes CFAST surface transfer and its small exterior leak.
The canonical comparison uses the same equation and independently sums the
accepted `wall`, `ambient`, `exterior` and `exterior_counterflow` residence
families.

The canonical inferred and observed sinks agree to numerical precision.
Plume and inter-zone heat are internal transfers and cancel at room level.

## Window results

| Window | CFAST inferred sink | Sim observed sink | Sim shortfall |
|---|---:|---:|---:|
| 0-60 s | 0.959 MJ | 0.309 MJ | 0.650 MJ |
| 60-120 s | 5.657 MJ | 3.837 MJ | 1.820 MJ |
| 120-180 s | 7.547 MJ | 6.603 MJ | 0.944 MJ |
| **0-180 s** | **14.163 MJ** | **10.749 MJ** | **3.414 MJ** |

The canonical sink components are:

| Window | Wall reservoir | Direct ambient | Exterior |
|---|---:|---:|---:|
| 0-60 s | 0.076 MJ | 0.205 MJ | 0.028 MJ |
| 60-120 s | 1.459 MJ | 1.789 MJ | 0.588 MJ |
| 120-180 s | 3.329 MJ | 2.823 MJ | 0.451 MJ |
| **0-180 s** | **4.864 MJ** | **4.817 MJ** | **1.067 MJ** |

F3.3p1 already supplies `24.020 MJ` canonical combustion heat versus about
`24.872 MJ` in CFAST. The remaining upper-temperature error is therefore not
primarily another Qc deficit. The canonical room removes about `3.41 MJ`
less energy through its boundary contract.

## Surface-state evidence

| t | Sim single wall | CFAST ceiling | CFAST upper wall | CFAST lower wall | CFAST floor |
|---:|---:|---:|---:|---:|---:|
| 60 s | 20.05 C | 26.68 C | 21.55 C | 21.58 C | 22.89 C |
| 120 s | 20.95 C | 43.06 C | 27.83 C | 25.98 C | 29.46 C |
| 180 s | 23.01 C | 52.38 C | 32.89 C | 29.22 C | 33.79 C |

CFAST resolves four surface classes with concrete conduction. The canonical
shadow has one lumped wall reservoir and a separate direct-ambient decay.
Those are not equivalent boundary models.

## Contract mismatch

The CFAST input explicitly declares for every R0 surface:

```text
conductivity = 1.75 W/(m K)
density = 2200 kg/m3
specific heat = 1.0 kJ/(kg K)
thickness = 0.15 m
emissivity = 0.94
```

The SimuFire validation case supplies none of the corresponding room material
fields. `RoomModel` therefore remains in `lumped fallback` mode.

There is also a geometric mismatch:

```text
R0 floor area                         = 20.0 m2
full floor + ceiling + wall envelope = 83.2 m2
canonical wall_area_m2               = 2 * floor = 40.0 m2
canonical / full envelope            = 0.481
```

`preview_phase3_canonical_wall_ambient_flux()` computes upper/lower exposure
fractions from the full enclosure, but conductance and heat capacity are
scaled by `wall_area_m2 = 2 * floor_area`. Normalizing the exposure fractions
does not restore the missing area magnitude.

The direct `upper/lower -> ambient` decay partially compensates this
under-represented wall reservoir, but it is not homologous to CFAST surface
storage/conduction. Tuning that decay would hide the ownership mismatch.

## Owner assignment

| Finding | Owner | Verdict |
|---|---|---|
| Accepted combustion source nearly matches | coupled Qc contract | not the remaining primary error |
| Canonical room stores too much energy | boundary-energy contract | primary thermal owner |
| CFAST concrete absent from case mapping | validation input correspondence | first mismatch to isolate |
| Canonical wall area is 48.1% of enclosure | wall context geometry | second structural mismatch |
| Direct ambient decay supplies 4.82 MJ | legacy-compatible boundary surrogate | do not tune |
| Canonical balance residual | atomic ledger | zero; not bookkeeping |

## Next phase: F3.3r0

F3.3r0 is an **existing-path material-correspondence scratch control**, not
a motor patch.

1. Copy `cfast_corridor_chain.json` to scratch.
2. Add the exact concrete properties to rooms 0-2 through existing
   `room_overrides`.
3. Preserve F3.3n routing and the valid F3.3p1 shadow source in the scratch
   experiment only.
4. Keep the current `40 m2` canonical wall-area contract unchanged so material
   and area are not combined.
5. Run OFF equivalence and the 180 s STOP.
6. Compare source, storage, doorway enthalpy, wall/ambient/exterior sinks and
   surface temperature.

Only if material mode moves the boundary sink in the correct direction
without overcooling should F3.3r1 design a default-OFF full-enclosure-area
contract. Neither stage may update the official case or validation baseline
before the physical correspondence gate passes.

## STOP gate

| Check | Result |
|---|---|
| Analyzer tests | 6/6 PASS |
| Canonical inferred vs observed sink | closes |
| Motor behavior changed | no |
| Official validation artifact changed | no |
| Expected/tolerance/gap changed | no |
| Missing boundary sink identified | 3.414 MJ over 0-180 s |
| First mismatch identified | concrete material mapping absent |
| Second mismatch identified | canonical area 40.0 vs 83.2 m2 |
| Authority / Group C retirement | NO-GO |

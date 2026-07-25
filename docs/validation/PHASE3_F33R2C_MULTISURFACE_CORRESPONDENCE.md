# Phase 3+ F3.3r2c multi-surface correspondence

Date: 2026-07-25

Status: telemetry GO, physical correspondence NO-GO.

## Scope

F3.3r2c tested the default-OFF canonical four-surface shadow against the
committed CFAST corridor reference. The experiment remained scratch-only:

- no official case or report changed;
- no expected value, tolerance, CTRL or VALID_GAP changed;
- no FED, HVAC or visual path changed;
- the legacy CSV values remained invariant with the shadow enabled.

The experiment stopped at the mandatory 180 s gate. No 300 or 600 s run was
made.

## Reproducible scratch matrix

`scripts/simulation/prepare_phase3_f33r2c_cases.py` creates only ignored
scratch cases under `runs/phase3_f33r2c/cases`:

- corridor OFF;
- corridor with the independent-compartment CFAST boundary;
- corridor with physical exterior/inter-room wall fractions;
- corridor with interior openings closed;
- sealed material fixture.

The source pair is the previously documented CFAST correspondence input:

```text
hrr_chi_rad_normal = 0.35
hrr_chi_rad_low_o2 = 0.35
plume_fire_diameter_m = 0.6196
```

The surface material is the CFAST concrete correspondence:

```text
k = 0.00175 kW/(m K)
rho = 2200 kg/m3
cp = 1.0 kJ/(kg K)
thickness = 0.15 m
```

## Added observability

The canonical shadow now exports cumulative, resettable correspondence data:

- gas-to-surface exchange;
- accepted fire radiation;
- exterior removal;
- combined and solver residuals;
- per-surface area, stored energy and inner/middle/outer temperatures;
- per-surface cumulative gas exchange, fire radiation and exterior removal.

These fields are present only in the opt-in canonical shadow CSV schema. No
physical equation or official CSV schema changed.

## Mandatory 180 s STOP gate

| Gate | SimuFire | CFAST | Limit | Result |
|---|---:|---:|---:|---|
| R0 total surface storage | 23.472 MJ | 26.993 MJ | +/-15% | PASS |
| R0 gas-driven storage | 14.347 MJ | 13.601 MJ | +/-10% | PASS |
| R0 accepted fire radiation | 9.124 MJ | 13.392 MJ | +/-2% | FAIL |
| Cumulative energy residual | -0.00000008 kJ | 0 | 0.0001 kJ | PASS |
| R0 upper temperature | 115.87 C | 159.82 C | 31 C | FAIL |
| R0 lower temperature | 25.88 C | 61.56 C | 10 C | FAIL |
| Hall upper/lower temperature | 24.96 / 20.48 C | 93.55 / 48.38 C | 15 / 15 C | FAIL |
| R2 upper/lower temperature | 21.26 / 20.08 C | 62.12 / 21.26 C | 15 / 5 C | FAIL / PASS |
| R0 upper mass | 7.80 kg | 26.94 kg | no worse than F3.3p1 | FAIL |
| R0 lower mass | 46.32 kg | 15.41 kg | no worse than F3.3p1 | FAIL |
| R0 interface | 1.969 m | 0.736 m | no worse than F3.3p1 | FAIL |

Legacy invariance closed exactly: zero differences across 13,110 compared
non-shadow cells.

## Surface allocation at 180 s

| Surface | SimuFire storage | CFAST storage | Delta |
|---|---:|---:|---:|
| Ceiling | 11.701 MJ | 12.614 MJ | -0.913 MJ |
| Upper wall | 4.466 MJ | 6.382 MJ | -1.916 MJ |
| Lower wall | 5.075 MJ | 2.707 MJ | +2.369 MJ |
| Floor | 2.229 MJ | 5.290 MJ | -3.061 MJ |

The total happens to be close while its physical partition is wrong. The
simulated interface leaves only `7.76 m2` of upper wall and `35.44 m2` of
lower wall; CFAST implies `29.96 m2` upper and `13.24 m2` lower at the same
time. Area/emissivity routing therefore deposits energy into the wrong wall
class even though the transaction conserves energy.

## Controls and topology sensitivity

- No-fire control: zero surface radiation and exchange.
- No-opening control: remote rooms remain at ambient.
- Sealed material fixture: energy closure remains within numerical tolerance.
- CFAST-boundary and physical-topology variants are nearly identical at
  180 s: only `-0.012 MJ` total storage and `-0.19 C` R0 upper temperature.

The unsupported paired inter-room wall contract is real future work, but it
is not the binding error in the 0-180 s window.

## Diagnosis

This is not a conservation, solver-stability or CSV-accounting failure:

1. the combined residual closes;
2. total and gas-driven surface storage pass;
3. the physical-topology variant does not materially change the result.

The failure is a coupled physical correspondence problem:

1. the upper layer remains too thin and too light;
2. the resulting interface routes too much wall area to the lower class;
3. canonical O2/source feedback accepts 31.9% less fire radiation than the
   CFAST reference;
4. remote rooms receive far too little thermal energy.

F3.3r2c therefore cannot promote the multi-surface shadow to runtime
authority and cannot retire Group C.

## Next phase

F3.3r2d must be diagnostic first. It should add no tuning coefficient and
should not run beyond 180 s. It must attribute, by checkpoint:

- requested, accepted and rejected fire radiation and the rejection reason;
- per-surface routing weights from the simulated interface;
- counterfactual routing weights from the committed CFAST interface, without
  applying them to state;
- upper/lower gas exchange accepted by each surface;
- wall-area migration and its carried energy;
- O2/source changes between OFF and multi-surface shadow.

The next implementation decision is allowed only after this audit separates
source-acceptance error from interface/area-allocation error. Paired
inter-room surface exchange remains a later phase unless the new attribution
shows it is material before 180 s.

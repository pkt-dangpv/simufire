# CFAST vs Simufire - R0 window opening at 360 s

## Scenario

Reduced comparison case built to mirror the Simufire "R0 isolated, exterior window opens at 360 s" behavior.

- Room `R0`: `5.0 x 4.0 x 2.4 m`
- Hall: `1.5 x 7.0 x 2.4 m`
- Interior door `R0 <-> Hall`: closed for the full run
- Exterior window in `R0`: closed at start, opened at `360 s`
- Duration: `520 s`

Artifacts:

- CFAST input: `sim/validation/cfast/r0_hall_window_360.in`
- Simufire case: `sim/validation/cases/cfast_r0_window_360.json`
- Simufire report: `sim/validation/reports/cfast_r0_window_360.json`

## Comparison table

`Layer_m` is the hot layer interface height from floor.

| Time (s) | Model | HRR (kW) | O2 | Upper temp (C) | Layer_m | CO (ppm) |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| 350 | CFAST | 288.36 | 0.0660 | 173.02 | 0.10 | 689 |
| 350.1 | Simufire | 261.14 | 0.0339 | 295.96 | 0.81 | 390 |
| 360 | CFAST | 288.36 | 0.0645 | 173.16 | 0.10 | 694 |
| 360.1 | Simufire | 256.43 | 0.0309 | 285.82 | 0.87 | 381 |
| 370 | CFAST | 240.36 | 0.0638 | 168.21 | 0.10 | 707 |
| 370.1 | Simufire | 245.44 | 0.0578 | 239.00 | 1.25 | 18 |
| 380 | CFAST | 1280.00 | 0.0616 | 260.31 | 0.52 | 722 |
| 380.1 | Simufire | 237.08 | 0.1093 | 218.28 | 1.64 | 2 |
| 420 | CFAST | 1280.00 | 0.1320 | 300.93 | 1.02 | 379 |
| 420.1 | Simufire | 1186.22 | 0.1439 | 154.14 | 1.20 | 80 |
| 510 | CFAST | 1280.00 | 0.1428 | 307.38 | 1.02 | 326 |
| 510.1 | Simufire | 965.67 | 0.1322 | 110.78 | 1.20 | 106 |

## What improved

- The pre-opening subventilated `HRR` still sits in the same band as CFAST instead of collapsing.
- The `CO` mismatch is no longer dominant. Simufire now stays in the same order of magnitude as CFAST instead of overshooting by one to two orders.
- Reventilation still produces a progressive `HRR` recovery rather than an instantaneous step.

## Main mismatches now

1. Simufire still keeps the hot layer too high before reopening.
   At `360 s`, CFAST is near `0.10 m` and Simufire is near `0.87 m`.

2. Simufire is now too cool after reopening.
   At `420 s`, CFAST is about `301 C` and Simufire is about `154 C`.

3. Post-opening recovery remains weaker than CFAST.
   At `420 s`, CFAST is `1280 kW` while Simufire is `1186 kW`, and by `510 s` Simufire has already decayed to `966 kW`.

4. The oxygen-starved phase is still more severe in Simufire.
   At `360 s`, CFAST is `O2 0.0645` while Simufire is `0.0309`.

## Most likely interpretation

The latest calibration largely fixed the old `CO` pathology by separating retained unburned gases from immediate toxic products and by adding a dedicated exterior species purge/dilution path. The dominant gap has shifted back to thermodynamics and layer structure:

- Simufire still consumes oxygen too aggressively in the sealed phase.
- Simufire vents and cools the room too effectively after reopening.
- The hot layer still does not collapse and reform with the same geometry CFAST predicts.

## Next calibration priorities

1. Reduce sealed-room oxygen depletion so the subventilated phase stabilizes closer to `O2 ~0.06`.
2. Recover more post-opening heat release without returning to the old digital `HRR` jump.
3. Lower the hot layer further in the sealed phase while keeping post-opening smoke venting stable.

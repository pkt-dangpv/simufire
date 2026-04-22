# CFAST vs Simufire - R0 window 0.8-2.0 m opens at 360 s

## Scenario

Reduced comparison case used to check the recent ventilation-layer fixes.

- Room `R0`: `5.0 x 4.0 x 2.4 m`
- Hall: `1.5 x 7.0 x 2.4 m`
- Door `R0 <-> Hall`: closed
- Exterior window in `R0`: `BOTTOM = 0.8 m`, `TOP = 2.0 m`
- Window opens at `360 s`
- Duration: `520 s`

Artifacts:

- CFAST input: `sim/validation/cfast/r0_hall_window_360_top20.in`
- Simufire case: `sim/validation/cases/cfast_r0_window_360.json`

## Comparison table

`Layer_m` is the hot layer interface height from floor.

| Time (s) | Model | HRR (kW) | O2 | Upper temp (C) | Layer_m | CO (ppm) |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| 350 | CFAST | 288.36 | 0.0660 | 173.02 | 0.10 | 689 |
| 350.1 | Simufire | 255.00 | 0.0529 | 304.08 | 0.75 | 2533 |
| 360 | CFAST | 288.36 | 0.0645 | 173.16 | 0.10 | 694 |
| 360.1 | Simufire | 255.00 | 0.0500 | 292.91 | 0.81 | 2471 |
| 370 | CFAST | 240.33 | 0.0638 | 168.21 | 0.10 | 707 |
| 370.1 | Simufire | 255.00 | 0.0685 | 247.69 | 1.20 | 383 |
| 380 | CFAST | 1280.00 | 0.0615 | 260.31 | 0.52 | 722 |
| 380.1 | Simufire | 402.29 | 0.1146 | 226.15 | 1.59 | 209 |
| 420 | CFAST | 1280.00 | 0.1310 | 301.33 | 0.96 | 384 |
| 420.1 | Simufire | 981.84 | 0.1342 | 160.11 | 1.08 | 3443 |
| 510 | CFAST | 1280.00 | 0.1421 | 307.55 | 0.96 | 329 |
| 510.1 | Simufire | 902.34 | 0.1321 | 101.49 | 1.20 | 5025 |

## What improved

- Pre-opening behavior is no longer catastrophically hot.
- Simufire now keeps a clearly ventilation-limited phase before the opening instead of racing into an unrealistic near-post-flashover state.
- Opening the window now increases `HRR`, raises `O2`, and actually vents / redistributes smoke instead of mainly moving `CO`.

## What still mismatches

1. Simufire remains too hot before opening.
   At `350-360 s`, it is still around `293-304 C` versus CFAST `173 C`.

2. Simufire reacts too softly just after opening.
   At `380 s`, CFAST has already climbed to `1280 kW`, while Simufire is only around `402 kW`.

3. Simufire cools too much after reopening.
   At `420 s`, CFAST is around `301 C`, while Simufire is near `160 C`.

4. CO remains far above CFAST after reopening.
   The model still over-retains / over-concentrates combustion products in the upper layer.

## Interpretation

The latest fixes moved the model in the right qualitative direction:

- flashover is less eager when there is not yet a convincing coupled layer,
- windows can now vent smoke without requiring a fully visible black layer all the way down,
- adjacent spaces respond more clearly to upper-layer transport.

But the post-vent recovery is still weaker and cooler than CFAST. The next calibration step should target:

1. upper-layer energy retention after re-ventilation,
2. upper-layer smoke / CO purge and dilution,
3. faster transition from subventilated burning back toward the vent-limited branch seen in CFAST.

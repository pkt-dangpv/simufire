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

## Comparison table

`Layer_m` is the hot layer interface height from floor.

| Time (s) | Model | HRR (kW) | O2 | Upper temp (C) | Layer_m | CO (ppm) |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| 350 | CFAST | 288.36 | 0.0660 | 173.02 | 0.10 | 689 |
| 350.1 | Simufire | 255.00 | 0.0500 | 470.87 | 0.54 | 2779 |
| 360 | CFAST | 288.36 | 0.0645 | 173.16 | 0.10 | 694 |
| 360.1 | Simufire | 255.00 | 0.0471 | 462.03 | 0.54 | 2709 |
| 370 | CFAST | 240.36 | 0.0638 | 168.21 | 0.10 | 707 |
| 370.1 | Simufire | 255.00 | 0.0768 | 391.25 | 1.04 | 418 |
| 380 | CFAST | 1280.00 | 0.0616 | 260.31 | 0.52 | 722 |
| 380.1 | Simufire | 217.00 | 0.1009 | 356.15 | 1.46 | 119 |
| 420 | CFAST | 1280.00 | 0.1320 | 300.93 | 1.02 | 379 |
| 420.1 | Simufire | 1148.11 | 0.1382 | 324.48 | 1.38 | 3631 |
| 510 | CFAST | 1280.00 | 0.1428 | 307.38 | 1.02 | 326 |
| 520.1 | Simufire | 1154.11 | 0.1382 | 342.35 | 1.38 | 3561 |

## What matches

- Both models show a ventilation-limited phase before the opening.
- Both models recover room oxygen from about `0.05-0.07` to about `0.13-0.14` after ventilation.
- The post-opening thermal response is now much closer: at `420 s`, Simufire is about `324 C` and CFAST about `301 C`.

## Main mismatches

1. Simufire still stays hotter before reopening.
   At `360 s`, CFAST is about `173 C` and Simufire about `462 C`.

2. Simufire keeps the hot layer too high after reopening.
   At `420 s`, CFAST is near `1.02 m` and Simufire near `1.38 m`.

3. Simufire is still somewhat under the CFAST HRR after reopening.
   At `420-520 s`, CFAST holds about `1280 kW` while Simufire stays near `1150 kW`.

4. CO remains the main unresolved gap.
   After adding a dedicated upper-layer CO metric in Simufire, the mismatch is clearer rather than smaller. At `420 s`, Simufire is about `3631 ppm` room-mean and about `25211 ppm` in the upper layer, while CFAST upper-layer CO is about `379 ppm`.

## Most likely interpretation

The oxygen fix plus the latest calibration were enough to restore reignition and make the post-opening temperature track much more closely. The remaining gap is now mostly about layer placement before/after opening and CO representation:

- Simufire still retains too much heat before the opening.
- Simufire does not lower the hot layer as aggressively as CFAST after the vent opens.
- Simufire needs a better CO model or a stratified CO bookkeeping if we want a closer apples-to-apples comparison with CFAST upper-layer outputs.

## Next calibration priorities

1. Review upper/lower layer placement before reopening so the pre-vent interface descends further under oxygen-starved burning.
2. Review post-opening layer recovery so the hot layer rises toward `~1.0 m` instead of staying near `~1.4 m`.
3. Review CO yield and upper-layer purge/mixing now that Simufire exposes a dedicated `COu` metric for apples-to-apples comparison against CFAST upper-layer outputs.

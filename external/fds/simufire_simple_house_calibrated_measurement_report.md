# Simple house FDS vs SimuFire measurement report

This report compares aligned measurements for calibration. It is not a scientific validation dataset.

SimuFire visibility uses the exported `visibility_m` column.
Older CSV files without that column fall back to the whole-room smoke approximation:
`visibility_m = 3 / (8700 * smoke_kg / volume_m3)`, capped at 30 m.

| Room | FDS peak T up C | Sim peak T up C | FDS vis<10m s | Sim vis<10m s | FDS min O2 % | Sim min O2 % | FDS peak CO ppm | Sim peak CO ppm | FDS peak CO2 % | Sim peak CO2 % | FDS est FED | Sim max FED |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Salon | 352.1 | 406.6 | 31.0 | 21.1 | 9.49 | 12.63 | 679 | 200 | 5.80 | 0.82 | 2.694 | 0.047 |
| Pasillo | 237.9 | 322.1 | 52.0 | 68.0 | 10.55 | 17.62 | 618 | 325 | 5.28 | 4.63 | 0.701 | 0.033 |
| Dormitorio1 | 136.0 | 51.5 | 77.0 | 92.1 | 11.51 | 20.38 | 562 | 157 | 4.81 | 2.15 | 0.249 | 0.011 |
| Dormitorio2 | 142.6 | 43.9 | 77.0 | 97.1 | 11.28 | 20.17 | 575 | 230 | 4.92 | 3.04 | 0.242 | 0.019 |
| Cocina | 129.5 | 51.4 | 83.0 | 91.1 | 11.56 | 20.52 | 558 | 112 | 4.78 | 1.58 | 0.203 | 0.006 |
| Bano | 127.0 | 46.4 | 78.0 | 125.1 | 11.45 | 20.25 | 565 | 203 | 4.84 | 2.66 | 0.232 | 0.015 |

## Notes

- FDS visibility is a device quantity at breathing height.
- SimuFire visibility is a whole-room smoke concentration approximation; it is useful for trends, not exact optics.
- FDS estimated FED is computed from room-point CO, O2, CO2 and interpolated breathing-height temperature; it omits radiant heat.
- If FDS CO columns show `NA`, regenerate `simufire_simple_house_default_devc.csv` by re-running FDS.

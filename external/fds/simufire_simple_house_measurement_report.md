# Simple house FDS vs SimuFire measurement report

This report compares aligned measurements for calibration. It is not a scientific validation dataset.

SimuFire visibility uses the exported `visibility_m` column.
Older CSV files without that column fall back to the whole-room smoke approximation:
`visibility_m = 3 / (8700 * smoke_kg / volume_m3)`, capped at 30 m.

| Room | FDS peak T up C | Sim peak T up C | FDS vis<10m s | Sim vis<10m s | FDS min O2 % | Sim min O2 % | FDS peak CO ppm | Sim peak CO ppm | FDS peak CO2 % | Sim peak CO2 % | FDS est FED | Sim max FED |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Salon | 352.1 | 355.4 | 31.0 | 21.1 | 9.49 | 12.14 | 679 | 196 | 5.80 | 0.98 | 2.694 | 0.061 |
| Pasillo | 237.9 | 216.6 | 52.0 | 64.0 | 10.55 | 18.41 | 618 | 140 | 5.28 | 1.40 | 0.701 | 0.011 |
| Dormitorio1 | 136.0 | 103.8 | 77.0 | 119.1 | 11.51 | 20.33 | 562 | 43 | 4.81 | 0.59 | 0.249 | 0.004 |
| Dormitorio2 | 142.6 | 114.8 | 77.0 | 122.1 | 11.28 | 20.10 | 575 | 61 | 4.92 | 0.81 | 0.242 | 0.005 |
| Cocina | 129.5 | 72.4 | 83.0 | 117.1 | 11.56 | 20.48 | 558 | 31 | 4.78 | 0.44 | 0.203 | 0.003 |
| Bano | 127.0 | 111.7 | 78.0 | 124.1 | 11.45 | 20.18 | 565 | 55 | 4.84 | 0.72 | 0.232 | 0.004 |

## Notes

- FDS visibility is a device quantity at breathing height.
- SimuFire visibility is a whole-room smoke concentration approximation; it is useful for trends, not exact optics.
- FDS estimated FED is computed from room-point CO, O2, CO2 and interpolated breathing-height temperature; it omits radiant heat.
- If FDS CO columns show `NA`, regenerate `simufire_simple_house_default_devc.csv` by re-running FDS.

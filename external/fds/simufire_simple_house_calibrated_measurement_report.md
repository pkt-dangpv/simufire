# Simple house FDS vs SimuFire measurement report

This report compares aligned measurements for calibration. It is not a scientific validation dataset.

SimuFire visibility uses the exported `visibility_m` column.
Older CSV files without that column fall back to the whole-room smoke approximation:
`visibility_m = 3 / (8700 * smoke_kg / volume_m3)`, capped at 30 m.

| Room | FDS peak T up C | Sim peak T up C | FDS vis<10m s | Sim vis<10m s | FDS min O2 % | Sim min O2 % | FDS peak CO ppm | Sim peak CO ppm | FDS peak CO2 % | Sim peak CO2 % | FDS est FED | Sim max FED |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Salon | 349.9 | 403.9 | 31.0 | NA | 9.70 | 12.68 | 667 | 278 | 5.71 | 1.43 | 2.612 | 0.083 |
| Pasillo | 239.6 | 371.5 | 52.0 | NA | 10.59 | 17.63 | 612 | 414 | 5.24 | 6.02 | 0.687 | 0.062 |
| Dormitorio1 | 132.4 | 51.3 | 77.0 | NA | 11.70 | 19.78 | 550 | 217 | 4.71 | 3.02 | 0.231 | 0.018 |
| Dormitorio2 | 126.5 | 42.1 | 77.0 | NA | 11.58 | 19.33 | 558 | 319 | 4.78 | 4.34 | 0.220 | 0.034 |
| Cocina | 119.2 | 53.0 | 83.0 | NA | 11.70 | 20.08 | 551 | 155 | 4.72 | 2.20 | 0.187 | 0.011 |
| Bano | 123.3 | 45.0 | 78.0 | NA | 11.57 | 19.51 | 558 | 281 | 4.78 | 3.79 | 0.226 | 0.027 |

## Notes

- FDS visibility is a device quantity at breathing height.
- SimuFire visibility is a whole-room smoke concentration approximation; it is useful for trends, not exact optics.
- FDS estimated FED is computed from room-point CO, O2, CO2 and interpolated breathing-height temperature; it omits radiant heat.
- If FDS CO columns show `NA`, regenerate `simufire_simple_house_default_devc.csv` by re-running FDS.

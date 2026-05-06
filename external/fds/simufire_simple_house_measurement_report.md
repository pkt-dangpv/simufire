# Simple house FDS vs SimuFire measurement report

This report compares aligned measurements for calibration. It is not a scientific validation dataset.

SimuFire visibility uses the exported `visibility_m` column.
Older CSV files without that column fall back to the whole-room smoke approximation:
`visibility_m = 3 / (8700 * smoke_kg / volume_m3)`, capped at 30 m.

| Room | FDS peak T up C | Sim peak T up C | FDS vis<10m s | Sim vis<10m s | FDS min O2 % | Sim min O2 % | FDS peak CO ppm | Sim peak CO ppm | FDS peak CO2 % | Sim peak CO2 % | FDS est FED | Sim max FED |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Salon | 349.9 | 412.9 | 31.0 | NA | 9.70 | 9.29 | 667 | 552 | 5.71 | 5.90 | 2.612 | 0.309 |
| Pasillo | 239.6 | 301.7 | 52.0 | NA | 10.59 | 13.48 | 612 | 434 | 5.24 | 6.26 | 0.687 | 0.093 |
| Dormitorio1 | 132.4 | 154.4 | 77.0 | NA | 11.70 | 15.40 | 550 | 288 | 4.71 | 4.27 | 0.231 | 0.027 |
| Dormitorio2 | 126.5 | 140.0 | 77.0 | NA | 11.58 | 14.68 | 558 | 349 | 4.78 | 5.10 | 0.220 | 0.039 |
| Cocina | 119.2 | 171.0 | 83.0 | NA | 11.70 | 16.16 | 551 | 233 | 4.72 | 3.47 | 0.187 | 0.018 |
| Bano | 123.3 | 143.3 | 78.0 | NA | 11.57 | 14.88 | 558 | 330 | 4.78 | 4.84 | 0.226 | 0.035 |

## Notes

- FDS visibility is a device quantity at breathing height.
- SimuFire visibility is a whole-room smoke concentration approximation; it is useful for trends, not exact optics.
- FDS estimated FED is computed from room-point CO, O2, CO2 and interpolated breathing-height temperature; it omits radiant heat.
- If FDS CO columns show `NA`, regenerate `simufire_simple_house_default_devc.csv` by re-running FDS.

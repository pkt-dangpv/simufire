# Simple house FDS vs SimuFire measurement report

This report compares aligned measurements for calibration. It is not a scientific validation dataset.

SimuFire visibility uses the exported `visibility_m` column.
Older CSV files without that column fall back to the whole-room smoke approximation:
`visibility_m = 3 / (8700 * smoke_kg / volume_m3)`, capped at 30 m.

| Room | FDS peak T up C | Sim peak T up C | FDS vis<10m s | Sim vis<10m s | FDS min O2 % | Sim min O2 % | FDS peak CO ppm | Sim peak CO ppm | FDS peak CO2 % | Sim peak CO2 % | FDS est FED | Sim max FED |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Salon | 335.3 | 412.9 | 31.0 | 21.1 | 9.79 | 9.29 | 665 | 557 | 5.68 | 5.90 | 2.607 | 0.309 |
| Pasillo | 236.2 | 301.7 | 52.0 | 58.0 | 10.38 | 13.48 | 627 | 434 | 5.36 | 6.26 | 0.673 | 0.093 |
| Dormitorio1 | 127.5 | 154.4 | 77.0 | 99.1 | 11.70 | 15.40 | 550 | 288 | 4.71 | 4.27 | 0.225 | 0.027 |
| Dormitorio2 | 124.7 | 140.0 | 77.0 | 94.1 | 11.58 | 14.68 | 558 | 349 | 4.78 | 5.10 | 0.221 | 0.039 |
| Cocina | 125.3 | 171.0 | 83.0 | 104.1 | 11.71 | 16.16 | 550 | 233 | 4.71 | 3.47 | 0.194 | 0.018 |
| Bano | 121.0 | 143.3 | 78.0 | 96.1 | 11.54 | 14.88 | 560 | 330 | 4.79 | 4.84 | 0.222 | 0.035 |

## Notes

- FDS visibility is a device quantity at breathing height.
- SimuFire visibility is a whole-room smoke concentration approximation; it is useful for trends, not exact optics.
- FDS estimated FED is computed from room-point CO, O2, CO2 and interpolated breathing-height temperature; it omits radiant heat.
- If FDS CO columns show `NA`, regenerate `simufire_simple_house_default_devc.csv` by re-running FDS.

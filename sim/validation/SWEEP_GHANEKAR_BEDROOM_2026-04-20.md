# Sweep Ghanekar Bedroom - 2026-04-20

Barrido ejecutado con:
- `scripts/simulation/run_ghanekar_sweep.ps1`

Resumen machine-readable:
- `sim/validation/reports/sweeps/ghanekar_sweep_summary_2026-04-20.json`

Reportes individuales:
- `sim/validation/reports/sweeps/_sweep_ghanekar_baseline.json`
- `sim/validation/reports/sweeps/_sweep_ghanekar_transport_soft.json`
- `sim/validation/reports/sweeps/_sweep_ghanekar_transport_soft_plus.json`
- `sim/validation/reports/sweeps/_sweep_ghanekar_thermal_fire_room.json`
- `sim/validation/reports/sweeps/_sweep_ghanekar_combo_balanced.json`
- `sim/validation/reports/sweeps/_sweep_ghanekar_combo_aggressive.json`

## Objetivos empiricos

- `flashover @ 0.9 m ~= 186 s`
- `DeltaO2 hallway ~= 198 s`
- `DeltaCO hallway ~= 204 s`
- `IDLH proxy (CO > 1200 ppm) ~= 216 s`

## Ranking del barrido

| Variante | Score | Flashover 0.9 m | O2 hallway | CO hallway | CO > 1200 | Smoke hallway |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `transport_soft_plus` | `507.75` | `n/a` | `148.67 s` | `153.75 s` | `160.50 s` | `152.67 s` |
| `transport_soft` | `514.17` | `n/a` | `145.33 s` | `152.50 s` | `159.17 s` | `151.67 s` |
| `combo_balanced` | `516.29` | `n/a` | `145.42 s` | `151.58 s` | `158.33 s` | `150.75 s` |
| `baseline` | `520.29` | `n/a` | `141.00 s` | `151.67 s` | `158.58 s` | `150.92 s` |
| `thermal_fire_room` | `523.71` | `n/a` | `140.67 s` | `150.42 s` | `157.33 s` | `149.75 s` |
| `combo_aggressive` | `548.96` | `n/a` | `138.67 s` | `141.50 s` | `147.58 s` | `140.58 s` |

## Lo que nos dice el barrido

### 1. El transporte al pasillo mejora si amortiguamos el intercambio interior

La mejor variante global ha sido `transport_soft_plus`, que toca solo:
- `doorway_o2_exchange_coeff = 1.00`
- `doorway_o2_background_exchange_kg_s_m2 = 0.035`
- `base_spill_kg_s_per_m2 = 0.30`
- `temp_push_factor = 0.0050`
- `ach_infiltration = 1.10`

Respecto al baseline:
- `O2 hallway`: `141.00 -> 148.67 s`
- `CO > 200 ppm`: `151.67 -> 153.75 s`
- `CO > 1200 ppm`: `158.58 -> 160.50 s`
- `smoke hallway`: `150.92 -> 152.67 s`

Mejora, pero todavia quedamos claramente por debajo de los objetivos empiricos de `198-216 s`.

### 2. El calentamiento a `0.9 m` responde a la termica, pero no lo suficiente

Las variantes termicas no consiguen el `flashover` experimental por `T(0.9 m) > 600 C` antes de `300 s`.

Si usamos `room_0_final_temp_at_0_9m_c` como proxy del progreso:
- `baseline`: `450.60 C`
- `combo_balanced`: `498.07 C`
- `thermal_fire_room`: `534.67 C`
- `combo_aggressive`: `527.47 C`

O sea: el perfil vertical si se deja mover, pero todavia no lo bastante como para reproducir el criterio del paper.

### 3. La variante agresiva no conviene

`combo_aggressive` empeora claramente la concordancia en el pasillo:
- `O2 hallway = 138.67 s`
- `CO hallway = 141.50 s`
- `CO > 1200 ppm = 147.58 s`

Eso sugiere que subir simultaneamente `fire_alpha` y `thermal_feedback` mete demasiada severidad demasiado pronto y vuelve a adelantar todo el transporte.

## Mejor punto de partida para la siguiente iteracion

### Si priorizamos transporte al pasillo

Usar `transport_soft_plus` como nueva base de exploracion.

### Si queremos equilibrio entre pasillo y calentamiento a `0.9 m`

Usar `combo_balanced` como base manual.

No ha ganado por score puro, pero es la mejor combinacion si queremos:
- retrasar algo el pasillo
- y a la vez empujar la temperatura del dormitorio a `0.9 m`

## Parametros con mejor señal despues del barrido

Mantener en la siguiente ronda:
- `doorway_o2_exchange_coeff`
- `doorway_o2_background_exchange_kg_s_m2`
- `base_spill_kg_s_per_m2`
- `temp_push_factor`
- `ach_infiltration`
- `upper_to_lower_loss_rate`
- `upper_to_ambient_loss_rate`
- `wall_absorption_rate`
- `thermal_gradient_band_fraction`
- `thermal_gradient_max_band_m`
- `floor_cooling_band_fraction`
- `floor_cooling_band_max_m`

Evitar por ahora:
- `fire_alpha_kw_s2`
- `thermal_feedback_coeff`

En esta fase tienden a adelantar demasiado la respuesta completa.

## Hallazgo de codigo importante

Esta memoria corresponde a la primera pasada de calibracion. En ese momento tratabamos `lower_layer_warming_rate` como una perilla todavia no conectada. Mas tarde, el 20-04-2026, esa transferencia a capa baja se cableo en `ThermalSystem.gd`, asi que esta nota debe leerse como historica y no como estado actual del motor.

La referencia actualizada despues del cableado es:
- `sim/validation/MICRO_CALIBRACION_GHANEKAR_2026-04-20.md`

## Siguiente paso recomendado

1. Tomar `combo_balanced` como base de trabajo.
2. Hacer un microbarrido alrededor suyo solo con:
   - `base_spill_kg_s_per_m2`
   - `temp_push_factor`
   - `ach_infiltration`
   - `upper_to_lower_loss_rate`
   - `floor_cooling_band_fraction`
3. Separar la evaluacion en dos objetivos:
   - `transporte hallway`
   - `flashover @ 0.9 m`
4. Si aun asi `T(0.9 m)` no llega, revisar el modelo vertical antes de seguir afinando coeficientes.

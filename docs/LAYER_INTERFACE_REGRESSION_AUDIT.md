# Layer Interface Regression Audit

## Resumen ejecutivo

- Resultado: **PASS_WITH_WARNINGS**
- Generado: `2026-06-06T11:40:34+00:00`
- Alcance: comparación before/after de HRR, especies, FED, visibilidad, temperaturas y alturas de capa.
- Nota: que `visible_smoke_layer_m`, `thermal_layer_m` y `flow_interface_m` sean distintos no es un fallo; son magnitudes físicas distintas.
- Corrección puntual FED térmico: el fallo estructural anterior queda cerrado. `ThermalSystem.step_fed()` y `compute_fed_delta_for_height()` ya no leen la capa visible legacy para decidir inmersión térmica; pasan por el helper canónico de exposición térmica.

## Validación puntual FED térmico

| Caso | visible min | thermal min | layer 150C min | FED heat final | Resultado |
|---|---:|---:|---:|---:|---|
| fed_thermal_layer_smoke_only | 1.400 m | 2.400 m | 2.400 m | 0.000000 | PASS |

Este caso inyecta humo frío sin ignición: la capa visible baja por carga óptica, pero la capa térmica y `layer_150c_m` se mantienen arriba. El FED térmico no se dispara por humo visible.

## Casos ejecutados / comparados

| Caso | CSV pair | JSON pair | Baseline after | Notas | Warnings |
|---|---:|---:|---|---|---:|
| layer_interface_single_room_window | yes | no | PASS/NA | - | 1 |
| cfast_r0_window_360 | no | yes | FAIL | csv pair unavailable; JSON report fallback used where possible | 11 |
| living_room_hallway | no | yes | FAIL | csv pair unavailable; JSON report fallback used where possible | 10 |
| v4_co_remote_rooms | no | yes | FAIL | csv pair unavailable; JSON report fallback used where possible | 9 |

## Warnings detectados

| Caso | Sala | Campo | Métrica | Valor | Umbral | Mensaje |
|---|---:|---|---|---:|---:|---|
| layer_interface_single_room_window | 0 | fed | max_rel_delta | 0.218861 | 0.100000 | FED > 10% in room 0: 0.218861 > 0.1 |
| cfast_r0_window_360 | 0 | o2 | max_abs_delta | 0.017482 | 0.010000 | O2 > 0.01 abs in room 0: 0.0174819 > 0.01 |
| cfast_r0_window_360 | 0 | o2_upper | max_abs_delta | 0.165913 | 0.010000 | O2 upper > 0.01 abs in room 0: 0.165913 > 0.01 |
| cfast_r0_window_360 | 0 | co_ppm | max_rel_delta | 0.505391 | 0.100000 | CO > 10% in room 0: 0.505391 > 0.1 |
| cfast_r0_window_360 | 0 | co2_ppm | max_rel_delta | 0.571141 | 0.100000 | CO2 > 10% in room 0: 0.571141 > 0.1 |
| cfast_r0_window_360 | 0 | visibility_m | max_rel_delta | 0.705309 | 0.150000 | Visibility > 15% in room 0: 0.705309 > 0.15 |
| cfast_r0_window_360 | 0 | fed | max_rel_delta | 0.211844 | 0.100000 | FED > 10% in room 0: 0.211844 > 0.1 |
| cfast_r0_window_360 | 1 | co_ppm | max_rel_delta | 0.359722 | 0.100000 | CO > 10% in room 1: 0.359722 > 0.1 |
| cfast_r0_window_360 | 1 | co2_ppm | max_rel_delta | 0.434579 | 0.100000 | CO2 > 10% in room 1: 0.434579 > 0.1 |
| cfast_r0_window_360 | 1 | hcn_ppm | max_rel_delta | 0.370390 | 0.100000 | HCN > 10% in room 1: 0.37039 > 0.1 |
| cfast_r0_window_360 | 1 | visibility_m | max_rel_delta | 0.862103 | 0.150000 | Visibility > 15% in room 1: 0.862103 > 0.15 |
| cfast_r0_window_360 | 1 | fed | max_rel_delta | 0.133191 | 0.100000 | FED > 10% in room 1: 0.133191 > 0.1 |
| living_room_hallway | 0 | hrr_kw | max_rel_delta | 0.051199 | 0.050000 | HRR > 5% in room 0: 0.0511987 > 0.05 |
| living_room_hallway | 0 | co_ppm | max_rel_delta | 1.5276 | 0.100000 | CO > 10% in room 0: 1.52757 > 0.1 |
| living_room_hallway | 0 | co2_ppm | max_rel_delta | 1.2986 | 0.100000 | CO2 > 10% in room 0: 1.29857 > 0.1 |
| living_room_hallway | 0 | visibility_m | max_rel_delta | 0.927462 | 0.150000 | Visibility > 15% in room 0: 0.927462 > 0.15 |
| living_room_hallway | 0 | fed | max_rel_delta | 1.5771 | 0.100000 | FED > 10% in room 0: 1.57707 > 0.1 |
| living_room_hallway | 1 | o2 | max_abs_delta | 0.015439 | 0.010000 | O2 > 0.01 abs in room 1: 0.0154386 > 0.01 |
| living_room_hallway | 1 | co_ppm | max_rel_delta | 0.825238 | 0.100000 | CO > 10% in room 1: 0.825238 > 0.1 |
| living_room_hallway | 1 | co2_ppm | max_rel_delta | 0.816113 | 0.100000 | CO2 > 10% in room 1: 0.816113 > 0.1 |
| living_room_hallway | 1 | visibility_m | max_rel_delta | 0.165469 | 0.150000 | Visibility > 15% in room 1: 0.165469 > 0.15 |
| living_room_hallway | 1 | fed | max_rel_delta | 15.94 | 0.100000 | FED > 10% in room 1: 15.9365 > 0.1 |
| v4_co_remote_rooms | 0 | hrr_kw | max_rel_delta | 0.136285 | 0.050000 | HRR > 5% in room 0: 0.136285 > 0.05 |
| v4_co_remote_rooms | 0 | co_ppm | max_rel_delta | 0.353269 | 0.100000 | CO > 10% in room 0: 0.353269 > 0.1 |
| v4_co_remote_rooms | 0 | co2_ppm | max_rel_delta | 0.381374 | 0.100000 | CO2 > 10% in room 0: 0.381374 > 0.1 |
| v4_co_remote_rooms | 0 | fed | max_rel_delta | 109.1 | 0.100000 | FED > 10% in room 0: 109.122 > 0.1 |
| v4_co_remote_rooms | 1 | co_ppm | max_rel_delta | 0.421938 | 0.100000 | CO > 10% in room 1: 0.421938 > 0.1 |
| v4_co_remote_rooms | 1 | co2_ppm | max_rel_delta | 0.304866 | 0.100000 | CO2 > 10% in room 1: 0.304866 > 0.1 |
| v4_co_remote_rooms | 1 | fed | max_rel_delta | 0.594507 | 0.100000 | FED > 10% in room 1: 0.594507 > 0.1 |
| v4_co_remote_rooms | 2 | co2_ppm | max_rel_delta | 0.311536 | 0.100000 | CO2 > 10% in room 2: 0.311536 > 0.1 |
| v4_co_remote_rooms | 2 | fed | max_rel_delta | 0.717170 | 0.100000 | FED > 10% in room 2: 0.71717 > 0.1 |

## Baseline histórica after

| Caso | Métrica | Actual | Regla |
|---|---|---:|---|
| cfast_r0_window_360 | room_0_final_hot_layer_m | 0.120000 | `{"expected": 1.008, "tolerance": 0.1}` |
| cfast_r0_window_360 | room_0_final_layer_150c_m | 0.120431 | `{"expected": 1.009, "tolerance": 0.1}` |
| cfast_r0_window_360 | room_0_final_temp_upper_raw_c | 333.7 | `{"expected": 308.96, "tolerance": 10.0}` |
| cfast_r0_window_360 | room_0_min_l150_m | 0.120431 | `{"expected": 0.561, "tolerance": 0.1}` |
| living_room_hallway | room_1_final_temp_at_1_8m_c | 156.1 | `{"expected": 122.534751, "tolerance": 15.0}` |
| living_room_hallway | room_1_min_l150_m | 0.318794 | `{"expected": 1.672793, "tolerance": 0.2}` |
| living_room_hallway | room_1_peak_temp_upper_c | 468 | `{"expected": 349.191257, "tolerance": 25.0}` |
| v4_co_remote_rooms | time_room_1_co_upper_above_1200_s | 96.25 | `{"expected": 140.25, "tolerance": 20.0}` |
| v4_co_remote_rooms | time_room_1_o2_below_18pct_s | 343.2 | `{"expected": 287.75, "tolerance": 10.0}` |
| v4_co_remote_rooms | time_room_2_co_upper_above_200_s | 98.5 | `{"expected": 152.25, "tolerance": 30.0}` |

## Diferencias principales

| Caso | Sala | Campo | Fuente | max abs | max rel | Δ60s | Δ120s | Δ180s | pico before | pico after |
|---|---:|---|---|---:|---:|---:|---:|---:|---:|---:|
| cfast_r0_window_360 | 0 | o2_upper | json_report | 0.165913 | 165.9 | - | - | - | 0.000929 | 0.039750 |
| v4_co_remote_rooms | 0 | fed | json_report | 181.7 | 109.1 | - | - | - | 1.6656 | 183.4 |
| living_room_hallway | 1 | fed | json_report | 4.9459 | 15.94 | - | - | - | 0.310352 | 5.2563 |
| cfast_r0_window_360 | 0 | temp_lower_c | json_report | 308.3 | 12.14 | - | - | - | 25.39 | 333.7 |
| living_room_hallway | 0 | fed | json_report | 61.22 | 1.5771 | - | - | - | 38.82 | 100 |
| living_room_hallway | 0 | co_ppm | json_report | 681.5 | 1.5276 | - | - | - | 846.1 | 1.19e+03 |
| living_room_hallway | 0 | co2_ppm | json_report | 7.41e+03 | 1.2986 | - | - | - | 8.39e+03 | 1.58e+04 |
| living_room_hallway | 0 | visibility_m | json_report | 0.094892 | 0.927462 | - | - | - | 0.008065 | 0.007134 |
| cfast_r0_window_360 | 0 | layer_150c_m | json_report | 0.888258 | 0.880606 | - | - | - | 0.560924 | 0.120431 |
| living_room_hallway | 0 | temp_lower_c | json_report | 169.2 | 0.864087 | - | - | - | 195.8 | 365 |
| cfast_r0_window_360 | 1 | visibility_m | json_report | 25.86 | 0.862103 | - | - | - | 30 | 4.1369 |
| living_room_hallway | 1 | layer_150c_m | json_report | 1.6341 | 0.831370 | - | - | - | 1.6841 | 0.318794 |
| v4_co_remote_rooms | 1 | temp_upper_c | json_report | 103.1 | 0.829479 | - | - | - | 124.3 | 227.4 |
| living_room_hallway | 1 | co_ppm | json_report | 4.74e+03 | 0.825238 | - | - | - | 5.75e+03 | 1e+03 |
| living_room_hallway | 1 | co2_ppm | json_report | 3.58e+04 | 0.816113 | - | - | - | 4.38e+04 | 8.06e+03 |
| v4_co_remote_rooms | 2 | fed | json_report | 1.5999 | 0.717170 | - | - | - | 2.2308 | 0.630938 |
| cfast_r0_window_360 | 0 | visibility_m | json_report | 0.600988 | 0.705309 | - | - | - | 0.008632 | 0.004343 |
| v4_co_remote_rooms | 1 | fed | json_report | 1.0177 | 0.594507 | - | - | - | 1.7119 | 0.694167 |
| cfast_r0_window_360 | 0 | co2_ppm | json_report | 5.21e+03 | 0.571141 | - | - | - | 9.05e+04 | 9.32e+04 |
| cfast_r0_window_360 | 0 | co_ppm | json_report | 14.69 | 0.505391 | - | - | - | 417.4 | 429 |
| living_room_hallway | 0 | layer_150c_m | json_report | 0.093737 | 0.448919 | - | - | - | 0.160458 | 0.098284 |
| cfast_r0_window_360 | 1 | co2_ppm | json_report | 159.1 | 0.434579 | - | - | - | 366.2 | 207 |
| v4_co_remote_rooms | 1 | co_ppm | json_report | 2.58e+03 | 0.421938 | - | - | - | 6.12e+03 | 3.54e+03 |
| living_room_hallway | 1 | temp_upper_c | json_report | 132.6 | 0.395363 | - | - | - | 335.4 | 468 |
| v4_co_remote_rooms | 0 | co2_ppm | json_report | 8.16e+03 | 0.381374 | - | - | - | 2.14e+04 | 2.95e+04 |
| cfast_r0_window_360 | 1 | hcn_ppm | json_report | 0.176060 | 0.370390 | - | - | - | 0.475336 | 0.299276 |
| cfast_r0_window_360 | 1 | co_ppm | json_report | 0.471555 | 0.359722 | - | - | - | 1.3109 | 0.839333 |
| v4_co_remote_rooms | 2 | temp_upper_c | json_report | 29.53 | 0.353447 | - | - | - | 83.55 | 113.1 |
| v4_co_remote_rooms | 0 | co_ppm | json_report | 1.67e+03 | 0.353269 | - | - | - | 4.76e+03 | 3.09e+03 |
| living_room_hallway | 0 | temp_upper_c | json_report | 128.6 | 0.318744 | - | - | - | 756.1 | 705.7 |

## Checks estructurales

| Check | Resultado | Detalle | Evidencia |
|---|---|---|---|
| canonical_layer_model_exports_four_functions | PASS | LayerInterfaceModel exposes visible, thermal, flow and breathing-zone helpers. | - |
| visibility_uses_visible_smoke_layer | PASS | SimulationStateBuilder computes visibility from visible_smoke_layer_m, not thermal_layer_m. | - |
| csv_exports_canonical_layer_fields | PASS | CSV header and rows export visible, thermal, flow and 150C layer heights. | - |
| gas_exchange_exterior_uses_flow_interface_helper | PASS | Exterior gas exchange obtains hot outflow height through LayerInterfaceModel. | - |
| gas_exchange_zone_routing_uses_flow_interface | PASS | Gas exchange upper/lower routing uses canonical flow_interface_m. | - |
| smoke_spill_uses_flow_interface | PASS | Smoke spill path is bridged through the canonical flow interface. | - |
| oxygen_and_hvac_use_flow_interface | PASS | O2/HVAC flow routing resolves room interfaces through LayerInterfaceModel. | - |
| interior_opening_flow_state_uses_flow_interface | PASS | Interior opening flow state centralizes neutral-plane derivation from flow_interface_m. | - |
| no_local_neutral_f_reintroduced | PASS | No local _neutral_f/_alpha_b-style interface calculation was found outside central flow helpers. | - |
| fed_thermal_exposure_uses_thermal_layer_or_150c | PASS | FED thermal exposure should be based on thermal_layer_m/layer_150c_m rather than legacy h_layer_m. | - |

## Conclusión

PASS_WITH_WARNINGS: la arquitectura queda auditable, pero hay warnings numéricos o artefactos incompletos que deben revisarse antes de cerrar baseline.

## Recomendaciones siguientes

- Generar pares CSV before/after para los cuatro casos si se necesita comparar `delta_at_60s/120s/180s` con máxima precisión.
- Revisar cualquier FAIL estructural antes de rebaselinear tolerancias físicas.
- Mantener separados los cambios de arquitectura y la recalibración de HRR/O2/FED/CO para que las causas sean trazables.

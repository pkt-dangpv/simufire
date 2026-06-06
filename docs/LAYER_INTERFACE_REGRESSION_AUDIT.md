# Layer Interface Regression Audit

## Resumen ejecutivo

- Resultado: **FAIL**
- Generado: `2026-06-06T11:14:25+00:00`
- Alcance: comparación before/after de HRR, especies, FED, visibilidad, temperaturas y alturas de capa.
- Nota: que `visible_smoke_layer_m`, `thermal_layer_m` y `flow_interface_m` sean distintos no es un fallo; son magnitudes físicas distintas.

## Casos ejecutados / comparados

| Caso | CSV pair | JSON pair | Notas | Warnings |
|---|---:|---:|---|---:|
| layer_interface_single_room_window | no | no | before artifact missing; after artifact missing; csv pair unavailable; JSON report fallback used where possible | 0 |
| cfast_r0_window_360 | no | yes | csv pair unavailable; JSON report fallback used where possible | 0 |
| living_room_hallway | no | yes | csv pair unavailable; JSON report fallback used where possible | 0 |
| v4_co_remote_rooms | no | yes | csv pair unavailable; JSON report fallback used where possible | 0 |

## Warnings detectados

No se detectaron warnings numéricos con los artefactos disponibles.

## Diferencias principales

| Caso | Sala | Campo | Fuente | max abs | max rel | Δ60s | Δ120s | Δ180s | pico before | pico after |
|---|---:|---|---|---:|---:|---:|---:|---:|---:|---:|
| cfast_r0_window_360 | 0 | hrr_kw | json_report | 0.000000 | 0.000000 | - | - | - | 1.27e+03 | 1.27e+03 |
| cfast_r0_window_360 | 0 | o2 | json_report | 0.000000 | 0.000000 | - | - | - | 0.149500 | 0.149500 |
| cfast_r0_window_360 | 0 | o2_upper | json_report | 0.000000 | 0.000000 | - | - | - | 0.000929 | 0.000929 |
| cfast_r0_window_360 | 0 | co_ppm | json_report | 0.000000 | 0.000000 | - | - | - | 417.4 | 417.4 |
| cfast_r0_window_360 | 0 | co2_ppm | json_report | 0.000000 | 0.000000 | - | - | - | 9.05e+04 | 9.05e+04 |
| cfast_r0_window_360 | 0 | hcn_ppm | json_report | 0.000000 | 0.000000 | - | - | - | 286.2 | 286.2 |
| cfast_r0_window_360 | 0 | layer_150c_m | json_report | 0.000000 | 0.000000 | - | - | - | 0.560924 | 0.560924 |
| cfast_r0_window_360 | 0 | visibility_m | json_report | 0.000000 | 0.000000 | - | - | - | 0.008632 | 0.008632 |
| cfast_r0_window_360 | 0 | fed | json_report | 0.000000 | 0.000000 | - | - | - | 7.7600 | 7.7600 |
| cfast_r0_window_360 | 0 | temp_upper_c | json_report | 0.000000 | 0.000000 | - | - | - | 318.5 | 318.5 |
| cfast_r0_window_360 | 0 | temp_lower_c | json_report | 0.000000 | 0.000000 | - | - | - | 25.39 | 25.39 |
| cfast_r0_window_360 | 1 | hrr_kw | json_report | 0.000000 | 0.000000 | - | - | - | 0.000000 | 0.000000 |
| cfast_r0_window_360 | 1 | o2 | json_report | 0.000000 | 0.000000 | - | - | - | 0.208923 | 0.208923 |
| cfast_r0_window_360 | 1 | o2_upper | json_report | 0.000000 | 0.000000 | - | - | - | 0.209000 | 0.209000 |
| cfast_r0_window_360 | 1 | co_ppm | json_report | 0.000000 | 0.000000 | - | - | - | 1.3109 | 1.3109 |
| cfast_r0_window_360 | 1 | co2_ppm | json_report | 0.000000 | 0.000000 | - | - | - | 366.2 | 366.2 |
| cfast_r0_window_360 | 1 | hcn_ppm | json_report | 0.000000 | 0.000000 | - | - | - | 0.475336 | 0.475336 |
| cfast_r0_window_360 | 1 | layer_150c_m | json_report | 0.000000 | 0.000000 | - | - | - | 2.4000 | 2.4000 |
| cfast_r0_window_360 | 1 | visibility_m | json_report | 0.000000 | 0.000000 | - | - | - | 30 | 30 |
| cfast_r0_window_360 | 1 | fed | json_report | 0.000000 | 0.000000 | - | - | - | 0.000508 | 0.000508 |
| cfast_r0_window_360 | 1 | temp_upper_c | json_report | 0.000000 | 0.000000 | - | - | - | 20 | 20 |
| cfast_r0_window_360 | 1 | temp_lower_c | json_report | 0.000000 | 0.000000 | - | - | - | 20 | 20 |
| living_room_hallway | 0 | hrr_kw | json_report | 0.000000 | 0.000000 | - | - | - | 1.24e+03 | 1.24e+03 |
| living_room_hallway | 0 | o2 | json_report | 0.000000 | 0.000000 | - | - | - | 0.117285 | 0.117285 |
| living_room_hallway | 0 | co_ppm | json_report | 0.000000 | 0.000000 | - | - | - | 846.1 | 846.1 |
| living_room_hallway | 0 | co2_ppm | json_report | 0.000000 | 0.000000 | - | - | - | 8.39e+03 | 8.39e+03 |
| living_room_hallway | 0 | layer_150c_m | json_report | 0.000000 | 0.000000 | - | - | - | 0.160458 | 0.160458 |
| living_room_hallway | 0 | visibility_m | json_report | 0.000000 | 0.000000 | - | - | - | 0.008065 | 0.008065 |
| living_room_hallway | 0 | fed | json_report | 0.000000 | 0.000000 | - | - | - | 38.82 | 38.82 |
| living_room_hallway | 0 | temp_upper_c | json_report | 0.000000 | 0.000000 | - | - | - | 756.1 | 756.1 |

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
| fed_thermal_exposure_uses_thermal_layer_or_150c | FAIL | FED thermal exposure should be based on thermal_layer_m/layer_150c_m rather than legacy h_layer_m. | ThermalSystem.step_fed still gates in_upper_layer with room.h_layer_m. |

## Conclusión

FAIL: al menos un contrato estructural de capas/interfaces no se cumple. No se han aplicado correcciones físicas automáticas en esta auditoría.

## Recomendaciones siguientes

- Generar pares CSV before/after para los cuatro casos si se necesita comparar `delta_at_60s/120s/180s` con máxima precisión.
- Revisar cualquier FAIL estructural antes de rebaselinear tolerancias físicas.
- Mantener separados los cambios de arquitectura y la recalibración de HRR/O2/FED/CO para que las causas sean trazables.

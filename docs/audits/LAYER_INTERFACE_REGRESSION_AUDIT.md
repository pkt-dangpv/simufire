# Layer Interface Regression Audit

## Resumen ejecutivo

- Resultado: **PASS_WITH_WARNINGS**
- Generado: `2026-06-06T13:28:20+00:00`
- Alcance: comparación before/after de HRR, especies, FED, visibilidad, temperaturas y alturas de capa.
- Nota: que `visible_smoke_layer_m`, `thermal_layer_m` y `flow_interface_m` sean distintos no es un fallo; son magnitudes físicas distintas.

## Casos ejecutados / comparados

| Caso | CSV pair | JSON pair | Baseline after | Notas | Warnings |
|---|---:|---:|---|---|---:|
| layer_interface_single_room_window | no | no | PASS/NA | before artifact missing; csv pair unavailable; JSON report fallback used where possible | 0 |
| cfast_r0_window_360 | no | no | PASS/NA | before artifact missing; csv pair unavailable; JSON report fallback used where possible | 0 |
| living_room_hallway | no | no | PASS/NA | before artifact missing; csv pair unavailable; JSON report fallback used where possible | 0 |
| v4_co_remote_rooms | no | no | PASS/NA | before artifact missing; csv pair unavailable; JSON report fallback used where possible | 0 |

## Warnings detectados

No se detectaron warnings numéricos con los artefactos disponibles.

## Baseline histórica after

Los reportes after no registran fallos contra su baseline histórica, o no incluyen baseline.

## Diferencias principales

No hay pares before/after suficientes para calcular deltas.

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

# Estado Sesion 2026-06-25

## Resumen

Se cerro la fase de auditoria fisica general y balance de CO (`D1`) como validacion gating. La linea de trabajo cambio explicitamente de "sumar casos M4" a revalidar el motor con balances fisicos e instrumentacion trazable.

## Estado Git Esperado

- Branch: `main`.
- HEAD antes del cierre documental: `b6e355f` — `feat(d1): promote D1 CO balance from WARN to FAIL`.
- Estado previo al cierre: `main` ahead 12 de `origin/main`.
- Tras esta nota, hay un commit documental de cierre y push pendiente/realizado segun el cierre final.

## Validacion

- Suite completa: 18 casos lanzados, 17 OK y 1 timeout preexistente (`long_burnout_3600s`).
- `validate_reference_cases`: 349/354 PASS.
- Los 5 FAIL restantes son los `VALID_GAP` conocidos.
- Physics coherence audit: 5/5 PASS, 0 FAIL, con D1 como FAIL.
- Tests de la fase: 221/221 PASS.

## Auditor Fisico General

Auditor integrado:

- `scripts/simulation/check_physics_coherence.py`
- `scripts/simulation/audit_physics_coherence_suite.py`
- `tests/test_check_physics_coherence.py`

Reglas gating actuales:

- `B1` inversion termica fuerte.
- `C1` suma FED.
- `C2` FED monotona por sala.
- `A2` HRR sin combustible.
- `A3` regimen fuel/full-developed con O2 superior critico.
- `D1` balance CO por sala/paso.

## D1 CO Balance

D1 quedo cerrado como FAIL/gating.

Formula:

```text
delta_co = co_kg[t] - co_kg[t-1]
expected = delta(co_generated_kg_total) + delta(co_net_transport_kg_total) - delta(co_exterior_removed_kg_total)
residual = abs(delta_co - expected)
```

Instrumentacion relevante:

- `co_kg`
- `co_generated_kg_step`
- `co2_generated_kg_step`
- `hcn_generated_kg_step`
- `co_net_transport_kg_step`
- `c_balance_frac`
- `carbon_conservation_error_kg`
- acumulados: `co_generated_kg_total`, `co_net_transport_kg_total`, `co_exterior_removed_kg_total`

Paths corregidos al cerrar D1:

1. `GasExchangeSystem._purge_upper_species_to_exterior_direct` acumula `co_exterior_removed_kg_total`.
2. `ThermalSystem._flush_contaminant_deltas` acumula `co_net_transport_kg_total`.
3. `GasExchangeSystem._release_pending_interior_deliveries` acumula `co_net_transport_kg_total`.

Nota semantica: `co_net_transport_kg_total` es neto amplio. No significa solo room-to-room; incluye intercambio, carry termico y entregas interiores diferidas. La salida a exterior se descuenta con `co_exterior_removed_kg_total`.

Resultados D1:

| CSV | Antes | Despues |
|---|---:|---:|
| `layer_interface_single_room_window` | 1 WARN | 0 findings |
| `v5_m4_ventilation_throttle` | 612 WARN | 0 findings |
| `cfast_ilv_audit` | 0 | 0 findings |

## Checklist Fisico

Se creo/actualizo:

- `docs/validation/MOTOR_PHYSICS_VALIDATION_CHECKLIST.md`

El documento registra items pendientes para revisar:

- HRR, combustible, energia y regimen.
- O2 por sala/capa y acoplamiento con HRR.
- CO/CO2/HCN, generacion, transporte y balance de carbono.
- Humo/soot, visibilidad y FED.
- Temperaturas, capas, plano neutro e isoterma 150 C.
- Modelo bizona, flotabilidad y transporte multi-room/multi-planta.
- Puertas/ventanas, reventilacion y efectos remotos.
- Presion y direccion de flujos.
- Paredes, radiacion, almacenamiento y reradiacion.
- Bateria futura CFAST/escenarios realistas.

## Decisiones Importantes

- No implementar `D2` CO/CO2 ratio todavia.
- Motivo: `co2_upper_ppm` viene de `co2_upper` como tracer/fraccion molar, mientras CO upper ppm viene de masa. La comparacion directa puede mezclar dos modelos distintos.
- La regla naive "CO sube sin fuego local" queda descartada en multi-room; puede ser transporte real.
- HVAC y visual FP quedan fuera de foco para esta linea.
- No empezar rewrite global del motor; avanzar por reconstruccion guiada por validacion y subsistemas.

## Proximo Trabajo Recomendado

### Actualizacion posterior: S0 humo y E1 combustible

Se cerro S0 como regla gating tras regenerar corpus CSV:

- `scripts/simulation/audit_physics_coherence_suite.py`: 11/11 PASS, 0 FAIL findings.
- `--rules S0`: 11/11 PASS (9 CSVs con esquema nuevo ejercitan la regla, 2 `p2h_diag_*` legacy hacen skip graceful).
- `--rules E1`: 11/11 PASS (9 CSVs con esquema nuevo ejercitan la regla, 2 `p2h_diag_*` legacy hacen skip graceful).
- `tests/test_check_physics_coherence.py`: 119/119 PASS.

Fixes de S0:

- ACH/infiltracion suma humo retirado a `smoke_vented_total_kg`.
- Purga por ventilacion natural suma humo retirado a `smoke_vented_total_kg`.
- Humo removido de una sala y pendiente de entrega interior se expone como `smoke_in_transit_kg`.
- `SmokeModel.recompute_layer_from_mass()` ya no destruye masa de humo sub-umbral.

Fix semantico de E1:

- E1 usa `solid_fuel_remaining_MJ`, no `fuel_remaining_MJ`.
- Motivo: `fuel_remaining_MJ` queda como campo legacy/visible y puede mezclar estado de objetos/retained unburned; E1 necesita el tanque solido exacto que se decrementa con `fuel_consumed_MJ_total`.

Proximo trabajo recomendado:

1. Mantener D1, E1 y S0 como gating.
2. Siguiente bloque: S1 per-sala o O1/O2, pero solo tras instrumentar acumuladores faltantes.
3. Para S1 faltan `smoke_generated/vented/deposited/net_transport` por sala.
4. Para O1 faltan transporte y exterior de O2 por masa.
5. No tocar fisica global ni tolerancias hasta tener plan explicito.

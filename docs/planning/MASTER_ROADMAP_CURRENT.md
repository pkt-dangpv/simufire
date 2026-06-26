# Hoja de ruta activa de SimuFire

Fecha: 2026-06-26
Estado: fuente de verdad operativa para continuar trabajo
Alcance: credibilidad fisica del motor, balances de conservacion, validacion CFAST restante y limites de cambios globales.

## Regla principal

La prioridad actual es que el motor sea fisicamente auditable. No perseguir un baseline bonito si eso conserva datos incoherentes.

Cada cambio debe estar ligado a una de estas lineas:

1. Cerrar incoherencias fisicas con auditoria reproducible.
2. Mejorar instrumentacion y balances sin cambiar fisica accidentalmente.
3. Mantener validacion CFAST sin tocar tolerancias para esconder fallos.
4. Documentar explicitamente lo que queda como `VALID_GAP`, caso legacy/control o deuda Phase 3+.

Antes de tocar motor:

- confirmar `git status --short --branch`;
- revisar `docs/HANDOFF_CURRENT_STATE.md`;
- revisar `docs/validation/MOTOR_PHYSICS_VALIDATION_CHECKLIST.md`;
- ejecutar o justificar por que no se ejecuta `python scripts\simulation\validation_guardrails.py --verbose`;
- no modificar reports, baselines ni tolerancias para forzar PASS.

## Estado actual conocido

- Rama esperada: `main`, sincronizada con `origin/main`.
- Handoff vigente: `docs/HANDOFF_CURRENT_STATE.md` rev 16.
- Ultimo estado documentado: physics coherence + D1 CO balance gating, O1 bulk O2 WARN-clean.
- Suite referencia: **349/354 PASS**.
- Los 5 FAIL restantes son los `VALID_GAP` conocidos:
  - Grupo A: O2 en `cfast_r0_window_360`.
  - Grupo C: temperatura en `cfast_corridor_chain`.
- Physics coherence audit: **5/5 PASS**, 0 FAIL, D1 ya `FAIL`/gating.
- Full reference suite: 18 casos lanzados, 17 OK y 1 timeout preexistente (`long_burnout_3600s`).
- Tests Python de la fase physics coherence: **221/221 PASS**.

## Cambio de enfoque

La linea M4/ILV ya no es el unico centro. El proyecto paso a una revalidacion fisica integral:

- HRR, combustible, energia y regimen de combustion.
- O2 por capa/sala y acoplamiento con HRR.
- CO/CO2/HCN, generacion local, transporte y balance de carbono.
- Humo/soot, visibilidad, FED y tenabilidad.
- Temperaturas upper/lower, capas, presion, plano neutro e isoterma 150 C.
- Modelo bizona, ventilacion por puertas/ventanas, flotabilidad y transporte multi-room/multi-planta.
- Paredes, radiacion, almacenamiento termico y reradiacion.

Documento maestro:

- `docs/validation/MOTOR_PHYSICS_VALIDATION_CHECKLIST.md`

## Auditores vigentes

### Auditor fisico general

Archivos:

- `scripts/simulation/check_physics_coherence.py`
- `scripts/simulation/audit_physics_coherence_suite.py`
- `tests/test_check_physics_coherence.py`

Reglas gating cerradas:

| Regla | Severidad | Estado |
|---|---|---|
| `B1` inversion termica fuerte | FAIL | Gating |
| `C1` FED suma | FAIL | Gating |
| `C2` FED monotonica | FAIL | Gating |
| `A2` HRR sin combustible | FAIL | Gating |
| `A3` regimen vs O2 superior critico | FAIL | Gating |
| `D1` balance CO por sala/paso | FAIL | Gating |

### Auditor ILV por capas

Archivos:

- `scripts/simulation/check_ilv_layer_coherence.py`
- `scripts/simulation/audit_ilv_layer_coherence_suite.py`

Uso:

- Detecta HRR significativo con `o2_upper` critico y throttle/regimen incoherente.
- `fp_ilv_upper_throttle_off` sigue siendo control intencional y puede fallar si se incluye.

## Lineas cerradas

### M4 ILV upper-O2 throttle guard

Estado:

- `fire_o2_upper_throttle_enabled` existe como fix fisico gated.
- Default global: `false`.
- Activacion global: bloqueada hasta migracion coordinada.
- No mezclar con `fire_o2_canonical_enabled` sin plan explicito: ambos mecanismos compiten.
- Casos correctos con M4:
  - `fp_ilv_upper_throttle_on`
  - `layer_interface_single_room_window`
  - `v5_m4_ventilation_throttle`

Decisiones vigentes:

- `v5_ventilation_hrr_spike` queda como legacy/control pre-M4.
- `v5_m4_ventilation_throttle` es la referencia fisica corregida.
- No usar M4 para intentar cerrar Grupo A sin plan Phase 3+/O2 separado.

### S0 smoke global conservation

Estado: cerrado como `FAIL`/gating.

Cobertura:

- Valida `sum(smoke_kg) + smoke_in_transit_kg` contra generado menos venteado menos depositado.
- Corrigio contabilidad de ACH, purga por ventilacion natural, humo interior diferido y masa sub-threshold.
- Corpus fresco: 11/11 CSVs PASS, 0 findings.

### D1 CO balance

Estado: cerrado como `FAIL`/gating.

Invariante:

```text
delta_co = co_kg[t] - co_kg[t-1]
expected = delta(co_generated_kg_total)
           + delta(co_net_transport_kg_total)
           - delta(co_exterior_removed_kg_total)
residual = abs(delta_co - expected)
```

Correcciones relevantes:

- `GasExchangeSystem._purge_upper_species_to_exterior_direct`
- `ThermalSystem._flush_contaminant_deltas`
- `GasExchangeSystem._release_pending_interior_deliveries`

Nota: `co_net_transport_kg_total` es neto amplio e incluye intercambio, arrastre termico/hot-gas carry y entregas interiores diferidas. Exterior se contabiliza aparte.

### E1 fuel balance

Estado: corregido para usar combustible solido explicito.

Decision:

- E1 valida `solid_fuel_remaining_MJ` contra `fuel_consumed_MJ_total`.
- No usar `fuel_remaining_MJ` legacy visible como fuente principal: puede incluir retained/unburned/object state y dar falsos residuales.

### O1 bulk O2 balance

Estado: **WARN-clean**, no `FAIL`/gating todavia.

Invariante:

```text
delta_bulk = (o2[t] - o2[t-1]) * air_mass_kg
expected   = -delta(o2_consumed_bulk_kg_total)
             + delta(o2_exterior_net_kg_total)
             + delta(o2_net_transport_kg_total)
             + delta(o2_zone_sync_kg_total)
residual   = abs(delta_bulk - expected)
```

Resultado actual:

- 11/11 PASS.
- 0 O1 findings.
- Max residual < `4e-4 kg`.
- Sigue como WARN hasta validarse en corpus mas amplio, largo y multi-planta.

Correcciones importantes:

- `SimulationStateBuilder` exporta `room.o2` real, no valor con correccion molar CO2 aplicada.
- O1 usa `o2_consumed_bulk_kg_total`, no `o2_consumed_kg_total_all`.
- `_apply_room_o2_mass_delta` acumula delta post-clamp real.

## Caveats conocidos

### CO2 upper dual tracking

`co2_upper_ppm` es tracer-derived (`co2_upper * 1e6`), mientras CO upper ppm es mass-derived.

Consecuencia:

- Reglas CO/CO2 ratio quedan bloqueadas.
- No implementar D2 hasta resolver o documentar la semantica dual de `co2_upper` / `co2_upper_kg`.

### O1 no sustituye balance zonal

O1 audita `room.o2` bulk. No cierra todavia la conservacion de `o2_upper` / `o2_lower`.

Pendiente:

- Balance zonal O2 por capa.
- Separacion clara de combustion, transporte y zone-sync.
- Reconciliacion con future two-zone canonico.

## Fallos CFAST vivos

Los 5 FAIL restantes siguen siendo estructurales y no pertenecen a D1/S0/O1:

| Grupo | Checks | Estado |
|---|---|---|
| A - `cfast_r0_window_360` | 3 checks O2 | VALID_GAP Phase 2/3+, requiere arquitectura O2/two-zone |
| C - `cfast_corridor_chain` | 2 checks temperatura | VALID_GAP Phase 3+, requiere presion/intercambio two-zone |

No cambiar tolerancias ni reclasificar estos FAIL sin decision cientifica explicita.

## Proxima linea recomendada

### Prioridad 1 - O2 + energia/HRR

Motivo: tras cerrar D1/S0 y dejar O1 WARN-clean, el siguiente bloque natural es cerrar la coherencia entre combustible, HRR, consumo O2 y energia entregada.

Primeros pasos:

1. Inventariar columnas CSV/JSON ya disponibles para HRR/energia/O2.
2. Separar consumo O2 bulk, upper, lower y plume.
3. Definir si la proxima regla sera WARN o FAIL.
4. No anadir una segunda ruta fisica de consumo O2: OES ya aplica Thornton rate.
5. Evitar doble conteo con `fire_o2_stoich_consumption_enabled`, que ahora debe tratarse como tracking/diagnostico.

Posibles reglas:

- HRR x dt vs consumo de combustible solido.
- O2 consumido por combustion vs energia liberada.
- No HRR sostenido con combustible solido agotado y pool no disponible.
- Coherencia entre `solid_pyrolysis_kw`, `fresh_flame_target_kw`, `smolder_hrr_target_kw`, `pool_release_hrr_target_kw` y `hrr_kw`.

### Prioridad 2 - Corpus O1 ampliado

Mantener O1 como WARN hasta probar:

- escenarios largos;
- multi-room;
- multi-planta;
- ventilacion exterior con eventos;
- HVAC solo cuando el nucleo este estable.

### Prioridad 3 - CO2 semantics

Resolver/documentar `co2_upper_ppm` vs `co2_upper_kg` antes de reglas CO/CO2 ratio.

### Prioridad 4 - Phase 3+ two-zone canonico

Necesario a largo plazo para cerrar los VALID_GAP:

- `room.o2` derivado, no fuente independiente;
- combustion vinculada a capa fisica correcta;
- presion/doorway ODE;
- recalibracion completa de casos CFAST afectados.

## Criterios de no-regresion

Antes de commit de motor o validacion:

```powershell
python scripts\simulation\validation_guardrails.py --verbose
python scripts\simulation\audit_physics_coherence_suite.py
python scripts\simulation\audit_ilv_layer_coherence_suite.py --allow-findings
git diff --check
```

Para cierre de fase amplia:

```powershell
powershell -ExecutionPolicy Bypass -File sim\validation\run_full_reference_suite.ps1 -TimeoutSeconds 900
python -m unittest
```

Para cambios solo de documentacion:

```powershell
python scripts\check_docs_links.py
git diff --check
```

## Puntos de entrada vivos

- `docs/HANDOFF_CURRENT_STATE.md`: estado operativo actual.
- `docs/validation/MOTOR_PHYSICS_VALIDATION_CHECKLIST.md`: checklist fisico maestro.
- `docs/validation/STATUS_VALIDATION.md`: fuente de verdad de validacion legacy.
- `docs/validation/GAPS_INVENTORY.md`: conteo de gaps non-gating.
- `docs/validation/GUARDRAILS_STATUS.md`: estado de guardrails.
- `docs/architecture/PHASE_5A_O2UPPER_SWEEP_RESULTS.md`: descarte per-case Grupo A.
- `docs/architecture/PHASE_3_DOORWAY_PRESSURE_ODE_PLAN.md`: plan pendiente para corridor_chain.
- `docs/architecture/ILV_COMBUSTION_REGIME_PLAN.md`: diseno ILV.

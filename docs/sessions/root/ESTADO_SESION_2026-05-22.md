# Estado de sesión — 2026-05-22

## Resumen ejecutivo

Sesión centrada en estabilizar la validación tras descubrir que el estado documentado del 21/05 dependía de reportes obsoletos y de regresiones introducidas entre el último commit verde (`b844be6`) y HEAD.

Resultado principal: la regresión interna de **17 fallos** fue diagnosticada y reducida de **26/43 PASS** a **42/43 PASS**, sin rebaseline y con cambios mínimos. Queda un único fallo interno activo (`g3_gie_ppv_post_knockdown`) y un fallo gating externo (`cfast_multifuel_t180_temp_upper_c`) atribuido a reporte obsoleto que debe refrescarse.

Referencia detallada: `docs/audits/AUDITORIA_REGRESION_2026-05-22.md`.

---

## Estado validación

### Suite interna de 43 casos

Último estado documentado por auditoría:

```text
Antes de fixes:   26/43 PASS
Después de fixes: 42/43 PASS
Fallo restante:   g3_gie_ppv_post_knockdown
```

El fallo restante:

| Caso | Check | Expected | Actual | Estado |
|---|---|---:|---:|---|
| `g3_gie_ppv_post_knockdown` | `time_room_1_smoke_below_0_1kg_post_vent_s` | 361 ±3 s | 339 s | Pendiente |

Diagnóstico posterior: el fallo de `g3` se debe al mismo mecanismo que `living_room_hallway`: `background_o2_exchange_multiplier` global está en `0.0`, pero el baseline de este caso se calibró con comportamiento equivalente a `1.0`. Recomendación pendiente: añadir override por caso:

```json
"background_o2_exchange_multiplier": 1.0
```

en `sim/validation/cases/g3_gie_ppv_post_knockdown.json`, sin tocar baseline ni física global.

### Suite externa/reference

Último estado reportado:

```text
validate_reference_cases.py: 291/292 required
Fallo gating: cfast_multifuel_t180_temp_upper_c
Known gaps: arquitectónicos, required=false
```

Diagnóstico: `cfast_multifuel_t180_temp_upper_c` no parece regresión física nueva. El audit de frescura indica que `sim/validation/reports/cfast_multi_fuel_couch_tv.json` es anterior al baseline actualizado. Acción pendiente: re-ejecutar `cfast_multi_fuel_couch_tv` para refrescar report y volver a correr `validate_reference_cases.py`.

### Freshness audit

Último audit reportado:

| Severidad | Ítem | Interpretación |
|---|---|---|
| CRIT | `score_mismatch` | `ESTADO` documenta 292/292 pero `reference_checks.json` tiene 291/292 por reporte obsoleto |
| WARN | `g3_gie_ppv_post_knockdown` | `baseline.all_pass=false`, único fail interno activo |
| WARN | `cfast_multi_fuel_couch_tv` | reporte 4 min anterior al baseline |
| WARN | `living_room_hallway` | report anterior a último edit del case; considerado inofensivo tras diagnóstico |
| INFO | `dt_sweep_*` orphan reports | runs ad-hoc normales |
| INFO | 13 baselines con BOM | usar `encoding="utf-8-sig"` en tooling nuevo |

---

## Fixes de regresión aplicados

Según `docs/audits/AUDITORIA_REGRESION_2026-05-22.md`, se aislaron tres causas raíz:

### 1. Thermal losses reducidas indebidamente

Archivo: `sim/core/ThermalSystem.gd`

Se restauraron tasas térmicas:

```gdscript
upper_to_lower_loss_rate = 0.025
upper_to_ambient_loss_rate = 0.008
```

Mecanismo: las tasas reducidas retenían demasiado calor en la capa superior y sumergían sondas de hallway en zona caliente.

### 2. `dp_buoyancy` eliminado en presión/venting

Archivo: `sim/core/GasExchangeSystem.gd`

Se restauró el cálculo de sobrepresión por boyanza de gas caliente para todas las salas, no sólo para plantas con `floor_level_z_m > 0`.

Mecanismo: sin `dp_buoyancy`, la sala de origen quedaba sin sobrepresión, se debilitaba el background drive y se alteraba el intercambio entre salas.

### 3. `background_o2_exchange_multiplier`

Archivo/caso: `sim/validation/cases/living_room_hallway.json`

Se añadió override local:

```json
"background_o2_exchange_multiplier": 1.0
```

No se cambió el default global, que queda en `0.0` para que el O2 inter-sala normal lo gestione `OxygenExchangeSystem`.

---

## Casos recuperados

La auditoría documenta 16 casos recuperados:

- `living_room_hallway`
- `layer150_tenability`
- `postfire_decay`
- `ul_exterior_water_knockdown`
- `confinement_open_close`
- `v1_backdraft_accumulation`
- `v2_sealed_room_o2_depletion`
- `v3_hallway_fed_exposure`
- `v7_underventilated_co_peak`
- `g1_gie_confinement_attack`
- `g2_gie_transitional_attack`
- `g4_gie_delayed_entry_hazard`
- `wind_assisted_exterior_spread`
- `tc_array_iso9705`
- `conservation_transport`
- `victim_fed_incapacitation`

Verificación incremental registrada:

| Caso | Resultado |
|---|---|
| `living_room_hallway` | 6/6 PASS |
| `postfire_decay` | 8/8 PASS |
| `two_storey_smoke` | 8/8 PASS |

---

## Acciones inmediatas pendientes

1. Aplicar override local en `g3_gie_ppv_post_knockdown.json`:

```json
"background_o2_exchange_multiplier": 1.0
```

2. Re-ejecutar:

```powershell
powershell -ExecutionPolicy Bypass -File sim/validation/run_case.ps1 -CaseName g3_gie_ppv_post_knockdown
powershell -ExecutionPolicy Bypass -File sim/validation/run_case.ps1 -CaseName cfast_multi_fuel_couch_tv
```

3. Validar:

```powershell
python scripts/simulation/validate_reference_cases.py
python scripts/simulation/audit_validation_freshness.py
```

4. Objetivo esperado tras esas acciones:

```text
Suite interna:     43/43 PASS
Reference checks:  292/292 required PASS
Freshness audit:   sin CRIT
```

No hacer rebaseline salvo que un diagnóstico nuevo lo justifique explícitamente.

---

## Próxima fase recomendada

No saltar directamente a Phase 2 two-zone hasta cerrar el estado reproducible.

Fase siguiente recomendada:

### Phase 1.5D — Validation Hardening

Objetivo: hacer que los scores sean reproducibles y difíciles de falsear por reports obsoletos.

Tareas:

- Runner único que ejecute casos stale, `validate_reference_cases.py` y `audit_validation_freshness.py`.
- Fallar si hay `score_mismatch`.
- Listar oficialmente gaps non-gating arquitectónicos.
- Mantener diagnósticos específicos para benchmarks frágiles:
  - `cfast_r0_window_360`
  - `cfast_multi_fuel_couch_tv`
  - `g3_gie_ppv_post_knockdown`
- Usar `encoding="utf-8-sig"` en tooling Python que lea baselines directamente.

Después de esa fase, pasar a Phase 2 two-zone con una red de validación más fiable.

---

## Notas críticas

- Los 85 gaps CFAST reportados son arquitectónicos (`required=false`), principalmente one-zone vs two-zone.
- `cfast_multi_fuel_couch_tv` pasa baseline interno, pero puede fallar contra CFAST si el report está stale; esta diferencia debe vigilarse.
- `g3_gie_ppv_post_knockdown` no debe rebaselinarse todavía: el diagnóstico apunta a override local faltante, no a tolerancia incorrecta.
- La hipótesis inicial de `smoke_buoyancy_boost` como causa principal quedó reemplazada por la auditoría final: las causas reales fueron `ThermalSystem`, `dp_buoyancy` y `background_o2_exchange_multiplier`.

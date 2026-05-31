# Estado de sesión — 2026-05-31

## Resumen ejecutivo actual

Sesión cerrada en Phase 2A — doorway hot-gas O2 upper routing.

- Estado validación actual: **373/373 required PASS**
- Gaps reales activos: **3 non-gating**
- Total checks registrados: **520**
- Guardrails: **ALL PASS**
- Unit tests: **13/13 OK**
- Base física: `e4564e3` — `phase-2a: route doorway hot-gas oxygen by upper layer`
- Último sync docs/reports: `d50a969` — `docs: sync Phase 2A validation state`
- Working tree al guardar este estado: limpio antes de añadir esta nota de sesión.

## Gaps reales activos

| Prioridad | Gap | Fase prevista | Nota |
|-----------|-----|---------------|------|
| 1 | `cfast_co2_stratification_pending` | Phase 2B | Siguiente objetivo. Falta tracking CO2 upper/lower bidireccional. |
| 2 | `cfast_hvac_two_zone_feed_pending` | Phase 2C | Gap específico del benchmark CFAST low-supply/high-return, no de todo HVAC residencial. |
| 3 | `cfast_overpressure_sealed_pending` | Phase 3 | Falta ODE de presión termodinámica por zona. |

## Historial previo de la sesión

Los apartados siguientes conservan el estado intermedio anterior a los cierres de GAP-8 y GAP-7. El estado actual definitivo está en el resumen superior y en la actualización final de este documento.

### Checks y guardrails

- `build_ghanekar_kitchen_checks()` promovido a required para los 5 checks de cocina:
  - O2 response
  - FED 0.3
  - FED 1.0
  - CO IDLH
  - flashover sala de fuego
- `reference_checks.json` regenerado: `required_count` pasa de 367 a 372; `known_gap_count` permanece en 6.
- `gap_inventory_check.py` ajustado para reconfigurar stdout a UTF-8 en Windows y evitar el fallo CP1252 al imprimir símbolos.

### Documentación

- `docs/GAPS_INVENTORY.md` sincronizado con 372/372 required y 6 gaps reales.
- `docs/PLAN_TRABAJO.md` actualizado con HEAD base `156fb81`, total checks 521 y roadmap de 6 gaps.
- Se aclaró que `cfast_t240_hrr_ventilation_limited` es un check legacy cerrado por tolerancia, mientras `cfast_hrr_ventilation_limited_f2_pending` sigue siendo el gap arquitectónico.

### Decisión HVAC guardada

El gap `cfast_hvac_two_zone_feed_pending` no debe interpretarse como "todo HVAC alimenta la capa baja".

El benchmark CFAST actual `cfast_hvac_residential` representa:

```text
impulsión de aire exterior baja: 0.25 m
retorno alto: 2.30 m
caudal: 0.08 m3/s
```

Eso es realista para un caso low-supply/high-return o ciertos forced-air/ventilation benchmarks, pero no para todos los sistemas residenciales.

Presets HVAC documentados para implementar:

| Preset | Configuración | Uso |
|--------|---------------|-----|
| `hvac_cfast_low_supply_high_return` | supply 0.25 m, return 2.30 m, aire exterior alto | Reproducir benchmark CFAST y cerrar GAP-9 |
| `hvac_us_forced_air_floor_supply` | impulsión baja/suelo, retorno alto o central, recirculación dominante | Vivienda norteamericana forced-air |
| `hvac_es_ceiling_ducts_recirc` | impulsión alta + retorno alto, `outside_air_fraction=0.0` | Conductos de falso techo típicos en España; redistribuye humo/calor, no repone O2 |
| `hvac_balanced_hrv_erv` | aire exterior bajo/medio, extracción baños/cocina, caudal menor | Ventilación mecánica balanceada |

## Verificación ejecutada

```powershell
python scripts\simulation\validate_reference_cases.py
# PASS: 372/372 required checks passed
# Known gaps: 6 non-gating checks did not pass

python scripts\simulation\validation_guardrails.py
# ALL GUARDRAILS PASS

python scripts\simulation\gap_inventory_check.py
# OK — reporte y documentación sincronizados

python tests\test_guardrails.py
# Ran 13 tests — OK
```

## Archivos modificados pendientes

```text
docs/GAPS_INVENTORY.md
docs/PLAN_TRABAJO.md
scripts/simulation/gap_inventory_check.py
scripts/simulation/validate_reference_cases.py
sim/validation/reports/reference_checks.json
ESTADO_SESION_2026-05-31.md
```

## Próximo paso recomendado

1. Revisar diff final.
2. Commit de sincronización:

```text
docs: sync gap roadmap after Phase 2 validation hardening
```

3. Empezar Phase 1.7 (`ghanekar_flashover_0_9m_known_gap`) o Phase 2 cont. (`cfast_hrr_ventilation_limited_f2_pending`) según prioridad.

---

## Actualización posterior — commit `cc48382`

Phase 1.7 quedó cerrada después de este estado inicial.

- Commit: `cc48382` — `phase-1.7: reduce thermal gradient band for bedroom case, close flashover GAP-1`
- Estado validación: **373/373 required PASS**
- Gaps reales activos: **5 non-gating**
- `ghanekar_flashover_0_9m_known_gap`: cerrado y promovido a required=True.

Resultados clave:

| Check | Resultado | Rango |
|-------|-----------|-------|
| `time_room_0_temp_0_9m_above_600c_s` | 166.75s | [156,216]s |
| `peak_temp_upper_c_global` | 620.5°C | [450,650]°C |
| `time_room_2_o2_below_20_4pct_s` | 215.6s | [168,228]s |

Overrides usados en `sim/validation/cases/ghanekar_bedroom_hallway.json`:

```json
"fire_alpha_kw_s2": 0.035,
"outside_open_upper_heat_boost": 0.20
```

Siguiente prioridad real: `cfast_hrr_ventilation_limited_f2_pending` (Phase 2 cont., HRR cap por `o2_upper`).

---

## Actualización posterior — Phase 2A cerrada y estado listo para retomar

Se cerraron también GAP-8 y GAP-7 después del estado anterior.

### Commits relevantes posteriores

| Commit | Descripción |
|--------|-------------|
| `a21326e` | `phase-2: close GAP-8 — fire_o2_upper_hrr_blend opt-in (gaps 5->4)` |
| `c435afb` | `docs: sync GAP-8 validation report` |
| `e4564e3` | `phase-2a: route doorway hot-gas oxygen by upper layer` |
| `d50a969` | `docs: sync Phase 2A validation state` |

### Estado actual validado

- Base física actual: `e4564e3`
- Último commit de sincronización docs/reports: `d50a969`
- Checks required: **373/373 PASS**
- Gaps reales activos: **3 non-gating**
- Total checks registrados: **520**
- Guardrails: **ALL PASS**
- Unit tests: **13/13 OK**
- Working tree tras `d50a969`: limpio

### Qué quedó cerrado

#### GAP-8 — `cfast_hrr_ventilation_limited_f2_pending`

- Implementado `fire_o2_upper_hrr_blend` opt-in en `CombustionSystem.gd` y `SimulationEngine.gd`.
- Default `0.0` = no-op.
- Stub eliminado.
- Check real: `cfast_t240_hrr_structural_ratio`, actual `1.91`, máximo `2.5`, PASS.
- Gaps: 5 -> 4.

#### GAP-7 — `cfast_hall_upper_o2_doorway_pending`

- Implementado `doorway_o2_upper_routing_gain` opt-in en `OxygenExchangeSystem.gd` y exportado en `SimulationEngine.gd`.
- En `cfast_two_room_door_open.json`: `doorway_o2_upper_routing_gain=1.0`.
- Los checks hall O2 comparan ahora `sim_field="o2_upper"` contra CFAST ULO2.
- Tolerancias tight:
  - t=120: `0.020`
  - t=240: `0.025`
  - t=360: `0.060`
  - RMSE: `<=0.060`
- Residual estructural t=360: SF mantiene fuego activo mientras CFAST extingue por depleción de O2 upper.
- Gaps: 4 -> 3.

### Gaps activos restantes

| Prioridad | Gap | Fase | Nota |
|-----------|-----|------|------|
| 1 | `cfast_co2_stratification_pending` | Phase 2B | Siguiente objetivo. Extender el patrón two-zone a CO2 upper/lower. |
| 2 | `cfast_hvac_two_zone_feed_pending` | Phase 2C | Preset HVAC low-supply/high-return; no representa todos los HVAC residenciales. |
| 3 | `cfast_overpressure_sealed_pending` | Phase 3 | ODE de presión termodinámica por zona; muy disruptivo. |

### Verificación ejecutada

```powershell
python scripts\simulation\validate_reference_cases.py
# PASS: 373/373 required checks passed
# Known gaps: 3 non-gating checks did not pass

python scripts\simulation\validation_guardrails.py
# ALL GUARDRAILS PASS

python tests\test_guardrails.py
# Ran 13 tests — OK
```

## Prompt listo para la próxima sesión

```text
Estamos en SimuFire, commit base físico e4564e3 y sync docs/reports d50a969.
Estado actual: 373/373 required PASS, 3 gaps non-gating.

Objetivo: cerrar el siguiente gap prioritario:
cfast_co2_stratification_pending

Contexto:
- Phase 2A ya cerró cfast_hall_upper_o2_doorway_pending con doorway_o2_upper_routing_gain opt-in.
- Ese patrón enruta O2 upper por hot-gas doorway en OxygenExchangeSystem.gd.
- Ahora hay que extender la lógica a CO2 stratification: SF aún mezcla CO2 demasiado uniforme, mientras CFAST retiene CO2 en upper layer.
- No tocar presión Phase 3 ni HVAC Phase 2C en este turno.

Tareas:
1. Leer GAPS_INVENTORY.md, PLAN_TRABAJO.md y validate_reference_cases.py para confirmar el estado exacto del gap.
2. Inspeccionar cómo se calcula/transporta CO2 actualmente en RoomModel.gd, GasExchangeSystem.gd, OxygenExchangeSystem.gd, ThermalSystem.gd y SimulationEngine.gd.
3. Diseñar un cambio opt-in default no-op para CO2 upper/lower stratification, siguiendo el estilo de doorway_o2_upper_routing_gain.
4. Implementar el mínimo necesario para cerrar cfast_co2_stratification_pending sin romper required checks.
5. Convertir el stub en check real passing o eliminarlo si queda cubierto por checks reales existentes.
6. Regenerar reports, correr:
   - python scripts/simulation/validate_reference_cases.py
   - python scripts/simulation/validation_guardrails.py
   - python tests/test_guardrails.py
7. Actualizar GAPS_INVENTORY.md y PLAN_TRABAJO.md: gaps 3->2 si procede.
8. Commit final con mensaje claro.

Criterios de aceptación:
- 373/373 required PASS o más si se añaden checks required.
- known_gap_count pasa de 3 a 2.
- Guardrails PASS.
- Unit tests 13/13 OK.
- Default global no-op salvo caso calibrado/opt-in.
```

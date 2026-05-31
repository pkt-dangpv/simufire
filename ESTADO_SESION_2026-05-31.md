# Estado de sesión — 2026-05-31

## Resumen ejecutivo

Sesión de auditoría y sincronización tras Phase 2 CO vent-limited.

- Estado validación actual: **372/372 required PASS**
- Gaps reales activos: **6 non-gating**
- Total checks registrados: **521**
- Guardrails: **ALL PASS**
- Unit tests: **13/13 OK**
- HEAD base: `156fb81` (`main = origin/main`) — `Add CO vent-limited phase to combustion model`
- Working tree: cambios pendientes en docs, guardrails/checks y `reference_checks.json`; no commiteado en esta sesión.

## Gaps reales activos

| Prioridad | Gap | Fase prevista | Nota |
|-----------|-----|---------------|------|
| 1 | `ghanekar_flashover_0_9m_known_gap` | Phase 1.7 | T_upper llega a ~608°C, pero T@0.9m no cruza 600°C por gradiente/interfaz; requiere suavizar progresión del colchón o mejorar criterio vertical. |
| 2 | `cfast_hrr_ventilation_limited_f2_pending` | Phase 2 cont. | Falta HRR cap real por `o2_upper`; el check legacy `cfast_t240_hrr_ventilation_limited` pasa por tolerancia, pero el gap arquitectónico sigue vivo. |
| 3 | `cfast_hall_upper_o2_doorway_pending` | Phase 2A | Falta doorway two-zone: gas caliente pobre en O2 entra por la parte alta del vano. |
| 4 | `cfast_co2_stratification_pending` | Phase 2B | Falta tracking CO2 upper/lower bidireccional. |
| 5 | `cfast_hvac_two_zone_feed_pending` | Phase 2C | Gap específico del benchmark CFAST low-supply/high-return, no de todo HVAC residencial. |
| 6 | `cfast_overpressure_sealed_pending` | Phase 3 | Falta ODE de presión termodinámica por zona. |

## Cambios hechos en esta sesión

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


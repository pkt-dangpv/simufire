# SimuFire — Handoff: estado actual

Fecha: 2026-06-25

## Rama y commits recientes

- Rama: `main`
- Commits del carril actual (más reciente primero):

```
54a701b promote(e1): E1 fuel balance rule WARN→FAIL after clean corpus validation
e7d73e6 fix(e1): increase fuel_remaining_MJ log precision from %.2f to %.6f
a6eff5a feat(e1): add E1 fuel balance rule, diagnostic case, and tests
6105dcd feat(e1): add fuel_consumed_MJ_step/total tracking for energy audit
04310df docs(o2): correct O2 diagnosis, add D2 structural tests, update handoff
d7e4aba fix(o2): eliminate double-count in stoich O2 tracking
```

## Carriles cerrados

### E1 fuel balance — CERRADO

- Regla E1 implementada en `scripts/simulation/check_physics_coherence.py`.
- Invariante: `fuel_remaining_MJ[t] = fuel_remaining_MJ[t-1] - fuel_consumed_MJ_step[t]`
  usando totales acumulados para evitar aliasing por `log_interval`.
- Severity promovida de WARN a FAIL (commit 54a701b). Corpus 7 CSVs: 0 findings.
- Caso diagnóstico: `sim/validation/cases/fuel_balance_diag_sealed.json` →
  `sim/validation/reports/fuel_balance_diag_sealed.csv`. Residuales en 10⁻⁷–10⁻⁶ MJ (suelo numérico).
- Precisión fix (commit e7d73e6): `fuel_remaining_MJ` de `%.2f` a `%.6f` en SimulationLogWriter.
- Tests: `TestE1FuelTracking` (13 tests), `TestCheckE1` (17 tests).
- Campos nuevos en RoomModel: `fuel_consumed_MJ_step`, `fuel_consumed_MJ_total` (ver abajo).

### D1 CO balance — CERRADO

- Regla D1 implementada en `scripts/simulation/check_physics_coherence.py`.
- Severity promovida de WARN a FAIL (commit b6e355f).
- 18 casos de referencia: 0 findings D1.
- Tests estructurales: `TestD1COTrackingPaths` en `tests/test_carbon_balance.py` (8 tests).
- Tres paths corregidos: `_purge_upper_species_to_exterior_direct` (GasExchangeSystem),
  `_flush_contaminant_deltas` (ThermalSystem), `_release_pending_interior_deliveries` (GasExchangeSystem).

### O2/HRR audit + corrección de doble-conteo — CERRADO

**Diagnóstico corregido:** La auditoría inicial sostuvo que `fire.o2_consumption_kg_per_MJ`
nunca se aplicaba. Eso era incorrecto. `OxygenExchangeSystem.gd` ya aplica la tasa Thornton
(0.076 kg O2/MJ) en dos sitios:

- `room.o2` bulk (línea 356): `consumed = (hrr_kw / 1000) * fire.o2_consumption_kg_per_MJ * dt`
- `room.o2_upper` (líneas 386–395): misma tasa, condicional a `lower_frac ≥ 0.15`

Un MVP previo (commit 03372fe) añadió una segunda deducción idéntica en CombustionSystem con
`fire_o2_stoich_consumption_enabled=true`, causando doble-conteo en `o2_upper`.

**Fix (commit d7e4aba):** El bloque de CombustionSystem se convirtió a tracking-only.
Ya no modifica `room.o2_upper`. Solo calcula y acumula `o2_consumed_kg_step/total` para
diagnóstico en CSV. OES sigue siendo el único escritor de la depleción física.

## Estado actual de flags

| Flag | Default | Semántica |
|------|---------|-----------|
| `fire_o2_stoich_consumption_enabled` | `false` | Emite contabilidad Thornton en CSV; no modifica física. |
| `fire_o2_canonical_enabled` | `false` | No combinar con el anterior sin plan explícito. |

## Campos nuevos en RoomModel

| Campo | Tipo | Semántica |
|-------|------|-----------|
| `o2_consumed_kg_step` | `float` | Thornton O2 consumido este paso (shadow de OES). 0 si flag=false. |
| `o2_consumed_kg_total` | `float` | Acumulado. 0 si flag=false. |
| `fuel_consumed_MJ_step` | `float` | `solid_fuel_demand_MJ` post-escala este paso (CombustionSystem). |
| `fuel_consumed_MJ_total` | `float` | Acumulado. Usado por regla E1. |

Todos los campos se exportan en CSV y en SimulationStateBuilder.
Todos se resetean en `reset_dynamic_state()`.

## Caso diagnóstico

`sim/validation/cases/o2_stoich_diag_sealed.json` — sala sellada con `fire_o2_stoich_consumption_enabled=true`.
Genera `sim/validation/reports/o2_stoich_diag_sealed.csv` con columnas de tracking O2.

## Lo que queda bloqueado / pendiente

### O1 (balance de masa de O2)

Bloqueado hasta instrumentar:
- `o2_net_transport_kg_total` — transporte inter-sala
- `o2_exterior_removed_kg_total` — O2 ventilado al exterior
- `o2_exterior_added_kg_total` — O2 que entra por infiltración/PPV

### D2 (ratio CO/CO2)

Bloqueado por dual-tracking de CO2 (`co2_upper_ppm` es tracer de fracción molar,
no derivado de `co2_upper_kg`). No implementar hasta resolver.

### Option C (rediseño canónico O2)

Para separar completamente consumo químico, transporte, mezcla/dilución y exterior
como paths auditables independientes. No tocar motor sin plan explícito.

## Constraints activos (no violar sin plan)

- No activar `fire_o2_stoich_consumption_enabled` globalmente.
- No combinar `fire_o2_stoich_consumption_enabled` con `fire_o2_canonical_enabled` sin plan explícito.
- No tocar `sim/core` ni física global sin plan explícito.
- No ensanchar tolerancias ni reescribir baselines para forzar PASS.
- `v5_ventilation_hrr_spike` queda legacy/control calibrado; no migrar sin validación.
- `fp_ilv_upper_throttle_off` es control intencional con findings esperados.
- No commitear `reference_checks.json` si solo refleja logs stale.
- No implementar D2 CO/CO2 ratio hasta resolver dual-tracking CO2.
- No implementar O1 hasta instrumentar transport/exterior O2.

## Suite de tests

```
160 passed  tests/test_carbon_balance.py    (TestE1FuelTracking 13 + TestD2O2StoichTracking 14)
104 passed  tests/test_check_physics_coherence.py  (TestCheckE1 17 tests)
...
```

Failures conocidas pre-existentes (no relacionadas con este carril):
- `test_guardrails.py::test_exit0_real_json` — `g4 FED timing` en FAIL en reference_checks.json
- 4 tests en `test_two_zone_energy_core.py` / `test_two_zone_opening_flow.py`

# SimuFire — Handoff: estado actual

Fecha: 2026-06-28 (actualizado O1 canonical doorway)

## Rama y commits recientes

- Rama: `main`
- Commits del carril actual (más reciente primero):

```
3aa582c feat(fire): implement M5 post-backdraft guard (fire_post_bd_hrr_cut_enabled)
18b6b5c docs(fire): record M5 post-backdraft guard plan
c0eac58 docs(o2e1): close C1 decision — path exercised, O2E1 stays WARN
c8af550 test(o2): add M4 pool-release path exercise case
9a973a1 feat(o1-f): close O1 WARNs via post-clamp transport tracking
```

## Carriles cerrados

### S0 smoke global conservation — CERRADO

- Regla S0 implementada en `scripts/simulation/check_physics_coherence.py`.
- Invariante global: `Σ smoke_kg (todas las salas) + smoke_in_transit_kg = smoke_generated_total_kg - smoke_vented_total_kg - smoke_deposited_total_kg`
- Los tres acumuladores del engine ya existían; ahora se exportan al CSV en cada fila (mismo valor repetido para todas las salas del mismo timestep).
- Columnas CSV: `smoke_generated_total_kg`, `smoke_vented_total_kg`, `smoke_deposited_total_kg`, `smoke_in_transit_kg`.
- Severity: FAIL. Corpus: 11 CSVs auditados, 9 con esquema nuevo ejercitando S0/E1 y 2 legacy `p2h_diag_*` con skip graceful; 0 findings.
- Paths corregidos al cerrar S0:
  - extracción ACH/infiltración acumula `smoke_vented_total_kg`;
  - purga por ventilación natural acumula `smoke_vented_total_kg`;
  - entregas interiores diferidas se contabilizan con `smoke_in_transit_kg`;
  - `SmokeModel.recompute_layer_from_mass()` ya no destruye humo sub-umbral poniendo `smoke_kg = 0`.
- Limitación: S0 es global — no detecta errores compensados de transporte inter-sala.
  S1 per-sala implementada como WARN-clean (2026-06-30): accumuladores ya existían en RoomModel.
- Tests: 15 (TestCheckS0). Total coherence tests: 119.

### E1 fuel balance — CERRADO

- Regla E1 implementada en `scripts/simulation/check_physics_coherence.py`.
- Invariante: `solid_fuel_remaining_MJ[t] = solid_fuel_remaining_MJ[t-1] - Δfuel_consumed_MJ_total`
  usando totales acumulados para evitar aliasing por `log_interval`.
- Severity promovida de WARN a FAIL (commit 54a701b). Corpus: 11 CSVs auditados, 9 con esquema nuevo ejercitando S0/E1 y 2 legacy `p2h_diag_*` con skip graceful; 0 findings.
- Caso diagnóstico: `sim/validation/cases/fuel_balance_diag_sealed.json` →
  `sim/validation/reports/fuel_balance_diag_sealed.csv`. Residuales en 10⁻⁷–10⁻⁶ MJ (suelo numérico).
- Precisión fix (commit e7d73e6): `fuel_remaining_MJ` de `%.2f` a `%.6f` en SimulationLogWriter.
- Fix semántico actual: E1 usa `solid_fuel_remaining_MJ`, no `fuel_remaining_MJ`, porque `fuel_remaining_MJ` es legacy/visible y puede incorporar semántica de objetos/retained unburned que no representa el tanque sólido exacto que valida E1.
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
| `solid_fuel_remaining_MJ` | `float` | Campo CSV/StateBuilder canónico para E1; refleja el tanque sólido restante sin semántica legacy de `fuel_remaining_MJ`. |
| `smoke_in_transit_kg` | `float` | Campo CSV/StateBuilder global; humo removido de sala origen y pendiente de entrega interior. |
| `o2_consumed_kg_step_all` | `float` | SF-O1A: suma de todos los paths de consumo O2 (bulk + upper + lower + pluma). Reset cada tick en CombustionSystem. |
| `o2_consumed_kg_total_all` | `float` | Acumulado. |
| `o2_exterior_net_kg_step` | `float` | SF-O1A: O2 neto desde exterior este paso (>0 = entra). ACH bulk, apertura exterior, PPV, pressure_venting. |
| `o2_exterior_net_kg_total` | `float` | Acumulado. |
| `o2_net_transport_kg_step` | `float` | SF-O1A: O2 neto inter-sala este paso (>0 = recibe). Vanos interior, canonical doorway, thermal counterflow, GES background. |
| `o2_net_transport_kg_total` | `float` | Acumulado. |

Todos los campos se exportan en CSV y en SimulationStateBuilder.
Todos se resetean en `reset_dynamic_state()`.

## Caso diagnóstico

`sim/validation/cases/o2_stoich_diag_sealed.json` — sala sellada con `fire_o2_stoich_consumption_enabled=true`.
Genera `sim/validation/reports/o2_stoich_diag_sealed.csv` con columnas de tracking O2.

## O1-A — Instrumentación de balance O2 (CERRADO)

Commit: `33c3593 feat(o1-a): instrument per-sala O2 mass balance accumulators`

Paths instrumentados:
- **OES**: consumo bulk, ACH exterior, consumo upper, consumo lower (`fire_uses_lower_o2`), consumo pluma lower, apertura exterior, outgoing de `_exchange_room_o2_immediate`, received en `_apply_room_o2_mass_delta`
- **GES**: transport background (`step_smoke` o2_delta_kg), `pressure_venting` (exterior), PPV (exterior)
- **ThermalSystem**: `_apply_doorway_thermal_counterflow` (transport), `_apply_canonical_doorway_exchange` (transport)

Paths bloqueados (no instrumentados):
- `ach_lower_dt` (OES línea 472): cambio fraccional a `o2_lower` sin kg delta disponible — requeriría modificar física
- HVAC: fuera de scope por constraints activos

Tests: 20 (tests/test_o2_balance_instrumentation.py). Total suite: 469 passed.

## O1-D — Diagnóstico de bloqueos (CERRADO)

Dos bloqueos resueltos:

**Bloqueo B** (plume_lower en salas idle): `fire_o2_mode_used = "plume_lower"` en salas no-fuego
es un artefacto diagnóstico de `CombustionSystem._resolve_fire_o2_selection`. El filtro del auditor
(`hrr_kw > 0.1 AND mode in plume_lower/plume_blend`) lo maneja correctamente — salas idle incluidas.

**Bloqueo A** (residuales grandes en salas frías): `SimulationStateBuilder.gd` aplicaba corrección
molar de CO2 a la columna `o2` solo en salas no-fuego:
`room.o2 / (1 + co2_kg / (volume*1.2) * 29/44)`. A medida que el CO2 se acumulaba, el valor
logeado caía más rápido que `room.o2` real, creando residuales aparentes de 0.04–0.10 kg (FAIL).
Fix: eliminar la corrección — `"o2": room.o2` siempre. Sin cambios de física.
Post-fix: max residual = 3.87×10⁻⁴ kg (< 0.4 g). Todos los intervalos CLEAN.

## O1-E — Regla O1 WARN (CERRADO)

Implementada en `scripts/simulation/check_physics_coherence.py`.

**Invariante**: por sala y log-interval:
```
Δo2_bulk = (o2[t] − o2[t−1]) × air_mass_kg
expected = −Δo2_consumed_bulk_kg_total + Δo2_exterior_net_kg_total + Δo2_net_transport_kg_total
         + Δo2_zone_sync_kg_total
residual = |Δo2_bulk − expected|
```

**Skip**: filas con `hrr_kw > 0.1 AND fire_o2_mode_used in (plume_lower, plume_blend)` — `room.o2`
es derivado de zonas en ese modo; balance bulk N/A para sala con fuego activo.
Salas idle con ese label (artefacto CombustionSystem) se incluyen.

**Tolerancia**: floor 1×10⁻³ kg (1 g); relativo 1% del mínimo de `|expected|` y `o2_available_kg`
(= `o2[t−1] × air_mass_kg`), lo más conservador. Justificación: floor 2.6× por encima del
residual máximo observado post-fix (3.87×10⁻⁴ kg); la referencia de masa disponible evita
que la tolerancia crezca sin cota cuando `expected` es grande.

**Severity**: FAIL. Gating — promovido en `6a8dd2a` tras confirmar corpus 14/14 limpio.

**Corpus (14 CSVs) — post O1-G + promoción**:
- 14/14 PASS (0 findings O1), incluyendo `cfast_two_room_door_open` (canonical doorway).
- 0/14 WARN, 0/14 FAIL.

**Tests**: 22 nuevos (`TestCheckO1`). Tests coherence total: 157 passed.

## O1-F — Cierre de WARNs O1 (CERRADO)

**Causa de fuel_balance_diag_sealed WARNs (159)**: CSV stale generado con log writer anterior
sin columnas `fire_o2_mode_used`, `o2_zone_sync_kg_*` (97 cols en lugar de 101). El auditor
no podía filtrar filas `plume_lower` del cuarto de fuego → falsos WARNs. Fix: regenerar CSV.

**Causa de v5_m4_ventilation_throttle WARNs (67)**: artefacto de clamping en `o2_nominal`.
`_exchange_room_o2_active_flow` usa `_effective_room_o2_fraction` (incluye reservas negativas
de Pasillo), haciendo `eff_Pasillo < Pasillo.o2`. Con `eff_Salon ≥ eff_Pasillo`, el active flow
encola entregas POSITIVAS a Pasillo. Al llegar, `_apply_room_o2_mass_delta` las clampea a 0
(Pasillo en techo `o2_nominal=0.209`) pero acumulaba el delta INTENDIDO, no el real → residual.

**Fix (pure tracking, sin cambio de física)**:
`_apply_room_o2_mass_delta` (OES línea 1049) ahora acumula `actual_delta_kg = (room.o2_after − room.o2_before) × air_mass` en lugar de `delta_o2_kg`. Cuando no hay clamping: `actual = intended` (sin cambio). Cuando hay clamping en `o2_nominal`: `actual < intended` (residual eliminado).

**hvac_exists**: columna añadida a SimulationLogWriter (SF-O1F) y skip en check_physics_coherence para escenarios con HVAC configurado — documentado aunque `hvac_exists=false` siempre en simple_house (HVAC fuera de scope).

**Resultado post-fix**: 0 WARNs en corpus completo. Max residual < 4×10⁻⁴ kg (< 0.4 g).

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

## M5 — Post-backdraft HRR guard (CERRADO, 2026-06-28)

Commit: `3aa582c feat(fire): implement M5 post-backdraft guard (fire_post_bd_hrr_cut_enabled)`

**Flag opt-in**: `fire_post_bd_hrr_cut_enabled` (default `false`). Activado solo en `v1_m4_pool_release.json`.

**Cambios implementados:**
- `SimulationEngine.gd`: export var + entrada en context dict
- `CombustionSystem.gd`: early guard (zeroes `retained_generation_kw` antes del update del pool, condición `backdraft_triggered AND not backdraft_active AND o2 < fire_backdraft_o2_max`) + late guard (corta `hrr_kw/hrr_target_kw` cuando `not can_flame AND not latent_viable`)
- `CombustionRegimeClassifier.gd`: rule 8 usa solo `hrr_kw > 0.0` (eliminado `or fire_time_s > 0.0` que causaba A3 FAIL con HRR=0 post-backdraft)
- `SimulationLogWriter.gd`: exporta columna `backdraft_active` al CSV
- `check_physics_coherence.py`: skip O2E1 Thornton en intervalos con `backdraft_active=1`

**Resultado:**
- Backdraft principal t≈350 s preservado (HRR spike 21 369 kW)
- Sin segundo backdraft
- A3=0 WARNs, O2E1=0 WARNs
- `check_physics_coherence.py` PASS (786 rows)
- `validate_reference_cases`: 349/354 PASS (5 VALID_GAP pre-existentes, sin cambio)

**C1 cerrado** → O2E1 puede promoverse a FAIL (decisión pendiente, sesión futura).

## O1-G — Brecha multi-room canonical doorway (CERRADO, 2026-06-28)

**Causa raíz**: doble-conteo de `_cde_net_hot` en `o2_net_transport_kg_total`.

`_apply_canonical_doorway_exchange` suma `_cde_net_hot` al transport (hot_room += , cold_room -=),
pero después sincroniza `room.o2 = zone_blend`. El zone sync ya captura el efecto neto de CDE en
`room.o2` vía la mezcla volumétrica de `o2_upper`/`o2_lower`. Al incluir ambos en la fórmula O1,
se contaba el flujo entre salas dos veces → `expected > delta_bulk` → residuals negativos crecientes
con HRR (244 WARNs en `cfast_two_room_door_open`, 6 salas, cumulativo −0.1268 kg a t=190s).

**Fixes aplicados:**
- `ThermalSystem.gd` `_apply_canonical_doorway_exchange`: eliminadas las 4 líneas que sumaban
  `_cde_net_hot` a `o2_net_transport_kg_step/total` (SF-O1A). El zone sync de hot_room y cold_room
  (existente + añadido en esta sesión) ya captura el efecto real sobre `room.o2`.
- `ThermalSystem.gd` `_apply_canonical_doorway_exchange`: añadido zone sync para `cold_room`
  (equivalente al que ya existía para hot_room), porque Part A modifica `cold_room.o2_upper`
  pero no sincronizaba `cold_room.o2`.
- `check_physics_coherence.py` O1: añadido `Δo2_zone_sync_kg_total` al expected.
  Columna opcional (default 0.0) — casos sin canonical doorway no se ven afectados.

**Resultado:** `cfast_two_room_door_open` PASS (0 findings O1). Corpus completo: 14 PASS, 0 WARN.

## Suite de tests

```
157 passed  Python unit tests (2026-06-28, post O1-G)
validate_reference_cases: 349/354 PASS (5 VALID_GAP pre-existentes, sin cambio)
Physics coherence audit: 14 PASS, 0 FAIL, 1 CTRL (v1_backdraft_accumulation intencional)
```

Failures conocidas pre-existentes (no relacionadas con este carril):
- `test_guardrails.py::test_exit0_real_json` — 5 CFAST checks failing en reference_checks.json (O2 depletion timings, chain room temps)
- `test_legacy_two_zone_compare.py::test_engine_flag_is_exported_and_default_off`
- 4 tests en `test_two_zone_energy_core.py` / `test_two_zone_opening_flow.py`

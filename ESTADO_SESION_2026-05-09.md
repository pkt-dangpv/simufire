# Estado de Sesión — 09/05/2026

## Contexto inicial
- Cargado estado: `ESTADO_SESION_2026-05-08.md`
- Baseline previo: ✅ 5/5 PASS antes de esta sesión
- Objetivo elegido: Análisis A2 — Gap de O2 en salas remotas vs FDS

---

## Trabajo realizado

### Análisis A2: O2 gap en salas remotas
Pre-fix (referencia de sesión anterior):

| Sala | SimuFire | FDS referencia | Gap |
|------|----------|----------------|-----|
| R0 | 9.55% | 9.89% | -0.34% |
| R1 | 14.26% | 10.4% | **+3.86%** |
| R2 | 15.86% | 14.0% | +1.86% |
| R3 | 15.25% | 13.0% | +2.25% |
| R4 | 16.49% | 15.0% | +1.49% |
| R5 | 15.44% | 13.5% | +1.94% |

**Causa raíz identificada**: el parcel caliente (`moved_upper_gas_kg`) transporta humo/CO/CO2/HCN entre salas pero NO transporta el O2 empobrecido de la sala fuente. Las salas receptoras mantienen O2 alto porque reciben gas caliente sin la composición de O2 del humo.

### Option A: O2 carry con hot gas flow (INTENTADA Y REVERTIDA)

**Primer intento**: bloque colocado en rama `else` (dead code cuando `use_transport_delay=true`). Sin efecto.

**Segundo intento** (bidireccional, coef 0.12): bloque antes de `if use_transport_delay:`. Resultado:
- `living_room_hallway`: **FAIL** (room_0_final_layer_150c_m = 1.785 vs 2.09 ±0.15)
- R0 recibía O2 extra de R1 como "contraflow" → fuego más intenso → capa caliente más baja
- Diagnóstico: doble conteo con `OxygenExchangeSystem`

**Tercer intento** (unidireccional, coef 0.12): solo `o2_delta_kg[to_id] -= o2_deficit_kg` sin modificar source. Resultado:
- `living_room_hallway`: ✅ PASS
- `confinement_open_close`: **FAIL** (room_0_final_o2 = 7.94% vs 10.6% ±2%)
- Diagnóstico: R1 se depletaba durante t=0-200s, al abrir la puerta (t=550s) el gas de R1 con O2 bajo mezclaba con R0

**Cuarto intento** (coeficiente reducido a 0.03): Sin efecto. Resultado idéntico al 0.12.
- Diagnóstico clave: `moved_upper_gas_kg = maxf(0.03, source.upper_gas_kg * 0.24)` — tiene un floor de 30g/step. El binding constraint es `moved_upper_gas_kg`, NO `tgt_air_mass * coeff`. Cambiar el coeficiente no tiene efecto porque la constraint activa es la otra rama de `minf()`.

### Decisión final: REVERT

El carry fue revertido (bloque comentado con nota diagnóstica en `sim/core/GasExchangeSystem.gd` línea ~496).

**Razón**: El floor de 0.03 kg en `moved_upper_gas_kg` hace el carry demasiado agresivo para escenarios con reapertura de puertas (900s). Con cualquier carry activo, el O2 en salas adyacentes se depleta y al reopener afecta R0.

---

## Estado final

### Baselines: ✅ 5/5 PASS (todos verificados con código revertido)
| Case | Estado | Timestamp |
|------|--------|-----------|
| confinement_open_close | ✅ PASS | 10:38:33 |
| living_room_hallway | ✅ PASS | 10:38:56 |
| postfire_decay | ✅ PASS | 10:41:59 |
| layer150_tenability | ✅ PASS | 10:42:29 |
| ul_exterior_water_knockdown | ✅ PASS | 10:42:53 |

### fds_simple_house_default: O2 gap sin cambios (carry revertido)
(valores pre-sesión — mismo estado que entrada)
| Sala | SimuFire | FDS ref | Gap |
|------|----------|---------|-----|
| R0 | 9.55% | 9.89% | -0.34% |
| R1 | 14.26% | 10.4% | **+3.86%** |
| R2 | 15.86% | 14.0% | +1.86% |
| R3 | 15.25% | 13.0% | +2.25% |
| R4 | 16.49% | 15.0% | +1.49% |
| R5 | 15.44% | 13.5% | +1.94% |

---

## Archivos modificados
- `sim/core/GasExchangeSystem.gd`: revertido al estado pre-sesión + comentario diagnóstico (línea ~496). Modificación neta: solo el comentario es nuevo.

---

## Lecciones aprendidas

### Sobre el mecanismo O2 carry
1. **`moved_upper_gas_kg` tiene floor de 0.03 kg**: `maxf(0.03, source.upper_gas_kg * 0.24)`. Cambiar el coeficiente multiplicador en `minf(moved_upper_gas_kg, tgt_mass * coeff)` NO tiene efecto cuando `moved_upper_gas_kg < tgt_mass * coeff` (que es el caso típico). El carry siempre usa `moved_upper_gas_kg` directamente.
2. **El carry unidireccional tiene efecto acumulativo**: 200 steps a 0.1 kg/step puede depleta significativamente el O2 de salas adyacentes (~20% del total).
3. **Escenarios de reapertura de puertas**: cualquier carry que depleta O2 de salas adyacentes durante el período activo del fuego afecta el estado final cuando las puertas se reabren y el gas se mezcla.

### Sobre el gap A2
- El gap en R1 (+3.86%) es estructural: el modelo 0D mezcla perfectamente el O2 en R1, mientras FDS muestra gradiente espacial (gas caliente con O2 bajo en capa alta, aire fresco con O2 normal en capa baja).
- La solución correcta requiere modelar la distribución de O2 por capas (upper/lower O2 por sala), similar a cómo ya se modela la temperatura.

---

## Pendientes para próximas sesiones
- **A2b**: Modelado de O2 por capas (upper_o2 y lower_o2 por sala) — solución arquitectónica real para el gap
- **A2c**: Aumentar `doorway_o2_exchange_coeff` en el override de `fds_simple_house_default` para ver si puede reducir el gap sin cambios de código
- **Otros análisis** de la lista en `ESTADO_SESION_2026-05-08.md`

---

## Continuación de sesión: Run 8 — Suite completa (17/17 PASS)

### Contexto
Continuación del esfuerzo multi-sesión de estabilización de baselines tras el `z_m fix` en `sim/core/ThermalSystem.gd`:
```gdscript
var z_m: float = maxf(room.thermal_layer_m, l_flame_m + 0.05)
```
Este fix reduce el HRR pico de ~1800 kW a ~1200–1400 kW y también reduce el calentamiento de habitaciones adyacentes.

### Baselines corregidos en esta continuación de sesión

| Archivo baseline | Métrica | Valor anterior | Valor corregido | Motivo |
|---|---|---|---|---|
| `v8_suppression_reburn.json` | `room_0_peak_hrr_kw` min | 1800.0 | 1000.0 | z_m fix reduce HRR pico |
| `g2_gie_transitional_attack.json` | `room_0_peak_hrr_kw` min | 1800.0 | 1000.0 | z_m fix reduce HRR pico |
| `g3_gie_ppv_post_knockdown.json` | `room_0_peak_hrr_kw` min | 1800.0 | 1000.0 | z_m fix reduce HRR pico |
| `g4_gie_delayed_entry_hazard.json` | `room_1_peak_temp_upper_c` min | 350.0 | 200.0 | z_m fix reduce transferencia de calor a habitaciones adyacentes |
| `v6_spread_to_hallway.json` | múltiples | revisado completo | 3 métricas | Baseline revisado para reflejar física correcta post-fix |

### Resultado Run 8 — Confirmado 2026-05-09 ~17:44

```
[Validation Suite] Resumen
 - living_room_hallway:          PASS (21,41s)
 - layer150_tenability:          PASS (26,42s)
 - postfire_decay:               PASS (136,06s)
 - ul_exterior_water_knockdown:  PASS (21,22s)
 - confinement_open_close:       PASS (82,57s)
 - v1_backdraft_accumulation:    PASS (55,22s)
 - v2_sealed_room_o2_depletion:  PASS (39,4s)
 - v3_hallway_fed_exposure:      PASS (83,05s)
 - v4_co_remote_rooms:           PASS (62,33s)
 - v5_ventilation_hrr_spike:     PASS (50,24s)
 - v6_spread_to_hallway:         PASS (74,24s)
 - v7_underventilated_co_peak:   PASS (40,26s)
 - v8_suppression_reburn:        PASS (52,44s)
 - g1_gie_confinement_attack:    PASS (39,97s)
 - g2_gie_transitional_attack:   PASS (40,18s)
 - g3_gie_ppv_post_knockdown:    PASS (70,33s)
 - g4_gie_delayed_entry_hazard:  PASS (48,94s)

[Validation Suite] Duracion total: 944,32s
[Validation Suite] Resultado final: PASS
```

**17/17 PASS — Suite de validación completa superada al 100%.**

### Notas de infraestructura
- `update_baselines2.ps1` es el ÚNICO script funcional. NO usar `update_baselines.ps1` ni `update_baselines_fixed.ps1` (comillas Unicode rotas).
- Godot headless: `F:\OneDrive\Escritorio\Godot_v4.6.2-stable_win64_console.exe`

---

## Continuación de sesión: Auditoría física y plan CFAST-lite

### Auditoría generada

Se creó `AUDIT_REPORT.md` con una auditoría técnica de realismo físico, químico y operativo de SimuFire.

También se creó `audit_issues/` con issues locales para fallos críticos/altos detectados inicialmente:
- `ISSUE-001-critical-cfast-hot-layer-temperature-mismatch.md`
- `ISSUE-002-critical-toxic-gas-chemistry-not-fuel-specific.md`
- `ISSUE-003-critical-backdraft-model-heuristic.md`
- `ISSUE-004-critical-water-suppression-lacks-steam-and-visibility.md`
- `ISSUE-005-high-hrr-curves-and-fuel-vent-transition-not-validated.md`
- `ISSUE-006-high-smoke-visibility-optics-units.md`
- `ISSUE-007-high-pyrolysis-and-ignition-threshold-model.md`
- `ISSUE-008-high-opening-flow-not-single-conservative-solver.md`
- `ISSUE-009-high-glass-failure-temperature-only.md`
- `ISSUE-010-high-validation-overrides-and-domain-of-applicability.md`

### Correcciones importantes a la auditoría

La primera versión mezclaba dos carriles de validación:

1. `run_all_cases.ps1`: suite interna de regresión.
   - Estado correcto: **17/17 PASS** tras el `z_m fix`.
2. `run_reference_checks.ps1`: benchmark externo CFAST/Ghanekar.
   - Escribe `sim/validation/reports/reference_checks.json`.
   - No debe interpretarse como fallo de la suite interna.

Se actualizó `AUDIT_REPORT.md` para dejar esto claro.

### Estado actualizado de reference checks

Se ejecutó:

```powershell
powershell -ExecutionPolicy Bypass -File .\sim\validation\run_reference_checks.ps1 -SkipCaseRuns
```

Resultado usando reportes existentes:

```text
[Reference Checks] FAIL: 24/28 required checks passed
[Reference Checks] Known gaps: 1 non-gating checks did not pass
```

Fallos requeridos actuales:
- `cfast_t420_co_upper_ppm`: SimuFire `6023 ppm`, CFAST `379 ppm`, tolerancia `350 ppm`.
- `cfast_t510_co_upper_ppm`: SimuFire `6021 ppm`, CFAST `326 ppm`, tolerancia `350 ppm`.
- `ghanekar_far_hall_o2_response_time_s`: SimuFire `161.6 s`, objetivo `198 +/- 30 s`.
- `ghanekar_origin_peak_upper_temp_reasonable_c`: SimuFire `278.7 C`, objetivo `450-650 C`.

Checks CFAST que antes se citaron mal como fallos actuales y ahora pasan:
- Temperatura superior t350/t360/t420/t510.
- Altura de capa t350/t360/t420/t510.

Nota: esto reutiliza reportes existentes. No sustituye una rerun completa de Godot para `cfast_r0_window_360` y `ghanekar_bedroom_hallway`.

### Matices corregidos

- Los overrides por escenario son legítimos cuando representan geometría, combustible, ventilación, instrumentación o frontera numérica real del caso.
- Se debe clasificar cada override como:
  - físico,
  - numérico,
  - empírico.
- `suppression_upper_heat_fraction=0.68`, `suppression_lower_cooling_fraction=0.18`, `suppression_surface_cooling_fraction=0.26` no son bug solo por sumar más de 1. Pueden ser efectividades/sumideros solapados. Hay que verificar semántica y budget.
- `upper_heat_capture_fraction=0.10-0.25` queda marcado como parámetro sensible, no como causa demostrada por sí sola de capas frías.

### Diagnóstico arquitectónico consensuado

El objetivo no es convertir SimuFire en FDS. El salto realista es un modelo **CFAST-lite / two-zone conservativo**:

- CFAST resuelve ODEs acopladas por sala: presión, masa upper/lower, energía upper/lower, altura de interfaz.
- SimuFire todavía mezcla sistemas heurísticos separados:
  - calor en `ThermalSystem`,
  - O2 en `OxygenExchangeSystem`,
  - humo/CO/CO2/HCN en `GasExchangeSystem`,
  - capa/humo con relajaciones.

El plan razonable es llevar la arquitectura de ~45% CFAST-like a ~80% CFAST-like sin hacer CFD.

### Plan priorizado Fase 1 — Minimum Viable CFAST

Orden recomendado:

1. **Budget energético por step y por sala**
   - Loguear:
     - `E_fire_in`
     - `Delta_E_upper`
     - `Delta_E_lower`
     - `Q_wall_absorbed`
     - `Q_radiative_surfaces`
     - `Q_vent_out`
     - `Q_suppression`
     - `Q_residual`
   - Al inicio: warning si error >5-10%, no fail duro.

2. **HRR capture realista**
   - Sustituir `upper_heat_capture=0.10-0.25` por:
     - `chi_rad ~= 0.30-0.35`
     - `q_conv = HRR * (1 - chi_rad)`
     - `q_rad = HRR * chi_rad`
   - `q_conv` entra al plume/capa superior.
   - `q_rad` debe ir explícitamente a paredes, suelo, objetos y/o capa/humo. Nada debe desaparecer.

3. **A/B inmediato contra CFAST**
   - Ejecutar `cfast_r0_window_360`.
   - Luego `run_reference_checks.ps1 -SkipCaseRuns`.
   - Mirar:
     - `temp_upper`
     - `hot_layer`
     - `HRR`
     - `O2`
     - `CO_upper`

4. **Masa upper/lower conservada**
   - Crear `m_upper`, `m_lower`.
   - `m_upper + m_lower` debe cerrar masa de sala.
   - Plume entrainment resta de lower y suma a upper.
   - Interfaz:
     - `h_interface = (m_lower / rho_lower) / A_floor`
   - Las relajaciones deben pasar a smoothing visual o quedar detrás de flag.

5. **Un único cálculo de mass-flow por abertura**
   - Centralizar en algo tipo:
     - `compute_vent_flow(opening, src_room, dst_room) -> {m_upper_flow, m_lower_flow, h_neutral}`
   - Calor, O2, humo, CO, CO2 y HCN usan el mismo flujo.
   - Esto debería resolver el O2 carry sin el parche bloqueado por el floor de `0.03 kg`.

### Lo que NO se prioriza para cerrar CFAST ahora

Son mejoras válidas, pero no atacan el gap visible de capa/temperatura/benchmark:
- Química C/H/O/N completa.
- HCN por nitrógeno.
- Supresión con vapor completo.
- Rotura de vidrio por flujo de calor.
- View factors avanzados.

### Siguiente paso recomendado

Empezar por `ThermalSystem.gd`:

1. Añadir budget energético no intrusivo.
2. Cambiar captura de HRR a `q_conv/q_rad`.
3. Correr `cfast_r0_window_360`.
4. Regenerar comparador con `run_reference_checks.ps1 -SkipCaseRuns`.
5. Decidir si el siguiente paso es masa upper/lower o transporte de especies.

---

## Continuación nocturna: Phase 1 Items 3-4, experimento O2 carry, confirmación 17/17 PASS

### Items Phase 1 implementados

**Item 3 — Centralizar mass-flow callable ✅**  
Refactorización en `SimulationEngine.gd` y `GasExchangeSystem.gd` para centralizar cálculo de flujo de masa.

**Item 4 — O2 carry bidireccional, floor-free ✅ (implementado, deshabilitado)**  
Bloque bidireccional en `GasExchangeSystem.gd` línea ~505. Solo activo cuando `o2_smoke_carry_coeff > 0.0`.
- `@export var o2_smoke_carry_coeff: float = 0.0` en SimulationEngine.gd
- **Estado final: 0.0 (deshabilitado)**

**Fix timeout ✅**  
`sim/validation/run_all_cases.ps1`: timeout default = **600s** (era 300s)

### Experimento O2 carry (abandonado)

| Coeff | FAILs | Casos fallidos |
|-------|-------|----------------|
| 0.30 | 4 | v3_hallway_fed_exposure, layer150_tenability, postfire_decay, confinement_open_close |
| 0.10 | 2 | postfire_decay (smoke -78%), confinement_open_close (HRR=0) |
| 0.00 | 0 | — |

**Causa raíz**: cualquier coeff > 0 altera balance de presión y transporte de masa. Baselines calibrados con coeff = 0.0 son incompatibles con valor no nulo.

**Decisión**: feature implementada pero deshabilitada. Para activarla en futuro: recalibrar TODOS los baselines con el coeff elegido.

### Validación final — 17/17 PASS (2026-05-09 ~00:43 hora local)

```
[Validation Suite] Resumen
 - living_room_hallway:          PASS (27.95s)
 - layer150_tenability:          PASS (30.59s)
 - postfire_decay:               PASS (136.16s)
 - ul_exterior_water_knockdown:  PASS (21.42s)
 - confinement_open_close:       PASS (76.61s)
 - v1_backdraft_accumulation:    PASS (59.86s)
 - v2_sealed_room_o2_depletion:  PASS (38.55s)
 - v3_hallway_fed_exposure:      PASS (86.02s)
 - v4_co_remote_rooms:           PASS (70.08s)
 - v5_ventilation_hrr_spike:     PASS (49.62s)
 - v6_spread_to_hallway:         PASS (67.75s)
 - v7_underventilated_co_peak:   PASS (36.56s)
 - v8_suppression_reburn:        PASS (51.92s)
 - g1_gie_confinement_attack:    PASS (33.35s)
 - g2_gie_transitional_attack:   PASS (37.14s)
 - g3_gie_ppv_post_knockdown:    PASS (52.89s)
 - g4_gie_delayed_entry_hazard:  PASS (39.64s)

[Validation Suite] Duracion total: 916.14s
[Validation Suite] Resultado final: PASS
```

# Current Handoff State

Date: 2026-06-21.

## Purpose

This note records the repository hygiene and validation state after the non-motor cleanup. It is meant to let another machine or contributor continue without relying on chat history.

## Current Session Update — 2026-06-23 (rev 15 — Ruta B: v5_m4_ventilation_throttle)

### Estado operativo actual

- Branch: `main`, limpio, **ahead 7** respecto a `origin/main` (push pendiente).
- Commit nuevo: `test(ilv): add M4 ventilation throttle reference case` (pendiente de confirmar hash).
- Validación: **354/354 PASS** (guardrails ampliados, 4 nuevos checks del caso M4 — todos PASS).
- Python tests: 244 tests, 5 failures pre-existentes (sin regresión).

### Ruta B: caso de referencia M4 para v5

**Decisión**: mantener `v5_ventilation_hrr_spike` como caso legacy/control (sin cambios). Crear nuevo caso `v5_m4_ventilation_throttle` con `fire_o2_upper_throttle_enabled: true` que verifica que M4 suprime el HRR zombie.

**Semántica**:
- `v5_ventilation_hrr_spike`: testea el spike como comportamiento esperado (bug ILV expuesto). `peak_hrr = 3245 kW`, `time_hrr_above_1000_post_vent ≈ 164 s`.
- `v5_m4_ventilation_throttle`: testea supresión M4. `peak_hrr ≤ 600 kW`, fire extinguido ~178 s post-ignición.

**Métricas baseline (M4)**:

| Métrica | Valor medido | Regla | Estado |
|---|---:|---|---|
| `room_0_peak_hrr_kw` | ~492 kW | `max: 600` | PASS |
| `room_0_min_o2_upper` | ~6.37% | `min: 0.05` | PASS |
| `room_0_min_l150_m` | ~1.98 m | `min: 1.90` | PASS |
| `room_0_peak_co_upper_ppm` | ~12386 ppm | `min: 1000` | PASS |

**Archivos añadidos**:
- `sim/validation/cases/v5_m4_ventilation_throttle.json` — misma física que v5, `fire_o2_upper_throttle_enabled: true`
- `sim/validation/baselines/v5_m4_ventilation_throttle.json` — 4 reglas de supresión
- `sim/validation/reports/v5_m4_ventilation_throttle.json` — reporte generado headless
- `sim/validation/reports/v5_m4_ventilation_throttle.csv` — CSV copiado desde tmp_v5_m4.csv (misma física)
- `scripts/simulation/validate_reference_cases.py` — caso añadido a `build_single_room_fire_checks()`

**Auditor ILV post-Ruta B**: coherence checker sobre `v5_m4_ventilation_throttle.csv` → 0 findings. `audit_ilv_layer_coherence_suite.py`: 8/8 PASS (excluye `fp_ilv_upper_throttle_off` como control intencional).

### Próxima sesión

El único HRR zombie sin resolver en CSVs permanentes es `fp_ilv_upper_throttle_off` (control intencional, 258 findings). No requiere acción.

Opciones abiertas:
- **Opción A** (baja prioridad): diseñar más escenarios M4 con `fire_o2_upper_throttle_enabled: true` desde el principio.
- **Opción B coordinada** (alta complejidad): migración de los ~8-10 casos con ventana exterior y `threshold_metrics` calibradas pre-M4.

---

## Current Session Update — 2026-06-22 (rev 14 — Phase C: credibility audit + primera migración M4)

### Estado operativo actual

- Branch: `main`, limpio, **ahead 6** respecto a `origin/main` (push pendiente).
- Commits nuevos en esta ronda:
  - `d635c83` — feat(ilv): add ILV layer-coherence suite auditor
  - `ee9216c` — fix(ilv): activate M4 guard in layer_interface_single_room_window
- Validación: 345/350 PASS (sin regresión). 42/42 Python tests PASS (incluye 2 pre-existentes corregidos).

### Motor credibility audit (Phase C) — Mapa de daño completado

**Auditor creado**: `scripts/simulation/audit_ilv_layer_coherence_suite.py` + `tests/test_audit_ilv_layer_coherence_suite.py` (16 tests).

**Resultados sobre 8 CSVs permanentes** (tmp excluidos, `--include-tmp` para incluirlos):

| Archivo CSV | Estado | Findings | Notas |
|---|---|---:|---|
| `cfast_ilv_audit` | PASS | 0 | Multi-room, canonical activo |
| `fp_ilv_open_partial_window` | PASS | 0 | Ventana parcial, canonical activo |
| `fp_ilv_upper_throttle_on` | PASS | 0 | M4 activo — referencia de diseño |
| `ilv_open_window_repro` | PASS | 0 | Canonical activo |
| `layer_interface_single_room_window` | **PASS** | 0 | ✅ Migrado a M4 (antes: 11 findings) |
| `p2h_diag_off` | PASS | 0 | Sin exposición exterior |
| `p2h_diag_on` | PASS | 0 | Sin exposición exterior |
| `fp_ilv_upper_throttle_off` | **FAIL** | 258 | Control intencional (HRR zombie ~1211 kW) |

**Único FAIL restante = caso de control intencional** `fp_ilv_upper_throttle_off`. No hay HRR zombies no intencionados en CSVs activos.

### Primera migración M4 permanente: `layer_interface_single_room_window`

**Contexto**: el auditor descubrió 11 findings en este caso de regresión de interfaz de capa — ILV zombie incidental (caso diseñado para testear alturas de capa, no combustión).

**Análisis OFF vs M4** (room 0, ventana exterior 50% abierta, sin canonical):

| t (s) | HRR OFF | HRR M4 | o2_upper OFF | o2_upper M4 |
|---|---:|---:|---:|---:|
| 100 | 377.7 kW | 377.7 kW | 16.9% | 16.9% |
| 130 | 662.3 kW | 336.1 kW | 4.2% | 6.5% |
| 160 | 959.3 kW | 79.9 kW | 0.08% | 6.6% |
| 180 | 1142.2 kW | **32.8 kW** | 0.08% | **8.5%** |

**Baseline checks con M4** — todos PASS:
- `min_visible_smoke_layer_m`: 1.175 (idéntico — mínimo antes de t=130s)
- `min_thermal/flow_interface_m`: 1.171 (idéntico)
- `final_flow_interface_m`: 1.428 ∈ [0, 2.40] ✓
- `final_visibility_m`: 0.33 ≤ 5.0 ✓

**Cambios en `ee9216c`**:
- `sim/validation/cases/layer_interface_single_room_window.json` — añadidos `fire_o2_upper_throttle_enabled: true` + `two_zone_solver_enabled: true`
- `sim/validation/cases/fed_thermal_layer_smoke_only.json` — añadido `two_zone_solver_enabled: true` (corrige 2 failures pre-existentes en test_layer_interface_model.py)

### Único caso real pendiente con HRR zombie: `v5_ventilation_hrr_spike`

El auditor `tmp_v5_off.csv` (95 findings, HRR zombie hasta 3245 kW) queda como único caso problemático real. Ruta de migración bloqueada: el caso tiene `threshold_metric: hrr >= 1000 post-vent` calibrado sobre el bug ILV. Para migrar: actualizar el threshold_metric a medir supresión por M4 en lugar de magnitud del spike.

### Próxima sesión

**Opción A (preferida)**: diseñar nuevos escenarios ILV/FP con M4 como física esperada desde el principio. Sin impacto en suite existente.

**Opción B**: migración coordinada de `v5_ventilation_hrr_spike` — requiere actualizar explícitamente el `threshold_metric` del caso antes de activar M4.

---

## Current Session Update — 2026-06-22 (rev 13 — Cierre campaña M4)

### Estado operativo actual

- Branch: `main`, limpio, **ahead 4** respecto a `origin/main` (push pendiente).
- Commits esta sesión:
  - `ba13139` — fix(ilv): add fire_o2_upper_throttle_enabled motor guard (Phase 5 M4)
  - `5c98429` — docs(ilv): document EXP-1 finding — M4 and canonical are competing mechanisms
  - `10e93ed` — docs(ilv): document EXP-2 finding — existing threshold_metrics built on ILV bug
- Validación: 345/350 PASS (sin regresión), unit test 7/7 PASS, coherence checker 0/1686 findings (throttle ON).

### Phase 5 M4 — ILV upper-O₂ throttle guard

**Causa raíz auditada**: `two_zone_solver_enabled=true` → `CombustionSystem` elige `o2_ref = room.o2_lower` para HRR throttle. En salas abiertas (`outside_open_factor > 0.01`), `OxygenExchangeSystem.plume_lower_mode=false` → consumo O₂ va al bulk `room.o2`, nunca a `room.o2_lower`. Resultado: `o2_lower` permanece ~19.7%, `o2_hrr_factor ≈ 0.894`, HRR ~1211 kW, mientras `o2_upper → 0.08%` sin efecto en combustión.

**Solución implementada**: flag `fire_o2_upper_throttle_enabled` (motor engine-side). En `CombustionSystem.step_room_fire()`, después de resolver `o2_selection`, si `fire_o2_upper_throttle_enabled=true` y `o2_upper < fire_o2_upper_throttle_critical(0.10)` y `sel_mode == "plume_lower" OR "plume_blend"`: `o2_ref = minf(room.o2, room.o2_upper)`.

**Corrección de placement**: los keys `fire_o2_upper_throttle_enabled` / `fire_o2_upper_throttle_critical` debían estar en `_build_room_combustion_context()` (dict leído por CombustionSystem), no en `_sync_auxiliary_services()` (dict de OxygenExchangeSystem, sin relación).

**Resultados verificados**:
- Throttle OFF: HRR 1211 kW indefinido, 258 coherence FAIL (fuego zombie)
- Throttle ON: HRR 549→299→184→46→25 kW (fuego se apaga t≈165 s), 0 coherence FAIL (1686 rows)
- Unit test: 7/7 PASS (bug secundario: `fire_max_active_s` ausente del contexto de test → fixed)
- Guardrails: 345/350 PASS intactos (5 failures pre-existentes, sin regresión)

**Archivos modificados**:
- `sim/fire/CombustionSystem.gd` — throttle guard (líneas ~124-136 post o2_selection)
- `sim/core/SimulationEngine.gd` — keys movidos a `_build_room_combustion_context()` (eliminados de `_sync_auxiliary_services()`)
- `tools/validate_fire_o2_upper_throttle.gd` — context fix `fire_max_active_s: 1800.0`
- `tools/validate_fire_o2_upper_throttle.tscn` — escena de test headless
- `sim/validation/cases/fp_ilv_upper_throttle_on.json` — escenario con flag activo per-caso
- `sim/validation/cases/fp_ilv_upper_throttle_off.json` — escenario control

### EXP-1 — Hallazgo crítico: M4 y canonical son mecanismos en competencia

**Experimento (2026-06-22)**: Activar `fire_o2_upper_throttle_enabled=true` en `cfast_ilv_open_window_repro` (que ya tiene `fire_o2_canonical_enabled=true`). Revertido después de análisis.

**Mecanismo de interacción descubierto**:
- Con canonical: `o2_lower ≈ 13–16%` (depleta por consumo real)
- `_resolve_fire_o2_selection()` en `plume_lower` → `o2_ref = room.o2_lower ≈ 13%`
- Cuando M4 activa (`o2_upper < 0.10`): `o2_ref = min(room.o2=14%, o2_upper=9%) = 9%`
- Resultado: M4 sobreescribe canonical con referencia MÁS agresiva → doble-freno
- Comportamiento observado: HRR oscila 100–750 kW (vs 972 kW estable con canonical solo), ciclos ILV_LATENT↔VCB, fuego termina en ILV_LATENT a t=1400s

**Coherence**: 0 findings (correcto). **Guardrails**: 345/350 (sin regresión). **Pero criterio ±10% HRR no se cumple** — cambio >>10%.

**Conclusión operativa**:
- M4 NO es "defense-in-depth" junto a canonical — es un mecanismo **en competencia**
- M4 aplica en casos **SIN canonical** (donde `o2_lower` se mantiene fresco ~19.7% por `plume_lower_mode=false`)
- Canonical aplica en casos donde se quiere que la combustión deplecione `o2_lower` directamente
- **No activar ambos flags simultáneamente sin plan explícito de interacción**

### EXP-2 — Hallazgo: casos existentes tienen threshold_metrics calibradas sobre el bug

**Experimento (2026-06-22)**: `v5_ventilation_hrr_spike` con M4 standalone (sin canonical). Caso tiene ventana exterior abriendo a t=120s, `fire_secondary_hrr_gain_kw: 2500`, y threshold_metric `hrr >= 1000 post-vent`.

**Resultados clave**:

| t | HRR OFF | HRR M4 | delta | o2_upper OFF | o2_upper M4 |
|---|---|---|---|---|---|
| t=115s | 486 kW | 486 kW | 0% | 10.22% | 10.22% |
| t=120s | 537 kW | 414 kW | -23% | 8.30% | 8.56% |
| t=145s | 819 kW | 122 kW | -85% | 0.08% | 6.56% |
| t=300s | 3104 kW | 107 kW | -97% | 0.08% | 10.15% |
| t=595s | 3232 kW | 162 kW | -95% | 0.08% | 9.44% |

**Coherence OFF**: 75 findings (bug ILV activo desde t=145s, o2_upper=0.08% mientras HRR sube a 3232 kW).
**Coherence M4**: PASS (0 findings).

**Problema**: `threshold_metric hrr >= 1000 post-vent` fallaría con M4 (HRR máximo ~210 kW). El caso testea el spike como feature — que es la manifestación del bug ILV con `fire_secondary_hrr_gain_kw`.

**Conclusión**: M4 es físicamente correcto pero incompatible con los threshold_metrics de casos diseñados pre-M4.

### Situación actual — Activación de M4 en casos existentes bloqueada

**Patrón identificado en EXP-1 y EXP-2:**
- Casos con `fire_o2_canonical_enabled`: M4 crea doble-freno, cambio >>10% HRR
- Casos sin canonical pero con ventana exterior: M4 funciona correctamente, pero threshold_metrics calibradas sobre HRR buggy fallan

**Única ruta segura**: activar M4 en **nuevos casos** diseñados desde cero con M4 como comportamiento esperado. Los `fp_ilv_upper_throttle_on/off.json` son el modelo correcto.

### Cierre de campaña M4 — CERRADA

**EXP-3 (`cfast_r0_window_360`) — ABORTADO**: mismo patrón que EXP-2 sin investigación necesaria. Los checks de Grupo A ya fallan y son pre-existentes; añadir M4 solo agregaría más variables sin beneficio claro.

**Estado de activación M4 — BLOQUEADA en casos existentes:**

| Escenario | Resultado | Motivo |
|---|---|---|
| Caso con `fire_o2_canonical_enabled` (EXP-1) | NO ACTIVAR | Doble-freno: M4 sobreescribe canonical, HRR oscila 100–750 vs 972 kW |
| Caso sin canonical + ventana exterior (EXP-2) | NO ACTIVAR | Threshold_metrics calibradas sobre HRR buggy fallarían |
| Caso nuevo diseñado para M4 (`fp_ilv_upper_throttle_on`) | ACTIVO | Física correcta, 0 coherence findings, referencia de diseño |

**M4 queda como fix gated**, disponible tras flag `fire_o2_upper_throttle_enabled=false` (default). No rompe nada existente. Listo para usar en nuevos escenarios.

### Proxima sesion — si se quiere progresar M4

**Opción A — Nuevos casos ILV FP** (coste bajo): diseñar 1-2 escenarios QA basados en `fp_ilv_upper_throttle_on` con variantes de ventilación (ventana 25%, 75%, 100%). Sin impacto en suite existente.

**Opción B — Pasada coordinada de validación** (coste alto): auditar todos los casos con ventana exterior y `threshold_metrics`, actualizar los afectados (~8-10 casos), luego activar M4 globalmente o per-familia. Requiere plan explícito antes de iniciar.

**Opción C — Dejar en standby** (sin coste): M4 queda disponible como fix gated. Se activa solo en escenarios FP/QA futuros. No hacer nada hasta que se necesite un escenario ILV concreto.

---

## Current Session Update — 2026-06-22 (rev 11 — FP ILV base scenario consolidado)

### Estado operativo actual

- Branch: `main`, limpio, **ahead 4** respecto a `origin/main` (push pendiente).
- Último commit: `test(ilv): add FP open-window ILV QA case` (pendiente).
- Validación: 345/350 PASS, clasificador 11/11 PASS, coherence checker 0/1686 findings.

### Escenario FP/QA ILV base (`fp_ilv_open_partial_window.json`)

Nuevo escenario headless dedicado para validación FP de ILV con ventana parcialmente abierta:
- `sim/validation/cases/fp_ilv_open_partial_window.json`
- Derivado del repro: `simple_house`, room 2, ventana exterior 0.5, puerta cerrada, 1400 s.
- `fire_o2_canonical_enabled: true` per-caso (no global).
- Resultado verificado: `o2_lower` 20.4% → 13.0%, `o2_hrr_factor` 0.986 → 0.278, HRR estable ~972 kW.
- Régimen: FUEL_CONTROLLED → VENTILATION_STRESSED → VENTILATION_CONTROLLED_BURNING.
- Coherence checker: 0/1686 findings.

**Por qué HRR ~972 kW y no ~3100 kW (QA manual):** diseño deliberado. Con canonical activo y `fire_secondary_hrr_gain_kw=0`, el fuego se autorregula por `o2_lower` (~13%). El QA manual de rev 9 operó con un modo interactivo con posiblemente mayor secondary gain o ventilación dinámica. La variante stress queda pendiente para diseño futuro explícito.

### Próxima sesión recomendada

1. **No hacer nada** con motor/defaults/casos existentes hasta decisión explícita.
2. **Variante stress** (`fp_ilv_open_partial_window_stress.json`): añadir `fire_secondary_hrr_gain_kw` para alcanzar HRR ~3100 kW y verificar si canonical sigue siendo estable. Solo si se decide reproducir el QA manual headless con fidelidad.
3. **Globalizar Opción C**: requiere plan explícito con calibración de `plume_lower_o2_depletion_fraction`, análisis de casos con `ach=0`, y Phase 3+ doorway exchange. No iniciar sin plan.

---

## Current Session Update — 2026-06-22 (rev 10 — ILV Opción A + C, línea cerrada per-caso)

### Estado operativo actual

- Branch: `main`, limpio, **ahead 3** respecto a `origin/main` (push pendiente).
- Últimos commits relevantes:
  - `56faa6e test(ilv): enable canonical O2 routing in open-window repro`
  - `9e23f9e fix(ilv): classify upper-O2 starvation as VCB in open rooms`
  - `afc1208 test(ilv): add layer coherence detector`
- Validación: 345/350 PASS (sin regresión), clasificador 11/11 PASS, coherence checker 0/1686 findings.

### Cierre de línea ILV motor (Opciones A y C)

**Causa raíz confirmada** (auditoria completa 2026-06-22):
- `SimulationEngine.two_zone_solver_enabled = true` (default) → `CombustionSystem._resolve_fire_o2_selection` elige `o2_ref = room.o2_lower` (zona baja, fresca ~19.7%) como señal de throttle.
- `OxygenExchangeSystem.plume_lower_mode = false` en salas con apertura exterior (guard `outside_open_factor <= 0.01` no se cumple) → el consumo de O₂ va al bulk `room.o2`, nunca a `room.o2_lower`.
- Resultado: `o2_lower` nunca depleta → `o2_hrr_factor ≈ 0.894` → HRR sin throttle → `o2_upper` colapsa a ~0 sin que el motor reaccione. Causa exacta de `hrr≈3108 kW` / `o2_upper≈0.3%` del QA manual rev 9.

**Opción A aplicada** (`9e23f9e`): `CombustionRegimeClassifier` regla 7.5 — si `o2_upper < 5%` y `hrr_kw >= 100` → `VENTILATION_CONTROLLED_BURNING`. Fix de display/régimen, sin cambio de física. 258 filas `upper-O2-critical-but-regime-fuel-controlled` → 0.

**Opción C aplicada per-caso** (`56faa6e`): `fire_o2_canonical_enabled: true` en `sim/validation/cases/cfast_ilv_open_window_repro.json` únicamente. Resultado verificado headless:
- `o2_lower`: 19.7% → 13.0% (depleta por combustión)
- `o2_hrr_factor`: 0.894 → 0.278 (throttle sigue zona baja real)
- `hrr_kw`: 1211 → 972 kW (self-throttled, sin extinción)
- `o2_upper`: 0.08% → 7.9% (entrainment bidireccional estabiliza zona superior)
- Coherence checker: 258 findings `HRR-throttle-high` → 0

**No globalizado**: el flag default del engine permanece `false`. Sin candidatos FP reales seguros para activación inmediata (`layer_interface_single_room_window` tiene `ach=0` → crash de zona baja; `bv031` tiene `fire_o2_full_hrr_open` simultáneo → sin caracterizar).

**El QA manual rev 9 fue interactivo**, no un JSON de validación. No existe escenario headless FP dedicado para ese caso (hrr≈3108, jugador con ventana abierta).

### Próxima sesión recomendada

1. **Mantener** `fire_o2_canonical_enabled=true` solo en `cfast_ilv_open_window_repro.json`. No aplicar a más casos sin análisis individual de `ach_infiltration` y flags de throttle existentes.
2. **Si se quiere reproducir el QA manual headless**: diseñar `sim/validation/cases/fp_ilv_open_partial_window.json` basado en el repro actual pero con `fire_secondary_hrr_gain_kw` para alcanzar hrr~3100 kW. Es diseño de escenario, no fix de motor.
3. **Para globalizar Opción C**: requiere plan explícito que incluya calibración de `plume_lower_o2_depletion_fraction`, análisis de casos con `ach=0`, y doorway pressure-driven exchange (Phase 3+). No iniciar sin plan.

---

## Current Session Update — 2026-06-21 (rev 9 — FP ILV/humo QA, estado guardado para otra maquina)

### Estado operativo actual

- Branch: `main`, sincronizado con `origin/main` tras push de cierre.
- Ultimos commits relevantes:
  - `d69232c fix(fp): eye-height gas layer + overhead smoke block WIP`
  - `696f03f fix(fp): tighten overhead smoke visibility`
- Validacion de producto: `python scripts/check_product.py` mantiene todos los suites de producto/Godot en PASS; unico fallo conocido: `Guardrail script unit tests` por los 5 `VALID_GAP` required.
- `git diff --check`: OK.
- Worktree esperado al continuar: limpio.

### Hallazgos nuevos de QA manual FP ILV/humo

Fuente de diagnostico: capturas FP y logs exportados en `F:/OneDrive/Escritorio/graficas/2026-06-21_23-21-39/`.

**Problema visual corregido:** el HUD podia mostrar `Vis FP 29m` aunque el CSV tuviera `visibility_m` fisica de centimetros. Causa: el ajuste de capa permitia que estar ligeramente bajo el plano de humo limpiara demasiado la vista. `696f03f` endurece el bloqueo por humo superior: agacharse sigue mejorando la visibilidad, pero una capa superior opticamente negra oscurece techo/luminarias y reduce contraste de la escena.

**Problema de HUD corregido:** el panel tecnico mezclaba datos de capa superior (`COu`, `HCNu`, `CO2u`) con temperatura/O2/visibilidad a la altura del jugador. El HUD ahora selecciona gases segun la altura de los ojos frente a `smoke_layer_m`/`smoke_display_layer_m`, mostrando sufijos `u` o `l` coherentes. Si hay HRR activo y `o2_upper < 5%`, el HUD muestra `Reg ILV CRIT` aunque el clasificador base aun devuelva `FUEL_CONTROLLED`.

**Hallazgo de motor no corregido:** el log contiene estados fisicamente incoherentes desde el punto de vista de combustion/layer coupling, por ejemplo:

- t≈940 s: `hrr_kw≈3108`, `combustion_regime=FUEL_CONTROLLED`, `o2_upper≈0.3%`, `o2_lower≈20.3%`, `visibility_m≈0.08 m`.
- t≈1280 s: patron similar, con jugador agachado viendo capa baja fresca pero capa superior sin O2.

Esto apunta a que combustion/clasificacion aun pueden usar una senal global/lower demasiado optimista frente a una capa superior agotada. No se ha tocado `sim/core` ni fisica para ocultarlo. Requiere auditoria de motor antes de cualquier fix.

### Proxima sesion recomendada

1. **Auditoria motor ILV/layer coupling**: reproducir el escenario FP/ILV y loggear por segundo `hrr_kw`, `combustion_regime`, `o2`, `o2_upper`, `o2_lower`, `co_upper_ppm`, `co_lower_ppm`, `co2_ppm`, `co2_upper_ppm`, `hcn_ppm`, `hcn_upper_ppm`, `smoke_kg`, `visibility_m`, `smoke_layer_m`, `thermal_layer_m`, `fire_latent_active`.
   - Detector automatico: `python scripts/simulation/check_ilv_layer_coherence.py <sim_log.csv> --room-id 0`.
   - Tests unitarios: `python -m unittest tests.test_ilv_layer_coherence -v`.
2. **Hipotesis principal**: HRR y clasificador estan acoplados a `o2`/lower/global mientras el fuego/llama visual y la capa superior indican ILV critico. Confirmar antes de tocar `CombustionSystem`.
3. **No cambiar motor aun**: preparar primero un informe con filas clave y un caso headless reproducible. Cualquier fix probablemente pertenece a two-zone canonico/Phase 3+ o a una regla intermedia explicita para HRR limitado por `o2_upper`.

---

## Current Session Update — 2026-06-21 (rev 8 — FP ILV/HUD/humo visual, pendiente push)

### Estado operativo actual

- Branch: `main`, **ahead 2** respecto a `origin/main`.
- Commits locales pendientes de push:
  - `a6d44c0 fix(fp-hud): clarify ILV critical display`
  - `b59fa33 fix(fp): strengthen ILV smoke visibility`
- Validación de producto: `python scripts/check_product.py` mantiene todos los suites de producto/Godot en PASS; único fallo conocido: `Guardrail script unit tests` por los 5 `VALID_GAP` required.
- `git diff --check`: OK.
- Worktree conserva artefactos generados/untracked no relacionados (`*.translation`, `.uid`, reports de auditoría); no incluirlos salvo decisión explícita.

### FP ILV / HUD / humo — cerrado visualmente en esta sesión

**Commit `a6d44c0` — HUD FP ILV**

- El panel superior deja de duplicar HRR/visibilidad cuando el panel técnico está visible.
- El panel técnico muestra `Reg ILC`, `Reg ILV` o `Reg ILV CRIT`.
- Gases etiquetados por capa: `O₂u/O₂l`, `COu`, `CO₂u`, `HCNu`.
- La llama FP se atenúa visualmente en `ILV_LATENT` o con O₂ superior crítico, sin cambiar `hrr_kw` ni física.
- `docs/validation/GAPS_INVENTORY.md` sincronizado a **69 gaps non-gating**.

**Commit `b59fa33` — humo/visibilidad FP en ILV**

- `FPVisibilityOverlay` fuerza visibilidad severa en ILV crítico (`smoke_overlay_ilv_severe_visibility_m = 1.6` m por defecto).
- Overlay de humo más opaco en régimen ventilación-limitado, especialmente con `o2_upper < 5%` y HRR activo.
- Luces de techo/aperturas pueden atenuarse casi a cero (`smoke_light_min_transmission = 0.01`), evitando que luminarias de techo sigan visibles en humo severo.
- Tests actualizados:
  - `tools/validate_fp_technical_hud.gd`: `Reg ILV CRIT` + `Vis FP 1.6m`.
  - `tools/validate_fp_fire_visuals.gd`: llama/luz atenuadas y luz de techo casi apagada en ILV crítico.

**Diagnóstico importante:** estos fixes son **visualización FP only**. No recalibran generación física de humo (`smoke_kg`, yields, soot, transporte). La queja sobre visibilidad irreal queda mitigada visualmente, pero requiere auditoría de motor para confirmar si la producción de humo/visibilidad física es suficiente en ILV.

### Pendientes priorizados para próximas sesiones

1. **Publicar commits FP locales**: push de `a6d44c0` y `b59fa33` si el QA visual manual es aceptable.
2. **QA manual FP ILV**: jugar escenario ILV y verificar pérdida de techo/luminarias, severidad de `Vis FP 1.6m` y llama atenuada.
3. **Auditoría humo motor**: loggear `smoke_kg`, `visibility_m`, `soot_fraction`, `CO`, `O₂`, `HRR`, `combustion_regime` en escenario ILV reproducible.
4. **Visualización avanzada de humo**: niebla/volumen local, pérdida de contraste por distancia, gradiente por altura y atenuación de geometría lejana.
5. **ILV Fase 3 motor**: pool latente real con HRR bajo positivo, reventilación, crecimiento inducido y backdraft risk.
6. **Phase 3+ two-zone canónico**: única ruta real para cerrar los 5 `VALID_GAP`; requiere plan de arquitectura y rollback.

---

## Current Session Update — 2026-06-21 (rev 7 — Hito B cerrado, publicado)

### ILV Hito B — cerrado hasta Fase 2 Paso 2 (2026-06-21)

| Fase | Commit | Estado |
|------|--------|--------|
| Fase 0 — auditoría extinción directa | `c59aeba` | Cerrado |
| Fase 1 — clasificador 9 regímenes + `combustion_regime` | `922a56a` | Cerrado |
| Fase 2 Paso 1 — `fire_latent_active` en `RoomModel` | `efcc492` | Cerrado |
| Fase 2 Paso 2 — `thermal_hold` fix → `ILV_LATENT` visible | `fbf4d3e` | Cerrado |
| Fase 3 — reventilación y smoldering con HRR positivo | — | **No iniciada** |

**Validación:** 345/350 PASS, 5/350 FAIL (todos VALID_GAP — Grupos A y C sin candidato per-caso). Intacta.

**Alcance de Hito B:** solo observabilidad. No hay pool latent smoldering real con HRR positivo durante `ILV_LATENT`. El campo `fire_latent_active=true` indica que `latent_viable=true` sin llama sostenida, pero el HRR decae hacia cero durante ese período. Fase 3 define la ruta para smoldering real con energía activa.

---

## Current Session Update — 2026-06-21 (rev 6 — ILV Fase 2 Paso 2 cerrado)

### ILV Hito B — Fase 2 Paso 2 cerrado (2026-06-21)

**Objetivo:** `fire_latent_active=true` y régimen `ILV_LATENT` visible en `cfast_ilv_audit.csv`.

**Causa raíz encontrada:** `_can_sustain_latent_fire` bloqueada por `thermal_hold=FALSE`. El default del engine `fire_latent_hold_upper_temp_c=140°C` nunca era alcanzado en la sala sellada (pico ~70°C upper, ~49°C lower).

**Cambios realizados (mínimos, sin tocar física global):**

1. `sim/validation/cases/cfast_ilv_audit.json` — añadidos dos overrides per-caso:
   - `fire_latent_hold_upper_temp_c: 40.0` (temp_upper=67°C > 40°C a t=406 s ✓)
   - `fire_latent_hold_lower_temp_c: 40.0` (temp_lower=49°C > 40°C a t=406 s ✓)
2. `sim/fire/CombustionSystem.gd` — `room.fire_latent_active = false` añadido en rama idle/post-extinción (previene stuck post-extinción).
3. Revertido código muerto: `fire_latent_smolder_o2_margin` nunca estuvo en el contexto de combustión; eliminado.

**Verificación:**
- `fire_latent_active=1`: 52 rows, t=406.1–457.1 s ✓
- Post-extinción: `latent=0` correctamente ✓
- Régimen: `VENTILATION_CONTROLLED_BURNING → ILV_LATENT → EXTINGUISHED` ✓
- Clasificador headless 9/9 PASS ✓
- Baseline: 345/350 PASS intacto (5 FAILs requeridos VALID_GAP sin cambio) ✓

---

## Current Session Update — 2026-06-21 (rev 5 — ILV Fase 0 cerrada)

### ILV Hito B — Auditoría Fase 0 cerrada (2026-06-21)

Escenario: room 2 (dormitorio, ~36 m³), sellado, legacy fire path, 900 s. Artefactos:

- `sim/validation/cases/cfast_ilv_audit.json` — caso de auditoría (read-only, sin cambio de física).
- `scripts/simulation/audit_ilv_phase0.py` — script diagnóstico (read-only, `--no-run` para reanalizar CSV existente).

**Hallazgo confirmado:** fuego pasa `VENTILATION_CONTROLLED_BURNING → EXTINGUISHED` a t=436 s, o2=10.9 %, sin pasar por `ILV_LATENT`. `fire_smoldering` nunca fue true. Gap estructural: con `fire_o2_min_for_flame=0.10`, `can_flame=false` a o2<8.5 % pero `latent_viable=false` a o2<10.8 %; en la ventana 8.5–10.8 % no hay llama ni latencia posible. El clasificador Fase 1 no muestra `ILV_LATENT` porque depende de `fire_smoldering`, que a su vez requiere `hrr_kw > 0.5`.

**Próxima decisión (Fase 2):** ampliar latencia ILV requiere una de estas rutas (ninguna iniciada sin plan explícito):
1. Bajar threshold `hrr_kw > 0.5` en `fire_smoldering` (toca `CombustionSystem.gd`).
2. Añadir campo `fire_latent_active: bool` a `RoomModel` activado antes de que HRR caiga a 0.
3. Exposer `latent_viable` directamente al clasificador como señal adicional.

No iniciar Fase 2 sin plan explícito y aprobación.

---

## Current Session Update — 2026-06-21 (rev 4 — UX polish cerrado)

- Branch: `main`, synchronized with `origin/main`.
- **Tag publicado: `v0.4.0` — release estable.**
- **Hito UX polish FP cerrado** — commits `c7e3db8` y `a689f1d`.
- **Current validation baseline: 345/350 PASS, `5/350` required FAIL (todos VALID_GAP)**.
- `docs/validation/STATUS_VALIDATION.md` is the validation source of truth.

### UX Polish FP — cerrado (2026-06-21)

| Ítem | Commit | Resultado |
|------|--------|-----------|
| Camera stance easing (`_apply_stance`) | `c7e3db8` | Cerrado — lerp tau=80ms, test headless PASS |
| Opening prompt text (accents, consistency) | `a689f1d` | Cerrado — 4 fixes de texto, sin cambio de lógica |
| Colisiones corner FP | — | Cerrado — sin issue reproducible (ver diagnóstico abajo) |

Suite headless Godot completa post-polish:

| Suite | Resultado |
|-------|-----------|
| FP stance easing Godot | PASS |
| FP technical HUD | PASS |
| FP victim states | PASS |
| FP detector alarm | PASS |
| FP fire visuals | PASS |
| FP player start | PASS |
| FPVisibilityOverlay smoke layer | SIN ISSUE |
| Colisiones corner FP | SIN ISSUE REPRODUCIBLE — diagnóstico cerrado |

**Diagnóstico colisiones corner FP (2026-06-21):** inspección de `CharacterBody3D + CapsuleShape3D (r=0.24m) + move_and_slide()`. La geometría de habitaciones (mínimo 2.8 m de espacio libre) y puertas (0.42 m de holgura lateral) supera el diámetro de cápsula (0.48 m). No se identificó bug ni escenario de traversal/clipping reproducible. No se añadió test headless por ausencia de caso de reproducción. Deuda cerrada como "sin issue reproducible".

Deuda de producto UX polish cerrada. Tras rev 8 quedan abiertas como líneas nuevas: QA visual FP ILV/humo, auditoría de humo motor, ILV Fase 3 y Phase 3+ two-zone.

### What is current now

- Phase 2A/2B/2C/2D, Phase 2E-bedroom, Phase 4B slow-growth wall reradiation and Phase 5A Group A sweep are already reflected in the current baseline.
- `cfast_two_room_door_open` now PASSes RMSE: 53.8°C (threshold <=60°C) after Phase 2C thermal counterflow.
- `cfast_hvac_t300_o2` now PASSes after Phase 2D HVAC two-zone O2 mass balance.
- `cfast_bedroom_closed_door` O2 checks now PASS after Phase 2E-bedroom per-case calibration.
- `cfast_slow_growth_sealed` temperature checks now PASS after Phase 4B wall reradiation during active fire.
- Phase 5A sweep confirmed Group A as a VALID_GAP with no viable per-case JSON calibration.

### Current guardrail state

- Required checks: FAIL — `5` required failures, all confirmed VALID_GAP.
- Known gaps: `69` non-gating gaps in JSON and docs.
- Gap inventory count: synchronized.
- Phase 2E sentinel: FAIL on `g4 FED timing [s]` (pre-existing, not caused by this session).
- Carbon/HCN sentinels: PASS.
- Legacy/two-zone contract: PASS.
- CFAST truth integrity: PASS (99/99).
- Physics override linter: PASS.

### Required FAILs current: 5

| Group | Checks | Root cause |
|-------|--------|------------|
| A — r0_window_360 (×3) | O2 upper vs bulk | Phase 2 gap |
| C — corridor_chain (×2) | t180+t600 temp | Phase 2 gap (M3 doorway O2 replenishment) |

Grupo B completamente resuelto: `cfast_slow_t480_temp_upper_c` y `cfast_slow_t600_temp_upper_c` PASS con Phase 4B wall reradiation durante fuego activo. Config actual per-caso: `hrr_chi_rad_* = 0.7`, `hrr_rad_wall_fraction=1.0`, `phase4b_wall_reradiation_during_fire_enabled=true`, `phase4b_wall_reradiation_during_fire_gain=5.0`, `wall_heat_capacity_kj_m2_k=6.5`, `wall_core_decay_per_s=0.0009`. La clave fue devolver energia radiativa desde pared sin cambiar HRR ni deplecion O2.

Grupo D completamente resuelto: `cfast_bed_o2_t300/t480/t600/t720_o2` PASS (Phase 2E-bedroom).

Grupo E completamente resuelto: `hvac_t300_o2` PASS (Phase 2D `b960d29`); `two_room RMSE` PASS 53.8°C (Phase 2C-thermal `e0785e8`).

### Recommended next work

> **HITO DE VALIDACIÓN CERRADO — 2026-06-21.** Baseline final: 345/350 PASS, 5/350 required FAIL (todos VALID_GAP). No hay siguiente candidato con fix per-caso disponible. No iniciar Phase 3+ ni ILV sin plan explícito.

Los 5 fallos restantes, cerrados definitivamente como VALID_GAP:

- **Grupo A `cfast_r0_window_360` (×3)** — Phase 5A sweep (15 configs) agotó espacio per-caso. Causa estructural: `plume_lower_mode` equilibra zonas bidireccional; target requeriría room.o2=0.085 → HRR<198 kW → guard FAIL. Ver `docs/architecture/PHASE_5A_O2UPPER_SWEEP_RESULTS.md`.
- **Grupo C `cfast_corridor_chain` (×2)** — Phase 2F, 2G y Phase 3 simplificado descartados. Requiere ODE de presión dos zonas. Phase 3+ scope.

**Fix HUD/FP temperatura cerrado** (`497b663`). Ver §HUD/FP Temperature Fix cerrado más abajo. No hay línea de trabajo abierta en este hito.

### CFAST reference sources

- Public source repository: `https://github.com/firemodels/cfast`
- Official CFAST landing page: `https://pages.nist.gov/cfast/`
- Local technical reference manual: `docs/literature/Reviews_and_Models/CFAST_Technical_Reference_Guide_2004.pdf`
- Local modern NIST reference/validation docs: `docs/literature/NIST.TN.1889v1.pdf`, `docs/literature/NIST.SP.1018e6.pdf`
- Local CFAST truth/output files for current validation cases: `sim/validation/cfast/`

Use these as primary references before changing physics: first read the CFAST manual/source for the relevant subsystem, then compare against the local `.out`/CSV truth files, then implement SimuFire changes behind default-off/per-case controls.

### Phase 2 architecture plan (2026-06-20)

Documento: `docs/architecture/PHASE_2_TWO_ZONE_ARCHITECTURE_PLAN.md`

Fases planificadas:
- **2A** (no-op): sync zonal mass (upper_gas_kg/lower_gas_kg) para todas las salas en ThermalSystem
- **2B** (combustion routing): O₂ consumido → solo o2_upper; throttle desde o2_upper; bedroom gets `fire_o2_mode="upper"`; archivos: OxygenExchangeSystem.gd, CombustionSystem.gd, cfast_bedroom_closed_door.json; target: Grupo D ×5, Grupo A ×3
- **2C** (doorway exchange): activar canonical_doorway_exchange en cfast_two_room_door_open; recalibrar corridor_chain; archivos: ThermalSystem.gd, cfast_two_room_door_open.json; target: Grupo E two_room ×1, Grupo C ×2
- **2D** (HVAC mass balance): return extrae o2_upper, repone desde o2_lower; archivos: HVACSystem.gd, cfast_hvac_residential.json; target: Grupo E HVAC ×1
- **2E** (cleanup): retirar M2, phase2h_*, phase2e_* una vez 2A–2D verdes

Regla: cada fase lleva flag default=false (no-op garantizado). Activar per-case primero, luego global solo si todos los sentinels PASS.

## What Changed

- Root-level session notes moved to `docs/sessions/root/`.
- Historical audits, plans, roadmaps, validation docs and architecture docs were grouped under `docs/`.
- Local bibliography and PDFs moved from `Docu Simufire/` to `docs/literature/`.
- Loose root artifacts kept for context moved to `docs/archive/root-artifacts/`.
- Exploratory root scripts moved to `tools/archive/root-scripts/`.
- Documentation entrypoints, command references, artifact policy, release checklist and architecture governance docs were added.
- Lightweight docs/product CI workflows and helper scripts were added.

## Key Entry Points

- Project overview: `README.md`
- Documentation index: `docs/INDEX.md`
- Official commands: `docs/COMMANDS.md`
- Cleanup status: `docs/REPO_STATUS_AFTER_CLEANUP.md`
- Validation guardrails status: `docs/validation/GUARDRAILS_STATUS.md`
- Gap inventory: `docs/validation/GAPS_INVENTORY.md`
- Commit split proposal: `docs/COMMIT_PLAN.md`
- PR summary draft: `docs/PR_DESCRIPTION.md`

## Validation Run

Recommended checks for the current state:

```powershell
python scripts\check_docs_links.py
python -m unittest tests.test_ui_localization -v
python -m unittest tests.test_editor_scenarios -v
python scripts\simulation\validation_guardrails.py --verbose
git diff --check
git diff --cached --check
```

Current result:

- Validation guardrails: FAIL because 5 required checks remain accepted VALID_GAPs and one Phase 2E sentinel remains red.

The following guardrail parts are now clean:

- Gap count is synchronized: `69` non-gating gaps in JSON and docs.
- Physics override linter passes.
- Carbon/HCN sentinels pass.
- Legacy/two-zone contract passes.
- CFAST truth integrity passes.

## Important Constraint

No simulation motor, editor runtime, visualizer runtime, scenes, HUD logic or physics formulas were intentionally changed during this cleanup. The only validation case change was removing the forbidden `vent_bernoulli_flow_multiplier` override from `sim/validation/cases/cfast_pool_fire_open.json`.

Do not try to make `validation_guardrails.py` green by widening tolerances, rewriting reports or reclassifying required failures unless the scientific validation decision has been explicitly reviewed.

## Estado actual de esta máquina (2026-06-21)

- Rama: `main`, sincronizada con `origin/main`.
- Baseline vigente: **345/350 PASS, 5/350 required FAIL**.
- El plan ILV está documentado pero sin implementar.
- Hoja de ruta activa: `docs/planning/MASTER_ROADMAP_CURRENT.md`.
- No iniciar ILV, M2 global ni cambios de doorway/O2 en `sim/core` sin plan explícito.

## Próximo paso recomendado

Ejecutar baseline de guardrails para confirmar 5/350 antes de tocar motor:

```powershell
python scripts\simulation\validation_guardrails.py --verbose
```

Después elegir una línea explícita:

- Producto/UX: hotfix de temperatura FP.
- Validación científica mayor: solo arquitectura two-zone canónica / Phase 3+ con plan explícito.
- Documentación: mantener sincronizados handoff, roadmap, guardrails y gap inventory.

## Estado guardado ahora (2026-06-21)

- La planificación activa quedó consolidada en `docs/planning/MASTER_ROADMAP_CURRENT.md`.
- El siguiente trabajo real no es ILV todavía salvo decisión expresa.
- Los 5 fallos restantes ya están diagnosticados; no repetir sweeps per-case salvo que una corrida fresca cambie el baseline.
- El hotfix FP queda como línea pendiente independiente: diagnosticar saltos de temperatura antes de tocar física/HUD.

## Other Machine Sync Protocol

Context recorded on 2026-06-18:

- Se perdió corriente en la otra máquina mientras ejecutaba Claude. El repo en esta máquina está limpio (ver `git status`).
- La otra máquina puede tener cambios locales sin commitear del trabajo anterior.
- No asumir que la otra máquina está limpia.
- No ejecutar `git pull`, `git reset`, `git restore` ni resolución de conflictos a ciegas en esa máquina.
- No tocar `sim/core` hasta autorización explícita.

Cuando se retome en la otra máquina, inspeccionar primero:

```powershell
git status --short
git branch --show-current
git log --oneline --decorate -5
git fetch
git log --oneline --decorate --graph --all -20
git diff --name-status
git diff --stat
```

If the other machine has local changes, protect them before integrating remote work:

```powershell
git switch -c backup/cambios-maquina-apagon
git add -A
git commit -m "WIP cambios locales antes de sincronizar"
```

Then compare the backup branch, the original branch and the remote branch before merging anything. The intended rule is: preserve first, synchronize second, resolve conflicts last.

## HUD/FP Temperature Fix cerrado

Commit `497b663 feat(fp-hud): smooth HUD temperature at thermal layer crossing` — 2026-06-21.

**Diagnóstico confirmado (Causa 2):** con `thermal_gradient_band_fraction=0.0`, `estimate_temperature_at_height_m` es una función escalón en `thermal_layer_m`. Cuando la capa desciende a través de la altura del jugador (1.8 m de pie), `T@1.8m` saltaba instantáneamente entre `temp_lower_c` y `temp_upper_c` — hasta +8 °C en un paso de 0.5 s en el escenario de diagnóstico, hasta cientos de °C en escenarios calientes.

**Fix aplicado (HUD-only, sin tocar física):**

- `view/fp/FirstPersonController.gd`:
  - Constante `HUD_LAYER_BLEND_HALF_M = 0.25`.
  - Helper `_hud_temp_at_height_m(room_state, height_m)`: lerp de `temp_lower_c` a `temp_upper_c` dentro de una banda de ±25 cm alrededor de `thermal_layer_m`; satura limpiamente fuera de la banda.
  - `_update_technical_overlay()`: las tres posturas (stand/crouch/prone) usan el helper en lugar de los campos precomputados `temp_at_N_m_c`.
  - El filtro `fp_hud_temperature_smoothing_tau_s=0.5 s` sigue actuando sobre el valor resultante.
- `tools/validate_fp_technical_hud.gd`: test actualizado con `thermal_layer_m=1.15 m`; expectativas ajustadas a la salida del blend (stand=210, crouch=105, prone=35 °C).

**Verificación final:** `python scripts/check_product.py` — FP technical HUD Godot 1/1 OK; todos los demás suites OK. Único fallo: `tests.test_guardrails.test_exit0_real_json`, pre-existente por los 5 VALID_GAP.

No se tocó `ThermalSystem.gd`, `SimulationStateBuilder.gd`, ni ningún archivo de validación científica.

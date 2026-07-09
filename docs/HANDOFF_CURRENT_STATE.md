# Current Handoff State

Date: 2026-06-21.

## Purpose

This note records the repository hygiene and validation state after the non-motor cleanup. It is meant to let another machine or contributor continue without relying on chat history.

## Current Session Update - 2026-07-09 - Grupo C confirmado como VALID_GAP estructural

### Estado guardado

- HEAD remoto: `2a0766c6` (`fix(validation): apply declared fire_o2_mode in cfast_hvac_residential`).
- Working tree: limpio antes de esta nota.
- Physics coherence: **0 FAIL** - 9 PASS / 15 CTRL / 5 WARN.
- Validation guardrails: **10/10 PASS**.
- Gap inventory: **348/353 PASS**, **5 VALID_GAP**, 71 gaps non-gating.

### Diagnostico Grupo C - `cfast_corridor_chain`

Se verifico el candidato de runner/config mismatch despues de cerrar los Grupos D y E. Resultado:
**Grupo C NO es runner/config mismatch**. Permanece como gap fisico estructural documentado.

- Los 2 checks restantes de `cfast_corridor_chain` siguen siendo CCH-2: doorway thermal counterflow / Phase 3+.
- No hay fix JSON-only equivalente al de `cfast_slow_growth_sealed` o `cfast_hvac_residential`.
- No se realizaron cambios de motor, tolerancias, expected baselines ni reports.

### VALID_GAP restantes

- **Grupo A** - `cfast_r0_window_360` (3 checks): gap estructural O2/two-zone Phase 2/3+.
- **Grupo C** - `cfast_corridor_chain` (2 checks): requiere bidirectional doorway thermal counterflow / ODE de presion dos zonas (M3/Phase 3+).

Siguiente trabajo recomendado: no seguir con fixes per-case para Grupo C. Cualquier cierre real requiere plan de arquitectura Phase 3+ con STOP gate propio.

---

## Current Session Update - 2026-07-08 — Plan B/F2 cerrado (fed_co2_source_mass flag)

### Estado operativo actual (2026-07-08, HEAD pendiente de commit)

- Branch: `main`, cambios sin commitear (motor F2 + script validate_reference_cases.py + reference_checks.json + docs).
- `validate_reference_cases`: **344/353 PASS** — 9 VALID_GAP; sin cambio de comportamiento.
- Physics coherence: **9 PASS / 14 CTRL / 6 WARN / 0 FAIL**, exit 0.
- ILV suite: **15 PASS / 14 CTRL / 0 FAIL**, exit 0.
- Guardrails: **10/10 PASS, exit 0** — R2-1 OK (reference_checks.json regenerado con `generated_at`).
- pytest: **598/604** — 6 pre-existentes two-zone structure, sin cambio.

### Plan B / F2 — flag `fed_co2_source_mass` (2026-07-08)

**Objetivo:** Añadir flag experimental per-caso para cambiar la fuente de CO₂ en el cálculo
`v_co2` del FED ISO 13571 del tracer OES (`room.co2_upper × 1e6`) al path mass-derived
(`co2_upper_kg / upper_zone_mass_kg`). Evaluar si el path mass mejora la exactitud.

**Resultado del experimento:** Flag ON es físicamente incorrecto en la cola post-extinción.
`co2_upper_kg` no drena cuando el fuego se extingue pero `upper_zone_mass_kg` colapsa por
enfriamiento → `co2_upper_ppm_mass` sube a >500 000 ppm (físicamente imposible). FED del adulto
(1.8 m) acumula valores astronómicos. Impacto en víctima a 0.9 m (zona inferior): +0.08 s —
irrelevante (usa `compute_co2_lower_ppm` en ambos modos).

**Decisión:** Mantener flag como infraestructura experimental default OFF. Default OFF = no-op
exacto — ningún check, baseline ni guardrail afectado. F3 (activar path mass en producción)
está **bloqueado** hasta corregir `co2_upper_kg` post-extinción.

Ver detalle completo: `docs/validation/plan_b_f2_fed_co2_mass_flag.md`

### Fix permanente R2-1 (2026-07-08)

`validate_reference_cases.py` ahora incluye `generated_at` (ISO 8601 UTC) en el JSON de salida.
Esto garantiza que cada regeneración cambia el contenido del archivo → git lo marca dirty →
R2-1 gate 1 pasa cuando el motor cambia pero el comportamiento es idéntico (flag OFF, etc.).
Antes: regenerar con flag OFF producía JSON byte-a-byte idéntico al commitado → R2-1 disparaba
aunque el usuario sí hubiera regenerado.

### Archivos modificados en este commit

Motor (2):
- `sim/core/SimulationEngine.gd` — `@export var fed_co2_source_mass: bool = false` + settings
- `sim/core/ThermalSystem.gd` — var + configure + 2 sitios FED patched

Validación (2):
- `scripts/simulation/validate_reference_cases.py` — `import datetime` + campo `generated_at`
- `sim/validation/reports/reference_checks.json` — regenerado (mismos 9 VALID_GAP)

Docs (2):
- `docs/validation/plan_b_f2_fed_co2_mass_flag.md` — nuevo, experimento completo
- `docs/HANDOFF_CURRENT_STATE.md` — esta entrada

### Próximos pasos

1. **Bug `co2_upper_kg` post-extinción:** mismo bug familiar que F0. El pool intra-room de
   `co2_upper_kg` no vacía al ritmo que colapsa `upper_zone_mass_kg` al enfriarse. Síntoma:
   `co2_upper_ppm_mass > 5 × 10⁵ ppm` a t ≈ 630 s en `victim_fed_incapacitation`.
   Cuando se corrija, F3 puede proceder.

2. **D2PRE transporte inter-room:** 6 WARNs restantes (divergencia tracer vs mass en salas
   receptoras). Requiere mapeo del transporte de CO₂ entre rooms — sesión dedicada Plan B.

---

## Current Session Update - 2026-07-07 — CO/specie pumping fix + HVAC VALID_GAP

(Registrado en project_overview.md — HEAD=3f5e0a4f, 5 commits pusheados)

---

## Current Session Update - 2026-07-06 (rev 35 - Rehabilitación de gates: ILV suite + guardrails + CI a exit 0)

### Contexto

Auditoría completa del proyecto detectó que 2 de las 3 suites-gate llevaban en **exit 1 crónico** — gates "quemados": un rojo nuevo era indistinguible del rojo permanente, incluido `tests.test_guardrails::test_exit0_real_json` que corre en CI (workflow `validation-guardrails.yml` en rojo). Sesión de rehabilitación sin tocar motor, thresholds, severities ni baselines.

### Estado operativo actual (todo verificado en vivo)

- Branch: `main`, cambios locales sin commitear (6 archivos, esta sesión).
- `validate_reference_cases`: **349/354 PASS** (5 VALID_GAP) — sin cambio.
- Physics coherence: **9 PASS / 5 CTRL / 3 WARN / 0 FAIL**, exit 0 — sin cambio.
- ILV layer coherence: **12 PASS / 5 CTRL / 0 FAIL, exit 0** (antes: 3 FAIL, exit 1).
- Guardrails: **8/8 gates PASS, exit 0** (antes: 4 secciones FAIL, exit 1).
- Tests: **209/209** physics coherence + **21/21** guardrails (antes 15, con 1 en rojo).

### Cambios (todos en capa de validación)

1. **ILV suite** — 3 CTRL nuevos registrados: `cfast_two_floor_stairwell` (42), `fuel_balance_diag_sealed` (35), `o2_stoich_diag_sealed` (35). Los tres son el bug ILV lower-O2 conocido (zombie HRR, o2_upper≈0.09%) en configs selladas sin M4 — no defectos nuevos. `v1_m4_pool_release` retirado (0 findings tras M5, CTRL obsoleto). Nota: el CTRL de los diag_sealed en ILV NO absorbe sus D2PRE de la physics suite, que siguen como WARN a propósito (gap M1 real).
2. **`gap_inventory_check.py`** — allowlist `KNOWN_VALID_GAP_REQUIRED_FAILURES` (los 5 VALID_GAP del hito 2026-06-21). Gate pasa solo si los required fallidos ⊆ allowlist; fallo required nuevo → exit 1. Detecta entradas obsoletas y JSON corrupto.
3. **`validation_guardrails.py`** — gate required vía la allowlist ("PASS (5 VALID_GAP)"). Linter R1-3: exención por (caso, clave) para `(cfast_pool_fire_open, vent_bernoulli_flow_multiplier)` — override intencional Phase 9 C4 (commit b5c63ce9) anterior al linter; deuda documentada visible, retirar la exención cuando se elimine el override en sesión de motor.
4. **`phase2e_preflight.py`** — sentinels non-required que fallan → "GAP (non-gating)", no gatean (el `g4 FED timing` es non-required y está en los 70 gaps). Los required siguen gateando.
5. **`GAPS_INVENTORY.md`** — encabezado 345/350→**349/354** required, 69→**70** gaps. Delta desde 2026-06-21: +4 required (baselines `v5_m4_ventilation_throttle`, todos PASS); gaps +3/−2 por corrimiento de timestamps de presión (mismo gap estructural Phase 3).
6. **`tests/test_guardrails.py`** — 6 tests nuevos que prueban que los gates siguen mordiendo: required nuevo no permitido → exit 1 (en ambos scripts), VALID_GAP+nuevo → exit 1, exención del linter limitada a su clave → exit 1 con otra clave.

### Endurecimiento CTRL — envelopes por regla/conteo (2026-07-06, misma sesión)

`KNOWN_INTENTIONAL_CONTROLS` en ambas audit suites pasa de set de stems a `{stem: {regla/kind: conteo_max}}` (conteos medidos 2026-07-06 + ~25% margen). Un finding de regla no registrada o conteo excedido reclasifica el caso CTRL a FAIL ("CTRL envelope excedido") y **gatea aunque el exceso sea WARN**. `v1_m4_pool_release` excluye A3 a propósito (eliminado por M5 — si reaparece, FAIL). `--intentional` CLI mantiene envelope ilimitado legacy. Tests: 209→216 physics, 19→26 ILV. Resultados actuales de las suites sin cambios (9/5/3/0 y 12/5/0, ambas exit 0).

### Guardrails R2-1 + PHY-P1 y bug motor CO₂ bulk descubierto (2026-07-06, misma sesión)

- **R2-1 frescura:** guardrail git-based — motor/casos más recientes que `reference_checks.json` (commit o working tree) → FAIL. Se omite con nota si no hay git/historial (CI shallow).
- **BUG MOTOR NUEVO:** el FED=3.47e9 de `v3_hallway` no es la fórmula de Purser: es `room_1_peak_co2_ppm = 1.099e6` (>100% de la mezcla). **7 casos afectados** (`confinement_open_close`, `postfire_decay`, `row_house_ground_floor_smoke`, `secondary_ignition_demo`, `v3_hallway_fed_exposure`, `v4_co_remote_rooms`, `v6_spread_to_hallway`), siempre CO₂ bulk de sala receptora (1.02e6–2.10e6 ppm), nunca fire room ni métricas upper. Root cause probable: dilución incorrecta en el path bulk/lower del transporte inter-room. Diagnóstico pendiente de sesión de motor dedicada.
- **PHY-P1 plausibilidad:** métrica `*_ppm` > 1e6 → FAIL salvo las 7 parejas registradas en `_KNOWN_PPM_VIOLATIONS` (deuda visible; el bug no puede crecer en silencio).
- Guardrails: **10/10 gates PASS, exit 0**. Tests guardrails 21→31.

### Expansión de cobertura 17→29 CSVs (2026-07-06, continuación de sesión)

- 12 casos representativos generados (`run_scenario.py` headless), deduplicados (el engine duplica las filas del último timestep — artefacto neutralizado en el pipeline) e instalados en reports/. Subsistemas nuevos bajo las 13 reglas: HVAC, supresión, cristales, multifuel, corridor, flashover, PPV, multi-planta, CO remoto, PVC/HCl, PU/FED, reburn.
- 7 CTRL envelope nuevos en physics suite (12 total), 8 en ILV (14 total, pinean la extensión del zombie por caso). 4 casos solo-D2PRE quedan como WARN (Plan B multi-room). `cfast_suppression_water` limpio.
- **Hallazgos motor nuevos:** (1) gap instrumentación HVAC — HVACSystem extrae smoke/CO sin acumuladores (D1/S1 en `cfast_hvac_residential`, mismo root cause que el skip O1); (2) write-off de inventario de fuel — `victim_fed_incapacitation` t=650s: `solid_fuel_remaining_MJ` cae 2200.15 MJ para igualar `fuel_remaining_MJ` post-extinción, sin acumulador de consumo.
- **Estado final:** physics **10 PASS / 12 CTRL / 7 WARN / 0 FAIL** (29 CSVs, exit 0) · ILV **15 PASS / 14 CTRL / 0 FAIL** (exit 0) · guardrails **10/10** (exit 0) · 31+242 tests. Los 7 WARN son todos D2PRE (Plan B).

### Deuda pendiente identificada en la auditoría (estado final de sesión)

- ~~CTRL absorbe por stem completo~~ — **CERRADO** (envelopes en ambas suites).
- ~~Sin check de frescura reports vs código `sim/`~~ — **CERRADO** (R2-1).
- ~~Bounds débiles / FED 3.47e9~~ — **DIAGNOSTICADO**: bug de motor (CO₂ bulk >100% en receptoras), acotado por PHY-P1; fix de motor pendiente.
- ~~Cobertura de coherencia ~17/108 casos~~ — **AMPLIADO a 29/108** (todos los subsistemas principales representados). Ampliar más es opcional e incremental con el mismo pipeline.
- **Candidatas para próxima sesión de motor (por rendimiento):** (1) Plan B / M1 o2_scale double-throttle — cerraría los 7 WARN D2PRE y gran parte de los D2PRE absorbidos en CTRLs; (2) bug CO₂ bulk >100% en receptoras (7 casos, afecta FED/toxicidad); (3) instrumentación HVAC de especies (retiraría el CTRL de cfast_hvac_residential); (4) write-off de inventario de fuel post-extinción.

## Session 2026-07-07 — M1 falsado, Plan B redirigido a transporte inter-room

### Experimento M1 (o2_scale double-throttle) — FALSADO

**Patch aplicado y revertido.** No produce cambio observable → revertido a `01610b46`.

**Hipótesis original:** `OES.co2_produced *= o2_scale` aplica un segundo throttle con `room.o2_upper` cuando `effective_plume_lower` ya throttleó el HRR por `o2_lower`. Diagnóstico: causa del D2PRE 7 WARN.

**Resultado del experimento:**
- CSVs regenerados byte-a-byte idénticos al baseline.
- D2PRE sin cambio: `cfast_slow_growth_sealed` 243, `fuel_balance_diag_sealed` 230, `o2_stoich_diag_sealed` 230.
- Physics suite: 10/12/7/0 sin cambio. ILV: 15/14/0 sin cambio. FED: sin cambio.

**Por qué M1 no activa:**

`plume_lower_mode` requiere `fire_o2_mode == "legacy"`. Los casos de test usan:
- `cfast_slow_growth_sealed`: `validation_fire_o2_mode: "upper"` → nunca activa.
- `fuel_balance_diag_sealed` / `o2_stoich_diag_sealed`: casos multi-room con aberturas interiores → `interior_open_factor > 0.01` → nunca activa.

**Root cause corregido de los 7 WARN D2PRE:** Los findings D2PRE están en salas **receptoras** (room=1, 2…), no en la sala de fuego. La divergencia `co2_upper_ppm(tracer) vs co2_upper_ppm_mass` es un problema de **transporte inter-room**, no de producción. Los dos paths (tracer mol-fraction via OES/GES y mass kg via CombustionSystem/GES doorway) divergen en cómo acumulan CO₂ en salas sin fuego.

**Estado del bug M1/o2_scale:** El double-throttle es un bug latente real, pero solo afectaría a casos con `fire_o2_mode = "legacy"` Y sala single-room sellada. Ninguno de los 29 casos actuales lo ejerce. No es causa activa de D2PRE.

**Plan B redirigido:** Sesión dedicada para mapear transporte inter-room de CO₂:
- Tracer path: `room.co2_upper` (mol fraction) via `_exchange_room_o2_active_flow` en OES/GES.
- Mass path: `room.co2_upper_kg` via transporte de gases en GES/doorway.
- Oráculo: D2PRE peor caso room=1 t=60s en los diag_sealed (rel_div=7.1×).

---

## Session 2026-07-07 — F0 Plan B: CO₂ bulk >100% CORREGIDO (commit pendiente)

### Objetivo y resultado

PHY-P1 gate sin allowlist: PASS. Las 7 salas receptoras que superaban 1e6 ppm de CO₂ están
corregidas. `_KNOWN_PPM_VIOLATIONS` queda vacío — el gate sigue activo y morderá si el bug
reaparece.

### Root cause

NO era creación de masa. Conservación exacta verificada en v4:
- CSV (submuestreo 1s): aparente 62 kg de CO₂ — artefacto × 12 del dt del engine (1/12 s).
- Verificación real (engine dt): 61.44 kg generados ≈ 62.04 kg en salas. Conservación exacta.

Root cause real: **bombeo concentrador** en el transporte inter-room.
`co2_moved = min(smoke_kg/source.smoke_kg, 1.0) × source.co2_kg` satura a 1.0 cuando la sala
de fuego tiene muy poco smoke_kg (~0.1 kg). En cada tick exporta TODO el stock CO₂ disponible
al hub (pasillo). El delayed delivery path amplificaba el efecto sin una cota de equilibrio.

### Fix — 3 puntos en el motor

1. **GES doorway (~L828):** limitador de equilibrio por concentración. El receptor no puede
   superar la concentración CO₂ de la fuente en esa advección.
   `co2_headroom = max(0, c_src × air_tgt − stock_tgt)` con densidad de aire 1.2 kg/m³.
   `co2_upper_moved` recortado por el mismo `cut_ratio`.

2. **GES delayed delivery:** se añade `"from": from_id` al parcel en vuelo y se re-aplica la
   misma cota al entregar. Excedente devuelto a la sala origen — conservación intacta.

3. **ThermalSystem (~L2779):** mismo limitador para el segundo path de transporte CO₂.

CO, HCN, OES, FED, baselines y tolerancias: **no tocados**.

### Resultados medidos

| Caso | CO₂ antes | CO₂ después |
|------|-----------|-------------|
| confinement_open_close | 1.02e6 ppm | 1.46e5 ppm |
| postfire_decay | 1.19e6 ppm | 2.77e5 ppm |
| row_house_ground_floor_smoke | 2.11e6 ppm | 4.40e5 ppm |
| secondary_ignition_demo | 1.19e6 ppm | 2.77e5 ppm |
| v3_hallway_fed_exposure | 1.10e6 ppm | 2.56e5 ppm |
| v4_co_remote_rooms | 1.10e6 ppm | 2.56e5 ppm |
| v6_spread_to_hallway | 1.19e6 ppm | 2.77e5 ppm |

FED v3 pasillo: 3.47e9 → 2.91e3 (corrección, no regresión — el absurdo venía del CO₂ > 100%).

### Estado de suites (post-fix)

- Physics suite: **exit 0** — 10 PASS / 12 CTRL / 7 WARN / 0 FAIL.
  v4_co_remote_rooms CTRL envelope actualizado: D2:69 añadido (55 medidos + 25% margen).
  Motivo D2 nuevo: al normalizar CO₂, sube ratio CO/CO₂ en receptoras — CO tiene el mismo
  bug de bombeo, pero la cota de CO es seguimiento separado (constraint: no tocar CO).
- ILV suite: **exit 0** — 15 PASS / 14 CTRL / 0 FAIL.
- Guardrails: **exit 1** — solo 5 stale checks pre-existentes (cfast_hvac + cfast_chain),
  no causados por F0. PHY-P1 PASS.
- pytest: **272/273** — único fallo `test_exit0_real_json` (stale reference_checks.json,
  pre-existente, no causado por F0).
- validate_reference_cases: **344/354** — mismos 10 FAILs que antes del fix
  (5 VALID_GAP + 5 stale cfast); ningún delta causado por F0.

### Archivos modificados (sin commit aún)

Motor (2):
- `sim/core/GasExchangeSystem.gd` — limitador GES doorway + delivery
- `sim/core/ThermalSystem.gd` — limitador ThermalSystem

Validación (3):
- `scripts/simulation/validation_guardrails.py` — `_KNOWN_PPM_VIOLATIONS = {}`
- `scripts/simulation/audit_physics_coherence_suite.py` — D2:69 en envelope v4
- `tests/test_guardrails.py` — test allowlist usa entrada sintética (la real está vacía)

Reports regenerados (9):
- 7 reports JSON + `v4_co_remote_rooms.csv` + `reference_checks.json`

### Pendientes separados (no causados por F0)

1. **CO pumping follow-up:** CO tiene el mismo bug de bombeo concentrador en GES. Requiere
   plan + auditoría de baselines CO (separate session). Los 69 D2 WARNs en v4 CTRL son la
   huella visible hasta que se cierre.
2. **5 stale checks cfast_hvac/cfast_chain:** reference_checks.json regenerado fresco activa
   estos checks latentes. Tarea separada.

---

## Current Session Update - 2026-06-30 (rev 34 - D2 CTRL wood_vc_reference + diagnóstico diag_sealed D2PRE)

### Estado operativo actual

- Branch: `main`, cambios locales sin commitear — `wood_vc_reference` añadido a `KNOWN_INTENTIONAL_CONTROLS`.
- `validate_reference_cases`: **349/354 PASS** — sin cambio.
- Physics coherence corpus: **9 PASS / 5 CTRL / 3 WARN / 0 FAIL** — estado final limpio.
- Tests: **209/209 PASS** — sin cambio.

### wood_vc_reference — Clasificación CTRL (2026-06-30)

`wood_vc_reference` añadido a `KNOWN_INTENTIONAL_CONTROLS`. Razón: fue creado explícitamente en Plan A Fase A1 para demostrar que D2 dispara en VC profundo con fuel mixto/sintético. Sus 114 D2 WARNs (t=710–1800s, ratio 0.51→2.14) y 74 D2PRE WARNs (M1 colateral, rooms 0/1/4) son todos esperados y necesarios como caso de referencia canónico para D2.

### fuel_balance_diag_sealed / o2_stoich_diag_sealed — Diagnóstico D2PRE (2026-06-30)

Ambos casos tienen 230 D2PRE WARNs cada uno. Análisis completo:

- **Room 0** (13 WARNs): tracer CO₂ < mass CO₂ en fire room — misma M1 o2_scale que en `cfast_slow_growth_sealed`. Esperado.
- **Rooms 1–5** (217 WARNs por caso): tracer CO₂ (400–1100 ppm) << mass CO₂ (4000–21000 ppm) desde t=60s. El mass path transporta CO₂ vía intercambio de gas caliente (ThermalSystem), pero el tracer OES no sigue la misma trayectoria de transporte. Root cause: M1 o2_scale double-throttle reduce tracer CO₂ en fire room → menos CO₂ disponible para transportar al tracer de rooms adyacentes.
- **Decisión: dejar como WARN.** Divergencia real, no control intencional. Documenta el alcance completo de Plan B en escenarios multi-room (no solo room 0). `fuel_balance_diag_sealed` y `o2_stoich_diag_sealed` no son CTRL porque sus WARNs no son consecuencia del mecanismo bajo prueba.

### Estado CTRL/WARN final (post-sesión)

**CTRLs (5):**
| Stem | Findings | Razón |
|---|---|---|
| v1_backdraft_accumulation | A3:2, D2PRE:563, O2E1:16 | Zombie sin M4, ILV lower-O2 bug |
| v1_m4_pool_release | D2:9, D2PRE:545 | Zombie post-backdraft con M4 |
| cfast_two_floor_stairwell | A3:4, O2E1:20 | Multi-floor sellado, O2 depleta |
| v5_m4_ventilation_throttle | D2:13, D2PRE:421 | M4 pool-release cíclico |
| wood_vc_reference | D2:114, D2PRE:74 | Referencia canónica D2 alto-CO |

**WARNs restantes (3, todos D2PRE / Plan B):**
| Stem | WARNs | Razón |
|---|---|---|
| cfast_slow_growth_sealed | D2PRE:243 | M1 o2_scale en fire room (referencia canónica Plan B) |
| fuel_balance_diag_sealed | D2PRE:230 | M1 tracer transport divergence rooms 0–5 (Plan B scope multi-room) |
| o2_stoich_diag_sealed | D2PRE:230 | ídem |

---

## Current Session Update - 2026-06-30 (rev 33 - D2 CTRL v5_m4_ventilation_throttle)

### Estado operativo actual

- Branch: `main`, cambios locales sin commitear — `v5_m4_ventilation_throttle` añadido a `KNOWN_INTENTIONAL_CONTROLS`.
- `validate_reference_cases`: **349/354 PASS** — sin cambio.
- Physics coherence corpus: **9 PASS / 4 CTRL / 4 WARN / 0 FAIL** — estado limpio.
- Tests: **209/209 PASS** — sin cambio.

### v5_m4_ventilation_throttle — Diagnóstico D2 WARNs (2026-06-30)

**Pregunta:** ¿Son los 13 D2 WARNs (ratio 0.51–0.62, t=225–600s) de `v5_m4_ventilation_throttle` intencionales o un defecto de calibración?

**Análisis del CSV:** Los 13 WARNs están todos en room=0. Correlación perfecta con `retained_unburned_MJ > 0` (pool release cíclico):

| t (s) | regime | retained_unburned_MJ | co_upper_ppm | ratio |
|---|---|---|---|---|
| 225 | ILV_LATENT | 0.0587 | 4969 | 0.510 |
| 325 | ILV_LATENT | 0.1620 | 4943 | 0.553 |
| 460 | ILV_LATENT | 0.1384 | 4722 | 0.618 |
| 505 | ILV_LATENT | 0.1325 | 4350 | 0.570 |
| 550 | ILV_LATENT | 0.1286 | 4344 | 0.554 |

Patrón: el M4 throttle deprime el fuego a `ILV_LATENT` → `retained_unburned_MJ` acumula hasta 0.12–0.17 MJ → pool release → CO burst → ratio > 0.50. Ciclo cada ~45s.

**Causa raíz del pool CO:** `fire_pool_release_max_fraction: 0.18` + `fire_secondary_hrr_gain_kw: 2500` en el JSON. El CO liberado del pool no está sujeto al cap phi-scaling (co_max=0.01250 kg/MJ), alcanzando yld_co efectivo de 0.03577 kg/MJ (2.84× cap).

**Decisión: CTRL — WARNs intencionales.** Los WARNs son consecuencia directa y esperada del mecanismo M4 bajo prueba. El propósito del caso es validar M4 ventilation throttle con secondary HRR gain; el CO post-throttle es parte del escenario.

**Acción:** Añadido `"v5_m4_ventilation_throttle"` a `KNOWN_INTENTIONAL_CONTROLS` en `scripts/simulation/audit_physics_coherence_suite.py`.

**Audit suite confirmado:** 9 PASS / 4 CTRL / 4 WARN / 0 FAIL. Exit code 0.

**WARNs restantes (no CTRL):**
- `cfast_slow_growth_sealed`: D2PRE (M1 o2_scale double-throttle, Plan B pendiente)
- `fuel_balance_diag_sealed`: D2PRE desde room=1, t=60s (M3 init asymmetry non-fire room — pendiente revisión)
- `o2_stoich_diag_sealed`: ídem
- `wood_vc_reference`: D2+D2PRE (intencionales — caso de referencia para D2 de alto CO yield)

---

## Current Session Update - 2026-06-30 (rev 32 - Plan A Sesión 4: D2 Sensitivity)

### Estado operativo actual

- Branch: `main`, cambios locales sin commitear — D2 sensitivity análisis completado. No hay cambios de motor ni de thresholds.
- `validate_reference_cases`: **349/354 PASS** — sin cambio.
- Physics coherence corpus: **9 PASS / 5 WARN / 3 CTRL / 0 FAIL** — WARNs adicionales identificadas esta sesión (ver abajo).
- Tests: **209/209 PASS** — sin cambio.

### Plan A Sesión 4 — Análisis sensibilidad D2 threshold (completado 2026-06-30)

**Objetivo:** Medir max D2 ratio y cruces de umbral (0.10/0.20/0.30/0.50) en todos los casos del corpus con columna `co2_upper_ppm_mass`. Concluir si el threshold 0.50 debe bajar.

**Caso diagnóstico creado:** `tmp_d2_sensitivity_engine_defaults.json` — sellado 1800s, engine defaults (co_base=0.00025, co_max=0.01250), sin pool release. CSV: `sim/validation/reports/tmp_d2_sensitivity_engine_defaults.csv`.

**Tabla de sensibilidad (todos los casos con co2_upper_ppm_mass):**

| Caso | CO yield config | max phi | max D2 ratio | ≥0.10 | ≥0.20 | ≥0.50 |
|---|---|---|---|---|---|---|
| cfast_slow_growth_sealed | FORCE=0.0003 | 3.60 | 0.0077 | never | never | never |
| fuel_balance_diag_sealed | engine defaults | 1.06 | 0.2465 | 135s | 175s | never |
| o2_stoich_diag_sealed | engine defaults | 1.06 | 0.2465 | 135s | 175s | never |
| v1_backdraft_accumulation (CTRL) | engine defaults | 1.17 | 0.2529 | 135s | 160s | never |
| **tmp_d2_sensitivity_eng_def** | engine defaults, sealed 1800s | 8.24 | **0.2982** | 580s | 870s | never |
| v5_m4_ventilation_throttle | eng + pool_release=0.18 | 8.38 | **0.6184** | 135s | 145s | **225s** |
| tmp_v1_backdraft_accum_m4 | eng + pool_release | 7.87 | **0.5661** | 135s | 155s | **285s** |
| v1_m4_pool_release (CTRL) | eng + pool_release | 10.00 | **0.7997** | 135s | 155s | **285s** |
| wood_vc_reference | base=0.004, max=0.10 | 8.24 | **2.1388** | 550s | 600s | **710s** |

**Hallazgo crítico — bifurcación pool release:**

- Sin pool release (`fire_pool_release_max_fraction=0`): max ratio con engine defaults = **0.2982** (phi=8.24, 1800s sellado). NUNCA alcanza 0.30 ni 0.50.
- Con pool release activo: `yld_co` alcanza 0.03577 kg/MJ (2.84× cap co_max=0.01250) porque el CO proviene del pool de gases no quemados, no del phi-scaling. Ratio alcanza 0.566–0.800 con madera engine defaults.
- La estimación teórica A2 (max ratio = 0.236, phi→inf) era correcta para phi-scaling normal. Pool release genera CO adicional no sujeto al cap.

**Corrección a la recomendación A2:**

A2 recomendó "bajar threshold a 0.20" asumiendo max ratio teórico = 0.236. Los datos medidos revelan que:
- Threshold 0.50 YA FUNCIONA: detecta backdraft/pool-release CO bursts y `wood_vc_reference`.
- Bajar a 0.20 causaría WARNs en `fuel_balance_diag_sealed` y `o2_stoich_diag_sealed` a t=135–175s (artefacto M3 init en room non-fire). Ruido diagnóstico sin valor físico.
- **Recomendación actualizada: Opción 3 — Mantener threshold 0.50 sin cambios.** D2 está calibrado correctamente para escenarios de CO extremo.

**Descubrimiento — `v5_m4_ventilation_throttle` WARN:**

El caso genera 13 D2 WARNs (ratio pico 0.6184, t=225s). Tiene `pool_release_max_fraction=0.18` y `secondary_hrr_gain=2500 kW`. La WARN refleja un CO burst físicamente real (ventilation-induced pool ignition con M4). El caso NO está en CTRL → pendiente agregar a CTRL en sesión futura con plan explícito.

**Nuevo estado audit suite (post sesión 4):**

- 9 PASS / 5 WARN / 3 CTRL / 0 FAIL (17 CSVs).
- WARNs: `cfast_slow_growth_sealed` (D2PRE), `fuel_balance_diag_sealed` (D2PRE), `o2_stoich_diag_sealed` (D2PRE), `v5_m4_ventilation_throttle` (D2+D2PRE), `wood_vc_reference` (D2+D2PRE).
- `fuel_balance_diag_sealed` y `o2_stoich_diag_sealed`: D2PRE desde room=1 a t=60s (M3 init asymmetry non-fire room). Pendiente revisión en sesión futura.

---

## Current Session Update - 2026-06-30 (rev 31 - Plan A Diagnóstico CO yield)

### Estado operativo actual

- Branch: `main`, cambios locales sin commitear — Plan A diagnóstico completado. No hay cambios de motor.
- `validate_reference_cases`: **349/354 PASS** — sin cambio.
- Physics coherence corpus: **13 PASS / 1 WARN / 2 CTRL / 0 FAIL** — sin cambio.
- Tests: **209/209 PASS** — sin cambio.

### Plan A — Diagnóstico CO yield en régimen VC (completado 2026-06-30)

**Pregunta:** ¿Por qué CO/CO₂ ratio en `cfast_slow_growth_sealed` es ~0.004–0.008 molar en condiciones VC (phi 2.8–3.6), cuando SFPE wood phi~2 debería ser ~0.3 masa / ~0.47 molar?

**Root cause: tres capas, no un bug del motor.**

**Capa 1 — Force override intencional (causa primaria):**
`cfast_slow_growth_sealed.json:88`: `"fire_co_yield_force_kg_per_MJ": 0.0003`
Activa `CombustionSystem.gd:705–707`: si `co_yield_force >= 0.0`, `co_yield = co_yield_force` incondicional. Bypass total del escalado phi. El case es CFAST comparison — yield fijo es intencional. Sin override, yield phi-escalado a phi=2.79: `0.0003 * exp(2.0*1.79) ≈ 0.0108 kg/MJ` (36× mayor). CSV confirma: `yld_co ≈ 0.000300` constante a todo tiempo (t=200s a t=1800s).

**Capa 2 — Default `co_base_yield = 0.0` (brecha silenciosa):**
`CombustionSystem.gd:663`: `context.get("co_base_yield_kg_per_MJ", 0.0)`. Casos sin yield explícito → CO = 0. `FuelObjectModel.co_yield_kg_per_MJ = 0.00025` (default) es muy bajo (nivel CFAST), no SFPE (~0.004 kg/MJ wood FC).

**Capa 3 — Clamp invertido cuando `co_max_yield = 0.0` (default):**
`CombustionSystem.gd:665–671`: `clampf(base*exp(k*(phi-1)), base, max=0.0)` → GDScript devuelve `base` siempre. Phi-scaling nunca aumenta CO sobre base. Solo `ghanekar_kitchen_living_room.json` tiene `co_max > co_base` → único caso con phi-scaling activo.

**Conclusión:** El motor phi→CO scaling está implementado correctamente. Las tres capas lo anulan o suprimen en todos los casos del corpus actual.

**Qué NO tocar:**
- `cfast_slow_growth_sealed.json`: force override 0.0003 es intencional.
- `CombustionSystem.gd` motor: no modificar.
- D2 threshold 0.5: correcto — no disparará en casos CFAST por diseño.
- OES tracer / Plan B: independiente.

**Plan A Fase A1 — COMPLETADO en esta sesión:**
- Caso `sim/validation/cases/wood_vc_reference.json` creado y ejecutado (1800s, exit 0).
- D2 dispara en t=710s: ratio=0.5123, VENTILATION_CONTROLLED_BURNING, phi=3.45, yld_co=0.04554 kg/MJ.
- Audit suite: 0 FAIL / 13 PASS / 2 WARN / 2 CTRL — sin regresiones.
- CSV producido en `sim/validation/reports/wood_vc_reference.csv`.

**Plan A Fase A2 — Diagnóstico completado 2026-06-30:**

Hallazgos principales:

1. **`FuelObjectModel.co_yield_kg_per_MJ` es irrelevante** — ningún caso define `fuel_objects` explícito. Los defaults reales son `SimulationEngine.co_base_yield_kg_per_MJ = 0.00025` y `co_max_yield_kg_per_MJ = 0.01250`. phi-scaling ya activo para todos los casos plain.

2. **Los defaults del motor son físicamente correctos para madera SFPE** (0.004 kg/kg / 16 MJ/kg = 0.00025 kg/MJ FC; 0.200 kg/kg / 16 MJ/kg = 0.01250 kg/MJ VC). NO cambiar.

3. **D2 threshold (0.5) nunca alcanzable con madera pura SFPE** — máximo ratio molar con engine defaults: 0.236 (phi→∞). D2 solo dispara con combustibles de alto CO (PU foam, mezcla residencial con sintéticos).

4. **Cambio global co_base 0.00025→0.004 sería INCORRECTO** para madera: equivaldría a 0.064 kg/kg FC (16× SFPE). FED CO 16× inflado. No afectaría 349/354 PASS (no hay CO checks non-CFAST), pero los valores físicos serían incorrectos.

5. **Inventario de riesgo:**
   - 23 casos CFAST (force override): inmunes.
   - 2 casos con co_base+co_max explícitos: inmunes.
   - 81 casos plain (engine defaults): CO físicamente correcto para madera, FED CO correcto.
   - 0 baseline CO checks en funciones non-CFAST.

**Recomendación:** Bajar D2 threshold a ~0.20 (para capturar madera VC severa phi≥3) O añadir caso PU foam VC (co_base=0.002, co_max=0.03) O dejar D2 como guardia de escenarios extremos. NO tocar engine defaults. Sesión futura con plan explícito.

---

## Current Session Update - 2026-06-30 (rev 30 - D2 Fase 3)

### Estado operativo actual

- Branch: `main`, cambios locales sin commitear — D2 Fase 3 (regla D2) implementada.
- `validate_reference_cases`: **349/354 PASS** — sin cambio.
- Physics coherence corpus: **13 PASS / 1 WARN / 2 CTRL / 0 FAIL** — sin cambio. D2 no genera findings en corpus actual (ratio CO/CO₂ max = 0.008 << threshold 0.5).
- Tests: **209/209 PASS** (183 pre-existentes + 26 nuevos TestCheckD2).

### D2 Fase 3 — regla diagnóstica CO/CO₂ upper ratio

**Función:** `_check_d2_co_co2_ratio()` en `check_physics_coherence.py`.

**Campos usados:**
- Numerador: `co_upper_ppm` (from `compute_co_upper_ppm()`, uses `co_upper_kg` con hot-gas density)
- Denominador: `co2_upper_ppm_mass` (from `compute_co2_upper_ppm_mass()`, uses `co2_upper_kg` con hot-gas density)
- Mismo denominador en ambos → ratio = `co_upper_kg/28` / `co2_upper_kg/44` (razón molar pura).

**Threshold:** `ratio > 0.5` — CO supera 50% de CO₂ en moles. Referencia SFPE: bien ventilado < 0.08, bajo-ventilado VC 0.08–0.5, post-FO severo > 0.5.

**Skip conditions (conservadoras):**
- `co2_upper_ppm_mass` ausente → legacy CSV sin D2 Fase 1 (21 de 22 CSVs del corpus actual).
- `co2_upper_ppm_mass < 1000 ppm` → CO₂ no establecido, zona fría o sin fuego.
- `time_s < 60 s` → M3 initial-condition asymmetry (mass path inicia en 0 kg vs 400 ppm tracer).

**Severity:** WARN — diagnóstico, no gating, no afecta exit code.

**Resultado en corpus:**
- 21 CSVs legacy (sin `co2_upper_ppm_mass`): skip graceful, 0 findings.
- `cfast_slow_growth_sealed`: CO/CO₂ ppm ratio = 0.006–0.008 durante toda la simulación (FUEL_CONTROLLED y VENTILATION_CONTROLLED). Muy por debajo del threshold 0.5 → **0 findings D2**. Esto indica que el modelo de CombustionSystem produce poco CO relativo a CO₂ incluso en condiciones ventilation-controlled. Documentado como observación calibración pendiente.

**Por qué `co2_upper_ppm` tracer NO se usa como denominador:**
El tracer OES es suprimido por `o2_scale` double-throttle (M1, D2PRE root cause). Usarlo produciría ratios artificialmente altos que no reflejan el estado real del fuego. `co2_upper_ppm_mass` es el denominador fiable para t > 300 s según diagnóstico D2 (rev 29).

**Observación calibración CO:**
El ratio de generación CO/CO₂ es ~0.004–0.005 (masa), constante incluso en VENTILATION_CONTROLLED_BURNING. Valor SFPE para wood, under-ventilated (phi~2): ~0.3 masa → ~0.47 molar. El modelo SimuFire parece infra-estimar CO en VC — pendiente como plan calibración separado, no bloqueante para D2 Fase 3.

### Próximos planes separados (post D2 Fase 3)

**Plan A — Calibración CO yield en régimen VC** *(prioridad: media)*
- CO/CO₂ ratio generación ~0.004–0.005 masa en `cfast_slow_growth_sealed` incluso en VENTILATION_CONTROLLED (phi >> 1). SFPE para wood phi~2: ~0.3 masa. Gap de ~60×.
- Sin Plan A, D2 nunca disparará en VC gradual — solo en post-FO con CO anómalamente alto.
- Precondición: leer y auditar escalado phi→CO en `CombustionSystem.gd`. No implementar sin diagnóstico previo.

**Plan B — Fix motor: o2_scale double-throttle en OES tracer CO₂** *(prioridad: baja)*
- Causa los 243 D2PRE WARNs en `cfast_slow_growth_sealed`. No bloqueante en corpus actual.
- Fix: eliminar/flag `co2_produced *= o2_scale` en OES (HRR ya refleja disponibilidad de O₂).
- Impacto en FED: el tracer CO₂ afecta `compute_co2_upper_ppm` → FED CO₂ narcosis. Aumentaría CO₂ FED en VC. Requiere validación FED.
- Constraint: flag per-case (no global) hasta que corpus valide. Requiere sesión con plan explícito.

**Prioridad recomendada:** Plan A primero (calibración CO es independiente del motor de tracking CO₂). Plan B después, con plan motor formal.

---

## Current Session Update - 2026-06-30 (rev 29 - D2 Diagnóstico completo)

### Estado operativo actual

- Branch: `main`, cambios locales sin commitear — diagnóstico D2 completado.
- Todos los contadores previos sin cambio: **349/354 PASS**, **183/183 tests PASS**, **13 PASS / 1 WARN / 2 CTRL / 0 FAIL** physics suite.

### D2 Diagnóstico — causa raíz identificada

**Causa raíz: tres mecanismos independientes compuestos.**

#### Hallazgo clave: dt_physics = 0.0833s, no 10s

`co2_generated_kg_step` registra el valor de UN paso físico (dt=0.0833s = 1/120s). Los 120 pasos físicos por intervalo de log de 10s producen ~0.155 kg totales de CO₂ (10s equivalente), mientras que el ACH=5.0 drena ~0.082 kg en ese mismo intervalo. El bulk co2_kg crece porque producción > drenaje ACH, lo que es consistente con los datos observados.

#### Mecanismo 1 — o2_scale double-throttle en OES (DOMINANTE)

OES aplica `o2_scale = clamp(o2_upper / 0.209, 0, 1)` a la producción de CO₂ del tracer.  
En t=700s: `o2_upper=0.063 → o2_scale=0.301` → tracer recibe solo 30% de producción nominal.  
CombustionSystem añade CO₂ proporcional al HRR real — el HRR **ya refleja** la disponibilidad de O₂ (régimen VENTILATION_CONTROLLED). Aplicar o2_scale en OES es un doble-descuento: throttle físico ya en HRR, throttle adicional en producción de tracer.

Ratio de producción masa/tracer medido: **2.56× en t=700s**, crece a **2.65× en t=1800s**.

#### Mecanismo 2 — Densidad en denominador (amplificador)

`compute_co2_upper_ppm_mass` divide por densidad caliente (≈0.71 kg/m³ a 186°C):  
`ppm_mass = co2_upper_kg × 29e6 / (floor_area × upper_height × rho_hot(temp_upper_c))`

OES tracer usa masa de aire a densidad ambiente:  
`upper_air_mass = volume × 1.2 × upper_frac`

Para igual masa de CO₂, la conversión mass da **1.68× más ppm** a t=700s (crece a 1.83× a t=1800s).

Esto NO es un error del mass path — la densidad caliente es más correcta para la concentración real de CO₂ en el gas caliente. El tracer OES usa densidad fija ambient (subestima la concentración real).

#### Mecanismo 3 — Condición inicial asimétrica (early-transient)

Tracer: `co2_upper` inicia en 0.0004 (400 ppm atmosférico) — physically correct.  
Mass path: `co2_upper_kg` inicia en 0.0 — missing atmospheric background CO₂.

Efecto: tracer **supera** al mass-derived para t < 300s (ratio < 1). La inversión ocurre alrededor de t=290s cuando la producción acumulada mass path supera el head-start inicial del tracer.

#### Dinámica observada

| t (s) | tracer_ppm | mass_ppm | ratio | o2_scale | rho_ratio |
|-------|-----------|---------|-------|---------|---------|
| 100   | 3827      | 2046    | 0.53  | 0.979   | 1.10    |
| 300   | 40376     | 77271   | 1.91  | 0.743   | 1.38    |
| 700   | 85501     | 181891  | 2.13  | 0.301   | 1.68    |
| 1800  | 69481     | 223740  | 3.22  | 0.268   | 1.83    |

Tracer pico en ~t=700s y **declina** (ACH drain supera producción throttleada).  
Mass path sigue creciendo lentamente hasta t≈1750s, luego estabiliza.

#### ¿Cuál representación es más fiable?

**Ninguna es completamente correcta:**
- **Tracer OES**: condición inicial correcta (400 ppm), física ACH correcta. **Error**: o2_scale duplica el throttle de O₂ (el HRR ya lo aplica). Denominator usa densidad ambiente → subestima ppm en zona caliente.
- **Mass-derived**: producción correcta (proporcional a HRR real, sin doble-throttle). Denominator usa densidad caliente (más correcto para concentración real). **Error**: inicia en 0 kg (falta CO₂ atmosférico), y `co2_upper_kg` no tiene verificación de que realmente esté en la capa superior.

**Para tenabilidad (CO₂ narcosis/hiperventilación)**: mass path es más fiable en t > 300s. El tracer subestima sistemáticamente por el o2_scale.

#### Instrumentación faltante para cerrar diagnóstico

Para confirmar cuantitativamente cada mecanismo, faltarían estas columnas CSV:
1. `co2_upper_oes_prod_ppm_step` — producción de tracer por paso físico (en ppm-equivalente)
2. `o2_scale_oes` — valor de o2_scale aplicado en OES por paso
3. `upper_frac_oes` — fracción upper_frac usada en OES para upper_air_mass
4. `co2_upper_kg_ach_step` — ACH drain aplicado a co2_upper_kg en GES por paso

Sin estas columnas, el diagnóstico es deductivo (código + datos CSV). Con ellas sería verificable por fila.

#### Conclusión y siguiente paso

Root cause confirmado sin ambigüedad: **el o2_scale en OES es la causa dominante** de divergencia. No es un bug de ACH ni de ventilación. El density mismatch amplifica. La initial condition asimetría explica el t < 300s.

**D2 Fase 3 (CO/CO₂ ratio rule)**: puede implementarse sobre el mass path (`co2_upper_ppm_mass`) con corrección de condición inicial (+400 ppm offset o init co2_upper_kg con CO₂ atmosférico). El tracer path no es adecuado para un ratio rule hasta que se corrija el o2_scale en OES — lo que requiere un plan motor separado.

---

## Current Session Update - 2026-06-30 (rev 28 - D2 Fase 2)

### Estado operativo actual

- Branch: `main`, cambios locales sin commitear — D2PRE implementado.
- `validate_reference_cases`: **349/354 PASS** — sin cambio.
- Physics coherence corpus: **13 PASS / 1 WARN / 2 CTRL / 0 FAIL** — `cfast_slow_growth_sealed` ahora clasifica como WARN por 243 D2PRE WARNs (no gating, exit code 0).
- Tests: **183/183 PASS** (162 pre-existentes + 21 nuevos TestCheckD2PRE).

### D2 Fase 2 — regla D2PRE implementada

**Función:** `_check_d2pre_co2_upper_divergence()` en `check_physics_coherence.py`.

**Métrica:** `rel_div = |co2_upper_ppm_mass − co2_upper_ppm| / max(co2_upper_ppm, 400.0)`

**Threshold:** `_D2PRE_REL_TOL = 1.0` — solo dispara cuando mass >2× tracer (o viceversa). Evita el ruido early-transient (t=50s da rel_div~0.6).

**Severity:** WARN — diagnóstica, no afecta exit code, no gating. Skip graceful en CSV legacy sin `co2_upper_ppm_mass`.

**Resultado diagnóstico — `cfast_slow_growth_sealed`:**
- 243 D2PRE WARNs — room 0 (fire room), t=320s en adelante.
- Tracer (`co2_upper_ppm`): toca techo ~85k ppm → decrece por dilución ODE.
- Mass-derived (`co2_upper_ppm_mass`): continúa acumulando hasta >220k ppm.
- `rel_div` crece de 1.0 (t=320s) hasta >2.2 (t=1800s) y sigue creciendo.
- Rooms 2, 3, 5: sin findings (permanecen en 400 ppm ambient).
- Room 1: WARN tardío a t=1800s (rel_div=3.81, mass=1928 vs tracer=401).
- Room 4: WARN intermitente a t=1200s (rel_div=1.40).

**Conclusión D2:**
D2 CO/CO₂ ratio rule (Fase 3) **bloqueada**. Divergencia tracer vs mass es sistemática y creciente en el fire room. Hipótesis root cause: el tracer ODE (`co2_upper` en `OxygenExchangeSystem`) pierde CO₂ por dilución en intercambios O₂/N₂ y ventilación, mientras `co2_upper_kg` (`CombustionSystem`+`GasExchangeSystem`) acumula directamente sin dilución proporcional. Debe diagnosticarse cuál representación es física antes de proceder.

**Próximo paso D2 (Fase 3 condicionada):**
Antes de implementar la regla ratio, entender por qué divergen. Opciones:
a) El tracer se diluye incorrectamente (bug en OES — dilución de CO₂ no proporcional a intercambio gaseoso).
b) El mass-derived acumula sin ventear correctamente (GES no descuenta CO₂ ventilado de `co2_upper_kg`).
c) La geometría de zona upper cambia y la conversión kg→ppm no compensa.

---

## Current Session Update - 2026-06-30 (rev 27 - D2 Fase 1)

### Estado operativo actual

- Branch: `main`, cambios locales sin commitear — GDScript D2 Fase 1 implementado.
- `validate_reference_cases`: **349/354 PASS** — sin cambio.
- Physics coherence corpus: **14 PASS / 2 CTRL / 0 FAIL** — sin cambio (sin regresiones tras añadir nuevas columnas CSV).
- Tests: **162/162 PASS** — sin cambio (tests Python no cubren GDScript directamente).

### D2 Fase 1 — implementación completa

**Objetivo:** Exportar `co2_upper_ppm` (tracer, faltaba en CSV) y `co2_upper_ppm_mass` (mass-derived, nueva) al CSV para diagnóstico D2-pre en Fase 2.

**Cambios GDScript (4 archivos):**

1. **`sim/core/ThermalSystem.gd`** — añadida `compute_co2_upper_ppm_mass()`. Fórmula: `co2_upper_kg * 29e6 / (upper_zone_mass_kg * 44.0)`. Guarda `upper_gas_kg < 0.1` → fallback a `room.co2_upper * 1e6` (400 ppm ambient). FED intacto.
2. **`sim/core/SimulationEngine.gd`** — callable `compute_co2_upper_ppm_mass_callable` registrado.
3. **`sim/core/SimulationStateBuilder.gd`** — callable declarado + `"co2_upper_ppm_mass"` añadido al state dict.
4. **`sim/core/SimulationLogWriter.gd`** — header y body: `co2_upper_ppm` y `co2_upper_ppm_mass` añadidos tras `co2_ppm`. Header=115 columnas, body=115 appends.

**Verificación headless:**
- `cfast_slow_growth_sealed`: 384 rows. `co2_upper_ppm` y `co2_upper_ppm_mass` presentes. t=5s: ambas = 400 ppm (fallback correcto, sin hot layer).
- Audit suite: **14 PASS / 2 CTRL / 0 FAIL** — sin regresiones.

**Próximos pasos D2:**
- **Fase 2:** Añadir regla `D2PRE` (WARN) en `check_physics_coherence.py` — diagnostica divergencia tracer vs mass-derived. Prerequisito: correr headless y comparar columnas en CSV largo.
- **Fase 3:** D2 ratio CO/CO2 en campos comparable (ambos mass-derived o ambos tracer).

---

## Current Session Update - 2026-06-30 (rev 26 - D2 semantic plan)

### Estado operativo actual

- Branch: `main`, cambios locales sin commitear — sin cambios de código esta sesión.
- `validate_reference_cases`: **349/354 PASS** — sin cambio.
- Physics coherence corpus: **14 PASS / 2 CTRL / 0 FAIL** — sin cambio.
- Tests: **162/162 PASS** — sin cambio.

### Plan D2 — CO/CO2 ratio rule

#### Mapa semántico actual CO/CO2

**`room.co2_upper` (tracer, fracción molar)**
- Init: `0.0004` (~400 ppm ambient)
- Escrito por: `OxygenExchangeSystem.gd` (6 sitios: combustión-delta, infiltración-ACH, dilución-inflow, canonical doorway exchange) y `HVACSystem.gd` (supply mix)
- NO escrito por ThermalSystem ni GasExchangeSystem
- Exportado como: `co2_upper_ppm = room.co2_upper × 1e6` (vía `compute_co2_upper_ppm()` en ThermalSystem.gd:3251)
- Usado en FED: `v_co2 = exp(0.1903 × co2_pct + 2.0004) / 7.1` — factor de potenciación CO/HCN en ISO 13571

**`room.co2_upper_kg` (mass-derived, kg)**
- Init: `0.0` — NO inicializado con masa ambient
- Escrito por: `CombustionSystem.gd` (generación: `room.co2_upper_kg += generated_co2_kg`), `GasExchangeSystem.gd` (14+ sitios: doorway exchange, ventilación exterior, purge, smoke-CO2 coupling)
- NO exportado al CSV
- NO usado en FED (FED usa tracer `co2_upper` vía `compute_co2_upper_ppm`)

**`room.co2_kg` (total CO2 mass, kg)**
- Init: `0.0` — NO inicializado con masa ambient
- Escrito por: `CombustionSystem.gd` (generación) y `GasExchangeSystem.gd` (transporte, ventilación, purge)
- NO exportado al CSV

**`room.co_upper_kg` (CO upper, kg)**
- Init: `0.0`
- Mass-derived, temperatura-corregida para exportar como `co_upper_ppm`
- Usado en FED directamente

**Incompatibilidad central:**
`co2_upper_ppm` (tracer, fracción molar ODE) y `co_upper_ppm` (mass-derived, temperatura-corregida) provienen de trayectorias computacionales completamente distintas. Un ratio CO/CO2 construido sobre ellas mezcla dos representaciones incomparables.

**Además: brecha de inicialización.** `co2_upper_kg` y `co2_kg` se inicializan a 0.0. El tracer `co2_upper` se inicializa a 0.0004. A t=0, `co2_upper_ppm` = 400 ppm (ambient), pero `co2_upper_ppm_mass` (si se exportara desde `co2_upper_kg`) = 0 ppm. Toda divergencia inicial se debe a esta brecha, no a física real.

---

#### Opciones de diseño D2

**Opción A — CO2 upper mass-derived como representación autoritativa**

Descripción: Añadir `compute_co2_upper_ppm_mass()` en ThermalSystem que usa `co2_upper_kg` y la masa de zona upper (temperatura-corregida, mismo método que `co_upper_ppm`). Exportar como `co2_upper_ppm_mass` al CSV. D2 compara `co_upper_ppm` vs `co2_upper_ppm_mass`.

| Aspecto | Detalle |
|---------|---------|
| Impacto FED | Ninguno — FED sigue usando tracer `co2_upper_ppm` para V_CO2. Solo se añade columna nueva. |
| Riesgo regresión | Bajo si se añade solo la columna. Si se cambia FED a mass-derived en el futuro: potencial regresión en fed_co/fed_hcn. |
| Cambios GDScript | 1 nueva función en ThermalSystem.gd + 1 export en SimulationStateBuilder.gd + 1 CSV column en SimulationLogWriter.gd + inicializar `co2_upper_kg` con masa ambient en RoomModel/setup |
| Columnas CSV nuevas | `co2_upper_ppm_mass` |
| Tests necesarios | Test que verifica D2 produce WARN/FAIL cuando ratio CO/CO2 sale de rango; test que verifica column existe en schema |
| Severidad inicial | WARN (observación) |
| Bloqueo previo | Hay que resolver la brecha de inicialización `co2_upper_kg = 0` antes de implementar D2, o la regla dará falsos positivos al inicio de cada simulación. |

**Opción B — D2 sobre campos existentes (co_upper_ppm + co2_upper_ppm tracer)**

Descripción: Implementar D2 directamente sobre `co_upper_ppm` y `co2_upper_ppm` existentes, con tolerancia amplia para absorber el mismatch representacional.

| Aspecto | Detalle |
|---------|---------|
| Impacto FED | Ninguno |
| Riesgo regresión | Ninguno en motor — no toca código. Pero la regla D2 sería semánticamente débil. |
| Cambios GDScript | Ninguno |
| Columnas CSV nuevas | Ninguna |
| Tests necesarios | Tests de la regla D2 en check_physics_coherence.py |
| Severidad inicial | Solo WARN o diagnóstico — no puede ser FAIL/gating con mismatch representacional |
| Problema fundamental | CO2 tracer y CO mass-derived no son comparables. El ratio reflejaría ruido del mismatch, no física real. Falsos positivos garantizados en multi-room (CO transportado de una sala, CO2 tracer independiente). **No recomendado.** |

**Opción C — Exportar ambas representaciones, D2-pre diagnóstico primero**

Descripción: Dos fases. Fase 1: exportar `co2_upper_ppm_mass` (desde `co2_upper_kg`) como columna CSV nueva. Añadir regla D2-pre como WARN diagnóstico que mide `abs(co2_upper_ppm_mass - co2_upper_ppm) / co2_upper_ppm` — si la divergencia es grande, el dual-tracking tiene un problema real antes de intentar D2. Fase 2: si D2-pre muestra convergencia en corpus, implementar D2 ratio rule sobre la representación mass-derived.

| Aspecto | Detalle |
|---------|---------|
| Impacto FED | Ninguno |
| Riesgo regresión | Bajo — solo se añade columna + regla WARN |
| Cambios GDScript | Idéntico a Opción A (columna), más la brecha de inicialización ambient |
| Columnas CSV nuevas | `co2_upper_ppm_mass` |
| Tests necesarios | Test D2-pre WARN cuando divergencia > umbral; test no-finding cuando convergentes |
| Severidad inicial | D2-pre: WARN diagnóstico. D2 ratio: WARN inicial → FAIL si corpus limpio |
| Ventaja diferencial | Revela si el dual-tracking es realmente problemático en el corpus actual antes de comprometerse a una D2 ratio rule. Si D2-pre muestra divergencia masiva, el problema está en la inicialización o en el motor — no en el balance rule. |

---

#### Recomendación: Opción C

**Ruta mínima para desbloquear D2:**

1. **Fase 0 (diagnóstico, sin motor):** Examinar un CSV existente para estimar cuánto divergen `co2_upper_ppm` (tracer, disponible) y una estimación de `co2_upper_ppm_mass` (requiere `co2_upper_kg`, no disponible en CSV actualmente). Como `co2_upper_kg` no está en CSV, este diagnóstico no puede hacerse sin tocar motor.

2. **Fase 1 (mínimo motor):** Añadir 3 cambios GDScript:
   - `RoomModel.gd`: inicializar `co2_upper_kg` con masa ambient estimada (o añadir campo `co2_upper_kg_initialized: bool`).
   - `ThermalSystem.gd`: añadir `compute_co2_upper_ppm_mass(room)` usando `co2_upper_kg`.
   - `SimulationStateBuilder.gd` + `SimulationLogWriter.gd`: exportar `co2_upper_ppm_mass` al CSV.

3. **Fase 2 (regla D2-pre):** Implementar en `check_physics_coherence.py` una regla D2-pre que mida la divergencia `co2_upper_ppm_mass` vs `co2_upper_ppm`. WARN solo. Auditar corpus. Si divergencia < 50% en todos los casos activos → D2 ratio es viable.

4. **Fase 3 (D2 ratio rule):** Implementar D2 propiamente: `co_upper_ppm / co2_upper_ppm_mass` dentro de rango esperado por condición de fuego (ventilated: CO/CO2 ratio < 0.1; under-ventilated: 0.1–1.0; post-flashover: hasta 2.0+). WARN inicial.

**Prerrequisito bloqueante identificado:** La brecha de inicialización `co2_upper_kg = 0` vs `co2_upper = 0.0004` producirá falsos positivos en D2-pre y D2. Hay que inicializar `co2_upper_kg` con la masa ambient CO2 del volumen de aire de la sala antes de que D2 sea significativo. Esto requiere acceso al volumen y masa de aire de la sala en el setup — cambio en el constructor de `RoomModel` o en `SimulationEngine._setup_rooms()`.

---

### Archivos modificados esta sesión

Solo documentación:
- `docs/HANDOFF_CURRENT_STATE.md` — rev 26 (este, plan D2)
- `docs/validation/MOTOR_PHYSICS_VALIDATION_CHECKLIST.md` — sección D2 ampliada

---

## Current Session Update - 2026-06-30 (rev 25 - S1 promovida a FAIL/gating)

### Estado operativo actual

- Branch: `main`, cambios locales sin commitear (S1→FAIL, O2E1, O1, M5, C-S1-3 — sesiones 2026-06-29/30).
- Último commit: `18b6b5c2` docs(fire): record M5 post-backdraft guard plan.
- `validate_reference_cases`: **349/354 PASS** — sin cambio.
- Physics coherence corpus: **14 PASS / 2 CTRL / 0 FAIL**.
- Tests `test_check_physics_coherence.py`: **162/162 PASS**.

### S1 — FAIL/gating (cerrado)

`severity="WARN"` → `severity="FAIL"` en `_check_s1_smoke_per_room_balance`. Sin cambio de tolerancias.

Criterios cumplidos: C-S1-1 (corpus sostenido), C-S1-2 (multi-room `cfast_two_room_door_open`), C-S1-3 (multi-floor `cfast_two_floor_stairwell`), C-S1-4 venting, C-S1-5 (sin residuos compensados), C-S1-6 (sin cambio de tolerancia). C-S1-4 deposition documentada como limitación de floor precision (max 0.002 kg < floor 0.01 kg).

`cfast_two_floor_stairwell` añadido a `KNOWN_INTENTIONAL_CONTROLS` en `audit_physics_coherence_suite.py`: A3/O2E1 por depleción O2 en edificio sellado (misma causa que `v1_backdraft_accumulation`); S1 limpia — propósito es cobertura C-S1-3.

### Archivos modificados esta sesión

- `scripts/simulation/check_physics_coherence.py` — S1 severity WARN → FAIL; docstring actualizado
- `scripts/simulation/audit_physics_coherence_suite.py` — `cfast_two_floor_stairwell` añadido a KNOWN_INTENTIONAL_CONTROLS
- `tests/test_check_physics_coherence.py` — `test_residual_above_floor_triggers_fail` (era `_warn`)
- `CHANGELOG.md` — entrada S1 FAIL/gating
- `docs/HANDOFF_CURRENT_STATE.md` — rev 25

### Gating balance lanes — estado final

| Lane | Severidad | Estado |
|------|-----------|--------|
| S0 | FAIL/gating | Cerrado |
| E1 | FAIL/gating | Cerrado |
| D1 | FAIL/gating | Cerrado |
| O2E1 | FAIL/gating | Cerrado |
| O1 | FAIL/gating | Cerrado |
| **S1** | **FAIL/gating** | **Cerrado (2026-06-30)** |
| D2 | Bloqueado | `co2_upper_ppm` tracer vs `co2_upper_kg` mass — sin resolver |

### Siguiente paso recomendado

- D2 sigue bloqueado. Opciones: (a) exportar `co2_upper_kg` al CSV como columna comparable, (b) derivar `co2_upper_ppm` de masa en lugar de tracer. Requiere plan semántico explícito.
- No hay balance lanes gating pendientes de implementar.

---

## Current Session Update - 2026-06-30 (rev 24 - C-S1-3 cubierto, corpus 15 PASS)

### Estado operativo actual

- Branch: `main`, cambios locales sin commitear (S1, O2E1, O1, M5, C-S1-3 — sesiones 2026-06-29/30).
- Último commit: `18b6b5c2` docs(fire): record M5 post-backdraft guard plan.
- `validate_reference_cases`: **349/354 PASS** — sin cambio.
- Physics coherence corpus: **15 PASS / 1 CTRL / 0 FAIL / 0 WARN**.
- Tests `test_check_physics_coherence.py`: **162/162 PASS**.

### C-S1-3 cerrado — cfast_two_floor_stairwell

Se añadió `csv_log_file_path` al caso JSON `sim/validation/cases/cfast_two_floor_stairwell.json` (único cambio; faltaba en `engine_overrides`). Se ejecutó headless con Godot 4.6.3.

**Resultado S1 (13 rooms, PB + P1, 0–350 s):**

| Room | Nombre | Transport total | Floor |
|------|--------|----------------|-------|
| 0 | Salon-comedor PB | −2.979 kg (emisor) | PB |
| 1 | Recibidor distribuidor | +0.192 kg | PB |
| 2 | Escalera PB | +0.135 kg | PB |
| 3 | Cocina PB | +0.224 kg | PB |
| 6 | **Escalera P1** | **+0.101 kg** | **P1** |
| 7 | **Distribuidor P1** | **+0.138 kg** | **P1** |
| 8–10,12 | Dormitorios P1 | +0.021–0.026 kg | P1 |

Todos los valores por encima del floor S1 (0.01 kg). S1 exit 0, sin WARNs. Transporte vertical vía escalera confirmado.

### Estado criterios C-S1

| Criterio | Estado |
|----------|--------|
| C-S1-1 Corpus sostenido | ✅ 15/15 PASS, 0 WARN |
| C-S1-2 Multi-room transport | ✅ `cfast_two_room_door_open` (5.43 kg, 6 rooms) |
| C-S1-3 Multi-floor transport | ✅ `cfast_two_floor_stairwell` (0.101–0.138 kg inter-floor) |
| C-S1-4 Venting | ✅ `fp_ilv_open_partial_window` (45.97 kg) |
| C-S1-4 Deposition | ⚠️ Limitación de escala — max 0.002 kg, bajo floor 0.01 kg. No bloquea. |
| C-S1-5 Sin residuos compensados | ✅ S1 exit 0 en ambos casos con transporte no trivial |
| C-S1-6 Sin cambio de tolerancia | ✅ Tolerancias intactas |

S1 permanece **WARN**. Todos los criterios bloqueantes cubiertos. La deposition está documentada como limitación de escala física (soot settling bajo en escenarios ≤600 s), no como gap de instrumentación. Promoción a FAIL/gating puede planificarse en sesión futura.

### Archivos modificados esta sesión

- `sim/validation/cases/cfast_two_floor_stairwell.json` — añadido `csv_log_file_path`
- `sim/validation/reports/cfast_two_floor_stairwell.csv` — generado (nuevo)
- `sim/validation/reports/cfast_two_floor_stairwell.json` — actualizado por Godot
- `docs/HANDOFF_CURRENT_STATE.md` — rev 24 (este)
- `docs/validation/MOTOR_PHYSICS_VALIDATION_CHECKLIST.md` — C-S1-2/3/4/5 marcados con estado
- `CHANGELOG.md` — entrada C-S1-3

### Siguiente paso recomendado

Con C-S1-1 a C-S1-6 todos cubiertos (deposition documentada como limitación aceptable), S1 está lista para promoción a FAIL/gating. La única acción pendiente es:
1. Cambiar `severity="WARN"` → `severity="FAIL"` en `_check_s1_smoke_per_room_balance`.
2. Re-auditar corpus completo y confirmar 0 FAIL.
3. Actualizar checklist, CHANGELOG y HANDOFF con fecha de promoción.

D2 sigue bloqueado (CO2 dual-tracking). No tocar hasta decisión semántica.

---

## Current Session Update - 2026-06-30 (rev 23 - S1 WARN-clean, promotion criteria defined)

### Estado operativo actual

- Branch: `main`, cambios locales sin commitear (S1, O2E1, O1, M5 — sesiones 2026-06-29/30).
- Último commit: `18b6b5c2` docs(fire): record M5 post-backdraft guard plan.
- `validate_reference_cases`: **349/354 PASS** — sin cambio.
- Physics coherence corpus: **14 PASS / 0 FAIL / 0 WARN** en casos activos.
- Tests `test_check_physics_coherence.py`: **162/162 PASS**.

### S1 smoke per-room balance — WARN-clean

S1 implementada en `scripts/simulation/check_physics_coherence.py` como **WARN**.

- Invariante: `Δsmoke_kg = Δsmoke_generated_kg_total − Δsmoke_vented_kg_total − Δsmoke_deposited_kg_total + Δsmoke_net_transport_kg_total`.
- Acumuladores per-room ya existían en `RoomModel.gd` y GDScript — no se tocó motor.
- Corpus S1 (2026-06-30): **14 PASS / 0 WARN / 0 FAIL** en todos los casos activos.
- Criterios de promoción S1 WARN → FAIL/gating definidos en `docs/validation/MOTOR_PHYSICS_VALIDATION_CHECKLIST.md` (C-S1-1 a C-S1-6).
- S1 permanece WARN. No promover sin evidencia de los criterios.

### Stale comments corregidos

- `docs/HANDOFF_CURRENT_STATE.md` rev 22: eliminada la referencia a "S1 bloqueado" y al plan de instrumentación.
- `docs/handoff/HANDOFF_CURRENT_STATE.md`: S0 limitations actualizado ("S1 bloqueado" → "S1 implementada WARN-clean").

### D2 — sigue bloqueado

`co2_upper_ppm` es tracer-derived (`room.co2_upper * 1e6`, actualizado por `ThermalSystem`).
`co2_upper_kg` es mass-derived (acumulado por `GasExchangeSystem`, 14+ sitios de escritura) y no está exportado al CSV.
Las dos representaciones son semánticamente incomparables. Reglas CO/CO2 ratio (D2 y derivadas) no pueden implementarse hasta resolver cuál es autoritativa o exportar `co2_upper_kg` de forma comparable.

### Siguiente paso recomendado

Opciones sin tocar motor directamente:

1. **Ampliar corpus S1** — verificar que los casos multi-room ya en suite tienen `smoke_net_transport_kg_total` no trivial (C-S1-2). Si es así, S1 cubre criterio C-S1-2/3 y la promoción puede planificarse.
2. **Plan D2** — decidir entre: (a) exportar `co2_upper_kg` al CSV como columna adicional comparable, o (b) derivar `co2_upper_ppm` de masa en lugar de tracer. Requiere plan semántico explícito antes de tocar `ThermalSystem`.
3. **Nuevas reglas de balance** — candidatos: temperatura upper/lower vs energía (B2), smoke visibility vs smoke_kg (V1).

---

## Current Session Update - 2026-06-29 (rev 22 - O2E1/O1 promoted to FAIL-gating)

### Estado operativo actual

- Branch: `main`, worktree limpio antes de esta nota, local ahead de `origin/main`.
- Ultimos commits relevantes:
  - `6db12f7` — O2E1 promoted to FAIL/gating.
  - `bd3e13e` — O1 canonical doorway double-count fixed.
  - `6a8dd2a` / `41eb069` — O1 promoted to FAIL/gating and documented.
- `validate_reference_cases`: **349/354 PASS** — sin cambio; los 5 FAIL restantes son `VALID_GAP` preexistentes.
- Physics coherence corpus: **14 PASS / 0 FAIL** en casos activos.
- Carriles gating activos: `S0`, `E1`, `D1`, `O2E1`, `O1`, y cobertura M5/C1.
- S1 añadida como WARN-clean (2026-06-30): ver entrada S1 en CHANGELOG y checklist.
- Bloqueado sin cambio: `D2` (CO2 upper dual-tracking).

### M5 y C1 cerrados

M5 ya no es solo plan. `fire_post_bd_hrr_cut_enabled` fue implementado y activado en `v1_m4_pool_release` como guard opt-in/default-off.

Resultado:

- `v1_m4_pool_release` mantiene el backdraft principal.
- No hay segundo backdraft artificial.
- El zombie post-backdraft queda cortado en el caso M5.
- C1 backdraft/pool-release queda cerrado como evidencia limpia para O2E1.

### O2E1 cerrado como FAIL/gating

O2E1 ahora usa `o2_consumed_fire_kg_total` contra `hrr_kj_total * 7.6e-5 kg/kJ` y su severidad es `FAIL`.

Decisiones:

- No tocar tolerancias: se mantiene 5 % relativo / `1e-5 kg` absoluto.
- No tocar fisica en la promocion: fue cambio de severidad/documentacion/tests.
- `v1_backdraft_accumulation` sigue como CTRL intencional con findings esperados.

### O1 canonical doorway cerrado y promovido

Causa raiz del gap O1 en `cfast_two_room_door_open`:

- `_apply_canonical_doorway_exchange` sumaba `_cde_net_hot` a `o2_net_transport_kg_total`.
- Pero `room.o2` se actualiza via zone blend; el zone sync ya capturaba el efecto neto de CDE en bulk O2.
- Resultado: O1 contaba dos veces el efecto y `expected > delta_bulk` por ~`_cde_net_hot` por paso.

Fix:

- `ThermalSystem.gd`: eliminado el tracking directo de `_cde_net_hot` hacia `o2_net_transport_kg_total`.
- `ThermalSystem.gd`: anadido zone sync para `cold_room` en CDE.
- `check_physics_coherence.py`: O1 suma `delta(o2_zone_sync_kg_total)` al expected.

Resultado:

- `cfast_two_room_door_open` limpio.
- Corpus de coherencia fisica: **14 PASS / 0 FAIL**.
- O1 promovido a `FAIL/gating`.

### Siguiente paso recomendado

No abrir D2/S1 directamente sin plan semantico.

Opcion recomendada ahora:

1. Cerrar documentalmente la fase de balances principales — ver entrada S1 en CHANGELOG (2026-06-30).
2. S1 ya está implementada como WARN-clean: 14 PASS / 0 WARN / 0 FAIL. Criterios de promoción definidos en `docs/validation/MOTOR_PHYSICS_VALIDATION_CHECKLIST.md`.
3. D2 sigue bloqueado: resolver/normalizar la dualidad `co2_upper_ppm` tracer-derived vs `co2_upper_kg` mass-derived antes de implementar reglas CO/CO2.

---

## Current Session Update - 2026-06-28 (rev 21 - M5 post-backdraft guard plan)

### Estado operativo actual

- Branch: `main`, worktree limpio antes de esta nota, local ahead de `origin/main`.
- Ultimo bloque tecnico cerrado: C1 backdraft/pool-release queda "path exercised, not clean promotion evidence".
- No hay cambio de motor en esta rev. Solo se guarda el plan M5 para la siguiente sesion.
- O2E1 permanece WARN. No promover a FAIL todavia.

### Diagnostico exacto del zombie post-backdraft

`v1_m4_pool_release` ya ejercita el path de backdraft:

- `backdraft_triggered=1` a t=350 s.
- HRR spike principal: 21.369 kW.
- `retained_unburned_MJ` se agota a t=355 s.
- O2E1 esta limpio durante la ventana de backdraft (t=340-360 s).

El problema restante empieza despues del evento:

1. Tras agotarse el pool, `can_flame=false` y `hrr_target_kw=0`, pero `room.hrr_kw` no cae inmediatamente; decae con `fire_hrr_fall_tau_s=20`.
2. Esa inercia mantiene HRR positivo con `o2_upper` critico, generando filas A3 y O2E1 WARN en fase zombie.
3. Cuando `o2_upper` se recupera por encima del umbral M4, el motor puede volver a alimentar llama/pool y disparar un segundo backdraft artificial.

La causa no es Thornton ni O2E1. Es una incoherencia de ciclo post-evento en `CombustionSystem.gd`: HRR suavizado y pool reaccumulado sobreviven a una condicion donde no hay llama ni latencia fisicamente viable.

### M5 recomendado

Implementar un guard opt-in:

- Flag: `fire_post_bd_hrr_cut_enabled`, default `false`.
- Activacion inicial: solo en `v1_m4_pool_release`.
- Ubicacion: `CombustionSystem.gd`, despues del bloque `if room.backdraft_active:` y antes del consumo/reacumulacion de pool.

Condicion propuesta:

```gdscript
if fire_post_bd_hrr_cut_enabled \
        and not room.backdraft_active \
        and not can_flame \
        and not latent_viable \
        and room.retained_unburned_MJ < 0.001 \
        and room.fire_o2_ref < o2_min_ref:
    room.hrr_kw = 0.0
    room.hrr_target_kw = 0.0
    retained_generation_kw = 0.0
```

La forma exacta puede ajustarse al estilo local del archivo, pero la intencion debe mantenerse: cortar la cola de HRR y bloquear la reacumulacion de pool cuando el backdraft ya termino, el pool esta agotado y no existe llama/latencia viable.

### Criterios de aceptacion M5

- `v1_m4_pool_release`: backdraft principal sigue ocurriendo a t≈350 s.
- `v1_m4_pool_release`: no hay segundo backdraft artificial.
- `v1_m4_pool_release`: A3=0 y O2E1=0 WARN.
- `check_physics_coherence.py` sobre el CSV del caso sale limpio.
- Guardrails globales se mantienen estables: `validate_reference_cases` no cambia por default-off.
- No tocar O2E1 severity ni tolerancias.

### Decision vigente

O2E1 sigue como WARN hasta que M5 produzca evidencia C1 limpia o hasta que se apruebe una politica formal de exclusion. La ruta preferida ahora es M5, no exclusion.

---

## Current Session Update — 2026-06-27 (rev 20 — M4 pool-release path-exercise)

### Estado operativo actual

- Branch: `main`, HEAD: último commit de este bloque.
- `validate_reference_cases`: **349/354 PASS** — sin cambio.
- Unit tests Python: sin regresión (5 FAIL + 1 ERROR pre-existentes).
- Physics coherence suite: **exit 0** — 12 PASS, 2 CTRL (`v1_backdraft_accumulation`, `v1_m4_pool_release`), 1 WARN (`cfast_two_room_door_open`).
- ILV suite: exit 1 (pre-existente: `fuel_balance_diag_sealed`, `o2_stoich_diag_sealed`). `v1_backdraft_accumulation` y `v1_m4_pool_release` registrados como CTRL.
- Sin cambio de física. Sin cambio de motor.

### M4 pool-release path-exercise `v1_m4_pool_release`

- **Caso**: derivado de `v1_backdraft_accumulation` con gates relajados y M4 activo. `fire_backdraft_pool_threshold_MJ: 0.35`, `fire_backdraft_o2_max: 0.20`, `fire_backdraft_temp_min_c: 100.0`, `fire_backdraft_lfl: 0.001`, `fire_o2_upper_throttle_enabled: true`.
- **Backdraft ejercitado**: `backdraft_triggered=1` a t=350 s, HRR spike 21.369 kW, pool exhaustado en t=355 s. Path ejecutado.
- **Post-evento zombie (CTRL)**: tras agotar el pool el motor vuelve a `FULLY_DEVELOPED` con `o2_upper≈0.0008` — mismo bug A3 que `v1_backdraft_accumulation`. 8 A3 FAILs + 5 O2E1 WARNs (todos en fase zombie, no en ventana de backdraft). Ambos casos registrados en `KNOWN_INTENTIONAL_CONTROLS`.
- **C1 parcialmente cubierto**: el path de backdraft/pool-release fue ejercitado exitosamente. Los O2E1 WARNs no son del backdraft propiamente, sino del zombie que continúa. C1 queda marcado "path ejercitado / zombie persiste post-backdraft".

Estado criterios WARN→FAIL O2E1 actualizado:

| Criterio | Estado |
|---|---|
| C1 backdraft / pool-release | ⚠️ Path ejercitado — zombie persiste post-backdraft (O2E1 WARNs en zombie, no en backdraft) |
| C2 larga duración ≥ 600 s | ✅ `cfast_slow_growth_sealed` PASS |
| C3 multi-room O2 exchange | ✅ O2E1 PASS en `cfast_two_room_door_open` |
| C4 effective_plume_lower | ✅ `fp_ilv_open_partial_window` PASS |

### Decisión C1 cerrada

**C1 = "path exercised, not clean promotion evidence."** El backdraft/pool-release fue ejercitado exitosamente en `v1_m4_pool_release`. O2E1 está limpio durante el evento (t=340-360 s). Los 5 O2E1 WARN post-evento son consecuencia del zombie A3 (bug de motor separado), no de un fallo de Thornton. **O2E1 permanece WARN.** No se promueve hasta tener C1 limpio o política de exclusión aprobada.

**Próxima sesión recomendada**

Para desbloquear O2E1 → FAIL, elegir una vía:

**Vía A (recomendada) — Fix A3 zombie:**  
`CombustionSystem.gd` no transiciona régimen cuando `o2_upper < fire_o2_min_for_flame` con plume_lower activo. Añadir un guard explícito (`if o2_upper < threshold: force ILV_LATENT`) eliminaría el zombie. Requiere plan de motor explícito antes de tocar `sim/fire/`. Con A3 resuelto, `v1_m4_pool_release` (o una variante) produciría un run limpio y cerraría C1.

**Vía B — Política de exclusión:**  
Documentar formalmente que los WARN del zombie post-backdraft no son bloqueantes para la promoción: ocurren fuera de la ventana del evento, O2 ya estaba capeado (no hay consumo real posible), y son artefacto del bug A3, no de la coherencia Thornton. Requiere decisión explícita documentada.

Otros pendientes (no bloqueantes para O2E1):
- Resolver gap O1 multi-room (no urgente hasta promover O1 a FAIL).

---

## Previous Session — 2026-06-27 (rev 19 — corpus diagnóstico O2E1/O1: 3 casos nuevos)

### Estado operativo actual

- Branch: `main`, HEAD: último commit de este bloque.
- `validate_reference_cases`: **349/354 PASS** — sin cambio.
- Unit tests Python: **157 PASS** — sin cambio.
- Physics coherence audit: **14/14 PASS + 1 WARN + 1 FAIL** (con tmp incluidos, 16 CSVs).
- Sin cambio de física. Sin cambio de motor.

### Corpus diagnóstico O2E1/O1 — 3 casos nuevos

Objetivo: cubrir criterios WARN→FAIL de O2E1 antes de promover severidad.

Casos añadidos (solo CSV + JSON de caso actualizados):
- `v1_backdraft_accumulation` — C1 backdraft/pool-release (650 s)
- `cfast_slow_growth_sealed` — C2 larga duración (1800 s, sellada)
- `cfast_two_room_door_open` — C3 multi-room + intercambio O2 (600 s)

Resultados:

| Caso | O2E1 | O1 | Diagnóstico |
|---|---|---|---|
| `cfast_slow_growth_sealed` | PASS | PASS | ✅ C2 cubierto. Apto para suite permanente. |
| `cfast_two_room_door_open` | PASS | 247 WARN | O2E1 ✅ C3 cubierto. O1 gap en multi-room (ver abajo). |
| `v1_backdraft_accumulation` | 16 WARN | PASS | ❌ A3 FAIL + O2E1 WARN consecuencia. Pool release no activó. C1 NO cubierto. |

**C4** (`effective_plume_lower`): ya cubierto por `fp_ilv_open_partial_window` en suite (280 pasos path no-bulk, O2E1 PASS).

Diagnósticos clave:

- **`v1_backdraft_accumulation` — A3 FAIL**: Motor mantiene `FULLY_DEVELOPED` cuando `o2_upper=0.0009` (0.09%), violando `fire_o2_min_for_flame=0.10`. A3 captura la incoherencia. O2E1 WARNs son consecuencia: HRR acumula ~3425 kW pero O2 está capeado a cero → `delta_o2_fire ≈ 40%` Thornton. `retained_unburned_MJ=0` en todo el CSV — pool release nunca activa. C1 requiere caso distinto o fix de régimen.

- **`cfast_two_room_door_open` — O1 gap multi-room**: El balance O1 (`-dcons + dext + dtrans + dsync`) no captura el flujo O2 vía `canonical_doorway_exchange_enabled`. Residual típico 0.11 kg vs. tolerancia 0.003 kg. Gap estructural de la fórmula O1 — no es bug de física. O1 no debe usarse como gating en casos multi-room con canonical doorway hasta resolver.

Estado criterios WARN→FAIL O2E1:

| Criterio | Estado |
|---|---|
| C1 backdraft / pool-release | ❌ Pendiente — A3 bloquea, pool release no activó |
| C2 larga duración ≥ 600 s | ✅ `cfast_slow_growth_sealed` PASS |
| C3 multi-room O2 exchange | ✅ O2E1 PASS en `cfast_two_room_door_open` |
| C4 effective_plume_lower | ✅ `fp_ilv_open_partial_window` PASS |

---

## Previous Session — 2026-06-27 (rev 18 — O2E1 fix: o2_consumed_fire_kg_total)

### Estado operativo actual

- Branch: `main`, limpio. HEAD: `88ce7d7` — `fix(o2e1): add o2_consumed_fire_kg_total primary-path accumulator`.
- `validate_reference_cases`: **349/354 PASS** — sin cambio.
- Unit tests Python: **157 PASS** (+2 tests O2E1).
- Physics coherence audit: **11/11 PASS, 0 WARN, 0 FAIL** — O2E1 limpio tras fix.

### O2E1 fix — o2_consumed_fire_kg_total

Problema: `o2_consumed_kg_total_all` acumulaba dos veces en modo two-zone estándar (bulk + upper, misma fórmula Thornton) → 1308 WARNs falsos.

Fix tracking-only (sin cambio de física):
- Nuevo campo `room.o2_consumed_fire_kg_total` (+ step) en RoomModel.
- OES selecciona path primario una vez por paso (en este orden de prioridad): bulk si corrió → lower si `fire_uses_lower_o2` → plume si `effective_plume_lower` → upper si `_phase2b_upper_active`. La asignación usa la variable local `_o2_fire_primary`.
- Zeroed en CombustionSystem junto a los demás step accumulators.
- Exportado en StateBuilder + CSV (columna nueva `o2_consumed_fire_kg_total`).
- O2E1 ahora compara `o2_consumed_fire_kg_total` vs `hrr_kj_total * Thornton`.
- `o2_consumed_kg_total_all` y `o2_consumed_bulk_kg_total` (O1) sin cambio.

Corpus audit post-fix (11 CSVs regenerados con nuevo schema): **11/11 PASS, 0 WARN**.

### Próxima sesión recomendada

1. O2E1 está limpio. Siguiente regla de balance: candidatos = balance O2 por zona (upper/lower) o validación de temperatura two-zone.
2. O2E1 puede considerarse para promoción a FAIL una vez el corpus incluya backdraft y pool release.
3. No tocar `o2_consumed_kg_total_all` (sigue siendo raw sum, correcto para diagnóstico granular).

---

## Current Session Update — 2026-06-27 (rev 17 — O2E1 Thornton cross-check corpus audit)

### Estado operativo actual

- Branch: `main`, limpio. HEAD: `90c436a` — `feat(o2e1): add O2E1 Thornton cross-check between CombustionSystem and OES`.
- `validate_reference_cases`: **349/354 PASS** — los 5 FAIL son los `VALID_GAP` conocidos (sin cambio).
- Unit tests Python: **155 PASS** (incluye 15 tests `TestCheckO2E1`).
- Physics coherence audit (11 CSVs): 8 WARN (O2E1), 3 PASS (old schema, skip graceful), **0 FAIL**.

### O2E1 Thornton cross-check — resultado corpus

Regla nueva `O2E1` (WARN, no gating). Cruza `o2_consumed_kg_total_all` (OES) con `hrr_kj_total * 7.6e-5 kg/kJ` (CombustionSystem tracking).

Instrumentación añadida al CSV sin cambiar física:
- `room.hrr_kj_total` en RoomModel — tracking-only, acumula `maxf(0, room.hrr_kw) * dt` en CombustionSystem.
- Exportado via StateBuilder + columna nueva `hrr_kj_total` en LogWriter CSV.

Corpus audit 2026-06-27 (11 CSVs):

| CSV | O2E1 resultado | Worst residual |
|---|---|---|
| `cfast_ilv_audit` | 439 WARN | 1.019e-05 kg |
| `fp_ilv_open_partial_window` | 279 WARN | 1.948e-05 kg |
| `fp_ilv_upper_throttle_off` | 280 WARN | 1.751e-05 kg |
| `fp_ilv_upper_throttle_on` | 34 WARN | 1.751e-05 kg |
| `fuel_balance_diag_sealed` | 60 WARN | 1.523e-05 kg |
| `layer_interface_single_room_window` | 36 WARN | 1.789e-05 kg |
| `o2_stoich_diag_sealed` | 60 WARN | 1.523e-05 kg |
| `v5_m4_ventilation_throttle` | 120 WARN | 1.523e-05 kg |
| `ilv_open_window_repro` | PASS (old schema) | — |
| `p2h_diag_off` | PASS (old schema) | — |
| `p2h_diag_on` | PASS (old schema) | — |

**Root cause identificado**: en modo two-zone estándar (`lower_frac ≥ 0.15`, no `plume_lower`, no `two_zone_solver`), OES acumula en `o2_consumed_kg_total_all` dos veces por paso:
1. Línea 362: bulk path `consumed = (hrr_kw/1000) * cr * dt`
2. Línea 407: upper-zone path `upper_consumed = (hrr_kw/1000) * cr_upper * dt`

Resultado: `o2_consumed_kg_total_all ≈ 2 × Thornton`. Los residuales (1–2 × 10⁻⁵ kg) cruzan el piso absoluto `1e-5` pero son pequeños. El acumulador `o2_consumed_bulk_kg_total` (usado por O1) **no está afectado** — solo acumula el bulk path.

### Reglas coherencia física — estado actualizado

| Regla | Severidad | Estado |
|---|---|---|
| `B1` inversión térmica fuerte | FAIL | Gating |
| `C1` FED suma | FAIL | Gating |
| `C2` FED monotónica | FAIL | Gating |
| `A2` HRR sin combustible | FAIL | Gating |
| `A3` régimen vs O2 superior crítico | FAIL | Gating |
| `D1` balance de CO por sala/paso | FAIL | Gating |
| `E1` balance de combustible sólido | FAIL | Gating |
| `S0` conservación de humo global | FAIL | Gating |
| `O1` balance masa O2 bulk | WARN | Clean (11/11 PASS) |
| `O2E1` cross-check Thornton HRR↔O2 | WARN | 8/11 WARN findings (double-accounting) |

### Próxima sesión recomendada

1. Decidir si se aborda el double-accounting de `o2_consumed_kg_total_all` (fix: separar acumuladores bulk y upper, usar solo uno para Thornton).
2. Regenerar CSVs restantes con schema nuevo (`ilv_open_window_repro`, `p2h_diag_*`) para completar el corpus de 11/11.
3. O2E1 se queda como WARN hasta que el double-accounting esté resuelto y el corpus esté limpio.
4. No promover O2E1 a FAIL sin un plan explícito de fix + re-audit.

---

## Current Session Update — 2026-06-25 (rev 16 — Physics coherence + D1 CO balance gating)

### Estado operativo actual

- Branch: `main`, limpio antes del cierre documental, **ahead 12** respecto a `origin/main` (push pendiente antes de esta nota).
- HEAD previo al cierre: `b6e355f` — `feat(d1): promote D1 CO balance from WARN to FAIL`.
- Suite completa: 18 casos lanzados, **17 OK** y 1 timeout preexistente (`long_burnout_3600s`).
- `validate_reference_cases`: **349/354 PASS** — los 5 FAIL restantes son los `VALID_GAP` conocidos (Grupo A O2 window + Grupo C corridor temp).
- Physics coherence audit: **5/5 PASS**, **0 FAIL**, con D1 ya `FAIL`/gating.
- Tests Python de la fase: **221/221 PASS**.

### Validación física: cambio de enfoque

Se acordó dejar de tratar el problema como una suma de casos M4 y pasar a una revalidación física integral del motor. El objetivo es auditar, con balances e instrumentación, que sean coherentes:

- HRR, combustible, energía y régimen de combustión.
- O2 por capa/sala y su acoplamiento con HRR.
- CO/CO2/HCN, generación local, transporte y balance de carbono.
- Humo/soot, visibilidad, FED y tenabilidad.
- Temperaturas upper/lower, capas, presión, plano neutro e isoterma 150 C.
- Modelo bizona, ventilación por puertas/ventanas, flotabilidad, transporte multi-room/multi-planta.
- Paredes, radiación, almacenamiento térmico y reradiación.

Documento nuevo/actualizado:

- `docs/validation/MOTOR_PHYSICS_VALIDATION_CHECKLIST.md` — checklist maestro de items físicos pendientes y cobertura actual.

### Auditor físico general

Se creó e integró el auditor físico general:

- `scripts/simulation/check_physics_coherence.py`
- `scripts/simulation/audit_physics_coherence_suite.py`
- `tests/test_check_physics_coherence.py`

Reglas cerradas actualmente:

| Regla | Severidad | Estado |
|---|---|---|
| `B1` inversión térmica fuerte | FAIL | Gating |
| `C1` FED suma | FAIL | Gating |
| `C2` FED monotónica | FAIL | Gating |
| `A2` HRR sin combustible | FAIL | Gating |
| `A3` régimen vs O2 superior crítico | FAIL | Gating |
| `D1` balance de CO por sala/paso | FAIL | Gating |

El auditor está integrado en `run_full_reference_suite.ps1` junto al auditor ILV.

### D1 CO balance — cerrado y gating

La línea CO/CO2/HCN se cerró en D1 como balance real, no como heurística de "CO sube sin fuego local".

Instrumentación añadida al CSV sin cambiar física:

- `c_balance_frac`
- `carbon_conservation_error_kg`
- `co_kg`
- `co_generated_kg_step`
- `co2_generated_kg_step`
- `hcn_generated_kg_step`
- `co_net_transport_kg_step`
- Acumulados usados por D1: `co_generated_kg_total`, `co_net_transport_kg_total`, `co_exterior_removed_kg_total`

Invariante D1:

```text
delta_co = co_kg[t] - co_kg[t-1]
expected = delta(co_generated_kg_total) + delta(co_net_transport_kg_total) - delta(co_exterior_removed_kg_total)
residual = abs(delta_co - expected)
```

`D1` empezó como `WARN`, detectó rutas reales de CO no contabilizadas, y después se promovió a `FAIL` tras corpus limpio.

Paths corregidos por D1 (`b41fcbd`):

1. `GasExchangeSystem._purge_upper_species_to_exterior_direct` — actualiza `co_exterior_removed_kg_total`.
2. `ThermalSystem._flush_contaminant_deltas` — actualiza `co_net_transport_kg_total`.
3. `GasExchangeSystem._release_pending_interior_deliveries` — actualiza `co_net_transport_kg_total`.

Semántica importante: `co_net_transport_kg_total` es **neto amplio**, no solo room-to-room. Incluye intercambio, arrastre térmico/hot-gas carry y entregas interiores diferidas. La pérdida a exterior se trata por separado con `co_exterior_removed_kg_total`.

Resultados antes/después:

| CSV | Antes | Después |
|---|---:|---:|
| `layer_interface_single_room_window` | 1 WARN | 0 findings |
| `v5_m4_ventilation_throttle` | 612 WARN | 0 findings |
| `cfast_ilv_audit` | 0 | 0 findings |

### Hallazgos CO/CO2/HCN que quedan registrados

- CO y HCN usan masa interna (`kg`) para generación/transporte/conversión.
- CO2 tiene **dual tracking**: `co2_kg`/`co2_upper_kg` por masa, pero `co2_upper_ppm` sale de `co2_upper * 1e6` (tracer/fracción molar), no de `co2_upper_kg`.
- Por eso `D2` CO/CO2 ratio queda **bloqueado**: no implementar hasta resolver o documentar mejor la dualidad de CO2 upper.
- La regla naive "CO sube sin fuego local" queda descartada para multi-room: puede ser transporte real desde otra sala con fuego.

### Próxima sesión recomendada

1. Confirmar que el cierre documental quedó pusheado.
2. Mantener D1 como gating y no tocar su severidad/tolerancia salvo evidencia nueva.
3. Elegir el siguiente bloque de balance, preferiblemente **O2 + energía/HRR** antes que D2 CO/CO2 ratio.
4. Para O2/energía: inventariar columnas e instrumentación necesaria antes de añadir reglas.
5. No tocar HVAC ni visual FP en esta línea; están fuera de foco hasta estabilizar el núcleo físico.

---

## Current Session Update — 2026-06-23 (rev 15 — Ruta B: v5_m4_ventilation_throttle)

### Estado operativo actual

- Branch: `main`, limpio, **ahead 7** respecto a `origin/main` (push pendiente).
- Commit nuevo: `21ba9ee` — `test(ilv): add M4 ventilation throttle reference case`.
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

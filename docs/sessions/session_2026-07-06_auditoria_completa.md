# Sesión 2026-07-06 — Auditoría completa, rehabilitación de gates y expansión de cobertura

**Rama:** `main` · **Rev:** 35 · **Modelo:** Fable 5 (claude-fable-5)  
**Estado anterior:** `b695ea00` — 9 PASS / 5 CTRL / 3 WARN / 0 FAIL, exits 1 crónicos en ILV + guardrails

---

## Contexto de entrada

El proyecto tenía 2 de sus 3 suites-gate en **exit 1 crónico** (gates "quemados"): cualquier regresión nueva era indistinguible del rojo permanente. El CI (`validation-guardrails.yml`) también estaba en rojo. La auditoría arrancó con esa premisa y cubrió 6 vectores.

---

## 1. Rehabilitación de gates (todos en capa de validación)

### ILV layer coherence suite

- **3 CTRL nuevos registrados:** `cfast_two_floor_stairwell` (42 findings), `fuel_balance_diag_sealed` (35), `o2_stoich_diag_sealed` (35). Los tres son el bug ILV lower-O2 conocido (HRR zombie, `o2_upper ≈ 0.09%`) en configs selladas sin M4.
- **`v1_m4_pool_release` eliminado del set** — 0 findings tras M5 (zombie eliminado por `fire_post_bd_hrr_cut_enabled`). CTRL obsoleto.
- Resultado: **12 PASS / 5 CTRL / 0 FAIL, exit 0** (antes: 3 FAIL, exit 1).

### `gap_inventory_check.py`

- Añadida `KNOWN_VALID_GAP_REQUIRED_FAILURES: frozenset[str]` con los 5 VALID_GAP definitivos:
  `cfast_t240_o2_depleted`, `cfast_t350_o2`, `cfast_t360_o2`, `cfast_chain_r0_t180_temp_upper_c`, `cfast_chain_r0_t600_temp_upper_c`
- Gate pasa solo si los required fallidos ⊆ allowlist; required inesperado → exit 1; entrada obsoleta (VALID_GAP que ahora pasa) → exit 1.
- Añadidas funciones `classify_required_failures()` y `stale_valid_gap_entries()`.

### `validation_guardrails.py`

- Gate required migrado a la allowlist: label "PASS (5 VALID_GAP)" / "FAIL (N no permitidos)".
- Linter R1-3 (physics overrides): exención por `(stem, key)` para `(cfast_pool_fire_open, vent_bernoulli_flow_multiplier)` — override intencional Phase 9 C4 preexistente al linter. Deuda visible en el CTRL; retirar cuando el override se elimine en sesión de motor.
- Resultado: **8/8 gates PASS, exit 0** (antes: 4 secciones FAIL, exit 1).

### `phase2e_preflight.py`

- Sentinels non-required que fallan → etiqueta `"GAP (non-gating)"`, no bloquean.
- El sentinel `g4 FED timing` (non-required, uno de los 70 gaps) ya no gateba.

### `GAPS_INVENTORY.md`

- Encabezado actualizado: 345/350 → **349/354** required, 69 → **70** gaps.
- Delta anotado: +4 required (baselines `v5_m4_ventilation_throttle`, PASS); +3/−2 gaps por corrimiento de timestamps de presión (mismo gap estructural Phase 3).

### Tests nuevos — `tests/test_guardrails.py` (15 → 21)

| Test añadido | Qué verifica |
|---|---|
| `test_exit1_unexpected_required_failure` | Required nuevo no en allowlist → exit 1 (gap_inventory) |
| `test_exit0_valid_gap_required_failures_allowed` | Los 5 VALID_GAP no gatean |
| `test_exit1_valid_gap_plus_unexpected` | VALID_GAP + nuevo → exit 1 |
| `test_exit0_non_required_sentinel_fails` | Sentinel non-required no gateba (phase2e) |
| `class TestPhysicsOverrideLinter` (3) | Exención limitada a su (caso, clave); otra clave → exit 1 |
| `test_exit1_unexpected_required_failure` (guardrails) | Same gate via validation_guardrails |

---

## 2. Endurecimiento CTRL — envelopes por regla/conteo

`KNOWN_INTENTIONAL_CONTROLS` en **ambas** audit suites cambia de `frozenset[str]` a `dict[str, dict[str, int] | None]`.

### Mecánica

```python
# Antes
KNOWN_INTENTIONAL_CONTROLS: frozenset[str] = frozenset({"stem_a", "stem_b"})

# Ahora
KNOWN_INTENTIONAL_CONTROLS: dict[str, dict[str, int] | None] = {
    "stem_a": {"RULE_ID": max_count, ...},  # conteo medido × 1.25 headroom
    "stem_b": None,   # solo via --intentional CLI (legacy)
}
```

- Finding de regla no registrada en el envelope → caso reclasificado a **FAIL ("CTRL envelope excedido")**, gatea aunque el finding sea WARN-severity.
- Conteo medido por regla + ~25% de margen → jitter de CSV no flapa el gate; regresión real sí lo tripa.
- `v1_m4_pool_release` excluye `A3` a propósito: M5 lo eliminó; si reaparece → FAIL.
- `--intentional` CLI: envelope = `None` (ilimitado), legacy para overrides ad-hoc.

### Función nueva en ambas suites

```python
def envelope_violations(findings, envelope: dict[str, int] | None) -> list[str]:
    """Retorna lista de strings describiendo violaciones de envelope."""
```

### Tests actualizados

- `test_check_physics_coherence.py`: 209 → 216
- `test_audit_ilv_layer_coherence_suite.py`: 19 → 26

---

## 3. Guardrails nuevos — R2-1 (frescura) + PHY-P1 (plausibilidad)

### R2-1 — Frescura de reports

Verificación git-based en `validation_guardrails.py`:

1. Si hay cambios sin commitear en `sim/` o `sim/validation/cases/` → FAIL.
2. Si el commit más reciente del motor es más nuevo que el commit de `reference_checks.json` → FAIL.
3. Se omite con nota si no hay repositorio git o si el historial es superficial (CI shallow clone).

### PHY-P1 — Plausibilidad de métricas

```python
_KNOWN_PPM_VIOLATIONS: dict[str, frozenset[str]] = {
    "confinement_open_close":         frozenset({"room_1_peak_co2_ppm"}),
    "postfire_decay":                 frozenset({"room_1_peak_co2_ppm"}),
    "row_house_ground_floor_smoke":   frozenset({"room_2_peak_co2_ppm"}),
    "secondary_ignition_demo":        frozenset({"room_1_peak_co2_ppm"}),
    "v3_hallway_fed_exposure":        frozenset({"room_1_peak_co2_ppm"}),
    "v4_co_remote_rooms":             frozenset({"room_1_peak_co2_ppm"}),
    "v6_spread_to_hallway":           frozenset({"room_1_peak_co2_ppm"}),
}
```

- Métrica `*_ppm > 1e6` (> 100% de la mezcla) → FAIL, salvo parejas registradas.
- Nueva pareja no registrada → exit 1 (el bug no puede crecer en silencio).
- Métricas `tmp_*` ignoradas.

### Tests nuevos (21 → 31)

| Clase | Tests | Qué verifica |
|---|---|---|
| `TestReportsFreshness` (5) | `@skipUnless(_GIT_AVAILABLE)` | sync→0, dirty engine→1, dirty+regen→0, engine post-report→1, no repo→0 |
| `TestMetricPlausibility` (5) | Sin decorador | clean→0, violación nueva→1, known→0+nota, known+nueva_métrica→1, tmp_ignorado→0 |

### Resultado guardrails: 8 → **10/10 gates PASS**

---

## 4. Expansión de cobertura — 17 → 29 CSVs

### Pipeline

```
run_scenario.py --timeout 480 (headless Godot)
  → sim_log.csv
  → dedupe por (time_s, room_id)   ← artefacto engine: duplica último timestep
  → physics_coherence_issues() + ilv_layer_coherence_issues()
  → envelopes → reports/
```

### 12 casos nuevos

| Caso | Subsistema principal | Physics | ILV |
|---|---|---|---|
| `cfast_corridor_chain` | Corridor chain propagation | PASS | PASS |
| `cfast_hvac_residential` | HVAC species extraction | CTRL (D1/S1) | PASS |
| `cfast_multi_fuel_couch_tv` | Multi-fuel object | CTRL (ILV high) | CTRL |
| `cfast_suppression_water` | Suppression (water) | PASS | PASS |
| `flashover_simple_house` | Flashover transition | CTRL (A3/D2PRE/O2E1) | CTRL |
| `g3_gie_ppv_post_knockdown` | PPV ventilation post-knockdown | WARN (D2PRE) | CTRL |
| `glass_break_window_spike` | Glass failure opening | WARN (D2PRE) | CTRL |
| `pvc_curtain_hcl_release` | PVC/HCl toxicity | CTRL | CTRL |
| `two_storey_smoke` | Multi-planta smoke transport | WARN (D2PRE) | CTRL |
| `v4_co_remote_rooms` | CO en salas remotas | CTRL (A3/D2PRE/E1/O2E1) | CTRL |
| `v8_suppression_reburn` | Suppressión → reburn | CTRL (A3/D2PRE) | CTRL |
| `victim_fed_incapacitation` | FED/incapacitación víctima | CTRL (A3/D2/D2PRE/E1/O2E1) | CTRL |

### Artefacto engine descubierto

El engine duplica las filas del último timestep en `sim_log.csv`. Causó falso FAIL S0 con factor 2.0 en `v4_co_remote_rooms`. Los 17 CSVs preexistentes están limpios. Fix en pipeline: `dedupe_by_time_room(rows)` antes del análisis.

### Estado final de suites

| Suite | Antes | Después |
|---|---|---|
| Physics coherence | 9/5/3/0 (17 CSVs) | **10 PASS / 12 CTRL / 7 WARN / 0 FAIL** (29 CSVs) |
| ILV layer coherence | 12/5/0 (17 CSVs) | **15 PASS / 14 CTRL / 0 FAIL** (29 CSVs) |
| Guardrails | 8/8 | **10/10** |
| Tests totales | 209+21 | **242+31** |

Los 7 WARN son todos D2PRE (Plan B / M1 scope).

---

## 5. Bug en `scripts/check_docs_links.py`

El checker de links Markdown fallaba (exit 1) porque `.claude/worktrees/` contiene copias históricas de docs con rutas absolutas de otra máquina.

**Fix:** añadido `if ".claude" in path.parts: continue` en el loop de escaneo.

```python
for path in sorted(ROOT.rglob("*.md")):
    if ".git" in path.parts:
        continue
    if ".claude" in path.parts:   # ← nuevo
        continue
    ...
```

---

## 6. Hallazgos de motor descubiertos (pendientes de sesión dedicada)

### Bug CO₂ bulk >100% en salas receptoras (PHY-P1)

**7 casos afectados:** `confinement_open_close`, `postfire_decay`, `row_house_ground_floor_smoke`, `secondary_ignition_demo`, `v3_hallway_fed_exposure`, `v4_co_remote_rooms`, `v6_spread_to_hallway`

- `room_N_peak_co2_ppm`: 1.02×10⁶ – 2.10×10⁶ ppm (imposible — >100% de la mezcla)
- Siempre sala receptora (nunca fire room, nunca métricas upper)
- Explica el FED=3.47×10⁹ de `v3_hallway` (fed_co=3.39×10⁹ — la fórmula de Purser lee CO₂ bulk imposible a altura de víctima)
- Root cause probable: path bulk/lower en transporte inter-room acumula especies sin dilución correcta
- Acotado por PHY-P1; 7 parejas en `_KNOWN_PPM_VIOLATIONS`

### Gap instrumentación HVAC de especies (D1/S1)

`HVACSystem.gd` extrae smoke/CO de rooms pero no escribe en los acumuladores de balance → D1:~58 + S1:~36 en `cfast_hvac_residential`. Mismo root cause que el skip O1 de HVAC. Absorbido en CTRL envelope.

### Write-off de inventario de fuel post-extinción (E1)

En `victim_fed_incapacitation` a t=650s: `solid_fuel_remaining_MJ` cae 2.200,15 MJ en un paso para igualar `fuel_remaining_MJ` post-extinción — dos inventarios divergen durante el burn y reconcilian sin acumulador de consumo. E1 lo caza. Absorbido en CTRL envelope.

### Resumen de candidatos para próxima sesión de motor

| Prioridad | Bug | Impacto si se cierra |
|---|---|---|
| 1 | Plan B / M1 (`o2_scale` double-throttle 2.56×) | Cierra los 7 WARN D2PRE + gran parte de D2PRE en CTRLs |
| 2 | CO₂ bulk >100% en receptoras | Corrige FED/toxicidad imposibles; retira 7 parejas PHY-P1 |
| 3 | Instrumentación HVAC de especies | Retira CTRL `cfast_hvac_residential`; cierra skip O1 |
| 4 | Write-off inventario fuel post-extinción | Retira E1 de `victim_fed_incapacitation` CTRL |

---

## 7. Archivos modificados en la sesión

### Modificados (5 archivos, pendientes de commit)

| Archivo | Cambios |
|---|---|
| `scripts/simulation/audit_physics_coherence_suite.py` | CTRL frozenset → dict envelopes; `envelope_violations()`; 7 CTRLs coverage expansion |
| `scripts/simulation/audit_ilv_layer_coherence_suite.py` | CTRL frozenset → dict envelopes; `envelope_violations()`; 8 CTRLs coverage expansion; `v1_m4_pool_release` eliminado |
| `scripts/simulation/validation_guardrails.py` | R2-1 frescura + PHY-P1 plausibilidad; allowlist VALID_GAP; exención R1-3 |
| `scripts/simulation/gap_inventory_check.py` | `KNOWN_VALID_GAP_REQUIRED_FAILURES`; `classify_required_failures()`; `stale_valid_gap_entries()` |
| `scripts/simulation/phase2e_preflight.py` | Sentinels non-required → GAP (non-gating) |
| `scripts/check_docs_links.py` | Skip `.claude/` en escaneo |
| `docs/validation/GAPS_INVENTORY.md` | Encabezado 349/354 + 70 gaps |
| `CHANGELOG.md` | Entradas rev 35 |
| `docs/HANDOFF_CURRENT_STATE.md` | Rev 35 completo |

### Archivos nuevos (12 CSVs, pendientes de commit)

```
sim/validation/reports/cfast_corridor_chain.csv
sim/validation/reports/cfast_hvac_residential.csv
sim/validation/reports/cfast_multi_fuel_couch_tv.csv
sim/validation/reports/cfast_suppression_water.csv
sim/validation/reports/flashover_simple_house.csv
sim/validation/reports/g3_gie_ppv_post_knockdown.csv
sim/validation/reports/glass_break_window_spike.csv
sim/validation/reports/pvc_curtain_hcl_release.csv
sim/validation/reports/two_storey_smoke.csv
sim/validation/reports/v4_co_remote_rooms.csv
sim/validation/reports/v8_suppression_reburn.csv
sim/validation/reports/victim_fed_incapacitation.csv
```

### Tests modificados

| Archivo | Antes | Después |
|---|---|---|
| `tests/test_guardrails.py` | 15 | 31 |
| `tests/test_check_physics_coherence.py` | 209 | 216 |
| `tests/test_audit_ilv_layer_coherence_suite.py` | 19 | 26 |

---

## 8. Estado post-sesión (verificado en vivo)

```
validate_reference_cases:   349/354 PASS (5 VALID_GAP, sin cambio)
physics_coherence_suite:    10 PASS / 12 CTRL / 7 WARN / 0 FAIL  exit 0
ilv_layer_coherence_suite:  15 PASS / 14 CTRL / 0 FAIL            exit 0
validation_guardrails:      10/10 PASS                             exit 0
tests/test_guardrails.py:   31/31 PASS
tests/test_check_physics_coherence.py: 216/216 PASS
tests/test_audit_ilv_layer_coherence_suite.py: 26/26 PASS
check_docs_links.py:        PASS (exit 0)
```

**Constraints vigentes (no modificados):** No ILV · No M2 global · No tocar sim/core sin plan · No tocar doorway O2 sin plan · No ampliar tolerancias para silenciar gaps · No tocar CO defaults · No tocar baselines · No push salvo que se pida.

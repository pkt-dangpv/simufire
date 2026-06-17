# Estado de sesión — 2026-05-27

## Resumen ejecutivo

Sesión de investigación y corrección de logs canónicos estables.

- **Problema resuelto**: 5 archivos de log canónicos estaban obsoletos (generados en sesiones anteriores con distintos estados de código). Esto producía que `validate_reference_cases.py` generara valores erróneos en `reference_checks.json`.
- **Root cause confirmado**: `cfast_window_break_t180.log` (2026-05-21) tenía `Up=36.53°C` a t=300s a pesar de HRR=951kW — artefacto de un código anterior con tasa de enfriamiento excesiva tras apertura de ventana. El código actual (HEAD) produce correctamente 313.47°C.
- **Acción tomada**: Re-ejecutados los 5 casos canónicos con Godot (exit 0 todos). Aceptados 60 gaps (era 54 backup enmascarado). Commit `17d5981` creado.

---

## Estado del sistema de validación

| Componente | Estado |
|---|---|
| `reference_checks.json` | ✅ Fresco — 60 gaps, 292/292 PASS |
| `GAPS_INVENTORY.md` | ✅ Actualizado — 60 gaps, sección O₂ expandida |
| Guardrails | ✅ ALL GUARDRAILS PASS |
| Git | HEAD = `17d5981` (main, 1 ahead of origin/main) |
| Working tree | Limpio (solo .pyc untracked) |

---

## Cambios en gap inventory (54 → 60)

| Categoría | Antes | Después | Cambio |
|---|---|---|---|
| O₂ zona inferior | 6 | 13 | +7 structural Phase 2A |
| RMSE temperatura superior | 7 | 6 | -1 fastgrowth ahora PASS |
| **Total** | **54** | **60** | **+6 neto** |

### 7 nuevos gaps o2_lower (Phase 2A — no gating, required=False)
Causa estructural: SimuFire 1-zona vs CFAST 2-zona (lower zone O₂).
- `cfast_t350_o2_lower` — sala sellada pre-window, SF depleta o2_lower, CFAST LLO₂ ~ambient
- `cfast_t420_o2_lower` — sala post-window-open, mismo efecto
- `cfast_closed_t300_o2_lower` — sala cerrada, SF 0.069 vs CFAST 0.205
- `cfast_closed_t450_o2_lower` — sala cerrada, igual
- `cfast_2r_r0_t180_o2_lower` — two-room, SF 0.209 vs CFAST 0.095 (door open, O₂ transfer)
- `cfast_2r_r0_t300_o2_lower` — igual
- `cfast_2r_r0_t450_o2_lower` — igual

### 1 gap cerrado
- `cfast_fastgrowth_rmse_temp_upper_c` — RMSE 162°C → 39°C (threshold ≤60°C), ahora PASS

---

## Valores clave recuperados en logs frescos

| Log | Métrica | Valor stale | Valor fresco | Diferencia |
|---|---|---|---|---|
| `cfast_window_break_t180` | t=300s temp_upper_c | 36.53°C | 313.47°C | +277°C |
| `cfast_door_close_midfire` | t=120s temp_upper_c | 240.02°C | 159.54°C | -80°C |

---

## Configuración de producción

```
Phase 2E Sub-A: phase2e_co2_suba_enabled = true, gain = 0.20
Phase 2E Sub-D: phase2e_co2_subd_enabled = true
Phase 2H:       phase2h_candidate_preset = false (opt-in candidate, default OFF)
```

---

## Comandos de validación

```powershell
# Run individual canonical case
& "F:\OneDrive\Escritorio\Godot_v4.6.3-stable_win64_console.exe" --headless --path "F:\OneDrive\Documentos\GitHub\simufire" -- --validation-case=CASE_NAME

# Regenerate reference_checks.json
python scripts/simulation/validate_reference_cases.py

# Run guardrails
python scripts/simulation/validation_guardrails.py
```

---

## Git

```
HEAD:          17d5981  fix: refresh canonical logs + update gap inventory (60 gaps, all required PASS)
origin/main:   29b925d  fix(phase2h): validate guard v4 opt-in candidate
Status:        1 ahead of origin/main (NOT pushed)
```

### Archivos del commit `17d5981`
- `sim/validation/reports/reference_checks.json` — 60 gaps, all_required_pass=true
- `sim/validation/reports/cfast_door_close_midfire.json` — fresh 2026-05-27
- `sim/validation/reports/cfast_single_room_closed.json` — fresh 2026-05-27
- `sim/validation/reports/cfast_two_room_door_open.json` — fresh 2026-05-27
- `sim/validation/reports/cfast_window_break_t180.json` — fresh 2026-05-27
- `docs/validation/GAPS_INVENTORY.md` — updated with 60 gaps

---

## Notas para siguiente sesión

- El commit `17d5981` NO está pusheado a origin. Si se requiere push: `git push origin main`
- Los 7 nuevos gaps o2_lower son no-gating (required=False). No requieren acción adicional.
- Phase 2H sigue como opt-in candidate (default OFF). Si se promueve, rebaseline necesario.
- El backup `reference_checks.BACKUP.json` (54 gaps) fue eliminado — ya no existe en disco.

---

## Sesión 2026-05-27 (continuación) — Route A: caso ghanekar_kitchen_living_room

### Resumen
Implementación completa del nuevo caso empírico de cocina/salon. Resultado: **1/5 checks PASS** (O₂ timing correcto), 4 gaps documentados (non-gating). Sin regresión. 292/292 required PASS.

### Archivos modificados/creados

| Archivo | Cambio |
|---------|--------|
| `sim/validation/cases/ghanekar_kitchen_living_room.json` | CREADO — caso nuevo R3=LivingRoom 56m², duración 1100s, α=0.0025 |
| `scripts/simulation/validate_reference_cases.py` | `build_ghanekar_kitchen_checks()` añadida (5 checks required=False) + main() actualizado |
| `sim/validation/run_reference_checks.ps1` | `"ghanekar_kitchen_living_room"` añadido al array `$cases` |
| `scripts/simulation/audit_validation_freshness.py` | `"ghanekar_kitchen_living_room"` en exploratory set (verificado, ya estaba presente) |
| `sim/validation/reports/ghanekar_kitchen_living_room.json` | GENERADO — run de 1100s con Godot GUI (timeout 480s) |
| `docs/validation/GAPS_INVENTORY.md` | Nota 2026-05-27e + 4 nuevas filas Section 7 + header actualizado (64 gaps) |

### Resultados de los 5 checks

| Check | Actual | Expected | Tolerancia | Estado |
|-------|--------|----------|------------|--------|
| `ghanekar_kitchen_far_hall_o2_response_s` | 387.8 s | 402 s | ±84 s | **PASS** |
| `ghanekar_kitchen_far_hall_fed_0_3_s` | 1057 s | 546 s | ±120 s | FAIL (+511 s) |
| `ghanekar_kitchen_far_hall_fed_1_0_s` | None | 624 s | ±126 s | FAIL |
| `ghanekar_kitchen_far_hall_idlh_co_s` | None | 642 s | ±102 s | FAIL |
| `ghanekar_kitchen_fire_room_flashover_s` | None | 894 s | ±30 s | FAIL |

### Diagnóstico root cause
- **CO gap**: CO no alcanza ni 200 ppm en R2 (pasillo lejano). FED acumula sólo vía O₂ depleción → llega 2× tarde.
- **Ventilación**: puerta exterior R3↔exterior open=1.0 disipa calor → T_upper_R3 pico = 426°C, flashover (600°C) no alcanzado.
- **Sweep α descartado**: O₂ check PASA con α=0.0025; subir α sacaría O₂ fuera de tolerancia sin resolver CO/flashover.

### Estado del sistema tras la sesión

| Componente | Estado |
|---|---|
| `reference_checks.json` | ✅ Fresco — **64 gaps**, 292/292 PASS |
| `GAPS_INVENTORY.md` | ✅ Actualizado — nota 2026-05-27e, Section 7 expandida (8 rows) |
| Guardrails | ✅ 292/292 PASS required, sentinels PASS |
| `audit_validation_freshness.py` | ✅ `ghanekar_kitchen_living_room` en exploratory set |
| Godot GUI binary | `F:\OneDrive\Escritorio\Godot_v4.6.3-stable_win64.exe` — usar con `-GodotExe` explícito |

### Próximo paso sugerido
- (a) Evaluar cerrar puerta exterior en `engine_overrides` del caso kitchen para aislar efecto ventilación vs Ghanekar
- (b) Calibrar CO yield para fuegos tipo salón grande (Phase 3)
- (c) Hasta entonces, 4 gaps permanecen non-gating; datos insuficientes para upgrade a required

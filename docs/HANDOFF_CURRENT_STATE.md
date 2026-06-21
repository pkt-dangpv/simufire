# Current Handoff State

Date: 2026-06-21.

## Purpose

This note records the repository hygiene and validation state after the non-motor cleanup. It is meant to let another machine or contributor continue without relying on chat history.

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

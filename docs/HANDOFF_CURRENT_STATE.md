# Current Handoff State

Date: 2026-06-19.

## Purpose

This note records the repository hygiene and validation state after the non-motor cleanup. It is meant to let another machine or contributor continue without relying on chat history.

## Current Session Update — 2026-06-19

- Branch: `main`, synchronized with `origin/main`.
- Latest pushed commit before this work: `72c4e98 docs(validation): audit CFAST and Ghanekar model geometry`.
- Current validation baseline: `336/350` required PASS, `14/350` required FAIL.
- `docs/validation/STATUS_VALIDATION.md` is the current validation source of truth.
- `docs/validation/CFAST_EQUIVALENCE_AUDIT_2026-06-19.md` records the equivalence audit and 2026-06-19 resolution that reduced required FAILs to 14.
- `docs/validation/CFAST_GHANEKAR_MODEL_AUDIT_2026-06-19.md` records the dwelling-model audit across CFAST/Ghanekar comparison cases.
- A-E validation groups were diagnosed and documented.
- Group C `cfast_corridor_chain` t300 was resolved by `doorway_thermal_counterflow_gain=0.25` in `sim/validation/cases/cfast_corridor_chain.json`.
- Remaining Group C t180/t600 failures are still structural M3/Phase 2 gaps.
- `cfast_multifuel_rmse_temp_upper_c` was resolved by matching the CFAST vented exterior-door topology with a 0.9x2.0 exterior opening open from t=0. Fresh RMSE=183.79°C <= 200°C.
- `cfast_window_break_t180` now matches CFAST window geometry (1.2x1.0, sill 0.8); the t300 pressure known gap now passes.
- `cfast_corridor_chain.in` R2 now matches SimuFire at 25.2 m3 and CFAST outputs were regenerated; required R0 t180/t600 failures remain structural.
- Equivalence audit result: all 14 current required FAILs are valid architecture/model gaps after geometry/topology reconciliation.
- Model audit result: CFAST multifuel/window/corridor R2 caveats were corrected; Ghanekar kitchen/living remains approximate/no estricto.
- No motor/core code, tolerances or required/known-gap classifications were changed in this session.

Validation commands run during this session:

```powershell
python scripts\simulation\validate_reference_cases.py
python scripts\simulation\validation_guardrails.py --verbose
python scripts\check_docs_links.py
git diff --check
```

Current guardrail state:

- Required checks: FAIL, expected, `14` required failures.
- Known gaps: `75` non-gating gaps in JSON and docs.
- Gap inventory count: synchronized, but guardrail still reports FAIL because required checks remain.
- Phase 2E sentinel: still FAIL on `g4 FED timing [s]`.
- Carbon/HCN sentinels: PASS.
- Legacy/two-zone contract: PASS.
- CFAST truth integrity: PASS.
- Physics override linter: PASS.

Recommended next work:

1. If pausing or changing machine, start from `docs/validation/STATUS_VALIDATION.md` and this handoff.
2. If continuing validation, treat the next low-risk experiment as separate work:
   - `cfast_two_room_door_open`: C3 RMSE per-stage diagnosis.
   - `cfast_corridor_chain`: only with a full doorway mass+energy plan, not another scalar gain sweep.
3. If prioritizing product/UX, resume the FP temperature HUD investigation below.
4. Do not start ILV or Phase 2C HVAC without an explicit architecture pass.

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

Commands run on 2026-06-17:

```powershell
python scripts\check_docs_links.py
python -m unittest tests.test_ui_localization -v
python -m unittest tests.test_editor_scenarios -v
python scripts\simulation\validation_guardrails.py --verbose
git diff --check
git diff --cached --check
```

Current result:

- Markdown links: PASS.
- UI localization tests: PASS.
- Editor scenario tests: PASS.
- Diff whitespace checks: PASS.
- Validation guardrails: FAIL, expected/current validation-lane issue.

The validation guardrail failure is not caused by repo organization or missing docs. The remaining blockers are:

- 16 required validation checks fail in `sim/validation/reports/reference_checks.json`.
- 1 Phase 2E sentinel fails: `g4 FED timing [s]`, actual `160.0833`, expected `201.5000 +/- 10.00`.

The following guardrail parts are now clean:

- Gap count is synchronized: `76` non-gating gaps in JSON and docs.
- Physics override linter passes.
- Carbon/HCN sentinels pass.
- Legacy/two-zone contract passes.
- CFAST truth integrity passes.

## Important Constraint

No simulation motor, editor runtime, visualizer runtime, scenes, HUD logic or physics formulas were intentionally changed during this cleanup. The only validation case change was removing the forbidden `vent_bernoulli_flow_multiplier` override from `sim/validation/cases/cfast_pool_fire_open.json`.

Do not try to make `validation_guardrails.py` green by widening tolerances, rewriting reports or reclassifying required failures unless the scientific validation decision has been explicitly reviewed.

## Estado actual de esta máquina (2026-06-18)

- Rama: `main`.
- Commit remoto base de hoja de ruta: `4bacebd Consolidate active roadmap`.
- Commit local de handoff pendiente de subir al iniciar este guardado: `f76e5ba docs(handoff): update sync state 2026-06-18 — power loss on other machine`.
- Baseline anterior: 16/350 required FAIL. Baseline actual tras 2026-06-19: 14/350 required FAIL.
- El plan ILV está documentado pero sin implementar.
- Hoja de ruta activa: `docs/planning/MASTER_ROADMAP_CURRENT.md`.
- No hay cambios de motor/core en la hoja de ruta ni en este handoff.

## Próximo paso recomendado

Ejecutar baseline de guardrails para confirmar 14/350 antes de tocar motor:

```powershell
python scripts\simulation\validation_guardrails.py --verbose
```

Después elegir una línea explícita:

- Producto/UX: hotfix de temperatura FP.
- Validación acotada: diagnóstico `cfast_two_room_door_open` RMSE o plan completo de doorway thermal para `cfast_corridor_chain`.
- Diagnóstico largo: `cfast_two_room_door_open` RMSE.
- Arquitectura: Phase 2/Phase 2C solo con plan explícito.

## Estado guardado ahora (2026-06-18)

- La planificación activa quedó consolidada en `docs/planning/MASTER_ROADMAP_CURRENT.md`.
- Se retiraron de la planificación activa los roadmaps antiguos que podían confundir:
  - `docs/planning/FINAL_VALIDATION_AND_PUBLICATION_PLAN.md`
  - `docs/planning/PLAN_TRABAJO.md`
  - `docs/roadmaps/ROADMAP_POST_V0_4_0.md`
  - `docs/roadmaps/ROADMAP_TECHNICAL_SIMULATOR_V0_5.md`
- El siguiente trabajo real no es ILV todavía salvo decisión expresa. Los grupos A-E ya están diagnosticados; no repetirlos salvo que una corrida fresca cambie el baseline.
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

## Pending Temperature HUD Investigation

No fix has been applied yet for the first-person HUD temperature jumps.

Current diagnosis:

- The exterior-opening smoothing hotfix exists: commit `69d6b55 feat(hotfix): exterior opening transition smoothing`.
- `open_fraction_smooth` is applied in several gas/O2 paths.
- Some thermal paths still appear to read `open_fraction` directly, so opening a window can still affect heat transfer abruptly.
- The first-person HUD displays `temp_at_1_8m_c`, `temp_at_1_1m_c` or `temp_at_0_5m_c` directly, refreshed every 0.05 s, without a display-side damping layer.
- If the thermal interface crosses near the player eye height, the HUD can jump between lower/mixed/upper temperatures even when the scene looks continuous.

Recommended next analysis before editing motor code:

- Log or display, for the current FP room: `temp_at_1_8m_c`, `temp_upper_c`, `temp_lower_c`, `thermal_layer_m`, `open_fraction`, `open_fraction_smooth`.
- Decide separately between a motor-side fix for thermal use of smoothed exterior opening fractions and a HUD-only visual smoothing fix.

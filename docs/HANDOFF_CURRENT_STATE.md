# Current Handoff State

Date: 2026-06-18.

## Purpose

This note records the repository hygiene and validation state after the non-motor cleanup. It is meant to let another machine or contributor continue without relying on chat history.

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
- 16/350 required FAIL en validation guardrails (esperado, no es regresión).
- El plan ILV está documentado pero sin implementar.
- Hoja de ruta activa: `docs/planning/MASTER_ROADMAP_CURRENT.md`.
- No hay cambios de motor/core en la hoja de ruta ni en este handoff.

## Próximo paso recomendado

Ejecutar baseline de guardrails para confirmar 16/350 antes de tocar motor:

```powershell
python scripts\simulation\validation_guardrails.py --verbose
```

Después atacar **Grupo A** (`cfast_r0_window_360` O2): diagnóstico sin tocar motor.

## Estado guardado ahora (2026-06-18)

- La planificación activa quedó consolidada en `docs/planning/MASTER_ROADMAP_CURRENT.md`.
- Se retiraron de la planificación activa los roadmaps antiguos que podían confundir:
  - `docs/planning/FINAL_VALIDATION_AND_PUBLICATION_PLAN.md`
  - `docs/planning/PLAN_TRABAJO.md`
  - `docs/roadmaps/ROADMAP_POST_V0_4_0.md`
  - `docs/roadmaps/ROADMAP_TECHNICAL_SIMULATOR_V0_5.md`
- El siguiente trabajo real no es ILV todavía salvo decisión expresa: primero confirmar baseline y atacar validación Grupo A.
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

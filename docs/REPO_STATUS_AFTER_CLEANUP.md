# Repository Status After Cleanup

Date: 2026-06-17.

## Summary

The repository has been reorganized so the root is focused on project entrypoints, configuration and major folders. Historical sessions, loose generated artifacts, exploratory scripts and local literature now live under documented archive or library locations.

For machine-to-machine or session-to-session continuation, see `docs/HANDOFF_CURRENT_STATE.md`.

## Root Entrypoints

- `README.md`
- `CHANGELOG.md`
- `CONTRIBUTING.md`
- `project.godot`
- `Main.gd`
- `icon.svg`
- `.github/`
- product folders such as `sim/`, `editor/`, `view/`, `ui/`, `scenes/`, `scripts/`, `tools/`, `docs/`, `tests/`

## Documentation Structure

- `docs/INDEX.md`: main documentation entrypoint.
- `docs/COMMANDS.md`: official commands.
- `docs/architecture/`: architecture maps, boundaries, ADRs and refactor plans.
- `docs/validation/`: validation status, summaries and gaps.
- `docs/audits/`: audit reports.
- `docs/planning/`: plans and checklists.
- `docs/archive/`: historical non-runtime artifacts.
- `docs/literature/`: local bibliography.

## Checks Run

- `python scripts/check_docs_links.py`: passing.
- `python -m unittest tests.test_ui_localization -v`: passing.
- `python -m unittest tests.test_editor_scenarios -v`: passing.
- `python scripts/simulation/validation_guardrails.py --verbose`: failing because 16 required validation checks and one Phase 2E sentinel remain red.
- `git diff --check`: passing.
- `git diff --cached --check`: passing.
- `powershell -ExecutionPolicy Bypass -File scripts/clean_workspace.ps1 -WhatIf`: passing.

## Known Open Point

`python -m unittest tests.test_guardrails -v` currently fails in the integration smoke that reads the real `reference_checks.json`. This has been documented in `docs/validation/GUARDRAILS_STATUS.md` and intentionally kept out of the lightweight product CI workflow.

## Runtime Impact

No simulation motor, editor runtime, visualizer runtime, HUD, scenes or physics formulas were intentionally changed. The changes are documentation, repository organization, CI metadata and helper scripts.

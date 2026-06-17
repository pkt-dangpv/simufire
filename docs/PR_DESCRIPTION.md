# Pull Request Description

## Summary

This change reorganizes repository documentation and non-runtime artifacts, adds documentation/tooling entrypoints, and introduces lightweight CI for documentation and product Python checks.

## What Changed

- Cleaned root-level historical sessions, temporary outputs, loose JSONs and exploratory scripts into documented archive folders.
- Moved local literature from `Docu Simufire/` to `docs/literature/`.
- Reorganized `docs/` into audits, architecture, validation, planning, roadmaps, handoff, archive and literature.
- Added documentation entrypoints, architecture maps, module boundaries, refactor plan, ADRs, templates, release checklist and artifact policy.
- Added Markdown link checker and large-file reporting helper.
- Added cleanup helper for ignored local artifacts.
- Added GitHub Actions workflows for docs checks and lightweight product Python tests.

## Verification

- `python scripts/check_docs_links.py`
- `python -m unittest tests.test_ui_localization -v`
- `python -m unittest tests.test_editor_scenarios -v`
- `git diff --check`
- `powershell -ExecutionPolicy Bypass -File scripts/clean_workspace.ps1 -WhatIf`

## Risk

Low runtime risk. The change is documentation, repository organization, CI metadata and helper scripts. No simulation motor, scene behavior, editor runtime, HUD or visualizer logic was intentionally changed.

## Known Follow-Up

- `tests.test_guardrails` still needs validation-lane review because the real-json integration smoke currently fails against the current validation report state.
- Future work can begin with the documented refactor plan for large files.

# Changelog

All notable changes to SimuFire should be recorded here.

## Unreleased

### Documentation and Repository Structure

- Organized documentation into `docs/audits/`, `docs/architecture/`, `docs/roadmaps/`, `docs/validation/`, `docs/planning/`, `docs/handoff/`, `docs/archive/`, and `docs/literature/`.
- Added documentation entrypoints: `docs/INDEX.md`, `docs/COMMANDS.md`, `docs/LOCAL_WORKSPACE.md`, `docs/ARTIFACT_POLICY.md`, `docs/LINK_AUDIT.md`, and `docs/RELEASE_CHECKLIST.md`.
- Added architecture documents: `PROGRAM_FLOW.md`, `CONTRIBUTOR_GUIDE.md`, `MODULE_BOUNDARIES.md`, and `REFACTOR_PLAN.md`.
- Added ADRs for documentation layout, script/tool boundaries, validation lanes, artifact policy, and local literature.
- Added audit issue index and templates for future ADRs, audits, release notes, and technical issues.
- Moved root session notes, temporary artifacts, exploratory scripts, and local literature into documented archive/library locations.

### Tooling

- Added `scripts/check_docs_links.py` for lightweight Markdown link checks.
- Added `scripts/clean_workspace.ps1` for safe cleanup of ignored local artifacts.
- Added documentation and product Python GitHub Actions workflows.

## v0.4.0-validation-rc1

### Validation Status

- Legacy required checks documented as passing.
- Two-Zone M4 contract documented as opt-in and passing.
- Known non-gating HVAC and empirical flashover gaps documented.

### Notes

- See `docs/validation/SIMUFIRE_VALIDATION_SUMMARY_2026-05-31.md` and `docs/validation/STATUS_VALIDATION.md` for validation detail.

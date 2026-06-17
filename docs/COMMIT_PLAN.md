# Commit Plan

This plan groups the repository hygiene work into reviewable commits. It is intended for maintainers who want to split the current workspace changes before merging.

## Commit 1: Clean Root and Archive Historical Artifacts

Suggested message:

```text
Organize root artifacts and local literature
```

Scope:

- move `ESTADO_SESION_*` files from root to `docs/sessions/root/`;
- move root `tmp_*`, `last_*`, logs and loose JSON output to `docs/archive/root-artifacts/`;
- move root exploratory scripts to `tools/archive/root-scripts/`;
- move local literature from `Docu Simufire/` to `docs/literature/`;
- update `.gitignore` exceptions for intentional archives.

## Commit 2: Reorganize Documentation

Suggested message:

```text
Restructure documentation entrypoints
```

Scope:

- create `docs/audits/`, `docs/architecture/`, `docs/roadmaps/`, `docs/validation/`, `docs/planning/`, `docs/handoff/`;
- update `docs/INDEX.md`;
- update README documentation links;
- add artifact, local workspace, link audit and release checklist docs.

## Commit 3: Add Documentation and Product Tooling

Suggested message:

```text
Add docs checks and lightweight product CI
```

Scope:

- add `scripts/check_docs_links.py`;
- add `scripts/clean_workspace.ps1`;
- add docs/product GitHub workflows;
- add `docs/COMMANDS.md`;
- add `scripts/README.md`, `tools/README.md`, `tools/INDEX.md`.

## Commit 4: Add Architecture Governance Docs

Suggested message:

```text
Document architecture boundaries and refactor plan
```

Scope:

- add program flow, module boundaries, dependency audit and contributor guide;
- add refactor plan and large files inventory;
- add ADRs and templates;
- add guardrails status and repo status docs.

## Commit 5: Add Project Metadata

Suggested message:

```text
Add changelog and PR summary
```

Scope:

- add `CHANGELOG.md`;
- add `docs/PR_DESCRIPTION.md`;
- add `docs/COMMIT_PLAN.md`.

## Notes

If preserving move detection is important, stage with:

```powershell
git add -A
git status --short
```

Git will show many entries as deletes plus adds until staged; after staging, most documentation moves should be recognized as renames.

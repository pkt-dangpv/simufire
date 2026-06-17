# Run Without Polluting the Repository

This guide explains how to run common checks while keeping generated files out of the repository root.

## Before Running

Check current state:

```powershell
git status --short
```

Use `-WhatIf` before cleanup:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/clean_workspace.ps1 -WhatIf
```

## Documentation Checks

```powershell
python scripts/check_docs_links.py
git diff --check
```

These should not create artifacts.

## Product Checks

```powershell
python scripts/check_product.py
```

This may exercise Godot headless and can create local ignored artifacts. Review `graphs/`, `runs/`, `.godot_validation_logs/` or temporary output before cleanup.

## Scenario Runs

Prefer explicit output directories:

```powershell
python scripts/run_scenario.py scenarios/compact_apartment_reference.json --duration 60 --out-dir runs/compact_apartment_reference
```

`runs/` is ignored by Git.

## Cleanup

```powershell
powershell -ExecutionPolicy Bypass -File scripts/clean_workspace.ps1
```

Add `-IncludeGodotCache` only when Godot is closed and you want to rebuild import/cache state.

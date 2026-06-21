# SimuFire

SimuFire is a Godot-based compartment fire dynamics simulator for training, scenario comparison and firefighter decision-support workflows.

It combines a scenario editor, 2D/3D/first-person visualization, technical exports and a validation lane for scientific guardrails.

**Current status**: `v0.4.0-validation-rc2` · 345/350 PASS · 5 VALID_GAP (structural, Phase 2/3+) · Godot 4.6.3.

## Quickstart

```powershell
# Product/editor checks
python scripts/check_product.py

# Documentation links
python scripts/check_docs_links.py

# Fast scientific guardrails
python scripts/simulation/validation_guardrails.py

# Recalculate checks from existing reports
python scripts/simulation/validate_reference_cases.py

# Full fresh scientific validation, requires Godot
powershell -ExecutionPolicy Bypass -File sim/validation/run_reference_checks.ps1 -TimeoutSeconds 900

# Run a scenario and generate technical outputs
python scripts/run_scenario.py scenarios/compact_apartment_reference.json --duration 60
```

More commands are listed in [docs/COMMANDS.md](docs/COMMANDS.md).

## Main Features

- Scenario editor for residential compartment layouts.
- Runtime simulation scene with HUD, 2D, 3D and first-person views.
- Compartment fire phenomena including HRR, oxygen effects, smoke, toxic gases, tenability, ventilation, HVAC, glass failure and suppression hooks.
- Technical logging, graph generation and validation reports.
- Separate product/editor checks and scientific validation lanes.

## Documentation

- [docs/INDEX.md](docs/INDEX.md): documentation entrypoint.
- [docs/architecture/PROGRAM_FLOW.md](docs/architecture/PROGRAM_FLOW.md): product flow and architecture map.
- [docs/architecture/MODULE_BOUNDARIES.md](docs/architecture/MODULE_BOUNDARIES.md): intended module boundaries.
- [docs/validation/SIMUFIRE_VALIDATION_SUMMARY_2026-05-31.md](docs/validation/SIMUFIRE_VALIDATION_SUMMARY_2026-05-31.md): validation summary.
- [docs/validation/GAPS_INVENTORY.md](docs/validation/GAPS_INVENTORY.md): known gaps.
- [CHANGELOG.md](CHANGELOG.md): notable changes.
- [CONTRIBUTING.md](CONTRIBUTING.md): repository conventions.

## Repository Layout

| Path | Purpose |
|---|---|
| `assets/` | Product assets, fonts, textures and reusable scenes |
| `docs/` | Documentation, validation summaries, audits, architecture and literature |
| `editor/` | Scenario editor implementation |
| `scenes/` | Godot entry scenes |
| `scripts/` | Official command-line entrypoints |
| `sim/` | Simulation models, core systems, templates and scientific validation |
| `tests/` | Python tests |
| `tools/` | Godot headless validators and technical utilities |
| `ui/` | HUD, localization and UI helpers |
| `view/` | 2D, 3D and first-person views |

## Validation Lanes

Product/editor lane:

```powershell
python scripts/check_product.py
```

Scientific guardrails lane:

```powershell
python scripts/simulation/validation_guardrails.py
```

Full scientific validation:

```powershell
powershell -ExecutionPolicy Bypass -File sim/validation/run_reference_checks.ps1 -TimeoutSeconds 900
```

## Known Limitations

- HVAC two-zone transport has accepted non-gating divergences against CFAST for selected upper-layer CO/CO2 checks.
- Ghanekar flashover empirical timing/height checks remain non-gating in the current documented validation state.
- HCN yield is conservative for well-ventilated combustion and can underestimate under-ventilated HCN.
- The zone model does not replace CFD tools such as FDS for high-rigor quantitative analysis.
- Two-Zone V1 remains opt-in through validation/runtime flags rather than the default global mode.

## Local Workspace

Generated outputs belong in ignored folders such as `runs/`, `graphs/`, `.godot_validation_logs/` or temporary directories. See [docs/RUN_WITHOUT_ARTIFACTS.md](docs/RUN_WITHOUT_ARTIFACTS.md) and [docs/LOCAL_WORKSPACE.md](docs/LOCAL_WORKSPACE.md).

Preview cleanup:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/clean_workspace.ps1 -WhatIf
```

## Engine

Godot 4.6.3 / GDScript · Windows-oriented tooling · Python 3.x for scripts and validation helpers.

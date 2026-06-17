# Large Files Inventory

This inventory tracks files that are likely to benefit from future extraction. It is intentionally documentation-only.

## Current Hotspots

| File | Approx. lines | Suggested action |
|---|---:|---|
| `editor/ScenarioEditor.gd` | 7,000+ | Extract tools, selection, property panel, drawing, stairs/floors, import/export |
| `view/fp/FirstPersonController.gd` | 3,400+ | Extract motion, HUD, opening interaction, world build, overlays |
| `sim/core/ThermalSystem.gd` | 3,300+ | Extract wall thermal helpers, plume/layer helpers, opening heat transfer |
| `sim/core/SimulationEngine.gd` | 2,900+ | Extract orchestration helpers, events, export/summary, setup |
| `view/3d/Visualizer3D.gd` | 2,900+ | Extract room shell, smoke, fire, furniture, selection/drag, camera |
| `sim/core/GasExchangeSystem.gd` | 2,200+ | Extract species movement, opening flow helpers, pressure/PPV |
| `sim/fire/CombustionSystem.gd` | 1,900+ | Extract yield resolution, object sync, ignition/pyrolysis helpers |
| `sim/templates/BuildingTemplate.gd` | 1,800+ | Split templates by building family or generator |
| `view/2d/Visualizer.gd` | 1,400+ | Extract room drawing, opening drawing, labels, furniture |
| `sim/validation/CaseRunner.gd` | 1,200+ | Extract metric collection and report writing |

## Thresholds

- Over 500 lines: watch for mixed responsibilities.
- Over 1,000 lines: prefer new helpers for new behavior.
- Over 2,000 lines: plan extraction before adding major features.

## Review Rule

If a change adds more than a small helper to one of these files, consider updating `docs/architecture/REFACTOR_PLAN.md` or extracting a focused collaborator first.

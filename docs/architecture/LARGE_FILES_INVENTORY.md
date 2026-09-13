# Large Files Inventory

This inventory tracks files that are likely to benefit from future extraction. It is intentionally documentation-only.

## Current Hotspots

Measured on 2026-09-10 with `wc -l`. The previous table dated from July and had
drifted badly: `FirstPersonController.gd` was listed at "3,400+" and is now
7,620 lines.

| File | Lines (2026-09-10) | Suggested action |
|---|---:|---|
| `editor/ScenarioEditor.gd` | 8,471 | Finding **D-1**, still open. Next cuts, by measured coupling: stairs (a home already exists in `StairPlanRules.gd`), the rest of detectors/victims, then openings. **Not** the 3D view: it is the most coupled block in the file (78 outward members), so moving it would make things worse. |
| `view/fp/FirstPersonController.gd` | 7,620 | Extract motion, HUD, opening interaction, world build, overlays |
| `sim/core/SimulationEngine.gd` | 5,418 | Extract orchestration helpers, events, export/summary, setup |
| `sim/core/ThermalSystem.gd` | 5,247 | Extract wall thermal helpers, plume/layer helpers, opening heat transfer |
| `sim/core/GasExchangeSystem.gd` | 4,514 | Extract species movement, opening flow helpers, pressure/PPV |
| `sim/fire/CombustionSystem.gd` | 3,699 | Extract yield resolution, object sync, ignition/pyrolysis helpers |
| `view/3d/Visualizer3D.gd` | 3,620 | Extract room shell, smoke, fire, furniture, selection/drag, camera |
| `sim/templates/BuildingTemplate.gd` | 1,976 | Split templates by building family or generator |
| `view/2d/Visualizer.gd` | 1,675 | Extract room drawing, opening drawing, labels, furniture |
| `sim/validation/CaseRunner.gd` | 1,411 | Extract metric collection and report writing |

Note on `ScenarioEditor.gd`: the problem is **width, not length** — 435 functions
and 144 state variables in one class, with only 2 functions over 100 lines.
Splitting it by "long functions" would not help. Four cuts on 2026-09-10 took it
from 8,739 to 8,471 lines and removed four duplicated concepts
(`EditorHandles.gd`, `CorridorLayout.gd`, `RoomMarkers.gd`, plus object geometry
into `PlanGeometry.gd`), but those were cuts of duplication, not of width. See
§17.9 and §19 of [../AUDITORIA_EDITOR_2026-09-06.md](../AUDITORIA_EDITOR_2026-09-06.md)
for the per-module breakdown and the measured coupling table that says where to
cut next.

## Thresholds

- Over 500 lines: watch for mixed responsibilities.
- Over 1,000 lines: prefer new helpers for new behavior.
- Over 2,000 lines: plan extraction before adding major features.

## Review Rule

If a change adds more than a small helper to one of these files, consider updating `docs/architecture/REFACTOR_PLAN.md` or extracting a focused collaborator first.

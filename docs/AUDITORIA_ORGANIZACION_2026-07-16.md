# Auditoría de organización y limpieza (todo excepto el motor)

**Fecha:** 2026-07-16 · **Alcance:** todo el repo salvo `sim/`, `tests/` del motor, `runs/`, `truth/`, `external/` y `docs/validation` (línea del motor en curso).

## Basura eliminada

| Qué | Por qué |
|---|---|
| `path/to/filename.js` | Commit accidental (placeholder de ejemplo commiteado como fichero real, commit `0c9aaa31`). |
| `scripts/Main.gd` + `.uid`, `scripts/Visualizer.gd` + `.uid` | Copias antiguas divergentes de `Main.gd` (raíz) y `view/2d/Visualizer.gd`. Sin ninguna referencia; fuente de confusión. |
| `tools/export_theme.gd.uid` | `.uid` huérfano (el script se renombró a `export_theme_tres.gd`). |
| `tools/tolerance_provenance.*.translation` ×12 + `tolerance_provenance.csv.import` | Godot importaba el CSV de tolerancias como "traducciones" y generaba 12 artefactos trackeados. |
| `docs/**/*.import` (6 trackeados + locales) | Godot importaba los PNG de `docs/literature` como texturas del juego; los `.import` cambiaban de mtime en cada arranque y ensuciaban `git status` constantemente (los `tmp_camscanner_*` que llevabas semanas viendo como modified). |
| `tools/run_all_r3.log` | Log local sin trackear. |

## Reubicaciones

- `tools/tolerance_provenance.csv`, `mutation_results.json`, `diag_fp_temp_jump.json` → **`tools/reports/`** (artefactos regenerables separados de los scripts; los generadores `audit_tolerance_provenance.py`, `credibility_report.py` y `mutation_audit.py` actualizados a la nueva ruta).

## Vallas nuevas contra la re-contaminación

- **`docs/.gdignore`** — Godot deja de escanear/importar todo `docs/` (nada del juego carga desde `res://docs`, verificado). Se acabó el churn de `.png.import`.
- **`tools/reports/.gdignore`** — los CSV/JSON de reports no vuelven a importarse como traducciones.
- **`runs/.gdignore` trackeado** — tu regla de `.gitignore` (`!runs/.gdignore`) ya lo preveía; el fichero existía pero sin añadir.
- **`.gitignore`**: `docs/**/*.import`, `tools/*.translation(.import)`, `tools/*.csv.import`, `.godot_validation_logs/`, `Docu Simufire/` (carpeta personal local).

## Organización resultante (no-motor)

```
Main.gd                    orquestador de SimulationScene (única .gd en raíz, requerida por la escena)
scenes/                    escenas raíz: MainMenu, SimulationScene, ScenarioEditorScene
ui/                        HUD, tema (.gd + SimuFireTheme.tres), ventanas y plantillas (.tscn junto a su script)
view/2d|3d|fp|furniture/   visores; escenas de componente junto a su dominio (FPHud, Legend3D)
view/geometry/             utilidades puras compartidas (StairGeometry)
editor/                    editor de escenarios (ScenarioEditor + EditorGrid)
assets/                    fonts, ui, smoke (spritesheets en uso), fp/furniture y fp/openings
scenarios/                 plantillas JSON de referencia
i18n/                      es_ui.json
scripts/                   herramientas Python de producto (check_product, gráficas, sweeps) + simulation/
tools/                     validadores Godot headless (validate_*.tscn/gd), sondas (probe_*), reports/ y archive/
docs/                      auditorías, planes, arquitectura, literatura, sesiones, validación (motor)
external/, truth/          datos de verdad CFAST/FDS (motor-adyacente, intacto)
```

## Revisado y deliberadamente NO tocado

- **`docs/COMMIT_PLAN.md`, `PR_DESCRIPTION.md`, `REPO_STATUS_AFTER_CLEANUP.md`, `LINK_AUDIT.md`** — artefactos one-shot candidatos a `docs/archive/`, pero están enlazados desde `HANDOFF_CURRENT_STATE.md`, que tienes modificado sin commitear en la línea del motor. Archivarlos rompería esos enlaces; hacerlo cuando el HANDOFF se actualice.
- **`docs/literature/tmp_*.png`** — nombre feo ("tmp") pero son escaneos referenciados por la literatura; con `docs/.gdignore` ya no generan ruido. Renombrar es opcional.
- **`assets/smoke/`** — en uso por `SmokePuffSpriteFactory`.
- **`tools/archive/root-scripts/tmp_*.py`** — archive intencional (regla `!tools/archive/**`).
- **`scripts/` vs `tools/`** — hay solape conceptual (Python en ambos); unificar sería un refactor de rutas invasivo con poco retorno. Convención actual: `scripts/` = producto/CI, `tools/` = validación Godot + análisis del motor.
- Todo `sim/`, `tests/`, `runs/`, `truth/`, `external/`, `docs/validation` — línea del motor.

## Verificación

- `scripts/check_docs_links.py`: PASS.
- `scripts/check_product.py`: 21 suites OK (persiste solo Reports freshness R2-1, propio del trabajo del motor en curso).

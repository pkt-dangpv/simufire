# Session handoff - SimuFire v0.5.0 E-04

**Date:** 2026-05-31  
**Branch:** `main`  
**Remote:** `origin` -> `https://github.com/pkt-dangpv/simufire.git`  
**Last known HEAD before this handoff:** `2dc1e33 feat(editor): v0.5.0 E-02 - runtime structural validation on load and run`

## Current project state

SimuFire is now framed as a **technical fire and gas simulator**, not a tactical videogame.

Out of active scope:

- water/hoselines
- PPV
- rescue gameplay
- victory/defeat
- tactical HUD

Rules for the next phase:

- Do not touch physics, tolerances, or baselines unless there is a critical bug.
- Do not reopen Phase 4A/4B.
- Anything implemented in code should also be visible/configurable/editable from Godot when it makes sense.
- Prefer `@export`, scenes, nodes, Resources, presets, and Inspector/UI configuration over hidden hardcoding.

## Stable validation state

- Scientific validation: `379/379 required PASS`
- Known gaps: `4`, all structural/non-gating HVAC CO/CO2 gaps
- Scientific guardrails: `ALL PASS`
- Product checks: `34/34 OK`

Useful commands:

```bash
python scripts/check_product.py
python scripts/simulation/validation_guardrails.py
python tests/test_guardrails.py
```

## Completed release/base work

- `v0.4.0-validation-rc1` is closed/published.
- `v0.4.1` is closed.
- `v0.5.0` is in progress.

Recent relevant commits:

```text
2dc1e33 feat(editor): v0.5.0 E-02 - runtime structural validation on load and run
63dec28 feat(product): v0.5.0 E-03 - product guardrails runner + docs two-tier check system
11a413e feat(editor): v0.5.0 E-02 - checklist y tests de flujo del editor
f64bcc1 feat(editor): v0.5.0 E-01 - error popup claro en carga fallida de escenario
14124fd docs: v0.5.0 - reframe as technical simulator; create ROADMAP_TECHNICAL_SIMULATOR_V0_5
98f8b86 docs: add PRODUCT_EDITOR_FP_3D_AUDIT - editor/FP/3D state, roadmap v0.5-v0.6
```

## v0.5.0 completed items

### E-01 - Load failure popup

- `ScenarioEditor.gd` adds a clear popup for failed scenario loading.
- `@export var load_error_dialog_title` is visible/editable in Godot Inspector.
- Runtime `AcceptDialog` named `LoadErrorDialog` is created/reused.
- Covers missing files and invalid/corrupt JSON.

### E-02 - Runtime template/scenario validation

- `ScenarioSerializer.gd` has:
  - `static func validate_scenario(data: Dictionary) -> Array`
- `ScenarioEditor.gd` calls `validate_scenario()` from:
  - `_load_from_path()`
  - `_load_scenario_pressed()`
  - `_run_simulation_pressed()`
- Invalid scenarios are blocked before assigning `editor_data = loaded`.
- Structural errors are shown through the E-01 popup.

Blocked invalid cases include:

- `height_m <= 0`
- missing `room_rect_m`
- invalid room rectangle width/height
- openings referencing missing rooms
- running a scenario with zero rooms

### E-03/E-03b - Product checks runner

- `scripts/check_product.py` exists.
- It runs:
  - editor/scenario JSON tests
  - guardrail script unit tests
- Final state: `34/34 product tests OK`.

## Docs already updated

- `README.md`
- `docs/ROADMAP_TECHNICAL_SIMULATOR_V0_5.md`
- `docs/ROADMAP_POST_V0_4_0.md`
- `docs/PRODUCT_EDITOR_FP_3D_AUDIT.md`
- `docs/EDITOR_FLOW_CHECKLIST.md`

## Next task

Implement **v0.5.0 E-04 - minimal safe decomposition of `ScenarioEditor.gd`**.

Objective:

Reduce the monolith without changing behavior. Extract one small, stable, low-risk responsibility.

Recommended extraction priority:

1. `EditorLoadErrorDialog` / load error helper
2. `EditorScenarioValidation` helper
3. `EditorStatusBar` helper

Selection criteria:

- Small diff in `ScenarioEditor.gd`.
- No complex geometry logic.
- E-01/E-02 behavior must remain identical.
- UI pieces should stay visible/configurable from Godot where practical.
- Avoid a broad refactor.

Suggested steps:

1. Check local state:
   ```bash
   git status --short --branch
   git log --oneline -8
   ```
2. Measure/inspect `ScenarioEditor.gd` around E-01/E-02 additions.
3. Choose the safest extraction.
4. Add a script in a coherent location, for example:
   - `sim/editor/EditorLoadErrorDialog.gd`
   - `sim/editor/EditorScenarioValidation.gd`
   - `sim/editor/EditorStatusBar.gd`
5. Integrate with `ScenarioEditor.gd` without restructuring the scene.
6. Update docs:
   - `docs/ROADMAP_TECHNICAL_SIMULATOR_V0_5.md`
   - `docs/EDITOR_FLOW_CHECKLIST.md` if the manual test steps change.
7. Run:
   ```bash
   python scripts/check_product.py
   python scripts/simulation/validation_guardrails.py
   ```

Closure criteria:

- `ScenarioEditor.gd` loses one concrete responsibility.
- E-01/E-02 still behave the same.
- Product checks stay OK.
- Scientific guardrails stay PASS.

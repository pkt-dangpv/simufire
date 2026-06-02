# ESTADO SESION - 2026-06-02

## Resumen

Sesion centrada en corregir el comportamiento de escaleras entre plantas:
- Las barandillas en FP y 3D estaban horizontales a altura fija; ahora siguen la pendiente real del tramo.
- Las escaleras de 180 grados se generaban en FP con hueco/losa de planta superior como si fueran rectas; ahora el recorte del hueco cubre la banda de los dos tramos.
- La vista 3D ya no dibuja una escalera recta cuando el modelo define `stair_turn_degrees >= 179`; genera dos tramos y descansillo.
- El hueco vertical amarillo del editor se alinea con la direccion y el tipo de escalera, en vez de ser un rectangulo centrado generico.

## Archivos modificados

- `view/fp/FirstPersonController.gd`
  - `_create_stairwell_upper_floor()` recibe `turn_degrees`.
  - Nuevo `_create_switchback_stairwell_upper_floor()` para dejar libre el hueco de escaleras 180 en FP.
  - Barandillas de tramo recto y 180 inclinadas con `rotation.x = -angle` y longitud real `sqrt(run^2 + rise^2)`.

- `view/3d/Visualizer3D.gd`
  - `_create_stair_visuals()` respeta `stair_turn_degrees`.
  - Nuevos helpers visuales para escaleras 180:
    - `_create_switchback_stair_visuals()`
    - `_create_stair_visual_flight_segment()`
  - Nuevo recorte visual de planta superior para escaleras 180:
    - `_create_switchback_stairwell_upper_floor_visual()`
  - Barandillas visuales inclinadas en rectas y 180.

- `editor/ScenarioEditor.gd`
  - `_vertical_opening_rect()` ahora calcula el rectangulo del hueco de escalera segun direccion y giro.

- `tools/validate_stairs_geometry.gd`
  - Nuevo validador headless para escaleras rectas y 180.
  - Instancia plantillas minimas PB/P1, reconstruye FP y 3D, comprueba hueco vertical, tramos, barandillas inclinadas, recorte de planta superior y clearance de cabeza por fisica.

- `tools/validate_stairs_geometry.tscn`
  - Escena minima para ejecutar el validador desde Godot headless.

- `scripts/check_product.py`
  - Integra el validador headless de escaleras como suite de producto.
  - Busca Godot por `GODOT_EXE`, rutas locales conocidas o `godot` en PATH.

## Verificacion ejecutada

```text
Godot 4.6.3 headless --quit-after 1
OK

Godot 4.6.3 headless res://tools/validate_stairs_geometry.tscn
STAIR GEOMETRY VALIDATION PASS

python scripts/check_product.py
ALL PRODUCT CHECKS PASS (35 tests)

python scripts/simulation/validation_guardrails.py
ALL GUARDRAILS PASS
Required checks: 379/379 PASS
Known gaps: 4
```

---

## Bloque W-05 - Internacionalizacion completa

Implementado:
- `i18n/es_ui.json` concentra las claves principales de UI en castellano para menu, editor, HUD y ventanas tecnicas.
- `ui/UILocalization.gd` carga el fichero de localizacion y ofrece helpers `t()` / `fmt()`.
- `MainMenu.gd`, `Main.gd`, `hud.gd`, `HUDPlaybackLabels.gd`, `HUDOpeningActionView.gd`, `HUDRoomSummary.gd` y `ScenarioEditor.gd` consumen claves localizadas.
- `ScenarioEditorScene.tscn`, `MainMenu.tscn` y `SimulationScene.tscn` ya no conservan textos visibles legacy como `Select`, `Room`, `Door`, `Window`, `Object`, `Ignite`, `Delete`, `Export runtime`, `TIME` o `2D PLAY`.
- `tests/test_ui_localization.py` valida el fichero de localizacion, claves requeridas y ausencia de textos UI ingleses residuales.
- `scripts/check_product.py` incluye el guardrail W-05; la suite de producto sube a 42 checks.

Verificacion ejecutada:
```text
python tests/test_ui_localization.py
Ran 4 tests
OK

python -m py_compile scripts/check_product.py tests/test_ui_localization.py
OK

python scripts/check_product.py
ALL PRODUCT CHECKS PASS (42 tests)

python scripts/simulation/validation_guardrails.py
ALL GUARDRAILS PASS
Required checks: 379/379 PASS
Known gaps: 4
```

## Estado Git

```text
HEAD: a7ce868 barandilla y escalera
Branch: main...origin/main
Working tree: cambios sin commit

Modificados:
- ESTADO_SESION_2026-06-02.md
- scripts/check_product.py

Nuevos:
- tools/validate_stairs_geometry.gd
- tools/validate_stairs_geometry.gd.uid
- tools/validate_stairs_geometry.tscn
```

No se ha creado commit en esta sesion.

## Validacion de cierre ejecutada

Validacion headless en Godot:
- Escalera recta entre PB y P1: rampa, peldaños, descansillo superior y hueco amarillo alineado.
- Escalera 180 entre PB y P1: dos tramos, descansillo, hueco vertical cubriendo la banda de ambos tramos.
- Barandillas FP y 3D: `rotation.x` inclinado en recta y 180.
- Clearance de cabeza: muestreo fisico en la trayectoria de subida sin obstrucciones.
- `python scripts/check_product.py` ahora ejecuta esta validacion automaticamente.

Pendiente opcional: una pasada visual interactiva en el editor de Godot si se quiere confirmar estetica/camara con ojo humano. A nivel estructural y de fisica headless, el caso queda validado.

---

## Bloque W-02 - Resumen tecnico post-simulacion

Implementado:
- `SimulationEngine.gd` mantiene picos tecnicos por sala: HRR, temperatura, CO upper, HCN upper, O2 minimo, visibilidad minima, FED maximo y SVV minimo.
- `summary.json` pasa a esquema `simufire_technical_summary_v1` con secciones `global`, `rooms`, `victims` y `detectors`.
- `Main.gd` muestra una ventana "Resumen tecnico post-simulacion" al generarse el export, con pestanas de salas, victimas, detectores y archivos.
- `tools/validate_technical_summary.gd` + `.tscn` validan el esquema y la escritura de `summary.json` en Godot headless.
- `scripts/check_product.py` incluye el guardrail W-02.

Verificacion ejecutada:
```text
python scripts/check_product.py
ALL PRODUCT CHECKS PASS (36 tests)

python scripts/simulation/validation_guardrails.py
ALL GUARDRAILS PASS
Required checks: 379/379 PASS
Known gaps: 4
```

## Bloque W-04 - Reproducibilidad completa

Implementado:
- `scripts/run_scenario.py` ejecuta un escenario JSON en Godot headless con un unico comando.
- `tools/run_scenario_headless.gd` + `.tscn` cargan templates runtime o casos de validacion con `template`, aplican `room_overrides`, `opening_overrides`, `engine_overrides`, `opening_events`, `suppression_events` y `targets`.
- `SimulationEngine.gd` expone `export_technical_results()` para generar export tecnico sin lanzar graficas ni depender de UI.
- Cada run escribe `summary.json`, `events.json`, `sim_log.txt`, `sim_log.csv` y `run_manifest.json`.
- `scripts/check_product.py` incluye un smoke end-to-end de `run_scenario.py`.
- `runs/` queda ignorado en git para salidas locales reproducibles.

Verificacion ejecutada:
```text
python scripts/run_scenario.py sim/validation/cases/victim_fed_incapacitation.json --duration 5 --out-dir runs/w04_smoke --timeout 90
RUN_SCENARIO PASS

python scripts/check_product.py
ALL PRODUCT CHECKS PASS (37 tests)

python scripts/simulation/validation_guardrails.py
ALL GUARDRAILS PASS
Required checks: 379/379 PASS
Known gaps: 4
```

---

## Correccion muebles editor/runtime

Problema detectado:
- En el editor 3D/FP, `Visualizer3D` recibia `set_state({})`; al no existir estado de simulacion, salia antes de crear `fuel_objects`.
- Al iniciar simulacion, `SimulationStateBuilder` no transportaba `visual_pose_locked`, asi que el visualizador podia volver a autocolocar muebles movidos en el editor.

Implementado:
- `FuelObjectModel.gd` conserva `visual_pose_locked`.
- `BuildingModel.gd` carga `visual_pose_locked` desde el runtime JSON.
- `SimulationStateBuilder.gd` exporta `visual_pose_locked` y `elevation_m` por objeto.
- `Visualizer3D.gd` crea un estado visual estatico desde `BuildingModel` cuando no hay estado de simulacion, cubriendo editor 3D y overlay FP.
- `tools/validate_furniture_runtime.gd` + `.tscn` validan round-trip editor -> runtime JSON -> BuildingModel -> Visualizer3D con `set_state({})`.
- `scripts/check_product.py` incluye el guardrail de muebles.

Verificacion ejecutada:
```text
Godot headless res://tools/validate_furniture_runtime.tscn
FURNITURE RUNTIME VALIDATION PASS

python scripts/check_product.py
ALL PRODUCT CHECKS PASS (38 tests)

python scripts/simulation/validation_guardrails.py
ALL GUARDRAILS PASS
Required checks: 379/379 PASS
Known gaps: 4
```

---

## Bloque W-03 - Escenarios predefinidos ampliados

Implementado:
- `scenarios/compact_apartment_reference.json`: piso compacto editable con salon-cocina, pasillo, dormitorio, bano y terraza/lavadero.
- `scenarios/long_hallway_reference.json`: vivienda con pasillo largo, sala origen, dormitorios remotos, cocina y recibidor para observar transporte de humo.
- `scenarios/two_storey_reference.json`: vivienda de dos plantas con escalera PB/P1, apertura vertical, dormitorios superiores y detectores por planta.
- Los muebles de los tres escenarios incluyen `visual_pose_locked` para que editor 3D, FP y runtime respeten la pose visual.
- README y roadmap v0.6 actualizados para reflejar los nuevos presets reproducibles.

Verificacion ejecutada:
```text
python tests/test_editor_scenarios.py
Ran 21 tests
OK

python scripts/run_scenario.py scenarios/compact_apartment_reference.json --duration 5 --out-dir runs/w03_compact --timeout 90
RUN_SCENARIO PASS

python scripts/run_scenario.py scenarios/long_hallway_reference.json --duration 5 --out-dir runs/w03_long_hallway --timeout 90
RUN_SCENARIO PASS

python scripts/run_scenario.py scenarios/two_storey_reference.json --duration 5 --out-dir runs/w03_two_storey --timeout 90
RUN_SCENARIO PASS

python scripts/check_product.py
ALL PRODUCT CHECKS PASS (38 tests)

python scripts/simulation/validation_guardrails.py
ALL GUARDRAILS PASS
Required checks: 379/379 PASS
Known gaps: 4
```

# Codex handoff - 2026-06-03

Este archivo resume el estado de la conversacion para poder continuar el trabajo en otro ordenador o en otra sesion de Codex.

## Estado git

- Rama: `main`
- Ultimo bloque tecnico guardado: `4e7b4bc Add 3D validation tools and FP detector alarm`
- Estado actual: `main` esta 1 commit por delante de `origin/main` y el working tree contiene el bloque no commiteado de editabilidad Godot (Editor/HUD/tests/docs).

## Validaciones recientes

Ultima validacion completa ejecutada tras cerrar guardrail de captura 3D, editabilidad Godot y huecos de escalera:

- `python scripts/check_product.py`
  - `ALL PRODUCT CHECKS PASS (57 tests)`
- `python scripts/simulation/validation_guardrails.py`
  - `Required checks 379/379 PASS`
  - `ALL GUARDRAILS PASS -- working tree listo.`
- `git diff --check`
  - sin errores; solo avisos CRLF en README/docs
- Revision de procesos Godot:
  - sin procesos Godot headless colgados

## Bloques cerrados en la conversacion

- DT-03: popup visible para errores de carga de escenario en editor.
  - Guardrail: `tools/validate_editor_load_error_dialog.tscn`
- Problema de mobiliario en FP:
  - `view/fp/FirstPersonController.gd` ahora crea `FirstPersonWorld/FPFurniture/FuelObjects_XX`
  - El mobiliario FP conserva pose, tamano, rotacion y estado desde snapshots runtime.
  - Guardrail ampliado: `tools/validate_furniture_runtime.gd`
- DT-06: fuego visible en FP.
  - Nodos `FPFire/Fire_XX`, llama/luz animada con `FireAnimation3D`, anclada a mueble activo.
  - Guardrail: `tools/validate_fp_fire_visuals.tscn`
- HUD tecnico FP:
  - Temperatura por postura, CO, CO2, O2, HCN, FED y visibilidad efectiva.
  - Guardrail: `tools/validate_fp_technical_hud.tscn`
- Estado visual de victimas en FP:
  - Color normal/incapacitada/fatal derivado de FED.
  - Guardrail: `tools/validate_fp_victim_states.tscn`
- Inicio FP restaurado desde editor:
  - `player_start` restaura posicion, planta y yaw.
  - Guardrail: `tools/validate_fp_player_start.tscn`
- `scripts/check_product.py` incluye ahora todos los guardrails nuevos y reporta 57 tests.
- `docs/PRODUCT_EDITOR_FP_3D_AUDIT.md` y `README.md` se actualizaron al estado 57/57.
- Alarma FP de detectores cerrada:
  - `FirstPersonController` crea `DetectorAlarm` (`AudioStreamPlayer3D`) con beep procedural por detector.
  - La alarma se activa con `triggered=true` solo si FP está activo y los detectores son visibles.
  - Guardrail: `tools/validate_fp_detector_alarm.tscn`.
- Puertas 3D orbitales cerradas:
  - `Visualizer3D` crea `DoorLeafPivot_XX` y `DoorLeaf_XX` para puertas no verticales.
  - La hoja rota segun `open_fraction`, `hinge_side` y `swing_direction`.
  - Guardrail: `tools/validate_3d_door_opening_visuals.tscn`.
- Overlays tecnicos 3D blindados:
  - Guardrail para gradiente de capa, heatmap de paredes, etiqueta FED y flags debug.
  - Guardrail: `tools/validate_3d_technical_overlays.tscn`.
- Captura 3D blindada:
  - Guardrail valida PNG real si el renderer headless expone textura; si no, valida fallo controlado sin archivo corrupto.
  - Guardrail: `tools/validate_3d_screenshot_export.tscn`.
- Editabilidad Godot blindada:
  - `ScenarioEditor` expone tipografia, layout de paneles/topbar y tolerancia de hover help en `Editor UI`.
  - `hud.gd` expone fuentes, margenes, separaciones y altura del panel compacto de aperturas en `HUD Layout`.
  - Guardrail: `tests/test_godot_editability.py`.
- Escaleras con hueco navegable:
  - `ScenarioEditor` añade selector `Tipo: Auto / Recta / 180°` en herramienta y propiedades; guarda `stair_turn_mode`.
  - El arrastre muestra ENTRADA -> SUBE, guia de peldaños y rectangulo real del hueco vertical.
  - `FirstPersonController` parte suelos y techos de salas solapadas alrededor del hueco vertical para que no quede una tapa bloqueando la subida.
  - `Visualizer3D` parte visualmente suelos superiores solapados y mantiene color termico/seleccion en las piezas.
  - Guardrail ampliado: `tools/validate_stairs_geometry.tscn`.

## Problema original del usuario

El usuario reporto que al editar una casa simple todo iba bien, pero al entrar en 3D o FP no se veian los muebles, y al iniciar simulacion los muebles movidos no salian bien. El trabajo reciente se centro en cerrar regresiones alrededor de:

- generacion de escenarios,
- editor 3D,
- FP,
- snapshots runtime de mobiliario,
- simulacion iniciada desde editor.

## Archivos clave para revisar

- `view/fp/FirstPersonController.gd`
- `tools/validate_furniture_runtime.gd`
- `tools/validate_stairs_geometry.gd`
- `tools/validate_3d_door_opening_visuals.gd`
- `tools/validate_3d_technical_overlays.gd`
- `tools/validate_3d_screenshot_export.gd`
- `tools/validate_fp_fire_visuals.gd`
- `tools/validate_fp_technical_hud.gd`
- `tools/validate_fp_victim_states.gd`
- `tools/validate_fp_player_start.gd`
- `tools/validate_fp_detector_alarm.gd`
- `tools/validate_editor_load_error_dialog.gd`
- `tests/test_godot_editability.py`
- `scripts/check_product.py`
- `docs/PRODUCT_EDITOR_FP_3D_AUDIT.md`

## Proximo bloque recomendado

El siguiente bloque tecnico logico es pasar a visualizacion interactiva/polish o a deuda de editor:

1. Hacer una pasada visual interactiva opcional de v0.5.2 en Godot/editor, verificando inspector editability en Editor/HUD/FP/3D, o continuar con refactor incremental del monolito de editor.
2. Ejecutar antes de cerrar cualquier commit nuevo:
   - `python scripts/check_product.py`
   - `python scripts/simulation/validation_guardrails.py`
   - `git diff --check`

## Como continuar en otro ordenador

1. Hacer pull:

   ```powershell
   git pull origin main
   ```

2. Leer este archivo:

   ```powershell
   Get-Content docs\CODEX_HANDOFF_2026-06-03.md
   ```

3. Pedirle a Codex:

   ```text
   Lee docs/CODEX_HANDOFF_2026-06-03.md y continua con el proximo bloque tecnico.
   ```

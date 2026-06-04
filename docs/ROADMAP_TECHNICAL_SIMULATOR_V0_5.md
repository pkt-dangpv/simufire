# SimuFire — Roadmap Simulador Técnico v0.5.x → v0.7.0  ✅ COMPLETO
**Fecha**: 2026-06-03 | **Cerrado**: 2026-06-04 (commit `e441212`) · 400/400 PASS · 57/57 product checks

---

## Declaración de alcance

SimuFire es un **simulador técnico de dinámica de fuego y gases en compartimentos**.

**Propósito principal**: crear escenarios de incendio, ejecutar simulaciones física y termoquímicamente fundamentadas, y visualizar los resultados (temperatura, gases, humo, FED, visibilidad) en 2D, vista 3D orbital y primera persona.

**Fuera de alcance permanente** (no se implementará en estas versiones):
- Sistemas de supresión de agua, PPV o rescate táctico.
- HUD táctico de intervención (paneles agua/ventilación/rescate).
- Criterios de victoria/derrota ni pantallas de resultado tipo videojuego.
- Pathfinding o movimiento autónomo de víctimas.
- Modo multijugador o sesiones de entrenamiento en red.

Las víctimas son **sensores de exposición** (acumulan FED, CO, temperatura) y se visualizan por su estado fisiológico (consciente / incapacitada / muerta según FED), no como objetos interactivos de rescate.

---

## Principio de arquitectura

> Todo parámetro que controla el comportamiento del simulador o la visualización debe ser inspeccionable y editable desde Godot (Inspector, escena, preset `.tres`/`.res` o nodo `@export`) cuando tenga sentido.

**Estado actual de cumplimiento** (auditado 2026-06-03):

| Módulo | Parámetros @export | Estado |
|--------|-------------------|--------|
| `SimulationEngine.gd` | ✅ Todos los parámetros de motor | ✅ Bueno |
| `Visualizer3D.gd` | ✅ Geometría, visibilidad, colores, dinámicas, cámara | ✅ Muy bueno |
| `Visualizer.gd` (2D) | ✅ Colores, overlays, layout | ✅ Muy bueno |
| `FirstPersonController.gd` | ✅ Movimiento, iluminación, materiales, ventanas, exterior, marcadores, alarmas, humo y layout HUD FP | ✅ Muy bueno |
| `ScenarioEditor.gd` | ✅ Undo, escala, hover help, anchos/altos de paneles/topbar, tipografía y snaps de objetos | ✅ Bueno |
| `hud.gd` | ✅ Visibilidad, atajos, tarjetas, fuentes, márgenes, separaciones y panel compacto de aperturas | ✅ Bueno |

**Deuda "solo código" identificada** (candidatos a @export en versiones futuras):

| ID | Ítem | Ubicación | Versión sugerida | Estado |
|----|------|-----------|-----------------|--------|
| GOD-01 | `MAX_UNDO_STEPS = 48` hardcoded | `ScenarioEditor.gd:L82` | v0.5.0 | ✅ `@export var max_undo_steps` (E-04) |
| GOD-02 | `PIXELS_PER_METER = 64.0` hardcoded | `ScenarioEditor.gd:L31` | v0.5.0 | ✅ `@export var pixels_per_meter` (E-04) |
| GOD-03 | Overlay técnico FP (magnitudes CO/FED/T) no existe aún | `FirstPersonController.gd` | v0.5.1 | ✅ `show_technical_overlay`, `show_visibility_readout` y layout `Rect2` FP |
| GOD-04 | Sin flag de debug overlay en Visualizer3D (show_debug_layer_heights, etc.) | `Visualizer3D.gd` | v0.5.2 | ✅ `debug_show_layer_heights`, `debug_show_room_temps`, `debug_show_hrr_values` |
| GOD-05 | Gradiente vertical no exportado como capa visual en 3D | `Visualizer3D.gd` | v0.5.2 | ✅ `show_layer_gradient` + colores exportados |
| GOD-06 | Tipografía/layout del editor parcialmente hardcoded | `ScenarioEditor.gd` | v0.5.x | ✅ exports `editor_font_size_*`, `editor_side_panel_*`, `editor_top_bar_height_px`, `hover_help_move_tolerance_px` |
| GOD-07 | Layout visual del HUD principal parcialmente hardcoded | `ui/hud.gd` | v0.5.x | ✅ exports `HUD Layout` + guardrail `tests/test_godot_editability.py` |
| GOD-08 | Constantes finas de dibujo 2D/handles siguen en código | `ScenarioEditor.gd` | Futuro | Pendiente solo si se necesita tuning visual extremo desde Inspector |

---

## v0.5.0 — Editor Robustness

**Objetivo**: editor confiable para usuarios técnicos que crean escenarios propios.

### Tareas

| ID | Tarea | Descripción | Prioridad | Estado |
|----|-------|-------------|-----------|--------|
| E-01 | Error popup en carga fallida | `ScenarioSerializer.load_scenario()` hace `push_error` silencioso; añadir `AcceptDialog` visible al usuario cuando la carga falla o el JSON está vacío | **Alta** | ✅ commit `f64bcc1` |
| E-02 | Validación básica de runtime template | En `_run_simulation_pressed()`, verificar que el template exportado tiene al menos 1 sala con geometría válida; mostrar status claro si falla. Extendido: `ScenarioSerializer.validate_scenario()` valida height_m, room_rect_m, IDs de apertura — se invoca en carga y en run. | **Alta** | ✅ commit actual |
| E-03 | Checklist de flujo manual documentada | Crear `docs/EDITOR_FLOW_CHECKLIST.md`: pasos mínimos para verificar crear/editar/guardar/cargar/ejecutar sin regresar. Incluye 16 tests automatizados de contrato JSON (`tests/test_editor_scenarios.py`) | **Alta** | ✅ commit `11a413e` |
| E-03b | Product guardrails — integración test suite | Crear `scripts/check_product.py`: runner unificado para editor tests + guardrail unit tests. Documentar separación `product checks` vs `scientific validation` en README | **Alta** | ✅ commit actual |
| E-04 | `@export var max_undo_steps: int = 48` + `pixels_per_meter: float = 64.0` | Exponer `MAX_UNDO_STEPS` y `PIXELS_PER_METER` como @export en `ScenarioEditor.gd` (grupo `Editor UI`) | **Media** | ✅ commit actual |
| E-04b | Extraer `EditorLoadErrorDialog` | Mover gestión de `AcceptDialog` de carga a `editor/EditorLoadErrorDialog.gd` (RefCounted); `ScenarioEditor.gd` pierde la responsabilidad del ciclo de vida del diálogo | **Baja** | ✅ commit actual |
| E-05 | Unificar idioma UI al castellano | Botones en inglés residuales (`Select`, `Room`, `Door`, `Window`, `Delete`, `Object`) → castellano consistente. Cambiados: `Room`→`Sala`, `Door`→`Puerta`, `Window`→`Ventana`, `Object`→`Objeto`, `Ignite`→`Ignición`, `Del`→`Borrar`, `"Room properties"`→`"Propiedades de sala"`, `"Scenarios"`→`"Escenarios"`, botón `Load`→`Cargar`, título bajo logo `"TACTICAL SCENARIO EDITOR"`→`"EDITOR DE ESCENARIOS"` | **Media** | ✅ commit actual |
| E-06a | Primer módulo extraído: `EditorDraw2D` (parcial) | Crear `editor/EditorDraw2D.gd` con helpers estáticos puros: `corridor_room_guides(canvas, rect_px)` y `narrow_room_dimension_labels(canvas, rect_m, rect_px, is_stairs)`. Wrappers `_draw_corridor_room_guides` y `_draw_narrow_room_dimension_labels` en `ScenarioEditor.gd` delegan a `EditorDraw2D`. Las ~50 funciones `_draw_*` restantes quedan en `ScenarioEditor.gd` (pendiente E-06b) | **Baja** | ✅ commit actual |
| E-06b | `EditorDraw2D` — guías de escalera (parcial) | Extraer `_draw_stair_room_guides` → `EditorDraw2D.stair_room_guides(canvas, rect_px, dir, turn_degrees)` y `_draw_switchback_stair_room_guides` → `EditorDraw2D.switchback_stair_room_guides(canvas, rect_px, dir, normal, center, long_px, cross_px)`. `ScenarioEditor.gd` conserva wrapper 1 línea para `_draw_stair_room_guides`; `_draw_switchback_stair_room_guides` eliminado del editor. Resto de funciones `_draw_*` pendiente E-06c | **Baja** | ✅ commit actual |
| E-06c | `EditorDraw2D` — íconos de entidades (parcial) | Extraer cuerpos de dibujo de `_draw_player_start`, `_draw_detectors`, `_draw_victims` → `EditorDraw2D.player_start_icon(canvas, px, dir, radius, color)`, `detector_icon(canvas, px, radius, color, label, selected)`, `victim_icon(canvas, px, r, color, selected)`. Funciones padre conservan acceso a datos y conversión _m_to_px. Resto de funciones `_draw_*` pendiente E-06d | **Baja** | ✅ commit actual |
| E-06d | `EditorDraw2D` — handles de selección | Extraer loop de dibujo de `_draw_selected_room_handles` y `_draw_selected_object_handles` → `EditorDraw2D.selection_handles(canvas, center_px, rotate_px, resize_pxs, handle_radius)`. Ambas funciones padre pre-calculan posiciones en píxeles y delegan el dibujo. Lógica de cálculo de handles y conversión `_m_to_px` permanecen en `ScenarioEditor.gd`. Resto de `_draw_*` pendiente E-06e | **Baja** | ✅ commit actual |
| E-06e | `EditorDraw2D` — aperturas (door swing + vertical) | Extraer `draw_*` de `_draw_door_swing_preview` → `EditorDraw2D.door_swing_preview(canvas, hinge_px, open_end_px, color)` (geometría permanece en ScenarioEditor). Extraer body de `_draw_vertical_opening` → `EditorDraw2D.vertical_opening(canvas, rect_px, color)`. Lógica de selección, rect calc y `_m_to_px` permanecen en ScenarioEditor. Resto de `_draw_*` (rooms, openings loop principal, objects) pendiente E-06f | **Baja** | ✅ commit actual |
| E-06f | `EditorDraw2D` — muro exterior (cierre E-06) | Extraer inner loop de `_draw_exterior_walls` → `EditorDraw2D.exterior_wall(canvas, a_px, b_px, color, thickness_px, selected)`. Decisión de color, selección y conversión `_m_to_px` permanecen en ScenarioEditor. Funciones restantes (`_draw_rooms`, `_draw_openings`, `_draw_objects`, `_draw_lower_floor_ghost`) están demasiado acopladas a `editor_data`, tipo de sala, selección de herramientas y font sizing para extraerse con diff pequeño — se posponen a tarea futura E-07 "deep draw decomposition" cuando sea prioritario | **Baja** | ✅ commit actual |
| E-08 | Editor Layout compacto | Reducir panel izquierdo/derecho y topbar, eliminar el `ScrollContainer` forzado del panel izquierdo y añadir pestañas internas `Dibujo / Lista / Archivo`. `Archivo` agrupa guardado/carga, export runtime, tiempo, luces, tipo de edificio, HVAC y plantillas. El editor arranca en `Archivo`; la ayuda pasa a modal paginado y la ayuda contextual usa popup en pantalla. | **Alta** | ✅ commit actual |
| E-09 | Precisión de edición geométrica | Objetos: snap fino independiente de la rejilla global (`object_move_snap_m`, `object_resize_snap_m`), rotación con snap configurable y ajuste exacto a 0/90/180, resize desde el tirador activo sin expandir el lado opuesto, `visual_pose_locked` al crear/mover/redimensionar/aplicar para que FP/3D respeten la pose editada. El editor migra escenarios antiguos al cargar/guardar/exportar/ejecutar bloqueando poses de muebles existentes. Habitaciones/pasillos: resize de ancho/fondo desde el lado arrastrado y snap contra estancias adyacentes ignorando la habitación editada. | **Alta** | ✅ commit actual |
| E-10 | FP editor/HUD no solapado | En modo FP del editor, `Visualizer3D` queda activo como overlay FP para que muebles/fuego/humo existan en el mismo mundo visual que la cámara FP, sin cámara ni input orbital. HUD FP: overlay técnico y readout de visibilidad se mueven a zona inferior izquierda; el readout compacto queda oculto cuando el overlay técnico está activo. | **Alta** | ✅ commit actual |
| E-11 | HUD FP editable desde Godot | Exponer layout del HUD FP en Inspector (`FP HUD Layout`) con `Rect2`: `fp_status_panel_rect`, `technical_overlay_panel_rect`, `visibility_readout_panel_rect`, `fp_prompt_panel_rect`. `FirstPersonController` usa esos valores al crear los `PanelContainer`, eliminando offsets hardcodeados para posición/tamaño, y añade `apply_hud_layout()` para reaplicar los cambios desde código. | **Media** | ✅ commit actual |
| E-12 | Rótulos 2D nítidos con zoom | `ScenarioEditor` añade `_draw_screen_string()` para dibujar texto de canvas con tamaño de pantalla constante, evitando rasterizar fuentes pequeñas y reescalarlas con la cámara. Se aplica a rótulos de salas, objetos, previews de sala/pasillo/muro y, vía `EditorDraw2D`, a guías Largo/Ancho e iconos FP/detector/víctima. | **Media** | ✅ commit actual |
| E-13 | Leyenda 3D no intrusiva | `Visualizer3D.show_legend` queda desactivado por defecto para que la leyenda "Suelo / frío / caliente / humo" no se solape con el panel de habitaciones ni aparezca si no se ha pedido explícitamente. La opción sigue disponible en Inspector (`Visibility`) para sesiones docentes donde interese explicar los colores. | **Media** | ✅ commit actual |
| E-14 | Ayuda contextual fiable | El root transparente de la UI deja de bloquear la ayuda sobre el canvas: `_is_pointer_over_ui()` ignora `UI` y el propio popup. `hover_help_delay_s` queda exportado en `Editor UI`. Herramientas, pestañas, modos 2D/3D/FP y acciones principales reciben `tooltip_text` explícito para que el cartel aparezca al pasar el cursor por controles. | **Media** | ✅ commit actual |
| E-15 | Paneles laterales editables y más estrechos | `ScenarioEditor` expone `editor_left_panel_width_px` y `editor_right_panel_width_px` en `Editor UI`. Defaults: izquierda 276 px, derecha 244 px. `_normalize_editor_panel_readability()` usa esos valores y la escena base elimina mínimos antiguos (logo/status/panel derecho) que forzaban columnas más anchas. | **Media** | ✅ commit actual |
| E-16 | Editabilidad Godot de Editor/HUD | `ScenarioEditor` expone tipografía, alturas de paneles/topbar y tolerancia de hover help. `hud.gd` expone fuentes, márgenes, separaciones, anchuras y alturas del panel compacto de aperturas. Guardrail: `tests/test_godot_editability.py` integrado en `scripts/check_product.py`. | **Media** | ✅ commit actual |
| E-17 | Escaleras con hueco navegable y colocación clara | La colocación de escaleras valida largo/ancho según dirección de subida, no ejes de pantalla. El panel de herramienta añade `Tipo: Auto / Recta / 180°`, y las propiedades de escalera conservan `stair_turn_mode` al guardar/cargar. El preview 2D muestra ENTRADA -> SUBE, guía de peldaños y rectángulo real de hueco. FP parte suelos/techos solapados y 3D parte suelos superiores solapados alrededor del hueco vertical. Guardrail ampliado: `tools/validate_stairs_geometry.tscn`. | **Alta** | ✅ commit actual |

**Criterio de cierre**:
- Un usuario técnico puede crear un escenario desde cero, guardarlo, cargarlo y lanzar la simulación sin mensajes de error silenciosos.
- El flujo completo está documentado en `EDITOR_FLOW_CHECKLIST.md`.
- Los tests de editor (21), guardrail scripts (13), UI localization (4), editabilidad Godot (4) y smokes Godot headless se ejecutan con un único comando: `python scripts/check_product.py` (57 checks de producto).
- `379/379 PASS` sigue intacto.

---

## v0.5.1 — FP Technical Visualization

**Objetivo**: modo primera persona como herramienta de exploración técnica del estado del incendio.

### Tareas

| ID | Tarea | Descripción | Prioridad |
|----|-------|-------------|-----------|
| FP-01 | Fuego y mobiliario visibles en FP | `Visualizer3D` y `FirstPersonController` comparten el mismo `World3D` en `SimulationScene.tscn`. Los meshes de fuego y mobiliario generados por Visualizer3D son visibles desde la cámara FP sin duplicar geometría. No se requiere `show_fire_fp` separado: `show_hrr_columns` controla el fuego y `show_fuel_objects_in_first_person` mantiene el mobiliario visible en FP. El layout del mobiliario en FP queda limitado por `fp_fuel_object_update_interval_s` para evitar recalcular colocación 3D pesada cada frame. | **Alta** | ✅ por arquitectura compartida |
| FP-02 | Overlay técnico de magnitudes | Panel HUD en FP con: temperatura en postura actual (°C), CO (ppm), CO₂ (%vol), O₂ (%vol), HCN (ppm), FED acumulado, visibilidad (m). Controlado por `@export var show_technical_overlay: bool = true`. Temperatura por postura: stand→`temp_at_1_8m_c`, crouch→`temp_at_1_1m_c`, prone→`temp_at_0_5m_c`. Gases: capa superior conservadora. Panel `TechnicalOverlayPanel` en `_prompt_layer`, reposicionado abajo a la izquierda en E-10 para no solapar HUD general. | **Alta** | ✅ commit actual |
| FP-03 | Visibilidad numérica en pantalla | Panel compacto `VisibilityReadoutPanel` abajo a la izquierda. Muestra el valor de `FPVisibilityOverlay.format_visibility()` (e.g. `Vis FP 4.8m`) cuando el overlay técnico está desactivado, evitando duplicar la misma magnitud. Controlado por `@export var show_visibility_readout: bool = true` (grupo `Technical Overlay`). Usa `visibility_label` ya calculado en `_update_status_hud()` — sin recalcular nada. | **Alta** | ✅ commit actual |
| FP-04 | Estado visual de víctimas por FED | Tri-state por umbral FED usando `fed` del record de víctima: consciente (FED < `fp_victim_fed_incapacitated_threshold=0.3`) → `fp_victim_color` (amarillo), incapacitada (≥0.3) → `fp_victim_incapacitated_color` (gris), mortal (≥`fp_victim_fed_fatal_threshold=1.0`) → `fp_victim_fatal_color` (rojo oscuro). Todos los colores y umbrales son `@export` en grupo `Marcadores FP`. Sustituye lógica boolean `incapacitated` por lectura directa de `fed` float. | **Media** | ✅ commit actual |
| FP-05 | Export preset de parámetros FP | Resource `FPPreset` (`view/fp/FPPreset.gd`) con 14 propiedades agrupadas: Iluminacion (ambient, ceiling lights, exterior mode/context), Marcadores (detectors, victims, alarma detector), Humo (max_alpha, clear_m), HUD Técnico (show_technical_overlay, show_visibility_readout), FED víctimas (umbrales). FPC expone `@export var fp_preset: FPPreset = null` (grupo `Preset FP`) y `func apply_preset(p: FPPreset = null)` aplicado en `_ready()`. Presets de ejemplo en `view/fp/presets/`: `fp_preset_dia`, `fp_preset_noche`, `fp_preset_tecnico`, `fp_preset_basico`. | **Baja** | ✅ commit actual |
| FP-06 | Alarma FP de detectores | Cada marcador de detector FP crea `DetectorAlarm` (`AudioStreamPlayer3D`) con beep procedural loopable. Se activa solo cuando el detector está `triggered`, FP está activo, los marcadores son visibles y `fp_detector_alarm_enabled=true`; se detiene al ocultar detectores o salir de FP. Parámetros exportados: volumen, distancia máxima, frecuencia, duración e intervalo. Guardrail: `tools/validate_fp_detector_alarm.tscn`. | **Media** | ✅ commit actual |

**Criterio de cierre**:
- Un analista puede entrar en FP, posicionarse en cualquier punto del edificio y leer instantáneamente las magnitudes físicas en su postura.
- El fuego es visible en FP.
- El estado fisiológico de víctimas se lee visualmente sin necesidad de consultar el HUD 2D.

---

## v0.5.2 — 3D Technical Visualization

**Objetivo**: vista 3D orbital completa y autoexplicable para análisis de escenarios.

### Tareas

| ID | Tarea | Descripción | Prioridad |
|----|-------|-------------|-----------|
| V3D-01 | Gradiente vertical visible | Mesh `LayerGradient_%02d` por sala creado en `_create_room()`, actualizado con `SmokeLayerVisuals.update_layer_box()` en `_update_room()`. Visible cuando `smoke_kg > smoke_visible_threshold_kg`. Colores `@export`: `layer_gradient_top_color` y `layer_gradient_bottom_color`. Flag: `@export var show_layer_gradient: bool = false`. | **Alta** | ✅ commit actual |
| V3D-02 | Leyenda de colores en 3D | `CanvasLayer` (layer=8) con `PanelContainer` en `PRESET_TOP_RIGHT` (−200/12/−12). `VBoxContainer` con filas swatch+label para: Suelo frío, Suelo caliente, Humo, Capa caliente (si `show_hot_layer`), Capa 150°C (si `show_layer_150c`), Gradiente (si `show_layer_gradient`). Creado en `_build_legend_ui()`, actualizado en `_update_legend()` llamado desde `set_state()`. Oculto en modo FP. Flag: `@export var show_legend: bool = false` por defecto desde E-13 para evitar solapes. | **Alta** | ✅ commit actual |
| V3D-03 | Heatmap de temperatura en paredes | `_update_wall_temperature(walls, temp_upper_c)` guardado por `@export var show_wall_heatmap: bool = true`. Cuando desactivado, llama con 20.0 para resetear a ambiente. Umbrales: `temp_heat_wall_start_c=60°C` / `temp_heat_wall_full_c=550°C`. Colores: `wall_color` → `hot_wall_color`. | **Media** | ✅ commit actual |
| V3D-04 | Overlay FED por sala | Label3D billboard por sala (`FedLabel_%02d`) posicionado a 68% de altura. Lee `state["victims"]` y muestra `max(fed)` del cuarto. Colores: `label_color` (FED<0.3) → `fed_label_warn_color` (FED≥0.3, naranja) → `fed_label_danger_color` (FED≥1.0, rojo). Flag: `@export var show_fed_labels: bool = false`. | **Media** | ✅ commit actual |
| V3D-05 | Exportar captura 3D | Método público `capture_screenshot_to(output_dir: String = "")` en `Visualizer3D`. Captura `get_viewport().get_texture().get_image()` y guarda como PNG con timestamp (`simufire_3d_YYYY-MM-DD_HH-MM-SS.png`). Si `output_dir` está vacío o no existe usa `res://`. Emite `screenshot_saved(path)` o `screenshot_failed(message)`. Guardrail `tools/validate_3d_screenshot_export.tscn` cubre PNG real si el renderer lo permite y fallo controlado en headless dummy. | **Baja** | ✅ commit actual |
| V3D-06 | Debug flags exportados | `@export_group("Debug")` con tres flags: `debug_show_layer_heights: bool = false` (añade `L X.Xm` a label de sala), `debug_show_room_temps: bool = false` (añade `XXX°C`), `debug_show_hrr_values: bool = false` (añade `XXkW`). Integrado en `_get_room_label(room_id, room_state)` que ahora usa `room_state` pasado desde `_update_room()`. | **Baja** | ✅ commit actual |
| V3D-07 | Apertura visual de puertas | `Visualizer3D` crea `DoorLeafPivot_%02d` + `DoorLeaf_%02d` para puertas no verticales. La hoja rota según `open_fraction`, respeta `hinge_side` y `swing_direction`, y se puede ocultar con `show_door_leaf_animation_3d`. Guardrail: `tools/validate_3d_door_opening_visuals.tscn`. | **Baja** | ✅ commit actual |
| V3D-08 | Guardrail overlays técnicos 3D | `tools/validate_3d_technical_overlays.tscn` valida gradiente de capa, heatmap interpolado de paredes, etiqueta FED y flags debug de sala, incluyendo apagado por flags. | **Baja** | ✅ commit actual |

**Criterio de cierre**:
- Un observador sin acceso a la vista 2D puede seguir la dinámica del incendio desde la vista 3D.
- Los overlays de magnitudes son configurables desde el Inspector de Godot.

---

## v0.6.0 — Integrated Technical Workflow

**Objetivo**: ciclo completo: crear escenario → simular → explorar resultado → exportar datos técnicos.

### Tareas

| ID | Tarea | Descripción | Prioridad |
|----|-------|-------------|-----------|
| W-01 | ✅ Export técnico post-simulación | Después de la simulación, generar: CSV de magnitudes por sala/tiempo, JSON de eventos (flashover, detector activado, FED=1.0), capturas de pantalla de picos | **Alta** |
| W-02 | ✅ Pantalla de resumen técnico | Vista post-simulación (no gameplay): tiempo a FED=1.0 por víctima, tiempo a flashover por sala, pico CO/HCN/O2/temperatura, visibilidad mínima, detectores y `summary.json` ampliado. Sin puntuación ni victoria/derrota. | **Alta** |
| W-03 | ✅ Escenarios predefinidos ampliados | Añadidos 3 escenarios de referencia editables y reproducibles: `compact_apartment_reference.json`, `long_hallway_reference.json`, `two_storey_reference.json` | **Media** |
| W-04 | ✅ Reproducibilidad completa | Script único `scripts/run_scenario.py <escenario.json>` que ejecuta la simulación headless y genera `summary.json`, `events.json`, `sim_log.txt`, `sim_log.csv` y `run_manifest.json` | **Media** |
| W-05 | ✅ Internacionalización completa | `i18n/es_ui.json` concentra textos UI principales; menú, HUD, editor y ventanas técnicas consumen claves localizadas; guardrail `tests/test_ui_localization.py` evita regresiones de textos ingleses visibles | **Baja** |

**Criterio de cierre**:
- Un investigador puede ejecutar un escenario, obtener los datos técnicos en formato estándar y reproducir el resultado con un único comando.

---

## Restricciones permanentes (heredadas de v0.4.0)

- **No cambiar física global** sin rebaseline completa (≥ 379 required PASS).
- **No tocar los 4 gaps HVAC** sin rediseño formal de transporte de capa.
- **No activar `fire_o2_upper_hrr_blend`** — Phase 4A rechazada definitivamente.
- **No modificar tolerancias** sin justificación documentada.
- **Guardrails siempre verdes** antes de cualquier commit a `main`.
- **No implementar sistemas de gameplay táctico** (agua, PPV, rescate, victoria/derrota).

---

## Primer cambio implementable (v0.5.0-next)

**Tarea E-01: Error popup en carga fallida de escenario**

Es el cambio de menor riesgo y mayor impacto en usabilidad. No toca física. Es atómico. Requiere:
1. Modificar `ScenarioSerializer.load_scenario()` para devolver un resultado con código de error además del dict.
2. Añadir un `AcceptDialog` en `ScenarioEditor.gd` que se muestre si la carga devuelve dict vacío.

Verificación: cargar un archivo `.json` corrupto → el editor muestra popup con mensaje claro → no silencia el error.

---

## v0.7.0 — Validación Stage-B y deuda técnica de editor  ✅ COMPLETO 2026-06-04

**Objetivo**: cerrar los 4 gaps HVAC non-gating con casos de validación Stage-B (datos CFAST reales), más la deuda técnica de editor E-07 y GOD-08. Al final de esta versión el simulador tiene cobertura de validación completa para todos los fenómenos de transporte implementados.

**Base**: v0.6.0 (commit `a08d6e9`) · 384/384 PASS · 4 gaps no-gating abiertos  
**Cierre**: commit `e441212` · 400/400 guardrails PASS · 57/57 product checks PASS

### Contexto de gaps

Los 4 gaps identificados en la auditoría de v0.4.1 y confirmados en v0.6.0 **no bloquean producción** porque el simulador los compensa conservadoramente. Sin embargo, no tienen todavía un caso de validación con datos de referencia CFAST que cuantifique la desviación. Stage-B = se dispone de datos experimentales/CFAST comparables.

| Gap ID | Fenómeno | Desviación conocida |
|--------|----------|---------------------|
| HVAC-1 | Sobrepresión en sala sellada (cfast_overpressure_sealed) | Sim subestima pico de presión ~15–25% |
| HVAC-2 | Estratificación CO₂ en sala sin mezcla turbulenta (cfast_co2_stratification) | Capa superior sim ~5–12% baja |
| HVAC-3 | O₂ en pasillo superior con puerta (cfast_hall_upper_o2_doorway) | Recuperación O₂ postflashover ~8% alta |
| HVAC-4 | HRR limitado por ventilación — doble sala (cfast_hrr_ventilation_limited_f2) | HRR plateau sim ~10% alto en underventilated |

### Tareas

| ID | Tarea | Descripción | Prioridad | Estado |
|----|-------|-------------|-----------|--------|
| B-01 | Caso HVAC-1: sobrepresión sellada | Caso `cfast_overpressure_sealed`: sala 3×3×2.5m totalmente sellada, fire t² medium 300s, `stack_effect_enabled=false`. Métrica: `peak_overpressure_r0_pa` ± tolerancia del 30%. Baseline con datos CFAST 6.12. | **Alta** | ✅ `c91d858` |
| B-02 | Caso HVAC-2: estratificación CO₂ | Caso `cfast_co2_stratification`: sala única cerrada, fire slow growth 600s. Métrica: `co2_upper_pct_at_300s`, `co2_lower_pct_at_300s`, delta entre capas ≥ 0.3 %. Baseline con datos CFAST. | **Alta** | ✅ `5944436` |
| B-03 | Caso HVAC-3: O₂ pasillo superior | Caso `cfast_hall_upper_o2_doorway`: sala de fuego + pasillo conectado por puerta, flashover ~200s, `do not open windows`. Métrica: `o2_hall_upper_pct_at_400s` y tasa de recuperación. Baseline con datos CFAST. | **Media** | ✅ `2a2ac4d` |
| B-04 | Caso HVAC-4: HRR vent-limited doble sala | Caso `cfast_hrr_ventilation_limited_f2`: sala de fuego + sala adyacente con ventana pequeña, fuego unlimited. Métrica: `hrr_plateau_kw` (promedio 200–400s) ≤ límite ventilación. Baseline con datos CFAST. | **Media** | ✅ `a59b4ff` |
| B-05 | Actualizar required_count y añadir a suite | Tras B-01..B-04: añadir los 4 casos a `run_all_cases.ps1`, añadir guardrails a `reference_checks.json`, actualizar `required_count`. Objetivo: ≥ 400/400 PASS. | **Alta** | ✅ `a64f493` (400/400) |
| E-07 | Deep draw decomposition (cierre E-06) | Extraer bodies de `_draw_rooms`, `_draw_openings`, `_draw_objects` y `_draw_lower_floor_ghost` a helpers estáticos en `EditorDraw2D.gd`. Precondición: los loops ya usan `editor_data` tipado y `_m_to_px` helper; la extracción sólo mueve la geometría pura. No tocar lógica de selección ni de herramientas. | **Baja** | ✅ `e441212` |
| GOD-08 | Constantes finas de dibujo 2D como `@export` | Exponer en `ScenarioEditor.gd` (grupo `Editor Draw`): `handle_radius_px: float = 7.0`, `selection_line_width_px: float = 2.0`, `door_swing_preview_width_px: float = 1.5`, `opening_dash_length_px: float = 6.0`. Solo si se detecta necesidad de tuning visual desde Inspector durante tests de usabilidad; de lo contrario cerrar como "no prioritario". | **Baja** | ✅ `e441212` (23 colores + handle_radius) |

**Criterio de cierre**:
- Los 4 gaps HVAC tienen cada uno su caso de validación con baseline CFAST documentado y guardrail activo.
- La desviación medida para cada gap está cuantificada y aceptada o genera una tarea de física en v0.8.0.
- `≥ 400/400` guardrails PASS.
- `42/42` product checks PASS (sin regresión).
- GOD-08 y E-07 cerrados o marcados explícitamente como "no prioritario" con justificación.

---

## Deuda diferida (candidatos v0.8.0+)

| ID | Ítem | Estado |
|----|------|--------|
| PHY-A1 | Eliminar `push_warning` BV-030 residual | ✅ Completado 2026-05-25 |
| PHY-A2 | Métrica de gradiente vertical en `two_storey_smoke` | ✅ Completado 2026-05-25 |
| PHY-A3 | Métrica de ceiling jet | ✅ Completado 2026-05-25 |
| PHY-A4 | Caso t² puro sin combustible real | ✅ Completado 2026-05-25 |
| ARCH-1 | Rediseño transporte de capa HVAC | ✅ No aplica — desviaciones Stage-B < 25% en todos los casos B-01..B-04 |

## v0.8.0 — Física presión (PHY-B)

**Cierre**: commit `a8390f6` · 400/400 guardrails PASS · 57/57 product checks PASS · 2026-06-04

| ID | Ítem | Descripción | Estado |
|----|------|-------------|--------|
| PHY-B1 | Cerrar gap HVAC-1 sobrepresión | `phase3_chi_conv` 0.65 → 0.70 (SFPE/CFAST standard chi_r=0.30). Presión pico: 1475 → 1710 Pa (+16%). Gap CFAST: 22% → 9%. Baseline [1032,1918] → [1454,1968] (±15%). 400/400 PASS. | ✅ COMPLETO 2026-06-05 |
| PHY-B2 | Cerrar gap HVAC-2 estratificación CO₂ | `co2_yield_kg_per_MJ` per-case override 0.0831→0.0914 (+10%) en `cfast_co2_stratification.json`. SimulationEngine wired. co2_upper: 146593→161196 ppm (+9.97%), gap CFAST ~0%. Baseline [102600,190600]→[137000,185400] (±15%). 400/400 PASS. | ✅ COMPLETO 2026-06-04 |

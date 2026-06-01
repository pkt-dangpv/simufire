# SimuFire — Roadmap Simulador Técnico v0.5.x
**Fecha**: 2026-05-31 | **Base**: v0.4.1 (commit 7b24f68) · 379/379 PASS · 4 gaps no-gating

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

**Estado actual de cumplimiento** (auditado 2026-05-31):

| Módulo | Parámetros @export | Estado |
|--------|-------------------|--------|
| `SimulationEngine.gd` | ✅ Todos los parámetros de motor | ✅ Bueno |
| `Visualizer3D.gd` | ✅ Geometría, visibilidad, colores, dinámicas, cámara | ✅ Muy bueno |
| `Visualizer.gd` (2D) | ✅ Colores, overlays, layout | ✅ Muy bueno |
| `FirstPersonController.gd` | ✅ Movimiento, iluminación, materiales, ventanas, exterior, marcadores, humo | ✅ Muy bueno |
| `ScenarioEditor.gd` | ✅ Parámetros de editor expuestos | ✅ Bueno |
| `hud.gd` | ✅ Opciones visuales de HUD | ✅ Bueno |

**Deuda "solo código" identificada** (candidatos a @export en versiones futuras):

| ID | Ítem | Ubicación | Versión sugerida |
|----|------|-----------|-----------------|
| GOD-01 | `MAX_UNDO_STEPS = 48` hardcoded | `ScenarioEditor.gd:L82` | v0.5.0 | ✅ `@export var max_undo_steps` (E-04) |
| GOD-02 | `PIXELS_PER_METER = 64.0` hardcoded | `ScenarioEditor.gd:L31` | v0.5.0 | ✅ `@export var pixels_per_meter` (E-04) |
| GOD-03 | Overlay técnico FP (magnitudes CO/FED/T) no existe aún | `FirstPersonController.gd` | v0.5.1 |
| GOD-04 | Sin flag de debug overlay en Visualizer3D (show_debug_layer_heights, etc.) | `Visualizer3D.gd` | v0.5.2 |
| GOD-05 | Gradiente vertical no exportado como capa visual en 3D | `Visualizer3D.gd` | v0.5.2 |

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
| E-05 | Unificar idioma UI al castellano | Botones en inglés residuales (`Select`, `Room`, `Door`, `Window`, `Delete`, `Object`) → castellano consistente. Cambiados: `Room`→`Sala`, `Door`→`Puerta`, `Window`→`Ventana`, `Object`→`Objeto`, `Ignite`→`Ignición`, `Del`→`Borrar`, `"Room properties"`→`"Propiedades de sala"`, `"Scenarios"`→`"Escenarios"`, botón `Load`→`Cargar`, título `"TACTICAL SCENARIO EDITOR"`→`"EDITOR DE ESCENARIOS TÉCNICO"` | **Media** | ✅ commit actual |
| E-06a | Primer módulo extraído: `EditorDraw2D` (parcial) | Crear `editor/EditorDraw2D.gd` con helpers estáticos puros: `corridor_room_guides(canvas, rect_px)` y `narrow_room_dimension_labels(canvas, rect_m, rect_px, is_stairs)`. Wrappers `_draw_corridor_room_guides` y `_draw_narrow_room_dimension_labels` en `ScenarioEditor.gd` delegan a `EditorDraw2D`. Las ~50 funciones `_draw_*` restantes quedan en `ScenarioEditor.gd` (pendiente E-06b) | **Baja** | ✅ commit actual |
| E-06b | `EditorDraw2D` — guías de escalera (parcial) | Extraer `_draw_stair_room_guides` → `EditorDraw2D.stair_room_guides(canvas, rect_px, dir, turn_degrees)` y `_draw_switchback_stair_room_guides` → `EditorDraw2D.switchback_stair_room_guides(canvas, rect_px, dir, normal, center, long_px, cross_px)`. `ScenarioEditor.gd` conserva wrapper 1 línea para `_draw_stair_room_guides`; `_draw_switchback_stair_room_guides` eliminado del editor. Resto de funciones `_draw_*` pendiente E-06c | **Baja** | ✅ commit actual |
| E-06c | `EditorDraw2D` — íconos de entidades (parcial) | Extraer cuerpos de dibujo de `_draw_player_start`, `_draw_detectors`, `_draw_victims` → `EditorDraw2D.player_start_icon(canvas, px, dir, radius, color)`, `detector_icon(canvas, px, radius, color, label, selected)`, `victim_icon(canvas, px, r, color, selected)`. Funciones padre conservan acceso a datos y conversión _m_to_px. Resto de funciones `_draw_*` pendiente E-06d | **Baja** | ✅ commit actual |
| E-06d | `EditorDraw2D` — handles de selección | Extraer loop de dibujo de `_draw_selected_room_handles` y `_draw_selected_object_handles` → `EditorDraw2D.selection_handles(canvas, center_px, rotate_px, resize_pxs, handle_radius)`. Ambas funciones padre pre-calculan posiciones en píxeles y delegan el dibujo. Lógica de cálculo de handles y conversión `_m_to_px` permanecen en `ScenarioEditor.gd`. Resto de `_draw_*` pendiente E-06e | **Baja** | ✅ commit actual |
| E-06e | `EditorDraw2D` — aperturas (door swing + vertical) | Extraer `draw_*` de `_draw_door_swing_preview` → `EditorDraw2D.door_swing_preview(canvas, hinge_px, open_end_px, color)` (geometría permanece en ScenarioEditor). Extraer body de `_draw_vertical_opening` → `EditorDraw2D.vertical_opening(canvas, rect_px, color)`. Lógica de selección, rect calc y `_m_to_px` permanecen en ScenarioEditor. Resto de `_draw_*` (rooms, openings loop principal, objects) pendiente E-06f | **Baja** | ✅ commit actual |
| E-06f | `EditorDraw2D` — muro exterior (cierre E-06) | Extraer inner loop de `_draw_exterior_walls` → `EditorDraw2D.exterior_wall(canvas, a_px, b_px, color, thickness_px, selected)`. Decisión de color, selección y conversión `_m_to_px` permanecen en ScenarioEditor. Funciones restantes (`_draw_rooms`, `_draw_openings`, `_draw_objects`, `_draw_lower_floor_ghost`) están demasiado acopladas a `editor_data`, tipo de sala, selección de herramientas y font sizing para extraerse con diff pequeño — se posponen a tarea futura E-07 "deep draw decomposition" cuando sea prioritario | **Baja** | ✅ commit actual |

**Criterio de cierre**:
- Un usuario técnico puede crear un escenario desde cero, guardarlo, cargarlo y lanzar la simulación sin mensajes de error silenciosos.
- El flujo completo está documentado en `EDITOR_FLOW_CHECKLIST.md`.
- Los tests de editor (21) y guardrail scripts (13) se ejecutan con un único comando: `python scripts/check_product.py`.
- `379/379 PASS` sigue intacto.

---

## v0.5.1 — FP Technical Visualization

**Objetivo**: modo primera persona como herramienta de exploración técnica del estado del incendio.

### Tareas

| ID | Tarea | Descripción | Prioridad |
|----|-------|-------------|-----------|
| FP-01 | Fuego visible en FP | `Visualizer3D` y `FirstPersonController` comparten el mismo `World3D` en `SimulationScene.tscn`. Los meshes de fuego generados por Visualizer3D son visibles desde la cámara FP sin código adicional. No se requiere `show_fire_fp` separado: `show_hrr_columns` en Visualizer3D controla ambas vistas. | **Alta** | ✅ por arquitectura compartida |
| FP-02 | Overlay técnico de magnitudes | Panel HUD en FP con: temperatura en postura actual (°C), CO (ppm), CO₂ (%vol), O₂ (%vol), HCN (ppm), FED acumulado, visibilidad (m). Controlado por `@export var show_technical_overlay: bool = true`. Temperatura por postura: stand→`temp_at_1_8m_c`, crouch→`temp_at_1_1m_c`, prone→`temp_at_0_5m_c`. Gases: capa superior conservadora. Panel `TechnicalOverlayPanel` en `_prompt_layer`, esquina superior izquierda. | **Alta** | ✅ commit actual |
| FP-03 | Visibilidad numérica en pantalla | Mostrar los metros de visión efectiva en FP como número junto al overlay de opacidad existente | **Alta** |
| FP-04 | Estado visual de víctimas por FED | Cambiar color/postura del marcador de víctima en función del umbral FED (consciente / incapacitada ≥ 0.3 / mortal ≥ 1.0). Los valores umbral son `@export`. Sin gameplay. | **Media** |
| FP-05 | Export preset de parámetros FP | Guardar la configuración FP actual como `.tres` Resource para poder intercambiar entre perfiles (día/noche, interior/exterior, técnico/básico) | **Baja** |

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
| V3D-01 | Gradiente vertical visible | Mostrar la interfaz capa superior/inferior como bandas de color con altura de capa de humo. Nuevo `@export var show_layer_gradient: bool = false` | **Alta** |
| V3D-02 | Leyenda de colores en 3D | Panel superpuesto en la vista 3D que muestre la escala de colores activa (temperatura, CO, humo). Controlado por `@export var show_legend: bool = true` | **Alta** |
| V3D-03 | Heatmap de temperatura en paredes | Interpolar el color de la pared entre `wall_color` y `hot_wall_color` usando la temperatura media de la sala, visible desde el Inspector (umbral configurable) | **Media** |
| V3D-04 | Overlay FED por sala | Label 3D adicional mostrando FED acumulado de cada sala (víctima más expuesta). `@export var show_fed_labels: bool = false` | **Media** |
| V3D-05 | Exportar captura 3D | Botón en HUD para guardar `viewport.get_texture()` como PNG al directorio de gráficas activo | **Baja** |
| V3D-06 | Debug flags exportados | Añadir grupo `@export_group("Debug")` con: `show_layer_heights_3d`, `show_pressure_arrows`, `show_opening_flow_vectors` | **Baja** |

**Criterio de cierre**:
- Un observador sin acceso a la vista 2D puede seguir la dinámica del incendio desde la vista 3D.
- Los overlays de magnitudes son configurables desde el Inspector de Godot.

---

## v0.6.0 — Integrated Technical Workflow

**Objetivo**: ciclo completo: crear escenario → simular → explorar resultado → exportar datos técnicos.

### Tareas

| ID | Tarea | Descripción | Prioridad |
|----|-------|-------------|-----------|
| W-01 | Export técnico post-simulación | Después de la simulación, generar: CSV de magnitudes por sala/tiempo, JSON de eventos (flashover, detector activado, FED=1.0), capturas de pantalla de picos | **Alta** |
| W-02 | Pantalla de resumen técnico | Vista post-simulación (no gameplay): tiempo a FED=1.0 por víctima, tiempo a flashover por sala, pico CO/HCN, temperatura máxima. Sin puntuación ni victoria/derrota. | **Alta** |
| W-03 | Escenarios predefinidos ampliados | Añadir 2-3 escenarios de referencia calibrados: piso compacto, pasillo largo, edificio 2 plantas | **Media** |
| W-04 | Reproducibilidad completa | Script único `scripts/run_scenario.py <escenario.json>` que ejecuta la simulación headless y genera el export técnico | **Media** |
| W-05 | Internacionalización completa | Todas las cadenas UI en castellano en archivos de localización | **Baja** |

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
